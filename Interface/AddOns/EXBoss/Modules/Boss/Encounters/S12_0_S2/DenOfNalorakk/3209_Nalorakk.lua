---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 3209,
    dungeon = { key = "den_of_nalorakk", name = "Den of Nalorakk", zhCN = "纳洛拉克的洞穴" },
    boss = { key = "nalorakk", name = "Nalorakk", zhCN = "纳洛拉克" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
