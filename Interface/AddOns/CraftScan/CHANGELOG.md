# CraftScan

## [v1.6.19](https://github.com/stevin05/CraftScan/tree/v1.6.19) (2026-08-13)
[Full Changelog](https://github.com/stevin05/CraftScan/compare/v1.6.17...v1.6.19) [Previous Releases](https://github.com/stevin05/CraftScan/releases)

- Merge branch 'main' of https://github.com/stevin05/CraftScan  
- Bump number for 12.1  
- Merge pull request #105 from Dobbelklick/bugfix/greeting-character-mismatch  
    Fix stale alt-craft greeting after logging into the crafter character  
- Merge pull request #98 from defunes43/feature/french-translations  
    Fix some French translations  
- Fix stale alt-craft greeting after logging into the crafter character  
    When a notification was created while playing character X for a craft  
    that alt Y could do, the response message was pre-generated as an  
    alt-craft greeting ("my alt Y can craft this"). If the player then  
    logged into Y and clicked the notification, that stale message would  
    stil say "my alt" even though Y is now the active character.  
    Fix: extract greeting generation into BuildRawGreeting(), which  
    re-evaluates alt\_craft against the current logged-in character each  
    time it is called. Add CraftScan.RebuildResponseMessage() which  
    detects the character mismatch and regenerates response.message  
    in-place. Store crafterFullName and alt\_craft on the response so  
    the rebuild has enough context. Call RebuildResponseMessage() just  
    before sending the greeting (GreetCustomer) and before displaying  
    the proposed greeting in the chat-history tooltip.  
- first pass  
