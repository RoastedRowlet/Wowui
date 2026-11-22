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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Shaman-Restoration','Paladin-Protection','Hunter-Survival','Unknown-Unknown','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Arcane','Mage-Fire','Warrior-Protection','Druid-Restoration','Shaman-Elemental','Priest-Holy','Priest-Shadow','Paladin-Retribution','Monk-Mistweaver','Druid-Guardian','Druid-Feral','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Havoc','Warlock-Affliction',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=53,date='2026-11-17',data={Ag='Agp:BAACNQAFFH8HAAIBAAUKTBXoCwCSAQABAAUKTBXoCwCSAQA1AAQKfx8AAwEACQqPI1EcACYDAAEACQqPI1EcACYDAAIAAQoAAPeNADEAAAAA.',
Ah='Aharan:BAABNQAECn81AAIDAAkKvAu4NgBcAQADAAkKvAu4NgBcAQAAAA==.Ahnaterra:BAAANQAECggICAAAAA==.',
Al='Aleria:BAAANQAECgcICgAAAA==.',
An='Andraxy:BAAANQAECgYICAABNQAFFAQIDwAEAHAaAA==.Anielor:BAAANQABCgQIBAAAAA==.',
Ar='Aratar:BAACNQAFFH8IAAMFAAUKBBZWIQD0AAAFAAQKBBZWIQD0AAAGAAEKAADxBQBJAAA1AAQKfzAAAgUACQpPHz5MABsCAAUACQpPHz5MABsCAAAA.Arcadia:BAABNQAECn8WAAIBAAgK3Aji0gBbAQABAAgK3Aji0gBbAQAAAA==.Arcticheat:BAAANQAECgQIBAABNQAECgkJJgAHAF4cAA==.Arizona:BAABNQAECn8iAAQIAAkKsRPqTADOAQAIAAgKiBLqTADOAQAJAAYKKRCwTwCAAQAKAAMKwQf9FgB3AAAAAA==.Arja:BAAANQAECgQIBAAAAA==.Arkantos:BAABNQAECn8YAAILAAkKjhL1cwCwAQALAAkKjhL1cwCwAQAAAA==.',
As='Asta:BAAANQADCgYIBgAAAA==.',
At='Athius:BAAANQADCgUIBQAAAA==.',
Au='Automobeer:BAAANQADCgMIAwAAAA==.',
Aw='Awake:BAAANQAFFAEIAgAAAA==.',
Ba='Bakedsham:BAAANQAECgQIBAAAAA==.',
Be='Belandra:BAAANQADCgYIAwABNQAECgkJLAAMAIUdAA==.',
Bi='Biggbird:BAABNQAECn8qAAIDAAcKkxHtQwAVAQADAAcKkxHtQwAVAQAAAA==.',
Bj='Bjord:BAABNQAECn82AAQBAAoKRiACHAAoAwABAAoKRiACHAAoAwANAAQKaRNsDADmAAACAAEK3gCAoAAaAAABNQADCggICAAOAAAAAA==.',
Bl='Blackplague:BAAANQABCgQIBAAAAA==.',
Bo='Boong:BAAANQADCgQIBAAAAA==.Bossdeath:BAABNQAECn8cAAIPAAkKthgkHQATAgAPAAkKthgkHQATAgABNQAFFAIIBgAIAJUlAA==.Bossdierr:BAABNQAECn87AAMQAAoK+iTBAQBjAwAQAAoK+iTBAQBjAwARAAgKMhPsEgCAAQABNQAFFAIIBgAIAJUlAA==.Bossdisan:BAABNQAECn8wAAMSAAoKqyNfCgA0AwASAAoKqyNfCgA0AwATAAMKaRI+CAChAAABNQAFFAIIBgAIAJUlAA==.Bossdiyi:BAABNQAECn9EAAMFAAoKhySJEgByAwAFAAoKhySJEgByAwAUAAgKghWhDwC9AQABNQAFFAIIBgAIAJUlAA==.Bosswudi:BAACNQAFFH8GAAIIAAIKlSUdFQDgAAAIAAIKlSUdFQDgAAA1AAQKf0IAAwgACQoeJtkCAHQDAAgACQrYJdkCAHQDAAkABQrEJTMxABwCAAAA.',
Br='Bruh:BAAANQAECgYICAAAAA==.',
Bu='Buffmw:BAEANQAECgQIBAABNQAFFAoKQAAVAJwjAA==.Bunnicula:BAAANQADCgUIBwAAAA==.Buttshaman:BAABNQAECn8nAAIWAAoK1he1KwAvAgAWAAoK1he1KwAvAgAAAA==.',
Ca='Cazadòr:BAAANQADCggICAAAAA==.',
Ch='Choco:BAABNQAECn80AAQHAAoK0Q9wBgCHAQAHAAoKUA5wBgCHAQAXAAYKxQ8ojQAxAQAYAAkK6gV8LgAUAQAAAA==.Christon:BAAANQABCgIIAgAAAA==.Chromiepip:BAAANQADCgEIAQAAAA==.Chudungus:BAAANQADCgUIBQAAAA==.',
Co='Colt:BAABNQAECn8sAAIMAAoK2huDFABfAgAMAAoK2huDFABfAgAAAA==.Corrosiveman:BAABNQAECn8pAAMXAAoKsRkfNQBqAgAXAAoKsRkfNQBqAgAYAAEKAACzegAzAAAAAA==.Cowned:BAAANQADCgYIBgABNQAFFAIIBgAZAAgTAA==.',
Cr='Creamy:BAABNQAECn8dAAIGAAgKHgouFgAaAQAGAAgKHgouFgAaAQAAAA==.Crockett:BAAANQAECgEIAQAAAA==.',
Da='Daer:BAAANQADCgQIBAAAAA==.Danielpana:BAACNQAFFH8PAAIEAAQKcBrkCQAtAQAEAAQKcBrkCQAtAQA1AAQKfyYAAgQACQoNI1MMABIDAAQACQoNI1MMABIDAAAA.Darkfyre:BAABNQAECn9DAAMaAAoKrxgTDQBYAgAaAAoKrxgTDQBYAgAEAAUKYAxIOwDPAAAAAA==.Darkraider:BAABNQAECn8gAAQbAAkKgxVgNAAAAQADAAUKPRBkcAAJAQAbAAYKGRlgNAAAAQAVAAQKrRFoSADeAAAAAA==.',
Di='Dinkledots:BAAANQADCgUIBQABNQAECgoKRgASAKQUAA==.Dinks:BAABNQAECn9GAAISAAoKpBSoTQAmAgASAAoKpBSoTQAmAgAAAA==.Dishwasher:BAABNQAECn8cAAMXAAkKGRjxSQBIAgAXAAkKAxfxSQBIAgAHAAIKNBVYHQB4AAAAAA==.',
Do='Docc:BAAANQAECgcIDAAAAA==.Doe:BAAANQADCgYIBgABNQAECgoKQgALAL8YAA==.',
Dr='Dragonfyre:BAAANQAECgQIBgAAAA==.Drood:BAAANQADCgUIBQAAAA==.',
Du='Duration:BAABNQAECn8VAAIKAAYK/AgcEAAgAQAKAAYK/AgcEAAgAQAAAA==.',
Ek='Ektyr:BAAANQAECgUIDAABNQADCggICAAOAAAAAA==.',
Em='Emiliam:BAABNQAECn8fAAQbAAoKshd+FAAdAgAbAAkKWxl+FAAdAgADAAUKuwoJVADOAAAcAAQKjhedLQChAAAAAA==.',
Er='Erdrick:BAAANQAECgQICwAAAA==.Ero:BAAANQAECggIEwAAAA==.',
Ev='Evito:BAAANQADCgUIBQAAAA==.Evërjzy:BAAANQADCggIDAAAAA==.',
Fa='Faded:BAAANQAECgMIBQAAAA==.Fatheralvin:BAAANQABCgUIDAAAAA==.',
Fe='Feronar:BAABNQAECn8sAAMGAAkKVA4tEQBnAQAGAAkKVA4tEQBnAQAFAAQKywMoIQFAAAAAAA==.',
Fl='Flowermom:BAAANQADCgQIBAAAAA==.Flume:BAAANQAECgcIDAAAAA==.',
Fr='Fromhell:BAAANQADCgEIAQAAAA==.',
Fx='Fx:BAABNQAECn9CAAMLAAoKvxh2KQCDAgALAAoKvxh2KQCDAgAWAAEKTg2ZBwEtAAAAAA==.Fxx:BAAANQAECgYIDQAAAA==.',
['Fé']='Féllgrim:BAAANQABCgQIBAAAAA==.',
['Fú']='Fúsión:BAEANQAECgEIAQABNQAECgoKKAAJAIgiAA==.',
Ga='Galedra:BAABNQAECn8sAAMMAAkKhR2AEwBrAgAMAAgKgCCAEwBrAgAZAAEKogsMkAE6AAAAAA==.Gargomash:BAAANQAECgIIAgAAAA==.',
Gi='Gin:BAAANQADCggIGgABNQAFFAUIEAABACsgAA==.',
Gj='Gjana:BAABNQAECn9IAAMdAAoKchweKQBqAgAdAAoKchweKQBqAgAeAAUK2gW+PQDLAAAAAA==.',
Go='Goma:BAAANQAECgcIDgAAAA==.Goomy:BAAANQAECgQICAAAAA==.Gorlash:BAAANQADCgYIBgAAAA==.',
Gp='Gpt:BAAANQAECgcIEwAAAA==.',
Gr='Gravemaw:BAAANQADCgcIBwAAAA==.Greenboi:BAAANQADCgcIEgAAAA==.Grimfeather:BAAANQAECgcIDwAAAA==.Grimgeth:BAABNQAECn9YAAQfAAoK1BnGIgA6AgAgAAkKixrWMgBgAgAfAAoKQBfGIgA6AgAPAAYKVhkfUAC0AQAAAA==.Grimwrath:BAABNQAECn8eAAMFAAkKoAmhugCKAQAFAAgKOgqhugCKAQAGAAIKBAb7OgAgAAABNQAECgoKWAAfANQZAA==.Grouch:BAABNQAECn9DAAIWAAoKAh0uLADNAgAWAAoKAh0uLADNAgABNQAECgoKSAAdAHIcAA==.',
Gu='Guanine:BAABNQAECn84AAMfAAoKpxqQHQBeAgAfAAoKpxqQHQBeAgAgAAYKRAldhAAOAQAAAA==.Gudeath:BAAANQAECgYIDwAAAA==.Guishin:BAAANQAECgEIAQAAAA==.Gulhain:BAAANQADCgQIBAAAAA==.Guyver:BAAANQADCgYICwAAAA==.',
He='Heidriel:BAAANQAECgQIAwAAAA==.Heontwo:BAAANQAECgIIAgAAAA==.Heshan:BAACNQAFFH8FAAIhAAIKsw3NCQCGAAAhAAIKsw3NCQCGAAA1AAQKf0IAAyEACgoEGzUFAMQCACEACgoEGzUFAMQCABIABwqzEcTGAPcBAAAA.',
Ho='Holycowza:BAAANQADCgQIAQAAAA==.Hoodwink:BAAANQADCgYIBwAAAA==.',
Im='Imortathorin:BAAANQADCggJCQAAAA==.',
In='Insanities:BAABNQAECn8mAAMHAAkKXhyCAwC0AgAHAAgK5xyCAwC0AgAXAAgKFROIXwACAgAAAA==.',
Ir='Iradakq:BAAANQAECgEIAQAAAA==.',
Ja='Jaidie:BAABNQAECn8kAAICAAkKoQakJQA8AQACAAkKoQakJQA8AQAAAA==.Jarco:BAECNQAFFH8OAAQKAAcK1BakAAD8AQAKAAYKHBqkAAD8AQAIAAIKsglYJQBUAAAJAAEKAADoHQBOAAA1AAQKfzQAAwoACgpRJHoBAHIDAAoACQraInoBAHIDAAgACgrlIt0KAMYCAAAA.',
Je='Jebussaves:BAAANQAECgEIAQAAAA==.Jeff:BAAANQADCgEIAQAAAA==.Jerlonge:BAAANQAECgEIAQAAAA==.',
Jo='Joak:BAAANQADCgIIAgAAAA==.',
Ka='Kasaar:BAAANQADCgIIAgAAAA==.',
Ki='Kitsune:BAABNQAECn8uAAMbAAkKRAjYNAD9AAADAAkKSAZ3WwBkAQAbAAYKrAnYNAD9AAAAAA==.',
Kr='Kryptix:BAABNQAECn8ZAAIXAAgKeB4mLgCwAgAXAAgKeB4mLgCwAgAAAA==.',
Ku='Kubicki:BAABNQAECn8UAAQYAAkKYxGePABGAQAYAAYKBA6ePABGAQAXAAUKBwrozQC6AAAHAAEKZBQUJwA6AAAAAA==.Kubimage:BAAANQADCgYIBgAAAA==.Kurta:BAAANQADCgEIAQAAAA==.',
La='Lastlife:BAAANQADCgYIDwAAAA==.Lastshamurai:BAAANQADCgUIBQAAAA==.Layona:BAAANQAECgYIDQAAAA==.',
Li='Linelli:BAACNQAFFH8UAAQNAAYKTCVPAACIAQANAAYKTCVPAACIAQABAAEKAACxLgBkAAACAAEKGAAtKQALAAA1AAQKfzQABA0ACQo/JgcBACgDAA0ACQo9JgcBACgDAAEABwqWH7l7ABcCAAIAAQriGUxaAEgAAAAA.',
Lo='Lobixona:BAAANQAECgYIBwAAAA==.Lowakacho:BAAANQADCgQIBAAAAA==.',
Lx='Lxrbread:BAACNQAFFH8HAAMiAAIKhgTrDABiAAAiAAIKhgTrDABiAAAjAAEKNACtGwAWAAA1AAQKf0kABCIACgqFEkAGAP0BACIACQqFEkAGAP0BACMACgp8CdIkAJoBACQAAwoBBXkyAH0AAAAA.',
['Lì']='Lìlith:BAABNQAECn8jAAIZAAkK6BmyOQB/AgAZAAkK6BmyOQB/AgABNQAFFAgIGwAQAEYdAA==.',
Ma='Maccazilla:BAAANQADCgYICgAAAA==.Magdalena:BAABNQAECn8zAAIEAAoKLyRLBACPAwAEAAoKLyRLBACPAwAAAA==.Martini:BAAANQAECgYICgAAAA==.',
Me='Meatkleaver:BAABNQAECn8YAAIfAAkKMRLNQgC5AQAfAAkKMRLNQgC5AQAAAA==.Mech:BAABNQAECn/FAAMbAAoK9iYfAACjAwAbAAoK9iYfAACjAwAcAAkKBx/MBwDfAgAAAA==.Mediumroast:BAAANQADCgcICQAAAA==.Merbs:BAAANQAECgQIBwAAAA==.',
Mo='Mochi:BAABNQAECn8hAAILAAkKxxjjTAAwAgALAAkKxxjjTAAwAgAAAA==.Mommydeath:BAAANQADCgYIBgAAAA==.Morbius:BAAANQAECggICAAAAA==.Morholt:BAAANQADCgMIAwAAAA==.Morix:BAAANQABCgcICgAAAA==.',
Na='Nanarik:BAAANQAECgEIAQAAAA==.',
Ne='Necromortas:BAABNQAECn8aAAMdAAcKCBZ9gQDiAQAdAAcKCBZ9gQDiAQAeAAEKEgPVgQAqAAAAAA==.',
Ni='Nipnaxes:BAAANQADCgIIAgAAAA==.Nira:BAAANQADCgYICgAAAA==.Niver:BAAANQAECgUIBQAAAA==.',
No='Notlrahc:BAAANQAECgQIDAAAAA==.',
Ny='Nyki:BAAANQADCgYICAAAAA==.',
Os='Oscrixi:BAAANQABCgcICAAAAA==.',
Ov='Overheat:BAAANQAECgQIBAAAAA==.',
Pa='Padriac:BAAANQAECgQIBQAAAA==.Paolinelli:BAAANQAECggIDgABNQAFFAYIFAANAEwlAA==.Pattêrn:BAAANQADCggIDQAAAA==.Paìn:BAACNQAFFH8PAAIQAAYKRRyvAwAaAgAQAAYKRRyvAwAaAgA1AAQKf20AAhAACgq8JksAAAcEABAACgq8JksAAAcEAAE1AAUUCAgbABAARh0A.',
Pe='Pedri:BAACNQAFFH8hAAQgAAUKmCZEBAA7AQAgAAUKmCZEBAA7AQAfAAQKCyAfCwAyAQAPAAEKAADbLwAAAAA1AAQKf1AAAyAACgr8Jo0AAI4DACAACgr8Jo0AAI4DAB8ABApUIDhfABsBAAAA.Pedrok:BAABNQAECn9cAAMFAAoKORbRQgA5AgAFAAoKORbRQgA5AgAUAAEKAAALTQAZAAAAAA==.',
Ph='Phael:BAAANQAECgUIBwAAAA==.',
Pi='Pinkdot:BAAANQADCgYIBwAAAA==.',
Po='Popius:BAAANQAECgQICQAAAA==.Pothtwo:BAAANQADCgUIBQAAAA==.',
Pr='Prentiss:BAAANQADCgcIDAABNQAECgUIFgADAHkDAA==.Promorph:BAAANQAECgEIAgAAAA==.',
Pu='Puups:BAAANQADCgYICAAAAA==.',
['Pì']='Pìngü:BAABNQAECn8aAAMXAAkKlxHabADXAQAXAAkKlxHabADXAQAHAAEKvwLoMAAiAAAAAA==.',
Ra='Raph:BAACNQAFFH8GAAMgAAQKagY0GwCAAAAgAAIKawY0GwCAAAAfAAIKaQYJIABCAAA1AAQKfzsAAyAACgpcIQcUABkDACAACgpcIQcUABkDAB8ABAqKFlF1AM4AAAAA.',
Re='Rednoser:BAACNQAFFH8HAAISAAMKoBIrJgDfAAASAAMKoBIrJgDfAAA1AAQKfx4AAhIACgpLFDmIAG4CABIACgpLFDmIAG4CAAAA.Redthedeer:BAAANQAECgYICAAAAA==.Redthepriest:BAAANQAECgEIAQAAAA==.Refuliya:BAAANQAECggICgAAAA==.Remmahcm:BAAANQAECggIEAAAAA==.Reverse:BAAANQADCgYIBgABNQAFFAUIBwABAEwVAA==.Rexnor:BAAANQADCgQIBAABNQAECgQICwAOAAAAAA==.',
Sa='Sagas:BAABNQAECn8wAAIlAAoKJR53BgAdAwAlAAoKJR53BgAdAwAAAA==.Sambiquira:BAAANQAECgIIAgAAAA==.Sarial:BAABNQAECn8qAAMmAAkKlSQaBACxAwAmAAkKlSQaBACxAwAQAAkKbhq+GwB5AgAAAA==.Saryeras:BAAANQADCgQIBAABNQADCggICAAOAAAAAA==.',
Sc='Scrit:BAAANQAECgQICQAAAA==.',
Se='Semrys:BAAANQAECgIIAgABNQADCggICAAOAAAAAA==.',
Si='Sil:BAABNQAECn8UAAIUAAkKwwoYHgBkAQAUAAkKwwoYHgBkAQAAAA==.',
Sk='Ska:BAABNQAECn8ZAAIdAAoKfR9aFQDOAgAdAAoKfR9aFQDOAgAAAA==.',
So='Softbutt:BAAANQADCgIIAgAAAA==.Soulreaper:BAAANQAECgIIBgABNQAECgoKQgALAL8YAA==.',
Sq='Squish:BAAANQADCgEJAQAAAA==.',
St='Staby:BAAANQADCgYIBgABNQAECgMIAwAOAAAAAA==.',
Ta='Tapechewer:BAAANQADCgUICgAAAA==.Tatax:BAAANQAECggIDAABNQAFFAQIDwAEAHAaAA==.',
Te='Tertlepaws:BAAANQAECggICAABNQAECgoKKwACAHwfAA==.Teto:BAAANQADCgYIBwAAAA==.Tetsunen:BAABNQAECn8aAAIaAAcKthe7GQBnAQAaAAcKthe7GQBnAQAAAA==.',
Th='Thralson:BAAANQADCgQIBAAAAA==.',
To='Tog:BAAANQADCgIIAgAAAA==.Toggywoggy:BAABNQAECn8bAAInAAgKkBZWBwApAgAnAAgKkBZWBwApAgAAAA==.Tortoisetoes:BAABNQAECn8rAAICAAoKfB+UCQCmAgACAAoKfB+UCQCmAgAAAA==.',
Tr='Trillex:BAAANQAECgUIAwAAAA==.',
Tu='Turok:BAAANQAECgUIBwAAAA==.Turtles:BAABNQAECn8cAAITAAoKFx/0AAC2AgATAAoKFx/0AAC2AgABNQAECgoKKwACAHwfAA==.Turtletoes:BAAANQAECgUICQABNQAECgoKKwACAHwfAA==.',
Ur='Urra:BAAANQAECggIBAAAAA==.',
Va='Valkyrie:BAAANQAECgcIBwAAAA==.',
Ve='Velo:BAAANQAECgEIAQAAAA==.Verminardy:BAAANQABCgMIBAAAAA==.',
Wa='Wanheda:BAACNQAFFH8FAAIBAAQKDRFMIgCYAAABAAQKDRFMIgCYAAA1AAQKfygAAgEACgrOIIIkAAUDAAEACgrOIIIkAAUDAAAA.Wargyu:BAACNQAFFH8PAAIFAAYKLRbsGABUAQAFAAYKLRbsGABUAQA1AAQKf18AAgUACgoUJMQPAIADAAUACgoUJMQPAIADAAAA.Watertort:BAABNQAECn+PAQMLAAoKnSELBgC4AwALAAoKnSELBgC4AwAWAAgKuRh8NQD/AQAAAA==.',
We='Weezard:BAAANQADCgYIEQABNQAECgoKSAAdAHIcAA==.',
Wo='Woobley:BAAANQADCgcICQAAAA==.',
Wy='Wyarlok:BAABNQAECn8aAAIdAAoK1hGBTgDoAQAdAAoK1hGBTgDoAQAAAA==.',
Xa='Xandraz:BAAANQADCgUIBgAAAA==.',
Yn='Ynup:BAAANQADCgcIFQAAAA==.',
Yr='Yrrygg:BAAANQADCgMIAwABNQADCgIIAwAOAAAAAA==.',
Za='Zardnax:BAAANQAECgIIAwAAAA==.',
Ze='Zel:BAAANQAECgEIAQAAAA==.Zenin:BAAANQAECgUICAABNQADCggICAAOAAAAAA==.Zenir:BAAANQAECgEIAQAAAA==.Zenjamin:BAAANQAECgYIDwABNQADCggICAAOAAAAAA==.',
Zu='Zuleika:BAABNQAECn8jAAILAAkKdh68QwBSAgALAAkKdh68QwBSAgAAAA==.',
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
