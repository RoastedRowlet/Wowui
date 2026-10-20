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

local lookup = {'Paladin-Retribution','Priest-Holy','Priest-Shadow','Shaman-Restoration','Rogue-Assassination','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','Mage-Arcane','Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Paladin-Holy','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','Rogue-Subtlety','Druid-Feral','Druid-Balance','Druid-Guardian','Warlock-Affliction','Paladin-Protection','Warrior-Arms','Priest-Discipline','Hunter-Marksmanship','Monk-Mistweaver','DemonHunter-Devourer','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Shaman-Elemental','Hunter-Survival',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Absolutepast:BAAANQAECgEIAQAAAA==.',
Ac='Achannara:BAABNQAECn8lAAIBAAkKSQQg+QAsAQABAAkKSQQg+QAsAQAAAA==.',
Ae='Aeoliana:BAABNQAECn8lAAICAAoKmRMcCwAzAgACAAoKmRMcCwAzAgAAAA==.',
Aj='Ajier:BAACNQAFFH8MAAICAAUK2g6IEgB5AQACAAUK2g6IEgB5AQA1AAQKfzEAAgIACgoAGOsKADYCAAIACgoAGOsKADYCAAAA.',
Al='Alaaris:BAAANQAECgEIAQAAAA==.Allcapwne:BAAANQADCggIIAAAAA==.Alucart:BAABNQAECn8YAAIDAAcKFBDhEwDrAAADAAcKFBDhEwDrAAAAAA==.',
An='Angela:BAABNQAECn8qAAICAAoKoBrCOACFAgACAAoKoBrCOACFAgAAAA==.Animalchin:BAAANQABCgEIAQABNQAECgoKHgAEAFgYAA==.Annadanna:BAAANQAECgUICwAAAA==.Annalunà:BAAANQAECgMIBQAAAA==.Anoheals:BAAANQADCggIAgAAAA==.Anowars:BAAANQAECgUIBwAAAA==.Antithicus:BAAANQADCgYIBgAAAA==.',
Ap='Apeople:BAABNQAECn8wAAIFAAoK4xquFQDOAgAFAAoK4xquFQDOAgAAAA==.Apocalýpsè:BAABNQAECn8UAAIGAAYK+hfiBwA4AQAGAAYK+hfiBwA4AQAAAA==.Applebottum:BAAANQAECgYIDwAAAA==.Applebottumj:BAAANQAECgQIBAAAAA==.Appärition:BAABNQAECn8rAAMHAAkK+BoqDADsAQAHAAkKIBkqDADsAQAIAAYK/hdLEgDiAQAAAA==.',
Ar='Arondael:BAABNQAECn8gAAIFAAkKBw1XDABmAQAFAAkKBw1XDABmAQAAAA==.',
As='Ashelaandrii:BAACNQAFFH8FAAIEAAIKpiCeHACxAAAEAAIKpiCeHACxAAA1AAQKfyMAAgQACQo2I54QAEADAAQACQo2I54QAEADAAAA.Astroglyde:BAAANQAECgMIAwAAAA==.Astryd:BAABNQAECn8ZAAMJAAkKYgUqDgCJAAAJAAgKYgUqDgCJAAAKAAEKAABrXgAAAAABNQAECgkJIQALAIYGAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAABNQAECn8oAAIMAAcKCAxjhAC6AAAMAAcKCAxjhAC6AAAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùvina:BAAANQADCgIJAgAAAA==.',
Ba='Badru:BAAANQAECgMIBAAAAA==.Bagmaster:BAABNQAECn8uAAICAAoK9CHoBgCOAwACAAoK9CHoBgCOAwAAAA==.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAABNQAECn8hAAIEAAoK8Rj1OwBvAgAEAAoK8Rj1OwBvAgAAAA==.Barie:BAAANQAECgIIAgABNQAECgkJIAAKAD4dAA==.Barthallomew:BAAANQAECgIIAgABNQAECgQICgANAAAAAA==.Bayonetta:BAABNQAECn8gAAIOAAoK3xWDMgBZAQAOAAoK3xWDMgBZAQAAAA==.',
Be='Bellann:BAAANQAECgIIBAAAAA==.',
Bi='Birghid:BAAANQABCgIIAgAAAA==.Birgite:BAAANQAECgYIEQAAAA==.',
Bl='Blackdracula:BAAANQAECgQIAwAAAA==.Blasphemar:BAAANQADCggIEAAAAA==.Blazefury:BAAANQAECgQICQAAAA==.Blazeknight:BAABNQAECn8qAAIKAAkKahbzLQA1AgAKAAkKahbzLQA1AgAAAA==.Blazemaker:BAABNQAECn8lAAIPAAkKgxZ/CgAgAgAPAAkKgxZ/CgAgAgAAAA==.Blazemaster:BAAANQAECgYICwAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.Bloodsylf:BAAANQADCgcIBwABNQAECggIDAANAAAAAA==.Blówpop:BAAANQADCgMIAwAAAA==.',
Bo='Bonecrushers:BAABNQAECn8ZAAIOAAYKTQwC0ABhAQAOAAYKTQwC0ABhAQAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAABNQAECn8WAAIQAAkKcBYpUAArAgAQAAkKcBYpUAArAgAAAA==.Books:BAABNQAECn8YAAIRAAoKxRlMEgC9AgARAAoKxRlMEgC9AgABNQAECgkJFgAQAHAWAA==.',
Br='Brainbread:BAAANQAECgQIDgABNQAECgoKOAAHAAgVAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQAECgYICwAAAA==.Broadside:BAAANQAECggIEgAAAA==.Brokil:BAAANQAECgIIAQAAAA==.Brolymorph:BAACNQAFFH8JAAIMAAQKlxHZNQDtAAAMAAQKlxHZNQDtAAA1AAQKfycAAgwACgrRG6xnAK8CAAwACgrRG6xnAK8CAAAA.Brossiere:BAAANQADCgQIBAAAAA==.Broverheal:BAAANQAECgMIBwAAAA==.Bru:BAABNQAECn8gAAICAAoK1Q9IXgAGAgACAAoK1Q9IXgAGAgAAAA==.',
Bt='Bt:BAAANQADCgYIBgAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAABNQAECn8nAAMSAAgKZxyQBQDeAQASAAgKZxyQBQDeAQATAAIKSRXPjQB/AAAAAA==.Burninglight:BAAANQADCgYIEQAAAA==.Burningtree:BAAANQAECgYIDAAAAA==.Buthunter:BAAANQAECgUICQAAAA==.',
['Bâ']='Bâhtilâ:BAAANQAECgYIAQAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECgoKXQAUAFgiAA==.',
Ca='Camamoonmana:BAAANQAECggIEgAAAA==.Caplevi:BAABNQAECn8iAAMVAAoKgRrsFAA/AgAVAAcKvRzsFAA/AgAFAAQK4RR2NAB3AAAAAA==.Carrìon:BAAANQADCgEIAQAAAA==.Caskket:BAAANQAECgYIDwAAAA==.Catdog:BAAANQADCgYIBgAAAA==.Catechism:BAAANQAECgYIDwAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAABNQAECn8vAAIKAAkKqCHtEAAZAwAKAAkKqCHtEAAZAwAAAA==.',
Ch='Chaningtotèm:BAAANQADCgUICgAAAA==.Charan:BAAANQADCgYICgAAAA==.Chickennuggi:BAAANQADCgQIBwABNQAFFAUIDwASAD0jAA==.Chiphoof:BAABNQAECn8UAAIWAAcKQRFKGAB2AQAWAAcKQRFKGAB2AQAAAA==.Chopndot:BAAANQAECgYIEQAAAA==.',
Cl='Clarabuns:BAABNQAECn8WAAMQAAkKmRryQgBZAgAQAAgKphnyQgBZAgABAAIKaRBrbQFxAAAAAA==.Clawdragoon:BAEBNQAECn8tAAMXAAkKJRuTJQCmAgAXAAkKJRuTJQCmAgAYAAcK1ggdNAACAQAAAA==.',
Co='Corine:BAAANQADCgUIBgAAAA==.Corndogmatt:BAAANQADCgUICAAAAA==.',
Cr='Creatlach:BAACNQAFFH8WAAIEAAYK4xmeBwDdAQAEAAYK4xmeBwDdAQA1AAQKfzgAAgQACgpaJDsNAFYDAAQACgpaJDsNAFYDAAAA.Creatlachtwo:BAAANQAECgQIBQABNQAFFAYIFgAEAOMZAA==.Creeptoken:BAAANQADCgQIBQAAAA==.Crucifilth:BAAANQAECgEIAQAAAA==.Crystallight:BAABNQAECn8XAAQUAAcKkwXRAgB2AAAMAAcKuAMoOwEqAQAUAAIKGAbRAgB2AAAPAAMKLwXpFQBWAAAAAA==.',
Cy='Cyraxx:BAAANQAECgEIAQAAAA==.Cytherea:BAAANQAECggIEQAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECggIHQAFAHQSAA==.Dalinek:BAABNQAECn8dAAIFAAoKVReUFwC/AgAFAAoKVReUFwC/AgAAAA==.Damah:BAAANQADCggIHQABNQADCggIHQANAAAAAA==.Dandelo:BAAANQADCgYIEQAAAA==.Danicarkel:BAABNQAECn82AAQZAAoKkBwnAgAOAwAZAAoKkBwnAgAOAwAIAAQKwQpzMgD7AAAHAAIKpwt2LQFiAAAAAA==.Darkdlord:BAABNQAECn8ZAAMLAAkKGAgoNgCfAAATAAUKfgoVZQAOAQALAAgK4QQoNgCfAAABNQAECgkJIgAaAPMNAA==.',
Dd='Ddpaladini:BAABNQAECn8iAAMaAAkK8w2rNwAtAQABAAgKcw+8zwB8AQAaAAkKIAerNwAtAQAAAA==.',
De='Deathtracker:BAABNQAECn8dAAIOAAcK1Au2pQC6AQAOAAcK1Au2pQC6AQAAAA==.Deathtrops:BAAANQAECgIIAgABNQAFFAcIIQAHAFkjAA==.Demindan:BAAANQAECgEIAQAAAA==.Demise:BAACNQAFFH8VAAMMAAcKdBH0EQDoAQAMAAYKoRL0EQDoAQAPAAEKwAzpDQBVAAA1AAQKfzgAAwwACgr6INE7AA8DAAwACgr6INE7AA8DAA8AAQr3G0U8AE4AAAAA.Demontickler:BAAANQADCggIDQABNQAECgYJEAANAAAAAA==.',
Di='Dianabol:BAABNQAECn8dAAIbAAkKpBnERgC1AgAbAAkKpBnERgC1AgABNQAECgoKLQAEAOolAA==.Diego:BAAANQADCgYIDAABNQADCggIEAANAAAAAA==.Dirkuatah:BAAANQAECgQIBAAAAA==.Dista:BAABNQAECn8xAAIHAAoKfBnhBQBXAgAHAAoKfBnhBQBXAgAAAA==.Divinebovine:BAAANQAECgEIAQAAAA==.Divinedragon:BAABNQAECn8oAAMDAAoKmBdOEwDxAAADAAcKyBZOEwDxAAAcAAQKvBo1BQCpAAAAAA==.',
Do='Doboy:BAAANQAECgEIAQAAAA==.Dotsncandies:BAAANQAECgIIAgAAAA==.Doublevegan:BAAANQADCgMJAwAAAA==.',
Dr='Drakin:BAAANQAECgcIEAAAAA==.Drawbridge:BAAANQADCgYIDQAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAACNQAFFH8FAAIEAAIKoQg6EQB8AAAEAAIKoQg6EQB8AAA1AAQKfy8AAgQACgofE45PACcCAAQACgofE45PACcCAAAA.Drinkoolaide:BAAANQAECgIIAgABNQAFFAIIBQAEAKEIAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQADCgYIBgAAAA==.Dunamis:BAABNQAECn8hAAIMAAgKDB/KWQDMAgAMAAgKDB/KWQDMAgAAAA==.Dungodon:BAAANQADCggIDgAAAA==.Durrt:BAAANQAECgYIEAAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAACNQAFFH8PAAMdAAYK4BaRDgBUAQAdAAUKoRCRDgBUAQAOAAMK6B6lEgBsAAA1AAQKfzIAAw4ACgpBJV8RAFwDAA4ACQorJl8RAFwDAB0ACgpcH/IHAGQBAAAA.',
El='Eldrene:BAABNQAECn8pAAIMAAkK0BofCQA3AgAMAAkK0BofCQA3AgAAAA==.Elizalde:BAAANQAECgYIDgAAAA==.Ellexi:BAAANQAECgQICAAAAA==.Elyseia:BAABNQAECn8hAAIOAAkKsw8JewAYAgAOAAkKsw8JewAYAgAAAA==.',
En='Enpower:BAAANQAECgQIBAABNQAFFAIIBQAeAFMHAA==.',
Es='Escata:BAAANQAECgMIAwAAAA==.Esdailongwe:BAAANQADCgMIBAAAAA==.Españamor:BAEBNQAECn8hAAMfAAoK5Q63FgD5AAAJAAcKugncGAAkAQAfAAoKIg63FgD5AAAAAA==.',
Eu='Eunite:BAABNQAECn9bAAISAAoK5RmkKACWAgASAAoK5RmkKACWAgAAAA==.',
Fa='Falkorne:BAAANQAECgYICgABNQAECgoKKQAeALQYAA==.Farael:BAAANQADCgYIBgAAAA==.Fashah:BAAANQAECgIIAgAAAA==.Fatalmann:BAAANQAECgIIAgAAAA==.',
Fe='Felmoo:BAAANQAECgYIDQAAAA==.Felorc:BAABNQAECn8cAAMGAAkK7QMCKwDhAAAGAAkK7QMCKwDhAAAbAAIKKAIbTQE6AAABNQAECgkJIQALAIYGAA==.',
Fi='Fintan:BAAANQADCggICAABNQAFFAYIFgAEAOMZAA==.',
Fo='Forsakenemp:BAAANQAECgcIBwABNQAECgkJIgAaAPMNAA==.',
Fr='Frassk:BAABNQAECn8nAAMIAAkKtg+LCQCFAAAHAAcKGw7TlQCwAQAIAAIKuROLCQCFAAAAAA==.Frigid:BAAANQADCgcIBwAAAA==.Froggystyle:BAAANQAECgcIDwAAAA==.Frozenheart:BAABNQAECn8hAAMLAAkKhga5dwAZAQALAAkKhga5dwAZAQATAAIK9gGEsgAtAAAAAA==.Fruk:BAAANQADCgUIBQAAAA==.Frösting:BAAANQADCgYIBgABNQAECgcIGQAgACMWAA==.',
Ft='Ftx:BAABNQAECn8mAAIbAAkKQSERHwCIAQAbAAkKQSERHwCIAQAAAA==.',
Fu='Fundidos:BAAANQADCggIEAAAAA==.',
Ga='Garbarn:BAAANQADCgcIDQAAAA==.',
Ge='Gelystine:BAAANQADCgIIAgAAAA==.Geminichi:BAACNQAFFH8FAAIeAAIKUwedBABzAAAeAAIKUwedBABzAAA1AAQKfy8AAx4ACgqUGaANAKoCAB4ACgqUGaANAKoCACEAAQqFEClqADcAAAAA.',
Gh='Ghauri:BAAANQADCgYJBgAAAA==.Ghorza:BAAANQADCgYIBwAAAA==.',
Gi='Gia:BAABNQAECn8qAAIeAAkKJRs6AwADAgAeAAkKJRs6AwADAgAAAA==.Gigasauce:BAAANQAECgEIAQAAAA==.Giraffage:BAABNQAECn8WAAIMAAcK6Q9j4ADIAQAMAAcK6Q9j4ADIAQABNQAECgcICQANAAAAAA==.',
Go='Golgroth:BAAANQADCgQJBAAAAA==.Gorearrow:BAABNQAECn8tAAIOAAoK7htgMwDSAgAOAAoK7htgMwDSAgAAAA==.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Grimmtotem:BAAANQAECggIBwAAAA==.Groggyfroggy:BAAANQADCgMJAwAAAA==.Grralt:BAAANQAECgIIAgABNQADCggIHQANAAAAAA==.Grís:BAABNQAECn8pAAMbAAoKBhSTaABWAgAbAAoKahOTaABWAgAGAAMKCA3uMwCXAAAAAA==.',
Gu='Gumbuz:BAAANQAECgQIBAAAAA==.Gunafistya:BAAANQAECgMIBQAAAA==.',
Ha='Harrier:BAAANQADCgYICgABNQAECgcIFAAWAEERAA==.Hazed:BAABNQAECn8UAAIMAAgKJA14IQCMAQAMAAgKJA14IQCMAQAAAA==.Hazzaa:BAAANQAECgcICwAAAA==.',
He='Healzforbeer:BAAANQADCgUIBQAAAA==.Herioffy:BAAANQADCgEIAQAAAA==.Hexxan:BAAANQADCgYIBgAAAA==.',
Hi='Hiawatha:BAAANQADCgQIBAAAAA==.Hiver:BAAANQAECgEIAQAAAA==.',
Ho='Holier:BAABNQAECn8wAAIBAAoKnw1VmwDsAQABAAoKnw1VmwDsAQAAAA==.Holybishh:BAAANQAECgUIBQAAAA==.Holyregerts:BAABNQAECn8cAAMDAAoKtQ4wJAAPAgADAAkK5A0wJAAPAgACAAgKzRODcQDIAQAAAA==.Honk:BAAANQAECgcIDwAAAA==.Hoochurcooch:BAAANQAECgQIBAAAAA==.Hoosnext:BAAANQADCgcIBgAAAA==.Hopperstotem:BAAANQAECgMIAwABNQAECggIEgANAAAAAA==.',
Hu='Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQAECgIIAgAAAA==.',
Il='Illumi:BAAANQABCgYIBgAAAA==.',
Im='Imbatmann:BAAANQADCgEIAQAAAA==.',
In='Indrà:BAAANQADCgQIBQAAAA==.Infamus:BAAANQAECgIIBQAAAA==.Invysion:BAACNQAFFH8MAAIcAAUKEAKWAQApAQAcAAUKEAKWAQApAQA1AAQKfzEAAhwACgqeEGcGACgCABwACgqeEGcGACgCAAAA.',
Is='Ishara:BAAANQAECgEIAQABNQAECgkJKQAMANAaAA==.Islander:BAAANQAECgYIDQAAAA==.',
Ja='Jackychang:BAABNQAECn8UAAIVAAgKRg1hGwD7AQAVAAgKRg1hGwD7AQAAAA==.Jaidess:BAAANQADCggIDgAAAA==.Jakeypoo:BAAANQAECgQICQAAAA==.',
Je='Jellybea:BAABNQAECn8kAAMCAAoK7RycGQCoAQACAAoK7RycGQCoAQADAAIKAAB2agBZAAAAAA==.',
Ji='Jimmee:BAAANQADCgIIAgAAAA==.',
Ju='Jukoti:BAAANQABCgIIBAAAAA==.Junglebrew:BAAANQAECgEIAQAAAA==.Junglepino:BAAANQAECgEIAQAAAA==.Jurisdiction:BAABNQAECn8YAAIBAAcKhwaOkwCwAAABAAcKhwaOkwCwAAAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAABNQAECn8xAAIhAAoKDhy4BADLAQAhAAoKDhy4BADLAQAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kanalz:BAAANQAECgUIBQAAAA==.Kasey:BAABNQAECn8VAAIBAAYK8B4guwCnAQABAAYK8B4guwCnAQAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keho:BAABNQAECn8YAAIiAAcKVgR1CwChAAAiAAcKVgR1CwChAAAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAACNQAFFH8LAAIKAAQKNRSjDwAMAQAKAAQKNRSjDwAMAQA1AAQKfzQAAx8ACgonHrkYAJYCAB8ACQrDHLkYAJYCAAoACgo/G9ghAI0CAAE1AAQKBwgJAA0AAAAA.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kickdrop:BAAANQADCgQIBAAAAA==.Kilgreed:BAAANQADCgYIDgAAAA==.Killaban:BAAANQAECgcIBwAAAA==.Killbydeath:BAAANQAECgYIEwAAAA==.Kimberlyhárt:BAAANQAECgYJEAAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYJEAANAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAABNQAECn9VAAIHAAoK/hofEgC0AQAHAAoK/hofEgC0AQAAAA==.',
Ko='Kohman:BAABNQAECn84AAMHAAoKCBVAMQDDAgAHAAoKCBVAMQDDAgAIAAMKMg1xUgCIAAAAAA==.Komatose:BAAANQADCgYIBgAAAA==.Kong:BAAANQADCgIIAwAAAA==.',
Kr='Krftpnk:BAACNQAFFH8fAAIKAAcKHCGBAQC0AgAKAAcKHCGBAQC0AgA1AAQKfzYAAgoACgrDIy4CANUDAAoACgrDIy4CANUDAAAA.Kricket:BAAANQAECgEIAgAAAA==.Kronas:BAABNQAECn8UAAIOAAgKKxRzMwBXAQAOAAgKKxRzMwBXAQAAAA==.Kronosity:BAABNQAECn8mAAIaAAkKnx6mCgDwAgAaAAkKnx6mCgDwAgABNQAECgoKOgALAIUiAA==.Kronotality:BAABNQAECn86AAILAAoKhSLDBQCXAwALAAoKhSLDBQCXAwAAAA==.Kronotekken:BAAANQAECgEIAQABNQAECgoKOgALAIUiAA==.Kronotide:BAAANQADCgQIBAABNQAECgoKOgALAIUiAA==.',
Ku='Kungfukittn:BAABNQAECn8dAAIhAAcKIxagKwC+AQAhAAcKIxagKwC+AQAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQAECgUICAAAAA==.Kyojuro:BAAANQABCgYIBgAAAA==.',
Kz='Kzorx:BAAANQADCgYIDwAAAA==.',
La='Laimaster:BAAANQAECgQIBAAAAA==.Lakiri:BAABNQAECn8oAAIgAAcK/hTvFwDpAQAgAAcK/hTvFwDpAQAAAA==.Landaeda:BAAANQADCgcIBwAAAA==.Lascivia:BAABNQAECn8mAAMGAAoKayBaBgACAwAGAAoKayBaBgACAwAjAAQKABj7GAASAQAAAA==.Latrice:BAAANQAECgcIBwABNQAFFAcIEwAPAOAdAA==.Laylahh:BAAANQADCgQIBAAAAA==.',
Le='Leademon:BAABNQAECn8YAAIKAAkKFxhpDwBxAQAKAAkKFxhpDwBxAQAAAA==.Leadmln:BAAANQAECgQIBQABNQAECgkJGAAKABcYAA==.Lebwonsamdi:BAAANQAECgEIAQABNQAECgoKKQAbAAYUAA==.',
Li='Lighterfluîd:BAAANQABCgIIAgABNQAECgoKLgAeAFEfAA==.Ligmadk:BAAANQADCgUIBQABNQAFFAQIBwAKAIMIAA==.Lilbeebs:BAAANQAECgIIAgAAAA==.Lilflea:BAABNQAECn8eAAMEAAoKWBglEwC7AQAEAAoKWBglEwC7AQAkAAEKAAD5TAEnAAAAAA==.Lillidari:BAAANQAECgcICQABNQAECgkJJgALACwkAA==.Lilzuki:BAAANQAECgMIBQAAAA==.Lilïth:BAABNQAECn8mAAILAAkKLCQkCwBbAwALAAkKLCQkCwBbAwAAAA==.Linguine:BAAANQADCggICAABNQAFFAMICQADAHQNAA==.Lisalisa:BAABNQAECn8fAAIEAAgKUhMJJQBQAQAEAAgKUhMJJQBQAQAAAA==.Littlej:BAAANQAECgQJBAAAAA==.Littlejohn:BAABNQAECn8pAAIeAAoKtBjhBwBhAQAeAAoKtBjhBwBhAQAAAA==.',
Lo='Logantis:BAAANQAECggIDgAAAA==.Logaothe:BAABNQAECn8UAAIBAAYKJQpOAgEbAQABAAYKJQpOAgEbAQAAAA==.',
Lu='Lucky:BAAANQAECgcIDQAAAA==.Lukethywalkr:BAAANQADCgYICgAAAA==.Lularia:BAAANQADCgUICAAAAA==.Lunaa:BAAANQAECgQIBwAAAA==.Lusid:BAAANQABCgcICAAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Makagh:BAAANQAECgEIAQAAAA==.Maliciousrot:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQIBQAAAA==.Marona:BAAANQAECggIAQAAAA==.',
Me='Medikus:BAABNQAECn8nAAIEAAkKUBjzDQDvAQAEAAkKUBjzDQDvAQAAAA==.Megajoo:BAAANQAECgQIBgAAAA==.Melkinov:BAAANQAECgEIAQAAAA==.Merryl:BAAANQAECgUIBwAAAA==.',
Mf='Mfive:BAAANQAECgQIBAAAAA==.',
Mi='Mike:BAEBNQAECn8cAAIMAAkK4iGtUQDdAgAMAAkK4iGtUQDdAgAAAA==.Milkjugs:BAAANQAECgMIAgABNQAECgoKHgAEAFgYAA==.Minijeangen:BAAANQAECgMJAwAAAA==.Missluana:BAAANQABCgEIAQAAAA==.',
Mo='Mockra:BAABNQAECn9AAAIMAAgKGhZxrAApAgAMAAgKGhZxrAApAgAAAA==.Moistmunnky:BAAANQAECgQICgAAAA==.Montera:BAEANQAECggIDQABNQAECgoKIQAfAOUOAA==.Moohammered:BAABNQAECn8eAAIBAAoKMhFUHgCpAQABAAoKMhFUHgCpAQAAAA==.Moolou:BAABNQAECn8kAAIaAAoKNBrtEACRAgAaAAoKNBrtEACRAgAAAA==.Mootarded:BAAANQAECgcIEQABNQAECgkJIQALAIYGAA==.Mordiggian:BAABNQAECn80AAMLAAkKoiPQDwAvAwALAAgKAiPQDwAvAwASAAkKZiMFGQD3AgAAAA==.Morechie:BAABNQAECn8jAAIZAAgKAxEkCQD0AQAZAAgKAxEkCQD0AQAAAA==.Morganaj:BAAANQAECgIIAgAAAA==.Morgatho:BAAANQABCgcICQAAAA==.Morsz:BAAANQAECgUICAAAAA==.Mortiferon:BAABNQAECn8jAAISAAkKShrUOwAyAgASAAkKShrUOwAyAgAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQAECgQICgANAAAAAA==.Munnkypox:BAAANQAECgIIBAABNQAECgQICgANAAAAAA==.Murderella:BAAANQADCgYIBgAAAA==.Muriggs:BAAANQAECgMIAwAAAA==.Murkhoof:BAAANQADCgYIBgABNQAECgcIFAAWAEERAA==.',
['Mö']='Mörgänä:BAAANQADCggIEQAAAA==.',
Na='Nakovii:BAAANQAECgUIBQAAAA==.Nascerathel:BAAANQAECgYIBgAAAA==.Nasmina:BAAANQAECggIAQAAAA==.',
Ne='Nealite:BAAANQADCgYIBgAAAA==.Neferata:BAABNQAECn81AAMHAAoK4hliFwCWAQAHAAoK4hliFwCWAQAIAAYKbgvNJwA6AQAAAA==.Nerrisa:BAAANQADCggIDwAAAA==.Nertmage:BAABNQAECn9dAAQUAAoKWCJQAACfAwAUAAoKWCJQAACfAwAPAAEKThkBFwBMAAAMAAIKAA7m7wA5AAAAAA==.Neublood:BAAANQAECgQIBwAAAA==.',
Ni='Nicodemus:BAAANQAECgQIBQAAAA==.Nineiota:BAABNQAECn8iAAIRAAgKExxrGQBwAgARAAgKExxrGQBwAgAAAA==.',
No='Noblewarrior:BAACNQAFFH8fAAIbAAYKtxkBEQCtAQAbAAYKtxkBEQCtAQA1AAQKfzYAAhsACgrgIB0aAE8DABsACgrgIB0aAE8DAAAA.Nobukawaii:BAAANQAECgMIAwAAAA==.Noctilus:BAAANQADCgcIDwAAAA==.Noke:BAAANQAECgIJAgAAAA==.Notakoala:BAACNQAFFH8PAAIXAAUK0RiZEABhAQAXAAUK0RiZEABhAQA1AAQKfzAAAhcACgrOIJEOAFUDABcACgrOIJEOAFUDAAAA.Nothnx:BAACNQAFFH8LAAIOAAQKnRQYBgD/AAAOAAQKnRQYBgD/AAA1AAQKfygAAg4ACgoiHAQDAL0CAA4ACgoiHAQDAL0CAAAA.Notillidan:BAAANQADCgQIBAAAAA==.Notoriouspat:BAAANQAECggIDAAAAA==.Novia:BAAANQAECggIDQABNQAECgoKKQAbAAYUAA==.Noxeternis:BAABNQAECn8oAAQDAAoK0xoyIQAuAgADAAgKwxkyIQAuAgACAAQKJhVAuQDtAAAcAAIKMgYgJABKAAAAAA==.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
Ny='Nyxandra:BAAANQADCgYIBgAAAA==.',
['Ní']='Níghtfall:BAAANQADCgUICwAAAA==.Nínebreaker:BAAANQAECgEIAQAAAA==.',
Ob='Obern:BAABNQAECn8aAAIlAAoKYxI5BQBzAgAlAAoKYxI5BQBzAgAAAA==.Obeysnapback:BAAANQADCgMIBAAAAA==.Oblïna:BAAANQAECgQIDAAAAA==.',
Od='Oddishh:BAAANQAECgcIEQAAAA==.',
Ol='Olleg:BAAANQADCgYICQAAAA==.',
Om='Omnicarkel:BAAANQADCgcIDAAAAA==.',
On='Onsen:BAABNQAECn8hAAIBAAoKBhaZLQB3AQABAAoKBhaZLQB3AQABNQAECgoKOAAHAAgVAA==.',
Or='Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQJBAAAAA==.',
Ou='Outwithabang:BAAANQAECgMIAwAAAA==.',
Pa='Pajl:BAABNQAECn8lAAIBAAkKkSOtDQCXAwABAAkKkSOtDQCXAwABNQAFFAcIDwATAKMeAA==.Pandablaze:BAAANQAECgQIBQAAAA==.Pandajoy:BAAANQADCgEIAQAAAA==.Panterarey:BAAANQAECgIIAgAAAA==.Papanurrgle:BAAANQAECgUICQAAAA==.Papazilla:BAAANQAECgMJAwAAAA==.Parakka:BAAANQAECgMIAgAAAA==.Patak:BAAANQADCgQIBAAAAA==.Pawp:BAAANQAECgcIEwABNQAECgoKLgACAHEYAA==.Paxiel:BAAANQAECgQICAAAAA==.',
Pe='Pearagon:BAAANQADCgYICQABNQAFFAYIEwAEAPoZAA==.Pepsidew:BAAANQAECgcICgAAAA==.Pepsisprite:BAABNQAECn8cAAICAAgKOBmEDgAIAgACAAgKOBmEDgAIAgAAAA==.',
Ph='Phdbeef:BAAANQAECgEIAQABNQAECgkJJgALACwkAA==.Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQAECgIIAgAAAA==.',
Pi='Picklez:BAABNQAECn8bAAITAAYKLhryJAAOAQATAAYKLhryJAAOAQAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.Portwings:BAAANQADCggIEwAAAA==.',
Ps='Psyop:BAAANQADCggIEAABNQAECgoKOwACAHYhAA==.Psyrax:BAAANQAECgQIBwAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Rashun:BAAANQADCgEIAQAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDgAAAA==.Redkoala:BAAANQAECgYIEwABNQAFFAUIDwAXANEYAA==.Regrets:BAAANQAECgEIAgABNQAECgoKHAADALUOAA==.Repete:BAAANQAECgQIBAAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECn9bAAIPAAoK+x8SAgBaAwAPAAoK+x8SAgBaAwAAAA==.Reven:BAAANQAECgYICAAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ri='Riivan:BAAANQAECgEIAQAAAA==.Rirugiliyang:BAAANQAECgEIAQAAAA==.Rivian:BAAANQAECgEIAQABNQAECgYIDQANAAAAAA==.',
Ro='Roardon:BAAANQADCggIDwAAAA==.Roflmfao:BAAANQADCggICAAAAA==.Roguè:BAAANQAECgQICgAAAA==.Rollinburn:BAAANQADCgUJBQAAAA==.Romanoff:BAABNQAECn8dAAMFAAgKdBKaPQDZAQAFAAcKBxOaPQDZAQAVAAMK1RHoJQDLAAAAAA==.Rosearcana:BAAANQAECgEIAQAAAA==.',
['Rô']='Rôx:BAAANQADCgcIBwABNQAECgkJWQAQAI0ZAA==.',
['Rõ']='Rõx:BAABNQAECn9ZAAMQAAkKjRlOLwCpAgAQAAkKjRlOLwCpAgABAAMKBw5euAB6AAAAAA==.',
Sa='Sackoss:BAABNQAECn8YAAIQAAcKhheQXwD6AQAQAAcKhheQXwD6AQAAAA==.Saffronspark:BAAANQAECgUIDAABNQAECgoKLwAhAHsaAA==.Sainsei:BAABNQAECn8UAAMiAAcKDRHmCwCZAAAiAAYKnA/mCwCZAAAhAAMKDAwBVgCUAAABNQAECgoKKQAbAAYUAA==.Sakata:BAAANQADCgIIAgABNQAECgcIFAAWAEERAA==.Sandwitch:BAABNQAECn9bAAMIAAoKThJuDwAGAgAHAAoKhhAjYAA4AgAIAAgKTxBuDwAGAgAAAA==.Sargatanas:BAABNQAECn8jAAILAAkK8gw/UgCsAQALAAkK8gw/UgCsAQAAAA==.Sars:BAAANQADCgUIBQABNQAECgYIDQANAAAAAA==.',
Sc='Scarcroww:BAAANQADCgMIAwABNQAECgoKIgAMAIMdAA==.Schrodinger:BAAANQAECgIIBAAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Septicflësh:BAAANQAECggICAAAAA==.Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAABNQAECn8nAAIGAAgKOhJSBgBXAQAGAAgKOhJSBgBXAQAAAA==.',
Sh='Shadrad:BAABNQAECn8eAAMBAAoKWx+IJwAoAwABAAoKWx+IJwAoAwAQAAYKeQP5xgDtAAAAAA==.Shallot:BAABNQAECn8sAAIMAAoKLx/dNwAYAwAMAAoKLx/dNwAYAwAAAA==.Shammoo:BAAANQAECggIEQABNQAFFAQIBgABAMYLAA==.Shammyd:BAAANQAECgUIEAAAAA==.Shantz:BAABNQAECn8eAAILAAkKtQhSFgA0AQALAAkKtQhSFgA0AQAAAA==.Shiftface:BAAANQADCgUIBwABNQAECggIEQANAAAAAA==.Shiftmypants:BAAANQAECggIEwAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Si='Sinterdeath:BAAANQAECgUIDwAAAA==.',
Sk='Skatervan:BAAANQADCggIEwABNQAECgoKOgADACQbAA==.Skylie:BAAANQADCgYIDwAAAA==.',
Sl='Slushpuppy:BAAANQAECgIIAgAAAA==.',
Sm='Smallpaladin:BAAANQAECgEIAQAAAA==.Smorthian:BAAANQAECgQIDwAAAA==.',
Sn='Sniffinsteak:BAAANQAECgYJEAAAAA==.Snoosnooftww:BAAANQAECgEIAQAAAA==.',
So='Solas:BAAANQAFFAEIAQAAAA==.Sonarael:BAAANQAECgQIBAABNQAECgkJKQAMANAaAA==.Sondeltis:BAAANQAECgQIBQAAAA==.Soryan:BAAANQAECgUIBQAAAA==.',
Sp='Spankenstine:BAABNQAECn8dAAIBAAgKlhotbQBXAgABAAgKlhotbQBXAgABNQAECggIIwAbAHcSAA==.Sparkyy:BAAANQAECgIIAwAAAA==.Sphaeram:BAAANQAECgcICAAAAA==.Spicypepsi:BAAANQADCgEIAQAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAABNQAECn8fAAIBAAkKrhxEFADaAQABAAkKrhxEFADaAQAAAA==.Stinkydeathy:BAAANQADCgYJBgABNQAECgIIAgANAAAAAA==.Stinkydragon:BAAANQAECgIIAgAAAA==.Stormknight:BAAANQAECgYICwAAAA==.Stormpoo:BAAANQAECgMIAgAAAA==.',
Su='Suneater:BAABNQAECn8aAAIQAAoK7hnKCwAIAgAQAAoK7hnKCwAIAgAAAA==.Superpi:BAAANQADCgYIBgABNQAECgUICAANAAAAAA==.Superret:BAAANQAECgUICAAAAA==.Surotor:BAAANQADCgQIBAAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAAANQAECggIEQAAAA==.',
Sw='Swíper:BAACNQAFFH8FAAIFAAIKLA8iFwCUAAAFAAIKLA8iFwCUAAA1AAQKfy4AAwUACgrAHHkIAFADAAUACgrAHHkIAFADABUABQq1CTA4APcAAAAA.',
Sy='Sylphièl:BAACNQAFFH8NAAMVAAUKgwdHDADuAAAVAAQKpghHDADuAAAFAAEKGwS9CQBEAAA1AAQKfykAAxUACgqoFrcHALYBAAUACQoxCflBAMMBABUACArTGLcHALYBAAAA.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgcIDQAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECn8oAAIBAAkKmiJpLAAWAwABAAkKmiJpLAAWAwAAAA==.Tankenstine:BAABNQAECn8jAAIbAAgKdxLYJgBqAQAbAAgKdxLYJgBqAQAAAA==.Tawnii:BAAANQAECgMIBAAAAA==.Taírn:BAAANQAECgQIBAAAAA==.',
Te='Tenderloin:BAAANQAECgUIDQAAAA==.',
Th='Thanitose:BAAANQAECgYIDgAAAA==.Thevelo:BAAANQAECgIIAgABNQAECggIDAANAAAAAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thornwyn:BAAANQAECgYIDAAAAA==.Thors:BAAANQADCgQIBAAAAA==.Thorul:BAAANQADCgEIAQAAAA==.Thundurus:BAACNQAFFH8MAAIkAAMKWwcdDgCGAAAkAAMKWwcdDgCGAAA1AAQKfzoAAiQACgpXFwlGAF4CACQACgpXFwlGAF4CAAAA.',
Ti='Timmayy:BAAANQAECggIDAABNQAECgoKKQAeALQYAA==.Tindrill:BAAANQAECgMIAwABNQAECgkJJwARAMkhAA==.Tinggoskrrah:BAAANQADCggIEgAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAABNQAECn8kAAIbAAcKrxBsswCcAQAbAAcKrxBsswCcAQAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAcIHwAKABwhAA==.Totemagoat:BAACNQAFFH8KAAMEAAYKLw/yDQBuAQAEAAYKLw/yDQBuAQAkAAEKsQXlMgBEAAA1AAQKfzUAAwQACgpEH4MWAB0DAAQACgpEH4MWAB0DACQACApvFtBgAP8BAAAA.',
Tr='Tracula:BAAANQADCgEIAQAAAA==.Treefist:BAAANQADCggIGgAAAA==.Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAACNQAFFH8JAAIRAAMKmQYpDgDHAAARAAMKmQYpDgDHAAA1AAQKfy0AAxEACgonFAgdAEsCABEACgonFAgdAEsCABcAAgpMAuVDAFgAAAAA.',
Un='Undeadkiels:BAAANQADCggICAABNQAECgkJIgAaAPMNAA==.Undeadmonks:BAAANQADCgYIBgAAAA==.',
Ur='Uraharakun:BAAANQAECgUIDgABNQAECgoKMQABAJoNAA==.',
Va='Vagalion:BAAANQAECggIDgAAAA==.Valdanyr:BAAANQADCgYICgAAAA==.Vale:BAAANQAECgMIAwAAAA==.Valeshot:BAABNQAECn8kAAIOAAoKPQ1+dwAgAgAOAAoKPQ1+dwAgAgAAAA==.Valimyr:BAAANQABCgMIBAAAAA==.Valkillrie:BAAANQAFFAEIAwAAAA==.Valohir:BAAANQAECgIIAgAAAA==.Vanhellsin:BAABNQAECn8UAAILAAcKPw7sZgBXAQALAAcKPw7sZgBXAQAAAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECgkJFgABAAcjAA==.Vedronas:BAABNQAECn8WAAIBAAkKByPmJQAuAwABAAkKByPmJQAuAwAAAA==.Veos:BAABNQAECn8sAAIPAAoK0hgeBQDIAgAPAAoK0hgeBQDIAgAAAA==.Verdict:BAAANQADCgYIGwAAAA==.Vern:BAABNQAECn8aAAMCAAgKRRMIZAD0AQACAAgKRRMIZAD0AQAcAAEKzQgLLAAsAAAAAA==.Vernaar:BAAANQAECgcIBwABNQAECggIGgACAEUTAA==.Vernah:BAAANQADCgIIAgABNQAECggIGgACAEUTAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Volætile:BAAANQAECgQIBQABNQAECgcIGQAgACMWAA==.Vorn:BAABNQAECn9bAAILAAoKjxlYIACxAgALAAoKjxlYIACxAgAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAABNQAECn8nAAIYAAgKDBusBADGAQAYAAgKDBusBADGAQAAAA==.Waamchifu:BAAANQAECgEJAQAAAA==.Waltersight:BAAANQAECgMIBQAAAA==.Warbritt:BAAANQADCgYJBgAAAA==.Warförged:BAAANQAECggICAAAAA==.Warwuff:BAAANQADCgUICAAAAA==.Waterwalkerr:BAAANQADCgYIBgAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgUIDgAAAA==.Whatthezug:BAAANQABCgIIAgABNQAECgQICQANAAAAAA==.Whoforted:BAABNQAECn8lAAMCAAoKlxUfDgAMAgACAAkKkRQfDgAMAgADAAcKzhJVKgDVAQAAAA==.',
Wi='Wisperia:BAAANQADCgQICQAAAA==.',
Wo='Wormchild:BAAANQADCgIIAgAAAA==.',
Wu='Wulrat:BAAANQAECggIEgAAAA==.',
Wy='Wyle:BAAANQAECgQIBwAAAA==.',
Xe='Xelí:BAABNQAECn9cAAIEAAoKNhjOFwCZAQAEAAoKNhjOFwCZAQAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAABNQAECn8VAAIOAAkKXRWMTwCAAgAOAAkKXRWMTwCAAgABNQAFFAYIFgAEAOMZAA==.',
Xt='Xtremes:BAAANQAECgUICwABNQAFFAIIBQAeAFMHAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.Youvbendoted:BAAANQAECggIDQAAAA==.',
Yu='Yudah:BAAANQAECgEIAQABNQAECgQIBAANAAAAAA==.',
Za='Zanghonghua:BAABNQAECn8vAAIhAAoKexqPAgAwAgAhAAoKexqPAgAwAgAAAA==.',
Ze='Zemy:BAABNQAECn8kAAMXAAoKGiWwCgB3AwAXAAoKGiWwCgB3AwAYAAcK0xctHwClAQAAAA==.Zeneca:BAAANQAECgIIAgABNQAFFAMICQADAHQNAA==.',
Zo='Zodstrike:BAABNQAECn8jAAMKAAcKmAjkUABUAQAKAAcKmAjkUABUAQAfAAUKCwJrKwBlAAAAAA==.Zooboo:BAAANQAECgcIEQAAAA==.',
Zu='Zugzuggler:BAABNQAECn8nAAIbAAgKChyNDgDmAQAbAAgKChyNDgDmAQAAAA==.',
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
