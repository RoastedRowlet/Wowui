# EllesmereUI

## [v9.0.6](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.0.6) (2026-08-26)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.0.5...v9.0.6) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.0.6  
- Merge pull request #1747 from notey-dev/aurabuffreminders-paladin-rites-1click  
    feat(aurabuffreminders): updated paladin rites to be 1click use  
- Merge pull request #1746 from dfrisone/fix/blizzskin-repair-hammer-durability-refresh  
    Fix char sheet durability not refreshing after self-repair items  
- Merge pull request #1745 from dfrisone/fix/pet-name-color-login-race  
    Fix pet frame name color reverting to wrong color on login  
- Merge pull request #1744 from JuJuFX-dev/feature/tsb-interrupt-visuals  
    Feature(Myhtic+ Tools): Add interrupt awareness, range fade, and raid markers to Targeted Spell Bars  
- feat(aurabuffreminders): updated paladin rites to be 1click use  
- Fix char sheet durability not refreshing after self-repair items  
    UPDATE\_INVENTORY\_DURABILITY isn't handled anywhere in Blizzard's own  
    retail UI; the minimap durability alert icon refreshes off  
    UPDATE\_INVENTORY\_ALERTS instead. Register that alongside the existing  
    event so a repair hammer toy updates the sheet immediately.  
- Fix pet frame name color reverting to wrong color on login  
    Pet text-color styling ran once at frame creation, before the pet unit  
    was resolvable. Reapply it on UNIT\_PET, same fix already in place for  
    targettarget/focustarget.  
- Add interrupt awareness, range fade and raid markers to Targeted Spell Bars  
    Targeted Spell Bars was the only cast-bar surface in the suite with no  
    interrupt awareness at all, discarding the notInterruptible flag on every  
    cast read. Ports the kick-ready tint, uninterruptible wash and important-cast  
    tint from Target/Focus Bars, adds an out-of-interrupt-range fade and a raid  
    target marker, and gives the important-cast glow a cheaper implementation  
    that routes through Glows.StartEngineGlow instead of the driver-ticked  
    engines, so it costs zero per-frame Lua no matter how many bars glow. Cast  
    Colors (kick-ready tint + uninterruptible wash) always applies; the rest is  
    opt-in and off by default.  
    Adds a Where to Show content-type gate (Open World, Mythic/Heroic/Normal-LFR  
    Raid, Mythic/Non-Mythic Dungeons, Timewalking, Delve, In Combat), matching  
    the multi-select dropdown and bucket-detection convention already used by  
    AuraBuffReminders, with its own zone/combat watcher decoupled from the  
    nameplate-tracking lifecycle so a location change (de)activates the group  
    immediately.  
    Also fixes a latent nil-texture trap in BuildBar (a StatusBar has no texture  
    object until one is assigned) and applies four behaviour-preserving  
    optimizations to the existing hot paths: the 10Hz ticker no longer runs work  
    that cannot be seen, the duration lookup no longer probes three APIs when one  
    is known to apply, a bar restyles only when its settings generation is stale  
    instead of on every cast, and a full nameplate scan on release only happens  
    when a cast was actually dropped at the bar cap. The duration-lookup fix also  
    applies to Target/Focus Bars, which had the same three-API probe.  
