# CraftSim

## [23.1.0](https://github.com/derfloh205/CraftSim/tree/23.1.0) (2026-03-27)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/23.0.3...23.1.0) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- feat: update version to 23.1.0 and add new patch notes  
- [RecipeScan] CraftLists Integration (#1152)  
    * Initial plan  
    * Implement RecipeScan CraftLists integration  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/14f71ed5-dffc-49df-a0b9-d91c40ac8090  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * refactor: clean up craft list icon handling in RecipeScan UI  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: Genju <derfloh205@gmail.com>  
- feat: add cheapest owned option to shatter (#1150)  
    * feat: add cheapest owned option to shatter  
    * fix: add icon and count for mote  
    ---------  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- feat: add shared cooldown for midnight (#1138)  
    * feat: add shared cooldown for midnight  
    also fixes so old cooldowns get cleaned up  
    * feat: add actual migration  
    * feat: update cooldown storage migration and enhance UI layout for better usability  
    ---------  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- Enhance QueueSelectedLists and QueueList with detailed logging for better debugging  
- Fix EncodeTable and DecodeTable to use GUTIL for base64 operations  
- Refactor CraftLists export/import to use CraftSim.UTIL for encoding/decoding tables  
- [CraftQueue] Add Reagent Allocation, Enable Unlearned, and TSM Restock Expression options to CraftLists (#1145)  
    * Initial plan  
    * Add Reagent Allocation, Enable Unlearned, and TSM Restock Expression options to CraftLists  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/4ef3c1fd-f46a-4586-906f-8ce60b37a442  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * Expand reagent allocation to nested Optimize submenu with Highest, Most Profitable, and Target Quality options  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/357225bb-a09f-49c4-b693-50977cb6c123  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * Replace global TSM restock expression with per-list expression input and validation in context menu  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/0dd99746-5b64-4917-bb1a-dae12fc9fde3  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * Show both standard and simplified quality icons for Q1/Q2 labels in Reagent Allocation menu  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/0f69646c-5479-4207-8c47-3b0a97f4bb17  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * Add option to enable unlearned recipes with formatted label and implement offset queue amount input in craft lists  
    * Enhance TSM restock expression label with bold formatting and update craft lists options for unlearned recipes  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- [Recipe Scan] Fix Smart Restock ignoring "Use TSM Restock Amount Expression" toggle (#1140)  
    * Initial plan  
    * Fix: Smart Restock respects Use TSM Restock Amount Expression toggle in Recipe Scan  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/29530f83-891a-4ada-abf1-ea204a810374  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- [CraftQueue] Add "Equip Tools" step to craft button status sequence (#1143)  
    * Initial plan  
    * feat: add Equip Tools step to CraftQueue craft button sequence  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/a8860c5b-0f63-4627-8610-b85e76170d91  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * feat: add CRAFT\_QUEUE\_BUTTON\_EQUIP\_TOOLS localization and update button label  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- Fix CraftLists export/import using UTIL instead of GUTIL for encode/decode (#1147)  
    * Initial plan  
    * fix: use GUTIL instead of UTIL for EncodeTable/DecodeTable in CraftLists export/import  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/8a5a205e-bba5-485e-ad03-eb293a2d7163  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- chore: DB2 Data Update: 12.0.1.66666 (#1148)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
- Fix tooltip taint from crafting order tipAmount/consortiumCut (#1121)  
    * Initial plan  
    * Fix tooltip taint: wrap tipAmount/consortiumCut with tonumber() and use fresh Blizzard order data in ViewOrder  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/958c03ad-c02e-4776-8257-f83f03cc34ca  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
    Co-authored-by: Aveline Estié <aa.estie@gmail.com>  
- [CodeCleanup] Refactor LocalizationIDs to be string only (#1136)  
    * Initial plan  
    * Refactor LocalizationIDs to be string only - remove CONST.TEXT enum  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/1fed594c-4e9d-4b9e-88fa-e5fac8ecc1ed  
    * Use keyof<CraftSim.LOCALIZATION\_DATA> for dynamic localization ID inference  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/e3233adc-6975-4f8d-9256-92f64dc8eb99  
    * Move LOCALIZATION\_IDS alias into enUS.lua with explicit string literal union  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/84ee6c8f-4020-4d4b-8c86-017d0ba9cfea  
    * Move LOCALIZATION\_IDS alias to dedicated LocalizationIDs.lua; use identifier keys in all locale files  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Agent-Logs-Url: https://github.com/derfloh205/CraftSim/sessions/ec21f8c7-2cb9-4ed6-9c4e-2e5cb5018921  
    * Remove LocalizationIDs.lua from the CraftSim.toc file  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: Genju <derfloh205@gmail.com>  