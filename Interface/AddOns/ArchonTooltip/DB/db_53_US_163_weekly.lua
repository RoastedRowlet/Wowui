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

local lookup = {'Druid-Feral','Druid-Balance','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Protection','DeathKnight-Blood','Monk-Brewmaster','Shaman-Restoration','Warrior-Protection','Hunter-Survival','Monk-Windwalker','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Warlock-Demonology','Warrior-Arms','DeathKnight-Unholy','Mage-Arcane','Warrior-Fury','Priest-Holy','Shaman-Enhancement','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Shaman-Elemental','Warlock-Affliction','Warlock-Destruction','Mage-Frost','Druid-Guardian','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Druid-Restoration','Hunter-Marksmanship','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adira:BAAANQADCgYIBgAAAA==.Adorabull:BAABNQAECn8sAAMBAAkKLCV8AwBmAwABAAgKLCV8AwBmAwACAAYKbxl1XABbAQAAAA==.',
Ae='Aemun:BAAANQADCggIEgAAAA==.',
Ag='Aggfu:BAAANQADCgcIBwABNQAECgcIEQADAAAAAA==.',
Ak='Akelita:BAABNQAECn8UAAMEAAcKNRe0PwC6AQAEAAcKNRe0PwC6AQAFAAIKCQblYwBTAAAAAA==.',
Al='Alailea:BAABNQAECn8kAAIGAAgKRhLNbQA0AgAGAAgKRhLNbQA0AgAAAA==.Aloepaw:BAAANQAECgQIBgAAAA==.Alwysafkable:BAABNQAECn8VAAIHAAgK/xz5FABYAgAHAAgK/xz5FABYAgAAAA==.',
An='Anastasía:BAABNQAECn8jAAIIAAgKPRAHRQDkAQAIAAgKPRAHRQDkAQAAAA==.Anzul:BAAANQADCgYICgAAAA==.',
As='Asure:BAABNQAECn8dAAIGAAgKLwu+hQD8AQAGAAgKLwu+hQD8AQAAAA==.',
Ay='Ayesu:BAAANQAECgUIDAABNQAECgcIEAADAAAAAA==.',
Az='Azerith:BAAANQADCgYIDgAAAA==.',
Ba='Balahuk:BAAANQAECgMIBQABNQAFFAQICQAJAOoYAA==.',
Bl='Bloodfish:BAAANQAECggIEwAAAA==.',
Bo='Bomber:BAAANQADCgQIBAAAAA==.Bombs:BAAANQAECgYIBgABNQAFFAUIFAAKAEIfAA==.Bonesy:BAAANQAECgcIEQAAAA==.',
Bu='Burdomew:BAAANQAECgQIBgAAAA==.',
['Bà']='Bàwitdàbà:BAABNQAECn8eAAIKAAcKkhGyfgCMAQAKAAcKkhGyfgCMAQAAAA==.',
['Bö']='Börs:BAAANQADCgEIAQAAAA==.',
Ca='Cadbringer:BAAANQADCggJCAAAAA==.Cadbury:BAAANQAECgQICAAAAA==.Cananojii:BAAANQADCgQIBgAAAA==.Cantona:BAAANQAECgEIAQAAAA==.Casmina:BAAANQAECgYIBwAAAA==.',
Ce='Ceola:BAABNQAECn8cAAILAAgKkBV1FADcAQALAAgKkBV1FADcAQAAAA==.',
Ch='Chamichurri:BAAANQADCgQIBAAAAA==.Chamming:BAAANQAECgIIAgAAAA==.Chaw:BAACNQAFFH8SAAIGAAUKOB9BCADBAQAGAAUKOB9BCADBAQA1AAQKfycAAwYACQqsJLIXADoDAAYACQqsJLIXADoDAAwAAQryGyERAFgAAAAA.Chawdan:BAAANQADCgcIBwAAAA==.Chenkenichi:BAABNQAECn8iAAINAAgKawyzMQCFAQANAAgKawyzMQCFAQAAAA==.Chillout:BAAANQAECgcIDAAAAA==.',
Ci='Cinny:BAABNQAECn8vAAIGAAkKJxQfVQBwAgAGAAkKJxQfVQBwAgAAAA==.Cityairlines:BAABNQAECn8oAAIOAAgKThH/PQDOAQAOAAgKThH/PQDOAQAAAA==.',
Cm='Cmoneyy:BAAANQADCgYIBgAAAA==.',
Co='Cooldukenuke:BAABNQAECn8gAAIPAAgKUh3eKwC1AgAPAAgKUh3eKwC1AgAAAA==.',
Cr='Criticize:BAAANQAECgcIDgAAAA==.',
Cs='Csorpa:BAAANQAECgEIAQAAAA==.',
Cu='Cultist:BAAANQAECgcIDAAAAA==.Cupcakes:BAABNQAECn8qAAQQAAkKHh+nTQCoAgAQAAkKHh+nTQCoAgAHAAQKaRTSQQDqAAAPAAMKgBRP2wDDAAABNQAECgkJLwAIAKIjAA==.',
De='Deadbrum:BAAANQADCgYIBgABNQAECgkJMwAKAP8eAA==.Deagua:BAAANQADCggIDwABNQAFFAUIFAARAFIVAA==.Deardra:BAAANQAECgIIBAAAAA==.Dejavu:BAACNQAFFH8JAAIJAAQK6hjPBAA8AQAJAAQK6hjPBAA8AQA1AAQKfyoAAgkACQpkH1AGAOkCAAkACQpkH1AGAOkCAAAA.Desdemona:BAAANQAECgIIAwAAAA==.',
Di='Dispal:BAAANQAECgIIAgAAAA==.',
Do='Doodoopoopoo:BAAANQAECggIAQAAAA==.',
Dr='Dracz:BAAANQAECgYIBwAAAA==.Dropkick:BAAANQAECgEIAgAAAA==.',
Du='Duplexity:BAABNQAECn8sAAMLAAkKGiS3AQCtAwALAAkKGiS3AQCtAwASAAEKkxFhRwE7AAAAAA==.',
Dv='Dvxmatt:BAAANQAECgUIEwAAAA==.',
Dw='Dwalin:BAAANQAECgcIEQAAAA==.',
Eg='Egohakai:BAACNQAFFH8SAAIQAAUKTR+nCgCaAQAQAAUKTR+nCgCaAQA1AAQKfycAAhAACQpdH3xHALsCABAACQpdH3xHALsCAAAA.',
El='Elfy:BAAANQADCgUIBQAAAA==.',
Em='Emieretta:BAABNQAECn8iAAMOAAkKgBKfOwDbAQAOAAgKIxKfOwDbAQATAAYKxQvHgwAMAQAAAA==.',
Er='Errekt:BAAANQAECgEIAgAAAA==.Erret:BAACNQAFFH8LAAIUAAUKCAhhJABcAQAUAAUKCAhhJABcAQA1AAQKfzEAAhQACQrJGuh9AIICABQACQrJGuh9AIICAAAA.',
Et='Ethaka:BAAANQAFFAEIAQAAAA==.',
Fa='Faemos:BAAANQAECgYICwAAAA==.Faience:BAAANQAECgUIEQAAAA==.Falorina:BAABNQAECn8uAAIEAAkK0SSXAgDLAwAEAAkK0SSXAgDLAwAAAA==.Fathernature:BAABNQAECn8YAAICAAkK+RZUKwB8AgACAAkK+RZUKwB8AgAAAA==.',
Fe='Feldra:BAABNQAECn8lAAIFAAkKUB+WCgAwAwAFAAkKUB+WCgAwAwAAAA==.',
Fi='Finnin:BAABNQAECn8jAAMSAAgK+RzBUgCPAgASAAgK+RzBUgCPAgAVAAEKFCAqKwBWAAAAAA==.',
Fo='Food:BAABNQAECn8kAAIGAAgKOxEkdAAlAgAGAAgKOxEkdAAlAgAAAA==.',
Fr='Frozenfaith:BAABNQAECn8iAAIWAAgKBhSWXgABAgAWAAgKBhSWXgABAgAAAA==.',
Fu='Furba:BAABNQAECn8nAAIGAAkKEhlaMgDTAgAGAAkKEhlaMgDTAgAAAA==.Furiouswind:BAABNQAECn8oAAIXAAgKABqhDwBtAgAXAAgKABqhDwBtAgAAAA==.Furyvolt:BAAANQAECgYIEQAAAA==.',
Gh='Ghettomike:BAABNQAECn8hAAITAAgKBR8ZJQCpAgATAAgKBR8ZJQCpAgAAAA==.Ghold:BAABNQAECn8bAAQPAAkKlR3aHAD+AgAPAAkKlR3aHAD+AgAQAAMKzQfoXQGBAAAHAAEKAAAddgAlAAABNQAECgkJHgAWABUeAA==.',
Gi='Giranimo:BAAANQAECgYIDwAAAA==.',
Gl='Glabados:BAAANQAECgcIEwABNQAECgcIGAAJANAjAA==.Glossy:BAACNQAFFH8TAAMYAAUKmiSaBwCKAQAYAAQKgSOaBwCKAQAZAAEKziZTGQBwAAA1AAQKfyUAAxgACAqRJdcXABwCABgABgoxJNcXABwCABkABAq6JS1GAKcBAAAA.Glossyrage:BAAANQADCgcIBwAAAA==.',
Go='Gorkus:BAAANQADCgMIAwAAAA==.Gors:BAAANQAECgQIBQAAAA==.',
Gr='Gratiaplena:BAAANQABCgQIBwAAAA==.',
Ha='Halîk:BAABNQAECn8bAAIPAAgKhxAyaQDZAQAPAAgKhxAyaQDZAQAAAA==.Hardheaded:BAAANQAECgEIAQAAAA==.Hathina:BAACNQAFFH8JAAMVAAUK4xyqAQAPAQAVAAMK+R+qAQAPAQASAAIKWBv2KgCbAAA1AAQKfx8AAxUACQpbJIMDAB0DABUACArzJIMDAB0DABIAAQrLILM9AU8AAAAA.',
He='Hedetet:BAAANQABCgEIAQABNQAECggIGgAFAFMXAA==.Heket:BAAANQADCggIDwAAAA==.Herath:BAAANQABCggIDwAAAA==.',
Hi='Hill:BAABNQAECn8fAAIGAAgKLBMNYgBPAgAGAAgKLBMNYgBPAgAAAA==.Hive:BAABNQAECn8nAAISAAkKHA/7jQD1AQASAAkKHA/7jQD1AQAAAA==.',
Hu='Husentar:BAAANQADCgYICwAAAA==.',
Ic='Icaron:BAAANQADCggIAQAAAA==.',
Ig='Igni:BAAANQABCgMIBAAAAA==.',
Il='Illuminottey:BAAANQADCgEIAQAAAA==.',
Im='Impériavil:BAAANQAECgQIBgAAAA==.',
In='Inferium:BAAANQADCgcIBwAAAA==.Insatiabull:BAAANQAECggIEgABNQAECgkJLAABACwlAA==.',
Ir='Iriaena:BAAANQADCgYIDwAAAA==.',
Is='Ishaa:BAAANQAECggICAAAAA==.',
Ja='Jackstands:BAABNQAECn8xAAIKAAkK/yGJEAA/AwAKAAkK/yGJEAA/AwAAAA==.Jagerin:BAAANQAECgMIBAABNQAECgcIGAAJANAjAA==.January:BAABNQAECn8WAAIaAAgKoAcWNwBoAQAaAAgKoAcWNwBoAQAAAA==.Jarry:BAAANQAECgMIBQAAAA==.',
Je='Jeannine:BAAANQAECgMIBgAAAA==.',
Ju='Junn:BAABNQAECn8oAAIbAAgK1A2rbgDQAQAbAAgK1A2rbgDQAQAAAA==.',
['Já']='Jánuary:BAABNQAECn8ZAAQRAAkKigzndgD5AQARAAkK4QrndgD5AQAcAAUKeQpcFAABAQAdAAMKKw54SAClAAAAAA==.',
Ka='Kahayman:BAABNQAECn8hAAMUAAkKGg1XrQAmAgAUAAkKGg1XrQAmAgAeAAQKNAR2LQCOAAAAAA==.Kaimari:BAABNQAECn8aAAQfAAgKqA0TKABQAQAfAAUKVhgTKABQAQACAAgKywJgbwAIAQABAAMKrQLgOgBIAAAAAA==.Kazuya:BAAANQAECgEIAQAAAA==.',
Ke='Kennyboi:BAAANQADCgIIAgAAAA==.',
Kh='Khaibit:BAABNQAECn8zAAIOAAkKdCGICQBPAwAOAAkKdCGICQBPAwAAAA==.Khathani:BAAANQADCggIDwAAAA==.',
Ki='Kirara:BAAANQAECgUIBQAAAA==.Kissofdeath:BAABNQAECn8jAAIZAAgKIguOPADZAQAZAAgKIguOPADZAQAAAA==.',
Ko='Komojo:BAAANQAECgUICgAAAA==.Koriggan:BAABNQAECn8bAAIMAAgKpRclBQB1AgAMAAgKpRclBQB1AgAAAA==.',
Kr='Krea:BAABNQAECn8bAAIHAAgKmCTcBQBNAwAHAAgKmCTcBQBNAwAAAA==.Kroval:BAABNQAECn8XAAIZAAkKCgh9RACwAQAZAAkKCgh9RACwAQAAAA==.Krystagosa:BAABNQAECn8aAAQgAAgK4wmXLQAyAQAgAAcK4QWXLQAyAQAhAAYKlQ2xEAApAQAiAAMK7gSFMQCCAAAAAA==.',
Ku='Kuriuh:BAAANQAECgYJDwAAAA==.',
Ky='Kybo:BAAANQABCgMIAwABNQAFFAQICQACAE4aAA==.Kyo:BAAANQADCgUIBQAAAA==.',
La='Lang:BAABNQAECn8jAAIjAAgKfBhFCgA0AgAjAAgKfBhFCgA0AgAAAA==.',
Li='Lightdogg:BAAANQAECgcIEQAAAA==.Limaia:BAABNQAECn8fAAMkAAgKPg+TKwC8AQAkAAgKPg+TKwC8AQACAAMKPwNXnwBbAAAAAA==.Linia:BAAANQAECgEIAQAAAA==.',
Lo='Loopey:BAAANQAECgMIAwABNQAFFAQICQAJAOoYAA==.',
Lu='Luceriss:BAAANQAECggIEQAAAA==.Luckylite:BAAANQAECgIIAgAAAA==.Lulilaj:BAABNQAECn8pAAIeAAgKtRfEBwBsAgAeAAgKtRfEBwBsAgAAAA==.',
Ma='Maike:BAABNQAECn8ZAAIYAAcKwhf+GgD8AQAYAAcKwhf+GgD8AQAAAA==.Marothius:BAACNQAFFH8UAAMRAAUKUhWmFwA8AQARAAQKshqmFwA8AQAdAAEKkwrbHgBLAAA1AAQKfycAAx0ACQpeHH4fAHIBABEACApAG71gADMCAB0ABQoVGX4fAHIBAAAA.Marrius:BAAANQADCgYIBwAAAA==.Martaug:BAABNQAECn8iAAIKAAkKjCGlFgAaAwAKAAkKjCGlFgAaAwAAAA==.Marune:BAABNQAECn8iAAMgAAgKvhPNHQDwAQAgAAgKvhPNHQDwAQAiAAYKfRDvHgBhAQAAAA==.Maverage:BAAANQAECgcIEQAAAA==.Mayfair:BAAANQAECgEIAQAAAA==.',
Me='Melee:BAABNQAECn8lAAIQAAgKrxtoRgC+AgAQAAgKrxtoRgC+AgAAAA==.Metal:BAAANQADCgcIEwAAAA==.',
Mi='Minibolt:BAAANQADCgEIAQAAAA==.Minimee:BAAANQAECgEIAQAAAA==.Miquella:BAABNQAECn8VAAIEAAYK2hsGOgDfAQAEAAYK2hsGOgDfAQAAAA==.',
Mo='Mollymauk:BAAANQADCgQIBAABNQAECgkJHgAWABUeAA==.Monkstrosity:BAAANQAECgYIEAAAAA==.Mookks:BAAANQADCgUIBQAAAA==.Moonn:BAAANQAECgcIDwAAAA==.Moor:BAAANQAECgQICQAAAA==.Mordakka:BAAANQAECgcIEwAAAA==.Morior:BAABNQAECn8sAAMRAAkKCBOGegDwAQARAAgKuRGGegDwAQAdAAEK3RouaQBOAAAAAA==.',
Mu='Mulletmaster:BAAANQAECgUJCQAAAA==.Murrda:BAABNQAECn8vAAMRAAkKwxaGTQBoAgARAAgKbReGTQBoAgAdAAEKxxICcwA7AAAAAA==.',
My='Myrokos:BAABNQAECn81AAIQAAkKox8QMwD9AgAQAAkKox8QMwD9AgAAAA==.',
['Mö']='Möokss:BAAANQAECgYIEwAAAA==.',
Na='Nailo:BAAANQADCggICAAAAA==.Nasperus:BAAANQABCgIIAgAAAA==.',
Ni='Niddles:BAAANQAECgcICAAAAA==.Niddy:BAABNQAECn8tAAMeAAkKxh4SAwAeAwAeAAkKxh4SAwAeAwAUAAMK+ghTkwGZAAAAAA==.',
No='Nobudee:BAAANQADCgcIBwABNQAFFAUIEAAbAJcdAA==.Nocandles:BAABNQAECn8gAAIaAAgKUh7eEgDRAgAaAAgKUh7eEgDRAgAAAA==.Noebuddie:BAACNQAFFH8QAAIbAAUKlx1FCwCyAQAbAAUKlx1FCwCyAQA1AAQKfyYAAhsACQrfIiwcAB8DABsACQrfIiwcAB8DAAAA.Noel:BAAANQAECgQICQAAAA==.Nonospot:BAAANQAECgcIEwAAAA==.Noraboo:BAAANQAECgcIEAAAAA==.Norganon:BAAANQAECgQIBAAAAA==.',
Nv='Nvied:BAABNQAECn8cAAMRAAgKFhdShgDSAQARAAcK7BZShgDSAQAdAAIKuxC1VwB3AAAAAA==.',
Ny='Nyctt:BAABNQAECn8tAAIYAAkKahs0CgDQAgAYAAkKahs0CgDQAgAAAA==.Nyzstra:BAABNQAECn8lAAIUAAkK9B+7OQAUAwAUAAkK9B+7OQAUAwAAAA==.',
['Nê']='Nêwt:BAACNQAFFH8FAAIUAAIK0wfZTQCGAAAUAAIK0wfZTQCGAAA1AAQKfykAAhQACQpCEb2lADUCABQACQpCEb2lADUCAAAA.',
On='Onlybeams:BAABNQAECn8aAAIFAAgKUxfuHgBVAgAFAAgKUxfuHgBVAgAAAA==.',
Or='Orcs:BAAANQADCgUIBQAAAA==.Oreo:BAAANQADCgcIEQAAAA==.Orphu:BAAANQADCgQIBwAAAA==.',
Pa='Palmiste:BAAANQAECgQIBAAAAA==.Pandoora:BAAANQADCgYIEAAAAA==.Pangoplexity:BAAANQABCgMJAwAAAA==.Papichulo:BAAANQADCgQIBAAAAA==.Parahsalin:BAAANQAECgYIEgAAAA==.Pastryblust:BAACNQAFFH8RAAMbAAUKixO6DgB+AQAbAAUKahO6DgB+AQAXAAEKzg7EBwBUAAA1AAQKfzEAAxsACQocIQEXADwDABsACQoVIQEXADwDABcACAoaGbEQAFwCAAAA.',
Pe='Pennyzillin:BAAANQADCggICAABNQAECgYIEgADAAAAAA==.Pewpewmon:BAAANQADCgcIBwABNQAECgkJLAALABokAA==.',
Pi='Pistachio:BAAANQADCggIHgAAAA==.Pitviper:BAABNQAECn8oAAIZAAgKBhYYKQBFAgAZAAgKBhYYKQBFAgAAAA==.',
Po='Pogaca:BAAANQADCggIEwAAAA==.Portabull:BAAANQADCgcIBwABNQAECgkJLAABACwlAA==.',
Pr='Precogvendor:BAAANQAECgMIBQAAAA==.',
Ra='Raddelwingus:BAAANQADCgMIAwABNQAECgkJLAALABokAA==.Rai:BAABNQAECn8jAAIGAAgKuSL6GwAmAwAGAAgKuSL6GwAmAwAAAA==.Ramens:BAAANQAECgIIAgAAAA==.Rapha:BAABNQAECn8YAAIJAAcK0CMtCACrAgAJAAcK0CMtCACrAgAAAA==.Rayyzor:BAABNQAECn8lAAIFAAgKsyJRDQAOAwAFAAgKsyJRDQAOAwAAAA==.',
Re='Reality:BAAANQADCgQICAAAAA==.Realtree:BAAANQADCgQIBwAAAA==.',
Ri='Riddles:BAAANQAECgcIEQAAAA==.',
Ro='Rot:BAABNQAECn8oAAIIAAgKuyRgDABOAwAIAAgKuyRgDABOAwAAAA==.',
Ru='Rusty:BAAANQADCgUIBQAAAA==.',
Sa='Santino:BAAANQADCgcICAABNQAECgkJIQAUABoNAA==.Sapherapal:BAAANQADCgMIAwAAAA==.Saphlocket:BAAANQAECgIIBwAAAA==.Saphmage:BAAANQAECgMIBwAAAA==.Sathin:BAABNQAECn8jAAIFAAgKGAf7NQCOAQAFAAgKGAf7NQCOAQAAAA==.',
Sc='Scher:BAAANQAECgMIAwAAAA==.Scufalufagus:BAAANQADCgUIBQABNQAFFAUIFAARAFIVAA==.',
Se='September:BAAANQADCgYJBgABNQAECggJFgAaAKAHAA==.Seqsy:BAAANQAECgQIBQAAAA==.',
Sf='Sfcwarner:BAAANQADCgYIDQAAAA==.',
Sg='Sgtwarner:BAAANQAECgQIBAAAAA==.',
Sh='Shampooyou:BAABNQAECn8cAAIKAAgKaw1BeQCcAQAKAAgKaw1BeQCcAQAAAA==.Shockakhan:BAAANQADCgQIBAAAAA==.',
Si='Silentkit:BAABNQAECn8bAAMOAAcK0hKsRgCeAQAOAAcK0hKsRgCeAQATAAMKowoMrgCTAAAAAA==.',
St='Stardel:BAAANQAECgcIDwABNQAFFAYIDQAYAJgjAA==.Stormclaw:BAABNQAECn8uAAMkAAkKNxi6HgA0AgAkAAgKaBa6HgA0AgACAAUK8hBfYgBBAQAAAA==.Stregglebus:BAAANQAECgYIDgABNQAFFAUIFAARAFIVAA==.Stregoica:BAAANQADCggICAABNQAFFAUIFAARAFIVAA==.Stroggosh:BAAANQADCggIEgABNQAFFAUIFAARAFIVAA==.',
Su='Suhfering:BAAANQAECgcIDgABNQAECggIGgAFAFMXAA==.Sunshot:BAAANQAECgEIAQAAAA==.Surrs:BAAANQAECgIIAgABNQAECggJFgAaAKAHAA==.',
Ta='Takrusani:BAAANQADCgIIAgAAAA==.Tallron:BAACNQAFFH8UAAIkAAUKdxI3BwCFAQAkAAUKdxI3BwCFAQA1AAQKfycAAiQACQrcHJsRAMICACQACQrcHJsRAMICAAAA.Tamedsloth:BAAANQAECgMIBAAAAA==.Tanerella:BAAANQAECgIIAwAAAA==.',
Th='Thrustruggle:BAABNQAECn8aAAIlAAgKDRRQKAAFAgAlAAgKDRRQKAAFAgAAAA==.',
Ti='Timir:BAACNQAFFH8RAAIQAAUKsRULDQB1AQAQAAUKsRULDQB1AQA1AAQKfycAAhAACQo3GphvAE0CABAACQo3GphvAE0CAAAA.Tinynutz:BAAANQADCgYICQAAAA==.',
To='Tojikitoushi:BAABNQAECn8xAAIXAAkKyhUsDwB1AgAXAAkKyhUsDwB1AgAAAA==.Tombs:BAAANQAECgEIAQABNQAECgkJHgAWABUeAA==.Totenhammer:BAAANQADCgYIBwAAAA==.Touche:BAABNQAECn8aAAIUAAgKPhK2yADyAQAUAAgKPhK2yADyAQAAAA==.',
Tr='Tribulate:BAAANQADCggIDAAAAA==.Trollyroller:BAAANQADCggIFAAAAA==.',
Tw='Twistedfrost:BAAANQADCgUIBQAAAA==.',
Ul='Ulrein:BAAANQAECgIIAwAAAA==.',
Ve='Vextt:BAABNQAECn8eAAMWAAkKFR7lIQDlAgAWAAgKtSDlIQDlAgAaAAgKWh3TGwBkAgAAAA==.Veylira:BAABNQAECn8WAAMRAAYK2xw1igDIAQARAAYK3xg1igDIAQAdAAIKGBQbVQB+AAABNQAECgkJMwASAOsdAA==.',
Vi='Vitner:BAABNQAECn8YAAIRAAkKrReGVQBSAgARAAkKrReGVQBSAgAAAA==.',
Vo='Voidra:BAAANQAECgEIAwAAAA==.Voidwarner:BAAANQADCggICAAAAA==.Volight:BAAANQAECgQIBgAAAA==.Volke:BAABNQAECn8oAAImAAgKqRNSGQDlAQAmAAgKqRNSGQDlAQAAAA==.Voltarix:BAAANQADCgEIAQAAAA==.Voyria:BAABNQAECn8jAAMkAAgK1wqWMgCBAQAkAAgK1wqWMgCBAQACAAIKuAG5swAtAAAAAA==.',
Vy='Vyskar:BAAANQADCgQIAwAAAA==.',
['Vê']='Vênm:BAAANQAECgMIBAABNQAFFAQICQAJAOoYAA==.',
Wa='Warm:BAAANQAECgQICAAAAA==.',
We='Weeziveli:BAAANQADCgYIBgAAAA==.Weledish:BAACNQAFFH8PAAMUAAUKYBJaJABcAQAUAAQKhhRaJABcAQAeAAEKFA49EwBHAAA1AAQKfy4AAxQACQoDH0IzACQDABQACQr1HkIzACQDAB4AAgpgG34pAKgAAAAA.Weleron:BAAANQADCgIIAgAAAA==.',
Wi='Widdles:BAAANQAECgMIAwAAAA==.',
Yi='Yinyangfaith:BAAANQADCgEIAQABNQAECggIIgAWAAYUAA==.',
Ze='Zerea:BAAANQABCgEIAQAAAA==.',
Zo='Zomgdk:BAABNQAECn81AAIIAAkKlCKfBwCBAwAIAAkKlCKfBwCBAwAAAA==.',
Zy='Zynthia:BAAANQADCgQIBAAAAA==.',
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
