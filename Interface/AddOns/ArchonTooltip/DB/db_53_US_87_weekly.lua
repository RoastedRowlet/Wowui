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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Warrior-Arms','DeathKnight-Blood','Druid-Guardian','Paladin-Holy','Priest-Discipline','Mage-Arcane','Hunter-Survival','Mage-Frost','DeathKnight-Frost','Paladin-Retribution','Warlock-Demonology','Druid-Restoration','Warlock-Destruction','Warrior-Protection','Warrior-Fury','Paladin-Protection','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Marksmanship','Rogue-Subtlety','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Evoker-Preservation',}
local provider = {region='US',realm='Elune',name='US',type='weekly',zone=53,date='2026-09-22',data={Ae='Aelaya:BAAANQADCgQIBAAAAA==.Aeshen:BAAANQAECgUICAAAAA==.Aevea:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Ai='Aib:BAAANQAECgIJAwABNQAECgMJAwABAAAAAA==.Aibe:BAAANQAECgMJAwAAAA==.Aifertim:BAAANQADCgQIBAABNQAECgkJHQACADQcAA==.',
Ak='Akashah:BAABNQAECoEaAAIDAAcKhAlgcACcAQADAAcKhAlgcACcAQAAAA==.Akeno:BAAANQAECgEIAQAAAA==.',
Al='Alarick:BAAANQAECgMJBAAAAA==.Alatha:BAAANQADCgQIBAABNQAECgYIEgABAAAAAA==.Alathasedai:BAAANQAECgYIEgAAAA==.Alathea:BAABNQAECoEcAAMEAAkKeB6SCwAnAwAEAAkKeB6SCwAnAwAFAAMKGwcqQgCHAAAAAA==.Aledis:BAABNQAECoEeAAIGAAgKqyMDDgATAwAGAAgKqyMDDgATAwAAAA==.Allanøn:BAAANQADCgYIEAAAAA==.',
Am='Amalith:BAAANQADCgcIEwAAAA==.Amirial:BAAANQADCggJDAAAAA==.Amowrath:BAAANQAECgUJCgAAAA==.Amyasia:BAAANQAECgQIBwABNQAECgYJDAABAAAAAA==.',
An='Anghúro:BAAANQADCgYICQABNQADCgcIFAABAAAAAA==.Angélica:BAAANQAECgYIDAAAAA==.Animethighs:BAAANQADCgcIEQAAAA==.Ankoou:BAAANQABCgUJBgAAAA==.',
Aq='Aquaskies:BAAANQAECgYICgABNQAECgcJBwABAAAAAA==.',
Ar='Arawynn:BAAANQAECgUJDQAAAA==.Archnessa:BAAANQAECggJAQAAAA==.Ariock:BAAANQAECgQJBgAAAA==.Arknight:BAAANQAECgYJDwAAAA==.Artémís:BAAANQAECgEIAQAAAA==.',
As='Astreae:BAAANQAECgQIBwAAAA==.',
At='Atamus:BAAANQADCggJGwAAAA==.',
Av='Avanah:BAAANQADCgYIBgAAAA==.Avi:BAAANQAECgcICgABNQAECgkJGQAGADwcAA==.',
Ay='Aya:BAAANQAECgYJDwAAAA==.Ayekillu:BAAANQAECgYJCwAAAA==.Ayiasofia:BAAANQAECgYIEgAAAA==.Ayla:BAAANQAECgUJCgAAAA==.Aylan:BAAANQAECgUICQAAAA==.Ayumfox:BAAANQAECgcJDwAAAA==.Ayumm:BAAANQADCggICAAAAA==.',
Az='Azapal:BAAANQAECgYJEwAAAA==.Azuros:BAAANQADCgUICAABNQAECgYJEQABAAAAAA==.',
Ba='Babyjezuz:BAAANQAECgQICQAAAA==.Badger:BAABNQAECoEZAAIHAAgKNCR/EgBKAwAHAAgKNCR/EgBKAwAAAA==.Balloon:BAAANQADCggIFAAAAA==.Bandâid:BAAANQADCgYIDQABNQAECgcICwABAAAAAA==.Barathiel:BAABNQAECoEjAAIDAAkKBhSiMgBoAgADAAkKBhSiMgBoAgAAAA==.Barlow:BAAANQAECgEJAgAAAA==.Baryll:BAAANQAECgQICAAAAA==.Batasu:BAAANQAECgcJEAAAAA==.Baulde:BAABNQAECoEaAAIIAAgKEgs5QwB8AQAIAAgKEgs5QwB8AQAAAA==.',
Be='Beerbroth:BAAANQAECgYJDAAAAA==.Bellitrix:BAAANQADCgcJBwAAAA==.',
Bi='Biefcake:BAAANQAECgcIEQAAAA==.Bigmoo:BAABNQAECoEiAAIJAAkKiRziAwDzAgAJAAkKiRziAwDzAgAAAA==.Bigoldotties:BAAANQAECgIJAwAAAA==.',
Bk='Bk:BAAANQAECgQJBwAAAA==.',
Bl='Blackparade:BAAANQAECgQJBgAAAA==.Blaydun:BAAANQAECgIIAgAAAA==.Blewboar:BAAANQAECgUICwAAAA==.Bllass:BAAANQADCgUJFAAAAA==.Blueberrie:BAAANQAECgYIEgAAAA==.Blyzard:BAAANQADCgQJBgAAAA==.',
Bo='Boiledfrogz:BAAANQAECgcJEgAAAA==.Boned:BAABNQAECoEVAAIDAAkKDyHgCABmAwADAAkKDyHgCABmAwAAAA==.Boopboops:BAAANQAECgYJDgAAAA==.Bosleigor:BAAANQADCgYIBgAAAA==.',
Br='Bravehearthx:BAAANQAECgUICgAAAA==.Bringerdk:BAAANQAFFAEJAQAAAA==.Brogend:BAAANQAECgUICgABNQAECggJGQAHADQkAA==.Bronco:BAAANQAECgYJDwAAAA==.Brume:BAAANQADCgYJDAAAAA==.Brünhïnnä:BAAANQADCgQJBwAAAA==.',
Bu='Bubblntendre:BAAANQAECgcJEgAAAA==.',
Ca='Caféconron:BAAANQAECgQIDAAAAA==.Caitsidhe:BAAANQAECgYJDwAAAA==.Calinda:BAAANQADCgYICgABNQAECgUICwABAAAAAA==.Cannute:BAAANQAECgQICQAAAA==.Canuckdruid:BAAANQAECgEIAQAAAA==.Canuckranger:BAAANQAECgQJBwAAAA==.Canucksham:BAAANQAECgEJAQAAAA==.Captnubcakes:BAAANQAECgQICAAAAA==.Carebear:BAABNQAECoEgAAIKAAkKpRsXFADrAgAKAAkKpRsXFADrAgAAAA==.Castallia:BAABNQAECoEaAAMEAAgKoxJbPgDvAQAEAAgKchJbPgDvAQALAAMKBBA4EQCqAAAAAA==.Catrathena:BAAANQADCggIEgAAAA==.',
Ce='Celeborn:BAAANQADCgYIBgAAAA==.Celta:BAAANQAECgEIAQAAAA==.',
Ch='Chaelis:BAABNQAECoEWAAIMAAgKwhwhSQCwAgAMAAgKwhwhSQCwAgAAAA==.Chainsoflove:BAAANQADCgQIBAAAAA==.Chalado:BAAANQADCgMIBAAAAA==.Chamanita:BAAANQAECgQICAAAAA==.Charizzard:BAAANQADCgcJBwAAAA==.Chauny:BAAANQADCgYJBgAAAA==.Cheweh:BAAANQAECgYIBgAAAA==.Chilléd:BAAANQAECgcIBwAAAA==.Chisato:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.Chwamzrogue:BAAANQADCgIIAgAAAA==.',
Ci='Cisticola:BAAANQAECgYJDwAAAA==.Citi:BAAANQABCgIIAgAAAA==.Citii:BAAANQADCgQIBAAAAA==.',
Cl='Clair:BAABNQAECoEgAAIEAAkKEBhKIQCHAgAEAAkKEBhKIQCHAgAAAA==.Clova:BAAANQAECgYJEgAAAA==.',
Co='Combusty:BAAANQADCgEIAgAAAA==.Cornholyoh:BAABNQAECoEkAAIFAAkK1RWTDwCmAgAFAAkK1RWTDwCmAgAAAA==.Counsel:BAAANQAECgIIAgAAAA==.',
Cr='Cremefraiche:BAAANQAECgYJBwAAAA==.Crillex:BAAANQADCgMIAwABNQAECgYJCgABAAAAAA==.Critkiller:BAAANQAECgEIAQAAAA==.Crulzilla:BAAANQAECgQJBQAAAA==.',
Cu='Cuero:BAAANQADCgUIBQAAAA==.Cupcakemeow:BAABNQAECoEZAAINAAgKihYnAwB2AgANAAgKihYnAwB2AgAAAA==.Curas:BAAANQAECgQJCAAAAA==.Curzøn:BAABNQAECoElAAIOAAcKciaxAQAbAwAOAAcKciaxAQAbAwAAAA==.',
Cw='Cw:BAAANQAECgQICQAAAA==.Cwd:BAAANQADCgYJBwAAAA==.Cwds:BAAANQADCgcIEwABNQADCgYJBwABAAAAAA==.Cwoodz:BAAANQAECgQIBAABNQADCgYJBwABAAAAAA==.',
Da='Dabubblez:BAAANQADCgEIAQAAAA==.Daedengerek:BAAANQAECgQICAAAAA==.Daggers:BAAANQADCgQIBAAAAA==.Daigz:BAAANQADCgYJCgAAAA==.Danerrin:BAABNQAECoEgAAMGAAkKwiOADgAOAwAGAAgKeSOADgAOAwAPAAYKECA6IwDdAQAAAA==.Dangersaur:BAAANQAECgUICQAAAA==.Danielsan:BAAANQABCgYIBwAAAA==.Danigos:BAAANQAFFAYIFAAAAQ==.Darkcrushr:BAAANQADCgYICQAAAA==.Daryss:BAAANQADCgcIDAAAAA==.Daspirn:BAAANQADCgYICgAAAA==.Dawnshott:BAAANQADCggIFwAAAA==.',
De='Deand:BAAANQABCgQIBAAAAA==.Deathadder:BAABNQAECoEaAAIDAAgKmiSdCgBVAwADAAgKmiSdCgBVAwAAAA==.Deathhounds:BAAANQADCgcJDAAAAA==.Deller:BAAANQADCgUIBgABNQADCgYIBgABAAAAAA==.Demiphant:BAAANQAECgYJCgAAAA==.Dennirn:BAAANQAECgIJAgABNQAECgkJIAAGAMIjAA==.',
Di='Diesalot:BAAANQAECgQJBwAAAA==.Divinedragon:BAAANQAECgIJAwAAAA==.',
Dr='Dracthar:BAAANQAECgEJAQAAAA==.Draczeal:BAAANQAECgEJAQAAAA==.Dragonlee:BAAANQADCgEIAQAAAA==.Dragovade:BAAANQAECgYJDwAAAA==.Dreadlocke:BAAANQAECgUJCgAAAA==.Dreidels:BAAANQADCgcJCgABNQAECgYJDAABAAAAAA==.Drunkciggie:BAAANQAECgMIAwAAAA==.Drunky:BAAANQAECgEJAQAAAA==.Drysua:BAABNQAECoEeAAIFAAgKMRS/FQBHAgAFAAgKMRS/FQBHAgAAAA==.',
Du='Duffageddon:BAAANQADCgcIBwAAAA==.Duskmender:BAABNQAECoEXAAIQAAcKaBDCbwCuAQAQAAcKaBDCbwCuAQAAAA==.Duzick:BAAANQADCgUICAAAAA==.',
Dz='Dzmage:BAAANQAECggJAQAAAA==.Dzshaman:BAAANQAECgEJAgAAAA==.Dzwarlock:BAABNQAECoEdAAIRAAkKrxE/XAC1AQARAAkKrxE/XAC1AQAAAA==.',
['Dë']='Dëëds:BAAANQADCgUJCgAAAA==.',
Ec='Ecklyn:BAAANQADCgIIAgABNQAECgcJEAABAAAAAA==.',
Eg='Egino:BAAANQAECgIJAgAAAA==.',
El='Elanuo:BAAANQADCgYIDAAAAA==.Elarisiel:BAAANQADCggICAAAAA==.Elaynne:BAAANQAECgYIEwAAAA==.Eldrith:BAAANQADCgIIAgABNQAECgcJEAABAAAAAA==.Eledis:BAAANQAECgIIBAAAAA==.Elemender:BAAANQAECgMJBgABNQAECgcJFwAQAGgQAA==.Elementrix:BAAANQAECggIAQAAAA==.Elieth:BAAANQADCgUICQABNQADCggIDAABAAAAAA==.Eliteelf:BAAANQAECgQJCQAAAA==.Ellenora:BAAANQADCgYIBgAAAA==.Ellmer:BAAANQAECgYIDwAAAA==.Elnir:BAAANQADCgUIBQAAAA==.Elopeppe:BAAANQAECgEIAQAAAA==.Elorro:BAAANQAECgEIAQABNQAECgkJJAAFANUVAA==.Eltaizari:BAAANQAECgQIBwAAAA==.Elthiør:BAAANQAECgYJCwAAAA==.Elumiel:BAAANQAECgUJBwAAAA==.Elunedorei:BAAANQADCgcICgAAAA==.Elunelol:BAAANQAFFAIIAgABNQAFFAUIDQASAE8WAA==.Elwesingollo:BAAANQADCgYICwAAAA==.',
En='Enilia:BAABNQAECoEaAAITAAkKdxpiAwDpAgATAAkKdxpiAwDpAgAAAA==.Enrgizernelf:BAAANQAECgQJBAAAAA==.',
Eo='Eo:BAAANQADCggICAAAAA==.',
Er='Erathena:BAAANQADCgYIBgAAAA==.Eriya:BAAANQAFFAEJAQAAAA==.',
Es='Esmeray:BAAANQADCgIIAgABNQAECgcJFwAQAGgQAA==.Estalea:BAAANQADCgIIAgAAAA==.Estideeslol:BAAANQAECgIIAwAAAA==.',
Ey='Eyllis:BAAANQAECgYJEAAAAA==.',
Ez='Ezareth:BAAANQADCgUIBQAAAA==.',
Fa='Faded:BAAANQAECgIIAQAAAA==.Faedark:BAAANQADCgMIAgAAAA==.Farastraza:BAAANQADCgMJBAAAAA==.',
Fe='Feralscar:BAAANQADCgQIBAAAAA==.Ferangdh:BAAANQAECgQIBwABNQAECgYJDAABAAAAAA==.Fevion:BAAANQAECgQJBgAAAA==.Fevius:BAAANQAECgUJCAABNQAECgQJBgABAAAAAA==.',
Fh='Fhantomgrave:BAAANQAECgYJDgAAAA==.',
Fi='Finduilas:BAABNQAECoEaAAIUAAcK/RxaCABGAgAUAAcK/RxaCABGAgAAAA==.Firepower:BAAANQAECgYIEAAAAA==.Firepriest:BAAANQAECgYJDgAAAA==.Firesdruid:BAAANQADCgcJDwABNQAECgYJDgABAAAAAA==.Fistu:BAAANQADCgQIBAAAAA==.',
Fl='Flagon:BAAANQADCgUJBQABNQAECgUJCgABAAAAAA==.Flappyjacks:BAAANQAECgQJCQAAAA==.Flappystraza:BAAANQAECgMIBQAAAA==.Fleabane:BAAANQABCgIIAgAAAA==.Flickka:BAAANQAECgIIAgAAAA==.',
Fo='Fourteen:BAAANQAECgMJAwAAAA==.Fourus:BAAANQADCggJFgAAAA==.',
Fr='Freakaleake:BAAANQAECgEJAgAAAA==.Freeport:BAACNQAFFIEGAAIMAAQKkSNBCwCqAQAMAAQKkSNBCwCqAQA1AAQKgRwAAgwACQrgI4MQAHsDAAwACQrgI4MQAHsDAAAA.Freezerburn:BAAANQAECgYJBgAAAA==.Frostmender:BAAANQADCggICAABNQAECgcJFwAQAGgQAA==.Frostypillz:BAAANQABCgEIAQAAAA==.Frtouches:BAAANQAECgQIBgABNQAECgUIBgABAAAAAA==.',
Fu='Funnymuffin:BAABNQAECoEaAAMTAAgK3A36IwAtAQARAAcKPw65YACnAQATAAUKpAr6IwAtAQAAAA==.Furyia:BAAANQADCggJIAAAAA==.Furyk:BAAANQAECgYJCQAAAA==.Fuzzleprime:BAAANQAECgYJDwAAAA==.Fuzzy:BAAANQADCgUIBQAAAA==.',
Ga='Gaebora:BAAANQADCggIFgAAAA==.Gahmull:BAAANQADCggIDQAAAA==.Galleae:BAAANQAECgYJDwAAAA==.Garmart:BAAANQAECgcJEgAAAA==.Gauza:BAAANQAECgEJAQAAAA==.',
Gh='Ghouldann:BAAANQAECgYIBwAAAA==.',
Gi='Gionathir:BAAANQAECgMJBAAAAA==.',
Gl='Glaakii:BAAANQADCgIJAgAAAA==.Glagglag:BAABNQAECoEZAAIVAAgKmh3XAgDGAgAVAAgKmh3XAgDGAgAAAA==.',
Go='Goldeen:BAAANQAECgYJDwAAAA==.Gorothraex:BAAANQADCgcIEwAAAA==.',
Gr='Graxion:BAAANQAECgQIBgAAAA==.Greggiiee:BAAANQAECgIJAgAAAA==.Grimmaw:BAAANQAECgQIBAAAAA==.Grindelwald:BAAANQADCggJGAAAAA==.',
Gu='Guacamelee:BAAANQAECgEJAgAAAA==.',
Gw='Gwuak:BAAANQADCgYJFgAAAA==.Gwynorra:BAAANQAECgMJAwAAAA==.',
Ha='Habibi:BAAANQAECgcJDwAAAA==.Haralda:BAAANQAECgYJBwAAAA==.Harshblue:BAABNQAECoEYAAMQAAcK8yWTHQD5AgAQAAcK8yWTHQD5AgAWAAMKCRsVMwC4AAAAAA==.Hatt:BAAANQAECgcJDgAAAA==.Hatts:BAAANQAECgEJAQAAAA==.Hawtnhordy:BAAANQADCgMIAwAAAA==.',
He='Healeydan:BAABNQAECoEgAAQEAAkKaSUBAwCaAwAEAAkKUCUBAwCaAwALAAcKPCAvAwB2AgAFAAIK4gu4RwBkAAAAAA==.Heddh:BAAANQAECgcIEQABNQAECgYJEQABAAAAAA==.Heddruid:BAAANQAECgYJEQAAAA==.Heiligfeuer:BAAANQADCgcIFAAAAA==.Hentaya:BAAANQADCgYJFAABNQABCgIIAgABAAAAAA==.Herrick:BAAANQAECggICAAAAA==.Heythanksman:BAAANQADCggJDgAAAA==.Heyzuse:BAAANQAECgQJBQAAAA==.',
Hi='Hippay:BAAANQAECgQJBQAAAA==.',
Ho='Hoid:BAAANQAECgQIBQAAAA==.Holynihalus:BAABNQAECoEeAAIEAAkK8xvzGgCwAgAEAAkK8xvzGgCwAgAAAA==.Holypowerr:BAAANQAECgEIAQABNQAECgkJHQACADQcAA==.Holyspoons:BAABNQAECoEdAAIQAAkKahXdQQBLAgAQAAkKahXdQQBLAgAAAA==.Homar:BAAANQAECgQIBgABNQAECgUIBgABAAAAAA==.Hoopa:BAACNQAFFIESAAIXAAcKEhi4AACHAgAXAAcKEhi4AACHAgA1AAQKgRYAAhcACQq0ICgNAKwCABcACQq0ICgNAKwCAAAA.Hordemender:BAAANQADCggJDwABNQAECgcJFwAQAGgQAA==.Houndsglory:BAAANQAECgEIAQAAAA==.Houndwar:BAAANQADCgYIDAAAAA==.',
Hu='Huggs:BAAANQAECgYICgAAAA==.Hunterama:BAAANQADCgUIBQAAAA==.Huntli:BAAANQAECgQICAAAAA==.Huntrix:BAAANQAECgQIBgAAAA==.Huricaine:BAAANQAECgEJAQAAAA==.',
['Hé']='Hécate:BAABNQAECoEbAAIYAAgK3xqZCwBjAgAYAAgK3xqZCwBjAgAAAA==.',
Ic='Icecreamcake:BAACNQAFFIEOAAIEAAYKvgMBBgC0AQAEAAYKvgMBBgC0AQA1AAQKgSAAAgQACQomGdQdAJwCAAQACQomGdQdAJwCAAAA.Icyy:BAAANQAECgMIBAAAAA==.',
Id='Idontpaint:BAAANQADCgUIBQABNQABCgQIBAABAAAAAA==.',
Il='Ilithya:BAAANQAECgEIAgAAAA==.Illidansdad:BAAANQAECgIIAgAAAA==.',
Io='Ioana:BAAANQAECgEIAQAAAA==.',
Ip='Iphei:BAAANQAECgcJCwAAAA==.',
Ir='Irulanni:BAABNQAECoEaAAIDAAgKVRB1QwArAgADAAgKVRB1QwArAgAAAA==.',
Is='Ishanaxade:BAAANQAECgUJDgAAAA==.',
Iv='Iva:BAABNQAECoEZAAIGAAkKPBzODgAJAwAGAAkKPBzODgAJAwAAAA==.Ivanov:BAAANQADCgcJDAAAAA==.',
Iz='Izzie:BAAANQADCgcIBwAAAA==.',
Ja='Jackybrennan:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.Jagershaii:BAAANQADCggJGwAAAA==.Jaketm:BAAANQADCgQIBAAAAA==.Jalaven:BAAANQAECgQICwAAAA==.Jano:BAAANQAECgQIBQAAAA==.Jas:BAAANQAECgQIBAAAAA==.Jawsh:BAAANQAECgYIBgAAAA==.',
Je='Jecka:BAAANQAECgQIBwAAAA==.Jentle:BAAANQAECgYICgAAAA==.Jessicka:BAAANQAECgQJBgAAAA==.Jesûs:BAAANQADCgUIBQAAAA==.',
Ji='Jibbywibby:BAAANQADCgIIBAABNQAECggJGQAZAJMfAA==.Jibreel:BAAANQAECgEIAQAAAA==.Jinyla:BAAANQADCgQIBQAAAA==.Jinzho:BAAANQAECgQICAAAAA==.Jiynila:BAAANQAECgEJAQAAAA==.',
Jo='Johey:BAAANQAECgYJEgABNQABCgUIBQABAAAAAA==.',
Ju='Juanchoxch:BAAANQAECgIJAwAAAA==.Justinian:BAAANQABCgMIAQAAAA==.Juvenate:BAAANQAECgUJDgAAAA==.Juyani:BAAANQAECgEJAwAAAA==.',
Ka='Kailyn:BAAANQADCgIJAgAAAA==.Kaiyah:BAAANQADCgcIEwAAAA==.Kanab:BAAANQAECgIJAwABNQAECgcICwABAAAAAA==.Kayllea:BAAANQADCgYIFwABNQADCggJHwABAAAAAA==.Kaytara:BAAANQAECgUJDgAAAA==.',
Ke='Keharn:BAAANQADCgYJFgAAAA==.Kellen:BAACNQAFFIELAAIEAAUK3SITAwANAgAEAAUK3SITAwANAgA1AAQKgSYAAgQACQoPJSAFAHUDAAQACQoPJSAFAHUDAAAA.Keloros:BAAANQADCgYICwAAAA==.Kenós:BAAANQAECgUICAAAAA==.Kettock:BAAANQAECgEJAQAAAA==.Kevzorg:BAAANQABCgMIAwAAAA==.',
Ki='Kierk:BAAANQADCgUIBAAAAA==.Kilj:BAAANQAECgYJDwAAAA==.Kinuran:BAABNQAECoEaAAMaAAgKnxklKgBsAgAaAAgKnxklKgBsAgAZAAEKTgOXJwAxAAAAAA==.Kitherry:BAAANQAECgQICAAAAA==.',
Kn='Knifeprty:BAAANQAECgEIAQAAAA==.',
Ko='Koristil:BAAANQADCgUJAQAAAA==.Kowdrak:BAAANQAECgIIAgABNQAECgUJCAABAAAAAA==.Kowmann:BAAANQABCgcJBwABNQAECgUJCAABAAAAAA==.',
Kr='Kreapen:BAAANQAECgQIBgAAAA==.Krisdk:BAABNQAECoEkAAIGAAkKxyL/CABTAwAGAAkKxyL/CABTAwAAAA==.Krisevoker:BAAANQAECgYICwABNQAECgkJJAAGAMciAA==.',
Ku='Kurenäi:BAAANQAECgQIBQAAAA==.Kurzul:BAAANQADCgMIAwAAAA==.',
Kw='Kwerin:BAAANQAECgEJAQAAAA==.',
['Kí']='Kírî:BAABNQAECoEiAAISAAkK2hnJDQCLAgASAAkK2hnJDQCLAgAAAA==.',
['Kö']='Körialstrasz:BAAANQAECgQIBgABNQAECgUJCQABAAAAAA==.',
La='Lacus:BAABNQAECoEaAAIQAAgKKyGhIADoAgAQAAgKKyGhIADoAgAAAA==.Larat:BAAANQADCgYJDwAAAA==.Laufeyson:BAAANQADCgcJCwAAAA==.Layara:BAAANQADCgUIBQAAAA==.Layil:BAAANQAECgEIAgAAAA==.Laymonath:BAAANQADCgUJBQABNQADCgYIBgABAAAAAA==.Lazanya:BAAANQAECgQICgAAAA==.',
Le='Legolamb:BAAANQAECgQJCQAAAA==.Leviasaint:BAABNQAECoEaAAIEAAcKAQ8KUACbAQAEAAcKAQ8KUACbAQAAAA==.',
Lh='Lhadnire:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.',
Li='Lifeinsuranc:BAAANQADCgUICQAAAA==.Lightstim:BAAANQADCgIIAgAAAA==.Lilito:BAAANQAECgQIBQAAAA==.Limewire:BAAANQAECgYJDgAAAA==.',
Lo='Lodtuspuch:BAAANQABCgEIAQAAAA==.Lofie:BAAANQAECgYJDwAAAA==.Lonesnipa:BAAANQADCgcJDwAAAA==.Looseyjoosey:BAAANQAECgYJDAAAAA==.Louiswu:BAAANQAECgYIDAAAAA==.',
Lu='Luciferias:BAABNQAECoEWAAMPAAcK1BPoJQDFAQAPAAcK1BPoJQDFAQAIAAEKigy6nQAqAAAAAA==.Luckyzounds:BAAANQABCgEIAQAAAA==.Lunariya:BAAANQAECgQIBwAAAA==.',
Ly='Lyz:BAAANQAECgEJAQAAAA==.',
Ma='Madreezov:BAAANQAECgcICAAAAA==.Madreezus:BAAANQAECgYICgAAAA==.Magdalayna:BAAANQADCggICAABNQADCggICAABAAAAAA==.Malfron:BAAANQADCgEIAQAAAA==.Malifrion:BAAANQADCgQJBAAAAA==.Mangodemon:BAABNQAECoEcAAMbAAkKHiHdBwA3AwAbAAkK9iDdBwA3AwAcAAQKBSVfCQCyAQAAAA==.Mangopally:BAAANQAECgEIAgABNQAECgkJHAAbAB4hAA==.Mantheon:BAAANQAECgUIBgAAAA==.Marvel:BAABNQAECoEXAAIQAAkKMxsPKADAAgAQAAkKMxsPKADAAgAAAA==.Mastadonian:BAAANQAECgQIBAAAAA==.Matak:BAAANQADCgcJBwAAAA==.Maybedos:BAAANQADCggJFAAAAA==.Mayuki:BAABNQAECoEgAAIJAAkKeiTsAAC2AwAJAAkKeiTsAAC2AwAAAA==.',
Me='Melmard:BAAANQABCgMIBAAAAA==.Meowfurion:BAAANQADCgIIAgAAAA==.Mezzocleeze:BAAANQAECgQJBwABNQAECgQJDAABAAAAAA==.',
Mi='Minä:BAAANQAECgYJEQAAAA==.Miquella:BAAANQADCggICAABNQAECgUJCQABAAAAAA==.Mirrari:BAAANQAECgEJAQAAAA==.Misschill:BAAANQADCgMIAwAAAA==.Missdumpling:BAAANQADCgIIAgAAAA==.',
Mo='Mogin:BAABNQAECoEdAAICAAkKNBztEQD4AgACAAkKNBztEQD4AgAAAA==.Molten:BAAANQAECgEJAQAAAA==.Morganite:BAAANQADCgMIAwAAAA==.Moronica:BAAANQADCggJFQAAAA==.Mox:BAAANQAECgYJBgAAAA==.',
Mu='Muehpera:BAAANQAECgYJDgAAAA==.Muya:BAAANQADCgYIBgAAAA==.',
My='Myrabeth:BAAANQADCgYICAAAAA==.',
Na='Nadion:BAAANQADCgQJCwAAAA==.Naldon:BAAANQADCgUICQAAAA==.Naraine:BAAANQADCgYICAAAAA==.Nayhture:BAAANQADCgEIAQAAAA==.',
Ne='Nefka:BAAANQADCgYIBgAAAA==.Nefkhet:BAAANQADCgcJDwAAAA==.Nephtyys:BAAANQAECgYJDQAAAA==.Nerfbat:BAAANQAECgQJBgAAAA==.Nes:BAAANQAECgQIBQAAAA==.Netra:BAAANQADCgEIAQAAAA==.',
Ni='Niavy:BAAANQAECgUICQAAAA==.Nightgecko:BAABNQAECoEaAAIdAAgKkxn0FQBcAgAdAAgKkxn0FQBcAgAAAA==.Nightshaded:BAAANQABCgYJCAAAAA==.Nihavoker:BAAANQADCgUIBQAAAA==.Nineteen:BAAANQAFFAEIAQABNQAECgMJAwABAAAAAA==.Nisroth:BAAANQAECgcICQAAAA==.Nitro:BAAANQAECgUIBQAAAA==.Niávy:BAAANQAECgIIAgAAAA==.',
No='Noedos:BAAANQAECgMIAwAAAA==.Nofoxgivn:BAAANQAECgEIAQAAAA==.Nogdem:BAAANQAECgQIBwAAAA==.Novaprime:BAAANQAECgQJCAAAAA==.Noyy:BAAANQADCgUJBAABNQADCgYIBgABAAAAAA==.',
['Nù']='Nùrse:BAAANQAECgYJBgAAAA==.',
Ob='Obeevoker:BAAANQAECgQICAAAAA==.',
Oc='Ocala:BAAANQADCgMIAwAAAA==.',
Og='Ogryn:BAAANQADCgMIAwAAAA==.',
Om='Omgsogoth:BAAANQABCgEIAQAAAA==.',
Oo='Oopsimdead:BAAANQAECgQJBQAAAA==.',
Or='Orziver:BAAANQABCgIIAgAAAA==.',
Os='Ostï:BAAANQADCgYJBgABNQAECggJGgAYANMiAA==.',
Ot='Otosan:BAABNQAECoEZAAICAAgKhxcyKwBTAgACAAgKhxcyKwBTAgAAAA==.',
Pa='Palshi:BAAANQADCgMIAwABNQAECgQJBwABAAAAAA==.Pandariock:BAAANQAECgMIBAAAAA==.Parfait:BAAANQADCgYIBgAAAA==.Pawsatyou:BAAANQAECgcJCwAAAA==.',
Pe='Peaberry:BAAANQADCggJCAABNQADCggICAABAAAAAA==.Peachiekeen:BAAANQADCgcIEwAAAA==.Peekãboo:BAABNQAECoEhAAIeAAkK8xw5BgD/AgAeAAkK8xw5BgD/AgAAAA==.Peewheewoo:BAAANQADCgcJFgAAAA==.Peliossa:BAAANQADCgYIBgAAAA==.Pelzy:BAAANQAECgQIBQAAAA==.Pepae:BAAANQAECgcIEAAAAA==.',
Ph='Pholia:BAAANQADCgcIGQAAAA==.',
Pi='Pieni:BAAANQADCgYIDwAAAA==.Pinkrose:BAAANQADCggJGgAAAA==.Pizza:BAAANQAECgUJCAAAAA==.',
Pl='Platomatrixx:BAAANQADCgYICwAAAA==.',
Po='Poko:BAAANQADCggJCAAAAA==.Pollyanna:BAAANQADCggICwAAAA==.Poony:BAABNQAECoEYAAIMAAgK5CDcLAAJAwAMAAgK5CDcLAAJAwABNQAECgkJIQAMACEjAA==.',
Pr='Proximus:BAAANQAECgEJAQABNQAECgYIEgABAAAAAA==.',
Ps='Psyop:BAABNQAECoEdAAIEAAkKzx8zCQBAAwAEAAkKzx8zCQBAAwAAAA==.',
Pu='Punnyname:BAAANQAECgYIEAAAAA==.Purrsian:BAAANQAECgQIBAAAAA==.',
Qb='Qberks:BAAANQAECggIEgAAAA==.',
Qu='Quaddh:BAAANQADCggIDAAAAA==.Quellif:BAAANQABCgYICAAAAA==.Quincee:BAAANQADCggICgAAAA==.',
Ra='Radtiz:BAAANQADCgEIAQAAAA==.Raenin:BAAANQAECgUJBgAAAA==.Ragingdraem:BAAANQAECgYIEwAAAA==.Raidei:BAAANQAECgUJDwAAAA==.Rainoffur:BAAANQAECgUICgABNQAECgYJBgABAAAAAA==.Rakeripwait:BAAANQADCgUICgAAAA==.Raoulqc:BAAANQADCgcIDAAAAA==.Ratatosk:BAAANQAECgMJBQAAAA==.Rathan:BAAANQAECgYJDwAAAA==.Ravenanarchy:BAABNQAECoEaAAIfAAgKLQ8oIwD9AQAfAAgKLQ8oIwD9AQAAAA==.Rawheadrexx:BAAANQABCgIIAgAAAA==.',
Re='Redpawedfox:BAAANQAECgYIDwAAAA==.Rekviem:BAAANQAECgIIBAAAAQ==.Remyz:BAAANQADCgUIBQAAAA==.Revie:BAAANQADCgQIBAAAAA==.',
Ri='Rielexia:BAAANQABCgYJBgAAAA==.Rikola:BAAANQAECgMJAwAAAA==.Rizzen:BAAANQADCggJFgAAAA==.',
Ro='Roderika:BAAANQAECgEIAQAAAA==.Rogmar:BAAANQABCgIIAgAAAA==.Royalnewb:BAABNQAECoEiAAMOAAkK8RkpBQBEAgAOAAgKbBwpBQBEAgAMAAkKng5DdwAvAgAAAA==.Royston:BAAANQAECgYJDwAAAA==.',
Ru='Rucereal:BAAANQAECgQJCwAAAA==.Rufous:BAAANQAECgYJDgAAAA==.',
Rw='Rwaga:BAAANQAECgIIAwAAAA==.',
Ry='Ryliea:BAAANQADCgMIAwAAAA==.Rynsidious:BAABNQAECoEaAAIfAAcKthMYKADNAQAfAAcKthMYKADNAQAAAA==.',
['Rã']='Rãin:BAAANQAECgMJBAABNQAECgYJEgABAAAAAA==.',
['Rì']='Rìkú:BAAANQADCgUIBQAAAA==.',
Sa='Sabelle:BAAANQADCggIGgAAAA==.Sableanne:BAAANQABCgYICwAAAA==.Sabîne:BAAANQAECgUJDgAAAA==.Saeton:BAABNQAECoEaAAIWAAgKOw2gGQCUAQAWAAgKOw2gGQCUAQAAAA==.Sahlaris:BAAANQAECgQIBwAAAA==.Salno:BAAANQADCgUJCAAAAA==.Samsonite:BAABNQAECoEWAAIDAAgKohfKNQBdAgADAAgKohfKNQBdAgAAAA==.Sanji:BAAANQADCgIIAgAAAA==.Sargerik:BAEANQABCgIIAgAAAA==.Sariths:BAAANQABCggJEAAAAA==.Savreen:BAAANQADCgYIBgAAAA==.',
Sc='Scrubpal:BAAANQADCggIFAAAAA==.',
Se='Sekhmet:BAAANQADCgMIAwAAAA==.Sekstrasza:BAAANQADCgcJCgAAAA==.Sens:BAAANQAECgUJCgAAAA==.Serrik:BAAANQAECggIBQAAAA==.Sersilkyhair:BAAANQAECgYJDAAAAA==.',
Sh='Shamanoid:BAAANQAECgIJAgABNQAECgUICgABAAAAAA==.Shasta:BAAANQAECgUJDgAAAA==.Shortieabc:BAAANQAECgEJAQAAAA==.Shortmark:BAAANQAECgEJAQAAAA==.Shozwar:BAAANQAECgcJEQAAAA==.',
Si='Siik:BAAANQAECgcICwAAAA==.Silaena:BAAANQAECgQJBgAAAA==.Silverlocke:BAAANQAECgQJDAAAAA==.Sindaris:BAAANQAECgcJBwAAAA==.',
Sj='Sj:BAAANQADCgQIBAAAAA==.',
Sk='Skillcrusade:BAAANQAECgIIAgAAAA==.Skillscales:BAABNQAECoElAAMgAAkKEyH8AQAdAwAgAAkKgh/8AQAdAwAhAAgKiyGDCAC3AgAAAA==.Skyfallen:BAAANQAECgIIAgAAAA==.',
Sl='Sleepydk:BAAANQAECgYJDwAAAA==.Slopysecondz:BAAANQAECgEIAQABNQAECgQICQABAAAAAA==.Slovik:BAAANQAECgEIAgAAAA==.Slowbro:BAAANQADCgYIDwAAAA==.',
Sm='Smok:BAAANQAECgIIAgAAAA==.',
Sn='Snafflo:BAAANQAECgYIBgAAAA==.Snekhet:BAAANQAECgYJDwAAAA==.',
So='Softscars:BAAANQAECgIIAwAAAA==.Solanea:BAAANQAECgUJCAAAAA==.Solaura:BAAANQAECgEJAQAAAA==.Solo:BAAANQADCgMIAwABNQAECgcIGAAHAHceAA==.Sorcero:BAAANQAECgQJBgAAAA==.Sorcforce:BAAANQADCgUIBQAAAA==.Soultelage:BAAANQAECgEJAQAAAA==.Sourwine:BAAANQADCgYICQAAAA==.',
Sp='Spaceman:BAABNQAECoE4AAIHAAkKTiaZAQDqAwAHAAkKTiaZAQDqAwAAAA==.Spire:BAAANQADCggILQAAAA==.Sporkeh:BAAANQADCgMIAwAAAA==.Spritemonk:BAAANQAECgQICgABNQAECgYIDwABAAAAAA==.Spritepally:BAAANQAECgYIDwAAAA==.Spritepriest:BAAANQAECgQIBAABNQAECgYIDwABAAAAAA==.',
St='Stellara:BAAANQADCgQIBwAAAA==.Stiff:BAAANQADCgQIBAAAAA==.Stiffmcgee:BAAANQAECgUIBgAAAA==.Stormdancer:BAABNQAECoEhAAIZAAgKCBiLCQCEAgAZAAgKCBiLCQCEAgAAAA==.Stormpage:BAAANQAECgIIAwAAAA==.Strangiatie:BAAANQADCgYJBwAAAA==.Strych:BAAANQAECgYICgABNQAECggIHwAeAMYdAA==.Stumpyfoot:BAAANQAECgYJDwAAAA==.Stygi:BAAANQAECgEJAgAAAA==.Stãrs:BAABNQAECoElAAMiAAkKaCL6CQBVAwAiAAkKaCL6CQBVAwASAAIKTAY/QwBmAAAAAA==.',
Su='Suki:BAAANQADCggICwAAAA==.Sulawesi:BAAANQADCggICAABNQADCggICAABAAAAAA==.Sultan:BAAANQADCgMJAwAAAA==.Surfacing:BAABNQAECoEbAAIDAAgKwCKCEQAXAwADAAgKwCKCEQAXAwAAAA==.',
Sy='Syntharia:BAABNQAECoEZAAIgAAgK4gf/CABlAQAgAAgK4gf/CABlAQAAAA==.',
Ta='Taffigosa:BAAANQAECgYJDAAAAA==.Taffy:BAAANQADCgcJCgAAAA==.Talomea:BAAANQAECgEIAgAAAA==.Tanthel:BAAANQAECgUICwAAAA==.Taursain:BAAANQADCgYIBwAAAA==.',
Tb='Tbh:BAAANQAECgEIAQABNQAECgYJDgABAAAAAA==.',
Te='Terranteal:BAAANQAECgcICwAAAA==.Terraquis:BAAANQAECgIIAgAAAA==.Terravolta:BAABNQAECoEYAAICAAgKuhDGRADZAQACAAgKuhDGRADZAQAAAA==.Testarossa:BAAANQAECgYIDwAAAA==.',
Th='Themage:BAAANQADCgQJBAABNQAECgUICQABAAAAAA==.Therealvenat:BAAANQAECgUJDgAAAA==.Thiccbiddies:BAAANQAECgcJEQAAAA==.Thort:BAAANQADCgQIBAAAAA==.Thunderwings:BAAANQAECgEJAgAAAA==.',
Ti='Tigan:BAAANQAECgQJCgAAAA==.Tigra:BAABNQAECoEXAAIiAAgKEw0aMgDYAQAiAAgKEw0aMgDYAQAAAA==.Timelord:BAAANQAECgUIBwAAAA==.Timeweaver:BAABNQAECoEaAAIjAAgKvgiuGwCWAQAjAAgKvgiuGwCWAQAAAA==.Tirione:BAAANQAECgUJCgAAAA==.Tirogue:BAAANQADCgUIBgAAAA==.',
To='Toastshark:BAAANQAECgYIDwAAAA==.Toranaar:BAAANQADCggIDgAAAA==.Torpal:BAAANQADCgcJDwABNQAECgUJDgABAAAAAA==.Totorö:BAAANQAECgYJEgAAAA==.Tova:BAAANQADCgcIDgAAAA==.',
Tr='Traiturner:BAAANQAECgQJDAAAAA==.Trayfu:BAAANQADCggJGgAAAA==.Treebeárd:BAAANQABCggICwAAAA==.Trice:BAAANQAECgQIDAAAAA==.Trillion:BAAANQAECgYJDwAAAA==.Trostani:BAAANQAECgYIBQAAAA==.Truc:BAAANQADCgMIAwAAAA==.Trusker:BAAANQAECgQIBgAAAA==.',
Ts='Tsaavas:BAAANQAECgMIBgAAAA==.Tsereya:BAAANQADCgYIBgAAAA==.Tsugumomo:BAAANQADCggICAAAAA==.',
Tu='Tullandil:BAAANQABCgQIAgAAAA==.',
Tw='Twitty:BAAANQAECgQICAABNQAECgkJIAAKAKUbAA==.',
Ty='Tyloestus:BAAANQAECgYJBwAAAA==.Tyragni:BAAANQAECgEIAQAAAA==.Tyravana:BAAANQADCgYIBgAAAA==.Tystriel:BAAANQAECgMIBAAAAA==.',
['Tí']='Tíamat:BAAANQAECgUJBwAAAA==.',
Ul='Ulasar:BAAANQADCgcIFAAAAA==.',
Un='Unmilkable:BAAANQADCgUIBQAAAA==.Untarot:BAAANQADCgMJBAAAAA==.',
Va='Valdanyr:BAEANQAECgEJAQAAAA==.Valimar:BAAANQADCgEIAQABNQAECgYIDwABAAAAAA==.Vallenar:BAAANQAECgEIAQAAAA==.Valliant:BAAANQAECgIIAgABNQAECgQJBAABAAAAAA==.Valnullis:BAAANQADCgUIBwAAAA==.Valorfist:BAAANQADCgQJBAAAAA==.Valídus:BAAANQADCgYJCgAAAA==.Vampteabag:BAAANQADCggIDQAAAA==.Vanden:BAAANQAECgMIBQABNQAECgcIBwABAAAAAA==.Varsi:BAABNQAECoEfAAQDAAkKtSE9EAAhAwADAAkKtSE9EAAhAwANAAEKUwqxDQA3AAAdAAEK9QTDXgA0AAAAAA==.',
Ve='Veetor:BAAANQAECgQJBwAAAA==.Velash:BAAANQAECgUICwAAAA==.Vendorin:BAAANQAECgEJAQAAAA==.Verratanikto:BAAANQAECggIBwAAAA==.Verwínd:BAAANQAECgYJDAAAAA==.',
Vi='Virusgt:BAAANQAECgQIBAAAAA==.Vitner:BAAANQAECgcICgABNQAECggIDwABAAAAAA==.',
Vo='Voidbeam:BAAANQAECgQJBQAAAA==.Voidsta:BAAANQADCgIIAgAAAA==.Volgur:BAAANQADCggJHwAAAA==.Volker:BAAANQAECgYJDwAAAA==.',
We='Wenotknow:BAAANQAECgcIEwAAAA==.',
Wi='Wife:BAABNQAECoEYAAIHAAcKdx67RABUAgAHAAcKdx67RABUAgAAAA==.Wildraubtier:BAAANQADCgIIAgAAAA==.',
Wo='Wormsloe:BAAANQADCgYIBgAAAA==.',
Xa='Xaida:BAAANQAECgUJDgAAAA==.Xaldania:BAAANQADCgcJDQAAAA==.',
Xc='Xcaps:BAAANQADCgcIBwAAAA==.',
Xu='Xuing:BAABNQAECoEaAAIYAAgK0yK5BAAcAwAYAAgK0yK5BAAcAwAAAA==.Xuingg:BAAANQAECgcIBwABNQAECggJGgAYANMiAA==.',
Ya='Yarp:BAAANQADCgUIBQAAAA==.Yarro:BAABNQAECoEXAAIDAAgKQwnVZQC8AQADAAgKQwnVZQC8AQAAAA==.',
Ye='Yesdaddy:BAAANQADCggJHwAAAA==.',
Yo='Yorozu:BAAANQAECgQIBQAAAA==.Young:BAAANQADCgQICAABNQAECgcICwABAAAAAA==.Youngblud:BAAANQAECgcICwAAAA==.Youngplasma:BAAANQAECgEJAQABNQAECgcICwABAAAAAA==.Youngwarlock:BAAANQADCgEJAQAAAA==.Yourhealor:BAAANQADCgYIBgAAAA==.',
Yu='Yugi:BAAANQAECgYICgAAAA==.',
Za='Zaela:BAAANQADCgQIBAAAAA==.Zahira:BAAANQAECgUJDgAAAA==.Zax:BAAANQAECgQJBgAAAA==.',
Ze='Zenatra:BAAANQADCgYICwAAAA==.Zeroximo:BAABNQAECoEWAAIMAAcKTxRZjgDzAQAMAAcKTxRZjgDzAQAAAA==.',
Zi='Zieren:BAAANQADCgcIBwABNQAECgQJBQABAAAAAA==.Zipline:BAAANQAECgYIDQAAAA==.Zirathiel:BAAANQADCgYICAABNQADCggIDAABAAAAAA==.',
Zo='Zofie:BAAANQADCgYJCwAAAA==.Zogz:BAAANQAECgUJCQAAAA==.Zombiexcat:BAAANQADCgEIAQAAAA==.Zorakiel:BAAANQAECgYIEAAAAA==.',
Zw='Zwiebelle:BAAANQAECgQJCQAAAA==.',
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
