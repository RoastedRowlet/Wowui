---@diagnostic disable: undefined-global
-- ExwindUnitFrame.lua
-- 统一单位框架检测层 —— 覆盖所有主流团队框架插件
-- 对外 API：ExwindTools.UnitFrame.FindUnitFrame(unit [, opts])

ExwindTools = ExwindTools or {}
ExwindTools.UnitFrame = ExwindTools.UnitFrame or {}

local Mod = ExwindTools.UnitFrame
local frameCache = {}
local SelectMatchingFrame

local function BuildCacheKey(unit, opts)
    local preferGrouped = type(opts) == "table" and opts.preferGroupedPlayerFrame == true
    return unit .. "\31" .. (preferGrouped and "grouped" or "default")
end

local function GetCachedFrame(unit, opts)
    local cacheKey = BuildCacheKey(unit, opts)
    local frame = frameCache[cacheKey]
    if SelectMatchingFrame(frame, unit) then
        return frame
    end
    frameCache[cacheKey] = nil
    return nil
end

local function SetCachedFrame(unit, opts, frame)
    local cacheKey = BuildCacheKey(unit, opts)
    if frame then
        frameCache[cacheKey] = frame
    else
        frameCache[cacheKey] = nil
    end
end

function Mod.ClearCache()
    for key in pairs(frameCache) do
        frameCache[key] = nil
    end
end

function Mod.InvalidateUnit(unit)
    if type(unit) ~= "string" then return end
    frameCache[unit .. "\31default"] = nil
    frameCache[unit .. "\31grouped"] = nil
end

-- ============================================================
-- § 1  底层工具函数
-- ============================================================

local function IsUsableFrame(frame)
    if frame == nil then return false end
    local t = type(frame)
    if t ~= "table" and t ~= "userdata" then return false end
    if type(frame.IsShown) ~= "function" then return false end
    local okShown, isShown = pcall(frame.IsShown, frame)
    if not okShown or not isShown then return false end
    if type(frame.IsVisible) == "function" then
        local okVis, isVis = pcall(frame.IsVisible, frame)
        if okVis and not isVis then return false end
    end
    if type(frame.GetObjectType) == "function" then
        local okT, ot = pcall(frame.GetObjectType, frame)
        if okT and type(ot) == "string" and ot == "" then return false end
    end
    if type(frame.GetPoint) ~= "function" and type(frame.SetPoint) ~= "function" then
        return false
    end
    return true
end

