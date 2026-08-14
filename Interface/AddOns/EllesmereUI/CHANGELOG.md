# EllesmereUI

## [v8.8.6](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.8.6) (2026-08-13)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.8.5...v8.8.6) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.8.6  
- Merge pull request #1282 from DlargeX/main  
    delete double entrys, optimizations, add missing German Locals  
- Update \_keys.txt  
- Merge remote-tracking branch 'upstream/main'  
- Update deDE.lua  
- Merge pull request #1389 from dfrisone/cdm-buff-placeholder-tooltip  
    fix(cdm): no tooltip or mouse capture on an invisible buff placeholder  
- Merge pull request #1388 from labrie75/l10n-wrap-the-Bags-right-click-menu,-ETC  
    l10n: wrap the Bags right-click menu, prompts, bank headers and warbank tab prefix  
- Merge branch 'main' into l10n-wrap-the-Bags-right-click-menu,-ETC  
- Merge pull request #1387 from dfrisone/cdm-pandemic-glow-hidden-icon-flash  
    fix(cdm): pandemic glow flashed on every fresh cast  
- Update deDE.lua  
- Update deDE.lua  
- Merge pull request #1384 from nulltyto/fix/quickdraw-bugs-2026-08-12  
    Quickdraw: ten reported items -- picker filters, nest reach, menu caps, presets  
- Update deDE.lua  
- Update deDE.lua  
- Update \_keys.txt  
- Update EllesmereUIBags\_Bank.lua  
- Update EllesmereUIBags.lua  
- fix(cdm): stop an invisible buff placeholder capturing the mouse  
    An alpha-0 placeholder stayed a live mouse target, so a reserved slot for  
    an inactive buff took mouseover from whatever the bar sits over (raid  
    frame hover highlight, [@mouseover] casts). Blizzard hides its own  
    inactive items, so those slots hold no frame at all; reserving them is  
    what makes the whole grid a permanent capture surface.  
    Fold the alpha-0 rule into one predicate, IsPlaceholderRenderHidden, and  
    use it in the three opacity passes plus both mouse passes. The collect  
    pass now owns mouse state for our own placeholder frames at the point  
    they are injected, so turning Keep Buffs in Same Place back off restores  
    capture on the next collect instead of latching it off.  
- Merge remote-tracking branch 'upstream/main'  
- fix(cdm): no tooltip on an invisible buff placeholder  
    Keep Buffs in Same Place reserves every tracked buff's slot with a  
    placeholder frame rendered at alpha 0. The frame stays shown and  
    mouse-enabled, so hovering an inactive buff's empty slot still ran the  
    placeholder OnEnter and showed the spell tooltip. Bail out of OnEnter  
    for the same two flags the opacity passes test before forcing alpha 0  
    (hidePlaceholderIcon and the hosted \_missingHidden).  
- add 8.8.4 German Locals  
- Merge remote-tracking branch 'upstream/main' into cdm-pandemic-glow-hidden-icon-flash  
- Merge pull request #1383 from labrie75/koKR-catch-up-8.8.5  
    koKR: catch up 8.8.5 additions (+158 keys)  
- Merge pull request #1386 from labrie75/l10n-translate-Buff/Debuff-Manager-filter-names  
    l10n: translate Buff/Debuff Manager filter names and the input placeholder  
- fix(cdm): ignore a pandemic window whose aura already ended  
    Clearing our flag on hide is not enough when the aura ends early rather  
    than running out. Blizzard computes the pandemic window when the aura  
    lands and never clears it on the way out, and the item stays registered  
    for the viewer OnUpdate, so a window whose aura is gone keeps satisfying  
    IsInPandemicTime and re-sets the flag on the hidden icon a frame later.  
    Re-apply inside that leftover window and the glow lights over a fresh  
    aura until the dead aura's end time passes.  
    Mark the flag unusable from the hide until the item computes a new  
    window, and only when the aura really ended (auraInstanceID is cleared  
    before the icon hides, while a bar merely hiding leaves it set) so a  
    visibility toggle mid-pandemic keeps its glow.  
