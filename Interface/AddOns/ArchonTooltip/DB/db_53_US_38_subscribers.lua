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

local lookup = {'Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Warrior-Protection','Mage-Frost','Druid-Restoration','Druid-Balance','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Priest-Holy','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Assassination','Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Hunter-Marksmanship','Rogue-Outlaw','Warrior-Arms','Warlock-Affliction','Shaman-Enhancement','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DemonHunter-Havoc','Hunter-BeastMastery','Mage-Arcane','Mage-Fire','Shaman-Restoration',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=53,date='2026-10-13',data={Ad='Addex:BAEBNQAECn8kAAQBAAkK6BWYQABgAgmODQAABwAyAHUNAAAEACIAfw0AAAQAJwCpDQAABAAyAFwNAAAEADEAXQ0AAAIASwBlDQAABgBRAKQNAAADAFEAMw0AAAIAKQABAAkK6BWYQABgAgmODQAAAwAyAHUNAAABACIAfw0AAAEAJwCpDQAAAQAyAFwNAAABADEAXQ0AAAEASwBlDQAABABRAKQNAAADAFEAMw0AAAIAKQACAAcKAhzJnQDhAQeODQAAAgA8AHUNAAABAFEAfw0AAAEANACpDQAAAQBUAFwNAAABAEUAXQ0AAAEAOQBlDQAAAgBLAAMABQqFHAY7ABQBBY4NAAACAFEAdQ0AAAIATAB/DQAAAgAzAKkNAAACAEcAXA0AAAIAPgABNQAFFAgIJwAEAI4kAA==.',
Am='Ambient:BAECNQAFFH8nAAIEAAgKjiTAAAAPAwiODQAABwBkAHUNAAAGAFsAfw0AAAUAWwCpDQAABgBZAFwNAAAFAFYAXQ0AAAQAXgBlDQAAAQBhADMNAAAFAGEABAAICo4kwAAADwMIjg0AAAcAZAB1DQAABgBbAH8NAAAFAFsAqQ0AAAYAWQBcDQAABQBWAF0NAAAEAF4AZQ0AAAEAYQAzDQAABQBhADUABAp/GwACBAAJCoQihA0AzQIABAAJCoQihA0AzQIAAAA=.',
Av='Avarat:BAECNQAFFH8UAAIFAAUKkB7HAQCoAQWODQAABQBLAHUNAAAEAEkAfw0AAAMANACpDQAABQBVADMNAAADAEMABQAFCpAexwEAqAEFjg0AAAUASwB1DQAABABJAH8NAAADADQAqQ0AAAUAVQAzDQAAAwBDADUABAp/HgACBQAJCnAdCgoAogIABQAJCnAdCgoAogIAATUABAoJCRUAAQA6FAA=.Avtrene:BAEANQADCgIJAgAAAA==.',
Ba='Banddaid:BAEANQAECgYIBwABNQAFFAQIDQAGAOoUAA==.Barkkobama:BAEBNQAECn8zAAQHAAkKpCQ6AwCUAwmODQAACABiAHUNAAAGAFsAfw0AAAYAYwCpDQAABwBhAFwNAAAFAGMAXQ0AAAUAYwBlDQAABQBWAKQNAAADAFQAMw0AAAYAVwAHAAkKpCQ6AwCUAwmODQAACABiAHUNAAADAFsAfw0AAAMAYwCpDQAABQBhAFwNAAACAGMAXQ0AAAMAYwBlDQAAAwBWAKQNAAADAFQAMw0AAAQAVwAIAAcKqCLOJgCaAgd1DQAAAgBfAH8NAAACAFsAqQ0AAAIAWgBcDQAAAwBhAF0NAAACAFsAZQ0AAAIARQAzDQAAAgBaAAkAAgqtI8A6ANEAAnUNAAABAFsAfw0AAAEAXwAAAA==.',
Bo='Boimilk:BAEANQAFFAQIBAABNQAFFAcIHAAKANUaAA==.',
Br='Brapcannon:BAECNQAFFH8MAAMEAAcK9wSCDgAYAQeODQAAAwAJAHUNAAABAAcAfw0AAAEABACpDQAABAAEAFwNAAABAAIAXQ0AAAEAOQAzDQAAAQADAAQABQpBAoIOABgBBY4NAAABAAkAdQ0AAAEABwB/DQAAAQAEAKkNAAABAAQAMw0AAAEAAwALAAQKKwh+BwAVAQSODQAAAgAzAKkNAAADAAwAXA0AAAEAAwBdDQAAAQAQADUABAp/HwADCwAJCjIQRRMAGAIACwAJCjIQRRMAGAIABAAHCrYJhykAYgEAAAA=.Briéè:BAEANQADCgEIAQAAAA==.Bruwon:BAECNQAFFH8WAAIMAAYKFh2FAQAGAgaODQAABABTAHUNAAADAFEAfw0AAAMASQCpDQAABABbAFwNAAACACkAMw0AAAYAWAAMAAYKFh2FAQAGAgaODQAABABTAHUNAAADAFEAfw0AAAMASQCpDQAABABbAFwNAAACACkAMw0AAAYAWAA1AAQKfyMAAgwACQqEJVICAIcDAAwACQqEJVICAIcDAAAA.',
Ch='Charzie:BAEANQAFFAEIAQABNQAFFAYIFgAMABYdAA==.',
Da='Danitsia:BAEBNQAECn8XAAINAAcKSwUqoQAsAQeODQAABQANAHUNAAAFAA4Afw0AAAQADQCpDQAABAAVAFwNAAACAAYAXQ0AAAEACAAzDQAAAgARAA0ABwpLBSqhACwBB44NAAAFAA0AdQ0AAAUADgB/DQAABAANAKkNAAAEABUAXA0AAAIABgBdDQAAAQAIADMNAAACABEAAAA=.',
De='Deathkleburg:BAEBNQAECn80AAQOAAkK7x9tEAAJAwmODQAABwBXAHUNAAAHAFsAfw0AAAcATwCpDQAABwBSAFwNAAAEAFUAXQ0AAAQARABlDQAABQBSAKQNAAAEAEgAMw0AAAcAUgAOAAkKlB9tEAAJAwmODQAABQBXAHUNAAADAFoAfw0AAAMATwCpDQAABQBSAFwNAAADAFUAXQ0AAAMARABlDQAAAwBNAKQNAAAEAEgAMw0AAAQARAAPAAcKFhhYTwDTAQeODQAAAgBAAHUNAAACAFsAfw0AAAIARwCpDQAAAgBBAFwNAAABAAQAZQ0AAAIAUgAzDQAAAgBSABAABAqOF/N4ABABBHUNAAACADgAfw0AAAIATgBdDQAAAQBAADMNAAABAEEAAAA=.Delacoûr:BAEANQAECgUICQABNQAFFAcIEQANAIsZAA==.Deleerious:BAEBNQAECn8fAAMRAAkKVR5+GgClAgmODQAABABaAHUNAAAEAF8Afw0AAAQARwCpDQAABABWAFwNAAAEAGAAXQ0AAAMAWQBlDQAAAgAeAKQNAAACADYAMw0AAAQAXQARAAkKVR5+GgClAgmODQAAAgBaAHUNAAACAF8Afw0AAAIARQCpDQAAAwBWAFwNAAADAGAAXQ0AAAMAWQBlDQAAAgAeAKQNAAACADYAMw0AAAIASAASAAYKyB3KJQCVAQaODQAAAgBKAHUNAAACAFsAfw0AAAIARwCpDQAAAQBDAFwNAAABAEcAMw0AAAIAXQAAAA==.',
Do='Doorstuck:BAEANQADCggICAABNQAECgkJFQABADoUAA==.',
El='Elfylicious:BAEANQAECgYIDQABNQAECgYICQATAAAAAA==.',
Fe='Fentweaver:BAECNQAFFH8bAAIUAAYKCSDjAQAkAgaODQAABgA/AHUNAAAFAFUAfw0AAAQAUACpDQAABgBMAFwNAAACAFYAMw0AAAQAYwAUAAYKCSDjAQAkAgaODQAABgA/AHUNAAAFAFUAfw0AAAQAUACpDQAABgBMAFwNAAACAFYAMw0AAAQAYwA1AAQKfy4AAhQACQqdIzYFAE0DABQACQqdIzYFAE0DAAAA.',
Gi='Ginebra:BAEANQADCggIFgAAAA==.',
Gj='Gjlo:BAEANQADCggICAABNQAFFAUICgAVABQfAA==.',
Gr='Gronknose:BAECNQAFFH8fAAMWAAcKMByPAAAPAgeODQAABgBcAHUNAAAGAEcAfw0AAAYANACpDQAABQBVAFwNAAADAEUAXQ0AAAIAKgAzDQAAAwBAABYABgogH48AAA8CBo4NAAAGAFwAdQ0AAAUARwB/DQAABgA0AKkNAAAFAFUAXA0AAAMARQAzDQAAAgA0ABEAAwqzFZwNABABA3UNAAABAEUAXQ0AAAIAKgAzDQAAAQBAADUABAp/LQAEFgAJCtYlIAEAiwMAFgAJCsskIAEAiwMAEQADCgYl4VoARQEAEgABClkVE00ASAAAAAA=.',
Ha='Hakdh:BAEANQAECgEIAQABNQAFFAcIIAADAK8QAA==.Hakdk:BAEANQAECgMICAABNQAFFAcIIAADAK8QAA==.Hakgek:BAEANQAECggIBAABNQAFFAcIIAADAK8QAA==.Hakmonk:BAEANQAECgEIAQABNQAFFAcIIAADAK8QAA==.Hakwar:BAEANQAECggICAABNQAFFAcIIAADAK8QAA==.',
He='Hekight:BAEANQAECggIDQABNQAECgkJHgACABkXAA==.',
Ho='Hobo:BAEANQADCgIIBQABNQAECggIIAAXAPAjAA==.Hoboomkin:BAEANQAECgYIEQABNQAECggIIAAXAPAjAA==.Hoborc:BAEBNQAECn8gAAMXAAgK8CO8JAAjAwiODQAABQBiAHUNAAAEAGAAfw0AAAQASQCpDQAABABcAFwNAAAEAGEAXQ0AAAQAXgBlDQAABABTAKQNAAADAFEAFwAICvAjvCQAIwMIjg0AAAQAYgB1DQAABABgAH8NAAAEAEkAqQ0AAAQAXABcDQAABABhAF0NAAAEAF4AZQ0AAAQAUwCkDQAAAwBRAAUAAQpCGgU9AEwAAY4NAAABAEMAAAA=.',
Hu='Hunterinnit:BAEANQADCgEIAQAAAA==.',
Ih='Ihateffxiv:BAEANQAECgcIDQABNQAFFAcIDAAEAPcEAA==.',
Im='Immolater:BAEANQAECggIAQABNQAFFAcIIAADAK8QAA==.',
In='Inaríus:BAEANQAECgcIDwAAAA==.',
Jw='Jwsmashfan:BAEBNQAECn8ZAAIXAAkKIxm8XQBwAgmODQAAAgA8AHUNAAACADAAfw0AAAIASQCpDQAAAgBGAFwNAAACAD0AXQ0AAAQAPwBlDQAABgBfAKQNAAAEADEAMw0AAAEAQQAXAAkKIxm8XQBwAgmODQAAAgA8AHUNAAACADAAfw0AAAIASQCpDQAAAgBGAFwNAAACAD0AXQ0AAAQAPwBlDQAABgBfAKQNAAAEADEAMw0AAAEAQQABNQAFFAcIHAAKANUaAA==.',
Ka='Kalevias:BAECNQAFFH8gAAIDAAcKrxADAwDeAQeODQAABwBKAHUNAAAGAA4Afw0AAAYAQACpDQAABgA+AFwNAAADABoAXQ0AAAIAIwAzDQAAAgAJAAMABwqvEAMDAN4BB44NAAAHAEoAdQ0AAAYADgB/DQAABgBAAKkNAAAGAD4AXA0AAAMAGgBdDQAAAgAjADMNAAACAAkANQAECn8oAAIDAAkKfxnlFwA3AgADAAkKfxnlFwA3AgAAAA==.',
Ki='Kirith:BAEBNQAECn8bAAIRAAcK4R8cIwBqAgeODQAABQBUAHUNAAAEAEkAfw0AAAMAVgCpDQAABQBfAFwNAAADAFAAZQ0AAAMATwCkDQAABABLABEABwrhHxwjAGoCB44NAAAFAFQAdQ0AAAQASQB/DQAAAwBWAKkNAAAFAF8AXA0AAAMAUABlDQAAAwBPAKQNAAAEAEsAAAA=.',
Le='Lewinskibidi:BAECNQAFFH8cAAIKAAcK1RoTAgA8AgeODQAABQBbAHUNAAAEAEUAfw0AAAMAOgCpDQAABwA9AFwNAAAEAEAAXQ0AAAMAOAAzDQAAAgAyAAoABwrVGhMCADwCB44NAAAFAFsAdQ0AAAQARQB/DQAAAwA6AKkNAAAHAD0AXA0AAAQAQABdDQAAAwA4ADMNAAACADIANQAECn8hAAIKAAkKZiOVAwDzAgAKAAkKZiOVAwDzAgAAAA==.',
Li='Lilsoup:BAEBNQAFFH8JAAINAAUK/AWSFABaAQWODQAAAwASAHUNAAACAAwAfw0AAAEACQCpDQAAAgASADMNAAABABIADQAFCvwFkhQAWgEFjg0AAAMAEgB1DQAAAgAMAH8NAAABAAkAqQ0AAAIAEgAzDQAAAQASAAAA.',
Ma='Madtheaug:BAEANQAECgcICAABNQAFFAkKKgAYAIcjAA==.Mangofart:BAEBNQAECn80AAIZAAkKrx/iCADnAgmODQAACgBfAHUNAAAHAFAAfw0AAAcAUACpDQAACABQAFwNAAAFAE4AXQ0AAAQASQBlDQAABABQAKQNAAADAE8AMw0AAAQAQQAZAAkKrx/iCADnAgmODQAACgBfAHUNAAAHAFAAfw0AAAcAUACpDQAACABQAFwNAAAFAE4AXQ0AAAQASQBlDQAABABQAKQNAAADAE8AMw0AAAQAQQAAAA==.Mattchstep:BAEANQAECggICAABNQAFFAcIHAAKANUaAA==.',
Mi='Minbä:BAECNQAFFH8FAAIaAAIKUBalIACoAAKODQAABAAwAKkNAAABAEEAGgACClAWpSAAqAACjg0AAAQAMACpDQAAAQBBADUABAp/MAACGgAJCloktAQAxQMAGgAJCloktAQAxQMAATUABRQHCBMAGwAAFAA=.Miniss:BAECNQAFFH8TAAMbAAcKABTQCADeAQeODQAABABSAHUNAAADADMAfw0AAAMAJQCpDQAAAgBDAFwNAAACACUAXQ0AAAEAEAAzDQAABAA7ABsABgoCFNAIAN4BBo4NAAADAFIAfw0AAAMAJQCpDQAAAgBDAFwNAAACACUAXQ0AAAEAEAAzDQAABAA7ABwAAgpmEOYPAJYAAo4NAAABACAAdQ0AAAMAMwA1AAQKf0EABBgACQqbItcDAK0CABsACQpwIiwbABcDABgABwqlHtcDAK0CABwABwpzHyYOABYCAAAA.',
Mo='Mobes:BAEBNQAECn8oAAMJAAkK1BRdEABVAgmODQAACABMAHUNAAAGAEcAfw0AAAYAPgCpDQAABAAjAFwNAAADACoAXQ0AAAIAJwBlDQAABAA7AKQNAAACADEAMw0AAAUAUwAJAAkK1BRdEABVAgmODQAABwBMAHUNAAAFAEcAfw0AAAUAPgCpDQAABAAjAFwNAAADACoAXQ0AAAIAJwBlDQAABAA7AKQNAAABADEAMw0AAAUAUwAdAAQKrg9kJwDPAASODQAAAQAkAHUNAAABADkAfw0AAAEAGACkDQAAAQAZAAAA.Moosclemommy:BAEBNQAFFH8VAAIMAAYKRBkIAgDgAQaODQAABQA/AHUNAAAEAEEAfw0AAAMAQgCpDQAABQBKAFwNAAABADYAMw0AAAMASQAMAAYKRBkIAgDgAQaODQAABQA/AHUNAAAEAEEAfw0AAAMAQgCpDQAABQBKAFwNAAABADYAMw0AAAMASQABNQAECgkJFQABADoUAA==.Mowrii:BAEANQADCgYIBgABNQAECgkJJQAeAOshAA==.',
Ni='Niniane:BAECNQAFFH8WAAMfAAYKUR3KCAC3AQaODQAABQBLAHUNAAAFAEMAfw0AAAIAFACpDQAABgBZAFwNAAACAEIAMw0AAAIAPAAfAAUK3xzKCAC3AQWODQAAAQBLAHUNAAABAD8AqQ0AAAQAWQBcDQAAAgBCADMNAAACADwAFQAECkEW8hAAKQEEjg0AAAQAPwB1DQAABABDAH8NAAACABQAqQ0AAAIAJwA1AAQKfyoAAx8ACQpRJX4PAGYDAB8ACQpRJX4PAGYDABUAAgqDEuNnAIgAAAAA.',
No='Noradk:BAEANQAECgYIEgABNQAFFAQIBwADAKEXAA==.Noralisa:BAECNQAFFH8HAAIDAAQKoRd0BgAfAQSODQAAAwA/AHUNAAABAC8AqQ0AAAIARwAzDQAAAQArAAMABAqhF3QGAB8BBI4NAAADAD8AdQ0AAAEALwCpDQAAAgBHADMNAAABACsANQAECn8jAAIDAAkKKiK8CQD/AgADAAkKKiK8CQD/AgAAAA==.Noreleasa:BAEANQADCgUIBgABNQAFFAQIBwADAKEXAA==.Notspidee:BAEANQADCgYIBgABNQAECgUIAgATAAAAAA==.Novelus:BAEBNQAFFH8LAAIFAAUKniMfAQDwAQWODQAAAwBaAHUNAAACAFYAfw0AAAIAWACpDQAAAwBgADMNAAABAFAABQAFCp4jHwEA8AEFjg0AAAMAWgB1DQAAAgBWAH8NAAACAFgAqQ0AAAMAYAAzDQAAAQBQAAAA.',
Ol='Oldbronze:BAEBNQAECn89AAIFAAkKGCaIAADoAwmODQAACwBiAHUNAAAJAGIAfw0AAAgAYwCpDQAACABiAFwNAAAHAGEAXQ0AAAQAYQBlDQAABQBfAKQNAAADAGEAMw0AAAYAYQAFAAkKGCaIAADoAwmODQAACwBiAHUNAAAJAGIAfw0AAAgAYwCpDQAACABiAFwNAAAHAGEAXQ0AAAQAYQBlDQAABQBfAKQNAAADAGEAMw0AAAYAYQAAAA==.',
Pa='Parkercannon:BAEANQAECgEIAQABNQAFFAcIHAAKANUaAA==.Patrennessy:BAEANQAECgEJAQABNQAFFAcIHwAWADAcAA==.',
Ra='Ramsama:BAEANQADCggICAABNQAFFAUICQAIAIQQAA==.Ramsw:BAECNQAFFH8aAAIXAAcKQSX9AQDcAgeODQAABgBgAHUNAAAEAGIAfw0AAAQAUgCpDQAABABhAFwNAAACAFkAXQ0AAAIAXgAzDQAABABhABcABwpBJf0BANwCB44NAAAGAGAAdQ0AAAQAYgB/DQAABABSAKkNAAAEAGEAXA0AAAIAWQBdDQAAAgBeADMNAAAEAGEANQAECn8jAAIXAAkKISWPFwBZAwAXAAkKISWPFwBZAwAAAA==.',
Re='Recursively:BAECNQAFFH8PAAQcAAcKjQ4WBADWAAeODQAAAQAKAHUNAAADABcAfw0AAAIAKwCpDQAAAwA7AF0NAAABAD4AZQ0AAAEAHgAzDQAABABCABsAAwqzEbsjAOMAA38NAAACACsAqQ0AAAEAHABdDQAAAQA+ABwAAwogDBYEANYAA44NAAABAAoAdQ0AAAMAFwCpDQAAAgA7ABgAAgryCyoEAKoAAmUNAAABAB4AMw0AAAQAQgA1AAQKfzsAAxsACQrkJSoiAPgCABsABwr0JSoiAPgCABwABwr0F44NAB8CAAAA.Resika:BAECNQAFFH8JAAIIAAUKhBA8DgCAAQWODQAAAQA4AHUNAAACAB4AqQ0AAAIAPgBcDQAAAQATADMNAAADACIACAAFCoQQPA4AgAEFjg0AAAEAOAB1DQAAAgAeAKkNAAACAD4AXA0AAAEAEwAzDQAAAwAiADUABAp/MwACCAAJChAeAhcADQMACAAJChAeAhcADQMAAAA=.Retaholics:BAEANQADCggIDgAAAA==.',
Ru='Ruwon:BAEANQAECgUIBwABNQAFFAYIFgAMABYdAA==.Ruwondk:BAEBNQAECn8mAAIQAAkKMCEgDABQAwmODQAABgBfAHUNAAAEAF8Afw0AAAUAWQCpDQAABQBeAFwNAAAEAGEAXQ0AAAMAMABlDQAAAwBRAKQNAAACAFEAMw0AAAYAXwAQAAkKMCEgDABQAwmODQAABgBfAHUNAAAEAF8Afw0AAAUAWQCpDQAABQBeAFwNAAAEAGEAXQ0AAAMAMABlDQAAAwBRAKQNAAACAFEAMw0AAAYAXwABNQAFFAYIFgAMABYdAA==.',
Sa='Sascya:BAEANQAECgEIAQABNQAFFAcIIAADAK8QAA==.',
Sh='Shadythicc:BAEANQAECgQIBAABNQAECggICAATAAAAAA==.Sharrq:BAECNQAFFH8KAAIgAAUKGhgjGwCdAQWODQAAAwA5AHUNAAACAEoAfw0AAAEAUgCpDQAAAwA0ADMNAAABACIAIAAFChoYIxsAnQEFjg0AAAMAOQB1DQAAAgBKAH8NAAABAFIAqQ0AAAMANAAzDQAAAQAiADUABAp/KQAEIAAJCowgUjkAFQMAIAAJCl8fUjkAFQMAIQAHCiMZEgMA4QEABgAFCkwW7RcAOAEAAAA=.',
Si='Silversoph:BAEANQADCgQIBAAAAA==.',
Sl='Slimelight:BAEANQAECgQIBgAAAA==.',
St='Stuu:BAECNQAFFH8XAAIQAAYK7CEFBAA/AgaODQAABQBbAHUNAAAEAFIAfw0AAAQASwCpDQAABQBfAFwNAAADAE0AMw0AAAIAYwAQAAYK7CEFBAA/AgaODQAABQBbAHUNAAAEAFIAfw0AAAQASwCpDQAABQBfAFwNAAADAE0AMw0AAAIAYwA1AAQKfyEAAxAACQpAJnkIAHcDABAACQpAJnkIAHcDAA8AAgpcB5XLAFEAAAE1AAQKBwgHABMAAAAA.Stuwy:BAEANQAECgcIBwAAAA==.',
Te='Tendiarii:BAEANQADCggIGwAAAA==.',
Th='Thanala:BAECNQAFFH8QAAIBAAYKVhZbBgAEAgaODQAABABTAHUNAAADAB0Afw0AAAMAIwCpDQAAAwA7AFwNAAABADUAMw0AAAIAUQABAAYKVhZbBgAEAgaODQAABABTAHUNAAADAB0Afw0AAAMAIwCpDQAAAwA7AFwNAAABADUAMw0AAAIAUQA1AAQKfxkAAgEACQqGGBozAJYCAAEACQqGGBozAJYCAAAA.Thejigglr:BAECNQAFFH8MAAIaAAQKUQU9FQAfAQR1DQAAAQAIAH8NAAADABMAqQ0AAAMAEgAzDQAABQAdABoABApRBT0VAB8BBHUNAAABAAgAfw0AAAMAEwCpDQAAAwASADMNAAAFAB0ANQAECn8jAAIaAAkKUBsgNwCXAgAaAAkKUBsgNwCXAgAAAA==.',
Wo='Wormdropper:BAEBNQAECn8bAAMiAAYKYhh5gACGAQaODQAABAA2AHUNAAAEAFgAfw0AAAUASACpDQAABQAvAFwNAAAEADQAMw0AAAUAOwAiAAYKYhh5gACGAQaODQAAAwA2AHUNAAADAFgAfw0AAAUASACpDQAABAAvAFwNAAAEADQAMw0AAAQAOwAaAAQKvARm8gCqAASODQAAAQAOAHUNAAABAAkAqQ0AAAEACwAzDQAAAQANAAAA.Wormite:BAEANQAECgQIBQABNQAECgYIGwAiAGIYAA==.',
Xm='Xmal:BAEANQAECgQIBAABNQAECgkJJQAeAOshAA==.',
Yu='Yukirippurr:BAEBNQAECn8kAAMdAAYKbA+9IgD2AAaODQAABgAmAHUNAAAGAC0Afw0AAAYARwCpDQAABwAqAFwNAAAFAB8AMw0AAAYAOQAIAAYKMA8tXQBYAQaODQAABQAmAHUNAAAGAC0Afw0AAAUARwCpDQAABwAqAFwNAAAEAB0AMw0AAAUAHgAdAAQKDQq9IgD2AASODQAAAQATAH8NAAABAEMAXA0AAAEAHwAzDQAAAQA5AAAA.',
Zd='Zdeath:BAEANQADCgYIBgABNQAECgkJNAAZAK8fAA==.',
Ze='Zemonn:BAEANQADCggICQABNQAECgkJNAAZAK8fAA==.',
Zu='Zuri:BAEANQAECggIEgABNQAFFAYIFgAMABYdAA==.',
['Çb']='Çbk:BAECNQAFFH8UAAQbAAcKCiEDAgCBAgeODQAAAgBjAHUNAAAEAFsAfw0AAAMAUgCpDQAABABRAFwNAAACAFMAXQ0AAAEAQgAzDQAABABhABsABwrMHQMCAIECB44NAAACAGMAdQ0AAAEAMgB/DQAAAwBSAKkNAAADAFEAXA0AAAEAUwBdDQAAAQBCADMNAAABAFIAGAACCkUgzwIA0wACXA0AAAEAUgAzDQAAAwBhABwAAgqlHKsIAK8AAnUNAAADAFsAqQ0AAAEANwA1AAQKfzUABBsACQrZJQgXACoDABsACAqAJQgXACoDABgABQp6IwcKANoBABwABgqAHwsUAM4BAAAA.',
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
