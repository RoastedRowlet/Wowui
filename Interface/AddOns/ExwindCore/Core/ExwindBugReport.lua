--[[
    ExwindBugReport.lua - /exbug 报错收集与诊断复制

    1. 接力式全局错误处理：存下原处理器，收完照样转交，暴雪默认显示行为不变。
       BugGrabber 装好后会把 seterrorhandler 换成空函数且不转交，此时改订阅它的
       "BugGrabber.BugGrabbed" 回调，两条路只走一条，不重复计次。
    2. 只收消息或调用栈里带 EX 插件目录的错；按错误文字去重（运行时错误文字自带
       "文件:行号"，即出错位置），同一条只在第一次取调用栈和当时 State，之后只计次。
       最多保留 MAX_ENTRIES 条，满了丢最老的；只存内存，不弹窗、不刷聊天框。
    3. /exbug 打开可全选复制的纯文字：State 整张导出 + 报错列表，格式见 ExwindCore.md。
--]]

local ExwindTools = _G.ExwindTools
local L = ExwindTools.L

local FORMAT_HEADER = "EXBUG v1"
local MAX_ENTRIES = 50
local MAX_FOREIGN_KEYS = 200
local MAX_DEPTH = 6
local SECRET_TEXT = "<secret>"

-- 路径片段按前缀匹配，同时覆盖 EXAura-Locale、EXAura_Editor、EXBossData 等附属插件。
local OWN_PATHS = {
    "AddOns/ExwindCore/", "AddOns/ExwindTools", "AddOns/EXBoss", "AddOns/EXBOSS", "AddOns/EXAura",
}

-- 带角色名、服务器名的 State 键不导出。
local PRIVATE_STATE_KEYS = {
    PlayerName = true,
    RealmName = true,
    ["3457interrupt1name"] = true,
    ["3457interrupt2name"] = true,
    ["3457interrupt3name"] = true,
}
-- 报错条目里的 State 快照不重复带插件清单，清单只在顶部 [State] 里出现一次。
local ENTRY_SKIP_KEYS = { LoadedAddOns = true }

local find, gsub, format, concat, sort = string.find, string.gsub, string.format, table.concat, table.sort
local time, date, tostring, type = time, date, tostring, type
local issecretvalue = issecretvalue

local entries = {}      -- 按第一次出现排序
local byKey = {}        -- 错误文字 → 条目
local foreignKeys = {}  -- 非 EX 的错误文字，命中直接跳过
local foreignCount = 0
local previousHandler
local viaBugGrabber = false

local function IsOwnText(text)
    for i = 1, #OWN_PATHS do
        if find(text, OWN_PATHS[i], 1, true) then return true end
    end
    return false
end

local function EscapeValue(text)
    return (gsub(gsub(gsub(text, "\\", "\\\\"), "\n", "\\n"), "\"", "\\\""))
end

local function KeyText(key)
    if issecretvalue(key) then return SECRET_TEXT end
    return tostring(key)
end

local function ValueText(value)
    if issecretvalue(value) then return SECRET_TEXT end
    local valueType = type(value)
    if valueType == "string" then return "\"" .. EscapeValue(value) .. "\"" end
    if valueType == "number" or valueType == "boolean" then return tostring(value) end
    return "<" .. valueType .. ">"
end

local function SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = key end
    sort(keys, function(a, b) return KeyText(a) < KeyText(b) end)
    return keys
end