- Add files via upload  
- Merge remote-tracking branch 'upstream/main'  
- fix(cdm): stop the pandemic glow when its buff icon hides  
    The buff tick only visits shown frames, so the glow's stop branch was  
    unreachable at the one moment it is always needed: the aura runs out,  
    Blizzard hides the icon, and the glow keeps animating on the hidden  
    overlay. It came back up with the icon on the buff's next application,  
    flashing a pandemic glow over a freshly cast aura until the next tick.  
    Take the glow down from the icon's OnHide instead, and drop Blizzard's  
    pandemic flag with it so a stale true cannot re-light it. Both re-arm  
    from Blizzard's next ShowPandemicStateFrame. The hook installs lazily  
    with the overlay, so a bar with no pandemic glow still pays nothing.  
- Update EllesmereUI.lua  
- Update EUI\_PlayerAuraBars\_ManagerPages.lua  
- Update EUI\_RaidFrames\_ManagerPages.lua  
- chore(quickdraw): regenerate locale keys for the new strings  
    Three new keys: the preset menu's "did not fit" count, the picker's  
    "favorite" search keyword, and the editor tooltip's note about entries a halo  
    nest cannot show.  
    The tooltip string moves onto the Lf line to be harvested at all -- the  
    extractor reads one line at a time, so a literal wrapped onto the next line  
    is a key it never learns about.  
- feat(quickdraw): search pickers by source and favorite, not only name  
    A picker holding several hundred rows that can only be searched by name can  
    only be searched by someone who already knows the name of the thing they  
    want, which is the opposite of what a search is for.  
    An entry may now carry keywords beside its name, and the filter matches  
    either, with the same plain substring test -- so "vend" finds a vendor mount  
    the way "sea" finds a seahorse. Keywords are built once with the list, which  
    the picker caches per session, so nothing was added to the typing path.  
    Mounts carry their source and whether they are a favorite. Toys carry  
    favorite alone: the toy API returns no source for an individual toy, and a  
    source guessed from anywhere else would be a made-up answer in a search box.  
    The source label is the client's own BATTLE\_PET\_SOURCE\_n string, the one the  
    collection journals label their own source filters with, so a localized  
    client searches in its own words.  
    Both pickers say so: a search that reaches further than the user expects is  
    worth nothing if the only way to find that out is to guess it, so their  
    placeholder reads "Search name, source, favorite..." rather than "Search...".  
    A search box rather than filter controls: the box is already on every picker  
    and costs nothing to learn, where a filter bar is a second thing to discover  
    and would need per-picker design for four pickers.  
    Closes QD-09.  
- feat(quickdraw): add a Quest Items preset  
    Builds a menu from the usable quest items the character is carrying, so they  
    get a keybind without being placed by hand.  
    It walks the bags for the quest item class and keeps only items with a use  
    effect -- an item without one is a quest object being carried, not something  
    an entry can fire -- then folds in the quest log's own special items. Those  
    are the ones the objective tracker draws a button for, and they are not  
    always in the quest item class: a trinket or a toy handed out for a single  
    quest reads as its own class and the bag walk alone would miss it. The link  
    is the first return of GetQuestLogSpecialItemInfo; the second is the button's  
    texture, not an id.  
    A snapshot, like every other preset. A menu that refills itself as the bags  
    change is a second feature: a menu's entries are a stored array the editor  
    owns, so it needs a dynamic flag on the palette, a generator behind  
    UsableSlots, memo invalidation and a coalesced re-push on bag and quest-log  
    events, and an editor that refuses to let a generated menu be edited. The  
    scan itself, which is the part this shares, is done. Recorded in the bug  
    report rather than half-built here.  
    Closes QD-07a.  
