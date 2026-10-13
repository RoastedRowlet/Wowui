# EllesmereUI

## [v9.4](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.4) (2026-10-07)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.3.8...v9.4) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.4  
- Merge pull request #2525 from IslayLaphroaig/add-form-and-stance-only-cooldown-state-visibility  
    Cooldown Manager: add form and stance visibility effects to Cooldown State Effects  
- 9.3.9  
- Merge pull request #2529 from Barbiero/locale/ptbr-since-938  
    ptBR: translate strings added since v9.3.8  
- Merge pull request #2487 from Hasenburg/feat/rounded-corners  
    feat: optional rounded corners (Corner Radius)  
- ptBR: translate the bags Junk Marker and bank display, nameplate debuff coloring class cards, WoW Forever name format settings and combo point placement, the /cd Cooldown Manager toggle, ignoring older expansion quests, and Raid Frames / Forever Essentials outline overrides  
- Merge pull request #2524 from Shiyan66666/main  
- feat: optional rounded corners (Corner Radius)  
    Adds an opt-in Corner Radius (default 0, off) for unit frames (incl. a  
    detached power bar), raid and party frames, nameplates (health and cast  
    bar), the Resource Bars (health, power, class resource and pips) and the  
    swing timer, set from an inline cog on each Border Size control.  
    Shared core in EllesmereUI\_RoundedCorners.lua: one nine-sliced rounded  
    mask per body texture, hosted on the owner frame; a Solid border becomes a  
    rounded fill with the body's inverse cut out; Glow and Shadow are redrawn  
    round. Other border styles keep square corners. Previews follow.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
- Fix typo in date format in zhCN.lua  
- Merge pull request #2518 from DlargeX/main  
- Update zhCN  
- 9.3.9  
- Merge pull request #2522 from dfrisone/fix/forever-inspect-talents-button  
    fix(blizzard skin): restyle the inspect Talents button on Forever  
- fix(blizzard skin): fit Forever's ranged slot in the inspect weapon row  
    The row was laid out for two weapon slots; Forever's ranged slot ran into  
    the Talents button once it moved to the bottom corner. Recentre the three  
    slots and narrow the two buttons when InspectRangedSlot exists.  
- fix(blizzard skin): restyle the inspect Talents button on Forever  
    Forever parents InspectTalents to InspectPaperDollFrame rather than  
    InspectPaperDollItemsFrame, so the lookup came back nil and the button  
    stayed at its stock top-centre spot under the average item level.  
- Merge pull request #2520 from JuJuFX-dev/refactor/raidframes-main-split  
    Split EllesmereUIRaidFrames.lua into eighteen files  
- Merge pull request #2521 from JuJuFX-dev/feat/np-debuff-coloring-layout  
    UI(Nameplates): group Debuff Coloring lists into class cards  
- Merge pull request #2519 from JuJuFX-dev/fix/np-debuff-border-combo-priority  
- Regenerate the locale key list  
- Nameplates: group Debuff Coloring lists into class cards  
    The debuff and combo rows of every class ran through one two-column grid, told apart only by the class name in each label. Each class that holds an entry now gets its own expandable card (class icon, name in class color, entry counts) under a CLASSES header, with debuffs down the left column and combos down the right so both read top to bottom in priority order.  
    - Rows read "1. Debuff" / "1. Combo"; Spec Overrides and the Custom Spell popup keep the class-qualified name, so existing override entries still match and two classes cannot share one.  
    - Add Debuff / Add Combo close their column and add to their own class; a single wide Add Class button below the cards starts a class.  
    - A class without entries has no card, the player's included; the player's card starts expanded, the others collapsed.  
- Merge pull request #2462 from defnotjec/feature/bags-junk-marker  
- Merge pull request #2516 from LoChinAn/cdm-picker-status-translatable  
- Merge remote-tracking branch 'upstream/main'  
- CDM: harden form-only visibility event handling and retirement  
    - Cache uncertain tooltip results as a visible sentinel; retry after  
      PLAYER\_REGEN\_ENABLED so combat-secret text re-reads once readable.  
    - Publish shapeshift form names only when the full list is readable.  
    - Invalidate a single cached spell on SPELL\_DATA\_LOAD\_RESULT and  
      SPELL\_TEXT\_UPDATE; skip uncached spells.  
    - Pass allActiveFrames to watch reconciliation so inactive pool frames  
      leave the watch but keep their prior bar claim.  
    - Register SPELL\_UPDATE\_USABLE only while Hidden Until Usable  
      subscribers exist.  
    - Preset rearm toggles form events only when the need changes and  
      keeps PLAYER\_REGEN\_ENABLED for remaining cooldown rules.  
