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

local lookup = {'Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','Rogue-Subtlety','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Unknown-Unknown','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Mage-Frost','Rogue-Assassination','Warrior-Fury','Paladin-Holy','Paladin-Protection','Druid-Feral','Warlock-Demonology','DeathKnight-Blood','Mage-Arcane','Hunter-Survival','Shaman-Enhancement','DemonHunter-Devourer','Mage-Fire','Warlock-Affliction','Warlock-Destruction','Monk-Brewmaster','Evoker-Preservation','Rogue-Outlaw','Monk-Mistweaver','DemonHunter-Havoc','Priest-Discipline',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abssorath:BAAANQADCgcICwAAAA==.',
Ae='Aerouant:BAABNQAECn9QAAMBAAoKHRnQBQBaAgABAAkK8BfQBQBaAgACAAkKeReXBgBWAgAAAA==.',
Ai='Aidix:BAAANQADCggIFQAAAA==.Aimassist:BAAANQAECgQIBAAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAABNQAECn80AAIDAAoK+R15DwDfAgADAAoK+R15DwDfAgAAAA==.Alexstanna:BAAANQAECgUICgAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.Alwaysbroke:BAAANQAECgYICAAAAA==.',
An='Andrena:BAABNQAECn8aAAIEAAgKZRQ4RQDqAQAEAAgKZRQ4RQDqAQAAAA==.Andycat:BAAANQAECgEIAQAAAA==.Annarchy:BAAANQADCgQIBAAAAA==.Antagony:BAAANQAECgUIBQAAAA==.Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAABNQAECn8wAAIFAAoKQBTJCQBEAgAFAAoKQBTJCQBEAgAAAA==.Anthross:BAABNQAECn8qAAIGAAoKHw9/hgD+AQAGAAoKHw9/hgD+AQAAAA==.',
Ap='Apollovon:BAABNQAECn8rAAIHAAkKeyGkLQAGAwAHAAkKeyGkLQAGAwAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanemage:BAAANQADCgYIBwAAAA==.Arcanenug:BAAANQADCgQJBAAAAA==.Arcbnonez:BAAANQAECgQIBAAAAA==.Arguxx:BAAANQAECggIEgAAAA==.Armiggy:BAABNQAECn9aAAIIAAoKghXMEwApAgAIAAoKghXMEwApAgAAAA==.Aro:BAACNQAFFH8TAAMJAAcKcCALCgCiAQAJAAYKYB8LCgCiAQAGAAIK4huxIACwAAA1AAQKfy4AAwkACgqwJPMYAMEBAAYABgrQI6OZANQBAAkACApRI/MYAMEBAAAA.Arrowraen:BAABNQAECn8rAAIGAAkK/SMfBwCkAwAGAAkK/SMfBwCkAwAAAA==.',
As='Asavera:BAAANQAECggICgAAAA==.Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgYJBgAAAA==.Asträl:BAAANQADCgYIBgAAAA==.',
Au='Audomere:BAABNQAECn8rAAMKAAoKpwwaXwCbAQAKAAoKpwwaXwCbAQALAAIKlgFXLQE7AAAAAA==.Auurwarr:BAAANQAECgUIBQAAAA==.',
Av='Avawrath:BAAANQAECggIEQAAAA==.Avelm:BAAANQAECggIAwAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgoKMwAFADwfAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Balanji:BAAANQADCgUIBQABNQAECgoKHAAFAPEUAA==.Ballstench:BAAANQAECgYICQAAAA==.Barbåtos:BAAANQAECgMIBQAAAA==.Baskthyr:BAAANQADCgQIBAAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAABNQAECn8XAAIMAAgKSBQ1OQAmAgAMAAgKSBQ1OQAmAgABNQADCgUIBQANAAAAAA==.Bearbomblolz:BAAANQADCgQIBQABNQAECgoKHAAFAPEUAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQADCgQICAAAAA==.Beastbane:BAAANQAECggIEQAAAA==.Beastly:BAAANQAECgYICgAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAABNQAECn83AAMHAAoKuhiyRQC4AgAHAAoKuhiyRQC4AgAOAAgKVhTyFQDJAQAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAABNQAECn9xAAMPAAkKyRY6QgATAgAPAAgKoBc6QgATAgAQAAkKXhD6PACpAQAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgANAAAAAA==.Bewslee:BAAANQAECgEIAwABNQAECgUIBQANAAAAAA==.Bexx:BAAANQADCggJGQAAAA==.',
Bi='Bibledaddy:BAABNQAECn9LAAMRAAoKkRmZSgBFAgARAAoKkRmZSgBFAgASAAYKlgsMQgAhAQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgcIDQANAAAAAA==.Bigbonks:BAAANQAECgQIBgAAAA==.Bigdumb:BAAANQAECgUIBwAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.Billclintun:BAAANQAECgMIAwABNQAECgQICAANAAAAAA==.',
Bl='Blackplague:BAAANQAECgEIAQAAAA==.Blaezèr:BAAANQAECgQIBgAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQAECggICwAAAA==.Blueshamoo:BAAANQAECgEJAQAAAA==.Blupl:BAAANQABCgYIBgAAAA==.Blãezer:BAAANQAECggICwAAAA==.',
Bo='Bonex:BAAANQAECgEIAgAAAA==.Boomshroom:BAAANQAECgMIBAABNQAECgoKOwAIAO4fAA==.Bootsie:BAAANQADCggICAAAAA==.',
Br='Brewtoe:BAABNQAECn8uAAIIAAgKQRnvFAAbAgAIAAgKQRnvFAAbAgAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Broshunteri:BAAANQADCggICAAAAA==.Bruegard:BAAANQADCgIIAgAAAA==.Bruneau:BAAANQABCgUIBQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAgIGwAJAEYaAA==.',
Bu='Bubblemehard:BAABNQAECn8cAAITAAgKMhibewAzAgATAAgKMhibewAzAgAAAA==.Bushky:BAAANQAECgMIAwAAAA==.',
By='Byahnbreath:BAACNQAFFH8FAAIQAAIK7waxGAB7AAAQAAIK7waxGAB7AAA1AAQKfygAAhAACgo0G5EjAHQCABAACgo0G5EjAHQCAAAA.',
Ca='Caesardr:BAABNQAECn9HAAIUAAoKVx6XCAC6AgAUAAoKVx6XCAC6AgAAAA==.Cakeiko:BAAANQAECgQIBgABNQAFFAIIBQAVAGAJAA==.Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Carolaine:BAAANQADCgQIAgAAAA==.Casmiralda:BAAANQABCgUIBQAAAA==.Castielx:BAABNQAECn8ZAAIWAAcKthIcQQDHAQAWAAcKthIcQQDHAQAAAA==.Catnips:BAAANQAECgUIBgABNQAECgoKSwARAJEZAA==.',
Ce='Celestraza:BAABNQAECn8cAAIXAAoKCRK3CgDoAQAXAAoKCRK3CgDoAQAAAA==.Celirra:BAABNQAECn80AAIPAAoKDyFvDwA7AwAPAAoKDyFvDwA7AwAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.Cenzo:BAABNQAECn8WAAILAAgKaw1wXAByAQALAAgKaw1wXAByAQAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAABNQAECn8vAAIHAAoKxQtQrgCpAQAHAAoKxQtQrgCpAQAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAABNQAECn8WAAMWAAgKKxyANwD6AQAWAAcKKxyANwD6AQAEAAEKAAA3TwBDAAAAAA==.Chokma:BAABNQAECn8vAAILAAoK3BiKZgDtAQALAAoK3BiKZgDtAQAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAABNQAECn8gAAMYAAkKcw8qVwC5AQAYAAkKcw8qVwC5AQAZAAEKlAQGfgAfAAAAAA==.',
Ci='Cinnaa:BAAANQAECgUICQAAAA==.',
Cl='Clawdog:BAAANQADCgIIAgABNQAECgIIBAANAAAAAQ==.Clawwz:BAAANQAECgMIBAAAAA==.Cleisthenes:BAAANQAECgEIAQABNQAECgUIBQANAAAAAA==.Clors:BAABNQAECn8sAAQDAAoKnRs4FACIAgADAAoKnRs4FACIAgAMAAIKnAmheABaAAAaAAIKOg0QSgA0AAAAAA==.',
Co='Compressed:BAAANQABCgIIAgAAAA==.Conflux:BAAANQADCggIFAAAAA==.Coopada:BAAANQABCgEIAQAAAA==.Cowvibez:BAAANQADCgUICgAAAA==.',
Cr='Crager:BAABNQAECn8VAAIHAAgKTwh0qgAmAQAHAAgKTwh0qgAmAQAAAA==.Crawlah:BAAANQADCggIDgABNQAECgoKUQALANIdAA==.Crazegideon:BAAANQABCgIIAgAAAA==.Crazespawnz:BAAANQABCgIIAgAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIEQAAAA==.',
Cy='Cyberfairy:BAAANQAECgEJAQAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQAECgEIAQAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgcICAAAAA==.Dalìnar:BAAANQAECggIDAAAAA==.Damadafacker:BAABNQAECn8wAAIHAAoKihkePgBJAgAHAAoKihkePgBJAgAAAA==.Darfine:BAAANQAECgMIAwAAAA==.Darkclôud:BAAANQAECgQIBAAAAA==.Darkkatriden:BAAANQADCgYIBgABNQAECgcIGAAbAJgJAA==.Darklia:BAABNQAECn8YAAIbAAcKmAmQzwArAQAbAAcKmAmQzwArAQAAAA==.Darthjae:BAABNQAECn9zAAMcAAkKZBvPGgApAgAcAAkKZBvPGgApAgAQAAEKAABQvgAfAAAAAA==.Darthmikkey:BAAANQADCgYIBgABNQAFFAYIEwAdAAMjAA==.Darthrakk:BAABNQAECn8qAAIeAAoKZhrUAwDBAgAeAAoKZhrUAwDBAgAAAA==.Davina:BAAANQADCgcIBwABNQAFFAQIBwATAAMOAA==.Daïn:BAAANQAECgcICgAAAA==.',
De='Deadestmoonb:BAAANQADCgIIBAAAAA==.Deathalimon:BAABNQAECn88AAQcAAkKgxsbGwAmAgAcAAkK0hkbGwAmAgAPAAgKnRTUUgDHAQAQAAEKTBBerQA0AAABNQAECgoKQAALANoYAA==.Deathvoid:BAAANQADCgQIAQAAAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQADCgUIBQAAAA==.Demonarian:BAAANQAECgcICQABNQAECgoKQAALANoYAA==.Demonicnut:BAAANQAECgMIAwABNQAECgoKLwALANwYAA==.Demonpotato:BAAANQADCggICAABNQAECgoKVQARACwhAA==.Denardath:BAAANQADCgUIBQAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAABNQAECn8kAAMKAAoKvgk1ZwCAAQAKAAoKvgk1ZwCAAQALAAgKiAyTogBQAQAAAA==.Deroc:BAABNQAECn8iAAITAAoKoAd10QA1AQATAAoKoAd10QA1AQAAAA==.Desporato:BAAANQAECggIBAAAAA==.Deáthtáxi:BAAANQAECggICAAAAA==.',
Di='Digweeds:BAABNQAECn8XAAIfAAkKrRqUEgDuAQAfAAkKrRqUEgDuAQABNQAFFAEIAQANAAAAAA==.Dinfarmer:BAAANQAECgUIDAAAAA==.Dirtycheese:BAAANQAECgYICwAAAA==.',
Dj='Djgha:BAAANQAECgIIBAAAAA==.',
Dm='Dmptruckdona:BAAANQAECgQIAwAAAA==.Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQAECgQICAAAAA==.Doombap:BAACNQAFFH8LAAIgAAQKnwdWCgC7AAAgAAQKnwdWCgC7AAA1AAQKfzcAAiAACgrIGmQMAIwCACAACgrIGmQMAIwCAAAA.Dorunter:BAABNQAECn83AAMJAAoK3hRMMwCzAQAJAAcKYBJMMwCzAQAGAAgKwROgpgBlAQAAAA==.Dottíe:BAAANQAECgcIDgABNQAECgoKUQALANIdAA==.Doubledosage:BAABNQAECn8ZAAIGAAYKAgqf4gDsAAAGAAYKAgqf4gDsAAAAAA==.',
Dr='Dragonbnonez:BAAANQAECgQIBAAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Dragontails:BAAANQADCgQIBAAAAA==.Drakujin:BAAANQADCgMIBQAAAA==.Drboomboom:BAABNQAECn8pAAMdAAoKxgsylwB3AQAdAAoKxgsylwB3AQAhAAEKAACsEQAAAAAAAA==.Drdoitall:BAAANQAECgYICwAAAA==.Dreadnpain:BAAANQADCgQIBAAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIAwABNQAFFAgIFwAQAA4eAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Du='Duukwan:BAABNQAECn8VAAMRAAkK8BmNJgDQAgARAAkK8BmNJgDQAgASAAEKjhF+XQA/AAAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.Elysiá:BAAANQADCggICAAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAACNQAFFH8RAAQiAAYKSxm5BQCrAAAiAAMK4Rq5BQCrAAAjAAIKtBf/BQCXAAAbAAIK6AE+PgAAAAA1AAQKfz0AAyIACgpUJaoDALYCACIACAp8JaoDALYCACMAAwqzJP4IADoBAAAA.',
Er='Erayr:BAAANQAECgcIEQABNQAECgkJGQAdAAoNAA==.Ericolson:BAABNQAECn8yAAIHAAoKGxiCQQA9AgAHAAoKGxiCQQA9AgAAAA==.Erze:BAAANQAECgUICQAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evilhealer:BAAANQAECgMIBwAAAA==.Evilmcgyver:BAAANQABCgEIAQAAAA==.Evosolz:BAEBNQAECn8dAAIHAAoKSQw1bQC6AQAHAAoKSQw1bQC6AQAAAA==.Evé:BAAANQAECgMIAwABNQAECgoKOwAIAO4fAA==.',
Ey='Eyehealu:BAAANQADCgIIAgABNQAECgoKKAAiALoPAA==.',
Ez='Ezzartkal:BAAANQAECgEIAQAAAA==.',
Fa='Faeloria:BAAANQAECgQIBAAAAA==.Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgkJcwAcAGQbAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgoKMQAkAP4gAA==.Fefra:BAAANQADCgQIBAAAAA==.Felicious:BAABNQAECn8pAAIbAAoKlRewMQBIAgAbAAoKlRewMQBIAgAAAA==.Feralco:BAABNQAECn8UAAIMAAkKcQwENABtAQAMAAkKcQwENABtAQAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fixiation:BAAANQAECgEIAQAAAA==.Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Flashdance:BAAANQADCggIIQAAAA==.Fleepo:BAAANQAECgIIAwAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAABNQAECn82AAMlAAoKuw1mHQD3AQAlAAoKuw1mHQD3AQABAAEKAAC7PgAvAAAAAA==.Flyhawk:BAAANQAECgYIEAAAAA==.Flöör:BAAANQADCgUIBQAAAA==.',
Fo='Footloose:BAAANQAECgcIDAABNQAECgkJcwAcAGQbAA==.',
Fu='Fullmetal:BAABNQAECn8XAAIiAAgKaQz1DQBYAQAiAAgKaQz1DQBYAQAAAA==.Funkadelfic:BAAANQAECggIDwAAAA==.',
['Fè']='Fèngshui:BAAANQADCggIGwAAAA==.',
['Fé']='Fénrír:BAAANQADCggIDwABNQAECgoKOwALANkhAA==.',
['Fò']='Fòxxy:BAAANQAECgMIAQAAAA==.',
Ga='Galadri:BAABNQAECn8ZAAMKAAgK/BuUQQBaAgAKAAgK/BuUQQBaAgALAAUKCxAXwwAMAQAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIEAAAAA==.Geartryx:BAAANQADCggIDQAAAA==.Geodood:BAAANQAECgYIDgAAAA==.',
Gh='Ghoshshadow:BAAANQAECgYICAAAAA==.Ghostinz:BAABNQAECn8XAAIHAAcKkQzOqAApAQAHAAcKkQzOqAApAQAAAA==.',
Gi='Gimpripper:BAAANQAECgcICQAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggJIAAcAGcaAA==.Globalcold:BAABNQAECn8bAAIHAAgKLBoLdAA4AgAHAAgKLBoLdAA4AgAAAA==.Globb:BAABNQAECn8xAAIHAAgKVxSIlwDhAQAHAAgKVxSIlwDhAQAAAA==.Globius:BAABNQAECn8yAAITAAoKdhtNSgC2AgATAAoKdhtNSgC2AgAAAA==.Gloriouscole:BAABNQAECn8UAAITAAYKBCIhdgBBAgATAAYKBCIhdgBBAgAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gooly:BAAANQADCgIIAgAAAA==.Goombit:BAAANQADCgEIAQAAAA==.',
Gr='Greekorc:BAAANQABCgYIBwAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Grimby:BAAANQAECggIBQAAAA==.Grimdisney:BAAANQADCggIDgAAAA==.Grimriot:BAAANQAECgUIBQABNQAECgoKLAAcAPEVAA==.Groceries:BAAANQADCgMIAwAAAA==.Gromol:BAAANQADCggIHwAAAA==.Grumby:BAAANQAECgIIBgAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQAECgQIBAAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQAECgQIBgAAAA==.Hatebrêêd:BAAANQADCgQIBQAAAA==.Hazhazbot:BAAANQADCgYIBQAAAA==.',
He='Healman:BAAANQADCgcIGQAAAA==.Healpaws:BAAANQADCgUIBQAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgcIDAAAAA==.Heiden:BAAANQADCgYJBgAAAA==.Hel:BAAANQAECgIIAwAAAA==.Hellyas:BAABNQAECn8cAAMTAAgKKxKfqgB6AQATAAgKKxKfqgB6AQAZAAMKSgvMSACCAAAAAA==.Herbs:BAAANQAECgEIAQABNQAECgoKUQAmACcdAA==.Herenorthere:BAABNQAECn8yAAMSAAoKgBr6GgBxAgASAAgKEhz6GgBxAgARAAgKgxs3dQC8AQABNQAFFAUICwAiABsXAA==.Hermippe:BAAANQAECgMIAwAAAA==.Hexstraits:BAACNQAFFH8GAAIcAAIKRBMsIACIAAAcAAIKRBMsIACIAAA1AAQKfycAAhwACgrHIiMQACwDABwACgrHIiMQACwDAAAA.',
Hi='Hia:BAACNQAFFH8WAAIcAAYKyByhCgCtAQAcAAYKyByhCgCtAQA1AAQKf0cABBwACgrGIh4LAFsDABwACgrGIh4LAFsDAA8AAQpAB0+MADAAABAAAgpmAbDHAA8AAAAA.Highriskbr:BAAANQAECggICAAAAA==.Hitlist:BAAANQADCgUJBQAAAA==.',
Ho='Holycow:BAAANQAECgIIBAAAAA==.Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBgAAAA==.Hondaimpala:BAAANQAECgQIBgABNQAECgkJcwAcAGQbAA==.Hoofmaster:BAAANQABCgMIAwAAAA==.Hopskotch:BAAANQADCgQIBAAAAA==.Hordenfel:BAAANQADCggIEAAAAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huffy:BAAANQAECggIDQABNQAFFAUIBgAHADgbAA==.Huffyy:BAACNQAFFH8GAAIHAAUKOBvrIAD4AAAHAAUKOBvrIAD4AAA1AAQKf3AAAgcACgp6Jl8BAI4DAAcACgp6Jl8BAI4DAAAA.Huhdean:BAABNQAECn8hAAMQAAgKDCQMHACqAgAQAAcKsiMMHACqAgAPAAQKzyF1hQALAQAAAA==.Hulxamus:BAAANQAECgYICgAAAA==.Hunterramen:BAAANQADCgEJAQAAAA==.Hunterz:BAAANQAECgQICQAAAA==.',
['Hé']='Héåthcliff:BAACNQAFFH8NAAMTAAUKWRi5CgA8AQATAAUKWRi5CgA8AQAZAAEKqA2vEQA9AAA1AAQKf2IAAxkACgoqJNQEAGcDABkACgqNItQEAGcDABMACgpoIVMmAMgCAAAA.',
Ic='Icyblaze:BAAANQAECggIEAAAAA==.',
Id='Idareu:BAABNQAECn8bAAIMAAgKaQXrhwC0AAAMAAgKaQXrhwC0AAAAAA==.',
If='Ifstar:BAAANQAECgMIBAAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICQANAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQAECgUIBgAAAA==.Issalis:BAAANQADCgYIBgAAAA==.',
It='Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgcIDgAAAA==.',
Iz='Izonie:BAABNQAECn8aAAMgAAkKAxQeHADHAQAgAAkKAxQeHADHAQAFAAQK5gwZIQCBAAABNQAFFAUIDgALAFsVAA==.',
Ja='Jaaric:BAAANQAECgUICAAAAA==.Jaimerrek:BAABNQAECn8ZAAIdAAkKCg0ZnwBmAQAdAAkKCg0ZnwBmAQAAAA==.Jainalynn:BAAANQAECgQIBAAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAABNQAECn9UAAMDAAoKBhHkHQATAgADAAoKBhHkHQATAgAMAAgKZASTVQDIAAAAAA==.',
Jd='Jdarkside:BAABNQAECn8XAAIFAAcK/AboHACqAAAFAAcK/AboHACqAAAAAA==.',
Je='Jebediahmoon:BAAANQAECggIEAABNQAECgkJcwAcAGQbAA==.Jenzil:BAAANQAECggICAAAAA==.Jeremmiah:BAAANQADCgcIEwAAAA==.',
Jh='Jhacobo:BAABNQAECn8sAAIMAAoKcxfwMQBTAgAMAAoKcxfwMQBTAgAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jonnyrage:BAAANQAECgIIAgAAAA==.Jorkinit:BAABNQAECn8hAAIdAAoKfxSl3wDJAQAdAAoKfxSl3wDJAQAAAA==.',
Jr='Jragon:BAABNQAECn8jAAIbAAgKbQoFlwCtAQAbAAgKbQoFlwCtAQAAAA==.',
Ju='Judis:BAAANQABCgYICwAAAA==.Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAABNQAECn8iAAIdAAoKDR0lZgCyAgAdAAoKDR0lZgCyAgAAAA==.Junipur:BAAANQAECgMICQAAAA==.Justinna:BAAANQADCgIIAgAAAA==.',
Jx='Jxxy:BAACNQAFFH8VAAMGAAUKNyMBDAAzAQAGAAUKNyMBDAAzAQAJAAQKvhUuFwCbAAA1AAQKfyYAAwYACgrRIKNbABICAAYACgpQIKNbABICAAkAAwrvGEhEAI0AAAE1AAUUBQoVAAYANyMA.',
['Jú']='Júnjúnwälä:BAABNQAECn8nAAIDAAoKoSQHDgDwAgADAAoKoSQHDgDwAgAAAA==.',
Ka='Kalories:BAAANQAECgUICwAAAA==.Kalvoid:BAAANQAECgQIBAABNQAECgUICwANAAAAAA==.Kandance:BAAANQAECggIEwABNQAFFAIIAgANAAAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ke='Kelvintwo:BAAANQADCgQIAwAAAA==.',
Ki='Kimbopable:BAAANQAECgUIBQABNQAECgkJcwAcAGQbAA==.Kitkatcate:BAAANQADCgEIAQAAAA==.Kittyÿ:BAAANQAECgYICwAAAA==.',
Kn='Knurl:BAAANQADCgMIAwAAAA==.',
Ko='Korak:BAAANQADCgUIBQABNQADCgYIBgANAAAAAA==.Korgh:BAAANQAECgEIAQAAAA==.Kosari:BAAANQAECgUIBgAAAA==.',
Kr='Krystall:BAABNQAECn8oAAIiAAoKug/NBwAbAgAiAAoKug/NBwAbAgAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAABNQAECn87AAMIAAoK7h/zEgDEAgAIAAoK7h/zEgDEAgAnAAIKjQpjOQBLAAAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQAECgUICgABNQAECgUICwANAAAAAA==.',
['Ká']='Kál:BAAANQADCgEIAQABNQAECgUICwANAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgUICwANAAAAAA==.',
['Kì']='Kìngknìghts:BAABNQAECn8hAAMQAAgKYhCvPwCdAQAQAAgKVQ+vPwCdAQAPAAQKYA+NVwCoAAAAAA==.',
La='Lalphas:BAABNQAECn81AAMbAAoKRg/CZQApAgAbAAoKRg/CZQApAgAjAAEKxgONhAAmAAAAAA==.Lanthos:BAABNQAECn9ZAAIgAAoKNCL9BQD/AgAgAAoKNCL9BQD/AgAAAA==.Lapulapu:BAAANQADCgYIBgAAAA==.Larthal:BAAANQAECgcICwAAAA==.Latinpapi:BAABNQAECn8rAAMTAAoKVxRydABFAgATAAoKVxRydABFAgAZAAEKAAB5aQBAAAAAAA==.',
Le='Leemers:BAAANQADCgEIAQAAAA==.Leemiez:BAAANQADCgcIDgAAAA==.Leyära:BAAANQAECgYIDAAAAA==.',
Li='Lielys:BAAANQAECgMIAgABNQAECgUIFQAJAPETAA==.Lilina:BAABNQAECn8nAAMFAAgKvhjACwAQAgAFAAgKvhjACwAQAgAoAAEK9wA5lAASAAAAAA==.Liljaejae:BAAANQADCgEIAQAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Lonweh:BAAANQAECgMIBAAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgUICwABNQAECgkJHwAGAAIPAA==.',
Lu='Lucith:BAABNQAECn82AAIQAAoKFiJJBgB+AwAQAAoKFiJJBgB+AwAAAA==.Luckie:BAAANQABCgQIBwABNQAFFAcIEAAYAIUOAA==.Lulafairy:BAAANQAECgEJAQAAAA==.Lumador:BAAANQAECgQIBwABNQAECgcIIAASAIQUAA==.Lunatick:BAABNQAECn9JAAQQAAoKyhAONgDKAQAQAAoKYA4ONgDKAQAcAAMKzRuphwDgAAAPAAUK6wMSpwCqAAAAAA==.Lunawa:BAACNQAFFH8UAAIdAAYKpB42EwBcAQAdAAYKpB42EwBcAQA1AAQKf3YAAx0ACgp3JlgCAHYDAB0ACgp3JlgCAHYDABUAAwpLETMtAJQAAAAA.Lustbót:BAABNQAECn8bAAIdAAkKGweA6AC5AQAdAAkKGweA6AC5AQAAAA==.Luvnrdjr:BAAANQADCgYIBgAAAA==.',
Ly='Lynnai:BAAANQAECgUIBAABNQAECgUIBgANAAAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAACNQAFFH8XAAIoAAcKpRwOBwDPAQAoAAcKpRwOBwDPAQA1AAQKf04AAigACgr+JXgEAEYDACgACgr+JXgEAEYDAAAA.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lí']='Líllith:BAAANQAECgIIAgAAAA==.',
['Lô']='Lôuku:BAABNQAECn86AAIbAAoKyxlCQwCIAgAbAAoKyxlCQwCIAgAAAA==.',
Ma='Maahn:BAAANQADCgcICAAAAA==.Macalob:BAAANQAECgQIBgAAAA==.Madallar:BAABNQAECn8ZAAIHAAkKIxB+rQCrAQAHAAkKIxB+rQCrAQAAAA==.Magdagni:BAABNQAECn8aAAIfAAgKHBDqHACVAQAfAAgKHBDqHACVAQAAAA==.Mageji:BAACNQAFFH8TAAIdAAYKAyMAEQB4AQAdAAYKAyMAEQB4AQA1AAQKf0sAAx0ACgokJpIQAA0DAB0ACgokJpIQAA0DABUAAQqMIhYyAGMAAAAA.Magepies:BAAANQAECgQIBgABNQAECgQICAANAAAAAA==.Magerella:BAAANQAECgMIAgAAAA==.Magicfurry:BAAANQAECgUICgABNQAECgoKSwARAJEZAA==.Mainveinz:BAABNQAFFH8LAAIcAAYK3wAUHQCqAAAcAAYK3wAUHQCqAAAAAA==.Makimayum:BAAANQADCgQIBAAAAA==.Malicelx:BAAANQAECgIIAgABNQAECggIEgANAAAAAA==.Mallgoth:BAABNQAECn8VAAIGAAYK9gVX+gAPAQAGAAYK9gVX+gAPAQAAAA==.Manohar:BAABNQAECn8wAAMKAAoKkh0tKwC2AgAKAAoKkh0tKwC2AgALAAcKzw7MggCeAQAAAA==.Mardtard:BAABNQAECn8fAAMGAAkKUR1wPgBZAgAGAAkKUR1wPgBZAgAJAAMKigksZQCWAAABNQAECgUIBgANAAAAAA==.Marximilian:BAAANQAECgMIAwAAAA==.Maryola:BAABNQAECn8hAAIeAAkK2xFbBABDAgAeAAkK2xFbBABDAgABNQAECgoKKAAiALoPAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIJAgABNQAFFAYICwAJABMSAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQADCgYICQAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Meewcow:BAAANQADCgcIBwAAAA==.Megamango:BAABNQAECn8cAAIHAAkK4xaJUAANAgAHAAkK4xaJUAANAgABNQAFFAUIDwAVABIfAA==.Mehiel:BAAANQAECgcIDQAAAA==.Meive:BAAANQADCgYIBgAAAA==.Menime:BAAANQADCgYIBgAAAA==.Meraxes:BAAANQAECgEIAQAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Merkén:BAABNQAECn8aAAIXAAkKYBcRCAArAgAXAAkKYBcRCAArAgAAAA==.Metaloclypse:BAAANQADCgcIDgAAAA==.Meteas:BAAANQAECggIDQAAAA==.Mezaryn:BAABNQAECn8cAAITAAoKCwlqCQHbAAATAAoKCwlqCQHbAAABNQAECgoKNwADAGkLAA==.Mezgrim:BAAANQAECggIAgABNQAECgoKNwADAGkLAA==.Mezzoo:BAABNQAECn83AAIDAAoKaQsRNgBGAQADAAoKaQsRNgBGAQAAAA==.',
Mi='Midger:BAAANQADCgUICAAAAA==.Mikitaju:BAAANQAECgEIAQABNQAECgoKHAAFAPEUAA==.Millic:BAABNQAECn87AAMpAAoKdhavAwA0AgApAAoKdhavAwA0AgASAAUK1AueNgDhAAAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEJAQAAAA==.Mitzrael:BAAANQADCgYICAAAAA==.',
Mo='Mongolious:BAAANQABCgUIBQAAAA==.Moozx:BAAANQAECgEIAQAAAA==.Mosfeat:BAAANQADCggICAABNQAECgkJIwAfAH4aAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Murrll:BAAANQAECgQIBQAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAABNQAECn84AAIoAAoKpgltNgBwAQAoAAoKpgltNgBwAQAAAA==.Nasuadia:BAAANQADCggIIQABNQAECgoKOwAQAIUdAA==.',
Ne='Necrolysis:BAAANQAECgYICwAAAA==.Necromansorz:BAAANQAECggICAAAAA==.Nekkash:BAAANQAECgYICgAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.Newwt:BAAANQAECggIDwAAAA==.Neytiri:BAAANQABCgQIBQAAAA==.Nezelle:BAABNQAECn8fAAIlAAkKWQ/zHgAZAQAlAAkKWQ/zHgAZAQABNQAECgoKUQAmACcdAA==.',
Ni='Nimou:BAAANQAECgYICwAAAA==.',
No='Nomaa:BAAANQADCgQIBAAAAA==.Noraice:BAAANQADCggICAAAAA==.Noris:BAABNQAECn8YAAMGAAkK8xAfqQBgAQAGAAgKJxMfqQBgAQAJAAIKJQNEgABEAAAAAA==.Norros:BAAANQAECgIIBAAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgQIDAAAAA==.Nuvostaph:BAABNQAECn8uAAIaAAoKaSFyBADkAgAaAAoKaSFyBADkAgAAAA==.',
Od='Odecias:BAAANQAECgcIBgAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Oh='Ohiya:BAAANQABCgIIAgAAAA==.Ohiyaa:BAAANQADCgQIBAAAAA==.',
Or='Orcboken:BAAANQAECgMIBAAAAA==.Orezn:BAAANQAECgQICgAAAA==.Oriner:BAAANQABCggIEAAAAA==.',
Os='Oshx:BAAANQADCgEIAQAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Painting:BAAANQAECgEIAQABNQAECgkJJgAoAG4fAA==.Pallypusher:BAAANQADCgQICAAAAA==.Papiace:BAAANQAECgYIEAABNQAECgoKYgAFAPUfAA==.Pato:BAABNQAECn8UAAMHAAgKnBxVeQAsAgAHAAgKnBxVeQAsAgAOAAEKBhhlQQA6AAAAAA==.',
Pi='Picklenipz:BAAANQADCgQICgAAAA==.Piesniper:BAAANQABCgIIAgABNQADCgYIDAANAAAAAA==.Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAACNQAFFH8VAAISAAcK+g2HBQB0AQASAAcK+g2HBQB0AQA1AAQKf1cAAhIACgpYIXAGAAoDABIACgpYIXAGAAoDAAAA.',
Po='Popedragon:BAAANQAECgEIAgAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Prayihealu:BAAANQAECgcICQAAAA==.Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAABNQAECn8sAAMEAAoKthpELgBFAgAEAAkK6xVELgBFAgAWAAkKAxksKwA9AgAAAA==.Promisa:BAAANQAECggICAAAAA==.Promise:BAAANQAFFAEIAQAAAA==.Prophets:BAAANQADCgMIBQAAAA==.Pryome:BAABNQAECn8YAAIdAAgKmQpL3gDLAQAdAAgKmQpL3gDLAQABNQAECgoKQAALANoYAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQAECgIIAgAAAA==.Punkz:BAAANQADCgYICAABNQAECggIGQAKAPwbAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgYICwAAAA==.',
Py='Pyromortis:BAAANQAECgcIEQABNQAECgoKSwARAJEZAA==.Pytorch:BAABNQAECn+PAAIdAAkKVCMaDgAbAwAdAAkKVCMaDgAbAwAAAA==.',
['Pø']='Pø:BAAANQAECgQIBAAAAA==.',
Qu='Queelex:BAAANQAECgcIDAABNQAECggIGQAKAPwbAA==.Quigzz:BAACNQAFFH8NAAIEAAYKkxFdDQA3AQAEAAYKkxFdDQA3AQA1AAQKf0QAAgQACgooIV8GABsDAAQACgooIV8GABsDAAAA.Quinnie:BAABNQAECn8ZAAMVAAoKQRk8IADnAAAdAAgKLRYRzAARAQAVAAUKqBQ8IADnAAABNQAFFAIIAgANAAAAAA==.',
Ra='Raganarok:BAAANQAECgIIAgAAAA==.Rahja:BAAANQAECggIDAAAAA==.Ramms:BAAANQAECggICAAAAA==.Ramss:BAAANQAECggIEAAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECgoKNAAbABQSAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQAECggIDgAAAA==.Rellans:BAAANQAECgYIBgAAAA==.Resa:BAAANQAECgYIEgAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ri='Ricasti:BAAANQAECgYICwAAAA==.Ritsu:BAAANQAECgcIDgAAAA==.',
Ro='Robinsonic:BAABNQAECn8yAAIUAAoKNx96BwDTAgAUAAoKNx96BwDTAgAAAA==.Rokenn:BAAANQADCggICAAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.Rosetastoned:BAAANQADCgIIAgAAAA==.',
Ru='Rukiè:BAAANQAFFAEIAQAAAA==.Runmyrkr:BAAANQAECgcIEgAAAA==.',
['Rô']='Rôbert:BAABNQAECn8pAAITAAoKzRFZbwDxAQATAAoKzRFZbwDxAQAAAA==.',
Sa='Saberyn:BAABNQAECn80AAIXAAoKOhi9BgBTAgAXAAoKOhi9BgBTAgAAAA==.Sacredsassy:BAAANQAECgUICwABNQAECgoKHwAoAIwIAA==.Saenya:BAABNQAECn8YAAISAAcK7RWWKgDSAQASAAcK7RWWKgDSAQAAAA==.Sageofwampa:BAAANQADCggICgAAAA==.Sahra:BAAANQADCggICAAAAA==.Samavanas:BAAANQADCggICwAAAA==.Sassynova:BAAANQADCgYICQABNQAECgoKHwAoAIwIAA==.',
Sc='Schvitz:BAABNQAECn8nAAIGAAoKsRW/dwDOAQAGAAoKsRW/dwDOAQAAAA==.Scopeftis:BAABNQAECn8gAAIPAAoKEx+MJQCoAgAPAAoKEx+MJQCoAgAAAA==.',
Se='Seano:BAAANQAECgMIAwAAAA==.Seberology:BAABNQAECn8pAAIYAAkKEBJ8SgA+AgAYAAkKEBJ8SgA+AgAAAA==.Segagamecube:BAAANQADCgMIAwAAAA==.Selkieslock:BAAANQAECgcIBwAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.Seraphies:BAAANQADCgQIAgAAAA==.Sergal:BAAANQADCggICAABNQAECgMICQANAAAAAA==.',
Sh='Shaco:BAAANQAECgMIAwAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgQICQABNQAECggIEgANAAAAAA==.Shamownage:BAABNQAECn9AAAMLAAoK2hicKwAvAgALAAkKphqcKwAvAgAKAAoKrRYFRwD3AQAAAA==.Shankyews:BAAANQADCgQJBAAAAA==.Sheev:BAAANQADCgEIAQAAAA==.Shepling:BAACNQAFFH8KAAIcAAUKMg2WEwAhAQAcAAUKMg2WEwAhAQA1AAQKfxQAAhwACAp7FfZGAN0BABwACAp7FfZGAN0BAAAA.Shifterella:BAAANQAECgQIBAAAAA==.Shifu:BAACNQAFFH8LAAIIAAQKyBcTCgDUAAAIAAQKyBcTCgDUAAA1AAQKfx8AAwgACgrzHvAaAGYCAAgACAr+IfAaAGYCACQABwqEFU4VAI8BAAAA.Shivàh:BAACNQAFFH8QAAMPAAYKRBfkBwCbAQAPAAUKOBrkBwCbAQAQAAQKdhHDEADTAAA1AAQKf0IABBAACgpqJXcCAG0DABAACgpqJXcCAG0DABwACQrCHIMZADcCAA8AAwqkIViDABEBAAAA.Shneezleberg:BAABNQAECn81AAMHAAoKNR/OIADBAgAHAAoKNR/OIADBAgAXAAQKvgrJIwCVAAAAAA==.Shädowcraft:BAAANQADCgUIBQAAAA==.',
Si='Sildormi:BAAANQAECgEIAQAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAABNQAECn8/AAIDAAoKshLFGABOAgADAAoKshLFGABOAgAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Skiddlywinks:BAAANQAECgMIAwABNQAECgoKHAAFAPEUAA==.Sko:BAABNQAECn8fAAIHAAkKPRkKVwCGAgAHAAkKPRkKVwCGAgAAAA==.Skyscreamer:BAAANQAECggICAAAAA==.Skár:BAAANQADCggICwAAAA==.',
Sl='Sladak:BAAANQAECgIIAgAAAA==.Slimjimm:BAAANQAECgUIBgABNQAECgoKIQAdAGwiAA==.Slutdraggin:BAAANQAECgEIAQAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakyky:BAAANQADCggIEgAAAA==.Sneakymoomoo:BAAANQADCgYJBgABNQAECgoKSwARAJEZAA==.Snipagooly:BAAANQADCgcIBwAAAA==.Snowyrain:BAAANQAECgUICgAAAA==.',
So='Sojourner:BAABNQAECn8UAAMLAAcKJhErgwCdAQALAAYK/Q8rgwCdAQAKAAcK0BBzhgB6AQABNQAECgoKJAAYALEaAA==.Solanum:BAAANQADCgQIBAABNQAECgQIBAANAAAAAA==.Solkar:BAAANQADCgcJCwAAAA==.Solo:BAACNQAFFH8IAAITAAQKKQTrHwCeAAATAAQKKQTrHwCeAAA1AAQKf0AAAxMACgpeHh84AIUCABMACgpeHh84AIUCABkAAQoAAP58AAAAAAAA.Soupsandwich:BAAANQAECgMIBAAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
Sp='Spartacùs:BAAANQADCgEIAQABNQAECgUICwANAAAAAA==.',
St='Stagg:BAABNQAECn80AAIdAAoKRBdjnABIAgAdAAoKRBdjnABIAgAAAA==.Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQADCgcIEQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.Stkk:BAAANQAECggICAAAAA==.Stonedkritz:BAAANQABCgQIAwAAAA==.',
Su='Sulfornarn:BAAANQAECgMIAwABNQAECgkJKAAdALIOAA==.Sunarii:BAABNQAECn8cAAISAAkKEBZEIQAtAgASAAkKEBZEIQAtAgAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.Superbroke:BAAANQAECgEIAQAAAA==.Superpoor:BAAANQABCgEIAQAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
['Sà']='Sàviorself:BAAANQAECgIIBQAAAA==.',
['Sý']='Sýlvanàs:BAAANQAECgYIBgAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAABNQAECn8zAAIlAAoKawsgEwDKAQAlAAoKawsgEwDKAQAAAA==.Talwayn:BAAANQADCgUIDwABNQAECgoKHAAFAPEUAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQAECgQIBwAAAA==.Taurtellini:BAAANQAECgQICwAAAA==.Tazoo:BAABNQAECn8hAAMfAAkKDgOPIgAzAQAfAAkKDgOPIgAzAQAKAAEKygi4KQEkAAAAAA==.',
Te='Teamfluffer:BAAANQADCgUICQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Tehzew:BAAANQADCggIDAAAAA==.Tehzoo:BAAANQADCgIIAgAAAA==.Tehzuurmx:BAAANQADCggIDAAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQABCgMIAwAAAA==.Terebitha:BAAANQABCgMIAgAAAA==.Teruulos:BAAANQAECgUIDgAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAABNQAECn8sAAIRAAoKkh3VNACUAgARAAoKkh3VNACUAgAAAA==.Thadiusx:BAAANQABCgUIBQAAAA==.Tharon:BAABNQAECn8kAAIGAAoKiBUeZgBIAgAGAAoKiBUeZgBIAgAAAA==.Thebigboom:BAACNQAFFH8HAAIUAAIKxgwBCABoAAAUAAIKxgwBCABoAAA1AAQKf0EAAhQACgpxHkMLAIgCABQACgpxHkMLAIgCAAAA.Thecarter:BAAANQAECgIIAgAAAA==.Theghoulest:BAABNQAECn8ZAAMcAAkK6g/5KgCsAQAcAAkKOA/5KgCsAQAPAAMKVw1kVQCwAAAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.Threnody:BAABNQAECn8wAAMJAAgKuQ5aIQBiAQAJAAgK9Q1aIQBiAQAGAAIKDBMtNAGAAAAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgUIBQANAAAAAA==.Tichemort:BAAANQAECgUIBQAAAA==.Tigerchimon:BAAANQADCgUIBQABNQAECgoKQAALANoYAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAACNQAFFH8KAAMhAAMKWA3uAACOAAAhAAMKWA3uAACOAAAdAAIK5AOaUACBAAA1AAQKf2AAAyEACgoxIoQAABcDACEACgoxIoQAABcDAB0ABAprCgKQAacAAAAA.',
Tr='Trapscallion:BAAANQAECgQIEAAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Tratraz:BAAANQAECggICwAAAA==.Treeknight:BAABNQAECn8fAAIPAAgKOBRISQDxAQAPAAgKOBRISQDxAQAAAA==.Treelimbs:BAAANQAECgcIDgAAAA==.Treemoo:BAAANQAECgEIAQABNQAECgoKSwARAJEZAA==.Tridity:BAAANQAECgYIDwAAAA==.Trollolollz:BAAANQAECgIIAwAAAA==.',
Ts='Tsuuna:BAABNQAECn9DAAQHAAoK9CKCIwCzAgAHAAoKcSKCIwCzAgAXAAEK8yJnKQBlAAAOAAEKAABxPgBIAAAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.Turtleqtx:BAAANQAECgQIBAAAAA==.',
Tw='Twohalfs:BAAANQADCgMIAwAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQAECgIIBAANAAAAAA==.Tylandon:BAAANQAECgYICQAAAA==.Tyralthas:BAAANQADCgQIAwAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgIJAwAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Un='Unavaluable:BAAANQAECgcICQAAAA==.Ungodlyy:BAABNQAECn8aAAMbAAkK7AVspAANAQAbAAkK7AVspAANAQAjAAIKDgKVagBMAAAAAA==.Untöuchable:BAABNQAECn9cAAMTAAoKtyT9CwBDAwATAAoKtyT9CwBDAwAYAAIKIwgz8gA4AAAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Va='Vanthelos:BAAANQADCgQIBQAAAA==.',
Ve='Velachlan:BAAANQAECgYIEwAAAA==.Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAABNQAECn9RAAQmAAoKJx2oAQBqAgAmAAoK+xyoAQBqAgAEAAkKThgNNQAnAgAWAAMK9RLXfQC8AAAAAA==.Verxl:BAABNQAECn8yAAIdAAgKHBgwegC4AQAdAAgKHBgwegC4AQAAAA==.Verypoor:BAAANQAECgMIBQAAAA==.',
Vi='Vihn:BAAANQADCgYIBgAAAA==.',
Vo='Voidnyou:BAAANQADCgQICAAAAA==.Volumes:BAAANQAECgUIBwAAAA==.Volund:BAABNQAECn9DAAIfAAoKWQhaGwCuAQAfAAoKWQhaGwCuAQAAAA==.',
Vy='Vynsong:BAABNQAECn8mAAIYAAkKMiBRIQDoAgAYAAkKMiBRIQDoAgAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAANAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFgAAAA==.Watchmebløck:BAAANQAECgQIBAAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBgAAAA==.Wetmonk:BAAANQAECgcIDQAAAA==.',
Wh='Whoyerdaddy:BAAANQAECgQICgAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Wiggletang:BAAANQAECgEIAQAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAABNQAECn82AAMKAAoKJBJ3WwD9AQAKAAoKJBJ3WwD9AQALAAgKeBFdqwA9AQAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.',
Wo='Wombatman:BAAANQAECgYIDwAAAA==.Wong:BAAANQAECgUIBgAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCggICAAAAA==.',
Xo='Xoron:BAAANQAECgQIBAAAAA==.',
Xu='Xugos:BAABNQAECn8fAAIbAAoKGRgbZgAoAgAbAAoKGRgbZgAoAgAAAA==.',
Xz='Xzeena:BAAANQADCgEIAQAAAA==.',
Ya='Yatagarasu:BAAANQAECggIAgAAAA==.',
Ye='Yenafer:BAAANQADCggICAAAAA==.',
Yo='Yochill:BAAANQAECgIIAgABNQAECgYICgANAAAAAA==.Yolokin:BAAANQADCgcIGAAAAA==.Yooper:BAAANQADCgcIBgAAAA==.Yota:BAAANQAECgIIAwAAAA==.',
Yr='Yrgg:BAAANQAECgYIEQAAAA==.',
Yt='Ytgamezoned:BAAANQADCgQIBAAAAA==.',
Yu='Yuna:BAAANQABCggIEAAAAA==.',
Za='Zadanthra:BAABNQAECn8cAAIFAAoK8RRVDQB4AQAFAAoK8RRVDQB4AQAAAA==.Zalektra:BAAANQADCgQIBAAAAA==.Zapadin:BAABNQAECn8tAAITAAoKZhIlggAkAgATAAoKZhIlggAkAgAAAA==.Zaphodè:BAAANQAECgUICQAAAA==.',
Ze='Zeenie:BAACNQAFFH8GAAIdAAIKagcwPQCBAAAdAAIKagcwPQCBAAA1AAQKfxQAAh0ACQrwBdauAEcBAB0ACQrwBdauAEcBAAAA.Zeljusticar:BAAANQADCgEIAgAAAA==.Zephian:BAAANQAECgMIAwAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAABNQAECn8gAAQpAAgKAAubCwCFAQApAAgKAAubCwCFAQARAAYK2wN8sQACAQASAAUKNgWpUQDKAAAAAA==.Zotoperen:BAABNQAECn8xAAMkAAoK/iBkAwBdAwAkAAoK/iBkAwBdAwAIAAMKFhHoUgClAAAAAA==.',
Zy='Zylergy:BAABNQAECn8cAAITAAoKPgl23wBcAQATAAoKPgl23wBcAQAAAA==.',
['Zì']='Zìfu:BAAANQADCggICQAAAA==.',
['Àv']='Àvicant:BAAANQAECgUJBwABNQAFFAQICAAGAFMiAA==.',
['Áp']='Ápex:BAAANQAECgMIAwAAAA==.',
['Än']='Ändo:BAABNQAECn8VAAIGAAUK4Bug1wBRAQAGAAUK4Bug1wBRAQAAAA==.',
['Äy']='Äy:BAAANQADCgUIBwAAAA==.',
['Çy']='Çyrin:BAABNQAECn8wAAMYAAkKsBMXSgA/AgAYAAkKsBMXSgA/AgATAAEK5QhHpwEzAAAAAA==.',
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
