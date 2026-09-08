---@diagnostic disable: undefined-global

ExBoss = ExBoss or {}

local BorderUtil = ExBoss.BorderUtil or {}
ExBoss.BorderUtil = BorderUtil

local function SafeNum(value, defaultValue)
    local n = tonumber(value)
    if n == nil then
        return defaultValue
    end
    return n
end

function BorderUtil.Ensure(ownerFrame, key, parentFrame)
    if not ownerFrame or not key or not parentFrame then
        return nil
    end
    local borderFrame = ownerFrame[key]
    if borderFrame then
        return borderFrame
    end

    borderFrame = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    borderFrame:Hide()
    ownerFrame[key] = borderFrame
    return borderFrame
end

function BorderUtil.Apply(borderFrame, targetFrame, texturePath, edgeSize, padding, r, g, b, a, frameLevel)
    if not borderFrame or not targetFrame or not texturePath or texturePath == "" then
        if borderFrame then
            borderFrame:Hide()
        end
        return
    end

    edgeSize = math.max(1, math.floor(SafeNum(edgeSize, 1)))
    padding = SafeNum(padding, 0)

    if frameLevel then
        borderFrame:SetFrameLevel(frameLevel)
    end
    borderFrame:ClearAllPoints()
    borderFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -padding, padding)
    borderFrame:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", padding, -padding)

    if borderFrame.SetBackdrop then
        borderFrame:SetBackdrop({ edgeFile = texturePath, edgeSize = edgeSize })
        borderFrame:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
    end

    borderFrame:Show()
end

function BorderUtil.SetColor(borderFrame, r, g, b, a)
    if borderFrame and borderFrame.SetBackdropBorderColor then
        borderFrame:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
    end
end

function BorderUtil.Hide(borderFrame)
    if borderFrame then
        borderFrame:Hide()
    end
end
