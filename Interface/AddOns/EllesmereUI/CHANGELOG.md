# EllesmereUI

## [v5.5.6](https://github.com/EllesmereGaming/EllesmereUI/tree/v5.5.6) (2026-03-25)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v5.5.5...v5.5.6) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v5.5.6  
- Merge pull request #213 from Lyrex/actionbars/press-and-hold-casting  
    fix(actionbars): stabilize visibility, dispatch, and Main Bar paging  
- 🐛 fix(actionbars): fix extra bar visibility toggle and queue icon mouse  
    Two bugs with a shared root cause: `ApplyManagedNonSecurePresentation`  
    managed the Blizzard frame (child) but not the holder frame (parent)  
    for extra bars like MicroBar, BagBar, and QueueStatus.  
    **MicroBar/BagBar not showing after Never → Always toggle:**  
    `SetupExtraBars` hides both the Blizzard frame and its holder when  
    `alwaysHidden=true`. When the user later changes to "Always",  
    `ApplyManagedNonSecurePresentation` called `frame:Show()` on the  
    Blizzard frame, but the holder stayed hidden. Since the Blizzard  
    frame is a child of the holder, it remained invisible until `/reload`.  
    Fix: sync holder visibility in `ApplyManagedNonSecurePresentation`,  
    showing it BEFORE the child so Blizzard's `Layout` → `GetPosition`  
    → `GetCenter()` chain has valid parent coordinates. Additionally,  
    guard the patched `MicroMenuContainer:Layout()` against nil  
    `GetCenter()` during the show transition, since the layout system  
    may not resolve screen coordinates within the same Lua call that  
    triggers `OnShow`.  
    **QueueStatusButton (eye icon) not clickable/hoverable:**  
    `ApplyManagedMouse` unconditionally called  
    `SafeEnableMouse(frame, false)` for `blizzOwnedVisibility` frames,  
    overriding the initial `SafeEnableMouse(blizzFrame, true)` from  
    holder setup on every visibility refresh.  
    Fix: `return` early for `blizzOwnedVisibility` frames instead of  
    disabling mouse. These frames manage their own mouse state; the  
    independent `ApplyClickThroughForBar` already handles QueueStatus  
    correctly.  
- 🐛 fix(actionbars): address 7 findings from gap analysis  
    Correctness fixes, ordered by impact:  
    1. Merge duplicate `PLAYER_REGEN_ENABLED` handlers into a single  
       registration. `EUILite._RegisterEvent` uses a single-slot  
       `_handlers[eventname]` table, so the second `RegisterEvent` call  
       silently replaced the first — `ApplyAll()` and `ResetDragState()`  
       never fired on combat exit.  
    2. Clear stale range tint when a slot loses its action (e.g. talent  
       swap). The `HasAction(slot)` guard skipped the tint-check block  
       entirely for empty slots, leaving red out-of-range coloring from  
       the previous spell.  
    3. Cache the deferred frame in `ApplyKeyDownCVar` so repeated  
       `CVAR_UPDATE` events during combat reuse a single listener instead  
       of accumulating orphaned `CreateFrame("Frame")` instances.  
    4. Replace `if not s then break end` with skip patterns in four  
       `ALL_BARS` loops (`RefreshMouseover`, `ApplyCombatVisibility`,  
       `RefreshRuntimeVisibility`, `SetDragVisible`). The `break` exited  
       the entire loop when any extra bar had nil settings, preventing  
       all subsequent bars from being processed.  
    5. Early-return from `ResetDragState` during combat instead of wiping  
       the strata cache. The old code called `wipe()` even when  
       `InCombatLockdown()` prevented `SetFrameStrata`, permanently  
       losing the original strata values. The merged REGEN handler from  
       fix 1 retries on combat exit.  
    6. Wrap `EAB.AnchorVehicleButton()` in `pcall` inside the `SetPoint`  
       hook so an error mid-call doesn't leave `hookGuard = true` forever,  
       which would silently disable all future vehicle button re-anchoring.  
    7. Rename `isDisabled` to `disabled` on the Stance Bar "Number of  
       Icons" slider (`EUI_ActionBars_Options.lua`). The widget system  
       checks `cfg.disabled`; the misspelled key left the control  
       interactive when it should have been grayed out.  
