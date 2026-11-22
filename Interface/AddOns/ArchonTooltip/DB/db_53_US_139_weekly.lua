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

local lookup = {'Paladin-Retribution','Priest-Holy','Priest-Shadow','Priest-Discipline','Rogue-Assassination','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','Mage-Arcane','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Holy','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Druid-Balance','Druid-Guardian','Warlock-Affliction','Paladin-Protection','Shaman-Elemental','Monk-Mistweaver','DemonHunter-Devourer','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Druid-Restoration',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Achannara:BAABNQAECn81AAIBAAkK+gWK3QAhAQABAAkK+gWK3QAhAQAAAA==.',
Ae='Aeloria:BAAANQADCgIIAgAAAA==.Aeoliana:BAABNQAECn8lAAICAAoKmRMcVwDgAQACAAoKmRMcVwDgAQAAAA==.',
Aj='Ajier:BAACNQAFFH8SAAICAAUK2g6IEgB5AQACAAUK2g6IEgB5AQA1AAQKf0wAAgIACgqcGflFACACAAIACgqcGflFACACAAAA.',
Al='Alaaris:BAAANQAECgEIAgAAAA==.Allcapwne:BAAANQADCggIIAAAAA==.Alucart:BAABNQAECn8oAAMDAAoKyg7LGgDEAQADAAoKyg7LGgDEAQAEAAEK2g6MGwAtAAAAAA==.',
An='Angela:BAABNQAECn8uAAICAAoKdBvCOACFAgACAAoKdBvCOACFAgAAAA==.Annadanna:BAAANQAECgUIEAAAAA==.Annalunà:BAAANQAECgMIBQAAAA==.Anogrips:BAAANQADCgYIBgAAAA==.Anoheals:BAAANQADCggIAgAAAA==.Anowars:BAAANQAECgUICAAAAA==.Antithicus:BAAANQADCgYIBgAAAA==.',
Ap='Apeople:BAACNQAFFH8GAAIFAAIKEBRdDACRAAAFAAIKEBRdDACRAAA1AAQKfzsAAgUACgo6HzAHAIgCAAUACgo6HzAHAIgCAAAA.Apocalýpsè:BAABNQAECn8gAAIGAAkKqxXvDQDdAQAGAAkKqxXvDQDdAQAAAA==.Applebottum:BAABNQAECn8hAAIBAAkKlQ4qrQB1AQABAAkKlQ4qrQB1AQAAAA==.Applebottumj:BAAANQAECgQICAAAAA==.Appärition:BAABNQAECn9AAAMHAAoKmhtLEgDiAQAIAAoK/RmsNwAyAgAHAAYK/hdLEgDiAQAAAA==.',
Ar='Archillius:BAAANQADCgUIBQAAAA==.Arondael:BAABNQAECn83AAIFAAoKwhLBDAAAAgAFAAoKwhLBDAAAAgAAAA==.',
As='Ashelaandrii:BAACNQAFFH8FAAIJAAIKpiCeHACxAAAJAAIKpiCeHACxAAA1AAQKfyMAAgkACQo2I54QAEADAAkACQo2I54QAEADAAAA.Astroglyde:BAAANQAECgUICwAAAA==.Astryd:BAABNQAECn8dAAMKAAkKTggQGQDRAAAKAAkKTggQGQDRAAALAAEKAABSnQAAAAABNQAECgkJKQAMABMIAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAABNQAECn9FAAINAAoKBg2hawDbAQANAAoKBg2hawDbAQAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùvina:BAAANQADCgIJAgAAAA==.',
Ba='Badru:BAAANQAECgMIAwAAAA==.Bagmaster:BAACNQAFFH8IAAICAAQK2BUUGgAlAQACAAQK2BUUGgAlAQA1AAQKfzwAAgIACgp4JegGAI4DAAIACgp4JegGAI4DAAAA.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAABNQAECn8hAAIJAAoK8Rj1OwBvAgAJAAoK8Rj1OwBvAgAAAA==.Barie:BAAANQAECgQIAwABNQAECgoKLAALAO0eAA==.Barthallomew:BAAANQAECgQIBAABNQAECgYIBAAOAAAAAA==.Bayonetta:BAABNQAECn83AAIPAAoK0xkFUQArAgAPAAoK0xkFUQArAgAAAA==.',
Be='Bellann:BAAANQAECgUICwAAAA==.',
Bi='Birghid:BAAANQABCgYIBgAAAA==.Birgite:BAABNQAECn8dAAIQAAcKQAqINgDJAAAQAAcKQAqINgDJAAAAAA==.',
Bl='Blackdracula:BAAANQAECgUIBgAAAA==.Blasphemar:BAAANQADCggIEAAAAA==.Blazefury:BAAANQAECgQIBwAAAA==.Blazeknight:BAABNQAECn9DAAMLAAoKQBmpJgDXAQALAAoKQBmpJgDXAQAKAAIKqAqfMAAsAAAAAA==.Blazemaker:BAABNQAECn8zAAIRAAoKCxV/CgAgAgARAAoKCxV/CgAgAgAAAA==.Blazemaster:BAAANQAECgYICQAAAA==.Bleach:BAAANQABCgQIBAAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.Bloodsylf:BAAANQADCgcICgABNQAECgkJFwASAMoSAA==.Blówpop:BAAANQADCgMIAwAAAA==.',
Bo='Bonecrushers:BAABNQAECn8sAAIPAAkK6ws/mACEAQAPAAkK6ws/mACEAQAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAABNQAECn8sAAITAAoKVhsAIAC+AgATAAoKVhsAIAC+AgAAAA==.Books:BAAANQAFFAEIAQABNQAECgoKLAATAFYbAA==.',
Br='Brainbread:BAABNQAECn8dAAIUAAgKVgyXrgAdAQAUAAgKVgyXrgAdAQABNQAECgoKSQAIAMUYAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAABNQAECn8dAAIRAAoKjxfrBgBUAgARAAoKjxfrBgBUAgAAAA==.Broadside:BAABNQAECn8eAAIPAAoKbiGmIAC9AgAPAAoKbiGmIAC9AgAAAA==.Brokil:BAAANQAECgYICwAAAA==.Brolymorph:BAACNQAFFH8KAAINAAUKdg7ZNQDtAAANAAUKdg7ZNQDtAAA1AAQKfy4AAg0ACgoyHrtIADMCAA0ACgoyHrtIADMCAAAA.Brossiere:BAAANQADCgQIBAAAAA==.Brotemic:BAAANQAECgIIAgAAAA==.Broverheal:BAAANQAECgMIBwAAAA==.Bru:BAACNQAFFH8IAAICAAUKNA+DFQBaAQACAAUKNA+DFQBaAQA1AAQKfysAAgIACgqMFEheAAYCAAIACgqMFEheAAYCAAAA.',
Bt='Bt:BAAANQADCgYIBgAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAABNQAECn8uAAQVAAoKiR2nGgAQAgAVAAkK3h2nGgAQAgAWAAIKSRXPjQB/AAAMAAEKMxuAkgBJAAAAAA==.Burninglight:BAAANQADCggIGQAAAA==.Burningtree:BAABNQAECn8ZAAMRAAoKmwxxFgBKAQARAAoKmwxxFgBKAQANAAQKNAe8fAHIAAAAAA==.Buthunter:BAAANQAECgUICQAAAA==.',
['Bâ']='Bâhtilâ:BAAANQAECggIBgAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECgoKbQAXAIEiAA==.',
Ca='Camamoonmana:BAAANQAECggIEwAAAA==.Canonbalizer:BAAANQAECgIIBAABNQAECggIIAAVAA0lAA==.Caplevi:BAABNQAECn9CAAQYAAoKLR7RKwBPAgAYAAoK4xzRKwBPAgAZAAYKThHYBABFAQAFAAYK5hnQKgDmAAAAAA==.Carrìon:BAAANQAECgYIBgAAAA==.Caskket:BAABNQAECn8aAAMMAAkK2hDLNgBqAQAMAAkK2hDLNgBqAQAVAAMKSgQ6uwB2AAAAAA==.Catdog:BAAANQADCgYIBgAAAA==.Catechism:BAABNQAECn8kAAITAAoKPxypGwDcAgATAAoKPxypGwDcAgAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAACNQAFFH8FAAILAAMKJRi8FACSAAALAAMKJRi8FACSAAA1AAQKfzkAAgsACgqnIe0QABkDAAsACgqnIe0QABkDAAAA.',
Ch='Chaningtotèm:BAAANQADCgUICgAAAA==.Charan:BAAANQADCgYIDgAAAA==.Chickennuggi:BAAANQADCgQIBwABNQAFFAYIEAAVAHAiAA==.Chiphoof:BAABNQAECn8dAAIaAAoK3RLiGgA4AQAaAAoK3RLiGgA4AQAAAA==.Chopndot:BAABNQAECn8XAAIMAAcK8AWuaACpAAAMAAcK8AWuaACpAAAAAA==.',
Cl='Clarabuns:BAABNQAECn8WAAMTAAkKmRryQgBZAgATAAgKphnyQgBZAgABAAIKaRBrbQFxAAAAAA==.Clawdragoon:BAECNQAFFH8GAAMbAAMKAxH/GgCUAAAbAAIKAxH/GgCUAAAcAAEKAAAdDgAAAAA1AAQKf0gAAxsACgoeHwMQAK8CABsACgoeHwMQAK8CABwACgoSEz8ZAL0BAAAA.',
Co='Corine:BAAANQADCgUIBgAAAA==.Corndogmatt:BAAANQADCgUICAAAAA==.',
Cr='Creatlach:BAACNQAFFH8ZAAIJAAgKBxqeBwDdAQAJAAgKBxqeBwDdAQA1AAQKfz8AAgkACgpiJDsNAFYDAAkACgpiJDsNAFYDAAAA.Creatlachtwo:BAAANQAECggIEQABNQAFFAgIGQAJAAcaAA==.Creeptoken:BAAANQADCgQIBQAAAA==.Crone:BAAANQADCgEIAQABNQAECgoKOgABANwcAA==.Crucifilth:BAAANQAECgEIAgAAAA==.Crystallight:BAABNQAECn8YAAQXAAgKfQVlCgBcAAANAAgK8QMoOwEqAQAXAAIKGAZlCgBcAAARAAMKLwXgOgBTAAAAAA==.',
Cy='Cyrusmônk:BAAANQAECgUIBgABNQAECgYIBQAOAAAAAA==.Cytherea:BAABNQAECn8bAAIBAAoKaAtVBAHjAAABAAoKaAtVBAHjAAAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgoKKQAFAP0TAA==.Dalinek:BAABNQAECn8oAAMFAAoKYR2UFwC/AgAFAAoKVReUFwC/AgAYAAQKrSKeXACXAQAAAA==.Damah:BAAANQADCggIHQABNQADCggIHQAOAAAAAA==.Dandelo:BAAANQAECgMIBAAAAA==.Danicarkel:BAACNQAFFH8HAAMdAAMKIAuyAwDWAAAdAAMKIAuyAwDWAAAIAAEKAQYBOwBAAAA1AAQKf0YABB0ACgquHCcCAA4DAB0ACgquHCcCAA4DAAcABArBCnMyAPsAAAgAAgqnC3YtAWIAAAAA.Darkdlord:BAABNQAECn84AAMWAAoKIg8oNADUAQAWAAoKIg8oNADUAQAMAAoKvwfFPgBEAQABNQAECgoKPAABAGcgAA==.Darío:BAAANQAECgYIBAAAAA==.',
Dd='Ddpaladini:BAABNQAECn88AAMBAAoKZyATHADwAgABAAoKZyATHADwAgAeAAkKlAerNwAtAQAAAA==.',
De='Deathtracker:BAABNQAECn8iAAIPAAoKUwu2pQC6AQAPAAoKUwu2pQC6AQAAAA==.Deathtrops:BAAANQAECgIIAgABNQAFFAgIIgAIADUfAA==.Demindan:BAAANQAECgUIBgAAAA==.Demise:BAACNQAFFH8WAAMNAAgKZBL0EQDoAQANAAcKhBP0EQDoAQARAAEKwAzpDQBVAAA1AAQKf0UAAw0ACgqTI3YmAKUCAA0ACgqTI3YmAKUCABEAAQr3G0U8AE4AAAAA.Demontickler:BAAANQADCggIDQABNQAECgYIEAAOAAAAAA==.',
Di='Dianabol:BAABNQAECn8sAAIUAAoKzRnERgC1AgAUAAoKzRnERgC1AgABNQAECgoKOAAJAPQlAA==.Diego:BAAANQADCgYIDAABNQAECgEIAQAOAAAAAA==.Dirkuatah:BAABNQAECn8UAAIfAAcKWCB8PgDaAQAfAAcKWCB8PgDaAQAAAA==.Dista:BAACNQAFFH8JAAIIAAQK+xAPHgDAAAAIAAQK+xAPHgDAAAA1AAQKf1MAAggACgrWIXULAA8DAAgACgrWIXULAA8DAAAA.Divinebovine:BAAANQAECgEIAQAAAA==.Divinedragon:BAABNQAECn8xAAMDAAoKqRagIQB7AQADAAkKdBWgIQB7AQAEAAQKvBoeFADnAAAAAA==.',
Do='Doboy:BAAANQAECgEIAQAAAA==.Dotsncandies:BAAANQAECgIIAgAAAA==.Doublevegan:BAAANQADCgMJAwAAAA==.',
Dr='Draconum:BAAANQADCgEIAQAAAA==.Drakin:BAABNQAECn8WAAIBAAoK/A6cqADPAQABAAoK/A6cqADPAQAAAA==.Draw:BAAANQADCgMIAwAAAA==.Drawbridge:BAAANQADCgYIEgAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAACNQAFFH8OAAIJAAYKthFiDACdAQAJAAYKthFiDACdAQA1AAQKfzQAAgkACgoGFo5PACcCAAkACgoGFo5PACcCAAAA.Drinkoolaide:BAAANQAECggIEQABNQAFFAYIDgAJALYRAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQAECgEIAQAAAA==.Dunamis:BAABNQAECn8qAAINAAoKXh/KWQDMAgANAAoKXh/KWQDMAgAAAA==.Dungodon:BAAANQAECgIIAgAAAA==.Durrt:BAAANQAECgYIEAAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAACNQAFFH8SAAMQAAcKshSRDgBUAQAQAAYKeA+RDgBUAQAPAAMK6B6SKACWAAA1AAQKfz4AAw8ACgrpJV8RAFwDAA8ACgrpJV8RAFwDABAACgqvH98MAG0CAAAA.',
['Dó']='Dóòmsday:BAAANQADCgYIBgAAAA==.',
Ei='Einaria:BAAANQAECgIIAgABNQAECgoKMwANANkdAA==.',
El='Eldrene:BAABNQAECn8zAAINAAoK2R1LMwB1AgANAAoK2R1LMwB1AgAAAA==.Elizalde:BAAANQAECgYIEAAAAA==.Ellexi:BAABNQAECn8ZAAIVAAkKwAyrJgCrAQAVAAkKwAyrJgCrAQAAAA==.Elyseia:BAABNQAECn8mAAIPAAoKFA4JewAYAgAPAAoKFA4JewAYAgAAAA==.',
En='Enpower:BAAANQAECgQICgABNQAFFAQIDgAgAEkIAA==.',
Ep='Epicsause:BAAANQAECggICgAAAA==.',
Es='Escata:BAAANQAECgQICAAAAA==.Esdailongwe:BAAANQADCgYIEQAAAA==.Españamor:BAECNQAFFH8GAAMhAAUKQgNfDwBcAAAhAAIKRwNfDwBcAAAKAAMKOQMWBwArAAA1AAQKfyoAAyEACgqKE5AiAIoBACEACgqlEpAiAIoBAAoACAqODNwYACQBAAE1AAQKCAgIAA4AAAAA.',
Eu='Eunite:BAABNQAECn9rAAIVAAoK0B2kKACWAgAVAAoK0B2kKACWAgAAAA==.',
Fa='Falkorne:BAABNQAECn8WAAMGAAcKqwrfHgAHAQAGAAcKGArfHgAHAQAUAAUKrQce2gC/AAABNQAECgoKKQAgALQYAA==.Farael:BAAANQADCgYIBgAAAA==.Fashah:BAAANQAECgMIAwAAAA==.Fatalmann:BAAANQAECgIIAgAAAA==.',
Fe='Felmoo:BAABNQAECn8XAAIcAAkKdgaLNQD1AAAcAAkKdgaLNQD1AAAAAA==.Felorc:BAABNQAECn8gAAMGAAkKJAUCKwDhAAAGAAkKJAUCKwDhAAAUAAIKKAIbTQE6AAABNQAECgkJKQAMABMIAA==.Feralhorn:BAAANQAECggIEQAAAA==.',
Fi='Fintan:BAAANQAECgUIBQABNQAFFAgIGQAJAAcaAA==.',
Fo='Forsakenemp:BAAANQAECggIDQABNQAECgoKPAABAGcgAA==.',
Fr='Frassk:BAABNQAECn88AAMIAAoKwBNXZwChAQAIAAoKTxJXZwChAQAHAAIKuRNyHQB8AAAAAA==.Frigid:BAAANQADCgcIBwAAAA==.Froggystyle:BAAANQAECggIEgAAAA==.Frozenheart:BAABNQAECn8pAAMMAAkKEwi5dwAZAQAMAAkKEwi5dwAZAQAWAAQKZgb0nQBgAAAAAA==.Fruk:BAAANQADCgUIBQAAAA==.Frösting:BAAANQADCgYIBgABNQAECgoKKwAiALwZAA==.',
Ft='Ftx:BAABNQAECn8sAAIUAAkKxiE3SgCqAgAUAAkKxiE3SgCqAgAAAA==.',
Fu='Fundidos:BAAANQAECgEIAQAAAA==.Furfoxxsakes:BAAANQADCgEIAQAAAA==.',
Ga='Garbarn:BAAANQADCgcIDQAAAA==.',
Ge='Gelystine:BAAANQADCgIIAgAAAA==.Geminichi:BAACNQAFFH8OAAMgAAQKSQgPBwD3AAAgAAQKSQgPBwD3AAAjAAEKGwpxEwBGAAA1AAQKfz0AAyAACgqfHR4LAI4CACAACgqfHR4LAI4CACMAAgqFEClqADcAAAAA.Geminishadow:BAABNQAECn8ZAAMYAAoKUQ25UwC2AQAYAAoKhgu5UwC2AQAFAAUKcw2iYAAyAQAAAA==.',
Gh='Ghauri:BAAANQADCgYJBgAAAA==.Ghorza:BAAANQADCgYIBwAAAA==.',
Gi='Gia:BAABNQAECn9LAAIgAAoKox2iBgAbAwAgAAoKox2iBgAbAwAAAA==.Gigasauce:BAAANQAECgEIAQAAAA==.Giraffage:BAABNQAECn8WAAINAAcK6Q9j4ADIAQANAAcK6Q9j4ADIAQABNQAECgcIBwAOAAAAAA==.',
Go='Golgroth:BAAANQADCgQJBAAAAA==.Goochgibbler:BAAANQADCgQIBAAAAA==.Gorearrow:BAACNQAFFH8GAAIPAAMKdxSBIgCXAAAPAAMKdxSBIgCXAAA1AAQKfzsAAg8ACgryH2AzANICAA8ACgryH2AzANICAAAA.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Grimmtotem:BAABNQAECn8YAAISAAgK8QQ6DADtAAASAAgK8QQ6DADtAAAAAA==.Groggyfroggy:BAAANQADCgMJAwAAAA==.Grognaak:BAAANQADCgMIBAAAAA==.Grralt:BAAANQAECgIIAgABNQADCggIHQAOAAAAAA==.Grís:BAABNQAECn8yAAMUAAoKFxiTaABWAgAUAAoKFxiTaABWAgAGAAMKCA3uMwCXAAAAAA==.',
Gu='Gumbuz:BAAANQAECgQIBAAAAA==.Gunafistya:BAAANQAECgMIBQAAAA==.',
Ha='Hanwi:BAAANQAECggICAAAAA==.Harrier:BAAANQADCggIEgABNQAECgoKHQAaAN0SAA==.Hazed:BAABNQAECn8XAAINAAoKfQwhdADHAQANAAoKfQwhdADHAQAAAA==.Hazyblades:BAAANQAECgIIAgAAAA==.Hazzaa:BAAANQAECgcICQAAAA==.',
He='Healzforbeer:BAAANQADCgUIBQAAAA==.Heila:BAAANQAFFAIIAgAAAA==.Henso:BAABNQAECn8dAAIaAAoKvRhSCQBRAgAaAAoKvRhSCQBRAgABNQAFFAQIDgAgAEkIAA==.Herioffy:BAAANQADCgEIAQAAAA==.Hexxan:BAAANQADCgYIBgAAAA==.',
Hi='Hiawatha:BAAANQADCgQIBAAAAA==.Hiver:BAAANQAECgEIAQAAAA==.',
Ho='Holier:BAACNQAFFH8FAAIBAAIKaAX8KQBwAAABAAIKaAX8KQBwAAA1AAQKf0cAAgEACgocEDKGAMABAAEACgocEDKGAMABAAAA.Holybishh:BAAANQAECgUIBQAAAA==.Holyregerts:BAABNQAECn8jAAMDAAoKmxEwJAAPAgADAAkKQRAwJAAPAgACAAgK4BmDcQDIAQAAAA==.Honk:BAABNQAECn8XAAIIAAoKOw4XmACrAQAIAAoKOw4XmACrAQAAAA==.Hoochurcooch:BAAANQAECgQIBAAAAA==.Hoosnext:BAAANQAECgEIAQAAAA==.Hopperstotem:BAAANQAECgMIAwABNQAECgoKHgAPAG4hAA==.',
Hu='Hulo:BAAANQAECgMIAwAAAA==.Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQAECgIIAgAAAA==.',
Il='Illari:BAAANQABCgIIAgAAAA==.Illumi:BAAANQABCgYIBgAAAA==.',
Im='Imbatmann:BAAANQADCgEIAQAAAA==.',
In='Indrà:BAAANQADCgQIBQAAAA==.Infamus:BAAANQAECgIIBQAAAA==.Invysion:BAACNQAFFH8SAAMEAAUKLAOWAQApAQAEAAUKLAOWAQApAQACAAIKyAGMLwBrAAA1AAQKf0wAAwQACgo1FcUDAC4CAAQACgo1FcUDAC4CAAIAAQqoBmz3ADEAAAAA.',
Is='Ishara:BAAANQABCgIIAgABNQAECgoKMwANANkdAA==.Islander:BAABNQAECn8gAAITAAgKKRQCTADkAQATAAgKKRQCTADkAQAAAA==.',
Ja='Jackychang:BAABNQAECn8mAAIYAAoKrw5hGwD7AQAYAAoKrw5hGwD7AQAAAA==.Jaidess:BAAANQADCggIFgAAAA==.Jakeypoo:BAAANQAECgQICgAAAA==.Jayskiller:BAAANQADCgUIBQAAAA==.',
Je='Jellybea:BAACNQAFFH8IAAICAAUKyBICEwB6AQACAAUKyBICEwB6AQA1AAQKfzIAAwIACgq5HnUrALsCAAIACgq5HnUrALsCAAMAAwpSDHZqAFkAAAAA.',
Ji='Jimmee:BAAANQADCgIIAgAAAA==.',
Ju='Jukoti:BAAANQABCgIIBAAAAA==.Junglebrew:BAAANQAECgUIAwAAAA==.Jurisdiction:BAABNQAECn8mAAIBAAoKdgwkiQC6AQABAAoKdgwkiQC6AQAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAABNQAECn8xAAIjAAoKDhzTDwDoAgAjAAoKDhzTDwDoAgAAAA==.Kalimyst:BAAANQAECgMIAwAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kanalz:BAAANQAECgUIBQAAAA==.Karambit:BAAANQAECgcICwAAAA==.Kasey:BAABNQAECn8VAAIBAAYK8B4guwCnAQABAAYK8B4guwCnAQAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keggstand:BAAANQAECgYIBgAAAA==.Keho:BAABNQAECn8mAAMkAAoKjgi1DwApAQAkAAkKOgi1DwApAQAjAAEK1grdXQA0AAAAAA==.Kellbor:BAAANQAECgEIAQAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAACNQAFFH8QAAMhAAUKNRRPCgC8AAALAAQKNRSjDwAMAQAhAAQKughPCgC8AAA1AAQKf0EAAyEACgpjHyMPAGQCAAsACgo/G9ghAI0CACEACgqyHiMPAGQCAAE1AAQKBwgHAA4AAAAA.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kickdrop:BAAANQADCgQIBAAAAA==.Kilgreed:BAAANQADCgYIDgAAAA==.Killaban:BAAANQAECgcIBwAAAA==.Killbydeath:BAABNQAECn8gAAQVAAgKDSUjFQBHAgAVAAgK1SMjFQBHAgAWAAQK8CD/QQCTAQAMAAIKax9anACiAAAAAA==.Kimberlyhárt:BAAANQAECgYIEAAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYIEAAOAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAABNQAECn90AAIIAAoK4x2qHACkAgAIAAoK4x2qHACkAgAAAA==.',
Ko='Kohman:BAABNQAECn9JAAMIAAoKxRhAMQDDAgAIAAoKxRhAMQDDAgAHAAMKtA1xUgCIAAAAAA==.Komatose:BAAANQADCgYIBgAAAA==.Kong:BAAANQADCgIIAwAAAA==.',
Kr='Krftpnk:BAACNQAFFH8iAAILAAkKFRyBAQC0AgALAAkKFRyBAQC0AgA1AAQKf0EAAgsACgrqJi4CANUDAAsACgrqJi4CANUDAAAA.Kricket:BAAANQAECgEIAgAAAA==.Kronas:BAABNQAECn8XAAMPAAkKHBQ3jwDrAQAPAAkKHBQ3jwDrAQAQAAEKjQOybwAsAAAAAA==.Kronosity:BAABNQAECn87AAIeAAoK8B+mCgDwAgAeAAoK8B+mCgDwAgABNQAFFAQICQAMAG8fAA==.Kronotality:BAACNQAFFH8JAAIMAAQKbx91EAD/AAAMAAQKbx91EAD/AAA1AAQKf0gAAgwACgrvI8MFAJcDAAwACgrvI8MFAJcDAAAA.Kronotekken:BAAANQAECgEIAQABNQAFFAQICQAMAG8fAA==.Kronotide:BAAANQADCgQIBAABNQAFFAQICQAMAG8fAA==.',
Ku='Kungfukittn:BAABNQAECn8dAAIjAAcKIxagKwC+AQAjAAcKIxagKwC+AQAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQAECggIDgAAAA==.Kyojuro:BAAANQABCgYIBgAAAA==.',
Kz='Kzorx:BAAANQAECgEIAgAAAA==.',
La='Laimaster:BAAANQAECgQIBAAAAA==.Laizie:BAAANQABCgYICAAAAA==.Lakiri:BAABNQAECn87AAIiAAoKrBBKEgDzAQAiAAoKrBBKEgDzAQAAAA==.Landaeda:BAAANQAECgUIBQAAAA==.Lascivia:BAACNQAFFH8GAAIGAAMK/RsIBQCVAAAGAAMK/RsIBQCVAAA1AAQKfywAAwYACgrIIVoGAAIDAAYACgrIIVoGAAIDACUABAoAGPsYABIBAAAA.Latrice:BAAANQAECgcIBwABNQAFFAgIFQARAB8cAA==.Laylahh:BAAANQADCgQIBAAAAA==.Lazereyes:BAAANQAECgUICQAAAA==.',
Le='Leademon:BAABNQAECn8gAAILAAoK5he4MAAiAgALAAoK5he4MAAiAgAAAA==.Leadmln:BAAANQAECgYICwABNQAECgoKIAALAOYXAA==.Lebwonsamdi:BAAANQAECgUIBQABNQAECgoKMgAUABcYAA==.Lethalkrits:BAAANQAECggIAgAAAA==.',
Li='Liberté:BAAANQADCggICgAAAA==.Liciano:BAAANQAECgcICAABNQAECgoKOAAJAPQlAA==.Lickey:BAAANQAECgEIAQABNQAECgYIEAAOAAAAAA==.Lighterfluîd:BAAANQABCgIIAgABNQAECgoKLgAgAFEfAA==.Ligmadk:BAAANQADCgUIBQABNQAFFAUICAALAHAJAA==.Lilbeebs:BAAANQAECgcIDwAAAA==.Lileth:BAAANQABCgIIBAAAAA==.Lilflea:BAABNQAECn8lAAMJAAoK9xliUQAgAgAJAAoK9xliUQAgAgAfAAEKAAD5TAEnAAAAAA==.Lillidari:BAAANQAECgcICQABNQAECgkJJgAMACwkAA==.Lilzuki:BAABNQAECn8XAAIHAAoKfg2QBwBZAQAHAAoKfg2QBwBZAQAAAA==.Lilïth:BAABNQAECn8mAAIMAAkKLCQkCwBbAwAMAAkKLCQkCwBbAwAAAA==.Linguine:BAAANQADCggICAABNQAFFAQICgADAHQNAA==.Lisalisa:BAABNQAECn8rAAIJAAoKTxL2VQC7AQAJAAoKTxL2VQC7AQAAAA==.Littlej:BAAANQAECgQJBAAAAA==.Littlejohn:BAABNQAECn8pAAIgAAoKtBjtEABwAgAgAAoKtBjtEABwAgAAAA==.',
Lo='Logantis:BAABNQAECn8eAAIUAAkKJxZ7QABBAgAUAAkKJxZ7QABBAgAAAA==.Logaothe:BAABNQAECn8cAAIBAAYKJQpOAgEbAQABAAYKJQpOAgEbAQAAAA==.Lokee:BAAANQADCgUIBQAAAA==.',
Lu='Lucky:BAABNQAECn8YAAILAAgKHRDxOgBVAQALAAgKHRDxOgBVAQAAAA==.Lukethywalkr:BAAANQAECgEIAQAAAA==.Lularia:BAAANQADCgYIDQAAAA==.Lunaa:BAAANQAECgQIBwAAAA==.Lusid:BAAANQABCgcICAAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Malakyte:BAAANQAECgIIAgAAAA==.Maliciousrot:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQIBQAAAA==.Marshail:BAAANQAECgUIBQAAAA==.',
Me='Medikus:BAABNQAECn85AAMJAAoKGxxNHQDPAgAJAAoKGxxNHQDPAgAfAAEKKQTjBgEuAAAAAA==.Megajoo:BAABNQAECn8gAAMmAAoK4BAuHgAQAgAmAAoK4BAuHgAQAgAbAAIK4QSTvwAiAAAAAA==.Melkinov:BAAANQABCgYIBgAAAA==.Melsande:BAAANQADCgUIBQAAAA==.Merryl:BAAANQAECgUIBwAAAA==.',
Mf='Mfive:BAAANQAECgQIBAAAAA==.',
Mi='Mike:BAEBNQAECn8cAAINAAkK4iGtUQDdAgANAAkK4iGtUQDdAgAAAA==.Milkjugs:BAAANQAECgUIAwABNQAECgoKJQAJAPcZAA==.Minijeangen:BAAANQAECgMJAwAAAA==.Missluana:BAAANQABCgEIAQAAAA==.Mizshankalot:BAAANQAECgcICQABNQAECgoKPAABAGcgAA==.',
Mo='Mockra:BAABNQAECn9AAAINAAgKGhZxrAApAgANAAgKGhZxrAApAgAAAA==.Moistmunnky:BAAANQAECgYIEAAAAA==.Montera:BAEANQAFFAIIAgABNQAECggICAAOAAAAAA==.Moohammered:BAABNQAECn86AAIBAAoK3BycLQCrAgABAAoK3BycLQCrAgAAAA==.Moolou:BAACNQAFFH8IAAIeAAUKBAwjCACtAAAeAAUKBAwjCACtAAA1AAQKfy8AAx4ACgpfHO0QAJECAB4ACgpfHO0QAJECAAEAAQrwC5SSATgAAAAA.Mootarded:BAABNQAECn8UAAIeAAkK5wS3RgCLAAAeAAkK5wS3RgCLAAABNQAECgkJKQAMABMIAA==.Mordiggian:BAABNQAECn9GAAMMAAoKjyTQDwAvAwAMAAkKbyXQDwAvAwAVAAkKlSMFGQD3AgAAAA==.Morechie:BAABNQAECn83AAMdAAoKYxAkCQD0AQAdAAkKBRAkCQD0AQAIAAYKgQwNuwDcAAAAAA==.Morganaj:BAAANQAECgQICwAAAA==.Morgatho:BAAANQABCgcICQAAAA==.Morsz:BAAANQAECgUICAAAAA==.Mortiferon:BAABNQAECn8jAAIVAAkKShrUOwAyAgAVAAkKShrUOwAyAgAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQAECgYIEAAOAAAAAA==.Munnkypox:BAAANQAECgIIBAABNQAECgYIEAAOAAAAAA==.Murderella:BAAANQADCgYIBgAAAA==.Muriggs:BAAANQAFFAEIAQAAAA==.Murkhoof:BAAANQADCgYIBgABNQAECgoKHQAaAN0SAA==.',
['Mö']='Mörgänä:BAAANQADCggIEQAAAA==.',
Na='Nakovii:BAAANQAECgUIBQAAAA==.Nakovy:BAAANQAECgQIAwAAAA==.Napa:BAAANQAECgUIBQABNQAFFAcIFAAJAKcXAA==.Nascerathel:BAAANQAECgQIBwAAAA==.',
Ne='Nealite:BAAANQADCgYIBgAAAA==.Neerem:BAAANQABCggIDQAAAA==.Neferata:BAABNQAECn9TAAMIAAoKIh9mKgBlAgAIAAoKIh9mKgBlAgAHAAYKbgvNJwA6AQAAAA==.Nerrisa:BAAANQADCggIDwAAAA==.Nertmage:BAABNQAECn9tAAQXAAoKgSJQAACfAwAXAAoKgSJQAACfAwANAAIKAA7+vAFEAAARAAEKThmNPgA6AAAAAA==.Neublood:BAAANQAECgQIBwAAAA==.',
Ni='Nicodemus:BAAANQAECgYICQAAAA==.Nineiota:BAABNQAECn8uAAMmAAoK+Bx0FQB4AgAmAAoK+Bx0FQB4AgAbAAEKzA3aiAA2AAAAAA==.',
No='Noblewarrior:BAACNQAFFH8gAAIUAAcK7hQBEQCtAQAUAAcK7hQBEQCtAQA1AAQKf1EAAxQACgpGJIwPABsDABQACgo1JIwPABsDACUACAqzIrADAMoCAAAA.Nobukawaii:BAAANQAECgMIAwAAAA==.Noctilus:BAAANQADCgcIGQAAAA==.Noke:BAAANQAECgIJAgAAAA==.Noril:BAAANQADCgUIBQAAAA==.Notakoala:BAACNQAFFH8QAAIbAAYKABaZEABhAQAbAAYKABaZEABhAQA1AAQKf0IAAhsACgreIjwLAO0CABsACgreIjwLAO0CAAAA.Nothnx:BAACNQAFFH8NAAIPAAYK0A/LBgCMAQAPAAYK0A/LBgCMAQA1AAQKf0wAAg8ACgpwH8glAKgCAA8ACgpwH8glAKgCAAAA.Notillidan:BAAANQADCgYICgAAAA==.Notoriouspat:BAAANQAECgcIEAAAAA==.Notromanoff:BAAANQADCgEIAQABNQAECgoKKQAFAP0TAA==.Novia:BAAANQAECgcIDgABNQAECgoKMgAUABcYAA==.Noxeternis:BAACNQAFFH8IAAMCAAQKIQtPHgD/AAACAAQKIQtPHgD/AAADAAEKfBA+FgBJAAA1AAQKfzYABAMACgr6GTIhAC4CAAMACQoZGTIhAC4CAAIABQrYG5CJADwBAAQAAgoyBiAkAEoAAAAA.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
Ny='Nyxandra:BAAANQADCggIGwAAAA==.',
['Ní']='Níghtfall:BAAANQADCgUICwAAAA==.Nínebreaker:BAAANQAECgEIAQAAAA==.',
['Nü']='Nüll:BAAANQAECgEIAQAAAA==.',
Ob='Obern:BAABNQAECn8hAAISAAoK1hQ5BQBzAgASAAoK1hQ5BQBzAgAAAA==.Obeysnapback:BAAANQADCgMIBAAAAA==.Oblïna:BAAANQAECgcIEgAAAA==.',
Od='Oddishh:BAABNQAECn8fAAMWAAoK4w55MwDXAQAWAAoK4w55MwDXAQAMAAYK6wivfQADAQAAAA==.',
Of='Offensivé:BAAANQAECgMIBAAAAA==.',
Ol='Olleg:BAAANQADCgYICQAAAA==.',
Om='Omnicarkel:BAAANQADCgcIDAAAAA==.',
On='Onsen:BAABNQAECn8wAAIBAAoKFxwaWwCHAgABAAoKFxwaWwCHAgABNQAECgoKSQAIAMUYAA==.',
Or='Oresties:BAAANQADCggICAAAAA==.Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQJBAAAAA==.',
Ou='Outwithabang:BAAANQAECgMIAwAAAA==.',
Pa='Pajl:BAABNQAECn8uAAIBAAoKlyOtDQCXAwABAAoKlyOtDQCXAwABNQAFFAgIEQAWAMYaAA==.Pandablaze:BAAANQAECgQIBQAAAA==.Pandajoy:BAAANQADCgEIAQAAAA==.Panterarey:BAAANQAECgIIAgAAAA==.Papanurrgle:BAAANQAECgUICQAAAA==.Papazilla:BAAANQAECgMJAwAAAA==.Parakka:BAAANQAECggICwAAAA==.Patak:BAAANQADCgQIBQAAAA==.Pawp:BAABNQAECn8dAAMJAAkK3REUXwCbAQAJAAkK3REUXwCbAQAiAAMKQwFYMQBfAAABNQAECgoKNwACACcaAA==.Paxiel:BAAANQAECgQICAAAAA==.',
Pe='Pearagon:BAABNQAECn8bAAMCAAkKmBnoLwCEAgACAAkKmBnoLwCEAgADAAIKBRcsWgBHAAABNQAFFAcIFAAJAKcXAA==.Pepsidew:BAAANQAECggICgAAAA==.Pepsisprite:BAABNQAECn8fAAICAAkKZhoZQQA1AgACAAkKZhoZQQA1AgAAAA==.',
Ph='Phdbeef:BAAANQAECgEIAQABNQAECgkJJgAMACwkAA==.Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQAECgIIAgAAAA==.',
Pi='Picklez:BAABNQAECn8wAAIWAAkKIhjfLQD3AQAWAAkKIhjfLQD3AQAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.Portwings:BAAANQAECgMIBAAAAA==.',
Ps='Psyop:BAAANQADCggIGAABNQAECgoKTAACAD4iAA==.Psyrax:BAAANQAECgQICgAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Rashguard:BAAANQAECggICAAAAA==.Rashun:BAAANQAECgUICAAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDgAAAA==.Redkoala:BAABNQAECn8eAAINAAgKTgfEnwBlAQANAAgKTgfEnwBlAQABNQAFFAYIEAAbAAAWAA==.Regrets:BAAANQAECgQIAwABNQAECgoKIwADAJsRAA==.Regretty:BAAANQAECgEIAQABNQAECgoKIwADAJsRAA==.Repete:BAAANQAECgQIBAAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECn9rAAIRAAoKwSESAgBaAwARAAoKwSESAgBaAwAAAA==.Reven:BAAANQAECgYICAAAAA==.Reverendgank:BAAANQAECgMIBgAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ri='Riivan:BAAANQAECgIIAQAAAA==.Rirugiliyang:BAAANQAECgEIAQAAAA==.Rivian:BAAANQAECgYICQABNQAECggIIAATACkUAA==.',
Ro='Roardon:BAAANQADCggIDwAAAA==.Roflmfao:BAAANQADCggICAAAAA==.Roguè:BAAANQAECgQICgABNQAECgYIBAAOAAAAAA==.Rollinburn:BAAANQADCgUJBQAAAA==.Romanoff:BAABNQAECn8pAAMFAAoK/ROaPQDZAQAFAAcKBxOaPQDZAQAYAAgKjBM0XwCOAQAAAA==.Rosearcana:BAAANQAECgEIAQAAAA==.Rozztok:BAAANQADCggIDgAAAA==.',
Ry='Ryokhan:BAAANQAECggICgAAAA==.',
['Rô']='Rôx:BAAANQADCgcIBgABNQAECgoKcQATAL0bAA==.',
['Rõ']='Rõx:BAABNQAECn9xAAMTAAoKvRtOLwCpAgATAAoKvRtOLwCpAgABAAgKjBS5gQDJAQAAAA==.',
Sa='Sackoss:BAABNQAECn8fAAITAAkKtxiQXwD6AQATAAkKtxiQXwD6AQAAAA==.Saffronspark:BAAANQAECgUIDQABNQAECgoKSwAjAJEeAA==.Sainsei:BAABNQAECn8lAAMkAAoKrRXbCADEAQAkAAkK7BHbCADEAQAjAAUKgRgJLQAxAQABNQAECgoKMgAUABcYAA==.Sakata:BAAANQADCgIIAgABNQAECgoKHQAaAN0SAA==.Sandwitch:BAABNQAECn9rAAMHAAoKsRNuDwAGAgAIAAoKPBIjYAA4AgAHAAgKTxBuDwAGAgAAAA==.Sargatanas:BAABNQAECn8jAAIMAAkK8gw/UgCsAQAMAAkK8gw/UgCsAQAAAA==.Sars:BAAANQADCgUIBQABNQAECggIIQACAC8kAA==.',
Sc='Scarcroww:BAAANQADCgMIAwABNQAECgoKJgANAGofAA==.Schrodinger:BAAANQAECgIIBAAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Selline:BAAANQAECgIIAgAAAA==.Septicflësh:BAAANQAECggICAAAAA==.Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAABNQAECn8tAAIGAAkKvxLhFAByAQAGAAkKvxLhFAByAQAAAA==.',
Sh='Shadrad:BAACNQAFFH8HAAIBAAUKsRX0FADgAAABAAUKsRX0FADgAAA1AAQKfzUAAwEACgp8IIgnACgDAAEACgp8IIgnACgDABMABwqnBPnGAO0AAAAA.Shallot:BAABNQAECn8zAAINAAoK3SDdNwAYAwANAAoK3SDdNwAYAwAAAA==.Shammoo:BAABNQAECn8YAAIfAAkK4RYAYAACAgAfAAkK4RYAYAACAgABNQAFFAQIBgABAMYLAA==.Shammyd:BAABNQAECn8nAAIfAAoK9QjMVwCAAQAfAAoK9QjMVwCAAQAAAA==.Shamsvet:BAAANQADCgIIAgAAAA==.Shantz:BAABNQAECn87AAIMAAoKAhEZKAC+AQAMAAoKAhEZKAC+AQAAAA==.Sharprot:BAAANQAECgYIBgABNQAECgoKKwAUAOQQAA==.Shiftface:BAAANQAECggICAABNQAECgoKGwABAGgLAA==.Shiftmypants:BAABNQAECn8sAAIbAAoKFhtNEwCFAgAbAAoKFhtNEwCFAgAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Si='Sinterdeath:BAABNQAECn8VAAMVAAcK7AjkgwAQAQAVAAcK7AjkgwAQAQAWAAQKTwUSmQBrAAAAAA==.',
Sk='Skatervan:BAAANQAECgUIBQABNQAECgoKTwADAFkdAA==.Skylie:BAAANQADCgYIDwAAAA==.',
Sl='Slushpuppy:BAAANQAECgIIAgAAAA==.',
Sm='Smorthian:BAAANQAECgQIDwAAAA==.',
Sn='Snicggers:BAAANQADCggICAAAAA==.Sniffinsteak:BAAANQAECgYJEAAAAA==.Snoosnooftww:BAAANQAECgIIAgAAAA==.',
So='Solas:BAABNQAECn8jAAICAAcKMxnnUAD2AQACAAcKMxnnUAD2AQAAAA==.Sonarael:BAAANQAECgMIAwABNQAECgoKMwANANkdAA==.Sondeltis:BAAANQAECgQIBQAAAA==.Soryan:BAAANQAECgUIBQAAAA==.',
Sp='Spankenstine:BAABNQAECn8eAAIBAAkKdRktbQBXAgABAAkKdRktbQBXAgABNQAECgoKKwAUAOQQAA==.Sparkyy:BAAANQAECgIIAwAAAA==.Sphaeram:BAAANQAECgcICAAAAA==.Spicypepsi:BAAANQADCgEIAQAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAABNQAECn8zAAIBAAoKXCFVLACwAgABAAoKXCFVLACwAgAAAA==.Stinkydeathy:BAAANQADCgYJBgABNQAECgIIAgAOAAAAAA==.Stinkydragon:BAAANQAECgIIAgAAAA==.Stormknight:BAAANQAECgYICgAAAA==.Stormpoo:BAAANQAECgYICQAAAA==.',
Su='Suneater:BAABNQAECn8sAAITAAoKlR9CFAAYAwATAAoKlR9CFAAYAwAAAA==.Superpi:BAAANQADCgYIBgABNQAECgUICAAOAAAAAA==.Superret:BAAANQAECgUICAAAAA==.Surotor:BAAANQADCgQICAAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAABNQAECn8tAAIBAAoKfA2CjQCxAQABAAoKfA2CjQCxAQAAAA==.',
Sw='Swíper:BAACNQAFFH8FAAIFAAIKLA8iFwCUAAAFAAIKLA8iFwCUAAA1AAQKfy8AAwUACgogHnkIAFADAAUACgogHnkIAFADABgABQq1CTA4APcAAAAA.',
Sy='Sylphièl:BAACNQAFFH8QAAMYAAcKywfPEAACAQAYAAYKtwjPEAACAQAFAAEKGwSqFAA8AAA1AAQKfzkAAxgACgomHOUcAJ8CABgACQomHOUcAJ8CAAUACQoxCflBAMMBAAAA.',
['Sö']='Sörceress:BAAANQADCgQIBAAAAA==.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgcIDQAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECn8oAAIBAAkKmiJpLAAWAwABAAkKmiJpLAAWAwAAAA==.Tankenstine:BAABNQAECn8rAAIUAAoK5BDvawC9AQAUAAoK5BDvawC9AQAAAA==.Tanktop:BAAANQADCggIDwABNQAECggICAAOAAAAAA==.Tastymilk:BAAANQAECgcIDQAAAA==.Tawnii:BAAANQAECgQIBAAAAA==.Taírn:BAAANQAECgQIBAAAAA==.',
Te='Tenderloin:BAABNQAECn8gAAMLAAoKhw44LQCpAQALAAoKNA04LQCpAQAKAAQKWhDhIwCgAAAAAA==.',
Th='Thanitose:BAABNQAECn8fAAIUAAoKAAdNkQBeAQAUAAoKAAdNkQBeAQAAAA==.Thevelo:BAAANQAECgYICAABNQAECgkJFwASAMoSAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thornok:BAAANQADCggICAAAAA==.Thornwyn:BAABNQAECn8aAAMmAAkKgw8AKQCoAQAmAAkKgw8AKQCoAQAbAAIKRAuqjwAtAAAAAA==.Thors:BAAANQADCgQIBAAAAA==.Thorul:BAABNQAECn8aAAIUAAkKWwvDawC+AQAUAAkKWwvDawC+AQAAAA==.Thundurus:BAACNQAFFH8MAAIfAAMKWwfmIAB7AAAfAAMKWwfmIAB7AAA1AAQKfz0AAh8ACgrqFwlGAF4CAB8ACgrqFwlGAF4CAAAA.',
Ti='Timmayy:BAABNQAECn8YAAIIAAkKrg1XYAC0AQAIAAkKrg1XYAC0AQABNQAECgoKKQAgALQYAA==.Tindrill:BAAANQAECgMIAwABNQAECgoKKwAmAL0iAA==.Tinggoskrrah:BAAANQADCggIEgAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAABNQAECn80AAIUAAoK1w8UZADUAQAUAAoK1w8UZADUAQAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAkJIgALABUcAA==.Totemagoat:BAACNQAFFH8MAAMJAAgKRA7yDQBuAQAJAAgKRA7yDQBuAQAfAAEKsQXlMgBEAAA1AAQKf08AAwkACgqyIoMWAB0DAAkACgqyIoMWAB0DAB8ACApPF9BgAP8BAAAA.',
Tr='Tracula:BAAANQADCgEIAQAAAA==.Tranquila:BAEANQAECggICAAAAA==.Treefist:BAAANQAECgYIBgAAAA==.Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAACNQAFFH8PAAImAAUKMgwOCgAiAQAmAAUKMgwOCgAiAQA1AAQKfzcAAyYACgqSFggdAEsCACYACgqSFggdAEsCABsAAwpMArx9AE0AAAAA.',
Un='Undeadkiels:BAAANQADCggICAABNQAECgoKPAABAGcgAA==.Undeadmonks:BAAANQADCgYIBgAAAA==.',
Ur='Uraharakun:BAAANQAECgcIDAABNQAECgoKTAAeAMMXAA==.',
Va='Vagalion:BAABNQAECn8uAAQiAAoKtxTTEAAJAgAiAAgKYBbTEAAJAgAfAAgKbQu/eAAiAQAJAAUK+gyJuAD7AAAAAA==.Valdanyr:BAAANQAECggICQAAAA==.Vale:BAAANQAECgMIAwAAAA==.Valeshot:BAABNQAECn8tAAIPAAoKcQ1+dwAgAgAPAAoKcQ1+dwAgAgAAAA==.Valimyr:BAAANQABCgMIBAAAAA==.Valkillrie:BAABNQAECn8lAAMTAAoKyBlbIAC8AgATAAoKyBlbIAC8AgABAAIKXgq9egFhAAAAAA==.Valohir:BAAANQAECgIIAgAAAA==.Vanhellsin:BAABNQAECn8aAAIMAAgKvQ9WUQD4AAAMAAgKvQ9WUQD4AAAAAA==.Vashi:BAAANQAECgYICgABNQAECgoKLgALAAsUAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECgkJFgABAAcjAA==.Vedronas:BAABNQAECn8WAAIBAAkKByPmJQAuAwABAAkKByPmJQAuAwAAAA==.Veos:BAABNQAECn8xAAIRAAoKYxoeBQDIAgARAAoKYxoeBQDIAgAAAA==.Verdict:BAAANQAECgUIBQAAAA==.Vern:BAABNQAECn8aAAMCAAgKRRMIZAD0AQACAAgKRRMIZAD0AQAEAAEKzQgLLAAsAAAAAA==.Vernaar:BAAANQAECggIDQABNQAECggIGgACAEUTAA==.Vernah:BAAANQADCgIIAgABNQAECggIGgACAEUTAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Volætile:BAAANQAECgQIBQABNQAECgoKKwAiALwZAA==.Vonaria:BAAANQAECgUIEQAAAA==.Vorn:BAABNQAECn9rAAIMAAoK0BpYIACxAgAMAAoK0BpYIACxAgAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAABNQAECn8nAAIcAAgKDBsrDwBxAgAcAAgKDBsrDwBxAgAAAA==.Waamchifu:BAAANQAECgMIBwAAAA==.Waltersight:BAAANQAECgMIBQAAAA==.Warbritt:BAAANQADCgYIBgAAAA==.Warförged:BAAANQAECggICAAAAA==.Warwuff:BAAANQADCgUICAAAAA==.Waterwalkerr:BAAANQADCgYIBgAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgUIDgAAAA==.Whatthezug:BAAANQABCgIIAgABNQAECgQICgAOAAAAAA==.Whoforted:BAABNQAECn8uAAMCAAoKUxt+NQBoAgACAAkKxhp+NQBoAgADAAcKzhJVKgDVAQAAAA==.',
Wi='Wisperia:BAAANQAECgMIBAAAAA==.',
Wo='Wormchild:BAAANQADCgQIBwAAAA==.',
Wu='Wulrat:BAABNQAECn8UAAMGAAoK5BSCJADWAAAUAAcKrw9NuQCNAQAGAAQKvhmCJADWAAAAAA==.',
Wy='Wyle:BAAANQAECgQIBwAAAA==.',
Xe='Xelí:BAABNQAECn9sAAIJAAoKoRl+NQCJAgAJAAoKoRl+NQCJAgAAAA==.Xeras:BAAANQADCgIIAgAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAABNQAECn8YAAIPAAkKxxeMTwCAAgAPAAkKxxeMTwCAAgABNQAFFAgIGQAJAAcaAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.Youvbendoted:BAABNQAECn8eAAIIAAoKtiCoDwDxAgAIAAoKtiCoDwDxAgAAAA==.',
Yu='Yudah:BAAANQAECgQIBAAAAA==.',
Za='Zaldorina:BAAANQAECgEIAQAAAA==.Zanghonghua:BAABNQAECn9LAAIjAAoKkR5hCgC+AgAjAAoKkR5hCgC+AgAAAA==.',
Ze='Zemy:BAACNQAFFH8FAAIbAAUK0BONEwAyAQAbAAUK0BONEwAyAQA1AAQKfzEAAxsACgocJbAKAHcDABsACgocJbAKAHcDABwABwrTFy0fAKUBAAAA.Zeneca:BAAANQAECgIIAgABNQAFFAQICgADAHQNAA==.',
Zo='Zodshot:BAAANQADCgQIBAAAAA==.Zodstrike:BAABNQAECn8/AAMLAAoKuAmUNQB1AQALAAoKuAmUNQB1AQAhAAkKaAQuNgDqAAAAAA==.Zooboo:BAABNQAECn8fAAIlAAoK5xYMCQAUAgAlAAoK5xYMCQAUAgAAAA==.',
Zu='Zugwuff:BAAANQABCgMIAwAAAA==.Zugzuggler:BAABNQAECn80AAIUAAoKnRsPPgBKAgAUAAoKnRsPPgBKAgAAAA==.',
Zy='Zyrick:BAAANQABCggICwAAAA==.',
['Ät']='Ätticus:BAAANQADCgQIBAABNQAECgYIBAAOAAAAAA==.',
['Öv']='Överpöwered:BAAANQAECgQICQABNQAECgYIBAAOAAAAAA==.',
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
