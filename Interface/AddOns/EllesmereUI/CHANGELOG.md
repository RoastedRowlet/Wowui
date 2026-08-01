# EllesmereUI

## [v8.7.1](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.7.1) (2026-08-01)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.7...v8.7.1) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.7.1  
- Merge pull request #1118 from Crazyyoungs/main  
    Update Korean translations in koKR.lua  
- Merge pull request #1117 from dfrisone/bags-unmerge-item-panels  
    fix(bags): stop merged duplicates blocking mail, and add a Merge Duplicate Items toggle  
- Merge pull request #1116 from dfrisone/uf-aura-update-remove-race  
    fix(unitframes): stop force-removed auras leaving a dead icon behind  
- Update Korean translations in koKR.lua  
- fix(bags): unmerge on the Send Mail tab, and recombine when the bags reopen  
    Two field-reported gaps in the unmerge feature.  
    Trigger: MAIL\_SHOW fires when the mailbox opens, which lands on the  
    Inbox -- reading mail never takes items out of the bags, so unmerging  
    there churned the layout for nothing, and an event fired once at open  
    cannot see a later switch to the Send Mail tab. Drive it off  
    SendMailFrame's own OnShow/OnHide instead, which covers tab switches and  
    opening straight onto Send Mail. MAIL\_CLOSED is kept only as a belt so  
    the flag cannot stick if the frame disappears without its OnHide.  
    Seeds from the live IsShown so a /reload with Send Mail already open  
    arms correctly.  
    Recombine: the flag-flip refresh is gated on the bags being visible, and  
    closing a mailbox hides the bags in the same breath, so the un-flip  
    repaint was discarded and the next open still showed split slots.  
    MergeDuplicates now stamps the state each paint was built with, and the  
    bags OnShow repaints when it no longer matches.  
- fix(bags): drop void storage events that killed the whole bags handler  
    VOID\_STORAGE\_OPEN/CLOSE no longer exist on 12.0 (void storage went away  
    with Warbands), and RegisterEvent on an unknown name is a hard Lua  
    error. The registration loop runs BEFORE EUI\_Bags gets its OnEvent  
    script, so the throw aborted the rest of StartAddon: no event handler,  
    no BAG\_UPDATE processing, display frozen at its first paint, secure  
    button pool never pre-warmed. The unmerge-on-panel feature this branch  
    adds was dead on every load, which field testing caught (1050 vials  
    mailed 1000 and the remaining 50 never repainted).  
    Remove the two dead events and pcall the rest of the registrations: a  
    panel event lost to a future patch rename must degrade to "that panel  
    does not unmerge", never to a dead bags addon. Registered names were  
    verified against the 12.0 generated event docs; void storage is the  
    only casualty.  
- Bags: add a Merge Duplicate Items toggle  
    The merge is a display choice, not something every player wants. Anyone who  
    deliberately keeps copies of an item in separate slots (vantus runes, split  
    stacks kept apart on purpose) sees them collapsed into one icon with no way  
    back short of switching to OneBag.  
    Adds Merge Duplicate Items under Bags > Display, on by default so existing  
    behaviour is unchanged. Off keeps every bag slot as its own icon. The  
    automatic unmerge while an item-management panel is open stays either way,  
    so mail and trade are correct without needing the toggle. The shift-click  
    "split stacks in OneBag" hint is also suppressed when merging is off.  
- Bags: unmerge duplicate items while an item-management panel is open  
    Category views merge duplicate non-gear items into one button showing the  
    combined count, even though the copies live in separate bag slots. That  
    button is still backed by a single slot, so any panel that takes items slot  
    by slot (mail, trade, auction house, bank, void storage, guild bank) only  
    ever receives that one slot's contents: a button reading 3 attaches 1. The  
    display reads as a stack the game never actually stacked.  
    Track those panels by their show/close events and skip the merge pass while  
    any is open, refreshing the grid when the state flips so every bag slot is  
    individually reachable. Merging resumes when the panel closes. The  
    shift-click "split stacks in OneBag" hint is suppressed while unmerged since  
    nothing is merged to split.  
