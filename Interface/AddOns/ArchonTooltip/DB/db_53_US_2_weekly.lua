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

local lookup = {'Unknown-Unknown','Hunter-Survival','Hunter-BeastMastery','Warlock-Demonology','DeathKnight-Unholy','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Devourer','Evoker-Devastation','Evoker-Preservation','Shaman-Restoration','Druid-Restoration','Warrior-Arms','Priest-Shadow','Druid-Feral','DemonHunter-Vengeance','Hunter-Marksmanship','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Druid-Guardian','Priest-Discipline','Priest-Holy','DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction','Shaman-Enhancement','Shaman-Elemental','Monk-Windwalker','Warrior-Fury','Monk-Mistweaver','DeathKnight-Blood','Paladin-Protection','Druid-Balance','DeathKnight-Frost','Evoker-Augmentation',}
local provider = {region='US',realm='AeriePeak',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aarella:BAAANQADCgcIGQAAAA==.',
Ab='Ablaez:BAAANQAECgQICwAAAA==.',
Ac='Acetaeon:BAAANQADCgQIBAAAAA==.Actionpants:BAAANQADCgcIEAAAAA==.',
Ad='Adderaul:BAAANQAECgMIBAAAAA==.Adonrager:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.Adoraesta:BAAANQADCggIFwAAAA==.Adveshan:BAACNQAFFIEJAAICAAUJMBoUAAD3AQACAAUJMBoUAAD3AQA1AAQKgR8AAgIACQnQJFwAAKgDAAIACQnQJFwAAKgDAAE1AAEKAggCAAEAAAAA.',
Ae='Aelmantis:BAAANQAECgQICQAAAA==.Aer:BAAANQADCggIEQAAAA==.Aerumas:BAAANQABCgYIDQAAAA==.Aesirson:BAAANQAECgMIBAAAAA==.',
Af='Affience:BAAANQAECgIIBAAAAA==.Afira:BAAANQADCgMIAwABNQAECgcIEgABAAAAAA==.',
Ag='Agzull:BAAANQAECgEIAQAAAA==.',
Ai='Aiers:BAAANQAECgUIBQABNQAFFAEIAQABAAAAAA==.Aimbot:BAAANQADCgcIBgAAAA==.Aither:BAAANQAECgQIBAAAAA==.Aivier:BAAANQADCgUIBQAAAA==.',
Ak='Akella:BAAANQADCggIEQABNQAECgQICwABAAAAAA==.Akichi:BAAANQAECgUICAAAAA==.',
Al='Aladelre:BAAANQAECgUICwAAAA==.Alagnir:BAAANQAECgUIBgAAAA==.Alakazamm:BAAANQAECgEIAQAAAA==.Alanrickman:BAAANQADCgIIAgAAAA==.Aldaßoltz:BAAANQAECgQIBgABNQAFFAUIDAADAMQbAA==.Aldineri:BAAANQADCgcIGAAAAA==.Aleiceline:BAAANQADCggIDQAAAA==.Alexxdataint:BAAANQADCggIDQAAAA==.Alficthis:BAAANQADCgcIFAAAAA==.Alliena:BAAANQAECgIIBAAAAA==.Alluera:BAAANQADCgYIBwAAAA==.Alomere:BAAANQADCgMIAwABNQAECggIEgABAAAAAA==.Alyssarra:BAAANQADCgYIBgABNQAECggIGwADAFUkAA==.Alyxstra:BAAANQAECgQIBAAAAA==.',
Am='Ambernox:BAAANQADCgcIFwAAAA==.Amee:BAAANQADCgYIBgAAAA==.Amnis:BAAANQAECgUIBgAAAA==.Amuuna:BAAANQADCggICwAAAA==.',
An='Analiese:BAAANQAECgEIAQAAAA==.Anathame:BAAANQADCgcIBwAAAA==.Anaura:BAAANQAECgIIBAAAAA==.Ancientjudge:BAAANQABCgYIBAAAAA==.Andorn:BAAANQAECgYIDgAAAA==.Andralais:BAAANQADCggICwAAAA==.Animorphz:BAAANQAECgEIAQAAAA==.Annasthesia:BAEANQADCggIEwAAAA==.Anrothar:BAAANQADCggIFAAAAA==.Anth:BAAANQADCgcIGAAAAA==.Antimordum:BAABNQAECoEgAAIEAAgJKyIFDwDpAgAEAAgJKyIFDwDpAgAAAA==.',
Ap='Apaal:BAAANQADCgMIAwABNQAECggIHAAFAKEhAA==.Apathas:BAAANQAECgUIDAAAAA==.Aphaysia:BAAANQAECgUICQAAAA==.Apollodin:BAAANQAECgMIAwAAAA==.Appleblossom:BAAANQAECgQIBwAAAA==.Applejåcks:BAAANQADCggIDQAAAA==.Applzmonk:BAAANQADCgUIDAABNQAECgYIDgABAAAAAA==.',
Aq='Aquarion:BAAANQADCgQIBAAAAA==.',
Ar='Arcandore:BAAANQADCgYICwAAAA==.Archmichaels:BAAANQADCgcIGAAAAA==.Arianaglande:BAAANQAECgEIAQAAAA==.Ariandran:BAAANQADCgcIFwAAAA==.Aribethtylm:BAAANQAECggIBwAAAA==.Arithelor:BAAANQADCggIDAAAAA==.Arlich:BAAANQADCggICQAAAA==.Arouse:BAAANQADCgcICgABNQAECgQIBAABAAAAAA==.Arraxion:BAAANQAECgMIAwAAAA==.Arthelaes:BAAANQADCgcIFQABNQAECgYIDAABAAAAAA==.',
As='Ashaei:BAABNQAECoEYAAMGAAkJPBxdBQASAwAGAAkJPBxdBQASAwAHAAcJBRQCBwDPAQAAAA==.Asherynn:BAAANQADCgYIDgAAAA==.Ashiadana:BAAANQADCgUICQAAAA==.Ashkariel:BAAANQAECgUICwAAAA==.Ashmalan:BAAANQADCgUIDAAAAA==.Ashtare:BAAANQADCgYIBgAAAA==.Asmodeá:BAAANQADCgMIAwAAAA==.Astrada:BAEANQADCggICAABNQAECgkJGwADAC0dAA==.Astrauza:BAAANQADCgcIDAAAAA==.Astritara:BAAANQADCggIEQAAAA==.',
At='Atramedes:BAACNQAFFIEHAAIIAAQJ/hgdAwBuAQAIAAQJ/hgdAwBuAQA1AAQKgRkAAggACQnnHrEIABQDAAgACQnnHrEIABQDAAAA.',
Au='Auldus:BAAANQAECgEIAQAAAA==.Aureliya:BAAANQAFFAIIAgAAAA==.Automagnus:BAAANQAECgQICAAAAA==.',
Av='Avashields:BAAANQAECggIBgAAAA==.Avvy:BAAANQADCgEIAQAAAA==.',
Ay='Ayabestie:BAACNQAFFIEJAAMJAAUJGCKzAgAmAQAJAAMJjR+zAgAmAQAKAAMJ9wUrBgDfAAA1AAQKgR8AAwkACQlVIiEEABwDAAkACAkgIiEEABwDAAoABAnKEMcfAAsBAAAA.Ayaki:BAAANQAECgQICAAAAA==.',
Az='Azeliana:BAAANQADCgIIAgAAAA==.Azlyn:BAAANQADCgcIDwAAAA==.Azmyra:BAAANQAECgEIAQAAAA==.Azoll:BAAANQADCgYIBgAAAA==.Azrielle:BAAANQADCgYICwAAAA==.Azyr:BAAANQAECgEIAwAAAA==.',
['Aê']='Aêrîth:BAAANQAECgIIBAAAAA==.',
['Aï']='Aïko:BAABNQAECoEYAAILAAkJyiCgDQD1AgALAAkJyiCgDQD1AgAAAA==.',
['Aø']='Aø:BAAANQADCgYIFQAAAA==.',
Ba='Babz:BAAANQADCgcIBwAAAA==.Badandruid:BAAANQAECgEIAQAAAA==.Badnes:BAAANQAECggICAAAAA==.Bajablastboy:BAAANQAECgEIAQAAAA==.Bakalakadaka:BAABNQAECoEZAAIMAAgJ8RReDwAtAgAMAAgJ8RReDwAtAgAAAA==.Balbar:BAAANQADCgUIBgAAAA==.Balsin:BAAANQADCgcIBwABNQAECgYIDwABAAAAAA==.Bananaslamma:BAAANQADCggICgAAAA==.Banegrim:BAAANQADCgUICAAAAA==.Baowaow:BAAANQADCggIDgAAAA==.Baseed:BAAANQAECgYIDwAAAA==.Bastelsyn:BAAANQADCggIGQAAAA==.',
Be='Beatitude:BAAANQAECgEIAQAAAA==.Beauorigin:BAAANQAECgcIEQAAAA==.Beañ:BAAANQAECgUIDAAAAA==.Beelzebubb:BAAANQADCggIEQAAAA==.Befus:BAAANQAECggIEAAAAA==.Beiral:BAAANQAECgMIAwAAAA==.Belenna:BAAANQAECgEIAwABNQAECgkJIAAFAHMhAA==.Bellatori:BAAANQADCgcIGQAAAA==.Bellion:BAEANQAECgUICQAAAA==.Berabin:BAAANQAECgEIAQAAAA==.Berrie:BAAANQADCgMIAwAAAA==.Berryle:BAAANQAECgQIBgAAAA==.Beån:BAAANQADCgEIAQABNQAECgUIDAABAAAAAA==.',
Bi='Biggbby:BAAANQAECgEIAQAAAA==.Billybone:BAABNQAECoEZAAINAAkJmh/EEQA5AwANAAkJmh/EEQA5AwAAAA==.Billyocean:BAAANQAECgcIDQAAAA==.',
Bl='Blast:BAAANQAECgYIBgABNQAFFAQIBwAIAP4YAA==.Blazelight:BAAANQADCgYIBgAAAA==.Blimp:BAAANQAECgIIAgAAAA==.Blindelf:BAAANQAECgQICwAAAA==.Bloodbank:BAAANQAECgMIBAAAAA==.Bloodeye:BAAANQAECgMIBAAAAA==.Bloodsheds:BAAANQADCgIIAgAAAA==.Bloodybones:BAAANQADCggIDQAAAA==.Bloompimp:BAAANQADCgYICwAAAA==.Bloriren:BAAANQADCgIIAgAAAA==.Bluebearly:BAAANQADCgcIDgAAAA==.Bluenut:BAAANQAECgQIBQABNQAECggIEwABAAAAAA==.Blurey:BAAANQADCggIDAAAAA==.Blãzè:BAAANQADCgUICQAAAA==.',
Bo='Bobseger:BAAANQAECgEIAQAAAA==.Bolloxd:BAAANQAECgIIAwAAAA==.Boombadabang:BAAANQADCgcICgAAAA==.Boombuckpow:BAAANQAECgMIBAAAAA==.Boomkïn:BAAANQABCgQIBQAAAA==.Borninbane:BAAANQADCgEIAQAAAA==.Bovinescat:BAAANQADCggIEQAAAA==.Boxercat:BAAANQABCgQIBAAAAA==.',
Br='Brachetto:BAAANQADCgQIBAAAAA==.Brandeads:BAAANQAECgQIBwAAAA==.Brandoch:BAAANQAECgEIAQAAAA==.Brecker:BAAANQADCgQIBAABNQAECgcIEQABAAAAAA==.Breetai:BAAANQADCggIEQAAAA==.Brevabos:BAAANQADCgUICAAAAA==.Brewmere:BAAANQAECggIEgAAAA==.Briggigne:BAABNQAECoEbAAIFAAkJjCRGAwCnAwAFAAkJjCRGAwCnAwAAAA==.Brimstonë:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Bronch:BAAANQAECgQIBgAAAA==.Brord:BAAANQADCgEIAQAAAA==.Brownikiller:BAAANQAECgEIAgAAAA==.',
Bu='Buddm:BAAANQAECgEIAQAAAA==.Bullzor:BAAANQADCgYIBgAAAA==.',
By='Byrna:BAAANQABCgMIAwAAAA==.',
['Bà']='Bàlan:BAAANQADCgIIAgAAAA==.',
['Bó']='Bóyardee:BAAANQADCgYIBgABNQADCggIHwABAAAAAA==.',
Ca='Cabrön:BAAANQAECgEIAgAAAA==.Caeyth:BAABNQAECoEgAAIOAAkJnCG0AwB6AwAOAAkJnCG0AwB6AwAAAA==.Calathelyn:BAAANQAECgIIAgAAAA==.Calendore:BAAANQAECgEIAQAAAA==.Caliban:BAAANQADCgcIEgAAAA==.Caliista:BAAANQAECgEIAgAAAA==.Caliphany:BAAANQAECgQIBwAAAA==.Calipso:BAAANQADCgYIEgAAAA==.Callmezan:BAAANQAECgcIEAAAAA==.Calltihump:BAAANQADCgUIBQAAAA==.Caltore:BAAANQAECgUICQAAAA==.Canopia:BAAANQADCgMIAwAAAA==.Cara:BAAANQADCgUICAAAAA==.Caramason:BAAANQADCgYIDQAAAA==.Carandris:BAAANQAECgQIBwAAAA==.Carbon:BAAANQADCggIDgAAAA==.Carindel:BAAANQAECgUICAAAAA==.Cazluzkal:BAAANQADCgEIAQAAAA==.',
Ch='Chaos:BAAANQAECgMIAwAAAA==.Chardd:BAAANQABCgYIBgAAAA==.Cheetarius:BAAANQAECgQIBwAAAA==.Childe:BAAANQADCgQICAAAAA==.Chilladin:BAAANQAECgUICAAAAA==.Christobelle:BAAANQAECgUIDQAAAA==.Chromrami:BAAANQABCgIIAgAAAA==.Chà:BAAANQAECgYIBgABNQAFFAIIAgABAAAAAA==.',
Ci='Cilraaz:BAAANQAECgUICgAAAA==.Cindraiz:BAAANQADCgcIDAAAAA==.',
Cl='Cliffburton:BAAANQABCgQIBAAAAA==.Cllab:BAAANQADCgYICgAAAA==.Cloverleigh:BAAANQADCgcIFQAAAA==.',
Co='Coatlicue:BAAANQADCgcIBwAAAA==.Cocoapuff:BAAANQADCgQIBAAAAA==.Codeblue:BAAANQADCgYICQAAAA==.Columbia:BAAANQADCgcIEAAAAQ==.Comfyrogue:BAAANQAECggICgAAAA==.Congress:BAAANQAECgIIAgAAAA==.Constantin:BAAANQADCggICwAAAA==.Consul:BAAANQADCgYICwAAAA==.Corelius:BAAANQAECgEIAQAAAA==.Corggi:BAAANQADCgcICQAAAA==.Corimin:BAAANQAECgIIAgAAAA==.Corntortilla:BAAANQADCgYIBgAAAA==.Cornwhiskey:BAAANQABCgEIAQAAAA==.Corrupten:BAEANQADCgQIBAABNQAECgcIEQABAAAAAA==.Coski:BAAANQADCggICAAAAA==.',
Cr='Crittmypants:BAAANQADCgMIAwAAAA==.Crowblast:BAAANQADCgYIBgAAAA==.Crowno:BAAANQADCgQICwAAAA==.Crumbsinbed:BAAANQAECgEIAQAAAA==.Crystalswan:BAAANQAECgIIAgAAAA==.',
Cy='Cybeloras:BAAANQABCgYIBgAAAA==.Cyoneii:BAAANQAECgEIAgAAAA==.Cyrusdk:BAAANQADCgUIBQAAAA==.',
Da='Dabestest:BAAANQADCgIIAgAAAA==.Dadnus:BAAANQADCgEIAQAAAA==.Dadnuss:BAAANQADCgUIBQAAAA==.Dalanas:BAAANQAECgEIAQAAAA==.Dalmatrius:BAAANQAECgYICAABNQAECgcIAQABAAAAAA==.Damariscotta:BAAANQABCgEIAQAAAA==.Dantespardaa:BAAANQAECgMIAwAAAA==.Darckattey:BAAANQAECgQIBwAAAA==.Darkmending:BAAANQAECgEIAQAAAA==.Darkskyou:BAAANQAECgQIBQAAAA==.Darkvane:BAAANQADCgcIBwAAAA==.Daroki:BAAANQADCgYIBgAAAA==.Darthkai:BAAANQABCgIIAgAAAA==.Dashifen:BAAANQADCgUIBwAAAA==.Dashwing:BAAANQAECgQIBAAAAA==.Dawncrest:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.',
De='Deadlishift:BAAANQADCgcIEgAAAA==.Deadlishot:BAAANQAECgIIAgAAAA==.Deadlybabe:BAAANQADCgUIDAAAAA==.Deathkitten:BAAANQADCgQIBAABNQADCgYIDQABAAAAAA==.Deathramzi:BAAANQADCgQIBAAAAA==.Deathsketch:BAAANQAECgYIBgABNQAECgkJGwAPAPIgAA==.Decày:BAAANQADCggIDwAAAA==.Delamari:BAAANQADCgcIDgAAAA==.Delfas:BAAANQAECgMIAwAAAA==.Demidove:BAAANQADCggICAAAAA==.Demitri:BAAANQAECggIEwAAAA==.Demonetized:BAAANQAECgIIAwAAAA==.Demonfen:BAAANQADCgUIEQABNQADCgYIBgABAAAAAA==.Demonsbane:BAAANQAECgQICAAAAA==.Depression:BAAANQADCgcIBgABNQAECgEIAgABAAAAAA==.Derfon:BAAANQAECgcIDgAAAA==.Deviousdevil:BAAANQAECgIIAgAAAA==.Devlenn:BAAANQAECgMIBAAAAA==.Devolutioned:BAAANQABCgIIAgAAAA==.',
Dk='Dkrisen:BAAANQAECgcIEwAAAA==.Dksou:BAAANQAECgUIDAAAAA==.',
Do='Dolpin:BAAANQAECgMIAwAAAA==.Donniedead:BAAANQAECgMIBAAAAA==.Doohickey:BAAANQAECggIAwAAAA==.Dorrestia:BAAANQABCgQIBAAAAA==.',
Dr='Drachkovitch:BAAANQAECgIIAgAAAA==.Dracil:BAAANQADCgcIDQAAAA==.Drackat:BAAANQADCgYIDwAAAA==.Dractiraffe:BAABNQAECoEcAAIJAAkJyyViAADiAwAJAAkJyyViAADiAwAAAA==.Dragdeznutz:BAAANQADCgIIAgAAAA==.Dragonreaver:BAAANQADCgcIBwAAAA==.Dragranos:BAAANQAECgEIAQAAAA==.Draigon:BAAANQADCgcIFQAAAA==.Drakengard:BAAANQADCggIEgAAAA==.Drakloak:BAACNQAFFIEIAAIQAAUJHSIYAAAEAgAQAAUJHSIYAAAEAgA1AAQKgSIAAhAACQnvJR0AAPIDABAACQnvJR0AAPIDAAAA.Drathos:BAAANQAECgIIAgAAAA==.Dravot:BAAANQABCgQIBgAAAA==.Drirden:BAAANQADCgMIAwAAAA==.Drixxì:BAAANQADCgYIFQAAAA==.Drobette:BAAANQADCgcIFQAAAA==.Drobnar:BAAANQADCgUIBQABNQADCgcIFQABAAAAAA==.Druam:BAAANQADCgQICQAAAA==.Druvett:BAAANQADCgYIEQAAAA==.',
Du='Duglar:BAAANQAECgEIAQAAAA==.Dumpsterdan:BAAANQAECgcIDwAAAA==.Duncarin:BAAANQAECgQICQAAAA==.Dunkstik:BAAANQAECgcIEQAAAA==.Duskedge:BAAANQADCgYICwAAAA==.',
Dx='Dxenzo:BAAANQAECgQIBwAAAA==.',
Dy='Dynamo:BAAANQAECgYICQAAAA==.',
['Dä']='Däwwg:BAAANQAECgQIBgAAAA==.',
Ea='Easypalm:BAAANQADCggIGgAAAA==.Eater:BAAANQAECgEIAQAAAA==.',
Eb='Ebonsùn:BAAANQAECgUICgAAAA==.',
Ed='Eden:BAAANQAECgMIBAAAAA==.Edgeadin:BAAANQADCggICAAAAA==.Edgeen:BAAANQAECgQIBQAAAA==.Edgesmash:BAAANQAECgYICgAAAA==.',
El='El:BAAANQAECgQIBgAAAA==.Elfraa:BAAANQADCgQIBgABNQADCgYIFQABAAAAAA==.Elide:BAAANQAECgEIAQAAAA==.Eliraena:BAAANQADCggIEQAAAA==.Ellasantra:BAAANQADCggIEwAAAA==.Ellasar:BAAANQAECgMIBQAAAA==.Elliere:BAAANQAECgYIBgABNQAECgkJFwARAJkeAA==.Elta:BAAANQAECgcIEAAAAA==.Eluvia:BAAANQADCgQIBAAAAA==.',
En='Encovaxx:BAAANQAECgYIDAAAAA==.Enlighthen:BAAANQAECgQICAAAAA==.',
Er='Erikahn:BAAANQAECgUICQAAAA==.Erranor:BAAANQADCgcIFQAAAA==.Erymontis:BAAANQAECgQIBAAAAA==.',
Es='Esstrielle:BAAANQADCgQIBQAAAA==.',
Et='Etched:BAAANQADCggICgABNQAFFAQIBwAIAP4YAA==.',
Ev='Evellynn:BAAANQADCggIGQAAAA==.Evermight:BAAANQABCgQIBgAAAA==.Evonker:BAAANQAECgYIDgAAAA==.',
Ex='Exadius:BAACNQAFFIEHAAIMAAQJChAhAgBGAQAMAAQJChAhAgBGAQA1AAQKgRkAAgwACQkkG2IHANMCAAwACQkkG2IHANMCAAAA.Exit:BAAANQADCgcIDQAAAA==.',
Ez='Ezakaa:BAAANQAECgQICQAAAA==.Ezgo:BAAANQADCgUICQAAAA==.',
['Eá']='Eádg:BAAANQADCgYICgAAAA==.',
['Eã']='Eãdg:BAAANQADCgMIBgAAAA==.',
Fa='Faanu:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Falathir:BAAANQAECgIIAgAAAA==.Falsehope:BAAANQABCgQIBAAAAA==.Fax:BAAANQADCggIEQAAAA==.Faýt:BAAANQADCggIEwAAAA==.',
Fd='Fdkt:BAAANQAECgUICAAAAA==.',
Fe='Feleanore:BAAANQAECgQIBQAAAA==.Feltempest:BAAANQADCggIDgAAAA==.Feltraz:BAAANQADCgcIFQAAAA==.Fenalane:BAAANQADCgYICwAAAA==.Fenniox:BAAANQADCgYIBgAAAA==.Fensdragon:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
Fi='Fiermicon:BAAANQAECgYIEAAAAA==.Finariya:BAAANQADCgQIBAAAAA==.Findula:BAEANQADCgUICAAAAA==.Finnardium:BAAANQAECgcIDgAAAA==.Firenova:BAAANQAECgUICwAAAA==.Fishslap:BAAANQAECgQICQAAAA==.',
Fl='Flattus:BAAANQADCgcIDAAAAA==.Flayfreak:BAAANQAECgEIAQAAAA==.Flibit:BAAANQADCgYICgAAAA==.Flordemon:BAAANQADCgUIBQAAAA==.Flordread:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.Flortheriann:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
Fo='Fonzarelli:BAAANQADCgcIEwAAAA==.Formula:BAAANQAECgIIAgAAAA==.',
Fr='Fraggs:BAAANQAECgIIAgAAAA==.Freyafenris:BAAANQADCggIGgABNQAECgQIBQABAAAAAA==.Frinban:BAAANQAECgEIAQAAAA==.Froggysham:BAAANQADCgYIBgAAAA==.Frubbles:BAAANQAECgIIBAAAAA==.Frydcomadant:BAAANQAECgIIAgAAAA==.',
Fu='Funran:BAAANQAECgMIBAAAAA==.Furdri:BAAANQADCgEIAQAAAA==.Furocious:BAAANQABCgcIBwAAAA==.Future:BAAANQADCggIFgAAAA==.Fuze:BAAANQAECgUIDQAAAA==.Fuzzyjager:BAEANQADCgcIEgAAAA==.Fuzzypumpkin:BAAANQADCgQIBQAAAA==.',
['Fá']='Fáthermaxi:BAAANQADCggIEgAAAA==.',
Ga='Gailyndra:BAABNQAECoEZAAIDAAgJ7xOAMAA4AgADAAgJ7xOAMAA4AgAAAA==.Gamba:BAAANQAECgMIBAAAAA==.Gandeyedeyne:BAAANQADCgMIAwAAAA==.Ganzilla:BAAANQAECgUICQAAAA==.Garakk:BAAANQADCgcIBwAAAA==.Garce:BAAANQADCggIEwAAAA==.Garthunter:BAAANQADCgQIBQAAAA==.Gatorage:BAAANQADCgcICAAAAA==.Gazember:BAAANQAECgYICwAAAA==.',
Ge='Genkidin:BAAANQAECgQIBgAAAA==.Genraam:BAAANQADCgUICgAAAA==.Gerrus:BAAANQADCgcIFQAAAA==.',
Gh='Ghoststout:BAAANQADCgIIAwAAAA==.',
Gi='Giggillow:BAAANQAECgYIDAAAAA==.Gingertonic:BAAANQAECgMIBAAAAA==.Girlypop:BAAANQAECgUIBQAAAA==.Givemenugs:BAAANQADCgcIFQAAAA==.',
Gl='Glockstrap:BAAANQAECgYICgAAAA==.Gluteusmaxx:BAAANQAECgcICwAAAA==.Glìssa:BAAANQADCgQIBAAAAA==.',
Go='Goggles:BAAANQADCggIHgAAAA==.Goldstag:BAAANQAECgEIAQAAAA==.Gonzypoowoo:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Goodvell:BAAANQAECgEIAQAAAA==.Goonacide:BAAANQAECgUICQAAAA==.Gou:BAAANQAECgIIAgAAAA==.',
Gp='Gpie:BAAANQAECgQIBwAAAA==.',
Gr='Graeves:BAAANQADCgQIBQAAAA==.Gravebane:BAAANQAECgIIBAAAAA==.Graycloak:BAAANQADCgYIEgAAAA==.Graydersher:BAAANQADCggIEwAAAA==.Gregsixnine:BAAANQADCgYICwAAAA==.Greshimus:BAAANQAECgUICQAAAA==.Greshticuffs:BAAANQAECgMIAwABNQAECgUICQABAAAAAA==.Greyelder:BAAANQADCgQIDAAAAA==.Greyrain:BAAANQADCgQICgABNQADCgQIDAABAAAAAA==.Greyroxy:BAAANQADCgQIBAABNQADCgQIDAABAAAAAA==.Greyskye:BAAANQADCgQICgABNQADCgQIDAABAAAAAA==.Greyywind:BAAANQADCgUIBgAAAA==.Grimsley:BAAANQADCggIFgAAAA==.Gripbob:BAAANQADCgUIBQAAAA==.Grizeban:BAAANQABCgYICAAAAA==.Grombindal:BAAANQAECgUICAAAAA==.Grrief:BAAANQADCgEIAQAAAA==.',
Gu='Guavamilktea:BAAANQAECgQIBgABNQAECgcIDQABAAAAAA==.Guildwarstoo:BAABNQAECoEaAAIDAAkJjSCeBgBmAwADAAkJjSCeBgBmAwAAAA==.',
Gw='Gwendolin:BAAANQADCggIGQAAAA==.',
Gy='Gyles:BAAANQADCgIIAgAAAA==.',
['Gø']='Gøkü:BAAANQAECgIIAgAAAA==.',
Ha='Haariik:BAAANQAECgUICQAAAA==.Habant:BAAANQADCgUIDAAAAA==.Halbert:BAAANQADCgYIBQAAAA==.Half:BAAANQADCgUIBwAAAA==.Hallomii:BAAANQADCggIEgAAAA==.Halutal:BAAANQADCgUIBQAAAA==.Hanbolo:BAAANQADCggICQABNQADCggIGQABAAAAAA==.Hapcrappens:BAAANQADCgIIAgAAAA==.Hardluck:BAAANQADCgcIEwAAAA==.Hardyfar:BAAANQADCgYIBgAAAA==.Harshpriest:BAAANQAECgYICwAAAA==.Hasophet:BAAANQAECgMIAwAAAA==.Hauger:BAAANQAECgEIAQAAAA==.Hazardless:BAAANQAECgMIAwAAAA==.',
He='Healmash:BAAANQAECgcIEwAAAA==.Healpimp:BAAANQAECgMIBAAAAA==.Heelsupharis:BAAANQADCgYIBgABNQAECgcIEQABAAAAAA==.Heiarra:BAAANQAECgcIBwABNQAFFAIIAgABAAAAAA==.Heliako:BAAANQADCggICAAAAA==.Herchel:BAAANQADCggICAABNQAECgYICQABAAAAAA==.Herö:BAAANQAECggIEQAAAA==.Heyoka:BAAANQAECgEIAQAAAA==.',
Hi='Hialeah:BAAANQABCgIIBAAAAA==.Hibacchii:BAAANQAECgUICAAAAA==.Hiyes:BAAANQAECgYIDgAAAA==.',
Ho='Hockeyblades:BAAANQADCgYIBgAAAA==.Hodred:BAAANQAECgEIAgAAAA==.Hokori:BAAANQADCgcIBwABNQAECgUICgABAAAAAA==.Hollýwood:BAABNQAECoEZAAMSAAgJLBz2LgBPAgASAAgJLBz2LgBPAgATAAMJ0gTxjQCnAAAAAA==.Holybreath:BAAANQADCgYIBgAAAA==.Holygreyel:BAAANQADCgMIAwABNQADCgQIDAABAAAAAA==.Holykiwi:BAAANQAECgEIAQAAAA==.Holymackerel:BAAANQABCgcIBwAAAA==.Holypreditor:BAAANQADCgUICQAAAA==.Holytbag:BAAANQAECgIIAgAAAA==.Honeonna:BAAANQADCggICgAAAA==.Honeymilktea:BAAANQAECgcIDQAAAA==.Honeýbunny:BAAANQABCgYICAAAAA==.Hopeandlight:BAAANQAECgEIAQAAAA==.Hotspriest:BAAANQADCgYIBgAAAA==.',
Hu='Hugehoofner:BAAANQADCgcIDwAAAA==.Humidor:BAAANQADCgYICgAAAA==.Huminn:BAAANQADCggIGgAAAA==.Hungfoo:BAAANQAECgUICQAAAA==.',
Hy='Hybri:BAAANQADCggICwAAAA==.Hypedd:BAAANQADCgYIBgAAAA==.Hyphie:BAEANQAECgIIAgAAAA==.Hysteri:BAABNQAECoEOAAIHAAcJnBZ1BgDoAQAHAAcJnBZ1BgDoAQAAAA==.',
['Hë']='Hël:BAAANQADCgUIBQABNQAECgcIFQAUAIUUAA==.',
Ia='Iameo:BAAANQAECgQIBAAAAA==.Iamgrubby:BAAANQAECgYICwAAAA==.',
Ic='Iceni:BAAANQADCgMIAwAAAA==.Icianira:BAAANQAECgIIAgAAAA==.Ickis:BAAANQAECgcICAAAAA==.Icyblades:BAAANQAECgMIBAAAAA==.Icénova:BAAANQAECgYIBwAAAA==.',
Id='Idkpriests:BAAANQAECgYIEQAAAA==.',
Ig='Igneifreet:BAAANQADCggIDAAAAA==.',
Il='Illaldraen:BAAANQAECgcIDgAAAA==.Illeyna:BAAANQAECgUIBgAAAA==.Illidamufine:BAAANQAECgcIBwABNQAECgkJGQAVAMwgAA==.',
Im='Imway:BAAANQAECgQIBgAAAA==.',
In='Incredble:BAAANQAECgYICwABNQABCgIIAgABAAAAAA==.Insul:BAABNQAECoEhAAMRAAkJ6SFzBwAaAwARAAkJbR9zBwAaAwADAAQJhx56bQBTAQAAAA==.',
Ir='Irminsul:BAAANQAECggIBgAAAA==.',
Is='Isilador:BAAANQAECgMIAwAAAA==.Isildar:BAAANQABCgIIAgAAAA==.Iskur:BAAANQADCgcIGAAAAA==.',
It='Ithildur:BAAANQADCgYIDQAAAA==.Ithilion:BAAANQADCggIGAAAAA==.',
Ja='Jabanokzul:BAAANQADCgcIDAAAAA==.Jackblackeye:BAAANQADCgUIBQABNQADCggIHwABAAAAAA==.Jadastormer:BAAANQADCgYIBwAAAA==.Jadormus:BAAANQADCgUIBQAAAA==.Jaerii:BAABNQAECoEdAAMRAAkJkh3aDQCrAgARAAkJKxvaDQCrAgADAAIJNCDBoAC4AAAAAA==.Jalox:BAABNQAECoEcAAIDAAgJ5SSUCABKAwADAAgJ5SSUCABKAwAAAA==.Janusquintus:BAAANQAECgMICAAAAA==.Jaqes:BAAANQADCgUIBQAAAA==.Jasaious:BAAANQADCgQIBQAAAA==.',
Je='Jedediah:BAAANQADCgYIFgAAAA==.Jeffagon:BAAANQADCgYIDAAAAA==.Jehtt:BAAANQABCgcIDgAAAA==.Jeofery:BAAANQAECgYIDAAAAA==.Jeofrey:BAAANQADCgUIBQAAAA==.Jerricco:BAAANQADCgUIDQAAAA==.Jersie:BAABNQAECoEYAAMWAAgJiSSRAABfAwAWAAgJdSSRAABfAwAXAAIJ/SKmawDBAAAAAA==.Jeta:BAAANQADCggICAAAAA==.Jetadari:BAAANQAECgMIBQAAAA==.Jetdh:BAAANQAECgMIBQABNQAECgUICgABAAAAAA==.Jetdin:BAAANQAECgUICgAAAA==.Jetlock:BAAANQABCgQIBAABNQAECgUICgABAAAAAA==.Jetribution:BAAANQADCgIIAgAAAA==.Jetsun:BAAANQAECgMIAwABNQAECgMIBQABAAAAAA==.Jettree:BAAANQADCgEIAQABNQAECgMIBQABAAAAAA==.',
Ji='Jibb:BAAANQADCgIIAgAAAA==.Jimzlock:BAAANQADCgUICAAAAA==.Jintara:BAAANQADCgQIBAAAAA==.Jinxie:BAAANQAECgIIAgAAAA==.Jinzak:BAAANQABCgIIAgAAAA==.',
Jo='Joosten:BAABNQAECoEZAAIYAAgJdyULBQBbAwAYAAgJdyULBQBbAwAAAA==.Joradys:BAAANQAECgEIAQAAAA==.Jorick:BAAANQAECgUIDgAAAA==.',
Jr='Jrex:BAAANQADCgcIFAAAAA==.',
Ju='Judge:BAAANQAECgUICAAAAA==.Jugjug:BAABNQAECoEYAAIEAAgJdiJ6CQAfAwAEAAgJdiJ6CQAfAwAAAA==.Julí:BAAANQADCgYIBgAAAA==.Junipers:BAAANQAECgEIAQAAAA==.Jurrie:BAAANQAECgUIBgAAAA==.',
['Jé']='Jétt:BAAANQABCgMIAwAAAA==.',
['Jê']='Jêht:BAAANQABCgYIBgAAAA==.',
['Jî']='Jînxx:BAAANQAECgEIAQAAAA==.',
['Jý']='Jýnxx:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Ka='Kachman:BAAANQABCgQIBAAAAA==.Kaeklek:BAAANQAECgQICQAAAA==.Kageth:BAAANQAECgQIBAAAAA==.Kagorak:BAAANQADCgYIBgAAAA==.Kaidyn:BAAANQAECgUIBgAAAA==.Kaizax:BAABNQAECoEbAAQEAAkJaB9YEQDUAgAEAAgJbB9YEQDUAgAZAAQJoRPPJgAFAQAaAAEJDRHvGgA+AAAAAA==.Kalaiedon:BAAANQADCgcIDwAAAA==.Kalesh:BAAANQADCgcIFgABNQADCggICAABAAAAAA==.Kannagi:BAAANQABCggIDwAAAA==.Kasala:BAAANQAECgQIDwAAAA==.Kassdruid:BAAANQAECgUICQAAAA==.Kasspally:BAAANQADCggIDgAAAA==.Katanyaa:BAAANQAECgMIBAAAAA==.Kathalia:BAAANQAECgUIBgAAAA==.Kazben:BAAANQABCgYIBwAAAA==.',
Ke='Kebechet:BAAANQADCgcIGAAAAA==.Keenlifey:BAAANQADCggIFAAAAA==.Keiiran:BAAANQAECgUIBgAAAA==.Kelesara:BAAANQAECgMIAwAAAA==.Kelsoth:BAAANQAECgQIBAABNQAECggIGQAFAEMcAA==.Kelyssel:BAAANQAECgMIAwAAAA==.Ken:BAAANQAECgUIBQABNQAECggIDQABAAAAAA==.Kendri:BAAANQADCgYIBgAAAA==.Kent:BAAANQAECgYIDgAAAA==.Keri:BAAANQAECgMIBAAAAA==.Kethys:BAAANQAECgEIAQAAAA==.',
Kh='Khione:BAAANQAECgQIBwAAAA==.Khirsah:BAAANQADCggICAAAAA==.',
Ki='Kiläva:BAAANQADCggIGQAAAA==.Kindria:BAAANQAECgUICQAAAA==.Kintaoro:BAAANQAECgUIDAAAAA==.Kinzia:BAAANQAECgYIDQAAAA==.Kioni:BAAANQADCgcIGAAAAA==.Kirkaviv:BAAANQADCgcIDwAAAA==.Kittyboar:BAAANQADCgYIBgAAAA==.Kittywrecker:BAAANQADCgMIAwAAAA==.',
Kl='Kleptik:BAAANQAECgUIDAAAAA==.',
Kn='Knuckleheäd:BAAANQADCggIFAAAAA==.',
Ko='Kolfinned:BAAANQAECgEIAQAAAA==.Koracritus:BAABNQAECoEbAAMbAAkJoCB+AgBFAwAbAAkJoCB+AgBFAwAcAAIJkxp6kACWAAAAAA==.Korakano:BAAANQADCgQIBwABNQAECgkJGwAbAKAgAA==.Korakishi:BAAANQAECgEIAQABNQAECgkJGwAbAKAgAA==.Koraniko:BAAANQAECgIIBAABNQAECgkJGwAbAKAgAA==.Korasana:BAAANQADCgQIBAABNQAECgkJGwAbAKAgAA==.Korasetalon:BAAANQAECgUIBgABNQAECgkJGwAbAKAgAA==.Korvain:BAAANQADCgYIEQAAAA==.Kovalla:BAAANQADCgcICgAAAA==.',
Kr='Krabpeople:BAAANQAECgUICgAAAA==.Krev:BAAANQAECgQICAAAAA==.Kràmpus:BAAANQAECgYIDgAAAA==.',
Ku='Kulash:BAAANQADCgYIDgAAAA==.Kungfubeauty:BAAANQADCggIDAABNQAECgIIAgABAAAAAA==.Kuromi:BAAANQADCgcIGgAAAA==.Kurrox:BAABNQAECoEdAAIdAAkJ0R//BQAYAwAdAAkJ0R//BQAYAwAAAA==.',
Kw='Kwaasoul:BAAANQADCgQIBAAAAA==.',
Ky='Kylight:BAAANQAECgMIBAAAAA==.Kyrnn:BAABNQAECoEXAAIUAAkJiBo+JwD0AgAUAAkJiBo+JwD0AgAAAA==.Kyvend:BAAANQADCgYIBgABNQAECgkJHgAdAAQjAA==.',
['Kí']='Kíngg:BAAANQADCgEIAQAAAA==.',
['Kî']='Kîngg:BAAANQAECgcIEwAAAA==.',
La='La:BAAANQADCgcICAAAAA==.Lagértha:BAAANQADCgUIBgABNQADCgYIDQABAAAAAA==.Lailahh:BAAANQAECgcIDwAAAA==.Lalyaa:BAAANQADCgIIAgAAAA==.Lalyaz:BAAANQAECgUIBgAAAA==.Lamelor:BAAANQADCgIIAgABNQAECgcIAQABAAAAAA==.Landrael:BAAANQAECgUICwAAAA==.Laotzu:BAAANQAECgYICwAAAA==.Lasergun:BAAANQAECgYIDwAAAA==.Lastchanceu:BAAANQAECgEIAQAAAA==.Laval:BAAANQAFFAIIAgABNQAFFAYIDAANALIdAA==.',
Le='Leafstone:BAAANQADCgUICAAAAA==.Lecap:BAAANQAECgIIAQAAAA==.Lecya:BAAANQADCgQIBAAAAA==.Leeroygkins:BAAANQADCggICAAAAA==.Leonsen:BAAANQAECgQIBAABNQAECggIHAAFAKEhAA==.Leprecháun:BAAANQAECgQIBAAAAA==.Levdravia:BAAANQAECgQIBAAAAA==.Lexla:BAAANQADCgEIAQAAAA==.Lexxin:BAAANQADCgUICAAAAA==.',
Li='Liallan:BAAANQADCgcIDgAAAA==.Lightelf:BAAANQAECgYIDQAAAA==.Lightlilith:BAAANQADCgUIBQAAAA==.Ligmamana:BAAANQAECgIIBAAAAA==.Liketopown:BAAANQADCggIGAAAAA==.Lildingus:BAAANQAECgMIBAAAAA==.Lilsaywho:BAAANQADCgQIBAAAAA==.Lilshamhai:BAAANQAECgQIBAAAAA==.Lisperiena:BAAANQABCgIIAgAAAA==.Littlezz:BAAANQAECgMIBQAAAA==.Lizwiz:BAAANQAECgUIBQAAAA==.',
Lo='Locklius:BAAANQAECgQICwAAAA==.Lohnarr:BAAANQADCggIEQAAAA==.Lolhands:BAAANQADCgUICAAAAA==.Loresbane:BAAANQAECgQIBQAAAA==.Lorianne:BAAANQAECgIIAgAAAA==.Lothros:BAAANQAECgYIEgAAAA==.',
Lu='Lucive:BAEANQADCgIIAgABNQAECgMIBAABAAAAAA==.Lurlene:BAAANQADCggIEQAAAA==.',
Ly='Lysanor:BAAANQADCgUICQAAAA==.Lytah:BAAANQADCgUICAAAAA==.',
Lz='Lzt:BAAANQAECggIEwAAAA==.',
['Lá']='Ládyemmá:BAAANQADCgUICgAAAA==.',
['Lí']='Líghtabove:BAAANQADCgcIEgAAAA==.',
['Lö']='Löka:BAAANQAECgcICgAAAA==.',
Ma='Mac:BAABNQAECoEbAAMeAAkJZiWUAAB2AwAeAAgJpyWUAAB2AwANAAYJ9h1RXQC9AQABNQAECgQIBAABAAAAAA==.Mad:BAAANQADCgEIAQABNQAECgEIAgABAAAAAA==.Maddgnome:BAAANQABCgcIDAAAAA==.Maddles:BAAANQADCgMIAwABNQADCggIFAABAAAAAA==.Madratter:BAAANQAECgQIBgAAAA==.Magelius:BAAANQAECgYIDwAAAA==.Mageymage:BAAANQAECgQIBQAAAA==.Maggotfeast:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Magickdoll:BAAANQAECgQIBAAAAA==.Makli:BAAANQAECgYIDAAAAA==.Malakhai:BAAANQAECgMIBAAAAA==.Maledictíon:BAAANQAECgQIBgAAAA==.Maleniia:BAAANQADCgYIBwABNQAECgEIAgABAAAAAA==.Malstrohm:BAAANQADCgUICAAAAA==.Mannynuff:BAAANQAECgQIBQABNQAECggIGgAUAPQZAA==.Margrim:BAAANQADCggIEQAAAA==.Marrowen:BAAANQADCgYIEgAAAA==.Mart:BAAANQAECgYICgAAAA==.Martymcfry:BAAANQADCgUICQAAAA==.Maulfang:BAAANQADCgYIBgAAAA==.Mausi:BAAANQAECgQIBgAAAA==.Mavdormu:BAAANQADCgcIBwABNQAECgkJJAAMAIshAA==.Maviah:BAAANQAECgYICQAAAA==.Maxious:BAAANQADCgcIDAAAAA==.Maxpàin:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Mays:BAABNQAECoEXAAIDAAcJayRwEwDbAgADAAcJayRwEwDbAgAAAA==.Mazer:BAAANQAECgUIDQAAAA==.',
Me='Meachmelou:BAAANQAECgYIDAAAAA==.Mechamonk:BAAANQAECgcICgAAAA==.Medco:BAAANQADCggIDwAAAA==.Medestruìt:BAAANQAECgcICwAAAA==.Meinna:BAAANQADCgMIBAAAAA==.Meleehunter:BAAANQAECgcIEQAAAA==.Melissandreh:BAAANQADCgYIBgAAAA==.Melonmilktea:BAAANQAECgMIAwABNQAECgcIDQABAAAAAA==.Merder:BAAANQADCgYIBwAAAA==.Mes:BAAANQAFFAIIBAAAAA==.Mewtwo:BAAANQAECgUICgABNQAFFAUICAAQAB0iAA==.',
Mi='Minanto:BAAANQABCgYIBgAAAA==.Mishift:BAAANQAECgQIBAAAAA==.Misttia:BAAANQAECgUIEgABNQAFFAUIDAATAKAdAA==.Mistweave:BAABNQAECoEZAAIfAAgJUB2WBwCaAgAfAAgJUB2WBwCaAgAAAA==.Mithrid:BAAANQADCgYICgABNQAECgUICwABAAAAAA==.',
Mn='Mnemosyne:BAAANQADCgUICgAAAA==.',
Mo='Mochamilktea:BAAANQABCgQIBQABNQAECgcIDQABAAAAAA==.Moff:BAAANQAECgYIBwAAAA==.Monksz:BAAANQABCgEIAQAAAA==.Moonkissdoll:BAAANQADCgUIDAAAAA==.Mordithaas:BAAANQAECgMIBgABNQABCgYICgABAAAAAA==.Moriarty:BAAANQAECgYICQAAAA==.Morved:BAABNQAECoEZAAMFAAgJQxwQFgCZAgAFAAgJLBwQFgCZAgAgAAcJrg5UMwCTAQAAAA==.Mowbray:BAAANQADCgcIDQAAAA==.',
Mt='Mtnmanbalgor:BAAANQABCggIDQAAAA==.',
Mu='Mulum:BAAANQADCgUICAAAAA==.Mungrurakrof:BAAANQADCggIEAAAAA==.Mussyx:BAAANQAECgEIAQAAAA==.',
My='Myanmar:BAAANQADCgUICAAAAA==.Myria:BAAANQADCggIFAAAAA==.Mythralit:BAAANQAECgUICwAAAA==.',
['Mä']='Mäelorn:BAAANQAECgEIAgAAAA==.',
['Mé']='Méhth:BAAANQADCgEIAQAAAA==.',
['Më']='Mëdüsä:BAAANQABCgYIDAAAAA==.',
['Mú']='Múlder:BAAANQADCgUIBQAAAA==.',
Na='Naandra:BAAANQADCgcIDQAAAA==.Naidris:BAAANQADCgEIAQABNQAECgYIDwABAAAAAA==.Naiel:BAAANQADCgcIBwABNQAECgYIDwABAAAAAA==.Namanda:BAAANQADCgcIBwAAAA==.Naraeth:BAAANQAECgcIEgAAAA==.Narroc:BAAANQADCgcIEQAAAA==.Narsyssa:BAAANQADCgUIBwAAAA==.',
Ne='Neltharionjr:BAAANQADCggICAAAAA==.Neplyin:BAAANQADCggICAAAAA==.Neptaluna:BAAANQAECgEIAQAAAA==.Neryssa:BAAANQAECggICgAAAA==.Nessfalco:BAABNQAECoEaAAMRAAcJQhDFHgCtAQARAAcJlg/FHgCtAQADAAMJ6QvtnADIAAAAAA==.',
Ni='Niewazny:BAAANQAECgIIBAAAAA==.Nikolos:BAAANQAECgYIDAAAAA==.Nimbielle:BAABNQAECoEiAAIbAAkJLBwwAwAmAwAbAAkJLBwwAwAmAwAAAA==.Niraffe:BAAANQABCgIIAgAAAA==.Nisara:BAAANQAECgUIDAAAAA==.Nispyshroud:BAAANQADCgMIAwAAAA==.Nixsons:BAAANQAECgUICAAAAA==.',
Nn='Nntaiga:BAAANQADCgEIAQAAAA==.',
No='Noctilucent:BAAANQAECgcIEgAAAA==.Nokey:BAAANQAECgEIAQAAAA==.Nommnomz:BAABNQAECoEpAAIIAAkJzCXTAADdAwAIAAkJzCXTAADdAwAAAA==.Nomns:BAAANQAECgQIBAAAAA==.Nomz:BAAANQAECggICgABNQAECgkJKQAIAMwlAA==.Noobh:BAAANQADCggIHwAAAA==.Nornogh:BAAANQAECgcIAQAAAA==.Notahealer:BAAANQAECgMIBAAAAA==.Nototemforu:BAAANQABCgIIAgAAAA==.Notshteve:BAAANQAECgUICgAAAA==.Notwulfdaria:BAAANQAECgUICwAAAA==.Novogelo:BAAANQADCgYICQAAAA==.',
Nr='Nrrology:BAAANQADCgUIBwAAAA==.',
Nu='Nuclearwintr:BAAANQAECgQICAAAAA==.Nurology:BAAANQADCgIIBAAAAA==.Nurs:BAAANQADCgYIBgAAAA==.Nuttlovin:BAAANQAECgUIBQAAAA==.Nuwang:BAAANQAECgQIBQAAAA==.',
Ny='Nychar:BAAANQAECgcIDwAAAA==.Nymira:BAAANQADCgUIBQAAAA==.',
Og='Ogadall:BAAANQADCggIDgAAAA==.',
Ok='Okasan:BAAANQAECgEIAQAAAA==.Okokok:BAAANQADCgIIAgAAAA==.Okwahokowa:BAAANQAECgQIBQAAAA==.',
Ol='Oldredbeard:BAAANQADCggIEQAAAA==.',
On='Ongaker:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Onyxstrasza:BAAANQADCgIIAgAAAA==.',
Oo='Oobubble:BAAANQAECgUICgAAAA==.',
Op='Opira:BAAANQADCgQIBAAAAA==.',
Or='Orcfrin:BAAANQAECgYICwAAAA==.Oryan:BAAANQADCgYICgAAAA==.',
Os='Osherio:BAAANQAECgQIBAAAAA==.',
Ow='Owlain:BAAANQADCgUICQAAAA==.',
Oz='Oztilla:BAAANQABCgQIBAAAAA==.',
Pa='Padahwon:BAAANQADCgUIBQABNQAECggIEgABAAAAAA==.Palermo:BAAANQAECgYIBwAAAA==.Pandemica:BAAANQAECgIIBAAAAA==.Pandermoneum:BAAANQAECgQIBAAAAA==.Panzadius:BAAANQAECgUIBQAAAA==.Papper:BAAANQAECgUIBQABNQAECgYIBwABAAAAAA==.Pappgrock:BAAANQADCgcIEAABNQAECgYIBwABAAAAAA==.Pappidan:BAAANQAECgYIBwAAAA==.Pappmist:BAAANQADCggICQAAAA==.Pastorpapp:BAAANQADCgIIAgAAAA==.',
Pe='Peaceadin:BAAANQAFFAIIAgAAAA==.Pegrhan:BAAANQAECgEIAQAAAA==.Pentakills:BAAANQAECgQIBQAAAA==.Pentalock:BAAANQADCgMIAwAAAA==.Petmastah:BAAANQAECgIIAgAAAA==.',
Ph='Phazius:BAABNQAECoEZAAMSAAgJCBtkMwA3AgASAAgJCBtkMwA3AgAhAAcJjBI1EQC1AQAAAA==.Phoebespell:BAAANQADCggIDwAAAA==.Physicalbuff:BAAANQAECgcIEQAAAA==.',
Pj='Pjsreturn:BAAANQAECgEIAQAAAA==.',
Pl='Plaguewîtch:BAAANQAECgYICwAAAA==.',
Pn='Pnashty:BAAANQAECgQIBAAAAA==.',
Po='Polarized:BAAANQAECgIIAgAAAA==.Pookîe:BAAANQADCgUIBQAAAA==.Poppajeffery:BAAANQADCgYICgAAAA==.Porqué:BAAANQAECgIIAwABNQAECgIIBAABAAAAAA==.Porquédtf:BAAANQAECgIIBAAAAA==.Postgres:BAAANQADCgUIAgAAAA==.Powbang:BAAANQADCgYIDgAAAA==.',
Pr='Prema:BAAANQADCgIIAgAAAA==.Priesttia:BAAANQAECgUIBQABNQAFFAUIDAATAKAdAA==.Prominenced:BAAANQADCgQIBgAAAA==.Prototype:BAAANQAECgEIAQAAAA==.Proxol:BAACNQAFFIEKAAQZAAUJJBrVAAAfAQAZAAMJphnVAAAfAQAEAAMJgyE4BQAeAQAaAAEJ8gDhBgAzAAA1AAQKgSMABBkACQk+JlIAANEDABkACQkEJlIAANEDAAQACAnrJcMDAHEDABoAAwk8GXQLAN8AAAAA.Príapus:BAAANQABCgcICgAAAA==.',
Pu='Puckyhuddle:BAAANQAECgIIAgAAAA==.Puun:BAAANQABCgMIAwABNQADCggIGQABAAAAAA==.',
['Pè']='Pènny:BAAANQAECgIIAgAAAA==.',
Qa='Qavax:BAAANQAECgQIBAABNQAECgkJIQAEAEcjAA==.',
Qu='Questchaser:BAAANQADCggIHAAAAA==.Quetzie:BAABNQAECoEgAAIiAAkJrRzoDQAJAwAiAAkJrRzoDQAJAwAAAA==.Quikclot:BAAANQAECgQIBAAAAA==.',
Ra='Raethia:BAAANQAECgYIDgAAAA==.Rafikiblade:BAECNQAFFIEIAAMYAAUJBRjMAgBpAQAYAAQJfxbMAgBpAQAQAAIJnBfjAACmAAA1AAQKgSkAAxgACQlgJCcBANYDABgACQlgJCcBANYDAAgACQlBIJkLAOACAAAA.Rafikizilla:BAEANQADCgEIAQABNQAFFAUICAAYAAUYAA==.Raging:BAAANQAECgIIAgAAAA==.Ragnuis:BAAANQAECgYIDAAAAA==.Ragrim:BAAANQAECgEIAQAAAA==.Ragñàr:BAAANQADCgYICAAAAA==.Raita:BAAANQADCgIIAwAAAA==.Rakar:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Randyman:BAAANQABCgIIAgAAAA==.Ranstartwo:BAAANQADCgQIBAAAAA==.Raveenchi:BAAANQADCgQIBAAAAA==.Ravenwulf:BAAANQADCgYIBgAAAA==.Raynacon:BAAANQADCgUIBQAAAA==.Raythe:BAAANQAECgMIBAAAAA==.Rayøn:BAAANQADCgcIBwAAAA==.Razelgul:BAAANQADCgcIGAAAAA==.Razfoo:BAAANQAECgUICAAAAA==.',
Re='React:BAAANQADCggICAAAAA==.Reaperr:BAAANQAECgUICQAAAA==.Recon:BAAANQADCgYIEwAAAA==.Recovery:BAAANQAECgQICAAAAA==.Redding:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.Reedicculus:BAAANQADCggICAAAAA==.Reegar:BAAANQADCgYICgAAAA==.Rekktless:BAAANQAECgQICAAAAA==.Repairs:BAAANQAECgMIBQAAAA==.Resteauxrer:BAAANQAECgUIBQAAAA==.Retoric:BAAANQAECgcIDQAAAA==.Reverïe:BAAANQAECgQICAAAAA==.Revvy:BAAANQAECgQIBgAAAA==.Reyalz:BAAANQAECgUICQAAAA==.Reyalzto:BAAANQAECgIIAgABNQAECgUICQABAAAAAA==.',
Rh='Rhaenera:BAAANQADCgMIAwAAAA==.Rhakú:BAAANQAECgQIBAAAAA==.',
Ri='Ribblet:BAAANQAECgYIDwAAAA==.Ricardö:BAAANQAECgcIDgAAAA==.Rickylafleur:BAAANQAECgMIAwAAAA==.Righteousron:BAAANQADCggIDgAAAA==.Riniion:BAAANQADCggIFwAAAA==.Riune:BAAANQAECgYIDAAAAA==.Rizpally:BAAANQADCgEIAQABNQAECgQICAABAAAAAA==.',
Ro='Robob:BAAANQAECgYIDAAAAA==.Rocktotems:BAAANQAECgEIAQAAAA==.Roduric:BAAANQABCgUIBQAAAA==.Ronaldreagan:BAAANQAECgYIDwAAAA==.Roshan:BAAANQADCgQIBAAAAA==.Roshel:BAAANQAECgMIBAAAAA==.Roxer:BAAANQAECgEIAQAAAA==.Royboy:BAAANQAFFAEIAgABNQAFFAQIBgASAJ0TAA==.',
Ru='Rubilâx:BAAANQADCgUICQAAAA==.Rumira:BAAANQAECgUICQAAAA==.Runklè:BAAANQADCgcIFQAAAA==.Rusticles:BAAANQADCgcICQAAAA==.',
Ry='Rychuspower:BAAANQADCggICAAAAA==.Rynnaa:BAAANQAECgIIAgAAAA==.',
['Rå']='Rågnår:BAAANQAECgQIBAAAAA==.Råyna:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
['Rü']='Rück:BAAANQAECgIIBAAAAA==.',
Sa='Saianne:BAAANQAECgIIAgAAAA==.Salli:BAAANQADCgYICgAAAA==.Samwysgankye:BAAANQADCggIGQAAAA==.Sanaim:BAAANQAECgIIAQABNQAECgIIAgABAAAAAA==.Sandsel:BAAANQAECgIIBAAAAA==.Sandsnakexx:BAAANQAECgQIBQAAAA==.Sangre:BAAANQADCgIIAgAAAA==.Saniita:BAAANQAECgEIAQAAAA==.Saosen:BAEANQAECgMIBAAAAA==.Sardaukaur:BAAANQAECgMIBAAAAA==.Sasslysnipes:BAAANQADCgcIFQABNQAECgIIAgABAAAAAA==.Sausagepants:BAABNQAECoEWAAIcAAkJcRhOHQCHAgAcAAkJcRhOHQCHAgAAAA==.Saydee:BAAANQADCggIDAAAAA==.',
Sc='Scabbers:BAAANQAECgMIBAAAAA==.Scarybeard:BAAANQAECgQIBgABNQAECgcIEAABAAAAAA==.Scathach:BAAANQAECgQIBgAAAA==.Schützë:BAAANQAECgQICwAAAA==.Scramboozled:BAAANQADCgEIAgAAAA==.Scriabin:BAAANQAECgIIAgAAAA==.Scúlly:BAAANQADCgUICAAAAA==.',
Se='Sebastum:BAAANQAECgIIAgAAAA==.Secondcup:BAAANQADCggIDAABNQAECgYIEQABAAAAAA==.Seeunt:BAAANQADCgEIAQAAAA==.Senleon:BAAANQADCgcIBwABNQAECggIHAAFAKEhAA==.Senn:BAABNQAECoEcAAMFAAgJoSFNEgDAAgAFAAgJnx9NEgDAAgAjAAMJHBkUNADHAAAAAA==.Sentino:BAAANQAECgEIAQAAAA==.Seribii:BAAANQAECgIIBAAAAA==.Serinar:BAAANQABCgIIAgAAAA==.Seris:BAABNQAECoEVAAIUAAcJhRTqdgDjAQAUAAcJhRTqdgDjAQAAAA==.Seritas:BAAANQABCgYIBgAAAA==.Seronas:BAAANQAECgMIBAAAAA==.',
Sh='Shadaz:BAAANQADCgQIBAABNQAECgEIAwABAAAAAA==.Shadewitch:BAAANQADCgQIBAAAAA==.Shadezar:BAAANQADCgUICAAAAA==.Shadowtivv:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Shainbas:BAAANQADCgUIBwABNQADCgcIHwABAAAAAA==.Shalashara:BAAANQADCgYIBgAAAA==.Shamazed:BAAANQAECgMIAwAAAA==.Shamjouk:BAAANQADCggIGgAAAA==.Shampion:BAAANQAECgcIDgAAAA==.Shamraz:BAAANQAECgIIAgAAAA==.Shamw:BAAANQAECgUIDQAAAA==.Shamyog:BAAANQADCgcIBwAAAA==.Shandren:BAAANQADCgcIHwAAAA==.Shanfo:BAAANQAECgMIAwAAAA==.Shansee:BAAANQADCgUICQAAAA==.Sharalandaa:BAAANQADCgcIFwAAAA==.Sharmayne:BAAANQADCgcIFQAAAA==.Sheepster:BAAANQADCggICAAAAA==.Sheildsmack:BAAANQADCgYIBwAAAA==.Shekar:BAAANQADCggICAABNQAECgcIEwABAAAAAA==.Shekhar:BAAANQAECgcIEwAAAA==.Shenanagain:BAAANQAECgQIBAAAAA==.Sherox:BAAANQADCggIFgAAAA==.Shhigotyou:BAAANQAECgQICQAAAA==.Shiitake:BAAANQABCgQIBAAAAA==.Shikke:BAAANQADCggIDgABNQAECgMIBAABAAAAAA==.Shokanshi:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Shollen:BAAANQAECgMIAwAAAA==.Shoshana:BAAANQADCggIDQAAAA==.Shredcruz:BAAANQAECgMIAwAAAA==.Shurelock:BAAANQAECgMIAwAAAA==.',
Si='Sicker:BAAANQAECgYIDgAAAA==.Sideral:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.Siegerbear:BAAANQAECgUICQAAAA==.Sielas:BAAANQADCgUICAAAAA==.Sietelle:BAAANQAECgQICwAAAA==.Silence:BAAANQADCggIFwAAAA==.Silentele:BAAANQADCgMIAwAAAA==.Silvaeri:BAAANQAECgIIAgAAAA==.Silvaga:BAAANQAECgMIAwAAAA==.Silvermight:BAAANQAECgEIAgAAAA==.Silversage:BAAANQADCgIIAgAAAA==.Sipnwhiskey:BAAANQAECgEIAQAAAA==.',
Sk='Skendeer:BAAANQADCgQICQAAAA==.Sketchsmash:BAAANQADCggICQABNQAECgkJGwAPAPIgAA==.Skiddoo:BAAANQAECgUICwAAAA==.Skylerx:BAAANQADCgIIAgAAAA==.Skyträm:BAAANQABCgIIAgAAAA==.',
Sl='Slavonk:BAEANQADCggICAABNQAECgkJHQAMADkgAA==.',
Sm='Smashburgr:BAAANQADCgYIBgAAAA==.Smaugerz:BAAANQAECgIIBQABNQAECgcIGgARAEIQAA==.Smells:BAAANQAECgQIBgAAAA==.Smolmage:BAAANQADCggIFQAAAA==.',
Sn='Snakecharms:BAABNQAECoEXAAIcAAgJqhRfKAA2AgAcAAgJqhRfKAA2AgAAAA==.',
So='Soapya:BAAANQADCgcIDwAAAA==.Soredish:BAAANQADCggICAABNQAFFAYIDAANALIdAA==.',
Sp='Spacedemons:BAAANQAECgMIBAAAAA==.Sparkledin:BAAANQADCgcIEgAAAA==.Sparklehands:BAAANQAECgEIAQAAAA==.Speaknoevil:BAAANQABCgIIAgAAAA==.Spffifty:BAAANQAECgQICgAAAA==.Spinåltap:BAAANQADCgcIFgAAAA==.Spitorgage:BAAANQADCgYICAAAAA==.Splitzor:BAAANQADCggICAAAAA==.Splut:BAAANQADCggIEQAAAA==.Splìtz:BAAANQAECgYICgAAAA==.Spoingus:BAAANQADCggICgAAAA==.Spopovich:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Sq='Squishy:BAACNQAFFIEGAAMYAAQJQhEHAwBaAQAYAAQJNRAHAwBaAQAIAAIJzA7lBwCfAAA1AAQKgSEAAwgACQn4I+8FAE4DAAgACQlNIu8FAE4DABgACAkbIpMHACADAAAA.',
Sr='Srahan:BAAANQAECgIIAgAAAA==.',
St='Starfirë:BAAANQAECgIIAQAAAA==.Stepmomboar:BAAANQAECgUICAAAAA==.Stevenzeagal:BAAANQAECgcIEAAAAA==.Stillup:BAAANQABCgQIBAAAAA==.Stoke:BAAANQAECgIIBAAAAA==.Stormlyn:BAAANQADCgYIDwAAAA==.Stormtank:BAAANQAECgcIEgAAAA==.Stormtitan:BAAANQAECgMIAwAAAA==.Strahan:BAAANQADCgYICAAAAA==.Stuffed:BAAANQAECgUICQABNQAECgYICQABAAAAAA==.Stugats:BAAANQADCgMIAwAAAA==.',
Su='Sugarglider:BAAANQAECgEIAQAAAA==.Sunshìne:BAAANQADCgcIEQAAAA==.Superstars:BAAANQADCggIFAAAAA==.Surelocke:BAAANQADCgQIBAAAAA==.',
Sw='Swingadin:BAAANQAECgMIAwAAAA==.Swisscheese:BAAANQAECgQIBAAAAA==.Swizzleuwu:BAAANQADCggIFwABNQAECgkJIwAiANUeAA==.Swizzlexd:BAABNQAECoEjAAIiAAkJ1R4GDAAiAwAiAAkJ1R4GDAAiAwAAAA==.Swordiesbig:BAAANQAECgIIAgAAAA==.Swordish:BAACNQAFFIEMAAMNAAYJsh1UAgANAgANAAUJjyNUAgANAgAeAAEJYACtAQBPAAA1AAQKgSEAAg0ACQnUJpsAAAAEAA0ACQnUJpsAAAAEAAAA.',
Sy='Sylartos:BAAANQAECgMIAwAAAA==.Syndicate:BAAANQABCgYICgAAAA==.Syndra:BAAANQADCggIGAAAAA==.Syraine:BAABNQAECoESAAIUAAkJjx+sKgDmAgAUAAkJjx+sKgDmAgAAAA==.Sythion:BAAANQADCgYIBgAAAA==.',
['Së']='Sëvën:BAAANQADCgcIGAAAAQ==.',
Ta='Takamurasaki:BAAANQADCgcIGQAAAA==.Talaspire:BAAANQAECgQICQAAAA==.Talby:BAAANQAECgIIAgAAAA==.Talovar:BAABNQAECoEYAAIUAAkJOhcjMwDFAgAUAAkJOhcjMwDFAgAAAA==.Tandori:BAAANQADCggIGQAAAA==.Taromilktea:BAAANQAECgMIBAABNQAECgcIDQABAAAAAA==.',
Tb='Tbgdemon:BAAANQADCggICAAAAA==.',
Te='Teletubbies:BAAANQADCgYICAAAAA==.Tenley:BAAANQADCgUICAAAAA==.Tetauri:BAAANQADCggIFgAAAA==.',
Th='Thehedgehog:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Theklaa:BAAANQAECgMIBgAAAA==.Theory:BAAANQAECgMIBAAAAA==.Therpent:BAABNQAECoEXAAQJAAkJ/BvwBQDfAgAJAAkJWhvwBQDfAgAKAAIJgwV0LABrAAAkAAEJ4hi5EQBMAAAAAA==.Thufeer:BAAANQADCgYIEAAAAA==.',
Ti='Tibber:BAAANQADCgcIDgAAAA==.Tiiv:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Timpuffle:BAAANQAECgIIBAAAAA==.Tinybully:BAAANQADCgQIBgAAAA==.Tinymortis:BAAANQAECgMIAwAAAA==.Tivvdk:BAAANQAECgIIAgAAAA==.Tivvie:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Tizzee:BAAANQADCggIEgABNQAECgkJHQAOAOsfAA==.',
Tj='Tj:BAAANQADCgEIAQAAAA==.',
To='Ton:BAAANQADCgYIBgAAAA==.Totembased:BAAANQAECgEIAQAAAA==.',
Tr='Trapdor:BAAANQAECgQICQAAAA==.Trapthis:BAAANQABCgIIAgAAAA==.Trebaxi:BAAANQADCgUIBwAAAA==.Trianua:BAAANQAECgQIBAAAAA==.Trindisil:BAAANQAECgYICAAAAA==.Tristein:BAAANQADCgEIAQAAAA==.Trobee:BAAANQAECgQICwAAAA==.Troki:BAAANQAECgUICQAAAA==.',
Tu='Tuesday:BAAANQAECgEIAgAAAA==.Tuso:BAAANQADCggICAABNQAECgkJIAAOAJwhAA==.Tuugolk:BAAANQAECgMIAwAAAA==.',
Tw='Twillem:BAAANQAECgUIBQAAAA==.',
Ty='Tyrfenris:BAAANQAECgQIBQAAAA==.Tyrillian:BAAANQAECgcIAgAAAA==.Tyyche:BAAANQADCgUICQAAAA==.',
['Tô']='Tôph:BAAANQADCgcIDwABNQAECgQIBAABAAAAAA==.',
Ul='Uleyah:BAAANQADCgYIFgAAAA==.Ullrfenris:BAAANQADCgcIDQAAAA==.',
Um='Umlautpunkte:BAAANQAECgQIBwAAAA==.',
Un='Unemployment:BAAANQAECgYICgAAAA==.Unexpectedly:BAAANQAECgMIBQAAAA==.Unkindness:BAAANQAECgIIAgAAAA==.',
Va='Vaayu:BAAANQAECgYICgAAAA==.Valics:BAAANQAECgYIDAAAAA==.Valko:BAAANQABCgQIBAAAAA==.Valkovae:BAAANQADCgUIBQAAAA==.Vallenhal:BAAANQADCgUIBgAAAA==.Vallynn:BAAANQADCgcIFAAAAA==.Valrasha:BAAANQAECggIAQAAAA==.Valtheris:BAAANQAECgQICQAAAA==.Valtorrana:BAAANQADCgYIBgAAAA==.Valyndra:BAAANQAECgUICQAAAA==.Vandrix:BAAANQAECgUICwAAAA==.Vanish:BAABNQAECoEdAAMGAAkJBiLAAwBBAwAGAAkJBiLAAwBBAwAHAAgJ9xADBgD8AQAAAA==.Vanyiel:BAAANQAECgcIEgAAAA==.Vapeauxr:BAAANQAECgYIDAAAAA==.Vardric:BAAANQAECgYIDgAAAA==.Variwaz:BAAANQADCggIFQAAAA==.Varkyrion:BAABNQAECoEZAAMEAAgJuSOJEgDLAgAEAAcJuSOJEgDLAgAZAAQJzhiJIgAkAQAAAA==.Varunn:BAAANQAECgIIAgAAAA==.Vashanathel:BAAANQADCggICAABNQAECgQICAABAAAAAA==.',
Ve='Ved:BAAANQADCgcIBwAAAA==.Vedalla:BAAANQAECgQIBAAAAA==.Vederia:BAAANQADCggIGQAAAA==.Velgris:BAAANQAECgEIAQAAAA==.Velitha:BAAANQAECgQICQAAAA==.Velkhie:BAAANQADCgUIBQABNQAECgkJIgAbACwcAA==.Velkyr:BAAANQAECgQIBAAAAA==.Velonnia:BAAANQAECgQIBgAAAA==.Velvana:BAAANQADCgYICwABNQAECgcIEgABAAAAAA==.Venant:BAAANQADCggIDAAAAA==.Verdigo:BAAANQAECgIIAgAAAA==.Versatilus:BAAANQAECgQIBAAAAA==.',
Vi='Victim:BAAANQAECgIIAgAAAA==.Viive:BAAANQADCgUIBQAAAA==.Viste:BAAANQAECgcIDwAAAA==.Visz:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.Vixenheart:BAAANQADCgcIFwAAAA==.',
Vo='Vodry:BAAANQADCggIEAAAAA==.Voldelig:BAAANQADCgYICwAAAA==.Voljon:BAAANQADCggIEQAAAA==.Vonryker:BAAANQAECgUIBQAAAA==.Voodeux:BAAANQADCgYIDwAAAA==.',
Vu='Vulkange:BAAANQAECgQICAAAAA==.',
['Vö']='Vöss:BAAANQAECgMIAwAAAA==.',
Wa='Wadetostealt:BAAANQADCgQIBAAAAA==.Wakiyancante:BAAANQADCgcIFQAAAA==.Wangsuckwu:BAAANQADCgcIBwAAAA==.Warao:BAAANQADCgEIAQAAAA==.Warlockketo:BAAANQAECgUICQAAAA==.Warnessy:BAAANQAECgYIDgAAAA==.',
We='Welluck:BAAANQAECgEIAQAAAA==.',
Wh='Whellerpal:BAAANQAECgUICQAAAA==.Whíteglint:BAAANQADCgUIBQAAAA==.',
Wi='Wind:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Windela:BAAANQADCgYICAAAAA==.Wiz:BAABNQAECoEdAAIOAAkJ6x8LBgBCAwAOAAkJ6x8LBgBCAwAAAA==.',
Wo='Wolfcloak:BAAANQAECgIIAgAAAA==.Woodhull:BAAANQADCgUIEAAAAA==.Worsthealer:BAAANQAECgEIAQAAAA==.Worstheals:BAAANQAECgQIBAAAAA==.',
Wr='Wratic:BAAANQAECgYIDwAAAA==.Wruthless:BAAANQADCgUIDAAAAA==.',
Wu='Wulfbite:BAAANQAECgUICwAAAA==.Wulfdaria:BAAANQAECgUIBgABNQAECgUICwABAAAAAA==.Wumpler:BAAANQAECgUIDQAAAA==.',
Xa='Xalinthe:BAAANQADCgYICQAAAA==.Xanson:BAAANQADCgQIBAAAAA==.Xarton:BAAANQAECgUIBgAAAA==.',
Xe='Xendier:BAAANQADCgYIFgAAAA==.',
Xz='Xzxs:BAAANQAECgEIAQAAAA==.Xzyla:BAAANQADCgcIBwAAAA==.',
['Xå']='Xåphan:BAAANQAECgQICwAAAA==.',
Ya='Yaegedgelord:BAAANQAECggIDwABNQAECggIEAABAAAAAA==.Yaegg:BAAANQAECggIEAAAAA==.',
Ye='Yeska:BAAANQAECggIBgAAAA==.',
Yi='Yifferrina:BAAANQAECgEIAQAAAA==.Yingi:BAAANQABCgcICwAAAA==.',
Yo='Yourbud:BAAANQADCgYIFQABNQAECgEIAQABAAAAAA==.Yourdady:BAAANQADCgEIAQAAAA==.',
Yu='Yunå:BAAANQAECgIIAgABNQAECgcIFQAUAIUUAA==.',
['Yá']='Yági:BAAANQADCgcIEgAAAA==.',
Za='Zachiarias:BAAANQAECgQICQAAAA==.Zachthyr:BAAANQAECgMIBAAAAA==.Zalaarrenz:BAAANQABCgQIBAAAAA==.Zalbag:BAAANQAECgUIBgAAAA==.Zalosk:BAAANQADCggICAAAAA==.Zalyssavara:BAAANQADCggICAAAAA==.Zappetto:BAAANQAECgQICAAAAA==.Zaroneus:BAAANQAECgQIBgAAAA==.Zarthass:BAAANQADCgYIDwAAAA==.Zarys:BAAANQAECgUICwAAAA==.Zastin:BAAANQADCgMIAwAAAA==.',
Ze='Zedekia:BAAANQABCgQIAgAAAA==.Zelythria:BAAANQAECgMIAwAAAA==.Zenya:BAAANQADCgMIAwAAAA==.',
Zi='Ziguzagu:BAAANQADCgcIFwAAAA==.Zion:BAAANQAECgYIDAABNQAECgcIDQABAAAAAA==.',
Zo='Zocalo:BAAANQADCggIEQAAAA==.Zodwa:BAAANQAECgEIAQAAAA==.',
Zu='Zuglord:BAAANQADCggIGgAAAA==.Zuldrat:BAAANQADCgcIDQAAAA==.',
Zy='Zynnz:BAAANQAECgIIAgAAAA==.',
['Zâ']='Zân:BAAANQAECgUIBQAAAA==.',
['Âr']='Ârcher:BAAANQAECgEIAQAAAA==.',
['Äl']='Älda:BAACNQAFFIEMAAMDAAUJxBuXAQCLAQADAAQJShqXAQCLAQARAAQJLRVLBQBFAQA1AAQKgRgAAxEACQkKIKkSAFwCABEACQnfH6kSAFwCAAMABQlPGIxmAGgBAAAA.',
['Är']='Ärturia:BAAANQADCgMIAwAAAA==.',
['Æo']='Æonflüx:BAAANQAECgQICgAAAA==.',
['Çr']='Çrovax:BAAANQADCgcIFQAAAA==.',
['Ép']='Épia:BAAANQAECgMIBQAAAA==.',
['Íc']='Ícaros:BAAANQAECgEIAgAAAA==.',
['Úñ']='Úñkñðwñèrrðr:BAAANQADCgEIAQAAAA==.',
['ßu']='ßullseye:BAAANQABCgYICAAAAA==.',
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
