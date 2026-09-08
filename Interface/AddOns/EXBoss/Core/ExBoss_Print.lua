---@diagnostic disable: undefined-global
-- Core/ExBoss_Print.lua
-- 统一聊天框 print 入口 + 进入副本提示表

ExBoss = ExBoss or {}
ExBoss.Print = ExBoss.Print or {}

local PREFIX = "|cff00ffff<EXBOSS>|r"
local L = (ExBoss and ExBoss.L) or setmetatable({}, { __index = function(_, key) return key end })

function ExBoss.Print.Say(msg)
    if type(msg) ~= "string" or msg == "" then return end
    print(PREFIX .. " " .. msg)
end

-- MapID -> 进入副本要打印的提示行（按顺序输出）
local ENTRY_NOTICES = {
    [658] = { L["进入 |cffffd100萨隆矿坑|r 小怪内置CD已载入,该功能测试中 如遇到问题请反馈给我 谢谢!"] },
}

local function HandleMapChange(newID, oldID)
    if newID == oldID then return end
    local lines = ENTRY_NOTICES[tonumber(newID) or 0]
    if not lines then return end
    for i = 1, #lines do
        ExBoss.Print.Say(lines[i])
    end
end

if ExwindTools and type(ExwindTools.WatchState) == "function" then
    ExwindTools:WatchState("MapID", "ExBoss.Print.EntryNotice", HandleMapChange)
end
