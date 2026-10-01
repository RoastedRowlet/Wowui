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

local lookup = {'Mage-Arcane','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Evoker-Devastation','Priest-Shadow','Unknown-Unknown','DemonHunter-Devourer','Shaman-Elemental','Rogue-Outlaw','Warrior-Protection','Druid-Guardian','Rogue-Assassination','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Warrior-Arms','Warrior-Fury','Monk-Windwalker','DemonHunter-Vengeance','Shaman-Restoration','Druid-Balance','Druid-Feral','DeathKnight-Frost','DemonHunter-Havoc','DeathKnight-Unholy','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','Druid-Restoration','Mage-Frost','Shaman-Enhancement','Priest-Discipline','Evoker-Augmentation','Hunter-Marksmanship','Rogue-Subtlety','Evoker-Preservation','Mage-Fire',}
local provider = {region='US',realm='Mannoroth',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aadda:BAABNQAECoEiAAIBAAkKkRiYXwCSAgABAAkKkRiYXwCSAgAAAA==.',
Ab='Abcdpal:BAABNQAFFIEOAAMCAAYKIRnsAQAvAgACAAYKIRnsAQAvAgADAAEKngB1IgA0AAAAAA==.Abena:BAAANQAECgcICgAAAA==.Abighoul:BAAANQADCgYICAAAAA==.Abusive:BAABNQAECoEgAAIEAAkKGR5CEwDoAgAEAAkKGR5CEwDoAgAAAA==.',
Ac='Acat:BAAANQAECgQIBQAAAA==.',
Ae='Aerogosa:BAACNQAFFIEGAAIFAAMKwRzfBQAKAQAFAAMKwRzfBQAKAQA1AAQKgSUAAgUACQpGIrMEAC4DAAUACQpGIrMEAC4DAAAA.Aeyonce:BAAANQADCgcIBwAAAA==.',
Af='Affrika:BAAANQADCgEIAQAAAA==.',
Ag='Agogagog:BAABNQAECoEbAAIGAAgKYBA/IADqAQAGAAgKYBA/IADqAQAAAA==.',
Ah='Ahlaris:BAAANQADCgcIBwABNQAECgMIAwAHAAAAAA==.',
Ai='Aicam:BAAANQAECgEIAQAAAA==.',
Ak='Akaza:BAAANQAECgUIBQAAAA==.',
Al='Alanalanalan:BAAANQAECgEIAQAAAA==.Alarg:BAAANQADCgIIAgABNQAECgYIEQAHAAAAAA==.Alatide:BAAANQAECgYIEQAAAA==.Alcani:BAAANQADCgYIBgAAAA==.Aleena:BAAANQADCgcICgAAAA==.Alleriaa:BAAANQADCggIDAAAAA==.Alphakuup:BAAANQADCgYIBgABNQAECgcIEgAHAAAAAA==.Altazar:BAABNQAECoEeAAIBAAgK9A/IoAD4AQABAAgK9A/IoAD4AQAAAA==.Alxath:BAABNQAECoEYAAIIAAgKrB/GEADEAgAIAAgKrB/GEADEAgAAAA==.',
Am='Amaryste:BAAANQAECgEIAQAAAA==.Amidalah:BAAANQAECgcIDwAAAA==.Amizlia:BAAANQADCgEIAQAAAA==.Amorinaron:BAABNQAECoE7AAIBAAkK1iDMGwBUAwABAAkK1iDMGwBUAwAAAA==.',
An='Anansi:BAAANQAECgIIAgABNQAFFAcIFgAFACkjAA==.Andsong:BAAANQADCgUIBQABNQAECgYICwAHAAAAAA==.Anfalas:BAABNQAECoE2AAIJAAkKnSAlDgBdAwAJAAkKnSAlDgBdAwAAAA==.Anic:BAAANQAECgcIEwAAAA==.Anikora:BAAANQADCgcIDAAAAA==.Anjelika:BAAANQAECgUICwAAAA==.Anklestabber:BAABNQAECoEfAAIKAAgKECBVAwDRAgAKAAgKECBVAwDRAgAAAA==.Annathema:BAAANQADCgQIBAAAAA==.Anser:BAAANQADCggICAAAAA==.Anthlina:BAAANQADCgUJBwAAAA==.',
Ar='Archicrash:BAAANQAECgEIAQAAAA==.Archipal:BAAANQADCgMIAwAAAA==.Archomen:BAAANQADCgQIBAABNQAECgQICQAHAAAAAA==.Arcwave:BAAANQADCgcIGQAAAA==.Arcyon:BAAANQAECgYJDAAAAA==.Arethi:BAACNQAFFIEKAAILAAQKtCMGAQCjAQALAAQKtCMGAQCjAQA1AAQKgR4AAgsACQoQJAUCAHsDAAsACQoQJAUCAHsDAAAA.Arleos:BAABNQAECoEfAAIDAAgKHhxNKgCIAgADAAgKHhxNKgCIAgAAAA==.Arroyo:BAAANQADCggIHQAAAA==.Artemasz:BAAANQAECgUICwAAAA==.',
As='Asrelle:BAAANQAECgYIEgAAAA==.Astaumin:BAAANQADCgYICgAAAA==.Asterrin:BAAANQAECgEIAQAAAA==.Astralfrog:BAAANQAECgQIBgAAAA==.',
At='Ateelasham:BAAANQADCgQIBAAAAA==.Atrophied:BAAANQAECgIIAgABNQAECgkJJAAMAIkgAA==.',
Au='Audeline:BAAANQAECgMIBAAAAA==.Augmented:BAAANQABCgYICgABNQAECgkJKQADANcmAA==.Auraelia:BAAANQADCgEIAQAAAA==.Aurilia:BAAANQADCggICwAAAA==.Aurôra:BAAANQAECgEJAQAAAA==.',
Av='Avran:BAABNQAECoEfAAIIAAgKbxfNGgBLAgAIAAgKbxfNGgBLAgAAAA==.',
Az='Aziala:BAAANQAECggICAABNQAECgkJIQAFAIQgAA==.Azreluna:BAABNQAECoEfAAINAAgKkA2hJQD5AQANAAgKkA2hJQD5AQAAAA==.',
Ba='Backstabr:BAAANQADCgIIAgAAAA==.Backyard:BAAANQADCgQIBAAAAA==.Bajablight:BAAANQAECgEIAQAAAA==.Bajiggitee:BAABNQAECoEmAAIEAAgKYBrbJQBVAgAEAAgKYBrbJQBVAgAAAA==.Ballsakz:BAAANQAECgMIAwABNQAECgcIBwAHAAAAAA==.Bananarosin:BAABNQAECoEaAAQOAAcKiAcZFQCsAAAPAAYK9gONvwDqAAAOAAMKEAkZFQCsAAAQAAQKHwX2QACqAAAAAA==.Banlers:BAAANQADCgYIFAAAAA==.Banmedaddy:BAAANQADCggIFAABNQABCgIJAgAHAAAAAA==.Baradoon:BAAANQAECgUIDAAAAA==.Bazrameet:BAAANQAECgcIDwABNQAECgkJJQAFAOYPAA==.',
Be='Bealzhunter:BAAANQADCgUIBgAAAA==.Bela:BAAANQADCgcIBwAAAA==.Bellion:BAAANQAECgIIAwAAAA==.Beo:BAABNQAECoEiAAIRAAkKkhl+CwCWAgARAAkKkhl+CwCWAgAAAA==.',
Bi='Bigbluetaco:BAABNQAECoEhAAQSAAgKjBorTQBjAgASAAgKUhorTQBjAgALAAcKwg48FwBZAQATAAIKNgjsIQBWAAAAAA==.Bigchug:BAABNQAECoEiAAIUAAkKZR9sCQASAwAUAAkKZR9sCQASAwAAAA==.Biggirlsonly:BAAANQAECgQIBAABNQAFFAcIFgAFACkjAA==.Bigyahu:BAAANQADCgIIAgAAAA==.Bitelo:BAAANQADCggICAABNQADCggICAAHAAAAAA==.',
Bl='Blast:BAAANQADCgIIAgAAAA==.Blatt:BAAANQADCgMIAwAAAA==.Blech:BAABNQAECoEiAAIBAAgKkg34rgDZAQABAAgKkg34rgDZAQAAAA==.',
Bo='Bookerneg:BAAANQAECgQICgAAAA==.Boomslang:BAAANQAECgQICwAAAA==.Borlen:BAAANQAECgUIDAAAAA==.',
Br='Braids:BAAANQADCgcICQAAAA==.Brassfeather:BAAANQAECgMICAAAAA==.Brewcifer:BAAANQADCgMIAwAAAA==.Brezzath:BAAANQADCggICAAAAA==.Brezzid:BAAANQADCgYICwABNQAECggIGQAVAEgNAA==.Brezzon:BAABNQAECoEZAAIVAAgKSA2NDACaAQAVAAgKSA2NDACaAQAAAA==.Brizzletwo:BAABNQAECoEXAAIWAAgKjQtfagB1AQAWAAgKjQtfagB1AQAAAA==.Brozzath:BAAANQAECgYICgABNQAECggIGQAVAEgNAA==.Bryanka:BAAANQADCggICgAAAA==.Brättie:BAAANQADCggIGwAAAA==.Bróx:BAABNQAECoEZAAISAAgK2xNBcgDvAQASAAgK2xNBcgDvAQAAAA==.',
Bu='Bubbajoe:BAAANQAECgIIAgABNQAFFAcIFgAFACkjAA==.Bubbajr:BAAANQAECgMJAwAAAA==.Bungholio:BAAANQAECgMIAwAAAA==.Burgy:BAAANQAECgcIEQAAAA==.Burgydk:BAABNQAECoEWAAIEAAYKHg3ZXQAyAQAEAAYKHg3ZXQAyAQAAAA==.Buttfancy:BAABNQAECoEdAAIXAAkKKBTTJQBoAgAXAAkKKBTTJQBoAgAAAA==.',
['Bï']='Bïgbear:BAAANQAECggIAQAAAA==.Bïgdot:BAAANQAECgcIBwABNQAECggIAQAHAAAAAA==.',
Ca='Cainbanw:BAAANQADCgUICAAAAA==.Caliery:BAAANQABCgEIAQAAAA==.Calmpressure:BAAANQAECggIEAAAAA==.Capnsparrow:BAAANQAECgMIBAAAAA==.Captncheese:BAAANQAECgEIAgAAAA==.Cargy:BAAANQADCgcJCQAAAA==.Carshas:BAAANQADCgYIBgAAAA==.Cas:BAAANQAECgIIAgAAAA==.Cassielee:BAAANQAECgIIAwAAAA==.Catabop:BAAANQAECgQIBwABNQAECgkJIgAWAE8dAA==.Catastorm:BAABNQAECoEiAAIWAAkKTx1aFQD1AgAWAAkKTx1aFQD1AgAAAA==.Catavoker:BAAANQAECgQICAABNQAECgkJIgAWAE8dAA==.Caustic:BAAANQAECgcIEwAAAA==.Caveatemptor:BAABNQAECoEdAAIXAAgKxSF4HwCcAgAXAAgKxSF4HwCcAgAAAA==.',
Ce='Celaina:BAAANQAECgMJAwAAAA==.',
Ch='Chainhappy:BAAANQAECgYICwAAAA==.Cheezybread:BAAANQADCgUIBQAAAA==.Chesshire:BAAANQAECgEIAgAAAA==.Chimeric:BAABNQAECoEkAAMMAAkKiSAbAwBMAwAMAAkKiSAbAwBMAwAYAAYKlwhFFwATAQAAAA==.Chlover:BAAANQAECgUIBQAAAA==.Chmap:BAAANQADCggJFQABNQAECgQIBQAHAAAAAA==.Chontosh:BAAANQAECgUICgAAAA==.Chozenfate:BAAANQADCggIEQAAAA==.Chronuwu:BAAANQAECgQIBQAAAA==.',
Ci='Cindymccain:BAAANQAECgUJDgAAAA==.',
Cl='Clearsight:BAAANQAECgUICQABNQAECggIHgAWAEcdAA==.Clemfandengo:BAAANQAECgQIBQAAAA==.',
Co='Cometh:BAAANQADCggIEAAAAA==.Compute:BAABNQAECoE0AAIZAAkK2B6eDwDbAgAZAAkK2B6eDwDbAgABNQAECggJEAAHAAAAAA==.Corursa:BAAANQADCgcJCwABNQAECgYICwAHAAAAAA==.Cozmowaffle:BAAANQADCgIIAgAAAA==.',
Cr='Critterr:BAAANQADCgEIAQAAAA==.Cronauer:BAAANQAECgUICAAAAA==.Cryofrog:BAAANQADCgMIBAAAAA==.',
Ct='Cthulusfiend:BAAANQAECgQIBAABNQAFFAcIFgAFACkjAA==.',
Cu='Cuppicakies:BAAANQADCgUIBwAAAA==.',
Da='Dabbington:BAAANQAECgUICQAAAA==.Daddilock:BAAANQAECgQIBQAAAA==.Daddyfatslap:BAAANQAFFAEIAgAAAA==.Daggerz:BAAANQAECgcIEwAAAA==.Dahood:BAAANQADCgYIBgAAAA==.Danasty:BAAANQAECgQIBAAAAA==.Danidakiesh:BAAANQAECgMIAwAAAA==.Daralina:BAAANQABCgIIAgAAAA==.Darbreezius:BAAANQAECgcIEAAAAA==.Daribow:BAAANQADCgcICwAAAA==.Darkcoffee:BAABNQAECoEYAAMVAAkKCgvADQB9AQAVAAkKwAfADQB9AQAaAAQKng6CUADeAAAAAA==.Darkvalk:BAAANQADCgEJAQAAAA==.Daroc:BAAANQAECggIBgAAAA==.Darvax:BAAANQAECgEIAQAAAA==.Datacenter:BAAANQAECggJEAAAAA==.Dawgan:BAAANQAECgIIAwAAAA==.',
De='Deadlyfrog:BAAANQADCgcICAAAAA==.Deamionn:BAAANQAECgQIBgAAAA==.Deathbauchs:BAAANQADCgcICwAAAA==.Deathlylove:BAAANQABCgYIBgAAAA==.Deathtreader:BAAANQADCggICAAAAA==.Delsym:BAAANQABCggIEwAAAA==.Demoinc:BAABNQAECoEiAAMTAAkKuxpABQB/AgATAAgK/RtABQB/AgASAAYKRhFfowBfAQAAAA==.Denathus:BAAANQADCgYIDwAAAA==.Denovo:BAAANQADCggICAABNQAECggIHQAXAMUhAA==.Desipator:BAAANQAECgMIAwAAAA==.Destinyløl:BAAANQAECgUICQAAAA==.',
Di='Diabolix:BAAANQADCgQIBwAAAA==.Dilo:BAAANQAECggIDQAAAA==.Divalatina:BAACNQAFFIEPAAIDAAUKDAQ6CgBdAQADAAUKDAQ6CgBdAQA1AAQKgSoAAgMACQp8FlI6AD0CAAMACQp8FlI6AD0CAAAA.Divinefrog:BAAANQAECgQIBAAAAA==.',
Dj='Djmax:BAAANQADCgIIAgAAAA==.',
Dk='Dkthae:BAABNQAECoEeAAIEAAgKZSLqDwAJAwAEAAgKZSLqDwAJAwAAAA==.',
Dl='Dlxanomaly:BAAANQAECgYIEgAAAA==.',
Do='Doeurden:BAAANQADCgYIBgAAAA==.Donttouchme:BAAANQADCgcIDAAAAA==.Doohickey:BAAANQAECgIIAwAAAA==.Dotsdaddy:BAAANQADCggJDwAAAA==.Doubledeez:BAAANQADCgIIAgAAAA==.Doubledz:BAAANQADCggIFQAAAA==.',
Dr='Dracslaya:BAAANQADCgcIDQAAAA==.Dragonaire:BAAANQABCgIIAgAAAA==.Dragondzntz:BAAANQAECgQICgAAAA==.Dragonfrog:BAAANQADCgMIAwAAAA==.Dreamyeyes:BAAANQAECgYIEAAAAA==.Drerein:BAAANQAECgQIBQAAAA==.',
Du='Dubz:BAAANQAECggICgAAAA==.Dundeal:BAAANQADCgcIBwAAAA==.Dunkel:BAABNQAECoEkAAMbAAkKARiOJgBSAgAbAAkKARiOJgBSAgAZAAIK1w0KcwBhAAAAAA==.Dupichu:BAABNQAECoEaAAIEAAgKQBvfIgBpAgAEAAgKQBvfIgBpAgAAAA==.',
Dy='Dyane:BAAANQADCgYICwAAAA==.',
Ea='Eataa:BAAANQAECgIIBAAAAA==.',
Eb='Ebonhammer:BAAANQADCgIIAgAAAA==.',
Eg='Egrilo:BAAANQADCggICAAAAA==.',
Ei='Eileithyia:BAAANQAECgYIDAAAAA==.',
El='Elekastra:BAAANQADCgcIFwAAAA==.Ellonan:BAAANQADCggICwABNQAECgkJJQAcAMoUAA==.Ellz:BAAANQAECgUICgAAAA==.Elyndor:BAAANQADCgUIBQAAAA==.',
Em='Emopally:BAABNQAECoEYAAMbAAcKzBLfRgCWAQAbAAcKaxLfRgCWAQAZAAYK1g0yQwA7AQAAAA==.Emopower:BAAANQAECgUICwAAAA==.',
En='Enderr:BAABNQAECoEeAAIUAAgKgh7cDwCrAgAUAAgKgh7cDwCrAgAAAA==.Enegma:BAAANQADCgYIBgAAAA==.Energètic:BAAANQADCgIIAgAAAA==.Enzini:BAAANQAECgQIBQAAAA==.',
Er='Erashi:BAAANQAECgQJBAAAAA==.',
Eu='Eupraxia:BAAANQAECggIAgABNQAECggICQAHAAAAAA==.',
Fa='Falculan:BAAANQADCgEIAQAAAA==.Fallen:BAAANQAECgUIEQABNQABCgIJAgAHAAAAAA==.Farwest:BAAANQADCggIFAAAAA==.Fatherchung:BAAANQAECgIIAwAAAA==.Fayotbeanz:BAAANQABCgYIDAAAAA==.',
Fe='Felwyth:BAAANQADCggIEwABNQAECggIHAATAJMWAA==.Feythe:BAAANQAECgQIBAABNQAECggIHgAUAIIeAA==.',
Fi='Finneas:BAAANQADCgEIAQAAAA==.Fireworkxz:BAAANQAECgEIAgAAAA==.Fishhawk:BAAANQAECgUIBwAAAA==.',
Fl='Flarehammer:BAABNQAECoEhAAICAAgKwCJ8IwADAwACAAgKwCJ8IwADAwAAAA==.Flogh:BAAANQAECgcIDgAAAA==.',
Fo='Fomanshi:BAABNQAECoElAAIFAAkK5g/jDwAfAgAFAAkK5g/jDwAfAgAAAA==.Forleaf:BAAANQADCgYIBgAAAA==.Forsierra:BAAANQADCgEIAQAAAA==.Foxiji:BAAANQAECgIIAgAAAA==.',
Fr='Frexadin:BAAANQADCgYIBwAAAA==.Frexican:BAABNQAECoEZAAIdAAgKnBhQPQBrAgAdAAgKnBhQPQBrAgAAAA==.Fright:BAAANQAECgQICgAAAA==.Frogleggs:BAAANQABCgMIAwAAAA==.Frogshock:BAAANQADCgUIBQAAAA==.',
Fu='Fupabean:BAAANQADCgcIBwAAAA==.Fure:BAAANQADCgQIBAAAAA==.Fuupa:BAAANQADCgIIAgAAAA==.',
['Fí']='Fíg:BAAANQADCgYIBgAAAA==.',
['Fö']='Förbindelse:BAAANQAECgEIAQAAAA==.',
Ga='Gangdat:BAAANQAECgEIAQAAAA==.Garur:BAAANQAECgQIBAAAAA==.',
Ge='Genridge:BAAANQADCgYIDAAAAA==.Gewl:BAAANQADCgUIBQABNQAECggIHgAUAIIeAA==.',
Gi='Gilani:BAAANQAECgEIAQAAAA==.',
Gl='Glp:BAAANQAECgYICAAAAA==.',
Go='Gorpy:BAACNQAFFIERAAMPAAcKdh6AAQBLAgAPAAYKoB6AAQBLAgAQAAIKyCAvBADKAAA1AAQKgSwABA8ACQpjJlQHAHEDAA8ACAoyJlQHAHEDABAABwpHHjgIAGsCAA4AAQrTHsAeAFMAAAAA.Gotrott:BAAANQADCgEIAQAAAA==.',
Gr='Gravybones:BAAANQADCgcIFAAAAA==.Grayparse:BAAANQADCgQIBAAAAA==.Greenjesh:BAABNQAECoEYAAIBAAkKNReYYQCNAgABAAkKNReYYQCNAgAAAA==.Greensheesh:BAABNQAECoElAAIBAAkKuBltVgCpAgABAAkKuBltVgCpAgABNQAECgkJGAABADUXAA==.Greypilgram:BAAANQAECgMIBAAAAA==.Grimstank:BAAANQADCggJFQAAAA==.Grizzlygerm:BAAANQADCgUIBQAAAA==.Grizzlyoné:BAAANQAECgIIAwAAAA==.Gronck:BAAANQADCgMIAwAAAA==.Grumbleface:BAACNQAFFIENAAIDAAUKwBHiBwCUAQADAAUKwBHiBwCUAQA1AAQKgSAAAgMACQq1H6gPACsDAAMACQq1H6gPACsDAAAA.Grumbletron:BAABNQAECoEXAAIeAAgKxhzbGgDXAgAeAAgKxhzbGgDXAgAAAA==.Gröver:BAAANQAECgIIAgABNQAECggIDQAHAAAAAA==.',
Gs='Gstatus:BAABNQAECoEYAAIJAAgKww0XVgDRAQAJAAgKww0XVgDRAQAAAA==.',
Gu='Gunel:BAAANQAECgQIBQAAAA==.',
Ha='Haawee:BAAANQAECgcIDAAAAA==.Hailcthulhu:BAABNQAECoEZAAIIAAcKux2nGwBCAgAIAAcKux2nGwBCAgAAAA==.Handcuffs:BAAANQAECgMJAwAAAA==.Handorn:BAAANQAECgMIBQABNQAECgkJLgAOACIcAA==.Hanwha:BAAANQAECgYICwAAAA==.Harrower:BAAANQAECgQICgAAAA==.Haze:BAAANQAECggICAAAAA==.Hazzkul:BAABNQAECoEeAAIdAAgKUyTfDQBOAwAdAAgKUyTfDQBOAwAAAA==.',
He='Healness:BAABNQAECoEaAAIWAAkKkyDRCwBAAwAWAAkKkyDRCwBAAwAAAA==.Helasam:BAAANQAECgIIAwAAAA==.Hellbourné:BAAANQAECgEIAQAAAA==.Helloboys:BAABNQAECoEXAAIPAAgKLw8+YADoAQAPAAgKLw8+YADoAQAAAA==.Helnome:BAAANQAECgIIAgABNQAECgIIAwAHAAAAAA==.Henzo:BAAANQABCgEIAQAAAA==.Herbavor:BAAANQAECgMJAwAAAA==.Hermes:BAABNQAECoEmAAMPAAkKNSHPEwARAwAPAAgKciLPEwARAwAQAAQKrA9UMgDmAAAAAA==.Hermestrisme:BAAANQAECgEIAQAAAA==.',
Hi='Hiemultis:BAAANQADCggIDwAAAA==.',
Ho='Holexplorer:BAABNQAECoEmAAISAAgKCyPvGwApAwASAAgKCyPvGwApAwAAAA==.Holytrashie:BAAANQAECgIIAwAAAA==.Honeybadger:BAABNQAECoEZAAQfAAcKhBTFHwDTAQAfAAcKhBTFHwDTAQAXAAUKqxYPUwA9AQAYAAIKnRT6KQBBAAAAAA==.Honnybuns:BAAANQABCgUIBQAAAA==.Hoofsmack:BAAANQADCggICgAAAA==.Hordeji:BAAANQADCggIDAAAAA==.Hordeslayer:BAAANQADCgUICAAAAA==.',
Hs='Hsk:BAABNQAECoEbAAMgAAgKvB5oBACjAgAgAAgKvB5oBACjAgABAAQKZg3DKAH5AAAAAA==.',
Hu='Hugostiglitx:BAAANQAECgIIAwAAAA==.Hulkaholic:BAABNQAECoEdAAMJAAgKsCKyFQAhAwAJAAgKsCKyFQAhAwAhAAMKEwz/IQC8AAAAAA==.Hulkclap:BAAANQABCgMIAwAAAA==.Hulkdemon:BAAANQABCgUIBgAAAA==.Hulkhunts:BAAANQABCgUICwAAAA==.',
['Hÿ']='Hÿphy:BAAANQAECgIIAgAAAA==.',
Ic='Icecat:BAAANQAECgYIDwAAAA==.',
Il='Ilian:BAAANQADCgQICwAAAA==.Illionecho:BAAANQABCgUIBQAAAA==.',
In='Innothule:BAAANQADCgUIBQAAAA==.Inseratum:BAAANQADCgYIHAAAAA==.Inê:BAAANQAECgYIEgABNQAECggIEwAHAAAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQABNQAECgYJDQAHAAAAAA==.',
Ir='Iriedraco:BAAANQABCgIIAgAAAA==.Irielite:BAAANQABCgQIBAAAAA==.Ironblast:BAAANQAECgYIEQAAAA==.',
Is='Ishaa:BAAANQADCgIIAgAAAA==.',
It='Ithanksource:BAAANQAFFAEIAQAAAA==.',
Iv='Ivincentl:BAAANQADCgUIBQAAAA==.',
Ix='Ixgangrxi:BAAANQADCgQIBAAAAA==.',
Ja='Jadethunder:BAAANQADCgEIAQABNQAECgQIBwAHAAAAAA==.Jake:BAAANQAECgEIAQAAAA==.Jankie:BAABNQAECoEaAAIaAAgKnh0KFQC3AgAaAAgKnh0KFQC3AgAAAA==.Jarnar:BAAANQAECgQIBAAAAA==.Jaxsin:BAAANQADCgEIAQAAAA==.',
Je='Jearemy:BAAANQADCgEIAQAAAA==.Jekster:BAAANQADCgEIAQAAAA==.Jerva:BAAANQADCgcIBwABNQAECgkJNAAWAJIiAA==.',
Ji='Jingburger:BAAANQAECggIEwAAAA==.Jinnosuke:BAAANQAECgMIBwAAAA==.',
Jo='Joecelin:BAAANQAECgMIAwAAAA==.Johhnyp:BAAANQAECggICwAAAA==.Johnathanwow:BAAANQAECgQJBwAAAA==.Johnnytotem:BAABNQAECoEdAAMJAAkKvhfiLACLAgAJAAkKvhfiLACLAgAWAAcKfAPslAD7AAABNQAECggICwAHAAAAAA==.Jonastus:BAAANQADCgQIBAAAAA==.Jonermar:BAAANQADCgMIAwAAAA==.',
Ju='Judgemental:BAAANQADCgUIBgAAAA==.Justicé:BAAANQAECgQIBQAAAA==.',
Jy='Jykyl:BAABNQAECoEZAAMYAAgK8hd/CQBCAgAYAAgK6xZ/CQBCAgAMAAIK+RsPLwCSAAAAAA==.',
['Jê']='Jêkyl:BAAANQADCgEIAQAAAA==.',
Ka='Kaidoazure:BAAANQAECgIIAgAAAA==.Kaipod:BAAANQAECgUJCgAAAA==.Kaorrii:BAAANQAECgUIBwAAAA==.Karlaia:BAAANQADCgEIAQAAAA==.Kattána:BAAANQAECgMIAwABNQAECgUIDAAHAAAAAA==.Kauthoon:BAAANQADCgQJBwAAAA==.Kaykotta:BAAANQADCgUIDQAAAA==.Kazademon:BAABNQAECoEZAAIIAAgKYQ0LJQDiAQAIAAgKYQ0LJQDiAQAAAA==.Kazmo:BAAANQAECgcIEgAAAA==.',
Ke='Kegheimer:BAAANQAECgIIAgABNQAECgUIEQAHAAAAAA==.Keigis:BAAANQAECgEIAQAAAA==.Kensington:BAAANQAECgUICgABNQAECgkJHgAEAGkgAA==.Keyalovar:BAABNQAECoEJAQIeAAgK/SboAgCqAwAeAAgK/SboAgCqAwAAAA==.Keìra:BAAANQADCgYIBwAAAA==.',
Kh='Khalgon:BAAANQADCggICAABNQAECggIAgAHAAAAAA==.',
Ki='Kimbecky:BAAANQADCgQJBQAAAA==.Kimchii:BAAANQAECgIIAgAAAA==.Kiritoo:BAAANQABCgQIBAAAAA==.Kishukae:BAABNQAECoEaAAIEAAgK8SOGCwA1AwAEAAgK8SOGCwA1AwAAAA==.Kislosladkiy:BAAANQAECggIEAAAAA==.',
Kl='Klassik:BAAANQAECgQIBwAAAA==.',
Kn='Knitbeaniex:BAAANQAECgEIAQABNQAECgEIAgAHAAAAAA==.Knobsnob:BAABNQAECoEoAAQiAAkKUB/HBAA3AgAeAAgKex14HADNAgAiAAYKViHHBAA3AgAGAAIKBBAXTwB1AAAAAA==.',
Kr='Kragden:BAAANQADCgMIAwABNQAECgUIEQAHAAAAAA==.Kriztina:BAAANQAECgQIBQAAAA==.Krizu:BAEANQADCgYIBgAAAA==.Kronkk:BAAANQADCgIIAgAAAA==.Kropie:BAAANQAECgUICwAAAA==.Krågden:BAAANQADCgUIBQABNQAECgUIEQAHAAAAAA==.',
Ku='Kunfuzion:BAAANQAECgQIDAABNQAECgQIBwAHAAAAAA==.',
Ky='Kynga:BAAANQADCgUIBwABNQADCgcICQAHAAAAAA==.',
La='Ladrian:BAABNQAECoEZAAQPAAkKLBApcwCtAQAPAAcKoBApcwCtAQAQAAIKMgsgVgBqAAAOAAEKcBMeIQBIAAAAAA==.Landoresh:BAAANQAECgEIAwAAAA==.Langers:BAAANQADCgEIAQAAAA==.Larenieth:BAAANQADCgcICQAAAA==.Larrykpinga:BAAANQAECgYIBwAAAA==.Larüd:BAABNQAECoEbAAIWAAkKCxWZMgBSAgAWAAkKCxWZMgBSAgAAAA==.Lasmon:BAABNQAECoEiAAIPAAgKZQ3EZADZAQAPAAgKZQ3EZADZAQAAAA==.',
Le='Legallyblind:BAABNQAECoEeAAIVAAgKHyQCAgBDAwAVAAgKHyQCAgBDAwAAAA==.Legit:BAAANQAECgMIBAAAAA==.',
Li='Lightblessed:BAAANQADCgcJBwABNQAECgYIEQAHAAAAAA==.Lightsauce:BAAANQAECgQIBAAAAA==.Lightsmisery:BAAANQADCgYIBgAAAA==.Lillithx:BAAANQAECgMJAwAAAA==.Lillucy:BAAANQADCggIDgAAAA==.Lilpä:BAAANQAECgcIBwABNQAECggIEwAHAAAAAA==.Lindarenne:BAAANQADCgUIBQAAAA==.Lindree:BAAANQAECgcICwAAAA==.Liquidfire:BAAANQADCgYIBgAAAA==.Lirang:BAAANQAECgQICAAAAA==.Littlewashu:BAAANQABCgUIBwAAAA==.Livlife:BAAANQAECgEIAQABNQAECggIDQAHAAAAAA==.Lizardfistin:BAACNQAFFIEWAAMFAAcKKSNqAACJAgAFAAYKzSRqAACJAgAjAAUKGh8kAgDAAQA1AAQKgR4AAwUACQo1JdgCAGoDAAUACQo1JdgCAGoDACMAAQoXID8ZAFEAAAAA.',
Lo='Loads:BAAANQAECggIAQAAAA==.Lockñlol:BAAANQABCgQIBAAAAA==.Loni:BAAANQAECgQICgAAAA==.Loonaimp:BAAANQAECgMJBQAAAA==.Lorthos:BAAANQABCgIIAgAAAA==.Lotús:BAABNQAECoEmAAMkAAkKQyQdCQAkAwAkAAgK8iMdCQAkAwAdAAIKLSYe2gDeAAAAAA==.',
Lu='Lucithalle:BAAANQADCgYIBgAAAA==.Lumenox:BAABNQAECoElAAMcAAkKyhTgFQD8AQAcAAkKyhTgFQD8AQACAAEKfgIoaAEkAAAAAA==.Luminarria:BAAANQAECgQICgAAAA==.Luminisong:BAAANQAECgUIBwAAAA==.Lupomic:BAAANQAECgIIAwAAAA==.Lushice:BAAANQABCgIIAgAAAA==.',
Ma='Maeivalla:BAABNQAECoEcAAIeAAgKDxNWRgAFAgAeAAgKDxNWRgAFAgAAAA==.Magdaliana:BAABNQAECoEXAAIkAAgKyB8tDAD1AgAkAAgKyB8tDAD1AgAAAA==.Mageler:BAABNQAECoEZAAMBAAkK3hTyjQAjAgABAAgK1xTyjQAjAgAgAAEKGBXbMABKAAAAAA==.Magicpurro:BAAANQAECggIDwABNQAFFAcIFgAFACkjAA==.Maiajayde:BAAANQABCgIIAgAAAA==.Malicebane:BAAANQADCgQIBAAAAA==.Mallory:BAAANQAECggICwAAAA==.Malma:BAAANQADCgYIBgAAAA==.Mancane:BAABNQAECoEkAAIBAAkK4xmMWgCfAgABAAkK4xmMWgCfAgAAAA==.Margolis:BAAANQADCggICgABNQAFFAcIEQAPAHYeAA==.Margrathwin:BAABNQAECoEYAAIJAAgKHRDFUQDhAQAJAAgKHRDFUQDhAQAAAA==.Marxman:BAAANQAECgYIBgABNQAFFAUIDgAkABQcAA==.Mask:BAAANQADCgUIBQAAAA==.Masokhist:BAAANQABCgYIBQAAAA==.Mauchs:BAAANQADCgUICQAAAA==.Maxthegreat:BAAANQABCgYIBgAAAA==.',
Me='Meedar:BAAANQAECgQIBQAAAA==.Meganite:BAAANQADCgYIGgAAAA==.Melaniatrump:BAAANQADCgEIAQAAAA==.Meningitis:BAAANQAECgEIAQAAAA==.',
Mi='Miahas:BAAANQADCgMIAwAAAA==.Mikecoxwoll:BAABNQAECoEhAAMaAAgKGxQeJQAkAgAaAAgKGxQeJQAkAgAIAAMKqAFlUQBcAAAAAA==.Milkmountain:BAAANQADCgIJAwAAAA==.Milkymoo:BAAANQADCgcIBwAAAA==.Minalina:BAAANQAECggIEQAAAA==.Minalinapr:BAAANQAECggICAAAAA==.Minalinaria:BAAANQAECggIDgAAAA==.Mindedz:BAABNQAECoEeAAIJAAgKfRl3NABhAgAJAAgKfRl3NABhAgAAAA==.Minnow:BAABNQAECoEbAAIPAAcKWQkgiABvAQAPAAcKWQkgiABvAQAAAA==.Miren:BAABNQAECoEeAAIWAAgKRx06JQCWAgAWAAgKRx06JQCWAgAAAA==.Mittsmitts:BAAANQAECgQIBQAAAA==.',
Mo='Mochiberry:BAAANQAECggIAgAAAA==.Moistbuns:BAAANQAECgcIEwAAAA==.Molatova:BAAANQAECgcIDQAAAA==.Moozart:BAAANQAECgEIAQABNQAECggIIAAaAGYaAA==.Mooze:BAAANQAECgQIBAAAAA==.Morgiana:BAAANQAECgIIBQAAAA==.Mortiferia:BAABNQAECoElAAIeAAgKsCIcFAAAAwAeAAgKsCIcFAAAAwAAAA==.Mortzx:BAAANQAECgQIBAAAAA==.Motown:BAABNQAECoEcAAQOAAkKwSBcAgDJAgAOAAgK5yFcAgDJAgAQAAQKoBwIIABcAQAPAAQKFxg3nAA7AQAAAA==.',
Mu='Mundane:BAAANQADCggICAAAAA==.Muyo:BAAANQADCgEIAQAAAA==.Muzzlefaulf:BAAANQABCgIIAgAAAA==.',
Mw='Mwooq:BAAANQADCgYICAAAAA==.',
My='Mystics:BAABNQAECoEfAAIlAAgKxiEuBgAMAwAlAAgKxiEuBgAMAwAAAA==.Mystiklight:BAAANQADCgUIBQABNQAECgQIBwAHAAAAAA==.Mythomagic:BAABNQAECoEcAAIBAAgK6xbaeABVAgABAAgK6xbaeABVAgAAAA==.',
Na='Naebchi:BAAANQADCgUIBQAAAA==.Nahjiky:BAAANQADCgYIEQAAAA==.Nakotak:BAAANQABCgQIBgAAAA==.Nanalady:BAAANQADCggICAAAAA==.Nastyjob:BAAANQAECgYIDgAAAA==.Nazgar:BAAANQADCgUJBQAAAA==.',
Ne='Necronips:BAAANQADCgIIAgAAAA==.Neurosis:BAAANQADCggIGgAAAA==.Nezzthena:BAAANQADCgEIAQAAAA==.',
Ni='Niari:BAAANQAECgIIAgAAAA==.Nibelung:BAABNQAECoEkAAMXAAgKoiO0QgCaAQAXAAgKoiO0QgCaAQAfAAEK2x9oUQBbAAAAAA==.Nikale:BAAANQAECgUIEQAAAA==.',
No='Nordy:BAAANQAECgUICwAAAA==.Normadin:BAABNQAECoEaAAQCAAgKthPhcQDtAQACAAgKthPhcQDtAQADAAIK0grb1gBrAAAcAAEKKAg/YQAiAAAAAA==.Norsefolk:BAAANQADCgIIAgAAAA==.Norseroch:BAAANQADCgYJCgABNQADCgIIAgAHAAAAAA==.',
Nv='Nvd:BAABNQAECoETAAMIAAkKfB46GQBeAgAIAAgKoyE6GQBeAgAaAAEKRwUGcwA1AAABNQAFFAIJAgAHAAAAAA==.',
Ny='Nyan:BAAANQAECgcIDQABNQAECgkJKQADANcmAA==.Nysonnia:BAAANQAECgYIDwABNQAECgkJKQADANcmAA==.',
Ob='Obliterate:BAAANQAECgQIBwABNQAECgQICgAHAAAAAA==.Obsidianfire:BAAANQADCgQIBAABNQAECgQIBwAHAAAAAA==.',
Od='Odonn:BAAANQAECgMIAwAAAA==.Odìnsôn:BAAANQADCggIIAAAAA==.',
Om='Omegafortswl:BAAANQADCgYIHAAAAA==.Omeni:BAAANQAECgQICQAAAA==.',
On='Oneshockiboi:BAAANQADCgMIAwAAAA==.',
Oo='Oogiie:BAAANQAECgQIBAAAAA==.',
Or='Orbits:BAAANQAECgUIBAAAAA==.Oric:BAABNQAECoEpAAIDAAkK1yYJAAASBAADAAkK1yYJAAASBAAAAA==.',
Os='Oscargrouch:BAAANQADCgUIBQABNQAECggIDQAHAAAAAA==.',
Pa='Paledeath:BAAANQAECgEIAQAAAA==.Pallverize:BAAANQADCggICAAAAA==.Pannmann:BAAANQAECgQICAAAAA==.Panzerhunt:BAAANQAECgcIBQABNQAECgkJIAACAG4cAA==.Panzerpala:BAABNQAECoEgAAICAAkKbhySNQC0AgACAAkKbhySNQC0AgAAAA==.Panzersham:BAAANQAECgcIBQABNQAECgkJIAACAG4cAA==.Paperdaen:BAAANQAECgYICwAAAA==.Papertanuon:BAAANQABCgQIBAABNQAECgYICwAHAAAAAA==.Parkle:BAAANQADCgcIFgAAAA==.Pastore:BAAANQAECgcIEwAAAA==.',
Pe='Pelee:BAAANQABCgIIAgAAAA==.Pelos:BAAANQADCgEIAQAAAA==.Peonmè:BAAANQAECgMIBAAAAA==.Pepitopingon:BAAANQABCggICwAAAA==.',
Pf='Pfeffernusse:BAACNQAFFIEOAAIkAAUKFBy5BQCzAQAkAAUKFBy5BQCzAQA1AAQKgRcAAiQACQrrHdEVAIACACQACQrrHdEVAIACAAAA.',
Ph='Phalluic:BAAANQADCggIDgAAAA==.Philpriest:BAABNQAECoEZAAMGAAkKpxwREwCSAgAGAAgKnBwREwCSAgAeAAIKaBBctAB4AAAAAA==.',
Pl='Plagued:BAAANQAECgQJBwABNQABCgIJAgAHAAAAAA==.Plagueis:BAAANQADCgMIAwAAAA==.',
Po='Pochaccob:BAABNQAECoEYAAIfAAkK+haqDwChAgAfAAkK+haqDwChAgAAAA==.Pokeysticks:BAAANQAECgMIBQAAAA==.Poncia:BAAANQAECgYIDgAAAA==.',
Pr='Pragmax:BAAANQAECgYICgAAAA==.Praynation:BAAANQAECgEIAQAAAA==.Prediction:BAAANQAECgEIAgAAAA==.',
Pu='Puffcodan:BAAANQAECgEIAwAAAA==.Pugcival:BAAANQADCgUIBQAAAA==.Punîshër:BAAANQAECgUIBwAAAA==.Puppenance:BAAANQADCgUIBQAAAA==.Purgatoriwlf:BAABNQAECoEYAAIdAAkKCh4kGwD5AgAdAAkKCh4kGwD5AgAAAA==.Purplehayz:BAAANQADCgMJAwAAAA==.',
Py='Pyrogale:BAAANQADCggIFgAAAA==.',
['Pó']='Póe:BAAANQAFFAEIAQAAAA==.',
Ql='Qlimax:BAAANQAECgEJAQAAAA==.',
Qu='Quadzilla:BAAANQAECgQIBAAAAA==.Quem:BAAANQAECgYIBQAAAA==.',
Ra='Rachet:BAAANQADCgcIEAAAAA==.Ragnalock:BAAANQAECgIJAgAAAA==.Ragnir:BAAANQAECgEIAQABNQAECgIIAgAHAAAAAA==.Rainbowtits:BAAANQAECgMIAwAAAA==.Raker:BAAANQABCgcIDAAAAA==.Rarh:BAAANQADCgYICQAAAA==.Rathlokor:BAAANQADCgMJAwAAAA==.Rathlore:BAAANQADCgUIBQAAAA==.Rathorn:BAAANQAECgQIBAAAAA==.Rawdawgan:BAAANQADCgYIBwAAAA==.Rawrbotz:BAAANQADCgUIDgAAAA==.Razeneth:BAAANQAECggIBgAAAA==.',
Re='Rebornqt:BAAANQADCgIIAgAAAA==.Reforsaken:BAABNQAECoEkAAIlAAgKLRqhDQCAAgAlAAgKLRqhDQCAAgAAAA==.Relarian:BAAANQAECgYICgAAAA==.Releimus:BAAANQAECgYJBgAAAA==.Rentera:BAAANQADCggICAAAAA==.Revengeance:BAABNQAECoEfAAIcAAgKwhcgFAATAgAcAAgKwhcgFAATAgAAAA==.',
Ri='Ripnfade:BAAANQADCgcIBwAAAA==.Riptide:BAAANQAECgEIAQAAAA==.Rissler:BAAANQADCgQIBAAAAA==.Rithallie:BAAANQAECgQIBAAAAA==.',
Rm='Rmplstilskin:BAAANQADCgcIDAAAAA==.',
Ro='Roanoke:BAAANQABCgMIAwAAAA==.Rocketsauce:BAAANQAECgUJBwAAAA==.Romcrom:BAAANQAECgYICwAAAA==.Rommagicus:BAAANQADCggIDQABNQAECgYICwAHAAAAAA==.Rosalíe:BAAANQADCgQIBAAAAA==.Rougetoon:BAAANQADCggICAABNQAFFAQIBwABALQUAA==.Rouxnic:BAAANQADCgEIAQAAAA==.Roxen:BAABNQAECoEcAAIJAAgKQh1mJwCqAgAJAAgKQh1mJwCqAgAAAA==.',
Ru='Rubyhart:BAAANQADCgYIBgAAAA==.Rukenji:BAACNQAFFIEIAAIeAAQKvxQADQBfAQAeAAQKvxQADQBfAQA1AAQKgSUAAx4ACQrGIIIRABIDAB4ACQqMIIIRABIDACIABArLHK4OAA4BAAAA.Runehulk:BAAANQABCgQIBAAAAA==.Runíc:BAAANQADCgEIAQAAAA==.',
Ry='Ryuunosuke:BAABNQAECoEfAAImAAgK2hOdGAD6AQAmAAgK2hOdGAD6AQAAAA==.',
Sa='Sabers:BAAANQAECgcJDgAAAA==.Sabriinaa:BAAANQABCgMIBAAAAA==.Sabrinachi:BAAANQABCgIIAgAAAA==.Sabrinadin:BAAANQABCgQIBQAAAA==.Sadako:BAAANQAECgEIAQAAAA==.Sakkraa:BAABNQAECoEuAAMOAAkKIhyfAQABAwAOAAkKIhyfAQABAwAPAAEKdg7OAQE9AAAAAA==.Salla:BAAANQAECgMIAwAAAA==.Sandrawolf:BAAANQAECggICAABNQAECgkJGAAdAAoeAA==.Sannea:BAAANQADCgYIBwAAAA==.Saponite:BAAANQADCgIIAgAAAA==.Sarumon:BAAANQAECgYIEwAAAA==.',
Sc='Schwimdy:BAAANQAECgQICwAAAA==.Scrappey:BAAANQADCgYIBgAAAA==.',
Se='Secondlife:BAAANQADCgQIBAAAAA==.Seeingeyedog:BAABNQAECoEdAAIWAAgKRhtQNABKAgAWAAgKRhtQNABKAgAAAA==.Seraphicfrog:BAAANQADCgMIAwAAAA==.Sevenseconds:BAAANQADCgcIDQAAAA==.Sewerclam:BAAANQADCgQIBAAAAA==.',
Sh='Shadowscythe:BAAANQAECgQIDAAAAA==.Shadowzar:BAAANQAECgIIAgABNQAECgQIDAAHAAAAAA==.Shampann:BAAANQADCgEIAQAAAA==.Sharish:BAAANQABCggIBwAAAA==.Shaundel:BAABNQAECoExAAIWAAgKjxq/NQBDAgAWAAgKjxq/NQBDAgAAAA==.Shavocadoos:BAAANQADCggICAAAAA==.Shestrain:BAAANQADCgUIBgAAAA==.Shezmu:BAABNQAECoEaAAIEAAgKKiEhEgDzAgAEAAgKKiEhEgDzAgAAAA==.Shiftinman:BAAANQADCgMIAwAAAA==.Shiftintime:BAAANQADCgQIBAABNQAFFAIIBQAaANchAA==.Shlorp:BAAANQADCgIIAgAAAA==.Shoopa:BAAANQAECgQIBwAAAA==.Shoopah:BAAANQAECgUIEQAAAA==.Short:BAABNQAECoEeAAIlAAgKHA0QGAD5AQAlAAgKHA0QGAD5AQAAAA==.Shunned:BAAANQAECgMIAwAAAA==.Shyok:BAAANQADCgEJAQAAAA==.Shädøwreeper:BAAANQAECgMIAwAAAA==.',
Si='Siduiss:BAAANQAECgMJBAAAAA==.Silvrfoxx:BAAANQAECgQIBQAAAA==.Silvänus:BAABNQAECoEmAAMfAAgKoiLVCAAJAwAfAAgKoiLVCAAJAwAXAAEKIwY5kwAxAAAAAA==.Simsha:BAAANQAECgQIEAAAAA==.',
Sk='Skinnylejend:BAABNQAECoEYAAMGAAgKKhp3HAAWAgAGAAcKlBl3HAAWAgAeAAIKnwsFsQCGAAAAAA==.Skipperty:BAAANQAECgMIAgAAAA==.Skizzy:BAAANQADCgMIAwAAAA==.Skmoon:BAAANQADCgIIAgAAAA==.Skãr:BAAANQADCgYJBgAAAA==.',
Sl='Sloimmortal:BAAANQABCgQIBAAAAA==.',
Sm='Smiley:BAABNQAECoEXAAIUAAgKFxbcGgASAgAUAAgKFxbcGgASAgAAAA==.Smokedmeats:BAAANQADCgIIAgAAAA==.',
Sn='Snac:BAAANQAECgIJAwAAAA==.Snackrifice:BAAANQAECgMIAwAAAA==.Snacs:BAAANQADCgMIAwAAAA==.Sndancekd:BAAANQAECgYIDQAAAA==.Sneakybeanz:BAAANQAECgQIBAAAAA==.',
So='Sollan:BAAANQABCgUIBAAAAA==.Someperson:BAAANQAECgUIBQAAAA==.Somoner:BAABNQAECoEoAAMQAAgKayKUAgAfAwAQAAgKayKUAgAfAwAOAAEKsw8ZJgA5AAAAAA==.Sompal:BAAANQAECgQIBgABNQAECggIKAAQAGsiAA==.',
Sp='Sparklz:BAAANQADCgcIBwAAAA==.Sparksizzle:BAABNQAECoEhAAMBAAkKehSAeQBTAgABAAkKehSAeQBTAgAnAAMKqAZsBgCgAAAAAA==.Spiseyy:BAAANQADCgYIBgAAAA==.Spitfel:BAABNQAECoEYAAQQAAkKjCCjBgCPAgAQAAkKuhejBgCPAgAPAAUK3B98iABuAQAOAAEKSRx5IABKAAABNQAFFAUICQAXAPESAA==.Spitfirex:BAABNQAFFIEJAAIXAAUK8RJXCQCDAQAXAAUK8RJXCQCDAQAAAA==.Spreadshecat:BAABNQAECoEVAAIBAAgKKhGRnQAAAgABAAgKKhGRnQAAAgABNQAFFAEIAQAHAAAAAA==.',
St='Stoix:BAAANQADCgUIAgAAAA==.Stompymunk:BAAANQADCggIDwAAAA==.Stopzîlla:BAABNQAECoEaAAIlAAcK0hHJGwDRAQAlAAcK0hHJGwDRAQAAAA==.Strûmpet:BAAANQAECgQIBAAAAA==.',
Su='Sugrdadi:BAAANQAECgMIBQAAAA==.',
Sy='Sylmar:BAAANQAECgIIAgAAAA==.Syndora:BAABNQAECoEgAAIfAAgKyh7lDADIAgAfAAgKyh7lDADIAgAAAA==.',
Ta='Tacoboss:BAAANQAECgEIAQAAAA==.Taerun:BAAANQAECgIIAgAAAA==.Tahu:BAAANQAECgYJDQAAAA==.Takal:BAAANQADCgYICwAAAA==.Talorn:BAAANQADCgUIBQAAAA==.Talreth:BAAANQAECgQIBwAAAA==.Tappnlock:BAAANQABCgIIAgABNQAECgYJEgAHAAAAAA==.',
Te='Teake:BAAANQAECgIIAgAAAA==.Teddymoove:BAAANQADCgYIBgAAAA==.Teddyruxpin:BAAANQADCgcIBwAAAA==.Teddytotems:BAABNQAECoEZAAIJAAcKbRAyXgC1AQAJAAcKbRAyXgC1AQAAAA==.Teessel:BAAANQADCgQIBAAAAA==.Telemarketer:BAAANQAECgUIBQAAAA==.Tenebrisol:BAAANQADCgYJBgAAAA==.Ternal:BAAANQAECgMIAwAAAA==.Terrato:BAAANQAECgEIAQAAAA==.Terrorize:BAAANQAECgQIBwAAAA==.Terrorley:BAAANQADCgQIBAAAAA==.Terrous:BAACNQAFFIEHAAMbAAMKAwrcDwCMAAAbAAIKrA7cDwCMAAAEAAEKsQDiLwAQAAA1AAQKgSIAAhsACQplGyUgAIECABsACQplGyUgAIECAAAA.Tetranutra:BAAANQADCgQIBAAAAA==.',
Th='Thakur:BAAANQAECgYIEgAAAA==.Theoslight:BAAANQAECgQIBgAAAA==.Thepetmaster:BAAANQADCgUICgAAAA==.Thiccaxe:BAAANQAECgUIBQAAAA==.Thighler:BAAANQAECgYIDQAAAA==.Thordenson:BAAANQABCgIIAgAAAA==.Thrandorinil:BAAANQADCgQIBgAAAA==.Thraxia:BAAANQABCgQIBAAAAA==.Threxon:BAAANQAECgcIDwAAAA==.Thrine:BAAANQAECgEIAQAAAA==.Thunderfire:BAAANQAECgQIBwAAAA==.',
Ti='Timepally:BAAANQADCgYIBgAAAA==.Tinytimothy:BAAANQADCgIIAgAAAA==.',
To='Tokajok:BAABNQAECoErAAMIAAkKiR0hEADLAgAIAAgK0h4hEADLAgAVAAMKCg4qGwCZAAAAAA==.Tokash:BAAANQADCggICQABNQAECgkJKwAIAIkdAA==.Tokashi:BAAANQAECgcIDwABNQAECgkJKwAIAIkdAA==.Tokeadin:BAABNQAECoEbAAIDAAcK+BMVWgDAAQADAAcK+BMVWgDAAQAAAA==.Tokzillu:BAAANQADCgUIBQAAAA==.Tomaki:BAAANQADCgcJCgAAAA==.Toriimage:BAAANQAECgEIAQAAAA==.Toughluck:BAAANQAECgQIBAAAAA==.',
Tr='Trackervalk:BAAANQADCgMIBAAAAA==.Traellissa:BAAANQAECgEIAgAAAA==.Treeady:BAAANQAECgMJAgAAAA==.Trenbölöne:BAABNQAECoEhAAISAAgKfx3FQACOAgASAAgKfx3FQACOAgAAAA==.Treyrin:BAABNQAECoEUAAICAAYKYhwmdQDkAQACAAYKYhwmdQDkAQAAAA==.Tritonian:BAACNQAFFIEXAAIcAAcK2CMiAADwAgAcAAcK2CMiAADwAgA1AAQKgSkAAhwACQrFJl0AAPMDABwACQrFJl0AAPMDAAAA.Trixio:BAABNQAECoEUAAINAAgKyh9eDQDiAgANAAgKyh9eDQDiAgAAAA==.Trollmother:BAAANQADCggICAAAAA==.Trolloutcast:BAAANQAECgQICAABNQAFFAcIEQAPAHYeAA==.',
Tu='Turtle:BAACNQAFFIELAAIDAAUKCBSqBgCrAQADAAUKCBSqBgCrAQA1AAQKgS4AAgMACQonHF0ZAOcCAAMACQonHF0ZAOcCAAAA.',
Tw='Twizzlestick:BAAANQABCgUIBQAAAA==.',
Ty='Tyluwu:BAAANQAECgYIEgAAAA==.Tyranis:BAAANQADCgIIAgAAAA==.Tyzz:BAAANQAECgEIAgAAAA==.',
['Tì']='Tìtân:BAAANQADCgcIBwAAAA==.',
['Tÿ']='Tÿ:BAABNQAECoEaAAMdAAgKziTxCQBuAwAdAAgKziTxCQBuAwAkAAEK+AoRcgAvAAAAAA==.',
Ud='Uddercleanse:BAAANQADCgYIBgABNQAECgkJKAAiAFAfAA==.',
Um='Umbrianna:BAABNQAECoEeAAIaAAgKIgVjPQBiAQAaAAgKIgVjPQBiAQAAAA==.',
Un='Undeadashyra:BAAANQADCgYIBgAAAA==.Unstablemagi:BAAANQADCgYIBgAAAA==.',
Uv='Uvulabean:BAAANQAECgQIBAAAAA==.',
Uw='Uwuclapmexd:BAAANQADCgMJAwAAAA==.Uwuhunterxd:BAACNQAFFIEFAAIkAAIK3wXyFgB+AAAkAAIK3wXyFgB+AAA1AAQKgSEAAyQACQruGLAXAGsCACQACQp3GLAXAGsCAB0AAQpeIpQDAV0AAAAA.',
Va='Vaelowyn:BAAANQAECgQIBQAAAA==.Vaelthyr:BAAANQADCggIEAABNQAECgkJJQAcAMoUAA==.Vakar:BAAANQAECgQIDQAAAA==.Valkorath:BAAANQAECgUIBQAAAA==.Valkyriee:BAAANQADCgMIAwAAAA==.Varninn:BAAANQADCgcIEAAAAA==.Varonos:BAAANQAECggICQAAAA==.Vasha:BAAANQAECgYICwAAAA==.',
Ve='Ventee:BAAANQAECgUICwAAAA==.Verymelon:BAAANQAECgEIAQAAAA==.',
Vi='Vincentv:BAAANQADCgYIBgAAAA==.Virtuositee:BAAANQADCgYICwABNQAECggIJgAEAGAaAA==.Vitadin:BAAANQAECgQICQAAAA==.',
Vo='Voidseeker:BAAANQABCgMIAwAAAA==.',
Vr='Vraugashan:BAAANQAECgcICgAAAA==.Vrice:BAAANQADCgIIAgAAAA==.',
['Vá']='Váprak:BAAANQADCgcICAAAAA==.',
Wa='Walmage:BAAANQADCgYIBgAAAA==.Wannabe:BAAANQABCgUIBQABNQAECggIGgAdAM4kAA==.Warbuck:BAAANQADCgUIBAAAAA==.Warlas:BAAANQAECgEIAQAAAA==.',
We='Wesson:BAAANQAECgUIEwAAAA==.',
Wh='Whompie:BAAANQABCgEIAQAAAA==.',
Wi='Winning:BAABNQAECoEcAAIdAAkKKB13IADeAgAdAAkKKB13IADeAgAAAA==.Wireless:BAABNQAECoEhAAMNAAkKFg6XJwDqAQANAAgKKw2XJwDqAQAlAAcK5QmPIwCDAQAAAA==.',
Wo='Wokker:BAAANQADCggIFAAAAA==.',
Wq='Wqwq:BAAANQADCgEIAQAAAA==.',
Wu='Wuköng:BAAANQAECgQJBwAAAA==.',
Xa='Xau:BAAANQABCgcICAAAAA==.Xaveak:BAAANQADCgYICwAAAA==.',
Xe='Xencero:BAAANQAECgQICgAAAA==.Xeum:BAABNQAECoEYAAMeAAYK6xuVVwC+AQAeAAYK6xuVVwC+AQAGAAEKcQZXYwAvAAAAAA==.',
Xg='Xgirlfriend:BAAANQAECgQICwAAAA==.',
Xh='Xhar:BAABNQAECoEZAAIBAAgK9BPOfABLAgABAAgK9BPOfABLAgAAAA==.Xhyros:BAABNQAECoEhAAIFAAkKhCDGBAArAwAFAAkKhCDGBAArAwAAAA==.',
Xi='Xiahou:BAABNQAECoEfAAIBAAgKQiKyOAD5AgABAAgKQiKyOAD5AgAAAA==.',
Xo='Xoothette:BAAANQADCgcIBwABNQAFFAcIEQAPAHYeAA==.',
Ya='Yahnari:BAAANQADCgMIAwAAAA==.',
Ye='Yel:BAACNQAFFIEIAAIFAAUKnhl8AgC5AQAFAAUKnhl8AgC5AQA1AAQKgScAAgUACQpvI4sCAHUDAAUACQpvI4sCAHUDAAAA.',
Yu='Yuanfen:BAAANQAECgMIBAAAAA==.Yunaraz:BAAANQADCgEIAQAAAA==.Yungshrimpy:BAAANQADCgYIBgAAAA==.',
Za='Zaffira:BAAANQAECgYIDAAAAA==.Zamlen:BAABNQAECoEgAAIBAAgKARgMfgBIAgABAAgKARgMfgBIAgAAAA==.Zaq:BAAANQAECgYIBgAAAA==.Zaradissa:BAAANQADCgEIAQAAAA==.Zargan:BAAANQAECgQIDAAAAA==.Zargstrike:BAAANQADCggIDQABNQAECgQIDAAHAAAAAA==.Zazie:BAABNQAECoEeAAIEAAgKThN8OwDVAQAEAAgKThN8OwDVAQAAAA==.',
Ze='Zedicuzz:BAAANQAECgQIEQAAAA==.Zeesala:BAAANQADCgUIBwABNQAECgkJKQADANcmAA==.Zemms:BAAANQADCggICAAAAA==.',
Zi='Zinbad:BAAANQADCgYIBgAAAA==.Zippbang:BAAANQADCgEIAQAAAA==.Zithazar:BAAANQADCgIIAgAAAA==.Zivyrial:BAAANQAECgUJCgAAAA==.',
Zu='Zugerrnaught:BAAANQADCgYIBgAAAA==.Zugzugzugzug:BAABNQAECoEjAAQZAAkKcyZmAQDMAwAZAAkKcyZmAQDMAwAEAAMKNSCnZQASAQAbAAEKASKLmgBfAAABNQAECgkJGgACAKAjAA==.Zuken:BAAANQAECgQIBAAAAA==.Zuriki:BAAANQADCgMIAwAAAA==.',
['År']='Årdentmeta:BAAANQAECgIIAgABNQAECgYICwAHAAAAAA==.',
['Ñe']='Ñemo:BAABNQAECoEhAAMdAAgKyiJUGAAJAwAdAAgKyiJUGAAJAwAkAAMKQxAvUgCJAAAAAA==.',
['Ør']='Øreo:BAAANQADCggIFQAAAA==.',
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
