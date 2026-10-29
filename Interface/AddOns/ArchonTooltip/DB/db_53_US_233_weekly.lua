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

local lookup = {'Mage-Frost','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Priest-Discipline','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Preservation','DemonHunter-Vengeance','Shaman-Elemental','Monk-Windwalker','Unknown-Unknown','DemonHunter-Devourer','Priest-Shadow','Hunter-Marksmanship','DemonHunter-Havoc','Warrior-Arms','Rogue-Assassination','Rogue-Subtlety','Druid-Restoration','Warrior-Protection','Warrior-Fury','Evoker-Devastation',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abdarahmed:BAAANQADCgMIAwAAAA==.',
Ah='Ahtreyou:BAAANQADCggIDgAAAA==.',
An='Anblod:BAAANQADCgYIBgAAAA==.Anduin:BAAANQAECgIIBAAAAA==.Angelona:BAACNQAFFH8MAAIBAAUKSiMSAQCHAQABAAUKSiMSAQCHAQA1AAQKfykAAwEACgqXJY8AAMQDAAEACgqXJY8AAMQDAAIAAQo2CQ3OATAAAAAA.Angelsenvy:BAABNQAECn9BAAMDAAoKiCEDBQCIAwADAAoKiCEDBQCIAwAEAAYK2xf61QBvAQAAAA==.Anhe:BAAANQAECgUIBQAAAA==.Antal:BAAANQADCgQICgAAAA==.',
Ar='Archadis:BAABNQAECn8cAAIFAAoKQRr5GQAiAgAFAAoKQRr5GQAiAgAAAA==.Archmichael:BAAANQAECgQICAAAAA==.',
Au='Aurawolf:BAAANQABCgIIAgAAAA==.',
Av='Avyhn:BAACNQAFFH8IAAMGAAQKlB8dHAAWAQAGAAMKNCQdHAAWAQAHAAEKVRYLCgBVAAA1AAQKfx4ABAYACgpdJVIPAFYDAAYACgrUI1IPAFYDAAcAAgrYIyRBAL8AAAgAAQoAJLIiAGcAAAAA.',
Az='Azmoodan:BAAANQADCggICAAAAA==.',
Ba='Bariki:BAAANQADCgcIDQABNQAECgoKOwAJALIhAA==.',
Be='Behemothi:BAAANQAECgUIBQABNQAECgoKOwAJALIhAA==.Bellithia:BAABNQAECn8hAAIKAAgKsBxtBQBWAgAKAAgKsBxtBQBWAgAAAA==.Benji:BAAANQAECgEIAQAAAA==.Bennylava:BAAANQADCggIFAAAAA==.Bewear:BAABNQAECn8aAAIDAAgKmR03LAC2AgADAAgKmR03LAC2AgAAAA==.',
Bi='Bigexplosion:BAAANQABCgMIBAAAAA==.',
Bl='Blitzkreig:BAAANQADCgYIBgAAAA==.Blueberry:BAAANQAECgQICwAAAA==.',
Bu='Bubbulubb:BAAANQAECgYIDgAAAA==.Bulla:BAABNQAECn8UAAICAAkKDQjA7ACxAQACAAkKDQjA7ACxAQAAAA==.Bullthing:BAABNQAECn8tAAMFAAoKsBV9DQDKAQAFAAoKsBV9DQDKAQADAAEKAQghLgEpAAAAAA==.Burlymage:BAAANQADCgcIBwAAAA==.',
Ca='Calex:BAAANQAECgUIDwAAAA==.Cathedrian:BAAANQADCggIDgAAAA==.',
Ce='Cereal:BAAANQAECgEIAQAAAA==.',
Ch='Chansey:BAAANQAECgMIBQAAAA==.Chantu:BAAANQAECgMIAwAAAA==.Chipsbambee:BAABNQAECn8oAAIJAAgKvg60bgBaAQAJAAgKvg60bgBaAQAAAA==.Chttrbox:BAACNQAFFH8sAAMLAAcKtiBGAAC2AgALAAcKtiBGAAC2AgAMAAYKzhRlCADMAQA1AAQKfzsAAwsACgpPJjsAAHsDAAsACgpPJjsAAHsDAAwACQpOIlYZAAwDAAAA.',
Co='Colacan:BAAANQADCgYIDQAAAA==.Coldcuts:BAAANQABCgMIAgAAAA==.Combust:BAABNQAECn9IAAIBAAoKOCMHAgBcAwABAAoKOCMHAgBcAwAAAA==.Corbinnik:BAAANQADCgcIBwAAAA==.',
Cr='Creepndeath:BAAANQADCgYIBgAAAA==.Crux:BAAANQAECgQIBAAAAA==.',
Da='Dallan:BAAANQADCgYIBgAAAA==.Davechapally:BAAANQADCgYIBgAAAA==.',
De='Defaultderyl:BAAANQAECgIIAQAAAA==.Delaomega:BAABNQAECn8xAAMNAAkKbhBOKgBLAQANAAkKbhBOKgBLAQAOAAIKRQg3zABUAAAAAA==.Demonpoop:BAAANQADCgMIBAAAAA==.',
Do='Doozler:BAABNQAECn8bAAIJAAgK+RFVbQBdAQAJAAgK+RFVbQBdAQAAAA==.',
Dr='Drash:BAABNQAECn8fAAMPAAgK1g7hQQC+AQAPAAgK1g7hQQC+AQANAAIKNAe7vQBMAAAAAA==.Dreni:BAAANQAECgMIBQAAAA==.Drown:BAAANQAECgMIBQAAAA==.',
Du='Durotagg:BAAANQAECgcIBwAAAA==.',
Ea='Earlgrips:BAAANQAECgIIBAAAAA==.',
El='Elfguy:BAAANQADCgcIDwAAAA==.Elvishblood:BAAANQADCggIIAAAAA==.',
En='Enhanceeliza:BAABNQAECn8kAAILAAoKkRKFCQAZAgALAAoKkRKFCQAZAgAAAA==.',
Er='Eremetrii:BAEBNQAECn8nAAIEAAkKvhHlWgCnAQAEAAkKvhHlWgCnAQAAAA==.',
Ev='Evocat:BAABNQAECn8ZAAIQAAkK2CFuCQAMAwAQAAkK2CFuCQAMAwAAAA==.',
Fe='Fec:BAABNQAECn9DAAILAAoKxSPsAQCWAwALAAoKxSPsAQCWAwAAAA==.',
Fi='Fibaldrachi:BAABNQAECn8gAAIRAAcKcCO4BQDOAgARAAcKcCO4BQDOAgAAAA==.',
Fr='Frostitude:BAAANQADCgIIAgAAAA==.',
Ga='Garrush:BAAANQADCgIIAgAAAA==.',
Gh='Ghantu:BAABNQAECn81AAISAAkKmSJpDQB9AwASAAkKmSJpDQB9AwAAAA==.Gharma:BAAANQAECgEIAQAAAA==.Ghazghkull:BAAANQABCgYIBgAAAA==.',
Gi='Gilderrand:BAAANQADCgIIAgAAAA==.Girlfriend:BAAANQAECgEIAQAAAA==.',
Gr='Granniekat:BAAANQAECgEIAQAAAA==.Gruon:BAAANQAECgQICQABNQAECgkJHQACANwEAA==.',
Gu='Gulzan:BAAANQADCgUIBQABNQAECgoKOwAJALIhAA==.',
Ha='Haven:BAAANQADCgYICwAAAA==.',
He='Helendir:BAAANQADCgcICAAAAA==.Hellonhooves:BAAANQAECggIDwAAAA==.Herbertwest:BAAANQADCgYIBgAAAA==.',
Hi='Hiimmas:BAACNQAFFH8qAAITAAgKQRsoAQD3AQATAAgKQRsoAQD3AQA1AAQKfzkAAhMACgqdJHsIAEgDABMACgqdJHsIAEgDAAAA.Himeko:BAAANQADCgEIAQAAAA==.',
Ho='Hoggmaxxing:BAAANQADCggICAAAAA==.',
Hu='Huntercobra:BAAANQADCgQIBAAAAA==.',
Hy='Hyacinthe:BAABNQAECn8bAAIIAAgKjhSQBQBnAgAIAAgKjhSQBQBnAgAAAA==.',
If='Ifany:BAAANQADCgQIBgAAAA==.',
Ig='Igordinus:BAAANQADCgYIBgAAAA==.',
Il='Illidanswife:BAAANQAECgEJAQAAAA==.',
In='Infernal:BAAANQAECgEIAQAAAA==.Inspiremoon:BAABNQAECn8yAAIJAAkK/xMNXgBcAgAJAAkK/xMNXgBcAgAAAA==.',
Ir='Irishpryde:BAAANQADCgQIBwAAAA==.',
Jo='Jojojojojojo:BAAANQAECgYICwABNQAECggIEwAUAAAAAA==.',
Ka='Kaliv:BAAANQAECggIEgAAAA==.Kantherath:BAAANQABCggIGAAAAA==.',
Ke='Keahoe:BAAANQABCgEIAQAAAA==.Kensonse:BAAANQADCgIJAgAAAA==.Keyadron:BAAANQADCgQIBAAAAA==.',
Ki='Kirab:BAABNQAECn8qAAIFAAcK2RW9JwCgAQAFAAcK2RW9JwCgAQAAAA==.Kis:BAABNQAECn8aAAISAAgKEAYiXAD5AAASAAgKEAYiXAD5AAAAAA==.Kisten:BAAANQADCgYICQAAAA==.',
Kr='Kreid:BAAANQAECgUICQAAAA==.Kreidwarf:BAAANQAECgUIBQABNQAECgUICQAUAAAAAA==.Kryptonyx:BAAANQADCgMIBgAAAA==.',
La='Larryirl:BAAANQABCgEIAQABNQAECgEIAgAUAAAAAA==.Larryp:BAAANQAECgEIAgAAAA==.',
Le='Leaphraashyl:BAAANQADCgYIBgAAAA==.Lemén:BAABNQAECn8nAAIVAAkK3BlsJAAjAgAVAAkK3BlsJAAjAgAAAA==.',
Li='Ligmaw:BAAANQAECgQIBAAAAA==.Lildonny:BAAANQAECgQIBQAAAA==.Lilpriest:BAABNQAECn8cAAIKAAkKySTQAgDdAgAKAAkKySTQAgDdAgAAAA==.Linaei:BAABNQAECn8yAAIWAAoKjhIqEADMAQAWAAoKjhIqEADMAQAAAA==.',
Ll='Llaz:BAAANQAECggICwAAAA==.',
Lo='Lockinflame:BAACNQAFFH8OAAMGAAUKQBIfGgAlAQAGAAQK1BQfGgAlAQAHAAEKGA2iHgBLAAA1AAQKfykAAwcACQrzIMETANIBAAYACAqPHi1eAD0CAAcABwrMGcETANIBAAAA.',
Lu='Lucedis:BAAANQAECgcIBwABNQAECgoKQQADAIghAA==.Luman:BAABNQAECn8ZAAICAAkKRQ7T0ADkAQACAAkKRQ7T0ADkAQAAAA==.Lurch:BAAANQADCgIIAwAAAA==.',
Ly='Lyndras:BAABNQAECn8cAAICAAcKsRJXGAFjAQACAAcKsRJXGAFjAQAAAA==.',
Ma='Maloob:BAAANQABCgMIBAAAAA==.Mascro:BAAANQAECggIDQAAAA==.',
Me='Meerlin:BAAANQABCggICwAAAA==.Melathia:BAABNQAECn8VAAIGAAcKUwdo1QAfAQAGAAcKUwdo1QAfAQAAAA==.',
Mi='Minimerlin:BAABNQAECn8dAAICAAkK3ATjvgDLAAACAAkK3ATjvgDLAAAAAA==.',
Mo='Moaroak:BAABNQAECn87AAMJAAoKsiFrFACuAgAJAAoKsiFrFACuAgAXAAEKAADuhAA5AAAAAA==.Monilara:BAAANQAECgYIEwAAAA==.Moredis:BAAANQABCgEIAQAAAA==.Morsiroth:BAAANQAECgEIAQAAAA==.',
Mu='Muskei:BAAANQADCggIDAABNQAECggIGwAIAI4UAA==.',
Na='Narcissus:BAAANQADCggIDQAAAA==.',
Ne='Neero:BAAANQAECgYIDwAAAA==.Nelena:BAABNQAECn8rAAIMAAoKEQ1RPACnAQAMAAoKEQ1RPACnAQAAAA==.Nerdbynature:BAAANQAECgQICAAAAA==.Neyes:BAAANQADCgYIBgAAAA==.Nezhyt:BAAANQAECgYIEwABNQAECggICwAUAAAAAA==.',
Ni='Niña:BAAANQADCgUICAAAAA==.',
No='Noodles:BAAANQADCgEIAQABNQAECgYIFAAEAHUVAA==.Nori:BAABNQAECn8fAAISAAgKvyBOJQDvAgASAAgKvyBOJQDvAgABNQAFFAcIKwABAPMmAA==.Notorious:BAAANQAECgEIAQAAAA==.',
Ny='Ny:BAAANQAECgQIBQABNQAECgcIHwAQAKoaAA==.Nyssebows:BAAANQAECggIEQAAAA==.Nythaenia:BAABNQAECn9PAAIDAAoKWB0NFgAmAwADAAoKWB0NFgAmAwAAAA==.',
Ob='Obe:BAABNQAECn8nAAIWAAkKoxo+EQDnAgAWAAkKoxo+EQDnAgAAAA==.Obeymegirl:BAAANQADCgEIAQAAAA==.',
On='Ondinea:BAAANQADCgIIAgAAAA==.One:BAABNQAECn8fAAMYAAgK/BXVMgAVAgAYAAgK/BXVMgAVAgAVAAUKhAdFTwDjAAABNQAECgoKGgACAN4UAA==.',
Pa='Palydawg:BAAANQABCgYIBgAAAA==.Paÿp:BAABNQAECn8pAAIKAAgKShWGBwD8AQAKAAgKShWGBwD8AQAAAA==.',
Pe='Peanut:BAAANQADCgMIAwAAAA==.Pelgryn:BAAANQADCgEIAQAAAA==.Pentasaurusr:BAABNQAECn8VAAMGAAYKwg9n0QAnAQAGAAUKQg9n0QAnAQAHAAIKDAuFXgBoAAAAAA==.',
Pl='Platemedic:BAAANQAECgYIBgAAAA==.',
Pr='Pressinbtns:BAAANQAECgYIBgABNQAECgoKHAAFAEEaAA==.',
Pu='Purp:BAAANQAECgEIAQAAAA==.',
Py='Pyromainiac:BAAANQAECgEIAQAAAA==.',
['Pú']='Pústulia:BAAANQABCgEIAQABNQAECggIGwAZAJkUAA==.',
Qu='Queteimporta:BAABNQAECn8bAAIZAAgKmRT6ogDFAQAZAAgKmRT6ogDFAQAAAA==.',
Ra='Raynsera:BAAANQAECgEIAQAAAA==.',
Re='Recmod:BAABNQAECn8nAAMaAAkKrhmGPQDZAQAaAAYKkRqGPQDZAQAbAAgK6hdUJACmAQAAAA==.Recsdru:BAAANQAECgQIBAABNQAECgkJJwAaAK4ZAA==.Return:BAAANQAECgcIEgABNQAECgoKQwALAMUjAA==.',
Rk='Rkaitoufashi:BAAANQAECgYIDwABNQAFFAQICwAZALIfAA==.',
Ro='Roussalina:BAABNQAECn8ZAAMEAAoKNw+jpwDRAQAEAAoKNw+jpwDRAQAFAAIKFQ2xYgBTAAAAAA==.',
Ru='Ruhua:BAACNQAFFH8LAAIZAAQKsh9FCwAQAQAZAAQKsh9FCwAQAQA1AAQKfy8AAhkACgorIxcmACEDABkACgorIxcmACEDAAAA.',
Ry='Ryahask:BAABNQAECn8iAAILAAcKkgZ4FQAxAQALAAcKkgZ4FQAxAQAAAA==.',
Sa='Sadisticrage:BAAANQAFFAIIBQAAAQ==.Samana:BAABNQAECn8ZAAMIAAcKBBEhCgDZAQAIAAcKlRAhCgDZAQAHAAIKYAi3XgBoAAAAAA==.',
Se='Seeturtle:BAABNQAECn8ZAAMCAAgKxSAkxwD2AQACAAcK8R8kxwD2AQABAAIK9CEpKwChAAAAAA==.Selvala:BAAANQAECggICAAAAA==.Selûne:BAAANQAECgYIAgAAAA==.Semanticss:BAAANQAECgQIBgAAAA==.',
Sh='Shera:BAAANQADCgcIDQAAAA==.Shocksalot:BAAANQAECgUIDQABNQAECggIHwAPANYOAA==.',
Si='Sielm:BAAANQADCgcICwAAAA==.',
Sm='Smell:BAABNQAECn8+AAIEAAkKshDOjwAFAgAEAAkKshDOjwAFAgAAAA==.',
So='Solheim:BAACNQAFFH8QAAIEAAQKbiE9BwAZAQAEAAQKbiE9BwAZAQA1AAQKfyMAAgQACgoeI3AWAMkCAAQACgoeI3AWAMkCAAAA.Soullie:BAAANQAECgEIAQAAAA==.',
Sp='Spacemonk:BAAANQADCggICAAAAA==.Spire:BAAANQADCggICQAAAA==.Sproutling:BAABNQAECn8jAAIcAAgK3RCVMACWAQAcAAgK3RCVMACWAQAAAA==.',
St='Stabandtwist:BAAANQADCgUIBQAAAA==.Stearphen:BAABNQAECn8kAAMdAAkKfxR1DQBfAQAdAAkKfxR1DQBfAQAZAAYKUAXU8gD6AAAAAA==.Stephmage:BAAANQABCgMIAwAAAA==.Stormlight:BAAANQAECgEIAQAAAA==.Strawhatdon:BAAANQADCgYIBwAAAA==.',
Sw='Swizky:BAAANQADCgcIBwABNQAECggIFwACAPoXAA==.',
Sy='Syrxxa:BAAANQADCggIEwAAAA==.',
Ta='Tatri:BAAANQADCgIIAgAAAA==.Taurnil:BAABNQAECn8rAAIIAAoKRA+bBACrAQAIAAoKRA+bBACrAQAAAA==.',
Te='Teloiv:BAAANQADCgEIAQAAAA==.Telperion:BAAANQADCgQIBAAAAA==.',
Th='Thorodinson:BAAANQADCgcICAAAAA==.',
Ti='Ticktickboom:BAAANQABCgMIAwAAAA==.Timelord:BAAANQADCgUIBQAAAA==.Timika:BAAANQAECgUIDgAAAA==.Tinamarie:BAAANQAECgQIBgAAAA==.',
Uk='Ukan:BAABNQAECn83AAIMAAkKfxsjKAAQAgAMAAkKfxsjKAAQAgAAAA==.',
Un='Unholydkguy:BAAANQADCgcIDQAAAA==.',
Ux='Uxx:BAABNQAECn8aAAIPAAoK4Q4lLgBwAQAPAAoK4Q4lLgBwAQAAAA==.',
Va='Vaeron:BAAANQAECgUICAAAAA==.Valareon:BAAANQAECggICQAAAA==.',
Ve='Vengeances:BAAANQAECggIDQAAAA==.Vengeancez:BAABNQAECn8vAAMeAAkKeB5cCgAmAgAeAAcK5hhcCgAmAgAZAAYK3xzEnADUAQAAAA==.',
Vi='Violetta:BAABNQAECn8jAAICAAkKehVpWQCgAQACAAkKehVpWQCgAQAAAA==.Visionaries:BAAANQADCgUIBwAAAA==.',
Vy='Vyeli:BAAANQABCgcICgAAAA==.Vyir:BAAANQAECgQIBAABNQAECggICwAUAAAAAA==.Vynn:BAAANQADCgQIBAABNQAECgcIHwAQAKoaAA==.',
We='Weathergirl:BAAANQAECgEIAQAAAA==.Wereber:BAAANQABCgYICgABNQAECggIGwAZAJkUAA==.',
Wy='Wy:BAABNQAECn8fAAMQAAcKqhqKDgCLAQAQAAYKtRiKDgCLAQAfAAQKZxTrJgD+AAAAAA==.',
Xa='Xanna:BAAANQADCgYIBgABNQAECgoKHAAFAEEaAA==.',
Xe='Xera:BAAANQADCgUIBgAAAA==.',
Xh='Xhaman:BAAANQADCgcICwABNQAECgQIBQAUAAAAAA==.',
Yo='Yoladdie:BAAANQAECgEIAQAAAA==.',
Yu='Yunàlestrà:BAACNQAFFH8MAAMGAAUKDgKlIQDqAAAGAAQKZwKlIQDqAAAHAAEKXAEMJgAzAAA1AAQKfzYABAYACgqsD6VTAGgBAAYACQpoD6VTAGgBAAgAAwr/Bs4dAI0AAAcAAQqMEWx5ADQAAAAA.',
Za='Zach:BAABNQAECn8aAAICAAoK3hQuMwAlAgACAAoK3hQuMwAlAgAAAA==.',
Zo='Zoviel:BAAANQAECggICwAAAA==.',
Zy='Zylith:BAABNQAECn8wAAIRAAkKsiGHAgBYAwARAAkKsiGHAgBYAwAAAA==.',
['Ád']='Ádelaida:BAAANQAECgUIBwABNQAECggIGwAZAJkUAA==.',
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
