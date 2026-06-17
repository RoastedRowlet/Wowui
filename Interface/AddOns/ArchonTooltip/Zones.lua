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

Private.Zones[1046] = {
    id = 1046,
    name = "Throne of Thunder",
    hasMultipleDifficulties = true,
    hasMultipleSizes = true,
    encounters = {
        { id = 51577, },
        { id = 51575, },
        { id = 51570, },
        { id = 51565, },
        { id = 51578, },
        { id = 51573, },
        { id = 51572, },
        { id = 51574, },
        { id = 51576, },
        { id = 51559, },
        { id = 51560, },
        { id = 51579, },
        { id = 51580, },
    },
    difficultyIconMap = nil,
}

Private.Zones[1055] = {
    id = 1055,
    name = "Throne of Thunder",
    hasMultipleDifficulties = true,
    hasMultipleSizes = true,
    encounters = {
        { id = 101577, },
        { id = 101575, },
        { id = 101570, },
        { id = 101565, },
        { id = 101578, },
        { id = 101573, },
        { id = 101572, },
        { id = 101574, },
        { id = 101576, },
        { id = 101559, },
        { id = 101560, },
        { id = 101579, },
        { id = 101580, },
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

Private.Zones[1057] = {
    id = 1057,
    name = "ToC / ZG",
    hasMultipleDifficulties = false,
    hasMultipleSizes = false,
    encounters = {
        { id = 100629, },
        { id = 100633, },
        { id = 100637, },
        { id = 100641, },
        { id = 100645, },
        { id = 200784, },
        { id = 200785, },
        { id = 200786, },
        { id = 200787, },
        { id = 200788, },
        { id = 200789, },
        { id = 200790, },
        { id = 200791, },
        { id = 200792, },
        { id = 200793, },
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