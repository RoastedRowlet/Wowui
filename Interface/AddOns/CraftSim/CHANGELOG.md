# CraftSim

## [27.0.5](https://github.com/derfloh205/CraftSim/tree/27.0.5) (2026-09-16)
[Full Changelog](https://github.com/derfloh205/CraftSim/compare/27.0.3...27.0.5) [Previous Releases](https://github.com/derfloh205/CraftSim/releases)

- fix  
- chore: DB2 Data Update: 12.1.0.69814 (#1499)  
    Co-authored-by: derfloh205 <9341090+derfloh205@users.noreply.github.com>  
    Co-authored-by: genjuwow <derfloh205@gmail.com>  
- Fix craft list restock ignoring soulbound treatises already in bags (#1501)  
    Restock subtracted only unbound inventory, so Bind-on-Pickup items like  
    profession treatises always looked like zero stock. Count bound copies of  
    inherently untradeable items, include the reagent bag and warbank, and  
    sum all non-gear result qualities against the restock target.  
    Co-authored-by: Cursor <cursoragent@cursor.com>  