- feat(quickdraw): add a Professions preset  
    A preset rather than a new slot kind: a profession's window opener and its  
    second ability are both ordinary spells, so the preset is a list of spell  
    slots and everything downstream already handles them.  
    It walks GetProfessions() -- all five slots, so cooking, fishing and  
    archaeology arrive alongside the two main professions -- and takes the spells  
    the profession book itself offers for each. That is where smelting,  
    prospecting, milling and runeforging live, so they are picked up without  
    naming any of them. Passive entries are skipped: a profession's passive is a  
    rank, not something an entry can do.  
    Read out of the spellbook rather than from a list of spell IDs, which is the  
    walk Blizzard's own profession book makes. A hard-coded list would go stale  
    with each expansion's skill lines and the preset would simply stop offering a  
    profession, silently.  
    The five slots are passed one at a time rather than gathered into a table: a  
    character missing a profession hands back a nil in the middle of those  
    returns, and a table constructor holding one stops counting there.  
    Closes QD-07b.  
- feat(quickdraw): add a Last Used Mount entry  
    An entry that summons whatever mount the player rode last, offered in the  
    mount picker beside the random-favorite roll. Both are kinds rather than  
    mounts, so both are pinned above the collection: there is nothing in the list  
    to pick for either.  
    Blizzard records no such thing -- the whole C\_MountJournal surface answers  
    only what is summoned right now -- so it is observed. Every successful player  
    cast is handed to GetMountFromSpell, which answers with a mountID for a mount  
    summon and nil for everything else, so the filter and the answer are one  
    call; Blizzard's own mount UI watches the same event.  
    The handler returns immediately while InCombatLockdown() is true. The event  
    fires for every cast the player makes and a payload read in combat may be a  
    secret value; nothing is missed, because no mount can be summoned then  
    anyway. A change re-pushes through RequestPush, which coalesces and defers  
    like every other push, so a mount cast costs everyone else one comparison.  
    Firing rides the existing insecure branch -- SummonByID with the stored ID  
    instead of 0 -- so there are no attribute writes, no snippet changes and no  
    combat debt. Before anything is tracked the entry falls back to the random  
    favorite rather than doing nothing, an entry that answers a press with  
    silence reading as broken.  
    Stored on the profile, so it is not blank at the start of a session. A  
    profile shared between characters shares the memory, and the game refuses a  
    summon the character cannot make with its own message.  
    Closes QD-07d.  
- feat(quickdraw): raise the menu cap to 16 and lift the arc's nest cap  
    Twelve was what a ring of the SETTING'S OWN radius could seat: at the shipped  
    100 with a 50-unit pitch the thirteenth entry overlaps its neighbour. So make  
    Menu Radius a minimum instead. PaletteView:Geom now derives the arc's radius  
    from the entry count and takes the larger of that and the setting. Nothing  
    moves for an existing menu: a count that already fitted never reaches the  
    floor.  
    The separation the radius is derived from is a square's, not a disc's. Two  
    axis-aligned squares only clear each other once their centres are a full icon  
    apart along x or along y, so a pair whose chord runs diagonally needs  
    iconSize * root 2 between centres -- more than a pitch at the shipped sizes.  
    A ring held to the pitch alone still touched at the four diagonals and  
    nowhere else. Consequence worth knowing: a menu of twelve or more at the  
    shipped radius of 100 now grows, twelve to 109 and sixteen to 145. Those  
    menus were overlapping at the corners before, at every count from twelve up;  
    the growth is that overlap being paid for. Menus of eleven or fewer are  
    untouched.  
    With the radius growing, the cap answers to how many entries a person can  
    still aim at rather than to how many fit. Sixteen, which is 22.5 degrees each  
    on a full circle.  
    The arc's nested menus are uncapped with it: an arc claim rings its children  
    and adds a ring as they crowd, which is ground of its own to grow into, the  
    same thing the lane and the strip have. The halo keeps eight, because it IS  
    eight fixed positions around a cell and there is no ninth to put a child in.  
    That rule is stated once, in NestChildCap, and ChildGeom asks it rather than  
    carrying a second copy -- a copy is how the lift once landed in the editor's  
    tooltip and nowhere the player could see it. The tooltip does say how many a  
    nested menu is not showing, so the one real cap is met with a label rather  
    than by counting.  
    REGION\_MAX is re-derived, which is the true cost of the lift. Swept over  
    330,692 arrangements at the new cap, 9 leaves 9,635 claims over budget and 14  
    leaves 239; 18 would leave none, at four more gate frames and eight more  
    wrapped scripts on every claim. 14. Its comment now carries the sweep and  
    says the number is an output of the shapes below it, to be re-derived  
    whenever any of them moves, and the harness is pinned to the shipped value --  
    a sweep left at a different one proves something about a build that does not  
    exist.  
    Preset truncation is no longer silent: a builder returns what it found and  
    how many it left out, and the preset menu says "4 did not fit". A hearthstone  
    past the cap is a destination the player has lost, unlike a toy that shares  
    its cooldown with the ones that got in.  
    MAX\_CHILD\_ROWS stays at 4 -- four rings hold more than a nested menu can now  
    contribute. The widget pool and the saved-variable clamp both read MAX\_SLOTS  
    and needed nothing; raising a ceiling cannot invalidate a stored profile.  
    Closes QD-08 and QD-03 (reported by @Shaikhain, and Discord).  
