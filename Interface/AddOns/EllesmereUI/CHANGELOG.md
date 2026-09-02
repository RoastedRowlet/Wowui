# EllesmereUI

## [v9.1.5](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.1.5) (2026-09-01)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.1.3...v9.1.5) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.1.5  
- Merge pull request #1896 from svart2521/mythic-plus-tools-focus-cast-bar-doesnt-show-full-name-of-spell-cast  
    Fix: M+ Tools cast bars truncate spell names with room to spare  
- Merge pull request #1895 from dfrisone/fix/menu-fallback-raid-target-icon  
    Fix(Menus): grey out Raid Target Icon in the backstop's re-opened unit menu  
- Merge pull request #1892 from tenngoxars/locale/zhcn-913-localization  
    locale(zhCN): translate new 9.1 strings  
- Merge pull request #1894 from dfrisone/fix/minimap-rectangular-blip-clip  
    Fix(Minimap): Clip rectangular mode's blips to the visible rectangle  
- Merge pull request #1893 from dfrisone/fix/communities-roster-scrollbox-taint  
    fix(blizzskin): stop re-anchoring the Communities roster scroll box  
- Fix: locale keys header comment count out of date  
    Bug:  
    Issue: EllesmereUILocales/\_keys.txt's header comment claimed 779 unique keys while the actual list already had 780, a stale comment already present upstream on main -- CI's locale-check workflow regenerates the file and fails the PR on any mismatch, so it failed here too even though this branch didn't add or remove any locale keys itself.  
    Fix: Re-ran .tools/extract-locale-keys.sh to regenerate the file; only the header count comment changed.  
- Merge branch 'EllesmereGaming:main' into mythic-plus-tools-focus-cast-bar-doesnt-show-full-name-of-spell-cast  
- Merge pull request #1887 from svart2521/target-border-target-effect  
    Fix: Target border size resetting to default when casting with Border Wraps Around Cast Bar  
- Fix: M+ Tools cast bars truncate spell names with room to spare  
    Bug:  
    Issue: Target/Focus and Targeted Spell cast bars in M+ Tools always reserved a flat 48% of the bar width for the spell name, leaving the rest for target text even when nothing was there to show (self-casts, or Show Target off), so short names truncated to "..." well before running out of room; SetText also ran before the width pass, so a later widening couldn't reliably un-truncate already-laid-out text.  
    Fix: Both files now reclaim the target zone's width for the name whenever the current cast has no target text to show, and the width/anchor pass runs before SetText instead of after.  
- Merge pull request #1886 from mariusch/feature/health-text-trim-zeros  
    Unit Frames: option to hide trailing zeros on health percent text  
- Merge pull request #1885 from dfrisone/feat/bank-grouping-category-sidebar  
    Add(Bank): expansion nesting, category grouping and a category sidebar  
- Merge branch 'main' into feat/bank-grouping-category-sidebar  
- Merge pull request #1884 from mariusch/feature/queue-timer-style  
    Blizzard Skin: configurable color, size, height and offset for the queue accept countdown  
- Merge pull request #1883 from mariusch/feature/npc-nameplate-colors  
    Nameplates: configurable name and title styling for friendly NPC name-only plates  
- Merge pull request #1882 from dfrisone/fix/cdm-bar-apply-stamp-order  
    Fix(CDM): Apply to Bar leaves preset icons on the default value  
- Merge pull request #1881 from dfrisone/fix/cdm-active-overlay-toggle-reset  
    Fix(CDM): Active State colour reset by Apply to This Spell  
- Merge pull request #1880 from dfrisone/fix/cdm-range-override-taint  
    Fix(CDM): range tint follows the live override spell  
- Merge pull request #1877 from JuJuFX-dev/fix/visibility-any-hide-veto  
    Fix(Visibility): Hide always hides, and an override replaces the setting  
- Clip the rectangular minimap's blips to the visible rectangle  
    The rectangular shape keeps a square native canvas and hides its top and  
    bottom strips with a mask, but the mask only covers the terrain: the engine  
    still draws unit blips across the whole canvas, so player and party arrows  
    appear above and below the border, most visibly in a battleground.  
    The native render is clipped to the minimap's parent rect -- ordinary child  
    frames and textures are not, which is why the border and buttons keep drawing  
    outside it -- so the square canvas now sits inside the 4:3 layout frame every  
    other rectangular-mode element already anchors to. That frame moves out of the  
    minimap and up to UIParent, and is re-anchored on every pass because its anchor  
    now spans the deferred SetParent.  
    Both combat bailouts on the reparent path also queue the apply that the module  
    already retries when combat ends. Without that, a reparent Blizzard performs in  
    combat (battleground and housing transitions) stood for the rest of the  
    session, leaving the map parented to -- and clipped by -- MinimapCluster, which  
    cut the top off the map once it grew past the cluster's own 256px bounds.  
