---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2139,
    dungeon = { key = "kings_rest", name = "Kings' Rest", zhCN = "诸王之眠" },
    boss = { key = "the_golden_serpent", name = "The Golden Serpent", zhCN = "黄金风蛇" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
