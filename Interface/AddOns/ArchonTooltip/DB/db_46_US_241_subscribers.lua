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

local lookup = {'DemonHunter-Devourer','Warlock-Demonology','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Retribution','Monk-Windwalker','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Evoker-Augmentation','Mage-Frost','Hunter-BeastMastery','Priest-Holy','DeathKnight-Frost','Druid-Feral','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Hunter-Marksmanship','Monk-Brewmaster','Evoker-Preservation','Rogue-Assassination','Druid-Restoration','Warrior-Arms','Mage-Fire','Paladin-Protection','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='WyrmrestAccord',name='US',type='subscribers',zone=46,date='2026-07-28',data={Ag='Aggrodari:BAECLgAFFH8TAAIBAAUJOSSnIwChAQVoDAAABgBjAGkMAAAFAGMAawwAAAMATABqDAAAAQARAOoMAAAEAF8AAQAFCTkkpyMAoQEFaAwAAAYAYwBpDAAABQBjAGsMAAADAEwAagwAAAEAEQDqDAAABABfAC4ABAp/SAACAQAJCVklagIAYgMAAQAJCVklagIAYgMAAAA=.Aggrorunner:BAEALgADCgMJBQABLgAFFAUJEwABADkkAA==.',
Ah='Ahyri:BAEALgAECgEJAQABLgAECgkJHQACAKIdAA==.',
An='Anuhkin:BAEALgADCgUJBQABLgAFFAYJEwADAEYfAA==.',
Ar='Archoknot:BAEALgAFFAEJAQAAAA==.Arcis:BAECLgAFFH8OAAIEAAQJYhiSFQD4AARoDAAABQBLAGkMAAADAFIAbAwAAAEAHwDqDAAABQA8AAQABAliGJIVAPgABGgMAAAFAEsAaQwAAAMAUgBsDAAAAQAfAOoMAAAFADwALgAECn8nAAQEAAkJASNkAQDAAgAEAAkJASNkAQDAAgABAAYJtw+YkgD7AAAFAAQJahU7FgD3AAAAAA==.',
Ba='Bastianar:BAEALgAECgQJBQABLgAECgkJLwAGACsZAA==.',
Bj='Bjørnulf:BAEALgAECgYJCwAAAA==.',
Bo='Bowbafletch:BAEALgAFFAEJAgABLgAFFAYJEwADAEYfAA==.',
Br='Breadroll:BAECLgAFFH8GAAIHAAIJviHaKQCpAAJoDAAAAgBWAOoMAAAEAFYABwACCb4h2ikAqQACaAwAAAIAVgDqDAAABABWAC4ABAp/HgADBwAJCdwh7wIAaAMABwAJCdwh7wIAaAMACAAECWUdeEgASgEAAAA=.Brendemøn:BAEALgAECgYJCwAAAA==.Brêndêath:BAEALgAECgYJCgABLgAECgYJCwAJAAAAAA==.',
Ca='Caedues:BAECLgAFFH8TAAMDAAYJRh9XTwBTAQZoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAGwMAAABACoA6gwAAAYAVQADAAUJ+SJXTwBTAQVoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAOoMAAAFAFUACgACCacNdjsASAACbAwAAAEAKgDqDAAAAQAbAC4ABAp/IQACAwAJCdAhfBMABgMAAwAJCdAhfBMABgMAAAA=.Calcydo:BAEALgADCgMJAwAAAA==.',
Ch='Chaosity:BAEALgAECgcJEgABLgAECgkJPwALAKkZAA==.Cheeseburber:BAEALgADCgMJAwABLgAECgQJEAAJAAAAAA==.',
Do='Domitian:BAEALgADCgkJCQABLgAECgkJLwAGACsZAA==.',
Dr='Drommekage:BAEBLgAECn8bAAIMAAcJuQbezgDzAAdoDAAABQANAGkMAAAFABQAawwAAAUAIwBqDAAABAATAGwMAAADAA8AbQwAAAEABgDqDAAABAAMAAwABwm5Bt7OAPMAB2gMAAAFAA0AaQwAAAUAFABrDAAABQAjAGoMAAAEABMAbAwAAAMADwBtDAAAAQAGAOoMAAAEAAwAAAA=.',
El='Elvarg:BAEALgAECgEJAQABLgAECgkJGgANAN4YAA==.',
En='Enneth:BAEALgADCgQJBAAAAA==.',
Ev='Eviecera:BAEALgAECgMJAwABLgAFFAYJBQAOAEofAA==.',
Ex='Exesa:BAECLgAFFH8FAAIDAAQJTBX5XwA1AQRoDAAAAQA4AGkMAAABAEEAawwAAAEAGADqDAAAAgBHAAMABAlMFflfADUBBGgMAAABADgAaQwAAAEAQQBrDAAAAQAYAOoMAAACAEcALgAECn8gAAMDAAkJwB1kFwC6AgADAAkJWx1kFwC6AgAPAAUJhhMiFQAxAQAAAA==.',
Fe='Fedja:BAEBLgAECn8cAAQKAAkJXxUVFADTAQloDAAAAwAzAGkMAAADACoAawwAAAMANwBqDAAAAwBGAGwMAAADADwAbQwAAAMAQwDqDAAABQA3AG4MAAADADEAbwwAAAIANwAKAAkJ2hMVFADTAQloDAAAAgAqAGkMAAACABUAawwAAAIANwBqDAAAAgBGAGwMAAACADwAbQwAAAEAQwDqDAAAAgA2AG4MAAACADEAbwwAAAIANwAPAAcJthJIEQBjAQdoDAAAAQAzAGkMAAABACoAagwAAAEAJABsDAAAAQAzAG0MAAACADEA6gwAAAMANwBuDAAAAQAkAAMAAQnfB993ATAAAWsMAAABABQAAS4ABAoJCS8ABgArGQA=.',
Ha='Harivata:BAEALgAECgUJBwABLgAFFAgJEgAQAJgfAA==.',
Hi='Hirenar:BAEALgAECgEJAgABLgAFFAYJEwADAEYfAA==.',
['Hâ']='Hâstery:BAEALgAECggJBwABLgAFFAgJEgAQAJgfAA==.',
Il='Illothe:BAECLgAFFH85AAQCAAkJ4RVlCAAxAgloDAAACgBZAGkMAAAIAFkAawwAAAkAQgBqDAAACQBVAGwMAAAFAFYAbQwAAAMAHQDqDAAACgAzAG4MAAABAA0AbwwAAAIAFQACAAkJ4RVlCAAxAgloDAAACgBZAGkMAAAGAFkAawwAAAkAQgBqDAAACQBVAGwMAAAFAFYAbQwAAAEAHQDqDAAACgAzAG4MAAABAA0AbwwAAAIAFQARAAEJoAnoKABFAAFpDAAAAQAYABIAAgnLABUoAEQAAmkMAAABAAAAbQwAAAIAAwAuAAQKfyoAAwIACQlfIQUSAOsCAAIACAn6IgUSAOsCABIAAwkTFdI3ANYAAAAA.Illothedh:BAEALgADCgMJAwABLgAFFAkJOQACAOEVAA==.',
Im='Imaqt:BAECLgAFFH8FAAIHAAMJxhuTHADrAANoDAAAAQBAAGkMAAABAEoA6gwAAAMASgAHAAMJxhuTHADrAANoDAAAAQBAAGkMAAABAEoA6gwAAAMASgAuAAQKfxkAAgcACAlzILMNAGoCAAcACAlzILMNAGoCAAEuAAUUCQksAA0AFh8A.',
In='Insouciantly:BAEALgAECgIJAgABLgAECgcJGAAOAIgjAA==.',
Ir='Irreverently:BAEBLgAECn8YAAIOAAcJiCMrEgBPAgdoDAAABABNAGkMAAAEAFkAawwAAAQAWgBqDAAAAgBhAGwMAAADAFoAbQwAAAEAYADqDAAABgBgAA4ABwmIIysSAE8CB2gMAAAEAE0AaQwAAAQAWQBrDAAABABaAGoMAAACAGEAbAwAAAMAWgBtDAAAAQBgAOoMAAAGAGAAAAA=.',
Jl='Jlucks:BAECLgAFFH8/AAILAAgJjyL+BAC8AghoDAAACwBiAGkMAAAKAFoAawwAAAoAWwBqDAAACgBaAGwMAAACAFsAbQwAAAIASQDqDAAADwBgAG4MAAADAE0ACwAICY8i/gQAvAIIaAwAAAsAYgBpDAAACgBaAGsMAAAKAFsAagwAAAoAWgBsDAAAAgBbAG0MAAACAEkA6gwAAA8AYABuDAAAAwBNAC4ABAp/TwADCwAJCYIm5gAAgAMACwAJCYIm5gAAgAMAEwABCY0dMR8AWAAAAAA=.Jlucksdh:BAECLgAFFH8hAAIBAAUJqiRUJwCOAQVoDAAACwBgAGkMAAAJAF8AawwAAAQAVQBqDAAAAgA7AOoMAAAHAGIAAQAFCaokVCcAjgEFaAwAAAsAYABpDAAACQBfAGsMAAAEAFUAagwAAAIAOwDqDAAABwBiAC4ABAp/TwACAQAJCSgl5wQAOQMAAQAJCSgl5wQAOQMAAS4ABRQICT8ACwCPIgA=.Jlucksdr:BAEBLgAFFH8OAAIQAAYJkiECAQD0AQZoDAAAAwBcAGkMAAADAFYAawwAAAMASABqDAAAAwBGAGwMAAABAFUA6gwAAAEAWwAQAAYJkiECAQD0AQZoDAAAAwBcAGkMAAADAFYAawwAAAMASABqDAAAAwBGAGwMAAABAFUA6gwAAAEAWwABLgAFFAgJPwALAI8iAA==.Jluckshnt:BAEBLgAFFH8KAAIUAAUJAht7BQB0AQVoDAAAAwBTAGkMAAADAFUA6gwAAAIAQABuDAAAAQAhAG8MAAABAE8AFAAFCQIbewUAdAEFaAwAAAMAUwBpDAAAAwBVAOoMAAACAEAAbgwAAAEAIQBvDAAAAQBPAAEuAAUUCAk/AAsAjyIA.Jlucksmk:BAEBLgAECn9WAAMIAAcJpyUvCwDmAgdoDAAADwBhAGkMAAAOAGIAawwAAA4AYgBqDAAADgBjAGwMAAAMAGIAbQwAAAIAUwDqDAAADwBjAAgABwmnJS8LAOYCB2gMAAANAGEAaQwAAAwAYgBrDAAADABiAGoMAAAKAGMAbAwAAAoAYgBtDAAAAgBTAOoMAAAKAGMAFQAGCasS1TUAJgEGaAwAAAIARgBpDAAAAgAwAGsMAAACACcAagwAAAQALABsDAAAAgAeAOoMAAAFADEAAS4ABRQICT8ACwCPIgA=.',
Ju='Juturna:BAEALgAECgEJAgABLgAFFAkJLAANABYfAA==.Juturnah:BAECLgAFFH8sAAMNAAkJFh9HCwATAgloDAAACgBiAGkMAAAKAFoAawwAAAYAXgBqDAAABABfAGwMAAACAGEAbQwAAAEAVADqDAAACQBbAG4MAAABADcAbwwAAAEAGAANAAgJGR5HCwATAghoDAAABwBiAGkMAAAHAFoAawwAAAQAXgBqDAAABABfAG0MAAABAFQA6gwAAAgAWwBuDAAAAQA3AG8MAAABABgAFAAFCcIUChkA7gAFaAwAAAMAOABpDAAAAwBQAGsMAAACABEAbAwAAAIAYQDqDAAAAQANAC4ABAp/JAADDQAJCU0l+QUALgMADQAJCU0l+QUALgMAFAAHCUIdPSkA4AEAAAA=.',
Ke='Keytana:BAEALgADCgQJBAABLgAFFAkJLAANABYfAA==.',
Ki='Kippee:BAECLgAFFH8cAAIMAAcJjRouMwCcAQdoDAAABwBUAGkMAAAGAEYAawwAAAYASQBqDAAAAgBDAGwMAAABAEgA6gwAAAUAIgBuDAAAAQBJAAwABwmNGi4zAJwBB2gMAAAHAFQAaQwAAAYARgBrDAAABgBJAGoMAAACAEMAbAwAAAEASADqDAAABQAiAG4MAAABAEkALgAECn8nAAIMAAkJTCLPIADwAgAMAAkJTCLPIADwAgAAAA==.Kipplock:BAEBLgAECn8ZAAMCAAkJbxc0BAAPAgloDAAABAA5AGkMAAAEAE0AawwAAAQASQBqDAAAAgBNAGwMAAADAEEAbQwAAAEAIwDqDAAABABGAG4MAAACAD4AbwwAAAEAJQACAAkJbxc0BAAPAgloDAAABAA5AGkMAAAEAE0AawwAAAQASQBqDAAAAQBNAGwMAAADAEEAbQwAAAEAIwDqDAAABABGAG4MAAACAD4AbwwAAAEAJQARAAEJAACNSQAAAAFqDAAAAQA3AAEuAAUUBwkcAAwAjRoA.',
Kr='Kred:BAEALgADCgYJBgABLgAECgkJXAANAOYiAA==.Kredrothi:BAEBLgAECn9cAAINAAkJ5iLgDwDRAgloDAAADABfAGkMAAALAGEAawwAAAwAWABqDAAACwBgAGwMAAALAFMAbQwAAAgATADqDAAADABXAG4MAAAJAF0AbwwAAAYAWwANAAkJ5iLgDwDRAgloDAAADABfAGkMAAALAGEAawwAAAwAWABqDAAACwBgAGwMAAALAFMAbQwAAAgATADqDAAADABXAG4MAAAJAF0AbwwAAAYAWwAAAA==.',
Ku='Kunha:BAEALgADCgkJCQABLgAFFAIJAwAJAAAAAA==.',
La='Laghar:BAEALgAECgEJAQAAAA==.',
Ma='Magicracoon:BAEALgAECgQJEAAAAA==.Malzbier:BAEALgAECggJDAABLgAFFAYJEwADAEYfAA==.Marosia:BAEBLgAECn8rAAMWAAgJiBulAACKAghoDAAACABcAGkMAAAIAFUAawwAAAgAUgBqDAAABQBEAGwMAAAFADYAbQwAAAMANADqDAAABQA6AG4MAAABAEMAFgAICYgbpQAAigIIaAwAAAcAXABpDAAABwBVAGsMAAAIAFIAagwAAAUARABsDAAABQA2AG0MAAADADQA6gwAAAUAOgBuDAAAAQBDABMAAgnnBj04AFcAAmgMAAABAA4AaQwAAAEAFAABLgAFFAMJDwAXABsgAA==.Marroc:BAECLgAFFH8PAAIXAAMJGyACAgASAQNoDAAABQBJAGkMAAADAEoA6gwAAAcAYgAXAAMJGyACAgASAQNoDAAABQBJAGkMAAADAEoA6gwAAAcAYgAuAAQKfz8AAhcACQkkJREAAHQDABcACQkkJREAAHQDAAAA.',
Ne='Nekun:BAEALgAECgMJBgABLgAECgMJBgAJAAAAAA==.',
Ni='Nitedragon:BAECLgAFFH8FAAIWAAEJNAzILQAtAAHqDAAABQAfABYAAQk0DMgtAC0AAeoMAAAFAB8ALgAECn8aAAMWAAgJASAaCABvAgAWAAgJASAaCABvAgATAAMJyANNIABRAAAAAA==.',
No='Nottoasty:BAEALgAFFAIJAgABLgAFFAQJBAAJAAAAAA==.',
Or='Oracs:BAEBLgAECn8VAAQLAAcJ6h9WGAAPAgdoDAAAAwBNAGkMAAADAFgAawwAAAMAXABqDAAABABZAGwMAAADAFIA6gwAAAQAWgBuDAAAAQA6AAsABglgH1YYAA8CBmgMAAABAEoAaQwAAAEAUwBrDAAAAQBcAGwMAAADAFIA6gwAAAIAWgBuDAAAAQA6ABMABQkkHRgXAIQBBWgMAAABAE0AaQwAAAEAWABrDAAAAQBNAGoMAAAEAFkA6gwAAAEANgAWAAQJdAQLOQCiAARoDAAAAQAGAGkMAAABABIAawwAAAEAAwDqDAAAAQAQAAEuAAUUBgkTAAMARh8A.',
Pa='Pai:BAEALgAFFAIJAwABLgAFFAIJBgAHAL4hAA==.',
Pi='Pickups:BAECLgAFFH8HAAIBAAMJtBeeXwDRAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQABAAMJtBeeXwDRAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQAuAAQKfyIAAwUACAmzG0IHABQCAAUABwm/GUIHABQCAAEABwn/FJN8ACcBAAEuAAUUCQkkAAwA6B0A.',
Qa='Qahz:BAECLgAFFH8PAAICAAUJlxUmRgA8AQVoDAAABABRAGkMAAAEAFoAawwAAAMAHQBqDAAAAQAlAOoMAAADABMAAgAFCZcVJkYAPAEFaAwAAAQAUQBpDAAABABaAGsMAAADAB0AagwAAAEAJQDqDAAAAwATAC4ABAp/LQACAgAJCRsi8w4A1AIAAgAJCRsi8w4A1AIAAS4ABRQFCRMAAQA5JAA=.',
Ru='Ruehnar:BAEALgAECgYJDwABLgAECgkJLwAGACsZAA==.',
Si='Sixul:BAEBLgAFFH8JAAIXAAQJ7RGsBQAiAQRoDAAABAA9AGkMAAADAEEAawwAAAEAFADqDAAAAQAkABcABAntEawFACIBBGgMAAAEAD0AaQwAAAMAQQBrDAAAAQAUAOoMAAABACQAAAA=.',
St='Startut:BAEALgAECgIJBAAAAA==.Stillwalker:BAEBLgAECn8YAAIYAAcJyiCoFACQAgdoDAAABQBhAGkMAAAFAF4AawwAAAQAVQBqDAAAAgBYAGwMAAACAE8AbQwAAAIALwDqDAAABABfABgABwnKIKgUAJACB2gMAAAFAGEAaQwAAAUAXgBrDAAABABVAGoMAAACAFgAbAwAAAIATwBtDAAAAgAvAOoMAAAEAF8AAAA=.',
Ta='Tazukey:BAEBLgAECn8VAAIYAAcJQht5OgC8AQdoDAAABQBgAGkMAAAEAFMAawwAAAQAUgBqDAAAAgBMAGwMAAABADsA6gwAAAQARgBuDAAAAQATABgABwlCG3k6ALwBB2gMAAAFAGAAaQwAAAQAUwBrDAAABABSAGoMAAACAEwAbAwAAAEAOwDqDAAABABGAG4MAAABABMAAS4ABAoJCRoADQDeGAA=.',
Te='Tenisia:BAEALgAECgcJDgAAAA==.Teyr:BAEBLgAECn89AAIZAAkJkSFXAwD9AgloDAAACQBgAGkMAAAJAF4AawwAAAkAXABqDAAACABiAGwMAAAHAFMAbQwAAAUAYADqDAAACABhAG4MAAAEADQAbwwAAAIASQAZAAkJkSFXAwD9AgloDAAACQBgAGkMAAAJAF4AawwAAAkAXABqDAAACABiAGwMAAAHAFMAbQwAAAUAYADqDAAACABhAG4MAAAEADQAbwwAAAIASQAAAA==.',
Th='Theò:BAEALgAECgQJBwAAAA==.',
Ti='Titanbp:BAEALgADCgYJCQABLgAFFAkJOQAKACUhAA==.Titandb:BAECLgAFFH85AAIKAAkJJSH0AwBrAgloDAAACwBgAGkMAAAKAGIAawwAAAkAYQBqDAAABwBXAGwMAAACAE4AbQwAAAIAOwDqDAAACQBeAG4MAAADAEEAbwwAAAQAWAAKAAkJJSH0AwBrAgloDAAACwBgAGkMAAAKAGIAawwAAAkAYQBqDAAABwBXAGwMAAACAE4AbQwAAAIAOwDqDAAACQBeAG4MAAADAEEAbwwAAAQAWAAuAAQKfy0AAgoACQksIxAFANsCAAoACQksIxAFANsCAAAA.Titanpp:BAEALgADCgQJCAABLgAFFAkJOQAKACUhAA==.',
Va='Valynithira:BAECLgAFFH8kAAMMAAkJ6B1kEwBTAgloDAAABQBiAGkMAAAFAGAAawwAAAYATQBqDAAABABcAGwMAAAEAE4AbQwAAAEAGgDqDAAABgBdAG4MAAACAEMAbwwAAAMASQAMAAkJ6B1kEwBTAgloDAAABQBiAGkMAAAFAGAAawwAAAYATQBqDAAABABcAGwMAAAEAE4AbQwAAAEAGgDqDAAABgBdAG4MAAACAEMAbwwAAAIASQAaAAEJThQSBQBeAAFvDAAAAQAzAC4ABAp/LwACDAAICeYlpQ8ASwMADAAICeYlpQ8ASwMAAAA=.',
Ve='Velanyr:BAEBLgAECn8dAAICAAkJoh1/MwALAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgACAAkJoh1/MwALAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAAAA==.',
Vi='Viridessia:BAEBLgAECn8/AAQLAAkJqRnHIADTAQloDAAACwBEAGkMAAAKADgAawwAAAoARQBqDAAACAA+AGwMAAAHAEQAbQwAAAIAGwDqDAAACQBYAG4MAAAEAEQAbwwAAAIATgALAAgJrxbHIADTAQhoDAAAAwAtAGkMAAADACcAawwAAAMARQBqDAAAAQAEAGwMAAACABAA6gwAAAUAWABuDAAABABEAG8MAAACAE4AEwAHCTUWXgoAeQEHaAwAAAcARABpDAAABgA4AGsMAAAGAEIAagwAAAUAPgBsDAAABABEAG0MAAACABsA6gwAAAQANQAWAAUJ0gtvBQDGAAVoDAAAAQAJAGkMAAABAC0AawwAAAEAIABqDAAAAgAdAGwMAAABACIAAAA=.',
Vl='Vladja:BAEBLgAECn8vAAMGAAkJKxlkTQDfAQloDAAABwBIAGkMAAAHADMAawwAAAcARwBqDAAABgBSAGwMAAAGAFAAbQwAAAEAHQDqDAAACQBTAG4MAAADAEwAbwwAAAEAMgAGAAgJHRtkTQDfAQhoDAAABwBIAGkMAAAHADMAawwAAAcARwBqDAAABgBSAGwMAAAGAFAA6gwAAAkAUwBuDAAAAwBMAG8MAAABADIAGwABCYoL41AALwABbQwAAAEAHQAAAA==.',
Wr='Wrexilion:BAEALgAECgYJCQAAAA==.',
Yi='Yiangchen:BAEBLgAECn8qAAMVAAkJRR3nCQCUAgloDAAABgBWAGkMAAAGAFsAawwAAAYAOABqDAAABwBWAGwMAAAGAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAAVAAkJRR3nCQCUAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAAIAAUJ5SLyBADwAQVoDAAAAgBbAGkMAAACAGAAawwAAAIAYABqDAAAAgBXAGwMAAABAEoAAS4ABAoJCT8ACwCpGQA=.',
Zi='Zirkondrake:BAEBLgAECn9DAAMcAAkJBSPRBwDiAgloDAAACgBbAGkMAAALAGIAawwAAAkAVwBqDAAACQBiAGwMAAAHAGEAbQwAAAMAUQDqDAAACgBdAG4MAAAHAGEAbwwAAAEARgAcAAkJBSPRBwDiAgloDAAACQBbAGkMAAAJAGIAawwAAAgAVwBqDAAABwBiAGwMAAAGAGEAbQwAAAIAUQDqDAAACABdAG4MAAAGAGEAbwwAAAEARgAdAAgJphviDAAcAghoDAAAAQBFAGkMAAACAFYAawwAAAEATQBqDAAAAgBaAGwMAAABADsAbQwAAAEAJQDqDAAAAgBaAG4MAAABAEwAAAA=.',
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
