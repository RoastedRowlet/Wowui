# WarpDeplete

## [v5.2.0](https://github.com/happenslol/WarpDeplete/tree/v5.2.0) (2026-05-04)
[Full Changelog](https://github.com/happenslol/WarpDeplete/commits/v5.2.0) [Previous Releases](https://github.com/happenslol/WarpDeplete/releases)

- chore: Bump version  
- feat: Add fallback split levels and permanent split visibility (#147)  
    * Add split fallback and always show option  
    * Add split fallback and always show option  
    * add closest proximity fallback behaviors and optimize loop logic  
    * Translated in french  
    * Removed translations for PR  
    * Correction Mise en page windows  
    * Correction Problemes espaces  
    * Doubles espaces  
    * Refine split records UI and visibility settings  
    * added translations  
    * removed icon and brackets  
    * Added missing translations  
    * fix: fallback split diffs not displaying during runs  
    * fix: display fallback source key level on split references  
    * added comments to split fallback logic  
    * Removed french translations  
    * Removed badges  
    Removed all mentions of the badges system for the splits, since they added too much complexity and not so much gain   
    Went back to the older method  
    Kept color picker for splits  
    * Moved splits color picker  
    - Moved splits color picker from Display to General  
    - Renamed "Split Reference Color" to "Split Records Color"  
    - And changed "splitReferenceColor" key to "splitRecordsColor"  
    * Added missing translations  
- chore: Bump version  
- feat: Show forces count in tooltips for midnight (#149)  
    Adds back the forces count as a fixed string in mob tooltips. Custom formatting is removed for now, since it would involve wrangling with secret values which is very error-prone.  
- chore: Bump version  
- fix: Add missing fonts and textures  
- chore: Bump version  
- fix: Check for secret values in UNIT\_DIED event (#141)  
- chore: Bump version  
- fix: Update addon for Midnight pre-patch (#138)  
    * Added support for Midnight pre-patch  
    * UNIT\_DIED is now its own event instead of a subevent of CLEU  
    * C\_ChallengeMode.GetCompletionInfo has been removed, using C\_ChallengeMode.GetChallengeCompletionInfo instead  
- fix: Use category id to open addon settings (#136)  
- chore: Update interface version russian description  (#134)  
- chore: Bump version  
- feat: Add checks for midnight expansion (#133)  
- chore: Add interface version for midnight (#132)  
- chore: update gitignore (#131)  
- chore: Update all locales (#129)  
- chore: Update embeds.xml (#130)  
- fix: Fix shared media dependency url (#128)  
- fix: Fix external dependency links again (#127)  
