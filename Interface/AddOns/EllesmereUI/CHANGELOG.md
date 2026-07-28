# EllesmereUI

## [v8.6.5](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.6.5) (2026-07-28)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.6.4...v8.6.5) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.6.5  
- Merge pull request #967 from dfrisone/actionbar-microbar-combat-taint-fix  
    Actionbar microbar combat taint fix  
- Merge pull request #1005 from MorgDT/feat/cdm-cooldown-saturation  
    CDM: add Cooldown Saturation (Keep Colored on CD)  
- Merge pull request #1050 from nulltyto/fix/actionbar-visibility-unlock  
    fix(actionbars): show unlock movers for Never bars surfaced by the toggle keybind  
- Merge pull request #1049 from nulltyto/fix/professions-tabs  
    Fix Crafting Orders order-type tab highlight stuck on Public  
- Merge pull request #1048 from nulltyto/fix/tip-of-the-spear  
    Fix Tip of the Spear overcounting Takedown with Twin Fangs  
- Merge pull request #1047 from dfrisone/CD-Text-AB-Bug  
    Fix double cooldown text on charge spells  
- Merge pull request #1046 from dfrisone/ab-charge-desat-flicker  
    fix(actionbars): charge spells flicker out of cooldown desaturation on every press  
- Merge pull request #1045 from dfrisone/settle-reapply-loop  
    fix(specov): post-combat full-refresh storm from stowaway Dragon Riding capture  
- Merge pull request #1043 from dfrisone/hover-cast-bug  
    fix(clickcast): dispatch the hovercast state driver  
- Merge pull request #1042 from dfrisone/cdm-collided-buff-placeholder  
    fix(cdm): give collided buff slots their own placeholder identity  
- Merge pull request #1040 from Velteia/patch-1  
    Increase Crosshair max size in EUI\_QoL\_Options.lua  
- Merge pull request #1038 from DlargeX/main  
    add missing and new German Locals  
- Merge pull request #1035 from Crazyyoungs/patch-1  
    Update translation for Encounter Bar in Korean locale  
- Merge pull request #1033 from labrie75/labrie75-patch-6  
    Updates the Korean (koKR) locale for 8.6.4.  
- Merge pull request #1031 from LoChinAn/locale-zhtw-databars-location-blizzskin-loot  
    locale(zhTW): DataBars location/coords blocks, loot & item upgrade reskins  
- Merge branch 'main' into feat/cdm-cooldown-saturation  
- Merge pull request #1024 from nulltyto/feat/mana-on-character-sheet  
    feat(charsheet): optional Mana row in the Attributes stats  
- Merge pull request #1020 from dfrisone/Vendor-Grays-Bug  
    fix(qol): retry Auto Sell Junk so partial sweeps finish  
- Merge pull request #1017 from RedAces/show-empty-castbar-if-not-casting  
    Show empty castbar if not casting  
- Merge pull request #1016 from RedAces/cdm-bar-visibility  
    Add a visibility toggle for the CDM Buff Bars: show only in combat  
- fix(actionbars): show unlock movers for Never bars surfaced by the toggle keybind  
    The unlock element's isHidden read only the saved alwaysHidden flag, which is  
    true for every bar set to Visibility = Never. CreateMover skips any element  
    whose isHidden returns true, so such a bar got no mover and could not be  
    positioned -- even while the "Toggle Action Bar Visibility" keybind had it on  
    screen, since that override is runtime-only and never writes barVisibility.  
    Consult EAB.\_visOverride first, matching the precedence RefreshRuntimeVisibility  
    already uses: a Never bar surfaced by the keybind now gets a mover, and an  
    Always bar toggled off correctly loses one. Bars left hidden are unchanged, so  
    the Bar9/Bar10 Never defaults still stay out of unlock mode.  
