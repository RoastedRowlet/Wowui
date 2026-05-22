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

local lookup = {'Paladin-Holy','Evoker-Preservation','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Priest-Discipline','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Mage-Frost','Rogue-Assassination','Warrior-Fury','Paladin-Retribution','Rogue-Outlaw','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','Warlock-Affliction','DeathKnight-Unholy','Priest-Holy','Hunter-BeastMastery','Druid-Feral','Hunter-Marksmanship','Mage-Fire','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=46,date='2026-05-21',data={Ad='Addex:BAEBLgAFFH8NAAIBAAYJjxM5BQCKAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABAAYJjxM5BQCKAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABLgAFFAkJMQACAFwgAA==.',
Ae='Aeveracy:BAEALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Am='Ambient:BAECLgAFFH8xAAMCAAkJXCAOAABxAwloDAAACABhAGkMAAAIAFwAawwAAAcAUABqDAAABwBjAGwMAAAGAFYAbQwAAAIAVQDqDAAACABLAG4MAAACAEkAbwwAAAEAOAACAAkJXCAOAABxAwloDAAABgBhAGkMAAAIAFwAawwAAAcAUABqDAAABwBjAGwMAAAGAFYAbQwAAAIAVQDqDAAACABLAG4MAAACAEkAbwwAAAEAOAAEAAEJPxd+IABQAAFoDAAAAgA7AC4ABAp/HQADAgAJCXMjvgQAAwMAAgAICSsjvgQAAwMABQABCYgT1joARAAAAAA=.',
Br='Briéè:BAEBLgAECn8UAAMGAAYJRxPRGgCoAAZoDAAABQBLAGkMAAAEADMAawwAAAQALwBqDAAAAwAuAGwMAAACADAA6gwAAAIAFgAHAAUJNw8poADiAAVoDAAAAwAvAGkMAAADACQAagwAAAEAKgBsDAAAAgAwAOoMAAACABYABgAECc4W0RoAqAAEaAwAAAIASwBpDAAAAQAzAGsMAAAEAC8AagwAAAIALgAAAA==.Bruwon:BAECLgAFFH8wAAIIAAgJtiGfAABJAghoDAAACABcAGkMAAAIAGMAawwAAAgAWgBqDAAABwBIAGwMAAAGAGIAbQwAAAEATwDqDAAACQBeAG4MAAABADIACAAICbYhnwAASQIIaAwAAAgAXABpDAAACABjAGsMAAAIAFoAagwAAAcASABsDAAABgBiAG0MAAABAE8A6gwAAAkAXgBuDAAAAQAyAC4ABAp/IQACCAAJCUAhxwQAPgMACAAJCUAhxwQAPgMAAAA=.',
Ch='Charzie:BAEALgAECgUJBgABLgAFFAgJMAAIALYhAA==.',
Ci='Ciprox:BAEBLgAECn8VAAIJAAgJqB41EQA4AghoDAAAAwBVAGkMAAADAEcAawwAAAMAXABqDAAAAwBQAGwMAAADAGAAbQwAAAIAOADqDAAAAwBcAG4MAAABADcACQAICageNREAOAIIaAwAAAMAVQBpDAAAAwBHAGsMAAADAFwAagwAAAMAUABsDAAAAwBgAG0MAAACADgA6gwAAAMAXABuDAAAAQA3AAEuAAUUBwkaAAoAJhoA.',
Cy='Cyprexdh:BAECLgAFFH8aAAMKAAcJJho1CQAIAgdoDAAABwBjAGkMAAAFAFoAawwAAAQASwBqDAAABABbAGwMAAABAB0AbQwAAAEADwDqDAAABABaAAoABwlVFzUJAAgCB2gMAAAEAEAAaQwAAAQAWgBrDAAAAwBLAGoMAAAEAFsAbAwAAAEAHQBtDAAAAQAPAOoMAAADAFIACwAECX8Z7wEAewEEaAwAAAMAYwBpDAAAAQAFAGsMAAABAEEA6gwAAAEAWgAuAAQKfxoABAsACAnwJTkDAFIDAAsACAlbJTkDAFIDAAoAAwmyJJl7ADUBAAwAAQkAALYtACkAAAAA.',
Da='Danilynn:BAEALgADCggJFAABLgAECgcJIwANAKEDAA==.Danitsia:BAEBLgAECn8jAAMNAAcJoQMmQwDPAAdoDAAABgAIAGkMAAAGAAwAawwAAAYACQBqDAAABQAUAGwMAAAFAAsAbQwAAAEABADqDAAABgAIAA0ABwmhAyZDAM8AB2gMAAAGAAgAaQwAAAYADABrDAAABQAJAGoMAAAFABQAbAwAAAQACwBtDAAAAQAEAOoMAAAFAAgADgADCeMAdVEARgADawwAAAEAAgBsDAAAAQADAOoMAAABAAAAAAA=.',
De='Delabrand:BAEALgAECgYJCQABLgAFFAgJHwAPAIkmAA==.Delajuv:BAEBLgAFFH8JAAIQAAUJrx5fBABqAQVoDAAAAgBTAGkMAAACAEwAawwAAAIATQBqDAAAAQAJAOoMAAACAEwAEAAFCa8eXwQAagEFaAwAAAIAUwBpDAAAAgBMAGsMAAACAE0AagwAAAEACQDqDAAAAgBMAAEuAAUUCAkfAA8AiSYA.Delarage:BAECLgAFFH8fAAIPAAgJiSYxAAALAwhoDAAABgBjAGkMAAAEAGMAawwAAAQAYwBqDAAABQBiAGwMAAADAGQAbQwAAAIAYQDqDAAABgBjAG4MAAABAF4ADwAICYkmMQAACwMIaAwAAAYAYwBpDAAABABjAGsMAAAEAGMAagwAAAUAYgBsDAAAAwBkAG0MAAACAGEA6gwAAAYAYwBuDAAAAQBeAC4ABAp/IQACDwAJCf4m/QAAkAMADwAJCf4m/QAAkAMAAAA=.Deleerious:BAECLgAFFH8TAAIRAAUJzCUtDQBjAQVoDAAABQBiAGkMAAAFAGEAawwAAAIAXgBqDAAAAQBdAOoMAAAGAGAAEQAFCcwlLQ0AYwEFaAwAAAUAYgBpDAAABQBhAGsMAAACAF4AagwAAAEAXQDqDAAABgBgAC4ABAp/KgACEQAICR0kogUAOAMAEQAICR0kogUAOAMAAAA=.',
Do='Doriel:BAEALgAECgMJBAABLgAFFAUJEQASAOUUAA==.',
Du='Dubsstree:BAEALgADCgYJBgABLgAFFAcJHQAHANQZAA==.',
Dw='Dwarfwarloc:BAEBLgAECn8aAAIHAAgJKCIVEwCYAghoDAAABABgAGkMAAAEAFMAawwAAAQAWgBqDAAABABgAGwMAAADAGEAbQwAAAEARADqDAAABQBfAG8MAAABAE4ABwAICSgiFRMAmAIIaAwAAAQAYABpDAAABABTAGsMAAAEAFoAagwAAAQAYABsDAAAAwBhAG0MAAABAEQA6gwAAAUAXwBvDAAAAQBOAAAA.',
Eg='Egirlarmpits:BAEALgAFFAMJAwABLgAFFAQJDAAJACgUAA==.',
Em='Emellious:BAECLgAFFH8XAAIRAAYJyxa9CQCGAQZoDAAABgBPAGkMAAAFAFsAawwAAAMAGgBqDAAAAgA6AG0MAAABAAcA6gwAAAYAVwARAAYJyxa9CQCGAQZoDAAABgBPAGkMAAAFAFsAawwAAAMAGgBqDAAAAgA6AG0MAAABAAcA6gwAAAYAVwAuAAQKfxwAAxEACAkEIaEMAM4CABEACAkEIaEMAM4CABMAAQmQC4IfADUAAAAA.',
Fr='Freddyfletch:BAEALgADCgUJBQAAAA==.',
Fu='Funkaroused:BAEBLgAECn8vAAIUAAgJmRqiHQDVAQhoDAAABwBbAGkMAAAHAEcAawwAAAcAQABqDAAABgBFAGwMAAAHAEsAbQwAAAEAMADqDAAACABKAG4MAAAEADIAFAAICZkaoh0A1QEIaAwAAAcAWwBpDAAABwBHAGsMAAAHAEAAagwAAAYARQBsDAAABwBLAG0MAAABADAA6gwAAAgASgBuDAAABAAyAAAA.',
Gi='Giantmagic:BAEBLgAECn8bAAISAAcJQh19XQAiAgdoDAAABABOAGkMAAAEAFIAawwAAAQAWwBqDAAABgBOAGwMAAACAD4AbQwAAAIAQgDqDAAABQBEABIABwlCHX1dACICB2gMAAAEAE4AaQwAAAQAUgBrDAAABABbAGoMAAAGAE4AbAwAAAIAPgBtDAAAAgBCAOoMAAAFAEQAAS4ABAoHCRkAFQDCIAA=.',
Gj='Gjlo:BAECLgAFFH8KAAMUAAMJzBNSJQDfAANoDAAABQBGAGkMAAACACUA6gwAAAMALAAUAAMJzBNSJQDfAANoDAAAAwBGAGkMAAABACUA6gwAAAMALAAPAAIJpAMoDgBlAAJoDAAAAgARAGkMAAABAAAALgAECn9SAAMUAAkJox6iBAD6AgAUAAkJox6iBAD6AgAPAAcJdw+jJQDYAAAAAA==.',
Gr='Gronknose:BAEBLgAECn8WAAIWAAcJ0iHgAQCcAgdoDAAAAwBVAGkMAAAEAFwAawwAAAQATABqDAAAAwBeAGwMAAACAFcAbQwAAAEAUgDqDAAABQBfABYABwnSIeABAJwCB2gMAAADAFUAaQwAAAQAXABrDAAABABMAGoMAAADAF4AbAwAAAIAVwBtDAAAAQBSAOoMAAAFAF8AAS4ABAoJCTEACACxJAA=.',
Ha='Hakdh:BAEALgAECgYJBgABLgAFFAYJFwAXACAOAA==.Hakdk:BAECLgAFFH8XAAIXAAYJIA7+BQA7AQZoDAAABAAlAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAYAQAAXAAYJIA7+BQA7AQZoDAAABAAlAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAYAQAAuAAQKfxQAAhcACAkkHtMKAGoCABcACAkkHtMKAGoCAAAA.Hakgek:BAEBLgAFFH8KAAIQAAUJFAzNBABcAQVoDAAAAgAlAGkMAAACACgAawwAAAIAJgBsDAAAAwAdAG4MAAABAAgAEAAFCRQMzQQAXAEFaAwAAAIAJQBpDAAAAgAoAGsMAAACACYAbAwAAAMAHQBuDAAAAQAIAAEuAAUUBgkXABcAIA4A.Hakmonk:BAEBLgAFFH8GAAIIAAQJSxHODQAWAQRoDAAAAgAmAGkMAAACAEsAawwAAAEAEQDqDAAAAQAuAAgABAlLEc4NABYBBGgMAAACACYAaQwAAAIASwBrDAAAAQARAOoMAAABAC4AAS4ABRQGCRcAFwAgDgA=.Haksham:BAEALgAECgkJDQABLgAFFAYJFwAXACAOAA==.Hakwar:BAEALgAECgUJBQABLgAFFAYJFwAXACAOAA==.Halosbrew:BAECLgAFFH8JAAIIAAQJqhnoDwADAQRoDAAAAgBLAGkMAAADAFYAawwAAAEAGgDqDAAAAwBKAAgABAmqGegPAAMBBGgMAAACAEsAaQwAAAMAVgBrDAAAAQAaAOoMAAADAEoALgAECn8UAAMIAAgJRx4TFQBjAgAIAAcJzSETFQBjAgAYAAUJaRO9PAAoAQAAAA==.Halosdk:BAEBLgAFFH8NAAIXAAUJFBjyEQAQAQVoDAAAAwBEAGkMAAACAEsAawwAAAIAGwBqDAAAAQA/AOoMAAAFAEoAFwAFCRQY8hEAEAEFaAwAAAMARABpDAAAAgBLAGsMAAACABsAagwAAAEAPwDqDAAABQBKAAEuAAUUBQkJAAgAqhkA.Halosmage:BAEALgAECggJDgABLgAFFAUJCQAIAKoZAA==.',
He='Heavensfeel:BAECLgAFFH8GAAICAAIJwR4iGgC1AAJoDAAAAwBSAOoMAAADAEsAAgACCcEeIhoAtQACaAwAAAMAUgDqDAAAAwBLAC4ABAp/NAAEAgAJCRQfDAgAuwIAAgAJCRQfDAgAuwIABAAJCcgbLAoAkQIABQACCY4LURgAZwAAAS4ABRQFCQkACACqGQA=.',
In='Inaríus:BAEBLgAECn8ZAAIVAAcJwiCvJwA+AgdoDAAABQBUAGkMAAAEAFoAawwAAAQAVgBqDAAABABRAGwMAAAEAGEA6gwAAAMASwBuDAAAAQBEABUABwnCIK8nAD4CB2gMAAAFAFQAaQwAAAQAWgBrDAAABABWAGoMAAAEAFEAbAwAAAQAYQDqDAAAAwBLAG4MAAABAEQAAAA=.Initiative:BAEBLgAECn8bAAMZAAkJMB13DACUAgloDAAAAwBXAGkMAAADAFwAawwAAAQAXwBqDAAAAwA8AGwMAAAFAEYAbQwAAAIASQDqDAAABABRAG4MAAACAD0AbwwAAAEAMQAZAAgJcB53DACUAghoDAAAAgBXAGkMAAACAFwAawwAAAMAXwBqDAAAAgA8AGwMAAACAEYAbQwAAAIASQDqDAAAAgBRAG4MAAABAD0AGAAICa8eWxoADQIIaAwAAAEAWQBpDAAAAQBdAGsMAAABAF4AagwAAAEAVQBsDAAAAwBgAOoMAAACAFAAbgwAAAEAIABvDAAAAQA/AAAA.',
It='Itsgrippy:BAEALgAECgYJDgAAAA==.',
Je='Jev:BAEBLgAECn8hAAINAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAANAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAAAAA==.',
Ke='Keeflan:BAECLgAFFH8MAAIJAAQJKBRlFwAkAQRoDAAAAwA8AGkMAAADABoAawwAAAIAMgDqDAAABABFAAkABAkoFGUXACQBBGgMAAADADwAaQwAAAMAGgBrDAAAAgAyAOoMAAAEAEUALgAECn8bAAMJAAgJIiC5KwC6AQAJAAcJUCC5KwC6AQAaAAcJRg2tQAB+AQAAAA==.',
Ku='Kungfupander:BAEALgADCgMJAwABLgAECgcJGQAVAMIgAA==.',
Le='Lewinskibidi:BAEBLgAFFH8HAAIEAAUJ3BRVEQB8AQVoDAAAAgBMAGkMAAACAEUAawwAAAEAOgDqDAAAAQAyAG4MAAABAAsABAAFCdwUVREAfAEFaAwAAAIATABpDAAAAgBFAGsMAAABADoA6gwAAAEAMgBuDAAAAQALAAEuAAUUBwkjAA0ADx8A.',
Ma='Madtheaug:BAECLgAFFH8HAAIEAAQJwBS7GgAzAQRoDAAAAgA1AGkMAAACAFUAawwAAAIANgDqDAAAAQATAAQABAnAFLsaADMBBGgMAAACADUAaQwAAAIAVQBrDAAAAgA2AOoMAAABABMALgAECn8WAAMFAAgJkyAzEgC+AQAFAAcJsxgzEgC+AQAEAAUJgSFyIAC9AQABLgAFFAkJLQAHACQmAA==.Madthehunt:BAEALgAFFAEJAQABLgAFFAkJLQAHACQmAA==.Madthelock:BAECLgAFFH8tAAQHAAkJJCanAADjAgloDAAABQBjAGkMAAAHAGMAawwAAAcAZABqDAAABwBYAGwMAAAFAGQAbQwAAAIAYgDqDAAACABhAG4MAAACAFoAbwwAAAIAXgAHAAkJFyKnAADjAgloDAAAAwBfAGkMAAADAGMAawwAAAEAYgBqDAAAAgBHAGwMAAACAFQAbQwAAAEAJADqDAAABABhAG4MAAACAFoAbwwAAAIAXgAGAAcJiSY4AACWAgdoDAAAAQBjAGkMAAADAGMAawwAAAUAZABqDAAAAwBYAGwMAAACAGEAbQwAAAEAYgDqDAAAAwBhABsABgkTJi4AACMCBmgMAAABAGEAaQwAAAEAYwBrDAAAAQBeAGoMAAACAFYAbAwAAAEAZADqDAAAAQBgAC4ABAp/KgAEBwAJCbEmagIAXwMABwAJCU0magIAXwMAGwAICWYmlwAADgMABgAGCRwmXQoAGQIAAAA=.Magolli:BAEALgAECgQJBAABLgAFFAUJEQASAOUUAA==.Magølli:BAECLgAFFH8RAAISAAUJ5RStPwBGAQVoDAAABQA5AGkMAAAFAEMAawwAAAMAGgBqDAAAAQBLAOoMAAADAD0AEgAFCeUUrT8ARgEFaAwAAAUAOQBpDAAABQBDAGsMAAADABoAagwAAAEASwDqDAAAAwA9AC4ABAp/LgACEgAICeAgTSYA2QIAEgAICeAgTSYA2QIAAAA=.',
Me='Megachud:BAEALgAFFAEJAQABLgAFFAQJDAAJACgUAA==.',
Mi='Minbä:BAEALgAECgYJEgABLgAFFAcJHQAHANQZAA==.Minigun:BAEALgAECgcJCgAAAQ==.Minipala:BAECLgAFFH8LAAIBAAQJtBsoGQAkAQRoDAAABABPAGkMAAACADMAawwAAAIASwDqDAAAAwBNAAEABAm0GygZACQBBGgMAAAEAE8AaQwAAAIAMwBrDAAAAgBLAOoMAAADAE0ALgAECn8dAAMBAAgJOCKCBgADAwABAAgJOCKCBgADAwAVAAUJ5w9EswAeAQABLgAFFAcJHQAHANQZAA==.Miniss:BAECLgAFFH8dAAQHAAcJ1BnHCQDyAQdoDAAABwBeAGkMAAAGAE8AawwAAAQAUgBqDAAABABXAGwMAAACABoAbQwAAAEADwDqDAAABQBhAAcABwnUGccJAPIBB2gMAAAHAF4AaQwAAAMATwBrDAAAAwBSAGoMAAAEAFcAbAwAAAIAGgBtDAAAAQAPAOoMAAAEAGEABgACCYANTA0AowACaQwAAAIAHgBrDAAAAQAmABsAAgl0D5cIAJcAAmkMAAABABMA6gwAAAEAPAAuAAQKf0EABBsACQkjJm8AACYDAAcACQnfJb4EAC4DABsACQk3JW8AACYDAAYAAgkRIEVBALAAAAAA.',
Mo='Mobes:BAEBLgAECn80AAIQAAkJjRdNCwDqAQloDAAACABCAGkMAAAHAE8AawwAAAcARgBqDAAABgAzAGwMAAAHADcAbQwAAAYAQQDqDAAABQBOAG4MAAAFACUAbwwAAAEAHQAQAAkJjRdNCwDqAQloDAAACABCAGkMAAAHAE8AawwAAAcARgBqDAAABgAzAGwMAAAHADcAbQwAAAYAQQDqDAAABQBOAG4MAAAFACUAbwwAAAEAHQAAAA==.Moosclemommy:BAECLgAFFH8VAAIIAAYJDiLaBADoAQZoDAAABgBVAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAACAE0A6gwAAAYAXwAIAAYJDiLaBADoAQZoDAAABgBVAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAACAE0A6gwAAAYAXwAuAAQKfyQAAggACAlOJb4FACwDAAgACAlOJb4FACwDAAEuAAUUCAkUAAIAEA0A.',
My='Mythicalhobo:BAEALgADCgUJCAAAAA==.Mythmaker:BAEALgAECgUJDQABLgAECgcJGQAVAMIgAA==.',
Na='Nargrodamus:BAEBLgAECn8oAAIcAAgJ8hhMOwDsAQhoDAAABgBGAGkMAAAHAFYAawwAAAUAQABqDAAABgA5AGwMAAAEAEkAbQwAAAIAGADqDAAABgBLAG4MAAAEADMAHAAICfIYTDsA7AEIaAwAAAYARgBpDAAABwBWAGsMAAAFAEAAagwAAAYAOQBsDAAABABJAG0MAAACABgA6gwAAAYASwBuDAAABAAzAAAA.',
Ni='Nimueh:BAECLgAFFH8PAAIdAAYJNApUBwCRAQZoDAAAAwAvAGkMAAACABwAawwAAAIAEABqDAAAAgAYAGwMAAAFABMA6gwAAAEAFAAdAAYJNApUBwCRAQZoDAAAAwAvAGkMAAACABwAawwAAAIAEABqDAAAAgAYAGwMAAAFABMA6gwAAAEAFAAuAAQKfy0AAx0ACQkvEukUADYCAB0ACQkvEukUADYCAA0ABwngD8sqAEwBAAAA.Nindragosa:BAEALgAFFAQJBAABLgAFFAcJHAAeAIUZAA==.Nindë:BAEBLgAFFH8JAAIfAAMJLQlVCQDcAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwAfAAMJLQlVCQDcAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwABLgAFFAcJHAAeAIUZAA==.Niniane:BAECLgAFFH8cAAMeAAcJhRl8BQDVAQdoDAAABgBOAGkMAAAFAF8AawwAAAUATQBqDAAABAAWAGwMAAABAAoAbQwAAAEAOADqDAAABgBJAB4ABgnEHXwFANUBBmgMAAAFAE4AaQwAAAUAXwBrDAAAAwBNAGoMAAACABYAbQwAAAEAOADqDAAABgBJACAABAkJBCIZAMMABGgMAAABAAoAawwAAAIACQBqDAAAAgARAGwMAAABAAoALgAECn8nAAMeAAkJGyPlDwCiAgAeAAkJGyPlDwCiAgAgAAYJUgq0VgDuAAAAAA==.',
No='Nordsense:BAEALgAECgEJAQAAAA==.Novebear:BAEBLgAFFH8HAAIQAAIJYRt/EQCfAAJoDAAABABCAOoMAAADAEkAEAACCWEbfxEAnwACaAwAAAQAQgDqDAAAAwBJAAEuAAUUAwkPAA8AwiUA.Novelus:BAECLgAFFH8PAAIPAAMJwiX3AwBHAQNoDAAABgBhAGkMAAAEAF4A6gwAAAUAYgAPAAMJwiX3AwBHAQNoDAAABgBhAGkMAAAEAF4A6gwAAAUAYgAuAAQKfzEAAg8ACQkAJvgAAFEDAA8ACQkAJvgAAFEDAAAA.',
Ol='Oldbronze:BAECLgAFFH8QAAIPAAUJLBp7CwAyAQVoDAAABQBLAGkMAAAEAEkAawwAAAIAKABqDAAAAQBIAOoMAAAEAE4ADwAFCSwaewsAMgEFaAwAAAUASwBpDAAABABJAGsMAAACACgAagwAAAEASADqDAAABABOAC4ABAp/MgACDwAICdUivwUAkQIADwAICdUivwUAkQIAAAA=.',
On='Onenjen:BAEBLgAECn8nAAITAAgJKgSdEADyAAhoDAAACAAPAGkMAAAIAAgAawwAAAgAFwBqDAAABAANAGwMAAAEAAgAbQwAAAEABQDqDAAABQAMAG4MAAABAAIAEwAICSoEnRAA8gAIaAwAAAgADwBpDAAACAAIAGsMAAAIABcAagwAAAQADQBsDAAABAAIAG0MAAABAAUA6gwAAAUADABuDAAAAQACAAAA.',
['Oñ']='Oññayu:BAEALgAECgIJAgAAAA==.',
Pa='Parkercannon:BAECLgAFFH8jAAINAAcJDx8GAQA6AgdoDAAABgBeAGkMAAAFAFwAawwAAAYAUgBqDAAABwBJAGwMAAAEAF4AbQwAAAMALgDqDAAABABBAA0ABwkPHwYBADoCB2gMAAAGAF4AaQwAAAUAXABrDAAABgBSAGoMAAAHAEkAbAwAAAQAXgBtDAAAAwAuAOoMAAAEAEEALgAECn8tAAINAAkJkyTuAADQAwANAAkJkyTuAADQAwAAAA==.Patrennessy:BAEBLgAECn8xAAIIAAkJsSTaAQA0AwloDAAABgBiAGkMAAAGAGAAawwAAAYAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAMAVwAIAAkJsSTaAQA0AwloDAAABgBiAGkMAAAGAGAAawwAAAYAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAMAVwAAAA==.',
Ra='Ramsama:BAEALgAECgkJEQAAAA==.Ramsdh:BAEALgAFFAMJAwABLgAFFAcJGwARANcdAA==.Ramsx:BAECLgAFFH8bAAMRAAcJ1x1+BADrAQdoDAAABwBcAGkMAAAGAF8AawwAAAQAUgBqDAAAAgAuAGwMAAABACkA6gwAAAYAVgBuDAAAAQA7ABEABgmJIH4EAOsBBmgMAAAHAFwAaQwAAAQAXwBrDAAAAwBSAGoMAAACAC4A6gwAAAUAVgBuDAAAAQA7ABMABAlLEmgCABYBBGkMAAACADoAawwAAAEAOgBsDAAAAQApAOoMAAABABwALgAECn8XAAMRAAcJyiXcFABrAgARAAcJyiXcFABrAgATAAEJOCTzGwBWAAAAAA==.Rarelinelk:BAEALgAECgIJAgABLgAFFAYJFQAcACMjAA==.',
Re='Recursively:BAECLgAFFH8fAAQHAAgJ8ROrAwDnAQhoDAAABgBhAGkMAAAFAEAAawwAAAYAQgBqDAAAAwAlAGwMAAABABUAbQwAAAEACADqDAAACABGAG4MAAABABsABwAHCTAWqwMA5wEHaAwAAAYAYQBpDAAAAwBAAGsMAAAEADoAagwAAAIADgBsDAAAAQAVAOoMAAAGAEYAbgwAAAEAGwAGAAQJvg/YAwBaAQRpDAAAAQAsAGsMAAACAEIAbQwAAAEACADqDAAAAgApABsAAgkICHYFAFcAAmkMAAABABQAagwAAAEAJQAuAAQKfyoABAcACQlpI+gLANQCAAcACQlII+gLANQCAAYABgkKIoQIADoCABsAAQkAANgiAGYAAAAA.Redxr:BAEALgAECgYJDQABLgAFFAcJDgAOAA0WAA==.Releira:BAEALgAFFAIJAwABLgAFFAUJEQASAOUUAA==.Resika:BAEALgAECgkJCQABLgAECgkJEQADAAAAAA==.',
Ri='Riversong:BAEALgAECgYJBgABLgAFFAYJDwAdADQKAA==.',
Sh='Sharrq:BAECLgAFFH8WAAIhAAQJRh57AACFAQRoDAAABwBUAGkMAAAGADAAawwAAAQAWgDqDAAABQBWACEABAlGHnsAAIUBBGgMAAAHAFQAaQwAAAYAMABrDAAABABaAOoMAAAFAFYALgAECn8gAAMhAAgJxCCoAAASAwAhAAgJxCCoAAASAwAiAAEJKwlZHgA0AAAAAA==.Shotgunarms:BAEALgAECgQJBAABLgAECgkJGwAZADAdAA==.',
Si='Silversoph:BAEALgADCgMJAwAAAA==.Sivvychuckle:BAEALgAECgIJAwABLgAECgcJCwADAAAAAA==.Sivvygrows:BAEALgAECgcJBwABLgAECgcJCwADAAAAAA==.Sivvyrawr:BAEALgAECgcJCwAAAA==.',
Sl='Slammybreath:BAECLgAFFH8JAAMEAAQJ4xMhHQAmAQRoDAAAAwArAGkMAAADAEwAawwAAAIAHADqDAAAAQA3AAQABAnjEyEdACYBBGgMAAACACsAaQwAAAMATABrDAAAAgAcAOoMAAABADcABQABCTYBHgwAQwABaAwAAAEAAwAuAAQKfx0AAwQACAloFCQxAD4BAAQABgnOEiQxAD4BAAUACAnaE/ssALQAAAEuAAUUCAkUAAIAEA0A.',
Sp='Spicyhotwing:BAECLgAFFH8UAAMCAAgJEA2KAwDOAQhoDAAAAwAKAGkMAAADAAsAawwAAAMAGwBqDAAABAAhAGwMAAABAAUAbQwAAAEAWQDqDAAABAAqAG4MAAABAC0AAgAGCaEIigMAzgEGaAwAAAEACgBpDAAAAQALAGsMAAABABsAagwAAAQAIQBsDAAAAQAFAOoMAAAEACoABAAFCUgULQwAugEFaAwAAAIATwBpDAAAAgBgAGsMAAACAEYAbQwAAAEABABuDAAAAQAJAC4ABAp/GAAEAgAICesSQBQAAgIAAgAICesSQBQAAgIABAAECbQk3DEAPQEABQABCX0efjgAVQAAAAA=.',
Ta='Tauntinitis:BAEALgAECgUJBQABLgAFFAMJCgAUAMwTAA==.',
Te='Tendeyaloran:BAEALgAECgYJEAAAAA==.',
Th='Thanala:BAECLgAFFH8cAAIBAAcJKCA5AwBTAgdoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEAbQwAAAEAKwDqDAAABwBbAAEABwkoIDkDAFMCB2gMAAAGAFIAaQwAAAYAYQBrDAAABABYAGoMAAADAEsAbAwAAAEAYQBtDAAAAQArAOoMAAAHAFsALgAECn8jAAIBAAgJKh98FABuAgABAAgJKh98FABuAgAAAA==.',
Tr='Trintu:BAEALgAECgkJAwABLgAFFAYJFwAXACAOAA==.',
Yo='Yoktuah:BAEBLgAFFH8GAAMBAAQJ6gPGDQD9AARoDAAAAwAAAGkMAAABABwAawwAAAEACgDqDAAAAQAAAAEABAnqA8YNAP0ABGgMAAABAAAAaQwAAAEAHABrDAAAAQAKAOoMAAABAAAAFQABCRgRnTEAUgABaAwAAAIAKwABLgAFFAQJDAAJACgUAA==.',
Yu='Yungdh:BAEBLgAECn8cAAIKAAcJ+hyXLwDjAQdoDAAABAA8AGkMAAAEAEwAawwAAAUAUgBqDAAABABOAGwMAAAEAEkAbQwAAAEAPADqDAAABgBbAAoABwn6HJcvAOMBB2gMAAAEADwAaQwAAAQATABrDAAABQBSAGoMAAAEAE4AbAwAAAQASQBtDAAAAQA8AOoMAAAGAFsAAS4ABRQHCSAAIwAOJgA=.Yungdrood:BAECLgAFFH8gAAIjAAcJDiZuAQCAAgdoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBhAGwMAAACAF4AbQwAAAEAXADqDAAABQBiACMABwkOJm4BAIACB2gMAAAGAGMAaQwAAAcAYwBrDAAABgBjAGoMAAAFAGEAbAwAAAIAXgBtDAAAAQBcAOoMAAAFAGIALgAECn82AAIjAAkJ1iZBAgCfAwAjAAkJ1iZBAgCfAwAAAA==.Yungmonk:BAEALgAECgQJBAABLgAFFAcJIAAjAA4mAA==.Yungwizard:BAEBLgAECn8WAAISAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQASAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQABLgAFFAcJIAAjAA4mAA==.',
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
