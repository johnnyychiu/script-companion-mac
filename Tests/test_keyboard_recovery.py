"""Browser/native-protocol regression tests for recovery mode. NOT macOS tests."""
from pathlib import Path
import json, os
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]
checks=[]
def check(name, ok):
    assert ok, name
    checks.append({'test':name,'result':'PASS'})
    print('PASS',name,flush=True)
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path=os.environ.get('CHROMIUM_EXECUTABLE'),headless=True,args=['--no-sandbox'])
    c=b.new_context(viewport={'width':920,'height':760});c.set_offline(True)
    p=c.new_page();errors=[];p.on('pageerror',lambda e:errors.append(str(e)));p.on('dialog',lambda d:d.accept())
    p.evaluate("Object.defineProperty(window,'localStorage',{value:{getItem(){return null},setItem(){}}}); window.nativeMessages=[];window.webkit={messageHandlers:{companion:{postMessage:m=>nativeMessages.push(m)}}};")
    p.set_content((R/'Source/reader.html').read_text())
    p.evaluate("document.getElementById('settingsPanel').open=true")
    send=lambda e:p.evaluate('e=>Companion.receive(e)',e)
    diag=lambda:p.evaluate('Companion.diagnostics()')
    rows=[{'number':i,'id':str(255+i),'title':f'Slide {i}','notes':'First line.\nSecond line.\nThird line.','notesOK':True} for i in range(1,4)]
    def packet(i,**extra):
        return {'type':'slide','identity':'/test/Recovery.pptx','name':'Recovery.pptx','number':i,'total':3,'current':rows[i-1],**extra}
    send({'type':'ready'});send({'type':'linked','identity':'/test/Recovery.pptx','name':'Recovery.pptx'});send(packet(2,slides=rows))
    send({'type':'arrowMode','enabled':True});send({'type':'line','delta':1})
    send(packet(2,navigationError='Slide jump rejected (-50). Parameter error.',navigationAvailable=False))
    check('Rejected direct command keeps notes linked',diag()['following'])
    check('Rejected direct command does not disable an enabled line-key mode',diag()['arrowMode'])
    check('PowerPoint keys toggle remains usable in follow-only mode',p.locator('#arrowModeBtn').is_enabled())
    check('Unsafe direct slide buttons are still paused',p.locator('#prevSlideBtn').is_disabled() and p.locator('#nextSlideBtn').is_disabled())
    check('Error retains original reason and describes recovery',all(s in p.locator('#notice').inner_text() for s in ['-50','PowerPoint keys','Presenter View']))
    send({'type':'line','delta':1});check('Down still advances highlighted line after direct command fails',diag()['line']==2 and diag()['slide']==2)
    send({'type':'line','delta':1});check('Down at final line does not change slide',diag()['slide']==2 and diag()['line']==2)
    send(packet(3,navigationAvailable=False));send(packet(2,navigationAvailable=False))
    check('A real slide-status change restores the earlier highlighted line',diag()['line']==2 and diag()['slide']==2)
    p.locator('#reader').focus();start=p.evaluate('nativeMessages.length');p.keyboard.press('ArrowRight')
    check('Reader-focused Right does not retry rejected slide adapter',not p.evaluate('(n)=>nativeMessages.slice(n).some(e=>e.type==="powerPointStep")',start))
    check('Reader-focused warning explains PowerPoint must have focus','Keep PowerPoint focused' in p.locator('#notice').inner_text())
    send({'type':'arrowMode','enabled':False});previous=p.evaluate('nativeMessages.length');p.locator('#arrowModeBtn').click()
    check('Line-key mode can be requested after direct failure',p.evaluate('(start)=>nativeMessages.slice(start).filter(m=>m.type==="toggleArrowMode").length',previous)==1)
    send({'type':'arrowMode','enabled':True});send({'type':'busy','message':'Reading notes'})
    check('User can switch capture off even while notes are busy',p.locator('#arrowModeBtn').is_enabled())
    send(packet(2,navigationAvailable=False));p.locator('#helpBtn').click();before=diag()['line'];send({'type':'line','delta':-1})
    check('Open reader help blocks native line movement',diag()['line']==before)
    p.locator('#closeHelpBtn').click();p.locator('#reader').focus();p.keyboard.press('Escape')
    check('Escape requests line capture release',p.evaluate('nativeMessages.some(x=>x.type==="disableArrowMode")'))
    send({'type':'unlinked','message':'Show ended'})
    check('Unlink releases capture and disables its toggle',not diag()['arrowMode'] and p.locator('#arrowModeBtn').is_disabled())
    check('UI shows version 0.5','0.5' in p.locator('.brand').inner_text())
    check('No JavaScript exceptions',not errors)
    b.close()
(R/'Tests/keyboard_results.json').write_text(json.dumps({'environment':'Offline Linux Chromium with simulated native packets, not PowerPoint','checks':checks},indent=2))
print(len(checks),'recovery checks passed.')
