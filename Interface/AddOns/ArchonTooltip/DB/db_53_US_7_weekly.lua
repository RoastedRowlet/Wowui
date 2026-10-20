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

local lookup = {'DeathKnight-Unholy','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Havoc','Mage-Arcane','Priest-Holy','Monk-Windwalker','DeathKnight-Blood','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Frost','Paladin-Retribution','Druid-Balance','Priest-Shadow','Priest-Discipline','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Warrior-Protection','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Rogue-Assassination','Monk-Mistweaver','Rogue-Outlaw','Warlock-Destruction','Hunter-Marksmanship','Hunter-Survival','Druid-Feral','Evoker-Preservation','Druid-Guardian',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abnalem:BAAANQAECgEIAQAAAA==.',
Ac='Aceventuraa:BAAANQADCgEIAQAAAA==.',
Ad='Adramalech:BAAANQADCgQIBAABNQAFFAcIEgABAA8aAA==.',
Ae='Aeakos:BAAANQAECgIIAwAAAA==.Aeldon:BAAANQAECgIIAgAAAA==.',
Ag='Agavaen:BAAANQAECggICAAAAA==.',
Ai='Airese:BAAANQAECgIIAwABNQAECgQIBwACAAAAAA==.Airist:BAAANQAECgQIBwAAAA==.Aisele:BAABNQAECn8ZAAIDAAgKFANAIgDZAAADAAgKFANAIgDZAAAAAA==.',
Al='Alander:BAAANQAECgUIBQAAAA==.Alastor:BAAANQADCgcICwAAAA==.Alathir:BAABNQAECn8XAAIEAAcKUBc1ngDKAQAEAAcKUBc1ngDKAQAAAA==.Alluri:BAAANQAECggIDwAAAA==.Althemia:BAAANQAECgMIAwAAAA==.Alunamora:BAABNQAECn80AAIFAAoKRRwvCAC5AQAFAAoKRRwvCAC5AQAAAA==.',
Am='Ammaris:BAAANQAECgYICQAAAA==.',
An='Analani:BAAANQAECgQIBgAAAA==.Anali:BAAANQAECgUIBwAAAA==.Anduriel:BAAANQABCggICAAAAA==.Angis:BAAANQADCgQICAAAAA==.Angryheals:BAAANQAECgUIBwAAAA==.Annieq:BAAANQAECgQIBAAAAA==.Ansfrid:BAAANQAECgMIAwAAAA==.',
Ap='Apøllø:BAABNQAECn8kAAIGAAoKZAd3QQC0AQAGAAoKZAd3QQC0AQAAAA==.',
Aq='Aquatofana:BAAANQAECgQICAAAAA==.',
Ar='Aranel:BAAANQADCgYIBgAAAA==.Arcamancer:BAAANQAECgQIBwAAAA==.Arinthal:BAAANQAECgUIDwAAAA==.Arkenfel:BAAANQADCgQIBAAAAA==.Aroia:BAABNQAECn8aAAIHAAgK8Q7kVgAPAQAHAAgK8Q7kVgAPAQAAAA==.Arril:BAAANQAECgUIEQAAAA==.Artemissy:BAAANQADCgUICwAAAA==.Artiis:BAAANQAECggICAAAAA==.Artrimus:BAAANQAECgMIAwAAAA==.',
As='Asham:BAAANQAECgMIAwAAAA==.Ashlieghee:BAABNQAECn8rAAIIAAoKVR4gGgAMAwAIAAoKVR4gGgAMAwAAAA==.Ashron:BAAANQAECgcICwABNQAECgoKLwAHAJggAA==.Ashuraa:BAAANQADCgQIBAABNQAECggIFQAJAJ4MAA==.Astien:BAAANQAECgQICQAAAA==.Astralee:BAAANQADCggIDwAAAA==.',
Au='Audric:BAAANQADCgYIBwAAAA==.Auot:BAAANQAECgMIAwAAAA==.',
Av='Avelen:BAABNQAECn8XAAMBAAgKfx6+LQB7AgABAAgKfx6+LQB7AgAKAAEKfAr9xwA5AAAAAA==.Averlen:BAAANQAECgUICgAAAA==.Avha:BAAANQAECgQIDQAAAA==.Avistero:BAAANQAECgMIAwAAAA==.',
Ax='Axel:BAABNQAECn8xAAIGAAoKfR3fBAAUAgAGAAoKfR3fBAAUAgAAAA==.',
Ay='Aylden:BAABNQAECn8dAAMGAAgKwQ96QAC6AQAGAAgKwQ96QAC6AQALAAIK2AFlaABDAAAAAA==.Aylshm:BAAANQADCgYIFAAAAA==.Ayrene:BAAANQADCgcIBwABNQAECgQIBQACAAAAAA==.',
Az='Azaloth:BAAANQADCgMIAwAAAA==.Azenazar:BAAANQADCgEIAQAAAA==.Azog:BAAANQAECgEIAQAAAA==.Azsharianna:BAAANQABCggIEAAAAA==.',
Ba='Bailas:BAAANQAECgUIDAAAAA==.Battousai:BAAANQADCgMIAwAAAA==.Bazileth:BAAANQADCgYIBgAAAA==.',
Be='Bearistotle:BAAANQAECgEIAQAAAA==.Beastm:BAAANQAECgQIBAAAAA==.Beastmehr:BAAANQAECgQICQABNQAECgoKLwAHAD4gAA==.Beauregardl:BAAANQAECgEJAQAAAA==.Bellina:BAAANQADCgcIBwAAAA==.Belwyn:BAAANQADCgUIBgAAAA==.Benjofamin:BAAANQAECgYIBwAAAA==.',
Bi='Bitesize:BAEBNQAECn8uAAMMAAoKZSNDBgBoAgAMAAoKZSNDBgBoAgANAAEK1yT8KQBhAAAAAA==.',
Bl='Blakelivly:BAEBNQAECn8mAAQOAAoK2R9dJgDqAgAOAAkK2R9dJgDqAgAPAAkKah1HKADDAgAQAAUKMBpjIABYAQAAAA==.Blashster:BAABNQAECn8vAAMHAAoKmCDOGQBuAwAHAAoKmCDOGQBuAwADAAEKPxnMQgA+AAAAAA==.Blightsize:BAEANQADCgMIAwABNQAECgoKLgAMAGUjAA==.Blkplayge:BAAANQADCgMIAwAAAA==.',
Bo='Bonemilker:BAACNQAFFH8SAAMBAAcKDxrUAQA7AgABAAYK4R7UAQA7AgARAAUKkBUsCQBaAQA1AAQKfy8AAxEACQqoJXcMADIDABEACQpUJXcMADIDAAEABQpMHK9dAJkBAAAA.Bonkdaddy:BAABNQAECn8eAAISAAkKFh/TOQDqAgASAAkKFh/TOQDqAgAAAA==.Bopeep:BAAANQAECgcICwAAAA==.',
Br='Brandt:BAAANQABCgQICAAAAA==.Breelyssa:BAAANQAECgQIBgAAAA==.Brego:BAAANQAECgIIAgAAAA==.Brenna:BAAANQAECgMIAwABNQAECgkJJwATAHcOAA==.Brewslèé:BAAANQADCgMIAgAAAA==.Brighter:BAABNQAECn8zAAQUAAoKKRkOHQBaAgAUAAkKrBgOHQBaAgAIAAYKlxY0kABmAQAVAAYKshITDgBPAQAAAA==.Brightsize:BAEANQAECgYIDAABNQAECgoKLgAMAGUjAA==.Broncopally:BAAANQADCgQIBAAAAA==.Brótien:BAAANQADCggICAABNQAECgYIBgACAAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bunnka:BAAANQADCgYIBgAAAA==.Bunnyparade:BAAANQADCgYIDAAAAA==.',
Ca='Cakesdruid:BAAANQAECgQICAAAAA==.Caledwar:BAABNQAECn8ZAAISAAYKwAqrgQDKAAASAAYKwAqrgQDKAAAAAA==.Calrissa:BAAANQADCgMIAwABNQAECgcIFwAEAFAXAA==.Calthirstrap:BAACNQAFFH8PAAQBAAYKvhezCwBSAQABAAQKKx2zCwBSAQARAAEKdwcnDQBTAAAKAAEKAADpNQAnAAA1AAQKfy8AAgEACgoeJO0LAFsDAAEACgoeJO0LAFsDAAAA.Carare:BAAANQADCgcICgAAAA==.Carnàge:BAAANQAECgMIBgAAAA==.Casterrata:BAAANQADCggICAAAAA==.',
Ce='Ceefack:BAAANQAECgQICgAAAA==.Cethin:BAAANQAECgQICAAAAA==.',
Ch='Chaargee:BAABNQAECn8aAAMMAAgKWQxPTQAEAQAMAAgKWQxPTQAEAQANAAIKywclGQAmAAAAAA==.Chaosshot:BAAANQAFFAEIAQAAAA==.Cheedar:BAACNQAFFH8HAAMWAAMKzQtDGgDNAAAWAAMKzQtDGgDNAAAXAAEKTABgFQAYAAA1AAQKfxwAAhYACQq8EB9TACECABYACQq8EB9TACECAAAA.Chelaria:BAAANQAECgMIBQAAAA==.Cherylindrea:BAAANQADCgUIDgAAAA==.Chillwombat:BAAANQADCggIIgAAAA==.Chumlei:BAAANQADCgcIBwAAAA==.',
Ck='Ckz:BAAANQAECggIBAAAAA==.',
Cl='Claydemon:BAAANQAECgQIDAAAAA==.Clayvicar:BAABNQAECn84AAMIAAoKWQscawDdAQAIAAoKWQscawDdAQAUAAIKVgNGaQBcAAAAAA==.',
Co='Convoid:BAAANQABCggIHgABNQABCggINgACAAAAAA==.Coridane:BAABNQAECn8cAAIIAAcKvQ5tjQBuAQAIAAcKvQ5tjQBuAQAAAA==.Corrum:BAAANQAECgUICgAAAA==.Corwinfiron:BAABNQAECn8eAAIHAAkK4whY9gCfAQAHAAkK4whY9gCfAQAAAA==.',
Cr='Crosse:BAAANQAECgQIBwAAAA==.Cruellà:BAAANQADCgYIEwAAAA==.Cryptcrawler:BAAANQAECgEIAgAAAA==.',
Cu='Cuddleme:BAAANQADCgcIBwAAAA==.Curkage:BAAANQADCgQIBQAAAA==.',
Cy='Cythera:BAACNQAFFH8MAAIQAAUKVxuxAgCZAQAQAAUKVxuxAgCZAQA1AAQKfysAAhAACQo0JmkDAGgDABAACQo0JmkDAGgDAAAA.',
['Cá']='Cámus:BAABNQAECn8gAAISAAYKHxUIcgDiAAASAAYKHxUIcgDiAAAAAA==.',
Da='Daammy:BAAANQAECgIIBAAAAA==.Daayumgurl:BAAANQADCgYIBgAAAA==.Dagren:BAAANQADCggIHgAAAA==.Daisy:BAAANQABCggINQABNQABCggINgACAAAAAA==.Dakdor:BAAANQADCgMIAwAAAA==.Daphine:BAAANQADCgUIDwAAAA==.Darimonk:BAAANQADCgEIAQABNQADCgYICgACAAAAAA==.Darivara:BAAANQADCgYICgAAAA==.Darkbeautie:BAABNQAECn8VAAIYAAcKzAZbHwDtAAAYAAcKzAZbHwDtAAAAAA==.Darkcarbon:BAABNQAECn8YAAILAAUKQBZ8GwDSAAALAAUKQBZ8GwDSAAAAAA==.Darkchylde:BAAANQADCgUIBQABNQAECgUIGAALAEAWAA==.Darkplazzma:BAAANQAECgQIBAAAAA==.',
De='Deathmask:BAAANQAECgMIAwAAAA==.Deathspal:BAABNQAECn8iAAMSAAgK2xIHqgDMAQASAAgK2xIHqgDMAQAXAAIKpQjBZwBFAAAAAA==.Defeated:BAAANQABCgYIBgAAAA==.Dementedfun:BAAANQAECggICAAAAA==.Dessembrae:BAABNQAECn88AAIZAAoKUSORAQC0AwAZAAoKUSORAQC0AwAAAA==.Devont:BAAANQADCgUIBQAAAA==.Dewkiez:BAEBNQAECn8fAAIOAAoKkCUVBgC5AwAOAAoKkCUVBgC5AwAAAA==.',
Di='Diabolicarl:BAABNQAECn8pAAIGAAkKKgoLFwA2AQAGAAkKKgoLFwA2AQAAAA==.Dimencius:BAAANQAECgEIAQAAAA==.Diri:BAAANQAECgYICAABNQAECgkJHwAYAMELAA==.',
Dm='Dmmeforpi:BAAANQADCgYICgABNQAFFAEIAQACAAAAAA==.',
Do='Docphanan:BAAANQAECgEIAgAAAA==.Doesntheal:BAAANQABCgIIBAAAAA==.Dookiez:BAEANQAECggIEgABNQAECgoKHwAOAJAlAA==.Doubledragin:BAABNQAECn8hAAMaAAcKKRTuFwDKAQAaAAcKCRTuFwDKAQAbAAQKpRQuFgDPAAAAAA==.',
Dr='Dracantar:BAAANQADCggIEQAAAA==.Dractini:BAAANQADCgcICgABNQAFFAkJIgAIAAUVAA==.Dragfan:BAAANQADCgQJBAAAAA==.Dragonbelly:BAAANQABCggINgAAAA==.Dragondeez:BAAANQABCgQIBQABNQAECgQICQACAAAAAA==.Dragore:BAABNQAECn8eAAIMAAgKhwznpQC+AQAMAAgKhwznpQC+AQAAAA==.Druidgirls:BAABNQAECn89AAIFAAoKdRxGAwBuAgAFAAoKdRxGAwBuAgAAAA==.',
Du='Duelist:BAAANQAECggIDAAAAA==.Dupree:BAAANQADCgQIBQAAAA==.Durogdem:BAAANQADCgYIBgAAAA==.Duskfire:BAAANQABCgQICAAAAA==.',
Dw='Dwarnter:BAAANQADCgYIBQAAAA==.',
Ea='Earthaggie:BAAANQADCgUIDgAAAA==.',
Ec='Echlipse:BAAANQAECgQICgABNQAECgkJKQAXALAhAA==.',
Ed='Ederon:BAAANQABCggICAAAAA==.Edirae:BAAANQAECgIIAgABNQAECgoKKgAPAJQaAA==.',
El='Elenora:BAABNQAECn8kAAITAAgKsQYsYQBKAQATAAgKsQYsYQBKAQAAAA==.Ellea:BAAANQAECgUICgAAAA==.Ellesmere:BAAANQAECgIIAgABNQAFFAkJJAAWAKIeAA==.Elye:BAAANQAECgcIDwAAAA==.',
Em='Emer:BAAANQAECgcICgAAAA==.Emiru:BAAANQADCgUJBgAAAA==.',
En='Encore:BAABNQAECn88AAIFAAoKOAw8DgBcAQAFAAoKOAw8DgBcAQAAAA==.',
Eo='Eousphorus:BAACNQAFFH8HAAIHAAMKPAwfEQDWAAAHAAMKPAwfEQDWAAA1AAQKfz0AAwcACgrZG0gQAOUBAAcACgrZG0gQAOUBAAMAAgr9CLw6AFQAAAAA.',
Er='Erathen:BAAANQADCggICgAAAA==.Eryanna:BAAANQAECgIIBgAAAA==.',
Es='Esplan:BAEBNQAECn8VAAIHAAgKFyGjQgD/AgAHAAgKFyGjQgD/AgABNQAECgoKJgAOANkfAA==.',
Eu='Euden:BAAANQADCgQIBAAAAA==.',
Ev='Evelleion:BAAANQAECgYIDwAAAA==.',
Ex='Excedrin:BAAANQADCgIIAgAAAA==.Exoticlord:BAAANQAECgQIBAAAAA==.',
Fe='Felhayde:BAAANQADCgYIBgAAAA==.Felicity:BAAANQADCggIDAAAAA==.Fenryyr:BAAANQADCgYJBwAAAA==.',
Fi='Fierygrace:BAAANQADCgcIEAAAAA==.Firburger:BAAANQAECgQICgAAAA==.Fischl:BAAANQAECgQIBgAAAA==.Fitzmagic:BAAANQAECgcIBwAAAA==.',
Fl='Flameth:BAABNQAECn87AAIcAAkKLA/fXABBAgAcAAkKLA/fXABBAgAAAA==.Fling:BAAANQADCgMIAwAAAA==.Flirtywombat:BAAANQAECgIIBAAAAA==.',
Fu='Fujitto:BAAANQADCgIIAgAAAA==.Fumanchu:BAABNQAECn8nAAIZAAoKfBqKCADJAgAZAAoKfBqKCADJAgAAAA==.Fuzugchu:BAAANQAECgcICwABNQAECgoKJwAZAHwaAA==.',
Ga='Gaamora:BAAANQADCgUIEwAAAA==.Gabooda:BAAANQADCgUIBQABNQAECgMIBAACAAAAAA==.Gainsborough:BAABNQAECn8uAAMSAAoKzR8CKAAmAwASAAoKzR8CKAAmAwAXAAMKaRR3TwCpAAABNQAFFAYIEwAPAOUUAA==.Gamegg:BAAANQAECgUICgAAAA==.Garagos:BAABNQAECn85AAIdAAoKahz/FADTAgAdAAoKahz/FADTAgAAAA==.',
Ge='Gebuss:BAABNQAECn8wAAIdAAoK1R9CCABSAwAdAAoK1R9CCABSAwAAAA==.Gempally:BAAANQADCgIIAgAAAA==.',
Gi='Gilford:BAAANQAECgUICgAAAA==.',
Gl='Glenraven:BAAANQAECgQIBgAAAA==.',
Go='Golokan:BAAANQADCgYIDAAAAA==.Goochaddi:BAABNQAECn8bAAISAAoKcBlLfAAyAgASAAoKcBlLfAAyAgAAAA==.Gorgunga:BAAANQAECgUIBQAAAA==.Gozer:BAAANQABCgcICgAAAA==.',
Gr='Grolden:BAAANQAECgQICAAAAA==.Grïpnrïp:BAAANQAECgEIAQAAAA==.',
Gu='Gunnerrata:BAAANQAECgQICAAAAA==.',
Ha='Hahalua:BAAANQAECgcICgAAAA==.Halieight:BAAANQAECgIIAgABNQAECgoKPgAHAGAcAA==.Halifaxx:BAABNQAECn8+AAIHAAoKYBxaCgAlAgAHAAoKYBxaCgAlAgAAAA==.Halifive:BAAANQADCgIIAgABNQAECgoKPgAHAGAcAA==.Haliseven:BAAANQADCgQIBAABNQAECgoKPgAHAGAcAA==.Halisix:BAAANQADCgIIAgABNQAECgoKPgAHAGAcAA==.Halithree:BAAANQADCgYICgABNQAECgoKPgAHAGAcAA==.Halitwo:BAAANQADCggICgABNQAECgoKPgAHAGAcAA==.Hapiagin:BAAANQAECgUICgAAAA==.Haraboo:BAAANQAECgUIBwAAAA==.Harmaa:BAAANQAECgcIDgAAAA==.Hauron:BAAANQAECgUIBwABNQAECgQICAACAAAAAA==.Havengul:BAAANQAECggIEAAAAA==.Hawknor:BAAANQAECgUIEAAAAA==.',
He='Healthcare:BAABNQAECn8xAAMPAAoKqRgBDwDkAQAPAAoKqRgBDwDkAQAOAAUKzwx4xgAFAQABNQAFFAkJIgAIAAUVAA==.Healthplan:BAAANQADCgYIBgABNQAECgkJHgAWAHYSAA==.Heartilly:BAACNQAFFH8TAAIPAAYK5RT3BwDVAQAPAAYK5RT3BwDVAQA1AAQKfzgAAg8ACgriIbkOAEwDAA8ACgriIbkOAEwDAAAA.Herm:BAABNQAECn9BAAMeAAoK4SSmAQCzAwAeAAoK4SSmAQCzAwAJAAcKDhrSIwAHAgAAAA==.',
Ho='Holyfu:BAAANQAECgUIDAABNQAECgoKJwAZAHwaAA==.Holymidget:BAAANQAECgEIAQAAAA==.Holysky:BAAANQAECgQIDwAAAA==.Holytim:BAABNQAECn8xAAQIAAoKECAQEQDuAQAIAAoKECAQEQDuAQAVAAcKhRWCCADdAQAUAAIK0A2iaABeAAAAAA==.Honeypackz:BAAANQAECgcIDAAAAA==.Honnik:BAAANQABCgIIAgAAAA==.Hotbarbie:BAAANQADCgIIAgAAAA==.Hotpink:BAAANQADCgUIDQAAAA==.How:BAABNQAECn8fAAMeAAkK7B/mCAD+AgAeAAkK7B/mCAD+AgAJAAIKAA4yXgBoAAAAAA==.',
Hu='Humongulus:BAABNQAECn8VAAIJAAgKngxDMACVAQAJAAgKngxDMACVAQAAAA==.',
Ic='Ickysins:BAAANQAECgEIAQAAAA==.Ickystix:BAAANQADCgMIAwABNQAECgQICQACAAAAAA==.',
Ig='Ignored:BAABNQAECn8ZAAMSAAoKPxSgKgB/AQASAAoKPxSgKgB/AQAWAAQKrgeifgBWAAAAAA==.Ignöred:BAABNQAECn8ZAAIMAAcKexjNkwDrAQAMAAcKexjNkwDrAQAAAA==.',
Il='Ila:BAAANQADCgIIAgAAAA==.Ilidra:BAAANQAECgEIAQAAAA==.Illaine:BAAANQADCgYIBgAAAA==.Illidæn:BAABNQAECn8kAAILAAkKgg3YLgDKAQALAAkKgg3YLgDKAQAAAA==.',
Im='Imgonaruneya:BAAANQAECgUICQAAAA==.Imos:BAAANQABCgUIBAAAAA==.Imperîus:BAAANQADCgUIBQABNQAFFAcIEgABAA8aAA==.',
In='Inaniel:BAABNQAECn8aAAILAAgKcBrEHwBQAgALAAgKcBrEHwBQAgAAAA==.Inq:BAABNQAECn83AAMHAAoKviGuBACVAgAHAAoKviGuBACVAgADAAEKLgu4TgAqAAAAAA==.',
Ir='Iridaceaë:BAABNQAECn8pAAIIAAoKvhlYKQBYAQAIAAoKvhlYKQBYAQABNQAECgcIDAACAAAAAA==.Iryris:BAAANQAECgMIBwAAAA==.',
Is='Isedeath:BAABNQAECn80AAQBAAoKgRXZSQDuAQABAAkKQBXZSQDuAQARAAkKIgtLRwChAQAKAAEKOB2QwwBBAAAAAA==.Istvankh:BAAANQABCgMIBAABNQADCgEIAQACAAAAAA==.',
Ja='Jaholin:BAAANQAECggIEgAAAA==.Jarhead:BAAANQADCgIIAgAAAA==.Jarrhead:BAAANQAECgQIBwAAAA==.Jaxarus:BAAANQADCgEIAQAAAA==.',
Je='Jenaveive:BAABNQAECn8YAAIEAAgK4QqJpAC9AQAEAAgK4QqJpAC9AQAAAA==.Jethoisi:BAAANQAECgYIEAABNQAFFAYIDgAXADMIAA==.Jexi:BAAANQADCgYJBgABNQAECgUICQACAAAAAA==.',
Jn='Jnex:BAABNQAECn8XAAISAAkKBiHUCABTAgASAAkKBiHUCABTAgAAAA==.',
Jo='Jongani:BAABNQAFFH8OAAIXAAYKMwjBBgAbAQAXAAYKMwjBBgAbAQAAAA==.Jookiez:BAEANQAECgYIBwABNQAECgoKHwAOAJAlAA==.',
Jr='Jrrtrolkien:BAAANQADCgQIBAABNQAECgEIAgACAAAAAA==.',
Ju='Judgemehr:BAAANQAECgcIDwABNQAECgoKLwAHAD4gAA==.Judgepain:BAAANQAECggICAAAAA==.Judgmental:BAABNQAECn8sAAIWAAkKAB8bFgAmAwAWAAkKAB8bFgAmAwAAAA==.Justine:BAAANQAECgUICgAAAA==.',
Ka='Kaboni:BAAANQAECgMIBAAAAA==.Kaelthorn:BAAANQAECgUIBQAAAA==.Kaelysong:BAAANQADCgUJDQAAAA==.Kageansatsu:BAAANQAECgUICgAAAA==.Kairah:BAAANQAECgEIAgAAAA==.Kaivig:BAAANQADCgYIBgAAAA==.Kalï:BAAANQADCgYICQAAAA==.Karlil:BAAANQAECgQIEAAAAA==.Kasiene:BAAANQAECgEIAQAAAA==.Kasnay:BAAANQADCgQIBgAAAA==.Kateria:BAAANQADCgQIBAAAAA==.Kathenset:BAABNQAECn8WAAIaAAcKmQLPDQCCAAAaAAcKmQLPDQCCAAAAAA==.Kazenseth:BAAANQADCgEIAQAAAA==.Kazeral:BAACNQAFFH8MAAIdAAUKPRRNCwBJAQAdAAUKPRRNCwBJAQA1AAQKfxwABB0ACgqtFusSAC4BAB8ABwo+EloMAJIBAB0AAwrrH+sSAC4BABgAAwq/AWRKAGcAAAAA.Kazzi:BAAANQADCgIIAgAAAA==.',
Ke='Keener:BAABNQAECn8gAAIMAAkKChlICwAMAgAMAAkKChlICwAMAgAAAA==.Kelvin:BAAANQABCgQIBAAAAA==.Kelyana:BAAANQABCgMIAwAAAA==.Kerrla:BAAANQAECgEIAQABNQAFFAUIDAAdAD0UAA==.Keylleth:BAAANQADCgYJDwAAAA==.',
Kh='Khalanie:BAABNQAECn8mAAIYAAgKTwmOGwAGAQAYAAgKTwmOGwAGAQAAAA==.Khamnox:BAABNQAECn8VAAMcAAgKHhKmWADRAAAcAAcKpRGmWADRAAAgAAIKfRRkXABtAAAAAA==.Khionia:BAAANQAECgIIAgAAAA==.',
Ki='Kidthefrist:BAAANQADCgUIBQAAAA==.Kielnmsoftly:BAAANQADCgYIBgAAAA==.Kilaia:BAAANQAECgEIAgAAAA==.Kirru:BAAANQAECgUICwAAAA==.',
Kn='Knoble:BAAANQADCgQIBAAAAA==.Knufflewolf:BAAANQADCgcIBgABNQAECgUICgACAAAAAA==.',
Ko='Kokatoes:BAAANQAECgIIAgABNQAECgkJKQAMADcQAA==.Korabas:BAAANQAECgQIBQABNQAECgoKPAAZAFEjAA==.',
Kr='Kreaton:BAAANQAECggIDAAAAA==.Kryt:BAABNQAECn8pAAIPAAoKbxx7MQCbAgAPAAoKbxx7MQCbAgAAAA==.',
Ku='Kuchikix:BAAANQABCgEIAQAAAA==.Kuponia:BAAANQABCgIIAgAAAA==.',
Kw='Kwichangpain:BAAANQADCgcIDQAAAA==.',
Kx='Kxchiki:BAABNQAECn8nAAIWAAkKsRIYRwBKAgAWAAkKsRIYRwBKAgAAAA==.',
['Kã']='Kãz:BAAANQADCgYICAAAAA==.',
La='Laaklem:BAAANQAECgEJAQAAAA==.Laei:BAAANQADCggIEAAAAA==.Laserfingies:BAAANQAECgMIAwAAAA==.Lastsun:BAAANQADCgIIAgAAAA==.Lavacakes:BAABNQAECn86AAMPAAoK/B62HAD7AgAPAAoK/B62HAD7AgAOAAIKsgQ2HAFXAAAAAA==.Lawndartz:BAAANQADCggJDgAAAA==.',
Le='Lelantoz:BAABNQAECn8iAAIEAAcKZAYyQQAzAQAEAAcKZAYyQQAzAQAAAA==.Leliel:BAAANQABCgUICgAAAA==.Leqoofus:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
Li='Lidan:BAABNQAECn8nAAIdAAgK0Q4ECwB2AQAdAAgK0Q4ECwB2AQAAAA==.Liebli:BAABNQAECn8VAAIcAAkKvhzJCQALAgAcAAkKvhzJCQALAgAAAA==.Liltank:BAAANQAECgIIAgAAAA==.Limity:BAAANQAECgQICAAAAA==.Linaeni:BAAANQADCgIIAgAAAA==.Linaradice:BAAANQAECgUIDAAAAA==.Lixandra:BAAANQADCgEIAQAAAA==.',
Lo='Logyn:BAAANQADCgQICgAAAA==.Lonelyspark:BAAANQADCgQICQAAAA==.Lonnias:BAAANQAECgYIEwAAAA==.Lotsalock:BAAANQADCgUIBQAAAA==.',
Lu='Lucicelse:BAAANQADCgYIDwAAAA==.Lucifur:BAAANQADCgMIAwAAAA==.Luna:BAABNQAECn8gAAIFAAgKvw0KLwCiAQAFAAgKvw0KLwCiAQAAAA==.Lunarluvgood:BAEBNQAECn8jAAITAAkKFSPsCACHAwATAAkKFSPsCACHAwABNQAECgoKJgAOANkfAA==.',
Ly='Lyrelia:BAAANQAECgIIAwAAAA==.',
Ma='Madbones:BAAANQADCgYIDAABNQAECgkJHgAWAHYSAA==.Madmetal:BAABNQAECn8eAAMWAAkKdhJOWgAKAgAWAAkKdhJOWgAKAgASAAEK3QPqwQEnAAAAAA==.Mado:BAAANQAECgcIDAAAAA==.Madstorm:BAAANQADCggICAAAAA==.Magefood:BAAANQAECgQIBgABNQAECgcICwACAAAAAA==.Magicky:BAAANQAECgQICQAAAA==.Mahlkier:BAAANQADCgUIDwAAAA==.Mahlkierson:BAAANQADCgQIAwAAAA==.Maikego:BAAANQAECgUIDAAAAA==.Mairadin:BAAANQAECgIIAgAAAA==.Malchelo:BAAANQAECgQIBgAAAA==.Malfhunter:BAABNQAECn8uAAIhAAoKXRnLCgA9AQAhAAoKXRnLCgA9AQAAAA==.Malfshammy:BAAANQADCgcIBwAAAA==.Maligosa:BAAANQADCgQIBgAAAA==.Manager:BAAANQADCggIBwAAAA==.Mangolassi:BAAANQAECgUICAAAAA==.Manto:BAAANQAECgQIBAAAAA==.Mantodea:BAAANQADCgcIFgAAAA==.Manup:BAAANQADCgcIEAAAAA==.Marmin:BAABNQAECn8mAAIDAAkKBhaHCgAgAgADAAkKBhaHCgAgAgAAAA==.Marossa:BAAANQADCgcIBgAAAA==.Marymae:BAAANQADCgUIDgAAAA==.Mattwm:BAAANQAECgEIAQAAAA==.Maîa:BAAANQADCggICAAAAA==.',
Me='Meatstick:BAAANQADCgIIAgABNQADCgQIBQACAAAAAA==.Meikai:BAAANQAECgUICAAAAA==.Melillia:BAAANQAECggIDQAAAA==.Melted:BAACNQAFFH8QAAIHAAYK8RepDgACAgAHAAYK8RepDgACAgA1AAQKfyoAAwcACgrIImocAGUDAAcACgq2H2ocAGUDAAMAAQo2IBM4AF0AAAAA.Merdocki:BAABNQAECn8zAAMcAAoKIR/iMwC6AgAcAAkKnB3iMwC6AgAgAAQKqRw/IQBnAQAAAA==.Merdra:BAABNQAECn8pAAIXAAkKsCFPBQBcAwAXAAkKsCFPBQBcAwAAAA==.Merdre:BAABNQAECn8/AAQIAAoKbhvFCgA4AgAIAAoKhxrFCgA4AgAVAAQKLxmWEgD+AAAUAAUKNQV9TwDVAAAAAA==.',
Mi='Michealhunt:BAAANQADCgIIAgAAAA==.Midory:BAAANQAECgQICQAAAA==.Midranaira:BAAANQADCgEIAQAAAA==.Milda:BAAANQAECgYICQAAAA==.Milkymocha:BAAANQAECgQIBwAAAA==.Misscorona:BAAANQAECgUIBwAAAA==.Mistyque:BAAANQAECgUICgAAAA==.Mithrandir:BAAANQADCgUIBAAAAA==.Mithrond:BAAANQADCgEIAQAAAA==.',
Mo='Modercai:BAAANQAECgQIBAAAAA==.Monalea:BAAANQAECgIIAgABNQAECgoKKAAGAEgRAA==.Monkshadow:BAAANQAECgcICAAAAA==.Monkydleafy:BAAANQADCgQIAwABNQAECgEIAgACAAAAAA==.Morcant:BAAANQAECgUIEAAAAA==.Morianoley:BAAANQAECgMIBgAAAA==.Morlu:BAAANQAECgYIEAAAAA==.Mortenson:BAAANQAECgYIDwAAAA==.Mortïmer:BAABNQAECn8fAAMUAAkKSBWtHwA+AgAUAAkKSBWtHwA+AgAIAAMKXw232QCbAAAAAA==.Mousee:BAAANQAECgIIAgAAAA==.',
Ms='Msdonnapally:BAAANQAECgMIAwAAAA==.',
Mu='Muffindr:BAAANQAECgMIAwABNQAECgQIBAACAAAAAA==.',
My='Mysticmage:BAAANQAECgUIDAAAAA==.Myxian:BAEANQAECgQIBQABNQAECgoKLgAMAGUjAA==.',
['Mö']='Möñk:BAAANQADCgQIBQAAAA==.',
Na='Nala:BAAANQAECgMIAwAAAA==.Narallia:BAAANQADCgYICAAAAA==.Nargalad:BAAANQABCgQICAAAAA==.Narios:BAAANQAECgYIEAAAAA==.Natureshogun:BAAANQAECgUIBQAAAA==.',
Ne='Nediem:BAAANQADCgQIBQAAAA==.Nexxicus:BAAANQADCgQIBwAAAA==.',
Ni='Nightmehr:BAABNQAECn8vAAIHAAoKPiAhFADGAQAHAAoKPiAhFADGAQAAAA==.Nightshade:BAAANQADCgcIDQAAAA==.Nippy:BAAANQADCgUICQAAAA==.',
No='Nored:BAAANQADCgEIAQAAAA==.Normalguyman:BAAANQABCgEIAgAAAA==.Nosaj:BAAANQAECgYIDQAAAA==.Nostrodomus:BAAANQADCgQIBwAAAA==.Novalee:BAAANQADCgIIAwAAAA==.',
Nu='Nuan:BAAANQADCgMIAwAAAA==.',
Ny='Nyki:BAAANQADCgMIAwAAAA==.',
Od='Odlaw:BAAANQAECgQIDgAAAA==.',
Ol='Olaria:BAAANQAECgEIAQABNQAECgUIFAAhACYOAA==.Olinax:BAABNQAECn8mAAQdAAoKLhd2CQCIAQAdAAkKRxZ2CQCIAQAfAAUKXxWoDwAtAQAYAAEKAACbVQAtAAAAAA==.',
Om='Omalmalha:BAAANQAECgMIBAAAAA==.',
On='Onedruidtion:BAAANQAECgIIBQAAAA==.',
Or='Orheo:BAAANQADCgcICwAAAA==.Orionmoon:BAABNQAECn8dAAMIAAkKRA7EcgDEAQAIAAkKRA7EcgDEAQAUAAYKsgfYSAD5AAAAAA==.Orlos:BAABNQAECn8UAAMhAAUKJg5dJQB5AAAEAAUKJg5l4ABAAQAhAAQK6wRdJQB5AAAAAA==.Oräkk:BAABNQAECn8pAAMZAAkKqSPCBQASAwAZAAkKqSPCBQASAwAMAAIKxhJFKAGGAAAAAA==.',
Pa='Padrin:BAAANQAECgQIDwAAAA==.Pandapaws:BAACNQAFFH8KAAIPAAMKaxm2CQDpAAAPAAMKaxm2CQDpAAA1AAQKfzIAAw8ACgpaJDcFAJ4DAA8ACgpaJDcFAJ4DAA4AAwpVB8/8AJgAAAAA.Papaflask:BAABNQAECn8bAAIIAAkKMxl0DQAUAgAIAAkKMxl0DQAUAgAAAA==.Parthal:BAAANQADCgEIAQAAAA==.Partyhardly:BAABNQAECn8rAAIXAAoK9hLnHgDwAQAXAAoK9hLnHgDwAQAAAA==.Pavetta:BAAANQAECgUIBQAAAA==.Pavle:BAAANQAECgQIBAAAAA==.',
Pd='Pdiddi:BAABNQAECn8VAAMBAAkKtRfQTADhAQABAAUKHiHQTADhAQARAAgKgBNDQQDBAQAAAA==.',
Pe='Pellaeon:BAABNQAECn84AAMKAAoK8BY9BQD4AQAKAAoKzhU9BQD4AQABAAgKTxWKTADiAQAAAA==.Pelt:BAABNQAECn8nAAILAAkK0RdmGwB8AgALAAkK0RdmGwB8AgAAAA==.Perseus:BAAANQAECgEIAQABNQAECgcIFQAYAMwGAA==.Petmasta:BAAANQABCgEIAQAAAA==.',
Ph='Pharaun:BAAANQAECgQIBQABNQAECgoKNwABAJQIAA==.Phlan:BAEANQAECgQIBAAAAA==.Phrostir:BAAANQAECggIEAAAAA==.',
Pi='Picklechips:BAAANQADCgEIAQAAAA==.Pillgrimm:BAAANQAECgQICwAAAA==.Pillsburyman:BAAANQAECgQICAAAAA==.',
Po='Pogue:BAAANQADCgIIAgAAAA==.Pointee:BAAANQADCgYICgAAAA==.Poisson:BAABNQAECn8fAAIYAAkKwQvYGgABAgAYAAkKwQvYGgABAgAAAA==.Pokoxo:BAABNQAECn8xAAQXAAoKMBmZFABeAgAXAAoKMBmZFABeAgAWAAYKVQmiwwD0AAASAAQKRwmiOQHEAAABNQAECgIIAwACAAAAAA==.Pookiez:BAEANQAECgIIBgABNQAECgoKHwAOAJAlAA==.',
Pr='Prancine:BAAANQAECgQIBAABNQAFFAkJIgAIAAUVAA==.Prescess:BAAANQADCgUICAAAAA==.Providence:BAABNQAECn80AAIGAAoKJB2eAwBEAgAGAAoKJB2eAwBEAgAAAA==.Prsr:BAAANQAECgMIBgABNQAFFAcIEgABAA8aAA==.',
Pu='Pudgypaws:BAAANQAECgQIBwAAAA==.Punishment:BAAANQABCgIIAgABNQAECgQICQACAAAAAA==.',
Qu='Quickmend:BAAANQAECgQIBAAAAA==.Quickpal:BAAANQAECgcIEQAAAA==.Quickpaw:BAABNQAECn8fAAIeAAkKYxsrDwCOAgAeAAkKYxsrDwCOAgAAAA==.',
Ra='Raccoons:BAAANQADCgMIAwABNQAFFAUIDAAcAOISAA==.Radell:BAAANQAECgQICAAAAA==.Rageproof:BAAANQAECgEIAgAAAA==.Ragged:BAABNQAECn8eAAMRAAoKdyBHBQAOAgARAAoKdyBHBQAOAgABAAEKAACI4gAxAAAAAA==.Raidbloom:BAEBNQAFFH8XAAIFAAUKvhZuAgCHAQAFAAUKvhZuAgCHAQABNQAECgoKLgAWAIoZAA==.Raidshock:BAEBNQAECn8uAAIWAAoKihkAMwCZAgAWAAoKihkAMwCZAgAAAA==.Rainsinger:BAAANQAECgEIAQAAAA==.Ramook:BAEANQAECgUIBQAAAA==.Randomchar:BAABNQAECn8+AAISAAoKYxMpLgB1AQASAAoKYxMpLgB1AQAAAA==.Rankor:BAAANQADCgYIBgABNQAECgoKOgAbAFUPAA==.Rastann:BAABNQAECn88AAISAAoKrh1mEgDoAQASAAoKrh1mEgDoAQAAAA==.Ratsdrack:BAAANQADCgMIAwAAAA==.Rawrlas:BAAANQADCgMIAwABNQAECgUIFAAhACYOAA==.Razdor:BAAANQADCgUIBgAAAA==.',
Re='Reapertoo:BAACNQAFFH8PAAMBAAcKnh+9AgAZAgABAAUKAiS9AgAZAgARAAYK9htuBwCDAQA1AAQKfzMAAxEACgrfJNECAG4CAAEACAqCJTUOAEcDABEACgrJH9ECAG4CAAAA.Recreant:BAAANQADCgcIDQAAAA==.Redbaron:BAABNQAECn8aAAIGAAkK6RiENAAJAgAGAAkK6RiENAAJAgAAAA==.Redmtndew:BAAANQAECgIIAgAAAA==.Reetep:BAAANQADCggIGQABNQAECgQICQACAAAAAA==.Regeth:BAAANQADCggIFQAAAA==.Remily:BAAANQAECgYICwABNQAECgoKKQAHANQZAA==.Repuns:BAEANQAECggIBAABNQAECgoKJgAOANkfAA==.Revin:BAAANQAECgEJAQAAAA==.Rezalia:BAAANQADCgMIAwAAAA==.',
Ro='Roary:BAAANQABCggIHgABNQABCggINgACAAAAAA==.Rodned:BAAANQADCggJCAAAAA==.Rolas:BAAANQADCgMIAQABNQAECgUIFAAhACYOAA==.Rondle:BAAANQAECgQIBQAAAA==.Rottencorpse:BAAANQADCgQIBAAAAA==.Rozalin:BAABNQAECn85AAMHAAoKzyF4EQCMAwAHAAoKzyF4EQCMAwADAAEKMSKSNQBlAAAAAA==.Rozalinamoon:BAAANQADCgMIAwAAAA==.',
Ru='Rubeus:BAEANQAECgcIBwABNQAECgoKJgAOANkfAA==.Rurouni:BAAANQAECgIIAgAAAA==.Rustystorm:BAAANQADCgMIAwAAAA==.Rustywarlock:BAAANQAECgQIBwAAAA==.',
Ry='Ryoshi:BAABNQAECn8nAAMEAAoKZhwfOgC8AgAEAAoKZhwfOgC8AgAiAAcKZxdvCADNAQAAAA==.',
['Rò']='Ròòszy:BAAANQADCgYIBwAAAA==.',
Sa='Sacredstars:BAAANQAECgUIBQAAAA==.Sacredswords:BAABNQAECn8nAAMMAAkKxBmXVwCEAgAMAAkKxBmXVwCEAgANAAIKbRC4IgCgAAAAAA==.Sakito:BAAANQAECgcIEAABNQAFFAYIEwAPAOUUAA==.Salarai:BAAANQADCgcIBgABNQAECgUIFAAhACYOAA==.Sanguinius:BAABNQAECn8hAAMWAAoKNyN2BwCOAwAWAAoKNyN2BwCOAwASAAIKMQS1hwFPAAAAAA==.Sapphiremist:BAABNQAECn8ZAAIGAAYKuQvQJwDQAAAGAAYKuQvQJwDQAAAAAA==.Sayen:BAAANQAFFAEIAQAAAA==.',
Sc='Scachity:BAABNQAECn8pAAMcAAkKxBQeXQBAAgAcAAkKxBQeXQBAAgAgAAMKexAlRQCxAAAAAA==.Scan:BAABNQAECn8mAAIOAAoKrBzFAwBRAgAOAAoKrBzFAwBRAgAAAA==.Schein:BAAANQAECgYIEwAAAA==.',
Se='Segsacute:BAABNQAECn8ZAAIMAAoKaBOJcgA9AgAMAAoKaBOJcgA9AgAAAA==.Sendatu:BAAANQAECgEIAgABNQAECgIIAwACAAAAAA==.Sepulchre:BAABNQAECn83AAMBAAoKlAg0GwANAQABAAoKlAg0GwANAQARAAYKagSPdgDIAAAAAA==.Seraphiim:BAAANQADCggICAAAAA==.',
Sh='Shadesfault:BAAANQADCgUIEQAAAA==.Shadowhart:BAAANQADCgcIBwAAAA==.Shaeebulay:BAAANQABCgQIBQAAAA==.Shamaroo:BAAANQABCgUIBwAAAA==.Shaundakul:BAABNQAECn8ZAAMPAAcKPg/pNwAGAQAPAAcKPg/pNwAGAQAOAAQKiQqz3QDaAAAAAA==.Shephion:BAABNQAECn8UAAIHAAYKvBlw2gDSAQAHAAYKvBlw2gDSAQABNQAECgoKQQAeAOEkAA==.Shnozberries:BAAANQADCgEJAQAAAA==.Shockhart:BAAANQAECggIEwAAAA==.Shonuffz:BAAANQADCgYIBgAAAA==.Shortnstack:BAABNQAECn8WAAIEAAUK6wtifQCyAAAEAAUK6wtifQCyAAAAAA==.Shãdow:BAAANQADCgUIBQAAAA==.',
Si='Side:BAAANQAECgEIAQAAAA==.Siegfried:BAAANQAECgQIBAAAAA==.Simori:BAAANQADCgIIAgAAAA==.Sindrel:BAAANQAECgUIBQABNQAFFAQIDAAJAPsaAA==.Siyurie:BAAANQADCgcIEAAAAA==.',
Sk='Skawalker:BAABNQAECn87AAMFAAoKPiJqBAAtAgAFAAoKPiJqBAAtAgAjAAEKVxcdHQBBAAAAAA==.',
Sl='Slaed:BAAANQADCgYIBwAAAA==.Slaynne:BAABNQAECn8UAAQMAAgKjRXPsgCeAQAMAAcKTRfPsgCeAQAZAAMKlxCUMgCjAAANAAEKAABVLgBIAAAAAA==.',
Sm='Smoky:BAAANQAECgUIBwAAAA==.Smäug:BAACNQAFFH8SAAMaAAcKOR2PAwC0AQAaAAYK2R2PAwC0AQAbAAEKuBr0CgBbAAA1AAQKfzIABBoACgpDJVkBALsDABoACgpDJVkBALsDACQABwr7DxkqAF4BABsAAQqTIhIfAGcAAAAA.',
Sn='Snailas:BAAANQADCggIDwAAAA==.Sniperwolf:BAAANQADCgYIBgABNQAECgUICAACAAAAAA==.Snowleopard:BAAANQADCgIIAgAAAA==.',
So='Sodomn:BAAANQADCgQIBAAAAA==.Solria:BAABNQAECn8nAAIIAAgKwRcwDAAjAgAIAAgKwRcwDAAjAgAAAA==.Sonnytyphoon:BAAANQADCgYIBgAAAA==.',
St='Starnex:BAAANQAECggIDQAAAA==.Statyrea:BAAANQADCgUIBQAAAA==.Strikes:BAAANQAECggIDwAAAA==.Styx:BAACNQAFFH8LAAIZAAQKiSSDAAA6AQAZAAQKiSSDAAA6AQA1AAQKf0gAAhkACgqzJgsAABgEABkACgqzJgsAABgEAAAA.',
Su='Sugabuns:BAAANQAECggICwAAAA==.Sukfööt:BAABNQAECn8mAAIZAAoKzA4ZFQDWAQAZAAoKzA4ZFQDWAQAAAA==.Sumbatadh:BAAANQAECgYIBwAAAA==.Summerflip:BAAANQADCggICAABNQAECgoKPwAIAG4bAA==.Sunnytyphoon:BAABNQAECn8aAAIjAAgKkhTIEAD7AQAjAAgKkhTIEAD7AQAAAA==.',
Sw='Swiftholy:BAAANQAECgcIEgAAAA==.Swiftmends:BAAANQAECgIIAgAAAA==.',
Sy='Sydahlis:BAAANQAECgcIEwAAAA==.Sylvestris:BAABNQAECn8ZAAIFAAkKIyQrCABCAwAFAAkKIyQrCABCAwAAAA==.',
Ta='Taiyana:BAAANQAECgQIBAAAAA==.Tangie:BAAANQADCggICgAAAA==.Tankjob:BAAANQAECgQIDgAAAA==.Tanklorswift:BAAANQAECgIIAgAAAA==.Tastemycrits:BAAANQADCggICAABNQAECgoKGwASAHAZAA==.',
Td='Tdog:BAAANQADCggICwAAAA==.',
Te='Tealetresh:BAAANQABCgIIAgAAAA==.Teapot:BAAANQAECgcICwAAAA==.Tedoseirum:BAABNQAECn8xAAIGAAoKIyGjCgBaAwAGAAoKIyGjCgBaAwAAAA==.Terminal:BAAANQADCggICwAAAA==.Terpyu:BAAANQADCgEIAQAAAA==.Texasbilly:BAAANQADCgYIDAAAAA==.Texasredneck:BAAANQADCgYIDAAAAA==.Texasslasher:BAAANQADCgYIBgAAAA==.',
Th='Thaelyra:BAAANQADCggICAAAAA==.Thedtwo:BAAANQAECgMIAgAAAA==.Thorgarrus:BAABNQAECn89AAISAAoKSh27CgAzAgASAAoKSh27CgAzAgAAAA==.',
Ti='Tigerwoodz:BAAANQAECgEIAQAAAA==.Tilbourne:BAAANQAECgUIBQAAAA==.Timvoker:BAAANQADCgYIBgAAAA==.',
To='Toddie:BAABNQAECn8uAAMEAAkKvhyPPAC0AgAEAAkKvhyPPAC0AgAhAAEKAABKjgAxAAAAAA==.Tolkarnyx:BAAANQADCgUIBQABNQAFFAYIEwAPABMbAA==.Tommyj:BAAANQADCggICwAAAA==.Torcher:BAAANQAECgMIAwAAAA==.Tormod:BAABNQAECn8qAAIEAAkKRRTHFgDBAQAEAAkKRRTHFgDBAQAAAA==.Torvaldt:BAAANQAECgcIDwABNQAECgkJLgAEAL4cAA==.Tourmod:BAAANQAECgQIDgAAAA==.Towmater:BAAANQAECgIIAwAAAA==.',
Tr='Trakkarz:BAAANQAECgQIBQAAAA==.Traps:BAAANQAECgQICQAAAA==.Trashypanda:BAACNQAFFH8UAAIHAAUK9hrxCQALAQAHAAUK9hrxCQALAQA1AAQKfysAAgcACgpjI2UeAJcBAAcACgpjI2UeAJcBAAAA.Traviskelce:BAEANQAECggICAABNQAECgoKJgAOANkfAA==.Trays:BAAANQADCgYIBgAAAA==.Trender:BAAANQADCgQIBAABNQAECgMIBAACAAAAAA==.Treniity:BAAANQAECgUICgAAAA==.Tressilly:BAABNQAECn8pAAIHAAoK1Bl8MgAmAwAHAAoK1Bl8MgAmAwAAAA==.Trinagirl:BAAANQADCgYIBgAAAA==.Trinneries:BAAANQADCgcJBwAAAA==.Triná:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Tristanyia:BAAANQADCggICAAAAA==.Tristiyan:BAAANQAECgMIBAAAAA==.Trogdorr:BAABNQAECn86AAMbAAoKVQ80CwCvAQAaAAkKHw9sEwAYAgAbAAkKow00CwCvAQAAAA==.Trutert:BAAANQAECgMIBgAAAA==.Tryana:BAAANQAECgIIAQAAAA==.Trystiana:BAAANQADCgMJBAAAAA==.',
Tt='Ttania:BAAANQADCgYIDgAAAA==.',
Tu='Tubor:BAAANQAECgQICwAAAA==.',
Tw='Tweetwee:BAAANQAECgYICAAAAA==.',
Ty='Tyledis:BAAANQADCggIEAABNQAECgoKPAAZAFEjAA==.Tyr:BAABNQAECn8zAAMOAAoKdxuIHwAOAwAOAAoKdxuIHwAOAwAPAAIK1gn9BgFaAAAAAA==.Tyrnova:BAAANQADCggICAAAAA==.',
['Tö']='Töshïrö:BAAANQADCgIIAgAAAA==.',
Uh='Uhope:BAAANQAECgYICgAAAA==.',
Um='Umbravolt:BAABNQAECn89AAIlAAoK0CLzAADTAgAlAAoK0CLzAADTAgAAAA==.',
Un='Unclezapp:BAAANQADCggJDgAAAA==.Unravel:BAAANQADCgUIDgAAAA==.Unrealcalorx:BAAANQADCgUIBQAAAA==.Unrealronin:BAAANQAECgUICQAAAA==.',
Va='Vaeris:BAAANQADCgUJCwAAAA==.Vakero:BAABNQAECn8aAAMSAAcKOAeDhADGAAASAAcKOAeDhADGAAAWAAIKuwEWHQE6AAAAAA==.Valeriana:BAAANQADCgQIBAAAAA==.Valess:BAABNQAECn8YAAMkAAYKmgUkQQCYAAAkAAUKhQQkQQCYAAAbAAUKdQGjHgBrAAAAAA==.Valros:BAAANQADCgYICgAAAA==.Vaythan:BAABNQAECn8mAAIjAAoK5h2jAAClAgAjAAoK5h2jAAClAgAAAA==.',
Ve='Venchris:BAABNQAECn8XAAIMAAkKKhMiTQAEAQAMAAkKKhMiTQAEAQAAAA==.Verica:BAAANQADCgEIAQAAAA==.',
Vh='Vhiz:BAABNQAECn8VAAIJAAcKRhBeLwCcAQAJAAcKRhBeLwCcAQAAAA==.',
Vi='Vibrance:BAAANQADCggJEAAAAA==.Victorius:BAAANQAECgMIAwAAAA==.Viridesa:BAAANQADCgcIFAAAAA==.Vixine:BAAANQAECgUICgAAAA==.',
Vn='Vnillabeef:BAAANQAECgQIBQABNQAFFAcIEgABAA8aAA==.',
Vo='Vohlen:BAAANQABCgYIBgAAAA==.Voidcore:BAAANQAFFAEIAgABNQAECgoKGgAMAPYTAA==.Voidwalker:BAAANQADCgYICQABNQAFFAUIDAAQAFcbAA==.',
Vy='Vysera:BAAANQAECgEIAQAAAA==.',
Wa='Warfarmer:BAAANQAECgQICgAAAA==.Warhawke:BAAANQADCggIEAAAAA==.',
We='Werenal:BAAANQADCgcICwAAAA==.',
Wh='Whis:BAAANQAECgUIEQAAAA==.Whispernight:BAAANQADCgQIBwAAAA==.',
Wi='Widja:BAAANQADCgUIEgAAAA==.Wiimage:BAAANQAECgQIBQAAAA==.Wiivinelight:BAAANQADCgMIAwABNQAECgQIBQACAAAAAA==.Wildhus:BAABNQAECn8oAAIGAAoKSBGKFQA/AQAGAAoKSBGKFQA/AQAAAA==.',
Wo='Wolfkin:BAAANQADCggIBwAAAA==.',
Wy='Wyckdd:BAAANQAECgYIBgAAAA==.',
['Wå']='Wåffle:BAAANQAECgcIDwABNQAECgoKMAAdANUfAA==.',
['Wî']='Wîca:BAABNQAECn8ZAAIUAAgKOQv+NwBlAQAUAAgKOQv+NwBlAQAAAA==.',
Xa='Xantris:BAAANQADCgEIAQAAAA==.',
Xe='Xenowolf:BAAANQAECgUICAABNQAECgcIFQAYAMwGAA==.',
Xv='Xvire:BAAANQAECgIIBAAAAA==.',
['Xû']='Xûrû:BAAANQAECgcICgAAAA==.',
Yc='Yce:BAABNQAECn8WAAMkAAUKRA95DwDZAAAkAAQKbxF5DwDZAAAaAAUKpgxbCwCvAAAAAA==.',
Ye='Yeiko:BAAANQAECgYIDQAAAA==.',
Yo='Yoker:BAAANQAECgYIEAAAAA==.Yokersen:BAABNQAECn8WAAIEAAkKfRx6XgBbAgAEAAkKfRx6XgBbAgAAAA==.',
Za='Zaeladen:BAAANQAECgQICAAAAA==.Zalorea:BAAANQAECgUIEQABNQAECgoKMwARAN4LAA==.Zambonii:BAAANQAECggIDQABNQAECgkJNAAgAO0gAA==.Zamdeath:BAAANQADCgMIAwABNQAECgkJNAAgAO0gAA==.Zamlock:BAABNQAECn80AAMgAAkK7SBrDwAGAgAcAAcKOiDiSwBwAgAgAAYKlh1rDwAGAgAAAA==.Zammonk:BAAANQAECgEIAQABNQAECgkJNAAgAO0gAA==.Zanya:BAAANQAECgQICAAAAA==.',
Ze='Zeiko:BAABNQAECn8jAAIBAAkKHCM9EwAeAwABAAkKHCM9EwAeAwAAAA==.Zestychip:BAAANQAECgQICQAAAA==.Zeäl:BAAANQADCgUIBgAAAA==.',
Zh='Zhaoyun:BAAANQAECgQIBAAAAA==.',
Zi='Zilkir:BAEBNQAECn8xAAMSAAoKghgbSgC3AgASAAoKghgbSgC3AgAWAAgKYxbPTwAsAgAAAA==.Ziran:BAABNQAECn8kAAIJAAoKRyQDAwCpAwAJAAoKRyQDAwCpAwAAAA==.Zivadhim:BAAANQADCgIIAgAAAA==.',
Zl='Zlyth:BAAANQAECgQIDAAAAA==.',
Zz='Zzodac:BAAANQADCgEIAQABNQAECgoKKAAGAEgRAA==.Zzvzz:BAAANQAECgQIBAAAAA==.',
['Är']='Ärtrix:BAAANQAECgIIBQAAAA==.',
['Èn']='Ènyo:BAAANQAECggICAAAAA==.',
['Øp']='Øptimusdayne:BAAANQADCgEIAgAAAA==.',
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
