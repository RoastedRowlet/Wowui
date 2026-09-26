# EllesmereUI

## [v9.2.9](https://github.com/EllesmereGaming/EllesmereUI/tree/v9.2.9) (2026-09-25)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v9.2.8...v9.2.9) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v9.2.9  
- Merge pull request #2213 from cassidymichael/feat/unitframes-power-cost-prediction  
    feat(unitframes): opt-in spell cost prediction on the player power bar  
- Merge pull request #2202 from cassidymichael/feat/faction-indicator  
    feat: faction indicator on unit frames and nameplates  
- feat: faction indicator on unit frames and nameplates  
    Opt-in Horde/Alliance indicator for the Player and Target frames and the  
    nameplates (its own Core Positions slot, or combined with Rare/Quest;  
    full friendly plates included, name-only plates stay just the name),  
    with PvP flag handling (dim unflagged, flagged only, ignore), a Players  
    Only option and seven icon styles. Preview eyes and click-to-jump for  
    Raid Marker, Leader, Elite and Faction.  
    Everything defaults to off. The nameplate badge frame and its  
    UNIT\_FACTION / UNIT\_FLAGS registrations exist only while a faction slot  
    is set; the unit frame events register only while an indicator is on.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
- Merge pull request #2204 from cassidymichael/feat/unitframes-heal-prediction  
    feat(unitframes): opt-in heal prediction on player, target, focus and boss frames  
- feat(unitframes): opt-in spell cost prediction on the player power bar  
    While a spell with a cast time is cast, the mana it will cost shows as  
    a colored segment at the end of the player's power bar, like Blizzard's  
    player frame. A StatusBar anchored to the fill's leading edge fills back  
    over it, laid out on each cast start (texture, fill direction, Blizzard  
    Style mask); max power and the cost from C\_Spell.GetSpellPowerCost only  
    reach SetMinMaxValues/SetValue (secret-safe). The cast is matched by  
    castGUID, so instants cast during it leave it alone. Mana only.  
    Options in the Player Power Bar section: Spell Cost Prediction toggle  
    with a preview eyeball, and Spell Cost Color (default: Blizzard's  
    POWERBAR\_PREDICTION\_COLOR\_MANA). Off by default: the segment and the  
    cast-event listener are created only when it is turned on.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
- Merge pull request #2186 from dfrisone/fix/chat-undocked-buttonframe-fade  
    fix(chat): keep the button frame hidden on undocked chat windows  
- Merge pull request #2201 from cassidymichael/feat/unitframes-buff-dispel-borders  
    feat(unitframes): opt-in dispel type borders on target, focus and boss buffs  
- Merge pull request #2203 from cassidymichael/feat/level-difficulty-color  
    feat: color level text by difficulty on unit frames and nameplates  
- Merge pull request #2211 from dfrisone/fix/forever-cdm-spec-key  
    Fix(Cooldown Manager): resolve the spec through C\_SpecializationInfo  
- Merge pull request #2210 from dfrisone/feat/quest-tracker-delves  
    Add a Dungeons condition to the Where to Show checklist  
- Merge pull request #2209 from dfrisone/feature/party-mode-spins-visibility  
    feat(partymode): spinning CDM, data bars, unit frames and resource bars; Party Mode visibility condition  
- Merge pull request #2207 from dfrisone/forever/threat-meter  
    Add a threat meter to Quality of Life (WoW Forever only)  
- Merge pull request #2208 from Barbiero/locale/ptbr-since-928  
    ptBR: translate raid frame group order, Show In filter, style options and new disabled-option tooltips  
- Fix(Cooldown Manager): count other classes' specs through C\_SpecializationInfo  
    GetNumSpecializationsForClassID is another Blizzard\_DeprecatedSpecialization  
    alias, nil on Forever, so the Sync From source picker listed no specs there.  
