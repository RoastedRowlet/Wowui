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

local lookup = {'Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Warlock-Destruction','Shaman-Restoration','Druid-Feral','Druid-Restoration','Druid-Balance','Monk-Mistweaver','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Retribution','Evoker-Augmentation','Hunter-Marksmanship','Warrior-Fury','Evoker-Preservation','Monk-Brewmaster','Mage-Frost','Mage-Arcane','Paladin-Protection','Warrior-Arms','Monk-Windwalker','Shaman-Enhancement',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aardin:BAABNQAECn8yAAMBAAoKtA/0MgARAgABAAoKSwz0MgARAgACAAkKpw2XPADGAQAAAA==.',
Ad='Adyrill:BAAANQADCgYICwAAAA==.',
Ai='Aiaxpriest:BAAANQAECgUIBQAAAA==.Ailani:BAAANQADCgIIAgAAAA==.Airnantas:BAAANQADCgEIAQABNQAECgoKHQADAMoPAA==.',
Al='Allure:BAABNQAECn8hAAMEAAkKFRYCLwBfAQAEAAkK+xMCLwBfAQAFAAMK4RymIQC2AAAAAA==.',
Am='Amadin:BAABNQAECn9OAAIGAAoKsiILBADJAwAGAAoKsiILBADJAwAAAA==.Amoralibash:BAABNQAECn8dAAIDAAoKyg8JQgDbAQADAAoKyg8JQgDbAQAAAA==.',
An='Anguskhan:BAAANQADCggIFQAAAA==.Anhafal:BAAANQADCgYIDwAAAA==.',
Ao='Aoife:BAABNQAECn82AAIGAAgK3x/AJwBeAgAGAAgK3x/AJwBeAgAAAA==.Aosin:BAAANQAECgYIDAABNQAECgcIDgAHAAAAAA==.',
Ap='Apocalipze:BAAANQADCgUICwAAAA==.',
Ar='Aragosa:BAAANQABCgQIBQAAAA==.Archdruid:BAAANQAECggICAAAAA==.Arileous:BAAANQAECgEIAQAAAA==.Aroes:BAAANQADCgUIBgAAAA==.Arrdy:BAAANQAECgUIBQABNQAECgoKMgABALQPAA==.Artemiza:BAAANQABCgcJDgAAAA==.',
As='Ashariel:BAAANQADCgYICwAAAA==.Ashria:BAAANQAECgIIAgAAAA==.Asylum:BAABNQAECn8WAAIIAAUKkw8o2gC6AAAIAAUKkw8o2gC6AAAAAA==.',
Ay='Ayeamanoob:BAAANQABCgIIAgABNQABCgYICgAHAAAAAA==.',
Ba='Bambiná:BAAANQADCgQIBQAAAA==.Bar:BAAANQAECgMIBAAAAA==.Batshaun:BAAANQADCgYIBgAAAA==.Bault:BAAANQAECgEIAQABNQAECgMIBAAHAAAAAA==.',
Be='Benadryl:BAABNQAECn8XAAIJAAYKERcoFgC8AQAJAAYKERcoFgC8AQAAAA==.',
Bh='Bhalen:BAAANQADCggIDAAAAA==.',
Bl='Bloodpear:BAAANQAECgMIAwABNQAECgkJFwAKAH0XAA==.',
Br='Brakey:BAAANQAECgYIEAAAAA==.Briar:BAABNQAECn8qAAQLAAoKjA1vEgBUAQALAAkKRg5vEgBUAQAMAAgK3Qe7OwBDAQANAAcKnQZJcgABAQAAAA==.Britnysteers:BAAANQADCgEIAQAAAA==.Bromkan:BAAANQADCgQIBAABNQAECgoKHQADAMoPAA==.Brungar:BAAANQAECggIDQAAAA==.',
Bu='Bubblybear:BAABNQAECn8ZAAIOAAgKwxukCQB4AgAOAAgKwxukCQB4AgAAAA==.Bucksdk:BAABNQAECn8eAAIPAAoK1wklaABSAQAPAAoK1wklaABSAQAAAA==.Buckshotheal:BAAANQADCgMIAwABNQAECgoKHgAPANcJAA==.Butterworm:BAAANQAECgEIAQAAAA==.',
Ca='Castiél:BAAANQADCgYIDAAAAA==.Caín:BAAANQADCgcICgAAAA==.',
Ch='Chuckroast:BAABNQAECn8jAAIQAAYKxAodhgDJAAAQAAYKxAodhgDJAAAAAA==.',
Cy='Cynastus:BAABNQAECn8jAAIPAAgKFxhmKwCAAQAPAAgKFxhmKwCAAQAAAA==.Cyrandalord:BAACNQAFFH8GAAIRAAQKZRBeFQAeAQARAAQKZRBeFQAeAQA1AAQKfy8ABBEACgrwHb00AJUCABEACgrSHb00AJUCABIAAgrHGBMcAIYAABMAAQoAAHiNAB0AAAAA.Cyrandalorr:BAAANQAECgYICwABNQAFFAQIBgARAGUQAA==.',
Da='Danteghost:BAAANQADCgYIBgAAAA==.',
De='Deathzdemize:BAACNQAFFH8aAAQUAAgKAB+6AgAUAgAUAAYKqh+6AgAUAgAVAAEKsxs8DQBfAAAPAAEKAAAEKgBOAAA1AAQKf3AABBQACgrnJjYAAAwEABQACgrnJjYAAAwEABUAAgrfJhKQAOgAAA8AAQooHsO6AFIAAAAA.Demonbane:BAABNQAECn8mAAMWAAkKnw4/MADAAQAWAAgKiA4/MADAAQAEAAQK9wgBWACPAAAAAA==.Demíse:BAAANQADCgEIAQAAAA==.',
Di='Dinduscuffin:BAAANQADCgcIBwABNQAFFAgIGgAUAAAfAA==.Dirtpear:BAABNQAECn8XAAMKAAkKfRcMVAAXAgAKAAkKfRcMVAAXAgAQAAEKAAC5NwEyAAAAAA==.',
Do='Doci:BAAANQADCggIFQABNQAECggIEQAHAAAAAA==.',
Dr='Dragundeznut:BAAANQAECgMIAwABNQAFFAgIGgAUAAAfAA==.Drakythor:BAAANQAECgEIAQABNQAECgoKLQAOAFQaAA==.Dreadnought:BAAANQADCgUIBQAAAA==.Druisy:BAABNQAECn8ZAAIMAAkKByC4BwArAwAMAAkKByC4BwArAwAAAA==.',
Dy='Dyrillin:BAABNQAECn8fAAIXAAkKZhRbiQAUAgAXAAkKZhRbiQAUAgAAAA==.',
El='Eleonna:BAAANQADCgEIAQAAAA==.',
Em='Emberblaze:BAAANQADCgcIDAAAAA==.Emiragosa:BAAANQAECgUIBwAAAA==.',
Er='Erazar:BAAANQADCgUIBQABNQAFFAQIBgARAGUQAA==.',
Et='Ethelstan:BAAANQADCgMIAwAAAA==.',
Ev='Evoker:BAACNQAFFH8HAAIYAAQKLwnxBgD7AAAYAAQKLwnxBgD7AAA1AAQKfyUAAhgACQoVHCoFAJwCABgACQoVHCoFAJwCAAE1AAUUBQgFABYA+AQA.',
Ex='Exorcizim:BAAANQAECgEIAQAAAA==.',
Fa='Facethegon:BAABNQAECn9VAAMIAAoKoCC+JACCAgAZAAkKaxoQFAC/AgAIAAkKtyG+JACCAgAAAA==.Facethezoom:BAAANQAECgQIBAABNQAECgoKVQAIAKAgAA==.Father:BAAANQAECgQIBgAAAA==.',
Fe='Feld:BAAANQADCgYIDQAAAA==.Felreaper:BAAANQADCgMIAwAAAA==.Feziwig:BAAANQADCgYIDgAAAA==.',
Fi='Fizbar:BAAANQADCgQIBAABNQAECgUIEAAHAAAAAA==.Fiztweaver:BAAANQADCggIDgABNQAECgUIEAAHAAAAAA==.Fizzywater:BAAANQAECgUIEAAAAA==.',
Fo='Fonzo:BAAANQADCgcICgAAAA==.Forloyn:BAAANQAECgIIAgAAAA==.',
Fr='Frozarath:BAAANQADCggICAAAAA==.Frozntempest:BAAANQADCgYIDgAAAA==.',
Ga='Galairn:BAAANQAECgQICAAAAA==.Garlatha:BAABNQAECn8rAAIaAAkKMRbTCQC1AQAaAAkKMRbTCQC1AQAAAA==.',
Ge='Gellicaan:BAAANQADCgcIHAAAAA==.Geves:BAAANQAECgUIDAAAAA==.',
Go='Gortry:BAAANQAECggIEAAAAA==.',
Gr='Gromdred:BAAANQADCgEIAQAAAA==.Gryfter:BAAANQADCggIDAAAAA==.',
He='Hedgehog:BAAANQADCgYIBQAAAA==.Helbrecht:BAAANQADCgUIBQAAAA==.Hellgar:BAAANQAECgQIDQAAAA==.Hellraid:BAABNQAECn8mAAINAAgKSRVpLwBRAQANAAgKSRVpLwBRAQABNQAECgoKHQADAMoPAA==.',
Ho='Holysquid:BAAANQADCggIDQAAAA==.Hordebreaker:BAAANQADCggICAAAAA==.',
Hu='Humblépié:BAAANQADCgMIAwAAAA==.',
Hy='Hydrosavior:BAABNQAECn8uAAIRAAoK1xlUGADnAgARAAoK1xlUGADnAgAAAA==.',
Il='Illbegood:BAAANQADCgQIBAAAAA==.',
Im='Impearing:BAAANQADCgcIBwABNQAECgkJFwAKAH0XAA==.',
In='Indaback:BAAANQADCgEIAQAAAA==.Initalog:BAAANQADCgUIBQAAAA==.',
It='Ithlaris:BAAANQADCgUIBQAAAA==.',
Iz='Izakura:BAAANQAECgYIBgAAAA==.Izumi:BAABNQAECn8jAAIbAAkK/xfuEQCMAgAbAAkK/xfuEQCMAgABNQAECgoKHwAKALMfAA==.',
Ja='Jab:BAABNQAECn8VAAIPAAgKCg65cQAuAQAPAAgKCg65cQAuAQAAAA==.Jamama:BAAANQADCgYICAAAAA==.Jasperr:BAABNQAECn9CAAIPAAoKrRpEEgBiAgAPAAoKrRpEEgBiAgAAAA==.Jaywalker:BAAANQADCgYIBgAAAA==.',
Je='Jenai:BAAANQADCgMIBQAAAA==.',
Ji='Jigsaw:BAAANQADCgYIBgAAAA==.Jinmoso:BAAANQADCgcICwAAAA==.Jinsha:BAABNQAECn8dAAINAAkKaxrPJQCXAQANAAkKaxrPJQCXAQAAAA==.Jiéqu:BAABNQAECn8dAAIcAAkKVBZUDgAQAgAcAAkKVBZUDgAQAgAAAA==.',
Jo='Jojodimojo:BAAANQADCgcIFAAAAA==.Joker:BAAANQADCgYICgAAAA==.Jomama:BAABNQAECn8UAAIXAAkKXAvT1gBuAQAXAAkKXAvT1gBuAQAAAA==.',
['Jö']='Jörmungandr:BAAANQADCgcIGwAAAA==.',
Ka='Kaitnahar:BAAANQADCggICQABNQAECgoKHQADAMoPAA==.Kalunom:BAAANQABCggIBQAAAA==.Karasendreth:BAAANQADCgEIAQAAAA==.Katiperry:BAABNQAECn8jAAIdAAYKmBC1GAAxAQAdAAYKmBC1GAAxAQAAAA==.',
Kk='Kk:BAABNQAECn8kAAIKAAgKsRffRQDJAQAKAAgKsRffRQDJAQAAAA==.',
Ko='Korloa:BAAANQADCgcICAAAAA==.',
Ky='Kylowren:BAAANQADCgcIBgAAAA==.',
La='Laloyd:BAAANQABCgIIAgAAAA==.Lawbreaker:BAAANQAECgMIBQAAAA==.',
Le='Leafygaga:BAAANQADCgIIAgAAAA==.Leora:BAAANQADCggIDAAAAA==.',
Li='Liana:BAAANQADCgMIAwAAAA==.',
Lo='Lobotamy:BAAANQADCgcIFQAAAA==.Lockycharms:BAAANQADCgcIGgAAAA==.Loremis:BAAANQADCgcIHgAAAA==.',
Lu='Lunary:BAAANQADCgUIBQABNQAFFAQIBgARAGUQAA==.Lunatari:BAAANQAECgQIBAAAAA==.',
Ma='Maal:BAAANQAECgEIAQAAAA==.Magetank:BAABNQAECn8yAAIeAAgKqwqolgBKAQAeAAgKqwqolgBKAQAAAA==.Marche:BAABNQAECn82AAITAAoK6iJLBQCEAwATAAoK6iJLBQCEAwAAAA==.Mathendistus:BAAANQAECgQIBwABNQAECgoKHQADAMoPAA==.',
Me='Meattwo:BAAANQADCgIIAgAAAA==.Meliôdas:BAABNQAECn8iAAIaAAkK8wpLDwBEAQAaAAkK8wpLDwBEAQAAAA==.Mendelson:BAAANQABCgIIAgABNQABCgYICgAHAAAAAA==.Mew:BAAANQAECggIDwAAAA==.',
Mo='Mommy:BAAANQAECgUICwAAAA==.Moonspinner:BAAANQADCgIIAgAAAA==.Mooädib:BAAANQADCggIKAAAAA==.',
Mu='Musketeer:BAAANQADCgMIAwAAAA==.',
My='Mygore:BAAANQADCgEIAQAAAA==.Myrcy:BAAANQADCggIFQAAAA==.Mysteia:BAABNQAECn8tAAIOAAoKVBr/DAC0AgAOAAoKVBr/DAC0AgAAAA==.',
['Mø']='Mørdréd:BAAANQAECgUICQAAAA==.',
Na='Naughtyhuman:BAAANQABCggIFwAAAA==.',
Ne='Necrobijuan:BAAANQADCgcICQAAAA==.Necronimus:BAAANQAECgMIAwAAAA==.Neodragoon:BAABNQAECn8iAAMfAAkKyxD3FACkAQAfAAkKyxD3FACkAQAXAAEKZhC4aAE3AAAAAA==.Neodragoonz:BAAANQAECgYIBwABNQAECgkJIgAfAMsQAA==.',
Ni='Nihcicle:BAAANQAECgUIBwAAAA==.Nihilist:BAABNQAECn8zAAIPAAoKxxdOLgBbAgAPAAoKxxdOLgBbAgAAAA==.Nihlliance:BAABNQAECn8cAAMUAAcKbQ4EUgAQAQAUAAcKzA0EUgAQAQAPAAUKngxQYACfAAAAAA==.Nitequilz:BAABNQAECn83AAIKAAkKnBUpRADRAQAKAAkKnBUpRADRAQAAAA==.',
No='Noblessyou:BAAANQABCgUJCAABNQABCgYICgAHAAAAAA==.',
Ob='Obeejoowan:BAAANQADCggIFwAAAA==.Obeewand:BAAANQADCggIGAAAAA==.Obijuan:BAAANQADCggIQgAAAA==.',
Oh='Ohurru:BAAANQADCgUIBQAAAA==.',
Ou='Ouch:BAABNQAECn8eAAMaAAcKKg4WEgAVAQAaAAcKKg4WEgAVAQAgAAEKWgKTIAEZAAAAAA==.',
Pa='Pandapunch:BAABNQAECn8rAAIhAAkKCxSrGQCmAQAhAAkKCxSrGQCmAQAAAA==.',
Pl='Plateguy:BAAANQAECgYIEQAAAA==.',
Po='Poxx:BAABNQAECn8cAAIeAAgK6yBWWwDJAgAeAAgK6yBWWwDJAgABNQAFFAgIFAACAO8gAA==.',
Qu='Quigonjin:BAABNQAECn8jAAIIAAkKAxQjZwCuAQAIAAkKAxQjZwCuAQAAAA==.Quinci:BAAANQABCggIEwAAAA==.',
Ra='Raelynixii:BAAANQADCgcIEwAAAA==.Raistliin:BAAANQAECgQIBAAAAA==.Raksi:BAAANQADCgIIAgAAAA==.Ranker:BAAANQADCgUICgAAAA==.Rastion:BAAANQADCgcIHQAAAA==.',
Re='Redacted:BAAANQADCgcIGQAAAA==.Rend:BAAANQADCgQIBAAAAA==.',
Ri='Rills:BAAANQADCgQIBAAAAA==.',
Ro='Rokku:BAAANQADCgYJBgAAAA==.Rollepolle:BAAANQAECgIIAgABNQAFFAgIGgAUAAAfAA==.Rosdom:BAAANQABCggICQAAAA==.Rossini:BAAANQADCgEIAQAAAA==.Roxoglam:BAAANQADCgYIBgAAAA==.',
Ru='Rueittrebeck:BAAANQABCgYICgABNQABCgYICgAHAAAAAA==.Rushs:BAAANQABCgYICgAAAA==.',
Ry='Ryleigh:BAAANQADCgQIBAAAAA==.Rynron:BAAANQADCgUICAAAAA==.',
Sa='Samraj:BAAANQAECggIEgAAAA==.',
Se='Seithr:BAAANQADCgEIAQAAAA==.Selexa:BAAANQADCgIIAgAAAA==.Sempiternal:BAACNQAFFH8VAAIGAAUKyRCACgBsAQAGAAUKyRCACgBsAQA1AAQKfzwAAgYACgpYFRdAAGQCAAYACgpYFRdAAGQCAAAA.Sentry:BAAANQADCgQIBAAAAA==.',
Sh='Shadowreaper:BAAANQABCgQIBAAAAA==.Shamanstu:BAAANQADCgMIAwAAAA==.Shambali:BAAANQAECgUICAABNQAECgkJFAAXAFwLAA==.Shaunanigans:BAAANQAECgcIBgAAAA==.Shaunwick:BAAANQADCgMIAwABNQAECgcIBgAHAAAAAA==.Shego:BAAANQAECgUICAABNQAECgcIFgABACkkAA==.Sheltered:BAABNQAECn8mAAIXAAoKRSMOGQDkAgAXAAoKRSMOGQDkAgAAAA==.Shocktopus:BAACNQAFFH8MAAIKAAQKtBpQDwBbAQAKAAQKtBpQDwBbAQA1AAQKfyYAAgoACgohHZ4eAPECAAoACgohHZ4eAPECAAAA.',
Si='Silver:BAAANQAECgEIAQAAAA==.Sinakra:BAABNQAECn8fAAIXAAkKtAsuvQCiAQAXAAkKtAsuvQCiAQAAAA==.',
Sl='Slapdh:BAAANQADCggIDAABNQAFFAgIFAACAO8gAA==.Slaphapypapy:BAACNQAFFH8UAAMCAAgK7yB1AQBSAgACAAcKhSB1AQBSAgABAAIKYSTkEgC3AAA1AAQKf0AAAwIACgp6Jg8BAMYDAAIACgp6Jg8BAMYDAAEABAp/JJxdAEABAAAA.',
Sm='Smee:BAABNQAECn8hAAICAAcKQhL8HwDOAQACAAcKQhL8HwDOAQAAAA==.',
Sn='Snowyscat:BAABNQAECn8ZAAIgAAoKYCBzQwC/AgAgAAoKYCBzQwC/AgABNQAFFAgIGgAUAAAfAA==.',
Sp='Spirits:BAABNQAECn8fAAIKAAoKsx/6KQC7AgAKAAoKsx/6KQC7AgAAAA==.Spritz:BAABNQAECn8XAAIIAAUKBAhe9AAZAQAIAAUKBAhe9AAZAQAAAA==.',
St='Stampede:BAAANQADCggIEgAAAA==.Starshots:BAAANQADCgMIAwAAAA==.Stuey:BAAANQADCgcIGQAAAA==.',
Su='Subito:BAAANQADCgEIAQAAAA==.',
Ta='Taburiel:BAAANQADCgcICgAAAA==.Tanis:BAAANQAECgMICQAAAA==.Tarstarkas:BAAANQABCgQIBgAAAA==.Taylea:BAAANQADCgYIBgAAAA==.',
Te='Temperånce:BAABNQAECn8xAAMMAAoKGw+rLwCdAQAMAAkKiAyrLwCdAQANAAkKAAa7awAcAQAAAA==.',
Ti='Tiled:BAAANQABCggJCgAAAA==.',
To='Toosalty:BAAANQADCgQIBAAAAA==.Toothgrinder:BAABNQAECn8nAAMiAAoKeQ8CFACOAQAiAAoKeQ8CFACOAQAKAAMKjAvBxABjAAAAAA==.',
Ur='Urbanfries:BAAANQADCgQIBAABNQAFFAcIEgAPAP4UAA==.',
Va='Varlonn:BAAANQADCggIEAAAAA==.Varr:BAAANQAECgQIBwAAAA==.Vayeda:BAABNQAECn8dAAIdAAgKLCJhAwATAwAdAAgKLCJhAwATAwAAAA==.',
Ve='Velini:BAAANQADCggICgAAAA==.Venderic:BAAANQADCggICAAAAA==.',
Vi='Vixia:BAAANQAECgUIDAAAAA==.Viz:BAAANQAECgQICwAAAA==.',
Vo='Voidpetal:BAAANQAECgUIBQAAAA==.Vozzert:BAAANQAECgIIAgAAAA==.',
Wh='Whatnow:BAAANQAECggICAAAAA==.Whítemane:BAAANQADCgYIBgAAAA==.',
Xa='Xantara:BAAANQABCgYIBgAAAA==.',
Yo='Yogi:BAAANQADCggICAABNQAECgcICgAHAAAAAA==.Yoursalad:BAACNQAFFH8GAAIXAAUKYAFNHwCBAAAXAAUKYAFNHwCBAAA1AAQKfyQAAxcACApcD27VAPEAABcACArACW7VAPEAAB8ABQpEEcNHAM8AAAAA.',
Yu='Yuuka:BAABNQAECn8iAAIRAAkK/yCXFAAqAwARAAkK/yCXFAAqAwAAAA==.',
Za='Zarigar:BAAANQADCgEIAQAAAA==.',
Ze='Zerin:BAAANQAECgUICwABNQAECgoKJgAXAEUjAA==.Zeroh:BAAANQADCgcIEQAAAA==.',
Zi='Zithia:BAAANQADCgcIHgAAAA==.',
Zn='Zna:BAAANQAECgQIBAAAAA==.',
Zu='Zuezes:BAAANQADCgcIFAAAAA==.',
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