- feat(quickdraw): add a Menu Cancel Action keybind  
    Backing out of an open menu was Escape and nothing else, and the hand  
    holding the menu key is nowhere near Escape. Right-click, which is what  
    people reach for, was simply unbound and so did nothing.  
    Add a Menu Cancel Action key, profile key cancelKey, unbound by default.  
    Escape keeps working and stays hard-wired; this is a second key for it, and  
    a plain mouse button is the point.  
    It is bound the way the Select key already is: an override binding owned by  
    the shared cancel button, claimed for exactly as long as a menu is up and  
    handed back by the one ClearBindings on close, so the button keeps its  
    ordinary use the rest of the time. It rides whichever of the two existing  
    routes the open is using -- a latched menu's cancel closes the menu itself,  
    a held menu's raises the flag its own release reads -- so no teardown moved  
    into Lua and no protected call was added.  
    Two chords are refused: the Select key, which would leave one chord meaning  
    two things, and any key that opens a menu, which would take that key for the  
    moment its own release has to reach the menu and leave it stuck open.  
    For the record, the report's premise was not the reason: CONFIRM\_BUTTON and  
    CANCEL\_BUTTON are internal tokens an override-binding click arrives under,  
    on a button with EnableMouse(false), not user bindings. Right-click was  
    never confirm, middle-click never cancelled, and confirm was already  
    configurable through the Select key.  
    Closes QD-01 (reported by @CallMeEddy).  
- fix(quickdraw): draw stack counts on whole pixels, inside the icon  
    A font height is given in the string's own units and drawn at that height  
    times its effective scale, so a palette scaled to anything but 1 asked the  
    client for a fractional pixel height. A glyph rasterised between two pixels  
    is resampled and reads soft and stair-stepped, while the icon beside it is a  
    texture and resamples cleanly -- which is exactly the report: the counts  
    looked pixelated and the icons did not.  
    ApplyModuleFont now snaps the height to whole physical pixels against the  
    string's own effective scale, through PP.perfect, the same constant the  
    borders are drawn on. At 1080p a palette at scale 1.25 asked for 17.5 pixels  
    and now asks for 18; scale 1 and 1.5 were already whole, which is why this  
    looked intermittent. The banked size is untouched, so the snap follows a  
    font-settings refresh and a scale change alike, and Layout re-applies the  
    fonts when the palette's scale actually moves.  
    The count is also held on both bottom corners now instead of one, so a wide  
    stack can no longer run off the icon it belongs to, with word wrap off so a  
    clamped count cannot climb onto a second line. Shrinking the text to fit is  
    not available: a count may be a secret value, and a secret FontString  
    refuses text access to a tainted caller, so nothing here may measure it.  
    Closes QD-10 (reported by @Fruit).  