- Fix(Cooldown Manager): resolve the spec through C\_SpecializationInfo  
    WoW Forever does not load Blizzard\_DeprecatedSpecialization (its TOC allows  
    only classic and standard, not camelot), so the loose GetSpecialization and  
    GetSpecializationInfo globals are nil there. The spec key read them behind  
    an existence guard, so it quietly came back nil: GetBarSpellData returned  
    nil for every bar and clicking any icon in the options errored at the  
    unguarded sd.hostedBuffSpellIDs read.  
    Every Cooldown Manager spec lookup now calls the C\_SpecializationInfo  
    functions those globals alias on retail, so retail behaviour is unchanged.  
    This also revives the healer check behind the focus kick context, which was  
    gated on the missing globals. The options read gains the sd guard its  
    neighbours already have.  
- Add a Dungeons condition to the Where to Show checklist  
    Hide in Instances also covers delves, because delves are scenarios, so  
    there was no way to hide an element in dungeons and keep it in delves.  
    Delves are always a party, so the group conditions offer no way around  
    it either.  
    The new Dungeons row counts five-player dungeons only, Mythic+ included.  
    Delves, raids and scenarios do not count, and garrisons are excluded as  
    they are for Instances. It is a Lua-only axis like Instances, Resting  
    and In Vehicle, re-evaluated on the zone events Instances already uses,  
    and off by default.  
- feat(partymode): spinning CDM, data bars, unit frames and resource bars; Party Mode visibility condition  
    * Visibility > Party Mode: new Show/Hide lane (visOnlyPartyMode /  
      visHidePartyMode). Party Mode has no game event, so Start/Stop fire  
      EllesmereUI.FireVisEdge; modules that evaluate visibility on their own  
      frames register through EllesmereUI.RegisterVisEdge. An edge that lands  
      in combat re-fires on PLAYER\_REGEN\_ENABLED so secure bars catch up.  
    * Spinning Cooldown Manager: icons orbit their bar's centre (or the root  
      bar of an anchor chain), snap to rest in combat and resume after.  
    * Shared spin engine, EllesmereUI.PartySpin\_Create, used by:  
      - Spinning Data Bars: blocks orbit their bar's centre  
      - Spinning Unit Frames: EUI unit frames orbit the screen centre  
      - Spinning Resource Bars: pips / runes orbit the class resource bar  
      - Spinning Power Bars: health and primary power bars orbit the screen centre  
      Pauses in combat and while Unlock Mode is open. All toggles default off,  
      each with a speed cog on the Party Mode page.  
- fix(qol): show Forever threat values without the x100 downscale  
    Forever's UnitDetailedThreatSituation returns threat in display units (a  
    couple of hits read 53 in game), not the x100 scale Classic's API uses, so  
    dividing by 100 showed every value a hundred times too small. Bar lengths,  
    order, percents and the pull line were unaffected; only the numbers were.  
- feat(qol): add a threat meter for WoW Forever  
    A Threat tab under Quality of Life, listed on WoW Forever only, showing  
    everyone's threat on your target as class-colored bars, highest first. With  
    a friendly target it shows the mob that target is fighting. Off by default.  
    Forever hands UnitDetailedThreatSituation over readable  
    (C\_Secrets.ShouldUnitThreatValuesBeSecret is false there); a value that does  
    come back secret skips that unit rather than erroring.  
    Includes a pull aggro bar, a one-shot warning sound at a threshold (quiet  
    while tanking if chosen), the shared Visibility control, and the usual size,  
    border, texture, font and color options. Moves and resizes in Unlock Mode.  
    Updates are event-driven and coalesced to one redraw per 0.2s. The one  
    exception is following a friendly target's enemy in combat: that mob is only  
    reachable as targettarget, which UNIT\_THREAT\_LIST\_UPDATE never names, so the  
    meter re-reads every 0.5s in that case only.  
