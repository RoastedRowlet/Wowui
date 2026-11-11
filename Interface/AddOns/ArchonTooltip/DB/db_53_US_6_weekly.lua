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

local lookup = {'Warlock-Demonology','Priest-Holy','Paladin-Protection','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer','Druid-Feral','DemonHunter-Vengeance','Mage-Arcane','Shaman-Elemental','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Mage-Fire','Mage-Frost','DeathKnight-Frost','Warrior-Arms','Priest-Shadow','Monk-Brewmaster','Priest-Discipline','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Shaman-Enhancement','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Druid-Balance','Rogue-Outlaw','DeathKnight-Unholy',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acbabcaa:BAAANQAECgEIAQAAAA==.Aceon:BAAANQAECgIIBAAAAA==.Aceonarcher:BAAANQAECgQICAAAAA==.',
Ad='Adfectia:BAABNQAECn8xAAIBAAoKXQomZQCTAQABAAoKXQomZQCTAQAAAA==.',
Ae='Aelianna:BAAANQAECgcIDQAAAA==.Aeryana:BAACNQAFFH8FAAICAAIKWhYNJACrAAACAAIKWhYNJACrAAA1AAQKfzwAAgIACgptI+QNAFUDAAIACgptI+QNAFUDAAAA.Aeth:BAAANQAECgYIDAABNQAECgoKJAADAPwiAA==.Aethér:BAAANQAECgYIDwABNQAFFAgIEQAEANMUAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgoKKQADAJUfAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgQICQAAAA==.',
Al='Alberoo:BAAANQABCgQIBAAAAA==.Albèdo:BAAANQABCgYIBgAAAA==.Alexstrászá:BAABNQAECn8xAAMFAAoKGg60BwCrAQAFAAoKGg60BwCrAQAGAAMKzwJ3NwBTAAAAAA==.Aloria:BAAANQADCgEIAQAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgUIDQAAAA==.',
Am='Amaarii:BAAANQABCgQJCAAAAA==.Ambeia:BAAANQAECgMIBQAAAA==.Amewow:BAACNQAFFH8aAAMGAAgKSh96AADnAQAGAAcKOCN6AADnAQAFAAEKpwveDABNAAA1AAQKf1oAAwYACgr/JWwAAHUDAAYACgr/JWwAAHUDAAcABwqAFjkRANcBAAAA.Amoril:BAABNQAECn8pAAIIAAoKRQYCJgBUAQAIAAoKRQYCJgBUAQAAAA==.',
An='Anarchy:BAABNQAECn84AAIJAAoKBRYPDADzAQAJAAoKBRYPDADzAQAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Andrewchau:BAAANQAECgIIAgAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Annòy:BAABNQAECn9SAAIKAAoKUh+oAwAkAwAKAAoKUh+oAwAkAwAAAA==.Anorakswrath:BAABNQAECn8dAAILAAkKXQQQEAFyAQALAAkKXQQQEAFyAQAAAA==.',
Ap='Apokai:BAAANQAECgcIBwABNQAFFAQIBwAMAOcbAA==.Apophys:BAAANQADCgcIIwAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Ariella:BAAANQADCgQIBAAAAA==.Artfulrodent:BAAANQADCgQIBAAAAA==.Aruneza:BAABNQAECn8dAAMGAAgKdhFQHQB5AQAGAAcKjg1QHQB5AQAHAAYKNgvYLwAfAQAAAA==.',
As='Asherous:BAAANQADCgQICQABNQAECggIIgANAMchAA==.Ashèr:BAABNQAECn8iAAMNAAgKxyGKKgBtAgANAAgKxyGKKgBtAgAOAAMKbgZlWgFfAAAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgUIEQABNQAECgoKIwAPADEUAA==.Auralion:BAAANQAECgQIBAAAAA==.Autoignition:BAABNQAECn8XAAQQAAkKthwwBAB1AQALAAcKqB9XwgAAAgAQAAUKDxswBAB1AQARAAMKlxnnIwDOAAABNQAECgoKIAASAAIiAA==.',
Ba='Badcompanytt:BAAANQADCgUIAwAAAA==.Bahnkano:BAABNQAECn8WAAIMAAgK6QSTwgANAQAMAAgK6QSTwgANAQAAAA==.Bakeddh:BAAANQADCgYIDAAAAA==.Balwal:BAAANQAECgIIAgAAAA==.Banditz:BAAANQADCgcIDwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAABNQAECn8YAAITAAYK9QMf+QDqAAATAAYK9QMf+QDqAAAAAA==.Beenah:BAAANQAECgUIEgAAAA==.Beyshunt:BAAANQADCgYICgAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAABNQAECn8WAAILAAkKIQtXogBNAQALAAkKIQtXogBNAQAAAA==.',
Bo='Boltcutter:BAAANQADCgYICgAAAA==.Bombmagic:BAAANQADCgMIAwAAAA==.Bonesmccoy:BAAANQABCgYIBgAAAA==.Boomie:BAABNQAFFH8FAAIHAAUKqCTcBAAiAgAHAAUKqCTcBAAiAgABNQAFFAgIBgAEAIkOAA==.Boopty:BAABNQAECn8UAAIUAAUKlgdsRACGAAAUAAUKlgdsRACGAAAAAA==.Booptydo:BAAANQADCggIHQAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAABNQAECn8aAAIPAAgKHAoksgAyAQAPAAgKHAoksgAyAQAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQAECgYICQABNQAFFAgIEQAEANMUAA==.Brazyn:BAAANQADCggIIwAAAA==.Brevarda:BAAANQAECgYIDQAAAA==.Brewcelee:BAABNQAECn82AAIVAAkKrg3qCwBgAQAVAAkKrg3qCwBgAQAAAA==.',
Bu='Bubblzmgee:BAABNQAECn9VAAMWAAoK/B3oAABXAwAWAAoK/B3oAABXAwAUAAEKxwliXAA4AAAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCgcIDwAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQAECgMIAwAAAA==.',
Ca='Cakeman:BAAANQAECgQIBAAAAA==.Capone:BAABNQAECn8gAAIXAAkKLhINIgDlAQAXAAkKLhINIgDlAQAAAA==.Captiva:BAAANQAECgEIAQAAAA==.Caracalous:BAAANQAECgYIDAAAAA==.Carindria:BAAANQADCggILAAAAA==.Carninn:BAAANQADCgcIBwAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cat:BAAANQAECgUICgAAAA==.Cattiebrie:BAAANQAECgQIDwAAAA==.Caylavana:BAABNQAECn9GAAMYAAoKqB/cAQDHAgAYAAkKAR3cAQDHAgAPAAgKqB+WSwCLAgAAAA==.',
Ce='Celaylria:BAABNQAECn9DAAIZAAoK1hPAEgADAgAZAAoK1hPAEgADAgAAAA==.Ceyine:BAAANQAECgEIAQAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgUICQAAAA==.Clugorn:BAABNQAECn8mAAIaAAoK2Qw0HQABAQAaAAoK2Qw0HQABAQAAAA==.Clydè:BAABNQAECn8eAAIKAAoKfhT/CADHAQAKAAoKfhT/CADHAQAAAA==.',
Co='Codyj:BAAANQADCggIDgAAAA==.Colossus:BAAANQADCggJCwAAAA==.Colourhunt:BAABNQAECn8YAAMZAAkKMxAwPQBoAQAPAAcKZw6MnwDHAQAZAAcKCw4wPQBoAQAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAABNQAECn8rAAIbAAkKHRv6IgCfAgAbAAkKHRv6IgCfAgAAAA==.Copestabb:BAAANQAECgMIBAABNQAECgkJKwAbAB0bAA==.Corrode:BAAANQAECgIIAwAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crimie:BAAANQADCggICAAAAA==.Crusadare:BAAANQAECgQIBAAAAA==.',
Cu='Culture:BAAANQAECgYIDAAAAA==.',
Cy='Cybeldin:BAABNQAECn8iAAMPAAgKSAnjngBaAQAPAAgKSAnjngBaAQAZAAQK8QIzbgB3AAAAAA==.Cyberdemonxd:BAAANQADCgYIDAABNQAECgoKHgASAH4OAA==.Cyndyr:BAAANQAECgMIBAAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAABNQAECn8kAAIIAAkKpA+VIACHAQAIAAkKpA+VIACHAQAAAA==.Dalarrus:BAABNQAECn8WAAMcAAgKhgw/UwCaAQAcAAgKhgw/UwCaAQAdAAYKEwjcXQA/AQABNQAECgoKRgAYAKgfAA==.Dalishya:BAAANQADCgQIBAAAAA==.Darbane:BAAANQAECgMIAwAAAA==.Darek:BAABNQAECn8XAAILAAgKRAlDNgEyAQALAAgKRAlDNgEyAQAAAA==.Darilyns:BAAANQAECgMIAwAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgcIHQAAAA==.Darylinn:BAAANQADCgQJBgAAAA==.Daymann:BAABNQAECn8eAAMCAAoKQBSbPQAvAgACAAoKxhKbPQAvAgAWAAEKKxzyIgBQAAAAAA==.',
De='Deathcore:BAAANQAECgIIAQABNQAECgoKNwALAEcTAA==.Demonrife:BAAANQABCgYIBgABNQADCgcIHQAeAAAAAA==.Dependabull:BAAANQADCgYIBgABNQAECgQICQAeAAAAAA==.Dernis:BAAANQAECgIIAgABNQAECgoKMQATAMQeAA==.Derplock:BAAANQADCgcIEAAAAA==.Deshaman:BAAANQADCgMIAwABNQAFFAYIHQAPAKsiAA==.Devilbeast:BAAANQAECgQIDQAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgYIDgABNQAECgQICQAeAAAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Diaous:BAAANQADCgcIEQAAAA==.Disasterina:BAAANQADCgcIBwABNQAECgoKRQAIAJ0hAA==.Disgruntled:BAAANQAECgcIEQAAAA==.',
Do='Docbrown:BAAANQADCgEIAQAAAA==.Dontormentaa:BAABNQAECn8lAAMTAAoKIBNtdgAzAgATAAoKohJtdgAzAgAfAAEK/Bl9LQBNAAAAAA==.Dontormentaj:BAABNQAECn8iAAQRAAgKXxfiFwA7AQALAAgK1xYpmABQAgARAAQKHB3iFwA7AQAQAAMKmRR7BwDCAAABNQAECgoKJQATACATAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAABNQAECn8eAAIFAAgKdww1EgAQAQAFAAgKdww1EgAQAQAAAA==.Dragonbrew:BAAANQADCggICAAAAA==.Dragonfang:BAAANQAECggIEQABNQAECgoKIAASAAIiAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQAeAAAAAA==.Dreamhammer:BAAANQABCgcIDwAAAA==.Dreamlesnite:BAAANQABCggIFAAAAA==.Dreidelman:BAAANQAECgQIBAAAAA==.Drkstar:BAAANQABCgEIAQAAAA==.Druvisept:BAAANQAECgQIBAAAAA==.',
Du='Dugdimadome:BAAANQAECgQIAwAAAA==.Dunthur:BAAANQAECgMIBAABNQAECgYIBQAeAAAAAA==.',
Dy='Dylora:BAABNQAECn8lAAIgAAgKgRsDCwB5AgAgAAgKgRsDCwB5AgAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECn8vAAMNAAoKSCKJCQB8AwANAAoKSCKJCQB8AwAOAAEKqAw/wwEnAAABNQAFFAkJJwACAH8YAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAABNQAECn8cAAILAAgK3xnV1ADdAQALAAgK3xnV1ADdAQAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgYIDAAAAA==.Elystaria:BAABNQAECn8aAAMDAAYKsR2NJAA1AQAOAAYKnxtE0AB7AQADAAUK3R2NJAA1AQAAAA==.',
Em='Emokins:BAEBNQAECn8pAAIMAAgK2SEyJwDmAgAMAAgK2SEyJwDmAgAAAA==.',
En='Enyos:BAAANQADCgcIEAAAAA==.',
Ep='Epicnakedman:BAABNQAECn8cAAIPAAkKRSHiGADVAgAPAAkKRSHiGADVAgABNQAECgoKSQANAKgaAA==.',
Er='Eronoljr:BAAANQADCgEIAQAAAA==.Erubus:BAACNQAFFH8FAAIVAAQKzRdGBgCbAAAVAAQKzRdGBgCbAAA1AAQKf0UABBUACgq0Ig8DAGkDABUACgq0Ig8DAGkDACEACQruGNoUAAYCACAAAwpnCo0yAGIAAAAA.Erubuss:BAABNQAECn8UAAIPAAgKXhNdgACeAQAPAAgKXhNdgACeAQAAAA==.Erubussyy:BAAANQAECgUIBQAAAA==.Eryss:BAABNQAECn8aAAIPAAYKEQrqxQAMAQAPAAYKEQrqxQAMAQAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Fa='Faithfulone:BAABNQAECn8VAAIbAAYKWghajADQAAAbAAYKWghajADQAAAAAA==.Farfidnoogan:BAAANQABCgQIBAAAAA==.Fateforged:BAAANQAECgYIBQAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAABNQAECn8fAAISAAcK2RwdMwDDAQASAAcK2RwdMwDDAQAAAA==.',
Fe='Fellariene:BAAANQADCggIDQAAAA==.',
Fi='Fistenlick:BAAANQADCgQIBAABNQADCgcIEgAeAAAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgYICwAAAA==.',
Fr='Freim:BAABNQAECn8bAAIfAAkKgyE5AgAGAwAfAAkKgyE5AgAGAwAAAA==.',
['Fà']='Fàmous:BAAANQAECgcICQAAAA==.',
Ga='Galabris:BAABNQAECn8kAAIbAAgKfx7rKQB1AgAbAAgKfx7rKQB1AgAAAA==.Garavos:BAAANQAECgIIAgAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.Gazzik:BAAANQAECgUICAAAAA==.',
Ge='Gera:BAAANQAECgEIAQAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECgkJFAAJAPMYAA==.Ghoulmania:BAAANQAECggICwAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQAECgYIEgAAAA==.Ginhei:BAAANQADCgcIBwAAAA==.Gitchusum:BAAANQAECgYIBgAAAA==.',
Gl='Glaivenez:BAAANQAECggIBgAAAA==.Gleenna:BAABNQAECn8jAAMiAAoKQxKOTwC8AQAiAAoKQxKOTwC8AQAMAAEKAAD4SAEqAAAAAA==.Glorify:BAAANQAECgUICAABNQAECgoKJgAbAOkcAA==.',
Go='Goose:BAABNQAECn82AAMCAAkKEyIaFgAhAwACAAkKEyIaFgAhAwAWAAEK3BevJABGAAAAAA==.Gormladin:BAAANQADCgYIFwAAAA==.Gormstorm:BAABNQAECn8YAAMiAAYKBxrtVgChAQAiAAYKBxrtVgChAQAMAAIKZANzIQFOAAAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grimsreaper:BAAANQADCgQIBAAAAA==.Grouchy:BAAANQADCgQIBgABNQAECggIHwASANkcAA==.',
Gw='Gwynythe:BAAANQADCgYICgAAAA==.',
Ha='Hadess:BAAANQADCgQIBAAAAA==.Hadriac:BAAANQAECgIIAgAAAA==.Hailes:BAAANQABCgIIAQAAAA==.Halfang:BAAANQADCggINAAAAA==.Halphas:BAAANQADCggICAABNQAECgMIAgAeAAAAAA==.Hanta:BAABNQAECn8qAAMPAAoKzhizNABlAgAPAAoKzhizNABlAgAZAAEK2gefbQApAAAAAA==.Hanterruso:BAAANQAECgEIAQAAAA==.Haplò:BAAANQAECgIIAgAAAA==.Hastebuff:BAABNQAECn8ZAAIMAAoK/wuvSQCYAQAMAAoK/wuvSQCYAQAAAA==.',
He='Healless:BAAANQAECgIIAgABNQAECgoKRgAYAKgfAA==.Hentaime:BAAANQABCgMIAwAAAA==.',
Hi='Hildegarde:BAAANQADCggICAABNQAECgcIFgAIAMMUAA==.Hitpoints:BAAANQADCgYIDAABNQAECggIGgAUAEYMAA==.',
Ho='Holispirit:BAAANQABCgMIAwAAAA==.Holyfrog:BAAANQAECgUICgAAAA==.Holyhannah:BAAANQAECgQIBAAAAA==.Holyhope:BAABNQAECn9JAAINAAoKqBoKJgCGAgANAAoKqBoKJgCGAgAAAA==.Holylightz:BAAANQAECgYICgAAAA==.Holymana:BAABNQAECn84AAMOAAoKyB+GLwCWAgAOAAoKyB+GLwCWAgADAAIKvweXZQBLAAAAAA==.Holymilkers:BAAANQADCggIDQABNQAECgoKNwAjACILAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAABNQAECn86AAIkAAoKSg3/IABjAQAkAAoKSg3/IABjAQAAAA==.',
Hu='Huffingpaint:BAAANQAECgUIAwABNQAECgcIFgAIAMMUAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAABNQAECn80AAQBAAoKLR0YGgCmAgABAAoKLR0YGgCmAgAlAAcK0RQwCAAPAgAmAAIKfQ/LVwB4AAAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAACNQAFFH8HAAIMAAQK5xtVDQD1AAAMAAQK5xtVDQD1AAA1AAQKfzwAAwwACgr5HvoZAI8CAAwACgr5HvoZAI8CACIABgo/CLK/AOoAAAAA.',
Il='Illidianna:BAABNQAECn86AAMIAAoK+Bv1EwASAgAIAAoKhBv1EwASAgAXAAcKSxwmNwD3AQAAAA==.',
Im='Imfiredup:BAABNQAFFH8FAAILAAUKOBGMFAA2AQALAAUKOBGMFAA2AQAAAA==.Imitlol:BAABNQAECn8YAAIOAAcKbyRPYQB2AgAOAAcKbyRPYQB2AgAAAA==.',
In='Inception:BAAANQAECgEIAQAAAA==.Ingress:BAAANQADCgYJBgAAAA==.',
Is='Ishu:BAAANQADCgIIAwAAAA==.',
It='Itchynyple:BAAANQADCgYIGAAAAA==.Ithowen:BAAANQABCgYIBgAAAA==.',
Ja='Jacques:BAAANQAECgcICwAAAA==.Jaetherion:BAABNQAECn8zAAMOAAkKuh4bUQCiAgAOAAkKuh4bUQCiAgADAAMKxQxuQQCPAAAAAA==.Jakes:BAAANQADCgYJDAAAAA==.Jayhawk:BAAANQAECgEIAwAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAECgYIBgAeAAAAAA==.Jinx:BAAANQAECgMIAgAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAABNQAECn88AAIOAAoKERZCYQD/AQAOAAoKERZCYQD/AQAAAA==.Jojohunts:BAAANQAECgEIAQAAAA==.Jonesy:BAAANQADCggICgABNQAECgoKXwAPAKAcAA==.',
Ju='Junyubych:BAAANQADCgcIKgABNQAECggIIQAOAHUIAA==.',
['Jà']='Jàccuse:BAAANQADCgUIDAABNQAECggIHgAFAHcMAA==.Jàrnsaxa:BAAANQADCggIJgAAAA==.',
Ka='Kaeladra:BAAANQABCgQIBgABNQAECgEIAwAeAAAAAA==.Kagé:BAAANQADCgEIAQAAAA==.Kaisra:BAAANQAECgUICAAAAA==.Kalida:BAAANQADCgYICwAAAA==.Kasumeli:BAAANQAECgYIDAAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayhan:BAAANQADCgQICgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kayos:BAAANQAECgMIBAAAAA==.Kazoo:BAAANQADCgMIAwABNQAECgMIAgAeAAAAAA==.Kazurend:BAACNQAFFH8TAAMUAAgKcRqdBQDaAQAUAAcKgx2dBQDaAQACAAIKSgoaJgCiAAA1AAQKfy0AAxQACgqTIqAMACADABQACgqTIqAMACADAAIAAwruHJ2rAMoAAAAA.',
Ke='Keish:BAAANQADCggICAAAAA==.Keleira:BAAANQAECgYICwAAAA==.Keyaielenst:BAAANQADCgYICwAAAA==.',
Kh='Khirina:BAABNQAECn8fAAMhAAkKwwsUNQBsAQAhAAkKwwsUNQBsAQAgAAYKnwnCIwDYAAAAAA==.Khristina:BAABNQAECn8bAAINAAgK/BpxWwAGAgANAAgK/BpxWwAGAgAAAA==.Khrogh:BAAANQAECgEIAwAAAA==.',
Ki='Kidiann:BAAANQAECgcIDQAAAA==.Kippo:BAAANQAECgcICAAAAA==.Kirar:BAAANQAECgMIAgAAAA==.Kisarrah:BAAANQABCgMIAwAAAA==.',
Kn='Knarn:BAABNQAECn83AAIPAAoKniHbFgDhAgAPAAoKniHbFgDhAgAAAA==.Knazugardarg:BAAANQAECgcIBwAAAA==.Knorre:BAAANQADCgMIAwAAAA==.',
Ko='Kohde:BAABNQAECn8VAAMZAAgKlhQ3MwC0AQAZAAgKwBI3MwC0AQAPAAYKWRI+1QBWAQABNQAFFAkJLgAZAH8iAA==.Koralie:BAACNQAFFH8XAAIPAAcKlRySBAAQAgAPAAcKlRySBAAQAgA1AAQKfzcAAg8ACgpqJb4QAGADAA8ACgpqJb4QAGADAAAA.Korrum:BAAANQABCgIIBAAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgABNQAECgoKRAASACokAA==.',
Ku='Kuneia:BAAANQAECgMIAwAAAA==.',
Ky='Kyliekat:BAABNQAECn8VAAInAAgKrQoybwANAQAnAAgKrQoybwANAQAAAA==.',
['Kå']='Kåiri:BAAANQAECgYIBgAAAA==.',
La='Lanceelot:BAAANQAECgUIDQAAAA==.Lanel:BAAANQAECgUIDgAAAA==.Lathelous:BAABNQAECn8wAAIDAAoKPSBzCgB+AgADAAoKPSBzCgB+AgAAAA==.Laulten:BAAANQABCgQIBAAAAA==.',
Le='Leintheir:BAABNQAECn8VAAMOAAgKahVovwA+AQAOAAgKahVovwA+AQANAAEK/wVb+AArAAAAAA==.Lexloother:BAAANQABCggIEQAAAA==.',
Li='Lideina:BAAANQADCgUIBwAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Lightt:BAACNQAFFH8FAAICAAMKlAjaJQCdAAACAAMKlAjaJQCdAAA1AAQKf18AAgIACgqUHmERAD8DAAIACgqUHmERAD8DAAAA.Liightt:BAABNQAECn9OAAICAAoKehzlFwAGAwACAAoKehzlFwAGAwAAAA==.Lilcozz:BAAANQAECgEIAQAAAA==.Lilpyroblast:BAACNQAFFH8KAAILAAQKQhFZJADdAAALAAQKQhFZJADdAAA1AAQKfywAAgsACgoAGmJvAJ8CAAsACgoAGmJvAJ8CAAAA.Liriope:BAAANQADCgcIEwAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUJBwAAAA==.Llars:BAABNQAECn83AAIiAAoKMhnhIgCVAgAiAAoKMhnhIgCVAgAAAA==.',
Lo='Loryanna:BAAANQADCgYIHgAAAA==.Louie:BAABNQAECn8ZAAIKAAoK0RTaCADLAQAKAAoK0RTaCADLAQAAAA==.Lovehandless:BAAANQADCgMIBQAAAA==.',
Lu='Lumenne:BAAANQADCgUIBwAAAA==.Luxore:BAABNQAECn8kAAIDAAoKVw+sHgDzAQADAAoKVw+sHgDzAQABNQAFFAQIBwAMAOcbAA==.',
Ly='Lyandrea:BAAANQADCggIIwAAAA==.Lyfebane:BAAANQADCgUJBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAABNQAECn8XAAMRAAgKWg9VFABkAQARAAgKWg9VFABkAQALAAUKuwXQegHMAAAAAA==.',
Ma='Main:BAABNQAECn8/AAIOAAoKmBDHmQCEAQAOAAoKmBDHmQCEAQAAAA==.Majrmiståke:BAACNQAFFH8ZAAMRAAYK0g1CBQCyAAALAAYK8QoIJwBPAQARAAMKgAdCBQCyAAA1AAQKfz0AAxEACgqyIPECANMCABEACgoqIPECANMCAAsACgp4HLdaAPUBAAE1AAQKCgoxAA0AthQA.Malakir:BAAANQADCgYIEwAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAABNQAECn8gAAIRAAYKCglGJQDFAAARAAYKCglGJQDFAAAAAA==.Maliceone:BAAANQADCggIJAAAAA==.Mallucavian:BAABNQAECn8XAAMCAAcKnRySWwC6AQACAAcKnRySWwC6AQAWAAEKKAT7GwAlAAAAAA==.Mamadp:BAABNQAECn8eAAISAAcK2AZcdQDMAAASAAcK2AZcdQDMAAAAAA==.Manaholy:BAAANQADCggIDQAAAA==.Manek:BAABNQAECn9fAAIPAAoKoByfIgCnAgAPAAoKoByfIgCnAgAAAA==.Marraxa:BAABNQAECn8hAAQdAAgK0QhqJQD/AAAdAAgK0QhqJQD/AAAoAAQKYgPLFACmAAAcAAMKBQJ2SAB2AAAAAA==.Maräjade:BAAANQABCgYIBgAAAA==.Max:BAABNQAECn8aAAMBAAkK0hVpbAAZAgABAAgKmBNpbAAZAgAmAAMKlROVQQC9AAAAAA==.',
Me='Melevil:BAABNQAECn8XAAIfAAgK6QVVGAAaAQAfAAgK6QVVGAAaAQAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlin:BAAANQAECgQICwAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metafritz:BAAANQAECggIDwABNQAECgoKGQAMAP8LAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgYIDAAAAA==.Milho:BAAANQADCgYIBgABNQAFFAIICAAXAEYiAA==.Milkmeholy:BAAANQADCgcICQAAAA==.Minikey:BAAANQAECgYICwAAAA==.Mishosuki:BAAANQAECgcIEAABNQADCgQIBAAeAAAAAA==.Misscleo:BAABNQAECn87AAILAAkKuQ+vdgCtAQALAAkKuQ+vdgCtAQAAAA==.Mistalar:BAAANQAECgYIBgAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Moltres:BAEBNQAFFH8FAAIGAAUKTiWqAAC3AQAGAAUKTiWqAAC3AQABNQAFFAgIAgAeAAAAAA==.Mongoro:BAAANQADCgEIAQAAAA==.Moonkist:BAABNQAECn8WAAMEAAcKZxGoOgAQAQAEAAcKZxGoOgAQAQAnAAEK9AKvugAmAAAAAA==.Moose:BAABNQAECn8bAAMpAAkKdB1LGQD1AgApAAkKdB1LGQD1AgAbAAEKAABcwgBDAAAAAA==.Mordrandian:BAAANQAECgMIBAAAAA==.Morroe:BAAANQADCgYIFwAAAA==.',
Mu='Muffindk:BAABNQAECn8XAAISAAkK7AmWPACVAQASAAkK7AmWPACVAQAAAA==.Muffintop:BAAANQADCggIEQAAAA==.',
['Mó']='Mórningstar:BAAANQADCgIIBAAAAA==.',
Na='Nadless:BAAANQAECgUICQAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgIIAwAAAA==.Narokatha:BAAANQAECggICgAAAA==.',
Ne='Necropanzer:BAABNQAECn8gAAISAAoKAiK3DQDdAgASAAoKAiK3DQDdAgAAAA==.Nelrehim:BAAANQAECgYIDwAAAA==.Nelumbo:BAABNQAFFH8GAAIEAAYKiQ4QBgCKAQAEAAYKiQ4QBgCKAQAAAA==.',
Ni='Niall:BAAANQAECgEIAQABNQAECgoKRgAYAKgfAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQAECgEIAQABNQAECggIHwASANkcAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECn8pAAMDAAoKlR+oEACUAgADAAoKlR+oEACUAgAOAAUK/xU36QBJAQAAAA==.Nokua:BAABNQAECn8hAAIOAAgKdQjv1AAaAQAOAAgKdQjv1AAaAQAAAA==.Noodles:BAABNQAECn87AAInAAoKVhaFGQAsAgAnAAoKVhaFGQAsAgAAAA==.',
Nu='Nulannatoo:BAAANQAECggICAAAAA==.',
Ny='Nyank:BAAANQAECgMIAgABNQAECgoKHgASAH4OAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyogen:BAAANQAECggJBgAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAABNQAECn83AAILAAoKRxMcUQAOAgALAAoKRxMcUQAOAgAAAA==.',
Od='Odysseus:BAABNQAECn8gAAIZAAkKvQ+3LADlAQAZAAkKvQ+3LADlAQAAAA==.',
Ol='Olgann:BAAANQAECgYICAAAAA==.Olguita:BAABNQAECn8YAAIMAAgKfxpjiQCMAQAMAAgKfxpjiQCMAQAAAA==.',
Om='Omez:BAAANQAECgYICgABNQAFFAEIAQAeAAAAAA==.Omgowned:BAAANQAECgIIAgABNQAECggIIAABAP0UAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCggIGQAAAA==.',
Op='Opheliastar:BAABNQAECn9CAAIUAAoKkRltDwBPAgAUAAoKkRltDwBPAgAAAA==.',
Or='Ordovis:BAAANQAECgUIDAAAAA==.Orlucicia:BAAANQAECgIIAgAAAA==.Orobas:BAAANQAECggIAgAAAA==.',
Ow='Owltoidz:BAAANQABCgYIBwAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAABNQAECn8aAAIBAAYKewdBsgDbAAABAAYKewdBsgDbAAAAAA==.Paetyn:BAAANQADCgMICAAAAA==.Pakoo:BAAANQAECgIIAQAAAA==.Paladerp:BAABNQAECn8hAAMNAAoKThg2PAAUAgANAAoKThg2PAAUAgAOAAIKDwjqhgE1AAAAAA==.Palanym:BAABNQAECn80AAINAAgKixebWAAPAgANAAgKixebWAAPAgAAAA==.Palidyne:BAAANQAECggIEAAAAA==.Pallyown:BAABNQAECn8dAAMNAAkKrx8gLgCuAgANAAkKrx8gLgCuAgAOAAIKrwg9TQFtAAAAAA==.Papamidnite:BAAANQADCgMIAwAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQADCgYICAAAAA==.',
Pe='Peluij:BAAANQAECgUICAAAAA==.',
Ph='Phelement:BAABNQAECn8zAAIjAAoKpyLmAwBbAwAjAAoKpyLmAwBbAwAAAA==.Pheta:BAAANQADCggICAAAAA==.Phett:BAABNQAECn82AAMfAAoKXiCKBADwAgAfAAgKMiOKBADwAgATAAcKpBuAWwDYAQAAAA==.Phonk:BAAANQAECgMIAQABNQAECgoKMwAjAKciAA==.Phædrea:BAAANQADCggICAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgkJNgACABMiAA==.Piffi:BAAANQAECgEIAwABNQAECgIIAQAeAAAAAA==.Pikatso:BAAANQADCgYICQAAAA==.Pimmscup:BAAANQADCgcIIQAAAA==.',
Po='Porgoon:BAAANQAECgQIBAAAAA==.',
Pr='Praedthy:BAAANQAFFAIIAgAAAA==.Prismatic:BAAANQAECggIDgAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raatus:BAAANQAECgIIAgABNQAECgoKHwAbACghAA==.Raenya:BAAANQAECgYIBQAAAA==.Raikouu:BAABNQAECn8ZAAIBAAcKXwiMzQAvAQABAAcKXwiMzQAvAQAAAA==.Rainydaze:BAAANQAECgQIBgAAAA==.Ramani:BAAANQADCgEIAQAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgIIAgABNQAECgoKRgAYAKgfAA==.Ramoreo:BAABNQAECn8aAAIJAAgKnAgbJADDAAAJAAgKnAgbJADDAAABNQAECgoKZgAXAH8KAA==.Rashun:BAABNQAECn81AAMhAAoKZRjxEgAgAgAhAAoKZRjxEgAgAgAVAAcKiQt8DwAbAQAAAA==.Raviolee:BAAANQAECgIIAQABNQAECggIIAABAP0UAA==.Rayvin:BAAANQADCggIEQAAAA==.',
Re='Reanatilax:BAAANQABCgMJBQABNQAECggIHAACAGcaAA==.Regnier:BAAANQADCggIEAAAAA==.Relaeh:BAAANQADCgcJDQAAAA==.Resusitate:BAAANQADCgYJBgAAAA==.Rev:BAABNQAECn8WAAIXAAoKMw4EJwC+AQAXAAoKMw4EJwC+AQAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQAECgMIAwABNQAECgoKFQABAIUMAA==.',
Ri='Rikashae:BAAANQADCgYJBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Roleon:BAAANQADCgcIEgAAAA==.Rollforpi:BAAANQAECgIIBAABNQAFFAgIEQAEANMUAA==.Ropebunnyana:BAAANQAECgIJAwABNQAFFAIIBQACAFoWAA==.',
Ru='Ruche:BAAANQAECggICAAAAA==.Rue:BAACNQAFFH8GAAIKAAQK5SH8AQDUAAAKAAQK5SH8AQDUAAA1AAQKfzIAAgoACgouJkUAAIEDAAoACgouJkUAAIEDAAE1AAUUBAgGAAoA5SEA.Ruki:BAABNQAECn8WAAMIAAcKwxTPJwBEAQAIAAcKmxTPJwBEAQAXAAMKCxL9eQCRAAAAAA==.Rumshwizzle:BAAANQADCgcICQAAAA==.',
Sa='Saltydk:BAABNQAECn8gAAIpAAkKhyClJACuAgApAAkKhyClJACuAgAAAA==.Samiracy:BAABNQAECn8kAAImAAgKohgwBQCUAQAmAAgKohgwBQCUAQAAAA==.Sannrin:BAAANQADCgMIAwAAAA==.Sataro:BAAANQABCggIEQAAAA==.',
Sc='Scappe:BAABNQAECn8fAAIbAAoKKCHlHADJAgAbAAoKKCHlHADJAgAAAA==.Schniel:BAABNQAECn8aAAICAAoKTw6+SgD4AQACAAoKTw6+SgD4AQAAAA==.',
Se='Sebek:BAAANQAECgYICAAAAA==.Seefoof:BAAANQADCgIIAgAAAA==.Seitaer:BAAANQADCgYICgAAAA==.Senbatorii:BAABNQAECn8bAAQEAAgK6hmNQAAiAQAEAAYKlxaNQAAiAQAnAAUKXg6EdQD1AAAJAAIKTArCNgBlAAAAAA==.Sentrosi:BAAANQAECgEIAQAAAA==.Sethrow:BAABNQAECn8gAAQBAAgK/RTxoACUAQABAAcKbBTxoACUAQAlAAIKWgnXHwBlAAAmAAEK1RfHLgBFAAAAAA==.Severa:BAABNQAECn8wAAIOAAoKhhiRUwAhAgAOAAoKhhiRUwAhAgAAAA==.',
Sh='Shadoh:BAAANQAECgIIAgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowsale:BAAANQADCgYIDAAAAA==.Shamwowza:BAABNQAECn9GAAIiAAoKmxYYLQBZAgAiAAoKmxYYLQBZAgAAAA==.Shantifa:BAAANQADCggIDgAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAAeAAAAAA==.Shoshanaa:BAAANQADCgYIEQAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAAeAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECn9RAAIpAAoKVw8yKwB4AQApAAoKVw8yKwB4AQAAAA==.',
Sn='Sneakysneak:BAABNQAECn8ZAAIoAAgKvRQUBwBOAgAoAAgKvRQUBwBOAgAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somavan:BAAANQADCgMIAwABNQAECgoKRgAYAKgfAA==.Somepriest:BAABNQAECn81AAIUAAkKXiNDBgACAwAUAAkKXiNDBgACAwAAAA==.Sotteria:BAAANQABCgQIBAAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Spicyness:BAAANQADCgIIAgAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQAECgMIBAAAAA==.Spëcter:BAABNQAECn8XAAMdAAgKKQ5mJAAFAQAdAAcKzgxmJAAFAQAcAAYKywo6hQD1AAABNQAECgoKNwALAEcTAA==.',
Sq='Squishypoo:BAAANQAECgUICgAAAA==.',
St='Starcrush:BAAANQAECgYIBwAAAA==.Staticpower:BAAANQAECggIBAAAAA==.Stiffkitten:BAAANQADCgEIAQAAAA==.Stoked:BAAANQAECgUIBQAAAA==.Studentloans:BAAANQABCgIIAgAAAA==.Sturba:BAAANQABCgIIAgAAAA==.',
Su='Suave:BAAANQAECgMIAwAAAA==.Sugrace:BAAANQADCgQIBAAAAA==.Sunaerosinda:BAAANQADCgYIDAAAAA==.Sunow:BAAANQADCgYIFwAAAA==.Superdemonzz:BAABNQAECn8pAAMIAAoKfRzmCQCrAgAIAAoKfRzmCQCrAgAKAAcK8wcaFgDbAAABNQAECgoKMQANALYUAA==.Superpallyz:BAABNQAECn8xAAQNAAoKthQZSwA8AgANAAoKthQZSwA8AgAOAAEKAADMoQE2AAADAAIKoA9uYAAxAAAAAA==.Superspidey:BAAANQAECggIAwAAAA==.',
Sw='Swipeleft:BAACNQAFFH8KAAInAAUKwg5fEQDXAAAnAAUKwg5fEQDXAAA1AAQKf0QAAicACgqSGFAyAFECACcACgqSGFAyAFECAAAA.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.',
Ta='Tabarnak:BAABNQAECn83AAIjAAoKtiDsAwBaAwAjAAoKtiDsAwBaAwABNQAFFAIIBwAhANMeAA==.Taiynn:BAAANQADCggIFwAAAA==.Tallon:BAACNQAFFH8RAAIkAAUK9xr1AgDtAAAkAAUK9xr1AgDtAAA1AAQKfzQAAyQACgpyJGwCAFADACQACgpyJGwCAFADAAkAAQokIo81AGQAAAAA.Tarogen:BAABNQAECn8UAAITAAYKZxJ0qgARAQATAAYKZxJ0qgARAQAAAA==.Taszherazade:BAAANQADCgEJAQAAAA==.Taszmyhn:BAAANQADCgYICQAAAA==.',
Te='Tedious:BAAANQADCggIDQAAAA==.Teknique:BAAANQAECgIIAgAAAA==.Tempestclaw:BAAANQADCgUIBQAAAA==.Tendroni:BAABNQAECn8pAAIXAAoK+hIlJQDMAQAXAAoK+hIlJQDMAQAAAA==.Tenoch:BAAANQADCgEIAQAAAA==.Tervor:BAAANQAECgQICAAAAA==.Tessadin:BAAANQADCgYICgAAAA==.',
Th='Thaddaues:BAAANQAECggIDwABNQAFFAQICAADACQGAA==.Thanamoros:BAABNQAECn80AAIKAAoK4RE4CwAeAgAKAAoK4RE4CwAeAgABNQAFFAQIBwAMAOcbAA==.Thelephobia:BAAANQABCgcICAABNQADCgUIBQAeAAAAAA==.Theredwake:BAAANQAECgYICgAAAA==.Theroach:BAAANQAECgIIAwAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.Throfin:BAAANQAECgYICgAAAA==.Thwaxi:BAAANQADCgQICAAAAA==.',
Ti='Timeismoney:BAAANQADCggIPgAAAA==.Tinydeath:BAABNQAECn8bAAISAAYKuAWQegCqAAASAAYKuAWQegCqAAAAAA==.Tiognaska:BAAANQAECgQICAAAAA==.Tirdain:BAAANQADCgYICgAAAA==.',
To='Toeren:BAACNQAFFH8dAAIPAAYKqyLLBQCDAQAPAAYKqyLLBQCDAQA1AAQKfzwAAg8ACgpAJA8UAPECAA8ACgpAJA8UAPECAAAA.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgMIAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgoKJQATACATAA==.Tormented:BAABNQAECn8fAAIIAAoKeBsdDACFAgAIAAoKeBsdDACFAgABNQAECgoKIAASAAIiAA==.Torosentado:BAAANQAECgQICAAAAA==.',
Tr='Tregan:BAAANQAECgUICQAAAA==.Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQAECgQIBQAAAA==.Trollie:BAAANQAECggICAAAAA==.Trumu:BAAANQAECgEIAQAAAA==.Trïsh:BAAANQAECgQIAgABNQAECgoKOgADAFwQAA==.',
Ty='Tyinorin:BAAANQAECgMIBAAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAABNQAECn8sAAIIAAgKeg8PJwBLAQAIAAgKeg8PJwBLAQAAAA==.',
Ud='Udderjustice:BAABNQAECn80AAIDAAkKwg0pJQAxAQADAAkKwg0pJQAxAQAAAA==.',
Ug='Uglyelf:BAABNQAECn8wAAIPAAkK+wnrhQCRAQAPAAkK+wnrhQCRAQAAAA==.',
Ul='Ulthrak:BAAANQADCgIIAgAAAA==.Ultimakitty:BAAANQAECgQIAwAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQAECgcIFgAIAMMUAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vanhellsings:BAAANQAECgEIAQAAAA==.Vantrix:BAACNQAFFH8FAAInAAIKYAnjIACMAAAnAAIKYAnjIACMAAA1AAQKf0QAAycACgrnGMwdANsCACcACgrnGMwdANsCAAQABwquDlY4AFsBAAE1AAUUBAgHAAwA5xsA.Varabo:BAAANQAECgcIBwAAAA==.Varaxx:BAAANQADCgUIBQAAAA==.Varolina:BAAANQADCggIJQAAAA==.',
Ve='Velthala:BAABNQAECn8oAAITAAoKrhjWPQA8AgATAAoKrhjWPQA8AgAAAA==.Velyra:BAAANQAECgUICgABNQAECgYICwAeAAAAAA==.',
Vi='Vitner:BAAANQADCgMIBAABNQAECgkJGAABAK0XAA==.Vivieneaux:BAAANQABCgUICAAAAA==.',
Vl='Vladdawngard:BAAANQAECggICAAAAA==.',
Vo='Voidcorpse:BAAANQADCgEIAQAAAA==.Voidmama:BAAANQADCgYIBgAAAA==.Voidryn:BAAANQABCgcIEQAAAA==.Voidshifter:BAAANQADCgUIBQAAAA==.Vosaleana:BAABNQAECn8cAAIUAAcK5AW+NgDLAAAUAAcK5AW+NgDLAAAAAA==.',
Vr='Vraak:BAACNQAFFH8RAAIEAAgK0xRRBADpAQAEAAgK0xRRBADpAQA1AAQKfzIAAwQACgoiJR8GAGEDAAQACgoiJR8GAGEDACcAAwpVHmeHALUAAAAA.',
Vu='Vulcus:BAAANQAECgQIBwABNQAFFAgIEQAEANMUAA==.',
Vy='Vyndarien:BAAANQABCgcICgAAAA==.',
Wa='Wa:BAABNQAECn8YAAMDAAcK4hPkMgBLAQADAAcK4hPkMgBLAQAOAAEKAABouAEsAAAAAA==.Walimagus:BAAANQAECgMIAgAAAA==.Wattles:BAAANQAECgYICAAAAA==.Wattlez:BAAANQAECgIIAQAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wh='Wheeljack:BAABNQAECn8qAAQEAAkKjhiFFQBcAgAEAAkKjhiFFQBcAgAnAAEKAAAnuwAlAAAkAAQKyQIAAAAAAAABNQAFFAIIBgAiALcPAA==.',
Wi='Widowcancer:BAAANQADCgIJAgAAAA==.Wigblam:BAAANQAECgEIAQAAAA==.Will:BAACNQAFFH8SAAIOAAUKJiT4CAA+AQAOAAUKJiT4CAA+AQA1AAQKf0IAAg4ACgqrJmACAIMDAA4ACgqrJmACAIMDAAAA.',
Wo='Womdalie:BAAANQADCggIGwAAAA==.',
Wy='Wyckedpally:BAABNQAECn8bAAIOAAgK7wUBDQEJAQAOAAgK7wUBDQEJAQABNQAECggIIQAOAHUIAA==.',
Xa='Xanthös:BAAANQAFFAIIAgABNQAFFAgIEQAEANMUAA==.',
Xe='Xemnastrasza:BAABNQAECn8uAAMFAAoK/BVsCAAQAgAFAAkKNxRsCAAQAgAGAAgK4BU0FAALAgABNQAFFAQIBwAMAOcbAA==.Xenonne:BAAANQAECgMIBAABNQAFFAQIBwANADYNAA==.',
Xo='Xolither:BAABNQAECn8cAAICAAgKZxplXwADAgACAAgKZxplXwADAgAAAA==.',
Ye='Yenneferr:BAAANQAECggICQAAAA==.',
Yo='Yorgo:BAAANQADCggICAAAAA==.Yourwifesbf:BAABNQAECn9DAAIaAAoKYBmNCgALAgAaAAoKYBmNCgALAgAAAA==.Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgQIBgAAAA==.',
Za='Zachdemon:BAABNQAECn82AAIKAAkKBReZDgDPAQAKAAkKBReZDgDPAQAAAA==.Zarulu:BAAANQAECggIDAABNQAFFAQIBwAMAOcbAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zeeblax:BAAANQADCggICAAAAA==.Zenyátta:BAAANQAECgUIEAAAAA==.Zephymoo:BAABNQAECn9bAAMJAAoKqR37BgB5AgAJAAkK0x77BgB5AgAnAAQKhhZObwANAQAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zershadowi:BAAANQAECgEIAQAAAA==.Zertfelgard:BAAANQABCgcICgAAAA==.Zeyana:BAABNQAECn8eAAMKAAoKFBPQCQCvAQAKAAoKFBPQCQCvAQAXAAYKtQQeaADYAAABNQAECgoKMgAPAP4cAA==.',
Zh='Zhengshi:BAABNQAECn8lAAIVAAgK2wnHEQDyAAAVAAgK2wnHEQDyAAAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgcIDQAAAA==.',
Zo='Zoose:BAABNQAECn8pAAQTAAgK0RlWZgC4AQATAAgK+BdWZgC4AQAaAAQK6RnrKQDrAAAfAAEKhg6SMwA0AAAAAA==.Zosahe:BAABNQAECn8sAAMhAAoKPRHKGADUAQAhAAoKPRHKGADUAQAgAAgKqgcxKwAVAQAAAA==.Zoser:BAABNQAECn8oAAIhAAgKpiPOEQDQAgAhAAgKpiPOEQDQAgAAAA==.',
Zs='Zsófia:BAAANQADCgcIBwAAAA==.',
Zu='Zuckuss:BAAANQAECgMIBAAAAA==.',
Zy='Zymri:BAAANQADCgUICQABNQAECgUIEgAeAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgYIDQAAAA==.',
['Ôr']='Ôrdra:BAAANQAECggICAAAAA==.',
['Öl']='Ölivê:BAABNQAECn8ZAAIbAAkKBAlvcAA0AQAbAAkKBAlvcAA0AQAAAA==.',
['ßu']='ßugs:BAABNQAECn81AAIPAAkKFBiQVQAJAgAPAAkKFBiQVQAJAgAAAA==.',
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
