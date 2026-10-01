"""0.5.1 reset-all tests on bundled HTML; native responses/storage simulated.
This does not build macOS code or drive a real PowerPoint installation.
"""
from pathlib import Path
import json, os, copy, datetime
from playwright.sync_api import sync_playwright
R = Path(__file__).resolve().parents[1]
HTML = (R/'Source/reader.html').read_text()
SEED = json.loads((R/'Demo/Preview demo.script.json').read_text())
SEED.update(slide=1, line=3, timer={'elapsedMs':65000, 'slides':{'demo|id:257':1000}})
SEED['linePositions']['id:256']={'line':2,'text':SEED['deckSlides'][0]['lines'][2]}
SEED['linePositions']['id:removed']={'line':9,'text':'Stale removed slide.'}
checks=[]; errors=[]; requests=[]
def check(label, condition):
    assert condition, label
    checks.append({'test':label,'result':'PASS'}); print('PASS',label,flush=True)
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path=os.environ.get('CHROMIUM_EXECUTABLE'),headless=True,args=['--no-sandbox'])
    ctx=b.new_context(viewport={'width':1180,'height':850},locale='en-GB',timezone_id='Europe/London')
    ctx.set_offline(True)
    def page(state=None,native=False,stored=None):
        p=ctx.new_page();p.set_default_timeout(3500)
        p.on('pageerror',lambda err:errors.append(str(err)))
        p.on('request',lambda req:requests.append(req.url) if req.url.startswith(('http://','https://')) else None)
        p.clock.install(time=datetime.datetime(2026,9,16,9,0,tzinfo=datetime.timezone.utc))
        p.evaluate("Object.defineProperty(window,'localStorage',{value:{data:{},getItem(k){return this.data[k]??null},setItem(k,v){this.data[k]=String(v)},removeItem(k){delete this.data[k]}}});")
        if stored:p.evaluate('s=>Object.assign(localStorage.data,s)',stored)
        elif state:p.evaluate('s=>localStorage.setItem("scriptCompanion.v1",JSON.stringify(s))',state)
        if native:p.evaluate('window.nativeMessages=[];window.webkit={messageHandlers:{companion:{postMessage:m=>nativeMessages.push(m)}}};')
        p.set_content(HTML)
        if native:p.evaluate("Companion.receive({type:'ready'})")
        p.clock.run_for(50)
        return p
    diag=lambda p:p.evaluate('Companion.diagnostics()')
    saved=lambda p:json.loads(p.evaluate('localStorage.getItem("scriptCompanion.v1")'))
    def open_reset(p):p.locator('#resetAllLinesBtn').click()
    def reset(p):
        open_reset(p);p.locator('#confirmResetLinesBtn').click();p.clock.run_for(400)
    p=page(SEED);initial=diag(p)
    check('Starts on slide 2, line 4 with positions on other slides',initial['slide']==2 and initial['line']==3 and initial['linePositions']['id:256']['line']==2)
    check('New reset button visible below line controls',p.locator('#resetAllLinesBtn').is_visible() and p.locator('#resetAllLinesBtn').bounding_box()['y']>p.locator('#nextLineBtn').bounding_box()['y'])
    open_reset(p)
    check('Confirmation identifies all three slides',p.locator('#resetLinesDialog').is_visible() and '3 slides' in p.locator('#resetLinesCount').inner_text())
    check('Cancel initially focused to avoid accidental reset',p.evaluate('document.activeElement.id')=='cancelResetLinesBtn')
    p.keyboard.press('ArrowDown');p.keyboard.press('ArrowRight')
    check('Line/slide keys do not navigate behind confirmation',diag(p)['line']==3 and diag(p)['slide']==2)
    p.locator('#cancelResetLinesBtn').click();p.clock.run_for(30)
    check('Cancel preserves all positions',diag(p)['linePositions']==initial['linePositions'] and diag(p)['line']==3)
    open_reset(p);p.keyboard.press('Escape');p.clock.run_for(30)
    check('Escape closes without reset',not p.locator('#resetLinesDialog').is_visible() and diag(p)['line']==3)
    p.locator('#restartLineBtn').click();p.clock.run_for(400)
    check('Existing single-slide button still leaves other slides alone',diag(p)['line']==0 and diag(p)['linePositions']['id:256']['line']==2)
    p.locator('#reader').focus();p.keyboard.press('ArrowDown');p.keyboard.press('ArrowDown')
    before=copy.deepcopy(saved(p));timer_before=diag(p)['elapsedMs'];image_before=p.locator('#slidePreview').get_attribute('src')
    reset(p);after=diag(p)
    check('Confirmed reset keeps current slide and highlights line 1',after['slide']==2 and after['line']==0 and p.locator('.current').count()==1)
    check('All slides, not only the visible one, are zeroed',len(after['linePositions'])==3 and all(v['line']==0 for v in after['linePositions'].values()))
    check('Stale IDs are discarded','id:removed' not in after['linePositions'])
    check('Paused total and per-slide timing unchanged',after['elapsedMs']==timer_before and saved(p)['timer']==before['timer'])
    check('Notes and all snapshot data unchanged',saved(p)['raw']==before['raw'] and saved(p)['deckSlides']==before['deckSlides'] and saved(p)['previews']==before['previews'])
    check('Current image unchanged',p.locator('#slidePreview').get_attribute('src')==image_before)
    check('Confirmation returns focus to notes',p.evaluate('document.activeElement.id')=='reader')
    check('Accessible confirmation feedback is shown','All 3 slides reset to line 1' in p.locator('#resetLinesFeedback').inner_text())
    check('Persisted current and other slide positions are reset',saved(p)['line']==0 and all(v['line']==0 for v in saved(p)['linePositions'].values()))
    p.keyboard.press('ArrowLeft');check('Previous slide returns to first line',diag(p)['slide']==1 and diag(p)['line']==0)
    p.keyboard.press('ArrowRight');p.keyboard.press('ArrowRight');check('Forward slide also returns to first line',diag(p)['slide']==3 and diag(p)['line']==0)
    p.keyboard.press('ArrowDown');p.keyboard.press('ArrowLeft');p.keyboard.press('ArrowRight')
    check('Normal per-slide memory resumes after reset',diag(p)['slide']==3 and diag(p)['line']==1)
    reset(p)
    reopened=page(stored=p.evaluate('({...localStorage.data})'))
    check('Reopening restored state keeps every reset position',diag(reopened)['line']==0 and diag(reopened)['slide']==3 and all(v['line']==0 for v in diag(reopened)['linePositions'].values()))
    with p.expect_download() as dl:p.locator('#backupBtn').click()
    dl.value.save_as(str(R/'Tests/reset_all_backup.json'))
    exported=json.loads((R/'Tests/reset_all_backup.json').read_text())
    check('JSON backup includes reset positions',exported['line']==0 and all(v['line']==0 for v in exported['linePositions'].values()))
    p.locator('#timerToggleBtn').click();p.clock.run_for(3200);elapsed=diag(p)['elapsedMs']
    reset(p);p.clock.run_for(1200)
    check('Running timer is not paused or reset',diag(p)['timerRunning'] and diag(p)['elapsedMs']>=elapsed+1500)
    # Static script numbers, single/empty slides.
    plain=page();plain.locator('#reader').focus();plain.keyboard.press('End');plain.keyboard.press('ArrowRight');plain.keyboard.press('End');reset(plain)
    check('Number-keyed manual scripts reset all positions',all(k.startswith('number:') and v['line']==0 for k,v in diag(plain)['linePositions'].items()))
    empty=copy.deepcopy(SEED);empty.update(slide=0,line=0);empty['deckSlides'][0]['lines']=[]
    q=page(empty);reset(q)
    check('Empty-note slide stays empty without fabricated line',diag(q)['line']==0 and q.locator('.current').count()==0 and q.locator('#lineInfo').inner_text()=='No notes')
    q.locator('#reader').focus();q.keyboard.press('ArrowRight');check('Other slides reset when current slide has no notes',diag(q)['line']==0)
    one=copy.deepcopy(SEED);one['deckSlides']=one['deckSlides'][:1];one.update(slide=0,line=2)
    onep=page(one);reset(onep);check('Single-slide presentation is handled',diag(onep)['line']==0 and 'Slide reset to line 1' in onep.locator('#resetLinesFeedback').inner_text())
    # Native transport simulation: no slide-control request may be emitted.
    n=page(native=True)
    send=lambda event:n.evaluate('e=>Companion.receive(e)',event)
    rows=[{'number':i+1,'id':s['id'],'title':s['title'],'notes':'\n'.join(s['lines']),'notesOK':True} for i,s in enumerate(SEED['deckSlides'])]
    full=lambda i:{'type':'slide','name':'Rehearsal.pptx','identity':'/local/Rehearsal.pptx','number':i,'total':3,'current':rows[i-1],'slides':rows}
    fast=lambda i:{'type':'slide','name':'Rehearsal.pptx','identity':'/local/Rehearsal.pptx','number':i,'total':3,'slideID':rows[i-1]['id'],'positionOnly':True,'navigationAvailable':True}
    send({'type':'linked','name':'Rehearsal.pptx','identity':'/local/Rehearsal.pptx'});send(full(1))
    n.locator('#reader').focus();n.keyboard.press('End');send(fast(2));n.locator('#reader').focus();n.keyboard.press('End');n.locator('#timerToggleBtn').click();n.clock.run_for(2000)
    send({'type':'arrowMode','enabled':True});n.evaluate('nativeMessages.length=0');reset(n)
    check('Linked reset keeps current slide, connection and key mode',diag(n)['following'] and diag(n)['slide']==2 and diag(n)['line']==0 and diag(n)['arrowMode'])
    check('Linked reset emits no PowerPoint navigation or unlink commands',n.evaluate('!nativeMessages.some(m=>["powerPointStep","link","unlink","refreshNotes","configureSlideButtons","disableArrowMode"].includes(m.type))'))
    check('Linked reset persists all positions through native saveState',n.evaluate('nativeMessages.some(m=>m.type==="saveState"&&m.state.line===0&&Object.values(m.state.linePositions).every(v=>v.line===0))'))
    check('Native interaction reports modal to suspend line capture',n.evaluate('nativeMessages.some(m=>m.type==="interaction"&&m.blocked===true)'))
    send(full(2));send(fast(1));check('Full notes refresh and sparse return do not restore old positions',diag(n)['slide']==1 and diag(n)['line']==0)
    send(fast(3));check('Previously unvisited linked slide starts at line 1',diag(n)['line']==0)
    send({'type':'busy'});check('Reset unavailable while a native transaction is busy',n.locator('#resetAllLinesBtn').is_disabled())
    send({'type':'navigationResult','ok':True});open_reset(n);send({'type':'busy'});n.locator('#confirmResetLinesBtn').click()
    check('Confirmation cannot reset during an in-progress transaction',n.locator('#resetLinesDialog').is_visible() and 'still updating' in n.locator('#resetLinesError').inner_text())
    send({'type':'navigationResult','ok':True});n.locator('#confirmResetLinesBtn').click();n.clock.run_for(400)
    check('Confirmation succeeds when operation finishes',not n.locator('#resetLinesDialog').is_visible() and diag(n)['line']==0)
    open_reset(n)
    changed=copy.deepcopy(rows);changed[0]['id']='different-slide-id'
    send({**full(3),'slides':changed})
    n.locator('#confirmResetLinesBtn').click()
    check('Changed deck is not reset under stale confirmation',n.locator('#confirmResetLinesBtn').is_disabled() and 'presentation changed' in n.locator('#resetLinesError').inner_text())
    n.locator('#cancelResetLinesBtn').click();n.clock.run_for(20)
    # Real reader DOM and bundled images; screenshots are browser demos.
    view=page(SEED)
    for width,height in [(1180,850),(920,700),(660,540),(520,700),(390,844)]:
        view.set_viewport_size({'width':width,'height':height});view.clock.run_for(60)
        check(f'No horizontal overflow at {width}',view.evaluate('document.documentElement.scrollWidth<=innerWidth'))
        check(f'Notes remain above reset and preview at {width}',view.locator('#reader').bounding_box()['y']<view.locator('#resetAllLinesBtn').bounding_box()['y'] and view.locator('#reader').bounding_box()['y']<view.locator('#previewPane').bounding_box()['y'])
        check(f'Reset can be opened and cancelled at {width}',view.locator('#resetAllLinesBtn').is_visible())
        open_reset(view);view.locator('#cancelResetLinesBtn').click();view.clock.run_for(30)
    view.set_viewport_size({'width':1180,'height':850});view.evaluate('document.querySelector("footer").scrollTop=0');view.clock.run_for(60)
    view.screenshot(path=str(R/'Tests/reset_all_layout.png'))
    open_reset(view);view.screenshot(path=str(R/'Tests/reset_all_confirmation.png'));view.locator('#cancelResetLinesBtn').click();view.clock.run_for(30)
    view.set_viewport_size({'width':660,'height':540});view.locator('#compactBtn').click();view.evaluate('document.querySelector("footer").scrollTop=0');view.clock.run_for(60)
    check('Compact mode retains reset button',view.locator('#resetAllLinesBtn').is_visible())
    view.screenshot(path=str(R/'Tests/reset_all_compact.png'))
    check('No JavaScript exceptions',not errors)
    check('No external requests',not requests)
    b.close()
(R/'Tests/reset_all_results.json').write_text(json.dumps({'environment':'Offline Linux Chromium; mocked storage; virtual time; native packets simulated','checks':checks},indent=2))
print(len(checks),'reset-all checks passed.',flush=True)
