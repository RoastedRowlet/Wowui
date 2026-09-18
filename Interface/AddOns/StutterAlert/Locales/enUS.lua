local _, ns = ...
local L = ns.L

-- enUS is the base locale and always loads, regardless of client language, so
-- it acts as the fallback set. British clients report enUS too, so this file is
-- what every English-speaking player reads; there is no enGB to write.
--
-- Every other locale file starts with:  if GetLocale() ~= "deDE" then return end
-- then overrides the keys it translates, and is listed in Locales.xml.
--
-- Rules for a translation:
--   * Keep every %d / %s / %.1f in the same number, type and ORDER as here. A
--     mismatch is a Lua error the moment the line is shown, not a cosmetic slip.
--     %% is a literal percent sign and takes no argument.
--   * Never make a word agree with a number. Russian has three plural forms and
--     Chinese none, so counts are written as "label: %d" or "x%d", which read
--     correctly for any value in every language.
--   * Leave in English: slash commands and their arguments (/sa lock,
--     all|summary|off), event names, "ms", "FPS", and the addon's name.
--   * Lists are joined with LIST_SEP, so a translation never hardcodes ", ".

-- == General ==
L.ADDON_TITLE                  = "StutterAlert"
L.UNKNOWN_SOURCE               = "Unknown"
-- Versioned title used in the tooltip header and export dialog.
-- Format args: (1) addon title, (2) version string
L.TITLE_VERSION                = "%s v%s"

-- == Context Labels ==
L.CTX_CITY                     = "City"
-- Format arg: (1) one of the context labels below
L.CTX_WITH_COMBAT              = "%s (in combat)"
-- The five-man label has two forms. CTX_DUNGEON is used on retail, where the
-- bucket is mostly Mythic+; CTX_DUNGEON_PLAIN is used on the Classic clients,
-- which have no such mode. Constants.lua picks between them.
L.CTX_DUNGEON                  = "Dungeon / M+"
L.CTX_DUNGEON_PLAIN            = "Dungeon"
L.CTX_PVP                      = "PvP"
L.CTX_RAID                     = "Raid"
L.CTX_SCENARIO                 = "Scenario"
L.CTX_WORLD                    = "Open world"

-- == Cause Definitions ==
L.DEF_ADDON                    = "This addon did too much work while the game was drawing one frame."
L.DEF_ENGINE                   = "A single slow frame from the game itself, often loading a model or spell effect. Not your UI."
L.DEF_GC                       = "The game briefly paused to tidy up temporary memory your addons created (known as garbage collection). Small and occasional is normal."
L.DEF_LOADING                  = "You just zoned or moved somewhere new, and the game was streaming it in."
L.DEF_SUSTAINED                = "Your frames have been slow for a stretch, not just this one. That points at graphics settings or your PC, not your addons."
L.DEF_UNCLEAR                  = "This frame ran long, but we couldn't pin it on your addons or a clear game cause."

-- == Overlay Headlines ==
-- Each cause has a short label and a _TIP shown under it in the tooltip.
L.HEADLINE_ENGINE              = "Engine spike"
L.HEADLINE_ENGINE_TIP          = "Game engine: usually nothing to do. If it repeats in one spot, the game is streaming assets there."
L.HEADLINE_GC                  = "Memory cleanup"
L.HEADLINE_GC_TIP              = "Memory cleanup: usually nothing. If it keeps happening, an addon may be wasteful - check Top Sources."
L.HEADLINE_LOADING             = "Zone loading"
L.HEADLINE_LOADING_TIP         = "Loading area: this is normal. Running WoW from a fast SSD makes these shorter."
L.HEADLINE_SUSTAINED           = "Sustained slowdown"
L.HEADLINE_SUSTAINED_TIP       = "Sustained slowdown: lower shadows, view distance, or effects, and close background apps."
L.HEADLINE_UNCLEAR             = "Cause unclear"
L.HEADLINE_UNCLEAR_TIP         = "Source unclear: nothing to change yet. Watch Recent and Top for a pattern."