-- 安全的单位比较（符合 12.0.5：不判断 == false，只判断 truthy）
local function SameUnit(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    if not UnitIsUnit then return false end
    local ok, result = pcall(UnitIsUnit, a, b)
    return ok and result
end

local function FrameMatchesUnit(frame, unit)
    if not frame or not unit then return false end
    if SameUnit(frame.unit, unit) then return true end
    if SameUnit(frame.displayedUnit, unit) then return true end
    -- Cell 按钮额外存放在 states 里
    if type(frame.states) == "table" then
        if SameUnit(frame.states.unit, unit) then return true end
        if SameUnit(frame.states.displayedUnit, unit) then return true end
    end
    if type(frame.GetAttribute) == "function" then
        local ok, val = pcall(frame.GetAttribute, frame, "unit")
        if ok and SameUnit(val, unit) then return true end
    end
    return false
end

SelectMatchingFrame = function(frame, unit)
    if IsUsableFrame(frame) and FrameMatchesUnit(frame, unit) then return frame end
    return nil
end

-- keysAreFrames=true：pairs 遍历时 key 是 frame（如 Grid2 的 activatedFrames）
-- keysAreFrames=false：value 是 frame（如数组）
local function SelectFromFrameList(frames, unit, keysAreFrames)
    if type(frames) ~= "table" then return nil end
    for k, v in pairs(frames) do
        local frame = keysAreFrames and k or v
        local matched = SelectMatchingFrame(frame, unit)
        if matched then return matched end
    end
    return nil
end

local function GetSafeChildren(frame)
    if frame == nil or type(frame.GetChildren) ~= "function" then return nil end
    local ok, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10,
               c11, c12, c13, c14, c15, c16, c17, c18, c19, c20 =
        pcall(frame.GetChildren, frame)
    if not ok then return nil end
    return { c1, c2, c3, c4, c5, c6, c7, c8, c9, c10,
             c11, c12, c13, c14, c15, c16, c17, c18, c19, c20 }
end

-- 在容器及其后代中递归找匹配 unit 的框架（限 depth 层，防止卡顿）
local function FindInContainer(container, unit, depth)
    if not container then return nil end
    if SelectMatchingFrame(container, unit) then return container end
    depth = tonumber(depth) or 0
    if depth >= 3 then return nil end
    local children = GetSafeChildren(container)
    if not children then return nil end
    for i = 1, #children do
        local child = children[i]
        local matched = SelectMatchingFrame(child, unit)
        if matched then return matched end
        local nested = FindInContainer(child, unit, depth + 1)
        if nested then return nested end
    end
    return nil
end

-- 在 SecureGroupHeader 子控件里按 childN attribute 遍历
local function FindInHeaderByAttribute(header, unit, maxDepth)
    if not header then return nil end
    if SelectMatchingFrame(header, unit) then return header end
    maxDepth = tonumber(maxDepth) or 4
    local i = 1
    while i <= 40 do
        if not header.GetAttribute then break end
        local ok, child = pcall(header.GetAttribute, header, "child" .. i)
        if not ok or not child then break end
        local matched = FindInHeaderByAttribute(child, unit, maxDepth - 1)
        if matched then return matched end
        i = i + 1
    end
    local children = GetSafeChildren(header)
    if children then
        for _, child in ipairs(children) do
            local matched = SelectMatchingFrame(child, unit)
            if matched then return matched end
        end
    end
    return nil
end

-- ============================================================
-- § 2  IsAddonLoadedCompat（兼容新旧 API）
-- ============================================================

local function IsAddonLoadedCompat(name)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(name) == true
    end
    if type(_G.IsAddOnLoaded) == "function" then
        return _G.IsAddOnLoaded(name) == true
    end
    return false
end

-- 暴露供调用方使用
Mod.IsAddonLoadedCompat = IsAddonLoadedCompat

-- ============================================================
-- § 3  Cell 框架检测
-- 访问方式：Cell.unitButtons.{raid|party|solo|npc}.units[unit]
-- 按钮对象同时含 button.unit 和 button.states.unit
-- ============================================================

local function FindCellFrame(unit)
    local Cell = _G.Cell
    if type(Cell) ~= "table" then return nil end
    local ub = Cell.unitButtons
    if type(ub) ~= "table" then return nil end

    local function TrySection(section)
        if type(section) ~= "table" then return nil end
        -- 先检查 .units[unit] 直接映射
        if type(section.units) == "table" then
            local btn = section.units[unit]
            if IsUsableFrame(btn) then return btn end
        end
        -- solo 存储方式不同，key 直接是 unit token
        if IsUsableFrame(section[unit]) then return section[unit] end
        return nil
    end

    -- 优先顺序：raid > party > solo > npc
    return TrySection(ub.raid)
        or TrySection(ub.party)
        or TrySection(ub.solo)
        or TrySection(ub.npc)
end

-- ============================================================
-- § 4  DandersFrames 框架检测
-- 官方 API：DandersFrames.Api.GetFrameForUnit(unit, kind)
--   kind 必须传 "party" 或 "raid"，两者都要试
-- 全局函数：DandersFrames_GetFrameForUnit(unit) — 已自动搜索两种
-- ============================================================

local function FindDandersFrame(unit)
    -- 优先走官方 Api（两种 kind 都试）
    local DF = _G.DandersFrames
    if type(DF) == "table" and type(DF.Api) == "table" then
        local api = DF.Api
        if type(api.GetFrameForUnit) == "function" then
            for _, kind in ipairs({ "party", "raid" }) do
                local ok, frame = pcall(api.GetFrameForUnit, unit, kind)
                local matched = ok and SelectMatchingFrame(frame, unit)
                if matched then return matched end
            end
        end
    end

    -- 全局函数：DandersFrames_GetFrameForUnit（内部已搜索两种 kind）
    local fn = _G.DandersFrames_GetFrameForUnit
    if type(fn) == "function" then
        local ok, frame = pcall(fn, unit)
        local matched = ok and SelectMatchingFrame(frame, unit)
        if matched then return matched end
    end

    -- 全局函数：DandersFrames_GetPinnedFrameForUnit
    fn = _G.DandersFrames_GetPinnedFrameForUnit
    if type(fn) == "function" then
        local ok, frame = pcall(fn, unit)
        local matched = ok and SelectMatchingFrame(frame, unit)
        if matched then return matched end
    end

    -- 全局迭代器
    fn = _G.DandersFrames_IterateFrames
    if type(fn) == "function" then
        local found
        pcall(fn, function(frame)
            found = found or SelectMatchingFrame(frame, unit)
            return found ~= nil
        end)
        if found then return found end
    end

    -- 全量帧列表
    fn = _G.DandersFrames_GetAllFrames
    if type(fn) == "function" then
        local ok, frames = pcall(fn)
        local matched = ok and SelectFromFrameList(frames, unit, false)
        if matched then return matched end
    end

    return nil
end

-- ============================================================
-- § 5  Grid2 框架检测
-- Grid2:GetUnitFrames(unit) → frames_of_unit[unit]（key=frame）
-- Grid2Frame.frames_of_unit、activatedFrames、registeredFrames
-- ============================================================

local function FindGrid2Frame(unit)
    local Grid2 = _G.Grid2
    if type(Grid2) == "table" and type(Grid2.GetUnitFrames) == "function" then
        local ok, frames = pcall(Grid2.GetUnitFrames, Grid2, unit)
        local matched = ok and SelectFromFrameList(frames, unit, true)
        if matched then return matched end
    end

    local G2F = _G.Grid2Frame
    if type(G2F) == "table" then
        -- frames_of_unit[unit] 是 {[frame]=true} 形式的 set
        local fou = G2F.frames_of_unit
        if type(fou) == "table" and type(fou[unit]) == "table" then
            local matched = SelectFromFrameList(fou[unit], unit, true)
            if matched then return matched end
        end

        -- activatedFrames：[frame] = unit，只含当前有单位的帧
        local af = G2F.activatedFrames
        if type(af) == "table" then
            for frame, frameUnit in pairs(af) do
                if SameUnit(frameUnit, unit) and IsUsableFrame(frame) then
                    return frame
                end
            end
        end

        -- registeredFrames：[frameName] = frame，含所有已创建帧（含未激活）
        local matched = SelectFromFrameList(G2F.registeredFrames, unit, false)
        if matched then return matched end
    end

    return nil
end

-- ============================================================
-- § 6  VuhDo 框架检测
-- 全局：VUHDO_UNIT_BUTTONS[unit] → {buttons}
--       VUHDO_getUnitButtonsSafe(unit) → buttons or {}
--       VUHDO_resolveVehicleUnit(unit) → 载具单位解析
-- ============================================================

local function SelectFromVuhDoSet(buttons, unit)
    if type(buttons) ~= "table" then return nil end
    for _, btn in pairs(buttons) do
        if IsUsableFrame(btn) then
            -- VuhDo 的 UNIT_BUTTONS 已经按 unit 分组，直接返回第一个可用帧
            -- 同时也检查 FrameMatchesUnit 作为安全守卫
            if FrameMatchesUnit(btn, unit) or true then
                return btn
            end
        end
    end
    return nil
end

local function FindVuhDoFrame(unit)
    if not (_G.VUHDO_UNIT_BUTTONS or _G.VUHDO_getUnitButtons
            or _G.VUHDO_getUnitButtonsSafe or IsAddonLoadedCompat("VuhDo")) then
        return nil
    end

    -- 载具单位解析（VuhDo 可能把单位映射到载具）
    local candidates = { unit }
    local resolveVehicle = _G.VUHDO_resolveVehicleUnit
    if type(resolveVehicle) == "function" then
        local ok, resolved = pcall(resolveVehicle, unit)
        if ok and type(resolved) == "string" and resolved ~= unit then
            candidates[#candidates + 1] = resolved
        end
    end

    local getUnitButtonsSafe = _G.VUHDO_getUnitButtonsSafe
    local getUnitButtons     = _G.VUHDO_getUnitButtons

    for _, candidate in ipairs(candidates) do
        if type(getUnitButtonsSafe) == "function" then
            local ok, btns = pcall(getUnitButtonsSafe, candidate)
            if ok then
                local matched = SelectFromVuhDoSet(btns, unit)
                if matched then return matched end
            end
        end
        if type(getUnitButtons) == "function" then
            local ok, btns = pcall(getUnitButtons, candidate)
            if ok then
                local matched = SelectFromVuhDoSet(btns, unit)
                if matched then return matched end
            end
        end
    end

    -- 全量遍历 VUHDO_UNIT_BUTTONS（key = vuhDoUnit）
    local ub = _G.VUHDO_UNIT_BUTTONS
    if type(ub) == "table" then
        for vuhDoUnit, btns in pairs(ub) do
            if SameUnit(vuhDoUnit, unit) then
                local matched = SelectFromVuhDoSet(btns, unit)
                if matched then return matched end
            end
        end
    end

    -- 兜底：VUHDO_UNIT_BUTTONS_PANEL（多面板布局）
    local ubp = _G.VUHDO_UNIT_BUTTONS_PANEL
    if type(ubp) == "table" then
        for vuhDoUnit, panels in pairs(ubp) do
            if SameUnit(vuhDoUnit, unit) and type(panels) == "table" then
                for _, btns in pairs(panels) do
                    local matched = SelectFromVuhDoSet(btns, unit)
                    if matched then return matched end
                end
            end
        end
    end

    return nil
end

-- ============================================================
-- § 7  ElvUI 框架检测
-- 引擎对象：_G.ElvUI[1] → E；E:GetModule("UnitFrames") → UF
-- 命名框架：ElvUF_Party、ElvUF_Raid1~3、ElvUF_Tank、ElvUF_Assist
-- 多分组：ElvUF_Raid1Group1..8、子按钮 ElvUF_Raid1Group1UnitButton1..40
-- ============================================================

local function GetElvUIUnitFrames()
    local engine = _G.ElvUI
    if type(engine) ~= "table" then return nil end
    local E = type(engine[1]) == "table" and engine[1] or engine
    if not (type(E) == "table" and type(E.GetModule) == "function") then return nil end
    local ok, UF = pcall(E.GetModule, E, "UnitFrames")
    if ok and type(UF) == "table" then return UF end
    return nil
end

local function FindElvUIHeaderFrame(header, unit, depth)
    if not header then return nil end
    local matched = SelectMatchingFrame(header, unit)
    if matched then return matched end
    depth = tonumber(depth) or 0
    if depth >= 4 then return nil end
    -- SecureGroupHeader 子控件通过 attribute "childN" 访问
    if type(header.GetAttribute) == "function" then
        local i = 1
        while i <= 40 do
            local ok, child = pcall(header.GetAttribute, header, "child" .. i)
            if not ok or not child then break end
            matched = FindElvUIHeaderFrame(child, unit, depth + 1)
            if matched then return matched end
            i = i + 1
        end
    end
    local children = GetSafeChildren(header)
    if children then
        for i = 1, #children do
            matched = FindElvUIHeaderFrame(children[i], unit, depth + 1)
            if matched then return matched end
        end
    end
    return nil
end

local function FindNamedElvUIFrame(unit)
    local inGroup = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())

    -- 独立玩家帧：队伍里时降为最后兜底，避免优先命中 ElvUF_Player
    if unit ~= "player" or not inGroup then
        local matched = SelectMatchingFrame(_G["ElvUF_Player"], unit)
        if matched then return matched end
    end

    -- 队伍/团队 header 直接匹配
    local groupDirectNames = {
        "ElvUF_Party",
        "ElvUF_Raid1", "ElvUF_Raid2", "ElvUF_Raid3",
        "ElvUF_Tank",  "ElvUF_Assist",
    }
    for _, name in ipairs(groupDirectNames) do
        local matched = SelectMatchingFrame(_G[name], unit)
        if matched then return matched end
    end

    -- 以上框架作为 header 递归搜索子帧
    for _, name in ipairs(groupDirectNames) do
        local matched = FindElvUIHeaderFrame(_G[name], unit, 0)
        if matched then return matched end
    end

    -- 多分组布局：ElvUF_Raid1Group1..8
    local groupPrefixes = {
        "ElvUF_PartyGroup",
        "ElvUF_Raid1Group", "ElvUF_Raid2Group", "ElvUF_Raid3Group",
        "ElvUF_TankGroup",  "ElvUF_AssistGroup",
    }
    for _, prefix in ipairs(groupPrefixes) do
        for i = 1, 8 do
            local matched = FindElvUIHeaderFrame(_G[prefix .. i], unit, 0)
            if matched then return matched end
        end
    end

    -- 子按钮直接命名（ElvUI 某些版本会给子帧全局名）
    local buttonPrefixes = {
        "ElvUF_PartyGroup1UnitButton",
        "ElvUF_Raid1Group1UnitButton", "ElvUF_Raid2Group1UnitButton",
        "ElvUF_Raid3Group1UnitButton",
        "ElvUF_TankGroup1UnitButton",  "ElvUF_AssistGroup1UnitButton",
    }
    for _, prefix in ipairs(buttonPrefixes) do
        for i = 1, 40 do
            local matched = SelectMatchingFrame(_G[prefix .. i], unit)
            if matched then return matched end
        end
    end

    -- 队伍里找不到时兜底返回 ElvUF_Player
    if unit == "player" and inGroup then
        local matched = SelectMatchingFrame(_G["ElvUF_Player"], unit)
        if matched then return matched end
    end

    return nil
end

local function FindElvUIFrame(unit)
    local inGroup = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())

    -- 先按名称找（内部已处理队伍里 ElvUF_Player 降权）
    local matched = FindNamedElvUIFrame(unit)
    if matched then return matched end

    local UF = GetElvUIUnitFrames()
    if type(UF) ~= "table" then return nil end

    -- groupunits（队伍/团队帧池）
    if type(UF.groupunits) == "table" then
        for frameUnit in pairs(UF.groupunits) do
            matched = SelectMatchingFrame(UF[frameUnit], unit)
            if matched then return matched end
        end
    end

    -- UF.headers（动态多分组 header）
    if type(UF.headers) == "table" then
        for _, header in pairs(UF.headers) do
            matched = FindElvUIHeaderFrame(header, unit, 0)
            if matched then return matched end
        end
    end

    -- ElvUF.objects（oUF 全量已生成对象）
    local ElvUF = _G["ElvUF"]
    if type(ElvUF) == "table" and type(ElvUF.objects) == "table" then
        -- 队伍里时跳过独立玩家帧对象
        for _, frame in pairs(ElvUF.objects) do
            if not (unit == "player" and inGroup and frame == _G["ElvUF_Player"]) then
                matched = SelectMatchingFrame(frame, unit)
                if matched then return matched end
            end
        end
    end

    -- UF.units[unit] / UF[unit]：可能直接命中单人玩家帧，放最后
    matched = (UF.units and SelectMatchingFrame(UF.units[unit], unit))
               or SelectMatchingFrame(UF[unit], unit)
    if matched then return matched end

    if type(UF.units) == "table" then
        matched = SelectFromFrameList(UF.units, unit, false)
        if matched then return matched end
    end

    return nil
