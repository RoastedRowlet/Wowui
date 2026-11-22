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

local lookup = {'Warlock-Demonology','Priest-Holy','Paladin-Protection','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer','Druid-Feral','DemonHunter-Vengeance','Mage-Arcane','Shaman-Elemental','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Mage-Fire','Mage-Frost','DeathKnight-Frost','Warrior-Arms','Unknown-Unknown','Priest-Shadow','Monk-Brewmaster','Priest-Discipline','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Shaman-Enhancement','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Druid-Balance','Rogue-Outlaw','DeathKnight-Unholy',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acbabcaa:BAAANQAECgEIAQAAAA==.Aceon:BAAANQAECgIIBAAAAA==.Aceonarcher:BAAANQAECgQICAAAAA==.',
Ad='Adfectia:BAABNQAECn81AAIBAAoKlwqzagCYAQABAAoKlwqzagCYAQAAAA==.',
Ae='Aelianna:BAAANQAECgcIDQAAAA==.Aeryana:BAACNQAFFH8HAAICAAQKzRo2FQBeAQACAAQKzRo2FQBeAQA1AAQKfzwAAgIACgptI+QNAFUDAAIACgptI+QNAFUDAAAA.Aeth:BAAANQAECgYIDAABNQAECgoKJAADAPwiAA==.Aethér:BAAANQAECgYIDwABNQAFFAgIEQAEANUUAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgoKKQADAJUfAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgQICQAAAA==.',
Al='Alberoo:BAAANQABCgQIBAAAAA==.Alexstrászá:BAABNQAECn86AAMFAAoKVA79BwC0AQAFAAoKVA79BwC0AQAGAAMKzwJ3NwBTAAAAAA==.Aloria:BAAANQADCgEIAQAAAA==.Alydria:BAAANQADCgUIBQAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgUIDQAAAA==.',
Am='Amaarii:BAAANQABCgQJCAAAAA==.Ambeia:BAAANQAECgMIBQAAAA==.Amewow:BAACNQAFFH8aAAMGAAgKSh+jAADYAQAGAAcKOCOjAADYAQAFAAEKpwtsDgBNAAA1AAQKf14AAwYACgr/JYoAAHMDAAYACgr/JYoAAHMDAAcABwqAFpUSANUBAAAA.Amoril:BAABNQAECn8pAAIIAAoKRQYBKQBRAQAIAAoKRQYBKQBRAQAAAA==.Amìko:BAAANQADCggIEAAAAA==.',
An='Anarchy:BAABNQAECn88AAIJAAoKMBaKDQD0AQAJAAoKMBaKDQD0AQAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Andrewchau:BAAANQAECgIIAgAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Annòy:BAABNQAECn9aAAIKAAoKFSCoAwAkAwAKAAoKFSCoAwAkAwAAAA==.Anorakswrath:BAABNQAECn8dAAILAAkKXQQQEAFyAQALAAkKXQQQEAFyAQAAAA==.',
Ap='Apokai:BAAANQAECgcIBwABNQAFFAQIBwAMAOcbAA==.Apophys:BAAANQADCgcIIwAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Ariella:BAAANQADCgYICQAAAA==.Artfulrodent:BAAANQADCgQIBAAAAA==.Aruneza:BAABNQAECn8dAAMGAAgKdhFQHQB5AQAGAAcKjg1QHQB5AQAHAAYKNgvYLwAfAQAAAA==.',
As='Asherous:BAAANQADCgQICQABNQAECgkJIwANAB8hAA==.Ashèr:BAABNQAECn8jAAMNAAkKHyHrIAC4AgANAAkKHyHrIAC4AgAOAAMKbgYJawFeAAAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgUIEQABNQAECgoKIwAPADEUAA==.Auralion:BAAANQAECgQIBAAAAA==.Autoignition:BAABNQAECn8XAAQQAAkKthwwBAB1AQALAAcKqB9XwgAAAgAQAAUKDxswBAB1AQARAAMKlxnnIwDOAAABNQAECgoKIAASAAIiAA==.',
Az='Azornia:BAAANQAECgMIAwAAAA==.',
Ba='Badcompanytt:BAAANQADCgUIAwAAAA==.Bahnkano:BAABNQAECn8WAAIMAAgK6QSTwgANAQAMAAgK6QSTwgANAQAAAA==.Bakeddh:BAAANQADCgYIDAAAAA==.Balwal:BAAANQAECgIIAgAAAA==.Banditz:BAAANQADCgcIDwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAABNQAECn8YAAITAAYK9QMf+QDqAAATAAYK9QMf+QDqAAAAAA==.Beenah:BAAANQAECgUIEgAAAA==.Beyshunt:BAAANQADCgYICgAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAABNQAECn8YAAILAAoKwgpElQB7AQALAAoKwgpElQB7AQAAAA==.',
Bo='Boltcutter:BAAANQADCgYICgAAAA==.Bombmagic:BAAANQADCgMIAwAAAA==.Bonesmccoy:BAAANQABCgYIBgAAAA==.Boomie:BAABNQAFFH8FAAIHAAUKqCTcBAAiAgAHAAUKqCTcBAAiAgABNQAFFAgIBAAUAAAAAA==.Boopty:BAABNQAECn8WAAIVAAYK6Qc1PgC3AAAVAAYK6Qc1PgC3AAAAAA==.Booptydo:BAAANQADCggIHQAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAABNQAECn8cAAIPAAkKYQrXpABpAQAPAAkKYQrXpABpAQAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQAECgYICQABNQAFFAgIEQAEANUUAA==.Brazyn:BAAANQADCggIIwAAAA==.Brevarda:BAAANQAECgYIDQAAAA==.Brewcelee:BAABNQAECn8/AAIWAAoKRg47CgCfAQAWAAoKRg47CgCfAQAAAA==.',
Bu='Bubblzmgee:BAABNQAECn9aAAMXAAoKKB7zAABdAwAXAAoKKB7zAABdAwAVAAEKyQkyYgA4AAAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCgcIDwAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQAECgMIAwAAAA==.',
Ca='Cakeman:BAAANQAECgQIBAAAAA==.Capone:BAABNQAECn8mAAIYAAkKyxVqHQAiAgAYAAkKyxVqHQAiAgAAAA==.Captiva:BAAANQAECgEIAQAAAA==.Caracalous:BAAANQAECgYIDAAAAA==.Carindria:BAAANQADCggILAAAAA==.Carninn:BAAANQADCgcIBwAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cat:BAAANQAECgUICgAAAA==.Cattiebrie:BAAANQAECgQIDwAAAA==.Caylavana:BAABNQAECn9GAAMZAAoKqB8fAgDCAgAZAAkKAR0fAgDCAgAPAAgKqB+WSwCLAgAAAA==.',
Ce='Celaylria:BAABNQAECn9LAAIaAAoK+xTlEgAUAgAaAAoK+xTlEgAUAgAAAA==.Ceyine:BAAANQAECgEIAQAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgUICQAAAA==.Clugorn:BAABNQAECn8mAAIbAAoK2QygHwABAQAbAAoK2QygHwABAQAAAA==.Clydè:BAABNQAECn8jAAIKAAoKEhX5CADjAQAKAAoKEhX5CADjAQAAAA==.',
Co='Codyj:BAAANQADCggIDgAAAA==.Colossus:BAAANQADCggJCwAAAA==.Colourhunt:BAABNQAECn8YAAMaAAkKMxAwPQBoAQAPAAcKZw6MnwDHAQAaAAcKCw4wPQBoAQAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAABNQAECn8rAAIcAAkKHRv6IgCfAgAcAAkKHRv6IgCfAgAAAA==.Copestabb:BAAANQAECgMIBAABNQAECgkJKwAcAB0bAA==.Corrode:BAAANQAECgIIAwAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crimie:BAAANQADCggICAAAAA==.Crinke:BAAANQABCgIIAgAAAA==.Crusadare:BAAANQAECgQIBAAAAA==.',
Cu='Culture:BAAANQAECgYIEQAAAA==.',
Cy='Cybeldin:BAABNQAECn8iAAMPAAgKSAnhrABYAQAPAAgKSAnhrABYAQAaAAQK8QIzbgB3AAAAAA==.Cyberdemonxd:BAAANQADCgYIDAABNQAECgoKHgASAH4OAA==.Cyndyr:BAAANQAECgMIBAAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAABNQAECn8rAAIIAAoKkBAxGwDRAQAIAAoKkBAxGwDRAQAAAA==.Dalarrus:BAABNQAECn8WAAMdAAgKhgy3WwCaAQAdAAgKhgy3WwCaAQAeAAYKEwjcXQA/AQABNQAECgoKRgAZAKgfAA==.Dalishya:BAAANQADCgQIBAAAAA==.Darbane:BAAANQAECgMIAwAAAA==.Darek:BAABNQAECn8XAAILAAgKRAlDNgEyAQALAAgKRAlDNgEyAQAAAA==.Darilyns:BAAANQAECgMIAwAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgcIHQAAAA==.Darylinn:BAAANQADCgQJBgAAAA==.Daymann:BAABNQAECn8eAAMCAAoKQBSzRAAlAgACAAoKxhKzRAAlAgAXAAEKKxzyIgBQAAAAAA==.',
De='Deathcore:BAAANQAECgIIAQABNQAECgoKOwALACkUAA==.Demonrife:BAAANQABCgYIBgABNQADCgcIHQAUAAAAAA==.Dependabull:BAAANQADCgYIBgABNQAECgQICQAUAAAAAA==.Dernis:BAAANQAECgIIAgABNQAECgoKMQATAMQeAA==.Derplock:BAAANQADCgcIEAAAAA==.Deshaman:BAAANQADCgMIAwABNQAFFAYIHQAPAKsiAA==.Devilbeast:BAAANQAECgQIDQAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgYIDgABNQAECgQICQAUAAAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Diaous:BAAANQADCgcIEQAAAA==.Disasterina:BAAANQADCgcIBwABNQAECgoKRQAIAJ0hAA==.Disgruntled:BAAANQAECgcIEQAAAA==.',
Do='Docbrown:BAAANQADCgEIAQAAAA==.Dontormentaa:BAABNQAECn8lAAMTAAoKIBNtdgAzAgATAAoKohJtdgAzAgAfAAEK/Bl9LQBNAAAAAA==.Dontormentaj:BAABNQAECn8iAAQRAAgKXxfiFwA7AQALAAgK1xYpmABQAgARAAQKHB3iFwA7AQAQAAMKmRR7BwDCAAABNQAECgoKJQATACATAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAABNQAECn8gAAIFAAkK1Qo1EgAQAQAFAAkK1Qo1EgAQAQAAAA==.Dragonbrew:BAAANQADCggICAAAAA==.Dragonfang:BAAANQAECggIEQABNQAECgoKIAASAAIiAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQAUAAAAAA==.Dreamhammer:BAAANQABCgcIDwAAAA==.Dreamlesnite:BAAANQABCggIFAAAAA==.Dreidelman:BAAANQAECgQIBAAAAA==.Drkstar:BAAANQABCgEIAQAAAA==.Druvisept:BAAANQAECgYICAAAAA==.',
Du='Dugdimadome:BAAANQAECgQIAwAAAA==.Dunthur:BAAANQAECgMIBAABNQAECgYIBQAUAAAAAA==.',
Dy='Dylora:BAABNQAECn8lAAIgAAgKgRsBDAB1AgAgAAgKgRsBDAB1AgAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECn8xAAMNAAoKXiKJCQB8AwANAAoKXiKJCQB8AwAOAAEKqAw/wwEnAAABNQAFFAkJKwACANUaAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAABNQAECn8cAAILAAgK3xnV1ADdAQALAAgK3xnV1ADdAQAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgYIDAAAAA==.Elystaria:BAABNQAECn8aAAMDAAYKsR00KAAwAQAOAAYKnxtE0AB7AQADAAUK3R00KAAwAQAAAA==.',
Em='Emokins:BAEBNQAECn8pAAIMAAgK2SEyJwDmAgAMAAgK2SEyJwDmAgAAAA==.',
En='Enyos:BAAANQADCgcIEAAAAA==.',
Ep='Epicnakedman:BAABNQAECn8cAAIPAAkKRSH0HADNAgAPAAkKRSH0HADNAgABNQAECgoKSQANAKgaAA==.',
Er='Eronoljr:BAAANQADCgEIAQAAAA==.Erubus:BAACNQAFFH8FAAIWAAQKzRcvBwCRAAAWAAQKzRcvBwCRAAA1AAQKf0UABBYACgq0Ig8DAGkDABYACgq0Ig8DAGkDACEACQruGKwWAAUCACAAAwpnCsg1AF4AAAAA.Erubuss:BAABNQAECn8UAAIPAAgKXhOfjQCbAQAPAAgKXhOfjQCbAQAAAA==.Erubussyy:BAAANQAECgUIBQAAAA==.Eryss:BAABNQAECn8aAAIPAAYKEQr70wAKAQAPAAYKEQr70wAKAQAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Fa='Faithfulone:BAABNQAECn8VAAIcAAYKWghajADQAAAcAAYKWghajADQAAAAAA==.Farfidnoogan:BAAANQABCgQIBAAAAA==.Fateforged:BAAANQAECgYIBQAAAA==.Fatercul:BAAANQAECgIIAgAAAA==.',
Fd='Fdk:BAABNQAECn8fAAISAAcK2RzwOAC8AQASAAcK2RzwOAC8AQAAAA==.',
Fe='Fellariene:BAAANQADCggIDQAAAA==.',
Fi='Fistenlick:BAAANQADCgQIBAABNQADCgcIEgAUAAAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgYICwAAAA==.',
Fr='Freim:BAABNQAECn8iAAIfAAkKCyOhAQAwAwAfAAkKCyOhAQAwAwAAAA==.',
['Fà']='Fàmous:BAAANQAECgcICQAAAA==.',
Ga='Galabris:BAABNQAECn8kAAIcAAgKfx7rKQB1AgAcAAgKfx7rKQB1AgAAAA==.Garavos:BAAANQAECgIIAgAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.Gazzik:BAAANQAECgUICAAAAA==.',
Ge='Gera:BAAANQAECgIIAgAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECgkJFAAJAPMYAA==.Ghoulmania:BAAANQAECggICwAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQAECgYIEgAAAA==.Ginhei:BAAANQADCgcIBwAAAA==.Gitchusum:BAAANQAECgYIBgAAAA==.',
Gl='Glaivenez:BAAANQAECggIBgAAAA==.Gleenna:BAABNQAECn8mAAMiAAoKQxLPVgC4AQAiAAoKQxLPVgC4AQAMAAEKAAD4SAEqAAAAAA==.Glorify:BAAANQAECgUICAABNQAECgoKJgAcAOkcAA==.',
Go='Goose:BAABNQAECn82AAMCAAkKEyIaFgAhAwACAAkKEyIaFgAhAwAXAAEK3BevJABGAAAAAA==.Gormladin:BAAANQADCgYIFwAAAA==.Gormstorm:BAABNQAECn8YAAMiAAYKBxpeXwCbAQAiAAYKBxpeXwCbAQAMAAIKZANzIQFOAAAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grimsreaper:BAAANQADCgQIBAAAAA==.Grouchy:BAAANQADCgQIBgABNQAECggIHwASANkcAA==.',
Gw='Gwynythe:BAAANQADCgYICgAAAA==.',
Ha='Hadess:BAAANQADCgQIBAAAAA==.Hadriac:BAAANQAECgIIAgAAAA==.Hailes:BAAANQABCgIIAQAAAA==.Halfang:BAAANQADCggINAAAAA==.Halphas:BAAANQADCggICAABNQAECgMIAgAUAAAAAA==.Hanta:BAABNQAECn8qAAMPAAoKzhiMOwBhAgAPAAoKzhiMOwBhAgAaAAEK2gdMcgApAAAAAA==.Hanterruso:BAAANQAECgIIAwAAAA==.Haplò:BAAANQAECgIIAgAAAA==.Hastebuff:BAABNQAECn8ZAAIMAAoK/wtJUACXAQAMAAoK/wtJUACXAQAAAA==.',
He='Healless:BAAANQAECgIIAgABNQAECgoKRgAZAKgfAA==.Hentaime:BAAANQABCgMIAwAAAA==.',
Hi='Hildegarde:BAAANQADCggICAABNQAECgcIFgAIAMMUAA==.Hitpoints:BAAANQADCgYIDAABNQAECgkJGwAVAKULAA==.',
Ho='Holispirit:BAAANQABCgMIAwAAAA==.Holyfrog:BAAANQAECgUICgAAAA==.Holyhannah:BAAANQAECgQIBAAAAA==.Holyhope:BAABNQAECn9JAAINAAoKqBozKgB/AgANAAoKqBozKgB/AgAAAA==.Holylightz:BAAANQAECgYICgAAAA==.Holymana:BAABNQAECn86AAMOAAoK5h8wMAChAgAOAAoK5h8wMAChAgADAAIKvweXZQBLAAAAAA==.Holymilkers:BAAANQADCggIDQABNQAECgoKPAAjAMcLAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAABNQAECn9CAAIkAAoKJxEuGwCqAQAkAAoKJxEuGwCqAQAAAA==.',
Hu='Huffingpaint:BAAANQAECgUIAwABNQAECgcIFgAIAMMUAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAABNQAECn80AAQBAAoKLR3lHQCeAgABAAoKLR3lHQCeAgAlAAcK0RQwCAAPAgAmAAIKfQ/LVwB4AAAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAACNQAFFH8HAAIMAAQK5xs9DwDzAAAMAAQK5xs9DwDzAAA1AAQKfzwAAwwACgr5HuIcAIkCAAwACgr5HuIcAIkCACIABgo/CLK/AOoAAAAA.',
Il='Illidianna:BAABNQAECn8+AAMIAAoKVhzYFAAZAgAIAAoK4xvYFAAZAgAYAAcKSxwmNwD3AQAAAA==.',
Im='Imfiredup:BAABNQAFFH8FAAILAAUKOBHnGAAsAQALAAUKOBHnGAAsAQAAAA==.Imitlol:BAABNQAECn8YAAIOAAcKbyRPYQB2AgAOAAcKbyRPYQB2AgAAAA==.',
In='Inception:BAAANQAECgEIAQAAAA==.Ingress:BAAANQADCgYJBgAAAA==.',
Is='Ishu:BAAANQADCgIIAwAAAA==.',
It='Itchynyple:BAAANQADCgYIGAAAAA==.Ithowen:BAAANQABCgYIBgAAAA==.',
Ja='Jacques:BAAANQAECgYIDQAAAA==.Jaetherion:BAABNQAECn81AAMOAAoK9xsbUQCiAgAOAAkKuh4bUQCiAgADAAUKBQuaNQDcAAAAAA==.Jakes:BAAANQADCgYJDAAAAA==.Jayhawk:BAAANQAECgEIAwAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAFFAgIEgAMAJgbAA==.Jinx:BAAANQAECgMIAgAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAABNQAECn88AAIOAAoKERaZbAD2AQAOAAoKERaZbAD2AQAAAA==.Jojohunts:BAAANQAECggIAQAAAA==.Jonesy:BAAANQADCggICgABNQAECgoKXwAPAKAcAA==.',
Ju='Junyubych:BAAANQADCgcIMAABNQAECggIIgAOANUGAA==.',
['Jà']='Jàccuse:BAAANQADCgUIDAABNQAECgkJIAAFANUKAA==.Jàrnsaxa:BAAANQADCggILQAAAA==.',
Ka='Kaeladra:BAAANQABCgQIBgABNQAECgEIAwAUAAAAAA==.Kagé:BAAANQADCgEIAQAAAA==.Kaisra:BAAANQAECgUICAAAAA==.Kalida:BAAANQADCgYICwAAAA==.Kasumeli:BAAANQAECgYIDAAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayd:BAAANQAECgUIBQAAAA==.Kayhan:BAAANQADCgQICgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kayos:BAAANQAECgMIBAAAAA==.Kazoo:BAAANQADCgMIAwABNQAECgMIAgAUAAAAAA==.Kazurend:BAACNQAFFH8TAAMVAAgKcRqdBQDaAQAVAAcKgx2dBQDaAQACAAIKSgoaJgCiAAA1AAQKfy0AAxUACgqTIqAMACADABUACgqTIqAMACADAAIAAwruHLi0AMgAAAAA.',
Ke='Keish:BAAANQADCggICAAAAA==.Keleira:BAAANQAECgYICwAAAA==.Keyaielenst:BAAANQADCgYICwAAAA==.',
Kh='Khirina:BAABNQAECn8mAAMhAAkKwwsUNQBsAQAhAAkKwwsUNQBsAQAgAAcKiwmXIQAEAQAAAA==.Khristina:BAABNQAECn8bAAINAAgK/BpxWwAGAgANAAgK/BpxWwAGAgAAAA==.Khrogh:BAAANQAECgEIAwAAAA==.',
Ki='Kidiann:BAAANQAECgcIDQAAAA==.Kippo:BAAANQAECgcICAAAAA==.Kirar:BAAANQAECgMIAgAAAA==.Kisarrah:BAAANQABCgMIAwAAAA==.',
Kn='Knarn:BAABNQAECn87AAIPAAoKsCGxGQDdAgAPAAoKsCGxGQDdAgAAAA==.Knazugardarg:BAAANQAECgcIBwAAAA==.Knorre:BAAANQADCgMIAwAAAA==.',
Ko='Kohde:BAABNQAECn8VAAMaAAgKlhQ3MwC0AQAaAAgKwBI3MwC0AQAPAAYKWRI+1QBWAQABNQAFFAkJLgAaAH8iAA==.Koralie:BAACNQAFFH8XAAIPAAcKlRySBAAQAgAPAAcKlRySBAAQAgA1AAQKfzcAAg8ACgpqJb4QAGADAA8ACgpqJb4QAGADAAAA.Korrum:BAAANQABCgIIBAAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgABNQAECgoKRAASACokAA==.',
Ku='Kuneia:BAAANQAECgMIAwAAAA==.',
Ky='Kyliekat:BAABNQAECn8WAAInAAkKkAoybwANAQAnAAkKkAoybwANAQAAAA==.',
['Kå']='Kåiri:BAAANQAECgYIBwAAAA==.',
La='Lanceelot:BAAANQAECgUIDQAAAA==.Lanel:BAAANQAECgUIDgAAAA==.Lathelous:BAABNQAECn80AAIDAAoKgyArCwCBAgADAAoKgyArCwCBAgAAAA==.Laulten:BAAANQABCgQIBAAAAA==.',
Le='Leintheir:BAABNQAECn8VAAMOAAgKahXFzwA4AQAOAAgKahXFzwA4AQANAAEK/wWVAQErAAAAAA==.Lexloother:BAAANQABCggIEQAAAA==.',
Li='Lideina:BAAANQADCgUIBwAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Liebesleid:BAAANQADCgYICwABNQAECgcIFgAIAMMUAA==.Lightt:BAABNQAECn9mAAICAAoKSB8MEQBSAwACAAoKSB8MEQBSAwAAAA==.Liightt:BAABNQAECn9XAAICAAoKHB1GFgAkAwACAAoKHB1GFgAkAwAAAA==.Lilcozz:BAAANQAECgEIAQAAAA==.Lilpyroblast:BAACNQAFFH8KAAILAAQKQhFKKQDTAAALAAQKQhFKKQDTAAA1AAQKfzIAAgsACgpxGmJvAJ8CAAsACgpxGmJvAJ8CAAAA.Liriope:BAAANQADCgcIEwAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUJBwAAAA==.Llars:BAABNQAECn87AAIiAAoKMhlSJwCPAgAiAAoKMhlSJwCPAgAAAA==.',
Lo='Loryanna:BAAANQADCgYIHgAAAA==.Louie:BAABNQAECn8eAAIKAAoKYBU6CQDdAQAKAAoKYBU6CQDdAQAAAA==.Lovehandless:BAAANQADCgMIBQAAAA==.',
Lu='Lumenne:BAAANQADCgUIBwAAAA==.Luxore:BAABNQAECn8kAAIDAAoKVw+sHgDzAQADAAoKVw+sHgDzAQABNQAFFAQIBwAMAOcbAA==.',
Ly='Lyandrea:BAAANQADCggIIwAAAA==.Lyfebane:BAAANQADCgUJBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAABNQAECn8YAAMRAAkKrg5VFABkAQARAAkKrg5VFABkAQALAAUKuwXQegHMAAAAAA==.',
Ma='Maguchi:BAAANQAECgIIAQAAAA==.Main:BAABNQAECn8/AAIOAAoKmBDnqwDIAQAOAAoKmBDnqwDIAQAAAA==.Majrmiståke:BAACNQAFFH8ZAAMRAAYK0g0fBgCyAAALAAYK8QoIJwBPAQARAAMKgAcfBgCyAAA1AAQKf0MAAxEACgqbIfMBABEDABEACgqbIfMBABEDAAsACgp4HM5iAPEBAAE1AAQKCgoyAA0AthQA.Malakir:BAAANQADCgYIEwAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAABNQAECn8kAAIRAAYKCglGJQDFAAARAAYKCglGJQDFAAAAAA==.Maliceone:BAAANQADCggIJAAAAA==.Mallucavian:BAABNQAECn8XAAMCAAcKnRy8ZACyAQACAAcKnRy8ZACyAQAXAAEKKATWHgAhAAAAAA==.Mamadp:BAABNQAECn8eAAISAAcK2AZcdQDMAAASAAcK2AZcdQDMAAAAAA==.Manaholy:BAAANQADCggIDQAAAA==.Manek:BAABNQAECn9fAAIPAAoKoBwLKACfAgAPAAoKoBwLKACfAgAAAA==.Marraxa:BAABNQAECn8hAAQeAAgK0QjUJgD9AAAeAAgK0QjUJgD9AAAoAAQKYgPLFACmAAAdAAMKBQJ2SAB2AAAAAA==.Max:BAABNQAECn8aAAMBAAkK0hVpbAAZAgABAAgKmBNpbAAZAgAmAAMKlROVQQC9AAAAAA==.',
Me='Melevil:BAABNQAECn8XAAIfAAgK6QVVGAAaAQAfAAgK6QVVGAAaAQAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlin:BAAANQAECgQICwAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metafritz:BAAANQAECggIDwABNQAECgoKGQAMAP8LAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgYIDAAAAA==.Milho:BAAANQADCgYIBgABNQAFFAIICAAYAEYiAA==.Milkmeholy:BAAANQADCgcICQAAAA==.Minikey:BAAANQAECgYICwAAAA==.Mishosuki:BAABNQAECn8UAAMpAAgK9RJOegAyAQApAAUKlhROegAyAQASAAUKdQ0hYgARAQABNQADCgQIBAAUAAAAAA==.Misscleo:BAABNQAECn87AAILAAkKuQ8DfwCtAQALAAkKuQ8DfwCtAQAAAA==.Mistalar:BAAANQAECgYIBgAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Moltres:BAEBNQAFFH8FAAIGAAUKTiXOAACwAQAGAAUKTiXOAACwAQABNQAFFAgIAQAUAAAAAA==.Mongoro:BAAANQADCgEIAQAAAA==.Moonkist:BAABNQAECn8WAAMEAAcKZxGpPAA8AQAEAAcKZxGpPAA8AQAnAAEK9AKvugAmAAAAAA==.Moose:BAABNQAECn8bAAMpAAkKdB1LGQD1AgApAAkKdB1LGQD1AgAcAAEKAABcwgBDAAAAAA==.Mordrandian:BAAANQAECgMIBAAAAA==.Morroe:BAAANQADCgYIFwAAAA==.',
Mu='Muffindk:BAABNQAECn8ZAAISAAkK7AmGQgCQAQASAAkK7AmGQgCQAQAAAA==.Muffintop:BAAANQADCggIEQAAAA==.',
['Mó']='Mórningstar:BAAANQADCgIIBAAAAA==.',
Na='Nadless:BAABNQAECn8UAAILAAkKPAPH4ADrAAALAAkKPAPH4ADrAAAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgIIAwAAAA==.Narokatha:BAAANQAECggICgAAAA==.',
Ne='Necropanzer:BAABNQAECn8gAAISAAoKAiLPDwDUAgASAAoKAiLPDwDUAgAAAA==.Nelrehim:BAAANQAECgYIDwAAAA==.Nelumbo:BAABNQAFFH8GAAIEAAYKiQ7iBgCKAQAEAAYKiQ7iBgCKAQABNQAFFAgIBAAUAAAAAA==.',
Ni='Niall:BAAANQAECgEIAQABNQAECgoKRgAZAKgfAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQAECgEIAQABNQAECggIHwASANkcAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECn8pAAMDAAoKlR+oEACUAgADAAoKlR+oEACUAgAOAAUK/xU36QBJAQAAAA==.Nokua:BAABNQAECn8iAAIOAAgKdQgr5AAWAQAOAAgKdQgr5AAWAQABNQAECggIIgAOANUGAA==.Noodles:BAABNQAECn87AAInAAoKVhaNGwArAgAnAAoKVhaNGwArAgAAAA==.',
Nu='Nulannatoo:BAAANQAECggICAAAAA==.',
Ny='Nyank:BAAANQAECgMIAgABNQAECgoKHgASAH4OAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyogen:BAAANQAECggJBgAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAABNQAECn87AAILAAoKKRTKUgAZAgALAAoKKRTKUgAZAgAAAA==.',
Od='Odysseus:BAABNQAECn8gAAIaAAkKvQ+3LADlAQAaAAkKvQ+3LADlAQAAAA==.',
Ol='Olgann:BAAANQAECgYICAAAAA==.Olguita:BAABNQAECn8YAAIMAAgKfxpjiQCMAQAMAAgKfxpjiQCMAQAAAA==.',
Om='Omez:BAAANQAECgYICgAAAA==.Omgowned:BAAANQAECgIIAgABNQAECggIIAABAP0UAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCggIGQAAAA==.',
Op='Opheliastar:BAABNQAECn9GAAIVAAoKrBpTDwBkAgAVAAoKrBpTDwBkAgAAAA==.',
Or='Ordovis:BAAANQAECgUIDAAAAA==.Orlucicia:BAAANQAECgIIAgAAAA==.Orobas:BAAANQAECggIAgAAAA==.',
Ow='Owltoidz:BAAANQABCgYIBwAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAABNQAECn8aAAIBAAYKewebuwDbAAABAAYKewebuwDbAAAAAA==.Paetyn:BAAANQADCgMICAAAAA==.Pakoo:BAAANQAECgIIAQAAAA==.Paladerp:BAABNQAECn8hAAMNAAoKThioQQAOAgANAAoKThioQQAOAgAOAAIKDwjwmAE0AAAAAA==.Palanym:BAABNQAECn80AAINAAgKixebWAAPAgANAAgKixebWAAPAgAAAA==.Palidyne:BAABNQAECn8ZAAINAAkKIhRWPQAhAgANAAkKIhRWPQAhAgAAAA==.Pallyown:BAABNQAECn8dAAMNAAkKrx8gLgCuAgANAAkKrx8gLgCuAgAOAAIKrwi5XQFsAAAAAA==.Papamidnite:BAAANQADCgMIAwAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQADCgYICAAAAA==.',
Pe='Peluij:BAAANQAECgUICAAAAA==.',
Ph='Phelement:BAABNQAECn8zAAIjAAoKpyLmAwBbAwAjAAoKpyLmAwBbAwAAAA==.Pheta:BAAANQADCggICAAAAA==.Phett:BAABNQAECn82AAMfAAoKXiCKBADwAgAfAAgKMiOKBADwAgATAAcKpBtIZADTAQAAAA==.Phonk:BAAANQAECgMIAQABNQAECgoKMwAjAKciAA==.Phædrea:BAAANQADCggICAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgkJNgACABMiAA==.Piffi:BAAANQAECgEIAwABNQAECgIIAQAUAAAAAA==.Pikatso:BAAANQADCgYIDwAAAA==.Pimmscup:BAAANQADCgcIIQAAAA==.',
Po='Porgoon:BAAANQAECgQIBAAAAA==.',
Pr='Praedthy:BAAANQAFFAIIAgAAAA==.Prismatic:BAAANQAECggIDgAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raatus:BAAANQAECgIIAgABNQAECgoKHwAcACghAA==.Raenya:BAAANQAECgUIBQAAAA==.Raikouu:BAABNQAECn8ZAAIBAAcKXwiMzQAvAQABAAcKXwiMzQAvAQAAAA==.Rainydaze:BAAANQAECgQIBgAAAA==.Ramani:BAAANQADCgEIAQAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgIIAgABNQAECgoKRgAZAKgfAA==.Ramoreo:BAABNQAECn8aAAIJAAgKnAgXKADCAAAJAAgKnAgXKADCAAABNQAECgoKcgAYAOUKAA==.Rashun:BAABNQAECn81AAMhAAoKZRiFFAAgAgAhAAoKZRiFFAAgAgAWAAcKiQu5EAAbAQAAAA==.Raviolee:BAAANQAECgIIAQABNQAECggIIAABAP0UAA==.Rayvin:BAAANQADCggIEQAAAA==.',
Re='Reanatilax:BAAANQADCgEIAQABNQAECgkJHQACAIIYAA==.Regnier:BAAANQADCggIEAAAAA==.Relaeh:BAAANQADCgcJDQAAAA==.Resusitate:BAAANQADCgYJBgAAAA==.Rev:BAABNQAECn8ZAAIYAAoK6Q+AJwDRAQAYAAoK6Q+AJwDRAQAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQAECgMIAwABNQAECgoKFQABAIUMAA==.',
Ri='Rikashae:BAAANQADCgYJBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Roleon:BAAANQADCgcIEgAAAA==.Rollforpi:BAAANQAECgIIBAABNQAFFAgIEQAEANUUAA==.Ropebunnyana:BAAANQAECgIJAwABNQAFFAQIBwACAM0aAA==.',
Ru='Ruche:BAAANQAECggICQAAAA==.Rue:BAACNQAFFH8GAAIKAAQK5SFCAgDSAAAKAAQK5SFCAgDSAAA1AAQKfzUAAgoACgo/Jj8AAIUDAAoACgo/Jj8AAIUDAAE1AAUUBAgGAAoA5SEA.Ruki:BAABNQAECn8WAAMIAAcKwxRgKwA9AQAIAAcKmxRgKwA9AQAYAAMKCxL9eQCRAAAAAA==.Rumshwizzle:BAAANQADCgcICQAAAA==.',
Ry='Ryzzle:BAAANQADCggICAAAAA==.',
Sa='Saltydk:BAABNQAECn8gAAIpAAkKhyClJACuAgApAAkKhyClJACuAgAAAA==.Samiracy:BAABNQAECn8kAAImAAgKohjYBQCRAQAmAAgKohjYBQCRAQAAAA==.Sannrin:BAAANQADCgMIAwABNQAECgkJMgAPAJodAA==.Sataro:BAAANQABCggIEQAAAA==.',
Sc='Scappe:BAABNQAECn8fAAIcAAoKKCHlHADJAgAcAAoKKCHlHADJAgAAAA==.Schniel:BAABNQAECn8aAAICAAoKTw6fUgDwAQACAAoKTw6fUgDwAQAAAA==.',
Se='Sebek:BAAANQAECgYIDAAAAA==.Seefoof:BAAANQADCgIIAgAAAA==.Seitaer:BAAANQADCgYIEAAAAA==.Senbatorii:BAABNQAECn8bAAQEAAgK6hmNQAAiAQAEAAYKlxaNQAAiAQAnAAUKXg6EdQD1AAAJAAIKTArCNgBlAAAAAA==.Sentrosi:BAAANQAECgEIAQAAAA==.Sethrow:BAABNQAECn8gAAQBAAgK/RTxoACUAQABAAcKbBTxoACUAQAlAAIKWgmDIgBlAAAmAAEK1RdPMQBFAAAAAA==.Severa:BAABNQAECn8yAAIOAAoKVRn0VQAsAgAOAAoKVRn0VQAsAgAAAA==.',
Sh='Shadoh:BAAANQAECgIIAgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowsale:BAAANQADCgYIDAAAAA==.Shamwowza:BAABNQAECn9SAAIiAAoKUBjCJgCTAgAiAAoKUBjCJgCTAgAAAA==.Shantifa:BAAANQADCggIDgAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAAUAAAAAA==.Shoshanaa:BAAANQADCgYIEQAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAAUAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECn9WAAIpAAoKVw9ZLQB+AQApAAoKVw9ZLQB+AQAAAA==.',
Sn='Sneakysneak:BAABNQAECn8ZAAIoAAgKvRQUBwBOAgAoAAgKvRQUBwBOAgAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somavan:BAAANQADCgMIAwABNQAECgoKRgAZAKgfAA==.Somepriest:BAABNQAECn84AAIVAAkKrCPRBQAWAwAVAAkKrCPRBQAWAwAAAA==.Sotteria:BAAANQABCgQIBAAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Spicyness:BAAANQADCgIIAgAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQAECgMIBAAAAA==.Spëcter:BAABNQAECn8XAAMeAAgKKQ4jJgABAQAeAAcKzgwjJgABAQAdAAYKywr7kAD0AAABNQAECgoKOwALACkUAA==.',
Sq='Squishypoo:BAAANQAECgYIDAAAAA==.',
St='Starcrush:BAAANQAECgYIBwAAAA==.Staticpower:BAAANQAECggIBAAAAA==.Stiffkitten:BAAANQADCgEIAQAAAA==.Stoked:BAAANQAECgUIBQAAAA==.Studentloans:BAAANQABCgIIAgAAAA==.Sturba:BAAANQABCgIIAgAAAA==.',
Su='Suave:BAAANQAECgUICAAAAA==.Sugrace:BAAANQADCgQIBAAAAA==.Summonher:BAAANQAECgMIAwABNQAFFAYIHQAPAKsiAA==.Sunaerosinda:BAAANQADCgYIDAAAAA==.Sunow:BAAANQADCgYIFwAAAA==.Superdemonzz:BAABNQAECn8sAAMIAAoKfBwsCwCgAgAIAAoKfBwsCwCgAgAKAAkK4wjmEQArAQABNQAECgoKMgANALYUAA==.Superpallyz:BAABNQAECn8yAAQNAAoKthQZSwA8AgANAAoKthQZSwA8AgAOAAEKAADMoQE2AAADAAIKoA/iZQAxAAAAAA==.Superspidey:BAAANQAECggIAwAAAA==.',
Sw='Swipeleft:BAACNQAFFH8PAAInAAUKwg6+EwDVAAAnAAUKwg6+EwDVAAA1AAQKf0wAAicACgqSGPUeAAkCACcACgqSGPUeAAkCAAAA.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.',
Ta='Tabarnak:BAABNQAECn83AAIjAAoKtiDsAwBaAwAjAAoKtiDsAwBaAwABNQAFFAIIBwAhANMeAA==.Taiynn:BAAANQADCggIFwAAAA==.Tallon:BAACNQAFFH8RAAIkAAUK9xo0AwDrAAAkAAUK9xo0AwDrAAA1AAQKfzQAAyQACgpyJKYCAE4DACQACgpyJKYCAE4DAAkAAQokIok6AGQAAAAA.Tarogen:BAABNQAECn8XAAITAAgKuxFofQCPAQATAAgKuxFofQCPAQAAAA==.Taszherazade:BAAANQADCgEJAQAAAA==.Taszmyhn:BAAANQADCgYICQAAAA==.',
Te='Tedious:BAAANQAECgcIBwAAAA==.Teknique:BAAANQAECgIIAgAAAA==.Tempestclaw:BAAANQADCgUIBQAAAA==.Tendroni:BAABNQAECn8pAAIYAAoK+hKNKADJAQAYAAoK+hKNKADJAQAAAA==.Tenoch:BAAANQADCgEIAQAAAA==.Tervor:BAAANQAECgUICQAAAA==.Tessadin:BAAANQADCgYIEAAAAA==.',
Th='Thaddaues:BAAANQAECggIDwABNQAFFAUICQADAJIFAA==.Thanamoros:BAABNQAECn80AAIKAAoK4RE4CwAeAgAKAAoK4RE4CwAeAgABNQAFFAQIBwAMAOcbAA==.Thelephobia:BAAANQABCgcICAABNQADCgUIBQAUAAAAAA==.Theredwake:BAAANQAECgYICgAAAA==.Theroach:BAAANQAECgIIAwAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.Throfin:BAAANQAECgYICgAAAA==.Thwaxi:BAAANQADCgQICAAAAA==.',
Ti='Timeismoney:BAAANQADCggISAAAAA==.Tinydeath:BAABNQAECn8bAAISAAYKuAXigQCpAAASAAYKuAXigQCpAAAAAA==.Tiognaska:BAAANQAECgQICAAAAA==.Tirdain:BAAANQADCgYIEAAAAA==.',
To='Toeren:BAACNQAFFH8dAAIPAAYKqyJnBwB/AQAPAAYKqyJnBwB/AQA1AAQKfzwAAg8ACgpAJOQVAEQDAA8ACgpAJOQVAEQDAAAA.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgMIAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgoKJQATACATAA==.Tormented:BAABNQAECn8fAAIIAAoKeBt0DQB8AgAIAAoKeBt0DQB8AgABNQAECgoKIAASAAIiAA==.Torosentado:BAAANQAECgQICAAAAA==.',
Tr='Tregan:BAAANQAECgUICQAAAA==.Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQAECgQIBQAAAA==.Trollie:BAAANQAECggICAAAAA==.Trumu:BAAANQAECgEIAQAAAA==.Trïsh:BAAANQAECgIIAgABNQAECgoKOgADAFwQAA==.',
Ty='Tyinorin:BAAANQAECgMIBAAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAABNQAECn8uAAIIAAkKng6CJAB4AQAIAAkKng6CJAB4AQAAAA==.',
Ud='Udderjustice:BAABNQAECn87AAIDAAkKwg11JgA8AQADAAkKwg11JgA8AQAAAA==.',
Ug='Uglyelf:BAABNQAECn8yAAIPAAkKMgqekACVAQAPAAkKMgqekACVAQAAAA==.',
Ul='Ulthrak:BAAANQADCgIIAgAAAA==.Ultimakitty:BAAANQAECgQIAwAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQAECgcIFgAIAMMUAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vanhellsings:BAAANQAECgEIAQAAAA==.Vantrix:BAACNQAFFH8FAAInAAIKYAnjIACMAAAnAAIKYAnjIACMAAA1AAQKf0QAAycACgrnGMwdANsCACcACgrnGMwdANsCAAQABwquDlY4AFsBAAE1AAUUBAgHAAwA5xsA.Varabo:BAAANQAECggIBwAAAA==.Varaxx:BAAANQADCgUIBQAAAA==.Varolina:BAAANQADCggIJQAAAA==.',
Ve='Velthala:BAABNQAECn8sAAITAAoKNRlKQABCAgATAAoKNRlKQABCAgAAAA==.Velyra:BAAANQAECgUICgABNQAECgYICwAUAAAAAA==.',
Vi='Vitner:BAAANQADCgMIBAABNQAECgkJGAABAK0XAA==.Vivieneaux:BAAANQABCgUICAAAAA==.Vixsen:BAAANQABCgcIDQAAAA==.',
Vl='Vladdawngard:BAAANQAECggICAAAAA==.',
Vo='Voidcorpse:BAAANQADCgEIAQAAAA==.Voidmama:BAAANQADCgYIBgAAAA==.Voidryn:BAAANQABCgcIEQAAAA==.Voidshifter:BAAANQADCgUIBQAAAA==.Vosaleana:BAABNQAECn8cAAIVAAcK5AWROgDLAAAVAAcK5AWROgDLAAAAAA==.',
Vr='Vraak:BAACNQAFFH8RAAIEAAgK1RRRBADpAQAEAAgK1RRRBADpAQA1AAQKfzMAAwQACgoiJR8GAGEDAAQACgoiJR8GAGEDACcAAwpVHmeHALUAAAAA.',
Vu='Vulcus:BAAANQAECgQIBwABNQAFFAgIEQAEANUUAA==.',
Vy='Vyndarien:BAAANQABCgcICgAAAA==.',
Wa='Wa:BAABNQAECn8YAAMDAAcK4hPkMgBLAQADAAcK4hPkMgBLAQAOAAEKAABouAEsAAAAAA==.Walimagus:BAAANQAECgMIAgAAAA==.Wattles:BAAANQAECgcIDgAAAA==.Wattlez:BAAANQAECgQIBgAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wh='Wheeljack:BAABNQAECn8sAAQEAAkKjhjYFwBaAgAEAAkKjhjYFwBaAgAkAAQKyQJ0XwBUAAAnAAEKAAAnuwAlAAABNQAFFAIIBgAiALcPAA==.',
Wi='Widowcancer:BAAANQADCgIJAgAAAA==.Wigblam:BAAANQAECgEIAQAAAA==.Will:BAACNQAFFH8TAAIOAAYKrSTsBQCsAQAOAAYKrSTsBQCsAQA1AAQKf0IAAg4ACgqrJg4DAH4DAA4ACgqrJg4DAH4DAAAA.',
Wo='Womdalie:BAAANQADCggIGwAAAA==.',
Wy='Wyckedpally:BAABNQAECn8iAAIOAAgK1QbY6AAPAQAOAAgK1QbY6AAPAQAAAA==.',
Xa='Xanthös:BAAANQAFFAIIAgABNQAFFAgIEQAEANUUAA==.',
Xe='Xemnastrasza:BAABNQAECn8uAAMFAAoK/BVsCAAQAgAFAAkKNxRsCAAQAgAGAAgK4BU0FAALAgABNQAFFAQIBwAMAOcbAA==.Xenonne:BAAANQAECgMIBAABNQAFFAQIBwANADYNAA==.',
Xo='Xolither:BAABNQAECn8dAAICAAkKghhlXwADAgACAAkKghhlXwADAgAAAA==.',
Ye='Yenneferr:BAAANQAECggICQAAAA==.',
Yo='Yorgo:BAAANQADCggICAAAAA==.Yourwifesbf:BAABNQAECn9GAAIbAAoKYBnPCwAGAgAbAAoKYBnPCwAGAgAAAA==.Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgQICgAAAA==.',
Za='Zachdemon:BAABNQAECn82AAIKAAkKBReZDgDPAQAKAAkKBReZDgDPAQAAAA==.Zarulu:BAAANQAECggIDAABNQAFFAQIBwAMAOcbAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zeeblax:BAAANQADCggICAAAAA==.Zenyátta:BAAANQAECgUIEAAAAA==.Zephymoo:BAABNQAECn9bAAMJAAoKqR3aBwB1AgAJAAkK0x7aBwB1AgAnAAQKhhZObwANAQAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zershadowi:BAAANQAECgEIAQAAAA==.Zertfelgard:BAAANQABCgcICgAAAA==.Zeyana:BAABNQAECn8eAAMKAAoKFBPgCgCuAQAKAAoKFBPgCgCuAQAYAAYKtQQeaADYAAABNQAECgoKMgAPAP4cAA==.',
Zh='Zhengshi:BAABNQAECn8lAAIWAAgK2wkoEwDyAAAWAAgK2wkoEwDyAAAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgcIDQAAAA==.',
Zo='Zoose:BAABNQAECn8pAAQTAAgK0RmrbwCzAQATAAgK+BerbwCzAQAbAAQK6RnrKQDrAAAfAAEKhg6SMwA0AAAAAA==.Zosahe:BAABNQAECn8sAAMhAAoKPRHgGgDUAQAhAAoKPRHgGgDUAQAgAAgKqgcxKwAVAQAAAA==.Zoser:BAABNQAECn8qAAIhAAkKoSPOEQDQAgAhAAkKoSPOEQDQAgAAAA==.',
Zs='Zsófia:BAAANQADCgcIBwAAAA==.',
Zu='Zuckuss:BAAANQAECgMIBAAAAA==.',
Zy='Zymri:BAAANQADCgUICQABNQAECgUIEgAUAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgYIDQAAAA==.',
['Ôr']='Ôrdra:BAAANQAECggICAAAAA==.',
['Öl']='Ölivê:BAABNQAECn8ZAAIcAAkKBAlvcAA0AQAcAAkKBAlvcAA0AQAAAA==.',
['ßu']='ßugs:BAABNQAECn88AAIPAAkKmhrZSwA4AgAPAAkKmhrZSwA4AgAAAA==.',
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
