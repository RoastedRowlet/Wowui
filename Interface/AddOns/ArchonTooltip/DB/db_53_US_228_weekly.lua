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

local lookup = {'Hunter-Survival','DeathKnight-Frost','DeathKnight-Blood','Warlock-Affliction','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Warrior-Fury','Warrior-Arms','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Unholy','Druid-Feral','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Druid-Restoration','Druid-Guardian','Druid-Balance','Rogue-Subtlety','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Frost','Monk-Brewmaster','Evoker-Devastation','DemonHunter-Devourer','Mage-Arcane','Shaman-Elemental','Monk-Windwalker','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Demonology','Evoker-Preservation',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abasi:BAAANQABCgQIBAAAAA==.',
Ad='Ademar:BAABNQAECn8wAAIBAAoK6R6xAgADAwABAAoK6R6xAgADAwABNQAFFAIIBQACAOoOAA==.',
Al='Alkie:BAAANQAECgEIAQAAAA==.Allectra:BAAANQAECgUIEAAAAA==.Allupinya:BAAANQAECgQIBAABNQAECgoKIQADANAbAA==.',
Am='Amarie:BAAANQABCgMIAwAAAA==.Amnon:BAABNQAECn8lAAIEAAgKnhgiBQB4AgAEAAgKnhgiBQB4AgAAAA==.',
An='Anáthema:BAAANQABCgEIAQAAAA==.',
Aq='Aquianna:BAAANQABCgQIBgAAAA==.',
Ar='Arath:BAAANQADCggICQAAAA==.Arielsz:BAAANQADCgUJBQAAAA==.',
As='Asanath:BAAANQADCgYJBQAAAA==.Ashlara:BAAANQAECgYICgAAAA==.',
Au='Ausha:BAAANQADCggICAAAAA==.',
Az='Azdaja:BAAANQADCgQIBAAAAA==.Azulå:BAACNQAFFH8JAAIFAAQKVglLDwDVAAAFAAQKVglLDwDVAAA1AAQKf0gAAgUACgqAJH8MAHoDAAUACgqAJH8MAHoDAAAA.',
Ba='Baadkitty:BAAANQADCgQIBAAAAA==.Bandwidth:BAAANQADCgUIBQABNQAECgQIBwAGAAAAAA==.',
Be='Becomedeath:BAAANQABCgcICwAAAA==.Bellachai:BAAANQAECgQIBwAAAA==.Benm:BAAANQADCgcIBwABNQAECgoKOQAHAHohAA==.Berastu:BAABNQAECn85AAMIAAoKQhndBQC7AgAIAAoKQhndBQC7AgAJAAoK0g1AUACTAQAAAA==.Bergalicious:BAAANQAECgUIBwAAAA==.',
Bl='Bludmace:BAAANQABCgcICQAAAA==.',
Bo='Booz:BAAANQADCgQJBAAAAA==.Bowdacious:BAAANQAECggIDgABNQAECgoKIQADANAbAA==.',
Bu='Bugabooed:BAAANQADCggICgAAAA==.',
Ca='Callee:BAAANQADCgcICQAAAA==.Calyse:BAAANQADCgYIBgAAAA==.Casima:BAAANQAECgEIAQAAAA==.',
Ch='Cheydinhal:BAABNQAECn8rAAIHAAoK2AixdQC7AQAHAAoK2AixdQC7AQAAAA==.Cheydinhalas:BAAANQADCgQIBgAAAA==.Chichi:BAABNQAECn8cAAIKAAcK9xpxFwAGAgAKAAcK9xpxFwAGAgAAAA==.Chicknwaffle:BAAANQAECgUIBQAAAA==.Chumlee:BAAANQADCgYIBwAAAA==.Chunks:BAAANQAECgUIDQAAAA==.',
Co='Colleague:BAAANQAECgUICwAAAA==.Cornmoon:BAAANQADCgYIGQAAAA==.',
Cr='Creamed:BAAANQAECgUIBQABNQAECgoKLwAFAKUYAA==.Crewgy:BAAANQADCgIIAgABNQADCggICAAGAAAAAA==.',
Da='Darksushi:BAAANQAECgcICAAAAA==.Dashamana:BAABNQAECn8fAAILAAoKZBX4HQBTAgALAAoKZBX4HQBTAgAAAA==.',
De='Deathbear:BAAANQAECgUIEwAAAA==.Demacia:BAAANQADCggIDgABNQAFFAUICgAMALYLAA==.',
Dh='Dhabyss:BAAANQADCgIIAgABNQAECggILgAGAAAAAA==.',
Di='Dimensionul:BAAANQAECgEIAQAAAA==.Dimensiònal:BAAANQADCgMIAwAAAA==.Dinbek:BAAANQAECgUICAAAAA==.Dindroc:BAAANQADCggICAAAAA==.Displacement:BAAANQADCgQIBAABNQAECgQIBwAGAAAAAA==.',
Do='Dordis:BAABNQAECn8cAAINAAkKbBtuBgAJAgANAAkKbBtuBgAJAgAAAA==.',
Dr='Dragonflamz:BAAANQADCgQIBAAAAA==.Drashammy:BAAANQADCggIEAAAAA==.',
Du='Duckmyass:BAAANQADCgMIAwAAAA==.Dusksurge:BAAANQADCggIBwAAAA==.',
['Dÿ']='Dÿmmensional:BAAANQAECgMIAgAAAA==.',
Ec='Eclipze:BAABNQAECn85AAIOAAoKChgxDwDfAQAOAAoKChgxDwDfAQAAAA==.Eclipzee:BAAANQAECgUICQABNQAECgoKOQAOAAoYAA==.Eclipzé:BAAANQAECggIEAABNQAECgoKOQAOAAoYAA==.Eclípze:BAAANQADCgcIBwABNQAECgoKOQAOAAoYAA==.',
Ei='Eifel:BAABNQAECn8cAAMPAAcKZSGfZwBlAgAPAAcKZSGfZwBlAgAQAAEKsR78YQBVAAAAAA==.',
El='Elaure:BAAANQADCgYIBgABNQAFFAQICAADAIocAA==.Elenna:BAAANQAECgEIAgABNQAECgoKOAARAL8iAA==.Elessardan:BAABNQAECn84AAQRAAoKvyKsCAA6AwARAAoKvyKsCAA6AwASAAgKUhQ/FwD5AQATAAIKVgeJpABRAAAAAA==.',
En='Endilli:BAAANQAECgYIDQABNQAECgoKNwAPABIhAA==.',
Eq='Equinoxis:BAEANQAECgYICwABNQAFFAcIGwAOAIIPAA==.',
Eu='Euria:BAAANQAECgcIBwABNQAFFAUIEAADAJwPAA==.',
Ey='Eyeeball:BAAANQADCgcJBwAAAA==.',
Fa='Fallynangel:BAABNQAECn8jAAIUAAYKlg4jKwBqAQAUAAYKlg4jKwBqAQAAAA==.',
Fi='Filho:BAAANQAECgQIBQAAAA==.',
Fo='Foxptm:BAAANQAECgcIDgAAAA==.',
Fr='Frastbert:BAAANQABCgEIAQAAAA==.Friedtips:BAAANQADCgQIAwABNQAFFAIIBQAVAHcQAA==.Frostymilk:BAABNQAECn8xAAITAAoKpBuCDwBQAgATAAoKpBuCDwBQAgAAAA==.',
Ga='Galvek:BAACNQAFFH8IAAMWAAQKTAnjDgB8AAAWAAIKLgjjDgB8AAAFAAIKiAvIJgBGAAA1AAQKfyoAAxYACgq9GA4tAOMBABYACQrBEg4tAOMBAAUABQqtHU1uAFsBAAAA.Garjzlaa:BAAANQAECgQIBAAAAA==.Garugamesh:BAAANQAECgIIBAAAAA==.Gas:BAAANQAECgEIAQAAAA==.',
Gi='Gigglecups:BAAANQAECgEIAgAAAA==.',
Gl='Glutton:BAAANQADCggICAAAAA==.',
Gr='Greenfoam:BAAANQADCgMIAwAAAA==.Greyswandir:BAABNQAECn8WAAIFAAYKlQTR9gAVAQAFAAYKlQTR9gAVAQAAAA==.',
Gw='Gwarr:BAAANQAECgUIDgAAAA==.Gwendolynn:BAABNQAECn8jAAIHAAoKFRckSgBHAgAHAAoKFRckSgBHAgAAAA==.',
Ha='Hailyea:BAABNQAECn8wAAIXAAkKfxZNCQBBAgAXAAkKfxZNCQBBAgAAAA==.Haskar:BAAANQADCgYIBwAAAA==.Havøc:BAAANQADCgQIBwABNQAECgcICAAGAAAAAA==.Haylee:BAAANQADCgEIAQAAAA==.',
He='Healydan:BAAANQADCgUIBQAAAA==.',
Ho='Holii:BAAANQADCgUIBwAAAA==.',
Hu='Husky:BAAANQAECgEIAQABNQAECgUIDQAGAAAAAA==.',
Id='Idfc:BAAANQADCgQIBAAAAA==.',
Il='Ilovesanta:BAAANQAECgQIBwAAAA==.',
In='Indigobleue:BAABNQAECn88AAIHAAoKRyILBwBxAwAHAAoKRyILBwBxAwAAAA==.',
Iv='Ivyluna:BAAANQAECgcIBwAAAA==.',
Je='Jemera:BAAANQADCgUIBQAAAA==.',
Ji='Jinkalou:BAAANQADCggIEgABNQAECggILQAYAJYfAA==.Jinsun:BAAANQADCggIEAAAAA==.Jinzun:BAAANQADCgYICQAAAA==.Jiñ:BAAANQADCgUICAAAAA==.',
Ka='Kabbitha:BAAANQADCgEIAQAAAA==.Kahuma:BAAANQAECgEIAQAAAA==.Kalzdemar:BAACNQAFFH8FAAICAAIK6g5IFwCGAAACAAIK6g5IFwCGAAA1AAQKfzYAAwIACgozJFMDAK4DAAIACgozJFMDAK4DAAwABQoFFDGKAPoAAAAA.Karnoviaa:BAAANQADCgUIBQAAAA==.',
Ke='Keldanor:BAAANQADCgQIBAAAAA==.',
Kh='Kheann:BAAANQADCgYIBgAAAA==.Khärdeen:BAAANQAECgEIAQAAAA==.',
Ki='Kimjongheals:BAABNQAECn8kAAIHAAkKFB3QKwC5AgAHAAkKFB3QKwC5AgAAAA==.Kissey:BAAANQADCgEIAQAAAA==.',
Ko='Konjar:BAAANQADCgUIBAAAAA==.',
Ku='Kungpowpoee:BAAANQADCgEIAQABNQADCgIIAgAGAAAAAA==.',
Ky='Kyrak:BAAANQAECgUIEwAAAA==.',
La='Lainey:BAABNQAECn83AAIFAAoKBh79EwCxAgAFAAoKBh79EwCxAgAAAA==.Landocamando:BAAANQAECgQICQAAAA==.',
Le='Lerya:BAABNQAECn8ZAAIZAAoK1gyHFwDRAQAZAAoK1gyHFwDRAQAAAA==.Lessa:BAAANQADCgQIBAAAAA==.Lexnn:BAABNQAECn85AAIaAAkK2RVIFQCbAQAaAAkK2RVIFQCbAQAAAA==.',
Li='Lifedrynker:BAAANQADCgUIBQAAAA==.Lighte:BAABNQAECn8wAAMXAAoKHCEWAwAgAwAXAAoKHCEWAwAgAwAbAAEKAADSxgE1AAAAAA==.',
Lo='Logicx:BAAANQAECgQICAABNQAECgYIGgAQAHEZAA==.Lorin:BAAANQABCgIIAgAAAA==.',
Lu='Lunalia:BAAANQADCgYIBgAAAA==.Lunarrastorm:BAAANQAECgYIDgAAAA==.Lunarìa:BAAANQAECggICQAAAA==.',
['Lê']='Lêssa:BAAANQAECgEIAQAAAA==.',
Ma='Magici:BAAANQAECgUICgAAAA==.Malganor:BAAANQABCgcICgAAAA==.Maraposaa:BAAANQAECggICAAAAA==.Marraud:BAAANQAECgEIAQAAAA==.Mavren:BAAANQAECgUIDQAAAA==.',
Me='Mellesaun:BAAANQADCgMIAwAAAA==.Mephístø:BAABNQAECn8qAAMcAAcKHSPWLADKAgAcAAcKHSPWLADKAgALAAcKpRaSgQCHAQABNQAECgkJLwAIAPwYAA==.Merie:BAAANQABCgMIAwAAAA==.Mewtwo:BAAANQAECgMIAwABNQAFFAcIFgAFAOocAA==.',
Mi='Micali:BAABNQAECn8iAAIPAAkKmRjPdQBCAgAPAAkKmRjPdQBCAgAAAA==.Mithrios:BAAANQADCgcIGgABNQAECggICAAGAAAAAA==.',
Mo='Monoris:BAAANQADCgcICwAAAA==.Moonk:BAAANQADCggIFAAAAA==.Moonsaw:BAACNQAFFH8FAAIdAAMK7hNUDwCWAAAdAAMK7hNUDwCWAAA1AAQKfz0AAh0ACgpsIj8EAJADAB0ACgpsIj8EAJADAAAA.Morgarlan:BAABNQAECn85AAIHAAoKeiGHCgA3AwAHAAoKeiGHCgA3AwAAAA==.',
My='Mysaa:BAAANQAECgIIAgABNQADCgYIBgAGAAAAAA==.',
['Má']='Máxîmús:BAAANQABCgEIAQAAAA==.',
['Mï']='Mïck:BAAANQAECgQIDwAAAA==.',
Na='Narusia:BAAANQADCgQIBAAAAA==.',
Ne='Newt:BAABNQAECn8xAAMaAAoKvx/+BQC5AgAaAAoKvx/+BQC5AgAeAAIKMQRYMwAvAAABNQAFFAEIAQAGAAAAAA==.',
Ni='Ninkasi:BAABNQAECn8aAAIdAAgK5xLoKQDPAQAdAAgK5xLoKQDPAQAAAA==.Nishikki:BAECNQAFFH8bAAIOAAcKgg/mBQDQAQAOAAcKgg/mBQDQAQA1AAQKfz4AAg4ACgpnJYIBAFkDAA4ACgpnJYIBAFkDAAAA.',
No='Noomrats:BAAANQABCgQIAgAAAA==.',
Ny='Nydie:BAABNQAECn8nAAIQAAoKKw+mJwChAQAQAAoKKw+mJwChAQAAAA==.',
Om='Omegon:BAAANQADCgcJBwAAAA==.',
Pa='Pallyrocker:BAAANQAECgIIAgAAAA==.',
Pe='Penumbral:BAAANQAECgQIBwAAAA==.Peterios:BAAANQADCgYIBgABNQAFFAUIFQALAPIeAA==.',
Ph='Phalst:BAAANQABCgMIBQAAAA==.Phibalan:BAAANQAECgEIAgAAAA==.Phyeo:BAAANQADCgcICwABNQAECgoKOgAPANAOAA==.',
Pi='Pixishot:BAAANQADCggIGgAAAA==.',
Pl='Plagueia:BAAANQADCggIDwAAAA==.',
Pu='Pubba:BAAANQAECgYIEQAAAA==.Pubbatis:BAAANQAECgYIBgABNQAECgYIEQAGAAAAAA==.',
['Pá']='Páin:BAAANQABCgEIAQAAAA==.',
Ra='Radiator:BAAANQADCgYIEAABNQAECgQIBwAGAAAAAA==.Raelyndria:BAAANQAECgQICQAAAA==.Rampart:BAAANQADCgMIAwAAAA==.Ratraxx:BAAANQAECgcIDgABNQAECggILQAYAJYfAA==.Ravagen:BAAANQADCgcICwAAAA==.',
Re='Redrogue:BAABNQAECn8ZAAIfAAYKvgVwEwB+AAAfAAYKvgVwEwB+AAAAAA==.Reiko:BAAANQADCgEIAQAAAA==.Renjanà:BAAANQAECgUIBQAAAA==.',
Ri='Riftan:BAABNQAECn8yAAIMAAoKExfiMQBlAgAMAAoKExfiMQBlAgAAAA==.Riviee:BAAANQADCggIGgAAAA==.',
Ro='Roderígo:BAAANQADCgEIAQAAAA==.Rogun:BAABNQAECn8lAAIWAAkKugkzHQAVAQAWAAkKugkzHQAVAQAAAA==.Roredge:BAABNQAECn8tAAMYAAgKlh+ECACiAgAYAAgKlh+ECACiAgAdAAgKtBnZEwCqAQAAAA==.',
Sa='Sarann:BAABNQAECn8kAAMRAAkKDAtgMwCAAQARAAkKDAtgMwCAAQATAAEKLQKztwAqAAAAAA==.',
Sc='Scarypoppins:BAABNQAECn8hAAIDAAoK0BtiFwDiAQADAAoK0BtiFwDiAQAAAA==.',
Se='Seanç:BAAANQABCgYICgAAAA==.',
Sh='Shagster:BAAANQADCgYIBgAAAA==.Shamoomoo:BAAANQADCggICAAAAA==.Sharrell:BAAANQADCgIIAgAAAA==.Sheraania:BAAANQADCgUIBQAAAA==.Shoripan:BAAANQAECgEIAQAAAA==.',
Si='Silvertrees:BAABNQAECn8iAAIRAAcKTAZgMgDaAAARAAcKTAZgMgDaAAAAAA==.',
Sk='Skorpius:BAABNQAECn8WAAIgAAYKTQYH3QAPAQAgAAYKTQYH3QAPAQAAAA==.',
Sl='Slaytanic:BAABNQAECn8cAAMPAAYKGRE26QBJAQAPAAYKGRE26QBJAQAQAAEKAAAefwAeAAAAAA==.Slymick:BAAANQADCgYICwABNQAECgQIDwAGAAAAAA==.',
Sn='Snoka:BAABNQAECn86AAIPAAoK0A6gXgCeAQAPAAoK0A6gXgCeAQAAAA==.',
So='Solora:BAABNQAECn8ZAAIcAAYKbQYTgACeAAAcAAYKbQYTgACeAAAAAA==.',
Sp='Sparklesky:BAAANQADCgYICQAAAA==.',
St='Stankyy:BAAANQAFFAEIAQAAAA==.Starí:BAAANQADCgYIBwAAAA==.Strawry:BAAANQADCgcIDAAAAA==.',
Su='Sunjiwung:BAAANQAECgIIAgAAAA==.Supadin:BAAANQADCgIIAgAAAA==.',
Sy='Sylanan:BAAANQAECgUIBwAAAA==.Syrüs:BAACNQAFFH8FAAIVAAIKdxAVDQCOAAAVAAIKdxAVDQCOAAA1AAQKfy8AAhUACgqyHHUhAJACABUACgqyHHUhAJACAAAA.',
['Sã']='Sãrik:BAAANQADCgMIAwAAAA==.',
Ta='Tasty:BAAANQAECgMIAwABNQAFFAYIEAAWAF4SAA==.',
Te='Tempestfury:BAAANQADCgIIAgAAAA==.Temuraire:BAAANQADCgUIBgAAAA==.Tethyssra:BAAANQADCgYICwABNQAECgQIBwAGAAAAAA==.',
Th='Thalyra:BAABNQAECn8eAAIaAAgKxhrVJAAgAgAaAAgKxhrVJAAgAgAAAA==.Thestar:BAAANQADCgQICgAAAA==.Thirstrap:BAABNQAECn8tAAIVAAkKoBHdIACPAQAVAAkKoBHdIACPAQAAAA==.Thorge:BAABNQAECn8YAAMBAAcKvhC2CAC9AQABAAcKEA+2CAC9AQAFAAYKmg0tuQCRAQAAAA==.Thíngtwo:BAAANQADCgUIBQAAAA==.',
Ti='Tiltawhirl:BAAANQAECgMIBQAAAA==.',
Tw='Twigz:BAAANQABCgYICQAAAA==.',
Un='Unclerukus:BAAANQADCgMIAwAAAA==.Unnserra:BAAANQAECgQIBAABNQAECgkJGgAhAAwNAA==.Unrestraind:BAAANQAECgUIDwAAAA==.Unrêstrained:BAAANQADCgcICQAAAA==.',
Va='Valeska:BAAANQADCgMIAwAAAA==.',
Ve='Vennt:BAACNQAFFH8VAAIWAAcKpR4oBQARAgAWAAcKpR4oBQARAgA1AAQKf0UAAhYACgqjI6kEAIoDABYACgqjI6kEAIoDAAAA.Ventt:BAAANQADCggIDgABNQAFFAcIFQAWAKUeAA==.Veredelyse:BAAANQADCgQIBAABNQAECgkJGgAhAAwNAA==.',
Vu='Vuhdostev:BAAANQAECgMIBAAAAA==.',
Wa='Warpéd:BAAANQABCgQIAwAAAA==.Wartraxx:BAAANQAECgIIAgABNQAECggILQAYAJYfAA==.Wayme:BAAANQADCggIGgAAAA==.',
We='Weewitch:BAAANQADCgcIBwAAAA==.',
Wi='Wizzlord:BAAANQAECgUIBgAAAA==.',
Wo='Woghog:BAAANQAECgYIDQAAAA==.Wotlk:BAAANQADCgQIBQAAAA==.',
Xa='Xahle:BAABNQAECn8uAAQMAAkK9xMsJQBOAQAMAAkK9xMsJQBOAQADAAcKPAcPOQD/AAACAAEK8AJsvwAdAAAAAA==.',
Ya='Yaboì:BAAANQADCgQIBAAAAA==.',
Za='Zareck:BAAANQADCgYIBgAAAA==.',
Ze='Zendayah:BAAANQADCggIDAAAAA==.Zent:BAAANQAECgUIBwAAAA==.Zephie:BAAANQADCgYIBgABNQAECggIGgAdAOcSAA==.',
Zi='Zitillidan:BAACNQAFFH8FAAIVAAIKfA6RDgB4AAAVAAIKfA6RDgB4AAA1AAQKfycAAhUACQpGHDAfAKACABUACQpGHDAfAKACAAE1AAUUAggFAAIA6g4A.',
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
