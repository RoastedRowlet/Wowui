-- ExwindTools 自己拥有日志正文与既有已读状态；共享 Core 只负责显示窗口。
local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local Viewer = ExwindTools.ChangelogViewer
if not Viewer then return end

local L = ExwindTools.L or setmetatable({}, { __index = function(_, key) return key end })

local function GetData()
    local data = _G.ExwindTools_ChangelogData
    return type(data) == "table" and data.changelog or nil
end

-- 保留已存在的 EXCORE12S2.Changelog，避免未经授权变更或迁移用户配置。
local function GetChangelogDB()
    EXCORE12S2 = EXCORE12S2 or {}
    EXCORE12S2.Changelog = type(EXCORE12S2.Changelog) == "table" and EXCORE12S2.Changelog or {}
    return EXCORE12S2.Changelog
end

local function GetVersion()
    local data = GetData()
    return type(data) == "table" and tostring(data.version or "") or ""
end

local function GetContent()
    local data = GetData()
    return type(data) == "table" and tostring(data.content or "") or ""
end

local function GetFontSize()
    local data = GetData()
    return type(data) == "table" and data.fontSize or 14
end

local function ParseVersion(versionText)
    local text = tostring(versionText or ""):lower():gsub("^v", "")
    local y, m, d, hm = text:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not y then return nil end
    return (tonumber(y) or 0) * 100000000 + (tonumber(m) or 0) * 1000000 + (tonumber(d) or 0) * 10000 + (tonumber(hm) or 0)
end

local function IsVersionNewer(newVersion, oldVersion)
    if not oldVersion or oldVersion == "" then return true end
    local newScore, oldScore = ParseVersion(newVersion), ParseVersion(oldVersion)
    if newScore and oldScore then return newScore > oldScore end
    return tostring(newVersion) ~= tostring(oldVersion)
end

local function HasContent()
    return GetContent():match("%S") ~= nil
end

local function MarkSeen()
    local db = GetChangelogDB()
    db.LastSeenVersion = GetVersion()
    db.LastSeenAt = date("%Y-%m-%d %H:%M:%S")
end

local function MarkPopupShown()
    local db = GetChangelogDB()
    db.LastPopupVersion = GetVersion()
    db.LastPopupAt = date("%Y-%m-%d %H:%M:%S")
end

Viewer:RegisterSource("tools", {
    title = "ExwindTools",
    GetVersion = GetVersion,
    GetContent = GetContent,
    GetFontSize = GetFontSize,
    MarkSeen = MarkSeen,
    MarkPopupShown = MarkPopupShown,
})

function ExwindTools:ShowChangelog(options)
    options = options or {}
    return Viewer:Show("tools", {
        markSeen = options.markSeen ~= false,
        markShown = options.markShown ~= false,
    })
end

function ExwindTools:ShouldPopupChangelog()
    if not HasContent() then return false end
    return IsVersionNewer(GetVersion(), GetChangelogDB().LastPopupVersion)
end

function ExwindTools:HandleChangelogPopupOnUIOpen()
    MarkSeen()
    if self:ShouldPopupChangelog() then
        Viewer:Show("tools", { markShown = true })
    end
end

MarkSeen()
