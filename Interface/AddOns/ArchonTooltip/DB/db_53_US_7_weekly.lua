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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Druid-Restoration','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Mage-Arcane','Warrior-Arms','Warrior-Fury','Druid-Balance','Mage-Frost','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Paladin-Retribution','Warrior-Protection','Shaman-Elemental','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Restoration','Warlock-Demonology','Rogue-Assassination','Monk-Mistweaver','Monk-Windwalker','Hunter-Marksmanship','Warlock-Destruction','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Survival','Evoker-Preservation','Druid-Feral','Druid-Guardian',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abnalem:BAAANQADCgIIAgAAAA==.',
Ad='Adramalech:BAAANQADCgQIBAABNQAFFAUIDAABAC0gAA==.',
Ae='Aeakos:BAAANQAECgIIAwABNQAECgcIFwACADUOAA==.Aeldon:BAAANQADCggIEAAAAA==.',
Ai='Aisele:BAAANQAECgYIDAAAAA==.',
Al='Alastor:BAAANQADCgcICwAAAA==.Alathir:BAAANQAECgYICAAAAA==.Alluri:BAAANQAECgcIDgAAAA==.Althemia:BAAANQADCgUIBwAAAA==.Alunamora:BAABNQAECoEcAAIDAAgKmxz9DwCcAgADAAgKmxz9DwCcAgAAAA==.Alwind:BAAANQAECgYIDwAAAA==.',
An='Analani:BAAANQADCgcJGQAAAA==.Anali:BAAANQAECgMIAwAAAA==.Angis:BAAANQADCgQICAAAAA==.Angryheals:BAAANQAECgMIAwAAAA==.Ansfrid:BAAANQADCggIDgAAAA==.',
Ap='Apøllø:BAAANQAECgcIEgAAAA==.',
Aq='Aquatofana:BAAANQAECgQICAAAAA==.',
Ar='Aranel:BAAANQADCgYIBgAAAA==.Arcamancer:BAAANQAECgIIAgAAAA==.Arinthal:BAAANQAECgIIAgAAAA==.Aroia:BAAANQAECgQIBAAAAA==.Arril:BAAANQAECgIIAwAAAA==.Artemissy:BAAANQADCgQIBgAAAA==.Artiis:BAAANQAECggICAAAAA==.',
As='Ashlieghee:BAABNQAECoEaAAIEAAgKbxziJgCTAgAEAAgKbxziJgCTAgAAAA==.Astien:BAAANQAECgEIAgAAAA==.Astralee:BAAANQADCggICAAAAA==.',
Au='Audric:BAAANQADCgYIBwAAAA==.',
Av='Avelen:BAAANQAECgYIEQAAAA==.Avha:BAAANQAECgIIAwAAAA==.Avistero:BAAANQADCgUIBwAAAA==.',
Ax='Axel:BAABNQAECoEeAAIFAAgKsh0tFwCfAgAFAAgKsh0tFwCfAgAAAA==.',
Ay='Aylden:BAABNQAECoEdAAMFAAgKZhBxLgDXAQAFAAgKZhBxLgDXAQAGAAIKsQHyUwBHAAAAAA==.Aylshm:BAAANQADCgYIFAAAAA==.Ayrene:BAAANQADCgcIBwABNQAECgQIBQAHAAAAAA==.',
Az='Azenazar:BAAANQADCgEIAQAAAA==.Azog:BAAANQAECgEIAQAAAA==.Azsharianna:BAAANQABCggIEAAAAA==.',
Ba='Bailas:BAAANQADCgcIDgAAAA==.Battousai:BAAANQADCgMIAwAAAA==.Bazileth:BAAANQADCgYIBgAAAA==.',
Be='Bearistotle:BAAANQAECgEIAQAAAA==.Beastmehr:BAAANQAECgMIBQABNQAECgkJJQAIADkgAA==.Beauregardl:BAAANQAECgEJAQAAAA==.Bellina:BAAANQADCgcIBwAAAA==.Belwyn:BAAANQADCgUIBgAAAA==.Benjofamin:BAAANQAECgYIBwAAAA==.',
Bi='Bitesize:BAEBNQAECoEjAAMJAAkKVyPjEQBfAwAJAAkKVyPjEQBfAwAKAAEK1yT5HwBmAAAAAA==.',
Bl='Blakelivly:BAEANQAECgcIEgABNQAECggIHwALAMokAA==.Blashster:BAABNQAECoElAAMIAAkKEyGZJwArAwAIAAkKEyGZJwArAwAMAAEKPxkXMgBGAAAAAA==.Blightsize:BAEANQADCgMIAwABNQAECgkJIwAJAFcjAA==.',
Bo='Bonemilker:BAACNQAFFIEMAAMBAAUKLSC8AwB9AQABAAQKtB28AwB9AQACAAMKViD7BwAeAQA1AAQKgSYAAwEACQq8JdAEAHYDAAEACQqKJdAEAHYDAAIAAwrtFkF5AMcAAAAA.Bonkdaddy:BAAANQAECggIDQAAAA==.Bopeep:BAAANQAECgcICwAAAA==.',
Br='Brandt:BAAANQABCgQICAAAAA==.Breelyssa:BAAANQADCgUJCQAAAA==.Brego:BAAANQAECgIIAgAAAA==.Brenna:BAAANQAECgMIAwABNQAECgYIDwAHAAAAAA==.Brewslèé:BAAANQABCgYIBgAAAA==.Brighter:BAABNQAECoEoAAQNAAgKgRzrGQA2AgANAAcKfhzrGQA2AgAEAAYKlxYdagB2AQAOAAYKRBELCwBgAQAAAA==.Brightsize:BAEANQAECgQIBgABNQAECgkJIwAJAFcjAA==.Broncopally:BAAANQADCgQIBAAAAA==.Brótien:BAAANQADCggICAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bunnka:BAAANQADCgYIBgAAAA==.Bunnyparade:BAAANQADCgYIBgAAAA==.',
Ca='Cakesdruid:BAAANQADCggIEAAAAA==.Caledwar:BAAANQAECgMIBwAAAA==.Calrissa:BAAANQADCgMIAwABNQAECgYICAAHAAAAAA==.Calthirstrap:BAACNQAFFIEHAAMCAAUKnRI7BwAxAQACAAQK4RM7BwAxAQAPAAEKjQ2rJwAqAAA1AAQKgSQAAgIACQoDJD0IAF4DAAIACQoDJD0IAF4DAAAA.Carare:BAAANQADCgYICgAAAA==.Carnàge:BAAANQAECgMIBgAAAA==.Casterrata:BAAANQADCggICAAAAA==.',
Ce='Ceefack:BAAANQAECgIIAgAAAA==.Cethin:BAAANQAECgEIAQAAAA==.',
Ch='Chaargee:BAAANQAECgQIBgAAAA==.Cheedar:BAACNQAFFIEHAAMQAAMKzQuBEADdAAAQAAMKzQuBEADdAAARAAEKTAB9DgAbAAA1AAQKgRwAAhAACQq8EH05AEECABAACQq8EH05AEECAAAA.Chelaria:BAAANQADCgcIDgAAAA==.Cherylindrea:BAAANQADCgMJBQAAAA==.Chillwombat:BAAANQADCggIGwAAAA==.Chumlei:BAAANQADCgcIBwAAAA==.',
Ck='Ckz:BAAANQAECgQIBAAAAA==.',
Cl='Claydemon:BAAANQAECgQIBAAAAA==.Clayvicar:BAABNQAECoEnAAMEAAgKpAxnawBxAQAEAAcKTw1nawBxAQANAAIKVgM7UwBgAAAAAA==.',
Co='Coridane:BAAANQAECgQICgAAAA==.Corwinfiron:BAAANQAECgYIEAAAAA==.',
Cr='Crosse:BAAANQAECgQIBAAAAA==.Cruellà:BAAANQADCgYIEwAAAA==.Cryptcrawler:BAAANQAECgEIAgAAAA==.',
Cu='Curkage:BAAANQADCgIIAgAAAA==.',
Cy='Cythera:BAACNQAFFIEHAAISAAMKcxd9AgAKAQASAAMKcxd9AgAKAQA1AAQKgSgAAhIACQofJZsBAJgDABIACQofJZsBAJgDAAAA.',
['Cá']='Cámus:BAAANQAECgUIEAAAAA==.',
Da='Daammy:BAAANQADCgcIHgAAAA==.Daayumgurl:BAAANQADCgYIBgAAAA==.Dagren:BAAANQADCggIGwAAAA==.Daisy:BAAANQABCggIHQABNQABCggIHgAHAAAAAA==.Dakdor:BAAANQADCgMIAwAAAA==.Daphine:BAAANQADCgQIBgAAAA==.Darimonk:BAAANQADCgEIAQABNQADCgYICgAHAAAAAA==.Darivara:BAAANQADCgYICgAAAA==.Darkbeautie:BAAANQAECgQIBQAAAA==.Darkcarbon:BAAANQAECgIIBAAAAA==.Darkplazzma:BAAANQAECgEIAQAAAA==.Darmin:BAAANQABCgQIBAAAAA==.',
De='Deathmask:BAAANQAECgEIAQAAAA==.Deathspal:BAABNQAECoEhAAMTAAcKrxM1iQCrAQATAAcKrxM1iQCrAQARAAIKpQjBTgBOAAAAAA==.Dessembrae:BAABNQAECoEoAAIUAAgKUiT9AgBBAwAUAAgKUiT9AgBBAwAAAA==.Dewkiez:BAEBNQAECoEYAAIVAAkKkiXDCQCGAwAVAAkKkiXDCQCGAwAAAA==.',
Di='Diabolicarl:BAABNQAECoEZAAIFAAgKkQoKNACrAQAFAAgKkQoKNACrAQAAAA==.Diri:BAAANQADCggICAABNQAECgkJHwAWAKoLAA==.',
Dm='Dmmeforpi:BAAANQADCgYICgAAAA==.',
Do='Docphanan:BAAANQAECgEIAgAAAA==.Doesntheal:BAAANQABCgIIAgAAAA==.Dookiez:BAEANQAECgYICQABNQAECgkJGAAVAJIlAA==.Doubledragin:BAABNQAECoEbAAMXAAcK6RSjEwDSAQAXAAcKmxSjEwDSAQAYAAQKxhQAEADcAAAAAA==.',
Dr='Dracantar:BAAANQADCgcICAAAAA==.Dractini:BAAANQADCgcICgABNQAECgkJJwAZAK4SAA==.Dragfan:BAAANQADCgQJBAAAAA==.Dragonbelly:BAAANQABCggIHgAAAA==.Dragondeez:BAAANQABCgQIBAABNQADCggIJgAHAAAAAA==.Dragore:BAAANQAECgUIDAAAAA==.Druidgirls:BAABNQAECoErAAIDAAkKhxiLDwCjAgADAAkKhxiLDwCjAgAAAA==.',
Du='Duelist:BAAANQAECgEIAQAAAA==.Dupree:BAAANQADCgIIAgAAAA==.Durogdem:BAAANQADCgYIBgAAAA==.Duskfire:BAAANQABCgQIBAAAAA==.',
Ea='Earthaggie:BAAANQADCgQICQAAAA==.',
Ec='Echlipse:BAAANQAECgQIBAABNQAECgcIFwARAK8hAA==.',
Ed='Ederon:BAAANQABCggICAAAAA==.Edirae:BAAANQAECgIIAgAAAA==.',
El='Elenora:BAAANQAECgYIDAAAAA==.Ellesmere:BAAANQADCggIEAABNQAFFAgIGgAQALEbAA==.Elye:BAAANQAECgUIBgAAAA==.',
Em='Emer:BAAANQAECgYICgAAAA==.Emiru:BAAANQADCgUJBgAAAA==.',
En='Encore:BAABNQAECoEoAAIDAAgK1AvbJACaAQADAAgK1AvbJACaAQAAAA==.',
Eo='Eousphorus:BAABNQAECoEoAAMIAAkK+hnfPADtAgAIAAkK+hnfPADtAgAMAAIK/QiYKgBiAAAAAA==.',
Er='Erathen:BAAANQADCggICgAAAA==.Eryanna:BAAANQADCgEIAQAAAA==.',
Es='Esplan:BAEANQAECgcICgABNQAECggIHwALAMokAA==.',
Eu='Euden:BAAANQADCgQIBAAAAA==.',
Ev='Evelleion:BAAANQAECgMIAwAAAA==.',
Ex='Exoticlord:BAAANQAECgQIBAAAAA==.',
Fe='Felhayde:BAAANQADCgYIBgAAAA==.Fenryyr:BAAANQADCgYJBwAAAA==.',
Fi='Fierygrace:BAAANQADCgcIEAAAAA==.Firburger:BAAANQAECgQIBgAAAA==.Fischl:BAAANQADCggIKAAAAA==.',
Fl='Flameth:BAABNQAECoEmAAIaAAgKrBBlWQD9AQAaAAgKrBBlWQD9AQAAAA==.Flirtywombat:BAAANQAECgEIAQAAAA==.',
Fr='Freezrorburn:BAAANQADCgYIBwAAAA==.',
Fu='Fujitto:BAAANQADCgIIAgAAAA==.Fumanchu:BAABNQAECoEaAAIUAAgKjBtmCQBjAgAUAAgKjBtmCQBjAgAAAA==.Fuzugchu:BAAANQADCgUIBQABNQAECggIGgAUAIwbAA==.',
Ga='Gaamora:BAAANQADCgQICgAAAA==.Gainsborough:BAABNQAECoEhAAMTAAkKwh44KgDkAgATAAgKiiA4KgDkAgARAAEKexCtVAA6AAABNQAFFAUIDgAZAHYVAA==.Garagos:BAABNQAECoEoAAIbAAgK1RhBGwBPAgAbAAgK1RhBGwBPAgAAAA==.',
Ge='Gebuss:BAABNQAECoEjAAIbAAkKtCL2AwBzAwAbAAkKtCL2AwBzAwAAAA==.',
Gl='Glenraven:BAAANQAECgEIAQAAAA==.',
Go='Golokan:BAAANQADCgYIDAAAAA==.Goochaddi:BAABNQAECoEYAAITAAkKoByrTQBcAgATAAkKoByrTQBcAgAAAA==.Gorgunga:BAAANQAECgUIBQAAAA==.Gozer:BAAANQABCgcICQAAAA==.',
Gr='Grolden:BAAANQADCgIIAgAAAA==.Grïpnrïp:BAAANQAECgEIAQAAAA==.',
Gu='Gunnerrata:BAAANQADCgcIBwAAAA==.',
Ha='Halifaxx:BAABNQAECoEnAAIIAAgKJRvgWwCbAgAIAAgKJRvgWwCbAgAAAA==.Halifour:BAAANQADCgIIAgAAAA==.Halithree:BAAANQADCgYIBgAAAA==.Halitwo:BAAANQADCggICAAAAA==.Haraboo:BAAANQAECgUIBQAAAA==.Harmaa:BAAANQAECgYICAAAAA==.Havengul:BAAANQAECggICAAAAA==.Hawknor:BAAANQAECgIIAwAAAA==.',
He='Healthcare:BAABNQAECoEnAAMZAAkKrhLVPAAjAgAZAAkKrhLVPAAjAgAVAAUKbw3omAAQAQAAAA==.Healthplan:BAAANQADCgYIBgABNQAECgcIGQAQANcVAA==.Heartilly:BAACNQAFFIEOAAIZAAUKdhVGBwCYAQAZAAUKdhVGBwCYAQA1AAQKgSoAAhkACQq2HagbAM0CABkACQq2HagbAM0CAAAA.Herm:BAABNQAECoEuAAMcAAgKoyXWAwBNAwAcAAgKoyXWAwBNAwAdAAUKZB6tIwCqAQAAAA==.',
Ho='Holyfu:BAAANQAECgUIDAABNQAECggIGgAUAIwbAA==.Holymidget:BAAANQAECgEJAQAAAA==.Holysky:BAAANQAECgIIBAAAAA==.Holytim:BAABNQAECoEcAAQEAAgK+B6CJwCQAgAEAAgKtxyCJwCQAgAOAAYK5hYZCACzAQANAAIKdArrUQBmAAAAAA==.Honeypackz:BAAANQAECgIIAgAAAA==.Honnik:BAAANQABCgIIAgAAAA==.Hotpink:BAAANQADCgQICAAAAA==.How:BAABNQAECoEcAAMcAAkK7B8YBQAoAwAcAAkK7B8YBQAoAwAdAAIKAA6xRwByAAAAAA==.',
Hu='Humongulus:BAAANQAECgYIDAAAAA==.',
Ig='Ignored:BAAANQAECgMIBAAAAA==.Ignöred:BAABNQAECoEZAAIJAAcKSBiEaQAJAgAJAAcKSBiEaQAJAgAAAA==.',
Il='Illaine:BAAANQADCgYIBgAAAA==.Illidæn:BAABNQAECoEWAAIGAAcKTAdOMgBrAQAGAAcKTAdOMgBrAQAAAA==.',
Im='Imos:BAAANQABCgQIBAAAAA==.Imperîus:BAAANQADCgUIBQABNQAFFAUIDAABAC0gAA==.',
In='Inaniel:BAAANQAECgUIDwAAAA==.Inq:BAABNQAECoEjAAMIAAgKpB+zQgDdAgAIAAgKpB+zQgDdAgAMAAEKLguAPQAuAAAAAA==.',
Ir='Iridaceaë:BAAANQAECgcIEgABNQAECgIIAgAHAAAAAA==.Iryris:BAAANQAECgMIBwAAAA==.',
Is='Isedeath:BAABNQAECoEoAAQCAAgKORNoPgDAAQACAAgKehFoPgDAAQABAAgKdQtaOACDAQAPAAEKOB2GogBIAAAAAA==.Istvankh:BAAANQABCgMIBAABNQADCgEIAQAHAAAAAA==.',
Ja='Jaholin:BAAANQAECgIIAgAAAA==.Jarhead:BAAANQADCgIIAgAAAA==.Jarrhead:BAAANQAECgIIAgAAAA==.Jaxarus:BAAANQADCgEIAQAAAA==.',
Je='Jenaveive:BAAANQAECgcIEgAAAA==.Jethoisi:BAAANQAECgYIEAABNQAFFAIIAwAHAAAAAA==.Jexi:BAAANQADCgYJBgABNQAECgQIBQAHAAAAAA==.',
Jn='Jnex:BAAANQAECgcIDAAAAA==.',
Jo='Jongani:BAAANQAFFAIIAwAAAA==.Jookiez:BAEANQAECgYIBwABNQAECgkJGAAVAJIlAA==.',
Jr='Jrrtrolkien:BAAANQADCgQIBAABNQAECgEIAgAHAAAAAA==.',
Ju='Judgemehr:BAAANQAECgQIBQABNQAECgkJJQAIADkgAA==.Judgepain:BAAANQAECggICAAAAA==.Judgmental:BAABNQAECoEdAAIQAAgKnh/QGQDkAgAQAAgKnh/QGQDkAgAAAA==.',
Ka='Kaelysong:BAAANQADCgUJDQAAAA==.Kairah:BAAANQADCgcIEAAAAA==.Kaivig:BAAANQADCgYIBgAAAA==.Kalï:BAAANQADCgYICQAAAA==.Karlil:BAAANQAECgQIDAAAAA==.Kasiene:BAAANQADCgcIFwAAAA==.Kasnay:BAAANQADCgQIBgAAAA==.Kathenset:BAAANQAECgUICAAAAA==.Kazenseth:BAAANQABCggIFQAAAA==.Kazeral:BAAANQAFFAIIAwAAAA==.Kazzi:BAAANQADCgIIAgAAAA==.',
Ke='Keener:BAAANQAECgUIDAAAAA==.Kelvin:BAAANQABCgQIBAAAAA==.Kelyana:BAAANQABCgMIAwAAAA==.Kerrla:BAAANQAECgEIAQABNQAFFAIIAwAHAAAAAA==.Keylleth:BAAANQADCgYJDwAAAA==.',
Kh='Khalanie:BAAANQAECgYIEgAAAA==.Khamnox:BAAANQAECgUIBgAAAA==.Khionia:BAAANQAECgIIAgAAAA==.',
Ki='Kidthefrist:BAAANQADCgUIBQAAAA==.Kielnmsoftly:BAAANQADCgYIBgAAAA==.Kilaia:BAAANQAECgEIAgAAAA==.Kirru:BAAANQAECgQIBAAAAA==.',
Kn='Knoble:BAAANQADCgQIBAAAAA==.',
Ko='Kokatoes:BAAANQAECgIIAgABNQAECgYIEwAHAAAAAA==.Korabas:BAAANQADCggICAABNQAECggIKAAUAFIkAA==.',
Kr='Kreaton:BAAANQAECgcICwAAAA==.Kryt:BAABNQAECoEdAAIZAAcKRiATLQBtAgAZAAcKRiATLQBtAgAAAA==.',
Ku='Kuponia:BAAANQABCgIIAgAAAA==.',
Kw='Kwichangpain:BAAANQADCgcIDQAAAA==.',
Kx='Kxchiki:BAABNQAECoEYAAIQAAgKKArNYACoAQAQAAgKKArNYACoAQAAAA==.',
['Kã']='Kãz:BAAANQADCgYICAAAAA==.',
La='Laaklem:BAAANQAECgEJAQAAAA==.Laei:BAAANQADCggIEAAAAA==.Laserfingies:BAAANQADCgcIDwAAAA==.Lastsun:BAAANQADCgIIAgAAAA==.Lavacakes:BAABNQAECoEpAAMZAAgKbyDSIQCqAgAZAAgKbyDSIQCqAgAVAAIKZwaf4QBdAAAAAA==.Lawndartz:BAAANQADCggJDgAAAA==.',
Le='Lelantoz:BAAANQAECgYIDwAAAA==.Leliel:BAAANQABCgUICAAAAA==.Leqoofus:BAAANQADCgIIAgABNQADCgcIDwAHAAAAAA==.',
Li='Lidan:BAAANQAECgUIDAAAAA==.Liebli:BAAANQAECgQIBQAAAA==.Liltank:BAAANQADCgYICQAAAA==.Limity:BAAANQAECgQIBAAAAA==.Linaradice:BAAANQAECgQIBgAAAA==.Lixandra:BAAANQADCgEIAQAAAA==.',
Lo='Logyn:BAAANQADCgQIBgAAAA==.Lonelyspark:BAAANQADCgMIBQAAAA==.Lonnias:BAAANQAECgQIBAAAAA==.Lotsalock:BAAANQADCgUIBQAAAA==.',
Lu='Lucifur:BAAANQADCgMIAwAAAA==.Luna:BAABNQAECoEZAAIDAAcKgw7qJgCFAQADAAcKgw7qJgCFAQAAAA==.Lunarluvgood:BAEBNQAECoEfAAILAAgKyiQtDABOAwALAAgKyiQtDABOAwAAAA==.',
Ly='Lyrelia:BAAANQAECgIIAwAAAA==.',
Ma='Madbones:BAAANQADCgYIDAABNQAECgcIGQAQANcVAA==.Madmetal:BAABNQAECoEZAAIQAAcK1xXTTwDnAQAQAAcK1xXTTwDnAQAAAA==.Mado:BAAANQAECgQICAAAAA==.Magicky:BAAANQADCggIJgAAAA==.Mahlkier:BAAANQADCgQIBgAAAA==.Mahlkierson:BAAANQADCgQIAwAAAA==.Maikego:BAAANQAECgQIBAAAAA==.Mairadin:BAAANQAECgIIAgAAAA==.Malchelo:BAAANQAECgQIBAAAAA==.Malfhunter:BAABNQAECoEdAAIeAAkK1xfPFgB2AgAeAAkK1xfPFgB2AgAAAA==.Malfshammy:BAAANQADCgcIBwAAAA==.Maligosa:BAAANQADCgQIBgAAAA==.Mantodea:BAAANQADCgcIFgAAAA==.Marmin:BAABNQAECoEaAAIMAAgKPRcNBwA5AgAMAAgKPRcNBwA5AgAAAA==.Marymae:BAAANQADCgMJBQAAAA==.Mattwm:BAAANQADCgEIAQAAAA==.',
Me='Meatstick:BAAANQADCgEIAQABNQADCgIIAgAHAAAAAA==.Meikai:BAAANQAECgUICAAAAA==.Melillia:BAAANQAECgEIAgAAAA==.Melted:BAACNQAFFIEGAAIIAAMKMhwKHwAPAQAIAAMKMhwKHwAPAQA1AAQKgRcAAggACQqWHMw+AOgCAAgACQqWHMw+AOgCAAAA.Merdocki:BAABNQAECoEhAAMaAAgKgSCFQABRAgAaAAcKGSCFQABRAgAfAAQKKhOUKwAMAQAAAA==.Merdra:BAABNQAECoEXAAIRAAcKryFHDgBrAgARAAcKryFHDgBrAgAAAA==.Merdre:BAABNQAECoEoAAQEAAgKOBvuNQBMAgAEAAgKYxnuNQBMAgAOAAQKLxmxDgAOAQANAAEKzAPcaAAmAAAAAA==.',
Mi='Michealhunt:BAAANQADCgIIAgAAAA==.Midory:BAAANQAECgQICQAAAA==.Midranaira:BAAANQADCgEIAQAAAA==.Milda:BAAANQAECgEIAQAAAA==.Milkymocha:BAAANQAECgQIBAAAAA==.Misscorona:BAAANQADCgcIHQAAAA==.Mistyque:BAAANQAECgQIBAAAAA==.Mithrandir:BAAANQADCgUIBAAAAA==.Mithrond:BAAANQADCgEIAQAAAA==.',
Mo='Monalea:BAAANQADCgQIBgABNQAECggIGwAFAP8TAA==.Morcant:BAAANQAECgIIAwAAAA==.Morianoley:BAAANQADCggIHAAAAA==.Morlu:BAAANQAECgQIBgAAAA==.Mortenson:BAAANQAECgQIBQAAAA==.Mortïmer:BAABNQAECoEZAAINAAgKpBaRGgAtAgANAAgKpBaRGgAtAgAAAA==.Mousee:BAAANQADCgcIGAAAAA==.',
Ms='Msdonnapally:BAAANQADCgYJFwAAAA==.',
Mu='Muffindr:BAAANQADCggICAAAAA==.',
My='Mysticmage:BAAANQAECgIIAgAAAA==.Myxian:BAEANQAECgQIBAABNQAECgkJIwAJAFcjAA==.',
['Mö']='Möñk:BAAANQADCgQIBQAAAA==.',
Na='Nala:BAAANQAECgEJAQAAAA==.Narallia:BAAANQADCgYICAAAAA==.Nargalad:BAAANQABCgQICAAAAA==.Narios:BAAANQAECgMIBQAAAA==.',
Ne='Nediem:BAAANQADCgQIBQAAAA==.Neral:BAAANQADCgMIAwAAAA==.Nexxicus:BAAANQADCgMJAwAAAA==.',
Ni='Nightmehr:BAABNQAECoElAAIIAAkKOSD0KQAkAwAIAAkKOSD0KQAkAwAAAA==.Nightshade:BAAANQADCgcIDQAAAA==.',
No='Nored:BAAANQADCgEIAQAAAA==.Nosaj:BAAANQAECgYIDQAAAA==.Nostrodomus:BAAANQADCgMJAwAAAA==.Novalee:BAAANQADCgEIAQAAAA==.',
Ny='Nyki:BAAANQADCgMIAwAAAA==.',
Od='Odlaw:BAAANQAECgMIAwAAAA==.',
Ol='Olaria:BAAANQAECgEIAQABNQAECgMIBQAHAAAAAA==.Olinax:BAABNQAECoEYAAQbAAgKhxKbKQDZAQAbAAcKPBObKQDZAQAgAAUKCBRMDQBAAQAWAAEKrQJ+SAAtAAAAAA==.',
Om='Omalmalha:BAAANQADCgQIBAAAAA==.',
On='Onedruidtion:BAAANQADCggIEgAAAA==.',
Or='Orheo:BAAANQADCgcICQAAAA==.Orionmoon:BAABNQAECoEcAAMEAAgKDg9LUQDXAQAEAAgKDg9LUQDXAQANAAYKLgeoOAAMAQAAAA==.Orlos:BAAANQAECgMIBQAAAA==.Oräkk:BAABNQAECoEgAAIUAAgK+CLtAwAUAwAUAAgK+CLtAwAUAwAAAA==.',
Pa='Padrin:BAAANQAECgQIBQAAAA==.Pandapaws:BAABNQAECoEoAAMZAAkKZyTRAwCZAwAZAAkKZyTRAwCZAwAVAAMKiQcryACeAAAAAA==.Papaflask:BAAANQAECgQICQAAAA==.Parthal:BAAANQADCgEIAQAAAA==.Partyhardly:BAABNQAECoEaAAIRAAgKLBRGGQDTAQARAAgKLBRGGQDTAQAAAA==.Pavle:BAAANQAECgIJAgAAAA==.',
Pd='Pdiddi:BAAANQAECgUIBgAAAA==.',
Pe='Pellaeon:BAABNQAECoEmAAMPAAkKnxjCJwBJAgAPAAkKLBXCJwBJAgACAAgKjhb0MAAPAgAAAA==.Pelt:BAABNQAECoEkAAIGAAgKyRdlGgBQAgAGAAgKyRdlGgBQAgAAAA==.Perseus:BAAANQADCggICAABNQAECgQIBQAHAAAAAA==.Petmasta:BAAANQABCgEIAQABNQABCgQIBAAHAAAAAA==.',
Ph='Pharaun:BAAANQADCggIGAABNQAECggIIwACAIoGAA==.Phlan:BAEANQAECgQIBAAAAA==.Phrostir:BAAANQAECggIEAAAAA==.',
Pi='Picklechips:BAAANQADCgEIAQAAAA==.Pillgrimm:BAAANQAECgQICAAAAA==.Pillsburyman:BAAANQAECgIIAwAAAA==.',
Po='Pointee:BAAANQADCgYICgAAAA==.Poisson:BAABNQAECoEfAAIWAAkKqgusFAAeAgAWAAkKqgusFAAeAgAAAA==.Pokoxo:BAABNQAECoEfAAMRAAgK+BujDQB3AgARAAgK+BujDQB3AgAQAAEKGQZB9gArAAABNQAECgIIAwAHAAAAAA==.Pookiez:BAEANQAECgEIAgABNQAECgkJGAAVAJIlAA==.',
Pr='Prancine:BAAANQAECgQIBAABNQAECgkJJwAZAK4SAA==.Prescess:BAAANQADCgMJAwAAAA==.Providence:BAABNQAECoEiAAIFAAkKmR/+EADjAgAFAAkKmR/+EADjAgAAAA==.Prsr:BAAANQAECgMIBgABNQAFFAUIDAABAC0gAA==.',
Pu='Pudgypaws:BAAANQAECgQJBwAAAA==.Punishment:BAAANQABCgIIAgABNQADCggIJgAHAAAAAA==.',
Qu='Quickmend:BAAANQAECgQIBAAAAA==.Quickpal:BAAANQAECgYICgAAAA==.Quickpaw:BAABNQAECoEeAAIcAAkKYxv0CQC4AgAcAAkKYxv0CQC4AgAAAA==.',
Ra='Raccoons:BAAANQADCgMIAwABNQAFFAMIBwAaACUIAA==.Radell:BAAANQAECgQIBAAAAA==.Rageproof:BAAANQAECgEIAgAAAA==.Ragged:BAAANQAECggIDwAAAA==.Raidbloom:BAEBNQAFFIEIAAIDAAQKfQtCBgAvAQADAAQKfQtCBgAvAQABNQAECggIIgAQAK0VAA==.Raidshock:BAEBNQAECoEiAAIQAAgKrRVJOwA4AgAQAAgKrRVJOwA4AgAAAA==.Rainsinger:BAAANQADCgcIGQAAAA==.Ramook:BAEANQADCggIGgAAAA==.Randomchar:BAABNQAECoEoAAITAAgK9A/+dADkAQATAAgK9A/+dADkAQAAAA==.Rankor:BAAANQADCgYIBgABNQAECggIIAAYAK0QAA==.Rastann:BAABNQAECoEqAAITAAkKPiDAKgDhAgATAAkKPiDAKgDhAgAAAA==.Ratsdrack:BAAANQADCgMIAwAAAA==.Rawrlas:BAAANQADCgMIAwABNQAECgMIBQAHAAAAAA==.Razdor:BAAANQADCgUIBgAAAA==.',
Re='Reapertoo:BAACNQAFFIEJAAIBAAUKMhl2AgC0AQABAAUKMhl2AgC0AQA1AAQKgSQAAwEACQrwJKUNAPICAAEACQpqIKUNAPICAAIABgqfI+onAEgCAAAA.Recreant:BAAANQADCgcIDQAAAA==.Redbaron:BAAANQAECgcJEgAAAA==.Reetep:BAAANQADCggIGQAAAA==.Regeth:BAAANQADCggIFQAAAA==.Remily:BAAANQAECgUIBQABNQAECgkJHAAIAPkZAA==.Repuns:BAEANQAECggIAQABNQAECggIHwALAMokAA==.Revin:BAAANQAECgEJAQAAAA==.Rezalia:BAAANQADCgMIAwAAAA==.',
Ro='Rodned:BAAANQADCggJCAAAAA==.Rolas:BAAANQADCgEIAQABNQAECgMIBQAHAAAAAA==.Rondle:BAAANQADCgEIAQABNQADCgcICAAHAAAAAA==.Rottencorpse:BAAANQADCgQIBAAAAA==.Rozalin:BAABNQAECoEoAAIIAAgK4yJxLwATAwAIAAgK4yJxLwATAwAAAA==.Rozalinamoon:BAAANQADCgMIAwAAAA==.',
Ru='Rurouni:BAAANQAECgIIAgAAAA==.Rustystorm:BAAANQADCgMIAwAAAA==.Rustywarlock:BAAANQAECgEIAQAAAA==.',
Ry='Ryoshi:BAABNQAECoEdAAMhAAgK2x/AUgAoAgAhAAcKbSHAUgAoAgAiAAcKaxY8BgDnAQAAAA==.',
['Rò']='Ròòszy:BAAANQADCgYIBwAAAA==.',
Sa='Sacredstars:BAAANQAECgUIBQAAAA==.Sacredswords:BAABNQAECoEfAAMJAAkK1heCSwBpAgAJAAkK1heCSwBpAgAKAAEK0wjPKQAuAAAAAA==.Sanguinius:BAABNQAECoEeAAMQAAgKayTyCgBTAwAQAAgKayTyCgBTAwATAAIKAgXiMAFRAAAAAA==.Sapphiremist:BAAANQAECgUIBwAAAA==.Sayen:BAAANQAFFAEIAQAAAA==.',
Sc='Scachity:BAABNQAECoEXAAMaAAcKvhTtZgDSAQAaAAcKFhTtZgDSAQAfAAMKxxO2PAC6AAAAAA==.Scan:BAABNQAECoEdAAIVAAkKZRtBJAC8AgAVAAkKZRtBJAC8AgAAAA==.Schein:BAAANQAECgUIDQAAAA==.',
Se='Segsacute:BAAANQAECggICAAAAA==.Sendatu:BAAANQAECgEIAQABNQAECgcIFwACADUOAA==.Sepulchre:BAABNQAECoEjAAMCAAgKigbsXQAyAQACAAgKKwXsXQAyAQABAAYK/QSEVgDOAAAAAA==.',
Sh='Shadesfault:BAAANQADCgQICAAAAA==.Shadowhart:BAAANQADCgEIAQAAAA==.Shaeebulay:BAAANQABCgQIBAAAAA==.Shamaroo:BAAANQABCgUIBQAAAA==.Shaundakul:BAAANQAECgQIBwAAAA==.Shephion:BAAANQAECgQICwABNQAECggILgAcAKMlAA==.Shnozberries:BAAANQADCgEJAQAAAA==.Shockhart:BAAANQAECgQIBAAAAA==.Shortnstack:BAAANQAECgIIBAAAAA==.Shãdow:BAAANQADCgUIBQAAAA==.',
Si='Siegfried:BAAANQAECgQIBAAAAA==.Simori:BAAANQADCgIIAgAAAA==.Sindrel:BAAANQAECgUIBQABNQAECgkJJwAdAI8hAA==.Siyurie:BAAANQADCgcIDAAAAA==.',
Sk='Skawalker:BAABNQAECoEpAAIDAAkK1yHJBQBDAwADAAkK1yHJBQBDAwAAAA==.',
Sl='Slaed:BAAANQADCgYIBwAAAA==.Slaynne:BAAANQAECgcJEwAAAA==.',
Sm='Smoky:BAAANQAECgUIBQAAAA==.Smäug:BAACNQAFFIEKAAIXAAUKIxtyAgC7AQAXAAUKIxtyAgC7AQA1AAQKgSEAAxcACQq3IrsEAC0DABcACQq3IrsEAC0DACMABQoIEdYmADMBAAAA.',
Sn='Snailas:BAAANQADCgYIBwAAAA==.',
So='Sodomn:BAAANQADCgQIBAAAAA==.Solria:BAAANQAECgYIEQAAAA==.Sonnytyphoon:BAAANQADCgYIBgAAAA==.',
Sp='Spex:BAAANQADCgUIBQAAAA==.',
St='Starnex:BAAANQADCgYIBgAAAA==.Statyrea:BAAANQADCgUIBQAAAA==.Styx:BAABNQAECoEzAAIUAAkKyCYOAAANBAAUAAkKyCYOAAANBAAAAA==.',
Su='Sugabuns:BAAANQAECgcIBwAAAA==.Sukfööt:BAABNQAECoEbAAIUAAgKOxFKEQC0AQAUAAgKOxFKEQC0AQAAAA==.Sumbatadh:BAAANQAECgYIBwAAAA==.Summerflip:BAAANQADCggICAABNQAECggIKAAEADgbAA==.Sunnytyphoon:BAABNQAECoEVAAIkAAgKURM5CwARAgAkAAgKURM5CwARAgAAAA==.',
Sw='Swiftholy:BAAANQAECgYIEgAAAA==.Swiftmends:BAAANQAECgIIAgAAAA==.',
Sy='Sydahlis:BAAANQAECgcICQAAAA==.Sylvestris:BAAANQAECgYIDwAAAA==.',
Ta='Taiyana:BAAANQAECgQIBAAAAA==.Tangie:BAAANQADCggICgAAAA==.Tankjob:BAAANQAECgQICQAAAA==.Tanklorswift:BAAANQADCggIFwAAAA==.Tastemycrits:BAAANQADCggICAABNQAECgkJGAATAKAcAA==.',
Td='Tdog:BAAANQADCggICwAAAA==.',
Te='Tedoseirum:BAABNQAECoEfAAIFAAgK3iAIEgDYAgAFAAgK3iAIEgDYAgAAAA==.Terminal:BAAANQADCggICwAAAA==.Terpyu:BAAANQADCgEIAQAAAA==.Texasbilly:BAAANQADCgYIDAAAAA==.Texasredneck:BAAANQADCgYIDAAAAA==.Texasslasher:BAAANQADCgYIBgAAAA==.',
Th='Thedtwo:BAAANQAECgEIAQAAAA==.Thorgarrus:BAABNQAECoErAAITAAkK9B1vKADsAgATAAkK9B1vKADsAgAAAA==.',
Ti='Tigerwoodz:BAAANQAECgEIAQAAAA==.Timvoker:BAAANQADCgYIBgAAAA==.',
To='Toddie:BAABNQAECoEZAAMhAAgK7hqzMACZAgAhAAgK7hqzMACZAgAeAAEKRA00cAAxAAAAAA==.Tolkarnyx:BAAANQADCgUIBQABNQAFFAQIBwAZAPoTAA==.Tommyj:BAAANQADCggICwAAAA==.Tormod:BAAANQAECgYIEgAAAA==.Torvaldt:BAAANQAECgMIAwABNQAECggIGQAhAO4aAA==.Tourmod:BAAANQAECgEIAQAAAA==.',
Tr='Trakkarz:BAAANQAECgIIAgAAAA==.Traps:BAAANQAECgEIAQAAAA==.Trashypanda:BAACNQAFFIEHAAIIAAQKnxdzFgBjAQAIAAQKnxdzFgBjAQA1AAQKgSEAAggACQokIuAlADEDAAgACQokIuAlADEDAAAA.Trays:BAAANQADCgYIBgAAAA==.Tressilly:BAABNQAECoEcAAIIAAkK+RkLUQC3AgAIAAkK+RkLUQC3AgAAAA==.Trinagirl:BAAANQADCgYIBgAAAA==.Trinneries:BAAANQADCgcJBwAAAA==.Triná:BAAANQADCgYIBgABNQADCgYIBgAHAAAAAA==.Trogdorr:BAABNQAECoEgAAMYAAgKrRBkCACyAQAYAAgKTxBkCACyAQAXAAUKZQnMIAAHAQAAAA==.Trutert:BAAANQAECgIIAgAAAA==.Tryana:BAAANQADCggILQAAAA==.Trystiana:BAAANQADCgMJBAAAAA==.',
Tt='Ttania:BAAANQADCgYIDgAAAA==.',
Tu='Tubor:BAAANQAECgIIAgAAAA==.',
Tw='Tweetwee:BAAANQADCgYIBgAAAA==.',
Ty='Tyledis:BAAANQADCggJEAABNQAECggIKAAUAFIkAA==.Tyr:BAABNQAECoElAAMVAAgKTx/rIgDEAgAVAAgKTx/rIgDEAgAZAAIK1gk62ABbAAAAAA==.Tyrnova:BAAANQADCggICAAAAA==.',
['Tö']='Töshïrö:BAAANQADCgIIAgAAAA==.',
Uh='Uhope:BAAANQAECgMIAwAAAA==.',
Um='Umbravolt:BAABNQAECoErAAIlAAkKWiMgAgCEAwAlAAkKWiMgAgCEAwAAAA==.',
Un='Unclezapp:BAAANQADCggJDgAAAA==.Unravel:BAAANQADCgQIBQAAAA==.Unrealcalorx:BAAANQADCgUIBQAAAA==.Unrealronin:BAAANQAECgUICQAAAA==.',
Va='Vaeris:BAAANQADCgUJCwAAAA==.Vakero:BAAANQAECgUIBwAAAA==.Valess:BAAANQAECgMIBwAAAA==.Valros:BAAANQADCgYICgAAAA==.Vapor:BAAANQABCgIIAgAAAA==.Vaythan:BAAANQAECgcIDgAAAA==.',
Ve='Venchris:BAAANQAECgUIBgAAAA==.Verica:BAAANQADCgEIAQAAAA==.',
Vh='Vhiz:BAAANQAECgUIEAAAAA==.',
Vi='Vibrance:BAAANQADCggJEAAAAA==.Victorius:BAAANQAECgMIAwAAAA==.Viridesa:BAAANQADCgcIFAAAAA==.',
Vo='Vohlen:BAAANQABCgYIBgAAAA==.Voidcore:BAAANQAFFAEIAQABNQAECgcIEwAHAAAAAA==.Voidwalker:BAAANQADCgYICQABNQAFFAMIBwASAHMXAA==.',
Vy='Vysera:BAAANQAECgEIAQAAAA==.',
Wa='Warfarmer:BAAANQAECgIIAgAAAA==.Warhawke:BAAANQADCggIDAAAAA==.',
We='Werenal:BAAANQADCgcICwAAAA==.',
Wh='Whis:BAAANQAECgIIBAAAAA==.Whispernight:BAAANQADCgMJBQAAAA==.',
Wi='Widja:BAAANQADCgQICQAAAA==.Wiimage:BAAANQAECgQIBQAAAA==.Wiivinelight:BAAANQADCgMIAwABNQAECgQIBQAHAAAAAA==.Wildhus:BAABNQAECoEbAAIFAAgK/xPgKAAFAgAFAAgK/xPgKAAFAgAAAA==.',
Wy='Wyckdd:BAAANQADCgYIBgAAAA==.',
['Wå']='Wåffle:BAAANQAECgUICQABNQAECgkJIwAbALQiAA==.',
['Wî']='Wîca:BAABNQAECoEXAAINAAcKBwxEKwB6AQANAAcKBwxEKwB6AQAAAA==.',
Xa='Xantris:BAAANQADCgEIAQAAAA==.',
Xe='Xenowolf:BAAANQADCgYJCgABNQAECgQIBQAHAAAAAA==.',
Xv='Xvire:BAAANQADCggIGwAAAA==.',
['Xû']='Xûrû:BAAANQAECgcICQAAAA==.',
Yc='Yce:BAAANQAECgIIBAAAAA==.',
Ye='Yeiko:BAAANQAECgQIBAAAAA==.',
Yo='Yoker:BAAANQAECgQIBQAAAA==.Yokersen:BAAANQAECgcIDAAAAA==.',
Za='Zaeladen:BAAANQAECgEIAQAAAA==.Zalorea:BAAANQAECgMIAwAAAA==.Zambonii:BAAANQAECgUICAABNQAECgkJKAAfAFMhAA==.Zamdeath:BAAANQADCgMIAwABNQAECgkJKAAfAFMhAA==.Zamlock:BAABNQAECoEoAAMfAAkKUyHSDgD7AQAaAAcKQCG4LQCWAgAfAAYKmB3SDgD7AQAAAA==.Zanya:BAAANQAECgEIAQAAAA==.',
Ze='Zeiko:BAAANQAECgcIDwAAAA==.Zestychip:BAAANQADCgYIFAAAAA==.Zeäl:BAAANQADCgUIBgAAAA==.',
Zh='Zhaoyun:BAAANQAECgQIBAAAAA==.',
Zi='Zilkir:BAEBNQAECoEhAAMTAAgKOhymQQCGAgATAAgKOhymQQCGAgAQAAcK0hMqUADlAQAAAA==.Ziran:BAABNQAECoEhAAIdAAkKNyS0AQC+AwAdAAkKNyS0AQC+AwAAAA==.Zivadhim:BAAANQADCgIIAgAAAA==.',
Zl='Zlyth:BAAANQAECgMIBAAAAA==.',
Zz='Zzodac:BAAANQADCgEIAQABNQAECggIGwAFAP8TAA==.Zzvzz:BAAANQADCggJEAAAAA==.',
['Är']='Ärtrix:BAAANQAECgEIAQAAAA==.',
['Èn']='Ènyo:BAAANQAECggICAAAAA==.',
['Øp']='Øptimusdayne:BAAANQADCgEIAgAAAA==.',
['ßl']='ßlaise:BAAANQADCgQIBAAAAA==.',
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
