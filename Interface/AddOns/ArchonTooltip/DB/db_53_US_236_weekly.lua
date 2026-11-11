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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Restoration','DeathKnight-Frost','Paladin-Protection','Hunter-Survival','Unknown-Unknown','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Arcane','Mage-Fire','Warrior-Protection','Druid-Restoration','Shaman-Elemental','Priest-Shadow','Priest-Holy','Paladin-Retribution','Monk-Mistweaver','Druid-Guardian','Druid-Feral','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Havoc','Warlock-Affliction',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=53,date='2026-11-10',data={Ag='Agp:BAACNQAFFH8HAAIBAAUKTBXoCwCSAQABAAUKTBXoCwCSAQA1AAQKfx8AAwEACQqPI1EcACYDAAEACQqPI1EcACYDAAIAAQoAAPeNADEAAAAA.',
Ah='Aharan:BAABNQAECn8tAAIDAAgKaAx5OgAxAQADAAgKaAx5OgAxAQAAAA==.Ahnaterra:BAAANQAECggICAAAAA==.',
Al='Aleria:BAAANQAECgcIDAAAAA==.',
An='Andraxy:BAAANQAECgYICQABNQAFFAQIDwAEAHAaAA==.Anielor:BAAANQAECgEIAwAAAA==.',
Ar='Aratar:BAACNQAFFH8IAAMFAAUKBBZWIQD0AAAFAAQKBBZWIQD0AAAGAAEKAADxBQBJAAA1AAQKfy8AAgUACQozHzlIABcCAAUACQozHzlIABcCAAAA.Arcadia:BAABNQAECn8WAAIBAAgK3AiswwAQAQABAAgK3AiswwAQAQAAAA==.Arcticheat:BAAANQAECgQIBQABNQAECgkJJgAHAF4cAA==.Arizona:BAABNQAECn8iAAQIAAkKsROsRQDPAQAIAAgKiBKsRQDPAQAJAAYKKRCwTwCAAQAKAAMKwQf9FgB3AAAAAA==.Arja:BAAANQAECgQIBAAAAA==.Arkantos:BAABNQAECn8YAAILAAkKjhL1cwCwAQALAAkKjhL1cwCwAQAAAA==.',
As='Aspir:BAEANQAECgEIAQABNQAFFAYIEgAMAAUWAA==.Asta:BAAANQADCgYIBgAAAA==.',
At='Athius:BAAANQAECgEIAQAAAA==.',
Au='Automobeer:BAAANQADCgMIAwAAAA==.',
Aw='Awake:BAAANQAFFAEIAgAAAA==.',
Ba='Bakedsham:BAAANQAECgQIBAAAAA==.Bayareadady:BAAANQAECgEIAQAAAA==.',
Be='Belandra:BAAANQADCgYIAwABNQAECgcIKgANADYhAA==.',
Bi='Biggbird:BAABNQAECn8lAAIDAAcKkxEdQAATAQADAAcKkxEdQAATAQAAAA==.',
Bj='Bjord:BAABNQAECn82AAQBAAoKRiACHAAoAwABAAoKRiACHAAoAwAOAAQKaROICwDmAAACAAEK3gCAoAAaAAABNQADCggICAAPAAAAAA==.',
Bl='Blackplague:BAAANQABCgQIBAAAAA==.',
Bo='Boong:BAAANQADCgQIBAAAAA==.Bossdeath:BAABNQAECn8bAAIQAAkKthiSGgAcAgAQAAkKthiSGgAcAgABNQAFFAIIBgAIAJUlAA==.Bossdierr:BAABNQAECn83AAMRAAoK8iTYAQBeAwARAAoK8iTYAQBeAwASAAgKMhPsEgCAAQABNQAFFAIIBgAIAJUlAA==.Bossdisan:BAABNQAECn8sAAMTAAoKTSNqCwAmAwATAAoKTSNqCwAmAwAUAAMKaRI+CAChAAABNQAFFAIIBgAIAJUlAA==.Bossdiyi:BAABNQAECn8/AAMFAAoKhySJEgByAwAFAAoKhySJEgByAwAVAAgKghXnDQDCAQABNQAFFAIIBgAIAJUlAA==.Bossmasster:BAAANQAECgEIAQABNQAFFAIIBgAIAJUlAA==.Bosswudi:BAACNQAFFH8GAAIIAAIKlSUbEwDhAAAIAAIKlSUbEwDhAAA1AAQKf0AAAwgACQoeJrMCAHQDAAgACQrYJbMCAHQDAAkABQrEJTMxABwCAAAA.',
Br='Bruh:BAAANQAECgYICgAAAA==.',
Bu='Buffmw:BAEANQAECgQIBQABNQAFFAoKPgAWAJwjAA==.Bunnicula:BAAANQADCgUIBwAAAA==.Buttshaman:BAABNQAECn8nAAIXAAoK1hd5JwAzAgAXAAoK1hd5JwAzAgAAAA==.',
Ca='Cazadòr:BAAANQADCggICAAAAA==.',
Ch='Choco:BAABNQAECn8uAAQHAAoKuA7DBQCQAQAHAAoKUA7DBQCQAQAYAAkK6gUdKwAUAQAZAAUK2gzBywB5AAAAAA==.Christon:BAAANQABCgIIAgAAAA==.Chromiepip:BAAANQADCgEIAQAAAA==.Chudungus:BAAANQADCgUIBQAAAA==.',
Co='Colt:BAABNQAECn8sAAINAAoK2huDFABfAgANAAoK2huDFABfAgAAAA==.Corrosiveman:BAABNQAECn8pAAMZAAoKsRmLLwBxAgAZAAoKsRmLLwBxAgAYAAEKAACzegAzAAAAAA==.Cowned:BAAANQADCgYIBgABNQAFFAIIBgAaAAgTAA==.',
Cr='Creamy:BAAANQAECgUJCwAAAA==.Crockett:BAAANQAECgEIAQAAAA==.',
Da='Daer:BAAANQADCgQIBAAAAA==.Danielpana:BAACNQAFFH8PAAIEAAQKcBrkCQAtAQAEAAQKcBrkCQAtAQA1AAQKfyYAAgQACQoNI1MMABIDAAQACQoNI1MMABIDAAAA.Darkfyre:BAABNQAECn87AAMbAAoKrxgJDABcAgAbAAoKrxgJDABcAgAEAAIKaxAAWgAyAAAAAA==.Darkraider:BAABNQAECn8fAAQcAAkKgxVgNAAAAQADAAUKPRBkcAAJAQAcAAYKGRlgNAAAAQAWAAQKlw/eRQDSAAAAAA==.',
Di='Dinkledots:BAAANQADCgUIBQABNQAECgoKPAATAA0TAA==.Dinks:BAABNQAECn88AAITAAoKDROtUAAQAgATAAoKDROtUAAQAgAAAA==.Dishwasher:BAABNQAECn8bAAMZAAkKGRjxSQBIAgAZAAkKAxfxSQBIAgAHAAIKNBVYHQB4AAAAAA==.',
Do='Docc:BAAANQAECgcIDwAAAA==.Doe:BAAANQADCgYIBgABNQAECgoKQgALAL8YAA==.',
Dr='Dragonfyre:BAAANQAECgQIBwAAAA==.Drood:BAAANQADCgUIBQAAAA==.',
Du='Duration:BAABNQAECn8VAAIKAAYK/AgcEAAgAQAKAAYK/AgcEAAgAQAAAA==.',
Ek='Ektyr:BAAANQAECgUIDAABNQADCggICAAPAAAAAA==.',
Em='Emiliam:BAABNQAECn8fAAQcAAoKshd+FAAdAgAcAAkKWxl+FAAdAgADAAUKuwplTwDOAAAdAAQKjhcXKQCjAAAAAA==.',
Er='Erdrick:BAAANQAECgQICwAAAA==.Ero:BAAANQAECgcIEwAAAA==.',
Ev='Evito:BAAANQADCgUIBQAAAA==.Evërjzy:BAAANQADCggIDAAAAA==.',
Fa='Faded:BAAANQAECgMIBgAAAA==.Fatheralvin:BAAANQAECgEIAQAAAA==.',
Fe='Feronar:BAABNQAECn8pAAMGAAgKlA2cEgB4AQAGAAgKlA2cEgB4AQAFAAQKywMqFgFAAAAAAA==.',
Fl='Flowermom:BAAANQADCgQIBAAAAA==.Flume:BAAANQAECgcIDgAAAA==.',
Fr='Fromhell:BAAANQADCgEIAQAAAA==.',
Fx='Fx:BAABNQAECn9CAAMLAAoKvxjrJACIAgALAAoKvxjrJACIAgAXAAEKTg3m+wAtAAAAAA==.Fxx:BAAANQAECgYIDQAAAA==.',
['Fé']='Féllgrim:BAAANQABCgQIBAAAAA==.',
['Fú']='Fúsión:BAEANQAECgEIAQABNQAECgoKKAAJAIgiAA==.',
Ga='Galedra:BAABNQAECn8qAAINAAcKNiGAEwBrAgANAAcKNiGAEwBrAgAAAA==.Gargomash:BAAANQAECgIIAwAAAA==.',
Gi='Gin:BAAANQADCggIGgABNQAFFAUIDAABACsgAA==.',
Gj='Gjana:BAABNQAECn9HAAMeAAoKchzOIwB0AgAeAAoKchzOIwB0AgAfAAUK2gW+PQDLAAAAAA==.',
Go='Goma:BAAANQAECgcICwAAAA==.Goomy:BAAANQAECgQICAAAAA==.Gorlash:BAAANQADCgYIBgAAAA==.',
Gp='Gpt:BAAANQAECgYIDQAAAA==.',
Gr='Gravemaw:BAAANQADCgcIBwAAAA==.Greenboi:BAAANQADCgcIEgAAAA==.Grimfeather:BAAANQAECgcIEAAAAA==.Grimgeth:BAABNQAECn9YAAQMAAoK1BniHgBDAgAgAAkKixrWMgBgAgAMAAoKQBfiHgBDAgAQAAYKVhkfUAC0AQAAAA==.Grimwrath:BAABNQAECn8eAAMFAAkKoAmhugCKAQAFAAgKOgqhugCKAQAGAAIKBAbrNQAiAAABNQAECgoKWAAMANQZAA==.Grouch:BAABNQAECn9DAAIXAAoKAh0uLADNAgAXAAoKAh0uLADNAgABNQAECgoKRwAeAHIcAA==.',
Gu='Guanine:BAABNQAECn82AAMMAAoKeRiNIgApAgAMAAoKeRiNIgApAgAgAAYKRAldhAAOAQAAAA==.Gudeath:BAAANQAECgYIEgAAAA==.Guishin:BAAANQAECgEIAgAAAA==.Gulhain:BAAANQADCgQIBAAAAA==.Guyver:BAAANQADCgYICwAAAA==.',
He='Heidriel:BAAANQAECgQIAwAAAA==.Heontwo:BAAANQAECgIIAwAAAA==.Heshan:BAACNQAFFH8FAAIhAAIKsw2DCACGAAAhAAIKsw2DCACGAAA1AAQKf0IAAyEACgoEGzUFAMQCACEACgoEGzUFAMQCABMABwqzEcTGAPcBAAAA.',
Ho='Holycowza:BAAANQADCgQIAQAAAA==.Hoodwink:BAAANQADCgYIBwAAAA==.',
Im='Imortathorin:BAAANQADCggJCQAAAA==.',
In='Insanities:BAABNQAECn8mAAMHAAkKXhyCAwC0AgAHAAgK5xyCAwC0AgAZAAgKFROIXwACAgAAAA==.',
Ir='Iradakq:BAAANQAECgEIAQAAAA==.',
Ja='Jaidie:BAABNQAECn8gAAICAAkKhAZcIwA7AQACAAkKhAZcIwA7AQAAAA==.Jarco:BAECNQAFFH8OAAQKAAcK1BakAAD8AQAKAAYKHBqkAAD8AQAIAAIKsglOIgBUAAAJAAEKAADoHQBOAAA1AAQKfzQAAwoACgpRJHoBAHIDAAoACQraInoBAHIDAAgACgrlIt0KAMYCAAAA.',
Je='Jebussaves:BAAANQAECgEIAQAAAA==.Jeff:BAAANQADCgEIAQAAAA==.Jerlonge:BAAANQAECgEIAgAAAA==.',
Jo='Joak:BAAANQADCgIIAgAAAA==.',
Ka='Kasaar:BAAANQADCgIIAgAAAA==.',
Ki='Kitsune:BAABNQAECn8uAAMcAAkKRAjYNAD9AAADAAkKSAZ3WwBkAQAcAAYKrAnYNAD9AAAAAA==.',
Kr='Kryptix:BAABNQAECn8ZAAIZAAgKeB4mLgCwAgAZAAgKeB4mLgCwAgAAAA==.',
Ku='Kubicki:BAABNQAECn8UAAQYAAkKYxGePABGAQAYAAYKBA6ePABGAQAZAAUKBwrozQC6AAAHAAEKZBQUJwA6AAAAAA==.Kubimage:BAAANQADCgYIBgAAAA==.Kurta:BAAANQADCgEIAQAAAA==.',
La='Lastlife:BAAANQADCgYIDwAAAA==.Lastshamurai:BAAANQADCgUIBQAAAA==.Layona:BAAANQAECgYIDgAAAA==.',
Li='Linelli:BAACNQAFFH8UAAQOAAYKTCU/AACTAQAOAAYKTCU/AACTAQABAAEKAACxLgBkAAACAAEKGAAtKQALAAA1AAQKfzQABA4ACQo/Ju4AACwDAA4ACQo9Ju4AACwDAAEABwqWH7l7ABcCAAIAAQriGSVWAEgAAAAA.',
Lo='Lobixona:BAAANQAECgYIBwAAAA==.Lowakacho:BAAANQADCgQIBAAAAA==.',
Lx='Lxrbread:BAACNQAFFH8HAAMiAAIKhgRdCwBiAAAiAAIKhgRdCwBiAAAjAAEKNACtGwAWAAA1AAQKfz8ABCIACgoxEVUGAOUBACIACQoxEVUGAOUBACMACQpPCNIkAJoBACQAAwoBBXkyAH0AAAAA.',
['Lì']='Lìlith:BAABNQAECn8jAAIaAAkK7hnNTwAsAgAaAAkK7hnNTwAsAgABNQAFFAgIGwARAEYdAA==.',
Ma='Maccazilla:BAAANQADCgYICgAAAA==.Magdalena:BAABNQAECn8vAAIEAAoKUyNLBACPAwAEAAoKUyNLBACPAwAAAA==.Martini:BAAANQAECgYICwAAAA==.',
Me='Meatkleaver:BAABNQAECn8YAAIMAAkKMRLNQgC5AQAMAAkKMRLNQgC5AQAAAA==.Mech:BAABNQAECn/FAAMcAAoK9iYaAAClAwAcAAoK9iYaAAClAwAdAAkKBx/MBwDfAgAAAA==.Mediumroast:BAAANQADCgcICQAAAA==.Merbs:BAAANQAECgQIBwAAAA==.',
Mo='Mochi:BAABNQAECn8fAAILAAkKxxjjTAAwAgALAAkKxxjjTAAwAgAAAA==.Mommydeath:BAAANQADCgYIBgAAAA==.Morbius:BAAANQAECggICAAAAA==.Morholt:BAAANQAECgEIAQAAAA==.Morix:BAAANQABCgcICgAAAA==.',
Ne='Necromortas:BAABNQAECn8aAAMeAAcKCBZ9gQDiAQAeAAcKCBZ9gQDiAQAfAAEKEgPVgQAqAAAAAA==.',
Ni='Nipnaxes:BAAANQADCgIIAgAAAA==.Nira:BAAANQADCgYICgAAAA==.Niver:BAAANQAECgUIBQAAAA==.',
No='Notlrahc:BAAANQAECgQIDQAAAA==.',
Ny='Nyki:BAAANQADCgYICAAAAA==.',
Os='Oscrixi:BAAANQABCgcICAAAAA==.',
Ov='Overheat:BAAANQAECgQIBAAAAA==.',
Pa='Padriac:BAAANQAECgQIBQAAAA==.Paolinelli:BAAANQAECggIDgABNQAFFAYIFAAOAEwlAA==.Pattêrn:BAAANQADCggIDQAAAA==.Paìn:BAACNQAFFH8PAAIRAAYKRRyvAwAaAgARAAYKRRyvAwAaAgA1AAQKf20AAhEACgq8JksAAAcEABEACgq8JksAAAcEAAE1AAUUCAgbABEARh0A.',
Pe='Pedri:BAACNQAFFH8hAAQgAAUKmCaKAwBBAQAgAAUKmCaKAwBBAQAMAAQKCyAfCwAyAQAQAAEKAACLLAAAAAA1AAQKf08AAyAACgr8JnQAAJEDACAACgr8JnQAAJEDAAwABApUIM9XAB4BAAAA.Pedrok:BAABNQAECn9UAAMFAAoKihXKQAAxAgAFAAoKihXKQAAxAgAVAAEKAAALTQAZAAAAAA==.',
Ph='Phael:BAAANQAECgUICgAAAA==.',
Pi='Pinkdot:BAAANQADCgYIBwAAAA==.',
Po='Popius:BAAANQAECgQICQAAAA==.Pothtwo:BAAANQADCgUIBQAAAA==.',
Pr='Prentiss:BAAANQADCgcIDAABNQAECgUIFAADAM0CAA==.Promorph:BAAANQAECgEIBAAAAA==.',
Pu='Puups:BAAANQADCgYICAAAAA==.',
['Pì']='Pìngü:BAABNQAECn8aAAMZAAkKlxHabADXAQAZAAkKlxHabADXAQAHAAEKvwLoMAAiAAAAAA==.',
Ra='Raph:BAACNQAFFH8GAAMgAAQKagY0GwCAAAAgAAIKawY0GwCAAAAMAAIKaQahHQBCAAA1AAQKfzkAAyAACgpcIQcUABkDACAACgpcIQcUABkDAAwAAwqVFQJvAMwAAAAA.',
Re='Rednoser:BAABNQAECn8eAAITAAoKSxQ5iABuAgATAAoKSxQ5iABuAgAAAA==.Redthedeer:BAAANQAECgYIBwAAAA==.Redthepriest:BAAANQAECgEIAQAAAA==.Refuliya:BAAANQAECggICgAAAA==.Remmahcm:BAAANQAECggIEwAAAA==.Reverse:BAAANQADCgYIBgABNQAFFAUIBwABAEwVAA==.Rexnor:BAAANQADCgQIBAABNQAECgQICwAPAAAAAA==.',
Sa='Sagas:BAABNQAECn8wAAIlAAoKJR53BgAdAwAlAAoKJR53BgAdAwAAAA==.Sambiquira:BAAANQAECgIIAgAAAA==.Sarial:BAABNQAECn8qAAMmAAkKlSQaBACxAwAmAAkKlSQaBACxAwARAAkKbhq+GwB5AgAAAA==.Saryeras:BAAANQADCgQIBAABNQADCggICAAPAAAAAA==.',
Sc='Scrit:BAAANQAECgQICgAAAA==.',
Se='Semrys:BAAANQAECgIIAgABNQADCggICAAPAAAAAA==.',
Si='Sil:BAABNQAECn8UAAIVAAkKwwoYHgBkAQAVAAkKwwoYHgBkAQAAAA==.',
Sk='Ska:BAABNQAECn8ZAAIeAAoKfR8wEgDWAgAeAAoKfR8wEgDWAgAAAA==.',
So='Softbutt:BAAANQADCgIIAgAAAA==.Soulreaper:BAAANQAECgIIBgABNQAECgoKQgALAL8YAA==.',
Sq='Squish:BAAANQADCgEJAQAAAA==.',
St='Staby:BAAANQADCgYIBgABNQAECgMIAwAPAAAAAA==.',
Ta='Tapechewer:BAAANQADCgUICgAAAA==.Tatax:BAAANQAECggIDAABNQAFFAQIDwAEAHAaAA==.',
Te='Tertlepaws:BAAANQAECggICQABNQAECgoKKwACAHwfAA==.Teto:BAAANQADCgYIBwAAAA==.Tetsunen:BAABNQAECn8aAAIbAAcKthcWGABoAQAbAAcKthcWGABoAQAAAA==.',
Th='Thralson:BAAANQADCgQIBAAAAA==.',
To='Tog:BAAANQADCgIIAgAAAA==.Toggywoggy:BAABNQAECn8bAAInAAgKkBZWBwApAgAnAAgKkBZWBwApAgAAAA==.Tortoisetoes:BAABNQAECn8rAAICAAoKfB+oCACuAgACAAoKfB+oCACuAgAAAA==.',
Tr='Trillex:BAAANQAECgUIBAAAAA==.',
Tu='Turok:BAAANQAECgUIBwAAAA==.Turtles:BAABNQAECn8cAAIUAAoKFx/cAAC3AgAUAAoKFx/cAAC3AgABNQAECgoKKwACAHwfAA==.Turtletoes:BAAANQAECgUICQABNQAECgoKKwACAHwfAA==.',
Ur='Urra:BAAANQAECggIBAAAAA==.',
Va='Valkyrie:BAAANQAECgcIBwAAAA==.',
Ve='Velo:BAAANQAECgEIAQAAAA==.Verminardy:BAAANQAECgEIBgAAAA==.',
Wa='Wanheda:BAACNQAFFH8FAAIBAAQKDRFyHwCYAAABAAQKDRFyHwCYAAA1AAQKfygAAgEACgrOIIIkAAUDAAEACgrOIIIkAAUDAAAA.Wargyu:BAACNQAFFH8PAAIFAAYKLRbsGABUAQAFAAYKLRbsGABUAQA1AAQKf18AAgUACgoUJMQPAIADAAUACgoUJMQPAIADAAAA.Watertort:BAABNQAECn+PAQMLAAoKnSE/BQC8AwALAAoKnSE/BQC8AwAXAAgKuRj5LwAEAgAAAA==.',
We='Weezard:BAAANQADCgYIEQABNQAECgoKRwAeAHIcAA==.',
Wo='Woobley:BAAANQADCgcICQAAAA==.',
Wy='Wyarlok:BAABNQAECn8aAAIeAAoK1hFpRwDsAQAeAAoK1hFpRwDsAQAAAA==.',
Xa='Xandraz:BAAANQADCgUIBgAAAA==.',
Yn='Ynup:BAAANQADCgcIFQAAAA==.',
Yr='Yrrygg:BAAANQADCgMIAwABNQADCgIIAwAPAAAAAA==.',
Za='Zardnax:BAAANQAECgIIAwAAAA==.',
Ze='Zel:BAAANQAECgEIAQAAAA==.Zenin:BAAANQAECgUICgABNQADCggICAAPAAAAAA==.Zenir:BAAANQAECgEIAQAAAA==.Zenjamin:BAAANQAECgUIDgABNQADCggICAAPAAAAAA==.',
Zu='Zuleika:BAABNQAECn8hAAILAAkKdh68QwBSAgALAAkKdh68QwBSAgAAAA==.',
['Øm']='Ømen:BAAANQAECgMIBAAAAA==.',
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
