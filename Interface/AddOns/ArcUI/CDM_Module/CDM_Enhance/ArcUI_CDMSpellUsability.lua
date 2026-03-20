-- ═══════════════════════════════════════════════════════════════════════════
-- ArcUI CDM Spell Usability
-- Runtime module for spell usability visuals on CDM (Cooldown Manager) frames.
-- Handles:
--   1. Usability vertex color tinting via RefreshIconColor hook
--   2. Usable glow via overlay pattern (Ellesmere method)
--
-- Shadow cooldown frame creation and feeding is owned by CooldownState.
-- This file only READS shadow state (IsShown) for glow decisions.
--
-- ALPHA is NOT managed here. CooldownState.ApplyReadyState merges usability
-- alpha into readyAlpha (single-writer pattern), eliminating flicker from
-- multiple systems fighting over SetAlpha.
--
-- EVENT-DRIVEN: CooldownState dispatch (which calls UpdateGlow) is now
-- triggered from SPELL_UPDATE_COOLDOWN hooks + shadow OnCooldownDone,
-- not 20Hz polling. SPELL_UPDATE_USABLE (line 372) handles resource changes.
--
-- Settings are stored in cfg.spellUsability (managed by SpellUsabilityOptions).
-- Integration: CDMEnhance calls HookFrame() during enhancement.
--              UpdateGlow() is called from the CooldownState relay wrapper.
-- ═══════════════════════════════════════════════════════════════════════════

local addonName, ns = ...

ns.CDMSpellUsability = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- DEFAULT COLORS (match CDM constants and ArcAurasCooldown defaults)
-- ═══════════════════════════════════════════════════════════════════════════

local NOT_ENOUGH_MANA  = { r = 0.5, g = 0.5, b = 1.0, a = 1.0 }
local NOT_USABLE_COLOR = { r = 0.4, g = 0.4, b = 0.4, a = 1.0 }
local ON_CD_COLOR      = { r = 0.4, g = 0.4, b = 0.4, a = 1.0 }

-- ═══════════════════════════════════════════════════════════════════════════
-- DESATURATION HELPER
-- Uses the bypass flag so CDMEnhance's desat hooks don't intercept.
-- Also stores the request so CooldownState can respect it on next pass.
-- ═══════════════════════════════════════════════════════════════════════════

local function ApplyUsabilityDesat(frame, iconTex, desaturate)
    -- Store request for CooldownState + CDMEnhance hooks to read
    frame._arcUsabilityDesatRequest = desaturate and true or nil

    -- ONLY touch desaturation when explicitly configured (true/false)
    -- When nil (not configured), leave desat alone so CDM's native
    -- cooldown desaturation isn't wiped by our hook.
    if desaturate == nil then return end

    if not iconTex then return end
    frame._arcBypassDesatHook = true
    if iconTex.SetDesaturation then
        iconTex:SetDesaturation(desaturate and 1 or 0)
    elseif iconTex.SetDesaturated then
        iconTex:SetDesaturated(desaturate and true or false)
    end
    frame._arcBypassDesatHook = false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- OPTIONS PANEL STATE
-- ═══════════════════════════════════════════════════════════════════════════

local function IsOptionsPanelOpen()
    return ns.CDMEnhance and ns.CDMEnhance.IsOptionsPanelOpen
        and ns.CDMEnhance.IsOptionsPanelOpen() or false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

local function GetSpellIDFromFrame(frame)
    if frame.cooldownInfo then
        return frame.cooldownInfo.overrideSpellID or frame.cooldownInfo.spellID
    end
    if frame.GetSpellID then
        local ok, id = pcall(frame.GetSpellID, frame)
        if ok then return id end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- USABILITY TINTING (RefreshIconColor hook)
--
-- Runs AFTER CDM sets its native colors. Overrides vertex color based
-- on spell usability state and user's custom tint settings.
-- Skip when out of range (range indicator handles that independently).
-- We do NOT check cooldown state here — cooldownDesaturated is SECRET.
-- CDM's own desaturation makes colors subtle during cooldown anyway.
-- ═══════════════════════════════════════════════════════════════════════════

