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

local lookup = {'Druid-Feral','Druid-Balance','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Protection','DeathKnight-Blood','Mage-Arcane','Druid-Guardian','Monk-Brewmaster','Shaman-Restoration','Rogue-Assassination','Warrior-Fury','Warrior-Arms','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Monk-Windwalker','DeathKnight-Frost','Paladin-Holy','Warlock-Demonology','DeathKnight-Unholy','Priest-Holy','Shaman-Enhancement','Rogue-Subtlety','Priest-Shadow','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Druid-Restoration','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=53,date='2026-11-17',data={Ad='Adira:BAAANQADCgYIDAAAAA==.Adorabull:BAABNQAECn8wAAMBAAoKQyWJAwBmAwABAAkKQyWJAwBmAwACAAYKbxlYXQBcAQAAAA==.',
Ae='Aemun:BAAANQADCggIEgAAAA==.',
Ag='Aggfu:BAAANQADCgcIBwABNQAECgoKGwADAKQUAA==.',
Ak='Akelita:BAABNQAECn8UAAMEAAcKNRd8QAC6AQAEAAcKNRd8QAC6AQAFAAIKCQZyZQBTAAAAAA==.',
Al='Alailea:BAABNQAECn9HAAIGAAoKWhNkUgAoAgAGAAoKWhNkUgAoAgAAAA==.Aloepaw:BAAANQAECgYIBwAAAA==.Aloepriest:BAAANQAECgIIAgAAAA==.Alwysafkable:BAABNQAECn8ZAAIHAAoKnRxFFQBXAgAHAAoKnRxFFQBXAgAAAA==.',
An='Anastasía:BAABNQAECn8vAAIIAAoKbhDGRQDjAQAIAAoKbhDGRQDjAQAAAA==.Anzul:BAAANQADCgYICgAAAA==.',
As='Asure:BAABNQAECn8pAAIGAAoK+Qu7hwD7AQAGAAoK+Qu7hwD7AQAAAA==.',
Ay='Ayesu:BAAANQAECgUIDAABNQAECgoKIgAJAOEfAA==.',
Az='Azerith:BAAANQADCgYIDgAAAA==.',
Ba='Balahuk:BAACNQAFFH8GAAIKAAQKqQxRBQCpAAAKAAQKqQxRBQCpAAA1AAQKfx4AAgoACQpPGY0OAE4CAAoACQpPGY0OAE4CAAE1AAUUBAgOAAsA6hgA.',
Bl='Bloodfish:BAABNQAECn8YAAIIAAkKNiDHDwAvAwAIAAkKNiDHDwAvAwAAAA==.',
Bo='Bomber:BAAANQADCgQIBAAAAA==.Bombs:BAAANQAECgYICgABNQAFFAcIHQAMAKIdAA==.Bonesy:BAABNQAECn8VAAINAAgKZQh8RAC2AQANAAgKZQh8RAC2AQAAAA==.',
Br='Brothermage:BAAANQAECgQIBAAAAA==.',
Bu='Burdomew:BAAANQAECgUIDQAAAA==.',
['Bà']='Bàwitdàbà:BAABNQAECn8vAAIMAAgKcxWEUADRAQAMAAgKcxWEUADRAQAAAA==.',
['Bö']='Börs:BAAANQADCgEIAQAAAA==.',
Ca='Cadbringer:BAAANQADCggJCAAAAA==.Cadbury:BAAANQAECgQICAAAAA==.Cananojii:BAAANQADCgQIBgAAAA==.Cantona:BAAANQAECgEIAQAAAA==.Casmina:BAABNQAECn8oAAMOAAkKFhf1DwB8AQAOAAkKcRX1DwB8AQAPAAUKXA/kwgDvAAAAAA==.',
Ce='Ceola:BAABNQAECn83AAIQAAoK3RUOEwCMAQAQAAoK3RUOEwCMAQAAAA==.',
Ch='Chamichurri:BAAANQADCgQIBAAAAA==.Chamming:BAAANQAECgIIAgAAAA==.Chaw:BAACNQAFFH8UAAIGAAcKuRuSCADBAQAGAAcKuRuSCADBAQA1AAQKfz8ABAYACgpLJCoYADkDAAYACgo8JCoYADkDABEACQqaHd4BANYCABIAAQoKDodpADEAAAAA.Chawdan:BAAANQADCgcIBwAAAA==.Chenkenichi:BAABNQAECn8+AAITAAoKPgxnIACbAQATAAoKPgxnIACbAQAAAA==.Chillout:BAAANQAECgcIDAAAAA==.',
Ci='Cinny:BAABNQAECn8zAAIGAAoKuRKGVgBvAgAGAAoKuRKGVgBvAgAAAA==.Cityairlines:BAABNQAECn8yAAIUAAoKXw8WPwDOAQAUAAoKXw8WPwDOAQAAAA==.',
Cm='Cmoneyy:BAAANQADCgYIBgAAAA==.',
Co='Cooldukenuke:BAABNQAECn8iAAIVAAgKaB95LAC1AgAVAAgKaB95LAC1AgAAAA==.',
Cr='Criticize:BAABNQAECn8YAAIDAAgKFQ9jsgC6AQADAAgKFQ9jsgC6AQAAAA==.',
Cs='Csorpa:BAAANQAECgEIAQAAAA==.',
Cu='Cultist:BAAANQAECgcIDAAAAA==.Cupcakes:BAABNQAECn9KAAQDAAoK3CJJFAATAwADAAoK3CJJFAATAwAHAAQKaRSRQgDqAAAVAAUKRhSl3QDDAAABNQAECgoKRgAIAI8kAA==.',
De='Deadbrum:BAAANQADCgYIBgABNQAECgoKQgAMAFUfAA==.Deagua:BAAANQADCggIDwABNQAFFAYIFQAWAA4WAA==.Deardra:BAAANQAECgMIBgAAAA==.Dejavu:BAACNQAFFH8OAAILAAQK6hjzBAA6AQALAAQK6hjzBAA6AQA1AAQKfzAAAgsACgqmHl0GAOgCAAsACgqmHl0GAOgCAAAA.Demontae:BAAANQADCgEIAQAAAA==.Desdemona:BAAANQAECgYICwAAAA==.',
Di='Disd:BAAANQAECgQIBAAAAA==.Disog:BAAANQAECgMIBAAAAA==.Dispal:BAAANQAECgIIAgAAAA==.',
Do='Doodoopoopoo:BAAANQAECggIAQAAAA==.',
Dr='Dracz:BAAANQAECggIDQAAAA==.Dragonthingy:BAAANQAECgUIBQABNQAFFAYIFQAWAA4WAA==.Dropdead:BAAANQAECgQIBAAAAA==.Dropkick:BAABNQAECn8gAAIDAAkKSxIWjwCuAQADAAkKSxIWjwCuAQAAAA==.',
Du='Duplexity:BAABNQAECn9MAAMQAAoK8SX2AABwAwAQAAoK8SX2AABwAwAPAAEKkxG0SwE7AAAAAA==.',
Dv='Dvxmatt:BAAANQAECgUIEwAAAA==.',
Dw='Dwalin:BAAANQAECgcIEQAAAA==.',
Eg='Egohakai:BAACNQAFFH8TAAIDAAYK1RvxCgCZAQADAAYK1RvxCgCZAQA1AAQKfz4AAgMACgqLI9AXAAMDAAMACgqLI9AXAAMDAAAA.',
El='Elfy:BAAANQADCgUIBQAAAA==.',
Em='Emieretta:BAABNQAECn8qAAMUAAoK8hHBPADaAQAUAAkKoRHBPADaAQAXAAYKxQv+hAAMAQAAAA==.',
Er='Errekt:BAAANQAECgIIAgAAAA==.Erret:BAACNQAFFH8LAAIJAAUKCAhTJQBcAQAJAAUKCAhTJQBcAQA1AAQKf04AAgkACgpHHnIrAJECAAkACgpHHnIrAJECAAAA.',
Et='Ethaka:BAABNQAECn8cAAMGAAkKqRfzawA7AgAGAAkKNRbzawA7AgASAAEK9Q5/gwA8AAAAAA==.',
Ey='Eywae:BAAANQADCgcIBwAAAA==.',
Fa='Faemos:BAAANQAECgYICwAAAA==.Faience:BAABNQAECn8sAAIUAAgK9wRwawDvAAAUAAgK9wRwawDvAAAAAA==.Falorina:BAACNQAFFH8JAAIEAAQKWRaCDgDdAAAEAAQKWRaCDgDdAAA1AAQKf0oAAgQACgphJakCAMoDAAQACgphJakCAMoDAAAA.Fathernature:BAABNQAECn87AAMBAAoKWhs1CABsAgABAAoKiBo1CABsAgACAAoKIRnDIgDnAQAAAA==.',
Fe='Feldra:BAABNQAECn9EAAIFAAoKsiNABgD6AgAFAAoKsiNABgD6AgAAAA==.',
Fi='Finnin:BAABNQAECn8vAAMPAAoKGh0tVACOAgAPAAoKGh0tVACOAgAOAAEKFCDEKwBWAAAAAA==.',
Fo='Food:BAABNQAECn8uAAIGAAoKyw/RdQAkAgAGAAoKyw/RdQAkAgAAAA==.',
Fr='Frozenfaith:BAABNQAECn8sAAIYAAoKXBbQXwABAgAYAAoKXBbQXwABAgAAAA==.',
Fu='Furba:BAABNQAECn8wAAIGAAoKlRmGMwDRAgAGAAoKlRmGMwDRAgAAAA==.Furioushealz:BAAANQAECgEIAQAAAA==.Furiouswind:BAABNQAECn8uAAIZAAoK2hfVDwBrAgAZAAoK2hfVDwBrAgAAAA==.Furyvolt:BAABNQAECn8aAAIZAAoKDA26HQCGAQAZAAoKDA26HQCGAQAAAA==.',
Gh='Ghettomike:BAABNQAECn8rAAIXAAoKlB6IJQCpAgAXAAoKlB6IJQCpAgAAAA==.Ghold:BAABNQAECn8uAAQVAAoKJCJYEQAyAwAVAAoKJCJYEQAyAwADAAMKzQcJYwGBAAAHAAEKAAB5dwAlAAAAAA==.',
Gi='Giranimo:BAABNQAECn8bAAIGAAoK0AzFwwB6AQAGAAoK0AzFwwB6AQAAAA==.',
Gl='Glabados:BAABNQAECn8eAAIKAAoKeCMYBQBNAwAKAAoKeCMYBQBNAwABNQAECgoKIwALAJggAA==.Glossy:BAACNQAFFH8VAAMaAAcK3yPFBwCKAQAaAAYKJCPFBwCKAQANAAEKzibzGQBwAAA1AAQKfzYAAxoACQrhJdkyADACABoACAqIJdkyADACAA0ABAq6JWtHAKcBAAAA.',
Go='Gorkus:BAAANQADCgMIAwAAAA==.Gors:BAAANQAECgQIBQAAAA==.',
Gr='Grandpaswamp:BAAANQAECgQIBQAAAA==.Gratiaplena:BAAANQABCgQIBwAAAA==.',
Ha='Halîk:BAABNQAECn8hAAIVAAoKtxAaagDZAQAVAAoKtxAaagDZAQAAAA==.Hardheaded:BAAANQAECgcICQAAAA==.Harloww:BAAANQADCgEIAQAAAA==.Hathina:BAACNQAFFH8LAAMOAAcK+xmtAQAPAQAOAAQKERqtAQAPAQAPAAMK7RnOKwCbAAA1AAQKfywAAw4ACgqUJIwDAB0DAA4ACQoeJYwDAB0DAA8AAQrLIMZBAU8AAAAA.',
He='Hedetet:BAAANQABCgEIAQABNQAECggIGgAFAFMXAA==.Heket:BAAANQAECgYICgAAAA==.Herath:BAAANQABCggIDwAAAA==.',
Hi='Hill:BAABNQAECn8nAAIGAAoKYRSjYwBOAgAGAAoKYRSjYwBOAgAAAA==.Hive:BAABNQAECn8rAAIPAAoK8g6ujwD1AQAPAAoK8g6ujwD1AQAAAA==.',
Ho='Holdyfolds:BAAANQADCgcICAABNQAFFAYIFQAWAA4WAA==.',
Hu='Husentar:BAAANQADCgYICwAAAA==.',
Ig='Igni:BAAANQABCgMIBAAAAA==.',
Il='Illuminottey:BAAANQADCgEIAQAAAA==.',
Im='Impériavil:BAAANQAECgQIBgAAAA==.',
In='Inferium:BAAANQADCgcIBwAAAA==.Insatiabull:BAABNQAECn8nAAMEAAoKeyCQGQDOAgAEAAkKIyCQGQDOAgAFAAIKSSP2SgBnAAABNQAECgoKMAABAEMlAA==.',
Ir='Iriaena:BAAANQADCgYIDwAAAA==.',
Is='Ishaa:BAAANQAECggICwAAAA==.',
Ja='Jackstands:BAABNQAECn89AAIMAAoKDyLaEAA/AwAMAAoKDyLaEAA/AwAAAA==.Jagerin:BAAANQAECggIEQABNQAECgoKIwALAJggAA==.January:BAABNQAECn8WAAIbAAgKoAeXNwBoAQAbAAgKoAeXNwBoAQAAAA==.Jarry:BAAANQAECgMIBQAAAA==.',
Je='Jeannine:BAABNQAECn8cAAIJAAgKnAcKvQAsAQAJAAgKnAcKvQAsAQAAAA==.',
Ju='Junn:BAABNQAECn8yAAIcAAoKfw8xcADQAQAcAAoKfw8xcADQAQAAAA==.',
['Já']='Jánuary:BAABNQAECn8jAAQdAAkKRg5oDQDpAAAWAAkK4QqjeAD5AQAeAAUKeQqQFAABAQAdAAcKkwxoDQDpAAAAAA==.',
Ka='Kahayman:BAABNQAECn8mAAMJAAoKRA0ZsAAjAgAJAAoKRA0ZsAAjAgAfAAQKNAT8LQCOAAAAAA==.Kaimari:BAABNQAECn8dAAQKAAkKPhG5KABQAQAKAAcKDRe5KABQAQACAAgKywJ3cAAIAQABAAMKrQJfPABIAAAAAA==.Katniss:BAAANQAECgQIBAAAAA==.Kazuya:BAAANQAECgEIAQAAAA==.',
Ke='Kennyboi:BAAANQADCgIIAgAAAA==.',
Kh='Khaibit:BAABNQAECn9AAAIUAAoKYCHNCQBOAwAUAAoKYCHNCQBOAwAAAA==.Khathani:BAAANQADCggIDwAAAA==.',
Ki='Kirara:BAABNQAECn8aAAIGAAkKdA7oYgAAAgAGAAkKdA7oYgAAAgAAAA==.Kissofdeath:BAABNQAECn8vAAINAAoKXQziFwBpAQANAAoKXQziFwBpAQAAAA==.',
Ko='Komojo:BAAANQAECgcIEAAAAA==.Koriggan:BAABNQAECn81AAIRAAoK/xkyBQB1AgARAAoK/xkyBQB1AgAAAA==.',
Kr='Krea:BAABNQAECn87AAMHAAoK2iT3BQBNAwAHAAoK2iT3BQBNAwADAAYKlBe+tABnAQAAAA==.Kroval:BAABNQAECn8jAAINAAoKFwm3RQCwAQANAAoKFwm3RQCwAQAAAA==.Krystagosa:BAABNQAECn8iAAQgAAgKqw/6FgCFAQAgAAgKqw/6FgCFAQAhAAYKlQ3gEAApAQAiAAMK7gT1MQCCAAAAAA==.',
Ku='Kuriuh:BAAANQAECgcIDwAAAA==.',
Ky='Kybo:BAAANQABCgMIAwABNQAFFAQIDQACAE4aAA==.Kyo:BAAANQADCgUIBQAAAA==.',
La='Lang:BAABNQAECn8vAAIjAAoKwxmMCADxAQAjAAoKwxmMCADxAQAAAA==.',
Li='Lightdogg:BAAANQAECgcIEQAAAA==.Limaia:BAABNQAECn8zAAMkAAkKKg7uKwC9AQAkAAkKKg7uKwC9AQACAAYKgAYnWwC0AAAAAA==.Linia:BAAANQAECgEIAQAAAA==.',
Lo='Lockndrop:BAAANQADCgEIAQAAAA==.Loopey:BAAANQAECgMIAwABNQAFFAQIDgALAOoYAA==.',
Lu='Luceriss:BAABNQAECn8UAAINAAkKOApiOAD0AQANAAkKOApiOAD0AQAAAA==.Luckylite:BAAANQAECgIIAgAAAA==.Lulilaj:BAABNQAECn8/AAIfAAoKLBriBwBsAgAfAAoKLBriBwBsAgAAAA==.',
Ma='Maike:BAABNQAECn8tAAIaAAoKyRNlGwD7AQAaAAoKyRNlGwD7AQAAAA==.Marothius:BAACNQAFFH8VAAMWAAYKDhYpGAAzAQAWAAUK4hkpGAAzAQAdAAEKkwqjHgBLAAA1AAQKfzwABBYACgqzHwsoAG8CABYACQp/HwsoAG8CAB0ABQoVGbgfAHIBAB4AAQrxHlskAFwAAAAA.Marrius:BAAANQADCgYIBwAAAA==.Martaug:BAABNQAECn8qAAIMAAoKRCEDFwAaAwAMAAoKRCEDFwAaAwAAAA==.Marune:BAABNQAECn8sAAMgAAoKWxPyHQDwAQAgAAoKWxPyHQDwAQAiAAgKDA0uHwBhAQAAAA==.Maverage:BAABNQAECn8bAAIPAAoKAxo5WACDAgAPAAoKAxo5WACDAgAAAA==.Mayfair:BAAANQAECgIIAwAAAA==.',
Me='Melee:BAABNQAECn8oAAIDAAgKrxuERwC+AgADAAgKrxuERwC+AgAAAA==.Metal:BAAANQADCgcIEwAAAA==.',
Mi='Miluda:BAAANQAECggIDgABNQAECgoKIwALAJggAA==.Minibolt:BAAANQADCgEIAQAAAA==.Minimee:BAAANQAECgEIAQAAAA==.Miquella:BAABNQAECn8gAAIEAAkKch3POgDfAQAEAAkKch3POgDfAQAAAA==.',
Mo='Mollymauk:BAAANQADCgQIBAABNQAECgoKLgAVACQiAA==.Monkstrosity:BAAANQAECgcIEAAAAA==.Mookks:BAAANQADCgYIBQAAAA==.Moonn:BAABNQAECn8VAAIcAAkKvwg6hACaAQAcAAkKvwg6hACaAQAAAA==.Moor:BAABNQAECn8UAAIJAAcK+gLhAwGuAAAJAAcK+gLhAwGuAAAAAA==.Mordakka:BAABNQAECn8UAAIJAAgK+A9F1QDcAQAJAAgK+A9F1QDcAQAAAA==.Morior:BAABNQAECn8vAAMWAAoK2xFFfADwAQAWAAkKkhBFfADwAQAdAAEK3RrKaQBNAAAAAA==.',
Mu='Mulletmaster:BAAANQAECgYICQAAAA==.Murrda:BAABNQAECn9NAAMWAAoKgxmCNgA3AgAWAAoKIxeCNgA3AgAdAAEKtBjENAA+AAAAAA==.',
My='Myrokos:BAABNQAECn9BAAIDAAoK2B8LNAD8AgADAAoK2B8LNAD8AgAAAA==.',
['Mö']='Möokss:BAABNQAECn8sAAIGAAoKLg3tawDqAQAGAAoKLg3tawDqAQAAAA==.',
Na='Nailo:BAAANQADCggICAAAAA==.Nasperus:BAAANQABCgIIAgAAAA==.',
Ni='Niddles:BAAANQAECggIDgAAAA==.Niddy:BAABNQAECn9HAAMfAAoKFSAcAwAeAwAfAAoKFSAcAwAeAwAJAAQKMwtQKQFxAAAAAA==.',
No='Nobudee:BAAANQADCgcIBwABNQAFFAcIEgAcACgZAA==.Nocandles:BAABNQAECn9BAAIbAAoKNSHYBwDqAgAbAAoKNSHYBwDqAgAAAA==.Nocturn:BAAANQAECgYIBgAAAA==.Noebuddie:BAACNQAFFH8SAAIcAAcKKBmMCwCyAQAcAAcKKBmMCwCyAQA1AAQKfzgAAxwACgpEI5ocAB4DABwACgqoIpocAB4DABkABQpiH84TANoBAAAA.Noel:BAABNQAECn8hAAIYAAgK5xQ0TwD8AQAYAAgK5xQ0TwD8AQAAAA==.Nonospot:BAABNQAECn8fAAIbAAoKYxAFJwD0AQAbAAoKYxAFJwD0AQAAAA==.Noraboo:BAABNQAECn8iAAIJAAoK4R/NTwDhAgAJAAoK4R/NTwDhAgAAAA==.Norganon:BAABNQAECn8XAAIJAAoKvBsGNQBvAgAJAAoKvBsGNQBvAgAAAA==.Novembér:BAAANQADCgMIAwAAAA==.',
Nv='Nvied:BAABNQAECn8fAAMWAAgKFhdSiADRAQAWAAgKCRdSiADRAQAdAAIKuxAnWAB3AAAAAA==.',
Ny='Nyctt:BAABNQAECn81AAIaAAoK4xpJCgDQAgAaAAoK4xpJCgDQAgAAAA==.Nyzstra:BAABNQAECn8qAAIJAAoKkB2wOgASAwAJAAoKkB2wOgASAwAAAA==.',
['Nê']='Nêwt:BAACNQAFFH8KAAIJAAMKGwadMACvAAAJAAMKGwadMACvAAA1AAQKf0gAAgkACgq6EoZfAPkBAAkACgq6EoZfAPkBAAAA.',
On='Onlybeams:BAABNQAECn8aAAIFAAgKUxdOHwBUAgAFAAgKUxdOHwBUAgAAAA==.',
Or='Orcs:BAAANQADCgUIBQAAAA==.Oreo:BAAANQADCgcIEQAAAA==.Orphu:BAAANQADCgQIBwAAAA==.',
Pa='Pallyplexity:BAAANQAECgMIAwABNQAECgoKTAAQAPElAA==.Palmiste:BAAANQAECgQIBAAAAA==.Pandoora:BAAANQADCgYIEAAAAA==.Pangoplexity:BAAANQABCgMJAwAAAA==.Papichulo:BAAANQADCgQIBAAAAA==.Parahsalin:BAABNQAECn8oAAMEAAkKDQ7oOQBbAQAEAAkKDQ7oOQBbAQAFAAIKVgHfZwBFAAAAAA==.Pastryblust:BAACNQAFFH8XAAMZAAcKnhFQAgAsAQAcAAUKahMJDwB+AQAZAAQK2g1QAgAsAQA1AAQKf1kAAxkACgpqImIDABkDABwACQoVIWAXADwDABkACgrJIWIDABkDAAAA.',
Pe='Pennyzillin:BAAANQADCggICAABNQAECgkJKAAEAA0OAA==.Pewpewmon:BAAANQADCgcIBwABNQAECgoKTAAQAPElAA==.',
Pi='Pistachio:BAAANQADCggIHgAAAA==.Pitviper:BAABNQAECn8yAAINAAoK+BfrKQBFAgANAAoK+BfrKQBFAgAAAA==.',
Po='Pogaca:BAAANQADCggIEwAAAA==.Portabull:BAAANQADCgcIBwABNQAECgoKMAABAEMlAA==.',
Pr='Precogvendor:BAABNQAECn8UAAMEAAoKcw2KLACuAQAEAAoKxgyKLACuAQAFAAMK/g+9WQCdAAAAAA==.',
Ra='Raddelwingus:BAAANQADCgMIAwABNQAECgoKTAAQAPElAA==.Rai:BAABNQAECn8xAAIGAAoKSCOEHAAlAwAGAAoKSCOEHAAlAwAAAA==.Ramens:BAAANQAECgIIAgAAAA==.Rapha:BAABNQAECn8jAAILAAoKmCBECACqAgALAAoKmCBECACqAgAAAA==.Rayyzor:BAABNQAECn8qAAIFAAoKLiGNDQANAwAFAAoKLiGNDQANAwAAAA==.',
Re='Reality:BAAANQADCgQICAAAAA==.Realtree:BAAANQADCgQIBwAAAA==.',
Ri='Riddles:BAAANQAECgcIEQAAAA==.',
Ro='Rot:BAABNQAECn8yAAIIAAoKhSOPDABOAwAIAAoKhSOPDABOAwAAAA==.',
Ru='Rusty:BAAANQADCgUIBQAAAA==.',
Sa='Santino:BAAANQADCgcICAABNQAECgoKJgAJAEQNAA==.Sapherapal:BAAANQADCgMIAwAAAA==.Saphlocket:BAAANQAECgMICQAAAA==.Saphmage:BAAANQAECgMIBwAAAA==.Sathin:BAABNQAECn8vAAIFAAoKGweeNgCOAQAFAAoKGweeNgCOAQAAAA==.',
Sc='Scher:BAAANQAECgMIAwAAAA==.Scufalufagus:BAAANQADCgUIBQABNQAFFAYIFQAWAA4WAA==.',
Se='September:BAAANQADCgYIBgABNQAECggIFgAbAKAHAA==.Seqsy:BAABNQAECn8WAAIcAAUKpg2DwgANAQAcAAUKpg2DwgANAQAAAA==.',
Sf='Sfcwarner:BAAANQADCgYIDQAAAA==.',
Sg='Sgtwarner:BAAANQAECgQIDgAAAA==.',
Sh='Shampooyou:BAABNQAECn80AAIMAAoKBQ2degCcAQAMAAoKBQ2degCcAQAAAA==.Shocka:BAAANQAECgMIBgAAAA==.Shockakhan:BAAANQADCgQIBAAAAA==.',
Si='Silentkit:BAABNQAECn8bAAMUAAcK0hL+RwCeAQAUAAcK0hL+RwCeAQAXAAMKowq/rwCTAAAAAA==.',
Ss='Ssgwarner:BAAANQADCgEIAQAAAA==.',
St='Stabanoob:BAAANQABCgMIAwAAAA==.Stardel:BAABNQAECn8UAAIRAAgKxx0EBQB+AgARAAgKxx0EBQB+AgABNQAFFAcIDgAaAPojAA==.Stormclaw:BAABNQAECn9QAAMCAAoK/R5JDwC4AgACAAoK/R5JDwC4AgAkAAkK7BQfHwA0AgAAAA==.Stregglebus:BAABNQAECn8gAAICAAoKUhg0GQBEAgACAAoKUhg0GQBEAgABNQAFFAYIFQAWAA4WAA==.Stregoica:BAAANQAECggIDgABNQAFFAYIFQAWAA4WAA==.Stroggosh:BAAANQAECgEIAQABNQAFFAYIFQAWAA4WAA==.',
Su='Suhfering:BAABNQAECn8bAAIWAAoKMBQefQDuAQAWAAoKMBQefQDuAQABNQAECggIGgAFAFMXAA==.Sunshot:BAAANQAECgEIAQAAAA==.Surrs:BAAANQAECgIIAgABNQAECggIFgAbAKAHAA==.',
Ta='Takrusani:BAAANQADCgIIAgAAAA==.Tallron:BAACNQAFFH8WAAIkAAcK9xF1BwCFAQAkAAcK9xF1BwCFAQA1AAQKf0IAAiQACgpOIxECAP4DACQACgpOIxECAP4DAAAA.Tamedsloth:BAAANQAECgUIBAAAAA==.Tanerella:BAABNQAECn8WAAMMAAUK3wdmsAC6AAAMAAUK3wdmsAC6AAAcAAQKZgXgxgB9AAAAAA==.',
Th='Thornevald:BAAANQABCgQIBAAAAA==.Thrustruggle:BAABNQAECn8rAAISAAoK3Ba1EwAHAgASAAoK3Ba1EwAHAgAAAA==.',
Ti='Timir:BAACNQAFFH8TAAIDAAcKGhJmDQB1AQADAAcKGhJmDQB1AQA1AAQKf0QAAgMACgqKIjUUABQDAAMACgqKIjUUABQDAAAA.Tinynutz:BAAANQADCgYICQAAAA==.',
To='Tojikitoushi:BAABNQAECn9IAAIZAAoK8xdQDwB0AgAZAAoK8xdQDwB0AgAAAA==.Tombs:BAAANQAECgEIAQABNQAECgoKLgAVACQiAA==.Totenhammer:BAAANQADCgYIBwAAAA==.Touche:BAABNQAECn8kAAIJAAoKqQ9gygDxAQAJAAoKqQ9gygDxAQAAAA==.',
Tr='Tribulate:BAAANQADCggIDAAAAA==.Trollyroller:BAAANQADCggIFAAAAA==.',
Tw='Twistedfrost:BAAANQADCgUIBQAAAA==.',
Ul='Ulrein:BAAANQAECgIIAwAAAA==.',
Ve='Veridrax:BAAANQADCgIIAgAAAA==.Vextt:BAABNQAECn8nAAMYAAoKKSGNIgDkAgAYAAoKKSGNIgDkAgAbAAkKChocHABkAgABNQAECgoKLgAVACQiAA==.Veylira:BAABNQAECn8bAAMWAAgKVxiHjADHAQAWAAgKVxiHjADHAQAdAAIKGBSUVQB+AAABNQAECgoKRwAPAE8iAA==.',
Vi='Vicsta:BAAANQAECgIIAgAAAA==.Vitner:BAABNQAECn8YAAIWAAkKrRf7VgBRAgAWAAkKrRf7VgBRAgAAAA==.',
Vo='Voidra:BAAANQAECgEIBAAAAA==.Voidwarner:BAAANQADCggICAAAAA==.Volight:BAAANQAECgQIBgAAAA==.Volke:BAABNQAECn8yAAIlAAoKshOlGQDlAQAlAAoKshOlGQDlAQAAAA==.Voltarix:BAAANQADCgEIAQAAAA==.Voyria:BAABNQAECn8vAAMkAAoKagshMwCCAQAkAAoKagshMwCCAQACAAIKuAHGtQAtAAAAAA==.',
Vy='Vyskar:BAAANQADCgUIBAAAAA==.Vyskari:BAAANQADCgUICAAAAA==.',
['Vê']='Vênm:BAAANQAECgMIBAABNQAFFAQIDgALAOoYAA==.',
Wa='Warm:BAAANQAECgQICAAAAA==.',
We='Weeziveli:BAAANQADCgYIBgAAAA==.Weledish:BAACNQAFFH8RAAMJAAcK4gxZJQBcAQAJAAUKzQ9ZJQBcAQAfAAIKggiEFQBHAAA1AAQKfzsAAwkACgoVIF80ACEDAAkACgoJIF80ACEDAB8AAgpgG/wpAKgAAAAA.Weleron:BAAANQADCgIIAgAAAA==.',
Wi='Widdles:BAAANQAECgMIAwAAAA==.',
Yi='Yinyangfaith:BAAANQADCgEIAQABNQAECgoKLAAYAFwWAA==.',
Ze='Zerea:BAAANQABCgEIAQAAAA==.',
Zo='Zomgdk:BAABNQAECn9BAAIIAAoKgSG5BwCAAwAIAAoKgSG5BwCAAwAAAA==.',
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
