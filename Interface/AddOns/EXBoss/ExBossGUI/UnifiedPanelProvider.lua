local ExBoss = _G.ExBoss
local ET = _G.ExwindTools
if not ExBoss or not ET or not ET.UnifiedPanel then return end

local Shell = ET.UnifiedPanel
local BossPanel = ExBoss.UI and ExBoss.UI.Panel
if not BossPanel then return end

-- Boss 页面左侧为副本/首领导航，明确采用 B:C=22:78；其他 Provider 仍用 Shell 默认 25:75。
local Provider = { id = "boss", hasTopTabs = true, navRatio = 0.22 }

function Provider:GetLayoutMode(route)
    local tab = type(route) == "table" and route.tab or BossPanel:GetCurrentTab()
    local splitRoutes = {
        boss = true, trash = true, globalsettings = true, tools = true,
        timerbar = true, bunbar = true, countdown = true, flashtextmedium = true,
        ringprogress = true, iconalert = true,
        castprogressbar = true, extrashieldbar = true,
        mythiccast = true,
        interrupttracker = true,
    }
    return splitRoutes[tab] and "tabs_split" or "tabs_full"
end

function Provider:Mount(hosts, metrics)
    self.Hosts = hosts
    BossPanel:MountUnified(hosts, Shell)
end

function Provider:Relayout(metrics)
    BossPanel:RelayoutUnified()
end

function Provider:ApplyRoute(route)
    local wasShown = BossPanel._frame and BossPanel._frame:IsShown()
    if type(route) == "table" and route.tab and BossPanel:GetCurrentTab() ~= route.tab then
        BossPanel:SetTab(route.tab)
    end
    BossPanel:RefreshUnifiedTabs()
    BossPanel._frame:Show()
    -- 已显示时 SetTab(route.tab) 会完成刷新；再次 SetTab 同一 Tab 会导致
    -- BossPage Hide/Render/延迟刷新整套重复执行。首次显示才需要这一轮渲染。
    if not wasShown then
        BossPanel:SetTab(BossPanel:GetCurrentTab())
    end

    -- Unified Shell 是 EXBoss 的默认入口；日志提示必须在这里触发，而不是只留在旧独立面板路径。
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            -- 以共享 Shell 的当前 Provider 为准。BossPanel._frame 是内容 root，
            -- 在切页/刷新期间可能暂时不处于 IsShown 状态，不能据此跳过日志检查。
            if Shell.Frame and Shell.Frame:IsShown() and Shell.ActiveProvider == "boss"
                and ExBoss.HandleChangelogPopupOnUIOpen then
                ExBoss:HandleChangelogPopupOnUIOpen()
            end
        end)
    end
end

function Provider:Hide()
    BossPanel:Hide()
end

Shell:RegisterProvider("boss", Provider)