-- Bypass keepBright hook when SpellUsability writes vertex color.
-- SpellUsability is the authority for ready-state tinting (OOM, not-usable,
-- normal) so keepBright must not override its writes.
local function SetVertexColorBypassed(frame, iconTex, r, g, b, a)
    frame._arcBypassVertexHook = true
    iconTex:SetVertexColor(r, g, b, a or 1)
    frame._arcBypassVertexHook = false
end

function ns.CDMSpellUsability.OnRefreshIconColor(frame, cfg, spellID, isUsable, notEnoughMana, allDepleted)
    if frame._arcBypassUsabilityHook then return end

    -- Skip Arc Auras frames (they handle their own usability)
    if frame._arcConfig or frame._arcAuraID then return end
    
    -- COOLDOWN FRAMES ONLY: Aura frames don't have spell usability state
    if frame._arcViewerType == "aura" then return end

    -- Get settings (use pre-computed if provided)
    if not cfg then
        if ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame then
            cfg = ns.CDMEnhance.GetEffectiveIconSettingsForFrame(frame)
        end
    end
    if not cfg then return end

    -- KEEP BRIGHT: When enabled, SpellUsability must not tint or desaturate.
    -- SetVertexColorBypassed skips the keepBright vertex hook (by design),
    -- so we must respect keepBright HERE before applying any usability visuals.
    if cfg.keepBright then
        local iconTex = frame.Icon or frame.icon
        if iconTex and not iconTex.SetVertexColor and iconTex.Icon then
            iconTex = iconTex.Icon
        end
        if iconTex and iconTex.SetVertexColor then
            -- Force white (undo any CDM native tinting)
            SetVertexColorBypassed(frame, iconTex, 1, 1, 1, 1)
            -- Clear usability desat unless user explicitly allows desaturation with keepBright
            if not cfg.keepBrightAllowDesat then
                ApplyUsabilityDesat(frame, iconTex, false)
            end
        end
        return
    end

    local su = cfg.spellUsability

    -- Resolve icon texture early (shared by both disabled-override and enabled paths)
    local iconTex = frame.Icon or frame.icon
    if not iconTex then return end
    -- Bar-style icons: frame.Icon is a Frame container with .Icon child texture
    if not iconTex.SetVertexColor and iconTex.Icon then
        iconTex = iconTex.Icon
    end
    if not iconTex or not iconTex.SetVertexColor then return end

    -- When usability tinting is DISABLED, undo CDM's native tinting
    -- (same pattern as range indicator disabled: hook fires after CDM
    --  sets its usability colors, so we override back to white)
    if not su or not su.enabled then
        -- Don't override if spell is out of range AND range indicator is enabled
        -- (let CDM/range handle the vertex color in that case)
        if frame.spellOutOfRange then
            local ri = cfg.rangeIndicator
            local rangeEnabled = not ri or ri.enabled ~= false
            if rangeEnabled then return end
        end
        -- Reset to full brightness (ITEM_USABLE_COLOR equivalent)
        iconTex:SetVertexColor(1, 1, 1, 1)
        -- Pass nil (not false!) so ApplyUsabilityDesat returns early and
        -- does NOT clear desaturation.  CDM / CooldownState own desat when
        -- usability tinting is disabled.
        ApplyUsabilityDesat(frame, iconTex, nil)
        return
    end

    -- Skip if spell is out of range AND range indicator is enabled (match ArcAuras)
    if frame.spellOutOfRange then
        local ri = cfg.rangeIndicator
        local rangeEnabled = not ri or ri.enabled ~= false
        if rangeEnabled then
            -- Clear our desat request — range indicator owns visuals now
            frame._arcUsabilityDesatRequest = nil
            return
        end
    end

    local spellID = spellID or GetSpellIDFromFrame(frame)
    if not spellID then return end

    -- ── Priority 1: On Cooldown (all charges depleted) ──────────────
    -- Shadow CD converts secret duration into non-secret boolean.
    -- IsShown()=true → all charges depleted / full CD active.
    -- When called from hook, allDepleted is pre-computed (with GCD guard applied).
    if allDepleted == nil then
        local shadowCD = frame._arcCDMShadowCooldown
        allDepleted = shadowCD and shadowCD:IsShown() or false
    end

    -- RECHARGING: charge shadow shown but main shadow hidden (1+ charges, one recharging).
    -- CooldownState owns desat in this state too — bail out same as depleted.
    local isRecharging = false
    if not allDepleted then
        local chargeShadow = frame._arcCDMChargeShadow
        isRecharging = chargeShadow and chargeShadow:IsShown() or false
    end

    if allDepleted and su.useOnCooldownColor then
        -- CooldownState's cooldownTint takes priority (enforced via _arcDesiredVertexColor).
        -- Only set usability's on-CD color when CooldownState isn't enforcing.
        if not frame._arcDesiredVertexColor then
            local c = su.onCooldownColor or ON_CD_COLOR
            SetVertexColorBypassed(frame, iconTex, c.r or 0.4, c.g or 0.4, c.b or 0.4, c.a or 1.0)
        end
        ApplyUsabilityDesat(frame, iconTex, nil)  -- CooldownState owns desat during cooldown
        return
    elseif allDepleted then
        -- Spell is fully depleted but user hasn't enabled custom on-cooldown color.
        -- Bail out: CDM / CooldownState own desat + visuals during cooldown.
        -- Without this, C_Spell.IsSpellUsable (resource check, not CD check)
        -- returns true and the "normal/usable" path below would force desat=0,
        -- wiping CDM's native cooldown desaturation.
        ApplyUsabilityDesat(frame, iconTex, nil)  -- clear request, don't touch desat
        return
    elseif isRecharging then
        -- Charge spell has 1+ charges available but is recharging.
        -- CooldownState owns desat here too — same bail-out as depleted.
        -- Without this, isUsable=true triggers normalDesaturate path every
        -- RefreshIconColor (~3x/s), writing SetDesaturation(0) with bypass
        -- and fighting CDM's charge timer desaturation continuously.
        ApplyUsabilityDesat(frame, iconTex, nil)
        return
    end

    -- ── Priority 2: Resource / Usability checks (non-secret bools) ──
    -- These ONLY apply in READY state (not on cooldown). Follows ABE pattern:
    -- on-CD → CD tint only. Ready → usability tints.
    -- When called from hook, isUsable/notEnoughMana are pre-computed.
    if isUsable == nil then
        isUsable, notEnoughMana = C_Spell.IsSpellUsable(spellID)
    end

    if isUsable then
        -- ── Priority 3: Normal / Usable state ──────────────────────
        if su.useNormalColor then
            local c = su.normalColor or { r = 1, g = 1, b = 1 }
            SetVertexColorBypassed(frame, iconTex, c.r or 1, c.g or 1, c.b or 1, 1)
        end
        ApplyUsabilityDesat(frame, iconTex, su.normalDesaturate)
        return
    elseif notEnoughMana then
        local c = su.notEnoughResourceColor or NOT_ENOUGH_MANA
        SetVertexColorBypassed(frame, iconTex, c.r or 0.5, c.g or 0.5, c.b or 1.0, c.a or 1.0)
        ApplyUsabilityDesat(frame, iconTex, su.notEnoughResourceDesaturate)
        -- NOTE: Alpha is handled by CooldownState.ApplyReadyState which merges
        -- usability alpha into readyAlpha (single-writer pattern, no fighting).
    else
        local c = su.notUsableColor or NOT_USABLE_COLOR
        SetVertexColorBypassed(frame, iconTex, c.r or 0.4, c.g or 0.4, c.b or 0.4, c.a or 1.0)
        ApplyUsabilityDesat(frame, iconTex, su.notUsableDesaturate)
        -- NOTE: Alpha is handled by CooldownState.ApplyReadyState (single-writer).
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HOOK INSTALLER
-- Called from CDMEnhance during frame enhancement.
-- Installs RefreshIconColor hook for usability tinting.
-- ═══════════════════════════════════════════════════════════════════════════

