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

local lookup = {'DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','Unknown-Unknown','Evoker-Devastation','Mage-Frost','Priest-Holy','Paladin-Retribution','Druid-Feral','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Monk-Brewmaster','Hunter-BeastMastery','Rogue-Assassination','Evoker-Preservation','DemonHunter-Vengeance','Druid-Restoration','DeathKnight-Blood','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='WyrmrestAccord',name='US',type='subscribers',zone=46,date='2026-05-25',data={Ag='Aggrodari:BAECLgAFFH8OAAIBAAQJwiP0FgCiAQRoDAAABQBjAGkMAAAEAGMAawwAAAIASQDqDAAAAwBdAAEABAnCI/QWAKIBBGgMAAAFAGMAaQwAAAQAYwBrDAAAAgBJAOoMAAADAF0ALgAECn8+AAIBAAgJjibrBgALAwABAAgJjibrBgALAwAAAA==.Aggrorunner:BAEALgADCgMJBQABLgAFFAQJDgABAMIjAA==.',
An='Anuhkin:BAEALgADCgUJBQABLgAFFAUJDwACALwhAA==.',
Ar='Archoknot:BAEALgAECgQJCwAAAA==.Arcis:BAEALgAFFAMJBAAAAA==.',
Bj='Bjørnulf:BAEALgAECgYJCwAAAA==.',
Bo='Bowbafletch:BAEALgAFFAEJAQABLgAFFAUJDwACALwhAA==.',
Br='Breadroll:BAECLgAFFH8GAAIDAAIJviEqHwC2AAJoDAAAAgBWAOoMAAAEAFYAAwACCb4hKh8AtgACaAwAAAIAVgDqDAAABABWAC4ABAp/HgADAwAJCdwh7wIAaAMAAwAJCdwh7wIAaAMABAAECWUdajcATAEAAAA=.Brendemøn:BAEALgAECgYJCwAAAA==.Brêndêath:BAEALgAECgYJCgABLgAECgYJCwAFAAAAAA==.',
Ca='Caedues:BAECLgAFFH8PAAICAAUJvCHGOgBTAQVoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAOoMAAADAEgAAgAFCbwhxjoAUwEFaAwAAAQAXwBpDAAABABbAGsMAAADAFUAagwAAAEARgDqDAAAAwBIAC4ABAp/IQACAgAJCdAhfBMABgMAAgAJCdAhfBMABgMAAAA=.',
Ch='Chaosity:BAEALgAECgcJEgABLgAECgkJNAAGAEEYAA==.Cheeseburber:BAEALgADCgMJAwABLgAECgQJEAAFAAAAAA==.',
Dr='Drommekage:BAEBLgAECn8bAAIHAAcJuQa+tgAAAQdoDAAABQANAGkMAAAFABQAawwAAAUAIwBqDAAABAATAGwMAAADAA8AbQwAAAEABgDqDAAABAAMAAcABwm5Br62AAABB2gMAAAFAA0AaQwAAAUAFABrDAAABQAjAGoMAAAEABMAbAwAAAMADwBtDAAAAQAGAOoMAAAEAAwAAAA=.',
El='Eliraina:BAEALgAECgkJEwAAAA==.',
En='Enneth:BAEALgADCgQJBAAAAA==.',
Ev='Eviecera:BAEALgADCgUJBQABLgAFFAMJBQAIAEofAA==.',
Ex='Exesa:BAEALgAECggJEAAAAA==.',
Fe='Fedja:BAEALgAECggJCAABLgAECgYJJAAJAD8bAA==.',
He='Henpaw:BAEALgAFFAEJAwABLgADCgEJAQAFAAAAAA==.Henscale:BAEALgAECgEJAQABLgADCgEJAQAFAAAAAQ==.Henseng:BAEALgADCgEJAQAAAA==.Hensurge:BAEALgAFFAEJAgABLgADCgEJAQAFAAAAAA==.',
Hi='Hirenar:BAEALgAECgEJAgABLgAFFAUJDwACALwhAA==.',
['Hâ']='Hâstery:BAEALgAECggJBwABLgAFFAUJCgAKADkcAA==.',
Il='Illothe:BAECLgAFFH8iAAQLAAcJVhZ9FwCmAQdoDAAABgBZAGkMAAAFAFkAawwAAAYAQgBqDAAABQBCAGwMAAADACoAbQwAAAIAAwDqDAAABwAzAAsABgmOGn0XAKYBBmgMAAAGAFkAaQwAAAMAWQBrDAAABgBCAGoMAAAFAEIAbAwAAAMAKgDqDAAABwAzAAwAAQmgCSEcAEkAAWkMAAABABgADQACCcsAbB8ASAACaQwAAAEAAABtDAAAAgADAC4ABAp/KAADCwAJCV8hBRIA6wIACwAICfoiBRIA6wIADQADCRMV0jcA1gAAAAA=.Illothedh:BAEALgADCgMJAwABLgAFFAcJIgALAFYWAA==.',
In='Insouciantly:BAEALgAECgIJAgABLgAECgcJGAAIAIgjAA==.',
Ir='Irreverently:BAEBLgAECn8YAAIIAAcJiCMrEgBPAgdoDAAABABNAGkMAAAEAFkAawwAAAQAWgBqDAAAAgBhAGwMAAADAFoAbQwAAAEAYADqDAAABgBgAAgABwmIIysSAE8CB2gMAAAEAE0AaQwAAAQAWQBrDAAABABaAGoMAAACAGEAbAwAAAMAWgBtDAAAAQBgAOoMAAAGAGAAAAA=.',
Jl='Jlucks:BAECLgAFFH8iAAIOAAYJZCSQCAATAgZoDAAABwBiAGkMAAAGAFgAawwAAAYAWwBqDAAABgBaAGwMAAACAFsA6gwAAAcAYAAOAAYJZCSQCAATAgZoDAAABwBiAGkMAAAGAFgAawwAAAYAWwBqDAAABgBaAGwMAAACAFsA6gwAAAcAYAAuAAQKf00AAg4ACQmCJpMAAIsDAA4ACQmCJpMAAIsDAAAA.Jlucksdh:BAECLgAFFH8eAAIBAAUJqiSOFgCkAQVoDAAACgBgAGkMAAAIAF8AawwAAAQAVQBqDAAAAgA7AOoMAAAGAGIAAQAFCaokjhYApAEFaAwAAAoAYABpDAAACABfAGsMAAAEAFUAagwAAAIAOwDqDAAABgBiAC4ABAp/TwACAQAJCSglaAMAQwMAAQAJCSglaAMAQwMAAS4ABRQGCSIADgBkJAA=.Jlucksmk:BAEBLgAECn9KAAMEAAcJpyVmCADqAgdoDAAADQBhAGkMAAAMAGIAawwAAAwAYgBqDAAADABjAGwMAAAKAGIAbQwAAAIAUwDqDAAADQBjAAQABwmnJWYIAOoCB2gMAAANAGEAaQwAAAwAYgBrDAAADABiAGoMAAAKAGMAbAwAAAoAYgBtDAAAAgBTAOoMAAAKAGMADwACCYAHPJMAIAACagwAAAIAGgDqDAAAAwATAAEuAAUUBgkiAA4AZCQA.',
Kr='Kred:BAEALgADCgYJBgABLgAECgkJPAAQAN0hAA==.Kredrothi:BAEBLgAECn88AAIQAAkJ3SHiDADKAgloDAAACABfAGkMAAAIAGEAawwAAAgAWABqDAAACABgAGwMAAAHAEwAbQwAAAYATADqDAAACABXAG4MAAAFAF0AbwwAAAIATgAQAAkJ3SHiDADKAgloDAAACABfAGkMAAAIAGEAawwAAAgAWABqDAAACABgAGwMAAAHAEwAbQwAAAYATADqDAAACABXAG4MAAAFAF0AbwwAAAIATgAAAA==.',
Ku='Kunha:BAEALgADCgkJCQABLgAFFAIJAwAFAAAAAA==.',
La='Laghar:BAEALgAECgEJAQAAAA==.',
Ma='Magicracoon:BAEALgAECgQJEAAAAA==.Malzbier:BAEALgAECggJDAABLgAFFAUJDwACALwhAA==.Marosia:BAEALgAECgYJCQABLgAECggJIQARAJQhAA==.Marroc:BAEBLgAECn8hAAIRAAgJlCGNAgCMAghoDAAABgBhAGkMAAAFAF4AawwAAAUAWQBqDAAABQBLAGwMAAADAEUAbQwAAAIAXgDqDAAABQBjAG4MAAACADoAEQAICZQhjQIAjAIIaAwAAAYAYQBpDAAABQBeAGsMAAAFAFkAagwAAAUASwBsDAAAAwBFAG0MAAACAF4A6gwAAAUAYwBuDAAAAgA6AAAA.',
Ne='Nekun:BAEALgAECgMJBgABLgAECgMJBgAFAAAAAA==.',
Ni='Nitedragon:BAEALgAECgcJEwAAAA==.',
No='Noellia:BAEALgAECgcJDgABLgAECgkJEwAFAAAAAA==.',
['Nì']='Nìte:BAEALgAECgcJBwABLgAECgcJEwAFAAAAAA==.',
Or='Oracs:BAEBLgAECn8VAAQOAAcJ6h9WGAAPAgdoDAAAAwBNAGkMAAADAFgAawwAAAMAXABqDAAABABZAGwMAAADAFIA6gwAAAQAWgBuDAAAAQA6AA4ABglgH1YYAA8CBmgMAAABAEoAaQwAAAEAUwBrDAAAAQBcAGwMAAADAFIA6gwAAAIAWgBuDAAAAQA6AAYABQkkHRgXAIQBBWgMAAABAE0AaQwAAAEAWABrDAAAAQBNAGoMAAAEAFkA6gwAAAEANgASAAQJdAQLOQCiAARoDAAAAQAGAGkMAAABABIAawwAAAEAAwDqDAAAAQAQAAEuAAUUBQkPAAIAvCEA.',
Pa='Pai:BAEALgAFFAIJAwABLgAFFAIJBgADAL4hAA==.',
Pi='Pickups:BAECLgAFFH8HAAIBAAMJtBeiSADlAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQABAAMJtBeiSADlAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQAuAAQKfyIAAxMACAmzG0IHABQCABMABwm/GUIHABQCAAEABwn/FIlsACoBAAEuAAUUBwkeAAcArB4A.',
Qa='Qahz:BAECLgAFFH8LAAILAAQJLROlNgA8AQRoDAAAAwA4AGkMAAADAFoAawwAAAIAHQDqDAAAAwATAAsABAktE6U2ADwBBGgMAAADADgAaQwAAAMAWgBrDAAAAgAdAOoMAAADABMALgAECn8oAAILAAcJ4CFXJgB5AgALAAcJ4CFXJgB5AgABLgAFFAQJDgABAMIjAA==.',
Ru='Ruehnar:BAEALgAECgYJDwABLgAECgYJJAAJAD8bAA==.',
Ry='Ryenth:BAEALgAECgEJAQABLgAECgkJNAAGAEEYAA==.',
Si='Simantha:BAEALgAECgYJDwABLgAECgkJEwAFAAAAAA==.Sixul:BAEBLgAFFH8JAAIRAAQJ7RESBABBAQRoDAAABAA9AGkMAAADAEEAawwAAAEAFADqDAAAAQAkABEABAntERIEAEEBBGgMAAAEAD0AaQwAAAMAQQBrDAAAAQAUAOoMAAABACQAAAA=.',
St='Startut:BAEALgAECgIJBAAAAA==.Stiffbow:BAEALgADCgQJBAABLgAECggJKAAQAK4UAA==.',
Ta='Taylorquick:BAEALgAECgcJDAAAAA==.Tazukey:BAEBLgAECn8VAAIUAAcJQht5OgC8AQdoDAAABQBgAGkMAAAEAFMAawwAAAQAUgBqDAAAAgBMAGwMAAABADsA6gwAAAQARgBuDAAAAQATABQABwlCG3k6ALwBB2gMAAAFAGAAaQwAAAQAUwBrDAAABABSAGoMAAACAEwAbAwAAAEAOwDqDAAABABGAG4MAAABABMAAAA=.',
Te='Tenisia:BAEALgAECgcJDgAAAA==.',
Th='Theò:BAEALgADCgMJAQAAAA==.',
Ti='Titanbp:BAEALgADCgYJCQABLgAFFAgJJQAVAJ8eAA==.Titandb:BAECLgAFFH8lAAIVAAgJnx46AQCUAghoDAAACABgAGkMAAAHAGIAawwAAAYAYQBqDAAABQBVAGwMAAABAE4AbQwAAAEAHgDqDAAACABeAG4MAAABADQAFQAICZ8eOgEAlAIIaAwAAAgAYABpDAAABwBiAGsMAAAGAGEAagwAAAUAVQBsDAAAAQBOAG0MAAABAB4A6gwAAAgAXgBuDAAAAQA0AC4ABAp/LQACFQAJCSwjhAMA7QIAFQAJCSwjhAMA7QIAAAA=.Titanpp:BAEALgADCgQJCAABLgAFFAgJJQAVAJ8eAA==.',
Va='Valynithira:BAECLgAFFH8eAAIHAAcJrB6fDAArAgdoDAAABQBiAGkMAAAFAGAAawwAAAYATQBqDAAABABcAGwMAAADAE4AbQwAAAEAGgDqDAAABgBdAAcABwmsHp8MACsCB2gMAAAFAGIAaQwAAAUAYABrDAAABgBNAGoMAAAEAFwAbAwAAAMATgBtDAAAAQAaAOoMAAAGAF0ALgAECn8uAAIHAAgJ5iWlDwBLAwAHAAgJ5iWlDwBLAwAAAA==.',
Ve='Velanyr:BAEBLgAECn8dAAILAAkJoh23KQAfAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgALAAkJoh23KQAfAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAAAA==.',
Vi='Viridessia:BAEBLgAECn80AAQGAAkJQRj1CACAAQloDAAACQBEAGkMAAAIADgAawwAAAgARQBqDAAABgA+AGwMAAAGAEQAbQwAAAIAGwDqDAAACAA7AG4MAAAEAEQAbwwAAAEATgAOAAgJFRUNIAC6AQhoDAAAAwAtAGkMAAADACcAawwAAAMARQBqDAAAAQAEAGwMAAACABAA6gwAAAQAOwBuDAAABABEAG8MAAABAE4ABgAHCTUW9QgAgAEHaAwAAAYARABpDAAABQA4AGsMAAAFAEIAagwAAAQAPgBsDAAABABEAG0MAAACABsA6gwAAAQANQASAAEJ1QfcNwApAAFqDAAAAQAUAAAA.',
Vl='Vladja:BAEBLgAECn8kAAIJAAYJPxtuZgCIAQZoDAAABgBIAGkMAAAGADMAawwAAAYARwBqDAAABQBQAGwMAAAFAEUA6gwAAAgAUwAJAAYJPxtuZgCIAQZoDAAABgBIAGkMAAAGADMAawwAAAYARwBqDAAABQBQAGwMAAAFAEUA6gwAAAgAUwAAAA==.',
Yi='Yiangchen:BAEBLgAECn8hAAIPAAkJRR3IBwCeAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAAPAAkJRR3IBwCeAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAABLgAECgkJNAAGAEEYAA==.',
Zi='Zirkondrake:BAEBLgAECn84AAMWAAgJUx9LDwBiAghoDAAACQBTAGkMAAAKAFwAawwAAAgAUABqDAAACABiAGwMAAAGAFoAbQwAAAIAJwDqDAAACQBdAG4MAAAEAFIAFgAICVMfSw8AYgIIaAwAAAgAUwBpDAAACABcAGsMAAAHAFAAagwAAAYAYgBsDAAABQBaAG0MAAABACcA6gwAAAcAXQBuDAAAAwBSABcACAmmGwUKADICCGgMAAABAEUAaQwAAAIAVgBrDAAAAQBNAGoMAAACAFoAbAwAAAEAOwBtDAAAAQAlAOoMAAACAFoAbgwAAAEATAAAAA==.',
Zy='Zylphian:BAEBLgAECn8oAAIQAAgJrhQwLgD5AQhoDAAABwBHAGkMAAAFADUAawwAAAQAKQBqDAAABQA8AGwMAAAFAC4AbQwAAAQAIQDqDAAABwBUAG4MAAADACYAEAAICa4UMC4A+QEIaAwAAAcARwBpDAAABQA1AGsMAAAEACkAagwAAAUAPABsDAAABQAuAG0MAAAEACEA6gwAAAcAVABuDAAAAwAmAAAA.',
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
