local _, ns = ...
local L = ns.L

-- enUS is the base locale and always loads, regardless of client language, so
-- it acts as the fallback set. Future locale files (deDE.lua, frFR.lua, ...)
-- should start with:  if GetLocale() ~= "deDE" then return end
-- and then override only the keys they translate.

-- == General ==
L.ADDON_TITLE                  = "StutterAlert"
L.UNKNOWN_SOURCE               = "Unknown"
-- Versioned title used in the tooltip header and export dialog.
-- Format args: (1) addon title, (2) version string
L.TITLE_VERSION                = "%s v%s"

-- == Context Labels ==
L.CTX_CITY                     = "City"
L.CTX_COMBAT_SUFFIX            = "(in combat)"
L.CTX_DUNGEON                  = "Dungeon / M+"
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
-- Format args: (1) addon title, (2) milliseconds
L.HEADLINE_ADDON               = "%s  -  %d ms"
L.HEADLINE_ENGINE              = "Engine spike"
L.HEADLINE_ENGINE_TIP          = "Game engine: usually nothing to do. If it repeats in one spot, the game is streaming assets there."
L.HEADLINE_GC                  = "Memory cleanup"
L.HEADLINE_GC_TIP              = "Memory cleanup: usually nothing. If it keeps happening, an addon may be wasteful - check Top Sources."
L.HEADLINE_LOADING             = "Zone loading"
L.HEADLINE_LOADING_TIP         = "Loading area: this is normal. Running WoW from a fast SSD makes these shorter."
-- Shown when a frame spiked but addon time was low (not the UI's fault)
L.HEADLINE_SERVER              = "Server / latency"
L.HEADLINE_SUSTAINED           = "Sustained slowdown"
L.HEADLINE_SUSTAINED_TIP       = "Sustained slowdown: lower shadows, view distance, or effects, and close background apps."
L.HEADLINE_UNCLEAR             = "Cause unclear"
L.HEADLINE_UNCLEAR_TIP         = "Source unclear: nothing to change yet. Watch Recent and Top for a pattern."

-- == Menu Options ==
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
L.MENU_SIZE_L                  = "Large (128x128)"
L.MENU_SIZE_M                  = "Medium (64x64)"
L.MENU_SIZE_S                  = "Small (32x32)"
L.MENU_TITLE                   = "StutterAlert"
L.PREVIEW_MODE                 = "Preview Mode"

-- == Severity Levels ==
L.SEV_CALM                     = "Calm"
L.SEV_CRITICAL                 = "Critical"
L.SEV_ELEVATED                 = "Elevated"

-- == Slash Commands ==
L.SLASH_DISABLED               = "Monitoring disabled."
L.SLASH_ENABLED                = "Monitoring enabled."
L.SLASH_LOCKED                 = "Overlay locked."
L.SLASH_RESET                  = "Overlay position reset to below the minimap."
L.SLASH_UNLOCKED               = "Overlay unlocked - drag it where you want it."
L.SLASH_USAGE_HEADER           = "StutterAlert commands:"
L.SLASH_USAGE_LOCK             = "/sa lock - lock the overlay in place"
L.SLASH_USAGE_RESET            = "/sa reset - move the overlay back below the minimap"
L.SLASH_USAGE_TOGGLE           = "/sa toggle - turn monitoring on or off"
L.SLASH_USAGE_UNLOCK           = "/sa unlock - unlock to drag the overlay"

-- == Post-pull Summary ==
-- Format args: (1) hitch count, (2) worst source title, (3) worst ms
L.SUMMARY_PULL                 = "Last pull: %d hitches  -  %d from addons, %d from the game"
L.SUMMARY_PULL_CLEAN           = "Last pull: no stutters. Smooth."

-- == Tooltips ==
L.TT_ACTION_ADDON              = "- Addon hitches: Update, reconfigure, or disable repeat offenders."
L.TT_ACTION_ENGINE             = "- Game/engine hitches: usually a one-off as the game loads a model or effect. If it repeats in one spot, lower your graphics settings."
L.TT_ACTION_HEADER             = "How to improve performance:"
L.TT_CTX_COMBAT                = "in combat"
L.TT_CTX_ENEMIES               = "%d enemies"
L.TT_CTX_LATENCY               = "world %d ms"
L.TT_CTX_PREFIX                = "While this happened: %s"
L.TT_HINT_CLEAR                = "Shift Left-Click to clear history"
L.TT_HINT_LOCKED               = "Unlock with /sa unlock to move."
L.TT_HINT_MENU                 = "Right-Click for menu"
L.TT_HINT_UNLOCKED             = "Drag to move. Lock with /sa lock."
L.TT_HITCH_EXPLAIN             = "A 'hitch' is a single frame that took too long to render, causing a visible stutter."
L.TT_RECENT_HEADER             = "Recent hitches"
-- Format args: (1) addon title or non-addon label, (2) ms, (3) context label
L.TT_RECENT_LINE               = "%s  -  %d ms  -  %s"
L.TT_RECENT_NONE               = "No hitches recorded yet."
-- Format args: (1) ms, (2) context label, (3) time ago string
L.TT_RECENT_RIGHT              = "%d ms  -  %s  -  %s"
L.TT_RECENT_RIGHT_MULT         = "%d ms  -  %dx usual  -  %s"
L.TT_SEVERITY                  = "Severity: %s"
L.TT_TIME_HOUR                 = "%dh ago"
L.TT_TIME_MIN                  = "%dm ago"
L.TT_TIME_SEC                  = "%ds ago"
L.TT_TITLE                     = "StutterAlert"
L.TT_TOP_HEADER                = "Top stutter sources (since last cleared)"
-- Format args: (1) addon title, (2) hitch count, (3) peak ms
L.TT_TOP_LINE                  = "%s  -  %d hitches, peak %d ms"
-- Format args: (1) hitch count, (2) peak ms, (3) time ago string
L.TT_TOP_RIGHT                 = "%d hitches  -  %d ms peak  -  %s"

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

-- == Granular Banner Line ==
-- Format args: (1) cause label, (2) milliseconds [, (3) evidence token]
L.HEADLINE_GAME_LINE           = "%s  -  %d ms"
L.HEADLINE_GAME_LINE_EV        = "%s  -  %d ms  -  %s"
L.EV_ENEMIES                   = "%d nearby"
L.EV_FPS                       = "%d FPS"

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
L.TT_PULL_LINE                 = "%d hitches  -  %d game, %d addon  -  worst %d ms"

-- == Post-pull Summary (additional) ==
-- Format args: (1) total hitches, (2) worst source title, (3) worst ms, (4) game-caused count
L.SUMMARY_PULL_WORST           = "Last pull: %d hitches  -  worst %s %d ms (%d from the game)"

-- == Tooltip hint (additional) ==
L.TT_HINT_EXPORT               = "Left-Click for the full report and advice"

-- == Export Report ==
L.EXPORT_VERSION               = "Version %s"
L.EXPORT_SCOPE                 = "Figures below cover everything since history was last cleared."
L.EXPORT_TLDR                  = "%d hitches recorded  -  %d from addons, %d from the game."
L.EXPORT_TLDR_CLEAN            = "No hitches recorded. Smooth so far."
-- Format args: (1) addon title, (2) ms, (3) multiple of its usual cost
L.EXPORT_WORST                 = "Worst addon: %s  -  %d ms (%dx its usual cost)"
L.EXPORT_WORST_NOMULT          = "Worst addon: %s  -  %d ms"
L.EXPORT_TOP_HEADER            = "Top addon sources:"
-- Format args: (1) addon title, (2) hitch count, (3) peak ms
L.EXPORT_TOP_LINE              = "  - %s: %d hitches, peak %d ms"
L.EXPORT_CAUSES_HEADER         = "Game causes (not your addons):"
-- Format args: (1) cause label, (2) count
L.EXPORT_CAUSE_LINE            = "  - %s: %d"
L.EXPORT_BASELINE              = "Typical frame time: %d ms"
L.EXPORT_BASELINE_WARMING      = "Typical frame time: still measuring."
L.EXPORT_FOOTER                = " "
L.EXPORT_COMBAT                = "Report available once you leave combat."

-- == Advice Panel ==
L.PANEL_REPORT_HEADER          = "Shareable report (Ctrl+C to copy)"
L.ADVISE_WHY_HEADER            = "Why am I stuttering?"
L.ADVISE_VERDICT_NONE          = "No stutters recorded yet. Play for a bit, then check back here."
-- Format args: (1) game hitch count, (2) total
L.ADVISE_VERDICT_GAME          = "Most of your stutters come from the game itself, not your addons (%d of %d)."
-- Format args: (1) addon hitch count, (2) total
L.ADVISE_VERDICT_ADDON         = "Most of your stutters come from your addons (%d of %d). See the report on the right for the culprits."
-- Format arg: (1) comma-joined pattern, e.g. "in combat, Dungeon / M+"
L.ADVISE_WHERE                 = "They mostly happen: %s."
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
-- Format args: (1) client version, (2) build number
L.EXPORT_CLIENT                = "Client %s (build %s)"
-- Turns a raw hitch count into a rate. Format args: (1) duration, (2) per minute
L.EXPORT_SPAN                  = "Measured across %s of play  -  about %.1f a minute."
L.EXPORT_CHRONIC_HEADER        = "Constant addon cost (spent every frame, stutter or not):"
-- Format arg: (1) milliseconds per frame
L.EXPORT_CHRONIC_TOTAL         = "  All addons together: about %.2f ms of every frame."
-- Format args: (1) addon title, (2) ms per frame
L.EXPORT_CHRONIC_LINE          = "  - %s: %.2f ms/frame"
-- Format args: (1) addon title, (2) version, (3) hitch count, (4) peak ms
L.EXPORT_TOP_LINE_VER          = "  - %s (%s): %d hitches, peak %d ms"
-- Singular forms, so a single hitch never reads as "1 hitches".
-- Format args: (1) addon title, (2) peak ms
L.EXPORT_TOP_LINE_ONE          = "  - %s: 1 hitch, peak %d ms"
-- Format args: (1) addon title, (2) version, (3) peak ms
L.EXPORT_TOP_LINE_VER_ONE      = "  - %s (%s): 1 hitch, peak %d ms"
-- Format arg: (1) comma-joined "Context xN" list
L.EXPORT_D_WHERE               = "      Where: %s"
-- Format args: (1) context label, (2) count
L.EXPORT_D_CTX                 = "%s x%d"
-- Format arg: (1) percent of the frame taken by this addon
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
L.EXPORT_D_PERIOD              = "      Regular rhythm: roughly every %d seconds (suggests a timer)"
-- Counts use "xN" notation so no phrasing has to agree with a number.
-- This is the CLIENT's own counter, not ours, which is why it can exceed the
-- peak StutterAlert recorded. Format args: (1) times over 100 ms, (2) over 500 ms
L.EXPORT_D_OVER                = "      Game's own session counter: %d frames over 100 ms, %d over 500 ms"
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
-- Used when every hitch matched. Format args: (1) hitch count, (2) joined pattern
L.EXPORT_D_SIG_ALL             = "      All %d shared one pattern: %s"
L.EXPORT_SIG_COMBAT            = "in combat"
L.EXPORT_SIG_CALM              = "out of combat"
-- Event names are technical identifiers and stay untranslated on purpose:
-- they are what an addon author greps for. Format arg: (1) event name
L.EXPORT_SIG_EVENT             = "triggered by %s"

-- == Export Report: events ==
-- Format arg: (1) comma-joined "EVENT xN" list
L.EXPORT_D_EV_PEAK             = "      Events on that frame: %s"
-- Format args: (1) event name, (2) count
L.EXPORT_D_EV_ITEM             = "%s x%d"
-- Format args: (1) hitches it fired on, (2) total hitches, (3) event name
L.EXPORT_D_EV_COMMON           = "      Fired on %d of %d hitches: %s"
-- Format args: (1) addon message prefix, (2) count
L.EXPORT_D_EV_PREFIX           = "      Addon traffic: messages tagged %s (x%d)"
-- Format arg: (1) how many further events fired past the per-frame cap
L.EXPORT_D_EV_BURST            = "      Plus %d more events on that frame - an event burst"
-- No events at all means the work was not a reaction to one.
L.EXPORT_D_EV_NONE             = "      No events fired on that frame - the work came from an OnUpdate or a timer"

-- CVar display names (the human label for each graphics console variable)
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