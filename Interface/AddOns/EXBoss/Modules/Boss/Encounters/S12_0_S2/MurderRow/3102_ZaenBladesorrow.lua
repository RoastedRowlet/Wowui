---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3102,
    dungeon = { key = "murder_row", name = "Murder Row", zhCN = "密谋小径" },
    boss = { key = "zaen_bladesorrow", name = "Zaen Bladesorrow", zhCN = "赞恩·刃悲" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