- Fix Crafting Orders order-type tab highlight stuck on Public  
    The crafter-side order-type tabs (Public/Guild/Patron/Personal) carry no  
    tabID and BrowseFrame is not a TabSystem, so nothing tied to an order-type  
    switch repainted them -- the engine's global PanelTemplates / TabSystem  
    hooks only reached them incidentally, when something else in the UI fired  
    them.  
    The per-tab OnClick hook that was meant to drive the repaint does not  
    survive either: Blizzard's InitOrderTypeTabs() re-SetScript's each tab's  
    OnClick, and it re-runs on PLAYER\_ENTERING\_WORLD / PLAYER\_GUILD\_UPDATE  
    (both in its always-listen set), so the hook is wiped for good. The  
    selection underline then froze on whichever type was live at skin time,  
    which is Public from OnLoad.  
    Hook SetCraftingOrderType instead, the authoritative setter: a method hook  
    survives SetScript and also catches programmatic switches such as the  
    leave-guild fallback to Public. The now-superseded OnClick hook is removed  
    rather than left as dead machinery.  
- Fix Tip of the Spear overcounting Takedown with Twin Fangs  
    Twin Fangs grants 3 stacks on Takedown and the ability's own impact  
    (1253859) spends one, so the cast nets 2. The tracker granted 2 on the  
    cast and then spent another on the impact, landing on 1.  
    From a partially filled bar the 3-stack cap hid the missing stack, which  
    is why this only reproduced when opening from an empty bar.  
    Resolve both halves on the cast and ignore the paired impact event when  
    Twin Fangs is known. Waiting for the impact is not reliable: at melee  
    range the two events land in the same frame and the impact can be  
    handled first, where the empty-bar guard drops it and the tracker then  
    sticks a stack high for the buff's full duration.  
- Fix double cooldown text on charge spells  
    At 0 charges the main cooldown mirrors the recharge and shows its own  
    countdown while the charge cooldown's un-hidden recharge number renders  
    on top of it, in Blizzard's default font since the 8.6.x lazily created  
    charge cooldown never receives the cooldown font application.  
    Route all recharge-number visibility through a shared helper that hides  
    the charge countdown while the main cooldown is showing a real (non-GCD)  
    cooldown, and queue the cooldown font patch when un-hiding an unstyled  
    charge cooldown. Also let the font retry paths trigger on a missing  
    charge-cooldown stamp instead of keying off the main cooldown only.  
- fix(actionbars): stop charge spells flickering out of cooldown desaturation  
    The cooldown walk fetches the action's duration object only on the  
    once-per-cast swipe push (the fd.pushGen gate), but the visuals gate below  
    re-enters RefreshCooldownVisuals on every walk for charge buttons via  
    chargeShown. On the second and later walks of a cast generation the shared  
    function therefore received isActive cooldown info with a nil duration  
    object, classified the cooldown as inactive, and wrote SetDesaturation(0)  
    -- snapping a recharging charge spell back to full color. The next cast  
    bumped the generation, the first walk re-fetched the duration object and  
    re-desaturated, so pressing any button flashed every recharging charge  
    spell grey-color-grey. Non-charge buttons skip the visuals call between  
    generations entirely, which is why only charge spells (Incarnation,  
    Prescience, Immolation Aura and the like) flickered.  
    Fetch the duration object at the call site when the cooldown is active and  
    the swipe-push gate did not already fetch it this walk. One extra fetch  
    per walk, only for buttons passing the visuals gate, and the walk itself  
    is rate-capped.  
