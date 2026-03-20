# CraftScan

## [v1.6.15](https://github.com/stevin05/CraftScan/tree/v1.6.15) (2026-03-13)
[Full Changelog](https://github.com/stevin05/CraftScan/compare/v1.6.14...v1.6.15) [Previous Releases](https://github.com/stevin05/CraftScan/releases)

- Make 'Attach CraftScan' more consistent and auto-hide on close even when TSM is installed.  
- Merge pull request #97 from defunes43/fix-taint-96  
    Fix taint-related arithmetic errors in MoneyFrame (#96)  
- Fix taint-related arithmetic errors in MoneyFrame (Fixes #96)  
    - Wrap GameTooltip:SetRecipeResultItem calls in securecall to ensure update logic runs in a secure context.  
    - Use anonymous frame for the toggle button in ProfessionsFrame to avoid taint propagation.  
