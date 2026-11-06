"""Runs the Lua tests and syntax-checks the addon under Lua 5.1 (WoW's dialect).

Needs: pip install lupa
Usage: python tests/run.py   (from the project root)
"""
import glob
import os
import sys

import lupa.lua51 as lua51

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)

ok = True

# Syntax check every addon file (compile only, nothing runs).
for path in sorted(glob.glob('Bagnon_Cheapest/*.lua')):
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    src = open(path, encoding='utf-8').read()
    compiled, err = rt.eval(
        'function(src, name) local f, e = loadstring(src, name) return f ~= nil, tostring(e) end'
    )(src, '@' + path)
    if not compiled:
        ok = False
        print('SYNTAX ' + str(err))
    else:
        print('syntax ok  ' + path)

# Unit tests, then the stubbed-API smoke test. Fresh runtime for each.
for test in ('tests/test_logic.lua', 'tests/smoke_wow.lua'):
    print('--- ' + test)
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    try:
        rt.execute(open(test, encoding='utf-8').read())
    except lua51.LuaError as e:
        ok = False
        print('ERROR', e)

# Every :Method( call must exist in Forever's widget API docs (or be a known exception).
import subprocess
print('--- tests/check_methods.py')
if subprocess.call([sys.executable, os.path.join('tests', 'check_methods.py')]) != 0:
    ok = False

sys.exit(0 if ok else 1)
