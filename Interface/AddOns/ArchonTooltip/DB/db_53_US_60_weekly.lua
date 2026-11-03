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

local lookup = {'Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','Rogue-Subtlety','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','Paladin-Holy','Unknown-Unknown','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Rogue-Assassination','Paladin-Protection','Druid-Feral','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Shaman-Enhancement','DemonHunter-Devourer','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Evoker-Preservation','Monk-Mistweaver','DemonHunter-Havoc','Mage-Frost','Warrior-Fury','Priest-Discipline','Mage-Fire','Rogue-Outlaw',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abssorath:BAAANQADCgYICQAAAA==.',
Ae='Aerouant:BAABNQAECn8/AAMBAAoK9RfVBQArAgACAAkKeReXBgBWAgABAAkKtBXVBQArAgAAAA==.',
Ai='Aidix:BAAANQAECgEIAQAAAA==.Aimassist:BAAANQAECgQIBAAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAABNQAECn80AAIDAAoK+R15DwDfAgADAAoK+R15DwDfAgAAAA==.Alexstanna:BAAANQAECgUIDwAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.Alwaysbroke:BAAANQAECgYICwAAAA==.',
An='Andrena:BAABNQAECn8UAAIEAAgKQxJ2PADGAQAEAAgKQxJ2PADGAQAAAA==.Andycat:BAAANQAECgEIAQAAAA==.Annarchy:BAAANQADCgQIBAAAAA==.Antagony:BAAANQAECgUIBgAAAA==.Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAABNQAECn8wAAIFAAoKQBTJCQBEAgAFAAoKQBTJCQBEAgAAAA==.Anthross:BAABNQAECn8qAAIGAAoKHw9/hgD+AQAGAAoKHw9/hgD+AQAAAA==.',
Ap='Apollovon:BAABNQAECn8pAAIHAAkKeyGkLQAGAwAHAAkKeyGkLQAGAwAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanemage:BAAANQADCgYIBwAAAA==.Arcanenug:BAAANQADCgQJBAAAAA==.Arcbnonez:BAAANQAECgQIBAAAAA==.Arguxx:BAABNQAECn8YAAIIAAoK2hQfMgAkAgAIAAoK2hQfMgAkAgABNQAECgEIAQAJAAAAAA==.Armiggy:BAABNQAECn9JAAIKAAoKvBMNEgANAgAKAAoKvBMNEgANAgAAAA==.Aro:BAACNQAFFH8TAAMLAAcKcCALCgCiAQALAAYKYB8LCgCiAQAGAAIK4huxIACwAAA1AAQKfy4AAwsACgqwJBIUAMkBAAYABgrQI6OZANQBAAsACApRIxIUAMkBAAAA.Arrowraen:BAABNQAECn8rAAIGAAkK/SMfBwCkAwAGAAkK/SMfBwCkAwAAAA==.',
As='Asavera:BAAANQAECgUICAAAAA==.Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgYJBgAAAA==.Asgeden:BAAANQAECgEIAQAAAA==.Asträl:BAAANQAECgEIAgAAAA==.',
Au='Audomere:BAABNQAECn8rAAMMAAoKpwxUSwCzAQAMAAoKpwxUSwCzAQANAAIKlgFXLQE7AAAAAA==.Auurwarr:BAAANQAECgUIBQAAAA==.',
Av='Avawrath:BAAANQAECggIEQAAAA==.Avelm:BAAANQAECggIAwAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgoKMQAFAB0fAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Balanji:BAAANQADCgUIBQABNQAECgkJFgAFAH8UAA==.Ballstench:BAAANQAECgUIBAAAAA==.Barbåtos:BAAANQAECgMIBQAAAA==.Baskthyr:BAAANQADCgQIBAAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAABNQAECn8XAAIOAAgKSBQ1OQAmAgAOAAgKSBQ1OQAmAgABNQADCgUIBQAJAAAAAA==.Bearbomblolz:BAAANQADCgQIBQABNQAECgkJFgAFAH8UAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQADCgQICAAAAA==.Beastbane:BAAANQAECggIEwAAAA==.Beastly:BAAANQAECgYIDAAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAABNQAECn83AAMHAAoKuhiyRQC4AgAHAAoKuhiyRQC4AgAPAAgKVhTyFQDJAQAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAABNQAECn9lAAMQAAgKrRc6QgATAgAQAAgKoBc6QgATAgARAAgKxA9sPABuAQAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgAJAAAAAA==.Bewslee:BAAANQAECgEIAwABNQAECgUIBQAJAAAAAA==.Bexx:BAAANQADCggJGQAAAA==.',
Bi='Biblehumping:BAABNQAECn89AAMSAAoKSxeZSgBFAgASAAoKSxeZSgBFAgATAAYKEQkMQgAhAQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgcIDQAJAAAAAA==.Bigbonks:BAAANQAECgQIBgAAAA==.Bigdumb:BAAANQAECgcIBgAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.Billclintun:BAAANQADCgcIEQAAAA==.',
Bl='Blackplague:BAAANQAECgEIAQAAAA==.Blaezèr:BAAANQAECgUIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQAECggICwAAAA==.Blueshamoo:BAAANQAECgEJAQAAAA==.Blupl:BAAANQABCgYIBgAAAA==.Blãezer:BAAANQAECgYICQAAAA==.',
Bo='Bonex:BAAANQAECgEIAgAAAA==.Boomshroom:BAAANQAECgMIBAABNQAECgoKNwAKAM8fAA==.Bootsie:BAAANQADCggICAAAAA==.',
Br='Brewser:BAAANQAECgEIAQAAAA==.Brewtoe:BAABNQAECn8lAAIKAAgKIRXtFQDWAQAKAAgKIRXtFQDWAQAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Broshunteri:BAAANQAECgEIAQAAAA==.Bruegard:BAAANQADCgIIAgAAAA==.Bruneau:BAAANQABCgUIBQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAcIFwALAPoaAA==.',
Bu='Bubblemehard:BAABNQAECn8cAAIUAAgKMhibewAzAgAUAAgKMhibewAzAgAAAA==.Bushky:BAAANQAECgMIBwAAAA==.',
By='Byahnbreath:BAACNQAFFH8FAAIRAAIK7waxGAB7AAARAAIK7waxGAB7AAA1AAQKfygAAhEACgo0G8kdACkCABEACgo0G8kdACkCAAAA.',
Ca='Caesardr:BAABNQAECn85AAIVAAoKVhy1CACLAgAVAAoKVhy1CACLAgAAAA==.Cakeiko:BAAANQAECgQIBQAAAA==.Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Carolaine:BAAANQADCgQIAgAAAA==.Casmiralda:BAAANQABCgUIBQAAAA==.Castielx:BAABNQAECn8ZAAIWAAcKthIcQQDHAQAWAAcKthIcQQDHAQAAAA==.Catnips:BAAANQAECgUICAABNQAECgoKPQASAEsXAA==.',
Ce='Celestraza:BAAANQAECgcICQAAAA==.Celirra:BAABNQAECn80AAIQAAoKDyFvDwA7AwAQAAoKDyFvDwA7AwAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.Cenzo:BAAANQAECgcICQAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAABNQAECn8uAAIHAAoKxQsghABGAQAHAAoKxQsghABGAQAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAABNQAECn8WAAMWAAgKKxyANwD6AQAWAAcKKxyANwD6AQAEAAEKAAA3TwBDAAAAAA==.Chokma:BAABNQAECn8nAAINAAkKwRSKZgDtAQANAAkKwRSKZgDtAQAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAABNQAECn8eAAMIAAkKzA72RwDBAQAIAAkKzA72RwDBAQAXAAEKlAQGfgAfAAAAAA==.',
Ci='Cinnaa:BAAANQAECgUICQAAAA==.',
Cl='Clawdog:BAAANQADCgIIAgABNQAECgIIBAAJAAAAAQ==.Clawwz:BAAANQAECgMIAwAAAA==.Cleisthenes:BAAANQAECgEIAQABNQAECgUIBwAJAAAAAA==.Clors:BAABNQAECn8qAAQDAAkKPRwrEwBMAgADAAkKPRwrEwBMAgAOAAIKnAnOagBcAAAYAAIKOg3VOwA0AAAAAA==.',
Co='Compressed:BAAANQAECgEIAQAAAA==.Conflux:BAAANQADCggIFAAAAA==.Coopada:BAAANQABCgEIAQAAAA==.Cowvibez:BAAANQADCgUICgAAAA==.',
Cr='Crager:BAABNQAECn8VAAIHAAgKTwiMkAAqAQAHAAgKTwiMkAAqAQAAAA==.Crawlah:BAAANQADCggIDgAAAA==.Crazegideon:BAAANQABCgIIAgAAAA==.Crazespawnz:BAAANQABCgIIAgAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIEQAAAA==.',
Cy='Cyberfairy:BAAANQAECgEJAQAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQAECgEIAQAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgcICAAAAA==.Dalìnar:BAAANQAECgYIDAAAAA==.Damadafacker:BAABNQAECn8nAAIHAAoK0RYdSgDxAQAHAAoK0RYdSgDxAQAAAA==.Darfine:BAAANQAECgMIAwAAAA==.Darkclôud:BAAANQAECgQIBAAAAA==.Darkkatriden:BAAANQADCgYIBgABNQAECgcIGAAZAJgJAA==.Darklia:BAABNQAECn8YAAIZAAcKmAlgpADXAAAZAAcKmAlgpADXAAAAAA==.Darthjae:BAABNQAECn9hAAMaAAkKZBsKFwAmAgAaAAkKZBsKFwAmAgARAAEKAABQvgAfAAAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAABNQAECn8qAAIbAAoKZhrUAwDBAgAbAAoKZhrUAwDBAgAAAA==.Davina:BAAANQADCgcIBwABNQAFFAQIBwAUAAMOAA==.Daïn:BAAANQAECgcICgAAAA==.',
De='Deadestmoonb:BAAANQADCgIIBAAAAA==.Deathalimon:BAABNQAECn88AAQaAAkKgxvEFQA0AgAaAAkK0hnEFQA0AgAQAAgKnRTUUgDHAQARAAEKTBBerQA0AAABNQAECgoKNQAMAOoVAA==.Deathvoid:BAAANQADCgQIAQAAAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQAECgEIAQAAAA==.Demonarian:BAAANQAECgcICQABNQAECgoKNQAMAOoVAA==.Demonicnut:BAAANQAECgMIAwABNQAECgkJJwANAMEUAA==.Demonpotato:BAAANQADCggICAABNQAECgoKSAASACYhAA==.Denardath:BAAANQADCgUIBQAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAABNQAECn8gAAMNAAkKwQyTogBQAQANAAgKiAyTogBQAQAMAAgKMQq1awA+AQAAAA==.Deroc:BAABNQAECn8iAAIUAAoKoAcisQAuAQAUAAoKoAcisQAuAQAAAA==.Desporato:BAAANQAECggIBAAAAA==.Deáthtáxi:BAAANQAECggICAAAAA==.',
Di='Digweeds:BAABNQAECn8XAAIcAAkKrRp7DgD1AQAcAAkKrRp7DgD1AQABNQAFFAEIAQAJAAAAAA==.Dinfarmer:BAAANQAECgUICgAAAA==.Dirtycheese:BAAANQAECgYICwAAAA==.',
Dj='Djgha:BAAANQAECgIIBAAAAA==.',
Dm='Dmptruckdona:BAAANQAECgQIAwAAAA==.Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQAECgEIAwAAAA==.Doombap:BAACNQAFFH8GAAIdAAQK9wWtCAC9AAAdAAQK9wWtCAC9AAA1AAQKfyAAAh0ACgo5EgEUAPMBAB0ACgo5EgEUAPMBAAAA.Dorunter:BAABNQAECn8wAAMLAAoKdRNMMwCzAQALAAcKYBJMMwCzAQAGAAYKyBIssgAJAQAAAA==.Dottíe:BAAANQAECgUIBwABNQAECgoKTwANAOEcAA==.Doubledosage:BAABNQAECn8ZAAIGAAYKAgogwADuAAAGAAYKAgogwADuAAAAAA==.',
Dr='Dragonbnonez:BAAANQAECgQIBAAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Drakujin:BAAANQADCgMIBQAAAA==.Drboomboom:BAABNQAECn8lAAIeAAoK9Qq2hABwAQAeAAoK9Qq2hABwAQAAAA==.Drdoitall:BAAANQAECgYICwAAAA==.Dreadnpain:BAAANQADCgQIBAAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIAwABNQAFFAcIFQARAMEfAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Du='Duukwan:BAABNQAECn8VAAMSAAkK8BmNJgDQAgASAAkK8BmNJgDQAgATAAEKjhENUAA/AAAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.Elysiá:BAAANQADCggICAAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAACNQAFFH8QAAQfAAUKohlxBACaAAAgAAIKfR0iBQCaAAAfAAIKtBdxBACaAAAZAAIK6AHJNAAAAAA1AAQKfzoAAyAACgpUJaoDALYCACAACAp8JaoDALYCAB8AAwqzJFUHADEBAAAA.',
Er='Erayr:BAAANQAECgcIEQABNQAECgkJGQAeAAoNAA==.Ericolson:BAABNQAECn8yAAIHAAoKGxi0MwBIAgAHAAoKGxi0MwBIAgAAAA==.Erze:BAAANQAECgUICQAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evilhealer:BAAANQAECgMIBwAAAA==.Evilmcgyver:BAAANQAECgEIAgAAAA==.Evosolz:BAEBNQAECn8ZAAIHAAkK3ArMbgB8AQAHAAkK3ArMbgB8AQAAAA==.Evé:BAAANQAECgMIAwABNQAECgoKNwAKAM8fAA==.',
Ey='Eyehealu:BAAANQADCgIIAgABNQAECgoKKAAgALoPAA==.',
Ez='Ezzartkal:BAAANQAECgEIAgAAAA==.',
Fa='Faeloria:BAAANQADCggICgAAAA==.Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgkJYQAaAGQbAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgoKMQAhAP4gAA==.Fefra:BAAANQADCgQIBAAAAA==.Felicious:BAABNQAECn8aAAIZAAoKrg/LdQABAgAZAAoKrg/LdQABAgAAAA==.Feralco:BAAANQAECgYIEgAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fixiation:BAAANQAECgEIAQAAAA==.Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Flashdance:BAAANQADCggIFAAAAA==.Fleepo:BAAANQAECgIIAwAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAABNQAECn82AAMiAAoKuw1mHQD3AQAiAAoKuw1mHQD3AQABAAEKAAC7PgAvAAAAAA==.Flyhawk:BAAANQAECgYIBgAAAA==.Flöör:BAAANQADCgUIBQAAAA==.',
Fo='Footloose:BAAANQAECgcIDAABNQAECgkJYQAaAGQbAA==.',
Fu='Fullmetal:BAABNQAECn8XAAIgAAgKaQzvCQBiAQAgAAgKaQzvCQBiAQAAAA==.Funkadelfic:BAAANQAECgYIBwAAAA==.',
['Fè']='Fèngshui:BAAANQADCggIGwAAAA==.',
['Fé']='Fénrír:BAAANQADCggIDwABNQAECgoKMwANAKYfAA==.',
['Fò']='Fòxxy:BAAANQAECgMIAQAAAA==.',
Ga='Galadri:BAABNQAECn8ZAAMMAAgK/BuUQQBaAgAMAAgK/BuUQQBaAgANAAUKCxAXwwAMAQAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIEAAAAA==.Geartryx:BAAANQADCggIDQAAAA==.Geodood:BAAANQAECgYIEAAAAA==.',
Gh='Ghoshshadow:BAAANQAECgEIAQAAAA==.Ghostinz:BAABNQAECn8XAAIHAAcKkQzRjgAtAQAHAAcKkQzRjgAtAQAAAA==.',
Gi='Gimpripper:BAAANQAECgcICQAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggJIAAaAGcaAA==.Globalcold:BAABNQAECn8bAAIHAAgKLBoLdAA4AgAHAAgKLBoLdAA4AgAAAA==.Globb:BAABNQAECn8xAAIHAAgKVxSIlwDhAQAHAAgKVxSIlwDhAQAAAA==.Globius:BAABNQAECn8yAAIUAAoKdhtNSgC2AgAUAAoKdhtNSgC2AgAAAA==.Gloriouscole:BAABNQAECn8UAAIUAAYKBCIhdgBBAgAUAAYKBCIhdgBBAgAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gooly:BAAANQADCgIIAgAAAA==.Goombit:BAAANQADCgEIAQAAAA==.',
Gr='Greekorc:BAAANQABCgYJBwAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Grimby:BAAANQAECggIBQAAAA==.Grimdisney:BAAANQAECgEIAQAAAA==.Groceries:BAAANQADCgMIAwAAAA==.Gromol:BAAANQADCggIHwAAAA==.Grumby:BAAANQAECgIIDAAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQAECgQIBQAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQAECgQIBwAAAA==.Hatebrêêd:BAAANQADCgQIBQAAAA==.Hazhazbot:BAAANQADCgYIBQAAAA==.',
He='Healman:BAAANQADCgcIGQAAAA==.Healpaws:BAAANQADCgUIBQAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgcIDAAAAA==.Heiden:BAAANQADCgYJBgAAAA==.Hel:BAAANQAECgIIAwAAAA==.Hellyas:BAABNQAECn8VAAIUAAYK/QsYAAEfAQAUAAYK/QsYAAEfAQAAAA==.Herbs:BAAANQAECgEIAQABNQAECgoKQwAEAP0ZAA==.Herenorthere:BAABNQAECn8yAAMTAAoKgBr6GgBxAgATAAgKEhz6GgBxAgASAAgKgxs3dQC8AQABNQAFFAUICwAgABsXAA==.Hermippe:BAAANQAECgMIAwAAAA==.Hexstraits:BAACNQAFFH8GAAIaAAIKRBMsIACIAAAaAAIKRBMsIACIAAA1AAQKfycAAhoACgrHIiMQACwDABoACgrHIiMQACwDAAAA.',
Hi='Hia:BAACNQAFFH8UAAIaAAYKyByhCgCtAQAaAAYKyByhCgCtAQA1AAQKf0MABBoACgrGIh4LAFsDABoACgrGIh4LAFsDABAAAQpABzt+ADEAABEAAgpmAZCvAA8AAAAA.Highriskbr:BAAANQAECggICAAAAA==.Hitlist:BAAANQADCgUJBQAAAA==.',
Ho='Holycow:BAAANQAECgIIBAAAAA==.Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBgAAAA==.Hondaimpala:BAAANQAECgQIBgABNQAECgkJYQAaAGQbAA==.Hoofmaster:BAAANQAECgEIAwAAAA==.Hopskotch:BAAANQAECgEIAQAAAA==.Hordenfel:BAAANQADCggIEAAAAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huffy:BAAANQAECggIDwABNQAECgoKSQAHAMElAA==.Huffyy:BAABNQAECn9JAAIHAAoKwSWjAgB5AwAHAAoKwSWjAgB5AwAAAA==.Huhdean:BAABNQAECn8hAAMRAAgKDCQMHACqAgARAAcKsiMMHACqAgAQAAQKzyF1hQALAQAAAA==.Hulxamus:BAAANQAECgYICgAAAA==.Hunterramen:BAAANQADCgEJAQAAAA==.Hunterryan:BAAANQAECggIAwAAAA==.Hunterz:BAAANQAECgQICQAAAA==.',
['Hé']='Héåthcliff:BAACNQAFFH8JAAMUAAQKSRSuEADcAAAUAAQKSRSuEADcAAAXAAEKqA2vEQA9AAA1AAQKf08AAxcACgoaI9QEAGcDABcACgotIdQEAGcDABQACgpyILUuAH0CAAAA.',
Ic='Icyblaze:BAAANQAECggIEAAAAA==.',
Id='Idareu:BAABNQAECn8bAAIOAAgKaQXrhwC0AAAOAAgKaQXrhwC0AAAAAA==.',
If='Ifstar:BAAANQAECgMIBAAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICQAJAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQAECgUIBgAAAA==.Issalis:BAAANQADCgYIBgAAAA==.',
It='Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgcIDwAAAA==.',
Iz='Izonie:BAABNQAECn8UAAMdAAgK3hC2HwBuAQAdAAgK3hC2HwBuAQAFAAQK5gy2GwCFAAABNQAFFAUIDAANAFsVAA==.',
Ja='Jaaric:BAAANQAECgUICAAAAA==.Jackvegas:BAAANQAECgEIAQABNQAECgkJIAANAMEMAA==.Jaimerrek:BAABNQAECn8ZAAIeAAkKCg2WhQBuAQAeAAkKCg2WhQBuAQAAAA==.Jainalynn:BAAANQAECgQIBAAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAABNQAECn9EAAMDAAoK/hGAHADSAQADAAkKLBCAHADSAQAOAAgKSgSoUwCkAAAAAA==.',
Jd='Jdarkside:BAABNQAECn8WAAIFAAYKswaDHwDNAAAFAAYKswaDHwDNAAAAAA==.',
Je='Jebediahmoon:BAAANQAECggIEgABNQAECgkJYQAaAGQbAA==.Jenzil:BAAANQAECggICAAAAA==.Jeremmiah:BAAANQAECgEIAQAAAA==.',
Jh='Jhacobo:BAABNQAECn8sAAIOAAoKcxfwMQBTAgAOAAoKcxfwMQBTAgAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jonnyrage:BAAANQAECgIIAgAAAA==.Jorkinit:BAABNQAECn8hAAIeAAoKfxSl3wDJAQAeAAoKfxSl3wDJAQAAAA==.',
Jr='Jragon:BAABNQAECn8jAAIZAAgKbQoFlwCtAQAZAAgKbQoFlwCtAQAAAA==.',
Ju='Judis:BAAANQABCgYICwAAAA==.Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAABNQAECn8hAAIeAAoKDR0lZgCyAgAeAAoKDR0lZgCyAgAAAA==.Junipur:BAAANQAECgMICQAAAA==.Justinna:BAAANQAECgEIAQAAAA==.',
Jx='Jxxy:BAACNQAFFH8NAAMGAAQKYRsAFQAXAQAGAAQKYRsAFQAXAQALAAIKjxAxHACPAAA1AAQKfyYAAwYACgrRICs/ACECAAYACgpQICs/ACECAAsAAwrvGBw8AIYAAAE1AAUUBAoNAAYAYRsA.',
['Jú']='Júnjúnwälä:BAABNQAECn8iAAIDAAoKCSQHDgDwAgADAAoKCSQHDgDwAgAAAA==.',
Ka='Kalories:BAAANQAECgUICwAAAA==.Kalvoid:BAAANQAECgQIBAABNQAECgUICwAJAAAAAA==.Kandance:BAABNQAECn8UAAIIAAkK0BLHXgBqAQAIAAkK0BLHXgBqAQABNQAFFAIIAgAJAAAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ke='Kelvintwo:BAAANQADCgQIAwAAAA==.',
Ki='Kimbopable:BAAANQAECgUIBQABNQAECgkJYQAaAGQbAA==.Kittyÿ:BAAANQAECgYICwAAAA==.',
Kn='Knurl:BAAANQADCgMIAwAAAA==.',
Ko='Korak:BAAANQADCgUIBQABNQADCgYIBgAJAAAAAA==.Korgh:BAAANQAECgEIAQAAAA==.Kosari:BAAANQAECgUIBgAAAA==.',
Kr='Krystall:BAABNQAECn8oAAIgAAoKug/NBwAbAgAgAAoKug/NBwAbAgAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAABNQAECn83AAMKAAoKzx/zEgDEAgAKAAoKzx/zEgDEAgAjAAIKjQrcMQBQAAAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQAECgUIBgABNQAECgUICwAJAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgUICwAJAAAAAA==.',
['Kì']='Kìngknìghts:BAABNQAECn8aAAMRAAcK6wwOSwArAQARAAcKQQoOSwArAQAQAAQKYA8hTQCrAAAAAA==.',
La='Lalphas:BAABNQAECn81AAMZAAoKRg/CZQApAgAZAAoKRg/CZQApAgAfAAEKxgONhAAmAAAAAA==.Lanthos:BAABNQAECn9MAAIdAAoKACGIBQD0AgAdAAoKACGIBQD0AgAAAA==.Lapulapu:BAAANQADCgYIBgAAAA==.Larthal:BAAANQAECgUICwAAAA==.Latinpapi:BAABNQAECn8qAAMUAAoKVxRydABFAgAUAAoKVxRydABFAgAXAAEKAAB5aQBAAAAAAA==.Lawlita:BAAANQAECgEIAwAAAA==.',
Le='Leemers:BAAANQADCgEIAQAAAA==.Leemiez:BAAANQADCgcIDgAAAA==.Lexìe:BAAANQAECgEIAwAAAA==.Leyära:BAAANQAECgMIBgAAAA==.',
Li='Lielys:BAAANQAECgIIAgABNQAECgUIFQALAPETAA==.Lilina:BAABNQAECn8mAAMFAAgKvhjACwAQAgAFAAgKvhjACwAQAgAkAAEK9wAQgwASAAAAAA==.Liljaejae:BAAANQADCgEIAQAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Lonweh:BAAANQAECgMIBAAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgUICwABNQAECggIGQAGAJcNAA==.',
Lu='Lucith:BAABNQAECn82AAIRAAoKFiJJBgB+AwARAAoKFiJJBgB+AwAAAA==.Luckie:BAAANQABCgQIBwABNQAFFAYIDwAIABEQAA==.Lulafairy:BAAANQAECgEJAQAAAA==.Lumador:BAAANQAECgQIBwABNQAECgcIIAATAIQUAA==.Lunatick:BAABNQAECn84AAQRAAoKNxDqLQC5AQARAAoKbQ3qLQC5AQAaAAMKzRuphwDgAAAQAAUK6wMSpwCqAAAAAA==.Lunawa:BAACNQAFFH8IAAIeAAUKSx3DGQCsAQAeAAUKSx3DGQCsAQA1AAQKf24AAx4ACgp3JiwBAIADAB4ACgp3JiwBAIADACUAAwpLETMtAJQAAAAA.Lustbót:BAABNQAECn8bAAIeAAkKGweA6AC5AQAeAAkKGweA6AC5AQAAAA==.Luvnrdjr:BAAANQADCgYIBgAAAA==.',
Ly='Lynnai:BAAANQAECgUIBQABNQAECgUIBgAJAAAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAACNQAFFH8XAAIkAAcKpRwOBwDPAQAkAAcKpRwOBwDPAQA1AAQKf0IAAiQACgocJc0FAJgDACQACgocJc0FAJgDAAAA.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lí']='Líllith:BAAANQAECgIIAgAAAA==.',
['Lô']='Lôuku:BAABNQAECn84AAIZAAoK3RhCQwCIAgAZAAoK3RhCQwCIAgAAAA==.',
Ma='Maahn:BAAANQADCgcICAAAAA==.Macalob:BAAANQAECgQIBgAAAA==.Madallar:BAABNQAECn8ZAAIHAAkKIxB+rQCrAQAHAAkKIxB+rQCrAQAAAA==.Magdagni:BAABNQAECn8aAAIcAAgKHBDqHACVAQAcAAgKHBDqHACVAQAAAA==.Mageji:BAACNQAFFH8RAAIeAAUKbSPGEgAiAQAeAAUKbSPGEgAiAQA1AAQKf0kAAx4ACgokJmILABsDAB4ACgokJmILABsDACUAAQqMImUpAGYAAAE1AAMKBggGAAkAAAAA.Magepies:BAAANQAECgQIBgABNQAECgQICAAJAAAAAA==.Magerella:BAAANQAECgMIAwAAAA==.Magicfurry:BAAANQAECgUICgABNQAECgoKPQASAEsXAA==.Mainveinz:BAABNQAFFH8LAAIaAAYK3wA6FQCYAAAaAAYK3wA6FQCYAAAAAA==.Malicelx:BAAANQAECgIIAgABNQAECgEIAQAJAAAAAA==.Mallgoth:BAABNQAECn8VAAIGAAYK9gVX+gAPAQAGAAYK9gVX+gAPAQAAAA==.Manohar:BAABNQAECn8wAAMMAAoKkh0tKwC2AgAMAAoKkh0tKwC2AgANAAcKzw7MggCeAQAAAA==.Mardtard:BAABNQAECn8dAAMGAAcKtx9yVAB0AgAGAAcKtx9yVAB0AgALAAMKigksZQCWAAABNQAECgUIBgAJAAAAAA==.Marximilian:BAAANQAECgMIAwAAAA==.Maryola:BAAANQAECgUIBgABNQAECgoKKAAgALoPAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIJAgABNQAFFAYICwALABMSAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQADCgYICQAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Meewcow:BAAANQADCgcIBwAAAA==.Megamango:BAAANQAECgcIEwABNQAFFAQICgAeANAhAA==.Mehiel:BAAANQAECgcIDQAAAA==.Meive:BAAANQADCgMIAwAAAA==.Menime:BAAANQADCgYIBgAAAA==.Meraxes:BAAANQAECgEIAQAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Merkén:BAABNQAECn8YAAImAAkK7BZCBgAoAgAmAAkK7BZCBgAoAgAAAA==.Metaloclypse:BAAANQADCgcIDgAAAA==.Meteas:BAAANQAECggIDwAAAA==.Mezaryn:BAABNQAECn8cAAIUAAoKCwlB6gDQAAAUAAoKCwlB6gDQAAABNQAECgoKMgADAGEKAA==.Mezgrim:BAAANQAECggIAgABNQAECgoKMgADAGEKAA==.Mezzoo:BAABNQAECn8yAAIDAAoKYQr7RwD0AAADAAoKYQr7RwD0AAAAAA==.',
Mi='Midger:BAAANQADCgUICAAAAA==.Mikitaju:BAAANQAECgEIAQABNQAECgkJFgAFAH8UAA==.Millic:BAABNQAECn8xAAMnAAoKvRUrBgAyAgAnAAoKvRUrBgAyAgATAAUK1At0LQDiAAAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minanda:BAAANQAECgEIAQAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEJAQAAAA==.Mitzrael:BAAANQADCgYICAAAAA==.',
Mo='Mongolious:BAAANQAECgEIAgAAAA==.Moozx:BAAANQAECgEIAQAAAA==.Mosfeat:BAAANQADCggICAABNQAECgkJIgAcAH4aAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Murrll:BAAANQAECgQIBQAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAABNQAECn8mAAIkAAkKSQgWPAAPAQAkAAkKSQgWPAAPAQAAAA==.Nasuadia:BAAANQADCggIIQABNQAECgoKNAARAAgdAA==.',
Ne='Necrolysis:BAAANQAECgYIDQAAAA==.Necromansorz:BAAANQAECggICAAAAA==.Nekkash:BAAANQAECgYICgAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Nerftraps:BAAANQAECggIAQAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.Newwt:BAAANQAECggIDQAAAA==.Neytiri:BAAANQABCgQIBQAAAA==.Nezelle:BAABNQAECn8cAAIiAAkKGg5rKQBmAQAiAAkKGg5rKQBmAQABNQAECgoKQwAEAP0ZAA==.',
Ni='Nimou:BAAANQAECgUIBQAAAA==.',
No='Nomaa:BAAANQADCgQIBAAAAA==.Noraice:BAAANQADCggICAAAAA==.Noris:BAABNQAECn8XAAMGAAkK8xBBhQBlAQAGAAgKJxNBhQBlAQALAAIKJQNEgABEAAAAAA==.Norros:BAAANQAECgIIBAAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgQIDAAAAA==.Nuvostaph:BAABNQAECn8rAAIYAAoKWyEeAwDwAgAYAAoKWyEeAwDwAgAAAA==.',
Od='Odecias:BAAANQAECgcIBgAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Oh='Ohiya:BAAANQABCgIIAgAAAA==.Ohiyaa:BAAANQADCgQIBAAAAA==.',
Or='Orcboken:BAAANQAECgMIBAAAAA==.Orezn:BAAANQAECgQICgAAAA==.',
Os='Oshx:BAAANQADCgEIAQAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Painting:BAAANQAECgEIAQABNQAECggIIgAkAGQfAA==.Pallypusher:BAAANQADCgQICAAAAA==.Papiace:BAAANQAECgYIEAABNQAECgoKYAAFAPUfAA==.Pato:BAABNQAECn8UAAMHAAgKnBxVeQAsAgAHAAgKnBxVeQAsAgAPAAEKBhhlQQA6AAAAAA==.',
Pi='Piesniper:BAAANQABCgIIAgABNQADCgYIDAAJAAAAAA==.Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAACNQAFFH8VAAITAAcK+g2GAwCCAQATAAcK+g2GAwCCAQA1AAQKf0UAAhMACgq/HzMHANkCABMACgq/HzMHANkCAAAA.',
Po='Popedragon:BAAANQAECgEIAgAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Prayihealu:BAAANQADCgYIBwAAAA==.Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAABNQAECn8oAAMEAAoKbRo1JQA9AgAEAAkKohU1JQA9AgAWAAkKAxksKwA9AgAAAA==.Promisa:BAAANQAECggICQAAAA==.Promise:BAAANQAFFAEIAQAAAA==.Prophets:BAAANQADCgMIBQAAAA==.Prucifix:BAAANQAECgEIAQAAAA==.Pryome:BAABNQAECn8YAAIeAAgKmQpL3gDLAQAeAAgKmQpL3gDLAQABNQAECgoKNQAMAOoVAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQAECgIIAgAAAA==.Punchju:BAAANQAECgEIAgAAAA==.Punkz:BAAANQADCgYICAABNQAECggIGQAMAPwbAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgYJCwAAAA==.',
Py='Pyromortis:BAAANQAECgcIEQABNQAECgoKPQASAEsXAA==.Pytorch:BAABNQAECn9+AAIeAAkKByHPFADgAgAeAAkKByHPFADgAgAAAA==.',
['Pø']='Pø:BAAANQAECgQIBAAAAA==.',
Qu='Queelex:BAAANQAECgcIDAABNQAECggIGQAMAPwbAA==.Quigzz:BAACNQAFFH8LAAIEAAUKfhBUEQDaAAAEAAUKfhBUEQDaAAA1AAQKf0AAAgQACgrZIF8GABsDAAQACgrZIF8GABsDAAAA.Quinnie:BAABNQAECn8ZAAMlAAoKQRk8IADnAAAeAAgKLRaitwAMAQAlAAUKqBQ8IADnAAABNQAFFAIIAgAJAAAAAA==.',
Ra='Raganarok:BAAANQAECgIIAgAAAA==.Rahja:BAAANQAECgYICQAAAA==.Ramms:BAAANQAECggICAAAAA==.Ramss:BAAANQAECggIEAAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECgoKLwAZANgRAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQAECggIDwAAAA==.Rellans:BAAANQAECgYIBwAAAA==.Resa:BAABNQAECn8YAAIMAAgKlwnYZQBSAQAMAAgKlwnYZQBSAQAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ri='Ricasti:BAAANQAECgYICwAAAA==.Ritsu:BAAANQAECgcIDgAAAA==.',
Ro='Robinsonic:BAABNQAECn8jAAIVAAoKFhnMEQBFAgAVAAoKFhnMEQBFAgAAAA==.Rokenn:BAAANQADCggICAAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.Rosetastoned:BAAANQADCgIIAgAAAA==.',
Ru='Rukiè:BAAANQAFFAEIAQAAAA==.Runmyrkr:BAAANQAECgcIEwAAAA==.',
['Rô']='Rôbert:BAABNQAECn8dAAIUAAkKlg7bowBFAQAUAAkKlg7bowBFAQAAAA==.',
Sa='Saberyn:BAABNQAECn8fAAImAAkK+hB3CQDAAQAmAAkK+hB3CQDAAQAAAA==.Sacredsassy:BAAANQAECgUIDAABNQAECgoKHwAkAIwIAA==.Saenya:BAABNQAECn8YAAITAAcK7RWWKgDSAQATAAcK7RWWKgDSAQAAAA==.Sageofwampa:BAAANQADCggICgAAAA==.Sahra:BAAANQADCggICAAAAA==.Samavanas:BAAANQADCggICwAAAA==.Sassynova:BAAANQADCgYICQABNQAECgoKHwAkAIwIAA==.',
Sc='Schvitz:BAABNQAECn8nAAIGAAoKsRX1XQDGAQAGAAoKsRX1XQDGAQAAAA==.Scopeftis:BAABNQAECn8dAAIQAAoKqR6MJQCoAgAQAAoKqR6MJQCoAgAAAA==.',
Se='Seano:BAAANQAECgMIAwAAAA==.Seberology:BAABNQAECn8pAAIIAAkKEBJ8SgA+AgAIAAkKEBJ8SgA+AgAAAA==.Segagamecube:BAAANQADCgMIAwAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.Seraphies:BAAANQADCgQIAgAAAA==.Sergal:BAAANQADCggICAABNQAECgMICQAJAAAAAA==.',
Sh='Shaco:BAAANQAECgMIAwAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgQICQABNQAECgEIAQAJAAAAAA==.Shamownage:BAABNQAECn81AAMMAAoK6hU7PQDwAQAMAAoK6hU7PQDwAQANAAcKwBNRgQChAQAAAA==.Shankyews:BAAANQADCgQJBAAAAA==.Sheev:BAAANQADCgEIAQAAAA==.Shepling:BAACNQAFFH8KAAIaAAUKMg2WEwAhAQAaAAUKMg2WEwAhAQA1AAQKfxQAAhoACAp7FfZGAN0BABoACAp7FfZGAN0BAAAA.Shifterella:BAAANQAECgMIBwAAAA==.Shifu:BAACNQAFFH8LAAIKAAQKyBedBwDaAAAKAAQKyBedBwDaAAA1AAQKfx8AAwoACgrzHvAaAGYCAAoACAr+IfAaAGYCACEABwqEFU4VAI8BAAAA.Shivàh:BAACNQAFFH8QAAMQAAYKRBfkBwCbAQAQAAUKOBrkBwCbAQARAAQKdhHDEADTAAA1AAQKfzgABBEACgqMI/IIAAUDABEACgpJI/IIAAUDABoACQrCHI0UAEQCABAAAwqkIViDABEBAAAA.Shneezleberg:BAABNQAECn8uAAMHAAoKGh8BOADkAgAHAAoKGh8BOADkAgAmAAQKvgrJIwCVAAAAAA==.Shädowcraft:BAAANQADCgUIBQAAAA==.',
Si='Sildormi:BAAANQAECgEIAQAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAABNQAECn83AAIDAAoKzBExFAA+AgADAAoKzBExFAA+AgAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Skiddlywinks:BAAANQADCgYIGAABNQAECgkJFgAFAH8UAA==.Sko:BAABNQAECn8fAAIHAAkKPRkKVwCGAgAHAAkKPRkKVwCGAgAAAA==.Skyscreamer:BAAANQAECggICAAAAA==.Skár:BAAANQADCggICwAAAA==.',
Sl='Sladak:BAAANQAECgIIAgAAAA==.Slimjimm:BAAANQAECgUICgABNQAECggIEQAJAAAAAA==.Slutdraggin:BAAANQAECgEIAQAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakyky:BAAANQADCggIEgAAAA==.Sneakymoomoo:BAAANQADCgYJBgABNQAECgoKPQASAEsXAA==.Snipagooly:BAAANQAECgEIAQAAAA==.Snowyrain:BAAANQAECgUICgAAAA==.',
So='Sojourner:BAABNQAECn8UAAMNAAcKJhErgwCdAQANAAYK/Q8rgwCdAQAMAAcK0BBzhgB6AQABNQAECgoKIAAIALEaAA==.Solanum:BAAANQADCgQIBAABNQAECgQIBQAJAAAAAA==.Solkar:BAAANQADCgcJCwAAAA==.Solo:BAACNQAFFH8HAAIUAAMKKQSVGACiAAAUAAMKKQSVGACiAAA1AAQKfzkAAhQACgqiHXAtAIICABQACgqiHXAtAIICAAAA.Soupsandwich:BAAANQAECgMIBAAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
Sp='Spartacùs:BAAANQADCgEIAQABNQAECgUICwAJAAAAAA==.',
St='Stagefive:BAAANQAECgEIAgAAAA==.Stagg:BAABNQAECn8vAAIeAAoKnRZjnABIAgAeAAoKnRZjnABIAgAAAA==.Staggerdaddy:BAAANQAECgEIAQAAAA==.Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQADCgcIEQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.Stkk:BAAANQAECggICAAAAA==.Stonedkritz:BAAANQABCgQIAwAAAA==.',
Su='Sunarii:BAABNQAECn8aAAITAAkKEBZEIQAtAgATAAkKEBZEIQAtAgAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.Superbroke:BAAANQAECgEIAQAAAA==.Superpoor:BAAANQABCgEIAQAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
['Sà']='Sàviorself:BAAANQAECgIIBQAAAA==.',
['Sý']='Sýlvanàs:BAAANQADCgMIAwAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAABNQAECn8uAAIiAAoKxQo7EAC/AQAiAAoKxQo7EAC/AQAAAA==.Talwayn:BAAANQADCgUIDwABNQAECgkJFgAFAH8UAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQAECgIIAgAAAA==.Taurtellini:BAAANQAECgQICQAAAA==.Tazoo:BAABNQAECn8hAAMcAAkKDgOPIgAzAQAcAAkKDgOPIgAzAQAMAAEKygi4KQEkAAAAAA==.',
Te='Teamfluffer:BAAANQADCgUICQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Tehzew:BAAANQADCggIDAAAAA==.Tehzuurmx:BAAANQADCggIDAAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQABCgMIAwAAAA==.Terebitha:BAAANQABCgMIAgAAAA==.Termina:BAAANQAECgEIAwAAAA==.Teruulos:BAAANQAECgUIDwAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAABNQAECn8sAAISAAoKkh3VNACUAgASAAoKkh3VNACUAgAAAA==.Thadiusx:BAAANQABCgUIBQAAAA==.Tharon:BAABNQAECn8jAAIGAAoKiBUeZgBIAgAGAAoKiBUeZgBIAgAAAA==.Thebigboom:BAACNQAFFH8HAAIVAAIKxgyVBgBtAAAVAAIKxgyVBgBtAAA1AAQKf0EAAhUACgpxHlQIAJUCABUACgpxHlQIAJUCAAAA.Thecarter:BAAANQAECgIIAgAAAA==.Theghoulest:BAAANQAECggICwAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.Threnody:BAABNQAECn8pAAMLAAcKXQ5vJAAMAQALAAcKcQ1vJAAMAQAGAAIKDBMtNAGAAAAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgUIBwAJAAAAAA==.Tichemort:BAAANQAECgUIBwAAAA==.Tigerchimon:BAAANQADCgUIBQABNQAECgoKNQAMAOoVAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAACNQAFFH8KAAMoAAMKWA2NAACPAAAoAAMKWA2NAACPAAAeAAIK5AOaUACBAAA1AAQKf0kAAygACgqdILsAALUCACgACgqdILsAALUCAB4ABAprCgKQAacAAAAA.',
Tr='Trapscallion:BAAANQAECgQIEAAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Tratraz:BAAANQAECggIBgAAAA==.Treeknight:BAABNQAECn8fAAIQAAgKOBRISQDxAQAQAAgKOBRISQDxAQAAAA==.Treelimbs:BAAANQAECgcIDwAAAA==.Treemoo:BAAANQAECgEIAgABNQAECgoKPQASAEsXAA==.Tridity:BAAANQAECgYIDwAAAA==.Trollolollz:BAAANQAECgIIAwAAAA==.',
Ts='Tsuuna:BAABNQAECn86AAQHAAoKRyH+LwBYAgAHAAoKxCD+LwBYAgAmAAEK8yJKIQBmAAAPAAEKAABxPgBIAAAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.Turtleqtx:BAAANQAECgQIBAAAAA==.',
Tw='Twohalfs:BAAANQADCgMIAwAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQAECgIIBAAJAAAAAA==.Tylandon:BAAANQAECgYICQAAAA==.Tyralthas:BAAANQADCgQIAwAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgIJAwAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Un='Unavaluable:BAAANQAECgYICwAAAA==.Ungodlyy:BAABNQAECn8aAAMZAAkK7AWxiwAPAQAZAAkK7AWxiwAPAQAfAAIKDgKVagBMAAAAAA==.Untöuchable:BAABNQAECn9NAAMUAAoKDCRSDAAuAwAUAAoKDCRSDAAuAwAIAAIKIwgt2AA7AAAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Va='Vanthelos:BAAANQADCgQIBQAAAA==.',
Ve='Velachlan:BAAANQAECgYIEwAAAA==.Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAABNQAECn9DAAQEAAoK/RniKgAdAgApAAkKyhebBwA3AgAEAAkKEBjiKgAdAgAWAAMK9RLXfQC8AAAAAA==.Verxl:BAABNQAECn8lAAIeAAcKURh0kgBTAQAeAAcKURh0kgBTAQAAAA==.Verypoor:BAAANQAECgUIBQAAAA==.',
Vi='Vihn:BAAANQADCgYIBgAAAA==.',
Vo='Voidnyou:BAAANQADCgQICAAAAA==.Volumes:BAAANQAECgUIBwAAAA==.Volund:BAABNQAECn89AAIcAAoKKwhYGABKAQAcAAoKKwhYGABKAQAAAA==.',
Vy='Vynsong:BAABNQAECn8mAAIIAAkKMiBRIQDoAgAIAAkKMiBRIQDoAgAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAAJAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFgAAAA==.Watchmebløck:BAAANQAECgQIBQAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBgAAAA==.Wetmonk:BAAANQAECgcIDQAAAA==.',
Wh='Whoyerdaddy:BAAANQAECgQICgAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Wiggletang:BAAANQAECgEIAQAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAABNQAECn82AAMMAAoKJBJ3WwD9AQAMAAoKJBJ3WwD9AQANAAgKeBGveADpAAAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.',
Wo='Wombatman:BAAANQAECgYIEQAAAA==.Wong:BAAANQAECgUIBgAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCggICAAAAA==.',
Xo='Xoron:BAAANQAECgQIBAAAAA==.',
Xu='Xugos:BAABNQAECn8fAAIZAAoKGRgbZgAoAgAZAAoKGRgbZgAoAgAAAA==.',
Xz='Xzeena:BAAANQADCgEIAQAAAA==.',
Ya='Yatagarasu:BAAANQAECggIAgAAAA==.',
Ye='Yenafer:BAAANQADCggICAAAAA==.',
Yo='Yochill:BAAANQAECgIIAgABNQAECgYIDAAJAAAAAA==.Yolokin:BAAANQAECgIIBAAAAA==.Yooper:BAAANQADCgcIBgAAAA==.Yota:BAAANQAECgIIBgAAAA==.',
Yr='Yrgg:BAAANQAECgcICwAAAA==.',
Yt='Ytgamezoned:BAAANQADCgQIBAAAAA==.',
Yu='Yuna:BAAANQAECgEIAQAAAA==.',
Za='Zadanthra:BAABNQAECn8WAAIFAAkKfxTHEAClAQAFAAkKfxTHEAClAQAAAA==.Zalektra:BAAANQADCgQIBAAAAA==.Zapadin:BAABNQAECn8tAAIUAAoKZhIlggAkAgAUAAoKZhIlggAkAgAAAA==.Zaphodè:BAAANQAECgUICQAAAA==.',
Ze='Zeenie:BAAANQAFFAIIAgAAAA==.Zeljusticar:BAAANQADCgEIAgAAAA==.Zephian:BAAANQAECgMIAwAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAABNQAECn8gAAQnAAgKAAubCwCFAQAnAAgKAAubCwCFAQASAAYK2wN8sQACAQATAAUKNgWpUQDKAAAAAA==.Zotoperen:BAABNQAECn8xAAMhAAoK/iBkAwBdAwAhAAoK/iBkAwBdAwAKAAMKFhHoUgClAAAAAA==.',
Zy='Zylergy:BAABNQAECn8cAAIUAAoKPgl23wBcAQAUAAoKPgl23wBcAQAAAA==.',
['Zì']='Zìfu:BAAANQADCggICQAAAA==.',
['Àv']='Àvicant:BAAANQAECgUJBwABNQAFFAQICAAGAFMiAA==.',
['Än']='Ändo:BAAANQAECgQIDgAAAA==.',
['Äy']='Äy:BAAANQADCgIIAgAAAA==.',
['Çy']='Çyrin:BAABNQAECn8wAAMIAAkKsBMXSgA/AgAIAAkKsBMXSgA/AgAUAAEK5QhHpwEzAAAAAA==.',
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
