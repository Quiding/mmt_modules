"""Draws every module's settings page as an HTML mockup, without the game.

It builds each page with test_settings' stand-in widgets (like tests/test_layout.py), records where
every tile, column widget and button lands and what value its getter returns, and draws that in
MMT's dark look: dist/settings-mockups.html (a sidebar with one entry per module tab and Look
sub-tab). Fonts, icons and the game's textures are approximations: it's a layout preview,
not a screenshot. Run from the repo root:

    python tools/mockup_settings.py            (needs lupa, like the tests)
"""
import html, json, os, sys
from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
src = open("tests/test_settings.py", encoding="utf-8").read()
STUBS = src.split("STUBS = r'''", 1)[1].split("'''", 1)[0]

RECORD = r'''
local U = getmetatable(STUB())
local index = U.__index
U.__index = function(t, k)
  if k == "SetSize" then return function(self, w, h) rawset(self, "_w", w); rawset(self, "_h", h) end end
  if k == "SetHeight" then return function(self, h) rawset(self, "_h", h) end end
  if k == "SetWidth" then return function(self, w) rawset(self, "_w", w) end end
  if k == "GetHeight" then return function(self) return rawget(self, "_h") or 564 end end
  if k == "GetWidth" then return function(self) return rawget(self, "_w") or 698 end end
  if k == "SetShown" then return function(self, v) rawset(self, "_hidden", not v) end end
  if k == "Hide" then return function(self) rawset(self, "_hidden", true) end end
  if k == "Show" then return function(self) rawset(self, "_hidden", false) end end
  if k == "SetPoint" then return function(self, p, rel, rp, x, y)
    if type(rel) == "table" then rawset(self, "_beside", { rel, tonumber(x) or 0 })
    elseif type(p) == "string" and p:find("^BOTTOM") then rawset(self, "_anchor", { p, tonumber(rel) or 0, tonumber(rp) or 0 }) end
  end end
  return index(t, k)
end

FRAMES = {}
function CreateFrame(_, name, parent)
  local f = STUB()
  rawset(f, "_parent", parent)
  if name then rawset(_G, name, f) end
  return f
end
local function W(kind, parent, w, text)
  local f = CreateFrame("Frame", nil, parent)
  rawset(f, "_kind", kind); rawset(f, "_w", w); rawset(f, "_text", text)
  local label = STUB()
  rawset(label, "SetText", function(_, t) rawset(f, "_text", t) end)
  rawset(f, "label", label)
  FRAMES[#FRAMES + 1] = f
  return f
end
rawset(UI, "Button", function(parent, w, text) return W("button", parent, w, text) end)
rawset(UI, "EditBox", function(parent, w, text) return W("edit", parent, w, text) end)
rawset(UI, "TextButton", function(parent, text, fn, w) return W("tbutton", parent, w or 22, text) end)
local H = MMT.ConfigHelpers
rawset(H, "ConfirmButton", function(parent, w, text) return W("button", parent, w, text) end)
rawset(H, "List", function(parent, w, rows, rowH)
  local f = W("list", parent, w, nil)
  rawset(f, "_h", rows * rowH); rawset(f, "_rows", rows); rawset(f, "_rowH", rowH)
  rawset(f, "Render", function(self, data) rawset(self, "_data", data) end)
  return f
end)

local function NoteH(text, width)
  local lines = 0
  for part in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    lines = lines + math.max(1, math.ceil(#part * 5.5 / width))
  end
  return math.max(22, lines * 12 + 8), lines
end

COLS = {}
UI.Column = function(parent, x, y, width)
  local col = STUB()
  width = width or 248
  local c = { parent = parent, x = x or 0, width = width, items = {} }
  COLS[#COLS + 1] = c
  local cur = y or 0
  rawset(col, "y", cur); rawset(col, "parent", parent); rawset(col, "width", width); rawset(col, "x", x)
  local function adv(h) cur = cur - h; rawset(col, "y", cur) end
  local function item(kind, text, h, extra, f)
    f = f or STUB()
    local it = { kind = kind, text = text, y = cur, h = h, f = f }
    for k, v in pairs(extra or {}) do it[k] = v end
    c.items[#c.items + 1] = it
    adv(h)
    return f
  end
  rawset(col, "Header", function(_, text) adv(6); local f = STUB(); c.items[#c.items + 1] = { kind = "header", text = text, y = cur, h = 22, f = f }; adv(22); return f end)
  rawset(col, "Note", function(_, text) local h = NoteH(text, width); return item("note", text, h) end)
  rawset(col, "Space", function(_, h) adv(h or 8) end)
  rawset(col, "Check", function(_, text, g) return item("check", text, 22, { get = g }) end)
  rawset(col, "Slider", function(_, text, lo, hi, step, g, s, fmt) return item("slider", text, 36, { get = g, fmt = fmt, lo = lo, hi = hi }) end)
  local function cyc(_, text, choices, g) return item("cycle", text, 24, { get = g, choices = choices }) end
  rawset(col, "Cycle", cyc); rawset(col, "Dropdown", cyc)
  rawset(col, "Button", function(_, text) return item("button", text, 24, nil, W("button", parent, width, text)) end)
  rawset(col, "Color", function(_, text, g) return item("color", text, 24, { get = g }) end)
  rawset(col, "Add", function(_, f, h) return item("add", nil, h == nil and 22 or h, nil, f) end)
  return col
end

TILES, INTROS, TABS = {}, {}, {}
rawset(H, "Tile", function(parent, x, y, w, h, title, icon)
  local t = CreateFrame("Frame", nil, parent)
  t:SetSize(w, h)
  rawset(t, "_x", x); rawset(t, "_y", y); rawset(t, "_tile", true)
  TILES[#TILES + 1] = { f = t, title = title, icon = icon }
  return t, UI.Column(t, 8, -42, w - 16)
end)
rawset(H, "Intro", function(page, text) INTROS[#INTROS + 1] = text; return -22, STUB() end)
'''

