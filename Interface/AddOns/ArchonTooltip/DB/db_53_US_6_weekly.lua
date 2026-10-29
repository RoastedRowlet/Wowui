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

local lookup = {'Warlock-Demonology','Priest-Holy','Paladin-Protection','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer','Druid-Feral','DemonHunter-Vengeance','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Mage-Fire','Mage-Frost','DeathKnight-Frost','Shaman-Elemental','Warrior-Arms','Unknown-Unknown','Monk-Brewmaster','Priest-Discipline','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Priest-Shadow','Shaman-Enhancement','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Druid-Balance','Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','DeathKnight-Unholy',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acbabcaa:BAAANQAECgEIAQAAAA==.Aceon:BAAANQAECgIIBAAAAA==.Aceonarcher:BAAANQAECgQICAAAAA==.',
Ad='Adfectia:BAABNQAECn8nAAIBAAkK9QoaUQBwAQABAAkK9QoaUQBwAQAAAA==.',
Ae='Aelianna:BAAANQAECgYIDAAAAA==.Aeryana:BAABNQAECn8uAAICAAoKXiLkDQBVAwACAAoKXiLkDQBVAwAAAA==.Aeth:BAAANQAECgYIDAABNQAECgoKJAADAPwiAA==.Aethér:BAAANQAECgcIDwABNQAFFAcIEAAEAPoWAA==.',
Ag='Aggroout:BAAANQADCgYIBgABNQAECgoKKQADAJUfAA==.',
Ah='Ahsöka:BAAANQADCgIIAgAAAA==.',
Ai='Aimbel:BAAANQADCgQICQAAAA==.',
Al='Alberoo:BAAANQABCgQIBAAAAA==.Alexstrászá:BAABNQAECn8bAAMFAAoKRgjmDgBUAQAFAAkKyQjmDgBUAQAGAAMKzwJ3NwBTAAAAAA==.Aloria:BAAANQADCgEIAQAAAA==.Alynas:BAAANQADCgUIBQAAAA==.Alysona:BAAANQADCgUIDQAAAA==.',
Am='Amaarii:BAAANQABCgQJCAAAAA==.Ambeia:BAAANQAECgMIBQAAAA==.Amewow:BAACNQAFFH8YAAIGAAcKOCM7AAD7AQAGAAcKOCM7AAD7AQA1AAQKf0AAAwYACgpdJbMCAIYDAAYACgpdJbMCAIYDAAcABgqvDRUVABwBAAAA.Amoril:BAABNQAECn8bAAIIAAkK2ATLIgASAQAIAAkK2ATLIgASAQAAAA==.Amìko:BAAANQADCggICAAAAA==.',
An='Anarchy:BAABNQAECn8oAAIJAAgKhRPRCwB5AQAJAAgKhRPRCwB5AQAAAA==.Andraxi:BAAANQADCgYICwAAAA==.Andrewchau:BAAANQAECgIIAgAAAA==.Angewomon:BAAANQADCgIIAgAAAA==.Annòy:BAABNQAECn9FAAIKAAoKFB+oAwAkAwAKAAoKFB+oAwAkAwAAAA==.Anorakswrath:BAABNQAECn8dAAILAAkKXQQQEAFyAQALAAkKXQQQEAFyAQAAAA==.',
Ap='Apophys:BAAANQADCggIHwAAAA==.',
Ar='Ariees:BAAANQADCgEIAQAAAA==.Ariella:BAAANQADCgQIBAAAAA==.Artfulrodent:BAAANQADCgQIBAAAAA==.Aruneza:BAABNQAECn8YAAMGAAgKdhFQHQB5AQAGAAcKjg1QHQB5AQAHAAYK9AnYLwAfAQAAAA==.',
As='Asherous:BAAANQADCgQICQABNQAECgcIGwAMAB4kAA==.Ashèr:BAABNQAECn8bAAMMAAcKHiRJKAAPAgAMAAcKHiRJKAAPAgANAAMKbgYPGAFhAAAAAA==.Asunnaa:BAAANQADCgIIAwAAAA==.',
At='Atenchion:BAAANQAECgQIBAAAAA==.Atticuz:BAAANQADCgIIAgAAAA==.',
Au='Aura:BAAANQAECgUIEQABNQAECgoKHgAOACsUAA==.Auralion:BAAANQAECgQIBAAAAA==.Autoignition:BAABNQAECn8XAAQPAAkKthwwBAB1AQALAAcKqB9XwgAAAgAPAAUKDxswBAB1AQAQAAMKlxnnIwDOAAABNQAECgoKFwARACsdAA==.',
Ba='Badcompanytt:BAAANQADCgUIAwAAAA==.Bahnkano:BAABNQAECn8WAAISAAgK6QSTwgANAQASAAgK6QSTwgANAQAAAA==.Bakeddh:BAAANQADCgYIDAAAAA==.Balwal:BAAANQAECgIIAgAAAA==.Banditz:BAAANQADCgcIDwAAAA==.Bashfury:BAAANQAECgEIAQAAAA==.',
Be='Beefcåkes:BAABNQAECn8YAAITAAYK9QMf+QDqAAATAAYK9QMf+QDqAAAAAA==.Beenah:BAAANQAECgUIEQAAAA==.Beyshunt:BAAANQADCgYICgAAAA==.',
Bl='Bloodrain:BAAANQAECggIBwAAAA==.Blàst:BAAANQAECgMIBwAAAA==.',
Bo='Boltcutter:BAAANQADCgQIBAAAAA==.Bombmagic:BAAANQADCgMIAwAAAA==.Bonesmccoy:BAAANQABCgYIBgAAAA==.Boomie:BAABNQAFFH8FAAIHAAUKqCTcBAAiAgAHAAUKqCTcBAAiAgABNQAFFAgIBAAUAAAAAA==.Boopty:BAAANQAECgUIBQAAAA==.Booptydo:BAAANQADCggIHQAAAA==.Boris:BAAANQAECgIIAgAAAA==.Bowhawk:BAAANQAECgYIDgAAAA==.',
Bp='Bpwhunter:BAAANQAECgQICgAAAA==.',
Br='Braiin:BAAANQAECgcICQABNQAFFAcIEAAEAPoWAA==.Brazyn:BAAANQADCggIIwAAAA==.Brevarda:BAAANQAECgYIDQAAAA==.Brewcelee:BAABNQAECn8nAAIVAAcKoA0CDQDzAAAVAAcKoA0CDQDzAAAAAA==.',
Bu='Bubblzmgee:BAABNQAECn9CAAIWAAoKnh3/AADWAgAWAAoKnh3/AADWAgAAAA==.Buscemi:BAAANQADCggIDAAAAA==.Bustofez:BAAANQADCggIDgAAAA==.Buttèrs:BAAANQADCgEIAQAAAA==.',
['Bé']='Béach:BAAANQAECgMIAwAAAA==.',
Ca='Cakeman:BAAANQAECgQIBAAAAA==.Capone:BAABNQAECn8WAAIXAAkKCgxnHAC4AQAXAAkKCgxnHAC4AQAAAA==.Captiva:BAAANQAECgEIAQAAAA==.Caracalous:BAAANQAECgYIDAAAAA==.Carindria:BAAANQADCggILAAAAA==.Carninn:BAAANQADCgcIBwAAAA==.Castermcfear:BAAANQABCgIIAgAAAA==.Cattiebrie:BAAANQAECgQIDAAAAA==.Caylavana:BAABNQAECn8yAAMOAAkK6x2WSwCLAgAOAAgKqB+WSwCLAgAYAAQKMw9sCADkAAAAAA==.',
Ce='Celaylria:BAABNQAECn8zAAIZAAkKzhOZHwBTAgAZAAkKzhOZHwBTAgAAAA==.Ceyine:BAAANQAECgEIAQAAAA==.',
Ch='Charmeleön:BAAANQADCgYIBgAAAA==.Chronicfury:BAAANQABCgIIAgAAAA==.',
Cl='Cloudedjayd:BAAANQADCgcIDgAAAA==.Cloudedmonk:BAAANQADCgUICQAAAA==.Clugorn:BAABNQAECn8mAAIaAAoK2QwpEwAMAQAaAAoK2QwpEwAMAQAAAA==.Clydè:BAAANQAECggIDwAAAA==.',
Co='Codyj:BAAANQADCggIDgAAAA==.Colossus:BAAANQADCggJCwAAAA==.Colourhunt:BAABNQAECn8YAAMZAAkKMxAwPQBoAQAOAAcKZw6MnwDHAQAZAAcKCw4wPQBoAQAAAA==.Condewit:BAAANQADCgUIBQAAAA==.Conoresa:BAAANQADCgMIAwAAAA==.Copedk:BAABNQAECn8rAAIbAAkKHRv6IgCfAgAbAAkKHRv6IgCfAgAAAA==.Copestabb:BAAANQAECgMIBAABNQAECgkJKwAbAB0bAA==.Corrode:BAAANQAECgEIAQAAAA==.Cozymav:BAAANQADCgUIBQAAAA==.',
Cp='Cpt:BAAANQADCgEIAQAAAA==.',
Cr='Crimie:BAAANQADCggICAAAAA==.Crusadare:BAAANQAECgQIBAAAAA==.',
Cu='Culture:BAAANQAECgQIBAAAAA==.',
Cy='Cybeldin:BAABNQAECn8bAAMOAAgKsgjvjAAXAQAOAAgKsgjvjAAXAQAZAAQK8QIzbgB3AAAAAA==.Cyberdemonxd:BAAANQADCgYIDAABNQAECgkJGAARADwOAA==.Cyndyr:BAAANQAECgEIAQAAAA==.',
['Cë']='Cërßerus:BAAANQADCgYIBgAAAA==.',
Da='Daddysparey:BAABNQAECn8gAAIIAAgKHxB/MQC1AQAIAAgKHxB/MQC1AQAAAA==.Dalarrus:BAAANQAECgcIDQABNQAECgkJMgAOAOsdAA==.Dalishya:BAAANQADCgQIBAAAAA==.Darbane:BAAANQAECgMIAwAAAA==.Darek:BAAANQAECgUIEgAAAA==.Darilyns:BAAANQADCgQIBQAAAA==.Darkbiffhunt:BAAANQADCgMIAwAAAA==.Darkrife:BAAANQADCgcIGAAAAA==.Darylinn:BAAANQADCgQJBgAAAA==.Daymann:BAAANQAECggIEgAAAA==.',
De='Demonrife:BAAANQABCgYIBgABNQADCgcIGAAUAAAAAA==.Dependabull:BAAANQADCgYIBgABNQAECgQICQAUAAAAAA==.Dernis:BAAANQAECgIIAgABNQAECgoKMAATAG8eAA==.Derplock:BAAANQADCgcIEAAAAA==.Deshaman:BAAANQADCgMIAwABNQAFFAUIGAAOADQdAA==.Devilbeast:BAAANQAECgQIDQAAAA==.Dew:BAAANQABCgQIAwAAAA==.',
Dh='Dhargo:BAAANQAECgYIDgABNQAECgQICQAUAAAAAA==.',
Di='Diablosauz:BAAANQADCgQIBAAAAA==.Diaous:BAAANQADCgcIEQAAAA==.Disasterina:BAAANQADCgcIBwABNQAECgoKOwAIAGYeAA==.Disgruntled:BAAANQAECgcIEQAAAA==.',
Do='Docbrown:BAAANQADCgEIAQAAAA==.Dontormentaa:BAABNQAECn8jAAMTAAoKIBMsVgB/AQATAAoKohIsVgB/AQAcAAEK/Bl9LQBNAAAAAA==.Dontormentaj:BAABNQAECn8iAAQQAAgKXxfiFwA7AQALAAgK1xYpmABQAgAQAAQKHB3iFwA7AQAPAAMKmRR7BwDCAAABNQAECgoKIwATACATAA==.Doomzday:BAAANQADCgYIDQAAAA==.',
Dr='Dracthra:BAABNQAECn8aAAIFAAgKAAw1EgAQAQAFAAgKAAw1EgAQAQAAAA==.Dragonbrew:BAAANQADCggICAAAAA==.Dragonfang:BAAANQAECgcIEQABNQAECgoKFwARACsdAA==.Drakk:BAAANQADCgUIBQABNQAECgEIAQAUAAAAAA==.Dreamhammer:BAAANQABCgcIDwAAAA==.Dreamlesnite:BAAANQABCggIFAAAAA==.Dreidelman:BAAANQAECgQIBAAAAA==.Druvisept:BAAANQADCgcIBwAAAA==.',
Du='Dugdimadome:BAAANQAECgMIAwAAAA==.Dunthur:BAAANQAECgMIBAABNQAECgYIBQAUAAAAAA==.',
Dy='Dylora:BAABNQAECn8bAAIdAAgK8ROIEABzAQAdAAgK8ROIEABzAQAAAA==.',
Ea='Ealdoras:BAAANQADCggIDgAAAA==.',
Eg='Egg:BAABNQAECn8qAAMMAAoKtyGJCQB8AwAMAAoKtyGJCQB8AwANAAEKqAw/wwEnAAABNQAFFAgIHQACAPYVAA==.',
El='Elassha:BAAANQADCggICwAAAA==.Elatio:BAABNQAECn8bAAILAAgKAhjV1ADdAQALAAgKAhjV1ADdAQAAAA==.Elfairea:BAAANQADCgEIAQAAAA==.Elmortal:BAAANQAECgYIDAAAAA==.Elystaria:BAABNQAECn8YAAMDAAUK1B5XFwBHAQANAAUKPRxE0AB7AQADAAUK3R1XFwBHAQAAAA==.',
Em='Emokins:BAEBNQAECn8fAAISAAgK0iEyJwDmAgASAAgK0iEyJwDmAgAAAA==.',
En='Enyos:BAAANQADCgcIEAAAAA==.',
Ep='Epicnakedman:BAAANQAECggIEQABNQAECgoKMwAMAHIWAA==.',
Er='Eronoljr:BAAANQADCgEIAQAAAA==.Erubus:BAABNQAECn89AAQVAAoKfiEPAwBpAwAVAAoKfiEPAwBpAwAeAAUKchUsPgAlAQAdAAMKZwq/JgBsAAAAAA==.Erubuss:BAAANQAECgYIDwAAAA==.Eryss:BAABNQAECn8YAAIOAAUKbwvfpgDgAAAOAAUKbwvfpgDgAAAAAA==.',
Ex='Excalibúr:BAAANQADCgcIBwAAAA==.',
Fa='Faithfulone:BAAANQAECgUIEwAAAA==.Farfidnoogan:BAAANQABCgQIBAAAAA==.Fateforged:BAAANQAECgYIBQAAAA==.Fatercul:BAAANQADCgEIAQAAAA==.',
Fd='Fdk:BAABNQAECn8WAAIRAAYKCh11MQBeAQARAAYKCh11MQBeAQAAAA==.',
Fe='Fellariene:BAAANQADCggIDQAAAA==.',
Fi='Fistenlick:BAAANQADCgMIAwABNQADCggIDgAUAAAAAA==.',
Fo='Forilla:BAAANQAECgQIBQAAAA==.Fortissimo:BAAANQADCgYICwAAAA==.',
Fr='Freim:BAAANQAFFAEIAQAAAA==.',
['Fà']='Fàmous:BAAANQAECgcICQAAAA==.',
Ga='Galabris:BAABNQAECn8fAAIbAAgK/hvrKQB1AgAbAAgK/hvrKQB1AgAAAA==.Garavos:BAAANQAECgIIAgAAAA==.Gasilbench:BAAANQAECgEIAQAAAA==.Gazzik:BAAANQAECgQIAwAAAA==.',
Ge='Gera:BAAANQAECgEIAQAAAA==.',
Gh='Ghostboydk:BAAANQADCgYIBgABNQAECgQICAAUAAAAAA==.Ghoulmania:BAAANQAECggICwAAAA==.',
Gi='Gimligrimes:BAAANQADCgYIBgAAAA==.Gington:BAAANQAECgUIDQAAAA==.Gitchusum:BAAANQAECgYIBgAAAA==.',
Gl='Glaivenez:BAAANQAECggIBgAAAA==.Gleenna:BAAANQAECggIEwAAAA==.Glorify:BAAANQAECgIIAwABNQAECgkJIgAbAAEdAA==.',
Go='Goose:BAABNQAECn8wAAMCAAkK9yEaFgAhAwACAAkK9yEaFgAhAwAWAAEK3BevJABGAAAAAA==.Gormladin:BAAANQADCgYIFwAAAA==.Gormstorm:BAABNQAECn8WAAMfAAUKFhkrUABWAQAfAAUKFhkrUABWAQASAAIKZANzIQFOAAAAAA==.',
Gr='Greenbahamut:BAAANQADCgEIAQAAAA==.Grimsreaper:BAAANQADCgQIBAAAAA==.Grouchy:BAAANQADCgQIBgABNQAECgcIFgARAAodAA==.',
Gw='Gwynythe:BAAANQADCgQIBAAAAA==.',
Ha='Hadess:BAAANQADCgQIBAAAAA==.Hadriac:BAAANQAECgIIAgAAAA==.Hailes:BAAANQABCgIIAQAAAA==.Halfang:BAAANQADCggIMgAAAA==.Hanta:BAABNQAECn8iAAMOAAoKqhLiMgAUAgAOAAoKqhLiMgAUAgAZAAEK2gfjVwAuAAAAAA==.Haplò:BAAANQAECgIIAgAAAA==.Hastebuff:BAABNQAECn8VAAISAAoK+gqgMgCNAQASAAoK+gqgMgCNAQAAAA==.',
He='Hentaime:BAAANQABCgMIAwAAAA==.',
Hi='Hildegarde:BAAANQADCggICAABNQAECgUIBQAUAAAAAA==.Hitpoints:BAAANQADCgYIDAABNQAECggIGQAgAEYMAA==.',
Ho='Holispirit:BAAANQABCgMIAwAAAA==.Holyfrog:BAAANQAECgUICgAAAA==.Holyhannah:BAAANQADCggIDwAAAA==.Holyhope:BAABNQAECn8zAAIMAAoKchbIPwBlAgAMAAoKchbIPwBlAgAAAA==.Holylightz:BAAANQAECgYICgAAAA==.Holymana:BAABNQAECn8rAAMNAAoKFh6dLQBHAgANAAoKFh6dLQBHAgADAAIKvweXZQBLAAAAAA==.Holymilkers:BAAANQADCggIDQABNQAECgoKMQAhAMQKAA==.Honeybunns:BAAANQADCgUIBQAAAA==.Hosstx:BAAANQADCgEIAQAAAA==.Hotandready:BAABNQAECn8qAAIiAAkKmQwuGwAxAQAiAAkKmQwuGwAxAQAAAA==.',
Hu='Huffingpaint:BAAANQADCggIFQABNQAECgUIBQAUAAAAAA==.Hukhokhan:BAAANQADCggIDwAAAA==.Hutzil:BAABNQAECn8oAAQjAAoKghowCAAPAgABAAkKYRsJawAcAgAjAAcK0RQwCAAPAgAkAAIKfQ/LVwB4AAAAAA==.Hutzilla:BAAANQABCgYICAAAAA==.',
Ia='Iakopa:BAABNQAECn86AAMSAAoK+R7vDwCYAgASAAoK+R7vDwCYAgAfAAYKPwiyvwDqAAAAAA==.',
Il='Illidianna:BAABNQAECn8vAAMIAAkKtBvBGwB4AgAIAAkKLxvBGwB4AgAXAAcKSxwmNwD3AQAAAA==.',
Im='Imfiredup:BAAANQAECggIBQAAAA==.Imitlol:BAABNQAECn8YAAINAAcKbyRPYQB2AgANAAcKbyRPYQB2AgAAAA==.',
In='Inception:BAAANQAECgEIAQAAAA==.Ingress:BAAANQADCgYJBgAAAA==.',
Is='Ishu:BAAANQADCgIIAwAAAA==.',
It='Itchynyple:BAAANQADCggIGAAAAA==.Ithowen:BAAANQABCgYIBgAAAA==.',
Ja='Jacques:BAAANQAECgUIBAAAAA==.Jaetherion:BAABNQAECn8nAAMNAAkKuh7hOAAWAgANAAkKuh7hOAAWAgADAAEKEgkkcgAtAAAAAA==.Jakes:BAAANQADCgYJDAAAAA==.Jayhawk:BAAANQAECgEIAwAAAA==.',
Ji='Jimothy:BAAANQADCgcIEwABNQAFFAcIEAASAJEdAA==.Jinx:BAAANQAECgMIAgAAAA==.',
Jo='Johaliz:BAAANQADCgEIAQAAAA==.Johnnypopoff:BAAANQADCgYIBgAAAA==.Jojohunts:BAAANQAECgEIAQAAAA==.Jonesy:BAAANQADCggICgABNQAECgoKSwAOAAcZAA==.',
Ju='Junyubych:BAAANQADCgcIJQABNQAECgYIFAANAPEGAA==.',
['Jà']='Jàccuse:BAAANQADCgUIDAABNQAECggIGgAFAAAMAA==.Jàrnsaxa:BAAANQADCggIJgAAAA==.',
['Jò']='Jòhnnypopo:BAABNQAECn8vAAINAAoK4xQZRgDmAQANAAoK4xQZRgDmAQAAAA==.',
Ka='Kaeladra:BAAANQABCgQIBgABNQAECgEIAwAUAAAAAA==.Kagé:BAAANQADCgEIAQAAAA==.Kaisra:BAAANQAECgUICAAAAA==.Kalida:BAAANQADCgYICwAAAA==.Kasumeli:BAAANQAECgYIDAAAAA==.Kathelas:BAAANQADCgYIBgAAAA==.Kayd:BAAANQADCggIHQAAAA==.Kayhan:BAAANQADCgQICgAAAA==.Kaylaiis:BAAANQADCggICAAAAA==.Kaylastrasza:BAAANQADCgYICgAAAA==.Kayos:BAAANQAECgEIAQAAAA==.Kazoo:BAAANQADCgMIAwABNQAECgMIAgAUAAAAAA==.Kazurend:BAACNQAFFH8RAAMgAAcKDBudBQDaAQAgAAYKCB+dBQDaAQACAAIKSgoaJgCiAAA1AAQKfywAAyAACgqTIqAMACADACAACgqTIqAMACADAAIAAwruHLeDANEAAAAA.',
Ke='Keish:BAAANQADCggICAAAAA==.Keleira:BAAANQAECgUICQABNQAECgUICgAUAAAAAA==.Keyaielenst:BAAANQADCgYICwAAAA==.',
Kh='Khirina:BAABNQAECn8YAAMeAAgKKQwUNQBsAQAeAAgKKQwUNQBsAQAdAAMKwAjCPwB5AAAAAA==.Khristina:BAABNQAECn8aAAIMAAgK+RpxWwAGAgAMAAgK+RpxWwAGAgAAAA==.Khrogh:BAAANQAECgEIAwAAAA==.',
Ki='Kidiann:BAAANQAECgcIDQAAAA==.Kippo:BAEANQAECgcICAAAAA==.Kirar:BAAANQAECgMIAgAAAA==.Kisarrah:BAAANQABCgMIAwAAAA==.',
Kn='Knarn:BAABNQAECn8tAAIOAAkKwCFlGACUAgAOAAkKwCFlGACUAgAAAA==.Knazugardarg:BAAANQAECggIBwAAAA==.',
Ko='Kohde:BAABNQAECn8VAAMZAAgKlhQ3MwC0AQAZAAgKwBI3MwC0AQAOAAYKWRI+1QBWAQABNQAFFAkJLgAZAH8iAA==.Koralie:BAACNQAFFH8XAAIOAAcKlRySBAAQAgAOAAcKlRySBAAQAgA1AAQKfzAAAg4ACgr4JL4QAGADAA4ACgr4JL4QAGADAAAA.Korrum:BAAANQABCgIIAgAAAA==.',
Kr='Krillaxx:BAAANQAECgQIBAAAAA==.',
Kt='Ktullanux:BAAANQAECgIIAgABNQAECgoKNQARAIojAA==.',
Ky='Kyliekat:BAABNQAECn8VAAIlAAgKrQoybwANAQAlAAgKrQoybwANAQAAAA==.',
['Kå']='Kåiri:BAAANQAECgUIBgAAAA==.',
La='Lanceelot:BAAANQAECgQICAAAAA==.Lanel:BAAANQAECgUIDgAAAA==.Lathelous:BAABNQAECn8mAAIDAAkKkCFIDQDHAgADAAkKkCFIDQDHAgAAAA==.Laulten:BAAANQABCgQIBAAAAA==.',
Le='Leintheir:BAAANQAECgcIEQAAAA==.',
Li='Lideina:BAAANQADCgUIBwAAAA==.Lieahi:BAAANQAECgIIAQAAAA==.Liebesleid:BAAANQADCgYICwABNQAECgUIBQAUAAAAAA==.Lightt:BAABNQAECn9PAAICAAoK7hq4HwBjAgACAAoK7hq4HwBjAgAAAA==.Liightt:BAABNQAECn85AAICAAoKoheOEgDVAgACAAoKoheOEgDVAgAAAA==.Lilcozz:BAAANQAECgEIAQAAAA==.Lilpyroblast:BAACNQAFFH8HAAILAAMKpA93GADlAAALAAMKpA93GADlAAA1AAQKfyMAAgsACgoaGGJvAJ8CAAsACgoaGGJvAJ8CAAAA.Liriope:BAAANQADCggIEgAAAA==.Lizbethstar:BAAANQADCggIDAAAAA==.',
Ll='Llaerwyn:BAAANQADCgUJBwAAAA==.Llars:BAABNQAECn8tAAIfAAkKKhWrLQDvAQAfAAkKKhWrLQDvAQAAAA==.',
Lo='Loryanna:BAAANQADCgYIHgAAAA==.Louie:BAAANQAECggICgAAAA==.Lovehandless:BAAANQADCgIIAgAAAA==.',
Lu='Lumenne:BAAANQADCgUIBwAAAA==.Luxore:BAABNQAECn8hAAIDAAoKVw+sHgDzAQADAAoKVw+sHgDzAQABNQAECgoKOgASAPkeAA==.',
Ly='Lyandrea:BAAANQADCggIIwAAAA==.Lyfebane:BAAANQADCgUJBQAAAA==.Lynaomira:BAAANQADCgMIAwAAAA==.',
['Lõ']='Lõrs:BAAANQADCgMIBQAAAA==.',
['Lø']='Lørs:BAAANQAECgYIEQAAAA==.',
Ma='Main:BAABNQAECn81AAINAAoK5Q3nqwDIAQANAAoK5Q3nqwDIAQAAAA==.Majrmiståke:BAACNQAFFH8UAAMQAAUKSBD3BQCxAAALAAUKcgwIJwBPAQAQAAMKgAf3BQCxAAA1AAQKfy0AAxAACgoAHocGAJgCABAACQqLGocGAJgCAAsACgq6Gg4+APwBAAE1AAQKCgouAAwAthQA.Malakir:BAAANQADCgYIEwAAAA==.Malaxxus:BAAANQADCgEIAQAAAA==.Malendorei:BAABNQAECn8VAAIQAAYKuQhGJQDFAAAQAAYKuQhGJQDFAAAAAA==.Maliceone:BAAANQADCggIJAAAAA==.Mallucavian:BAABNQAECn8WAAMCAAYK7hwqSgCIAQACAAYK7hwqSgCIAQAWAAEKKATwEwAmAAAAAA==.Mamadp:BAABNQAECn8aAAIRAAYK5gdcdQDMAAARAAYK5gdcdQDMAAAAAA==.Manaholy:BAAANQADCggIDQAAAA==.Manek:BAABNQAECn9LAAIOAAoKBxnjMwAQAgAOAAoKBxnjMwAQAgAAAA==.Marraxa:BAABNQAECn8bAAQmAAgK7AYmJgDcAAAmAAgK7AYmJgDcAAAnAAQKYgPLFACmAAAoAAMKBQJ2SAB2AAAAAA==.Maräjade:BAAANQABCgYJBgAAAA==.Max:BAABNQAECn8aAAMBAAkK0hVpbAAZAgABAAgKmBNpbAAZAgAkAAMKlROVQQC9AAAAAA==.',
Me='Melevil:BAAANQAECgcIDwAAAA==.Melinoe:BAAANQADCgIIAgAAAA==.Merlin:BAAANQAECgQIBgAAAA==.Merlise:BAAANQADCgcICgAAAA==.Metalgreymon:BAAANQADCgIIAgAAAA==.',
Mi='Milenad:BAAANQAECgYIDAAAAA==.Milho:BAAANQADCgYIBgABNQAFFAIICAAXAEYiAA==.Milkmeholy:BAAANQADCgcICQAAAA==.Minikey:BAAANQAECgUIBgAAAA==.Mishosuki:BAAANQAECgYIDwABNQADCgQIBAAUAAAAAA==.Misscleo:BAABNQAECn8nAAILAAgKgBCZgwA8AQALAAgKgBCZgwA8AQAAAA==.Mistalar:BAAANQAECgUIBgAAAA==.',
Mn='Mnesarte:BAAANQADCgUIBQAAAA==.',
Mo='Mongoro:BAAANQADCgEIAQAAAA==.Moonkist:BAAANQAECgUIEwAAAA==.Moose:BAABNQAECn8bAAMpAAkKdB1LGQD1AgApAAkKdB1LGQD1AgAbAAEKAABcwgBDAAAAAA==.Mordrandian:BAAANQAECgEIAQAAAA==.',
Mu='Muffindk:BAAANQAECgYICQAAAA==.Muffintop:BAAANQADCggIEQAAAA==.',
['Mó']='Mórningstar:BAAANQADCgIIBAAAAA==.',
Na='Nadless:BAAANQAECgUIBQAAAA==.Naeliria:BAAANQADCggICAAAAA==.Namuss:BAAANQADCgIIAwAAAA==.Narokatha:BAAANQAECgIIAgAAAA==.Navariis:BAAANQADCgQIDQAAAA==.',
Ne='Necropanzer:BAABNQAECn8XAAIRAAoKKx2fDwATAwARAAoKKx2fDwATAwAAAA==.Nelrehim:BAAANQAECgcIDwAAAA==.Nelumbo:BAABNQAFFH8GAAIEAAYKjg5YAwCmAQAEAAYKjg5YAwCmAQABNQAFFAgIBAAUAAAAAA==.',
Ni='Niall:BAAANQAECgEIAQABNQAECgkJMgAOAOsdAA==.Niandilan:BAAANQADCgYICgAAAA==.Niixxi:BAAANQADCgEIAQAAAA==.',
Nm='Nmbrs:BAAANQAECgEIAQABNQAECgcIFgARAAodAA==.',
No='Noirah:BAAANQADCgcIBwAAAA==.Noirheffer:BAABNQAECn8pAAMDAAoKlR+oEACUAgADAAoKlR+oEACUAgANAAUK/xU36QBJAQAAAA==.Nokua:BAABNQAECn8UAAINAAYK8QYbJwHfAAANAAYK8QYbJwHfAAAAAA==.Noodles:BAABNQAECn8rAAIlAAoKVxAbHACsAQAlAAoKVxAbHACsAQAAAA==.',
Nu='Nulannatoo:BAAANQAECgYICAAAAA==.',
Ny='Nyank:BAAANQAECgMIAgABNQAECgkJGAARADwOAA==.Nyleaf:BAAANQADCgUIBwAAAA==.Nyogen:BAAANQAECggJBgAAAA==.Nyxaraa:BAAANQADCgYIEAAAAA==.',
Oc='Octomore:BAABNQAECn8tAAILAAkKFBP8TwC+AQALAAkKFBP8TwC+AQAAAA==.',
Od='Odysseus:BAABNQAECn8gAAIZAAkKvQ+3LADlAQAZAAkKvQ+3LADlAQAAAA==.',
Ol='Olgann:BAAANQAECgUIBgAAAA==.Olguita:BAABNQAECn8XAAISAAgKfxp2WAADAQASAAgKfxp2WAADAQAAAA==.',
Om='Omez:BAAANQAECgYICgABNQAFFAQIBAAUAAAAAA==.Omgowned:BAAANQAECgIIAgABNQAECgcIGAABAMoVAA==.',
On='Onehothealer:BAAANQADCgYIBwAAAA==.',
Oo='Oorua:BAAANQADCggIGQAAAA==.',
Op='Opheliastar:BAABNQAECn8wAAIgAAoKmBY4HwBDAgAgAAoKmBY4HwBDAgAAAA==.',
Or='Ordovis:BAAANQAECgUIDAAAAA==.Orlucicia:BAAANQAECgIIAgAAAA==.Orobas:BAAANQAECggIAgAAAA==.',
Ow='Owltoidz:BAAANQABCgYIBwAAAA==.',
Pa='Pace:BAAANQABCgYICgAAAA==.Pad:BAABNQAECn8YAAIBAAUKRghUngCzAAABAAUKRghUngCzAAAAAA==.Paetyn:BAAANQADCgIIAgAAAA==.Paladerp:BAABNQAECn8eAAMMAAkKphj9KwD6AQAMAAkKphj9KwD6AQANAAEKAABEfQEAAAAAAA==.Palanym:BAABNQAECn8tAAIMAAgKSBdcMADiAQAMAAgKSBdcMADiAQAAAA==.Palidyne:BAAANQAECgUIBgAAAA==.Pallyown:BAABNQAECn8YAAIMAAkKXB4gLgCuAgAMAAkKXB4gLgCuAgAAAA==.Papamidnite:BAAANQADCgMIAwAAAA==.Papichulo:BAAANQADCgcIDQAAAA==.Parox:BAAANQADCgYICAAAAA==.',
Pe='Peluij:BAAANQAECgUICAAAAA==.',
Ph='Phelement:BAABNQAECn8kAAIhAAoKeiLmAwBbAwAhAAoKeiLmAwBbAwAAAA==.Pheta:BAAANQADCggICAAAAA==.Phett:BAABNQAECn8yAAMcAAoKXiCKBADwAgAcAAgKMiOKBADwAgATAAYKvBuQWAB4AQAAAA==.Phonk:BAAANQAECgMIAQABNQAECgoKJAAhAHoiAA==.Phædrea:BAAANQADCggICAAAAA==.',
Pi='Picklës:BAAANQADCgUIBQABNQAECgkJMAACAPchAA==.Piffi:BAAANQAECgEIAwAAAA==.Pikatso:BAAANQADCgMIAwAAAA==.Pimmscup:BAAANQADCggIHAAAAA==.',
Po='Porgoon:BAAANQAECgEIAQAAAA==.',
Pr='Praedthy:BAAANQAFFAIIAgAAAA==.',
Qo='Qohelet:BAAANQAECgQIBQAAAA==.',
Ra='Raatus:BAAANQAECgIIAgABNQAECgkJHQAbAEIiAA==.Raenya:BAAANQAECgIIAgAAAA==.Raikouu:BAABNQAECn8ZAAIBAAcKXwiMzQAvAQABAAcKXwiMzQAvAQAAAA==.Rainydaze:BAAANQAECgMIBQAAAA==.Ramani:BAAANQADCgEIAQAAAA==.Ramasses:BAAANQADCgYICgAAAA==.Ramcharger:BAAANQAECgEIAQABNQAECgkJMgAOAOsdAA==.Ramoreo:BAAANQAECgYIEAABNQAECggIUAAXAGwKAA==.Rashun:BAABNQAECn8rAAMeAAkK/xhpEADgAQAeAAkK/xhpEADgAQAVAAcKiQtKCgAvAQAAAA==.Raviolee:BAAANQAECgEIAQABNQAECgcIGAABAMoVAA==.Rayvin:BAAANQADCggIBwAAAA==.',
Re='Reanatilax:BAAANQABCgMJBQABNQAECggIHAACAGcaAA==.Regnier:BAAANQADCggIEAAAAA==.Relaeh:BAAANQADCgcJDQAAAA==.Resusitate:BAAANQADCgYJBgAAAA==.Rev:BAAANQAECgcICgAAAA==.Rexxy:BAAANQADCgcICwAAAA==.',
Rh='Rhod:BAAANQAECgMIAwABNQAECgoKFQABAIUMAA==.',
Ri='Rikashae:BAAANQADCgYJBgAAAA==.Rissa:BAAANQADCgEIAQAAAA==.Risuku:BAAANQADCgEIAQAAAA==.',
Ro='Roleon:BAAANQADCggIDgAAAA==.Rollforpi:BAAANQAECgMIAwABNQAFFAcIEAAEAPoWAA==.Ropebunnyana:BAAANQAECgIJAwABNQAECgoKLgACAF4iAA==.',
Ru='Ruki:BAAANQAECgUIBQAAAA==.Rumshwizzle:BAAANQADCgQJBAAAAA==.',
Sa='Saltydk:BAABNQAECn8gAAIpAAkKhyClJACuAgApAAkKhyClJACuAgAAAA==.Samiracy:BAABNQAECn8aAAIkAAgKQBhKDAAyAgAkAAgKQBhKDAAyAgAAAA==.Sannrin:BAAANQADCgMIAwAAAA==.Sataro:BAAANQABCggIDwAAAA==.',
Sc='Scappe:BAABNQAECn8dAAIbAAkKQiLlHADJAgAbAAkKQiLlHADJAgAAAA==.Schniel:BAABNQAECn8aAAICAAoKTw7gKwAWAgACAAoKTw7gKwAWAgAAAA==.',
Se='Seefoof:BAAANQADCgIIAgAAAA==.Seitaer:BAAANQADCgQIBAAAAA==.Senbatorii:BAABNQAECn8aAAQEAAgK6hmNQAAiAQAEAAYKlxaNQAAiAQAlAAUKXg6EdQD1AAAJAAIKTArCNgBlAAAAAA==.Sentrosi:BAAANQAECgEIAQAAAA==.Sethrow:BAABNQAECn8YAAMBAAcKyhXxoACUAQABAAYKRxXxoACUAQAkAAEK1ReEbgBCAAAAAA==.Severa:BAABNQAECn8mAAINAAoKLxcIVwCxAQANAAoKLxcIVwCxAQAAAA==.',
Sh='Shadoh:BAAANQAECgIIAgAAAA==.Shamazing:BAAANQADCgEIAQAAAA==.Shamwowsale:BAAANQADCgYIDAAAAA==.Shamwowza:BAABNQAECn85AAIfAAoKuRHYWQADAgAfAAoKuRHYWQADAgAAAA==.Shantifa:BAAANQADCggIDgAAAA==.Shengari:BAAANQADCgIIAgABNQADCgQIBAAUAAAAAA==.Shoshanaa:BAAANQADCgYIEQAAAA==.Shotcallà:BAAANQADCgYIBwABNQADCggICAAUAAAAAA==.Shuna:BAAANQADCgYICQAAAA==.Shyly:BAAANQAECgIIAgAAAA==.',
Si='Siley:BAABNQAECn9FAAIpAAoKDQ/qHwB1AQApAAoKDQ/qHwB1AQAAAA==.',
Sn='Sneakysneak:BAABNQAECn8ZAAInAAgKvRQUBwBOAgAnAAgKvRQUBwBOAgAAAA==.Snüff:BAAANQADCgMIAwAAAA==.',
So='Somavan:BAAANQADCgMIAwABNQAECgkJMgAOAOsdAA==.Somepriest:BAABNQAECn8rAAIgAAkKMyOxBADlAgAgAAkKMyOxBADlAgAAAA==.Sotteria:BAAANQABCgQIBAAAAA==.',
Sp='Spiarmf:BAAANQADCgMIAwAAAA==.Spicyness:BAAANQADCgIIAgAAAA==.Sprockett:BAAANQADCggICAAAAA==.Spycmchaggis:BAAANQAECgMIBAAAAA==.Spëcter:BAAANQAECgYIDgABNQAECgkJLQALABQTAA==.',
Sq='Squishypoo:BAAANQAECgUICgAAAA==.',
St='Starcrush:BAAANQAECgEIAQAAAA==.Staticpower:BAAANQAECggIBAAAAA==.Stiffkitten:BAAANQADCgEJAQAAAA==.Stoked:BAAANQAECgMIAwAAAA==.Studentloans:BAAANQABCgIIAgAAAA==.Sturba:BAAANQABCgIIAgAAAA==.',
Su='Sugrace:BAAANQADCgQIBAAAAA==.Sunaerosinda:BAAANQADCgYIDAAAAA==.Sunow:BAAANQADCgYIFwAAAA==.Superdemonzz:BAABNQAECn8XAAMKAAoKCwklFgCIAAAIAAcKNgn1SAAOAQAKAAcKLQYlFgCIAAABNQAECgoKLgAMALYUAA==.Superpallyz:BAABNQAECn8uAAQMAAoKthQZSwA8AgAMAAoKthQZSwA8AgANAAEKAADMoQE2AAADAAEKAADrfAAgAAAAAA==.',
Sw='Swipeleft:BAABNQAECn87AAIlAAoKHhZQMgBRAgAlAAoKHhZQMgBRAgAAAA==.',
Sy='Sylora:BAAANQADCgIIAgAAAA==.',
Ta='Tabarnak:BAABNQAECn8uAAIhAAoKRx3sAwBaAwAhAAoKRx3sAwBaAwABNQAFFAIIBwAeANMeAA==.Taiynn:BAAANQADCggIFwAAAA==.Tallon:BAACNQAFFH8MAAIiAAUKnxr9AQDwAAAiAAUKnxr9AQDwAAA1AAQKfxsAAiIACQrbINkGAH8CACIACQrbINkGAH8CAAAA.Tarogen:BAAANQAECgUIEwAAAA==.Taszherazade:BAAANQADCgEJAQAAAA==.Taszmyhn:BAAANQADCgMIAwAAAA==.',
Te='Teknique:BAAANQAECgIIAgAAAA==.Tempestclaw:BAAANQADCgUIBQAAAA==.Tendroni:BAABNQAECn8jAAIXAAoKahD4GgDFAQAXAAoKahD4GgDFAQAAAA==.Tervor:BAAANQAECgMIBQAAAA==.Tessadin:BAAANQADCgQIBAAAAA==.',
Th='Thaddaues:BAAANQAECgcIBwABNQAFFAMIBwADAGIFAA==.Thanamoros:BAABNQAECn8yAAIKAAoKuxE4CwAeAgAKAAoKuxE4CwAeAgABNQAECgoKOgASAPkeAA==.Thelephobia:BAAANQABCgYIBwABNQADCgUIBQAUAAAAAA==.Theredwake:BAAANQAECgYICgAAAA==.Theroach:BAAANQAECgIIAwAAAA==.Thgiewerom:BAAANQABCgYIBwAAAA==.Throfin:BAAANQAECgYICgAAAA==.Thwaxi:BAAANQADCgQICAAAAA==.',
Ti='Tinydeath:BAAANQAECgUICgAAAA==.Tiognaska:BAAANQAECgQICAAAAA==.Tirdain:BAAANQADCgQIBAAAAA==.',
To='Toeren:BAACNQAFFH8YAAIOAAUKNB17CAASAQAOAAUKNB17CAASAQA1AAQKfzoAAg4ACgo4I+QVAEQDAA4ACgo4I+QVAEQDAAAA.Tokå:BAAANQADCgIIAgAAAA==.Torage:BAAANQAECgEJAQAAAA==.Tormentah:BAAANQADCgIIAgABNQAECgoKIwATACATAA==.Tormented:BAAANQAECggIDQABNQAECgoKFwARACsdAA==.Torosentado:BAAANQAECgQICAAAAA==.',
Tr='Tregan:BAAANQAECgIIBAAAAA==.Trenity:BAAANQAECgMIBAAAAA==.Triplecanopy:BAAANQAECgEIAQAAAA==.Trollie:BAAANQAECggICAAAAA==.Trumu:BAAANQAECgEIAQAAAA==.Trïsh:BAAANQAECgQIAgABNQAECggIEQAUAAAAAA==.',
Ty='Tyinorin:BAAANQAECgEIAQAAAA==.',
['Tä']='Täryn:BAAANQADCgEIAQAAAA==.',
Ub='Ubee:BAABNQAECn8jAAIIAAgKAA+vGwBRAQAIAAgKAA+vGwBRAQAAAA==.',
Ud='Udderjustice:BAABNQAECn8rAAIDAAcKeg7IMQBSAQADAAcKeg7IMQBSAQAAAA==.',
Ug='Uglyelf:BAABNQAECn8hAAIOAAgKPwlwdgBIAQAOAAgKPwlwdgBIAQAAAA==.',
Ul='Ultimakitty:BAAANQAECgQIAwAAAA==.',
Un='Uncertainty:BAAANQADCgUIBQABNQAECgUIBQAUAAAAAA==.Unchanged:BAAANQAECgIIAgAAAA==.',
Va='Vaeldrin:BAAANQADCgUIBQAAAA==.Vanhellsings:BAAANQAECgEIAQAAAA==.Vantrix:BAABNQAECn9AAAMlAAoK2RjMHQDbAgAlAAoK2RjMHQDbAgAEAAYKohBWOABbAQABNQAECgoKOgASAPkeAA==.Varabo:BAAANQAECgUIBwAAAA==.Varolina:BAAANQADCggIJQAAAA==.',
Ve='Velmara:BAAANQABCgMIAwAAAA==.Velthala:BAABNQAECn8gAAITAAkK0hiSNQD9AQATAAkK0hiSNQD9AQAAAA==.Velyra:BAAANQAECgUICgAAAA==.',
Vi='Vitner:BAAANQADCgMIBAABNQAECgkJGAABAK0XAA==.Vivieneaux:BAAANQABCgUICAAAAA==.Vixsen:BAAANQABCgcIDQAAAA==.',
Vl='Vladdawngard:BAAANQAECggICAAAAA==.',
Vo='Voidcorpse:BAAANQADCgEIAQAAAA==.Voidmama:BAAANQADCgYIBgAAAA==.Voidryn:BAAANQABCgcIEQAAAA==.Voidshifter:BAAANQADCgUIBQAAAA==.Vosaleana:BAAANQAECgYIDgAAAA==.',
Vr='Vraak:BAACNQAFFH8QAAIEAAcK+hZRBADpAQAEAAcK+hZRBADpAQA1AAQKfy0AAwQACgplJFMEAEsDAAQACgplJFMEAEsDACUAAgrrHGeHALUAAAAA.',
Vu='Vulcus:BAAANQAECgUIBgABNQAFFAcIEAAEAPoWAA==.',
Vy='Vyndarien:BAAANQABCgcICgAAAA==.',
Wa='Wa:BAABNQAECn8XAAMDAAYKbhbkMgBLAQADAAYKbhbkMgBLAQANAAEKAABouAEsAAAAAA==.Walimagus:BAAANQAECgMIAgAAAA==.Wayofthemist:BAAANQABCgIIAgAAAA==.',
Wc='Wcreator:BAAANQAECgIIAgAAAA==.',
Wh='Wheeljack:BAABNQAECn8cAAMEAAkKYBNgHACBAQAEAAkKYBNgHACBAQAlAAEKAAAnuwAlAAABNQAECgoKHAAfAC0VAA==.',
Wi='Widowcancer:BAAANQADCgIJAgAAAA==.Will:BAACNQAFFH8NAAINAAQKNCO0BQAyAQANAAQKNCO0BQAyAQA1AAQKfzgAAg0ACgpvJkcBAIcDAA0ACgpvJkcBAIcDAAAA.',
Wo='Womdalie:BAAANQADCggIGwAAAA==.',
Wy='Wyckedpally:BAAANQAECgUIEgABNQAECgYIFAANAPEGAA==.',
Xa='Xanthös:BAAANQAFFAIIAgABNQAFFAcIEAAEAPoWAA==.',
Xe='Xemnastrasza:BAABNQAECn8rAAMFAAoKLBRsCAAQAgAFAAkKaBJsCAAQAgAGAAgK4BU0FAALAgABNQAECgoKOgASAPkeAA==.Xenonne:BAAANQAECgQIBAABNQAFFAQIBwAMADYNAA==.',
Xo='Xolither:BAABNQAECn8cAAICAAgKZxplXwADAgACAAgKZxplXwADAgAAAA==.',
Yo='Yorgo:BAAANQADCggICAAAAA==.Yourwifesbf:BAABNQAECn84AAIaAAoK5xXICADEAQAaAAoK5xXICADEAQAAAA==.Yourwivesbf:BAAANQADCggICQAAAA==.',
Yu='Yuura:BAAANQAECgMIBAAAAA==.',
Za='Zachdemon:BAABNQAECn8sAAIKAAkK6xOZDgDPAQAKAAkK6xOZDgDPAQAAAA==.Zarulu:BAAANQAECgUIBAABNQAECgoKOgASAPkeAA==.Zazoo:BAAANQABCgEIAQAAAA==.',
Ze='Zeeblax:BAAANQADCggICAAAAA==.Zenyátta:BAAANQAECgUIEAAAAA==.Zephymoo:BAABNQAECn9KAAMJAAoKzxv4BABKAgAJAAkKtRz4BABKAgAlAAQKhhZObwANAQAAAA==.Zershadowi:BAAANQAECgEIAQAAAA==.Zertfelgard:BAAANQABCgcICgAAAA==.Zeyana:BAABNQAECn8YAAMKAAkKBRE+DAAVAQAKAAkKBRE+DAAVAQAXAAYKtQQeaADYAAABNQAECgoKMAAOAP4cAA==.',
Zh='Zhengshi:BAABNQAECn8bAAIVAAgKsAk/DgDbAAAVAAgKsAk/DgDbAAAAAA==.',
Zi='Zinsatra:BAAANQADCgEIAQAAAA==.',
Zk='Zkarlyse:BAAANQAECgcIDQAAAA==.',
Zo='Zoose:BAABNQAECn8fAAQTAAgKXRcaigADAgATAAgKXhQaigADAgAaAAQK6RnrKQDrAAAcAAEKhg6SMwA0AAAAAA==.Zosahe:BAABNQAECn8kAAMeAAkK8Q/dFACdAQAeAAkK8Q/dFACdAQAdAAcK3AcxKwAVAQAAAA==.Zoser:BAABNQAECn8fAAIeAAgKpiPOEQDQAgAeAAgKpiPOEQDQAgAAAA==.',
Zs='Zsófia:BAAANQADCgcIBwAAAA==.',
Zu='Zuckuss:BAAANQAECgEIAQAAAA==.',
Zy='Zymri:BAAANQADCgUICQABNQAECgUIEQAUAAAAAA==.',
['Æl']='Ælthan:BAAANQAECgEIAQAAAA==.',
['Ér']='Érubus:BAAANQAECgUICAAAAA==.',
['Ôr']='Ôrdra:BAAANQAECggICAAAAA==.',
['Öl']='Ölivê:BAABNQAECn8WAAIbAAcKDQpvcAA0AQAbAAcKDQpvcAA0AQAAAA==.',
['ßu']='ßugs:BAABNQAECn8nAAIOAAgK7ReMVACfAQAOAAgK7ReMVACfAQAAAA==.',
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
