# CraftSim

## [23.1.1](https://github.com/derfloh205/CraftSim/tree/23.1.1) (2026-03-28)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/23.1.0...23.1.1) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- feat: add updates for Korean localization and public orders to news  
- feat: update version to 23.1.1 and add patch notes for public orders feature  
- fix: increase fixedWidth for itemCountColumn in InitLogFrame  
- fix: extract setup function  
- feat: enable addWorkOrdersButton based on profession focus  
    - Added logic to enable the addWorkOrdersButton in the CraftQueue UI based on the current profession and its proximity to the profession spell focus.  
    - Improved user experience by ensuring the button's state reflects the player's profession context.  
- feat: add support for public orders in CraftQueue  
    - Introduced new options for including public orders in the crafting queue.  
    - Added localization strings for public orders and their maximum count.  
    - Implemented functionality to handle public orders in the queue processing logic.  
    - Updated UI to allow users to configure public order settings.  
- fix: ensure we load windows  
- chore: DB2 Data Update: 12.0.1.66709  
- feat: add koKR (Korean) translation (#1154)  
    * feat: add koKR (Korean) translation  
    * feat: Added localized strings  
    * Update Locals/koKR.lua  
    Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>  
    * fix: 즉시시가 -> 즉시 구매가가  
    * fix: typo in koKR.lua  
    * fix: tab -> space only  
    * fix: remove the whitespace-only line.  
    ---------  
    Co-authored-by: Mingu Jo <whalsrn0710@naver.com>  
    Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>  