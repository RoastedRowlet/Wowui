# EllesmereUI

## [v9.6.9](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.6.9) (2026-10-27)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.6.8...v9.6.9) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.6.9  
- Merge pull request #2898 from Aelexe/fix/spec-override-form-paging  
    [Fix] Paging settings not applying on spec switch or login  
- Merge pull request #2895 from JuJuFX-dev/fix/ab-visibility-override-never  
    Fix(Action Bars): Visibility override not showing Action Bars saved as Never  
- Merge pull request #2896 from DlargeX/main  
    add more new German Localstrings  
- Fix paging settings not applying on spec switch or login  
- added new German Localstrings  
- Merge remote-tracking branch 'upstream/main'  
- Regenerate the locale key list  
- Drop Mouseover override checks, clear stale toggle state  
    Action Bars cannot carry a Mouseover override (noOverrideMouseover), so the  
    two hover checks for it were dead code. When an override change takes a bar  
    out of the Toggle Action Bar set, its key is no longer bound, so a leftover  
    runtime toggle state is now cleared before the visibility pass instead of  
    pinning the bar until /reload. Also drops a duplicated Never check in the  
    data bar update.  
- Honor Visibility override in hover, toggle key and drag paths  
    Follow-up to the effective-Never gates: the mouse-motion gate, the  
    non-driver Show branch, the drag mouseover surfacing and the Toggle Action  
    Bar key still read the saved mode. They now let an applied override decide,  
    and \_EAB\_Apply rebuilds the toggle key bindings so a changed override or  
    profile re-evaluates which bars participate.  
- Fix Visibility override not showing Action Bars saved as Never  
    A Visibility override (spec or conditional) only reached the driver string  
    builder. Every gate in front of it still read the saved alwaysHidden /  
    barVisibility, so a Never bar with an Always or Mouseover override stayed  
    hidden, and an unbound Never bar never got its buttons built.  
    Add EAB.VisibilityCompat.IsNever(s), which lets an applied override decide  
    before the saved mode, and use it at every runtime gate: combat and runtime  
    visibility passes, the Never set, initial bar state, paging, QuickKeybind,  
    drag and spellbook surfacing, unlock movers, pet, extra, data and XP bars.  
- Merge pull request #2883 from nulltyto/audit/2026-10-25  
    Correctness fixes from a full-codebase review: profiles, sync, spec overrides, and module bugs  
- Merge pull request #2884 from scavienger/locales/koKR  
    locales(koKR): Translate new features and refine existing translations  
- Merge pull request #2888 from Barbiero/locale/ptbr-since-2026-10-24  
    ptBR: Party Mode horoscope and AFK screen, unit frame text tags, missing-debuff nameplate colors, enhanced upgrade tooltips  
- Merge remote-tracking branch 'upstream/main'  
- ptBR: Party Mode horoscope and AFK screen, unit frame text tags, missing-debuff nameplate colors, enhanced upgrade tooltips  
- Fix the Dracthyr birth zone name in the horoscope: The Forbidden Reach  
- Unit Frames: repaint after Dark Mode is turned off with the panel open  
    ReloadFramesBody ran ApplyEnemyColors, whose Engine.ForceAll repaints  
    every frame, before the per-frame pass re-ran ApplyDarkTheme. Turning  
    Dark Mode off therefore repainted with the dark color hooks still  
    installed, and ApplyDarkTheme then turned class coloring back on  
    without repainting: the player bar stayed the dark fill until the next  
    health event or the panel closed. Run ApplyEnemyColors last. Same single  
    repaint per reload, so no added cost.  
- Cooldown Manager: one rebuild per gear swap, not one per slot  
    An equipment set fires PLAYER\_EQUIPMENT\_CHANGED once per changed slot,  
    and each ran a full BuildAllCDMBars (MeasureCall: about 3.5 ms), so a  
    3-5 slot swap stacked 10-17 ms into one frame. Coalesce them into one  
    rebuild on the next frame. A swap in combat still needs none: trinkets  
    cannot be swapped in combat, and the trinket hook already updates its  
    frames. If combat starts before the deferred rebuild runs (an /equipset  
    + opener macro), it stays pending and PLAYER\_REGEN\_ENABLED runs it.  
    In game: six set swaps added no Cooldown Manager frame over 5 ms.  
