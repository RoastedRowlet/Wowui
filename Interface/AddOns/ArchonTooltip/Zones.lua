---@class Private
local Private = select(2, ...)

Private.Zones[46] = {
    id = 46,
    name = "VS / DR / MQD",
    hasMultipleDifficulties = true,
    hasMultipleSizes = false,
    encounters = {
        { id = 3176, },
        { id = 3177, },
        { id = 3179, },
        { id = 3178, },
        { id = 3180, },
        { id = 3181, },
        { id = 3306, },
        { id = 3182, },
        { id = 3183, },
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

Private.Zones[1056] = {
    id = 1056,
    name = "SSC / TK",
    hasMultipleDifficulties = false,
    hasMultipleSizes = false,
    encounters = {
        { id = 100623, },
        { id = 100624, },
        { id = 100625, },
        { id = 100626, },
        { id = 100627, },
        { id = 100628, },
        { id = 100730, },
        { id = 100731, },
        { id = 100732, },
        { id = 100733, },
    },
    difficultyIconMap = nil,
}

for _, zone in pairs(Private.Zones) do
    for _, encounter in pairs(zone.encounters) do
        Private.EncounterZoneIdMap[encounter.id] = zone.id
    end
end