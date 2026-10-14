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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Paladin-Protection','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Unholy','Druid-Feral','Monk-Mistweaver','Druid-Balance','Druid-Guardian','Druid-Restoration','Priest-Holy','Priest-Shadow','Mage-Frost','Mage-Arcane','Priest-Discipline','DeathKnight-Frost','Warrior-Fury','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Holy','Monk-Windwalker','DemonHunter-Vengeance','Monk-Brewmaster','Evoker-Augmentation','Rogue-Assassination','Rogue-Subtlety','Hunter-Survival','DemonHunter-Havoc','Evoker-Preservation',}
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Accea:BAAANQADCgEIAQAAAA==.Acehobo:BAAANQADCgUIBQAAAA==.Acetaminofun:BAAANQAECgQIDQAAAA==.Actionjaxson:BAABNQAECn8gAAIBAAcKNSTJPwDTAgABAAcKNSTJPwDTAgAAAA==.',
Ad='Adeathknight:BAAANQABCgIIAgAAAA==.Ademis:BAAANQAECgQICAAAAA==.Admore:BAAANQAECgUIEgAAAA==.',
Ae='Aeriith:BAACNQAFFH8GAAICAAIK9BL2IACHAAACAAIK9BL2IACHAAA1AAQKfyIAAwIACQoVGBFFAEoCAAIACQoVGBFFAEoCAAMACApyC/x4ALMBAAAA.Aethmourne:BAAANQADCgMIAwABNQAECgIIAgAEAAAAAA==.',
Ag='Agameden:BAABNQAECn8bAAIFAAcKpR7CEgB0AgAFAAcKpR7CEgB0AgAAAA==.Agogg:BAAANQADCggIJAAAAA==.Agronak:BAAANQABCgIIAgAAAA==.',
Ah='Ahsina:BAAANQABCgUIBQAAAA==.',
Ai='Aintnosecret:BAAANQAECgcIDAAAAA==.Aishi:BAAANQAECgQIDQAAAA==.',
Ak='Akaya:BAABNQAECn8XAAIGAAcKoQ1HGQCgAQAGAAcKoQ1HGQCgAQABNQAECgkJIQADACYSAA==.Akitsuki:BAAANQADCgUIBQAAAA==.',
Al='Algy:BAAANQADCgIJAgAAAA==.Alillara:BAAANQADCgIIAgAAAA==.Alivron:BAABNQAECn8fAAQHAAgKTQzaCgDDAQAHAAgKTQzaCgDDAQAIAAMKPwM4IQF3AAAGAAEKAAAthQAjAAAAAA==.Alkopoke:BAAANQAECgQIBAAAAA==.Alkoren:BAAANQAECgYIDwABNQAECgkJJwAJAEsgAA==.Alkorind:BAABNQAECn8nAAMJAAkKSyC8BAAzAwAJAAkKSyC8BAAzAwAKAAIKZglMMgFoAAAAAA==.Allestra:BAACNQAFFH8JAAILAAMKbhhkDADoAAALAAMKbhhkDADoAAA1AAQKfzEAAgsACQoJHW0RAN8CAAsACQoJHW0RAN8CAAAA.',
Am='Amaranthine:BAAANQADCgYIBgAAAA==.Amoxil:BAAANQAECgUIDAAAAA==.',
An='Anasztaizia:BAEANQAECgMIBQAAAA==.Andorin:BAABNQAECn8wAAIMAAkKXBt9MwDPAgAMAAkKXBt9MwDPAgAAAA==.Andronicus:BAAANQADCgMIAwAAAA==.Andwin:BAAANQADCggJCAAAAA==.Anorah:BAAANQAECgMIBQAAAA==.Anunitu:BAABNQAECn8rAAICAAgKShtwQQBYAgACAAgKShtwQQBYAgAAAA==.',
Ao='Aoibheann:BAAANQAECgUICwAAAA==.',
Ar='Arath:BAABNQAECn8mAAINAAgKyRS9EgAiAgANAAgKyRS9EgAiAgAAAA==.Arcath:BAABNQAECn8rAAIOAAgKNxyBIwCaAgAOAAgKNxyBIwCaAgAAAA==.Arcona:BAAANQAECgUIDgAAAA==.Aristus:BAAANQADCggIEgAAAA==.Arthuel:BAAANQADCgMIAwAAAA==.',
As='Asar:BAAANQAECgQICAAAAA==.Ashlanni:BAAANQADCgIIAwAAAA==.Asiaminor:BAAANQADCgQIBgAAAA==.Astora:BAAANQADCgcIBwAAAA==.',
At='Athuzad:BAABNQAECn8nAAIPAAgKQB06MgBgAgAPAAgKQB06MgBgAgAAAA==.',
Au='Auroraalysia:BAAANQAECgIIAgAAAA==.Auroran:BAABNQAECn8bAAIFAAgKzBvUEgBzAgAFAAgKzBvUEgBzAgAAAA==.Autumnmoon:BAABNQAECn8gAAIQAAcKAA7qFgCGAQAQAAcKAA7qFgCGAQAAAA==.',
Av='Aviendah:BAAANQADCggIIQAAAA==.Avrilenv:BAAANQAECggICwAAAA==.',
Ay='Ayeroh:BAAANQAECgUICQAAAA==.Aylara:BAAANQAECgQIBAAAAA==.',
Az='Azenet:BAAANQADCgYIBgAAAA==.Azkabras:BAAANQADCgMIAwABNQAECggIJAADAEoeAA==.',
Ba='Badoink:BAAANQADCggICAABNQAECggIIwARAI8jAA==.Bakasaura:BAAANQADCgYICwABNQAECgcIIwASAMoiAA==.Balorous:BAABNQAECn8kAAQTAAgKwA0nJwBXAQASAAgK3wctVgB6AQAUAAcKSg/GNABwAQATAAcKyw4nJwBXAQAAAA==.Bansheelen:BAABNQAECn8mAAQQAAkKNxiICgCNAgAQAAkKFxiICgCNAgAUAAUKHg63QQAVAQATAAUKOhU+MAAUAQAAAA==.Banthis:BAAANQAECgcIEgAAAA==.Barkcamon:BAABNQAECn8kAAIRAAgKEBN3GgDVAQARAAgKEBN3GgDVAQAAAA==.Barmaak:BAAANQAECgEIAQAAAA==.Barrand:BAAANQADCggJCAABNQAECgcICwAEAAAAAA==.Barthelo:BAABNQAECn8iAAIOAAcKdiP6HADGAgAOAAcKdiP6HADGAgAAAA==.Bassandi:BAAANQADCgEIAQABNQAECggIJAAKAPIPAA==.Baxdock:BAAANQAECgUICgAAAA==.Baxibovtic:BAAANQADCgUIBQAAAA==.Baxideath:BAAANQAECgYIEwAAAA==.',
Be='Beastylad:BAAANQAECgUIBgAAAA==.Beefcâke:BAAANQADCgYIBgAAAA==.Bekahroo:BAAANQAECgEIAQABNQAECgQIDAAEAAAAAA==.Bekahsama:BAAANQAECgQIDAAAAA==.Belcron:BAAANQAECgQICQAAAA==.Beld:BAAANQADCgYJBgAAAA==.Beldaran:BAAANQAECgMIBQAAAA==.Belladawna:BAABNQAECn8hAAMHAAcKyAtnDACYAQAHAAcKyAtnDACYAQAIAAEK3QICSwEpAAAAAA==.Belldândy:BAAANQAECgUIBgAAAA==.Bernal:BAAANQAECgUIDgAAAA==.',
Bh='Bhature:BAAANQADCgMIAwAAAA==.',
Bi='Bigmapletree:BAABNQAECn8fAAMVAAgKbAp6fwCVAQAVAAgKbAp6fwCVAQAWAAIKOAJueAA0AAAAAA==.Bigëmu:BAAANQADCggIKQAAAA==.Billyidols:BAAANQADCgEIAQAAAA==.Bingbangpów:BAAANQAECgMIAwAAAA==.',
Bl='Blackblader:BAAANQAECgUICgAAAA==.Blarus:BAAANQADCgIIAgAAAA==.Bluecat:BAABNQAECn8cAAIXAAkKBxOYCQAzAgAXAAkKBxOYCQAzAgAAAA==.Blueplanet:BAABNQAECn8jAAISAAcKyiJtIwCyAgASAAcKyiJtIwCyAgAAAA==.',
Bn='Bnoo:BAAANQADCgEIAQABNQAFFAUICwAYAPgSAA==.',
Bo='Boarggon:BAAANQAECgMIAwABNQAECgkJJwAJAFIiAA==.Boherwin:BAABNQAECn8bAAMUAAcKByTiEQC/AgAUAAcKByTiEQC/AgAQAAQKqw8HJADrAAAAAA==.Bonnie:BAAANQAECggIDgAAAA==.Borealus:BAABNQAECn8ZAAIYAAgKRRrFlgBSAgAYAAgKRRrFlgBSAgAAAA==.',
Br='Bratakwar:BAAANQAECgcICQAAAA==.Bris:BAABNQAECn8gAAMUAAgKNBBuKwC+AQAUAAgKNBBuKwC+AQASAAEK3gNstQAqAAAAAA==.Bruby:BAAANQAECgcIEAAAAA==.Bruceleelad:BAAANQADCgYIBgAAAA==.Brugamen:BAABNQAECn8kAAMKAAgK8g/CnADQAQAKAAgKDQ/CnADQAQAJAAQKLA3wMQCiAAAAAA==.Brugg:BAABNQAECn8XAAIMAAgKVBmyXABcAgAMAAgKVBmyXABcAgABNQAECggIJAAKAPIPAA==.Brynnu:BAAANQADCgIIAgAAAA==.Brád:BAABNQAECn8eAAMVAAgKfiRJDgBRAwAVAAgKfiRJDgBRAwAZAAEKmhO6JQA+AAAAAA==.',
Bu='Bunnylajoya:BAAANQADCgYICwAAAA==.Burgerz:BAAANQADCggIGwAAAA==.Busblaster:BAABNQAECn8ZAAMaAAgKSxG0QAC+AQAaAAgKsA+0QAC+AQAOAAQKBhZ4iQDWAAAAAA==.',
['Bä']='Bäldur:BAAANQAECgcIDQAAAA==.',
Ca='Cainan:BAAANQADCgEIAQAAAA==.Calestel:BAAANQADCgIIAgAAAA==.Careßear:BAAANQAECgUIBQAAAA==.Carielle:BAAANQADCggIGgAAAA==.Carodd:BAABNQAECn8uAAIaAAkKYiK2DgAZAwAaAAkKYiK2DgAZAwAAAA==.',
Ce='Cedaver:BAABNQAECn8eAAMKAAcKWhfGmADaAQAKAAcKWhfGmADaAQAbAAEKDhzSKwBSAAAAAA==.Ceez:BAAANQADCgYIBwABNQADCggIBQAEAAAAAA==.Cellphoneguy:BAAANQADCgMIAwAAAA==.Celtigar:BAAANQAECgUICAAAAA==.',
Ch='Chaan:BAAANQAECgYIEAAAAA==.Chaddicus:BAAANQADCggJGwAAAA==.Chainna:BAAANQADCggIFwAAAA==.Chaliceia:BAAANQAECgIIAgAAAA==.Chanlin:BAABNQAECn8bAAIOAAkKyx47GQDhAgAOAAkKyx47GQDhAgAAAA==.Chateau:BAAANQAECgEIAQAAAA==.Chauda:BAAANQAECgUIBQABNQAECgkJIQADACYSAA==.Chazbot:BAAANQAECgQIBwAAAA==.Chereth:BAAANQAECgUIDgAAAA==.Cheshire:BAABNQAECn8tAAIMAAkKAh5YLgDgAgAMAAkKAh5YLgDgAgAAAA==.Chestystab:BAAANQAECgEIAQAAAA==.Chezpuff:BAAANQADCgEIAQAAAA==.Chill:BAABNQAECn8aAAIXAAgKHSPpAgAoAwAXAAgKHSPpAgAoAwAAAA==.Chlorin:BAABNQAECn8kAAIcAAgKKQZOOwBxAQAcAAgKKQZOOwBxAQAAAA==.Chocolate:BAACNQAFFH8PAAIYAAYKAxPQDwDzAQAYAAYKAxPQDwDzAQA1AAQKfyIAAhgACQrTI/dJAO4CABgACQrTI/dJAO4CAAAA.Chunala:BAAANQADCggIDwABNQAECgMIBQAEAAAAAA==.',
Cl='Cloudcrasher:BAAANQAECgQIBQAAAA==.Cloudsayer:BAAANQAECgUIBwAAAA==.Cloudspeaker:BAABNQAECn8gAAMdAAgKIBf+EQBHAgAdAAgKIBf+EQBHAgACAAEKfQ//FwE2AAAAAA==.Cloudwalker:BAAANQADCgIIAgAAAA==.',
Co='Coldazzice:BAAANQADCgIIAgABNQAECgEIAQAEAAAAAA==.Coldblades:BAAANQADCgYJBgAAAA==.Coldfrostshk:BAAANQADCgUICgAAAA==.Coldslayer:BAABNQAECn8UAAIMAAYKgBEAuACPAQAMAAYKgBEAuACPAQAAAA==.Coldsteeldx:BAAANQADCgUIBQAAAA==.Copy:BAAANQAECgQJBQAAAA==.Corpha:BAAANQADCgUJBQABNQAFFAMIBwADAK4ZAA==.Cozbysuite:BAAANQADCgIIAgAAAA==.',
Cr='Crackzap:BAAANQAECgEIAQAAAA==.Crazyrd:BAABNQAECn8hAAIGAAgK1gMmJABPAQAGAAgK1gMmJABPAQAAAA==.Creammhm:BAAANQAECgUIBQAAAA==.Crotgustus:BAAANQADCgMIBQAAAA==.Crudkicker:BAAANQADCgYIBgAAAA==.Crumblebump:BAAANQAECgUIDgAAAA==.Crummbly:BAAANQAECgIIAwAAAA==.',
Cy='Cyndelle:BAAANQAECgIIAwAAAA==.Cyntaria:BAAANQAECgUICQAAAA==.Cyriz:BAAANQAECgUICwAAAA==.',
Da='Daedrea:BAAANQADCgYICgAAAA==.Dagarim:BAAANQAECgEIAQAAAA==.Daienne:BAABNQAECn8jAAISAAgKRQ/FRQDUAQASAAgKRQ/FRQDUAQAAAA==.Danamor:BAABNQAECn8oAAIBAAgKCBhgfQArAgABAAgKCBhgfQArAgAAAA==.Dandanx:BAAANQADCggIKAABNQAECgcIHgAKAFoXAA==.Daplug:BAAANQAECgMIBgAAAA==.Dariann:BAAANQADCgYIBgAAAA==.Darkbrand:BAABNQAECn8iAAILAAgKOg6RKwDhAQALAAgKOg6RKwDhAQAAAA==.Darkdock:BAAANQADCgIIAgAAAA==.Darkladÿ:BAAANQADCgMIAwAAAA==.Darnel:BAABNQAECn8iAAIFAAcK4REAKwCBAQAFAAcK4REAKwCBAQAAAA==.Darnogden:BAAANQADCgUIBQAAAA==.Darnokk:BAAANQAECgQICQAAAA==.Dayd:BAAANQAECgIIAgAAAA==.Daylight:BAAANQAECgUICgAAAA==.',
De='Deathbreaker:BAAANQADCgYJCAAAAA==.Deathbyfel:BAAANQADCgcIDAABNQAECgcIDgAEAAAAAA==.Deathbyshock:BAAANQAECgcIDgAAAA==.Deathdan:BAAANQADCgEIAQAAAA==.Deathrollins:BAAANQAECgUICAAAAA==.Deathylad:BAAANQAECggIEAAAAA==.Delaror:BAAANQADCgYIBgAAAA==.Denadin:BAAANQAECgEIAgABNQAECgkJGgASAN0WAA==.Denari:BAAANQABCgMIBQAAAA==.Dennygrips:BAAANQADCggIDQABNQAECgkJGgASAN0WAA==.Dennyshotz:BAAANQAECgUIBQABNQAECgkJGgASAN0WAA==.Dennyshreds:BAABNQAECn8aAAISAAkK3RadKgCBAgASAAkK3RadKgCBAgAAAA==.Dennytotem:BAAANQAECgQIBwABNQAECgkJGgASAN0WAA==.Dennywarrior:BAAANQAECgcIBwABNQAECgkJGgASAN0WAA==.Denrukhan:BAACNQAFFH8TAAIUAAYK5x18AgA3AgAUAAYK5x18AgA3AgA1AAQKfyQAAxQACQorI70JACcDABQACQorI70JACcDABIAAQoAAAAAAAAAAAAA.Deschain:BAAANQAECgEIAQAAAA==.Dew:BAABNQAECn9CAAIDAAkKmyT+BQC5AwADAAkKmyT+BQC5AwAAAA==.',
Di='Didudye:BAAANQADCgMIAwABNQAECggIIAAeAAAWAA==.Diin:BAABNQAECn8bAAMXAAYK1wdDLQCPAAAYAAYK1wfzNwErAQAXAAQKjgNDLQCPAAAAAA==.',
Dk='Dklord:BAAANQAECgUIEAAAAA==.',
Do='Dolan:BAAANQADCgEIAQAAAA==.Donappletino:BAAANQAECgIIBAAAAA==.Donkedixlol:BAAANQADCgcICwAAAA==.Doobzers:BAAANQADCgMIAwABNQAECgYJDQAEAAAAAA==.Doxtorbrujo:BAABNQAECn8dAAIIAAkKJg0JewDuAQAIAAkKJg0JewDuAQABNQAECgkJKAAFAAshAA==.Doxtorele:BAABNQAECn8cAAIDAAkKQxN+TgA6AgADAAkKQxN+TgA6AgABNQAECgkJKAAFAAshAA==.Doxtormonje:BAAANQAECggIEQABNQAECgkJKAAFAAshAA==.Doxtoroso:BAAANQAECgUICQABNQAECgkJKAAFAAshAA==.Doxtorprote:BAABNQAECn8oAAIFAAkKCyGLBwAnAwAFAAkKCyGLBwAnAwAAAA==.Doxtorunholy:BAABNQAECn8bAAMOAAkKbxvFIACrAgAOAAkKbxvFIACrAgAPAAEKAADh7wAkAAABNQAECgkJKAAFAAshAA==.',
Dr='Draelgor:BAAANQADCgEJAQAAAA==.Dredd:BAAANQAECgIIAwAAAA==.Drunk:BAABNQAECn8nAAMRAAkKAQ/TGwDBAQARAAkKAQ/TGwDBAQAfAAMK5QoeUQCoAAAAAA==.',
Du='Duckpally:BAAANQABCgYIBgAAAA==.',
Dw='Dwarfussy:BAAANQAECgYICwAAAA==.Dwindle:BAAANQADCgUIBQABNQAECgcIHAAFAIIdAA==.',
Ea='Earthernheal:BAAANQAECgUIDQAAAA==.',
Ec='Eckshin:BAAANQAECgIIAgAAAA==.',
Ed='Edroffert:BAAANQADCgQIBAAAAA==.',
Eh='Ehonte:BAABNQAECn8qAAIKAAgKXBJrjgD0AQAKAAgKXBJrjgD0AQAAAA==.',
Ei='Eidolonn:BAAANQADCggIIAAAAA==.',
Ek='Ekkaia:BAABNQAECn8kAAIMAAgKOh/GOgC4AgAMAAgKOh/GOgC4AgAAAA==.',
El='Eleminohpee:BAAANQADCgMIAwABNQAECggIHQAYADMdAA==.Elfypriestly:BAAANQADCgUIBwAAAA==.Elsell:BAAANQAECgEJAQAAAA==.Elwasp:BAAANQAECgMIBQAAAA==.',
Em='Emptypockets:BAAANQADCgUICgAAAA==.',
En='Encana:BAABNQAECn8tAAIgAAkK2hQhCgA4AgAgAAkK2hQhCgA4AgAAAA==.Ender:BAAANQAECgIIAwAAAA==.',
Ep='Epiales:BAAANQADCgUIBQAAAA==.',
Er='Ericgb:BAABNQAECn8mAAMTAAgK/BIxHQCyAQATAAgK/BIxHQCyAQAQAAEKPAOnRgApAAAAAA==.Eronara:BAAANQADCgIIAgABNQAECgcIGwAVAFQeAA==.Errzza:BAAANQAECgUIDgAAAA==.Erutreya:BAAANQAECgUIBQAAAA==.Erzsébet:BAAANQAECgIJBQAAAA==.',
Es='Esha:BAAANQADCgYIHgAAAA==.',
Et='Etsubrew:BAABNQAECn8kAAIfAAkKdyK1BQBzAwAfAAkKdyK1BQBzAwAAAA==.Etsupriest:BAAANQAECggIEQAAAA==.',
Eu='Eula:BAAANQADCgYIEQAAAA==.',
Ev='Evelynn:BAABNQAECn8WAAIgAAcKaw+LFABgAQAgAAcKaw+LFABgAQAAAA==.Evoked:BAAANQAECgUICwABNQAECgcICwAEAAAAAA==.',
Ex='Exanimus:BAAANQADCgUJCAAAAA==.Exign:BAAANQADCgIIAgAAAA==.Exix:BAAANQAECgEIAQAAAA==.Exqui:BAABNQAECn8pAAMIAAgKaSJ9GQAeAwAIAAgKaSJ9GQAeAwAGAAEKkhfqbwA/AAAAAA==.',
Ez='Ezral:BAAANQAECgEJAQABNQAECgEIAQAEAAAAAA==.',
['Eí']='Eíko:BAABNQAECn8jAAIVAAkKNhmsOgB7AgAVAAkKNhmsOgB7AgAAAA==.',
Fa='Faeruh:BAAANQADCggICQAAAA==.Fafnar:BAAANQADCgcIDAABNQAECggIIwAMAN4cAA==.Fafnie:BAABNQAECn8aAAIDAAcKEQdongBWAQADAAcKEQdongBWAQAAAA==.',
Fe='Felath:BAABNQAECn8fAAIgAAgKIB2+BgCmAgAgAAgKIB2+BgCmAgAAAA==.Feldspar:BAABNQAECn8bAAIeAAgKnxa1TwAqAgAeAAgKnxa1TwAqAgAAAA==.Fennyk:BAAANQADCgYICwAAAA==.',
Fi='Fil:BAABNQAECn8hAAMfAAgKjx5eEgDGAgAfAAgKjx5eEgDGAgAhAAEKdQayMAA0AAAAAA==.Finalkill:BAAANQADCgYIBgAAAA==.Fishswife:BAAANQAECgYIEwAAAA==.Fissal:BAAANQADCgcIBwAAAA==.Fistoflurry:BAAANQADCgIIAgABNQAECgkJJwAJAFIiAA==.',
Fl='Flameviper:BAAANQAECgUICQAAAA==.Flompy:BAAANQADCgIIAgAAAA==.Floreil:BAAANQADCgYIEAAAAA==.',
Fo='Foofighter:BAAANQADCgIIAgAAAA==.Footoo:BAAANQAECgUICwAAAA==.Foxybrie:BAAANQABCgIIAgAAAA==.',
Fr='Friedchimkin:BAAANQADCggIGAAAAA==.Frort:BAAANQAECgIIAgAAAA==.',
Fu='Fuknord:BAAANQADCgYIBwAAAA==.Fulva:BAAANQADCgcIBgAAAA==.',
Fy='Fyneep:BAABNQAECn8iAAIYAAkKkxk/UQDeAgAYAAkKkxk/UQDeAgAAAA==.Fynne:BAABNQAECn8uAAIVAAkKChZqPQBxAgAVAAkKChZqPQBxAgAAAA==.',
Ga='Gaiusmohiam:BAAANQABCgUIBQAAAA==.Galadriell:BAAANQADCgcIDgAAAA==.Galdademon:BAAANQAECgUIBQAAAA==.Galiophobia:BAAANQAECgIIAgAAAA==.Galm:BAAANQADCggIFwAAAA==.Garrethul:BAAANQAECgMIBgAAAA==.Gawleywood:BAAANQAECgUIDgAAAA==.',
Ge='Gellidus:BAABNQAECn8YAAMiAAcKnwpHEAAxAQAiAAcKaQlHEAAxAQANAAUKjQgzLAC9AAAAAA==.Genhooves:BAEANQADCgYJCwABNQAECgkJLwAYABsaAA==.Gensisd:BAABNQAECn8iAAIDAAgKgx1VMgCtAgADAAgKgx1VMgCtAgAAAA==.Gentledh:BAAANQAECgUIDQAAAA==.Gentleshadow:BAAANQAECgUICQAAAA==.Gerulf:BAAANQABCgQIBAAAAA==.',
Gh='Ghosteagle:BAAANQADCgQIBAAAAA==.Ghostvoid:BAAANQABCgYICgAAAA==.',
Gn='Gnomejodas:BAAANQAECgEIAQAAAA==.',
Go='Goatedslurp:BAAANQAFFAEIAQABNQAFFAQICQAWAHkcAA==.Gobfather:BAAANQADCgcIEgAAAA==.Goldcity:BAABNQAFFH8MAAILAAUKGhKSBwCNAQALAAUKGhKSBwCNAQAAAA==.Goodfaith:BAAANQAECgUICAAAAA==.Goofy:BAACNQAFFH8TAAIKAAYKsSF6CAAoAgAKAAYKsSF6CAAoAgA1AAQKfx4AAgoACQqUJDkcAEUDAAoACQqUJDkcAEUDAAE1AAUUAggBAAQAAAAA.Gotha:BAAANQADCgEIAQABNQAECgcIHgAKAFoXAA==.',
Gr='Grandgooner:BAAANQAECgQIBAABNQAECgQIBwAEAAAAAA==.Grimlocke:BAAANQAECgcIDwAAAA==.Grimsolo:BAAANQAECgMIAwABNQAECgcIDwAEAAAAAA==.Gromit:BAAANQAECgcIEgAAAA==.Grovecaller:BAAANQADCgUICAABNQAECggIIAAdACAXAA==.',
Gu='Gubber:BAAANQADCgIIAQAAAA==.',
Gw='Gwyndolin:BAAANQAECgUIDgAAAA==.Gwynne:BAAANQAECgUIDwAAAA==.',
Ha='Hacrox:BAAANQAECgUIBwAAAA==.Halanad:BAAANQAECgMIBQAAAA==.Halfmoons:BAABNQAECn8kAAIVAAkKORtqJgDPAgAVAAkKORtqJgDPAgAAAA==.Halfsumo:BAABNQAECn8XAAIOAAYKxBFAcgAoAQAOAAYKxBFAcgAoAQAAAA==.Halobender:BAAANQAECgIIAgAAAA==.Harmhárm:BAAANQADCgUIBwAAAA==.Harrol:BAAANQAECgcIDwABNQAECgQIBAAEAAAAAA==.Hassindiir:BAABNQAECn8rAAITAAkKGgd2KQBGAQATAAkKGgd2KQBGAQAAAA==.Hawgelf:BAABNQAECn8ZAAIMAAgKUgbcrQCkAQAMAAgKUgbcrQCkAQAAAA==.Hawmahcide:BAAANQAECgcIDAAAAA==.Hayles:BAAANQAECgUIDgAAAA==.',
He='Helathra:BAAANQAECgcIEAAAAA==.Helliona:BAAANQAECgUIBQAAAA==.Hellraizer:BAAANQAECgQIBwAAAA==.Herhunter:BAAANQAECgQIBAABNQAECgQICAAEAAAAAA==.Hermonk:BAAANQAECgQICAAAAA==.',
Hi='Hiiru:BAAANQADCgcIBwABNQAECgkJJwAJAEsgAA==.Hishunter:BAAANQAECgcIDgABNQAFFAUICQASAGUiAA==.',
Ho='Hofin:BAAANQAECgcIEQAAAA==.Holybound:BAAANQADCgIIAgAAAA==.',
Hu='Huntarr:BAABNQAECn8XAAIBAAgKRxgVgAAkAgABAAgKRxgVgAAkAgAAAA==.Hunterdamon:BAABNQAECn8oAAMLAAgKdBDYKQDwAQALAAgKdBDYKQDwAQAgAAIKzAoSKgBeAAAAAA==.',
Hy='Hycinna:BAAANQAECgIIAgAAAQ==.Hydrazashen:BAAANQAECgIIAwAAAA==.',
['Hà']='Hàou:BAAANQADCggIIQAAAA==.',
Ia='Iamafish:BAABNQAECn8gAAIMAAgKghRjXQBbAgAMAAgKghRjXQBbAgAAAA==.Iamgroott:BAAANQADCgMIAwAAAA==.',
Ic='Ichimaru:BAAANQAECgYIBgAAAA==.',
Ig='Igotyou:BAABNQAECn8fAAIVAAcK+xU7bADVAQAVAAcK+xU7bADVAQAAAA==.',
In='Insidae:BAABNQAECn8pAAMjAAkKLhfzHgCEAgAjAAkKLhfzHgCEAgAkAAEKowADWAAVAAAAAA==.',
Ir='Ironpunch:BAAANQADCggICQAAAA==.',
Is='Ismirea:BAAANQAECgQIBwAAAA==.Isoldella:BAAANQADCgcICAAAAA==.',
Iz='Izuna:BAAANQADCgUIBQAAAA==.',
Ja='Jakedo:BAAANQABCgYIBAAAAA==.Jalencarter:BAAANQAECgUICQAAAA==.Jamirprote:BAABNQAECn8ZAAIFAAgKJxzaEACPAgAFAAgKJxzaEACPAgAAAA==.Jantasir:BAAANQAECgUIEgAAAA==.Jasaryia:BAAANQADCgUICQAAAA==.Javalyn:BAAANQAECgUIDgAAAA==.Jazzymage:BAAANQADCgcIBwAAAA==.',
Ji='Jin:BAABNQAECn8aAAIKAAkKUhvjPgDLAgAKAAkKUhvjPgDLAgABNQAFFAYIDgAdAB0dAA==.Jinda:BAAANQADCgcIIAAAAA==.Jirachi:BAABNQAECn8eAAMeAAgKJR2VLQCuAgAeAAgKJR2VLQCuAgABAAEKZwkZmgE3AAABNQAFFAUIHAAWAF4dAA==.Jiujitsu:BAABNQAECn8XAAMjAAgK/gUDTwB9AQAjAAgK/gUDTwB9AQAkAAQKJgIdRQCHAAAAAA==.',
Jo='Jobergas:BAAANQAECgUICQAAAA==.Jobi:BAAANQAECgMIBAAAAA==.Johallas:BAABNQAECn8kAAIXAAgKOR2hBgCQAgAXAAgKOR2hBgCQAgAAAA==.',
Ju='Judzia:BAAANQAECgMIAwAAAA==.Juf:BAABNQAECn8lAAMVAAgK7g4JcADJAQAVAAgK7g4JcADJAQAWAAEKAADWjgAZAAAAAA==.Jufster:BAAANQADCggICwAAAA==.Jumpingbear:BAACNQAFFH8TAAIQAAUK3BEpAQCqAQAQAAUK3BEpAQCqAQA1AAQKfzAAAxAACQqqIrkEADoDABAACQqqIrkEADoDABIAAgpyFv6UAH4AAAAA.Justdeadfred:BAAANQADCggICAAAAA==.',
Ka='Kagar:BAAANQADCgYIDQAAAA==.Kaho:BAAANQAECgUICQAAAA==.Kainazzo:BAAANQAECgUIBgAAAA==.Kaladorn:BAAANQAECgQIBwAAAA==.Kaladïn:BAAANQADCgUIBQABNQAECgMIBgAEAAAAAA==.Kalda:BAAANQAECgYIEQABNQAECgkJKAAVAF0dAA==.Kalikali:BAAANQADCgcIBwABNQAECgQIBgAEAAAAAA==.Kallisto:BAAANQAECgUIEgAAAA==.Kamiarashi:BAAANQADCggICgAAAA==.Karabethe:BAEANQAECgIIAQAAAA==.Kattizzi:BAAANQADCgMIAwAAAA==.Kazuhiro:BAACNQAFFH8SAAIKAAYKNhwTCAAyAgAKAAYKNhwTCAAyAgA1AAQKfy0AAwoACQqpJrIEANADAAoACQqLJrIEANADAAkAAgr6JR8sANEAAAAA.',
Ke='Keadath:BAAANQADCgcIBwAAAA==.Keagan:BAAANQAECgUICgAAAA==.Kehzai:BAABNQAECn8vAAIPAAcKjg0rXwCPAQAPAAcKjg0rXwCPAQAAAA==.Kelric:BAAANQADCgUIBQAAAA==.Kenpomaster:BAAANQAECgUIBwAAAA==.Keyalastus:BAAANQADCgQIBAAAAA==.',
Kh='Khaluha:BAAANQAECgUICAAAAA==.Khaymaan:BAAANQAECgUIEQAAAA==.',
Ki='Killios:BAAANQAECgMIAwAAAA==.Kilmeawden:BAABNQAECn8lAAQIAAkKSSHaGgAYAwAIAAgKyCDaGgAYAwAHAAcKGBiSBwAfAgAGAAEK/RlKagBLAAAAAA==.',
Ko='Kozal:BAAANQADCgcIBwAAAA==.',
Kr='Krionys:BAAANQADCgEIAQAAAA==.Krisha:BAABNQAECn8hAAIDAAkKJhK8UwAnAgADAAkKJhK8UwAnAgAAAA==.Krisphobos:BAABNQAECn8bAAIMAAgKtRGNcQArAgAMAAgKtRGNcQArAgAAAA==.',
Ku='Kubael:BAAANQAECgEIAQAAAA==.Kuesham:BAAANQADCgUJBAABNQAECgEIAQAEAAAAAA==.Kulgutbuster:BAABNQAECn8rAAIMAAgKVx9vOAC+AgAMAAgKVx9vOAC+AgAAAA==.Kungpow:BAABNQAECn8gAAIfAAgKCSFKDwDsAgAfAAgKCSFKDwDsAgAAAA==.Kupdor:BAABNQAECn8YAAMWAAYKQBDZNwBiAQAWAAYKQBDZNwBiAQAVAAYKnQtkpQAgAQABNQAECgcIDwAEAAAAAA==.Kuromatsu:BAABNQAECn8dAAIUAAcKmx7BGwBVAgAUAAcKmx7BGwBVAgAAAA==.Kurtrus:BAAANQADCgQIBAAAAA==.',
['Kÿ']='Kÿt:BAAANQAECgYIEgAAAA==.',
La='Lacedon:BAABNQAECn8bAAIKAAgKCw93kADuAQAKAAgKCw93kADuAQAAAA==.Lantank:BAAANQABCgIIAgAAAA==.Larceny:BAAANQAECgYICAAAAA==.Larfleeze:BAAANQADCgYIBgAAAA==.Larryy:BAAANQADCgcIBwAAAA==.Layliah:BAACNQAFFH8SAAISAAYK1RpRBQBHAgASAAYK1RpRBQBHAgA1AAQKfzIAAhIACQrDJSIEALwDABIACQrDJSIEALwDAAAA.',
Le='Leiania:BAAANQADCgUIBQABNQAECgkJMgAPAIkdAA==.Lewis:BAAANQADCggICAAAAA==.',
Li='Lild:BAAANQADCgYICQAAAA==.Lilgup:BAAANQAECggIDQAAAA==.Linadrea:BAAANQADCggIDgAAAA==.Linedaleiris:BAAANQADCggIDwAAAA==.Liqudblu:BAAANQAECgQIEQAAAA==.Liqudfury:BAAANQADCggIEQAAAA==.Lishan:BAAANQAECgQIBAAAAA==.Liszandera:BAAANQAECgQIBQAAAA==.Literein:BAABNQAECn8gAAIeAAgKABaUUAAmAgAeAAgKABaUUAAmAgAAAA==.Lizora:BAAANQAECgYICgAAAA==.',
Lo='Lokisan:BAAANQADCgMIAwAAAA==.Lorenei:BAABNQAECn8aAAMaAAgKGyBMHACkAgAaAAgKGyBMHACkAgAPAAEKAADa4AAwAAAAAA==.Los:BAAANQAECgUIDQAAAA==.',
Lt='Ltthunder:BAAANQADCggICQAAAA==.Ltwhisker:BAAANQAECgYIDAAAAA==.',
Lu='Lucìd:BAAANQADCggIEAAAAA==.Lucïd:BAABNQAECn8aAAIFAAgK/RZ/GAAxAgAFAAgK/RZ/GAAxAgAAAA==.Lunhzae:BAAANQADCgUIBQAAAA==.Lustallo:BAAANQAECgIIAgAAAA==.',
Ly='Lynxx:BAAANQAECgYIEAAAAA==.',
Ma='Macharth:BAAANQAECgUICQAAAA==.Mack:BAAANQAECgcIDwAAAA==.Mad:BAABNQAECn8jAAMRAAgKjyN/DAC4AgARAAcKEiN/DAC4AgAfAAEKtwZHcQAmAAAAAA==.Madchickenz:BAABNQAECn8aAAISAAYKex2/OwATAgASAAYKex2/OwATAgAAAA==.Magicwithin:BAAANQAECgcIJAAAAQ==.Magut:BAAANQADCgUICAAAAA==.Maira:BAAANQADCgYIFgAAAA==.Maitias:BAAANQADCgUIBQABNQADCggIDgAEAAAAAA==.Majim:BAABNQAECn8YAAIMAAcKaRH/kwDdAQAMAAcKaRH/kwDdAQAAAA==.Malevolens:BAAANQAECgUIBwAAAA==.Mannyfingers:BAAANQADCgUIBQAAAA==.Marche:BAABNQAECn8sAAIIAAgKtxYOXQA8AgAIAAgKtxYOXQA8AgAAAA==.Marianacross:BAABNQAECn8XAAIVAAcK2R5KPQByAgAVAAcK2R5KPQByAgAAAA==.Marsel:BAAANQADCgYIBgAAAA==.Masokist:BAAANQADCgYIBgAAAA==.Mavdk:BAAANQADCggIDgABNQAECgQICAAEAAAAAA==.Mavrar:BAAANQAECgQICAAAAA==.',
Mc='Mcflurrey:BAAANQAECgQIEQAAAA==.',
Me='Mechamana:BAAANQADCgYIBgABNQADCggIBQAEAAAAAA==.Meing:BAAANQAECgEIAQAAAA==.Melodrama:BAAANQADCgIIAgAAAA==.Meowrian:BAAANQAECgMIAwAAAA==.Mephïsto:BAAANQAECgEIAQAAAA==.Mereoleona:BAABNQAECn8bAAIYAAkKLxKpoQA9AgAYAAkKLxKpoQA9AgAAAA==.Messdupjuf:BAAANQADCggJCAABNQAECggINgAMAOAmAA==.Messdupllama:BAABNQAECn82AAIMAAgK4CbcBgCmAwAMAAgK4CbcBgCmAwAAAA==.Metamorfasis:BAABNQAECn8hAAIQAAgK/g6EFACvAQAQAAgK/g6EFACvAQAAAA==.',
Mi='Micos:BAAANQAECgQIBgAAAA==.Microburst:BAABNQAECn8dAAIYAAgKMx08iQBsAgAYAAgKMx08iQBsAgAAAA==.Microcharge:BAAANQADCgUIBQABNQAECggIHQAYADMdAA==.Miischief:BAAANQAECgUIDgAAAA==.Milkman:BAAANQADCggIFAAAAA==.Misslynn:BAAANQAECgQIBQAAAA==.Missmoodý:BAAANQAECgIIAwAAAA==.Missqwerty:BAAANQAECggICQAAAA==.Mistya:BAAANQADCgcIBwAAAA==.Mizari:BAAANQABCgEIAQAAAA==.',
Mo='Moltenbeast:BAAANQAECggIDQAAAA==.Mongargiss:BAAANQAECgMIBwAAAA==.Mongoth:BAAANQAECgMIBQAAAA==.Montaro:BAAANQAECgUIDgAAAA==.Morbidi:BAAANQAECgQIBwAAAA==.Moreithe:BAAANQADCggICAAAAA==.Mortand:BAAANQABCgIIAgAAAA==.Mortharos:BAAANQAECgMIBQAAAA==.',
Mu='Mudkip:BAACNQAFFH8cAAIWAAUKXh0CBgDEAQAWAAUKXh0CBgDEAQA1AAQKfzoAAxYACQoYJRECAMADABYACQoYJRECAMADABkAAQqBDu4pAC8AAAAA.Munnsta:BAABNQAECn8YAAIcAAcKShAdNgCZAQAcAAcKShAdNgCZAQAAAA==.Muskan:BAAANQAECgEIAgAAAA==.',
My='Mylanara:BAABNQAECn8sAAIbAAgKqxwOBgCwAgAbAAgKqxwOBgCwAgAAAA==.Mysticah:BAAANQAECgUIDAAAAA==.Mythalagos:BAAANQADCgEIAQAAAA==.Mythblast:BAAANQAECgEJAgAAAA==.Myvrth:BAAANQAECgEIAQAAAA==.',
['Mä']='Märs:BAACNQAFFH8JAAISAAUKZSIADACoAQASAAUKZSIADACoAQA1AAQKfzYAAhIACQq+I9sHAJADABIACQq+I9sHAJADAAAA.',
Na='Nacholibre:BAAANQAECgIIAgAAAA==.Naelu:BAAANQADCgMIAwAAAA==.Nanr:BAABNQAECn8sAAQSAAgKOhH5SQC7AQASAAcKahL5SQC7AQAUAAUK8RPQPQAwAQATAAMKLArBSACCAAAAAA==.Nathi:BAAANQAECgMIBQAAAA==.Navori:BAACNQAFFH8RAAIfAAYKhA4MBgCrAQAfAAYKhA4MBgCrAQA1AAQKfx4AAh8ACAoWHCYgACkCAB8ACAoWHCYgACkCAAAA.Nazeera:BAEANQADCggIFwABNQAECgMIBQAEAAAAAA==.Nazeraz:BAABNQAECn8bAAIiAAcKfQLOFADeAAAiAAcKfQLOFADeAAAAAA==.',
Ne='Necrokinesis:BAAANQAECgEJAQAAAA==.Nerve:BAABNQAECn8eAAIYAAkKExEJpAA4AgAYAAkKExEJpAA4AgAAAA==.Nesiryn:BAAANQADCgYIEAAAAA==.Neth:BAAANQAECgcIDgAAAA==.Neuroshots:BAAANQAECgUIEAAAAA==.Newkers:BAAANQADCgUICQAAAA==.',
Ni='Nightknight:BAAANQADCgQIBwAAAA==.Nightràven:BAABNQAECn8rAAMlAAgKmxRzBwD6AQAlAAcKXxVzBwD6AQAMAAUKMg4c7QAiAQAAAA==.Nijitani:BAAANQADCgcIFAAAAA==.Nimrodd:BAAANQAECgQIBQAAAA==.',
No='Nobby:BAAANQADCgUICgAAAA==.Noogan:BAAANQADCgYIBgAAAA==.Nosferatü:BAAANQADCgUJBQAAAA==.Nothotdog:BAAANQADCgIIAgAAAA==.Novacat:BAABNQAECn8rAAIUAAkKBiGaCAA4AwAUAAkKBiGaCAA4AwAAAA==.Novangel:BAAANQADCgYIBgAAAA==.November:BAABNQAECn8XAAIXAAYKFQ0fGQArAQAXAAYKFQ0fGQArAQAAAA==.Nox:BAAANQADCggIDAAAAA==.',
Nu='Nubriss:BAABNQAECn8XAAITAAgK0BWIFgD8AQATAAgK0BWIFgD8AQAAAA==.Nudetayne:BAAANQADCgQJBAAAAA==.Nuitsguard:BAABNQAECn80AAQCAAkKxBsUMACfAgACAAkKxBsUMACfAgAdAAUK1AyRIwAcAQADAAIKAADNDgFnAAAAAA==.Nunnaly:BAAANQAECgcIEgAAAA==.',
Ny='Nyaboron:BAABNQAECn8gAAIeAAkK1RruKADCAgAeAAkK1RruKADCAgAAAA==.Nykira:BAAANQABCgIIAgAAAA==.Nyv:BAAANQADCggICAABNQAECgQIBAAEAAAAAA==.',
['Nè']='Nèaner:BAABNQAECn8rAAIVAAkKBhHUTAA7AgAVAAkKBhHUTAA7AgAAAA==.',
Og='Oggden:BAABNQAECn8aAAIdAAcKdQdDHgB3AQAdAAcKdQdDHgB3AQAAAA==.Ogrebane:BAABNQAECn8YAAIkAAcK4gdIKQB2AQAkAAcK4gdIKQB2AQAAAA==.',
Oi='Oiheg:BAABNQAECn8rAAIJAAgKPiB6BwDgAgAJAAgKPiB6BwDgAgAAAA==.',
Or='Oriha:BAAANQADCgYIBgAAAA==.',
Pa='Pajamasniper:BAAANQAECgQICAAAAA==.Pantheon:BAAANQAECgcIEAAAAA==.Parttimebear:BAAANQADCgEIAQABNQAECggIJAACAAIlAA==.',
Pe='Peach:BAABNQAECn8iAAIeAAcKqCSLIQDlAgAeAAcKqCSLIQDlAgAAAA==.Peppermint:BAAANQADCggIDwAAAA==.Perlita:BAAANQADCgQJBAAAAA==.',
Ph='Phoephoe:BAAANQADCgMIAwABNQAECgcIGwAVAFQeAA==.Photos:BAABNQAECn8fAAIeAAcKNSSTIwDbAgAeAAcKNSSTIwDbAgAAAA==.',
Pi='Pigums:BAABNQAECn8kAAICAAgKAiXpDQBQAwACAAgKAiXpDQBQAwAAAA==.Pilupi:BAAANQAECggICAAAAA==.Pixie:BAAANQADCgcIDQAAAA==.',
Pl='Plugbae:BAAANQADCgMIAwAAAA==.Pluug:BAABNQAECn8dAAMXAAkK+RvTAwD8AgAXAAkK2xvTAwD8AgAYAAcKcw4XAwGFAQAAAA==.',
Po='Poleo:BAAANQADCggICAAAAA==.',
Pr='Prayer:BAABNQAECn8pAAMBAAgKMCatEwB2AwABAAgKMCatEwB2AwAeAAEKtRUkHAE2AAABNQADCgcIBwAEAAAAAA==.Prayered:BAAANQAECgcICwAAAA==.Prete:BAAANQAECggICAAAAA==.Prîde:BAAANQADCgYIBwAAAA==.',
Ps='Psycopath:BAABNQAECn8jAAILAAgKsR+VDQAKAwALAAgKsR+VDQAKAwAAAA==.Psygn:BAAANQADCgUIBQABNQAECgcIIgAOAHYjAA==.Psyloc:BAAANQADCggIHQABNQAECgcIIgAOAHYjAA==.',
Pt='Ptra:BAACNQAFFH8GAAISAAIK/AwZHwCWAAASAAIK/AwZHwCWAAA1AAQKfxwAAhIABwpjG/k0AD4CABIABwpjG/k0AD4CAAE1AAUUBAgHABIAgxMA.',
Pu='Puddingfarts:BAAANQAECgMIAwAAAA==.Pumpy:BAACNQAFFH8QAAIDAAYKOx/cBQAdAgADAAYKOx/cBQAdAgA1AAQKfyQAAgMACQrWJH4RAGEDAAMACQrWJH4RAGEDAAAA.Purrfessor:BAAANQADCggIEQAAAA==.Purrpally:BAAANQADCggIGQAAAA==.',
Py='Pywacket:BAABNQAECn8XAAIVAAcKrwKtrwACAQAVAAcKrwKtrwACAQAAAA==.',
['Pã']='Pãlàdoom:BAAANQADCgUIDgABNQAECggIKwAlAJsUAA==.',
Qa='Qadésh:BAAANQABCgYICAABNQADCgUIBQAEAAAAAA==.',
Qu='Quendwings:BAEANQAECgUIBQABNQAFFAcIFQAUAFIaAA==.',
Ra='Rabern:BAAANQADCgIIAgAAAA==.Ragnaclio:BAAANQADCgIJAgAAAA==.Rainsky:BAAANQAECgQIAwAAAA==.Ralat:BAAANQADCgYIBgAAAA==.Rasmatazz:BAAANQAECgEIAQAAAA==.Rayleighh:BAAANQAECgYIEAABNQAECgcIDwAEAAAAAA==.',
Re='Redemptio:BAABNQAECn8VAAQeAAgKgQ0RiQB9AQAeAAcKggwRiQB9AQABAAUKlQudHQHnAAAFAAEKbxN9bgAxAAAAAA==.Relerin:BAAANQADCgIIAgAAAA==.Rexxcat:BAAANQAECgQIBAAAAA==.',
Ri='Rikaza:BAAANQADCgcIBgAAAA==.Ristraza:BAAANQADCgIIAgABNQAECgMJBwAEAAAAAA==.',
Ro='Roguewølf:BAAANQADCgQIBgAAAA==.Roono:BAAANQADCgcICgAAAA==.Rosalidia:BAAANQAECgQIDgAAAA==.Rosephane:BAAANQADCgUIBQAAAA==.Ross:BAAANQAECgMIBAAAAA==.Rossco:BAAANQAECgEIAQABNQAECgMIBAAEAAAAAA==.Rozoe:BAAANQAECgcIDAAAAA==.Rozzluz:BAAANQAECgYICwAAAA==.',
Ru='Rutira:BAABNQAECn8nAAImAAgKUCRjDgAvAwAmAAgKUCRjDgAvAwAAAA==.',
Ry='Ryân:BAAANQADCgMIAwAAAA==.',
['Rê']='Rêcklêss:BAAANQADCgUICAABNQAECggIKwAlAJsUAA==.',
Sa='Sabbat:BAAANQADCggIEwAAAA==.Salder:BAAANQADCggIFQAAAA==.Sapphiwrath:BAAANQADCgYIFAAAAA==.',
Sc='Scuuzemee:BAAANQAECgYIDwAAAA==.',
Se='Seacow:BAAANQAECgYIDAAAAA==.Searilus:BAAANQAECgUIDgAAAA==.Seethed:BAAANQADCgUJCgAAAA==.Seylena:BAAANQADCggILwABNQAECgcIIgAfAD4PAA==.',
Sh='Shadowcrit:BAAANQAECgUICgAAAA==.Shamamma:BAAANQADCgYIDQAAAA==.Shammallamma:BAAANQABCgQIBgAAAA==.Shamæn:BAAANQAECgUICgAAAA==.Shaphyr:BAAANQAECgUIDgABNQAECgYIGgASAHsdAA==.Sharphammer:BAAANQAECgIIAwAAAA==.Shieldon:BAAANQADCgUIBQABNQAECgcIHQAUAJseAA==.Shieldud:BAAANQAECgEIAQAAAA==.Shikamarú:BAAANQADCgEIAQAAAA==.Shinhealer:BAAANQAECgEIAQAAAA==.Shiroa:BAAANQAECgIIAwABNQAECgIJBQAEAAAAAA==.Shlapp:BAAANQADCgUJBQAAAA==.Shootsahlot:BAAANQAECgMICAAAAA==.',
Si='Sidapa:BAAANQAECgIIAgAAAA==.Silvernleaf:BAAANQAECgIIAwAAAA==.Sinai:BAABNQAECn8hAAIUAAgK0gvKMwB3AQAUAAgK0gvKMwB3AQAAAA==.Sindir:BAAANQADCgUIBQABNQAFFAYIEwAUAOcdAA==.Sinner:BAAANQAECgUIBQABNQAECgYICAAEAAAAAA==.Siyx:BAAANQAECgQIDAAAAA==.',
Sk='Skept:BAABNQAECn8gAAMkAAkKVxZADQCfAgAkAAkKVxZADQCfAgAjAAIKPAxNjQBxAAAAAA==.',
Sl='Slacky:BAAANQABCggICgAAAA==.Sleêp:BAAANQAECgUIDwAAAA==.Slosh:BAABNQAECn8qAAMCAAkKXyNlCQB1AwACAAkKXyNlCQB1AwADAAIKnwbuEwFfAAAAAA==.',
Sm='Smellyandfat:BAECNQAFFH8VAAMUAAcKUhqrAQBfAgAUAAcKUhqrAQBfAgASAAUKogf9FAAWAQA1AAQKfzYAAxQACQoxJeECAJsDABQACQoxJeECAJsDABIACQpcIDobAOwCAAAA.Smerffy:BAABNQAECn8cAAQCAAcKYBWAbgC8AQACAAcKYBWAbgC8AQADAAMKGwJGCAF0AAAdAAEKzwHuOQAkAAAAAA==.Smites:BAAANQAECgUIBQABNQAECgcIIAABADUkAA==.',
So='Soiled:BAAANQAECgIIAgAAAA==.Solise:BAAANQAECggIEwAAAA==.Somehobo:BAAANQADCgIIAgAAAA==.Sonny:BAABNQAECn8lAAMXAAgK9x4bCABhAgAXAAcK9x4bCABhAgAYAAYKxBBgFQFlAQAAAA==.Sorshalynne:BAAANQAECgUICQAAAA==.Soulhorror:BAABNQAECn8kAAIPAAgKDR38MwBYAgAPAAgKDR38MwBYAgAAAA==.Sourcha:BAAANQAECgIIAgAAAA==.',
Sp='Spiritfire:BAAANQAECgQIEQAAAA==.Spitefury:BAAANQAECgcIEgABNQAECggIJAARABATAA==.Spriggs:BAEBNQAECn8vAAIYAAkKGxo5SQDwAgAYAAkKGxo5SQDwAgAAAA==.',
St='Starrfighter:BAAANQAECgcIDAABNQAECgkJNAACAMQbAA==.Stepfather:BAAANQAECgQIBAAAAA==.Stepmother:BAAANQAECgQIBAAAAA==.Stillblade:BAAANQADCggIBQAAAA==.Stonedread:BAAANQAECgIIAgAAAA==.Stormfodder:BAAANQABCgQIBAAAAA==.Stronker:BAAANQADCggICgAAAA==.',
Su='Sungmi:BAABNQAECn8bAAMCAAgKBRtdQwBQAgACAAgKBRtdQwBQAgADAAMKuBXx6wC4AAAAAA==.Sunntzu:BAABNQAECn8jAAMhAAkKSx/uBQD1AgAhAAkKSx/uBQD1AgAfAAIKXw0lXABsAAAAAA==.',
Sw='Swindlle:BAABNQAECn8cAAIFAAcKgh3AFwA5AgAFAAcKgh3AFwA5AgAAAA==.',
Sy='Syber:BAABNQAECn8uAAMUAAkK7BtWDgDpAgAUAAkK7BtWDgDpAgASAAkKShL1NwAqAgAAAA==.Syberfist:BAAANQABCgQIBAABNQAECgkJLgAUAOwbAA==.Syberstyx:BAAANQADCggICQABNQAECgkJLgAUAOwbAA==.Sylvanxs:BAAANQADCgEIAQAAAA==.Sympathy:BAAANQAECgQICQAAAA==.Symphonica:BAABNQAECn8iAAIjAAkKThTnJQBYAgAjAAkKThTnJQBYAgAAAA==.Syreithis:BAAANQAECgUIDwAAAA==.',
['Sí']='Síd:BAABNQAECn8nAAMjAAgKNhqnJQBaAgAjAAgKNhqnJQBaAgAkAAUKmQswNQAKAQAAAA==.',
Ta='Tacofighter:BAABNQAECn8eAAMPAAcKZAv8dABAAQAPAAcKOAv8dABAAQAOAAYK9ATphADlAAAAAA==.Taerielle:BAACNQAFFH8GAAIXAAMK7ghEBADPAAAXAAMK7ghEBADPAAA1AAQKfzgAAhcACQqjHDsEAO0CABcACQqjHDsEAO0CAAAA.Tageren:BAAANQADCgYIEAAAAA==.Taldim:BAAANQADCggIDQABNQAECgcIIgAOAHYjAA==.Tarhos:BAAANQABCgIIBgAAAA==.Tarò:BAACNQAFFH8FAAIVAAIK2gMhLACCAAAVAAIK2gMhLACCAAA1AAQKfy4AAhUACQoqDEJuAM4BABUACQoqDEJuAM4BAAAA.Taychi:BAAANQAECgIIAgABNQAECggIGAALAFcSAA==.',
Te='Teacupps:BAACNQAFFH8OAAQGAAYKiBQnCACyAAAIAAMKcw3KIwDjAAAGAAIKnRsnCACyAAAHAAEKAACgDQBJAAA1AAQKfyQAAwYACQpzHyYVAMMBAAgABwr0HlhvAA0CAAYABwoQFyYVAMMBAAAA.Teegan:BAAANQAECgcIEQABNQAECggIJwAWAD8bAA==.Tekloa:BAAANQADCgYIBgAAAA==.Telvissra:BAABNQAECn8yAAIPAAkKiR1ZFAAUAwAPAAkKiR1ZFAAUAwAAAA==.Temporary:BAAANQAECgEIAQAAAA==.Teoritta:BAABNQAECn8eAAQIAAkKWRgsOgCiAgAIAAkKIBcsOgCiAgAGAAMKkRGdQwC1AAAHAAEKAAB+LAA8AAAAAA==.Terrisher:BAABNQAECn8hAAIBAAgKzQkrvgCaAQABAAgKzQkrvgCaAQAAAA==.',
Th='Thaljadrak:BAAANQADCgQIBwAAAA==.Thermopalea:BAAANQADCggIEgAAAA==.Thetamoon:BAABNQAECn8jAAMMAAgK3hwFSQCPAgAMAAgK3hwFSQCPAgAcAAMK+AgdawB8AAAAAA==.Thorald:BAABNQAECn8UAAIKAAcKBgQO7gD/AAAKAAcKBgQO7gD/AAAAAA==.Thordh:BAAANQAECggIEwAAAA==.Thorggon:BAABNQAECn8nAAMJAAkKUiLcAgB8AwAJAAkKUiLcAgB8AwAKAAEKiBZyQwFCAAAAAA==.Thornbeast:BAAANQAECgQIBgAAAA==.Thuato:BAAANQAECgIIAgAAAA==.Thundermayne:BAAANQAECgQIBwAAAA==.Thád:BAABNQAECn8eAAITAAgKmx+BCQDZAgATAAgKmx+BCQDZAgAAAA==.',
To='Tojara:BAAANQAECgYICwAAAA==.Toxique:BAAANQAECgUICQAAAA==.',
Tr='Trappist:BAAANQADCgMIAwAAAA==.Travelocitee:BAAANQAECgYIDgAAAA==.Triskalyn:BAAANQAECgEJAQAAAA==.Trojanhorse:BAAANQADCggIIAAAAA==.Trokosan:BAAANQAECgQIBwAAAA==.Trustissues:BAAANQADCggIFgAAAA==.Try:BAACNQAFFH8OAAIdAAYKHR1fAQAQAgAdAAYKHR1fAQAQAgA1AAQKfycAAh0ACQppJiIDAG4DAB0ACQppJiIDAG4DAAAA.Trybu:BAACNQAFFH8LAAIYAAUK+BIOHQCTAQAYAAUK+BIOHQCTAQA1AAQKf0EAAhgACQqmI2sSAIkDABgACQqmI2sSAIkDAAAA.Tryiss:BAAANQAECgUIBwAAAA==.',
Tt='Ttryss:BAAANQADCgUIBQAAAA==.',
Tu='Tubslumpkin:BAAANQAECgIIAgAAAA==.Tuketu:BAABNQAECn8tAAISAAkKCRC8OwATAgASAAkKCRC8OwATAgAAAA==.Turtlelord:BAABNQAECn8pAAIIAAgKtxXgbQARAgAIAAgKtxXgbQARAgAAAA==.',
Ty='Tylarion:BAAANQAECgQIBAAAAA==.Tylendal:BAABNQAECn8lAAINAAkKyhlMCgDHAgANAAkKyhlMCgDHAgAAAA==.Tylenolz:BAAANQAECgcIEwAAAA==.Tylenulz:BAAANQAECgYIEwAAAA==.Tylheras:BAAANQAECgcIDAAAAA==.Tyliera:BAAANQADCgcICAAAAA==.Tylren:BAAANQAECgMIAwAAAA==.',
['Tà']='Tànya:BAAANQAECgUIDQAAAA==.',
Un='Undbaxi:BAAANQADCgUICgAAAA==.Unfàthømable:BAAANQADCggICAABNQAECggIKwAlAJsUAA==.',
Ut='Uthercito:BAAANQADCggICQAAAA==.',
Uz='Uzen:BAAANQAECgYICQAAAA==.',
Va='Vallarath:BAABNQAECn8cAAIBAAgK+xavewAvAgABAAgK+xavewAvAgAAAA==.Valtaran:BAAANQAECgUICAAAAA==.Valtarr:BAABNQAECn8kAAIMAAgKHxSnZQBHAgAMAAgKHxSnZQBHAgAAAA==.Vampirism:BAABNQAECn8nAAIOAAgKSxqeJwCAAgAOAAgKSxqeJwCAAgAAAA==.Vasira:BAAANQAECgUICQAAAA==.Vaulthunter:BAAANQAECgUICQAAAA==.',
Ve='Vecna:BAAANQADCgMIBQAAAA==.Veina:BAABNQAECn8dAAIMAAgKgRDedgAfAgAMAAgKgRDedgAfAgAAAA==.Veloril:BAAANQADCggIFQABNQADCggIFQAEAAAAAA==.Vespicey:BAAANQAECgEIAgAAAA==.Vethena:BAAANQAECgUIDQAAAA==.Vezahk:BAAANQADCgEIAQAAAA==.',
Vi='Vidu:BAABNQAECn8iAAMfAAcKPg9mMgB/AQAfAAcKPg9mMgB/AQARAAYKNRD8JQBEAQAAAA==.Vikas:BAAANQADCgYIBgAAAA==.Vivitrix:BAAANQAECgUICAAAAA==.Viví:BAABNQAECn8iAAMYAAkKpQ7KrwAhAgAYAAkKFA3KrwAhAgAXAAMKCRC7LgCFAAAAAA==.',
Vl='Vlm:BAAANQAECgUICQAAAA==.',
Vo='Voidbreaker:BAABNQAECn8oAAMVAAkKXR39FwAVAwAVAAkKXR39FwAVAwAWAAEKJAAqlgAGAAAAAA==.Vordis:BAAANQAECgQIBQABNQAECgcIDQAEAAAAAA==.Vordissia:BAAANQAECgcIDQAAAA==.Voxis:BAAANQAECgUICQAAAA==.Voxww:BAAANQAECgQIBAAAAA==.',
Vv='Vv:BAABNQAECn8XAAQRAAYKyQboLwDlAAARAAYKyQboLwDlAAAhAAUK5QEpJgCYAAAfAAMKPQuHVwCFAAAAAA==.',
Vy='Vyrande:BAAANQADCggICQAAAA==.Vyrstal:BAAANQAECgIIAgABNQAECgkJIAAGAMwIAA==.',
Wa='Wardan:BAAANQAECgQICAAAAA==.',
We='Weavile:BAAANQADCgUIBQABNQAFFAUIHAAWAF4dAA==.Wef:BAAANQAECgQIBgAAAA==.Weirdtotem:BAACNQAFFH8HAAMDAAMKrhmNGAD5AAADAAMKrhmNGAD5AAACAAEKpgupKgBHAAA1AAQKfykAAwMACQqZICIbACUDAAMACQqZICIbACUDAAIABwpmHH1SABkCAAAA.Westylad:BAABNQAECn8mAAMKAAgKLx+2OADfAgAKAAgKLx+2OADfAgAbAAUKGBnoEwBeAQAAAA==.Westyladd:BAAANQADCggIDwAAAA==.Wetrat:BAAANQAECgUIBQABNQAFFAYIEAADADsfAA==.',
Wh='Whatthefunk:BAAANQADCgUICgAAAA==.Whohitme:BAAANQADCgEIAQAAAA==.',
Wi='Winterfox:BAAANQADCgYICQAAAA==.Winters:BAAANQADCgMIAwAAAA==.',
Wo='Wolfylad:BAAANQADCgYIBgAAAA==.Woodybax:BAAANQAECgQIBAAAAA==.',
Wr='Wrystal:BAABNQAECn8gAAMGAAkKzAjbFQC9AQAGAAkKzAjbFQC9AQAIAAEKqQLmVwEZAAAAAA==.',
Xa='Xannaa:BAAANQAECgQIBAAAAA==.',
Xe='Xernes:BAAANQADCgQIBAAAAA==.',
Xu='Xujian:BAAANQAECgUICAAAAA==.',
Yu='Yuma:BAAANQAECgQICQABNQAECgUIDQAEAAAAAA==.',
Za='Zaelenia:BAABNQAECn8aAAMaAAcKjRE/SQCQAQAaAAcKIRE/SQCQAQAOAAIK9g6GsgBhAAAAAA==.Zaerel:BAAANQADCgMIAwAAAA==.Zalen:BAABNQAECn8kAAIDAAgKSh40LwC8AgADAAgKSh40LwC8AgAAAA==.Zappylad:BAAANQAECgMIAwAAAA==.Zarelle:BAAANQAECgEIAQAAAA==.Zartoon:BAAANQADCgcIBwAAAA==.',
Ze='Zenamani:BAAANQAECgUJBQAAAA==.Zenetha:BAABNQAECn8bAAMVAAcKVB7UQQBgAgAVAAcKVB7UQQBgAgAWAAMKphI4WwCUAAAAAA==.Zephyres:BAABNQAECn8sAAMSAAkKaCXbAwDAAwASAAkKaCXbAwDAAwATAAYK1CTYDgBxAgABNQAFFAYIEgAKADYcAA==.Zerokool:BAAANQABCgYIBgABNQAECgcIDQAEAAAAAA==.Zevarya:BAAANQAECgEIAQAAAA==.',
Zo='Zonksmoose:BAAANQAECgIIAgABNQAFFAMIBgAeAIkMAA==.Zonkspaladin:BAACNQAFFH8GAAIeAAMKiQwZGADeAAAeAAMKiQwZGADeAAA1AAQKfysAAh4ACQrWHrsWACADAB4ACQrWHrsWACADAAAA.Zornac:BAAANQAECgQICAAAAA==.',
Zp='Zpyder:BAAANQAECgUIDgAAAA==.',
Zu='Zurä:BAAANQADCgQIBAAAAA==.',
Zy='Zynskie:BAABNQAECn8YAAInAAkKIh2ECgD6AgAnAAkKIh2ECgD6AgAAAA==.Zyraa:BAAANQADCgUIBgAAAA==.',
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