function ns.CDMSpellUsability.HookFrame(frame)
    if not frame then return end
    if frame._arcUsabilityTintHooked then return end
    if not frame.RefreshIconColor then return end
    
    -- COOLDOWN FRAMES ONLY: Aura frames don't have spell usability state
    if frame._arcViewerType == "aura" then return end

    frame._arcUsabilityTintHooked = true

    -- ── Per-button RefreshIconColor hook ──────────────────────────────
    -- Blizzard's CDM calls RefreshIconColor on each button when
    -- SPELL_UPDATE_USABLE fires. We ride that dispatch (like ABE)
    -- instead of registering our own event + iterating all frames.
    --
    -- PERF: Compute shared state ONCE and pass to all three paths.
    -- Before: 11 API calls per fire (3× GetSpellID, 3× IsSpellUsable,
    --         2× GetEffectiveIconSettings, 2× shadowCD:IsShown, 1× GetSpellCooldown)
    -- After:  4 API calls per fire (1× each + early exit guards)
    hooksecurefunc(frame, "RefreshIconColor", function(self)
        -- Early guards (shared across all paths)
        if self._arcBypassUsabilityHook then return end
        if self._arcConfig or self._arcAuraID then return end
        if self._arcViewerType == "aura" then return end

        -- ── Compute shared state once ────────────────────────────────
        local cfg
        if ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame then
            cfg = ns.CDMEnhance.GetEffectiveIconSettingsForFrame(self)
        end
        if not cfg then return end

        local spellID = GetSpellIDFromFrame(self)

        local shadowCD = self._arcCDMShadowCooldown
        local allDepleted = shadowCD and shadowCD:IsShown() or false

        -- GCD guard for shadow (shared by tinting + glow)
        if allDepleted and spellID then
            local cdOK, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
            if cdOK and cdInfo and cdInfo.isOnGCD then
                allDepleted = false
            end
        end

        local isUsable, notEnoughMana
        if spellID then
            isUsable, notEnoughMana = C_Spell.IsSpellUsable(spellID)
        end

        -- 1. Tinting (uses cfg, spellID, isUsable, notEnoughMana, allDepleted)
        ns.CDMSpellUsability.OnRefreshIconColor(self, cfg, spellID, isUsable, notEnoughMana, allDepleted)

        -- 2. Glow (uses cfg, spellID, isUsable, allDepleted)
        ns.CDMSpellUsability.UpdateGlow(self, cfg, spellID, isUsable, allDepleted)

        -- 3. Alpha — ONLY when usability state actually changed.
        --    CooldownState.Apply re-dispatches visuals including usability alpha.
        --    Usability flips are rare (resource gain/spend, form swap).
        if spellID then
            local prev = self._arcPrevUsable
            if prev ~= isUsable then
                if ns.CooldownState and ns.CooldownState.Apply then
                    local fCfg = cfg  -- already fetched above
                    if fCfg then ns.CooldownState.Apply(self, fCfg) end
                end
                self._arcPrevUsable = isUsable
            end
        end
    end)

    -- Shadow cooldown frame is now created and managed by CooldownState.
    -- Create it eagerly here so it exists before the first event fires.
    if ns.CooldownState and ns.CooldownState.EnsureShadow then
        ns.CooldownState.EnsureShadow(frame)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- USABLE GLOW OVERLAY (dedicated per-icon frame)
