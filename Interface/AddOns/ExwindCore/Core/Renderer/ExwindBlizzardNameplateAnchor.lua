-- Blizzard 原生姓名板锚点：仅解析 Frame 引用，不读取/比较单位状态或秘密值。
-- 第三方姓名板必须各自实现 adapter；不能把其布局伪装成原生布局。

local ExwindTools = _G.ExwindTools
if type(ExwindTools) ~= "table" or type(ExwindTools.UI) ~= "table" then
    error("ExwindBlizzardNameplateAnchor requires initialized EXUI", 0)
end

local EXUI = ExwindTools.UI
if EXUI.BlizzardNameplateAnchorInitialized then
    error("ExwindBlizzardNameplateAnchor already initialized", 0)
end
EXUI.BlizzardNameplateAnchorInitialized = true

local NAMEPLATE_BACKENDS = {
    { addonName = "Plater", backend = "plater" },
    { addonName = "Platynator", backend = "platynator" },
    { addonName = "EllesmereUINameplates", backend = "ellesmere" },
    { addonName = "PlateColor", backend = "platecolor" },
}

-- Add-on presence is session-static in the supported workflow.  Resolve it
-- once after all normal add-ons finish loading; hot paths only read this table.
local nameplateBackendCache = { ready = false, backend = "blizzard", addonName = nil }

local function IsAddonLoaded(addonName)
    local api = _G.C_AddOns
    if type(api) == "table" and type(api.IsAddOnLoaded) == "function" then
        return api.IsAddOnLoaded(addonName) == true
    end
    local legacy = _G.IsAddOnLoaded
    return type(legacy) == "function" and legacy(addonName) == true
end

local function RefreshNameplateBackendCache()
    nameplateBackendCache.backend, nameplateBackendCache.addonName = "blizzard", nil
    for _, entry in ipairs(NAMEPLATE_BACKENDS) do
        if IsAddonLoaded(entry.addonName) then
            nameplateBackendCache.backend = entry.backend
            nameplateBackendCache.addonName = entry.addonName
            break
        end
    end
    nameplateBackendCache.ready = true
end

function EXUI:RefreshNameplateBackendCache()
    RefreshNameplateBackendCache()
    return nameplateBackendCache.backend
end

function EXUI:GetNameplateBackend()
    return nameplateBackendCache.backend
end

local function HasKnownThirdPartyNameplate()
    -- PlateColor only restyles and reanchors Blizzard's UnitFrame.  Its
    -- HealthBarsContainer remains the live, authoritative attachment target;
    -- unlike full replacement add-ons it must not disable the native path.
    local replacesNativeNameplate = nameplateBackendCache.backend == "plater"
        or nameplateBackendCache.backend == "platynator"
        or nameplateBackendCache.backend == "ellesmere"
    return replacesNativeNameplate, nameplateBackendCache.addonName
end

-- PLAYER_LOGIN runs after normal enabled add-ons have loaded.  Do not listen
-- to combat, nameplate, or render events: backend discovery must never become
-- a per-frame/per-unit cost.
if type(_G.CreateFrame) == "function" then
    local cacheFrame = _G.CreateFrame("Frame")
    cacheFrame:RegisterEvent("PLAYER_LOGIN")
    cacheFrame:SetScript("OnEvent", function(self)
        RefreshNameplateBackendCache()
        self:UnregisterEvent("PLAYER_LOGIN")
    end)
end

