"""Runs every test against the addon folders in Lua 5.1 (same version as WoW).

Setup once:  pip install lupa luaparser   (or: pip install --target <dir> lupa luaparser
             and set PYTHONPATH=<dir>)
Run:         python tests/run_all.py        (from Interface/AddOns)
"""
import glob, os, subprocess, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ours = ["MMT_PawnCompare", "MMT_CooldownTimers", "MMT_BuffTimers", "MMT_Totems", "MMT_Whispers", "MMT_TeamGear", "MMT_TeamInventory", "MMT_QoL", "MMT_qStyles"]

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

# Lua slip seen twice: "local a, b = x and f()" keeps only f's FIRST value
import re
slip = re.compile(r"^\s*local\s+\w+\s*,\s*\w+\s*=\s*[\w.]+\s+and\s+[\w.:]+\(")
for d in ours:
    for f in glob.glob(os.path.join(root, d, "*.lua")):
        for n, line in enumerate(open(f, encoding="utf-8"), 1):
            if slip.search(line):
                bad += 1
                print("LINT %s:%d two values from 'x and f()' - only the first survives" % (f, n))

shared = [("IconBars", ["MMT_CooldownTimers", "MMT_BuffTimers"]), ("ListKeys", ["MMT_CooldownTimers", "MMT_BuffTimers"]), ("Specs", ["MMT_CooldownTimers", "MMT_BuffTimers"]), ("SettingsKit", ["MMT_CooldownTimers", "MMT_BuffTimers", "MMT_Totems", "MMT_TeamInventory", "MMT_QoL"]),
          ("Compat", ["MMT_CooldownTimers", "MMT_BuffTimers", "MMT_Totems"]), ("Search", ["MMT_CooldownTimers", "MMT_BuffTimers"]), ("FramesTab", ["MMT_CooldownTimers", "MMT_BuffTimers"]), ("Transfer", ["MMT_CooldownTimers", "MMT_BuffTimers", "MMT_Totems"])]
for name, dirs in shared:
    texts = {open(os.path.join(root, d, name + ".lua"), encoding="utf-8").read() for d in dirs}
    print("shared %s.lua: %s" % (name, "identical" if len(texts) == 1 else "DIFFERS"))
    bad += len(texts) > 1

# key bindings as in the core's CreateModules.md: Bindings.xml not in the TOC, every binding in
# category BINDING_CATEGORY_MMT, the first with an own MMT_<NAME> header, texts set in Lua
for d in ours:
    xml = os.path.join(root, d, "Bindings.xml")
    if not os.path.exists(xml):
        continue
    text = open(xml, encoding="utf-8").read()
    lua = "".join(open(f, encoding="utf-8").read() for f in glob.glob(os.path.join(root, d, "*.lua")))
    toc = open(os.path.join(root, d, d + ".toc"), encoding="utf-8").read()
    binds = re.findall(r"<Binding\s+([^>]*)>", text)
    headers = re.findall(r'header="([^"]*)"', text)
    problems = []
    if re.search(r"^\s*Bindings\.xml\s*$", toc, re.M | re.I): problems.append("listed in the TOC")
    if any('category="BINDING_CATEGORY_MMT"' not in b for b in binds): problems.append("binding without category BINDING_CATEGORY_MMT")
    if not binds or 'header="' not in binds[0]: problems.append("first binding has no header")
    for h in headers:
        if not h.startswith("MMT_") or h == "MMT": problems.append("header %s is not MMT_<NAME>" % h)
        if "BINDING_HEADER_" + h not in lua: problems.append("BINDING_HEADER_%s not set in Lua" % h)
    for name in re.findall(r'name="([^"]*)"', text):
        if ("BINDING_NAME_" + name) not in lua: problems.append("BINDING_NAME_%s not set in Lua" % name)
    print("bindings %s: %s" % (d, "; ".join(problems) or "ok"))
    bad += len(problems)

# off by default (MMT's CreateModules.md): "## DefaultState: disabled" and "## X-MMT-DefaultState: disabled" together
for d in ours:
    toc = open(os.path.join(root, d, d + ".toc"), encoding="utf-8").read()
    a = re.search(r"^## DefaultState:\s*disabled\s*$", toc, re.M | re.I) is not None
    b = re.search(r"^## X-MMT-DefaultState:\s*disabled\s*$", toc, re.M | re.I) is not None
    if a != b:
        bad += 1
        print("DEFAULTSTATE %s: needs both DefaultState and X-MMT-DefaultState (or neither)" % d)

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