--
-- Creates a DEDICATED child frame per icon for usable glow.
-- This gives usable glow its own _ButtonGlow (LCG stores one per frame),
-- eliminating all conflicts with ready/proc/preview glow on _arcGlowOverlay.
-- Same technique used by ArcAurasCooldown and EllesmereBarGlows.
-- ═══════════════════════════════════════════════════════════════════════════

-- Usable glow overlay + raw LCG removed — ns.Glows handles everything.
-- ns.Glows uses keyed glows so ButtonGlow conflicts are impossible.

local function StopUsableGlow(frame)
    if ns.Glows then
        ns.Glows.Stop(frame, "ArcUI_UsableGlow")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- GLOW UPDATE (called from CooldownState relay + ApplyIconVisuals)
--
-- Manages usable glow overlay based on spell state:
--   Show glow when: spell has resources (IsSpellUsable)
--                   AND not all charges depleted (shadow CD not shown)
--   Hide glow when: no resources OR all charges consumed
--
-- NOTE: Shadow cooldown is fed by CooldownState BEFORE this runs.
-- The event-driven dispatch order guarantees fresh shadow state.
-- ═══════════════════════════════════════════════════════════════════════════

function ns.CDMSpellUsability.UpdateGlow(frame, cfg, spellID, isUsable, allDepleted)
    if not frame then return end
    -- Skip Arc Auras frames
    if frame._arcConfig or frame._arcAuraID then return end

    if not cfg then
        if ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame then
            cfg = ns.CDMEnhance.GetEffectiveIconSettingsForFrame(frame)
        end
    end
    if not cfg then return end

    local su = cfg.spellUsability

    -- Use pre-computed spellID or look it up
    spellID = spellID or GetSpellIDFromFrame(frame)

    -- Check preview mode
    local cdID = frame.cooldownID
    local isPreview = cdID
        and ns.CDMEnhanceOptions
        and ns.CDMEnhanceOptions.IsUsableGlowPreviewActive
        and ns.CDMEnhanceOptions.IsUsableGlowPreviewActive(cdID)

    local shouldGlow = false

    if isPreview then
        -- Preview always shows glow
        shouldGlow = true
    elseif su and su.usableGlow and spellID then
            -- Use pre-computed allDepleted or compute from shadow
            if allDepleted == nil then
                local shadowCD = frame._arcCDMShadowCooldown
                allDepleted = shadowCD and shadowCD:IsShown() or false

                -- GCD GUARD (only needed when computing fresh)
                if allDepleted then
                    local cdOK, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
                    if cdOK and cdInfo and cdInfo.isOnGCD then
                        allDepleted = false
                    end
                end
            end

            -- Use pre-computed isUsable or query fresh
            if isUsable == nil then
                isUsable = C_Spell.IsSpellUsable(spellID)
            end

            -- Glow when: has resources AND not fully on cooldown
            if isUsable and not allDepleted then
                local combatOnly = su.usableGlowCombatOnly
                shouldGlow = not combatOnly or InCombatLockdown()
            end
    end

    if shouldGlow then
        local glowSu = su or {}
        local originalType = glowSu.usableGlowType or "button"
        local glowType = originalType
        if glowType == "blizzard" then glowType = "proc" end  -- migrate old name
        if glowType == "glow" then glowType = "proc" end      -- migrate alt name
        if glowType == "default" then glowType = "proc" end   -- "default" routes through LCG proc

        -- Skip if glow is already active with the same type (prevents animation restart)
        if frame._arcCDMUsableGlowActive and frame._arcCDMUsableGlowType == glowType then
            return
        end

        -- Color: nil for "default" with no user color = LCG native golden texture
        local gc = glowSu.usableGlowColor
        local color = nil
        if gc then
            color = {gc.r or 1, gc.g or 0.85, gc.b or 0.1, gc.a or 1}
        elseif originalType ~= "default" then
            color = {1, 0.85, 0.1, 1}
        end

        -- Apply padding offset (matches CDMEnhance behavior)
        local padding = cfg.padding or 0
        local glowOffset = -padding

        if ns.Glows then
            ns.Glows.Start(frame, "ArcUI_UsableGlow", glowType, {
                color = color,
                lines = glowSu.usableGlowLines or 8,
                frequency = glowSu.usableGlowSpeed or 0.25,
                thickness = glowSu.usableGlowThickness or 2,
                particles = glowSu.usableGlowParticles or 4,
                scale = glowSu.usableGlowScale or 1,
                xOffset = glowOffset + (glowSu.usableGlowXOffset or 0),
                yOffset = glowOffset + (glowSu.usableGlowYOffset or 0),
            })
        end
        frame._arcCDMUsableGlowActive = true
        frame._arcCDMUsableGlowType = glowType
    elseif frame._arcCDMUsableGlowActive then
        StopUsableGlow(frame)
        frame._arcCDMUsableGlowActive = false
        frame._arcCDMUsableGlowType = nil
        frame._arcCDMUsableGlowSig = nil
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CLEANUP HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

