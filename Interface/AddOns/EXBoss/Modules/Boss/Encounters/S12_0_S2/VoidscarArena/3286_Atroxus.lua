---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3286,
    dungeon = { key = "voidscar_arena", name = "Voidscar Arena", zhCN = "虚空之痕竞技场" },
    boss = { key = "atroxus", name = "Atroxus", zhCN = "阿特洛苏斯" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
