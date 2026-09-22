# EllesmereUI

## [v9.2.2](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.2.2) (2026-09-21)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.2.1...v9.2.2) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.2.2  
- Merge pull request #2158 from dfrisone/fix/forever-nameplate-class-power  
    fix(nameplates): make the class resource work on Forever  
- chore(nameplates): check EllesmereUI.IS\_FOREVER, matching the suite  
- fix(nameplates): match the options preview to the Forever resource set  
    The preview keeps its own class map, so on Forever a paladin or warlock still  
    saw a filled pip preview and a live Size slider for a resource the watcher now  
    refuses to enable.  
- fix(nameplates): read Forever combo points from the target  
    Same fault as the unit frame pips: UnitPower still reports the previous target's  
    count when PLAYER\_TARGET\_CHANGED fires, so the plate kept the old number until  
    the next point was built. Traced on 1.60.1: up=3 while gcp=0 on the swap.  
    GetComboPoints is correct at that instant and is what Blizzard's own classic  
    ComboFrame reads.  
- fix(nameplates): raise the Forever class resource default size  
    The 8x3 base pip at scale 1 is too small to read on that client, where this is  
    the target-side display rather than a second one alongside the unit frame. The  
    Size slider still overrides it.  
- fix(nameplates): make the class resource work on Forever  
    The nameplate class resource carried the same two Forever faults the unit frame  
    one did.  
    Combo points come back secret there, and isSecret was hardcoded to Vengeance  
    soul fragments, the only resource that is secret on retail, so the pip fill  
    compared against a secret value and raised. Classify the value instead.  
    The class map is retail-shaped: its spec-keyed entries never resolve without  
    specializations, so druids got nothing, and its flat entries name resources  
    vanilla content does not have, so paladins and warlocks drew pips that can never  
    fill. Resolve rogue and druid to combo points there and nothing else.  
    Druid combo points are cat-only for every druid on that client, there being no  
    specs to tell Feral from Resto, and the form check now reads Blizzard's own  
    DRUID\_CAT\_FORM rather than a bare 1.  
- Merge pull request #2152 from svart2521/choose-your-roles-window-not-skinned  
    Fix: Choose your Roles window not skinned  
- Merge pull request #2151 from dfrisone/fix/forever-combo-frame-orphan  
    fix(unitframes): show combo points on Forever  
- Merge pull request #2150 from thoriphes/feat/swing-timer-resource-bar  
    resourcebars: Swing Timer as a resource bar (replaces the QoL timer)  
- chore(locales): regenerate \_keys.txt after merging upstream  
- Merge remote-tracking branch 'upstream/main' into fix/forever-combo-frame-orphan  
- fix(unitframes): read Forever combo points from the target  
    Combo points belong to the target on Forever, and UnitPower still reports the  
    previous target's count at the moment PLAYER\_TARGET\_CHANGED fires. Traced on  
    1.60.1 across a target swap:  
        PLAYER\_TARGET\_CHANGED up=3 gcp=0 token=nil  
    No power event follows, because the player's own power did not change, so the  
    refresh added in the previous commit re-read the stale value and the row held  
    the old count until the next point was built.  
    GetComboPoints is correct at that instant and is what Blizzard's own classic  
    ComboFrame reads.  
- Merge pull request #2149 from thoriphes/feat/unlock-anchor-params  
    unlock: edit an anchor's points and offsets from the cog menu  
- Merge pull request #2148 from thoriphes/fix/cdm-picker-empty-list  
    Cooldown Manager: open the CD/utility spell picker on an empty Blizzard list  
- Merge pull request #2146 from svart2521/boss-unit-frames-not-showing-correct-class-colouring  
    Fix: Boss Frame target name not showing class color on live  
- Merge pull request #2145 from dfrisone/fix/forever-editmode-mainactionbar-taint  
    Forever: stop the degraded layout reparenting MainActionBar  
- Merge pull request #2144 from FrancisS/main  
    Added new split compare option for fastest run.  
- Merge pull request #2142 from dfrisone/fix/forever-mainbar-keybind-page  
    Forever: click-route Action Bar 1 keys while paging is frozen  