- Bank: poll for new tabs only after a purchase, on one reused frame  
    Every PLAYER\_ACCOUNT\_BANK\_TAB\_SLOTS\_CHANGED (each warband slot change)  
    created a new frame that re-ran DiscoverBankTabs every 6 frames for up to  
    300 frames, waiting for a tab count that only a purchase changes. Slot  
    changes now take the debounced refresh, like BAG\_UPDATE; only  
    BANK\_TABS\_CHANGED polls, on one reused frame.  
    Same-session A/B, 20 warband moves: total Bags CPU about 3.5 s vs 4.1 s.  
    The remaining cost is the full RefreshBank per move (about 17 ms each).  
- Party Mode: automatic triggers leave a manual session alone  
    Every trigger set partyMode and started a stop timer, so a session the  
    user turned on by hand ended when the timer fired. Fold the seven copies  
    into one Celebrate helper with the AFK corner's existing guard, and have  
    the manual toggle cancel a running celebration timer.  
    The toggle and the panel open share one CancelCelebration, which runs the  
    celebration's end hook, so a Random celebration ended by the keybind or  
    /partymode still schedules the next one. A trigger that replaces a running  
    celebration keeps the earlier hook.  
- Profiles: trim the name in Create New (Copy)  
    Matches the page's other name boxes, which already strtrim.  
- Profiles: detect old CDM layout strings by their 8-character prefix  
    The check compared sub(1, 9) with the 8-character "!EUICDM\_", so it never  
    matched and old strings got the generic "Not a valid" message.  
- Profiles: stop the deserializer looping on a truncated token  
    A string token with no colon, no length or a negative length, or a  
    number token with no ';', did not advance, so the enclosing table loop  
    re-read it forever and froze the client on a damaged import string.  
    Flag the parse as malformed and jump past the end; Deserialize then  
    returns nil, which both import paths report as a failed decode. No  
    error(): the async decode yields mid-parse, which a pcall would forbid.  
- Fonts: keep Blizzard Default on the client font under Apply to All Game Text  
    Apply to All Game Text overwrites STANDARD\_TEXT\_FONT at login, and the  
    Blizzard Default sentinel resolved through that global, so every font set  
    to Blizzard Default turned into the EUI face. Capture the client path when  
    the file loads and resolve the sentinel and its dropdown previews from it.  
- Spec Overrides: harvest on logout from the Lite pre-logout hook  
    The PLAYER\_LOGOUT harvest ran after Lite had already copied db.profile  
    into the saved store, so canonical values it restored never reached  
    SavedVariables. Run it as a pre-logout callback instead, ahead of the  
    defaults strip and the sync push.  
- Conditional overrides: release the transition latch when the handler errors  
    An error inside SpecOverrides\_CondTransition left \_condBusy and  
    Cond.\_resolveOverride set, so every later condition flip was refused  
    until a reload. Run the body through xpcall with the client error  
    handler, always release both, and mark the engine stale on failure so  
    the retry establishes instead of banking half-applied live values into  
    the outgoing group.  
    For the same reason Conditions\_Recheck does not resume the Default view  
    after a failed handler (it now returns ok, failed): re-entering the view  
    harvests, which would bank the half-applied values into the outgoing  
    group's override map.  
- Profile sync: mirror deletions and keep override-owned keys under exclusions  
    \_SelectiveOverlay wrote only the keys the source holds, so a key removed  
    on the active profile (a deleted CDM bar) stayed in every other member,  
    and an array entry survived past the source's end. Before the overlay,  
    drop destination keys the source no longer has, unless an exclusion  
    names that path or one below it, matching what the full-copy branch  
    already does for modules without exclusions.  
    The wildcard-container branch of \_SelectiveOverlay and SelectiveCopy  
    honoured only wildcard child names (cdmBars.bars.*.iconSize) and ignored  
    exact override-owned paths below them (cdmBars.bars.1.borderTexture), so  
    a spec override's live value was pushed into synced profiles. Skip exact  
    excluded leaves, recurse into tables that hold an exclusion, and keep  
    excluded keys in the deletion pass.  
    One commit because neither half works alone: the deletion pass without  
    the wildcard handling deletes override-owned keys, and the wildcard  
    handling calls the deletion pass's HoldsExclusion.  
- Conditional overrides: restore the applied overlay when a spec change ends an edit  
    A spec change ends an Editing-as-conditional session with noRestore,  
    which wrote back only the spec layer. The transition re-applies spec  
    values, and the conditional recheck is a no-op while the applied group  
    holds, so the edited group's values stayed live and a later flip banked  
    them into the outgoing group's maps. Write the applied group's values  
    on that path too and refresh what changed.  
