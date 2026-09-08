---@diagnostic disable: undefined-global

-- Cross-nameplate L1 evidence. Positive companion evidence requires a Runtime
-- identity lock. Runtime may separately request a temporary timeout fallback;
-- that fallback never becomes identity evidence or a lock.
ExBoss = ExBoss or {}
ExBoss.Trash = ExBoss.Trash or {}
ExBoss.TrashCD = ExBoss.TrashCD or {}

local Mod = ExBoss.TrashCD.CoPresence or {}
ExBoss.TrashCD.CoPresence = Mod
ExBoss.Trash.CoPresence = Mod

Mod._byMap = Mod._byMap or {}

local function WipeTable(t)
    if type(t) ~= "table" then
        return
    end
    for key in pairs(t) do
        t[key] = nil
    end
end

local function GetMapBucket(mapID, create)
    local mid = tonumber(mapID)
    if not mid then
        return nil
    end
    local bucket = Mod._byMap[mid]
    if type(bucket) ~= "table" and create == true then
        bucket = {}
        Mod._byMap[mid] = bucket
    end
    return type(bucket) == "table" and bucket or nil
end

function Mod.Reset()
    WipeTable(Mod._byMap)
end

function Mod.UnregisterRuntime(runtime)
    if type(runtime) ~= "table" then
        return
    end
    local mapID = tonumber(runtime._coPresenceMapID)
    local npcID = tonumber(runtime._coPresenceNPCID)
    if mapID and npcID then
        local bucket = GetMapBucket(mapID, false)
        local runtimes = bucket and bucket[npcID]
        if type(runtimes) == "table" then
            runtimes[runtime] = nil
            if next(runtimes) == nil then
                bucket[npcID] = nil
            end
        end
        if bucket and next(bucket) == nil then
            Mod._byMap[mapID] = nil
        end
    end
    runtime._coPresenceMapID = nil
    runtime._coPresenceNPCID = nil
end

function Mod.MarkRuntimeLocked(runtime, mapID, npcID)
    if type(runtime) ~= "table" then
        return false
    end
    local mid = tonumber(mapID)
    local nid = tonumber(npcID)
    if not (mid and nid) then
        Mod.UnregisterRuntime(runtime)
        return false
    end
    if tonumber(runtime._coPresenceMapID) == mid and tonumber(runtime._coPresenceNPCID) == nid then
        return false
    end
    Mod.UnregisterRuntime(runtime)
    local bucket = GetMapBucket(mid, true)
    bucket[nid] = type(bucket[nid]) == "table" and bucket[nid] or {}
    bucket[nid][runtime] = true
    runtime._coPresenceMapID = mid
    runtime._coPresenceNPCID = nid
    return true
end