- Drop unread imports and an unread copy, guard the preview file, name the part files in comments  
    Review follow-up to the Raid Frames split. EUI\_RaidFrames\_Extras.lua imported the ten names of the ns.\_internals literal that moved to the main file, and EUI\_RaidFrames\_Lifecycle.lua kept an inCombat copy it only wrote. EUI\_RaidFrames\_Preview.lua now returns like the chain files when an earlier file failed. playerFriendlySpell and playerRezSpell are false in the table for a class without one, so their import goes through the guard like every other. Comments that pointed at a place in the old single file name the file that holds the code now.  
- fix(nameplates): rank debuff border colors so a combo draws over single debuffs  
- Merge pull request #2514 from JuJuFX-dev/refactor/quickdraw-main-split  
- Wire up the Raid Frames files: headers, shared locals, setters, load order  
- Move the Raid Frames code into seventeen new files (verbatim)  
- added more Localstrings  
- fixes and removed unused locals  
- Merge remote-tracking branch 'upstream/main'  
- added new Strings for German Locals  
- Add form-only cooldown state visibility  
- Merge pull request #2513 from JuJuFX-dev/fix/qt-auto-accept-trivial  
- Merge pull request #2515 from LoChinAn/locale-zhtw-debuff-colors-gossip-font-outline  
- fix(cdm): make custom spell, item and slot popup status messages translatable  
    The red status line in the Cooldown Manager's add-by-ID popups stayed  
    English on non-English clients: the five local SetStatus() helpers  
    passed their text straight to SetText().  
    Pass it through L() instead. All 15 callers hand in English literals,  
    so nothing is localized twice and English output is unchanged. Add  
    zhTW for the six new keys.  
- locale(zhTW): translate 47 new keys, prune 26 dead ones and refile Threat keys  
    Covers v9.3.7..v9.3.8: nameplate debuff coloring, auto gossip, tooltip  
    buffs, auto uprank messages, Debuff Manager hints and the Window Mover  
    tab, plus three Click Casting row labels that reach L() through  
    RowLabel().  
    The Fonts "Module Outline" tooltip joins the module name into the  
    sentence before L(), so the existing %1$s key never matched; it is  
    replaced by one full sentence per module.  
    The Unit Frames combat and leader indicator strings used three words  
    for "indicator"; they now match the panel's other indicators. 42  
    Threat Meter keys filed under Core / General before Forever Essentials  
    had a section move there, and one Unit Frames key leaves Nameplates.  
    The 26 removed keys are strings the source no longer produces.  
- feat(quest tracker): auto accept ignore older expansion quests option  
- Build the four fan-out setters in one loop, name the main file in the OnEnable comment  
- Point the nest sweep's extract at the two files that hold the geometry  
- Wire up the Quickdraw files: headers, shared locals, setters, load order  
- Move the Quickdraw code into twelve new files (verbatim)  
- Bags: Junk Marker -- opt-in vendor-value sort + Show Junk in Recent  
    Ordering items by vendor value deviates from the EUI norm (categories keep  
    their saved drag/visual order), so make it opt-in; and give control over  
    whether junk clutters the Recent Items section. Both live in the Junk cog.  
    - Sort Junk by Vendor Value (bagJunkSortByValue, default OFF): gates every  
      junk vendor-sort site -- the All Items pre-pass, the grouped-member and  
      selected-category paths, and the OneBag/MultiBag pull-out. Off -> Junk  
      orders like any other category (saved order / VisualSortCompare).  
    - Show Junk in Recent (bagJunkShowInRecent, default ON): shared  
      ns.JunkHiddenFromRecent gate filters junk (grey + player-marked) out of the  
      Recent Items section in the grid (OneBag + All Items) and list views when  
      turned off. Default-on path returns early with no IsJunk lookup, and it is a  
      no-op whenever the feature itself is off.  
    Also drops the stale "(sorted by vendor value)" note from the One Bag /  
    MultiBag pull-out tooltips, since that ordering is now opt-in.  