-- == Menu Options ==
L.MENU_BANNERS                 = "Pop-up Banners"
L.MENU_BANNERS_ALL             = "All (live hitches + pull summaries)"
L.MENU_BANNERS_OFF             = "Off (icon and tooltip only)"
L.MENU_BANNERS_SUMMARY         = "Pull summaries only"
L.MENU_CLEAR_HIST              = "Clear Hitch History"
L.MENU_GROWTH_AUTO             = "Auto (Smart Docking)"
L.MENU_GROWTH_DIR              = "Banner Growth Direction"
L.MENU_GROWTH_LD               = "Grow Left & Down"
L.MENU_GROWTH_LU               = "Grow Left & Up"
L.MENU_GROWTH_RD               = "Grow Right & Down"
L.MENU_GROWTH_RU               = "Grow Right & Up"
L.MENU_LOCK                    = "Lock Position"
L.MENU_RESET                   = "Reset Position to Menu"
L.MENU_SIZE                    = "Button Size"
L.MENU_SIZE_DEFAULT            = "Default (Menu Size)"
L.MENU_SIZE_M                  = "Medium (64x64)"
L.MENU_SIZE_S                  = "Small (32x32)"
-- The addon's name. Not translated.
L.MENU_TITLE                   = "StutterAlert"
L.PREVIEW_MODE                 = "Preview Mode"

-- == Severity Levels ==
L.SEV_CALM                     = "Calm"
L.SEV_CRITICAL                 = "Critical"
L.SEV_ELEVATED                 = "Elevated"

-- == Slash Commands ==
-- The command words (/sa, lock, all|summary|off, ...) are what the player types
-- and what the parser matches, so they stay English in every translation.
-- Format args: (1) one of the SLASH_BANNERS_* descriptions below
L.SLASH_BANNERS                = "Pop-up banners: %s"
L.SLASH_BANNERS_ALL            = "all (live hitches and pull summaries)"
L.SLASH_BANNERS_OFF            = "off - the icon colour and the tooltip still work"
L.SLASH_BANNERS_SUMMARY        = "pull summaries only"
L.SLASH_DISABLED               = "Monitoring disabled."
L.SLASH_ENABLED                = "Monitoring enabled."
L.SLASH_LOCKED                 = "Overlay locked."
L.SLASH_RESET                  = "Overlay position reset to below the minimap."
L.SLASH_UNLOCKED               = "Overlay unlocked - drag it where you want it."
L.SLASH_USAGE_BANNERS          = "/sa banners all|summary|off - choose which pop-up banners appear"
L.SLASH_USAGE_HEADER           = "StutterAlert commands:"
L.SLASH_USAGE_LOCK             = "/sa lock - lock the overlay in place"
L.SLASH_USAGE_REPORT           = "/sa report - open the full report and advice"
L.SLASH_USAGE_RESET            = "/sa reset - move the overlay back below the minimap"
L.SLASH_USAGE_TOGGLE           = "/sa toggle - turn monitoring on or off"
L.SLASH_USAGE_UNLOCK           = "/sa unlock - unlock to drag the overlay"

-- == Post-pull Summary ==
-- Format args: (1) hitch count, (2) of those from addons, (3) from the game
L.SUMMARY_PULL                 = "Last pull  -  hitches: %d (addons %d, game %d)"
L.SUMMARY_PULL_CLEAN           = "Last pull: no stutters. Smooth."