- fix(actionbars): resync Main Bar page changes in combat  
    Why this change was needed:  
    Main Bar page swaps were only updating EUI's custom parent frame  
    `actionpage`. Blizzard normally follows that with a button refresh,  
    but EUI's custom parent bypassed that step. During dynamic flight and  
    other bonus-bar transitions, `ActionButton1-12` could keep stale page  
    content until a later out-of-combat refresh.  
    What changed:  
    Added a `MainBarPageSync` helper that installs secure child-update  
    handlers on the reused Main Bar buttons. The Main Bar's `_onstate-page`  
    driver now broadcasts page changes to its children so their normal  
    `OnAttributeChanged -> UpdateAction()` path reruns in combat, while a  
    small Lua-side queue reapplies EUI's empty-slot bookkeeping when combat  
    allows it.  
    Problem solved:  
    Dragonriding and other Main Bar page transitions now switch back to the  
    correct actions immediately after the secure page changes instead of  
    keeping the old page until combat ends.  
- 🐛 fix(actionbars): compute flyout action slot for native dispatch  
    The flyout `SEC_CLICK_HOOK` WrapScript read the button's `action`  
    attribute to detect flyout-type actions via `GetActionInfo`. After the  
    native dispatch refactor, the explicit `action` attribute is  
    intentionally cleared on bars 1-8 (action is derived from ID +  
    `actionpage` via `CalculateAction` path 1). This caused  
    `GetActionInfo(nil)` errors on every mouse click.  
    Fix: compute the action slot inline, mirroring `CalculateAction`:  
    - ID > 0: `action = ID + (actionpage - 1) * 12` (native dispatch)  
    - ID == 0: `action = GetEffectiveAttribute("action")` (legacy fallback)  
    Both `GetActionBarPage` and `GetActionInfo` are available in the  
    restricted environment. The `else` branch uses `or 0` instead of  
    `or 1` to avoid false flyout detection on slot 1 when no action  
    attribute is set.  
- ♻️ refactor(actionbars): switch to native keyboard dispatch  
    Replace the hidden bind-button proxy system with Blizzard's native  
    keyboard dispatch for action bars 1-8. The bind-button approach called  
    `SecureActionButton_OnClick` without the `isKeyPress` and  
    `isSecureAction` parameters that Blizzard's native path provides,  
    causing `UseAction(action, unit, button, nil)` instead of  
    `UseAction(action, unit, button, true)`.  
    With `isKeyPress=nil`:  
    - Press-and-hold casting (CVar `ActionButtonUseKeyHeldSpell`) could not  
      repeat-fire normal spells while the key was held  
    - Empowered spells (e.g., Evoker abilities) did not charge through  
      stages — the C-side treated keyboard input as a mouse click  
    The fix lets keyboard input flow through Blizzard's native handlers:  
    - MainBar: `ActionButtonDown/Up` → `GetActionButtonForID` →  
      `_G["ActionButton"..id]`  
    - Bars 2-8: `MultiActionButtonDown/Up` →  
      `_G[barName].actionButtons[id]`  
    Both call `TryUseActionButton` which passes `isKeyPress=true`.  
    Key changes:  
    - Buttons keep their native IDs (no more `SetID(0)`) so  
      `CalculateAction` uses path 1 (page-based: `ID + (page-1)*12`)  
      instead of path 2 (explicit `action` attribute, taint-prone)  
    - MainBar: `_onstate-page` handler sets `actionpage` from the  
      restricted env, replacing the `_childupdate-offset` mechanism  
    - Bars 2-8: fixed `actionpage` set from the restricted env, matching  
      Blizzard's `MultiActionBars.xml` values  
    - `btn.bar = nil` moved outside the `skipProtected` guard so  
      combat-reload also breaks the `UpdateShownButtons` loop  
    - `RegisterForClicks` set to Blizzard's default for native-dispatch  
      buttons (`AnyUp`, `LeftButtonDown`, `RightButtonDown`)  
    - Bars 2-8 keep `blizzBar.actionButtons` intact (needed for  
      `MultiActionButtonDown` lookup); `btn.bar = nil` prevents  
      `UpdateShownButtons` from the button side instead  
    - `ActionBarParent` hidden at file-load time (not via  
      `RegisterAttributeDriver`) to avoid tainting protected state  
    - `OverrideActionBar` visibility fully owned by Blizzard's  
      `ValidateActionBarTransition()` — removed EUI's attribute drivers  
    - Removed: `GetOrCreateBindButton`, `ApplyBindButtonMode`,  
      `_bindController`, `IsKeyDownEnabled`, and all bind-button  
      infrastructure for action bars  
    - `UpdateKeybinds` simplified to only handle stance/pet bars  
    - Vehicle/housing bind clearing simplified to stance/pet only  
    No profile or DB schema changes. Existing profiles remain compatible.  
