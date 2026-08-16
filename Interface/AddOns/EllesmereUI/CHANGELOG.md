# EllesmereUI

## [v8.8.9](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.8.9) (2026-08-16)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.8.8...v8.8.9) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.8.9  
- Merge pull request #1495 from labrie75/koKR-remaining-English-strings  
    koKR: remaining English strings + two catalog fixes  
- Merge pull request #1494 from jixinliu666/agent/fix-combat-item-comparison-tooltip-no-flash  
    Fix:Prevent combat item comparison tooltip flash  
- Merge pull request #1492 from dfrisone/fix/friendly-boss-frames-missing-last-boss  
    Friendly Boss Frames: show in dungeons, not raid only  
- Prevent combat item comparison tooltip flash  
- Update koKR.lua  
- Merge pull request #1491 from Kirihasio2/feature/trade-window-and-rarity-borders  
    [Feature] Reskins, MANY reskins.  
- Update \_keys.txt  
- Merge pull request #1489 from Barbiero/locale/ptbr-updates  
    ptBR: add recently added translation keys  
- Merge pull request #1488 from dfrisone/fix/movealert-buffalert-vehicle-identity-gate  
    Movement Alert: stop a vehicle degrading the Burning Rush alert  
- Merge pull request #1487 from svart2521/interact-icon-on-nameplates  
    Hide Interact Icon from enemies  
- Merge pull request #1485 from dfrisone/fix/questtracker-poi-supertrack-taint  
    Quest Tracker: stop POI suppression tainting the supertracking registry  
- Merge pull request #1484 from lolswirl/main  
    [bugfix] Resolve class color background for NPC reaction on unit frames  
- Update koKR.lua  
- Merge pull request #1483 from uNBEx/minimal\_cdm\_width  
    feat(cdm): minimum bar width  
- Merge pull request #1481 from Odiurd/fix/missing\_ascendance  
    Fix Ascendance buff tracking for Elemental Shamans  
- Merge pull request #1480 from uNBEx/arcane\_missiles\_ticks  
    fix(castbar): accurate arcane missiles cast bar  
- Regenerate locale keys after syncing upstream/main  
- Merge remote-tracking branch 'upstream/main' into fix/friendly-boss-frames-missing-last-boss  
- Merge pull request #1478 from Odiurd/fix/missing\_arcane\_surge  
    Fix Arcane Surge buff tracking  
- Merge pull request #1477 from tyyrenn/main  
    feat(quickdraw): add preset for ping system  
- Merge pull request #1475 from Nialoshaar/ABR-fix-text-frame-strata-  
    fix(ABR): render icon text above borders and glows  
- chore(locales): regenerate \_keys.txt  
    Ran .tools/extract-locale-keys.sh, which the locale-keys CI check  
    verifies. Adds 7 keys (731 -> 738).  
    None originate from this PR. They come from strings already on main:  
      EllesmereUIQoL.lua                      Learn %1$d skill(s) for %2$s  
      EUI\_Quickdraw\_Options.lua               Left-click to set a keybind...  
                                              nested action menu, %1$d entr(y|ies)  
      EllesmereUIBlizzardSkin\_SocketPanel.lua No gems in bags.  
                                              \nPick a gem from the list to socket it.  
    \_keys.txt had simply not been regenerated after those landed, so the  
    check fails on main as well; this PR only surfaced it.  
    The options strings added by this PR are not expected here. They reach  
    the translator as variables (L(win.title) / L(win.desc) in the shared  
    card builder), which the static extractor cannot see by design -- the  
    in-game /euiloc harvester is the source of truth for those.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Merge pull request #1474 from Barbiero/feature/aura-bar-shapes  
    feat(pab): allow custom shapes and zoom for player aura icons like action bars  
