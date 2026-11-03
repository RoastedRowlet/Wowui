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

local lookup = {'Paladin-Retribution','Priest-Holy','Priest-Shadow','Shaman-Restoration','Rogue-Assassination','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','Mage-Arcane','Hunter-BeastMastery','Unknown-Unknown','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Holy','Druid-Restoration','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','Druid-Guardian','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Druid-Balance','Warlock-Affliction','Paladin-Protection','Priest-Discipline','Monk-Mistweaver','DemonHunter-Devourer','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Shaman-Elemental',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Achannara:BAABNQAECn81AAIBAAkK+gXKvQAYAQABAAkK+gXKvQAYAQAAAA==.',
Ae='Aeloria:BAAANQADCgIIAgAAAA==.Aeoliana:BAABNQAECn8lAAICAAoKmRNTQgD3AQACAAoKmRNTQgD3AQAAAA==.',
Aj='Ajier:BAACNQAFFH8SAAICAAUK2g6IEgB5AQACAAUK2g6IEgB5AQA1AAQKf0QAAgIACgqcGXQ0ADcCAAIACgqcGXQ0ADcCAAAA.',
Al='Alaaris:BAAANQAECgEIAgAAAA==.Allcapwne:BAAANQADCggIIQAAAA==.Alucart:BAABNQAECn8cAAIDAAgK/A4TNACCAQADAAgK/A4TNACCAQAAAA==.',
An='Angela:BAABNQAECn8uAAICAAoKdBvCOACFAgACAAoKdBvCOACFAgAAAA==.Animalchin:BAAANQAECgIIAgABNQAECgoKIwAEAPcZAA==.Annadanna:BAAANQAECgUIEQAAAA==.Annalunà:BAAANQAECgMIBQAAAA==.Anogrips:BAAANQADCgYIBgAAAA==.Anoheals:BAAANQADCggIAgAAAA==.Anomok:BAAANQADCgEIAQAAAA==.Anowars:BAAANQAECgUICAAAAA==.Antithicus:BAAANQADCgYIBgAAAA==.',
Ap='Apeople:BAACNQAFFH8GAAIFAAIKEBRsCACWAAAFAAIKEBRsCACWAAA1AAQKfzsAAgUACgo6H4QFAJkCAAUACgo6H4QFAJkCAAAA.Apocalýpsè:BAABNQAECn8gAAIGAAkKqxVmCgDqAQAGAAkKqxVmCgDqAQAAAA==.Applebottum:BAAANQAECgYIEwAAAA==.Applebottumj:BAAANQAECgQIBQAAAA==.Appärition:BAABNQAECn83AAMHAAkKbxxLEgDiAQAIAAkKmBpePgDpAQAHAAYK/hdLEgDiAQAAAA==.',
Ar='Archillius:BAAANQADCgUIBQAAAA==.Arondael:BAABNQAECn8oAAIFAAkKzg28EgCFAQAFAAkKzg28EgCFAQAAAA==.',
As='Ashelaandrii:BAACNQAFFH8FAAIEAAIKpiCeHACxAAAEAAIKpiCeHACxAAA1AAQKfyMAAgQACQo2I54QAEADAAQACQo2I54QAEADAAAA.Astroglyde:BAAANQAECgQIBwAAAA==.Astryd:BAABNQAECn8dAAMJAAkKTgjNEwDbAAAJAAkKTgjNEwDbAAAKAAEKAAA4iwAAAAABNQAECgkJKQALABMIAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAABNQAECn82AAIMAAgKIg2JigBjAQAMAAgKIg2JigBjAQAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùvina:BAAANQADCgIJAwAAAA==.',
Ba='Badru:BAAANQAECgMIBAAAAA==.Bagmaster:BAACNQAFFH8IAAICAAQK2BWUEwA1AQACAAQK2BWUEwA1AQA1AAQKfzwAAgIACgp4JegGAI4DAAIACgp4JegGAI4DAAAA.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAABNQAECn8hAAIEAAoK8Rj1OwBvAgAEAAoK8Rj1OwBvAgAAAA==.Barie:BAAANQAECgQIBQABNQAECggIFAANAK4fAA==.Barthallomew:BAAANQAECgQIBAABNQAECgQICgAOAAAAAA==.Bayonetta:BAABNQAECn8zAAINAAoK0hmDRQAMAgANAAoK0hmDRQAMAgAAAA==.',
Be='Beefyshadow:BAAANQADCgEIAQAAAA==.Bellann:BAAANQAECgQIBgAAAA==.',
Bi='Bigflea:BAAANQADCgEIAQABNQAECgoKIwAEAPcZAA==.Birghid:BAAANQADCgEIAQAAAA==.Birgite:BAABNQAECn8aAAIPAAYKQwvVRQArAQAPAAYKQwvVRQArAQAAAA==.',
Bl='Blackdracula:BAAANQAECgYICAAAAA==.Blasphemar:BAAANQADCggIFAAAAA==.Blazefury:BAAANQAECgQICQAAAA==.Blazeknight:BAABNQAECn84AAIKAAoK0RjzLQA1AgAKAAoK0RjzLQA1AgAAAA==.Blazemaker:BAABNQAECn8xAAIQAAoKCxV/CgAgAgAQAAoKCxV/CgAgAgAAAA==.Blazemaster:BAAANQAECgYICwAAAA==.Bleach:BAAANQAECgEIAQAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.Bloodsylf:BAAANQADCgcICgABNQAECgkJFgARAMoSAA==.Blówpop:BAAANQADCgMIAwAAAA==.',
Bo='Bonecrushers:BAABNQAECn8lAAINAAgK0wvxkgBIAQANAAgK0wvxkgBIAQAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAABNQAECn8mAAISAAoK8hpRGQC/AgASAAoK8hpRGQC/AgAAAA==.Books:BAABNQAECn8ZAAITAAoKxRlMEgC9AgATAAoKxRlMEgC9AgABNQAECgoKJgASAPIaAA==.',
Br='Brainbread:BAABNQAECn8YAAIUAAgKZgt1mAAYAQAUAAgKZgt1mAAYAQABNQAECgoKRwAIADsYAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQAECgYIDwAAAA==.Broadside:BAABNQAECn8eAAINAAoKbiG8FQDRAgANAAoKbiG8FQDRAgAAAA==.Brokil:BAAANQAECgUIBgAAAA==.Brolic:BAAANQADCgEIAQAAAA==.Brolymorph:BAACNQAFFH8KAAIMAAUKdg7ZNQDtAAAMAAUKdg7ZNQDtAAA1AAQKfy4AAgwACgoyHlk3AEYCAAwACgoyHlk3AEYCAAAA.Brossiere:BAAANQADCgQIBQAAAA==.Brotemic:BAAANQAECgIIAwAAAA==.Broverheal:BAAANQAECgMIBwAAAA==.Bru:BAACNQAFFH8GAAICAAMKhBF4GwDTAAACAAMKhBF4GwDTAAA1AAQKfyoAAgIACgqMFEheAAYCAAIACgqMFEheAAYCAAAA.',
Bt='Bt:BAAANQADCgYIBgAAAA==.',
Bu='Bubbleoseven:BAAANQADCgEIAQAAAA==.Bullsmcgee:BAABNQAECn8rAAQVAAoKEB11FgANAgAVAAkKVB11FgANAgAWAAIKSRXPjQB/AAALAAEKMxvHggBMAAAAAA==.Burninglight:BAAANQADCgYIEQAAAA==.Burningtree:BAAANQAECgcIDwAAAA==.Buthunter:BAAANQAECgUICQAAAA==.',
['Bâ']='Bâhtilâ:BAAANQAECgYIAQAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECgoKbQAXAIEiAA==.',
Ca='Camamoonmana:BAABNQAECn8bAAMTAAoK5RF+JwDlAQATAAoK5RF+JwDlAQAYAAYKmgZ9PQDIAAAAAA==.Canonbalizer:BAAANQAECgQIBAABNQAECggIGAAVADMhAA==.Caplevi:BAABNQAECn80AAQZAAoKBxwGKQAoAgAZAAoKvRoGKQAoAgAaAAUKNws2BgDVAAAFAAQK4RT/RQBqAAAAAA==.Carrìon:BAAANQADCgEIAQAAAA==.Caskket:BAAANQAECgcIEQAAAA==.Catdog:BAAANQADCgYIBgAAAA==.Catechism:BAAANQAECgcIEwAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAACNQAFFH8FAAIKAAMKJRiVDwCZAAAKAAMKJRiVDwCZAAA1AAQKfzkAAgoACgqnIeENAKICAAoACgqnIeENAKICAAAA.',
Ch='Chaningtotèm:BAAANQADCgUICgAAAA==.Charan:BAAANQADCgYIDgAAAA==.Chickennuggi:BAAANQADCgQIBwABNQAFFAUIDwAVAD0jAA==.Chiphoof:BAABNQAECn8YAAIbAAgKdhFKGAB2AQAbAAgKdhFKGAB2AQAAAA==.Chopndot:BAABNQAECn8XAAILAAcK8AVjWwCvAAALAAcK8AVjWwCvAAAAAA==.',
Cl='Clarabuns:BAABNQAECn8WAAMSAAkKmRryQgBZAgASAAgKphnyQgBZAgABAAIKaRBrbQFxAAAAAA==.Clawdragoon:BAEBNQAECn8/AAMYAAoKZBvlEgDNAQAcAAoK+hqTJQCmAgAYAAoKEhPlEgDNAQAAAA==.',
Co='Corine:BAAANQADCgUIBgAAAA==.Corndogmatt:BAAANQADCgUICQAAAA==.',
Cr='Creatlach:BAACNQAFFH8XAAIEAAcK9BqeBwDdAQAEAAcK9BqeBwDdAQA1AAQKfz8AAgQACgpiJDsNAFYDAAQACgpiJDsNAFYDAAAA.Creatlachtwo:BAABNQAECn8UAAICAAoKEg8pPQANAgACAAoKEg8pPQANAgABNQAFFAcIFwAEAPQaAA==.Creeptoken:BAAANQADCgQIBQAAAA==.Crucifilth:BAAANQAECgEIAgAAAA==.Crystallight:BAABNQAECn8YAAQXAAgKfQWgBwBgAAAMAAgK8QMoOwEqAQAXAAIKGAagBwBgAAAQAAMKLwXgOgBTAAAAAA==.',
Cy='Cytherea:BAABNQAECn8WAAIBAAkK+QqtEgEAAQABAAkK+QqtEgEAAQAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgoKKAAFAP0TAA==.Dalinek:BAABNQAECn8lAAMFAAoKYR2UFwC/AgAFAAoKVReUFwC/AgAZAAQKrSLPRwCVAQAAAA==.Damah:BAAANQADCggIHgABNQADCggIHgAOAAAAAA==.Dandelo:BAAANQAECgEIAgAAAA==.Danicarkel:BAACNQAFFH8HAAMdAAMKIAsGAgDZAAAdAAMKIAsGAgDZAAAIAAEKAQazMQBBAAA1AAQKf0UABB0ACgquHCcCAA4DAB0ACgquHCcCAA4DAAcABArBCnMyAPsAAAgAAgqnC3YtAWIAAAAA.Dans:BAAANQAECgEIAQAAAA==.Darkdlord:BAABNQAECn8pAAMWAAoKwwprTAAmAQAWAAgK0QprTAAmAQALAAoKRwVlSwDlAAABNQAECgoKLwABAOIWAA==.Darthflea:BAAANQADCgEIAQABNQAECgoKIwAEAPcZAA==.Darío:BAAANQAECgIIAwABNQAECgQICgAOAAAAAA==.',
Dd='Ddpaladini:BAABNQAECn8vAAMBAAoK4hZLZQDKAQABAAoK4hZLZQDKAQAeAAkKlgerNwAtAQAAAA==.',
De='Deathtracker:BAABNQAECn8eAAINAAcK1Au2pQC6AQANAAcK1Au2pQC6AQAAAA==.Deathtrops:BAAANQAECgIIAgABNQAFFAcIIQAIAFkjAA==.Demindan:BAAANQAECgIIAgAAAA==.Demise:BAACNQAFFH8VAAMMAAcKdBH0EQDoAQAMAAYKoRL0EQDoAQAQAAEKwAzpDQBVAAA1AAQKf0QAAwwACgqTI9cbALoCAAwACgqTI9cbALoCABAAAQr3G0U8AE4AAAAA.Demontickler:BAAANQADCggIDQABNQAECgYIEAAOAAAAAA==.',
Di='Dianabol:BAABNQAECn8qAAIUAAkKShrERgC1AgAUAAkKShrERgC1AgABNQAECgoKNwAEAPQlAA==.Diego:BAAANQADCgYIDAAAAA==.Dirkuatah:BAAANQAECgQIBgAAAA==.Dista:BAACNQAFFH8JAAIIAAQK+xDqFQDLAAAIAAQK+xDqFQDLAAA1AAQKf0QAAggACgobIHkQANACAAgACgobIHkQANACAAAA.Divinebovine:BAAANQAECgEIAQAAAA==.Divinedragon:BAABNQAECn8xAAMDAAoKqRaUGwB7AQADAAkKdBWUGwB7AQAfAAQKvBoeFADnAAAAAA==.',
Do='Doboy:BAAANQAECgEIAQAAAA==.Dotsncandies:BAAANQAECgIIAgAAAA==.Doublevegan:BAAANQADCgMJAwAAAA==.',
Dr='Draconum:BAAANQADCgEIAQAAAA==.Drakin:BAABNQAECn8WAAIBAAoK/A6cqADPAQABAAoK/A6cqADPAQAAAA==.Drawbridge:BAAANQADCgYIDwAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAACNQAFFH8MAAIEAAQK6xegDgAsAQAEAAQK6xegDgAsAQA1AAQKfzQAAgQACgoGFo5PACcCAAQACgoGFo5PACcCAAAA.Drinkoolaide:BAAANQAECgcIDgABNQAFFAQIDAAEAOsXAA==.Drybooger:BAAANQADCgEIAQAAAA==.',
Du='Dumb:BAAANQAECgEIAQAAAA==.Dunamis:BAABNQAECn8lAAIMAAkK6R7KWQDMAgAMAAkK6R7KWQDMAgAAAA==.Dungodon:BAAANQAECgMIAQAAAA==.Durrt:BAAANQAECgYIEAAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAACNQAFFH8PAAMPAAYK4BaRDgBUAQAPAAUKoRCRDgBUAQANAAMK6B6SKACWAAA1AAQKfzwAAw0ACgrpJV8RAFwDAA0ACgrpJV8RAFwDAA8ACgqvH+MKAGkCAAAA.',
['Dó']='Dóòmsday:BAAANQADCgYIBgAAAA==.',
Ei='Einaria:BAAANQAECgIIAwABNQAECgoKLgAMAOccAA==.',
El='Eldrene:BAABNQAECn8uAAIMAAoK5xxTLgBoAgAMAAoK5xxTLgBoAgAAAA==.Elizalde:BAAANQAECgYIEAAAAA==.Ellexi:BAAANQAECgUIDwAAAA==.Eltunco:BAAANQADCgEIAQAAAA==.Elyseia:BAABNQAECn8iAAINAAkKvw8JewAYAgANAAkKvw8JewAYAgAAAA==.',
En='Enpower:BAAANQAECgQICgABNQAFFAQICgAgAEkIAA==.',
Ep='Epicsause:BAAANQAECggIDAAAAA==.',
Es='Escata:BAAANQAECgQICAAAAA==.Esdailongwe:BAAANQADCgYIDQAAAA==.Españamor:BAEBNQAECn8oAAMhAAoKPRGIHwBwAQAhAAoKWBCIHwBwAQAJAAgKjgzcGAAkAQAAAA==.',
Eu='Eunite:BAABNQAECn9rAAIVAAoK0B2kKACWAgAVAAoK0B2kKACWAgAAAA==.',
Fa='Falkorne:BAABNQAECn8WAAMGAAcKqwpxGAAOAQAGAAcKGApxGAAOAQAUAAUKrQe4wADAAAABNQAECgoKKQAgALQYAA==.Farael:BAAANQADCgYICAAAAA==.Fashah:BAAANQAECgIIBAAAAA==.Fatalmann:BAAANQAECgIIAgAAAA==.',
Fe='Felmoo:BAABNQAECn8XAAIYAAkKdgZeKwD4AAAYAAkKdgZeKwD4AAAAAA==.Felorc:BAABNQAECn8gAAMGAAkKJAUCKwDhAAAGAAkKJAUCKwDhAAAUAAIKKAIbTQE6AAABNQAECgkJKQALABMIAA==.Feralhorn:BAAANQAECggIEAAAAA==.',
Fi='Fintan:BAAANQAECgUIBQABNQAFFAcIFwAEAPQaAA==.Fishypirks:BAAANQADCgEIAQAAAA==.',
Fo='Forsakenemp:BAAANQAECggIDwABNQAECgoKLwABAOIWAA==.',
Fr='Frassk:BAABNQAECn81AAMIAAoKZhA6awBcAQAIAAoK9g46awBcAQAHAAIKuRO/GAB9AAAAAA==.Frigid:BAAANQADCgcIBwAAAA==.Froggystyle:BAAANQAECggIEAAAAA==.Frozenheart:BAABNQAECn8pAAMLAAkKEwi5dwAZAQALAAkKEwi5dwAZAQAWAAQKZgaGiABjAAAAAA==.Fruk:BAAANQADCgUIBQAAAA==.Frösting:BAAANQADCgYIBgABNQAECgoKHwAiAJ0RAA==.',
Ft='Ftx:BAABNQAECn8sAAIUAAkKxiE3SgCqAgAUAAkKxiE3SgCqAgAAAA==.',
Fu='Furfoxxsakes:BAAANQADCgEIAQAAAA==.',
Ga='Garbarn:BAAANQADCgcIDwAAAA==.',
Ge='Gelystine:BAAANQADCgIIAwAAAA==.Geminichi:BAACNQAFFH8KAAIgAAQKSQhIBQD+AAAgAAQKSQhIBQD+AAA1AAQKfzkAAyAACgqfHawIAJkCACAACgqfHawIAJkCACMAAgqFEClqADcAAAAA.Geminishadow:BAABNQAECn8WAAMZAAoKrAtlTgB7AQAZAAoK4QllTgB7AQAFAAUKcw2iYAAyAQAAAA==.',
Gh='Ghauri:BAAANQADCgYJBgAAAA==.Ghorza:BAAANQADCgYIBwAAAA==.',
Gi='Gia:BAABNQAECn85AAIgAAkKax0ZCACuAgAgAAkKax0ZCACuAgAAAA==.Gigasauce:BAAANQAECgEIAQAAAA==.Giraffage:BAABNQAECn8WAAIMAAcK6Q9j4ADIAQAMAAcK6Q9j4ADIAQABNQAECgcICQAOAAAAAA==.',
Go='Gobdklicious:BAAANQADCgEIAQAAAA==.Golgroth:BAAANQADCgQJBAAAAA==.Gorearrow:BAACNQAFFH8GAAINAAMKdxR0GgCgAAANAAMKdxR0GgCgAAA1AAQKfzsAAg0ACgryH2AzANICAA0ACgryH2AzANICAAAA.',
Gr='Griffoo:BAAANQADCgEIAgAAAA==.Grimmtotem:BAAANQAECggIEAAAAA==.Groggyfroggy:BAAANQADCgMJAwAAAA==.Grognaak:BAAANQADCgMIBAAAAA==.Grralt:BAAANQAECgIIAgABNQADCggIHgAOAAAAAA==.Grís:BAABNQAECn8tAAMUAAoKpxeTaABWAgAUAAoKpxeTaABWAgAGAAMKCA3uMwCXAAAAAA==.',
Gu='Gumbuz:BAAANQAECgQIBAAAAA==.Gunafistya:BAAANQAECgMIBQAAAA==.',
Ha='Hanwi:BAAANQAECggICAAAAA==.Harrier:BAAANQADCgYICgABNQAECggIGAAbAHYRAA==.Hazed:BAABNQAECn8XAAIMAAoKfQzvYADJAQAMAAoKfQzvYADJAQAAAA==.Hazyblades:BAAANQAECgIIAgAAAA==.Hazzaa:BAAANQAECgcICwAAAA==.',
He='Healzforbeer:BAAANQADCgUIBQAAAA==.Heila:BAAANQAECgYICgAAAA==.Henso:BAAANQAFFAIIAgABNQAFFAQICgAgAEkIAA==.Herioffy:BAAANQADCgEIAQAAAA==.Hexxan:BAAANQADCgYIBgAAAA==.',
Hi='Hiawatha:BAAANQADCgQIBAAAAA==.Hiver:BAAANQAECgEIAQAAAA==.',
Ho='Holier:BAABNQAECn9DAAIBAAoKHBDUbQC1AQABAAoKHBDUbQC1AQAAAA==.Holybishh:BAAANQAECgUIBQAAAA==.Holyregerts:BAABNQAECn8jAAMDAAoKmxEwJAAPAgADAAkKQRAwJAAPAgACAAgK4BmDcQDIAQAAAA==.Hongsh:BAAANQADCgEIAQAAAA==.Honk:BAAANQAECggIEwAAAA==.Hoochurcooch:BAAANQAECgQIBAAAAA==.Hoosnext:BAAANQAECgEIAQAAAA==.Hopperstotem:BAAANQAECgMIAwABNQAECgoKHgANAG4hAA==.',
Hu='Hulo:BAAANQAECgMIAwAAAA==.Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQAECgIIBAAAAA==.',
Il='Illari:BAAANQAECgEIAQAAAA==.Illumi:BAAANQADCgEIAQAAAA==.',
Im='Imbatmann:BAAANQAECgEIAQAAAA==.',
In='Indrà:BAAANQADCgQIBQAAAA==.Infamus:BAAANQAECgIIBQAAAA==.Invysion:BAACNQAFFH8SAAMfAAUKLAOWAQApAQAfAAUKLAOWAQApAQACAAIKyAFmJwBxAAA1AAQKf0QAAx8ACgplFP0CACoCAB8ACgosFP0CACoCAAIAAQqoBlDhADIAAAAA.',
Is='Ishara:BAAANQAECgEIAgABNQAECgoKLgAMAOccAA==.Islander:BAABNQAECn8YAAISAAgKVBHoQQDZAQASAAgKVBHoQQDZAQAAAA==.',
Ja='Jackychang:BAABNQAECn8cAAIZAAkKGQ5hGwD7AQAZAAkKGQ5hGwD7AQAAAA==.Jaidess:BAAANQADCggIDgAAAA==.Jakeypoo:BAAANQAECgQICgAAAA==.Jayskiller:BAAANQADCgUIBQAAAA==.',
Je='Jellybea:BAACNQAFFH8GAAICAAMKXQvWHADHAAACAAMKXQvWHADHAAA1AAQKfy8AAwIACgq5HnUrALsCAAIACgq5HnUrALsCAAMAAwpSDHZqAFkAAAAA.',
Ji='Jimmee:BAAANQADCgIIAgAAAA==.',
Ju='Jukoti:BAAANQADCgEIAgAAAA==.Junglebrew:BAAANQAECgUIBQAAAA==.Junglepino:BAAANQAECgEIAQAAAA==.Jurisdiction:BAABNQAECn8cAAIBAAgKfgdN6QDRAAABAAgKfgdN6QDRAAAAAA==.',
Ka='Kabea:BAAANQADCgEIAQAAAA==.Kadath:BAAANQADCgEIAwAAAA==.Kaizokuo:BAABNQAECn8xAAIjAAoKDhzTDwDoAgAjAAoKDhzTDwDoAgAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kanalz:BAAANQAECgUIBQAAAA==.Kappowee:BAAANQAECgEIAQAAAA==.Karambit:BAAANQAECgcIBwAAAA==.Kasey:BAABNQAECn8VAAIBAAYK8B4guwCnAQABAAYK8B4guwCnAQAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keggstand:BAAANQAECgYIBgAAAA==.Keho:BAABNQAECn8aAAIkAAgKbAREFACzAAAkAAgKbAREFACzAAAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAACNQAFFH8QAAMhAAUKNRRTCADFAAAKAAQKNRSjDwAMAQAhAAQKughTCADFAAA1AAQKf0EAAyEACgpjHwwLAIECAAoACgo/G9ghAI0CACEACgqyHgwLAIECAAE1AAQKBwgJAA4AAAAA.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kickdrop:BAAANQADCgQIBAAAAA==.Kilgreed:BAAANQADCgYIDgAAAA==.Killaban:BAAANQAECgcIBwAAAA==.Killbydeath:BAABNQAECn8YAAQVAAgKMyFGHQDHAQAVAAgKMh9GHQDHAQALAAIKax9anACiAAAWAAIKjxR8dwCQAAAAAA==.Kimberlyhárt:BAAANQAECgYIEAAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYIEAAOAAAAAA==.Kimdruid:BAAANQADCgQIBQAAAA==.Kissmydots:BAABNQAECn9qAAIIAAoK7Rx0IABsAgAIAAoK7Rx0IABsAgAAAA==.',
Ko='Kohman:BAABNQAECn9HAAMIAAoKOxhAMQDDAgAIAAoKOxhAMQDDAgAHAAMKtA1xUgCIAAAAAA==.Komatose:BAAANQADCgYIBgAAAA==.Kong:BAAANQADCgIIAwAAAA==.',
Kr='Krftpnk:BAACNQAFFH8hAAIKAAgKRyCBAQC0AgAKAAgKRyCBAQC0AgA1AAQKf0AAAgoACgrqJi4CANUDAAoACgrqJi4CANUDAAAA.Kricket:BAAANQAECgEIAgAAAA==.Kronas:BAABNQAECn8XAAMNAAkKHBQ3jwDrAQANAAkKHBQ3jwDrAQAPAAEKjQM9ZQAsAAAAAA==.Kronosity:BAABNQAECn80AAIeAAoK7R+mCgDwAgAeAAoK7R+mCgDwAgABNQAFFAQICQALAG8fAA==.Kronotality:BAACNQAFFH8JAAILAAQKbx8dCwAOAQALAAQKbx8dCwAOAQA1AAQKf0gAAgsACgrvI8MFAJcDAAsACgrvI8MFAJcDAAAA.Kronotekken:BAAANQAECgEIAQABNQAFFAQICQALAG8fAA==.Kronotide:BAAANQADCgQIBAABNQAFFAQICQALAG8fAA==.',
Ku='Kungfukittn:BAABNQAECn8dAAIjAAcKIxagKwC+AQAjAAcKIxagKwC+AQAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQAECggIEQAAAA==.Kyojuro:BAAANQADCgEIAQAAAA==.',
Kz='Kzorx:BAAANQAECgEIAwAAAA==.',
La='Laimaster:BAAANQAECgQIBAAAAA==.Lakiri:BAABNQAECn8vAAIiAAgKsxLvFwDpAQAiAAgKsxLvFwDpAQAAAA==.Landaeda:BAAANQAECgUIBQAAAA==.Lascivia:BAACNQAFFH8FAAIGAAIK/RvIAwCeAAAGAAIK/RvIAwCeAAA1AAQKfysAAwYACgqYIVoGAAIDAAYACgqYIVoGAAIDACUABAoAGPsYABIBAAAA.Latrice:BAAANQAECgcIBwABNQAFFAcIEwAQAOAdAA==.Laylahh:BAAANQADCgQIBAAAAA==.Lazereyes:BAAANQAECgYICwAAAA==.',
Le='Leademon:BAABNQAECn8gAAIKAAoK5he4MAAiAgAKAAoK5he4MAAiAgAAAA==.Leadmln:BAAANQAECgYIDAABNQAECgoKIAAKAOYXAA==.Lebwonsamdi:BAAANQAECgUIBQABNQAECgoKLQAUAKcXAA==.Lethalkrits:BAAANQAECggIAgAAAA==.',
Li='Lighterfluîd:BAAANQADCgEIAQABNQAECgoKLgAgAFEfAA==.Ligmadk:BAAANQADCgUIBQABNQAFFAQIBwAKAIMIAA==.Lilbeebs:BAAANQAECgYIBwAAAA==.Lileth:BAAANQABCgIIBAAAAA==.Lilflea:BAABNQAECn8jAAMEAAoK9xliUQAgAgAEAAoK9xliUQAgAgAmAAEKAAD5TAEnAAAAAA==.Lillidari:BAAANQAECgcICQABNQAECgkJJgALACwkAA==.Lilzuki:BAAANQAECgcIDgAAAA==.Lilïth:BAABNQAECn8mAAILAAkKLCQkCwBbAwALAAkKLCQkCwBbAwAAAA==.Linguine:BAAANQADCggICQABNQAFFAQICgADAHQNAA==.Lisalisa:BAABNQAECn8nAAIEAAkKbhJjUgCXAQAEAAkKbhJjUgCXAQAAAA==.Littlej:BAAANQAECgQJBAAAAA==.Littlejohn:BAABNQAECn8pAAIgAAoKtBjtEABwAgAgAAoKtBjtEABwAgAAAA==.',
Lo='Logantis:BAABNQAECn8eAAIUAAkKJxY1MwBKAgAUAAkKJxY1MwBKAgAAAA==.Logaothe:BAABNQAECn8cAAIBAAYKJQpOAgEbAQABAAYKJQpOAgEbAQAAAA==.Lokee:BAAANQADCgUIBQAAAA==.',
Lu='Lucky:BAABNQAECn8XAAIKAAgKHRAWMQBSAQAKAAgKHRAWMQBSAQAAAA==.Lukethywalkr:BAAANQAECgIIAgAAAA==.Lularia:BAAANQADCgYIDgAAAA==.Lunaa:BAAANQAECgQIBwAAAA==.Lusid:BAAANQAECgEIAQAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Makagh:BAAANQAECgEIAgAAAA==.Malakyte:BAAANQAECgIIAgAAAA==.Maliciousrot:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQIBQAAAA==.Marona:BAAANQAECggIAQAAAA==.Marshail:BAAANQAECgUIBgAAAA==.',
Me='Medikus:BAABNQAECn8yAAMEAAoKmBtkGgC3AgAEAAoKmBtkGgC3AgAmAAEKKQSC6QAuAAAAAA==.Megajoo:BAABNQAECn8VAAMTAAoKFA84GQD4AQATAAoKFA84GQD4AQAcAAEK4QSTvwAiAAAAAA==.Melkinov:BAAANQAECgEIAgAAAA==.Merryl:BAAANQAECgUIBwAAAA==.',
Mf='Mfive:BAAANQAECgQIBAAAAA==.',
Mi='Mike:BAEBNQAECn8cAAIMAAkK4iGtUQDdAgAMAAkK4iGtUQDdAgAAAA==.Milkjugs:BAAANQAECgMIBwABNQAECgoKIwAEAPcZAA==.Minijeangen:BAAANQAECgMJAwAAAA==.Missluana:BAAANQADCgEIAQAAAA==.Mizshankalot:BAAANQAECgMIAwABNQAECgoKLwABAOIWAA==.',
Mo='Mockra:BAABNQAECn9AAAIMAAgKGhZxrAApAgAMAAgKGhZxrAApAgAAAA==.Moistmunnky:BAAANQAECgQIDAAAAA==.Montera:BAEANQAFFAIIAgABNQAECgoKKAAhAD0RAA==.Moohammered:BAABNQAECn8uAAIBAAoKnBWZSgAWAgABAAoKnBWZSgAWAgAAAA==.Moolou:BAACNQAFFH8GAAIeAAMKBAxZBgCuAAAeAAMKBAxZBgCuAAA1AAQKfywAAh4ACgr2G+0QAJECAB4ACgr2G+0QAJECAAAA.Mootarded:BAABNQAECn8UAAIeAAkK5wSZOwCRAAAeAAkK5wSZOwCRAAABNQAECgkJKQALABMIAA==.Mordiggian:BAABNQAECn89AAMLAAoKjyTQDwAvAwALAAkKbyXQDwAvAwAVAAkKlSMFGQD3AgAAAA==.Morechie:BAABNQAECn8yAAMdAAoK6A8kCQD0AQAdAAkKBRAkCQD0AQAIAAMKYwvt2gBuAAAAAA==.Morganaj:BAAANQAECgQICgAAAA==.Morgatho:BAAANQADCgEIAQAAAA==.Morsz:BAAANQAECgUICAAAAA==.Mortiferon:BAABNQAECn8jAAIVAAkKShrUOwAyAgAVAAkKShrUOwAyAgAAAA==.',
Mu='Munnky:BAAANQADCgMIBQABNQAECgQIDAAOAAAAAA==.Munnkypox:BAAANQAECgIIBAABNQAECgQIDAAOAAAAAA==.Murderella:BAAANQADCgYIBwAAAA==.Muriggs:BAAANQAECgMIAwAAAA==.Murkhoof:BAAANQADCgYIBgABNQAECggIGAAbAHYRAA==.',
['Mö']='Mörgänä:BAAANQADCggIEQAAAA==.',
Na='Nakovii:BAAANQAECgUIBQAAAA==.Nakovy:BAAANQAECgQIBAAAAA==.Napa:BAAANQAECgUIBQABNQAFFAcIFAAEAKcXAA==.Narga:BAAANQADCgEIAQAAAA==.Nascerathel:BAAANQAECgQICwAAAA==.Nasmina:BAAANQAECggIAQAAAA==.Naturebull:BAAANQADCgEIAQAAAA==.',
Ne='Nealite:BAAANQADCgYICAAAAA==.Neerem:BAAANQADCgEIAQAAAA==.Neferata:BAABNQAECn9EAAMIAAoKFRyANwCuAgAIAAoKFRyANwCuAgAHAAYKbgvNJwA6AQAAAA==.Nerrisa:BAAANQADCggIDwAAAA==.Nertmage:BAABNQAECn9tAAQXAAoKgSJQAACfAwAXAAoKgSJQAACfAwAMAAIKAA7+vAFEAAAQAAEKThmMNAA8AAAAAA==.Neublood:BAAANQAECgQIBwAAAA==.',
Ni='Nicodemus:BAAANQAECgYICwAAAA==.Nineiota:BAABNQAECn8tAAMTAAoK6BrJEwBEAgATAAoK6BrJEwBEAgAcAAEKzA1yegA2AAAAAA==.',
No='Noblewarrior:BAACNQAFFH8gAAIUAAcK7hQBEQCtAQAUAAcK7hQBEQCtAQA1AAQKf0kAAxQACgo1JLYKAC4DABQACgo1JLYKAC4DACUAAQq2HSAkAFUAAAAA.Nobukawaii:BAAANQAECgMIAwAAAA==.Noctilus:BAAANQADCgcIFwAAAA==.Noke:BAAANQAECgIJAgAAAA==.Noril:BAAANQADCgUIBQAAAA==.Notakoala:BAACNQAFFH8QAAIcAAYKABaZEABhAQAcAAYKABaZEABhAQA1AAQKfz4AAhwACgqPIpEOAFUDABwACgqPIpEOAFUDAAAA.Nothnx:BAACNQAFFH8MAAINAAUK4xJ/BwBGAQANAAUK4xJ/BwBGAQA1AAQKfzoAAg0ACgrZHmsbALECAA0ACgrZHmsbALECAAAA.Notillidan:BAAANQADCgYICgAAAA==.Notoriouspat:BAAANQAECgcIDwAAAA==.Novia:BAAANQAECggIEgABNQAECgoKLQAUAKcXAA==.Noxeternis:BAACNQAFFH8IAAMCAAQKIQsaFwANAQACAAQKIQsaFwANAQADAAEKfBChEgBLAAA1AAQKfzYABAMACgr6GTIhAC4CAAMACQoZGTIhAC4CAAIABQrYG1RzAEQBAB8AAgoyBiAkAEoAAAAA.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
Ny='Nyxandra:BAAANQADCgYIDgAAAA==.',
['Ní']='Níghtfall:BAAANQADCgUICwAAAA==.Nínebreaker:BAAANQAECgEIAQAAAA==.',
['Nü']='Nüll:BAAANQADCgYICgAAAA==.',
Ob='Obern:BAABNQAECn8eAAIRAAoKmBQ5BQBzAgARAAoKmBQ5BQBzAgAAAA==.Obeysnapback:BAAANQADCgMIBAAAAA==.Oblïna:BAAANQAECgUIEAAAAA==.',
Od='Oddishh:BAABNQAECn8fAAMWAAoK4w73JwDeAQAWAAoK4w73JwDeAQALAAYK6wivfQADAQAAAA==.',
Ol='Olleg:BAAANQADCgYICwAAAA==.',
Om='Omnicarkel:BAAANQADCgcIDAAAAA==.',
On='Onsen:BAABNQAECn8sAAIBAAoKuRkaWwCHAgABAAoKuRkaWwCHAgABNQAECgoKRwAIADsYAA==.',
Or='Oresties:BAAANQADCggICAAAAA==.Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQJBAAAAA==.',
Ou='Outwithabang:BAAANQAECgMIAwAAAA==.',
Pa='Pajl:BAABNQAECn8rAAIBAAoKlyOtDQCXAwABAAoKlyOtDQCXAwABNQAFFAcIDwAWAKMeAA==.Pandablaze:BAAANQAECgQIBQAAAA==.Pandajoy:BAAANQADCgEIAQAAAA==.Panterarey:BAAANQAECgIIAgAAAA==.Papalego:BAAANQADCgEIAQAAAA==.Papanurrgle:BAAANQAECgUICQAAAA==.Papazilla:BAAANQAECgMJAwAAAA==.Parakka:BAAANQAECgQIBAAAAA==.Patak:BAAANQADCgQIBQAAAA==.Pawp:BAAANQAECgcIEwABNQAECgoKNwACACcaAA==.Paxiel:BAAANQAECgQICAAAAA==.',
Pe='Pearagon:BAAANQAECggIEQABNQAFFAcIFAAEAKcXAA==.Pepsidew:BAAANQAECggICwAAAA==.Pepsisprite:BAABNQAECn8fAAICAAkKZhqVMABLAgACAAkKZhqVMABLAgAAAA==.',
Ph='Phdbeef:BAAANQAECgEIAQABNQAECgkJJgALACwkAA==.Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQAECgIIAgAAAA==.',
Pi='Pickledeggs:BAAANQADCgEIAQAAAA==.Picklez:BAABNQAECn8jAAIWAAgKvxbTMwCZAQAWAAgKvxbTMwCZAQAAAA==.',
Pl='Plaguemother:BAAANQADCgEIAQAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBQAAAA==.Portwings:BAAANQAECgEIAwAAAA==.',
Ps='Psyop:BAAANQADCggIGAABNQAECgoKSQACAD4iAA==.Psyrax:BAAANQAECgQICgAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Rashun:BAAANQAECgMIAwAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDwAAAA==.Redkoala:BAABNQAECn8XAAIMAAYKjgaAywDnAAAMAAYKjgaAywDnAAABNQAFFAYIEAAcAAAWAA==.Regrets:BAAANQAECgQIBAABNQAECgoKIwADAJsRAA==.Repete:BAAANQAECgQIBAAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECn9rAAIQAAoKwSESAgBaAwAQAAoKwSESAgBaAwAAAA==.Reven:BAAANQAECgYICAAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ri='Riivan:BAAANQAECgIIAQAAAA==.Rirugiliyang:BAAANQAECgEIAQAAAA==.Rivian:BAAANQAECgMIBgABNQAECggIGAASAFQRAA==.',
Ro='Roardon:BAAANQADCggIDwAAAA==.Roflmfao:BAAANQADCggICAAAAA==.Roguè:BAAANQAECgQICgAAAA==.Rollinburn:BAAANQADCgUJBgAAAA==.Romanoff:BAABNQAECn8oAAMFAAoK/ROaPQDZAQAFAAcKBxOaPQDZAQAZAAgKjBPySwCEAQAAAA==.Rosearcana:BAAANQAECgEIAQAAAA==.',
Ry='Ryokhan:BAAANQAECggIDAAAAA==.',
['Rô']='Rôx:BAAANQADCgcIBwABNQAECgoKaQASAL0bAA==.',
['Rõ']='Rõx:BAABNQAECn9pAAMSAAoKvRtOLwCpAgASAAoKvRtOLwCpAgABAAMKBw7aPAFhAAAAAA==.',
Sa='Sackoss:BAABNQAECn8cAAISAAgKwBaQXwD6AQASAAgKwBaQXwD6AQAAAA==.Saffronspark:BAAANQAECgUIEAABNQAECgoKPQAjADEbAA==.Sainsei:BAABNQAECn8ZAAMkAAgKGxPFHAAbAQAkAAYKnA/FHAAbAQAjAAUKKhBXNgC4AAABNQAECgoKLQAUAKcXAA==.Sakata:BAAANQADCgIIAgABNQAECggIGAAbAHYRAA==.Sandwitch:BAABNQAECn9rAAMHAAoKsRNuDwAGAgAIAAoKPBIjYAA4AgAHAAgKTxBuDwAGAgAAAA==.Sargatanas:BAABNQAECn8jAAILAAkK8gw/UgCsAQALAAkK8gw/UgCsAQAAAA==.Sars:BAAANQADCgUIBgABNQAECgQIBwAOAAAAAA==.',
Sc='Scarcroww:BAAANQADCgMIAwABNQAECgoKJgAMAGofAA==.Schrodinger:BAAANQAECgIIBAAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Selline:BAAANQADCgYIBwAAAA==.Septicflësh:BAAANQAECggICAAAAA==.Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAABNQAECn8qAAIGAAkKvxINEAB8AQAGAAkKvxINEAB8AQAAAA==.',
Sh='Shadrad:BAACNQAFFH8FAAIBAAMKsRVzDgDqAAABAAMKsRVzDgDqAAA1AAQKfzIAAwEACgpnIAUiALYCAAEACgpnIAUiALYCABIABgrcA/nGAO0AAAAA.Shallot:BAABNQAECn8zAAIMAAoK3SDdNwAYAwAMAAoK3SDdNwAYAwAAAA==.Shammoo:BAABNQAECn8WAAImAAkKHRQAYAACAgAmAAkKHRQAYAACAgABNQAFFAQIBgABAMYLAA==.Shammyd:BAABNQAECn8dAAImAAoK5QMgcwD3AAAmAAoK5QMgcwD3AAAAAA==.Shantz:BAABNQAECn8pAAILAAkKzApZOQA0AQALAAkKzApZOQA0AQAAAA==.Sharprot:BAAANQAECgYIBgABNQAECgkJHgABAHUZAA==.Shiftface:BAAANQADCggIDgABNQAECgkJFgABAPkKAA==.Shiftmypants:BAABNQAECn8iAAIcAAoK3BZEGAAaAgAcAAoK3BZEGAAaAgAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Si='Sinterdeath:BAABNQAECn8VAAMVAAcK7AjkgwAQAQAVAAcK7AjkgwAQAQAWAAQKTwWugwBuAAAAAA==.',
Sk='Skatervan:BAAANQAECgUIBQABNQAECgoKRwADAFkdAA==.Skylie:BAAANQADCgYIDwAAAA==.',
Sl='Sloppyjoes:BAAANQADCgEIAQAAAA==.Slushpuppy:BAAANQAECgIIAgAAAA==.',
Sm='Smallpaladin:BAAANQAECgEIAQAAAA==.Smorthian:BAAANQAECgQIDwAAAA==.',
Sn='Sniffinsteak:BAAANQAECgYJEAAAAA==.Snoosnooftww:BAAANQAECgIIAgAAAA==.',
So='Solas:BAABNQAECn8fAAICAAcKMxnQPwACAgACAAcKMxnQPwACAgAAAA==.Sonarael:BAAANQAECgQIBQABNQAECgoKLgAMAOccAA==.Sondeltis:BAAANQAECgQIBQAAAA==.Soryan:BAAANQAECgUIBQAAAA==.',
Sp='Spankenstine:BAABNQAECn8eAAIBAAkKdRktbQBXAgABAAkKdRktbQBXAgAAAA==.Sparkyy:BAAANQAECgIIAwAAAA==.Sphaeram:BAAANQAECgcICAAAAA==.Spicypepsi:BAAANQADCgEIAgAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.Spiritnail:BAAANQADCgEIAQAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAABNQAECn8zAAIBAAoKXCHzHgDGAgABAAoKXCHzHgDGAgAAAA==.Stinkydeathy:BAAANQADCgYJBgABNQAECgIIAgAOAAAAAA==.Stinkydragon:BAAANQAECgIIAgAAAA==.Stormknight:BAAANQAECgYICwAAAA==.Stormpoo:BAAANQAECgIIBAAAAA==.',
Su='Suneater:BAABNQAECn8qAAISAAoKlR8rDgAtAwASAAoKlR8rDgAtAwAAAA==.Supergenius:BAAANQADCgEIAQAAAA==.Superpi:BAAANQADCgYIBgABNQAECgUICAAOAAAAAA==.Superret:BAAANQAECgUICAAAAA==.Surotor:BAAANQADCgQICAAAAA==.Susano:BAAANQAECgEIAQAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAABNQAECn8eAAIBAAkKWwxJlABjAQABAAkKWwxJlABjAQAAAA==.',
Sw='Swíper:BAACNQAFFH8FAAIFAAIKLA8iFwCUAAAFAAIKLA8iFwCUAAA1AAQKfy8AAwUACgogHnkIAFADAAUACgogHnkIAFADABkABQq1CTA4APcAAAAA.',
Sy='Sylphièl:BAACNQAFFH8QAAMZAAcKyweaDAACAQAZAAYKtwiaDAACAQAFAAEKGwTHDwA8AAA1AAQKfzkAAxkACgomHMcWAKECABkACQomHMcWAKECAAUACQoxCflBAMMBAAAA.',
['Sö']='Sörceress:BAAANQADCgQIBAAAAA==.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgcIDgAAAA==.Talixis:BAAANQADCgYIBwAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECn8oAAIBAAkKmiJpLAAWAwABAAkKmiJpLAAWAwAAAA==.Tankenstine:BAABNQAECn8pAAIUAAgKtBJMfABZAQAUAAgKtBJMfABZAQABNQAECgkJHgABAHUZAA==.Tanktop:BAAANQADCggIDwAAAA==.Tastymilk:BAAANQAECgcICQAAAA==.Tawnii:BAAANQAECgMIBAAAAA==.Taírn:BAAANQAECgQIBAAAAA==.',
Te='Tenderloin:BAABNQAECn8WAAMKAAcKdA5+VQA4AQAKAAYKtAp+VQA4AQAJAAQKWhDhIwCgAAAAAA==.',
Th='Thanitose:BAAANQAECgUIEgAAAA==.Thevelo:BAAANQAECgYICgABNQAECgkJFgARAMoSAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thornwyn:BAAANQAECggIEwAAAA==.Thors:BAAANQADCgQIBAAAAA==.Thorul:BAAANQAECgcIDQAAAA==.Thundurus:BAACNQAFFH8MAAImAAMKWwejGgB9AAAmAAMKWwejGgB9AAA1AAQKfz0AAiYACgrqFwlGAF4CACYACgrqFwlGAF4CAAAA.',
Ti='Timmayy:BAABNQAECn8YAAIIAAkKrg1DTgCxAQAIAAkKrg1DTgCxAQABNQAECgoKKQAgALQYAA==.Tindrill:BAAANQAECgMIAwABNQAECgoKKwATAL0iAA==.Tinggoskrrah:BAAANQADCggIFAAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAABNQAECn8lAAIUAAgKgw9sswCcAQAUAAgKgw9sswCcAQAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAgIIQAKAEcgAA==.Totemagoat:BAACNQAFFH8LAAMEAAcKCxDyDQBuAQAEAAcKCxDyDQBuAQAmAAEKsQXlMgBEAAA1AAQKf0UAAwQACgomIoMWAB0DAAQACgomIoMWAB0DACYACArWFtBgAP8BAAAA.',
Tr='Tracula:BAAANQADCgEIAQAAAA==.Treefist:BAAANQAECgYIBgAAAA==.Trollfetus:BAAANQADCgEIAQAAAA==.Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAACNQAFFH8KAAITAAQKcAt/CwC+AAATAAQKcAt/CwC+AAA1AAQKfzYAAxMACgqSFggdAEsCABMACgqSFggdAEsCABwAAwpMAkBwAE0AAAAA.',
Un='Undeadkiels:BAAANQADCggICAABNQAECgoKLwABAOIWAA==.Undeadmonks:BAAANQADCgYIBwAAAA==.',
Ur='Uraharakun:BAAANQAECgUIDgABNQAECgoKRwAeAKIVAA==.',
Va='Vagalion:BAABNQAECn8hAAQiAAoK3g/REgCkAQAiAAcKexLREgCkAQAmAAgKFQkEbQAHAQAEAAUK+gyJuAD7AAAAAA==.Valdanyr:BAAANQAECgUICQAAAA==.Vale:BAAANQAECgMIAwAAAA==.Valeshot:BAABNQAECn8sAAINAAoKcQ1+dwAgAgANAAoKcQ1+dwAgAgAAAA==.Valimyr:BAAANQABCgMIBAAAAA==.Valkillrie:BAABNQAECn8dAAMSAAoKzhZLIQCGAgASAAoKzhZLIQCGAgABAAIKXgq9egFhAAAAAA==.Valkor:BAAANQADCgEIAQAAAA==.Valohir:BAAANQAECgIIAgAAAA==.Vanhellsin:BAABNQAECn8aAAILAAgKvQ+3RAABAQALAAgKvQ+3RAABAQAAAA==.Vashi:BAAANQAECgQIBgABNQAECgoKLgAKAAsUAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECgkJFgABAAcjAA==.Vedronas:BAABNQAECn8WAAIBAAkKByPmJQAuAwABAAkKByPmJQAuAwAAAA==.Veos:BAABNQAECn8xAAIQAAoKYxoeBQDIAgAQAAoKYxoeBQDIAgAAAA==.Verdict:BAAANQAECgUIBQAAAA==.Vern:BAABNQAECn8aAAMCAAgKRRMIZAD0AQACAAgKRRMIZAD0AQAfAAEKzQgLLAAsAAAAAA==.Vernaar:BAAANQAECggICwABNQAECggIGgACAEUTAA==.Vernah:BAAANQADCgIIAwABNQAECggIGgACAEUTAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Volætile:BAAANQAECgQIBQABNQAECgoKHwAiAJ0RAA==.Vonaria:BAAANQAECgYICQAAAA==.Vorn:BAABNQAECn9rAAILAAoK0BpYIACxAgALAAoK0BpYIACxAgAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAABNQAECn8nAAIYAAgKDBsrDwBxAgAYAAgKDBsrDwBxAgAAAA==.Waamchifu:BAAANQAECgMIBQAAAA==.Waltersight:BAAANQAECgMIBQAAAA==.Warbritt:BAAANQADCgYJBgAAAA==.Warförged:BAAANQAECggICQAAAA==.Warwuff:BAAANQADCgUICAAAAA==.Waterwalkerr:BAAANQADCgYIBgAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgUIDgAAAA==.Whatthezug:BAAANQADCgEIAQABNQAECgQICgAOAAAAAA==.Whoforted:BAABNQAECn8oAAMDAAoKxBhVKgDVAQADAAcKzhJVKgDVAQACAAkKNRgjTADOAQAAAA==.',
Wi='Wisperia:BAAANQAECgEIAwAAAA==.',
Wo='Woodard:BAAANQADCgEIAQAAAA==.Wormchild:BAAANQADCgQICAAAAA==.',
Wu='Wulrat:BAABNQAECn8UAAMGAAoK5BQ/HQDcAAAUAAcKrw9NuQCNAQAGAAQKvhk/HQDcAAAAAA==.',
Wy='Wyle:BAAANQAECgQICQAAAA==.',
Xe='Xelí:BAABNQAECn9sAAIEAAoKoRl+NQCJAgAEAAoKoRl+NQCJAgAAAA==.Xeneize:BAAANQADCgEIAQAAAA==.Xeras:BAAANQADCgIIAgAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAABNQAECn8YAAINAAkKxxeMTwCAAgANAAkKxxeMTwCAAgABNQAFFAcIFwAEAPQaAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.Youvbendoted:BAABNQAECn8eAAIIAAoKtiDrCQADAwAIAAoKtiDrCQADAwAAAA==.',
Yu='Yudah:BAAANQAECgQIBAAAAA==.',
Za='Zaldorina:BAAANQAECgEIAQAAAA==.Zanghonghua:BAABNQAECn89AAIjAAoKMRvUDgBAAgAjAAoKMRvUDgBAAgAAAA==.',
Ze='Zemy:BAACNQAFFH8FAAIcAAUK0BONEwAyAQAcAAUK0BONEwAyAQA1AAQKfzAAAxwACgocJbAKAHcDABwACgocJbAKAHcDABgABwrTFy0fAKUBAAAA.Zeneca:BAAANQAECgIIAgABNQAFFAQICgADAHQNAA==.',
Zo='Zodshot:BAAANQADCgQIBAAAAA==.Zodstrike:BAABNQAECn8wAAMKAAgKMwruOAAhAQAKAAgKMwruOAAhAQAhAAcK4QMfNwCxAAAAAA==.Zooboo:BAABNQAECn8fAAIlAAoK5xaFBgAhAgAlAAoK5xaFBgAhAgAAAA==.',
Zu='Zugwuff:BAAANQABCgMIAwAAAA==.Zugzuggler:BAABNQAECn80AAIUAAoKnRuSMABWAgAUAAoKnRuSMABWAgAAAA==.',
Zy='Zyrick:BAAANQADCgEIAQAAAA==.',
['Ät']='Ätticus:BAAANQADCgQIBAABNQAECgQICgAOAAAAAA==.',
['Öv']='Överpöwered:BAAANQAECgQICQABNQAECgQICgAOAAAAAA==.',
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