-- == Tooltips ==
L.TT_ACTION_ADDON              = "- Addon hitches: Update, reconfigure, or disable repeat offenders."
L.TT_ACTION_ENGINE             = "- Game/engine hitches: usually a one-off as the game loads a model or effect. If it repeats in one spot, lower your graphics settings."
L.TT_ACTION_HEADER             = "How to improve performance:"
L.TT_CTX_COMBAT                = "in combat"
-- Format arg: (1) enemy nameplates on screen, always 5 or more
L.TT_CTX_ENEMIES               = "%d enemies"
-- Format arg: (1) world latency in ms
L.TT_CTX_LATENCY               = "world %d ms"
-- Format arg: (1) the conditions above, joined with LIST_SEP
L.TT_CTX_PREFIX                = "While this happened: %s"
L.TT_HINT_BANNERS_OFF          = "Pop-up banners are turned down. Monitoring is still running - right-click to change it."
L.TT_HINT_CLEAR                = "Shift Left-Click to clear history"
L.TT_HINT_LOCKED               = "Unlock with /sa unlock to move."
L.TT_HINT_MENU                 = "Right-Click for menu"
L.TT_HINT_UNLOCKED             = "Drag to move. Lock with /sa lock."
L.TT_HITCH_EXPLAIN             = "A 'hitch' is a single frame that took too long to render, causing a visible stutter."
L.TT_RECENT_HEADER             = "Recent hitches"
L.TT_RECENT_NONE               = "No hitches recorded yet."
-- Format args: (1) ms, (2) context label, (3) time ago string
L.TT_RECENT_RIGHT              = "%d ms  -  %s  -  %s"
-- Format args: (1) ms, (2) multiple of the addon's usual cost, (3) time ago string
L.TT_RECENT_RIGHT_MULT         = "%d ms  -  %dx usual  -  %s"
-- Format arg: (1) one of the SEV_* labels
L.TT_SEVERITY                  = "Severity: %s"
L.TT_THROTTLED                 = "Monitoring paused - frame rate is capped"
-- Format args: (1) the readable name of the setting that confirmed the cap
L.TT_THROTTLED_CVAR            = "Every frame is landing exactly on your %s limit, so nothing here is a stutter. Detection resumes on its own."
L.TT_THROTTLED_WHY             = "Every frame is the same length, which is a frame rate limit rather than a stutter. Detection resumes on its own."
-- Format arg: (1) hours / minutes / seconds. Abbreviated: the tooltip is narrow.
L.TT_TIME_HOUR                 = "%dh ago"
L.TT_TIME_MIN                  = "%dm ago"
L.TT_TIME_SEC                  = "%ds ago"
-- The addon's name. Not translated.
L.TT_TITLE                     = "StutterAlert"
L.TT_TOP_HEADER                = "Top stutter sources (since last cleared)"
-- Format args: (1) hitch count, (2) peak ms, (3) time ago string
L.TT_TOP_RIGHT                 = "hitches: %d  -  peak %d ms  -  %s"

-- == Granular Game Causes ==
L.HEADLINE_SCENE               = "Busy scene"
L.HEADLINE_SCENE_TIP           = "Busy scene: normal on big pulls or crowded hubs as the game loads unit models and effects. Lower view distance and effect density to ease it."
L.DEF_SCENE                    = "Lots of units appeared at once and the game loaded their models and effects in one frame. Common on big pulls or zoning into a crowd. Not your addons."

L.HEADLINE_COMBAT_FX           = "Combat effects"
L.HEADLINE_COMBAT_FX_TIP       = "Combat effects: spell visuals and particles loading mid-fight. Lower Spell Density, Particle Density, and Projected Textures to ease it."
L.DEF_COMBAT_FX                = "A spell effect, particle burst, or projected texture loaded during combat. Common on bosses and small packs. Not your addons."
L.HEADLINE_STREAMING           = "World streaming"
L.HEADLINE_STREAMING_TIP       = "World streaming: the game is loading terrain as you travel. A fast SSD helps most; lower View Distance to ease it."
L.DEF_STREAMING                = "The game streamed in terrain and textures as you moved into new ground. Common while flying or riding. Not your addons."

-- == Toast Banners ==
-- Single banner. Format args: (1) source name, (2) milliseconds
L.TOAST_ONE                    = "%s  -  %d ms"
-- Coalesced banner (repeats of one source). Format args: (1) name, (2) count, (3) peak ms
L.TOAST_MANY                   = "%s  x%d  -  peak %d ms"

-- == Last Pulls (tooltip) ==
L.TT_PULLS_HEADER              = "Last 5 pulls (this session)"
L.TT_PULLS_NONE                = "No pulls completed yet this session."
L.TT_PULL_CLEAN                = "Clean - no stutters"
-- Format args: (1) total hitches, (2) game-caused, (3) addon-caused, (4) worst frame ms
L.TT_PULL_LINE                 = "hitches: %d (game %d, addons %d)  -  worst %d ms"

-- == Post-pull Summary (additional) ==
-- Format args: (1) total hitches, (2) worst source title, (3) worst ms, (4) game-caused count
L.SUMMARY_PULL_WORST           = "Last pull  -  hitches: %d, worst %s %d ms (game: %d)"

-- == Tooltip hint (additional) ==
L.TT_HINT_EXPORT               = "Left-Click for the full report and advice"

