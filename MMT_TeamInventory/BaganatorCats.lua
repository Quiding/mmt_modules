-- MMT Team Inventory: the team bags in Baganator's categories.
-- When Baganator is on, its category setup is read from its profile
-- (BAGANATOR_CONFIG, read only) every time the window is drawn, so a change
-- there shows here too:
--   * the display order and hidden categories
--   * custom categories (name + search) and the items dragged into a category
--   * priorities (an item goes to the highest-priority category whose search
--     matches; same priority: the earlier one in the order), like Baganator
-- Searches are checked with Syndicator's public search (Syndicator.Search).
-- Baganator's default categories are private, so their searches are built
-- here the same way Baganator builds them on Forever. Its automatic
-- categories (Recent, equipment sets, inventory slots, empty slots) only make
-- sense for your own live bags and are left out. Anything unexpected: nil, and
-- the window uses the built-in categories instead.

local _, mod = ...
local MMT = MMT

local function ClassName(e)
    local ok, n = pcall(C_Item.GetItemClassInfo, e)
    return ok and type(n) == "string" and n or nil
end

-- Baganator's default categories on Forever: source -> name, search, priority offset
local function Defaults()
    local L = Syndicator and Syndicator.Locales or {}
    local C = Enum and Enum.ItemClass or {}
    local d = {}
    local function Add(key, name, search, offset)
        if name and search then d["default_" .. key] = { name = name, search = search, offset = offset or -70 } end
    end
    local function Class(e) local n = e and ClassName(e) return n and ("#" .. n:lower()) end
    local hearth = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(6948)) or "Hearthstone"
    Add("hearthstone", hearth, hearth:lower() .. "&#" .. (ITEM_UNIQUE or "unique"):lower() .. "&#" .. (ITEM_SOULBOUND or "soulbound"):lower(), -10)
    Add("consumable", ClassName(C.Consumable), Class(C.Consumable))
    Add("reagent", L.KEYWORD_REAGENT and (L.KEYWORD_REAGENT:sub(1, 1):upper() .. L.KEYWORD_REAGENT:sub(2)), L.KEYWORD_REAGENT and ("#" .. L.KEYWORD_REAGENT), -50)
    Add("weapon", ClassName(C.Weapon), Class(C.Weapon))
    Add("armor", ClassName(C.Armor), L.KEYWORD_GEAR and Class(C.Armor) and (Class(C.Armor) .. "&#" .. L.KEYWORD_GEAR))
    Add("container", ClassName(C.Container), Class(C.Container))
    Add("tradegoods", ClassName(C.Tradegoods), Class(C.Tradegoods))
    Add("recipe", ClassName(C.Recipe), Class(C.Recipe))
    Add("questitem", ClassName(C.Questitem), Class(C.Questitem), -65)
    Add("miscellaneous", ClassName(C.Miscellaneous), L.KEYWORD_GEAR and Class(C.Miscellaneous) and (Class(C.Miscellaneous) .. "&!#" .. L.KEYWORD_GEAR), -30)
    Add("other", OTHER or "Other", "", -90)
    Add("junk", L.KEYWORD_JUNK and (L.KEYWORD_JUNK:sub(1, 1):upper() .. L.KEYWORD_JUNK:sub(2)) or "Junk", L.KEYWORD_JUNK and ("#" .. L.KEYWORD_JUNK), -15)
    Add("projectile", ClassName(C.Projectile), Class(C.Projectile))
    Add("quiver", ClassName(C.Quiver), Class(C.Quiver))
    local key = L.KEYWORD_KEY or L.KEYWORD_KEYRING
    Add("key", ClassName(C.Key) or "Key", key and ("#" .. key), -35)
    return d
end

-- Baganator's current setup: { list = { {source, name, search, added} } in display
-- order, prio = the same entries by priority }, or nil
local function Setup()
    if not (Baganator and Syndicator and Syndicator.Search and Syndicator.Search.CheckItem and Syndicator.Search.GetBaseInfo) then return nil end
    local profiles = type(BAGANATOR_CONFIG) == "table" and BAGANATOR_CONFIG.Profiles
    local cfg = type(profiles) == "table" and profiles[BAGANATOR_CURRENT_PROFILE or "DEFAULT"]
    local order = type(cfg) == "table" and cfg.category_display_order
    if type(order) ~= "table" or #order == 0 then return nil end
    local custom = type(cfg.custom_categories) == "table" and cfg.custom_categories or {}
    local mods = type(cfg.category_modifications) == "table" and cfg.category_modifications or {}
    local hidden = type(cfg.category_hidden) == "table" and cfg.category_hidden or {}
    local defaults = Defaults()
    local list = {}
    for index, source in ipairs(order) do
        if type(source) == "string" then
            local m = type(mods[source]) == "table" and mods[source] or {}
            local prio = m.priority and (m.priority + 1) * 200 or 0
            local added = {}
            for k in pairs(type(m.addedItems) == "table" and m.addedItems or {}) do
                local id = type(k) == "string" and tonumber(k:match("^i:(%d+)"))
                if id then added[id] = true end
            end
            local def, cus = defaults[source], custom[source]
            local entry
            if def then
                entry = { source = source, name = def.name, search = def.search, prio = def.offset + prio }
            elseif type(cus) == "table" and type(cus.search) == "string" then
                entry = { source = source, name = cus.name or source, search = cus.search:lower(), prio = prio }
            end
            if entry then
                entry.index, entry.added, entry.hidden = index, added, hidden[source] and true or false
                list[#list + 1] = entry
            end
        end
    end
    if #list == 0 then return nil end
    local prio = {}
    for i, e in ipairs(list) do prio[i] = e end
    table.sort(prio, function(a, b)
        if a.prio ~= b.prio then return a.prio > b.prio end
        return a.index < b.index
    end)
    return { list = list, prio = prio }
end

local details = {}   -- [itemID] = Syndicator search details (it caches its matches in them)

local function Matches(slot, search)
    if search == "" then return true end
    local d = details[slot.id]
    if not d then
        d = Syndicator.Search.GetBaseInfo({ itemLink = slot.link or ("item:" .. slot.id), itemID = slot.id,
            quality = slot.quality, itemCount = slot.count })
        if slot.link then details[slot.id] = d end   -- without a link the item isn't loaded yet
    end
    local ok, r = pcall(Syndicator.Search.CheckItem, d, search)
    return ok and r == true
end

-- slots -> { { name, slots }, ... } in Baganator's display order (hidden left
-- out), or nil when Baganator's categories can't be used
function mod.BaganatorGroups(slots)
    local ok, setup = pcall(Setup)
    if not ok or not setup then return nil end
    local by = {}
    for _, s in ipairs(slots) do
        local home
        for _, e in ipairs(setup.prio) do
            if e.added[s.id] then home = e break end
        end
        if not home then
            for _, e in ipairs(setup.prio) do
                if Matches(s, e.search) then home = e break end
            end
        end
        if home then
            by[home.source] = by[home.source] or {}
            table.insert(by[home.source], s)
        end
    end
    local out = {}
    for _, e in ipairs(setup.list) do
        if by[e.source] and not e.hidden then out[#out + 1] = { id = e.source, name = e.name, slots = by[e.source] } end
    end
    return out
end

function mod.HasBaganatorCategories()
    local ok, setup = pcall(Setup)
    return ok and setup ~= nil
end