- fix(quickdraw): arm an arc nest from the claim's own ground  
    An arc claim could only be armed by the cursor crossing its parent's ICON  
    box. That box is 40 units across at a radius of 100 -- about eleven degrees  
    -- while a claim's children spread up to forty-five degrees either side of  
    it, so a straight line from the palette's centre to a child mostly misses  
    the icon and the nest never opened. A claim with two children could not be  
    reached directly on any arc size, which is what the report shows.  
    Arming now asks the same question the disarm has always asked: is the cursor  
    on this claim's ground, measured polar. Three changes, all confined to  
    ANGULAR mode:  
    - the arc's region gates go up with the palette rather than on arming, and a  
      disarm leaves them up, so there is something under the cursor to raise an  
      OnEnter on the claim's own ground;  
    - a region gate's OnEnter carries the ground test, and asks it of EVERY  
      claim rather than only its own. The arc's region rects are generous and  
      overlap around the ring, and mouse focus is topmost-wins among frames on  
      one level, so a gate answering only for itself would let the rect on top  
      shadow the claim underneath it;  
    - a stale region gate is not hidden on the arc, that being the way in.  
    Claim grounds OVERLAP -- a wedge widens as it goes out, and one claim's beam  
    crosses its neighbour's wedge near the ring -- so the ground test needs a  
    rule for who wins where two hold the cursor at once. Taking the first claim  
    found handed a reach past a nest's own icons to whichever neighbour also  
    covered that point, lowest index winning, which put 12 o'clock in front of  
    everything its wedge reached over. Two rules instead: the armed claim keeps  
    the cursor while it still holds it, so a reach into a nest cannot be taken  
    away mid-reach, and where nothing is armed the claim whose own axis the  
    cursor is nearest wins.  
    The polar test and the cursor-offset maths become two shared fragments  
    rather than one copy each, the arm and the disarm having to measure the  
    identical ground the identical way. Both sit inside a do block with the  
    snippet builders, so neither costs a main-chunk local.  
    Reaching an arc nest at all made a second thing plain: an entry that opens a  
    menu was drawn exactly like one that fires an action, so the only thing  
    saying a nest existed was the nest itself, drawn faintly whenever the  
    selection touched its parent. On the arc both sit in the same ring, which put  
    a second set of icons over the open nest's own. Say it on the entry instead  
    -- three dots in the corner nothing else uses, on any entry that opens a  
    menu, at every size and on every layout, sized from the icon and snapped to  
    physical pixels like the borders. The preview state is gone entirely: one  
    nest is drawn, the armed one, and an entry answers "is there more behind  
    this" before it is touched rather than after.  
    Verified offline: the generated snippet text is byte-identical to HEAD's for  
    a parent gate's OnEnter, and the parent and floor OnLeave variants differ  
    only in the rename the shared fragment needs and one mode guard. Every  
    generated body compiles.  
    Adds .tools/quickdraw-nest/arc-reach.lua, the model the numbers came from.  
    Closes QD-05 (reported by @Nollychi).  