-- == Export Report ==
-- The report is translated like everything else. Addon names, versions, event
-- names and numbers pass through untouched, so an author reading a report in
-- another language can still act on it.
L.EXPORT_SCOPE                 = "Figures below cover everything since history was last cleared."
-- Format args: (1) total hitches, (2) from addons, (3) from the game
L.EXPORT_TLDR                  = "Hitches recorded: %d  -  from addons: %d, from the game: %d."
L.EXPORT_TLDR_CLEAN            = "No hitches recorded. Smooth so far."
-- Format args: (1) addon title, (2) ms, (3) multiple of its usual cost
L.EXPORT_WORST                 = "Worst addon: %s  -  %d ms (%dx its usual cost)"
-- Format args: (1) addon title, (2) ms
L.EXPORT_WORST_NOMULT          = "Worst addon: %s  -  %d ms"
L.EXPORT_TOP_HEADER            = "Top addon sources:"
-- Format args: (1) addon title, (2) hitch count, (3) peak ms
L.EXPORT_TOP_LINE              = "  - %s  -  hitches: %d, peak %d ms"
L.EXPORT_CAUSES_HEADER         = "Game causes (not your addons):"
-- Format args: (1) cause label, (2) count
L.EXPORT_CAUSE_LINE            = "  - %s: %d"
-- Format arg: (1) ms
L.EXPORT_BASELINE              = "Typical frame time: %d ms"
L.EXPORT_BASELINE_WARMING      = "Typical frame time: still measuring."
-- Deliberately a single space: a blank closing line. Leave it untranslated.
L.EXPORT_FOOTER                = " "

-- == Advice Panel ==
-- Use the key names printed on this language's keyboards (German: Strg+C).
L.PANEL_REPORT_HEADER          = "Shareable report (Ctrl+C to copy)"
L.ADVISE_WHY_HEADER            = "Why am I stuttering?"
L.ADVISE_VERDICT_NONE          = "No stutters recorded yet. Play for a bit, then check back here."
-- Format args: (1) game hitch count, (2) total
L.ADVISE_VERDICT_GAME          = "Most of your stutters come from the game itself, not your addons (%d of %d)."
-- Format args: (1) addon hitch count, (2) total
L.ADVISE_VERDICT_ADDON         = "Most of your stutters come from your addons (%d of %d). See the report on the right for the culprits."
-- Format arg: (1) patterns joined with LIST_SEP, e.g. "in combat, Dungeon / M+"
L.ADVISE_WHERE                = "They mostly happen: %s."
L.ADVISE_PAT_COMBAT            = "in combat"
L.ADVISE_PAT_TRAVEL            = "while travelling"
-- Format arg: (1) zone name
L.ADVISE_PAT_ZONE              = "in %s"
L.ADVISE_CAUSE_HEADER          = "What's causing them"
L.ADVISE_TRY_HEADER            = "What you can try"
L.ADVISE_RAID_NOTE             = "Your spikes cluster in raids, so the values below are your raid graphics settings."
L.ADVISE_SETTINGS_OK           = "Your graphics settings already look modest. Remaining spikes are likely hardware, drivers, or asset streaming - not settings you can change here."
L.ADVISE_SETTINGS_HEADER       = "Your relevant settings"
-- Format args: (1) setting name, (2) current value, (3) default value
L.ADVISE_SLIDER                = "Lower %s - currently %s (default %s)"
-- Format arg: (1) setting name
L.ADVISE_TOGGLE                = "Turn off %s (currently on)"
-- Format args: (1) setting name, (2) current value, (3) default value
L.ADVISE_SETTING_LINE          = "%s: %s (default %s)"
L.ADVISE_CHANGE_WHERE          = "Change these in the game menu: System > Graphics (and Advanced)."
L.ADVISE_AIO                   = "You also run Advanced Interface Options - type /aio for a full CVar browser."

-- Per-cause plain-language tips (shown above the setting suggestions)
L.ADVISE_TIP_COMBAT_FX         = "Combat loads spell and particle effects. The settings below cut that clutter the most."
L.ADVISE_TIP_SCENE             = "Big pulls and crowds load many models at once. Particle Density and View Distance ease it most."
L.ADVISE_TIP_STREAMING         = "Travelling streams the world from disk. An SSD helps most; lower View Distance so the game streams less at once."
L.ADVISE_TIP_SUSTAINED         = "Your frames are broadly slow, not just spiking. Lower the heaviest settings and close background apps (browsers, Discord overlay)."
L.ADVISE_TIP_ENGINE            = "These are isolated one-off frames as the game loads a model or effect. Often normal; the settings below reduce how often they happen."
L.ADVISE_TIP_GC                = "Frequent memory cleanups usually mean a wasteful addon. Check the Top addon sources in the report."
L.ADVISE_TIP_LOADING           = "Loading spikes are normal. A fast SSD shortens them; nothing else to change."