TABS_WRAP = r'''function(m)
  local orig = m.Tabs
  if not orig then return end
  m.Tabs = function(page, list, opts)
    local panels = orig(page, list, opts)
    TABS[#TABS + 1] = { owner = page, list = list, panels = panels }
    for _, t in ipairs(list) do
      local p = panels[t[1]]
      rawset(p, "_tab", { g = #TABS, id = t[1] })
      rawset(p, "_x", 0); rawset(p, "_y", -34)
    end
    return panels
  end
end'''

EXPORT = r'''function(m, page)
  local function Pos(f)
    if f == nil or f == page then return 0, 0 end
    local px, py = Pos(rawget(f, "_parent"))
    return px + (rawget(f, "_x") or 0), py + (rawget(f, "_y") or 0)
  end
  local function Chain(f)
    local out = {}
    while f and f ~= page do
      local t = rawget(f, "_tab")
      if t then out[#out + 1] = t end
      if rawget(f, "_hidden") and not t then out.hidden = true end
      f = rawget(f, "_parent")
    end
    return out
  end
  local function Val(it)
    local ok, v = pcall(it.get or function() end)
    if not ok then return nil end
    if it.kind == "check" then return v and true or false end
    if it.kind == "slider" then
      local ok2, s = pcall(string.format, it.fmt or "%d", tonumber(v) or 0)
      return ok2 and s or tostring(v)
    end
    if it.kind == "cycle" then
      local list = it.choices
      if type(list) == "function" then local ok3, l = pcall(list); list = ok3 and l or {} end
      for _, c in ipairs(list or {}) do if not c.header and c.value == v then return c.text end end
      return v ~= nil and tostring(v) or "-"
    end
    if it.kind == "color" then
      if type(v) ~= "table" then return "ffffff" end
      return ("%02x%02x%02x"):format(math.floor((v.r or 1) * 255 + 0.5), math.floor((v.g or 1) * 255 + 0.5), math.floor((v.b or 1) * 255 + 0.5))
    end
  end
  local out, placed = {}, {}
  local function Emit(d, f, chain)
    d.chain = {}
    for i, t in ipairs(chain) do d.chain[i] = { g = t.g, id = t.id } end
    d.hidden = chain.hidden or (f and rawget(f, "_hidden")) or false
    out[#out + 1] = d
    if f then placed[f] = d end
  end
  for _, t in ipairs(TILES) do
    local x, y = Pos(t.f)
    Emit({ type = "tile", x = x, y = y, w = rawget(t.f, "_w"), h = rawget(t.f, "_h"), text = t.title,
      icon = (t.icon or ""):match("([^\\]+)$") }, t.f, Chain(t.f))
  end
  for _, c in ipairs(COLS) do
    local px, py = Pos(c.parent)
    local chain = Chain(c.parent)
    for _, it in ipairs(c.items) do
      local f = it.f
      local d = { type = it.kind, x = px + c.x, y = py + it.y, w = c.width, h = it.h, text = it.text }
      if it.kind == "add" then
        local kind = rawget(f, "_kind")
        d.type = kind or "frame"
        d.text = rawget(f, "_text")
        d.w = rawget(f, "_w") or c.width
        d.h = (kind == "list" and rawget(f, "_h")) or (kind and 20) or it.h
        if kind == "list" then
          d.rows, d.rowH = rawget(f, "_rows"), rawget(f, "_rowH")
          d.data = {}
          for i, e in ipairs(rawget(f, "_data") or {}) do
            if i > d.rows then break end
            local ok, n = pcall(m.EntryName or tostring, e)
            -- spell / item names come from the game: without it, the ID
            if not ok or type(n) ~= "string" then
              n = type(e) == "table" and ((e.stance and "Stance / form") or (e.weapon and tostring(e.weapon)) or e.name
                or ((e.t == "i" and "Item " or "Spell ") .. tostring(e.id))) or "?"
            end
            d.data[i] = { name = n, off = type(e) == "table" and e.off and true or false }
          end
        end
      elseif it.kind == "button" then
        d.text = rawget(f, "_text") or it.text
      else
        d.value = Val(it)
      end
      Emit(d, f, chain)
    end
  end
  -- buttons beside another one (SetPoint LEFT of / RIGHT of), and the page's bottom buttons
  for _ = 1, 4 do
    for _, f in ipairs(FRAMES) do
      if not placed[f] then
        local b = rawget(f, "_beside")
        local a = rawget(f, "_anchor")
        local base = b and placed[b[1]]
        if base then
          Emit({ type = rawget(f, "_kind"), x = base.x + (base.w or 0) + b[2], y = base.y, w = rawget(f, "_w") or 60, h = 20,
            text = rawget(f, "_text") }, f, Chain(rawget(f, "_parent")))
        elseif a and rawget(f, "_parent") == page then
          local w = rawget(f, "_w") or 120
          local x = a[1] == "BOTTOMRIGHT" and (698 + a[2] - w) or a[2]
          Emit({ type = rawget(f, "_kind"), x = x, y = -(564 - a[3] - 20), w = w, h = 20, text = rawget(f, "_text") }, f, {})
        end
      end
    end
  end
  local tabs = {}
  for i, t in ipairs(TABS) do
    local list = {}
    for j, e in ipairs(t.list) do list[j] = { id = e[1], text = e[2], icon = e[3] or e.icon or "INV_Misc_Gear_01" } end
    local x, y = Pos(t.owner)
    tabs[i] = { list = list, x = x, y = y, owner = rawget(t.owner, "_tab") and { g = rawget(t.owner, "_tab").g, id = rawget(t.owner, "_tab").id } or false }
  end
  return { items = out, tabs = tabs, intros = INTROS, sync = m.M.sync and true or false }
end'''