- Spec Overrides: keep group overrides of disabled modules on harvest  
    HarvestMap records the default for an unloaded module's fkey, and the  
    session snapshot holds no table for that folder, so HarvestGroup took the  
    match for a revert made this session and cleared the fkey from every  
    member spec. Route unloaded fkeys through preserve, as match-owned ones  
    already are.  
- Unlock: end a combat-suspended session on a layout owner change  
    SuspendForCombat clears \_unlockModeActive and isUnlocked but keeps the  
    session's snapshots for the resume. Condition flips, profile switches and  
    profile applies tested \_unlockModeActive, and ForceCloseUnlockDiscard  
    tested isUnlocked, so a flip at PLAYER\_REGEN\_ENABLED left the session  
    open: 0.5 s later it resumed onto the new layout, where Exit Without  
    Saving reverted onto the wrong owner and Save committed the old  
    positions against it. Callers now test \_unlockModeSessionActive, and  
    ForceCloseUnlockDiscard closes a suspended session (UM.combatSuspended).  
- Profiles: keep the imported layout when importing over the active profile  
    ImportProfile installs the merged profile under the target name before the  
    switch step. When that name is the active profile, the outgoing harvest and  
    layout snapshot then wrote the live state into the imported profile: the  
    spec override harvest banked live values over the imported stores, and  
    SnapshotUnlockLayout replaced the imported unlockLayout.  
    At the start of the full-import branch, before current and merged are  
    built, close any edit session or Default view and run the one spec  
    override harvest, as SwitchProfile does. ApplyProfileData only closed  
    them after the stores swap, so with the options panel open the exit  
    banked live values into the imported Default values. Skip the snapshot  
    when the import targets the active profile's name.  
- Profiles: keep the recipient's per-profile stores on a full-account import  
    ImportFullAccountData copied every root key wholesale, so the recipient's  
    other profiles lost their CDM spell layouts (spellAssignments.profiles),  
    profile keybinds, sync groups and last-spec records. Snapshot those keys  
    before the copy and merge after it: the recipient's entries stand, and  
    only the carried profile's entry is taken from the string.  
    Spec-profile assignments are still replaced from the string, as before:  
    keeping the recipient's would reload a spec assigned to one of their own  
    profiles straight back onto it, and the import would not take.  
    The import also closes any Spec Overrides edit session or Default view  
    and banks live edits first, while the stores are still the recipient's.  
    With the options panel open, the later exit banked the live values into  
    the imported profile's Default values.  
- Fix reads of locals before their declaration in Bags, Unlock and Skin  
    * Bags Bank: BuildBankSidebar was a global; forward-declare it.  
    * Bags Sidebar: declare sidebarChild before the divider uses it.  
    * Unlock Tools: drop the snap edge indexes, written out of scope and  
      read nowhere.  
    * BlizzardSkin queue timer: the parent fallback named a global dialog  
      that is never set; say popup, which is what it resolved to.  
- ABR options: fix the talent and zone search resets and the talent pulse  
    * Talent and zone search reset the list through undeclared globals, so  
      the smooth scroll and thumb kept their old position; use the  
      scrollbar's own scroll-to.  
    * The missing-talent check pulsed classDDBtn/specDDBtn, which do not  
      exist; pulse the talent dropdown.  
    * Declare the header-height local before UpdatePreviewHeader writes it.  
- QoL Cursor: drop the broken unlock-mode watch tick  
    CursorWatchBody read gcdRoot, castRoot and their attach flags before  
    their locals were declared, so it never did anything. The unlock-mode  
    listener in OnEnable already hides and restores the circles, so remove  
    the watch and its 0.15s tick instead of reviving a second copy.  
- CDM: fix undeclared names in FocusKick, tooltip and preset paths  
    * Bars: the FocusKick re-anchor after a layout pass compared against a  
      nil global; use ns.FOCUSKICK\_BAR\_KEY.  
    * Bars: clearing a shown tooltip when a bar's tooltips are turned off  
      read a variable nothing set; check GameTooltip's owner instead.  
    * FocusKick: the nameplate-added early-out read an undeclared flag; use  
      \_focusKickNoKick (ShowFocusReminder already gated on it).  
    * HookPresetCooldowns: drop a call that has read a nil global since it  
      was written.  
    * Rebuild: GetBarData was a global; make it local (ns.GetBarData stays).  
