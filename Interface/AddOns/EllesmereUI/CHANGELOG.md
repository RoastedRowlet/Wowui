# EllesmereUI

## [v8.9.8](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.9.8) (2026-08-21)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.9.7...v8.9.8) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.9.8  
- Merge branch 'main' of https://github.com/EllesmereGaming/EllesmereUI  
- Merge pull request #1628 from nulltyto/fix/trade-glow-on-move  
    Trade: move the change glow onto the item that moved  
- Merge pull request #1633 from Nnoggie/codex/fix-abr-invisible-tooltips  
    fix(abr): clear reminders before lockdown  
- Revert "Merge pull request #1610 from Nnoggie/codex/fix-unit-menu-taint"  
    This reverts commit fc7c2af746a4fbf35d5be74322df918496451912, reversing  
    changes made to dd3707224f69b79c778bca2332aad5bcb1eb0743.  
- fix(abr): clear reminders before lockdown  
    Use the real lockdown state for secure-button cleanup so ENCOUNTER\_START  
    cannot leave alpha-zero buttons mouse-active.  
- fix: move the trade change glow onto the item that moved  
    Dragging an item between trade slots left the proc glow behind on the  
    slot it came from.  
    Blizzard fires the TradeItemAlertTemplate flipbook from  
    TradeFrame\_AlertItemIfChanged on any slot whose contents differ from  
    what that slot last held. A drag between slots is not a reposition --  
    PlayerTradeItemTemplate's OnDragStart and OnReceiveDrag both call  
    ClickTradeButton -- so the item is removed from the offer and added  
    back, and two slots change. The slot you emptied alerts, and the slot  
    you filled does not, because Blizzard skips the alert while a slot's  
    itemKey is still nil ("We don't alert the first time an item is placed  
    in the slot"). The enchant slot behind "Will not be traded" is almost  
    always in that state, so dragging an item there always left the glow  
    on an empty box.  
    Post-hook TradeFrame\_AlertItemIfChanged with a per-side latch. A slot  
    going empty arms its side; the next slot on the same side to gain an  
    item consumes the latch, alerts, and stops the source.  
    Only a move is redirected. An item that leaves the offer for good never  
    gets its latch consumed, so its removal glow plays out in full -- that  
    is the per-slot half of the change warning TRADE\_WARNING\_CHANGED\_OFFER  
    gives on the Trade button, and it is not the accept state, which is  
    TradeHighlightPlayer/TradeHighlightRecipient and is left stock.  
    Per side, so a partner rearranging their offer cannot steal the glow  
    off yours. Blizzard's oldItemKey is already overwritten by the time a  
    post-hook runs, so the fix keeps a shadow flag in frame data; that flag  
    also makes a button's first sighting quiet, which keeps a /reload  
    mid-trade from alerting on all fourteen slots at once.  
