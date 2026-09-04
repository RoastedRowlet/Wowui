# EllesmereUI

## [v9.1.6](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.1.6) (2026-09-02)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.1.5...v9.1.6) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.1.6  
- Merge pull request #1918 from dfrisone/fix/classpower-size-reset-zone  
    Fix Class Resource pips widening after a zone change  
- Merge pull request #1917 from svart2521/absorbs-max-health-style  
    Fix: Max Health Style not rendering when Absorb Style is disabled  
- Merge pull request #1916 from svart2521/cdm-buff-bar-preview-missing  
    Fix: Liquid Luster missing as a default potion preset in CDM buff bars  
- Merge pull request #1915 from JuJuFX-dev/feature/bnet-toast-skin  
    feat+fix(blizzskin): skin the BNet friend online/offline toast and fix a taint issue  
- Merge pull request #1912 from dfrisone/fix/qt-master-header-onshow-taint  
    Fix: quest objectives stop updating until /reload  
- Merge pull request #1911 from svart2521/multi-modifiers-dont-work  
    Fix: multi-modifier keybinds silently not triggering  
- Merge pull request #1909 from Barbiero/feat/warlock-wrong-demon-reminder  
    ABR: Configurable, spec-agnostic Warlock wrong-demon reminder  
- Merge pull request #1908 from svart2521/lfg-reminder-not-working-for-german-client  
    Fix: LFG Reminder never firing on non-English/Russian clients  
- Merge pull request #1907 from svart2521/dk-pips-borders-not-working  
    Fix: DK rune pips not honoring Border on Individual Pips  
- Merge pull request #1904 from tough-griff/fix/warrior-charges-threshold-respect-config  
    Fix Sweeping Strikes / Whirlwind threshold config  
- Merge pull request #1901 from LoChinAn/locale-zhtw-bank-grouping-visibility-overrides  
    zhTW: translate 32 new keys for bank grouping, queue timer and visibility overrides  
- Merge pull request #1899 from 0x963D/codex/buff-stack-glow-comparison  
    feat(cdm): add stack glow comparisons  
- Merge pull request #1900 from Crazyyoungs/main  
    Update koKR.lua  
- Merge pull request #1898 from Barbiero/locale/ptbr-since-913  
    ptBR: translate Bank category sidebar, Recent Items, and Visibility override tooltips  
- Merge pull request #1888 from dfrisone/fix/uf-visibility-override-stale-driver  
    Fix(Unit Frames): keep the frame built when Visibility is set to Never  
- Stretch the class power row over the shown pip count  
    \_repositionForWidth divided the target width by #pips, the high-water  
    mark the rebuild's shownPipCount already exists to replace: once a  
    resource max shrank, the "above" row laid its remaining pips out at the  
    old pip width and left a permanent gap at the right edge of the health  
    bar until the max grew back.  
- Fix: Max Health Style not rendering when Absorb Style is disabled  
    Bug:  
    Issue: Raid Frames' Max Health Style overlay (e.g. for max-HP-reduction debuffs like the Den of Nalorakk curse) never rendered unless Absorb Style was also enabled, even though it's meant to be independent like Heal Absorb Style/Bar. Two separate early-return gates in UpdateAbsorb bailed out of the shared overlay frame whenever Absorb Style was off, without ever checking whether Max Health Style itself was on.  
    Fix: Added a maxHealthOn flag checked by both gates so the function keeps painting when Max Health Style is enabled on its own. Also scoped the shield-absorb-specific bar painting (previously reached via fallthrough) behind styleOn so it doesn't re-show the unstyled shield-absorb overlay when Absorb Style is off.  
- Fix: Liquid Luster missing as a default potion preset in CDM buff bars  
    Bug:  
    Issue: Liquid Luster was already in the CD/Utility bar item preset list (CDM\_ITEM\_PRESETS) but missing from BUFF\_BAR\_PRESETS, the separate list that feeds the Custom Buff Bar preset picker, so it never showed up as an option there alongside Light's Potential and Potion of Recklessness.  
    Fix: Added a liquid\_luster entry to BUFF\_BAR\_PRESETS (spell 1295132, 30s duration), matching the shape of the other two combat potion entries.  
