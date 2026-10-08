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

local lookup = {'Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Protection','Druid-Feral','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Guardian','Unknown-Unknown','Priest-Holy','Priest-Shadow','Mage-Frost','Mage-Arcane','Priest-Discipline','DeathKnight-Frost','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Holy','Monk-Windwalker','DemonHunter-Vengeance','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','Hunter-Survival','DemonHunter-Havoc',}
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Accea:BAAANQADCgEIAQAAAA==.Acehobo:BAAANQADCgUIBQAAAA==.Acetaminofun:BAAANQAECgQIDQAAAA==.Actionjaxson:BAABNQAECoEZAAIBAAcKdyMtQACvAgABAAcKdyMtQACvAgAAAA==.',
Ad='Adeathknight:BAAANQABCgIIAgAAAA==.Ademis:BAAANQAECgQIBgAAAA==.Admore:BAAANQAECgUIDgAAAA==.',
Ae='Aeriith:BAABNQAECoEfAAMCAAkKFRj7OgBLAgACAAkKFRj7OgBLAgADAAgK8QziZwC4AQAAAA==.Aethmourne:BAAANQADCgMIAwAAAA==.',
Ag='Agameden:BAAANQAECgYIDwAAAA==.Agogg:BAAANQADCggIHAAAAA==.Agronak:BAAANQABCgIIAgAAAA==.',
Ah='Ahsina:BAAANQABCgUIBQAAAA==.',
Ai='Aintnosecret:BAAANQAECgUICAAAAA==.Aishi:BAAANQAECgQIDQAAAA==.',
Ak='Akaya:BAAANQAECgYIEAABNQAECggIHgADAOARAA==.Akitsuki:BAAANQADCgUIBQAAAA==.',
Al='Algy:BAAANQADCgIJAgAAAA==.Alillara:BAAANQADCgIIAgAAAA==.Alivron:BAABNQAECoEfAAQEAAgKJAs5CQDJAQAEAAgKBQs5CQDJAQAFAAMKaQS4BgF9AAAGAAEKHwIbfwAjAAAAAA==.Alkoren:BAAANQAECgYIDwABNQAECggIJAAHAOsfAA==.Alkorin:BAABNQAECoEkAAMHAAgK6x8+BgDiAgAHAAgK6x8+BgDiAgAIAAIKZgm0GAFsAAAAAA==.Allestra:BAABNQAECoEtAAIJAAkKmR2xDQD8AgAJAAkKmR2xDQD8AgAAAA==.',
Am='Amaranthine:BAAANQADCgYIBgAAAA==.Amoxil:BAAANQAECgQIBwAAAA==.',
An='Anasztaizia:BAEANQAECgEIAgAAAA==.Andorin:BAABNQAECoEoAAIKAAkKhxlSNACsAgAKAAkKhxlSNACsAgAAAA==.Andronicus:BAAANQADCgMIAwAAAA==.Andwin:BAAANQADCggJCAAAAA==.Anorah:BAAANQAECgEIAgAAAA==.Anunitu:BAABNQAECoEjAAICAAgKShsSNQBlAgACAAgKShsSNQBlAgAAAA==.',
Ao='Aoibheann:BAAANQAECgUICwAAAA==.',
Ar='Arath:BAABNQAECoEfAAILAAgKcRV6EQAeAgALAAgKcRV6EQAeAgAAAA==.Arcath:BAABNQAECoEkAAIMAAgK9xuuJQBzAgAMAAgK9xuuJQBzAgAAAA==.Arcona:BAAANQAECgQICQAAAA==.Aristus:BAAANQADCggIEgAAAA==.Arthuel:BAAANQADCgMIAwAAAA==.',
As='Asar:BAAANQAECgQIBwAAAA==.Ashlanni:BAAANQADCgIIAwAAAA==.Asiaminor:BAAANQADCgMIBQAAAA==.Astora:BAAANQADCgcIBwAAAA==.',
At='Athuzad:BAABNQAECoEgAAINAAgKJR77KQBvAgANAAgKJR77KQBvAgAAAA==.',
Au='Auroraalysia:BAAANQADCgcIEgAAAA==.Auroran:BAABNQAECoEZAAIOAAgKrBxMEQBkAgAOAAgKrBxMEQBkAgAAAA==.Autumnmoon:BAABNQAECoEZAAIPAAcKeAzcEwCFAQAPAAcKeAzcEwCFAQAAAA==.',
Av='Aviendah:BAAANQADCggIGgAAAA==.Avrilenv:BAAANQAECgcIBAAAAA==.',
Ay='Ayeroh:BAAANQAECgIIBAAAAA==.Aylara:BAAANQAECgQIBAAAAA==.',
Az='Azenet:BAAANQADCgYIBgAAAA==.Azkabras:BAAANQADCgMIAwABNQAECggIHAADAGgdAA==.',
Ba='Badoink:BAAANQADCggICAABNQAECggIHQAQADYjAA==.Bakasaura:BAAANQADCgYICwABNQAECgcIHAARAMYiAA==.Balorous:BAABNQAECoEcAAQRAAgKsQvHTQCAAQARAAgKdgjHTQCAAQASAAcKSg/aLQB3AQATAAQKaA/XNACzAAAAAA==.Bansheelen:BAABNQAECoEjAAQPAAkK5hVPCwBEAgAPAAgKkBdPCwBEAgATAAUKHxVwJQAkAQASAAUKHg7pOAAgAQAAAA==.Banthis:BAAANQAECgcJEgAAAA==.Barkcamon:BAABNQAECoEfAAIQAAgKWRBKGgCvAQAQAAgKWRBKGgCvAQAAAA==.Barmaak:BAAANQAECgEIAQAAAA==.Barrand:BAAANQADCggJCAABNQAECgcICwAUAAAAAA==.Barthelo:BAABNQAECoEbAAIMAAcK9SEOHwChAgAMAAcK9SEOHwChAgAAAA==.Bassandi:BAAANQADCgEIAQABNQAECggIIwAIAJ4PAA==.Baxdock:BAAANQAECgUICgAAAA==.Baxibovtic:BAAANQADCgUIBQAAAA==.Baxideath:BAAANQAECgYIEQAAAA==.',
Be='Beastylad:BAAANQAECgUIBgAAAA==.Beefcâke:BAAANQADCgYIBgAAAA==.Bekahroo:BAAANQADCgcIHAABNQAECgQICAAUAAAAAA==.Bekahsama:BAAANQAECgQICAAAAA==.Belcron:BAAANQAECgQIBAAAAA==.Beld:BAAANQADCgYJBgAAAA==.Beldaran:BAAANQAECgEIAgAAAA==.Belladawna:BAABNQAECoEaAAMEAAcKUQy+CgCdAQAEAAcKUQy+CgCdAQAFAAEK3QJZMAEpAAAAAA==.Belldândy:BAAANQAECgEIAQAAAA==.Bernal:BAAANQAECgQICQAAAA==.',
Bh='Bhature:BAAANQADCgMIAwAAAA==.',
Bi='Bigmapletree:BAABNQAECoEZAAMVAAcKbgZaiwA6AQAVAAcKbgZaiwA6AQAWAAIKOAIlbAA1AAAAAA==.Bigëmu:BAAANQADCggIKQAAAA==.Billyidols:BAAANQADCgEIAQAAAA==.Bingbangpów:BAAANQAECgMIAgAAAA==.',
Bl='Blackblader:BAAANQAECgUIBgAAAA==.Blarus:BAAANQADCgIIAgAAAA==.Bluecat:BAABNQAECoEaAAIXAAgKWBIJCwDfAQAXAAgKWBIJCwDfAQAAAA==.Blueplanet:BAABNQAECoEcAAIRAAcKxiI2IQClAgARAAcKxiI2IQClAgAAAA==.',
Bn='Bnoo:BAAANQADCgEIAQABNQAFFAUICQAYAEYPAA==.',
Bo='Boarggon:BAAANQADCgEIAQABNQAECgkJHwAHAM0iAA==.Boherwin:BAAANQAECgYIEwAAAA==.Bonnie:BAAANQAECgcICwAAAA==.Borealus:BAAANQAECgYIEQAAAA==.',
Br='Bratakwar:BAAANQAECgcIBwAAAA==.Bris:BAAANQAECgcIEwAAAA==.Bruby:BAAANQAECgYICwAAAA==.Bruceleelad:BAAANQADCgYIBgAAAA==.Brugamen:BAABNQAECoEjAAMIAAgKng+HhwDjAQAIAAgK8g6HhwDjAQAHAAQKaA35KwCnAAAAAA==.Brugg:BAABNQAECoEXAAIKAAgKjRm5SQBpAgAKAAgKjRm5SQBpAgABNQAECggIIwAIAJ4PAA==.Brynnu:BAAANQADCgIIAgAAAA==.Brád:BAABNQAECoEWAAMVAAcKtyPNIADQAgAVAAcKtyPNIADQAgAZAAEKmhNMIgA/AAAAAA==.',
Bu='Bunnylajoya:BAAANQADCgYICwAAAA==.Burgerz:BAAANQADCggIGwAAAA==.Busblaster:BAABNQAECoEZAAMaAAgKeRN/NADNAQAaAAgKRRJ/NADNAQAMAAQKLBKXfQDcAAAAAA==.',
['Bä']='Bäldur:BAAANQAECgcIDQAAAA==.',
Ca='Cainan:BAAANQADCgEIAQAAAA==.Calestel:BAAANQADCgIIAgAAAA==.Careßear:BAAANQAECgMIBAAAAA==.Carielle:BAAANQADCggIGgAAAA==.Carodd:BAABNQAECoErAAIaAAkK6CI8CgA1AwAaAAkK6CI8CgA1AwAAAA==.',
Ce='Cedaver:BAABNQAECoEXAAIIAAYK1RiBogCbAQAIAAYK1RiBogCbAQAAAA==.Ceez:BAAANQADCgYIBwABNQADCggIBQAUAAAAAA==.Cellphoneguy:BAAANQADCgMIAwAAAA==.Celtigar:BAAANQAECgIIAwAAAA==.',
Ch='Chaan:BAAANQAECgUICwAAAA==.Chaddicus:BAAANQADCggJGwAAAA==.Chainna:BAAANQADCggIEAAAAA==.Chaliceia:BAAANQADCgEIAQAAAA==.Chanlin:BAABNQAECoEXAAIMAAkKmh5aGQDLAgAMAAkKmh5aGQDLAgAAAA==.Chateau:BAAANQAECgEIAQAAAA==.Chauda:BAAANQADCgcICwABNQAECggIHgADAOARAA==.Chazbot:BAAANQAECgQIBAAAAA==.Chereth:BAAANQAECgQICQAAAA==.Cheshire:BAABNQAECoElAAIKAAgKWx81MwCwAgAKAAgKWx81MwCwAgAAAA==.Chestystab:BAAANQAECgEIAQAAAA==.Chezpuff:BAAANQADCgEIAQAAAA==.Chill:BAAANQAECgcIEgAAAA==.Chlorin:BAABNQAECoEhAAIbAAgKRAZsNQB2AQAbAAgKRAZsNQB2AQAAAA==.Chocolate:BAACNQAFFIEKAAIYAAUK5xHLGACKAQAYAAUK5xHLGACKAQA1AAQKgSAAAhgACQrMIR1AAPcCABgACQrMIR1AAPcCAAAA.Chunala:BAAANQADCggICAABNQAECgEIAgAUAAAAAA==.',
Cl='Cloudcrasher:BAAANQAECgQIBQAAAA==.Cloudsayer:BAAANQAECgQIBwAAAA==.Cloudspeaker:BAABNQAECoEZAAIcAAgK1RIuEQA4AgAcAAgK1RIuEQA4AgAAAA==.Cloudwalker:BAAANQADCgIIAgAAAA==.',
Co='Coldblades:BAAANQADCgYJBgAAAA==.Coldfrostshk:BAAANQADCgUICgAAAA==.Coldslayer:BAABNQAECoEUAAIKAAYKAxH9ngCWAQAKAAYKAxH9ngCWAQAAAA==.Coldsteeldx:BAAANQADCgUIBQAAAA==.Copy:BAAANQAECgQJBQAAAA==.Corpha:BAAANQADCgUJBQABNQAECgkJJwADAGweAA==.Cozbysuite:BAAANQADCgIIAgAAAA==.',
Cr='Crackzap:BAAANQAECgEIAQAAAA==.Crazyrd:BAABNQAECoEZAAIGAAgKGgTrIwBIAQAGAAgKGgTrIwBIAQAAAA==.Crotgustus:BAAANQADCgMIBQAAAA==.Crudkicker:BAAANQADCgYIBgAAAA==.Crumblebump:BAAANQAECgQICQAAAA==.Crummbly:BAAANQAECgEIAQAAAA==.',
Cy='Cyndelle:BAAANQAECgEIAQAAAA==.Cyntaria:BAAANQAECgIIBAAAAA==.Cyriz:BAAANQAECgIIBgAAAA==.',
Da='Daedrea:BAAANQADCgYIBgAAAA==.Dagarim:BAAANQAECgEIAQAAAA==.Daienne:BAABNQAECoEZAAIRAAgKUQ7jQQDDAQARAAgKUQ7jQQDDAQAAAA==.Danamor:BAABNQAECoEgAAIBAAgKXhdcbwAjAgABAAgKXhdcbwAjAgAAAA==.Dandanx:BAAANQADCggIIAABNQAECgYIFwAIANUYAA==.Daplug:BAAANQAECgMIBgAAAA==.Dariann:BAAANQADCgYIBgAAAA==.Darkbrand:BAABNQAECoEZAAIJAAgKrglvLwCjAQAJAAgKrglvLwCjAQAAAA==.Darkdock:BAAANQADCgIIAgAAAA==.Darkladÿ:BAAANQADCgMIAwAAAA==.Darnel:BAABNQAECoEbAAIOAAcKQxJqJQCGAQAOAAcKQxJqJQCGAQAAAA==.Darnogden:BAAANQADCgUIBQAAAA==.Darnokk:BAAANQAECgQICQAAAA==.',
De='Deathbreaker:BAAANQADCgYJCAAAAA==.Deathbyfel:BAAANQADCgcIDAABNQAECgcIDgAUAAAAAA==.Deathbyshock:BAAANQAECgcIDgAAAA==.Deathdan:BAAANQADCgEIAQAAAA==.Deathrollins:BAAANQAECgIIAwAAAA==.Deathylad:BAAANQAECgYICQAAAA==.Delaror:BAAANQADCgYIBgAAAA==.Denadin:BAAANQAECgEIAgABNQAECgcIBwAUAAAAAA==.Denari:BAAANQABCgMIBQAAAA==.Dennygrips:BAAANQADCggIDQABNQAECgcIBwAUAAAAAA==.Dennyshotz:BAAANQAECgUIBQABNQAECgcIBwAUAAAAAA==.Dennyshreds:BAAANQAECgYIDwABNQAECgcIBwAUAAAAAA==.Dennytotem:BAAANQAECgQIBwABNQAECgcIBwAUAAAAAA==.Dennywarrior:BAAANQAECgcIBwAAAA==.Denrukhan:BAACNQAFFIENAAISAAUKvyIVAwD0AQASAAUKvyIVAwD0AQA1AAQKgSIAAxIACQorI9sHADADABIACQorI9sHADADABEAAQoOHQAAAAAAAAAA.Deschain:BAAANQAECgEIAQAAAA==.Dew:BAABNQAECoE0AAIDAAkKziEDDgBsAwADAAkKziEDDgBsAwAAAA==.',
Di='Didudye:BAAANQADCgMIAwABNQAECgcIGwAdAKsWAA==.Diin:BAAANQAECgUIEAAAAA==.',
Dk='Dklord:BAAANQAECgUIDAAAAA==.',
Do='Dolan:BAAANQADCgEIAQAAAA==.Donappletino:BAAANQAECgIIAwAAAA==.Donkedixlol:BAAANQADCgcICwAAAA==.Doobzers:BAAANQADCgMIAwABNQAECgYJDQAUAAAAAA==.Doxtorbrujo:BAAANQAECgcIEgABNQAECgkJJAAOADIfAA==.Doxtorele:BAAANQAECggIEgABNQAECgkJJAAOADIfAA==.Doxtormonje:BAAANQAECgYICgABNQAECgkJJAAOADIfAA==.Doxtoroso:BAAANQAECgQIBAABNQAECgkJJAAOADIfAA==.Doxtorprote:BAABNQAECoEkAAIOAAkKMh9wBwASAwAOAAkKMh9wBwASAwAAAA==.Doxtorunholy:BAABNQAECoEZAAMMAAkKfRgvOwD2AQAMAAkKfRgvOwD2AQANAAEKigMP3QAkAAABNQAECgkJJAAOADIfAA==.',
Dr='Draelgor:BAAANQADCgEJAQAAAA==.Dredd:BAAANQAECgIIAwAAAA==.Drunk:BAABNQAECoEgAAMQAAgK5g68HACNAQAQAAgK5g68HACNAQAeAAMKXQ4NSgCgAAAAAA==.',
Du='Duckpally:BAAANQABCgYIBgAAAA==.',
Dw='Dwarfussy:BAAANQAECgYICwAAAA==.Dwindle:BAAANQADCgUIBQABNQAECgYIEQAUAAAAAA==.',
Ea='Earthernheal:BAAANQAECgQICAAAAA==.',
Ec='Eckshin:BAAANQADCggIEQAAAA==.',
Ed='Edroffert:BAAANQADCgQIBAAAAA==.',
Eh='Ehonte:BAABNQAECoEjAAIIAAgKWRLxeQAIAgAIAAgKWRLxeQAIAgAAAA==.',
Ei='Eidolonn:BAAANQADCggIGAAAAA==.',
Ek='Ekkaia:BAABNQAECoEcAAIKAAgKRhzZOQCaAgAKAAgKRhzZOQCaAgAAAA==.',
El='Eleminohpee:BAAANQADCgMIAwABNQAECggIFgAYAG0cAA==.Elfypriestly:BAAANQADCgUIBwAAAA==.Elsell:BAAANQAECgEJAQAAAA==.Elwasp:BAAANQAECgEIAgAAAA==.',
Em='Emptypockets:BAAANQADCgUICQAAAA==.',
En='Encana:BAABNQAECoElAAIfAAgKZBfECQAYAgAfAAgKZBfECQAYAgAAAA==.Ender:BAAANQAECgEIAQAAAA==.',
Ep='Epiales:BAAANQADCgUIBQAAAA==.',
Er='Ericgb:BAABNQAECoEmAAMTAAgKmhMcFgDDAQATAAgKmhMcFgDDAQAPAAEKPANUOwApAAAAAA==.Eronara:BAAANQADCgIIAgABNQAECgUIEQAUAAAAAA==.Errzza:BAAANQAECgQICQAAAA==.Erutreya:BAAANQADCgcICQAAAA==.Erzsébet:BAAANQAECgIJBQAAAA==.',
Es='Esha:BAAANQADCgYIGQAAAA==.',
Et='Etsubrew:BAABNQAECoEbAAIeAAkKaCH2BgBMAwAeAAkKaCH2BgBMAwAAAA==.Etsupriest:BAAANQAECgcIEAAAAA==.',
Eu='Eula:BAAANQADCgYICwAAAA==.',
Ev='Evelynn:BAABNQAECoEWAAIfAAcK7g8yEQBrAQAfAAcK7g8yEQBrAQAAAA==.Evoked:BAAANQAECgUICwABNQAECgcICwAUAAAAAA==.',
Ex='Exanimus:BAAANQADCgUJCAAAAA==.Exign:BAAANQADCgIIAgAAAA==.Exix:BAAANQAECgEIAQAAAA==.Exqui:BAABNQAECoEiAAMFAAgKMCEcIQDpAgAFAAgKMCEcIQDpAgAGAAEKkhdGagBBAAAAAA==.',
Ez='Ezral:BAAANQAECgEJAQABNQAECgEIAQAUAAAAAA==.',
['Eí']='Eíko:BAABNQAECoEiAAIVAAkKNhkBMQCDAgAVAAkKNhkBMQCDAgAAAA==.',
Fa='Faeruh:BAAANQADCggICQAAAA==.Fafnar:BAAANQADCgcIDAABNQAECgcIGwAKAB4cAA==.Fafnie:BAAANQAECgYIEwAAAA==.',
Fe='Felath:BAABNQAECoEYAAIfAAcKAxwJCQAtAgAfAAcKAxwJCQAtAgAAAA==.Feldspar:BAAANQAECgcIEQAAAA==.Fennyk:BAAANQADCgYIBgAAAA==.',
Fi='Fil:BAABNQAECoEaAAMeAAcKZSDiFQB6AgAeAAcKZSDiFQB6AgAgAAEKdQaXLAA0AAAAAA==.Fishswife:BAAANQAECgYIDwAAAA==.Fissal:BAAANQADCgcIBwAAAA==.Fistoflurry:BAAANQADCgIIAgABNQAECgkJHwAHAM0iAA==.',
Fl='Flameviper:BAAANQAECgIIBAAAAA==.Flompy:BAAANQADCgIIAgAAAA==.Floreil:BAAANQADCgUICgAAAA==.',
Fo='Foofighter:BAAANQADCgIIAgAAAA==.Footoo:BAAANQAECgMIBgAAAA==.Foxybrie:BAAANQABCgIIAgAAAA==.',
Fr='Friedchimkin:BAAANQADCggIEwAAAA==.Frort:BAAANQADCgcIFAAAAA==.',
Fu='Fuknord:BAAANQADCgYIBwAAAA==.Fulva:BAAANQADCgcIBgAAAA==.',
Fy='Fyneep:BAABNQAECoEcAAIYAAgK7RpubgCLAgAYAAgK7RpubgCLAgAAAA==.Fynne:BAABNQAECoEoAAIVAAkKcxTQPwBGAgAVAAkKcxTQPwBGAgAAAA==.',
Ga='Gaiusmohiam:BAAANQABCgUIBQAAAA==.Galadriell:BAAANQADCgcIDgAAAA==.Galdademon:BAAANQAECgQIBAAAAA==.Galiophobia:BAAANQADCgcIEgAAAA==.Galm:BAAANQADCggIFwAAAA==.Garrethul:BAAANQAECgMIBgAAAA==.Gawleywood:BAAANQAECgQICQAAAA==.',
Ge='Gellidus:BAAANQAECgYIDwAAAA==.Genhooves:BAEANQADCgYJCwABNQAECgkJJwAYAFcaAA==.Gensisd:BAABNQAECoEaAAIDAAgKlBcJRAA6AgADAAgKlBcJRAA6AgAAAA==.Gentledh:BAAANQAECgQICwAAAA==.Gentleshadow:BAAANQAECgUICQAAAA==.Gerulf:BAAANQABCgQIBAAAAA==.',
Gh='Ghosteagle:BAAANQADCgQIBAAAAA==.Ghostvoid:BAAANQABCgYICgAAAA==.',
Gn='Gnomejodas:BAAANQAECgEIAQAAAA==.',
Go='Gobfather:BAAANQADCgcIEgAAAA==.Goldcity:BAABNQAFFIEHAAIJAAUKjQieBwBgAQAJAAUKjQieBwBgAQAAAA==.Goodfaith:BAAANQAECgIIAwAAAA==.Goofy:BAACNQAFFIETAAIIAAYKfB/2BQA7AgAIAAYKfB/2BQA7AgA1AAQKgRwAAggACQr7JG4UAGADAAgACQr7JG4UAGADAAE1AAUUAQgBABQAAAAA.Gotha:BAAANQADCgEIAQABNQAECgYIFwAIANUYAA==.',
Gr='Grimlocke:BAAANQAECgYICAAAAA==.Grimsolo:BAAANQAECgMIAwABNQAECgYICAAUAAAAAA==.Gromit:BAAANQAECgcIEgAAAA==.Grovecaller:BAAANQADCgUICAABNQAECggIGQAcANUSAA==.',
Gu='Gubber:BAAANQADCgIIAQAAAA==.',
Gw='Gwyndolin:BAAANQAECgQICQAAAA==.Gwynne:BAAANQAECgUICgAAAA==.',
Ha='Hacrox:BAAANQAECgQIBAAAAA==.Halanad:BAAANQAECgEIAgAAAA==.Halfmoons:BAABNQAECoEeAAIVAAgK0RvKMQCAAgAVAAgK0RvKMQCAAgAAAA==.Halfsumo:BAAANQAECgUIEQAAAA==.Halobender:BAAANQAECgIIAgAAAA==.Harmhárm:BAAANQADCgIIAgAAAA==.Harrol:BAAANQAECgQICQABNQAECgQIBAAUAAAAAA==.Hassindiir:BAABNQAECoEnAAITAAgKggYcJgAeAQATAAgKggYcJgAeAQAAAA==.Hawgelf:BAAANQAECgYIDwAAAA==.Hawmahcide:BAAANQAECgYIBgAAAA==.Hayles:BAAANQAECgUICgAAAA==.',
He='Helathra:BAAANQAECgcIEAAAAA==.Helliona:BAAANQAECgUIBQAAAA==.Hermonk:BAAANQAECgQICAABNQAFFAUIDAAMAKQcAA==.',
Hi='Hiiru:BAAANQADCgcIBwABNQAECggIJAAHAOsfAA==.Hishunter:BAAANQAECgcIDgABNQAFFAUICQARAIAZAA==.',
Ho='Hofin:BAAANQAECgcIDAAAAA==.',
Hu='Huntarr:BAABNQAECoEXAAIBAAgKzherZgA6AgABAAgKzherZgA6AgAAAA==.Hunterdamon:BAABNQAECoEiAAMJAAgKBg3pKADcAQAJAAgKuQzpKADcAQAfAAIK6w/HJABfAAAAAA==.',
Hy='Hycinna:BAAANQADCgcIEgAAAQ==.Hydrazashen:BAAANQAECgIIAwAAAA==.',
['Hà']='Hàou:BAAANQADCggIGgAAAA==.',
Ia='Iamafish:BAABNQAECoEZAAIKAAcK1hIrewDpAQAKAAcK1hIrewDpAQAAAA==.Iamgroott:BAAANQADCgMIAwAAAA==.',
Ic='Ichimaru:BAAANQAECgYIBgAAAA==.',
Ig='Igotyou:BAABNQAECoEZAAIVAAYKlhOtegBxAQAVAAYKlhOtegBxAQAAAA==.',
In='Insidae:BAABNQAECoEhAAMhAAgK+xh5HwBbAgAhAAgK+xh5HwBbAgAiAAEKowDEUAAVAAAAAA==.',
Ir='Ironpunch:BAAANQADCggICQAAAA==.',
Is='Ismirea:BAAANQAECgIIAwAAAA==.Isoldella:BAAANQADCgcICAAAAA==.',
Iz='Izuna:BAAANQADCgUIBQAAAA==.',
Ja='Jalencarter:BAAANQAECgUICQAAAA==.Jamirprote:BAABNQAECoEVAAIOAAgKUhg9FAA9AgAOAAgKUhg9FAA9AgAAAA==.Jantasir:BAAANQAECgUIDgAAAA==.Jasaryia:BAAANQADCgUICQAAAA==.Javalyn:BAAANQAECgQICQAAAA==.Jazzymage:BAAANQADCgcIBwAAAA==.',
Ji='Jin:BAABNQAECoEaAAIIAAkKXBtlMADpAgAIAAkKXBtlMADpAgABNQAFFAYIDQAcAB0eAA==.Jinda:BAAANQADCgcIGwAAAA==.Jirachi:BAABNQAECoEYAAIdAAgKyxvVLQCTAgAdAAgKyxvVLQCTAgABNQAFFAUIFwAWAHAZAA==.Jiujitsu:BAAANQAECgcICgAAAA==.',
Jo='Jobergas:BAAANQAECgIIBAAAAA==.Jobi:BAAANQAECgMIBAAAAA==.Johallas:BAABNQAECoEkAAIXAAgKYx0ABQCmAgAXAAgKYx0ABQCmAgAAAA==.',
Ju='Judzia:BAAANQAECgMIAwAAAA==.Juf:BAABNQAECoEfAAMVAAgK7g58XwDRAQAVAAgK7g58XwDRAQAWAAEKDQOQgAAbAAAAAA==.Jufster:BAAANQADCggICwAAAA==.Jumpingbear:BAACNQAFFIEOAAIPAAUKUwwDAQCSAQAPAAUKUwwDAQCSAQA1AAQKgSwAAw8ACQr6IrQDAEQDAA8ACQr6IrQDAEQDABEAAgpyFrSHAIIAAAAA.Justdeadfred:BAAANQADCggICAAAAA==.',
Ka='Kagar:BAAANQADCgQIBwAAAA==.Kaho:BAAANQAECgUICQAAAA==.Kainazzo:BAAANQAECgEIAQAAAA==.Kaladorn:BAAANQAECgIIAwAAAA==.Kaladïn:BAAANQADCgUIBQABNQAECgMIBgAUAAAAAA==.Kalda:BAAANQAECgYIEQABNQAECgkJHwAVAGgcAA==.Kalikali:BAAANQADCgcIBwABNQAECgQIBgAUAAAAAA==.Kallisto:BAAANQAECgUIDgAAAA==.Kamiarashi:BAAANQADCggICgAAAA==.Karabethe:BAEANQAECgIIAQAAAA==.Kattizzi:BAAANQADCgMIAwAAAA==.Kazuhiro:BAACNQAFFIESAAIIAAYKhB3FBQBCAgAIAAYKhB3FBQBCAgA1AAQKgSgAAwgACQq3JTQHALQDAAgACQqdJTQHALQDAAcAAgr6JR0nANYAAAAA.',
Ke='Keadath:BAAANQADCgcIBwAAAA==.Keagan:BAAANQAECgUICgAAAA==.Kehzai:BAABNQAECoElAAINAAcKrg+KVgCPAQANAAcKrg+KVgCPAQAAAA==.Kelric:BAAANQADCgUIBQAAAA==.Kenpomaster:BAAANQAECgEIAgAAAA==.Keyalastus:BAAANQADCgQIBAAAAA==.',
Kh='Khaluha:BAAANQAECgIIAwAAAA==.Khaymaan:BAAANQAECgUIDQAAAA==.',
Ki='Killios:BAAANQAECgMIAwAAAA==.Kilmeawden:BAABNQAECoEdAAQEAAkKSx/OBwD2AQAFAAcKwR6JQwBrAgAEAAYKsR3OBwD2AQAGAAEK/Rn2ZABNAAAAAA==.',
Ko='Kozal:BAAANQADCgcIBwAAAA==.',
Kr='Krionys:BAAANQADCgEIAQAAAA==.Krisha:BAABNQAECoEeAAIDAAgK4BFXVQD3AQADAAgK4BFXVQD3AQAAAA==.Krisphobos:BAAANQAECgUIDwAAAA==.',
Ku='Kubael:BAAANQAECgEIAQAAAA==.Kuesham:BAAANQADCgUJBAABNQAECgEIAQAUAAAAAA==.Kulgutbuster:BAABNQAECoEjAAIKAAgKYRxUOACfAgAKAAgKYRxUOACfAgAAAA==.Kungpow:BAABNQAECoEZAAIeAAgKfCG5CwADAwAeAAgKfCG5CwADAwAAAA==.Kupdor:BAAANQAECgYIEgAAAA==.Kuromatsu:BAABNQAECoEXAAISAAcKGh0NGgBBAgASAAcKGh0NGgBBAgAAAA==.Kurtrus:BAAANQADCgQIBAAAAA==.',
['Kÿ']='Kÿt:BAAANQAECgYIEgAAAA==.',
La='Lacedon:BAAANQAECgcIEQAAAA==.Lantank:BAAANQABCgIIAgAAAA==.Larceny:BAAANQAECgYICAAAAA==.Larfleeze:BAAANQADCgYIBgAAAA==.Larryy:BAAANQADCgcIBwAAAA==.Layliah:BAACNQAFFIENAAIRAAYKAxzdBAAnAgARAAYKAxzdBAAnAgA1AAQKgS8AAhEACQrpJJIDALwDABEACQrpJJIDALwDAAAA.',
Le='Leiania:BAAANQADCgUIBQABNQAECgkJKwANABAdAA==.Lewis:BAAANQADCggICAAAAA==.',
Li='Lild:BAAANQADCgYICQAAAA==.Lilgup:BAAANQAECgcICgAAAA==.Linadrea:BAAANQADCggIDgAAAA==.Linedaleiris:BAAANQADCgcIBwAAAA==.Liqudblu:BAAANQAECgQIDwAAAA==.Liqudfury:BAAANQADCggIDQAAAA==.Lishan:BAAANQAECgQIBAAAAA==.Liszandera:BAAANQAECgQIBQAAAA==.Literein:BAABNQAECoEbAAIdAAcKqxbVXADfAQAdAAcKqxbVXADfAQAAAA==.Lizora:BAAANQAECgYICgAAAA==.',
Lo='Lokisan:BAAANQADCgMIAwAAAA==.Lorenei:BAAANQAECgcIEgAAAA==.Los:BAAANQAECgQICAAAAA==.',
Lt='Ltwhisker:BAAANQAECgYIDAAAAA==.',
Lu='Lucìd:BAAANQADCgcIDQAAAA==.Lucïd:BAAANQAECgYIEgAAAA==.Lunhzae:BAAANQADCgUIBQAAAA==.Lustallo:BAAANQADCgcICwAAAA==.',
Ly='Lynxx:BAAANQAECgUICgAAAA==.',
Ma='Macharth:BAAANQAECgUICQAAAA==.Mack:BAAANQAECgcICgAAAA==.Mad:BAABNQAECoEdAAMQAAgKNiMOCwC4AgAQAAcKrCIOCwC4AgAeAAEKtwZLZAAoAAAAAA==.Madchickenz:BAAANQAECgQIEQAAAA==.Magicwithin:BAAANQAECgcIHQAAAQ==.Magut:BAAANQADCgUICAAAAA==.Maira:BAAANQADCgYIFgAAAA==.Maitias:BAAANQADCgUIBQABNQADCgYIBgAUAAAAAA==.Majim:BAAANQAECgYIDgAAAA==.Malevolens:BAAANQAECgIIAgAAAA==.Mannyfingers:BAAANQADCgUIBQAAAA==.Marche:BAABNQAECoEkAAIFAAgKbBUsVAA4AgAFAAgKbBUsVAA4AgAAAA==.Marianacross:BAAANQAECgUIDgAAAA==.Marsel:BAAANQADCgYIBgAAAA==.Masokist:BAAANQADCgYIBgAAAA==.Mavdk:BAAANQADCggIDgABNQAECgQICAAUAAAAAA==.Mavrar:BAAANQAECgQICAAAAA==.',
Mc='Mcflurrey:BAAANQAECgQIDgAAAA==.',
Me='Mechamana:BAAANQADCgYIBgABNQADCggIBQAUAAAAAA==.Meing:BAAANQAECgEIAQAAAA==.Melodrama:BAAANQADCgIIAgAAAA==.Meowrian:BAAANQAECgMIAwAAAA==.Mephïsto:BAAANQAECgEIAQAAAA==.Mereoleona:BAABNQAECoEYAAIYAAgKCBNrrQAGAgAYAAgKCBNrrQAGAgAAAA==.Messdupjuf:BAAANQADCggJCAABNQAECggILgAKAOAmAA==.Messdupllama:BAABNQAECoEuAAIKAAgK4CaPBgCfAwAKAAgK4CaPBgCfAwAAAA==.Metamorfasis:BAABNQAECoEbAAIPAAgK+gyWEQCyAQAPAAgK+gyWEQCyAQAAAA==.',
Mi='Micos:BAAANQAECgIIAgAAAA==.Microburst:BAABNQAECoEWAAIYAAgKbRx9dwB5AgAYAAgKbRx9dwB5AgAAAA==.Microcharge:BAAANQADCgUIBQABNQAECggIFgAYAG0cAA==.Miischief:BAAANQAECgUICgAAAA==.Milkman:BAAANQADCggIFAAAAA==.Misslynn:BAAANQAECgQIBQAAAA==.Missmoodý:BAAANQAECgIIAwAAAA==.Missqwerty:BAAANQAECgEIAQAAAA==.Mistya:BAAANQADCgcIBwAAAA==.Mizari:BAAANQABCgEIAQAAAA==.',
Mo='Moltenbeast:BAAANQAECgcICwABNQAECggIBgAUAAAAAA==.Mongargiss:BAAANQAECgMIBwAAAA==.Mongoth:BAAANQAECgIIAgAAAA==.Montaro:BAAANQAECgQICQAAAA==.Morbidi:BAAANQAECgIIAwAAAA==.Moreithe:BAAANQADCggICAAAAA==.Mortand:BAAANQABCgIIAgAAAA==.Mortharos:BAAANQAECgMIBQAAAA==.',
Mu='Mudkip:BAACNQAFFIEXAAIWAAUKcBlMBQC0AQAWAAUKcBlMBQC0AQA1AAQKgTYAAxYACQo1JD8DAJ0DABYACQo1JD8DAJ0DABkAAQqBDuMmADEAAAAA.Munnsta:BAAANQAECgYIEQAAAA==.Muskan:BAAANQAECgEIAQAAAA==.',
My='Mylanara:BAABNQAECoEkAAIjAAgKKBx0BQCgAgAjAAgKKBx0BQCgAgAAAA==.Mysticah:BAAANQAECgQIBwAAAA==.Mythalagos:BAAANQADCgEIAQAAAA==.Mythblast:BAAANQAECgEJAgAAAA==.Myvrth:BAAANQAECgEIAQAAAA==.',
['Mä']='Märs:BAACNQAFFIEJAAIRAAUKgBlQCQCyAQARAAUKgBlQCQCyAQA1AAQKgSsAAhEACQqmIXkQADEDABEACQqmIXkQADEDAAAA.',
Na='Nacholibre:BAAANQAECgIIAgAAAA==.Naelu:BAAANQADCgMIAwAAAA==.Nanr:BAABNQAECoEkAAQRAAgK5A8xRgCpAQARAAcKjBAxRgCpAQASAAUKyROhNQA6AQATAAMKIQocPACDAAAAAA==.Nathi:BAAANQAECgEIAgAAAA==.Navori:BAACNQAFFIELAAIeAAUKxw2NBgBmAQAeAAUKxw2NBgBmAQA1AAQKgRwAAh4ACArsG4AbADMCAB4ACArsG4AbADMCAAAA.Nazeera:BAEANQADCggIEAABNQAECgEIAgAUAAAAAA==.Nazeraz:BAAANQAECgUIEQAAAA==.',
Ne='Necrokinesis:BAAANQAECgEJAQAAAA==.Nerve:BAABNQAECoEbAAIYAAgKNhMAqQAPAgAYAAgKNhMAqQAPAgAAAA==.Nesiryn:BAAANQADCgYIEAAAAA==.Neth:BAAANQAECgYIDAAAAA==.Neuroshots:BAAANQAECgUICwAAAA==.Newkers:BAAANQADCgUICQAAAA==.',
Ni='Nightknight:BAAANQADCgQIBwAAAA==.Nightràven:BAABNQAECoEkAAMkAAgKZhVlBgAKAgAkAAcKDxZlBgAKAgAKAAUKtQtB1AAlAQAAAA==.Nijitani:BAAANQADCgcIDQAAAA==.Nimrodd:BAAANQAECgQIBQAAAA==.',
No='Nobby:BAAANQADCgUICgAAAA==.Noogan:BAAANQADCgYIBgAAAA==.Nosferatü:BAAANQADCgUJBQAAAA==.Nothotdog:BAAANQADCgIIAgAAAA==.Novacat:BAABNQAECoEoAAISAAkKOR/CCQAQAwASAAkKOR/CCQAQAwAAAA==.Novangel:BAAANQADCgYIBgAAAA==.November:BAAANQAECgUIEQAAAA==.Nox:BAAANQADCggIDAAAAA==.',
Nu='Nubriss:BAABNQAECoEXAAITAAgKGhYLEQAOAgATAAgKGhYLEQAOAgAAAA==.Nudetayne:BAAANQADCgQJBAAAAA==.Nuitsguard:BAABNQAECoEtAAQCAAkKxBs9KAChAgACAAkKxBs9KAChAgAcAAUKhgw6HwAwAQADAAIK+Qzr9ABnAAAAAA==.Nunnaly:BAAANQAECgcIDQAAAA==.',
Ny='Nyaboron:BAABNQAECoEcAAIdAAgKohtCNAB4AgAdAAgKohtCNAB4AgAAAA==.Nyv:BAAANQADCggICAABNQAECgQIBAAUAAAAAA==.',
['Nè']='Nèaner:BAABNQAECoEnAAIVAAgKixH9VAD3AQAVAAgKixH9VAD3AQAAAA==.',
Og='Oggden:BAAANQAECgUIEAAAAA==.Ogrebane:BAABNQAECoEWAAIiAAcK5ga8JgB4AQAiAAcK5ga8JgB4AQAAAA==.',
Oi='Oiheg:BAABNQAECoEjAAIHAAgKTh4cCACsAgAHAAgKTh4cCACsAgAAAA==.',
Or='Oriha:BAAANQADCgYIBgAAAA==.',
Pa='Pajamasniper:BAAANQAECgQICAAAAA==.Pantheon:BAAANQAECgYICQAAAA==.Parttimebear:BAAANQADCgEIAQABNQAECggIHgACAPIkAA==.',
Pe='Peach:BAABNQAECoEbAAIdAAcKEyMvIgDMAgAdAAcKEyMvIgDMAgAAAA==.Peppermint:BAAANQADCggIDwAAAA==.Perlita:BAAANQADCgQJBAAAAA==.',
Ph='Phoephoe:BAAANQADCgMIAwABNQAECgUIEQAUAAAAAA==.Photos:BAABNQAECoEYAAIdAAcKMSSjHgDgAgAdAAcKMSSjHgDgAgAAAA==.',
Pi='Pigums:BAABNQAECoEeAAICAAgK8iRFCwBSAwACAAgK8iRFCwBSAwAAAA==.Pixie:BAAANQADCgcIDQAAAA==.',
Pl='Plugbae:BAAANQADCgMIAwAAAA==.Pluug:BAABNQAECoEYAAMXAAkKhhsiBQCgAgAXAAgKyRwiBQCgAgAYAAYKXRDQ/QBrAQAAAA==.',
Po='Poleo:BAAANQADCggICAAAAA==.',
Pr='Prayer:BAABNQAECoEhAAMBAAgKHCZkEQBzAwABAAgKHCZkEQBzAwAdAAEKtRWRBAE4AAABNQADCgcIBwAUAAAAAA==.Prayered:BAAANQAECgcICwAAAA==.Prîde:BAAANQADCgYIBwAAAA==.',
Ps='Psycopath:BAABNQAECoEbAAIJAAYKwx/mHgA7AgAJAAYKwx/mHgA7AgAAAA==.Psygn:BAAANQADCgUIBQABNQAECgcIGwAMAPUhAA==.Psyloc:BAAANQADCggIHQABNQAECgcIGwAMAPUhAA==.',
Pt='Ptra:BAABNQAECoEXAAIRAAcKaBuTLwA/AgARAAcKaBuTLwA/AgABNQAECgkJIQARAEIdAA==.',
Pu='Puddingfarts:BAAANQAECgMIAwAAAA==.Pumpy:BAACNQAFFIEMAAIDAAUK3hbPCACxAQADAAUK3hbPCACxAQA1AAQKgSIAAgMACQrtIzcQAFkDAAMACQrtIzcQAFkDAAAA.Purrfessor:BAAANQADCggICgAAAA==.Purrpally:BAAANQADCggIEQAAAA==.',
Py='Pywacket:BAAANQAECgcIEAAAAA==.',
['Pã']='Pãlàdoom:BAAANQADCgUIDgABNQAECggIJAAkAGYVAA==.',
Qa='Qadésh:BAAANQABCgYICAABNQADCgUIBQAUAAAAAA==.',
Qu='Quendwings:BAEANQAECgUIBQABNQAFFAYIEwASAA8aAA==.',
Ra='Rabern:BAAANQADCgIIAgAAAA==.Ragnaclio:BAAANQADCgIJAgAAAA==.Rainsky:BAAANQAECgQIAwAAAA==.Ralat:BAAANQADCgQIBAAAAA==.Rasmatazz:BAAANQADCgcIDAAAAA==.Rayleighh:BAAANQAECgYIEAAAAA==.',
Re='Redemptio:BAABNQAECoEVAAQdAAgKgQ0ldwCKAQAdAAcKggwldwCKAQABAAUK8wy4/ADtAAAOAAEKbxP6YAA3AAAAAA==.Relerin:BAAANQADCgIIAgAAAA==.Rexxcat:BAAANQAECgQIBAAAAA==.',
Ri='Rikaza:BAAANQADCgcIBgAAAA==.Ristraza:BAAANQADCgIIAgABNQAECgMJBwAUAAAAAA==.',
Ro='Roguewølf:BAAANQADCgQIBgAAAA==.Roono:BAAANQADCgcICgAAAA==.Rosalidia:BAAANQAECgQICQAAAA==.Rosephane:BAAANQADCgUIBQAAAA==.Ross:BAAANQAECgIIAgAAAA==.Rossco:BAAANQAECgEIAQABNQAECgIIAgAUAAAAAA==.Rozoe:BAAANQAECgUIBQAAAA==.Rozzluz:BAAANQAECgYICwAAAA==.',
Ru='Rutira:BAABNQAECoEnAAIlAAgKZSQOCwBCAwAlAAgKZSQOCwBCAwAAAA==.',
Ry='Ryân:BAAANQADCgMIAwAAAA==.',
['Rê']='Rêcklêss:BAAANQADCgIIAwABNQAECggIJAAkAGYVAA==.',
Sa='Sabbat:BAAANQADCggIEwAAAA==.Salder:BAAANQADCgcIDQABNQADCggIFQAUAAAAAA==.Sapphiwrath:BAAANQADCgYIFAAAAA==.',
Sc='Scuuzemee:BAAANQAECgYICgAAAA==.',
Se='Seacow:BAAANQAECgYIDAAAAA==.Searilus:BAAANQAECgQICQAAAA==.Seethed:BAAANQADCgUJCgAAAA==.Selyana:BAAANQADCggICAAAAA==.Seylena:BAAANQADCggIJwABNQAECgcIGwAeAD8PAA==.',
Sh='Shadowcrit:BAAANQAECgUICgAAAA==.Shamamma:BAAANQADCgUICwAAAA==.Shammallamma:BAAANQABCgQIBgAAAA==.Shamæn:BAAANQAECgQIBwAAAA==.Shaphyr:BAAANQAECgQICgABNQAECgQIEQAUAAAAAA==.Sharphammer:BAAANQAECgEIAQAAAA==.Shieldon:BAAANQADCgUIBQABNQAECgcIFwASABodAA==.Shikamarú:BAAANQADCgEIAQAAAA==.Shinhealer:BAAANQAECgEIAQAAAA==.Shiroa:BAAANQAECgIIAwABNQAECgIJBQAUAAAAAA==.Shlapp:BAAANQADCgUJBQAAAA==.Shootsahlot:BAAANQAECgMIBAAAAA==.',
Si='Sidapa:BAAANQAECgIIAgAAAA==.Silvernleaf:BAAANQAECgEIAQAAAA==.Sinai:BAABNQAECoEaAAISAAcKEQ2GMQBaAQASAAcKEQ2GMQBaAQAAAA==.Sindir:BAAANQADCgUIBQABNQAFFAUIDQASAL8iAA==.Sinner:BAAANQAECgUIBQABNQAECgYICAAUAAAAAA==.Siyx:BAAANQAECgMIBgAAAA==.',
Sk='Skept:BAABNQAECoEdAAMiAAgKAxlIDwB1AgAiAAgKAxlIDwB1AgAhAAIKPAwNeQBzAAAAAA==.',
Sl='Slacky:BAAANQABCggICgAAAA==.Sleêp:BAAANQAECgUICgAAAA==.Slosh:BAABNQAECoEgAAMCAAkKZSL/CQBeAwACAAkKZSL/CQBeAwADAAIKnwZk+QBfAAAAAA==.',
Sm='Smellyandfat:BAECNQAFFIETAAMSAAYKDxqYAgALAgASAAYKDxqYAgALAgARAAUK2wRhEQAaAQA1AAQKgTMAAxIACQoxJQYCAKYDABIACQoxJQYCAKYDABEACQqbH80XAPACAAAA.Smerffy:BAABNQAECoEVAAQCAAcKNRLjbACWAQACAAcKNRLjbACWAQADAAMKxgLX7gB0AAAcAAEKzwFUMwApAAAAAA==.Smites:BAAANQAECgUIBQABNQAECgcIGQABAHcjAA==.',
So='Soiled:BAAANQADCgcIBwAAAA==.Solise:BAAANQAECggIEAAAAA==.Somehobo:BAAANQADCgIIAgAAAA==.Sonny:BAABNQAECoEgAAMXAAcKxh61BgBlAgAXAAcKxh61BgBlAgAYAAUK+BFaEwFFAQAAAA==.Sorshalynne:BAAANQAECgIIBAAAAA==.Soulhorror:BAABNQAECoEeAAINAAgKExwpLABhAgANAAgKExwpLABhAgAAAA==.Sourcha:BAAANQAECgIIAgAAAA==.',
Sp='Spiritfire:BAAANQAECgQIDgAAAA==.Spitefury:BAAANQAECgUICwABNQAECggIHwAQAFkQAA==.Spriggs:BAEBNQAECoEnAAIYAAkKVxocTADaAgAYAAkKVxocTADaAgAAAA==.',
St='Starrfighter:BAAANQAECgYIBgABNQAECgkJLQACAMQbAA==.Stepfather:BAAANQADCgIIAgAAAA==.Stepmother:BAAANQADCgIIAgAAAA==.Stillblade:BAAANQADCggIBQAAAA==.Stonedread:BAAANQADCgcIEgAAAA==.Stormfodder:BAAANQABCgQIBAAAAA==.Stronker:BAAANQADCggICgAAAA==.',
Su='Sungmi:BAABNQAECoEZAAMCAAgKBRtjNwBaAgACAAgKBRtjNwBaAgADAAMKJBOf0wC6AAAAAA==.Sunntzu:BAABNQAECoEfAAMgAAkKER72BAAEAwAgAAkKER72BAAEAwAeAAIKqA7MUQBwAAAAAA==.',
Sw='Swindlle:BAAANQAECgYIEQAAAA==.',
Sy='Syber:BAABNQAECoEmAAMSAAkK7BucCwD2AgASAAkK7BucCwD2AgARAAQKzA7fbgDkAAAAAA==.Syberfist:BAAANQABCgQIBAABNQAECgkJJgASAOwbAA==.Syberstyx:BAAANQADCgQIBAABNQAECgkJJgASAOwbAA==.Sympathy:BAAANQAECgQIBgAAAA==.Symphonica:BAABNQAECoEcAAIhAAgKzRIVKQAYAgAhAAgKzRIVKQAYAgAAAA==.Syreithis:BAAANQAECgUICgAAAA==.',
['Sí']='Síd:BAABNQAECoEkAAMhAAgKexm+HQBnAgAhAAgKexm+HQBnAgAiAAUKvgvQMAAWAQAAAA==.',
Ta='Tacofighter:BAABNQAECoEYAAINAAcKOAruagBCAQANAAcKOAruagBCAQAAAA==.Taerielle:BAABNQAECoEwAAIXAAkKNhudBAC2AgAXAAkKNhudBAC2AgAAAA==.Tageren:BAAANQADCgYIEAAAAA==.Taldim:BAAANQADCgUIBQABNQAECgcIGwAMAPUhAA==.Tarhos:BAAANQABCgIIBgAAAA==.Tarò:BAABNQAECoErAAIVAAkKmgu8YADNAQAVAAkKmgu8YADNAQAAAA==.Taychi:BAAANQAECgIIAgABNQAECggIFgAJAAgQAA==.',
Te='Teacupps:BAACNQAFFIEJAAQGAAUKugq/CwCjAAAGAAIKVBG/CwCjAAAFAAIKjgjsLACLAAAEAAEK3AF7EAAzAAA1AAQKgSIAAwYACQotHrkTAMoBAAUABwpVG1BkAAkCAAYABwoeFrkTAMoBAAAA.Teegan:BAAANQAECgQIDQABNQAECgcIHwAWAKIXAA==.Tekloa:BAAANQADCgUIBQAAAA==.Telvissra:BAABNQAECoErAAINAAkKEB2sGgDRAgANAAkKEB2sGgDRAgAAAA==.Temporary:BAAANQAECgEIAQAAAA==.Teoritta:BAABNQAECoEYAAQFAAcK7xsbVgAyAgAFAAcKtxobVgAyAgAGAAMKkRGIQQCzAAAEAAEKDRasJwA/AAAAAA==.Terrisher:BAABNQAECoEbAAIBAAgK1AlPqQCVAQABAAgK1AlPqQCVAQAAAA==.',
Th='Thaljadrak:BAAANQADCgQIBwAAAA==.Thermopalea:BAAANQADCggIEgAAAA==.Thetamoon:BAABNQAECoEbAAMKAAcKHhzRYAArAgAKAAcKHhzRYAArAgAbAAMK+AhNYAB+AAAAAA==.Thorald:BAAANQAECgYIDgAAAA==.Thordh:BAAANQAECgcIDAAAAA==.Thorggon:BAABNQAECoEfAAMHAAkKzSJcAgB7AwAHAAkKzSJcAgB7AwAIAAEKiBbjJwFHAAAAAA==.Thornbeast:BAAANQAECgQIBgAAAA==.Thuato:BAAANQADCgQICAAAAA==.Thundermayne:BAAANQAECgIIAwAAAA==.Thád:BAABNQAECoEWAAITAAcKcCDNCgCIAgATAAcKcCDNCgCIAgAAAA==.',
Ti='Tiranoc:BAAANQADCgcIEAABNQAECggIGgADAJQXAA==.',
To='Tojara:BAAANQAECgUIBQAAAA==.Toxique:BAAANQAECgIIBAAAAA==.',
Tr='Trappist:BAAANQADCgMIAwAAAA==.Travelocitee:BAAANQAECgYIDgAAAA==.Triskalyn:BAAANQAECgEJAQAAAA==.Trojanhorse:BAAANQADCggIIAAAAA==.Trokosan:BAAANQAECgQJBAAAAA==.Trustissues:BAAANQADCggIFgAAAA==.Try:BAACNQAFFIENAAIcAAYKHR7iAAArAgAcAAYKHR7iAAArAgA1AAQKgSUAAhwACQp9JroBAJ0DABwACQp9JroBAJ0DAAAA.Trybu:BAACNQAFFIEJAAIYAAUKRg/uFwCRAQAYAAUKRg/uFwCRAQA1AAQKgTMAAhgACQrwIpoUAHsDABgACQrwIpoUAHsDAAAA.Tryiss:BAAANQAECgUIBwAAAA==.',
Tt='Ttryss:BAAANQADCgUIBQAAAA==.',
Tu='Tubslumpkin:BAAANQAECgIIAgAAAA==.Tuketu:BAABNQAECoElAAIRAAgKzxA2PQDiAQARAAgKzxA2PQDiAQAAAA==.Turtlelord:BAABNQAECoEjAAIFAAgKDxWuYwALAgAFAAgKDxWuYwALAgAAAA==.',
Ty='Tylarion:BAAANQAECgQIBAAAAA==.Tylendal:BAABNQAECoEhAAILAAgK/hqvCwCUAgALAAgK/hqvCwCUAgAAAA==.Tylenolz:BAAANQAECgUIDAAAAA==.Tylenulz:BAAANQAECgYIEgAAAA==.Tylheras:BAAANQAECgcIDAAAAA==.Tyliera:BAAANQADCgcICAAAAA==.Tylren:BAAANQAECgMIAwAAAA==.',
['Tà']='Tànya:BAAANQAECgUIDQAAAA==.',
Un='Undbaxi:BAAANQADCgQIBQAAAA==.Unfàthømable:BAAANQADCggICAABNQAECggIJAAkAGYVAA==.',
Ut='Uthercito:BAAANQADCggICQAAAA==.',
Uz='Uzen:BAAANQAECgMIAwAAAA==.',
Va='Vallarath:BAAANQAECgcIEgAAAA==.Valtaran:BAAANQAECgIIAwAAAA==.Valtarr:BAABNQAECoEdAAIKAAgK4ROnXQAzAgAKAAgK4ROnXQAzAgAAAA==.Vampirism:BAABNQAECoEfAAIMAAgKAhhpLQBEAgAMAAgKAhhpLQBEAgAAAA==.Vasira:BAAANQAECgIIBAAAAA==.Vaulthunter:BAAANQAECgQIBQAAAA==.',
Ve='Vecna:BAAANQADCgMIBQAAAA==.Veina:BAAANQAECgcIEgAAAA==.Veloril:BAAANQADCggIFQAAAA==.Vespicey:BAAANQAECgEIAQAAAA==.Vethena:BAAANQAECgUICQAAAA==.Vezahk:BAAANQADCgEIAQAAAA==.',
Vi='Vidu:BAABNQAECoEbAAMeAAcKPw98LQB6AQAeAAcKPw98LQB6AQAQAAYKHw0JJQApAQAAAA==.Vikas:BAAANQADCgYIBgAAAA==.Vivitrix:BAAANQAECgIIAwAAAA==.Viví:BAABNQAECoEcAAMYAAkKagt1sQD+AQAYAAkKKAp1sQD+AQAXAAMKCRD5KACIAAAAAA==.',
Vl='Vlm:BAAANQAECgUICQAAAA==.',
Vo='Voidbreaker:BAABNQAECoEfAAMVAAkKaBzzFgAGAwAVAAkKaBzzFgAGAwAWAAEKJADxhgAGAAAAAA==.Vordis:BAAANQAECgQIBQABNQAECgcIDQAUAAAAAA==.Vordissia:BAAANQAECgcIDQAAAA==.Voxis:BAAANQAECgQICAAAAA==.',
Vv='Vv:BAAANQAECgUIEQAAAA==.',
Vy='Vyrande:BAAANQADCggICQAAAA==.Vyrstal:BAAANQADCggICAABNQAECggIHgAGAPkHAA==.',
Wa='Wardan:BAAANQAECgIIBAAAAA==.',
We='Weavile:BAAANQADCgUIBQABNQAFFAUIFwAWAHAZAA==.Wef:BAAANQAECgIIAgAAAA==.Weirdtotem:BAABNQAECoEnAAMDAAkKbB7KIwDYAgADAAgKriHKIwDYAgACAAcKZhykRwAYAgAAAA==.Westylad:BAABNQAECoEeAAMIAAcKDiLrRgCcAgAIAAcKDiLrRgCcAgAjAAUK8BpBEQBqAQAAAA==.Westyladd:BAAANQADCggIDwAAAA==.Wetrat:BAAANQAECgUIBQABNQAFFAUIDAADAN4WAA==.',
Wh='Whatthefunk:BAAANQADCgUICgAAAA==.Whohitme:BAAANQADCgEIAQAAAA==.',
Wi='Winterfox:BAAANQADCgYICQAAAA==.Winters:BAAANQADCgMIAwAAAA==.',
Wo='Woodybax:BAAANQAECgQIBAAAAA==.',
Wr='Wrystal:BAABNQAECoEeAAMGAAgK+QfyGgCNAQAGAAgK+QfyGgCNAQAFAAEKqQKWPAEZAAAAAA==.',
Xa='Xannaa:BAAANQADCgIJAgAAAA==.',
Xe='Xernes:BAAANQADCgQIBAAAAA==.',
Xu='Xujian:BAAANQAECgUICAAAAA==.',
Ya='Yakiki:BAAANQAFFAEIAQABNQAECgkJGgASAAAaAA==.',
Yu='Yuma:BAAANQAECgQIBQABNQAECgUIDQAUAAAAAA==.',
Za='Zaelenia:BAAANQAECgUIEAAAAA==.Zaerel:BAAANQADCgMIAwAAAA==.Zalen:BAABNQAECoEcAAIDAAgKaB1dKwCuAgADAAgKaB1dKwCuAgAAAA==.Zappylad:BAAANQAECgMIAwAAAA==.Zarelle:BAAANQAECgEIAQAAAA==.Zartoon:BAAANQADCgcIBwAAAA==.',
Ze='Zenamani:BAAANQAECgUJBQAAAA==.Zenetha:BAAANQAECgUIEQAAAA==.Zephyres:BAABNQAECoEkAAMRAAkKPSUuBACyAwARAAkKPSUuBACyAwATAAYKrSRPCwB7AgABNQAFFAYIEgAIAIQdAA==.Zerokool:BAAANQABCgYIBgABNQAECgcICQAUAAAAAA==.Zevarya:BAAANQAECgEIAQAAAA==.',
Zo='Zonksmoose:BAAANQADCgYIDwAAAA==.Zonkspaladin:BAABNQAECoEqAAIdAAkK1h4MEgAuAwAdAAkK1h4MEgAuAwAAAA==.Zornac:BAAANQAECgIIBAAAAA==.',
Zp='Zpyder:BAAANQAECgUICQAAAA==.',
Zy='Zynskie:BAAANQAECgcIEQAAAA==.Zyraa:BAAANQADCgIIAQAAAA==.',
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
