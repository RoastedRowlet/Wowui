# CraftSim

## [21.4.1](https://github.com/derfloh205/CraftSim/tree/21.4.1) (2026-03-20)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/21.4.0...21.4.1) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- news  
- map to indexed table to preserve sort order (#1100)  
- chore: update version to 21.4.1 and add patch notes for new features and fixes  
- feat: improve debug UI with copy popup, enlarged frame and cascading log ID toggles (#1060)  
    * feat: improve debug UI with copy popup, enlarged frame and cascading log ID toggles  
    - Enlarge debug frame to 700x550 and log box to 650x500 for better readability  
    - Add logBuffer to track all messages even when scrolled up  
    - Add 'Copy All' popup with a scrollable EditBox for easy copy-paste of logs  
    - Fix log ID checkbox closure bug: each checkbox now captures its own ID  
      instead of sharing the last iterated fullID  
    - Cascading toggle: checking a parent log ID category now also enables/disables  
      all child IDs (e.g. toggling 'Modules' propagates to all 'Modules.*' entries)  
    * refactor: simplify debug ID handling and adjust control panel size  
    * feat: add 'Disable All' button to debug UI and implement functionality to disable all log IDs  
    ---------  
    Co-authored-by: netouss <netoussgaming@gmail.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- [SimulationMode] Fix QualityMeter showing max quality icon when concentration is active (#1096)  
    * Initial plan  
    * Fix QualityMeter: hide current quality icon when concentration is active  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    * Fix QualityMeter: adjust next quality icon display and update bar thresholds  
    ---------  
    Co-authored-by: copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- chore: DB2 Data Update: 12.0.1.66527 (#1097)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  