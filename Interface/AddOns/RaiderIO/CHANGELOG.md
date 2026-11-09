# Raider.IO Mythic Plus, Raiding, and Recruitment

## [v202611060600](https://github.com/RaiderIO/raiderio-addon/tree/v202611060600) (2026-11-06)
[Full Changelog](https://github.com/RaiderIO/raiderio-addon/compare/v202611050600...v202611060600) [Previous Releases](https://github.com/RaiderIO/raiderio-addon/releases)

- [Raider.IO] Database Refresh  
- Wait for the guild name before recording a guild join (#409)  
    IsInGuild turns true before GetGuildInfo names the guild, so a join  
    read the name too early and recorded "Unrecorded name". Hold the join  
    with its original context, request the roster, and record it once the  
    name arrives, after 5 s, or at logout. A rejoin during the wait records  
    the held join first.  
- Send the surname in Forever character observations (#408)  
    The site stores `First Surname`, so a first name alone can name another  
    character. Schema 2 adds the surname, and an unreadable one or an unloaded  
    unit's placeholder name rejects the sighting.  
- [Raider.IO] Classic Database Refresh  
- Let Journey source activations through before collection is on (#407)  
    The desktop withholds enableJourneys and enableJourneyMetadata until it has  
    seen a source activation, but QueueMessage rejected every Journey message  
    without those flags. A first enable could never qualify, leaving "Sync and  
    reload the addon" on screen through any number of reloads.  
    Activation echoes now pass sourceControl, which needs only the beacon switch  
    and a published activation ticket. Other Journey messages keep the full gate.  