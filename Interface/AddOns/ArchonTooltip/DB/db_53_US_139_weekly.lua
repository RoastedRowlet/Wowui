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

local lookup = {'Paladin-Retribution','Priest-Holy','Unknown-Unknown','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','Rogue-Subtlety','Paladin-Holy','Druid-Balance','Druid-Guardian','Warlock-Affliction','Paladin-Protection','Warrior-Arms','Priest-Shadow','Priest-Discipline','Hunter-Marksmanship','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Vengeance','Warrior-Protection','Monk-Windwalker','Shaman-Enhancement','Warrior-Fury','Druid-Restoration','Shaman-Elemental',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Absolutepast:BAAANQABCgQIBAAAAA==.',
Ac='Acanaline:BAAANQADCgYIBgAAAA==.Achannara:BAABNQAECn8hAAIBAAgKrgSV9QAsAQABAAgKrgSV9QAsAQAAAA==.',
Ae='Aeoliana:BAABNQAECn8cAAICAAgKjBTQWgANAgACAAgKjBTQWgANAgAAAA==.',
Aj='Ajier:BAACNQAFFH8KAAICAAUK2g4LEgB5AQACAAUK2g4LEgB5AQA1AAQKfyYAAgIACQrqF6lWABsCAAIACQrqF6lWABsCAAAA.',
Al='Allcapwne:BAAANQADCggIIAAAAA==.Alucart:BAAANQAECgUIDQAAAA==.',
An='Angela:BAABNQAECn8mAAICAAgKvB3YNwCGAgACAAgKvB3YNwCGAgAAAA==.Animalchin:BAAANQABCgEIAQABNQAECggIEgADAAAAAA==.Annadanna:BAAANQAECgUICwAAAA==.Annalunà:BAAANQAECgMIBQAAAA==.Anowars:BAAANQAECgQIBAAAAA==.Antithicus:BAAANQADCgYIBgAAAA==.',
Ap='Apeople:BAABNQAECn8sAAIEAAkKHB1SFQDOAgAEAAkKHB1SFQDOAgAAAA==.Apocalýpsè:BAAANQAECgUIDgAAAA==.Applebottum:BAAANQAECgUIDQAAAA==.Applebottumj:BAAANQADCgIIAgAAAA==.Appärition:BAABNQAECn8jAAMFAAgKZxwlEgDjAQAGAAgKQRrNTwBiAgAFAAYK/hclEgDjAQAAAA==.',
Ar='Arondael:BAABNQAECn8ZAAIEAAcKxQ1TRgCnAQAEAAcKxQ1TRgCnAQAAAA==.',
As='Ashelaandrii:BAACNQAFFH8FAAIHAAIKpiDzGwCyAAAHAAIKpiDzGwCyAAA1AAQKfyMAAgcACQo2I1AQAEADAAcACQo2I1AQAEADAAAA.Astroglyde:BAAANQADCgcIDQAAAA==.Astryd:BAAANQAECgcIEwABNQAECgcIHQAIADsGAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAABNQAECn8kAAIJAAcKugrx+QCVAQAJAAcKugrx+QCVAQAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùvina:BAAANQADCgIJAgAAAA==.',
Ba='Badru:BAAANQAECgIIAwAAAA==.Bagmaster:BAABNQAECn8qAAICAAkKkyK8BgCOAwACAAkKkyK8BgCOAwAAAA==.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAABNQAECn8fAAIHAAgKjBo2OwBwAgAHAAgKjBo2OwBwAgAAAA==.Barthallomew:BAAANQAECgEIAQABNQAECgQICgADAAAAAA==.Bayonetta:BAABNQAECn8ZAAIKAAgK2xYCVwBrAgAKAAgK2xYCVwBrAgAAAA==.',
Be='Bellann:BAAANQAECgIIAwAAAA==.',
Bi='Birghid:BAAANQABCgIIAgAAAA==.Birgite:BAAANQAECgUIDAAAAA==.',
Bl='Blackdracula:BAAANQAECgMIAwAAAA==.Blasphemar:BAAANQADCggICAAAAA==.Blazefury:BAAANQAECgMIAwAAAA==.Blazeknight:BAABNQAECn8kAAILAAgKTBlQLQA1AgALAAgKTBlQLQA1AgAAAA==.Blazemaker:BAABNQAECn8eAAIMAAgKyhVVCgAhAgAMAAgKyhVVCgAhAgAAAA==.Blazemaster:BAAANQAECgUIBQAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.Bloodsylf:BAAANQADCgcIBwABNQAECgQICgADAAAAAA==.',
Bo='Bonecrushers:BAAANQAECgYIEAAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAAANQAECgcIEgAAAA==.Books:BAAANQAECggIEgABNQAECgcIEgADAAAAAA==.',
Br='Brainbread:BAAANQAECgQIDAABNQAECgkJMgAGAKoWAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQAECgUICgAAAA==.Broadside:BAAANQAECgcICQABNQAECgkJLAAGAPMgAA==.Brokil:BAAANQAECgEIAQAAAA==.Brolymorph:BAACNQAFFH8HAAIJAAMKlxGkNADtAAAJAAMKlxGkNADtAAA1AAQKfyMAAgkACQoPHJFlALMCAAkACQoPHJFlALMCAAAA.Brossiere:BAAANQADCgQIBAAAAA==.Broverheal:BAAANQAECgMIBwAAAA==.Bru:BAABNQAECn8cAAICAAkKCBAVXQAGAgACAAkKCBAVXQAGAgAAAA==.',
Bt='Bt:BAAANQADCgYIBgAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAABNQAECn8gAAMNAAgKDhy1LgBzAgANAAgKDhy1LgBzAgAOAAIKSRXFigCAAAAAAA==.Burninglight:BAAANQADCgYIEQAAAA==.Burningtree:BAAANQAECgUICgAAAA==.Buthunter:BAAANQAECgUICQAAAA==.',
['Bâ']='Bâhtilâ:BAAANQAECgYIAQAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECgkJUwAPACEjAA==.',
Ca='Camamoonmana:BAAANQAECggIEAAAAA==.Caplevi:BAABNQAECn8cAAMQAAkKlhyoFABAAgAQAAYKISCoFABAAgAEAAMK3Bf+cADkAAAAAA==.Carrìon:BAAANQADCgEIAQAAAA==.Caskket:BAAANQAECgUICQAAAA==.Catdog:BAAANQADCgYIBgAAAA==.Catechism:BAAANQAECgUIDQAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAABNQAECn8sAAILAAkKzyCGEAAZAwALAAkKzyCGEAAZAwAAAA==.',
Ch='Chaningtotèm:BAAANQADCgUICgAAAA==.Charan:BAAANQADCgYICgAAAA==.Chickennuggi:BAAANQADCgQIBwABNQAFFAQICgANALMjAA==.Chiphoof:BAAANQAECgUIDQAAAA==.Chopndot:BAAANQAECgUIDAAAAA==.',
Cl='Clarabuns:BAABNQAECn8WAAMRAAkKmRpNQgBZAgARAAgKphlNQgBZAgABAAIKaRAIaAFxAAAAAA==.Clawdragoon:BAEBNQAECn8pAAMSAAkKJRsUJQCmAgASAAkKJRsUJQCmAgATAAcK1ghAMwACAQAAAA==.',
Co='Corine:BAAANQADCgEIAQAAAA==.Corndogmatt:BAAANQADCgUICAAAAA==.',
Cr='Creatlach:BAACNQAFFH8UAAIHAAYKghVfBwDeAQAHAAYKghVfBwDeAQA1AAQKfy8AAgcACQo9IwQNAFcDAAcACQo9IwQNAFcDAAAA.Creeptoken:BAAANQADCgQIBQAAAA==.Crystallight:BAAANQAECgYIDgAAAA==.',
Cy='Cyraxx:BAAANQADCgYICgAAAA==.Cytherea:BAAANQAECggIEQAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgcIGQAEAAcTAA==.Dalinek:BAABNQAECn8ZAAIEAAkKlBgqFwC+AgAEAAkKlBgqFwC+AgAAAA==.Damah:BAAANQADCggIHQABNQADCggIHQADAAAAAA==.Dandelo:BAAANQADCgYICwAAAA==.Danicarkel:BAABNQAECn8yAAQUAAkKLRwiAgAOAwAUAAkKLRwiAgAOAwAFAAQKwQpLMgD7AAAGAAIKpwvBKQFiAAAAAA==.Darkdlord:BAAANQAECgYIEQABNQAECggIGwAVAMMNAA==.',
Dd='Ddpaladini:BAABNQAECn8bAAMVAAgKww34NgAtAQABAAcK+A6UzAB8AQAVAAgKfQf4NgAtAQAAAA==.',
De='Deathtracker:BAABNQAECn8cAAIKAAcK1AtbowC7AQAKAAcK1AtbowC7AQAAAA==.Deathtrops:BAAANQAECgIIAgABNQAFFAcIGwAGAEwgAA==.Demindan:BAAANQABCgYICQAAAA==.Demise:BAACNQAFFH8VAAMJAAcKdBFaEQDnAQAJAAYKoRJaEQDnAQAMAAEKwAyUDQBVAAA1AAQKfzYAAwkACQoNIb06ABEDAAkACQoNIb06ABEDAAwAAQr3G3g7AE8AAAAA.Demontickler:BAAANQADCggIDQABNQAECgYJEAADAAAAAA==.',
Di='Dianabol:BAABNQAECn8WAAIWAAkKnRnIRQC1AgAWAAkKnRnIRQC1AgAAAA==.Diego:BAAANQADCgYIDAABNQADCggIEAADAAAAAA==.Dirkuatah:BAAANQAECgMIAgAAAA==.Dista:BAABNQAECn8oAAIGAAkKSBc7PACbAgAGAAkKSBc7PACbAgAAAA==.Divinebovine:BAAANQAECgEIAQAAAA==.Divinedragon:BAABNQAECn8hAAMXAAgK1xn/LgCoAQAXAAYKjBj/LgCoAQAYAAMKZhn2EwDnAAAAAA==.',
Do='Doboy:BAAANQAECgEIAQAAAA==.Dotsncandies:BAAANQAECgIIAgAAAA==.Doublevegan:BAAANQADCgMJAwAAAA==.',
Dr='Drakin:BAAANQAECgcIEAAAAA==.Drawbridge:BAAANQADCgQIBwAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAABNQAECn8rAAIHAAkKIhSRTgAnAgAHAAkKIhSRTgAnAgAAAA==.Drinkoolaide:BAAANQAECgIIAgABNQAECgkJKwAHACIUAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQADCgYIBgAAAA==.Dunamis:BAABNQAECn8fAAIJAAgKWR62VwDQAgAJAAgKWR62VwDQAgAAAA==.Dungodon:BAAANQADCggIDgAAAA==.Durrt:BAAANQAECgQICwAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAACNQAFFH8NAAMZAAUKJRM/DgBUAQAZAAUKoRA/DgBUAQAKAAIKvhuoJwCWAAA1AAQKfy0AAwoACQorJv0QAF0DAAoACQorJv0QAF0DABkACQpuH38RANkCAAAA.',
El='Eldrene:BAABNQAECn8hAAIJAAgK1xpIawCnAgAJAAgK1xpIawCnAgAAAA==.Elizalde:BAAANQAECgYICgAAAA==.Ellexi:BAAANQAECgQIBgAAAA==.Elyseia:BAABNQAECn8gAAIKAAgKIRAbeQAZAgAKAAgKIRAbeQAZAgAAAA==.',
En='Enpower:BAAANQADCgYICwABNQAECgkJKwAaAEIbAA==.',
Es='Escata:BAAANQADCggIEAAAAA==.Esdailongwe:BAAANQADCgMIBAAAAA==.Españamor:BAEBNQAECn8cAAMbAAkKYA5sLwDCAQAbAAkKSQ1sLwDCAQAcAAcKugmZGAAkAQAAAA==.',
Eu='Eunite:BAABNQAECn9TAAINAAkKKh1GKACWAgANAAkKKh1GKACWAgAAAA==.',
Fa='Falkorne:BAAANQAECgMIBAABNQAECgkJIgAaAIMZAA==.Farael:BAAANQADCgYIBgAAAA==.Fashah:BAAANQAECgIIAgAAAA==.Fatalmann:BAAANQAECgIIAgAAAA==.',
Fe='Felmoo:BAAANQAECgUIBQAAAA==.Felorc:BAABNQAECn8YAAMdAAcKUASALADOAAAdAAcKUASALADOAAAWAAIKKALASAE6AAABNQAECgcIHQAIADsGAA==.',
Fi='Fintan:BAAANQADCggICAABNQAFFAYIFAAHAIIVAA==.',
Fo='Forsakenemp:BAAANQADCggIDQABNQAECggIGwAVAMMNAA==.',
Fr='Frassk:BAABNQAECn8hAAMGAAgKpQ6nkwCwAQAGAAcKGw6nkwCwAQAFAAEKWBHKcQA8AAAAAA==.Frigid:BAAANQADCgcIBwAAAA==.Froggystyle:BAAANQAECgcIDwAAAA==.Frozenheart:BAABNQAECn8dAAMIAAcKOwazdgAZAQAIAAcKOwazdgAZAQAOAAIK9gH3rgAtAAAAAA==.Fruk:BAAANQADCgUIBQAAAA==.Frösting:BAAANQADCgYIBgABNQAECgUIDwADAAAAAA==.',
Ft='Ftx:BAABNQAECn8iAAIWAAgKRyAaSQCrAgAWAAgKRyAaSQCrAgAAAA==.',
Fu='Fundidos:BAAANQADCggIEAAAAA==.',
Ga='Garbarn:BAAANQADCgcIDQAAAA==.',
Ge='Gelystine:BAAANQADCgIIAgAAAA==.Geminichi:BAABNQAECn8rAAMaAAkKQhtiDQCqAgAaAAkKQhtiDQCqAgAeAAEKhRBmaAA3AAAAAA==.',
Gh='Ghauri:BAAANQADCgYJBgAAAA==.Ghorza:BAAANQADCgYIBwAAAA==.',
Gi='Gia:BAABNQAECn8iAAIaAAcK9R0CEgBZAgAaAAcK9R0CEgBZAgAAAA==.Gigasauce:BAAANQAECgEIAQAAAA==.Giraffage:BAAANQAECgYIEwABNQADCggICAADAAAAAA==.',
Go='Golgroth:BAAANQADCgQJBAAAAA==.Gorearrow:BAABNQAECn8pAAIKAAkKCR1ZMgDTAgAKAAkKCR1ZMgDTAgAAAA==.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Groggyfroggy:BAAANQADCgMJAwAAAA==.Grralt:BAAANQAECgIIAgABNQADCggIHQADAAAAAA==.Grís:BAABNQAECn8nAAMWAAkKZhZQZwBWAgAWAAkKsxVQZwBWAgAdAAMKCA0+MwCXAAAAAA==.',
Gu='Gunafistya:BAAANQAECgMIAwAAAA==.',
Ha='Harrier:BAAANQADCgYICgABNQAECgUIDQADAAAAAA==.Hazed:BAAANQAECgcIDAAAAA==.Hazzaa:BAAANQAECgUICQAAAA==.',
He='Herioffy:BAAANQADCgEIAQAAAA==.Hexxan:BAAANQADCgYIBgAAAA==.',
Hi='Hiawatha:BAAANQADCgQIBAAAAA==.Hiver:BAAANQAECgEIAQAAAA==.',
Ho='Holier:BAABNQAECn8tAAIBAAkK3g0KmQDsAQABAAkK3g0KmQDsAQAAAA==.Holybishh:BAAANQAECgUIBQAAAA==.Holyregerts:BAABNQAECn8YAAMXAAkK5A3XIwAPAgAXAAkK5A3XIwAPAgACAAcKFRUZcADJAQAAAA==.Honk:BAAANQAECgcIDwAAAA==.Hoochurcooch:BAAANQAECgQIBAAAAA==.Hopperstotem:BAAANQAECgMIAwABNQAECgkJLAAGAPMgAA==.',
Hu='Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQAECgIIAgAAAA==.',
Il='Illumi:BAAANQABCgYIBgAAAA==.',
Im='Imbatmann:BAAANQADCgEIAQAAAA==.',
In='Indrà:BAAANQADCgQIBQAAAA==.Infamus:BAAANQAECgIIBQAAAA==.Invysion:BAACNQAFFH8KAAIYAAUKEAKRAQApAQAYAAUKEAKRAQApAQA1AAQKfy0AAhgACQr5EVUGACcCABgACQr5EVUGACcCAAAA.',
Is='Islander:BAAANQAECgQIBwAAAA==.',
Ja='Jackychang:BAAANQAECgcIEAAAAA==.Jaidess:BAAANQADCggIDgAAAA==.Jakeypoo:BAAANQAECgQICAAAAA==.',
Je='Jellybea:BAABNQAECn8fAAMCAAkK0hrEKgC7AgACAAkK0hrEKgC7AgAXAAIKAAAxaQBZAAAAAA==.',
Ju='Jukoti:BAAANQABCgIIBAAAAA==.Junglebrew:BAAANQADCggJDgAAAA==.Junglepino:BAAANQADCgYIBgAAAA==.Jurisdiction:BAAANQAECgUIDQAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAABNQAECn8qAAIeAAkKdRydDwDoAgAeAAkKdRydDwDoAgAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kanalz:BAAANQAECgUIBQAAAA==.Kappowee:BAAANQADCgEIAQAAAA==.Kasey:BAAANQAECgUIEwAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keho:BAAANQAECgUIDQAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAACNQAFFH8JAAILAAQKoQ9JDwAMAQALAAQKoQ9JDwAMAQA1AAQKfzAAAxsACQoMH2wYAJYCABsACQrDHGwYAJYCAAsACQq6G1whAIwCAAE1AAMKCAgIAAMAAAAA.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kickdrop:BAAANQADCgQIBAAAAA==.Kilgreed:BAAANQADCgYIDgAAAA==.Killaban:BAAANQAECgcIBwAAAA==.Killbydeath:BAAANQAECgYIDQAAAA==.Kimberlyhárt:BAAANQAECgYJEAAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYJEAADAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAABNQAECn9LAAIGAAkKixubKADfAgAGAAkKixubKADfAgAAAA==.',
Ko='Kohman:BAABNQAECn8yAAMGAAkKqhY6MADEAgAGAAkKqhY6MADEAgAFAAMKMg39UQCIAAAAAA==.Komatose:BAAANQADCgYIBgAAAA==.Kong:BAAANQADCgIIAwAAAA==.',
Kr='Krftpnk:BAACNQAFFH8fAAILAAcKHCFpAQC1AgALAAcKHCFpAQC1AgA1AAQKfzIAAgsACQrhJhsCANYDAAsACQrhJhsCANYDAAAA.Kricket:BAAANQAECgEIAQAAAA==.Kronas:BAAANQAECgYICwAAAA==.Kronosity:BAABNQAECn8gAAIVAAgKox+GCgDxAgAVAAgKox+GCgDxAgABNQAECgkJMwAIADAjAA==.Kronotality:BAABNQAECn8zAAIIAAkKMCOyBQCXAwAIAAkKMCOyBQCXAwAAAA==.Kronotekken:BAAANQAECgEIAQABNQAECgkJMwAIADAjAA==.Kronotide:BAAANQADCgQIBAABNQAECgkJMwAIADAjAA==.',
Ku='Kungfukittn:BAABNQAECn8dAAIeAAcKIxYZKwC/AQAeAAcKIxYZKwC/AQAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQAECgQIBgAAAA==.Kyojuro:BAAANQABCgYIBgAAAA==.',
Kz='Kzorx:BAAANQADCgYICwAAAA==.',
La='Laimaster:BAAANQADCgcIJAAAAA==.Lakiri:BAABNQAECn8kAAIfAAcK/hSWFwDqAQAfAAcK/hSWFwDqAQAAAA==.Landaeda:BAAANQADCgcIBwAAAA==.Lascivia:BAABNQAECn8iAAMdAAkKdSBABgACAwAdAAkKdSBABgACAwAgAAQKABjIGAASAQAAAA==.Latrice:BAAANQAECgcIBwABNQAFFAYIEQAMALwhAA==.Laylahh:BAAANQADCgQIBAAAAA==.',
Le='Leademon:BAAANQAECgYIDgAAAA==.Leadmln:BAAANQAECgMIAwABNQAECgYIDgADAAAAAA==.Lebwonsamdi:BAAANQAECgEIAQABNQAECgkJJwAWAGYWAA==.',
Li='Lighterfluîd:BAAANQABCgIIAgABNQAECgkJKgAaABAgAA==.Ligmadk:BAAANQADCgUIBQABNQAFFAMIBgALAIMIAA==.Lilbeebs:BAAANQAECgIIAgAAAA==.Lilflea:BAAANQAECggIEgAAAA==.Lillidari:BAAANQAECgcICQABNQAECgkJJgAIACwkAA==.Lilzuki:BAAANQAECgIIAgAAAA==.Lilïth:BAABNQAECn8mAAIIAAkKLCT7CgBbAwAIAAkKLCT7CgBbAwAAAA==.Linguine:BAAANQADCggICAABNQAFFAMIBgAXAEgaAA==.Lisalisa:BAABNQAECn8XAAIHAAcKORQ6cAC3AQAHAAcKORQ6cAC3AQAAAA==.Littlej:BAAANQAECgQJBAAAAA==.Littlejohn:BAABNQAECn8iAAIaAAkKgxmyEABwAgAaAAkKgxmyEABwAgAAAA==.',
Lo='Logaothe:BAAANQAECgUIEAAAAA==.',
Lu='Lucky:BAAANQAECgYICgAAAA==.Lukethywalkr:BAAANQADCgQIBAAAAA==.Lularia:BAAANQADCgUICAAAAA==.Lunaa:BAAANQAECgQJBAAAAA==.Lusid:BAAANQABCgcICAAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Maliciousrot:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQIBQAAAA==.',
Me='Medikus:BAABNQAECn8eAAIHAAcKBBrlVAAQAgAHAAcKBBrlVAAQAgAAAA==.Megajoo:BAAANQAECgEIAQAAAA==.Melkinov:BAAANQABCgYIBgAAAA==.Merryl:BAAANQAECgUIBwAAAA==.',
Mf='Mfive:BAAANQAECgQIBAAAAA==.',
Mi='Mike:BAEBNQAECn8cAAIJAAkK4iHJTwDhAgAJAAkK4iHJTwDhAgAAAA==.Milkjugs:BAAANQAECgIIAgABNQAECggIEgADAAAAAA==.Minijeangen:BAAANQAECgMJAwAAAA==.Missluana:BAAANQABCgEIAQAAAA==.',
Mo='Mockra:BAABNQAECn9AAAIJAAgKGhYKqwArAgAJAAgKGhYKqwArAgAAAA==.Moistmunnky:BAAANQAECgQIBgAAAA==.Montera:BAEANQAECggICwABNQAECgkJHAAbAGAOAA==.Moohammered:BAAANQAECgcIEgAAAA==.Moolou:BAABNQAECn8gAAIVAAkKIxq4EACRAgAVAAkKIxq4EACRAgAAAA==.Mootarded:BAAANQAECgYIDgABNQAECgcIHQAIADsGAA==.Mordiggian:BAABNQAECn8vAAMIAAkKoiOcDwAvAwAIAAgKAiOcDwAvAwANAAkKZiPNGAD3AgAAAA==.Morechie:BAABNQAECn8hAAIUAAgKxRCECQDnAQAUAAgKxRCECQDnAQAAAA==.Morgatho:BAAANQABCgcICQAAAA==.Morsz:BAAANQAECgUICAAAAA==.Mortiferon:BAABNQAECn8gAAINAAgKxx1ROwAyAgANAAgKxx1ROwAyAgAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQAECgQIBgADAAAAAA==.Munnkypox:BAAANQAECgIIBAABNQAECgQIBgADAAAAAA==.Murderella:BAAANQADCgYIBgAAAA==.Murkhoof:BAAANQADCgYIBgABNQAECgUIDQADAAAAAA==.',
['Mö']='Mörgänä:BAAANQADCgcICAAAAA==.',
Na='Nakovii:BAAANQAECgUIBQAAAA==.Nascerathel:BAAANQAECgQIBAAAAA==.',
Ne='Nealite:BAAANQADCgYIBgAAAA==.Neerem:BAAANQABCggICAAAAA==.Neferata:BAABNQAECn8rAAMGAAkKSxssNgCvAgAGAAkKSxssNgCvAgAFAAYKbgugJwA6AQAAAA==.Nerrisa:BAAANQADCggIDwAAAA==.Nertmage:BAABNQAECn9TAAMPAAkKISNPAACgAwAPAAkKISNPAACgAwAJAAEKsxBWuAFFAAAAAA==.Neublood:BAAANQAECgQIBwAAAA==.',
Ni='Nicodemus:BAAANQAECgQIBAAAAA==.Nineiota:BAABNQAECn8eAAIhAAcK1B0MGQBwAgAhAAcK1B0MGQBwAgAAAA==.',
No='Noblewarrior:BAACNQAFFH8eAAIWAAUK2xx2EACuAQAWAAUK2xx2EACuAQA1AAQKfzIAAhYACQpGIqoZAFADABYACQpGIqoZAFADAAAA.Nobukawaii:BAAANQAECgMIAwAAAA==.Noctilus:BAAANQADCgcIDwAAAA==.Noke:BAAANQAECgIJAgAAAA==.Notakoala:BAACNQAFFH8OAAISAAQKVxw+EABhAQASAAQKVxw+EABhAQA1AAQKfy0AAhIACQqEIVcOAFUDABIACQqEIVcOAFUDAAAA.Nothnx:BAACNQAFFH8HAAIKAAMK9glOGgDjAAAKAAMK9glOGgDjAAA1AAQKfx8AAgoACQrvFzY1AMkCAAoACQrvFzY1AMkCAAAA.Notoriouspat:BAAANQAECgYICgAAAA==.Novia:BAAANQAECgUICgABNQAECgkJJwAWAGYWAA==.Noxeternis:BAABNQAECn8kAAQXAAkKsRncIAAuAgAXAAgKwxncIAAuAgACAAMKSBf9tgDtAAAYAAIKMga0IwBKAAAAAA==.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
Ny='Nyxandra:BAAANQADCgYIBgAAAA==.',
['Ní']='Níghtfall:BAAANQADCgUICwAAAA==.Nínebreaker:BAAANQAECgEIAQAAAA==.',
Ob='Obern:BAAANQAECggIDgAAAA==.Obeysnapback:BAAANQADCgMIBAAAAA==.Oblïna:BAAANQAECgQICAAAAA==.',
Od='Oddishh:BAAANQAECgYIDwAAAA==.',
Ol='Olleg:BAAANQADCgYICQAAAA==.',
Om='Omnicarkel:BAAANQADCgcIDAAAAA==.',
On='Onsen:BAABNQAECn8bAAIBAAkKwxZPWQCIAgABAAkKwxZPWQCIAgABNQAECgkJMgAGAKoWAA==.',
Or='Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQJBAAAAA==.',
Pa='Pajl:BAABNQAECn8iAAIBAAkKkSNKDQCYAwABAAkKkSNKDQCYAwABNQAFFAcIDwAOAKMeAA==.Pandablaze:BAAANQADCggIKgAAAA==.Pandajoy:BAAANQADCgEIAQAAAA==.Panterarey:BAAANQAECgIIAgAAAA==.Papanurrgle:BAAANQAECgUICQAAAA==.Papazilla:BAAANQAECgMJAwAAAA==.Parakka:BAAANQAECgIIAgAAAA==.Patak:BAAANQADCgQIBAAAAA==.Pawp:BAAANQAECgQICwABNQAECgkJKQACANQWAA==.Paxiel:BAAANQAECgQICAAAAA==.',
Pe='Pearagon:BAAANQADCgQIBAABNQAFFAYIEwAHAPoZAA==.Pepsidew:BAAANQAECgcICgAAAA==.Pepsisprite:BAAANQAECgcIEgAAAA==.',
Ph='Phdbeef:BAAANQAECgEIAQABNQAECgkJJgAIACwkAA==.Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQAECgIIAgAAAA==.',
Pi='Picklez:BAAANQAECgUIEQAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.Portwings:BAAANQADCggIDQAAAA==.',
Ps='Psyop:BAAANQADCggIEAABNQAECgkJOQACAJ8iAA==.Psyrax:BAAANQAECgMIAwAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Rashun:BAAANQADCgEIAQAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDgAAAA==.Redkoala:BAAANQAECgYIDQABNQAFFAQIDgASAFccAA==.Repete:BAAANQAECgIIAwAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECn9TAAIMAAkK6iAEAgBbAwAMAAkK6iAEAgBbAwAAAA==.Reven:BAAANQAECgYICAAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ri='Riivan:BAAANQAECgEIAQAAAA==.Rirugiliyang:BAAANQAECgEIAQAAAA==.',
Ro='Roardon:BAAANQADCgcIDQAAAA==.Roflmfao:BAAANQADCggICAAAAA==.Roguè:BAAANQAECgQICgAAAA==.Rollinburn:BAAANQADCgUJBQAAAA==.Romanoff:BAABNQAECn8ZAAIEAAcKBxOEPADZAQAEAAcKBxOEPADZAQAAAA==.Rosearcana:BAAANQAECgEIAQAAAA==.',
['Rô']='Rôx:BAAANQADCgcIBwABNQAECgkJUgARAI0ZAA==.',
['Rõ']='Rõx:BAABNQAECn9SAAMRAAkKjRmRLgCqAgARAAkKjRmRLgCqAgABAAEKAACoqwEvAAAAAA==.',
Sa='Sackoss:BAABNQAECn8YAAIRAAcKhheqXgD6AQARAAcKhheqXgD6AQAAAA==.Saffronspark:BAAANQAECgQICAABNQAECggIJQAeAFgcAA==.Sainsei:BAAANQAECgUIEAABNQAECgkJJwAWAGYWAA==.Sakata:BAAANQADCgIIAgABNQAECgUIDQADAAAAAA==.Sandwitch:BAABNQAECn9TAAMFAAkKPxJbDwAGAgAGAAkKNxCpXgA4AgAFAAgKTxBbDwAGAgAAAA==.Sargatanas:BAABNQAECn8gAAIIAAgKVw6LUQCsAQAIAAgKVw6LUQCsAQAAAA==.Sars:BAAANQADCgUIBQABNQAECgUIBgADAAAAAA==.',
Sc='Scarcroww:BAAANQADCgMIAwABNQAECgkJIAAJABQfAA==.Schrodinger:BAAANQAECgIIBAAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAABNQAECn8gAAIdAAgKlxGoFgC8AQAdAAgKlxGoFgC8AQAAAA==.',
Sh='Shadrad:BAABNQAECn8XAAMBAAkKex/DJgAoAwABAAkKex/DJgAoAwARAAYKeQPfxADtAAAAAA==.Shallot:BAABNQAECn8oAAIJAAkKTx8lNwAaAwAJAAkKTx8lNwAaAwAAAA==.Shammoo:BAAANQAECggICgABNQAECgkJLAABANgkAA==.Shammyd:BAAANQAECgUIDAAAAA==.Shantz:BAAANQAECgUIDwAAAA==.Shiftface:BAAANQADCgMIAwAAAA==.Shiftmypants:BAAANQAECgcICwAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Si='Sinterdeath:BAAANQAECgUIDAAAAA==.',
Sk='Skatervan:BAAANQADCggIEwABNQAECgkJMQAXAAEbAA==.Skylie:BAAANQADCgYIDwAAAA==.',
Sl='Slushpuppy:BAAANQAECgIIAgAAAA==.',
Sm='Smorthian:BAAANQAECgQICwAAAA==.',
Sn='Sniffinsteak:BAAANQAECgYJEAAAAA==.Snoosnooftww:BAAANQADCgcICgAAAA==.',
So='Solas:BAAANQAFFAEIAQAAAA==.Sondeltis:BAAANQAECgQIBAAAAA==.Soryan:BAAANQAECgUIBQAAAA==.',
Sp='Spankenstine:BAABNQAECn8dAAIBAAgKlhqKawBXAgABAAgKlhqKawBXAgAAAA==.Sparkyy:BAAANQAECgIIAwAAAA==.Sphaeram:BAAANQAECgcICAAAAA==.Spicypepsi:BAAANQADCgEIAQAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAABNQAECn8ZAAIBAAcKKyHjawBWAgABAAcKKyHjawBWAgAAAA==.Stinkydeathy:BAAANQADCgYJBgABNQAECgIIAgADAAAAAA==.Stinkydragon:BAAANQAECgIIAgAAAA==.Stormknight:BAAANQAECgQIBAAAAA==.Stormpoo:BAAANQAECgEIAQAAAA==.',
Su='Suneater:BAAANQAECgcIEQAAAA==.Superpi:BAAANQADCgYIBgABNQAECgUICAADAAAAAA==.Superret:BAAANQAECgUICAAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAAANQAECgcICQAAAA==.',
Sw='Swíper:BAACNQAFFH8FAAIEAAIKLA+NFgCUAAAEAAIKLA+NFgCUAAA1AAQKfykAAwQACQpbIFUIAE8DAAQACQpbIFUIAE8DABAABQq1CX43APcAAAAA.',
Sy='Sylphièl:BAACNQAFFH8KAAMQAAQKawkVDADuAAAQAAMKFAwVDADuAAAEAAEKGwQGIgBAAAA1AAQKfyIAAxAACQqfEVgfANIBABAABwpPE1gfANIBAAQACQoxCdVAAMMBAAAA.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgcIDQAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECn8nAAIBAAkKmiJoKwAXAwABAAkKmiJoKwAXAwAAAA==.Tankenstine:BAABNQAECn8cAAIWAAgKdxLGmQDXAQAWAAgKdxLGmQDXAQABNQAECggIHQABAJYaAA==.Tawnii:BAAANQAECgMIBAAAAA==.Taírn:BAAANQAECgQIBAAAAA==.',
Te='Tenderloin:BAAANQAECgUIDQAAAA==.',
Th='Thanitose:BAAANQAECgUIDQAAAA==.Thevelo:BAAANQAECgIIAgABNQAECgQICgADAAAAAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thornwyn:BAAANQAECgYIBwAAAA==.Thors:BAAANQADCgQIBAAAAA==.Thorul:BAAANQADCgEIAQAAAA==.Thundurus:BAABNQAECn8yAAIiAAkKZxdERQBeAgAiAAkKZxdERQBeAgAAAA==.',
Ti='Timmayy:BAAANQAECgIIAwABNQAECgkJIgAaAIMZAA==.Tindrill:BAAANQADCgMIAwABNQAECggIJgAhABclAA==.Tinggoskrrah:BAAANQADCggIEgAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAABNQAECn8gAAIWAAcKrxBhsQCcAQAWAAcKrxBhsQCcAQAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAcIHwALABwhAA==.Totemagoat:BAACNQAFFH8JAAMHAAUK1BGYDQBuAQAHAAUK1BGYDQBuAQAiAAEKsQUEMgBEAAA1AAQKfy4AAwcACQrkHiwWAB0DAAcACQrkHiwWAB0DACIACApvFllfAAACAAAA.',
Tr='Tracula:BAAANQADCgEIAQAAAA==.Treefist:BAAANQADCggIFQAAAA==.Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAACNQAFFH8HAAIhAAMKmQbRDQDHAAAhAAMKmQbRDQDHAAA1AAQKfygAAiEACQp0FLYcAEoCACEACQp0FLYcAEoCAAAA.',
Un='Undeadkiels:BAAANQADCggICAABNQAECggIGwAVAMMNAA==.Undeadmonks:BAAANQADCgYIBgAAAA==.',
Ur='Uraharakun:BAAANQAECgQIBwABNQAECgkJKwABAMMOAA==.',
Va='Vagalion:BAAANQAECgUICAAAAA==.Valdanyr:BAAANQADCgMIAwAAAA==.Vale:BAAANQADCgYICgAAAA==.Valeshot:BAABNQAECn8gAAIKAAkKjA3CdQAhAgAKAAkKjA3CdQAhAgAAAA==.Valimyr:BAAANQABCgMIBAAAAA==.Valkillrie:BAAANQAFFAEIAgAAAA==.Valohir:BAAANQAECgIIAgAAAA==.Vanhellsin:BAAANQAECgYIEgAAAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECgkJFgABAAcjAA==.Vedronas:BAABNQAECn8WAAIBAAkKByMbJQAuAwABAAkKByMbJQAuAwAAAA==.Veos:BAABNQAECn8oAAIMAAkKkxkRBQDJAgAMAAkKkxkRBQDJAgAAAA==.Verdict:BAAANQADCgYIGAAAAA==.Vern:BAABNQAECn8aAAMCAAgKRRPRYgD0AQACAAgKRRPRYgD0AQAYAAEKzQiLKwAsAAAAAA==.Vernah:BAAANQADCgIIAgABNQAECggIGgACAEUTAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Volætile:BAAANQAECgQIBQABNQAECgUIDwADAAAAAA==.Vorn:BAABNQAECn9TAAIIAAkKExryHwCxAgAIAAkKExryHwCxAgAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAABNQAECn8gAAITAAgKDBvwDgBwAgATAAgKDBvwDgBwAgAAAA==.Waamchifu:BAAANQAECgEJAQAAAA==.Waltersight:BAAANQAECgMIBQAAAA==.Warbritt:BAAANQADCgYJBgAAAA==.Waterwalkerr:BAAANQADCgYIBgAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgUIDgAAAA==.Whatthezug:BAAANQABCgIIAgABNQAECgQICAADAAAAAA==.Whoforted:BAABNQAECn8dAAMXAAkKFRfiKQDVAQAXAAcKzhLiKQDVAQACAAUKPA9soAAvAQAAAA==.',
Wi='Wisperia:BAAANQADCgQIBQAAAA==.',
Wo='Wormchild:BAAANQADCgIIAgAAAA==.',
Wu='Wulrat:BAAANQAECgcIDwAAAA==.',
Wy='Wyle:BAAANQAECgQIBwAAAA==.',
Xe='Xelí:BAABNQAECn9RAAIHAAkK3hfUNACKAgAHAAkK3hfUNACKAgAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAAANQAECggIEgABNQAFFAYIFAAHAIIVAA==.',
Xt='Xtremes:BAAANQAECgQIBAABNQAECgkJKwAaAEIbAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.Youvbendoted:BAAANQAECgYICAAAAA==.',
Yu='Yudah:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
Za='Zanghonghua:BAABNQAECn8lAAIeAAgKWBy3GAB9AgAeAAgKWBy3GAB9AgAAAA==.',
Ze='Zemy:BAABNQAECn8gAAMSAAkKgyWHCgB3AwASAAkKgyWHCgB3AwATAAcK0xeMHgClAQAAAA==.Zeneca:BAAANQAECgIIAgABNQAFFAMIBgAXAEgaAA==.',
Zo='Zodstrike:BAABNQAECn8eAAMLAAcKmAjxTwBUAQALAAcKmAjxTwBUAQAbAAEK0QLlcQAnAAAAAA==.Zooboo:BAAANQAECgUIDQAAAA==.',
Zu='Zugzuggler:BAABNQAECn8gAAIWAAgKBxyvZQBbAgAWAAgKBxyvZQBbAgAAAA==.',
Zy='Zyrick:BAAANQABCggICwAAAA==.',
['Ät']='Ätticus:BAAANQADCgQIBAABNQAECgQICgADAAAAAA==.',
['Öv']='Överpöwered:BAAANQAECgQICQABNQAECgQICgADAAAAAA==.',
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
