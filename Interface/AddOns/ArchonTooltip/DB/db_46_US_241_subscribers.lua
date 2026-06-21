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

local lookup = {'DemonHunter-Devourer','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Evoker-Augmentation','Mage-Frost','Hunter-BeastMastery','Priest-Holy','DeathKnight-Frost','Paladin-Retribution','Druid-Feral','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Hunter-Marksmanship','Monk-Brewmaster','Rogue-Assassination','Evoker-Preservation','Mage-Arcane','Druid-Restoration','Warrior-Arms','Paladin-Protection','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='WyrmrestAccord',name='US',type='subscribers',zone=46,date='2026-06-19',data={Ag='Aggrodari:BAECLgAFFH8TAAIBAAUJOSS7IwChAQVoDAAABgBjAGkMAAAFAGMAawwAAAMATABqDAAAAQARAOoMAAAEAF8AAQAFCTkkuyMAoQEFaAwAAAYAYwBpDAAABQBjAGsMAAADAEwAagwAAAEAEQDqDAAABABfAC4ABAp/SAACAQAJCVklagIAYgMAAQAJCVklagIAYgMAAAA=.Aggrorunner:BAEALgADCgMJBQABLgAFFAUJEwABADkkAA==.',
An='Anuhkin:BAEALgADCgUJBQABLgAFFAYJEgACAEYfAA==.',
Ar='Archoknot:BAEALgAFFAEJAQAAAA==.Arcis:BAECLgAFFH8MAAIDAAMJahyRFQD4AANoDAAABQBLAGkMAAADAFIA6gwAAAQAPAADAAMJahyRFQD4AANoDAAABQBLAGkMAAADAFIA6gwAAAQAPAAuAAQKfx4ABAMACQkSHv0OADYCAAMABwn+Hv0OADYCAAEABgm3D5SSAPsAAAQABAlqFTwWAPcAAAAA.',
Bj='Bjørnulf:BAEALgAECgYJCwAAAA==.',
Bo='Bowbafletch:BAEALgAFFAEJAgABLgAFFAYJEgACAEYfAA==.',
Br='Breadroll:BAECLgAFFH8GAAIFAAIJviHdKQCpAAJoDAAAAgBWAOoMAAAEAFYABQACCb4h3SkAqQACaAwAAAIAVgDqDAAABABWAC4ABAp/HgADBQAJCdwh7wIAaAMABQAJCdwh7wIAaAMABgAECWUdeUgASgEAAAA=.Brendemøn:BAEALgAECgYJCwAAAA==.Brêndêath:BAEALgAECgYJCgABLgAECgYJCwAHAAAAAA==.',
Ca='Caedues:BAECLgAFFH8SAAMCAAYJRh9fTwBTAQZoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAGwMAAABACoA6gwAAAUAVQACAAUJ+SJfTwBTAQVoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAOoMAAAFAFUACAABCXoQdzsASAABbAwAAAEAKgAuAAQKfyEAAgIACQnQIXwTAAYDAAIACQnQIXwTAAYDAAAA.',
Ch='Chaosity:BAEALgAECgcJEgABLgAECgkJNQAJAKkZAA==.Cheeseburber:BAEALgADCgMJAwABLgAECgQJEAAHAAAAAA==.',
Dr='Drommekage:BAEBLgAECn8bAAIKAAcJuQbXzgDzAAdoDAAABQANAGkMAAAFABQAawwAAAUAIwBqDAAABAATAGwMAAADAA8AbQwAAAEABgDqDAAABAAMAAoABwm5BtfOAPMAB2gMAAAFAA0AaQwAAAUAFABrDAAABQAjAGoMAAAEABMAbAwAAAMADwBtDAAAAQAGAOoMAAAEAAwAAAA=.',
El='Elvarg:BAEALgAECgEJAQABLgAECgkJGgALAN8YAA==.',
En='Enneth:BAEALgADCgQJBAAAAA==.',
Ev='Eviecera:BAEALgADCgUJBQABLgAFFAYJBQAMAEofAA==.',
Ex='Exesa:BAECLgAFFH8FAAICAAQJTBUEYAA1AQRoDAAAAQA4AGkMAAABAEEAawwAAAEAGADqDAAAAgBHAAIABAlMFQRgADUBBGgMAAABADgAaQwAAAEAQQBrDAAAAQAYAOoMAAACAEcALgAECn8gAAMCAAkJwB1kFwC6AgACAAkJWx1kFwC6AgANAAUJhhMiFQAxAQAAAA==.',
Fe='Fedja:BAEBLgAECn8cAAQIAAkJXxUUFADTAQloDAAAAwAzAGkMAAADACoAawwAAAMANwBqDAAAAwBGAGwMAAADADwAbQwAAAMAQwDqDAAABQA3AG4MAAADADEAbwwAAAIANwAIAAkJ2hMUFADTAQloDAAAAgAqAGkMAAACABUAawwAAAIANwBqDAAAAgBGAGwMAAACADwAbQwAAAEAQwDqDAAAAgA2AG4MAAACADEAbwwAAAIANwANAAcJthJIEQBjAQdoDAAAAQAzAGkMAAABACoAagwAAAEAJABsDAAAAQAzAG0MAAACADEA6gwAAAMANwBuDAAAAQAkAAIAAQnfB9h3ATAAAWsMAAABABQAAS4ABAoICSsADgCdGQA=.',
Hi='Hirenar:BAEALgAECgEJAgABLgAFFAYJEgACAEYfAA==.',
['Hâ']='Hâstery:BAEALgAECggJBwABLgAFFAcJDQAPAG0dAA==.',
Il='Illothe:BAECLgAFFH8xAAQQAAcJVhZeEABeAQdoDAAACQBZAGkMAAAIAFkAawwAAAkAQgBqDAAACABVAGwMAAAEACoAbQwAAAIAAwDqDAAACQAzABAABgmOGl4QAF4BBmgMAAAJAFkAaQwAAAYAWQBrDAAACQBCAGoMAAAIAFUAbAwAAAQAKgDqDAAACQAzABEAAQmgCeYoAEUAAWkMAAABABgAEgACCcsAGSgARAACaQwAAAEAAABtDAAAAgADAC4ABAp/KgADEAAJCV8hBRIA6wIAEAAICfoiBRIA6wIAEgADCRMV0jcA1gAAAAA=.Illothedh:BAEALgADCgMJAwABLgAFFAcJMQAQAFYWAA==.',
In='Insouciantly:BAEALgAECgIJAgABLgAECgcJGAAMAIgjAA==.',
Ir='Irreverently:BAEBLgAECn8YAAIMAAcJiCMrEgBPAgdoDAAABABNAGkMAAAEAFkAawwAAAQAWgBqDAAAAgBhAGwMAAADAFoAbQwAAAEAYADqDAAABgBgAAwABwmIIysSAE8CB2gMAAAEAE0AaQwAAAQAWQBrDAAABABaAGoMAAACAGEAbAwAAAMAWgBtDAAAAQBgAOoMAAAGAGAAAAA=.',
Jl='Jlucks:BAECLgAFFH8zAAIJAAgJiiILBQC6AghoDAAACQBiAGkMAAAIAFoAawwAAAgAWwBqDAAACABaAGwMAAACAFsAbQwAAAIASQDqDAAADQBgAG4MAAABAE0ACQAICYoiCwUAugIIaAwAAAkAYgBpDAAACABaAGsMAAAIAFsAagwAAAgAWgBsDAAAAgBbAG0MAAACAEkA6gwAAA0AYABuDAAAAQBNAC4ABAp/TwADCQAJCYIm5QAAgAMACQAJCYIm5QAAgAMAEwABCY0dMR8AWAAAAAA=.Jlucksdh:BAECLgAFFH8hAAIBAAUJqiRqJwCOAQVoDAAACwBgAGkMAAAJAF8AawwAAAQAVQBqDAAAAgA7AOoMAAAHAGIAAQAFCaokaicAjgEFaAwAAAsAYABpDAAACQBfAGsMAAAEAFUAagwAAAIAOwDqDAAABwBiAC4ABAp/TwACAQAJCSgl6AQAOQMAAQAJCSgl6AQAOQMAAS4ABRQICTMACQCKIgA=.Jluckshnt:BAEBLgAFFH8GAAIUAAMJJxuEGQDpAANoDAAAAgA+AGkMAAACAFEA6gwAAAIAQAAUAAMJJxuEGQDpAANoDAAAAgA+AGkMAAACAFEA6gwAAAIAQAABLgAFFAgJMwAJAIoiAA==.Jlucksmk:BAEBLgAECn9WAAMGAAcJpyUxCwDmAgdoDAAADwBhAGkMAAAOAGIAawwAAA4AYgBqDAAADgBjAGwMAAAMAGIAbQwAAAIAUwDqDAAADwBjAAYABwmnJTELAOYCB2gMAAANAGEAaQwAAAwAYgBrDAAADABiAGoMAAAKAGMAbAwAAAoAYgBtDAAAAgBTAOoMAAAKAGMAFQAGCasS0zUAJgEGaAwAAAIARgBpDAAAAgAwAGsMAAACACcAagwAAAQALABsDAAAAgAeAOoMAAAFADEAAS4ABRQICTMACQCKIgA=.',
Ki='Kippee:BAECLgAFFH8YAAIKAAYJIxpQMwCcAQZoDAAABgBUAGkMAAAFAEYAawwAAAUASQBqDAAAAgBDAGwMAAABAEgA6gwAAAUAIgAKAAYJIxpQMwCcAQZoDAAABgBUAGkMAAAFAEYAawwAAAUASQBqDAAAAgBDAGwMAAABAEgA6gwAAAUAIgAuAAQKfycAAgoACQlMIs8gAPACAAoACQlMIs8gAPACAAAA.Kipplock:BAEALgAECgYJDwABLgAFFAYJGAAKACMaAA==.',
Kr='Kred:BAEALgADCgYJBgABLgAECgkJWwALAOYiAA==.Kredrothi:BAEBLgAECn9bAAILAAkJ5iJRAACIAgloDAAADABfAGkMAAALAGEAawwAAAwAWABqDAAACwBgAGwMAAALAFMAbQwAAAgATADqDAAADABXAG4MAAAJAF0AbwwAAAUAWwALAAkJ5iJRAACIAgloDAAADABfAGkMAAALAGEAawwAAAwAWABqDAAACwBgAGwMAAALAFMAbQwAAAgATADqDAAADABXAG4MAAAJAF0AbwwAAAUAWwAAAA==.',
Ku='Kunha:BAEALgADCgkJCQABLgAFFAIJAwAHAAAAAA==.',
La='Laghar:BAEALgAECgEJAQAAAA==.',
Ma='Magicracoon:BAEALgAECgQJEAAAAA==.Malzbier:BAEALgAECggJDAABLgAFFAYJEgACAEYfAA==.Marosia:BAEALgAECgcJEwABLgAFFAIJBQAWAHgdAA==.Marroc:BAECLgAFFH8FAAIWAAIJeB3lCADCAAJoDAAAAQA0AOoMAAAEAGIAFgACCXgd5QgAwgACaAwAAAEANADqDAAABABiAC4ABAp/LQACFgAJCSQitAEA4wIAFgAJCSQitAEA4wIAAAA=.',
Ne='Nekun:BAEALgAECgMJBgABLgAECgMJBgAHAAAAAA==.',
Ni='Nitedragon:BAEBLgAECn8XAAMXAAcJUCAbCABvAgdoDAAABABcAGkMAAAEAFUAawwAAAQASABqDAAAAwBSAGwMAAADAFcA6gwAAAQAWABuDAAAAQBEABcABwlQIBsIAG8CB2gMAAADAFwAaQwAAAMAVQBrDAAAAwBIAGoMAAADAFIAbAwAAAMAVwDqDAAABABYAG4MAAABAEQAEwADCcgDTCAAUQADaAwAAAEABQBpDAAAAQAMAGsMAAABAAsAAAA=.',
No='Nottoasty:BAEALgAFFAIJAgABLgAFFAQJBAAHAAAAAA==.',
['Nì']='Nìte:BAEALgAECgcJDgABLgAECgcJFwAXAFAgAA==.',
Or='Oracs:BAEBLgAECn8VAAQJAAcJ6h9WGAAPAgdoDAAAAwBNAGkMAAADAFgAawwAAAMAXABqDAAABABZAGwMAAADAFIA6gwAAAQAWgBuDAAAAQA6AAkABglgH1YYAA8CBmgMAAABAEoAaQwAAAEAUwBrDAAAAQBcAGwMAAADAFIA6gwAAAIAWgBuDAAAAQA6ABMABQkkHRgXAIQBBWgMAAABAE0AaQwAAAEAWABrDAAAAQBNAGoMAAAEAFkA6gwAAAEANgAXAAQJdAQLOQCiAARoDAAAAQAGAGkMAAABABIAawwAAAEAAwDqDAAAAQAQAAEuAAUUBgkSAAIARh8A.',
Pa='Pai:BAEALgAFFAIJAwABLgAFFAIJBgAFAL4hAA==.',
Pi='Pickups:BAECLgAFFH8HAAIBAAMJtBerXwDRAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQABAAMJtBerXwDRAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQAuAAQKfyIAAwQACAmzG0IHABQCAAQABwm/GUIHABQCAAEABwn/FJN8ACcBAAEuAAUUCAkfAAoAYxwA.',
Qa='Qahz:BAECLgAFFH8PAAIQAAUJlxVBRgA8AQVoDAAABABRAGkMAAAEAFoAawwAAAMAHQBqDAAAAQAlAOoMAAADABMAEAAFCZcVQUYAPAEFaAwAAAQAUQBpDAAABABaAGsMAAADAB0AagwAAAEAJQDqDAAAAwATAC4ABAp/LQACEAAJCRsi8w4A1AIAEAAJCRsi8w4A1AIAAS4ABRQFCRMAAQA5JAA=.',
Ru='Ruehnar:BAEALgAECgYJDwABLgAECggJKwAOAJ0ZAA==.',
Si='Sixul:BAEBLgAFFH8JAAIWAAQJ7RGsBQAiAQRoDAAABAA9AGkMAAADAEEAawwAAAEAFADqDAAAAQAkABYABAntEawFACIBBGgMAAAEAD0AaQwAAAMAQQBrDAAAAQAUAOoMAAABACQAAAA=.',
St='Startut:BAEALgAECgIJBAAAAA==.',
Sy='Syth:BAEALgAECggJDwABLgAECgkJLQAYAKIkAA==.',
Ta='Tazukey:BAEBLgAECn8VAAIZAAcJQht5OgC8AQdoDAAABQBgAGkMAAAEAFMAawwAAAQAUgBqDAAAAgBMAGwMAAABADsA6gwAAAQARgBuDAAAAQATABkABwlCG3k6ALwBB2gMAAAFAGAAaQwAAAQAUwBrDAAABABSAGoMAAACAEwAbAwAAAEAOwDqDAAABABGAG4MAAABABMAAS4ABAoJCRoACwDfGAA=.',
Te='Tenisia:BAEALgAECgcJDgAAAA==.Teyr:BAEBLgAECn84AAIaAAkJkSFXAwD9AgloDAAACABgAGkMAAAIAF4AawwAAAgAXABqDAAABwBiAGwMAAAHAFMAbQwAAAUAYADqDAAABwBhAG4MAAAEADQAbwwAAAIASQAaAAkJkSFXAwD9AgloDAAACABgAGkMAAAIAF4AawwAAAgAXABqDAAABwBiAGwMAAAHAFMAbQwAAAUAYADqDAAABwBhAG4MAAAEADQAbwwAAAIASQAAAA==.',
Th='Theò:BAEALgAECgQJBAAAAA==.',
Ti='Titanbp:BAEALgADCgYJCQABLgAFFAgJKQAIAJ8eAA==.Titandb:BAECLgAFFH8pAAIIAAgJnx78AwBqAghoDAAACQBgAGkMAAAIAGIAawwAAAcAYQBqDAAABQBVAGwMAAABAE4AbQwAAAEAHgDqDAAACQBeAG4MAAABADQACAAICZ8e/AMAagIIaAwAAAkAYABpDAAACABiAGsMAAAHAGEAagwAAAUAVQBsDAAAAQBOAG0MAAABAB4A6gwAAAkAXgBuDAAAAQA0AC4ABAp/LQACCAAJCSwjEwUA2wIACAAJCSwjEwUA2wIAAAA=.Titanpp:BAEALgADCgQJCAABLgAFFAgJKQAIAJ8eAA==.',
Va='Valynithira:BAECLgAFFH8fAAIKAAgJYxxxEwBTAghoDAAABQBiAGkMAAAFAGAAawwAAAYATQBqDAAABABcAGwMAAADAE4AbQwAAAEAGgDqDAAABgBdAG4MAAABACUACgAICWMccRMAUwIIaAwAAAUAYgBpDAAABQBgAGsMAAAGAE0AagwAAAQAXABsDAAAAwBOAG0MAAABABoA6gwAAAYAXQBuDAAAAQAlAC4ABAp/LgACCgAICeYlpQ8ASwMACgAICeYlpQ8ASwMAAAA=.',
Ve='Velanyr:BAEBLgAECn8dAAIQAAkJoh1+MwALAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAQAAkJoh1+MwALAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAAAA==.',
Vi='Viridessia:BAEBLgAECn81AAQJAAkJqRnJIADTAQloDAAACQBEAGkMAAAIADgAawwAAAgARQBqDAAABgA+AGwMAAAGAEQAbQwAAAIAGwDqDAAACQBYAG4MAAAEAEQAbwwAAAEATgAJAAgJrxbJIADTAQhoDAAAAwAtAGkMAAADACcAawwAAAMARQBqDAAAAQAEAGwMAAACABAA6gwAAAUAWABuDAAABABEAG8MAAABAE4AEwAHCTUWXgoAeQEHaAwAAAYARABpDAAABQA4AGsMAAAFAEIAagwAAAQAPgBsDAAABABEAG0MAAACABsA6gwAAAQANQAXAAEJ1QchPwAoAAFqDAAAAQAUAAAA.',
Vl='Vladja:BAEBLgAECn8rAAMOAAgJnRloTQDfAQhoDAAABwBIAGkMAAAHADMAawwAAAcARwBqDAAABgBSAGwMAAAGAFAAbQwAAAEAHQDqDAAACABTAG4MAAABAEYADgAHCfUbaE0A3wEHaAwAAAcASABpDAAABwAzAGsMAAAHAEcAagwAAAYAUgBsDAAABgBQAOoMAAAIAFMAbgwAAAEARgAbAAEJigvjUAAvAAFtDAAAAQAdAAAA.',
Wr='Wrexilion:BAEALgAECgUJBQAAAA==.',
Yi='Yiangchen:BAEBLgAECn8hAAIVAAkJRR3nCQCUAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAAVAAkJRR3nCQCUAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAABLgAECgkJNQAJAKkZAA==.',
Zi='Zirkondrake:BAEBLgAECn9BAAMcAAgJGSTPBwDiAghoDAAACgBbAGkMAAALAGIAawwAAAkAVwBqDAAACQBiAGwMAAAHAGEAbQwAAAMAUQDqDAAACgBdAG4MAAAGAGEAHAAICRkkzwcA4gIIaAwAAAkAWwBpDAAACQBiAGsMAAAIAFcAagwAAAcAYgBsDAAABgBhAG0MAAACAFEA6gwAAAgAXQBuDAAABQBhAB0ACAmmG+IMABwCCGgMAAABAEUAaQwAAAIAVgBrDAAAAQBNAGoMAAACAFoAbAwAAAEAOwBtDAAAAQAlAOoMAAACAFoAbgwAAAEATAAAAA==.',
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