def py(v):
    """lupa table -> plain Python (lists for 1..n tables)."""
    if hasattr(v, "items") and callable(getattr(v, "items")) and type(v).__name__ == "_LuaTable":
        d = {k: py(x) for k, x in v.items()}
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[i] for i in range(1, len(d) + 1)]
        return d
    return v


FOLDERS = ["MMT_CooldownTimers", "MMT_BuffTimers", "MMT_Totems", "MMT_PawnCompare", "MMT_TeamGear",
           "MMT_TeamInventory", "MMT_Whispers", "MMT_QoL", "MMT_qStyles"]


def build(folder):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute(RECORD)
    toc_lines = open(os.path.join(folder, folder + ".toc"), encoding="utf-8").read().splitlines()
    title = next((l.split(":", 1)[1].strip() for l in toc_lines if l.startswith("## X-MMT-Title:")), folder)
    files = [l.strip() for l in toc_lines if l.strip().endswith(".lua")]
    mod = lua.eval("{}")
    for f in files:
        lua.eval('function(src, name, m) assert(loadstring(src, name))("x", m) end')(
            open(os.path.join(folder, f), encoding="utf-8").read(), folder + "/" + f, mod)
    lua.eval(TABS_WRAP)(mod)
    page = lua.eval("function() local p = STUB(); rawset(p, '_h', 564); rawset(p, '_w', 698); return p end")()
    lua.eval("function(m, page) m.M.Page(m.M, page); if rawget(page, 'OnRefresh') then pcall(page.OnRefresh) end end")(mod, page)
    data = py(lua.eval(EXPORT)(mod, page))
    data["title"] = title
    data["folder"] = folder
    return data