- Convert the three remaining Shell copies to the same script hook  
    The Character Sheet, Inspect Sheet and Group Finder build their own shell and  
    adopt it through WSkin.AdoptShell rather than going through WSkin.Shell, so the  
    window engine's conversion did not reach the copy of UpdateBgTexCoords each of  
    them carries. All three still hooked SetSize/SetWidth/SetHeight with  
    hooksecurefunc, which is the field write onto a Blizzard frame the engine just  
    stopped doing. PVEFrame is the most taint-sensitive of the three.  
    The same three copies were also missing the engine's secrecy test, and the zero  
    check they run instead is itself a comparison that throws on a secret size.  
    Switching to OnSizeChanged widens when that function runs, so the guard is added  
    here rather than left for later.  
- Add a Blizzard window skin for the BNet friend online/offline toast  
    BNToastFrame was the last visible popup with no EUI skin, still carrying its  
    gold BACKDROP\_TOAST\_12\_12 frame and Blizzard's font while every comparable  
    element (loot toasts, loot rolls, group invites, ready check) already runs  
    through the window skin engine.  
    New window pack "bnettoast", wired the usual six ways: enable key  
    reskinBNetToast, its own style-seed batch so existing accounts inherit their  
    majority style, an options card under Blizzard Window Skins, a reset entry and  
    the profile allowlist. Chrome only: shell, border, close button, house font on  
    the four text lines, house panel on the broadcast tooltip. The toast-type icon  
    stays native, since it is a SetTexCoord crop out of one sheet that  
    WSkin.SquareIcon would overwrite, and the flair glow is cleared rather than  
    alpha'd because it carries its own alpha animation.  
    WSkin.Shell no longer hooks SetSize/SetWidth/SetHeight with hooksecurefunc.  
    That form is a field write onto a Blizzard frame whose field Blizzard reads  
    back, and BNToastMixin:ShowToast calls SetHeight in the very chain whose  
    OnClick opens a Battle.net whisper - the hazard EllesmereUIChat already  
    documents for SetPoint on this frame. A HookScript("OnSizeChanged") replaces  
    all three, which also covers anchor-driven resizes the setter hooks never saw.  
- Fix UnitFrames Class Resource widening on a zone change  
    The pip rebuild that runs whenever the resource max changes finished by  
    re-stretching the pips across the frame width. That stretch only belongs  
    to the "above" position, where PositionClassPowerBar anchors the row to  
    the health bar's edges -- the comment said so, the code did it  
    unconditionally. Every loading screen re-reads the max (talent data  
    reloads with the zone), so any other position lost its configured pip  
    size and came back spanning the whole frame until the next reload, with  
    the profile value itself untouched.  
    Gate the re-stretch on modern + "above", the same pair  
    PositionClassPowerBar and the warrior-charge sync already test.  
- Reconcile the "never" decoupling with applied Visibility overrides  
    An applied Visibility override replaces the whole shared setting, "never"  
    included, so the new never handling cannot read the stored scalar: a shared  
    Never under an override of Always would pin the secure driver to a constant  
    hide and the frame would stay missing, and an override of Never would leave the  
    unlocked class resource bar on screen.  
    The visibility pass now derives one override-aware verdict and both driver pins,  
    the class resource bar and the Show/Hide bucket read it. The other "never" reads  
    this branch added -- Blizzard frame source, the mini donor, player cast bar  
    suppression, the unlock movers -- go through ns.VisEffective for the same reason.  
    VisUnitDisabled drops its override carve-out with it. That carve-out existed  
    because Visibility wrote enabledFrames; now that it does not, the flag means only  
    the "Enable X Frame" toggles, and honouring an override there would resurrect a  
    frame the user deliberately disabled.  
