---@diagnostic disable: undefined-global

ExBoss.Voice = ExBoss.Voice or {}
ExBoss.Voice.Profiles = ExBoss.Voice.Profiles or {}
local Profiles = ExBoss.Voice.Profiles

local function GetBossConfig()
    local cfg = ExBoss and ExBoss.BossConfig
    if type(cfg) == "table" and type(cfg.Ensure) == "function" then
        cfg:Ensure()
        return cfg
    end
    return nil
end

local function GetFirstAuthorKey(slotKey)
    local root = _G.EXBOSS_AUTHOR_PRESETS
    local slot = type(root) == "table" and type(root.slots) == "table" and root.slots[slotKey] or nil
    if type(slot) ~= "table" then
        return nil
    end
    local keys = {}
    for key in pairs(slot) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    return keys[1]
end

local function NormalizeSceneKey(scene)
    scene = tostring(scene or ""):lower()
    return scene == "raid" and "raid" or "mplus"
end

local function GetSlotMeta(slotKey)
    local map = {
        mplus_tank = { scene = "mplus", name = "大米坦克" },
        mplus_dps =  { scene = "mplus", name = "大米DPS"  },
        mplus_heal = { scene = "mplus", name = "大米治疗" },
        raid_tank = { scene = "raid", name = "团本坦克" },
        raid_dps =  { scene = "raid", name = "团本DPS"  },
        raid_heal = { scene = "raid", name = "团本治疗" },
    }
    return map[tostring(slotKey or "")]
end

local function GetSceneFromEvent(eventID)
    local data = _G.EXBOSS_ENCOUNTER_DATA
    local eid = tonumber(eventID)
    if not eid or type(data) ~= "table" or type(data.maps) ~= "table" then
        return nil
    end
    for _, mapRow in pairs(data.maps) do
        if type(mapRow) == "table" and type(mapRow.bosses) == "table" then
            local scene = (tonumber(mapRow.instanceType) == 2 or tostring(mapRow.category or ""):find("团") ~= nil) and "raid" or "mplus"
            for _, bossRow in pairs(mapRow.bosses) do
                if type(bossRow) == "table" and type(bossRow.events) == "table" and bossRow.events[eid] ~= nil then
                    return scene
                end
            end
        end
    end
    return nil
end

local function BuildProfileRow(slotKey)
    local bossCfg = GetBossConfig()
    local meta = GetSlotMeta(slotKey) or {}
    local author = bossCfg and bossCfg.GetSelectedAuthor and bossCfg:GetSelectedAuthor(slotKey) or GetFirstAuthorKey(slotKey) or ""
    return {
        key = slotKey,
        name = (meta.name or tostring(slotKey)) .. " · " .. tostring(author or ""),
        builtIn = true,
        scene = meta.scene or "mplus",
        author = author or "",
        events = {},
    }
end

function Profiles:Ensure()
    return true
end

function Profiles:GetActiveKey(scene)
    local bossCfg = GetBossConfig()
    if not bossCfg or not bossCfg.GetRuntimeSlotForScene then
        return nil
    end
    return bossCfg:GetRuntimeSlotForScene(NormalizeSceneKey(scene))
end

function Profiles:GetProfile(profileKey)
    local meta = GetSlotMeta(profileKey)
    if not meta then
        return nil
    end
    return BuildProfileRow(profileKey)
end

function Profiles:SaveCurrentToProfile(profileKey)
    return true, profileKey
end

function Profiles:SaveActiveScene(scene)
    return true, NormalizeSceneKey(scene)
end

function Profiles:SaveEventToActiveProfile(eventID)
    local bossCfg = GetBossConfig()
    if bossCfg and bossCfg.ApplyPersistedChange then
        bossCfg:ApplyPersistedChange(eventID)
    end
    return true
end

function Profiles:LoadProfileToCurrent(profileKey)
    local bossCfg = GetBossConfig()
    local meta = GetSlotMeta(profileKey)
    if not bossCfg or not meta then
        return false, "profile not found"
    end
    bossCfg:PublishRuntimeSelection()
    local BossPage = ExBoss and ExBoss.UI and ExBoss.UI.Panel and ExBoss.UI.Panel.BossPage
    if BossPage and BossPage.RefreshSpellUI then
        BossPage:RefreshSpellUI()
    end
    return true
end

function Profiles:SetActive(profileKey)
    return self:LoadProfileToCurrent(profileKey)
end

function Profiles:Create(name, scene)
    return false, "slot profiles are fixed"
end

function Profiles:Delete(profileKey)
    return false, "slot profiles are fixed"
end

function Profiles:Rename(profileKey, newName)
    return false, "slot profiles are fixed"
end

function Profiles:GetList(scene)
    local bossCfg = GetBossConfig()
    if not bossCfg or not bossCfg.GetSlotKeys then
        return {}
    end
    local out = {}
    for _, slotKey in ipairs(bossCfg:GetSlotKeys(scene and NormalizeSceneKey(scene) or nil)) do
        out[#out + 1] = BuildProfileRow(slotKey)
    end
    return out
end

function Profiles:ApplyForScene(scene)
    local bossCfg = GetBossConfig()
    if bossCfg and bossCfg.PublishRuntimeSelection then
        bossCfg:PublishRuntimeSelection()
    end
    return true
end