-- Force-stop all usable glows (for settings refresh)
function ns.CDMSpellUsability.StopAllGlows()
    if not ns.CDMEnhance or not ns.CDMEnhance.GetEnhancedFrames then return end
    local enhanced = ns.CDMEnhance.GetEnhancedFrames()
    if not enhanced then return end
    for _, entry in pairs(enhanced) do
        local frame = entry.frame
        if frame and frame._arcCDMUsableGlowActive then
            StopUsableGlow(frame)
            frame._arcCDMUsableGlowActive = false
            frame._arcCDMUsableGlowType = nil
            frame._arcCDMUsableGlowSig = nil
        end
    end
end

-- Refresh all CDM frame usability visuals
-- IMPORTANT: Never call Blizzard's RefreshIconColor from here — it does a
-- boolean test on IsSpellUsable which is SECRET and taint persists even
-- after InCombatLockdown() returns false. Call our hook directly.
function ns.CDMSpellUsability.RefreshAll()
    if not ns.CDMEnhance or not ns.CDMEnhance.GetEnhancedFrames then return end
    local enhanced = ns.CDMEnhance.GetEnhancedFrames()
    if not enhanced then return end
    for cdID, entry in pairs(enhanced) do
        local frame = entry.frame
        if frame then
            ns.CDMSpellUsability.OnRefreshIconColor(frame)
            ns.CDMSpellUsability.UpdateGlow(frame)
            -- Re-run CooldownState so usability alpha gets applied
            if ns.CooldownState and ns.CooldownState.Apply then
                local cfg = ns.CDMEnhance.GetEffectiveIconSettingsForFrame
                    and ns.CDMEnhance.GetEffectiveIconSettingsForFrame(frame)
                if cfg then ns.CooldownState.Apply(frame, cfg) end
            end
        end
    end
