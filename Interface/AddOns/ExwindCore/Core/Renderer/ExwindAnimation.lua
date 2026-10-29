-- =========================================================
-- ExwindAnimation.lua
-- 任意框体 / 区域（Frame、Texture、FontString）通用的现成动画，全部用原生 AnimationGroup。
-- 每个目标只建一个单次动画组和一个呼吸动画组，重复调用只改参数后重播，不新建。
--
--   EXUI:PlayAnimation(target, spec, onFinished)  组合动画，spec 各项可同时出现：
--       duration   秒，默认 .25；smoothing 默认 "OUT"（NONE / IN / OUT / IN_OUT）
--       alpha      = { from, to }       透明度，播完停在 to
--       scale      = { from, to }       以中心缩放的倍数；只改显示，播完回到原尺寸
--       slide      = { x, y }           从原位偏移 (x, y) 处滑回原位
--       hideOnFinish = true             播完把 target 藏起来（淡出常用）
--     例：从 0.6 倍放大到 2 倍同时淡出
--       EXUI:PlayAnimation(f, { scale = { .6, 2 }, alpha = { 1, 0 }, duration = .4 }, cb)
--   EXUI:FadeIn(target, duration, onFinished)              显示并从 0 淡到 1
--   EXUI:FadeOut(target, duration, onFinished, hide)       从当前透明度淡到 0，hide 为真时播完隐藏
--   EXUI:PlayScale(target, from, to, duration, onFinished) 从 from 倍缩放到 to 倍
--   EXUI:SlideIn(target, x, y, duration, onFinished)       从偏移 (x, y) 滑入并淡入
--   EXUI:StopAnimation(target) / EXUI:IsAnimationPlaying(target)
--     停下时不调 onFinished；新一次播放会顶掉上一次（上一次的 onFinished 不再调）。
--   EXUI:StartBreath(target, scale, duration)  呼吸：以中心放大到 scale 倍再缩回、循环，
--       duration 是放大或缩回一段的秒数；参数没变时重复调用不打断正在播的循环。
--   EXUI:StopBreath(target)
-- =========================================================

local ExwindTools = _G.ExwindTools
local EXUI = ExwindTools and ExwindTools.UI
if not EXUI then return end

local NO_SCALE = { 1, 1 }
local NO_SLIDE = { 0, 0 }

local function OneShotState(target)
    local state = target._exAnimation
    if state then return state end
    local group = target:CreateAnimationGroup()
    group:SetLooping("NONE")
    group:SetToFinalAlpha(true)
    state = { group = group }
    state.alpha = group:CreateAnimation("Alpha")
    state.scale = group:CreateAnimation("Scale")
    state.scale:SetOrigin("CENTER", 0, 0)
    -- 平移没有起点参数：先用一段极短的平移跳到偏移处，再用同时开始的另一段滑回，两段相加归零。
    state.slideJump = group:CreateAnimation("Translation")
    state.slideJump:SetDuration(.001)
    state.slide = group:CreateAnimation("Translation")
    for _, animation in ipairs({ state.alpha, state.scale, state.slideJump, state.slide }) do
        animation:SetOrder(1)
    end
    group:SetScript("OnFinished", function()
        local callback, hide = state.onFinished, state.hideOnFinish
        state.onFinished, state.hideOnFinish = nil, nil
        if hide then target:Hide() end
        if callback then callback(target) end
    end)
    target._exAnimation = state
    return state
end

function EXUI:PlayAnimation(target, spec, onFinished)
    assert(type(spec) == "table", "PlayAnimation requires a spec table")
    local state = OneShotState(target)
    local group = state.group
    group:Stop()
    local duration = math.max(.01, tonumber(spec.duration) or .25)
    local smoothing = spec.smoothing or "OUT"
    -- 没写的项设成原地不动，保证同一组动画可以任意组合。
    local currentAlpha = target:GetAlpha()
    local alpha = spec.alpha or { currentAlpha, currentAlpha }
    state.alpha:SetFromAlpha(alpha[1] or currentAlpha)
    state.alpha:SetToAlpha(alpha[2] or currentAlpha)
    local scale = spec.scale or NO_SCALE
    state.scale:SetScaleFrom(scale[1] or 1, scale[1] or 1)
    state.scale:SetScaleTo(scale[2] or 1, scale[2] or 1)
    local slide = spec.slide or NO_SLIDE
    local x, y = tonumber(slide[1] or slide.x) or 0, tonumber(slide[2] or slide.y) or 0
    state.slideJump:SetOffset(x, y)
    state.slide:SetOffset(-x, -y)
    for _, animation in ipairs({ state.alpha, state.scale, state.slide }) do
        animation:SetDuration(duration)
        animation:SetSmoothing(smoothing)
    end
    state.onFinished, state.hideOnFinish = onFinished, spec.hideOnFinish == true
    group:Play()
    return group
end

function EXUI:FadeIn(target, duration, onFinished)
    target:Show()
    return self:PlayAnimation(target, { alpha = { 0, 1 }, duration = duration }, onFinished)
end

function EXUI:FadeOut(target, duration, onFinished, hide)
    return self:PlayAnimation(target, { alpha = { target:GetAlpha(), 0 }, duration = duration,
        hideOnFinish = hide }, onFinished)
end

function EXUI:PlayScale(target, from, to, duration, onFinished)
    return self:PlayAnimation(target, { scale = { from, to }, duration = duration }, onFinished)
end

function EXUI:SlideIn(target, x, y, duration, onFinished)
    target:Show()
    return self:PlayAnimation(target, { slide = { x, y }, alpha = { 0, 1 }, duration = duration }, onFinished)
end

function EXUI:StopAnimation(target)
    local state = target._exAnimation
    if not state then return end
    state.onFinished, state.hideOnFinish = nil, nil
    state.group:Stop()
end

function EXUI:IsAnimationPlaying(target)
    local state = target._exAnimation
    return state ~= nil and state.group:IsPlaying()
end

-- 呼吸照暴雪法术触发材质（SpellActivationOverlay 的 pulse 组）：以中心放大再缩回、循环。
function EXUI:StartBreath(target, scale, duration)
    scale = math.max(1, tonumber(scale) or 1)
    duration = math.max(.05, tonumber(duration) or .5)
    local state = target._exBreath
    if not state then
        local group = target:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        state = { group = group, up = group:CreateAnimation("Scale"), down = group:CreateAnimation("Scale") }
        for order, animation in ipairs({ state.up, state.down }) do
            animation:SetOrder(order)
            animation:SetSmoothing("IN_OUT")
            animation:SetOrigin("CENTER", 0, 0)
        end
        target._exBreath = state
    end
    if state.scale ~= scale or state.duration ~= duration then
        state.group:Stop()
        state.up:SetDuration(duration)
        state.up:SetScale(scale, scale)
        state.down:SetDuration(duration)
        state.down:SetScale(1 / scale, 1 / scale)
        state.scale, state.duration = scale, duration
    end
    if not state.group:IsPlaying() then state.group:Play() end
    return state.group
end

function EXUI:StopBreath(target)
    local state = target._exBreath
    if state then state.group:Stop() end
end
