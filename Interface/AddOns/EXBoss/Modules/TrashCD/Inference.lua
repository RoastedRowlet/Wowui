---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.Inference or {}
ExBoss.TrashCD.Inference = Mod
ExBoss.Trash.Inference = Mod

local Data = ExBoss.TrashCD and ExBoss.TrashCD.Data or nil
local Layer1 = ExBoss.TrashCD and ExBoss.TrashCD.Layer1Filter or nil
local Layer2 = ExBoss.TrashCD and ExBoss.TrashCD.Layer2Filter or nil
local Population = ExBoss.TrashCD and ExBoss.TrashCD.Population or nil
local CoPresence = ExBoss.TrashCD and ExBoss.TrashCD.CoPresence or nil

local function NormalizeNameKey(name)
    if Data and type(Data.NormalizeNameKey) == "function" then
        return Data.NormalizeNameKey(name)
    end
    local s = tostring(name or "")
    s = s:lower()
    s = s:gsub("%s+", "")
    s = s:gsub("[：:，,。%.！!？?·%-_—~`'\"%(%[%{%)%]%}]", "")
    return s
end

function Mod.BuildLayer1Candidates(obs, currentDungeonKey, rows, mapID, runtime, options)
    rows = type(rows) == "table" and rows or {}
    if Layer1 and type(Layer1.BuildCandidates) == "function" then
        return Layer1.BuildCandidates(obs, currentDungeonKey, rows, mapID, runtime, options)
    end
    return {}
end

function Mod.ApplyLayer2Candidates(candidates, obs, runtime, mapID, now)
    if Layer2 and type(Layer2.FilterCandidates) == "function" then
        return Layer2.FilterCandidates(candidates, obs, runtime, mapID, now)
    end
    return candidates
end

function Mod.ApplyCoPresenceCandidates(candidates, runtime, mapID, trace)
    if CoPresence and type(CoPresence.FilterCandidates) == "function" then
        return CoPresence.FilterCandidates(candidates, runtime, mapID, trace == true)
    end
    return candidates, false, nil
end

function Mod.ResolveCandidates(obs, currentDungeonKey, rows, runtime, mapID, now)
    -- 先保留阶段、地图、等级等可信 L1 条件，单独跳过数量池。
    -- bossCounts 只能缩小预览候选，不能制造可锁身份。
    local trustedLayer1Candidates = Mod.BuildLayer1Candidates(obs, currentDungeonKey, rows, mapID, runtime, {
        ignoreBossCounts = true,
    })
    local layer1Candidates = Mod.BuildLayer1Candidates(obs, currentDungeonKey, rows, mapID, runtime)
    local trace = type(runtime) == "table" and runtime._debugTrace == true
    local trustedCoPresenceApplied, trustedCoPresenceDebug = false, nil
    trustedLayer1Candidates, trustedCoPresenceApplied, trustedCoPresenceDebug =
        Mod.ApplyCoPresenceCandidates(trustedLayer1Candidates, runtime, mapID, trace)
    local coPresenceApplied, coPresenceDebug = false, nil
    layer1Candidates, coPresenceApplied, coPresenceDebug =
        Mod.ApplyCoPresenceCandidates(layer1Candidates, runtime, mapID, trace)
    local layer2Candidates = Mod.ApplyLayer2Candidates(layer1Candidates, obs, runtime, mapID, now)
    local resolved = type(layer2Candidates) == "table" and #layer2Candidates == 1 and layer2Candidates[1] or nil
    -- 可信 L1（不含 bossCounts）本身唯一可锁；bossCounts 造成的唯一仍只是预览。
    -- 多个正常 L1 候选由 L2 收敛唯一时，也可锁。
    local trustedLayer1Count = type(trustedLayer1Candidates) == "table" and #trustedLayer1Candidates or 0
    local layer1Count = type(layer1Candidates) == "table" and #layer1Candidates or 0
    local layer2Count = type(layer2Candidates) == "table" and #layer2Candidates or 0
    local trustedL1Resolved = trustedLayer1Count == 1
        and layer1Count == 1
        and resolved ~= nil
        and tonumber(trustedLayer1Candidates[1] and trustedLayer1Candidates[1].npcID) == tonumber(resolved.npcID)
    local layer2Resolved = resolved ~= nil and layer1Count > 1 and layer2Count == 1
    local identityLockEligible = trustedL1Resolved or layer2Resolved
    local resolutionSource = nil
    if resolved then
        if trustedL1Resolved then
            resolutionSource = trustedCoPresenceApplied and "layer1-co-presence" or "layer1-unique"
        elseif layer2Resolved then
            resolutionSource = "layer2-evidence"
        else
            resolutionSource = "candidate-preview"
        end
    end
    if not resolved and Population and type(Population.SelectPriority) == "function" then
        resolved = Population.SelectPriority(layer2Candidates, obs, runtime, mapID)
        if resolved then
            resolutionSource = "priority"
        end
    end
    -- 此处必须保持纯推理：候选结论由 Runtime 接受后才可写入人口/排程状态。
    -- 否则输出链的二次推理可能把暂定优先级写回 runtime。
    return {
        dungeonKey = NormalizeNameKey(currentDungeonKey),
        trustedLayer1Candidates = trustedLayer1Candidates,
        layer1Candidates = layer1Candidates,
        candidates = layer2Candidates,
        resolved = resolved,
        resolutionSource = resolutionSource,
        identityLockEligible = identityLockEligible,
        coPresenceApplied = coPresenceApplied == true or trustedCoPresenceApplied == true,
        coPresenceDebug = coPresenceDebug,
        trustedCoPresenceDebug = trustedCoPresenceDebug,
    }
end