- fix(specov): stop stowaway Dragon Riding captures from escalating into full-suite refresh storms  
    The Skyriding HUD registers its own sub-DB (EllesmereUIDragonRidingDB), so  
    its registry folder is EllesmereUIDragonRiding and the BlizzardSkin entry  
    in the capture blacklist never matched it. A width-match engine write to  
    its width key was auto-captured into a user's CDM Icon Scale override  
    entry, with divergent per-spec values.  
    Applying that entry touches a folder with no REFRESH\_FNS mapping, and the  
    unmapped-folder fallback in RunRefreshers escalates every such apply into  
    a full RefreshAllAddons. Under the spec-changed event traffic that follows  
    combat this produced minutes of continuous full-suite refresh: every  
    action bar relaid out at the notify throttle cap, Blizzard's combat script  
    execution limiter tripping, a severe sustained post-combat frame drop.  
    Stack capture in the field went NotifyElementResized <- \_EAB\_Apply <-  
    RefreshAllAddons <- RunRefreshers <- SpecOverrides\_Apply <- the  
    PLAYER\_SPECIALIZATION\_CHANGED handler.  
    Three layers:  
    - Blacklist the EllesmereUIDragonRiding folder for capture and apply.  
    - Migration specov\_strip\_dragonriding\_fkeys\_v1 strips already-banked keys  
      from both override stores, preserving each entry's own settings and  
      dropping only entries left empty.  
    - Map the folder to \_EDR\_Rebuild in REFRESH\_FNS as insurance so no future  
      slip-through can reach the unmapped-folder fallback.  
- fix(unlock): stop the settle re-apply pass from re-arming itself  
    ScheduleSettleReapply guards against re-arming from its own forced pass  
    with \_settleReapplyInProgress, but the flag only covers the synchronous  
    call. The anchor batches and SetPoint move checks the pass spawns are all  
    After(0) deferred and land after the flag clears, so each one re-armed the  
    settle timer.  
    On a layout whose forced re-apply is not pixel-stable this became a  
    self-sustaining engine: every pass moved some chain member by one physical  
    pixel, one physical pixel exceeds the fixed 0.5 UI-unit change epsilon at  
    low UI scale (at 0.64 scale a pixel is 0.83-1.11 UI units at common  
    resolutions), the deferred tail re-armed the timer, and the settle pass ran  
    forever at the debounce rate. Field capture showed 51 forced full anchor  
    re-applies in ten seconds, every action bar relaid out at the notify  
    throttle cap, and Blizzard's combat script execution limiter tripping,  
    presenting as a severe sustained frame-rate drop with visibly jittering  
    bars. The state re-establishes from SavedVariables, so a reload restarts  
    the loop.  
    Suppress re-arms for 0.75s from the start of a forced pass, long enough to  
    swallow the deferred tail. A real disturbance inside the window loses only  
    the belt-and-braces settle pass; the normal notify and batch path has  
    already handled it, and any disturbance after the window re-arms normally.  
- Merge remote-tracking branch 'origin/main' into show-empty-castbar-if-not-casting  
- Merge remote-tracking branch 'origin/main' into cdm-bar-visibility  
- fix(clickcast): default new hovercast macro bindings to both reactions  
    A macro binding created from the picker sat at hoverFriendly = true,  
    hoverEnemy = false. Now that the friend/harm filter is actually applied to  
    macros, that default makes every freshly created mouseover focus or target  
    macro dead on enemies, which is the same report the filter work came from.  
    Macros default to both reactions; spell bindings keep friendly-only, which  
    suits the click-cast healing case they are built for.  