- fix(unitframes): stop force-removed auras leaving a dead icon behind  
    A forcibly removed aura (dispel, trap break, absorb consumed) can show  
    up in updatedAuraInstanceIDs of the SAME UNIT\_AURA payload that removes  
    it, and GetAuraDataByAuraInstanceID then returns nil. The update loop  
    stored that nil into el.all, silently deleting the bookkeeping entry  
    while active/sorted still displayed the aura. The removal loop that runs  
    NEXT in the same payload is gated on el.all, so it skipped the id, and  
    the icon was orphaned: no tooltip (the aura truly is gone), immune to  
    the prune (which iterates el.all, where the id no longer exists), and  
    duplicated as soon as the aura was reapplied under a fresh instance id.  
    Field reports match all three symptoms.  
    The nil-store came from upstream oUF, which shares the hole but  
    constantly rebuilds its sorted list, dropping the orphan within a frame,  
    which is why this never showed before the 8.6.8 incremental edge path  
    removed those rebuilds. Reporters dating it to "the latest bug fixes"  
    were right.  
    Treat the nil fetch as the removal it really is, with the removal  
    branch's exact bookkeeping (all/\_allN/active/sorted/edgeDirty). The  
    removal loop stays consistent whether or not the id also arrives there,  
    since it only acts when el.all still has the entry.  
- Merge pull request #1112 from dfrisone/inspect-sheet-stale-ilvl-labels  
    fix(blizzskin): stop the inspect sheet showing the last target's item levels  
- Merge pull request #1111 from dfrisone/raidframes-bm-propagate-mouse-gate  
    fix(raidframes): stop a combat-born buff icon from eating click-casts  
- fix(blizzskin): stop the inspect sheet showing the last target's item levels  
    Blizzard reuses the same global slot frames for every target, and the  
    per-slot labels were create-once: the guards read "not  
    GetFFD(slot).iLvlText", so while a previous target's label survived,  
    every styling pass was a no-op and the old numbers stayed next to the  
    new target's icons.  
    Only RefreshSlotStyles cleared, and it is reached solely from  
    INSPECT\_READY behind an InspectFrame:IsShown() check. InspectFrame\_Show  
    calls HideUIPanel and it is Blizzard's own INSPECT\_READY handler that  
    calls ShowUIPanel, so on the opening event the frame is still hidden and  
    that check always bails. The clearing pass is skipped by construction  
    every time a sheet opens, and the labels are only ever corrected if a  
    second INSPECT\_READY happens to arrive while the sheet is up. That is  
    the whole of the reported intermittency, and why re-inspecting the same  
    person guarantees nothing.  
    Clear in EUI\_UpdateSlotStyle instead, so every styling pass rebuilds  
    from the live item link no matter which path calls it. Covers the  
    enchant and upgrade-track labels, which had the identical pattern.  
- fix(raidframes): stop a combat-born buff icon from eating click-casts  
    The Buff Manager pools are built lazily, so the first BM update inside a  
    pull creates them mid-combat. SetPropagateMouseMotion/Clicks are blocked  
    there, so the wiring is queued for a PLAYER\_REGEN\_ENABLED pass. But the  
    hover was still allowed to take the mouse in the meantime: a frame that  
    is mouse-enabled and not yet propagating swallows motion AND clicks, so  
    click-casting died over that 12px icon for the rest of the fight.  
    Gate the mouse on the propagation having actually landed, and re-arm the  
    hover from the REGEN pass so an opted-in tooltip comes back as soon as  
    combat drops rather than on the unit's next aura event.  
    The delve report that surfaced this also pins the entry path:  
    SecureGroupHeader\_Update is not combat-gated by Blizzard, so its  
    SetAttribute("unit") drives our OnAttributeChanged hook into pool  
    creation on any roster or name update, in combat or out. Noted in the  
    comment so the deferral is not mistaken for a rare edge.  