- ptBR: translate raid frame Custom Group Order, party frame buff anchors and Name Position, Show In indicator filter, Blizzard Border glow style, Blizzard UI Color, cast bar Inherit texture, Resource Bars style description and the disabled-option tooltips now shown for nameplate, raid frame, damage meter and cooldown manager settings; drop keys for removed strings  
- feat(unitframes): opt-in heal prediction on player, target, focus and boss frames  
    Incoming heals drawn past the health fill, like Blizzard's frames: the  
    player's own heals first, then other players', each in its own color.  
    Two StatusBars fed by a heal prediction calculator (secret-safe), in the  
    absorb cluster's missing-health clip, following the fill direction  
    (reverse and vertical included). An Overheal slider lets them run past  
    the bar's end by up to 50% of its length: a holder outside the frame's  
    bar clip, clipping at the allowance, with the calculator clamping to  
    maximum health.  
    Options in the Absorbs section, renamed Absorbs and Heals: Heal  
    Prediction toggle with two color swatches and a preview eyeball,  
    Prediction Opacity (default 60), Overheal, and Texture (Health Bar, the  
    default, follows the frame's own health texture; Flat; or any health-bar  
    texture). Boss Frames use the Target setting, like their absorbs. Off by  
    default: the bars, the calculator and the UNIT\_HEAL\_PREDICTION listener  
    are created only when a frame turns it on.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
- Merge remote-tracking branch 'upstream/main' into fix/chat-undocked-buttonframe-fade  
- fix(chat): gate the button-frame alpha re-assert to docked frames  
    Elle: the watcher still forced this frame's alpha to 0 on every pass,  
    regardless of dock state, so it kept fighting Blizzard's undocked hover  
    fade after the last commit. btnFrame's own border/background art is  
    gone either way, but the minimize button is a child that kept its art  
    and inherited the fight, which is what still flickered. Undocked  
    windows now follow Blizzard's own fade untouched; the re-assert only  
    runs while docked, which is also the only state that needs it.  
- feat: color level text by difficulty on unit frames and nameplates  
    Optional level text coloring in Blizzard's difficulty colors (red "??",  
    gold for units you cannot attack, otherwise the color for the unit's  
    level against yours), with an Include Friendly option that colors  
    friendly units by level too. Unit frames: two toggles on the Unit  
    Frames page, applied to the Level, Level | Name and Name | Level texts.  
    Nameplates: the same two toggles in the level text slot's cog, which  
    gains an optional second toggle row. Off by default.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
- feat(unitframes): opt-in dispel type borders on target, focus and boss buffs  
    The debuff Dispel Type Borders ring, now also available on buffs: typed  
    buffs on Target, Focus and Boss frames get the engine-tinted ring (Magic  
    blue), untyped buffs none. Off by default; a Dispel Type Borders toggle  
    in each Buff Settings cog. AuraKit's ring registration takes  
    showWhenHelpful from the new style.dispelHelpful instead of hardcoding  
    false.  
    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>  
- fix(chat): restore the minimize button on undocked windows  
    Leave it alone rather than disabling it. It fades in with btnFrame's  
    alpha on hover, the same as any other chat window's, since the black  
    bar behind it -- the reported bug -- is gone regardless: btnFrame's  
    own border/background textures are what get emptied, and the button  
    is a separate child object neither of those writes ever reached.  
- fix(chat): drop dead alpha writes, fix stale comments (review)  
    The wiped button-frame textures never needed a SetAlpha(0) alongside  
    SetTexture(""): the texture is gone either way, and Blizzard periodically  
    resets these regions' own alpha (FCF\_SetWindowAlpha, the tab-menu opacity  
    slider), so the write was doing nothing. The minimize button does not  
    need the same texture wipe: nothing re-applies its own alpha, so a single  
    SetAlpha(0) at skin time holds. Updated SyncChatFrameState's header  
    comment, which still described the button frame as watcher-hidden.  
- fix(chat): hide the button frame by its art, not an alpha hook  
    A SetAlpha post-hook ran inside Blizzard's dock pass and chat fades,  
    the path this module keeps its code out of; 6.8.3 shipped and removed  
    the same hook. Blizzard never re-textures the button frame or its  
    minimize button, so empty their textures once at skin time and disable  
    the minimize button's mouse. The old lookup of that button used a name  
    that does not exist, so it stayed clickable on undocked windows.  
- fix(chat): keep the button frame hidden on undocked chat windows  
    Blizzard fades an undocked window's button frame in on hover and out to  
    0.2 alpha, animating it every frame. The state watcher's periodic zero  
    could not keep up, so the black bar flickered beside a moved chat window  
    and stayed faintly visible afterwards. Zero every alpha write with a  
    SetAlpha post-hook, installed once per chat frame.  
