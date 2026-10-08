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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Hunter-BeastMastery','Mage-Arcane','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Warlock-Demonology','Druid-Restoration','Hunter-Marksmanship','Paladin-Retribution','Mage-Frost','Paladin-Holy','Monk-Brewmaster','Paladin-Protection','Warrior-Arms','Shaman-Elemental','DeathKnight-Blood','Monk-Windwalker','Druid-Guardian','Druid-Balance','Shaman-Enhancement','DemonHunter-Vengeance','Priest-Discipline','Monk-Mistweaver','Hunter-Survival','DeathKnight-Frost','Warlock-Destruction','Warrior-Protection','Warrior-Fury','Rogue-Subtlety','DemonHunter-Havoc','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Rogue-Outlaw','Rogue-Assassination','Druid-Feral',}
local provider = {region='US',realm='Elune',name='US',type='weekly',zone=53,date='2026-10-06',data={Ae='Aelaya:BAAANQADCgQIBAAAAA==.Aeshen:BAAANQAECgUICAAAAA==.Aevea:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Ai='Aib:BAAANQAECgIIAwABNQAECgYICQABAAAAAA==.Aibe:BAAANQAECgYICQAAAA==.Aifertim:BAAANQADCgQIBAABNQAECgkJHQACADQcAA==.Aisellea:BAAANQABCgIIAgAAAA==.',
Ak='Akashah:BAABNQAECoEoAAIDAAgKFwt6eQDtAQADAAgKFwt6eQDtAQAAAA==.Akeno:BAAANQAECgEIAQAAAA==.',
Al='Alarick:BAAANQAECgQICAAAAA==.Alatha:BAAANQADCgQIBAABNQAECggIJgAEAPceAA==.Alathasedai:BAABNQAECoEmAAIEAAgK9x5OTgDUAgAEAAgK9x5OTgDUAgAAAA==.Alathea:BAABNQAECoEoAAMFAAkKMyERCgBgAwAFAAkKMyERCgBgAwAGAAMKGwdrVwB8AAAAAA==.Aledis:BAABNQAECoExAAIHAAkKwyUwAgDRAwAHAAkKwyUwAgDRAwAAAA==.Allanøn:BAAANQAECgEIAQAAAA==.Alyrical:BAAANQABCgIIAQAAAA==.',
Am='Amirial:BAAANQADCggIDgAAAA==.Amowrath:BAAANQAECgUIDwAAAA==.Amyasia:BAAANQAECgQIBwABNQAECggIGwAIAP4jAA==.',
An='Ancila:BAAANQADCgEIAQAAAA==.Anghúro:BAAANQADCgYICQABNQAECgUIBwABAAAAAA==.Angélica:BAAANQAECgYIDgAAAA==.Animethighs:BAAANQADCgcIFQAAAA==.Ankoou:BAAANQABCgUICAAAAA==.Antifungal:BAAANQABCgIIAgAAAA==.',
Aq='Aquaskies:BAAANQAECgYICgABNQAECgkJFwAJALwOAA==.',
Ar='Aranwyn:BAAANQAECgQIBAABNQAECgYIEgABAAAAAA==.Arawynn:BAABNQAECoEXAAIDAAcKvBFxewDoAQADAAcKvBFxewDoAQAAAA==.Archnessa:BAAANQAECggIAQAAAA==.Ariock:BAAANQAECgQIDgAAAA==.Arknight:BAABNQAECoEZAAMDAAgKqh6SMgCyAgADAAgKqh6SMgCyAgAKAAIK/AQnbgBRAAAAAA==.Artémís:BAAANQAECgEIAQAAAA==.',
As='Astreae:BAAANQAECgUICAAAAA==.',
At='Atamus:BAAANQADCggIGwAAAA==.',
Av='Avanah:BAAANQADCgcIDQAAAA==.Avi:BAABNQAECoEVAAILAAgKHxYZZwA5AgALAAgKHxYZZwA5AgABNQAECgkJJQAHADAgAA==.',
Ay='Aya:BAABNQAECoEYAAIMAAgKuBx6BgBuAgAMAAgKuBx6BgBuAgAAAA==.Ayekillu:BAABNQAECoEcAAMLAAgKZQ4ulQDEAQALAAgKZQ4ulQDEAQANAAYKBARAqQADAQAAAA==.Ayiasofia:BAABNQAECoEjAAIFAAgKthseNgBuAgAFAAgKthseNgBuAgAAAA==.Ayla:BAABNQAECoEYAAIOAAcKaQOpHADxAAAOAAcKaQOpHADxAAAAAA==.Aylan:BAABNQAECoEYAAIOAAcKMCOoBgDAAgAOAAcKMCOoBgDAAgAAAA==.Ayum:BAAANQAECgcIBwAAAA==.Ayumfox:BAABNQAECoEfAAIDAAgKRx5ELADIAgADAAgKRx5ELADIAgAAAA==.Ayumm:BAAANQADCggICAAAAA==.',
Az='Azapal:BAABNQAECoEnAAMLAAgKnxZydwAOAgALAAgKnxZydwAOAgAPAAEKvxiqWwBGAAAAAA==.Azuros:BAAANQADCgUICAABNQAECgYIEQABAAAAAA==.',
Ba='Babyjezuz:BAAANQAECgQIDQAAAA==.Badger:BAABNQAECoEpAAIQAAkKKCRwCACrAwAQAAkKKCRwCACrAwAAAA==.Balloon:BAAANQADCggIFAAAAA==.Bandâid:BAAANQAECgQIBAABNQAECgcICwABAAAAAA==.Barathiel:BAABNQAECoErAAIDAAkKtxXsSwBiAgADAAkKtxXsSwBiAgAAAA==.Barlow:BAAANQAECgEIAgAAAA==.Baryll:BAAANQAECgYIEwAAAA==.Batasu:BAABNQAECoEgAAMCAAgKeBpBNABpAgACAAgKeBpBNABpAgARAAEKSw5sDwE5AAAAAA==.Baulde:BAABNQAECoErAAISAAkKgw2MRwC7AQASAAkKgw2MRwC7AQAAAA==.',
Be='Beerbroth:BAABNQAECoEZAAITAAgKJg9tJwCzAQATAAgKJg9tJwCzAQAAAA==.Bellitrix:BAAANQADCggIDwAAAA==.',
Bi='Biefcake:BAABNQAECoEkAAIHAAgKQAjKYgBfAQAHAAgKQAjKYgBfAQAAAA==.Bigmoo:BAABNQAECoEtAAIUAAkKlh3oBgDtAgAUAAkKlh3oBgDtAgAAAA==.Bigoldotties:BAAANQAECgQIBwAAAA==.',
Bk='Bk:BAAANQAECgYIEwAAAA==.',
Bl='Blackparade:BAAANQAECgQIBgAAAA==.Blaydun:BAAANQAECgIIAgAAAA==.Blewboar:BAAANQAECgUIEAAAAA==.Bllass:BAAANQADCgUIGwAAAA==.Blueberrie:BAAANQAECgcIEwAAAA==.Blyzard:BAAANQAECgQIBQAAAA==.',
Bo='Boiledfrogz:BAABNQAECoEkAAMVAAkK6xeyIgCbAgAVAAkK6xeyIgCbAgAJAAQKCQ4dRgDLAAAAAA==.Boned:BAABNQAECoEVAAIDAAkKDyFnFgAqAwADAAkKDyFnFgAqAwAAAA==.Boopboops:BAABNQAECoEXAAMCAAcKUyIHJAC3AgACAAcKUyIHJAC3AgAWAAIKuRBgKQB/AAAAAA==.Bosleigor:BAAANQADCgYIBgAAAA==.',
Br='Bravehearthx:BAAANQAECgYIEQAAAA==.Bringerdk:BAAANQAFFAEIAQAAAA==.Bringerlk:BAAANQAECgUICQAAAA==.Bringerp:BAAANQAECgMIAQAAAA==.Brogend:BAAANQAECgcIEgABNQAECgkJKQAQACgkAA==.Bronco:BAABNQAECoEYAAIQAAgK4QzCkwDDAQAQAAgK4QzCkwDDAQAAAA==.Brume:BAAANQADCgYIEQAAAA==.Brünhïnnä:BAAANQAECgIIAgAAAA==.',
Bu='Bubblntendre:BAAANQAECgcIEwAAAA==.Bucknastyy:BAAANQADCggICAAAAA==.',
Ca='Caféconron:BAABNQAECoEaAAIXAAgKTiF3AwAFAwAXAAgKTiF3AwAFAwAAAA==.Caitsidhe:BAABNQAECoEZAAIUAAgKURFJGACpAQAUAAgKURFJGACpAQAAAA==.Calinda:BAAANQADCgYICgABNQAECggIHgATAJgSAA==.Cannute:BAAANQAECgQICQAAAA==.Canuckdemon:BAAANQAECgEIAQAAAA==.Canuckdruid:BAAANQAECgQICQAAAA==.Canuckranger:BAAANQAECgUIEgAAAA==.Canucksham:BAAANQAECgEIAwAAAA==.Captnubcakes:BAAANQAECgYIEwAAAA==.Carebear:BAACNQAFFIEMAAINAAUKCw1yCwCBAQANAAUKCw1yCwCBAQA1AAQKgScAAg0ACQocHOUfANkCAA0ACQocHOUfANkCAAAA.Castallia:BAABNQAECoEjAAMFAAkKlhFHTQAUAgAFAAkKaxFHTQAUAgAYAAMKBBD8FgCjAAAAAA==.Catrathena:BAAANQAECgEIAQAAAA==.',
Ce='Celeborn:BAAANQADCgYIBgAAAA==.Celta:BAAANQAECgQIBwAAAA==.',
Ch='Chaelis:BAABNQAECoEmAAIEAAkKIB7jNAATAwAEAAkKIB7jNAATAwAAAA==.Chainsoflove:BAAANQADCgQIBAAAAA==.Chalado:BAAANQADCgMIBAAAAA==.Chamanita:BAAANQAECgYIEwAAAA==.Charizzard:BAAANQAECgEIAQAAAA==.Chauny:BAAANQADCgYIEAAAAA==.Cheweh:BAAANQAECgYIBgAAAA==.Chilléd:BAAANQAECgcIBwAAAA==.Chisato:BAAANQADCggICAABNQAECgIIAwABAAAAAA==.Chwamzrogue:BAAANQADCgIIAgAAAA==.',
Ci='Cindêr:BAAANQABCgYIBwAAAA==.Cisticola:BAABNQAECoEZAAIZAAgKHiIICAD1AgAZAAgKHiIICAD1AgAAAA==.Citi:BAAANQABCgIIAgAAAA==.Citii:BAAANQADCgQIBAAAAA==.',
Cl='Clair:BAACNQAFFIEGAAIFAAMK6gkVGwDeAAAFAAMK6gkVGwDeAAA1AAQKgSwAAgUACQp6GMAwAIQCAAUACQp6GMAwAIQCAAAA.Clova:BAABNQAECoEdAAIJAAgKvRoDFgBwAgAJAAgKvRoDFgBwAgAAAA==.',
Co='Combusty:BAAANQADCgEIAgAAAA==.Cornholyoh:BAACNQAFFIELAAIGAAUKWwmWBwBsAQAGAAUKWwmWBwBsAQA1AAQKgSgAAgYACQrkFj8ZAGMCAAYACQrkFj8ZAGMCAAAA.Counsel:BAAANQAECgIIAgAAAA==.',
Cr='Cremefraiche:BAAANQAECgcIDgAAAA==.Crillex:BAAANQADCgMIAwABNQAECggIHAALACUYAA==.Critkiller:BAAANQAECgQICAAAAA==.Crulzilla:BAAANQAECgYIEAAAAA==.',
Cu='Cuero:BAAANQADCgUIBwAAAA==.Cupcakemeow:BAABNQAECoEqAAIaAAkK0BgSAwDMAgAaAAkK0BgSAwDMAgAAAA==.Curas:BAAANQAECggIEQAAAA==.Curzøn:BAABNQAECoEsAAIMAAkKFSZkAADMAwAMAAkKFSZkAADMAwAAAA==.',
Cw='Cw:BAAANQAECgQIDQABNQADCgYJBwABAAAAAA==.Cwd:BAAANQADCgYJBwAAAA==.Cwds:BAAANQADCgcIEwABNQADCgYJBwABAAAAAA==.Cwoodz:BAAANQAECgYICwABNQADCgYJBwABAAAAAA==.',
Da='Dabubblez:BAAANQADCgUIBQAAAA==.Daedengerek:BAAANQAECgQICAAAAA==.Daggers:BAAANQADCgQIBAAAAA==.Daigz:BAAANQADCgYJCgAAAA==.Danerrin:BAACNQAFFIEFAAIbAAIKthsnDgCpAAAbAAIKthsnDgCpAAA1AAQKgSMAAwcACQobJDonAH4CAAcACAp5IzonAH4CABsABgoRIuIwAOYBAAAA.Dangersaur:BAABNQAECoEcAAMJAAgKXCAfDgDSAgAJAAgKXCAfDgDSAgAUAAUK7QoTLgDhAAAAAA==.Danielsan:BAAANQABCgYIBwAAAA==.Danigos:BAAANQAFFAcIHwAAAQ==.Darkcrushr:BAAANQAECgEIAQAAAA==.Daryss:BAAANQAECgIIAgAAAA==.Daspirn:BAAANQADCgYICgAAAA==.Dawnkeeper:BAAANQAECgIIAgAAAA==.Dawnshott:BAAANQADCggIFwAAAA==.',
De='Deand:BAAANQABCgQIBAAAAA==.Deathadder:BAABNQAECoErAAIDAAkK4CRuAwDHAwADAAkK4CRuAwDHAwAAAA==.Deathhounds:BAAANQADCgcIDAAAAA==.Deller:BAAANQADCgUIBgABNQADCgYIBgABAAAAAA==.Demiphant:BAABNQAECoEcAAILAAgKJRhHbQAoAgALAAgKJRhHbQAoAgAAAA==.Dennirn:BAAANQAECgQIBgABNQAFFAIIBQAbALYbAA==.Desna:BAAANQADCgUIBQAAAA==.',
Di='Diesalot:BAABNQAECoEaAAIHAAgKKQiwZABYAQAHAAgKKQiwZABYAQAAAA==.Divinedragon:BAAANQAECgUICwAAAA==.',
Do='Downstime:BAAANQADCgEIAQABNQAECgYIEwABAAAAAA==.',
Dr='Dracthar:BAAANQAECgEIAgAAAA==.Draczeal:BAAANQAECgMIBAAAAA==.Dragonlee:BAAANQAECgUIBwAAAA==.Dragovade:BAABNQAECoEZAAIRAAcK+A0legCEAQARAAcK+A0legCEAQAAAA==.Dreadlocke:BAAANQAECgYIEwAAAA==.Dreidels:BAAANQADCggIGgABNQAECggIHwAJAGQQAA==.Drunkciggie:BAAANQAECgMIAwAAAA==.Drunky:BAAANQAECgMIBQAAAA==.Drysua:BAABNQAECoEpAAIGAAgK2hexGwBFAgAGAAgK2hexGwBFAgAAAA==.',
Du='Duffageddon:BAAANQADCgcIBwAAAA==.Duskmender:BAABNQAECoEjAAILAAgK+RLMfgD7AQALAAgK+RLMfgD7AQAAAA==.Duzick:BAAANQADCgUICAAAAA==.',
Dz='Dzmage:BAABNQAECoEPAAIEAAgKRwkb+QB0AQAEAAgKRwkb+QB0AQAAAA==.Dzret:BAAANQAECgUIBQAAAA==.Dzshaman:BAAANQAECgUIBwAAAA==.Dzwarlock:BAABNQAECoE4AAIIAAkKChg/OACQAgAIAAkKChg/OACQAgAAAA==.',
['Dë']='Dëëds:BAAANQAECgIIAgAAAA==.',
Ec='Ecklyn:BAAANQADCgIIAgABNQAECggIIAACAHgaAA==.Eclipsis:BAAANQADCgUIBQAAAA==.',
Eg='Egino:BAAANQAECgYICwAAAA==.',
El='Elanuo:BAAANQADCgYIDAAAAA==.Elarisiel:BAAANQADCggICAAAAA==.Elaynne:BAABNQAECoEjAAIDAAgKsCReFAA1AwADAAgKsCReFAA1AwAAAA==.Eldrith:BAAANQADCgIIAgABNQAECggIIAACAHgaAA==.Eledis:BAAANQAECgIIBAAAAA==.Elemender:BAAANQAECgMJBgABNQAECggIIwALAPkSAA==.Elementrix:BAAANQAECggIBwAAAA==.Elfaa:BAAANQADCgEIAwAAAA==.Elieth:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.Eliteelf:BAAANQAECgQIEwAAAA==.Ellenora:BAAANQADCgYIBgAAAA==.Ellmer:BAABNQAECoEhAAIDAAgKFBvVRAB3AgADAAgKFBvVRAB3AgAAAA==.Elnir:BAAANQADCgUIBQAAAA==.Elopeppe:BAAANQAECgMIBAAAAA==.Elorro:BAAANQAECgEIAQABNQAFFAUICwAGAFsJAA==.Eltaizari:BAAANQAECgcIDgAAAA==.Elthiør:BAABNQAECoEWAAIIAAgKyBT/WgAkAgAIAAgKyBT/WgAkAgAAAA==.Elumiel:BAAANQAECgcIDgAAAA==.Elunedorei:BAAANQADCgcICgAAAA==.Elunelol:BAABNQAFFIEIAAINAAUKZAprCwCCAQANAAUKZAprCwCCAQAAAA==.Elwesingollo:BAAANQADCgYICwAAAA==.',
En='Enilia:BAABNQAECoEhAAIcAAkKyxs+BADcAgAcAAkKyxs+BADcAgAAAA==.Enrgizernelf:BAAANQAECgYICgAAAA==.Entylzah:BAAANQADCgYIBgAAAA==.',
Eo='Eo:BAAANQADCggICAABNQAECgcIBwABAAAAAA==.',
Er='Erathena:BAAANQADCgYIBgAAAA==.Eriya:BAABNQAECoEZAAILAAcKKCCfUQB3AgALAAcKKCCfUQB3AgAAAA==.',
Es='Esmeray:BAAANQADCgIIAgABNQAECggIIwALAPkSAA==.Estalea:BAAANQADCgQIBAAAAA==.Estideeslol:BAAANQAECgYICQAAAA==.',
Eu='Euphonia:BAAANQAECgEIAgAAAA==.',
Ey='Eyllis:BAAANQAECgcIEwAAAA==.',
Ez='Ezareth:BAAANQADCgUIBQAAAA==.',
Fa='Faded:BAAANQAECgIIAQAAAA==.Faedark:BAAANQADCgMIAgAAAA==.Farastraza:BAAANQADCgYICgAAAA==.',
Fe='Feralscar:BAAANQADCgQIBAAAAA==.Ferangdh:BAAANQAECgQIBwABNQAECggIGQATACYPAA==.Fevion:BAAANQAECgYIEgAAAA==.Fevius:BAAANQAECgUIDAABNQAECgYIEgABAAAAAA==.',
Fh='Fhantomgrave:BAAANQAECgYIDgAAAA==.',
Fi='Fifteen:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Finduilas:BAABNQAECoEiAAIdAAgKXBwuCwBfAgAdAAgKXBwuCwBfAgAAAA==.Firepower:BAABNQAECoEgAAIEAAgKEBsFdQB+AgAEAAgKEBsFdQB+AgAAAA==.Firepriest:BAABNQAECoEgAAIGAAgKHhI9IgD8AQAGAAgKHhI9IgD8AQAAAA==.Firesdruid:BAAANQADCggIFwABNQAECggIIAAGAB4SAA==.Fistu:BAAANQADCgQIBAAAAA==.',
Fl='Flagon:BAAANQAECgQIBAABNQAECgUICgABAAAAAA==.Flappyjacks:BAAANQAECgQICgAAAA==.Flappystraza:BAAANQAECgYIEQAAAA==.Fleabane:BAAANQABCgIIAgAAAA==.Flickka:BAAANQAECgYICAAAAA==.',
Fo='Fourteen:BAAANQAECgMIAwAAAA==.Fourus:BAAANQADCggIHQAAAA==.',
Fr='Freakaleake:BAAANQAECgMIBQAAAA==.Freeport:BAACNQAFFIEGAAIEAAQKkSOAGQCEAQAEAAQKkSOAGQCEAQA1AAQKgRwAAgQACQrgI3gjAEUDAAQACQrgI3gjAEUDAAAA.Freezerburn:BAAANQAECgYIBgABNQAECgcIGwACAPoaAA==.Frostmender:BAAANQADCggICAABNQAECggIIwALAPkSAA==.Frostypillz:BAAANQABCgEIAQAAAA==.Frtouches:BAAANQAECgQIBgABNQAECgUIBgABAAAAAA==.',
Fu='Funnymuffin:BAABNQAECoEaAAMcAAgK3A2dKgAcAQAIAAcKPw4xjwCRAQAcAAUKpAqdKgAcAQAAAA==.Furyia:BAAANQAECgUICQAAAA==.Furyk:BAAANQAECgYIDAAAAA==.Fuzzleprime:BAABNQAECoEiAAIUAAgKpxmxDQBMAgAUAAgKpxmxDQBMAgAAAA==.Fuzzy:BAAANQADCgUIBQAAAA==.',
['Fä']='Fäye:BAAANQADCgIIAgAAAA==.',
Ga='Gaebora:BAAANQAECgEIAQAAAA==.Gahmull:BAAANQADCggIDQAAAA==.Galleae:BAABNQAECoEhAAIFAAgKMREPYgDIAQAFAAgKMREPYgDIAQAAAA==.Garmart:BAABNQAECoEmAAMDAAkKlB9BHAANAwADAAgKlyFBHAANAwAKAAkKmgy3KADkAQAAAA==.Gauza:BAAANQAECgMIBQAAAA==.',
Gh='Ghouldann:BAABNQAECoEZAAMcAAgK8BfYEADqAQAIAAgKnBOhYgAOAgAcAAcK3xPYEADqAQAAAA==.',
Gi='Gionathir:BAAANQAECgYIDwAAAA==.',
Gl='Glaakii:BAAANQADCgIJAgAAAA==.Glagglag:BAABNQAECoEqAAMeAAkKSCGwAQBpAwAeAAkKSCGwAQBpAwAQAAEKDBZhKQFDAAAAAA==.',
Go='Goldeen:BAABNQAECoEYAAIFAAgKhQzXagCnAQAFAAgKhQzXagCnAQAAAA==.Gorothraex:BAAANQAECgEIAQAAAA==.',
Gr='Graxion:BAAANQAECgYIDAAAAA==.Greggiiee:BAAANQAECgIJAgAAAA==.Grimmaw:BAAANQAECgQIBAAAAA==.Grindelwald:BAAANQAECgQIBAAAAA==.',
Gu='Guacamelee:BAAANQAECgQICQAAAA==.Guak:BAAANQADCggICAAAAA==.',
Gw='Gwuak:BAAANQADCgcIHQAAAA==.Gwynorra:BAAANQAECgUIDAAAAA==.',
Ha='Habibi:BAABNQAECoEXAAIfAAgKcRV2EwA+AgAfAAgKcRV2EwA+AgAAAA==.Haralda:BAAANQAECgcIDgAAAA==.Harshblue:BAABNQAECoEmAAMLAAgKSiX3HQA1AwALAAgKSiX3HQA1AwAPAAgKXB6xDwB8AgAAAA==.Haste:BAAANQADCgEIAQAAAA==.Hatt:BAAANQAECgcIDgAAAA==.Hatts:BAAANQAECgEJAQAAAA==.Hawtnhordy:BAAANQADCgMIAwAAAA==.',
He='Healeydan:BAACNQAFFIEFAAIFAAIKpyb+GQDoAAAFAAIKpyb+GQDoAAA1AAQKgSMABAUACQppJQAHAH0DAAUACQpQJQAHAH0DABgABwo8IH0EAGgCAAYAAgriCw9fAFoAAAAA.Heddh:BAABNQAECoEkAAQgAAkKdh92EAAEAwAgAAkKmB12EAAEAwAXAAIKxiTAGgDWAAAhAAQKKQuSSQDTAAABNQAECggIJgAJAIcjAA==.Heddruid:BAABNQAECoEmAAMJAAgKhyOjCQASAwAJAAgKhyOjCQASAwAUAAEK/gzOUwAlAAAAAA==.Heiligfeuer:BAAANQAECgMIAgAAAA==.Hentaya:BAAANQAECgEIAQABNQABCgQIBAABAAAAAA==.Herrick:BAAANQAECggICAAAAA==.Heythanksman:BAAANQADCggJDgAAAA==.Heyzuse:BAAANQAECgYICwAAAA==.',
Hi='Hippay:BAAANQAECgYICwAAAA==.',
Ho='Hoid:BAAANQAECgQIBwAAAA==.Holynihalus:BAACNQAFFIELAAMFAAUKKCLkBgAAAgAFAAUKKCLkBgAAAgAYAAEKSQnpAwBAAAA1AAQKgSIAAgUACQrtHCkoAKsCAAUACQrtHCkoAKsCAAAA.Holypowerr:BAAANQAECgEIAQABNQAECgkJHQACADQcAA==.Holyspoons:BAABNQAECoElAAILAAkKoxdhXwBPAgALAAkKoxdhXwBPAgAAAA==.Homar:BAAANQAECgQICQABNQAECgUIBgABAAAAAA==.Hoopa:BAACNQAFFIETAAITAAcKEhhLAgA+AgATAAcKEhhLAgA+AgA1AAQKgRoAAhMACQpfISoVAIQCABMACQpfISoVAIQCAAAA.Hordemender:BAAANQAECgcIBwABNQAECggIIwALAPkSAA==.Houndsglory:BAAANQAECgMIBAAAAA==.Houndwar:BAAANQADCgYIDAAAAA==.',
Hu='Huggs:BAAANQAECgYICgAAAA==.Hunterama:BAAANQADCgUIBQAAAA==.Huntli:BAAANQAECgYIEwAAAA==.Huntrix:BAAANQAECgQIBgAAAA==.Huricaine:BAAANQAECgEIAwAAAA==.',
['Hé']='Hécate:BAABNQAECoEmAAIZAAkKSx7+BgAKAwAZAAkKSx7+BgAKAwAAAA==.',
Ic='Icecreamcake:BAACNQAFFIEYAAIFAAYK2gZLCgC9AQAFAAYK2gZLCgC9AQA1AAQKgSUAAgUACQomGXUyAH0CAAUACQomGXUyAH0CAAAA.Icyy:BAAANQAECgYICwAAAA==.',
Id='Idontpaint:BAAANQADCgUIBQABNQABCgQIBAABAAAAAA==.',
Il='Ilithya:BAAANQAECgUIBwAAAA==.Illidansdad:BAAANQAECgIIAgAAAA==.',
Io='Ioana:BAAANQAECgEIAQAAAA==.',
Ip='Iphei:BAAANQAECggIEQAAAA==.',
Ir='Irulanni:BAABNQAECoErAAIDAAkKShWZPACQAgADAAkKShWZPACQAgAAAA==.',
Is='Ishanaxade:BAABNQAECoEdAAIGAAcKxhkPIAATAgAGAAcKxhkPIAATAgAAAA==.',
Iv='Iva:BAABNQAECoElAAIHAAkKMCDBFAD8AgAHAAkKMCDBFAD8AgAAAA==.Ivanov:BAAANQADCggIFAAAAA==.',
Iz='Izzie:BAAANQADCgcIBwAAAA==.',
Ja='Jackybrennan:BAAANQADCgcIBwABNQAECggIHgAgAGIVAA==.Jagershaii:BAAANQADCggJGwAAAA==.Jaketm:BAAANQADCgQIBAAAAA==.Jalaven:BAABNQAECoEZAAIQAAcKpgkhsgBxAQAQAAcKpgkhsgBxAQAAAA==.Jano:BAAANQAECgQIBwAAAA==.Jas:BAAANQAECgYIDQAAAA==.Jawsh:BAAANQAECgYIBgAAAA==.',
Je='Jecka:BAAANQAECgQIBwAAAA==.Jentle:BAAANQAECgYICgAAAA==.Jessicka:BAAANQAECgYIDAAAAA==.Jesûs:BAAANQADCgUIBQAAAA==.',
Ji='Jibbywibby:BAAANQADCgIIBAABNQAECgkJHAAWAHogAA==.Jibreel:BAAANQAECgEIAQAAAA==.Jinyla:BAAANQADCggIDQAAAA==.Jinzho:BAABNQAECoEVAAILAAcK7wkrxABaAQALAAcK7wkrxABaAQAAAA==.Jiynila:BAAANQAECgMIBAAAAA==.',
Jo='Johey:BAABNQAECoEjAAMRAAgKuh+9IwDYAgARAAgKuh+9IwDYAgACAAgKUgoOewBsAQABNQABCgUIBQABAAAAAA==.Jorzul:BAAANQADCgQIBgAAAA==.',
Ju='Juanchoxch:BAAANQAECgYICQAAAA==.Justinian:BAAANQABCgMIAQAAAA==.Juvenate:BAABNQAECoEdAAIJAAcKUiXEDADlAgAJAAcKUiXEDADlAgAAAA==.Juyani:BAAANQAECgQICgAAAA==.',
Jy='Jynela:BAAANQAECgQIBAAAAA==.',
Ka='Kahlanämnell:BAAANQADCgUIBQAAAA==.Kailyn:BAAANQADCgIIAgAAAA==.Kaiyah:BAAANQAECgMIAgAAAA==.Kalici:BAAANQADCgUIBQAAAA==.Kanab:BAAANQAECgIJAwABNQAECggIEQABAAAAAA==.Kavian:BAAANQADCgUIBQAAAA==.Kayllea:BAAANQADCgYIFwABNQADCggIHwABAAAAAA==.Kaytara:BAABNQAECoEWAAIUAAcK0woAJAAvAQAUAAcK0woAJAAvAQAAAA==.',
Ke='Keharn:BAAANQADCggIJQAAAA==.Kellen:BAACNQAFFIEXAAIFAAYK6SMjAgCJAgAFAAYK6SMjAgCJAgA1AAQKgS8AAwUACQokJYQJAGUDAAUACQokJYQJAGUDAAYAAQoPDsZmAEAAAAAA.Keloros:BAAANQADCgYICwAAAA==.Kenós:BAABNQAECoEWAAIGAAgK8xYCGwBNAgAGAAgK8xYCGwBNAgAAAA==.Kettock:BAAANQAECgQICQAAAA==.Kevzorg:BAAANQABCgMIAwAAAA==.',
Kh='Khae:BAAANQADCgcIBwAAAA==.',
Ki='Kierk:BAAANQADCgUIBAAAAA==.Kilj:BAABNQAECoEiAAIIAAgKQRVEWAAsAgAIAAgKQRVEWAAsAgAAAA==.Kinuran:BAABNQAECoErAAMRAAkKmR5rFwAmAwARAAkKmR5rFwAmAwAWAAEKTgN+MgAtAAAAAA==.Kitherry:BAAANQAECgYIEwAAAA==.',
Kn='Knifeprty:BAAANQAECgEIAQAAAA==.',
Ko='Koristil:BAAANQADCgYICAAAAA==.Kowdrak:BAAANQAECgUICgABNQAECgcIFgANAH4OAA==.Kowmann:BAAANQABCgcJBwABNQAECgcIFgANAH4OAA==.',
Kr='Kreapen:BAAANQAECgYIDAAAAA==.Krisdk:BAACNQAFFIEJAAMHAAUKeRgsCwAzAQAHAAQKxRgsCwAzAQASAAEKTBdqJgBEAAA1AAQKgSwAAwcACQp1I1EUAAADAAcACQp1I1EUAAADABIAAQpeJBGjAGoAAAAA.Krisevoker:BAABNQAECoEeAAQiAAkKbxMyBgBCAgAiAAkKbxMyBgBCAgAjAAYKbAvKHwA8AQAkAAQKhAV/OQCsAAABNQAFFAUICQAHAHkYAA==.',
Kt='Ktosh:BAAANQAECgEIAgAAAA==.',
Ku='Kurenäi:BAAANQAECgUICgAAAA==.Kurzul:BAAANQADCgMIAwAAAA==.',
Kw='Kwerin:BAAANQAECgEJAQAAAA==.',
['Kí']='Kírî:BAACNQAFFIENAAIJAAUK0hoGBADOAQAJAAUK0hoGBADOAQA1AAQKgSYAAgkACQq0GhwUAIgCAAkACQq0GhwUAIgCAAAA.',
['Kö']='Körialstrasz:BAAANQAECgUICQAAAA==.',
La='Lacus:BAABNQAECoErAAILAAkKwSPjCgCcAwALAAkKwSPjCgCcAwAAAA==.Larat:BAAANQAECgIIAwAAAA==.Laufeyson:BAAANQADCgcIGAAAAA==.Layara:BAAANQADCgUIBQAAAA==.Layil:BAAANQAECgEIAgAAAA==.Laymonath:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Lazanya:BAAANQAECgUIEAAAAA==.Lazula:BAAANQAECgEIAQAAAA==.',
Le='Legolamb:BAABNQAECoEZAAIlAAcKKQncDABnAQAlAAcKKQncDABnAQAAAA==.Leviasaint:BAABNQAECoEoAAIFAAgKNxM1VQD2AQAFAAgKNxM1VQD2AQAAAA==.',
Lh='Lhadnire:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.',
Li='Lifeinsuranc:BAAANQADCgUICQAAAA==.Lightstim:BAAANQADCgIIAgAAAA==.Lightswitch:BAAANQADCgMIAwABNQAECgUICgABAAAAAA==.Lilito:BAAANQAECgQIBQAAAA==.Limewire:BAAANQAECgcIEgAAAA==.Lion:BAAANQAECgUIBwAAAA==.',
Lo='Lodtuspuch:BAAANQABCgEIAQAAAA==.Lofie:BAABNQAECoEZAAMfAAgKaBHHFwAOAgAfAAgKaBHHFwAOAgAmAAEKBgRBjwAoAAAAAA==.Loire:BAAANQADCgMIAwAAAA==.Lonesnipa:BAAANQADCggIHwAAAA==.Looseyjoosey:BAABNQAECoEfAAMJAAgKZBCiJADQAQAJAAgKZBCiJADQAQAnAAEKkQz6NQA3AAAAAA==.Louiswu:BAABNQAECoEeAAMgAAgKYhX/KwAXAgAgAAgKNRX/KwAXAgAhAAYKfw1sOQBRAQAAAA==.',
Lu='Luciferias:BAABNQAECoEaAAMbAAcKmRdiMwDUAQAbAAcKmRdiMwDUAQASAAEKigysxQAnAAAAAA==.Luckyzounds:BAAANQABCgEIAQAAAA==.Lunariya:BAAANQAECgQIBwAAAA==.',
Ly='Lyz:BAAANQAECgIIBAAAAA==.',
Ma='Madreezov:BAAANQAECgcICQAAAA==.Madreezus:BAABNQAECoEVAAMeAAgKASMxAgBDAwAeAAgKASMxAgBDAwAQAAEKXA0hLQE9AAAAAA==.Magdalayna:BAAANQAECgcIBwAAAA==.Mahjikman:BAAANQAECgMIBAAAAA==.Mai:BAAANQAECgQIBAAAAA==.Malamuse:BAAANQAECgYIBgABNQAECggIIgAdAFwcAA==.Malfron:BAAANQADCgEIAQAAAA==.Malifrion:BAAANQADCgQIBAAAAA==.Mangodemon:BAACNQAFFIELAAMhAAUKZRmEBQC3AQAhAAUK/xeEBQC3AQAgAAEKTxEPGQBHAAA1AAQKgSIABCEACQrCIRAMABEDACEACQqaIRAMABEDABcABAoFJVEOAKMBACAABApsFWNRABQBAAAA.Mangopally:BAAANQAECgEIAgABNQAFFAUICwAhAGUZAA==.Mangoshammy:BAAANQADCgMIAwABNQAFFAUICwAhAGUZAA==.Mantheon:BAAANQAECgYIDAAAAA==.Marvel:BAABNQAECoEhAAILAAkKiiGFFABiAwALAAkKiiGFFABiAwAAAA==.Mastadonian:BAAANQAECgQIBwAAAA==.Matak:BAAANQADCgcJBwAAAA==.Maybedos:BAAANQAECgIIAgAAAA==.Mayuki:BAACNQAFFIEFAAIUAAIK0RykBACmAAAUAAIK0RykBACmAAA1AAQKgSgAAhQACQo1JYsBALoDABQACQo1JYsBALoDAAAA.',
Me='Melmard:BAAANQABCgMIBAAAAA==.Meowfurion:BAAANQADCgIIAgAAAA==.Mezzocleeze:BAAANQAECgQJBwABNQAECgQIEwABAAAAAA==.',
Mi='Minä:BAABNQAECoEYAAMFAAcKdRvlUwD7AQAFAAcKdRvlUwD7AQAGAAEK3QPhfAAgAAAAAA==.Miquella:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Mirrari:BAAANQAECgMIBQAAAA==.Misojos:BAAANQABCgYIBQAAAA==.Misschill:BAAANQADCgMIAwAAAA==.Missdumpling:BAAANQADCgUIBgAAAA==.',
Mo='Mogin:BAABNQAECoEdAAICAAkKNBxUIgC/AgACAAkKNBxUIgC/AgAAAA==.Mohim:BAAANQADCgMIAwAAAA==.Molten:BAAANQAECgMIBQAAAA==.Moonsault:BAAANQABCgMIAgAAAA==.Morganite:BAAANQAECgUIBgAAAA==.Morggoth:BAAANQADCgUIBQAAAA==.Moronica:BAAANQAECgMIAwAAAA==.Morti:BAAANQADCgMIAwAAAA==.Mox:BAAANQAECgYIDQAAAA==.',
Mu='Muehpera:BAAANQAECgYJDgAAAA==.Muya:BAAANQADCgYIBgAAAA==.',
My='Mynxe:BAAANQADCgIIAgAAAA==.Myrabeth:BAAANQADCggICAAAAA==.',
Na='Nadion:BAAANQAECgEIAQAAAA==.Naldon:BAAANQADCgUICQAAAA==.Naraine:BAAANQADCgYICAAAAA==.Nayhture:BAAANQADCgEIAQAAAA==.',
Ne='Nefka:BAAANQADCgYIBgAAAA==.Nefkhet:BAAANQADCggIHwAAAA==.Nephtyys:BAABNQAECoEUAAImAAgKjxtSGwB6AgAmAAgKjxtSGwB6AgAAAA==.Nerfbat:BAAANQAECgYIDAAAAA==.Nes:BAAANQAECgYIEAAAAA==.Netra:BAAANQAECgIIAgAAAA==.',
Ni='Niavy:BAAANQAECgUIDgAAAA==.Nightgecko:BAABNQAECoErAAIKAAkKLiDGCAA5AwAKAAkKLiDGCAA5AwAAAA==.Nightshaded:BAAANQABCgYICAAAAA==.Nihavoker:BAAANQADCgUIBQAAAA==.Nineteen:BAAANQAFFAEIAQABNQAECgMIAwABAAAAAA==.Nisroth:BAAANQAECgcICQAAAA==.Nitro:BAAANQAECgUIBQAAAA==.Niávy:BAAANQAECgIIAgAAAA==.',
No='Noedos:BAAANQAECgcICgAAAA==.Nofoxgivn:BAAANQAECgEIAQAAAA==.Nogdem:BAAANQAECgYIEgAAAA==.Novaprime:BAABNQAECoEaAAMNAAcKUxqiZwC7AQANAAYKwhiiZwC7AQALAAUK1BW6xgBVAQAAAA==.Noyy:BAAANQADCgUJBAABNQADCgYIBgABAAAAAA==.',
['Nù']='Nùrse:BAAANQAECgcIBwAAAA==.',
Ob='Obeevoker:BAAANQAECgYIEwAAAA==.',
Oc='Ocala:BAAANQADCgMIAwAAAA==.',
Og='Ogryn:BAAANQADCgMIAwAAAA==.',
Om='Omgsogoth:BAAANQABCgEIAQAAAA==.',
Oo='Oopsimdead:BAAANQAECgYICQAAAA==.',
Or='Orziver:BAAANQABCgIIAgAAAA==.',
Os='Ostï:BAAANQADCgYIBgABNQAECgkJKwAZAO4hAA==.',
Ot='Otosan:BAABNQAECoEaAAICAAgKhxc0RgAdAgACAAgKhxc0RgAdAgAAAA==.',
Pa='Palshi:BAAANQADCgMIAwABNQAECgYIEwABAAAAAA==.Pandariock:BAAANQAECgMIBAAAAA==.Pandfu:BAAANQAECgIIAgAAAA==.Parfait:BAAANQADCgYIBgAAAA==.Pawsatyou:BAABNQAECoEYAAIUAAkKVhrsCAC1AgAUAAkKVhrsCAC1AgAAAA==.',
Pe='Peaberry:BAAANQADCggJCAABNQAECgcIBwABAAAAAA==.Peachiekeen:BAAANQAECgMIAgAAAA==.Peekãboo:BAABNQAECoEjAAIfAAkK8xx5CQDSAgAfAAkK8xx5CQDSAgAAAA==.Peewheewoo:BAAANQAECgQIBAAAAA==.Peliossa:BAAANQADCggIFQAAAA==.Pelzy:BAAANQAECgQIBQAAAA==.Pepae:BAAANQAECgcIEgAAAA==.',
Ph='Pholia:BAAANQAECgIIAgAAAA==.',
Pi='Pieni:BAAANQADCgYIFAAAAA==.Pinkrose:BAAANQAECgMIBAAAAA==.Pizza:BAAANQAECgUIEQAAAA==.',
Pl='Platomatrixx:BAAANQADCgYICwAAAA==.',
Po='Poko:BAAANQADCggICgAAAA==.Pollyanna:BAAANQAECgIIAwAAAA==.Poony:BAABNQAECoEgAAMEAAgKliPANwAMAwAEAAgKKCPANwAMAwAMAAIKJCJxIADEAAAAAA==.',
Pr='Proximus:BAAANQAECgEJAQABNQAECggIIwAFALYbAA==.',
Ps='Psyop:BAABNQAECoEwAAIFAAkKRCGYCABtAwAFAAkKRCGYCABtAwAAAA==.',
Pu='Punnyname:BAABNQAECoEZAAIPAAgKFBZOHQDUAQAPAAgKFBZOHQDUAQAAAA==.Purrsian:BAAANQAECgQIBAAAAA==.',
Qb='Qberks:BAABNQAECoEmAAIHAAgKmx6FJgCCAgAHAAgKmx6FJgCCAgAAAA==.',
Qu='Quaddh:BAAANQADCggIDAAAAA==.Quellif:BAAANQABCgcIDAAAAA==.Quincee:BAAANQAECgYICQAAAA==.',
Ra='Radtiz:BAAANQADCgEIAQAAAA==.Raenin:BAAANQAECgUIBwAAAA==.Ragingdraem:BAABNQAECoEgAAIRAAgKeRz6MwCDAgARAAgKeRz6MwCDAgAAAA==.Raidei:BAABNQAECoEdAAMmAAcKCBBCOQCvAQAmAAcKxA5COQCvAQAfAAUKZQ67LQA1AQAAAA==.Rainoffur:BAABNQAECoEbAAICAAcK+hr6RwAWAgACAAcK+hr6RwAWAgAAAA==.Rakeripwait:BAAANQADCgUICgAAAA==.Raoulqc:BAAANQAECgEIAQAAAA==.Ratatosk:BAAANQAECgUIDwAAAA==.Rathan:BAABNQAECoEbAAIQAAgKmhwfTACLAgAQAAgKmhwfTACLAgAAAA==.Ravenanarchy:BAABNQAECoErAAMXAAkKihliBwBlAgAXAAgKyRliBwBlAgAgAAkKaxCxKwAZAgAAAA==.Rawheadrexx:BAAANQAECgIIAgAAAA==.',
Re='Redpawedfox:BAABNQAECoEhAAIJAAgK7hvJFAB/AgAJAAgK7hvJFAB/AgAAAA==.Redsun:BAAANQAECgYICwAAAA==.Rekviem:BAAANQAECgIIBAAAAQ==.Remyz:BAAANQADCgUIBQAAAA==.Revie:BAAANQADCgQIBAAAAA==.',
Rh='Rhavaniel:BAAANQAECgQIBwAAAA==.',
Ri='Rielexia:BAAANQABCgYIBgAAAA==.Rikola:BAAANQAECgMJAwAAAA==.Rizzen:BAAANQADCggIFgAAAA==.',
Ro='Roderika:BAAANQAECgEIAQAAAA==.Roderis:BAAANQAECggICQAAAA==.Rogmar:BAAANQABCgIIAgAAAA==.Royalnewb:BAACNQAFFIEIAAIEAAMK8wQVMwDFAAAEAAMK8wQVMwDFAAA1AAQKgSoAAwwACQpxHPgJAP4BAAQACQq5FK5zAIACAAwACApsHPgJAP4BAAAA.Royston:BAABNQAECoEiAAIdAAgK1wwwFwCLAQAdAAgK1wwwFwCLAQAAAA==.',
Ru='Rucereal:BAAANQAECgQICwAAAA==.Rufous:BAAANQAECgYIDgAAAA==.',
Rw='Rwaga:BAAANQAECgIIBAAAAA==.',
Ry='Ryliea:BAAANQADCgMIAwAAAA==.Rynsidious:BAABNQAECoEoAAIgAAgKQhNxMQDuAQAgAAgKQhNxMQDuAQAAAA==.',
['Rã']='Rãin:BAAANQAECgQICAABNQAECggIJwAVAKkVAA==.',
['Rì']='Rìkú:BAAANQADCgUIBQAAAA==.',
Sa='Sabelle:BAAANQAECgMIBAAAAA==.Sableanne:BAAANQABCgYIDAAAAA==.Sabîne:BAABNQAECoEcAAIDAAcKgBh9YwAkAgADAAcKgBh9YwAkAgAAAA==.Saeton:BAABNQAECoEjAAIPAAkKzhCnGwDmAQAPAAkKzhCnGwDmAQAAAA==.Sahlaris:BAAANQAECgYIEgAAAA==.Salno:BAAANQADCgUJCAAAAA==.Samsonite:BAABNQAECoEWAAIDAAgKohcaXgAyAgADAAgKohcaXgAyAgAAAA==.Sanji:BAAANQADCgIIAgAAAA==.Sariths:BAAANQABCggIEgAAAA==.Savreen:BAAANQADCgYIBgAAAA==.',
Sc='Scrubpal:BAAANQADCggIFAAAAA==.',
Se='Seasalt:BAAANQABCgEIAQAAAA==.Sekhmet:BAAANQADCgMIAwAAAA==.Sekstrasza:BAAANQADCggIGgAAAA==.Sens:BAAANQAECgUICgAAAA==.Serrik:BAAANQAECggIDgAAAA==.Sersilkyhair:BAAANQAECgcIEwAAAA==.',
Sh='Shamanoid:BAAANQAECgMIBQABNQAECgYIEQABAAAAAA==.Shamonz:BAAANQADCgMIAwAAAA==.Shasta:BAABNQAECoEeAAILAAgKbxV/fAABAgALAAgKbxV/fAABAgAAAA==.Shortieabc:BAAANQAECgMIAwAAAA==.Shortmark:BAAANQAECgMIBgAAAA==.',
Si='Siik:BAAANQAECggIEQAAAA==.Silaena:BAAANQAECgYIDAAAAA==.Silverlocke:BAAANQAECgQIEwAAAA==.Sindaris:BAABNQAECoEXAAQJAAkKvA7lIgDiAQAJAAkKvA7lIgDiAQAVAAUK6xdYUgBmAQAnAAMKuxmcHgDxAAAAAA==.Sinedchi:BAAANQAECgEIAQABNQAECgkJFwAJALwOAA==.',
Sj='Sj:BAAANQADCgQIBAAAAA==.',
Sk='Skillbeam:BAAANQAECggIDwAAAA==.Skillcrusade:BAAANQAECgMIBAAAAA==.Skillscales:BAACNQAFFIELAAMjAAUKNQ1CBgAmAQAjAAQKIA5CBgAmAQAiAAMKbA0YBgDXAAA1AAQKgSkAAyIACQoTIVYDAOUCACIACQqCH1YDAOUCACMACAqLIZwMAIECAAAA.Skyfallen:BAAANQAECgIIAgAAAA==.',
Sl='Sleepydk:BAABNQAECoEZAAISAAgKzCEpFgDlAgASAAgKzCEpFgDlAgAAAA==.Slopysecondz:BAAANQAECgEIAQABNQAECgQIDQABAAAAAA==.Slovik:BAAANQAECgEIAgAAAA==.Slowbro:BAAANQAECgIIAgAAAA==.',
Sm='Smok:BAAANQAECgIIAgAAAA==.',
Sn='Snafflo:BAAANQAECgcIEQAAAA==.Snekhet:BAABNQAECoEiAAMGAAgKTRZ6HQAxAgAGAAgKTRZ6HQAxAgAFAAcKXBfAVwDtAQAAAA==.',
So='Softscars:BAAANQAECgIIAwAAAA==.Solanea:BAAANQAECgUIEQAAAA==.Solaura:BAAANQAECgYIDAAAAA==.Solo:BAAANQADCgMIAwABNQAECggIJQAQAHYeAA==.Sorcero:BAAANQAECgYIEgAAAA==.Sorcforce:BAAANQADCgUIBQAAAA==.Soultelage:BAAANQAECgIIAwAAAA==.Sourwine:BAAANQADCgYICQAAAA==.',
Sp='Spaceman:BAABNQAECoFOAAIQAAkKmSZZAgDpAwAQAAkKmSZZAgDpAwABNQAECgkJKQALAM0mAA==.Spire:BAAANQAECgUIBQAAAA==.Sporkeh:BAAANQADCgMIAwAAAA==.Spritedk:BAAANQADCgcIBwABNQAECggIIAANAEYiAA==.Spritelock:BAAANQADCgQIAgABNQAECggIIAANAEYiAA==.Spritemonk:BAAANQAECgQICgABNQAECggIIAANAEYiAA==.Spritepally:BAABNQAECoEgAAINAAgKRiLrFAAbAwANAAgKRiLrFAAbAwAAAA==.Spritepriest:BAAANQAECgQIDAABNQAECggIIAANAEYiAA==.',
St='Starbreeze:BAAANQADCgEIAQAAAA==.Stellara:BAAANQADCgQIBwAAAA==.Stiff:BAAANQADCgQIBAAAAA==.Stiffmcgee:BAAANQAECgUIBgAAAA==.Stormdancer:BAABNQAECoFBAAIWAAgKbR+uCQDHAgAWAAgKbR+uCQDHAgAAAA==.Stormpage:BAAANQAECgIIAwABNQAFFAMIBQAIALUEAA==.Strangiatie:BAAANQADCgYJBwAAAA==.Strych:BAABNQAECoEeAAMfAAkKlhrrDgB6AgAfAAgK7hrrDgB6AgAmAAUKFBfcQwB0AQABNQAECgkJLQAfAB8eAA==.Stumpyfoot:BAABNQAECoEZAAIJAAgKSRcKHAAqAgAJAAgKSRcKHAAqAgAAAA==.Stygi:BAAANQAECgQICQAAAA==.Stãrs:BAACNQAFFIEMAAMVAAUKyhg0CgCfAQAVAAUKyhg0CgCfAQAJAAEK1BN6EABSAAA1AAQKgS4AAxUACQpUIxcNAFMDABUACQpUIxcNAFMDAAkAAgpMBkRcAF8AAAAA.',
Su='Suki:BAAANQADCggICwAAAA==.Sulawesi:BAAANQADCggICAABNQAECgcIBwABAAAAAA==.Sultan:BAAANQAECgYIBwAAAA==.Surfacing:BAABNQAECoEjAAIDAAkKXiJvEQBHAwADAAkKXiJvEQBHAwAAAA==.',
Sw='Swingin:BAAANQADCgIIAgAAAA==.',
Sy='Syntharia:BAABNQAECoEmAAMiAAgK9gdCDQBOAQAiAAgK4gdCDQBOAQAjAAcKvQOzIwAGAQAAAA==.',
Ta='Taffigosa:BAABNQAECoEfAAIiAAgK6Q+TCQC5AQAiAAgK6Q+TCQC5AQAAAA==.Taffy:BAAANQADCggIGgAAAA==.Talomea:BAAANQAECgEIAgAAAA==.Tanthel:BAABNQAECoEeAAITAAgKmBIzIgDqAQATAAgKmBIzIgDqAQAAAA==.Taursain:BAAANQAECgMIAwAAAA==.',
Tb='Tbh:BAAANQAECgUIBQABNQAECgcIFwACAFMiAA==.',
Te='Terranteal:BAAANQAECggIEgAAAA==.Terraquis:BAAANQAECgIIAgAAAA==.Terravolta:BAABNQAECoEpAAICAAkKKhH4SwAHAgACAAkKKhH4SwAHAgAAAA==.Teshaa:BAAANQADCggICAAAAA==.Testarossa:BAABNQAECoEZAAIgAAgKjCSeDAAuAwAgAAgKjCSeDAAuAwAAAA==.',
Th='Themage:BAAANQADCgQJBAABNQAECgcIGAAOADAjAA==.Thenian:BAAANQADCgUIBgAAAA==.Therealvenat:BAABNQAECoEWAAMIAAcKYRC2hQCqAQAIAAcKYRC2hQCqAQAcAAEKHAZyegArAAAAAA==.Thiccbiddies:BAABNQAECoE2AAIeAAgKWx4FBQCxAgAeAAgKWx4FBQCxAgAAAA==.Thort:BAAANQADCgQIBAAAAA==.Thunderwings:BAAANQAECgMIBQAAAA==.',
Ti='Tigan:BAABNQAECoEaAAIhAAcKKBPBKgDLAQAhAAcKKBPBKgDLAQAAAA==.Tigra:BAABNQAECoEgAAIVAAkKwA3gOAD/AQAVAAkKwA3gOAD/AQAAAA==.Timelord:BAAANQAECgUIBwAAAA==.Timeweaver:BAABNQAECoErAAIkAAkKNQrMHQDTAQAkAAkKNQrMHQDTAQAAAA==.Tirione:BAAANQAECgYICwAAAA==.Tirogue:BAAANQADCgUIBgAAAA==.',
To='Toastshark:BAABNQAECoEaAAIEAAgKFhXVmgAtAgAEAAgKFhXVmgAtAgAAAA==.Toranaar:BAAANQADCggIDgAAAA==.Torpal:BAAANQADCggIHwABNQAECggIHgALAG8VAA==.Totorö:BAABNQAECoEnAAIVAAgKqRXtMgAnAgAVAAgKqRXtMgAnAgAAAA==.',
Tr='Traiturner:BAAANQAECgUIDwAAAA==.Trayfu:BAAANQAECgMIBAAAAA==.Treebeárd:BAAANQADCgIIAgAAAA==.Trice:BAAANQAECgQIDAABNQAECgYIBwABAAAAAA==.Trillion:BAAANQAECgYIEwAAAA==.Trostani:BAAANQAECgYIBQAAAA==.Truc:BAAANQADCgMIAwAAAA==.Trusker:BAAANQAECgYIDAAAAA==.',
Ts='Tsaavas:BAAANQAECgMICQAAAA==.Tsereya:BAAANQADCgYIBgAAAA==.Tsugumomo:BAAANQADCggICAABNQAFFAYIEwATAE4gAA==.',
Tu='Tullandil:BAAANQABCgQIAgAAAA==.',
Tw='Twitty:BAAANQAECgYIEwABNQAFFAUIDAANAAsNAA==.',
Ty='Tyloestus:BAAANQAECgYJBwAAAA==.Tyragni:BAAANQAECgEIAQAAAA==.Tyravana:BAAANQADCgYIBgAAAA==.Tystriel:BAAANQAECgYIDwAAAA==.',
['Tí']='Tíamat:BAABNQAECoEZAAIEAAkK5wS+4wCbAQAEAAkK5wS+4wCbAQAAAA==.',
Ul='Ulasar:BAAANQAECgUIBwAAAA==.',
Un='Unmilkable:BAAANQADCgUIBQAAAA==.Untarot:BAAANQADCgMJBAAAAA==.',
Va='Valdanyr:BAEANQAECgMIBQAAAA==.Valimar:BAAANQADCgEIAQABNQAECggIGQAgAIwkAA==.Vallenar:BAAANQAECgYICwAAAA==.Valliant:BAAANQAECgMIAwABNQAECgYIDAABAAAAAA==.Valnullis:BAAANQADCgUIBwAAAA==.Valorfist:BAAANQADCgQJBAAAAA==.Valídus:BAAANQADCgYIDwAAAA==.Vampteabag:BAAANQADCggIDQAAAA==.Vanden:BAAANQAECgUICQABNQAECgcIBwABAAAAAA==.Varsi:BAACNQAFFIEFAAIDAAIKWRSIHgCjAAADAAIKWRSIHgCjAAA1AAQKgSIABAMACQo4IvsjAOkCAAMACQo4IvsjAOkCAAoAAQr1BHOAAC8AABoAAQpTChASAC4AAAAA.',
Ve='Veetor:BAAANQAECgQICgAAAA==.Velannia:BAAANQADCgMIAwAAAA==.Velash:BAABNQAECoEbAAIhAAcKOyNfEQDQAgAhAAcKOyNfEQDQAgAAAA==.Vendorin:BAAANQAECgMIBQAAAA==.Verratanikto:BAAANQAECggIBwAAAA==.Verwínd:BAABNQAECoEZAAIEAAgK9wKKGgE5AQAEAAgK9wKKGgE5AQAAAA==.',
Vi='Virusgt:BAAANQAECgcICAAAAA==.Vitner:BAAANQAECgcIDQABNQAECgkJFwAIAKQWAA==.',
Vn='Vn:BAAANQAECgIIAgABNQAECgYIEwABAAAAAA==.',
Vo='Voidbeam:BAAANQAECgYIBQAAAA==.Voidsta:BAAANQADCgIIAgAAAA==.Volgur:BAAANQADCggIHwAAAA==.Volker:BAABNQAECoEiAAIQAAgKCRdrawAvAgAQAAgKCRdrawAvAgAAAA==.',
Wa='Walk:BAAANQAECgEIAQABNQAECgcIGAAgALgeAA==.',
We='Wemad:BAAANQAECgcICQAAAA==.Wenotknow:BAABNQAECoEVAAIWAAcKLx1dEQAzAgAWAAcKLx1dEQAzAgAAAA==.',
Wi='Wife:BAABNQAECoElAAMQAAgKdh5SSgCRAgAQAAgKdh5SSgCRAgAdAAYKghbXFgCQAQAAAA==.Wildraubtier:BAAANQADCgIIAgAAAA==.',
Wo='Wormsloe:BAAANQADCgYIBgAAAA==.',
Wy='Wyfaggro:BAAANQADCgMIAwAAAA==.',
Xa='Xaida:BAABNQAECoEdAAMOAAcK/RF0EgCdAQAOAAcKlxF0EgCdAQATAAcKOA3NMABaAQAAAA==.Xaldania:BAAANQADCggIGQAAAA==.',
Xc='Xcaps:BAAANQADCgcIBwAAAA==.',
Xs='Xstinger:BAAANQADCgUIBQAAAA==.',
Xu='Xuing:BAABNQAECoErAAIZAAkK7iHgAwBbAwAZAAkK7iHgAwBbAwAAAA==.Xuingg:BAAANQAECgcIDgABNQAECgkJKwAZAO4hAA==.',
Ya='Yarp:BAAANQADCgUIBQAAAA==.Yarro:BAABNQAECoEoAAIDAAgKHg9aZAAhAgADAAgKHg9aZAAhAgAAAA==.',
Ye='Yesdaddy:BAAANQADCggJHwAAAA==.',
Yl='Yliana:BAAANQAECgIIAwABNQAECggIIwALAPkSAA==.',
Yo='Yorozu:BAAANQAECgUICgAAAA==.Young:BAAANQADCgQICAABNQAECgcICwABAAAAAA==.Youngblud:BAAANQAECgcICwAAAA==.Youngplasma:BAAANQAECgEIAQABNQAECgcICwABAAAAAA==.Youngwarlock:BAAANQAECgQIBgABNQAECgcICwABAAAAAA==.Yourhealor:BAAANQADCgYIBgAAAA==.',
Yu='Yugi:BAAANQAECgYICgAAAA==.',
Za='Zaela:BAAANQADCgQIBAAAAA==.Zahira:BAAANQAECgUIEwAAAA==.Zaratras:BAAANQADCgYIBgAAAA==.Zatilia:BAAANQADCgMIAwAAAA==.Zax:BAAANQAECgYIEgAAAA==.Zaxtor:BAAANQAECgQIBAAAAA==.',
Ze='Zenatra:BAAANQADCggIEwAAAA==.Zerkku:BAAANQAECgcIBwAAAA==.Zeroximo:BAABNQAECoEWAAIEAAcKTxQhxQDWAQAEAAcKTxQhxQDWAQAAAA==.',
Zi='Zieren:BAAANQADCgcIDQABNQAECgYIEAABAAAAAA==.Zipline:BAABNQAECoEYAAIgAAcKuB42JwA6AgAgAAcKuB42JwA6AgAAAA==.Zirathiel:BAAANQAECgEIAQAAAA==.',
Zo='Zofie:BAAANQADCggIFwAAAA==.Zogz:BAAANQAECgUICQAAAA==.Zombiexcat:BAAANQAECgUIBgAAAA==.Zorakiel:BAABNQAECoEgAAMPAAgKlhyDFAA5AgALAAgK2BtUYABMAgAPAAgKZheDFAA5AgAAAA==.',
Zu='Zulema:BAAANQABCgQIBAAAAA==.',
Zw='Zwiebelle:BAAANQAECgYIEAAAAA==.',
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
