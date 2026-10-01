"""0.5 regression (ignore background autosave/focus messages when checking action order): real reader UI, simulated native responses. NOT PowerPoint."""
from pathlib import Path
import os, json
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]
checks=[]
def check(name, ok):
    assert ok, name
    checks.append({'test':name,'result':'PASS'}); print('PASS',name,flush=True)
with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path=os.getenv('CHROMIUM_EXECUTABLE'),headless=True,args=['--no-sandbox'])
    context=browser.new_context(viewport={'width':1180,'height':850});context.set_offline(True)
    page=context.new_page();errors=[];requests=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('request',lambda r:requests.append(r.url) if r.url.startswith(('http://','https://')) else None)
    page.on('dialog',lambda d:d.accept())
    page.evaluate("Object.defineProperty(window,'localStorage',{value:{getItem(){return null},setItem(){}}});window.nativeMessages=[];window.webkit={messageHandlers:{companion:{postMessage:m=>nativeMessages.push(m)}}};")
    page.set_content((R/'Source/reader.html').read_text())
    page.evaluate("document.getElementById('settingsPanel').open=true")
    send=lambda e:page.evaluate('e=>Companion.receive(e)',e)
    d=lambda:page.evaluate('Companion.diagnostics()')
    rows=[{'number':i,'id':str(255+i),'title':f'Topic {i}','notes':'First line.\nSecond line.\nThird line.','notesOK':True} for i in range(1,4)]
    def packet(i,**extra): return {'type':'slide','name':'Rehearsal.pptx','identity':'/test/Rehearsal.pptx','number':i,'total':3,'current':rows[i-1],**extra}
    send({'type':'ready'})
    check('Version is visible in the reader', '0.5' in page.locator('.brand').inner_text())
    check('Window setup cannot be used before linking',page.locator('#slideButtonsBtn').is_disabled())
    send({'type':'linked','name':'Rehearsal.pptx','identity':'/test/Rehearsal.pptx'});send(packet(2,slides=rows))
    check('Live link offers a slideshow-window setup button',page.locator('#slideButtonsBtn').is_enabled())
    page.locator('#slideButtonsBtn').click()
    check('Setup sends a dedicated configuration request',page.evaluate('nativeMessages.filter(m=>!["interaction","saveState","saveTimer"].includes(m.type)).at(-1).type')=='configureSlideButtons')
    check('Setup does not change the reader slide',d()['slide']==2)
    send({'type':'slideButtons','configured':True});send({'type':'navigationResult','ok':True,'message':'Slide buttons ready to test.'})
    check('Ready state is distinct from confirmed navigation',d()['slideButtonsReady'] and not d()['busy'] and d()['slide']==2)
    page.locator('#reader').focus();page.keyboard.press('ArrowDown');page.keyboard.press('ArrowDown')
    check('Down still changes only the line',d()['line']==2 and d()['slide']==2)
    page.keyboard.press('ArrowDown');check('Down stops at last line without changing slide',d()['line']==2 and d()['slide']==2)
    page.locator('#nextSlideBtn').click()
    check('Next button sends exactly a next slide request',page.evaluate('nativeMessages.filter(m=>!["interaction","saveState","saveTimer"].includes(m.type)).at(-1)')=={'type':'powerPointStep','direction':'next'})
    check('Reader does not optimistically advance before confirmation',d()['busy'] and d()['slide']==2 and d()['line']==2)
    check('Duplicate button press is disabled during verification',page.locator('#nextSlideBtn').is_disabled())
    send(packet(2,navigationAvailable=True));send({'type':'navigationResult','ok':False,'message':'Requested slide 3; PowerPoint still reports slide 2. No automatic retry was sent.'})
    check('Unconfirmed request preserves notes and current line',d()['following'] and d()['slide']==2 and d()['line']==2)
    check('Unconfirmed request does not permanently lock buttons',d()['slideControlAvailable'] and page.locator('#nextSlideBtn').is_enabled())
    check('Failure is visible to presenter','No automatic retry' in page.locator('#notice').inner_text())
    count=page.evaluate('nativeMessages.filter(m=>m.type==="powerPointStep").length');page.wait_for_timeout(500)
    check('UI does not automatically resend failed navigation',page.evaluate('nativeMessages.filter(m=>m.type==="powerPointStep").length')==count)
    page.locator('#nextSlideBtn').click();send(packet(3,navigationAvailable=True));send({'type':'navigationResult','ok':True,'message':'PowerPoint confirmed slide 3 / 3.'})
    check('Confirmed next slide loads actual notes at first line',d()['slide']==3 and d()['line']==0)
    page.locator('#reader').focus();page.keyboard.press('ArrowLeft')
    check('Reader-focused Left requests previous slide',page.evaluate('nativeMessages.filter(m=>!["interaction","saveState","saveTimer"].includes(m.type)).at(-1)')=={'type':'powerPointStep','direction':'previous'})
    send(packet(2,navigationAvailable=True));send({'type':'navigationResult','ok':True,'message':'PowerPoint confirmed slide 2 / 3.'})
    check('Returning after accidental change restores saved highlight',d()['slide']==2 and d()['line']==2)
    # Native shortcut errors are not reported as permission to stop following.
    send({'type':'navigationResult','ok':False,'message':'A text field has focus. No keys were sent.'})
    check('Focus refusal keeps the notes connection and configuration button usable',d()['following'] and page.locator('#slideButtonsBtn').is_enabled())
    send({'type':'arrowMode','enabled':True});send({'type':'navigationResult','ok':False,'message':'Shortcut blocked.'})
    check('Slide-button refusal does not disable independent line-key mode',d()['arrowMode'])
    # Compatibility when an earlier native adapter sends a failed navigation packet.
    send(packet(2,navigationError='Legacy -50',navigationAvailable=False))
    check('Legacy rejected-command status is recognised',not d()['slideControlAvailable'])
    send({'type':'navigationResult','ok':True,'message':'Keyboard route ready.'})
    check('New keyboard result recovers legacy-disabled controls without relinking',d()['slideControlAvailable'] and d()['following'])
    check('Recovery updates the live-status label as well as buttons',page.locator('#connectionStatus').inner_text().startswith('Live notes'))
    # Long error message should be scrollable, not take the reader offscreen.
    send({'type':'navigationResult','ok':False,'message':'Unable to verify keyboard focus. '*24})
    for width,height in [(1180,850),(660,540),(390,844)]:
        page.set_viewport_size({'width':width,'height':height});page.wait_for_timeout(90)
        check(f'No horizontal overflow at {width}',page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
        check(f'Clock visible at {width}',page.locator('#clockTime').is_visible())
        page.screenshot(path=str(R/f'Tests/debug_{width}.png'));print('LAYOUT',width,page.evaluate('[...document.querySelectorAll(".top,.toolbar,.statusbar,.notice,.main,.slidehead,.reader,footer")].map(e=>[e.className||e.tagName,Math.round(e.getBoundingClientRect().height)])'))
        check(f'Notes retain usable height at {width}',page.locator('#reader').bounding_box()['height']>=100)
    page.set_viewport_size({'width':1180,'height':850})
    send({'type':'navigationResult','ok':True,'message':'PowerPoint confirmed slide 2 / 3. (Simulated native response for UI test.)'})
    page.screenshot(path=str(R/'Tests/slide_button_ui.png'))
    send({'type':'unlinked','message':'Show ended.'})
    check('Unlink forgets session-only window setup',not d()['slideButtonsReady'] and page.locator('#slideButtonsBtn').is_disabled())
    check('Unlink releases captured keys',not d()['arrowMode'])
    check('No JavaScript exceptions',not errors)
    check('No external network requests',not requests)
    browser.close()
(R/'Tests/slide_buttons_results.json').write_text(json.dumps({'environment':'Offline Linux Chromium; native PowerPoint responses simulated','checks':checks},indent=2))
print(len(checks),'slide-button UI checks passed; native macOS keyboard delivery is not tested.')
