--[[-------------------------------------------------------------------
--  Clique - Copyright 2006-2026 - James N. Whitehead II
-------------------------------------------------------------------]]--

--- @class CliqueAddon
local addon = select(2, ...)

-- A Clique-owned proxy button isolates our dispatch from Blizzard's
-- SecureUnitButton_OnClick. Proxies are pooled (frames can't be destroyed) and
-- named, since key bindings target them by name via SetBindingClick. See
-- docs/architecture.md.
function addon:GetOrCreateProxy(frame)
    if self.proxies[frame] then return self.proxies[frame] end

    local proxy = self.proxyPool[frame]
    if not proxy then
        self.proxyCount = self.proxyCount + 1
        local proxyName = "CliqueProxy" .. self.proxyCount
        proxy = CreateFrame("Button", proxyName, frame, "SecureActionButtonTemplate")
        proxy.parentName = frame:GetName()
        self.proxyPool[frame] = proxy
    end

    proxy:SetAttribute("useparent-unit", true)
    -- Proxy is always "up": delegate:Click() sends it no down arg, so a down-mode
    -- proxy would never fire. The firing edge is chosen on the source frame instead.
    proxy:SetAttribute("useOnKeyDown", false)
    proxy:RegisterForClicks("AnyUp")

    -- First touch of the frame, before any routing write, so the backup always holds
    -- the original un-routed values.
    self.proxyBackup[frame] = {
        ["*type1"]        = frame:GetAttribute("*type1"),
        ["*type2"]        = frame:GetAttribute("*type2"),
        ["type1"]         = frame:GetAttribute("type1"),
        ["type2"]         = frame:GetAttribute("type2"),
        ["type"]          = frame:GetAttribute("type"),
        ["*type*"]        = frame:GetAttribute("*type*"),
        ["clickbutton"]   = frame:GetAttribute("clickbutton"),
        ["*clickbutton*"] = frame:GetAttribute("*clickbutton*"),
        ["clickbutton1"]  = frame:GetAttribute("clickbutton1"),
        ["clickbutton2"]  = frame:GetAttribute("clickbutton2"),
        ["*clickbutton1"] = frame:GetAttribute("*clickbutton1"),
        ["*clickbutton2"] = frame:GetAttribute("*clickbutton2"),
    }

    self.proxies[frame] = proxy
    self:RegisterProxySecure(proxy)
    return proxy
end

-- Tracks the proxy in the header's secure `proxies` table so setup_clicks/
-- remove_clicks can be re-run on it from the restricted environment. Combat-safe;
-- it's proxy creation in GetOrCreateProxy that forces callers out of combat.
function addon:RegisterProxySecure(proxy)
    self.header:SetFrameRef("clique_proxy", proxy)
    self.header:Execute([[
        proxies[self:GetFrameRef("clique_proxy")] = true
    ]])
end

function addon:UnregisterProxySecure(proxy)
    self.header:SetFrameRef("clique_proxy", proxy)
    self.header:Execute([[
        proxies[self:GetFrameRef("clique_proxy")] = nil
    ]])
end

-- The full set of routing state Clique owns on a source frame. Centralized so
-- the register-time writer and the reassert path can't drift apart.
local function writeRouting(frame, proxy)
    frame:SetAttribute("*type1", "click")
    frame:SetAttribute("*type2", "click")
    frame:SetAttribute("type", "click")
    frame:SetAttribute("*type*", "click")
    -- Some unit frames (e.g. Dander's) set the specific type1/type2 directly.
    -- Those win over the *type wildcards in attribute resolution, so the click
    -- never reaches the proxy unless we override them too.
    frame:SetAttribute("type1", "click")
    frame:SetAttribute("type2", "click")
    -- A modified-click resolves clickbutton via *clickbutton<N>, clickbutton<N>,
    -- *clickbutton*, clickbutton -- most-specific first. A bare clickbutton loses
    -- to any variant a unit frame addon writes (e.g. EllesmereUI's *clickbutton2),
    -- so take over the whole set to keep the click on our proxy.
    frame:SetAttribute("clickbutton", proxy)
    frame:SetAttribute("*clickbutton*", proxy)
    frame:SetAttribute("clickbutton1", proxy)
    frame:SetAttribute("clickbutton2", proxy)
    frame:SetAttribute("*clickbutton1", proxy)
    frame:SetAttribute("*clickbutton2", proxy)
    -- Plain-string name for the OnEnter snippet to pass to SetBindingClick.
    frame:SetAttribute("clique_proxyname", proxy:GetName())
    -- The source ignores useOnKeyDown, so its RegisterForClicks is the only lever
    -- that selects press vs. release.
    frame:RegisterForClicks(addon:GetButtonDirections())
end

-- Routes the frame's clicks to the proxy. The original attributes were already
-- snapshotted in GetOrCreateProxy, so this is a pure writer.
function addon:SetupFrameClickRouting(frame, proxy)
    writeRouting(frame, proxy)
end

-- Re-stamp our routing after something else overwrote it. Unit frame addons
-- re-run their own secure setup (e.g. *type1="target") on rebuilds; Blizzard
-- does it via CompactUnitFrame_SetUnit, third-party frames via their own paths.
-- Blocked in combat, so queue and reassert on PLAYER_REGEN_ENABLED.
function addon:ReassertFrameClickRouting(frame)
    local proxy = self.proxies[frame]
    if not proxy then return end

    -- A frame denylisted after registration keeps its proxy (BLACKLIST_CHANGED
    -- doesn't tear it down), so guard here rather than trusting self.proxies.
    if self:IsFrameBlacklisted(frame) then return end

    if InCombatLockdown() then
        self.reassertqueue[frame] = true
        return
    end

    writeRouting(frame, proxy)
end

-- Reassert routing on every proxied frame. The old direct-attribute model got
-- this for free by re-running setup_clicks on each frame in ApplyAttributes; the
-- proxy model writes frame routing once at registration, so we reassert here on
-- the re-apply path (binding change, PEW) to heal clobbers. Combat exit heals
-- only the frames the SetUnit hook queued, not the full set -- see LeavingCombat.
function addon:ReassertAllFrameClickRouting()
    for frame in pairs(self.proxies) do
        self:ReassertFrameClickRouting(frame)
    end
end

-- Removes click routing from a frame and restores its original attribute values.
function addon:TeardownFrameClickRouting(frame)
    local backup = self.proxyBackup[frame]
    if backup then
        frame:SetAttribute("*type1", backup["*type1"])
        frame:SetAttribute("*type2", backup["*type2"])
        frame:SetAttribute("type1", backup["type1"])
        frame:SetAttribute("type2", backup["type2"])
        frame:SetAttribute("type", backup["type"])
        frame:SetAttribute("*type*", backup["*type*"])
        frame:SetAttribute("clickbutton", backup["clickbutton"])
        frame:SetAttribute("*clickbutton*", backup["*clickbutton*"])
        frame:SetAttribute("clickbutton1", backup["clickbutton1"])
        frame:SetAttribute("clickbutton2", backup["clickbutton2"])
        frame:SetAttribute("*clickbutton1", backup["*clickbutton1"])
        frame:SetAttribute("*clickbutton2", backup["*clickbutton2"])
        self.proxyBackup[frame] = nil
    end

    local proxy = self.proxies[frame]
    if proxy then
        self:UnregisterProxySecure(proxy)
    end
    self.proxies[frame] = nil
end