- fix(quickdraw): keep the corridor between an entry and its nest  
    A claim's region rects cover the ground it stays armed on: its own cell, its  
    nest, and a corridor across the gap between the two. AddRegion drops any  
    piece that neither holds a child nor touches the parent cell, that piece  
    being on the far side of another claim's entry -- but it asked with  
    BoxesMeet, a strict overlap test, and a corridor never overlaps the parent  
    cell at all. CorridorBox starts it at that cell's outer edge, so the two  
    share an edge exactly. The corridor was read as disconnected and dropped,  
    and the pointer crossed unarmed ground on its way to every child.  
    The filter only runs when another claim puts a hole in play, so one nesting  
    entry behaved and two did not. That is the reported case: a grid whose  
    entries fit one row, with two of them nesting.  
    Ask an edge-sharing question instead. BoxesTouch counts a shared edge and  
    not a shared corner -- a corner is not ground a cursor can cross, and a  
    piece reachable only past one is what the filter exists to drop. It sits  
    inside a do block with its only caller: the main chunk is a couple of locals  
    short of Lua's ceiling of 200.  
    The defect was not confined to the reported layout. Over a sweep of 227,172  
    configurations -- every block layout, 2 to 12 entries, every arrangement of  
    up to four nesting entries, 1 to 12 children each, auto and pinned columns --  
    configurations with at least one reach across unheld ground fall from 55,620  
    to 0 for the halo and from 65,257 to 8,405 for the perimeter lane; the strip  
    nests the report is about go to 0. The remainder is dense lanes whose claims  
    were already past REGION\_MAX before this change.  
    Adds .tools/quickdraw-nest, the harness that measured all of it. It cuts the  
    geometry out of the module by function name, so it cannot go stale against  
    line numbers, and it reports the worst region count a claim came to -- the  
    sweep REGION\_MAX's own comment refers to.  
    Closes QD-04 (reported by @Shaikhain).  
- fix(quickdraw): show every owned toy in the toy picker  
    The toy picker walked GetNumFilteredToys/GetToyFromIndex, which is the  
    enumeration the player's own Collections filters leave standing. Any filter  
    set in the Toy Box carried into the picker, and "Not Collected" emptied it  
    outright -- a toy outside the filter could not be picked at all.  
    Widen the filters for the length of the walk and put them back afterwards.  
    ScanToysUnfiltered banks collected/uncollected/unusable shown, every source  
    and expansion filter, and the search string, clears them, forces a refilter,  
    runs the scan, then restores all of it and forces another. The scan runs  
    inside pcall and the error is re-raised after the restore, so a fault cannot  
    leave the player holding the picker's filters. An open Toy Box is redrawn  
    with the same pair its own filter menu calls.  
    GetToyFromIndex is an index into the filtered list, so pairing it with  
    GetNumToys is not an unfiltered enumeration and was not used.  
    The walk runs once per picker session, behind the existing picker cache.  
    Closes QD-06 (reported by @Mittoa).  
- fix(quickdraw): offer every collected mount in the picker  
    The mount picker filtered on the isUsable return of GetMountInfoByID, and  
    that return moves with where the player is standing: an aquatic mount is  
    unusable on dry ground, so it was absent from the picker until the player  
    swam. Mounts could only be picked in the place they could be ridden.  
    Drop isUsable from the filter and keep isCollected and not hideOnChar.  
    Which mounts can be summoned right now is a run-time question, not a  
    pick-time one.  
    The comment claimed isUsable was a permanent character capability. It is  
    not: the Mount Journal has a MOUNT\_JOURNAL\_USABILITY\_CHANGED event, rebuilds  
    its list on it, and gates its Summon button on the same return. Comment  
    rewritten to say why the return is not read.  
    Closes QD-02 (reported by @Hydranide).  
- Update koKR.lua  
- Merge pull request #1382 from tenngoxars/zhcn-8.8.5  
    locale(zhCN): update translations for 8.8.5  
- locale(zhCN): translate 8.8.5 UI strings  
- Merge pull request #1380 from Barbiero/locale/ptbr-updates  
    ptBR: translate Minimap, Mythic+ Timer, Chat, and a some shared texts  
- Merge pull request #1379 from Crazyyoungs/main  
    Update Korean localization for new features  
- Merge pull request #1381 from dfrisone/border-forbidden-layout-aspect  
    fix: guard border and tooltip skin against inherited forbidden layout aspects  
- Merge remote-tracking branch 'upstream/main' into border-forbidden-layout-aspect  
- ptBR: translate Minimap, Mythic+ Timer, Chat, and shared Visibility Options  
- Merge pull request #1378 from LoChinAn/locale-zhtw-8-8-5-cast-bars-range-checks  
    locale(zhTW): translate 60 keys for v8.8.5, unify the Tick + Bar wording  
- Update Korean localization for new features  
    Added new localization strings for housing and cooldown features.  
