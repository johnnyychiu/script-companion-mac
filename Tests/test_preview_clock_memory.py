"""Offline UI tests. Native event packets are simulated, never an actual Mac/PPT run."""
from pathlib import Path
from playwright.sync_api import sync_playwright
import io, json, os, re, zipfile, time
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'Tests'
HTML=(ROOT/'Source/reader.html').read_text()
IMAGES=sorted((ROOT/'Demo/Slide images').glob('*.png'))
results=[];errors=[];requests=[]
def check(name, ok):
    assert ok,name
    results.append({'test':name,'result':'PASS'})
    print('PASS',name,flush=True)
STORAGE="""Object.defineProperty(window,'localStorage',{value:{data:{},getItem(k){return this.data[k]??null},setItem(k,v){this.data[k]=String(v)},removeItem(k){delete this.data[k]}}});"""
with sync_playwright() as pw:
    browser=pw.chromium.launch(headless=True,executable_path=os.environ.get('CHROMIUM_EXECUTABLE'),args=['--no-sandbox'])
    ctx=browser.new_context(viewport={'width':1180,'height':850},accept_downloads=True,locale='en-GB',timezone_id='Europe/London')
    ctx.set_offline(True)
    def page(native=False):
        p=ctx.new_page();p.set_default_timeout(4000)
        p.on('pageerror',lambda e: errors.append(str(e)));p.on('request',lambda r:requests.append(r.url) if r.url.startswith(('http:','https:')) else None)
        p.on('dialog',lambda d:d.accept());p.evaluate(STORAGE)
        if native:p.evaluate('window.nativeMessages=[];window.webkit={messageHandlers:{companion:{postMessage:m=>nativeMessages.push(m)}}};')
        p.set_content(HTML)
        p.evaluate("document.getElementById('settingsPanel').open=true")
        if native:p.evaluate("Companion.receive({type:'ready'})")
        return p
    def wait(p, expression):
        end=time.monotonic()+4
        while time.monotonic()<end:
            if p.evaluate(expression):return
            p.wait_for_timeout(50)
        raise AssertionError('Timed out: '+expression)
    def diag(p):return p.evaluate('Companion.diagnostics()')
    def files(p, items):p.locator('#previewFiles').set_input_files(items);wait(p,'!document.querySelector("#choosePreviewFilesBtn").disabled')
    def image_import(p):
        p.locator('#loadPreviewsBtn').click();files(p,[str(x) for x in reversed(IMAGES)]);p.locator('#applyPreviewsBtn').click()
    def script(p):
        p.locator('#fileInput').set_input_files(str(ROOT/'Demo/Rehearsal.pptx'));wait(p,'Companion.diagnostics().slides===3')
    q=page();check('Clock displays seconds in 24-hour mode',bool(re.match(r'^\d\d:\d\d:\d\d$',diag(q)['clock'])))
    before=diag(q);q.wait_for_timeout(1200);check('Clock advances without changing the slide or line',diag(q)['clock']!=before['clock'] and diag(q)['line']==before['line'] and diag(q)['slide']==before['slide'])
    q.locator('#clockBtn').click();check('Click switches clock to 12-hour mode',not diag(q)['clock24'] and bool(re.search(r'am|pm',diag(q)['clock'],re.I)))
    q.locator('#clockBtn').click();check('Click restores 24-hour mode',diag(q)['clock24'])
    script(q);check('PowerPoint import retains stable slide IDs',diag(q)['previewKey']=='id:256')
    q.locator('#reader').focus();q.keyboard.press('ArrowRight')
    check('Seven supplied lesson sentences are speaker-note lines',q.locator('.words').count()==7 and 'confirmed facts' in q.locator('.words').nth(3).inner_text())
    q.keyboard.press('ArrowDown');q.keyboard.press('ArrowDown');q.keyboard.press('ArrowDown')
    q.keyboard.press('ArrowRight');q.keyboard.press('ArrowDown');q.keyboard.press('ArrowLeft')
    check('Accidental next slide then back restores line 4 on lesson slide',diag(q)['slide']==2 and diag(q)['line']==3)
    q.keyboard.press('ArrowRight');check('Forward navigation also restores that slide’s line 2',diag(q)['slide']==3 and diag(q)['line']==1)
    q.keyboard.press('ArrowLeft');q.locator('#restartLineBtn').click();check('Restart button resets only the current slide',diag(q)['line']==0)
    q.locator('#reader').focus();q.keyboard.press('ArrowRight');check('Other slides keep their positions after current-slide restart',diag(q)['line']==1)
    q.keyboard.press('ArrowLeft');q.keyboard.press('ArrowDown');q.keyboard.press('ArrowDown');q.keyboard.press('ArrowDown')
    q.locator('#loadPreviewsBtn').click();files(q,[str(IMAGES[0])]);check('Wrong image count is rejected before mapping','3 slides' in q.locator('#previewImportStatus').inner_text() and diag(q)['previewCount']==0)
    files(q,[str(x) for x in reversed(IMAGES)])
    check('Unordered image selection maps by slide numbers',[x.strip() for x in q.locator('.mappingrow span').all_text_contents()]==[x.name for x in IMAGES])
    check('Images are not applied before explicit confirmation',diag(q)['previewCount']==0 and q.locator('#applyPreviewsBtn').is_enabled())
    old=diag(q);q.locator('#previewDialog').focus();q.keyboard.press('ArrowDown');q.keyboard.press('ArrowRight');check('Arrow keys do not move script while mapping dialog is open',diag(q)['line']==old['line'] and diag(q)['slide']==old['slide'])
    q.locator('#applyPreviewsBtn').click();check('Confirmed image set appears on current slide',diag(q)['previewCount']==3 and q.locator('#slidePreview').is_visible() and 'slide 2' in q.locator('#slidePreview').get_attribute('alt'))
    src=q.locator('#slidePreview').get_attribute('src');q.locator('#reader').focus();q.keyboard.press('ArrowRight');check('Preview changes with the selected slide',q.locator('#slidePreview').get_attribute('src')!=src and 'slide 3' in q.locator('#slidePreview').get_attribute('alt'))
    q.keyboard.press('ArrowLeft');check('Returning restores both preview image and highlighted line',q.locator('#slidePreview').get_attribute('src')==src and diag(q)['line']==3)
    q.locator('#enlargePreviewBtn').click();check('Slide preview can be enlarged',q.locator('#largePreview').evaluate('e=>e.open') and q.locator('#largePreviewImage').get_attribute('src')==src)
    q.keyboard.press('ArrowRight');check('Large preview dialog prevents accidental slide jumps',diag(q)['slide']==2);q.locator('#closeLargePreviewBtn').click()
    q.locator('#reader').focus();q.keyboard.press('p');check('P hides preview without changing line',not diag(q)['previewVisible'] and diag(q)['line']==3)
    q.keyboard.press('p');check('P restores preview and image',diag(q)['previewVisible'] and q.locator('#slidePreview').get_attribute('src')==src)
    # Back up all images, notes and positions using the actual export action.
    with q.expect_download() as dl:q.locator('#backupBtn').click()
    dl.value.save_as(str(WORK/'preview_backup.json'));backup=json.loads((WORK/'preview_backup.json').read_text())
    check('Backup includes images and independent per-slide positions',len(backup['previews'])==3 and backup['linePositions']['id:257']['line']==3 and backup['linePositions']['id:258']['line']==1)
    restored=page();restored.locator('#fileInput').set_input_files(str(WORK/'preview_backup.json'));wait(restored,'Companion.diagnostics().previewCount===3')
    check('Restored backup retains image, current slide and current line',diag(restored)['slide']==2 and diag(restored)['line']==3 and restored.locator('#slidePreview').get_attribute('src')==src)
    restored.locator('#reader').focus();restored.keyboard.press('ArrowRight');check('Restored backup retains other slide’s saved line',diag(restored)['line']==1)
    # ZIP import skips Finder metadata and maps by the image filenames.
    zbytes=io.BytesIO()
    with zipfile.ZipFile(zbytes,'w') as z:
        for im in reversed(IMAGES):z.writestr('slides/'+im.name,im.read_bytes())
        z.writestr('__MACOSX/._slide-1.png',b'not an image')
    q.locator('#loadPreviewsBtn').click();files(q,{'name':'slide_images.zip','mimeType':'application/zip','buffer':zbytes.getvalue()})
    check('ZIP of exported slides ignores Mac metadata',q.locator('.mappingrow').count()==3 and q.locator('#applyPreviewsBtn').is_enabled());q.locator('#applyPreviewsBtn').click()
    # Invalid image: existing previews stay intact.
    q.locator('#loadPreviewsBtn').click();bad=[{'name':'Slide1.png','mimeType':'image/png','buffer':b'not an image'},*[{'name':x.name,'mimeType':'image/png','buffer':x.read_bytes()} for x in IMAGES[1:]]]
    files(q,bad);check('Corrupt image does not replace working previews','Not a readable' in q.locator('#previewImportStatus').inner_text() and diag(q)['previewCount']==3);q.locator('#cancelPreviewBtn').click()
    # Quota fallback saves text even when images cannot fit.
    q.evaluate("localStorage.setItem=function(k,v){if(JSON.parse(v).previews && Object.keys(JSON.parse(v).previews).length)throw Error('quota');this.data[k]=v;};undefined")
    q.locator('#nextLineBtn').click();q.wait_for_timeout(400)
    data=q.evaluate("JSON.parse(localStorage.getItem('scriptCompanion.v1'))")
    check('Storage quota fallback retains notes and position instead of losing everything',data['line']==4 and not data['previews'] and data['previewsNotSaved'])
    check('Storage quota fallback reports image backup is needed','Back up images' in q.locator('#saveStatus').inner_text())
    q.locator('#prevLineBtn').click()
    # Simulated Mac transport, with explicit stable identities and real preview image import.
    n=page(native=True)
    send=lambda e:n.evaluate('e=>Companion.receive(e)',e)
    rows=[{'number':i+1,'id':str(256+i),'title':t,'notes':'\n'.join(ls),'notesOK':True} for i,(t,ls) in enumerate([
        ('Opening',['Intro.','Second sentence.','Third sentence.']),('Seven lessons',['First.','Second.','Third.','Fourth.','Fifth.']),('Close',['Thank you.','Questions?'])])]
    def payload(num,deck=None,**extra):
        d=deck or rows
        return {'type':'slide','name':'Live.pptx','identity':'/local/Live.pptx','number':num,'total':len(d),'current':d[num-1],**extra}
    send({'type':'linked','name':'Live.pptx','identity':'/local/Live.pptx'});send(payload(2,slides=rows));image_import(n)
    n.locator('#reader').focus();n.keyboard.press('ArrowDown');n.keyboard.press('ArrowDown');n.keyboard.press('ArrowDown')
    src_live=n.locator('#slidePreview').get_attribute('src')
    n.keyboard.press('ArrowRight');check('Right requests native navigation without optimistic preview change',diag(n)['slide']==2 and n.locator('#slidePreview').get_attribute('src')==src_live)
    send(payload(3));send(payload(2));check('Confirmed native slide changes restore previous highlighted line and image',diag(n)['line']==3 and n.locator('#slidePreview').get_attribute('src')==src_live)
    n.evaluate('window.keptPreview=document.querySelector("#slidePreview");window.keptCurrent=document.querySelector(".current")');send(payload(2))
    check('Unchanged live poll preserves preview and highlighted DOM node',n.evaluate('keptPreview===document.querySelector("#slidePreview")&&keptCurrent===document.querySelector(".current")'))
    # Edited notes should retain the spoken sentence.
    modified=[dict(x) for x in rows];modified[1]['notes']='Inserted first.\n'+rows[1]['notes'];send(payload(2,modified));check('Edited live notes relocate the remembered sentence',diag(n)['line']==4 and n.locator('.current .words').inner_text()=='Fourth.')
    send(payload(3,modified));send(payload(2,modified));check('Revisiting updated slide retains its adjusted line position',diag(n)['line']==4)
    # Reordering uses IDs, not the new number.
    reorder=[dict(modified[1],number=1),dict(modified[0],number=2),dict(modified[2],number=3)]
    send(payload(1,reorder,slides=reorder));check('Reordered slide keeps its line and image via stable slide ID',diag(n)['line']==4 and n.locator('#slidePreview').get_attribute('src')==src_live)
    failed=[dict(x) for x in reorder];failed[0].update(notesOK=False,notesError='Temporary notes failure.');send(payload(1,failed));send(payload(1,reorder));check('Temporary notes failure does not erase the saved line',diag(n)['line']==4)
    send({'type':'unlinked','message':'Disconnected.'});check('Unlink labels previews as script-selected, not live','Selected script slide' in n.locator('#previewCaption').inner_text())
    send({'type':'linked','name':'Live.pptx','identity':'/local/Live.pptx'});send(payload(1,reorder,slides=reorder));check('Relinking same presentation retains line positions and previews',diag(n)['line']==4 and diag(n)['previewCount']==3)
    send({'type':'arrowMode','enabled':False});send(payload(1,reorder,navigationError='Parameter error (-50).',navigationAvailable=False))
    check('Navigation failure packet keeps valid note following but disables slide commands',diag(n)['following'] and not diag(n)['slideControlAvailable'] and n.locator('#nextSlideBtn').is_disabled())
    check('Follow-only fallback is clearly labelled','Follow-only' in n.locator('#connectionStatus').inner_text() and 'live notes still follow' in n.locator('#notice').inner_text())
    send(payload(2,reorder,navigationAvailable=False));check('PowerPoint changes still update preview in follow-only mode',diag(n)['slide']==2 and n.locator('#slidePreview').get_attribute('src')!=src_live)
    # A new presentation often reuses slide IDs 256, 257: do not leak memory or images across decks.
    send({'type':'unlinked','message':'New presentation test.'});send({'type':'linked','name':'Different.pptx','identity':'/different/Different.pptx'})
    e=payload(2);e.update(identity='/different/Different.pptx',name='Different.pptx',slides=rows);send(e)
    check('Different deck does not inherit positions or images despite reused slide IDs',diag(n)['line']==0 and diag(n)['previewCount']==0)
    n.locator('#loadPreviewsBtn').click();check('Image mapping dialog tells native app to suspend captured keys',n.evaluate("nativeMessages.some(m=>m.type==='interaction'&&m.blocked===true)"));send({'type':'line','delta':1});check('Native line events are ignored during image mapping',diag(n)['line']==0);n.locator('#cancelPreviewBtn').click()
    # Safety: backups cannot inject SVG or external image URLs.
    malicious=dict(backup);malicious['previews']={'id:257':{'name':'bad','data':'https://example.invalid/track.png'},'id:256':{'name':'svg','data':'data:image/svg+xml;base64,PHN2Zz4='}}
    safe=page();safe.locator('#fileInput').set_input_files({'name':'bad.json','mimeType':'application/json','buffer':json.dumps(malicious).encode()});safe.wait_for_timeout(100);check('Backup validation rejects external and SVG image payloads',diag(safe)['previewCount']==0)
    # Screenshots are of actual browser state with the included demo, never claimed to be Mac screenshots.
    q.evaluate("localStorage.setItem=function(k,v){this.data[k]=String(v);};undefined");q.locator('#prevLineBtn').click();q.locator('#nextLineBtn').click();q.wait_for_timeout(350)
    q.evaluate("document.querySelector('#notice').hidden=true");q.locator('#reader').focus()
    for w,h in [(1180,850),(920,700),(660,540),(520,700),(390,844)]:
        q.set_viewport_size({'width':w,'height':h})
        if w==660:q.locator('#compactBtn').click()
        q.wait_for_timeout(160)
        check(f'Preview layout has no horizontal overflow at {w}x{h}',q.evaluate('document.documentElement.scrollWidth<=innerWidth'))
        check(f'Clock remains visible at {w}x{h}',q.locator('#clockTime').is_visible())
        q.screenshot(path=str(WORK/f'preview_layout_{w}.png'))
    q.set_viewport_size({'width':1180,'height':850})
    if q.locator('#compactBtn').inner_text()=='Expand':q.locator('#compactBtn').click()
    q.wait_for_timeout(200);q.screenshot(path=str(WORK/'preview_full.png'))
    q.set_viewport_size({'width':660,'height':540});q.locator('#compactBtn').click();q.wait_for_timeout(200);q.screenshot(path=str(WORK/'preview_compact.png'))
    check('No external network requests during preview, ZIP import, clock or syncing tests',not requests)
    check('No JavaScript errors during new-feature tests',not errors)
    browser.close()
(WORK/'preview_results.json').write_text(json.dumps({'environment':'Linux Chromium; native packets simulated, not actual Mac/PowerPoint','checks':results},indent=2))
print(len(results),'new-feature checks passed. Actual macOS build and PowerPoint integration are not tested here.')