- Blizzard skin: HUD reskins, window packs, square rarity borders  
    Ports the local Blizzard-skin work onto 8.8.8. Three-way merged against  
    v8.8.6 so upstream's 8.8.7/8.8.8 changes to these files are preserved --  
    all 335 upstream-added lines are present, no conflicts.  
    HUD reskins (BlizzardSkin.lua tail block)  
      Tooltip progress/status bars, UI widget status-bar COVERS, extra action  
      and zone ability buttons.  
      Widget covers never write into a widget tree -- values are secret in  
      instanced content -- so an EUI-owned StatusBar is anchored over  
      Blizzard's and mirrors it through pcall'd reads, retiring on any secret  
      or failed read.  
      Registration is gated at PLAYER\_LOGIN: with the setting off the frame  
      ends up with no events and no script, so it costs nothing rather than  
      returning early from a live handler. There is no timer -- sweeps run  
      from UPDATE\_UI\_WIDGET / UPDATE\_ALL\_UI\_WIDGETS / nameplate events,  
      coalesced to one per frame, plus a per-bar hook on DisplayBarValue for  
      hasTimer widgets and smooth fills, which move with no event at all.  
      The extra action / zone ability reskin is opt-in (default off).  
    Window packs (WindowPacks.lua tail block)  
      Queue status, ready check, delve tier picker, choice windows, stack  
      split, and a new trade window pack.  
      Trade runs its phases in individual pcalls: the engine isolates each  
      WINDOW, so one forbidden object would otherwise take out every step  
      after it and leave the frame half skinned. The currency row is left  
      stock -- the money frame, its edit boxes and even their bevel textures  
      are all forbidden.  
    Square rarity borders (WindowEngine.lua)  
      WSkin.QualityBorder draws a 1px square edge coloured from the quality  
      Blizzard already worked out, read back off IconBorder rather than  
      re-derived from an itemID. Applied to quest rewards, loot rolls, delve  
      tiles and both merchant views.  
      Repaints hook BOTH routes to SetItemButtonQuality: the global delegates  
      to the button's own method when it has one, so MerchantFrame's direct  
      method call never reaches a global-only hook.  
    Verified against a mock-client harness (78 + 83 + 39 assertions,  
    mutation-tested 30/42/17). NOT verified in game for the 8.8.8 merge --  
    the in-game testing was done against 8.8.6.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Friendly Boss Frames: fix the party attach axis and stale layout anchor  
    The attach axis read unitGrowth off the party proxy, which never carries it:  
    party growth comes from partyHorizontal/partyFlipGrowth, so Horizontal Party  
    Frames put the boss group beside a five-wide bar instead of above it. Read the  
    same source, and re-anchor from \_LayoutPartyFrames so a growth or size change  
    mid-dungeon moves the group with it.  
- Friendly Boss Frames: show in dungeons, not raid only  
    The slot controller was gated on [@raid1,exists], so the five boss buttons  
    stayed hidden in every 5-man even though dungeon encounters expose the same  
    healable friendly bossN tokens. Gate on raid OR party instead, and attach the  
    group beside the party container when the raid headers are the hidden ones.  
- Merge pull request #1472 from JuJuFX-dev/fix/questtracker-shared-pool-header-click  
    Fix(questtracker): shared pool header click  
- Merge pull request #1471 from Cryogenics/fix/ru-cyrillic-bundled-fonts  
    ruRU: honour bundled fonts that carry Cyrillic glyphs  
- Merge pull request #1470 from svart2521/Max-character-of-name-in-raid-and-party-frames-can't-be-different  
    Refactor CapName and ResolveDisplayName functions  
- Merge pull request #1467 from Zac-oihfdwrrtuinvbcp/CDM-Allow-buff-bars-decimal-treshold-under-3s  
    Allow buff bars decimal treshold under 3s  
- Merge pull request #1466 from RedAces/hide-loot-rolls-window  
    add the ability to hide the group "Loot roll window"  
- Merge pull request #1465 from RedAces/style-readycheck-window  
    Style readycheck window  
- Merge pull request #1464 from SamJin98/feat/bags-per-equipment-set-categories  
    feat(Bags): bags per equipment set categories and equipment set names  
- ptBR: add recently added translation keys  
- Merge pull request #1462 from RoakStatic/nameplate-name-reaction-color  
    [Feature Request] Colour the nameplate enemy name text by their reaction colour  
- Merge pull request #1460 from jixinliu666/agent/fix-combat-item-comparison-tooltip  
    Fix combat item comparison tooltips  
- Merge pull request #1459 from LoChinAn/locale-wrap-missing-l-calls  
    fix(locale): wrap display strings that never reached L()  
- Update nameplate icon visibility logic  
    Refactor visibility logic for nameplate icons to hide only for attackable enemies.  
