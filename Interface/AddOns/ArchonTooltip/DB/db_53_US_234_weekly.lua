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

local lookup = {'Rogue-Assassination','Mage-Frost','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Arms','Paladin-Retribution','Priest-Holy','Paladin-Protection','DemonHunter-Devourer','Unknown-Unknown','Paladin-Holy','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Druid-Restoration','DeathKnight-Frost','Druid-Guardian','Priest-Shadow','DemonHunter-Vengeance','Evoker-Preservation','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Warrior-Fury','Shaman-Enhancement','Monk-Windwalker','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm="Vek'nilash",name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abel:BAEANQADCggICAABNQAECggIFgABAAkOAA==.',
Ae='Aeidail:BAACNQAFFH8UAAMCAAYKNB5EBQC7AAADAAUK3xcFGgClAQACAAIKhB5EBQC7AAA1AAQKfysAAwIACQqjJPAGAIcCAAMACQogIhRUANgCAAIABwpQI/AGAIcCAAAA.',
Ag='Agraceful:BAAANQAECgUIBgAAAA==.',
Ai='Aidton:BAAANQAECgEIAQAAAA==.Aiobhicefall:BAAANQAECgMIBwAAAA==.Aiobhicefell:BAAANQAECgQICwAAAA==.Aiobicefall:BAAANQAECgQICAAAAA==.Aioboicefall:BAAANQADCgcICwAAAA==.Aioicefall:BAAANQABCgYIBgAAAA==.Aiza:BAABNQAECn82AAQEAAkKcBnrDQBzAQAFAAcK4BnaYgAtAgAEAAYKFxXrDQBzAQAGAAMKkgsnSQCjAAAAAA==.',
Al='Albinoknight:BAAANQADCgEIAQAAAA==.Alessia:BAAANQADCgYICgAAAA==.',
An='Angrypants:BAAANQAECgUIDwAAAA==.Animalfriend:BAAANQADCggJDgAAAA==.Anklesmasher:BAAANQAECgIIBQAAAA==.Antisocial:BAAANQADCggIEAABNQAECgkKKQAHAGoiAA==.',
Ar='Arfaz:BAABNQAECn8YAAMHAAgK5BY0MwBcAgAHAAgK5BY0MwBcAgAIAAEKcg7Z0QApAAAAAA==.Arthemis:BAAANQAECgQIBAAAAA==.Arçano:BAAANQADCgMIAwABNQAECgkJJgAJABYWAA==.',
As='Astramoon:BAAANQAECgUIDQAAAA==.',
Ay='Aylå:BAAANQADCgIIAgAAAA==.',
Ba='Baerd:BAAANQADCgcICQAAAA==.Barlz:BAAANQADCgUIEwAAAA==.',
Be='Beasthunt:BAAANQAECgYIEQAAAA==.Beatmywillie:BAAANQAECgUIBQAAAA==.Bebby:BAAANQAECgQICwAAAA==.Belienn:BAAANQADCggICAAAAA==.Belwolf:BAAANQADCgcIFAAAAA==.Bennehona:BAAANQADCgEIAQAAAA==.Bergstrom:BAABNQAECn8kAAIKAAgKawwiswCzAQAKAAgKawwiswCzAQAAAA==.Betrayer:BAAANQAECgEIAQABNQAECggILQAFAPUkAA==.',
Bi='Biancafiamma:BAAANQAECgIIAgAAAA==.Biancaneve:BAABNQAECn8aAAILAAgKahb9VwAWAgALAAgKahb9VwAWAgAAAA==.',
Bo='Bombacløt:BAABNQAECn8cAAMGAAcKDBP7EgDaAQAGAAcKDBP7EgDaAQAFAAIKiQLSLwFTAAAAAA==.',
Br='Brastin:BAABNQAECn8YAAIMAAYK0Rk5JQCyAQAMAAYK0Rk5JQCyAQAAAA==.Brenell:BAABNQAECn8hAAIDAAgKbBVotAAZAgADAAgKbBVotAAZAgAAAA==.Brixscen:BAAANQAECgYICQAAAA==.',
Bu='Bubblehearth:BAAANQAECgEIAQABNQAFFAUIEAANAHQLAA==.',
Ca='Cabëla:BAAANQAECgUICQABNQAECgUIDwAOAAAAAA==.Caineicefall:BAAANQADCggICwAAAA==.Calacolinda:BAABNQAECn8bAAMPAAYKuQUQvgD8AAAPAAYKuQUQvgD8AAAKAAUKpQUtLgHOAAAAAA==.',
Ce='Celestiall:BAAANQAECgUIBQAAAA==.Ceridwyn:BAAANQADCgcIEgAAAA==.',
Ch='Chadalonius:BAAANQADCgQIBAABNQAFFAQIDAAQAJ8SAA==.Cheesecurd:BAAANQAECgIIAgAAAA==.Choal:BAAANQADCgYICwAAAA==.Chriswin:BAAANQADCgEIAQAAAA==.',
Cl='Claytonbigsb:BAAANQADCgYIBgABNQAECgUIDgAOAAAAAA==.',
Co='Corahin:BAAANQAECgQIBAAAAA==.',
Cu='Cuecumba:BAAANQAECgUIDgAAAA==.',
Cy='Cynndi:BAAANQABCgYIBgAAAA==.',
Da='Dalren:BAACNQAFFH8PAAIRAAYKSBYiAwDIAQARAAYKSBYiAwDIAQA1AAQKfzkAAxEACQpkIWQEAFQDABEACQpLIWQEAFQDABIAAgpnHa4bAIcAAAAA.Dalvix:BAAANQAECgIIAwABNQAECggIHgATAKEiAA==.Dammedude:BAAANQABCgMIAwAAAA==.Dartagnan:BAABNQAECn8YAAIUAAgKgRFTfQAPAgAUAAgKgRFTfQAPAgAAAA==.Darthmaul:BAABNQAECn8lAAIVAAgKcBCoRADbAQAVAAgKcBCoRADbAQAAAA==.Daveykrook:BAAANQAECggIAQABNQAECggIGgAFABYYAA==.David:BAAANQAECgYIEQAAAA==.',
De='Dendiian:BAAANQADCgYICQAAAA==.Depletor:BAABNQAECn8gAAMJAAgK7wh8uACKAQAJAAgK7wh8uACKAQAWAAMKCATLOwBTAAAAAA==.',
Di='Diem:BAAANQAECgQICAAAAA==.Dirtydotss:BAAANQAECgEIAgAAAA==.',
Do='Docholiday:BAABNQAECn8VAAQXAAYK+xWGCADFAQAXAAYK+xWGCADFAQAYAAMKOQcOaACHAAAUAAIKmQHDOQFoAAAAAA==.Docsassist:BAAANQAECgUICgAAAA==.Dowedoes:BAABNQAECn8sAAIKAAgK3QxGsgC1AQAKAAgK3QxGsgC1AQAAAA==.',
Dr='Drachula:BAAANQAECgUIDQAAAA==.Dracultra:BAAANQADCgYIBgABNQAECggIFgAPAIIVAA==.Draeun:BAAANQAECgEIAQABNQAFFAYIDwARAEgWAA==.Dreolan:BAAANQAECgcIEQAAAA==.Druaga:BAAANQAECggIEAAAAA==.Dràchula:BAAANQADCgYICQAAAA==.Dràúgr:BAAANQADCgMIAwAAAA==.',
Dy='Dyala:BAABNQAECn8cAAIZAAgKYBy+FwB+AgAZAAgKYBy+FwB+AgAAAA==.',
Dz='Dzznuts:BAAANQABCgYICgAAAA==.',
['Dé']='Démonléth:BAAANQAECgIIAgABNQAECgkJJgAaAEQZAA==.',
['Dö']='Dönövan:BAABNQAECn8cAAIKAAcK6Qv2zQB5AQAKAAcK6Qv2zQB5AQAAAA==.',
Eg='Eggyolk:BAABNQAECn8YAAIbAAgKXxfeEwAgAgAbAAgKXxfeEwAgAgAAAA==.',
El='Elastwo:BAAANQADCgcIFgAAAA==.Eloise:BAAANQAECgEIAQAAAA==.Elvenbane:BAABNQAECn8sAAMcAAgKMBTfIwAPAgAcAAgKMBTfIwAPAgALAAgKoQLWngAzAQAAAA==.',
Eu='Eunliza:BAAANQAECggICAAAAA==.',
Ew='Ew:BAACNQAFFH8QAAMUAAYK6BVUBQD7AQAUAAYK6BVUBQD7AQAYAAEKyAfBJABAAAA1AAQKfy8AAxQACQo4IRoWAEIDABQACQo4IRoWAEIDABgABwpHGWw1AJ8BAAE1AAQKCQopAAcAaiIA.',
Ex='Extrathick:BAAANQAECgEIAQAAAA==.',
Fa='Fathershale:BAAANQADCgYIEwAAAA==.',
Fe='Fedupdk:BAAANQADCgYIDQAAAA==.Feet:BAAANQAECgUIBwAAAA==.Felidae:BAEANQADCggIJAAAAA==.',
Fi='Firedancer:BAAANQAECgQIBgAAAA==.Fizzfiend:BAAANQADCggIDQAAAA==.',
Fo='Foulcor:BAAANQAECgIIAgABNQAECgYIEQAOAAAAAA==.',
Fr='Freakadeek:BAAANQAECgIIBQABNQAECgYIFQAXAPsVAA==.Freâkadeek:BAAANQADCgQIBAABNQAECgYIFQAXAPsVAA==.Frieren:BAABNQAECn8YAAICAAgKQRUECgApAgACAAgKQRUECgApAgAAAA==.Frëak:BAAANQADCgUIBgABNQAECgYIFQAXAPsVAA==.',
Ga='Gabbyo:BAAANQAECgUIEQAAAA==.Galadorn:BAABNQAECn8eAAMTAAgKoSJuEQARAwATAAgKISJuEQARAwAdAAUKriAFEACuAQAAAA==.',
Ge='Genasis:BAAANQABCgMIBQAAAA==.Gerdash:BAAANQAECgYIEwAAAA==.Gerred:BAABNQAECn8oAAIJAAgKUhtGYQBnAgAJAAgKUhtGYQBnAgAAAA==.',
Gh='Ghallow:BAAANQAECgUIBQAAAA==.Ghosthowl:BAAANQAECgUIDAAAAA==.',
Go='Goldenflame:BAAANQAECgMIBQAAAA==.Goldenlight:BAABNQAECn8qAAILAAkK4BJMVQAgAgALAAkK4BJMVQAgAgAAAA==.Goldenmunc:BAAANQADCgIIAgAAAA==.Goldenone:BAAANQAECgUICwAAAA==.Goldenpants:BAAANQADCggIDwAAAA==.',
Gr='Grandesaxx:BAAANQAECgQICAAAAA==.Grievous:BAABNQAECn8sAAIdAAgKzSUiAgBtAwAdAAgKzSUiAgBtAwAAAA==.',
Ha='Hailmary:BAAANQAECgUIDwAAAA==.Hakudoshi:BAAANQAECgQIBAAAAA==.Harmanee:BAAANQADCgYIBgAAAA==.Hauser:BAABNQAECn8eAAIKAAgKLh5BYgBvAgAKAAgKLh5BYgBvAgAAAA==.',
He='Healaga:BAAANQAECgUIBwABNQAECggIGAAHAOQWAA==.Heinrich:BAAANQADCgMIAwAAAA==.',
Hh='Hhoonnzz:BAAANQADCgYIBgABNQAECgkKKQAHAGoiAA==.',
Ho='Hornreaper:BAABNQAECn8dAAQeAAgKCAx0LABAAQAeAAcKoQl0LABAAQASAAYKagxnEAAvAQARAAEK4ALEQQAlAAAAAA==.',
Hu='Hubbabubbajr:BAAANQAECgYIEAAAAA==.',
Il='Ilavengu:BAAANQAECgYIBwABNQAFFAUIDAAcADMgAA==.',
Is='Isochu:BAAANQADCgMJAwAAAA==.',
Ja='Jayonor:BAABNQAECn8pAAMfAAgKnBzCQwBjAgAfAAgKnBzCQwBjAgAgAAEKwQAQNQEWAAAAAA==.',
Je='Jek:BAAANQADCgEIAQAAAA==.',
Ju='Judgethis:BAAANQABCgIIAgAAAA==.Juicycucci:BAAANQADCgcIDQABNQAFFAUIEAANAHQLAA==.',
Ka='Kaevrielle:BAEANQAECgcIEgAAAA==.Kaidrosa:BAAANQAECgIIAgAAAA==.Kainicefall:BAAANQAECgUICgAAAA==.Kainicefell:BAAANQAECgIIAgAAAA==.Kainoficefal:BAAANQAECgYICQAAAA==.Kaladîn:BAAANQAECgEIAQABNQAFFAYIFAACADQeAA==.Kalokako:BAAANQADCgEIAQAAAA==.Kamel:BAAANQABCgQIBQAAAA==.Karwin:BAAANQAECggICwAAAA==.',
Ke='Keeper:BAAANQAECgcIDAABNQAFFAIIBQAKAIQeAA==.Keeperodark:BAABNQAECn8YAAIFAAkKPxEraQAdAgAFAAkKPxEraQAdAgABNQAFFAIIBQAKAIQeAA==.Keeperolight:BAACNQAFFH8FAAIKAAIKhB7WHAC6AAAKAAIKhB7WHAC6AAA1AAQKfzcAAgoACQpRJR0FANADAAoACQpRJR0FANADAAAA.',
Ki='Kifo:BAAANQAECgEIAQABNQAECgQIBgAOAAAAAA==.Killkat:BAAANQAECgUIDwAAAA==.',
Ko='Koojo:BAAANQAECgYIDwAAAA==.',
La='Lans:BAAANQAECgIIAgAAAA==.Larew:BAAANQAECgQIBwAAAA==.',
Le='Lealla:BAABNQAECn8rAAIVAAgK5Rz+JACnAgAVAAgK5Rz+JACnAgAAAA==.Leodin:BAAANQADCgYIBgAAAA==.Lethhunt:BAAANQAECgEIAQABNQAECgkJJgAaAEQZAA==.Letholas:BAABNQAECn8mAAQaAAkKRBl7NAAFAgAaAAgKHxl7NAAFAgAHAAcKwxNwXQCWAQAIAAEKAADp0QApAAAAAA==.',
Li='Lightmàiden:BAAANQADCgEIAQAAAA==.Lilkingpunch:BAAANQADCgYIBgABNQAECgkJRgAhAFghAA==.Lizardgang:BAAANQAECgUICQAAAA==.',
Lo='Loganshu:BAAANQADCgYIBgAAAA==.Lokan:BAABNQAECn8dAAMUAAgKIBkZVAByAgAUAAgKQBgZVAByAgAXAAUKIBBKDAASAQAAAA==.Lots:BAABNQAECn8iAAMFAAkKqSHCOgCgAgAFAAcKCyLCOgCgAgAGAAIKtCD2QQC7AAAAAA==.',
Lu='Ludakris:BAAANQAECgUIDwAAAA==.',
['Lí']='Líonheart:BAAANQAECgUICAAAAA==.',
Ma='Maami:BAAANQAECgYICwAAAA==.Machognome:BAAANQADCgQIBAAAAA==.Mahina:BAAANQAECgUIDgAAAA==.Makrabro:BAAANQABCgIIAgAAAA==.Marcille:BAAANQAECgcJDgAAAA==.Mattix:BAAANQADCggICAAAAA==.Matíx:BAABNQAECn8aAAMFAAcKFhjzeQDxAQAFAAcKFhjzeQDxAQAGAAIKVA7EWwBtAAAAAA==.Mayhaps:BAABNQAECn8lAAMUAAkKjA/XZwBCAgAUAAkKjA/XZwBCAgAYAAEKAAD8ngAWAAAAAA==.',
Me='Mentaltitty:BAAANQAECgYIEQAAAA==.',
Mi='Milhouse:BAABNQAECn8sAAIIAAgKACKHEwAOAwAIAAgKACKHEwAOAwAAAA==.Minerwor:BAAANQAECgEIAQAAAA==.Miooh:BAAANQADCgcIGQAAAA==.Mirrayla:BAAANQADCgEIAQAAAA==.Misty:BAAANQAECgQIBAAAAA==.',
Mm='Mmisty:BAABNQAECn8ZAAIVAAgKJBBBRADeAQAVAAgKJBBBRADeAQAAAA==.',
Mo='Momometaru:BAABNQAECn8fAAQGAAgKFhAeMgD8AAAFAAgKNQ0ngwDaAQAGAAQK8BEeMgD8AAAEAAMKnwr8GQC0AAAAAA==.Monsterbee:BAABNQAECn8uAAIFAAkKlhUZTwBkAgAFAAkKlhUZTwBkAgAAAA==.Morne:BAAANQADCgYIBgAAAA==.',
Mu='Mustypizza:BAAANQAECgUIDwAAAA==.',
My='Mystery:BAABNQAECn8sAAIeAAgKdxwKEQCXAgAeAAgKdxwKEQCXAgAAAA==.',
Na='Nailme:BAAANQAECgUIBQAAAA==.Nats:BAABNQAECn8aAAIgAAgK7RM5UgAaAgAgAAgK7RM5UgAaAgAAAA==.',
Ne='Neameny:BAABNQAECn8sAAIUAAgK8g8bdgAgAgAUAAgK8g8bdgAgAgAAAA==.',
Ni='Nightstar:BAAANQADCgYIBgAAAA==.',
Nu='Nualrossan:BAAANQADCgEIAgAAAA==.Nubrac:BAAANQAECgYIDwAAAA==.',
Ob='Oblivion:BAABNQAECn8tAAMFAAgK9SQjEABPAwAFAAgK9SQjEABPAwAGAAIK0BSnVQB8AAAAAA==.',
Om='Omey:BAAANQAECgUICQAAAA==.',
Pa='Pallyshore:BAAANQADCggICAAAAA==.Papichuló:BAAANQADCgMIBgABNQAECgYIFQAXAPsVAA==.',
Pi='Pixae:BAAANQAECgYIDAAAAA==.',
Po='Portknight:BAAANQADCgcIBwAAAA==.Potatochip:BAAANQAECgIIAgAAAA==.Powerplant:BAACNQAFFH8MAAIUAAUKPSKaCAC7AQAUAAUKPSKaCAC7AQA1AAQKfyoAAhQACQq1IZQXADoDABQACQq1IZQXADoDAAAA.',
Py='Pyralys:BAABNQAECn8qAAILAAgKvw+magDaAQALAAgKvw+magDaAQAAAA==.',
['Pâ']='Pârtyrockêr:BAAANQADCgUIBwABNQAECgYIFQAXAPsVAA==.',
Ra='Raelene:BAAANQADCgYICQAAAA==.Ragedk:BAAANQAECgIIAwABNQAECgcIBwAOAAAAAA==.Ragenbefcake:BAAANQADCggICwAAAA==.Ragetality:BAAANQAECgcIBwAAAA==.Rallaster:BAAANQAECgUICQABNQAECggILAAcADAUAA==.Rampage:BAAANQABCgUIAgAAAA==.Raserei:BAABNQAECn8fAAMiAAgK9R6KBwB5AgAiAAgKxx2KBwB5AgAJAAMKmxsC9ADwAAAAAA==.Rattelyr:BAAANQADCgQIBAAAAA==.Rawb:BAAANQAECgYJCgABNQAECgkKKQAHAGoiAA==.',
Re='Recolada:BAAANQADCgcJDAAAAA==.Regicee:BAAANQAECgYIEQAAAA==.',
Ri='Riffraff:BAAANQADCggICgAAAA==.',
Ro='Rockdyou:BAAANQAECgYICAAAAA==.Rotlobster:BAABNQAECn8eAAIEAAkKhyI8AQBUAwAEAAkKhyI8AQBUAwABNQAECgkJLAAjAKcfAA==.',
Ru='Rudal:BAAANQADCgIIAgAAAA==.Rundvelt:BAAANQADCgIIAgAAAA==.',
Ry='Rydiaicefall:BAAANQAECgMIAwAAAA==.',
Sa='Sapkick:BAAANQAECgQIBAAAAA==.',
Se='Selina:BAAANQAECgQIBAAAAA==.Serdwarf:BAAANQAECgYIEQAAAA==.Sertian:BAAANQADCgQIBAAAAA==.',
Sh='Shatha:BAAANQADCgQIBQAAAA==.Sherten:BAAANQAECgIJAgAAAA==.Shooturiout:BAAANQAECgMIAwAAAA==.Shtanky:BAABNQAECn8XAAIWAAgKyBJXFgDAAQAWAAgKyBJXFgDAAQAAAA==.',
Si='Sinpony:BAAANQABCgQIBAAAAA==.Sixsixsix:BAAANQADCggJCgABNQAECgkKKQAHAGoiAA==.',
Sk='Sketch:BAAANQAECgIIAgABNQAFFAYIFwAbAH0YAA==.Skoogz:BAAANQAECgQIBAAAAA==.',
So='Sogsy:BAAANQAECgYIEAAAAA==.Soleri:BAAANQAECgQIBAAAAA==.Soulfulgingr:BAAANQAECgIIAgAAAA==.',
St='Styx:BAAANQAECgUIBQAAAA==.Stza:BAAANQABCgYICAAAAA==.',
Su='Sunbake:BAAANQAECgQICQAAAA==.',
Sw='Sweetbbyraze:BAACNQAFFH8MAAIRAAUK1hPGBAB/AQARAAUK1hPGBAB/AQA1AAQKfyEAAhEACQqIH5YIAOwCABEACQqIH5YIAOwCAAAA.',
['Sí']='Sín:BAAANQADCgIJAgABNQAECgkKKQAHAGoiAA==.',
Ta='Talipally:BAAANQAECgcIEgAAAA==.Taliwhacker:BAAANQADCgMIAwABNQAECgcIEgAOAAAAAA==.Talonleafgrd:BAABNQAECn8UAAIYAAYKWRRBOQCBAQAYAAYKWRRBOQCBAQAAAA==.Tandsonna:BAAANQAECgUIBQAAAA==.Tanisong:BAAANQAECgMIAwAAAA==.',
Te='Terayus:BAAANQADCgIJAgAAAA==.Terraform:BAAANQADCgYICwAAAA==.',
Th='Thalor:BAAANQAFFAIIAgABNQAFFAYIDQAkAG8ZAA==.Thekingpunch:BAABNQAECn9GAAIhAAkKWCGpBQBBAwAhAAkKWCGpBQBBAwAAAA==.Thenle:BAAANQAECgEIAQAAAA==.Theworst:BAAANQAECgYIBgABNQAECgkKKQAHAGoiAA==.',
Ti='Tillwar:BAABNQAECn8vAAIJAAgKgxl3YwBhAgAJAAgKgxl3YwBhAgAAAA==.Tiàna:BAAANQADCgEIAQAAAA==.',
To='Tofu:BAABNQAECn8WAAIHAAgKlSAVLwBxAgAHAAgKlSAVLwBxAgAAAA==.Tortillachip:BAAANQADCgYIBgAAAA==.',
Tr='Treibh:BAABNQAECn8lAAIZAAgKsBcbIQAcAgAZAAgKsBcbIQAcAgAAAA==.Trulydps:BAAANQAECgYIEwAAAA==.',
Tu='Tust:BAAANQAECgQIBwABNQADCgYICgAOAAAAAA==.',
Ty='Tymora:BAAANQADCggICAABNQAECggILAAcADAUAA==.',
['Të']='Tërris:BAAANQAECgYIEwAAAA==.',
['Tî']='Tîlldeath:BAAANQAECgUICgAAAA==.',
Un='Undzl:BAACNQAFFH8IAAMaAAIKox8tEwCiAAAaAAIKox8tEwCiAAAHAAEKcga2JAA4AAA1AAQKfzgAAwcACQp6JSkKAGoDAAcACQqhIikKAGoDABoACAqRJHMLADoDAAAA.Unknowna:BAAANQADCgYIBgAAAA==.',
Ur='Urowndad:BAAANQADCgIIAgABNQAECgUIDgAOAAAAAA==.',
Va='Vallez:BAEBNQAECn8gAAMPAAgKuyVEDQBeAwAPAAgKuyVEDQBeAwAKAAEKAABcqAEwAAAAAA==.Varnusshadow:BAAANQAECgIIBAAAAA==.Vayn:BAAANQAECgUICgAAAA==.',
Ve='Velladoree:BAAANQAECgIJAgAAAA==.Vexahlia:BAAANQAECggIDAAAAA==.',
Vy='Vyrable:BAEBNQAECn8WAAQBAAgKCQ6pOgDjAQABAAgK6A2pOgDjAQAlAAMK2gThFgB1AAAQAAEKAAB0VQAnAAAAAA==.',
Wa='Waveygravee:BAAANQADCgcJCwAAAA==.Wavygraivy:BAAANQAECgQICgAAAA==.',
We='Wedragon:BAAANQAECgQIBQAAAA==.',
Wo='Woofwoof:BAAANQAECgIIBAAAAA==.Wooshh:BAAANQAECgUIDQAAAA==.',
Xh='Xhexana:BAABNQAECn8bAAIgAAcKuA5bjABmAQAgAAcKuA5bjABmAQABNQAECggILAAUAPIPAA==.',
Xi='Xianofukuju:BAABNQAECn8jAAIVAAcKrRUVQwDlAQAVAAcKrRUVQwDlAQABNQAECggIHwAGABYQAA==.',
Xr='Xrayl:BAABNQAECn8qAAMmAAkKtxzpCgBfAgAmAAgKFBrpCgBfAgAkAAYKvhxFLAC0AQAAAA==.',
Xz='Xzerocool:BAAANQAECgUIDgAAAA==.',
Yo='Yoshikazu:BAAANQAECgIIAgAAAA==.',
Za='Zaarah:BAAANQADCgUIFAAAAA==.',
Ze='Zendezoth:BAAANQAECgYIDQAAAA==.Zevthekuatin:BAAANQAECgUIDgAAAA==.',
Zh='Zhiva:BAAANQAECgUICwAAAA==.',
Zy='Zykoz:BAAANQAECgUIDwAAAA==.',
['Åy']='Åyna:BAAANQADCgcIEQAAAA==.',
['Ða']='Ðaddy:BAAANQAECgYIEAAAAA==.Ðamned:BAAANQAECgUICAABNQAECgkKKQAHAGoiAA==.',
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