- fix(blizzskin): stop re-anchoring the Communities roster scroll box  
    The guild pack lifted MemberList.ScrollBox 2px and pushed its ScrollBar 5px  
    right. Both are one-shot cosmetic nudges, but they leave addon-written anchors  
    on the frames the list view measures: CalculateDataIndices reads  
    ScrollBox:GetVisibleExtent() (a GetSize on those points) in the same pass that  
    creates the row buttons, so every row is born tainted and stays that way for  
    the session. Hovering a member then dies on the secret member fields, e.g.  
    C\_CreatureInfo.GetRaceInfo(memberInfo.race) from the roster tooltip.  
    Drop both nudges and fold the reason into the existing "never widen the roster"  
    note so the whole scroll subtree is off limits, not just its width.  
- Menu fallbacks: grey out Raid Target Icon in the re-opened unit menu  
    The togglemenu classifier misfires for a raid member whose unit data has  
    not streamed, so the backstop re-opens the correct player menu from Lua.  
    That menu is tainted and its entries' click closures carry the taint, so  
    picking a marker reaches the protected SetRaidTarget and throws  
    ADDON\_ACTION\_FORBIDDEN.  
    Set Focus, Follow and View Houses were already disabled for that menu;  
    Raid Target Icon was missed. Disabling the submenu covers all nine  
    markers. Every other entry in the RAID\_PLAYER/PARTY menus (promote,  
    demote, trade, inspect, duel, uninvite) is unprotected.  
