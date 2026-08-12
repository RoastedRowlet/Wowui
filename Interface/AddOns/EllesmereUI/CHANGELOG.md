# EllesmereUI

## [v8.8.4](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.8.4) (2026-08-12)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.8.3...v8.8.4) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.8.4  
- Merge pull request #1350 from JuJuFX-dev/feat/pab-weapon-enchants-filter  
    feat/fix: add standalone Weapon Enchants filter to the default Buffs  
- feat(pab): add standalone Weapon Enchants filter to the default Buffs bar  
    Weapon Enchants moves from a DISPLAY-section toggle into its own pinned row in  
    the Filters dropdown, dropping the previous gate that required All Buffs or  
    Has Duration to be on -- checking it alone now shows just the enchant cells.  
    The default Buffs bar renames itself to Weapon Enchants (or Buffs & Weapon  
    Enchants when combined with a broad-content mode) in both the options sidebar  
    and the unlock-mode mover, and auto-sizes its grid to 3/1/3 while  
    enchants-only, restoring the user's previous values on the way back out. The  
    preview box mirrors the live container's own shift-past-enchants behavior  
    instead of treating them as ordinary leading icons.  
- Merge pull request #1342 from labrie75/Updates-the-Korean-locale-only  
    koKR: +300 keys (Quickdraw, Player Aura Bars, raid frames, reminders), unify timer/raid terminology  
- Merge pull request #1341 from labrie75/Quickdraw-picker-menus  
    Localization: route Quickdraw picker menus, slot tooltips, and popups through L()/Lf()  
- Merge pull request #1347 from SamTheBosssss/fix-warrior-sweeping-strike-12.1  
    Fix warrior sweeping strike changes in 12.1  
- Merge pull request #1346 from labrie75/Fix-spec-override-labels  
    Fix: spec override labels drop the first character of localized class names  
- Merge pull request #1345 from dfrisone/rf-debuffmanager-stray-dbg  
    fix(raidframes): restore the Icon Effects per-slot gate, dropping a stray dbg global  
- Merge pull request #1348 from nulltyto/quick-draw-updates  
    feat(quickdraw): toggle mode, Dynamic Rez and world marker entries  
- Merge pull request #1349 from JuJuFX-dev/fix/cdm-stale-linked-spell-cooldown  
    fix: CDM repair stale-linked-spell icons instead of leaving them blank  
- CDM: repair stale-linked-spell icons instead of leaving them blank  
    Blizzard resolves a cooldown item's spell through GetSpellID(), which prefers  
    cooldownInfo.linkedSpellID over the base spell. When an aura ends without its  
    UNIT\_AURA removal reaching the item (e.g. an aura instance cleared by a refresh  
    that lands just inside the removal race, or an aura on a unit that is no longer  
    the target), the link outlives the aura. Blizzard then reads the cooldown from  
    the linked (aura) spell instead of the ability, gets start=0/dur=0, and renders  
    the icon as fully available for the rest of the real cooldown -- no swipe, no  
    countdown, not desaturated. Reported for Touch of the Magi and Execution  
    Sentence; field-confirmed with real ids (base=321507, linked=210824) and with a  
    recovery path (PLAYER\_TARGET\_CHANGED without UNIT\_TARGET) that is unreliable.  
    ReAssertRealCooldown's existing "widget reads ~0" proof cannot run in  
    restricted combat, where the duration itself is a secret value -- exactly the  
    content this was reported from. Detect the stale-link state structurally  
    instead (linkedSpellID set, no aura instance, aura not displayed -- all  
    nil-compares and never-secret bools, never a spell-id comparison) and repair  
    both the swipe geometry/colour and the icon's saturation from it.  
    Still reachable upstream: Blizzard's PTR branch adds this same repair to  
    CooldownViewerBuffItemMixin, but not to the cooldown-item mixin this addon  
    hooks, so the underlying bug is not yet fixed there either.  
