"""Exercise the ACTUAL placement method in a lightweight Swift/Foundation harness.
NSScreen/panel are stubs. This is not an AppKit/macOS/full-screen test.
"""
from pathlib import Path
import subprocess, tempfile
R=Path(__file__).resolve().parents[1]
s=(R/'Source/ScriptCompanion.swift').read_text()
start=s.index('    private func positionOnPresenterDisplay(snapToTop: Bool = false) {')
end=s.index('    func windowDidMove(', start)
method=s[start:end]
harness=r'''
import Foundation
final class Screen {
 let id: Int; let visibleFrame: NSRect
 init(_ id: Int, _ visible: NSRect) { self.id=id; visibleFrame=visible }
}
final class Panel {
 var frame: NSRect; var screen: Screen?; var calls=0
 init(_ frame:NSRect, _ screen:Screen?) { self.frame=frame;self.screen=screen }
 func setFrame(_ frame:NSRect, display:Bool) { self.frame=frame;calls+=1 }
}
final class Placement {
 var selected:Screen?; var positioning=false;var didPlaceReader=false
 var pinnedDisplay:Int;var panel:Panel
 init(_ screen:Screen?, _ frame:NSRect) {
  selected=screen;pinnedDisplay=screen?.id ?? -1;panel=Panel(frame,screen)
 }
 private func selectedScreen() -> Screen? { selected }
 private func displayID(_ screen:Screen) -> Int { screen.id }
 func place(_ snap:Bool=false) { positionOnPresenterDisplay(snapToTop:snap) }
__METHOD__
}
var passed=0
func check(_ label:String, _ condition:Bool) {
 if !condition { fatalError("FAIL: \(label)") }
 passed+=1;print("PASS: \(label)")
}
let screen=Screen(1,NSRect(x:0,y:50,width:1440,height:810))
let initial=NSRect(x:50,y:80,width:920,height:560)
let t=Placement(screen,initial)
t.place()
check("Initial placement reaches usable top with no extra 14-point gap", t.panel.frame.maxY==860)
check("Initial horizontal centering and size retained", t.panel.frame.minX==260 && t.panel.frame.size==initial.size)
t.panel.frame.origin=NSPoint(x:100,y:600);t.place()
check("Dragging upward clamps at usable top, not 14 points below",t.panel.frame.maxY==860 && t.panel.frame.minX==100)
t.panel.frame.origin=NSPoint(x:90,y:120);t.place()
check("Dragging down stays where requested",t.panel.frame.minY==120)
t.place(true)
check("Top command preserves horizontal position",t.panel.frame.maxY==860 && t.panel.frame.minX==90)
t.panel.frame.origin=NSPoint(x:-100,y:-100);t.place()
check("Left and bottom protection remains 14 points",t.panel.frame.minX==14 && t.panel.frame.minY==64)
t.panel.frame.origin.x=2000;t.place()
check("Right-side protection remains 14 points",t.panel.frame.maxX==1426)
let oldCalls=t.panel.calls;t.positioning=true;t.place(true)
check("Reentrant positioning is ignored",t.panel.calls==oldCalls)
t.positioning=false;t.selected=nil;t.place(true)
check("Disconnected selected screen does not reposition to another display",t.panel.calls==oldCalls)
let offset=Screen(9,NSRect(x:-1920,y:-200,width:1920,height:1080))
let n=Placement(offset,initial);n.place(true)
check("Negative-coordinate presenter display reaches its own usable top",n.panel.frame.maxY==880 && n.panel.frame.minX < 0)
n.didPlaceReader=true;n.panel.screen=screen;n.panel.frame.origin=NSPoint(x:1000,y:1000);n.place()
check("Window returned from a different display is placed on selected display",n.panel.frame.maxY==880 && n.panel.frame.minX>=offset.visibleFrame.minX)
let large=Placement(screen,NSRect(x:0,y:0,width:2500,height:1800));large.place(true)
check("Oversized frame uses available bounds retaining sides/bottom",large.panel.frame.maxY==860 && large.panel.frame.minY==64 && large.panel.frame.width==1412)
check("Positioning state released after successful placement",!large.positioning && large.didPlaceReader)
print("\(passed) isolated placement checks passed. AppKit screen/window behavior NOT tested.")
'''.replace('__METHOD__',method)
with tempfile.TemporaryDirectory() as folder:
 src=Path(folder)/'PlacementTests.swift';src.write_text(harness)
 proc=subprocess.run(['swift',str(src)],capture_output=True,text=True,timeout=45)
 print(proc.stdout,end='');print(proc.stderr,end='')
 (R/'Tests/window_placement_run.log').write_text(proc.stdout+proc.stderr)
 if proc.returncode:raise SystemExit(proc.returncode)
