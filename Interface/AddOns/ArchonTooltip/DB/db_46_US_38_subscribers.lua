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

local lookup = {'Paladin-Holy','Evoker-Preservation','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Paladin-Protection','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Priest-Discipline','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Mage-Frost','Rogue-Assassination','Warrior-Fury','Paladin-Retribution','Rogue-Outlaw','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','Warlock-Affliction','DeathKnight-Unholy','Priest-Holy','Hunter-BeastMastery','Druid-Feral','Hunter-Marksmanship','Mage-Fire','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=46,date='2026-05-25',data={Ad='Addex:BAEBLgAFFH8NAAIBAAYJjxM5BQCKAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABAAYJjxM5BQCKAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABLgAFFAkJMQACAFYgAA==.',
Ae='Aeveracy:BAEALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Am='Ambient:BAECLgAFFH8xAAMCAAkJViAeAABrAwloDAAACABhAGkMAAAIAFwAawwAAAcAUABqDAAABwBjAGwMAAAGAFYAbQwAAAIAVADqDAAACABLAG4MAAACAEkAbwwAAAEAOAACAAkJViAeAABrAwloDAAABgBhAGkMAAAIAFwAawwAAAcAUABqDAAABwBjAGwMAAAGAFYAbQwAAAIAVADqDAAACABLAG4MAAACAEkAbwwAAAEAOAAEAAEJPxd+IABQAAFoDAAAAgA7AC4ABAp/HQADAgAJCXMjvgQAAwMAAgAICSsjvgQAAwMABQABCYgT1joARAAAAAA=.',
Br='Briéè:BAEBLgAECn8WAAMGAAcJxBFLHACnAAdoDAAABQBLAGkMAAAEADMAawwAAAQALwBqDAAAAwAuAGwMAAACADAA6gwAAAMAFgBuDAAAAQAaAAcABgk2DjaLABMBBmgMAAADAC8AaQwAAAMAJABqDAAAAQAqAGwMAAACADAA6gwAAAMAFgBuDAAAAQAaAAYABAnOFkscAKcABGgMAAACAEsAaQwAAAEAMwBrDAAABAAvAGoMAAACAC4AAAA=.Bruwon:BAECLgAFFH8wAAIIAAgJtiGfAABJAghoDAAACABcAGkMAAAIAGMAawwAAAgAWgBqDAAABwBIAGwMAAAGAGIAbQwAAAEATwDqDAAACQBeAG4MAAABADIACAAICbYhnwAASQIIaAwAAAgAXABpDAAACABjAGsMAAAIAFoAagwAAAcASABsDAAABgBiAG0MAAABAE8A6gwAAAkAXgBuDAAAAQAyAC4ABAp/IQACCAAJCUAhxwQAPgMACAAJCUAhxwQAPgMAAAA=.',
Ch='Charzie:BAEBLgAFFH8FAAIJAAUJRxg8BAArAQVoDAAAAQBOAGkMAAABAEkAawwAAAEAOQBqDAAAAQAzAOoMAAABACcACQAFCUcYPAQAKwEFaAwAAAEATgBpDAAAAQBJAGsMAAABADkAagwAAAEAMwDqDAAAAQAnAAEuAAUUCAkwAAgAtiEA.',
Ci='Ciprox:BAEBLgAECn8VAAIKAAgJpx6vEgA1AghoDAAAAwBVAGkMAAADAEcAawwAAAMAXABqDAAAAwBQAGwMAAADAGAAbQwAAAIAOADqDAAAAwBcAG4MAAABADcACgAICacerxIANQIIaAwAAAMAVQBpDAAAAwBHAGsMAAADAFwAagwAAAMAUABsDAAAAwBgAG0MAAACADgA6gwAAAMAXABuDAAAAQA3AAEuAAUUCAkbAAsA8BgA.',
Cy='Cyprexdh:BAECLgAFFH8bAAMLAAgJ8BgTBgBRAghoDAAABwBjAGkMAAAFAFoAawwAAAQASwBqDAAABABbAGwMAAABAB0AbQwAAAEADwDqDAAABABaAG4MAAABAC0ACwAICYYWEwYAUQIIaAwAAAQAQABpDAAABABaAGsMAAADAEsAagwAAAQAWwBsDAAAAQAdAG0MAAABAA8A6gwAAAMAUgBuDAAAAQAtAAwABAl/Ge8BAHsBBGgMAAADAGMAaQwAAAEABQBrDAAAAQBBAOoMAAABAFoALgAECn8aAAQMAAgJ8CU5AwBSAwAMAAgJWyU5AwBSAwALAAMJsiSZewA1AQANAAEJAAC2LQApAAAAAA==.',
Da='Danilynn:BAEALgADCggJFAABLgAECgcJIwAOAKEDAA==.Danitsia:BAEBLgAECn8jAAMOAAcJoQM3RwDNAAdoDAAABgAIAGkMAAAGAAwAawwAAAYACQBqDAAABQAUAGwMAAAFAAsAbQwAAAEABADqDAAABgAIAA4ABwmhAzdHAM0AB2gMAAAGAAgAaQwAAAYADABrDAAABQAJAGoMAAAFABQAbAwAAAQACwBtDAAAAQAEAOoMAAAFAAgADwADCeMAdVEARgADawwAAAEAAgBsDAAAAQADAOoMAAABAAAAAAA=.',
De='Delabrand:BAEALgAECgYJCQABLgAFFAgJHwAQAIkmAA==.Delajuv:BAEBLgAFFH8JAAIRAAUJrx46BQBqAQVoDAAAAgBTAGkMAAACAEwAawwAAAIATQBqDAAAAQAJAOoMAAACAEwAEQAFCa8eOgUAagEFaAwAAAIAUwBpDAAAAgBMAGsMAAACAE0AagwAAAEACQDqDAAAAgBMAAEuAAUUCAkfABAAiSYA.Delarage:BAECLgAFFH8fAAIQAAgJiSZBAAADAwhoDAAABgBjAGkMAAAEAGMAawwAAAQAYwBqDAAABQBiAGwMAAADAGQAbQwAAAIAYQDqDAAABgBjAG4MAAABAF4AEAAICYkmQQAAAwMIaAwAAAYAYwBpDAAABABjAGsMAAAEAGMAagwAAAUAYgBsDAAAAwBkAG0MAAACAGEA6gwAAAYAYwBuDAAAAQBeAC4ABAp/IQACEAAJCf4m/QAAkAMAEAAJCf4m/QAAkAMAAAA=.Deleerious:BAECLgAFFH8TAAISAAUJzCXFDwBgAQVoDAAABQBiAGkMAAAFAGEAawwAAAIAXgBqDAAAAQBdAOoMAAAGAGAAEgAFCcwlxQ8AYAEFaAwAAAUAYgBpDAAABQBhAGsMAAACAF4AagwAAAEAXQDqDAAABgBgAC4ABAp/KgACEgAICR0kogUAOAMAEgAICR0kogUAOAMAAAA=.',
Do='Doriel:BAEALgAECgMJBAABLgAFFAUJFgATAJ8bAA==.',
Du='Dubsstree:BAEALgADCgYJBgABLgAFFAcJHQAHANgZAA==.',
Dw='Dwarfwarloc:BAEBLgAECn8aAAIHAAgJKSLyFACVAghoDAAABABgAGkMAAAEAFMAawwAAAQAWgBqDAAABABgAGwMAAADAGEAbQwAAAEARADqDAAABQBfAG8MAAABAE4ABwAICSki8hQAlQIIaAwAAAQAYABpDAAABABTAGsMAAAEAFoAagwAAAQAYABsDAAAAwBhAG0MAAABAEQA6gwAAAUAXwBvDAAAAQBOAAAA.',
Eg='Egirlarmpits:BAEALgAFFAMJAwABLgAFFAUJDQAKAPwQAA==.',
Em='Emellious:BAECLgAFFH8XAAISAAYJyxaTCwCFAQZoDAAABgBPAGkMAAAFAFsAawwAAAMAGgBqDAAAAgA6AG0MAAABAAcA6gwAAAYAVwASAAYJyxaTCwCFAQZoDAAABgBPAGkMAAAFAFsAawwAAAMAGgBqDAAAAgA6AG0MAAABAAcA6gwAAAYAVwAuAAQKfxwAAxIACAkEIaEMAM4CABIACAkEIaEMAM4CABQAAQmQC4IfADUAAAAA.',
Fr='Freddyfletch:BAEALgADCgUJBQAAAA==.',
Fu='Funkaroused:BAEBLgAECn8vAAIVAAgJmRq4HwDSAQhoDAAABwBbAGkMAAAHAEcAawwAAAcAQABqDAAABgBFAGwMAAAHAEsAbQwAAAEAMADqDAAACABKAG4MAAAEADIAFQAICZkauB8A0gEIaAwAAAcAWwBpDAAABwBHAGsMAAAHAEAAagwAAAYARQBsDAAABwBLAG0MAAABADAA6gwAAAgASgBuDAAABAAyAAAA.',
Gi='Giantmagic:BAEBLgAECn8bAAITAAcJQR19XQAiAgdoDAAABABOAGkMAAAEAFIAawwAAAQAWwBqDAAABgBOAGwMAAACAD4AbQwAAAIAQgDqDAAABQBEABMABwlBHX1dACICB2gMAAAEAE4AaQwAAAQAUgBrDAAABABbAGoMAAAGAE4AbAwAAAIAPgBtDAAAAgBCAOoMAAAFAEQAAS4ABAoHCRwAFgAzIgA=.',
Gj='Gjlo:BAECLgAFFH8NAAMVAAQJ/Q+sHQAbAQRoDAAABgBGAGkMAAADACUAawwAAAEACwDqDAAAAwAsABUABAn9D6wdABsBBGgMAAAEAEYAaQwAAAIAJQBrDAAAAQALAOoMAAADACwAEAACCaQDKA4AZQACaAwAAAIAEQBpDAAAAQAAAC4ABAp/UwADFQAJCaYeaAUA8QIAFQAJCaYeaAUA8QIAEAAHCXcPbycA1QAAAAA=.',
Gr='Gronknose:BAEBLgAECn8WAAIXAAcJ0iHgAQCcAgdoDAAAAwBVAGkMAAAEAFwAawwAAAQATABqDAAAAwBeAGwMAAACAFcAbQwAAAEAUgDqDAAABQBfABcABwnSIeABAJwCB2gMAAADAFUAaQwAAAQAXABrDAAABABMAGoMAAADAF4AbAwAAAIAVwBtDAAAAQBSAOoMAAAFAF8AAS4ABAoJCTUACACxJAA=.',
Ha='Hakdh:BAEALgAECgYJBgABLgAFFAYJFwAYACEOAA==.Hakdk:BAECLgAFFH8XAAIYAAYJIQ7+BQA7AQZoDAAABAAlAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAYAQAAYAAYJIQ7+BQA7AQZoDAAABAAlAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAYAQAAuAAQKfxQAAhgACAkkHtMKAGoCABgACAkkHtMKAGoCAAAA.Hakgek:BAEBLgAFFH8KAAIRAAUJFAyxBQBdAQVoDAAAAgAlAGkMAAACACgAawwAAAIAJgBsDAAAAwAdAG4MAAABAAgAEQAFCRQMsQUAXQEFaAwAAAIAJQBpDAAAAgAoAGsMAAACACYAbAwAAAMAHQBuDAAAAQAIAAEuAAUUBgkXABgAIQ4A.Hakmonk:BAEBLgAFFH8GAAIIAAQJSxHODQAWAQRoDAAAAgAmAGkMAAACAEsAawwAAAEAEQDqDAAAAQAuAAgABAlLEc4NABYBBGgMAAACACYAaQwAAAIASwBrDAAAAQARAOoMAAABAC4AAS4ABRQGCRcAGAAhDgA=.Haksham:BAEALgAECgkJDQABLgAFFAYJFwAYACEOAA==.Hakwar:BAEALgAECgUJBQABLgAFFAYJFwAYACEOAA==.Halosbrew:BAECLgAFFH8JAAIIAAQJqhnoDwADAQRoDAAAAgBLAGkMAAADAFYAawwAAAEAGgDqDAAAAwBKAAgABAmqGegPAAMBBGgMAAACAEsAaQwAAAMAVgBrDAAAAQAaAOoMAAADAEoALgAECn8UAAMIAAgJRx4TFQBjAgAIAAcJzSETFQBjAgAZAAUJaRO9PAAoAQAAAA==.Halosdk:BAEBLgAFFH8SAAIYAAUJCR+CCwBxAQVoDAAABABTAGkMAAADAFMAawwAAAMARgBqDAAAAgBAAOoMAAAGAFAAGAAFCQkfggsAcQEFaAwAAAQAUwBpDAAAAwBTAGsMAAADAEYAagwAAAIAQADqDAAABgBQAAEuAAUUBQkJAAgAqhkA.Halosmage:BAEALgAECggJDgABLgAFFAUJCQAIAKoZAA==.',
He='Heavensfeel:BAECLgAFFH8GAAICAAIJwR7VGwCzAAJoDAAAAwBSAOoMAAADAEsAAgACCcEe1RsAswACaAwAAAMAUgDqDAAAAwBLAC4ABAp/NAAEAgAJCRMfDAgAuwIAAgAJCRMfDAgAuwIABAAJCcgb+woAkAIABQACCY4LgRkAZwAAAS4ABRQFCQkACACqGQA=.',
In='Inaríus:BAEBLgAECn8cAAIWAAcJMyJjJABXAgdoDAAABgBUAGkMAAAFAFoAawwAAAQAVgBqDAAABABRAGwMAAAEAGEA6gwAAAQAYQBuDAAAAQBEABYABwkzImMkAFcCB2gMAAAGAFQAaQwAAAUAWgBrDAAABABWAGoMAAAEAFEAbAwAAAQAYQDqDAAABABhAG4MAAABAEQAAAA=.Initiative:BAEBLgAECn8bAAMaAAkJLx2ZDQCVAgloDAAAAwBXAGkMAAADAFwAawwAAAQAXwBqDAAAAwA8AGwMAAAFAEYAbQwAAAIASQDqDAAABABRAG4MAAACAD0AbwwAAAEAMQAaAAgJcB6ZDQCVAghoDAAAAgBXAGkMAAACAFwAawwAAAMAXwBqDAAAAgA8AGwMAAACAEYAbQwAAAIASQDqDAAAAgBRAG4MAAABAD0AGQAICa8eWxoADQIIaAwAAAEAWQBpDAAAAQBdAGsMAAABAF4AagwAAAEAVQBsDAAAAwBgAOoMAAACAFAAbgwAAAEAIABvDAAAAQA/AAAA.',
It='Itsgrippy:BAEALgAECgYJDgAAAA==.',
Je='Jev:BAEBLgAECn8hAAIOAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAAOAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAAAAA==.',
Ke='Keeflan:BAECLgAFFH8NAAIKAAUJ/BDrDwBmAQVoDAAAAwA8AGkMAAADABoAawwAAAIAMgBtDAAAAQAKAOoMAAAEAEUACgAFCfwQ6w8AZgEFaAwAAAMAPABpDAAAAwAaAGsMAAACADIAbQwAAAEACgDqDAAABABFAC4ABAp/GwADCgAICSEguSsAugEACgAHCU8guSsAugEAGwAHCUYNrUAAfgEAAAA=.',
Ku='Kungfupander:BAEALgADCgMJAwABLgAECgcJHAAWADMiAA==.',
Le='Lewinskibidi:BAEBLgAFFH8MAAIEAAYJ/hZ8EACWAQZoDAAAAwBMAGkMAAADAEUAawwAAAIARQBqDAAAAQATAOoMAAACAEMAbgwAAAEACwAEAAYJ/hZ8EACWAQZoDAAAAwBMAGkMAAADAEUAawwAAAIARQBqDAAAAQATAOoMAAACAEMAbgwAAAEACwABLgAFFAcJIwAOAA4fAA==.',
Ma='Madtheaug:BAECLgAFFH8HAAIEAAQJwBTgHgAjAQRoDAAAAgA1AGkMAAACAFUAawwAAAIANgDqDAAAAQATAAQABAnAFOAeACMBBGgMAAACADUAaQwAAAIAVQBrDAAAAgA2AOoMAAABABMALgAECn8WAAMFAAgJkyAzEgC+AQAFAAcJsxgzEgC+AQAEAAUJgSFyIAC9AQABLgAFFAkJLQAHACQmAA==.Madthehunt:BAEALgAFFAEJAQABLgAFFAkJLQAHACQmAA==.Madthelock:BAECLgAFFH8tAAQHAAkJJCbzAADTAgloDAAABQBjAGkMAAAHAGMAawwAAAcAZABqDAAABwBYAGwMAAAFAGQAbQwAAAIAYgDqDAAACABhAG4MAAACAFoAbwwAAAIAXgAHAAkJFSLzAADTAgloDAAAAwBfAGkMAAADAGMAawwAAAEAYgBqDAAAAgBHAGwMAAACAFQAbQwAAAEAJADqDAAABABhAG4MAAACAFoAbwwAAAIAXgAGAAcJiSY4AACWAgdoDAAAAQBjAGkMAAADAGMAawwAAAUAZABqDAAAAwBYAGwMAAACAGEAbQwAAAEAYgDqDAAAAwBhABwABgkTJkMAAB0CBmgMAAABAGEAaQwAAAEAYwBrDAAAAQBeAGoMAAACAFYAbAwAAAEAZADqDAAAAQBgAC4ABAp/KgAEBwAJCbImzQIAXAMABwAJCU4mzQIAXAMAHAAICWYmuAAACwMABgAGCRwmXQoAGQIAAAA=.Magolli:BAEALgAECgQJBAABLgAFFAUJFgATAJ8bAA==.Magølli:BAECLgAFFH8WAAITAAUJnxu6NABfAQVoDAAABgBWAGkMAAAGAEMAawwAAAQAPQBqDAAAAgBLAOoMAAAEAEMAEwAFCZ8bujQAXwEFaAwAAAYAVgBpDAAABgBDAGsMAAAEAD0AagwAAAIASwDqDAAABABDAC4ABAp/LwACEwAJCTchFxUAxQIAEwAJCTchFxUAxQIAAAA=.',
Me='Megachud:BAEALgAFFAEJAQABLgAFFAUJDQAKAPwQAA==.',
Mi='Minbä:BAEALgAECgYJEgABLgAFFAcJHQAHANgZAA==.Minigun:BAEALgAECgcJCgAAAQ==.Minipala:BAECLgAFFH8PAAIBAAUJEBcrEwBmAQVoDAAABQBPAGkMAAADADMAawwAAAMASwBqDAAAAQALAOoMAAADAE0AAQAFCRAXKxMAZgEFaAwAAAUATwBpDAAAAwAzAGsMAAADAEsAagwAAAEACwDqDAAAAwBNAC4ABAp/HQADAQAICTgiggYAAwMAAQAICTgiggYAAwMAFgAFCecPRLMAHgEAAS4ABRQHCR0ABwDYGQA=.Miniss:BAECLgAFFH8dAAQHAAcJ2BlNDQDnAQdoDAAABwBeAGkMAAAGAE8AawwAAAQAUgBqDAAABABXAGwMAAACABoAbQwAAAEADwDqDAAABQBhAAcABwnYGU0NAOcBB2gMAAAHAF4AaQwAAAMATwBrDAAAAwBSAGoMAAAEAFcAbAwAAAIAGgBtDAAAAQAPAOoMAAAEAGEABgACCYANTA0AowACaQwAAAIAHgBrDAAAAQAmABwAAgl0D3IKAJQAAmkMAAABABMA6gwAAAEAPAAuAAQKf0EABBwACQkjJocAACEDAAcACQnnJUUFACsDABwACQk4JYcAACEDAAYAAgkRIEVBALAAAAAA.',
Mo='Mobes:BAECLgAFFH8GAAIRAAMJbAtHFQCdAANoDAAAAwAhAGkMAAACABUA6gwAAAEAIAARAAMJbAtHFQCdAANoDAAAAwAhAGkMAAACABUA6gwAAAEAIAAuAAQKfzQAAhEACQmNF1YMAOkBABEACQmNF1YMAOkBAAAA.Moosclemommy:BAECLgAFFH8VAAIIAAYJDiJBBgDfAQZoDAAABgBVAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAACAE0A6gwAAAYAXwAIAAYJDiJBBgDfAQZoDAAABgBVAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAACAE0A6gwAAAYAXwAuAAQKfycAAggACAlOJb4FACwDAAgACAlOJb4FACwDAAEuAAUUCAkUAAIAEA0A.Mowry:BAEALgAECgYJBgABLgAFFAUJFwAOAKYZAA==.',
My='Mythicalhobo:BAEALgADCgUJCAAAAA==.Mythmaker:BAEALgAECgUJDQABLgAECgcJHAAWADMiAA==.',
Na='Nargrodamus:BAEBLgAECn8uAAIdAAgJIxoMLgApAghoDAAABwBGAGkMAAAIAFYAawwAAAYARgBqDAAABwBbAGwMAAAFAFMAbQwAAAIAGADqDAAABwBRAG4MAAAEADMAHQAICSMaDC4AKQIIaAwAAAcARgBpDAAACABWAGsMAAAGAEYAagwAAAcAWwBsDAAABQBTAG0MAAACABgA6gwAAAcAUQBuDAAABAAzAAAA.',
Ni='Nimueh:BAECLgAFFH8PAAIeAAYJNArTCACLAQZoDAAAAwAvAGkMAAACABwAawwAAAIAEABqDAAAAgAYAGwMAAAFABMA6gwAAAEAFAAeAAYJNArTCACLAQZoDAAAAwAvAGkMAAACABwAawwAAAIAEABqDAAAAgAYAGwMAAAFABMA6gwAAAEAFAAuAAQKfy4AAx4ACQkvEukUADYCAB4ACQkvEukUADYCAA4ABwngD4QtAEkBAAAA.Nindragosa:BAEALgAFFAQJBAABLgAFFAcJHAAfAIsZAA==.Nindë:BAEBLgAFFH8JAAIgAAMJLQmDCgDbAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwAgAAMJLQmDCgDbAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwABLgAFFAcJHAAfAIsZAA==.Niniane:BAECLgAFFH8cAAMfAAcJixkkCADEAQdoDAAABgBOAGkMAAAFAF8AawwAAAUATQBqDAAABAAWAGwMAAABAAoAbQwAAAEAOADqDAAABgBJAB8ABgnLHSQIAMQBBmgMAAAFAE4AaQwAAAUAXwBrDAAAAwBNAGoMAAACABYAbQwAAAEAOADqDAAABgBJACEABAkJBCIZAMMABGgMAAABAAoAawwAAAIACQBqDAAAAgARAGwMAAABAAoALgAECn8nAAMfAAkJHCMlEgCbAgAfAAkJHCMlEgCbAgAhAAYJUgq0VgDuAAAAAA==.',
No='Nordsense:BAEALgAECgEJAQAAAA==.Novebear:BAEBLgAFFH8HAAIRAAIJYRswFQCdAAJoDAAABABCAOoMAAADAEkAEQACCWEbMBUAnQACaAwAAAQAQgDqDAAAAwBJAAEuAAUUAwkPABAAwiUA.Novelus:BAECLgAFFH8PAAIQAAMJwiX3AwBHAQNoDAAABgBhAGkMAAAEAF4A6gwAAAUAYgAQAAMJwiX3AwBHAQNoDAAABgBhAGkMAAAEAF4A6gwAAAUAYgAuAAQKfzYAAhAACQkAJhcBAE0DABAACQkAJhcBAE0DAAAA.',
Ol='Oldbronze:BAECLgAFFH8RAAIQAAUJtRryCwA+AQVoDAAABQBLAGkMAAAEAEkAawwAAAIAKABqDAAAAQBIAOoMAAAFAFMAEAAFCbUa8gsAPgEFaAwAAAUASwBpDAAABABJAGsMAAACACgAagwAAAEASADqDAAABQBTAC4ABAp/MgACEAAICdkiUwYAiQIAEAAICdkiUwYAiQIAAAA=.',
On='Onenjen:BAEBLgAECn8nAAIUAAgJKARwEQDyAAhoDAAACAAPAGkMAAAIAAgAawwAAAgAFwBqDAAABAANAGwMAAAEAAgAbQwAAAEABQDqDAAABQAMAG4MAAABAAIAFAAICSgEcBEA8gAIaAwAAAgADwBpDAAACAAIAGsMAAAIABcAagwAAAQADQBsDAAABAAIAG0MAAABAAUA6gwAAAUADABuDAAAAQACAAAA.',
['Oñ']='Oññayu:BAEALgAECgIJAgAAAA==.',
Pa='Parkercannon:BAECLgAFFH8jAAIOAAcJDh8GAQA6AgdoDAAABgBeAGkMAAAFAFwAawwAAAYAUgBqDAAABwBJAGwMAAAEAF4AbQwAAAMALgDqDAAABABBAA4ABwkOHwYBADoCB2gMAAAGAF4AaQwAAAUAXABrDAAABgBSAGoMAAAHAEkAbAwAAAQAXgBtDAAAAwAuAOoMAAAEAEEALgAECn8tAAIOAAkJlCTuAADQAwAOAAkJlCTuAADQAwAAAA==.Patrennessy:BAEBLgAECn81AAIIAAkJsSTMAQA7AwloDAAABwBiAGkMAAAHAGAAawwAAAcAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAQAVwAIAAkJsSTMAQA7AwloDAAABwBiAGkMAAAHAGAAawwAAAcAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAQAVwAAAA==.',
Ra='Ramsama:BAEALgAFFAEJAQAAAA==.Ramsdh:BAEBLgAFFH8FAAILAAQJ9Qv4UQDKAARoDAAAAQAWAGsMAAABACcAagwAAAEAAwDqDAAAAgAeAAsABAn1C/hRAMoABGgMAAABABYAawwAAAEAJwBqDAAAAQADAOoMAAACAB4AAS4ABRQHCRsAEgDXHQA=.Ramsx:BAECLgAFFH8bAAMSAAcJ1x0DBgDiAQdoDAAABwBcAGkMAAAGAF8AawwAAAQAUgBqDAAAAgAuAGwMAAABACkA6gwAAAYAVgBuDAAAAQA7ABIABgmJIAMGAOIBBmgMAAAHAFwAaQwAAAQAXwBrDAAAAwBSAGoMAAACAC4A6gwAAAUAVgBuDAAAAQA7ABQABAlLEmgCABYBBGkMAAACADoAawwAAAEAOgBsDAAAAQApAOoMAAABABwALgAECn8XAAMSAAcJyiXcFABrAgASAAcJyiXcFABrAgAUAAEJOCQwHQBVAAAAAA==.Rarelinelk:BAEALgAECgIJAgABLgAFFAYJGQAdAJcjAA==.',
Re='Recursively:BAECLgAFFH8hAAQHAAgJZBSrAwDnAQhoDAAABwBhAGkMAAAGAEgAawwAAAYAQgBqDAAAAwAlAGwMAAABABUAbQwAAAEACADqDAAACABGAG4MAAABABsABwAHCTAWqwMA5wEHaAwAAAcAYQBpDAAAAwBAAGsMAAAEADoAagwAAAIADgBsDAAAAQAVAOoMAAAGAEYAbgwAAAEAGwAGAAQJvg/YAwBaAQRpDAAAAQAsAGsMAAACAEIAbQwAAAEACADqDAAAAgApABwAAgkuHFYRAFkAAmkMAAACAEgAagwAAAEAJQAuAAQKfyoABAcACQltIzQNANACAAcACQlNIzQNANACAAYABgkKIoQIADoCABwAAQkAANgiAGYAAAAA.Redxr:BAEALgAECgYJDQABLgAFFAcJDgAPAA8WAA==.Releira:BAEALgAFFAIJAwABLgAFFAUJFgATAJ8bAA==.Resika:BAEALgAECgkJCQABLgAFFAEJAQADAAAAAA==.',
Ri='Riversong:BAEALgAECggJCwABLgAFFAYJDwAeADQKAA==.',
Sh='Sharrq:BAECLgAFFH8XAAIiAAUJRh6QAAB8AQVoDAAABwBUAGkMAAAGADAAawwAAAQAWgBqDAAAAQATAOoMAAAFAFYAIgAFCUYekAAAfAEFaAwAAAcAVABpDAAABgAwAGsMAAAEAFoAagwAAAEAEwDqDAAABQBWAC4ABAp/IAADIgAICcQgqAAAEgMAIgAICcQgqAAAEgMAIwABCSsJWR4ANAAAAAA=.Shotgunarms:BAEALgAECgQJBAABLgAECgkJGwAaAC8dAA==.',
Si='Silversoph:BAEALgADCgMJAwAAAA==.Sivvychuckle:BAEALgAECgIJAwABLgAECgcJCwADAAAAAA==.Sivvygrows:BAEALgAECgcJBwABLgAECgcJCwADAAAAAA==.Sivvyrawr:BAEALgAECgcJCwAAAA==.',
Sl='Slammybreath:BAECLgAFFH8NAAMEAAQJahjhHQAoAQRoDAAABAA/AGkMAAAEAEwAawwAAAMAMADqDAAAAgA8AAQABAlqGOEdACgBBGgMAAADAD8AaQwAAAQATABrDAAAAwAwAOoMAAACADwABQABCTYBHgwAQwABaAwAAAEAAwAuAAQKfyMAAwQACAm4FwU6ACIBAAQABgl/FwU6ACIBAAUACAnaE/ssALQAAAEuAAUUCAkUAAIAEA0A.',
Sp='Spicyhotwing:BAECLgAFFH8UAAMCAAgJEA2KAwDOAQhoDAAAAwAKAGkMAAADAAsAawwAAAMAGwBqDAAABAAhAGwMAAABAAUAbQwAAAEAWQDqDAAABAAqAG4MAAABAC0AAgAGCaEIigMAzgEGaAwAAAEACgBpDAAAAQALAGsMAAABABsAagwAAAQAIQBsDAAAAQAFAOoMAAAEACoABAAFCUgUKQ4AswEFaAwAAAIATwBpDAAAAgBgAGsMAAACAEYAbQwAAAEABABuDAAAAQAJAC4ABAp/GAAEAgAICesSQBQAAgIAAgAICesSQBQAAgIABAAECbQkhDQAPQEABQABCX0efjgAVQAAAAA=.',
Ta='Tauntinitis:BAEALgAECgUJBQABLgAFFAQJDQAVAP0PAA==.',
Te='Tendeyaloran:BAEALgAECgYJEAAAAA==.',
Th='Thanala:BAECLgAFFH8cAAIBAAcJKCBeBAA9AgdoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEAbQwAAAEAKwDqDAAABwBbAAEABwkoIF4EAD0CB2gMAAAGAFIAaQwAAAYAYQBrDAAABABYAGoMAAADAEsAbAwAAAEAYQBtDAAAAQArAOoMAAAHAFsALgAECn8jAAIBAAgJKh98FABuAgABAAgJKh98FABuAgAAAA==.',
Tr='Trintu:BAEALgAECgkJAwABLgAFFAYJFwAYACEOAA==.',
['Wó']='Wólffy:BAECLgAFFH8iAAIIAAcJLRYVAwC0AQdoDAAABgA9AGkMAAAGAFIAawwAAAYAXgBqDAAABgBMAG0MAAABABcA6gwAAAgARQBuDAAAAQAJAAgABwktFhUDALQBB2gMAAAGAD0AaQwAAAYAUgBrDAAABgBeAGoMAAAGAEwAbQwAAAEAFwDqDAAACABFAG4MAAABAAkALgAECn8gAAIIAAkJBCIwBQA2AwAIAAkJBCIwBQA2AwAAAA==.',
Yo='Yoktuah:BAEBLgAFFH8GAAMBAAQJ6gPGDQD9AARoDAAAAwAAAGkMAAABABwAawwAAAEACgDqDAAAAQAAAAEABAnqA8YNAP0ABGgMAAABAAAAaQwAAAEAHABrDAAAAQAKAOoMAAABAAAAFgABCRgRnTEAUgABaAwAAAIAKwABLgAFFAUJDQAKAPwQAA==.',
Yu='Yungdh:BAEBLgAECn8cAAILAAcJ+xxZMgDhAQdoDAAABAA8AGkMAAAEAEwAawwAAAUAUgBqDAAABABOAGwMAAAEAEkAbQwAAAEAPADqDAAABgBbAAsABwn7HFkyAOEBB2gMAAAEADwAaQwAAAQATABrDAAABQBSAGoMAAAEAE4AbAwAAAQASQBtDAAAAQA8AOoMAAAGAFsAAS4ABRQICSEAJAAPJQA=.Yungdrood:BAECLgAFFH8hAAIkAAgJDyWiAADcAghoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBhAGwMAAACAF4AbQwAAAEAXADqDAAABQBiAG4MAAABAE8AJAAICQ8logAA3AIIaAwAAAYAYwBpDAAABwBjAGsMAAAGAGMAagwAAAUAYQBsDAAAAgBeAG0MAAABAFwA6gwAAAUAYgBuDAAAAQBPAC4ABAp/NgACJAAJCdYmQQIAnwMAJAAJCdYmQQIAnwMAAAA=.Yungmonk:BAEALgAECgQJBAABLgAFFAgJIQAkAA8lAA==.Yungwizard:BAEBLgAECn8WAAITAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQATAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQABLgAFFAgJIQAkAA8lAA==.',
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
