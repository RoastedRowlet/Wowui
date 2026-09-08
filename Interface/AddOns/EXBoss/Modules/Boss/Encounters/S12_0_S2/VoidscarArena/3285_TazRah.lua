---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3285,
    dungeon = { key = "voidscar_arena", name = "Voidscar Arena", zhCN = "虚空之痕竞技场" },
    boss = { key = "taz_rah", name = "Taz'Rah", zhCN = "塔兹拉尔" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
