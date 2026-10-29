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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Havoc','Mage-Arcane','Priest-Holy','Priest-Shadow','Monk-Windwalker','DemonHunter-Devourer','Paladin-Protection','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Frost','Paladin-Retribution','Druid-Balance','Priest-Discipline','Paladin-Holy','Rogue-Subtlety','Warrior-Protection','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Rogue-Assassination','Monk-Mistweaver','Rogue-Outlaw','Warlock-Destruction','Hunter-Marksmanship','Hunter-Survival','Druid-Guardian','Druid-Feral','Evoker-Preservation','DemonHunter-Vengeance',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abnalem:BAAANQAECgEIAQAAAA==.Abrahmis:BAAANQABCgcIEAABNQAECgoKPwABABkKAA==.',
Ac='Aceventuraa:BAAANQADCgEIAQAAAA==.',
Ad='Adramalech:BAAANQADCgQIBAABNQAFFAcIEgABAA8aAA==.',
Ae='Aeakos:BAAANQAECgIIAwABNQAECgoKKwACAOoQAA==.Aeldon:BAAANQAECgIIAgAAAA==.',
Ai='Airese:BAAANQAECgYIBwAAAA==.Airist:BAAANQAECgQICAABNQAECgYIBwADAAAAAA==.Aisele:BAABNQAECn8cAAIEAAkKnANAIgDZAAAEAAkKnANAIgDZAAAAAA==.',
Al='Alander:BAAANQAECgUICgAAAA==.Alastor:BAAANQADCgcICwAAAA==.Alathir:BAABNQAECn8ZAAIFAAcKIRk1ngDKAQAFAAcKIRk1ngDKAQAAAA==.Alluri:BAAANQAECggIDwAAAA==.Althemia:BAAANQAECgMIAwAAAA==.Alunamora:BAABNQAECn89AAIGAAoKOR0xBwDrAgAGAAoKOR0xBwDrAgAAAA==.',
Am='Ammaris:BAAANQAECgYICQAAAA==.',
An='Analani:BAAANQAECgQICgAAAA==.Anali:BAAANQAECgUIBwAAAA==.Anduriel:BAAANQABCggICAAAAA==.Angis:BAAANQADCgQICAAAAA==.Angryheals:BAAANQAECgUIBwAAAA==.Annieq:BAAANQAECgQIBAAAAA==.Ansfrid:BAAANQAECgMIAwAAAA==.',
Ap='Apøllø:BAABNQAECn8rAAIHAAoKegltJgBjAQAHAAoKegltJgBjAQAAAA==.',
Aq='Aquatofana:BAAANQAECgQICAAAAA==.',
Ar='Aranel:BAAANQADCgYIBgAAAA==.Arcamancer:BAAANQAECgQICwAAAA==.Arcee:BAAANQABCgIIAgAAAA==.Arinthal:BAAANQAECgUIEAAAAA==.Arkenfel:BAAANQADCgQIBAAAAA==.Aroia:BAABNQAECn8kAAIIAAkKyhGNWACjAQAIAAkKyhGNWACjAQAAAA==.Arril:BAAANQAECgYIEwAAAA==.Artemissy:BAAANQADCgUICwAAAA==.Artiis:BAAANQAECggICAAAAA==.Artrimus:BAAANQAECgMIBgAAAA==.',
As='Asham:BAAANQAECggICgAAAA==.Ashlieghee:BAABNQAECn80AAMJAAoKzR4gGgAMAwAJAAoKzR4gGgAMAwAKAAIKSQV3SQAyAAAAAA==.Ashron:BAAANQAECgcIDAABNQAECgoKMQAIAEIhAA==.Ashuraa:BAAANQADCgQIBAABNQAECgoKGQALABsMAA==.Astien:BAAANQAECgUICgAAAA==.Astralee:BAAANQAECgUIBwAAAA==.Aszunie:BAAANQAECgIIAgAAAA==.',
Au='Audric:BAAANQADCgYIBwAAAA==.Auot:BAAANQAECgMIAwAAAA==.',
Av='Avelen:BAABNQAECn8YAAMBAAkKYx2+LQB7AgABAAkKYx2+LQB7AgACAAEKfAr9xwA5AAAAAA==.Averlen:BAAANQAECgYIDwAAAA==.Avha:BAAANQAECgYIDwAAAA==.Avistero:BAAANQAECgMIAwAAAA==.',
Ax='Axel:BAABNQAECn81AAIHAAoKJiAUEAAhAwAHAAoKJiAUEAAhAwAAAA==.',
Ay='Aylden:BAABNQAECn8dAAMHAAgKwQ96QAC6AQAHAAgKwQ96QAC6AQAMAAIK2AFlaABDAAAAAA==.Aylshm:BAAANQADCgYIFAAAAA==.Ayrene:BAAANQADCgcIBwABNQAECgQIBQADAAAAAA==.',
Az='Azaloth:BAAANQADCgMIAwAAAA==.Azenazar:BAAANQADCgEIAQAAAA==.Azog:BAAANQAECgEIAQAAAA==.Azsharianna:BAAANQABCggIEAAAAA==.',
Ba='Bailas:BAAANQAECgUIDAAAAA==.Battousai:BAAANQADCgMIAwAAAA==.Bazileth:BAAANQADCgYIBgAAAA==.',
Be='Bearistotle:BAAANQAECgEIAQAAAA==.Bearjax:BAAANQAECgUIBQABNQAECgoKGAANAEAYAA==.Beastm:BAAANQAECgQIBAAAAA==.Beastmehr:BAAANQAECgUICgABNQAECgoKOAAIAMciAA==.Beauregardl:BAAANQAECgEIAQAAAA==.Bellina:BAAANQADCgcIBwAAAA==.Belwyn:BAAANQADCgUIBgAAAA==.Benjofamin:BAAANQAECgYIBwAAAA==.',
Bi='Bitesize:BAEBNQAECn83AAMOAAoKsyRwFQBkAwAOAAoKsyRwFQBkAwAPAAEK1yT8KQBhAAAAAA==.Bittauren:BAAANQAECgIIAgAAAA==.',
Bl='Blakelivly:BAEBNQAECn8pAAQQAAoKPSBdJgDqAgAQAAkK3B9dJgDqAgARAAkKbx1HKADDAgASAAcKKRynGAAHAQAAAA==.Blashster:BAABNQAECn8xAAMIAAoKQiHOGQBuAwAIAAoKQiHOGQBuAwAEAAEKPxnMQgA+AAAAAA==.Blender:BAAANQADCgEIAQAAAA==.Blightsize:BAEANQADCgMIAwABNQAECgoKNwAOALMkAA==.Blkplayge:BAAANQADCgMIAwAAAA==.',
Bo='Bonemilker:BAACNQAFFH8SAAMBAAcKDxrUAQA7AgABAAYK4R7UAQA7AgATAAUKkBUsCQBaAQA1AAQKfzMAAxMACgqyJXcMADIDABMACgpoJXcMADIDAAEABQpMHK9dAJkBAAAA.Bonkdaddy:BAABNQAECn8iAAIUAAoKSh/TOQDqAgAUAAoKSh/TOQDqAgAAAA==.Bopeep:BAAANQAECgcICwAAAA==.',
Br='Brackz:BAAANQAECgIIAQAAAA==.Brandt:BAAANQABCgQICAAAAA==.Breelyssa:BAAANQAECgQICQAAAA==.Brego:BAAANQAECgIIAgAAAA==.Brenna:BAAANQAECgMIAwABNQAECgkJKgAVAEAPAA==.Brewslèé:BAAANQADCgMIAgAAAA==.Brighter:BAABNQAECn83AAQKAAoKrhkOHQBaAgAKAAkKrBgOHQBaAgAJAAgKHxU0kABmAQAWAAYKshITDgBPAQAAAA==.Brightsize:BAEANQAECgYIDQABNQAECgoKNwAOALMkAA==.Broncopally:BAAANQADCgQIBAAAAA==.Brótien:BAAANQADCggICAABNQAECgYIBgADAAAAAA==.',
Bu='Bubbleboi:BAAANQADCgYICAAAAA==.Bunnka:BAAANQADCgYIBgAAAA==.Bunnyparade:BAAANQADCggIDgAAAA==.',
Ca='Cakesdruid:BAAANQAECgYIDQAAAA==.Caledwar:BAABNQAECn8fAAIUAAYKxgqVzwDDAAAUAAYKxgqVzwDDAAAAAA==.Calrissa:BAAANQADCgMIAwABNQAECgcIGQAFACEZAA==.Calthirstrap:BAACNQAFFH8PAAQBAAYKvhezCwBSAQABAAQKKx2zCwBSAQATAAEKdwcGFABPAAACAAEKAADpNQAnAAA1AAQKfzcAAgEACgqJJS4CAEcDAAEACgqJJS4CAEcDAAAA.Carare:BAAANQADCgcICgAAAA==.Carnàge:BAAANQAECgMIBgAAAA==.Casterrata:BAAANQADCggICAAAAA==.',
Ce='Ceefack:BAAANQAECgQIDgAAAA==.Cethin:BAAANQAECgUICQAAAA==.',
Ch='Chaargee:BAABNQAECn8iAAMOAAkKoAsIXwBlAQAOAAkKoAsIXwBlAQAPAAIKywd+JgAeAAAAAA==.Chaosshot:BAAANQAFFAIIAwAAAA==.Cheedar:BAACNQAFFH8HAAMXAAMKzQtDGgDNAAAXAAMKzQtDGgDNAAANAAEKTABgFQAYAAA1AAQKfxwAAhcACQq8EB9TACECABcACQq8EB9TACECAAAA.Chelaria:BAAANQAECgQICQAAAA==.Cherylindrea:BAAANQADCgUIDgAAAA==.Chillwombat:BAAANQADCggIIgAAAA==.Chumlei:BAAANQADCgcIBwAAAA==.',
Ck='Ckz:BAAANQAECggICgAAAA==.',
Cl='Claydemon:BAABNQAECn8UAAIHAAYKmgdWQgDAAAAHAAYKmgdWQgDAAAAAAA==.Clayvicar:BAABNQAECn88AAMJAAoKWQwcawDdAQAJAAoKWQwcawDdAQAKAAIKVgNGaQBcAAAAAA==.',
Co='Convoid:BAAANQABCggIHQABNQAECgMIAwADAAAAAA==.Coridane:BAABNQAECn8kAAIJAAkKig28RwCSAQAJAAkKig28RwCSAQAAAA==.Corrum:BAAANQAECgYIDAAAAA==.Corwinfiron:BAABNQAECn8fAAIIAAkKCQlY9gCfAQAIAAkKCQlY9gCfAQAAAA==.',
Cr='Crosse:BAAANQAECgYIDQAAAA==.Cruellà:BAAANQADCgYIEwAAAA==.Cryptcrawler:BAAANQAECgEIAgAAAA==.',
Cu='Cuddleme:BAAANQADCgcIDQAAAA==.',
Cy='Cythera:BAACNQAFFH8MAAISAAUKVxuxAgCZAQASAAUKVxuxAgCZAQA1AAQKfysAAhIACQo0JmkDAGgDABIACQo0JmkDAGgDAAAA.',
['Cá']='Cámus:BAABNQAECn8mAAIUAAcKtBIwmQAhAQAUAAcKtBIwmQAhAQAAAA==.',
Da='Daammy:BAAANQAECgUICAAAAA==.Daayumgurl:BAAANQADCgYIBgAAAA==.Dagren:BAAANQADCggIHgAAAA==.Daisy:BAAANQABCggINgABNQAECgMIAwADAAAAAA==.Dakdor:BAAANQADCgMIAwAAAA==.Daphine:BAAANQADCgUIDwAAAA==.Darimonk:BAAANQADCgEIAQABNQADCgYICgADAAAAAA==.Darivara:BAAANQADCgYICgAAAA==.Darkbeautie:BAABNQAECn8aAAIYAAcKzAatYQDXAAAYAAcKzAatYQDXAAAAAA==.Darkcarbon:BAABNQAECn8fAAIMAAYK4hSBHQBAAQAMAAYK4hSBHQBAAQAAAA==.Darkchylde:BAAANQADCgUIBQABNQAECgYIHwAMAOIUAA==.Darkplazzma:BAAANQAECgYIBwAAAA==.',
De='Deathmask:BAAANQAECgMIAwAAAA==.Deathonyou:BAAANQAECggIBQABNQAECgkJJgAUAAwSAA==.Deathspal:BAABNQAECn8mAAMUAAkKDBIHqgDMAQAUAAkKDBIHqgDMAQANAAMKsAjZQgBMAAAAAA==.Defeated:BAAANQABCgYIBgAAAA==.Dementedfun:BAAANQAECggICAAAAA==.Dessembrae:BAABNQAECn9FAAMZAAoK/iORAQC0AwAZAAoK/iORAQC0AwAOAAUKqwaFpQDBAAAAAA==.Devont:BAAANQADCgUIBQAAAA==.Dewkiez:BAEBNQAECn8oAAIQAAoKBiYVBgC5AwAQAAoKBiYVBgC5AwAAAA==.',
Di='Diabolicarl:BAABNQAECn8yAAIHAAoKIw98GQDUAQAHAAoKIw98GQDUAQAAAA==.Dimencius:BAAANQAECgQIAQAAAA==.Diri:BAAANQAECggIDwABNQAECgkJHwAYAMELAA==.',
Dm='Dmmeforpi:BAAANQADCgYICgABNQAFFAIIAwADAAAAAA==.',
Do='Docphanan:BAAANQAECgEIAgAAAA==.Doesntheal:BAAANQABCgIIAgAAAA==.Dookiez:BAEBNQAECn8aAAISAAkKcCEUBQCYAgASAAkKcCEUBQCYAgABNQAECgoKKAAQAAYmAA==.Dotgnome:BAAANQADCgcIBAAAAA==.Doubledragin:BAABNQAECn8lAAMaAAcK2hTuFwDKAQAaAAcK2hTuFwDKAQAbAAQKpRQuFgDPAAAAAA==.',
Dr='Dracantar:BAAANQADCggIFgAAAA==.Dractini:BAAANQADCgcICgABNQAFFAkJKQAJAC8ZAA==.Dragfan:BAAANQADCgQJBAAAAA==.Dragonbelly:BAAANQAECgMIAwAAAA==.Dragondeez:BAAANQABCgQIBAABNQAECgYIGAAIAOIMAA==.Dragore:BAABNQAECn8eAAIOAAgKhwznpQC+AQAOAAgKhwznpQC+AQAAAA==.Drakage:BAAANQADCggICAAAAA==.Druidgirls:BAABNQAECn9HAAIGAAoKUx3wBQARAwAGAAoKUx3wBQARAwAAAA==.',
Du='Dublynn:BAAANQAECgIIAgABNQAFFAcIEQAcAJcUAA==.Duelist:BAAANQAECggIEwAAAA==.Dupree:BAAANQADCgQIBQAAAA==.Durogdem:BAAANQADCgYIBgAAAA==.Duskfire:BAAANQABCgQICAAAAA==.',
Dw='Dwarnter:BAAANQADCgYIBQAAAA==.',
Ea='Earthaggie:BAAANQADCgUIDgAAAA==.',
Ec='Echlipse:BAAANQAECgcIEQABNQAECgkJMgANAG0jAA==.',
Ed='Ederon:BAAANQABCggICAAAAA==.Edirae:BAAANQAECgIIAgAAAA==.',
El='Elenora:BAABNQAECn8qAAIVAAkKXwe8NQD1AAAVAAkKXwe8NQD1AAAAAA==.Ellea:BAAANQAECgYIDwAAAA==.Ellesmere:BAAANQAECgYICAABNQAFFAkJLAAXAMYfAA==.Elye:BAAANQAECgcIDwAAAA==.',
Em='Emer:BAAANQAECgcICgAAAA==.Emiru:BAAANQADCgUJBgAAAA==.',
En='Encore:BAABNQAECn9FAAIGAAoKSg2AGACtAQAGAAoKSg2AGACtAQAAAA==.',
Eo='Eousphorus:BAACNQAFFH8IAAIIAAQKPAzJGwDRAAAIAAQKPAzJGwDRAAA1AAQKf0AAAwgACgomHLw1AB4DAAgACgomHLw1AB4DAAQAAgr9CLw6AFQAAAAA.',
Er='Erathen:BAAANQADCggICgAAAA==.Eryanna:BAAANQAECgIIBgAAAA==.',
Es='Esplan:BAEBNQAECn8fAAIIAAoKyiI0BgAxAwAIAAoKyiI0BgAxAwABNQAECgoKKQAQAD0gAA==.',
Eu='Euden:BAAANQADCgQIBAAAAA==.',
Ev='Evelleion:BAAANQAECgYIDwAAAA==.',
Ex='Excedrin:BAAANQADCgIIAgAAAA==.Exoticlord:BAAANQAECgQIBAAAAA==.',
Fe='Felhayde:BAAANQADCgYIBgAAAA==.Felicity:BAAANQAECgUIBQAAAA==.Fenryyr:BAAANQADCgYJBwAAAA==.',
Fi='Fierygrace:BAAANQADCgcIEAAAAA==.Firburger:BAAANQAECgYICgAAAA==.Fischl:BAAANQAECgQIBgAAAA==.Fitzmagic:BAAANQAECggICAAAAA==.',
Fl='Flameth:BAABNQAECn8/AAIcAAoKpw7fXABBAgAcAAoKpw7fXABBAgAAAA==.Fling:BAAANQADCgMIAwAAAA==.Flirtywombat:BAAANQAECgMIBgAAAA==.',
Fo='Foe:BAAANQAECgUIBQABNQAECgkJHgAdAK8UAA==.',
Fr='Freezrorburn:BAAANQADCgYIBwAAAA==.',
Fu='Fujiko:BAAANQADCgIIAgAAAA==.Fujitto:BAAANQADCgIIAgAAAA==.Fumanchu:BAABNQAECn8rAAIZAAoKYRuKCADJAgAZAAoKYRuKCADJAgAAAA==.Fuzugchu:BAAANQAECgcICwABNQAECgoKKwAZAGEbAA==.',
Ga='Gaamora:BAAANQADCgUIEwAAAA==.Gabooda:BAAANQADCgUIBQABNQAECgMIBgADAAAAAA==.Gainsborough:BAABNQAECn80AAMUAAoKOiECKAAmAwAUAAoKOiECKAAmAwANAAMKaRR3TwCpAAABNQAFFAcIFAARAJQWAA==.Gamegg:BAAANQAECgUIDwAAAA==.Garagos:BAABNQAECn89AAIdAAoKfR7/FADTAgAdAAoKfR7/FADTAgAAAA==.',
Ge='Gebuss:BAABNQAECn84AAMdAAoKZyRCCABSAwAdAAoKZyRCCABSAwAYAAEK9x5vigBXAAAAAA==.Gempally:BAAANQADCgcICQAAAA==.',
Gi='Gilford:BAAANQAECgUICgAAAA==.',
Gl='Glenraven:BAAANQAECgQIBgAAAA==.',
Go='Golokan:BAAANQADCgYIDAAAAA==.Goochaddi:BAABNQAECn8bAAIUAAoKcBlLfAAyAgAUAAoKcBlLfAAyAgAAAA==.Gorgunga:BAAANQAECgUIBQAAAA==.Gozer:BAAANQABCgcICQAAAA==.',
Gr='Grolden:BAAANQAECgUICQAAAA==.Grïpnrïp:BAAANQAECgEIAQAAAA==.',
Gu='Gunnerrata:BAAANQAECgYIDgAAAA==.',
Ha='Hahalua:BAAANQAECgcICgAAAA==.Halieight:BAAANQAECgIIAgABNQAECgoKRwAIAMIeAA==.Halifaxx:BAABNQAECn9HAAIIAAoKwh7pGwCPAgAIAAoKwh7pGwCPAgAAAA==.Halifive:BAAANQADCgIIAgABNQAECgoKRwAIAMIeAA==.Haliseven:BAAANQADCgQIBAABNQAECgoKRwAIAMIeAA==.Halisix:BAAANQADCgIIAgABNQAECgoKRwAIAMIeAA==.Halithree:BAAANQADCgYICgABNQAECgoKRwAIAMIeAA==.Halitwo:BAAANQADCggICgABNQAECgoKRwAIAMIeAA==.Hapiagin:BAAANQAECgUIDwAAAA==.Haraboo:BAAANQAECgUIBwAAAA==.Harmaa:BAAANQAECgcIEAAAAA==.Hauron:BAAANQAECgYIBwABNQAECgUICQADAAAAAA==.Havengul:BAAANQAECggIEAAAAA==.Hawknor:BAAANQAECgYIEgAAAA==.',
He='Healthcare:BAABNQAECn8xAAMRAAoKqRjjPgBkAgARAAoKqRjjPgBkAgAQAAUKzwx4xgAFAQABNQAFFAkJKQAJAC8ZAA==.Healthplan:BAAANQADCgYIBgABNQAECgoKIgAXAOgRAA==.Heartilly:BAACNQAFFH8UAAIRAAcKlBb3BwDVAQARAAcKlBb3BwDVAQA1AAQKf0EAAhEACgpkIrkOAEwDABEACgpkIrkOAEwDAAAA.Herm:BAABNQAECn9FAAMeAAoK4SSmAQCzAwAeAAoK4SSmAQCzAwALAAgKrhrSIwAHAgAAAA==.',
Ho='Holyfu:BAAANQAECgUIDAABNQAECgoKKwAZAGEbAA==.Holymidget:BAAANQAECgEIAQAAAA==.Holysky:BAABNQAECn8UAAMXAAUKABhoSwBpAQAXAAUKABhoSwBpAQAUAAQKlQcM/ACEAAAAAA==.Holytim:BAABNQAECn86AAQJAAoKECApIwDhAgAJAAoKECApIwDhAgAWAAcKhRWCCADdAQAKAAIK0A2iaABeAAAAAA==.Honeypackz:BAAANQAECgcIDAAAAA==.Honnik:BAAANQABCgIIAgAAAA==.Hotbarbie:BAAANQADCgIIAgAAAA==.Hotpink:BAAANQADCgUIDQAAAA==.How:BAABNQAECn8fAAMeAAkK7B/mCAD+AgAeAAkK7B/mCAD+AgALAAIKAA4yXgBoAAAAAA==.',
Hu='Humongulus:BAABNQAECn8ZAAILAAoKGwxDMACVAQALAAoKGwxDMACVAQAAAA==.',
Ic='Ickysins:BAAANQAECgEIAQAAAA==.',
Ig='Ignored:BAABNQAECn8dAAMUAAoKRhfsegA1AgAUAAoKRhfsegA1AgAXAAQKrgcOAwFzAAAAAA==.Ignoréd:BAAANQAECgcIDAABNQAECgoKHQAUAEYXAA==.Ignöred:BAABNQAECn8ZAAIOAAcKexjNkwDrAQAOAAcKexjNkwDrAQAAAA==.',
Il='Ila:BAAANQADCgIIAgAAAA==.Ilidra:BAAANQAECgEIAQAAAA==.Illaine:BAAANQADCgYIBgAAAA==.Illidæn:BAABNQAECn8oAAIMAAoKcA3YLgDKAQAMAAoKcA3YLgDKAQAAAA==.',
Im='Imgonaruneya:BAAANQAECgUICQAAAA==.Imos:BAAANQABCgUIBAAAAA==.Imperîus:BAAANQADCgUIBQABNQAFFAcIEgABAA8aAA==.',
In='Inaniel:BAABNQAECn8eAAIMAAkKHRjEHwBQAgAMAAkKHRjEHwBQAgAAAA==.Inq:BAABNQAECn9BAAMIAAoKySKgCQALAwAIAAoKySKgCQALAwAEAAEKLgu4TgAqAAAAAA==.',
Ir='Iridaceaë:BAABNQAECn8tAAIJAAoKwBmAQwBeAgAJAAoKwBmAQwBeAgABNQAECggIDgADAAAAAA==.Iryris:BAAANQAECgMIBwAAAA==.',
Is='Isedeath:BAABNQAECn84AAQBAAoKohjZSQDuAQABAAoKohjZSQDuAQATAAkKIgtLRwChAQACAAEKOB2QwwBBAAAAAA==.Istvankh:BAAANQABCgMIBAABNQADCgEIAQADAAAAAA==.',
Ja='Jaholin:BAABNQAECn8bAAMJAAkKlBIxOADXAQAJAAgKQxMxOADXAQAKAAcKBRoxMgCRAQAAAA==.Jarhead:BAAANQADCgIIAgAAAA==.Jarrhead:BAAANQAECgUICgAAAA==.Jaxarus:BAAANQADCgEIAQAAAA==.',
Je='Jenaveive:BAABNQAECn8YAAIFAAgK4QqJpAC9AQAFAAgK4QqJpAC9AQAAAA==.Jethoisi:BAAANQAECgYIEAABNQAFFAYIDgANADMIAA==.Jexi:BAAANQADCgYIBgABNQAECgQICQADAAAAAA==.',
Jn='Jnex:BAABNQAECn8dAAIUAAkKqCGLLABLAgAUAAkKqCGLLABLAgAAAA==.',
Jo='Jongani:BAACNQAFFH8OAAINAAYKMwjBBgAbAQANAAYKMwjBBgAbAQA1AAQKfxcAAg0ACgpHFwsJADICAA0ACgpHFwsJADICAAAA.Jookiez:BAEANQAECgcICAABNQAECgoKKAAQAAYmAA==.',
Ju='Judgemehr:BAAANQAECggIEAABNQAECgoKOAAIAMciAA==.Judgepain:BAAANQAECggICQAAAA==.Judgmental:BAABNQAECn8yAAIXAAoK3R8bFgAmAwAXAAoK3R8bFgAmAwAAAA==.Justine:BAAANQAECgUIDwAAAA==.',
Ka='Kaboni:BAAANQAECgMIBgAAAA==.Kaelthorn:BAAANQAECgYIBwAAAA==.Kaelysong:BAAANQADCgUJDQAAAA==.Kageansatsu:BAAANQAECgUIDwAAAA==.Kairah:BAAANQAECgUIBwAAAA==.Kaivig:BAAANQADCgYIBgAAAA==.Kalï:BAAANQADCgYICQAAAA==.Karlil:BAAANQAECgYIEgAAAA==.Kasiene:BAAANQAECgIIAgAAAA==.Kasnay:BAAANQADCgQIBgAAAA==.Kateria:BAAANQADCgQIBAAAAA==.Kathenset:BAABNQAECn8YAAIaAAgKqQKLEwCcAAAaAAgKqQKLEwCcAAAAAA==.Kazenseth:BAAANQADCgEIAQAAAA==.Kazeral:BAACNQAFFH8MAAIdAAUKPRRNCwBJAQAdAAUKPRRNCwBJAQA1AAQKfx0ABB0ACgqtFqkaACcBAB8ABwo+EloMAJIBAB0AAwrrH6kaACcBABgAAwq/AWRKAGcAAAAA.Kazzi:BAAANQADCgIIAgAAAA==.',
Ke='Keener:BAABNQAECn8sAAIOAAoKFBrfJgBKAgAOAAoKFBrfJgBKAgAAAA==.Kelvin:BAAANQABCgQIBAAAAA==.Kelyana:BAAANQABCgMIAwAAAA==.Kerrla:BAAANQAECggICQABNQAFFAUIDAAdAD0UAA==.Keylleth:BAAANQADCgYJDwAAAA==.',
Kh='Khalanie:BAABNQAECn8pAAIYAAkKxgkEQwBTAQAYAAkKxgkEQwBTAQAAAA==.Khamnox:BAABNQAECn8dAAMcAAkKWxXxPgCuAQAcAAgKgBXxPgCuAQAgAAIKfRRkXABtAAAAAA==.Khionia:BAAANQAECgIIAgAAAA==.',
Ki='Kidthefrist:BAAANQADCgUIBQAAAA==.Kielnmsoftly:BAAANQADCgYIBgAAAA==.Kilaia:BAAANQAECgEIAgAAAA==.Kirru:BAAANQAECgYIEQAAAA==.',
Kn='Knoble:BAAANQADCgQIBAAAAA==.',
Ko='Kokatoes:BAAANQAECgIIAgABNQAECgkJMQAOAPIRAA==.Korabas:BAAANQAECgUIBQABNQAECgoKRQAZAP4jAA==.',
Kr='Kreaton:BAAANQAECggIEgAAAA==.Kryt:BAABNQAECn8vAAIRAAoKuR17MQCbAgARAAoKuR17MQCbAgAAAA==.',
Ku='Kuponia:BAAANQABCgIIAgAAAA==.',
Kw='Kwichangpain:BAAANQADCgcIDQAAAA==.',
Kx='Kxchiki:BAABNQAECn8rAAIXAAoKuhEYRwBKAgAXAAoKuhEYRwBKAgAAAA==.',
['Kã']='Kãz:BAAANQADCgYICAAAAA==.',
La='Laaklem:BAAANQAECgEIAQAAAA==.Laei:BAAANQADCggIEAAAAA==.Laserfingies:BAAANQAECgMIAwAAAA==.Lastsun:BAAANQADCgIIAgAAAA==.Lavacakes:BAABNQAECn8+AAMRAAoKrR+2HAD7AgARAAoKrR+2HAD7AgAQAAQKfgmfgACdAAAAAA==.Lawndartz:BAAANQADCggJDgAAAA==.',
Le='Lelantoz:BAABNQAECn8oAAIFAAcKZAbQhQAmAQAFAAcKZAbQhQAmAQAAAA==.Leliel:BAAANQABCgUICgAAAA==.Leqoofus:BAAANQADCgIIAgABNQAECgMIAwADAAAAAA==.',
Li='Lidan:BAABNQAECn8uAAIdAAgKnQ/pEAB8AQAdAAgKnQ/pEAB8AQAAAA==.Liebli:BAABNQAECn8cAAIcAAkKsyDOCgDbAgAcAAkKsyDOCgDbAgAAAA==.Liltank:BAAANQAECgIIAgAAAA==.Limity:BAAANQAECgQICAAAAA==.Linaeni:BAAANQADCgIIAgAAAA==.Linaradice:BAAANQAECgUIDAAAAA==.Lixandra:BAAANQADCgEIAQAAAA==.',
Lo='Logyn:BAAANQAECgMIAgAAAA==.Lonelyspark:BAAANQADCgQICQAAAA==.Lonnias:BAABNQAECn8XAAIEAAYKxxDiFABdAQAEAAYKxxDiFABdAQAAAA==.Lotsalock:BAAANQADCgUIBQAAAA==.',
Lu='Lucicelse:BAAANQADCgYIDwAAAA==.Lucifur:BAAANQADCgMIAwAAAA==.Lucyfire:BAAANQAECgUIBQABNQAFFAQIBQAIAIEQAA==.Luna:BAABNQAECn8jAAIGAAkK4g4KLwCiAQAGAAkK4g4KLwCiAQAAAA==.Lunarluvgood:BAEBNQAECn8jAAIVAAkKFSPsCACHAwAVAAkKFSPsCACHAwABNQAECgoKKQAQAD0gAA==.',
Ly='Lyrelia:BAAANQAECgIIAwAAAA==.',
Ma='Madbones:BAAANQADCgYIDAABNQAECgoKIgAXAOgRAA==.Madmetal:BAABNQAECn8iAAMXAAoK6BFOWgAKAgAXAAoK6BFOWgAKAgAUAAEK3QPqwQEnAAAAAA==.Mado:BAAANQAECgcIDgAAAA==.Madstorm:BAAANQADCggICAAAAA==.Magefood:BAAANQAECgUICgABNQAECgkJGAAOAA8cAA==.Magicky:BAABNQAECn8YAAIIAAYK4gyGswDgAAAIAAYK4gyGswDgAAAAAA==.Mahlkier:BAAANQADCgUIDwAAAA==.Mahlkierson:BAAANQADCgQIAwAAAA==.Maikego:BAAANQAECgYIDQAAAA==.Mairadin:BAAANQAECgIIAgAAAA==.Malchelo:BAAANQAECgQIBgAAAA==.Malfhunter:BAABNQAECn84AAIhAAoKsBr+CQBGAgAhAAoKsBr+CQBGAgAAAA==.Malfshammy:BAAANQADCgcIBwAAAA==.Maligosa:BAAANQADCgQIBgAAAA==.Manager:BAAANQADCggIBwAAAA==.Mangolassi:BAAANQAECgQIDAAAAA==.Manto:BAAANQAECgQIBAAAAA==.Mantodea:BAAANQAECgEIAQAAAA==.Manup:BAAANQADCgcIEAAAAA==.Marmin:BAABNQAECn8mAAIEAAkKBhaHCgAgAgAEAAkKBhaHCgAgAgAAAA==.Marossa:BAAANQADCgcIBgAAAA==.Marymae:BAAANQADCgUIDgAAAA==.Mattwm:BAAANQAECgEIAQAAAA==.Maîa:BAAANQADCggICAAAAA==.',
Me='Meikai:BAAANQAECgUICAAAAA==.Melillia:BAAANQAECgcIEwAAAA==.Melted:BAACNQAFFH8QAAIIAAYK8RepDgACAgAIAAYK8RepDgACAgA1AAQKfysAAwgACgrIImocAGUDAAgACgq2H2ocAGUDAAQAAQo2IBM4AF0AAAAA.Merdocki:BAABNQAECn83AAMcAAoK1h/iMwC6AgAcAAkKax7iMwC6AgAgAAQKqRw/IQBnAQAAAA==.Merdra:BAABNQAECn8yAAINAAkKbSNPBQBcAwANAAkKbSNPBQBcAwAAAA==.Merdre:BAABNQAECn9DAAQJAAoK0ByHIADtAgAJAAoK6RuHIADtAgAWAAQKLxmWEgD+AAAKAAUKNQV9TwDVAAAAAA==.',
Mi='Michealhunt:BAAANQADCgIIAgAAAA==.Midory:BAAANQAECgQICQAAAA==.Midranaira:BAAANQADCgEIAQAAAA==.Milda:BAAANQAECgYICQAAAA==.Milkymocha:BAAANQAECgYIDQAAAA==.Misscorona:BAAANQAFFAEIAQAAAA==.Mistyque:BAAANQAECgQICgAAAA==.Mithrandir:BAAANQADCgUIBAAAAA==.Mithrond:BAAANQADCgEIAQAAAA==.',
Mo='Modercai:BAAANQAECgQIBAAAAA==.Mojor:BAAANQABCgEIAQAAAA==.Monalea:BAAANQAECgIIAgABNQAECgoKMQAHALgSAA==.Monkshadow:BAAANQAECgcIDQAAAA==.Monkydleafy:BAAANQADCgQIAwABNQAECgEIAgADAAAAAA==.Morcant:BAAANQAECgUIEAAAAA==.Morianoley:BAAANQAECgQICgAAAA==.Morlu:BAABNQAECn8YAAIPAAoK7h4UAwB+AgAPAAoK7h4UAwB+AgAAAA==.Mortenson:BAAANQAECgYIDwAAAA==.Mortïmer:BAABNQAECn8fAAMKAAkKSBWtHwA+AgAKAAkKSBWtHwA+AgAJAAMKXw232QCbAAAAAA==.Mousee:BAAANQAECgIIAgAAAA==.',
Ms='Msdonnapally:BAAANQAECgQIBwAAAA==.',
Mu='Muffindr:BAAANQAECgMIAwABNQAECgYICQADAAAAAA==.',
My='Mysticmage:BAAANQAECgUIDAAAAA==.Myxian:BAEANQAECgQIBQABNQAECgoKNwAOALMkAA==.',
['Mö']='Möñk:BAAANQADCgQIBQAAAA==.',
Na='Nala:BAAANQAECgQIBwAAAA==.Narallia:BAAANQADCgYICAAAAA==.Nargalad:BAAANQABCgUICQAAAA==.Narios:BAAANQAECggIEgAAAA==.Natureshogun:BAAANQAECgUIBQAAAA==.',
Ne='Nediem:BAAANQADCgQIBQAAAA==.Nefeli:BAAANQABCgQIBQAAAA==.Neral:BAAANQADCgMIAwAAAA==.Nexxicus:BAAANQADCgQIBwAAAA==.',
Ni='Nightmehr:BAABNQAECn84AAIIAAoKxyKiGACiAgAIAAoKxyKiGACiAgAAAA==.Nightshade:BAAANQADCgcIDQAAAA==.Nippy:BAAANQADCgUICQAAAA==.',
No='Nored:BAAANQADCgEIAQAAAA==.Nosaj:BAAANQAECgYIDQAAAA==.Nostrodomus:BAAANQADCgQIBwAAAA==.Novalee:BAAANQADCgUICAAAAA==.',
Nu='Nuan:BAAANQADCgMIAwAAAA==.',
Ny='Nyki:BAAANQADCgMIAwAAAA==.',
Od='Odlaw:BAABNQAECn8aAAIKAAcK+wkeIQD+AAAKAAcK+wkeIQD+AAAAAA==.',
Ol='Olaria:BAAANQAECgIIAQABNQAECgYIGgAhAJcOAA==.Olinax:BAABNQAECn8rAAQdAAoKRBm8CQDtAQAdAAkKKhm8CQDtAQAfAAUKXxWoDwAtAQAYAAEKAACbVQAtAAAAAA==.',
Om='Omalmalha:BAAANQAECgYICAAAAA==.',
On='Onedruidtion:BAAANQAECgIICAAAAA==.',
Or='Orheo:BAAANQADCgcICwAAAA==.Orionmoon:BAABNQAECn8gAAMJAAkKvw7EcgDEAQAJAAkKvw7EcgDEAQAKAAYKsgfYSAD5AAAAAA==.Orlos:BAABNQAECn8aAAMhAAYKlw7XNwB0AAAFAAYKlw5l4ABAAQAhAAUK/ATXNwB0AAAAAA==.Oräkk:BAABNQAECn8sAAMZAAkKoiTCBQASAwAZAAkKoiTCBQASAwAOAAIKxhJFKAGGAAAAAA==.',
Pa='Padrin:BAABNQAECn8aAAIFAAgKQBEuWACUAQAFAAgKQBEuWACUAQAAAA==.Pandapaws:BAACNQAFFH8KAAIRAAMKaxn3DwDdAAARAAMKaxn3DwDdAAA1AAQKfzsAAxEACgoGJTcFAJ4DABEACgoGJTcFAJ4DABAAAwpVB8/8AJgAAAAA.Papaflask:BAABNQAECn8jAAIJAAkKoBmPHQB0AgAJAAkKoBmPHQB0AgAAAA==.Parthal:BAAANQADCgEIAQAAAA==.Partyhardly:BAABNQAECn80AAINAAoK/xOjEwBvAQANAAoK/xOjEwBvAQAAAA==.Pavetta:BAAANQAECgUIBQAAAA==.Pavle:BAAANQAECgQIBAAAAA==.',
Pd='Pdiddi:BAABNQAECn8XAAMBAAkKbhrQTADhAQABAAYK1x7QTADhAQATAAgKgBNDQQDBAQAAAA==.',
Pe='Pellaeon:BAABNQAECn9CAAMCAAoKHhqeDwBMAgACAAoKgxmeDwBMAgABAAgKTxWKTADiAQAAAA==.Pelt:BAABNQAECn8nAAIMAAkK0RdmGwB8AgAMAAkK0RdmGwB8AgAAAA==.Perseus:BAAANQAECgEIAQABNQAECgcIGgAYAMwGAA==.Perthynas:BAAANQAECgIIAgAAAA==.Petmasta:BAAANQABCgEIAQAAAA==.',
Ph='Pharaun:BAAANQAECgQICQABNQAECgoKPwABABkKAA==.Phlan:BAEANQAECgQIBAAAAA==.Phrostir:BAAANQAECggIEAAAAA==.',
Pi='Picklechips:BAAANQADCgEIAQAAAA==.Pillgrimm:BAAANQAECgUIEAAAAA==.Pillsburyman:BAAANQAECgQICAAAAA==.',
Po='Pogue:BAAANQADCgIIAgAAAA==.Pointee:BAAANQADCgYICgAAAA==.Poisson:BAABNQAECn8fAAIYAAkKwQvYGgABAgAYAAkKwQvYGgABAgAAAA==.Pokoxo:BAABNQAECn8zAAQNAAoKvRqZFABeAgANAAoKvRqZFABeAgAXAAYKVQmiwwD0AAAUAAQKRwmiOQHEAAABNQAECgYIBwADAAAAAA==.Pookiez:BAEANQAECgMIBwABNQAECgoKKAAQAAYmAA==.',
Pr='Prancine:BAAANQAECgQIBAABNQAFFAkJKQAJAC8ZAA==.Prescess:BAAANQADCgUICAAAAA==.Providence:BAABNQAECn8+AAIHAAoKQB7vDgBdAgAHAAoKQB7vDgBdAgAAAA==.Prsr:BAAANQAECgMIBgABNQAFFAcIEgABAA8aAA==.',
Pu='Pudgypaws:BAAANQAECgQIBwAAAA==.Punishment:BAAANQABCgIIAgABNQAECgYIGAAIAOIMAA==.',
Py='Pyoneer:BAAANQABCggIJgAAAA==.',
Qu='Quickmend:BAAANQAECgQIBAAAAA==.Quickpal:BAAANQAECgcIEQAAAA==.Quickpaw:BAABNQAECn8fAAIeAAkKYxsrDwCOAgAeAAkKYxsrDwCOAgAAAA==.',
Ra='Raccoons:BAAANQADCgMIAwABNQAFFAUIDAAcAOISAA==.Radell:BAAANQAECgUICQAAAA==.Rageproof:BAAANQAECgEIAgAAAA==.Ragged:BAACNQAFFH8GAAITAAIKiBkODQCaAAATAAIKiBkODQCaAAA1AAQKfycAAxMACgqVINUXAMwCABMACgqVINUXAMwCAAEAAQoAAIjiADEAAAAA.Raidbloom:BAECNQAFFH8XAAIGAAUKvhaUBABsAQAGAAUKvhaUBABsAQA1AAQKfxwAAgYACgr0F+0LAHgCAAYACgr0F+0LAHgCAAE1AAQKCgouABcAihkA.Raidshock:BAEBNQAECn8uAAIXAAoKihkAMwCZAgAXAAoKihkAMwCZAgAAAA==.Rainsinger:BAAANQAECgIIAgAAAA==.Ramook:BAEANQAECgQICQAAAA==.Randomchar:BAABNQAECn9IAAIUAAoKdxP9VAC3AQAUAAoKdxP9VAC3AQAAAA==.Rankor:BAAANQADCgYIBgABNQAECgoKRAAbAJ4QAA==.Rastann:BAABNQAECn9GAAIUAAoKqx9MJQBwAgAUAAoKqx9MJQBwAgAAAA==.Ratsdrack:BAAANQADCgMIAwAAAA==.Rawrlas:BAAANQADCgYICQABNQAECgYIGgAhAJcOAA==.Razdor:BAAANQADCgUIBgAAAA==.',
Re='Reapertoo:BAACNQAFFH8PAAMBAAcKnh+9AgAZAgABAAUKAiS9AgAZAgATAAYK9htuBwCDAQA1AAQKfz4AAwEACgodJjUOAEcDAAEACAqYJTUOAEcDABMACgp0IZgIAN4CAAAA.Recreant:BAAANQADCgcIDQAAAA==.Redbaron:BAABNQAECn8gAAIHAAoKLxmENAAJAgAHAAoKLxmENAAJAgAAAA==.Redmtndew:BAAANQAECgIIAgAAAA==.Reetep:BAAANQADCggIGQABNQAECgUICgADAAAAAA==.Regeth:BAAANQADCggIFQAAAA==.Remily:BAAANQAECgYICwABNQAFFAQIBQAIAIEQAA==.Repuns:BAEANQAECggIBAABNQAECgoKKQAQAD0gAA==.Revin:BAAANQAECgEJAQAAAA==.Rezalia:BAAANQADCgMIAwAAAA==.',
Ro='Roary:BAAANQADCgcICQABNQAECgMIAwADAAAAAA==.Rodned:BAAANQADCggJCAAAAA==.Rolas:BAAANQADCgMIAQABNQAECgYIGgAhAJcOAA==.Rondle:BAAANQAECgQIBQAAAA==.Roonyx:BAAANQAECgEIAQAAAA==.Rottencorpse:BAAANQADCgQIBAAAAA==.Rozalin:BAABNQAECn89AAMIAAoKRSN4EQCMAwAIAAoKRSN4EQCMAwAEAAEKMSKSNQBlAAAAAA==.Rozalinamoon:BAAANQADCgMIAwAAAA==.',
Ru='Rubeus:BAEANQAECgcIBwABNQAECgoKKQAQAD0gAA==.Rurouni:BAAANQAECgIIAgAAAA==.Rustystorm:BAAANQADCgMIAwAAAA==.Rustywarlock:BAAANQAECgYIDQAAAA==.',
Ry='Ryoshi:BAABNQAECn8pAAMFAAoKZhwfOgC8AgAFAAoKZhwfOgC8AgAiAAcKZxdvCADNAQAAAA==.',
['Rò']='Ròòszy:BAAANQADCgYIBwAAAA==.',
Sa='Sacredstars:BAAANQAECgUIBQAAAA==.Sacredswords:BAACNQAFFH8HAAIOAAQKvwbJFQC0AAAOAAQKvwbJFQC0AAA1AAQKfycAAw4ACQrEGZdXAIQCAA4ACQrEGZdXAIQCAA8AAgptELgiAKAAAAAA.Sakito:BAABNQAECn8dAAMGAAoKQxh1CADJAgAGAAoKQxh1CADJAgAjAAUKWhK0LgAkAQABNQAFFAcIFAARAJQWAA==.Salarai:BAAANQADCgcIBgABNQAECgYIGgAhAJcOAA==.Sanguinius:BAABNQAECn8hAAMXAAoKNyN2BwCOAwAXAAoKNyN2BwCOAwAUAAIKMQS1hwFPAAAAAA==.Sapphiremist:BAABNQAECn8aAAIHAAYKuQu+VAA8AQAHAAYKuQu+VAA8AQAAAA==.Sayen:BAAANQAFFAEIAQAAAA==.',
Sc='Scachity:BAABNQAECn8vAAMcAAoKchMeXQBAAgAcAAoKchMeXQBAAgAgAAMKexAlRQCxAAAAAA==.Scan:BAABNQAECn8uAAIQAAoKECCoCwDQAgAQAAoKECCoCwDQAgAAAA==.Schein:BAAANQAECgYIEwAAAA==.',
Se='Segsacute:BAABNQAECn8bAAIOAAoKaBOJcgA9AgAOAAoKaBOJcgA9AgAAAA==.Sendatu:BAAANQAECgEIAwABNQAECgoKKwACAOoQAA==.Sepulchre:BAABNQAECn8/AAMBAAoKGQr0JQBJAQABAAoKGQr0JQBJAQATAAYKagSPdgDIAAAAAA==.Seraphiim:BAAANQADCggICAAAAA==.',
Sh='Shadeaway:BAAANQAECgYIBQABNQAECgoKGwAUAHAZAA==.Shadowhart:BAAANQADCgcIBwAAAA==.Shaeebulay:BAAANQABCgQIBAAAAA==.Shamaroo:BAAANQABCgUIBwAAAA==.Shaundakul:BAABNQAECn8iAAMRAAgKeBX0JgAXAgARAAgKeBX0JgAXAgAQAAQKiQqz3QDaAAAAAA==.Shephion:BAABNQAECn8UAAIIAAYKvBlw2gDSAQAIAAYKvBlw2gDSAQABNQAECgoKRQAeAOEkAA==.Shikimori:BAAANQAECggIBwAAAA==.Shnozberries:BAAANQADCggICQAAAA==.Shockhart:BAABNQAECn8fAAQRAAoKHw+LMQDbAQARAAoKHw+LMQDbAQASAAMKzwf8IwBxAAAQAAEKAACI4gAAAAAAAA==.Shonuffz:BAAANQADCgYIBgAAAA==.Shortnstack:BAABNQAECn8ZAAIFAAYK7AqdiAAgAQAFAAYK7AqdiAAgAQAAAA==.Shãdow:BAAANQADCgUIBQAAAA==.',
Si='Side:BAAANQAECgEIAQAAAA==.Siegfried:BAAANQAECgQIBAAAAA==.Simori:BAAANQADCgIIAgAAAA==.Sindrel:BAAANQAECgUICQABNQAFFAQIDwALAFYeAA==.Siyurie:BAAANQADCgcIEAAAAA==.',
Sk='Skawalker:BAABNQAECn9FAAMGAAoKQyMMBQAxAwAGAAoKQyMMBQAxAwAkAAEKVxfcLAA/AAAAAA==.',
Sl='Slaed:BAAANQADCgYIBwAAAA==.Slaynne:BAABNQAECn8UAAQOAAgKjRXPsgCeAQAOAAcKTRfPsgCeAQAZAAMKlxCUMgCjAAAPAAEKAABVLgBIAAAAAA==.',
Sm='Smoky:BAAANQAECgUIBwAAAA==.Smäug:BAACNQAFFH8SAAMaAAcKOR2PAwC0AQAaAAYK2R2PAwC0AQAbAAEKuBr0CgBbAAA1AAQKfzQABBoACgpDJVkBALsDABoACgpDJVkBALsDACUABwr7DxkqAF4BABsAAQqTIhIfAGcAAAAA.',
Sn='Snailas:BAAANQAECgYIBgAAAA==.Sniperwolf:BAAANQADCgYIBgABNQAECgQIDAADAAAAAA==.Snowleopard:BAAANQADCgIIAgAAAA==.',
So='Sodomn:BAAANQADCgQIBAAAAA==.Solria:BAABNQAECn8wAAIJAAkKqRksGAChAgAJAAkKqRksGAChAgAAAA==.Sonnytyphoon:BAAANQADCgYIBgAAAA==.',
Sp='Spacewulf:BAAANQADCgMIAwABNQAECgoKPwABABkKAA==.Spicychip:BAAANQADCgEIAQAAAA==.',
St='Starnex:BAABNQAECn8WAAIVAAkKnxcEEQA4AgAVAAkKnxcEEQA4AgAAAA==.Statyrea:BAAANQADCgUIBQAAAA==.Strikes:BAABNQAECn8YAAMNAAoKQBgnDgC9AQANAAcKQh8nDgC9AQAUAAkKdQm42wBkAQAAAA==.Styx:BAACNQAFFH8PAAIZAAQKEyXdAAA6AQAZAAQKEyXdAAA6AQA1AAQKf1MAAhkACgrgJgsAABgEABkACgrgJgsAABgEAAAA.',
Su='Sugabuns:BAAANQAECggIDgAAAA==.Sukfööt:BAABNQAECn8vAAIZAAoKVg/eCwB/AQAZAAoKVg/eCwB/AQAAAA==.Sumbatadh:BAAANQAECgYIBwAAAA==.Summerflip:BAAANQAECgYIBQABNQAECgoKQwAJANAcAA==.Sunnytyphoon:BAABNQAECn8aAAIkAAgKkhTIEAD7AQAkAAgKkhTIEAD7AQAAAA==.',
Sw='Swiftholy:BAAANQAECgcIEgAAAA==.Swiftmends:BAAANQAECgIIAgAAAA==.',
Sy='Sydahlis:BAAANQAECgcIEwAAAA==.Sylvestris:BAABNQAECn8ZAAIGAAkKIiQrCABCAwAGAAkKIiQrCABCAwAAAA==.',
Ta='Taiyana:BAAANQAECgQIBAAAAA==.Tangie:BAAANQADCggICgAAAA==.Tankjob:BAABNQAECn8VAAIUAAcKRA7clgAlAQAUAAcKRA7clgAlAQAAAA==.Tanklorswift:BAAANQAECgIIAgAAAA==.Tastemycrits:BAAANQADCggICAABNQAECgoKGwAUAHAZAA==.',
Td='Tdog:BAAANQADCggICwAAAA==.',
Te='Tealetresh:BAAANQABCgIIAgAAAA==.Teapot:BAABNQAECn8YAAIOAAkKDxySPQDaAQAOAAkKDxySPQDaAQAAAA==.Tedoseirum:BAABNQAECn81AAIHAAoKVSKjCgBaAwAHAAoKVSKjCgBaAwAAAA==.Terminal:BAAANQADCggICwAAAA==.Terpyu:BAAANQADCgEIAQAAAA==.Texasbilly:BAAANQADCgYIDAAAAA==.Texasredneck:BAAANQADCgYIDAAAAA==.Texasslasher:BAAANQADCgYIBgAAAA==.',
Th='Thaelyra:BAAANQADCggICAAAAA==.Thedtwo:BAAANQAECgMIAgAAAA==.Thorgarrus:BAABNQAECn9HAAIUAAoK9B3RJwBjAgAUAAoK9B3RJwBjAgAAAA==.',
Ti='Tigerwoodz:BAAANQAECgEIAQAAAA==.Tilbourne:BAAANQAECgQIBQAAAA==.Timmeh:BAAANQAECgIIAgAAAA==.Timvoker:BAAANQADCgYIBgAAAA==.',
To='Toddie:BAABNQAECn83AAMFAAoKmhvGGwCAAgAFAAoKmhvGGwCAAgAhAAEKAABKjgAxAAAAAA==.Tolkarnyx:BAAANQADCgUIBQABNQAFFAcIFAARANwXAA==.Tommyj:BAAANQADCggICwAAAA==.Torcher:BAAANQAECgQIAwAAAA==.Tormod:BAABNQAECn8uAAIFAAkKbhdSOwDzAQAFAAkKbhdSOwDzAQAAAA==.Torvaldt:BAABNQAECn8cAAIXAAoK0BnUDgDkAgAXAAoK0BnUDgDkAgABNQAECgoKNwAFAJobAA==.Tourmod:BAABNQAECn8bAAIEAAcKeg+mDwAPAQAEAAcKeg+mDwAPAQAAAA==.Towmater:BAAANQAECgIIAwAAAA==.',
Tr='Trakkarz:BAAANQAECgQIBQAAAA==.Traps:BAAANQAECgQIDQAAAA==.Trashypanda:BAACNQAFFH8VAAIIAAUK9hpnEwD9AAAIAAUK9hpnEwD9AAA1AAQKfzMAAggACgrEJBsEAEkDAAgACgrEJBsEAEkDAAAA.Traviskelce:BAEANQAECggICAABNQAECgoKKQAQAD0gAA==.Trays:BAAANQADCgYIBgAAAA==.Trender:BAAANQADCgQIBAABNQAECgMIBgADAAAAAA==.Treniity:BAAANQAECgUIDwAAAA==.Tressilly:BAACNQAFFH8FAAIIAAQKgRCNRQCeAAAIAAQKgRCNRQCeAAA1AAQKfy0AAggACgqoHHwyACYDAAgACgqoHHwyACYDAAAA.Trinagirl:BAAANQADCgYIBgAAAA==.Trinneries:BAAANQADCgcJBwAAAA==.Triná:BAAANQADCgYIBgABNQADCgYIBgADAAAAAA==.Tristanyia:BAAANQADCggICAAAAA==.Tristiyan:BAAANQAECgUICQAAAA==.Trogdorr:BAABNQAECn9EAAMbAAoKnhA0CwCvAQAaAAkKjhBsEwAYAgAbAAkKwA00CwCvAQAAAA==.Trutert:BAAANQAECgQICgAAAA==.Tryana:BAAANQAECgUIBgAAAA==.Trystiana:BAAANQADCgMJBAAAAA==.',
Tt='Ttania:BAAANQADCgYIDgAAAA==.',
Tu='Tubor:BAAANQAECgUICwAAAA==.',
Tw='Tweetwee:BAAANQAECggICAAAAA==.',
Ty='Tyledis:BAAANQADCggIEAABNQAECgoKRQAZAP4jAA==.Tyr:BAABNQAECn8zAAMQAAoKdxuIHwAOAwAQAAoKdxuIHwAOAwARAAIK1gn9BgFaAAAAAA==.Tyrlathis:BAAANQADCgYIBgAAAA==.Tyrnova:BAAANQADCggICAAAAA==.',
['Tö']='Töshïrö:BAAANQADCgIIAgAAAA==.',
Uh='Uhope:BAAANQAECgYICgAAAA==.',
Um='Umbravolt:BAABNQAECn9HAAIjAAoKkiT6AQA7AwAjAAoKkiT6AQA7AwAAAA==.',
Un='Unclezapp:BAAANQADCggJDgAAAA==.Unravel:BAAANQADCgUIDgAAAA==.Unrealcalorx:BAAANQADCgUIBQAAAA==.Unrealronin:BAAANQAECgUICQAAAA==.',
Va='Vaeris:BAAANQADCgUJCwAAAA==.Vakero:BAABNQAECn8gAAMUAAcKuAgyuADqAAAUAAcKuAgyuADqAAAXAAIKuwEWHQE6AAAAAA==.Valeriana:BAAANQADCgQIBAAAAA==.Valess:BAABNQAECn8eAAMlAAYKjwYGIwCAAAAlAAUKGQUGIwCAAAAbAAYKSgIEEQBqAAAAAA==.Valros:BAAANQADCgYICgAAAA==.Vapor:BAAANQABCgIIAgAAAA==.Vaythan:BAABNQAECn8sAAIkAAoK/x/qAgDBAgAkAAoK/x/qAgDBAgAAAA==.',
Ve='Velneenar:BAAANQADCgQIBAAAAA==.Venchris:BAABNQAECn8fAAIOAAoK4xu7HwB1AgAOAAoK4xu7HwB1AgAAAA==.Verica:BAAANQADCgEIAQAAAA==.',
Vh='Vhiz:BAABNQAECn8VAAILAAcKRhBeLwCcAQALAAcKRhBeLwCcAQAAAA==.',
Vi='Vibrance:BAAANQADCggJEAAAAA==.Victorius:BAAANQAECgMIAwAAAA==.Viridesa:BAAANQAECgEIAQAAAA==.Vixine:BAAANQAECgUIDwAAAA==.',
Vn='Vnillabeef:BAAANQAECgQIBQABNQAFFAcIEgABAA8aAA==.',
Vo='Vohlen:BAAANQABCgYIBgAAAA==.Voidcore:BAABNQAECn8XAAMHAAkKjRbYRACfAQAHAAkKfBXYRACfAQAMAAUKfA+LJwDrAAABNQAECgoKHwAOAGEYAA==.Voidwalker:BAAANQADCgYICQABNQAFFAUIDAASAFcbAA==.',
Vy='Vysera:BAAANQAECgEIAQAAAA==.',
Wa='Warfarmer:BAAANQAECgYIEAAAAA==.Warhawke:BAAANQADCggIEAAAAA==.',
We='Werenal:BAAANQADCgcICwAAAA==.',
Wh='Whis:BAABNQAECn8VAAIYAAcKnw5AUwAQAQAYAAcKnw5AUwAQAQAAAA==.Whispernight:BAAANQADCgQIBwAAAA==.',
Wi='Widja:BAAANQADCgUIEgAAAA==.Wiimage:BAAANQAECgQIBQAAAA==.Wiivinelight:BAAANQADCgMIAwABNQAECgQIBQADAAAAAA==.Wildhus:BAABNQAECn8xAAQHAAoKuBJiNgD8AQAHAAoKbRJiNgD8AQAmAAIKnhAXGQBsAAAMAAEKogTjSQAiAAAAAA==.',
Wo='Wolfkin:BAAANQADCggIBwAAAA==.',
['Wå']='Wåffle:BAABNQAECn8cAAITAAoKuR+6CADcAgATAAoKuR+6CADcAgABNQAECgoKOAAdAGckAA==.',
['Wî']='Wîca:BAABNQAECn8ZAAIKAAgKOQv+NwBlAQAKAAgKOQv+NwBlAQAAAA==.',
Xa='Xantris:BAAANQADCgEIAQAAAA==.',
Xe='Xenowolf:BAAANQAECgYICQABNQAECgcIGgAYAMwGAA==.',
Xv='Xvire:BAAANQAECgQICAAAAA==.',
['Xû']='Xûrû:BAAANQAECgcICgAAAA==.',
Yc='Yce:BAABNQAECn8YAAMlAAYKJw8TGQDmAAAlAAUKrA4TGQDmAAAaAAYKrgvtDwDUAAAAAA==.',
Ye='Yeiko:BAAANQAECggIEQAAAA==.',
Yo='Yoker:BAABNQAECn8YAAIRAAgKQx3WggCEAQARAAgKQx3WggCEAQAAAA==.Yokersen:BAABNQAECn8cAAIFAAkKnh57OgD3AQAFAAkKnh57OgD3AQAAAA==.',
Za='Zaeladen:BAAANQAECgUIDQAAAA==.Zalorea:BAABNQAECn8WAAMjAAYKUAg3MwCUAAAjAAYKUAg3MwCUAAAGAAIKhgR1cwA7AAABNQAECgoKOwATAMEMAA==.Zambonii:BAABNQAECn8bAAQXAAoKlRJGHABhAgAXAAoKlRJGHABhAgANAAUKcAiNSQDGAAAUAAIKRQgthQFSAAAAAA==.Zamdeath:BAAANQADCgMIAwABNQAECgoKGwAXAJUSAA==.Zamlock:BAABNQAECn80AAMgAAkK7SBrDwAGAgAcAAcKOiDiSwBwAgAgAAYKlh1rDwAGAgABNQAECgoKGwAXAJUSAA==.Zammonk:BAAANQAECgEIAQABNQAECgoKGwAXAJUSAA==.Zanya:BAAANQAECgUIDQAAAA==.',
Ze='Zeiko:BAABNQAECn8qAAIBAAoKhiM9EwAeAwABAAoKhiM9EwAeAwAAAA==.Zestychip:BAAANQAECgUIDQAAAA==.Zeäl:BAAANQADCgUIBgAAAA==.',
Zh='Zhaoyun:BAAANQAECgQIBAAAAA==.',
Zi='Zilkir:BAEBNQAECn80AAMUAAoKghgbSgC3AgAUAAoKghgbSgC3AgAXAAkKZxXPTwAsAgAAAA==.Ziran:BAABNQAECn8nAAILAAoKRyQDAwCpAwALAAoKRyQDAwCpAwAAAA==.Zivadhim:BAAANQADCgIIAgAAAA==.',
Zl='Zlyth:BAABNQAECn8ZAAMaAAYKpR04GwCWAQAaAAUKIBs4GwCWAQAlAAQKUxEzPgCsAAAAAA==.',
Zz='Zzodac:BAAANQADCgEIAQABNQAECgoKMQAHALgSAA==.Zzvzz:BAAANQAECgQIBAAAAA==.',
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