- Merge pull request #2141 from svart2521/received-lua-error  
    Fix: Secret-value taint errors in social tooltip and damage breakdown  
- Merge pull request #2139 from Thunderz96/fix/forever-power-type  
    fix(resourcebars): use the live power type on WoW Forever  
- Merge pull request #2138 from LoChinAn/locale-zhtw-batch-260920  
    zhTW: translate 139 new keys for WoW Forever, Blizzard Style and Run Summary (supersedes #2047)  
- Merge pull request #2137 from Crazyyoungs/main  
    [koKR] Add Korean localization for new UI features  
- Merge pull request #2135 from denis-makula/fix/unitframes-health-text-centering  
    fix(unitframes): keep health text centered with clipping  
- Fix: Choose your Roles window not skinned  
    Bug:  
    Issue: SkinApplicationDialog (LFGListApplicationDialog, the "Choose your Roles" sign-up dialog) gated itself on "not EllesmereUIDB.reskinQueuePopup" -- true (skip skinning) whenever the setting is nil, i.e. on any profile where the user never touched that checkbox. But the options panel itself, and every other reskinQueuePopup-gated feature except this one, read the same setting the opposite way (only false disables it, nil/true means enabled) -- so the checkbox shows checked by default while this dialog silently never gets skinned.  
    Fix: Changed the gate to match the setting's actual default-on behavior, consistent with the options panel and the other queue-popup skinning code.  
- fix(unitframes): keep Forever combo points on the target when ours are off  
    Combo points belong to the target on Forever, not the player, so hiding  
    Blizzard's ComboFrame outright took away a placement the client already offers  
    through its comboPointLocation cvar.  
    Suppress it only while our own class resource is drawing, which is what would  
    otherwise double up; with the resource set to None, ComboFrame stays the display  
    and is re-anchored onto the EllesmereUI target frame rather than left stranded  
    at a dead anchor.  
    Also refresh the pips on PLAYER\_TARGET\_CHANGED. A target swap changes the count  
    with no power event behind it, so the row could hold a stale number -- Blizzard's  
    own ComboFrame registers the same event for the same reason.  
- fix(unitframes): show combo points on Forever  
    Combo points on WoW Forever rendered as Blizzard's classic ComboFrame floating  
    in open space. That frame is parented to UIParent and only anchored to  
    TargetFrame, so replacing the target frame strands the art at a dead anchor  
    rather than hiding it, and none of the BLIZZARD\_CP\_FRAMES globals the Blizzard  
    class power style adopts exist on that client, so nothing ever took it over.  
    Suppress ComboFrame when Blizzard's target frame is not the live one, and give  
    Forever a class resource that works instead:  
    - Classify the pip value rather than the resource kind. Only Vengeance soul  
      fragments were treated as secret, so combo points, which come back secret on  
      Forever, raised on the `i <= cur` compare.  
    - Add FOREVER\_CLASS\_POWER. The spec-keyed entries never resolve without  
      specializations, which left druids with nothing, and the flat entries name  
      resources vanilla content does not have, which drew paladins and warlocks an  
      empty five-pip row and shrank the health bar to fit it.  
    - Gate druid pips on cat form for every druid there, since there are no specs to  
      tell Guardian and Resto apart, and read DRUID\_CAT\_FORM instead of a literal.  
    - Grey out the Blizzard style on Forever and migrate profiles already holding  
      it, along with a one-time move off the "none" default, which nobody chose.  
    - Seed the class resource in the Forever base layout.  
- Fix: Boss Frame target name not showing class color on live  
    Bug:  
    Issue: Two separate bugs, both regressions from the merged "Name > Target" fix. (1) The v9.2 release squash added an "and not issecretvalue(hex)" guard around ColorMixin:GenerateHexColor's result in TagFns.tgtcol -- GenerateHexColor's hex string can itself be secret, so this guard is what silently broke the class color, rejecting a value that was actually fine to use and falling back to plain reaction color (e.g. friendly green) instead of the target's real class color. Confirmed directly via a SavedVariables capture (genHexOk=true, hexType=string, hexSecret=true) and reproduced/isolated by reinstating the guard on its own. (2) Separately, the "text" painter channel's event list never included UNIT\_TARGET, so a unit's own target changing (a boss getting taunted) triggered no repaint at all -- "Name > Target" content only updated opportunistically whenever an unrelated event (a health/power tick) happened to fire around the same time, leaving it blank until a /reload forced a full repaint.  
    Fix: Removed the issecretvalue(hex) guard -- a secret hex string still renders correctly through SetFormattedText's arg lane, the same safe channel secret names already use elsewhere in this file, so it never needed to be a plain string to begin with. Added UNIT\_TARGET to the text channel's event list so any unit's own target change repaints immediately (applies to all "Name > Target" users: player/target/focus/boss, not just boss frames).  
- Always save best run splits so that data is available on toggle.  
- fix(forever): stop the degraded layout reparenting MainActionBar  
    HideBlizzardBars spares MainActionBar deliberately: it is Edit Mode  
    system 0 index 1, it has to stay in Blizzard's parent chain for pet  
    battle MicroMenu restoration, and an insecure write to it taints the  
    frame. It is hidden with alpha and an OnShow re-hide instead.  
    \_DegradedLayoutApply, the no-snippet path, reparents every entry in  
    STOCK\_BAR\_DISPOSAL, and MainActionBar is the first of them. That taints  
    it on Forever, where the path is the only one that runs, so Blizzard's  
    InitSystemAnchors is blocked on SetPointBase every reload and every  
    /editmode:  
      AddOn 'EllesmereUIActionBars' tried to call the protected function  
      'MainActionBar:SetPointBase()'  
      EditModeManager.lua:1461 in secureexecuterange  
      EditModeManager.lua:1465 InitSystemAnchors  
      EditModeManager.lua:1009 UpdateLayoutInfo  
    Retail never sees it: there the snippet path does the same reparent  
    inside the restricted environment, untainted.  
    Skip it here. The other stock bars keep reparenting, which they already  
    do insecurely in HideBlizzardBars on every client without complaint.  
- fix(forever): click-route Action Bar 1 keys while paging is frozen  
    Forever lacks loadstring\_untainted, so SecureSnippetsOK is false and the  
    MainBar page state driver is never registered. Our bar stays on page 1  
    for the session. The engine does not: Forever runs vanilla content, so a  
    warrior has stances, and a stance pages bar 1 through bonusbar.  
    ACTIONBUTTONn resolves through MainActionBar's actionpage, so the keys  
    land on slots 73-84 while the icons, mouse clicks and drag targets use  
    slots 1-12. Measured on a Forever warrior in Battle Stance: euislot 1  
    holding Charge, blizzslot 73. Rearranging the bar makes it obvious, the  
    keys keep firing the stance page's untouched default layout: key 2 casts  
    the Heroic Strike that used to be on button 2, key 3 hits an empty slot  
    and does nothing.  
    This is the same show-one/fire-another split the auto-paging opt-outs  
    just above already handle, so take the same exit. The click route reads  
    our own static action attribute, so key, icon, click and drag agree.  
    Scoped to MainBar: bonusbar does not reach bars 2 to 8, and their native  
    keys resolve correctly today.  
    Cost: press-and-hold repeat casting on Action Bar 1, on clients with no  
    snippet compiler. Nothing changes where SNIPPETS\_OK is true.  
- Not necessary to disable.  
- Merge branch 'main' of https://github.com/FrancisS/EllesmereUI  
- Added setting and functionality to display splits from fastest m+ run instead of sum of best splits.  
- Fix: Secret-value taint errors in social tooltip and damage breakdown  
    Bug:  
    Issue: Two repeating Lua errors from secret-value taint: format("%s", ...) rejected a cross-faction BNet friend's secret characterName in the social tooltip, and GetSpellTexture rejected a secret spellID for non-group combat participants in the damage meter breakdown -- both unlike sibling calls in the same files that already tolerate secret arguments.  
    Fix: Nil out a display-only copy of characterName before the tooltip's format() call (BuildFullName still gets the real value), and skip the icon lookup when spellID is secret, matching the existing GetSpellName guard nearby.  
- Swing Timer: drive the fill from the engine timer  
    The QoL timer this bar replaces put its fill on the engine: a per-row  
    C\_DurationUtil duration object handed to StatusBar:SetTimerDuration, no  
    Lua per frame. The bar was animating the same fill from a 20 Hz Lua  
    ticker (the GCD bar's eased SetValue), a cost regression against the  
    code it removes.  
    PLAYER\_SWING now re-sets the row's duration object and arms the bar  
    timer in the direction the row already drew (ElapsedTime fills,  
    RemainingTime drains for Deplete Fill), with Immediate interpolation so  
    a restart mid-swing snaps instead of easing back. The ticker keeps only  
    what the engine timer cannot do: the remaining-time text and the end  
    edge (idle render, Hide When Idle). Idle, PLAYER\_DEAD, the row toggles  
    and bar disable park the timer on a finished duration, whose terminal  
    state is static (the GCD bar's idle recipe), so an idle row costs  
    nothing.  
    The top gate now covers the duration and timer APIs alongside  
    C\_SwingTimer and its enum, with the enum's literal fallback gone.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Unlock: review fixes  
    Closes what a review against CONTRIBUTING and the surrounding code found  
    in the explicit-anchor branch:  
    - SetAnchorParams re-derived the offset from raw live rects, bypassing  
      \_CaptureAnchorOffsets and so keeping the raid container's per-tier  
      offset in the stored offset (every apply folds it back in). The helper  
      now takes an optional point pair and every capture goes through it:  
      the point pick, the screen-anchor set/clear recaptures, and the  
      post-drag capture no longer computes the side offsets first.  
    - PropagateAnchorChain's axis gate read the derived side, so a pointed  
      child hanging off a target corner was skipped on the parent's width  
      or height change although the corner moves under CENTER growth. The  
      gate now reads the target point instead when one is stored.  
    - The pre-load ReapplyOwnAnchor stub placed a pointed record with the  
      side geometry until the full body reapplied. The point arithmetic  
      moved ahead of the stub, which now places it the same way.  
    - The chain cascade after a pick ran on a C\_Timer, unlike the nudge  
      path; synchronous now, and the anchor-links stamp bumps when the  
      derived side changes so memoized views re-derive.  
    - The point list was parented to cogMenu, which reparents its children  
      to nil on every open; it lives on the mover under unlockFrame like the  
      screen-edge flyout, with that flyout's colours, font, current-row  
      orange, click registration and leave-to-close. The value button uses  
      MakeDropdownArrow instead of a "v" glyph, labels go through Lf, the  
      offset boxes take the X/Y boxes' numeric setup, and one conversion  
      serves the box and the nudge sync.  
    - The read-only X/Y boxes were EnableMouse(false) with an ad hoc grey;  
      they are disabled the way a matched Width/Height box is, with the  
      same tooltip shape.  
    - Picking a point closed and reopened the menu; it rebuilds in place.  
    - Helpers private to this file carry the underscore the neighbours use,  
      and the block note says why they sit on EllesmereUI (200-local cap);  
      the PropagateAnchorChain doc comment is back on its function.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Swing Timer: review fixes  
    Closes what a review against the module's own bars turned up:  
    - ApplyRowLook read an undefined fillTex when anchoring the spark, so  
      Show Spark pinned it to the row's right edge instead of the fill's  
      leading edge. It now fetches the fill texture as the GCD bar does.  
    - Every value read from the swing API and UnitAttackSpeed (PLAYER\_SWING  
      and PLAYER\_SWING\_RANGE\_UPDATE arguments, IsTargetWithinSwingRange, the  
      off-hand and ranged speeds) goes through a Plain() secret-value check  
      before it is compared, and a non-finite swing duration is ignored --  
      the guards the Quality of Life timer this bar replaces already had.  
    - The migration moves under the Registered migrations header with the  
      rest of the chain, and fills in the QoL defaults (240x18, gap 4,  
      y -220) for keys the profile store stripped, so a migrated bar keeps  
      the size and place the user last saw instead of the bar's own  
      defaults.  
    - Row Spacing is a pixel slider like the other spacing sliders on the  
      Resource Bars pages.  
    - The swing timer's width and height join the MATCH\_OWNED\_FKEYS map so  
      a live match link is not fought by a stale spec-override copy, as the  
      GCD bar's are.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Fix the Power Bar resource on WoW Forever (hunters use mana)  
- Cooldown Manager: review fixes  
    Closes the picker comment's mismatch with the menu it describes: the  
    entries hidden by the removed gate are Custom Spell ID / Custom Item ID /  
    Equipment Slot plus the trinket / racial / potion presets, not three  
    custom entries, and the empty states that reach the gate are named the  
    way the code sees them (before COOLDOWN\_VIEWER\_DATA\_LOADED, or every  
    entry set to Not Displayed) so the comment says why the menu must still  
    build there.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Swing Timer: row toggles on two DualRows, not a TripleRow  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Swing Timer: queued attacks, per-row toggles; replace the QoL timer  
    The Resource Bars swing timer takes over from the Quality of Life one  
    (v9.2) and picks up what that one had: on-next-swing attacks (Heroic  
    Strike / Cleave / Maul) turn the melee rows the queue colour and carry  
    the attack's name (ACTIONBAR\_UPDATE\_STATE, registered only while the  
    highlight is on, delta-painted); Main Hand / Off Hand / Ranged rows can  
    be switched off individually; rows reset on PLAYER\_DEAD.  
    The QoL files, TOC lines, options page and profile hook go; a profile  
    migration (swing\_timer\_to\_resource\_bars\_v1) carries an enabled QoL  
    timer's settings over (size, gap, font size, texture, position, rows,  
    queue colour; Only Show In Combat -> the In Combat visibility mode).  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Swing Timer: lay the rows out before styling their borders  
    The textured border backdrop was first set up on unsized rows and then  
    kept its dead nine-slice; size and position now come first, as on the  
    cast and GCD bars.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Swing Timer: set the row fonts before the first SetText  
    A FontString without a font raises "Font not set" on SetText on the  
    Forever client; the tag and time strings now get the resource-bar font  
    at creation, ApplyRowLook only re-sizes them.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- Resource Bars: Swing Timer bar (WoW Forever)  
    A fifth resource bar for WoW Forever, driven by the client's native swing  
    timer API (PLAYER\_SWING, C\_SwingTimer range checks). One row per weapon  
    slot that can swing (Main Hand / Off Hand / Ranged, from UnitAttackSpeed),  
    stacked in one frame that shrinks to the rows shown. Each row is a  
    StatusBar with bg, PP border, spark, remaining time and slot tag; fill on  
    a 20 Hz anim ticker that runs only while a row is live. Out-of-range  
    target dims the row and paints its text red, mirroring Blizzard's bar.  
    Shares the Visibility checklist, colour/gradient/texture/border widgets  
    and the unlock mover with the other bars (element ERB\_SwingTimer, order  
    508, anchorable). Options page "Swing Timer" under Resource Bars.  
    Gated on C\_SwingTimer: on retail the file returns at load, the page is  
    not registered and the hooks are nil. Off by default = no frame, no  
    events, no ticker.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- zhTW: translate 103 new keys for WoW Forever, Blizzard Style and Run Summary  
    Covers everything v9.2 and v9.2.1 added on top of the previous watermark:  
    the Style page with its per-module Blizzard Style descriptions, the WoW  
    Forever launch popup, the Mythic+ Run Summary panel and its columns, the  
    Swing Timer page, the Camp Benefits reminder with the two camp foods, and  
    the screen-edge anchors in Unlock Mode.  
    Terms follow the client's own zhTW strings wherever one exists. Blizzard  
    Style reuses the rendering already fixed by Blizzard Style Action Bars,  
    Depleted takes Blizzard's own CHALLENGE\_MODE\_KEYSTONE\_DEPLETED wording,  
    and the two camp foods use their retail item names (275266, 275269).  
    Tooltips that name another option quote that option's existing rendering,  
    so Tabs Inside Chat Panel, Show Level, Refresh Rate, Damage Taken and  
    Interrupts all read the same as the controls they point at.  
    WoW Forever stays in English: it is the client's product name and has no  
    official zhTW rendering, the same treatment EllesmereUI itself already  
    gets.  
    Also drops eight entries the source no longer looks up. Five were renamed  
    or reworded upstream and their replacements are already translated (Apply  
    Visibility to all Frames, Stack Count, Friendly Name Size (Name Only), the  
    rewritten pull-button countdown tooltip, and the reminder tooltip that  
    gained augment runes); the other three no longer exist in any form. L() is  
    an exact table lookup, so none of them could ever be hit again.  
- Add Korean localization for new UI features  
    Added new localization strings for UI settings and features related to WoW Forever.  
- zhTW: translate 36 new keys for chat bubbles and Rotation Assist  
    Covers the two v9.1.8 additions that shipped untranslated: the Chat Bubbles  
    page (channel picker, appearance sliders, enable popup and the instance  
    warning) and the Cooldown Manager's Rotation Assist style row.  
    Terms follow the client's own zhTW strings wherever one exists, and tooltips  
    reuse the exact option names the player sees on the same page, including the  
    existing Party and Raid renderings.  
    Also replaces the Chat module's searchTerms haystack. Upstream appended the  
    bubble keywords to it, so the previous key can never be looked up again --  
    L() is an exact table lookup. The Chinese search words carry over unchanged  
    plus the new bubble terms.  
- fix(unitframes): keep health text centered with clipping  
    Preserve the health bar's logical vertical position while retaining the half-pixel clipping inset. Cancel the clip's top inset after pixel snapping so zero-offset text matches the preview instead of inheriting a downward half-pixel shift.  
- Cooldown Manager: open the CD/utility spell picker on an empty Blizzard list  
    ShowSpellPicker returned before building the menu when the bar's Blizzard  
    CDM set was empty, which also hid the Custom Spell ID / Custom Item /  
    Equipment Slot entries it hosts - the only way to populate a bar while the  
    viewer has no data for the spec. The list sections already render nothing  
    for an empty set, so the gate is dropped.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- unlock: Offset X/Y boxes in physical pixels  
    The two Offset boxes showed and took raw UIParent units while every  
    pixel slider (Button Spacing) and the X/Y Position boxes next to them  
    show physical pixels; at 1.8 px/unit an Offset of 5 read as a Spacing of  
    10 within a pixel. Convert with PP.ToPixels / PP.FromPixels so +1 is one  
    pixel, one nudge, and the numbers agree with the sliders.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- unlock: keep anchor points across the Exit-without-saving snapshot  
    The discard snapshot copies anchor records field by field; point/relPoint  
    were not on the list, so every pointed anchor came back as a side record  
    carrying point-to-point offsets and jumped on Exit without saving.  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
- unlock: edit an anchor's points and offsets from the cog menu  
    An anchored element's cog menu (right-click in Unlock Mode) gets an  
    Anchor block under the size/position rows: the target it hangs off, a  
    point dropdown for THIS element, a point dropdown for the target (each  
    labelled with the element's name and offering the nine frame points),  
    and Offset X / Offset Y in pixels. Picking a point keeps the element  
    exactly where it is - the offset is re-derived from live bounds for the  
    new pair - and a typed offset moves it. "Action Bar 3 point: Bottom  
    Left, Action Bar 2 point: Bottom Right, 0, 0" reads the way SetPoint  
    does, which is the vocabulary people already have.  
    Storage: ai.point / ai.relPoint on the anchor record, both optional. A  
    record without them reads back as the classic side geometry (child's  
    near edge on the target's edge, centred across), so nothing changes for  
    existing anchors, drags, nudges, chains, fallbacks or the Anchor To  
    picker. With them, ApplyAnchorPosition places the element from the two  
    points directly and skips the growth-edge pin and edge preservation:  
    the own point IS the fixed edge, so a resize grows away from it by  
    construction. ai.side is kept in sync from the pair for the parts of the  
    system that read it (chain extents, mover captions, fallback picks), and  
    the post-drag capture stores the offset point to point.  
    Why not expose side + a cross-axis alignment instead: it was tried  
    first, and "side" was ambiguous (it is the target's edge, not the  
    element's), the growth pin fought the cross alignment, and it still  
    could not say "my bottom-left on your bottom-right" without a hand-  
    computed offset.  
    No new top-level locals (the file sits at 196).  
    Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>  