- Movement Alert: cite the Blizzard source the vehicle gate rests on  
    Cross-checked against the 12.1.0.69299 clone. No code change; records the  
    files and mixins so the claims are re-checkable rather than re-derived.  
    Worth calling out: UpdateAllAuras is a NO-OP stub on AuraContainerSharedMixin.  
    It only does anything because ManagedAuraContainerSharedMixin overrides it with  
    MarkDirty(FullAuraRebuild), and that override reaches the addon-callable  
    partition via ManagedAuraContainerInboundMixin. Reading the base mixin alone  
    would suggest the recovery call does nothing.  
- Movement Alert: harden the vehicle gate on the Burning Rush lane  
    Review follow-ups to the identity-gate fix:  
    - Reconcile the occupancy latch whenever the tracker's events are (re-)armed.  
      No EXITED edge reaches an unregistered lane, so a tracker switched off  
      mid-ride came back with the alert suppressed until the next loading screen.  
    - Gate the DISPLAY, not the build. Denying the first eligible pass (login in a  
      vehicle, intro cinematic) postponed container creation, and if the gate then  
      opened in combat AK.RequestContainer queued the build to PLAYER\_REGEN\_ENABLED  
      and the alert was absent for that whole fight. Build unconditionally, park at  
      the end.  
    - Register CINEMATIC\_STOP alongside UNIT\_FACTION for the addon-cancelled skip  
      path, whose faction restore can order ahead of the faction edge. The lane  
      runs no ticker, so a missed restore left it hidden until an incidental  
      cooldown or aura event.  
- Movement Alert: stop a vehicle degrading the Burning Rush lane  
    Boarding a vehicle drops the player's own assistability, and the engine's  
    identity gate then SKIPS includeSpellIDs for helpful auras rather than  
    failing closed. The buffActive lane is a single-button HELPFUL container  
    filtered to Burning Rush, so it degraded to "first buff found" wearing the  
    Burning Rush label. Aura membership is cached per instance and UNIT\_AURA  
    only re-parses what changed, so the bad parse outlived the ride and the  
    alert stayed up until a reload.  
    Suppress the lane while the player is in a vehicle (latched from the  
    vehicle events -- UnitUsingVehicle is still true across the exit  
    transition) or while self-assist reads cleanly false, and force one  
    UpdateAllAuras on the denied->allowed flip to clear the stale membership.  
    Same gate the Raid Frames assist probe and the player aura bars guard.  
- Quest Tracker: stop POI suppression tainting the supertracking registry  
    Hiding a quest POI button ran POIButtonMixin:OnHide from our execution, and  
    that handler calls EventRegistry:UnregisterCallback("Supertracking.OnChanged").  
    The write landed in EventRegistry's shared callback table, so every other  
    subscriber -- SuperTrackablePinMixin, VignetteDataProvider, QuestDataProvider,  
    WorldQuestDataProvider, DungeonEntranceDataProvider -- was dispatched tainted  
    on the next TriggerEvent. The post-hook on the button's Show did the same on  
    every Blizzard button:Show(), which is why it repeated hundreds of times.  
    Suppress with alpha and EnableMouse instead; neither runs a script handler.  
    Blizzard's UpdateButtonAlpha only touches NormalTexture/PushedTexture, so it  
    cannot undo this, which also makes the Show hook unnecessary.  
    The template's AddAnim is the only writer of the button frame's alpha and ends  
    on 1 via setToFinalAlpha, so a deferred re-apply covers it. It is queued  
    unconditionally and deduped on a pending timer rather than gated on current  
    alpha: Pool\_HideAndClearAnchors and POIButtonMixin:Reset() reset neither alpha  
    nor mouse state, so a recycled button comes back already at alpha 0 and an  
    alpha gate would skip the very re-apply its incoming fanfare needs.  
- feat(cdm): minimum bar width  
    - add per-bar Minimum Width/Height, counted in icon slots (0 = Off, 1-20, default off)  
    - Reserves the exact space N real icons would occupy and applies it to the bar frame, so width match, anchor edges, the unlock mover and the bar background all inherit it  
    - Icons center inside the reservation when fewer than N are shown  
    - Applies to the bar's growth axis: width on horizontal bars, height on vertical  
    - Skipped while the growth axis is match-owned, so width matching a CDM bar stays exact  
    - Login pre-size path reserves too, so anchored elements do not settle after data loads  
