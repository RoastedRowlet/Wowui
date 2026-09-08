---@diagnostic disable: undefined-global
-- =============================================================
-- ExwindFramePicker — 通用框架拾取器
-- 用法: ExwindTools:StartFramePicker(onConfirm, onCancel)
--   onConfirm(frameName)  左键确认时调用
--   onCancel()            右键/ESC 取消时调用（可选）
-- =============================================================

local ExwindTools = _G.ExwindTools
if not ExwindTools then return end

local pickerOverlay   = nil
local highlightFrame  = nil

-- 递归获取框架名称
-- 优先 GetName → GetParentKey → pairs(parent) 遍历，最多 5 层
local function GetFrameName(frame, depth)
    depth = depth or 0
    if depth > 5 or not frame then return nil end

    local name = frame.GetName and frame:GetName()
    if type(name) == "string" and name ~= "" then return name end

    if depth == 0 then
        for k, v in pairs(_G) do
            if v == frame and type(k) == "string" then return k end
        end
    end

    local parent = frame.GetParent and frame:GetParent()
    if not parent then return nil end

    local parentKey = frame.GetParentKey and frame:GetParentKey()
    if not parentKey then
        for k, v in pairs(parent) do
            if v == frame and type(k) == "string" then
                parentKey = k
                break
            end
        end
    end

    if parentKey then
        local pName = GetFrameName(parent, depth + 1)
        if pName then return pName .. "." .. parentKey end
    end
    return nil
end

local function StopPicker(confirmed, frameName, onConfirm, onCancel)
    if pickerOverlay then pickerOverlay:SetScript("OnUpdate", nil) end
    if highlightFrame then highlightFrame:Hide() end
    ResetCursor()
    GameTooltip:Hide()
    if confirmed and frameName and type(onConfirm) == "function" then
        onConfirm(frameName)
    elseif not confirmed and type(onCancel) == "function" then
        onCancel()
    end
end

function ExwindTools:StartFramePicker(onConfirm, onCancel)
    if not pickerOverlay then
        pickerOverlay = CreateFrame("Frame")
    end
    if not highlightFrame then
        highlightFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        highlightFrame:SetFrameStrata("TOOLTIP")
    end

    local lastFocus     = nil
    local lastFocusName = nil
    local leftWasDown   = false

    local L = ExwindTools.L or {}
    local function T(key, fallback)
        return (type(L[key]) == "string" and L[key]) or fallback
    end

    pickerOverlay:SetScript("OnUpdate", function(self)
        -- 右键 / ESC：取消
        if IsMouseButtonDown("RightButton") or IsKeyDown("ESCAPE") then
            StopPicker(false, nil, onConfirm, onCancel)
            return
        end

        SetCursor("CAST_CURSOR")

        -- 左键：用上一帧缓存确认，避免点击瞬间 focus 被 Tooltip 抢走
        local leftDown = IsMouseButtonDown("LeftButton")
        if leftDown and not leftWasDown and lastFocusName then
            StopPicker(true, lastFocusName, onConfirm, onCancel)
            return
        end
        leftWasDown = leftDown

        -- 兼容新旧 WoW API
        local focus
        if GetMouseFocus then
            focus = GetMouseFocus()
        end
        if (not focus or focus == WorldFrame) and GetMouseFoci then
            local foci = GetMouseFoci()
            if type(foci) == "table" then
                for _, candidate in ipairs(foci) do
                    if candidate and candidate ~= WorldFrame and candidate ~= highlightFrame then
                        focus = candidate
                        break
                    end
                end
            end
        end

        if focus and focus ~= WorldFrame and focus ~= highlightFrame then
            local name = GetFrameName(focus)
            if name then
                if focus ~= lastFocus then
                    -- 高亮边框
                    local targetLevel = (type(focus.GetFrameLevel) == "function" and focus:GetFrameLevel()) or 0
                    highlightFrame:SetFrameLevel(targetLevel + 20)
                    highlightFrame:ClearAllPoints()
                    highlightFrame:SetPoint("TOPLEFT",     focus, "TOPLEFT",     -2,  2)
                    highlightFrame:SetPoint("BOTTOMRIGHT", focus, "BOTTOMRIGHT",  2, -2)
                    highlightFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
                    highlightFrame:SetBackdropBorderColor(0, 1, 0, 1)
                    highlightFrame:Show()
                    lastFocus     = focus
                    lastFocusName = name
                end
                GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
                GameTooltip:SetText("|cff00ff00" .. T(L["拾取中: "], "Picking: ") .. "|r" .. name)
                GameTooltip:AddLine("|cffffffff" .. T(L["左键 : 选择该框架"], "Left Click: Select Frame") .. "|r")
                GameTooltip:AddLine("|cffaaaaaa" .. T(L["右键/ESC : 取消退出"], "Right Click / ESC: Cancel") .. "|r")
                GameTooltip:Show()
                return
            else
                GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
                GameTooltip:SetText("|cffff8800" .. T(L["无法识别该框架"], "Frame not identifiable") .. "|r")
                GameTooltip:AddLine("|cffaaaaaa" .. T(L["右键/ESC : 取消退出"], "Right Click / ESC: Cancel") .. "|r")
                GameTooltip:Show()
            end
        end

        highlightFrame:Hide()
        lastFocus     = nil
        lastFocusName = nil
        GameTooltip:Hide()
    end)
end