- fix(locales): drop 26 dead keys the stale build copy put in the list  
    Regenerated in a clean checkout: 724 keys down to 698, nothing added. Every one  
    removed belongs to a string that no longer exists in the source -- Anchor  
    Direction, Export Full Profile, Health Bar and the rest are ActionBars,  
    Profiles and ResourceBars strings still sitting in a .release/ snapshot. None  
    of them are Quickdraw's.  
- build(locales): keep the key extractor out of the stale build copy  
    The grep walked the whole tree with only Libs and the locale folder excluded,  
    so a working copy holding a .release/ build directory -- an old snapshot of  
    every file -- had its dead strings scraped back in. That is invisible locally,  
    where the run comes out "clean" against a key list generated the same poisoned  
    way, and shows up only as a CI failure: the checkout there has no .release, so  
    it regenerates a shorter list and fails the PR.  
    CI's own output is unchanged. This only makes a local run agree with it.  
- refactor(quickdraw): build the pass-through list on the first gate  
    At file scope it was built whether or not the module was ever switched on. Gates  
    are made when a palette opens, so behind that the list costs a disabled session  
    nothing at all.  
- fix(quickdraw): move auto-names down when an action menu is deleted  
    Deletion shifts the palettes and repoints everything that pointed at them --  
    nested entries, keybinds -- but left the names where they were. A menu the user  
    never renamed carries the number it was made under, so deleting Action Menu 1  
    left "Action Menu 2" sitting at index 1, and Add, which names by index, then  
    handed out that same name a second time.  
    Only the auto-name moves; a name the user typed is theirs, whatever it looks  
    like. Names already duplicated in a profile stay as they are -- rewriting names  
    on load would touch what the user may have chosen deliberately.  
- fix(quickdraw): stop a modified palette key from claiming the bare key  
    The modifier variants started at the empty prefix, so a palette bound to SHIFT-T  
    also took plain T whenever T was free -- an opening on a key the player had left  
    alone, not a rescued release edge. Variants are now supersets of what the key  
    already carries: the point of them is that a hold survives a modifier picked up  
    DURING it, and dropping one the binding requires is a different gesture.  
    A key bound with META gets none. It is stripped for the base but has no  
    MOD\_COMBOS entry to keep it, so every variant would have dropped the Command key  
    -- including the bare one. The first pass has already bound the key itself.  
- fix(quickdraw): give the Dynamic Rez macro an unconditional branch  
    Rez.SpellNow ends on `group or single`, so a character who knows the single rez  
    but not the group one -- one still levelling into it -- draws the single rez and  
    reports it usable. The macro had no branch to match: the group line contributed  
    nothing, leaving the conditional single-target line as the whole of it, and out  
    of combat with no dead target the entry cast nothing at all.  
    The bare line falls back the same way SpellNow does, so the two agree by  
    construction. A press with no target now says so, which is the answer the spell  
    gives from an action bar and the one the drawn icon promises.  
- fix(quickdraw): unregister RAID\_TARGET\_UPDATE with the rest  
    The marker-pip registration had no counterpart in the branch that switches the  
    module off, so disabling Quickdraw left the handler live for the rest of the  
    session -- against what the comment above EventsWanted says the off state  
    means. The event fires on every mark a group sets.  
- fix(quickdraw): pass every mouse button through the palette gates  
    The gates enabled clicks and then passed through five buttons. Blizzard names  
    Button4 through Button31 (SecureTemplates.lua:90-93), so a Select key bound to  
    a side button on an MMO mouse was swallowed for as long as a gate sat under the  
    cursor -- the floor gate covers the screen, so that is the whole of an open.  
    That is the same failure the note above GateMouse describes and the change  
    below it was meant to fix; it merely moved from every mouse button to the ones  
    past the fifth. The list is built out to the client's own ceiling instead.  
- fix(quickdraw): stop a nested marker cell from erroring on a pip refresh  
    RefreshMarkerPips passed CellSlot's result straight into MarkerPip. In final  
    argument position that call expands, and CellSlot answers a NESTED cell with  
    three values -- slot, claim, subIndex -- so the claim table landed in  
    MarkerPip's iconSize and the size arithmetic there multiplied it.  
    Top-level cells return a single value, which is what hid this: the menu had to  
    hold a nested world marker entry whose marker was on the ground, and something  
    had to move a marker while the menu was up. The nest did not even have to be  
    open, since the walk covers every cell the layout built and only the parent  
    frame's visibility is tested.  
