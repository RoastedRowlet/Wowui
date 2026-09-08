---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2142,
    dungeon = { key = "kings_rest", name = "Kings' Rest", zhCN = "诸王之眠" },
    boss = { key = "mchimba_the_embalmer", name = "Mchimba the Embalmer", zhCN = "殓尸者姆沁巴" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
