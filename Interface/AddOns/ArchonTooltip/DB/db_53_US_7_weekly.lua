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

local lookup = {'DeathKnight-Unholy','Unknown-Unknown','Druid-Restoration','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','Priest-Holy','Mage-Arcane','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Mage-Frost','DeathKnight-Frost','Paladin-Retribution','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Paladin-Holy','Paladin-Protection','Warrior-Protection','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Rogue-Assassination','Monk-Mistweaver','Monk-Windwalker','Hunter-BeastMastery','Rogue-Outlaw','Hunter-Marksmanship','Warlock-Destruction','Hunter-Survival','Evoker-Preservation','Druid-Feral',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abnalem:BAAANQADCgIIAgAAAA==.',
Ac='Aceventuraa:BAAANQADCgEIAQAAAA==.',
Ad='Adramalech:BAAANQADCgQIBAABNQAFFAYIEQABAKMhAA==.',
Ae='Aeakos:BAAANQAECgIIAwABNQAECgcIHQABAO0PAA==.Aeldon:BAAANQADCggIIAAAAA==.',
Ai='Airese:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.Airist:BAAANQAECgMIAwAAAA==.Aisele:BAAANQAECgYIEgAAAA==.',
Al='Alastor:BAAANQADCgcICwAAAA==.Alathir:BAAANQAECgYIDgAAAA==.Alluri:BAAANQAECgcIDgAAAA==.Althemia:BAAANQADCgcIDgAAAA==.Alunamora:BAABNQAECoEjAAIDAAgKUh0TEgChAgADAAgKUh0TEgChAgAAAA==.Alwind:BAABNQAECoEWAAMEAAgKig/8PgDXAQAEAAgKig/8PgDXAQAFAAUKCwQdOQCYAAAAAA==.',
An='Analani:BAAANQAECgIIAgAAAA==.Anali:BAAANQAECgUIBQAAAA==.Angis:BAAANQADCgQICAAAAA==.Angryheals:BAAANQAECgUIBQAAAA==.Annieq:BAAANQADCgMIAQAAAA==.Ansfrid:BAAANQADCggIDgAAAA==.',
Ap='Apøllø:BAABNQAECoEcAAIGAAkK5gdzOgCsAQAGAAkK5gdzOgCsAQAAAA==.',
Aq='Aquatofana:BAAANQAECgQICAAAAA==.',
Ar='Aranel:BAAANQADCgYIBgAAAA==.Arcamancer:BAAANQAECgIIAwAAAA==.Arinthal:BAAANQAECgQIBgAAAA==.Arkenfel:BAAANQADCgQIBAAAAA==.Aroia:BAAANQAECgQICQAAAA==.Arril:BAAANQAECgQIBwAAAA==.Artemissy:BAAANQADCgUICwAAAA==.Artiis:BAAANQAECggICAAAAA==.',
As='Ashlieghee:BAABNQAECoEiAAIHAAgKBx/xIADPAgAHAAgKBx/xIADPAgAAAA==.Ashron:BAAANQAECgcIBwABNQAECgkJJwAIAHohAA==.Astien:BAAANQAECgEIAwAAAA==.Astralee:BAAANQADCggIDwAAAA==.',
Au='Audric:BAAANQADCgYIBwAAAA==.Auot:BAAANQAECgMIAwAAAA==.',
Av='Avelen:BAAANQAECgYIEQAAAA==.Averlen:BAAANQAECgQIBAAAAA==.Avha:BAAANQAECgQIBwAAAA==.Avistero:BAAANQADCgUIBwAAAA==.',
Ax='Axel:BAABNQAECoEgAAIGAAgKvB4FHQCMAgAGAAgKvB4FHQCMAgAAAA==.',
Ay='Aylden:BAABNQAECoEdAAMGAAgKZhBCNwDCAQAGAAgKZhBCNwDCAQAJAAIKsQF8WwBEAAAAAA==.Aylshm:BAAANQADCgYIFAAAAA==.Ayrene:BAAANQADCgcIBwABNQAECgQIBQACAAAAAA==.',
Az='Azenazar:BAAANQADCgEIAQAAAA==.Azog:BAAANQAECgEIAQAAAA==.Azsharianna:BAAANQABCggIEAAAAA==.',
Ba='Bailas:BAAANQAECgIIAgAAAA==.Battousai:BAAANQADCgMIAwAAAA==.Bazileth:BAAANQADCgYIBgAAAA==.',
Be='Bearistotle:BAAANQAECgEIAQAAAA==.Beastm:BAAANQAECgQIBAAAAA==.Beastmehr:BAAANQAECgQIBwABNQAECgkJJwAIADkgAA==.Beauregardl:BAAANQAECgEJAQAAAA==.Bellina:BAAANQADCgcIBwAAAA==.Belwyn:BAAANQADCgUIBgAAAA==.Benjofamin:BAAANQAECgYIBwAAAA==.',
Bi='Bitesize:BAEBNQAECoEmAAMKAAkKWCSIEQBvAwAKAAkKWCSIEQBvAwALAAEK1yTsJABjAAAAAA==.',
Bl='Blakelivly:BAEBNQAECoEaAAQMAAgKcB+PHwDPAgAMAAgKcB+PHwDPAgANAAUKHxufGwB0AQAOAAMKbBnizADKAAABNQAECggIIQAEAMokAA==.Blashster:BAABNQAECoEnAAMIAAkKeiEdKwAvAwAIAAkKeiEdKwAvAwAPAAEKPxneOQBCAAAAAA==.Blightsize:BAEANQADCgMIAwABNQAECgkJJgAKAFgkAA==.',
Bo='Bonemilker:BAACNQAFFIERAAMBAAYKoyE7AQA8AgABAAYK8SA7AQA8AgAQAAQKtB1QBQBxAQA1AAQKgSkAAxAACQrYJXEHAFoDABAACQqKJXEHAFoDAAEABQoLHDxUAJgBAAAA.Bonkdaddy:BAABNQAECoEWAAIRAAkKnxlKOADMAgARAAkKnxlKOADMAgAAAA==.Bopeep:BAAANQAECgcICwAAAA==.',
Br='Brandt:BAAANQABCgQICAAAAA==.Breelyssa:BAAANQAECgIIAgAAAA==.Brego:BAAANQAECgIIAgAAAA==.Brenna:BAAANQAECgMIAwABNQAECggIFgAEAIoPAA==.Brewslèé:BAAANQABCgYIBgAAAA==.Brighter:BAABNQAECoEtAAQSAAkK8xp6GQBgAgASAAgKvxp6GQBgAgAHAAYKlxYKfABsAQATAAYKshKMDABaAQAAAA==.Brightsize:BAEANQAECgUICgABNQAECgkJJgAKAFgkAA==.Broncopally:BAAANQADCgQIBAAAAA==.Brótien:BAAANQADCggICAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bunnka:BAAANQADCgYIBgAAAA==.Bunnyparade:BAAANQADCgYIBgAAAA==.',
Ca='Cakesdruid:BAAANQAECgQIBAAAAA==.Caledwar:BAAANQAECgQICwAAAA==.Calrissa:BAAANQADCgMIAwABNQAECgYIDgACAAAAAA==.Calthirstrap:BAACNQAFFIEMAAMBAAUKdRejCQBSAQABAAQK7xmjCQBSAQAUAAEKjQ2XLgAqAAA1AAQKgScAAgEACQoKJUMJAGMDAAEACQoKJUMJAGMDAAAA.Carare:BAAANQADCgYICgAAAA==.Carnàge:BAAANQAECgMIBgAAAA==.Casterrata:BAAANQADCggICAAAAA==.',
Ce='Ceefack:BAAANQAECgIIAwAAAA==.Cethin:BAAANQAECgEIAgAAAA==.',
Ch='Chaargee:BAAANQAECgQICAAAAA==.Cheedar:BAACNQAFFIEHAAMVAAMKzQvkFADaAAAVAAMKzQvkFADaAAAWAAEKTACYEQAYAAA1AAQKgRwAAhUACQq8EDVEADYCABUACQq8EDVEADYCAAAA.Chelaria:BAAANQAECgEIAQAAAA==.Cherylindrea:BAAANQADCgUICgAAAA==.Chillwombat:BAAANQADCggIGwAAAA==.Chumlei:BAAANQADCgcIBwAAAA==.',
Ck='Ckz:BAAANQAECggIBAAAAA==.',
Cl='Claydemon:BAAANQAECgQICAAAAA==.Clayvicar:BAABNQAECoEsAAMHAAkKMQt1XwDRAQAHAAkKMQt1XwDRAQASAAIKVgMJXgBeAAAAAA==.',
Co='Coridane:BAAANQAECgUIDwAAAA==.Corrum:BAAANQADCgUIBQAAAA==.Corwinfiron:BAABNQAECoEZAAIIAAcKYgke9QB7AQAIAAcKYgke9QB7AQAAAA==.',
Cr='Crosse:BAAANQAECgQIBgAAAA==.Cruellà:BAAANQADCgYIEwAAAA==.Cryptcrawler:BAAANQAECgEIAgAAAA==.',
Cu='Curkage:BAAANQADCgIIAgAAAA==.',
Cy='Cythera:BAACNQAFFIEMAAINAAUKdhTbAQCxAQANAAUKdhTbAQCxAQA1AAQKgSsAAg0ACQqvJZgBAKIDAA0ACQqvJZgBAKIDAAAA.',
['Cá']='Cámus:BAAANQAECgUIEwAAAA==.',
Da='Daammy:BAAANQAECgIIAgAAAA==.Daayumgurl:BAAANQADCgYIBgAAAA==.Dagren:BAAANQADCggIHgAAAA==.Daisy:BAAANQABCggIJQABNQABCggIJgACAAAAAA==.Dakdor:BAAANQADCgMIAwAAAA==.Daphine:BAAANQADCgUICwAAAA==.Darimonk:BAAANQADCgEIAQABNQADCgYICgACAAAAAA==.Darivara:BAAANQADCgYICgAAAA==.Darkbeautie:BAAANQAECgQICQAAAA==.Darkcarbon:BAAANQAECgQICQAAAA==.Darkchylde:BAAANQADCgUIBQABNQAECgQICQACAAAAAA==.Darkplazzma:BAAANQAECgEIAQAAAA==.Darmin:BAAANQABCgQIBAAAAA==.',
De='Deathmask:BAAANQAECgIIAwAAAA==.Deathspal:BAABNQAECoEiAAMRAAgK6RLkigDdAQARAAgK6RLkigDdAQAWAAIKpQgVWgBLAAAAAA==.Dessembrae:BAABNQAECoEtAAIXAAkKPyS3AQCdAwAXAAkKPyS3AQCdAwAAAA==.Dewkiez:BAEBNQAECoEeAAIOAAkKxyUbBADEAwAOAAkKxyUbBADEAwAAAA==.',
Di='Diabolicarl:BAABNQAECoEaAAIGAAgKowpYPQCZAQAGAAgKowpYPQCZAQAAAA==.Diri:BAAANQADCggICAABNQAECgkJHwAYAKoLAA==.',
Dm='Dmmeforpi:BAAANQADCgYICgAAAA==.',
Do='Docphanan:BAAANQAECgEIAgAAAA==.Doesntheal:BAAANQABCgIIAgAAAA==.Dookiez:BAEANQAECgYICgABNQAECgkJHgAOAMclAA==.Doubledragin:BAABNQAECoEbAAMZAAcK6RQfFgDIAQAZAAcKmxQfFgDIAQAaAAQKxhT9EgDTAAAAAA==.',
Dr='Dracantar:BAAANQADCggIDQAAAA==.Dractini:BAAANQADCgcICgABNQAFFAcIHgAHAHEYAA==.Dragfan:BAAANQADCgQJBAAAAA==.Dragonbelly:BAAANQABCggIJgAAAA==.Dragondeez:BAAANQABCgQIBAABNQAECgIIAgACAAAAAA==.Dragore:BAAANQAECggIEwAAAA==.Druidgirls:BAABNQAECoEzAAIDAAkK1RhIEgCfAgADAAkK1RhIEgCfAgAAAA==.',
Du='Duelist:BAAANQAECgcICQAAAA==.Dupree:BAAANQADCgIIAgAAAA==.Durogdem:BAAANQADCgYIBgAAAA==.Duskfire:BAAANQABCgQIBgAAAA==.',
Ea='Earthaggie:BAAANQADCgUIDgAAAA==.',
Ec='Echlipse:BAAANQAECgQIBQABNQAECgkJIAAWACMhAA==.',
Ed='Ederon:BAAANQABCggICAAAAA==.Edirae:BAAANQAECgIIAgAAAA==.',
El='Elenora:BAAANQAECgYIEgAAAA==.Ellea:BAAANQAECgQIBAAAAA==.Ellesmere:BAAANQAECgIIAgABNQAFFAgIGwAVALcbAA==.Elye:BAAANQAECgYIDAAAAA==.',
Em='Emer:BAAANQAECgYICgAAAA==.Emiru:BAAANQADCgUJBgAAAA==.',
En='Encore:BAABNQAECoEvAAIDAAgK1AtMKwCPAQADAAgK1AtMKwCPAQAAAA==.',
Eo='Eousphorus:BAABNQAECoExAAMIAAkKDx7KKAA2AwAIAAkKDx7KKAA2AwAPAAIK/Qj9MwBUAAAAAA==.',
Er='Erathen:BAAANQADCggICgAAAA==.Eryanna:BAAANQAECgIIAgAAAA==.',
Es='Esplan:BAEANQAECgcIDQABNQAECggIIQAEAMokAA==.',
Eu='Euden:BAAANQADCgQIBAAAAA==.',
Ev='Evelleion:BAAANQAECgYICQAAAA==.',
Ex='Excedrin:BAAANQADCgIIAgAAAA==.Exoticlord:BAAANQAECgQIBAAAAA==.',
Fe='Felhayde:BAAANQADCgYIBgAAAA==.Felicity:BAAANQADCgQIBAAAAA==.Fenryyr:BAAANQADCgYJBwAAAA==.',
Fi='Fierygrace:BAAANQADCgcIEAAAAA==.Firburger:BAAANQAECgQICgAAAA==.Fischl:BAAANQAECgIIAgAAAA==.',
Fl='Flameth:BAABNQAECoEwAAIbAAkKshCZVQA0AgAbAAkKshCZVQA0AgAAAA==.Fling:BAAANQADCgMIAwAAAA==.Flirtywombat:BAAANQAECgEIAgAAAA==.',
Fr='Freezrorburn:BAAANQADCgYIBwAAAA==.',
Fu='Fujitto:BAAANQADCgIIAgAAAA==.Fumanchu:BAABNQAECoEfAAIXAAgK7hteCwBbAgAXAAgK7hteCwBbAgAAAA==.Fuzugchu:BAAANQAECgYIBgABNQAECggIHwAXAO4bAA==.',
Ga='Gaamora:BAAANQADCgUIDwAAAA==.Gainsborough:BAABNQAECoEkAAMRAAkKJB9GKQAGAwARAAkKJB9GKQAGAwAWAAMKaRTIQwC6AAABNQAFFAYIEwAMAOUUAA==.Gamegg:BAAANQAECgQIBAAAAA==.Garagos:BAABNQAECoEtAAIcAAkKWhmXGACPAgAcAAkKWhmXGACPAgAAAA==.',
Ge='Gebuss:BAABNQAECoEpAAIcAAkK6yJgBQBoAwAcAAkK6yJgBQBoAwAAAA==.',
Gi='Gilford:BAAANQAECgQIBAAAAA==.',
Gl='Glenraven:BAAANQAECgEIAgAAAA==.',
Go='Golokan:BAAANQADCgYIDAAAAA==.Goochaddi:BAABNQAECoEZAAIRAAkKoBy+YgBFAgARAAkKoBy+YgBFAgAAAA==.Gorgunga:BAAANQAECgUIBQAAAA==.Gozer:BAAANQABCgcICQAAAA==.',
Gr='Grolden:BAAANQAECgIIAgAAAA==.Grïpnrïp:BAAANQAECgEIAQAAAA==.',
Gu='Gunnerrata:BAAANQADCgcICAAAAA==.',
Ha='Hahalua:BAAANQAECgMIAQAAAA==.Halieight:BAAANQAECgIIAgAAAA==.Halifaxx:BAABNQAECoEtAAIIAAgKOxwlXgCwAgAIAAgKOxwlXgCwAgAAAA==.Haliseven:BAAANQADCgIIAgAAAA==.Halithree:BAAANQADCgYICgABNQAECggILQAIADscAA==.Halitwo:BAAANQADCggICgABNQAECggILQAIADscAA==.Hapiagin:BAAANQAECgQIBAAAAA==.Haraboo:BAAANQAECgUIBwAAAA==.Harmaa:BAAANQAECgYICAAAAA==.Havengul:BAAANQAECggIEAAAAA==.Hawknor:BAAANQAECgQIBwAAAA==.',
He='Healthcare:BAABNQAECoErAAMMAAkKQRY9NABpAgAMAAkKQRY9NABpAgAOAAUKbw31rgAGAQABNQAFFAcIHgAHAHEYAA==.Healthplan:BAAANQADCgYIBgABNQAECgcIGgAVANcVAA==.Heartilly:BAACNQAFFIETAAIMAAYK5RQ/BQD3AQAMAAYK5RQ/BQD3AQA1AAQKgS0AAgwACQo5IJMTABUDAAwACQo5IJMTABUDAAAA.Herm:BAABNQAECoEzAAMdAAkKTCVNAQCyAwAdAAkKTCVNAQCyAwAeAAUKZB4+KgCZAQAAAA==.',
Ho='Holyfu:BAAANQAECgUIDAABNQAECggIHwAXAO4bAA==.Holymidget:BAAANQAECgEJAQAAAA==.Holysky:BAAANQAECgIIBQAAAA==.Holytim:BAABNQAECoEkAAQHAAgKICCTJwCuAgAHAAgKICCTJwCuAgATAAYK5hZBCQCtAQASAAIKdAqcXABjAAAAAA==.Honeypackz:BAAANQAECgMIBQAAAA==.Honnik:BAAANQABCgIIAgAAAA==.Hotpink:BAAANQADCgUIDQAAAA==.How:BAABNQAECoEfAAMdAAkK7B+6BgAQAwAdAAkK7B+6BgAQAwAeAAIKAA5ZUgBsAAAAAA==.',
Hu='Humongulus:BAAANQAECgcIEwAAAA==.',
Ic='Ickystix:BAAANQADCgMIAwABNQAECgIIAgACAAAAAA==.',
Ig='Ignored:BAAANQAECgcICwAAAA==.Ignöred:BAABNQAECoEZAAIKAAcKSBgKfgD9AQAKAAcKSBgKfgD9AQAAAA==.',
Il='Ilidra:BAAANQAECgEIAQAAAA==.Illaine:BAAANQADCgYIBgAAAA==.Illidæn:BAABNQAECoEZAAIJAAcK1wufMgCIAQAJAAcK1wufMgCIAQAAAA==.',
Im='Imos:BAAANQABCgQIBAAAAA==.Imperîus:BAAANQADCgUIBQABNQAFFAYIEQABAKMhAA==.',
In='Inaniel:BAABNQAECoEXAAIJAAgK3xegGQByAgAJAAgK3xegGQByAgAAAA==.Inq:BAABNQAECoErAAMIAAkKgR8DJwA7AwAIAAkKgR8DJwA7AwAPAAEKLguXRgAqAAAAAA==.',
Ir='Iridaceaë:BAABNQAECoEcAAIHAAgKBxnOSAAkAgAHAAgKBxnOSAAkAgABNQAECgUIBgACAAAAAA==.Iryris:BAAANQAECgMIBwAAAA==.',
Is='Isedeath:BAABNQAECoEtAAQBAAkKvhWVQgDrAQABAAgKjBWVQgDrAQAQAAkKqQuMOQCsAQAUAAEKOB2JsgBFAAAAAA==.Istvankh:BAAANQABCgMIBAABNQADCgEIAQACAAAAAA==.',
Ja='Jaholin:BAAANQAECgIIBAAAAA==.Jarhead:BAAANQADCgIIAgAAAA==.Jarrhead:BAAANQAECgIIAwAAAA==.Jaxarus:BAAANQADCgEIAQAAAA==.',
Je='Jenaveive:BAABNQAECoEVAAIfAAcKRQtUjgC8AQAfAAcKRQtUjgC8AQAAAA==.Jethoisi:BAAANQAECgYIEAABNQAFFAUICQAWAL4HAA==.Jexi:BAAANQADCgYJBgABNQAECgQIBQACAAAAAA==.',
Jn='Jnex:BAAANQAECgcIDgAAAA==.',
Jo='Jongani:BAABNQAFFIEJAAIWAAUKvgc4BQAeAQAWAAUKvgc4BQAeAQAAAA==.Jookiez:BAEANQAECgYIBwABNQAECgkJHgAOAMclAA==.',
Jr='Jrrtrolkien:BAAANQADCgQIBAABNQAECgEIAgACAAAAAA==.',
Ju='Judgemehr:BAAANQAECgYICwABNQAECgkJJwAIADkgAA==.Judgepain:BAAANQAECggICAAAAA==.Judgmental:BAABNQAECoEgAAIVAAgKmSBjGwDzAgAVAAgKmSBjGwDzAgAAAA==.Justine:BAAANQAECgQIBAAAAA==.',
Ka='Kaboni:BAAANQAECgEIAQAAAA==.Kaelysong:BAAANQADCgUJDQAAAA==.Kageansatsu:BAAANQAECgQIBAAAAA==.Kairah:BAAANQAECgEIAQAAAA==.Kaivig:BAAANQADCgYIBgAAAA==.Kalï:BAAANQADCgYICQAAAA==.Karlil:BAAANQAECgQIDAAAAA==.Kasiene:BAAANQADCgcIFwAAAA==.Kasnay:BAAANQADCgQIBgAAAA==.Kathenset:BAAANQAECgUICAAAAA==.Kazenseth:BAAANQADCgEIAQAAAA==.Kazeral:BAACNQAFFIEHAAIcAAQKsA8tCABLAQAcAAQKsA8tCABLAQA1AAQKgRcABCAACQpxEzMLAJ0BACAABwrSETMLAJ0BABwAAgrjG0RuAKUAABgAAwqdAXhDAGwAAAAA.Kazzi:BAAANQADCgIIAgAAAA==.',
Ke='Keener:BAAANQAECgYIDQAAAA==.Kelvin:BAAANQABCgQIBAAAAA==.Kelyana:BAAANQABCgMIAwAAAA==.Kerrla:BAAANQAECgEIAQABNQAFFAQIBwAcALAPAA==.Keylleth:BAAANQADCgYJDwAAAA==.',
Kh='Khalanie:BAABNQAECoEZAAIYAAgKxQd0IAC1AQAYAAgKxQd0IAC1AQAAAA==.Khamnox:BAAANQAECgYIDAAAAA==.Khionia:BAAANQAECgIIAgAAAA==.',
Ki='Kidthefrist:BAAANQADCgUIBQAAAA==.Kielnmsoftly:BAAANQADCgYIBgAAAA==.Kilaia:BAAANQAECgEIAgAAAA==.Kirru:BAAANQAECgQIBgAAAA==.',
Kn='Knoble:BAAANQADCgQIBAAAAA==.',
Ko='Kokatoes:BAAANQAECgIIAgABNQAECggIHQAKABoRAA==.Korabas:BAAANQAECgQIBAABNQAECgkJLQAXAD8kAA==.',
Kr='Kreaton:BAAANQAECgcICwAAAA==.Kryt:BAABNQAECoEkAAIMAAcKRiB4NABoAgAMAAcKRiB4NABoAgAAAA==.',
Ku='Kuponia:BAAANQABCgIIAgAAAA==.',
Kw='Kwichangpain:BAAANQADCgcIDQAAAA==.',
Kx='Kxchiki:BAABNQAECoEgAAIVAAgKkgssawCvAQAVAAgKkgssawCvAQAAAA==.',
['Kã']='Kãz:BAAANQADCgYICAAAAA==.',
La='Laaklem:BAAANQAECgEJAQAAAA==.Laei:BAAANQADCggIEAAAAA==.Laserfingies:BAAANQADCgcIDwAAAA==.Lastsun:BAAANQADCgIIAgAAAA==.Lavacakes:BAABNQAECoEuAAMMAAkKSSDQFgAAAwAMAAkKSSDQFgAAAwAOAAIKZwYF/ABbAAAAAA==.Lawndartz:BAAANQADCggJDgAAAA==.',
Le='Lelantoz:BAABNQAECoEVAAIfAAYKfAX7wwBGAQAfAAYKfAX7wwBGAQAAAA==.Leliel:BAAANQABCgUICgAAAA==.Leqoofus:BAAANQADCgIIAgABNQADCgcIDwACAAAAAA==.',
Li='Lidan:BAAANQAECgYIEgAAAA==.Liebli:BAAANQAECgQIBwAAAA==.Liltank:BAAANQAECgIIAgAAAA==.Limity:BAAANQAECgQICAAAAA==.Linaradice:BAAANQAECgUICgAAAA==.Lixandra:BAAANQADCgEIAQAAAA==.',
Lo='Logyn:BAAANQADCgQIBgAAAA==.Lonelyspark:BAAANQADCgQICQAAAA==.Lonnias:BAAANQAECgUICQAAAA==.Lotsalock:BAAANQADCgUIBQAAAA==.',
Lu='Lucicelse:BAAANQADCgUIBQAAAA==.Lucifur:BAAANQADCgMIAwAAAA==.Luna:BAABNQAECoEZAAIDAAcKgw43LgB0AQADAAcKgw43LgB0AQAAAA==.Lunarluvgood:BAEBNQAECoEhAAIEAAgKyiQgDwA+AwAEAAgKyiQgDwA+AwAAAA==.',
Ly='Lyrelia:BAAANQAECgIIAwAAAA==.',
Ma='Madbones:BAAANQADCgYIDAABNQAECgcIGgAVANcVAA==.Madmetal:BAABNQAECoEaAAMVAAcK1xWqXADfAQAVAAcK1xWqXADfAQARAAEK3QO6igEpAAAAAA==.Mado:BAAANQAECgQICAAAAA==.Magefood:BAAANQADCgQIBAABNQAECgYIBAACAAAAAA==.Magicky:BAAANQAECgIIAgAAAA==.Mahlkier:BAAANQADCgUICwAAAA==.Mahlkierson:BAAANQADCgQIAwAAAA==.Maikego:BAAANQAECgQIBwAAAA==.Mairadin:BAAANQAECgIIAgAAAA==.Malchelo:BAAANQAECgQIBgAAAA==.Malfhunter:BAABNQAECoElAAIhAAkK7RluFgCRAgAhAAkK7RluFgCRAgAAAA==.Malfshammy:BAAANQADCgcIBwAAAA==.Maligosa:BAAANQADCgQIBgAAAA==.Manager:BAAANQADCggIBwAAAA==.Mangolassi:BAAANQAECgIIAgAAAA==.Mantodea:BAAANQADCgcIFgAAAA==.Manup:BAAANQADCgYIBgAAAA==.Marmin:BAABNQAECoEgAAIPAAgKwRdhCAAsAgAPAAgKwRdhCAAsAgAAAA==.Marymae:BAAANQADCgUICgAAAA==.Mattwm:BAAANQADCgEIAQAAAA==.',
Me='Meatstick:BAAANQADCgEIAQABNQADCgIIAgACAAAAAA==.Meikai:BAAANQAECgUICAAAAA==.Melillia:BAAANQAECgEIAwAAAA==.Melted:BAACNQAFFIEKAAIIAAUKlRNFFgCdAQAIAAUKlRNFFgCdAQA1AAQKgRwAAwgACQpoILI8AP8CAAgACQqtHbI8AP8CAA8AAQo2IIIwAGAAAAAA.Merdocki:BAABNQAECoEnAAMbAAkKKSAINACfAgAbAAgKfB8INACfAgAiAAQK5BOPKgAcAQAAAA==.Merdra:BAABNQAECoEgAAIWAAkKIyGKBABaAwAWAAkKIyGKBABaAwAAAA==.Merdre:BAABNQAECoEuAAQHAAkKIh05GQD5AgAHAAkKIRw5GQD5AgATAAQKLxnFEAAEAQASAAEKzAOadgAmAAAAAA==.',
Mi='Michealhunt:BAAANQADCgIIAgAAAA==.Midory:BAAANQAECgQICQAAAA==.Midranaira:BAAANQADCgEIAQAAAA==.Milda:BAAANQAECgMIBAAAAA==.Milkymocha:BAAANQAECgQIBgAAAA==.Misscorona:BAAANQAECgIIAgAAAA==.Mistyque:BAAANQAECgQIBgAAAA==.Mithrandir:BAAANQADCgUIBAAAAA==.Mithrond:BAAANQADCgEIAQAAAA==.',
Mo='Monalea:BAAANQAECgIIAgABNQAECggIIgAGAMsUAA==.Monkydleafy:BAAANQADCgQIAwABNQAECgEIAgACAAAAAA==.Morcant:BAAANQAECgQIBwAAAA==.Morianoley:BAAANQAECgIIAgAAAA==.Morlu:BAAANQAECgQIBgAAAA==.Mortenson:BAAANQAECgYICwAAAA==.Mortïmer:BAABNQAECoEdAAMSAAgKpBZpHwAaAgASAAgKpBZpHwAaAgAHAAMKXw1rwAChAAAAAA==.Mousee:BAAANQAECgIIAgAAAA==.',
Ms='Msdonnapally:BAAANQADCggIHwAAAA==.',
Mu='Muffindr:BAAANQADCggICAAAAA==.',
My='Mysticmage:BAAANQAECgUICAAAAA==.Myxian:BAEANQAECgQIBQABNQAECgkJJgAKAFgkAA==.',
['Mö']='Möñk:BAAANQADCgQIBQAAAA==.',
Na='Nala:BAAANQAECgEIAQAAAA==.Narallia:BAAANQADCgYICAAAAA==.Nargalad:BAAANQABCgQICAAAAA==.Narios:BAAANQAECgQICQAAAA==.Natureshogun:BAAANQAECgQIBAAAAA==.',
Ne='Nediem:BAAANQADCgQIBQAAAA==.Neral:BAAANQADCgMIAwAAAA==.Nexxicus:BAAANQADCgMJAwAAAA==.',
Ni='Nightmehr:BAABNQAECoEnAAIIAAkKOSDpNwALAwAIAAkKOSDpNwALAwAAAA==.Nightshade:BAAANQADCgcIDQAAAA==.Nippy:BAAANQADCgUIBQAAAA==.',
No='Nored:BAAANQADCgEIAQAAAA==.Nosaj:BAAANQAECgYIDQAAAA==.Nostrodomus:BAAANQADCgQIBwAAAA==.Novalee:BAAANQADCgEIAQAAAA==.',
Ny='Nyki:BAAANQADCgMIAwAAAA==.',
Od='Odlaw:BAAANQAECgQIBwAAAA==.',
Ol='Olaria:BAAANQAECgEIAQABNQAECgUICgACAAAAAA==.Olinax:BAABNQAECoEaAAQcAAgKhxJ1MwDTAQAcAAcKjhN1MwDTAQAgAAUKCBSYDgA0AQAYAAEKrQKSTQAtAAAAAA==.',
Om='Omalmalha:BAAANQAECgEIAQAAAA==.',
On='Onedruidtion:BAAANQAECgEIAQAAAA==.',
Or='Orheo:BAAANQADCgcICwAAAA==.Orionmoon:BAABNQAECoEcAAMHAAgKDg8rYgDHAQAHAAgKDg8rYgDHAQASAAYKMweZQAADAQAAAA==.Orlos:BAAANQAECgUICgAAAA==.Oräkk:BAABNQAECoEkAAMXAAgKsyPCBAAWAwAXAAgKsyPCBAAWAwAKAAIKxhKuCwGNAAAAAA==.',
Pa='Padrin:BAAANQAECgQIBwAAAA==.Pandapaws:BAABNQAECoErAAMMAAkKyCSaAwCiAwAMAAkKyCSaAwCiAwAOAAMKiQdd4QCYAAAAAA==.Papaflask:BAAANQAECgcIEAAAAA==.Parthal:BAAANQADCgEIAQAAAA==.Partyhardly:BAABNQAECoEiAAIWAAgKMhV8HADdAQAWAAgKMhV8HADdAQAAAA==.Pavetta:BAAANQAECgQIBAAAAA==.Pavle:BAAANQAECgIIAgAAAA==.',
Pd='Pdiddi:BAAANQAECggIDAAAAA==.',
Pe='Pellaeon:BAABNQAECoEuAAMUAAkKcBlvKABiAgAUAAkKcBZvKABiAgABAAgKjhYKQwDpAQAAAA==.Pelt:BAABNQAECoEkAAIJAAgKyRc6HgBCAgAJAAgKyRc6HgBCAgAAAA==.Perseus:BAAANQAECgEIAQABNQAECgQICQACAAAAAA==.Petmasta:BAAANQABCgEIAQABNQABCgQIBAACAAAAAA==.',
Ph='Pharaun:BAAANQAECgEIAQABNQAECggIKgABAN0HAA==.Phlan:BAEANQAECgQIBAAAAA==.Phrostir:BAAANQAECggIEAAAAA==.',
Pi='Picklechips:BAAANQADCgEIAQAAAA==.Pillgrimm:BAAANQAECgQICQAAAA==.Pillsburyman:BAAANQAECgIIAwAAAA==.',
Po='Pointee:BAAANQADCgYICgAAAA==.Poisson:BAABNQAECoEfAAIYAAkKqgt6FwARAgAYAAkKqgt6FwARAgAAAA==.Pokoxo:BAABNQAECoEoAAQWAAgKcBztEABpAgAWAAgKcBztEABpAgARAAQKRwmbEgHJAAAVAAMKBwr22ACgAAABNQAECgIIAwACAAAAAA==.Pookiez:BAEANQAECgIIAwABNQAECgkJHgAOAMclAA==.',
Pr='Prancine:BAAANQAECgQIBAABNQAFFAcIHgAHAHEYAA==.Prescess:BAAANQADCgUICAAAAA==.Providence:BAABNQAECoEqAAIGAAkKmR8cFADdAgAGAAkKmR8cFADdAgAAAA==.Prsr:BAAANQAECgMIBgABNQAFFAYIEQABAKMhAA==.',
Pu='Pudgypaws:BAAANQAECgQIBwAAAA==.Punishment:BAAANQABCgIIAgABNQAECgIIAgACAAAAAA==.',
Qu='Quickmend:BAAANQAECgQIBAAAAA==.Quickpal:BAAANQAECgcIEQAAAA==.Quickpaw:BAABNQAECoEfAAIdAAkKYxuIDACaAgAdAAkKYxuIDACaAgAAAA==.',
Ra='Raccoons:BAAANQADCgMIAwABNQAFFAUIDAAbAJEOAA==.Radell:BAAANQAECgQIBwAAAA==.Rageproof:BAAANQAECgEIAgAAAA==.Ragged:BAAANQAECggIEQAAAA==.Raidbloom:BAEBNQAFFIENAAIDAAUKYhKCBQCXAQADAAUKYhKCBQCXAQABNQAECgkJJgAVABMXAA==.Raidshock:BAEBNQAECoEmAAIVAAkKExeEMACIAgAVAAkKExeEMACIAgAAAA==.Rainsinger:BAAANQADCgcIGQAAAA==.Ramook:BAEANQADCggIIgAAAA==.Randomchar:BAABNQAECoEuAAIRAAkK4g/SdwANAgARAAkK4g/SdwANAgAAAA==.Rankor:BAAANQADCgYIBgABNQAECgkJKgAaABAQAA==.Rastann:BAABNQAECoEyAAIRAAkKVyDJNgDRAgARAAkKVyDJNgDRAgAAAA==.Ratsdrack:BAAANQADCgMIAwAAAA==.Rawrlas:BAAANQADCgMIAwABNQAECgUICgACAAAAAA==.Razdor:BAAANQADCgUIBgAAAA==.',
Re='Reapertoo:BAACNQAFFIEOAAMBAAYKzCH3AQAYAgABAAUKeyT3AQAYAgAQAAUKMhnsAwCfAQA1AAQKgScAAwEACQpjJcULAEgDAAEACAqpJcULAEgDABAACQpqILcSANgCAAAA.Recreant:BAAANQADCgcIDQAAAA==.Redbaron:BAABNQAECoEUAAIGAAcKkRdFNQDRAQAGAAcKkRdFNQDRAQAAAA==.Redmtndew:BAAANQAECgIIAgAAAA==.Reetep:BAAANQADCggIGQABNQAECgEIAwACAAAAAA==.Regeth:BAAANQADCggIFQAAAA==.Remily:BAAANQAECgUIBQABNQAECgkJJAAIACceAA==.Repuns:BAEANQAECggIAQABNQAECggIIQAEAMokAA==.Revin:BAAANQAECgEJAQAAAA==.Rezalia:BAAANQADCgMIAwAAAA==.',
Ro='Rodned:BAAANQADCggJCAAAAA==.Rolas:BAAANQADCgEIAQABNQAECgUICgACAAAAAA==.Rondle:BAAANQAECgQIBAAAAA==.Rottencorpse:BAAANQADCgQIBAAAAA==.Rozalin:BAABNQAECoEtAAIIAAkKKyPjFwBuAwAIAAkKKyPjFwBuAwAAAA==.Rozalinamoon:BAAANQADCgMIAwAAAA==.',
Ru='Rurouni:BAAANQAECgIIAgAAAA==.Rustystorm:BAAANQADCgMIAwAAAA==.Rustywarlock:BAAANQAECgEIAQAAAA==.',
Ry='Ryoshi:BAABNQAECoEhAAMfAAkKox/vKwDJAgAfAAkKox/vKwDJAgAjAAcKaxZjBwDTAQAAAA==.',
['Rò']='Ròòszy:BAAANQADCgYIBwAAAA==.',
Sa='Sacredstars:BAAANQAECgUIBQAAAA==.Sacredswords:BAABNQAECoEfAAMKAAkK1hfZWgBeAgAKAAkK1hfZWgBeAgALAAEK0wjZLwAuAAAAAA==.Sakito:BAAANQAECgUIBQABNQAFFAYIEwAMAOUUAA==.Salarai:BAAANQADCgcIBgABNQAECgUICgACAAAAAA==.Sanguinius:BAABNQAECoEfAAMVAAkK7yJ1BQCYAwAVAAkK7yJ1BQCYAwARAAIKAgVVWQFPAAAAAA==.Sapphiremist:BAAANQAECgUIDAAAAA==.Sayen:BAAANQAFFAEIAQAAAA==.',
Sc='Scachity:BAABNQAECoEeAAMbAAcKKBVodwDSAQAbAAcKgBRodwDSAQAiAAMKxxP/QAC1AAAAAA==.Scan:BAABNQAECoEdAAIOAAkKZRsvLACqAgAOAAkKZRsvLACqAgAAAA==.Schein:BAAANQAECgYIDQAAAA==.',
Se='Segsacute:BAAANQAECggIDgAAAA==.Sendatu:BAAANQAECgEIAgABNQAECgcIHQABAO0PAA==.Sepulchre:BAABNQAECoEqAAMBAAgK3QevawA/AQABAAgKhQavawA/AQAQAAYK/QQWYgDPAAAAAA==.',
Sh='Shadesfault:BAAANQADCgUIDQAAAA==.Shadowhart:BAAANQADCgEIAQAAAA==.Shaeebulay:BAAANQABCgQIBAAAAA==.Shamaroo:BAAANQABCgUIBwAAAA==.Shaundakul:BAAANQAECgQICwAAAA==.Shephion:BAAANQAECgQIDwABNQAECgkJMwAdAEwlAA==.Shnozberries:BAAANQADCgEJAQAAAA==.Shockhart:BAAANQAECgcICwAAAA==.Shonuffz:BAAANQADCgYIBgAAAA==.Shortnstack:BAAANQAECgQICQAAAA==.Shãdow:BAAANQADCgUIBQAAAA==.',
Si='Siegfried:BAAANQAECgQIBAAAAA==.Simori:BAAANQADCgIIAgAAAA==.Sindrel:BAAANQAECgUIBQABNQAECgkJKgAeAAEjAA==.Siyurie:BAAANQADCgcIEAAAAA==.',
Sk='Skawalker:BAABNQAECoExAAIDAAkK1yGsBwAzAwADAAkK1yGsBwAzAwAAAA==.',
Sl='Slaed:BAAANQADCgYIBwAAAA==.Slaynne:BAAANQAECgcIEwAAAA==.',
Sm='Smoky:BAAANQAECgUIBwAAAA==.Smäug:BAACNQAFFIEQAAMZAAYK7BysAgDIAQAZAAUKXR2sAgDIAQAaAAEKuBruCABcAAA1AAQKgSgAAxkACQqhJG8BAKsDABkACQqhJG8BAKsDACQABQoIEcsqADABAAAA.',
Sn='Snailas:BAAANQADCggIDwAAAA==.Sniperwolf:BAAANQADCgQIBAABNQAECgIIAgACAAAAAA==.',
So='Sodomn:BAAANQADCgQIBAAAAA==.Solria:BAABNQAECoEYAAIHAAcKCBjtSQAgAgAHAAcKCBjtSQAgAgAAAA==.Sonnytyphoon:BAAANQADCgYIBgAAAA==.',
Sp='Spex:BAAANQADCgUIBQAAAA==.',
St='Starnex:BAAANQAECgcIBwAAAA==.Statyrea:BAAANQADCgUIBQAAAA==.Styx:BAABNQAECoE8AAIXAAkK3SYLAAATBAAXAAkK3SYLAAATBAAAAA==.',
Su='Sugabuns:BAAANQAECgcIBwAAAA==.Sukfööt:BAABNQAECoEeAAIXAAgKOxEaFQCoAQAXAAgKOxEaFQCoAQAAAA==.Sumbatadh:BAAANQAECgYIBwAAAA==.Summerflip:BAAANQADCggICAABNQAECgkJLgAHACIdAA==.Sunnytyphoon:BAABNQAECoEWAAIlAAgKjRObDQAJAgAlAAgKjRObDQAJAgAAAA==.',
Sw='Swiftholy:BAAANQAECgYIEgAAAA==.Swiftmends:BAAANQAECgIIAgAAAA==.',
Sy='Sydahlis:BAAANQAECgcIDQAAAA==.Sylvestris:BAAANQAECgcIEAAAAA==.',
Ta='Taiyana:BAAANQAECgQIBAAAAA==.Tangie:BAAANQADCggICgAAAA==.Tankjob:BAAANQAECgQIDAAAAA==.Tanklorswift:BAAANQADCggIFwAAAA==.Tastemycrits:BAAANQADCggICAABNQAECgkJGQARAKAcAA==.',
Td='Tdog:BAAANQADCggICwAAAA==.',
Te='Tealetresh:BAAANQABCgIIAgAAAA==.Teapot:BAAANQAECgYIBAAAAA==.Tedoseirum:BAABNQAECoEnAAIGAAkK7CDACgBHAwAGAAkK7CDACgBHAwAAAA==.Terminal:BAAANQADCggICwAAAA==.Terpyu:BAAANQADCgEIAQAAAA==.Texasbilly:BAAANQADCgYIDAAAAA==.Texasredneck:BAAANQADCgYIDAAAAA==.Texasslasher:BAAANQADCgYIBgAAAA==.',
Th='Thedtwo:BAAANQAECgEIAQAAAA==.Thorgarrus:BAABNQAECoEzAAIRAAkKER7RMgDgAgARAAkKER7RMgDgAgAAAA==.',
Ti='Tigerwoodz:BAAANQAECgEIAQAAAA==.Timvoker:BAAANQADCgYIBgAAAA==.',
To='Toddie:BAABNQAECoEgAAMfAAgKlRysNwChAgAfAAgKlRysNwChAgAhAAEKRA2CfgAxAAAAAA==.Tolkarnyx:BAAANQADCgUIBQABNQAFFAQICgAMACoXAA==.Tommyj:BAAANQADCggICwAAAA==.Torcher:BAAANQADCgYIBgAAAA==.Tormod:BAABNQAECoEaAAIfAAgKThWxWQA9AgAfAAgKThWxWQA9AgAAAA==.Torvaldt:BAAANQAECgUICAABNQAECggIIAAfAJUcAA==.Tourmod:BAAANQAECgQICAAAAA==.Towmater:BAAANQAECgIIAgAAAA==.',
Tr='Trakkarz:BAAANQAECgIIAgAAAA==.Traps:BAAANQAECgIIAwAAAA==.Trashypanda:BAACNQAFFIELAAIIAAQK3Re3HgBQAQAIAAQK3Re3HgBQAQA1AAQKgSMAAggACQokIo0wAB8DAAgACQokIo0wAB8DAAAA.Trays:BAAANQADCgYIBgAAAA==.Trender:BAAANQADCgQIBAAAAA==.Treniity:BAAANQAECgQIBAAAAA==.Tressilly:BAABNQAECoEkAAIIAAkKJx6IMQAdAwAIAAkKJx6IMQAdAwAAAA==.Trinagirl:BAAANQADCgYIBgAAAA==.Trinneries:BAAANQADCgcJBwAAAA==.Triná:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Tristanyia:BAAANQADCggICAAAAA==.Trogdorr:BAABNQAECoEqAAMaAAkKEBCwCQC1AQAaAAgKCBGwCQC1AQAZAAcKVwy9GgCAAQAAAA==.Trutert:BAAANQAECgIIAwAAAA==.Tryana:BAAANQADCggINQAAAA==.Trystiana:BAAANQADCgMJBAAAAA==.',
Tt='Ttania:BAAANQADCgYIDgAAAA==.',
Tu='Tubor:BAAANQAECgMIBQAAAA==.',
Tw='Tweetwee:BAAANQAECgUIBwAAAA==.',
Ty='Tyledis:BAAANQADCggIEAABNQAECgkJLQAXAD8kAA==.Tyr:BAABNQAECoEpAAMOAAkK4B6YGwAMAwAOAAkK4B6YGwAMAwAMAAIK1gn37gBaAAAAAA==.Tyrnova:BAAANQADCggICAAAAA==.',
['Tö']='Töshïrö:BAAANQADCgIIAgAAAA==.',
Uh='Uhope:BAAANQAECgUIBQAAAA==.',
Um='Umbravolt:BAABNQAECoEzAAIFAAkK8iNlAgCPAwAFAAkK8iNlAgCPAwAAAA==.',
Un='Unclezapp:BAAANQADCggJDgAAAA==.Unravel:BAAANQADCgUICgAAAA==.Unrealcalorx:BAAANQADCgUIBQAAAA==.Unrealronin:BAAANQAECgUICQAAAA==.',
Va='Vaeris:BAAANQADCgUJCwAAAA==.Vakero:BAAANQAECgUIDAAAAA==.Valess:BAAANQAECgQICwAAAA==.Valros:BAAANQADCgYICgAAAA==.Vapor:BAAANQABCgIIAgAAAA==.Vaythan:BAAANQAECgcIEwAAAA==.',
Ve='Venchris:BAAANQAECgcIEAAAAA==.Verica:BAAANQADCgEIAQAAAA==.',
Vh='Vhiz:BAAANQAECgUIEAAAAA==.',
Vi='Vibrance:BAAANQADCggJEAAAAA==.Victorius:BAAANQAECgMIAwAAAA==.Viridesa:BAAANQADCgcIFAAAAA==.Vixine:BAAANQAECgQIBAAAAA==.',
Vn='Vnillabeef:BAAANQADCgIIAgABNQAFFAYIEQABAKMhAA==.',
Vo='Vohlen:BAAANQABCgYIBgAAAA==.Voidcore:BAAANQAFFAEIAQABNQAECggIFgAKALEWAA==.Voidwalker:BAAANQADCgYICQABNQAFFAUIDAANAHYUAA==.',
Vy='Vysera:BAAANQAECgEIAQAAAA==.',
Wa='Warfarmer:BAAANQAECgQIBgAAAA==.Warhawke:BAAANQADCggIEAAAAA==.',
We='Werenal:BAAANQADCgcICwAAAA==.',
Wh='Whis:BAAANQAECgQICAAAAA==.Whispernight:BAAANQADCgMJBQAAAA==.',
Wi='Widja:BAAANQADCgUIDgAAAA==.Wiimage:BAAANQAECgQIBQAAAA==.Wiivinelight:BAAANQADCgMIAwABNQAECgQIBQACAAAAAA==.Wildhus:BAABNQAECoEiAAIGAAgKyxT0LQAIAgAGAAgKyxT0LQAIAgAAAA==.',
Wo='Wolfkin:BAAANQADCggIBwAAAA==.',
Wy='Wyckdd:BAAANQADCgYIBgAAAA==.',
['Wå']='Wåffle:BAAANQAECgUICwABNQAECgkJKQAcAOsiAA==.',
['Wî']='Wîca:BAABNQAECoEXAAISAAcKBwx6MQBuAQASAAcKBwx6MQBuAQAAAA==.',
Xa='Xantris:BAAANQADCgEIAQAAAA==.',
Xe='Xenowolf:BAAANQADCgYJCgABNQAECgQICQACAAAAAA==.',
Xv='Xvire:BAAANQAECgEIAQAAAA==.',
['Xû']='Xûrû:BAAANQAECgcICgAAAA==.',
Yc='Yce:BAAANQAECgQICQAAAA==.',
Ye='Yeiko:BAAANQAECgUIBgAAAA==.',
Yo='Yoker:BAAANQAECgUICwAAAA==.Yokersen:BAAANQAECgcIEgAAAA==.',
Za='Zaeladen:BAAANQAECgEIAgAAAA==.Zalorea:BAAANQAECgQIBwABNQAECggIJwAQAPoMAA==.Zambonii:BAAANQAECgUICAABNQAECgkJMAAiAKohAA==.Zamdeath:BAAANQADCgMIAwABNQAECgkJMAAiAKohAA==.Zamlock:BAABNQAECoEwAAMiAAkKqiERDgANAgAbAAcKQCHyOwCEAgAiAAYKGh4RDgANAgAAAA==.Zanya:BAAANQAECgEIAgAAAA==.',
Ze='Zeiko:BAABNQAECoEVAAIBAAcKniIyJgCEAgABAAcKniIyJgCEAgAAAA==.Zestychip:BAAANQAECgIIAgAAAA==.Zeäl:BAAANQADCgUIBgAAAA==.',
Zh='Zhaoyun:BAAANQAECgQIBAAAAA==.',
Zi='Zilkir:BAEBNQAECoElAAMRAAkKzRrHRQCeAgARAAkKzRrHRQCeAgAVAAcK0hM8XgDaAQAAAA==.Ziran:BAABNQAECoEiAAIeAAkKriQGAgC6AwAeAAkKriQGAgC6AwAAAA==.Zivadhim:BAAANQADCgIIAgAAAA==.',
Zl='Zlyth:BAAANQAECgMIBQAAAA==.',
Zz='Zzodac:BAAANQADCgEIAQABNQAECggIIgAGAMsUAA==.Zzvzz:BAAANQAECgQIBAAAAA==.',
['Är']='Ärtrix:BAAANQAECgIIAwAAAA==.',
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