def views(data):
    """[(label, {group: tab id})]: each top tab, and each sub-tab of a tab that has them."""
    tabs = data.get("tabs") or []
    if not tabs:
        return [("Settings", {})]
    out = []
    tops = [i + 1 for i, t in enumerate(tabs) if not t["owner"]]
    for g in tops:
        for e in tabs[g - 1]["list"]:
            subs = [i + 1 for i, t in enumerate(tabs) if t["owner"] and t["owner"]["g"] == g and t["owner"]["id"] == e["id"]]
            if subs:
                for sg in subs:
                    for se in tabs[sg - 1]["list"]:
                        out.append(("%s > %s" % (e["text"], se["text"]), {g: e["id"], sg: se["id"]}))
            else:
                out.append((e["text"], {g: e["id"]}))
    return out


def shown(item, sel):
    if item.get("hidden"):
        return False
    for c in item.get("chain") or []:
        if sel.get(c["g"]) != c["id"]:
            return False
    return True


ICON = "https://wow.zamimg.com/images/wow/icons/medium/%s.jpg"


def icon(name, size):
    name = (name or "inv_misc_questionmark").lower()
    return ('<img class="ic" src="%s" style="width:%dpx;height:%dpx" alt="" '
            'onerror="this.style.visibility=\'hidden\'">' % (ICON % html.escape(name), size, size))


def esc(t):
    return html.escape(str(t if t is not None else ""))