- perf(unitframes): drop a per-call closure and an unconditional alpha write  
    GetMiniDonorSettings runs from the mini frames' OnEnter/OnLeave, so the local  
    helper it grew allocated a closure on every hover for no reason; back to plain  
    branches.  
    The class resource bar alpha is written from the visibility pass, which runs on  
    every target change, and for the "blizzard" style the bar is Blizzard's own  
    frame. Write it only when it actually moves.  
- Pin "never" on the secure driver and share one mini-donor rule  
    The Show/Hide bucket that hid a "never" frame is lockdown-gated, so acquiring a  
    target in combat let the unit watch show an alpha-0 click blocker until regen.  
    Never is terminal, so it pins state-visibility to a constant hide instead -- the  
    same lever the companion mini already uses -- and the watch cannot out-vote it.  
    The unlock movers gated on the element's own barVisibility, which the minis and  
    an unlocked class resource bar do not have; map each to the frame whose  
    Visibility governs it, with Always Show Pet opting out as it does everywhere.  
    The options file carried two more copies of the mini-frame donor rule, so a focus  
    set to Never fell out of the live frames' inheritance but not the preview's.  
    Both now route through the runtime resolver.  
- Carry "never" through the paths that assumed an unspawned frame  
    Four places treated Visibility "Never" as "no frame exists", which was true only  
    because it used to clear enabledFrames:  
    ResolveVisResting had no alpha case for it, so the mode rested on the Show/Hide  
    bucket alone -- and that bucket is lockdown-gated, leaving a Never picked (or  
    applied by an override) in combat at full alpha until PLAYER\_REGEN\_ENABLED.  
    The companion mini frame inherited only the parent's alpha, so a "never" parent  
    left an invisible click blocker; pin its driver the way the disabled-parent  
    branch already does.  
    A class resource bar unlocked from the frame is parented to UIParent and outlived  
    its owner. Only Never takes it along -- the other hiding modes have always kept  
    their own bar visible.  
    GetMiniDonorSettings picked the mini frames' border/texture/font donor off  
    enabledFrames, so a focus set to Never used to fall out for free and now has to  
    be checked directly.  
- Address review findings on the Visibility decoupling  
    The migration cleared the base enabledFrames flag but left the same fkey banked  
    in the spec and conditional override stores, where auto-capture put it while the  
    two keys were written together. Nothing blacklists it, so the next spec apply  
    wrote false back and the frame went missing again at the following login -- and  
    with Visibility no longer writing the key there was no way back from the UI.  
    Strip it for player/target/focus, the same way the Dragon Riding migration does;  
    the other units keep theirs, since their Enable toggles own that key.  
    Under a leftover Match Any selection the engine evaluates the scalar and answers  
    false rather than nil for "never", so the secure bucket read it as engine-owned  
    and kept the frame shown at alpha 0 -- invisible but still eating clicks. Never  
    is exclusive, so it now settles the verdict ahead of the engine.  
    A frame Visibility hides outright is built but never on screen, so its unlock  
    mover had nothing to drag. Gate the unit and cast bar elements on isHidden,  
    which is re-read on every unlock-mode open, so lifting the hide needs no reload.  
- Fix(Unit Frames): stop Visibility "Never" from unbuilding the frame  
    Visibility "Never" wrote enabledFrames[unit] = false alongside barVisibility, and  
    that key is a build-time decision: ns.GetUnitFrameSource reports the unit  
    "hidden" and InitializeFrames skips the spawn entirely. A Spec Override carrying  
    "Never" therefore left the frame uncreated for the whole session -- switching  
    back to a spec without the override wrote enabledFrames true again and ran the  
    reload pass, but there was no frame to show and only a /reload brought it back.  
    Visibility is a runtime axis now and leaves enabledFrames alone, so the frame is  
    always built and "never" is hidden the same way "in\_combat" and "mouseover" are:  
    ToggleFrame's group trio and UpdateFrameVisibility's secure bucket both already  
    handle it, and both reverse when the override lifts. enabledFrames goes back to  
    meaning what the Enable Pet / Target of Target / Focus Target / Boss toggles say,  
    which is why SetUnitFrameSource no longer rewrites barVisibility to keep the two  
    in sync -- picking a frame source would otherwise clear a user's "Never".  
    Two things ride on the old pairing and are kept: a unit on Blizzard's frame set  
    to "Never" still resolves "hidden", since suppressing Blizzard's frame is the  
    only way to honour it when we spawn nothing of our own; and Blizzard's player  
    cast bar is still left alone under "Never", because ours is built but hides with  
    the frame. A profile migration clears the enabledFrames flag the old pairing  
    wrote for player/target/focus -- those three have no Enable toggle of their own,  
    so a stored false there can only have come from it.  
