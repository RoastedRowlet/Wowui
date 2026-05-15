# EllesmereUI

## [v7.7.2](https://github.com/EllesmereGaming/EllesmereUI/tree/v7.7.2) (2026-05-15)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v7.7.1...v7.7.2) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v7.7.2  
- Merge pull request #314 from RoastedRowlet/main  
    Aurabuff Reminders: Add the ability to remind for buffs under a certain threshold remaining.  
- Merge pull request #324 from liamcooper/fix/character-sheet-gem-hydration  
    Fix themed character sheet: gem hydration + spec portrait on reopen  
- Fix Blizzard skin character sheet gem socket display  
    - Refresh gem icons when tooltip/item data hydrates (TOOLTIP\_DATA\_UPDATE)  
    - Debounce socket refresh on item load and equipment events  
    - Avoid painting empty-socket atlas before GetItemGem matches stats  
    - Clear stale gem art on equipment change; consolidate socket row builder  
    Co-authored-by: Cursor <cursoragent@cursor.com>  
- Update version number to 7.6.1  
- add colons  
- fix shaman imbue  
- add raid as an option, cover flasks and food  
- Add options for reminding buff when remaining duration is below a certain value  