def render_view(data, sel):
    parts = []
    tabs = data.get("tabs") or []
    for gi, t in enumerate(tabs, 1):
        if t["owner"] and sel.get(t["owner"]["g"]) != t["owner"]["id"]:
            continue
        n = len(t["list"])
        bw = (698 - 6 * (n - 1)) // n
        x0, y0 = t["x"], -t["y"]
        parts.append('<div class="tabline" style="left:%dpx;top:%dpx"></div>' % (x0, y0 + 26))
        for i, e in enumerate(t["list"]):
            on = sel.get(gi) == e["id"]
            parts.append('<div class="tab%s" style="left:%dpx;top:%dpx;width:%dpx">%s<span>%s</span></div>'
                         % (" on" if on else "", x0 + i * (bw + 6), y0, bw, icon(e["icon"], 16), esc(e["text"])))
    if data.get("intros") and not tabs:
        parts.append('<div class="intro" style="left:0;top:0">%s</div>' % esc(data["intros"][0]))
    for it in data["items"]:
        if not shown(it, sel):
            continue
        k, x, y, w, h = it["type"], it["x"], -it["y"], it.get("w") or 100, it.get("h") or 20
        if k == "tile":
            parts.append('<div class="tile" style="left:%dpx;top:%dpx;width:%dpx;height:%dpx">'
                         '<div class="tt">%s<span>%s</span></div><div class="tl"></div></div>'
                         % (x, y, w - 2, h - 2, icon(it.get("icon"), 22), esc(it.get("text"))))
        elif k == "header":
            parts.append('<div class="hdr" style="left:%dpx;top:%dpx;width:%dpx">%s</div>' % (x, y, w, esc(it["text"])))
        elif k == "note":
            parts.append('<div class="note" style="left:%dpx;top:%dpx;width:%dpx">%s</div>' % (x, y, w, esc(it["text"])))
        elif k == "check":
            parts.append('<div class="chk" style="left:%dpx;top:%dpx;width:%dpx"><i class="%s"></i>%s</div>'
                         % (x, y + 2, w, "x" if it.get("value") else "", esc(it["text"])))
        elif k == "slider":
            lo, hi = it.get("lo") or 0, it.get("hi") or 1
            try:
                frac = (float(it.get("value") or lo) - lo) / ((hi - lo) or 1)
            except ValueError:
                frac = 0.5
            frac = min(1, max(0, frac))
            parts.append('<div class="sld" style="left:%dpx;top:%dpx;width:%dpx"><span>%s</span><b>%s</b>'
                         '<div class="trk"><div class="thumb" style="left:%dpx"></div></div></div>'
                         % (x, y, w, esc(it["text"]), esc(it.get("value")), int(frac * (w - 8))))
        elif k == "cycle":
            parts.append('<div class="btn cyc" style="left:%dpx;top:%dpx;width:%dpx"><span>%s</span><b>%s</b><em>v</em></div>'
                         % (x, y, w - 2, esc(it["text"]), esc(it.get("value"))))
        elif k == "color":
            parts.append('<div class="btn cyc" style="left:%dpx;top:%dpx;width:%dpx"><span>%s</span>'
                         '<small>#%s</small><i class="sw" style="background:#%s"></i></div>'
                         % (x, y, w - 2, esc(it["text"]), esc(it.get("value")), esc(it.get("value"))))
        elif k == "button":
            parts.append('<div class="btn" style="left:%dpx;top:%dpx;width:%dpx">%s</div>' % (x, y, w - 2, esc(it.get("text"))))
        elif k == "tbutton":
            parts.append('<div class="tbtn" style="left:%dpx;top:%dpx;width:%dpx">%s</div>' % (x, y, w, esc(it.get("text"))))
        elif k == "edit":
            parts.append('<div class="edit" style="left:%dpx;top:%dpx;width:%dpx">%s</div>' % (x, y, w - 2, esc(it.get("text"))))
        elif k == "list":
            rows = []
            for i in range(it.get("rows") or 0):
                e = (it.get("data") or [None] * 99)[i] if i < len(it.get("data") or []) else None
                rows.append('<div class="row%s" style="height:%dpx">%s</div>'
                            % (" odd" if i % 2 else "", (it.get("rowH") or 22),
                               ('<span class="grip">::</span>%s<span class="rt">%s x</span>'
                                % (esc(e["name"]), "off" if e["off"] else '<g>on</g>')) if e else ""))
            parts.append('<div class="list" style="left:%dpx;top:%dpx;width:%dpx">%s</div>' % (x, y, w, "".join(rows)))
        elif k == "frame":
            parts.append('<div class="frm" style="left:%dpx;top:%dpx;width:%dpx;height:%dpx">custom widget</div>'
                         % (x, y, w - 2, max(10, h - 6)))
    if data.get("sync"):
        parts.append('<div class="btn" style="left:%dpx;top:%dpx;width:174px">Sync to team</div>' % (698 - 176, 564 - 22))
    return "".join(parts)


