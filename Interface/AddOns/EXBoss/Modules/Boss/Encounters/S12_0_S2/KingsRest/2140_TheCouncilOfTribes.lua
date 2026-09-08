---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2140,
    dungeon = { key = "kings_rest", name = "Kings' Rest", zhCN = "诸王之眠" },
    boss = { key = "the_council_of_tribes", name = "The Council of Tribes", zhCN = "部族议会" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
