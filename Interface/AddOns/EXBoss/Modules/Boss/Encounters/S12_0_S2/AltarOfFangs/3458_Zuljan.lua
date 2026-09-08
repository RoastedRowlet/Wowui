---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3458,
    dungeon = { key = "altar_of_fangs", name = "Altar of Fangs", zhCN = "毒牙祭坛" },
    boss = { key = "zul_jan", name = "Zul'jan", zhCN = "祖尔加" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
