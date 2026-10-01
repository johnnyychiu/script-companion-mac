"""0.5.3 layout tests: Chromium renderer; simulated storage/native messages.
No macOS, WKWebView, or PowerPoint execution. Run with Python + Playwright + Chromium.
"""
from pathlib import Path
from datetime import datetime, timezone
import copy, json, os
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]
HTML=(R/'Source/reader.html').read_text()
SEED=json.loads((R/'Demo/Preview demo.script.json').read_text())
checks=[];errors=[];requests=[]
def check(name,value):
    assert value,name
    checks.append({'test':name,'result':'PASS'})
    print('PASS',name,flush=True)
with sync_playwright() as pw:
    browser=pw.chromium.launch(headless=True,executable_path=os.environ.get('CHROMIUM_EXECUTABLE'),args=['--no-sandbox'])
    ctx=browser.new_context(viewport={'width':1180,'height':760},locale='en-GB',timezone_id='Europe/London')
    ctx.set_offline(True)
    def page(native=False):
        p=ctx.new_page();p.set_default_timeout(2500)
        p.on('pageerror',lambda e:errors.append(str(e)))
        p.on('request',lambda r:requests.append(r.url) if r.url.startswith(('http:','https:')) else None)
        p.clock.install(time=datetime(2026,9,16,13,30,tzinfo=timezone.utc))
        p.evaluate('''seed=>{Object.defineProperty(window,'localStorage',{value:{data:{'scriptCompanion.v1':JSON.stringify(seed)},getItem(k){return this.data[k]??null},setItem(k,v){this.data[k]=String(v)},removeItem(k){delete this.data[k]}}});}''',SEED)
        if native:p.evaluate('window.nativeMessages=[];window.webkit={messageHandlers:{companion:{postMessage:m=>nativeMessages.push(m)}}};')
        p.set_content(HTML)
        if native:p.evaluate("Companion.receive({type:'ready'})")
        p.clock.run_for(60)
        return p
    p=page()
    def diag(p=p):return p.evaluate('Companion.diagnostics()')
    def key(k,p=p):
        p.locator('#reader').focus();p.keyboard.press(k);p.clock.run_for(60)
    def inset(p=p):
        return p.locator('.current').bounding_box()['y']-p.locator('#reader').bounding_box()['y']
    check('No slide heading remains inside the notes area',p.locator('.readarea .slidehead').count()==0)
    check('Slide heading is beside the snapshot in the lower session panel',p.locator('.console .session-panel #slideTitle').count()==1)
    check('Notes area starts at the first content pixel',p.locator('#reader').bounding_box()['y']==0)
    check('Restored highlighted line starts 4 pixels from content top',abs(inset()-4)<1)
    check('Full slide title remains in a hover tooltip',p.locator('#slideTitle').get_attribute('title')==p.locator('#slideTitle').inner_text())
    src=p.locator('#slidePreview').get_attribute('src')
    line=diag()['line'];key('ArrowRight');key('ArrowLeft')
    check('Accidental slide change restores the line and preview',diag()['line']==line and p.locator('#slidePreview').get_attribute('src')==src)
    check('Returning line keeps the 4-pixel top inset',abs(inset()-4)<1)
    key('ArrowDown');check('Next line is also aligned at 4 pixels',abs(inset()-4)<1)
    key('Home');check('First line has no extra blank spacer',abs(inset()-4)<1)
    key('End');check('Last line can reach the same top position',abs(inset()-4)<1)
    p.locator('#timerToggleBtn').click();p.clock.run_for(3250)
    check('Presentation timer still counts',diag()['timerRunning'] and diag()['elapsedMs']>=3200)
    key('p');check('Hidden snapshot does not hide the relocated slide identity',not p.locator('#previewPane').is_visible() and p.locator('#slideTitle').is_visible())
    key('p');check('Showing the snapshot does not move notes downward',abs(inset()-4)<1)
    p.locator('#resetAllLinesBtn').click();p.locator('#confirmResetLinesBtn').click();p.clock.run_for(60)
    check('Reset-all leaves a running timer untouched',diag()['timerRunning'] and diag()['elapsedMs']>=3200)
    check('Reset-all returns current line to top without changing the slide',diag()['line']==0 and diag()['slide']==2 and abs(inset()-4)<1)
    key('ArrowRight');check('Reset-all still resets other slides too',diag()['line']==0)
    key('ArrowLeft')
    for width,height in [(1180,760),(920,700),(660,540),(520,700),(390,844)]:
        p.set_viewport_size({'width':width,'height':height});p.clock.run_for(80)
        for compact in [False,True]:
            if p.locator('#app').evaluate('e=>e.classList.contains("compact")')!=compact:p.locator('#compactBtn').click()
            key('End');p.clock.run_for(60)
            p.evaluate('document.querySelector("footer").scrollTop=0')
            tag=f'{width}x{height} {"compact" if compact else "normal"}'
            check(f'{tag}: notes have no top header or spacer',p.locator('#reader').bounding_box()['y']==0 and abs(inset()-4)<1)
            check(f'{tag}: metadata below notes and above timer',p.locator('#slideTitle').bounding_box()['y']>=p.locator('#reader').bounding_box()['height'] and p.locator('#slideTitle').bounding_box()['y']<p.locator('#elapsedTime').bounding_box()['y'])
            check(f'{tag}: no horizontal overflow',p.evaluate('document.documentElement.scrollWidth<=innerWidth'))
            check(f'{tag}: reader retains at least 160 pixels height',p.locator('#reader').bounding_box()['height']>=160)
    # Open settings and large fonts must not insert anything above the notes.
    p.set_viewport_size({'width':1180,'height':760});p.clock.run_for(60)
    p.evaluate('document.getElementById("settingsPanel").open=true')
    p.locator('#biggerBtn').click();p.clock.run_for(60)
    check('Opening setup and increasing text retain top alignment',p.locator('#reader').bounding_box()['y']==0 and abs(inset()-4)<1)
    p.locator('#smallerBtn').click()
    p.evaluate('document.getElementById("settingsPanel").open=false')
    # Normal and compact browser screenshots (not native Mac desktop captures).
    if p.locator('#app').evaluate('e=>e.classList.contains("compact")'):p.locator('#compactBtn').click()
    key('Home');key('ArrowDown');key('ArrowDown');key('ArrowDown')
    p.locator('#timerToggleBtn').click();p.clock.run_for(60)
    p.evaluate('document.querySelector("footer").scrollTop=0');p.screenshot(path=str(R/'Tests/notes_at_top.png'))
    p.set_viewport_size({'width':660,'height':540});p.locator('#compactBtn').click();p.clock.run_for(80)
    p.evaluate('document.querySelector("footer").scrollTop=0');p.screenshot(path=str(R/'Tests/notes_at_top_compact.png'))
    # Live packets update the relocated identity without moving the script viewport.
    n=page(native=True)
    n.evaluate("Companion.receive({type:'linked',name:'Test.pptx',identity:'/test/Test.pptx'})")
    rows=[{'number':i,'id':str(255+i),'title':f'Live slide {i}','notes':'First thought.\nSecond thought.\nThird thought.','notesOK':True} for i in range(1,4)]
    def send(i):
        n.evaluate('e=>Companion.receive(e)',{'type':'slide','name':'Test.pptx','identity':'/test/Test.pptx','number':i,'total':3,'current':rows[i-1],'slides':rows})
        n.clock.run_for(60)
    send(1);key('ArrowDown',n);send(2)
    check('Live slide packet updates the relocated title and count',n.locator('#slideTitle').inner_text()=='Live slide 2' and '2 / 3' in n.locator('#slideEyebrow').inner_text())
    send(1)
    check('Live return restores line memory at the upper edge',diag(n)['line']==1 and abs(inset(n)-4)<1)
    n.evaluate('nativeMessages.length=0');key('ArrowDown',n)
    check('Line movement sends no PowerPoint slide request',n.evaluate('!nativeMessages.some(m=>m.type==="powerPointStep")'))
    check('No JavaScript exceptions',not errors)
    check('No external requests',not requests)
    (R/'Tests/notes_at_top_results.json').write_text(json.dumps({'environment':'Offline Linux Chromium; virtual clock; mocked storage and native transport; not macOS or PowerPoint','checks':checks},indent=2))
    print(f'{len(checks)} notes-at-top checks passed.',flush=True)
    ctx.close();browser.close()
