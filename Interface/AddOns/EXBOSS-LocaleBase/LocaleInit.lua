---@diagnostic disable: undefined-global
-- This file is the canonical EXBoss locale system bootstrap.
-- It must run BEFORE EXBOSS-Locale fills the locale stores, and BEFORE any
-- EXBoss page files capture L["..."] strings.  That ordering is enforced by
-- the addon dependency chain:
--   EXBOSS-LocaleBase  →  EXBOSS-Locale  →  EXBoss
--
-- Because this addon declares SavedVariables: ExBossDB with
-- LoadSavedVariablesFirst: 1, ExBossDB is available here, so
-- _currentLocale is set to the user's saved preference immediately.
-- All subsequent L["..."] lookups in EXBoss page files therefore return the
-- correct locale without any deferred workaround.
--
-- Keep in sync with EXBoss/Locale/Init.lua (which re-runs harmlessly later).

ExBoss = ExBoss or {}
ExBoss.Locale = ExBoss.Locale or {}

local Locale = ExBoss.Locale

Locale._appName = "EXBoss"
Locale._defaultLocale = Locale._defaultLocale or "zhCN"
Locale._stores = Locale._stores or {}

local function NormalizeLocaleTag(tag)
    local locale = tostring(tag or ""):gsub("%s+", "")
    if locale == "enGB" then
        return "enUS"
    end
    return locale ~= "" and locale or "zhCN"
end

local function NormalizeLocaleMode(mode)
    local value = tostring(mode or ""):gsub("%s+", "")
    if value == "zhCN" or value == "enUS" then
        return value
    end
    return "AUTO"
end

local function GetSavedLocaleMode()
    local db = rawget(_G, "ExBossDB")
    if type(db) == "table" and type(db.locale) == "table" then
        return NormalizeLocaleMode(db.locale.mode)
    end
    return "AUTO"
end

function Locale:GetClientLocale()
    return NormalizeLocaleTag(GetLocale and GetLocale() or self._defaultLocale)
end

function Locale:GetEffectiveLocale(mode)
    local localeMode = NormalizeLocaleMode(mode)
    if localeMode == "AUTO" then
        return self:GetClientLocale()
    end
    return NormalizeLocaleTag(localeMode)
end

Locale._mode = GetSavedLocaleMode()
Locale._currentLocale = Locale:GetEffectiveLocale(Locale._mode)

local function EnsureStore(locale)
    locale = NormalizeLocaleTag(locale)
    local store = Locale._stores[locale]
    if not store then
        store = {}
        Locale._stores[locale] = store
    end
    return store
end

function Locale:NewLocale(appName, locale, isDefault)
    if tostring(appName or self._appName) ~= self._appName then
        return nil
    end

    locale = NormalizeLocaleTag(locale)
    local store = EnsureStore(locale)
    if isDefault == true then
        self._defaultLocale = locale
    end

    return setmetatable({}, {
        __newindex = function(_, key, value)
            if type(key) ~= "string" or key == "" then
                return
            end
            if value == true or value == nil then
                store[key] = key
            else
                store[key] = tostring(value)
            end
        end,
        __index = function(_, key)
            return store[key]
        end,
    })
end

function Locale:GetLocale(appName)
    if tostring(appName or self._appName) ~= self._appName then
        return self._proxy
    end
    return self._proxy
end

function Locale:GetCurrentLocale()
    return self._currentLocale
end

function Locale:GetDefaultLocale()
    return self._defaultLocale
end

function Locale:GetLocaleMode()
    return NormalizeLocaleMode(self._mode)
end

function Locale:SetLocaleMode(mode)
    local localeMode = NormalizeLocaleMode(mode)
    self._mode = localeMode

    ExBossDB = ExBossDB or {}
    ExBossDB.locale = type(ExBossDB.locale) == "table" and ExBossDB.locale or {}
    ExBossDB.locale.mode = localeMode

    self._currentLocale = self:GetEffectiveLocale(localeMode)

    local engine = ExBoss and ExBoss.Voice and ExBoss.Voice.Engine
    if engine and type(engine.RefreshSelectedVoicePackForLocale) == "function" then
        pcall(engine.RefreshSelectedVoicePackForLocale, engine, {
            applyOverrides = true,
        })
    end

    return localeMode
end

Locale._proxy = Locale._proxy or setmetatable({}, {
    __index = function(_, key)
        if type(key) ~= "string" or key == "" then
            return key
        end
        local current = Locale._stores[Locale._currentLocale]
        if type(current) == "table" and current[key] ~= nil then
            return current[key]
        end
        local defaultStore = Locale._stores[Locale._defaultLocale]
        if type(defaultStore) == "table" and defaultStore[key] ~= nil then
            return defaultStore[key]
        end
        return key
    end,
})

function ExBoss:NewLocale(locale, isDefault)
    return Locale:NewLocale(self.Locale._appName, locale, isDefault)
end

function ExBoss:GetLocale()
    return Locale:GetLocale(self.Locale._appName)
end

function ExBoss:GetLocaleMode()
    return Locale:GetLocaleMode()
end

function ExBoss:GetEffectiveLocale(mode)
    return Locale:GetEffectiveLocale(mode)
end

function ExBoss:SetLocaleMode(mode)
    return Locale:SetLocaleMode(mode)
end

ExBoss.L = Locale:GetLocale(Locale._appName)