- RaidFrames: restore the preview-open guards lost in the file split  
    Visibility and PartyLayout read a bare previewActive that no longer  
    exists in those files, so the guards were always false and  
    UpdateVisibility / \_UpdatePartyVisibility could re-show real frames  
    behind an open preview. Read ns.previewActive() there.  
    Events and Update carried the same dead read around repaints. Drop it  
    there instead of reviving it: the real raid frames stay faintly visible  
    under the default Overlay preview, and Extra Frames show beside it, so  
    both must keep repainting while the preview is open (a Power Bar Height  
    change, a Raid -> Party tab swap).  
- Use Blizzard's tIndexOf for two local list-index helpers  
    MicroMenu's IndexOf and GroupFinder Search's Contains each re-implemented  
    tIndexOf. Alias it instead, as EllesmereUIBags\_List.lua already does.  
    tIndexOf is defined in Blizzard\_SharedXMLBase on every client branch.  
- Share one frame-data constructor instead of 14 copies  
    Fourteen files each built the same weak-keyed frame-data table and  
    GetFFD getter. Add EllesmereUI.NewFrameData() to SharedHelpers, which  
    returns a fresh table and its getter, and call it once per file. Every  
    file still owns its own table, so two files never share fields on one  
    frame. The core's \_FFD/\_GetFFD pair uses it too.  
    The BlizzardSkin, Friends, Minimap and RaidFrames mains call it at load,  
    so their stale-parent guards check it too: a new child on an old parent  
    goes dormant instead of erroring.  
    The four *Forever.lua BlizzardSkin files were not tested in game (the  
    Forever client was unavailable); they take the same one-line change.  
- Remove unreferenced definitions across CDM, Glows and the modules  
    Each had a single reference in the repo (its definition), no string  
    dispatch, and no use in any other installed addon:  
    * CDM: no-op ns.RefreshTBBResolvedIDs, ns.RefreshBuffBarGating and  
      ns.SyncViewerToContainer; ns.CdmBookNameCount, ns.GetCDMBarFrame,  
      ns.GetCDMBarIcons, and \_G.\_ECME\_GetCDMSpellSet with the  
      BuildAvailableSpellPool it wrapped (unused since profile import moved  
      to spec filtering in v5.1.3)  
    * Glows: G.HideStealableBorder, G.HidePandemicBorder, G.EngineGroups  
    * DamageMeters: ns.ApplyDMPosition, ns.ApplyDMSize and the imports only  
      they used  
    * Visibility: no-op \_G.\_EBS\_UpdateVisEventRegistration  
    * ResourceBars: no-op \_G.\_ERB\_ApplyUnlock  
    * QoL: \_G.\_EUI\_HideTeleportPrompt  
    * AuraBuffReminders: \_G.\_EABR\_BeaconAnchor, \_G.\_EABR\_TR\_GetAnchor  
    * RaidFrames: ns.\_IsPartyAllSynced, ns.ResetPartyPreviewRandomization  
    * ForeverEssentials: ns.GetStyleGroup  
    Removed globals: \_ECME\_GetCDMSpellSet, \_EBS\_UpdateVisEventRegistration,  
    \_ERB\_ApplyUnlock, \_EUI\_HideTeleportPrompt, \_EABR\_BeaconAnchor,  
    \_EABR\_TR\_GetAnchor. Removed from EllesmereUI.Glows: HideStealableBorder,  
    HidePandemicBorder, EngineGroups.  
    Kept bar.GetAllowRadialWheel on the resource bars: Blizzard's ping  
    manager calls it.  
- CDM options: preview custom spell charges only when Show Charges is opted in  
    The live icon for a custom CD/utility spell has no Blizzard charge frame and  
    shows a count only when customSpellForceCount is set. The options preview  
    showed maxCharges for every spell with charges, so a custom spell previewed  
    a count the bar never drew. Gate the preview on the same opt-in.  
    A custom-tagged spell that Blizzard also tracks (one added before the v9.6.5  
    spell-list check, or a list-picked cooldown sharing an ID with a custom buff  
    added to the bar first) draws Blizzard's frame live, so it keeps the bar's  
    Show Charges setting, matching the Custom Spell ID popup's  
    IsCDMTrackedCooldown check.  
