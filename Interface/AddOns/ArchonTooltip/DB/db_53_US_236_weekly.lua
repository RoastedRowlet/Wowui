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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Priest-Discipline','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Unknown-Unknown','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Arcane','Mage-Fire','Warrior-Protection','Druid-Restoration','Priest-Holy','Priest-Shadow','Paladin-Retribution','Monk-Mistweaver','Druid-Guardian','Shaman-Restoration','Druid-Feral','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Shaman-Elemental','Mage-Frost','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Havoc','Warlock-Affliction',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=53,date='2026-10-20',data={Ag='Agp:BAACNQAFFH8HAAIBAAUKTBXoCwCSAQABAAUKTBXoCwCSAQA1AAQKfx8AAwEACQqPI1EcACYDAAEACQqPI1EcACYDAAIAAQoAAPeNADEAAAAA.',
Ah='Aharan:BAABNQAECn8aAAIDAAcKDAmeJQDPAAADAAcKDAmeJQDPAAAAAA==.',
Al='Aleria:BAAANQAECgMIAgAAAA==.',
An='Andraxy:BAAANQAECgYICAABNQAFFAQIDwAEAHAaAA==.Anielor:BAAANQABCgQIBAAAAA==.',
Ar='Aratar:BAACNQAFFH8HAAMFAAQKYxhWIQD0AAAFAAMKYxhWIQD0AAAGAAEKAADxBQBJAAA1AAQKfyEAAgUACQptHfplAF0CAAUACQptHfplAF0CAAAA.Arcadia:BAAANQAECgUICAAAAA==.Arcticheat:BAAANQAECgQIBAABNQAECgkJJgAHAF4cAA==.Arizona:BAABNQAECn8bAAQIAAkKuhJxDQBvAQAJAAYKKRCwTwCAAQAIAAcKEhBxDQBvAQAKAAMKwQf9FgB3AAAAAA==.Arja:BAAANQAECgQIBAAAAA==.Arkantos:BAAANQAECgcIEwAAAA==.',
As='Asta:BAAANQADCgYIBgAAAA==.',
At='Athius:BAAANQADCgUIBQAAAA==.',
Au='Automobeer:BAAANQADCgMIAwAAAA==.',
Aw='Awake:BAAANQAFFAEIAQAAAA==.',
Ba='Bakedsham:BAAANQADCgEIAQAAAA==.',
Be='Belandra:BAAANQADCgYIAwABNQAECgcIGgALADYhAA==.',
Bi='Biggbird:BAABNQAECn8dAAIDAAYKUxI6IwDbAAADAAYKUxI6IwDbAAAAAA==.',
Bj='Bjord:BAABNQAECn8sAAMBAAoKtR8CHAAoAwABAAoKtR8CHAAoAwACAAEK3gCAoAAaAAABNQADCggICAAMAAAAAA==.',
Bl='Blackplague:BAAANQABCgEIAQAAAA==.',
Bo='Boong:BAAANQADCgQIBAAAAA==.Bossdeath:BAAANQAECgcICwABNQAECgoKLgAFALQhAA==.Bossdierr:BAABNQAECn8fAAMNAAoKvhpxBQC8AQANAAoKvhpxBQC8AQAOAAgKNw/sEgCAAQABNQAECgoKLgAFALQhAA==.Bossdisan:BAABNQAECn8bAAMPAAoKmRxiHgCXAQAPAAoKmRxiHgCXAQAQAAMKaRI+CAChAAABNQAECgoKLgAFALQhAA==.Bossdiyi:BAABNQAECn8uAAMFAAoKtCGJEgByAwAFAAkKDiWJEgByAwARAAEKPQp2IQA4AAAAAA==.Bosswudi:BAABNQAECn8zAAMIAAkK0iUdBwC/AQAJAAUKxCUzMQAcAgAIAAcKuSUdBwC/AQABNQAECgoKLgAFALQhAA==.',
Br='Bruh:BAAANQAECgYICAAAAA==.',
Bu='Buffmw:BAEANQADCgIIAgABNQAFFAkJIQASAAcgAA==.Bunnicula:BAAANQADCgQIAgAAAA==.Buttshaman:BAAANQAECgcIEgAAAA==.',
Ca='Cazadòr:BAAANQADCggICAAAAA==.',
Ch='Choco:BAAANQAECggIEgAAAA==.Chromiepip:BAAANQADCgEIAQAAAA==.',
Co='Colt:BAABNQAECn8gAAILAAgKqh+DFABfAgALAAgKqh+DFABfAgAAAA==.Corrosiveman:BAABNQAECn8fAAMTAAkKLBcKEAD5AQATAAkKLBcKEAD5AQAUAAEKAACzegAzAAAAAA==.Cowned:BAAANQADCgYIBgABNQAFFAIIBgAVAAgTAA==.',
Cr='Creamy:BAAANQAECgUJCwAAAA==.Crockett:BAAANQADCgUIAwAAAA==.',
['Có']='Cómstock:BAAANQABCgQIBAAAAA==.',
Da='Daer:BAAANQADCgQIBAAAAA==.Danielpana:BAACNQAFFH8PAAIEAAQKcBrkCQAtAQAEAAQKcBrkCQAtAQA1AAQKfyYAAgQACQoNI1MMABIDAAQACQoNI1MMABIDAAAA.Darkfyre:BAABNQAECn8oAAIWAAkKMhQIBgCOAQAWAAkKMhQIBgCOAQAAAA==.Darkraider:BAABNQAECn8WAAQXAAcKYBJgNAAAAQADAAQKbxNkcAAJAQAXAAQKZhZgNAAAAQASAAMK2w25JwChAAAAAA==.',
Di='Dinkledots:BAAANQADCgUIBQABNQAECgkJIgAPAEoQAA==.Dinks:BAABNQAECn8iAAIPAAkKShBxGwChAQAPAAkKShBxGwChAQAAAA==.Dishwasher:BAABNQAECn8WAAMTAAkKGRjxSQBIAgATAAkKAxfxSQBIAgAHAAIKNBVYHQB4AAAAAA==.',
Do='Docc:BAAANQAECgYICgAAAA==.Doe:BAAANQADCgYIBgABNQAECggIJgAYAMsZAA==.Doii:BAAANQAECgEIAQABNQAECggIJgAYAMsZAA==.',
Dr='Dragonfyre:BAAANQAECgUIBQAAAA==.Drood:BAAANQADCgUIBQAAAA==.',
Du='Duration:BAABNQAECn8VAAIKAAYK/AgcEAAgAQAKAAYK/AgcEAAgAQAAAA==.',
Ek='Ektyr:BAAANQAECgUIDAABNQADCggICAAMAAAAAA==.',
Em='Emiliam:BAABNQAECn8WAAQXAAoKDxR+FAAdAgAXAAgKzRh+FAAdAgADAAUKuwqqIADpAAAZAAIKnw9FNgBoAAAAAA==.',
Er='Erdrick:BAAANQAECgQICgAAAA==.Ero:BAAANQAECgcICwAAAA==.',
Ev='Evito:BAAANQADCgUIBQAAAA==.Evërjzy:BAAANQADCggIDAAAAA==.',
Fa='Faded:BAAANQAECgMIAwAAAA==.Fatheralvin:BAAANQABCgUIDAAAAA==.',
Fe='Feronar:BAABNQAECn8gAAMGAAcKzAycEgB4AQAGAAcKzAycEgB4AQAFAAQKywP5tABHAAAAAA==.',
Fl='Flowermom:BAAANQADCgQIBAAAAA==.Flume:BAAANQAECgcIDAAAAA==.',
Fx='Fx:BAABNQAECn8mAAIYAAgKyxnWEQDIAQAYAAgKyxnWEQDIAQAAAA==.',
['Fú']='Fúsión:BAEANQAECgEIAQABNQAECgoKGwAJAPIhAA==.',
Ga='Galedra:BAABNQAECn8aAAILAAcKNiGAEwBrAgALAAcKNiGAEwBrAgAAAA==.Gargomash:BAAANQAECgIIAgAAAA==.',
Gi='Gin:BAAANQADCggIGgABNQAFFAMIBgABAO0dAA==.',
Gj='Gjana:BAABNQAECn84AAMaAAoKHhr4CAAWAgAaAAoKHhr4CAAWAgAbAAUK2gW+PQDLAAAAAA==.',
Go='Goma:BAAANQAECgUIBQAAAA==.Goomy:BAAANQAECgQIBwAAAA==.Gorlash:BAAANQADCgYIBgAAAA==.',
Gp='Gpt:BAAANQADCgMIBAAAAA==.',
Gr='Gravemaw:BAAANQADCgcIBwAAAA==.Greenboi:BAAANQADCgcIEgAAAA==.Grimfeather:BAAANQAECgcIDwAAAA==.Grimgeth:BAABNQAECn86AAQcAAoKDRjWMgBgAgAcAAkKixrWMgBgAgAdAAYKVhkfUAC0AQAeAAkK/w9WRgCmAQAAAA==.Grimwrath:BAABNQAECn8XAAMFAAkK4wihugCKAQAFAAgKXgmhugCKAQAGAAIKBAZpGQAkAAABNQAECgoKOgAcAA0YAA==.Grouch:BAABNQAECn81AAIfAAoKBBzfEwB6AQAfAAoKBBzfEwB6AQABNQAECgoKOAAaAB4aAA==.',
Gu='Guanine:BAABNQAECn8jAAMeAAoKixC4BwDbAQAeAAoKixC4BwDbAQAcAAYKRAldhAAOAQAAAA==.Gudeath:BAAANQAECgYIDwAAAA==.Guishin:BAAANQAECgEIAQAAAA==.Guyver:BAAANQADCgYICwAAAA==.',
He='Heidriel:BAAANQADCgUIBwAAAA==.Heontwo:BAAANQAECgIIAgAAAA==.Heshan:BAABNQAECn83AAMgAAkK7Rs1BQDEAgAgAAkK7Rs1BQDEAgAPAAcKsxHExgD3AQAAAA==.',
Ho='Hoodwink:BAAANQADCgYIBwAAAA==.',
Im='Imortathorin:BAAANQADCggJCQAAAA==.',
In='Insanities:BAABNQAECn8mAAMHAAkKXhyCAwC0AgAHAAgK5xyCAwC0AgATAAgKFROIXwACAgAAAA==.',
Ja='Jaidie:BAAANQAECgcIEQAAAA==.Jarco:BAECNQAFFH8NAAQKAAYKHBqkAAD8AQAKAAYKHBqkAAD8AQAJAAEKAADoHQBOAAAIAAEKAAAwEQAAAAA1AAQKfyYAAwoACgrPI3oBAHIDAAoACQraInoBAHIDAAgACgo3Ht0KAMYCAAAA.',
Je='Jebussaves:BAAANQADCggICQAAAA==.Jeff:BAAANQADCgEIAQAAAA==.Jerlonge:BAAANQAECgEIAQAAAA==.',
Jo='Joak:BAAANQADCgIIAgAAAA==.',
Ka='Kaidou:BAABNQAFFH8HAAIaAAUK3hlwDwCIAQAaAAUK3hlwDwCIAQAAAA==.Kasaar:BAAANQADCgIIAgAAAA==.',
Ki='Kitsune:BAABNQAECn8nAAMXAAkKRAjYNAD9AAADAAkKSAZ3WwBkAQAXAAYKrAnYNAD9AAAAAA==.',
Kr='Kryptix:BAABNQAECn8ZAAITAAgKeB4mLgCwAgATAAgKeB4mLgCwAgAAAA==.',
Ku='Kubicki:BAAANQAECgcIEAAAAA==.Kubimage:BAAANQADCgYIBgAAAA==.Kurta:BAAANQADCgEIAQAAAA==.',
La='Lastlife:BAAANQADCgUIDgAAAA==.Lastshamurai:BAAANQADCgUIBQAAAA==.Layona:BAAANQAECgYIDQAAAA==.',
Li='Linelli:BAACNQAFFH8UAAQhAAYKTCUKAADMAQAhAAYKTCUKAADMAQABAAEKAACxLgBkAAACAAEKGAAtKQALAAA1AAQKfyMAAyEACQpcIgEBAIEDACEACQpcIgEBAIEDAAEABwrlG7l7ABcCAAAA.',
Lo='Lobixona:BAAANQAECgEIAQAAAA==.Lowakacho:BAAANQADCgQIBAAAAA==.',
Lx='Lxrbread:BAABNQAECn8nAAQiAAkKtAbSJACaAQAiAAkKtAbSJACaAQAjAAYKoxKvDgBaAQAkAAMKAQV5MgB9AAAAAA==.',
['Lì']='Lìlith:BAAANQAECgQIBAABNQAFFAYIDwANAEUcAA==.',
Ma='Maccazilla:BAAANQADCgYICgAAAA==.Magdalena:BAABNQAECn8jAAIEAAkKPyNLBACPAwAEAAkKPyNLBACPAwABNQAECgkJHQAFACUdAA==.Martini:BAAANQAECgQICAAAAA==.',
Me='Meatkleaver:BAABNQAECn8WAAIeAAgKGRPNQgC5AQAeAAgKGRPNQgC5AQAAAA==.Mech:BAABNQAECn+IAAMXAAoK5SYHAACnAwAXAAoK5SYHAACnAwAZAAgK4h/MBwDfAgAAAA==.Mediumroast:BAAANQADCgcICQAAAA==.Merbs:BAAANQAECgQIBwAAAA==.',
Mo='Mochi:BAABNQAECn8eAAIYAAkKexjjTAAwAgAYAAkKexjjTAAwAgAAAA==.Mommydeath:BAAANQADCgYIBgAAAA==.Morbius:BAAANQAECggICAAAAA==.Morholt:BAAANQADCgMIAwAAAA==.',
Ne='Necromortas:BAABNQAECn8aAAMaAAcKCBZ9gQDiAQAaAAcKCBZ9gQDiAQAbAAEKEgPVgQAqAAAAAA==.',
Ni='Nipnaxes:BAAANQADCgIIAgAAAA==.Nira:BAAANQADCgYICgAAAA==.',
No='Notlrahc:BAAANQAECgQIDAAAAA==.',
Ny='Nyki:BAAANQADCgYICAAAAA==.',
Os='Oscrixi:BAAANQABCgcICAAAAA==.',
Pa='Padriac:BAAANQADCggICwAAAA==.Paolinelli:BAAANQAECggICwABNQAFFAYIFAAhAEwlAA==.Pattêrn:BAAANQADCggIDQAAAA==.Paìn:BAACNQAFFH8PAAINAAYKRRzPAQAyAQANAAYKRRzPAQAyAQA1AAQKf1gAAg0ACgqLJksAAAcEAA0ACgqLJksAAAcEAAAA.',
Pe='Pedri:BAACNQAFFH8SAAMcAAUKmiH5CgBfAQAcAAQK3ib5CgBfAQAeAAQKCyAfCwAyAQA1AAQKfzgAAxwACgpLJnQHAIkDABwACgpLJnQHAIkDAB4AAgpwGOCNAH8AAAAA.Pedrok:BAABNQAECn81AAMFAAoKiwtbEgDFAQAFAAoKiwtbEgDFAQARAAEKAAALTQAZAAAAAA==.',
Ph='Phael:BAAANQAECgMIBAAAAA==.',
Pi='Pinkdot:BAAANQADCgYIBwAAAA==.',
Po='Popius:BAAANQAECgQICQAAAA==.Pothtwo:BAAANQADCgUIBQAAAA==.',
Pr='Prentiss:BAAANQADCgcIDAABNQAECgQIBAAMAAAAAA==.Promorph:BAAANQAECgEIAgAAAA==.',
Pu='Puups:BAAANQADCgYICAAAAA==.',
['Pì']='Pìngü:BAABNQAECn8aAAMTAAkKlxHabADXAQATAAkKlxHabADXAQAHAAEKvwLoMAAiAAAAAA==.',
Ra='Raph:BAABNQAECn8rAAIcAAkKgiAHFAAZAwAcAAkKgiAHFAAZAwAAAA==.',
Re='Rednoser:BAABNQAECn8WAAIPAAoKlA85iABuAgAPAAoKlA85iABuAgAAAA==.Redthepriest:BAAANQAECgEIAQAAAA==.Remmahcm:BAAANQAECggIDgAAAA==.Reverse:BAAANQADCgYIBgABNQAFFAUIBwABAEwVAA==.Rexnor:BAAANQADCgQIBAABNQAECgQICgAMAAAAAA==.',
Sa='Sagas:BAABNQAECn8sAAIlAAoKJR53BgAdAwAlAAoKJR53BgAdAwAAAA==.Sambiquira:BAAANQAECgIIAgAAAA==.Sarial:BAABNQAECn8qAAMmAAkKlSQaBACxAwAmAAkKlSQaBACxAwANAAkKbhq+GwB5AgAAAA==.Saryeras:BAAANQADCgQIBAABNQADCggICAAMAAAAAA==.',
Sc='Scrit:BAAANQAECgQICQAAAA==.',
Si='Sil:BAAANQAECgcIEAAAAA==.',
Sk='Ska:BAAANQAECgIIBAAAAA==.',
So='Softbutt:BAAANQADCgIIAgAAAA==.Soulreaper:BAAANQADCgcJDgABNQAECggIJgAYAMsZAA==.',
Sq='Squish:BAAANQADCgEJAQAAAA==.',
St='Staby:BAAANQADCgYIBgABNQAECgMIAwAMAAAAAA==.',
Ta='Tapechewer:BAAANQADCgUICgAAAA==.Tatax:BAAANQAECggIDAABNQAFFAQIDwAEAHAaAA==.',
Te='Tertlepaws:BAAANQAECggICAABNQAECggIGQACADIXAA==.Teto:BAAANQADCgYIBwAAAA==.Tetsunen:BAAANQAECgUIEQAAAA==.',
Th='Thralson:BAAANQADCgQIBAAAAA==.',
To='Tog:BAAANQADCgIIAgAAAA==.Toggywoggy:BAABNQAECn8aAAInAAgKkBZWBwApAgAnAAgKkBZWBwApAgAAAA==.Tortoisetoes:BAABNQAECn8ZAAICAAgKMhdHBQCdAQACAAgKMhdHBQCdAQAAAA==.',
Tr='Trillex:BAAANQAECgIIAgAAAA==.',
Tu='Turok:BAAANQAECgUIBwAAAA==.Turtles:BAAANQAECgYIBwABNQAECggIGQACADIXAA==.',
Ur='Urra:BAAANQAECggIBAAAAA==.',
Ve='Velo:BAAANQAECgEIAQAAAA==.Verminardy:BAAANQABCgMIBAAAAA==.',
Wa='Wanheda:BAABNQAECn8iAAIBAAoK0h2CJAAFAwABAAoK0h2CJAAFAwAAAA==.Wargyu:BAACNQAFFH8OAAIFAAUKzRPsGABUAQAFAAUKzRPsGABUAQA1AAQKf08AAgUACgr2IMQPAIADAAUACgr2IMQPAIADAAAA.Watertort:BAABNQAECn+1AAMYAAkKkiIcAQCQAwAYAAkKkiIcAQCQAwAfAAMKTAoW/ACaAAAAAA==.',
We='Weezard:BAAANQADCgYIEQABNQAECgoKOAAaAB4aAA==.',
Wo='Woobley:BAAANQADCgcICQAAAA==.',
Wy='Wyarlok:BAAANQAECgcICgAAAA==.',
Xa='Xandraz:BAAANQADCgEIAQAAAA==.',
Yn='Ynup:BAAANQADCgcIFQAAAA==.',
Za='Zardnax:BAAANQAECgIIAgAAAA==.',
Ze='Zel:BAAANQADCgIIAgAAAA==.Zenin:BAAANQAECgUICAABNQADCggICAAMAAAAAA==.Zenjamin:BAAANQAECgEIAQABNQADCggICAAMAAAAAA==.Zenu:BAAANQADCggICAAAAA==.',
Zu='Zuleika:BAABNQAECn8WAAIYAAkKYR0nFwCdAQAYAAkKYR0nFwCdAQAAAA==.',
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
