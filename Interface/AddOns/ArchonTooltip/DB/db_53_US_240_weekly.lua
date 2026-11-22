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

local lookup = {'Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Hunter-BeastMastery','Unknown-Unknown','Warlock-Destruction','Shaman-Restoration','Druid-Feral','Druid-Restoration','Druid-Balance','Monk-Mistweaver','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Devourer','Evoker-Augmentation','Hunter-Marksmanship','Warrior-Fury','Evoker-Preservation','Monk-Brewmaster','Mage-Frost','Mage-Arcane','Paladin-Protection','Monk-Windwalker','Shaman-Enhancement',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aardin:BAABNQAECn80AAMBAAoKtA/0MgARAgABAAoKSwz0MgARAgACAAkKpw2ETADPAQAAAA==.',
Ad='Adyrill:BAAANQADCgYICwAAAA==.',
Ai='Aiaxpriest:BAAANQAECgYICwAAAA==.Ailani:BAAANQADCgIIAgAAAA==.Airnantas:BAAANQADCgEIAQABNQAECgoKHwADAMoPAA==.',
Al='Allure:BAABNQAECn8oAAMEAAoK8xbFKADHAQAEAAoKHRXFKADHAQAFAAMK4RymIQC2AAAAAA==.',
Am='Amadin:BAABNQAECn9TAAMGAAoK7iP4AgD+AwAGAAoK7iP4AgD+AwAHAAEKpxBZnAEyAAAAAA==.Amoralibash:BAABNQAECn8fAAIDAAoKyg9KUwDaAQADAAoKyg9KUwDaAQAAAA==.',
An='Anguskhan:BAAANQADCggIFQAAAA==.Anhafal:BAAANQADCgYIDwAAAA==.',
Ao='Aoife:BAABNQAECn9CAAIGAAoKLh5GHADXAgAGAAoKLh5GHADXAgAAAA==.Aosin:BAABNQAECn8dAAIIAAkKPxBkbwC0AQAIAAkKPxBkbwC0AQAAAA==.',
Ap='Apocalipze:BAAANQADCgUICwAAAA==.',
Ar='Aragosa:BAAANQABCgQIBQAAAA==.Archdruid:BAAANQAECggICAAAAA==.Arileous:BAAANQAECgEIAQAAAA==.Aroes:BAAANQADCgUIBgAAAA==.Arrdy:BAAANQAECgYIEAABNQAECgoKNAABALQPAA==.Artemiza:BAAANQABCgcJDgAAAA==.',
As='Ashariel:BAAANQADCgYICwAAAA==.Ashria:BAAANQAECgIIAwAAAA==.Asylum:BAABNQAECn8XAAIJAAYK+g5b3wDzAAAJAAYK+g5b3wDzAAAAAA==.',
Ay='Ayeamanoob:BAAANQABCgIIAgABNQABCgYICgAKAAAAAA==.',
Ba='Bambiná:BAAANQADCgQIBQAAAA==.Bar:BAAANQAECgMIBAAAAA==.Batshaun:BAAANQADCgYIBgAAAA==.Bault:BAAANQAECgEIAQABNQAECgMIBAAKAAAAAA==.',
Be='Benadryl:BAABNQAECn8XAAILAAYKERcoFgC8AQALAAYKERcoFgC8AQAAAA==.',
Bh='Bhalen:BAAANQADCggIDAAAAA==.',
Bl='Blaum:BAAANQADCgMIAgAAAA==.Bloodpear:BAAANQAECgMIAwABNQAECgkJFwAMAH0XAA==.',
Br='Brakey:BAAANQAECgYIEAAAAA==.Briar:BAABNQAECn8qAAQNAAoKjA3CGABPAQANAAkKRg7CGABPAQAOAAgK3Qe7OwBDAQAPAAcKnQZJcgABAQAAAA==.Britnysteers:BAAANQADCgEIAQAAAA==.Bromkan:BAAANQADCgQIBAABNQAECgoKHwADAMoPAA==.Brungar:BAAANQAECggIDQAAAA==.',
Bu='Bubblybear:BAABNQAECn8hAAIQAAoKfB2NBQBGAwAQAAoKfB2NBQBGAwAAAA==.Bucksdk:BAABNQAECn8jAAIRAAoK1wklaABSAQARAAoK1wklaABSAQAAAA==.Buckshotheal:BAAANQADCgMIAwABNQAECgoKIwARANcJAA==.Butterworm:BAAANQAECgEIAQAAAA==.',
Ca='Castiél:BAAANQADCgYIDAAAAA==.Caín:BAAANQADCgcICgAAAA==.',
Ch='Chuckroast:BAABNQAECn8qAAISAAcKLAuYhQADAQASAAcKLAuYhQADAQAAAA==.',
Cy='Cynastus:BAABNQAECn8oAAIRAAkK7Rg0JADZAQARAAkK7Rg0JADZAQAAAA==.Cyrandalord:BAACNQAFFH8GAAITAAQKZRDFHAAMAQATAAQKZRDFHAAMAQA1AAQKfy8ABBMACgrwHb00AJUCABMACgrSHb00AJUCABQAAgrHGBMcAIYAABUAAQoAAHiNAB0AAAAA.Cyrandalorr:BAAANQAECgYICwABNQAFFAQIBgATAGUQAA==.',
Da='Danteghost:BAAANQADCgYIBgAAAA==.',
De='Deathzdemize:BAACNQAFFH8cAAQWAAkKiRu6AgAUAgAWAAgKghu6AgAUAgAXAAEKsxufEQBWAAARAAEKAAAEKgBOAAA1AAQKf3AABBYACgrnJjYAAAwEABYACgrnJjYAAAwEABcAAgrfJhKQAOgAABEAAQooHsO6AFIAAAAA.Demonbane:BAABNQAECn8mAAMYAAkKnw4/MADAAQAYAAgKiA4/MADAAQAEAAQK9wgNZACVAAAAAA==.Demíse:BAAANQADCgEIAQAAAA==.',
Di='Dinduscuffin:BAAANQADCgcIBwABNQAFFAkJHAAWAIkbAA==.Dirtpear:BAABNQAECn8XAAMMAAkKfRcMVAAXAgAMAAkKfRcMVAAXAgASAAEKAAC5NwEyAAAAAA==.',
Do='Doci:BAAANQADCggIFQABNQAECgoKHQAMABMRAA==.',
Dr='Dragundeznut:BAAANQAECgMIAwABNQAFFAkJHAAWAIkbAA==.Drakythor:BAAANQAECgEIAQABNQAECgoKLQAQAFQaAA==.Dreadnought:BAAANQADCgUIBQAAAA==.Druisy:BAABNQAECn8eAAIOAAoKjSBVBQCXAwAOAAoKjSBVBQCXAwAAAA==.',
Dy='Dyrillin:BAABNQAECn8fAAIHAAkKZhRbiQAUAgAHAAkKZhRbiQAUAgAAAA==.',
El='Eleonna:BAAANQADCgEIAQAAAA==.',
Em='Emberblaze:BAAANQAECgUICQAAAA==.Emiragosa:BAAANQAECgQICwAAAA==.',
Er='Erazar:BAAANQADCgUIBQABNQAFFAQIBgATAGUQAA==.',
Et='Ethelstan:BAAANQADCgMIAwAAAA==.',
Ev='Evoker:BAACNQAFFH8HAAIZAAQKLwnxBgD7AAAZAAQKLwnxBgD7AAA1AAQKfyUAAhkACQoVHCoFAJwCABkACQoVHCoFAJwCAAE1AAUUBggGABgAfwQA.',
Ex='Exorcizim:BAAANQAECgcIDAAAAA==.',
Fa='Facethegon:BAABNQAECn9nAAMJAAoK5CH5FgDrAgAJAAoK5CH5FgDrAgAaAAoK5BgQFAC/AgAAAA==.Facethezoom:BAAANQAECgQIBAABNQAECgoKZwAJAOQhAA==.Father:BAAANQAECgQIBgAAAA==.',
Fe='Feld:BAAANQADCgYIDQAAAA==.Felreaper:BAAANQADCgMIAwAAAA==.Feziwig:BAAANQADCgcIFAAAAA==.',
Fi='Fizbar:BAAANQADCgQIBAABNQAECgUIEAAKAAAAAA==.Fiztweaver:BAAANQADCggIDgABNQAECgUIEAAKAAAAAA==.Fizzywater:BAAANQAECgUIEAAAAA==.',
Fo='Fonzo:BAAANQAECgUICQAAAA==.Forloyn:BAAANQAECgIIAgAAAA==.',
Fr='Frozarath:BAAANQADCggICAAAAA==.Frozntempest:BAAANQADCgYIDgAAAA==.',
Ga='Galairn:BAAANQAECgQICAAAAA==.Garlatha:BAABNQAECn8rAAIbAAkKMRawCwAHAgAbAAkKMRawCwAHAgAAAA==.',
Ge='Gellicaan:BAAANQADCggIJAAAAA==.Geves:BAAANQAECgQIEAAAAA==.',
Go='Gortry:BAAANQAECggIDwAAAA==.',
Gr='Gromdred:BAAANQADCgEIAQAAAA==.Gryfter:BAAANQADCggIDAAAAA==.',
He='Hedgehog:BAAANQADCgYIBQAAAA==.Helbrecht:BAAANQADCgUIBQAAAA==.Hellgar:BAAANQAECgQIDQAAAA==.Hellraid:BAABNQAECn8mAAIPAAgKSRXLQwDkAQAPAAgKSRXLQwDkAQABNQAECgoKHwADAMoPAA==.',
Ho='Holysquid:BAAANQADCggIDQAAAA==.Hordebreaker:BAAANQADCggICAAAAA==.',
Hu='Humblépié:BAAANQADCgMIAwAAAA==.',
Hy='Hydrosavior:BAABNQAECn80AAITAAoKZBuhGwD8AgATAAoKZBuhGwD8AgAAAA==.',
Il='Illbegood:BAAANQADCgQIBAAAAA==.',
Im='Impearing:BAAANQADCgcIBwABNQAECgkJFwAMAH0XAA==.',
In='Indaback:BAAANQADCgEIAQAAAA==.Initalog:BAAANQADCgUIBQAAAA==.',
It='Ithlaris:BAAANQADCgUIBQAAAA==.',
Iz='Izakura:BAAANQAECggIDAAAAA==.Izumi:BAABNQAECn8jAAIcAAkK/xfuEQCMAgAcAAkK/xfuEQCMAgABNQAECgoKJAAMANofAA==.',
Ja='Jab:BAACNQAFFH8OAAIRAAkK5wggCgB6AQARAAkK5wggCgB6AQA1AAQKfxYAAhEACQpNDcVWAOIAABEACQpNDcVWAOIAAAAA.Jamama:BAAANQADCgYICAAAAA==.Jasperr:BAABNQAECn9LAAIRAAoKsxuNEgCAAgARAAoKsxuNEgCAAgAAAA==.Jaspper:BAAANQAECgcICQABNQAECgoKSwARALMbAA==.Jaywalker:BAAANQADCgYIBgAAAA==.',
Je='Jenai:BAAANQADCgMIBQAAAA==.',
Ji='Jigsaw:BAAANQADCgYIBgAAAA==.Jinmoso:BAAANQADCgcICwAAAA==.Jinsha:BAABNQAECn8eAAIPAAoK1hkUJQDTAQAPAAoK1hkUJQDTAQAAAA==.Jiéqu:BAABNQAECn8gAAIdAAoK+BVUDgAQAgAdAAoK+BVUDgAQAgAAAA==.',
Jo='Jojodimojo:BAAANQADCggIGgAAAA==.Joker:BAAANQADCgYICgAAAA==.Jomama:BAABNQAECn8ZAAIHAAoKHgzT1gBuAQAHAAoKHgzT1gBuAQAAAA==.',
['Jö']='Jörmungandr:BAAANQADCggIHAAAAA==.',
Ka='Kaitnahar:BAAANQADCggICQABNQAECgoKHwADAMoPAA==.Kalunom:BAAANQABCggIBQAAAA==.Karasendreth:BAAANQADCgEIAQAAAA==.Katiperry:BAABNQAECn8qAAIeAAcKIg61GAAxAQAeAAcKIg61GAAxAQAAAA==.',
Kk='Kk:BAABNQAECn8yAAIMAAoKqxcbLwBlAgAMAAoKqxcbLwBlAgAAAA==.',
Ko='Korloa:BAAANQADCgcICgAAAA==.',
Ky='Kylowren:BAAANQADCgcIBgAAAA==.',
La='Laloyd:BAAANQABCgIIAgAAAA==.Lawbreaker:BAAANQAECgUICAAAAA==.',
Le='Leafygaga:BAAANQADCgIIAgAAAA==.Leora:BAAANQADCggIDAAAAA==.',
Li='Liana:BAAANQADCgMIAwAAAA==.',
Lo='Lobotamy:BAAANQAECgUICQAAAA==.Lockycharms:BAAANQADCggIGwAAAA==.Loremis:BAAANQADCggIJgAAAA==.Lovesmack:BAAANQAECgEIAQAAAA==.',
Lu='Lunary:BAAANQADCgUIBQABNQAFFAQIBgATAGUQAA==.Lunatari:BAAANQAECgQIBAAAAA==.',
Ma='Maal:BAAANQAECgEIAQAAAA==.Magetank:BAABNQAECn85AAIfAAkKqAq+kgCAAQAfAAkKqAq+kgCAAQAAAA==.Marche:BAABNQAECn9AAAIVAAoK6iJLBQCEAwAVAAoK6iJLBQCEAwAAAA==.Mathendistus:BAAANQAECgQIBwABNQAECgoKHwADAMoPAA==.',
Me='Meattwo:BAAANQADCgIIAgAAAA==.Meliôdas:BAABNQAECn8sAAIbAAkKrQ3RDwB+AQAbAAkKrQ3RDwB+AQAAAA==.Mendelson:BAAANQABCgIIAgABNQABCgYICgAKAAAAAA==.Mew:BAABNQAECn8YAAMXAAoKzRpFMQBoAgAXAAgKKB5FMQBoAgAWAAgKohf2KgAIAgAAAA==.',
Mo='Mommy:BAAANQAECgUICwAAAA==.Moo:BAAANQADCgIIAgAAAA==.Moonspinner:BAAANQADCgIIAgAAAA==.Mooädib:BAAANQADCggIKAAAAA==.',
Mu='Musketeer:BAAANQADCgMIAwAAAA==.',
My='Mygore:BAAANQADCgEIAQAAAA==.Myrcy:BAAANQADCggIFQAAAA==.Mysteia:BAABNQAECn8tAAIQAAoKVBr/DAC0AgAQAAoKVBr/DAC0AgAAAA==.',
['Mø']='Mørdréd:BAAANQAECgUICQAAAA==.',
Na='Naughtyhuman:BAAANQABCggIFwAAAA==.',
Ne='Necrobijuan:BAAANQADCgcICQAAAA==.Necronimus:BAAANQAECgMIAwAAAA==.Neodragoon:BAABNQAECn8iAAMgAAkKyxA9GwCYAQAgAAkKyxA9GwCYAQAHAAEKZhCalgE2AAAAAA==.Neodragoonz:BAAANQAECgYIBwABNQAECgkJIgAgAMsQAA==.',
Ni='Nihcicle:BAAANQAECgUIBwAAAA==.Nihilist:BAABNQAECn81AAMRAAoKxxdOLgBbAgARAAoKxxdOLgBbAgAXAAIKpw1pbQBlAAAAAA==.Nihlliance:BAABNQAECn8gAAMWAAgKCA+uUQBPAQAWAAgKfg6uUQBPAQARAAUKngw1bgCYAAAAAA==.Nitequilz:BAABNQAECn9KAAIMAAoKZhaDKgB9AgAMAAoKZhaDKgB9AgAAAA==.',
No='Noblessyou:BAAANQABCgUJCAABNQABCgYICgAKAAAAAA==.',
['Ní']='Nía:BAAANQAECgcIBQAAAA==.',
Ob='Obeejoowan:BAAANQADCggIFwAAAA==.Obeewand:BAAANQADCggIGAAAAA==.Obijuan:BAAANQADCggIQgAAAA==.',
Oh='Ohurru:BAAANQADCgUIBQAAAA==.',
Ou='Ouch:BAABNQAECn8gAAMbAAcKKg78FgARAQAbAAcKKg78FgARAQAIAAEKWgJNPQEZAAAAAA==.',
Pa='Pandapunch:BAABNQAECn8rAAIhAAkKCxRFHwClAQAhAAkKCxRFHwClAQAAAA==.',
Pl='Plateguy:BAAANQAECgYIEQAAAA==.',
Po='Poxx:BAABNQAECn8cAAIfAAgK6yBWWwDJAgAfAAgK6yBWWwDJAgABNQAFFAkJFQACAJghAA==.',
Qu='Quigonjin:BAABNQAECn8sAAIJAAkK4RdGYQAEAgAJAAkK4RdGYQAEAgAAAA==.Quinci:BAAANQABCggIEwAAAA==.',
Ra='Raelynixii:BAAANQADCgcIEwAAAA==.Raistliin:BAAANQAECgQIBAAAAA==.Raksi:BAAANQADCgIIAgAAAA==.Ranker:BAAANQADCgUICgAAAA==.Rastion:BAAANQADCggIIAAAAA==.Rayek:BAAANQADCgUIBQAAAA==.',
Re='Redacted:BAAANQADCggIIQAAAA==.Rend:BAAANQADCgQIBAAAAA==.',
Ri='Rills:BAAANQADCgQIBAAAAA==.',
Ro='Rokku:BAAANQADCgYJBgAAAA==.Rollepolle:BAAANQAECgIIAgABNQAFFAkJHAAWAIkbAA==.Rosdom:BAAANQABCggICQAAAA==.Ross:BAAANQAECgUICQAAAA==.Rossini:BAAANQADCgEIAQAAAA==.Roxoglam:BAAANQADCgYIBgAAAA==.',
Ru='Rueittrebeck:BAAANQABCgYICgABNQABCgYICgAKAAAAAA==.Rushs:BAAANQABCgYICgAAAA==.',
Ry='Ryleigh:BAAANQAECgUIBQAAAA==.Rynron:BAAANQADCgUICAAAAA==.',
Sa='Samraj:BAABNQAECn8eAAMTAAoK+BYEKwCeAgATAAoKRxYEKwCeAgAUAAQKhBm1DwAvAQAAAA==.',
Se='Seithr:BAAANQADCgEIAQAAAA==.Selexa:BAAANQADCgIIAgAAAA==.Sempiternal:BAACNQAFFH8ZAAIGAAUKfRHsDQBpAQAGAAUKfRHsDQBpAQA1AAQKfz0AAgYACgpYFRdAAGQCAAYACgpYFRdAAGQCAAAA.Sentry:BAAANQADCgQIBAAAAA==.',
Sh='Shadowreaper:BAAANQABCgQIBAAAAA==.Shamanstu:BAAANQADCgUICAAAAA==.Shambali:BAAANQAECgUIEAABNQAECgoKGQAHAB4MAA==.Shaunanigans:BAAANQAECggIEQAAAA==.Shaunwick:BAAANQADCgMIAwABNQAECggIEQAKAAAAAA==.Shego:BAAANQAECgUICAABNQAECgcIFgABACkkAA==.Sheltered:BAABNQAECn8mAAIHAAoKRSMOJQDNAgAHAAoKRSMOJQDNAgAAAA==.Shocktopus:BAACNQAFFH8MAAIMAAQKtBpQDwBbAQAMAAQKtBpQDwBbAQA1AAQKfyYAAgwACgohHZ4eAPECAAwACgohHZ4eAPECAAAA.',
Si='Silver:BAAANQAECgEIAQAAAA==.Sinakra:BAABNQAECn8fAAIHAAkKtAsuvQCiAQAHAAkKtAsuvQCiAQAAAA==.',
Sl='Slapdh:BAAANQADCggIDAABNQAFFAkJFQACAJghAA==.Slaphapypapy:BAACNQAFFH8VAAMCAAkKmCF1AQBSAgACAAcKhSB1AQBSAgABAAMKxSTkEgC3AAA1AAQKf0EAAwIACgp6Jg8BAMYDAAIACgp6Jg8BAMYDAAEABAp/JJxdAEABAAAA.',
Sm='Smee:BAABNQAECn8hAAICAAcKQhL8HwDOAQACAAcKQhL8HwDOAQAAAA==.',
Sn='Snowyscat:BAABNQAECn8ZAAIIAAoKYCBzQwC/AgAIAAoKYCBzQwC/AgABNQAFFAkJHAAWAIkbAA==.',
Sp='Spirits:BAABNQAECn8kAAIMAAoK2h+1JACfAgAMAAoK2h+1JACfAgAAAA==.Spritz:BAABNQAECn8XAAIJAAUKBAhe9AAZAQAJAAUKBAhe9AAZAQAAAA==.',
St='Stampede:BAAANQADCggIEgAAAA==.Starshots:BAAANQADCgMIAwAAAA==.Stellara:BAAANQAECgYIBgABNQAECggIDAAKAAAAAA==.Stuey:BAAANQADCggIHAAAAA==.',
Su='Subito:BAAANQADCgEIAQAAAA==.',
Ta='Taburiel:BAAANQADCgcICgAAAA==.Tanis:BAAANQAECgMICQAAAA==.Tarstarkas:BAAANQABCgQIBgAAAA==.Taylea:BAAANQADCgYIBgAAAA==.',
Te='Temperånce:BAABNQAECn81AAMOAAoKGw+rLwCdAQAOAAkKiAyrLwCdAQAPAAkKVAiNVADMAAAAAA==.',
Th='Thekingelvis:BAAANQABCgYICAABNQABCgYICgAKAAAAAA==.',
Ti='Tiled:BAAANQABCggJCgAAAA==.',
To='Toosalty:BAAANQADCgQIBAAAAA==.Toothgrinder:BAABNQAECn8qAAMiAAoK5Q9DGACPAQAiAAoK5Q9DGACPAQAMAAMKjAs52gBjAAAAAA==.',
Ur='Urbanfries:BAAANQADCgQIBAABNQAFFAgIEwARAD8XAA==.',
Va='Varlonn:BAAANQADCggIEAAAAA==.Varr:BAAANQAECgQICgAAAA==.Vayeda:BAABNQAECn8dAAIeAAgKLCJhAwATAwAeAAgKLCJhAwATAwAAAA==.',
Ve='Velini:BAAANQADCggICgAAAA==.Venderic:BAAANQADCggICAAAAA==.',
Vi='Vixia:BAAANQAECgQIEAAAAA==.Viz:BAAANQAECgQICwAAAA==.',
Vo='Voidpetal:BAAANQAECgQIBQAAAA==.Vozzert:BAAANQAECgIIAgAAAA==.',
Wh='Whatnow:BAAANQAECggICAAAAA==.Whítemane:BAAANQADCgYIBgAAAA==.',
Xa='Xantara:BAAANQABCgYIBgAAAA==.',
Yo='Yogi:BAAANQAECgQIBAABNQAECggIDAAKAAAAAA==.Yoursalad:BAACNQAFFH8GAAIHAAUKYAGZJwB9AAAHAAUKYAGZJwB9AAA1AAQKfyYAAwcACApcD0XwAAMBAAcACAoqCkXwAAMBACAABQpEEcNHAM8AAAAA.',
Yu='Yuuka:BAABNQAECn8iAAITAAkK/yCXFAAqAwATAAkK/yCXFAAqAwAAAA==.',
Za='Zarigar:BAAANQADCgEIAQAAAA==.',
Ze='Zerin:BAAANQAECgUICwABNQAECgoKJgAHAEUjAA==.Zeroh:BAAANQADCgcIEQAAAA==.',
Zi='Zithia:BAAANQADCggIJgAAAA==.',
Zn='Zna:BAAANQAECgQIBAAAAA==.',
Zu='Zuezes:BAAANQADCggIHAAAAA==.',
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
