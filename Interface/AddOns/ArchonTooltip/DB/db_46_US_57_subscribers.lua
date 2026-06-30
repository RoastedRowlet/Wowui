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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Mage-Frost','Priest-Holy','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Arms','Warrior-Fury','DeathKnight-Unholy','Hunter-Survival','Mage-Arcane','Paladin-Protection','Druid-Balance','Druid-Restoration','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Druid-Guardian','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Frost','DeathKnight-Blood','Warrior-Protection','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-06-29',data={Ad='Adansso:BAEBLgAECn81AAIBAAkJFxKKHgC5AQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACQA7AG4MAAAFACUAbwwAAAEAGgABAAkJFxKKHgC5AQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACQA7AG4MAAAFACUAbwwAAAEAGgAAAA==.',
Al='Aliastei:BAEALgADCggJDAABLgAECgkJNQACAAoaAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAYJGAADADQRAA==.',
As='Ashko:BAEBLgAECn8yAAMEAAgJDBu/OwAVAghoDAAACgBLAGkMAAAJAFcAawwAAAgAUQBqDAAABwBSAGwMAAAFAFEAbQwAAAMAKwDqDAAABgBHAG4MAAACACkABAAICQwbvzsAFQIIaAwAAAkASwBpDAAACABXAGsMAAAGAFEAagwAAAYAUgBsDAAABQBRAG0MAAADACsA6gwAAAUARwBuDAAAAgApAAUABQlwD7xMAAgBBWgMAAABACYAaQwAAAEAHQBrDAAAAgBPAGoMAAABABcA6gwAAAEAGwAAAA==.',
Ay='Ayodele:BAEBLgAECn84AAIGAAkJtBuCHgCmAgloDAAACQBSAGkMAAAHAEcAawwAAAUAQwBqDAAACABWAGwMAAAGAEkAbQwAAAQAPwDqDAAACABTAG4MAAAGAFYAbwwAAAMAJwAGAAkJtBuCHgCmAgloDAAACQBSAGkMAAAHAEcAawwAAAUAQwBqDAAACABWAGwMAAAGAEkAbQwAAAQAPwDqDAAACABTAG4MAAAGAFYAbwwAAAMAJwAAAA==.',
Az='Azurlia:BAEALgAFFAEJAQAAAA==.',
Ba='Babycora:BAEALgAFFAMJAwABLgAFFAQJEQAHACwhAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAIAAAAAA==.Barrui:BAECLgAFFH8+AAMJAAkJQSADAQDAAgloDAAACgBfAGkMAAALAGIAawwAAAoAXABqDAAACgBgAGwMAAACAFkAbQwAAAMAKQDqDAAACgBdAG4MAAADAGEAbwwAAAMAMwAJAAkJQSADAQDAAgloDAAACgBfAGkMAAAKAGIAawwAAAkAXABqDAAACgBgAGwMAAABAFkAbQwAAAMAKQDqDAAACgBdAG4MAAADAGEAbwwAAAMAMwAKAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzkAAwkACQlwJOkFADMDAAkACQnxIukFADMDAAoABgkfIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8ZAAILAAUJVBvCBQArAQVoDAAACQBVAGkMAAAHAD4AawwAAAMAIABqDAAAAQBJAOoMAAAFAGMACwAFCVQbwgUAKwEFaAwAAAkAVQBpDAAABwA+AGsMAAADACAAagwAAAEASQDqDAAABQBjAC4ABAp/QAACCwAJCaAhOgUAAgMACwAJCaAhOgUAAgMAAAA=.Bestiavera:BAEBLgAECn9FAAIMAAkJbxYFDgAJAgloDAAACwBFAGkMAAAKAE4AawwAAAoARQBqDAAACQBCAGwMAAAJADUAbQwAAAQAOQDqDAAACAA+AG4MAAAHACsAbwwAAAEAGAAMAAkJbxYFDgAJAgloDAAACwBFAGkMAAAKAE4AawwAAAoARQBqDAAACQBCAGwMAAAJADUAbQwAAAQAOQDqDAAACAA+AG4MAAAHACsAbwwAAAEAGAAAAA==.',
Br='Briggoker:BAEALgAECgUJCAAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgUJCAAIAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn9FAAINAAkJSBuwAQDXAQloDAAADABbAGkMAAALAEcAawwAAAsAUgBqDAAACABYAGwMAAAIAEgAbQwAAAMALADqDAAACABDAG4MAAAFAEEAbwwAAAMAPwANAAkJSBuwAQDXAQloDAAADABbAGkMAAALAEcAawwAAAsAUgBqDAAACABYAGwMAAAIAEgAbQwAAAMALADqDAAACABDAG4MAAAFAEEAbwwAAAMAPwAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAFFAMJCQANABUjAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8pAAMBAAkJyiE4AABxAgloDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABwBfAGwMAAAFAGMAbQwAAAEAJQDqDAAABwBhAG4MAAACAF0AbwwAAAIAXgABAAkJyiE4AABxAgloDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABwBfAGwMAAABAGMAbQwAAAEAJQDqDAAABwBhAG4MAAACAF0AbwwAAAIAXgADAAEJIApqXwBCAAFsDAAABAAZAC4ABAp/KgACAQAICXEmCQIAhAMAAQAICXEmCQIAhAMAAAA=.Daeke:BAEALgADCgUJBQABLgAECgQJBwAIAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEBLgAFFH8YAAIGAAUJbwtHKQC9AAVoDAAABwAuAGkMAAAHAB4AawwAAAMADwBqDAAAAQARAOoMAAAGABgABgAFCW8LRykAvQAFaAwAAAcALgBpDAAABwAeAGsMAAADAA8AagwAAAEAEQDqDAAABgAYAAEuAAUUCAkpAAsA1xoA.',
De='Deathbeaver:BAEALgAECgYJCwABLgAECgkJUwAEAF8eAA==.Destrom:BAEBLgAECn8UAAIOAAkJuBHYggBeAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAOAAkJuBHYggBeAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAAAA==.',
Di='Diozi:BAEALgADCgkJCQABLgAECggJLAAPAJUlAA==.',
Ep='Epilepticc:BAECLgAFFH8PAAIEAAQJSB7COAA7AQRoDAAABQBCAGkMAAAEAFUAawwAAAMAUADqDAAAAwBNAAQABAlIHsI4ADsBBGgMAAAFAEIAaQwAAAQAVQBrDAAAAwBQAOoMAAADAE0ALgAECn88AAIEAAkJ6yL5GQCoAgAEAAkJ6yL5GQCoAgAAAA==.',
Et='Ethalon:BAECLgAFFH8TAAMFAAQJ1Bl5GgBNAQRoDAAABgBOAGkMAAAFAFoAawwAAAMAEwDqDAAABQBMAAUABAnUGXkaAE0BBGgMAAAFAE4AaQwAAAUAWgBrDAAAAwATAOoMAAAFAEwABAABCbcC38cAOQABaAwAAAEABgAuAAQKfycAAwUACQmuGycYAFECAAUACQmuGycYAFECAAQAAgnJFKowADYAAAAA.',
Ga='Garlooth:BAECLgAFFH8NAAIQAAMJ5BY0AgDhAANoDAAABgAzAGkMAAAEAE4A6gwAAAMALQAQAAMJ5BY0AgDhAANoDAAABgAzAGkMAAAEAE4A6gwAAAMALQAuAAQKfzYAAhAACQkVJS8AAGIDABAACQkVJS8AAGIDAAAA.',
Gl='Glizzygary:BAEALgAFFAUJEgAAAQ==.',
Gr='Grimvalor:BAEBLgAECn9TAAMEAAkJXx7sHACYAgloDAAACwBcAGkMAAAKAEwAawwAAAsAUgBqDAAACQBYAGwMAAAKAFkAbQwAAAcASwDqDAAADABSAG4MAAAIAD0AbwwAAAUAPQAEAAkJXx7sHACYAgloDAAACgBcAGkMAAAKAEwAawwAAAoAUgBqDAAACABYAGwMAAAJAFkAbQwAAAcASwDqDAAACwBSAG4MAAAIAD0AbwwAAAUAPQARAAUJzwpaQABdAAVoDAAAAQAPAGsMAAABACwAagwAAAEALABsDAAAAQAiAOoMAAABAA8AAAA=.Grunclaws:BAEBLgAECn8VAAQSAAcJIREHQwABAQdoDAAABQAzAGkMAAAFACsAawwAAAQALwBqDAAAAgAfAGwMAAACAEAAbQwAAAEAEwDqDAAAAgAkABIABgl/DwdDAAEBBmgMAAABADMAaQwAAAIAKwBrDAAAAgAvAGoMAAABAB8AbQwAAAEAEwDqDAAAAQAkABMABgkfFTEFAPgABmgMAAAEAE8AaQwAAAMASwBrDAAAAgBEAGoMAAABACEAbAwAAAEACQDqDAAAAQA6ABQAAQlIGblHAEsAAWwMAAABAEAAAS4ABAoJCTIABAAMGwA=.Grunjo:BAEALgAECgkJDAABLgAECgkJMgAEAAwbAA==.Grunsy:BAEALgAECgcJBgABLgAECgkJMgAEAAwbAA==.',
Ha='Haf:BAEBLgAECn8qAAIRAAkJ8hELFQCAAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwARAAkJ8hELFQCAAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAYJGAADADQRAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Ka='Kautheros:BAEBLgAECn8fAAQVAAkJ+Ay+EQCuAQloDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABgBDAG4MAAACAB0AbwwAAAEAHwAVAAkJ+Ay+EQCuAQloDAAAAgAIAGkMAAACABkAawwAAAIAOwBqDAAAAgAfAGwMAAABACIAbQwAAAMACQDqDAAABQBDAG4MAAACAB0AbwwAAAEAHwAWAAYJUglQXADFAAZoDAAAAQAdAGkMAAABABgAawwAAAIAHABqDAAAAQAkAGwMAAACABcA6gwAAAEADAAXAAMJmgaqIABOAANoDAAAAQAJAGkMAAABABgAagwAAAEAGgAAAA==.',
Kr='Kroxychi:BAEALgAECgcJDgAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJDgAIAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8YAAIDAAYJNBE4IgBcAQZoDAAABgAqAGkMAAAGADoAawwAAAQALwBqDAAAAQAaAGwMAAABABYA6gwAAAYAQgADAAYJNBE4IgBcAQZoDAAABgAqAGkMAAAGADoAawwAAAQALwBqDAAAAQAaAGwMAAABABYA6gwAAAYAQgAuAAQKf3QABAMACQkWHsAKAKUCAAMACQkWHsAKAKUCAAEACQmYFBIYAPMBABgABAn/CHBaAKEAAAAA.',
Le='Lennather:BAEBLgAECn9LAAIBAAkJtCVvAQBkAwloDAAACQBjAGkMAAAJAGEAawwAAAgAYABqDAAACABOAGwMAAAKAGEAbQwAAAkAXgDqDAAACwBfAG4MAAAJAGMAbwwAAAIAWgABAAkJtCVvAQBkAwloDAAACQBjAGkMAAAJAGEAawwAAAgAYABqDAAACABOAGwMAAAKAGEAbQwAAAkAXgDqDAAACwBfAG4MAAAJAGMAbwwAAAIAWgAAAA==.',
Li='Lidomi:BAEALgAECgUJDAABLgAFFAQJCwAVAP8PAA==.Lidrunka:BAECLgAFFH8GAAMYAAIJNRehQwCVAAJoDAAAAwAwAOoMAAADAEUAGAACCTUXoUMAlQACaAwAAAIAMADqDAAAAwBFAAEAAQkMAp4UAD0AAWgMAAABAAUALgAECn8YAAMBAAgJdBXVGwD9AQABAAgJ0BTVGwD9AQAYAAQJFhTISgDSAAABLgAFFAQJCwAVAP8PAA==.',
['Lé']='Lépewpew:BAEBLgAECn8YAAIPAAcJSRI/KABdAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKAA8ABwlJEj8oAF0BB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8uAAMZAAgJrA5CCABUAQhoDAAACAA9AGkMAAAIACgAawwAAAkAGgBqDAAABgA1AGwMAAAEACYA6gwAAAcAKQBuDAAAAwAfAG8MAAABABcAGQAICawOQggAVAEIaAwAAAgAPQBpDAAABwAoAGsMAAAIABoAagwAAAUANQBsDAAABAAmAOoMAAAGACkAbgwAAAMAHwBvDAAAAQAXABoABAn5ArZwAHwABGkMAAABAAEAawwAAAEACQBqDAAAAQAJAOoMAAABAAwAAAA=.',
['Má']='Mákí:BAEBLgAECn8kAAQBAAkJThUJIwCZAQloDAAABQBIAGkMAAAEADQAawwAAAUALwBqDAAABABIAGwMAAADAEEAbQwAAAEAFgDqDAAABwBQAG4MAAAFADUAbwwAAAIAKgABAAgJHRcJIwCZAQhoDAAABABIAGkMAAADADQAawwAAAQALwBqDAAAAgBIAGwMAAADAEEA6gwAAAQAUABuDAAABQA1AG8MAAACACoAGAAFCYIWGTwACwEFaAwAAAEAQABpDAAAAQAyAGsMAAABACUAagwAAAEAPQDqDAAAAgBOAAMAAwn4DiWGAJEAA2oMAAABACsAbQwAAAEAHQDqDAAAAQApAAAA.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAkJKQABAMohAA==.',
No='Noeyednuck:BAEALgAECgcJEQABLgAFFAMJDgAZAKsSAA==.',
Nu='Nuckshott:BAECLgAFFH8OAAIZAAMJqxLLXgDnAANoDAAABgA2AGkMAAADAB0A6gwAAAUAOwAZAAMJqxLLXgDnAANoDAAABgA2AGkMAAADAB0A6gwAAAUAOwAuAAQKfzQAAhkACQnWHwIaAIkCABkACQnWHwIaAIkCAAAA.',
Og='Ogx:BAEBLgAECn8WAAQbAAUJnh1zVwBZAQVoDAAABgBhAGkMAAAFADwAawwAAAUATgBqDAAAAQBGAOoMAAAFAEgAGwAECSUec1cAWQEEaAwAAAMAYQBpDAAAAgA8AGsMAAACAE4A6gwAAAIASAACAAQJURTJHwD6AARoDAAAAgBAAGkMAAACADUAawwAAAIAMgDqDAAAAgAnABwABQlxEFp2AIoABWgMAAABACMAaQwAAAEAIABrDAAAAQAjAGoMAAABADAA6gwAAAEAQAABLgAECgkJMgAEAAwbAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECgkJNAAdAGUjAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJMgAEAAwbAA==.',
Qu='Quindrox:BAEBLgAECn8aAAIWAAkJRSGiBQAFAwloDAAAAgBdAGkMAAACAFMAawwAAAMAVgBqDAAAAwBTAGwMAAADAFoAbQwAAAMATADqDAAABABQAG4MAAADAFoAbwwAAAMATwAWAAkJRSGiBQAFAwloDAAAAgBdAGkMAAACAFMAawwAAAMAVgBqDAAAAwBTAGwMAAADAFoAbQwAAAMATADqDAAABABQAG4MAAADAFoAbwwAAAMATwABLgAFFAMJCAAeAIMZAA==.Quinet:BAEBLgAECn80AAMdAAkJZSP6CwDuAgloDAAABwBhAGkMAAAHAFwAawwAAAcAXABqDAAABwBRAGwMAAAGAFwAbQwAAAQAWADqDAAABwBeAG4MAAAFAEcAbwwAAAIAYAAdAAkJZSP6CwDuAgloDAAABwBhAGkMAAAGAFwAawwAAAcAXABqDAAAAQAQAGwMAAAEAFwAbQwAAAQAWADqDAAABwBeAG4MAAAFAEcAbwwAAAIAYAAfAAMJyh5xLwD9AANpDAAAAQBGAGoMAAAGAFEAbAwAAAIAVwAAAA==.Quinman:BAEBLgAECn8aAAQPAAkJRRoQFAAFAgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgAPAAkJixcQFAAFAgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAaAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABkAAQkVGNgnAToAAWgMAAABAD0AAS4ABRQDCQgAHgCDGQA=.Quinmanbear:BAEBLgAFFH8IAAMeAAMJgxndFQDTAANoDAAAAgA8AGkMAAACAEIA6gwAAAQARAAeAAMJgxndFQDTAANoDAAAAgA8AGkMAAACAEIA6gwAAAMARAAUAAEJeguOIAA4AAHqDAAAAQAdAAAA.Quinroxx:BAEBLgAECn8gAAIGAAgJXiN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0ABgAICV4jfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAUUAwkIAB4AgxkA.Quinvinvin:BAEALgAECgcJDQABLgAFFAMJCAAeAIMZAA==.',
Ra='Ragsnak:BAEALgAECgkJEwABLgAECgkJMgAEAAwbAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8NAAIgAAMJJQzpHAC7AANoDAAABgA2AGkMAAAEABMA6gwAAAMAEwAgAAMJJQzpHAC7AANoDAAABgA2AGkMAAAEABMA6gwAAAMAEwAuAAQKfzQAAiAACQlsHtsAAHkCACAACQlsHtsAAHkCAAAA.',
Ry='Rytiou:BAECLgAFFH8aAAIWAAcJbRhXBQCuAQdoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAABABJAGwMAAABADUA6gwAAAcAUgBuDAAAAQAXABYABwltGFcFAK4BB2gMAAAEAFIAaQwAAAUAVgBrDAAABAAuAGoMAAAEAEkAbAwAAAEANQDqDAAABwBSAG4MAAABABcALgAECn8yAAIWAAkJ6iRZAgCMAwAWAAkJ6iRZAgCMAwAAAA==.',
Sa='Saadxevok:BAEBLgAECn8YAAMXAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAFwAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMABUABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAsAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwALAGQeAA==.Saadxp:BAECLgAFFH8jAAMLAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACwAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAhAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwsACAmRJrcDAGADAAsACAmRJrcDAGADACEABQkLHz4gAJEBAAAA.',
Se='Sendrys:BAEALgAECgEJAQABLgAECgkJNQACAAoaAA==.',
Sg='Sgtgigachad:BAEALgAECgUJBQABLgAFFAUJEgAIAAAAAQ==.',
Sp='Spilt:BAECLgAFFH85AAIGAAkJ+BivAQCMAgloDAAACQBaAGkMAAAJAFQAawwAAAcAPwBqDAAABwA0AGwMAAAFAEIAbQwAAAQARgDqDAAACgBTAG4MAAADACgAbwwAAAMACwAGAAkJ+BivAQCMAgloDAAACQBaAGkMAAAJAFQAawwAAAcAPwBqDAAABwA0AGwMAAAFAEIAbQwAAAQARgDqDAAACgBTAG4MAAADACgAbwwAAAMACwAuAAQKfx0AAgYACQnJJOMKAG0DAAYACQnJJOMKAG0DAAAA.Spilthen:BAEBLgAFFH8XAAIcAAkJBBLMAgASAgloDAAABABPAGkMAAAEAEQAawwAAAMAJwBqDAAAAgBIAGwMAAACADQAbQwAAAEACADqDAAABABLAG4MAAACACAAbwwAAAEADAAcAAkJBBLMAgASAgloDAAABABPAGkMAAAEAEQAawwAAAMAJwBqDAAAAgBIAGwMAAACADQAbQwAAAEACADqDAAABABLAG4MAAACACAAbwwAAAEADAABLgAFFAkJOQAGAPgYAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAkJOQAGAPgYAA==.',
Ta='Taku:BAEBLgAECn8UAAMiAAcJWBlKAQBaAQdoDAAAAwA7AGkMAAADAD8AawwAAAMAQgBqDAAAAwA+AGwMAAADAEUAbQwAAAIAMwDqDAAAAwBPACIABgkKGEoBAFoBBmgMAAACADsAaQwAAAIAPwBrDAAAAgA/AGoMAAACADUAbAwAAAIARQBtDAAAAgAzACMABgkzFbEoAA8BBmgMAAABADEAaQwAAAEAFwBrDAAAAQBCAGoMAAABAD4AbAwAAAEANADqDAAAAwBPAAEuAAQKCQkfABUA+AwA.Talakua:BAEALgAECgcJBwABLgAECgkJHwAVAPgMAA==.Taymeean:BAEALgAECgMJBAABLgAFFAQJBwAWAEAJAA==.Tayvok:BAECLgAFFH8HAAIWAAQJQAmzOwDYAARoDAAAAgAOAGkMAAADADAAawwAAAEAFgDqDAAAAQAJABYABAlACbM7ANgABGgMAAACAA4AaQwAAAMAMABrDAAAAQAWAOoMAAABAAkALgAECn8xAAMWAAkJkRyjDwBtAgAWAAkJkRyjDwBtAgAVAAIJ7AaTBQA+AAAAAA==.',
Te='Tentickles:BAECLgAFFH8NAAILAAQJlx/7EwBGAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABQA9AAsABAmXH/sTAEYBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAFAD0ALgAECn8UAAILAAgJiCJyCAD9AgALAAgJiCJyCAD9AgABLgAFFAkJKQABAMohAA==.',
Th='Thecheatt:BAECLgAFFH8JAAMNAAMJFSPLDgDRAANoDAAAAgBbAGkMAAACAFkA6gwAAAUAWAANAAMJZCLLDgDRAANoDAAAAgBbAGkMAAABAFMA6gwAAAUAWAAkAAEJyiKhDQBpAAFpDAAAAQBZAC4ABAp/OgADJAAJCfEjRQcAkQIAJAAJCd4jRQcAkQIADQAGCQge6kkAfQEAAAA=.Therelore:BAEALgAECgkJEwABLgAECgkJFAAOALgRAA==.',
Ty='Tyära:BAEBLgAECn8dAAMOAAgJTAtBuAAIAQhoDAAABgAYAGkMAAAGACQAawwAAAUAPgBqDAAAAwAXAGwMAAACAB4AbQwAAAEADQDqDAAABQAUAG4MAAABAA4ADgAHCUEJQbgACAEHaAwAAAUAEgBpDAAABQAZAGsMAAAEACYAagwAAAIAEwBsDAAAAQAeAOoMAAAEAA0AbgwAAAEADgAjAAcJtgqZMwDNAAdoDAAAAQAYAGkMAAABACQAawwAAAEAPgBqDAAAAQAXAGwMAAABAAcAbQwAAAEADQDqDAAAAQAUAAEuAAUUBAkVAAYAHQsA.',
Vi='Vilexie:BAEALgAECggJEwAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAAPAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zanea:BAEALgADCgkJEgABLgAECgkJNQACAAoaAA==.Zargan:BAEALgAECgcJCAABLgAECgkJHwAVAPgMAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAcJIQALAJ0fAA==.',
Zi='Zibbz:BAECLgAFFH8KAAIWAAQJIx6NIgBMAQRoDAAAAwBHAGkMAAADAFAAawwAAAEAVwDqDAAAAwBEABYABAkjHo0iAEwBBGgMAAADAEcAaQwAAAMAUABrDAAAAQBXAOoMAAADAEQALgAECn8/AAMWAAkJgiUjAgBdAwAWAAkJgiUjAgBdAwAXAAcJyxqmBwC/AQAAAA==.Zinia:BAEBLgAECn81AAICAAkJChqkBwBRAgloDAAACQBXAGkMAAAJAFIAawwAAAkAOQBqDAAABgA6AGwMAAAGAE8AbQwAAAMANwDqDAAABwBCAG4MAAADACsAbwwAAAEAPAACAAkJChqkBwBRAgloDAAACQBXAGkMAAAJAFIAawwAAAkAOQBqDAAABgA6AGwMAAAGAE8AbQwAAAMANwDqDAAABwBCAG4MAAADACsAbwwAAAEAPAAAAA==.',
Zo='Zoan:BAEALgAECgQJCAABLgAECgkJNAAdAGUjAA==.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAFFAQJCgAWACMeAA==.Zubbrael:BAEBLgAECn8sAAMLAAgJHhsNIADFAQhoDAAACQBUAGkMAAAHAEMAawwAAAYARQBqDAAABgBQAGwMAAAGAEMAbQwAAAEAUgDqDAAACABHAG4MAAABACoACwAHCUMaDSAAxQEHaAwAAAcAVABpDAAABQBDAGsMAAAEAEUAagwAAAQAUABsDAAABABDAOoMAAAGAEcAbgwAAAEAKgAhAAcJgwk+OAAyAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAUUBAkKABYAIx4A.Zubbz:BAECLgAFFH8GAAMgAAQJFxKvEgAOAQRoDAAAAwAqAGkMAAABAD0AawwAAAEAGADqDAAAAQA4ACAABAkXEq8SAA4BBGgMAAACACoAaQwAAAEAPQBrDAAAAQAYAOoMAAABADgAJQABCU8IuqIAOAABaAwAAAEAFQAuAAQKfzQAAyUACAkuH5MeAJoCACUACAksHpMeAJoCACAABwmWHvcSAAACAAEuAAUUBAkKABYAIx4A.Zubbzdh:BAEBLgAFFH8FAAMNAAMJfhH9NQDaAANoDAAAAgAsAGkMAAABACAA6gwAAAIAOQANAAMJ4A79NQDaAANoDAAAAgAsAGkMAAABACAA6gwAAAEAJQAkAAEJcBZZEQBDAAHqDAAAAQA5AAEuAAUUBAkKABYAIx4A.',
Zz='Zzertz:BAECLgAFFH8hAAILAAcJnR9XCADmAQdoDAAACABhAGkMAAAHAGIAawwAAAYAVABqDAAAAwBcAGwMAAABACcAbQwAAAEATgDqDAAABwBYAAsABwmdH1cIAOYBB2gMAAAIAGEAaQwAAAcAYgBrDAAABgBUAGoMAAADAFwAbAwAAAEAJwBtDAAAAQBOAOoMAAAHAFgALgAECn8rAAILAAgJ/yI6BgApAwALAAgJ/yI6BgApAwAAAA==.',
['Àb']='Àbeel:BAEALgAECgUJCAABLgAECgkJPAAKAE8cAA==.Àbel:BAEBLgAECn88AAMKAAkJTxxjBgASAgloDAAACgBXAGkMAAALAFQAawwAAAgAWgBqDAAABwBeAGwMAAAFAD0AbQwAAAIAIwDqDAAADABZAG4MAAAEAFkAbwwAAAEAKQAKAAcJKx5jBgASAgdoDAAACABXAGkMAAAJAFQAawwAAAUAWgBqDAAABQBeAGwMAAAFAD0A6gwAAAkAWQBuDAAAAgAyAAkACAnkGRsaAMgBCGgMAAACAEkAaQwAAAIATwBrDAAAAwBOAGoMAAACAF0AbQwAAAIAIwDqDAAAAwBBAG4MAAACAFkAbwwAAAEAKQAAAA==.Àble:BAEALgAECggJDQABLgAECgkJPAAKAE8cAA==.',
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