CSS = """
:root{--a:79,179,255}
*{box-sizing:border-box}
body{margin:0;background:#0b0b0d;color:#e6e6e6;font:13px/1.3 "Segoe UI",Arial,sans-serif;display:flex;min-height:100vh}
nav{width:250px;flex:none;background:#111114;border-right:1px solid #222;padding:12px 0;overflow:auto;max-height:100vh;position:sticky;top:0}
nav h1{font-size:14px;margin:0 14px 10px;color:rgb(var(--a))}
nav h2{font-size:12px;margin:12px 14px 4px;color:#ffd100;font-weight:600}
nav a{display:block;padding:3px 14px 3px 24px;color:#bbb;text-decoration:none;font-size:12px;cursor:pointer}
nav a:hover{background:#1b1b20}nav a.on{color:#fff;background:rgba(var(--a),.18)}
main{flex:1;padding:20px;overflow:auto}
.cap{color:#888;font-size:12px;margin:0 0 10px}
.cap b{color:#ffd100;font-weight:600}
.win{background:rgba(13,13,15,.96);border:1px solid rgba(var(--a),.5);padding:14px;display:inline-block;transform-origin:0 0}
.page{position:relative;width:698px;height:564px;font:11px/1.25 Arial,sans-serif}
.page>*{position:absolute}
.ic{border:1px solid #000;vertical-align:middle;object-fit:cover}
.tab{height:26px;display:flex;align-items:center;gap:6px;padding-left:6px;color:#b3b3b3;font:12px Georgia,serif;white-space:nowrap;overflow:hidden}
.tab.on{color:rgb(var(--a));border-bottom:2px solid rgba(var(--a),.9)}
.tabline{width:698px;height:1px;background:rgba(255,255,255,.08)}
.intro{width:698px;color:#bfbfbf}
.tile{background:rgba(var(--a),.04);border:1px solid rgba(var(--a),.30)}
.tile .tt{position:absolute;left:7px;top:6px;display:flex;align-items:center;gap:8px;color:rgb(var(--a));font:15px Georgia,serif;white-space:nowrap}
.tile .tl{position:absolute;left:7px;right:7px;top:33px;height:1px;background:rgba(var(--a),.35)}
.hdr{color:#ffd100;font:12px Georgia,serif;border-bottom:1px solid rgba(255,255,255,.08);height:17px}
.note{color:#999}
.chk{height:18px;display:flex;align-items:center;gap:8px;white-space:nowrap;overflow:hidden}
.chk i{width:14px;height:14px;flex:none;background:#1f1f1f;border:1px solid #595959;position:relative}
.chk i.x:after{content:"";position:absolute;inset:2px;background:rgb(var(--a))}
.sld{height:32px}.sld span{position:absolute;left:0;top:0}.sld b{position:absolute;right:0;top:0;font-weight:normal}
.trk{position:absolute;left:0;right:0;top:19px;height:4px;background:#2e2e2e}
.thumb{position:absolute;top:-4px;width:8px;height:12px;background:rgb(var(--a))}
.btn{height:20px;background:#1f1f1f;border:1px solid #404040;display:flex;align-items:center;justify-content:center;white-space:nowrap;overflow:hidden}
.cyc{justify-content:flex-start;padding:0 7px 0 8px;gap:8px}.cyc b{margin-left:auto;color:rgb(var(--a));font-weight:normal;overflow:hidden;text-overflow:ellipsis}
.cyc em{color:#999;font-style:normal}.cyc small{margin-left:auto;color:#999;font-size:11px}
.sw{width:28px;height:12px;border:1px solid #737373;flex:none}
.tbtn{height:18px;color:#999;text-align:center}
.edit{height:20px;background:#17171a;border:1px solid #404040;color:#737373;padding:3px 6px;white-space:nowrap;overflow:hidden}
.list .row{display:flex;align-items:center;gap:6px;padding:0 4px;background:rgba(255,255,255,.02)}
.list .row.odd{background:rgba(255,255,255,.05)}
.list .grip{color:#555}.list .rt{margin-left:auto;color:#999}.list g{color:#55ff55}
.frm{border:1px dashed #444;color:#555;display:flex;align-items:center;justify-content:center}
"""

JS = """
const V=window.VIEWS;const nav=document.querySelector('nav');const main=document.querySelector('main');
let last=null;
V.forEach((m,mi)=>{const h=document.createElement('h2');h.textContent=m.title;nav.appendChild(h);
 m.views.forEach((v,vi)=>{const a=document.createElement('a');a.textContent=v.label;a.onclick=()=>show(mi,vi,a);nav.appendChild(a);
 if(!last)last=[mi,vi,a];});});
function show(mi,vi,a){document.querySelectorAll('nav a').forEach(x=>x.classList.remove('on'));a.classList.add('on');
 const m=V[mi],v=m.views[vi];
 main.innerHTML='<p class="cap"><b>'+m.title+'</b> &middot; '+v.label+' &mdash; layout mockup from the test harness, not a game screenshot</p>'+
 '<div class="win"><div class="page">'+v.html+'</div></div>';}
show(...last);
"""


def main():
    out = []
    for folder in FOLDERS:
        data = build(folder)
        vs = [{"label": label, "html": render_view(data, sel)} for label, sel in views(data)]
        out.append({"title": data["title"], "views": vs})
        print("%-20s %d view(s)" % (folder, len(vs)))
    os.makedirs("dist", exist_ok=True)
    path = os.path.join("dist", "settings-mockups.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
                "<title>MMT Settings Mockups</title><style>%s</style></head><body><nav><h1>QMMT Modules settings</h1></nav><main></main>"
                "<script>window.VIEWS=%s;</script><script>%s</script></body></html>"
                % (CSS, json.dumps(out).replace("</", "<\\/"), JS))
    print(path)


if __name__ == "__main__":
    main()