end

-- ============================================================
-- § 8  NDui 框架检测
-- NDui 使用内置 oUF（私有命名空间），但把帧暴露为全局名：
--   oUF_Player, oUF_Target, oUF_Pet, oUF_Focus, oUF_FocusTarget
--   oUF_Boss1~5, oUF_Arena1~5
--   oUF_Party（SecureGroupHeader，子帧可通过 GetChildren 遍历）
--   oUF_Raid / oUF_Raid1..N（团队模式）
-- ============================================================

local function FindNDuiFrame(unit)
    -- 必须先确认 NDui 已加载，避免误命中其他 oUF 系插件
    if type(_G.NDui) ~= "table" and not IsAddonLoadedCompat("NDui") then
        return nil
    end

    local inGroup = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())

    -- 玩家在队伍里时，先找队伍/团队帧（oUF_Party / oUF_Raid），再返回 oUF_Player
    -- 其他单位直接从命名帧开始
    if unit ~= "player" or not inGroup then
        local singleNames = {
            "oUF_Player", "oUF_Target", "oUF_ToT",
            "oUF_Pet", "oUF_Focus", "oUF_FocusTarget",
        }
        for _, name in ipairs(singleNames) do
            local matched = SelectMatchingFrame(_G[name], unit)
            if matched then return matched end
        end
    end

    -- Boss / Arena 帧
    for i = 1, 5 do
        local matched = SelectMatchingFrame(_G["oUF_Boss" .. i], unit)
        if matched then return matched end
        matched = SelectMatchingFrame(_G["oUF_Arena" .. i], unit)
        if matched then return matched end
    end

    -- Party header 子帧
    local partyHeader = _G.oUF_Party
    if partyHeader then
        local matched = FindInContainer(partyHeader, unit, 2)
        if matched then return matched end
    end

    -- Raid header（单组 oUF_Raid，或多组 oUF_Raid1..N）
    local raidHeader = _G.oUF_Raid
    if raidHeader then
        local matched = FindInContainer(raidHeader, unit, 2)
        if matched then return matched end
    end
    for i = 1, 8 do
        local rh = _G["oUF_Raid" .. i]
        if rh then
            local matched = FindInContainer(rh, unit, 2)
            if matched then return matched end
        end
    end

    -- 玩家在队伍里时兜底：仍然找到 oUF_Player（以防队伍帧未显示玩家格）
    if unit == "player" and inGroup then
        local matched = SelectMatchingFrame(_G["oUF_Player"], unit)
        if matched then return matched end
    end

    return nil