- Fix Warrior charge count text ignoring configured font  
    WC\_Sync ran before \_countText was created and styled, so the engine  
    slot baked its count-text font from a nil fontstring and fell back to  
    a hardcoded Expressway 12 OUTLINE. Move the call after the text setup  
    so the configured font and size apply on /reload.  
    Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>  
    Claude-Session: https://claude.ai/code/session\_01PcMbcZg9X5oNsnHBQNoVy7  
- Quest Tracker: re-apply master header suppression on a profile swap  
    The OnShow fight re-read the setting on every Blizzard Header:Show(), so it  
    self-healed across a profile switch. The alpha suppression is a one-shot, and  
    \_EQT\_RefreshAll never called it: switching to a profile that hides the header  
    left it drawn outside the background (ApplyBackground re-anchors the BG top to  
    the header's bottom edge), and switching the other way left the collapse-all  
    button mouse-disabled until /reload.  
- Quest Tracker: stop the objective tracker freezing mid-quest  
    The "All Objectives" master header is hidden by default, and it was kept  
    hidden by an OnShow script that re-hid it every time Blizzard showed it.  
    ObjectiveTrackerFrameMixin:Update() calls Header:Show() immediately before  
    the container layout, so that script ran inside the update chain and  
    tainted the rest of the pass. ScenarioObjectiveTracker lays out first and  
    its LayoutContents reads player auras via ShouldShowMawBuffs, which hard  
    errors under taint; the pass unwound before DirtiableMixin cleared  
    self.dirty, so MarkDirty never scheduled another one and the tracker  
    stopped updating until /reload.  
    Suppress the header with alpha instead, the way POI buttons already are.  
    The header's shown state has no effect on layout, so this is visually  
    identical, and it puts no addon code in Blizzard's update chain.  
- Fix: multi-modifier keybinds silently not triggering  
    Bug:  
    Issue: EUI's custom keybind-capture widgets (used across several options pages to bind an EUI action to a key combo) built the modifier prefix in SHIFT-CTRL-ALT order, but Blizzard's binding engine requires the canonical ALT-CTRL-SHIFT order, so any bind using two or more modifiers (e.g. CTRL+ALT+1) saved and displayed fine but never actually fired; single-modifier binds were unaffected since order doesn't matter with only one.  
    Fix: switched all affected capture sites to CreateKeyChordStringUsingMetaKeyState (with a correctly-ordered ALT-CTRL-SHIFT-META manual fallback), matching the same fix already proven correct elsewhere in this codebase for the identical bug.  
- feat(warlock): Wrong Demon reminder is now clickable too  
    Reuses the same pet-cycle logic as Missing Pet: left-click on a Wrong  
    Demon reminder attempts to summon a correct demon, right-click  
    previews/cycles through the allowed ones without casting. Both  
    reminders share one cycle index, so cycling on either advances the  
    same pointer.  
- i18n(ptBR): translate warlock demon reminder strings  
    Covers the new Wrong Demon / Allowed Demons options and the Imp,  
    Voidwalker, Felhunter, and Sayaad pet names (looked up officially by  
    spell id; Felguard already had a translation). Drops the now-dead  
    "Wrong Pet (Demo Lock)" entry the reminder no longer uses.  
- chore(locale): regenerate key list  
    New literal L()/Lf() keys from the wrong-demon reminder work; Felguard  
    drops off the static list since its only literal call site is now a  
    variable lookup (still reachable at runtime through the pet table).  
- feat(warlock): configurable, spec-agnostic wrong-demon reminder  
    Lets any Warlock spec pick which demons count as correct for the  
    active-pet reminder instead of hardcoding Felguard for Demonology only.  
    A demon only counts while its summon spell is actually known, so an  
    untalented Summon Felguard silently drops out rather than nagging for  
    an unobtainable pet, and cosmetic Grimoire-of-* reskins (Wrathguard,  
    Voidlord, Fel Imp, Observer, Shivarra/Incubus) no longer trip a false  
    positive. The Missing Pet reminder can now be clicked to summon the  
    chosen demon directly, or right-click to preview/cycle between several  
    allowed demons without casting.  
- Fix: LFG Reminder never firing on non-English/Russian clients  
    Bug:  
    Issue: QoL's LFG Reminder popup silently never fired on a German client (and every other locale besides English/Russian) because TELEPORT\_BY\_NAME was seeded only from a hardcoded English/Russian alias list, while the joined LFGList activity's fullName comes back in the client's own locale and never matched.  
    Fix: For each SEASON\_PORTALS entry, also seed TELEPORT\_BY\_NAME with GetLFGDungeonInfo(dungeonID)'s live, client-locale dungeon name (pcall-wrapped), so the lookup self-corrects for every client locale automatically instead of relying on hardcoded translations.  
- Fix: DK rune pips not honoring Border on Individual Pips  
    Bug:  
    Issue: Death Knight rune pips were hardcoded to always draw the outer secondary-frame border and never the per-pip border, ignoring the Border on Individual Pips setting that every other resource bar type respects.  
    Fix: Removed the DEATHKNIGHT/runes special-casing so rune pips apply the per-pip border via ApplyBorder when Border on Individual Pips is enabled, and hide the outer border in that case like other pip types.  
- Raise count-based threshold input cap from 10 to 20  
    Sweeping Strikes stacks to 18 with Broad Strokes, so the class/secondary  
    resource bar threshold input clamped it to 10. Bump the pip/count cap to  
    20; bar-type (percent/value) and stagger caps are unchanged.  
    Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>  
    Claude-Session: https://claude.ai/code/session\_01PcMbcZg9X5oNsnHBQNoVy7  
- Fix Warrior charge bar showing threshold overlay when disabled  
    The WHIRLWIND\_STACKS / SWEEPING\_STRIKES engine-fed class bar routes its  
    threshold coloring through ns.WC\_Thresholds. That call passed  
    \_tsThreshCount unconditionally, but when the threshold entry is disabled  
    (or a tracked buff is active) the resolver only nils \_tsEntry --  
    \_tsThreshCount still falls back to the legacy global sp.thresholdCount.  
    The engine module then builds a range strip from any count > 0, so the  
    overlay showed regardless of configuration.  
    Gate the count on \_tsEntry, matching every other threshold renderer in  
    this function.  
    Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>  
    Claude-Session: https://claude.ai/code/session\_01PcMbcZg9X5oNsnHBQNoVy7  
- zhTW: translate 32 new keys for bank grouping, queue timer and visibility  
    Covers the bank page's new GROUPING and SIDEBAR blocks (category sidebar,  
    group by category, hide empty slots when grouped) plus the bank grid's  
    "Empty Slots" / "No Items" headers, the queue-timer countdown options in  
    Blizzard Skin, the new Not Skyriding (Airborne) visibility row and the  
    override-session lock/pick tooltips, and the Arms/Fury charge-bar threshold  
    notices in Resource Bars.  
    The override lock tooltip is stored twice: the widget concatenates the  
    shared text with the Mouseover-sealed sentence before it reaches L(), so  
    the combined string needs its own key or that variant falls back to English.  
    Also rewords "Cast Bar Y Offset" and "Text Offset Y" to spell the axis out  
    in words instead of the bare letter, matching "Extra Y Offset" and  
    "Y-Offset" which already do.  
- Update koKR.lua  
- feat(cdm): add stack glow comparisons  
- ptBR: translate Bank category sidebar, Recent Items clear button, health text trailing zeros, Queue Timer Style, and Visibility override lock tooltips  
