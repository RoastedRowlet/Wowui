# EllesmereUI

## [v9.3.8](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.3.8) (2026-10-05)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.3.7...v9.3.8) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.3.8  
- Merge pull request #2494 from lkshrk/fix/abr-scenario-where-to-show  
    fix(aurabuffreminders): add Scenario to Where to Show  
- Merge branch 'main' into fix/abr-scenario-where-to-show  
- Merge pull request #2512 from Barbiero/locale/ptbr-since-936  
    ptBR: catch up with v9.3.5 – v9.3.7  
- Merge pull request #2511 from JuJuFX-dev/refactor/nameplates-main-split  
- ptBR: translate nameplate debuff coloring and threat gap, XP bar quest overlay and text slots, character sheet item details and stat sections, Dark Mode colors, graphics restore and full reset, action bar paging tooltips, Unlock Mode width/height matching, QoL auto gossip, and WoW Forever spell ranks and loot feed styles  
- Merge upstream main (v9.3.7) into refactor/nameplates-main-split  
- Regenerate the locale key list  
- Merge upstream main into refactor/nameplates-main-split  
- Write the profile through SetProfile alone, give class power the same setter shape, point the forward declaration comment at its file  
- Wire up the nameplate files: headers, shared locals, setters, load order  
- Move the nameplate code into thirteen new files (verbatim)  
- locales: translate the Scenario Where to Show entry  
- fix(aurabuffreminders): add Scenario to Where to Show  
    Island Expeditions, Warfronts, Visions, Torghast and every other non-delve  
    scenario resolved to no Where to Show bucket, so every section ignored its  
    settings there and always showed. Map them to a new "Scenario" entry in  
    AuraBuffReminders and the Targeted Spell Bars filter.  
    Housing plots also report as "scenario"; treat them as open world.  
    Fixes #2493  
