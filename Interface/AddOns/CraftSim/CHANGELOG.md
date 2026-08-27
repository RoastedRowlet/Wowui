# CraftSim

## [27.0.2](https://github.com/derfloh205/CraftSim/tree/27.0.2) (2026-08-26)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/27.0.1...27.0.2) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- fixes  
- chore: DB2 Data Update: 12.1.0.69497 (#1480)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- chore: DB2 Data Update: 12.1.0.69465 (#1479)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
- Fix reagent optimize, recraft order optionals, frame reset, and concentration tracker (#1470)  
    * fix: added missing usePermutation back in Optimize for recipeData  
    * feat: Add frameID and frameTable to various UI modules for improved frame management  
    - Introduced frameID and frameTable properties in multiple UI initialization functions across different modules, enhancing the frame management system.  
    - Updated the CraftSim.CONST.FRAMES with new frame identifiers for better organization and access.  
    - Ensured consistency in frame handling by utilizing the shared frame registry.  
    * Simplify frame reset to the GGUI registry instead of a hardcoded module list.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * fix: Improve reagent quality comparison and recipe data handling in optimization UI  
    - Added checks to ensure the quality of reagents matches before proceeding with optimization.  
    - Updated the logic to compare against the live schematic allocation instead of potentially stale data.  
    - Enhanced recipe data assignment in the initialization process to ensure accurate updates during events.  
    * feat: Enhance concentration tracking with new timer and refresh logic  
    - Added a method to calculate the time until the next concentration point.  
    - Implemented a refresh mechanism for the concentration tracker display, including a timer for updates.  
    - Updated UI to handle visibility changes and ensure accurate display of concentration data.  
    - Improved event handling for recipe data updates to keep the tracker in sync.  
    * fix: Refactor reagent handling to improve currency checks and slot status management  
    - Updated checks for active reagents to ensure proper identification of currency types across various slots.  
    - Enhanced logic in `CraftResult`, `OptionalReagentSlot`, and `ReagentData` to handle locked slots and order reagents more effectively.  
    - Improved the `RecipeData` class to rebuild reagent data based on the current order state, ensuring accurate crafting conditions.  
    - Adjusted the shopping module to correctly identify missing reagents based on updated slot conditions.  
    * fix: Refine concentration tracker display logic and UI updates  
    - Improved the RefreshTrackerDisplay method to ensure proper handling of tracker visibility and timer management.  
    - Updated UI initialization to handle frame visibility changes more effectively, ensuring accurate display updates.  
    - Enhanced minimized display logic to prevent blank entries during frame resizing and collapsing.  
    - Added checks to ensure the tracker frame is shown before updating the display and scheduling refreshes.  
    * fix: Enhance AuctionHouseFrame visibility checks and refine recipe data retrieval  
    - Updated visibility checks for AuctionHouseFrame to ensure it exists before checking its visibility.  
    - Refactored recipe data retrieval logic to handle cases where the initial recipe ID may not be set, improving robustness.  
    - Adjusted logging level for missing schematic forms to provide clearer debugging information.  
    ---------  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- Skip the UNIT\_AURA payload while aura restrictions are active (#1472)  
    The payload is SecretWhenAurasRestricted, so branching on info.isFullUpdate throws for tainted callers; ADDON\_RESTRICTION\_STATE\_CHANGED resyncs the tracked set once restrictions lift.  
- fix: 27.0.2 - Work order queue pruning & Customer History (#1465)  
    * feat: Enhance RemoveStaleWorkOrders to support skill line filtering  
    Added an optional skillLineID parameter to the RemoveStaleWorkOrders function to allow for more precise pruning of work orders based on the expansion skill line. Updated related calls in CRAFTQ to pass the skill line ID when removing stale work orders.  
    * feat: Enhance Customer History Module with additional event handling and caching  
    Added support for new crafting order events: CRAFTINGORDERS\_CLAIMED\_ORDER\_UPDATED and CRAFTINGORDERS\_CLAIMED\_ORDER\_REMOVED. Implemented caching for claimed orders to improve data integrity during fulfillments. Updated UI visibility logic to include crafting orders tab. Improved logging for customer history recording.  
    ---------  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- chore: DB2 Data Update: 12.1.0.69404 (#1466)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
- Fix CraftListsDB v1→v2 migration failure due to missing NormalizeCrafterUIDKey (#1464)  
    * Initial plan  
    * Fix missing NormalizeCrafterUIDKey and improve migration error reporting  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
- chore: DB2 Data Update: 12.1.0.69382 (#1453)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- Fix reagent optimization UI comparing against live allocation instead of optimized snapshot (#1462)  
    * Initial plan  
    * Fix reagent optimization comparison regression  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  