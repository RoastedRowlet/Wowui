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

local lookup = {'Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','Rogue-Subtlety','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Druid-Balance','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Mage-Frost','Rogue-Assassination','Paladin-Holy','Paladin-Protection','Druid-Feral','Warlock-Demonology','DeathKnight-Blood','Mage-Arcane','Hunter-Survival','Shaman-Enhancement','DemonHunter-Devourer','Mage-Fire','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Evoker-Preservation','Monk-Mistweaver','DemonHunter-Havoc','Warrior-Fury','Priest-Discipline','Rogue-Outlaw',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abssorath:BAAANQADCgcICwAAAA==.',
Ae='Aerouant:BAABNQAECn9IAAMBAAoKuRiQBQBTAgACAAkKeReXBgBWAgABAAkKjReQBQBTAgAAAA==.',
Ai='Aidix:BAAANQAECgEIAgAAAA==.Aimassist:BAAANQAECgQIBAAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAABNQAECn80AAIDAAoK+R15DwDfAgADAAoK+R15DwDfAgAAAA==.Alexstanna:BAAANQAECgUICwAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.Alwaysbroke:BAAANQAECgYICQAAAA==.',
An='Andrena:BAABNQAECn8YAAIEAAgKwBKVRQDPAQAEAAgKwBKVRQDPAQAAAA==.Andycat:BAAANQAECgEIAgAAAA==.Annarchy:BAAANQADCgQIBAAAAA==.Antagony:BAAANQAECgUIBQAAAA==.Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAABNQAECn8wAAIFAAoKQBTJCQBEAgAFAAoKQBTJCQBEAgAAAA==.Anthross:BAABNQAECn8qAAIGAAoKHw9/hgD+AQAGAAoKHw9/hgD+AQAAAA==.',
Ap='Apollovon:BAABNQAECn8rAAIHAAkKeyGkLQAGAwAHAAkKeyGkLQAGAwAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanemage:BAAANQADCgYIBwAAAA==.Arcanenug:BAAANQADCgQJBAAAAA==.Arcbnonez:BAAANQAECgQIBQAAAA==.Arguxx:BAAANQAECggIEwAAAA==.Armiggy:BAABNQAECn9RAAIIAAoKSxWQEgAlAgAIAAoKSxWQEgAlAgAAAA==.Aro:BAACNQAFFH8TAAMJAAcKcCALCgCiAQAJAAYKYB8LCgCiAQAGAAIK4huxIACwAAA1AAQKfy4AAwkACgqwJDUXAMQBAAYABgrQI6OZANQBAAkACApRIzUXAMQBAAAA.Arrowraen:BAABNQAECn8rAAIGAAkK/SMfBwCkAwAGAAkK/SMfBwCkAwAAAA==.',
As='Asavera:BAAANQAECgcICgAAAA==.Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgYJBgAAAA==.Asträl:BAAANQAECgEIBAAAAA==.',
Au='Audomere:BAABNQAECn8rAAMKAAoKpwxVVwCfAQAKAAoKpwxVVwCfAQALAAIKlgFXLQE7AAAAAA==.Auurwarr:BAAANQAECgUIBQAAAA==.',
Av='Avawrath:BAAANQAECggIEgAAAA==.Avelm:BAAANQAECggIAwAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgoKMwAFADwfAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Bailey:BAAANQAECgIIAQABNQAECgQICAAMAAAAAA==.Balanji:BAAANQADCgUIBQABNQAECgoKFwAFALoUAA==.Ballstench:BAAANQAECgYICQAAAA==.Barbåtos:BAAANQAECgMIBQAAAA==.Baskthyr:BAAANQADCgQIBAAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAABNQAECn8XAAINAAgKSBQ1OQAmAgANAAgKSBQ1OQAmAgABNQADCgUIBQAMAAAAAA==.Bearbomblolz:BAAANQADCgQIBQABNQAECgoKFwAFALoUAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQAECgEIAgAAAA==.Beastbane:BAAANQAECggIEQAAAA==.Beastly:BAAANQAECgYICwAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAABNQAECn83AAMHAAoKuhiyRQC4AgAHAAoKuhiyRQC4AgAOAAgKVhTyFQDJAQAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAABNQAECn9rAAMPAAgKiBg6QgATAgAPAAgKoBc6QgATAgAQAAgKDBEQQgB7AQAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgAMAAAAAA==.Bewslee:BAAANQAECgEIAwABNQAECgUIBQAMAAAAAA==.Bexx:BAAANQADCggJGQAAAA==.',
Bi='Bibledaddy:BAABNQAECn9FAAMRAAoKKxmZSgBFAgARAAoKKxmZSgBFAgASAAYKEQkMQgAhAQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgcIDQAMAAAAAA==.Bigbonks:BAAANQAECgQIBwAAAA==.Bigdumb:BAAANQAECgUICAAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.Billclintun:BAAANQADCgcIFgAAAA==.',
Bl='Blackplague:BAAANQAECgEIAQAAAA==.Blaezèr:BAAANQAECgQIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQAECggIDQAAAA==.Blueshamoo:BAAANQAECgEJAQAAAA==.Blupl:BAAANQABCgYIBgAAAA==.Blãezer:BAAANQAECggIDAAAAA==.',
Bo='Bonex:BAAANQAECgEIAgAAAA==.Boomshroom:BAAANQAECgMIBgABNQAECgoKOwAIAO4fAA==.Bootsie:BAAANQADCggICAAAAA==.',
Br='Brewtoe:BAABNQAECn8tAAIIAAgK8xioEwAXAgAIAAgK8xioEwAXAgAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Broshunteri:BAAANQADCggICAAAAA==.Bruegard:BAAANQADCgIIAgAAAA==.Bruneau:BAAANQAECgEIAQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAgIGwAJAEYaAA==.',
Bu='Bubblemehard:BAABNQAECn8cAAITAAgKMhibewAzAgATAAgKMhibewAzAgAAAA==.Bushky:BAAANQAECgMIAwAAAA==.',
By='Byahnbreath:BAACNQAFFH8FAAIQAAIK7waxGAB7AAAQAAIK7waxGAB7AAA1AAQKfygAAhAACgo0G5EjAHQCABAACgo0G5EjAHQCAAAA.',
Ca='Caesardr:BAABNQAECn8+AAIUAAoKmB3ACACnAgAUAAoKmB3ACACnAgAAAA==.Cakeiko:BAAANQAECgQIBQABNQAECgoKGgAVAD0RAA==.Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Carolaine:BAAANQADCgQIAgAAAA==.Casmiralda:BAAANQAECgEIAwAAAA==.Castielx:BAABNQAECn8ZAAIWAAcKthIcQQDHAQAWAAcKthIcQQDHAQAAAA==.Catnips:BAAANQAECgUIBgABNQAECgoKRQARACsZAA==.',
Ce='Celestraza:BAAANQAECggIEAAAAA==.Celirra:BAABNQAECn80AAIPAAoKDyFvDwA7AwAPAAoKDyFvDwA7AwAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.Cenzo:BAAANQAECgcIEAAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAABNQAECn8vAAIHAAoKxQuKkwBFAQAHAAoKxQuKkwBFAQAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAABNQAECn8WAAMWAAgKKxyANwD6AQAWAAcKKxyANwD6AQAEAAEKAAA3TwBDAAAAAA==.Chokma:BAABNQAECn8pAAILAAkKZhaKZgDtAQALAAkKZhaKZgDtAQAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAABNQAECn8gAAMXAAkKcw+OTgDHAQAXAAkKcw+OTgDHAQAYAAEKlAQGfgAfAAAAAA==.',
Ci='Cinnaa:BAAANQAECgUICgAAAA==.',
Cl='Clawdog:BAAANQADCgIIAgABNQAECgIIBAAMAAAAAQ==.Clawwz:BAAANQAECgMIBAAAAA==.Cleisthenes:BAAANQAECgEIAQABNQAECgUIBQAMAAAAAA==.Clors:BAABNQAECn8sAAQDAAoKnRtJEgCKAgADAAoKnRtJEgCKAgANAAIKnAnwcgBbAAAZAAIKOg1gRAA0AAAAAA==.',
Co='Compressed:BAAANQABCgIIAgAAAA==.Conflux:BAAANQADCggIFAAAAA==.Coopada:BAAANQABCgEIAQAAAA==.Cowvibez:BAAANQADCgUICgAAAA==.',
Cr='Crager:BAABNQAECn8VAAIHAAgKTwhPoAAoAQAHAAgKTwhPoAAoAQAAAA==.Crawlah:BAAANQADCggIDgABNQAECgoKUAALAOEcAA==.Crazegideon:BAAANQAECgEIAQAAAA==.Crazespawnz:BAAANQAECgEIAQAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIEwAAAA==.',
Cy='Cyberfairy:BAAANQAECgEJAgAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQAECgEIAQAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgcICAAAAA==.Dalìnar:BAAANQAECgYIDQAAAA==.Damadafacker:BAABNQAECn8wAAIHAAoKihkDOQBOAgAHAAoKihkDOQBOAgAAAA==.Darfine:BAAANQAECgMIAwAAAA==.Darkclôud:BAAANQAECgQIBAAAAA==.Darkkatriden:BAAANQADCgYIBgABNQAECgcIGAAaAJgJAA==.Darklia:BAABNQAECn8YAAIaAAcKmAmQzwArAQAaAAcKmAmQzwArAQAAAA==.Darthjae:BAABNQAECn9zAAMbAAkKZBtrGAAxAgAbAAkKZBtrGAAxAgAQAAEKAABQvgAfAAAAAA==.Darthmikkey:BAAANQADCgYIBgABNQAFFAYIEgAcAFUiAA==.Darthrakk:BAABNQAECn8qAAIdAAoKZhrUAwDBAgAdAAoKZhrUAwDBAgAAAA==.Davina:BAAANQADCgcIBwABNQAFFAQIBwATAAMOAA==.Daïn:BAAANQAECgcIDQAAAA==.',
De='Deadestmoonb:BAAANQADCgIIBAAAAA==.Deathalimon:BAABNQAECn88AAQbAAkKgxumGAAuAgAbAAkK0hmmGAAuAgAPAAgKnRTUUgDHAQAQAAEKTBBerQA0AAABNQAECgoKPgALABQYAA==.Deathvoid:BAAANQADCgQIAQAAAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQAECgEIAgAAAA==.Demonarian:BAAANQAECgcICgABNQAECgoKPgALABQYAA==.Demonicnut:BAAANQAECgMIAwABNQAECgkJKQALAGYWAA==.Demonpotato:BAAANQADCggICAABNQAECgoKUQARACYhAA==.Denardath:BAAANQADCgUIBQAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAABNQAECn8kAAMKAAoKvgnfXgCFAQAKAAoKvgnfXgCFAQALAAgKiAyTogBQAQAAAA==.Deroc:BAABNQAECn8iAAITAAoKoAdXwgA5AQATAAoKoAdXwgA5AQAAAA==.Desporato:BAAANQAECggIBQAAAA==.Deáthtáxi:BAAANQAECggICAAAAA==.',
Di='Digweeds:BAABNQAECn8XAAIeAAkKrRrgEADyAQAeAAkKrRrgEADyAQABNQAFFAEIAQAMAAAAAA==.Dinfarmer:BAAANQAECgUICgAAAA==.Dirtycheese:BAAANQAECgYIDQAAAA==.',
Dj='Djgha:BAAANQAECgIIBAAAAA==.',
Dm='Dmptruckdona:BAAANQAECgQIAwAAAA==.Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQAECgMIBgAAAA==.Doombap:BAACNQAFFH8KAAIfAAQKnwdrCQDBAAAfAAQKnwdrCQDBAAA1AAQKfygAAh8ACgpbFQATAB8CAB8ACgpbFQATAB8CAAAA.Dorunter:BAABNQAECn8zAAMJAAoK+BNMMwCzAQAJAAcKYBJMMwCzAQAGAAcKjxIMnABgAQAAAA==.Dottíe:BAAANQAECgcIDgABNQAECgoKUAALAOEcAA==.Doubledosage:BAABNQAECn8ZAAIGAAYKAgpI1QDsAAAGAAYKAgpI1QDsAAAAAA==.',
Dr='Dragonbnonez:BAAANQAECgQIBQAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Drakujin:BAAANQADCgMIBQAAAA==.Drboomboom:BAABNQAECn8oAAMcAAoKxgsEjgB3AQAcAAoKxgsEjgB3AQAgAAEKAADXDwAAAAAAAA==.Drdoitall:BAAANQAECgYIDAAAAA==.Dreadnpain:BAAANQADCgQIBAAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIBAABNQAFFAcIFQAQAMEfAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Du='Duukwan:BAABNQAECn8VAAMRAAkK8BmNJgDQAgARAAkK8BmNJgDQAgASAAEKjhH0VwA/AAAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.Elysiá:BAAANQADCggICAAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAACNQAFFH8QAAQhAAUKohlPBQCZAAAiAAIKfR0iBQCaAAAhAAIKtBdPBQCZAAAaAAIK6AHuOQAAAAA1AAQKfzwAAyIACgpUJaoDALYCACIACAp8JaoDALYCACEAAwqzJJoIAC4BAAAA.',
Er='Erayr:BAAANQAECgcIEQABNQAECgkJGQAcAAoNAA==.Ericolson:BAABNQAECn8yAAIHAAoKGxhxPABBAgAHAAoKGxhxPABBAgAAAA==.Erze:BAAANQAECgUIDAAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evilhealer:BAAANQAECgMIBwAAAA==.Evilmcgyver:BAAANQAECgEIAgAAAA==.Evosolz:BAEBNQAECn8dAAIHAAoKSQzSZAC8AQAHAAoKSQzSZAC8AQAAAA==.Evé:BAAANQAECgMIBAABNQAECgoKOwAIAO4fAA==.',
Ey='Eyehealu:BAAANQADCgIIAgABNQAECgoKKAAiALoPAA==.',
Ez='Ezzartkal:BAAANQAECgEIAgAAAA==.',
Fa='Faeloria:BAAANQADCggICgAAAA==.Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgkJcwAbAGQbAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgoKMQAjAP4gAA==.Fefra:BAAANQADCgQIBAAAAA==.Felicious:BAABNQAECn8jAAIaAAoKGhNZXwCjAQAaAAoKGhNZXwCjAQAAAA==.Feralco:BAAANQAECgYIEAAAAA==.Fertra:BAAANQAECgEIAQAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fixiation:BAAANQAECgEIAQAAAA==.Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Flashdance:BAAANQADCggIHAAAAA==.Fleepo:BAAANQAECgIIAwAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAABNQAECn82AAMkAAoKuw1mHQD3AQAkAAoKuw1mHQD3AQABAAEKAAC7PgAvAAAAAA==.Flyhawk:BAAANQAECgUICwAAAA==.Flöör:BAAANQADCgUIBQAAAA==.',
Fo='Footloose:BAAANQAECgcIDAABNQAECgkJcwAbAGQbAA==.',
Fu='Fullmetal:BAABNQAECn8XAAIiAAgKaQxqDABdAQAiAAgKaQxqDABdAQAAAA==.Funkadelfic:BAAANQAECgYICAAAAA==.',
['Fè']='Fèngshui:BAAANQADCggIGwAAAA==.',
['Fé']='Fénrír:BAAANQADCggIDwABNQAECgoKNwALALogAA==.',
['Fò']='Fòxxy:BAAANQAECgMIAQAAAA==.',
Ga='Galadri:BAABNQAECn8ZAAMKAAgK/BuUQQBaAgAKAAgK/BuUQQBaAgALAAUKCxAXwwAMAQAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIEwAAAA==.Geartryx:BAAANQADCggIDQAAAA==.Geodood:BAAANQAECgYIDgAAAA==.',
Gh='Ghoshshadow:BAAANQAECgYIBwAAAA==.Ghostinz:BAABNQAECn8XAAIHAAcKkQy7ngArAQAHAAcKkQy7ngArAQAAAA==.',
Gi='Gimpripper:BAAANQAECgcICgAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggJIAAbAGcaAA==.Globalcold:BAABNQAECn8bAAIHAAgKLBoLdAA4AgAHAAgKLBoLdAA4AgAAAA==.Globb:BAABNQAECn8xAAIHAAgKVxSIlwDhAQAHAAgKVxSIlwDhAQAAAA==.Globius:BAABNQAECn8yAAITAAoKdhtNSgC2AgATAAoKdhtNSgC2AgAAAA==.Gloriouscole:BAABNQAECn8UAAITAAYKBCIhdgBBAgATAAYKBCIhdgBBAgAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gooly:BAAANQADCgIIAgAAAA==.Goombit:BAAANQADCgEIAQAAAA==.Gospel:BAAANQAECgEIAgAAAA==.',
Gr='Greekorc:BAAANQABCgYJBwAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Grimby:BAAANQAECggIBgAAAA==.Grimdisney:BAAANQADCggIDgAAAA==.Groceries:BAAANQADCgMIAwAAAA==.Gromol:BAAANQADCggIHwAAAA==.Grumby:BAAANQAECgIIBwAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQAECgQIBAAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQAECgQIBgAAAA==.Hareball:BAAANQAECgEIAQAAAA==.Hatebrêêd:BAAANQADCgQIBQAAAA==.Hazhazbot:BAAANQADCgYIBQAAAA==.',
He='Healman:BAAANQADCgcIGQAAAA==.Healpaws:BAAANQADCgUIBQAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgcIDAAAAA==.Heiden:BAAANQADCgYJBgAAAA==.Hel:BAAANQAECgIIAwAAAA==.Hellyas:BAABNQAECn8YAAMTAAgKkAsYAAEfAQATAAYK/QsYAAEfAQAYAAMKSgtnRACCAAAAAA==.Herbs:BAAANQAECgEIAQABNQAECgoKSAAEADMaAA==.Herenorthere:BAABNQAECn8yAAMSAAoKgBr6GgBxAgASAAgKEhz6GgBxAgARAAgKgxs3dQC8AQABNQAFFAUICwAiABsXAA==.Hermippe:BAAANQAECgMIAwAAAA==.Hexstraits:BAACNQAFFH8GAAIbAAIKRBMsIACIAAAbAAIKRBMsIACIAAA1AAQKfycAAhsACgrHIiMQACwDABsACgrHIiMQACwDAAAA.',
Hi='Hia:BAACNQAFFH8UAAIbAAYKyByhCgCtAQAbAAYKyByhCgCtAQA1AAQKf0MABBsACgrGIh4LAFsDABsACgrGIh4LAFsDAA8AAQpAB6OGADAAABAAAgpmAbi9AA8AAAAA.Highriskbr:BAAANQAECggICAAAAA==.Hitlist:BAAANQADCgUJBQAAAA==.',
Ho='Holycow:BAAANQAECgIIBQAAAA==.Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBwAAAA==.Hondaimpala:BAAANQAECgQIBwABNQAECgkJcwAbAGQbAA==.Hoofmaster:BAAANQAECgEIAgAAAA==.Hopskotch:BAAANQADCgQIBAAAAA==.Hordenfel:BAAANQADCggIEAAAAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huffy:BAAANQAECggIDQABNQAFFAUIBgAHADgbAA==.Huffyy:BAACNQAFFH8GAAIHAAUKOBvrIAD4AAAHAAUKOBvrIAD4AAA1AAQKf2sAAgcACgp6JhsBAJEDAAcACgp6JhsBAJEDAAAA.Huhdean:BAABNQAECn8hAAMQAAgKDCQMHACqAgAQAAcKsiMMHACqAgAPAAQKzyF1hQALAQAAAA==.Hulxamus:BAAANQAECgYICwAAAA==.Hunterramen:BAAANQADCgEJAQAAAA==.Hunterryan:BAAANQAECggIBQAAAA==.Hunterz:BAAANQAECgQICQAAAA==.',
['Hé']='Héåthcliff:BAACNQAFFH8NAAMTAAUKWRifCABDAQATAAUKWRifCABDAQAYAAEKqA2vEQA9AAA1AAQKf1cAAxgACgooI9QEAGcDABgACgotIdQEAGcDABMACgrqIIMlAMECAAAA.',
Ic='Icyblaze:BAAANQAECggIEgAAAA==.',
Id='Idareu:BAABNQAECn8bAAINAAgKaQXrhwC0AAANAAgKaQXrhwC0AAAAAA==.',
If='Ifstar:BAAANQAECgMIBAAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICgAMAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQAECgUIBgAAAA==.Issalis:BAAANQADCgYIBgAAAA==.',
It='Itheusvalles:BAAANQAECgEIAgAAAA==.Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgcIEAAAAA==.',
Iz='Izonie:BAABNQAECn8aAAMfAAkKAxS6GQDOAQAfAAkKAxS6GQDOAQAFAAQK5gy/HgCCAAABNQAFFAUIDgALAFsVAA==.',
Ja='Jaaric:BAAANQAECgUICAAAAA==.Jaimerrek:BAABNQAECn8ZAAIcAAkKCg30lQBmAQAcAAkKCg30lQBmAQAAAA==.Jainalynn:BAAANQAECgQIBAAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAABNQAECn9KAAMDAAoK4hLWHwDhAQADAAkKKhHWHwDhAQANAAgKZAS2UADJAAAAAA==.',
Jd='Jdarkside:BAABNQAECn8XAAIFAAcK/AauGgCqAAAFAAcK/AauGgCqAAAAAA==.',
Je='Jebediahmoon:BAAANQAECggIEAABNQAECgkJcwAbAGQbAA==.Jenzil:BAAANQAECggICQAAAA==.Jenzilus:BAAANQAECgcIAgABNQAECggICQAMAAAAAA==.Jeremmiah:BAAANQADCgcIEwAAAA==.',
Jh='Jhacobo:BAABNQAECn8sAAINAAoKcxfwMQBTAgANAAoKcxfwMQBTAgAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jonnyrage:BAAANQAECgIIAgAAAA==.Jorkinit:BAABNQAECn8hAAIcAAoKfxSl3wDJAQAcAAoKfxSl3wDJAQAAAA==.',
Jr='Jragon:BAABNQAECn8jAAIaAAgKbQoFlwCtAQAaAAgKbQoFlwCtAQAAAA==.',
Ju='Judis:BAAANQABCgYICwAAAA==.Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAABNQAECn8iAAIcAAoKDR0lZgCyAgAcAAoKDR0lZgCyAgAAAA==.Junipur:BAAANQAECgMICQAAAA==.Justinna:BAAANQADCgIIAgAAAA==.',
Jx='Jxxy:BAACNQAFFH8RAAMGAAUKYRsAFQAXAQAGAAQKYRsAFQAXAQAJAAQKvhXMEwCeAAA1AAQKfyYAAwYACgrRIDdQABgCAAYACgpQIDdQABgCAAkAAwrvGEhAAI8AAAE1AAUUBQoRAAYAYRsA.',
['Jú']='Júnjúnwälä:BAABNQAECn8lAAIDAAoKciQHDgDwAgADAAoKciQHDgDwAgAAAA==.',
Ka='Kalories:BAAANQAECgUICwAAAA==.Kalvoid:BAAANQAECgQIBAABNQAECgUICwAMAAAAAA==.Kandance:BAAANQAECggIEwABNQAFFAIIAgAMAAAAAA==.Karlmagnus:BAAANQAECgEIAQAAAA==.',
Ke='Kelvintwo:BAAANQADCgQIAwAAAA==.',
Ki='Kimbopable:BAAANQAECgUIBQABNQAECgkJcwAbAGQbAA==.Kitkatcate:BAAANQADCgEIAQAAAA==.Kittyÿ:BAAANQAECgYIDwAAAA==.',
Kn='Knurl:BAAANQADCgMIAwAAAA==.',
Ko='Korak:BAAANQADCgUIBQABNQADCgYIBgAMAAAAAA==.Korgh:BAAANQAECgEIAQAAAA==.Kosari:BAAANQAECgUIBgAAAA==.',
Kr='Krystall:BAABNQAECn8oAAIiAAoKug/NBwAbAgAiAAoKug/NBwAbAgAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAABNQAECn87AAMIAAoK7h/zEgDEAgAIAAoK7h/zEgDEAgAlAAIKjQrINgBLAAAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQAECgUIBgABNQAECgUICwAMAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgUICwAMAAAAAA==.',
['Kì']='Kìngknìghts:BAABNQAECn8hAAMQAAgKYhCBOQCjAQAQAAgKVQ+BOQCjAQAPAAQKYA/iUwCoAAAAAA==.',
La='Lalphas:BAABNQAECn81AAMaAAoKRg/CZQApAgAaAAoKRg/CZQApAgAhAAEKxgONhAAmAAAAAA==.Lanthos:BAABNQAECn9TAAIfAAoKACEYBwDiAgAfAAoKACEYBwDiAgAAAA==.Lapulapu:BAAANQADCgYIBgAAAA==.Larthal:BAAANQAECgcICwAAAA==.Latinpapi:BAABNQAECn8qAAMTAAoKVxRydABFAgATAAoKVxRydABFAgAYAAEKAAB5aQBAAAAAAA==.Lawlita:BAAANQAECgEIAQAAAA==.',
Le='Leemers:BAAANQADCgEIAQAAAA==.Leemiez:BAAANQADCgcIDgAAAA==.Leyära:BAAANQAECgYIDQAAAA==.',
Li='Lielys:BAAANQAECgIIAwABNQAECgUIFQAJAPETAA==.Lilina:BAABNQAECn8nAAMFAAgKvhjACwAQAgAFAAgKvhjACwAQAgAmAAEK9wAWjQASAAAAAA==.Liljaejae:BAAANQADCgEIAQAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Loneorc:BAAANQAECgEIAQAAAA==.Lonweh:BAAANQAECgMICAAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgUICwABNQAECggIGwAGAJcNAA==.',
Lu='Lucith:BAABNQAECn82AAIQAAoKFiJJBgB+AwAQAAoKFiJJBgB+AwAAAA==.Luckie:BAAANQABCgQIBwABNQAFFAcIEAAXAIUOAA==.Lulafairy:BAAANQAECgEJAgAAAA==.Lumador:BAAANQAECgQICgABNQAECgcIIAASAIQUAA==.Lunatick:BAABNQAECn9AAAQQAAoKgxBuMwDCAQAQAAoKuQ1uMwDCAQAbAAMKzRuphwDgAAAPAAUK6wMSpwCqAAAAAA==.Lunawa:BAACNQAFFH8OAAIcAAYK2hzDGQCsAQAcAAYK2hzDGQCsAQA1AAQKf3YAAxwACgp3JuABAHoDABwACgp3JuABAHoDABUAAwpLETMtAJQAAAAA.Lustbót:BAABNQAECn8bAAIcAAkKGweA6AC5AQAcAAkKGweA6AC5AQAAAA==.Luvnrdjr:BAAANQADCgYIBgAAAA==.',
Ly='Lynnai:BAAANQAECgUIBQABNQAECgUIBgAMAAAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAACNQAFFH8XAAImAAcKpRwOBwDPAQAmAAcKpRwOBwDPAQA1AAQKf0gAAiYACgr0Jf4DAEkDACYACgr0Jf4DAEkDAAAA.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lí']='Líllith:BAAANQAECgIIAgAAAA==.',
['Lô']='Lôuku:BAABNQAECn86AAIaAAoKyxlCQwCIAgAaAAoKyxlCQwCIAgAAAA==.',
Ma='Maahn:BAAANQADCgcICAAAAA==.Macalob:BAAANQAECgQICAAAAA==.Madallar:BAABNQAECn8ZAAIHAAkKIxB+rQCrAQAHAAkKIxB+rQCrAQAAAA==.Magdagni:BAABNQAECn8aAAIeAAgKHBDqHACVAQAeAAgKHBDqHACVAQAAAA==.Mageji:BAACNQAFFH8SAAIcAAYKVSLYDQB3AQAcAAYKVSLYDQB3AQA1AAQKf0oAAxwACgokJpQOABIDABwACgokJpQOABIDABUAAQqMIpUuAGQAAAAA.Magepies:BAAANQAECgQIBgABNQAECgQICQAMAAAAAA==.Magerella:BAAANQAECgMIAwAAAA==.Magicfurry:BAAANQAECgUICgABNQAECgoKRQARACsZAA==.Mainveinz:BAABNQAFFH8LAAIbAAYK3wAUHQCqAAAbAAYK3wAUHQCqAAAAAA==.Malicelx:BAAANQAECgIIAgABNQAECggIEwAMAAAAAA==.Mallgoth:BAABNQAECn8VAAIGAAYK9gVX+gAPAQAGAAYK9gVX+gAPAQAAAA==.Manohar:BAABNQAECn8wAAMKAAoKkh0tKwC2AgAKAAoKkh0tKwC2AgALAAcKzw7MggCeAQAAAA==.Mardtard:BAABNQAECn8fAAMGAAkKUR1wNwBcAgAGAAkKUR1wNwBcAgAJAAMKigksZQCWAAABNQAECgUICAAMAAAAAA==.Marximilian:BAAANQAECgMIAwAAAA==.Maryola:BAAANQAECggIDwABNQAECgoKKAAiALoPAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIJAwABNQAFFAYICwAJABMSAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQAECgEIAQAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Meewcow:BAAANQADCgcIBwAAAA==.Megamango:BAABNQAECn8ZAAIHAAkK4xSuVQDrAQAHAAkK4xSuVQDrAQABNQAFFAQIDgAcANAhAA==.Mehiel:BAAANQAECgcIDQAAAA==.Meive:BAAANQADCgMIAwAAAA==.Menime:BAAANQADCgYIBgAAAA==.Meraxes:BAAANQAECgEIAQAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Merkén:BAABNQAECn8YAAInAAkK7BaWBwAhAgAnAAkK7BaWBwAhAgAAAA==.Metaloclypse:BAAANQADCgcIDgAAAA==.Meteas:BAAANQAECggIDAAAAA==.Mezaryn:BAABNQAECn8cAAITAAoKCwmi+QDeAAATAAoKCwmi+QDeAAABNQAECgoKNAADAGEKAA==.Mezgrim:BAAANQAECggIAgABNQAECgoKNAADAGEKAA==.Mezzoo:BAABNQAECn80AAIDAAoKYQr7RwD0AAADAAoKYQr7RwD0AAAAAA==.',
Mi='Midger:BAAANQADCgUICAAAAA==.Mikitaju:BAAANQAECgEIAQABNQAECgoKFwAFALoUAA==.Millic:BAABNQAECn84AAMoAAoKdhZNAwA8AgAoAAoKdhZNAwA8AgASAAUK1AvdMgDhAAAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEJAQAAAA==.Mitzrael:BAAANQADCgYICAAAAA==.',
Mo='Mongolious:BAAANQABCgUIBQAAAA==.Moozx:BAAANQAECgEIAQAAAA==.Mosfeat:BAAANQADCggICAABNQAECgkJIwAeAH4aAA==.',
Mu='Muckdile:BAAANQAECgQIBQAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Murrll:BAAANQAECgQIBQAAAA==.Mux:BAAANQAECgEIAgAAAA==.',
Na='Narayeda:BAABNQAECn8vAAImAAkK0QgpPQAvAQAmAAkK0QgpPQAvAQAAAA==.Nasuadia:BAAANQADCggIIQABNQAECgoKOAAQACodAA==.',
Ne='Necrolysis:BAAANQAECgYICwAAAA==.Necromansorz:BAAANQAECggICAAAAA==.Nekkash:BAAANQAECgYICgAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.Newwt:BAAANQAECggIDwAAAA==.Neytiri:BAAANQABCgQIBQAAAA==.Nezelle:BAABNQAECn8fAAIkAAkKWQ/3HAAaAQAkAAkKWQ/3HAAaAQABNQAECgoKSAAEADMaAA==.',
Ni='Nimou:BAAANQAECgQIBwAAAA==.',
No='Nomaa:BAAANQADCgQIBAAAAA==.Noraice:BAAANQADCggICAAAAA==.Noris:BAABNQAECn8YAAMGAAkK8xBhmwBhAQAGAAgKJxNhmwBhAQAJAAIKJQNEgABEAAAAAA==.Norros:BAAANQAECgIIBAAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgQIEAAAAA==.Nuvostaph:BAABNQAECn8tAAIZAAoKaSHgAwDpAgAZAAoKaSHgAwDpAgAAAA==.',
Od='Oddithy:BAAANQAECgEIAQAAAA==.Odecias:BAAANQAECgcIBgAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Oh='Ohiya:BAAANQABCgIIAgAAAA==.Ohiyaa:BAAANQADCgQIBAAAAA==.',
Or='Orcboken:BAAANQAECgMIBAAAAA==.Orezn:BAAANQAECgQIDAAAAA==.',
Os='Oshx:BAAANQADCgEIAQAAAA==.',
Pa='Pabby:BAAANQAECgEIAQAAAA==.Painting:BAAANQAECgEIAwABNQAECggIJAAmAC8gAA==.Pallypusher:BAAANQADCgQICAAAAA==.Papiace:BAAANQAECgYIEgABNQAECgoKYgAFAPUfAA==.Pato:BAABNQAECn8UAAMHAAgKnBxVeQAsAgAHAAgKnBxVeQAsAgAOAAEKBhhlQQA6AAAAAA==.',
Pi='Piesniper:BAAANQABCgIIAgABNQADCgYIDAAMAAAAAA==.Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAACNQAFFH8VAAISAAcK+g2BBAB1AQASAAcK+g2BBAB1AQA1AAQKf04AAhIACgqnIO8GAPQCABIACgqnIO8GAPQCAAAA.',
Po='Popedragon:BAAANQAECgEIAwAAAA==.Poppypoopoo:BAAANQAECgEIAQABNQAECgoKJAAKAL4JAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Prayihealu:BAAANQADCgYIBwAAAA==.Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAABNQAECn8sAAMEAAoKthrjKQBHAgAEAAkK6xXjKQBHAgAWAAkKAxksKwA9AgAAAA==.Profit:BAAANQAECgEIAQAAAA==.Promisa:BAAANQAECggICAAAAA==.Promise:BAAANQAFFAEIAgAAAA==.Prophets:BAAANQAECgEIAQAAAA==.Prucifix:BAAANQAECgEIAgAAAA==.Pryome:BAABNQAECn8YAAIcAAgKmQpL3gDLAQAcAAgKmQpL3gDLAQABNQAECgoKPgALABQYAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQAECgIIAgAAAA==.Punkz:BAAANQADCgYICAABNQAECggIGQAKAPwbAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgYICwAAAA==.',
Py='Pyromortis:BAAANQAECgcIEwABNQAECgoKRQARACsZAA==.Pytorch:BAABNQAECn+OAAIcAAkKWyGpEgD6AgAcAAkKWyGpEgD6AgAAAA==.',
['Pø']='Pø:BAAANQAECgQIBAAAAA==.',
Qu='Queelex:BAAANQAECgcIDQABNQAECggIGQAKAPwbAA==.Quigzz:BAACNQAFFH8NAAIEAAYKkxGgCwA3AQAEAAYKkxGgCwA3AQA1AAQKf0MAAgQACgrZIF8GABsDAAQACgrZIF8GABsDAAAA.Quinnie:BAABNQAECn8ZAAMVAAoKQRk8IADnAAAcAAgKLRa9wQARAQAVAAUKqBQ8IADnAAABNQAFFAIIAgAMAAAAAA==.',
Ra='Raganarok:BAAANQAECgIIAgAAAA==.Rahja:BAAANQAECgYICQAAAA==.Ramms:BAAANQAECggICAAAAA==.Ramss:BAAANQAECggIEAAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECgoKNAAaABQSAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQAECggIDwAAAA==.Rellans:BAAANQAECgYIBgAAAA==.Resa:BAABNQAECn8YAAIKAAgKlwnKdQA7AQAKAAgKlwnKdQA7AQAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ri='Ricasti:BAAANQAECgYICwAAAA==.Ritsu:BAAANQAECgcIDgAAAA==.',
Ro='Robinsonic:BAABNQAECn8sAAIUAAoK8h08CAC0AgAUAAoK8h08CAC0AgAAAA==.Rokenn:BAAANQAECgEIAgAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.Rosetastoned:BAAANQADCgIIAgAAAA==.',
Ru='Rukiè:BAAANQAFFAEIAQAAAA==.Runmyrkr:BAAANQAECgcIEgAAAA==.',
Ry='Ryanbank:BAAANQAECgEIAwAAAA==.',
['Rô']='Rôbert:BAABNQAECn8kAAITAAkKmw7bngB6AQATAAkKmw7bngB6AQAAAA==.',
Sa='Saberyn:BAABNQAECn8pAAInAAkKthT6BwAYAgAnAAkKthT6BwAYAgAAAA==.Sacredsassy:BAAANQAECgUICwABNQAECgoKHwAmAIwIAA==.Saenya:BAABNQAECn8YAAISAAcK7RWWKgDSAQASAAcK7RWWKgDSAQAAAA==.Sageofwampa:BAAANQADCggICgAAAA==.Sahra:BAAANQAECgEIAgAAAA==.Samavanas:BAAANQADCggICwAAAA==.Sassynova:BAAANQADCgYICQABNQAECgoKHwAmAIwIAA==.',
Sc='Schvitz:BAABNQAECn8nAAIGAAoKsRUKbADPAQAGAAoKsRUKbADPAQAAAA==.Scopeftis:BAABNQAECn8fAAIPAAoKEx+MJQCoAgAPAAoKEx+MJQCoAgAAAA==.Scroticus:BAAANQAECgEIAQABNQAECggICQAMAAAAAA==.',
Se='Seano:BAAANQAECgMIBQAAAA==.Seberology:BAABNQAECn8pAAIXAAkKEBJ8SgA+AgAXAAkKEBJ8SgA+AgAAAA==.Segagamecube:BAAANQADCgMIAwAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.Seraphies:BAAANQADCgQIAgAAAA==.Sergal:BAAANQADCggICAABNQAECgMICQAMAAAAAA==.',
Sh='Shaco:BAAANQAECgMIBAAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgQICwABNQAECggIEwAMAAAAAA==.Shamownage:BAABNQAECn8+AAMLAAoKFBiVKgAhAgALAAkKxBmVKgAhAgAKAAoKrRZVQAD9AQAAAA==.Shankyews:BAAANQADCgQJBAAAAA==.Sheev:BAAANQADCgEIAQAAAA==.Shepling:BAACNQAFFH8KAAIbAAUKMg2WEwAhAQAbAAUKMg2WEwAhAQA1AAQKfxQAAhsACAp7FfZGAN0BABsACAp7FfZGAN0BAAAA.Shifterella:BAAANQAECgQICAAAAA==.Shifu:BAACNQAFFH8LAAIIAAQKyBfpCADZAAAIAAQKyBfpCADZAAA1AAQKfx8AAwgACgrzHvAaAGYCAAgACAr+IfAaAGYCACMABwqEFU4VAI8BAAAA.Shivàh:BAACNQAFFH8QAAMPAAYKRBfkBwCbAQAPAAUKOBrkBwCbAQAQAAQKdhHDEADTAAA1AAQKf0IABBAACgpqJQ4CAHMDABAACgpqJQ4CAHMDABsACQrCHEQXAD0CAA8AAwqkIViDABEBAAAA.Shneezleberg:BAABNQAECn81AAMHAAoKNR8dHQDJAgAHAAoKNR8dHQDJAgAnAAQKvgrJIwCVAAAAAA==.Shädowcraft:BAAANQADCgUIBQAAAA==.',
Si='Sildormi:BAAANQAECgEIAgAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAABNQAECn8/AAIDAAoKshJBFgBSAgADAAoKshJBFgBSAgAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Skiddlywinks:BAAANQAECgMIAwABNQAECgoKFwAFALoUAA==.Sko:BAABNQAECn8fAAIHAAkKPRkKVwCGAgAHAAkKPRkKVwCGAgAAAA==.Skyscreamer:BAAANQAECggICAAAAA==.Skár:BAAANQADCggICwAAAA==.',
Sl='Sladak:BAAANQAECgIIAgAAAA==.Slimjimm:BAAANQAECgUIBwABNQAECgoKGQAcADQeAA==.Slutdraggin:BAAANQAECgEIAQAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakyky:BAAANQADCggIEgAAAA==.Sneakymoomoo:BAAANQADCgYJBgABNQAECgoKRQARACsZAA==.Snipagooly:BAAANQADCgcIBwAAAA==.Snowyrain:BAAANQAECgUICwAAAA==.',
So='Sojourner:BAABNQAECn8UAAMLAAcKJhErgwCdAQALAAYK/Q8rgwCdAQAKAAcK0BBzhgB6AQABNQAECgoKJAAXALEaAA==.Solanum:BAAANQADCgQIBAABNQAECgQIBAAMAAAAAA==.Solkar:BAAANQADCgcJCwAAAA==.Solo:BAACNQAFFH8IAAITAAQKKQSMHACgAAATAAQKKQSMHACgAAA1AAQKfzwAAhMACgpZHm8yAIsCABMACgpZHm8yAIsCAAAA.Soupsandwich:BAAANQAECgMIBQAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
Sp='Spartacùs:BAAANQADCgEIAQABNQAECgUICwAMAAAAAA==.',
St='Stagg:BAABNQAECn80AAIcAAoKRBdjnABIAgAcAAoKRBdjnABIAgAAAA==.Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQAECgEIAQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.Stkk:BAAANQAECggICQAAAA==.Stonedkritz:BAAANQABCgQIAwAAAA==.',
Su='Sunarii:BAABNQAECn8cAAISAAkKEBZEIQAtAgASAAkKEBZEIQAtAgAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.Superbroke:BAAANQAECgEIAQAAAA==.Superpoor:BAAANQAECgEIAwAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
['Sà']='Sàviorself:BAAANQAECgIIBgAAAA==.',
['Sý']='Sýlvanàs:BAAANQAECgYIBgAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAABNQAECn8yAAIkAAoKawumEQDOAQAkAAoKawumEQDOAQAAAA==.Taldor:BAAANQAECgEIAQAAAA==.Talwayn:BAAANQADCgUIDwABNQAECgoKFwAFALoUAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQAECgIIAgAAAA==.Taurtellini:BAAANQAECgQICAAAAA==.Tazoo:BAABNQAECn8hAAMeAAkKDgOPIgAzAQAeAAkKDgOPIgAzAQAKAAEKygi4KQEkAAAAAA==.',
Te='Teamfluffer:BAAANQAECgEIAQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Tehzew:BAAANQAECgEIAQAAAA==.Tehzoo:BAAANQADCgIIAgAAAA==.Tehzuurmx:BAAANQADCggIDAAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQAECgEIAQAAAA==.Terebitha:BAAANQABCgMIAgAAAA==.Teruulos:BAAANQAECgUIDgAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAABNQAECn8sAAIRAAoKkh3VNACUAgARAAoKkh3VNACUAgAAAA==.Thadiusx:BAAANQABCgUIBQAAAA==.Tharon:BAABNQAECn8kAAIGAAoKiBUeZgBIAgAGAAoKiBUeZgBIAgAAAA==.Thebigboom:BAACNQAFFH8HAAIUAAIKxgxRBwBtAAAUAAIKxgxRBwBtAAA1AAQKf0EAAhQACgpxHiIKAIwCABQACgpxHiIKAIwCAAAA.Thecarter:BAAANQAECgIIAgAAAA==.Theghoulest:BAAANQAECggIEwAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.Threnody:BAABNQAECn8pAAMJAAcKXQ4tNwCVAQAJAAcKcQ0tNwCVAQAGAAIKDBMtNAGAAAAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgUIBQAMAAAAAA==.Tichemort:BAAANQAECgUIBQAAAA==.Tigerchimon:BAAANQADCgUIBQABNQAECgoKPgALABQYAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Tobiramaa:BAAANQAECgEIAwAAAA==.Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAACNQAFFH8KAAMgAAMKWA2/AACPAAAgAAMKWA2/AACPAAAcAAIK5AOaUACBAAA1AAQKf1YAAyAACgq3IaYAAO0CACAACgq3IaYAAO0CABwABAprCgKQAacAAAAA.',
Tr='Trapscallion:BAAANQAECgQIEAAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Tratraz:BAAANQAECggICwAAAA==.Treeknight:BAABNQAECn8fAAIPAAgKOBRISQDxAQAPAAgKOBRISQDxAQAAAA==.Treelimbs:BAAANQAECgcIDwAAAA==.Treemoo:BAAANQAECgEIAQABNQAECgoKRQARACsZAA==.Tridity:BAAANQAECgYIEQAAAA==.Trollolollz:BAAANQAECgIIBAAAAA==.',
Ts='Tsuuna:BAABNQAECn9DAAQHAAoK9CLxHwC6AgAHAAoKcSLxHwC6AgAnAAEK8yLxJQBmAAAOAAEKAABxPgBIAAAAAA==.',
Tu='Turböman:BAAANQAECgEIAgAAAA==.Turtleqt:BAAANQABCgEIAQAAAA==.Turtleqtx:BAAANQAECgQIBAAAAA==.',
Tw='Twohalfs:BAAANQADCgMIAwAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQAECgIIBAAMAAAAAA==.Tylandon:BAAANQAECgYICgAAAA==.Tyralthas:BAAANQADCgQIAwAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgIJBAAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Un='Unavaluable:BAAANQAECgcICAAAAA==.Ungodlyy:BAABNQAECn8aAAMaAAkK7AUCmwAOAQAaAAkK7AUCmwAOAQAhAAIKDgKVagBMAAAAAA==.Untöuchable:BAABNQAECn9UAAMTAAoKDCRSDgAvAwATAAoKDCRSDgAvAwAXAAIKIwjz5gA7AAAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Va='Vanthelos:BAAANQADCgQIBQAAAA==.',
Ve='Velachlan:BAABNQAECn8XAAMRAAYKox4UXgAHAgARAAYKox4UXgAHAgAoAAEKxw9LKQAxAAAAAA==.Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAABNQAECn9IAAQEAAoKMxrGLwAqAgApAAkKyhebBwA3AgAEAAkKThjGLwAqAgAWAAMK9RLXfQC8AAAAAA==.Verxl:BAABNQAECn8tAAIcAAgKHBhDdgCuAQAcAAgKHBhDdgCuAQAAAA==.Verypoor:BAAANQAECgMIBQAAAA==.',
Vi='Vihn:BAAANQADCgYIBgAAAA==.',
Vo='Voidnyou:BAAANQADCgQICAAAAA==.Volumes:BAAANQAECgUICwAAAA==.Volund:BAABNQAECn9DAAIeAAoKWQhaGwCuAQAeAAoKWQhaGwCuAQAAAA==.',
Vr='Vrixz:BAAANQAECgEIAQAAAA==.',
Vy='Vynsong:BAABNQAECn8mAAIXAAkKMiBRIQDoAgAXAAkKMiBRIQDoAgAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBQAMAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFgAAAA==.Watchmebløck:BAAANQAECgQIBAAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBwAAAA==.Wetmonk:BAAANQAECgcIDQAAAA==.',
Wh='Whoyerdaddy:BAAANQAECgQICwAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Wiggletang:BAAANQAECgEIAQAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAABNQAECn82AAMKAAoKJBJ3WwD9AQAKAAoKJBJ3WwD9AQALAAgKeBEthwDpAAAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.Wix:BAAANQAECgEIAgAAAA==.',
Wo='Wombatman:BAAANQAECgYIDwAAAA==.Wong:BAAANQAECgUIBgAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCggICAAAAA==.',
Xo='Xoron:BAAANQAECgQIBAAAAA==.',
Xu='Xugos:BAABNQAECn8fAAIaAAoKGRgbZgAoAgAaAAoKGRgbZgAoAgAAAA==.',
Xz='Xzeena:BAAANQADCgEIAQAAAA==.',
Ya='Yatagarasu:BAAANQAECggIAgAAAA==.',
Ye='Yenafer:BAAANQADCggICAAAAA==.',
Yo='Yochill:BAAANQAECgIIAgABNQAECgYICwAMAAAAAA==.Yolokin:BAAANQADCgcIGAAAAA==.Yooper:BAAANQAECgEIAQAAAA==.Yota:BAAANQAECgIIAwAAAA==.',
Yr='Yrgg:BAAANQAECgYIEwAAAA==.',
Yt='Ytgamezoned:BAAANQADCgQIBAAAAA==.',
Yu='Yuna:BAAANQAECgEIBAAAAA==.',
Za='Zadanthra:BAABNQAECn8XAAIFAAoKuhR0DwA4AQAFAAoKuhR0DwA4AQAAAA==.Zalektra:BAAANQADCgQIBAAAAA==.Zapadin:BAABNQAECn8tAAITAAoKZhIlggAkAgATAAoKZhIlggAkAgAAAA==.Zaphodè:BAAANQAECgUICQAAAA==.',
Ze='Zeenie:BAAANQAFFAIIBAAAAA==.Zeljusticar:BAAANQADCgEIAgAAAA==.Zephian:BAAANQAECgMIBAAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAABNQAECn8gAAQoAAgKAAubCwCFAQAoAAgKAAubCwCFAQARAAYK2wN8sQACAQASAAUKNgWpUQDKAAAAAA==.Zotoperen:BAABNQAECn8xAAMjAAoK/iBkAwBdAwAjAAoK/iBkAwBdAwAIAAMKFhHoUgClAAAAAA==.',
Zy='Zylergy:BAABNQAECn8cAAITAAoKPgl23wBcAQATAAoKPgl23wBcAQAAAA==.',
['Zì']='Zìfu:BAAANQADCggICQAAAA==.',
['Àv']='Àvicant:BAAANQAECgUJCAABNQAFFAQICAAGAFMiAA==.',
['Áp']='Ápex:BAAANQAECgMIAwAAAA==.',
['Än']='Ändo:BAABNQAECn8VAAIGAAUK4Bug1wBRAQAGAAUK4Bug1wBRAQAAAA==.',
['Äy']='Äy:BAAANQADCgUIBwAAAA==.',
['Çy']='Çyrin:BAABNQAECn8wAAMXAAkKsBMXSgA/AgAXAAkKsBMXSgA/AgATAAEK5QhHpwEzAAAAAA==.',
['Çø']='Çørpsë:BAAANQABCgIJAgAAAA==.',
['Ëu']='Ëuphoria:BAAANQADCgQIBAAAAA==.',
['Ün']='Üna:BAAANQADCggIEAAAAA==.',
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