-- 一行一个叶子：路径 = 值；嵌套表用点连接路径，空表写 {}。
local function AppendTable(lines, tbl, prefix, indent, skip, depth, seen)
    local keys = SortedKeys(tbl)
    for _, key in ipairs(keys) do
        if not (skip and skip[key]) then
            local path = prefix .. KeyText(key)
            local value = tbl[key]
            if not issecretvalue(value) and type(value) == "table" then
                if seen[value] or depth >= MAX_DEPTH then
                    lines[#lines + 1] = indent .. path .. " = <table>"
                elseif next(value) == nil then
                    lines[#lines + 1] = indent .. path .. " = {}"
                else
                    seen[value] = true
                    AppendTable(lines, value, path .. ".", indent, nil, depth + 1, seen)
                end
            else
                lines[#lines + 1] = indent .. path .. " = " .. ValueText(value)
            end
        end
    end
end

local function StateLines(lines, indent, extraSkip)
    local skip = PRIVATE_STATE_KEYS
    if extraSkip then
        skip = {}
        for key in pairs(PRIVATE_STATE_KEYS) do skip[key] = true end
        for key in pairs(extraSkip) do skip[key] = true end
    end
    AppendTable(lines, ExwindTools.State, "", indent, skip, 1, {})
    return lines
end

-- 与暴雪默认处理器同一算法：按出错时的栈高度定位，不受处理器接力层数影响。
local function StackAtError()
    local errorHeight = GetErrorCallstackHeight()
    local level = errorHeight and (GetCallstackHeight() - (errorHeight - 1)) or 4
    local stack = debugstack(level)
    if issecretvalue(stack) then return SECRET_TEXT end
    return stack or ""
end

local function Capture(message, stack)
    if issecretvalue(message) then return end
    local key = type(message) == "string" and message or tostring(message)
    local entry = byKey[key]
    if entry then
        entry.count = entry.count + 1
        entry.last = time()
        return
    end
    if foreignKeys[key] then return end
    stack = stack or StackAtError()
    if not IsOwnText(key) and not IsOwnText(stack) then
        if foreignCount >= MAX_FOREIGN_KEYS then foreignKeys, foreignCount = {}, 0 end
        foreignKeys[key] = true
        foreignCount = foreignCount + 1
        return
    end
    local now = time()
    entry = { message = key, count = 1, first = now, last = now, stack = stack,
        state = concat(StateLines({}, "  ", ENTRY_SKIP_KEYS), "\n") }
    if #entries >= MAX_ENTRIES then
        byKey[table.remove(entries, 1).message] = nil
    end
    entries[#entries + 1] = entry
    byKey[key] = entry
end

local function OnError(message, ...)
    if not viaBugGrabber then Capture(message) end
    return previousHandler(message, ...)
end

-- BugGrabber 同一条错误复用同一张表，按表 ID 缓存，重复时不再扫它的库。
local bugGrabberIDs = {}
local bugGrabberCount = 0
local function OnBugGrabbed(_, tableID)
    local cached = bugGrabberIDs[tableID]
    if cached then
        if cached ~= true and byKey[cached.message] == cached then
            cached.count = cached.count + 1
            cached.last = time()
        end
        return
    end
    local db = BugGrabber:GetDB()
    for i = #db, 1, -1 do
        local err = db[i]
        if tostring(err) == tableID then
            Capture(err.message, err.stack or "")
            if bugGrabberCount >= MAX_FOREIGN_KEYS then bugGrabberIDs, bugGrabberCount = {}, 0 end
            bugGrabberIDs[tableID] = byKey[err.message] or true
            bugGrabberCount = bugGrabberCount + 1
            return
        end
    end
end

local function UseBugGrabber()
    if viaBugGrabber then return end
    viaBugGrabber = true
    EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", OnBugGrabbed, ExwindTools)
end

if BugGrabber then
    UseBugGrabber()
else
    previousHandler = geterrorhandler()
    seterrorhandler(OnError)
end

-- 内嵌在别的插件里的 BugGrabber 可能晚于 Core 装上并顶掉本处理器。
ExwindTools:RegisterEvent("PLAYER_LOGIN", "ExwindBugReport", function()
    if BugGrabber and geterrorhandler() ~= OnError then UseBugGrabber() end
end)

local function TimeText(stamp)
    return date("%Y-%m-%d %H:%M:%S", stamp)
end

function ExwindTools:BuildBugReportText()
    local lines = { FORMAT_HEADER, "generated = " .. TimeText(time()), "[State]" }
    StateLines(lines, "")
    lines[#lines + 1] = "[Errors] " .. #entries
    for index, entry in ipairs(entries) do
        lines[#lines + 1] = "[Error " .. index .. "]"
        lines[#lines + 1] = "message = " .. ValueText(entry.message)
        lines[#lines + 1] = "count = " .. entry.count
        lines[#lines + 1] = "first = " .. TimeText(entry.first)
        lines[#lines + 1] = "last = " .. TimeText(entry.last)
        lines[#lines + 1] = "stack:"
        for stackLine in gsub(entry.stack, "\n+$", ""):gmatch("[^\n]+") do
            lines[#lines + 1] = "  " .. stackLine
        end
        lines[#lines + 1] = "state:"
        lines[#lines + 1] = entry.state
    end
    lines[#lines + 1] = "[End]"
    return concat(lines, "\n")
end

function ExwindTools:ShowBugReport()
    local text = self:BuildBugReportText()
    self.UI:ShowDialog({
        id = "ExwindBugReport",
        title = L["EX 报错与状态"],
        text = format(L["全选复制下面的文字，贴给客服（当前 %d 条报错）"], #entries),
        width = 640,
        input = { multiline = true, readOnly = true, text = text, height = 360, highlight = true },
        defaultButton = "close", cancelButton = "close",
        buttons = { { id = "close", text = L["关闭"], variant = "primary" } },
    })
end

ExwindTools:RegisterChatCommand("exbug", function() ExwindTools:ShowBugReport() end)