- fix(actionbars): stabilize custom data bar combat visibility  
    Why this change was needed:  
    The custom XP and reputation bars were still mishandling combat visibility after the hover and visibility refactors. Their non-secure runtime path could sample combat state on the wrong transition edge, miss legacy visibility-mode normalization, and leave the shared hover state out of sync after a forced alpha refresh.  
    What changed:  
    Managed non-secure bars now cache combat state from the combat enter and leave events that trigger their refreshes, normalize visibility modes through EAB.VisibilityCompat before evaluating them, and keep the shared hover fade direction synchronized with any alpha changes applied by the visibility pass. Mouse handling for these bars is also refreshed during combat transitions.  
    Problem solved:  
    The custom XP and reputation bars now honor in-combat and out-of-combat visibility reliably, including on older profiles, and their mouseover fade-in still works after combat-driven visibility changes.  
- fix(actionbars): restore data bar metadata lookup  
    Why this change was needed:  
    The hover-state refactor started using BAR\_LOOKUP as the shared metadata source for managed non-secure bars, but the table still only contained the secure action bars. XP and reputation updates could therefore hit nil metadata during visibility refreshes, which broke mouseover behavior and caused errors when no faction was being watched or when the watched faction changed.  
    What changed:  
    Extra bar metadata is now registered in BAR\_LOOKUP so the managed data-bar visibility path can resolve XPBar and RepBar consistently. The orientation capability check was tightened to look for button-count metadata so it still only applies to real action bars.  
    Problem solved:  
    XP and reputation visibility updates can now re-enter the managed presentation path without missing metadata. That restores mouseover behavior for both bars and fixes the watched-faction edge cases that were getting stuck or erroring.  
- refactor(actionbars): rename runtime visibility refresh  
    Why this change was needed:  
    The old ApplyAlwaysHidden name no longer matched what the method actually does. It now refreshes secure visibility drivers, managed non-secure bars, quick-keybind surfacing, and mouse enablement in addition to the explicit never-hidden case.  
    What changed:  
    The method has been renamed to RefreshRuntimeVisibility, and every runtime and options call site now uses that name. The surrounding section header was updated as well so the visibility code reads in terms of runtime refreshes instead of the narrower always-hidden label.  
    Problem solved:  
    The visibility code now describes its real behavior at the definition and every call site. That makes later maintenance less error-prone, because readers no longer have to mentally translate a misleading method name before understanding why it is being called.  
- refactor(actionbars): share hover controller logic  
    Why this change was needed:  
    Action bars, data bars, and managed extra bars all implemented the same hover fade state machine separately. Their enter and leave handlers had already started to drift, which made mouseover behavior harder to reason about and increased the chance of subtle startup or fade timing regressions.  
    What changed:  
    A shared hover controller now owns state lookup, fade-in, guarded fade-out, and handler construction. The action bar, data bar, and extra bar attach paths now pass only their special-case policies, such as visible-button hit testing, flyout suppression, or Blizzard hover-root checks.  
    Problem solved:  
    Mouseover behavior for the different bar types now runs through one controller instead of three nearly identical implementations. That reduces future drift while preserving the bar-specific edge cases that still need different rules.  
- refactor(actionbars): extract visibility compatibility helpers  
    Why this change was needed:  
    The action bar visibility mode had two parallel compatibility paths.  
    Runtime migration, options dropdowns, and multi-apply sync each kept their  
    own copies of the legacy boolean to  mapping, which made the  
    state model harder to reason about and easier to drift over time.  
    What changed:  
    A dedicated  API now owns the visibility-mode  
    normalization, application, and copy logic. The runtime uses it when  
    importing legacy visibility values, and the options UI now delegates its  
    get/set and sync-copy behavior through that same adapter instead of  
    reimplementing the field updates locally.  
    Problem solved:  
    Existing profiles still map cleanly onto the newer visibility dropdown, but  
    there is now one compatibility adapter instead of several partially duplicated  
    ones. That keeps runtime and options behavior aligned as future visibility  
    changes land.  
