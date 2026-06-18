# CraftSim

## [26.1.8](https://github.com/derfloh205/CraftSim/tree/26.1.8) (2026-06-17)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/26.1.7...26.1.8) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- news  
- TOC bumb  
- chore: DB2 Data Update: 12.0.7.68232 (#1397)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
- feat: enhance reagent handling for public orders + logging (#1384)  
    * feat: enhance reagent handling for public orders + logging  
    Added checks for order reagents in the HasEnough function to improve reagent validation. Introduced logging for skipped work orders to provide better insights during the crafting process. Updated queue processing logic to handle public orders more effectively, including detailed debug logging for order candidates.  
    * Fix allowConcentration to only enable concentration when qualityWithoutConcentration < minQuality  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/2a403ec2-b308-4338-8b1e-a4698eb64ecc  
    Co-authored-by: avilene <5927637+avilene@users.noreply.github.com>  
    * fix: respect multiplier in HasEnough when IsOrderReagentIn is true  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/50bbb752-8bc3-4c6a-b49a-180154c0cc1b  
    Co-authored-by: avilene <5927637+avilene@users.noreply.github.com>  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
- chore: DB2 Data Update: 12.0.5.67602 (#1376)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  