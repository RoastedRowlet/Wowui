---@diagnostic disable: undefined-global

local R = ExBoss and ExBoss.BossEncounters
if not R then return end

R:Register({
    encounterID = 2125,
    dungeon = { key = "temple_of_sethraliss", name = "Temple of Sethraliss", zhCN = "塞塔里斯神庙" },
    boss = { key = "merektha", name = "Merektha", zhCN = "米利克萨" },
    phaseAlerts = {},
    vulnerability = {},
    extras = {},
})