- add options for class color bg on mini frames  
- fix class color background resolver  
- feat(quickdraw): add preset for ping system  
- Add missing ID  
- fix(castbar): accurate arcane missiles cast bar  
    - Arcane Missiles fires fenceposted (first missile at channel start, last at  
      channel end), so the base channel draws 3 interior marks, not 4  
    - Count extra missiles from Amplification (236628, +2) and the tier set 2pc  
      (1296581, +1)  
    - A recast during a running AM channel keeps the outgoing cast's missile  
      schedule: draw the extra mark at the leftover time to the old channel's  
      next missile, then evenly from there (chain state keyed on the channel  
      castID so mid-cast window re-reports never chain a cast onto itself)  
    - Recasting immediately after a missile loses the bonus missile in-game, so  
      a carry of ~a full interval lays out as a fresh cast  
    - A cast bar rebuild landing mid-channel (spec-override/profile refresh via  
      ApplyAll, e.g. triggered by gaining Bloodlust) blanked the tick marks for  
      the rest of the cast; BuildCastBar now redraws them for the channel still  
      in progress (fixes this for all tick-marked channels, not just AM)  
- Add correct spell id  
- feat(pab): allow custom shapes for player auras like action bars  
- Quest Tracker: restore click-anywhere-on-header via native hit rect  
    Brings the feature back without putting addon code in the click path.  
    Instead of an overlay forwarding Click() to the MinimizeButton -- which  
    tainted ObjectiveTrackerContainer's dispatch loop and survived zone  
    changes -- widen the native MinimizeButton's own hit rect across the  
    header. The client then dispatches the click straight to Blizzard's  
    OnClick closure, the same path a bare +/- press takes and the one the  
    taint repro never reproduced on.  
    Verified against Gethe/wow-ui-source: both header templates  
    (ObjectiveTrackerContainerHeaderTemplate, ObjectiveTrackerModuleHeader-  
    Template) are plain Frames with no enableMouse, so the header cannot  
    swallow the click; their MinimizeButton OnClick is set by Blizzard in  
    the mixin OnLoad; and Blizzard never calls SetHitRectInsets on these  
    buttons itself, so nothing resets it.  
    The insets are recomputed on every skin pass to track Edit Mode resizes,  
    clamped at zero so a stale header can't leave a hit area hanging into  
    empty screen, expanded vertically to the full header height (the button  
    is 16px against a 26px header), and stop short of the FilterButton while  
    it is showing.  
- Quest Tracker: remove header click-forward, taint persists across zones  
    In-game repro (2026-08-15) showed the instance-gated click-forward from  
    the previous commit only narrowed the reproduction window instead of  
    closing it: forwarding a click to a header's MinimizeButton while  
    outside any instance still taints ObjectiveTrackerContainer's shared  
    dispatch loop, and that taint survives the zone change into a dungeon/  
    raid/scenario, throwing the same GetAuraDataByIndex secret-value error  
    out of ScenarioObjectiveTracker/UIWidgetObjectiveTracker's LayoutContents  
    the next time the container processes every module together. There is no  
    addon-side way to clear that taint, so the click-forward is removed  
    entirely. The native +/- button is untouched by this and keeps working  
    everywhere, since collapsing was never routed through it.  
- Quest Tracker: disable header click-forward inside instances  
    In-game repro (2026-08-15): forwarding Click() to a header's own  
    MinimizeButton from any tracker (not just the shared-widget-pool ones)  
    taints ObjectiveTrackerContainer's dispatch loop. Outside an instance  
    that's inert; inside a party/raid/scenario instance the same loop later  
    carries the taint into ScenarioObjectiveTracker/UIWidgetObjectiveTracker's  
    LayoutContents, throwing a GetAuraDataByIndex secret-value error. The  
    native +/- button never reproduces it since its OnClick is untouched, so  
    only the click-forward overlay is disabled while in an instance.  
- fix(abr): render icon text above borders and glows  
- Quest Tracker: skip header click-forward on shared-widget-pool trackers  
    MinimizeButton:Click() on ScenarioObjectiveTracker/UIWidgetObjectiveTracker  
    headers runs Blizzard's SetCollapsed() on a tracker whose blocks share the  
    widget pool with GameTooltip/AreaPOI widgets, the same taint surface  
    SharesWidgetPool() already guards everywhere else in this file. Gate the  
    click-forward overlay installation on it too.  
