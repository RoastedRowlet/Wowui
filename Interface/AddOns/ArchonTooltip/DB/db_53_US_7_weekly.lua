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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','Priest-Holy','Mage-Arcane','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Frost','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Paladin-Holy','Paladin-Protection','Warrior-Protection','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Rogue-Assassination','Monk-Mistweaver','Monk-Windwalker','Rogue-Outlaw','Hunter-Marksmanship','Warlock-Destruction','Hunter-Survival','Druid-Feral','Evoker-Preservation',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abnalem:BAAANQADCgIIAgAAAA==.',
Ac='Aceventuraa:BAAANQADCgEIAQAAAA==.',
Ad='Adramalech:BAAANQADCgQIBAABNQAFFAYIEQABAF4fAA==.',
Ae='Aeakos:BAAANQAECgIIAwABNQAECggIJAACAKURAA==.Aeldon:BAAANQADCggIIAAAAA==.',
Ai='Airese:BAAANQAECgIIAwABNQAECgQIBwADAAAAAA==.Airist:BAAANQAECgQIBwAAAA==.Aisele:BAABNQAECn8WAAIEAAcKTAPPIQDZAAAEAAcKTAPPIQDZAAAAAA==.',
Al='Alander:BAAANQAECgUIBQAAAA==.Alastor:BAAANQADCgcICwAAAA==.Alathir:BAABNQAECn8UAAIFAAYK7RnkmwDLAQAFAAYK7RnkmwDLAQAAAA==.Alluri:BAAANQAECggIDwAAAA==.Althemia:BAAANQAECgMIAwAAAA==.Alunamora:BAABNQAECn8tAAIGAAkK6xqsFQCVAgAGAAkK6xqsFQCVAgAAAA==.Alwind:BAABNQAECn8eAAMHAAgK7A8tQwDkAQAHAAgK7A8tQwDkAQAIAAUKgAN5RQCVAAAAAA==.',
Am='Ammaris:BAAANQAECgQIBAAAAA==.',
An='Analani:BAAANQAECgMIBAAAAA==.Anali:BAAANQAECgUIBwAAAA==.Angis:BAAANQADCgQICAAAAA==.Angryheals:BAAANQAECgUIBwAAAA==.Ansfrid:BAAANQADCggIDgAAAA==.',
Ap='Apøllø:BAABNQAECn8gAAIJAAkKnwewQAC0AQAJAAkKnwewQAC0AQAAAA==.',
Aq='Aquatofana:BAAANQAECgQICAAAAA==.',
Ar='Aranel:BAAANQADCgYIBgAAAA==.Arcamancer:BAAANQAECgIIAwAAAA==.Arinthal:BAAANQAECgUICwAAAA==.Arkenfel:BAAANQADCgQIBAAAAA==.Aroia:BAAANQAECgYIDwAAAA==.Arril:BAAANQAECgUIDAAAAA==.Artemissy:BAAANQADCgUICwAAAA==.Artiis:BAAANQAECggICAAAAA==.Artrimus:BAAANQADCgUIBQAAAA==.',
As='Asham:BAAANQADCggICAAAAA==.Ashlieghee:BAABNQAECn8oAAIKAAkKtB2kGQAMAwAKAAkKtB2kGQAMAwAAAA==.Ashron:BAAANQAECgcICQABNQAECgkJLQALAOEhAA==.Ashuraa:BAAANQADCgQIBAABNQAECgcIEwADAAAAAA==.Astien:BAAANQAECgIIBQAAAA==.Astralee:BAAANQADCggIDwAAAA==.',
Au='Audric:BAAANQADCgYIBwAAAA==.Auot:BAAANQAECgMIAwAAAA==.',
Av='Avelen:BAABNQAECn8XAAMBAAgKfx5NLQB7AgABAAgKfx5NLQB7AgACAAEKfAohxgA5AAAAAA==.Averlen:BAAANQAECgUICgAAAA==.Avha:BAAANQAECgQICQAAAA==.Avistero:BAAANQADCgUIBwAAAA==.',
Ax='Axel:BAABNQAECn8nAAIJAAkKhx6zDwAhAwAJAAkKhx6zDwAhAwAAAA==.',
Ay='Aylden:BAABNQAECn8dAAMJAAgKwQ+wPwC6AQAJAAgKwQ+wPwC6AQAMAAIK2AG6ZgBDAAAAAA==.Aylshm:BAAANQADCgYIFAAAAA==.Ayrene:BAAANQADCgcIBwABNQAECgQIBQADAAAAAA==.',
Az='Azenazar:BAAANQADCgEIAQAAAA==.Azog:BAAANQAECgEIAQAAAA==.Azsharianna:BAAANQABCggIEAAAAA==.',
Ba='Bailas:BAAANQAECgUIBwAAAA==.Battousai:BAAANQADCgMIAwAAAA==.Bazileth:BAAANQADCgYIBgAAAA==.',
Be='Bearistotle:BAAANQAECgEIAQAAAA==.Beastm:BAAANQAECgQIBAAAAA==.Beastmehr:BAAANQAECgQICAABNQAECgkJKgALAGEgAA==.Beauregardl:BAAANQAECgEJAQAAAA==.Bellina:BAAANQADCgcIBwAAAA==.Belwyn:BAAANQADCgUIBgAAAA==.Benjofamin:BAAANQAECgYIBwAAAA==.',
Bi='Bitesize:BAEBNQAECn8oAAMNAAkKbCTtFABlAwANAAkKbCTtFABlAwAOAAEK1yRxKQBhAAAAAA==.',
Bl='Blakelivly:BAEBNQAECn8iAAQPAAkKtB/lJQDqAgAPAAgKtB/lJQDqAgAQAAgKcB/BJwDDAgARAAUKMBoGIABZAQABNQAECgkJIwAHABUjAA==.Blashster:BAABNQAECn8tAAMLAAkK4SE/GQBwAwALAAkK4SE/GQBwAwAEAAEKPxnkQQA+AAAAAA==.Blightsize:BAEANQADCgMIAwABNQAECgkJKAANAGwkAA==.Blkplayge:BAAANQADCgMIAwAAAA==.',
Bo='Bonemilker:BAACNQAFFH8RAAMBAAYKXh+6AQA7AgABAAYK4R66AQA7AgASAAQKJhvECABaAQA1AAQKfywAAxIACQqTJScMADIDABIACQouJScMADIDAAEABQpMHM1cAJgBAAAA.Bonkdaddy:BAABNQAECn8dAAITAAkKFh/DOADrAgATAAkKFh/DOADrAgAAAA==.Bopeep:BAAANQAECgcICwAAAA==.',
Br='Brandt:BAAANQABCgQICAAAAA==.Breelyssa:BAAANQAECgIIBAAAAA==.Brego:BAAANQAECgIIAgAAAA==.Brenna:BAAANQAECgMIAwABNQAECggIHgAHAOwPAA==.Brewslèé:BAAANQABCgYIBgAAAA==.Brighter:BAABNQAECn8yAAQUAAkK+BnBHABaAgAUAAgKiRnBHABaAgAKAAYKlxagjgBmAQAVAAYKshIGDgBOAQAAAA==.Brightsize:BAEANQAECgYICwABNQAECgkJKAANAGwkAA==.Broncopally:BAAANQADCgQIBAAAAA==.Brótien:BAAANQADCggICAABNQAECgYIBgADAAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bunnka:BAAANQADCgYIBgAAAA==.Bunnyparade:BAAANQADCgYIDAAAAA==.',
Ca='Cakesdruid:BAAANQAECgQIBAAAAA==.Caledwar:BAAANQAECgQIDwAAAA==.Calrissa:BAAANQADCgMIAwABNQAECgYIFAAFAO0ZAA==.Calthirstrap:BAACNQAFFH8NAAMBAAUKKx2MCwBSAQABAAQKKx2MCwBSAQACAAEKAAApNQAnAAA1AAQKfyoAAgEACQqlJMcLAFsDAAEACQqlJMcLAFsDAAAA.Carare:BAAANQADCgYICgAAAA==.Carnàge:BAAANQAECgMIBgAAAA==.Casterrata:BAAANQADCggICAAAAA==.',
Ce='Ceefack:BAAANQAECgMIBgAAAA==.Cethin:BAAANQAECgIIBAAAAA==.',
Ch='Chaargee:BAAANQAECgYIDwAAAA==.Chaosshot:BAAANQAECgMIAwAAAA==.Cheedar:BAACNQAFFH8HAAMWAAMKzQuzGQDNAAAWAAMKzQuzGQDNAAAXAAEKTAAFFQAYAAA1AAQKfxwAAhYACQq8EAVSACICABYACQq8EAVSACICAAAA.Chelaria:BAAANQAECgMIAwAAAA==.Cherylindrea:BAAANQADCgUIDgAAAA==.Chillwombat:BAAANQADCggIIgAAAA==.Chumlei:BAAANQADCgcIBwAAAA==.',
Ck='Ckz:BAAANQAECggIBAAAAA==.',
Cl='Claydemon:BAAANQAECgQICAAAAA==.Clayvicar:BAABNQAECn80AAMKAAkKBQy9aQDdAQAKAAkKBQy9aQDdAQAUAAIKVgMDaABcAAAAAA==.',
Co='Coridane:BAAANQAECgYIEwAAAA==.Corrum:BAAANQAECgUIBQAAAA==.Corwinfiron:BAABNQAECn8bAAILAAgKzwkk9ACgAQALAAgKzwkk9ACgAQAAAA==.',
Cr='Crosse:BAAANQAECgQIBwAAAA==.Cruellà:BAAANQADCgYIEwAAAA==.Cryptcrawler:BAAANQAECgEIAgAAAA==.',
Cu='Cuddleme:BAAANQADCgcIBwAAAA==.Curkage:BAAANQADCgQIBQAAAA==.',
Cy='Cythera:BAACNQAFFH8MAAIRAAUKVxudAgCeAQARAAUKVxudAgCeAQA1AAQKfysAAhEACQo0JksDAGoDABEACQo0JksDAGoDAAAA.',
['Cá']='Cámus:BAABNQAECn8bAAITAAYKnBQn0wBvAQATAAYKnBQn0wBvAQAAAA==.',
Da='Daammy:BAAANQAECgIIAgAAAA==.Daayumgurl:BAAANQADCgYIBgAAAA==.Dagren:BAAANQADCggIHgAAAA==.Daisy:BAAANQABCggILQABNQABCggILgADAAAAAA==.Dakdor:BAAANQADCgMIAwAAAA==.Daphine:BAAANQADCgUIDwAAAA==.Darimonk:BAAANQADCgEIAQABNQADCgYICgADAAAAAA==.Darivara:BAAANQADCgYICgAAAA==.Darkbeautie:BAAANQAECgQIDQAAAA==.Darkcarbon:BAAANQAECgUIEAAAAA==.Darkchylde:BAAANQADCgUIBQABNQAECgUIEAADAAAAAA==.Darkplazzma:BAAANQAECgEIAQAAAA==.Darmin:BAAANQABCgQIBAAAAA==.',
De='Deathmask:BAAANQAECgIIAwAAAA==.Deathspal:BAABNQAECn8iAAMTAAgK2xJ/pwDMAQATAAgK2xJ/pwDMAQAXAAIKpQiMZgBFAAAAAA==.Dementedfun:BAAANQAECggICAAAAA==.Dessembrae:BAABNQAECn81AAIYAAkKjiSPAQC0AwAYAAkKjiSPAQC0AwAAAA==.Dewkiez:BAEBNQAECn8eAAIPAAkKnyXwBQC5AwAPAAkKnyXwBQC5AwAAAA==.',
Di='Diabolicarl:BAABNQAECn8iAAIJAAgKUwqFQwCiAQAJAAgKUwqFQwCiAQAAAA==.Diri:BAAANQAECgMIAwABNQAECgkJHwAZAMELAA==.',
Dm='Dmmeforpi:BAAANQADCgYICgABNQAECgMIAwADAAAAAA==.',
Do='Docphanan:BAAANQAECgEIAgAAAA==.Doesntheal:BAAANQABCgIIAgAAAA==.Dookiez:BAEANQAECgcIDAABNQAECgkJHgAPAJ8lAA==.Doubledragin:BAABNQAECn8fAAMaAAcKKRTBFwDLAQAaAAcKCBTBFwDLAQAbAAQKpRT2FQDPAAAAAA==.',
Dr='Dracantar:BAAANQADCggIEQAAAA==.Dractini:BAAANQADCgcICgABNQAFFAgIIAAKAK8WAA==.Dragfan:BAAANQADCgQJBAAAAA==.Dragonbelly:BAAANQABCggILgAAAA==.Dragondeez:BAAANQABCgQIBAABNQAECgQIBgADAAAAAA==.Dragore:BAABNQAECn8eAAINAAgKhwwMpAC+AQANAAgKhwwMpAC+AQAAAA==.Druidgirls:BAABNQAECn82AAIGAAkK+Bj8FQCSAgAGAAkK+Bj8FQCSAgAAAA==.',
Du='Duelist:BAAANQAECgcICQAAAA==.Dupree:BAAANQADCgQIBQAAAA==.Durogdem:BAAANQADCgYIBgAAAA==.Duskfire:BAAANQABCgQICAAAAA==.',
Ea='Earthaggie:BAAANQADCgUIDgAAAA==.',
Ec='Echlipse:BAAANQAECgQIBQABNQAECgkJIgAXAJghAA==.',
Ed='Ederon:BAAANQABCggICAAAAA==.Edirae:BAAANQAECgIIAgABNQAECgkJJQAQACsaAA==.',
El='Elenora:BAABNQAECn8fAAIHAAgKTAZFYABKAQAHAAgKTAZFYABKAQAAAA==.Ellea:BAAANQAECgUICgAAAA==.Ellesmere:BAAANQAECgIIAgABNQAFFAkJHQAWABQbAA==.Elye:BAAANQAECgYIDAAAAA==.',
Em='Emer:BAAANQAECgYICgAAAA==.Emiru:BAAANQADCgUJBgAAAA==.',
En='Encore:BAABNQAECn81AAIGAAgK2gsfMgCFAQAGAAgK2gsfMgCFAQAAAA==.',
Eo='Eousphorus:BAABNQAECn80AAMLAAkK3BvCMwAjAwALAAkK3BvCMwAjAwAEAAIK/QgBOgBUAAAAAA==.',
Er='Erathen:BAAANQADCggICgAAAA==.Eryanna:BAAANQAECgIIBAAAAA==.',
Es='Esplan:BAEANQAECgcIEwABNQAECgkJIwAHABUjAA==.',
Eu='Euden:BAAANQADCgQIBAAAAA==.',
Ev='Evelleion:BAAANQAECgYIDwAAAA==.',
Ex='Excedrin:BAAANQADCgIIAgAAAA==.Exoticlord:BAAANQAECgQIBAAAAA==.',
Fe='Felhayde:BAAANQADCgYIBgAAAA==.Felicity:BAAANQADCggIDAAAAA==.Fenryyr:BAAANQADCgYJBwAAAA==.',
Fi='Fierygrace:BAAANQADCgcIEAAAAA==.Firburger:BAAANQAECgQICgAAAA==.Fischl:BAAANQAECgQIBgAAAA==.Fitzmagic:BAAANQAECgcIBwAAAA==.',
Fl='Flameth:BAABNQAECn84AAIcAAkKIg9cWwBBAgAcAAkKIg9cWwBBAgAAAA==.Fling:BAAANQADCgMIAwAAAA==.Flirtywombat:BAAANQAECgIIBAAAAA==.',
Fr='Freezrorburn:BAAANQADCgYIBwAAAA==.',
Fu='Fujitto:BAAANQADCgIIAgAAAA==.Fumanchu:BAABNQAECn8jAAIYAAkK5Bt0CADKAgAYAAkK5Bt0CADKAgAAAA==.Fuzugchu:BAAANQAECgYICwABNQAECgkJIwAYAOQbAA==.',
Ga='Gaamora:BAAANQADCgUIEwAAAA==.Gabooda:BAAANQADCgUIBQABNQAECgIIAwADAAAAAA==.Gainsborough:BAABNQAECn8qAAMTAAkKLCA2JwAnAwATAAkKLCA2JwAnAwAXAAMKaRRnTgCqAAABNQAFFAYIEwAQAOUUAA==.Gamegg:BAAANQAECgUICgAAAA==.Garagos:BAABNQAECn81AAIdAAkK7xqFFADTAgAdAAkK7xqFFADTAgAAAA==.',
Ge='Gebuss:BAABNQAECn8qAAIdAAkKnyMbCABSAwAdAAkKnyMbCABSAwAAAA==.',
Gi='Gilford:BAAANQAECgUICgAAAA==.',
Gl='Glenraven:BAAANQAECgEIAgAAAA==.',
Go='Golokan:BAAANQADCgYIDAAAAA==.Goochaddi:BAABNQAECn8ZAAITAAkKRBuIegAyAgATAAkKRBuIegAyAgAAAA==.Gorgunga:BAAANQAECgUIBQAAAA==.Gozer:BAAANQABCgcICQAAAA==.',
Gr='Grolden:BAAANQAECgQIBAAAAA==.Grïpnrïp:BAAANQAECgEIAQAAAA==.',
Gu='Gunnerrata:BAAANQAECgQIBAAAAA==.',
Ha='Hahalua:BAAANQAECgQIAwAAAA==.Halieight:BAAANQAECgIIAgABNQAECgkJNgALAN0aAA==.Halifaxx:BAABNQAECn82AAILAAkK3RrUOgARAwALAAkK3RrUOgARAwAAAA==.Halifive:BAAANQADCgIIAgABNQAECgkJNgALAN0aAA==.Haliseven:BAAANQADCgQIBAABNQAECgkJNgALAN0aAA==.Halisix:BAAANQADCgIIAgABNQAECgkJNgALAN0aAA==.Halithree:BAAANQADCgYICgABNQAECgkJNgALAN0aAA==.Halitwo:BAAANQADCggICgABNQAECgkJNgALAN0aAA==.Hapiagin:BAAANQAECgUICgAAAA==.Haraboo:BAAANQAECgUIBwAAAA==.Harmaa:BAAANQAECgYICwAAAA==.Hauron:BAAANQAECgMIAwABNQAECgQIBwADAAAAAA==.Havengul:BAAANQAECggIEAAAAA==.Hawknor:BAAANQAECgUIDAAAAA==.',
He='Healthcare:BAABNQAECn8rAAMQAAkKQBYfPgBlAgAQAAkKQBYfPgBlAgAPAAUKzwz7wwAGAQABNQAFFAgIIAAKAK8WAA==.Healthplan:BAAANQADCgYIBgABNQAECggIGwAWAEQUAA==.Heartilly:BAACNQAFFH8TAAIQAAYK5RSaBwDZAQAQAAYK5RSaBwDZAQA1AAQKfzMAAhAACQrSIWsOAE0DABAACQrSIWsOAE0DAAAA.Herm:BAABNQAECn88AAMeAAkKTCWcAQC0AwAeAAkKTCWcAQC0AwAfAAcKDhpqIwAHAgAAAA==.',
Ho='Holyfu:BAAANQAECgUIDAABNQAECgkJIwAYAOQbAA==.Holymidget:BAAANQAECgEIAQAAAA==.Holysky:BAAANQAECgMIBwAAAA==.Holytim:BAABNQAECn8rAAQKAAkK3h11IgDiAgAKAAkK3h11IgDiAgAVAAcKhRVuCADcAQAUAAIK0A1eZwBeAAAAAA==.Honeypackz:BAAANQAECgcICgAAAA==.Honnik:BAAANQABCgIIAgAAAA==.Hotpink:BAAANQADCgUIDQAAAA==.How:BAABNQAECn8fAAMeAAkK7B/ACAD+AgAeAAkK7B/ACAD+AgAfAAIKAA7YXABoAAAAAA==.',
Hu='Humongulus:BAAANQAECgcIEwAAAA==.',
Ic='Ickysins:BAAANQAECgEIAQAAAA==.Ickystix:BAAANQADCgMIAwABNQAECgQIBgADAAAAAA==.',
Ig='Ignored:BAAANQAECggIEQAAAA==.Ignöred:BAABNQAECn8ZAAINAAcKexjMkQDrAQANAAcKexjMkQDrAQAAAA==.',
Il='Ila:BAAANQADCgIIAgAAAA==.Ilidra:BAAANQAECgEIAQAAAA==.Illaine:BAAANQADCgYIBgAAAA==.Illidæn:BAABNQAECn8gAAIMAAgK2w5YLgDKAQAMAAgK2w5YLgDKAQAAAA==.',
Im='Imgonaruneya:BAAANQAECgQIBAAAAA==.Imos:BAAANQABCgQIBAAAAA==.Imperîus:BAAANQADCgUIBQABNQAFFAYIEQABAF4fAA==.',
In='Inaniel:BAABNQAECn8YAAIMAAgKcBprHwBRAgAMAAgKcBprHwBRAgAAAA==.Inq:BAABNQAECn8uAAMLAAkKIyJYHQBiAwALAAkKIyJYHQBiAwAEAAEKLgvETQAqAAAAAA==.',
Ir='Iridaceaë:BAABNQAECn8jAAIKAAgKUxtnQgBeAgAKAAgKUxtnQgBeAgABNQAECgYICAADAAAAAA==.Iryris:BAAANQAECgMIBwAAAA==.',
Is='Isedeath:BAABNQAECn8wAAQBAAkKSBYnSQDuAQABAAgKHhYnSQDuAQASAAkKoAoKRgChAQACAAEKOB23wQBBAAAAAA==.Istvankh:BAAANQABCgMIBAABNQADCgEIAQADAAAAAA==.',
Ja='Jaholin:BAAANQAECgUICQAAAA==.Jarhead:BAAANQADCgIIAgAAAA==.Jarrhead:BAAANQAECgIIAwAAAA==.Jaxarus:BAAANQADCgEIAQAAAA==.',
Je='Jenaveive:BAABNQAECn8XAAIFAAcKawtEogC9AQAFAAcKawtEogC9AQAAAA==.Jethoisi:BAAANQAECgYIEAABNQAFFAUICwAXAHIIAA==.Jexi:BAAANQADCgYJBgABNQAECgQIBQADAAAAAA==.',
Jn='Jnex:BAAANQAECggIEAAAAA==.',
Jo='Jongani:BAABNQAFFH8LAAIXAAUKcgiWBgAbAQAXAAUKcgiWBgAbAQAAAA==.Jookiez:BAEANQAECgYIBwABNQAECgkJHgAPAJ8lAA==.',
Jr='Jrrtrolkien:BAAANQADCgQIBAABNQAECgEIAgADAAAAAA==.',
Ju='Judgemehr:BAAANQAECgYIDQABNQAECgkJKgALAGEgAA==.Judgepain:BAAANQAECggICAAAAA==.Judgmental:BAABNQAECn8pAAIWAAkKrB6ZFQAnAwAWAAkKrB6ZFQAnAwAAAA==.Justine:BAAANQAECgUICgAAAA==.',
Ka='Kaboni:BAAANQAECgIIAwAAAA==.Kaelthorn:BAAANQAECgUIBQAAAA==.Kaelysong:BAAANQADCgUJDQAAAA==.Kageansatsu:BAAANQAECgUICgAAAA==.Kairah:BAAANQAECgEIAQAAAA==.Kaivig:BAAANQADCgYIBgAAAA==.Kalï:BAAANQADCgYICQAAAA==.Karlil:BAAANQAECgQIDAAAAA==.Kasiene:BAAANQADCgcIFwAAAA==.Kasnay:BAAANQADCgQIBgAAAA==.Kateria:BAAANQADCgQIBAAAAA==.Kathenset:BAAANQAECgUIDQAAAA==.Kazenseth:BAAANQADCgEIAQAAAA==.Kazeral:BAACNQAFFH8JAAIdAAQKiRX8CgBJAQAdAAQKiRX8CgBJAQA1AAQKfxkABCAACQqSFEcMAJIBACAABwo+EkcMAJIBAB0AAgosHQ6AAKkAABkAAwq/AVdJAGcAAAAA.Kazzi:BAAANQADCgIIAgAAAA==.',
Ke='Keener:BAAANQAECgcIEwAAAA==.Kelvin:BAAANQABCgQIBAAAAA==.Kelyana:BAAANQABCgMIAwAAAA==.Kerrla:BAAANQAECgEIAQABNQAFFAQICQAdAIkVAA==.Keylleth:BAAANQADCgYJDwAAAA==.',
Kh='Khalanie:BAABNQAECn8gAAIZAAgKFAkYIgC2AQAZAAgKFAkYIgC2AQAAAA==.Khamnox:BAAANQAECgYIDwAAAA==.Khionia:BAAANQAECgIIAgAAAA==.',
Ki='Kidthefrist:BAAANQADCgUIBQAAAA==.Kielnmsoftly:BAAANQADCgYIBgAAAA==.Kilaia:BAAANQAECgEIAgAAAA==.Kirru:BAAANQAECgQIBwAAAA==.',
Kn='Knoble:BAAANQADCgQIBAAAAA==.',
Ko='Kokatoes:BAAANQAECgIIAgABNQAECggIJAANAOYRAA==.Korabas:BAAANQAECgQIBAABNQAECgkJNQAYAI4kAA==.',
Kr='Kreaton:BAAANQAECgcICwAAAA==.Kryt:BAABNQAECn8mAAIQAAgKxB7PMACbAgAQAAgKxB7PMACbAgAAAA==.',
Ku='Kuponia:BAAANQABCgIIAgAAAA==.',
Kw='Kwichangpain:BAAANQADCgcIDQAAAA==.',
Kx='Kxchiki:BAABNQAECn8nAAIWAAkKsRJ9RgBKAgAWAAkKsRJ9RgBKAgAAAA==.',
['Kã']='Kãz:BAAANQADCgYICAAAAA==.',
La='Laaklem:BAAANQAECgEJAQAAAA==.Laei:BAAANQADCggIEAAAAA==.Laserfingies:BAAANQAECgIIAgAAAA==.Lastsun:BAAANQADCgIIAgAAAA==.Lavacakes:BAABNQAECn82AAMQAAkKSSBAHAD7AgAQAAkKSSBAHAD7AgAPAAIKsgRYGAFXAAAAAA==.Lawndartz:BAAANQADCggJDgAAAA==.',
Le='Lelantoz:BAABNQAECn8bAAIFAAYK+AVy3ABDAQAFAAYK+AVy3ABDAQAAAA==.Leliel:BAAANQABCgUICgAAAA==.Leqoofus:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.',
Li='Lidan:BAABNQAECn8fAAIdAAgKQg6oNwDyAQAdAAgKQg6oNwDyAQAAAA==.Liebli:BAAANQAECgYIDQAAAA==.Liltank:BAAANQAECgIIAgAAAA==.Limity:BAAANQAECgQICAAAAA==.Linaeni:BAAANQADCgIIAgAAAA==.Linaradice:BAAANQAECgUIDAAAAA==.Lixandra:BAAANQADCgEIAQAAAA==.',
Lo='Logyn:BAAANQADCgQICgAAAA==.Lonelyspark:BAAANQADCgQICQAAAA==.Lonnias:BAAANQAECgYIDwAAAA==.Lotsalock:BAAANQADCgUIBQAAAA==.',
Lu='Lucicelse:BAAANQADCgUICQAAAA==.Lucifur:BAAANQADCgMIAwAAAA==.Luna:BAABNQAECn8gAAIGAAgKvw2RLgCiAQAGAAgKvw2RLgCiAQAAAA==.Lunarluvgood:BAEBNQAECn8jAAIHAAkKFSPFCACIAwAHAAkKFSPFCACIAwAAAA==.',
Ly='Lyrelia:BAAANQAECgIIAwAAAA==.',
Ma='Madbones:BAAANQADCgYIDAABNQAECggIGwAWAEQUAA==.Madmetal:BAABNQAECn8bAAMWAAgKRBRkWQAKAgAWAAgKRBRkWQAKAgATAAEK3QOPuwEnAAAAAA==.Mado:BAAANQAECgUICgAAAA==.Madstorm:BAAANQADCggICAAAAA==.Magefood:BAAANQAECgQIBAABNQAECgcICgADAAAAAA==.Magicky:BAAANQAECgQIBgAAAA==.Mahlkier:BAAANQADCgUIDwAAAA==.Mahlkierson:BAAANQADCgQIAwAAAA==.Maikego:BAAANQAECgQIBwAAAA==.Mairadin:BAAANQAECgIIAgAAAA==.Malchelo:BAAANQAECgQIBgAAAA==.Malfhunter:BAABNQAECn8oAAIhAAkKgBpuGgB/AgAhAAkKgBpuGgB/AgAAAA==.Malfshammy:BAAANQADCgcIBwAAAA==.Maligosa:BAAANQADCgQIBgAAAA==.Manager:BAAANQADCggIBwAAAA==.Mangolassi:BAAANQAECgIIBAAAAA==.Manto:BAAANQADCgEIAQAAAA==.Mantodea:BAAANQADCgcIFgAAAA==.Manup:BAAANQADCgYICgAAAA==.Marmin:BAABNQAECn8jAAIEAAgKrBdYCgAhAgAEAAgKrBdYCgAhAgAAAA==.Marymae:BAAANQADCgUIDgAAAA==.Mattwm:BAAANQADCgEIAQAAAA==.Maîa:BAAANQABCggIBgAAAA==.',
Me='Meatstick:BAAANQADCgIIAgABNQADCgQIBQADAAAAAA==.Meikai:BAAANQAECgUICAAAAA==.Melillia:BAAANQAECgUICAAAAA==.Melted:BAACNQAFFH8QAAILAAYK8RcRDgACAgALAAYK8RcRDgACAgA1AAQKfyMAAwsACQqtI54bAGgDAAsACQorIJ4bAGgDAAQAAQo2IFM3AF0AAAAA.Merdocki:BAABNQAECn8vAAMcAAkKUCDZMgC6AgAcAAgKvR7ZMgC6AgAiAAQKqRwIIQBnAQAAAA==.Merdra:BAABNQAECn8iAAIXAAkKmCFBBQBcAwAXAAkKmCFBBQBcAwAAAA==.Merdre:BAABNQAECn82AAQKAAkKeh3oHwDuAgAKAAkKeRzoHwDuAgAVAAQKLxl1EgD9AAAUAAUKNQWVTgDVAAAAAA==.',
Mi='Michealhunt:BAAANQADCgIIAgAAAA==.Midory:BAAANQAECgQICQAAAA==.Midranaira:BAAANQADCgEIAQAAAA==.Milda:BAAANQAECgMIBAAAAA==.Milkymocha:BAAANQAECgQIBwAAAA==.Misscorona:BAAANQAECgIIAgAAAA==.Mistyque:BAAANQAECgQICAAAAA==.Mithrandir:BAAANQADCgUIBAAAAA==.Mithrond:BAAANQADCgEIAQAAAA==.',
Mo='Modercai:BAAANQADCgIIAgAAAA==.Monalea:BAAANQAECgIIAgABNQAECggIIgAJAIgTAA==.Monkshadow:BAAANQAECgQIBAAAAA==.Monkydleafy:BAAANQADCgQIAwABNQAECgEIAgADAAAAAA==.Morcant:BAAANQAECgUIDAAAAA==.Morianoley:BAAANQAECgMIBAAAAA==.Morlu:BAAANQAECgYICgAAAA==.Mortenson:BAAANQAECgYIDwAAAA==.Mortïmer:BAABNQAECn8fAAMUAAkKSBVaHwA+AgAUAAkKSBVaHwA+AgAKAAMKXw3K1gCbAAAAAA==.Mousee:BAAANQAECgIIAgAAAA==.',
Ms='Msdonnapally:BAAANQADCggIIQAAAA==.',
Mu='Muffindr:BAAANQAECgMIAwAAAA==.',
My='Mysticmage:BAAANQAECgUICAAAAA==.Myxian:BAEANQAECgQIBQABNQAECgkJKAANAGwkAA==.',
['Mö']='Möñk:BAAANQADCgQIBQAAAA==.',
Na='Nala:BAAANQAECgEIAQAAAA==.Narallia:BAAANQADCgYICAAAAA==.Nargalad:BAAANQABCgQICAAAAA==.Narios:BAAANQAECgYIDwAAAA==.Natureshogun:BAAANQAECgUIBQAAAA==.',
Ne='Nediem:BAAANQADCgQIBQAAAA==.Neral:BAAANQADCgMIAwAAAA==.Nexxicus:BAAANQADCgQIBwAAAA==.',
Ni='Nightmehr:BAABNQAECn8qAAILAAkKYSAXPgAKAwALAAkKYSAXPgAKAwAAAA==.Nightshade:BAAANQADCgcIDQAAAA==.Nippy:BAAANQADCgUICQAAAA==.',
No='Nored:BAAANQADCgEIAQAAAA==.Nosaj:BAAANQAECgYIDQAAAA==.Nostrodomus:BAAANQADCgQIBwAAAA==.Novalee:BAAANQADCgEIAQAAAA==.',
Nu='Nuan:BAAANQADCgMIAwAAAA==.',
Ny='Nyki:BAAANQADCgMIAwAAAA==.',
Od='Odlaw:BAAANQAECgQICgAAAA==.',
Ol='Olaria:BAAANQAECgEIAQABNQAECgUIDwADAAAAAA==.Olinax:BAABNQAECn8eAAQdAAkKKReDKgA8AgAdAAgKIRaDKgA8AgAgAAUKXxWZDwAtAQAZAAEKAAA4VAAtAAAAAA==.',
Om='Omalmalha:BAAANQAECgMIBAAAAA==.',
On='Onedruidtion:BAAANQAECgIIAwAAAA==.',
Or='Orheo:BAAANQADCgcICwAAAA==.Orionmoon:BAABNQAECn8cAAMKAAgKDg9hcQDEAQAKAAgKDg9hcQDEAQAUAAYKsgcSSAD5AAAAAA==.Orlos:BAAANQAECgUIDwAAAA==.Oräkk:BAABNQAECn8nAAMYAAgKFiSvBQASAwAYAAgKFiSvBQASAwANAAIKxhK5JAGGAAAAAA==.',
Pa='Padrin:BAAANQAECgQICwAAAA==.Pandapaws:BAACNQAFFH8HAAIQAAMKvhQGFwDmAAAQAAMKvhQGFwDmAAA1AAQKfy4AAxAACQrIJBIFAJ4DABAACQrIJBIFAJ4DAA8AAwpVB535AJgAAAAA.Papaflask:BAABNQAECn8VAAIKAAgKQBZITwAzAgAKAAgKQBZITwAzAgAAAA==.Parthal:BAAANQADCgEIAQAAAA==.Partyhardly:BAABNQAECn8oAAIXAAkKGhOHHgDxAQAXAAkKGhOHHgDxAQAAAA==.Pavetta:BAAANQAECgUIBQAAAA==.Pavle:BAAANQAECgQIBAAAAA==.',
Pd='Pdiddi:BAABNQAECn8VAAMBAAkKtRcRTADhAQABAAUKHiERTADhAQASAAgKgBMQQADCAQAAAA==.',
Pe='Pellaeon:BAABNQAECn8xAAMCAAkKhRgoMABPAgACAAkKQhYoMABPAgABAAgKTxXMSwDiAQAAAA==.Pelt:BAABNQAECn8nAAIMAAkK0RcHGwB8AgAMAAkK0RcHGwB8AgAAAA==.Perseus:BAAANQAECgEIAQABNQAECgQIDQADAAAAAA==.Petmasta:BAAANQABCgEIAQABNQABCgQIBAADAAAAAA==.',
Ph='Pharaun:BAAANQAECgEIAQABNQAECggIMQABAJIIAA==.Phlan:BAEANQAECgQIBAAAAA==.Phrostir:BAAANQAECggIEAAAAA==.',
Pi='Picklechips:BAAANQADCgEIAQAAAA==.Pillgrimm:BAAANQAECgQICQAAAA==.Pillsburyman:BAAANQAECgQIBwAAAA==.',
Po='Pointee:BAAANQADCgYICgAAAA==.Poisson:BAABNQAECn8fAAIZAAkKwQuHGgABAgAZAAkKwQuHGgABAgAAAA==.Pokoxo:BAABNQAECn8sAAQXAAgK0RxNFABfAgAXAAgK0RxNFABfAgAWAAUK5wiXwQD0AAATAAQKRwknNQHEAAABNQAECgIIAwADAAAAAA==.Pookiez:BAEANQAECgIIBQABNQAECgkJHgAPAJ8lAA==.',
Pr='Prancine:BAAANQAECgQIBAABNQAFFAgIIAAKAK8WAA==.Prescess:BAAANQADCgUICAAAAA==.Providence:BAABNQAECn8tAAIJAAkKHx9iFgDmAgAJAAkKHx9iFgDmAgAAAA==.Prsr:BAAANQAECgMIBgABNQAFFAYIEQABAF4fAA==.',
Pu='Pudgypaws:BAAANQAECgQIBwAAAA==.Punishment:BAAANQABCgIIAgABNQAECgQIBgADAAAAAA==.',
Qu='Quickmend:BAAANQAECgQIBAAAAA==.Quickpal:BAAANQAECgcIEQAAAA==.Quickpaw:BAABNQAECn8fAAIeAAkKYxvyDgCOAgAeAAkKYxvyDgCOAgAAAA==.',
Ra='Raccoons:BAAANQADCgMIAwAAAA==.Radell:BAAANQAECgQIBwAAAA==.Rageproof:BAAANQAECgEIAgAAAA==.Ragged:BAABNQAECn8VAAMSAAkKoyBAFwDNAgASAAkKoyBAFwDNAgABAAEKAAAB4AAxAAAAAA==.Raidbloom:BAEBNQAFFH8SAAIGAAUKkRPeBgCQAQAGAAUKkRPeBgCQAQABNQAECgkJKgAWAN4YAA==.Raidshock:BAEBNQAECn8qAAIWAAkK3hhpMgCZAgAWAAkK3hhpMgCZAgAAAA==.Rainsinger:BAAANQADCgcIGQAAAA==.Ramook:BAEANQAECgIIAgAAAA==.Randomchar:BAABNQAECn81AAITAAkKdBOZdABAAgATAAkKdBOZdABAAgAAAA==.Rankor:BAAANQADCgYIBgABNQAECgkJMgAbAM4QAA==.Rastann:BAABNQAECn81AAITAAkK/h8KRQDCAgATAAkK/h8KRQDCAgAAAA==.Ratsdrack:BAAANQADCgMIAwAAAA==.Rawrlas:BAAANQADCgMIAwABNQAECgUIDwADAAAAAA==.Razdor:BAAANQADCgUIBgAAAA==.',
Re='Reapertoo:BAACNQAFFH8OAAMBAAYK/iSlAgAZAgABAAUKAiSlAgAZAgASAAUK6SESBwCDAQA1AAQKfyoAAwEACQoEJRcOAEYDAAEACApRJRcOAEYDABIACQqzHjIZAL4CAAAA.Recreant:BAAANQADCgcIDQAAAA==.Redbaron:BAABNQAECn8XAAIJAAgKRRfUMwAJAgAJAAgKRRfUMwAJAgAAAA==.Redmtndew:BAAANQAECgIIAgAAAA==.Reetep:BAAANQADCggIGQABNQAECgIIBQADAAAAAA==.Regeth:BAAANQADCggIFQAAAA==.Remily:BAAANQAECgUIBQABNQAECgkJJgALAEcdAA==.Repuns:BAEANQAECggIAgABNQAECgkJIwAHABUjAA==.Revin:BAAANQAECgEJAQAAAA==.Rezalia:BAAANQADCgMIAwAAAA==.',
Ro='Rodned:BAAANQADCggJCAAAAA==.Rolas:BAAANQADCgMIAQABNQAECgUIDwADAAAAAA==.Rondle:BAAANQAECgQIBQAAAA==.Rottencorpse:BAAANQADCgQIBAAAAA==.Rozalin:BAABNQAECn81AAMLAAkKcSMNEQCOAwALAAkKcSMNEQCOAwAEAAEKMSLjNABlAAAAAA==.Rozalinamoon:BAAANQADCgMIAwAAAA==.',
Ru='Rubeus:BAEANQAECgcIBwABNQAECgkJIwAHABUjAA==.Rurouni:BAAANQAECgIIAgAAAA==.Rustystorm:BAAANQADCgMIAwAAAA==.Rustywarlock:BAAANQAECgQIBQAAAA==.',
Ry='Ryoshi:BAABNQAECn8mAAMFAAkKWB/sOAC9AgAFAAkKWB/sOAC9AgAjAAcKZxdiCADNAQAAAA==.',
['Rò']='Ròòszy:BAAANQADCgYIBwAAAA==.',
Sa='Sacredstars:BAAANQAECgUIBQAAAA==.Sacredswords:BAABNQAECn8nAAMNAAkKxBk+VgCFAgANAAkKxBk+VgCFAgAOAAIKbRBTIgCgAAAAAA==.Sakito:BAAANQAECggICwABNQAFFAYIEwAQAOUUAA==.Salarai:BAAANQADCgcIBgABNQAECgUIDwADAAAAAA==.Sanguinius:BAABNQAECn8fAAMWAAkK7yJeBwCOAwAWAAkK7yJeBwCOAwATAAIKMQQAggFPAAAAAA==.Sapphiremist:BAAANQAECgUIEQAAAA==.Sayen:BAAANQAFFAEIAQAAAA==.',
Sc='Scachity:BAABNQAECn8kAAMcAAgKfhWVWwBBAgAcAAgKfhWVWwBBAgAiAAMKexC5RACxAAAAAA==.Scan:BAABNQAECn8dAAIPAAkKgBkgNQCgAgAPAAkKgBkgNQCgAgAAAA==.Schein:BAAANQAECgYIEwAAAA==.',
Se='Segsacute:BAABNQAECn8XAAINAAkK/xIxcQA9AgANAAkK/xIxcQA9AgAAAA==.Sendatu:BAAANQAECgEIAgABNQAECggIJAACAKURAA==.Sepulchre:BAABNQAECn8xAAMBAAgKkgiSbwBTAQABAAgKkgiSbwBTAQASAAYKagQcdADIAAAAAA==.Seraphiim:BAAANQADCggICAAAAA==.',
Sh='Shadesfault:BAAANQADCgUIEQAAAA==.Shadowhart:BAAANQADCgEIAQAAAA==.Shaeebulay:BAAANQABCgQIBAAAAA==.Shamaroo:BAAANQABCgUIBwAAAA==.Shaundakul:BAAANQAECgUIEQAAAA==.Shephion:BAAANQAECgQIDwABNQAECgkJPAAeAEwlAA==.Shnozberries:BAAANQADCgEJAQAAAA==.Shockhart:BAAANQAECgcIDgAAAA==.Shonuffz:BAAANQADCgYIBgAAAA==.Shortnstack:BAAANQAECgUIDwAAAA==.Shãdow:BAAANQADCgUIBQAAAA==.',
Si='Side:BAAANQAECgEIAQAAAA==.Siegfried:BAAANQAECgQIBAAAAA==.Simori:BAAANQADCgIIAgAAAA==.Sindrel:BAAANQAECgUIBQABNQAFFAMICAAfADoaAA==.Siyurie:BAAANQADCgcIEAAAAA==.',
Sk='Skawalker:BAABNQAECn80AAMGAAkK1yHACQAnAwAGAAkK1yHACQAnAwAkAAEKVxd+OwBFAAAAAA==.',
Sl='Slaed:BAAANQADCgYIBwAAAA==.Slaynne:BAAANQAECgcIEwAAAA==.',
Sm='Smoky:BAAANQAECgUIBwAAAA==.Smäug:BAACNQAFFH8QAAMaAAYK2xyFAwC2AQAaAAUKkR2FAwC2AQAbAAEKuBq0CgBbAAA1AAQKfy4ABBoACQq2JVUBALsDABoACQq2JVUBALsDACUABgoYELwpAF8BABsAAQqTIq8eAGcAAAAA.',
Sn='Snailas:BAAANQADCggIDwAAAA==.Sniperwolf:BAAANQADCgYIBgABNQAECgIIBAADAAAAAA==.Snowleopard:BAAANQADCgIIAgAAAA==.',
So='Sodomn:BAAANQADCgQIBAAAAA==.Solria:BAABNQAECn8fAAIKAAcKCBiMVwAYAgAKAAcKCBiMVwAYAgAAAA==.Sonnytyphoon:BAAANQADCgYIBgAAAA==.',
Sp='Spex:BAAANQADCgUIBQAAAA==.',
St='Starnex:BAAANQAECggICgAAAA==.Statyrea:BAAANQADCgUIBQAAAA==.Strikes:BAAANQAECggICAAAAA==.Styx:BAACNQAFFH8IAAIYAAMKASXxAgBHAQAYAAMKASXxAgBHAQA1AAQKf0UAAhgACQrpJgkAABgEABgACQrpJgkAABgEAAAA.',
Su='Sugabuns:BAAANQAECggICgAAAA==.Sukfööt:BAABNQAECn8iAAIYAAkK4A/WFADWAQAYAAkK4A/WFADWAQAAAA==.Sumbatadh:BAAANQAECgYIBwAAAA==.Summerflip:BAAANQADCggICAABNQAECgkJNgAKAHodAA==.Sunnytyphoon:BAABNQAECn8YAAIkAAgKkhSHEAD+AQAkAAgKkhSHEAD+AQAAAA==.',
Sw='Swiftholy:BAAANQAECgYIEgAAAA==.Swiftmends:BAAANQAECgIIAgAAAA==.',
Sy='Sydahlis:BAAANQAECgcIEwAAAA==.Sylvestris:BAABNQAECn8YAAIGAAgKLST/BwBDAwAGAAgKLST/BwBDAwAAAA==.',
Ta='Taiyana:BAAANQAECgQIBAAAAA==.Tangie:BAAANQADCggICgAAAA==.Tankjob:BAAANQAECgQIDAAAAA==.Tanklorswift:BAAANQADCggIGwAAAA==.Tastemycrits:BAAANQADCggICAABNQAECgkJGQATAEQbAA==.',
Td='Tdog:BAAANQADCggICwAAAA==.',
Te='Tealetresh:BAAANQABCgIIAgAAAA==.Teapot:BAAANQAECgcICgAAAA==.Tedoseirum:BAABNQAECn8tAAIJAAkKbyJyCgBbAwAJAAkKbyJyCgBbAwAAAA==.Terminal:BAAANQADCggICwAAAA==.Terpyu:BAAANQADCgEIAQAAAA==.Texasbilly:BAAANQADCgYIDAAAAA==.Texasredneck:BAAANQADCgYIDAAAAA==.Texasslasher:BAAANQADCgYIBgAAAA==.',
Th='Thaelyra:BAAANQADCggICAAAAA==.Thedtwo:BAAANQAECgIIAgAAAA==.Thorgarrus:BAABNQAECn82AAITAAkKFR6UPQDaAgATAAkKFR6UPQDaAgAAAA==.',
Ti='Tigerwoodz:BAAANQAECgEIAQAAAA==.Tilbourne:BAAANQAECgMIBAAAAA==.Timvoker:BAAANQADCgYIBgAAAA==.',
To='Toddie:BAABNQAECn8oAAMFAAgK1R2AOwC1AgAFAAgK1R2AOwC1AgAhAAEKAABajAAxAAAAAA==.Tolkarnyx:BAAANQADCgUIBQABNQAFFAYIDgAQAIEWAA==.Tommyj:BAAANQADCggICwAAAA==.Torcher:BAAANQAECgIIAgAAAA==.Tormod:BAABNQAECn8hAAIFAAgKzBaWZQBHAgAFAAgKzBaWZQBHAgAAAA==.Torvaldt:BAAANQAECgYICgABNQAECggIKAAFANUdAA==.Tourmod:BAAANQAECgQICgAAAA==.Towmater:BAAANQAECgIIAwAAAA==.',
Tr='Trakkarz:BAAANQAECgQIBQAAAA==.Traps:BAAANQAECgIIBQAAAA==.Trashypanda:BAACNQAFFH8PAAILAAQK9hqcIgBrAQALAAQK9hqcIgBrAQA1AAQKfycAAgsACQqwI6c9AAsDAAsACQqwI6c9AAsDAAAA.Trays:BAAANQADCgYIBgAAAA==.Trender:BAAANQADCgQIBAAAAA==.Treniity:BAAANQAECgUICgAAAA==.Tressilly:BAABNQAECn8mAAILAAkKRx2FMQAoAwALAAkKRx2FMQAoAwAAAA==.Trinagirl:BAAANQADCgYIBgAAAA==.Trinneries:BAAANQADCgcJBwAAAA==.Triná:BAAANQADCgYIBgABNQADCgYIBgADAAAAAA==.Tristanyia:BAAANQADCggICAAAAA==.Tristiyan:BAAANQAECgEIAQAAAA==.Trogdorr:BAABNQAECn8yAAMbAAkKzhAcCwCvAQAaAAkKHw87EwAYAgAbAAgKEw8cCwCvAQAAAA==.Trutert:BAAANQAECgMIBgAAAA==.Tryana:BAAANQADCggINQAAAA==.Trystiana:BAAANQADCgMJBAAAAA==.',
Tt='Ttania:BAAANQADCgYIDgAAAA==.',
Tu='Tubor:BAAANQAECgMICAAAAA==.',
Tw='Tweetwee:BAAANQAECgUIBwAAAA==.',
Ty='Tyledis:BAAANQADCggIEAABNQAECgkJNQAYAI4kAA==.Tyr:BAABNQAECn8vAAMPAAkKHx4dHwAOAwAPAAkKHx4dHwAOAwAQAAIK1gkEBAFaAAAAAA==.Tyrnova:BAAANQADCggICAAAAA==.',
['Tö']='Töshïrö:BAAANQADCgIIAgAAAA==.',
Uh='Uhope:BAAANQAECgUICgAAAA==.',
Um='Umbravolt:BAABNQAECn82AAIIAAkKWCNRAwCCAwAIAAkKWCNRAwCCAwAAAA==.',
Un='Unclezapp:BAAANQADCggJDgAAAA==.Unravel:BAAANQADCgUIDgAAAA==.Unrealcalorx:BAAANQADCgUIBQAAAA==.Unrealronin:BAAANQAECgUICQAAAA==.',
Va='Vaeris:BAAANQADCgUJCwAAAA==.Vakero:BAAANQAECgYIEgAAAA==.Valeriana:BAAANQADCgQIBAAAAA==.Valess:BAAANQAECgQIDwAAAA==.Valros:BAAANQADCgYICgAAAA==.Vapor:BAAANQABCgIIAgAAAA==.Vaythan:BAABNQAECn8cAAIkAAkKHx9HBABJAwAkAAkKHx9HBABJAwAAAA==.',
Ve='Venchris:BAAANQAECgcIEQAAAA==.Verica:BAAANQADCgEIAQAAAA==.',
Vh='Vhiz:BAAANQAECgYIEQAAAA==.',
Vi='Vibrance:BAAANQADCggJEAAAAA==.Victorius:BAAANQAECgMIAwAAAA==.Viridesa:BAAANQADCgcIFAAAAA==.Vixine:BAAANQAECgUICgAAAA==.',
Vn='Vnillabeef:BAAANQAECgQIBQABNQAFFAYIEQABAF4fAA==.',
Vo='Vohlen:BAAANQABCgYIBgAAAA==.Voidcore:BAAANQAFFAEIAgABNQAECgkJFwANAEQUAA==.Voidwalker:BAAANQADCgYICQABNQAFFAUIDAARAFcbAA==.',
Vy='Vysera:BAAANQAECgEIAQAAAA==.',
Wa='Warfarmer:BAAANQAECgQIBgAAAA==.Warhawke:BAAANQADCggIEAAAAA==.',
We='Werenal:BAAANQADCgcICwAAAA==.',
Wh='Whis:BAAANQAECgUIDQAAAA==.Whispernight:BAAANQADCgQIBwAAAA==.',
Wi='Widja:BAAANQADCgUIEgAAAA==.Wiimage:BAAANQAECgQIBQAAAA==.Wiivinelight:BAAANQADCgMIAwABNQAECgQIBQADAAAAAA==.Wildhus:BAABNQAECn8iAAIJAAgKiBOrNQD8AQAJAAgKiBOrNQD8AQAAAA==.',
Wo='Wolfkin:BAAANQADCggIBwAAAA==.',
Wy='Wyckdd:BAAANQAECgUIBQAAAA==.',
['Wå']='Wåffle:BAAANQAECgYIDgABNQAECgkJKgAdAJ8jAA==.',
['Wî']='Wîca:BAABNQAECn8XAAIUAAcK6Qt5NwBlAQAUAAcK6Qt5NwBlAQAAAA==.',
Xa='Xantris:BAAANQADCgEIAQAAAA==.',
Xe='Xenowolf:BAAANQAECgIIAwABNQAECgQIDQADAAAAAA==.',
Xv='Xvire:BAAANQAECgIIAwAAAA==.',
['Xû']='Xûrû:BAAANQAECgcICgAAAA==.',
Yc='Yce:BAAANQAECgUIDgAAAA==.',
Ye='Yeiko:BAAANQAECgUIBgAAAA==.',
Yo='Yoker:BAAANQAECgUIDwAAAA==.Yokersen:BAAANQAECgcIEgAAAA==.',
Za='Zaeladen:BAAANQAECgIIBAAAAA==.Zalorea:BAAANQAECgQICAABNQAECggILQASAAgNAA==.Zambonii:BAAANQAECgYICwABNQAECgkJMQAiAO0gAA==.Zamdeath:BAAANQADCgMIAwABNQAECgkJMQAiAO0gAA==.Zamlock:BAABNQAECn8xAAMiAAkK7SBPDwAGAgAcAAcKOiCESgBwAgAiAAYKlh1PDwAGAgAAAA==.Zanya:BAAANQAECgIIBAAAAA==.',
Ze='Zeiko:BAABNQAECn8cAAIBAAgK8SIIEwAeAwABAAgK8SIIEwAeAwAAAA==.Zestychip:BAAANQAECgMIBQAAAA==.Zeäl:BAAANQADCgUIBgAAAA==.',
Zh='Zhaoyun:BAAANQAECgQIBAAAAA==.',
Zi='Zilkir:BAEBNQAECn8tAAMTAAkKWRqaSAC4AgATAAkKWRqaSAC4AgAWAAgKYxYiTwAsAgAAAA==.Ziran:BAABNQAECn8jAAIfAAkKViT1AgCpAwAfAAkKViT1AgCpAwAAAA==.Zivadhim:BAAANQADCgIIAgAAAA==.',
Zl='Zlyth:BAAANQAECgQICAAAAA==.',
Zz='Zzodac:BAAANQADCgEIAQABNQAECggIIgAJAIgTAA==.Zzvzz:BAAANQAECgQIBAAAAA==.',
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