- Merge remote-tracking branch 'upstream/main' into border-forbidden-layout-aspect  
- fix(skins): probe tooltip restrictions before the skin pass  
    Same window as the border fix: while a tooltip is anchored to a forbidden  
    UI-widget owner, the reskin's own reads raise. \_ttSkin asked for the width  
    to test it for secrecy, \_ttFonts asked for the name, and the configured  
    border asked the owner for its frame level, each of which is the first  
    widget call on that path. Route all three through pcall and skip the pass  
    when the read is denied; the owner's level is now read once and reused.  
- Merge pull request #1377 from dfrisone/abr-pet-reminder-mounted  
    fix(abr): stop the Missing Pet reminder while mounted  
- fix(core): guard border restyle against forbidden layout aspects  
    A Blizzard UI widget anchors the tooltip it owns to a forbidden frame on  
    hover. UntrustedLayoutScriptExecution propagates to that frame's children  
    and to anything anchored to it, so a textured border hung off the tooltip  
    inherits it and every widget call from our tainted code raises, the size  
    read included. Read the size through pcall and skip the pass when it  
    fails, and probe once at the top of ApplyBorderStyle so a restyle landing  
    in that window leaves the last-good border instead of erroring.  
- locale(zhTW): translate 60 keys for v8.8.5, unify the Tick + Bar wording  
    Incremental pass over the 58 commits since v8.8.4. Most of it is the new  
    Mythic+ Tools work: targeted spell bars, the standalone target/focus cast  
    bars, and the nameplate range checks with their CPU-cost warning. The rest  
    is spread thin -- housing and mounted visibility conditions, the minimap  
    auto zoom reset, comma-separated tick marks in the Cooldown Manager, the  
    damage-meter timer lock, and the character sheet and socket panel strings.  
    Terms follow the client where the client has one: BINDING\_NAME\_NAMEPLATES  
    for the keybind a nameplate tooltip refers to, INVTYPE\_FINGER / \_CLOAK /  
    \_CHEST for the equipment slots. The two cast-bar preview spell names stay  
    English, matching the preview list they sit in.  
    Two existing values are rewritten. The two sentences describing the  
    interrupt-ready hint quoted "Tick" and "Tick + Bar" in English while the  
    dropdown they name has been 刻度 / 刻度 + 長條 all along, so the sentence  
    named something the reader never sees. Both sentences now quote the  
    dropdown, and the dropdown value itself moves from 長條 to 計量條 to match  
    how the other cast-bar options in that panel read.  
    Not a completeness pass: strings assembled at runtime stay invisible to a  
    static scan.  
    Compiles under Lua 5.1, round-trips through the catalog parser, zhTW has  
    no duplicate keys, file stays UTF-8 without BOM.  
- fix(abr): stop the Missing Pet reminder while mounted  
    Mounting auto-dismisses the pet in the open world and the server  
    resummons it on dismount, so the reminder was pure noise for the whole  
    ride. Skyriding already hid it because Refresh() hides everything when  
    mounted and flying, which is why it only showed on the ground.  
    Skip the reminder while IsMounted(), plus a 2s grace after the mount  
    display drops (the pet returns a beat later), with a scheduled refresh  
    so a genuinely absent pet still reports once the grace expires.  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main'  
- Update deDE.lua  
- Update deDE.lua  
- Merge remote-tracking branch 'upstream/main'  
- Update deDE.lua  
- Merge remote-tracking branch 'upstream/main'  
- add more missing German locals  
- Merge remote-tracking branch 'upstream/main'  
- Update deDE.lua  
- Update deDE.lua  
- Update deDE.lua  
- Update \_keys.txt  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main'  
- Merge remote-tracking branch 'upstream/main'  
- Update deDE.lua  
- Update deDE.lua  
- Update deDE.lua  
- Merge remote-tracking branch 'upstream/main'  
- Update deDE.lua  
- Merge remote-tracking branch 'upstream/main'  
- delete double entrys, optimizations  
