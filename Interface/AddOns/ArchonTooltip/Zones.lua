---@class Private
local Private = select(2, ...)

Private.Zones[53] = {
    id = 53,
    name = "The Venomous Abyss",
    hasMultipleDifficulties = true,
    hasMultipleSizes = false,
    encounters = {
        { id = 3470, },
        { id = 3445, },
        { id = 3455, },
        { id = 3497, },
        { id = 3420, },
        { id = 3421, },
        { id = 3429, },
        { id = 3492, },
        { id = 3379, },
        { id = 3513, },
    },
    difficultyIconMap = nil,
}

Private.Zones[1054] = {
    id = 1054,
    name = "Siege of Orgrimmar",
    hasMultipleDifficulties = true,
    hasMultipleSizes = true,
    encounters = {
        { id = 51602, },
        { id = 51598, },
        { id = 51624, },
        { id = 51604, },
        { id = 51622, },
        { id = 51600, },
        { id = 51606, },
        { id = 51603, },
        { id = 51595, },
        { id = 51594, },
        { id = 51599, },
        { id = 51601, },
        { id = 51593, },
        { id = 51623, },
    },
    difficultyIconMap = nil,
}

Private.Zones[2018] = {
    id = 2018,
    name = "Scarlet Enclave",
    hasMultipleDifficulties = false,
    hasMultipleSizes = true,
    encounters = {
        { id = 3185, },
        { id = 3187, },
        { id = 3186, },
        { id = 3197, },
        { id = 3196, },
        { id = 3188, },
        { id = 3190, },
        { id = 3189, },
    },
    difficultyIconMap = nil,
}

Private.Zones[1060] = {
    id = 1060,
    name = "BT / Hyjal",
    hasMultipleDifficulties = false,
    hasMultipleSizes = false,
    encounters = {
        { id = 50601, },
        { id = 50602, },
        { id = 50603, },
        { id = 50604, },
        { id = 50605, },
        { id = 50606, },
        { id = 50607, },
        { id = 50608, },
        { id = 50609, },
        { id = 50618, },
        { id = 50619, },
        { id = 50620, },
        { id = 50621, },
        { id = 50622, },
    },
    difficultyIconMap = nil,
}

for _, zone in pairs(Private.Zones) do
    for _, encounter in pairs(zone.encounters) do
        Private.EncounterZoneIdMap[encounter.id] = zone.id
    end
end