-- Returns the two native geometry meanings used by Blizzard itself:
--   container: full health-bar bounds; correct for side icons / decorations.
--   bar:       actual StatusBar fill bounds; correct for fill-attached visuals.
-- No dimensions or unit values are read.  A missing/removed nameplate simply
-- returns nil, reason, and must be hidden by the caller.
function EXUI:GetBlizzardNameplateAnchor(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil, "invalid-unit"
    end

    local hasThirdParty, addonName = HasKnownThirdPartyNameplate()
    if hasThirdParty then
        return nil, "third-party-nameplate-active:" .. addonName
    end

    local api = _G.C_NamePlate
    if type(api) ~= "table" or type(api.GetNamePlateForUnit) ~= "function" then
        return nil, "nameplate-api-unavailable"
    end

    local plate = api.GetNamePlateForUnit(unit)
    if not plate then return nil, "nameplate-not-visible" end

    local unitFrame = plate.UnitFrame or plate.unitFrame
    if not unitFrame then return nil, "native-unit-frame-unavailable" end

    local container = unitFrame.HealthBarsContainer
    local bar = container and container.healthBar or unitFrame.healthBar
    if not container or not bar then return nil, "native-health-bar-unavailable" end

    return {
        backend = "blizzard",
        unit = unit,
        plate = plate,
        unitFrame = unitFrame,
        container = container,
        bar = bar,
    }, nil
end

local PLATER_NAME_ANCHORS = {
    [1] = { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", justifyH = "LEFT" },
    [2] = { point = "RIGHT", relativePoint = "LEFT", justifyH = "LEFT" },
    [3] = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", justifyH = "LEFT" },
    [4] = { point = "TOP", relativePoint = "BOTTOM", justifyH = "CENTER" },
    [5] = { point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT", justifyH = "RIGHT" },
    [6] = { point = "LEFT", relativePoint = "RIGHT", justifyH = "RIGHT" },
    [7] = { point = "BOTTOMRIGHT", relativePoint = "TOPRIGHT", justifyH = "RIGHT" },
    [8] = { point = "BOTTOM", relativePoint = "TOP", justifyH = "CENTER" },
    [9] = { point = "CENTER", relativePoint = "CENTER", justifyH = "CENTER" },
    [10] = { point = "LEFT", relativePoint = "LEFT", justifyH = "LEFT" },
    [11] = { point = "RIGHT", relativePoint = "RIGHT", justifyH = "RIGHT" },
    [12] = { point = "TOP", relativePoint = "TOP", justifyH = "CENTER" },
    [13] = { point = "BOTTOM", relativePoint = "BOTTOM", justifyH = "CENTER" },
    [14] = { point = "TOPLEFT", relativePoint = "TOPLEFT", justifyH = "LEFT" },
    [15] = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", justifyH = "LEFT" },
    [16] = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", justifyH = "RIGHT" },
    [17] = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", justifyH = "RIGHT" },
}

local function FetchLSM(kind, name)
    local libStub = _G.LibStub
    -- WoW's LibStub is a table with GetLibrary (and may additionally be
    -- callable through a metatable).  Checking only type == "function" made
    -- every real client fall through to the EXBoss fallback texture.
    local lsm = nil
    if type(libStub) == "table" and type(libStub.GetLibrary) == "function" then
        lsm = libStub:GetLibrary("LibSharedMedia-3.0", true)
    elseif type(libStub) == "function" then
        lsm = libStub("LibSharedMedia-3.0", true)
    end
    if lsm and type(lsm.Fetch) == "function" and type(name) == "string" and name ~= "" then
        -- Match Plater's own call exactly.
        local path = lsm:Fetch(kind, name)
        if type(path) == "string" and path ~= "" then return path end
    end
    return nil
end

local function Color(source, fallback)
    source = type(source) == "table" and source or fallback
    return {
        r = tonumber(source and (source.r or source[1])) or fallback[1],
        g = tonumber(source and (source.g or source[2])) or fallback[2],
        b = tonumber(source and (source.b or source[3])) or fallback[3],
        a = tonumber(source and (source.a or source[4])) or fallback[4],
    }
end

-- Plain preview data for a hostile NPC under the player's active Plater profile.
-- This is intentionally not a live unit query: threat, quest, and per-NPC script
-- colors can differ per visible unit, so a settings preview uses Plater's hostile
-- profile color instead of pretending there is one universal runtime color.
function EXUI:GetPlaterEnemyNPCPreviewStyle()
    if nameplateBackendCache.backend ~= "plater" then return nil end
    local plater = _G.Plater
    local profile = plater and plater.db and plater.db.profile
    local npc = profile and profile.plate_config and profile.plate_config.enemynpc
    if type(profile) ~= "table" or type(npc) ~= "table" then return nil end

    local inCombat = type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
    local size = (inCombat and type(npc.health_incombat) == "table" and npc.health_incombat)
        or npc.health
        or npc.health_incombat
        or {}
    local hostileColor = profile.color_override == true
        and type(profile.color_override_colors) == "table"
        and profile.color_override_colors[3]
        or nil
    local nameAnchor = PLATER_NAME_ANCHORS[tonumber(npc.actorname_text_anchor and npc.actorname_text_anchor.side) or 4]
        or PLATER_NAME_ANCHORS[4]
    local nameOffset = type(npc.actorname_text_anchor) == "table" and npc.actorname_text_anchor or {}

    return {
        backend = "plater",
        width = math.max(1, tonumber(size[1]) or 112),
        height = math.max(1, tonumber(size[2]) or 12),
        texture = FetchLSM("statusbar", profile.health_statusbar_texture),
        color = Color(hostileColor, { 0.78, 0.08, 0.08, 1 }),
        -- Plater's health-bar background has an independent LSM material and
        -- color.  Keep these plain values so consumers can present the same
        -- profile appearance without ever touching a real nameplate.
        backgroundTexture = FetchLSM("statusbar", profile.health_statusbar_bgtexture),
        backgroundColor = Color(profile.health_statusbar_bgcolor, { 0.08, 0.08, 0.08, 1 }),
        name = {
            text = "Plater 敌对怪物",
            font = FetchLSM("font", npc.actorname_text_font),
            size = math.max(1, tonumber(npc.actorname_text_size) or 11),
            color = Color(npc.actorname_text_color, { 1, 1, 1, 1 }),
            outline = tostring(npc.actorname_text_outline or "NONE"),
            shadowColor = Color(npc.actorname_text_shadow_color, { 0, 0, 0, 1 }),
            shadowX = tonumber(npc.actorname_text_shadow_color_offset and npc.actorname_text_shadow_color_offset[1]) or 1,
            shadowY = tonumber(npc.actorname_text_shadow_color_offset and npc.actorname_text_shadow_color_offset[2]) or -1,
            anchor = {
                point = nameAnchor.point, relativePoint = nameAnchor.relativePoint,
                x = tonumber(nameOffset.x) or 0, y = tonumber(nameOffset.y) or 0,
                justifyH = nameAnchor.justifyH,
            },
        },
    }
end

-- Ellesmere publishes its active profile and the exact helpers its own
-- nameplates use.  This adapter deliberately reads those public values only;
-- it never walks a visible plate or inspects a unit.
function EXUI:GetEllesmereEnemyNPCPreviewStyle()
    if nameplateBackendCache.backend ~= "ellesmere" then return nil end
    local ns = _G.EllesmereNameplates_NS
    local eui = _G.EllesmereUI
    local profile = ns and ns.db and ns.db.profile
    local defaults = ns and ns.defaults
    if type(ns) ~= "table" or type(profile) ~= "table" or type(defaults) ~= "table" then return nil end
    local function Setting(key)
        local value = profile[key]
        if value == nil then value = defaults[key] end
        return value
    end
    local width = type(ns.GetHealthBarWidth) == "function" and ns.GetHealthBarWidth() or 150
    local height = type(ns.GetHealthBarHeight) == "function" and ns.GetHealthBarHeight() or 14
    local texture = nil
    if type(eui) == "table" and type(eui.ResolveTexturePath) == "function" then
        texture = eui.ResolveTexturePath(ns.healthBarTextures, Setting("healthBarTexture"), "Interface\\Buttons\\WHITE8x8")
    end
    local nameSlot = type(ns.FindNameSlot) == "function" and ns.FindNameSlot() or "textSlotTop"
    local nameMap = {
        textSlotLeft = { point = "LEFT", relativePoint = "LEFT", xBase = 4, justifyH = "LEFT" },
        textSlotCenter = { point = "CENTER", relativePoint = "CENTER", xBase = 0, justifyH = "CENTER" },
        textSlotRight = { point = "RIGHT", relativePoint = "RIGHT", xBase = -2, justifyH = "RIGHT" },
        textSlotTop = { point = "BOTTOM", relativePoint = "TOP", xBase = 0, yBase = 4, justifyH = "CENTER" },
    }
    local map = nameMap[nameSlot] or nameMap.textSlotTop
    local slotSize = tonumber(Setting(nameSlot .. "Size")) or 10
    local slotColor = Setting(nameSlot .. "Color")
    local nameOffsetY = nameSlot == "textSlotTop" and (type(ns.GetNameYOffset) == "function" and ns.GetNameYOffset() or 0) or 0

    return {
        backend = "ellesmere",
        width = math.max(1, tonumber(width) or 150), height = math.max(1, tonumber(height) or 14),
        texture = type(texture) == "string" and texture or "Interface\\Buttons\\WHITE8x8",
        color = Color(Setting("hostile"), { 0.39, 0.11, 0.09, 1 }),
        backgroundTexture = "Interface\\Buttons\\WHITE8x8",
        backgroundColor = Color(Setting("bgColor"), { 0.12, 0.12, 0.12, 1 }),
        name = {
            text = "Ellesmere 敌对怪物", font = type(ns.GetFont) == "function" and ns.GetFont() or "",
            size = math.max(1, slotSize), color = Color(slotColor, { 1, 1, 1, 1 }),
            outline = type(ns.GetNPOutline) == "function" and ns.GetNPOutline() or "OUTLINE",
            shadowColor = { r = 0, g = 0, b = 0, a = 1 }, shadowX = 1, shadowY = -1,
            anchor = {
                point = map.point, relativePoint = map.relativePoint,
                x = (map.xBase or 0) + (tonumber(Setting(nameSlot .. "XOffset")) or 0),
                y = (map.yBase or 0) + nameOffsetY + (tonumber(Setting(nameSlot .. "YOffset")) or 0),
                justifyH = map.justifyH,
            },
        },
    }
end

local PLATECOLOR_TEXTURES = {
    ["PC-White"] = "Interface\\AddOns\\PlateColor\\texture\\Bar\\WHITE8x8",
    PlateColor = "Interface\\AddOns\\PlateColor\\texture\\Bar\\HP-PlateColor",
    Rainbow = "Interface\\AddOns\\PlateColor\\texture\\Bar\\HP-rainbow",
    ["PC-BarFill"] = "Interface\\AddOns\\PlateColor\\texture\\Bar\\HP-PC-BarFill",
    ["PC-3D"] = "Interface\\AddOns\\PlateColor\\texture\\Bar\\3D",
    ["NamePlate-7.0"] = "Interface\\AddOns\\PlateColor\\texture\\Bar\\HP-noHpTexture",
    ["NamePlate-12.0"] = "UI-HUD-CoolDownManager-Bar",
    ["Blizzard-default"] = "ui-castingbar-filling-standard",
}

function EXUI:GetPlateColorEnemyNPCPreviewStyle()
    if nameplateBackendCache.backend ~= "platecolor" then return nil end
    local db = _G.PlateColorDB
    if type(db) ~= "table" then return nil end
    local textureKey = tostring(db.hpbarTexture or db.hpTexture or "PC-White")
    local texture = PLATECOLOR_TEXTURES[textureKey] or FetchLSM("statusbar", textureKey) or PLATECOLOR_TEXTURES.PlateColor
    -- Settings preview keeps its established independent preview dimensions.
    -- Runtime attachment is handled separately through HealthBarsContainer.
    local width = tonumber(db.myHPwidth) or tonumber(db.npWidth) or 140
    local height = tonumber(db.myHPheight) or tonumber(db.npHeight) or 15
    local namePoint = tonumber(db.namePoint) or 1
    local nameOffsetY = tonumber(db.nameVoffset) or 0
    local nameAnchor = {
        [1] = { point = "BOTTOM", relativePoint = "TOP", x = 0, y = nameOffsetY + 2, justifyH = "CENTER" },
        [2] = { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", x = 0, y = nameOffsetY + 2, justifyH = "LEFT" },
        [3] = { point = "LEFT", relativePoint = "LEFT", x = 2, y = 0, justifyH = "LEFT" },
        [4] = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 0, y = nameOffsetY - 4, justifyH = "LEFT" },
        [5] = { point = "TOP", relativePoint = "BOTTOM", x = 0, y = nameOffsetY - 4, justifyH = "CENTER" },
    }
    local nameColor = db.whiteName == true and { r = 1, g = 1, b = 1, a = 1 } or { r = 1, g = 0, b = 0, a = 1 }
    return {
        backend = "platecolor", width = math.max(1, width), height = math.max(1, height),
        texture = texture, color = Color(db.allColor or db.PCBARCOLOR, { 1, 0, 0, 1 }),
        backgroundTexture = "Interface\\Buttons\\WHITE8x8",
        backgroundColor = { r = 0, g = 0, b = 0, a = tonumber(db.hpbgAlpha) or 0.55 },
        name = {
            text = "PlateColor 敌对怪物", font = "", size = math.max(1, tonumber(db.enemyNameScale or db.nameScale) or 12),
            color = nameColor, outline = db.enemyNameOUTLINE == true and "OUTLINE" or "NONE",
            shadowColor = { r = 0, g = 0, b = 0, a = 1 }, shadowX = 1, shadowY = -1,
            anchor = nameAnchor[namePoint] or nameAnchor[1],
        },
    }
end

-- The page asks for a neutral preview contract.  Its caller never needs to
-- know which supported third-party backend supplied it.
function EXUI:GetThirdPartyNameplatePreviewStyle()
    if nameplateBackendCache.backend == "plater" then return self:GetPlaterEnemyNPCPreviewStyle() end
    if nameplateBackendCache.backend == "ellesmere" then return self:GetEllesmereEnemyNPCPreviewStyle() end
    if nameplateBackendCache.backend == "platecolor" then return self:GetPlateColorEnemyNPCPreviewStyle() end
    return nil
end