- locale(zhCN): translate new 9.1 strings  
- Fix(Visibility): seven gaps found reviewing the override feature  
    An override REPLACES the whole Visibility setting, and the review of that  
    feature turned up seven places where either half of that sentence did not  
    hold: the shared value it replaces, or the modules that have to obey it.  
    The checklist read the shared selection through the evaluator-facing view,  
    which hides the stored mode set while an override applies. The rows then  
    rendered the bare legacy scalar and the next click wrote that rump back over  
    the set, silently dropping every other condition. ActiveModes and  
    GetVisibilitySelection take an ignoreOverride flag now; the options row, the  
    sync-icon compare and the sync copy all pass it, because they edit or compare  
    the shared value and never touch the marker. Evaluators and driver compilers  
    pass nothing and keep the replacing behaviour.  
    The row gated on SpecOverrides\_EditSessionActive, which is global, but the row  
    also sits on pages excluded from the override systems (Quest Tracker, Damage  
    Meters, the CDM Tracking Bars tab). There a picked state wrote a marker every  
    capture gate drops as blacklisted, stranding it in the shared profile with  
    nothing owning it; the editing-as overlay is decoration only and stops no  
    click. A new SpecOverrides\_SlotOverridable asks the session AND the page.  
    Resource Bars drive health, primary and secondary from one control, and the  
    scalar, the mode set, the match mode and the option lanes all fan out. The  
    marker did not: it landed on secondary alone and the other two kept obeying  
    the setting it was meant to take over. An opts.getStores hook carries it as  
    far as the shared value goes, and SpecOverrides\_ClearStoreKey takes an array  
    so three stores clear in one pass rather than re-snapshotting every module  
    profile three times on one click.  
    Three modules read the shared value raw and never saw the marker. Unit Frames  
    gate the whole visibility pass on enabledFrames, which is also how a shared  
    "never" is stored, so an Always override could not bring a frame back; the new  
    ns.VisUnitDisabled lifts that veto for a Visibility "never" while leaving a  
    frame source of "hidden" (the cog's own choice) winning. Data Bars tear a bar  
    down entirely on a raw visibility == "never" in four places, now behind  
    ns.VisIsNever. Action Bars kept hiding on visHideNoTarget and visHideMounted  
    inside ShouldHideNonMacro, ahead of the guard the shared helper already had.  
    A marker nothing owns any more pinned its element with no path back: the  
    management list's Remove drops the entry but deliberately leaves applied values  
    alone, and a profile exported while an override applied carried the marker into  
    every import that did not also take the overrides. SpecOverrides\_KeyIsOwned  
    answers whether some entry still holds it; the row heals a stranded one on page  
    build (outside any session, with a deferred light re-apply so the element  
    catches up), and ImportProfile strips it from incoming addon data when the  
    override stores are not coming along.  
    Carried along, smaller: the capture slot's setValue now writes back where its  
    getValue reads from, so the pair round-trips; the dispatcher stopped asking for  
    the option hide veto twice per event under Match Any, where the extended  
    evaluator already runs it (Match All still leads with the veto, and the legacy  
    orphan hand-back keeps it); GetChecked reads a memoized selection instead of  
    allocating one per lane per refresh sweep; and the sealed block hides itself  
    while a search filter is active, since it is anchored to rows that filter  
    hides and moves.  
    Documented rather than changed: hide\_not\_dragonriding stays Lua-resolved. Under  
    Match Any it compiles to the combat escape hatch, so entering combat on the  
    ground reveals the element until the next out-of-combat rebuild, while Match  
    All and the equivalent Show on Skyriding (Airborne) stay live in combat. A gate  
    would need a two-bracket clause rather than the single token the axis table  
    carries, and whether [noadvflyable] parses is not something Lua source can  
    answer, so it waits for an in-game check instead of a guess.  
    No SavedVariables are written at login by any of this: no new event  
    registration, no migration, no DEFAULTS entry for visibilityOverride or the  
    hide lanes. Every write is a user click, a page visit that finds a stranded  
    marker, or an import.  
- Feat(Visibility): fold the sealed Mouseover row into the block  
    The Mouseover row a module has to seal now joins the sealed run instead of  
    carrying a lock of its own. It sits directly above the section header the block  
    starts at, so the block simply grows by one row and stays contiguous, with Never  
    and Always left outside it where they belong.  
    The block carries ONE tooltip, so a module that seals Mouseover too gets a  
    sentence appended saying why, rather than losing that reason to the shared text.  
- Fix: Target border size resetting to default when casting with Border Wraps Around Cast Bar  
    Bug:  
    Issue: With Border Wraps Around Cast Bar enabled alongside the target border-size effect, UpdateBorderWrap rebuilt the wrapped border using the plain default border size instead of the target-effect size, so casting on your current target visibly shrank the border back to normal for the cast (and again when the cast ended).  
    Fix: UpdateBorderWrap now checks whether the plate's border was resized for being targeted and uses the target border-size value on both the wrap-on and wrap-off paths, so the target border stays correctly sized through casting.  
- Feat(Visibility): lock the Mouseover override where it cannot work  
    Action Bars wire their hover mechanism from the STORED mouseoverEnabled, which  
    an override never writes, so a Mouseover override there simply left the bar  
    shown. Nothing broke, but the row offered a state that quietly did nothing.  
    An opt-out cap covers it: caps.noOverrideMouseover locks the Mouseover row while  
    an override is being edited, with a tooltip saying why and that Never and Always  
    do work. Both Action Bars rows declare it. The lock is a plain one rather than  
    the sealed block, because the seal marks one contiguous run further down and  
    this row sits above it among the states that DO work.  
    Deliberately per module, not global: every other consumer derives its hover  
    state from the LIVE verdict -- Resource Bars, Data Bars, Minimap, Quest Tracker,  
    Friends and Damage Meters go through EvalVisibilityExtended or VisWantsMouseover,  
    both of which already answer from the override -- so a Mouseover override works  
    there and stays offered.  
- Fix(UnitFrames): a Mouseover override made the frame unreachable  
    Both hover handlers gate on the cheap static prefilter  
    `(s.barVisibility or "always") == "mouseover"`, which reads the SHARED scalar. An  
    override holding Mouseover leaves that scalar alone, so the visibility pass  
    rested the frame at alpha 0 through the live verdict while neither handler was  
    willing to reveal it again: the frame vanished and only the options could bring  
    it back.  
    The prefilter is now ns.VisMouseoverWired, asking the same question of the  
    override as well. It stays STATIC on purpose -- a live verdict here would write  
    alpha on every mouse leave of every frame, which is exactly why the prefilter  
    exists -- and it lives on ns because this chunk sits near the Lua 5.1 local cap.  
    Action Bars are deliberately left as they are: a Mouseover override there simply  
    behaves like Always (the resting-alpha path is itself gated on the stored  
    mouseoverEnabled, so nothing hides), and teaching that module would mean  
    touching around thirty read sites across its fade, mouse-enable, click-through  
    and keybind machinery -- a feature of its own, not a footnote to this one.  
- Fix(Visibility): removing an override took every other group's with it  
    Clearing an override cleared it for everyone. One capture entry is SHARED by  
    every group that customized the same slot -- AutoCapture looks an entry up by  
    slot, module, page, element and section, never by group, and only adds a  
    per-group value map to it -- and the clear walked `entry.values` wholesale.  
    Removing the override in one group therefore deleted the value every other group  
    held for the same setting, and left the shared default gone with it.  
    Only the maps the edited session owns are cleared now: the group's own map for a  
    conditional session, every member spec's map for a spec group, which is the same  
    set HarvestGroup banks into. The recorded default and the entry itself survive  
    for as long as any other owner still holds a value for the key, and the live  
    value is written back either way, because the session has to show the value it  
    just gave up.  
    The offline test grew the case that would have caught this: one entry with two  
    owners, where clearing in one session must leave the other's value, the default  
    and the entry intact. 21/21.  
- Fix(Visibility): three gaps found reviewing the override feature  
    The Pet Bar ignored an override. Its branch in BuildVisibilityString returns  
    before the constant the override compiles to, so the bar kept following the  
    shared selection. It now takes the same route: Never hides outright, the other  
    two leave the pet wrapper as the only condition.  
    An APPLIED override left the row unmarked. The gold walk decides from the fkeys  
    a slot's getter READS under the trace proxies, and the capture config only ever  
    read the legacy scalar, so a row overridden through the new key never showed as  
    overridden. It reads both keys now, unconditionally, and reports the override as  
    the effective value.  
    A stranded override marker had no way out. Two paths leave one behind: the  
    management list's Remove drops the entry but deliberately keeps live values, and  
    a profile exported while an override applied carries the key into every import.  
    Nothing owns the key afterwards, so the element was stuck on a value no UI could  
    reach. A shared edit outside a session clears it now; a real applied override  
    just writes it back on its next apply.  
    Checked and found sound, so left alone: VisFullCopy and VisFullEquals do not  
    carry the key between elements (an override belongs to one element), the  
    blacklist keeps it capturable, and every Lua consumer reaches it through  
    EvalVisibilityExtended.  
- Share one health-percent body between the two text pieces  
    perhpnosign was a copy of perhp plus the exists/connected/dead guards, so  
    the trim dispatch landed in both. One body now, matching the rule the  
    piece table states just above it. The options preview reads the same  
    curve and config through Evaluate rather than repeating the scale, and  
    MakePctTrim drops its C\_CurveUtil guard to match how the file builds its  
    other curves.  
- Unit Frames: option to hide trailing zeros on health percent text  
    Adds "Hide Trailing Zeros" to the Health Text Decimals cog, so an  
    enabled health decimal renders 100% instead of 100.0% while 99.5%  
    keeps its decimal. Global, default off, percent only.  
    UnitHealthPercent returns a secret value, so the trailing zero cannot  
    be trimmed with Lua string ops; AbbreviateNumbers drops a zero fraction  
    on its own and accepts secrets. It truncates rather than rounds though,  
    so a fractional significandDivisor reads low (0.1 renders 33.3 as  
    "33.2"). The scaling is done by the curve instead: the percent arrives  
    as whole tenths (or hundredths for the boss 2-decimal option) and the  
    config divides by integers only. The curve's +0.5 offset makes the  
    truncation land on the value "%.1f" would have rounded to, so the  
    toggle changes the trailing zero and never a digit.  
- Bank: expansion nesting, category grouping and a category sidebar  
    Adds a Bank options page with five toggles, all off by default: Nest by  
    Expansion and Group by Category for the consolidated OneBank/OneWarbank  
    grids, a Category Sidebar that browses both banks together, an option to  
    drop the per-tab sidebar entries once it is doing the navigating, and one  
    to hide the trailing empty slots while grouped.  
    Grouping reuses the bags CategoryManager, so category order, renames and  
    disabled categories carry over. Gear splits by equipment slot, Professions  
    and Trade Goods by subclass. Classification runs once per refresh and is  
    shared by the sidebar counts and the grid.  
- Blizz Skin options: refresh the page when Reskin Popups and Menus is toggled  
    Its border cog and colour swatches gray off reskinPopupsMenus, but the widget  
    refresh list only runs on page show, so they stayed lit until you navigated  
    away and back.  
- Blizzard Skin: configurable style for the queue accept countdown  
    The LFG accept countdown painted its text two hardcoded ways depending on  
    whether the queue popup reskin was on. Text colour, text size, bar height and  
    text offset are now player-owned and apply in both styles.  
    Defaults live in EllesmereUI.QUEUE\_TIMER so the skin and the options sliders  
    read one source, and reproduce the current EUI-style look exactly.  
    The bar is raised above the dialog because its parent deliberately sits a level  
    below it, which clipped a raised countdown against the dialog art.  
- Widgets: dim the label on disabled cog colourpicker rows  
    Every other BuildCogPopup row type -- slider, toggle, dropdown, segmented,  
    input, multiswatch -- dims label and control together under a full-width row  
    overlay. colorpicker was the only one that didn't: it faded the swatch and  
    left the label at full brightness, since its label frame is an invisible  
    mouse-blocker with no texture.  
    The label now tracks the disabled state by alpha, at build time and in  
    pf.\_refresh. Alpha rather than the row overlay the other types use, because  
    that overlay would sit on top of the swatch and tint the colour being read.  
- Nameplates: configurable name and title styling for friendly NPC name-only plates  
    Name-only friendly NPC plates drew the name and the <Title> line under it in  
    one fixed green, with the title reusing the name's RGB at 0.7 alpha. Neither  
    was reachable from the options panel.  
    Adds Title Size, Name Color and Title Color to the Friendly NPC Settings cog,  
    alongside the existing Name Size. Defaults reproduce the current appearance  
    exactly, so no profile changes visually.  
    Extracts ApplyOverlayStyle() from ShowNPCOverlay and shares it with a new  
    ns.RefreshNPCOverlayStyle(), so the style rows re-paint live overlays instead  
    of rebuilding them through RefreshAllNPCOverlays, which re-reads every unit's  
    tooltip for the title text. The titles toggle still rebuilds, since it needs  
    that text.  
    Every row in this cog styles the name-only overlay, so the mode gate moves to  
    the cog button (matching the Distance cog beside it) instead of being repeated  
    per row. The inline full-plate swatch switches to the canonical  
    friendlyPlateOff() helper, which adds the showFriendlyPlayers term its  
    hand-rolled check was missing.  
- Fix(Visibility): an applied override leaked into the shared row  
    The override branch in GetChecked went in without its session gate, so it also  
    answered while an override was merely APPLIED. The Always row then reported the  
    override while the group row below reported the shared value, and the summary  
    joined them into "Always or Solo (-1)" -- a selection that exists nowhere. It  
    flipped back and forth with every click, because each click sets or clears the  
    live key.  
    The two halves are separated now. The menu rows show the SHARED value outside a  
    session, because that is what they edit; a click there must not act on a row  
    that is checked for a reason the click cannot change. Only while an override is  
    being edited do the three exclusive rows show what it holds.  
    The summary carries the override instead, live in both cases: while it holds a  
    value the row reads that value and nothing else, so the label always states what  
    actually applies to the element even when the rows underneath show the shared  
    selection they edit.  
    Ruled out along the way, with a test rather than by reading:  
    SpecOverrides\_ClearStoreKey resolves and clears correctly for both entry shapes  
    (AutoCapture's slot-attributed one and the exit sweep's fkey-only one), leaves  
    other keys of the same table alone and does not match another element's entry.  
    That test is offline and slices the two functions out of the real source.  
- Fix(Visibility): the summary claimed an override that was never set  
    Excluding the sealed rows from the summary left nothing to show while a session  
    held no override, so the label fell back to its empty text -- "Always" -- and  
    read as an override of Always next to an unchecked Always row.  
    The split is now explicit. While a session is live the summary is the override's  
    own row if one is held, and the plain shared summary if none is, which is what  
    still applies to the element. Only a held override replaces the text.  
- Fix(Visibility): the summary mixed the override with the shared value  
    With an override of Always the closed row read "Always or Solo (-1)": the  
    summary walks every item, so the three exclusive rows answered from the override  
    while the sealed rows below still answered from the shared value, and the two  
    were joined into one selection that exists nowhere.  
    Sealed rows are now left out of the summary entirely. They belong to the shared  
    value, not to what the override holds, so during a session the row reads  
    "Always" and nothing else.  
    Note for the same symptom seen after leaving a session: the label is rebuilt by  
    the widget refresh, and ExitGroupEdit forces a page rebuild, so a stale string  
    there means the refresh did not reach the row -- worth a second look if it  
    survives a reload.  
- Feat(Visibility): an override replaces the whole setting, and toggles off  
    An override on Visibility merged with the shared value instead of replacing it.  
    With "Show while Solo" and "Hide with Target" set normally, an override of  
    Always still followed those, because only the legacy scalar was captured while  
    the option lanes stayed live underneath. Always now means always.  
    A new scalar carries it: visibilityOverride, absent in every normal profile and  
    written only by an override session. While it holds a value it settles  
    visibility alone -- the legacy scalar, the mode set, the match mode and every  
    option lane are ignored. It is a plain capturable key on purpose, so the value  
    system stores and restores it like any other setting, with no new layer.  
    It reaches the Lua consumers through the one path they share:  
    EvalVisibilityExtended answers from it first, VisWantsMouseover and  
    VisDependsOnCombat follow it, ActiveModes reports no stored set, and  
    CheckVisibilityOptions, CheckVisibilityOptionsNonMacro, VisOptionHideVeto and  
    TallyVisibilityOptionAxes report nothing constrained. The three driver-building  
    consumers compile a constant from it instead of the shared selection.  
    Picking the state an override already holds removes it again, through  
    EllesmereUI.SpecOverrides\_ClearStoreKey: it drops what the session captured for  
    that ONE key of that ONE settings table and writes the recorded value back.  
    Attribution is by table identity rather than by slot label, because AutoCapture  
    attributes an entry by slot while the exit sweep mints entries from the fkey  
    alone with no slot fields at all, and only identity matches both shapes.  
    The session writes exactly one key and nothing else. An earlier attempt also  
    wrote the legacy scalar through applyScalarFn to keep the modules' own  
    mechanisms in step, which put the shared value at risk on every path that failed  
    to restore it; the drivers now read the override directly instead, so the  
    profile underneath is never touched.  
    That discipline also covers the reads: the row takes the override value from the  
    store Sel() has already resolved rather than calling opts.getStore() again. A  
    getter is not guaranteed free -- CDM's GetTrackedBuffBars CREATES its table on  
    read -- and inside a session that write is a diff the exit sweep mints into the  
    group as an override nobody asked for.  
- Cooldown Manager: resolve an Apply to Bar value once instead of per sweep  
    A payload-carrying apply writer (Active State custom colour, Threshold Seconds,  
    Threshold Color) reads the source spell's own values back out of its settings  
    entry, and RunBarApply re-ran that writer for the tier and again for every  
    preset and hosted-buff stamp. The sweeps in between clear exactly the keys those  
    writers read, so the result depended on what had already been swept:  
    - The member wipe clears the source entry before the stamps run. It usually goes  
      unnoticed, since the wiped read falls through the chain to the tier the apply  
      just wrote, but the entry is only re-chained at the end of RunBarApply, so an  
      apply that CREATES the tier leaves the read pointing at the old head. Every  
      preset or custom-injected icon on the bar is then stamped with the writer's  
      hardcoded defaults while the regular icons get the picked value.  
    - For All Specs the sweep runs per profile in undefined pairs() order, so  
      whether the stamps see a live source at all depends on where the active spec  
      lands in that order.  
    - In the this-spec branch the All Specs unapply runs first and can clear the  
      source preset's own entry before the tier write reads it.  
    Resolve the value once at the top, into a scratch table, and have the tier write  
    and both stamps copy from it. This is the same simulate-once shape  
    CountApplyOverwrites already uses, and it drops the order dependence entirely.  
- Feat(Visibility): seal the locked rows as one block with a caption  
    Follow-up on how an override session presents the checklist, from testing.  
    The per-row marking is gone. The excluded rows are sealed off as ONE block now,  
    from the section header that introduces them down to the last row: a 1px red  
    border, a faint red wash and a click blocker, which is the treatment SetSlotMark  
    already gives an override-red slot in the panel, so the checklist speaks the  
    language the rest of the override UI does. A "Not overridable" caption sits on  
    the block's top edge. It reads on the header's divider line, which crosses the  
    glyphs at that height, so a plate in the menu's own background colour cuts the  
    line for the width of the caption -- the seal sits at a higher frame level than  
    the header, so anything it draws covers that line.  
    The block stops 9px short of the row's right edge. The 4px scrollbar track hangs  
    off the SCROLL FRAME rather than the content, so a full-width seal ran  
    underneath it and the bar cut through the border.  
    The tooltip was wrong, not just unclear: it still claimed only Never and Always  
    could be overridden, from before Mouseover was freed. It now names all three,  
    says the rest is shared, and says when it can be changed instead -- without  
    talking about stores or captures.  
    \_keys.txt regenerated for the one new string.  
- Fix(SpecOverrides): the Visibility row could only be half overridden  
    Reported from a conditional override group: a condition already set could not be  
    unchecked, Show and Hide could end up checked at once, Mouseover did nothing at  
    all, and deleting the group left some of its checkmarks behind while reverting  
    others.  
    One root cause. The Visibility row is a COMPOUND setting: a legacy scalar, the  
    mode set (visibilityModes, a table), the match mode and the option lanes, which  
    only mean anything while they agree with each other, and which the checklist  
    rewrites as a fresh table on every click. The value system is a per-leaf differ  
    that stores scalars: HarvestMap refuses to bank a table at all, and an apply  
    skips a removal whose key has a registered default (HasRegisteredDefault, which  
    exists because honoring such a removal once nilled a key module code reads raw  
    and crashed SetFont). A capture could therefore only ever hold PART of that  
    state. Unchecking a lane writes nil, a REMOVAL: for a lane the module registers  
    a default for (Quest Tracker registers five of the sixteen, and every module  
    differs) the removal was skipped and the checkmark came back, while an  
    unregistered lane cleared normally. Mouseover needs scalar and set to agree, and  
    the engine discards a set whose representative does not match the scalar, so a  
    partial apply silently disabled the whole selection.  
    Excluded from the value system rather than half-fixed: making it work needs an  
    atomic capture unit, which is what the Buff and Debuff Manager subtrees already  
    have as a layer fork of their own. Excluded is the COMPOUND half only -- the  
    mode set, the match mode and the option lanes -- while the legacy scalar and the  
    companions the row writes alongside it stay capturable, so Never, Always,  
    Mouseover and a single legacy mode keep overriding exactly as they did before  
    the unified row existed. Those companions ARE the legacy mechanism (Unit Frames  
    hides a "never" frame through showInRaid/showInParty/showSolo and enabledFrames,  
    Action Bars through mouseoverEnabled and the combat flags), so blocking them  
    would have broken the very override worth keeping. The lanes come from the  
    shared EllesmereUI.VIS\_OPT\_KEYS, merged in lazily because this file can load  
    first, so a lane added later cannot silently become capturable again; the  
    compound keys merge eagerly and hold even without that list.  
    The checklist also has to SAY so, which needed two more things. It never called  
    EllesmereUI.\_NotifySettingWrite, the primary capture path every other widget's  
    setter uses, leaving it on the polling fallback alone -- and that attributes by  
    mouse focus, while the menu is a UIParent child with no popup marker, so  
    SampleAttribution took it for "world / other UI" and CLEARED the attribution.  
    AutoCapture then returned at its first guard: no capture at the moment of the  
    click, no answer, and whatever the watcher picked up later landed on whichever  
    slot the mouse happened to rest on within three seconds. That race is also why  
    the original symptoms were so erratic. The checklist now notifies, behind an  
    opt-in opts.notifyWrites that only this row sets: BuildVisOptsCBDropdown has 62  
    call sites across 22 files, and moving them all onto the primary path is very  
    likely right but is not this change.  
    On top of that the excluded rows are now locked while a session is live instead  
    of accepting a click that gets dropped. Every row except the three exclusive  
    states refuses the click, greys its label and explains itself on hover, on the  
    row and on the Hide box alike. The two section headers ("Match Mode" and  
    "Show / Hide") carry the override system's red on caption, divider and right  
    caption, so the boundary is visible at a glance: everything below them is  
    locked, everything above is not. Mechanically this rides the existing per-item  
    lock through one shared RowLocked predicate that the click guards and the  
    visuals both use, so the three sites can no longer drift apart. extraItems stay  
    unlocked on purpose: those are plain module settings that merely sit in this  
    menu and remain perfectly overridable.  
    Two refresher fixes this depends on. The rows are parented to the menu's SCROLL  
    CHILD, so the menu:GetChildren() walk in RefreshAll never reached them and  
    refreshed nothing; the builder now publishes its row list on the menu and both  
    refreshers walk that. And a static menu is built once and reused, so ShowMenu  
    refreshes checked state and locks on every open, or a session starting between  
    two opens would show stale rows.  
- Cooldown Manager: keep the picked Active State colour on Apply to This Spell  
    The Active State apply writer cleared activeSwipeR/G/B/A up front so a stale  
    colour from an earlier Custom apply could not linger in a bar tier, then read  
    the source colour back for the Custom branch. "Apply to This Spell" passes the  
    spell's own settings table as the write target, so the clear wiped the colour it  
    was about to read and the branch fell through to the #FFC660/70% defaults --  
    picking a colour (or dropping its opacity to 0 to hide the overlay) and applying  
    it to the spell reset it on the next open. Snapshot the source values before the  
    clear.  
    The preset/custom icon copy of the writer had the same aliasing: a bar apply  
    stamps every preset member's customActiveStates entry, including the one the  
    writer reads from, so members stamped after it got the defaults.  
- Cooldown Manager: arm the range check on the live override  
    The repaint-driven re-poll only saw the range boundaries the BASE spell crosses,  
    because Blizzard arms its check on the base and nothing dispatches for the  
    override. A melee base with a 15yd override therefore painted correctly at the  
    swap and then went stale on the walk out, which is exactly the reported case.  
    The override id is now armed in its own right and SPELL\_RANGE\_CHECK\_UPDATE drives  
    the repaint, so the tint follows the player for whichever spell is actually live.  
    The registration is per spell rather than per caller, so an id Blizzard already  
    holds for an icon of its own is left alone in both directions, re-checked at  
    disarm time in case it became theirs while ours was armed. Everything armed is  
    dropped on a spec change, and the handler sits early in the event chain since it  
    falls through for the base-spell dispatches, which are nearly all of them.  
- Merge remote-tracking branch 'upstream/main' into fix/cdm-range-override-taint  
- Cooldown Manager: re-poll the override's range on each repaint  
    The first pass stored the answer from the swap and replayed it on every Blizzard  
    repaint, which pinned the tint: with the override still up, walking back into  
    range repainted white and the hook immediately put the red back, and nothing  
    cleared it until the next override event, since nothing here listens for range  
    updates.  
    The hook now re-polls the live override id instead of replaying a stored boolean.  
    It rides Blizzard's own repaints, including the one their range event drives, so  
    the tint follows the player without a second event of our own; an unknown or  
    secret answer leaves their colour alone. The stored id is cleared the moment no  
    override is live, handing the icon back to Blizzard's check, which is correct for  
    the base spell from that point.  
- Merge remote-tracking branch 'upstream/main' into fix/cdm-range-override-taint  
- Cooldown Manager: repaint the override range tint on our own texture  
    The reverted version wrote spellOutOfRange on the viewer item frame and called  
    RefreshIconColor, which is what the taint law above it now forbids: the written  
    key is tainted, Blizzard's own RefreshIconColor reads it mid-refresh, and the  
    taint follows the chain into the aura pass, where a secret expirationTime  
    comparison throws once auras are secret.  
    This keeps the fix and drops both offences. The out-of-range answer lives on the  
    side table, the tint is written to the icon texture we already hold and re-asserts  
    from a per-frame SetVertexColor post-hook so a Blizzard repaint cannot stomp it,  
    and coming back into range repaints once from Blizzard's own colour constants  
    rather than calling their resolver. A secret usability answer leaves the icon  
    alone. Nothing writes a field on a Blizzard frame and nothing calls its paint  
    methods, so the refresh chain stays clean.  
- Fix(Visibility): hide gates dropped by a passing Lua-only Show lane  
    Three defects from the review of this branch.  
    BuildAnyMatchTail returned early on a passing Lua-only SHOW lane  
    ("if luaP > 0 then return Finish(wrappedShow, luaC, 0) end"), which skips  
    BuildVisibilityDriverStringAny -- the only place the leading hide gates are  
    emitted. "Only Show in Instances" plus any macro-expressible Hide lane therefore  
    compiled to a bare "show" inside an instance, the exact inversion this branch  
    exists to remove. The pass now sets a flag and falls through to the forceShow  
    path, which already means "show outright, gates intact". The wrappedShow local  
    it left behind is gone.  
    ApplyCombatVisibility and RefreshRuntimeVisibility wrote a literal "hide"  
    whenever CheckVisibilityOptionsNonMacro returned truthy. That helper used to  
    return false for Any stores, so both sites were inert there; the Any branch added  
    in the previous commit made them live, replacing a self-updating driver string  
    with a dead constant and discarding both the leading gates and the  
    "[nocombat] hide;" escape hatch. Both now carry the same visibilityMatch guard  
    ShouldHideNonMacro already had. The "any" branch in that helper consequently has  
    no live caller left; it stays because it is the correct answer for the helper's  
    own contract, and the code says so.  
    BuildVisModeConjuncts folded hide\_in\_combat into c2 and hide\_out\_of\_combat into  
    c1, so both checked at once looked like a saturated axis and emitted no term at  
    all, while VisModeHideVeto hides in every state. The contradiction is caught  
    before the fold now and compiles to an unconditional leading "hide; ". The fold  
    also gained the "own Show lane wins" rule the veto uses, which removes a second  
    divergence for a row carrying both of its own lanes.  
    Plus a nit: hideLaneTooltip is a plain string instead of a closure returning a  
    constant.  
    Offline harness covers 1 and 3 (190/190); the exhaustive legacy-invariance dump  
    still reports zero differences.  
- Fix(Visibility): Hide lanes on the mode rows were not vetoes  
    The previous commit settled the rule for the option rows (Instances, Mounted,  
    Target, Resting, ...): a checked Hide lane vetoes in every match mode. The mode  
    rows were left out, so one checklist carried two rules -- under Match Any,  
    "Hide: In Combat" read as the disjunct "show while out of combat" and lost to  
    any other passing Show lane, while "Hide: Mounted" always hid.  
    The group rows had a second defect on top: their Hide lane had no stored key at  
    all, it was derived sugar over the three Show booleans. The derivation only  
    recognised the 2-of-3 shape, so checking a second Show lane made the Hide  
    checkmark disappear on its own. That is the reported bug.  
    Every row's Hide lane is a veto now, mode rows included, and each one has a key  
    of its own. So that nothing expressible before becomes inexpressible, the  
    inverse conditions get Show rows of their own: "Out of Combat" and "Not  
    Skyriding (Airborne)" carry the existing out\_of\_combat / show\_not\_dragonriding  
    keys as their SHOW lane, which is also why those legacy stores need no  
    migration -- the checkmark just renders on the new row.  
    - EllesmereUI.VIS\_MODE\_AXES mirrors VIS\_OPT\_AXES: show key, hide key, macro  
      token, Lua probe, luaOnly/combatFlip/group flags. Seven new hide keys live  
      only inside visibilityModes, never as a legacy scalar, so no scalar reader in  
      any module can see one.  
    - EllesmereUI.VisModeHideVeto is the mirror of VisOptionHideVeto, called from  
      EvalAnyMatch and from EvalVisibilityModes. TallyVisibilityModeAxes is  
      untouched: under All a veto is exactly the AND-conjunct of the negated  
      condition it already computes, which is what keeps Match All unchanged.  
    - A hide lane has no representative scalar, so SetVisibilitySelection writes  
      "always" plus the set and ActiveModes accepts that pair. VisDependsOnCombat  
      learned the two combat hide lanes, or a protected consumer would miss the  
      combat edge and try a Show/Hide inside lockdown. VisCopySelection strips the  
      group hide lanes for noGroupModes targets.  
    - Secure drivers: the combat and dragon hide lanes fold into  
      BuildVisModeConjuncts (no new grammar), the group ones become leading gates  
      through the new BuildVisModeHideGates in both compilers, and the Any compiler  
      counts them so a hide-only selection still registers a live driver instead of  
      a constant. hide\_not\_dragonriding is the one lane with no positive bracket  
      form, so BuildAnyMatchTail resolves it in Lua and, being combatFlip, it rides  
      the "[nocombat] hide;" escape hatch.  
    - UI: two new rows, explicit hide keys on every mode and group row, the 2-of-3  
      sugar deleted, one tooltip rule for all rows. A selection of nothing but hide  
      lanes reads as Always, and Always no longer clears them, matching how the  
      option Hide lanes already behaved. A legacy 2-of-3 group selection is  
      normalised to the hide key while the store is Match All, where the two  
      encodings are equivalent; Match Any stores are left as stored.  
    - EUI\_UnitFrames\_Options: GroupAxisPasses learned the group hide lanes, or the  
      legacy showInRaid/showInParty/showSolo trio that gates ToggleFrame would stay  
      at "unconstrained = true".  
    Legacy invariance was machine-checked, not argued: every subset of the seven  
    condition keys plus mouseover, in both match modes, over twelve world states,  
    dumping the stored shape, the verdict and both compiled driver strings against  
    the previous engine. Zero differences.  
- Fix(Visibility): Hide lanes ignored under the Any match  
    Under Match Any every checked lane was tallied as a disjunct, so a Hide lane  
    "passed" whenever its condition was FALSE -- true nearly all the time. One  
    passing disjunct settles the verdict, so a single Hide checkmark out-voted every  
    Show condition and the element stayed permanently visible. Resting was never  
    special: a tester standing in a city is resting, so its lane was the only one  
    whose disjunct failed there.  
    Match Mode now governs how the SHOW side combines; a checked Hide lane on an  
    option row vetoes in every match mode. Mode rows keep their symmetric OR  
    semantics, where the Hide lane is just the opposite condition of the same axis.  
    - EllesmereUI.VisOptionHideVeto walks VIS\_OPT\_AXES for the veto (second return:  
      the axis is combatFlip, so a driver caller bakes a combat escape hatch).  
    - CheckVisibilityOptions / CheckVisibilityOptionsNonMacro evaluate the hide  
      lanes under Any instead of bailing out, which restores the veto for every Lua  
      consumer at once; TallyVisibilityOptionAxes counts show lanes only.  
    - EvalAnyMatch vetoes before tallying, mouseover included: a hover must not  
      reveal what a Hide lane hid.  
    - Secure drivers: BuildVisOptHideGates emits [mounted]/[exists]/[harm] hide as  
      leading gates, the Any compiler drops its negated disjuncts, and  
      BuildAnyMatchTail resolves the Lua-only hide vetoes at build time, wrapping a  
      combatFlip verdict in "[nocombat] hide;" so it cannot freeze as a dead hide.  
      AnyDriverLaneFixups gained forceHide and drops a wrongly-firing gate.  
    - Match Any and Hide-lane tooltips state the new rule.  
    Match All is unchanged by construction.  
