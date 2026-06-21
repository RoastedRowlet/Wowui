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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Mage-Frost','Priest-Holy','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Arms','Warrior-Fury','DeathKnight-Unholy','Hunter-Survival','Mage-Arcane','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Druid-Guardian','Warlock-Destruction','Druid-Feral','DemonHunter-Havoc','Priest-Discipline','Warrior-Protection','DeathKnight-Blood','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-06-20',data={Ad='Adansso:BAEBLgAECn80AAIBAAkJFxKKHgC5AQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgABAAkJFxKKHgC5AQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgAAAA==.',
Al='Aliastei:BAEALgADCggJDAABLgAECgkJLwACALsZAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAYJFwADADQRAA==.',
As='Ashko:BAEBLgAECn8yAAMEAAgJDBvEOwAVAghoDAAACgBLAGkMAAAJAFcAawwAAAgAUQBqDAAABwBSAGwMAAAFAFEAbQwAAAMAKwDqDAAABgBHAG4MAAACACkABAAICQwbxDsAFQIIaAwAAAkASwBpDAAACABXAGsMAAAGAFEAagwAAAYAUgBsDAAABQBRAG0MAAADACsA6gwAAAUARwBuDAAAAgApAAUABQlwD7tMAAgBBWgMAAABACYAaQwAAAEAHQBrDAAAAgBPAGoMAAABABcA6gwAAAEAGwAAAA==.',
Ay='Ayodele:BAEBLgAECn84AAIGAAkJtBuEHgCmAgloDAAACQBSAGkMAAAHAEcAawwAAAUAQwBqDAAACABWAGwMAAAGAEkAbQwAAAQAPwDqDAAACABTAG4MAAAGAFYAbwwAAAMAJwAGAAkJtBuEHgCmAgloDAAACQBSAGkMAAAHAEcAawwAAAUAQwBqDAAACABWAGwMAAAGAEkAbQwAAAQAPwDqDAAACABTAG4MAAAGAFYAbwwAAAMAJwAAAA==.',
Az='Azurlia:BAEALgAFFAEJAQAAAA==.',
Ba='Babycora:BAEALgAFFAMJAwABLgAFFAQJEAAHACwhAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAIAAAAAA==.Barrui:BAECLgAFFH83AAMJAAkJhR88AACxAgloDAAACQBfAGkMAAAKAGAAawwAAAkAXABqDAAACQBgAGwMAAACAFkAbQwAAAIAJwDqDAAACgBdAG4MAAACAGEAbwwAAAIAKAAJAAkJ7R48AACxAgloDAAACQBfAGkMAAAJAFQAawwAAAgAXABqDAAACQBgAGwMAAABAFkAbQwAAAIAJwDqDAAACgBdAG4MAAACAGEAbwwAAAIAKAAKAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzkAAwkACQlwJOkFADMDAAkACQnxIukFADMDAAoABgkfIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8TAAILAAQJ4xpeEgBVAQRoDAAACABVAGkMAAAGAD4AawwAAAIAGwDqDAAAAwBjAAsABAnjGl4SAFUBBGgMAAAIAFUAaQwAAAYAPgBrDAAAAgAbAOoMAAADAGMALgAECn9AAAILAAkJoCE8BQACAwALAAkJoCE8BQACAwAAAA==.Bestiavera:BAEBLgAECn9AAAIMAAkJGhUHDgAJAgloDAAACgBFAGkMAAAJAE4AawwAAAkAOgBqDAAACAA8AGwMAAAIACUAbQwAAAQAOQDqDAAACAA+AG4MAAAHACsAbwwAAAEAGAAMAAkJGhUHDgAJAgloDAAACgBFAGkMAAAJAE4AawwAAAkAOgBqDAAACAA8AGwMAAAIACUAbQwAAAQAOQDqDAAACAA+AG4MAAAHACsAbwwAAAEAGAAAAA==.',
Br='Briggoker:BAEALgAECgQJBwAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgQJBwAIAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn8/AAINAAkJohh3FQBEAgloDAAACwBbAGkMAAAKAEcAawwAAAoAUgBqDAAACABYAGwMAAAIAEgAbQwAAAMALADqDAAABwBDAG4MAAAEADEAbwwAAAIAGQANAAkJohh3FQBEAgloDAAACwBbAGkMAAAKAEcAawwAAAoAUgBqDAAACABYAGwMAAAIAEgAbQwAAAMALADqDAAABwBDAG4MAAAEADEAbwwAAAIAGQAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAFFAMJBQANAKchAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8nAAMBAAkJQyA4AABxAgloDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABwBfAGwMAAAEAEQAbQwAAAEAJQDqDAAABwBhAG4MAAACAF0AbwwAAAEAXgABAAgJEiE4AABxAghoDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABwBfAG0MAAABACUA6gwAAAcAYQBuDAAAAgBdAG8MAAABAF4AAwABCSAKbV8AQgABbAwAAAQAGQAuAAQKfyoAAgEACAlxJgkCAIQDAAEACAlxJgkCAIQDAAAA.Daeke:BAEALgADCgUJBQABLgAECgQJBwAIAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEBLgAFFH8YAAIGAAUJbwt0CgDLAAVoDAAABwAuAGkMAAAHAB4AawwAAAMADwBqDAAAAQARAOoMAAAGABgABgAFCW8LdAoAywAFaAwAAAcALgBpDAAABwAeAGsMAAADAA8AagwAAAEAEQDqDAAABgAYAAEuAAUUCAkpAAsA1xoA.',
De='Deathbeaver:BAEALgAECgYJCwABLgAECgkJUwAEAF8eAA==.Destrom:BAEBLgAECn8UAAIOAAkJuBHUggBeAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAOAAkJuBHUggBeAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAAAA==.',
Di='Diozi:BAEALgADCgkJCQABLgAECggJLAAPAJUlAA==.',
Ep='Epilepticc:BAECLgAFFH8PAAIEAAQJSB7TOAA7AQRoDAAABQBCAGkMAAAEAFUAawwAAAMAUADqDAAAAwBNAAQABAlIHtM4ADsBBGgMAAAFAEIAaQwAAAQAVQBrDAAAAwBQAOoMAAADAE0ALgAECn88AAIEAAkJ6yL4GQCoAgAEAAkJ6yL4GQCoAgAAAA==.',
Et='Ethalon:BAECLgAFFH8TAAMFAAQJ1Bl/GgBNAQRoDAAABgBOAGkMAAAFAFoAawwAAAMAEwDqDAAABQBMAAUABAnUGX8aAE0BBGgMAAAFAE4AaQwAAAUAWgBrDAAAAwATAOoMAAAFAEwABAABCbcC6McAOQABaAwAAAEABgAuAAQKfyUAAwUACQkdGicYAFECAAUACQkdGicYAFECAAQAAgnJFDR7AUAAAAAA.',
Ga='Garlooth:BAECLgAFFH8NAAIQAAMJ5BY1AgDhAANoDAAABgAzAGkMAAAEAE4A6gwAAAMALQAQAAMJ5BY1AgDhAANoDAAABgAzAGkMAAAEAE4A6gwAAAMALQAuAAQKfzUAAhAACQkVJS8AAGIDABAACQkVJS8AAGIDAAAA.',
Gl='Glizzygary:BAEALgAFFAUJEgAAAQ==.',
Gr='Grimvalor:BAEBLgAECn9TAAMEAAkJXx7rHACXAgloDAAACwBcAGkMAAAKAEwAawwAAAsAUgBqDAAACQBYAGwMAAAKAFkAbQwAAAcASwDqDAAADABSAG4MAAAIAD0AbwwAAAUAPQAEAAkJXx7rHACXAgloDAAACgBcAGkMAAAKAEwAawwAAAoAUgBqDAAACABYAGwMAAAJAFkAbQwAAAcASwDqDAAACwBSAG4MAAAIAD0AbwwAAAUAPQARAAUJzwpYQABdAAVoDAAAAQAPAGsMAAABACwAagwAAAEALABsDAAAAQAiAOoMAAABAA8AAAA=.Grunclaws:BAEALgAECgcJEgABLgAECgkJMgAEAAwbAA==.Grunjo:BAEALgAECgkJDAABLgAECgkJMgAEAAwbAA==.Grunsy:BAEALgAECgcJBgABLgAECgkJMgAEAAwbAA==.',
Ha='Haf:BAEBLgAECn8qAAIRAAkJ8hELFQCAAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwARAAkJ8hELFQCAAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAYJFwADADQRAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Ka='Kautheros:BAEBLgAECn8eAAQSAAkJ+Ay+EQCuAQloDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABQBDAG4MAAACAB0AbwwAAAEAHwASAAkJ+Ay+EQCuAQloDAAAAgAIAGkMAAACABkAawwAAAIAOwBqDAAAAgAfAGwMAAABACIAbQwAAAMACQDqDAAABABDAG4MAAACAB0AbwwAAAEAHwATAAYJUglQXADFAAZoDAAAAQAdAGkMAAABABgAawwAAAIAHABqDAAAAQAkAGwMAAACABcA6gwAAAEADAAUAAMJmgaqIABOAANoDAAAAQAJAGkMAAABABgAagwAAAEAGgAAAA==.',
Ke='Kelo:BAEALgAECgkJBgABLgAECgkJMgAEAAwbAA==.',
Kr='Kroxychi:BAEALgAECgcJDgAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJDgAIAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8XAAIDAAYJNBEzIgBcAQZoDAAABgAqAGkMAAAGADoAawwAAAQALwBqDAAAAQAaAGwMAAABABYA6gwAAAUAQgADAAYJNBEzIgBcAQZoDAAABgAqAGkMAAAGADoAawwAAAQALwBqDAAAAQAaAGwMAAABABYA6gwAAAUAQgAuAAQKf3QABAMACQkWHsAKAKUCAAMACQkWHsAKAKUCAAEACQmYFBEYAPMBABUABAn/CG9aAKEAAAAA.',
Le='Lennather:BAEBLgAECn9DAAIBAAkJtCVvAQBkAwloDAAACABjAGkMAAAIAGEAawwAAAcAYABqDAAABwBOAGwMAAAJAGEAbQwAAAgAXgDqDAAACgBfAG4MAAAIAGMAbwwAAAIAWgABAAkJtCVvAQBkAwloDAAACABjAGkMAAAIAGEAawwAAAcAYABqDAAABwBOAGwMAAAJAGEAbQwAAAgAXgDqDAAACgBfAG4MAAAIAGMAbwwAAAIAWgAAAA==.',
Li='Lidomi:BAEALgAECgUJDAABLgAFFAQJCwASAP8PAA==.Lidrunka:BAECLgAFFH8FAAMVAAIJNRevQwCVAAJoDAAAAwAwAOoMAAACAEUAFQACCTUXr0MAlQACaAwAAAIAMADqDAAAAgBFAAEAAQkMAp4UAD0AAWgMAAABAAUALgAECn8YAAMBAAgJdBXVGwD9AQABAAgJ0BTVGwD9AQAVAAQJFhTFSgDSAAABLgAFFAQJCwASAP8PAA==.',
['Lé']='Lépewpew:BAEBLgAECn8YAAIPAAcJSRI+KABdAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKAA8ABwlJEj4oAF0BB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8lAAMWAAcJag++egBKAQdoDAAABgA9AGkMAAAGACUAawwAAAcAGgBqDAAABQA1AGwMAAADACYA6gwAAAcAKQBuDAAAAwAfABYABwlqD756AEoBB2gMAAAGAD0AaQwAAAUAJQBrDAAABgAaAGoMAAAEADUAbAwAAAMAJgDqDAAABgApAG4MAAADAB8AFwAECfkCtnAAfAAEaQwAAAEAAQBrDAAAAQAJAGoMAAABAAkA6gwAAAEADAAAAA==.',
['Má']='Mákí:BAEBLgAECn8kAAQBAAkJThUIIwCZAQloDAAABQBIAGkMAAAEADQAawwAAAUALwBqDAAABABIAGwMAAADAEEAbQwAAAEAFgDqDAAABwBQAG4MAAAFADUAbwwAAAIAKgABAAgJHRcIIwCZAQhoDAAABABIAGkMAAADADQAawwAAAQALwBqDAAAAgBIAGwMAAADAEEA6gwAAAQAUABuDAAABQA1AG8MAAACACoAFQAFCYIWFzwACwEFaAwAAAEAQABpDAAAAQAyAGsMAAABACUAagwAAAEAPQDqDAAAAgBOAAMAAwn4DiKGAJEAA2oMAAABACsAbQwAAAEAHQDqDAAAAQApAAAA.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAkJJwABAEMgAA==.',
No='Noeyednuck:BAEALgAECgcJEQABLgAFFAMJDQAWAKsSAA==.',
Nu='Nuckshott:BAECLgAFFH8NAAIWAAMJqxLMXgDnAANoDAAABgA2AGkMAAADAB0A6gwAAAQAOwAWAAMJqxLMXgDnAANoDAAABgA2AGkMAAADAB0A6gwAAAQAOwAuAAQKfzQAAhYACQnWHwMaAIkCABYACQnWHwMaAIkCAAAA.',
Og='Ogx:BAEBLgAECn8VAAQYAAUJnh1uVwBZAQVoDAAABgBhAGkMAAAFADwAawwAAAUATgBqDAAAAQBGAOoMAAAEAEgAGAAECSUeblcAWQEEaAwAAAMAYQBpDAAAAgA8AGsMAAACAE4A6gwAAAIASAACAAQJURTJHwD6AARoDAAAAgBAAGkMAAACADUAawwAAAIAMgDqDAAAAgAnABkABAl9DVd2AIoABGgMAAABACMAaQwAAAEAIABrDAAAAQAjAGoMAAABADAAAS4ABAoJCTIABAAMGwA=.',
Ol='Olgass:BAEALgADCgIJAgABLgAECgkJNAAaAGUjAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJMgAEAAwbAA==.',
Qu='Quindrox:BAEBLgAECn8aAAITAAkJRSGiBQAFAwloDAAAAgBdAGkMAAACAFMAawwAAAMAVgBqDAAAAwBTAGwMAAADAFoAbQwAAAMATADqDAAABABQAG4MAAADAFoAbwwAAAMATwATAAkJRSGiBQAFAwloDAAAAgBdAGkMAAACAFMAawwAAAMAVgBqDAAAAwBTAGwMAAADAFoAbQwAAAMATADqDAAABABQAG4MAAADAFoAbwwAAAMATwABLgAFFAMJBgAbAB0YAA==.Quinet:BAEBLgAECn80AAMaAAkJZSP6CwDuAgloDAAABwBhAGkMAAAHAFwAawwAAAcAXABqDAAABwBRAGwMAAAGAFwAbQwAAAQAWADqDAAABwBeAG4MAAAFAEcAbwwAAAIAYAAaAAkJZSP6CwDuAgloDAAABwBhAGkMAAAGAFwAawwAAAcAXABqDAAAAQAQAGwMAAAEAFwAbQwAAAQAWADqDAAABwBeAG4MAAAFAEcAbwwAAAIAYAAcAAMJyh5xLwD9AANpDAAAAQBGAGoMAAAGAFEAbAwAAAIAVwAAAA==.Quinman:BAEBLgAECn8aAAQPAAkJRRoSFAAFAgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgAPAAkJixcSFAAFAgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAXAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABYAAQkVGNMnAToAAWgMAAABAD0AAS4ABRQDCQYAGwAdGAA=.Quinmanbear:BAEBLgAFFH8GAAMbAAMJHRjcFQDTAANoDAAAAgA8AGkMAAACAEIA6gwAAAIAOgAbAAMJHRjcFQDTAANoDAAAAgA8AGkMAAACAEIA6gwAAAEAOgAdAAEJeguMIAA4AAHqDAAAAQAdAAAA.Quinroxx:BAEBLgAECn8gAAIGAAgJXiN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0ABgAICV4jfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAUUAwkGABsAHRgA.Quinvinvin:BAEALgAECgcJDQABLgAFFAMJBgAbAB0YAA==.',
Ra='Ragsnak:BAEALgAECgkJEQABLgAECgkJMgAEAAwbAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8NAAIeAAMJJQzlHAC7AANoDAAABgA2AGkMAAAEABMA6gwAAAMAEwAeAAMJJQzlHAC7AANoDAAABgA2AGkMAAAEABMA6gwAAAMAEwAuAAQKfzQAAh4ACQlsHj8AAH8CAB4ACQlsHj8AAH8CAAAA.',
Ry='Rytiou:BAECLgAFFH8ZAAITAAcJbRhXBQCuAQdoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAABABJAGwMAAABADUA6gwAAAYAUgBuDAAAAQAXABMABwltGFcFAK4BB2gMAAAEAFIAaQwAAAUAVgBrDAAABAAuAGoMAAAEAEkAbAwAAAEANQDqDAAABgBSAG4MAAABABcALgAECn8yAAITAAkJ6iRZAgCMAwATAAkJ6iRZAgCMAwAAAA==.',
Sa='Saadxevok:BAEBLgAECn8YAAMUAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAFAAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMABIABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAsAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwALAGQeAA==.Saadxp:BAECLgAFFH8jAAMLAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACwAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAfAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwsACAmRJrcDAGADAAsACAmRJrcDAGADAB8ABQkLHz4gAJEBAAAA.',
Se='Sendrys:BAEALgAECgEJAQABLgAECgkJLwACALsZAA==.',
Sg='Sgtgigachad:BAEALgAECgUJBQABLgAFFAUJEgAIAAAAAQ==.',
Sp='Spilt:BAECLgAFFH84AAIGAAkJ+BivAQCMAgloDAAACQBaAGkMAAAJAFQAawwAAAcAPwBqDAAABwA0AGwMAAAFAEIAbQwAAAMARgDqDAAACgBTAG4MAAADACgAbwwAAAMACwAGAAkJ+BivAQCMAgloDAAACQBaAGkMAAAJAFQAawwAAAcAPwBqDAAABwA0AGwMAAAFAEIAbQwAAAMARgDqDAAACgBTAG4MAAADACgAbwwAAAMACwAuAAQKfx0AAgYACQnJJOMKAG0DAAYACQnJJOMKAG0DAAAA.Spilthen:BAEBLgAFFH8TAAIZAAcJQBZoAQCLAQdoDAAABABPAGkMAAAEAEQAawwAAAMAJwBqDAAAAgBIAGwMAAABADQA6gwAAAQASwBuDAAAAQAZABkABwlAFmgBAIsBB2gMAAAEAE8AaQwAAAQARABrDAAAAwAnAGoMAAACAEgAbAwAAAEANADqDAAABABLAG4MAAABABkAAS4ABRQJCTgABgD4GAA=.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAkJOAAGAPgYAA==.',
Ta='Taku:BAEALgAECgcJDgABLgAECgkJHgASAPgMAA==.Taymeean:BAEALgAECgMJBAABLgAFFAQJBwATAEAJAA==.Tayvok:BAECLgAFFH8HAAITAAQJQAmxOwDYAARoDAAAAgAOAGkMAAADADAAawwAAAEAFgDqDAAAAQAJABMABAlACbE7ANgABGgMAAACAA4AaQwAAAMAMABrDAAAAQAWAOoMAAABAAkALgAECn8xAAMTAAkJkRylDwBtAgATAAkJkRylDwBtAgASAAIJ7AbsAQA+AAAAAA==.',
Te='Tentickles:BAECLgAFFH8NAAILAAQJlx/7EwBGAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABQA9AAsABAmXH/sTAEYBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAFAD0ALgAECn8UAAILAAgJiCJyCAD9AgALAAgJiCJyCAD9AgABLgAFFAkJJwABAEMgAA==.',
Th='Thecheatt:BAECLgAFFH8FAAINAAMJpyGKKQAPAQNoDAAAAQBWAGkMAAABAFMA6gwAAAMAWAANAAMJpyGKKQAPAQNoDAAAAQBWAGkMAAABAFMA6gwAAAMAWAAuAAQKfzoAAyAACQnxI0YHAJECACAACQneI0YHAJECAA0ABgkIHupJAH0BAAAA.Therelore:BAEALgAECgkJEwABLgAECgkJFAAOALgRAA==.',
Ty='Tyära:BAEBLgAECn8dAAMOAAgJTAs6uAAIAQhoDAAABgAYAGkMAAAGACQAawwAAAUAPgBqDAAAAwAXAGwMAAACAB4AbQwAAAEADQDqDAAABQAUAG4MAAABAA4ADgAHCUEJOrgACAEHaAwAAAUAEgBpDAAABQAZAGsMAAAEACYAagwAAAIAEwBsDAAAAQAeAOoMAAAEAA0AbgwAAAEADgAhAAcJtgqXMwDNAAdoDAAAAQAYAGkMAAABACQAawwAAAEAPgBqDAAAAQAXAGwMAAABAAcAbQwAAAEADQDqDAAAAQAUAAEuAAUUAwkPAAYA3g0A.',
Vi='Vilexie:BAEALgAECggJEwAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAAPAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zanea:BAEALgADCgkJEgABLgAECgkJLwACALsZAA==.Zargan:BAEALgAECgcJCAABLgAECgkJHgASAPgMAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAYJIAALANUfAA==.',
Zi='Zibbz:BAECLgAFFH8KAAITAAQJIx6OIgBMAQRoDAAAAwBHAGkMAAADAFAAawwAAAEAVwDqDAAAAwBEABMABAkjHo4iAEwBBGgMAAADAEcAaQwAAAMAUABrDAAAAQBXAOoMAAADAEQALgAECn8/AAMTAAkJgiUjAgBdAwATAAkJgiUjAgBdAwAUAAcJyxqmBwC/AQAAAA==.Zinia:BAEBLgAECn8vAAICAAkJuxmkBwBRAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAACAAkJuxmkBwBRAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAAAAA==.',
Zo='Zoan:BAEALgAECgQJCAABLgAECgkJNAAaAGUjAA==.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAFFAQJCgATACMeAA==.Zubbrael:BAEBLgAECn8sAAMLAAgJHhsNIADFAQhoDAAACQBUAGkMAAAHAEMAawwAAAYARQBqDAAABgBQAGwMAAAGAEMAbQwAAAEAUgDqDAAACABHAG4MAAABACoACwAHCUMaDSAAxQEHaAwAAAcAVABpDAAABQBDAGsMAAAEAEUAagwAAAQAUABsDAAABABDAOoMAAAGAEcAbgwAAAEAKgAfAAcJgwk/OAAyAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAUUBAkKABMAIx4A.Zubbz:BAECLgAFFH8FAAMeAAQJtxGtEgAOAQRoDAAAAgAmAGkMAAABAD0AawwAAAEAGADqDAAAAQA4AB4ABAm3Ea0SAA4BBGgMAAABACYAaQwAAAEAPQBrDAAAAQAYAOoMAAABADgAIgABCU8IuKIAOAABaAwAAAEAFQAuAAQKfzQAAyIACAkuH5MeAJoCACIACAksHpMeAJoCAB4ABwmWHvkSAAACAAEuAAUUBAkKABMAIx4A.Zubbzdh:BAEBLgAFFH8FAAMNAAMJfhECNgDaAANoDAAAAgAsAGkMAAABACAA6gwAAAIAOQANAAMJ4A4CNgDaAANoDAAAAgAsAGkMAAABACAA6gwAAAEAJQAgAAEJcBYaBQBJAAHqDAAAAQA5AAEuAAUUBAkKABMAIx4A.',
Zz='Zzertz:BAECLgAFFH8gAAILAAYJ1R9XCADmAQZoDAAACABhAGkMAAAHAGIAawwAAAYAVABqDAAAAwBcAGwMAAABACcA6gwAAAcAWAALAAYJ1R9XCADmAQZoDAAACABhAGkMAAAHAGIAawwAAAYAVABqDAAAAwBcAGwMAAABACcA6gwAAAcAWAAuAAQKfysAAgsACAn/IjoGACkDAAsACAn/IjoGACkDAAAA.',
['Àb']='Àbeel:BAEALgAECgUJBgABLgAECgkJPAAKAE8cAA==.Àbel:BAEBLgAECn88AAMKAAkJTxxjBgASAgloDAAACgBXAGkMAAALAFQAawwAAAgAWgBqDAAABwBeAGwMAAAFAD0AbQwAAAIAIwDqDAAADABZAG4MAAAEAFkAbwwAAAEAKQAKAAcJKx5jBgASAgdoDAAACABXAGkMAAAJAFQAawwAAAUAWgBqDAAABQBeAGwMAAAFAD0A6gwAAAkAWQBuDAAAAgAyAAkACAnkGRkaAMgBCGgMAAACAEkAaQwAAAIATwBrDAAAAwBOAGoMAAACAF0AbQwAAAIAIwDqDAAAAwBBAG4MAAACAFkAbwwAAAEAKQAAAA==.Àble:BAEALgAECggJDQABLgAECgkJPAAKAE8cAA==.',
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