- Clean up dead code  
- Fix warrior sweeping strike changes in 12.1  
- Update EllesmereUI\_SpecOverrides.lua  
- feat(quickdraw): mark a world marker entry whose marker is on the ground  
    A world marker entry looked the same whether its marker was down or not, so  
    nothing said whether pressing it would place the marker or pick it back up.  
    Blizzard's own manager draws the distinction, swapping its button art between  
    applied and available.  
    An accent pip in the corner the count does not use, read from  
    IsRaidMarkerActive -- unrestricted, and a plain bool rather than a secret  
    value, so it reads the same in combat.  
    The cycling world marker entry carries it too, for the marker it is about to  
    place. That position comes from CycleNext, the same function the entry draws  
    its icon from, so the pip and the icon cannot disagree about which marker is  
    on offer. The target-marker cycle is excluded: raid targets sit on units, and  
    IsRaidMarkerActive answers for world markers alone.  
    Painted on every open, which is where the value is -- firing an entry closes  
    the menu, so a press never updates a pip its presser can still see. Also  
    refreshed on RAID\_TARGET\_UPDATE, which catches the rest of the group moving  
    markers while a latched menu sits open. Not polled by the live-icon tick:  
    that pays its API calls every frame, and a cell that is not a world marker  
    never reaches the API call at all.  
    The pip, its refresh and its caller are methods rather than local functions:  
    the main chunk is at Lua's ceiling of 200 locals.  
