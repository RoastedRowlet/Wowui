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

local lookup = {'Mage-Arcane','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Arms','Unknown-Unknown','DeathKnight-Unholy','Shaman-Restoration','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Druid-Guardian','Priest-Holy','Warrior-Fury','Paladin-Retribution','Evoker-Preservation','Priest-Shadow','Hunter-Marksmanship','Priest-Discipline','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Fire','DemonHunter-Vengeance','Druid-Feral','Shaman-Enhancement','Shaman-Elemental','Warlock-Affliction','Evoker-Devastation','Monk-Brewmaster','Evoker-Augmentation','Monk-Mistweaver','DeathKnight-Frost','Monk-Windwalker',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAABNQAECoEbAAIBAAgKKRUenQAoAgABAAgKKRUenQAoAgAAAA==.',
Ac='Acceb:BAAANQADCgQJBAAAAA==.',
Ad='Adventureux:BAABNQAECoEfAAICAAkKrBk0OwCVAgACAAkKrBk0OwCVAgAAAA==.',
Ae='Aedx:BAABNQAECoEiAAIDAAkKyQ+yGQD5AQADAAkKyQ+yGQD5AQAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Al='Alastar:BAABNQAECoEZAAIEAAgKqx8RSgCSAgAEAAgKqx8RSgCSAgABNQAFFAEIAQAFAAAAAA==.Alexmage:BAAANQADCgYIBgABNQADCgcIBwAFAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alphasalt:BAAANQADCgcIBwABNQAECgQICgAFAAAAAA==.Alucard:BAAANQAECgYIDwAAAA==.Alunadoom:BAAANQAECgYIDQAAAA==.Alvera:BAACNQAFFIEGAAIGAAQKIBi3CgA+AQAGAAQKIBi3CgA+AQA1AAQKgSsAAgYACQrIJLQFAI8DAAYACQrIJLQFAI8DAAAA.',
Am='Ambellìna:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.',
An='Ancestor:BAABNQAECoEeAAIHAAkK8g7ZUgDuAQAHAAkK8g7ZUgDuAQAAAA==.Angechi:BAEANQADCgIJAgABNQAECggIHQAIAN4HAA==.Angrydk:BAAANQAECgEIAQAAAA==.Antisocial:BAABNQAECoEkAAIGAAkKUyGjDwAlAwAGAAkKUyGjDwAlAwABNQAECgkKJAAGAFMhAA==.',
Ar='Arm:BAABNQAECoExAAQJAAkKKxHZHAAiAgAJAAkKKxHZHAAiAgAKAAYKxguZXgAtAQALAAIKuBIwQgBcAAAAAA==.Armee:BAABNQAECoEXAAIMAAgK7BeVUgAAAgAMAAgK7BeVUgAAAgAAAA==.Armz:BAAANQABCgEIAQAAAA==.',
As='Astrael:BAAANQAECgYIDAAAAA==.Aszea:BAAANQAECgEIAQAAAA==.',
Ax='Axra:BAABNQAECoEXAAINAAgKvA5QDQC8AQANAAgKvA5QDQC8AQAAAA==.',
Az='Azairius:BAAANQADCggIEAAAAA==.Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAAANQAECgcIEQAAAA==.',
Ba='Balsin:BAABNQAECoEgAAIOAAgKMiSpHwAtAwAOAAgKMiSpHwAtAwAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgUIBgABNQAFFAcIFAAPAB0XAA==.Barlaf:BAABNQAECoEvAAICAAgKnB8BLADJAgACAAgKnB8BLADJAgABNQADCggIGgAFAAAAAA==.Batou:BAAANQAECgUICAAAAA==.',
Be='Beeski:BAAANQADCgUIDwAAAA==.Beeto:BAABNQAECoEoAAIOAAkKMhcfqwCRAQAOAAkKMhcfqwCRAQAAAA==.Belyndris:BAAANQAECgcIEgAAAA==.Benlian:BAEBNQAECoEdAAIIAAgK3gdGXgBYAQAIAAgK3gdGXgBYAQAAAA==.',
Bl='Blighty:BAAANQAECgUIBgAAAA==.Blâze:BAACNQAFFIEKAAIBAAUKzhZTFACrAQABAAUKzhZTFACrAQA1AAQKgSAAAgEACQroGo1jAKMCAAEACQroGo1jAKMCAAAA.',
Bo='Bonknsmash:BAABNQAECoEfAAIEAAgK/RNsdwAOAgAEAAgK/RNsdwAOAgAAAA==.Boof:BAABNQAECoEgAAIQAAgKyRdLHQAzAgAQAAgKyRdLHQAzAgAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAABNQAECoEgAAIRAAgKuRSLIgAZAgARAAgKuRSLIgAZAgAAAA==.',
Bu='Bubbleoshift:BAAANQAECgEIAQABNQAECgYIEAAFAAAAAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICgAFAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECggIGQABACoSAA==.',
['Bó']='Bóba:BAACNQAFFIEcAAIPAAcKUiL4AADFAgAPAAcKUiL4AADFAgA1AAQKgSUAAg8ACQrCIw8FAFMDAA8ACQrCIw8FAFMDAAAA.',
['Bö']='Böba:BAABNQAECoEZAAQMAAkKkCTKCABrAwAMAAkKkCTKCABrAwASAAYKCyC/BQApAgAQAAEK7RK+awA2AAABNQAFFAcIHAAPAFIiAA==.',
Ca='Cadiva:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.Cadroyd:BAAANQAECggIDQAAAA==.Caelin:BAABNQAECoEoAAMTAAkK8RHlLAAPAgATAAgKABTlLAAPAgAUAAEKegFSaAAgAAAAAA==.Cailand:BAAANQAECgYIEwAAAA==.Caishana:BAABNQAECoEpAAIHAAkKIiLeCgBVAwAHAAkKIiLeCgBVAwAAAA==.Cambium:BAAANQAECgUIEAAAAA==.Camerbunne:BAAANQADCgYIDwAAAA==.Catdude:BAAANQAECgQJBQAAAA==.',
Ce='Cecil:BAAANQADCgYIBgAAAA==.Celebrate:BAAANQADCgMIAwAAAA==.',
Ch='Chaddingus:BAAANQAECggICgAAAA==.Chopadk:BAABNQAECoEgAAIIAAkK6Q7iSAC1AQAIAAkK6Q7iSAC1AQAAAA==.Chumlëy:BAAANQADCgUIBQAAAA==.',
Cl='Clash:BAAANQADCgUICAAAAA==.Clique:BAABNQAECoEXAAIVAAcKqhlLSQAjAgAVAAcKqhlLSQAjAgAAAA==.',
Cn='Cnc:BAAANQAECgEIAQAAAA==.',
Co='Coheedkil:BAAANQAECgEIAQAAAA==.Coldbreeze:BAAANQAECgYIEwAAAA==.Collateral:BAAANQADCgcIBwAAAA==.Colomel:BAAANQAECgYICQAAAA==.Comegetsum:BAAANQADCgYIEQAAAA==.Compaktdisc:BAAANQADCgYJBgABNQAECgYIEAAFAAAAAA==.Conqbine:BAAANQADCgcIEwAAAA==.Corg:BAAANQAECgEIAQAAAA==.Countchocula:BAAANQAECgQIDAAAAA==.',
Cr='Crimmi:BAAANQAECgUICQAAAA==.Critzilla:BAAANQAECgUIBQAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUJBQABNQAECgkJGwABAIcbAA==.Cyndle:BAABNQAECoEpAAIHAAkKbAqaZwCmAQAHAAkKbAqaZwCmAQAAAA==.',
Da='Daddythicc:BAABNQAECoEgAAIBAAgK9QtTygDMAQABAAgK9QtTygDMAQAAAA==.Darnwrath:BAAANQAECgYIBgAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQAECgQIBQAAAA==.Deadillusion:BAAANQADCgUIBQABNQAECgYIBwAFAAAAAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAABNQAECoEbAAMOAAcK4xtPcgAcAgAOAAcKsRlPcgAcAgAWAAYKixirJQCEAQAAAA==.',
Di='Diante:BAAANQAECgEIAQAAAA==.Dimple:BAAANQAECgIJAgAAAA==.Dirtmonkgirt:BAAANQAECgcIEwAAAA==.',
Dk='Dknujabes:BAAANQAECggICAAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAABNQAECoEgAAMXAAkKEA5AcQDjAQAXAAkKqAtAcQDjAQAYAAMKJg3GQgCvAAAAAA==.',
Dr='Dracara:BAABNQAECoEdAAQZAAkKDRc7BwBTAgAZAAgKdxk7BwBTAgAaAAQKDA+8BQDxAAABAAMKkQctfgGQAAAAAA==.Dracia:BAAANQAECgYIEAAAAA==.Drakulya:BAAANQABCgQIBAAAAA==.Dreadz:BAABNQAECoEbAAMUAAcKBRHBLQCxAQAUAAcKuhDBLQCxAQAbAAIKuwtEJABkAAAAAA==.Drewish:BAABNQAECoEgAAIcAAgK/h+pBgDWAgAcAAgK/h+pBgDWAgAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQAFAAAAAA==.Drizzle:BAABNQAECoEhAAIUAAkKOiL3BQBsAwAUAAkKOiL3BQBsAwAAAA==.Drktotem:BAABNQAECoEeAAMdAAkKAiEsAwBnAwAdAAkKAiEsAwBnAwAHAAYKtxbofABnAQAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFIEcAAIJAAcKPx9hAAC5AgAJAAcKPx9hAAC5AgA1AAQKgTEAAgkACQqoI+gCAI8DAAkACQqoI+gCAI8DAAAA.Dumbledwarf:BAAANQADCggICAAAAA==.Dusan:BAABNQAECoEeAAIMAAcKMh9COQBhAgAMAAcKMh9COQBhAgAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgcICAAAAA==.',
Ec='Echeyaket:BAAANQAECgYIEgAAAA==.',
Ed='Edonsian:BAABNQAECoEtAAIEAAkKmxalVgBrAgAEAAkKmxalVgBrAgAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEAABNQAECgYIEgAFAAAAAA==.Elelusion:BAAANQAECgYIBwAAAA==.Elliekins:BAAANQAECgYICgAAAA==.Ellunaris:BAEANQAECgcIDgABNQAECggIHQAIAN4HAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
En='Endlesshour:BAAANQADCgMIAwAAAA==.Endlessly:BAAANQAECgEIAQAAAA==.Enoka:BAABNQAECoEdAAIBAAgKhxjemQAvAgABAAgKhxjemQAvAgAAAA==.',
Es='Estelá:BAAANQADCgYIBgAAAA==.',
Et='Etikwa:BAABNQAECoEYAAIJAAcK5wlgNQA8AQAJAAcK5wlgNQA8AQAAAA==.',
Eu='Euclid:BAAANQAECgMIAwAAAA==.',
Ev='Evilguard:BAABNQAECoEaAAIIAAgKhA1kVACAAQAIAAgKhA1kVACAAQAAAA==.',
Ex='Excessive:BAAANQAECgIIAgAAAA==.Exroastbeef:BAAANQADCggICAAAAA==.',
Fa='Falador:BAAANQAECgUICwAAAA==.Fariebubbles:BAAANQAECgEIAQAAAA==.',
Fe='Felene:BAABNQAECoEbAAMeAAkKZBpnKgCzAgAeAAkKZBpnKgCzAgAHAAIK7A7I6gBkAAAAAA==.',
Fi='Firitako:BAAANQAECgUICgAAAA==.',
Fr='Frailey:BAAANQAECgYIEAAAAA==.Frankiejr:BAAANQAECgEIAQABNQAECgYIEQAFAAAAAA==.Fraubles:BAAANQAECgMIBAAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQADCggICQAAAA==.Frostnite:BAAANQAECgQICAAAAA==.Frostpoptart:BAABNQAECoEeAAIdAAgKDhZ1DwBYAgAdAAgKDhZ1DwBYAgAAAA==.Frozenblade:BAABNQAECoEfAAIIAAkKNRWzOAAEAgAIAAkKNRWzOAAEAgAAAA==.',
Fu='Furball:BAAANQADCgYIBgABNQAFFAMIBwAYAP8QAA==.Furiousgeorg:BAAANQAECgUIDAAAAA==.',
Ga='Gagabooney:BAAANQAFFAIIBAAAAA==.Garabashi:BAAANQADCgcJBwAAAA==.Garrick:BAAANQAECgYICQAAAA==.Gazze:BAABNQAECoEeAAILAAcKbAktJgAeAQALAAcKbAktJgAeAQAAAA==.',
Ge='Gemli:BAAANQADCgUIBQAAAA==.Gennissa:BAAANQAECgMIBAAAAA==.Gethsemane:BAABNQAECoEfAAMXAAgK3xotSABcAgAXAAgK3xotSABcAgAfAAQKoxfgDwAmAQAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcJCQAAAA==.Gillis:BAAANQADCgQIBAAAAA==.',
Gl='Glassdance:BAAANQADCgcIBwAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggIFwAAAA==.Googrektar:BAAANQAECgQIBAABNQAECgkJKgABAIIeAA==.Goonielama:BAABNQAECoEjAAIIAAkKjyE5CwBLAwAIAAkKjyE5CwBLAwABNQAFFAIIBAAFAAAAAA==.Goonietai:BAAANQAECgUICQABNQAECgkJKgABAIIeAA==.',
Gr='Greenterror:BAAANQADCgIIAgAAAA==.Grid:BAAANQAECgEIAQABNQAECgkJNwAXAA4kAA==.Griitz:BAAANQAECgQICAAAAA==.Grimmsheeper:BAACNQAFFIEGAAIBAAQK6A5yIgAzAQABAAQK6A5yIgAzAQA1AAQKgS4AAgEACQorIfEyABkDAAEACQorIfEyABkDAAAA.Gryff:BAAANQADCgUJBQAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFIEZAAMGAAYKtCByAwDkAQAGAAUKxyByAwDkAQAIAAEKVSAFIwBZAAA1AAQKgSYAAgYACQrbJYsIAGsDAAYACQrbJYsIAGsDAAAA.',
Gy='Gyat:BAAANQADCgMJAwAAAA==.',
Ha='Hairynujabes:BAAANQAECggIDgAAAA==.Hanyuu:BAAANQAECgcIEQAAAA==.',
He='Heiter:BAABNQAECoEiAAIMAAgKKhrbRQAwAgAMAAgKKhrbRQAwAgAAAA==.Hellbound:BAABNQAECoEjAAMXAAgKrxiMTgBJAgAXAAgKNReMTgBJAgAYAAIK/BOPUACBAAAAAA==.Hellinhunt:BAABNQAFFIEIAAMCAAcK2AuhEQAHAQARAAQK2gfUDgAjAQACAAMKKxGhEQAHAQAAAA==.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Holypants:BAAANQADCgYIBgAAAA==.Honk:BAAANQAECgUIBQABNQAECggIGQABACoSAA==.Hornivore:BAAANQADCgcIFQABNQAECggIJgACAGIZAA==.',
Hy='Hyrja:BAAANQADCgUIBgABNQAECgkJHQAZAA0XAA==.',
Ic='Icefrosting:BAAANQAECgYIDgAAAA==.',
Id='Idistroya:BAAANQAECgQJBgABNQAECggIFwACAIEUAA==.',
Ig='Iggnogg:BAAANQADCggIKwAAAA==.',
Ik='Ikura:BAACNQAFFIEIAAIMAAMK4RCkGAD1AAAMAAMK4RCkGAD1AAA1AAQKgSQABBIACQoxE3sLAHIBAAwACQqDD79VAPQBABIABwoyDXsLAHIBABAAAQpvCP93ACUAAAAA.',
Il='Ilithiya:BAABNQAECoEaAAIUAAgKHSS/CQAxAwAUAAgKHSS/CQAxAwAAAA==.Ilk:BAAANQAECgYIEAAAAA==.Illududu:BAAANQAECgEIAQABNQAECgYIBwAFAAAAAA==.',
Im='Imangry:BAAANQADCgEIAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAAANQAECgYIEAAAAA==.Ishton:BAABNQAECoEYAAIOAAkKrw+cdwAOAgAOAAkKrw+cdwAOAgAAAA==.Istompgnomes:BAAANQAECgYIEwAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jasøn:BAAANQADCgcIDgABNQAECgYIEwAFAAAAAA==.',
Je='Jecthyr:BAABNQAECoEfAAMPAAgKrRhVFABWAgAPAAgKrRhVFABWAgAgAAMKjw/eKQC4AAAAAA==.Jefeson:BAAANQAECgMIAwAAAA==.Jemhdar:BAAANQAECgEIAQAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAAANQAECgEIAQAAAA==.',
Js='Jsdruid:BAAANQAECgQIBAAAAA==.',
Ju='Juicyheals:BAAANQADCgIIAgAAAA==.',
Ka='Kaelosu:BAABNQAECoEtAAIXAAkKWh17IQDnAgAXAAkKWh17IQDnAgAAAA==.Kakum:BAAANQAECgMIAwAAAA==.Kaldrogo:BAAANQADCggIFAAAAA==.Kalnuggets:BAAANQAECgMIAwAAAA==.Kalrathen:BAABNQAECoEpAAMMAAkK1BYfMACHAgAMAAkK1BYfMACHAgAQAAEKewGMggAYAAAAAA==.Kanda:BAABNQAECoEnAAICAAkKghZ4OgCYAgACAAkKghZ4OgCYAgAAAA==.Karsh:BAAANQAECgcIEwAAAA==.Kazadax:BAAANQAECgcIDgAAAA==.',
Ke='Kealosu:BAAANQADCggIDgAAAA==.Keen:BAAANQAECgEIAQAAAA==.Keuaakepo:BAABNQAECoEXAAICAAgKgRQCZQAgAgACAAgKgRQCZQAgAgAAAA==.',
Ki='Kienne:BAAANQAECgUIEwAAAA==.Kiljaedra:BAAANQAECgEIAQABNQAECgkJHQAZAA0XAA==.Kinomi:BAAANQADCgYJBgABNQAECgYIEAAFAAAAAA==.Kitenna:BAAANQAECgMIAwAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAAANQAECgYIEQAAAA==.Korogar:BAAANQAECgMIBQAAAA==.',
Kp='Kpes:BAAANQADCgUJBQAAAA==.',
Kr='Kreamyumyums:BAAANQAECgUICgAAAA==.Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAFFAUIDQAGAJElAA==.Kronknar:BAAANQABCgQJBAABNQAECggIJQAeAOUaAA==.',
Ky='Kymira:BAABNQAECoEmAAIhAAkKthrYBwCbAgAhAAkKthrYBwCbAgAAAA==.',
La='Lace:BAABNQAECoE3AAMXAAkKDiT7CAB0AwAXAAkKsiL7CAB0AwAYAAIK1CJJPADFAAAAAA==.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAABNQAECoEmAAICAAgKYhkGTgBdAgACAAgKYhkGTgBdAgAAAA==.Lavatory:BAAANQADCgEIAQAAAA==.Lazarou:BAAANQAECgQIAwAAAA==.',
Le='Legsday:BAAANQADCgQJBQAAAA==.Lementz:BAACNQAFFIEOAAIeAAQK8BRqDgBHAQAeAAQK8BRqDgBHAQA1AAQKgSAAAh4ACQrLHygaABUDAB4ACQrLHygaABUDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcIEgABNQAECgEIAQAFAAAAAA==.Libellule:BAAANQABCgQIBAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAABNQAECoEeAAIXAAcKghKSfQDAAQAXAAcKghKSfQDAAQAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAAANQAECggICAAAAA==.Loopku:BAAANQAECggICAAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECggIHwAOAIscAA==.',
Lu='Lumpia:BAABNQAECoEZAAMGAAkKyxhuMgA/AgAGAAkKyxhuMgA/AgAIAAIKuwUqrgBOAAAAAA==.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
Ma='Maey:BAABNQAECoEnAAMBAAkKzha1eQB0AgABAAkKfRS1eQB0AgAZAAEKASElNABTAAAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAABNQAECoElAAMeAAgK5RpOOABuAgAeAAgK5RpOOABuAgAdAAEK/Ag0LgBCAAAAAA==.Malpractice:BAAANQAECgEIAQABNQAECgYIEAAFAAAAAA==.Maybesinged:BAABNQAECoEnAAIBAAkKtBp7SgDeAgABAAkKtBp7SgDeAgAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAABNQAECoEpAAMgAAkKjiA8BABJAwAgAAkKjiA8BABJAwAiAAEKCRMZHwA5AAAAAA==.',
Mi='Midgetninja:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.Miltank:BAABNQAECoElAAIOAAkK+RuBSACVAgAOAAkK+RuBSACVAgAAAA==.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAABNQAECoEdAAIUAAkKOxmfFACqAgAUAAkKOxmfFACqAgAAAA==.Mionn:BAAANQAECgYIEgAAAA==.Misfires:BAAANQABCggIEwAAAA==.',
Ml='Mlleena:BAABNQAECoEZAAIYAAcKdhDQFwClAQAYAAcKdhDQFwClAQAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQAECgEIAQAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Montorgo:BAAANQADCgYIBgAAAA==.Moofi:BAAANQADCggIDgABNQAECgcIDgAFAAAAAA==.Mooncake:BAABNQAECoEeAAMgAAgKSAkkGgCJAQAgAAgKSAkkGgCJAQAiAAIK1QIxHgBBAAAAAA==.Moosiah:BAAANQADCgcIBwAAAA==.Motoko:BAABNQAECoEZAAMhAAgKKhszCwA9AgAhAAgKKhszCwA9AgAjAAEKQAJRTAAhAAAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møø:BAAANQADCggIDAABNQAECgYIEwAFAAAAAA==.Møøfi:BAAANQAECgcIDgAAAA==.',
Na='Naianasha:BAAANQAECgYICAAAAA==.Nameless:BAABNQAECoEoAAIBAAkKEhKahwBWAgABAAkKEhKahwBWAgAAAA==.Narc:BAAANQAECgUICgAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAAANQAECgcIEQAAAA==.Nevergreen:BAAANQABCgIIAgAAAA==.',
Ni='Nightreaver:BAAANQAECgQIBAABNQAECgYIEAAFAAAAAA==.Nippiest:BAAANQABCggICwAAAA==.',
No='Nokzash:BAAANQAECggIEAAAAA==.Noova:BAABNQAECoEjAAIBAAkKHB20VQDEAgABAAkKHB20VQDEAgAAAA==.',
Ny='Nyang:BAAANQAECgYIDQAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgkJHQAZAA0XAA==.',
Ob='Obliverat:BAAANQAECggIEAAAAA==.',
Od='Odysseus:BAAANQADCgIIBAAAAA==.',
Ok='Okiedokie:BAAANQADCgQIBAABNQAECgYIEAAFAAAAAA==.',
Oo='Oongaboonga:BAABNQAECoEgAAIEAAcKaBsYYgBJAgAEAAcKaBsYYgBJAgAAAA==.',
Or='Orcaneblast:BAABNQAECoEqAAIBAAkKgh5kQQDzAgABAAkKgh5kQQDzAgAAAA==.Orcsoup:BAAANQAECgYJEAABNQAECgkJHAAJANEZAA==.',
Pa='Paddord:BAAANQADCgcIBwAAAA==.Pandemnik:BAAANQAECgEIAQAAAA==.Paranoià:BAAANQADCgIIAgABNQAECgEIAQAFAAAAAA==.',
Pe='Penance:BAAANQAECgYICwAAAA==.Percible:BAAANQADCgYIBgAAAA==.',
Pi='Pivnert:BAABNQAECoEWAAQBAAYKRhiH1AC4AQABAAYKeBaH1AC4AQAZAAIKghQWKgCAAAAaAAEKvg0pCwA8AAAAAA==.',
Po='Popdkook:BAAANQADCgYIEgAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgYICAAAAA==.',
['Pü']='Pünish:BAACNQAFFIEGAAIGAAMKohiEDQADAQAGAAMKohiEDQADAQA1AAQKgUUABAYACQr4JAEHAH0DAAYACQr4JAEHAH0DACQAAwpxFQdmAMAAAAgAAQpfBaPBACsAAAAA.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Qu='Quinn:BAAANQADCgIJAgABNQAECgYIEAAFAAAAAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAABNQAECoEiAAMBAAkKPCDmPAD/AgABAAkK0h7mPAD/AgAZAAIKoCIVIQDAAAABNQAFFAcIHQABAP8dAA==.Ragingiscool:BAAANQADCggIDwAAAA==.Rail:BAAANQAECgEIAQAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAABNQAECoEcAAIVAAgKHhCfXQDcAQAVAAgKHhCfXQDcAQAAAA==.Ranuggul:BAAANQAECgEIAQAAAA==.Ratsrepus:BAAANQADCgcICwAAAA==.Raza:BAAANQAECgQIDAABNQAFFAMIBgAGAKIYAA==.',
Re='Read:BAAANQAECgMIBAAAAA==.Reddawn:BAAANQADCgcIBwAAAA==.Remeras:BAAANQAECgYICQAAAA==.',
Ri='Riken:BAAANQAECgYIEwAAAA==.',
Ro='Roadi:BAAANQAECgMJAwABNQAECgkJKQAXAFofAA==.Roxer:BAABNQAECoEaAAIVAAkKpw5FTAAYAgAVAAkKpw5FTAAYAgAAAA==.',
Ru='Rummyy:BAAANQAFFAEIAQAAAA==.',
Ry='Rycken:BAABNQAECoEcAAMKAAgKWhrURwCgAQAKAAYKIxjURwCgAQAJAAUKAwvhOwALAQAAAA==.',
Sa='Saeylva:BAAANQAECgMIBAAAAA==.Saosis:BAAANQAECgYIBgAAAA==.Savage:BAAANQADCgIIAgAAAA==.Sayurri:BAAANQADCgEJAQAAAA==.',
Sc='Scribble:BAAANQAECgMIBAAAAA==.Sculper:BAAANQAECgUIEAAAAA==.',
Se='Senica:BAAANQAECgYICwAAAA==.Seriphina:BAAANQADCggICAAAAA==.',
Sg='Sgornyweaver:BAAANQADCgUJBQAAAA==.',
Sh='Shabbarankzz:BAABNQAECoEiAAIkAAgK+RKHLAADAgAkAAgK+RKHLAADAgAAAA==.Shadetotem:BAAANQAECgUIEQAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCggIFwAAAA==.Shiftor:BAAANQADCgUICgAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQADCgcIEwAAAA==.Shradehn:BAABNQAECoEZAAITAAkKRRfzJABNAgATAAkKRRfzJABNAgAAAA==.Shutitdown:BAAANQAECgUIBQAAAA==.',
Si='Sisterswede:BAABNQAECoEdAAIQAAkKIx2+DwDhAgAQAAkKIx2+DwDhAgAAAA==.Sizzle:BAABNQAECoEZAAIBAAgKKhLOpAAYAgABAAgKKhLOpAAYAgAAAA==.',
Sm='Smokeahontas:BAAANQAECgQICQAAAA==.Smokindots:BAAANQAECgUIBQABNQAFFAIIBQAHAG4ZAA==.Smokingreen:BAAANQADCggJCAABNQAFFAIIBQAHAG4ZAA==.Smokinmyrrh:BAAANQAECgUIBQABNQAFFAIIBQAHAG4ZAA==.Smokinmyth:BAAANQADCgcICAAAAA==.Smokinpsalm:BAAANQAECgcICwABNQAFFAIIBQAHAG4ZAA==.Smokintotem:BAACNQAFFIEFAAIHAAIKbhnzFwCvAAAHAAIKbhnzFwCvAAA1AAQKgSwAAwcACQoFIz4JAGQDAAcACQoFIz4JAGQDAB4ABQrnFbOMAFMBAAAA.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEANQAECgQIBgABNQAFFAQICQAEAFYWAA==.Sparklnmagic:BAAANQADCgcIBwAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAAANQAECgcJEAAAAA==.Stemi:BAAANQAECgEIAQAAAA==.Steveirwin:BAAANQADCggJCAAAAA==.Stiffsheets:BAAANQAECgQIBAABNQAECgYIEAAFAAAAAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAAANQAECgcIDwAAAA==.Stormz:BAABNQAECoEgAAIKAAgK0hLEOAD/AQAKAAgK0hLEOAD/AQAAAA==.',
Su='Sunblade:BAAANQAECgUICwABNQAECgkJKAABABISAA==.Sundowning:BAAANQAECgUIBQAAAA==.Sunreaver:BAAANQADCgYIBgAAAA==.Supercappy:BAAANQAECgEIAQAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swabby:BAAANQADCgEIAQAAAA==.Swiftdragon:BAAANQAECgYIEAAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECggIGwABACkVAA==.Tackyh:BAABNQAECoEZAAICAAYKqh85ZQAfAgACAAYKqh85ZQAfAgAAAA==.Takamatsu:BAABNQAECoEhAAMMAAgKWyNrEgAiAwAMAAgKWyNrEgAiAwASAAMKDA5VFwCeAAAAAA==.Taku:BAAANQAECgIIBAAAAA==.Tar:BAAANQAECgYIEwAAAA==.Taxii:BAABNQAECoEiAAMEAAkKWyKPHQA0AwAEAAkKhyCPHQA0AwANAAYKlyJZBwBbAgAAAA==.',
Te='Tealnujabes:BAAANQAECgYIBwAAAA==.Teapots:BAAANQAFFAEIAQAAAA==.Tempi:BAAANQABCgMIAwABNQAECgYIBgAFAAAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thayelith:BAAANQAECgUIBAAAAA==.Thedeus:BAAANQAECgUICQABNQAECggIHwAOAIscAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAABNQAECoEhAAIdAAkKxBXXCwCcAgAdAAkKxBXXCwCcAgAAAA==.Threebeans:BAABNQAECoEcAAMJAAkK0Rn7DwC6AgAJAAkK0Rn7DwC6AgAKAAcKfhM7PgDbAQAAAA==.Thromir:BAACNQAFFIEGAAMVAAMKyA9MEwDsAAAVAAMKyA9MEwDsAAAOAAIKbiDzFQDFAAA1AAQKgRoAAxUACQoEIKYRADEDABUACQoEIKYRADEDAA4ABgoIJD9eAFICAAAA.Thyrn:BAABNQAECoEfAAIIAAgKFx3qIgCGAgAIAAgKFx3qIgCGAgAAAA==.',
Ti='Tirare:BAABNQAECoEaAAIGAAcKrBmaRwDSAQAGAAcKrBmaRwDSAQAAAA==.',
Tr='Tri:BAAANQAECgYIEQAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tuneleitor:BAAANQAECggIEgAAAA==.Turdferguson:BAAANQADCgcIBwABNQAFFAIIBAAFAAAAAA==.Turgrok:BAAANQAECgcIEQAAAA==.',
Tw='Twothang:BAAANQAECgYIEgAAAA==.',
Ty='Tyllan:BAABNQAECoEbAAMBAAkKhxu4nQAnAgABAAcKZxu4nQAnAgAZAAIK9xtKJgCcAAAAAA==.',
['Tâ']='Tâku:BAAANQADCggIHgAAAA==.',
Va='Vainhellsing:BAAANQAECgUICQAAAA==.Vanzier:BAAANQAECgcIEAAAAA==.Vaxis:BAABNQAECoEZAAICAAgKqg2PcQAAAgACAAgKqg2PcQAAAgAAAA==.',
Vi='Vid:BAACNQAFFIEKAAIjAAUKgReHAwCfAQAjAAUKgReHAwCfAQA1AAQKgSIAAiMACQofILQHAPsCACMACQofILQHAPsCAAAA.',
Vo='Voidillusion:BAAANQAECgMIAwABNQAECgYIBwAFAAAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAECgkJNwAXAA4kAA==.Wernov:BAABNQAECoEgAAMeAAgKihq9NwBxAgAeAAgKihq9NwBxAgAHAAUK5BCVlwAfAQABNQAECggIIgAMACoaAA==.',
Wh='Whitetail:BAAANQADCgEJAQAAAA==.',
Wi='Wichan:BAABNQAECoEbAAILAAgKXBseCwCAAgALAAgKXBseCwCAAgAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECggIGQAhACobAA==.Wiziviji:BAAANQAECgYICQAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Xa='Xanorea:BAAANQADCgYIBgABNQAECgYIEAAFAAAAAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQAECgUIBwAAAA==.',
Xr='Xray:BAAANQAECgUIEQAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQADCggIDQAAAA==.',
Ya='Yamii:BAAANQAECgcIDQABNQAECgkJGQAGAMsYAA==.Yaphetkotto:BAAANQADCgcJCAAAAA==.Yawnk:BAAANQAECgQICwAAAA==.',
Yu='Yunsky:BAAANQAECgEIAQAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAABNQAECoEnAAQHAAgKSRmrPQBAAgAHAAgKSRmrPQBAAgAdAAEK/wL1MQAwAAAeAAEKPQUpJwEpAAAAAA==.Zanosuke:BAAANQAECggIEgAAAA==.Zaria:BAAANQAECgUIEAAAAA==.Zaryor:BAABNQAECoEWAAMlAAcKIhW3KwCKAQAlAAcKhBO3KwCKAQAhAAQK4RTkHADsAAAAAA==.Zaun:BAAANQAECgUIBQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerica:BAAANQADCgQIBAAAAA==.Zerika:BAABNQAECoEiAAIMAAkK8R8HEAAxAwAMAAkK8R8HEAAxAwAAAA==.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIBQAAAA==.Zionna:BAAANQAECgYIEAABNQAECgYIEAAFAAAAAA==.',
Zo='Zomgqq:BAAANQAFFAEIAQAAAA==.',
Zy='Zydis:BAAANQAECgUICgAAAA==.Zyggy:BAAANQAECgQIBAAAAA==.Zynfanatic:BAAANQAECgQIBAAAAA==.',
['Än']='Ännihilation:BAAANQAECgIIAgAAAA==.',
['Èe']='Èepy:BAAANQAECgEIAQABNQAECgUIBQAFAAAAAA==.',
['És']='Éstéla:BAABNQAECoEgAAICAAkK1ROGTwBZAgACAAkK1ROGTwBZAgAAAA==.',
['Ío']='Ío:BAAANQAECgUICAAAAA==.',
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
