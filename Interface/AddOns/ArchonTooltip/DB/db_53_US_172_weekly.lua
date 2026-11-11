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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Warrior-Arms','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Mage-Arcane','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Unknown-Unknown','Druid-Balance','Druid-Restoration','Paladin-Holy','Druid-Guardian','Druid-Feral','Rogue-Subtlety','Evoker-Preservation','Shaman-Enhancement','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warrior-Fury','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Hunter-Marksmanship','Priest-Holy','DemonHunter-Vengeance','Monk-Brewmaster','Monk-Windwalker','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival','Rogue-Outlaw','Priest-Discipline','Monk-Mistweaver',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aanien:BAAANQAECgEIAwAAAA==.',
Ac='Acedk:BAABNQAECn8hAAMBAAkKoiEyGgDvAgABAAkKPCAyGgDvAgACAAUKdiAWRACyAQAAAA==.Aceslam:BAABNQAECn8YAAIDAAgKuiFKMwDzAgADAAgKuiFKMwDzAgABNQAECgkJIQABAKIhAA==.',
Ad='Adrador:BAABNQAECn9BAAMEAAoKWB6jCQADAwAEAAkKLx+jCQADAwAFAAcKahZh0QAfAQAAAA==.Adrenaline:BAACNQAFFH8VAAIGAAYKnB4ZAQBkAQAGAAYKnB4ZAQBkAQA1AAQKf0YAAgYACgrpJHoCAI4DAAYACgrpJHoCAI4DAAAA.',
Ae='Aelik:BAABNQAECn8qAAIBAAgKxxXLaABuAQABAAgKxxXLaABuAQAAAA==.Aeolian:BAAANQADCgYIDgAAAA==.Aeru:BAAANQADCgQIBAAAAA==.',
Af='Afk:BAAANQAECgMIAwAAAA==.',
Aj='Ajaila:BAAANQADCgQIBAAAAA==.',
Ak='Akueria:BAAANQADCgcIBwAAAA==.',
Al='Alayssa:BAABNQAECn8oAAIHAAoKzhuQMABzAgAHAAoKzhuQMABzAgAAAA==.Alda:BAAANQADCgYIFgAAAA==.Alemental:BAABNQAECn8kAAIIAAoKqgx7SACcAQAIAAoKqgx7SACcAQAAAA==.Aleska:BAABNQAECn8XAAQJAAgKWhR4DQDdAAAKAAcKVwyZ6AD4AAAJAAUKTxZ4DQDdAAALAAEKXwzsLQA6AAAAAA==.Allarius:BAAANQAECgUIBAAAAA==.Allevist:BAAANQAECgMIAwABNQAECggILAAHAGIGAA==.Alo:BAABNQAECn85AAIMAAoKvxbGPgBlAgAMAAoKvxbGPgBlAgABNQAECgEJAQANAAAAAA==.',
Am='Amilee:BAAANQAECgIIAQAAAA==.Amoondai:BAAANQADCgYICAAAAA==.Amoondrin:BAABNQAECn8oAAMOAAoKZQdJPQAiAQAOAAoKZQdJPQAiAQAPAAEK3wPDewAnAAAAAA==.',
An='Analiya:BAAANQADCgQJBQAAAA==.Anatyr:BAAANQAECgMIAgAAAA==.Andoria:BAAANQAECgEIAQAAAA==.',
Ar='Aramathis:BAAANQAECgUIBgAAAA==.Araviin:BAAANQAECgUIDgAAAA==.Arbor:BAAANQAECgQICQAAAA==.Arcillias:BAABNQAECn8bAAMQAAkK0xXhOgAaAgAQAAkK0xXhOgAaAgAFAAEKDALGmgEnAAABNQAECgYIDAANAAAAAA==.Arilas:BAAANQAECgQICgABNQAECgYIDAANAAAAAA==.Arkanist:BAABNQAECn8sAAIHAAgKYgZZywAAAQAHAAgKYgZZywAAAQAAAA==.Arthia:BAAANQADCgYICQAAAA==.Arvidpally:BAABNQAECn8VAAIFAAcKiwdN+gDdAAAFAAcKiwdN+gDdAAAAAA==.',
As='Ashesius:BAABNQAECn9WAAQJAAoKAB2GBADhAgAJAAoKAB2GBADhAgAKAAMKYQmcHgGHAAALAAIKaxyHHgCHAAAAAA==.Ashmehameha:BAAANQAECgQIBgABNQAECgYIDQANAAAAAA==.Ashstabber:BAAANQAECgQIBgABNQAECgYIDQANAAAAAA==.',
At='Atredes:BAAANQAECgYIEgAAAA==.',
Au='Auspex:BAABNQAECn8qAAIRAAoKjwnpKQAkAQARAAoKjwnpKQAkAQAAAA==.',
Av='Avaryn:BAABNQAECn8aAAIPAAkKiBbVHwAtAgAPAAkKiBbVHwAtAgAAAA==.',
Ax='Aximlii:BAAANQADCgUICQAAAA==.',
Ba='Babavoss:BAAANQAECggIEAAAAA==.Babs:BAAANQADCggIDgAAAA==.Badaracka:BAACNQAFFH8LAAISAAYKPw0wAQCoAQASAAYKPw0wAQCoAQA1AAQKf0gABBIACgppJEUCAC4DABIACgppJEUCAC4DABEACAojHREVANYBAA4ABgpqFJY2AEYBAAAA.Badash:BAAANQAECgQIDAABNQAECgYIDQANAAAAAA==.Bahamuth:BAABNQAECn9IAAIFAAoKTxyMMgCLAgAFAAoKTxyMMgCLAgAAAA==.Bahamutsrage:BAAANQADCggIDgABNQAECggIGQAJAAQIAA==.Balder:BAAANQAECggIGQABNQAFFAUIDwANAAAAAQ==.Bandage:BAAANQAECgYIBgABNQAECgoKMgATAKEVAA==.Barbattos:BAACNQAFFH8VAAIUAAYKPhkhCACgAQAUAAYKPhkhCACgAQA1AAQKfzgAAhQACgroIxUGAEgDABQACgroIxUGAEgDAAAA.Batmon:BAAANQAECgUIBQAAAA==.',
Bd='Bdyrk:BAABNQAECn8ZAAIVAAgKDw9pFwCCAQAVAAgKDw9pFwCCAQABNQAFFAYICwASAD8NAA==.',
Be='Bealzeboss:BAAANQADCgcICQAAAA==.Bexley:BAABNQAECn9EAAIEAAoKjiBGBgDmAgAEAAoKjiBGBgDmAgAAAA==.',
Bi='Biggerbunny:BAABNQAECn8hAAIWAAoKkhLqJQD/AQAWAAoKkhLqJQD/AQAAAA==.Biglarry:BAAANQADCgMJBQAAAA==.Biianca:BAAANQADCgUICQAAAA==.',
Bl='Blacklok:BAAANQAECgIIBwABNQAECgoKOgAXANMlAA==.Blanne:BAAANQABCgIIAgAAAA==.Blargle:BAAANQAECgUIEQAAAA==.Blegh:BAACNQAFFH8HAAIFAAMKARnHFQABAQAFAAMKARnHFQABAQA1AAQKfyQAAgUACgoNILwvAAoDAAUACgoNILwvAAoDAAE1AAUUBAgHABgAYQoA.Blessyaheart:BAABNQAECn8eAAIQAAoKXRA/NwArAgAQAAoKXRA/NwArAgAAAA==.Blincyto:BAAANQAECgEIAQAAAA==.Blinx:BAAANQAECgEIAgAAAA==.Bloodrake:BAABNQAECn9IAAIYAAoKGhgoQwChAgAYAAoKGhgoQwChAgAAAA==.Blueray:BAAANQADCgYIBgAAAA==.',
Bm='Bman:BAABNQAECn8gAAIDAAcKlhoBbQCkAQADAAcKlhoBbQCkAQAAAA==.',
Br='Braneour:BAABNQAECn83AAMEAAoKShJzJwCjAQAEAAoKShJzJwCjAQAQAAYK1QcEswAYAQAAAA==.Bravisimo:BAAANQAECgIIAgAAAA==.Browel:BAABNQAECn8nAAIKAAoKdxhkTgBpAgAKAAoKdxhkTgBpAgAAAA==.',
Bu='Bubblfett:BAAANQAECgcICwAAAA==.Bumm:BAAANQAECgMIBAAAAA==.',
Bz='Bzspy:BAABNQAECn8zAAMDAAoKxBknYwBlAgADAAoKxBknYwBlAgAZAAIK9ApMKwBZAAAAAA==.',
['Bë']='Bëar:BAAANQAECgEIAgAAAA==.',
Ca='Cabooselul:BAAANQAECgYIDQAAAA==.Calyptus:BAABNQAECn8yAAMJAAkKew8xBQCUAQAJAAkK6w4xBQCUAQAKAAMK1gmq1ACXAAAAAA==.Capylaura:BAAANQAECgMIBgAAAA==.Caratine:BAAANQADCgcIDQAAAA==.Cassandrah:BAABNQAECn9KAAIHAAoK1x+VKgCJAgAHAAoK1x+VKgCJAgAAAA==.',
Ce='Celìa:BAABNQAECn8XAAIYAAoKPgXzrQA7AQAYAAoKPgXzrQA7AQAAAA==.',
Ch='Chillymage:BAAANQADCgcIBwAAAA==.Chpchop:BAAANQABCggIEQAAAA==.Christy:BAAANQADCgYIGwAAAA==.Chugg:BAABNQAECn8tAAIMAAgKWAZpjAD7AAAMAAgKWAZpjAD7AAAAAA==.',
Ci='Ciaphus:BAABNQAECn82AAQFAAoKqxCbtwCvAQAFAAgK6A+btwCvAQAQAAoKOQolWwCXAQAEAAcKNgxENgA1AQAAAA==.Cinnamonster:BAABNQAECn8aAAMJAAkKKgu8CwDxAAAKAAYKJAs/5gD8AAAJAAgK4gi8CwDxAAAAAA==.',
Cl='Clogs:BAAANQAECgUIBwAAAA==.',
Co='Coffeedemon:BAAANQAECgQIBgAAAA==.Coldslappins:BAAANQAECgYICQABNQAECgoKNwAEAEoSAA==.Convalescent:BAAANQADCgYIBgAAAA==.Coragrr:BAAANQAECgIIBgAAAA==.',
Cr='Cracklepants:BAACNQAFFH8KAAIIAAUKaAlMEABoAQAIAAUKaAlMEABoAQA1AAQKf0YAAggACgp+IjQXAD0DAAgACgp+IjQXAD0DAAE1AAUUBggPAA4AwhEA.Crashout:BAAANQAECggIEwAAAA==.',
Cu='Curtastrophe:BAABNQAECn9EAAIaAAoK2yIpAQCQAwAaAAoK2yIpAQCQAwAAAA==.Curticus:BAAANQADCgYIBgAAAA==.',
Da='Daelanos:BAABNQAECn8ZAAIDAAgKIAtbrwCmAQADAAgKIAtbrwCmAQAAAA==.Dallas:BAAANQAECggICgAAAA==.Danorman:BAAANQADCgQIBAABNQAECgIIBAANAAAAAA==.',
De='Deathisreal:BAAANQADCgEIAgABNQAECgQIBQANAAAAAA==.Deathoof:BAABNQAECn8wAAQBAAkKWRbyGQAFAgABAAkKRxbyGQAFAgAbAAQKJRLKlwCuAAACAAEKGgWKtAArAAABNQAECgoKGQARAMMaAA==.Demonblaze:BAAANQAECgIIBgAAAA==.Demonilla:BAABNQAECn8sAAIcAAoKiBqdDgBfAgAcAAoKiBqdDgBfAgAAAA==.Destro:BAABNQAECn87AAIKAAoKNg0kUgDKAQAKAAoKNg0kUgDKAQAAAA==.',
Di='Dilaudyd:BAAANQAECgMIAgAAAA==.Disbeleaf:BAAANQAECgcIEQAAAA==.Dishu:BAAANQABCgQIBAAAAA==.Dispel:BAAANQADCgYIBgAAAA==.Disputatious:BAAANQAECgEIAQAAAA==.',
Dn='Dntblink:BAAANQADCgUIBQAAAA==.',
Do='Dogaz:BAAANQADCgYIGwAAAA==.Dogsoldier:BAAANQADCgQIBAAAAA==.Donori:BAAANQAECgYIDwAAAA==.Doomphoenix:BAAANQAECgQIAgAAAA==.',
Dr='Dragonias:BAABNQAECn8aAAIdAAcKQAfBLwDeAAAdAAcKQAfBLwDeAAAAAA==.Drakthorn:BAAANQAECgEIAQAAAA==.Drinny:BAABNQAECn8xAAIeAAoKfgX+agCEAQAeAAoKfgX+agCEAQAAAA==.Dripington:BAACNQAFFH8GAAICAAUKFxToDQDXAAACAAUKFxToDQDXAAA1AAQKfysAAwIACgqZIZUUAOgCAAIACgqZIZUUAOgCAAEAAQoAAGngADMAAAAA.',
Ea='Earthangel:BAABNQAECn8kAAIeAAcK9wjWjQAYAQAeAAcK9wjWjQAYAQAAAA==.',
Ef='Efon:BAAANQADCgUIBQABNQAECgoKKAAHAM4bAA==.',
Ei='Eine:BAABNQAECn9AAAIYAAoK4RGGTAAiAgAYAAoK4RGGTAAiAgAAAA==.',
El='Eldergreen:BAABNQAECn8VAAMPAAcKxgk9RAALAQAPAAYK3gk9RAALAQAOAAQK7QQujQChAAAAAA==.Elemanda:BAAANQAECgMIAwABNQAECgcIIQAEABAOAA==.Elfwine:BAABNQAECn8kAAIWAAcKMwmlLQACAQAWAAcKMwmlLQACAQAAAA==.Elindria:BAABNQAECn86AAMXAAoK0yXCBACnAwAXAAoKiyXCBACnAwAfAAUK/iS+DwA0AQAAAA==.Elissa:BAAANQAECgEIAwAAAA==.Elminstir:BAABNQAECn8uAAIaAAoK1xb1CgAWAgAaAAoK1xb1CgAWAgAAAA==.Eluzhion:BAAANQADCgUICAAAAA==.Elysian:BAAANQAECgUICwAAAA==.',
Er='Erisa:BAAANQADCgMIAwAAAA==.Erizhal:BAAANQABCgIIAgAAAA==.Eruptyon:BAAANQAECgEIAQABNQAECgoKLwAHAJYgAA==.',
Es='Esabel:BAAANQAECgcIDwABNQAECgoKKAAHAM4bAA==.',
Ev='Eviae:BAABNQAECn8kAAIbAAcKwATAXwC4AAAbAAcKwATAXwC4AAAAAA==.Evillure:BAAANQAECgYICwAAAA==.',
Ex='Explanation:BAAANQADCgQIBAAAAA==.',
Fa='Falan:BAAANQAECgEIAQAAAA==.Farfins:BAAANQAECgEIAQAAAA==.',
Fe='Fedor:BAAANQAECggICAAAAA==.Feår:BAABNQAECn8eAAMKAAkKOhDkawCAAQAKAAcKPRDkawCAAQAJAAIKMBAsWwBvAAAAAA==.',
Fi='Finley:BAAANQADCgQIBAAAAA==.Fixation:BAAANQABCgIIAgAAAA==.',
Fl='Flane:BAACNQAFFH8WAAIgAAcKABm+AQD2AQAgAAcKABm+AQD2AQA1AAQKfzYAAyAACgq2ItQBAAsDACAACgq2ItQBAAsDACEAAQoAAEdkAE4AAAAA.Flexdruid:BAAANQAECgUIBgAAAA==.',
Fr='Fragil:BAABNQAECn86AAMiAAoK0iA2FwDCAgAiAAoK7xs2FwDCAgATAAgKDCDCKgBDAgAAAA==.Frostmane:BAABNQAECn8ZAAMBAAkK6hRqFgApAgABAAkKLRRqFgApAgAbAAUKLQ9YXgC9AAABNQAFFAYIDwAOAMIRAA==.Frostssiah:BAAANQAECgUICQAAAA==.',
Ga='Galena:BAABNQAECn8cAAIPAAgKhRIsJgCiAQAPAAgKhRIsJgCiAQAAAA==.Galian:BAAANQADCggIEgAAAA==.Ganonn:BAAANQAECgQICgABNQAECgcIEQANAAAAAA==.',
Ge='Geshtal:BAABNQAECn8YAAMXAAgKAwxPOwA6AQAXAAgKAwxPOwA6AQAfAAEKAAAcNAAsAAAAAA==.',
Gi='Girion:BAABNQAECn8hAAIEAAcKEA7ALwDqAAAEAAcKEA7ALwDqAAAAAA==.',
Gl='Glaiven:BAECNQAFFH8RAAIXAAYKNBGNCQAgAQAXAAYKNBGNCQAgAQA1AAQKfzYAAxcACgotIpAOADEDABcACgotIpAOADEDABwABwoxFzoxALcBAAAA.Glaiveparty:BAAANQAECgEIAQABNQAECgoKHgAQAF0QAA==.Glyr:BAAANQAECgEJAQAAAA==.',
Gn='Gnofear:BAAANQABCggIEwABNQAECgUIEAANAAAAAA==.Gnora:BAAANQADCggIEwAAAA==.Gnova:BAAANQADCgUIBgAAAA==.',
Go='Gorgrin:BAABNQAECn8VAAILAAgKCAkBDwAuAQALAAgKCAkBDwAuAQAAAA==.',
Gr='Groguu:BAAANQAECgQIBQABNQAECgkJIQABAKIhAA==.',
Ha='Harkanum:BAABNQAECn8sAAMjAAgKSAq+HACBAQAjAAgKSAq+HACBAQAUAAgK6QQ1KwBSAQAAAA==.Harvester:BAABNQAECn8ZAAMPAAUKXwkcSgC/AAAPAAUKXwkcSgC/AAAOAAUKNww6XwCVAAAAAA==.',
He='Healinturds:BAAANQADCgEIAQAAAA==.Healsurazz:BAAANQADCgQIBAAAAA==.Helloagain:BAABNQAECn8WAAIHAAkK3RucfgCBAgAHAAkK3RucfgCBAgAAAA==.',
Hi='Hidethetotem:BAABNQAECn8bAAIMAAgKvxCHZAByAQAMAAgKvxCHZAByAQAAAA==.Hiimdeath:BAAANQADCgQIBAABNQAECgQIBQANAAAAAA==.Hikari:BAACNQAFFH8MAAIFAAYKJwzvFgDGAAAFAAYKJwzvFgDGAAA1AAQKfzIAAgUACgrWHZ43AHgCAAUACgrWHZ43AHgCAAAA.Hiown:BAAANQAECgEIAQAAAA==.',
Ho='Holyrebel:BAAANQAECgQIBQAAAA==.Holyspike:BAABNQAECn8cAAMMAAgKqhKnUwCtAQAMAAgKqhKnUwCtAQAIAAEKAABDIAEAAAAAAA==.Homerr:BAABNQAECn8ZAAIYAAcKcwv2tQArAQAYAAcKcwv2tQArAQAAAA==.Honiahaka:BAABNQAECn9QAAIYAAoKSRI7RwAvAgAYAAoKSRI7RwAvAgAAAA==.Hotsdog:BAAANQADCgIIAgAAAA==.Hottcakes:BAABNQAECn9KAAIHAAoKgiElDwCWAwAHAAoKgiElDwCWAwABNQAFFAkJGwAKABgRAA==.',
Hu='Humanoidlite:BAAANQAFFAEIAgABNQAFFAUICgADAEYIAA==.Humanoidlock:BAAANQADCgcIDAABNQAFFAUICgADAEYIAA==.Humanoidwar:BAACNQAFFH8KAAMDAAUKRghiFAD2AAADAAUKRghiFAD2AAAGAAEKoAP3CgAtAAA1AAQKfzMAAwMACgoEHy40APACAAMACgoEHy40APACAAYABQr+D50pAO4AAAAA.',
['Hà']='Hàvòc:BAAANQADCgQIBAAAAA==.',
['Hö']='Hölyçow:BAAANQADCgUIBQAAAA==.',
Ic='Icedtea:BAAANQAECgQIBAAAAA==.',
In='Inoru:BAAANQAECgUIDwAAAA==.Intgrumblyeo:BAAANQAECggICgAAAA==.',
Ip='Ipseity:BAAANQABCgMIAwAAAA==.',
Ir='Irmaline:BAABNQAECn8cAAIeAAgKbw7RbQB7AQAeAAgKbw7RbQB7AQAAAA==.',
It='Ithurtshuh:BAAANQAECgIIBQABNQAECgQIBQANAAAAAA==.',
Ja='Jabbawockie:BAABNQAECn8XAAIXAAgKFwhqYwDsAAAXAAgKFwhqYwDsAAAAAA==.Jackcat:BAAANQADCgQIAwAAAA==.Jackyl:BAAANQABCgYIBgAAAA==.',
Je='Jeffee:BAABNQAECn8jAAICAAkKsxgPKQBQAgACAAkKsxgPKQBQAgAAAA==.Jennifleur:BAAANQAECgEIAQAAAA==.Jequalsjosh:BAABNQAECn8eAAIiAAkKfBKNHwAlAQAiAAkKfBKNHwAlAQAAAA==.Jerk:BAACNQAFFH8XAAIcAAcKYB++BADxAQAcAAcKYB++BADxAQA1AAQKfz8AAhwACgrHJTgEAJIDABwACgrHJTgEAJIDAAAA.Jesper:BAABNQAECn9WAAIMAAoKlSKeCACBAwAMAAoKlSKeCACBAwAAAA==.Jetz:BAAANQAECgQIDAAAAA==.Jetzul:BAAANQAECgUICAAAAA==.Jezelle:BAAANQADCggICAAAAA==.',
Ji='Jilara:BAABNQAECn8ZAAIFAAYKFQht/ADaAAAFAAYKFQht/ADaAAAAAA==.Jimmyjim:BAABNQAECn8WAAIaAAgKIwmZFQAkAQAaAAgKIwmZFQAkAQAAAA==.',
Jo='Joink:BAAANQADCgYICQAAAA==.',
Jp='Jpepps:BAABNQAECn8mAAMKAAgK2A0tigDNAQAKAAgK2A0tigDNAQAJAAMKcAThXgBoAAAAAA==.',
Jr='Jrose:BAAANQADCggIGQAAAA==.',
Ka='Kagozo:BAEANQAECgEIAgABNQAECgIIAgANAAAAAA==.Kahlanrahl:BAAANQADCgIIAgAAAA==.Kaiatra:BAABNQAECn8cAAICAAgKEhhhPADcAQACAAgKEhhhPADcAQAAAA==.Kalamor:BAAANQAECgUIBQAAAA==.Kaliguala:BAAANQADCgUIBwAAAA==.Kaloran:BAAANQAECgcIEAAAAA==.Katalaystar:BAAANQAECgEIAQABNQAECgoKTQAPAHoiAA==.Katalegdh:BAAANQAECgcIEQAAAA==.Kative:BAAANQAECgEIAQAAAA==.Kaìju:BAABNQAECn8mAAIFAAoK2R9QJwC4AgAFAAoK2R9QJwC4AgAAAA==.',
Ke='Kellytgt:BAAANQAECggIDAAAAA==.',
Kh='Khaelyn:BAAANQADCgQIBQAAAA==.Khai:BAABNQAECn8WAAIFAAgKyA1X4ABbAQAFAAgKyA1X4ABbAQAAAA==.',
Ki='Kiae:BAAANQADCgYJBwAAAA==.Kidneyspears:BAAANQADCgYICAAAAA==.Kilaura:BAAANQADCgUIBQAAAA==.Kilmandaros:BAAANQAECgUICwAAAA==.Kimblee:BAAANQADCgQIBAAAAA==.',
Ko='Korbix:BAAANQABCgUIBAABNQAECgUIEAANAAAAAA==.',
Kr='Kraxxas:BAAANQAECggIDgAAAA==.Kronmon:BAAANQADCgQIBAAAAA==.',
Ku='Kudria:BAABNQAECn8uAAIYAAoK4xFmWgD9AQAYAAoK4xFmWgD9AQAAAA==.Kunei:BAAANQABCgYICQABNQAECgIIBAANAAAAAA==.Kurdran:BAAANQAECgEIBAAAAA==.Kuroyukihime:BAABNQAECn8vAAIaAAoKHBtNBgCfAgAaAAoKHBtNBgCfAgAAAA==.',
Ky='Kyarina:BAAANQAECgEIAQABNQAECgQIEQANAAAAAA==.Kylas:BAAANQAECgIIAQAAAA==.Kynae:BAAANQAECgQIEQAAAA==.Kyross:BAAANQABCgIIAgAAAA==.',
['Ká']='Kárma:BAAANQADCgYICwABNQAECgkJHgAKADoQAA==.',
La='Landoridan:BAAANQAECggICAAAAA==.Lashela:BAABNQAECn8rAAIdAAkKFQfDIQBJAQAdAAkKFQfDIQBJAQAAAA==.Laughter:BAABNQAECn8UAAIGAAcKuAV+JQC5AAAGAAcKuAV+JQC5AAAAAA==.Lavamylash:BAAANQAECgcIEQAAAA==.Laylla:BAAANQAECgQICwAAAA==.Lazulie:BAAANQAECgYICgAAAA==.',
Le='Lefnedrav:BAAANQADCgYICgABNQAECgoKMgAgAHAaAA==.Lektrik:BAAANQAECgUIDQAAAA==.Lenexa:BAAANQADCgUICQAAAA==.Lexapayne:BAAANQADCgEIAQABNQAECgoKMAAYAPkTAA==.Leyra:BAABNQAECn8oAAIdAAoK5xpCDgBLAgAdAAoK5xpCDgBLAgABNQAECgoKOgAXANMlAA==.',
Li='Lighthammer:BAAANQADCggIDgAAAA==.Lightmessiah:BAABNQAECn83AAQFAAoKCBysfgAsAgAFAAgKyBqsfgAsAgAQAAgKFBYpOwAZAgAEAAIKgwb7awAgAAAAAA==.Lightnig:BAAANQADCgUIBQAAAA==.Lilyvain:BAAANQAECgEIAwAAAA==.Lireal:BAABNQAECn8gAAMQAAoKKx7MIwDcAgAQAAkKNB3MIwDcAgAFAAEKKAxajwEwAAAAAA==.Livnod:BAAANQAECgQIAwAAAA==.',
Lo='Logdiir:BAAANQAECgMIAwAAAA==.Lonon:BAABNQAECn8XAAIIAAgKJA5tcwDHAQAIAAgKJA5tcwDHAQAAAA==.Loosescrew:BAAANQADCgQIBQAAAA==.Lorine:BAABNQAECn9CAAIEAAoKoRu6CwBkAgAEAAoKoRu6CwBkAgAAAA==.',
Lu='Lunara:BAAANQADCgYIDAAAAA==.',
Ly='Lynnethe:BAAANQAECgYIDgAAAA==.Lyyse:BAAANQADCgIIAgAAAA==.',
Ma='Malkiel:BAAANQAECgQIEAAAAA==.Mantang:BAAANQAECgEIAQAAAA==.Mastakillah:BAAANQADCgQICAABNQAECgUIEgANAAAAAA==.Maxamus:BAAANQAECgEIAgAAAA==.',
Me='Meeseeks:BAAANQAECgcIDgAAAA==.Merckel:BAABNQAECn84AAIcAAoKJB1READvAgAcAAoKJB1READvAgAAAA==.Messorom:BAAANQADCgEIAQAAAA==.',
Mi='Michello:BAABNQAECn8cAAIYAAgK9A+fhgCPAQAYAAgK9A+fhgCPAQAAAA==.Mightytot:BAAANQAECgUIBQAAAA==.Millia:BAABNQAECn8vAAMHAAoKliAuWwD0AQAHAAgKZiEuWwD0AQAaAAIKJh6rKQCqAAAAAA==.Mint:BAABNQAECn8fAAIQAAkKGBW5QgBaAgAQAAkKGBW5QgBaAgAAAA==.Mintberrytea:BAAANQAECgQJBwABNQAECgkJHwAQABgVAA==.Misstress:BAABNQAECn8tAAMOAAoKLgyRLgB5AQAOAAoKxguRLgB5AQARAAQK0gvLWABXAAAAAA==.',
Mo='Moistweaver:BAAANQADCgYIBgAAAA==.Monkussy:BAAANQADCgUIBQAAAA==.Monoxide:BAAANQADCgUIBQABNQAECgkJFQAXAGMRAA==.Mooncloud:BAAANQAECgMIAgAAAA==.Moonhunt:BAAANQAECgQIBgAAAA==.Morkleb:BAAANQAECgYIEQAAAA==.Morrag:BAABNQAECn8xAAMKAAkK+AngdgBjAQAKAAkK+AngdgBjAQAJAAEKAABVPwAAAAAAAA==.Morrtisha:BAAANQAECgcIDAAAAA==.',
Mu='Munchkins:BAAANQAECgEIAQAAAA==.Munden:BAAANQAECgEIAQABNQAECgQIEAANAAAAAA==.',
My='Myxie:BAABNQAECn8xAAIMAAkKqBd9PQAJAgAMAAkKqBd9PQAJAgAAAA==.',
['Mí']='Mísfìt:BAABNQAECn9EAAIMAAoKXx8lEAAqAwAMAAoKXx8lEAAqAwAAAA==.',
Na='Nakaito:BAABNQAECn8UAAIKAAgK4Ae0vwBMAQAKAAgK4Ae0vwBMAQABNQAECgoKOwAiAM4TAA==.Narcoleptic:BAACNQAFFH8FAAIUAAQKeBFQEQCdAAAUAAQKeBFQEQCdAAA1AAQKf1AABBQACgrhFyYJAJsCABQACgrgFyYJAJsCACMABQrNC5gmAAEBACQABgraERcPAN8AAAAA.Nashty:BAAANQAECgEIAgAAAA==.Naturaljuice:BAAANQAECggIEwABNQAFFAkJGwAKABgRAA==.Naturebreakr:BAABNQAECn8bAAIOAAkKwhK+PQAKAgAOAAkKwhK+PQAKAgAAAA==.',
Ne='Nex:BAABNQAECn88AAIHAAoKDiEwOAAYAwAHAAoKDiEwOAAYAwAAAA==.',
Ni='Niceshield:BAAANQAECggIEgAAAA==.Nightsawdy:BAABNQAECn8qAAMYAAgK/RRrfACnAQAYAAgK/RRrfACnAQAlAAEKLROFEQBGAAAAAA==.Niightstorm:BAABNQAECn8iAAMYAAYK/w/wyABwAQAYAAYK/w/wyABwAQAlAAEKAAC/FQAAAAAAAA==.Nilvannas:BAAANQADCggICAAAAA==.Nitefire:BAAANQADCgYIGgAAAA==.Nitélifé:BAABNQAECn8VAAIMAAcKLxDMZgBqAQAMAAcKLxDMZgBqAQAAAA==.',
Of='Offspring:BAAANQABCgIIAgAAAA==.',
Om='Omora:BAABNQAECn8lAAQEAAoK2RahEQD7AQAEAAoK2RahEQD7AQAQAAYKWgm5rwAgAQAFAAIKmwwfcgFrAAABNQAECgoKMgAgAHAaAA==.',
Op='Opalinnas:BAABNQAECn9NAAIPAAoKeiKLBQCDAwAPAAoKeiKLBQCDAwAAAA==.Optimism:BAAANQADCgIIAgAAAA==.',
Pa='Paladrone:BAAANQABCggIDwABNQADCgcICgANAAAAAA==.Palestrina:BAAANQADCgMIAwAAAA==.Pallyandtank:BAAANQAECgEIAQAAAA==.Panzer:BAABNQAECn8zAAIRAAgKXxb0IQBcAQARAAgKXxb0IQBcAQAAAA==.Parts:BAABNQAECn8yAAQTAAoKoRWARADTAQATAAgK4haARADTAQAiAAYKwg+MUAB8AQAmAAMK0gpNFQCbAAAAAA==.Passionfruit:BAAANQAECgcICAAAAA==.Paul:BAAANQAECgUIDAAAAA==.',
Pe='Peachtea:BAAANQAECgYIDgAAAA==.Pepecojon:BAAANQADCggIDwAAAA==.',
Pi='Piebaby:BAAANQADCgUIBgAAAA==.Pirodeath:BAAANQAECgYICAAAAA==.',
Pl='Plovdiv:BAAANQADCgcJCQAAAA==.',
Po='Poah:BAAANQAECgYIBwAAAA==.',
Pr='Pray:BAABNQAECn9JAAMeAAoKgiUQAgAbBAAeAAoKGyUQAgAbBAAnAAgKMiR5AQA5AwAAAA==.Prodarkangel:BAAANQADCgcJCQAAAA==.',
Pu='Puckllane:BAAANQAECgEIAgAAAA==.Punkin:BAAANQAECgMIAgAAAA==.',
Py='Pyre:BAABNQAECn85AAMnAAoKCQ2VCgCeAQAnAAgKWg2VCgCeAQAeAAoK0gb2ZgCSAQABNQAECgEJAQANAAAAAA==.',
['Pü']='Püff:BAAANQADCgEIAQABNQAECgYIDAANAAAAAA==.',
Qu='Quanah:BAABNQAECn8cAAIMAAgKrB6jMQBCAgAMAAgKrB6jMQBCAgAAAA==.Quivver:BAAANQADCgYIGAAAAA==.',
Ra='Rabmaxx:BAABNQAECn8sAAIXAAkKqQXuVwAqAQAXAAkKqQXuVwAqAQAAAA==.Raina:BAAANQAECgIIAgAAAA==.Rap:BAAANQAECgMIBAAAAA==.Ravenlight:BAACNQAFFH8KAAIFAAUKFwWPFwDCAAAFAAUKFwWPFwDCAAA1AAQKfyUAAgUACgolFlJ1AEMCAAUACgolFlJ1AEMCAAAA.Ravenwynnd:BAABNQAECn84AAMDAAoKjCFSHQBCAwADAAoKjCFSHQBCAwAGAAYKFh23FQDMAQAAAA==.Raynman:BAABNQAECn9CAAMIAAoKUhOiOADdAQAIAAoKUhOiOADdAQAMAAoKjATqbgBQAQAAAA==.',
Re='Restotuition:BAAANQABCgQICAABNQAFFAYIEgAeAB0cAA==.Reylariel:BAAANQADCgMIAwAAAA==.',
Rh='Rhydian:BAAANQADCgQIBAAAAA==.Rhyzer:BAABNQAECn8kAAIZAAcK3xicEABWAQAZAAcK3xicEABWAQAAAA==.',
Ri='Riiver:BAAANQAECgQIBAAAAA==.',
Ro='Roderick:BAAANQAECgMIAgAAAA==.Root:BAABNQAECn86AAIRAAoKxiZeAACVAwARAAoKxiZeAACVAwAAAA==.',
Ru='Rubmytotem:BAAANQAECgYICwAAAA==.',
Sa='Sabazia:BAABNQAECn8tAAMbAAgKHxPfSADUAQAbAAgKHxPfSADUAQABAAIK1gV3jQAmAAAAAA==.Sabelinå:BAAANQAECgIIBAAAAA==.Sable:BAAANQADCgEIAQAAAA==.Sacred:BAABNQAECn8YAAMSAAkKUhDZHAACAQASAAgKvg/ZHAACAQAOAAIKzBOdlQCBAAAAAA==.Saerise:BAAANQAECgQIAgAAAA==.Sairalindë:BAAANQAECgcIEQAAAA==.Salamandra:BAAANQADCggIGQABNQAECgoKMgAgAHAaAA==.Saleath:BAAANQAECgIIAwAAAA==.Salios:BAAANQAECgEIAQAAAA==.Sanara:BAAANQABCgUIBwABNQAECgcIJAAQAN8NAA==.Sanctifier:BAAANQADCgUIBQAAAA==.',
Sc='Scrept:BAAANQAECggICwAAAA==.Scynix:BAEBNQAECn8cAAMUAAgKvQkhJwCAAQAUAAgKvQkhJwCAAQAkAAcKRQzADQBwAQAAAA==.Scÿph:BAEANQAECgMIBQABNQAECggIHAAUAL0JAA==.',
Se='Sedaline:BAAANQAECgEIAQAAAA==.Seizuregoat:BAAANQAECgMIBAAAAA==.Senus:BAAANQADCgEIAQAAAA==.Servoker:BAAANQAECggIEQAAAA==.',
Sh='Shabzshooter:BAAANQAECgUICgAAAA==.Shabzyt:BAABNQAECn8ZAAMBAAkKsRZdUADSAQABAAcK6hldUADSAQACAAcKVA7TWAAaAQAAAA==.Shaienne:BAAANQADCgcIDgAAAA==.Shammander:BAABNQAECn8YAAIIAAcKngjRhADuAAAIAAcKngjRhADuAAAAAA==.Shamrockshak:BAAANQAECgIIBAAAAA==.Shamron:BAAANQADCgcICgAAAA==.Shenuton:BAABNQAECn8hAAIFAAkKsQgZwQA7AQAFAAkKsQgZwQA7AQAAAA==.Shieldbash:BAABNQAECn9EAAIGAAoKASb9AADNAwAGAAoKASb9AADNAwAAAA==.Shockthêràpy:BAABNQAECn8pAAMMAAoKjSKvHgDwAgAMAAoKjSKvHgDwAgAIAAEKzw4lMgE3AAAAAA==.Shoes:BAAANQAECgYIDAAAAA==.Shtdruid:BAAANQAECgEIAQAAAA==.',
Si='Sibearian:BAABNQAECn8ZAAMRAAoKwxqcHQCAAQARAAoKwxqcHQCAAQASAAMKTQyhLwCVAAAAAA==.Sibeson:BAABNQAECn8vAAMLAAoKkBJgCAC/AQALAAkKFRRgCAC/AQAKAAgKyAqurgB0AQABNQAECgoKGQARAMMaAA==.Simi:BAABNQAECn8wAAIYAAoK+RMARwAwAgAYAAoK+RMARwAwAgAAAA==.',
Sm='Smithnwesson:BAAANQAECgEIAQAAAA==.Smokesçreen:BAABNQAECn8+AAMfAAoKLhAsDAB2AQAfAAoKLhAsDAB2AQAXAAcKKQlqTwBcAQAAAA==.',
So='Soonerpride:BAABNQAECn8iAAIFAAkKbiOrUwAhAgAFAAkKbiOrUwAhAgAAAA==.Soothed:BAAANQADCggICAAAAA==.',
Sp='Spearminttea:BAAANQADCgIIAgAAAA==.Spellbreakr:BAACNQAFFH8KAAMHAAUKwAmZPgDAAAAHAAQKcQmZPgDAAAAaAAEKqgqjEABOAAA1AAQKfysAAgcACgpUIEkmAJsCAAcACgpUIEkmAJsCAAAA.Spirtbreaker:BAABNQAECn8VAAIIAAgKnhLBmABnAQAIAAgKnhLBmABnAQAAAA==.Sprockette:BAAANQADCgIIAgAAAA==.',
Sq='Squeak:BAEANQADCgUIDQABNQAECgMIAgANAAAAAA==.Squiby:BAABNQAECn9MAAMWAAoKSCPrBQB5AwAWAAoKSCPrBQB5AwAeAAcK/CDxJwCaAgAAAA==.',
St='Stankowitz:BAAANQAECgEIAgAAAA==.Starboi:BAAANQADCgUIBQAAAA==.Starce:BAAANQAECgEIAgAAAA==.Steveirwin:BAAANQADCgYICgAAAA==.Stheris:BAABNQAECn8zAAIiAAoKxBjzCABHAgAiAAoKxBjzCABHAgAAAA==.Stoops:BAAANQADCggICAAAAA==.Stuefester:BAABNQAECn8UAAMbAAcKTyAFPAATAgAbAAcKIh0FPAATAgABAAcK9x1AWgCnAQAAAA==.Stäirs:BAABNQAECn8aAAMDAAoKhw+2UwDxAQADAAoKhw+2UwDxAQAZAAEKVw+aMQA0AAAAAA==.',
Sv='Sveika:BAABNQAECn8WAAIRAAYKFQW5QgCrAAARAAYKFQW5QgCrAAAAAA==.',
Sy='Sylaria:BAEANQAECgMIAgAAAA==.Syreline:BAAANQAECgQIBAAAAA==.',
['Sï']='Sïn:BAABNQAECn8jAAIKAAoKtRmYSwDfAQAKAAoKtRmYSwDfAQAAAA==.',
['Sý']='Sýlver:BAABNQAECn8hAAIOAAgKkwxcUQCXAQAOAAgKkwxcUQCXAQAAAA==.',
Ta='Tantric:BAAANQAECgMIAQABNQAECggIMwARAF8WAA==.Tarathiel:BAAANQADCgIIAgAAAA==.Tarpalantir:BAAANQAECgEIAQAAAA==.Taurne:BAABNQAECn9DAAMPAAoKzBvEEQCSAgAPAAoKzBvEEQCSAgAOAAMKiQX6lwB5AAAAAA==.',
Tc='Tchnce:BAAANQADCgcICgAAAA==.',
Te='Teknoman:BAABNQAECn8/AAMDAAoKvxuhLwBzAgADAAoKvxuhLwBzAgAGAAEKWgpmRQApAAAAAA==.Telephone:BAAANQAECgEIBwAAAA==.Tempered:BAABNQAECn8mAAIDAAoKyA9glADpAQADAAoKyA9glADpAQABNQAECgoKMgATAKEVAA==.Tendrian:BAAANQAECgEIAQAAAA==.Teresen:BAAANQADCgIIAgAAAA==.',
Th='Thaitea:BAAANQADCgIIBAAAAA==.Thalindra:BAABNQAECn8kAAIYAAcK5A1LqQBEAQAYAAcK5A1LqQBEAQAAAA==.Tharain:BAAANQAECgQIBgAAAA==.Thebigbeast:BAABNQAECn8aAAMEAAcKiR3VIABRAQAEAAUKZh3VIABRAQAQAAYKzx06nwBHAQABNQAFFAkJGwAKABgRAA==.Thecurt:BAABNQAECn9JAAIgAAoKWSOCAQAlAwAgAAoKWSOCAQAlAwAAAA==.Thunderrbutt:BAABNQAECn8WAAIIAAcKoAw3kgB3AQAIAAcKoAw3kgB3AQABNQAECgoKHgAQAF0QAA==.Thyralizen:BAAANQADCgUICQAAAA==.',
Ti='Tiael:BAAANQAECgIIAgAAAA==.Timaeus:BAAANQADCggIGgAAAA==.Tinylef:BAABNQAECn8yAAQgAAoKcBoJCQCqAQAhAAcKpxePJwDlAQAgAAcKwh0JCQCqAQAoAAYKXhFJHQAjAQAAAA==.Tirouke:BAAANQAECgUIBwAAAA==.Titanlock:BAAANQAECgIIAQAAAA==.',
Tk='Tkdfath:BAAANQADCgYIBgAAAA==.',
To='Toralina:BAAANQAECgEIAQAAAA==.Torvia:BAAANQAECgMIAgAAAA==.',
Tr='Trisinz:BAABNQAECn8dAAIOAAkKJQ0eMQBoAQAOAAkKJQ0eMQBoAQAAAA==.',
Tu='Tuerto:BAABNQAECn8pAAIYAAoKNRJmUAAXAgAYAAoKNRJmUAAXAgAAAA==.Tuiarmstrong:BAAANQAECgUIEAABNQAFFAYIEgAeAB0cAA==.Tuipasteur:BAACNQAFFH8SAAMeAAYKHRycDgCmAQAeAAYKHRycDgCmAQAnAAMK/QMqAQCxAAA1AAQKfzUABB4ACgq2ISgWABQDAB4ACgq2ISgWABQDABYABQp6C/1FAIAAACcAAgriCqkfAGQAAAAA.Tuithexiv:BAAANQAECgcIEQABNQAFFAYIEgAeAB0cAA==.Turbojohnson:BAAANQAECgEIAQAAAA==.Turk:BAABNQAECn9OAAIcAAoKcBVjFwDqAQAcAAoKcBVjFwDqAQAAAA==.Turkish:BAABNQAECn80AAICAAoKrA73MQDKAQACAAoKrA73MQDKAQAAAA==.',
Tw='Twinkytoes:BAAANQAECgEIAQAAAA==.',
Ty='Tychaa:BAAANQADCgYIEgAAAA==.Tylat:BAAANQABCgMIAwAAAA==.Tyranay:BAABNQAECn9VAAIeAAoK9R52CwB6AwAeAAoK9R52CwB6AwAAAA==.Tyrith:BAAANQADCgQIBQAAAA==.',
Ui='Uintah:BAABNQAECn8bAAIRAAkKVxndEgD1AQARAAkKVxndEgD1AQAAAA==.',
Ul='Ullyr:BAACNQAFFH8PAAIOAAYKwhGsCABzAQAOAAYKwhGsCABzAQA1AAQKfz0AAw4ACgrhIH0KAOwCAA4ACgrhIH0KAOwCABIAAQoAAJVOABkAAAAA.',
Um='Umbryss:BAAANQAECgUIBwABNQAECgoKOgAXANMlAA==.',
Us='Userdel:BAABNQAECn8dAAIMAAYKXwj+vADwAAAMAAYKXwj+vADwAAAAAA==.',
Va='Vadose:BAAANQADCgYIBgABNQAECgoKMAAYAPkTAA==.Valytrois:BAAANQAECggICgAAAA==.Variant:BAAANQAECgMIBQAAAA==.Varinix:BAAANQAECgEIAQAAAA==.Vauld:BAAANQADCgQJBQAAAA==.',
Ve='Veiksla:BAAANQADCgYIGgAAAA==.Vengerr:BAAANQADCgYIFQAAAA==.Verace:BAAANQAECggICQAAAA==.Verradic:BAABNQAECn8ZAAMJAAgKBAiYLQAWAQAJAAcKlgeYLQAWAQAKAAcKYwZmrADoAAAAAA==.',
Vi='Vilanelle:BAAANQABCgUIBwAAAA==.Vitur:BAABNQAECn84AAIcAAkKxCN1AwChAwAcAAkKxCN1AwChAwAAAA==.Vivi:BAAANQADCgYIBgAAAA==.',
Vo='Voidbunny:BAAANQAECgYIEgAAAA==.Volaine:BAABNQAECn8iAAQJAAcKgwgZKQBRAAAKAAUK/wfj0ACeAAAJAAIKSQkZKQBRAAALAAEKvwkNKwA4AAAAAA==.Volgar:BAAANQADCgUIDwAAAA==.Volition:BAAANQADCgYIBgAAAA==.Volt:BAABNQAECn8nAAIVAAoKoxcpEABmAgAVAAoKoxcpEABmAgABNQAECgoKOwAKADYNAA==.Vorarephilia:BAAANQAECgUIBQAAAA==.',
Vr='Vrye:BAABNQAECn8cAAIcAAkKQwTnSwD6AAAcAAkKQwTnSwD6AAAAAA==.',
Vy='Vynaeda:BAABNQAECn8UAAIHAAcKEhSc6gC1AQAHAAcKEhSc6gC1AQAAAA==.',
['Vô']='Vôx:BAAANQAECgIIBgABNQAECgcIDgANAAAAAA==.',
Wa='Wakko:BAAANQADCgcIEwAAAA==.Walkure:BAAANQADCgYIHAAAAA==.',
We='Weirdscience:BAAANQABCgQIBAAAAA==.Wetasstotem:BAABNQAECn8dAAMIAAoK5BzkKwDPAgAIAAoK5BzkKwDPAgAMAAYKrhXBYwB0AQABNQAFFAkJGwAKABgRAA==.',
Wh='Whew:BAAANQADCggICQAAAA==.',
Wi='Widge:BAAANQAECgQIBAAAAA==.Wikker:BAAANQADCgQIBAAAAA==.Wishy:BAAANQABCgQIBgAAAA==.',
Wo='Worldlight:BAAANQADCgIIAgAAAA==.',
Wr='Wreckbums:BAAANQAECgMIBAAAAA==.Wreckd:BAAANQAECggIEAABNQAECgoKMgATAKEVAA==.Wrongway:BAAANQADCgQIBwAAAA==.',
Xa='Xanthad:BAAANQADCgUICAAAAA==.',
Xb='Xb:BAAANQADCgYIFgAAAA==.',
Xi='Xitãozinho:BAAANQAECgQICgAAAA==.',
Xy='Xyomi:BAAANQADCgQIBAAAAA==.',
Ya='Yaalia:BAABNQAECn8kAAIQAAcK3w37cwBFAQAQAAcK3w37cwBFAQAAAA==.Yaan:BAABNQAECn8aAAIIAAoK+gtZWwBdAQAIAAoK+gtZWwBdAQAAAA==.Yalane:BAAANQAECgMIAwAAAA==.Yamat:BAAANQAECgEIAwABNQAECgIIAwANAAAAAA==.',
Yo='Yogi:BAAANQAECgUIBQAAAA==.',
Za='Zain:BAAANQADCgYIBgABNQAECgoKVgAJAAAdAA==.Zalaan:BAAANQAECgcIEgABNQAECgoKKAAHAM4bAA==.Zandibar:BAABNQAECn8jAAIZAAcKQRJBEwAqAQAZAAcKQRJBEwAqAQAAAA==.Zaptoasted:BAAANQADCgYIBgAAAA==.Zariea:BAAANQAECgIIAgABNQAECggIKgABAMcVAA==.Zavac:BAAANQADCgUIBwAAAA==.',
Ze='Zellezugtail:BAAANQADCgYIBgABNQAECgkJGwAKAA0FAA==.Zelritch:BAAANQADCggICAAAAA==.',
Zi='Zinfandell:BAAANQAECgUIEAAAAA==.',
Zo='Zorrloc:BAAANQADCgQIBAAAAA==.',
Zu='Zuggie:BAABNQAECn8bAAIKAAkKDQW9lwAVAQAKAAkKDQW9lwAVAQAAAA==.Zugtail:BAAANQAECgEIAgABNQAECgkJGwAKAA0FAA==.Zurtrinik:BAAANQAECgUICwABNQAFFAcIFgAgAAAZAA==.',
Zy='Zyntalla:BAABNQAECn8iAAMcAAcK0w1sLgAPAQAcAAcK0w1sLgAPAQAfAAMKjwz8JABXAAAAAA==.',
Zz='Zzonked:BAAANQAECgEIAQAAAA==.',
['Zê']='Zêp:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrròw:BAAANQAECgEIAgAAAA==.',
['Ðo']='Ðoogle:BAABNQAECn8ZAAMVAAgKPQ1bHQAtAQAVAAgKPQ1bHQAtAQAMAAIKdRDjAwFhAAABNQADCgIIAgANAAAAAA==.',
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
