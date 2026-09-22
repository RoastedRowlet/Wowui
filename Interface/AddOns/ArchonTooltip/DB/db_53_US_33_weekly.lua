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

local lookup = {'Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Unknown-Unknown','Evoker-Devastation','DeathKnight-Blood','Warlock-Demonology','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Balance','Druid-Restoration','Hunter-Marksmanship','Warrior-Arms','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Hunter-BeastMastery','Mage-Arcane','Warlock-Destruction','Evoker-Preservation','Mage-Frost','Shaman-Enhancement','Priest-Discipline','Warrior-Protection','Priest-Shadow','Hunter-Survival','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Monk-Windwalker','Druid-Guardian',}
local provider = {region='US',realm='Blackrock',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Absolve:BAABNQAECoEcAAIBAAkKHyEhCABbAwABAAkKHyEhCABbAwAAAA==.',
Ad='Adamantium:BAAANQADCgQIBAABNQAFFAMIBgACABUhAA==.Adamantorc:BAACNQAFFIEGAAICAAMKFSEXCAApAQACAAMKFSEXCAApAQA1AAQKgSkAAwIACQq7JOcCAKMDAAIACQq7JOcCAKMDAAMAAQrvA/jfADEAAAAA.Adampal:BAAANQAECgIIAgABNQAFFAMIBgACABUhAA==.Adlez:BAAANQAECgUJBQAAAA==.Adowarlord:BAAANQADCgYJBwAAAA==.',
Ae='Aethylas:BAAANQAECgQJBQAAAA==.',
Af='Afsdruid:BAAANQADCgUJBQAAAA==.',
Ai='Aizzen:BAABNQAECoEbAAIEAAgKTxQXCwDqAQAEAAgKTxQXCwDqAQAAAA==.',
Ak='Akadeyjr:BAAANQADCggJEwAAAA==.Akaeus:BAAANQAECgQIBgAAAA==.Akhouel:BAAANQADCgQIBAAAAA==.',
Al='Albatross:BAAANQAECgQJBgAAAA==.Alfalfaflow:BAAANQADCggIFQAAAA==.Alienfreakdt:BAAANQAECgcIEQAAAA==.Alizalynn:BAAANQADCggICAAAAA==.Allaon:BAAANQAECgcJDwAAAA==.Allerianna:BAAANQADCgIIAgAAAA==.Alyriel:BAAANQADCggIDQAAAA==.Alysun:BAAANQAECgUIDgAAAA==.Alysyn:BAAANQAECgUJBwABNQAECgUIDgAFAAAAAA==.Alyys:BAAANQABCgIJAgABNQAECgUIDgAFAAAAAA==.Alèxander:BAAANQAECgMIBAAAAA==.',
Am='Amado:BAAANQADCgEIAQAAAA==.Amathel:BAAANQAECgYIDQAAAA==.Amynda:BAAANQADCgQIBAAAAA==.',
An='Angelsfìst:BAAANQAECgUICwAAAA==.Annexin:BAAANQAECgUIBQABNQAECgcIDgAFAAAAAA==.',
Ap='Apocalyptic:BAAANQADCgEJAQAAAA==.',
Ar='Arawein:BAAANQAECgEIAQAAAA==.Aremis:BAAANQAECgYIEgABNQAECgkJHQAGAMEbAA==.Argonius:BAAANQADCgUIBQAAAA==.Arka:BAAANQAECgYJBwAAAA==.Arkavine:BAAANQAECgEJAQABNQAECgcJIAAHAJgZAA==.Arkelly:BAABNQAECoEgAAIHAAcKmBkmLgDyAQAHAAcKmBkmLgDyAQAAAA==.Armedcookies:BAAANQADCgYIBgAAAA==.Artemicion:BAAANQADCgQIBAABNQAECgQICAAFAAAAAA==.Arutoria:BAAANQAECgEIAQAAAA==.',
As='Asche:BAAANQADCgYIBgAAAA==.Ashlie:BAAANQADCgcIDgAAAA==.Asirili:BAAANQAECgQJBQAAAA==.Asmoodeus:BAAANQAECggJCgABNQAECgkJIQAIAN4jAA==.',
Au='Auramaxxer:BAAANQADCggICAAAAA==.',
Av='Avazen:BAAANQAECgEJAQAAAA==.',
Ay='Ayrah:BAAANQAECgUJCAAAAA==.',
Ba='Badaboom:BAAANQADCgcIDQAAAA==.Badeeasu:BAAANQADCgQIBAABNQAFFAMIBgACABUhAA==.Badshammy:BAAANQAECgIJBAAAAA==.Baelcoz:BAAANQAECgUICwAAAA==.Baragan:BAAANQAECgEIAQAAAA==.',
Be='Beamqt:BAAANQAFFAEIAQAAAA==.Bear:BAAANQAECgUICAAAAA==.Bearwurst:BAAANQAECgQICAAAAA==.Beazle:BAAANQAECgQJCQAAAA==.Beefchub:BAACNQAFFIEGAAIBAAMK8gQ+DADXAAABAAMK8gQ+DADXAAA1AAQKgRYAAwEACAphBjpWAJsBAAEACAphBjpWAJsBAAkAAQrmGOEGAUwAAAAA.Beladora:BAAANQAFFAEIAQAAAA==.Bellarke:BAAANQADCgYIBgAAAA==.Belldelphine:BAABNQAECoEcAAQKAAkKsBztGABlAgAKAAgKxhntGABlAgALAAgK9BodGABRAgAMAAIKVR+JFACvAAAAAA==.Better:BAAANQADCgYIBgABNQAECggJHwALADsbAA==.',
Bi='Bichyone:BAAANQADCggJDwAAAA==.Bigback:BAABNQAECoEZAAMNAAgKxxS4JgAzAgANAAgKxxS4JgAzAgAOAAQK7xyHLAAPAQAAAA==.Bigmeattréat:BAAANQAECgEIAQAAAA==.Bigpurr:BAAANQAECgUICQABNQAFFAUICAALAG4KAA==.Bigtruss:BAAANQAECgIIAgAAAA==.Bilo:BAAANQAECgUJDgAAAA==.Bimpo:BAAANQAECgEIAQAAAA==.Biohazzard:BAAANQADCgUJBQAAAA==.Bipolar:BAAANQAECggICAAAAA==.',
Bl='Blangtron:BAAANQAECgYIDgAAAA==.Blickyz:BAAANQAECgQICAAAAA==.Bloodbortie:BAAANQAECgYJDAAAAA==.Blueflame:BAAANQADCgUJBQAAAA==.Blödhgárm:BAAANQADCggICwABNQAECgcIEgAFAAAAAA==.',
Bo='Boatsnack:BAAANQADCgcIFwAAAA==.Boboko:BAAANQAECgQIBAAAAA==.Boderationx:BAAANQADCggIDwABNQAECgkJHwAPAH8lAA==.Bodyshots:BAAANQAECgcJDwAAAA==.Boing:BAAANQABCgEJAQABNQADCgMJAwAFAAAAAA==.Bokar:BAAANQADCgEIAQABNQAECggJHgAQAHshAA==.Bokatan:BAAANQAECgEIAQAAAA==.Bolgc:BAAANQADCgcIBwABNQAECgQIBAAFAAAAAA==.Bonethug:BAAANQADCgUIBQAAAA==.Boofoo:BAAANQAECgQJBwAAAA==.Borbleybim:BAAANQAECgQICAAAAA==.Borella:BAAANQADCgEIAQABNQAFFAMJCwARAL8gAA==.Bortikai:BAAANQADCgcIBwAAAA==.Bortikus:BAAANQADCgUIBwAAAA==.Boscho:BAAANQAECgcJDwAAAA==.Boschoa:BAAANQAECgUICQABNQAECgcJDwAFAAAAAA==.Bouncedh:BAAANQAECgIIBAABNQAECgkJGwAQANkiAA==.Bowzarr:BAAANQADCgUICQAAAA==.Bowzerr:BAAANQADCgYIDAAAAA==.',
Br='Brayeda:BAAANQADCggJIwAAAA==.Breadpudn:BAAANQAECgUIBwAAAA==.Briighe:BAAANQADCgEJAQABNQAFFAEIAQAFAAAAAA==.Broccoliched:BAAANQAECgMJAwAAAA==.Brodacz:BAAANQADCgYIEgAAAA==.Brownii:BAAANQAECgYIDgAAAA==.',
Bu='Bubsdk:BAAANQABCgUIBQAAAA==.Bullohme:BAAANQADCgYIBgAAAA==.Burntbunss:BAAANQADCgUICQAAAA==.Burnysanders:BAAANQAECgYIAwAAAA==.Burritortega:BAAANQADCggIIAAAAA==.Burstinatrix:BAAANQADCgYJBgAAAA==.',
['Bé']='Bérserkblave:BAAANQADCggIFwAAAA==.',
['Bó']='Bóunce:BAABNQAECoEbAAIQAAkK2SLQEQBPAwAQAAkK2SLQEQBPAwAAAA==.',
Ca='Cainos:BAAANQADCgQIBQAAAA==.Calandra:BAAANQAECgQIDAAAAA==.Cantgetme:BAAANQAECgEIAQAAAA==.Carditis:BAACNQAFFIEHAAICAAMKPhRkCgDyAAACAAMKPhRkCgDyAAA1AAQKgSAAAgIACQogH6YUAOECAAIACQogH6YUAOECAAAA.Carditits:BAAANQADCgYIBgABNQAFFAMJBwACAD4UAA==.Catwilliams:BAAANQADCggJEAABNQAECgYIAwAFAAAAAA==.',
Ce='Celeríty:BAAANQADCgEJAQAAAA==.Ceri:BAAANQADCggJEAAAAA==.Cev:BAAANQAECgYJCgABNQAFFAMJBQAHAHYiAA==.Cevren:BAACNQAFFIEFAAMHAAMKdiKdDQC9AAARAAIKHSXGBgDRAAAHAAIKSCCdDQC9AAA1AAQKgSMABBEACQoDJk0BAOUDABEACQoDJk0BAOUDABIAAgrnGo5PAKoAAAcAAQojGkGRAEMAAAAA.',
Ch='Chals:BAABNQAECoEbAAITAAgKHh9fEwDlAgATAAgKHh9fEwDlAgAAAA==.Chaoselite:BAABNQAECoEoAAMJAAkKoBpJKgC0AgAJAAkKoBpJKgC0AgABAAgKjQ/mQQDtAQAAAA==.Chelia:BAAANQAECgEIAQAAAA==.Chuibacca:BAAANQAECgUIDAAAAA==.',
Cl='Claanx:BAAANQAECgIJAgAAAA==.Clops:BAAANQADCgUICwAAAA==.',
Co='Cobrakilla:BAAANQAECgQIBgAAAA==.Cobrakiller:BAAANQADCgMJAwABNQAECgQIBgAFAAAAAA==.Coldgrasp:BAAANQADCgcJBwAAAA==.Coochpooch:BAAANQADCgYIDAAAAA==.Corbun:BAAANQADCggJFQAAAA==.Corpsebane:BAAANQAECgUJCQAAAA==.Cortèx:BAAANQADCgEIAQAAAA==.Cosmicgate:BAABNQAECoEfAAMLAAkKWSE9CgAPAwALAAgKziE9CgAPAwAKAAUK6B3YKADGAQAAAA==.Cowguy:BAAANQAECgUIBQAAAA==.Cowlawladin:BAAANQAECgcIDQAAAA==.',
Cr='Crockett:BAABNQAECoEjAAIUAAkKwhWcKACTAgAUAAkKwhWcKACTAgAAAA==.Croissantz:BAAANQAECgUIDQAAAA==.Crusha:BAAANQADCgMIAwAAAA==.Cryssis:BAAANQADCgYIBgAAAA==.',
Cu='Cubanmage:BAAANQAECgQICAABNQAECgUJCAAFAAAAAA==.Cubanpally:BAAANQAECgUJCAAAAA==.Cucucachoo:BAAANQADCggJGQAAAA==.Cupgayke:BAAANQAECgUJBQABNQAECgcJCQAFAAAAAA==.',
Cy='Cyndi:BAAANQAECgEJAQAAAA==.Cynnabar:BAAANQADCgIIAgAAAA==.Cyrce:BAAANQADCgQIBAAAAA==.',
Da='Daanos:BAAANQADCgYIBgABNQAECggJGAAVAEkhAA==.Daeltha:BAABNQAECoEdAAIGAAkKwRs7BwDZAgAGAAkKwRs7BwDZAgAAAA==.Dafdafdaf:BAAANQAECgQIBAAAAA==.Daffenprime:BAABNQAECoElAAISAAkKjh+4BgBDAwASAAkKjh+4BgBDAwAAAA==.Dailong:BAAANQAECgIIAgAAAA==.Dalux:BAAANQADCgUIBgAAAA==.Danastey:BAAANQADCgYIBgAAAA==.Daneglesack:BAAANQAECgYJDQAAAA==.Danoslock:BAAANQADCggICAABNQAECggJGAAVAEkhAA==.Danosxd:BAABNQAECoEYAAIVAAgKSSETOADkAgAVAAgKSSETOADkAgAAAA==.Daragnos:BAABNQAECoEiAAMIAAkKiR0dJACWAgAIAAgKvR0dJACWAgAWAAQKSRWQKwD8AAAAAA==.Darkfäll:BAAANQADCgEJAQAAAA==.Darkhært:BAAANQAECgUJEAAAAA==.Darkkai:BAABNQAECoEcAAMCAAgK2R8mEwDtAgACAAgK2R8mEwDtAgADAAIKHA2KvgBpAAAAAA==.Darthmuffin:BAAANQAECgcIDgAAAA==.Daryl:BAAANQAFFAEIAQABNQAFFAMJAgAFAAAAAA==.Dasprime:BAAANQAECgYICgAAAA==.Dastòmper:BAAANQADCgUIBQABNQAECgQJCAAFAAAAAA==.Dayven:BAAANQADCggJCQAAAA==.',
De='Deadhitmann:BAAANQAECgEIAQAAAA==.Deathbringer:BAAANQAECggIBQAAAA==.Deathpenance:BAAANQADCgYIBgAAAA==.Deathãngel:BAAANQAECgcIEgAAAA==.Decall:BAEANQAECgMIBgABNQAECgUIBQAFAAAAAA==.Decepper:BAAANQAECgEIAgAAAA==.Degraded:BAAANQAECggJEwAAAA==.Delenix:BAAANQADCgYIBgABNQADCggIDQAFAAAAAA==.Demelion:BAAANQAECgMIAwABNQAFFAEIAQAFAAAAAA==.Demonblood:BAAANQAECgUIBgAAAA==.Denul:BAAANQAECggICAAAAA==.Ders:BAAANQADCggIDgAAAA==.Dessius:BAAANQAECggIDAAAAA==.Dethstra:BAAANQAECgQJBQAAAA==.Devouring:BAAANQADCggICAAAAA==.Deüs:BAAANQAECgQICAAAAA==.',
Di='Diffstyle:BAAANQAECggJCQAAAA==.Dionotus:BAAANQAECgEIAQAAAA==.Dirtgrub:BAAANQAECgQIBAAAAA==.Divdan:BAAANQADCggICAAAAA==.Divert:BAAANQADCggICAAAAA==.',
Dk='Dkhaoz:BAAANQAECgcIDgABNQADCgYIDAAFAAAAAA==.Dkinabox:BAAANQADCggJAgABNQAECgYIAwAFAAAAAA==.',
Do='Docturnal:BAAANQADCgMIAwAAAA==.Dolphina:BAAANQAECgQIBAAAAA==.Donfrancisco:BAAANQAECgEIAQAAAA==.Donsaul:BAAANQADCggICgAAAA==.Donuts:BAAANQADCgMIAwAAAA==.Doomsure:BAAANQADCgMIAwAAAA==.Doryani:BAAANQAECgQIBAAAAA==.Doømhammer:BAAANQADCggICAAAAA==.',
Dr='Dracburton:BAAANQADCgEIAQAAAA==.Drachen:BAAANQADCgYIBgABNQAECgcJDwAFAAAAAA==.Dracnaphobia:BAAANQADCgMIAwABNQAECgYIDAAFAAAAAA==.Dragynsabor:BAAANQADCgYJDwAAAA==.Dragynsoul:BAAANQADCgYIDAAAAA==.Dranok:BAAANQAECgQIBAAAAA==.Dratnosfan:BAAANQADCgYJCgABNQAECggJGAAVAEkhAA==.Drballseks:BAAANQAECgUJBQAAAA==.Drdingus:BAAANQADCggJCAAAAA==.Dreadfox:BAAANQADCgYJCwAAAA==.Dreamlike:BAABNQAECoEmAAIOAAkKciLFAwBcAwAOAAkKciLFAwBcAwAAAA==.Drezco:BAAANQADCgUIBwABNQAFFAMJBQAHAHYiAA==.Droit:BAAANQAECgQIBAAAAA==.Drstormii:BAAANQAECgEIAQAAAA==.Drumelion:BAAANQAFFAEIAQAAAA==.',
Du='Dukazra:BAAANQADCgcJIQAAAA==.Dunkndonuts:BAAANQAECgYICwAAAA==.',
['Dé']='Déathy:BAAANQAECgQJBQABNQAECgQJBQAFAAAAAA==.',
Ea='Earthencore:BAAANQAECgUJEgAAAA==.',
Eb='Ebully:BAAANQAECgMIAwAAAA==.',
Ed='Edgyboy:BAAANQAECgEJAgAAAA==.Edjelord:BAAANQADCgcICQAAAA==.',
Eg='Eggmilk:BAAANQADCgUIBQAAAA==.Egirltank:BAAANQADCgcJDQABNQAECgkJGgAJALofAA==.',
El='Elaxa:BAAANQADCggJDAABNQAFFAQICQALAOIWAA==.Eldanath:BAAANQADCgYIBgAAAA==.Eliriel:BAAANQADCgQJBAABNQADCgYICgAFAAAAAA==.Elnaa:BAAANQADCgUIBQAAAA==.Elsulan:BAAANQADCggICAAAAA==.Elteethree:BAABNQAECoEXAAIXAAkK0Az8FAABAgAXAAkK0Az8FAABAgAAAA==.Elunelock:BAAANQADCggJFgAAAA==.Elunepal:BAAANQAECgYJDAAAAA==.Elys:BAAANQAECgUJCwAAAA==.Elysel:BAAANQAECgMIAwABNQAECgkKHgARAJUkAA==.',
Em='Emalynn:BAAANQADCgYIBgAAAA==.Emilyfrost:BAAANQADCgQIBAAAAA==.',
En='Enigmà:BAABNQAECoEcAAMVAAgKcBGJjQD1AQAVAAgKcBGJjQD1AQAYAAEK4AFLNgApAAAAAA==.Enmanuel:BAAANQAECgcIDwAAAA==.',
Ep='Epyôn:BAABNQAECoEmAAMDAAkKcCKyCwBdAwADAAkKcCKyCwBdAwAZAAYKMx4uDQApAgAAAA==.',
Er='Ericthebrave:BAAANQADCgcICQAAAA==.Eriodara:BAAANQADCgIIAgAAAA==.',
Es='Escas:BAAANQAECgUICgAAAA==.Escaz:BAAANQAECgQIBAAAAA==.Esrahaddon:BAABNQAECoEYAAIGAAcKXxZ4DwAKAgAGAAcKXxZ4DwAKAgAAAA==.',
Et='Etreyu:BAAANQAECgEIAgABNQAECgcIGAAJANsKAA==.',
Ev='Evanora:BAAANQAECgUIDgAAAA==.Evillinx:BAAANQAECgQJBQAAAA==.Evilmaru:BAAANQAECgMJAwAAAA==.Evokelion:BAAANQAECgMIAwABNQAFFAEIAQAFAAAAAA==.Evoxx:BAAANQAECgEIAQAAAA==.',
Ew='Ewok:BAAANQADCgQIBAAAAA==.',
Ex='Exploited:BAAANQADCgcIBwAAAA==.',
Fa='Factz:BAAANQADCgEIAQAAAA==.Faespalmn:BAABNQAECoEhAAICAAkK/x5MCwAzAwACAAkK/x5MCwAzAwAAAA==.Fatalstab:BAAANQAECgMJAwAAAA==.Fauin:BAAANQADCgYIBgAAAA==.',
Fe='Featheramby:BAAANQADCgIIAgAAAA==.Felenesh:BAAANQADCgEIAQAAAA==.Felwräth:BAAANQAECgcJBwAAAA==.Fenthead:BAAANQADCgYJCgABNQAECgkJGgAJALofAA==.Fernandôge:BAAANQAECgUIDAAAAA==.',
Fi='Fidel:BAAANQAECgcIDQAAAA==.Fil:BAAANQAECgcJEwAAAA==.Fisac:BAACNQAFFIENAAIPAAYK6RXZAgDqAQAPAAYK6RXZAgDqAQA1AAQKgSUAAg8ACQrwIWgFAFsDAA8ACQrwIWgFAFsDAAAA.Fishbubble:BAAANQABCgYIBwAAAA==.Fistbox:BAAANQADCggICAAAAA==.',
Fl='Fletchtern:BAAANQADCgEIAQABNQAECgQIDQAFAAAAAA==.Flexicute:BAAANQADCgcIBwAAAA==.Flexlock:BAAANQADCgMIAwAAAA==.Flextime:BAAANQAECgQJBwAAAA==.Flippinfear:BAAANQAECgYJCwAAAA==.',
Fo='Folius:BAACNQAFFIETAAMIAAYKoyDJAABHAgAIAAYK8R/JAABHAgAWAAEKIhHXDwBYAAA1AAQKgR8AAwgACQppJjwBANIDAAgACQppJjwBANIDABYAAwr7HRMuAO0AAAAA.Fortyourself:BAAANQADCggIDwABNQAFFAMJBwACAD4UAA==.',
Fr='Franky:BAAANQAECgYICgAAAA==.Franzu:BAAANQAECgcIEwAAAA==.Freehits:BAAANQADCgEIAQAAAA==.Freelaughs:BAAANQADCgQIBAAAAA==.Friggitte:BAAANQADCggIFgAAAA==.Friholy:BAAANQAECgUIDQABNQAECgkJHwACALoSAA==.Frostdragyn:BAAANQAECgEJAQAAAA==.Frosteviã:BAAANQAECgQIBAAAAA==.',
Fu='Full:BAAANQADCggIFAAAAA==.Furgoblin:BAAANQAECgQICQABNQAECgYJEQAFAAAAAA==.',
['Fâ']='Fâdêd:BAAANQADCggICAAAAA==.',
['Fä']='Fäerise:BAAANQADCgEIAQAAAA==.',
['Fé']='Fén:BAAANQADCgYIDAABNQAECgQJCQAFAAAAAA==.',
['Fë']='Fëanör:BAAANQAECgYIDgAAAA==.',
['Fø']='Førce:BAAANQAECgEIAQAAAA==.',
Ga='Gabi:BAAANQADCgcIDQAAAA==.Gacrüx:BAAANQAECgEJAQAAAA==.Galadrìel:BAABNQAECoEkAAIJAAkKjRkyMgCOAgAJAAkKjRkyMgCOAgAAAA==.Galadrìèl:BAAANQAECgUJBgAAAA==.Gambol:BAAANQADCgYIBgAAAA==.Garegar:BAAANQADCgYIBgAAAA==.',
Ge='Gengizkhan:BAAANQADCgUICgABNQADCgYICgAFAAAAAA==.',
Gh='Ghorn:BAAANQAECgQJCQAAAA==.',
Gl='Glaivetoes:BAAANQAECggICwAAAA==.Glareaforsor:BAAANQADCggIEAAAAA==.Glimpse:BAAANQAECgUJCQAAAA==.Glytteris:BAAANQAECgMJAwAAAA==.',
Go='Gochurass:BAAANQAECgEIAQAAAA==.Goonspree:BAAANQADCgEIAQAAAA==.',
Gr='Grabbyhands:BAAANQADCgEIAQAAAA==.Grapthar:BAEANQAECgUIBQAAAA==.Grenth:BAAANQADCgMIAwAAAA==.Greyarrow:BAAANQAECgUICwAAAA==.Greæd:BAACNQAFFIESAAITAAcKKRUCAQBxAgATAAcKKRUCAQBxAgA1AAQKgSQAAxMACQpoJMIIAEUDABMACQpoJMIIAEUDABoABgrLHYwHAJ4BAAAA.Grimgown:BAAANQAECgMIAwABNQAECgcJDwAFAAAAAA==.Grimreaper:BAAANQAECgMIAwAAAA==.Grizzard:BAAANQAECgMJBAAAAA==.Gruckek:BAABNQAECoEdAAMQAAkKSRv5LwCqAgAQAAkK1Rr5LwCqAgAbAAIKTg0KJgBdAAAAAA==.Grææd:BAAANQAECgQIBAABNQAFFAcJEgATACkVAA==.',
Gu='Gulanis:BAAANQAECgQICQAAAA==.Guldhakii:BAAANQAECggICQAAAA==.',
Gw='Gwendlyne:BAAANQAECgQIBwAAAA==.',
['Gó']='Góddess:BAAANQADCggICQAAAA==.',
Ha='Hag:BAAANQAECgQIBAABNQAFFAYICwAJAGAOAA==.Hakarii:BAAANQAECgQIBQABNQAFFAUICAALAG4KAA==.Halloffaith:BAAANQAECgcIDwAAAA==.Harissa:BAAANQADCgEJAQABNQAECgQJBQAFAAAAAA==.Harry:BAAANQAECgEIAQAAAA==.Hawgneto:BAAANQADCggIDQAAAA==.Hazel:BAAANQAECgUICQAAAA==.',
He='Hellig:BAABNQAECoEbAAMTAAgKGBfnOwD7AQATAAgKGBfnOwD7AQAcAAEK+BKZUgA4AAAAAA==.Hellofriday:BAAANQADCggICAAAAA==.Hellíg:BAAANQADCggIDgAAAA==.Hetzfury:BAAANQAECgYIBgAAAA==.Heyman:BAAANQAECgIIAgAAAA==.',
Hi='Hideyerweed:BAAANQAECgQJBAABNQAECgkJHAAQAO8bAA==.Higi:BAAANQADCgYIBgAAAA==.',
Ho='Holistic:BAABNQAECoEgAAICAAkKuySRAQDAAwACAAkKuySRAQDAAwAAAA==.Holyclanx:BAAANQADCgYIBgAAAA==.Holylips:BAAANQAECggJBwAAAA==.Holyzamboni:BAABNQAECoEVAAIBAAgKdRtvIACWAgABAAgKdRtvIACWAgAAAA==.Honeyblunt:BAAANQADCgIIAgAAAA==.Horsepower:BAAANQADCgIJAgAAAA==.Horvarth:BAAANQADCgUJBQAAAA==.Hotchocmilk:BAAANQAECgUIDQAAAA==.',
Hr='Hr:BAAANQADCgcIBwAAAA==.',
Hu='Huanglow:BAAANQADCgcJBwAAAA==.Hunex:BAAANQAECgYJBgAAAA==.Huntaa:BAABNQAECoEZAAMdAAgK6iS+AABrAwAdAAgK6iS+AABrAwAPAAEKaxQ/VQBEAAAAAA==.Hurají:BAABNQAECoEZAAMBAAkKLRtDFADqAgABAAkKLRtDFADqAgAJAAUKuQJg4QCaAAABNQAFFAYICwAeACAXAA==.Huråji:BAACNQAFFIELAAIeAAYKIBedAAAkAgAeAAYKIBedAAAkAgA1AAQKgSQAAh4ACQoXIeoDADUDAB4ACQoXIeoDADUDAAAA.',
Il='Ilnookll:BAAANQADCgUJCQAAAA==.',
Im='Imblooms:BAAANQADCgEIAQAAAA==.Imbooms:BAAANQADCgYJBgAAAA==.Imryl:BAAANQAECgYIEQAAAA==.',
Io='Ionea:BAAANQADCgYICgABNQAECggIGQAZAJIaAA==.',
Ir='Irisaar:BAAANQADCgMJAwAAAA==.Ironpaws:BAAANQAECgYJEQAAAA==.Iryssoscaly:BAAANQADCgIIAgAAAA==.',
Is='Isa:BAAANQAECgYICwABNQAFFAUICAALAG4KAA==.Isaa:BAACNQAFFIEIAAILAAUKbgoVBACOAQALAAUKbgoVBACOAQA1AAQKgR0AAwsACQrRGpwQAK4CAAsACQq5GpwQAK4CAAoAAgqWFyFRAI4AAAAA.Isamaru:BAAANQADCgYJBgAAAA==.Istredd:BAAANQAECgEJAQAAAA==.',
Ja='Jackrackham:BAAANQAECgUJDQAAAA==.Jakuza:BAAANQADCgYIBgABNQAECgUJCQAFAAAAAA==.Jaydeep:BAAANQABCgIIAgAAAA==.Jayrayco:BAAANQABCgQIBQAAAA==.',
Jd='Jdub:BAAANQAECgYJDQAAAA==.',
Je='Jebx:BAAANQADCgYIBgABNQAFFAUJCgADAI0RAA==.Jebydk:BAAANQAECgUIBQABNQAFFAUJCgADAI0RAA==.Jebysham:BAACNQAFFIEKAAIDAAUKjREBBQCTAQADAAUKjREBBQCTAQA1AAQKgSgABAMACQrJII4OAEEDAAMACQoqII4OAEEDABkABwpOHGYLAFUCAAIAAgpEAkLIAEcAAAAA.Jeffybubbles:BAAANQADCggIEAAAAA==.Jeffytotems:BAAANQAECgcIDgAAAA==.Jelsy:BAAANQAECgUICwAAAA==.Jepx:BAAANQAECgQIBwAAAA==.Jesly:BAAANQADCgcJEwABNQAECgUICwAFAAAAAA==.Jessibella:BAABNQAECoEoAAITAAkKsxwrDgAOAwATAAkKsxwrDgAOAwAAAA==.',
Jh='Jhnstzy:BAAANQADCgYICwAAAA==.',
Jo='Johnsteez:BAAANQAECgEIAQAAAA==.Jorndalf:BAABNQAECoEaAAIDAAgK1R+JGQDfAgADAAgK1R+JGQDfAgAAAA==.',
Jt='Jt:BAAANQABCgIIAgAAAA==.',
Ju='Juggz:BAAANQAECgUIDgAAAA==.Juicylewts:BAAANQADCgcIBwABNQAECgYIDAAFAAAAAA==.Justabutcher:BAAANQAECgUJEAAAAA==.',
Jw='Jwag:BAAANQADCgYIFAAAAA==.',
['Jê']='Jêcht:BAABNQAECoElAAITAAkKdyTWAwCLAwATAAkKdyTWAwCLAwAAAA==.',
Ka='Kafur:BAAANQAECgYJDwAAAA==.Kaiido:BAAANQAECgEIAgABNQAFFAUICAALAG4KAA==.Kak:BAAANQAECgQIBAAAAA==.Kakesoba:BAAANQADCgcIBwABNQADCgcIFwAFAAAAAA==.Kalstorm:BAAANQAECgQJBAABNQAECgQJBQAFAAAAAA==.Karmanda:BAAANQAECgEJAQAAAA==.Kattel:BAAANQADCggJEgAAAA==.Kaychow:BAAANQAECgcICgAAAA==.',
Ke='Keither:BAAANQADCgMJAwAAAA==.Kelendor:BAABNQAECoEmAAIUAAkKbxCRMQBtAgAUAAkKbxCRMQBtAgAAAA==.Kellandil:BAAANQADCgQICQAAAA==.Kemmlerok:BAAANQAECgIIAgAAAA==.Kenju:BAAANQAFFAEIAQAAAA==.Kensie:BAAANQAECggIEgAAAA==.',
Kh='Khlampz:BAABNQAECoEYAAMfAAgKTxjkEACEAgAfAAgKTxjkEACEAgAgAAUKegUlLgDrAAAAAA==.Khlampzight:BAAANQAECgUICAABNQAECggIGAAfAE8YAA==.Khlampzoker:BAAANQADCggIEAABNQAECggIGAAfAE8YAA==.Khondor:BAAANQAECgEJAQAAAA==.',
Ki='Kiel:BAAANQAECgQICAAAAA==.Kigen:BAAANQAECgEIAQAAAA==.Kikurface:BAAANQADCggIIAAAAA==.Kilmonger:BAAANQADCggJAgAAAA==.Kimjungun:BAAANQADCgEIAQAAAA==.Kiranax:BAABNQAECoEtAAQRAAkKeCXfAQDWAwARAAkKeCXfAQDWAwAHAAMKVAcTfgB+AAASAAEK1RJebwAxAAABNQAFFAIIBAAIANYHAA==.Kiraxxus:BAABNQAFFIEEAAIIAAIK1gcfHACCAAAIAAIK1gcfHACCAAAAAA==.Kittensune:BAAANQABCgYIBgAAAA==.',
Ko='Koinu:BAABNQAECoEdAAIeAAgKdiGoBQAAAwAeAAgKdiGoBQAAAwABNQAFFAIIAgAFAAAAAA==.Kooriaisu:BAAANQADCgUJCAAAAA==.Korbun:BAAANQADCgYIDgAAAA==.Kovskii:BAAANQADCggIHAAAAA==.',
Kr='Krad:BAAANQADCggIEwAAAA==.Kriathura:BAAANQAECgYICgAAAA==.Krizah:BAAANQADCgUJBAAAAA==.',
Ku='Kukui:BAAANQADCgYJBgABNQAECgUJDQAFAAAAAA==.',
Kw='Kwangpow:BAAANQAECgMJBgAAAA==.',
['Kà']='Kàkàshi:BAABNQAECoEaAAIVAAgK3BE/ewAkAgAVAAgK3BE/ewAkAgAAAA==.',
La='Laethal:BAAANQADCgQIBQAAAA==.Lambbchopp:BAAANQADCgUIDgAAAA==.Lassitar:BAAANQADCgEIAQAAAA==.Lazyrage:BAAANQAECgUICQAAAA==.Lazyreaper:BAAANQADCgUJCwABNQAECgUICQAFAAAAAA==.',
Le='Lebronto:BAABNQAECoEeAAIQAAgKeyH5IgDpAgAQAAgKeyH5IgDpAgAAAA==.Legsquats:BAAANQAECgQJCAABNQAECggIHQAHACoYAA==.Lessirs:BAAANQAECgEIAQAAAA==.Lexatron:BAAANQABCgEIAQAAAA==.',
Li='Lichnaught:BAAANQADCgcJEwABNQAECgUICwAFAAAAAA==.Lifetapped:BAAANQAECgEIAQAAAA==.Lilfluffy:BAAANQAECgMJAgAAAA==.Liquid:BAAANQADCgcIEAAAAA==.Little:BAAANQABCgQIBAAAAA==.',
Ll='Llikdaor:BAAANQAECgUIDwAAAA==.',
Lo='Loaded:BAAANQAECgYIDgAAAA==.Lockitupp:BAAANQADCgUIBQAAAA==.Loikk:BAAANQADCgMIAwAAAA==.Loodacrits:BAAANQAECgUIBwAAAA==.',
Lu='Lushylock:BAAANQADCgEIAQAAAA==.',
Ma='Macklin:BAAANQAECgEIAQAAAA==.Maddalynn:BAABNQAECoEbAAIBAAgKNRM2OAAYAgABAAgKNRM2OAAYAgAAAA==.Maelstrox:BAAANQADCgUIDQAAAA==.Magandadrake:BAABNQAECoEiAAMXAAkKaRSiDgBxAgAXAAkKaRSiDgBxAgAGAAEKlglWLQA6AAAAAA==.Magerita:BAAANQAECgEIAQAAAA==.Magharat:BAAANQADCgYIDwABNQAECgkJIAADAF0jAA==.Magicman:BAAANQADCgYIBgAAAA==.Malacanthet:BAAANQADCggIEAAAAA==.Malyss:BAAANQAECgUJBQAAAA==.Mandelstam:BAAANQAECgYJDAAAAA==.Mangkanor:BAAANQADCgYICgAAAA==.Mangoloidman:BAAANQADCgIIAgABNQADCggIEAAFAAAAAA==.Marow:BAAANQADCgQIBAAAAA==.Marsan:BAAANQABCgQIBgAAAA==.Marxen:BAAANQADCgQIBAAAAA==.',
Mc='Mcsstab:BAAANQADCgYIBgAAAA==.',
Me='Meatballer:BAAANQAECgYIBwAAAA==.Meatballz:BAABNQAECoEZAAIZAAgKkholCQCPAgAZAAgKkholCQCPAgAAAA==.Mecalux:BAAANQAECgEJAQAAAA==.Meliodäs:BAAANQADCgYJBgABNQAECgQJCQAFAAAAAA==.Meloco:BAAANQAECgUJBwAAAA==.Melody:BAACNQAFFIESAAITAAcKyx5eAACuAgATAAcKyx5eAACuAgA1AAQKgSAAAhMACQoaJnoEAIADABMACQoaJnoEAIADAAAA.Menj:BAAANQAECgEIAQABNQAFFAEIAQAFAAAAAA==.Meno:BAAANQADCggJEQAAAA==.Meowcheese:BAAANQAECgQICQAAAA==.Meowmix:BAAANQADCgUIBQABNQAECgQJBQAFAAAAAA==.Meridah:BAAANQADCgUIBQAAAA==.Mert:BAAANQADCgUJCAAAAA==.Mesosphere:BAEANQAECgQICQAAAA==.',
Mi='Midorii:BAAANQAECgUJBQAAAA==.Migpala:BAAANQAECgQIBQAAAA==.Miiniimaage:BAAANQAECgMJBgAAAA==.Milkmann:BAAANQABCgIIAgAAAA==.Milkymoos:BAAANQAECgUJCQAAAA==.Minar:BAABNQAECoEXAAMMAAkKsxm3AwChAgAMAAgKthy3AwChAgAKAAYKoAKWSADEAAABNQAECgkKHgARAJUkAA==.Minoic:BAAANQADCgYJFAAAAA==.Mistamiyagi:BAAANQAECgYIDAAAAA==.Mistchivus:BAAANQAECgQIBAAAAA==.Mistelion:BAAANQAECgQIBAABNQAFFAEIAQAFAAAAAA==.Mizrah:BAAANQADCggICAABNQAECgcJEgAFAAAAAA==.',
Mk='Mkultra:BAAANQAECgEJAQAAAA==.',
Mo='Mobbster:BAAANQADCggIGgAAAA==.Mohnster:BAAANQADCgMIBAAAAA==.Moiststaff:BAAANQADCgcIBwAAAA==.Moisttotems:BAAANQADCgEIAQAAAA==.Monipouch:BAAANQAECgYJEQAAAA==.Moonchicken:BAAANQADCgQJBAAAAA==.Moondaisy:BAAANQADCgIIAgAAAA==.Moopocalypse:BAAANQAECgQIBQAAAA==.Moosenukle:BAAANQADCgQIBQAAAA==.Morphaeus:BAAANQADCgUICgAAAA==.Mortar:BAAANQAECgMIAwAAAA==.Mozrog:BAAANQAECgcIDQAAAA==.',
Ms='Mshchase:BAAANQADCgEIAQAAAA==.',
Mu='Muffblaster:BAABNQAECoEhAAMVAAkKhCJlFQBjAwAVAAkKhCJlFQBjAwAYAAIKOx1WGgCuAAAAAA==.Murphet:BAAANQAECgYIDAAAAA==.',
My='Mythrix:BAAANQAECgUIBwABNQAECgkJGAAUAE4hAA==.',
['Mí']='Míra:BAAANQAECgQJBwAAAA==.',
['Mó']='Mónsoon:BAAANQABCgUIBQAAAA==.',
['Mö']='Mönïca:BAAANQAECgMIBAAAAA==.Mörrys:BAAANQAECgIIAgAAAA==.',
Na='Narrath:BAAANQABCgYICAAAAA==.Narwhal:BAAANQAECgcJCQAAAA==.Nathenatra:BAAANQADCgQIBAABNQAECgkJJQASAI4fAA==.Naurea:BAAANQADCgcJBwAAAA==.',
Ne='Neeko:BAAANQAECgcIEwAAAA==.Nenechi:BAAANQAECggIBwABNQAFFAMJAgAFAAAAAA==.Neonmoose:BAAANQAECgIJAwABNQAECggICwAFAAAAAA==.Nezbrez:BAAANQADCgcIDQAAAA==.Nezzrad:BAAANQADCgMIAwAAAA==.',
Nh='Nhthree:BAAANQAECgQJDAAAAA==.',
Ni='Niklaws:BAAANQAECgIIAgABNQAECgkJHwACALoSAA==.',
No='Nofsha:BAAANQADCgUIBQABNQAECgYJDAAFAAAAAA==.Noktyx:BAAANQADCggJEAABNQAECgIIAgAFAAAAAA==.Nomoney:BAAANQAECgEIAwAAAA==.Norasong:BAAANQAECgEIAQAAAA==.Norava:BAAANQAECgQIBQAAAA==.Nostick:BAABNQAECoEjAAMLAAkK/yERBgBZAwALAAkK/yERBgBZAwAKAAIKmR4bVAB8AAAAAA==.Novacrono:BAABNQAECoEcAAIGAAkK7Q1LDgAmAgAGAAkK7Q1LDgAmAgAAAA==.Noxioustoast:BAAANQAFFAEIAQAAAA==.Nozdog:BAAANQADCgUIDgAAAA==.',
Nu='Nuke:BAABNQAECoEyAAIQAAkK8RqDHwD8AgAQAAkK8RqDHwD8AgAAAA==.',
['Nô']='Nôôk:BAAANQAECgUICAAAAA==.',
Oa='Oaklánd:BAAANQAECggIAQAAAA==.',
Od='Odeinn:BAAANQADCgEIAQAAAA==.Odiare:BAAANQADCgUIBQAAAA==.',
Ok='Okogo:BAAANQADCgQJBAABNQADCgYICgAFAAAAAA==.',
Or='Orkhis:BAAANQAECgcIDgAAAA==.',
Ou='Outbrèak:BAAANQAECgUJDAAAAA==.',
Ow='Owo:BAAANQABCgQIBQABNQAECgUJDQAFAAAAAA==.',
Oz='Ozzyosbourne:BAAANQABCggJDQAAAA==.',
['Oá']='Oáklánd:BAAANQAECggJCAAAAA==.',
Pa='Pakuru:BAABNQAECoEbAAINAAgKuRqvHACNAgANAAgKuRqvHACNAgAAAA==.Pal:BAAANQAECgIIAgAAAA==.Palachin:BAAANQAECgcIDQAAAA==.Paladelion:BAABNQAECoEfAAQBAAkKKx7QGwC0AgABAAgKqB3QGwC0AgAJAAUKMBqKigBiAQAhAAEKmR7XQABYAAABNQAFFAEIAQAFAAAAAA==.Paleonebula:BAAANQAECgMJAwAAAA==.Pallmtree:BAAANQAECgMIBAABNQAECgcJDwAFAAAAAA==.Pallyberry:BAAANQADCgYIBgABNQAECgQJCQAFAAAAAA==.Pangittroll:BAAANQAECgUJDgAAAA==.Papatotems:BAAANQADCggIEQAAAA==.Papå:BAAANQAECgUJBwAAAA==.Parang:BAAANQAECgUJBQAAAA==.Partyphil:BAAANQAECgQJBAAAAA==.Pawtirra:BAAANQADCgIIAgAAAA==.',
Pe='Perfume:BAAANQAECgEIAQAAAA==.Persephone:BAAANQADCgMIAwABNQAECggIGwAQAKUfAA==.Petri:BAAANQAECgQJBwAAAA==.',
Pi='Pickwaton:BAABNQAECoEaAAMCAAkKGxsrFwDOAgACAAkKGxsrFwDOAgAZAAIKqwJ+IgBhAAAAAA==.Pinnhead:BAAANQAECgEJAQAAAA==.Pipen:BAACNQAFFIEOAAIBAAUKugZVBgB7AQABAAUKugZVBgB7AQA1AAQKgSYAAwEACQqQDbIzAC0CAAEACQqQDbIzAC0CAAkACAoTGWxNAB8CAAAA.Pixelglitter:BAAANQADCgYJCAAAAA==.',
Pl='Pld:BAAANQADCgcIBwAAAA==.',
Po='Potatatoes:BAAANQADCgUJBQAAAA==.Poxrot:BAAANQADCgQIBAABNQAECgEIAQAFAAAAAA==.',
Pr='Praize:BAABNQAECoEmAAMIAAkKyxwTIQClAgAIAAgKTRwTIQClAgAWAAQKcRQnJwAYAQAAAA==.Press:BAACNQAFFIELAAIJAAYKYA5oAgDYAQAJAAYKYA5oAgDYAQA1AAQKgSsAAgkACQr5Jd4BAOcDAAkACQr5Jd4BAOcDAAAA.Prìde:BAAANQAECgQIBAABNQAFFAcJEgATACkVAA==.',
Ps='Psykopathik:BAAANQAECgUICwAAAA==.',
Pu='Puddl:BAACNQAFFIEFAAIDAAIKiQ2TEgCXAAADAAIKiQ2TEgCXAAA1AAQKgSEAAwMACQrgHHMXAPACAAMACQrgHHMXAPACAAIACArLF5s+APQBAAAA.Purrsephone:BAAANQADCgEIAQAAAA==.',
Py='Pyrocutie:BAAANQADCggICwABNQAECgkJHAAKALAcAA==.',
Qa='Qaa:BAAANQAECgQICQAAAA==.',
Qh='Qhaos:BAAANQADCgYIBgABNQADCgYIDAAFAAAAAA==.Qhaoss:BAAANQADCgYIDAAAAA==.',
Qi='Qirl:BAAANQADCgcJBwAAAA==.',
Qt='Qti:BAAANQADCggIHAAAAA==.',
Qu='Quadnines:BAAANQAECgQJCgAAAA==.Quelivia:BAAANQADCgEIAQABNQAECgYIEQAFAAAAAA==.Ques:BAAANQADCgcIFwAAAA==.Quesly:BAAANQAECgYJDAAAAA==.Quetzacoatl:BAAANQAECgYJDwAAAA==.',
Ra='Rabbit:BAABNQAECoEWAAMCAAgKwBOsQQDnAQACAAgKwBOsQQDnAQADAAUKiSEpRQDfAQAAAA==.Racophorus:BAAANQADCggIIAAAAA==.Raffe:BAAANQAECgQICgAAAA==.Rammsteen:BAAANQAECgMIAgAAAA==.Rarity:BAAANQAECgEIAwAAAA==.Ratarga:BAABNQAECoEgAAIDAAkKXSOvBgCXAwADAAkKXSOvBgCXAwAAAA==.Rattroll:BAAANQAECgUIBwABNQAECgkJIAADAF0jAA==.Ratzgül:BAAANQAECggIBgAAAA==.Ravenaa:BAABNQAECoEaAAIJAAgKvRh8PwBUAgAJAAgKvRh8PwBUAgAAAA==.',
Re='Readycheck:BAAANQADCgEIAQAAAA==.Reallywanna:BAAANQAECgEIAQAAAA==.Reddragyn:BAAANQAECgQJDAAAAA==.Reeves:BAAANQAECgEIAwAAAA==.Reggiez:BAAANQADCggIIwAAAA==.Reinbert:BAAANQAECgQIBAABNQAECgQJBQAFAAAAAA==.Rektski:BAABNQAECoEeAAMRAAkKlSTBAwCqAwARAAkKlSTBAwCqAwAHAAMKaB+9XwDyAAABNQAECgkKHgARAJUkAA==.Remiel:BAAANQAECgEIAQABNQAECgQICAAFAAAAAA==.Remixi:BAAANQAECgIIAgAAAA==.Renzer:BAAANQAECgEIAQAAAA==.Reprosal:BAAANQAECgMIBAABNQAECggIEgAFAAAAAA==.Restasis:BAAANQADCgUIBwAAAA==.Retburn:BAABNQAECoEYAAIJAAgKVRf/QgBHAgAJAAgKVRf/QgBHAgAAAA==.Reveluv:BAAANQAECgYJCwAAAA==.',
Rh='Rheagar:BAAANQADCggJCAAAAA==.Rheveus:BAAANQAECgcICwAAAA==.',
Ri='Rickehlol:BAAANQADCgYICgAAAA==.Righturn:BAAANQAECgQIDQAAAA==.Rikkeh:BAAANQADCgIIAgAAAA==.Rinaera:BAAANQAECgUICwAAAA==.',
Ro='Roahr:BAAANQADCgUIBAAAAA==.Rollinsmacks:BAAANQADCgIIAgAAAA==.Rollsforham:BAAANQADCggIFgAAAA==.Rondali:BAAANQADCggICAAAAA==.Rotheris:BAAANQAECgUJEwAAAA==.Rottentreats:BAAANQADCgYJCQABNQAECgQJCQAFAAAAAA==.Rottie:BAABNQAECoEdAAMIAAkKMh3kIgCcAgAIAAgKGh7kIgCcAgAWAAQKXxbPKAANAQAAAA==.',
Rs='Rski:BAAANQAECgEJAgAAAA==.',
Rt='Rts:BAABNQAECoEmAAIVAAkKhCXiAgDXAwAVAAkKhCXiAgDXAwAAAA==.',
Ru='Rufio:BAABNQAECoEfAAIHAAkKQSPPBQB2AwAHAAkKQSPPBQB2AwAAAA==.Rufiu:BAAANQAECgYIEAAAAA==.',
Ry='Ryjaxqt:BAAANQAECgIIAgAAAA==.Ryogen:BAABNQAECoEfAAMeAAkKpRzNBQD9AgAeAAkKpRzNBQD9AgAiAAIK5RJEPAB5AAAAAA==.',
['Ré']='Rén:BAAANQAECgIIAgAAAA==.',
Sa='Saarahkin:BAAANQAECgEJAQAAAA==.Sablewhisper:BAAANQAECgQJCQAAAA==.Sabryel:BAABNQAECoEgAAIUAAcKFxozQgAvAgAUAAcKFxozQgAvAgAAAA==.Saintvyn:BAABNQAECoElAAMTAAkKISA+CwArAwATAAkKISA+CwArAwAaAAMKWQ0cFAB4AAAAAA==.Salmonroll:BAAANQAECgUICwAAAA==.Salos:BAAANQADCgYIBgAAAA==.Salvation:BAAANQAECgEJAQAAAA==.Samael:BAAANQADCgUIBgAAAA==.Sandarah:BAABNQAECoEbAAMBAAkKRCGcBQB7AwABAAkKRCGcBQB7AwAhAAUKqhdMHgBkAQABNQAFFAcIEgATAMseAA==.Sapling:BAAANQAECgYJDwAAAA==.Sathic:BAAANQAECgYIDQAAAA==.Satreser:BAAANQAECgUJCQAAAA==.Satyra:BAAANQADCgQIBAAAAA==.',
Sc='Scallywrath:BAAANQAECgIIAgAAAA==.Scaretale:BAAANQADCgQIBgAAAA==.Scribbles:BAABNQAECoEkAAMcAAkK2COLAgClAwAcAAkK2COLAgClAwATAAEKBAxrpwA9AAAAAA==.Scribblesz:BAAANQADCgYIBgAAAA==.Scòtt:BAAANQADCgUIBQAAAA==.',
Se='Seanthepally:BAAANQAECgQIBQABNQAECgkJHgACAFcbAA==.Seantheshamm:BAABNQAECoEeAAMCAAkKVxuVFwDLAgACAAkKVxuVFwDLAgADAAEKMQW96AAsAAAAAA==.Secihots:BAABNQAECoEfAAMOAAkKDx6SBABHAwAOAAkKDx6SBABHAwANAAQKDRkfUAAWAQAAAA==.Secretaznman:BAAANQAECgIJAgAAAA==.Seidhkona:BAAANQADCgYIBgABNQAECgcJEgAFAAAAAA==.Seiko:BAAANQADCgYJBgAAAA==.Seishirou:BAAANQADCggICAABNQAECgcJDwAFAAAAAA==.Serialheal:BAAANQAECgQIBwABNQAECgYJEQAFAAAAAA==.Sevalynn:BAAANQADCggIEAAAAA==.',
Sh='Shadalune:BAABNQAECoEkAAMUAAkKPSMBEQAbAwAUAAkKLiIBEQAbAwAPAAcKzyKWDwCxAgAAAA==.Shamanelion:BAABNQAECoEZAAMCAAkKIB0rEgD1AgACAAkKIB0rEgD1AgADAAEKiAqF4wAvAAABNQAFFAEIAQAFAAAAAA==.Shamnobi:BAAANQADCgQIBAAAAA==.Shampai:BAAANQADCgIJAgAAAA==.Shazza:BAAANQADCgcJCQAAAA==.Shinso:BAAANQAFFAMJAgAAAA==.Shiwang:BAAANQAECgcJEgAAAA==.Shockazuwu:BAABNQAECoEfAAMCAAkKuhI1NgAaAgACAAkKuhI1NgAaAgADAAQKKxvlcgA8AQAAAA==.Shocktagon:BAAANQADCgEIAQAAAA==.Shocktherapy:BAAANQAECgEIAQAAAA==.Shocktroopz:BAAANQADCgIIAgAAAA==.Shockzilla:BAAANQAECgMIAwAAAA==.Shockér:BAAANQAECgQJCQAAAA==.Shodoroki:BAAANQAECgcJDwAAAA==.Shogunhanzo:BAAANQADCgUJBQAAAA==.Shuu:BAAANQAECgYJEgAAAA==.Shwoidlord:BAAANQAECgQICAABNQAECgkJHwACALoSAA==.Shwoop:BAAANQAECgQIBAABNQAECgkJHwACALoSAA==.',
Si='Sigurrose:BAAANQAECgUIDQAAAA==.Silëntshøt:BAAANQADCgEJAQAAAA==.',
Sk='Skitzosvnff:BAAANQAECgcIEQAAAA==.Skrai:BAAANQADCggIBgAAAA==.',
Sm='Smetrios:BAAANQADCggIEAABNQAECgcJEgAFAAAAAA==.Smokedh:BAAANQAECgUIDAABNQAECgkJHAAQAO8bAA==.Smokezug:BAABNQAECoEcAAIQAAkK7xukJgDWAgAQAAkK7xukJgDWAgAAAA==.',
Sn='Snorter:BAAANQADCggIDQAAAA==.Snowfury:BAAANQAFFAIIAgAAAA==.Snowlock:BAAANQADCgYIEAAAAA==.Snowrain:BAABNQAECoEcAAIRAAkK3SBDCgBAAwARAAkK3SBDCgBAAwAAAA==.',
So='Solamina:BAAANQADCgYICAAAAA==.Sotek:BAAANQABCgIIAgAAAA==.Soulster:BAAANQADCgEIAQAAAA==.Sourdeath:BAAANQAECgUICwAAAA==.',
Sp='Spinningbrew:BAAANQAECgQIBwAAAA==.Spinseason:BAAANQADCgMIAwAAAA==.Spirittide:BAAANQABCgIIAgAAAA==.Spit:BAAANQAECgEIAQAAAA==.',
Sr='Srf:BAAANQAECgQIBAABNQAFFAQIDAAFAAAAAA==.',
Ss='Ssnoosnoo:BAAANQAECgQIBgAAAA==.',
St='Stanchion:BAAANQADCgUJCAAAAA==.Steelmessiah:BAAANQADCgcJCAAAAA==.Stinko:BAAANQAECgIIAQABNQAFFAYJCwAXAOEVAA==.Stonecrusade:BAAANQAECgQJCAAAAA==.Stonedhokage:BAABNQAECoEeAAIUAAkKLBpoIAC6AgAUAAkKLBpoIAC6AgAAAA==.Stopthebleed:BAAANQADCggIDwAAAA==.Sturdy:BAAANQADCgYJBgAAAA==.Sty:BAACNQAFFIEKAAIKAAUKWxH3AwCRAQAKAAUKWxH3AwCRAQA1AAQKgSMAAwoACQqDItAFAGgDAAoACQpXItAFAGgDAAsACAqMGfkZADkCAAAA.Ståb:BAAANQADCgYIBgABNQAECggIHAAVAHARAA==.Stårr:BAAANQADCgYJBwAAAA==.',
Su='Suffering:BAAANQADCgYJEQAAAA==.Suicideblond:BAAANQADCggJIgAAAA==.Supadrac:BAABNQAECoEhAAIXAAkKxhpxCADoAgAXAAkKxhpxCADoAgAAAA==.Surfnturf:BAAANQAFFAQIDAAAAQ==.Surging:BAAANQAECgUJEQAAAA==.Suri:BAAANQAECgIIAgABNQAECggJFwAVAJ8QAA==.Surii:BAABNQAECoEXAAIVAAgKnxCLgwAOAgAVAAgKnxCLgwAOAgAAAA==.',
Sw='Swaazz:BAABNQAECoEgAAIXAAcK0BJmGADGAQAXAAcK0BJmGADGAQAAAA==.Swampypants:BAAANQAECgUIBQAAAA==.Swerve:BAAANQAECgMIBAAAAA==.Swinybswipen:BAAANQAECggIAgAAAA==.',
Sy='Sycorex:BAAANQADCgEJAQAAAA==.Sykocious:BAABNQAECoEbAAIgAAgKuhAnEgApAgAgAAgKuhAnEgApAgAAAA==.Sylleria:BAAANQAECgIIAwAAAA==.Syllia:BAAANQAECggJDgABNQAECgkJGwAQANkiAA==.Syngatesx:BAAANQADCggIAQAAAA==.Syphilia:BAABNQAECoEbAAILAAkKYxPlFAB4AgALAAkKYxPlFAB4AgAAAA==.',
Sz='Szeto:BAAANQAECgYIDAABNQAFFAUICAALAG4KAA==.',
['Sè']='Sèanthewarr:BAAANQAECgIIAgABNQAECgkJHgACAFcbAA==.',
Ta='Tacocát:BAAANQAECgIJBQABNQAFFAMJCwARAL8gAA==.Tacosback:BAAANQADCgEIAQABNQAFFAMJCwARAL8gAA==.Tacosdk:BAACNQAFFIELAAIRAAMKvyBsBAAyAQARAAMKvyBsBAAyAQA1AAQKgRQAAhEACApXJCAJAFEDABEACApXJCAJAFEDAAAA.Tacosneak:BAAANQAECgYICgABNQAFFAMJCwARAL8gAA==.Talonarayan:BAAANQADCggIIAAAAA==.Tanksinatra:BAAANQAECgIIAgABNQAECgYIAwAFAAAAAA==.Taote:BAAANQABCgIIAgAAAA==.',
Te='Teebonez:BAAANQAECgUJBwAAAA==.Teesdays:BAAANQABCgYJDwAAAA==.Tefiti:BAAANQADCgcIBwAAAA==.Tetrâ:BAAANQADCgYIBgAAAA==.Tewasha:BAABNQAECoEdAAIjAAgKiB4oBQC3AgAjAAgKiB4oBQC3AgAAAA==.',
Th='Thalryn:BAAANQADCgMIAwAAAA==.Thaylen:BAAANQADCgYIBQAAAA==.Thedoofy:BAAANQAECgEJAgAAAA==.Thiccmage:BAAANQAECgYIDAABNQAECgkJHwALAFkhAA==.Thorskin:BAAANQADCgUIBQAAAA==.Threellamas:BAAANQAFFAEJAQAAAA==.Thuggèr:BAAANQADCgcICwAAAA==.Thunderchub:BAAANQAECgQIBAAAAA==.Thunderx:BAAANQAECgQIBAAAAA==.Thuringwethl:BAAANQADCggIGAABNQAECgEIAQAFAAAAAA==.',
Ti='Tidyswet:BAAANQADCgYIBgABNQAECgQJBQAFAAAAAA==.Tinydonny:BAAANQADCgQIBQAAAA==.',
To='Tokyø:BAAANQADCgEIAQAAAA==.Tonylildik:BAAANQAECgEIAQABNQAFFAMJBQAVAC0YAA==.Toolh:BAAANQADCgUIBQAAAA==.Toopac:BAEBNQAECoEnAAQPAAkKoiOSAwCGAwAPAAkKESOSAwCGAwAUAAMKUR5/uQDiAAAdAAMKbBkOCgDBAAAAAA==.Totö:BAAANQAECgUIEQAAAA==.',
Tr='Tramana:BAABNQAECoEZAAIZAAgKDxnJCACZAgAZAAgKDxnJCACZAgAAAA==.Trashxbin:BAAANQADCgUIBQAAAA==.Trauk:BAAANQAFFAEIAQAAAA==.Triggéred:BAAANQAECgQIBwAAAA==.Triig:BAAANQAECgQJCgAAAA==.Trollcopter:BAAANQAECgMJBAABNQAECgYIDAAFAAAAAA==.Trollreroll:BAAANQADCgIIAgAAAA==.Trollwíthbow:BAAANQAECgQICAAAAA==.Truzxz:BAAANQADCgYJBgABNQAECgcJDwAFAAAAAA==.Trytip:BAEANQADCgcJBwABNQAECgUIBQAFAAAAAA==.',
Tu='Turr:BAAANQAECgEJAQAAAA==.',
Tw='Tweedledumb:BAAANQAECgQICgAAAA==.Twìnky:BAABNQAECoElAAMZAAkKPSDdAgBTAwAZAAkKPSDdAgBTAwACAAIKIAbyugBnAAAAAA==.',
Ul='Ulfric:BAAANQADCgIIAgAAAA==.',
Un='Unbreakkable:BAAANQAECgcJBwABNQAECgkJGgAEAPsbAA==.Unclepete:BAAANQAECgYIDAAAAA==.Unstobubble:BAAANQABCgIIAgAAAA==.',
Ur='Urouge:BAAANQAECgUIBQABNQAFFAUICAALAG4KAA==.',
Va='Vacula:BAAANQAECgUIDAAAAA==.Vaelyriana:BAAANQAECgQICAAAAA==.Valreaux:BAAANQAECgUIDgAAAA==.Vandalism:BAAANQADCggJGgAAAA==.Vanian:BAAANQADCgUIBgAAAA==.Vanquìshh:BAAANQADCgUIBQAAAA==.',
Vd='Vdyr:BAAANQAECgMJBQAAAA==.',
Ve='Velarayna:BAAANQAECgEJAQABNQAECgkKHgARAJUkAA==.Vex:BAAANQABCgMIAwAAAA==.',
Vi='Vilgefortz:BAAANQAECgYJEQAAAA==.Vivelf:BAAANQADCggJAQAAAA==.',
Vo='Voidborn:BAAANQAECgYIEgAAAA==.Voidling:BAAANQAECgIIAwAAAA==.Voidturned:BAAANQADCgQIBAAAAA==.Vortexis:BAAANQAECgYJDAAAAA==.',
Vu='Vulpurra:BAAANQAECgUICgAAAA==.Vurm:BAABNQAECoEeAAIQAAgKFiPaLAC4AgAQAAgKFiPaLAC4AgAAAA==.',
Vy='Vytamin:BAAANQAECgQIBQAAAA==.',
['Vâ']='Vâlinoth:BAAANQAECgYIDgAAAA==.',
['Vó']='Vólkan:BAAANQADCgcIGQAAAA==.',
Wa='Walkinghealz:BAAANQADCgQIBQABNQAECgYIDAAFAAAAAA==.',
We='Weiss:BAAANQADCggICAAAAA==.Wengo:BAAANQADCgIIBAAAAA==.',
Wh='Whistlejinky:BAAANQADCgQIBAAAAA==.',
Wi='Willywonkie:BAAANQADCgQIBgAAAA==.Winbot:BAAANQAECgQJBgABNQAFFAUJCgAiAHwaAA==.Windfrey:BAAANQAECgUIBwAAAA==.Windsong:BAAANQADCgUIBQAAAA==.Winghollow:BAAANQADCgIIAgAAAA==.Wintershock:BAAANQAECgcIEQAAAA==.Wisk:BAAANQAECggJDgAAAA==.',
Wl='Wll:BAAANQAECgQIBgABNQAECgkJHQARAAceAA==.Wlx:BAABNQAECoEdAAMRAAkKBx7LGgCRAgARAAkKVxvLGgCRAgASAAcKYh2pGwAkAgAAAA==.',
Wo='Wobs:BAABNQAECoEcAAITAAkKjiMtBwBYAwATAAkKjiMtBwBYAwAAAA==.Woopoles:BAAANQADCggJHAAAAA==.',
Wr='Wredgeek:BAAANQAECgQIBAAAAA==.',
Wy='Wy:BAAANQAECgUICAAAAA==.',
Xa='Xavierboí:BAAANQAECgYIDwAAAA==.',
Xi='Xileon:BAAANQAECgUICwAAAA==.',
Xo='Xombie:BAAANQADCgUIBQAAAA==.',
Ya='Yabishus:BAAANQAECgUIBgAAAA==.Yahboibangz:BAAANQAECgQJBQAAAA==.Yamajin:BAAANQADCgIIAgAAAA==.',
Yc='Ycetz:BAAANQADCgYJCgABNQAECgQIDQAFAAAAAA==.',
Ye='Yelacsa:BAAANQAECgMIBQABNQAECgkJHwACALoSAA==.',
Yi='Yinan:BAAANQAECggICgAAAA==.',
Yo='Yoshu:BAAANQAECgYJEAAAAA==.',
Yu='Yukyukyuk:BAAANQABCgQIBAAAAA==.',
Za='Zalarax:BAAANQAECggIEAAAAA==.Zalaraxe:BAAANQAECggJCAAAAA==.Zanthu:BAEANQADCgYIBgABNQAECgkJJwAPAKIjAA==.Zanu:BAAANQADCgYICwAAAA==.Zardon:BAAANQADCgYIBgABNQAECgkJJQAGAKYlAA==.',
Ze='Zecar:BAAANQADCgUJBQAAAA==.Zengard:BAAANQADCggIDgAAAA==.Zenkic:BAAANQADCgEIAQAAAA==.Zenlock:BAAANQADCgYIBgABNQAECgcJDQAFAAAAAA==.',
Zi='Zivzs:BAAANQADCgYJCAAAAA==.Zivá:BAAANQABCgYJCAAAAA==.',
Zo='Zoralari:BAAANQAECgcJEwAAAA==.Zorke:BAAANQAECgYIEAAAAA==.',
Zu='Zulnas:BAAANQAECgcJEgAAAA==.',
['Ön']='Önonta:BAAANQAECgIJAgAAAA==.Önotoes:BAAANQAECgUICwAAAA==.',
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
