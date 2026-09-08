---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2126,
    dungeon = { key = "temple_of_sethraliss", name = "Temple of Sethraliss", zhCN = "塞塔里斯神庙" },
    boss = { key = "galvazzt", name = "Galvazzt", zhCN = "加瓦兹特" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