- ruRU: honour bundled fonts that carry Cyrillic glyphs  
    ResolveFontName treated every bundled font as Latin-only in glyph-restricted  
    locales, so ruRU always fell back to the system glyph font. Eleven of the  
    bundled faces cover the full Russian alphabet, Expressway included, and were  
    unreachable as a result.  
    Add FONT\_CYRILLIC listing the faces whose cmap covers U+0410-U+044F plus  
    U+0401/U+0451, and let ResolveFontName return those directly. The branch is  
    gated on a new LOCALE\_SCRIPT ("cyrillic"/"cjk"), so CJK is untouched: no  
    bundled face has CJK coverage.  
    Defaults are preserved. GetFontsDB seeds the system font in Cyrillic locales  
    instead of Expressway, and the ru\_cyrillic\_font\_optin\_v1 migration rewrites a  
    stored "Expressway" to the same sentinel. That value was unreachable from the  
    old ruRU picker, which could only store \_\_system, \_\_expressway or an external  
    SharedMedia name, so it is provably the seeded default rather than a  
    deliberate pick. Nothing changes until the user chooses a font.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Refactor CapName and ResolveDisplayName functions  
- Allow buff bars decimal treshold under 3s  
- add the ability to hide the group "Loot roll window" - either completely or after a certain amount of time  
- The ready check frame can now be styled in Ellesmere UI "modern" style, you can also hide the portrait  
- fix(bags): meet PR acceptance criteria -- default off, zero cost disabled  
    Show Set Name on Gear now defaults OFF (all reads flipped to == true  
    semantics), matching the "new settings default off" rule. Zero-cost-  
    while-disabled pass: EQUIPMENT\_SETS\_CHANGED is registered dynamically  
    (only while either set feature is on, updated from both option setters),  
    the SetNameText FontString is lazy-created on first actual display  
    instead of on every pooled button, and every per-refresh scan the  
    feature added (setCatIdx refill, name stamping, sidebar children scan,  
    filterSet/All Items/group-view/Auto-Size folds) is gated on its toggle.  
    With both toggles off the remaining footprint is one flag read per  
    gated site.  
- Add Enemy Name Text Reaction Colour toggle  
    Opt-in setting (default off) that colours enemy nameplate name text  
    Hostile/Neutral to match the unit's reaction, independent of the  
    existing Enemy Name Text color. Hooks the existing UpdateHealthColor  
    event cadence rather than adding new events.  
- perf(bags): options row rebalance + skip set-name lookups when label off  
    Desaturate Junk Items moves up from its half-empty EXTRAS row to pair  
    with Merge Duplicate Items in DISPLAY (it is a display effect), so no  
    options row sits half-empty. BuildSetGearLookup skips the per-set  
    GetEquipmentSetInfo name calls when Show Set Name on Gear is off.  
    Deep perf review (2 adversarial lenses) upheld the no-meaningful-cost  
    claim: the feature adds ~6-8KB alloc/refresh (~5% of the existing  
    80-150KB baseline) and ~0.06-0.2ms CPU on a 10-30ms refresh, debounced  
    to <=10Hz with an IsVisible early-out; loot storms don't touch  
    EQUIPMENT\_SETS\_CHANGED, and VisualSortCompare never calls IsGearCategory  
    so there's no O(N log N) amplification.  