- refactor(actionbars): split data bar setup into phases  
    Why this change was needed:  
    The XP / reputation setup flow was doing frame creation, hover wiring,  
    position restore, unlock registration, and runtime visibility sync in  
    one function body. The behavior depended on call ordering, but that  
    ordering was implicit rather than named.  
    What changed:  
    Broke the data-bar setup path into explicit phased helpers under  
    `EAB_VTABLE.ExtraBars` for frame creation, hover initialization,  
    position restore, unlock registration, and runtime-state sync.  
    `SetupDataBars()` now acts as an ordered orchestrator for those phases.  
    Problem solved:  
    The data-bar startup path now reads in the same order the runtime depends  
    on, which makes later visibility and hover changes easier to reason  
    about without reintroducing startup-order bugs.  
- refactor(actionbars): centralize managed extra bar presentation  
    Why this change was needed:  
    Managed non-secure extra bars were still applying visibility, alpha, and  
    mouse handling from multiple entry points. That made the startup and  
    update behavior harder to reason about and left XP / reputation updates  
    with their own ad-hoc hide paths.  
    What changed:  
    Added one shared presentation helper for managed non-secure bars and  
    routed both the runtime visibility pass and the XP / reputation update  
    paths through it. Data bars now use the same presentation flow when they  
    show, hide, or early-return from update callbacks.  
    Problem solved:  
    Managed extra bars now have one consistent source of truth for their  
    visible presentation state, which makes later setup and hover refactors  
    safer and easier to verify.  
- fix(actionbars): restore initial data bar mouseover behavior  
    Why this change was needed:  
    XP and reputation bars could appear with broken mouseover behavior after  
    updating into the new managed non-secure visibility path. On startup,  
    the bars could become visible before their mouse state was refreshed,  
    which made `mouseover` feel broken until the setting was toggled away  
    and back.  
    What changed:  
    Managed non-secure visibility now applies mouse handling as part of the  
    same visibility pass that shows or hides the frame. The old follow-up  
    mouse update in `ApplyAlwaysHidden()` was removed so the startup path and  
    later refresh paths share one consistent source of truth.  
    Problem solved:  
    XP and reputation bars now enter `mouseover` mode correctly on first  
    load, without needing a manual visibility toggle to wake up the hover  
    state.  
- fix(actionbars): preserve cooldown text styling  
    Why this change was needed:  
    Cooldown countdown text could reset after reloads, talent changes, or same-spec loadout swaps because Blizzard rebuilds cooldown visuals after those transitions.  
    What changed:  
    Cooldown font application now uses shared `EAB_VTABLE.CooldownFonts` helpers, re-applies settings to both normal and charge cooldown frames, retries once when the countdown font string is created lazily, and hooks `SetCooldown()` so styling is restored whenever Blizzard refreshes cooldown state.  
    Problem solved:  
    Configured cooldown text size, color, and offsets now persist across the reset paths that were previously falling back to Blizzard defaults.  
- fix(actionbars): keep Blizzard borders suppressed  
    Why this change was needed:  
    Action bar buttons could lose the configured `none` border state after stealth, reloads, combat transitions, or other Blizzard button-art refreshes. The default thin border would return even when EAB had been configured to hide it.  
    What changed:  
    The square-button path now hides the Blizzard-owned `Border` region alongside the existing normal texture cleanup, reuses one deferred-hide helper for art that Blizzard re-shows on the next frame, and suppresses `Border:SetAtlas()` and `Border:Show()` instead of trying to restyle Blizzard border art.  
    Problem solved:  
    EAB-owned border visuals remain the only visible border source, so bars configured with no border keep that state across the refresh paths that previously resurrected the Blizzard border.  
- fix(actionbars): honor extra bar visibility rules  
    Why this change was needed:  
    Reputation and experience bars were not reliably honoring `solo`, `mouseover`, and the related non-secure visibility modifiers. Later XP or faction updates could also re-show a bar after the runtime visibility pass had hidden it.  
    What changed:  
    The options UI now uses one shared visibility helper so `barVisibility` stays in sync with the legacy boolean fields that existing profiles still store. Runtime visibility for managed non-secure bars now flows through shared `EAB_VTABLE.ExtraBars` helpers, data-bar updates are gated through that same logic, and data bars use motion-only mouse input when `mouseover` is combined with `clickThrough`.  
    Problem solved:  
    Rep and XP bars now respond consistently to visibility modifiers, including mouseover and state-based rules such as mounted-only, without later update events undoing the chosen setting.  
