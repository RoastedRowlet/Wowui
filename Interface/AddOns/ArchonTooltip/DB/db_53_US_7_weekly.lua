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

local lookup = {'DeathKnight-Unholy','Unknown-Unknown','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','Warrior-Arms','Warrior-Fury','DeathKnight-Frost','Priest-Shadow','Priest-Holy','Priest-Discipline','Paladin-Holy','Shaman-Enhancement','Paladin-Retribution','Paladin-Protection','Warrior-Protection','Shaman-Elemental','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Warlock-Demonology','Shaman-Restoration','Rogue-Assassination','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Blood','Warlock-Destruction','Hunter-BeastMastery','Hunter-Survival','Evoker-Preservation','Druid-Guardian',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abnalem:BAAANQADCgIIAgAAAA==.',
Ad='Adramalech:BAAANQADCgQIBAABNQAFFAUICAABALMeAA==.',
Ae='Aeakos:BAAANQAECgIIAwABNQAECgUJDwACAAAAAA==.Aeldon:BAAANQADCggICAAAAA==.',
Ai='Aisele:BAAANQAECgQJBgAAAA==.',
Al='Alastor:BAAANQADCgcICwAAAA==.Alathir:BAAANQAECgQIBAAAAA==.Alluri:BAAANQAECgQICAAAAA==.Althemia:BAAANQADCgUIBwAAAA==.Alunamora:BAABNQAECoEVAAIDAAgKWxxrDACkAgADAAgKWxxrDACkAgAAAA==.Alwind:BAAANQAECgUJCQAAAA==.',
An='Analani:BAAANQADCgcJGQAAAA==.Anali:BAAANQAECgEJAQAAAA==.Angis:BAAANQADCgQICAAAAA==.Angryheals:BAAANQAECgEJAQAAAA==.Ansfrid:BAAANQADCggIDgAAAA==.',
Ap='Apøllø:BAAANQAECgcIDwAAAA==.',
Aq='Aquatofana:BAAANQAECgQIBQAAAA==.',
Ar='Aranel:BAAANQADCgYIBgAAAA==.Arcamancer:BAAANQADCgcJEgAAAA==.Arinthal:BAAANQADCggIFwAAAA==.Arril:BAAANQAECgEIAQAAAA==.Artemissy:BAAANQADCgEIAgAAAA==.',
As='Ashlieghee:BAAANQAECgYIEAAAAA==.Astien:BAAANQAECgEJAQAAAA==.Astralee:BAAANQADCgEIAQAAAA==.',
Au='Audric:BAAANQADCgYIBwAAAA==.',
Av='Avelen:BAAANQAECgYIDwAAAA==.Avha:BAAANQAECgEIAQAAAA==.Avistero:BAAANQADCgUIBwAAAA==.',
Ax='Axel:BAABNQAECoEYAAIEAAcK6h5zGgBUAgAEAAcK6h5zGgBUAgAAAA==.',
Ay='Aylden:BAABNQAECoEdAAMEAAgKZhD4IwD1AQAEAAgKZhD4IwD1AQAFAAIKsQE8TQBNAAAAAA==.Aylshm:BAAANQADCgYIFAAAAA==.Ayrene:BAAANQADCgcIBwABNQAECgQIBQACAAAAAA==.',
Az='Azenazar:BAAANQADCgEIAQAAAA==.Azog:BAAANQAECgEIAQAAAA==.Azsharianna:BAAANQABCggIDAAAAA==.',
Ba='Bailas:BAAANQADCgcIDgAAAA==.Battousai:BAAANQADCgMIAwAAAA==.Bazileth:BAAANQADCgYIBgAAAA==.',
Be='Bearistotle:BAAANQAECgEIAQAAAA==.Beastmehr:BAAANQAECgMIBAABNQAECgkJHwAGALofAA==.Beauregardl:BAAANQAECgEJAQAAAA==.Bellina:BAAANQADCgcIBwAAAA==.Belwyn:BAAANQADCgUIBgAAAA==.Benjofamin:BAAANQAECgEJAQAAAA==.',
Bi='Bitesize:BAEBNQAECoEfAAMHAAkK0SIEFQA6AwAHAAkKWyEEFQA6AwAIAAEK1yT5GgBpAAAAAA==.',
Bl='Blakelivly:BAEANQAECgUICwABNQAECgcJEwACAAAAAA==.Blashster:BAABNQAECoEgAAIGAAkKfR+cHwA5AwAGAAkKfR+cHwA5AwAAAA==.Blightsize:BAEANQADCgMIAwABNQAECgkJHwAHANEiAA==.',
Bo='Bonemilker:BAACNQAFFIEIAAMBAAUKsx5EBAA7AQABAAMKlB9EBAA7AQAJAAMKTh+dBAAaAQA1AAQKgSEAAwkACQolJT4FAGADAAkACQolJT4FAGADAAEAAwr+FMJrAMAAAAAA.Bonkdaddy:BAAANQAECggJDQAAAA==.Bopeep:BAAANQAECgcICwAAAA==.',
Br='Brandt:BAAANQABCgQICAAAAA==.Breelyssa:BAAANQADCgUJCQAAAA==.Brenna:BAAANQAECgMIAwABNQAECgUJCQACAAAAAA==.Brewslèé:BAAANQABCgYIBgAAAA==.Brighter:BAABNQAECoEgAAQKAAgKPhuqFQBHAgAKAAcKDRuqFQBHAgALAAYKlxY+VQCFAQAMAAYKRBFoCQBjAQAAAA==.Brightsize:BAEANQAECgEIAgABNQAECgkJHwAHANEiAA==.Broncopally:BAAANQADCgQIBAAAAA==.Brótien:BAAANQADCggICAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bunnka:BAAANQADCgYIBgAAAA==.Bunnyparade:BAAANQADCgYIBgAAAA==.',
Ca='Cakesdruid:BAAANQADCggJCAAAAA==.Caledwar:BAAANQAECgMIBAAAAA==.Calrissa:BAAANQADCgMIAwABNQAECgQIBAACAAAAAA==.Calthirstrap:BAABNQAECoEcAAIBAAkKliPnBACUAwABAAkKliPnBACUAwAAAA==.Carare:BAAANQADCgYICgAAAA==.Carnàge:BAAANQAECgMIBgAAAA==.',
Ce='Ceefack:BAAANQADCgcJGAAAAA==.Cethin:BAAANQADCggIGQAAAA==.',
Ch='Chaargee:BAAANQAECgIIAgAAAA==.Cheedar:BAABNQAECoEZAAINAAkKFRAXLwBEAgANAAkKFRAXLwBEAgAAAA==.Chelaria:BAAANQADCgcJDQAAAA==.Cherylindrea:BAAANQADCgMJBQAAAA==.Chillwombat:BAAANQADCgcJEwAAAA==.Chumlei:BAAANQADCgcIBwAAAA==.',
Ck='Ckz:BAAANQADCggJDgAAAA==.',
Cl='Claydemon:BAAANQAECgQJBAAAAA==.Clayvicar:BAABNQAECoEfAAMLAAgKpAw/WAB4AQALAAcKTw0/WAB4AQAKAAIKVgPmRQBuAAAAAA==.',
Co='Coridane:BAAANQAECgMIBgAAAA==.Corwinfiron:BAAANQAECgUJCgAAAA==.',
Cr='Crosse:BAAANQADCgYIDwAAAA==.Cruellà:BAAANQADCgYIEwAAAA==.Cryptcrawler:BAAANQAECgEIAgAAAA==.',
Cu='Curkage:BAAANQADCgIIAgAAAA==.Cuz:BAAANQAECgYJBgAAAA==.',
Cy='Cythera:BAABNQAECoElAAIOAAkKHyX2AAC0AwAOAAkKHyX2AAC0AwAAAA==.',
['Cá']='Cámus:BAAANQAECgUJCwAAAA==.',
Da='Daammy:BAAANQADCgcJFwAAAA==.Dagren:BAAANQADCggIGQAAAA==.Daisy:BAAANQABCggJFwABNQABCggJGAACAAAAAA==.Dakdor:BAAANQADCgMIAwAAAA==.Daphine:BAAANQADCgEIAgAAAA==.Darimonk:BAAANQADCgEIAQABNQADCgYICgACAAAAAA==.Darivara:BAAANQADCgYICgAAAA==.Darkbeautie:BAAANQAECgEIAQAAAA==.Darkcarbon:BAAANQAECgEIAQAAAA==.Darkplazzma:BAAANQAECgEIAQAAAA==.Darmin:BAAANQABCgQIBAAAAA==.',
De='Deathmask:BAAANQAECgEIAQAAAA==.Deathspal:BAABNQAECoEbAAMPAAcKrxN9aQDAAQAPAAcKrxN9aQDAAQAQAAIKpQg2QQBWAAAAAA==.Dessembrae:BAABNQAECoEgAAIRAAgKUyOaAgA1AwARAAgKUyOaAgA1AwAAAA==.Dewkiez:BAEBNQAECoEXAAISAAkKkiUNBgCeAwASAAkKkiUNBgCeAwAAAA==.',
Di='Diabolicarl:BAAANQAECgYIDQAAAA==.Diri:BAAANQADCggICAABNQAECgkJFwATAGsKAA==.',
Dm='Dmmeforpi:BAAANQADCgQIBAAAAA==.',
Do='Docphanan:BAAANQAECgEIAgAAAA==.Doesntheal:BAAANQABCgIIBAAAAA==.Dookiez:BAEANQAECgYICAABNQAECgkJFwASAJIlAA==.Doubledragin:BAABNQAECoEXAAMUAAcKjxJZFACoAQAUAAcK0Q5ZFACoAQAVAAQKxhT9DADqAAAAAA==.',
Dr='Dracantar:BAAANQADCgEIAQAAAA==.Dractini:BAAANQADCgcJCgABNQAFFAcIFwALAHEYAA==.Dragfan:BAAANQADCgQJBAAAAA==.Dragonbelly:BAAANQABCggJGAAAAA==.Dragondeez:BAAANQABCgQIBQABNQADCggJHgACAAAAAA==.Dragore:BAAANQAECgQIBwAAAA==.Druidgirls:BAABNQAECoEiAAIDAAkK1xbQDQCLAgADAAkK1xbQDQCLAgAAAA==.',
Du='Durogdem:BAAANQADCgYIBgAAAA==.Duskfire:BAAANQABCgIIAgAAAA==.',
Ea='Earthaggie:BAAANQADCgMJBQAAAA==.',
Ed='Ederon:BAAANQABCgYIBgAAAA==.Edirae:BAAANQAECgIIAgAAAA==.',
El='Elenora:BAAANQAECgUIBgAAAA==.Ellesmere:BAAANQADCggIEAABNQAFFAcIEgANAMQdAA==.Elye:BAAANQAECgEJAQAAAA==.',
Em='Emer:BAAANQAECgQIBAAAAA==.Emiru:BAAANQADCgUJBgAAAA==.',
En='Encore:BAABNQAECoEgAAIDAAgKEQtxHgCgAQADAAgKEQtxHgCgAQAAAA==.',
Eo='Eousphorus:BAABNQAECoEeAAMGAAgKCxRebwBEAgAGAAgKCxRebwBEAgAWAAIK/Qh3IwBkAAAAAA==.',
Er='Erathen:BAAANQADCggICgAAAA==.',
Es='Esplan:BAEANQAECgMJBAABNQAECgcJEwACAAAAAA==.',
Eu='Euden:BAAANQADCgQIBAAAAA==.',
Ev='Evelleion:BAAANQAECgMIAwAAAA==.',
Ex='Exoticlord:BAAANQADCgUJCQAAAA==.',
Fe='Felhayde:BAAANQADCgYIBgAAAA==.Fenryyr:BAAANQADCgYJBwAAAA==.',
Fi='Fierygrace:BAAANQADCgcIEAAAAA==.Firburger:BAAANQAECgQIBgAAAA==.Fischl:BAAANQADCggJIgAAAA==.',
Fl='Flameth:BAABNQAECoEeAAIXAAgKfw5MUADfAQAXAAgKfw5MUADfAQAAAA==.Flirtywombat:BAAANQADCggIDwAAAA==.',
Fr='Freezrorburn:BAAANQADCgYJBwAAAA==.Frõst:BAAANQABCgMIAwAAAA==.',
Fu='Fujitto:BAAANQADCgIIAgAAAA==.Fumanchu:BAABNQAECoEYAAIRAAcKkBxtCABDAgARAAcKkBxtCABDAgAAAA==.',
Ga='Gaamora:BAAANQADCgMJBgAAAA==.Gainsborough:BAABNQAECoEdAAMPAAkKFx44HwDwAgAPAAgKyx84HwDwAgAQAAEKexDHRQBDAAABNQAFFAUICgAYANEUAA==.Garagos:BAABNQAECoEgAAIZAAgKaBjNEwBfAgAZAAgKaBjNEwBfAgAAAA==.',
Ge='Gebuss:BAABNQAECoEcAAIZAAkKqCKgAgCFAwAZAAkKqCKgAgCFAwAAAA==.',
Gl='Glenraven:BAAANQADCggIGgAAAA==.',
Go='Golokan:BAAANQADCgYIDAAAAA==.Goochaddi:BAABNQAECoEYAAIPAAkKoBwLNwB4AgAPAAkKoBwLNwB4AgAAAA==.',
Gr='Grolden:BAAANQADCgIIAgAAAA==.Grïpnrïp:BAAANQAECgEIAQAAAA==.',
Ha='Halifaxx:BAABNQAECoEfAAIGAAgK9hahYwBkAgAGAAgK9hahYwBkAgAAAA==.Halitwo:BAAANQADCggICAAAAA==.Haraboo:BAAANQADCggJCAABNQAECgEIAQACAAAAAA==.Harmaa:BAAANQAECgIIAgAAAA==.Hawknor:BAAANQAECgEJAQAAAA==.',
He='Healthcare:BAABNQAECoEiAAMYAAkKJRIvLgBEAgAYAAkKJRIvLgBEAgASAAUKbw0MgAAYAQABNQAFFAcIFwALAHEYAA==.Healthplan:BAAANQADCgYIBgABNQAECgUJEAACAAAAAA==.Heartilly:BAACNQAFFIEKAAIYAAUK0RSlBAChAQAYAAUK0RSlBAChAQA1AAQKgSYAAhgACQoUHRgWANYCABgACQoUHRgWANYCAAAA.Herm:BAABNQAECoEmAAMaAAgKdSX6AgBXAwAaAAgKdSX6AgBXAwAbAAMKLBtPNwCmAAAAAA==.',
Ho='Holyfu:BAAANQAECgUIDAABNQAECgcJGAARAJAcAA==.Holymidget:BAAANQAECgEJAQAAAA==.Holysky:BAAANQAECgEIAQAAAA==.Holytim:BAAANQAECgcJEAAAAA==.Honeypackz:BAAANQAECgIIAgAAAA==.Honnik:BAAANQABCgIIAgAAAA==.Hotpink:BAAANQADCgMJBAAAAA==.How:BAABNQAECoEYAAMaAAkK7B9nAwBGAwAaAAkK7B9nAwBGAwAbAAIKrQqAPQBvAAAAAA==.',
Hu='Humongulus:BAAANQAECgYIDAAAAA==.',
Ig='Ignöred:BAAANQAECgYJEAAAAA==.',
Il='Illaine:BAAANQADCgYIBgAAAA==.Illidæn:BAAANQAECgUJDgAAAA==.',
Im='Imos:BAAANQABCgQIBAAAAA==.Imperîus:BAAANQADCgUIBQABNQAFFAUICAABALMeAA==.',
In='Inaniel:BAAANQAECgQJCgAAAA==.Inq:BAABNQAECoEbAAMGAAgKNx1IRwC1AgAGAAgKNx1IRwC1AgAWAAEKLgsINAAvAAAAAA==.',
Ir='Iridaceaë:BAAANQAECgYIDAABNQAECgEIAQACAAAAAA==.Iryris:BAAANQAECgMIBwAAAA==.',
Is='Isedeath:BAABNQAECoEgAAQBAAgKuhLqKwAMAgABAAgKehHqKwAMAgAJAAUKdQsrRQDdAAAcAAEKOB3YjQBNAAAAAA==.Istvankh:BAAANQABCgMIBAABNQADCgEIAQACAAAAAA==.',
Ja='Jaholin:BAAANQADCgEIAQAAAA==.Jarhead:BAAANQADCgIIAgAAAA==.Jaxarus:BAAANQADCgEIAQAAAA==.',
Je='Jenaveive:BAAANQAECgcICwAAAA==.Jethoisi:BAAANQAECgYIEAABNQAFFAEJAQACAAAAAA==.Jexi:BAAANQADCgYJBgABNQAECgQIBQACAAAAAA==.',
Jn='Jnex:BAAANQAECgUIBgAAAA==.',
Jo='Jongani:BAAANQAFFAEJAQAAAA==.Jookiez:BAEANQAECgIJAgABNQAECgkJFwASAJIlAA==.',
Jr='Jrrtrolkien:BAAANQADCgQIBAABNQAECgEIAgACAAAAAA==.',
Ju='Judgemehr:BAAANQAECgMIAwABNQAECgkJHwAGALofAA==.Judgepain:BAAANQADCgcJDAAAAA==.Judgmental:BAABNQAECoEWAAINAAcKEB3qKABlAgANAAcKEB3qKABlAgAAAA==.',
Ka='Kaelysong:BAAANQADCgUJDQAAAA==.Kairah:BAAANQADCgcIEAAAAA==.Kaivig:BAAANQADCgYIBgAAAA==.Kalï:BAAANQADCgYICQAAAA==.Karlil:BAAANQAECgQICAAAAA==.Kasiene:BAAANQADCgYIFgAAAA==.Kasnay:BAAANQADCgQIBgAAAA==.Kathenset:BAAANQAECgUICAAAAA==.Kazeral:BAAANQAFFAEJAQAAAA==.Kazzi:BAAANQADCgIIAgAAAA==.',
Ke='Keener:BAAANQAECgQJBwAAAA==.Kelvin:BAAANQABCgQIBAAAAA==.Kerrla:BAAANQAECgEJAQABNQAFFAEJAQACAAAAAA==.Keylleth:BAAANQADCgYJDwAAAA==.',
Kh='Khalanie:BAAANQAECgUJDAAAAA==.Khamnox:BAAANQAECgEJAQAAAA==.Khionia:BAAANQAECgIIAgAAAA==.',
Ki='Kidthefrist:BAAANQADCgUIBQAAAA==.Kielnmsoftly:BAAANQADCgYIBgAAAA==.Kilaia:BAAANQAECgEIAgAAAA==.Kirru:BAAANQADCgYJDwAAAA==.',
Kn='Knoble:BAAANQADCgQIBAAAAA==.',
Ko='Kokatoes:BAAANQAECgIIAgABNQAECgQJDQACAAAAAA==.',
Kr='Kreaton:BAAANQAECgYICgAAAA==.Kryt:BAABNQAECoEbAAIYAAcKRiAaIwCBAgAYAAcKRiAaIwCBAgAAAA==.',
Ku='Kuponia:BAAANQABCgIIAgAAAA==.',
Kw='Kwichangpain:BAAANQADCgcJDQAAAA==.',
Kx='Kxchiki:BAAANQAECgYIDwAAAA==.',
['Kã']='Kãz:BAAANQADCgYICAAAAA==.',
La='Laaklem:BAAANQAECgEJAQAAAA==.Laei:BAAANQADCggIEAAAAA==.Laserfingies:BAAANQADCgcIDQAAAA==.Lastsun:BAAANQADCgIIAgAAAA==.Lavacakes:BAABNQAECoEhAAMYAAgKbyACGQDCAgAYAAgKbyACGQDCAgASAAIKZwYjwgBhAAAAAA==.Lawndartz:BAAANQADCggJDgAAAA==.',
Le='Lelantoz:BAAANQAECgUJCQAAAA==.Leliel:BAAANQABCgUICAAAAA==.Leqoofus:BAAANQADCgIIAgABNQADCgcIDQACAAAAAA==.',
Li='Lidan:BAAANQAECgUIBwAAAA==.Liebli:BAAANQAECgEIAQAAAA==.Liltank:BAAANQADCgYICQAAAA==.Limity:BAAANQADCgIIAgAAAA==.Linaradice:BAAANQAECgQIBgAAAA==.',
Lo='Logyn:BAAANQADCgQIBgAAAA==.Lonelyspark:BAAANQADCgMIBQAAAA==.Lonnias:BAAANQADCgYJBgAAAA==.Lotsalock:BAAANQADCgUIBQAAAA==.',
Lu='Lucifur:BAAANQADCgMIAwAAAA==.Luna:BAAANQAECgUJDwAAAA==.Lunarluvgood:BAEANQAECgcJEwAAAA==.',
Ly='Lyrelia:BAAANQAECgEJAQAAAA==.',
Ma='Madbones:BAAANQADCgYIBgABNQAECgUJEAACAAAAAA==.Madmetal:BAAANQAECgUJEAAAAA==.Mado:BAAANQAECgQICAAAAA==.Magefood:BAAANQABCgEIAQABNQABCgIJAgACAAAAAA==.Magicky:BAAANQADCggJHgAAAA==.Mahlkier:BAAANQADCgEIAgAAAA==.Maikego:BAAANQAECgEIAQAAAA==.Mairadin:BAAANQABCggIDAAAAA==.Malchelo:BAAANQADCgIJAgAAAA==.Malfhunter:BAAANQAECggIEgAAAA==.Malfshammy:BAAANQADCgcIBwAAAA==.Maligosa:BAAANQADCgQIBgAAAA==.Mantodea:BAAANQADCgYIFQAAAA==.Marmin:BAAANQAECgYJEAAAAA==.Marymae:BAAANQADCgMJBQAAAA==.',
Me='Meatstick:BAAANQADCgEIAQAAAA==.Meikai:BAAANQAECgUICAAAAA==.Melillia:BAAANQAECgEIAgAAAA==.Melted:BAABNQAECoEWAAIGAAkKKhwmMwD0AgAGAAkKKhwmMwD0AgAAAA==.Merdocki:BAABNQAECoEhAAMXAAgKgSAELgBoAgAXAAcKGSAELgBoAgAdAAQKKhONJwAVAQAAAA==.Merdra:BAAANQAECgUJDgAAAA==.Merdre:BAABNQAECoEgAAQLAAgKxxrCLQBCAgALAAgK8hjCLQBCAgAMAAQKLxmcDAAQAQAKAAEKzAPFVwArAAAAAA==.',
Mi='Michealhunt:BAAANQADCgIIAgAAAA==.Midory:BAAANQAECgQICQAAAA==.Midranaira:BAAANQADCgEIAQAAAA==.Milda:BAAANQADCggJDQAAAA==.Milkymocha:BAAANQADCgYJDwAAAA==.Misscorona:BAAANQADCgcJFwAAAA==.Mistyque:BAAANQAECgQJBAAAAA==.Mithrandir:BAAANQADCgMJAgAAAA==.Mithrond:BAAANQADCgEIAQAAAA==.',
Mo='Monalea:BAAANQADCgQIBgABNQAECgYJEQACAAAAAA==.Morcant:BAAANQAECgEJAQAAAA==.Morianoley:BAAANQADCggJGwAAAA==.Morlu:BAAANQAECgQJBgAAAA==.Mortenson:BAAANQAECgQIBQAAAA==.Mortïmer:BAAANQAECgYIDgAAAA==.Mousee:BAAANQADCgcJFwAAAA==.',
Ms='Msdonnapally:BAAANQADCgYJFwAAAA==.',
Mu='Muffindr:BAAANQADCggICAAAAA==.',
My='Myxian:BAEANQAECgQIBAABNQAECgkJHwAHANEiAA==.',
['Mö']='Möñk:BAAANQADCgQIBQAAAA==.',
Na='Nala:BAAANQAECgEJAQAAAA==.Narallia:BAAANQADCgYICAAAAA==.Nargalad:BAAANQABCgQICAAAAA==.Narios:BAAANQAECgIIAgAAAA==.',
Ne='Nediem:BAAANQADCgQIBQAAAA==.Neral:BAAANQADCgMIAwAAAA==.Nexxicus:BAAANQADCgMJAwAAAA==.',
Ni='Nightmehr:BAABNQAECoEfAAIGAAkKuh8WIQAzAwAGAAkKuh8WIQAzAwAAAA==.Nightshade:BAAANQADCgcIDQAAAA==.',
No='Nosaj:BAAANQAECgYIDQAAAA==.Nostrodomus:BAAANQADCgMJAwAAAA==.Novalee:BAAANQADCgEIAQAAAA==.',
Ny='Nyki:BAAANQADCgMIAwAAAA==.',
Od='Odlaw:BAAANQADCgYIEQAAAA==.',
Ol='Olaria:BAAANQAECgEJAQABNQAECgIJAgACAAAAAA==.Olinax:BAAANQAECgcJEgAAAA==.',
Om='Omalmalha:BAAANQADCgQIBAAAAA==.',
On='Onedruidtion:BAAANQADCggJEQAAAA==.',
Or='Orheo:BAAANQADCgMJAgAAAA==.Orionmoon:BAABNQAECoEWAAMLAAcKbRCgTACqAQALAAcKbRCgTACqAQAKAAQKtgaIOwC9AAAAAA==.Orlos:BAAANQAECgIJAgAAAA==.Oräkk:BAABNQAECoEeAAIRAAgKzyFHAwASAwARAAgKzyFHAwASAwAAAA==.',
Pa='Padrin:BAAANQAECgEJAQAAAA==.Pandapaws:BAABNQAECoEhAAIYAAkKDCIRBQB/AwAYAAkKDCIRBQB/AwAAAA==.Papaflask:BAAANQAECgMIBQAAAA==.Parthal:BAAANQADCgEIAQAAAA==.Partyhardly:BAAANQAECgYJEAAAAA==.Pavle:BAAANQAECgIJAgAAAA==.',
Pd='Pdiddi:BAAANQAECgMJBgAAAA==.',
Pe='Pellaeon:BAABNQAECoEeAAMBAAkKexbnIABdAgABAAgKjhbnIABdAgAcAAUKeQyyWAASAQAAAA==.Pelt:BAABNQAECoEdAAIFAAgKgxYRFwBeAgAFAAgKgxYRFwBeAgAAAA==.Perseus:BAAANQADCgYJBgABNQAECgEIAQACAAAAAA==.Petmasta:BAAANQABCgEIAQABNQABCgQIBAACAAAAAA==.',
Ph='Pharaun:BAAANQADCggJEAABNQAECggJGwABANkFAA==.Phlan:BAEANQAECgQIBAAAAA==.Phrostir:BAAANQAECggIEAAAAA==.',
Pi='Picklechips:BAAANQADCgEIAQAAAA==.Pillgrimm:BAAANQAECgQJBAAAAA==.Pillsburyman:BAAANQAECgEIAQAAAA==.',
Po='Pointee:BAAANQADCgYICgAAAA==.Poisson:BAABNQAECoEXAAITAAkKawrJEgAhAgATAAkKawrJEgAhAgAAAA==.Pokoxo:BAAANQAECgcIEAABNQAECgIIAwACAAAAAA==.Pookiez:BAEANQAECgEIAQABNQAECgkJFwASAJIlAA==.',
Pr='Prancine:BAAANQADCggIDgABNQAFFAcIFwALAHEYAA==.Prescess:BAAANQADCgMJAwAAAA==.Providence:BAABNQAECoEZAAIEAAkKUB4yEADJAgAEAAkKUB4yEADJAgAAAA==.Prsr:BAAANQAECgEIBAABNQAFFAUICAABALMeAA==.',
Pu='Pudgypaws:BAAANQAECgQJBwAAAA==.',
Qu='Quickmend:BAAANQAECgQIBAAAAA==.Quickpal:BAAANQAECgQIBAAAAA==.Quickpaw:BAABNQAECoEcAAIaAAkK5BqHBwDOAgAaAAkK5BqHBwDOAgAAAA==.',
Ra='Raccoons:BAAANQADCgMIAwABNQAECgkJJAAXAEsbAA==.Radell:BAAANQAECgEIAQAAAA==.Rageproof:BAAANQAECgEIAgAAAA==.Ragged:BAAANQAECggIDQAAAA==.Raidbloom:BAEANQAFFAIIBAABNQAECggIHAANADkUAA==.Raidshock:BAEBNQAECoEcAAINAAgKORQ9NQAmAgANAAgKORQ9NQAmAgAAAA==.Rainsinger:BAAANQADCgYIGAAAAA==.Ramook:BAEANQADCggIFwAAAA==.Randomchar:BAABNQAECoEgAAIPAAgKow0sZwDHAQAPAAgKow0sZwDHAQAAAA==.Rankor:BAAANQADCgYIBgABNQAECggJHwAVAE8QAA==.Rastann:BAABNQAECoEiAAIPAAkKBiDVIgDbAgAPAAkKBiDVIgDbAgAAAA==.Ratsdrack:BAAANQADCgMIAwAAAA==.Rawrlas:BAAANQADCgMJAwABNQAECgIJAgACAAAAAA==.Razdor:BAAANQADCgUIBgAAAA==.',
Re='Reapertoo:BAABNQAECoEeAAMJAAkKeCTvCQAJAwAJAAkKTyDvCQAJAwABAAYKoh7SOAC8AQAAAA==.Recreant:BAAANQADCgcIDQAAAA==.Redbaron:BAAANQAECgcJEgAAAA==.Reetep:BAAANQADCggIFwAAAA==.Regeth:BAAANQADCggIFQAAAA==.Remily:BAAANQADCgUJBQABNQAECgkJGQAGALUZAA==.Revin:BAAANQAECgEJAQAAAA==.',
Ro='Rodned:BAAANQADCggJCAAAAA==.Rolas:BAAANQADCgEIAQABNQAECgIJAgACAAAAAA==.Rondle:BAAANQADCgEIAQABNQADCgcICAACAAAAAA==.Rottencorpse:BAAANQADCgQIBAAAAA==.Rozalin:BAABNQAECoEgAAIGAAgKdiIMLQAJAwAGAAgKdiIMLQAJAwAAAA==.Rozalinamoon:BAAANQADCgMIAwAAAA==.',
Ru='Rurouni:BAAANQADCgcIBwAAAA==.Rustystorm:BAAANQADCgMIAwAAAA==.Rustywarlock:BAAANQADCgUJBQAAAA==.',
Ry='Ryoshi:BAABNQAECoEdAAMeAAgK2x9qOwBIAgAeAAcKbSFqOwBIAgAfAAcKaxb3BAD2AQAAAA==.',
['Rò']='Ròòszy:BAAANQADCgYIBwAAAA==.',
Sa='Sacredstars:BAAANQADCggICAAAAA==.Sacredswords:BAABNQAECoEcAAMHAAgKfxnLSQBCAgAHAAgKfxnLSQBCAgAIAAEK0whQIwAxAAAAAA==.Sanguinius:BAAANQAECgcJEwAAAA==.Sapphiremist:BAAANQAECgIJAgAAAA==.Sayen:BAAANQAFFAEIAQAAAA==.',
Sc='Scachity:BAAANQAECgUIDgAAAA==.Scan:BAABNQAECoEZAAISAAkKEhlCIgCgAgASAAkKEhlCIgCgAgAAAA==.Schein:BAAANQAECgQIDAAAAA==.',
Se='Segsacute:BAAANQAECgcJBwAAAA==.Sepulchre:BAABNQAECoEbAAMBAAgK2QU2TQBOAQABAAgKvAQ2TQBOAQAJAAYKpgRFRgDYAAAAAA==.',
Sh='Shadesfault:BAAANQADCgMJBAAAAA==.Shadowhart:BAAANQADCgEIAQAAAA==.Shaeebulay:BAAANQABCgQIBQAAAA==.Shamaroo:BAAANQABCgUIBQAAAA==.Shaundakul:BAAANQAECgQJBwAAAA==.Shephion:BAAANQAECgQIBwABNQAECggJJgAaAHUlAA==.Shnozberries:BAAANQADCgEJAQAAAA==.Shockhart:BAAANQADCggIDwAAAA==.Shortnstack:BAAANQAECgEIAQAAAA==.Shãdow:BAAANQADCgUIBQAAAA==.',
Si='Simori:BAAANQADCgIIAgAAAA==.Sindrel:BAAANQAECgUIBQABNQAECgkJIAAbAKQgAA==.Siyurie:BAAANQADCgUJBQAAAA==.',
Sk='Skawalker:BAABNQAECoEjAAIDAAkKoCEOBABUAwADAAkKoCEOBABUAwAAAA==.',
Sl='Slaed:BAAANQADCgYIBwAAAA==.Slaynne:BAAANQAECgcJEwAAAA==.',
Sm='Smoky:BAAANQADCgEJAQAAAA==.Smäug:BAACNQAFFIEGAAIUAAQKRRvtAgBuAQAUAAQKRRvtAgBuAQA1AAQKgSEAAxQACQq3IjIDAFYDABQACQq3IjIDAFYDACAABQoIER4iADcBAAAA.',
Sn='Snailas:BAAANQADCgYJBwAAAA==.',
So='Sodomn:BAAANQADCgQIBAAAAA==.Solria:BAAANQAECgUICwAAAA==.Sonnytyphoon:BAAANQADCgYIBgAAAA==.',
Sp='Spex:BAAANQADCgUIBQAAAA==.',
St='Starnex:BAAANQADCgYIBgAAAA==.Statyrea:BAAANQADCgUIBQAAAA==.Styx:BAABNQAECoEqAAIRAAkKxSYKAAARBAARAAkKxSYKAAARBAAAAA==.',
Su='Sukfööt:BAABNQAECoEYAAIRAAgKcg+XDgCsAQARAAgKcg+XDgCsAQAAAA==.Sumbatadh:BAAANQAECgQIBQAAAA==.Sunnytyphoon:BAAANQAECgYIEAAAAA==.',
Sw='Swiftholy:BAAANQAECgYJEAAAAA==.Swiftmends:BAAANQAECgIIAgAAAA==.',
Sy='Sydahlis:BAAANQADCggJDAAAAA==.Sylvestris:BAAANQAECgUIDgAAAA==.',
Ta='Taiyana:BAAANQAECgQIBAAAAA==.Tangie:BAAANQADCggICgAAAA==.Tankjob:BAAANQAECgQJCAAAAA==.Tanklorswift:BAAANQADCgcIDwAAAA==.Tastemycrits:BAAANQADCggICAABNQAECgkJGAAPAKAcAA==.',
Td='Tdog:BAAANQADCggICwAAAA==.',
Te='Teapot:BAAANQABCgIJAgAAAA==.Tedoseirum:BAABNQAECoEYAAIEAAgK2SBxDgDgAgAEAAgK2SBxDgDgAgAAAA==.Terminal:BAAANQADCgcICAAAAA==.Terpyu:BAAANQADCgEIAQAAAA==.Texasbilly:BAAANQADCgYJDAAAAA==.Texasredneck:BAAANQADCgYJDAAAAA==.Texasslasher:BAAANQADCgYIBgAAAA==.',
Th='Thedtwo:BAAANQADCgcIDAAAAA==.Thorgarrus:BAABNQAECoEiAAIPAAkKbB3yHgDyAgAPAAkKbB3yHgDyAgAAAA==.',
Ti='Tigerwoodz:BAAANQAECgEIAQAAAA==.Timvoker:BAAANQADCgYIBgAAAA==.',
To='Toddie:BAAANQAECgYIDQAAAA==.Tommyj:BAAANQADCggICwAAAA==.Tormod:BAAANQAECgUJDAAAAA==.Tourmod:BAAANQAECgEIAQAAAA==.',
Tr='Trakkarz:BAAANQAECgIIAgAAAA==.Traps:BAAANQAECgEJAQAAAA==.Trashypanda:BAABNQAECoEeAAIGAAkKUiDBJgAfAwAGAAkKUiDBJgAfAwAAAA==.Trays:BAAANQADCgYIBgAAAA==.Tressilly:BAABNQAECoEZAAIGAAkKtRnrPgDOAgAGAAkKtRnrPgDOAgAAAA==.Trinagirl:BAAANQADCgYJBgAAAA==.Trinneries:BAAANQADCgcJBwAAAA==.Triná:BAAANQADCgYIBgABNQADCgYJBgACAAAAAA==.Trogdorr:BAABNQAECoEfAAMVAAgKTxCqBgDKAQAVAAgKTxCqBgDKAQAUAAQKegrmIADXAAAAAA==.Trutert:BAAANQADCgcJGAAAAA==.Tryana:BAAANQADCggJJgAAAA==.Trystiana:BAAANQADCgMJBAAAAA==.',
Tt='Ttania:BAAANQADCgYIDgAAAA==.',
Tw='Tweetwee:BAAANQADCgYIBgAAAA==.',
Ty='Tyledis:BAAANQADCggJEAABNQAECggJIAARAFMjAA==.Tyr:BAABNQAECoEeAAMSAAgKjx2VIACsAgASAAgKjx2VIACsAgAYAAIK1gkWugBpAAAAAA==.Tyrnova:BAAANQADCggICAAAAA==.',
['Tö']='Töshïrö:BAAANQADCgIIAgAAAA==.',
Uh='Uhope:BAAANQAECgEJAQAAAA==.',
Um='Umbravolt:BAABNQAECoEiAAIhAAkKNCN1AQCHAwAhAAkKNCN1AQCHAwAAAA==.',
Un='Unclezapp:BAAANQADCggJDgAAAA==.Unravel:BAAANQADCgEIAQAAAA==.Unrealcalorx:BAAANQADCgUIBQAAAA==.Unrealronin:BAAANQAECgIJAgAAAA==.',
Va='Vaeris:BAAANQADCgUJCwAAAA==.Vakero:BAAANQAECgIIAgAAAA==.Valess:BAAANQAECgMIBAAAAA==.Valros:BAAANQADCgYICgAAAA==.Vapor:BAAANQABCgIJAgAAAA==.Vaythan:BAAANQAECgcIBwAAAA==.',
Ve='Venchris:BAAANQADCggJCwAAAA==.Verica:BAAANQADCgEIAQAAAA==.',
Vh='Vhiz:BAAANQAECgUIDgAAAA==.',
Vi='Vibrance:BAAANQADCggJEAAAAA==.Victorius:BAAANQAECgMIAwAAAA==.Viridesa:BAAANQADCgYIEwAAAA==.',
Vo='Voidcore:BAAANQAFFAEJAQABNQAECgcIEAACAAAAAA==.Voidwalker:BAAANQADCgYICQABNQAECgkJJQAOAB8lAA==.',
Vy='Vysera:BAAANQADCgcIEQAAAA==.',
Wa='Warfarmer:BAAANQADCggIHAAAAA==.Warhawke:BAAANQADCgYJCQAAAA==.',
We='Werenal:BAAANQADCgcICwAAAA==.',
Wh='Whis:BAAANQAECgEJAQAAAA==.Whispernight:BAAANQADCgMJBQAAAA==.',
Wi='Widja:BAAANQADCgMJBQAAAA==.Wiimage:BAAANQAECgQIBQAAAA==.Wiivinelight:BAAANQADCgMIAwABNQAECgQIBQACAAAAAA==.Wildhus:BAAANQAECgYJEQAAAA==.',
Wy='Wyckdd:BAAANQADCgYIBgAAAA==.',
['Wå']='Wåffle:BAAANQAECgQIBAABNQAECgkJHAAZAKgiAA==.',
['Wî']='Wîca:BAABNQAECoEWAAIKAAcKjAuqIwCUAQAKAAcKjAuqIwCUAQAAAA==.',
Xa='Xantris:BAAANQADCgEIAQAAAA==.',
Xe='Xenowolf:BAAANQADCgYJCgABNQAECgEIAQACAAAAAA==.',
Xv='Xvire:BAAANQADCggIGAAAAA==.',
['Xû']='Xûrû:BAAANQAECgcICAAAAA==.',
Yc='Yce:BAAANQAECgEJAQAAAA==.',
Yo='Yoker:BAAANQAECgQIBAAAAA==.Yokersen:BAAANQAECgYIBgAAAA==.',
Za='Zaeladen:BAAANQADCggIFQAAAA==.Zalorea:BAAANQADCggJDwAAAA==.Zambonii:BAAANQAECgQIBgABNQAECgkJIQAdAJ8eAA==.Zamdeath:BAAANQADCgMIAwABNQAECgkJIQAdAJ8eAA==.Zamlock:BAABNQAECoEhAAMdAAkKnx4DDgD7AQAXAAcKvxxSMgBVAgAdAAYKRB0DDgD7AQAAAA==.Zanya:BAAANQADCggIFQAAAA==.',
Ze='Zeiko:BAAANQAECgcJCAAAAA==.Zestychip:BAAANQADCgYJDgAAAA==.Zeäl:BAAANQADCgUIBgAAAA==.',
Zh='Zhaoyun:BAAANQADCgUJCQAAAA==.',
Zi='Zilkir:BAEBNQAECoEZAAMPAAgK1BumMgCMAgAPAAgK1BumMgCMAgANAAcK0hOnQQDuAQAAAA==.Ziran:BAABNQAECoEYAAIbAAgKOCGZCAAEAwAbAAgKOCGZCAAEAwAAAA==.Zivadhim:BAAANQADCgIIAgAAAA==.',
Zl='Zlyth:BAAANQAECgIJAgAAAA==.',
Zz='Zzvzz:BAAANQADCggJEAAAAA==.',
['Är']='Ärtrix:BAAANQAECgEJAQAAAA==.',
['Èn']='Ènyo:BAAANQAECggICAAAAA==.',
['Øp']='Øptimusdayne:BAAANQADCgEIAgAAAA==.',
['ßl']='ßlaise:BAAANQABCgYICwAAAA==.',
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
