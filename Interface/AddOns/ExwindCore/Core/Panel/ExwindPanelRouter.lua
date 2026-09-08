-- =========================================================
-- ExwindPanelRouter.lua
-- Core 唯一的面板入口与 Provider 可用性判断。
-- 各插件只注册 UnifiedPanel Provider；不再各自注册 /exboss、/exaura 等入口。
-- =========================================================

local ExwindTools = _G.ExwindTools
local L = (ExwindTools and ExwindTools.L)
    or (_G.ExwindLocale and _G.ExwindLocale.GetProxy and _G.ExwindLocale.GetProxy())
    or setmetatable({}, { __index = function(_, key) return key end })

if not ExwindTools then
    error(L["[ExwindPanelRouter] ExwindTools 核心未加载"])
end

local Router = ExwindTools.PanelRouter or {}
ExwindTools.PanelRouter = Router

Router.ProviderAddons = Router.ProviderAddons or {
    tools = { "ExwindTools" },
    boss = { "EXBoss" },
    aura = { "EXAura" },
}

local function TrimLower(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
end

local function GetAddonStatus(addonNames)
    local status = {
        installed = false,
        enabled = false,
        loaded = false,
        addonName = nil,
    }

    for _, addonName in ipairs(addonNames or {}) do
        local exists, loadable
        if C_AddOns and type(C_AddOns.GetAddOnInfo) == "function" then
            local returnedName, _, _, returnedLoadable = C_AddOns.GetAddOnInfo(addonName)
            exists = returnedName ~= nil
            loadable = returnedLoadable
        elseif type(GetAddOnInfo) == "function" then
            local returnedName, _, _, returnedLoadable = GetAddOnInfo(addonName)
            exists = returnedName ~= nil
            loadable = returnedLoadable
        end

        local loaded = false
        if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
            loaded = C_AddOns.IsAddOnLoaded(addonName) == true
        elseif type(IsAddOnLoaded) == "function" then
            loaded = IsAddOnLoaded(addonName) == true
        end

        if exists or loaded then
            status.installed = true
            status.enabled = loadable ~= false
            status.loaded = loaded
            status.addonName = addonName
            return status
        end
    end

    return status
end

function Router:GetProviderStatus(id)
    local shell = ExwindTools.UnifiedPanel
    local addonStatus = GetAddonStatus(self.ProviderAddons[id])
    addonStatus.registered = shell and shell.Providers and shell.Providers[id] ~= nil or false
    addonStatus.available = addonStatus.registered == true
    return addonStatus
end

function Router:RefreshState()
    local states = {}
    for _, id in ipairs({ "tools", "boss", "aura" }) do
        states[id] = self:GetProviderStatus(id)
    end

    -- State 只保存可供 Core UI 读取的快照；路由逻辑仍完全属于本文件。
    if ExwindTools.State then
        if type(ExwindTools.UpdateState) == "function" then
            ExwindTools:UpdateState("PanelProviders", states)
        else
            ExwindTools.State.PanelProviders = states
        end
    end
    return states
end

local function GetUnavailableMessage(id, status)
    local names = {
        tools = "ExwindTools",
        boss = "EXBoss",
        aura = "EXAura",
    }
    local name = names[id] or tostring(id)
    if not status.installed then
        return name .. L[" 未安装，已保留在 ExwindCore 中央面板。"]
    end
    if not status.enabled then
        return name .. L[" 已安装但未启用，已保留在 ExwindCore 中央面板。"]
    end
    if not status.loaded then
        return name .. L[" 尚未加载，已保留在 ExwindCore 中央面板。"]
    end
    return name .. L[" 已加载但尚未注册 Unified Provider，已保留在 ExwindCore 中央面板。"]
end

function Router:ShowCentralStatus(id)
    local shell = ExwindTools.UnifiedPanel
    if not shell then return false end
    shell:Show()
    shell:SelectProvider(nil)
    shell:ShowCoreStatus()

    if id then
        local message = GetUnavailableMessage(id, self:GetProviderStatus(id))
        if ExwindTools.Print then
            ExwindTools:Print(message)
        else
            print("|cffA330C9ExwindCore|r " .. message)
        end
    end
    return false
end

function Router:Open(id, route)
    local shell = ExwindTools.UnifiedPanel
    if not shell then return false end

    local status = self:GetProviderStatus(id)
    self:RefreshState()
    if not status.registered then
        return self:ShowCentralStatus(id)
    end

    shell:Show(id, route)
    return true
end

function Router:Toggle(id, route)
    local shell = ExwindTools.UnifiedPanel
    if not shell then return false end

    local status = self:GetProviderStatus(id)
    self:RefreshState()
    if not status.registered then
        return self:ShowCentralStatus(id)
    end

    if shell.Frame and shell.Frame:IsShown() and shell.ActiveProvider == id then
        shell:Hide()
        return true
    end

    shell:Show(id, route)
    return true
end

function Router:Close(id)
    local shell = ExwindTools.UnifiedPanel
    if shell and shell.Frame and shell.Frame:IsShown() and (not id or shell.ActiveProvider == id) then
        shell:Hide()
        return true
    end
    return false
end

function Router:HandleBossSlash(input)
    local arg = TrimLower(input)
    local pullArgs = arg:match("^pull%s*(.*)$")
    if pullArgs ~= nil then
        local pullCountdown = _G.ExBoss and _G.ExBoss.PullCountdown
        if pullCountdown and type(pullCountdown.HandleSlash) == "function" then
            pullCountdown:HandleSlash(pullArgs)
        elseif _G.ExBoss and _G.ExBoss.Print and _G.ExBoss.Print.Say then
            _G.ExBoss.Print.Say((_G.ExBoss.L and _G.ExBoss.L["开怪倒数功能未就绪"]) or L["开怪倒数功能未就绪"])
        end
        return
    end

    if arg == "edit" or arg == "edmode" then
        if EXUI.ToggleEditMode then
            EXUI:ToggleEditMode()
        end
        return
    end

    if arg == "version" then
        local boss = _G.ExBoss
        local message = "|cffff4400Ex|r|cff00ccffBoss|r v" .. tostring(boss and boss.VERSION or L["未加载"])
        if boss and boss.Print and boss.Print.Say then boss.Print.Say(message) else print(message) end
        return
    end

    self:Toggle("boss")
end

local legacyExCommand = SlashCmdList and SlashCmdList["EX"]
function Router:HandleToolsSlash(input)
    if TrimLower(input) == "" then
        self:Toggle("tools")
        return
    end
    if legacyExCommand then
        legacyExCommand(input)
        return
    end
    self:Open("tools")
end

local function RegisterSlashCommand(command, aliases, handler)
    for index, alias in ipairs(aliases) do
        _G["SLASH_" .. command .. index] = "/" .. alias
    end
    SlashCmdList[command] = handler
end

-- /ex 的开发子命令仍由其既有包装器继续处理；空命令才由 Router 打开 Tools。
RegisterSlashCommand("EX", { "ex" }, function(input)
    Router:HandleToolsSlash(input)
end)
RegisterSlashCommand("EXWINDTOOLS", { "exwindtools" }, function()
    Router:Toggle("tools")
end)
RegisterSlashCommand("EXTOOLS", { "extools" }, function()
    Router:Toggle("tools")
end)
RegisterSlashCommand("EXBOSS", { "exboss", "exb" }, function(input)
    Router:HandleBossSlash(input)
end)
RegisterSlashCommand("EXAURA", { "exaura" }, function()
    Router:Toggle("aura")
end)

Router:RefreshState()

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function()
    Router:RefreshState()
end)
