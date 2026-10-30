-- MMT Quality of life: "ask before applying".
-- Changes from the team wait in a queue: one dialog per sender and feature,
-- and what the same sender sends while it waits joins that dialog.

local _, mod = ...
local MMT = MMT

local queue = {}   -- { from, feature, lines = {}, applies = {}, ignores = {} }
local showing

local function ShowNext()
    if showing or #queue == 0 then return end
    local q = table.remove(queue, 1)
    showing = q
    local function done()
        showing = nil
        if C_Timer and C_Timer.After then C_Timer.After(0, ShowNext) else ShowNext() end
    end
    -- a feature may word the dialog itself: askText(who, n), askAccept
    local f = q.feature
    local head = f.askText and f.askText(MMT.FullDisplay(q.from), #q.lines)
        or ("%s sent %d %s change(s):"):format(MMT.FullDisplay(q.from), #q.lines, f.title)
    MMT.UI.Confirm(head .. "\n" .. mod.Summary(q.lines, 4), f.askAccept or "Apply", function()
        for _, fn in ipairs(q.applies) do
            local ok, err = pcall(fn)
            if not ok then mod.M:Debug("apply failed: %s", tostring(err)) end
        end
        done()
    end, "Ignore", function()
        for _, fn in ipairs(q.ignores) do pcall(fn) end
        done()
    end)
end

-- lines = what it does ("+ [Linen Cloth] to junk"), apply() does it,
-- ignored() (optional) runs on Ignore
function mod.Ask(from, feature, lines, apply, ignored)
    for _, q in ipairs(queue) do
        if q.from == from and q.feature == feature then
            for _, l in ipairs(lines) do q.lines[#q.lines + 1] = l end
            q.applies[#q.applies + 1] = apply
            q.ignores[#q.ignores + 1] = ignored
            return
        end
    end
    local q = { from = from, feature = feature, lines = {}, applies = { apply }, ignores = { ignored } }
    for _, l in ipairs(lines) do q.lines[#q.lines + 1] = l end
    queue[#queue + 1] = q
    ShowNext()
end

-- for the debug report
function mod.AskWaiting() return #queue + (showing and 1 or 0) end
