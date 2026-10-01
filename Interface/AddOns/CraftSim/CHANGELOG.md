# CraftSim

## [27.0.7](https://github.com/derfloh205/CraftSim/tree/27.0.7) (2026-09-28)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/27.0.6.1...27.0.7) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- patchnotes for avilene's updates  
- Patron KP cost overrides, Moxie auto-update, and recraft order craft fix (#1514)  
    * Add patron order knowledge point cost customization  
    - Introduced new options for setting maximum gold costs per knowledge point for characters and professions.  
    - Added tooltips for better user guidance on cost settings and overrides.  
    - Implemented UI components to allow users to customize costs directly within the CraftSim interface.  
    - Enhanced the CraftQueue module to utilize the new cost settings in patron order calculations.  
    - Updated localization files to include new strings related to the knowledge point cost features.  
    * Refactor patron order knowledge point cost handling  
    - Updated localization strings for clarity on knowledge point cost settings.  
    - Removed unused character cost settings to streamline the configuration process.  
    - Enhanced UI logic to ensure proper handling of character overrides for knowledge point costs.  
    - Improved documentation within the code to reflect changes in cost management behavior.  
    * Refactor patron order UI for knowledge point cost settings  
    - Streamlined the character override checkbox functionality to improve user experience.  
    - Enhanced tooltip descriptions for better clarity on knowledge point cost options.  
    - Adjusted UI layout to ensure proper display of profession-specific cost settings.  
    - Improved code organization for better maintainability and readability.  
    * Fix auto-updating Moxie values after Auctionator price scans.  
    Wire Auctionator DB updates into the surplus-based Moxie recompute path and log changed values for verification.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * Fix recraft work orders so Craft Queue can fulfill and submit them.  
    Use RecraftRecipeForOrder with the claimed order's output item GUID instead of CraftRecipe, matching Blizzard's order view.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * Queue restock crafts from item yield, not one craft per missing item.  
    Convert restock targets with ceil(needed items / yield per craft) so multi-output recipes like flasks and phials only queue the minimum crafts required.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * Count Syndicator AH stock in restock and exclude Cooking from concentration tracker.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * Fix restock AH counts when TSM is loaded alongside Syndicator.  
    Use live Syndicator auction data and take the best AH amount from available trackers instead of skipping Syndicator whenever TSM is present.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * Store patron KP max costs per character and profession.  
    Profession costs were shared account-wide while only the override toggle was per character; nest costs by crafterUID and migrate legacy flat maps.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    * Fix recraft work-order crafting and allow unset optional slots.  
    Prefer live claimed-order GUIDs for RecraftRecipeForOrder, and stop treating empty sparks/optionals or base mats as required on recrafts.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    ---------  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- chore: DB2 Data Update: 12.1.0.69933 (#1511)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  