-- == Units and shared fragments ==
-- Format arg: (1) kilobytes
L.UNIT_KB                      = "%d KB"
-- Format arg: (1) megabytes
L.UNIT_MB                      = "%.1f MB"
-- Separator used when joining short phrases into one list.
L.LIST_SEP                     = ", "
-- Durations. Format args: (1) hours, (2) minutes / (1) minutes / (1) seconds
L.DUR_HM                       = "%dh %dm"
L.DUR_M                        = "%dm"
L.DUR_S                        = "%ds"

-- == Allocation buckets ==
-- How much Lua memory a hitching frame allocated. Large means the addon was
-- computing (building tables, serializing); none means it was waiting on the game.
L.ALLOC_NONE                   = "allocating almost nothing"
L.ALLOC_SMALL                  = "allocating a little memory"
L.ALLOC_MEDIUM                 = "allocating a few MB"
L.ALLOC_LARGE                  = "allocating a lot of memory"

-- == Export Report: detail ==
-- Used only on a client whose project we have no name for.
-- Format args: (1) client version, (2) build number
L.EXPORT_CLIENT                = "Client %s (build %s)"
-- The normal client line, naming the game so a pasted report is unambiguous.
-- Format args: (1) game name, (2) client version, (3) build number
L.EXPORT_CLIENT_FLAVOR         = "Client %s %s (build %s)"
-- Turns a raw hitch count into a rate. Format args: (1) duration, (2) per minute
L.EXPORT_SPAN                  = "Measured across %s of play  -  about %.1f a minute."
-- Format args: (1) duration string
L.EXPORT_THROTTLED             = "A further %s is not counted above: the frame rate was capped (window in the background, or a set FPS limit), so nothing was measured."
-- Format args: (1) the capped frame rate, (2) the readable name of the setting
L.EXPORT_BASELINE_CAP          = "Note: your frame rate is limited to %d (%s). That sets the floor here, and no graphics setting below can raise it - change the limit itself."
L.EXPORT_CHRONIC_HEADER        = "Constant addon cost (spent every frame, stutter or not):"
-- Format arg: (1) milliseconds per frame
L.EXPORT_CHRONIC_TOTAL         = "  All addons together: about %.2f ms of every frame."
-- Format args: (1) addon title, (2) ms per frame
L.EXPORT_CHRONIC_LINE          = "  - %s: %.2f ms/frame"
-- Format args: (1) addon title, (2) version, (3) hitch count, (4) peak ms
L.EXPORT_TOP_LINE_VER          = "  - %s (%s)  -  hitches: %d, peak %d ms"
-- The detail lines below are indented six spaces, under their EXPORT_TOP_LINE.
-- Keep the indent.
-- Format arg: (1) "Context xN" items joined with LIST_SEP
L.EXPORT_D_WHERE               = "      Where: %s"
-- Format args: (1) context label, (2) count
L.EXPORT_D_CTX                 = "%s x%d"
-- Format arg: (1) percent of the frame taken by this addon. %% is a literal %.
L.EXPORT_D_SHARE               = "      At its worst it was %d%% of the whole frame"
-- Used when the addon's measured time meets or exceeds the measured frame length.
L.EXPORT_D_SHARE_ALL           = "      At its worst it accounted for essentially the whole frame"
-- Shown when a shared library package is the named culprit.
L.EXPORT_D_LIBRARY             = "      This is a shared library package - the cost belongs to whichever addon called into it, which the game does not let us identify"
-- Format arg: (1) host addon title
L.EXPORT_D_LIBRARY_HOST        = "      This is a shared library package (ships with %s) - the cost belongs to whichever addon called into it"
-- Format arg: (1) multiple of its normal cost
L.EXPORT_D_MULT                = "      Peak was %dx its normal cost"
-- Format arg: (1) formatted size
L.EXPORT_D_ALLOC               = "      Allocated %s on that frame"
-- Format arg: (1) seconds
L.EXPORT_D_PERIOD              = "      Regular rhythm: roughly every %d s (suggests a timer)"
-- This is the CLIENT's own counter, not ours, which is why it can exceed the
-- peak StutterAlert recorded. Format args: (1) times over 100 ms, (2) over 500 ms
L.EXPORT_D_OVER                = "      Game's own session counter  -  frames over 100 ms: %d, over 500 ms: %d"
-- Shown when that counter is far above our own hitch count, which otherwise
-- reads as a contradiction.
L.EXPORT_D_OVER_NOTE           = "      (the client counts the whole session including loading screens, which StutterAlert excludes)"
-- Format args: (1) other addon title, (2) count
L.EXPORT_D_CO                  = "      Also spiked alongside %s (x%d) - likely one shared trigger"
-- Format args: (1) first version seen, (2) last version seen
L.EXPORT_D_VER_SPAN            = "      Recorded across versions %s to %s"
-- Format args: (1) version at the time, (2) version installed now
L.EXPORT_D_VER_NOW             = "      Recorded on %s; you now run %s"
-- Format arg: (1) formatted size
L.EXPORT_D_MEM                 = "      Memory in use: %s"
-- Format args: (1) formatted size, (2) formatted growth
L.EXPORT_D_MEM_GROW            = "      Memory in use: %s (grew %s since the last check)"
-- Format args: (1) matching hitches, (2) total hitches, (3) joined pattern
L.EXPORT_D_SIG                 = "      %d of %d shared one pattern: %s"
-- Used when every hitch matched, which can be a single one, so no count.
-- Format arg: (1) joined pattern
L.EXPORT_D_SIG_ALL             = "      Every hitch shared one pattern: %s"
L.EXPORT_SIG_COMBAT            = "in combat"
L.EXPORT_SIG_CALM              = "out of combat"
-- Event names are technical identifiers and stay untranslated on purpose:
-- they are what an addon author greps for. Format arg: (1) event name
L.EXPORT_SIG_EVENT             = "triggered by %s"