- fix(raidframes): restore the Icon Effects per-slot gate, dropping a stray dbg global  
    FxApply gated on `dbg.gate` and wrote `dbg.ok`/`dbg.err` -- leftover  
    instrumentation whose backing table never shipped, so `dbg` was a nil global.  
    The index sits OUTSIDE the pcalls, so it threw before either path could run,  
    and because the applier runs inside the engine's CreateFrameBatch the throw  
    aborted slot creation: Icon Effects tiles on raid frames rendered nothing and  
    errored on every attempt.  
    The real gate is recoverable from the surrounding code, which documents it  
    twice: fx.filters is "the applier's per-slot gate" (live reference to the  
    tile's checked-filter set) and each slot is stamped d2.dmCat = catKey  
    "(applier filter gate)" at creation. A tile declares one slot per EVER-checked  
    category and slots cannot be un-declared, so a slot whose category is now  
    unchecked must hide. Both paths stay pcall-wrapped for batch safety.  
- docs(quickdraw): record the world marker cooldown  
    Repeating one world marker fast stalls and the game says "You can't do that  
    right now". A plain /wm macro alone reproduces it, with about four dead  
    presses between a place and a re-place, so it is a per-marker cooldown in the  
    game rather than anything this module does.  
    Clearing before placing does not work around it from a macro: the /cwm spends  
    the cooldown and the /wm behind it lands inside the window, which reads as a  
    toggle. Written down where the next reader will look for it.  
- feat(quickdraw): let a world marker entry pick its own marker back up  
    A world marker entry fired /wm, which is PlaceRaidMarker with no test, so  
    using one twice moved the marker rather than removing it. Removing anything  
    needed the separate clear-all entry.  
    Toggle World Markers, per menu and on by default, sends the entry through  
    SECURE\_ACTIONS.worldmarker instead. That action tests IsRaidMarkerActive  
    itself and places or clears accordingly, and it costs the same one attribute  
    a cell may spend: its "action" key falls back to "toggle" when unset, which  
    the snippet's clear already guarantees. Placement is unchanged -- no unit  
    token either way -- so the marker still lands under the cursor.  
    The clear-all entry and the cycling entries keep placing. A cycle step that  
    picked its marker back up would skip that marker and still advance.  
- chore(locales): regenerate \_keys.txt  
    Stale since the merge from main: 26 keys from the resource bar and profile  
    export work were never extracted. No Quickdraw strings among them.  
- Update koKR.lua  
- Update koKR.lua  
- Update koKR.lua  
- fix(quickdraw): hide a Dynamic Rez entry on a class that has no rez  
    Hide Unusable Entries exists so one menu can be shared between  
    characters, and Dynamic Rez exists for the same reason -- but the filter  
    was written before the entry and passed it through, so a mage carrying  
    the shared menu still drew a dead question mark where the rez sits.  
    Tested by CLASS rather than by what is in the spellbook right now: a  
    paladin who has not taken Intercession still has Redemption, and a druid  
    too low for Rebirth will have it soon. Hiding it on those would take the  
    entry away from the characters it is for.  
- Merge branch 'main' into quick-draw-updates  
    Upstream v8.8.3 adds "Hide Unusable Entries" to Quickdraw, which lands on  
    the same functions this branch changed. Three conflicts, resolved:  
    - PushAllPalettes and SetEventsEnabled: upstream registers SPELLS\_CHANGED  
      and UPDATE\_MACROS to re-push when the usability filter's inputs move.  
      That supersedes the three events this branch registered to rebuild the  
      Dynamic Rez macro -- a spec change, a talent swap and levelling all  
      reach SPELLS\_CHANGED -- so the rez event switch, its per-push flag and  
      the PLAYER\_ENTERING\_WORLD cold-spellbook repair are all removed rather  
      than kept alongside. The spellbook warming up after login fires  
      SPELLS\_CHANGED too, which is what the repair was for.  
    - The Dynamic Rez block and upstream's usability helpers both insert  
      after SpecIndexFor; both kept.  
    Two things the automatic merge got wrong or could not know:  
    - Layout collected its live-icon cells from palette.slots while the  
      merged PaintCell beside it draws from the filtered list. Once anything  
      is hidden the two part company and the wrong cells are collected. Now  
      reads the same list.  
    - The merged main chunk went past Lua's ceiling of 200 locals. Upstream's  
      KnownForm, SpellKnownHere and SlotUsable are private to UsableSlots and  
      are scoped into a block; usableMemo stays outside for PushAllPalettes  
      to wipe. No logic of upstream's is changed.  
- Update \_keys.txt  
- Update EUI\_Quickdraw\_Options.lua  
- Update EllesmereUIQuickdraw.lua  
- fix(quickdraw): let a mouse Select key through the nesting gates  
    A latched menu's Select key did nothing for as long as a nest was armed.  
    Nested entries could not be picked at all, and the next top-level entry  
    stayed dead until a retreat through the centre disarmed. A keyboard  
    Select key was unaffected throughout, which is what identified the gates  
    as the thing in the way.  
    The gates are hover detectors, and SetMouseClickEnabled(false) only stops  
    one from HANDLING a click -- the client still counts it as the frame  
    under the cursor, so the override binding behind a mouse Select key never  
    ran. The floor gate covers the whole screen and stands for as long as any  
    claim is armed, which is why the failure tracked arming rather than any  
    one layout.  
    Every gate -- floor, parent, region and lattice -- now goes through one  
    helper that declares the buttons not its own outright: clicks enabled,  
    and every button passed through. Same shape Blizzard's map pins use to  
    let a button reach the canvas beneath them. Older clients without  
    SetPassThroughButtons keep clicks off, which is the behaviour they have  
    now.  
    The two gate builders and their private helpers move into a block while  
    this is done. That is not tidiness: the main chunk had reached Lua's  
    ceiling of 200 locals exactly, and this buys two back.  
- fix(quickdraw): don't fire an entry when a toggle closes the menu  
    Pressing a latched menu's own keybind to put it away also cast whatever  
    the pointer was resting on.  
    The press's down edge drops the latch, which is what lets SNIPPET\_POST  
    run its teardown on the release that follows. It also means that release  
    no longer sees a latch, so the guard meant to hold a latched menu open  
    lets it through and it goes on to resolve a cell and fire it.  
    The release now recognises its own down edge by the step it left behind  
    and stops there. Nothing else writes "toggleclose", and a fresh press  
    overwrites it with "pressed" before any other release can read it.  
- feat(quickdraw): add a Dynamic Rez entry  
    One entry that is whichever resurrection spell the character holding the  
    palette has, so a menu shared across classes carries the rez once rather  
    than once per class with all but one of them dead.  
    Fired as macro text, not as a resolved spell. The attributes are written  
    out of combat and a rez has to choose its branch during the fight, so the  
    choice is left to conditionals the game evaluates when the macro runs:  
      /cast [combat] Intercession; [@target,help,dead] Redemption; Absolution  
    One fallback chain rather than a line per spell, so exactly one cast is  
    attempted. The battle rez takes [combat] only when a branch follows it: a  
    death knight or a warlock, whose only rez is the battle one, would  
    otherwise cast nothing out of combat, where that spell works.  
    Icon, cooldown, charge count and usability tint all read the branch the  
    entry would take right now, so a battle rez shows the charges a raid  
    asks it for. The per-frame icon refresh written for [mod] macros now  
    watches combat and dead-target state as well, so a menu left open across  
    a pull redraws the battle rez in place.  
    The spell IDs are a second copy of the raid frames' click-cast table  
    rather than a read across to it: that is a separate addon the user can  
    switch off, and an entry on a palette must not stop working when they  
    do. The two lists have to change together.  
    Three events rebuild the macro when what the character knows changes --  
    spec, talents, levelling -- registered only while a palette holds such  
    an entry. PLAYER\_ENTERING\_WORLD repairs the same push for a spellbook  
    that was still cold at login.  
- feat(quickdraw): toggle a menu open and choose with a Select key  
    A menu opens on key down and fires on key up, so every entry must be  
    reached in one hold. Toggle Menu Open latches the menu instead: it stays  
    up when the key is released, and a Select key uses whatever the pointer  
    is on.  
    The latch and the Select key live in the secure snippet, so both work in  
    combat. Two reserved button tokens carry the extra input to the palette  
    button: the Select key routes to \_\_CONFIRM\_BUTTON\_\_ and Escape routes to  
    \_\_CANCEL\_BUTTON\_\_, which lets a cancel run the same secure teardown a  
    normal release runs rather than leaving the override bindings claimed.  
    Both bindings are set inside the snippet with SetBindingClick, so they  
    exist only while the menu is up.  
    Toggle Menu Open is per menu; the Select key is one for the profile, so  
    the gesture means the same thing whichever menu is up. A latched menu  
    gets a 120s idle timeout instead of the normal one, and the timeout does  
    not close a latched menu during combat.  
    The keybind picker is generalized to serve both keys. Two fixes fall out  
    of that:  
    - The label is painted after the commit, not before it. The palette  
      keybind hid this because a successful commit rebuilds the page; the  
      Select key only writes the profile, so the label stayed one  
      interaction behind the value.  
    - While the picker is listening, any bare click is the chord. BUTTON1  
      and BUTTON2 were unreachable because left and right kept their widget  
      meanings in both states. Unbind is now a right-click from rest.  
- fix(quickdraw): let modifiers reach a held palette  
    A keybind matches one modifier combination exactly, and the palette performs  
    its action on the release edge -- so the modifiers held at that release were  
    pinned to whatever the bind itself required. A macro using [mod]/[nomod]  
    could only ever take one of its branches: a SHIFT- bind never the [nomod]  
    one, an unmodified bind never the other. Nothing was caching the macro;  
    RunMacro evaluates the conditionals live, against a state that could not  
    change.  
    Bind every modifier combination of a palette's key to the same secure button  
    so a modifier pressed or let go during the hold still reaches it. A  
    combination already bound to something else is left alone, and its  
    availability is part of the binding signature, so a key the player later  
    claims in the Keybindings panel is handed straight back.  
    Repaint macro icons while the palette is open whenever the modifier state  
    moves, and resolve what the macro will actually fire for one carrying no  
    icon of its own -- otherwise the palette draws one branch and casts the  
    other. A macro the player gave a real icon keeps it, the way Blizzard's own  
    action buttons do.  
