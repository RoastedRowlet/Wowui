---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Locale = ExBoss.Locale or {}

local Locale = ExBoss.Locale

local function GetEffectiveLocale()
    if ExBoss and ExBoss.GetEffectiveLocale then
        local locale = tostring(ExBoss:GetEffectiveLocale() or "zhCN"):gsub("%s+", "")
        if locale == "enGB" then return "enUS" end
        return locale
    end
    return "zhCN"
end

local function Trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function Locale.TranslateBossDynamicText(text)
    if type(text) ~= "string" then
        return text
    end
    -- zhCN 原文不需要转换
    local locale = GetEffectiveLocale()
    if locale == "zhCN" then
        return text
    end

    local key = Trim(text)
    if key == "" then
        return text
    end

    local L = ExBoss and ExBoss.L
    local mapped = L and L[key] or nil
    if type(mapped) == "string" and mapped ~= "" and mapped ~= key then
        return mapped
    end
    return text
end