end

-- ============================================================
-- § 9  EllesmereUIRaidFrames 框架检测
-- 全局：ERFPartySelfButton, ERFPartyHeader, ERFFlatHeader
--       ERFGroupHeader1~8, EllesmereUIRaidFrameContainer
-- ============================================================

local function FindEllesmereHeaderFrame(header, unit, maxButtons)
    if not header then return nil end
    local matched = SelectMatchingFrame(header, unit)
    if matched then return matched end
    maxButtons = tonumber(maxButtons) or 40
    for i = 1, maxButtons do
        local child = header[i]
        matched = SelectMatchingFrame(child, unit)
        if matched then return matched end
        if type(header.GetAttribute) == "function" then
            local ok, attrChild = pcall(header.GetAttribute, header, "child" .. i)
            if ok and attrChild then
                matched = SelectMatchingFrame(attrChild, unit)
                if matched then return matched end
            end
        end
    end
    return FindInContainer(header, unit)
end

local function FindEllesmereFrame(unit)
    local loaded = type(_G.EllesmereUIRaidFrames) ~= "nil"
    if not loaded then loaded = IsAddonLoadedCompat("EllesmereUIRaidFrames") end
    if not loaded then return nil end

    local matched = SelectMatchingFrame(_G.ERFPartySelfButton, unit)
    if matched then return matched end

    matched = FindEllesmereHeaderFrame(_G.ERFPartyHeader, unit, 5)
    if matched then return matched end

    matched = FindEllesmereHeaderFrame(_G.ERFFlatHeader, unit, 40)
    if matched then return matched end

    for i = 1, 8 do
        matched = FindEllesmereHeaderFrame(_G["ERFGroupHeader" .. i], unit, 5)
        if matched then return matched end
    end

    return FindInContainer(_G.EllesmereUIRaidFrameContainer, unit)
