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

local lookup = {'Druid-Feral','Druid-Balance','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','DeathKnight-Blood','Monk-Brewmaster','Shaman-Restoration','Warrior-Protection','Hunter-Survival','Monk-Windwalker','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Paladin-Protection','DeathKnight-Unholy','Warlock-Demonology','Mage-Arcane','Warrior-Arms','Warrior-Fury','Priest-Holy','Shaman-Enhancement','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Shaman-Elemental','Mage-Frost','Druid-Guardian','DemonHunter-Vengeance','Warlock-Destruction','Evoker-Preservation','Druid-Restoration','Monk-Mistweaver',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Adorabull:BAABNQAECoEjAAMBAAkKeiLlBAARAwABAAgKziPlBAARAwACAAYKdxp/UwBhAQAAAA==.',
Ae='Aemun:BAAANQADCggIEgAAAA==.',
Ag='Aggfu:BAAANQADCgcIBwABNQAECgcIDQADAAAAAA==.',
Ak='Akelita:BAABNQAECoEUAAMEAAcKDxcdNwDDAQAEAAcKDxcdNwDDAQAFAAIKCQaaWABZAAAAAA==.',
Al='Alailea:BAABNQAECoEdAAIGAAgK5RGVYgAmAgAGAAgK5RGVYgAmAgAAAA==.Aloepaw:BAAANQAECgIIAgAAAA==.Alwysafkable:BAAANQAECgYIDQAAAA==.',
An='Anastasía:BAABNQAECoEbAAIHAAcKKxOOTgCaAQAHAAcKKxOOTgCaAQAAAA==.Anzul:BAAANQADCgYICgAAAA==.',
As='Asure:BAAANQAECgYIEQAAAA==.',
Ay='Ayesu:BAAANQAECgUIDAAAAA==.',
Az='Azerith:BAAANQADCgYIDgAAAA==.',
Ba='Balahuk:BAAANQAECgMIAwABNQAFFAMIBQAIANoUAA==.',
Bl='Bloodfish:BAAANQAECgcIEgAAAA==.',
Bo='Bomber:BAAANQADCgQIBAAAAA==.Bombs:BAAANQAECgYIBgABNQAFFAUIDwAJAOYeAA==.Bonesy:BAAANQAECgUICgAAAA==.',
Bu='Burdomew:BAAANQAECgMIAwAAAA==.',
['Bà']='Bàwitdàbà:BAABNQAECoEYAAIJAAcKORGObgCRAQAJAAcKORGObgCRAQAAAA==.',
['Bö']='Börs:BAAANQADCgEIAQAAAA==.',
Ca='Cadbringer:BAAANQADCggJCAAAAA==.Cadbury:BAAANQAECgQICAAAAA==.Cananojii:BAAANQADCgQIBgAAAA==.Cantona:BAAANQAECgEIAQAAAA==.Casmina:BAAANQAECgYIBwAAAA==.',
Ce='Ceola:BAABNQAECoEaAAIKAAgKYBTqEQDZAQAKAAgKYBTqEQDZAQAAAA==.',
Ch='Chamichurri:BAAANQADCgQIBAAAAA==.Chamming:BAAANQAECgIIAgAAAA==.Chaw:BAACNQAFFIENAAIGAAUKdx0oBgDGAQAGAAUKdx0oBgDGAQA1AAQKgSQAAwYACQoqJC8SAEIDAAYACQoqJC8SAEIDAAsAAQryG3gPAFgAAAAA.Chawdan:BAAANQADCgcIBwAAAA==.Chenkenichi:BAABNQAECoEcAAIMAAgK0QqMKwCMAQAMAAgK0QqMKwCMAQAAAA==.Chillout:BAAANQAECgUICQAAAA==.',
Ci='Cinny:BAABNQAECoEpAAIGAAkKWxPESgBmAgAGAAkKWxPESgBmAgAAAA==.Cityairlines:BAABNQAECoEhAAINAAgKYhCrNgC+AQANAAgKYhCrNgC+AQAAAA==.',
Cm='Cmoneyy:BAAANQADCgYIBgAAAA==.',
Co='Cooldukenuke:BAABNQAECoEgAAIOAAgKUh1qJADBAgAOAAgKUh1qJADBAgAAAA==.',
Cr='Criticize:BAAANQAECgUICQAAAA==.',
Cs='Csorpa:BAAANQAECgEIAQAAAA==.',
Cu='Cultist:BAAANQAECgcIDAAAAA==.Cupcakes:BAABNQAECoEmAAQPAAgK1h4AYABOAgAPAAgKmR4AYABOAgAQAAQKwhcPOwDsAAAOAAMKgBTLxADJAAABNQAECggIJgARANAkAA==.',
De='Deadbrum:BAAANQADCgYIBgABNQAECgkJKwAJAEIdAA==.Deagua:BAAANQADCggIDwABNQAFFAUIDwASAEIRAA==.Deardra:BAAANQAECgIIBAAAAA==.Dejavu:BAACNQAFFIEFAAIIAAMK2hR1BQDiAAAIAAMK2hR1BQDiAAA1AAQKgScAAggACQq9HlQFAPUCAAgACQq9HlQFAPUCAAAA.Desdemona:BAAANQAECgEIAQAAAA==.',
Di='Dispal:BAAANQAECgIIAgAAAA==.',
Do='Doodoopoopoo:BAAANQAECggIAQAAAA==.',
Dr='Dracz:BAAANQAECgYIBwAAAA==.Dropkick:BAAANQAECgEIAQAAAA==.',
Du='Duplexity:BAABNQAECoEnAAIKAAgKqCReAwBRAwAKAAgKqCReAwBRAwAAAA==.',
Dv='Dvxmatt:BAAANQAECgUIDgAAAA==.',
Dw='Dwalin:BAAANQAECgcIEQAAAA==.',
Eg='Egohakai:BAACNQAFFIEOAAIPAAUKWhdVBwCwAQAPAAUKWhdVBwCwAQA1AAQKgSQAAg8ACQrOHs43AM4CAA8ACQrOHs43AM4CAAAA.',
El='Elfy:BAAANQADCgUIBQAAAA==.',
Em='Emieretta:BAABNQAECoEeAAMNAAkKnQ+xNADMAQANAAgKug+xNADMAQARAAYKbAvdeAAOAQAAAA==.',
Er='Errekt:BAAANQAECgEIAgAAAA==.Erret:BAACNQAFFIEIAAITAAUKAAd+HABlAQATAAUKAAd+HABlAQA1AAQKgSgAAhMACQqSGSpzAIECABMACQqSGSpzAIECAAAA.',
Et='Ethaka:BAAANQAECgcIEAAAAA==.',
Fa='Faemos:BAAANQAECgYICwAAAA==.Faience:BAAANQAECgUIDAAAAA==.Falorina:BAABNQAECoEmAAIEAAkKziRDAgDKAwAEAAkKziRDAgDKAwAAAA==.Fathernature:BAAANQAECggIEwAAAA==.',
Fe='Feldra:BAABNQAECoEiAAIFAAgKASE2DwDqAgAFAAgKASE2DwDqAgAAAA==.',
Fi='Finnin:BAABNQAECoEcAAMUAAgKJR26SgCPAgAUAAgKJR26SgCPAgAVAAEKFCA/JgBZAAAAAA==.',
Fo='Food:BAABNQAECoEdAAIGAAgKsxGRYAArAgAGAAgKsxGRYAArAgAAAA==.',
Fr='Frozenfaith:BAABNQAECoEcAAIWAAgKJw9fZQC8AQAWAAgKJw9fZQC8AQAAAA==.',
Fu='Furba:BAABNQAECoEjAAIGAAgKNBluQwB8AgAGAAgKNBluQwB8AgAAAA==.Furiouswind:BAABNQAECoEhAAIXAAgKWxXZDwBRAgAXAAgKWxXZDwBRAgAAAA==.Furyvolt:BAAANQAECgUICwAAAA==.',
Gh='Ghettomike:BAABNQAECoEhAAIRAAgKXiDZHgC0AgARAAgKXiDZHgC0AgAAAA==.Ghold:BAABNQAECoEYAAQOAAgKMxucLACZAgAOAAgKMxucLACZAgAPAAMKzQcdOAGDAAAQAAEKOA4uagAlAAABNQAECgkJHAAWAGEcAA==.',
Gi='Giranimo:BAAANQAECgYIDwAAAA==.',
Gl='Glabados:BAAANQAECgcIDAABNQAECgcIGAAIAIQjAA==.Glossy:BAACNQAFFIEOAAMYAAUKhSJsBgCZAQAYAAQKcyFsBgCZAQAZAAEKziYIFABzAAA1AAQKgSIAAxgACAq3JSwVACoCABgABgqeJCwVACoCABkABAq6Jew5AKsBAAAA.Glossyrage:BAAANQADCgcIBwAAAA==.',
Go='Gorkus:BAAANQADCgMIAwAAAA==.Gors:BAAANQAECgQIBQAAAA==.',
Gr='Gratiaplena:BAAANQABCgQIBwAAAA==.',
Ha='Halîk:BAABNQAECoEaAAIOAAgKhxBRWwDkAQAOAAgKhxBRWwDkAQAAAA==.Hardheaded:BAAANQAECgEIAQAAAA==.Hathina:BAACNQAFFIEIAAMVAAUKvR0oAQAdAQAVAAMKVR8oAQAdAQAUAAIKWBu4IwCgAAA1AAQKgRwAAxUACQqNI8QCACQDABUACArlI8QCACQDABQAAQrLIOUjAVIAAAAA.',
He='Hedetet:BAAANQABCgEIAQABNQAECggIGgAFADEaAA==.Heket:BAAANQADCggIDwAAAA==.Herath:BAAANQABCggIDwAAAA==.',
Hi='Hill:BAABNQAECoEYAAIGAAgKYhZhUgBRAgAGAAgKYhZhUgBRAgAAAA==.Hive:BAABNQAECoEnAAIUAAkKXg7DeAAKAgAUAAkKXg7DeAAKAgAAAA==.',
Hu='Husentar:BAAANQADCgYICwAAAA==.',
Ic='Icaron:BAAANQADCggIAQAAAA==.',
Ig='Igni:BAAANQABCgMIBAAAAA==.',
Il='Illuminottey:BAAANQADCgEIAQAAAA==.',
Im='Impériavil:BAAANQAECgQIBgAAAA==.',
In='Inferium:BAAANQADCgcIBwAAAA==.Insatiabull:BAAANQAECggIDwABNQAECgkJIwABAHoiAA==.',
Ir='Iriaena:BAAANQADCgYIDwAAAA==.',
Is='Ishaa:BAAANQADCgEIAQAAAA==.',
Ja='Jackstands:BAABNQAECoEuAAIJAAkK/yGBDABIAwAJAAkK/yGBDABIAwAAAA==.Jagerin:BAAANQAECgEIAQABNQAECgcIGAAIAIQjAA==.January:BAABNQAECoEWAAIaAAgKMgjYMABzAQAaAAgKMgjYMABzAQAAAA==.Jarry:BAAANQAECgMIBQAAAA==.',
Je='Jeannine:BAAANQADCggIDgAAAA==.',
Ju='Junn:BAABNQAECoEhAAIbAAgKmw1VYwDGAQAbAAgKmw1VYwDGAQAAAA==.',
['Já']='Jánuary:BAAANQAECgcIEwAAAA==.',
Ka='Kahayman:BAABNQAECoEhAAMTAAkKRw9elgA2AgATAAkKRw9elgA2AgAcAAQKagTzJwCQAAAAAA==.Kaimari:BAABNQAECoEaAAQdAAgKNBAOHwBfAQAdAAUKJBgOHwBfAQACAAgKiAJtZQAMAQABAAMKrQJ8MABNAAAAAA==.Kazuya:BAAANQAECgEIAQAAAA==.',
Ke='Kennyboi:BAAANQADCgIIAgAAAA==.',
Kh='Khaibit:BAABNQAECoEuAAINAAkKeCGZCABLAwANAAkKeCGZCABLAwAAAA==.Khathani:BAAANQADCggIDwAAAA==.',
Ki='Kissofdeath:BAABNQAECoEbAAIZAAcKCgtiPgCSAQAZAAcKCgtiPgCSAQAAAA==.',
Ko='Komojo:BAAANQAECgQIBQAAAA==.Koriggan:BAAANQAECgcIEAAAAA==.',
Kr='Krea:BAAANQAECgcIEAAAAA==.Kroval:BAAANQAECgYIEAAAAA==.Krystagosa:BAAANQAECgYIEAAAAA==.',
Ku='Kuriuh:BAAANQAECgYJDwAAAA==.',
Ky='Kybo:BAAANQABCgMIAwABNQAFFAIIBQACAKgSAA==.Kyo:BAAANQADCgUIBQAAAA==.',
La='Lang:BAABNQAECoEbAAIeAAcKdRjmCgD3AQAeAAcKdRjmCgD3AQAAAA==.',
Li='Lightdogg:BAAANQAECgcIEQAAAA==.Limaia:BAAANQAECgYIEgAAAA==.Linia:BAAANQAECgEIAQAAAA==.',
Lo='Loopey:BAAANQAECgMIAwABNQAFFAMIBQAIANoUAA==.',
Lu='Luceriss:BAAANQAECggIEQAAAA==.Luckylite:BAAANQAECgIIAgAAAA==.Lulilaj:BAABNQAECoEiAAIcAAgKcBfHBgBiAgAcAAgKcBfHBgBiAgAAAA==.',
Ma='Maike:BAAANQAECgYIEgAAAA==.Marothius:BAACNQAFFIEPAAMSAAUKQhFKEgA7AQASAAQKghNKEgA7AQAfAAEKPwicHABLAAA1AAQKgSQAAx8ACQp8HdIdAHcBABIACArzG2ZSAD0CAB8ABQqwGtIdAHcBAAAA.Marrius:BAAANQADCgYIBwAAAA==.Martaug:BAABNQAECoEgAAIJAAgKpCF4IADJAgAJAAgKpCF4IADJAgAAAA==.Marune:BAABNQAECoEbAAIgAAgKvhMbGwD4AQAgAAgKvhMbGwD4AQAAAA==.Maverage:BAAANQAECgYICgAAAA==.Mayfair:BAAANQAECgEIAQAAAA==.',
Me='Melee:BAABNQAECoElAAIPAAgKGB1rPQC4AgAPAAgKGB1rPQC4AgAAAA==.Metal:BAAANQADCgcIEwAAAA==.',
Mi='Minimee:BAAANQAECgEIAQAAAA==.Miquella:BAAANQAECgQIEAAAAA==.',
Mo='Mollymauk:BAAANQADCgQIBAABNQAECgkJHAAWAGEcAA==.Monkstrosity:BAAANQAECgYIEAAAAA==.Mookks:BAAANQADCgUIBQAAAA==.Moonn:BAAANQAECgcIDwAAAA==.Moor:BAAANQAECgQICQAAAA==.Mordakka:BAAANQAECgcIEwAAAA==.Morior:BAABNQAECoEqAAMSAAkKMBNpaQD6AQASAAgKOhJpaQD6AQAfAAEK3RrkYwBQAAAAAA==.',
Mu='Mulletmaster:BAAANQAECgUJCQAAAA==.Murrda:BAABNQAECoElAAMSAAkK+BPZbQDtAQASAAgKHhTZbQDtAQAfAAEKxxIDbQA9AAAAAA==.',
My='Myrokos:BAABNQAECoEvAAIPAAkK/R76KAAHAwAPAAkK/R76KAAHAwAAAA==.',
['Mö']='Möokss:BAAANQAECgYIEwAAAA==.',
Na='Nailo:BAAANQADCggICAAAAA==.Nasperus:BAAANQABCgIIAgAAAA==.',
Ni='Niddles:BAAANQAECgYIBgAAAA==.Niddy:BAABNQAECoEkAAMcAAgKOh78BACnAgAcAAgKOh78BACnAgATAAMKAwlcfQGRAAAAAA==.',
No='Nobudee:BAAANQADCgcIBwABNQAFFAUIDAAbAFUWAA==.Nocandles:BAAANQAECgYIEwAAAA==.Noebuddie:BAACNQAFFIEMAAIbAAUKVRaWCQCjAQAbAAUKVRaWCQCjAQA1AAQKgSMAAhsACQrDH0cYACEDABsACQrDH0cYACEDAAAA.Noel:BAAANQAECgQICQAAAA==.Nonospot:BAAANQAECgUIDAAAAA==.Noraboo:BAAANQAECgUICQABNQAECgUIDAADAAAAAA==.Norganon:BAAANQAECgQIAgAAAA==.',
Nv='Nvied:BAABNQAECoEaAAMSAAgKehVicADmAQASAAcKIhVicADmAQAfAAIKuxC6UwB5AAAAAA==.',
Ny='Nyctt:BAABNQAECoEpAAIYAAkK/hUzDQCTAgAYAAkK/hUzDQCTAgAAAA==.Nyzstra:BAABNQAECoEiAAITAAkK5B8nLwAjAwATAAkK5B8nLwAjAwAAAA==.',
['Nê']='Nêwt:BAABNQAECoEoAAITAAkKtBFrjgBHAgATAAkKtBFrjgBHAgAAAA==.',
On='Onlybeams:BAABNQAECoEaAAIFAAgKMRrdGAB7AgAFAAgKMRrdGAB7AgAAAA==.',
Or='Orcs:BAAANQADCgUIBQAAAA==.Oreo:BAAANQADCgcIEQAAAA==.Orphu:BAAANQADCgQIBwAAAA==.',
Pa='Palmiste:BAAANQAECgQIBAAAAA==.Pandoora:BAAANQADCgYIEAAAAA==.Pangoplexity:BAAANQABCgMJAwAAAA==.Papichulo:BAAANQADCgQIBAAAAA==.Parahsalin:BAAANQAECgYIEAAAAA==.Pastryblust:BAACNQAFFIEMAAMbAAQKshCYFQDqAAAbAAMKUxGYFQDqAAAXAAEKzg4sBgBZAAA1AAQKgS4AAxsACQq8If0RAEwDABsACQq3If0RAEwDABcABQpsFkUbAHoBAAAA.',
Pe='Pennyzillin:BAAANQADCgcIBwABNQAECgYIEAADAAAAAA==.Pewpewmon:BAAANQADCgcIBwABNQAECggIJwAKAKgkAA==.',
Pi='Pistachio:BAAANQADCggIGQAAAA==.Pitviper:BAABNQAECoEhAAIZAAgKlxYcIgBIAgAZAAgKlxYcIgBIAgAAAA==.',
Po='Pogaca:BAAANQADCggIEwAAAA==.Portabull:BAAANQADCgcIBwABNQAECgkJIwABAHoiAA==.',
Pr='Precogvendor:BAAANQAECgIIBAAAAA==.',
Ra='Raddelwingus:BAAANQADCgMIAwABNQAECggIJwAKAKgkAA==.Rai:BAABNQAECoEbAAIGAAcKxyBjPQCOAgAGAAcKxyBjPQCOAgAAAA==.Ramens:BAAANQAECgIIAgAAAA==.Rapha:BAABNQAECoEYAAIIAAcKhCPqBgC2AgAIAAcKhCPqBgC2AgAAAA==.Rayyzor:BAABNQAECoEeAAIFAAgKhSKTCwAXAwAFAAgKhSKTCwAXAwAAAA==.',
Re='Reality:BAAANQADCgQICAAAAA==.Realtree:BAAANQADCgQIBwAAAA==.',
Ri='Riddles:BAAANQAECgcIEQAAAA==.',
Ro='Rot:BAABNQAECoEhAAIHAAgKNyPtDwAbAwAHAAgKNyPtDwAbAwAAAA==.',
Sa='Santino:BAAANQADCgcICAABNQAECgkJIQATAEcPAA==.Sapherapal:BAAANQADCgMIAwAAAA==.Saphlocket:BAAANQAECgIIBwAAAA==.Saphmage:BAAANQAECgIIBQAAAA==.Sathin:BAABNQAECoEbAAIFAAcKUAazOABXAQAFAAcKUAazOABXAQAAAA==.',
Sc='Scher:BAAANQAECgMIAwAAAA==.Scufalufagus:BAAANQADCgUIBQABNQAFFAUIDwASAEIRAA==.',
Se='September:BAAANQADCgYJBgABNQAECggJFgAaADIIAA==.Seqsy:BAAANQAECgQIBQAAAA==.',
Sf='Sfcwarner:BAAANQADCgYJDQAAAA==.',
Sg='Sgtwarner:BAAANQADCgcICwAAAA==.',
Sh='Shampooyou:BAAANQAECgcIEAAAAA==.Shockakhan:BAAANQADCgQIBAAAAA==.',
Si='Silentkit:BAABNQAECoEbAAMNAAcK7BNLOQCuAQANAAcKnRNLOQCuAQARAAMKVA6coACUAAAAAA==.',
St='Stardel:BAAANQAECgcIDwABNQAFFAUICgAYAFoeAA==.Stormclaw:BAABNQAECoElAAMhAAgKixhIIQDxAQAhAAcKhhZIIQDxAQACAAMKcxTxcgDUAAAAAA==.Stregglebus:BAAANQAECgYIDgABNQAFFAUIDwASAEIRAA==.Stregoica:BAAANQADCggICAABNQAFFAUIDwASAEIRAA==.Stroggosh:BAAANQADCggIEgABNQAFFAUIDwASAEIRAA==.',
Su='Suhfering:BAAANQAECgcIBwABNQAECggIGgAFADEaAA==.Sunshot:BAAANQAECgEIAQAAAA==.',
Ta='Takrusani:BAAANQADCgIIAgAAAA==.Tallron:BAACNQAFFIEPAAIhAAUKrBDSBQCOAQAhAAUKrBDSBQCOAQA1AAQKgSQAAiEACQrcHM8OAMoCACEACQrcHM8OAMoCAAAA.Tamedsloth:BAAANQAECgMIBAAAAA==.Tanerella:BAAANQAECgEIAQAAAA==.',
Th='Thrustruggle:BAAANQAECgcIEwAAAA==.',
Ti='Timir:BAACNQAFFIEOAAIPAAUKsxBPCQCIAQAPAAUKsxBPCQCIAQA1AAQKgSQAAg8ACQrQGlFcAFkCAA8ACQrQGlFcAFkCAAAA.Tinynutz:BAAANQADCgYICQAAAA==.',
To='Tojikitoushi:BAABNQAECoEuAAIXAAkKsxWACwCiAgAXAAkKsxWACwCiAgAAAA==.Tombs:BAAANQAECgEIAQABNQAECgkJHAAWAGEcAA==.Totenhammer:BAAANQADCgYIBwAAAA==.Touche:BAABNQAECoEaAAITAAgKBRDQsAD/AQATAAgKBRDQsAD/AQAAAA==.',
Tr='Tribulate:BAAANQADCggIDAAAAA==.Trollyroller:BAAANQADCggIFAAAAA==.',
Tw='Twistedfrost:BAAANQADCgUIBQAAAA==.',
Ul='Ulrein:BAAANQAECgIIAwAAAA==.',
Ve='Vextt:BAABNQAECoEcAAMWAAkKYRweIADUAgAWAAgKyx4eIADUAgAaAAgKixyuFwB1AgAAAA==.Veylira:BAABNQAECoEWAAMSAAYKmB13dADaAQASAAYKRhp3dADaAQAfAAIKGBQgUQCAAAABNQAECgkJLQAUAJccAA==.',
Vi='Vitner:BAABNQAECoEXAAISAAkKpBZpQwBrAgASAAkKpBZpQwBrAgAAAA==.',
Vo='Voidra:BAAANQAECgEIAwAAAA==.Voidwarner:BAAANQADCggICAAAAA==.Volight:BAAANQAECgQIBgAAAA==.Volke:BAABNQAECoEhAAIiAAgKzxBWGgCuAQAiAAgKzxBWGgCuAQAAAA==.Voltarix:BAAANQADCgEIAQAAAA==.Voyria:BAABNQAECoEbAAMhAAcKSQgiOgAYAQAhAAcKSQgiOgAYAQACAAIKbgE5pAAtAAAAAA==.',
Vy='Vyskar:BAAANQADCgQIAwAAAA==.',
['Vê']='Vênm:BAAANQAECgIIAgABNQAFFAMIBQAIANoUAA==.',
Wa='Warm:BAAANQAECgQICAAAAA==.',
We='Weeziveli:BAAANQADCgYIBgAAAA==.Weledish:BAACNQAFFIEOAAMTAAUKAhY6HgBUAQATAAQK/hc6HgBUAQAcAAEKFA6LDwBIAAA1AAQKgSkAAxMACQrqHsw2AA4DABMACQrqHsw2AA4DABwAAgpuDrUuAGcAAAAA.Weleron:BAAANQADCgIIAgAAAA==.',
Wi='Widdles:BAAANQAECgMIAwAAAA==.',
Yi='Yinyangfaith:BAAANQADCgEIAQABNQAECggIHAAWACcPAA==.',
Ze='Zerea:BAAANQABCgEIAQAAAA==.',
Zo='Zomgdk:BAABNQAECoEvAAIHAAkKgyFjCQBfAwAHAAkKgyFjCQBfAwAAAA==.',
Zy='Zynthia:BAAANQADCgQIBAAAAA==.',
['Äm']='Ämäteräsu:BAAANQAECggJAgAAAA==.',
['Ël']='Ëlement:BAAANQADCgIIAgAAAA==.',
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