- Guard inactive tooltip comparison cleanup  
- Drop zero-flash tooltip suppression  
- feat(bags): set-name text size cog + half-row options placement  
    Show Set Name on Gear moves next to Split Set Gear by Set in one dual  
    row (Merge Duplicate Items returns to its own row), and gains an inline  
    resize cog opening a Text Size slider (bagSetNameFontSize, 7-14,  
    default 9 = the old computed size). Font face keeps following the bags  
    font like every other bag text element.  
    Perf audit of the whole feature vs main: no meaningful per-refresh cost  
    added -- the set lookup already ran per classify pass on main; the new  
    work is O(#cats) scans and one label SetText per button.  
- Skip comparison work while tooltip suppression is inactive  
- refactor(bags): nest split-mode set categories as children of the anchor  
    Replace the runtime-group model with anchor + children: the Item Set  
    Gear category is always built normally (keeping its saved position,  
    rename, and The Armory grouping), and split mode appends runtime-only  
    per-set child categories after it. The sidebar renders them one level  
    under the anchor -- third level when the anchor sits inside a group --  
    instead of as a separate top-level group. Anchor and group views fold  
    the children's items in; All Items looks identical to merged mode.  
    This deletes the SaveState collapse/carry-over machinery and all the  
    runtime-group guards the old model needed. Kept fixes: header-drag  
    persistence, selection re-resolution by stable key (now also applied  
    when toggling the option, via EUI\_Bags.InvalidateSetCategories), child  
    drag/reorder blocks. New from review: disabling the anchor now disables  
    its children too, the classify fallback matches the anchor explicitly,  
    child rows open no empty context menu, the drag insert line no longer  
    targets gaps inside the child block, and Auto-Size counts the folded  
    anchor view correctly.  
- Make comparison suppression lazy and taint-safe  
- feat(bags): nest set categories under Item Set Gear and label set gear  
    Split-mode set categories now join a runtime group named after the Item  
    Set Gear anchor, so the sidebar shows them indented under a header  
    instead of as a flat block. The group is rebuild-owned: rename/disband/  
    ungroup/joins are refused (they would silently revert), hide state  
    persists under the stable anchor key, member drag is blocked while the  
    header still moves the whole block (header block-moves now SaveState,  
    which normal groups also gain).  
    Separately, gear belonging to an equipment set gets the set's name  
    bottom-center on its bag icon (new toggle, default on; works in merged  
    mode too). The label yields to the upgrade-track rank when that occupies  
    the same row. Known cosmetic edge: with Item Set Gear disabled or a  
    manual assignment overriding set gear, a merged pair of identical items  
    can carry the wrong label.  
- Avoid per-hover comparison cleanup closures  
- Fix combat item comparison tooltips  
- Locale: wrap slot names, tooltips, and fallback labels that skip L()  
    Several display strings across bags, character sheet, socket panel,  
    Quickdraw, and QoL are built by string concatenation or string.format  
    before reaching L()/Lf(), so a runtime-composed string can never match  
    a catalog key even when a translation exists.  
    - Character sheet: wrap item.slot at the three tooltip display sites;  
      rename the cloak slot literal "Back" -> "Cloak" to avoid colliding  
      with the existing "Back" nav-button catalog entry (Cloak already has  
      a translation in every shipped locale, matches EUI\_UpgradeCalc.lua's  
      own slot table). Wrap the " Crests" suffix that was concatenated  
      outside L().  
    - Socket panel: wrap the empty-socket tooltip and the "No gems in  
      bags." flyout row.  
    - Quickdraw: wrap the keybind-picker tooltip (including the optional  
      intro line); split the nested-menu "N entries" caption into separate  
      singular/plural Lf() keys instead of an English plural suffix.  
    - Bags/Bank: wrap the fallback tab/bag name fallbacks ("Bag N",  
      "Tab N", "Bank Tab N") with Lf().  
    - QoL: localize the trainer "Learn N skill(s) for ..." tooltip, same  
      singular/plural split as the Quickdraw caption.  
    New Lf() keys have no zhTW translation yet; they render in English  
    until a follow-up locale PR adds them (no regression vs. before).  
- feat(bags): split Item Set Gear into one category per equipment set  
    New profile toggle (default off) expands the Item Set Gear anchor into  
    per-set categories named and iconed after each C\_EquipmentSet set, the  
    way Baganator/BetterBags surface set membership. Runtime-only: SaveState  
    collapses the block back to the anchor so per-character setIDs never  
    reach the shared profile (order, state, hidden keys all collapse), and  
    zero sets falls through to the merged category so the anchor keeps its  
    saved position. EQUIPMENT\_SETS\_CHANGED now invalidates the category  
    cache and re-resolves the selected view by stable key; the setID->index  
    map and gear-category cache rebuild every classify pass so drag-reorder  
    cannot misroute set gear. Set categories refuse rename/group/drag since  
    none of it would persist.  
    Known limits (pre-existing wart, tracked separately): bagVisualOrder is  
    keyed by numeric category index, so toggling split shifts saved manual  
    item orders; an open context menu can act on shifted indices if sets  
    change mid-menu.  
