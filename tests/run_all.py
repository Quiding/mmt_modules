"""Runs every test against the addon folders in Lua 5.1 (same version as WoW).

Setup once:  pip install lupa luaparser   (or: pip install --target <dir> lupa luaparser
             and set PYTHONPATH=<dir>)
Run:         python tests/run_all.py        (from Interface/AddOns)
"""
import glob, os, subprocess, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ours = ["MMT_PawnCompare", "MMT_BugFixes", "MMT_Cooldowns", "MMT_Buffs", "MMT_Totems"]

from luaparser import ast
bad = 0
for d in ours:
    for f in glob.glob(os.path.join(root, d, "*.lua")):
        try:
            ast.parse(open(f, encoding="utf-8").read())
        except Exception as e:
            bad += 1
            print("SYNTAX", f, str(e)[:200])
print("syntax: %d failure(s)" % bad)

shared = [("IconBars", ["MMT_Cooldowns", "MMT_Buffs"]), ("ListKeys", ["MMT_Cooldowns", "MMT_Buffs"]), ("SettingsKit", ["MMT_Cooldowns", "MMT_Buffs"]),
          ("Compat", ["MMT_Cooldowns", "MMT_Buffs", "MMT_Totems"]), ("Transfer", ["MMT_Cooldowns", "MMT_Buffs", "MMT_Totems"])]
for name, dirs in shared:
    texts = {open(os.path.join(root, d, name + ".lua"), encoding="utf-8").read() for d in dirs}
    print("shared %s.lua: %s" % (name, "identical" if len(texts) == 1 else "DIFFERS"))
    bad += len(texts) > 1

here = os.path.dirname(os.path.abspath(__file__))
for t in sorted(glob.glob(os.path.join(here, "test_*.py"))):
    r = subprocess.run([sys.executable, t, root], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip().splitlines()
    # a check that was defined but never called prints "<Lua function ...>": that's a failure too
    ok = r.returncode == 0 and not any("<Lua function" in l for l in out)
    print(("PASS " if ok else "FAIL ") + os.path.basename(t))
    if not ok:
        bad += 1
        print("\n".join(out[-6:]))
sys.exit(1 if bad else 0)
