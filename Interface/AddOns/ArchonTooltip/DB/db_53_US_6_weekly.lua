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

local lookup = {'Warlock-Demonology','Priest-Holy','Paladin-Protection','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer','Druid-Feral','DemonHunter-Vengeance','Mage-Arcane','Shaman-Elemental','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Mage-Fire','Mage-Frost','DeathKnight-Frost','Warrior-Arms','Monk-Brewmaster','Priest-Discipline','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','DeathKnight-Blood','Unknown-Unknown','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Priest-Shadow','Shaman-Enhancement','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Druid-Balance','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Unholy',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acbabcaa:BAAANQAECgEIAQAAAA==.Aceon:BAAANQAECgIIBAAAAA==.Aceonarcher:BAAANQAECgQICAAAAA==.',
Ad='Adfectia:BAABNQAECn8tAAIBAAkK9Qo+agBeAQABAAkK9Qo+agBeAQAAAA==.',
Ae='Aelianna:BAAANQAECgYIDAAAAA==.Aeryana:BAACNQAFFH8FAAICAAIKWhbaHwCtAAACAAIKWhbaHwCtAAA1AAQKfzcAAgIACgpiI+QNAFUDAAIACgpiI+QNAFUDAAAA.Aeth:BAAANQAECgYIDAABNQAECgoKJAADAPwiAA==.Aethér:BAAANQAECgcIDwABNQAFFAcIEAAEAPoWAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgoKKQADAJUfAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgQICQAAAA==.',
Al='Alberoo:BAAANQABCgQIBAAAAA==.Alexstrászá:BAABNQAECn8lAAMFAAoKNgo/CAB0AQAFAAoKNgo/CAB0AQAGAAMKzwJ3NwBTAAAAAA==.Aloria:BAAANQADCgEIAQAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgUIDQAAAA==.',
Am='Amaarii:BAAANQABCgQJCAAAAA==.Ambeia:BAAANQAECgMIBQAAAA==.Amewow:BAACNQAFFH8YAAIGAAcKOCNeAADvAQAGAAcKOCNeAADvAQA1AAQKf0wAAwYACgplJbMCAIYDAAYACgplJbMCAIYDAAcABwp8FikPANkBAAAA.Amoril:BAABNQAECn8lAAIIAAoKsgUIJABEAQAIAAoKsgUIJABEAQAAAA==.',
An='Anarchy:BAABNQAECn8wAAIJAAgKohamDwB9AQAJAAgKohamDwB9AQAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Andrewchau:BAAANQAECgIIAgAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Annòy:BAABNQAECn9NAAIKAAoKFB+oAwAkAwAKAAoKFB+oAwAkAwAAAA==.Anorakswrath:BAABNQAECn8dAAILAAkKXQQQEAFyAQALAAkKXQQQEAFyAQAAAA==.',
Ap='Apokai:BAAANQAECgcIBwABNQAECgoKOwAMAPkeAA==.Apophys:BAAANQADCgcIIgAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Ariella:BAAANQADCgQIBAAAAA==.Artfulrodent:BAAANQADCgQIBAAAAA==.Aruneza:BAABNQAECn8aAAMGAAgKdhFQHQB5AQAGAAcKjg1QHQB5AQAHAAYKjgrYLwAfAQAAAA==.',
As='Asherous:BAAANQADCgQICQABNQAECgcIGwANAB4kAA==.Ashèr:BAABNQAECn8bAAMNAAcKHiSLOgB6AgANAAcKHiSLOgB6AgAOAAMKbgZrPAFhAAAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgUIEQABNQAECgoKIwAPADEUAA==.Auralion:BAAANQAECgQIBAAAAA==.Autoignition:BAABNQAECn8XAAQQAAkKthwwBAB1AQALAAcKqB9XwgAAAgAQAAUKDxswBAB1AQARAAMKlxnnIwDOAAABNQAECgoKIAASAAMiAA==.',
Ba='Badcompanytt:BAAANQADCgUIAwAAAA==.Bahnkano:BAABNQAECn8WAAIMAAgK6QSTwgANAQAMAAgK6QSTwgANAQAAAA==.Bakeddh:BAAANQADCgYIDAAAAA==.Balwal:BAAANQAECgIIAgAAAA==.Banditz:BAAANQADCgcIDwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAABNQAECn8YAAITAAYK9QMf+QDqAAATAAYK9QMf+QDqAAAAAA==.Beenah:BAAANQAECgUIEgAAAA==.Beyshunt:BAAANQADCgYICgAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAAANQAECgQICwAAAA==.',
Bo='Boltcutter:BAAANQADCgYICQAAAA==.Bombmagic:BAAANQADCgMIAwAAAA==.Bonesmccoy:BAAANQABCgYIBgAAAA==.Boomie:BAABNQAFFH8FAAIHAAUKqCTcBAAiAgAHAAUKqCTcBAAiAgABNQAFFAYIBgAEAIkOAA==.Boopty:BAAANQAECgUICQAAAA==.Booptydo:BAAANQADCggIHQAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAABNQAECn8YAAIPAAcKdAnSvgDwAAAPAAcKdAnSvgDwAAAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQAECgYICQABNQAFFAcIEAAEAPoWAA==.Brazyn:BAAANQADCggIIwAAAA==.Brevarda:BAAANQAECgYIDQAAAA==.Brewcelee:BAABNQAECn8uAAIUAAgKPA77CwA+AQAUAAgKPA77CwA+AQAAAA==.',
Bu='Bubblzmgee:BAABNQAECn9OAAIVAAoK+x29AABaAwAVAAoK+x29AABaAwAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCggIDgAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQAECgMIAwAAAA==.',
Ca='Cakeman:BAAANQAECgQIBAAAAA==.Capone:BAABNQAECn8cAAIWAAkKBA2eJACpAQAWAAkKBA2eJACpAQAAAA==.Captiva:BAAANQAECgEIAQAAAA==.Caracalous:BAAANQAECgYIDAAAAA==.Carindria:BAAANQADCggILAAAAA==.Carninn:BAAANQADCgcIBwAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cat:BAAANQAECgUIBQAAAA==.Cattiebrie:BAAANQAECgQIDAAAAA==.Caylavana:BAABNQAECn89AAMXAAoKlR1WAwBLAgAPAAgKqB+WSwCLAgAXAAgKqRlWAwBLAgAAAA==.',
Ce='Celaylria:BAABNQAECn86AAIYAAkKLhSZHwBTAgAYAAkKLhSZHwBTAgAAAA==.Ceyine:BAAANQAECgEIAQAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgUICQAAAA==.Clugorn:BAABNQAECn8mAAIZAAoK2QwsGQAGAQAZAAoK2QwsGQAGAQAAAA==.Clydè:BAABNQAECn8aAAIKAAoKdhQjCAC9AQAKAAoKdhQjCAC9AQAAAA==.',
Co='Codyj:BAAANQADCggIDgAAAA==.Colossus:BAAANQADCggJCwAAAA==.Colourhunt:BAABNQAECn8YAAMYAAkKMxAwPQBoAQAPAAcKZw6MnwDHAQAYAAcKCw4wPQBoAQAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAABNQAECn8rAAIaAAkKHRv6IgCfAgAaAAkKHRv6IgCfAgAAAA==.Copestabb:BAAANQAECgMIBAABNQAECgkJKwAaAB0bAA==.Corrode:BAAANQAECgEIAQAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crimie:BAAANQADCggICAAAAA==.Crusadare:BAAANQAECgQIBAAAAA==.',
Cu='Culture:BAAANQAECgQIBgAAAA==.',
Cy='Cybeldin:BAABNQAECn8hAAMPAAgKzggEowAnAQAPAAgKzggEowAnAQAYAAQK8QIzbgB3AAAAAA==.Cyberdemonxd:BAAANQADCgYIDAABNQAECgoKHAASAH4OAA==.Cyndyr:BAAANQAECgEIAQAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAABNQAECn8iAAIIAAkKhA/aHACJAQAIAAkKhA/aHACJAQAAAA==.Dalarrus:BAAANQAECgcIDQABNQAECgoKPQAXAJUdAA==.Dalishya:BAAANQADCgQIBAAAAA==.Darbane:BAAANQAECgMIAwAAAA==.Darek:BAABNQAECn8WAAILAAgKNQlDNgEyAQALAAgKNQlDNgEyAQAAAA==.Darilyns:BAAANQADCgQIBQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgcIHAAAAA==.Darylinn:BAAANQADCgQJBgAAAA==.Daymann:BAABNQAECn8YAAMCAAoKLROuOAAiAgACAAoKshGuOAAiAgAVAAEKKxzyIgBQAAAAAA==.',
De='Deathcore:BAAANQAECgIIAQABNQAECgkJMwALABQTAA==.Demonrife:BAAANQABCgYIBgABNQADCgcIHAAbAAAAAA==.Dependabull:BAAANQADCgYIBgABNQAECgQICQAbAAAAAA==.Dernis:BAAANQAECgIIAgABNQAECgoKMQATAMQeAA==.Derplock:BAAANQADCgcIEAAAAA==.Deshaman:BAAANQADCgMIAwABNQAFFAYIHQAPAKsiAA==.Devilbeast:BAAANQAECgQIDQAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgYIDgABNQAECgQICQAbAAAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Diaous:BAAANQADCgcIEQAAAA==.Disasterina:BAAANQADCgcIBwABNQAECgoKQgAIAOEgAA==.Disgruntled:BAAANQAECgcIEQAAAA==.',
Do='Docbrown:BAAANQADCgEIAQAAAA==.Dontormentaa:BAABNQAECn8lAAMTAAoKIBNtdgAzAgATAAoKohJtdgAzAgAcAAEK/Bl9LQBNAAAAAA==.Dontormentaj:BAABNQAECn8iAAQRAAgKXxfiFwA7AQALAAgK1xYpmABQAgARAAQKHB3iFwA7AQAQAAMKmRR7BwDCAAABNQAECgoKJQATACATAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAABNQAECn8bAAIFAAgKdww1EgAQAQAFAAgKdww1EgAQAQAAAA==.Dragonbrew:BAAANQADCggICAAAAA==.Dragonfang:BAAANQAECgcIEQABNQAECgoKIAASAAMiAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQAbAAAAAA==.Dreamhammer:BAAANQABCgcIDwAAAA==.Dreamlesnite:BAAANQABCggIFAAAAA==.Dreidelman:BAAANQAECgQIBAAAAA==.Druvisept:BAAANQADCgcIBwAAAA==.',
Du='Dugdimadome:BAAANQAECgQIAwAAAA==.Dunthur:BAAANQAECgMIBAABNQAECgYIBQAbAAAAAA==.',
Dy='Dylora:BAABNQAECn8iAAIdAAgKvBmJCgBbAgAdAAgKvBmJCgBbAgAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECn8sAAMNAAoKHiKJCQB8AwANAAoKHiKJCQB8AwAOAAEKqAw/wwEnAAABNQAFFAkJJQACAIMYAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAABNQAECn8cAAILAAgK3xnV1ADdAQALAAgK3xnV1ADdAQAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgYIDAAAAA==.Elystaria:BAABNQAECn8aAAMDAAYKsR25HwA7AQAOAAYKnxtE0AB7AQADAAUK3R25HwA7AQAAAA==.',
Em='Emokins:BAEBNQAECn8mAAIMAAgK2SEyJwDmAgAMAAgK2SEyJwDmAgAAAA==.',
En='Enyos:BAAANQADCgcIEAAAAA==.',
Ep='Epicnakedman:BAABNQAECn8UAAIPAAkKQB7FIwCHAgAPAAkKQB7FIwCHAgABNQAECgoKQQANAKgaAA==.',
Er='Eronoljr:BAAANQADCgEIAQAAAA==.Erubus:BAABNQAECn9FAAQUAAoKtCIPAwBpAwAUAAoKtCIPAwBpAwAeAAkK7hgvEgALAgAdAAMKZwpyLgBkAAAAAA==.Erubuss:BAABNQAECn8UAAIPAAgKXhOfawCiAQAPAAgKXhOfawCiAQAAAA==.Erubussyy:BAAANQAECgUIBQAAAA==.Eryss:BAABNQAECn8aAAIPAAYKEQpHsAANAQAPAAYKEQpHsAANAQAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Fa='Faithfulone:BAABNQAECn8VAAIaAAYKWghajADQAAAaAAYKWghajADQAAAAAA==.Farfidnoogan:BAAANQABCgQIBAAAAA==.Fateforged:BAAANQAECgYIBQAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAABNQAECn8fAAISAAcK2RzuKgDLAQASAAcK2RzuKgDLAQAAAA==.',
Fe='Fellariene:BAAANQADCggIDQAAAA==.',
Fi='Fistenlick:BAAANQADCgQIBAABNQADCgYIEQAbAAAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgYICwAAAA==.',
Fr='Freim:BAABNQAECn8VAAIcAAkKKx5HAwCzAgAcAAkKKx5HAwCzAgAAAA==.',
['Fà']='Fàmous:BAAANQAECgcICQAAAA==.',
Ga='Galabris:BAABNQAECn8hAAIaAAgKgxzrKQB1AgAaAAgKgxzrKQB1AgAAAA==.Garavos:BAAANQAECgIIAgAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.Gazzik:BAAANQAECgQIAwAAAA==.',
Ge='Gera:BAAANQAECgEIAQAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECggIDgAbAAAAAA==.Ghoulmania:BAABNQAECn8OAAIPAAoKywZ+9ACIAAAPAAoKywZ+9ACIAAAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQAECgYIEgAAAA==.Ginhei:BAAANQADCgcIBwAAAA==.Gitchusum:BAAANQAECgYIBgAAAA==.',
Gl='Glaivenez:BAAANQAECggIBgAAAA==.Gleenna:BAABNQAECn8dAAMfAAoKQxJpRgDHAQAfAAoKQxJpRgDHAQAMAAEKAAD4SAEqAAAAAA==.Glorify:BAAANQAECgIIAwABNQAECgoKJgAaAOkcAA==.',
Go='Goose:BAABNQAECn82AAMCAAkKEyIaFgAhAwACAAkKEyIaFgAhAwAVAAEK3BevJABGAAAAAA==.Gormladin:BAAANQADCgYIFwAAAA==.Gormstorm:BAABNQAECn8YAAMfAAYKBxrUTACsAQAfAAYKBxrUTACsAQAMAAIKZANzIQFOAAAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grimsreaper:BAAANQADCgQIBAAAAA==.Grouchy:BAAANQADCgQIBgABNQAECggIHwASANkcAA==.',
Gw='Gwynythe:BAAANQADCgYICQAAAA==.',
Ha='Hadess:BAAANQADCgQIBAAAAA==.Hadriac:BAAANQAECgIIAgAAAA==.Hailes:BAAANQABCgIIAQAAAA==.Halfang:BAAANQADCggIMgAAAA==.Halphas:BAAANQADCggICAABNQAECgMIAgAbAAAAAA==.Hanta:BAABNQAECn8mAAMPAAoKhxeBLgBaAgAPAAoKhxeBLgBaAgAYAAEK2gfiZAAsAAAAAA==.Haplò:BAAANQAECgIIAgAAAA==.Hastebuff:BAABNQAECn8ZAAIMAAoK/wtYQACYAQAMAAoK/wtYQACYAQAAAA==.',
He='Healless:BAAANQADCgUIBwABNQAECgoKPQAXAJUdAA==.Hentaime:BAAANQABCgMIAwAAAA==.',
Hi='Hildegarde:BAAANQADCggICAABNQAECgUIBQAbAAAAAA==.Hitpoints:BAAANQADCgYIDAABNQAECggIGgAgAEYMAA==.',
Ho='Holispirit:BAAANQABCgMIAwAAAA==.Holyfrog:BAAANQAECgUICgAAAA==.Holyhannah:BAAANQAECgQIBAAAAA==.Holyhope:BAABNQAECn9BAAINAAoKqBoGIACOAgANAAoKqBoGIACOAgAAAA==.Holylightz:BAAANQAECgYICgAAAA==.Holymana:BAABNQAECn8yAAMOAAoKyB/oKACWAgAOAAoKyB/oKACWAgADAAIKvweXZQBLAAAAAA==.Holymilkers:BAAANQADCggIDQABNQAECgoKNwAhACILAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAABNQAECn8yAAIiAAkK1Qw8IwAxAQAiAAkK1Qw8IwAxAQAAAA==.',
Hu='Huffingpaint:BAAANQADCggIFQABNQAECgUIBQAbAAAAAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAABNQAECn8yAAQBAAoK5xxbGACaAgABAAoK5xxbGACaAgAjAAcK0RQwCAAPAgAkAAIKfQ/LVwB4AAAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAABNQAECn87AAMMAAoK+R5uGACEAgAMAAoK+R5uGACEAgAfAAYKPwiyvwDqAAAAAA==.',
Il='Illidianna:BAABNQAECn82AAMIAAkKtBvBGwB4AgAIAAkKLxvBGwB4AgAWAAcKSxwmNwD3AQAAAA==.',
Im='Imfiredup:BAABNQAFFH8FAAILAAUKOBHADwA8AQALAAUKOBHADwA8AQAAAA==.Imitlol:BAABNQAECn8YAAIOAAcKbyRPYQB2AgAOAAcKbyRPYQB2AgAAAA==.',
In='Inception:BAAANQAECgEIAQAAAA==.Ingress:BAAANQADCgYJBgAAAA==.',
Is='Ishu:BAAANQADCgIIAwAAAA==.',
It='Itchynyple:BAAANQADCggIGAAAAA==.Ithowen:BAAANQABCgYIBgAAAA==.',
Ja='Jacques:BAAANQAECgcICgAAAA==.Jaetherion:BAABNQAECn8uAAMOAAkKuh4bUQCiAgAOAAkKuh4bUQCiAgADAAEKEgkkcgAtAAAAAA==.Jakes:BAAANQADCgYJDAAAAA==.Jayhawk:BAAANQAECgEIAwAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAFFAcIEAAMAJEdAA==.Jinx:BAAANQAECgMIAgAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jojohunts:BAAANQAECgEIAQAAAA==.Jonesy:BAAANQADCggICgABNQAECgoKVgAPACcaAA==.',
Ju='Junyubych:BAAANQADCgcIKgABNQAECggIGwAOAO0HAA==.',
['Jà']='Jàccuse:BAAANQADCgUIDAABNQAECggIGwAFAHcMAA==.Jàrnsaxa:BAAANQADCggIJgAAAA==.',
['Jò']='Jòhnnypopo:BAABNQAECn84AAIOAAoKXxWJYwDPAQAOAAoKXxWJYwDPAQAAAA==.',
Ka='Kaeladra:BAAANQABCgQIBgABNQAECgEIAwAbAAAAAA==.Kagé:BAAANQADCgEIAQAAAA==.Kaisra:BAAANQAECgUICAAAAA==.Kalida:BAAANQADCgYICwAAAA==.Kasumeli:BAAANQAECgYIDAAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayd:BAAANQADCggIHQAAAA==.Kayhan:BAAANQADCgQICgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kayos:BAAANQAECgEIAQAAAA==.Kazoo:BAAANQADCgMIAwABNQAECgMIAgAbAAAAAA==.Kazurend:BAACNQAFFH8RAAMgAAcKDBudBQDaAQAgAAYKCB+dBQDaAQACAAIKSgoaJgCiAAA1AAQKfy0AAyAACgqTIqAMACADACAACgqTIqAMACADAAIAAwruHIGeAMwAAAAA.',
Ke='Keish:BAAANQADCggICAAAAA==.Keleira:BAAANQAECgYICwAAAA==.Keyaielenst:BAAANQADCgYICwAAAA==.',
Kh='Khirina:BAABNQAECn8dAAMeAAgKKQwUNQBsAQAeAAgKKQwUNQBsAQAdAAUKOgp1JAC3AAAAAA==.Khristina:BAABNQAECn8bAAINAAgK/BpxWwAGAgANAAgK/BpxWwAGAgAAAA==.Khrogh:BAAANQAECgEIAwAAAA==.',
Ki='Kidiann:BAAANQAECgcIDQAAAA==.Kippo:BAEANQAECgcICAAAAA==.Kirar:BAAANQAECgMIAgAAAA==.Kisarrah:BAAANQABCgMIAwAAAA==.',
Kn='Knarn:BAABNQAECn8zAAIPAAkKAyLsIwCGAgAPAAkKAyLsIwCGAgAAAA==.Knazugardarg:BAAANQAECgcIBwAAAA==.Knorre:BAAANQADCgMIAwAAAA==.',
Ko='Kohde:BAABNQAECn8VAAMYAAgKlhQ3MwC0AQAYAAgKwBI3MwC0AQAPAAYKWRI+1QBWAQABNQAFFAkJLgAYAH8iAA==.Koralie:BAACNQAFFH8XAAIPAAcKlRySBAAQAgAPAAcKlRySBAAQAgA1AAQKfzMAAg8ACgoFJb4QAGADAA8ACgoFJb4QAGADAAAA.Korrum:BAAANQABCgIIBAAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgABNQAECgoKPwASAKgjAA==.',
Ky='Kyliekat:BAABNQAECn8VAAIlAAgKrQoybwANAQAlAAgKrQoybwANAQAAAA==.',
['Kå']='Kåiri:BAAANQAECgYIBgAAAA==.',
La='Lanceelot:BAAANQAECgUIDQAAAA==.Lanel:BAAANQAECgUIDgAAAA==.Lathelous:BAABNQAECn8sAAIDAAkKzSFIDQDHAgADAAkKzSFIDQDHAgAAAA==.Laulten:BAAANQABCgQIBAAAAA==.',
Le='Leintheir:BAAANQAECggIEwAAAA==.Lexloother:BAAANQABCggIEQAAAA==.',
Li='Lideina:BAAANQADCgUIBwAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Liebesleid:BAAANQADCgYICwABNQAECgUIBQAbAAAAAA==.Lightt:BAABNQAECn9aAAICAAoKlR6NDwA2AwACAAoKlR6NDwA2AwAAAA==.Liightt:BAABNQAECn9DAAICAAoKHxlOGQDfAgACAAoKHxlOGQDfAgAAAA==.Lilcozz:BAAANQAECgEIAQAAAA==.Lilpyroblast:BAACNQAFFH8KAAILAAQKQhHYHgDjAAALAAQKQhHYHgDjAAA1AAQKfyYAAgsACgoAGmJvAJ8CAAsACgoAGmJvAJ8CAAAA.Liriope:BAAANQADCggIEgAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUJBwAAAA==.Llars:BAABNQAECn8zAAIfAAkKLBlAKABZAgAfAAkKLBlAKABZAgAAAA==.',
Lo='Loryanna:BAAANQADCgYIHgAAAA==.Louie:BAAANQAECgcIDwAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Lu='Lumenne:BAAANQADCgUIBwAAAA==.Luxore:BAABNQAECn8kAAIDAAoKVw+sHgDzAQADAAoKVw+sHgDzAQABNQAECgoKOwAMAPkeAA==.',
Ly='Lyandrea:BAAANQADCggIIwAAAA==.Lyfebane:BAAANQADCgUJBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAABNQAECn8UAAMRAAgKWg9VFABkAQARAAgKWg9VFABkAQALAAQKpwbQegHMAAAAAA==.',
Ma='Main:BAABNQAECn85AAIOAAoKGA/nqwDIAQAOAAoKGA/nqwDIAQAAAA==.Majrmiståke:BAACNQAFFH8ZAAMRAAYK0g1nBAC1AAALAAYK8QrQHQDoAAARAAMKgAdnBAC1AAA1AAQKfzMAAxEACgryHocGAJgCABEACQqLGocGAJgCAAsACgp4HFROAP4BAAE1AAQKCgoxAA0AthQA.Malakir:BAAANQADCgYIEwAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAABNQAECn8bAAIRAAYKxghGJQDFAAARAAYKxghGJQDFAAAAAA==.Maliceone:BAAANQADCggIJAAAAA==.Mallucavian:BAABNQAECn8XAAMCAAcKnRyiTgDFAQACAAcKnRyiTgDFAQAVAAEKKAT3GAAlAAAAAA==.Mamadp:BAABNQAECn8cAAISAAcK2AZcdQDMAAASAAcK2AZcdQDMAAAAAA==.Manaholy:BAAANQADCggIDQAAAA==.Manek:BAABNQAECn9WAAIPAAoKJxqzPAAoAgAPAAoKJxqzPAAoAgAAAA==.Marraxa:BAABNQAECn8gAAQmAAgKCwiUKADgAAAmAAgKCwiUKADgAAAnAAQKYgPLFACmAAAoAAMKBQJ2SAB2AAAAAA==.Max:BAABNQAECn8aAAMBAAkK0hVpbAAZAgABAAgKmBNpbAAZAgAkAAMKlROVQQC9AAAAAA==.',
Me='Melevil:BAABNQAECn8XAAIcAAgK6QVVGAAaAQAcAAgK6QVVGAAaAQAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlin:BAAANQAECgQICQAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metafritz:BAAANQAECggICAABNQAECgoKGQAMAP8LAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgYIDAAAAA==.Milho:BAAANQADCgYIBgABNQAFFAIICAAWAEYiAA==.Milkmeholy:BAAANQADCgcICQAAAA==.Minikey:BAAANQAECgUIBgAAAA==.Mishosuki:BAAANQAECgcIDwABNQADCgQIBAAbAAAAAA==.Misscleo:BAABNQAECn8yAAILAAgKgxDthgBrAQALAAgKgxDthgBrAQAAAA==.Mistalar:BAAANQAECgYIBgAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Moltres:BAEBNQAFFH8FAAIGAAUKTiWDAAC8AQAGAAUKTiWDAAC8AQABNQAFFAgIAQAbAAAAAA==.Mongoro:BAAANQADCgEIAQAAAA==.Moonkist:BAABNQAECn8WAAMEAAcKZxGKMwASAQAEAAcKZxGKMwASAQAlAAEK9AKvugAmAAAAAA==.Moose:BAABNQAECn8bAAMpAAkKdB1LGQD1AgApAAkKdB1LGQD1AgAaAAEKAABcwgBDAAAAAA==.Mordrandian:BAAANQAECgEIAQAAAA==.Morroe:BAAANQADCgYIFwAAAA==.',
Mu='Muffindk:BAAANQAECggIEQAAAA==.Muffintop:BAAANQADCggIEQAAAA==.',
['Mó']='Mórningstar:BAAANQADCgIIBAAAAA==.',
Na='Nadless:BAAANQAECgYICQAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgIIAwAAAA==.Narokatha:BAAANQAECggICgAAAA==.Navariis:BAAANQADCgQIDQAAAA==.',
Ne='Necropanzer:BAABNQAECn8gAAISAAoKAyLMCgDrAgASAAoKAyLMCgDrAgAAAA==.Nelrehim:BAAANQAECgcIDwAAAA==.Nelumbo:BAABNQAFFH8GAAIEAAYKiQ7NBACfAQAEAAYKiQ7NBACfAQAAAA==.',
Ni='Niall:BAAANQAECgEIAQABNQAECgoKPQAXAJUdAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQAECgEIAQABNQAECggIHwASANkcAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECn8pAAMDAAoKlR+oEACUAgADAAoKlR+oEACUAgAOAAUK/xU36QBJAQAAAA==.Nokua:BAABNQAECn8bAAIOAAgK7Qe0ygACAQAOAAgK7Qe0ygACAQAAAA==.Noodles:BAABNQAECn80AAIlAAoKVBPrGgD8AQAlAAoKVBPrGgD8AQAAAA==.',
Nu='Nulannatoo:BAAANQAECggICAAAAA==.',
Ny='Nyank:BAAANQAECgMIAgABNQAECgoKHAASAH4OAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyogen:BAAANQAECggJBgAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAABNQAECn8zAAILAAkKFBNhXgDQAQALAAkKFBNhXgDQAQAAAA==.',
Od='Odysseus:BAABNQAECn8gAAIYAAkKvQ+3LADlAQAYAAkKvQ+3LADlAQAAAA==.',
Ol='Olgann:BAAANQAECgYICAAAAA==.Olguita:BAABNQAECn8YAAIMAAgKfxpjiQCMAQAMAAgKfxpjiQCMAQAAAA==.',
Om='Omez:BAAANQAECgYICgAAAA==.Omgowned:BAAANQAECgIIAgABNQAECggIHwABABUUAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCggIGQAAAA==.',
Op='Opheliastar:BAABNQAECn88AAIgAAoKaRiHDwAsAgAgAAoKaRiHDwAsAgAAAA==.',
Or='Ordovis:BAAANQAECgUIDAAAAA==.Orlucicia:BAAANQAECgIIAgAAAA==.Orobas:BAAANQAECggIAgAAAA==.',
Ow='Owltoidz:BAAANQABCgYIBwAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAABNQAECn8aAAIBAAYKewfioADfAAABAAYKewfioADfAAAAAA==.Paetyn:BAAANQADCgMIBQAAAA==.Pakoo:BAAANQAECgIIAQAAAA==.Paladerp:BAABNQAECn8hAAMNAAoKThjPMAAqAgANAAoKThjPMAAqAgAOAAIKDwhbZwE4AAAAAA==.Palanym:BAABNQAECn80AAINAAgKixfwQwDRAQANAAgKixfwQwDRAQAAAA==.Palidyne:BAAANQAECgYICQAAAA==.Pallyown:BAABNQAECn8dAAMNAAkKrx8gLgCuAgANAAkKrx8gLgCuAgAOAAIKrwibLwFwAAAAAA==.Papamidnite:BAAANQADCgMIAwAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQADCgYICAAAAA==.',
Pe='Peluij:BAAANQAECgUICAAAAA==.',
Ph='Phelement:BAABNQAECn8sAAIhAAoKeiLmAwBbAwAhAAoKeiLmAwBbAwAAAA==.Pheta:BAAANQADCggICAAAAA==.Phett:BAABNQAECn82AAMcAAoKXiCKBADwAgAcAAgKMiOKBADwAgATAAcKpBs1TgDiAQAAAA==.Phonk:BAAANQAECgMIAQABNQAECgoKLAAhAHoiAA==.Phædrea:BAAANQADCggICAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgkJNgACABMiAA==.Piffi:BAAANQAECgEIAwABNQAECgIIAQAbAAAAAA==.Pikatso:BAAANQADCgYICAAAAA==.Pimmscup:BAAANQADCgYIIAAAAA==.',
Po='Porgoon:BAAANQAECgEIAQAAAA==.',
Pr='Praedthy:BAAANQAFFAIIAgAAAA==.Prismatic:BAAANQAECggIBwAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raatus:BAAANQAECgIIAgABNQAECgoKHwAaACghAA==.Raenya:BAAANQAECgYIBQAAAA==.Raikouu:BAABNQAECn8ZAAIBAAcKXwiMzQAvAQABAAcKXwiMzQAvAQAAAA==.Rainydaze:BAAANQAECgQIBgAAAA==.Ramani:BAAANQADCgEIAQAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgEIAQABNQAECgoKPQAXAJUdAA==.Ramoreo:BAABNQAECn8XAAIJAAcK+geLIwCiAAAJAAcK+geLIwCiAAABNQAECgkJWAAWAEcKAA==.Rashun:BAABNQAECn8xAAMeAAkK/xgrFQDhAQAeAAkK/xgrFQDhAQAUAAcKiQusDQAfAQAAAA==.Raviolee:BAAANQAECgIIAQABNQAECggIHwABABUUAA==.Rayvin:BAAANQADCggIDQAAAA==.',
Re='Reanatilax:BAAANQABCgMJBQABNQAECggIHAACAGcaAA==.Regnier:BAAANQADCggIEAAAAA==.Relaeh:BAAANQADCgcJDQAAAA==.Resusitate:BAAANQADCgYJBgAAAA==.Rev:BAAANQAECggIDQAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQAECgMIAwABNQAECgoKFQABAIUMAA==.',
Ri='Rikashae:BAAANQADCgYJBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Roleon:BAAANQADCgYIEQAAAA==.Rollforpi:BAAANQAECgIIBAABNQAFFAcIEAAEAPoWAA==.Ropebunnyana:BAAANQAECgIJAwABNQAFFAIIBQACAFoWAA==.',
Ru='Ruki:BAAANQAECgUIBQAAAA==.Rumshwizzle:BAAANQADCgYICAAAAA==.',
Sa='Saltydk:BAABNQAECn8gAAIpAAkKhyClJACuAgApAAkKhyClJACuAgAAAA==.Samiracy:BAABNQAECn8hAAIkAAgKQRjvBAB7AQAkAAgKQRjvBAB7AQAAAA==.Sannrin:BAAANQADCgMIAwABNQAECgkJLAAPAJodAA==.Sataro:BAAANQABCggIEQAAAA==.',
Sc='Scappe:BAABNQAECn8fAAIaAAoKKCHlHADJAgAaAAoKKCHlHADJAgAAAA==.Schniel:BAABNQAECn8aAAICAAoKTw5JPwAFAgACAAoKTw5JPwAFAgAAAA==.',
Se='Sebek:BAAANQAECgQIBAAAAA==.Seefoof:BAAANQADCgIIAgAAAA==.Seitaer:BAAANQADCgYICQAAAA==.Senbatorii:BAABNQAECn8bAAQEAAgK6hmNQAAiAQAEAAYKlxaNQAAiAQAlAAUKXg6EdQD1AAAJAAIKTArCNgBlAAAAAA==.Sentrosi:BAAANQAECgEIAQAAAA==.Sethrow:BAABNQAECn8fAAQBAAgKFRTxoACUAQABAAYKRxXxoACUAQAjAAIKUQmPGwBlAAAkAAEK1RcFKwBFAAAAAA==.Severa:BAABNQAECn8tAAIOAAoK5BdkTgALAgAOAAoK5BdkTgALAgAAAA==.',
Sh='Shadoh:BAAANQAECgIIAgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowsale:BAAANQADCgYIDAAAAA==.Shamwowza:BAABNQAECn9CAAIfAAoKtxSkPQDuAQAfAAoKtxSkPQDuAQAAAA==.Shantifa:BAAANQADCggIDgAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAAbAAAAAA==.Shoshanaa:BAAANQADCgYIEQAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAAbAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECn9LAAIpAAoKVw8lJwB3AQApAAoKVw8lJwB3AQAAAA==.',
Sn='Sneakysneak:BAABNQAECn8ZAAInAAgKvRQUBwBOAgAnAAgKvRQUBwBOAgAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somavan:BAAANQADCgMIAwABNQAECgoKPQAXAJUdAA==.Somepriest:BAABNQAECn8xAAIgAAkKXiPmBQD4AgAgAAkKXiPmBQD4AgAAAA==.Sotteria:BAAANQABCgQIBAAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Spicyness:BAAANQADCgIIAgAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQAECgMIBAAAAA==.Spëcter:BAAANQAECgYIEwABNQAECgkJMwALABQTAA==.',
Sq='Squishypoo:BAAANQAECgYICgAAAA==.',
St='Starcrush:BAAANQAECgYIBwAAAA==.Staticpower:BAAANQAECggIBAAAAA==.Stiffkitten:BAAANQADCgEIAQAAAA==.Stoked:BAAANQAECgUIBQAAAA==.Studentloans:BAAANQABCgIIAgAAAA==.Sturba:BAAANQABCgIIAgAAAA==.',
Su='Sugrace:BAAANQADCgQIBAAAAA==.Sunaerosinda:BAAANQADCgYIDAAAAA==.Sunow:BAAANQADCgYIFwAAAA==.Superdemonzz:BAABNQAECn8gAAMKAAoKUg4VEwDkAAAKAAcK8wcVEwDkAAAIAAgK7w3GMADdAAABNQAECgoKMQANALYUAA==.Superpallyz:BAABNQAECn8xAAQNAAoKthQZSwA8AgANAAoKthQZSwA8AgAOAAEKAADMoQE2AAADAAIKoA/5WAAxAAAAAA==.Superspidey:BAAANQAECggIAwAAAA==.',
Sw='Swipeleft:BAACNQAFFH8FAAIlAAIK5QsfFgCGAAAlAAIK5QsfFgCGAAA1AAQKf0AAAiUACgqSGFAyAFECACUACgqSGFAyAFECAAAA.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.',
Ta='Tabarnak:BAABNQAECn83AAIhAAoKtiDsAwBaAwAhAAoKtiDsAwBaAwABNQAFFAIIBwAeANMeAA==.Taiynn:BAAANQADCggIFwAAAA==.Tallon:BAACNQAFFH8MAAIiAAUKnxqyAgDpAAAiAAUKnxqyAgDpAAA1AAQKfzIAAyIACgpyJPoBAFUDACIACgpyJPoBAFUDAAkAAQqWG5UzAE8AAAAA.Tarogen:BAABNQAECn8UAAITAAYKZxJsmgATAQATAAYKZxJsmgATAQAAAA==.Taszherazade:BAAANQADCgEJAQAAAA==.Taszmyhn:BAAANQADCgYICAAAAA==.',
Te='Teknique:BAAANQAECgIIAgAAAA==.Tempestclaw:BAAANQADCgUIBQAAAA==.Tendroni:BAABNQAECn8pAAIWAAoK+hIiIADPAQAWAAoK+hIiIADPAQAAAA==.Tervor:BAAANQAECgMIBQAAAA==.Tessadin:BAAANQADCgYICQAAAA==.',
Th='Thaddaues:BAAANQAECggIDwABNQAFFAQICAADACQGAA==.Thanamoros:BAABNQAECn80AAIKAAoK4RE4CwAeAgAKAAoK4RE4CwAeAgABNQAECgoKOwAMAPkeAA==.Thelephobia:BAAANQABCgcICAABNQADCgUIBQAbAAAAAA==.Theredwake:BAAANQAECgYICgAAAA==.Theroach:BAAANQAECgIIAwAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.Throfin:BAAANQAECgYICgAAAA==.Thwaxi:BAAANQADCgQICAAAAA==.',
Ti='Tinydeath:BAAANQAECgUIEQAAAA==.Tiognaska:BAAANQAECgQICAAAAA==.Tirdain:BAAANQADCgYICQAAAA==.',
To='Toeren:BAACNQAFFH8dAAIPAAYKqyImBACMAQAPAAYKqyImBACMAQA1AAQKfzwAAg8ACgpAJKoPAPoCAA8ACgpAJKoPAPoCAAAA.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgMIAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgoKJQATACATAA==.Tormented:BAABNQAECn8WAAIIAAoKMhlQDwA5AgAIAAoKMhlQDwA5AgABNQAECgoKIAASAAMiAA==.Torosentado:BAAANQAECgQICAAAAA==.',
Tr='Tregan:BAAANQAECgUICAAAAA==.Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQAECgQIBQAAAA==.Trollie:BAAANQAECggICAAAAA==.Trumu:BAAANQAECgEIAQAAAA==.Trïsh:BAAANQAECgQIAgABNQAECgoKOAADAFwQAA==.',
Ty='Tyinorin:BAAANQAECgEIAQAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAABNQAECn8qAAIIAAgKeg/fIgBOAQAIAAgKeg/fIgBOAQAAAA==.',
Ud='Udderjustice:BAABNQAECn8yAAIDAAgKqg0gJgAKAQADAAgKqg0gJgAKAQAAAA==.',
Ug='Uglyelf:BAABNQAECn8oAAIPAAgK0gmcjgBQAQAPAAgK0gmcjgBQAQAAAA==.',
Ul='Ulthrak:BAAANQADCgIIAgAAAA==.Ultimakitty:BAAANQAECgQIAwAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQAECgUIBQAbAAAAAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vanhellsings:BAAANQAECgEIAQAAAA==.Vantrix:BAACNQAFFH8FAAIlAAIKYwnjIACMAAAlAAIKYwnjIACMAAA1AAQKf0QAAyUACgrnGMwdANsCACUACgrnGMwdANsCAAQABwquDlY4AFsBAAE1AAQKCgo7AAwA+R4A.Varabo:BAAANQAECgcIBwAAAA==.Varaxx:BAAANQADCgUIBQAAAA==.Varolina:BAAANQADCggIJQAAAA==.',
Ve='Velmara:BAAANQABCgMIAwAAAA==.Velthala:BAABNQAECn8kAAITAAkK0hgJSQD1AQATAAkK0hgJSQD1AQAAAA==.Velyra:BAAANQAECgUICgABNQAECgYICwAbAAAAAA==.',
Vi='Vitner:BAAANQADCgMIBAABNQAECgkJGAABAK0XAA==.Vivieneaux:BAAANQABCgUICAAAAA==.',
Vl='Vladdawngard:BAAANQAECggICAAAAA==.',
Vo='Voidcorpse:BAAANQADCgEIAQAAAA==.Voidmama:BAAANQADCgYIBgAAAA==.Voidryn:BAAANQABCgcIEQAAAA==.Voidshifter:BAAANQADCgUIBQAAAA==.Vosaleana:BAABNQAECn8WAAIgAAYKVARHPACNAAAgAAYKVARHPACNAAAAAA==.',
Vr='Vraak:BAACNQAFFH8QAAIEAAcK+hZRBADpAQAEAAcK+hZRBADpAQA1AAQKfy8AAwQACgplJB8GAGEDAAQACgplJB8GAGEDACUAAwpVHmeHALUAAAAA.',
Vu='Vulcus:BAAANQAECgQIBwABNQAFFAcIEAAEAPoWAA==.',
Vy='Vyndarien:BAAANQABCgcICgAAAA==.',
['Vö']='Vöidríx:BAAANQADCgQIBAAAAA==.',
Wa='Wa:BAABNQAECn8YAAMDAAcK4hPkMgBLAQADAAcK4hPkMgBLAQAOAAEKAABouAEsAAAAAA==.Walimagus:BAAANQAECgMIAgAAAA==.Wattles:BAAANQAECgIIAgAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wh='Wheeljack:BAABNQAECn8kAAMEAAkKkhgNEgBfAgAEAAkKkhgNEgBfAgAlAAEKAAAnuwAlAAABNQAFFAIIBQAfAKYPAA==.',
Wi='Widowcancer:BAAANQADCgIJAgAAAA==.Wigblam:BAAANQAECgEIAQAAAA==.Will:BAACNQAFFH8OAAIOAAUKNCOXCAAlAQAOAAUKNCOXCAAlAQA1AAQKf0IAAg4ACgqrJooBAIUDAA4ACgqrJooBAIUDAAAA.',
Wo='Womdalie:BAAANQADCggIGwAAAA==.',
Wy='Wyckedpally:BAABNQAECn8ZAAIOAAcKRQYBDQEJAQAOAAcKRQYBDQEJAQABNQAECggIGwAOAO0HAA==.',
Xa='Xanthös:BAAANQAFFAIIAgABNQAFFAcIEAAEAPoWAA==.',
Xe='Xemnastrasza:BAABNQAECn8tAAMFAAoKLBRsCAAQAgAFAAkKaBJsCAAQAgAGAAgK4BU0FAALAgABNQAECgoKOwAMAPkeAA==.Xenonne:BAAANQAECgMIBAAAAA==.',
Xo='Xolither:BAABNQAECn8cAAICAAgKZxplXwADAgACAAgKZxplXwADAgAAAA==.',
Ye='Yenneferr:BAAANQAECgYIBQAAAA==.',
Yo='Yorgo:BAAANQADCggICAAAAA==.Yourwifesbf:BAABNQAECn8+AAIZAAoKPRggDAB1AgAZAAoKPRggDAB1AgAAAA==.Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgQIBgAAAA==.',
Za='Zachdemon:BAABNQAECn8xAAIKAAkK7xWZDgDPAQAKAAkK7xWZDgDPAQAAAA==.Zarulu:BAAANQAECggIDAABNQAECgoKOwAMAPkeAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zeeblax:BAAANQADCggICAAAAA==.Zenyátta:BAAANQAECgUIEAAAAA==.Zephymoo:BAABNQAECn9TAAMJAAoKRBwaCgDxAQAJAAkKOx0aCgDxAQAlAAQKhhZObwANAQAAAA==.Zeretha:BAAANQABCgIIAgAAAA==.Zershadowi:BAAANQAECgEIAQAAAA==.Zertfelgard:BAAANQABCgcICgAAAA==.Zeyana:BAABNQAECn8eAAMKAAoKEhNqCAC1AQAKAAoKEhNqCAC1AQAWAAYKtQQeaADYAAABNQAECgoKMgAPAP4cAA==.',
Zh='Zhengshi:BAABNQAECn8iAAIUAAgKsAkmEADwAAAUAAgKsAkmEADwAAAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgcIDQAAAA==.',
Zo='Zoose:BAABNQAECn8mAAQTAAgKzBeEYwCbAQATAAgKXxWEYwCbAQAZAAQK6RnrKQDrAAAcAAEKhg6SMwA0AAAAAA==.Zosahe:BAABNQAECn8pAAMeAAoKPRHYFQDXAQAeAAoKPRHYFQDXAQAdAAcK3AcxKwAVAQAAAA==.Zoser:BAABNQAECn8mAAIeAAgKpiPOEQDQAgAeAAgKpiPOEQDQAgAAAA==.',
Zs='Zsófia:BAAANQADCgcIBwAAAA==.',
Zu='Zuckuss:BAAANQAECgEIAQAAAA==.',
Zy='Zymri:BAAANQADCgUICQABNQAECgUIEgAbAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgUICQAAAA==.',
['Ôr']='Ôrdra:BAAANQAECggICAAAAA==.',
['Öl']='Ölivê:BAABNQAECn8YAAIaAAkKBAlvcAA0AQAaAAkKBAlvcAA0AQAAAA==.',
['ßu']='ßugs:BAABNQAECn8tAAIPAAgKXBjDbACgAQAPAAgKXBjDbACgAQAAAA==.',
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
