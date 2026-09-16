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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','Warrior-Arms','Warrior-Fury','DeathKnight-Unholy','Priest-Shadow','Priest-Holy','Priest-Discipline','Shaman-Enhancement','Warrior-Protection','Shaman-Elemental','Shaman-Restoration','Druid-Restoration','Paladin-Holy','Mage-Frost','Rogue-Assassination','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Druid-Guardian',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abnalem:BAAANQADCgIIAgAAAA==.',
Ad='Adramalech:BAAANQADCgQIBAABNQAECgkJHwABALIkAA==.',
Ae='Aeakos:BAAANQAECgIIAwABNQAECgUIDAACAAAAAA==.',
Ai='Aisele:BAAANQAECgIIAgAAAA==.',
Al='Alastor:BAAANQADCgcICwAAAA==.Alathir:BAAANQADCggICAAAAA==.Alluri:BAAANQAECgQICAAAAA==.Althemia:BAAANQADCgUIBwAAAA==.Alunamora:BAAANQAECgUIDQAAAA==.Alwind:BAAANQAECgQIBAAAAA==.',
An='Analani:BAAANQADCgYIEgAAAA==.Anali:BAAANQAECgEIAQAAAA==.Angis:BAAANQADCgQICAAAAA==.Angryheals:BAAANQAECgEIAQAAAA==.Ansfrid:BAAANQADCgYIDAAAAA==.',
Ap='Apøllø:BAAANQAECgYICwAAAA==.',
Aq='Aquatofana:BAAANQAECgQIBAAAAA==.',
Ar='Aranel:BAAANQADCgYIBgAAAA==.Arcamancer:BAAANQADCgYICwAAAA==.Arinthal:BAAANQADCggIFQAAAA==.Arril:BAAANQADCggIJwAAAA==.Artemissy:BAAANQADCgEIAgAAAA==.Artiis:BAAANQADCggICAAAAA==.',
As='Ashlieghee:BAAANQAECgYICgAAAA==.Astien:BAAANQADCgcIEgAAAA==.Astralee:BAAANQABCggICwAAAA==.',
Au='Audric:BAAANQADCgYIBwAAAA==.',
Av='Avelen:BAAANQAECgQICwAAAA==.Avha:BAAANQADCgcIDwAAAA==.Avistero:BAAANQADCgUIBwAAAA==.',
Ax='Axel:BAAANQAECgYIEAAAAA==.',
Ay='Aylden:BAABNQAECoEXAAMDAAgJKhDdGQAGAgADAAgJKhDdGQAGAgAEAAIJsQF5RgBNAAAAAA==.Aylshm:BAAANQADCgYIFAAAAA==.Ayrene:BAAANQADCgcIBwABNQAECgQIBQACAAAAAA==.',
Az='Azenazar:BAAANQADCgEIAQAAAA==.Azsharianna:BAAANQABCgYICgAAAA==.',
Ba='Bailas:BAAANQADCgcIDgAAAA==.Battousai:BAAANQADCgMIAwAAAA==.Bazileth:BAAANQADCgYIBgAAAA==.',
Be='Beastmehr:BAAANQAECgIIAgABNQAECgkJGAAFAJYfAA==.Beauregardl:BAAANQADCggIFwAAAA==.Bellina:BAAANQADCgcIBwAAAA==.Belwyn:BAAANQADCgUIBgAAAA==.Benjofamin:BAAANQADCgYIEgAAAA==.',
Bi='Bitesize:BAEBNQAECoEYAAMGAAkJRyKYDgBTAwAGAAkJ0SCYDgBTAwAHAAEJ1yTkFQBsAAAAAA==.',
Bl='Blakelivly:BAAANQAECgUICwABNQAECgYIDAACAAAAAA==.Blashster:BAABNQAECoEXAAIFAAkJWxctOwClAgAFAAkJWxctOwClAgAAAA==.Blightsize:BAEANQADCgMIAwABNQAECgkJGAAGAEciAA==.',
Bo='Bonemilker:BAABNQAECoEfAAMBAAkJsiRSAwBpAwABAAkJbiRSAwBpAwAIAAMJ/hSEXQDIAAAAAA==.Bonkdaddy:BAAANQAECggIBgAAAA==.Bopeep:BAAANQAECgcICwAAAA==.',
Br='Brandt:BAAANQABCgQICAAAAA==.Breelyssa:BAAANQADCgUIBQAAAA==.Brenna:BAAANQAECgMIAwABNQAECgQIBAACAAAAAA==.Brewslèé:BAAANQABCgYIBgAAAA==.Brighter:BAABNQAECoEYAAQJAAgJSBoqHgCQAQAJAAUJDRsqHgCQAQAKAAYJoBYOQACLAQALAAUJwBLDCQAyAQAAAA==.Brightsize:BAEANQAECgEIAQABNQAECgkJGAAGAEciAA==.Broncopally:BAAANQADCgQIBAAAAA==.Brótien:BAAANQADCggICAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bunnka:BAAANQADCgYIBgAAAA==.Bunnyparade:BAAANQADCgYIBgAAAA==.',
Ca='Caledwar:BAAANQAECgEIAQAAAA==.Calthirstrap:BAAANQAECggIEwAAAA==.Carare:BAAANQADCgYICgAAAA==.Carnàge:BAAANQAECgMIBgAAAA==.',
Ce='Ceefack:BAAANQADCgcIEQAAAA==.Cethin:BAAANQADCgYIEQAAAA==.',
Ch='Chaargee:BAAANQADCgYIBgAAAA==.Cheedar:BAAANQAFFAEIAgAAAA==.Chelaria:BAAANQADCgYIBgAAAA==.Cherylindrea:BAAANQADCgEIAgAAAA==.Chillwombat:BAAANQADCgYIDAAAAA==.',
Ck='Ckz:BAAANQADCgYIBgAAAA==.',
Cl='Clayvicar:BAAANQAECgYIEwAAAA==.',
Co='Coridane:BAAANQAECgIIAwAAAA==.Corwinfiron:BAAANQAECgQIBQAAAA==.',
Cr='Crosse:BAAANQADCgUICQAAAA==.Cruellà:BAAANQADCgYIEwAAAA==.Cryptcrawler:BAAANQAECgEIAQAAAA==.',
Cu='Curkage:BAAANQADCgIIAgAAAA==.Cuz:BAAANQADCgMIAwAAAA==.',
Cy='Cythera:BAABNQAECoEhAAIMAAkJDCV8AADQAwAMAAkJDCV8AADQAwAAAA==.',
['Cá']='Cámus:BAAANQAECgQICAAAAA==.',
Da='Daammy:BAAANQADCgYIEAAAAA==.Dagren:BAAANQADCggIGQAAAA==.Daisy:BAAANQABCggIDQABNQABCggIDgACAAAAAA==.Dakdor:BAAANQADCgMIAwAAAA==.Daphine:BAAANQADCgEIAgAAAA==.Darimonk:BAAANQADCgEIAQABNQADCgYICgACAAAAAA==.Darivara:BAAANQADCgYICgAAAA==.Darkbeautie:BAAANQADCgcIFgAAAA==.Darkcarbon:BAAANQADCggIJAAAAA==.Darkplazzma:BAAANQAECgEIAQAAAA==.Darmin:BAAANQABCgQIBAAAAA==.',
De='Deathmask:BAAANQAECgEIAQAAAA==.Deathspal:BAAANQAECgYIEwAAAA==.Dessembrae:BAABNQAECoEYAAINAAgJwh8gAwDnAgANAAgJwh8gAwDnAgAAAA==.Dewkiez:BAEBNQAECoEWAAIOAAkJkiUXAwC5AwAOAAkJkiUXAwC5AwAAAA==.',
Di='Diabolicarl:BAAANQAECgUIBwAAAA==.Diri:BAAANQADCggICAABNQAECgcIDAACAAAAAA==.',
Do='Docphanan:BAAANQADCgQIBAABNQADCgQIBAACAAAAAA==.Doesntheal:BAAANQABCgIIAgAAAA==.Dookiez:BAEANQAECgMIAwABNQAECgkJFgAOAJIlAA==.Doubledragin:BAAANQAECgUIDgAAAA==.',
Dr='Dractini:BAAANQADCgcICgABNQAECggIHgAPAJYSAA==.Dragonbelly:BAAANQABCggIDgAAAA==.Dragondeez:BAAANQABCgQIBAABNQADCgcIGAACAAAAAA==.Dragore:BAAANQAECgMIAwAAAA==.Druidgirls:BAABNQAECoEZAAIQAAkJQxHcDQBKAgAQAAkJQxHcDQBKAgAAAA==.',
Du='Durogdem:BAAANQADCgYIBgAAAA==.Duskfire:BAAANQABCgIIAgAAAA==.',
Ea='Earthaggie:BAAANQADCgEIAgAAAA==.',
Ed='Ederon:BAAANQABCgYIBgAAAA==.Edirae:BAAANQADCggIBwABNQAECgYIDwACAAAAAA==.',
El='Elenora:BAAANQAECgEIAQAAAA==.Ellesmere:BAAANQADCggIEAABNQAFFAcIEQARANAbAA==.Elye:BAAANQADCggIDAAAAA==.',
Em='Emer:BAAANQAECgQIBAAAAA==.Emiru:BAAANQADCgUIBQAAAA==.',
En='Encore:BAABNQAECoEYAAIQAAcJvwX0HwA9AQAQAAcJvwX0HwA9AQAAAA==.',
Eo='Eousphorus:BAABNQAECoEWAAMFAAgJwBDcaQAJAgAFAAgJwBDcaQAJAgASAAIJ/QhIHABlAAAAAA==.',
Er='Erathen:BAAANQADCggICgAAAA==.',
Es='Esplan:BAAANQAECgIIAgABNQAECgYIDAACAAAAAA==.',
Eu='Euden:BAAANQADCgQIBAAAAA==.',
Ev='Evelleion:BAAANQADCggIDAAAAA==.',
Ex='Exoticlord:BAAANQADCgUICQAAAA==.',
Fe='Felhayde:BAAANQADCgYIBgAAAA==.Fenryyr:BAAANQADCgMIAwAAAA==.',
Fi='Fierygrace:BAAANQADCgcIEAAAAA==.Firburger:BAAANQAECgQIBAAAAA==.Fischl:BAAANQADCgcIGgAAAA==.',
Fl='Flameth:BAAANQAECgcIEwAAAA==.Flirtywombat:BAAANQADCgYIDQAAAA==.',
Fr='Freezrorburn:BAAANQADCgYIBgAAAA==.Frõst:BAAANQABCgMIAwAAAA==.',
Fu='Fujitto:BAAANQADCgIIAgAAAA==.Fumanchu:BAAANQAECgYIEQAAAA==.',
Ga='Gaamora:BAAANQADCgIIAwAAAA==.Gainsborough:BAAANQAECggIEwABNQAECgkJIQAPAPIbAA==.Garagos:BAABNQAECoEYAAITAAgJIRgEDgBeAgATAAgJIRgEDgBeAgAAAA==.',
Ge='Gebuss:BAAANQAECggIEAAAAA==.',
Gl='Glenraven:BAAANQADCgYIEgAAAA==.',
Go='Golokan:BAAANQADCgYIDAAAAA==.Goochaddi:BAABNQAECoEWAAIUAAkJoByTIQCcAgAUAAkJoByTIQCcAgAAAA==.',
Gr='Grolden:BAAANQADCgIIAgAAAA==.Grïpnrïp:BAAANQAECgEIAQAAAA==.',
Ha='Halifaxx:BAABNQAECoEYAAIFAAgJPBVTVABNAgAFAAgJPBVTVABNAgAAAA==.Haraboo:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.Harmaa:BAAANQAECgIIAgAAAA==.Hawknor:BAAANQADCggIGQAAAA==.',
He='Healthcare:BAABNQAECoEeAAMPAAgJlhKkKwATAgAPAAgJlhKkKwATAgAOAAUJbw2ZYwAiAQAAAA==.Healthplan:BAAANQADCgYIBgABNQAECgUICwACAAAAAA==.Heartilly:BAABNQAECoEhAAIPAAkJ8hv/EQDJAgAPAAkJ8hv/EQDJAgAAAA==.Herm:BAABNQAECoEdAAMVAAgJkCFwAwAnAwAVAAgJkCFwAwAnAwAWAAMJLBtPLQCrAAAAAA==.',
Ho='Holyfu:BAAANQAECgQIBwABNQAECgYIEQACAAAAAA==.Holysky:BAAANQADCggIIgAAAA==.Holytim:BAAANQAECgUICQAAAA==.Honeypackz:BAAANQAECgIIAgAAAA==.Honnik:BAAANQABCgIIAgAAAA==.Hotpink:BAAANQADCgEIAQAAAA==.How:BAAANQAECgcIEQAAAA==.',
Hu='Humongulus:BAAANQAECgUIBgAAAA==.',
Ig='Ignöred:BAAANQAECgYICgAAAA==.',
Il='Illaine:BAAANQADCgYIBgAAAA==.Illidæn:BAAANQAECgQICQAAAA==.',
Im='Imos:BAAANQABCgQIBAAAAA==.Imperîus:BAAANQADCgUIBQABNQAECgkJHwABALIkAA==.',
In='Inaniel:BAAANQAECgQIBwAAAA==.Inq:BAABNQAECoETAAMFAAcJwxZPbwD5AQAFAAcJwxZPbwD5AQASAAEJLgsSKwAvAAAAAA==.',
Ir='Iridaceaë:BAAANQAECgUIBwABNQAECgEIAQACAAAAAA==.Iryris:BAAANQAECgEIAQAAAA==.',
Is='Isedeath:BAABNQAECoEYAAQIAAgJ0A0WMADCAQAIAAgJ/AkWMADCAQABAAUJdQstMADgAAAXAAEJOB1zdwBSAAAAAA==.Istvankh:BAAANQABCgMIBAABNQADCgEIAQACAAAAAA==.',
Ja='Jaholin:BAAANQADCgEIAQAAAA==.Jarhead:BAAANQADCgIIAgAAAA==.Jaxarus:BAAANQADCgEIAQAAAA==.',
Je='Jenaveive:BAAANQAECgQIBAAAAA==.Jethoisi:BAAANQAECgYIEAAAAA==.',
Jn='Jnex:BAAANQAECgEIAQAAAA==.',
Jo='Jongani:BAAANQAECgEIAgABNQAECgYIEAACAAAAAA==.Jookiez:BAEANQAECgEIAQABNQAECgkJFgAOAJIlAA==.',
Jr='Jrrtrolkien:BAAANQADCgQIBAAAAA==.',
Ju='Judgemehr:BAAANQAECgMIAwABNQAECgkJGAAFAJYfAA==.Judgepain:BAAANQADCgUIBQAAAA==.Judgmental:BAAANQAECgYIDgAAAA==.',
Ka='Kaelysong:BAAANQADCgUIDAAAAA==.Kairah:BAAANQADCgYIDwAAAA==.Kaivig:BAAANQADCgYIBgAAAA==.Kalï:BAAANQADCgYICQAAAA==.Karlil:BAAANQAECgQIBAAAAA==.Kasiene:BAAANQADCgYIEAAAAA==.Kasnay:BAAANQADCgQIBgAAAA==.Kathenset:BAAANQAECgQIBgAAAA==.Kazeral:BAAANQAECgcIDwAAAA==.Kazzi:BAAANQADCgIIAgAAAA==.',
Ke='Keener:BAAANQAECgIIAwAAAA==.Kelvin:BAAANQABCgQIBAAAAA==.Kerrla:BAAANQADCgcIBwABNQAECgcIDwACAAAAAA==.Keylleth:BAAANQADCgYIDgAAAA==.',
Kh='Khalanie:BAAANQAECgQIBwAAAA==.Khamnox:BAAANQADCggIEQAAAA==.Khionia:BAAANQAECgIIAgAAAA==.',
Ki='Kidthefrist:BAAANQADCgUIBQAAAA==.Kielnmsoftly:BAAANQADCgYIBgAAAA==.Kilaia:BAAANQAECgEIAQAAAA==.Kirru:BAAANQADCgUICQAAAA==.',
Kn='Knoble:BAAANQADCgQIBAAAAA==.',
Ko='Kokatoes:BAAANQADCgUIBQABNQAECgQIBwACAAAAAA==.',
Kr='Kreaton:BAAANQAECgQIBAAAAA==.Kryt:BAAANQAECgYIEQAAAA==.',
Ku='Kuponia:BAAANQABCgIIAgAAAA==.',
Kw='Kwichangpain:BAAANQADCgYIDAAAAA==.',
Kx='Kxchiki:BAAANQAECgUICQAAAA==.',
['Kã']='Kãz:BAAANQADCgYICAAAAA==.',
La='Laaklem:BAAANQADCgUIBQAAAA==.Laei:BAAANQADCggIEAAAAA==.Laserfingies:BAAANQADCgQIBgAAAA==.Lastsun:BAAANQADCgIIAgAAAA==.Lavacakes:BAABNQAECoEZAAMPAAgJuxwnHQBwAgAPAAcJTSAnHQBwAgAOAAIJOAaNnwBmAAAAAA==.Lawndartz:BAAANQADCgYIBgAAAA==.',
Le='Lelantoz:BAAANQAECgIIBAAAAA==.Leliel:BAAANQABCgQIBgAAAA==.Leqoofus:BAAANQADCgIIAgABNQADCgQIBgACAAAAAA==.',
Li='Lidan:BAAANQAECgIIAgAAAA==.Liebli:BAAANQADCgQIBAAAAA==.Liltank:BAAANQADCgYICQAAAA==.Limity:BAAANQADCgIIAgAAAA==.Linaradice:BAAANQAECgQIBgAAAA==.',
Lo='Logyn:BAAANQADCgQIBgAAAA==.Lonelyspark:BAAANQADCgMIBQAAAA==.Lotsalock:BAAANQADCgUIBQAAAA==.',
Lu='Lucifur:BAAANQADCgMIAwAAAA==.Luna:BAAANQAECgUICgAAAA==.Lunarluvgood:BAAANQAECgYIDAAAAA==.',
Ly='Lyrelia:BAAANQADCggIFwAAAA==.',
Ma='Madbones:BAAANQADCgYIBgABNQAECgUICwACAAAAAA==.Madmetal:BAAANQAECgUICwAAAA==.Mado:BAAANQAECgQIBQAAAA==.Magicky:BAAANQADCgcIGAAAAA==.Mahlkier:BAAANQADCgEIAgAAAA==.Maikego:BAAANQADCgMIAwAAAA==.Mairadin:BAAANQABCggIDAAAAA==.Malchelo:BAAANQADCgEIAQAAAA==.Malfhunter:BAAANQAECgcIDgAAAA==.Malfshammy:BAAANQADCgcIBwAAAA==.Maligosa:BAAANQADCgQIBgAAAA==.Mantodea:BAAANQADCgYIDwAAAA==.Marmin:BAAANQAECgYICgAAAA==.Marymae:BAAANQADCgEIAgAAAA==.',
Me='Meatstick:BAAANQADCgEIAQAAAA==.Meikai:BAAANQAECgQIBgAAAA==.Melillia:BAAANQAECgEIAgAAAA==.Melted:BAAANQAFFAIIAwAAAA==.Merdocki:BAABNQAECoEZAAMYAAgJux5KHgB5AgAYAAcJgx5KHgB5AgAZAAMJABhvLQDdAAAAAA==.Merdra:BAAANQAECgUICgAAAA==.Merdre:BAABNQAECoEYAAQKAAgJvxcPMADnAQAKAAgJ1hQPMADnAQALAAQJLxnDCgAZAQAJAAEJzAPjSwArAAAAAA==.',
Mi='Michealhunt:BAAANQADCgIIAgAAAA==.Midory:BAAANQAECgMIBQAAAA==.Midranaira:BAAANQADCgEIAQAAAA==.Milda:BAAANQADCgQIBQAAAA==.Milkymocha:BAAANQADCgUICQAAAA==.Misscorona:BAAANQADCgYIEAAAAA==.Mistyque:BAAANQADCgYIEgAAAA==.Mithrond:BAAANQADCgEIAQAAAA==.',
Mo='Monalea:BAAANQADCgQIBgABNQAECgYICwACAAAAAA==.Morcant:BAAANQADCggIEgAAAA==.Morianoley:BAAANQADCggIFAAAAA==.Morlu:BAAANQAECgIIAgAAAA==.Mortenson:BAAANQAECgQIBQAAAA==.Mortïmer:BAAANQAECgYICAAAAA==.Mousee:BAAANQADCgYIEAAAAA==.',
Ms='Msdonnapally:BAAANQADCgYIEQAAAA==.',
Mu='Muffindr:BAAANQADCggICAAAAA==.',
My='Myxian:BAEANQAECgQIBAABNQAECgkJGAAGAEciAA==.',
['Mö']='Möñk:BAAANQADCgQIBQAAAA==.',
Na='Nala:BAAANQAECgEIAQAAAA==.Narallia:BAAANQADCgYICAAAAA==.Nargalad:BAAANQABCgQICAAAAA==.Narios:BAAANQADCggIGgAAAA==.',
Ne='Nediem:BAAANQADCgQIBQAAAA==.Neral:BAAANQADCgMIAwAAAA==.',
Ni='Nightmehr:BAABNQAECoEYAAIFAAkJlh/8GQAyAwAFAAkJlh/8GQAyAwAAAA==.Nightshade:BAAANQADCgcIDQAAAA==.',
No='Nosaj:BAAANQAECgYIDQAAAA==.Novalee:BAAANQADCgEIAQAAAA==.',
Ny='Nyki:BAAANQADCgMIAwAAAA==.',
Od='Odlaw:BAAANQADCgYIEQAAAA==.',
Ol='Olaria:BAAANQAECgEIAQAAAA==.Olinax:BAAANQAECgUICwAAAA==.',
Om='Omalmalha:BAAANQADCgQIBAAAAA==.',
On='Onedruidtion:BAAANQADCgYICgAAAA==.',
Or='Orionmoon:BAAANQAECgYIDQAAAA==.Orlos:BAAANQADCggIGQABNQAECgEIAQACAAAAAA==.Oräkk:BAABNQAECoEWAAINAAcJAiL3AwC0AgANAAcJAiL3AwC0AgAAAA==.',
Pa='Padrin:BAAANQAECgEIAQAAAA==.Pandapaws:BAABNQAECoEXAAIPAAgJoSDPDQDzAgAPAAgJoSDPDQDzAgAAAA==.Papaflask:BAAANQAECgIIAgAAAA==.Parthal:BAAANQADCgEIAQAAAA==.Partyhardly:BAAANQAECgYICgAAAA==.Pavle:BAAANQAECgIIAgAAAA==.',
Pd='Pdiddi:BAAANQAECgMIAwAAAA==.',
Pe='Pellaeon:BAAANQAECgcIEwAAAA==.Pelt:BAAANQAECgcIEgAAAA==.Petmasta:BAAANQABCgEIAQABNQABCgQIBAACAAAAAA==.',
Ph='Pharaun:BAAANQADCggICAABNQAECgYIEAACAAAAAA==.Phlan:BAEANQAECgQIBAAAAA==.Phrostir:BAAANQAECggIEAAAAA==.',
Pi='Picklechips:BAAANQADCgEIAQAAAA==.Pillgrimm:BAAANQAECgQIBAAAAA==.Pillsburyman:BAAANQAECgEIAQAAAA==.',
Po='Pointee:BAAANQADCgYICgAAAA==.Poisson:BAAANQAECgcIDAAAAA==.Pokoxo:BAAANQAECgQICQABNQAECgIIAwACAAAAAA==.Pookiez:BAEANQADCggIDwABNQAECgkJFgAOAJIlAA==.',
Pr='Prancine:BAAANQADCggICAABNQAECggIHgAPAJYSAA==.Providence:BAAANQAECgcIDgAAAA==.',
Pu='Pudgypaws:BAAANQAECgMIAwAAAA==.',
Qu='Quickmend:BAAANQAECgQIBAAAAA==.Quickpal:BAAANQAECgQIBAAAAA==.Quickpaw:BAAANQAECggIEgAAAA==.',
Ra='Raccoons:BAAANQADCgMIAwABNQAECgkJIAAYADcaAA==.Radell:BAAANQADCgIIAgAAAA==.Rageproof:BAAANQAECgEIAgAAAA==.Ragged:BAAANQAECgcIDQAAAA==.Raidbloom:BAEANQAFFAIIAgABNQAECggIGwARADYUAA==.Raidshock:BAEBNQAECoEbAAIRAAgJNhS0JgA6AgARAAgJNhS0JgA6AgAAAA==.Rainsinger:BAAANQADCgYIEgAAAA==.Ramook:BAEANQADCggIEQAAAA==.Randomchar:BAABNQAECoEYAAIUAAgJRgzWVQChAQAUAAgJRgzWVQChAQAAAA==.Rankor:BAAANQADCgYIBgABNQAECggIGAAaAJwMAA==.Rastann:BAABNQAECoEZAAIUAAkJjxxQIQCfAgAUAAkJjxxQIQCfAgAAAA==.Ratsdrack:BAAANQADCgMIAwAAAA==.Rawrlas:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Razdor:BAAANQADCgUIBgAAAA==.',
Re='Reapertoo:BAABNQAECoEaAAMBAAkJOCSwBQAhAwABAAkJECCwBQAhAwAIAAYJoh5kLgDNAQAAAA==.Recreant:BAAANQADCgYICwAAAA==.Redbaron:BAAANQAECgYICwAAAA==.Reetep:BAAANQADCgYIDwAAAA==.Regeth:BAAANQADCggIFQAAAA==.Revin:BAAANQAECgEIAQAAAA==.',
Ro='Rolas:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.Rondle:BAAANQADCgEIAQABNQADCgcICAACAAAAAA==.Rottencorpse:BAAANQADCgQIBAAAAA==.Rozalin:BAABNQAECoEYAAIFAAgJ7yAIKQDtAgAFAAgJ7yAIKQDtAgAAAA==.Rozalinamoon:BAAANQADCgMIAwAAAA==.',
Ru='Rurouni:BAAANQADCgcIBwAAAA==.Rustystorm:BAAANQADCgMIAwAAAA==.Rustywarlock:BAAANQADCgUIBQAAAA==.',
Ry='Ryoshi:BAAANQAECgYIEgAAAA==.',
['Rò']='Ròòszy:BAAANQADCgYIBwAAAA==.',
Sa='Sacredstars:BAAANQADCggICAAAAA==.Sacredswords:BAABNQAECoEVAAMGAAgJnRdfNwBcAgAGAAgJnRdfNwBcAgAHAAEJ0whFHQAyAAAAAA==.Sanguinius:BAAANQAECgYIDQAAAA==.Sapphiremist:BAAANQAECgIIAgAAAA==.Sayen:BAAANQAFFAEIAQAAAA==.',
Sc='Scachity:BAAANQAECgQICQAAAA==.Scan:BAAANQAECggIEgAAAA==.Schein:BAAANQAECgQIDAAAAA==.',
Se='Segsacute:BAAANQAECgYIBgAAAA==.Sepulchre:BAAANQAECgYIEAAAAA==.',
Sh='Shadesfault:BAAANQADCgEIAgAAAA==.Shadowhart:BAAANQADCgEIAQAAAA==.Shaeebulay:BAAANQABCgIIAgAAAA==.Shamaroo:BAAANQABCgUIBQAAAA==.Shaundakul:BAAANQAECgQIBwAAAA==.Shephion:BAAANQAECgEIAQABNQAECggIHQAVAJAhAA==.Shnozberries:BAAANQADCgEIAQAAAA==.Shockhart:BAAANQADCggIDwAAAA==.Shortnstack:BAAANQADCggIGAAAAA==.Shãdow:BAAANQADCgUIBQAAAA==.',
Si='Simori:BAAANQADCgIIAgAAAA==.Sindrel:BAAANQADCgYIBgABNQAECggIGgAWAJ8fAA==.',
Sk='Skawalker:BAABNQAECoEaAAIQAAkJsh+lAgBeAwAQAAkJsh+lAgBeAwAAAA==.',
Sl='Slaed:BAAANQADCgYIBwAAAA==.Slaynne:BAAANQAECgcIEAAAAA==.',
Sm='Smäug:BAABNQAECoEfAAMbAAkJ3CDUAgBTAwAbAAkJ3CDUAgBTAwAcAAUJCBG+HAA9AQAAAA==.',
Sn='Snailas:BAAANQADCgEIAQAAAA==.',
So='Sodomn:BAAANQADCgQIBAAAAA==.Solria:BAAANQAECgQIBgAAAA==.Sonnytyphoon:BAAANQADCgYIBgAAAA==.',
Sp='Spex:BAAANQADCgUIBQAAAA==.',
St='Starnex:BAAANQADCgYIBgAAAA==.Statyrea:BAAANQADCgUIBQAAAA==.Styx:BAABNQAECoEgAAINAAkJuCYHAAAWBAANAAkJuCYHAAAWBAAAAA==.',
Su='Sukfööt:BAAANQAECgcIDwAAAA==.Sumbatadh:BAAANQAECgQIBQAAAA==.Sunnytyphoon:BAAANQAECgYICgAAAA==.',
Sw='Swiftholy:BAAANQAECgUICgAAAA==.Swiftmends:BAAANQAECgIIAgAAAA==.',
Sy='Sylvestris:BAAANQAECgUICgAAAA==.',
Ta='Taiyana:BAAANQAECgQIBAAAAA==.Tangie:BAAANQADCggICgAAAA==.Tankjob:BAAANQAECgQIAwAAAA==.Tanklorswift:BAAANQADCgcICgAAAA==.Tastemycrits:BAAANQADCggICAABNQAECgkJFgAUAKAcAA==.',
Td='Tdog:BAAANQADCggICwAAAA==.',
Te='Teapot:BAAANQABCgIIAgAAAA==.Tedoseirum:BAAANQAECgYIDwAAAA==.Terpyu:BAAANQADCgEIAQAAAA==.Texasbilly:BAAANQADCgYIDAAAAA==.Texasredneck:BAAANQADCgYIDAAAAA==.Texasslasher:BAAANQADCgYIBgAAAA==.',
Th='Thedtwo:BAAANQADCgcIDAAAAA==.Thorgarrus:BAABNQAECoEZAAIUAAkJeBWYLQBXAgAUAAkJeBWYLQBXAgAAAA==.',
Ti='Tigerwoodz:BAAANQAECgEIAQAAAA==.Timvoker:BAAANQADCgYIBgAAAA==.',
To='Toddie:BAAANQAECgUIBwAAAA==.Tommyj:BAAANQADCggICwAAAA==.Tormod:BAAANQAECgQIBwAAAA==.Tourmod:BAAANQAECgEIAQAAAA==.',
Tr='Trakkarz:BAAANQAECgIIAgAAAA==.Traps:BAAANQAECgEIAQAAAA==.Trashypanda:BAABNQAECoEbAAIFAAkJIyCZGQA0AwAFAAkJIyCZGQA0AwAAAA==.Trays:BAAANQADCgYIBgAAAA==.Tressilly:BAAANQAECgcIEgAAAA==.Trinagirl:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Triná:BAAANQADCgYIBgAAAA==.Trogdorr:BAABNQAECoEYAAMaAAgJnAw0BgCeAQAaAAgJnAw0BgCeAQAbAAIJvAV8JABbAAAAAA==.Trutert:BAAANQADCgcIEQAAAA==.Tryana:BAAANQADCggIHgAAAA==.Trystiana:BAAANQADCgMIBAAAAA==.',
Tt='Ttania:BAAANQADCgYIDgAAAA==.',
Tw='Tweetwee:BAAANQADCgYIBgAAAA==.',
Ty='Tyledis:BAAANQADCggICAABNQAECggIGAANAMIfAA==.Tyr:BAAANQAECgcIEgAAAA==.Tyrnova:BAAANQADCggICAAAAA==.',
['Tö']='Töshïrö:BAAANQADCgIIAgAAAA==.',
Uh='Uhope:BAAANQAECgEIAQAAAA==.',
Um='Umbravolt:BAABNQAECoEZAAIdAAkJYCCiAQBSAwAdAAkJYCCiAQBSAwAAAA==.',
Un='Unclezapp:BAAANQADCgcIBwAAAA==.Unravel:BAAANQADCgEIAQAAAA==.Unrealronin:BAAANQADCggICAAAAA==.',
Va='Vaeris:BAAANQADCgUICwAAAA==.Vakero:BAAANQAECgIIAgAAAA==.Valess:BAAANQAECgEIAQAAAA==.Valros:BAAANQADCgYICgAAAA==.Vapor:BAAANQABCgIIAgAAAA==.Vaythan:BAAANQAECgcIBwAAAA==.',
Ve='Venchris:BAAANQADCgUIBgAAAA==.Verica:BAAANQADCgEIAQAAAA==.',
Vh='Vhiz:BAAANQAECgUICQAAAA==.',
Vi='Vibrance:BAAANQADCggICAAAAA==.Victorius:BAAANQAECgMIAwAAAA==.Viridesa:BAAANQADCgYIDQAAAA==.',
Vo='Voidcore:BAAANQAECgIIAwABNQAECgYICgACAAAAAA==.Voidwalker:BAAANQADCgYICQABNQAECgkJIQAMAAwlAA==.',
Vy='Vysera:BAAANQADCgYIDAAAAA==.',
Wa='Warfarmer:BAAANQADCggIFAAAAA==.Warhawke:BAAANQADCgMIAwAAAA==.',
We='Werenal:BAAANQADCgcICwAAAA==.',
Wh='Whis:BAAANQADCggIGQAAAA==.Whispernight:BAAANQADCgEIAgAAAA==.',
Wi='Widja:BAAANQADCgEIAgAAAA==.Wiimage:BAAANQAECgQIBQAAAA==.Wiivinelight:BAAANQADCgMIAwABNQAECgQIBQACAAAAAA==.Wildhus:BAAANQAECgYICwAAAA==.',
Wy='Wyckdd:BAAANQADCgYIBgAAAA==.',
['Wå']='Wåffle:BAAANQAECgQIBAABNQAECggIEAACAAAAAA==.',
['Wî']='Wîca:BAAANQAECgYIDgAAAA==.',
Xa='Xantris:BAAANQADCgEIAQAAAA==.',
Xe='Xenowolf:BAAANQADCgYICgABNQADCgcIFgACAAAAAA==.',
Xv='Xvire:BAAANQADCgYIEAAAAA==.',
['Xû']='Xûrû:BAAANQAECgIIAgAAAA==.',
Yc='Yce:BAAANQADCggIHAAAAA==.',
Yo='Yokersen:BAAANQADCggIDgAAAA==.',
Za='Zaeladen:BAAANQADCgYIDQAAAA==.Zalorea:BAAANQADCgcIBwAAAA==.Zambonii:BAAANQAECgQIBQABNQAECgkJGQAYAMYbAA==.Zamdeath:BAAANQADCgMIAwABNQAECgkJGQAYAMYbAA==.Zamlock:BAABNQAECoEZAAMYAAkJxhsxKwAxAgAYAAcJXxoxKwAxAgAZAAUJVRy2FgCSAQAAAA==.Zanya:BAAANQADCgYIDQAAAA==.',
Ze='Zeiko:BAAANQADCggIDgAAAA==.Zestychip:BAAANQADCgYIDQAAAA==.Zeäl:BAAANQADCgUIBgAAAA==.',
Zh='Zhaoyun:BAAANQADCgUICQAAAA==.',
Zi='Zilkir:BAEANQAECgcIDgAAAA==.Ziran:BAAANQAECggIDwAAAA==.Zivadhim:BAAANQADCgIIAgAAAA==.',
Zl='Zlyth:BAAANQAECgEIAQAAAA==.',
Zz='Zzvzz:BAAANQADCgYICAAAAA==.',
['Är']='Ärtrix:BAAANQAECgEIAQAAAA==.',
['Èn']='Ènyo:BAAANQADCgUICQAAAA==.',
['Øp']='Øptimusdayne:BAAANQADCgEIAQAAAA==.',
['ßl']='ßlaise:BAAANQABCgYICQAAAA==.',
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
