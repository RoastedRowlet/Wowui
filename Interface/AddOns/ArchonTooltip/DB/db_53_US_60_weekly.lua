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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Mage-Arcane','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Unknown-Unknown','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Paladin-Protection','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Shaman-Enhancement','Druid-Guardian','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Evoker-Preservation','Rogue-Outlaw','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Frost','Warrior-Fury','Priest-Discipline','Druid-Feral','Mage-Fire',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abssorath:BAAANQADCgYICQAAAA==.',
Ae='Aerouant:BAABNQAECn82AAMBAAoK1RaXBgBWAgABAAkKeReXBgBWAgACAAkKaQ89BwCsAQAAAA==.',
Ai='Aidix:BAAANQADCggIFQAAAA==.Aimassist:BAAANQAECgQIBAAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAABNQAECn80AAIDAAoK+R15DwDfAgADAAoK+R15DwDfAgAAAA==.Alexstanna:BAAANQAECgUIBwAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.Alwaysbroke:BAAANQAECgYIBgAAAA==.',
An='Andrena:BAAANQAECgUICQABNQAECggIIQAEAJEVAA==.Andycat:BAAANQAECgEIAQAAAA==.Annarchy:BAAANQADCgQIBAAAAA==.Antagony:BAAANQAECgUIBQAAAA==.Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAABNQAECn8wAAIFAAoKQBTJCQBEAgAFAAoKQBTJCQBEAgAAAA==.Anthross:BAABNQAECn8mAAIGAAkKdQ1/hgD+AQAGAAkKdQ1/hgD+AQAAAA==.',
Ap='Apollovon:BAABNQAECn8oAAIHAAkKeyGkLQAGAwAHAAkKeyGkLQAGAwAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanemage:BAAANQADCgYIBwAAAA==.Arcanenug:BAAANQADCgQJBAAAAA==.Arcbnonez:BAAANQAECgQIBAAAAA==.Arguxx:BAAANQAECggIDwAAAA==.Armiggy:BAABNQAECn8/AAIIAAoKxxK1EQDKAQAIAAoKxxK1EQDKAQAAAA==.Aro:BAACNQAFFH8TAAMJAAcKcCALCgCiAQAJAAYKYB8LCgCiAQAGAAIK4huxIACwAAA1AAQKfy4AAwkACgqwJHoOAOQBAAkACApRI3oOAOQBAAYABgrQI6OZANQBAAAA.Arrowraen:BAABNQAECn8rAAIGAAkK/SMfBwCkAwAGAAkK/SMfBwCkAwAAAA==.',
As='Asavera:BAAANQAECgUIBwAAAA==.Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgYJBgAAAA==.',
Au='Audomere:BAABNQAECn8rAAMKAAoKpwxPNwC/AQAKAAoKpwxPNwC/AQALAAIKlgFXLQE7AAAAAA==.Auurwarr:BAAANQAECgUIBQAAAA==.',
Av='Avawrath:BAAANQAECggIEQAAAA==.Avelm:BAAANQAECggIAwAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgoKLwAFAPkdAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Ballstench:BAAANQADCgIIAgAAAA==.Barbåtos:BAAANQAECgEIAQAAAA==.Baskthyr:BAAANQADCgQIBAAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAABNQAECn8XAAIMAAgKSBQ1OQAmAgAMAAgKSBQ1OQAmAgABNQADCgUIBQANAAAAAA==.Bearbomblolz:BAAANQADCgQIBQABNQAECggIFAAFADEUAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQADCgQICAAAAA==.Beastbane:BAAANQAECggIEQAAAA==.Beastly:BAAANQAECgYICgAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAABNQAECn83AAMHAAoKuhiyRQC4AgAHAAoKuhiyRQC4AgAOAAgKVhTyFQDJAQAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAABNQAECn9TAAMPAAgKrRc6QgATAgAPAAgKoBc6QgATAgAQAAcKtQ4AWQBHAQAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgANAAAAAA==.Bewslee:BAAANQAECgEIAwABNQAECgMIAwANAAAAAA==.Bexx:BAAANQADCggJGQAAAA==.',
Bi='Biblehumping:BAABNQAECn83AAMRAAoKhxaZSgBFAgARAAoKhxaZSgBFAgASAAYKEQkMQgAhAQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgcIDQANAAAAAA==.Bigbonks:BAAANQAECgQIBgAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.Billclintun:BAAANQADCgcIDQAAAA==.',
Bl='Blackplague:BAAANQADCgQIBQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQAECggICwAAAA==.Blueshamoo:BAAANQAECgEJAQAAAA==.Blupl:BAAANQABCgYIBgAAAA==.Blãezer:BAAANQAECgQIAwAAAA==.',
Bo='Bonex:BAAANQAECgEIAgAAAA==.Boomshroom:BAAANQAECgMIBAABNQAECgoKMwAIABceAA==.Bootsie:BAAANQADCggICAAAAA==.',
Br='Brewtoe:BAABNQAECn8dAAIIAAgKjBL/EQDFAQAIAAgKjBL/EQDFAQAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Bruegard:BAAANQADCgIIAgAAAA==.Bruneau:BAAANQABCgUIBQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAcIFgAJAPoaAA==.',
Bu='Bubblemehard:BAABNQAECn8cAAITAAgKMhibewAzAgATAAgKMhibewAzAgAAAA==.Bushky:BAAANQAECgMIAwAAAA==.',
By='Byahnbreath:BAACNQAFFH8FAAIQAAIK7waxGAB7AAAQAAIK7waxGAB7AAA1AAQKfyQAAhAACgo0Gx4TAEQCABAACgo0Gx4TAEQCAAAA.',
Ca='Cakeiko:BAAANQAECgQIBQAAAA==.Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Carolaine:BAAANQADCgQIAgAAAA==.Casmiralda:BAAANQABCgUIBQAAAA==.Castielx:BAABNQAECn8ZAAIUAAcKthIcQQDHAQAUAAcKthIcQQDHAQAAAA==.Catnips:BAAANQAECgQIBgABNQAECgoKNwARAIcWAA==.',
Ce='Celestraza:BAAANQAECgMIAwAAAA==.Celirra:BAABNQAECn80AAIPAAoKDyFvDwA7AwAPAAoKDyFvDwA7AwAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAABNQAECn8qAAIHAAoKAwpJewAfAQAHAAoKAwpJewAfAQAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAABNQAECn8WAAMUAAgKKxyANwD6AQAUAAcKKxyANwD6AQAVAAEKAAA3TwBDAAAAAA==.Chokma:BAABNQAECn8hAAILAAkK9BOKZgDtAQALAAkK9BOKZgDtAQAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAABNQAECn8bAAMWAAcKJQ93TABkAQAWAAcKJQ93TABkAQAXAAEKlAQGfgAfAAAAAA==.',
Ci='Cinnaa:BAAANQAECgUICQAAAA==.',
Cl='Clawdog:BAAANQADCgIIAgABNQAECgIIBAANAAAAAQ==.Clawwz:BAAANQAECgMIAwAAAA==.Cleisthenes:BAAANQAECgEIAQAAAA==.Clors:BAABNQAECn8kAAIDAAkKPRwWDQBgAgADAAkKPRwWDQBgAgAAAA==.',
Co='Compressed:BAAANQABCgIIAgAAAA==.Conflux:BAAANQADCggIFAAAAA==.',
Cr='Crager:BAAANQAECgUIDgAAAA==.Crawlah:BAAANQADCggIDgAAAA==.Crazegideon:BAAANQABCgIIAgAAAA==.Crazespawnz:BAAANQABCgIIAgAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIEQAAAA==.',
Cy='Cyberfairy:BAAANQAECgEJAQAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQAECgEIAQAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgcICAAAAA==.Dalìnar:BAAANQAECgYICwAAAA==.Damadafacker:BAABNQAECn8fAAIHAAoKzRXZaABVAgAHAAoKzRXZaABVAgAAAA==.Darkclôud:BAAANQAECgQIBAAAAA==.Darkkatriden:BAAANQADCgYIBgABNQAECgYIFwAYALgKAA==.Darklia:BAABNQAECn8XAAIYAAYKuArxlQDEAAAYAAYKuArxlQDEAAAAAA==.Darthjae:BAABNQAECn9JAAMZAAkKTBrpQQD1AQAZAAkKTBrpQQD1AQAQAAEKAABQvgAfAAAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAABNQAECn8qAAIaAAoKZhrUAwDBAgAaAAoKZhrUAwDBAgAAAA==.Davina:BAAANQADCgcIBwABNQAFFAQIBwATAAMOAA==.Daïn:BAAANQAECgcICgAAAA==.',
De='Deadestmoonb:BAAANQADCgIIBAAAAA==.Deathalimon:BAABNQAECn8zAAQPAAkKZxrUUgDHAQAPAAgKnRTUUgDHAQAZAAcK9Ri8UgCqAQAQAAEKTBBerQA0AAABNQAECgoKMAAKAOoVAA==.Deathvoid:BAAANQADCgQIAQAAAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQADCgUIBQAAAA==.Demonarian:BAAANQAECgcICQABNQAECgoKMAAKAOoVAA==.Demonicnut:BAAANQAECgMIAwABNQAECgkJIQALAPQTAA==.Demonpotato:BAAANQADCggJCAAAAA==.Denardath:BAAANQADCgUIBQAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAABNQAECn8dAAMLAAkK+guTogBQAQALAAcKJAyTogBQAQAKAAgKMQqoVABFAQAAAA==.Deroc:BAABNQAECn8eAAITAAkKYQfU4ABaAQATAAkKYQfU4ABaAQAAAA==.Deáthtáxi:BAAANQAECggICAAAAA==.',
Di='Digweeds:BAABNQAECn8XAAIbAAkKrRpRCgAFAgAbAAkKrRpRCgAFAgABNQAFFAEIAQANAAAAAA==.Dinfarmer:BAAANQAECgUIBwAAAA==.Dirtycheese:BAAANQAECgYICwAAAA==.',
Dj='Djgha:BAAANQAECgIIBAAAAA==.',
Dm='Dmptruckdona:BAAANQAECgEIAQAAAA==.Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQAECgEIAwAAAA==.Doombap:BAAANQAFFAMIAwAAAA==.Dorunter:BAABNQAECn8sAAMJAAkKgBNMMwCzAQAJAAcKYBJMMwCzAQAGAAQKHxT70QCPAAAAAA==.Dottíe:BAAANQAECgUIBwAAAA==.Doubledosage:BAABNQAECn8ZAAIGAAYKAgoPngDzAAAGAAYKAgoPngDzAAAAAA==.',
Dr='Dragonbnonez:BAAANQAECgQIBAAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Drakujin:BAAANQADCgMIBQAAAA==.Drboomboom:BAABNQAECn8dAAIEAAkKDQquhQA3AQAEAAkKDQquhQA3AQAAAA==.Drdoitall:BAAANQAECgYICwAAAA==.Dreadnpain:BAAANQADCgQIBAAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIAwABNQAFFAcIFQAQAMEfAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Du='Duuid:BAABNQAECn8vAAIcAAkKdRssBwB2AgAcAAkKdRssBwB2AgAAAA==.Duukwan:BAABNQAECn8VAAMRAAkK8BmNJgDQAgARAAkK8BmNJgDQAgASAAEKjhGqQQBDAAAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.Elysiá:BAAANQADCggICAAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAACNQAFFH8QAAQdAAUKohlAAwCkAAAdAAIKtBdAAwCkAAAeAAIKfR0iBQCaAAAYAAIK6AFMLQAAAAA1AAQKfzAAAx4ACgpEJaoDALYCAB4ACApoJaoDALYCAB0AAwqzJHEFADkBAAAA.',
Er='Erayr:BAAANQAECgYIEAABNQAECgkJFQAEAM8MAA==.Ericolson:BAABNQAECn8qAAIHAAoKLhYWQADPAQAHAAoKLhYWQADPAQAAAA==.Erze:BAAANQAECgUICQAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evilhealer:BAAANQAECgMIBgAAAA==.Evosolz:BAEANQAECgcIEgABNQAECggIDQANAAAAAA==.Evé:BAAANQAECgMIAwABNQAECgoKMwAIABceAA==.',
Ey='Eyehealu:BAAANQADCgIIAgABNQAECgoKKAAeALoPAA==.',
Ez='Ezzartkal:BAAANQAECgEIAQAAAA==.',
Fa='Faeloria:BAAANQADCggICgAAAA==.Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgkJSQAZAEwaAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgoKMQAfAP4gAA==.Fefra:BAAANQADCgQIBAAAAA==.Felicious:BAAANQAECggIEQAAAA==.Fengshui:BAAANQADCggIGwAAAA==.Feralco:BAAANQAECgYICwAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fixiation:BAAANQAECgEIAQAAAA==.Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Flashdance:BAAANQADCggIFAAAAA==.Fleepo:BAAANQAECgIIAwAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAABNQAECn82AAMgAAoKuw1mHQD3AQAgAAoKuw1mHQD3AQACAAEKAAC7PgAvAAAAAA==.Flöör:BAAANQADCgUIBQAAAA==.',
Fu='Fullmetal:BAAANQAECgQIDAAAAA==.Funkadelfic:BAAANQAECgYIBwAAAA==.',
['Fé']='Fénrír:BAAANQADCggIDwABNQAECgQIBAANAAAAAA==.',
['Fò']='Fòxxy:BAAANQAECgMIAQAAAA==.',
Ga='Galadri:BAABNQAECn8ZAAMKAAgK/BuUQQBaAgAKAAgK/BuUQQBaAgALAAUKCxAXwwAMAQAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIEAAAAA==.Geartryx:BAAANQADCggIDQAAAA==.Geodood:BAAANQAECgcICgAAAA==.',
Gh='Ghoshshadow:BAAANQADCgYIFQAAAA==.Ghostinz:BAABNQAECn8WAAIHAAcKkQyidAAuAQAHAAcKkQyidAAuAQAAAA==.',
Gi='Gimpripper:BAAANQAECgcICQAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggJIAAZAGcaAA==.Globalcold:BAABNQAECn8bAAIHAAgKLBoLdAA4AgAHAAgKLBoLdAA4AgAAAA==.Globb:BAABNQAECn8wAAIHAAgKVxSIlwDhAQAHAAgKVxSIlwDhAQAAAA==.Globius:BAABNQAECn8yAAITAAoKdhtNSgC2AgATAAoKdhtNSgC2AgAAAA==.Gloriouscole:BAABNQAECn8UAAITAAYKBCIhdgBBAgATAAYKBCIhdgBBAgAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gooly:BAAANQADCgIIAgAAAA==.Goombit:BAAANQADCgEIAQAAAA==.',
Gr='Greekorc:BAAANQABCgYJBwAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Grimby:BAAANQAECggIAwAAAA==.Grimdisney:BAAANQADCggIDgAAAA==.Groceries:BAAANQADCgMIAwAAAA==.Gromol:BAAANQADCggIHwAAAA==.Grumby:BAAANQAECgIIBAAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQAECgQIBAAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQAECgQIBgAAAA==.Hatebrêêd:BAAANQADCgQIBQAAAA==.',
He='Healman:BAAANQADCgcIGQAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgcIDAAAAA==.Heiden:BAAANQADCgYJBgAAAA==.Hel:BAAANQAECgEIAQAAAA==.Hellyas:BAAANQAECgUICQAAAA==.Herbs:BAAANQAECgEIAQABNQAECgoKPAAhAH4ZAA==.Herenorthere:BAABNQAECn8xAAMSAAoKgBr6GgBxAgASAAgKEhz6GgBxAgARAAgKgxs3dQC8AQABNQAFFAQICgAeAOgVAA==.Hermippe:BAAANQAECgMIAwAAAA==.Hexstraits:BAACNQAFFH8GAAIZAAIKRBMsIACIAAAZAAIKRBMsIACIAAA1AAQKfycAAhkACgrHIiMQACwDABkACgrHIiMQACwDAAAA.',
Hi='Hia:BAACNQAFFH8TAAIZAAUKBR+hCgCtAQAZAAUKBR+hCgCtAQA1AAQKfz8AAxkACgq2Ih4LAFsDABkACgq2Ih4LAFsDABAAAgpmAZCYAA8AAAAA.Highriskbr:BAAANQAECggICAAAAA==.Hitlist:BAAANQADCgUJBQAAAA==.',
Ho='Holycow:BAAANQAECgIIBAAAAA==.Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBgAAAA==.Hondaimpala:BAAANQAECgQIBgABNQAECgkJSQAZAEwaAA==.Hoofmaster:BAAANQABCgMIAwAAAA==.Hordenfel:BAAANQADCggICAAAAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huffy:BAAANQAECggIDQABNQAECgoKNAAHANQiAA==.Huffyy:BAABNQAECn80AAIHAAoK1CKkDAABAwAHAAoK1CKkDAABAwAAAA==.Huhdean:BAABNQAECn8hAAMQAAgKDCQMHACqAgAQAAcKsiMMHACqAgAPAAQKzyF1hQALAQAAAA==.Hulxamus:BAAANQAECgYICgAAAA==.Hunterramen:BAAANQADCgEJAQAAAA==.Hunterz:BAAANQAECgQICQAAAA==.',
['Hé']='Héåthcliff:BAACNQAFFH8HAAMTAAQKSRQzDADkAAATAAQKSRQzDADkAAAXAAEKqA2vEQA9AAA1AAQKf0sAAxcACgoTI9QEAGcDABcACgotIdQEAGcDABMACgprIJ8eAJUCAAAA.',
Ic='Icyblaze:BAAANQAECggIEAAAAA==.',
Id='Idareu:BAABNQAECn8bAAIMAAgKaQXrhwC0AAAMAAgKaQXrhwC0AAAAAA==.',
If='Ifstar:BAAANQAECgMIBAAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICQANAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQAECgUIBgAAAA==.Issalis:BAAANQADCgYIBgAAAA==.',
It='Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgcIDQAAAA==.',
Iz='Izonie:BAAANQAECgUICQABNQAFFAQICwALAFsVAA==.',
Ja='Jaaric:BAAANQAECgQIBAAAAA==.Jaimerrek:BAABNQAECn8VAAIEAAkKzwz5bABtAQAEAAkKzwz5bABtAQAAAA==.Jainalynn:BAAANQAECgMIAwAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAABNQAECn84AAMDAAoKUg9fHQB3AQADAAgKxwxfHQB3AQAMAAgKPQShRQCtAAAAAA==.',
Jd='Jdarkside:BAABNQAECn8WAAIFAAYKswaDHwDNAAAFAAYKswaDHwDNAAAAAA==.',
Je='Jebediahmoon:BAAANQAECggIEAABNQAECgkJSQAZAEwaAA==.Jeremmiah:BAAANQADCgcIEwAAAA==.',
Jh='Jhacobo:BAABNQAECn8sAAIMAAoKcxfwMQBTAgAMAAoKcxfwMQBTAgAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jonnyrage:BAAANQAECgIIAgAAAA==.Jorkinit:BAABNQAECn8fAAIEAAoKfxQhgwA8AQAEAAoKfxQhgwA8AQAAAA==.',
Jr='Jragon:BAABNQAECn8jAAIYAAgKbQoFlwCtAQAYAAgKbQoFlwCtAQAAAA==.',
Ju='Judis:BAAANQABCgYICwAAAA==.Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAABNQAECn8gAAIEAAoKIhwlZgCyAgAEAAoKIhwlZgCyAgAAAA==.Junipur:BAAANQAECgMICQAAAA==.',
Jx='Jxxy:BAACNQAFFH8MAAMGAAQKYRsAFQAXAQAGAAQKYRsAFQAXAQAJAAIKjxAxHACPAAA1AAQKfyQAAwYACgrRIDEqADgCAAYACgpQIDEqADgCAAkAAwrvGA0xAJcAAAE1AAUUBAoMAAYAYRsA.',
['Jú']='Júnjúnwälä:BAABNQAECn8gAAIDAAoKrSMHDgDwAgADAAoKrSMHDgDwAgAAAA==.',
Ka='Kalories:BAAANQAECgUICwAAAA==.Kalvoid:BAAANQAECgQIBAABNQAECgUICwANAAAAAA==.Kandance:BAAANQAECgcIEgABNQAFFAIIAgANAAAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ke='Kelvintwo:BAAANQADCgQIAwAAAA==.',
Ki='Kimbopable:BAAANQAECgUIBQABNQAECgkJSQAZAEwaAA==.Kittyÿ:BAAANQAECgYICwAAAA==.',
Kn='Knurl:BAAANQADCgMIAwAAAA==.',
Ko='Korak:BAAANQADCgUIBQABNQADCgYIBgANAAAAAA==.Korgh:BAAANQAECgEIAQAAAA==.Kosari:BAAANQAECgMIAwABNQAECgQIBAANAAAAAA==.',
Kr='Krystall:BAABNQAECn8oAAIeAAoKug/NBwAbAgAeAAoKug/NBwAbAgAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAABNQAECn8zAAMIAAoKFx7zEgDEAgAIAAoKFx7zEgDEAgAiAAIKjQpSKwBQAAAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQAECgIIAgABNQAECgUICwANAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgUICwANAAAAAA==.',
['Kì']='Kìngknìghts:BAABNQAECn8aAAMQAAcK6wysOQA0AQAQAAcKQQqsOQA0AQAPAAQKYA+RQQCzAAAAAA==.',
La='Lalphas:BAABNQAECn81AAMYAAoKRg/CZQApAgAYAAoKRg/CZQApAgAdAAEKxgONhAAmAAAAAA==.Lanthos:BAABNQAECn9DAAIjAAoKkyBMBADsAgAjAAoKkyBMBADsAgAAAA==.Lapulapu:BAAANQADCgYIBgAAAA==.Larthal:BAAANQAECgQIBgAAAA==.Latinpapi:BAABNQAECn8qAAMTAAoKVxRydABFAgATAAoKVxRydABFAgAXAAEKAAB5aQBAAAAAAA==.',
Le='Leemers:BAAANQADCgEIAQAAAA==.Leemiez:BAAANQADCgUIDgAAAA==.Leyära:BAAANQAECgIIBAAAAA==.',
Li='Lielys:BAAANQAECgIIAgABNQAECgUIFQAJAPETAA==.Lilina:BAABNQAECn8iAAMFAAgKvhjACwAQAgAFAAgKvhjACwAQAgAkAAEK9wBDcwATAAAAAA==.Liljaejae:BAAANQADCgEIAQAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Lonweh:BAAANQAECgMIBAAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgUICwABNQAECggIFgAGAGMNAA==.',
Lu='Lucith:BAABNQAECn82AAIQAAoKFiJJBgB+AwAQAAoKFiJJBgB+AwAAAA==.Luckie:BAAANQABCgQIBwABNQAFFAYIDwAWABEQAA==.Lulafairy:BAAANQAECgEJAQAAAA==.Lumador:BAAANQAECgQIBwABNQAECgcIIAASAIQUAA==.Lunatick:BAABNQAECn8uAAQQAAoKsQ7wJQChAQAQAAoK5wvwJQChAQAZAAMKzRuphwDgAAAPAAUK6wMSpwCqAAAAAA==.Lunawa:BAACNQAFFH8IAAIEAAUKSx3DGQCsAQAEAAUKSx3DGQCsAQA1AAQKf2IAAwQACgpVJs4BAGoDAAQACgpVJs4BAGoDACUAAwpLETMtAJQAAAAA.Lustbót:BAABNQAECn8bAAIEAAkKGweA6AC5AQAEAAkKGweA6AC5AQAAAA==.Luvnrdjr:BAAANQADCgYIBgAAAA==.',
Ly='Lynnai:BAAANQAECgQIBAAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAACNQAFFH8WAAIkAAYKixwOBwDPAQAkAAYKixwOBwDPAQA1AAQKfzgAAiQACgrhJM0FAJgDACQACgrhJM0FAJgDAAAA.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lí']='Líllith:BAAANQADCgYJBgAAAA==.',
['Lô']='Lôuku:BAABNQAECn80AAIYAAkK2hlCQwCIAgAYAAkK2hlCQwCIAgAAAA==.',
Ma='Maahn:BAAANQADCgcICAAAAA==.Macalob:BAAANQAECgQIBgAAAA==.Madallar:BAABNQAECn8WAAIHAAgKow9+rQCrAQAHAAgKow9+rQCrAQAAAA==.Magdagni:BAABNQAECn8ZAAIbAAcKrBHqHACVAQAbAAcKrBHqHACVAQAAAA==.Mageji:BAACNQAFFH8MAAIEAAUK8iAwIACFAQAEAAUK8iAwIACFAQA1AAQKf0UAAgQACgrGJbAIABQDAAQACgrGJbAIABQDAAE1AAMKBggGAA0AAAAA.Magepies:BAAANQAECgQIBgABNQAECgQICAANAAAAAA==.Magerella:BAAANQAECgMIAgAAAA==.Magicfurry:BAAANQAECgUICgABNQAECgoKNwARAIcWAA==.Mainveinz:BAABNQAFFH8LAAIZAAYK3wCuEACfAAAZAAYK3wCuEACfAAAAAA==.Malicelx:BAAANQAECgIIAgABNQAECggIDwANAAAAAA==.Mallgoth:BAABNQAECn8VAAIGAAYK9gVX+gAPAQAGAAYK9gVX+gAPAQAAAA==.Manohar:BAABNQAECn8wAAMKAAoKkh0tKwC2AgAKAAoKkh0tKwC2AgALAAcKzw7MggCeAQAAAA==.Mardtard:BAABNQAECn8XAAMGAAcKtx+WQQDdAQAGAAcKtx+WQQDdAQAJAAMKigksZQCWAAABNQAECgUIBgANAAAAAA==.Marximilian:BAAANQAECgMIAwAAAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIJAgAAAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medlock:BAAANQADCgYICQAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Megamango:BAAANQAECgYICgABNQAFFAMIBgAlALoaAA==.Mehiel:BAAANQAECgcIDQAAAA==.Meive:BAAANQADCgMIAwAAAA==.Menime:BAAANQADCgYIBgAAAA==.Meraxes:BAAANQAECgEIAQAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Merkén:BAABNQAECn8WAAImAAkKoBWzBAAnAgAmAAkKoBWzBAAnAgAAAA==.Metaloclypse:BAAANQADCgcIDgAAAA==.Meteas:BAAANQAECgQIBAAAAA==.Mezaryn:BAABNQAECn8aAAITAAoKxAfoEQEBAQATAAoKxAfoEQEBAQABNQAECgoKMAADAGEKAA==.Mezgrim:BAAANQAECggIAgABNQAECgoKMAADAGEKAA==.Mezzoo:BAABNQAECn8wAAIDAAoKYQr7RwD0AAADAAoKYQr7RwD0AAAAAA==.',
Mi='Midger:BAAANQADCgQIBAAAAA==.Mikitaju:BAAANQAECgEIAQABNQAECggIFAAFADEUAA==.Millic:BAABNQAECn8pAAMnAAkK/hQrBgAyAgAnAAkK/hQrBgAyAgASAAEKYQf6dgA5AAAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEJAQAAAA==.Mitzrael:BAAANQADCgYICAAAAA==.',
Mo='Moozx:BAAANQAECgEIAQAAAA==.Mosfeat:BAAANQADCggICAABNQAECgkJHgAbAC0ZAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Murrll:BAAANQAECgIIAwAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAABNQAECn8fAAIkAAgK2Ac6UQBRAQAkAAgK2Ac6UQBRAQAAAA==.Nasuadia:BAAANQADCggIIQABNQAECgoKLgAQANIcAA==.',
Ne='Necrolysis:BAAANQAECgQIBwAAAA==.Necromansorz:BAAANQAECggICAAAAA==.Nekkash:BAAANQAECgYICgAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.Newwt:BAAANQAECgcIDAAAAA==.Neytiri:BAAANQABCgQIBQAAAA==.Nezelle:BAABNQAECn8aAAIgAAkKDA1rKQBmAQAgAAkKDA1rKQBmAQABNQAECgoKPAAhAH4ZAA==.',
Ni='Nimou:BAAANQADCggIDgAAAA==.',
No='Nomaa:BAAANQADCgQIBAAAAA==.Noraice:BAAANQADCggICAAAAA==.Noris:BAAANQAECggIDwAAAA==.Norros:BAAANQAECgIIBAAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgQIDAAAAA==.Nuvostaph:BAABNQAECn8kAAIoAAoKISCXAgDWAgAoAAoKISCXAgDWAgAAAA==.',
Od='Odecias:BAAANQADCgUICQAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Oh='Ohiya:BAAANQABCgIIAgAAAA==.Ohiyaa:BAAANQADCgQIBAAAAA==.',
Or='Orcboken:BAAANQAECgMIBAAAAA==.Orezn:BAAANQAECgQICgAAAA==.',
Os='Oshx:BAAANQADCgEIAQAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Painting:BAAANQAECgEIAQABNQAECggIHwAkAFoeAA==.Pallypusher:BAAANQADCgQICAAAAA==.Papiace:BAAANQAECgYIDgABNQAECgoKVwAFAOwfAA==.Pato:BAABNQAECn8UAAMHAAgKnBxVeQAsAgAHAAgKnBxVeQAsAgAOAAEKBhhlQQA6AAAAAA==.',
Pi='Piesniper:BAAANQABCgIIAgABNQADCgYIDAANAAAAAA==.Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAACNQAFFH8UAAISAAYKuw+tAwA8AQASAAYKuw+tAwA8AQA1AAQKfzwAAhIACgrjHuIFAMECABIACgrjHuIFAMECAAAA.',
Po='Popedragon:BAAANQAECgEIAgAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Prayihealu:BAAANQADCgYIBwAAAA==.Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAABNQAECn8fAAMUAAoKERksKwA9AgAUAAkKAxksKwA9AgAVAAYKZBLGRgBDAQAAAA==.Promisa:BAAANQAECggICAAAAA==.Promise:BAAANQAFFAEIAQAAAA==.Prophets:BAAANQADCgMIBQAAAA==.Pryome:BAABNQAECn8YAAIEAAgKmQpL3gDLAQAEAAgKmQpL3gDLAQABNQAECgoKMAAKAOoVAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQAECgIIAgAAAA==.Punkz:BAAANQADCgYICAABNQAECggIGQAKAPwbAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgYJCwAAAA==.',
Py='Pyromortis:BAAANQAECgcIEQABNQAECgoKNwARAIcWAA==.Pytorch:BAABNQAECn9aAAIEAAkKXCDrFQCzAgAEAAkKXCDrFQCzAgAAAA==.',
['Pø']='Pø:BAAANQAECgQIBAAAAA==.',
Qu='Queelex:BAAANQAECgcIDAABNQAECggIGQAKAPwbAA==.Quigzz:BAACNQAFFH8KAAIVAAUKfhCYDQDbAAAVAAUKfhCYDQDbAAA1AAQKfzcAAhUACgq2IF8GABsDABUACgq2IF8GABsDAAAA.Quinnie:BAABNQAECn8VAAMlAAkKnxc8IADnAAAlAAUKsRE8IADnAAAEAAcKmRXCwQDGAAABNQAFFAIIAgANAAAAAA==.',
Ra='Raganarok:BAAANQAECgIIAgAAAA==.Rahja:BAAANQAECgYICQAAAA==.Ramss:BAAANQAECggIEAAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECggIKQAYACQTAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQAECggIDQAAAA==.Rellans:BAAANQAECgYIBgAAAA==.Resa:BAAANQAECgYIDAAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ri='Ricasti:BAAANQAECgYICwAAAA==.Ritsu:BAAANQAECgYIDQAAAA==.',
Ro='Robinsonic:BAABNQAECn8gAAIcAAkKtRjMEQBFAgAcAAkKtRjMEQBFAgAAAA==.Rokenn:BAAANQADCggICAAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.Rosetastoned:BAAANQADCgIIAgAAAA==.',
Ru='Rukiè:BAAANQAFFAEIAQAAAA==.Runmyrkr:BAAANQAECgcIEgAAAA==.',
['Rô']='Rôbert:BAABNQAECn8WAAITAAgKEQ5LoAAUAQATAAgKEQ5LoAAUAQAAAA==.',
Sa='Saberyn:BAABNQAECn8WAAImAAgKNxBuEACgAQAmAAgKNxBuEACgAQAAAA==.Sacredsassy:BAAANQAECgUICwABNQAECgoKHwAkAIwIAA==.Saenya:BAABNQAECn8YAAISAAcK7RWWKgDSAQASAAcK7RWWKgDSAQAAAA==.Sageofwampa:BAAANQADCggICgAAAA==.Sahra:BAAANQADCggICAAAAA==.Samavanas:BAAANQADCggIBgAAAA==.Sassynova:BAAANQADCgYICQABNQAECgoKHwAkAIwIAA==.',
Sc='Schvitz:BAABNQAECn8hAAIGAAoKABS8SgC9AQAGAAoKABS8SgC9AQAAAA==.Scopeftis:BAABNQAECn8cAAIPAAoKhx6MJQCoAgAPAAoKhx6MJQCoAgAAAA==.',
Se='Seano:BAAANQAECgMIAwAAAA==.Seberology:BAABNQAECn8pAAIWAAkKEBJ8SgA+AgAWAAkKEBJ8SgA+AgAAAA==.Segagamecube:BAAANQADCgMIAwAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.Sergal:BAAANQADCggICAABNQAECgMICQANAAAAAA==.',
Sh='Shaco:BAAANQAECgMIAwAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgQICQABNQAECggIDwANAAAAAA==.Shamownage:BAABNQAECn8wAAMKAAoK6hW7KgAAAgAKAAoK6hW7KgAAAgALAAcKwBNRgQChAQAAAA==.Shankyews:BAAANQADCgQJBAAAAA==.Sheev:BAAANQADCgEIAQAAAA==.Shepling:BAACNQAFFH8KAAIZAAUKMg2WEwAhAQAZAAUKMg2WEwAhAQA1AAQKfxQAAhkACAp7FfZGAN0BABkACAp7FfZGAN0BAAAA.Shifterella:BAAANQAECgMIBAAAAA==.Shifu:BAACNQAFFH8LAAIIAAQKyBfVBQDkAAAIAAQKyBfVBQDkAAA1AAQKfx4AAwgACgrzHvAaAGYCAAgACAr+IfAaAGYCAB8ABwqEFU4VAI8BAAAA.Shivàh:BAACNQAFFH8QAAMPAAYKRBfkBwCbAQAPAAUKOBrkBwCbAQAQAAQKdhHDEADTAAA1AAQKfy8ABBkACgoeI8sOAFgCABAACgrBIjghAIQCABkACQrCHMsOAFgCAA8AAwqkIViDABEBAAAA.Shneezleberg:BAABNQAECn8oAAMHAAoKqB4BOADkAgAHAAoKqB4BOADkAgAmAAQKvgrJIwCVAAAAAA==.Shädowcraft:BAAANQADCgUIBQAAAA==.',
Si='Sildormi:BAAANQAECgEIAQAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAABNQAECn8rAAIDAAoKeA8FEQAWAgADAAoKeA8FEQAWAgAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Skiddlywinks:BAAANQADCgYIFAABNQAECggIFAAFADEUAA==.Sko:BAABNQAECn8fAAIHAAkKPRkKVwCGAgAHAAkKPRkKVwCGAgAAAA==.Skár:BAAANQADCggICwAAAA==.',
Sl='Sladak:BAAANQAECgIIAgAAAA==.Slimjimm:BAAANQAECgUIBQABNQAECgYICwANAAAAAA==.Slutdraggin:BAAANQAECgEIAQAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakyky:BAAANQADCggIEgAAAA==.Sneakymoomoo:BAAANQADCgYJBgABNQAECgoKNwARAIcWAA==.Snipagooly:BAAANQADCgcIBwAAAA==.Snowyrain:BAAANQAECgUICgAAAA==.',
So='Sojourner:BAAANQAECgcIEwABNQAECgoKHQAWAJQaAA==.Solanum:BAAANQADCgQIBAABNQAECgQIBAANAAAAAA==.Solkar:BAAANQADCgcJCwAAAA==.Solo:BAACNQAFFH8GAAITAAIKbAShHABoAAATAAIKbAShHABoAAA1AAQKfzMAAhMACgqvGXUwADkCABMACgqvGXUwADkCAAAA.Soupsandwich:BAAANQAECgMIBAAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
Sp='Spartacùs:BAAANQADCgEIAQABNQAECgUICwANAAAAAA==.',
St='Stagg:BAABNQAECn8uAAIEAAoKRRRjnABIAgAEAAoKRRRjnABIAgAAAA==.Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQADCgcIEQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.Stkk:BAAANQAECggICAAAAA==.Stonedkritz:BAAANQABCgMIAwAAAA==.',
Su='Sunarii:BAABNQAECn8aAAISAAkKEBZEIQAtAgASAAkKEBZEIQAtAgAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.Superbroke:BAAANQABCgIIAgAAAA==.Superpoor:BAAANQABCgEIAQAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
['Sà']='Sàviorself:BAAANQAECgIIBAAAAA==.',
['Sý']='Sýlvanàs:BAAANQADCgMIAwAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAABNQAECn8sAAIgAAoKmQoADQCxAQAgAAoKmQoADQCxAQAAAA==.Talwayn:BAAANQADCgUIDwABNQAECggIFAAFADEUAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQADCgcIBwAAAA==.Taurtellini:BAAANQAECgIIAgAAAA==.Tazoo:BAABNQAECn8dAAMbAAkKBwOPIgAzAQAbAAkKBwOPIgAzAQAKAAEKygi4KQEkAAAAAA==.',
Te='Teamfluffer:BAAANQADCgUICQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Tehzew:BAAANQADCgYICAAAAA==.Tehzuurmx:BAAANQADCggICAAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQABCgMIAwAAAA==.Terebitha:BAAANQABCgMIAgAAAA==.Teruulos:BAAANQAECgUIDgAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAABNQAECn8sAAIRAAoKkh3VNACUAgARAAoKkh3VNACUAgAAAA==.Thadiusx:BAAANQABCgUIBQAAAA==.Tharon:BAABNQAECn8gAAIGAAoKZxUeZgBIAgAGAAoKZxUeZgBIAgAAAA==.Thebigboom:BAACNQAFFH8FAAIcAAIKxgxMBQBwAAAcAAIKxgxMBQBwAAA1AAQKfzsAAhwACgraHfoGAHsCABwACgraHfoGAHsCAAAA.Thecarter:BAAANQAECgIIAgAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.Threnody:BAABNQAECn8jAAMJAAcKXQ4sHQAVAQAJAAcKcQ0sHQAVAQAGAAIKDBMtNAGAAAAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgEIAQANAAAAAA==.Tichemort:BAAANQAECgQIBAAAAA==.Tigerchimon:BAAANQADCgUIBQABNQAECgoKMAAKAOoVAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAACNQAFFH8IAAMpAAMKygunAACIAAApAAMKygunAACIAAAEAAIK5AOaUACBAAA1AAQKfzwAAykACgrEHOsAAAoDACkACgrEHOsAAAoDAAQABAprCgKQAacAAAAA.',
Tr='Trapscallion:BAAANQAECgQIEAAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Treeknight:BAABNQAECn8fAAIPAAgKOBRISQDxAQAPAAgKOBRISQDxAQAAAA==.Treelimbs:BAAANQAECgcIDgAAAA==.Treemoo:BAAANQAECgEIAQABNQAECgoKNwARAIcWAA==.Tridity:BAAANQAECgYIDwAAAA==.Trollolollz:BAAANQAECgIIAwAAAA==.',
Ts='Tsuuna:BAABNQAECn81AAQHAAoKRyEEIQBtAgAHAAoKxCAEIQBtAgAmAAEK8yJMGgBqAAAOAAEKAABxPgBIAAAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.Turtleqtx:BAAANQAECgQIBAAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQAECgIIBAANAAAAAA==.Tylandon:BAAANQAECgYICQAAAA==.Tyralthas:BAAANQADCgQIAwAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgIJAwAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Un='Unavaluable:BAAANQAECgEIAQAAAA==.Ungodlyy:BAABNQAECn8WAAMYAAkKkwVceAAIAQAYAAkKkwVceAAIAQAdAAIKDgKVagBMAAAAAA==.Untöuchable:BAABNQAECn9DAAMTAAoKQSLkEQDpAgATAAoKQSLkEQDpAgAWAAEK4gEwNgEhAAAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Va='Vanthelos:BAAANQADCgQIBQAAAA==.',
Ve='Velachlan:BAAANQAECgYIEwAAAA==.Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAABNQAECn88AAQhAAoKfhmbBwA3AgAhAAgKbRmbBwA3AgAVAAcKaRdgOQCBAQAUAAMK9RLXfQC8AAAAAA==.Verxl:BAABNQAECn8iAAIEAAcKmRXMfgBFAQAEAAcKmRXMfgBFAQAAAA==.',
Vi='Vihn:BAAANQADCgYIBgAAAA==.',
Vo='Voidnyou:BAAANQADCgQICAAAAA==.Volumes:BAAANQAECgUIBwAAAA==.Volund:BAABNQAECn81AAIbAAoKhAcYFABFAQAbAAoKhAcYFABFAQAAAA==.',
Vy='Vynsong:BAABNQAECn8mAAIWAAkKMiBRIQDoAgAWAAkKMiBRIQDoAgAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAANAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFgAAAA==.Watchmebløck:BAAANQAECgQIBAAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBgAAAA==.Wetmonk:BAAANQAECgcIDQAAAA==.',
Wh='Whoyerdaddy:BAAANQAECgUIBwAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAABNQAECn82AAMKAAoKJBJ3WwD9AQAKAAoKJBJ3WwD9AQALAAgKeBH4YADqAAAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.',
Wo='Wombatman:BAAANQAECgQICQAAAA==.Wong:BAAANQAECgUIBgAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCggICAAAAA==.',
Xo='Xoron:BAAANQAECgQIBAAAAA==.',
Xu='Xugos:BAABNQAECn8eAAIYAAoKGRgbZgAoAgAYAAoKGRgbZgAoAgAAAA==.',
Xz='Xzeena:BAAANQADCgEIAQAAAA==.',
Ya='Yatagarasu:BAAANQAECggIAgAAAA==.',
Ye='Yenafer:BAAANQADCggICAAAAA==.',
Yo='Yochill:BAAANQAECgIIAgABNQAECgYICgANAAAAAA==.Yolokin:BAAANQADCgcIGAAAAA==.Yooper:BAAANQADCgcIBgAAAA==.Yota:BAAANQAECgMIAwAAAA==.',
Yr='Yrgg:BAAANQAECgYICwAAAA==.',
Yt='Ytgamezoned:BAAANQADCgQIBAAAAA==.',
Yu='Yuna:BAAANQABCggIEAAAAA==.',
Za='Zadanthra:BAABNQAECn8UAAIFAAgKMRTHEAClAQAFAAgKMRTHEAClAQAAAA==.Zalektra:BAAANQADCgQIBAAAAA==.Zapadin:BAABNQAECn8tAAITAAoKZhKYXQCgAQATAAoKZhKYXQCgAQAAAA==.Zaphodè:BAAANQAECgUICQAAAA==.',
Ze='Zeenie:BAAANQAFFAIIAgAAAA==.Zeljusticar:BAAANQADCgEIAQAAAA==.Zephian:BAAANQAECgMIAwAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAABNQAECn8gAAQnAAgKAAubCwCFAQAnAAgKAAubCwCFAQARAAYK2wN8sQACAQASAAUKNgWpUQDKAAAAAA==.Zotoperen:BAABNQAECn8xAAMfAAoK/iBkAwBdAwAfAAoK/iBkAwBdAwAIAAMKFhHoUgClAAAAAA==.',
Zy='Zylergy:BAABNQAECn8cAAITAAoKPgl23wBcAQATAAoKPgl23wBcAQAAAA==.',
['Zì']='Zìfu:BAAANQADCggICQAAAA==.',
['Àv']='Àvicant:BAAANQAECgUJBwABNQAFFAQICAAGAFMiAA==.',
['Än']='Ändo:BAAANQAECgQIDgAAAA==.',
['Äy']='Äy:BAAANQADCgIIAgAAAA==.',
['Çy']='Çyrin:BAABNQAECn8wAAMWAAkKsBO2LAD2AQAWAAkKsBO2LAD2AQATAAEK5QhHpwEzAAAAAA==.',
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