-- == Export Report: events ==
-- Format arg: (1) "EVENT xN" items joined with LIST_SEP
L.EXPORT_D_EV_PEAK             = "      Events on that frame: %s"
-- Format args: (1) event name, (2) count
L.EXPORT_D_EV_ITEM             = "%s x%d"
-- Format args: (1) hitches it fired on, (2) total hitches, (3) event name
L.EXPORT_D_EV_COMMON           = "      Most common event (%d of %d): %s"
-- Format args: (1) addon message prefix, (2) count
L.EXPORT_D_EV_PREFIX           = "      Addon traffic: messages tagged %s (x%d)"
-- Format arg: (1) how many further events fired past the per-frame cap
L.EXPORT_D_EV_BURST            = "      Further events on that frame: %d  -  an event burst"
-- No events at all means the work was not a reaction to one.
L.EXPORT_D_EV_NONE             = "      No events fired on that frame - the work came from an OnUpdate or a timer"

-- CVar display names (the human label for each graphics console variable).
-- The advice sends the player looking for these in the options menu, so use
-- the game's own wording for this language, not a fresh translation. The same
-- goes for the menu path in ADVISE_CHANGE_WHERE.
L.CVAR_MAX_FPS                 = "Max Foreground FPS"
L.CVAR_MAX_FPS_BK              = "Max Background FPS"
L.CVAR_VIEW_DISTANCE           = "View Distance"
L.CVAR_ENV_DETAIL              = "Environment Detail"
L.CVAR_GROUND_CLUTTER          = "Ground Clutter"
L.CVAR_SHADOW                  = "Shadow Quality"
L.CVAR_LIQUID                  = "Liquid Detail"
L.CVAR_SUNSHAFTS               = "Sunshafts"
L.CVAR_PARTICLE                = "Particle Density"
L.CVAR_SSAO                    = "Ambient Occlusion"
L.CVAR_DEPTH                   = "Depth Effects"
L.CVAR_TEXTURE_RES             = "Texture Resolution"
L.CVAR_PROJECTED               = "Projected Textures"
L.CVAR_SPELL_DENSITY           = "Spell Density"

-- == Client / Flavor Names ==
-- Shown in the pasted report's client line so a reader can tell which game the
-- report came from. Flavor.lua maps WOW_PROJECT_ID to one of these keys, and
-- leaves the key unset for a project it has no name for. Use Blizzard's own
-- name for each game in this language.
L.FLAVOR_RETAIL                = "Retail"
L.FLAVOR_MISTS                 = "Mists of Pandaria Classic"
L.FLAVOR_CATA                  = "Cataclysm Classic"
L.FLAVOR_WRATH                 = "Wrath of the Lich King Classic"
L.FLAVOR_TBC                   = "Burning Crusade Classic"
L.FLAVOR_CLASSIC_ERA           = "Classic Era"