- fix(clickcast): dispatch the hovercast state driver  
    The click-cast header was created with SecureHandlerBaseTemplate, which  
    carries no OnAttributeChanged script. Only SecureHandlerStateTemplate  
    installs SecureHandler\_StateOnAttributeChanged, the handler that dispatches  
    "\_onstate-<id>" snippets. RegisterStateDriver therefore wrote state-eui\_cc  
    on every mouseover change and nothing ever listened, so the hover set/clear  
    snippet never ran.  
    Hovercast still worked on EUI unit frames because their secure OnEnter wrap  
    sets the override binding directly, bypassing the driver. Nameplates are  
    excluded from click-cast registration, so the dead driver was their only  
    path and a hovercast key never bound over one, staying on whatever the  
    player's normal keybind was. A focus macro pressed over a nameplate fell  
    through to its own fallback clause and set focus to the current target,  
    which read as "only works when I already have a target selected".  
    Second defect on the same path: Blizzard's resolveDriver runs  
    newValue = tonumber(newValue) or newValue before setting the state, so a  
    "1; 0" driver delivers newstate as the number 1 and a snippet testing  
    newstate == "1" never matches. Moved to non-numeric "on; off" states, which  
    the coercion leaves alone. This was masked by the template bug and would  
    have broken the handler again as soon as it started running.  
    Also honor the Hovercast Friendly/Enemy toggles for macro bindings. The  
    friend/harm filter was only applied when assembling a spell binding, so  
    both toggles were built and shown for macros but did nothing. A macro body  
    belongs to the user and cannot take injected conditionals, so the filter  
    gates the whole macro with /stopmacro instead. Existing stored bindings sit  
    at the creation defaults (hoverFriendly = true, hoverEnemy = false) and  
    have always run unfiltered, so a profile migration seeds both flags to  
    preserve that rather than silently disabling them on enemies.  
- fix(cdm): give collided buff slots their own placeholder identity  
    Two viewer slots on one bar can resolve to the same realSID. For split-form  
    talents that is correct and the placeholder dedup must collapse them, but it  
    is also what a viewer-level COLLISION looks like: Blizzard hands the Demonic  
    Art slot Diabolic Ritual's id. Unlike the split-identity twins the clean-read  
    cache cannot separate those two either, because both reads return the same id.  
    Keyed on realSID alone the second slot was skipped by the "ph:" dedup and  
    shared the first's pooled frame, which is keyed by spellID as well. The pair  
    therefore rendered two icons while both buffs were active and one while either  
    was missing, so the bar's icon count rose and fell through a fight -- reported  
    as a buff icon disappearing with Visibility When Missing on Desaturated.  
    cooldownID is distinct per viewer slot, which is why the buff enumeration dedup  
    was moved onto it; this is that same identity rule reaching the placeholder  
    path, which had been left behind. The FIRST claimer of a realSID keeps the  
    plain key, so every non-colliding spec (unique sid <=> unique cooldownID) is  
    byte-identical to before; only a later slot carrying a DIFFERENT cooldownID  
    takes an identity of its own instead of vanishing. GetOrCreatePlaceholderFrame  
    gains an optional pooling identity so the two slots stop sharing one frame; the  
    preset caller passes none and is unchanged.  
- more missing German Locals  
- Update deDE.lua  
- Update EUI\_QoL\_Options.lua  
    I like a bigger crosshair and the current 100 max is not doing it for me. I suggested the number 500 because around 300 is the sweetspot for me. Maybe a higher number is optimal for people who want the crosshair over their entire screen?   
    In my personal test, I could not find any disadvantage to increasing the number and I will keep rolling with 300, but I don't want to edit the code after every update 😄  
- add missing and new German Locals  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main' into actionbar-microbar-combat-taint-fix  
- Merge remote-tracking branch 'upstream/main' into actionbar-microbar-combat-taint-fix  
    # Conflicts:  
    #	Locales/\_keys.txt  
