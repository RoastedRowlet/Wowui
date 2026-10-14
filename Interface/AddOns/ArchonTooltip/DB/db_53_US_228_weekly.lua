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

local lookup = {'Hunter-Survival','DeathKnight-Frost','DeathKnight-Blood','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Warrior-Fury','Warrior-Arms','Monk-Mistweaver','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Druid-Restoration','Druid-Guardian','Druid-Balance','Rogue-Subtlety','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Frost','Monk-Brewmaster','DemonHunter-Devourer','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abasi:BAAANQABCgQIBAAAAA==.',
Ad='Ademar:BAABNQAECn8iAAIBAAkKOR6tAgADAwABAAkKOR6tAgADAwABNQAFFAIIBQACAOoOAA==.',
Al='Alkie:BAAANQADCggICgAAAA==.Allectra:BAAANQAECgUIBwAAAA==.Allupinya:BAAANQAECgQIBAABNQAECggIFgADAJsbAA==.',
Am='Amarie:BAAANQABCgMIAwAAAA==.Amnon:BAAANQAECgcIDgAAAA==.',
An='Anáthema:BAAANQABCgEIAQAAAA==.',
Ar='Arath:BAAANQADCggICQAAAA==.Arielsz:BAAANQADCgUJBQAAAA==.',
As='Asanath:BAAANQADCgYJBQAAAA==.Ashlara:BAAANQAECgYICgAAAA==.',
Au='Ausha:BAAANQADCggICAAAAA==.',
Az='Azdaja:BAAANQADCgQIBAAAAA==.Azulå:BAACNQAFFH8FAAIEAAIK7AnrKgCEAAAEAAIK7AnrKgCEAAA1AAQKfzoAAgQACQp1JEQMAHsDAAQACQp1JEQMAHsDAAAA.',
Ba='Baadkitty:BAAANQADCgQIBAAAAA==.Bandwidth:BAAANQADCgUIBQABNQAECgQIBwAFAAAAAA==.',
Be='Becomedeath:BAAANQABCgcICwAAAA==.Bellachai:BAAANQAECgQIBwAAAA==.Benm:BAAANQADCgcIBwABNQAECgkJKQAGAF4gAA==.Berastu:BAABNQAECn8pAAMHAAkKEhrOBQC6AgAHAAkKEhrOBQC6AgAIAAQKkAoGGwGeAAAAAA==.Bergalicious:BAAANQAECgUIBwAAAA==.',
Bo='Booz:BAAANQADCgQJBAAAAA==.Bowdacious:BAAANQAECgIIAgABNQAECggIFgADAJsbAA==.',
Bu='Bugabooed:BAAANQADCgIIAgAAAA==.',
Ca='Callee:BAAANQADCgcICQAAAA==.Calyse:BAAANQADCgYIBgAAAA==.Casima:BAAANQAECgEIAQAAAA==.',
Ch='Cheydinhal:BAABNQAECn8jAAIGAAkKXQhRdAC7AQAGAAkKXQhRdAC7AQAAAA==.Cheydinhalas:BAAANQADCgQIBgAAAA==.Chichi:BAABNQAECn8cAAIJAAcK9xotFwAGAgAJAAcK9xotFwAGAgAAAA==.Chicknwaffle:BAAANQAECgMIBAAAAA==.Chumlee:BAAANQADCgYIBwAAAA==.Chunks:BAAANQAECgUICQAAAA==.',
Co='Colleague:BAAANQAECgUICgAAAA==.Cornmoon:BAAANQADCgUIDQAAAA==.',
Cr='Creamed:BAAANQAECgUIBQABNQAECggIJgAEAPYZAA==.',
Da='Darksushi:BAAANQAECgUIBwAAAA==.Dashamana:BAAANQAECgcIDgAAAA==.',
De='Deathbear:BAAANQAECgQICgAAAA==.Demacia:BAAANQADCggIDgABNQAFFAUICQAKALYLAA==.',
Dh='Dhabyss:BAAANQADCgIIAgABNQAECggIIgAFAAAAAA==.',
Di='Dimensionul:BAAANQAECgEIAQAAAA==.Dimensiònal:BAAANQADCgMIAwAAAA==.Dinbek:BAAANQAECgMIAwAAAA==.Displacement:BAAANQADCgQIBAABNQAECgQIBwAFAAAAAA==.',
Do='Dordis:BAAANQAECgYIDQAAAA==.',
Dr='Dragonflamz:BAAANQABCgIIAgAAAA==.Drashammy:BAAANQADCggIEAAAAA==.',
Du='Duckmyass:BAAANQADCgMIAwAAAA==.Dusksurge:BAAANQADCggIBwAAAA==.',
['Dÿ']='Dÿmmensional:BAAANQAECgIIAgAAAA==.',
Ec='Eclipze:BAABNQAECn8sAAILAAgK0hZtHQBTAgALAAgK0hZtHQBTAgAAAA==.Eclipzee:BAAANQAECgUICQABNQAECggILAALANIWAA==.Eclipzé:BAAANQAECgQIBAABNQAECggILAALANIWAA==.Eclípze:BAAANQADCgcIBwABNQAECggILAALANIWAA==.',
Ei='Eifel:BAABNQAECn8XAAMMAAcKYCD1ZQBlAgAMAAcKpB/1ZQBlAgANAAEKsR7vYABVAAAAAA==.',
El='Elaure:BAAANQADCgYIBgABNQAFFAQICAADAIocAA==.Elenna:BAAANQAECgEIAgABNQAECggILwAOAHokAA==.Elessardan:BAABNQAECn8vAAQOAAgKeiSCCAA6AwAOAAgKeiSCCAA6AwAPAAgKUhTUFgD4AQAQAAIKVgezogBRAAAAAA==.',
En='Endilli:BAAANQAECgQICAABNQAECgkJMAAMAJMhAA==.',
Eq='Equinoxis:BAEANQAECgYICwABNQAFFAYIGQALAEoQAA==.',
Ey='Eyeeball:BAAANQADCgcJBwAAAA==.',
Fa='Fallynangel:BAABNQAECn8aAAIRAAYKMAymKgBqAQARAAYKMAymKgBqAQAAAA==.',
Fi='Filho:BAAANQAECgEJAQAAAA==.',
Fo='Foxptm:BAAANQAECgcIDgAAAA==.',
Fr='Frastbert:BAAANQABCgEIAQAAAA==.Friedtips:BAAANQADCgQIAwABNQAECgkJIwASAOcaAA==.Frostymilk:BAABNQAECn8kAAIQAAkKvxohIQDCAgAQAAkKvxohIQDCAgAAAA==.',
Ga='Galvek:BAABNQAECn8hAAMTAAkK5BiaLADjAQATAAgKOhOaLADjAQAEAAQKzxQ19QATAQAAAA==.Garjzlaa:BAAANQAECgQIBAAAAA==.Garugamesh:BAAANQAECgIIBAAAAA==.Gas:BAAANQAECgEIAQAAAA==.',
Gi='Gigglecups:BAAANQAECgEIAQAAAA==.',
Gl='Glutton:BAAANQADCggICAAAAA==.',
Gr='Greenfoam:BAAANQADCgMIAwAAAA==.Greyswandir:BAAANQAECgQIDAAAAA==.',
Gw='Gwarr:BAAANQAECgUICAAAAA==.Gwendolynn:BAABNQAECn8cAAIGAAgK8BjySABHAgAGAAgK8BjySABHAgAAAA==.',
Ha='Hailyea:BAABNQAECn8jAAIUAAgKTRUkCQBCAgAUAAgKTRUkCQBCAgAAAA==.Haskar:BAAANQADCgYIBwAAAA==.Havøc:BAAANQADCgQIBwABNQAECggIBwAFAAAAAA==.Haylee:BAAANQADCgEIAQAAAA==.',
He='Healydan:BAAANQADCgUIBQAAAA==.',
Ho='Holii:BAAANQADCgUIBwAAAA==.',
Hu='Husky:BAAANQADCgYICgABNQAECgUICQAFAAAAAA==.',
Id='Idfc:BAAANQADCgQIBAAAAA==.',
Il='Ilovesanta:BAAANQAECgQIBQAAAA==.',
In='Indigobleue:BAABNQAECn8oAAIGAAgKvRxfIwDdAgAGAAgKvRxfIwDdAgAAAA==.',
Je='Jemera:BAAANQADCgUIBQAAAA==.',
Ji='Jinkalou:BAAANQADCgcICgABNQAECggIIwAVAJYfAA==.Jinsun:BAAANQADCggIEAAAAA==.Jinzun:BAAANQADCgYICQAAAA==.Jiñ:BAAANQADCgUICAAAAA==.',
Ka='Kabbitha:BAAANQADCgEIAQAAAA==.Kahuma:BAAANQADCgYIBgAAAA==.Kalzdemar:BAACNQAFFH8FAAICAAIK6g6cFgCGAAACAAIK6g6cFgCGAAA1AAQKfzAAAwIACQr8JDkDAK8DAAIACQr8JDkDAK8DAAoABQoFFOuIAPoAAAAA.',
Ke='Keldanor:BAAANQADCgQIBAAAAA==.',
Kh='Kheann:BAAANQADCgYIBgAAAA==.Khärdeen:BAAANQAECgEIAQAAAA==.',
Ki='Kimjongheals:BAABNQAECn8iAAIGAAkKMxwUKwC6AgAGAAkKMxwUKwC6AgAAAA==.Kissey:BAAANQADCgEIAQAAAA==.',
Ko='Konjar:BAAANQADCgUIBAAAAA==.',
Ku='Kungpowpoee:BAAANQADCgEIAQABNQADCgIIAgAFAAAAAA==.',
Ky='Kyrak:BAAANQAECgUIDAAAAA==.',
La='Lainey:BAABNQAECn8dAAIEAAkKORqsSACQAgAEAAkKORqsSACQAgAAAA==.Landocamando:BAAANQAECgIIBAAAAA==.',
Le='Lerya:BAAANQAECgcIEgAAAA==.Lessa:BAAANQADCgQIBAAAAA==.Lexnn:BAABNQAECn8qAAIWAAgKERc8IQA/AgAWAAgKERc8IQA/AgAAAA==.',
Li='Lifedrynker:BAAANQADCgUIBQAAAA==.Ligetnoone:BAAANQADCggINQAAAA==.Lighte:BAABNQAECn8oAAMUAAgKOyIKAwAhAwAUAAgKOyIKAwAhAwAXAAEKAACMwgE1AAAAAA==.',
Lo='Logicx:BAAANQAECgMIAwABNQAECgQICgAFAAAAAA==.Lorin:BAAANQABCgIIAgAAAA==.',
Lu='Lunalia:BAAANQADCgYIBgAAAA==.Lunarrastorm:BAAANQAECgYICAAAAA==.',
['Lê']='Lêssa:BAAANQAECgEIAQAAAA==.',
Ma='Magici:BAAANQAECgMIBQAAAA==.Marraud:BAAANQADCggIKwAAAA==.Mavren:BAAANQAECgQIBwAAAA==.',
Me='Mellesaun:BAAANQADCgMIAwAAAA==.Mephístø:BAABNQAECn8oAAMYAAcKHSNKLADKAgAYAAcKHSNKLADKAgAZAAYK3xc3gACHAQABNQAECgkJIwAGAMMjAA==.Merie:BAAANQABCgEIAQAAAA==.Mewtwo:BAAANQAECgMIAwABNQAFFAYIFAAEAFEdAA==.',
Mi='Micali:BAABNQAECn8fAAIMAAgKORiicwBDAgAMAAgKORiicwBDAgAAAA==.Mithrios:BAAANQADCgcIFgABNQAECggICAAFAAAAAA==.',
Mo='Monoris:BAAANQADCgcICwAAAA==.Moonk:BAAANQADCggIFAAAAA==.Moonsaw:BAABNQAECn80AAIaAAkKfiMnBACRAwAaAAkKfiMnBACRAwAAAA==.Morgarlan:BAABNQAECn8pAAIGAAkKXiBjEgA1AwAGAAkKXiBjEgA1AwAAAA==.',
My='Mysaa:BAAANQAECgIIAgABNQADCgYIBgAFAAAAAA==.',
['Má']='Máxîmús:BAAANQABCgEIAQAAAA==.',
['Mï']='Mïck:BAAANQAECgQIDwAAAA==.',
Na='Narusia:BAAANQADCgQIBAAAAA==.',
Ne='Newt:BAABNQAECn8gAAMWAAkKmRrAEgDSAgAWAAkKmRrAEgDSAgAbAAIKMQSbMgAvAAAAAA==.',
Ni='Ninkasi:BAABNQAECn8aAAIaAAgK5xJkKQDPAQAaAAgK5xJkKQDPAQAAAA==.Nishikki:BAECNQAFFH8ZAAILAAYKShC1BQDRAQALAAYKShC1BQDRAQA1AAQKfy8AAgsACQrnJD4KADwDAAsACQrnJD4KADwDAAAA.',
No='Noomrats:BAAANQABCgQIAgAAAA==.',
Ny='Nydie:BAABNQAECn8jAAINAAgKLBAfJwChAQANAAgKLBAfJwChAQAAAA==.',
Om='Omegon:BAAANQADCgcJBwAAAA==.',
Pa='Pallyrocker:BAAANQAECgIIAgAAAA==.',
Pe='Penumbral:BAAANQAECgQIBwAAAA==.Peterios:BAAANQADCgYIBgABNQAFFAUIDgAZACAZAA==.',
Ph='Phalst:BAAANQABCgMIBQAAAA==.Phibalan:BAAANQAECgEIAgAAAA==.Phyeo:BAAANQADCgcICwABNQAECggIKQAMAFANAA==.',
Pi='Pixishot:BAAANQADCggIGgAAAA==.',
Pl='Plagueia:BAAANQADCggIDwAAAA==.',
Pu='Pubba:BAAANQAECgYIDQAAAA==.',
['Pá']='Páin:BAAANQABCgEIAQAAAA==.',
Ra='Radiator:BAAANQADCgYICQABNQAECgQIBwAFAAAAAA==.Raelyndria:BAAANQAECgQICQAAAA==.Rampart:BAAANQADCgMIAwAAAA==.Ratraxx:BAAANQAECgUIBwABNQAECggIIwAVAJYfAA==.Ravagen:BAAANQADCgcICAAAAA==.',
Re='Redrogue:BAAANQAECgQIDAAAAA==.Reiko:BAAANQADCgEIAQAAAA==.Renjanà:BAAANQAECgUIBQAAAA==.',
Ri='Riftan:BAABNQAECn8mAAIKAAkKBRlnMQBlAgAKAAkKBRlnMQBlAgAAAA==.Riviee:BAAANQADCggIGgAAAA==.',
Ro='Roderígo:BAAANQADCgEIAQAAAA==.Rogun:BAABNQAECn8VAAITAAcKhgmVPABnAQATAAcKhgmVPABnAQAAAA==.Roredge:BAABNQAECn8jAAMVAAgKlh9qCACjAgAVAAgKlh9qCACjAgAaAAcKLBr2IAAhAgAAAA==.',
Sa='Sarann:BAABNQAECn8gAAMOAAgKVQvUMgB/AQAOAAgKVQvUMgB/AQAQAAEKLQKftQAqAAAAAA==.Satele:BAAANQADCgEIAQAAAA==.',
Sc='Scarypoppins:BAABNQAECn8WAAIDAAgKmxsgMgBEAgADAAgKmxsgMgBEAgAAAA==.',
Sh='Shamoomoo:BAAANQADCggICAAAAA==.Sharrell:BAAANQADCgIIAgAAAA==.Shoripan:BAAANQAECgEIAQAAAA==.',
Si='Silvertrees:BAAANQAECgUIEAAAAA==.',
Sk='Skorpius:BAAANQAECgUIDQAAAA==.',
Sl='Slaytanic:BAAANQAECgUIDwAAAA==.Slymick:BAAANQADCgYICwABNQAECgQIDwAFAAAAAA==.',
Sn='Snoka:BAABNQAECn8pAAIMAAgKUA0eswCzAQAMAAgKUA0eswCzAQAAAA==.',
So='Solora:BAAANQAECgQIDAAAAA==.',
Sp='Sparklesky:BAAANQADCgYICQAAAA==.',
St='Stankyy:BAAANQAECgQIBgABNQAECgkJIAAWAJkaAA==.Starí:BAAANQADCgYIBwAAAA==.Strawry:BAAANQADCgcIDAAAAA==.',
Su='Sunjiwung:BAAANQADCgUIBQAAAA==.Supadin:BAAANQADCgIIAgAAAA==.',
Sy='Sylanan:BAAANQAECgUIBwAAAA==.Syrüs:BAABNQAECn8jAAISAAkK5xreIACQAgASAAkK5xreIACQAgAAAA==.',
['Sã']='Sãrik:BAAANQADCgMIAwAAAA==.',
Te='Tempestfury:BAAANQADCgIIAgAAAA==.Temuraire:BAAANQADCgUIBgAAAA==.Tethyssra:BAAANQADCgYICwABNQAECgQIBwAFAAAAAA==.',
Th='Thalyra:BAABNQAECn8aAAIWAAYKlh5zJAAgAgAWAAYKlh5zJAAgAgABNQAECggIDgAFAAAAAA==.Thestar:BAAANQADCgQICgAAAA==.Thirstrap:BAABNQAECn8iAAISAAgKuRICOQDmAQASAAgKuRICOQDmAQAAAA==.Thorge:BAAANQAECgYIEwAAAA==.Thíngtwo:BAAANQADCgUIBQAAAA==.',
Ti='Tiltawhirl:BAAANQAECgMIBQAAAA==.',
Tw='Twigz:BAAANQABCgYICQAAAA==.',
Un='Unclerukus:BAAANQADCgMIAwAAAA==.Unnserra:BAAANQAECgQIBAABNQAECgkJLwAcAMgXAA==.Unrestraind:BAAANQAECgUICwAAAA==.Unrêstrained:BAAANQADCgcICQAAAA==.',
Va='Valeska:BAAANQADCgMIAwAAAA==.',
Ve='Vennt:BAACNQAFFH8TAAITAAYK8SH5BAASAgATAAYK8SH5BAASAgA1AAQKfzcAAhMACQpEJI8EAIoDABMACQpEJI8EAIoDAAAA.Ventt:BAAANQADCggJDgABNQAFFAYIEwATAPEhAA==.',
Vu='Vuhdostev:BAAANQAECgIIAgAAAA==.',
Wa='Warpéd:BAAANQABCgQIAwAAAA==.Wartraxx:BAAANQAECgEIAQABNQAECggIIwAVAJYfAA==.Wayme:BAAANQADCggIGgAAAA==.',
We='Weewitch:BAAANQADCgcIBwAAAA==.',
Wi='Wizzlord:BAAANQAECgQIBQAAAA==.',
Wo='Woghog:BAAANQAECgYICQAAAA==.Wotlk:BAAANQADCgQIBQAAAA==.',
Xa='Xahle:BAABNQAECn8gAAMKAAgK9hIxUgDGAQAKAAgK9hIxUgDGAQACAAEK8AKiuwAdAAAAAA==.',
Ya='Yaboì:BAAANQADCgQIBAAAAA==.',
Ze='Zendayah:BAAANQADCggIDAAAAA==.Zent:BAAANQADCggICgAAAA==.Zephie:BAAANQADCgYIBgABNQAECggJGgAaAOcSAA==.',
Zi='Zitillidan:BAABNQAECn8fAAISAAgKGxywHgCgAgASAAgKGxywHgCgAgABNQAFFAIIBQACAOoOAA==.',
Zo='Zogo:BAAANQADCgIIAgAAAA==.',
['Ör']='Öreö:BAAANQADCggICQAAAA==.',
['ße']='ßeech:BAAANQABCggICgAAAA==.',
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
