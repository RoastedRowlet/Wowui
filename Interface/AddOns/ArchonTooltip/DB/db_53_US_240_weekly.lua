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
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aardin:BAABNQAECn8yAAMBAAoKtA/0MgARAgABAAoKSwz0MgARAgACAAkKpw2JRQDPAQAAAA==.',
Ad='Adyrill:BAAANQAECgEIAQAAAA==.',
Ai='Aiaxpriest:BAAANQAECgYICwAAAA==.Ailani:BAAANQADCgIIAgAAAA==.Airnantas:BAAANQADCgEIAQABNQAECgoKHwADAMoPAA==.',
Al='Allure:BAABNQAECn8mAAMEAAoK4hUjKAC2AQAEAAoKDBQjKAC2AQAFAAMK4RymIQC2AAAAAA==.',
Am='Amadin:BAABNQAECn9TAAMGAAoK7iOAAgAGBAAGAAoK7iOAAgAGBAAHAAEKpxATiwEzAAAAAA==.Amoralibash:BAABNQAECn8fAAIDAAoKyg/JSwDeAQADAAoKyg/JSwDeAQAAAA==.',
An='Anguskhan:BAAANQADCggIFQAAAA==.Anhafal:BAAANQAECgEIAQAAAA==.',
Ao='Aoife:BAABNQAECn8+AAIGAAkK7h7tIgCaAgAGAAkK7h7tIgCaAgAAAA==.Aosin:BAABNQAECn8WAAIIAAcKVw4SpgAbAQAIAAcKVw4SpgAbAQAAAA==.',
Ap='Apocalipze:BAAANQADCgUICwAAAA==.',
Ar='Aragosa:BAAANQABCgQIBQAAAA==.Archdruid:BAAANQAECggICQAAAA==.Arileous:BAAANQAECgEIAQAAAA==.Aroes:BAAANQADCgUIBgAAAA==.Arrdy:BAAANQAECgYICwABNQAECgoKMgABALQPAA==.Artemiza:BAAANQABCgcJDgAAAA==.',
As='Ashariel:BAAANQADCgYICwAAAA==.Ashria:BAAANQAECgIIAwAAAA==.Asylum:BAABNQAECn8XAAIJAAYK+g7G0QD0AAAJAAYK+g7G0QD0AAAAAA==.',
Aw='Awwbeeph:BAAANQAECgEIAQAAAA==.',
Ay='Ayeamanoob:BAAANQABCgIIAgABNQAECgEIAgAKAAAAAA==.',
Ba='Bambiná:BAAANQADCgQIBQAAAA==.Bar:BAAANQAECgMIBAAAAA==.Batshaun:BAAANQADCgYIBgAAAA==.Bault:BAAANQAECgEIAQABNQAECgMIBAAKAAAAAA==.',
Be='Benadryl:BAABNQAECn8XAAILAAYKERcoFgC8AQALAAYKERcoFgC8AQAAAA==.',
Bh='Bhalen:BAAANQADCggIDAAAAA==.',
Bl='Blaum:BAAANQADCgMIAgAAAA==.Bloodpear:BAAANQAECgMIAwABNQAECgkJFwAMAH0XAA==.',
Br='Brakey:BAAANQAECgYIEgAAAA==.Briar:BAABNQAECn8qAAQNAAoKjA0JFgBRAQANAAkKRg4JFgBRAQAOAAgK3Qe7OwBDAQAPAAcKnQZJcgABAQAAAA==.Britnysteers:BAAANQADCgEIAQAAAA==.Bromkan:BAAANQADCgQIBAABNQAECgoKHwADAMoPAA==.Brungar:BAAANQAECggIDQAAAA==.',
Bu='Bubblybear:BAABNQAECn8hAAIQAAoKfB3yBABMAwAQAAoKfB3yBABMAwAAAA==.Bucksdk:BAABNQAECn8jAAIRAAoK1wklaABSAQARAAoK1wklaABSAQAAAA==.Buckshotheal:BAAANQAECgEIAQABNQAECgoKIwARANcJAA==.Butterworm:BAAANQAECgEIAQAAAA==.',
Ca='Castiél:BAAANQADCgYIDAAAAA==.Caín:BAAANQADCgcICgAAAA==.',
Ch='Chuckroast:BAABNQAECn8qAAISAAcKLAs/fAADAQASAAcKLAs/fAADAQAAAA==.',
Cy='Cynastus:BAABNQAECn8lAAIRAAgKDRm9LQCNAQARAAgKDRm9LQCNAQAAAA==.Cyrandalord:BAACNQAFFH8GAAITAAQKZRBPGQAVAQATAAQKZRBPGQAVAQA1AAQKfy8ABBMACgrwHb00AJUCABMACgrSHb00AJUCABQAAgrHGBMcAIYAABUAAQoAAHiNAB0AAAAA.Cyrandalorr:BAAANQAECgYICwABNQAFFAQIBgATAGUQAA==.',
Da='Danteghost:BAAANQADCgYIBgAAAA==.',
De='Deathzdemize:BAACNQAFFH8aAAQWAAgKAB+6AgAUAgAWAAYKqh+6AgAUAgAXAAEKsxuSDwBbAAARAAEKAAAEKgBOAAA1AAQKf3AABBYACgrnJjYAAAwEABYACgrnJjYAAAwEABcAAgrfJhKQAOgAABEAAQooHsO6AFIAAAAA.Demonbane:BAABNQAECn8mAAMYAAkKnw4/MADAAQAYAAgKiA4/MADAAQAEAAQK9wi/XgCVAAAAAA==.Demíse:BAAANQADCgEIAQAAAA==.',
Di='Dinduscuffin:BAAANQADCgcIBwABNQAFFAgIGgAWAAAfAA==.Dirtpear:BAABNQAECn8XAAMMAAkKfRcMVAAXAgAMAAkKfRcMVAAXAgASAAEKAAC5NwEyAAAAAA==.',
Do='Doci:BAAANQADCggIFQABNQAECgoKGQAMANoPAA==.',
Dr='Dragundeznut:BAAANQAECgMIAwABNQAFFAgIGgAWAAAfAA==.Drakythor:BAAANQAECgEIAwABNQAECgoKLQAQAFQaAA==.Dreadnought:BAAANQADCgUIBQAAAA==.Druisy:BAABNQAECn8eAAIOAAoKjSCxBACZAwAOAAoKjSCxBACZAwAAAA==.',
Dy='Dyrillin:BAABNQAECn8fAAIHAAkKZhRbiQAUAgAHAAkKZhRbiQAUAgAAAA==.',
El='Eleonna:BAAANQADCgEIAQAAAA==.',
Em='Emberblaze:BAAANQAECgUIBQAAAA==.Emiragosa:BAAANQAECgQIDQAAAA==.',
Er='Erazar:BAAANQADCgUIBQABNQAFFAQIBgATAGUQAA==.',
Et='Ethelstan:BAAANQADCgMIAwAAAA==.',
Ev='Evoker:BAACNQAFFH8HAAIZAAQKLwnxBgD7AAAZAAQKLwnxBgD7AAA1AAQKfyUAAhkACQoVHCoFAJwCABkACQoVHCoFAJwCAAE1AAUUBggGABgAfwQA.',
Ex='Exorcizim:BAAANQAECgcIBwAAAA==.',
Fa='Facethegon:BAABNQAECn9eAAMJAAoKaSG+FwDcAgAJAAoKaSG+FwDcAgAaAAoK5BgQFAC/AgAAAA==.Facethezoom:BAAANQAECgQIBAABNQAECgoKXgAJAGkhAA==.Father:BAAANQAECgQICgAAAA==.',
Fe='Feld:BAAANQADCgYIDQAAAA==.Felreaper:BAAANQADCgMIAwAAAA==.Feziwig:BAAANQADCgcIDwAAAA==.',
Fi='Fizbar:BAAANQADCgQIBAABNQAECgUIEwAKAAAAAA==.Fiztweaver:BAAANQAECgEIAQABNQAECgUIEwAKAAAAAA==.Fizzywater:BAAANQAECgUIEwAAAA==.',
Fo='Fonzo:BAAANQAECgUIBQAAAA==.Forloyn:BAAANQAECgIIBAAAAA==.',
Fr='Frozarath:BAAANQADCggICAAAAA==.Frozntempest:BAAANQADCgYIDgAAAA==.',
Ga='Galairn:BAAANQAECgQICQAAAA==.Garlatha:BAABNQAECn8rAAIbAAkKMRawCwAHAgAbAAkKMRawCwAHAgAAAA==.',
Ge='Gellicaan:BAAANQADCggIHQAAAA==.Geves:BAAANQAECgUIDwAAAA==.',
Go='Gortry:BAAANQAECggIDwAAAA==.',
Gr='Gromdred:BAAANQADCgEIAQAAAA==.Gryfter:BAAANQADCggIDAAAAA==.',
He='Hedgehog:BAAANQADCgYIBQAAAA==.Helbrecht:BAAANQADCgUIBQAAAA==.Hellgar:BAAANQAECgQIEQAAAA==.Hellraid:BAABNQAECn8mAAIPAAgKSRX8NABQAQAPAAgKSRX8NABQAQABNQAECgoKHwADAMoPAA==.',
Ho='Holysquid:BAAANQADCggIDQAAAA==.Hordebreaker:BAAANQADCggICAAAAA==.',
Hu='Humblépié:BAAANQADCgMIAwAAAA==.',
Hy='Hydrosavior:BAABNQAECn8zAAITAAoKZBuPFwAJAwATAAoKZBuPFwAJAwAAAA==.',
Il='Illbegood:BAAANQAECgEIAQAAAA==.',
Im='Impearing:BAAANQADCgcIBwABNQAECgkJFwAMAH0XAA==.',
In='Indaback:BAAANQADCgEIAQAAAA==.Initalog:BAAANQADCgUIBQAAAA==.',
It='Ithlaris:BAAANQADCgUIBQAAAA==.',
Iz='Izakura:BAAANQAECggIDAAAAA==.Izumi:BAABNQAECn8jAAIcAAkK/xfuEQCMAgAcAAkK/xfuEQCMAgABNQAECgoKIgAMAMYfAA==.',
Ja='Jab:BAACNQAFFH8OAAIRAAkK5wjqBwCGAQARAAkK5wjqBwCGAQA1AAQKfxYAAhEACQpNDdlRAOcAABEACQpNDdlRAOcAAAAA.Jamama:BAAANQADCgYICAAAAA==.Jasperr:BAABNQAECn9LAAIRAAoKsxtHEQCGAgARAAoKsxtHEQCGAgAAAA==.Jaywalker:BAAANQADCgYIBgAAAA==.',
Je='Jenai:BAAANQADCgMIBQAAAA==.',
Ji='Jigsaw:BAAANQADCgYIBgAAAA==.Jinmoso:BAAANQADCgcICwAAAA==.Jinsha:BAABNQAECn8dAAIPAAkKaxoAKwCSAQAPAAkKaxoAKwCSAQAAAA==.Jiéqu:BAABNQAECn8gAAIdAAoK+BVUDgAQAgAdAAoK+BVUDgAQAgAAAA==.',
Jo='Jojodimojo:BAAANQADCggIFQAAAA==.Joker:BAAANQADCgYICgAAAA==.Jomama:BAABNQAECn8YAAIHAAoKHgzT1gBuAQAHAAoKHgzT1gBuAQAAAA==.',
['Jö']='Jörmungandr:BAAANQADCggIHAAAAA==.',
Ka='Kaitnahar:BAAANQADCggICQABNQAECgoKHwADAMoPAA==.Kalunom:BAAANQABCggIBQAAAA==.Karasendreth:BAAANQADCgEIAQAAAA==.Katiperry:BAABNQAECn8qAAIeAAcKIg61GAAxAQAeAAcKIg61GAAxAQAAAA==.',
Kk='Kk:BAABNQAECn8rAAIMAAkKcRdpOAAhAgAMAAkKcRdpOAAhAgAAAA==.',
Ko='Korloa:BAAANQADCgcICgAAAA==.',
Ky='Kylowren:BAAANQADCgcIBgAAAA==.',
La='Laloyd:BAAANQABCgIIAgAAAA==.Lawbreaker:BAAANQAECgMIBgAAAA==.',
Le='Leafygaga:BAAANQADCgIIAgAAAA==.Leora:BAAANQADCggIDAAAAA==.',
Li='Liana:BAAANQADCgMIAwAAAA==.',
Lo='Lobotamy:BAAANQAECgUIBQAAAA==.Lockycharms:BAAANQADCggIGwAAAA==.Loremis:BAAANQADCggIHwAAAA==.Lovesmack:BAAANQAECgEIAQAAAA==.',
Lu='Lunary:BAAANQADCgUIBQABNQAFFAQIBgATAGUQAA==.Lunatari:BAAANQAECgQIBQAAAA==.',
Ma='Maal:BAAANQAECgEIAgAAAA==.Magetank:BAABNQAECn81AAIfAAgKqwq+oQBOAQAfAAgKqwq+oQBOAQAAAA==.Marche:BAABNQAECn88AAIVAAoK6iJLBQCEAwAVAAoK6iJLBQCEAwAAAA==.Mathendistus:BAAANQAECgQICAABNQAECgoKHwADAMoPAA==.',
Me='Meattwo:BAAANQADCgIIAgAAAA==.Meliôdas:BAABNQAECn8nAAIbAAkKfQtfEQBKAQAbAAkKfQtfEQBKAQAAAA==.Mendelson:BAAANQABCgIIAgABNQAECgEIAgAKAAAAAA==.Mew:BAABNQAECn8YAAMXAAoKzRpFMQBoAgAXAAgKKB5FMQBoAgAWAAgKohcqJgARAgAAAA==.',
Mi='Mirkwood:BAAANQAECgEIAQAAAA==.',
Mo='Mommy:BAAANQAECgUIDQAAAA==.Moonspinner:BAAANQADCgIIAgAAAA==.Mooädib:BAAANQAECgEIAgAAAA==.',
Mu='Musketeer:BAAANQADCgMIAwAAAA==.',
My='Mygore:BAAANQADCgEIAQAAAA==.Myrcy:BAAANQAECgEIAQAAAA==.Mysteia:BAABNQAECn8tAAIQAAoKVBr/DAC0AgAQAAoKVBr/DAC0AgAAAA==.',
['Mø']='Mørdréd:BAAANQAECgUICQAAAA==.',
Na='Naughtyhuman:BAAANQAECgEIBwAAAA==.',
Ne='Necrobijuan:BAAANQADCgcICQAAAA==.Necronimus:BAAANQAECgMIAwAAAA==.Neodragoon:BAABNQAECn8iAAMgAAkKyxDOGACYAQAgAAkKyxDOGACYAQAHAAEKZhBUhgE2AAAAAA==.Neodragoonz:BAAANQAECgYIBwABNQAECgkJIgAgAMsQAA==.',
Ni='Nihcicle:BAAANQAECgUIBwAAAA==.Nihilist:BAABNQAECn8zAAIRAAoKxxdOLgBbAgARAAoKxxdOLgBbAgAAAA==.Nihlliance:BAABNQAECn8gAAMWAAgKCA8sSwBTAQAWAAgKfg4sSwBTAQARAAUKngxjaACdAAAAAA==.Nitequilz:BAABNQAECn9AAAIMAAoKwRX4PAALAgAMAAoKwRX4PAALAgAAAA==.',
No='Noblessyou:BAAANQABCgUJCAABNQAECgEIAgAKAAAAAA==.',
Ob='Obeejoowan:BAAANQADCggIFwAAAA==.Obeewand:BAAANQADCggIGAAAAA==.Obijuan:BAAANQAECgEIAQAAAA==.',
Oh='Ohurru:BAAANQADCgUIBQAAAA==.',
Ou='Ouch:BAABNQAECn8gAAMbAAcKKg4AFQASAQAbAAcKKg4AFQASAQAIAAEKWgKmMQEZAAAAAA==.',
Pa='Pandapunch:BAABNQAECn8rAAIhAAkKCxTAHAClAQAhAAkKCxTAHAClAQAAAA==.',
Pl='Plateguy:BAAANQAECgYIEgAAAA==.',
Po='Poxx:BAABNQAECn8cAAIfAAgK6yBWWwDJAgAfAAgK6yBWWwDJAgABNQAFFAgIFAACAO8gAA==.',
Qu='Quigonjin:BAABNQAECn8sAAIJAAkK4RfcVgAGAgAJAAkK4RfcVgAGAgAAAA==.Quinci:BAAANQABCggIEwAAAA==.',
Ra='Raelynixii:BAAANQADCgcIEwAAAA==.Raistliin:BAAANQAECgQIBAAAAA==.Raksi:BAAANQADCgIIAgAAAA==.Ranker:BAAANQAECgEIAgAAAA==.Rastion:BAAANQAECgEIAwAAAA==.',
Re='Redacted:BAAANQADCggIGgAAAA==.Rend:BAAANQADCgQIBAAAAA==.',
Ri='Rills:BAAANQADCgQIBAAAAA==.',
Ro='Rokku:BAAANQADCgYJBgAAAA==.Rollepolle:BAAANQAECgIIAgABNQAFFAgIGgAWAAAfAA==.Rosdom:BAAANQABCggICQAAAA==.Ross:BAAANQAECgUIBQAAAA==.Rossini:BAAANQADCgEIAQAAAA==.Roxoglam:BAAANQADCgYIBgAAAA==.',
Ru='Rueittrebeck:BAAANQABCgYICgABNQAECgEIAgAKAAAAAA==.Rushs:BAAANQAECgEIAgAAAA==.',
Ry='Ryleigh:BAAANQAECgEIAQAAAA==.Rynron:BAAANQADCgUICAAAAA==.',
Sa='Samraj:BAABNQAECn8eAAMTAAoK+BbEJQCnAgATAAoKRxbEJQCnAgAUAAQKhBm1DwAvAQAAAA==.',
Se='Seithr:BAAANQADCgEIAQAAAA==.Selexa:BAAANQADCgIIAgAAAA==.Sempiternal:BAACNQAFFH8ZAAIGAAUKfREQDABvAQAGAAUKfREQDABvAQA1AAQKfz0AAgYACgpYFRdAAGQCAAYACgpYFRdAAGQCAAAA.Sentry:BAAANQADCgQIBAAAAA==.',
Sh='Shadowreaper:BAAANQAECgEIAQAAAA==.Shamanstu:BAAANQADCgMIAwAAAA==.Shambali:BAAANQAECgUIDQABNQAECgoKGAAHAB4MAA==.Shaunanigans:BAAANQAECggIDQAAAA==.Shaunwick:BAAANQADCgMIAwABNQAECggIDQAKAAAAAA==.Shego:BAAANQAECgUICgABNQAECgcIFgABACkkAA==.Sheltered:BAABNQAECn8mAAIHAAoKRSNbIADWAgAHAAoKRSNbIADWAgAAAA==.Shocktopus:BAACNQAFFH8MAAIMAAQKtBpQDwBbAQAMAAQKtBpQDwBbAQA1AAQKfyYAAgwACgohHZ4eAPECAAwACgohHZ4eAPECAAAA.',
Si='Silver:BAAANQAECgEIAwAAAA==.Sinakra:BAABNQAECn8fAAIHAAkKtAsuvQCiAQAHAAkKtAsuvQCiAQAAAA==.',
Sl='Slapdaddy:BAAANQAECgEIAQAAAA==.Slapdh:BAAANQADCggIDAABNQAFFAgIFAACAO8gAA==.Slaphapypapy:BAACNQAFFH8UAAMCAAgK7yB1AQBSAgACAAcKhSB1AQBSAgABAAIKYSTkEgC3AAA1AAQKf0EAAwIACgp6Jg8BAMYDAAIACgp6Jg8BAMYDAAEABAp/JJxdAEABAAAA.',
Sm='Smee:BAABNQAECn8hAAICAAcKQhL8HwDOAQACAAcKQhL8HwDOAQAAAA==.',
Sn='Snowyscat:BAABNQAECn8ZAAIIAAoKYCBzQwC/AgAIAAoKYCBzQwC/AgABNQAFFAgIGgAWAAAfAA==.',
Sp='Spirits:BAABNQAECn8iAAIMAAoKxh/6KQC7AgAMAAoKxh/6KQC7AgAAAA==.Spritz:BAABNQAECn8XAAIJAAUKBAhe9AAZAQAJAAUKBAhe9AAZAQAAAA==.',
St='Stampede:BAAANQADCggIEgAAAA==.Starshots:BAAANQADCgMIAwAAAA==.Stellara:BAAANQAECgEIAQABNQAECggIDAAKAAAAAA==.Stringbean:BAAANQAECgEIAQAAAA==.Stuey:BAAANQADCggIGgAAAA==.',
Su='Subito:BAAANQADCgEIAQAAAA==.',
Ta='Taburiel:BAAANQADCgcICgAAAA==.Tanis:BAAANQAECgMICQAAAA==.Tarstarkas:BAAANQAECgEIAQAAAA==.Taylea:BAAANQAECgEIAQAAAA==.',
Te='Temperånce:BAABNQAECn8xAAMOAAoKGw+rLwCdAQAOAAkKiAyrLwCdAQAPAAkKAAa7awAcAQAAAA==.',
Th='Thekingelvis:BAAANQAECgEIAQABNQAECgEIAgAKAAAAAA==.',
Ti='Tiled:BAAANQABCggJCgAAAA==.',
To='Toosalty:BAAANQADCgQIBAAAAA==.Toothgrinder:BAABNQAECn8qAAMiAAoK5Q9/FgCRAQAiAAoK5Q9/FgCRAQAMAAMKjAuS0QBjAAAAAA==.',
Ug='Uglycow:BAAANQAECgEIAwAAAA==.',
Ur='Urbanfries:BAAANQADCgQIBAABNQAFFAcIEgARAP4UAA==.',
Va='Varlonn:BAAANQADCggIEAAAAA==.Varr:BAAANQAECgQICAAAAA==.Vayeda:BAABNQAECn8dAAIeAAgKLCJhAwATAwAeAAgKLCJhAwATAwAAAA==.',
Ve='Velini:BAAANQAECgEIAgAAAA==.Venderic:BAAANQADCggICAAAAA==.',
Vi='Vixia:BAAANQAECgUIDwAAAA==.Viz:BAAANQAECgQIDwAAAA==.',
Vo='Voidpetal:BAAANQAECgUIBgAAAA==.Vozzert:BAAANQAECgIIAgAAAA==.',
Wh='Whatnow:BAAANQAECggICAAAAA==.Whítemane:BAAANQADCgYIBgAAAA==.',
Xa='Xantara:BAAANQABCgYIBgAAAA==.',
Yo='Yogi:BAAANQADCggICAABNQAECggICAAKAAAAAA==.Yoursalad:BAACNQAFFH8GAAIHAAUKYAHzIwB/AAAHAAUKYAHzIwB/AAA1AAQKfyYAAwcACApcD9LgAAYBAAcACAoqCtLgAAYBACAABQpEEcNHAM8AAAAA.',
Yu='Yuuka:BAABNQAECn8iAAITAAkK/yCXFAAqAwATAAkK/yCXFAAqAwAAAA==.',
Za='Zarigar:BAAANQADCgEIAQAAAA==.',
Ze='Zerin:BAAANQAECgUIDgABNQAECgoKJgAHAEUjAA==.Zeroh:BAAANQADCgcIEQAAAA==.',
Zi='Zithia:BAAANQADCggIHwAAAA==.',
Zn='Zna:BAAANQAECgQIBwAAAA==.',
Zu='Zuezes:BAAANQADCggIFQAAAA==.',
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
