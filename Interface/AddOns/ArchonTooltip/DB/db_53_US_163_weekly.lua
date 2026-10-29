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

local lookup = {'Druid-Feral','Druid-Balance','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Protection','DeathKnight-Blood','Mage-Arcane','Monk-Brewmaster','Shaman-Restoration','Rogue-Assassination','Warrior-Fury','Warrior-Arms','Warrior-Protection','Hunter-Survival','Monk-Windwalker','DeathKnight-Frost','Paladin-Holy','Warlock-Demonology','DeathKnight-Unholy','Hunter-Marksmanship','Priest-Holy','Shaman-Enhancement','Druid-Guardian','Rogue-Subtlety','Priest-Shadow','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Druid-Restoration','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adira:BAAANQADCgYIDAAAAA==.Adorabull:BAABNQAECn8uAAMBAAoKCCWJAwBmAwABAAkKCCWJAwBmAwACAAYKbxlYXQBcAQAAAA==.',
Ae='Aemun:BAAANQADCggIEgAAAA==.',
Ag='Aggfu:BAAANQADCgcIBwABNQAECgoKGgADAKQUAA==.',
Ak='Akelita:BAABNQAECn8UAAMEAAcKNRd8QAC6AQAEAAcKNRd8QAC6AQAFAAIKCQZyZQBTAAAAAA==.',
Al='Alailea:BAABNQAECn8yAAIGAAoKDRHcQwDVAQAGAAoKDRHcQwDVAQAAAA==.Aloepaw:BAAANQAECgYIBwAAAA==.Aloepriest:BAAANQAECgIIAgAAAA==.Alwysafkable:BAABNQAECn8VAAIHAAgK/xxFFQBXAgAHAAgK/xxFFQBXAgAAAA==.',
An='Anastasía:BAABNQAECn8tAAIIAAkKPRHGRQDjAQAIAAkKPRHGRQDjAQAAAA==.Anzul:BAAANQADCgYICgAAAA==.',
As='Asure:BAABNQAECn8nAAIGAAkKAgzNagBjAQAGAAkKAgzNagBjAQAAAA==.',
Ay='Ayesu:BAAANQAECgUIDAABNQAECgoKGgAJAHQdAA==.',
Az='Azerith:BAAANQADCgYIDgAAAA==.',
Ba='Balahuk:BAAANQAECgQICwABNQAFFAQIDQAKAOoYAA==.',
Bl='Bloodfish:BAABNQAECn8YAAIIAAkKNiDHDwAvAwAIAAkKNiDHDwAvAwAAAA==.',
Bo='Bomber:BAAANQADCgQIBAAAAA==.Bombs:BAAANQAECgYICQABNQAFFAYIGwALAJUcAA==.Bonesy:BAABNQAECn8VAAIMAAgKZQh8RAC2AQAMAAgKZQh8RAC2AQAAAA==.',
Br='Brothermage:BAAANQAECgQIBAAAAA==.',
Bu='Burdomew:BAAANQAECgUIDQAAAA==.',
['Bà']='Bàwitdàbà:BAABNQAECn8oAAILAAcKpxKSVgA+AQALAAcKpxKSVgA+AQAAAA==.',
['Bö']='Börs:BAAANQADCgEIAQAAAA==.',
Ca='Cadbringer:BAAANQADCggJCAAAAA==.Cadbury:BAAANQAECgQICAAAAA==.Cananojii:BAAANQADCgQIBgAAAA==.Cantona:BAAANQAECgEIAQAAAA==.Casmina:BAABNQAECn8XAAMNAAkKQxDFEACZAQANAAkKQxDFEACZAQAOAAUKBwk9rQCyAAAAAA==.',
Ce='Ceola:BAABNQAECn8lAAIPAAoK3RW2FADbAQAPAAoK3RW2FADbAQAAAA==.',
Ch='Chamichurri:BAAANQADCgQIBAAAAA==.Chamming:BAAANQAECgIIAgAAAA==.Chaw:BAACNQAFFH8UAAIGAAcKuRuSCADBAQAGAAcKuRuSCADBAQA1AAQKfzAAAwYACgo8JCoYADkDAAYACgo8JCoYADkDABAAAwrYG4kHAAsBAAAA.Chawdan:BAAANQADCgcIBwAAAA==.Chenkenichi:BAABNQAECn8uAAIRAAoKWwvYFwB4AQARAAoKWwvYFwB4AQAAAA==.Chillout:BAAANQAECgcIDAAAAA==.',
Ci='Cinny:BAABNQAECn8zAAIGAAoKuRKGVgBvAgAGAAoKuRKGVgBvAgAAAA==.Cityairlines:BAABNQAECn8uAAISAAoKtA4WPwDOAQASAAoKtA4WPwDOAQAAAA==.',
Cm='Cmoneyy:BAAANQADCgYIBgAAAA==.',
Co='Cooldukenuke:BAABNQAECn8iAAITAAgKaB95LAC1AgATAAgKaB95LAC1AgAAAA==.',
Cr='Criticize:BAABNQAECn8YAAIDAAgKFQ9jsgC6AQADAAgKFQ9jsgC6AQAAAA==.',
Cs='Csorpa:BAAANQAECgEIAQAAAA==.',
Cu='Cultist:BAAANQAECgcIDAAAAA==.Cupcakes:BAABNQAECn87AAQDAAoKqCGADwD7AgADAAoKqCGADwD7AgAHAAQKaRSRQgDqAAATAAMKgBSl3QDDAAABNQAECgoKPAAIAGUkAA==.',
De='Deadbrum:BAAANQADCgYIBgABNQAECgoKPwALACkdAA==.Deagua:BAAANQADCggIDwABNQAFFAYIFQAUAA4WAA==.Deardra:BAAANQAECgMIBgAAAA==.Dejavu:BAACNQAFFH8NAAIKAAQK6hjzBAA6AQAKAAQK6hjzBAA6AQA1AAQKfy8AAgoACgqmHl0GAOgCAAoACgqmHl0GAOgCAAAA.Desdemona:BAAANQAECgQIBwAAAA==.',
Di='Disd:BAAANQAECgQIBAAAAA==.Disog:BAAANQAECgMIBAAAAA==.Dispal:BAAANQAECgIIAgAAAA==.',
Do='Doodoopoopoo:BAAANQAECggIAQAAAA==.',
Dr='Dracz:BAAANQAECgYIBwAAAA==.Dropdead:BAAANQAECgQIBAAAAA==.Dropkick:BAAANQAECgYIDQAAAA==.',
Du='Duplexity:BAABNQAECn86AAMPAAoKWCWSAABpAwAPAAoKWCWSAABpAwAOAAEKkxG0SwE7AAAAAA==.',
Dv='Dvxmatt:BAAANQAECgYIEwAAAA==.',
Dw='Dwalin:BAAANQAECgcIEQAAAA==.',
Eg='Egohakai:BAACNQAFFH8TAAIDAAYK1RvxCgCZAQADAAYK1RvxCgCZAQA1AAQKfy8AAgMACgpUH7BIALsCAAMACgpUH7BIALsCAAAA.',
El='Elfy:BAAANQADCgUIBQAAAA==.',
Em='Emieretta:BAABNQAECn8mAAMSAAoK8hHBPADaAQASAAkKoRHBPADaAQAVAAYKxQv+hAAMAQAAAA==.',
Er='Errekt:BAAANQAECgEIAgAAAA==.Erret:BAACNQAFFH8LAAIJAAUKCAhTJQBcAQAJAAUKCAhTJQBcAQA1AAQKf0IAAgkACgr3Gw42ABoCAAkACgr3Gw42ABoCAAAA.',
Et='Ethaka:BAABNQAECn8aAAMGAAkKWRdPTQC1AQAGAAkK5RVPTQC1AQAWAAEK9Q5/gwA8AAAAAA==.',
Ey='Eywae:BAAANQADCgcIBwAAAA==.',
Fa='Faemos:BAAANQAECgYICwAAAA==.Faience:BAABNQAECn8dAAISAAYKPgSDWwCwAAASAAYKPgSDWwCwAAAAAA==.Falorina:BAACNQAFFH8GAAIEAAMKuRybCwCpAAAEAAMKuRybCwCpAAA1AAQKfzgAAgQACgrsJKkCAMoDAAQACgrsJKkCAMoDAAAA.Fathernature:BAABNQAECn8kAAICAAoKIRkwFQD+AQACAAoKIRkwFQD+AQAAAA==.',
Fe='Feldra:BAABNQAECn8yAAIFAAoKiSMPBAD1AgAFAAoKiSMPBAD1AgAAAA==.',
Fi='Finnin:BAABNQAECn8qAAMOAAoKthstVACOAgAOAAoKthstVACOAgANAAEKFCDEKwBWAAAAAA==.',
Fo='Food:BAABNQAECn8qAAIGAAoKeA/RdQAkAgAGAAoKeA/RdQAkAgAAAA==.',
Fr='Frozenfaith:BAABNQAECn8oAAIXAAoKABbQXwABAgAXAAoKABbQXwABAgAAAA==.',
Fu='Furba:BAABNQAECn8oAAIGAAoKkxeGMwDRAgAGAAoKkxeGMwDRAgAAAA==.Furiouswind:BAABNQAECn8uAAIYAAoK2hfVDwBrAgAYAAoK2hfVDwBrAgAAAA==.Furyvolt:BAAANQAECgYIEQAAAA==.',
Gh='Ghettomike:BAABNQAECn8nAAIVAAoKQh2IJQCpAgAVAAoKQh2IJQCpAgAAAA==.Ghold:BAABNQAECn8pAAQTAAoK8iDoCgAYAwATAAoK8iDoCgAYAwADAAMKzQcJYwGBAAAHAAEKAAB5dwAlAAAAAA==.',
Gi='Giranimo:BAAANQAECggIEQAAAA==.',
Gl='Glabados:BAABNQAECn8YAAIZAAoKGiMYBQBNAwAZAAoKGiMYBQBNAwABNQAECgkJHQAKAPAgAA==.Glossy:BAACNQAFFH8VAAMaAAcK3yPFBwCKAQAaAAYKJCPFBwCKAQAMAAEKzibzGQBwAAA1AAQKfy4AAxoACQq0JcseACcCABoACApVJcseACcCAAwABAq6JWtHAKcBAAAA.',
Go='Gorkus:BAAANQADCgMIAwAAAA==.Gors:BAAANQAECgQIBQAAAA==.',
Gr='Grandpaswamp:BAAANQAECgQIBQAAAA==.Gratiaplena:BAAANQABCgQIBwAAAA==.',
Ha='Halîk:BAABNQAECn8hAAITAAoKtxAaagDZAQATAAoKtxAaagDZAQAAAA==.Hardheaded:BAAANQAECgcICQAAAA==.Hathina:BAACNQAFFH8LAAMNAAcK+xmtAQAPAQANAAQKERqtAQAPAQAOAAMK7RnOKwCbAAA1AAQKfycAAw0ACgqUJIwDAB0DAA0ACQoeJYwDAB0DAA4AAQrLIMZBAU8AAAAA.',
He='Hedetet:BAAANQABCgEIAQABNQAECggIGgAFAFMXAA==.Heket:BAAANQADCggIGgAAAA==.Herath:BAAANQABCggIDwAAAA==.',
Hi='Hill:BAABNQAECn8jAAIGAAoKIRKjYwBOAgAGAAoKIRKjYwBOAgAAAA==.Hive:BAABNQAECn8rAAIOAAoK8g6ujwD1AQAOAAoK8g6ujwD1AQAAAA==.',
Hu='Husentar:BAAANQADCgYICwAAAA==.',
Ig='Igni:BAAANQABCgMIBAAAAA==.',
Il='Illuminottey:BAAANQADCgEIAQAAAA==.',
Im='Impériavil:BAAANQAECgQIBgAAAA==.',
In='Inferium:BAAANQADCgcIBwAAAA==.Insatiabull:BAABNQAECn8ZAAMEAAoKhB6QGQDOAgAEAAkKhB6QGQDOAgAFAAEKAAC3TgAAAAABNQAECgoKLgABAAglAA==.',
Ir='Iriaena:BAAANQADCgYIDwAAAA==.',
Is='Ishaa:BAAANQAECggICwAAAA==.',
Ja='Jackstands:BAABNQAECn81AAILAAoKBCLaEAA/AwALAAoKBCLaEAA/AwAAAA==.Jagerin:BAAANQAECggIBwABNQAECgkJHQAKAPAgAA==.January:BAABNQAECn8WAAIbAAgKoAeXNwBoAQAbAAgKoAeXNwBoAQAAAA==.Jarry:BAAANQAECgMIBQAAAA==.',
Je='Jeannine:BAABNQAECn8UAAIJAAUKjQdb4ACUAAAJAAUKjQdb4ACUAAAAAA==.',
Ju='Junn:BAABNQAECn8uAAIcAAoKPw0xcADQAQAcAAoKPw0xcADQAQAAAA==.',
['Já']='Jánuary:BAABNQAECn8jAAQdAAkKRg77BwDyAAAUAAkK4QqjeAD5AQAeAAUKeQqQFAABAQAdAAcKkwz7BwDyAAAAAA==.',
Ka='Kahayman:BAABNQAECn8hAAMJAAkKGg0ZsAAjAgAJAAkKGg0ZsAAjAgAfAAQKNAT8LQCOAAAAAA==.Kaimari:BAABNQAECn8aAAQZAAgKqA25KABQAQAZAAUKVhi5KABQAQACAAgKywJ3cAAIAQABAAMKrQJfPABIAAAAAA==.Katniss:BAAANQAECgQIBAAAAA==.Kazuya:BAAANQAECgEIAQAAAA==.',
Ke='Kennyboi:BAAANQADCgIIAgAAAA==.',
Kh='Khaibit:BAABNQAECn84AAISAAoK7B/NCQBOAwASAAoK7B/NCQBOAwAAAA==.Khathani:BAAANQADCggIDwAAAA==.',
Ki='Kirara:BAAANQAECggIDAAAAA==.Kissofdeath:BAABNQAECn8tAAIMAAkK1wu3FQBNAQAMAAkK1wu3FQBNAQAAAA==.',
Ko='Komojo:BAAANQAECgcICwAAAA==.Koriggan:BAABNQAECn8jAAIQAAkKnBkyBQB1AgAQAAkKnBkyBQB1AgAAAA==.',
Kr='Krea:BAABNQAECn8jAAMHAAoKxSL3BQBNAwAHAAkKsiT3BQBNAwADAAEKSBWeMgFAAAAAAA==.Kroval:BAABNQAECn8bAAIMAAoKrQe3RQCwAQAMAAoKrQe3RQCwAQAAAA==.Krystagosa:BAABNQAECn8iAAQgAAgKqw9xDgCNAQAgAAgKqw9xDgCNAQAhAAYKlQ3gEAApAQAiAAMK7gT1MQCCAAAAAA==.',
Ku='Kuriuh:BAAANQAECgcIDwAAAA==.',
Ky='Kybo:BAAANQABCgMIAwABNQAFFAQIDQACAE4aAA==.Kyo:BAAANQADCgUIBQAAAA==.',
La='Lang:BAABNQAECn8tAAIjAAkKeBisBgCfAQAjAAkKeBisBgCfAQAAAA==.',
Li='Lightdogg:BAAANQAECgcIEQAAAA==.Limaia:BAABNQAECn8oAAMkAAgKUA/uKwC9AQAkAAgKUA/uKwC9AQACAAMKPwMVoQBbAAAAAA==.Linia:BAAANQAECgEIAQAAAA==.',
Lo='Loopey:BAAANQAECgMIAwABNQAFFAQIDQAKAOoYAA==.',
Lu='Luceriss:BAABNQAECn8UAAIMAAkKOApiOAD0AQAMAAkKOApiOAD0AQAAAA==.Luckylite:BAAANQAECgIIAgAAAA==.Lulilaj:BAABNQAECn8vAAIfAAgKtRfiBwBsAgAfAAgKtRfiBwBsAgAAAA==.',
Ma='Maike:BAABNQAECn8eAAIaAAkKyBRlGwD7AQAaAAkKyBRlGwD7AQAAAA==.Marothius:BAACNQAFFH8VAAMUAAYKDhYpGAAzAQAUAAUK4hkpGAAzAQAdAAEKkwqjHgBLAAA1AAQKfzMAAxQACgrxHfgeAEQCABQACQo2HfgeAEQCAB0ABQoVGbgfAHIBAAAA.Marrius:BAAANQADCgYIBwAAAA==.Martaug:BAABNQAECn8lAAILAAoKRCEDFwAaAwALAAoKRCEDFwAaAwAAAA==.Marune:BAABNQAECn8oAAMgAAoKWxPyHQDwAQAgAAoKWxPyHQDwAQAiAAcKjw4uHwBhAQAAAA==.Maverage:BAABNQAECn8ZAAIOAAkKDxo5WACDAgAOAAkKDxo5WACDAgAAAA==.Mayfair:BAAANQAECgMIAwAAAA==.',
Me='Melee:BAABNQAECn8oAAIDAAgKrxuERwC+AgADAAgKrxuERwC+AgAAAA==.Metal:BAAANQADCgcIEwAAAA==.',
Mi='Minibolt:BAAANQADCgEIAQAAAA==.Minimee:BAAANQAECgEIAQAAAA==.Miquella:BAABNQAECn8ZAAIEAAgKbhvPOgDfAQAEAAgKbhvPOgDfAQAAAA==.',
Mo='Mollymauk:BAAANQADCgQIBAABNQAECgoKKQATAPIgAA==.Monkstrosity:BAAANQAECgcIEAAAAA==.Mookks:BAAANQADCgUIBQAAAA==.Moonn:BAABNQAECn8VAAIcAAkKvwg6hACaAQAcAAkKvwg6hACaAQAAAA==.Moor:BAAANQAECgUIDgAAAA==.Mordakka:BAABNQAECn8UAAIJAAgK+A9F1QDcAQAJAAgK+A9F1QDcAQAAAA==.Morior:BAABNQAECn8uAAMUAAoKwxFFfADwAQAUAAkKdhBFfADwAQAdAAEK3RrKaQBNAAAAAA==.',
Mu='Mulletmaster:BAAANQAECgUJCQAAAA==.Murrda:BAABNQAECn9BAAMUAAoKyxb5TgBnAgAUAAoKaxT5TgBnAgAdAAEKtBjXJQBAAAAAAA==.',
My='Myrokos:BAABNQAECn85AAIDAAoKah8LNAD8AgADAAoKah8LNAD8AgAAAA==.',
['Mö']='Möokss:BAABNQAECn8jAAIGAAgKKgwyqQCzAQAGAAgKKgwyqQCzAQAAAA==.',
Na='Nailo:BAAANQADCggICAAAAA==.Nasperus:BAAANQABCgIIAgAAAA==.',
Ni='Niddles:BAAANQAECggICwAAAA==.Niddy:BAABNQAECn88AAMfAAoK7xwcAwAeAwAfAAoKERwcAwAeAwAJAAQKMwvdlgGZAAAAAA==.',
No='Nobudee:BAAANQADCgcIBwABNQAFFAcIEgAcACgZAA==.Nocandles:BAABNQAECn8yAAIbAAkKryAkCgBRAgAbAAkKryAkCgBRAgAAAA==.Noebuddie:BAACNQAFFH8SAAIcAAcKKBmMCwCyAQAcAAcKKBmMCwCyAQA1AAQKfzAAAxwACgqoIpocAB4DABwACgqoIpocAB4DABgABApxEGUYAAsBAAAA.Noel:BAAANQAECgYIEgAAAA==.Nonospot:BAABNQAECn8eAAIbAAkKtxAFJwD0AQAbAAkKtxAFJwD0AQAAAA==.Noraboo:BAABNQAECn8aAAIJAAoKdB3NTwDhAgAJAAoKdB3NTwDhAgAAAA==.Norganon:BAAANQAECgcICgAAAA==.Novembér:BAAANQADCgMIAwAAAA==.',
Nv='Nvied:BAABNQAECn8cAAMUAAgKFhdSiADRAQAUAAcK7BZSiADRAQAdAAIKuxAnWAB3AAAAAA==.',
Ny='Nyctt:BAABNQAECn8xAAIaAAoK4xpJCgDQAgAaAAoK4xpJCgDQAgAAAA==.Nyzstra:BAABNQAECn8qAAIJAAoKkB2wOgASAwAJAAoKkB2wOgASAwAAAA==.',
['Nê']='Nêwt:BAACNQAFFH8JAAIJAAIKOQgKKwCCAAAJAAIKOQgKKwCCAAA1AAQKfzYAAgkACgq5EfA+APkBAAkACgq5EfA+APkBAAAA.',
On='Onlybeams:BAABNQAECn8aAAIFAAgKUxdOHwBUAgAFAAgKUxdOHwBUAgAAAA==.',
Or='Orcs:BAAANQADCgUIBQAAAA==.Oreo:BAAANQADCgcIEQAAAA==.Orphu:BAAANQADCgQIBwAAAA==.',
Pa='Pallyplexity:BAAANQAECgMIAwABNQAECgoKOgAPAFglAA==.Palmiste:BAAANQAECgQIBAAAAA==.Pangoplexity:BAAANQABCgMJAwAAAA==.Papichulo:BAAANQADCgQIBAAAAA==.Parahsalin:BAABNQAECn8dAAMEAAgKjw5oKwBCAQAEAAgKjw5oKwBCAQAFAAIKVgHfZwBFAAAAAA==.Pastryblust:BAACNQAFFH8WAAMcAAYKPhQJDwB+AQAcAAUKahMJDwB+AQAYAAMKGBAJAgD1AAA1AAQKf0MAAxwACgosIWAXADwDABwACQoVIWAXADwDABgACgqRHWUEALQCAAAA.',
Pe='Pennyzillin:BAAANQADCggICAABNQAECggIHQAEAI8OAA==.Pewpewmon:BAAANQADCgcIBwABNQAECgoKOgAPAFglAA==.',
Pi='Pistachio:BAAANQADCggIHgAAAA==.Pitviper:BAABNQAECn8uAAIMAAoKzhXrKQBFAgAMAAoKzhXrKQBFAgAAAA==.',
Po='Pogaca:BAAANQADCggIEwAAAA==.Portabull:BAAANQADCgcIBwABNQAECgoKLgABAAglAA==.',
Pr='Precogvendor:BAAANQAECgQIBwAAAA==.',
Ra='Raddelwingus:BAAANQADCgMIAwABNQAECgoKOgAPAFglAA==.Rai:BAABNQAECn8tAAIGAAkKdyOEHAAlAwAGAAkKdyOEHAAlAwAAAA==.Ramens:BAAANQAECgIIAgAAAA==.Rapha:BAABNQAECn8dAAIKAAkK8CBECACqAgAKAAkK8CBECACqAgAAAA==.Rayyzor:BAABNQAECn8qAAIFAAoKLiGNDQANAwAFAAoKLiGNDQANAwAAAA==.',
Re='Reality:BAAANQADCgQICAAAAA==.Realtree:BAAANQADCgQIBwAAAA==.',
Ri='Riddles:BAAANQAECgcIEQAAAA==.',
Ro='Rot:BAABNQAECn8uAAIIAAoKAiOPDABOAwAIAAoKAiOPDABOAwAAAA==.',
Ru='Rusty:BAAANQADCgUIBQAAAA==.',
Sa='Santino:BAAANQADCgcICAABNQAECgkJIQAJABoNAA==.Sapherapal:BAAANQADCgMIAwAAAA==.Saphlocket:BAAANQAECgMICQAAAA==.Saphmage:BAAANQAECgMIBwAAAA==.Sathin:BAABNQAECn8tAAIFAAkKKQcSIwAPAQAFAAkKKQcSIwAPAQAAAA==.',
Sc='Scher:BAAANQAECgMIAwAAAA==.Scufalufagus:BAAANQADCgUIBQABNQAFFAYIFQAUAA4WAA==.',
Se='September:BAAANQADCgYIBgABNQAECggIFgAbAKAHAA==.Seqsy:BAAANQAECgQIDAAAAA==.',
Sf='Sfcwarner:BAAANQADCgYIDQAAAA==.',
Sg='Sgtwarner:BAAANQAECgUIBAAAAA==.',
Sh='Shampooyou:BAABNQAECn8iAAILAAkKHw2degCcAQALAAkKHw2degCcAQAAAA==.Shocka:BAAANQAECgIIAgAAAA==.Shockakhan:BAAANQADCgQIBAAAAA==.',
Si='Silentkit:BAABNQAECn8bAAMSAAcK0hL+RwCeAQASAAcK0hL+RwCeAQAVAAMKowq/rwCTAAAAAA==.',
Ss='Ssgwarner:BAAANQADCgEIAQAAAA==.',
St='Stardel:BAABNQAECn8UAAIQAAgKxx0EBQB+AgAQAAgKxx0EBQB+AgABNQAFFAcIDgAaAPojAA==.Stormclaw:BAABNQAECn8+AAMCAAoKpB20CgCiAgACAAoKpB20CgCiAgAkAAkK7BQfHwA0AgAAAA==.Stregglebus:BAAANQAECgYIDgABNQAFFAYIFQAUAA4WAA==.Stregoica:BAAANQAECgYIBgABNQAFFAYIFQAUAA4WAA==.Stroggosh:BAAANQAECgEIAQABNQAFFAYIFQAUAA4WAA==.',
Su='Suhfering:BAABNQAECn8WAAIUAAoKYxIefQDuAQAUAAoKYxIefQDuAQABNQAECggIGgAFAFMXAA==.Sunshot:BAAANQAECgEIAQAAAA==.Surrs:BAAANQAECgIIAgABNQAECggIFgAbAKAHAA==.',
Ta='Takrusani:BAAANQADCgIIAgAAAA==.Tallron:BAACNQAFFH8WAAIkAAcK9xF1BwCFAQAkAAcK9xF1BwCFAQA1AAQKfzAAAiQACgr3Ht0RAMICACQACgr3Ht0RAMICAAAA.Tamedsloth:BAAANQAECgUIBAAAAA==.Tanerella:BAAANQAECgQICAAAAA==.',
Th='Thrustruggle:BAABNQAECn8iAAIWAAoKbRL5FQBjAQAWAAoKbRL5FQBjAQAAAA==.',
Ti='Timir:BAACNQAFFH8TAAIDAAcKGhJmDQB1AQADAAcKGhJmDQB1AQA1AAQKfzIAAgMACgqiHGZSAL4BAAMACgqiHGZSAL4BAAAA.Tinynutz:BAAANQADCgYICQAAAA==.',
To='Tojikitoushi:BAABNQAECn86AAIYAAoKwRRQDwB0AgAYAAoKwRRQDwB0AgAAAA==.Tombs:BAAANQAECgEIAQABNQAECgoKKQATAPIgAA==.Totenhammer:BAAANQADCgYIBwAAAA==.Touche:BAABNQAECn8gAAIJAAoKIQ9gygDxAQAJAAoKIQ9gygDxAQAAAA==.',
Tr='Tribulate:BAAANQADCggIDAAAAA==.Trollyroller:BAAANQADCggIFAAAAA==.',
Tw='Twistedfrost:BAAANQADCgUIBQAAAA==.',
Ul='Ulrein:BAAANQAECgIIAwAAAA==.',
Ve='Vextt:BAABNQAECn8jAAMXAAoKih6NIgDkAgAXAAkK7CCNIgDkAgAbAAgKWh0cHABkAgABNQAECgoKKQATAPIgAA==.Veylira:BAABNQAECn8bAAMUAAgKVxiHjADHAQAUAAgKVxiHjADHAQAdAAIKGBSUVQB+AAABNQAECgoKQAAOAE8iAA==.',
Vi='Vicsta:BAAANQAECgIIAgAAAA==.Vitner:BAABNQAECn8YAAIUAAkKrRf7VgBRAgAUAAkKrRf7VgBRAgAAAA==.',
Vo='Voidra:BAAANQAECgEIBAAAAA==.Voidwarner:BAAANQADCggICAAAAA==.Volight:BAAANQAECgQIBgAAAA==.Volke:BAABNQAECn8uAAIlAAoKmhOlGQDlAQAlAAoKmhOlGQDlAQAAAA==.Voltarix:BAAANQADCgEIAQAAAA==.Voyria:BAABNQAECn8tAAMkAAkKQgwdJgAsAQAkAAkKQgwdJgAsAQACAAIKuAHGtQAtAAAAAA==.',
Vy='Vyskar:BAAANQADCgUIBAAAAA==.',
['Vê']='Vênm:BAAANQAECgMIBAABNQAFFAQIDQAKAOoYAA==.',
Wa='Warm:BAAANQAECgQICAAAAA==.',
We='Weeziveli:BAAANQADCgYIBgAAAA==.Weledish:BAACNQAFFH8QAAMJAAYKXw9ZJQBcAQAJAAUKzQ9ZJQBcAQAfAAEKFA6iEwBHAAA1AAQKfzYAAwkACgraH180ACEDAAkACgrNH180ACEDAB8AAgpgG/wpAKgAAAAA.Weleron:BAAANQADCgIIAgAAAA==.',
Wi='Widdles:BAAANQAECgMIAwAAAA==.',
Yi='Yinyangfaith:BAAANQADCgEIAQABNQAECgoKKAAXAAAWAA==.',
Ze='Zerea:BAAANQABCgEIAQAAAA==.',
Zo='Zomgdk:BAABNQAECn85AAIIAAoKHSC5BwCAAwAIAAoKHSC5BwCAAwAAAA==.',
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