- Update koKR.lua  
- Update translation for Encounter Bar in Korean locale  
- Updates the Korean (koKR) locale for 8.6.4.  
    ## What does this PR do?  
    Updates the Korean (koKR) locale for 8.6.4.  
    - Adds new catalog entries for strings that were still English on the koKR client.  
    - Korean terminology cross-checked against official Blizzard koKR data (GlobalStrings / spec, spell, and item names), so in-game terms match the official client localization.  
    - Locale data only -- no engine or module code is touched. Untranslated keys still fall back to English as before.  
    New entries by window:  
    1. Profiles & Presets (52)  
    2. Nameplates (25) + 2 shared tooltips  
    3. Cooldown Manager (22)  
    4. Resource & Cast Bars (3)  
    5. Raid Frames (23)  
    6. Quality-of-Life (12)  
    7. Data Bars (21)  
    8. Blizzard UI Skin (23)  
    9. Damage Meters (8) + term unify  
    10. Quest Tracker (1)  
    11. Action Bars (3) -- One Button Assist  
    12. Unit Frames (2) -- Show Tooltip For  
    - EN note for author: The Chat page label and the Bank sidebar header both feed the same source string "Tabs", so a locale can only give them one value. They happen to both mean "tab" in koKR, so it's fine here -- but renaming the Chat-side source to a distinct string (e.g. "Chat Tabs") would let locales translate the two independently.  
    ## How was it tested?  
    Tested in game on live retail with the koKR client: options panel pages, module tooltips, confirmation popups verified visually. File parses clean (Lua syntax checked), UTF-8 without BOM preserved, and no load errors.  
    ## Screenshots  
    N/A -- text-only locale data (no layout/visual change).  
    ## Checklist  
    - [ ] New settings default **OFF** -- N/A (locale data only, no settings added)  
    - [ ] Zero cost while disabled -- N/A (no events, hooks, frames, or code; translation table only)  
    - [ ] Cheap while enabled -- N/A (same single catalog lookup path as every existing locale)  
    - [ ] No writes onto Blizzard-owned frames -- N/A (no frame code)  
    - [x] Tested in-game, works on live retail; no load errors (data-only table, no API calls; not separately run on 12.1 PTR)  
- locale(zhTW): translate DataBars location/coords blocks and loot reskin strings  
    Also backfills seven strings that predate the sync watermark: the  
    Nameplates border style Basic entry and six unit frame health text  
    dropdown values (Level | Name, Name | Level, absorb short forms,  
    Group Number). Retunes One from a Bags-flavoured wording to the  
    decimal-place reading its only consumer needs.  
- feat(charsheet): add an optional Mana row to the Attributes stats  
    The Attributes section shows the primary stat, Stamina and Health, but never  
    the mana pool those spells are cast from. Add Mana as a fourth row, reading  
    UnitPowerMax with Enum.PowerType.Mana so it matches the Health row's max-value  
    semantics, toggled from a cog on the Attributes swatch in the Stat Display  
    card.  
    The row is opt-in and defaults off, so existing sheets are unchanged, and it  
    stays hidden for classes with no mana pool -- UnitPowerMax reads 0 there, the  
    same check Blizzard's PaperDollFrame uses for alternate mana.  
    Unlike the per-crest filter, the row is built unconditionally and only its  
    visibility is gated. Rows are created once, inside CharacterFrame's first  
    OnShow, and the OnShow hooks registered during that build do not run for the  
    show that triggered it -- a build-time filter would therefore need a /reload  
    before a toggle took effect. RefreshStatsVisibility now also runs at the end  
    of the build so the row is settled before the panel is first drawn.  
    Mana stays in GetFilteredAttributeStats even for classes without a pool,  
    because RefreshAttributeStats pairs existing rows with that list by index  
    when the spec changes and a shorter list would misalign them.  
    UNIT\_MAXPOWER joins the stat refresh events, showManaStat travels with the  
    Character Sheet profile bundle, and the two new strings are translated in the  
    six fully translated locales.  
- Merge remote-tracking branch 'upstream/main' into Vendor-Grays-Bug  
- Back the junk sweep off on a stall and stop arming a pointless timer  
    Two problems with the retry loop.  
    The ticker was created unconditionally after the first synchronous pass, and  
    StopJunkSweep only cancels a ticker that exists -- which it did not yet during  
    that first call. So the common case, a vendor with no grays at all, still armed  
    a timer and paid a second full bag walk 0.4s later before shutting down. Pass  
    now reschedules itself only when there is more to do, so that case costs one  
    scan and never arms a timer.  
    The give-up rule also worked against the premise. The failure being fixed is  
    the server dropping sell requests past its rate limit; retrying at a fixed  
    0.4s and concluding after two unchanged passes means a limiter eating those  
    retries looks identical to "cannot be sold". A large batch could stop after  
    0.8s and report items that were perfectly sellable, with MAX\_PASSES never  
    reached because the stall check fired first. Stalls now back the delay off  
    (0.4 -> 0.8 -> 1.6) and tolerate three, giving the limiter room before the  
    sweep concludes anything.  
    A rising count is no longer treated as a stall either. Slots whose item data  
    had not cached yet resolve into newly visible junk, which is the case this  
    sweep exists for; counting it as a stall bailed out exactly when there was  
    more work to do. Passes with nothing sellable also skip the server call and  
    just wait for item data to cache.  
