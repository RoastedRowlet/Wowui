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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Hunter-BeastMastery','Mage-Arcane','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Paladin-Retribution','Warrior-Arms','Shaman-Elemental','DeathKnight-Blood','Druid-Guardian','Druid-Balance','Druid-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Holy','Priest-Discipline','Hunter-Survival','Mage-Frost','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Hunter-Marksmanship','Warrior-Fury','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver','Rogue-Subtlety','Rogue-Assassination','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Monk-Brewmaster',}
local provider = {region='US',realm='Elune',name='US',type='weekly',zone=53,date='2026-09-29',data={Ae='Aelaya:BAAANQADCgQIBAAAAA==.Aeshen:BAAANQAECgUICAAAAA==.Aevea:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Ai='Aib:BAAANQAECgIJAwABNQAECgUICAABAAAAAA==.Aibe:BAAANQAECgUICAAAAA==.Aifertim:BAAANQADCgQIBAABNQAECgkJHQACADQcAA==.',
Ak='Akashah:BAABNQAECoEhAAIDAAgKLQolcQDUAQADAAgKLQolcQDUAQAAAA==.Akeno:BAAANQAECgEIAQAAAA==.',
Al='Alarick:BAAANQAECgMIBwAAAA==.Alatha:BAAANQADCgQIBAABNQAECggIHQAEABgdAA==.Alathasedai:BAABNQAECoEdAAIEAAgKGB07UwCxAgAEAAgKGB07UwCxAgAAAA==.Alathea:BAABNQAECoEiAAMFAAkK/h6ODgAoAwAFAAkK/h6ODgAoAwAGAAMKGwc1TQCAAAAAAA==.Aledis:BAABNQAECoEoAAIHAAkKgyX4AwCeAwAHAAkKgyX4AwCeAwAAAA==.Allanøn:BAAANQADCgYIEAAAAA==.',
Am='Amirial:BAAANQADCggIDgAAAA==.Amowrath:BAAANQAECgUIDwAAAA==.Amyasia:BAAANQAECgQIBwABNQAECgcIEwABAAAAAA==.',
An='Ancila:BAAANQADCgEIAQAAAA==.Anghúro:BAAANQADCgYICQABNQAECgIIAgABAAAAAA==.Angélica:BAAANQAECgYIDAAAAA==.Animethighs:BAAANQADCgcIFQAAAA==.Ankoou:BAAANQABCgUIBgAAAA==.Antifungal:BAAANQABCgIIAgAAAA==.',
Aq='Aquaskies:BAAANQAECgYICgABNQAECgcIDgABAAAAAA==.',
Ar='Arawynn:BAAANQAECgYIEwAAAA==.Archnessa:BAAANQAECggJAQAAAA==.Ariock:BAAANQAECgQICgAAAA==.Arknight:BAAANQAECgcIEgAAAA==.Artémís:BAAANQAECgEIAQAAAA==.',
As='Astreae:BAAANQAECgQIBwAAAA==.',
At='Atamus:BAAANQADCggJGwAAAA==.',
Av='Avanah:BAAANQADCgcIDQAAAA==.Avi:BAAANQAECgcIDAABNQAECgkJHgAHAAQeAA==.',
Ay='Aya:BAAANQAECgcIEgAAAA==.Ayekillu:BAAANQAECgYIEQAAAA==.Ayiasofia:BAABNQAECoEcAAIFAAgKIxiEMwBXAgAFAAgKIxiEMwBXAgAAAA==.Ayla:BAAANQAECgYIEAAAAA==.Aylan:BAAANQAECgYIDwAAAA==.Ayum:BAAANQADCgQIBAAAAA==.Ayumfox:BAABNQAECoEZAAIDAAgKmBxdKQC2AgADAAgKmBxdKQC2AgAAAA==.Ayumm:BAAANQADCggICAAAAA==.',
Az='Azapal:BAABNQAECoEfAAIIAAgKnxaqYQAdAgAIAAgKnxaqYQAdAgAAAA==.Azuros:BAAANQADCgUICAABNQAECgYIEQABAAAAAA==.',
Ba='Babyjezuz:BAAANQAECgQIDQAAAA==.Badger:BAABNQAECoEhAAIJAAkKLCO+CgCOAwAJAAkKLCO+CgCOAwAAAA==.Balloon:BAAANQADCggIFAAAAA==.Bandâid:BAAANQADCgYIDQABNQAECgcICwABAAAAAA==.Barathiel:BAABNQAECoEnAAIDAAkKjhR4QgBaAgADAAkKjhR4QgBaAgAAAA==.Barlow:BAAANQAECgEIAgAAAA==.Baryll:BAAANQAECgUIDQAAAA==.Batasu:BAABNQAECoEaAAMCAAgKsRcEQgANAgACAAgKsRcEQgANAgAKAAEKSw5W8gA9AAAAAA==.Baulde:BAABNQAECoEjAAILAAkKBQuMRwCYAQALAAkKBQuMRwCYAQAAAA==.',
Be='Beerbroth:BAAANQAECgcIEgAAAA==.Bellitrix:BAAANQADCggIDwAAAA==.',
Bi='Biefcake:BAABNQAECoEcAAIHAAgKvQf2UwBaAQAHAAgKvQf2UwBaAQAAAA==.Bigmoo:BAABNQAECoEoAAIMAAkKHx0eBQD4AgAMAAkKHx0eBQD4AgAAAA==.Bigoldotties:BAAANQAECgQIBwAAAA==.',
Bk='Bk:BAAANQAECgYIDQAAAA==.',
Bl='Blackparade:BAAANQAECgQIBgAAAA==.Blaydun:BAAANQAECgIIAgAAAA==.Blewboar:BAAANQAECgUIEAAAAA==.Bllass:BAAANQADCgUIGwAAAA==.Blueberrie:BAAANQAECgcIEwAAAA==.Blyzard:BAAANQAECgEIAQAAAA==.',
Bo='Boiledfrogz:BAABNQAECoEdAAMNAAkKNBGOLAA0AgANAAkKNBGOLAA0AgAOAAQKCQ7qOwDYAAAAAA==.Boned:BAABNQAECoEVAAIDAAkKDyE4DwBEAwADAAkKDyE4DwBEAwAAAA==.Boopboops:BAABNQAECoEUAAMCAAYKESIFMgBVAgACAAYKESIFMgBVAgAPAAIKuRDNJACEAAAAAA==.Bosleigor:BAAANQADCgYIBgAAAA==.',
Br='Bravehearthx:BAAANQAECgYIEAAAAA==.Bringerdk:BAAANQAFFAEIAQAAAA==.Bringerlk:BAAANQAECgUIBQAAAA==.Brogend:BAAANQAECgUIDgABNQAECgkJIQAJACwjAA==.Bronco:BAAANQAECgcIEgAAAA==.Brume:BAAANQADCgYIEQAAAA==.Brünhïnnä:BAAANQADCgYIDQAAAA==.',
Bu='Bubblntendre:BAAANQAECgcIEwAAAA==.',
Ca='Caféconron:BAABNQAECoEUAAIQAAgKGh/XBQB0AgAQAAgKGh/XBQB0AgAAAA==.Caitsidhe:BAAANQAECgcIEgAAAA==.Calinda:BAAANQADCgYICgABNQAECgYIEQABAAAAAA==.Cannute:BAAANQAECgQICQAAAA==.Canuckdruid:BAAANQAECgQIBQAAAA==.Canuckranger:BAAANQAECgQICwAAAA==.Canucksham:BAAANQAECgEIAgAAAA==.Captnubcakes:BAAANQAECgUIDQAAAA==.Carebear:BAACNQAFFIEHAAIRAAQKdA6NCwA5AQARAAQKdA6NCwA5AQA1AAQKgSQAAhEACQocHBAaAOMCABEACQocHBAaAOMCAAAA.Castallia:BAABNQAECoEbAAMFAAkKMRFhQAAfAgAFAAkKBhFhQAAfAgASAAMKBBBZFACmAAAAAA==.Catrathena:BAAANQADCggIEgAAAA==.',
Ce='Celeborn:BAAANQADCgYIBgAAAA==.Celta:BAAANQAECgIIAwAAAA==.',
Ch='Chaelis:BAABNQAECoEeAAIEAAkK0hy7OQD2AgAEAAkK0hy7OQD2AgAAAA==.Chainsoflove:BAAANQADCgQIBAAAAA==.Chalado:BAAANQADCgMIBAAAAA==.Chamanita:BAAANQAECgUIDQAAAA==.Charizzard:BAAANQADCgcIBwAAAA==.Chauny:BAAANQADCgYIDAAAAA==.Cheweh:BAAANQAECgYIBgAAAA==.Chilléd:BAAANQAECgcIBwAAAA==.Chisato:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.Chwamzrogue:BAAANQADCgIIAgAAAA==.',
Ci='Cindêr:BAAANQABCgYIBwAAAA==.Cisticola:BAAANQAECgcIEgAAAA==.Citi:BAAANQABCgIIAgAAAA==.Citii:BAAANQADCgQIBAAAAA==.',
Cl='Clair:BAABNQAECoEmAAIFAAkKehg8JwCSAgAFAAkKehg8JwCSAgAAAA==.Clova:BAABNQAECoEbAAIOAAcKPB3gFgA/AgAOAAcKPB3gFgA/AgAAAA==.',
Co='Combusty:BAAANQADCgEIAgAAAA==.Cornholyoh:BAABNQAECoEmAAIGAAkK5BbjFAB5AgAGAAkK5BbjFAB5AgAAAA==.Counsel:BAAANQAECgIIAgAAAA==.',
Cr='Cremefraiche:BAAANQAECgcICgAAAA==.Crillex:BAAANQADCgMIAwABNQAECgYIDwABAAAAAA==.Critkiller:BAAANQAECgMIBAAAAA==.Crulzilla:BAAANQAECgUICgAAAA==.',
Cu='Cuero:BAAANQADCgUIBQAAAA==.Cupcakemeow:BAABNQAECoEiAAITAAkKGRYkAwCnAgATAAkKGRYkAwCnAgAAAA==.Curas:BAAANQAECggIEAAAAA==.Curzøn:BAABNQAECoEsAAIUAAkKFSYmAADpAwAUAAkKFSYmAADpAwAAAA==.',
Cw='Cw:BAAANQAECgQIDQABNQADCgYJBwABAAAAAA==.Cwd:BAAANQADCgYJBwAAAA==.Cwds:BAAANQADCgcIEwABNQADCgYJBwABAAAAAA==.Cwoodz:BAAANQAECgYICgABNQADCgYJBwABAAAAAA==.',
Da='Dabubblez:BAAANQADCgUIBQAAAA==.Daedengerek:BAAANQAECgQICAAAAA==.Daggers:BAAANQADCgQIBAAAAA==.Daigz:BAAANQADCgYJCgAAAA==.Danerrin:BAACNQAFFIEFAAIVAAIKthsmCwCyAAAVAAIKthsmCwCyAAA1AAQKgSMAAwcACQobJAwZALkCAAcACAp5IwwZALkCABUABgoRIlYoAPYBAAAA.Dangersaur:BAAANQAECgcIEAAAAA==.Danielsan:BAAANQABCgYIBwAAAA==.Danigos:BAAANQAFFAcIGQAAAQ==.Darkcrushr:BAAANQADCgYICwAAAA==.Daryss:BAAANQADCgcIDAAAAA==.Daspirn:BAAANQADCgYICgAAAA==.Dawnkeeper:BAAANQAECgIIAgAAAA==.Dawnshott:BAAANQADCggIFwAAAA==.',
De='Deand:BAAANQABCgQIBAAAAA==.Deathadder:BAABNQAECoEjAAIDAAkKGyTwBAClAwADAAkKGyTwBAClAwAAAA==.Deathhounds:BAAANQADCgcIDAAAAA==.Deller:BAAANQADCgUIBgABNQADCgYIBgABAAAAAA==.Demiphant:BAAANQAECgYIDwAAAA==.Dennirn:BAAANQAECgIJAgABNQAFFAIIBQAVALYbAA==.Desna:BAAANQADCgUIBQAAAA==.',
Di='Diesalot:BAAANQAECgYIDQAAAA==.Divinedragon:BAAANQAECgUICAAAAA==.',
Do='Downstime:BAAANQADCgEIAQABNQAECgYIDQABAAAAAA==.',
Dr='Dracthar:BAAANQAECgEIAgAAAA==.Draczeal:BAAANQAECgEIAQAAAA==.Dragonlee:BAAANQADCgEIAQAAAA==.Dragovade:BAABNQAECoEZAAIKAAcK+A0AaACUAQAKAAcK+A0AaACUAQAAAA==.Dreadlocke:BAAANQAECgYIEAAAAA==.Dreidels:BAAANQADCggIEgABNQAECgYIEgABAAAAAA==.Drunkciggie:BAAANQAECgMIAwAAAA==.Drunky:BAAANQAECgEIAgAAAA==.Drysua:BAABNQAECoEmAAIGAAgK2hcwFwBbAgAGAAgK2hcwFwBbAgAAAA==.',
Du='Duffageddon:BAAANQADCgcIBwAAAA==.Duskmender:BAABNQAECoEbAAIIAAcKgRCHjQCgAQAIAAcKgRCHjQCgAQAAAA==.Duzick:BAAANQADCgUICAAAAA==.',
Dz='Dzmage:BAAANQAECggICQAAAA==.Dzshaman:BAAANQAECgEJAgAAAA==.Dzwarlock:BAABNQAECoEqAAIWAAkK8hUYRABFAgAWAAkK8hUYRABFAgAAAA==.',
['Dë']='Dëëds:BAAANQADCgYIEAAAAA==.',
Ec='Ecklyn:BAAANQADCgIIAgABNQAECggIGgACALEXAA==.',
Eg='Egino:BAAANQAECgMIBQAAAA==.',
El='Elanuo:BAAANQADCgYIDAAAAA==.Elarisiel:BAAANQADCggICAAAAA==.Elaynne:BAABNQAECoEcAAIDAAgKqyRaDwBDAwADAAgKqyRaDwBDAwAAAA==.Eldrith:BAAANQADCgIIAgABNQAECggIGgACALEXAA==.Eledis:BAAANQAECgIIBAAAAA==.Elemender:BAAANQAECgMJBgABNQAECgcIGwAIAIEQAA==.Elementrix:BAAANQAECggIBwAAAA==.Elfaa:BAAANQADCgEIAwAAAA==.Elieth:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.Eliteelf:BAAANQAECgQIDQAAAA==.Ellenora:BAAANQADCgYIBgAAAA==.Ellmer:BAABNQAECoEaAAIDAAgKYRmhPABuAgADAAgKYRmhPABuAgAAAA==.Elnir:BAAANQADCgUIBQAAAA==.Elopeppe:BAAANQAECgEIAQAAAA==.Elorro:BAAANQAECgEIAQABNQAECgkJJgAGAOQWAA==.Eltaizari:BAAANQAECgYIDQAAAA==.Elthiør:BAAANQAECgcIEQAAAA==.Elumiel:BAAANQAECgYIDAAAAA==.Elunedorei:BAAANQADCgcICgAAAA==.Elunelol:BAAANQAFFAIIAwABNQAFFAUIDgAOABIXAA==.Elwesingollo:BAAANQADCgYICwAAAA==.',
En='Enilia:BAABNQAECoEeAAIXAAkKyxuIAwDvAgAXAAkKyxuIAwDvAgAAAA==.Enrgizernelf:BAAANQAECgUICQAAAA==.',
Eo='Eo:BAAANQADCggICAAAAA==.',
Er='Erathena:BAAANQADCgYIBgAAAA==.Eriya:BAAANQAFFAEIAQAAAA==.Erryck:BAAANQAECggIAQAAAA==.',
Es='Esmeray:BAAANQADCgIIAgABNQAECgcIGwAIAIEQAA==.Estalea:BAAANQADCgIIAgAAAA==.Estideeslol:BAAANQAECgUICAAAAA==.',
Eu='Euphonia:BAAANQAECgEIAQAAAA==.',
Ey='Eyllis:BAAANQAECgYIEAAAAA==.',
Ez='Ezareth:BAAANQADCgUIBQAAAA==.',
Fa='Faded:BAAANQAECgIIAQAAAA==.Faedark:BAAANQADCgMIAgAAAA==.Farastraza:BAAANQADCgYICgAAAA==.',
Fe='Feralscar:BAAANQADCgQIBAAAAA==.Ferangdh:BAAANQAECgQIBwABNQAECgcIEgABAAAAAA==.Fevion:BAAANQAECgYIDAAAAA==.Fevius:BAAANQAECgUIDAABNQAECgYIDAABAAAAAA==.',
Fh='Fhantomgrave:BAAANQAECgYIDgAAAA==.',
Fi='Finduilas:BAABNQAECoEhAAIYAAgKLhwLCQBvAgAYAAgKLhwLCQBvAgAAAA==.Firepower:BAABNQAECoEYAAIEAAgKEBuqXgCVAgAEAAgKEBuqXgCVAgAAAA==.Firepriest:BAABNQAECoEYAAIGAAcK0BHcJAC3AQAGAAcK0BHcJAC3AQAAAA==.Firesdruid:BAAANQADCggIFwABNQAECgcIGAAGANARAA==.Fistu:BAAANQADCgQIBAAAAA==.',
Fl='Flagon:BAAANQADCgcIDAABNQAECgUICgABAAAAAA==.Flappyjacks:BAAANQAECgQICgAAAA==.Flappystraza:BAAANQAECgYICwAAAA==.Fleabane:BAAANQABCgIIAgAAAA==.Flickka:BAAANQAECgYICAAAAA==.',
Fo='Fourteen:BAAANQAECgMIAwAAAA==.Fourus:BAAANQADCggIHQAAAA==.',
Fr='Freakaleake:BAAANQAECgEJAgAAAA==.Freeport:BAACNQAFFIEGAAIEAAQKkSPUEQCZAQAEAAQKkSPUEQCZAQA1AAQKgRwAAgQACQrgI40ZAF0DAAQACQrgI40ZAF0DAAAA.Freezerburn:BAAANQAECgYJBgABNQAECgYIEAABAAAAAA==.Frostmender:BAAANQADCggICAABNQAECgcIGwAIAIEQAA==.Frostypillz:BAAANQABCgEIAQAAAA==.Frtouches:BAAANQAECgQIBgABNQAECgUIBgABAAAAAA==.',
Fu='Funnymuffin:BAABNQAECoEaAAMXAAgK3A3eJwAjAQAWAAcKPw53egCYAQAXAAUKpAreJwAjAQAAAA==.Furyia:BAAANQAECgQIBAAAAA==.Furyk:BAAANQAECgYJCQAAAA==.Fuzzleprime:BAABNQAECoEaAAIMAAcKMho0DQAYAgAMAAcKMho0DQAYAgAAAA==.Fuzzy:BAAANQADCgUIBQAAAA==.',
['Fä']='Fäye:BAAANQADCgIIAgAAAA==.',
Ga='Gaebora:BAAANQADCggIGwAAAA==.Gahmull:BAAANQADCggIDQAAAA==.Galleae:BAABNQAECoEaAAIFAAgKxRBdVADLAQAFAAgKxRBdVADLAQAAAA==.Garmart:BAABNQAECoEdAAMDAAgK8CBaGgD9AgADAAgK8CBaGgD9AgAZAAgKPgzfKAC2AQAAAA==.Gauza:BAAANQAECgEIAgAAAA==.',
Gh='Ghouldann:BAAANQAECgYIDQAAAA==.',
Gi='Gionathir:BAAANQAECgUICQAAAA==.',
Gl='Glaakii:BAAANQADCgIJAgAAAA==.Glagglag:BAABNQAECoEiAAIaAAkKSR/1AQA5AwAaAAkKSR/1AQA5AwAAAA==.',
Go='Goldeen:BAAANQAECgcIEgAAAA==.Gorothraex:BAAANQAECgEIAQAAAA==.',
Gr='Graxion:BAAANQAECgQIBgAAAA==.Greggiiee:BAAANQAECgIJAgAAAA==.Grimmaw:BAAANQAECgQIBAAAAA==.Grindelwald:BAAANQADCggIIAAAAA==.',
Gu='Guacamelee:BAAANQAECgMIBQAAAA==.',
Gw='Gwuak:BAAANQADCgcIHQAAAA==.Gwynorra:BAAANQAECgQIBwAAAA==.',
Ha='Habibi:BAAANQAECgcIEwAAAA==.Haralda:BAAANQAECgcICgAAAA==.Harshblue:BAABNQAECoEfAAMbAAgKHiTNCwCbAgAIAAcK8yW2KgDiAgAbAAgKXB7NCwCbAgAAAA==.Haste:BAAANQADCgEIAQAAAA==.Hatt:BAAANQAECgcIDgAAAA==.Hatts:BAAANQAECgEJAQAAAA==.Hawtnhordy:BAAANQADCgMIAwAAAA==.',
He='Healeydan:BAACNQAFFIEFAAIFAAIKpya/FADqAAAFAAIKpya/FADqAAA1AAQKgSMABAUACQppJdYEAIsDAAUACQpQJdYEAIsDABIABwo8INkDAG4CAAYAAgriCxVUAF0AAAAA.Heddh:BAABNQAECoEcAAQcAAkKdx2XGgCAAgAcAAgKrhqXGgCAAgAQAAIKxiSOFgDZAAAdAAQKKQt3QwDYAAABNQAECggIHgAOALciAA==.Heddruid:BAABNQAECoEeAAMOAAgKtyKwCAAMAwAOAAgKtyKwCAAMAwAMAAEK/gx2QwAoAAAAAA==.Hentaya:BAAANQAECgEIAQABNQABCgQIBAABAAAAAA==.Herrick:BAAANQAECggICAAAAA==.Heythanksman:BAAANQADCggJDgAAAA==.Heyzuse:BAAANQAECgUICgAAAA==.',
Hi='Hippay:BAAANQAECgUICgAAAA==.',
Ho='Hoid:BAAANQAECgQIBQAAAA==.Holynihalus:BAACNQAFFIEHAAIFAAQKch6PCwCEAQAFAAQKch6PCwCEAQA1AAQKgSAAAgUACQoMHKgkAJ8CAAUACQoMHKgkAJ8CAAAA.Holypowerr:BAAANQAECgEIAQABNQAECgkJHQACADQcAA==.Holyspoons:BAABNQAECoEhAAIIAAkKvBYzUgBOAgAIAAkKvBYzUgBOAgAAAA==.Homar:BAAANQAECgQICQABNQAECgUIBgABAAAAAA==.Hoopa:BAACNQAFFIETAAIeAAcKEhh5AQBjAgAeAAcKEhh5AQBjAgA1AAQKgRgAAh4ACQpfISYRAJcCAB4ACQpfISYRAJcCAAAA.Hordemender:BAAANQADCggJDwABNQAECgcIGwAIAIEQAA==.Houndsglory:BAAANQAECgMIBAAAAA==.Houndwar:BAAANQADCgYIDAAAAA==.',
Hu='Huggs:BAAANQAECgYICgAAAA==.Hunterama:BAAANQADCgUIBQAAAA==.Huntli:BAAANQAECgUIDQAAAA==.Huntrix:BAAANQAECgQIBgAAAA==.Huricaine:BAAANQAECgEIAgAAAA==.',
['Hé']='Hécate:BAABNQAECoEfAAIfAAgKcx2UCwCTAgAfAAgKcx2UCwCTAgAAAA==.',
Ic='Icecreamcake:BAACNQAFFIEUAAIFAAYKmAZjBwDOAQAFAAYKmAZjBwDOAQA1AAQKgSIAAgUACQomGeUnAI4CAAUACQomGeUnAI4CAAAA.Icyy:BAAANQAECgQIBQAAAA==.',
Id='Idontpaint:BAAANQADCgUIBQABNQABCgQIBAABAAAAAA==.',
Il='Ilithya:BAAANQAECgEIAgAAAA==.Illidansdad:BAAANQAECgIIAgAAAA==.',
Io='Ioana:BAAANQAECgEIAQAAAA==.',
Ip='Iphei:BAAANQAECggIDgAAAA==.',
Ir='Irulanni:BAABNQAECoEjAAIDAAkKbhLtOgB0AgADAAkKbhLtOgB0AgAAAA==.',
Is='Ishanaxade:BAABNQAECoEWAAIGAAcKCRWbIgDQAQAGAAcKCRWbIgDQAQAAAA==.',
Iv='Iva:BAABNQAECoEeAAIHAAkKBB4rFgDRAgAHAAkKBB4rFgDRAgAAAA==.Ivanov:BAAANQADCggIFAAAAA==.',
Iz='Izzie:BAAANQADCgcIBwAAAA==.',
Ja='Jackybrennan:BAAANQADCgcIBwABNQAECgcIEwABAAAAAA==.Jagershaii:BAAANQADCggJGwAAAA==.Jaketm:BAAANQADCgQIBAAAAA==.Jalaven:BAAANQAECgUIEAAAAA==.Jano:BAAANQAECgQIBQAAAA==.Jas:BAAANQAECgQICAAAAA==.Jawsh:BAAANQAECgYIBgAAAA==.',
Je='Jecka:BAAANQAECgQIBwAAAA==.Jentle:BAAANQAECgYICgAAAA==.Jessicka:BAAANQAECgUICwAAAA==.Jesûs:BAAANQADCgUIBQAAAA==.',
Ji='Jibbywibby:BAAANQADCgIIBAABNQAECggIGgAPAM4fAA==.Jibreel:BAAANQAECgEIAQAAAA==.Jinyla:BAAANQADCgQIBQAAAA==.Jinzho:BAAANQAECgYIDgAAAA==.Jiynila:BAAANQAECgMIBAAAAA==.',
Jo='Johey:BAABNQAECoEcAAMKAAgK5h7LNABgAgAKAAcKKB/LNABgAgACAAgKUgqCawByAQABNQABCgUIBQABAAAAAA==.Jorzul:BAAANQADCgMIAwAAAA==.',
Ju='Juanchoxch:BAAANQAECgIJAwAAAA==.Justinian:BAAANQABCgMIAQAAAA==.Juvenate:BAABNQAECoEWAAIOAAcKUiVLCgDvAgAOAAcKUiVLCgDvAgAAAA==.Juyani:BAAANQAECgMIBgAAAA==.',
Ka='Kailyn:BAAANQADCgIIAgAAAA==.Kalici:BAAANQADCgUIBQAAAA==.Kanab:BAAANQAECgIJAwABNQAECggIDwABAAAAAA==.Kayllea:BAAANQADCgYIFwABNQADCggIHwABAAAAAA==.Kaytara:BAABNQAECoEWAAIMAAcK0wpIHAA0AQAMAAcK0wpIHAA0AQAAAA==.',
Ke='Keharn:BAAANQADCgcIHQAAAA==.Kellen:BAACNQAFFIERAAIFAAYKfiN3AQCJAgAFAAYKfiN3AQCJAgA1AAQKgS0AAgUACQokJb8GAHMDAAUACQokJb8GAHMDAAAA.Keloros:BAAANQADCgYICwAAAA==.Kenós:BAAANQAECgcIDwAAAA==.Kettock:BAAANQAECgQIBQAAAA==.Kevzorg:BAAANQABCgMIAwAAAA==.',
Kh='Khae:BAAANQABCgYICgAAAA==.',
Ki='Kierk:BAAANQADCgUIBAAAAA==.Kilj:BAABNQAECoEaAAIWAAcKpxY6XgDuAQAWAAcKpxY6XgDuAQAAAA==.Kinuran:BAABNQAECoEjAAMKAAkKAxpQJQC2AgAKAAkKAxpQJQC2AgAPAAEKTgPkLAAwAAAAAA==.Kitherry:BAAANQAECgUIDQAAAA==.',
Kn='Knifeprty:BAAANQAECgEIAQAAAA==.',
Ko='Koristil:BAAANQADCgYIBwAAAA==.Kowdrak:BAAANQAECgQIBQABNQAECgYIDgABAAAAAA==.Kowmann:BAAANQABCgcJBwABNQAECgYIDgABAAAAAA==.',
Kr='Kreapen:BAAANQAECgUICwAAAA==.Krisdk:BAACNQAFFIEGAAMHAAUKRxWjBgBAAQAHAAQKxRijBgBAAQALAAEKUAehKwAhAAA1AAQKgSgAAgcACQpHI7sOABcDAAcACQpHI7sOABcDAAAA.Krisevoker:BAAANQAECgcIEgABNQAFFAUIBgAHAEcVAA==.',
Kt='Ktosh:BAAANQAECgEIAQAAAA==.',
Ku='Kurenäi:BAAANQAECgUICgAAAA==.Kurzul:BAAANQADCgMIAwAAAA==.',
Kw='Kwerin:BAAANQAECgEJAQAAAA==.',
['Kí']='Kírî:BAACNQAFFIELAAIOAAUK0hqmAgDZAQAOAAUK0hqmAgDZAQA1AAQKgSQAAg4ACQoIGmgRAIgCAA4ACQoIGmgRAIgCAAAA.',
['Kö']='Körialstrasz:BAAANQAECgQIBwABNQAECgUICQABAAAAAA==.',
La='Lacus:BAABNQAECoEjAAIIAAkKFSLNEQBhAwAIAAkKFSLNEQBhAwAAAA==.Larat:BAAANQAECgEIAQAAAA==.Laufeyson:BAAANQADCgcIEQAAAA==.Layara:BAAANQADCgUIBQAAAA==.Layil:BAAANQAECgEIAgAAAA==.Laymonath:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Lazanya:BAAANQAECgUICwAAAA==.',
Le='Legolamb:BAAANQAECgUIDgAAAA==.Leviasaint:BAABNQAECoEhAAIFAAgKvhCETwDfAQAFAAgKvhCETwDfAQAAAA==.',
Lh='Lhadnire:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.',
Li='Lifeinsuranc:BAAANQADCgUICQAAAA==.Lightstim:BAAANQADCgIIAgAAAA==.Lightswitch:BAAANQADCgIIAgABNQAECgUICgABAAAAAA==.Lilito:BAAANQAECgQIBQAAAA==.Limewire:BAAANQAECgcIDwAAAA==.Lion:BAAANQAECgIIAgAAAA==.',
Lo='Lodtuspuch:BAAANQABCgEIAQAAAA==.Lofie:BAAANQAECgcIEgAAAA==.Lonesnipa:BAAANQADCggIFwAAAA==.Looseyjoosey:BAAANQAECgYIEgAAAA==.Louiswu:BAAANQAECgcIEwAAAA==.',
Lu='Luciferias:BAABNQAECoEWAAMVAAcK1BNPMwClAQAVAAcK1BNPMwClAQALAAEKigxStQAnAAAAAA==.Luckyzounds:BAAANQABCgEIAQAAAA==.Lunariya:BAAANQAECgQIBwAAAA==.',
Ly='Lyz:BAAANQAECgEIAgAAAA==.',
Ma='Madreezov:BAAANQAECgcICQAAAA==.Madreezus:BAAANQAECgcIDQAAAA==.Magdalayna:BAAANQADCggICAABNQADCggICAABAAAAAA==.Mahjikman:BAAANQAECgEIAQAAAA==.Malfron:BAAANQADCgEIAQAAAA==.Malifrion:BAAANQADCgQJBAAAAA==.Mangodemon:BAACNQAFFIEIAAMdAAUKehRwBQCPAQAdAAUKFBNwBQCPAQAcAAEKTxGHFABKAAA1AAQKgSAABB0ACQoeIb4KABQDAB0ACQr2IL4KABQDABAABAoFJfoLAKsBABwABApsFdRGABwBAAAA.Mangopally:BAAANQAECgEIAgABNQAFFAUICAAdAHoUAA==.Mantheon:BAAANQAECgYIDAAAAA==.Marvel:BAABNQAECoEbAAIIAAkK8h2QJgD0AgAIAAkK8h2QJgD0AgAAAA==.Mastadonian:BAAANQAECgQIBwAAAA==.Matak:BAAANQADCgcJBwAAAA==.Maybedos:BAAANQADCggIHAAAAA==.Mayuki:BAABNQAECoElAAIMAAkKwSRIAQC0AwAMAAkKwSRIAQC0AwAAAA==.',
Me='Melmard:BAAANQABCgMIBAAAAA==.Meowfurion:BAAANQADCgIIAgAAAA==.Mezzocleeze:BAAANQAECgQJBwABNQAECgQIDwABAAAAAA==.',
Mi='Minä:BAABNQAECoEYAAMFAAcKdRu+RAAMAgAFAAcKdRu+RAAMAgAGAAEK3QPjbgAgAAAAAA==.Miquella:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Mirrari:BAAANQAECgEIAgAAAA==.Misschill:BAAANQADCgMIAwAAAA==.Missdumpling:BAAANQADCgUIBQAAAA==.',
Mo='Mogin:BAABNQAECoEdAAICAAkKNBx9GQDbAgACAAkKNBx9GQDbAgAAAA==.Mohim:BAAANQADCgMIAwAAAA==.Molten:BAAANQAECgEIAgAAAA==.Moonsault:BAAANQABCgMIAgAAAA==.Morganite:BAAANQAECgEIAQAAAA==.Moronica:BAAANQAECgMIAwAAAA==.Morti:BAAANQADCgMIAwAAAA==.Mox:BAAANQAECgYICgAAAA==.',
Mu='Muehpera:BAAANQAECgYJDgAAAA==.Muya:BAAANQADCgYIBgAAAA==.',
My='Myrabeth:BAAANQADCggICAAAAA==.',
Na='Nadion:BAAANQADCgUIDwAAAA==.Naldon:BAAANQADCgUICQAAAA==.Naraine:BAAANQADCgYICAAAAA==.Nayhture:BAAANQADCgEIAQAAAA==.',
Ne='Nefka:BAAANQADCgYIBgAAAA==.Nefkhet:BAAANQADCggIFwAAAA==.Nephtyys:BAAANQAECgYIDQAAAA==.Nerfbat:BAAANQAECgUICwAAAA==.Nes:BAAANQAECgUICgAAAA==.Netra:BAAANQADCgEIAQAAAA==.',
Ni='Niavy:BAAANQAECgUICQAAAA==.Nightgecko:BAABNQAECoEjAAIZAAkK5hxCDAD0AgAZAAkK5hxCDAD0AgAAAA==.Nightshaded:BAAANQABCgYICAAAAA==.Nihavoker:BAAANQADCgUIBQAAAA==.Nineteen:BAAANQAFFAEIAQABNQAECgMIAwABAAAAAA==.Nisroth:BAAANQAECgcICQAAAA==.Nitro:BAAANQAECgUIBQAAAA==.Niávy:BAAANQAECgIIAgAAAA==.',
No='Noedos:BAAANQAECgcICgAAAA==.Nofoxgivn:BAAANQAECgEIAQAAAA==.Nogdem:BAAANQAECgUIDAAAAA==.Novaprime:BAAANQAECgYIDgAAAA==.Noyy:BAAANQADCgUJBAABNQADCgYIBgABAAAAAA==.',
['Nù']='Nùrse:BAAANQAECgcIBwAAAA==.',
Ob='Obeevoker:BAAANQAECgUIDQAAAA==.',
Oc='Ocala:BAAANQADCgMIAwAAAA==.',
Og='Ogryn:BAAANQADCgMIAwAAAA==.',
Om='Omgsogoth:BAAANQABCgEIAQAAAA==.',
Oo='Oopsimdead:BAAANQAECgQIBQAAAA==.',
Or='Orziver:BAAANQABCgIIAgAAAA==.',
Os='Ostï:BAAANQADCgYIBgABNQAECgkJIwAfAGMhAA==.',
Ot='Otosan:BAABNQAECoEaAAICAAgKhxe8OwAoAgACAAgKhxe8OwAoAgAAAA==.',
Pa='Palshi:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Pandariock:BAAANQAECgMIBAAAAA==.Pandfu:BAAANQAECgIIAgAAAA==.Parfait:BAAANQADCgYIBgAAAA==.Pawsatyou:BAAANQAECggIDgAAAA==.',
Pe='Peaberry:BAAANQADCggJCAABNQADCggICAABAAAAAA==.Peekãboo:BAABNQAECoEhAAIgAAkK8xzgBwDnAgAgAAkK8xzgBwDnAgAAAA==.Peewheewoo:BAAANQADCgcIHQAAAA==.Peliossa:BAAANQADCgcIDQAAAA==.Pelzy:BAAANQAECgQIBQAAAA==.Pepae:BAAANQAECgcIEgAAAA==.',
Ph='Pholia:BAAANQAECgIIAgAAAA==.',
Pi='Pieni:BAAANQADCgYIFAAAAA==.Pinkrose:BAAANQAECgEIAQAAAA==.Pizza:BAAANQAECgUIDAAAAA==.',
Pl='Platomatrixx:BAAANQADCgYICwAAAA==.',
Po='Poko:BAAANQADCggICgAAAA==.Pollyanna:BAAANQAECgEIAQAAAA==.Poony:BAABNQAECoEcAAMEAAgKriJBLwATAwAEAAgKriJBLwATAwAUAAEKCiBmKwBeAAABNQAECgkJJQAEAOojAA==.',
Pr='Proximus:BAAANQAECgEJAQABNQAECggIHAAFACMYAA==.',
Ps='Psyop:BAABNQAECoEmAAIFAAkKRCEZBwBuAwAFAAkKRCEZBwBuAwAAAA==.',
Pu='Punnyname:BAAANQAECgcIEQAAAA==.Purrsian:BAAANQAECgQIBAAAAA==.',
Qb='Qberks:BAABNQAECoEeAAIHAAgK8x3hIAB7AgAHAAgK8x3hIAB7AgAAAA==.',
Qu='Quaddh:BAAANQADCggIDAAAAA==.Quellif:BAAANQABCgcIDAAAAA==.Quincee:BAAANQAECgQIBAAAAA==.',
Ra='Radtiz:BAAANQADCgEIAQAAAA==.Raenin:BAAANQAECgUIBwAAAA==.Ragingdraem:BAABNQAECoEgAAIKAAgKeRwhKgCaAgAKAAgKeRwhKgCaAgAAAA==.Raidei:BAABNQAECoEZAAMhAAYKNBEmOAB0AQAhAAYKug8mOAB0AQAgAAUKZQ58KgA7AQAAAA==.Rainoffur:BAAANQAECgYIEAAAAA==.Rakeripwait:BAAANQADCgUICgAAAA==.Raoulqc:BAAANQADCgcIDAAAAA==.Ratatosk:BAAANQAECgUICgAAAA==.Rathan:BAABNQAECoEaAAIJAAcKGR+CTQBiAgAJAAcKGR+CTQBiAgAAAA==.Ravenanarchy:BAABNQAECoEjAAIcAAkKaxDrIwAvAgAcAAkKaxDrIwAvAgAAAA==.Rawheadrexx:BAAANQAECgIIAgAAAA==.',
Re='Redpawedfox:BAABNQAECoEZAAIOAAcKIxw3GAAuAgAOAAcKIxw3GAAuAgAAAA==.Redsun:BAAANQAECgUIBQAAAA==.Rekviem:BAAANQAECgIIBAAAAQ==.Remyz:BAAANQADCgUIBQAAAA==.Revie:BAAANQADCgQIBAAAAA==.',
Rh='Rhavaniel:BAAANQAECgQIBAAAAA==.',
Ri='Rielexia:BAAANQABCgYJBgAAAA==.Rikola:BAAANQAECgMJAwAAAA==.Rizzen:BAAANQADCggIFgAAAA==.',
Ro='Roderika:BAAANQAECgEIAQAAAA==.Rogmar:BAAANQABCgIIAgAAAA==.Royalnewb:BAACNQAFFIEGAAIEAAMKygRLKQDJAAAEAAMKygRLKQDJAAA1AAQKgSYAAxQACQrjGq4HACQCAAQACQrZEUJ3AFkCABQACApsHK4HACQCAAAA.Royston:BAABNQAECoEaAAIYAAcKmQxZFwBYAQAYAAcKmQxZFwBYAQAAAA==.',
Ru='Rucereal:BAAANQAECgQICwAAAA==.Rufous:BAAANQAECgYJDgAAAA==.',
Rw='Rwaga:BAAANQAECgIIBAAAAA==.',
Ry='Ryliea:BAAANQADCgMIAwAAAA==.Rynsidious:BAABNQAECoEhAAIcAAgKVxK/KgD1AQAcAAgKVxK/KgD1AQAAAA==.',
['Rã']='Rãin:BAAANQAECgMJBAABNQAECggIHwANAIoVAA==.',
['Rì']='Rìkú:BAAANQADCgUIBQAAAA==.',
Sa='Sabelle:BAAANQAECgEIAQAAAA==.Sableanne:BAAANQABCgYIDAAAAA==.Sabîne:BAAANQAECgUIEwAAAA==.Saeton:BAABNQAECoEjAAIbAAkKzhCTFQAAAgAbAAkKzhCTFQAAAgAAAA==.Sahlaris:BAAANQAECgUIDAAAAA==.Salno:BAAANQADCgUJCAAAAA==.Samsonite:BAABNQAECoEWAAIDAAgKohfgSQBDAgADAAgKohfgSQBDAgAAAA==.Sanji:BAAANQADCgIIAgAAAA==.Sariths:BAAANQABCggIEQAAAA==.Savreen:BAAANQADCgYIBgAAAA==.',
Sc='Scrubpal:BAAANQADCggIFAAAAA==.',
Se='Seasalt:BAAANQABCgEIAQAAAA==.Sekhmet:BAAANQADCgMIAwAAAA==.Sekstrasza:BAAANQADCggIEgAAAA==.Sens:BAAANQAECgUICgAAAA==.Serrik:BAAANQAECggIBgAAAA==.Sersilkyhair:BAAANQAECgYIEQAAAA==.',
Sh='Shamanoid:BAAANQAECgIJAgABNQAECgYIEAABAAAAAA==.Shasta:BAABNQAECoEXAAIIAAcK/xUyggC+AQAIAAcK/xUyggC+AQAAAA==.Shortieabc:BAAANQAECgEIAQAAAA==.Shortmark:BAAANQAECgMIAwAAAA==.Shozwar:BAABNQAECoEYAAMJAAgK/RjSaQAIAgAJAAcK9BrSaQAIAgAYAAUKMw7zHgD3AAAAAA==.',
Si='Siik:BAAANQAECggIDwAAAA==.Silaena:BAAANQAECgUICwAAAA==.Silverlocke:BAAANQAECgQIDwAAAA==.Sindaris:BAAANQAECgcIDgAAAA==.',
Sj='Sj:BAAANQADCgQIBAAAAA==.',
Sk='Skillbeam:BAAANQAECgcIBwAAAA==.Skillcrusade:BAAANQAECgMIBAAAAA==.Skillscales:BAACNQAFFIEGAAMiAAMKbA12BADlAAAiAAMKbA12BADlAAAjAAEKbwX9DAA+AAA1AAQKgSUAAyIACQoTIbcCAPgCACIACQqCH7cCAPgCACMACAqLIa4KAJUCAAAA.Skyfallen:BAAANQAECgIIAgAAAA==.',
Sl='Sleepydk:BAAANQAECgcIEgAAAA==.Slopysecondz:BAAANQAECgEIAQABNQAECgQIDQABAAAAAA==.Slovik:BAAANQAECgEIAgAAAA==.Slowbro:BAAANQADCgYIDwAAAA==.',
Sm='Smok:BAAANQAECgIIAgAAAA==.',
Sn='Snafflo:BAAANQAECgYICwAAAA==.Snekhet:BAABNQAECoEaAAMFAAcKXBcrSAD9AQAFAAcKXBcrSAD9AQAGAAcKcRQKJADAAQAAAA==.',
So='Softscars:BAAANQAECgIIAwAAAA==.Solanea:BAAANQAECgUIDAAAAA==.Solaura:BAAANQAECgUIBgAAAA==.Solo:BAAANQADCgMIAwABNQAECggIHwAJAHYeAA==.Sorcero:BAAANQAECgYIDAAAAA==.Sorcforce:BAAANQADCgUIBQAAAA==.Soultelage:BAAANQAECgIIAgAAAA==.Sourwine:BAAANQADCgYICQAAAA==.',
Sp='Spaceman:BAABNQAECoFFAAIJAAkKmSZmAQDwAwAJAAkKmSZmAQDwAwAAAA==.Spire:BAAANQADCggIMwAAAA==.Sporkeh:BAAANQADCgMIAwAAAA==.Spritedk:BAAANQADCgcIBwABNQAECggIGgARAEYiAA==.Spritemonk:BAAANQAECgQICgABNQAECggIGgARAEYiAA==.Spritepally:BAABNQAECoEaAAIRAAgKRiLFEAAjAwARAAgKRiLFEAAjAwAAAA==.Spritepriest:BAAANQAECgQICAABNQAECggIGgARAEYiAA==.',
St='Stellara:BAAANQADCgQIBwAAAA==.Stiff:BAAANQADCgQIBAAAAA==.Stiffmcgee:BAAANQAECgUIBgAAAA==.Stormdancer:BAABNQAECoExAAIPAAgKBR1aCADGAgAPAAgKBR1aCADGAgAAAA==.Stormpage:BAAANQAECgIIAwABNQAFFAIIAgABAAAAAA==.Strangiatie:BAAANQADCgYJBwAAAA==.Strych:BAAANQAECggIEgABNQAECggIJwAgALMeAA==.Stumpyfoot:BAAANQAECgcIEgAAAA==.Stygi:BAAANQAECgMIBQAAAA==.Stãrs:BAACNQAFFIEJAAINAAUKnBbaBwCjAQANAAUKnBbaBwCjAQA1AAQKgSkAAw0ACQqIIrsMAEgDAA0ACQqIIrsMAEgDAA4AAgpMBgtQAGIAAAAA.',
Su='Suki:BAAANQADCggICwAAAA==.Sulawesi:BAAANQADCggICAABNQADCggICAABAAAAAA==.Sultan:BAAANQAECgEIAQAAAA==.Surfacing:BAABNQAECoEjAAIDAAkKXiJICwBiAwADAAkKXiJICwBiAwAAAA==.',
Sy='Syntharia:BAABNQAECoEgAAMiAAgK4gdOCwBUAQAiAAgK4gdOCwBUAQAjAAcK4QIEJADbAAAAAA==.',
Ta='Taffigosa:BAAANQAECgYIEgAAAA==.Taffy:BAAANQADCggIEgAAAA==.Talomea:BAAANQAECgEIAgAAAA==.Tanthel:BAAANQAECgYIEQAAAA==.Taursain:BAAANQADCgYIBwAAAA==.',
Tb='Tbh:BAAANQAECgEIAQABNQAECgYIFAACABEiAA==.',
Te='Terranteal:BAAANQAECggIDgAAAA==.Terraquis:BAAANQAECgIIAgAAAA==.Terravolta:BAABNQAECoEhAAICAAkKXxCPRQD+AQACAAkKXxCPRQD+AQAAAA==.Testarossa:BAAANQAECgcIEgAAAA==.',
Th='Themage:BAAANQADCgQJBAABNQAECgYIDwABAAAAAA==.Therealvenat:BAABNQAECoEWAAMWAAcKYRCmcAC1AQAWAAcKYRCmcAC1AQAXAAEKHAbocgAuAAAAAA==.Thiccbiddies:BAABNQAECoEmAAIaAAgKrB3dAwC+AgAaAAgKrB3dAwC+AgAAAA==.Thort:BAAANQADCgQIBAAAAA==.Thunderwings:BAAANQAECgMIBQAAAA==.',
Ti='Tigan:BAAANQAECgYIEAAAAA==.Tigra:BAABNQAECoEgAAINAAkKwA11MQAQAgANAAkKwA11MQAQAgAAAA==.Timelord:BAAANQAECgUIBwAAAA==.Timeweaver:BAABNQAECoEjAAIkAAkKqwiXGwDMAQAkAAkKqwiXGwDMAQAAAA==.Tirione:BAAANQAECgYICwAAAA==.Tirogue:BAAANQADCgUIBgAAAA==.',
To='Toastshark:BAAANQAECgcIEgAAAA==.Toranaar:BAAANQADCggIDgAAAA==.Torpal:BAAANQADCggIFwABNQAECgcIFwAIAP8VAA==.Totorö:BAABNQAECoEfAAINAAgKihWbLAA0AgANAAgKihWbLAA0AgAAAA==.',
Tr='Traiturner:BAAANQAECgQIDAAAAA==.Trayfu:BAAANQAECgEIAQAAAA==.Treebeárd:BAAANQADCgIIAgAAAA==.Trice:BAAANQAECgQIDAABNQAECgYIBwABAAAAAA==.Trillion:BAAANQAECgYIEwAAAA==.Trostani:BAAANQAECgYIBQAAAA==.Truc:BAAANQADCgMIAwAAAA==.Trusker:BAAANQAECgQIBgAAAA==.',
Ts='Tsaavas:BAAANQAECgMIBwAAAA==.Tsereya:BAAANQADCgYIBgAAAA==.Tsugumomo:BAAANQADCggICAAAAA==.',
Tu='Tullandil:BAAANQABCgQIAgAAAA==.',
Tw='Twitty:BAAANQAECgUIDQABNQAFFAQIBwARAHQOAA==.',
Ty='Tyloestus:BAAANQAECgYJBwAAAA==.Tyragni:BAAANQAECgEIAQAAAA==.Tyravana:BAAANQADCgYIBgAAAA==.Tystriel:BAAANQAECgUICQAAAA==.',
['Tí']='Tíamat:BAAANQAECgYIDQAAAA==.',
Ul='Ulasar:BAAANQAECgIIAgAAAA==.',
Un='Unmilkable:BAAANQADCgUIBQAAAA==.Untarot:BAAANQADCgMJBAAAAA==.',
Va='Valdanyr:BAEANQAECgEIAgAAAA==.Valimar:BAAANQADCgEIAQABNQAECgcIEgABAAAAAA==.Vallenar:BAAANQAECgUIBgAAAA==.Valliant:BAAANQAECgIIAgABNQAECgYICgABAAAAAA==.Valnullis:BAAANQADCgUIBwAAAA==.Valorfist:BAAANQADCgQJBAAAAA==.Valídus:BAAANQADCgYIDwAAAA==.Vampteabag:BAAANQADCggIDQAAAA==.Vanden:BAAANQAECgUIBwABNQAECgcIBwABAAAAAA==.Varsi:BAACNQAFFIEFAAIDAAIKWRRxFwCkAAADAAIKWRRxFwCkAAA1AAQKgSIABAMACQo4IjQYAAoDAAMACQo4IjQYAAoDABMAAQpTCs0PADYAABkAAQr1BHdwADEAAAAA.',
Ve='Veetor:BAAANQAECgQICAAAAA==.Velash:BAAANQAECgYIEAAAAA==.Vendorin:BAAANQAECgEIAgAAAA==.Verratanikto:BAAANQAECggIBwAAAA==.Verwínd:BAAANQAECgcIEwAAAA==.',
Vi='Virusgt:BAAANQAECgQIBAAAAA==.Vitner:BAAANQAECgcIDQABNQAFFAEIAQABAAAAAA==.',
Vo='Voidbeam:BAAANQAECgQIBQAAAA==.Voidsta:BAAANQADCgIIAgAAAA==.Volgur:BAAANQADCggIHwAAAA==.Volker:BAABNQAECoEaAAIJAAcKhxgqcQDyAQAJAAcKhxgqcQDyAQAAAA==.',
Wa='Walk:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.',
We='Wemad:BAAANQAECgIIAgAAAA==.Wenotknow:BAABNQAECoEVAAIPAAcKLx0qDgBJAgAPAAcKLx0qDgBJAgAAAA==.',
Wi='Wife:BAABNQAECoEfAAIJAAgKdh46OQCqAgAJAAgKdh46OQCqAgAAAA==.Wildraubtier:BAAANQADCgIIAgAAAA==.',
Wo='Wormsloe:BAAANQADCgYIBgAAAA==.',
Xa='Xaida:BAABNQAECoEWAAMeAAcK6w6wKQBnAQAeAAcKOA2wKQBnAQAlAAQKUw54GwDPAAAAAA==.Xaldania:BAAANQADCggIEQAAAA==.',
Xc='Xcaps:BAAANQADCgcIBwAAAA==.',
Xu='Xuing:BAABNQAECoEjAAIfAAkKYyFCAwBhAwAfAAkKYyFCAwBhAwAAAA==.Xuingg:BAAANQAECgcICgABNQAECgkJIwAfAGMhAA==.',
Ya='Yarp:BAAANQADCgUIBQAAAA==.Yarro:BAABNQAECoEfAAIDAAgKLA0lWwAQAgADAAgKLA0lWwAQAgAAAA==.',
Ye='Yesdaddy:BAAANQADCggJHwAAAA==.',
Yl='Yliana:BAAANQAECgEIAQABNQAECgcIGwAIAIEQAA==.',
Yo='Yorozu:BAAANQAECgUICgAAAA==.Young:BAAANQADCgQICAABNQAECgcICwABAAAAAA==.Youngblud:BAAANQAECgcICwAAAA==.Youngplasma:BAAANQAECgEIAQABNQAECgcICwABAAAAAA==.Youngwarlock:BAAANQAECgMIAwABNQAECgcICwABAAAAAA==.Yourhealor:BAAANQADCgYIBgAAAA==.',
Yu='Yugi:BAAANQAECgYICgAAAA==.',
Za='Zaela:BAAANQADCgQIBAAAAA==.Zahira:BAAANQAECgUIEwAAAA==.Zatilia:BAAANQADCgMIAwAAAA==.Zax:BAAANQAECgYIDAAAAA==.Zaxtor:BAAANQADCgEIAQAAAA==.',
Ze='Zenatra:BAAANQADCgcIDAAAAA==.Zeroximo:BAABNQAECoEWAAIEAAcKTxSUrQDcAQAEAAcKTxSUrQDcAQAAAA==.',
Zi='Zieren:BAAANQADCgcIDQABNQAECgUICgABAAAAAA==.Zipline:BAAANQAECgcIEgAAAA==.Zirathiel:BAAANQAECgEIAQAAAA==.',
Zo='Zofie:BAAANQADCggIEwAAAA==.Zogz:BAAANQAECgUJCQAAAA==.Zombiexcat:BAAANQADCgQIBQAAAA==.Zorakiel:BAABNQAECoEYAAIIAAgK2Bu2SQBqAgAIAAgK2Bu2SQBqAgAAAA==.',
Zu='Zulema:BAAANQABCgQIBAAAAA==.',
Zw='Zwiebelle:BAAANQAECgUICgAAAA==.',
Zz='Zzyuniver:BAAANQADCggICAAAAA==.',
['ßl']='ßlight:BAAANQADCgMIAwAAAA==.',
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
