local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Rogue-Subtlety','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Mage-Frost','Warlock-Demonology','Rogue-Outlaw','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Druid-Feral','Warrior-Protection','Priest-Shadow','Priest-Discipline','Priest-Holy','DemonHunter-Devourer','Hunter-BeastMastery',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-05-21',data={As='Astaren:BAEALgAECgcJDQAAAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8HAAIBAAMJiiH3HwCUAANoDAAAAQBLAGoMAAACADkA6gwAAAQAXwABAAMJiiH3HwCUAANoDAAAAQBLAGoMAAACADkA6gwAAAQAXwAuAAQKfyAAAwEACQnbHqsGAMoCAAEACQnbHqsGAMoCAAIABwljERxxAKUBAAEuAAUUBAkRAAMAUCIA.Brylic:BAECLgAFFH8RAAMDAAQJUCK5DAB9AQRoDAAABQBYAGkMAAAGAGEAawwAAAQAWQDqDAAAAgBMAAMABAnTH7kMAH0BBGgMAAAFAFgAaQwAAAYAYQBrDAAABABZAOoMAAABADMABAABCe8d8igAWQAB6gwAAAEATAAuAAQKfyYAAwQACAk5IyQGAB8DAAQACAkmISQGAB8DAAMACAmqIjIIAAIDAAAA.',
Ca='Camreon:BAEALgAFFAEJAQAAAA==.Captpando:BAEALgAECgQJBAABLgAFFAkJEAAFAKMcAA==.',
Cm='Cmenstabber:BAEBLgAECn8nAAIGAAgJnRaJFADTAQhoDAAABwA4AGkMAAAGAEoAawwAAAYARwBqDAAABQA8AGwMAAAFAFkAbQwAAAEACQDqDAAABwA0AG4MAAACADIABgAICZ0WiRQA0wEIaAwAAAcAOABpDAAABgBKAGsMAAAGAEcAagwAAAUAPABsDAAABQBZAG0MAAABAAkA6gwAAAcANABuDAAAAgAyAAAA.',
Fi='Fishybrew:BAEBLgAECn8qAAIDAAYJMiKAFADlAQZoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAA6gwAAAcAXQADAAYJMiKAFADlAQZoDAAACQBaAGkMAAAIAFsAawwAAAcAUgBqDAAABgBYAGwMAAAFAFAA6gwAAAcAXQABLgADCgEJAQAHAAAAAA==.',
Fl='Fleasfordays:BAEALgAECgEJAQABLgAECggJJwAGAJ0WAA==.',
Fo='Foxblade:BAEALgAECgcJDAAAAA==.Foxorcism:BAEBLgAECn8WAAMIAAYJeRgGKwCKAQZoDAAABABSAGkMAAAEADEAawwAAAQATABqDAAABAA3AGwMAAACAB0A6gwAAAQAUgAIAAYJeRgGKwCKAQZoDAAAAwBSAGkMAAADADEAawwAAAMATABqDAAABAA3AGwMAAACAB0A6gwAAAQAUgAJAAMJfQfGDQFrAANoDAAAAQAqAGkMAAABAAUAawwAAAEACQABLgAECgcJDAAHAAAAAA==.Foxox:BAEBLgAECn8WAAIKAAYJkBkzZwCMAQZoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAAAgBGAG0MAAABADIA6gwAAAMARQAKAAYJkBkzZwCMAQZoDAAABwBKAGkMAAAFAEIAawwAAAQAPgBsDAAAAgBGAG0MAAABADIA6gwAAAMARQABLgAECgcJDAAHAAAAAA==.',
Fr='Fries:BAEALgAECgcJCgABLgAFFAQJBwALAKYPAA==.',
Ga='Gardenweed:BAEBLgAECn8YAAIJAAcJ1gnGlwAfAQdoDAAABAAjAGkMAAAEABoAawwAAAQAEwBqDAAABAASAGwMAAAEACgAbQwAAAEADwDqDAAAAwANAAkABwnWCcaXAB8BB2gMAAAEACMAaQwAAAQAGgBrDAAABAATAGoMAAAEABIAbAwAAAQAKABtDAAAAQAPAOoMAAADAA0AAAA=.',
Gu='Guthyne:BAEALgAECgMJAwABLgAECgkJIgAMAOYjAA==.Guthynn:BAEBLgAECn8iAAMMAAkJ5iPDAAAdAwloDAAABwBhAGkMAAAFAFwAawwAAAUAYQBqDAAAAgBiAGwMAAABAFkAbQwAAAMAQwDqDAAABQBjAG4MAAAFAGEAbwwAAAEAXgAMAAkJ5iPDAAAdAwloDAAABQBhAGkMAAAFAFwAawwAAAUAYQBqDAAAAgBiAGwMAAABAFkAbQwAAAMAQwDqDAAABQBjAG4MAAAFAGEAbwwAAAEAXgANAAEJzBteHQBAAAFoDAAAAgBHAAAA.',
Ir='Irro:BAEALgAECgUJBQABLgAECggJKwAOAGAfAA==.Irrogenia:BAEBLgAECn8rAAMOAAgJYB/xDwCgAghoDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAMANQDqDAAACABVAG4MAAAEAEAADgAICWAf8Q8AoAIIaAwAAAcAYABpDAAABgBVAGsMAAAFAGEAagwAAAQARgBsDAAABABZAG0MAAADADUA6gwAAAgAVQBuDAAABABAAA8AAgn9ChdxAFcAAmkMAAABACIAawwAAAEAFQAAAA==.',
Li='Lidariel:BAEALgAECggJDwABLgAFFAMJBwAQABwKAA==.Lidathra:BAECLgAFFH8HAAIQAAMJHAogGgC1AANoDAAAAwAVAGkMAAACAC8A6gwAAAIACQAQAAMJHAogGgC1AANoDAAAAwAVAGkMAAACAC8A6gwAAAIACQAuAAQKfywAAhAACQnmFTMJACsCABAACQnmFTMJACsCAAAA.Lidiosa:BAEBLgAECn8eAAIKAAgJ9xMYUwDAAQhoDAAABgAyAGkMAAAEADkAawwAAAQAKQBqDAAAAwASAGwMAAADADAAbQwAAAEAJwDqDAAACAArAG4MAAABAEwACgAICfcTGFMAwAEIaAwAAAYAMgBpDAAABAA5AGsMAAAEACkAagwAAAMAEgBsDAAAAwAwAG0MAAABACcA6gwAAAgAKwBuDAAAAQBMAAEuAAUUAwkHABAAHAoA.Lidizine:BAEALgADCggJDAABLgAFFAMJBwAQABwKAA==.',
Lo='Lochru:BAEBLgAECn80AAIRAAkJ7B7xAgDFAgloDAAACABdAGkMAAAHAFMAawwAAAgAUgBqDAAABgBSAGwMAAAGAFYAbQwAAAUAPQDqDAAABwBMAG4MAAAEAFQAbwwAAAEAQAARAAkJ7B7xAgDFAgloDAAACABdAGkMAAAHAFMAawwAAAgAUgBqDAAABgBSAGwMAAAGAFYAbQwAAAUAPQDqDAAABwBMAG4MAAAEAFQAbwwAAAEAQAAAAA==.',
Ma='Makoto:BAEBLgAECn8aAAISAAcJlR3sCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABIABwmVHewLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Ne='Neodefender:BAECLgAFFH8jAAIIAAYJKCbAAQCPAgZoDAAACQBjAGkMAAAIAF4AawwAAAYAYwBqDAAABABjAGwMAAABAF4A6gwAAAcAYQAIAAYJKCbAAQCPAgZoDAAACQBjAGkMAAAIAF4AawwAAAYAYwBqDAAABABjAGwMAAABAF4A6gwAAAcAYQAuAAQKfzIAAggACQnnJvwAAIgDAAgACQnnJvwAAIgDAAAA.',
No='Nosferratu:BAECLgAFFH8hAAMTAAcJXhwOAgA5AgdoDAAACABjAGkMAAAFACwAawwAAAUAWwBqDAAABQAcAGwMAAACAD0A6gwAAAcAYgBuDAAAAQAoABMABwleHA4CADkCB2gMAAAIAGMAaQwAAAQALABrDAAABABbAGoMAAAFABwAbAwAAAIAPQDqDAAABwBiAG4MAAABACgAFAACCTgHei0AhwACaQwAAAEADwBrDAAAAQAVAC4ABAp/PwACEwAJCYQmYQAAigMAEwAJCYQmYQAAigMAAAA=.',
Ny='Nyfaria:BAECLgAFFH8XAAIDAAUJtBUKFwA0AQVoDAAABwBLAGkMAAAGADMAawwAAAMALABqDAAAAgBJAOoMAAAFADMAAwAFCbQVChcANAEFaAwAAAcASwBpDAAABgAzAGsMAAADACwAagwAAAIASQDqDAAABQAzAC4ABAp/IgACAwAJCY4VGQ4AMgIAAwAJCY4VGQ4AMgIAAAA=.',
Or='Orsp:BAECLgAFFH8bAAQTAAcJrxYABgC1AQdoDAAABQBLAGkMAAADAEwAawwAAAQATABqDAAABABHAGwMAAACAAIAbQwAAAEAGwDqDAAACABaABMABgkNGwAGALUBBmgMAAAFAEsAaQwAAAMATABrDAAABABMAGoMAAACAEcAbQwAAAEAGwDqDAAACABaABQAAgk8AT4WAH4AAmoMAAABAAAAbAwAAAIABQAVAAEJRgHuFABBAAFqDAAAAQADAC4ABAp/KQAEEwAJCSsjOwUAPQMAEwAJCSsjOwUAPQMAFQADCcoKCGUAmQAAFAADCcEZ30YAhgAAAAA=.Orspp:BAECLgAFFH8FAAMTAAMJbxFaIACkAANoDAAAAgBAAGkMAAACADsA6gwAAAEACQATAAIJOxhaIACkAAJoDAAAAgBAAGkMAAACADsAFAABCcgFPDYARwAB6gwAAAEADgAuAAQKfxsABBMABwl8GG4hAMwBABMABwl8GG4hAMwBABUABgmlCCJJABQBABQAAQm1DcNVADYAAAEuAAUUBwkbABMArxYA.',
Pa='Pakk:BAEBLgAECn8fAAIBAAcJDB/7DAACAgdoDAAABwBeAGkMAAAGAE4AawwAAAUAQwBqDAAABABJAGwMAAAEAEQA6gwAAAQAXQBuDAAAAQBJAAEABwkMH/sMAAICB2gMAAAHAF4AaQwAAAYATgBrDAAABQBDAGoMAAAEAEkAbAwAAAQARADqDAAABABdAG4MAAABAEkAAAA=.Pandoken:BAEALgAFFAgJAwABLgAFFAkJEAAFAKMcAA==.Pandotides:BAEALgAFFAUJAgABLgAFFAkJEAAFAKMcAA==.Papadefensve:BAEALgADCgEJAQAAAA==.',
Ra='Razamon:BAEBLgAECn8rAAMOAAkJMSFeEwB9AgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAAOAAkJMSFeEwB9AgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAPAAcJgxiJLgCpAQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAFFAIJAgABLgAFFAgJHwALAPETAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAQJEQADAFAiAA==.',
Ro='Roukedhh:BAECLgAFFH8PAAIWAAUJGhcyMAAlAQVoDAAABABSAGkMAAADAEoAawwAAAIAEgBqDAAAAQADAOoMAAAFAD0AFgAFCRoXMjAAJQEFaAwAAAQAUgBpDAAAAwBKAGsMAAACABIAagwAAAEAAwDqDAAABQA9AC4ABAp/HgACFgAICachkBYAzwIAFgAICachkBYAzwIAAAA=.',
Ru='Runehaven:BAEALgAECgYJEQABLgAFFAgJIwAFAFsbAA==.',
Sa='Sargala:BAEBLgAECn8bAAIXAAYJGBeVYABQAQZoDAAABwBLAGkMAAAGAEkAawwAAAYANwBqDAAAAgApAGwMAAACADMA6gwAAAQAJwAXAAYJGBeVYABQAQZoDAAABwBLAGkMAAAGAEkAawwAAAYANwBqDAAAAgApAGwMAAACADMA6gwAAAQAJwAAAA==.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAHAAAAAA==.Scootypriest:BAEALgADCggJCAABLgAECgUJBQAHAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAHAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAHAAAAAA==.',
Th='Thez:BAEALgADCgYJBgABLgAECgcJIwASAGIbAA==.Thezdin:BAEBLgAECn8jAAISAAcJYhsKEgDnAQdoDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACABPABIABwliGwoSAOcBB2gMAAAGAFgAaQwAAAYATwBrDAAABgBOAGoMAAAEAD4AbAwAAAMASwBtDAAAAgASAOoMAAAIAE8AAAA=.Thezfu:BAEALgAECgEJAgABLgAECgcJIwASAGIbAA==.',
Ve='Velohm:BAEALgAECgUJCQAAAA==.',
Zi='Zick:BAEALgAFFAYJAQAAAA==.Zikker:BAEALgADCgcJBwABLgAFFAYJAQAHAAAAAA==.',
Zo='Zoe:BAECLgAFFH8YAAIDAAcJXx6CAQBfAgdoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgBuDAAAAQAwAAMABwlfHoIBAF8CB2gMAAAFAFkAaQwAAAUAYwBrDAAABABSAGwMAAABACUAbQwAAAEAXwDqDAAABwBaAG4MAAABADAALgAECn8vAAIDAAgJVyajAwD2AgADAAgJVyajAwD2AgAAAA==.Zogle:BAEBLgAFFH8JAAIBAAUJGRPAFAD4AAVoDAAAAQA3AGkMAAABAC4AawwAAAEAPABqDAAABQAcAOoMAAABACEAAQAFCRkTwBQA+AAFaAwAAAEANwBpDAAAAQAuAGsMAAABADwAagwAAAUAHADqDAAAAQAhAAEuAAUUBwkYAAMAXx4A.Zoog:BAEALgAECggJEwABLgAFFAcJGAADAF8eAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
