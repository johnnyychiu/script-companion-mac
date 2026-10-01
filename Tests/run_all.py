#!/usr/bin/env python3
"""Run checked-in tests, write fresh logs, and never count incomplete runs as passes.

Browser tests simulate native messages. They do not execute macOS or PowerPoint.
Use --browser-only in Linux CI that does not have Swift installed.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Tests' / 'artifacts'
BROWSER = [
 ('test_notes_at_top.py','notes_at_top_results.json'),
 ('test_notes_first_timer.py','timer_layout_results.json'),
 ('test_reset_all_lines.py','reset_all_results.json'),
 ('test_reader.py','results.json'),
 ('test_keyboard_recovery.py','keyboard_results.json'),
 ('test_slide_buttons.py','slide_buttons_results.json'),
 ('test_preview_clock_memory.py','preview_results.json'),
]
SWIFT = [
 ('KeyPolicyTests.swift','PresentationKeyPolicy.swift'),
 ('SlideNavigationPolicyTests.swift','SlideNavigationPolicy.swift'),
 ('PositionParserTests.swift','PowerPointPositionParser.swift'),
]

def run(label: str, command: list[str], timeout: int = 120) -> dict:
    begin = time.monotonic()
    print(f'Running {label}...', flush=True)
    try:
        result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
        output, code = result.stdout, result.returncode
        status = 'PASS' if code == 0 else 'FAIL'
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b''
        if isinstance(output, bytes):
            output = output.decode('utf-8', errors='replace')
        output += '\nINCOMPLETE: exceeded test runner time limit.\n'
        code, status = None, 'TIMEOUT'
    (OUT / f'{label}.log').write_text(output, encoding='utf-8')
    print(f'{label}: {status}', flush=True)
    return {'suite':label,'result':status,'exit_code':code,
            'duration_seconds':round(time.monotonic()-begin,2),
            'log':f'{label}.log'}

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--browser-only', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    entries = []
    for script, report in BROWSER:
        target = ROOT / 'Tests' / report
        target.unlink(missing_ok=True)
        entry = run(script.removesuffix('.py'), [sys.executable,str(ROOT/'Tests'/script)])
        if entry['result']=='PASS' and target.exists():
            data=json.loads(target.read_text())
            entry['checks'] = data['checks']
            shutil.copy2(target, OUT / report)
        entries.append(entry)
    if not args.browser_only:
        if not shutil.which('swift') or not shutil.which('swiftc'):
            entries.append({'suite':'Swift policy / placement checks','result':'NOT RUN',
                            'reason':'Swift compiler not installed.'})
        else:
            with tempfile.TemporaryDirectory(prefix='script-companion-tests-') as temp:
                temp=Path(temp)
                for test, production in SWIFT:
                    executable=temp/'tests'
                    entry=run(test.removesuffix('.swift')+'-compile',[
                        'swiftc',str(ROOT/'Source'/production),str(ROOT/'Tests'/test),'-o',str(executable)])
                    entries.append(entry)
                    if entry['result']=='PASS':
                        entries.append(run(test.removesuffix('.swift'),[str(executable)]))
                entries.append(run('test_window_placement',[sys.executable,str(ROOT/'Tests/test_window_placement.py')]))
    entries.append(run('builder-syntax',['bash','-n',str(ROOT/'Build Mac App.command')]))
    passed=sum(sum(c.get('result')=='PASS' for c in x.get('checks',[])) for x in entries)
    notrun=sum(sum(c.get('result')!='PASS' for c in x.get('checks',[])) for x in entries)
    data={
        'generated_at_utc':datetime.now(timezone.utc).isoformat(),
        'scope':'Browser reader and simulated native packets; isolated Swift/Foundation checks only. No macOS app build, WKWebView, PowerPoint, or projector validation.',
        'system':platform.system(), 'python':platform.python_version(),
        'playwright':importlib.metadata.version('playwright'),
        'chromium_executable_override':bool(os.environ.get('CHROMIUM_EXECUTABLE')),
        'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'Source').iterdir()) if p.is_file()},
        'browser_checks_passed':passed,'browser_checks_not_run':notrun,
        'suites':entries,
    }
    (OUT/'summary.json').write_text(json.dumps(data,indent=2)+'\n')
    failed=any(x['result'] in ['FAIL','TIMEOUT'] for x in entries)
    print(f'\n{passed} browser checks passed; {notrun} checks not run. See Tests/artifacts/summary.json.')
    return 1 if failed else 0

if __name__=='__main__':
    raise SystemExit(main())