- CDM options: merge the duplicate Custom Spell ID popup into ShowCustomSpellIDPopup  
    ShowSpellPicker built its own copy of the Custom Spell ID popup to add the  
    Show Charges opt-in. Fold that into ShowCustomSpellIDPopup behind a  
    withCharges flag (Show Charges toggle, spell-list rejection,  
    customSpellForceCount write) and call it from ShowSpellPicker with its own  
    frame name, so the two pickers still never share a frame (see #2187).  
    Drop the withDuration branch and its duration fields: every caller passed  
    false. That removes the "Required" locale key.  
- UnitFrames: hoist per-builder text tag/position closures into shared functions  
    StyleFullFrame, StyleFocusFrame, StyleSimpleFrame and StyleBossFrame each  
    carried their own copy of ApplyTextTags and ApplyTextPositions. Replace them  
    with file-level ApplyFrameTextTags / ApplyFrameTextPositions. The per-builder  
    differences (right text default, frame width default, Simple has no extra  
    text) are passed in or read from the frame.  
    Simple and Boss now clear anchors on hidden left/right text, as Full and  
    Focus already did. No visible change: those texts are re-anchored before  
    being shown.  
- locales(koKR): Add missing Kick Tracker experimental warning translation  
    Translate the experimental workaround warning string on the Kick Tracker options page.  
- Translate new features and refine existing Korean locales  
    - Add translations for recent features (Custom Text tags and templates, Nameplates Missing debuffs, 9.6.9 patch notes, Mail Alt List, Enhanced Upgrade Tooltips, AFK Screen, Gather Tracking)  
    - Refine Kick Tracker bar settings, Threat Meter headers, and WoW Forever action bar notices  
    - Regenerate locale key list in \_keys.txt  
- Merge pull request #2879 from Direction6275/feat/np-missing-debuff-colors  
    Nameplates: color a plate while a debuff is missing  
- Merge branch 'main' into feat/np-missing-debuff-colors  
- Merge pull request #2880 from JuJuFX-dev/refactor/panel-builders  
    Panel: split CreateMainFrame into four builders to get it off the 60-upvalue limit  
- Merge pull request #2881 from JuJuFX-dev/feat/custom-text-tags  
    Feat(Unit Frames): Custom text with tags for text slots, text bar and power text  
- Regenerate the locale key list  
- Custom text popup: preselect the first suggestion again  
    The first suggestion is marked when the list opens and Enter inserts it like Tab, so a half-typed tag such as [health is completed instead of saved as typed.  
- Text tags: trim two doc comments to the comment budget  
- Custom text: review fixes for sync, popup and power text  
    Sync, multi-apply and slot moves copy a custom format only with Custom content, so other frames keep their own. The popup re-escapes pipes on open, names any unknown bracketed text, and its preview no longer fills the shared parse cache. Suggestions follow modifier aliases and free order; Enter inserts a picked or single suggestion and the first arrow key only reveals the pick. The power text cog moves into a shared helper with the Forever Name Format, Forever Essentials covers the power text, Form Power Text shows an inherited Custom as Power %, and the scrollbar inset for dropdown icons is opt-in.  
- Power text: Custom text on main, boss and pet frames  
    Power Text offers the Custom entry with the edit pencil on the main frames, boss frames and the WoW Forever pet frame; Form Power Text keeps its list without it. Sync copies and compares the format, Spec Overrides gets an accessor, Show % is locked for Custom, and the popup preview follows the power text colour. The deferred menu rebuild moves out of the text bar into a shared helper that both use.  
- Text bar: Custom text on the left, right and center slots  
    The custom text popup, its dropdown entry and the Spec Overrides accessor move out of the text slots into shared helpers, so the text bar reuses them. Sync copies the format, Power Colored covers custom formats with a power tag, and the popup preview follows Power Colored.  
- Text slots: edit pencil on the Custom dropdown entry  
- Custom text popup: scrollable suggestion list, tighter preview gap  
- Custom text popup: smaller suggestion descriptions  
- Custom text popup: suggestion list back to input width, smaller samples  
- Custom text popup: modifiers before the closing bracket, descriptions in the list  
    Tab on a tag that has longer variants inserts it without "]" and lists its  
    modifiers next; the bracket closes on the next Tab, or right away for a tag  
    typed in full. Each suggestion shows a short description between the tag and  
    its sample; the list spans the popup width.  
- Custom text popup: tag suggestions as a dropdown list  
    Typing "[" opens a list under the input with each matching tag and its  
    sample value. Up/Down move the selection (the panel search box's arrow  
    handling), Tab or a click inserts it, Esc closes the list before the popup,  
    and a click elsewhere closes it too. The list floats over the preview, so the  
    layout keeps its height.  
- Custom text popup: centred preview under the input, plainer message  
    The preview block moves back under the input, centred, with its label on a  
    line of its own. The message explains brackets, suggestions and the info  
    badge at size 10. Help examples colour their modifiers and show the result  
    after "=".  
- Nameplates: cap Missing debuffs at five; pets and roster changes count  
    Missing tints take one OVERLAY sublevel each (-4 to -8), so at most five  
    Missing debuffs can rank; the plates keep the first five chosen ones. The  
    state menu greys Missing once five other rows hold a chosen Missing debuff,  
    and a Missing row past the cap greys its spells (and Custom Spell...  
    refuses) with the reason, so it never silently colors nothing.  
    Who counts as engaged is now a cached list: you, your pet, your group and  
    the group's pets that are out. It is rebuilt and every plate re-checked on  
    GROUP\_ROSTER\_UPDATE and on UNIT\_PET for you or your group, both held only  
    while a Missing row exists. Locale keys regenerated for the new reason.  
- Custom text popup: preview above the input, tag suggestions, reworked help  
    The preview row moves above the input with a small dimmed label and the  
    value in the slot's text colour. Typing "[" lists matching tags under the  
    input and Tab takes the first one (TextTags.Complete). The info badge sits  
    left of the input with the help opening left of the popup. The help gets a  
    Syntax heading, shows aliases inline ("[hp] or [health]", "pct or percent"),  
    lists every tag in the same format and notes DEAD or OFFLINE at [hp].  
- TextTags: clearer preview line and a shorter tag help  
    The popup preview sits under a divider with a dimmed label and the value in  
    the accent colour; unknown tags are coloured inline. The help lists one line  
    per tag with its modifiers, explains each modifier once, and colours headers,  
    modifiers and descriptions.  
- Nameplates: Missing debuff colors draw through masks, on engaged mobs only  
    Clip windows rendered as their own units at their frame level, so ties  
    with each other and with the border broke differently per plate (mixed  
    colors, color over the border). Each sensor now owns a mask on its  
    container's right edge (clamped to black outside its rect, sized so the  
    WHITE8x8 edge fade stays off the bar), and the color draws through it.  
    In the flattened plate a higher frame level beats a higher sublevel, and  
    the border and the target/focus/hover stripes share the bar's level + 1.  
    Missing tints therefore stay on the bar's level, on OVERLAY -4 down to -8  
    by list order: over the other debuff colors, under the border, shade,  
    hash line and stripes. Color Border copies carry their own mask copy.  
    The color now shows only on a mob whose threat list holds you, your pet  
    or your group (type tag only; the value can be secret), so mobs fighting  
    only other players keep their normal color. The combat-flag read and the  
    UNIT\_COMBAT fallback are gone. The state menu reads the saved list once.  
- Unit Frames: preview, unknown-tag hint and letter count in the Custom popup  
    The Custom text popup takes its preview line, the hint naming unknown tags  
    and the tag help beside the popup from TextTags.PopupOpts, and shows the  
    letter count. The help notes that [hp] and [hp:abr] read DEAD or OFFLINE.  
- Popups: optional preview line and tooltip options for the input popup  
    ShowInputPopup takes opts.preview(text), which returns a preview line and a  
    hint line shown under the input at a fixed height, refreshed on open and on  
    every text change. opts.infoTooltipOpts goes to ShowWidgetTooltip with the  
    popup frame as anchor, so the info text can sit beside the popup. Without  
    these options the popup is unchanged.  
- Unit Frames: parse Custom text through TextTags  
    The health text slots bind the unit tag schema to their own pieces and  
    resolve Custom formats through EllesmereUI.TextTags instead of a local  
    parser. Adds full-number pieces for [hp], [hp:max], [pp] and [pp:max];  
    the abbreviated values move to the :abr modifier. Width estimate, preview,  
    level and name checks and the tag help read the same catalog.  
- Core: add TextTags, a shared tag vocabulary and parser for custom text  
    EllesmereUI.TextTags holds the unit tag schema (tags, aliases, modifiers,  
    what each key reads, width estimate, sample), Bind to narrow it to the keys  
    a module draws, a cached Parse returning a format string plus schema keys,  
    and helpers for preview, width estimate, help text and popup options.  
    Pure string logic: no frames, events or units.  
- Panel: split CreateMainFrame into four builders  
    CreateMainFrame sat at 59 of 60 upvalues (the Lua 5.1 limit), so one more  
    outer local read would have broken the core file to load. Its body is now  
    BuildFrame, BuildSidebar, BuildContent and BuildFooter (at most 30 upvalues  
    each), called in the same order by a thin CreateMainFrame. The bodies are  
    unchanged. BuildContent hands rightW and rightX to BuildFooter and keeps its  
    own local pairs, which it used to share from the sidebar section.  
- Unit Frames: show Remove in red with the close X in text slot menus  
    The Remove entry of the text slot dropdowns now reads in the house BAD  
    red and carries the house close X (eui-close) at the row's right edge,  
    12px in the same red at the list delete buttons' 0.75 alpha. Label and  
    icon brighten on hover, so the entry stands apart from the text  
    contents and the Custom entry below it.  
- Widgets: optional icon and label styling for dropdown menu items  
    Dropdown menus can now style individual items through \_menuOpts, for  
    both plain and clickable (iconOnClick) icons:  
    - iconSize(key): icon edge length (default row height - 8)  
    - iconColor(key): r, g, b[, a] idle tint; hover raises it to alpha 1  
    - iconInset: right inset, a number or fn(key) (default 6)  
    - labelColor(key): r, g, b[, a] idle label colour; hover keeps the hue  
      at alpha 1 and menu refreshes restore it  
    Icons on the default inset also move clear of the scrollbar track when  
    the menu scrolls, so scrolling menus with icons no longer overlap it.  
    Menus that set none of the new options look as before, apart from that  
    scrollbar inset.  
- Unit Frames: edit Custom text in a popup with a tag info badge  
    Custom is now an accent-coloured action entry right below Remove. It  
    opens an input popup (format prefilled, 120 letters or the stored  
    length) instead of a cog row; saving selects Custom for the slot, and  
    spaces-only input reopens the popup with a hint.  
    ShowInputPopup gains an optional infoTooltip: an info badge beside the  
    title that shows the tag list on hover and drops it when the popup  
    closes. Other callers are unchanged.  
    The engine exposes its cached parser (copying for the options side, raw  
    through I for the layout), so the width estimate, preview, level cog  
    rows and Forever name-format gate all read the same parse. Names weigh  
    only on the right slot's estimate, literal text counts UTF-8 characters,  
    and the identity flag comes from PIECE\_READS. The cache is bounded.  
    Spec Overrides captures the format on Custom slots, the sync icon  
    compares formats only for Custom, and all new strings are literal  
    EllesmereUI.L calls (\_keys.txt regenerated).  
- Unit Frames: add Custom text format for health text slots  
    A new "Custom" entry at the bottom of the Left/Right/Center/Extra text  
    dropdowns lets each slot carry its own format string, e.g.  
    "[hp] | [hppct]%". The cog gets a Custom Format input whose label tooltip  
    lists every tag.  
    The string is parsed once into a format plus text pieces and rendered  
    through the existing zone painter, so values stay in the SetFormattedText  
    argument lane. Several slots may use Custom at once; the format follows  
    sync and slot moves, and the options preview renders it.  
- Merge remote-tracking branch 'upstream/main'  
- 9.6.9  
- Merge pull request #2537 from Jetro974/forever-gather-tracking  
- Nameplates: Debuff Coloring can color a plate while a debuff is missing  
    Each debuff row gets an Applied / Missing dropdown beside its spell. A  
    Missing row colors the health bar (or border, with Color Border) of an  
    enemy in combat while your debuff is not on it, and wins over every other  
    debuff color and the target/focus/hover patterns. Combos stay all-applied.  
    A Missing row reads one hidden one-aura group per plate: the engine lays  
    its container out at 1x1 while the debuff is absent, and a clip window on  
    the container's edge shows the color only then. No aura data is read. The  
    color shows on an enemy in combat or one that lists you for threat (a body  
    pull's threat update comes first). Sensors persist per plate and are  
    re-pointed on settings changes, since groups cannot be removed.  
    Saved as a "!" ahead of the spell in the class list; older builds read a  
    missing row as an unchosen debuff. Tests cover the codec, the options  
    dropdown and the runtime (gate, precedence, sensor reuse, Color Border).  
- add more new German Localstrings  
- 9.6.9  
- Merge pull request #2872 from silverbrit/feat/enhanced-upgrade-tooltips  
    feat(qol): add opt-in upgrade tooltips and Ascendant caps  
- Merge branch 'main' into feat/enhanced-upgrade-tooltips  
- Merge pull request #2876 from LoChinAn/locale-zhtw-mail-alt-list  
    zhTW: translate 21 new keys and the Mail Alt List  
- Merge pull request #2878 from TzahalHPal/afk-logo-size-fix  
    AFK screen: fix Logo Size at large values  
- AFK screen: fix Logo Size at large values  
- Merge pull request #2877 from TzahalHPal/afk-screen  
    Party Mode: add AFK tab with bouncing logo screen  
- AFK screen: add Logo Size slider  
- Merge pull request #2874 from choppaoops/feat/cdm-tbb-reorder  
    feat(cdm): drag Tracking Bars to reorder them within their group  
- Party Mode: add AFK tab with bouncing logo screen  
- zhTW: translate 21 new keys and the Mail Alt List  
    Covers the strings added in v9.6.7 - v9.6.8 after #2866: the Mail  
    Alt List card and menu, the Mythic+ Timer conflict message, the  
    options-language note and the checkbox dropdown count label.  
- Merge pull request #2873 from brokencrown/bag-and-bank-strata-fix  
    Fix unresponsive bag/bank icons when frame strata is set to High  
- Merge pull request #2875 from Barbiero/locale/ptbr-since-968  
    ptBR: Mail Alt List, Mythic+ Timer conflict message and language note  
- ptBR: Mail Alt List, Mythic+ Timer conflict message and language note  
- ran full in-game tests and cleaned up comments to be more understandable. Also removed some comments that were more of a code smell than helpful  
- Address audit: fix Compact drop-zone collision, overlay staleness, bank list-row order, Raise() desync  
    - Grid.lua GetOrCreateSlot: missed +50->+9 adjustment for Compact drop-zone collision  
    - Add ns.PinItemButtonLevel shared helper (EUI\_Bags\_Shared.lua): re-pins btn plus  
      its \_textOverlay (+3) and \_warbankDim (+6) together, since both are separate  
      sibling frames that previously froze at the button's original template level  
    - Fix \_textOverlay level computation in Grid/Reagent/List/Bank creation sites to  
      read the button's own (pinned) level instead of the frozen Cooldown snapshot  
    - Extract EUI\_Bags:RepinIconLevels() / EUI\_Bank:RepinIconLevels(), call them from  
      ApplyWindowLayering (bank's own ApplyWindowLayering now runs before the shared  
      list-row resync, so bank-hosted rows never read a stale bank level) and from  
      every Raise() call site (OnMouseDown/OnShow), so a window being raised outside  
      of a strata change can no longer desync it from its icon pool  
    Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>  
- feat(cdm): drag Tracking Bars to reorder them within their group  
    The "Currently Editing" menu could only drag a bar into another group;  
    changing the order inside a group meant deleting bars and adding them  
    back. Dragging a bar over its own group's rows now shows a green  
    insertion line (the same marker as the CDM bar menu's reorder) and the  
    drop moves the bar there. The group header drops it first, the  
    "+ Add Bar to Group" row last. Drops on another group still move the bar  
    into it exactly as before.  
    ns.MoveTrackedBuffBarInGroup(idx, pos) lets the group's members trade  
    the slots they already hold. Bars outside the group keep their indices,  
    and positions and unlock links (keyed by index) stay with their slot, so  
    the group does not move and whatever is anchored to it stays anchored.  
    When a disabled member hands the anchor role to another slot, the group  
    origin is copied there, as the group mover's save already does for  
    every member. No style is copied, so per-bar text positions and looks  
    are kept.  
    The editing context survives the drop (a selected bar follows its  
    config to its new index) and the menu opens again for the next move.  
    Options-only: no new setting, nothing runs until a bar is dragged.  
    The drag hint now mentions reordering: one changed locale key, zhTW  
    translation added, \_keys.txt regenerated.  
    Co-Authored-By: Claude <noreply@anthropic.com>  
- fix for #2856  
- feat(qol): add opt-in upgrade tooltips and Ascendant caps  
- ABR (WoW Forever): gathering tracking and Find Treasure reminders  
    Two opt-in reminders in the WoW Forever section: Find Herbs / Find Minerals  
    when known but neither is active (cog: ignore while a class tracking is up),  
    and Find Treasure for Dwarves. Click to cast.  
