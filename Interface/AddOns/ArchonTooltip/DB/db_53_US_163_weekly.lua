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

local lookup = {'Druid-Feral','Druid-Balance','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Protection','DeathKnight-Blood','Mage-Arcane','Monk-Brewmaster','Shaman-Restoration','Rogue-Assassination','Warrior-Protection','Hunter-Survival','Monk-Windwalker','DeathKnight-Frost','Paladin-Holy','Warlock-Demonology','Warrior-Arms','DeathKnight-Unholy','Warrior-Fury','Priest-Holy','Shaman-Enhancement','Druid-Guardian','Rogue-Subtlety','Priest-Shadow','Shaman-Elemental','Warlock-Affliction','Warlock-Destruction','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Druid-Restoration','Hunter-Marksmanship','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adira:BAAANQADCgYIDAAAAA==.Adorabull:BAABNQAECn8tAAMBAAoKCCWJAwBmAwABAAkKCCWJAwBmAwACAAYKbxlYXQBcAQAAAA==.',
Ae='Aemun:BAAANQADCggIEgAAAA==.',
Ag='Aggfu:BAAANQADCgcIBwABNQAECgkJFAADALIWAA==.',
Ak='Akelita:BAABNQAECn8UAAMEAAcKNRd8QAC6AQAEAAcKNRd8QAC6AQAFAAIKCQZyZQBTAAAAAA==.',
Al='Alailea:BAABNQAECn8oAAIGAAkKKRF8bwAzAgAGAAkKKRF8bwAzAgAAAA==.Aloepaw:BAAANQAECgUIBgAAAA==.Alwysafkable:BAABNQAECn8VAAIHAAgK/xxFFQBXAgAHAAgK/xxFFQBXAgAAAA==.',
An='Anastasía:BAABNQAECn8pAAIIAAgKfxHGRQDjAQAIAAgKfxHGRQDjAQAAAA==.Anzul:BAAANQADCgYICgAAAA==.',
As='Asure:BAABNQAECn8jAAIGAAgKfQu7hwD7AQAGAAgKfQu7hwD7AQAAAA==.',
Ay='Ayesu:BAAANQAECgUIDAABNQAECgkJFgAJAPweAA==.',
Az='Azerith:BAAANQADCgYIDgAAAA==.',
Ba='Balahuk:BAAANQAECgQICQABNQAFFAQIDQAKAOoYAA==.',
Bl='Bloodfish:BAABNQAECn8YAAIIAAkKNiDHDwAvAwAIAAkKNiDHDwAvAwAAAA==.',
Bo='Bomber:BAAANQADCgQIBAAAAA==.Bombs:BAAANQAECgYICQABNQAFFAUIGQALAGsgAA==.Bonesy:BAABNQAECn8VAAIMAAgKZQh8RAC2AQAMAAgKZQh8RAC2AQAAAA==.',
Bu='Burdomew:BAAANQAECgUICwAAAA==.',
['Bà']='Bàwitdàbà:BAABNQAECn8kAAILAAcKpxJDJQBPAQALAAcKpxJDJQBPAQAAAA==.',
['Bö']='Börs:BAAANQADCgEIAQAAAA==.',
Ca='Cadbringer:BAAANQADCggJCAAAAA==.Cadbury:BAAANQAECgQICAAAAA==.Cananojii:BAAANQADCgQIBgAAAA==.Cantona:BAAANQAECgEIAQAAAA==.Casmina:BAAANQAECgcICwAAAA==.',
Ce='Ceola:BAABNQAECn8gAAINAAkKGxa2FADbAQANAAkKGxa2FADbAQAAAA==.',
Ch='Chamichurri:BAAANQADCgQIBAAAAA==.Chamming:BAAANQAECgIIAgAAAA==.Chaw:BAACNQAFFH8TAAIGAAYKTR2SCADBAQAGAAYKTR2SCADBAQA1AAQKfysAAwYACgo8JCoYADkDAAYACgo8JCoYADkDAA4AAwrYG4gEABkBAAAA.Chawdan:BAAANQADCgcIBwAAAA==.Chenkenichi:BAABNQAECn8qAAIPAAkKJwvxDABMAQAPAAkKJwvxDABMAQAAAA==.Chillout:BAAANQAECgcIDAAAAA==.',
Ci='Cinny:BAABNQAECn8zAAIGAAoKuRKGVgBvAgAGAAoKuRKGVgBvAgAAAA==.Cityairlines:BAABNQAECn8sAAIQAAoKtA4WPwDOAQAQAAoKtA4WPwDOAQAAAA==.',
Cm='Cmoneyy:BAAANQADCgYIBgAAAA==.',
Co='Cooldukenuke:BAABNQAECn8iAAIRAAgKaB95LAC1AgARAAgKaB95LAC1AgAAAA==.',
Cr='Criticize:BAABNQAECn8WAAIDAAgK7A5jsgC6AQADAAgK7A5jsgC6AQAAAA==.',
Cs='Csorpa:BAAANQAECgEIAQAAAA==.',
Cu='Cultist:BAAANQAECgcIDAAAAA==.Cupcakes:BAABNQAECn8wAAQDAAkKHh82TwCnAgADAAkKHh82TwCnAgAHAAQKaRSRQgDqAAARAAMKgBSl3QDDAAABNQAECgkJNAAIAKIjAA==.',
De='Deadbrum:BAAANQADCgYIBgABNQAECgoKPAALACkdAA==.Deagua:BAAANQADCggIDwABNQAFFAYIFQASAA4WAA==.Deardra:BAAANQAECgMIBgAAAA==.Dejavu:BAACNQAFFH8NAAIKAAQK6hjzBAA6AQAKAAQK6hjzBAA6AQA1AAQKfy4AAgoACgqmHl0GAOgCAAoACgqmHl0GAOgCAAAA.Desdemona:BAAANQAECgIIAwAAAA==.',
Di='Disd:BAAANQAECgQIBAAAAA==.Dispal:BAAANQAECgIIAgAAAA==.',
Do='Doodoopoopoo:BAAANQAECggIAQAAAA==.',
Dr='Dracz:BAAANQAECgYIBwAAAA==.Dropdead:BAAANQAECgQIBAAAAA==.Dropkick:BAAANQAECgMIBgAAAA==.',
Du='Duplexity:BAABNQAECn8wAAMNAAoKDiW8AQCtAwANAAoKDiW8AQCtAwATAAEKkxG0SwE7AAAAAA==.',
Dv='Dvxmatt:BAAANQAECgYIEwAAAA==.',
Dw='Dwalin:BAAANQAECgcIEQAAAA==.',
Eg='Egohakai:BAACNQAFFH8SAAIDAAUKTR/xCgCZAQADAAUKTR/xCgCZAQA1AAQKfysAAgMACgpNH7BIALsCAAMACgpNH7BIALsCAAAA.',
El='Elfy:BAAANQADCgUIBQAAAA==.',
Em='Emieretta:BAABNQAECn8mAAMQAAoK8hHBPADaAQAQAAkKoRHBPADaAQAUAAYKxQv+hAAMAQAAAA==.',
Er='Errekt:BAAANQAECgEIAgAAAA==.Erret:BAACNQAFFH8LAAIJAAUKCAhTJQBcAQAJAAUKCAhTJQBcAQA1AAQKfz0AAgkACgp3GssKAB8CAAkACgp3GssKAB8CAAAA.',
Et='Ethaka:BAAANQAFFAEIAQAAAA==.',
Fa='Faemos:BAAANQAECgYICwAAAA==.Faience:BAABNQAECn8XAAIQAAYKiAPHPgCpAAAQAAYKiAPHPgCpAAAAAA==.Falorina:BAACNQAFFH8GAAIEAAMKuRwHBwC1AAAEAAMKuRwHBwC1AAA1AAQKfzUAAgQACgrsJKkCAMoDAAQACgrsJKkCAMoDAAAA.Fathernature:BAABNQAECn8cAAICAAoK+xbbFAA1AQACAAoK+xbbFAA1AQAAAA==.',
Fe='Feldra:BAABNQAECn8oAAIFAAoKKiDQCgAwAwAFAAoKKiDQCgAwAwAAAA==.',
Fi='Finnin:BAABNQAECn8nAAMTAAoK/xgtVACOAgATAAoK/xgtVACOAgAVAAEKFCDEKwBWAAAAAA==.',
Fo='Food:BAABNQAECn8oAAIGAAoKZA/RdQAkAgAGAAoKZA/RdQAkAgAAAA==.',
Fr='Frozenfaith:BAABNQAECn8mAAIWAAoKCxXQXwABAgAWAAoKCxXQXwABAgAAAA==.',
Fu='Furba:BAABNQAECn8oAAIGAAoKkxeGMwDRAgAGAAoKkxeGMwDRAgAAAA==.Furiouswind:BAABNQAECn8sAAIXAAoKGBfVDwBrAgAXAAoKGBfVDwBrAgAAAA==.Furyvolt:BAAANQAECgYIEQAAAA==.',
Gh='Ghettomike:BAABNQAECn8lAAIUAAoKiBqIJQCpAgAUAAoKiBqIJQCpAgAAAA==.Ghold:BAABNQAECn8gAAQRAAoK9B4mHQD/AgARAAoK9B4mHQD/AgADAAMKzQcJYwGBAAAHAAEKAAB5dwAlAAAAAA==.',
Gi='Giranimo:BAAANQAECgcIEAAAAA==.',
Gl='Glabados:BAABNQAECn8XAAIYAAoKGiMYBQBNAwAYAAoKGiMYBQBNAwABNQAECgkJGwAKAPAgAA==.Glossy:BAACNQAFFH8UAAMZAAYKyCPFBwCKAQAZAAUKxiLFBwCKAQAMAAEKzibzGQBwAAA1AAQKfykAAxkACQqGJVgSAEQBAAwABAq6JWtHAKcBABkACAprJFgSAEQBAAAA.Glossyrage:BAAANQADCgcIBwAAAA==.',
Go='Gorkus:BAAANQADCgMIAwAAAA==.Gors:BAAANQAECgQIBQAAAA==.',
Gr='Gratiaplena:BAAANQABCgQIBwAAAA==.',
Ha='Halîk:BAABNQAECn8dAAIRAAkKCRAaagDZAQARAAkKCRAaagDZAQAAAA==.Hardheaded:BAAANQAECgcICQAAAA==.Hathina:BAACNQAFFH8KAAMVAAYKtRqtAQAPAQAVAAQKERqtAQAPAQATAAIKWBvOKwCbAAA1AAQKfyMAAxUACgqQJIwDAB0DABUACQoaJYwDAB0DABMAAQrLIMZBAU8AAAAA.',
He='Hedetet:BAAANQABCgEIAQABNQAECggIGgAFAFMXAA==.Heket:BAAANQADCggIEwAAAA==.Herath:BAAANQABCggIDwAAAA==.',
Hi='Hill:BAABNQAECn8hAAIGAAkK1RKjYwBOAgAGAAkK1RKjYwBOAgAAAA==.Hive:BAABNQAECn8rAAITAAoK8g6ujwD1AQATAAoK8g6ujwD1AQAAAA==.',
Hu='Husentar:BAAANQADCgYICwAAAA==.',
Ic='Icaron:BAAANQADCggIAQAAAA==.',
Ig='Igni:BAAANQABCgMIBAAAAA==.',
Il='Illuminottey:BAAANQADCgEIAQAAAA==.',
Im='Impériavil:BAAANQAECgQIBgAAAA==.',
In='Inferium:BAAANQADCgcIBwAAAA==.Insatiabull:BAABNQAECn8XAAMEAAoKsh2QGQDOAgAEAAkKsh2QGQDOAgAFAAEKAABOPgAAAAABNQAECgoKLQABAAglAA==.',
Ir='Iriaena:BAAANQADCgYIDwAAAA==.',
Is='Ishaa:BAAANQAECggICgAAAA==.',
Ja='Jackstands:BAABNQAECn81AAILAAoKBCLaEAA/AwALAAoKBCLaEAA/AwAAAA==.Jagerin:BAAANQAECgQIBAABNQAECgkJGwAKAPAgAA==.January:BAABNQAECn8WAAIaAAgKoAeXNwBoAQAaAAgKoAeXNwBoAQAAAA==.Jarry:BAAANQAECgMIBQAAAA==.',
Je='Jeannine:BAAANQAECgQICwAAAA==.',
Ju='Junn:BAABNQAECn8sAAIbAAoK5wxbMAD9AAAbAAoK5wxbMAD9AAAAAA==.',
['Já']='Jánuary:BAABNQAECn8bAAQSAAkKKQ2jeAD5AQASAAkK4QqjeAD5AQAcAAUKeQqQFAABAQAdAAQKeg3mSAClAAAAAA==.',
Ka='Kahayman:BAABNQAECn8hAAMJAAkKGg0ZsAAjAgAJAAkKGg0ZsAAjAgAeAAQKNAT8LQCOAAAAAA==.Kaimari:BAABNQAECn8aAAQYAAgKqA25KABQAQAYAAUKVhi5KABQAQACAAgKywJ3cAAIAQABAAMKrQJfPABIAAAAAA==.Katniss:BAAANQAECgQIBAAAAA==.Kazuya:BAAANQAECgEIAQAAAA==.',
Ke='Kennyboi:BAAANQADCgIIAgAAAA==.',
Kh='Khaibit:BAABNQAECn84AAIQAAoK7B/NCQBOAwAQAAoK7B/NCQBOAwAAAA==.Khathani:BAAANQADCggIDwAAAA==.',
Ki='Kirara:BAAANQAECgYIBgAAAA==.Kissofdeath:BAABNQAECn8pAAIMAAgKIgshHwDZAAAMAAgKIgshHwDZAAAAAA==.',
Ko='Komojo:BAAANQAECgcICwAAAA==.Koriggan:BAABNQAECn8gAAIOAAkKDxgyBQB1AgAOAAkKDxgyBQB1AgAAAA==.',
Kr='Krea:BAABNQAECn8fAAIHAAkKsiT3BQBNAwAHAAkKsiT3BQBNAwAAAA==.Kroval:BAABNQAECn8bAAIMAAoKrQe3RQCwAQAMAAoKrQe3RQCwAQAAAA==.Krystagosa:BAABNQAECn8gAAQfAAgKNQ+FBQCDAQAfAAgKNQ+FBQCDAQAgAAYKlQ3gEAApAQAhAAMK7gT1MQCCAAAAAA==.',
Ku='Kuriuh:BAAANQAECgYJDwAAAA==.',
Ky='Kybo:BAAANQABCgMIAwABNQAFFAQIDQACAE4aAA==.Kyo:BAAANQADCgUIBQAAAA==.',
La='Lang:BAABNQAECn8pAAIiAAgKfBhiCgA1AgAiAAgKfBhiCgA1AgAAAA==.',
Li='Lightdogg:BAAANQAECgcIEQAAAA==.Limaia:BAABNQAECn8mAAMjAAgKPg8pEgA0AQAjAAgKPg8pEgA0AQACAAMKPwMVoQBbAAAAAA==.Linia:BAAANQAECgEIAQAAAA==.',
Lo='Loopey:BAAANQAECgMIAwABNQAFFAQIDQAKAOoYAA==.',
Lu='Luceriss:BAABNQAECn8UAAIMAAkKOApiOAD0AQAMAAkKOApiOAD0AQAAAA==.Luckylite:BAAANQAECgIIAgAAAA==.Lulilaj:BAABNQAECn8vAAIeAAgKtRfiBwBsAgAeAAgKtRfiBwBsAgAAAA==.',
Ma='Maike:BAABNQAECn8bAAIZAAkKyBRlGwD7AQAZAAkKyBRlGwD7AQAAAA==.Marothius:BAACNQAFFH8VAAMSAAYKDhYpGAAzAQASAAUK4hkpGAAzAQAdAAEKkwqjHgBLAAA1AAQKfykAAx0ACgoMHLgfAHIBABIACQoMGwdiADMCAB0ABQoVGbgfAHIBAAAA.Marrius:BAAANQADCgYIBwAAAA==.Martaug:BAABNQAECn8iAAILAAkKjCEDFwAaAwALAAkKjCEDFwAaAwAAAA==.Marune:BAABNQAECn8mAAMfAAoKFxPyHQDwAQAfAAoKFxPyHQDwAQAhAAcKjw4uHwBhAQAAAA==.Maverage:BAABNQAECn8VAAITAAgKehw5WACDAgATAAgKehw5WACDAgAAAA==.Mayfair:BAAANQAECgIIAwAAAA==.',
Me='Melee:BAABNQAECn8oAAIDAAgKrxuERwC+AgADAAgKrxuERwC+AgAAAA==.Metal:BAAANQADCgcIEwAAAA==.',
Mi='Minibolt:BAAANQADCgEIAQAAAA==.Minimee:BAAANQAECgEIAQAAAA==.Miquella:BAABNQAECn8WAAIEAAcKlBzPOgDfAQAEAAcKlBzPOgDfAQAAAA==.',
Mo='Mollymauk:BAAANQADCgQIBAABNQAECgoKIAARAPQeAA==.Monkstrosity:BAAANQAECgYIEAAAAA==.Mookks:BAAANQADCgUIBQAAAA==.Moonn:BAABNQAECn8VAAIbAAkKvwg6hACaAQAbAAkKvwg6hACaAQAAAA==.Moor:BAAANQAECgUIDgAAAA==.Mordakka:BAABNQAECn8UAAIJAAgK+A9F1QDcAQAJAAgK+A9F1QDcAQAAAA==.Morior:BAABNQAECn8uAAMSAAoKwxFFfADwAQASAAkKdhBFfADwAQAdAAEK3RrKaQBNAAAAAA==.',
Mu='Muirfire:BAAANQABCggICgAAAA==.Mulletmaster:BAAANQAECgUJCQAAAA==.Murrda:BAABNQAECn83AAMSAAoKghX5TgBnAgASAAkKDRX5TgBnAgAdAAEKtBjcEgBHAAAAAA==.',
My='Myrokos:BAABNQAECn85AAIDAAoKah8LNAD8AgADAAoKah8LNAD8AgAAAA==.',
['Mö']='Möokss:BAABNQAECn8dAAIGAAgKvgvuYwDjAAAGAAgKvgvuYwDjAAAAAA==.',
Na='Nailo:BAAANQADCggICAAAAA==.Nasperus:BAAANQABCgIIAgAAAA==.',
Ni='Niddles:BAAANQAECgcICAAAAA==.Niddy:BAABNQAECn82AAMeAAoK6RvjAABQAgAeAAoK6RvjAABQAgAJAAMK+gjdlgGZAAAAAA==.',
No='Nobudee:BAAANQADCgcIBwABNQAFFAYIEQAbAOwbAA==.Nocandles:BAABNQAECn8pAAIaAAkKYR8kAgAwAgAaAAkKYR8kAgAwAgAAAA==.Noebuddie:BAACNQAFFH8RAAIbAAYK7BuMCwCyAQAbAAYK7BuMCwCyAQA1AAQKfyoAAhsACgqoIpocAB4DABsACgqoIpocAB4DAAAA.Noel:BAAANQAECgQIDQAAAA==.Nonospot:BAABNQAECn8aAAIaAAgKGxEFJwD0AQAaAAgKGxEFJwD0AQAAAA==.Noraboo:BAABNQAECn8WAAIJAAkK/B7NTwDhAgAJAAkK/B7NTwDhAgAAAA==.Norganon:BAAANQAECgUIBQAAAA==.',
Nv='Nvied:BAABNQAECn8cAAMSAAgKFhdSiADRAQASAAcK7BZSiADRAQAdAAIKuxAnWAB3AAAAAA==.',
Ny='Nyctt:BAABNQAECn8xAAIZAAoK4xpJCgDQAgAZAAoK4xpJCgDQAgAAAA==.Nyzstra:BAABNQAECn8pAAIJAAoKkB2wOgASAwAJAAoKkB2wOgASAwAAAA==.',
['Nê']='Nêwt:BAACNQAFFH8HAAIJAAIKNQhUHQCDAAAJAAIKNQhUHQCDAAA1AAQKfy0AAgkACgpAEFmoADECAAkACgpAEFmoADECAAAA.',
On='Onlybeams:BAABNQAECn8aAAIFAAgKUxdOHwBUAgAFAAgKUxdOHwBUAgAAAA==.',
Or='Orcs:BAAANQADCgUIBQAAAA==.Oreo:BAAANQADCgcIEQAAAA==.Orphu:BAAANQADCgQIBwAAAA==.',
Pa='Palmiste:BAAANQAECgQIBAAAAA==.Pandoora:BAAANQADCgYIEAAAAA==.Pangoplexity:BAAANQABCgMJAwAAAA==.Papichulo:BAAANQADCgQIBAAAAA==.Parahsalin:BAABNQAECn8dAAMEAAgKjw6QEgBWAQAEAAgKjw6QEgBWAQAFAAIKVgHfZwBFAAAAAA==.Pastryblust:BAACNQAFFH8VAAMbAAUKGBUJDwB+AQAbAAUKahMJDwB+AQAXAAIKTQ9iAgClAAA1AAQKfzkAAxcACgplH/UBADoCABsACQoVIWAXADwDABcACQqgGfUBADoCAAAA.',
Pe='Pennyzillin:BAAANQADCggICAABNQAECggIHQAEAI8OAA==.Pewpewmon:BAAANQADCgcIBwABNQAECgoKMAANAA4lAA==.',
Pi='Pistachio:BAAANQADCggIHgAAAA==.Pitviper:BAABNQAECn8sAAIMAAoKfxUeFQAeAQAMAAoKfxUeFQAeAQAAAA==.',
Po='Pogaca:BAAANQADCggIEwAAAA==.Portabull:BAAANQADCgcIBwABNQAECgoKLQABAAglAA==.',
Pr='Precogvendor:BAAANQAECgQIBwAAAA==.',
Ra='Raddelwingus:BAAANQADCgMIAwABNQAECgoKMAANAA4lAA==.Rai:BAABNQAECn8pAAIGAAgKuSKEHAAlAwAGAAgKuSKEHAAlAwAAAA==.Ramens:BAAANQAECgIIAgAAAA==.Rapha:BAABNQAECn8bAAIKAAkK8CBECACqAgAKAAkK8CBECACqAgAAAA==.Rayyzor:BAABNQAECn8oAAIFAAoKqh+NDQANAwAFAAoKqh+NDQANAwAAAA==.',
Re='Reality:BAAANQADCgQICAAAAA==.Realtree:BAAANQADCgQIBwAAAA==.',
Ri='Riddles:BAAANQAECgcIEQAAAA==.',
Ro='Rot:BAABNQAECn8sAAIIAAoK8SGPDABOAwAIAAoK8SGPDABOAwAAAA==.',
Ru='Rusty:BAAANQADCgUIBQAAAA==.',
Sa='Santino:BAAANQADCgcICAABNQAECgkJIQAJABoNAA==.Sapherapal:BAAANQADCgMIAwAAAA==.Saphlocket:BAAANQAECgMICQAAAA==.Saphmage:BAAANQAECgMIBwAAAA==.Sathin:BAABNQAECn8pAAIFAAgKXQeeNgCOAQAFAAgKXQeeNgCOAQAAAA==.',
Sc='Scher:BAAANQAECgMIAwAAAA==.Scufalufagus:BAAANQADCgUIBQABNQAFFAYIFQASAA4WAA==.',
Se='September:BAAANQADCgYIBgABNQAECggIFgAaAKAHAA==.Seqsy:BAAANQAECgUICQAAAA==.',
Sf='Sfcwarner:BAAANQADCgYIDQAAAA==.',
Sg='Sgtwarner:BAAANQAECgQIBAAAAA==.',
Sh='Shampooyou:BAABNQAECn8fAAILAAkKDA2degCcAQALAAkKDA2degCcAQAAAA==.Shocka:BAAANQAECgIIAgAAAA==.Shockakhan:BAAANQADCgQIBAAAAA==.',
Si='Silentkit:BAABNQAECn8bAAMQAAcK0hL+RwCeAQAQAAcK0hL+RwCeAQAUAAMKowq/rwCTAAAAAA==.',
St='Stardel:BAABNQAECn8UAAIOAAgKxx0EBQB+AgAOAAgKxx0EBQB+AgABNQAFFAYIDQAZAJgjAA==.Stormclaw:BAABNQAECn80AAMjAAoKuhYfHwA0AgAjAAkK7BQfHwA0AgACAAgKeBUfFgAsAQAAAA==.Stregglebus:BAAANQAECgYIDgABNQAFFAYIFQASAA4WAA==.Stregoica:BAAANQAECgYIBgABNQAFFAYIFQASAA4WAA==.Stroggosh:BAAANQAECgEIAQABNQAFFAYIFQASAA4WAA==.',
Su='Suhfering:BAAANQAECggIEQABNQAECggIGgAFAFMXAA==.Sunshot:BAAANQAECgEIAQAAAA==.Surrs:BAAANQAECgIIAgABNQAECggIFgAaAKAHAA==.',
Ta='Takrusani:BAAANQADCgIIAgAAAA==.Tallron:BAACNQAFFH8VAAIjAAYKpxJ1BwCFAQAjAAYKpxJ1BwCFAQA1AAQKfysAAiMACgpqHd0RAMICACMACgpqHd0RAMICAAAA.Tamedsloth:BAAANQAECgMIBAAAAA==.Tanerella:BAAANQAECgIIBAAAAA==.',
Th='Thrustruggle:BAABNQAECn8cAAIkAAoKsxC0KAAFAgAkAAoKsxC0KAAFAgAAAA==.',
Ti='Timir:BAACNQAFFH8SAAIDAAYKmxJmDQB1AQADAAYKmxJmDQB1AQA1AAQKfywAAgMACgpGGZU9AEwBAAMACgpGGZU9AEwBAAAA.Tinynutz:BAAANQADCgYICQAAAA==.',
To='Tojikitoushi:BAABNQAECn82AAIXAAoKwRRQDwB0AgAXAAoKwRRQDwB0AgAAAA==.Tombs:BAAANQAECgEIAQABNQAECgoKIAARAPQeAA==.Totenhammer:BAAANQADCgYIBwAAAA==.Touche:BAABNQAECn8eAAIJAAoKIQ/1ZgDvAAAJAAoKIQ/1ZgDvAAAAAA==.',
Tr='Tribulate:BAAANQADCggIDAAAAA==.Trollyroller:BAAANQADCggIFAAAAA==.',
Tw='Twistedfrost:BAAANQADCgUIBQAAAA==.',
Ul='Ulrein:BAAANQAECgIIAwAAAA==.',
Ve='Vextt:BAABNQAECn8gAAMWAAoKih6NIgDkAgAWAAkK7CCNIgDkAgAaAAgKWh0cHABkAgABNQAECgoKIAARAPQeAA==.Veylira:BAABNQAECn8bAAMSAAgKVxjXOwAYAQASAAgKVxjXOwAYAQAdAAIKGBSUVQB+AAABNQAECgoKNgATAAEdAA==.',
Vi='Vitner:BAABNQAECn8YAAISAAkKrRf7VgBRAgASAAkKrRf7VgBRAgAAAA==.',
Vo='Voidra:BAAANQAECgEIBAAAAA==.Voidwarner:BAAANQADCggICAAAAA==.Volight:BAAANQAECgQIBgAAAA==.Volke:BAABNQAECn8sAAIlAAoKmhOlGQDlAQAlAAoKmhOlGQDlAQAAAA==.Voltarix:BAAANQADCgEIAQAAAA==.Voyria:BAABNQAECn8pAAMjAAgKBw09GwDrAAAjAAgKBw09GwDrAAACAAIKuAHGtQAtAAAAAA==.',
Vy='Vyskar:BAAANQADCgUIBAAAAA==.',
['Vê']='Vênm:BAAANQAECgMIBAABNQAFFAQIDQAKAOoYAA==.',
Wa='Warm:BAAANQAECgQICAAAAA==.',
We='Weeziveli:BAAANQADCgYIBgAAAA==.Weledish:BAACNQAFFH8QAAMJAAYKXw9ZJQBcAQAJAAUKzQ9ZJQBcAQAeAAEKFA6iEwBHAAA1AAQKfzEAAwkACgolHl80ACEDAAkACgoZHl80ACEDAB4AAgpgG/wpAKgAAAAA.Weleron:BAAANQADCgIIAgAAAA==.',
Wi='Widdles:BAAANQAECgMIAwAAAA==.',
Yi='Yinyangfaith:BAAANQADCgEIAQABNQAECgoKJgAWAAsVAA==.',
Ze='Zerea:BAAANQABCgEIAQAAAA==.',
Zo='Zomgdk:BAABNQAECn85AAIIAAoKHSC5BwCAAwAIAAoKHSC5BwCAAwAAAA==.',
Zy='Zynthia:BAAANQAECgEIAQAAAA==.',
['Äm']='Ämäteräsu:BAAANQAECggJAgAAAA==.',
['Ël']='Ëlement:BAAANQADCgcIBwAAAA==.',
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
