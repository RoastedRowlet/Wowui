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

local lookup = {'Paladin-Retribution','Priest-Holy','Priest-Shadow','Rogue-Assassination','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','Mage-Arcane','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Holy','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','Rogue-Subtlety','Rogue-Outlaw','Druid-Feral','Druid-Balance','Druid-Guardian','Warlock-Affliction','Paladin-Protection','Priest-Discipline','Monk-Mistweaver','DemonHunter-Devourer','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Shaman-Elemental','Druid-Restoration',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Achannara:BAABNQAECn81AAIBAAkK+gUqzgAlAQABAAkK+gUqzgAlAQAAAA==.',
Ae='Aeloria:BAAANQADCgIIAgAAAA==.Aeoliana:BAABNQAECn8lAAICAAoKmRMwTQDuAQACAAoKmRMwTQDuAQAAAA==.',
Aj='Ajier:BAACNQAFFH8SAAICAAUK2g6IEgB5AQACAAUK2g6IEgB5AQA1AAQKf0wAAgIACgqcGXQ/ACYCAAIACgqcGXQ/ACYCAAAA.',
Al='Alaaris:BAAANQAECgEIAgAAAA==.Allcapwne:BAAANQADCggIIAAAAA==.Alucart:BAABNQAECn8fAAIDAAkKoQ4IJQBFAQADAAkKoQ4IJQBFAQAAAA==.',
An='Angela:BAABNQAECn8uAAICAAoKdBvCOACFAgACAAoKdBvCOACFAgAAAA==.Annadanna:BAAANQAECgUIEAAAAA==.Annalunà:BAAANQAECgMIBQAAAA==.Anogrips:BAAANQADCgYIBgAAAA==.Anoheals:BAAANQADCggIAgAAAA==.Anowars:BAAANQAECgUICAAAAA==.Antithicus:BAAANQADCgYIBgAAAA==.',
Ap='Apeople:BAACNQAFFH8GAAIEAAIKEBSjCgCSAAAEAAIKEBSjCgCSAAA1AAQKfzsAAgQACgo6H4EGAI4CAAQACgo6H4EGAI4CAAAA.Apocalýpsè:BAABNQAECn8gAAIFAAkKqxWIDADgAQAFAAkKqxWIDADgAQAAAA==.Applebottum:BAABNQAECn8aAAIBAAcK9BCO4wBUAQABAAcK9BCO4wBUAQAAAA==.Applebottumj:BAAANQAECgQIBQAAAA==.Appärition:BAABNQAECn9AAAMGAAoKmhtLEgDiAQAHAAoK/RmvMQA5AgAGAAYK/hdLEgDiAQAAAA==.',
Ar='Archillius:BAAANQADCgUIBQAAAA==.Arondael:BAABNQAECn8vAAIEAAoK/Q/bDQDeAQAEAAoK/Q/bDQDeAQAAAA==.',
As='Ashelaandrii:BAACNQAFFH8FAAIIAAIKpiCeHACxAAAIAAIKpiCeHACxAAA1AAQKfyMAAggACQo2I54QAEADAAgACQo2I54QAEADAAAA.Astroglyde:BAAANQAECgUICgAAAA==.Astryd:BAABNQAECn8dAAMJAAkKTgj4FgDRAAAJAAkKTgj4FgDRAAAKAAEKAACylQAAAAABNQAECgkJKQALABMIAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAABNQAECn8+AAIMAAkKyA2LewChAQAMAAkKyA2LewChAQAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùvina:BAAANQADCgIJAgAAAA==.',
Ba='Badru:BAAANQAECgMIAwAAAA==.Bagmaster:BAACNQAFFH8IAAICAAQK2BXOFgAvAQACAAQK2BXOFgAvAQA1AAQKfzwAAgIACgp4JegGAI4DAAIACgp4JegGAI4DAAAA.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAABNQAECn8hAAIIAAoK8Rj1OwBvAgAIAAoK8Rj1OwBvAgAAAA==.Barie:BAAANQAECgQIAwABNQAECgoKLAAKAO0eAA==.Barthallomew:BAAANQAECgQIBAABNQAECgQICgANAAAAAA==.Bayonetta:BAABNQAECn83AAIOAAoK0xk2RwAvAgAOAAoK0xk2RwAvAgAAAA==.',
Be='Beefyshadow:BAAANQADCgEIAQAAAA==.Bellann:BAAANQAECgQIBgAAAA==.',
Bi='Birghid:BAAANQABCgYIBgAAAA==.Birgite:BAABNQAECn8dAAIPAAcKQAoxMwDKAAAPAAcKQAoxMwDKAAAAAA==.',
Bl='Blackdracula:BAAANQAECgQIBQAAAA==.Blasphemar:BAAANQADCggIEAAAAA==.Blazefury:BAAANQAECgQIBwAAAA==.Blazeknight:BAABNQAECn8+AAMKAAoKQBn/JQDGAQAKAAoKQBn/JQDGAQAJAAIKqAqpLQAsAAAAAA==.Blazemaker:BAABNQAECn8zAAIQAAoKCxV/CgAgAgAQAAoKCxV/CgAgAgAAAA==.Blazemaster:BAAANQAECgYICQAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.Bloodsylf:BAAANQADCgcICgABNQAECgkJFwARAMoSAA==.Blówpop:BAAANQADCgMIAwAAAA==.',
Bo='Bonecrushers:BAABNQAECn8mAAIOAAgK0wv7qABFAQAOAAgK0wv7qABFAQAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAABNQAECn8sAAISAAoKVhucGwDLAgASAAoKVhucGwDLAgAAAA==.Books:BAAANQAECggIEwABNQAECgoKLAASAFYbAA==.',
Br='Brainbread:BAABNQAECn8bAAITAAgKVgyvpAAeAQATAAgKVgyvpAAeAQABNQAECgoKSQAHAMUYAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQAECggIEAAAAA==.Broadside:BAABNQAECn8eAAIOAAoKbiH9GwDGAgAOAAoKbiH9GwDGAgAAAA==.Brokil:BAAANQAECgYICwAAAA==.Brolymorph:BAACNQAFFH8KAAIMAAUKdg7ZNQDtAAAMAAUKdg7ZNQDtAAA1AAQKfy4AAgwACgoyHtNCADcCAAwACgoyHtNCADcCAAAA.Brossiere:BAAANQADCgQIBAAAAA==.Brotemic:BAAANQAECgIIAgAAAA==.Broverheal:BAAANQAECgMIBwAAAA==.Bru:BAACNQAFFH8IAAICAAUKNA/uEgBhAQACAAUKNA/uEgBhAQA1AAQKfysAAgIACgqMFEheAAYCAAIACgqMFEheAAYCAAAA.',
Bt='Bt:BAAANQADCgYIBgAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAABNQAECn8uAAQUAAoKiR14GAAUAgAUAAkK3h14GAAUAgAVAAIKSRXPjQB/AAALAAEKMxunjABKAAAAAA==.Burninglight:BAAANQADCggIGwAAAA==.Burningtree:BAABNQAECn8WAAMQAAgKngxxFgBKAQAQAAgKngxxFgBKAQAMAAQKNAe8fAHIAAAAAA==.Buthunter:BAAANQAECgUICQAAAA==.',
['Bâ']='Bâhtilâ:BAAANQAECggIBgAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECgoKbQAWAIEiAA==.',
Ca='Camamoonmana:BAAANQAECggIEwAAAA==.Canonbalizer:BAAANQAECgIIBAABNQAECggIHAAUAGEkAA==.Caplevi:BAABNQAECn87AAQXAAoKyhwsLwAtAgAXAAoKvRosLwAtAgAYAAYKThGhBABGAQAEAAQKNBcNQwB6AAAAAA==.Carrìon:BAAANQADCgEIAQAAAA==.Caskket:BAAANQAECggIEQAAAA==.Catdog:BAAANQADCgYIBgAAAA==.Catechism:BAABNQAECn8bAAISAAkKExskXQABAgASAAkKExskXQABAgAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAACNQAFFH8FAAIKAAMKJRhnEgCTAAAKAAMKJRhnEgCTAAA1AAQKfzkAAgoACgqnIe0QABkDAAoACgqnIe0QABkDAAAA.',
Ch='Chaningtotèm:BAAANQADCgUICgAAAA==.Charan:BAAANQADCgYIDgAAAA==.Chickennuggi:BAAANQADCgQIBwABNQAFFAYIEAAUAHAiAA==.Chiphoof:BAABNQAECn8aAAIZAAgK2BJKGAB2AQAZAAgK2BJKGAB2AQAAAA==.Chopndot:BAABNQAECn8XAAILAAcK8AX6YgCuAAALAAcK8AX6YgCuAAAAAA==.',
Cl='Clarabuns:BAABNQAECn8WAAMSAAkKmRryQgBZAgASAAgKphnyQgBZAgABAAIKaRBrbQFxAAAAAA==.Clawdragoon:BAEBNQAECn9IAAMaAAoKHh/dDgCwAgAaAAoKHh/dDgCwAgAbAAoKEhNlFgDFAQAAAA==.',
Co='Corine:BAAANQADCgUIBgAAAA==.Corndogmatt:BAAANQADCgUICAAAAA==.',
Cr='Creatlach:BAACNQAFFH8XAAIIAAcK9BqeBwDdAQAIAAcK9BqeBwDdAQA1AAQKfz8AAggACgpiJDsNAFYDAAgACgpiJDsNAFYDAAAA.Creatlachtwo:BAAANQAECggIEQABNQAFFAcIFwAIAPQaAA==.Creeptoken:BAAANQADCgQIBQAAAA==.Crucifilth:BAAANQAECgEIAgAAAA==.Crystallight:BAABNQAECn8YAAQWAAgKfQVVCQBcAAAMAAgK8QMoOwEqAQAWAAIKGAZVCQBcAAAQAAMKLwXgOgBTAAAAAA==.',
Cy='Cyrusmônk:BAAANQAECgUIBQABNQAECgYIBQANAAAAAA==.Cytherea:BAABNQAECn8ZAAIBAAoK+QpW+QDeAAABAAoK+QpW+QDeAAAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgoKKQAEAP0TAA==.Dalinek:BAABNQAECn8oAAMEAAoKYR2UFwC/AgAEAAoKVReUFwC/AgAXAAQKrSLwUwCYAQAAAA==.Damah:BAAANQADCggIHQABNQADCggIHQANAAAAAA==.Dandelo:BAAANQAECgEIAQAAAA==.Danicarkel:BAACNQAFFH8HAAMcAAMKIAvsAgDXAAAcAAMKIAvsAgDXAAAHAAEKAQawNgBBAAA1AAQKf0YABBwACgquHCcCAA4DABwACgquHCcCAA4DAAYABArBCnMyAPsAAAcAAgqnC3YtAWIAAAAA.Darkdlord:BAABNQAECn8vAAMVAAoKtA6jOgCdAQAVAAkKgA+jOgCdAQALAAoKRwUAUwDiAAABNQAECgoKNAABAPkbAA==.',
Dd='Ddpaladini:BAABNQAECn80AAMBAAoK+RsyMQCQAgABAAoK+RsyMQCQAgAdAAkKlAerNwAtAQAAAA==.',
De='Deathtracker:BAABNQAECn8hAAIOAAkK3gu2pQC6AQAOAAkK3gu2pQC6AQAAAA==.Deathtrops:BAAANQAECgIIAgABNQAFFAgIIgAHADUfAA==.Demindan:BAAANQAECgUIBgAAAA==.Demise:BAACNQAFFH8WAAMMAAgKZBL0EQDoAQAMAAcKhBP0EQDoAQAQAAEKwAzpDQBVAAA1AAQKf0UAAwwACgqTI3EiAKsCAAwACgqTI3EiAKsCABAAAQr3G0U8AE4AAAAA.Demontickler:BAAANQADCggIDQABNQAECgYIEAANAAAAAA==.',
Di='Dianabol:BAABNQAECn8sAAITAAoKzRnERgC1AgATAAoKzRnERgC1AgABNQAECgoKNwAIAPQlAA==.Diego:BAAANQADCgYIDAAAAA==.Dirkuatah:BAAANQAECgUICgAAAA==.Dista:BAACNQAFFH8JAAIHAAQK+xBZGgDFAAAHAAQK+xBZGgDFAAA1AAQKf00AAgcACgpDIYULAAUDAAcACgpDIYULAAUDAAAA.Divinebovine:BAAANQAECgEIAQAAAA==.Divinedragon:BAABNQAECn8xAAMDAAoKqRYXHwB7AQADAAkKdBUXHwB7AQAeAAQKvBoeFADnAAAAAA==.',
Do='Doboy:BAAANQAECgEIAQAAAA==.Dotsncandies:BAAANQAECgIIAgAAAA==.Doublevegan:BAAANQADCgMJAwAAAA==.',
Dr='Draconum:BAAANQADCgEIAQAAAA==.Drakin:BAABNQAECn8WAAIBAAoK/A6cqADPAQABAAoK/A6cqADPAQAAAA==.Drawbridge:BAAANQADCgYIEAAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAACNQAFFH8MAAIIAAQK6xddEQAqAQAIAAQK6xddEQAqAQA1AAQKfzQAAggACgoGFo5PACcCAAgACgoGFo5PACcCAAAA.Drinkoolaide:BAAANQAECggIDgABNQAFFAQIDAAIAOsXAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQAECgEIAQAAAA==.Dunamis:BAABNQAECn8oAAIMAAoK6R7KWQDMAgAMAAoK6R7KWQDMAgAAAA==.Durrt:BAAANQAECgYIEAAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAACNQAFFH8PAAMPAAYK4BaRDgBUAQAPAAUKoRCRDgBUAQAOAAMK6B6SKACWAAA1AAQKfz4AAw4ACgrpJV8RAFwDAA4ACgrpJV8RAFwDAA8ACgqvH8gLAHMCAAAA.',
['Dó']='Dóòmsday:BAAANQADCgYIBgAAAA==.',
Ei='Einaria:BAAANQAECgIIAgABNQAECgoKMQAMANkdAA==.',
El='Eldrene:BAABNQAECn8xAAIMAAoK2R0VLwB4AgAMAAoK2R0VLwB4AgAAAA==.Elizalde:BAAANQAECgYIEAAAAA==.Ellexi:BAAANQAECgYIEAAAAA==.Elyseia:BAABNQAECn8mAAIOAAoKFA4JewAYAgAOAAoKFA4JewAYAgAAAA==.',
En='Enpower:BAAANQAECgQICgABNQAFFAQIDgAfAEkIAA==.',
Ep='Epicsause:BAAANQAECggICgAAAA==.',
Es='Escata:BAAANQAECgQICAAAAA==.Esdailongwe:BAAANQADCgYIDQAAAA==.Españamor:BAECNQAFFH8GAAMgAAUKQgNODgBeAAAgAAIKRwNODgBeAAAJAAMKOQOqBgArAAA1AAQKfyoAAyAACgqKE2sfAJIBACAACgqlEmsfAJIBAAkACAqODNwYACQBAAAA.',
Eu='Eunite:BAABNQAECn9rAAIUAAoK0B2kKACWAgAUAAoK0B2kKACWAgAAAA==.',
Fa='Falkorne:BAABNQAECn8WAAMFAAcKqwqCHAAHAQAFAAcKGAqCHAAHAQATAAUKrQcT0ADAAAABNQAECgoKKQAfALQYAA==.Farael:BAAANQADCgYIBgAAAA==.Fashah:BAAANQAECgIIAgAAAA==.Fatalmann:BAAANQAECgIIAgAAAA==.',
Fe='Felmoo:BAABNQAECn8XAAIbAAkKdgY3MQD3AAAbAAkKdgY3MQD3AAAAAA==.Felorc:BAABNQAECn8gAAMFAAkKJAUCKwDhAAAFAAkKJAUCKwDhAAATAAIKKAIbTQE6AAABNQAECgkJKQALABMIAA==.Feralhorn:BAAANQAECggIEQAAAA==.',
Fi='Fintan:BAAANQAECgUIBQABNQAFFAcIFwAIAPQaAA==.',
Fo='Forsakenemp:BAAANQAECggIDQABNQAECgoKNAABAPkbAA==.',
Fr='Frassk:BAABNQAECn81AAMHAAoKZhB2dgBkAQAHAAoK9g52dgBkAQAGAAIKuROPGwB8AAAAAA==.Frigid:BAAANQADCgcIBwAAAA==.Froggystyle:BAAANQAECggIEgAAAA==.Frozenheart:BAABNQAECn8pAAMLAAkKEwi5dwAZAQALAAkKEwi5dwAZAQAVAAQKZgaclABjAAAAAA==.Fruk:BAAANQADCgUIBQAAAA==.Frösting:BAAANQADCgYIBgABNQAECgoKIgAhAPESAA==.',
Ft='Ftx:BAABNQAECn8sAAITAAkKxiE3SgCqAgATAAkKxiE3SgCqAgAAAA==.',
Fu='Furfoxxsakes:BAAANQADCgEIAQAAAA==.',
Ga='Garbarn:BAAANQADCgcIDQAAAA==.',
Ge='Gelystine:BAAANQADCgIIAgAAAA==.Geminichi:BAACNQAFFH8OAAMfAAQKSQgmBgD+AAAfAAQKSQgmBgD+AAAiAAEKGwpVEgBGAAA1AAQKfzsAAx8ACgqfHScKAJICAB8ACgqfHScKAJICACIAAgqFEClqADcAAAAA.Geminishadow:BAABNQAECn8XAAMXAAoKrAvlVwCJAQAXAAoK4QnlVwCJAQAEAAUKcw2iYAAyAQAAAA==.',
Gh='Ghauri:BAAANQADCgYJBgAAAA==.Ghorza:BAAANQADCgYIBwAAAA==.',
Gi='Gia:BAABNQAECn9CAAIfAAoKSR2ABgAPAwAfAAoKSR2ABgAPAwAAAA==.Gigasauce:BAAANQAECgEIAQAAAA==.Giraffage:BAABNQAECn8WAAIMAAcK6Q9j4ADIAQAMAAcK6Q9j4ADIAQABNQAECgcIBwANAAAAAA==.',
Go='Golgroth:BAAANQADCgQJBAAAAA==.Goochgibbler:BAAANQADCgQIBAAAAA==.Gorearrow:BAACNQAFFH8GAAIOAAMKdxSoHgCbAAAOAAMKdxSoHgCbAAA1AAQKfzsAAg4ACgryH2AzANICAA4ACgryH2AzANICAAAA.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Grimmtotem:BAABNQAECn8YAAIRAAgK8QRbCwDsAAARAAgK8QRbCwDsAAAAAA==.Groggyfroggy:BAAANQADCgMJAwAAAA==.Grognaak:BAAANQADCgMIBAAAAA==.Grralt:BAAANQAECgIIAgABNQADCggIHQANAAAAAA==.Grís:BAABNQAECn8vAAMTAAoKpxeTaABWAgATAAoKpxeTaABWAgAFAAMKCA3uMwCXAAAAAA==.',
Gu='Gumbuz:BAAANQAECgQIBAAAAA==.Gunafistya:BAAANQAECgMIBQAAAA==.',
Ha='Hanwi:BAAANQAECggICAAAAA==.Harrier:BAAANQADCggIEwABNQAECggIGgAZANgSAA==.Hazed:BAABNQAECn8XAAIMAAoKfQwzbADIAQAMAAoKfQwzbADIAQAAAA==.Hazyblades:BAAANQAECgIIAgAAAA==.Hazzaa:BAAANQAECgcICQAAAA==.',
He='Healzforbeer:BAAANQADCgUIBQAAAA==.Heila:BAAANQAFFAIIAgAAAA==.Henso:BAAANQAFFAIIAgABNQAFFAQIDgAfAEkIAA==.Herioffy:BAAANQADCgEIAQAAAA==.Hexxan:BAAANQADCgYIBgAAAA==.',
Hi='Hiawatha:BAAANQADCgQIBAAAAA==.Hiver:BAAANQAECgEIAQAAAA==.',
Ho='Holier:BAACNQAFFH8FAAIBAAIKaAU2JgByAAABAAIKaAU2JgByAAA1AAQKf0UAAgEACgocEHx6AMQBAAEACgocEHx6AMQBAAAA.Holybishh:BAAANQAECgUIBQAAAA==.Holyregerts:BAABNQAECn8jAAMDAAoKmxEwJAAPAgADAAkKQRAwJAAPAgACAAgK4BmDcQDIAQAAAA==.Honk:BAABNQAECn8XAAIHAAoKOw4XmACrAQAHAAoKOw4XmACrAQAAAA==.Hoochurcooch:BAAANQAECgQIBAAAAA==.Hoosnext:BAAANQAECgEIAQAAAA==.Hopperstotem:BAAANQAECgMIAwABNQAECgoKHgAOAG4hAA==.',
Hu='Hulo:BAAANQAECgMIAwAAAA==.Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQAECgIIAgAAAA==.',
Il='Illari:BAAANQABCgIIAgAAAA==.Illumi:BAAANQABCgYIBgAAAA==.',
Im='Imbatmann:BAAANQADCgEIAQAAAA==.',
In='Indrà:BAAANQADCgQIBgAAAA==.Infamus:BAAANQAECgIIBQAAAA==.Invysion:BAACNQAFFH8SAAMeAAUKLAOWAQApAQAeAAUKLAOWAQApAQACAAIKyAHzKwBuAAA1AAQKf0wAAx4ACgo1FVsDADcCAB4ACgo1FVsDADcCAAIAAQqoBrTuADEAAAAA.',
Is='Ishara:BAAANQABCgIIAgABNQAECgoKMQAMANkdAA==.Islander:BAABNQAECn8cAAISAAgK8ROLRgDnAQASAAgK8ROLRgDnAQAAAA==.',
Ja='Jackychang:BAABNQAECn8cAAIXAAkKGQ5hGwD7AQAXAAkKGQ5hGwD7AQAAAA==.Jaidess:BAAANQADCggIFwAAAA==.Jakeypoo:BAAANQAECgQICgAAAA==.Jayskiller:BAAANQADCgUIBQAAAA==.',
Je='Jellybea:BAACNQAFFH8IAAICAAUKyBJmEACDAQACAAUKyBJmEACDAQA1AAQKfzIAAwIACgq5HnUrALsCAAIACgq5HnUrALsCAAMAAwpSDHZqAFkAAAAA.',
Ji='Jimmee:BAAANQADCgIIAgAAAA==.',
Ju='Jukoti:BAAANQABCgIIBAAAAA==.Junglebrew:BAAANQAECgUIAwAAAA==.Jurisdiction:BAABNQAECn8fAAIBAAkKUQlm0wAcAQABAAkKUQlm0wAcAQAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAABNQAECn8xAAIiAAoKDhzTDwDoAgAiAAoKDhzTDwDoAgAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kanalz:BAAANQAECgUIBQAAAA==.Karambit:BAAANQAECgcICwAAAA==.Kasey:BAABNQAECn8VAAIBAAYK8B4guwCnAQABAAYK8B4guwCnAQAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keggstand:BAAANQAECgYIBgAAAA==.Keho:BAABNQAECn8dAAIjAAkKHQVPEwDbAAAjAAkKHQVPEwDbAAAAAA==.Kellbor:BAAANQAECgEIAQAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAACNQAFFH8QAAMgAAUKNRRgCQDCAAAKAAQKNRSjDwAMAQAgAAQKughgCQDCAAA1AAQKf0EAAyAACgpjH4ENAG8CAAoACgo/G9ghAI0CACAACgqyHoENAG8CAAE1AAQKBwgHAA0AAAAA.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kickdrop:BAAANQADCgQIBAAAAA==.Kilgreed:BAAANQADCgYIDgAAAA==.Killaban:BAAANQAECgcIBwAAAA==.Killbydeath:BAABNQAECn8cAAQUAAgKYSRMEwBLAgAUAAgK1SNMEwBLAgALAAIKax9anACiAAAVAAIKjxSLgwCOAAAAAA==.Kimberlyhárt:BAAANQAECgYIEAAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYIEAANAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAABNQAECn9sAAIHAAoKIR2MKQDeAgAHAAoKIR2MKQDeAgAAAA==.',
Ko='Kohman:BAABNQAECn9JAAMHAAoKxRhAMQDDAgAHAAoKxRhAMQDDAgAGAAMKtA1xUgCIAAAAAA==.Komatose:BAAANQADCgYIBgAAAA==.Kong:BAAANQADCgIIAwAAAA==.',
Kr='Krftpnk:BAACNQAFFH8hAAIKAAgKRyCBAQC0AgAKAAgKRyCBAQC0AgA1AAQKf0EAAgoACgrqJi4CANUDAAoACgrqJi4CANUDAAAA.Kricket:BAAANQAECgEIAgAAAA==.Kronas:BAABNQAECn8XAAMOAAkKHBQ3jwDrAQAOAAkKHBQ3jwDrAQAPAAEKjQMMawAsAAAAAA==.Kronosity:BAABNQAECn80AAIdAAoK7R+mCgDwAgAdAAoK7R+mCgDwAgABNQAFFAQICQALAG8fAA==.Kronotality:BAACNQAFFH8JAAILAAQKbx/pDQAHAQALAAQKbx/pDQAHAQA1AAQKf0gAAgsACgrvI8MFAJcDAAsACgrvI8MFAJcDAAAA.Kronotekken:BAAANQAECgEIAQABNQAFFAQICQALAG8fAA==.Kronotide:BAAANQADCgQIBAABNQAFFAQICQALAG8fAA==.',
Ku='Kungfukittn:BAABNQAECn8dAAIiAAcKIxagKwC+AQAiAAcKIxagKwC+AQAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQAECggIDgAAAA==.Kyojuro:BAAANQABCgYIBgAAAA==.',
Kz='Kzorx:BAAANQAECgEIAQAAAA==.',
La='Laimaster:BAAANQAECgQIBAAAAA==.Lakiri:BAABNQAECn82AAIhAAgK1xLvFwDpAQAhAAgK1xLvFwDpAQAAAA==.Landaeda:BAAANQAECgUIBQAAAA==.Lascivia:BAACNQAFFH8GAAIFAAMK/Rt7BACaAAAFAAMK/Rt7BACaAAA1AAQKfywAAwUACgrIIVoGAAIDAAUACgrIIVoGAAIDACQABAoAGPsYABIBAAAA.Latrice:BAAANQAECgcIBwABNQAFFAgIFQAQAB8cAA==.Laylahh:BAAANQADCgQIBAAAAA==.Lazereyes:BAAANQAECgUICQAAAA==.',
Le='Leademon:BAABNQAECn8gAAIKAAoK5he4MAAiAgAKAAoK5he4MAAiAgAAAA==.Leadmln:BAAANQAECgYICwABNQAECgoKIAAKAOYXAA==.Lebwonsamdi:BAAANQAECgUIBQABNQAECgoKLwATAKcXAA==.Lethalkrits:BAAANQAECggIAgAAAA==.',
Li='Liberté:BAAANQADCggICQAAAA==.Lighterfluîd:BAAANQABCgIIAgABNQAECgoKLgAfAFEfAA==.Ligmadk:BAAANQADCgUIBQABNQAFFAUICAAKAHAJAA==.Lilbeebs:BAAANQAECgcICwAAAA==.Lileth:BAAANQADCgEIAQAAAA==.Lilflea:BAABNQAECn8lAAMIAAoK9xliUQAgAgAIAAoK9xliUQAgAgAlAAEKAAD5TAEnAAAAAA==.Lillidari:BAAANQAECgcICQABNQAECgkJJgALACwkAA==.Lilzuki:BAAANQAECggIEgAAAA==.Lilïth:BAABNQAECn8mAAILAAkKLCQkCwBbAwALAAkKLCQkCwBbAwAAAA==.Linguine:BAAANQADCggICAABNQAFFAQICgADAHQNAA==.Lisalisa:BAABNQAECn8oAAIIAAoKTxKZTwC8AQAIAAoKTxKZTwC8AQAAAA==.Littlej:BAAANQAECgQJBAAAAA==.Littlejohn:BAABNQAECn8pAAIfAAoKtBjtEABwAgAfAAoKtBjtEABwAgAAAA==.',
Lo='Logantis:BAABNQAECn8eAAITAAkKJxY7OwBFAgATAAkKJxY7OwBFAgAAAA==.Logaothe:BAABNQAECn8cAAIBAAYKJQpOAgEbAQABAAYKJQpOAgEbAQAAAA==.Lokee:BAAANQADCgUIBQAAAA==.',
Lu='Lucky:BAABNQAECn8YAAIKAAgKHRBBNgBYAQAKAAgKHRBBNgBYAQAAAA==.Lukethywalkr:BAAANQAECgEIAQAAAA==.Lularia:BAAANQADCgYIDQAAAA==.Lunaa:BAAANQAECgQIBwAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Malakyte:BAAANQAECgIIAgAAAA==.Maliciousrot:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQIBQAAAA==.Marshail:BAAANQAECgUIBQAAAA==.',
Me='Medikus:BAABNQAECn80AAMIAAoKmBtEIQCgAgAIAAoKmBtEIQCgAgAlAAEKKQQj+wAuAAAAAA==.Megajoo:BAABNQAECn8gAAMmAAoK4BA6GwATAgAmAAoK4BA6GwATAgAaAAIK4QSTvwAiAAAAAA==.Merryl:BAAANQAECgUIBwAAAA==.',
Mf='Mfive:BAAANQAECgQIBAAAAA==.',
Mi='Mike:BAEBNQAECn8cAAIMAAkK4iGtUQDdAgAMAAkK4iGtUQDdAgAAAA==.Milkjugs:BAAANQAECgUIAwABNQAECgoKJQAIAPcZAA==.Minijeangen:BAAANQAECgMJAwAAAA==.Missluana:BAAANQABCgEIAQAAAA==.Mizshankalot:BAAANQAECgUIBwABNQAECgoKNAABAPkbAA==.',
Mo='Mockra:BAABNQAECn9AAAIMAAgKGhZxrAApAgAMAAgKGhZxrAApAgAAAA==.Moistmunnky:BAAANQAECgQIDgAAAA==.Montera:BAEANQAFFAIIAgABNQAFFAUIBgAgAEIDAA==.Moohammered:BAABNQAECn8wAAIBAAoKrxjJRQBJAgABAAoKrxjJRQBJAgAAAA==.Moolou:BAACNQAFFH8IAAIdAAUKBAxdBwCtAAAdAAUKBAxdBwCtAAA1AAQKfy8AAx0ACgpfHO0QAJECAB0ACgpfHO0QAJECAAEAAQrwC9B/AToAAAAA.Mootarded:BAABNQAECn8UAAIdAAkK5wR1QgCLAAAdAAkK5wR1QgCLAAABNQAECgkJKQALABMIAA==.Mordiggian:BAABNQAECn9BAAMLAAoKjyTQDwAvAwALAAkKbyXQDwAvAwAUAAkKlSMFGQD3AgAAAA==.Morechie:BAABNQAECn83AAMcAAoKYxAkCQD0AQAcAAkKBRAkCQD0AQAHAAYKgQwDsQDdAAAAAA==.Morganaj:BAAANQAECgQICwAAAA==.Morgatho:BAAANQABCgcICQAAAA==.Morsz:BAAANQAECgUICAAAAA==.Mortiferon:BAABNQAECn8jAAIUAAkKShrUOwAyAgAUAAkKShrUOwAyAgAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQAECgQIDgANAAAAAA==.Munnkypox:BAAANQAECgIIBAABNQAECgQIDgANAAAAAA==.Murderella:BAAANQADCgYIBgAAAA==.Muriggs:BAAANQAFFAEIAQAAAA==.Murkhoof:BAAANQADCgYIBgABNQAECggIGgAZANgSAA==.',
['Mö']='Mörgänä:BAAANQADCggIEgAAAA==.',
Na='Nakovii:BAAANQAECgUIBQAAAA==.Nakovy:BAAANQAECgQIAwAAAA==.Napa:BAAANQAECgUIBQABNQAFFAcIFAAIAKcXAA==.Nascerathel:BAAANQAECgQIBwAAAA==.',
Ne='Nealite:BAAANQADCgYIBgAAAA==.Neerem:BAAANQABCggIDQAAAA==.Neferata:BAABNQAECn9OAAMHAAoKlh7QKABdAgAHAAoKlh7QKABdAgAGAAYKbgvNJwA6AQAAAA==.Nerrisa:BAAANQADCggIDwAAAA==.Nertmage:BAABNQAECn9tAAQWAAoKgSJQAACfAwAWAAoKgSJQAACfAwAMAAIKAA7+vAFEAAAQAAEKThmiOgA6AAAAAA==.Neublood:BAAANQAECgQIBwAAAA==.',
Ni='Nicodemus:BAAANQAECgYICQAAAA==.Nineiota:BAABNQAECn8uAAMmAAoK+BxvEwB6AgAmAAoK+BxvEwB6AgAaAAEKzA3GggA2AAAAAA==.',
No='Noblewarrior:BAACNQAFFH8gAAITAAcK7hQBEQCtAQATAAcK7hQBEQCtAQA1AAQKf1EAAxMACgpGJIoNACIDABMACgo1JIoNACIDACQACAqzIksDANACAAAA.Nobukawaii:BAAANQAECgMIAwAAAA==.Noctilus:BAAANQADCgcIGQAAAA==.Noke:BAAANQAECgIJAgAAAA==.Noril:BAAANQADCgUIBQAAAA==.Notakoala:BAACNQAFFH8QAAIaAAYKABaZEABhAQAaAAYKABaZEABhAQA1AAQKfz8AAhoACgrPIpEOAFUDABoACgrPIpEOAFUDAAAA.Nothnx:BAACNQAFFH8NAAIOAAYK0A9cBQCPAQAOAAYK0A9cBQCPAQA1AAQKf0MAAg4ACgpwH88gAK8CAA4ACgpwH88gAK8CAAAA.Notillidan:BAAANQADCgYICwAAAA==.Notoriouspat:BAAANQAECgcIDgAAAA==.Notromanoff:BAAANQADCgEIAQABNQAECgoKKQAEAP0TAA==.Novia:BAAANQAECgcIDgABNQAECgoKLwATAKcXAA==.Noxeternis:BAACNQAFFH8IAAMCAAQKIQvHGgAHAQACAAQKIQvHGgAHAQADAAEKfBDEFABJAAA1AAQKfzYABAMACgr6GTIhAC4CAAMACQoZGTIhAC4CAAIABQrYG0aAAD8BAB4AAgoyBiAkAEoAAAAA.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
Ny='Nyxandra:BAAANQADCggIFwAAAA==.',
['Ní']='Níghtfall:BAAANQADCgUICwAAAA==.Nínebreaker:BAAANQAECgEIAQAAAA==.',
['Nü']='Nüll:BAAANQADCgYICwAAAA==.',
Ob='Obern:BAABNQAECn8fAAIRAAoKmBQ5BQBzAgARAAoKmBQ5BQBzAgAAAA==.Obeysnapback:BAAANQADCgMIBQAAAA==.Oblïna:BAAANQAECgcIEgAAAA==.',
Od='Oddishh:BAABNQAECn8fAAMVAAoK4w6oLgDcAQAVAAoK4w6oLgDcAQALAAYK6wivfQADAQAAAA==.',
Of='Offensivé:BAAANQAECgIIAgAAAA==.',
Ol='Olleg:BAAANQADCgYICQAAAA==.',
Om='Omnicarkel:BAAANQADCgcIDAAAAA==.',
On='Onsen:BAABNQAECn8uAAIBAAoKaRsaWwCHAgABAAoKaRsaWwCHAgABNQAECgoKSQAHAMUYAA==.',
Or='Oresties:BAAANQADCggICQAAAA==.Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQJBAAAAA==.',
Ou='Outwithabang:BAAANQAECgMIAwAAAA==.',
Pa='Pajl:BAABNQAECn8tAAIBAAoKlyOtDQCXAwABAAoKlyOtDQCXAwABNQAFFAgIEQAVAMYaAA==.Pandablaze:BAAANQAECgQIBQAAAA==.Pandajoy:BAAANQADCgEIAQAAAA==.Panterarey:BAAANQAECgIIAgAAAA==.Papanurrgle:BAAANQAECgUICQAAAA==.Papazilla:BAAANQAECgMJAwAAAA==.Parakka:BAAANQAECggICwAAAA==.Patak:BAAANQADCgQIBwAAAA==.Pawp:BAABNQAECn8dAAMIAAkK3RF/VgCiAQAIAAkK3RF/VgCiAQAhAAMKQwFYMQBfAAABNQAECgoKNwACACcaAA==.Paxiel:BAAANQAECgQICAAAAA==.',
Pe='Pearagon:BAABNQAECn8YAAICAAkKmBkLKgCPAgACAAkKmBkLKgCPAgABNQAFFAcIFAAIAKcXAA==.Pepsidew:BAAANQAECggICgAAAA==.Pepsisprite:BAABNQAECn8fAAICAAkKZhoLOgA/AgACAAkKZhoLOgA/AgAAAA==.',
Ph='Phdbeef:BAAANQAECgEIAQABNQAECgkJJgALACwkAA==.Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQAECgIIAgAAAA==.',
Pi='Picklez:BAABNQAECn8qAAIVAAgKpxjHNQC1AQAVAAgKpxjHNQC1AQAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.Portwings:BAAANQAECgEIAQAAAA==.',
Ps='Psyop:BAAANQADCggIGQABNQAECgoKTAACAD4iAA==.Psyrax:BAAANQAECgQICgAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Rashun:BAAANQAECgUICAAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDgAAAA==.Redkoala:BAABNQAECn8eAAIMAAgKTgdRlgBlAQAMAAgKTgdRlgBlAQABNQAFFAYIEAAaAAAWAA==.Regrets:BAAANQAECgQIAwABNQAECgoKIwADAJsRAA==.Regretty:BAAANQAECgEIAQABNQAECgoKIwADAJsRAA==.Repete:BAAANQAECgQIBAAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECn9rAAIQAAoKwSESAgBaAwAQAAoKwSESAgBaAwAAAA==.Reven:BAAANQAECgYICAAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ri='Riivan:BAAANQAECgIIAQAAAA==.Rirugiliyang:BAAANQAECgEIAQAAAA==.Rivian:BAAANQAECgUIBgABNQAECggIHAASAPETAA==.',
Ro='Roardon:BAAANQADCggIDwAAAA==.Roflmfao:BAAANQADCggICAAAAA==.Roguè:BAAANQAECgQICgAAAA==.Rollinburn:BAAANQADCgUJBQAAAA==.Romanoff:BAABNQAECn8pAAMEAAoK/ROaPQDZAQAEAAcKBxOaPQDZAQAXAAgKjBNBVgCPAQAAAA==.Rosearcana:BAAANQAECgEIAQAAAA==.Rozztok:BAAANQADCggICgAAAA==.',
Ry='Ryokhan:BAAANQAECggICgAAAA==.',
['Rô']='Rôx:BAAANQADCgcIBgABNQAECgoKcQASAL0bAA==.',
['Rõ']='Rõx:BAABNQAECn9xAAMSAAoKvRtOLwCpAgASAAoKvRtOLwCpAgABAAgKjBTZdQDPAQAAAA==.',
Sa='Sackoss:BAABNQAECn8fAAISAAkKtxiQXwD6AQASAAkKtxiQXwD6AQAAAA==.Saffronspark:BAAANQAECgUIDQABNQAECgoKQAAiAMEbAA==.Sainsei:BAABNQAECn8iAAMjAAoKFhMnCADEAQAjAAkK7BEnCADEAQAiAAUKKhBcOwC3AAABNQAECgoKLwATAKcXAA==.Sakata:BAAANQADCgIIAgABNQAECggIGgAZANgSAA==.Sandwitch:BAABNQAECn9rAAMGAAoKsRNuDwAGAgAHAAoKPBIjYAA4AgAGAAgKTxBuDwAGAgAAAA==.Sargatanas:BAABNQAECn8jAAILAAkK8gw/UgCsAQALAAkK8gw/UgCsAQAAAA==.Sars:BAAANQADCgUIBQABNQAECggIIQACAC8kAA==.',
Sc='Scarcroww:BAAANQADCgMIAwABNQAECgoKJgAMAGofAA==.Schrodinger:BAAANQAECgIIBAAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Selline:BAAANQAECgIIAgAAAA==.Septicflësh:BAAANQAECggICAAAAA==.Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAABNQAECn8tAAIFAAkKvxLsEgB0AQAFAAkKvxLsEgB0AQAAAA==.',
Sh='Shadrad:BAACNQAFFH8HAAIBAAUKsRUDEgDlAAABAAUKsRUDEgDlAAA1AAQKfzUAAwEACgp8IIgnACgDAAEACgp8IIgnACgDABIABwqnBPnGAO0AAAAA.Shallot:BAABNQAECn8zAAIMAAoK3SDdNwAYAwAMAAoK3SDdNwAYAwAAAA==.Shammoo:BAABNQAECn8XAAIlAAkKixUAYAACAgAlAAkKixUAYAACAgABNQAFFAQIBgABAMYLAA==.Shammyd:BAABNQAECn8nAAIlAAoK9Qh7UACAAQAlAAoK9Qh7UACAAQAAAA==.Shantz:BAABNQAECn8yAAILAAoKaw73KgCdAQALAAoKaw73KgCdAQAAAA==.Sharprot:BAAANQAECgYIBgABNQAECgoKKwATAOQQAA==.Shiftface:BAAANQAECggICAABNQAECgoKGQABAPkKAA==.Shiftmypants:BAABNQAECn8sAAIaAAoKFhvsEQCIAgAaAAoKFhvsEQCIAgAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Si='Sinterdeath:BAABNQAECn8VAAMUAAcK7AjkgwAQAQAUAAcK7AjkgwAQAQAVAAQKTwXwjwBuAAAAAA==.',
Sk='Skatervan:BAAANQAECgUIBQABNQAECgoKTwADAFkdAA==.Skylie:BAAANQADCgYIDwAAAA==.',
Sl='Slushpuppy:BAAANQAECgIIAgAAAA==.',
Sm='Smorthian:BAAANQAECgQIDwAAAA==.',
Sn='Snicggers:BAAANQADCggICAAAAA==.Sniffinsteak:BAAANQAECgYJEAAAAA==.Snoosnooftww:BAAANQAECgIIAgAAAA==.',
So='Solas:BAABNQAECn8jAAICAAcKMxnhSQD7AQACAAcKMxnhSQD7AQAAAA==.Sonarael:BAAANQAECgMIAwABNQAECgoKMQAMANkdAA==.Sondeltis:BAAANQAECgQIBQAAAA==.Soryan:BAAANQAECgUIBQAAAA==.',
Sp='Spankenstine:BAABNQAECn8eAAIBAAkKdRktbQBXAgABAAkKdRktbQBXAgABNQAECgoKKwATAOQQAA==.Sparkyy:BAAANQAECgIIAwAAAA==.Sphaeram:BAAANQAECgcICAAAAA==.Spicypepsi:BAAANQADCgEIAQAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAABNQAECn8zAAIBAAoKXCHyJgC6AgABAAoKXCHyJgC6AgAAAA==.Stinkydeathy:BAAANQADCgYJBgABNQAECgIIAgANAAAAAA==.Stinkydragon:BAAANQAECgIIAgAAAA==.Stormknight:BAAANQAECgYICgAAAA==.Stormpoo:BAAANQAECgUIBgAAAA==.',
Su='Suneater:BAABNQAECn8sAAISAAoKlR+oEQAhAwASAAoKlR+oEQAhAwAAAA==.Superpi:BAAANQADCgYIBgABNQAECgUICAANAAAAAA==.Superret:BAAANQAECgUICAAAAA==.Surotor:BAAANQADCgQICAAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAABNQAECn8kAAIBAAoKfA2EhACuAQABAAoKfA2EhACuAQAAAA==.',
Sw='Swíper:BAACNQAFFH8FAAIEAAIKLA8iFwCUAAAEAAIKLA8iFwCUAAA1AAQKfy8AAwQACgogHnkIAFADAAQACgogHnkIAFADABcABQq1CTA4APcAAAAA.',
Sy='Sylphièl:BAACNQAFFH8QAAMXAAcKywfrDgACAQAXAAYKtwjrDgACAQAEAAEKGwR+EgA8AAA1AAQKfzkAAxcACgomHCoaAKMCABcACQomHCoaAKMCAAQACQoxCflBAMMBAAAA.',
['Sö']='Sörceress:BAAANQADCgQIBAAAAA==.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgcIDQAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECn8oAAIBAAkKmiJpLAAWAwABAAkKmiJpLAAWAwAAAA==.Tankenstine:BAABNQAECn8rAAITAAoK5BChYwDAAQATAAoK5BChYwDAAQAAAA==.Tanktop:BAAANQADCggIDwAAAA==.Tastymilk:BAAANQAECgcIDQAAAA==.Tawnii:BAAANQAECgQIBAAAAA==.Taírn:BAAANQAECgQIBAAAAA==.',
Te='Tenderloin:BAABNQAECn8XAAMKAAgKmg1+VQA4AQAKAAcKbQp+VQA4AQAJAAQKWhDhIwCgAAAAAA==.',
Th='Thanitose:BAABNQAECn8YAAITAAcKaQZHwQDeAAATAAcKaQZHwQDeAAAAAA==.Thevelo:BAAANQAECgYICAABNQAECgkJFwARAMoSAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thornok:BAAANQADCgQIBAAAAA==.Thornwyn:BAAANQAECgcIEgAAAA==.Thors:BAAANQADCgQIBAAAAA==.Thorul:BAABNQAECn8VAAITAAgKuAiPggBsAQATAAgKuAiPggBsAQAAAA==.Thundurus:BAACNQAFFH8MAAIlAAMKWwclHgB7AAAlAAMKWwclHgB7AAA1AAQKfz0AAiUACgrqFwlGAF4CACUACgrqFwlGAF4CAAAA.',
Ti='Timmayy:BAABNQAECn8YAAIHAAkKrg2IWAC3AQAHAAkKrg2IWAC3AQABNQAECgoKKQAfALQYAA==.Tindrill:BAAANQAECgMIAwABNQAECgoKKwAmAL0iAA==.Tinggoskrrah:BAAANQADCggIEgAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAABNQAECn8tAAITAAkKcRAJcgCWAQATAAkKcRAJcgCWAQAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAgIIQAKAEcgAA==.Totemagoat:BAACNQAFFH8LAAMIAAcKCxDyDQBuAQAIAAcKCxDyDQBuAQAlAAEKsQXlMgBEAAA1AAQKf0kAAwgACgomIoMWAB0DAAgACgomIoMWAB0DACUACApPF9BgAP8BAAAA.',
Tr='Tracula:BAAANQADCgEIAQAAAA==.Treefist:BAAANQAECgYIBgAAAA==.Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAACNQAFFH8KAAImAAQKcAtcDQC0AAAmAAQKcAtcDQC0AAA1AAQKfzcAAyYACgqSFggdAEsCACYACgqSFggdAEsCABoAAwpMAiF4AE0AAAAA.',
Un='Undeadkiels:BAAANQADCggICAABNQAECgoKNAABAPkbAA==.Undeadmonks:BAAANQADCgYIBgAAAA==.',
Ur='Uraharakun:BAAANQAECgcIDAABNQAECgoKTAAdAMMXAA==.',
Va='Vagalion:BAABNQAECn8oAAQhAAoKpxIlFAC5AQAhAAcKMxYlFAC5AQAlAAgKbQuObwAjAQAIAAUK+gyJuAD7AAAAAA==.Valdanyr:BAAANQAECggICQAAAA==.Vale:BAAANQAECgMIAwAAAA==.Valeshot:BAABNQAECn8tAAIOAAoKcQ1+dwAgAgAOAAoKcQ1+dwAgAgAAAA==.Valimyr:BAAANQABCgMIBAAAAA==.Valkillrie:BAABNQAECn8hAAMSAAoKYhkKHgC7AgASAAoKYhkKHgC7AgABAAIKXgq9egFhAAAAAA==.Valohir:BAAANQAECgIIAgAAAA==.Vanhellsin:BAABNQAECn8aAAILAAgKvQ/BSwD/AAALAAgKvQ/BSwD/AAAAAA==.Vashi:BAAANQAECgQIBAABNQAECgoKLgAKAAsUAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECgkJFgABAAcjAA==.Vedronas:BAABNQAECn8WAAIBAAkKByPmJQAuAwABAAkKByPmJQAuAwAAAA==.Veos:BAABNQAECn8xAAIQAAoKYxoeBQDIAgAQAAoKYxoeBQDIAgAAAA==.Verdict:BAAANQAECgUIBQAAAA==.Vern:BAABNQAECn8aAAMCAAgKRRMIZAD0AQACAAgKRRMIZAD0AQAeAAEKzQgLLAAsAAAAAA==.Vernaar:BAAANQAECggIDQABNQAECggIGgACAEUTAA==.Vernah:BAAANQADCgIIAgABNQAECggIGgACAEUTAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Volætile:BAAANQAECgQIBQABNQAECgoKIgAhAPESAA==.Vonaria:BAAANQAECgUIDAAAAA==.Vorn:BAABNQAECn9rAAILAAoK0BpYIACxAgALAAoK0BpYIACxAgAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAABNQAECn8nAAIbAAgKDBsrDwBxAgAbAAgKDBsrDwBxAgAAAA==.Waamchifu:BAAANQAECgMIBwAAAA==.Waltersight:BAAANQAECgMIBQAAAA==.Warbritt:BAAANQADCgYIBgAAAA==.Warförged:BAAANQAECggICAAAAA==.Warwuff:BAAANQADCgUICAAAAA==.Waterwalkerr:BAAANQADCgYIBgAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgUIDgAAAA==.Whatthezug:BAAANQABCgIIAgABNQAECgQICgANAAAAAA==.Whoforted:BAABNQAECn8uAAMCAAoKUxv7LwBuAgACAAkKxhr7LwBuAgADAAcKzhJVKgDVAQAAAA==.',
Wi='Wisperia:BAAANQAECgEIAQAAAA==.',
Wo='Wormchild:BAAANQADCgQICAAAAA==.',
Wu='Wulrat:BAABNQAECn8UAAMFAAoK5BSLIQDXAAATAAcKrw9NuQCNAQAFAAQKvhmLIQDXAAAAAA==.',
Wy='Wyle:BAAANQAECgQIBwAAAA==.',
Xe='Xelí:BAABNQAECn9sAAIIAAoKoRl+NQCJAgAIAAoKoRl+NQCJAgAAAA==.Xeras:BAAANQADCgIIAwAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAABNQAECn8YAAIOAAkKxxeMTwCAAgAOAAkKxxeMTwCAAgABNQAFFAcIFwAIAPQaAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.Youvbendoted:BAABNQAECn8eAAIHAAoKtiArDQD4AgAHAAoKtiArDQD4AgAAAA==.',
Yu='Yudah:BAAANQAECgQIBAAAAA==.',
Za='Zaldorina:BAAANQAECgEIAQAAAA==.Zanghonghua:BAABNQAECn9AAAIiAAoKwRv1DwBJAgAiAAoKwRv1DwBJAgAAAA==.',
Ze='Zemy:BAACNQAFFH8FAAIaAAUK0BONEwAyAQAaAAUK0BONEwAyAQA1AAQKfzEAAxoACgocJbAKAHcDABoACgocJbAKAHcDABsABwrTFy0fAKUBAAAA.Zeneca:BAAANQAECgIIAgABNQAFFAQICgADAHQNAA==.',
Zo='Zodshot:BAAANQADCgQIBAAAAA==.Zodstrike:BAABNQAECn84AAMKAAkKnAr5NQBZAQAKAAkKnAr5NQBZAQAgAAcK4QP3OwCvAAAAAA==.Zooboo:BAABNQAECn8fAAIkAAoK5xbZBwAbAgAkAAoK5xbZBwAbAgAAAA==.',
Zu='Zugwuff:BAAANQADCgEIAQAAAA==.Zugzuggler:BAABNQAECn80AAITAAoKnRvpOABOAgATAAoKnRvpOABOAgAAAA==.',
Zy='Zyrick:BAAANQABCggICwAAAA==.',
['Ät']='Ätticus:BAAANQADCgQIBAABNQAECgQICgANAAAAAA==.',
['Öv']='Överpöwered:BAAANQAECgQICQABNQAECgQICgANAAAAAA==.',
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
