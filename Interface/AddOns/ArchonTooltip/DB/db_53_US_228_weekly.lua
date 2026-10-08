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

local lookup = {'Hunter-Survival','DeathKnight-Frost','Unknown-Unknown','Hunter-BeastMastery','Priest-Holy','Warrior-Fury','Warrior-Arms','Monk-Mistweaver','DeathKnight-Unholy','Priest-Shadow','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Druid-Balance','Paladin-Retribution','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Frost','Monk-Brewmaster','DemonHunter-Devourer','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','DemonHunter-Vengeance','Paladin-Protection','Rogue-Outlaw',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abasi:BAAANQABCgQIBAAAAA==.',
Ad='Ademar:BAABNQAECoEiAAIBAAkKnB3kAgDYAgABAAkKnB3kAgDYAgABNQAFFAIIBQACAOoOAA==.',
Al='Alkie:BAAANQADCggICgAAAA==.Allectra:BAAANQAECgIIAgAAAA==.Allupinya:BAAANQAECgQIBAABNQAECgUIEQADAAAAAA==.',
Am='Amarie:BAAANQABCgMIAwAAAA==.Amnon:BAAANQAECgMIBwAAAA==.',
An='Anáthema:BAAANQABCgEIAQAAAA==.',
Ar='Arath:BAAANQADCggICQAAAA==.Arielsz:BAAANQADCgUJBQAAAA==.',
As='Asanath:BAAANQADCgYJBQAAAA==.Ashlara:BAAANQAECgYICgAAAA==.',
Au='Ausha:BAAANQADCggICAAAAA==.',
Az='Azdaja:BAAANQADCgQIBAAAAA==.Azulå:BAABNQAECoE1AAIEAAkK9SPoBwCQAwAEAAkK9SPoBwCQAwAAAA==.',
Ba='Baadkitty:BAAANQADCgQIBAAAAA==.Bandwidth:BAAANQADCgUIBQABNQAECgMIBAADAAAAAA==.',
Be='Becomedeath:BAAANQABCgcICwAAAA==.Bellachai:BAAANQAECgMIBAAAAA==.Benm:BAAANQADCgcIBwABNQAECgkJJQAFAF4gAA==.Berastu:BAABNQAECoEiAAMGAAgK0xi2BwBNAgAGAAgK0xi2BwBNAgAHAAQKwAZkAwGiAAAAAA==.Bergalicious:BAAANQAECgUIBwAAAA==.',
Bo='Booz:BAAANQADCgQJBAAAAA==.Bowdacious:BAAANQAECgIIAgABNQAECgUIEQADAAAAAA==.',
Bu='Bugabooed:BAAANQADCgIIAgAAAA==.',
Ca='Callee:BAAANQADCgcICQAAAA==.Calyse:BAAANQADCgYIBgAAAA==.Casima:BAAANQAECgEIAQAAAA==.',
Ch='Cheydinhal:BAABNQAECoEcAAIFAAgKMAcvewBvAQAFAAgKMAcvewBvAQAAAA==.Cheydinhalas:BAAANQADCgMIBQAAAA==.Chichi:BAABNQAECoEcAAIIAAcK9xqjEwAVAgAIAAcK9xqjEwAVAgAAAA==.Chicknwaffle:BAAANQAECgIIAwAAAA==.Chumlee:BAAANQADCgYIBwAAAA==.Chunks:BAAANQAECgQIBQAAAA==.',
Co='Colleague:BAAANQAECgQICAAAAA==.Cornmoon:BAAANQADCgUIDQAAAA==.',
Cr='Creamed:BAAANQAECgUIBQABNQAECggIJAAEAPwaAA==.',
Da='Darksushi:BAAANQAECgIIAgAAAA==.Dashamana:BAAANQAECgcIDgAAAA==.',
De='Deathbear:BAAANQAECgMIBgAAAA==.Demacia:BAAANQADCggIDgABNQAFFAUICAAJADwMAA==.',
Dh='Dhabyss:BAAANQADCgIIAgABNQAECggIGwADAAAAAA==.',
Di='Dimensionul:BAAANQAECgEIAQAAAA==.Dimensiònal:BAAANQADCgMIAwAAAA==.Dinbek:BAAANQAECgMIAwAAAA==.Displacement:BAAANQADCgQIBAABNQAECgMIBAADAAAAAA==.',
Do='Dordis:BAAANQAECgYIDQAAAA==.',
Dr='Dragonflamz:BAAANQABCgIIAgAAAA==.Drashammy:BAAANQADCggIEAAAAA==.',
Du='Duckmyass:BAAANQADCgMIAwAAAA==.Dusksurge:BAAANQADCggIBwAAAA==.',
['Dÿ']='Dÿmmensional:BAAANQAECgIJAgAAAA==.',
Ec='Eclipze:BAABNQAECoEqAAIKAAgKyxYiGwBMAgAKAAgKyxYiGwBMAgAAAA==.Eclipzee:BAAANQAECgUICQABNQAECggIKgAKAMsWAA==.Eclipzé:BAAANQAECgQIBAABNQAECggIKgAKAMsWAA==.Eclípze:BAAANQADCgcIBwABNQAECggIKgAKAMsWAA==.',
Ei='Eifel:BAAANQAECgYIDwAAAA==.',
El='Elaure:BAAANQADCgYIBgABNQAFFAQICAALAHgbAA==.Elenna:BAAANQAECgEIAgABNQAECggIJwAMAHokAA==.Elessardan:BAABNQAECoEnAAQMAAgKeiS3BgBEAwAMAAgKeiS3BgBEAwANAAIKEhfdPQB3AAAOAAIKYAj1lABRAAAAAA==.',
En='Endilli:BAAANQAECgIIBAABNQAECggIKAAPAFQjAA==.',
Eq='Equinoxis:BAEANQAECgUIBQABNQAFFAYIGAAKAJ4RAA==.',
Ey='Eyeeball:BAAANQADCgcJBwAAAA==.',
Fa='Fallynangel:BAAANQAECgUIEAAAAA==.',
Fi='Filho:BAAANQAECgEJAQAAAA==.',
Fo='Foxptm:BAAANQAECgcIDgAAAA==.',
Fr='Frastbert:BAAANQABCgEIAQAAAA==.Friedtips:BAAANQADCgQIAwABNQAECggIIAAQALEdAA==.Frostymilk:BAABNQAECoEeAAIOAAcKFxx+LwA/AgAOAAcKFxx+LwA/AgAAAA==.',
Ga='Galvek:BAABNQAECoEfAAMRAAkK0RlnJgD3AQARAAgKWxRnJgD3AQAEAAQKERcI2gAaAQAAAA==.Garjzlaa:BAAANQAECgQIBAAAAA==.Garugamesh:BAAANQAECgIIBAAAAA==.Gas:BAAANQAECgEIAQAAAA==.',
Gi='Gigglecups:BAAANQAECgEIAQAAAA==.',
Gl='Glutton:BAAANQADCggICAAAAA==.',
Gr='Greyswandir:BAAANQAECgQICAAAAA==.',
Gw='Gwarr:BAAANQAECgQIBwAAAA==.Gwendolynn:BAABNQAECoEZAAIFAAcKQRlHUQAFAgAFAAcKQRlHUQAFAgAAAA==.',
Ha='Hailyea:BAABNQAECoEbAAISAAcK7xhyCgDvAQASAAcK7xhyCgDvAQAAAA==.Haskar:BAAANQADCgYIBwAAAA==.Havøc:BAAANQADCgQIBwABNQAECgYIBgADAAAAAA==.Haylee:BAAANQADCgEIAQAAAA==.',
He='Healydan:BAAANQADCgUIBQAAAA==.',
Ho='Holii:BAAANQADCgUIBwAAAA==.',
Hu='Husky:BAAANQADCgYICgABNQAECgQIBQADAAAAAA==.',
Id='Idfc:BAAANQADCgQJBAAAAA==.',
Il='Ilovesanta:BAAANQAECgQIBQAAAA==.',
In='Indigobleue:BAABNQAECoEgAAIFAAcKdx0tLgCQAgAFAAcKdx0tLgCQAgAAAA==.',
Je='Jemera:BAAANQADCgUIBQAAAA==.',
Ji='Jinkalou:BAAANQADCgMIAwABNQAECggIGwATAJ4eAA==.Jinsun:BAAANQADCggIEAAAAA==.Jinzun:BAAANQADCgYICQAAAA==.Jiñ:BAAANQADCgUICAAAAA==.',
Ka='Kabbitha:BAAANQADCgEIAQAAAA==.Kahuma:BAAANQADCgYIBgAAAA==.Kalzdemar:BAACNQAFFIEFAAICAAIK6g4xEQCQAAACAAIK6g4xEQCQAAA1AAQKgTAAAwIACQorJbEBAMoDAAIACQorJbEBAMoDAAkABQqtE7h9APwAAAAA.',
Ke='Keldanor:BAAANQADCgQIBAAAAA==.',
Kh='Kheann:BAAANQADCgYIBgAAAA==.Khärdeen:BAAANQAECgEIAQAAAA==.',
Ki='Kimjongheals:BAABNQAECoEcAAIFAAgKuRz7MgB7AgAFAAgKuRz7MgB7AgAAAA==.Kissey:BAAANQADCgEIAQAAAA==.',
Ko='Konjar:BAAANQADCgUIBAAAAA==.',
Ku='Kungpowpoee:BAAANQADCgEIAQABNQADCgIIAgADAAAAAA==.',
Ky='Kyrak:BAAANQAECgQIBwAAAA==.',
La='Lainey:BAABNQAECoEaAAIEAAkKAxotPQCPAgAEAAkKAxotPQCPAgAAAA==.Landocamando:BAAANQAECgEIAgAAAA==.',
Le='Lerya:BAAANQAECgcIEgAAAA==.Lessa:BAAANQADCgQIBAAAAA==.Lexnn:BAABNQAECoEiAAIUAAgKTRYPHgBDAgAUAAgKTRYPHgBDAgAAAA==.',
Li='Lifedrynker:BAAANQADCgUIBQAAAA==.Ligetnoone:BAAANQADCggILQAAAA==.Lighte:BAABNQAECoEhAAMSAAgKNCM5AgAwAwASAAgKNCM5AgAwAwAVAAEKQxIapwE1AAAAAA==.',
Lo='Lorin:BAAANQABCgIIAgAAAA==.',
Lu='Lunalia:BAAANQADCgYIBgAAAA==.Lunarrastorm:BAAANQAECgUIBwAAAA==.',
['Lê']='Lêssa:BAAANQAECgEIAQAAAA==.',
Ma='Magici:BAAANQAECgIIAwAAAA==.Marraud:BAAANQADCggIKwAAAA==.Mavren:BAAANQAECgIIAwAAAA==.',
Me='Mellesaun:BAAANQADCgMIAwAAAA==.Mephístø:BAABNQAECoElAAMWAAcKhyNUJQDQAgAWAAcKhyNUJQDQAgAXAAYK3xeQcACKAQABNQAECgkJIQAFAMMjAA==.Merie:BAAANQABCgEIAQAAAA==.Mewtwo:BAAANQAECgMIAwABNQAFFAUIDwAEANQaAA==.',
Mi='Micali:BAABNQAECoEcAAIPAAgKlxpBYQBKAgAPAAgKlxpBYQBKAgAAAA==.Mithrios:BAAANQADCgcJEgABNQAECggIAgADAAAAAA==.',
Mo='Monoris:BAAANQADCgcICwAAAA==.Moonk:BAAANQADCggIFAAAAA==.Moonsaw:BAABNQAECoEqAAIYAAkKqSOBBAB+AwAYAAkKqSOBBAB+AwAAAA==.Morgarlan:BAABNQAECoElAAIFAAkKXiBmDQBFAwAFAAkKXiBmDQBFAwAAAA==.',
My='Mysaa:BAAANQAECgIIAgABNQADCgYIBgADAAAAAA==.',
['Má']='Máxîmús:BAAANQABCgEIAQAAAA==.',
['Mï']='Mïck:BAAANQAECgMICwAAAA==.',
Na='Narusia:BAAANQADCgQIBAAAAA==.',
Ne='Newt:BAABNQAECoEbAAMUAAkK2haFFgCVAgAUAAkK2haFFgCVAgAZAAIKMQTKKwAxAAAAAA==.',
Ni='Ninkasi:BAABNQAECoEaAAIYAAgKchQ3IwDfAQAYAAgKchQ3IwDfAQAAAA==.Nishikki:BAECNQAFFIEYAAIKAAYKnhEiBADiAQAKAAYKnhEiBADiAQA1AAQKgS0AAgoACQosJKYDAJUDAAoACQosJKYDAJUDAAAA.',
No='Noomrats:BAAANQABCgQIAgAAAA==.',
Ny='Nydie:BAABNQAECoEhAAIaAAgKJBJdIQCsAQAaAAgKJBJdIQCsAQAAAA==.',
Om='Omegon:BAAANQADCgcJBwAAAA==.',
Pa='Pallyrocker:BAAANQAECgIIAgAAAA==.',
Pe='Penumbral:BAAANQAECgQIBwAAAA==.Peterios:BAAANQADCgYIBgABNQAFFAUICQAXANMVAA==.',
Ph='Phalst:BAAANQABCgMIBQAAAA==.Phibalan:BAAANQAECgEIAQAAAA==.Phyeo:BAAANQADCgcICwABNQAECggIIgAPAOwIAA==.',
Pi='Pixishot:BAAANQADCggIGgAAAA==.',
Pl='Plagueia:BAAANQADCggIDwAAAA==.',
Pu='Pubba:BAAANQAECgUICAAAAA==.',
Ra='Radiator:BAAANQADCgYIBgABNQAECgMIBAADAAAAAA==.Raelyndria:BAAANQAECgQICQAAAA==.Rampart:BAAANQADCgMIAwAAAA==.Ratraxx:BAAANQAECgMIAgABNQAECggIGwATAJ4eAA==.Ravagen:BAAANQADCgMIAwAAAA==.',
Re='Redrogue:BAAANQAECgMICAAAAA==.Reiko:BAAANQADCgEIAQAAAA==.Renjanà:BAAANQAECgUIBQAAAA==.',
Ri='Riftan:BAABNQAECoEiAAIJAAgKOBoiOQAaAgAJAAgKOBoiOQAaAgAAAA==.Riviee:BAAANQADCggIGgAAAA==.',
Ro='Roderígo:BAAANQADCgEIAQAAAA==.Rogun:BAAANQAECgYIDwAAAA==.Roredge:BAABNQAECoEbAAMTAAgKnh4WBwCxAgATAAgKnh4WBwCxAgAYAAcK1RMVJwC3AQAAAA==.',
Sa='Sarann:BAABNQAECoEYAAMMAAcKvAs5MQBdAQAMAAcKvAs5MQBdAQAOAAEKLQLLpQAqAAAAAA==.Satele:BAAANQADCgEIAQAAAA==.',
Sc='Scarypoppins:BAAANQAECgUIEQAAAA==.',
Sh='Shamoomoo:BAAANQADCggICAAAAA==.Sharrell:BAAANQADCgIIAgAAAA==.Shoripan:BAAANQAECgEIAQAAAA==.',
Si='Silvertrees:BAAANQAECgUICwAAAA==.',
Sk='Skorpius:BAAANQAECgQICAAAAA==.',
Sl='Slaytanic:BAAANQAECgQICgAAAA==.Slymick:BAAANQADCgYICwABNQAECgMICwADAAAAAA==.',
Sn='Snoka:BAABNQAECoEiAAIPAAgK7AgarwCIAQAPAAgK7AgarwCIAQAAAA==.',
So='Solora:BAAANQAECgMICAAAAA==.',
Sp='Sparklesky:BAAANQADCgYICQAAAA==.',
St='Stankyy:BAAANQAECgMIBAAAAA==.Starí:BAAANQADCgYIBwAAAA==.Strawry:BAAANQADCgcIDAAAAA==.',
Su='Sunjiwung:BAAANQADCgUIBQAAAA==.Supadin:BAAANQADCgIIAgAAAA==.',
Sy='Sylanan:BAAANQAECgUIBwAAAA==.Syrüs:BAABNQAECoEgAAIQAAgKsR21IQBmAgAQAAgKsR21IQBmAgAAAA==.',
['Sã']='Sãrik:BAAANQADCgMIAwAAAA==.',
Te='Tempestfury:BAAANQADCgIIAgAAAA==.Temuraire:BAAANQADCgUIBgAAAA==.Tethyssra:BAAANQADCgYICwABNQAECgMIBAADAAAAAA==.',
Th='Thalyra:BAABNQAECoEVAAIUAAYKwha6LwCgAQAUAAYKwha6LwCgAQABNQAECggIDAADAAAAAA==.Thestar:BAAANQADCgQICgAAAA==.Thirstrap:BAABNQAECoEaAAIQAAcKvQ02PwCMAQAQAAcKvQ02PwCMAQAAAA==.Thorge:BAAANQAECgYIEgAAAA==.Thíngtwo:BAAANQADCgUIBQAAAA==.',
Ti='Tiltawhirl:BAAANQAECgMIBQAAAA==.',
Tw='Twigz:BAAANQABCgYICQAAAA==.',
Un='Unclerukus:BAAANQADCgMIAwAAAA==.Unnserra:BAAANQAECgQIBAABNQAECgkJKAAbAFUXAA==.Unrestraind:BAAANQAECgQICAAAAA==.Unrêstrained:BAAANQADCgcICQAAAA==.',
Va='Valeska:BAAANQADCgMIAwAAAA==.',
Ve='Vennt:BAACNQAFFIESAAIRAAYK6x1zAwArAgARAAYK6x1zAwArAgA1AAQKgTUAAhEACQo1JHUDAJsDABEACQo1JHUDAJsDAAAA.Ventt:BAAANQADCggJDgABNQAFFAYIEgARAOsdAA==.',
Vu='Vuhdostev:BAAANQAECgIIAgAAAA==.',
Wa='Warpéd:BAAANQABCgQIAgAAAA==.Wayme:BAAANQADCggIGgAAAA==.',
Wi='Wizzlord:BAAANQAECgMIAwAAAA==.',
Wo='Woghog:BAAANQAECgQIBAAAAA==.Wotlk:BAAANQADCgQIBQAAAA==.',
Xa='Xahle:BAABNQAECoEZAAMJAAcK/Q4xXQB0AQAJAAcK/Q4xXQB0AQACAAEK8AJBowAdAAAAAA==.',
Ze='Zendayah:BAAANQADCggIDAAAAA==.Zent:BAAANQADCggICAAAAA==.Zephie:BAAANQADCgYIBgABNQAECggJGgAYAHIUAA==.',
Zi='Zitillidan:BAABNQAECoEcAAIQAAgKQhpRKAAyAgAQAAgKQhpRKAAyAgABNQAFFAIIBQACAOoOAA==.',
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