- Bags: Junk Marker -- actually order the Junk category by vendor value  
    Found (during in-game validation):  
    - The Junk category never ordered by vendor value. Two latent bugs: (1)  
      SortJunkByVendor read sell price from a bare itemID via C\_Item.GetItemInfo,  
      which returns nil on this client, so every value was 0; (2) the All Items  
      view ordered every category (Junk included) with ApplySavedOrder in a  
      pre-pass and only ran SortJunkByVendor in the grouped/selected paths, so in  
      All Items the Junk section used the saved/bag order and never vendor-sorted.  
    Verified:  
    - List view's Sell Price column reads the same price fine via the item LINK  
      (C\_Item.GetItemInfo(link) index 11); the bare-id form is what failed.  
    - In All Items, itemsByCat[junk] went through ApplySavedOrder (line pre-pass)  
      with no vendor sort anywhere downstream. Confirmed in-game: values now sort  
      high-to-low in both All Items and the selected Junk category.  
    Did:  
    - SortJunkByVendor reads sell price from d.itemLink (PreCacheSortFields warms  
      it just above); the SellJunk earned total reads it from info.hyperlink.  
    - All Items pre-pass vendor-sorts the Junk category instead of ApplySavedOrder,  
      matching the grouped-member and selected-category paths.  
- Bags: Junk Marker -- one Junk section in list view, not two  
    Elle:  
    - List view already puts grey items in its own "Junk" section, and marked  
      items now land in the new Junk category, so with the feature on there are  
      two sections called Junk. Send cat.isJunk items into the list's existing  
      junk bucket.  
    Verified:  
    - In category (non-slot) list view, grey items bucket to "junk" by quality,  
      while player-marked items carry the Junk category index and bucketed to  
      that category's own section -- also labelled "Junk" -- giving two.  
    Did:  
    - Route cat.isJunk items into the existing "junk" bucket alongside grey items  
      (key = (d.\_lvQuality == 0 or cat.isJunk) and "junk" or ci). cat.isJunk is  
      nil when the feature is off, so behaviour is unchanged there.  
- Bags: Junk Marker -- never auto-sell a still-refundable item  
    Elle:  
    - SellJunk calls UseContainerItem on items that are still refundable, which  
      Blizzard's own right-click never does (it shows the refund confirmation  
      instead). Marks are per item ID and account-wide, so e.g. if you buy a  
      fresh copy of a marked item with currency, auto-sell sells it at the next  
      merchant without asking. Skip slots where  
      C\_Container.GetContainerItemPurchaseInfo(bag, slot, false) has refundSeconds.  
    Verified:  
    - NextJunkSlot returned any junk slot with vendor value, so a freshly bought  
      copy of a marked item (marks are account-wide per itemID) would sell on the  
      next sweep with no refund prompt -- unlike Blizzard's right-click.  
    Did:  
    - Added IsRefundable(bag, slot): GetContainerItemPurchaseInfo(bag, slot,  
      false).refundSeconds > 0. NextJunkSlot now skips refundable slots.  
      Capability- and type-guarded so a missing or odd-shaped return degrades to  
      "sellable" rather than erroring mid-sweep.  
- Bags: Junk Marker -- refresh the Junk category index each classify pass  
    Elle:  
    - \_junkCatIdx is only set in InitCategories, but ReorderCategory,  
      AddCustomCategory and RemoveCustomCategory change the list in place without  
      a rebuild. E.g. drag a category from above Junk to below it and every grey  
      item goes to the wrong category until a reload. Refresh it in ClassifyAll  
      each pass, the same way setCatIdx already is.  
    Verified:  
    - ClassifyItem routes grey items to self.\_junkCatIdx, but that index was only  
      computed in InitCategories; the in-place reorder/add/remove paths shift cats  
      without rebuilding it, so grey items landed in a stale index until /reload.  
      setCatIdx is rebuilt each ClassifyAll pass for exactly this reason.  
    Did:  
    - Rebuild \_junkCatIdx at the top of ClassifyAll, folded into the existing  
      unconditional counts-reset loop over cats (one pass, no extra traversal).  
      Stays nil when the feature is off.  