- fix(qol): retry Auto Sell Junk so partial sweeps finish  
    C\_MerchantFrame.SellAllJunkItems() is fire-and-forget: the server drops  
    sell requests past its rate limit, and bag slots whose item data has not  
    been cached yet at MERCHANT\_SHOW are skipped outright. A single call  
    therefore routinely leaves grays behind.  
    Re-count poor-quality sellable items after each pass and fire again while  
    the number is still falling, stopping on two consecutive no-progress  
    passes (still-refundable purchases can never be sold this way) or after  
    12 passes. Track the vendor via MERCHANT\_SHOW/MERCHANT\_CLOSED rather than  
    MerchantFrame:IsShown(), since the frame may not be up yet when our  
    handler runs.  
- add missing German locals  
- Add an Always Show option to the Player Cast Bar: keep it empty when idle  
    Every path that ends a cast now routes through ns.ShowIdleCastBar, which  
    empties the fill and clears the name, timer, icon, pips, ticks, latency  
    overlay and spark; ns.ActivateCastBar is the mirror image on cast start.  
    Default is off, so existing profiles are unchanged.  
    Also fixes the cast bar background below Fill Opacity 100 leaving the  
    spell icon's slot uncovered, via the new ns.ApplyCastBgAnchor.  
- Add a visibility toggle for the CDM Buff Bars: show only in combat  
- Regenerate locale keys  
    Stale since 8.6, which wrapped the account export/import strings without  
    rerunning the extractor. locale-check only runs on pull\_request so the  
    release push never tripped it, but it fails anything opened against the  
    current tip.  
- CDM: add Cooldown Saturation (Keep Colored on CD)  
    Per-spell option to stop an icon greying out while its spell is on  
    cooldown. Defaults to None.  
    Regular icons re-saturate off an additive SetDesaturated/SetDesaturation  
    hook, same shape as the Desaturate When Not Active block above it and  
    behind the usual session flag. Desaturate When Not Active still wins if  
    both are set.  
    Presets (trinkets, racials, potions, injected spells) never get  
    Blizzard's CD desaturation, so they read the setting via PresetKeepsColor  
    where the Fake-Active engine would grey them instead.  
    Includes deDE/frFR/koKR/ruRU/zhCN/zhTW.  
- Fix combat taint from hiding managed micro menu / bag bar  
    SetManagedBlizzOwnedSuppressed unconditionally called frame:Hide()/  
    frame:Show() on the EditMode-managed MicroMenuContainer and BagsBar.  
    Those route through the protected HideBase/ShowBase, which is blocked in  
    combat. For a user whose micro menu / bag bar is suppressed while its  
    container is protected, every visibility refresh during combat re-issued  
    the protected Hide() -- SPELLS\_CHANGED fires repeatedly mid-rotation  
    (e.g. Ascendance on Elemental Shaman), spamming ADDON\_ACTION\_BLOCKED.  
    Only issue the protected call on a real state transition and never  
    during combat lockdown; the pending state is re-applied by  
    RefreshRuntimeVisibility from ApplyAll on PLAYER\_REGEN\_ENABLED once  
    combat ends.  
- Regenerate locale keys for nameplate aura filter strings  
    Mechanical regeneration of Locales/\_keys.txt to catch up on strings that  
    landed with the nameplate aura filters feature without a regen. No code  
    change. Committed separately so the taint fix that follows stays isolated.  