local function SortedNPCIDs(set)
    local out = {}
    for npcID in pairs(type(set) == "table" and set or {}) do
        local id = tonumber(npcID)
        if id then
            out[#out + 1] = id
        end
    end
    table.sort(out)
    return out
end

local function GetCandidateCompanions(candidate)
    local row = type(candidate) == "table" and candidate.row or nil
    local companions = type(candidate) == "table" and candidate.coPresenceNPCIDs or nil
    if type(companions) ~= "table" then
        companions = type(row) == "table" and row.coPresenceNPCIDs or nil
    end
    return type(companions) == "table" and companions or nil
end

local function HasCompanionRequirement(candidate)
    local companions = GetCandidateCompanions(candidate)
    return type(companions) == "table" and next(companions) ~= nil
end

local function CandidateMatchesPresentCompanion(candidate, presentByNPCID)
    local companions = GetCandidateCompanions(candidate)
    if type(companions) ~= "table" then
        return false
    end
    for npcID in pairs(companions) do
        if presentByNPCID[tonumber(npcID)] == true then
            return true
        end
    end
    return false
end

local function CollectPresentByNPCID(runtime, mapID)
    local bucket = GetMapBucket(mapID, false)
    if type(bucket) ~= "table" then
        return {}
    end
    local presentByNPCID = {}
    for npcID, runtimes in pairs(bucket) do
        if type(runtimes) == "table" then
            for lockedRuntime in pairs(runtimes) do
                if lockedRuntime ~= runtime then
                    presentByNPCID[tonumber(npcID)] = true
                    break
                end
            end
        end
    end
    return presentByNPCID
end

function Mod.HasCompanionRequirement(candidates)
    if type(candidates) ~= "table" then
        return false
    end
    for i = 1, #candidates do
        if HasCompanionRequirement(candidates[i]) then
            return true
        end
    end
    return false
end

-- 超时后仅供暂定展示/计时使用：没有正向同场证据的依赖候选被暂时排除。
-- 只有余下一项时才返回；调用方不得把它写入 identity lock。
function Mod.GetTentativeFallback(candidates, runtime, mapID)
    if type(candidates) ~= "table" or #candidates <= 1 then
        return nil
    end
    local presentByNPCID = CollectPresentByNPCID(runtime, mapID)
    local filtered = {}
    local removedAny = false
    for i = 1, #candidates do
        local candidate = candidates[i]
        local hasRequirement = HasCompanionRequirement(candidate)
        local hasPositiveMatch = hasRequirement and CandidateMatchesPresentCompanion(candidate, presentByNPCID)
        if hasRequirement and not hasPositiveMatch then
            removedAny = true
        else
            filtered[#filtered + 1] = candidate
        end
    end
    if removedAny and #filtered == 1 then
        return filtered[1]
    end
    return nil
end

function Mod.FilterCandidates(candidates, runtime, mapID, trace)
    if type(candidates) ~= "table" or #candidates <= 1 then
        return candidates, false, trace == true and {
            mapID = tonumber(mapID), inputCount = type(candidates) == "table" and #candidates or 0,
            outputCount = type(candidates) == "table" and #candidates or 0,
            reason = "not-ambiguous",
        } or nil
    end
    local bucket = GetMapBucket(mapID, false)
    if type(bucket) ~= "table" then
        return candidates, false, trace == true and {
            mapID = tonumber(mapID), inputCount = #candidates, outputCount = #candidates, reason = "no-locked-companion",
        } or nil
    end

    local presentByNPCID = CollectPresentByNPCID(runtime, mapID)
    if next(presentByNPCID) == nil then
        return candidates, false, trace == true and {
            mapID = tonumber(mapID), inputCount = #candidates, outputCount = #candidates, reason = "no-other-locked-companion",
        } or nil
    end

    local matched = {}
    local debug = trace == true and {
        mapID = tonumber(mapID),
        inputCount = #candidates,
        lockedNPCIDs = SortedNPCIDs(presentByNPCID),
        candidates = {},
    } or nil
    for i = 1, #candidates do
        local candidate = candidates[i]
        local isMatch = CandidateMatchesPresentCompanion(candidate, presentByNPCID)
        if debug then
            local row = type(candidate) == "table" and candidate.row or nil
            local companions = type(candidate) == "table" and candidate.coPresenceNPCIDs or nil
            companions = type(companions) == "table" and companions
                or type(row) == "table" and row.coPresenceNPCIDs or nil
            debug.candidates[#debug.candidates + 1] = {
                npcID = tonumber(type(candidate) == "table" and candidate.npcID),
                requiredNPCIDs = SortedNPCIDs(companions),
                matched = isMatch == true,
            }
        end
        if isMatch then
            matched[#matched + 1] = candidate
        end
    end

    -- Only a positive companion match may narrow the list. A missing
    -- companion, or a list with no matching relation, leaves every candidate
    -- intact and can never imply a different NPC identity.
    if #matched == 0 then
        if debug then
            debug.outputCount = #candidates
            debug.applied = false
            debug.reason = "no-positive-match"
        end
        return candidates, false, debug
    end
    if debug then
        debug.outputCount = #matched
        debug.applied = #matched < #candidates
        debug.reason = debug.applied and "positive-match" or "all-matched"
    end
    return matched, #matched < #candidates, debug
end
