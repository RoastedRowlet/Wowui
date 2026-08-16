# Grid2

## [4.0.12](https://github.com/michaelnpsp/Grid2/tree/4.0.12) (2026-08-15)
[Full Changelog](https://github.com/michaelnpsp/Grid2/compare/4.0.8...4.0.12) [Previous Releases](https://github.com/michaelnpsp/Grid2/releases)

- Icons indicators: now smartcenter option is always enabled in aura mode.  
    Small code style change in UpdateAuraContainers() function.  
- Merge pull request #443 from KogasaPls/fix/aura-containers  
    Fix aura containers collecting other units' auras  
- Fix aura container size in icons indicators.  
- Match the aura sorting options to AuraContainerSortMethod  
    The stored sortRule is handed straight to AddAuraGroup/AddAuraSlot as  
    sortMethod, but the dropdown was keyed one below Blizzard's enum, so every label  
    named the wrong comparator: "Default" applied BigDefensive, "Big Defensive"  
    applied UnitFrameDebuff, "Expiration" applied ImportantOnly, and "Unsorted" did  
    not exist at all, 0 being Default. ValidateSortOptions accepts any in-range  
    number, so the mismatch was silent.  
    Keys now match the enum, and the members that were unreachable are listed.  
    Values are not migrated, so a status configured under the old labels keeps the  
    comparator it has been using and simply shows the right name for it.  
    UnitFrameDebuff is listed for completeness but sorts as Default here: it  
    compares auraData.debuffType, which AuraUtil.ProcessAura only fills in under the  
    ProcessAura policy, and these containers are left at the default policy of None.  
- Keep auraMode and iconMode balanced when an indicator wakes  
    Grid2:WakeUpIndicator() calls status:RegisterIndicator(indicator) without a  
    priority. RegisterIndicator resolves one for its own bookkeeping but forwarded  
    the raw argument to indicator:StatusChanged(), which reads a missing priority as  
    an unregistration, so every wake decremented the counter it should have raised.  
    An indicator suspended and woken once by a theme change ends up at -1 with one  
    aura status linked. That stays truthy so Icon\_Layout keeps taking the aura path  
    by luck, but linking another status lands it on exactly 0, where the counter is  
    cleared and the indicator silently drops its aura container and stops drawing.  
    Unlinking instead leaves it truthy with no aura status left, and both  
    Icon\_LayoutAura and Bar\_Layout then index a nil filter.  
    Forward the resolved priority instead.  
- Bind aura containers when they are created  
    Blizzard\_AuraContainer.xml gives every new AuraContainer the KeyValues  
    enabled=true and unitToken="none". It registers no unit events until it has a  
    group or a slot, but once one is added those registrations go through  
    FrameUtil.RegisterFrameForUnitEvents, which calls RegisterUnitEvent(event,  
    "none"), and that does not filter: the container receives UNIT\_AURA for every  
    unit. ProcessUnitAuraUpdate then adds whatever arrives, keyed on the event's  
    token, without ever comparing it to its own. A container parked at "none"  
    collects auras from everyone nearby.  
    Verified against a live client: a container left at its birth state next to one  
    bound to the player fills with other units' auras.  
    Grid2 created containers and left them that way. UpdateAuraContainers is the  
    only binder, and it runs from a frame's unit change, a unit removal, the  
    UNIT\_FACTION hook and Grid2Options:UpdateIndicator, never from the layout that  
    creates them. Icon\_LayoutB builds a fresh container on every layout pass with  
    its parent already shown, and the options relayout paths walk registeredFrames  
    including frames with no unit, so a relayout left live "none" containers behind  
    until that frame's unit next changed, which may be never. Each of them  
    accumulated the same aura stream, which is how a block of frames ends up  
    showing one identical aura set, with matching countdowns, that none of those  
    units has.  
    Bind at creation instead: to the frame's unit if it has one, otherwise parked  
    disabled and hidden, which suppresses the registration entirely. Binding before  
    the group exists means the eventual registration picks up the right unit.  
    UpdateAuraContainers used to leave a container alone when its token already  
    matched, which is exactly how one sitting at "none" for a frame with no unit  
    stayed enabled, so the unbound case now disables explicitly.  
- Icons indicator: Fixing wrong icons centering in aura mode when CENTER, TOP, BOTTOM, LEFT, RIGHT anchor points were selected.  
    Icons indicator: Disabled smartcenter option in settings when the indicator is displaying auras, to center the icons for auras you must  
    select CENTER, TOP, BOTTOM, LEFT or RIGHT anchor points (depending of the desired row orientation).  
- Implemented new bar(auras) indicator, this new bar can display remaining time/elapsed time for buff/debuffs statuses.  
- Fix for auras not displayed after watching cinematics.  
- Merge pull request #440 from KogasaPls/fix/icon-aura-border-without-icon  
    Fix icon indicator painting a filled square instead of a border  
- Merge pull request #441 from KogasaPls/fix/icon-cooldown-text-status-color  
    Fix cooldown text status coloring issues from #437  
- Merge branch 'main' into fix/icon-cooldown-text-status-color  
- Fix cooldown text status coloring issues from #437.  
    - Use the status hue at full alpha instead of the status alpha. Status colors  
      are configured for the icon and border, where a low alpha is useful; applied  
      to the countdown text it made the text unreadable with no way to override it.  
    - Disable the cooldown text color picker instead of hiding it, matching the  
      "Cooldown Colors -> Cooldown Text" setting, so it stays visible while inert.  
    - Add a description to the "Use Status Color" toggle. The icon border option  
      uses the same name, and the two were indistinguishable in the same panel.  
    - Fetch the status color once per aura in the icons indicator frame update  
      instead of calling GetColor() twice, and hoist the flag out of the loop.  
    - Drop a redundant branch: UpdateDB() already clears ctOptions when the status  
      color is in use.  
- Fix icon indicator painting a filled square instead of a border.  
    The aura container border texture covers the whole button and relies on the  
    icon to mask its center, so it only reads as a border when a border size is  
    set to inset the icon by. With no border size and the icon hidden there was  
    nothing to mask it, and the whole button was painted with the border color.  
    Also fixes the cleanup branch, which tested an unset self.border and called  
    Hide() on an undefined global, so a stale border texture was never hidden.  
- Now auras cannot be linked to background indicator.  
- Now aura statuses cannot be added to glowing-border indicator.  
- Small fixes in cooldown text colors management code.  
- Merge pull request #437 from KogasaPls/feat/icon-use-status-color  
    Add status color option for icon cooldown text  
- Now shape indicator uses the auras dispel type color.  
    BugFix: Dispel Border not visible with non integer border sizes.  
- Add status color option for icon cooldown text.  
    When enabled, cooldown text uses the status color instead of the  
    indicator's configured cooldown text color.  
    Disables the indicator-level cooldown text color controls while status  
    coloring is enabled.  