end

-- Refresh a single CDM frame by cooldownID
function ns.CDMSpellUsability.RefreshFrame(cdID)
    if not ns.CDMEnhance or not ns.CDMEnhance.GetEnhancedFrames then return end
    local enhanced = ns.CDMEnhance.GetEnhancedFrames()
    if not enhanced or not enhanced[cdID] then return end
    local frame = enhanced[cdID].frame
    if frame then
        -- Force glow restart
        if frame._arcCDMUsableGlowActive then
            StopUsableGlow(frame)
            frame._arcCDMUsableGlowActive = false
            frame._arcCDMUsableGlowType = nil
            frame._arcCDMUsableGlowSig = nil
        end
        -- Re-evaluate
        ns.CDMSpellUsability.UpdateGlow(frame)
        ns.CDMSpellUsability.OnRefreshIconColor(frame)
        -- Re-run CooldownState so usability alpha gets applied
        if ns.CooldownState and ns.CooldownState.Apply then
            local cfg = ns.CDMEnhance and ns.CDMEnhance.GetEffectiveIconSettingsForFrame
                and ns.CDMEnhance.GetEffectiveIconSettingsForFrame(frame)
            if cfg then ns.CooldownState.Apply(frame, cfg) end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- OPTIONS PANEL STATE — CALLBACK (zero polling)
-- ═══════════════════════════════════════════════════════════════════════════

if ns.CDMShared and ns.CDMShared.RegisterPanelCallback then
    ns.CDMShared.RegisterPanelCallback("CDMSpellUsability", {
        onOpen = function() ns.CDMSpellUsability.RefreshAll() end,
        onClose = function() ns.CDMSpellUsability.RefreshAll() end,
    })
end

-- SPELL_UPDATE_USABLE: No longer needs its own event handler.
-- Blizzard's CDM calls RefreshIconColor on each affected button when this
-- event fires. Our per-button hooksecurefunc (installed in HookFrame) rides
-- that dispatch and handles tinting, glow, and alpha-on-flip per-button.
-- This eliminates the O(N) RefreshAll() that was the #1 source of stutter
-- on multi-spell-change abilities like DH Metamorphosis.