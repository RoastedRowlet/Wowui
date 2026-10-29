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

local lookup = {'Paladin-Retribution','Priest-Holy','Priest-Shadow','Unknown-Unknown','Shaman-Restoration','Rogue-Assassination','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Paladin-Holy','Druid-Restoration','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','Druid-Guardian','Rogue-Subtlety','Druid-Feral','Druid-Balance','Warlock-Affliction','Paladin-Protection','Priest-Discipline','Monk-Mistweaver','DemonHunter-Devourer','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Shaman-Elemental','Hunter-Survival',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Absolutepast:BAAANQAECgEIAgAAAA==.',
Ac='Acanaline:BAAANQAECgEIAQAAAA==.Acesfull:BAAANQAECgEIAQAAAA==.Achannara:BAABNQAECn8tAAIBAAkKBwXyrAD9AAABAAkKBwXyrAD9AAAAAA==.',
Ae='Aelaríon:BAAANQAECgEIAQAAAA==.Aeloria:BAAANQADCgIIAgAAAA==.Aeoliana:BAABNQAECn8lAAICAAoKmRMILgALAgACAAoKmRMILgALAgAAAA==.',
Aj='Ajier:BAACNQAFFH8OAAICAAUK2g6IEgB5AQACAAUK2g6IEgB5AQA1AAQKfzsAAgIACgqcGd8jAEkCAAIACgqcGd8jAEkCAAAA.',
Al='Alaaris:BAAANQAECgEIAQAAAA==.Allcapwne:BAAANQADCggIIAAAAA==.Alucart:BAABNQAECn8aAAIDAAgK/A6vHgATAQADAAgK/A6vHgATAQAAAA==.',
Am='Amerissis:BAAANQAECgEIAwABNQAECgEIBAAEAAAAAA==.',
An='Angela:BAABNQAECn8qAAICAAoKoBrCOACFAgACAAoKoBrCOACFAgAAAA==.Animalchin:BAAANQAECgEIAgABNQAECgoKIAAFABwZAA==.Annadanna:BAAANQAECgUIDQAAAA==.Annalunà:BAAANQAECgMIBQAAAA==.Anogrips:BAAANQADCgIIAgAAAA==.Anoheals:BAAANQADCggIAgAAAA==.Anowars:BAAANQAECgUIBwAAAA==.Antithicus:BAAANQADCgYIBgAAAA==.',
Ap='Apeople:BAABNQAECn86AAIGAAoK7x6sAwCyAgAGAAoK7x6sAwCyAgAAAA==.Apocalýpsè:BAABNQAECn8YAAIHAAYK+hftEAAqAQAHAAYK+hftEAAqAQAAAA==.Applebottum:BAAANQAECgcIEQAAAA==.Applebottumj:BAAANQAECgQIBAAAAA==.Appärition:BAABNQAECn8xAAMIAAkKbxxLEgDiAQAJAAkKmBruLgDzAQAIAAYK/hdLEgDiAQAAAA==.',
Ar='Arondael:BAABNQAECn8lAAIGAAkKpQ0HFABbAQAGAAkKpQ0HFABbAQAAAA==.',
As='Ashelaandrii:BAACNQAFFH8FAAIFAAIKpiCeHACxAAAFAAIKpiCeHACxAAA1AAQKfyMAAgUACQo2I54QAEADAAUACQo2I54QAEADAAAA.Astroglyde:BAAANQAECgQIBQAAAA==.Astryd:BAABNQAECn8cAAMKAAkKrAYiEwCsAAAKAAkKrAYiEwCsAAALAAEKAABMegAAAAABNQAECgkJJQAMAFgHAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAABNQAECn8vAAINAAgKHA3KbQBrAQANAAgKHA3KbQBrAQAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùvina:BAAANQADCgIJAgAAAA==.',
Ba='Badru:BAAANQAECgIIBAAAAA==.Bagmaster:BAABNQAECn84AAICAAoKeCXoBgCOAwACAAoKeCXoBgCOAwAAAA==.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAABNQAECn8hAAIFAAoK8Rj1OwBvAgAFAAoK8Rj1OwBvAgAAAA==.Barie:BAAANQAECgIIAgABNQAECgkJJQALAHsdAA==.Barthallomew:BAAANQAECgQIBAABNQAECgQIDQAEAAAAAA==.Bayonetta:BAABNQAECn8qAAIOAAoKRhnnOwDxAQAOAAoKRhnnOwDxAQAAAA==.',
Be='Bellann:BAAANQAECgIIBAAAAA==.',
Bi='Birghid:BAAANQABCgIIAgAAAA==.Birgite:BAABNQAECn8YAAIPAAYKQwvVRQArAQAPAAYKQwvVRQArAQAAAA==.',
Bl='Blackdracula:BAAANQAECgQICwAAAA==.Blasphemar:BAAANQADCggIEAAAAA==.Blazefury:BAAANQAECgQICQAAAA==.Blazeknight:BAABNQAECn8yAAILAAoKORjzLQA1AgALAAoKORjzLQA1AgAAAA==.Blazemaker:BAABNQAECn8rAAIQAAkKgxZ/CgAgAgAQAAkKgxZ/CgAgAgAAAA==.Blazemaster:BAAANQAECgYIDAAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.Bloodsylf:BAAANQADCgcICgABNQAECgcIEgAEAAAAAA==.Blówpop:BAAANQADCgMIAwAAAA==.',
Bo='Bonecrushers:BAABNQAECn8gAAIOAAgKpQvcdQBJAQAOAAgKpQvcdQBJAQAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAABNQAECn8gAAIRAAoKLRaxKgACAgARAAoKLRaxKgACAgAAAA==.Books:BAABNQAECn8ZAAISAAoKxRlMEgC9AgASAAoKxRlMEgC9AgABNQAECgoKIAARAC0WAA==.',
Br='Brainbread:BAABNQAECn8UAAITAAgKIgqTnQDQAAATAAgKIgqTnQDQAAABNQAECgoKQAAJAN0XAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQAECgcIDwAAAA==.Broadside:BAABNQAECn8WAAIOAAoK3BuDIABnAgAOAAoK3BuDIABnAgAAAA==.Brokil:BAAANQAECgIIAgAAAA==.Brolymorph:BAACNQAFFH8JAAINAAQKlxHZNQDtAAANAAQKlxHZNQDtAAA1AAQKfy0AAg0ACgofHicnAFkCAA0ACgofHicnAFkCAAAA.Brossiere:BAAANQADCgQIBAAAAA==.Broverheal:BAAANQAECgMICQAAAA==.Bru:BAACNQAFFH8FAAICAAIKzRGSHQCMAAACAAIKzRGSHQCMAAA1AAQKfyUAAgIACgo6EkheAAYCAAIACgo6EkheAAYCAAAA.Brutalizèr:BAAANQAECgEIAQAAAA==.',
Bt='Bt:BAAANQADCgYIBgAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAABNQAECn8oAAQUAAkKOxxCLwBzAgAUAAgKZxxCLwBzAgAVAAIKSRXPjQB/AAAMAAEKMxsqcQBRAAAAAA==.Burninglight:BAAANQADCgYIEQAAAA==.Burningtree:BAAANQAECggIEgAAAA==.Buthunter:BAAANQAECgUIDAAAAA==.',
['Bâ']='Bâhtilâ:BAAANQAECgYIAQAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECgoKZQAWAGIiAA==.',
Ca='Camamoonmana:BAABNQAECn8aAAMSAAoKHQ9+JwDlAQASAAoKHQ9+JwDlAQAXAAYKmgZ9PQDIAAAAAA==.Canonbalizer:BAAANQAECgEIAQABNQAECggIFwAUAPIgAA==.Caplevi:BAABNQAECn8pAAMYAAoKaRu0JwDqAQAYAAoKXhm0JwDqAQAGAAQK4RTCPgByAAAAAA==.Carrìon:BAAANQADCgEIAQAAAA==.Caskket:BAAANQAECgYIEQAAAA==.Catdog:BAAANQADCgYIBgAAAA==.Catechism:BAABNQAECn8WAAIRAAgKsxokXQABAgARAAgKsxokXQABAgAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAABNQAECn85AAILAAoKpyEoCQDBAgALAAoKpyEoCQDBAgAAAA==.',
Ch='Chaningtotèm:BAAANQAECgEIAQAAAA==.Charan:BAAANQADCgYICgAAAA==.Chickennuggi:BAAANQAECgEIAQABNQAFFAUIDwAUAD0jAA==.Chiphoof:BAABNQAECn8WAAIZAAgKJBFKGAB2AQAZAAgKJBFKGAB2AQAAAA==.Chopndot:BAAANQAECgYIEwAAAA==.',
Cl='Clarabuns:BAABNQAECn8WAAMRAAkKmRryQgBZAgARAAgKphnyQgBZAgABAAIKaRBrbQFxAAAAAA==.Clawdragoon:BAEBNQAECn81AAMXAAkKzhvQEgCHAQAaAAkKJRuTJQCmAgAXAAkK/hDQEgCHAQAAAA==.',
Co='Corine:BAAANQADCgUIBgAAAA==.Corndogmatt:BAAANQADCgUICAAAAA==.',
Cr='Creatlach:BAACNQAFFH8WAAIFAAYK4xmeBwDdAQAFAAYK4xmeBwDdAQA1AAQKfz4AAgUACgpiJDsNAFYDAAUACgpiJDsNAFYDAAAA.Creatlachtwo:BAAANQAECggIDwABNQAFFAYIFgAFAOMZAA==.Creeptoken:BAAANQADCgQIBQAAAA==.Crucifilth:BAAANQAECgEIAQAAAA==.Crystallight:BAABNQAECn8YAAQWAAgKfQXbBABnAAANAAgK8QMoOwEqAQAWAAIKGAbbBABnAAAQAAMKLwXgOgBTAAAAAA==.',
Cy='Cyraxx:BAAANQAECgEIAQAAAA==.Cytherea:BAAANQAECggIEwAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgoKIgAGADcSAA==.Dalinek:BAABNQAECn8hAAMGAAoKbhyUFwC/AgAGAAoKVReUFwC/AgAYAAQKxSAaPgBpAQAAAA==.Damah:BAAANQAECgEIAgABNQADCggIHQAEAAAAAA==.Dandelo:BAAANQAECgEIAQAAAA==.Danicarkel:BAABNQAECn9BAAQbAAoKrhwnAgAOAwAbAAoKrhwnAgAOAwAIAAQKwQpzMgD7AAAJAAIKpwt2LQFiAAAAAA==.Dans:BAAANQAECgEIAQAAAA==.Darkdlord:BAABNQAECn8hAAMMAAoKDgnESwC2AAAVAAcK4gmwTADjAAAMAAkKKgXESwC2AAABNQAECgoKKAABALwPAA==.Darío:BAAANQAECgIIAQABNQAECgQIDQAEAAAAAA==.',
Dd='Ddpaladini:BAABNQAECn8oAAMBAAoKvA/gfQBVAQABAAoKvA/gfQBVAQAcAAkKIAerNwAtAQAAAA==.',
De='Deathtracker:BAABNQAECn8eAAIOAAcK1Au2pQC6AQAOAAcK1Au2pQC6AQAAAA==.Deathtrops:BAAANQAECgIIAgABNQAFFAcIIQAJAFkjAA==.Demindan:BAAANQAECgEIAQAAAA==.Demise:BAACNQAFFH8VAAMNAAcKdBH0EQDoAQANAAYKoRL0EQDoAQAQAAEKwAzpDQBVAAA1AAQKf0IAAw0ACgqTIwIRANMCAA0ACgqTIwIRANMCABAAAQr3G0U8AE4AAAAA.Demontickler:BAAANQADCggIDQABNQAECgYJEAAEAAAAAA==.',
Di='Dianabol:BAABNQAECn8jAAITAAkK+BnERgC1AgATAAkK+BnERgC1AgABNQAECgoKMgAFAOolAA==.Diego:BAAANQADCgYIDAABNQADCggIEAAEAAAAAA==.Dirkuatah:BAAANQAECgQIBwAAAA==.Dista:BAACNQAFFH8JAAIJAAQK+xBYEADPAAAJAAQK+xBYEADPAAA1AAQKfzsAAgkACgpGHdsTAIoCAAkACgpGHdsTAIoCAAAA.Divinebovine:BAAANQAECgEIAgAAAA==.Divinedragon:BAABNQAECn8uAAMDAAoKMhacFQB1AQADAAkK7RScFQB1AQAdAAQKvBoeFADnAAAAAA==.',
Do='Doboy:BAAANQAECgEIAQAAAA==.Dotsncandies:BAAANQAECgIIAgAAAA==.Doublevegan:BAAANQADCgMJAwAAAA==.',
Dr='Drakin:BAAANQAECggIEgAAAA==.Drawbridge:BAAANQADCgYIDQAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAACNQAFFH8IAAIFAAMKCQ9AEQDKAAAFAAMKCQ9AEQDKAAA1AAQKfzMAAgUACgoGFo5PACcCAAUACgoGFo5PACcCAAAA.Drinkoolaide:BAAANQAECgIIAgABNQAFFAMICAAFAAkPAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQAECgEIAwAAAA==.Dunamis:BAABNQAECn8jAAINAAkKlRzKWQDMAgANAAkKlRzKWQDMAgAAAA==.Dungodon:BAAANQADCggIDgAAAA==.Durrt:BAAANQAECgYIEAAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAACNQAFFH8PAAMPAAYK4BaRDgBUAQAPAAUKoRCRDgBUAQAOAAMK6B6CHABoAAA1AAQKfzsAAw4ACgrpJV8RAFwDAA4ACgrpJV8RAFwDAA8ACgqvH4kGAJkCAAAA.',
Ei='Einaria:BAAANQAECgEIAQABNQAECgkJKgANANAaAA==.',
El='Eldrene:BAABNQAECn8qAAINAAkK0BrJPgD5AQANAAkK0BrJPgD5AQAAAA==.Elizalde:BAAANQAECgYIEQAAAA==.Ellexi:BAAANQAECgQICgAAAA==.Elyseia:BAABNQAECn8hAAIOAAkKsw8JewAYAgAOAAkKsw8JewAYAgAAAA==.',
En='Enpower:BAAANQAECgQIBQABNQAFFAMIBgAeAAAFAA==.',
Ep='Epicsause:BAAANQAECgYIBgAAAA==.',
Es='Escata:BAAANQAECgMIBAAAAA==.Esdailongwe:BAAANQADCgUIBwAAAA==.Españamor:BAEBNQAECn8jAAMfAAoKiRD+HQA7AQAfAAoKxg/+HQA7AQAKAAcKugncGAAkAQABNQAFFAIIAgAEAAAAAA==.',
Eu='Eunite:BAABNQAECn9jAAIUAAoKER2kKACWAgAUAAoKER2kKACWAgAAAA==.',
Fa='Falkorne:BAAANQAECgcIEQABNQAECgoKKQAeALQYAA==.Fangdoo:BAAANQAECgEIAQABNQAECgcIFAAMAD8OAA==.Farael:BAAANQADCgYIBgAAAA==.Fashah:BAAANQAECgIIBAAAAA==.Fatalmann:BAAANQAECgIIBQAAAA==.',
Fe='Felmoo:BAABNQAECn8VAAIXAAkKrAQ8JADoAAAXAAkKrAQ8JADoAAAAAA==.Felorc:BAABNQAECn8eAAMHAAkKFwQCKwDhAAAHAAkKFwQCKwDhAAATAAIKKAIbTQE6AAABNQAECgkJJQAMAFgHAA==.Feralhorn:BAAANQAECgYIBwAAAA==.',
Fi='Fintan:BAAANQADCggICAABNQAFFAYIFgAFAOMZAA==.',
Fo='Forsakenemp:BAAANQAECggIEAABNQAECgoKKAABALwPAA==.',
Fr='Frassk:BAABNQAECn8tAAMIAAoKMw8nEwCAAAAJAAgKsA3TlQCwAQAIAAIKuRMnEwCAAAAAAA==.Frigid:BAAANQAECgEIAQAAAA==.Froggystyle:BAAANQAECggIEwAAAA==.Frozenheart:BAABNQAECn8lAAMMAAkKWAe5dwAZAQAMAAkKCge5dwAZAQAVAAQKZgZQdQBjAAAAAA==.Fruk:BAAANQADCgUIBQAAAA==.Frösting:BAAANQADCgYIBgABNQAECgkJHAAgAFUSAA==.',
Ft='Ftx:BAABNQAECn8qAAITAAkKTiE3SgCqAgATAAkKTiE3SgCqAgAAAA==.',
Fu='Fundidos:BAAANQADCggIEAAAAA==.Furfoxxsakes:BAAANQADCgEIAQAAAA==.',
Ga='Garbarn:BAAANQADCgcIDQAAAA==.',
Ge='Gelystine:BAAANQADCgIIAgAAAA==.Geminichi:BAACNQAFFH8GAAIeAAMKAAWKBQCkAAAeAAMKAAWKBQCkAAA1AAQKfzUAAx4ACgoPGmMIAEwCAB4ACgoPGmMIAEwCACEAAgqFEClqADcAAAAA.Geminishadow:BAAANQAECgcIEgAAAA==.',
Gh='Ghauri:BAAANQADCgYJBgAAAA==.Ghorza:BAAANQADCgYIBwAAAA==.',
Gi='Gia:BAABNQAECn8vAAIeAAkKJRtiCwDoAQAeAAkKJRtiCwDoAQAAAA==.Gigasauce:BAAANQAECgEIAQAAAA==.Giraffage:BAABNQAECn8WAAINAAcK6Q9j4ADIAQANAAcK6Q9j4ADIAQABNQAECgcICQAEAAAAAA==.',
Go='Golgroth:BAAANQADCgQJBAAAAA==.Gorearrow:BAACNQAFFH8FAAIOAAIKdxQCFACmAAAOAAIKdxQCFACmAAA1AAQKfzcAAg4ACgroH7cgAGUCAA4ACgroH7cgAGUCAAAA.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Grimmtotem:BAAANQAECggICAAAAA==.Groggyfroggy:BAAANQADCgMJAwAAAA==.Grralt:BAAANQAECgIIBQABNQADCggIHQAEAAAAAA==.Grís:BAABNQAECn8sAAMTAAoKpxeTaABWAgATAAoKpxeTaABWAgAHAAMKCA3uMwCXAAAAAA==.',
Gu='Gumbuz:BAAANQAECgQIBAAAAA==.Gunafistya:BAAANQAECgMIBQAAAA==.',
Ha='Harrier:BAAANQADCgYICgABNQAECggIFgAZACQRAA==.Hazed:BAABNQAECn8VAAINAAkKIAzLWQCfAQANAAkKIAzLWQCfAQAAAA==.Hazyblades:BAAANQAECgIIAgAAAA==.Hazzaa:BAAANQAECgcICwAAAA==.',
He='Healzforbeer:BAAANQADCgUIBQAAAA==.Heila:BAAANQAECgIIAgAAAA==.Henso:BAAANQAECgQIBAABNQAFFAMIBgAeAAAFAA==.Herioffy:BAAANQADCgEIAQAAAA==.Hexxan:BAAANQAECgEIAQAAAA==.',
Hi='Hiawatha:BAAANQAECgEIAQAAAA==.Hiver:BAAANQAECgEIAgAAAA==.',
Ho='Holier:BAABNQAECn85AAIBAAoK5g9EUgC/AQABAAoK5g9EUgC/AQAAAA==.Holybishh:BAAANQAECgUIBQAAAA==.Holyregerts:BAABNQAECn8iAAMDAAoKxhAwJAAPAgADAAkKQRAwJAAPAgACAAgKRxiDcQDIAQAAAA==.Honk:BAAANQAECggIEwAAAA==.Hoochurcooch:BAAANQAECgQIBQAAAA==.Hoosnext:BAAANQAECgEIAQAAAA==.Hopperstotem:BAAANQAECgMIAwABNQAECgoKFgAOANwbAA==.',
Hu='Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQAECgMIBQAAAA==.',
Il='Illumi:BAAANQABCgYIBgAAAA==.',
Im='Imbatmann:BAAANQADCgEIAQAAAA==.',
In='Indrà:BAAANQADCgQIBQAAAA==.Infamus:BAAANQAECgIIBgAAAA==.Invysion:BAACNQAFFH8OAAMdAAUKMQKWAQApAQAdAAUKEAKWAQApAQACAAIKyAGwIABxAAA1AAQKfzsAAx0ACgrGE1gCAA4CAB0ACgqNE1gCAA4CAAIAAQqoBgrKADIAAAAA.',
Is='Ishara:BAAANQAECgEIAQABNQAECgkJKgANANAaAA==.Islander:BAAANQAECgYIEgAAAA==.',
Ja='Jackychang:BAABNQAECn8VAAIYAAgK5w1hGwD7AQAYAAgK5w1hGwD7AQAAAA==.Jaidess:BAAANQADCggIDgAAAA==.Jakeypoo:BAAANQAECgQIDAAAAA==.',
Je='Jellybea:BAACNQAFFH8FAAICAAIK2Q3fHgCDAAACAAIK2Q3fHgCDAAA1AAQKfykAAwIACgp7HnUrALsCAAIACgp7HnUrALsCAAMAAgoAAHZqAFkAAAAA.',
Ji='Jimmee:BAAANQADCgIIAgAAAA==.',
Ju='Jukoti:BAAANQABCgIIBAAAAA==.Junglebrew:BAAANQAECgEIAgAAAA==.Junglepino:BAAANQAECgEIAQAAAA==.Jurisdiction:BAABNQAECn8aAAIBAAgK6gYewgDZAAABAAgK6gYewgDZAAAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAABNQAECn8xAAIhAAoKDhzTDwDoAgAhAAoKDhzTDwDoAgAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kanalz:BAAANQAECgUIBQAAAA==.Kappowee:BAAANQAECgEIAwAAAA==.Kasey:BAABNQAECn8VAAIBAAYK8B4guwCnAQABAAYK8B4guwCnAQAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keho:BAABNQAECn8aAAIiAAgKbATPDwDBAAAiAAgKbATPDwDBAAAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAACNQAFFH8MAAMLAAQKNRSjDwAMAQALAAQKNRSjDwAMAQAfAAEKIQqTDQBBAAA1AAQKfzkAAx8ACgonHrkYAJYCAB8ACgr8G7kYAJYCAAsACgo/G9ghAI0CAAE1AAQKBwgJAAQAAAAA.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kickdrop:BAAANQADCgQIBAAAAA==.Kilgreed:BAAANQAECgEIAQAAAA==.Killaban:BAAANQAECgcICAAAAA==.Killbydeath:BAABNQAECn8XAAQUAAgK8iCBFgDMAQAUAAgK8R6BFgDMAQAMAAIKax9anACiAAAVAAIKjxQ9YwCWAAAAAA==.Kimberlyhárt:BAAANQAECgYJEAAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYJEAAEAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAABNQAECn9jAAIJAAoKWRycHABTAgAJAAoKWRycHABTAgAAAA==.',
Ko='Kohman:BAABNQAECn9AAAMJAAoK3RdAMQDDAgAJAAoK3RdAMQDDAgAIAAMKMg1xUgCIAAAAAA==.Komatose:BAAANQADCgYIBgAAAA==.Kong:BAAANQADCgIIAwAAAA==.',
Kr='Krftpnk:BAACNQAFFH8hAAILAAgKRyCBAQC0AgALAAgKRyCBAQC0AgA1AAQKfz8AAgsACgrWJoQBAGYDAAsACgrWJoQBAGYDAAAA.Kricket:BAAANQAECgEIAgAAAA==.Kronas:BAABNQAECn8UAAIOAAgKKxQ3jwDrAQAOAAgKKxQ3jwDrAQAAAA==.Kronosity:BAABNQAECn8uAAIcAAoKjx+mCgDwAgAcAAoKjx+mCgDwAgABNQAFFAIIBQAMADAfAA==.Kronotality:BAACNQAFFH8FAAIMAAIKMB8IDgC5AAAMAAIKMB8IDgC5AAA1AAQKf0QAAgwACgpgI8MFAJcDAAwACgpgI8MFAJcDAAAA.Kronotekken:BAAANQAECgEIAgABNQAFFAIIBQAMADAfAA==.Kronotide:BAAANQADCgQIBAABNQAFFAIIBQAMADAfAA==.Krothas:BAAANQAECgEIAQAAAA==.',
Ku='Kungfukittn:BAABNQAECn8dAAIhAAcKIxagKwC+AQAhAAcKIxagKwC+AQAAAA==.Kurze:BAAANQAECgIIBQAAAA==.',
Ky='Kylorai:BAAANQAECggIEAAAAA==.Kyojuro:BAAANQABCgYIBgAAAA==.',
Kz='Kzorx:BAAANQAECgIIAgAAAA==.',
La='Laimaster:BAAANQAECgQIBAAAAA==.Lakiri:BAABNQAECn8oAAIgAAcK/hTvFwDpAQAgAAcK/hTvFwDpAQAAAA==.Landaeda:BAAANQADCggIDwAAAA==.Lascivia:BAACNQAFFH8FAAIHAAIK/RvbAgCkAAAHAAIK/RvbAgCkAAA1AAQKfyoAAwcACgosIVoGAAIDAAcACgosIVoGAAIDACMABAoAGPsYABIBAAAA.Latrice:BAAANQAECgcIBwABNQAFFAcIEwAQAOAdAA==.Laylahh:BAAANQADCgQIBAAAAA==.Lazereyes:BAAANQAECgYIBgAAAA==.',
Le='Leademon:BAABNQAECn8gAAILAAoK5hezHgCiAQALAAoK5hezHgCiAQAAAA==.Leadmln:BAAANQAECgYIDAABNQAECgoKIAALAOYXAA==.Lebwonsamdi:BAAANQAECgUIBgABNQAECgoKLAATAKcXAA==.Lethalkrits:BAAANQAECggIAgAAAA==.',
Li='Lighterfluîd:BAAANQAECgEIAQABNQAECgoKLgAeAFEfAA==.Ligmadk:BAAANQADCgUIBQABNQAFFAQIBwALAIMIAA==.Lilbeebs:BAAANQAECgIIAgAAAA==.Lilflea:BAABNQAECn8gAAMFAAoKHBkuOAC7AQAFAAoKHBkuOAC7AQAkAAEKAAD5TAEnAAAAAA==.Lillidari:BAAANQAECgcICgABNQAECgkJJgAMACwkAA==.Lilzuki:BAAANQAECggICwAAAA==.Lilïth:BAABNQAECn8mAAIMAAkKLCQkCwBbAwAMAAkKLCQkCwBbAwAAAA==.Linguine:BAAANQADCggICAABNQAFFAQICgADAHQNAA==.Lisalisa:BAABNQAECn8nAAIFAAkKbhKqPgCdAQAFAAkKbhKqPgCdAQAAAA==.Littlej:BAAANQAECgQJBAAAAA==.Littlejohn:BAABNQAECn8pAAIeAAoKtBjtEABwAgAeAAoKtBjtEABwAgAAAA==.',
Lo='Logantis:BAABNQAECn8XAAITAAkKOBK6NAABAgATAAkKOBK6NAABAgAAAA==.Logaothe:BAABNQAECn8YAAIBAAYKJQpOAgEbAQABAAYKJQpOAgEbAQAAAA==.Lokee:BAAANQADCgUIBQAAAA==.',
Lu='Lucky:BAAANQAECggIEQAAAA==.Lukethywalkr:BAAANQAECgIIAgAAAA==.Lularia:BAAANQADCgUICAAAAA==.Lunaa:BAAANQAECgQIBwAAAA==.Lusid:BAAANQAECgEIAQAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Makagh:BAAANQAECgEIBQAAAA==.Maliciousrot:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQICAAAAA==.Marona:BAAANQAECggIAQAAAA==.',
Me='Medikus:BAABNQAECn8sAAMFAAkKWxoLIwAwAgAFAAkKWxoLIwAwAgAkAAEKKQT/ygAuAAAAAA==.Medina:BAAANQAECggIAQAAAA==.Megajoo:BAAANQAECgcIDAAAAA==.Melkinov:BAAANQAECgEIAgAAAA==.Merryl:BAAANQAECgUICgAAAA==.',
Mf='Mfive:BAAANQAECgQIBQAAAA==.',
Mi='Mike:BAEBNQAECn8cAAINAAkK4iGtUQDdAgANAAkK4iGtUQDdAgAAAA==.Milkjugs:BAAANQAECgQICAABNQAECgoKIAAFABwZAA==.Minijeangen:BAAANQAECgMJAwAAAA==.Missluana:BAAANQABCgEIAQAAAA==.Mizshankalot:BAAANQADCgcICAABNQAECgoKKAABALwPAA==.',
Mo='Mockra:BAABNQAECn9AAAINAAgKGhZxrAApAgANAAgKGhZxrAApAgAAAA==.Moistmunnky:BAAANQAECgYIDgAAAA==.Montera:BAEANQAFFAIIAgAAAA==.Moohammered:BAABNQAECn8oAAIBAAoK0hJpQQD2AQABAAoK0hJpQQD2AQAAAA==.Moolou:BAACNQAFFH8FAAIcAAIKWQswBwB0AAAcAAIKWQswBwB0AAA1AAQKfygAAhwACgo0Gu0QAJECABwACgo0Gu0QAJECAAAA.Mootarded:BAABNQAECn8UAAIcAAkK5wSLMACUAAAcAAkK5wSLMACUAAABNQAECgkJJQAMAFgHAA==.Mordiggian:BAABNQAECn88AAMMAAoKZSTQDwAvAwAMAAkKbyXQDwAvAwAUAAkKZiMFGQD3AgAAAA==.Morechie:BAABNQAECn8oAAIbAAgKAxEkCQD0AQAbAAgKAxEkCQD0AQAAAA==.Morganaj:BAAANQAECgQIBgAAAA==.Morgatho:BAAANQABCgcICQAAAA==.Morsz:BAAANQAECgUIDAAAAA==.Mortiferon:BAABNQAECn8jAAIUAAkKShrUOwAyAgAUAAkKShrUOwAyAgAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQAECgYIDgAEAAAAAA==.Munnkypox:BAAANQAECgIIBgABNQAECgYIDgAEAAAAAA==.Murderella:BAAANQADCgYIBgAAAA==.Muriggs:BAAANQAECgMIBAAAAA==.Murkhoof:BAAANQADCgYIBgABNQAECggIFgAZACQRAA==.',
['Mö']='Mörgänä:BAAANQADCggIEQAAAA==.',
Na='Nakovii:BAAANQAECgUIBgAAAA==.Nascerathel:BAAANQAECgYICAAAAA==.Nasmina:BAAANQAECggIAgAAAA==.',
Ne='Nealite:BAAANQADCgYIBgAAAA==.Neerem:BAAANQABCggIDQAAAA==.Neferata:BAABNQAECn89AAMJAAoKWRuANwCuAgAJAAoKWRuANwCuAgAIAAYKbgvNJwA6AQAAAA==.Nerrisa:BAAANQAECgEIAQAAAA==.Nertmage:BAABNQAECn9lAAQWAAoKYiJQAACfAwAWAAoKYiJQAACfAwANAAIKAA7+vAFEAAAQAAEKThm3KgA+AAAAAA==.Neublood:BAAANQAECgQICQAAAA==.',
Ni='Nicodemus:BAAANQAECgYIEAAAAA==.Nineiota:BAABNQAECn8nAAISAAoKNRlrGQBwAgASAAoKNRlrGQBwAgAAAA==.',
No='Noblewarrior:BAACNQAFFH8gAAITAAcK7hQBEQCtAQATAAcK7hQBEQCtAQA1AAQKfz8AAxMACgp9Ih0aAE8DABMACgp9Ih0aAE8DACMAAQq2HVQcAFoAAAAA.Nobukawaii:BAAANQAECgMIAwAAAA==.Noctilus:BAAANQADCgcIEwAAAA==.Noke:BAAANQAECgIJAwAAAA==.Noril:BAAANQADCgUIBQAAAA==.Notakoala:BAACNQAFFH8QAAIaAAYKABaZEABhAQAaAAYKABaZEABhAQA1AAQKfzkAAhoACgocIg8IANcCABoACgocIg8IANcCAAAA.Nothnx:BAACNQAFFH8LAAIOAAQKnRTmCwD0AAAOAAQKnRTmCwD0AAA1AAQKfzEAAg4ACgq6HV8WAKECAA4ACgq6HV8WAKECAAAA.Notillidan:BAAANQADCgYICgAAAA==.Notoriouspat:BAAANQAECggIDwAAAA==.Novia:BAAANQAECgcIEgABNQAECgoKLAATAKcXAA==.Noxeternis:BAABNQAECn8yAAQDAAoKRRkyIQAuAgADAAkKXBgyIQAuAgACAAUK2BvqWQBMAQAdAAIKMgYgJABKAAAAAA==.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
Ny='Nyxandra:BAAANQADCgYICwAAAA==.',
['Ní']='Níghtfall:BAAANQADCgUICwAAAA==.Nínebreaker:BAAANQAECgEIAQAAAA==.',
['Nü']='Nüll:BAAANQADCgQIBAAAAA==.',
Ob='Obern:BAABNQAECn8cAAIlAAoK+BI5BQBzAgAlAAoK+BI5BQBzAgAAAA==.Obeysnapback:BAAANQADCgMIBAAAAA==.Oblïna:BAAANQAECgUIEgAAAA==.',
Od='Oddishh:BAABNQAECn8WAAMVAAoKrgpnRwD5AAAMAAYK6wivfQADAQAVAAkK4ApnRwD5AAAAAA==.',
Ol='Olleg:BAAANQADCgYICQAAAA==.',
Om='Omnicarkel:BAAANQADCgcIDAAAAA==.',
On='Onsen:BAABNQAECn8mAAIBAAoKvBYaWwCHAgABAAoKvBYaWwCHAgABNQAECgoKQAAJAN0XAA==.',
Or='Oresties:BAAANQADCggICAAAAA==.Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQJBAAAAA==.',
Ou='Outwithabang:BAAANQAECgMIAwAAAA==.',
Pa='Pajl:BAABNQAECn8qAAIBAAoKeiOtDQCXAwABAAoKeiOtDQCXAwABNQAFFAcIDwAVAKMeAA==.Pandablaze:BAAANQAECgQIBQAAAA==.Pandajoy:BAAANQADCgEIAQAAAA==.Panterarey:BAAANQAECgIIAgAAAA==.Papanurrgle:BAAANQAECgUICwAAAA==.Papazilla:BAAANQAECgMJBAAAAA==.Parakka:BAAANQAECgQIBQAAAA==.Patak:BAAANQADCgQIBQAAAA==.Pawp:BAABNQAECn8WAAMFAAkKERF+OAC6AQAFAAkKERF+OAC6AQAgAAMKQwFYMQBfAAAAAA==.Paxiel:BAAANQAECgQICAAAAA==.',
Pe='Pearagon:BAAANQAECggICQABNQAFFAcIFAAFAKcXAA==.Pepsidew:BAAANQAECggICwAAAA==.Pepsisprite:BAABNQAECn8cAAICAAgKOBlGNwDbAQACAAgKOBlGNwDbAQAAAA==.',
Ph='Phdbeef:BAAANQAECgEIAgABNQAECgkJJgAMACwkAA==.Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQAECgIIBwAAAA==.',
Pi='Picklez:BAABNQAECn8bAAIVAAYKLhrsPwDJAQAVAAYKLhrsPwDJAQAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.Portwings:BAAANQAECgIIAgAAAA==.',
Ps='Psyop:BAAANQADCggIGAABNQAECgoKRgACAD4iAA==.Psyrax:BAAANQAECgQICAAAAA==.',
Pu='Pushemover:BAAANQAECgEIAgAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Rashun:BAAANQAECgIIAgAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQAECgEIAgAAAA==.Redkoala:BAABNQAECn8XAAINAAYKjgb0rgDpAAANAAYKjgb0rgDpAAABNQAFFAYIEAAaAAAWAA==.Regrets:BAAANQAECgQIBAABNQAECgoKIgADAMYQAA==.Repete:BAAANQAECgQIBgAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECn9jAAIQAAoKxCASAgBaAwAQAAoKxCASAgBaAwAAAA==.Reven:BAAANQAECgYICwAAAA==.',
Rh='Rhak:BAAANQAECgEIAgAAAA==.',
Ri='Riivan:BAAANQAECgIIAgAAAA==.Rirugiliyang:BAAANQAECgEIAQAAAA==.Rivian:BAAANQAECgIIAwABNQAECgYIEgAEAAAAAA==.',
Ro='Roardon:BAAANQADCggIDwAAAA==.Roflmfao:BAAANQADCggICAAAAA==.Roguè:BAAANQAECgQIDQABNQAECgQIDQAEAAAAAA==.Rollinburn:BAAANQADCgUJBQAAAA==.Romanoff:BAABNQAECn8iAAMGAAoKNxKaPQDZAQAGAAcKBxOaPQDZAQAYAAcKMBGBPAByAQAAAA==.Rosearcana:BAAANQAECgEIAgAAAA==.',
Ry='Ryokhan:BAAANQAECggIAQAAAA==.',
['Rô']='Rôx:BAAANQADCgcIBwABNQAECgoKYQARAL0bAA==.',
['Rõ']='Rõx:BAABNQAECn9hAAMRAAoKvRtOLwCpAgARAAoKvRtOLwCpAgABAAMKBw5cCgFxAAAAAA==.',
Sa='Sackoss:BAABNQAECn8aAAIRAAgKDhaQXwD6AQARAAgKDhaQXwD6AQAAAA==.Saffronspark:BAAANQAECgYIEQABNQAECgoKMwAhAK0aAA==.Sainsei:BAABNQAECn8XAAMiAAgKGxPFHAAbAQAiAAYKnA/FHAAbAQAhAAUKKhBVLQC9AAABNQAECgoKLAATAKcXAA==.Sakata:BAAANQADCgIIAgABNQAECggIFgAZACQRAA==.Sandwitch:BAABNQAECn9jAAMIAAoKsRNuDwAGAgAJAAoKPBIjYAA4AgAIAAgKTxBuDwAGAgAAAA==.Sargatanas:BAABNQAECn8jAAIMAAkK8gw/UgCsAQAMAAkK8gw/UgCsAQAAAA==.Sars:BAAANQADCgUIBQABNQAECgYIEgAEAAAAAA==.',
Sc='Scarcroww:BAAANQADCgMIAwABNQAECgoKIwANAGofAA==.Schrodinger:BAAANQAECgIIBwAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Septicflësh:BAAANQAECggICAAAAA==.Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAABNQAECn8nAAIHAAgKOhLZDwA5AQAHAAgKOhLZDwA5AQAAAA==.',
Sh='Shadrad:BAABNQAECn8mAAMBAAoKjh+IJwAoAwABAAoKjh+IJwAoAwARAAYK3AP5xgDtAAAAAA==.Shallot:BAABNQAECn8zAAINAAoK3SDdNwAYAwANAAoK3SDdNwAYAwAAAA==.Shammoo:BAABNQAECn8UAAIkAAgKOxUAYAACAgAkAAgKOxUAYAACAgABNQAFFAQIBgABAMYLAA==.Shammyd:BAABNQAECn8UAAIkAAYKcgJG8QCzAAAkAAYKcgJG8QCzAAAAAA==.Shantz:BAABNQAECn8jAAIMAAkKRQp0LgA1AQAMAAkKRQp0LgA1AQAAAA==.Sharprot:BAAANQAECgYIBgABNQAECgkJHgABAHUZAA==.Shiftface:BAAANQADCggIDgABNQAECggIEwAEAAAAAA==.Shiftmypants:BAABNQAECn8fAAIaAAoKcxVCEwAYAgAaAAoKcxVCEwAYAgAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Si='Sinterdeath:BAABNQAECn8UAAMUAAcKbwjkgwAQAQAUAAYKaQjkgwAQAQAVAAQKTwWecABvAAAAAA==.',
Sk='Skatervan:BAAANQAECgUIBQABNQAECgoKPQADAM0bAA==.Skylie:BAAANQADCgYIDwAAAA==.',
Sl='Slushpuppy:BAAANQAECgIIAgAAAA==.',
Sm='Smallpaladin:BAAANQAECgEIAQAAAA==.Smorthian:BAAANQAECgQIEQAAAA==.',
Sn='Sniffinsteak:BAAANQAECgYJEgAAAA==.Snoosnooftww:BAAANQAECgEIAQAAAA==.',
So='Solas:BAABNQAECn8ZAAICAAYKJBqnQQCsAQACAAYKJBqnQQCsAQAAAA==.Sonarael:BAAANQAECgQIBQABNQAECgkJKgANANAaAA==.Sondeltis:BAAANQAECgQIBQAAAA==.Soryan:BAAANQAECgUIBgAAAA==.',
Sp='Spankenstine:BAABNQAECn8eAAIBAAkKdRktbQBXAgABAAkKdRktbQBXAgAAAA==.Sparkyy:BAAANQAECgIIBAAAAA==.Sphaeram:BAAANQAECgcICgAAAA==.Spicypepsi:BAAANQAECgEIAwAAAA==.Spinfalldown:BAAANQAECgMIBAAAAA==.Spiritnail:BAAANQAECgEIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAABNQAECn8pAAIBAAoK7B9NKABhAgABAAoK7B9NKABhAgAAAA==.Stinkydeathy:BAAANQADCgYJBgABNQAECgIIBwAEAAAAAA==.Stinkydragon:BAAANQAECgIIBwAAAA==.Stormknight:BAAANQAECgYIDQAAAA==.Stormpoo:BAAANQAECgQIBQAAAA==.',
Su='Suneater:BAABNQAECn8kAAIRAAoKNx9TCQAzAwARAAoKNx9TCQAzAwAAAA==.Superpi:BAAANQAECgEIAQABNQAECgUICgAEAAAAAA==.Superret:BAAANQAECgUICgAAAA==.Surotor:BAAANQADCgQICAAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAABNQAECn8YAAIBAAkKhAtSdgBmAQABAAkKhAtSdgBmAQAAAA==.',
Sw='Swíper:BAACNQAFFH8FAAIGAAIKLA8iFwCUAAAGAAIKLA8iFwCUAAA1AAQKfy8AAwYACgogHnkIAFADAAYACgogHnkIAFADABgABQq1CTA4APcAAAAA.',
Sy='Sylphièl:BAACNQAFFH8PAAMYAAYKUgnSDgDIAAAYAAUKDgvSDgDIAAAGAAEKGwSrDABDAAA1AAQKfzAAAxgACgp8G/8XAF0CABgACApYHv8XAF0CAAYACQoxCflBAMMBAAAA.',
['Sö']='Sörceress:BAAANQADCgQIBAAAAA==.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgcIDQAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECn8oAAIBAAkKmiJpLAAWAwABAAkKmiJpLAAWAwAAAA==.Tankenstine:BAABNQAECn8nAAITAAgKdxKrYgBbAQATAAgKdxKrYgBbAQABNQAECgkJHgABAHUZAA==.Tanktop:BAAANQADCgcIBwAAAA==.Tastymilk:BAAANQAECgcIBwAAAA==.Tawnii:BAAANQAECgMIBQAAAA==.Taírn:BAAANQAECgQIBAAAAA==.',
Te='Tenderloin:BAABNQAECn8UAAMLAAcKPg1+VQA4AQALAAYKtAp+VQA4AQAKAAQKVQ7hIwCgAAAAAA==.',
Th='Thanitose:BAAANQAECgYIDwAAAA==.Thevelo:BAAANQAECgYICgABNQAECgcIEgAEAAAAAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thornwyn:BAAANQAECgYIDQAAAA==.Thors:BAAANQADCgQIBAAAAA==.Thorul:BAAANQAECgYIBwAAAA==.Thundurus:BAACNQAFFH8MAAIkAAMKWwejFQB+AAAkAAMKWwejFQB+AAA1AAQKfzwAAiQACgpXFwlGAF4CACQACgpXFwlGAF4CAAAA.',
Ti='Timmayy:BAABNQAECn8UAAIJAAkKrg0TOADJAQAJAAkKrg0TOADJAQABNQAECgoKKQAeALQYAA==.Tindrill:BAAANQAECgMIAwABNQAECgkJJwASAMkhAA==.Tinggoskrrah:BAAANQAECgEIAQAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAABNQAECn8lAAITAAgKgw9sswCcAQATAAgKgw9sswCcAQAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAgIIQALAEcgAA==.Totemagoat:BAACNQAFFH8KAAMFAAYKLw/yDQBuAQAFAAYKLw/yDQBuAQAkAAEKsQXlMgBEAAA1AAQKfz8AAwUACgokIoMWAB0DAAUACgokIoMWAB0DACQACApvFtBgAP8BAAAA.',
Tr='Tracula:BAAANQADCgEIAQAAAA==.Treefist:BAAANQADCggIIgAAAA==.Trollietoes:BAAANQAECgEIAQAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAACNQAFFH8KAAISAAQKcAv6CADCAAASAAQKcAv6CADCAAA1AAQKfzIAAxIACgonFAgdAEsCABIACgonFAgdAEsCABoAAwpMAlphAFAAAAAA.',
Un='Undeadkiels:BAAANQADCggICAABNQAECgoKKAABALwPAA==.Undeadmonks:BAAANQADCgYIBgAAAA==.',
Ur='Uraharakun:BAAANQAECgUIDgABNQAECgoKOwABAKYRAA==.',
Va='Vagalion:BAABNQAECn8ZAAQkAAkKbwldVgAKAQAkAAgKFQldVgAKAQAFAAUK+gyJuAD7AAAgAAQKEQpgHwCqAAAAAA==.Valdanyr:BAAANQADCggIEAAAAA==.Vale:BAAANQAECgMIAwAAAA==.Valeshot:BAABNQAECn8oAAIOAAoKcQ1+dwAgAgAOAAoKcQ1+dwAgAgAAAA==.Valimyr:BAAANQAECgEIAQAAAA==.Valkillrie:BAABNQAECn8UAAMRAAoKohLnIQA5AgARAAoKohLnIQA5AgABAAIKXgq9egFhAAAAAA==.Valohir:BAAANQAECgIIBwAAAA==.Vanhellsin:BAABNQAECn8UAAIMAAcKPw7sZgBXAQAMAAcKPw7sZgBXAQAAAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECgkJFgABAAcjAA==.Vedronas:BAABNQAECn8WAAIBAAkKByPmJQAuAwABAAkKByPmJQAuAwAAAA==.Veos:BAABNQAECn8wAAIQAAoKQRkeBQDIAgAQAAoKQRkeBQDIAgAAAA==.Verdict:BAAANQADCgYIGwAAAA==.Vern:BAABNQAECn8aAAMCAAgKRRMIZAD0AQACAAgKRRMIZAD0AQAdAAEKzQgLLAAsAAAAAA==.Vernaar:BAAANQAECggICAABNQAECggIGgACAEUTAA==.Vernah:BAAANQADCgIIAgABNQAECggIGgACAEUTAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Volætile:BAAANQAECgQIBQABNQAECgkJHAAgAFUSAA==.Vonaria:BAAANQAECgUIBQAAAA==.Vorn:BAABNQAECn9jAAIMAAoKjxlYIACxAgAMAAoKjxlYIACxAgAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAABNQAECn8nAAIXAAgKDBsrDwBxAgAXAAgKDBsrDwBxAgAAAA==.Waamchifu:BAAANQAECgIIAgAAAA==.Waltersight:BAAANQAECgMIBwAAAA==.Warbritt:BAAANQADCgYJBgAAAA==.Warförged:BAAANQAECggICAAAAA==.Warwuff:BAAANQADCgUICAAAAA==.Waterwalkerr:BAAANQADCgYIBgAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgUIDwAAAA==.Whatthezug:BAAANQABCgIIAgABNQAECgQIDAAEAAAAAA==.Whoforted:BAABNQAECn8lAAMCAAoKlxVINgDgAQACAAkKkRRINgDgAQADAAcKzhJVKgDVAQAAAA==.',
Wi='Wisperia:BAAANQAECgIIAgAAAA==.',
Wo='Wormchild:BAAANQADCgQIBgAAAA==.',
Wu='Wulrat:BAABNQAECn8UAAMHAAoK5BQyFgDmAAATAAcKrw9NuQCNAQAHAAQKvhkyFgDmAAAAAA==.',
Wy='Wyle:BAAANQAECgUIDgAAAA==.',
Xe='Xelí:BAABNQAECn9kAAIFAAoKcBl+NQCJAgAFAAoKcBl+NQCJAgAAAA==.Xeras:BAAANQADCgIIAgAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAABNQAECn8YAAIOAAkKxxeMTwCAAgAOAAkKxxeMTwCAAgABNQAFFAYIFgAFAOMZAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.Youvbendoted:BAABNQAECn8WAAIJAAoKzx0kEQCfAgAJAAoKzx0kEQCfAgAAAA==.',
Yu='Yudah:BAAANQAECgEIAQABNQAECgQIBAAEAAAAAA==.',
Za='Zaldorina:BAAANQAECgEIAQAAAA==.Zanghonghua:BAABNQAECn8zAAIhAAoKrRpDDgAIAgAhAAoKrRpDDgAIAgAAAA==.',
Ze='Zemy:BAACNQAFFH8FAAIaAAUK0BONEwAyAQAaAAUK0BONEwAyAQA1AAQKfygAAxoACgocJbAKAHcDABoACgocJbAKAHcDABcABwrTFy0fAKUBAAAA.Zeneca:BAAANQAECgIIAgABNQAFFAQICgADAHQNAA==.Zergzug:BAAANQAECgEIAQAAAA==.',
Zo='Zodstrike:BAABNQAECn8pAAMLAAcKmAjkUABUAQALAAcKmAjkUABUAQAfAAcK4QMVLgC3AAAAAA==.Zooboo:BAABNQAECn8bAAIjAAkKJRZABgDcAQAjAAkKJRZABgDcAQAAAA==.',
Zu='Zugzuggler:BAABNQAECn8rAAITAAoKnRt9JABYAgATAAoKnRt9JABYAgAAAA==.',
Zy='Zyrick:BAAANQABCggICwAAAA==.',
['Ät']='Ätticus:BAAANQAECgEIAQABNQAECgQIDQAEAAAAAA==.',
['Öv']='Överpöwered:BAAANQAECgQIDQAAAA==.',
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
