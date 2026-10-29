-- [[ ExwindFrameTask.lua ]]
-- 分帧任务：把一个函数放进协程，每帧按该任务自己的毫秒预算推进，
-- 任务在可以停下的地方 coroutine.yield()。同名任务开始时会先停掉旧的。

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end
local EXUI = ExwindTools.UI or {}
ExwindTools.UI = EXUI

local tasks = {}     -- 按开始顺序：{ name, budget, co, onError, stopped }
local snapshot = {}  -- 本帧要推进的任务；任务执行中可能开始或停止别的任务
local runner = CreateFrame("Frame")
runner:Hide()

local function FindTask(name)
    for i = 1, #tasks do
        if tasks[i].name == name then return tasks[i] end
    end
end

local function RemoveTask(task)
    task.stopped = true
    for i = #tasks, 1, -1 do
        if tasks[i] == task then
            table.remove(tasks, i)
            break
        end
    end
    if #tasks == 0 then runner:Hide() end
end

-- budgetMs：每帧最多推进的毫秒数（每帧至少推进一次）。
-- onError(message)：可选，出错时调用，任务此时已移除；不传则交给 geterrorhandler()。
function EXUI:StartFrameTask(name, budgetMs, func, onError)
    local old = FindTask(name)
    if old then RemoveTask(old) end
    tasks[#tasks + 1] = {
        name = name,
        budget = budgetMs,
        co = coroutine.create(func),
        onError = onError,
    }
    runner:Show()
end

function EXUI:StopFrameTask(name)
    local task = FindTask(name)
    if task then RemoveTask(task) end
end

local function StepTask(task)
    local start = debugprofilestop()
    repeat
        local ok, message = coroutine.resume(task.co)
        if not ok then
            RemoveTask(task)
            local handler = task.onError or geterrorhandler()
            handler(tostring(message) .. "\n" .. debugstack(task.co))
            return
        end
        if coroutine.status(task.co) == "dead" then
            RemoveTask(task)
            return
        end
    until task.stopped or debugprofilestop() - start >= task.budget
end

runner:SetScript("OnUpdate", function()
    local count = #tasks
    for i = 1, count do snapshot[i] = tasks[i] end
    for i = 1, count do
        local task = snapshot[i]
        snapshot[i] = nil
        if not task.stopped then StepTask(task) end
    end
end)