end

-- ============================================================
-- § 10  EQO / EQL 框架检测
-- 按前缀全局名枚举：EQOLUFPartyHeaderUnitButton、EQLUFPartyHeaderUnitButton 等
-- ============================================================

local function FindEQOFrame(unit)
    local buttonPrefixes = {
        "EQOLUFPartyHeaderUnitButton",
        "EQLUFPartyHeaderUnitButton",
        "EQLUPartyHeaderUnitButton",
    }
    for _, prefix in ipairs(buttonPrefixes) do
        for i = 1, 40 do
            local matched = SelectMatchingFrame(_G[prefix .. i], unit)
            if matched then return matched end
        end
    end

    local containers = {
        _G.EQOLUFPartyHeader,
        _G.EQLUFPartyHeader,
        _G.EQLUPartyHeader,
    }
    for _, container in ipairs(containers) do
        local matched = FindInContainer(container, unit)
        if matched then return matched end
    end

    return nil
end

-- ============================================================
-- § 11  player 优先找团队视角下的帧（避免返回单人的 PlayerFrame）
-- ============================================================

local function CollectMatchingFrames(container, unit, depth, out, seen)
    if not container then return end
    seen = seen or {}
    if seen[container] then return end
    seen[container] = true
    local matched = SelectMatchingFrame(container, unit)
    if matched then out[#out + 1] = matched end
    depth = tonumber(depth) or 0
    if depth >= 4 then return end
    local children = GetSafeChildren(container)
    if not children then return end
    for i = 1, #children do
        CollectMatchingFrames(children[i], unit, depth + 1, out, seen)
    end
end

local function ScoreGroupedPlayerFrame(frame)
    if not frame then return -math.huge end
    local score = 0
    if frame == PlayerFrame then score = score - 100 end
    local function ApplyNameScore(name, weight)
        if type(name) ~= "string" or name == "" then return end
        local lower = string.lower(name)
        if string.find(lower, "party",  1, true) then score = score + 40 * weight end
        if string.find(lower, "raid",   1, true) then score = score + 35 * weight end
        if string.find(lower, "group",  1, true) then score = score + 20 * weight end
        if string.find(lower, "header", 1, true) then score = score + 8  * weight end
        if string.find(lower, "player", 1, true) then score = score - 25 * weight end
    end
    if frame.GetName then ApplyNameScore(frame:GetName(), 1) end
    local parent = frame.GetParent and frame:GetParent()
    if parent and parent.GetName then ApplyNameScore(parent:GetName(), 0.5) end
    return score
end

local function FindPreferredGroupedPlayerFrame(unit)
    if unit ~= "player" then return nil end
    local candidates, seen = {}, {}
    CollectMatchingFrames(UIParent, unit, 0, candidates, seen)
    local bestFrame, bestScore = nil, -math.huge
    for _, frame in ipairs(candidates) do
        local score = ScoreGroupedPlayerFrame(frame)
        if score > bestScore then bestScore = score; bestFrame = frame end
    end
    return bestFrame
end

-- ============================================================
-- § 12  暴雪原生框架兜底
-- ============================================================

local function FindBlizzardFrame(unit)
    -- 12.0+ 新版 PartyFrame（MemberFrame1~4）
    if PartyFrame then
        for i = 1, 4 do
            local matched = SelectMatchingFrame(PartyFrame["MemberFrame" .. i], unit)
            if matched then return matched end
        end
    end

    -- CompactPartyFrame.memberUnitFrames（数组）
    local CompactPartyFrame = _G["CompactPartyFrame"]
    if type(CompactPartyFrame) == "table"
    and type(CompactPartyFrame.memberUnitFrames) == "table" then
        for _, frame in ipairs(CompactPartyFrame.memberUnitFrames) do
            local matched = SelectMatchingFrame(frame, unit)
            if matched then return matched end
        end
    end

    -- CompactPartyFrameMember1~5（旧版命名帧）
    for i = 1, 5 do
        local matched = SelectMatchingFrame(_G["CompactPartyFrameMember" .. i], unit)
        if matched then return matched end
    end

    -- CompactRaidFrame1~40
    for i = 1, 40 do
        local matched = SelectMatchingFrame(_G["CompactRaidFrame" .. i], unit)
        if matched then return matched end
    end

    -- 递归兜底（CompactRaidFrameContainer / CompactPartyFrame）
    local inContainer = FindInContainer(_G["CompactRaidFrameContainer"], unit)
        or FindInContainer(_G["CompactPartyFrame"], unit)
    if inContainer then return inContainer end

    -- 独立玩家帧最后兜底（单人或队伍帧里找不到时）
    if unit == "player" and IsUsableFrame(PlayerFrame) then return PlayerFrame end

    return nil
end

-- ============================================================
-- § 13  对外公开 API
-- ============================================================

--[[
opts 可选字段：
  preferGroupedPlayerFrame (bool)  — 对 "player" 单位优先返回团队视角下的帧
]]
function Mod.FindUnitFrame(unit, opts)
    if type(unit) ~= "string" then return nil end
    if UnitExists and not UnitExists(unit) then return nil end

    local cached = GetCachedFrame(unit, opts)
    if cached then return cached end

    -- player 优先团队视角
    if type(opts) == "table" and opts.preferGroupedPlayerFrame == true
    and unit == "player"
    and ((IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())) then
        local preferred = FindPreferredGroupedPlayerFrame(unit)
        if preferred then
            SetCachedFrame(unit, opts, preferred)
            return preferred
        end
    end

    -- 第三方框架优先级链
    local matched = FindCellFrame(unit)
        or FindDandersFrame(unit)
        or FindGrid2Frame(unit)
        or FindVuhDoFrame(unit)
        or FindElvUIFrame(unit)
        or FindNDuiFrame(unit)
        or FindEllesmereFrame(unit)
        or FindEQOFrame(unit)
        or FindBlizzardFrame(unit)
    SetCachedFrame(unit, opts, matched)
    return matched
end

-- 批量版本：返回 unit→frame 映射（nil 代表未找到）
function Mod.FindUnitFrames(units, opts)
    local result = {}
    if type(units) ~= "table" then return result end
    for i = 1, #units do
        local unit = units[i]
        result[unit] = Mod.FindUnitFrame(unit, opts)
    end
    return result
end

if type(ExwindTools.RegisterEvent) == "function" then
    ExwindTools:RegisterEvent("PLAYER_ENTERING_WORLD", "ExwindTools.UnitFrame.CacheWorld", function()
        Mod.ClearCache()
    end)
end