- Bags: Junk Marker -- make Junk the last default so saved order is stable  
    Elle:  
    - Junk is inserted before Miscellaneous, but bagVisualOrder (each category's  
      saved drag order) is keyed by category index. So turning the feature on or  
      off shifts Miscellaneous and everything after it by one, and they pick up  
      each other's saved orders. Make Junk the very last default with  
      appendLast = true, added after the Forever block so it lands after Special  
      Bags there too.  
    Verified:  
    - The Junk def sat between Housing and the Miscellaneous catch-all, so every  
      index at or below Junk shifted by one when the feature toggled, and  
      bagVisualOrder (index-keyed) then applied the wrong saved order.  
    Did:  
    - Removed the inline Junk def; append it as the last DEFAULT\_CATEGORIES entry  
      after the Forever block (so it lands after Special Bags, which is also  
      appendLast). InitCategories already routes appendLast defaults to the end  
      without disturbing any saved index, and the catch-all is found by its  
      isCatchAll flag, not position, so Junk after Miscellaneous is fine.  
- Bags: Junk Marker -- keep the full-screen dim for normal assign mode  
    Elle:  
    - The overlay change in EnterAssignSelectMode also hits the normal "+" assign  
      mode, so everyone gets the bag-only dim now (pin mode still dims the whole  
      screen). Keep the old overlay for normal assign mode and use the bag-only  
      one just for junk mode.  
    Verified:  
    - EnterAssignSelectMode built a single cached \_assignOverlay parented to the  
      bag window; normal "+" assign (DoAssign) and junk-select both reused it, so  
      the normal mode lost its long-standing full-viewport dim.  
    Did:  
    - Two overlays cached separately and picked per mode: full-screen (UIParent /  
      FULLSCREEN\_DIALOG, the pre-feature look) for normal assign, bag-only for  
      junk select. The active one is assigned to \_assignOverlay so Exit, the  
      fades and the catcher are untouched. EnterJunkSelectMode passes bagOnly.  
- Bags: Junk Marker -- only pay for it while it is enabled  
    Elle:  
    - The MERCHANT\_SHOW/MERCHANT\_CLOSED watcher registers at file load, so it  
      runs for everyone even with the feature off. Register it only while  
      bagJunkMarker is on. Same for the junkItems/diverted tables and the  
      RenderJunkSection/RenderJunkCatTop closures -- RenderGridView builds those  
      on every render even when it is off.  
    Verified:  
    - The watcher called RegisterEvent at parse time, so its OnEvent ran for all  
      players. In RenderGridView the OneBag/MultiBag block allocated junkItems +  
      diverted and defined RenderJunkSection every render, and the All Items  
      block scanned cats + defined RenderJunkCatTop every render, regardless of  
      the toggle.  
    Did:  
    - Watcher no longer registers at load; new EUI\_Bags:SyncJunkMerchantWatcher  
      registers/unregisters MERCHANT\_SHOW/CLOSED to match the toggle (and hides  
      the Sell Junk button when off). Called at header build (DB ready) and from  
      the options toggle.  
    - OneBag/MultiBag junk machinery (tables + RenderJunkSection + junkAtTop) is  
      built only inside "if pullJunk"; readers use "not (diverted and ...)" and  
      "if RenderJunkSection and not junkAtTop", matching the file's own  
      "not (special and special[...])" idiom.  
    - All Items junk-top scan + RenderJunkCatTop closure built only inside  
      "if IsJunkMarkerEnabled() and bagJunkAtTop". Zero tables/closures when off.  
- Bags: Junk Marker -- mark items as junk, group them, sell at a vendor  
    Off by default; master toggle 'Enable Junk Marker' in Bags > Extras.  
    - Junk category collects grey (Poor) items plus anything the player marks;  
      marks persist per itemID (account-wide), so future copies auto-classify.  
    - A coin button in the bag header enters a click-to-toggle select mode -- the  
      dim is scoped to the bag window so grid items stay bright; middle-click also  
      unmarks. Marked items desaturate and get a rounded coin badge whose corner  
      is pickable (TL/TR/BL/BR), lifted just outside the slot.  
    - The Junk category orders items by vendor value. 'Move Junk Category to Top'  
      renders it just below Pinned in All Items / OneBag / MultiBag; optional  
      per-view pull-out toggles for OneBag and MultiBag.  
    - A 'Sell Junk' button appears at merchants; optional auto-sell on open behind  
      a confirm popup. Selling is throttled (one item per tick), bails if the  
      merchant closes or combat starts, leaves no-value items in place, and can  
      silence its chat summary ('No Sale Summary Text').  
    Retail/other clients unaffected -- everything is gated on the feature toggle.  
