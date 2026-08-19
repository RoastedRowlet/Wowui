# CraftSim

## [27.0.0](https://github.com/derfloh205/CraftSim/tree/27.0.0) (2026-08-17)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/26.1.11...27.0.0) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- notes  
- notes fix  
- version  
- chore: DB2 Data Update: 12.1.0.69299 (#1447)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
- currency mapping result len check  
- Change currencyReagents CategoryID to 282 (#1444)  
    Updated CategoryID for currencyReagents to reflect Midnight Season 2.  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- [WIP] Module Code Refactor and Cleanup (#1292)  
    * feat: implement module visibility migration and update related options handling  
    * refactor: remove AverageProfit module and update ConcentrationTracker module registration  
    * WORK IN PROGRESS  
    * refactor: update module class definitions and visibility handling across multiple modules  
    * logging updates  
    * updated print to logger calls  
    * refactor: update debug UI frame size and logging command handling  
    * refactor: enhance logging and debug options, remove deprecated variables  
    * refactor: unify UI update method calls and enhance event logging  
    * refactor: update subproject commit reference in GUTIL  
    * new initializing events  
    * concentration tracker init  
    * feat: add warning log for failed recipe data build and update module visibility logic  
    * refactor: comment out module visibility logic for future cleanup  
    * refactor: update minimum log level fetching in DEBUG:Init function  
    * refactor: ensure database initialization occurs before minimap button setup  
    * refactor: update event names for profession and recipe initialization in simulation modules  
    * refactor: streamline simulation mode initialization and update UI components  
    * refactor: update simulation mode event handling and UI visibility logic  
    * refactor: enhance OpenRecipeAllocationUpdated function with validation checks and logging  
    * refactor: update recipe data retrieval logic in event handling  
    * refactor: improve event handling for simulation mode in recipe allocation updates  
    * refactor: add warning log for recipe data update when simulation mode is active  
    * Refactor/event based modules simulation mode (#1323)  
    * fix: safely fetch minimum log level in DEBUG initialization (#1316)  
    * feat: update version to 26.1.2 and add patch notes for recent fixes  
    * resolve and merge  
    * fix: add formatter initialization in Slash.lua  
    * feat: update version to 26.1.3 and add new patch notes  
    * refactor: enhance OpenRecipeAllocationUpdated function with validation checks and logging  
    * refactor: update recipe data retrieval logic in event handling  
    * simulation mode functionality  
    * refactor: update GGUI subproject to latest commit  
    * refactor: update logging for profiling and enhance event handling in initialization  
    * refactor: update GGUI subproject commit reference  
    * feat: implement patch notes module and update UI integration  
    * refactor: simplify checksum retrieval logic in IsPatchNotesUpdate function  
    * refactor: rename visibleRecipeID to initialRecipeID for consistency and clarity  
    * refactor: implement specialization info module (#1325)  
    * refactor: implement specialization info module with event handling and UI updates  
    * feat: add collapse event handling for specialization info module UI  
    * feat: add handling for module maximization and improve recipe data retrieval logic  
    * feat: enhance specialization info UI with simulation mode handling and frame updates  
    * feat: add new event handling for recipe info updates and enhance UI state management  
    * feat: improve UI state management by updating visibility context on module close and option toggle  
    * fix: update visibleRecipeID to initialRecipeID for consistency  
    * refactor: streamline specialization info UI logic and remove simulation mode handling  
    * feat: enhance specialization info module with control panel integration and visibility updates  
    Co-authored-by: Copilot <copilot@github.com>  
    ---------  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: update patch notes with new slash commands and fixes  
    * Refactor PreCraftBuffGate module: Move functionality to CraftQueue and remove old implementation  
    - Deleted the PreCraftBuffGate.lua file from Modules/PreCraftBuffGate.  
    - Moved the PreCraftBuffGate functionality into the CraftQueue module.  
    - Updated CraftSim.toc to reflect the new location of PreCraftBuffGate.  
    * refactor: streamline debug logging options and update UI for event logging  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: enhance Cooldowns module with event handling and UI updates  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: add context-based visibility check for Cooldowns UI module  
    * refactor: enhance module frame state callbacks for Cooldowns and Specialization Info UI  
    Co-authored-by: Copilot <copilot@github.com>  
    * chore: DB2 Data Update: 12.0.5.67186 (#1339)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix: enhance CMD\_bruto command to handle user preferences and visibility checks  
    fix: add visibility check for AuctionatorShoppingFrame in AuctionatorQuickBuy function  
    * refactor: add event handling for order view closure and update visibility context  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: update UI module method signatures for consistency and clarity  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: enhance event handling for Craft Buffs and update UI module structure  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: simplify visibility check logic in Craft Buffs UI  
    * refactor: add debug module for Simulation Mode and enhance inspection capabilities  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: streamline debug module button creation in UI  
    * CraftQueue  
    * refactor: add visibility check for CraftQueue UI based on module settings  
    * Refactor CraftQueue module and introduce Shopping module  
    - Removed Auctionator dependency from CraftQueue and moved related functionality to a new Shopping module.  
    - Simplified CraftQueue event handling and removed unused code related to quick buy caching.  
    - Updated UI interactions to utilize the new Shopping module for creating shopping lists.  
    - Enhanced debugging capabilities for the Shopping module.  
    - Implemented hooks for commodity purchase confirmation in the Shopping module.  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: update CraftLog module to use event-driven architecture and improve frame handling  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: remove debug logging from SetCraftedRecipeData function  
    * refactor: implement event registration system for CraftSim modules  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: enhance event handling for module visibility in ControlPanel  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: introduce Recipe Info module and update event handling (#1341)  
    * refactor: introduce Recipe Info module and update event handling  
    - Added the Recipe Info module with registration and event subscription.  
    - Updated the Update function to handle recipe data updates via events.  
    - Removed obsolete average profit frame handling and UI updates.  
    - Streamlined the Recipe Info UI initialization and display logic.  
    * refactor: improve RecipeInfo module's UI and stat handling  
    - Updated the RecipeInfo module to enhance the display state management and row rendering logic.  
    - Refactored the Update function to rebuild rows from the state, improving performance and clarity.  
    - Clarified comments regarding the necessity of refreshing profession stats after modifier changes.  
    * refactor: add event handling for order view closure and update module visibility  
    - Registered a new event for order view closure to hide the RecipeInfo frame.  
    - Updated the module visibility upon receiving fresh recipe data to ensure UI consistency.  
    * refactor: enhance RecipeInfo UI rendering and state management  
    - Introduced rowRefsByKey to maintain references for rows and their data.  
    - Updated RenderCachedDisplay to improve row rendering logic and visibility handling.  
    - Set currentRowData during state rebuild to streamline data management.  
    * refactor: streamline RecipeInfo UI state management and rendering  
    - Removed rowRefsByKey and currentRowData, simplifying the data structure.  
    - Updated RenderCachedDisplay to utilize preparedRows for improved rendering logic.  
    - Enhanced UpdateDisplay to directly set preparedRows from the built display state.  
    * refactor: remove deprecated Update function and streamline module visibility handling  
    - Eliminated the outdated Update function from the MODULES, which was previously responsible for managing UI state.  
    - Integrated visibility handling directly into the event flow, enhancing the responsiveness of the UI to recipe data changes.  
    * refactor: enhance RecipeInfo state management and UI updates  
    - Introduced currentRecipeData to track the active recipe, improving data handling.  
    - Updated CRAFTSIM\_RECIPE\_DATA\_UPDATED to set currentRecipeData upon receiving new data.  
    - Modified UpdateDisplay to utilize currentRecipeData for rendering, streamlining the UI update process.  
    - Removed deprecated preparedRows in favor of state-based rendering for better clarity and performance.  
    * refactor: simplify RecipeInfo event handling and visibility logic  
    - Removed the CRAFTSIM\_ORDER\_VIEW\_CLOSED event and its associated logic to streamline state management.  
    - Updated CRAFTSIM\_RECIPE\_DATA\_UPDATED to focus on currentRecipeData without reapplying module visibility.  
    - Enhanced the VisibleByContext method to improve clarity in module visibility based on selected profession tab.  
    * refactor: update recipe info module and localization identifiers  
    ---------  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
    * Refactor localization handling and update formatting functions across multiple language files  
    - Replaced instances of CraftSim.UTIL:FormatMoney with GUTIL:FormatMoney in enUS, frFR, koKR, ptBR, ruRU, zhCN, and zhTW localization files for consistent money formatting.  
    - Updated the localization retrieval method from CraftSim.UTIL:GetLocalizer to CraftSim.LOCAL:GetLocalizer in various UI modules to streamline localization access.  
    - Removed deprecated localization constants from Util/Const.lua.  
    - Cleaned up code formatting for readability in several modules, ensuring consistent indentation and spacing.  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: update localization handling in module registrations and text retrieval  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: streamline frame state callbacks in CraftQueue UI initialization  
    Co-authored-by: Copilot <copilot@github.com>  
    * refactor: add custom module registration to CraftSimAPI  
    * refactor: remove unnecessary blank line in CraftBuffs module  
    * refactor: add new localization identifiers for crafting and recipe statistics  
    * refactor: re-enable reagent slots on simulation mode  
    * add .cursor to gitignore  
    * refactor: implement CRAFTSIM\_RECIPE\_DATA\_MODIFIED event and clean up event triggers  
    - Removed duplicate event trigger for CRAFTSIM\_RECIPE\_DATA\_UPDATED in the Init module.  
    - Added new CRAFTSIM\_RECIPE\_DATA\_MODIFIED event in the Modules module to handle recipe data updates.  
    - Updated SimulationMode and SpecializationInfo modules to utilize the new event and ensure proper data handling.  
    - Cleaned up comments and improved code readability across affected files.  
    * feat: add new frame constants for UI components  
    - Introduced a new CraftSim.CONST.FRAMES table to define constants for various UI frames.  
    - This addition enhances the organization and accessibility of frame identifiers within the codebase.  
    * fix: address several lua errors  
    * fix: ensure frames are hidden on initial creation to avoid flickering  
    * fix: remove hide property from craftqueue  
    * feat: enhance CraftQueue UI with edit recipe frame functionality (#1349)  
    * feat: enhance CraftQueue UI with edit recipe frame functionality  
    - Added a method to retrieve the edit recipe frame within the CraftQueue module.  
    - Improved the OpenEditRecipeFrame function to ensure proper display and layering of the edit frame.  
    - Updated the initialization of the edit recipe frame to maintain correct parent-child relationships in the UI.  
    - Introduced constants for frame strata to manage popup layering effectively.  
    * fix: update CraftQueue module to correctly enable the craft queue on auto show  
    - Replaced the Save method with SetModuleEnabled to ensure the MODULE\_CRAFT\_QUEUE state is accurately updated when the auto show option is triggered.  
    * feat: add EditRecipe module to CraftQueue  
    - Introduced a new EditRecipe module within the CraftQueue to facilitate recipe editing functionality.  
    - Implemented UI elements for the edit recipe frame, including dynamic reagent management and auto-hide features.  
    - Updated CraftQueue UI to integrate the new EditRecipe frame, ensuring proper layering and interaction handling.  
    * refactor: streamline CraftQueue edit recipe functionality  
    - Removed the direct method for retrieving the edit recipe frame from the CraftQueue module.  
    - Introduced custom events to manage the lifecycle of the edit recipe frame, enhancing modularity and separation of concerns.  
    - Updated UI interactions to utilize the new event-driven approach for opening and hiding the edit recipe frame, improving code clarity and maintainability.  
    * refactor: update event handling for CraftQueue edit recipe module  
    - Replaced the "CRAFTQUEUE\_FRAME\_HIDDEN" event with "CRAFTSIM\_MODULE\_CLOSED" to improve modularity in the CraftQueue edit recipe functionality.  
    - Adjusted the UI to hide the edit recipe frame based on the new event trigger, enhancing the separation of concerns within the code.  
    - Cleaned up related comments and documentation for clarity.  
    * remove custom event trigger  
    * refactor: remove unused event and streamline EditRecipe initialization  
    - Eliminated the "CRAFTQUEUE\_EDIT\_RECIPE\_HOST\_READY" event and its associated method to simplify the EditRecipe module.  
    - Updated the initialization process to directly call the EditRecipe UI setup, enhancing clarity and reducing unnecessary complexity.  
    - Cleaned up related comments and documentation for better understanding of the code structure.  
    * refactor: change RecipeScan into a module  
    * refactor: streamline Reagent Optimization module and UI updates (#1344)  
    * refactor: streamline Reagent Optimization module and UI updates  
    - Removed unused code related to the Reagent Optimization Work Order frame.  
    - Enhanced the Reagent Optimization module by adding a new update method for handling recipe data.  
    - Updated UI initialization to utilize the new module structure and improve frame management.  
    - Cleaned up event handling to ensure proper updates on recipe data changes.  
    * Apply suggestion from @Copilot  
    Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>  
    * refactor: streamline ReagentOptimization UI updates and improve visibility checks  
    - Removed unnecessary checks in the Update function to simplify UI updates.  
    - Enhanced the recipe data parameter documentation for clarity.  
    - Improved visibility logic in the UI to ensure proper context handling.  
    ---------  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
    Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>  
    * feat: enhance concentration management with new affordability checks (#1354)  
    - Added methods to calculate spendable and queueable amounts in ConcentrationData.  
    - Updated CanAfford method to streamline affordability checks across various modules.  
    - Refactored UI components to utilize new methods for displaying current concentration values and managing crafting costs.  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
    * fix: hide edit if craftqueue isnt enabled  
    when closing the profession window, the edit recipe window would stay visible  
    * feat: display progress in (1/13) for craftlist queueing  
    * feat(datamining): add multicraft support mapper by profession with cauldron exclusions (#1372)  
    * feat(datamining): add multicraft support mapper and output data file  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/e9155b2d-2c03-45ed-8f98-4783462f9bea  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix(datamining): exclude alchemy cauldron recipes from multicraft support  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): clarify cauldron filter constants and parsing note  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): normalize cauldron keyword comparison  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): align cauldron keyword constant casing  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): harden cauldron name extraction and keyword matching  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): tighten item name fallback handling for cauldron filter  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix(datamining): filter cauldrons by recipe category instead of keyword  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/d3ace29b-28c0-42fc-b327-625337eb7f61  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): harden category field handling for cauldron filter  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/d3ace29b-28c0-42fc-b327-625337eb7f61  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix: set default debug values for build and module in updateAll.py  
    * chore(datamining): normalize cauldron category matching logic  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/d3ace29b-28c0-42fc-b327-625337eb7f61  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): handle invalid trade skill category IDs safely  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/d3ace29b-28c0-42fc-b327-625337eb7f61  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix(multicraft): remove obsolete item IDs from MULTICRAFT\_SUPPORT\_DATA  
    * fix: reset debug values for build and module in updateAll.py  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: Genju <derfloh205@gmail.com>  
    * Feature/operationinfo loading improvements (#1373)  
    * fix  
    * feat(datamining): add multicraft support mapper by profession with cauldron exclusions (#1372)  
    * feat(datamining): add multicraft support mapper and output data file  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/e9155b2d-2c03-45ed-8f98-4783462f9bea  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix(datamining): exclude alchemy cauldron recipes from multicraft support  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): clarify cauldron filter constants and parsing note  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): normalize cauldron keyword comparison  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): align cauldron keyword constant casing  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): harden cauldron name extraction and keyword matching  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): tighten item name fallback handling for cauldron filter  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/825ee9fb-7a2c-4c24-b4a0-60aa20364416  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix(datamining): filter cauldrons by recipe category instead of keyword  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/d3ace29b-28c0-42fc-b327-625337eb7f61  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): harden category field handling for cauldron filter  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/d3ace29b-28c0-42fc-b327-625337eb7f61  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix: set default debug values for build and module in updateAll.py  
    * chore(datamining): normalize cauldron category matching logic  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/d3ace29b-28c0-42fc-b327-625337eb7f61  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * chore(datamining): handle invalid trade skill category IDs safely  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/d3ace29b-28c0-42fc-b327-625337eb7f61  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix(multicraft): remove obsolete item IDs from MULTICRAFT\_SUPPORT\_DATA  
    * fix: reset debug values for build and module in updateAll.py  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: Genju <derfloh205@gmail.com>  
    * feat(multicraft): enhance recipe initialization and preload logic for professions  
    ---------  
    Co-authored-by: Copilot <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * refactor: remove commented-out code in HookToProfessionsFrame function  
    * refactor: simplify event triggering in TRADE\_SKILL\_DATA\_SOURCE\_CHANGED function  
    * refactor: add VisibleByContext function to CONTROL\_PANEL.UI  
    * feat: enhance concentration tracker UI with moxie/acuity display (#1379)  
    * feat: enhance concentration tracker UI with moxie display and updates  
    - Introduced moxie icon display in the concentration tracker, including visibility logic based on moxie quantity.  
    - Added methods to check for gathering professions and populate tracker rows with relevant data.  
    - Updated UI layout for the concentration list to accommodate new moxie column and improved spacing.  
    - Enhanced tooltip functionality for moxie display, providing clearer information to users.  
    * feat: implement ApplyConcentrationTrackerMoxieIcon function for moxie display  
    - Added the ApplyConcentrationTrackerMoxieIcon function to manage the display of moxie icons in the concentration tracker.  
    - Included logic to handle visibility and alpha settings based on moxie quantity thresholds.  
    - Removed the previous implementation of the function to streamline the code.  
    * feat: add support for acuity in TWW  
    * refactor: move GetCrafterProfessionUID to UTIL module  
    * refactor: streamline concentration tracker logic and update gathering profession handling  
    - Removed the previous MOXIE\_GATHERING\_PROFESSIONS definition from UI.lua and moved it to Const.lua for better organization.  
    - Updated the logic in UpdateTrackerDisplay to utilize the new CrafterHasProfession utility function for checking gathering professions.  
    - Renamed desiredRowKeys to validRowKeys for clarity in tracking valid entries in the concentration tracker.  
    ---------  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
    * feat: add RestoreFrameConfig method to multiple UI modules for frame restoration (#1381)  
    * Refactor remaining legacy modules to `CraftSim.Module` / `CraftSim.Module.UI` (#1382)  
    * refactor: migrate remaining legacy modules to module/ui types  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/71d40cf8-516a-4562-bcf7-274e3a90fcb0  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * refactor: align module UIs with review feedback  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/f1ea74ce-f1d4-4e6e-ab04-14f390c16d96  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * refactor: apply follow-up visibility and naming feedback  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/b6511680-81c7-495a-a452-0e8c803b02cd  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * style: simplify explanations visibility return  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/b6511680-81c7-495a-a452-0e8c803b02cd  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * fix: add module enable check in CRAFTSIM\_RECIPE\_DATA\_UPDATED and update statistics frame reference  
    * feat: add ShowRecipeIndependentModules function to display UI when professions frame opens; enhance CRAFTSIM\_RECIPE\_DATA\_UPDATED and UpdateDisplay with module checks  
    * feat: add minimizable Concentration Tracker with current-character summary (#1432)  
    Collapse the overview to a compact per-profession list showing live  
    concentration and moxie or acuity for the logged-in character.  
    Co-authored-by: Aveline Estié <aa.estie@gmail.com>  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * Feat/crafting orders topgear (#1433)  
    * feat: enhance CraftSim with crafting orders support and UI updates  
    - Updated CraftSim.toc to include new interface version for crafting orders.  
    - Added functions in CraftQueue to manage stale work orders and handle order fulfillment responses.  
    - Implemented caching and invalidation logic for profession gear in response to crafting orders.  
    - Enhanced RecipeData to support resourcefulness and multicraft checks for work orders.  
    - Introduced event handling for crafting orders in the initialization process and UI updates.  
    - Improved logging for crafting order operations and added new event triggers for better integration.  
    * feat: enhance profession gear logic and UI updates for multicraft handling  
    - Updated ProfessionGear and ProfessionGearSet classes to improve multicraft tool checks and handling.  
    - Introduced new function ToolSlotMatchesEquipped to ensure equipped gear meets expected tool requirements.  
    - Enhanced RecipeData to determine when to avoid multicraft-only tools based on work orders and recipe support.  
    - Improved CraftQueue and EditRecipe modules to better manage gear selection and UI updates for crafting actions.  
    ---------  
    Co-authored-by: Aveline Estié <aa.estie@gmail.com>  
    * Feat/work order tracker (#1434)  
    * feat: enhance CraftSim with crafting orders support and UI updates  
    - Updated CraftSim.toc to include new interface version for crafting orders.  
    - Added functions in CraftQueue to manage stale work orders and handle order fulfillment responses.  
    - Implemented caching and invalidation logic for profession gear in response to crafting orders.  
    - Enhanced RecipeData to support resourcefulness and multicraft checks for work orders.  
    - Introduced event handling for crafting orders in the initialization process and UI updates.  
    - Improved logging for crafting order operations and added new event triggers for better integration.  
    * feat: enhance profession gear logic and UI updates for multicraft handling  
    - Updated ProfessionGear and ProfessionGearSet classes to improve multicraft tool checks and handling.  
    - Introduced new function ToolSlotMatchesEquipped to ensure equipped gear meets expected tool requirements.  
    - Enhanced RecipeData to determine when to avoid multicraft-only tools based on work orders and recipe support.  
    - Improved CraftQueue and EditRecipe modules to better manage gear selection and UI updates for crafting actions.  
    * feat: add work order tracker module and related UI enhancements  
    - Introduced the WorkOrderTracker module to manage patron work orders across characters.  
    - Implemented UI components for tracking work orders, including sorting and filtering options.  
    - Added functionality to evaluate and display the status of patron work orders with expiration times.  
    - Updated localization files to support new UI elements and options for the work order tracker.  
    - Enhanced CraftQueue to integrate with the work order tracker for improved order management.  
    * feat: add function to format last snapshot age in work order tracker UI  
    - Introduced a new function, FormatLastSnapshotAge, to calculate and format the time since the last snapshot.  
    - Refactored the snapshot age display logic in PopulateWorkOrderTrackerRow to utilize the new function for improved readability and maintainability.  
    * feat: implement recipe acquisition module and enhance work order tracker  
    - Added a new RecipeAcquisition module to manage recipe sourcing information.  
    - Enhanced the WorkOrderTracker to include acquisition hints and navigation to recipe sources.  
    - Updated UI components to display acquisition information in work order tooltips.  
    - Introduced functions for scoring and resolving specialization paths related to recipe acquisition.  
    - Improved localization files to support new terms and hints related to recipe acquisition.  
    * feat: enhance work order tracker tooltips and improve shopping list functionality  
    - Added short labels for required and expected quality in work order tracker tooltips for better clarity.  
    - Refactored tooltip formatting functions to improve readability and maintainability.  
    - Updated shopping list functionality to allow for non-exact item searches, enhancing user experience.  
    - Improved localization files to include new tooltip terms and ensure consistency across the UI.  
    * feat: enhance shopping list functionality with category filtering  
    - Added categoryKey filtering to the shopping list search functionality, allowing for more precise item searches.  
    - Introduced a new function to strip prefixes from recipe item names for cleaner display.  
    - Implemented a method to retrieve the category key for recipe shopping, improving item classification in the shopping list.  
    * fix: prevent patron work order tracker flash on profession open  
    Start the frame hidden and apply module visibility when the professions window opens.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * fix: avoid undeclared lastOrdersTabEnabled on EventBasedModules base  
    Keep early UpdateVisibilityByContext for tracker flash prevention without relying on precraft-only locals.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    ---------  
    Co-authored-by: Aveline Estié <aa.estie@gmail.com>  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * feat: craft-list concentration allocation modes (off/single/multi) (#1435)  
    Replace smart concentration queueing with explicit Disabled/Enabled/Single Best/Multi-Recipe modes and migrate craft list options.  
    Co-authored-by: Aveline Estié <aa.estie@gmail.com>  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * Feat/craftlist quality skip owned (#1436)  
    * feat: craft-list concentration allocation modes (off/single/multi)  
    Replace smart concentration queueing with explicit Disabled/Enabled/Single Best/Multi-Recipe modes and migrate craft list options.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * feat: add per-recipe quality filters for gear in craft lists  
    Allow restricting craft list armor recipes to specific output qualities for restock counting, optimization, and queueing, with no selection meaning all qualities are allowed.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * feat: skip owned material costs for patron orders and craft lists  
    Treat inventory-held reagents as zero cost in profit and max-cost checks, with a shared per-batch pool so materials are not double-counted across queued recipes.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    ---------  
    Co-authored-by: Aveline Estié <aa.estie@gmail.com>  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * Feat/inventory cache unbound restock (#1437)  
    * feat: craft-list concentration allocation modes (off/single/multi)  
    Replace smart concentration queueing with explicit Disabled/Enabled/Single Best/Multi-Recipe modes and migrate craft list options.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * feat: add per-recipe quality filters for gear in craft lists  
    Allow restricting craft list armor recipes to specific output qualities for restock counting, optimization, and queueing, with no selection meaning all qualities are allowed.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * feat: skip owned material costs for patron orders and craft lists  
    Treat inventory-held reagents as zero cost in profit and max-cost checks, with a shared per-batch pool so materials are not double-counted across queued recipes.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * feat: cache inventory lookups and prefer item ID queries  
    Add short-lived inventory source caching with invalidation on bag, bank, and purchase events, resolve counts by item ID where possible, and coalesce craft queue UI refreshes after craft results.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * fix: exclude soulbound inventory from restock and crafting limits  
    Count only unbound bags, bank, and AH stock when deciding how much still needs to be crafted.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    ---------  
    Co-authored-by: Aveline Estié <aa.estie@gmail.com>  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * fix: avoid nil realm crash when building player crafter UID during ADDON\_LOADED (#1440)  
    Realm APIs may be unavailable when module init restores frame config; do not cache incomplete player data and refresh the cache on PLAYER\_ENTERING\_WORLD.  
    * fix: restore shopping list and precraft shim  
    * feat: add right-click blacklist bindings to disenchant window  
    Right-click mirrors middle-click for session/permanent item blacklisting so users without a middle mouse button can ignore items.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * libs  
    * restored libs  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: Aveline Estié <aa.estie@gmail.com>  
    Co-authored-by: Copilot <copilot@github.com>  
    Co-authored-by: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>  
    Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
- chore: DB2 Data Update: 12.0.7.68974 (#1426)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  