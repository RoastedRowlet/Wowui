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

local lookup = {'Paladin-Holy','Paladin-Protection','Unknown-Unknown','Shaman-Restoration','Evoker-Devastation','Druid-Balance','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Paladin-Retribution','Monk-Brewmaster','Shaman-Elemental','Priest-Shadow','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Priest-Holy','Warlock-Demonology','Rogue-Assassination','Warrior-Arms','Monk-Windwalker','Priest-Discipline','Warlock-Destruction','DemonHunter-Havoc','Rogue-Subtlety','DemonHunter-Devourer','Mage-Fire','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian','Warrior-Protection','Warrior-Fury','Rogue-Outlaw','Mage-Frost','Druid-Restoration','DemonHunter-Vengeance','Druid-Feral','Monk-Mistweaver',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Ablestract:BAAANQAECgEIAgAAAA==.',
Ac='Acid:BAAANQAECgIIBAAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQAECgQIBwAAAA==.',
Ak='Akamma:BAAANQAECgQIBgAAAA==.Aktzin:BAAANQADCgIIAgAAAA==.',
Al='Alex:BAAANQADCggIDwAAAA==.Algeriono:BAAANQADCgcIFwAAAA==.Alidawn:BAAANQAECgEIAgAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliluna:BAAANQAECgEIAwAAAA==.Alimortis:BAAANQAECgEIAQAAAA==.Alirain:BAAANQAECgEIAwAAAA==.Aliwings:BAABNQAECn8aAAMBAAcKkiRaJADXAgABAAcKkiRaJADXAgACAAYKDQ0rQwDjAAAAAA==.',
Am='Amarokk:BAAANQAECgUICgAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
An='Ancestor:BAAANQADCggIFQAAAA==.Antumblare:BAAANQAECgQIBAABNQAECgIIAgADAAAAAA==.',
Ar='Arioch:BAAANQAECgYIDAAAAA==.',
As='Ashireg:BAAANQAFFAQIAwAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgcIHAAEAMQWAA==.',
Az='Azimondius:BAABNQAECn8iAAIFAAkK5hXnDACSAgAFAAkK5hXnDACSAgAAAA==.Azzix:BAAANQAECgEIAgAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Beefarrows:BAAANQADCgYIBgABNQAECgcIDQADAAAAAA==.Belthora:BAAANQAECgQICQAAAA==.Benry:BAABNQAECn8aAAIGAAgKMRw7JgCeAgAGAAgKMRw7JgCeAgAAAA==.',
Bi='Biblethumpr:BAAANQABCgQIBAAAAA==.Bistroboy:BAAANQAECggIAQAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgcIFwAAAA==.',
Br='Brianjany:BAAANQAECgQICAAAAA==.Browntotem:BAAANQAECgIIBAAAAA==.',
Bu='Bubblehëarth:BAAANQAECgMICwAAAA==.Bubblidan:BAAANQAECgEIAQABNQAECgcIDQADAAAAAA==.Bulgestomper:BAABNQAECn8XAAQHAAkKyBaXPQCvAgAHAAkKyBaXPQCvAgAIAAEKFAOFFAAoAAAJAAEKUwPCmgAiAAAAAA==.Bully:BAAANQAECgYIDQAAAA==.Burbuja:BAAANQAECgMICwAAAA==.Buschgore:BAAANQADCgUIDQAAAA==.',
['Bá']='Bádoink:BAAANQAECgEIAQAAAA==.',
Ca='Calimari:BAAANQADCggICAAAAA==.Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.Caste:BAAANQADCgUIBQAAAA==.Castr:BAAANQAECgQIBQABNQAECgIIBgADAAAAAA==.',
Ce='Celessaria:BAAANQAECgEIAQAAAA==.Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Chamii:BAAANQADCgYIBgAAAA==.Chargeantrot:BAAANQAECgEIAgABNQAECgcICAADAAAAAA==.Cherrypalaid:BAABNQAECn8bAAMBAAkKcxadQQBcAgABAAkKcxadQQBcAgAKAAEKdAG2zwEaAAAAAA==.Chicntrl:BAABNQAECn8VAAILAAcKqBrjDQAXAgALAAcKqBrjDQAXAgAAAA==.',
Cl='Clingy:BAAANQAECgEIAgAAAA==.',
Co='Cobble:BAABNQAECn8VAAIMAAcKmw6UhQCSAQAMAAcKmw6UhQCSAQAAAA==.Colhap:BAABNQAECn8pAAINAAkK5iH7CgAyAwANAAkK5iH7CgAyAwAAAA==.Conjure:BAAANQAECgQIDAAAAA==.Corehammer:BAAANQADCgYIDQAAAA==.',
Cr='Creamsocket:BAAANQAECgQJCgAAAA==.Cru:BAAANQAECgYIDAAAAA==.',
Cu='Culligan:BAABNQAECn8+AAIOAAgKhxvWhgBwAgAOAAgKhxvWhgBwAgAAAA==.Cuttingcrew:BAAANQADCggICAAAAA==.',
Cy='Cygwin:BAABNQAECn8UAAMEAAcKjhmyXQDyAQAEAAcKjhmyXQDyAQAMAAEKAACFNAExAAAAAA==.',
Da='Danaforever:BAAANQADCgIJAgAAAA==.Darklon:BAABNQAECn8aAAMPAAkKgQr9ZQB1AQAPAAgKyQr9ZQB1AQAQAAIKhwfmmABaAAAAAA==.Datmage:BAAANQAECgEIBQAAAA==.',
De='Decomposed:BAAANQADCgMIAwAAAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECggIEAAAAA==.Demunzz:BAAANQADCggIFgAAAA==.Destruction:BAABNQAECn8bAAIRAAgK4wWNbgA3AQARAAgK4wWNbgA3AQAAAA==.Deylei:BAAANQAECgEIAgAAAA==.',
Di='Dithur:BAAANQADCgMJAwAAAA==.Divinespark:BAABNQAECn8bAAISAAgKVRqPRgBQAgASAAgKVRqPRgBQAgAAAA==.',
Do='Doinkbigs:BAABNQAECn8bAAITAAgKxAsTlwCnAQATAAgKxAsTlwCnAQAAAA==.Dolmant:BAAANQAECgUJBQAAAA==.Dooko:BAAANQAECgEIAQAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAAANQAECgMICgABNQAECgcICAADAAAAAA==.',
Dr='Draethno:BAAANQADCgUIBwAAAA==.Drambush:BAAANQADCgMIAwAAAA==.Draqulen:BAAANQAECgEIAwAAAA==.Dredd:BAAANQAECgEIBAAAAA==.Drewsilla:BAAANQADCgIIAgAAAA==.Druidrose:BAAANQAECgYICQAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAAANQAECgcIEAAAAA==.Dustbroom:BAAANQADCgQIBAAAAA==.',
['Dà']='Dàvë:BAAANQAECgQIBAABNQAECggIGgAUAJgPAA==.',
Ea='Eap:BAAANQADCggIEQAAAA==.Eazye:BAABNQAECn8xAAINAAkKsB7KDQAPAwANAAkKsB7KDQAPAwAAAA==.',
Ec='Ectojudge:BAAANQADCgUIBQAAAA==.',
Ed='Edgeffs:BAABNQAECn8bAAIVAAgKzwffuwCCAQAVAAgKzwffuwCCAQAAAA==.',
El='Elentiya:BAABNQAECn8dAAISAAkKcRp2LwCnAgASAAkKcRp2LwCnAgAAAA==.Elphs:BAABNQAECn8UAAIWAAkKxRe/HwAtAgAWAAkKxRe/HwAtAgAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Eriius:BAAANQAECgIIAwAAAA==.',
Et='Ethnodust:BAAANQAECgEIAQAAAA==.',
Fa='Fabri:BAABNQAECn8YAAMXAAYKvCXjCgCUAQASAAYKvCUTYQD6AQAXAAUKDSHjCgCUAQAAAA==.',
Fe='Felorc:BAABNQAECn8YAAITAAYKzxD6uwBQAQATAAYKzxD6uwBQAQAAAA==.Fenton:BAAANQAECgcIEgAAAA==.Fentun:BAABNQAECn8ZAAIBAAgKqiaCCACDAwABAAgKqiaCCACDAwAAAA==.',
Fo='Foulplay:BAAANQAECgUIBQAAAA==.',
Fr='Free:BAAANQAECgEIAgAAAA==.',
Ga='Gabacadabra:BAAANQAECgEIAQAAAA==.Gali:BAAANQABCgcIFAAAAA==.',
Ge='Gelektrael:BAABNQAECn8cAAMYAAgK6xBmDQAhAgAYAAgK6xBmDQAhAgATAAQKOAcCCwGvAAAAAA==.Getchya:BAAANQAECgQIBQABNQAECggIGgAUAJgPAA==.',
Gh='Ghoostt:BAABNQAECn8WAAIZAAkKGAs6PADQAQAZAAkKGAs6PADQAQABNQAFFAQICwAKAKAOAA==.Ghostzz:BAACNQAFFH8LAAIKAAQKoA4OGgDSAAAKAAQKoA4OGgDSAAA1AAQKfy8AAgoACQqjIZcoACIDAAoACQqjIZcoACIDAAAA.',
Gl='Gloríous:BAAANQAECgEIAQABNQAECgcIHAABAK4SAA==.Glzygldiator:BAAANQAECgIIBQAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgAAAA==.',
Go='Goriath:BAAANQAECgMIBQAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAAANQAECgUICwAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAECgYIDQABNQAECgcIEgADAAAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAABNQAECn8VAAIEAAgK9BK/cwCsAQAEAAgK9BK/cwCsAQAAAA==.Haldire:BAAANQAECgEIAwAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haruto:BAAANQADCggICAAAAA==.Haschel:BAAANQADCgcICgAAAA==.',
He='Hexhunts:BAAANQADCgEJAQAAAA==.',
Ho='Holiecow:BAABNQAECn8dAAIBAAYKpwkYqQAsAQABAAYKpwkYqQAsAQAAAA==.Hoshi:BAAANQADCgQIBAABNQAECgkJLgANAGIlAA==.',
Hu='Hurtak:BAAANQAECgUIDgAAAA==.',
Hy='Hycisan:BAABNQAECn8aAAIBAAgKFho+MwCVAgABAAgKFho+MwCVAgAAAA==.Hysteria:BAAANQAECgIIBgAAAA==.',
Ic='Icydoodad:BAAANQAECgUIBQABNQAECggIGgAUAJgPAA==.',
Ik='Ikdutak:BAAANQAECgcIDQAAAA==.',
Il='Illusionwr:BAAANQAECgcICwABNQAECgkKMAAZAEwgAA==.',
Ja='Jagerspell:BAABNQAECn8zAAMaAAkKqCLyBgANAwAaAAgK8CHyBgANAwAUAAQKjCGhSwCNAQAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAAANQAECgcIDgAAAA==.',
Ji='Jibryl:BAAANQADCgMIAwAAAA==.',
Ka='Kaerina:BAAANQAECgUIEgAAAA==.Kanastra:BAABNQAECn8aAAIbAAgKXRTNKQDwAQAbAAgKXRTNKQDwAQABNQAECgkJIgAFAOYVAA==.Karraa:BAAANQADCgYJBgABNQAECgUIEgADAAAAAA==.Kaylib:BAABNQAECn8eAAIcAAgKpA01AwDTAQAcAAgKpA01AwDTAQAAAA==.',
Ke='Kesi:BAAANQAECgMJAwAAAA==.',
Kh='Khaztharion:BAAANQAECgUIBgABNQAECggIGAAdACQgAA==.Khendrick:BAABNQAECn8lAAMCAAgKXhfJIwC/AQACAAcKohjJIwC/AQAKAAcK6BBJuACnAQAAAA==.',
Ki='Kinarra:BAAANQABCgYIBgAAAA==.Kittykatt:BAABNQAECn8nAAIGAAkKihojIgC7AgAGAAkKihojIgC7AgAAAA==.',
Kn='Knowledge:BAABNQAECn8cAAIOAAgKviAsSQDwAgAOAAgKviAsSQDwAgAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECgcIGwAVAOUZAA==.',
Kr='Kraggo:BAABNQAECn8zAAMTAAkKjB29GAAiAwATAAkKjB29GAAiAwAYAAIKPA/iWAB0AAAAAA==.Krakk:BAAANQAECgEIAgAAAA==.Krimzin:BAAANQAFFAEIAQABNQAFFAUIDAAHAHMbAA==.',
['Kí']='Kíllerwolf:BAAANQAECgQICQAAAA==.',
La='Larsen:BAABNQAECn8cAAIMAAgKqBpdPACBAgAMAAgKqBpdPACBAgAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQAECgUIBgAAAA==.',
Le='Leap:BAAANQAECgYIDAAAAA==.Legbah:BAAANQADCgYIEAABNQAECggIGgAUAJgPAA==.',
Li='Lightmare:BAAANQAECgEIAQAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lookadragon:BAAANQAECgUIDQAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAgADAAAAAA==.Lunacy:BAAANQAECgIIBgAAAA==.',
Ly='Lynngosa:BAABNQAECn80AAMeAAkKQxPYHAD8AQAeAAgKxhPYHAD8AQAfAAYKxgxtDgBdAQAAAA==.',
Ma='Magebob:BAAANQAECgYIDgAAAA==.Magisterium:BAAANQAECgQIDAAAAA==.Mario:BAAANQABCgUIBQABNQADCgYIBgADAAAAAA==.Marlfox:BAAANQADCgEIAQAAAA==.Maulware:BAAANQADCgQICwAAAA==.',
Me='Meingaree:BAAANQAECgEIBAAAAA==.Mentery:BAAANQADCgUJBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.Metronome:BAAANQADCgEIAQAAAA==.',
Mi='Mightyguzz:BAABNQAECn8oAAIVAAkKlhEhbgBFAgAVAAkKlhEhbgBFAgAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAABNQAECn8UAAIgAAgKOBsAEABbAgAgAAgKOBsAEABbAgAAAA==.Minimuffn:BAABNQAECn8cAAMPAAgKiBnwQgAMAgAPAAcKgBzwQgAMAgARAAIKtAtUtgBYAAAAAA==.Misericordia:BAABNQAECn8fAAINAAcK/gvCNgBqAQANAAcK/gvCNgBqAQAAAA==.',
['Mø']='Møønchild:BAAANQAECgQIDQAAAA==.',
Na='Nanaish:BAAANQAECgMICQAAAA==.Natë:BAABNQAECn82AAIhAAkKRRaqDQBTAgAhAAkKRRaqDQBTAgAAAA==.',
Ne='Nebakenazzer:BAAANQADCgQIBAABNQAECgQIBgADAAAAAA==.Necrotalon:BAAANQAECgUIBgAAAA==.Nemesia:BAABNQAECn8bAAMVAAcK5Rk1iQABAgAVAAcK5Rk1iQABAgAiAAUKKBCFGAAVAQAAAA==.Neonsunrise:BAABNQAECn8xAAINAAkK1yILBwBnAwANAAkK1yILBwBnAwAAAA==.',
Nh='Nharuna:BAABNQAECn8fAAIHAAgKWBBjfgANAgAHAAgKWBBjfgANAgAAAA==.',
Ni='Nieloriel:BAABNQAECn8VAAIBAAcKeA2FigB5AQABAAcKeA2FigB5AQAAAA==.Nimbus:BAAANQAECgcICwABNQAFFAQICAAMADIWAA==.Niykee:BAABNQAECn8gAAQUAAgKViFhFgDGAgAUAAgKViFhFgDGAgAjAAUKrBgJDgBbAQAaAAEKAAA8UQA3AAAAAA==.',
No='Noboundss:BAABNQAECn8iAAMZAAgKRB26HACwAgAZAAgKmhy6HACwAgAbAAUKLxcSPwBNAQAAAA==.Noztra:BAABNQAECn8yAAMkAAkKsgz6HwDmAAAOAAkKKgqnyADyAQAkAAQKPBT6HwDmAAAAAA==.',
Ns='Nsolant:BAAANQAECgUICwAAAA==.',
Nu='Nubsy:BAAANQAECgEIAQAAAA==.Nuker:BAAANQAECgQIDQAAAA==.Nukron:BAAANQADCggIEAAAAA==.',
Oh='Ohgr:BAABNQAECn8WAAMiAAcKzweeHADeAAAVAAcKzwf4ygBaAQAiAAUK4QWeHADeAAAAAA==.Ohshifty:BAABNQAECn8vAAMGAAkKgBZxIgC5AgAGAAkKgBZxIgC5AgAlAAIK5gGlcwA1AAAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgYIDwAAAA==.',
Or='Orbsicles:BAABNQAECn8dAAMbAAcKURrbIQA5AgAbAAcKURrbIQA5AgAmAAIKlBezJQCIAAAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQAECgEIAQAAAA==.Papitomyrey:BAAANQAECgQIBQABNQAECgkJHgACAOwgAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIGQAAAA==.Pestílence:BAACNQAFFH8JAAIPAAQKihq1DAA+AQAPAAQKihq1DAA+AQA1AAQKfzEAAg8ACQqpJQ8EALIDAA8ACQqpJQ8EALIDAAAA.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQAECgEIAQAAAA==.Pooter:BAABNQAECn8VAAIHAAgKUwUmBwHyAAAHAAgKUwUmBwHyAAAAAA==.Powpow:BAABNQAECn8dAAIaAAkKkBUgDwCGAgAaAAkKkBUgDwCGAgAAAA==.',
Pr='Prejudice:BAABNQAECn8cAAIBAAgKJQ4gdAC4AQABAAgKJQ4gdAC4AQAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAABNQAECn8qAAMlAAkKuA3CKgDEAQAlAAkKuA3CKgDEAQAnAAcKPA1ZGAByAQAAAA==.',
['Pû']='Pûff:BAABNQAECn8mAAIeAAgKCB7HDwCrAgAeAAgKCB7HDwCrAgAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Raiiz:BAAANQAECgMIAwAAAA==.Rainhoof:BAABNQAECn8cAAMnAAgKTBQUFgCVAQAnAAYKqRIUFgCVAQAlAAUK5AkhSQDoAAAAAA==.Ralneth:BAACNQAFFH8hAAIeAAcKkRQ3BAAzAgAeAAcKkRQ3BAAzAgA1AAQKfy0AAh4ACQorGaEWAEsCAB4ACQorGaEWAEsCAAAA.Rapala:BAABNQAECn8dAAITAAcKbhy0aQAcAgATAAcKbhy0aQAcAgAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECgcIHQATAG4cAA==.Raspútin:BAAANQAECgMIAwABNQAECgUICQADAAAAAA==.Ravos:BAAANQABCgIIAgAAAA==.Rawdoinkers:BAAANQAECgIIAwAAAA==.Rawkfice:BAAANQADCggIGAAAAA==.',
Re='Redlefbarg:BAAANQADCgQIBwAAAA==.Renakir:BAAANQADCgEIAQAAAA==.Renly:BAABNQAECn8fAAICAAcK5x12FQBSAgACAAcK5x12FQBSAgAAAA==.Restoral:BAAANQAECgIIAgAAAA==.',
Ri='Riordan:BAABNQAECn8ZAAMHAAcKuSP9LgDeAgAHAAcKuSP9LgDeAgAJAAEKnx3teABXAAAAAA==.Rivvetear:BAAANQADCgIIAgAAAA==.',
Rj='Rjolz:BAACNQAFFH8LAAMPAAQKzSEUCwBaAQAPAAQKzSEUCwBaAQAQAAEKxBOgHABJAAA1AAQKf0EAAw8ACQomJt4CAMgDAA8ACQomJt4CAMgDABAABgqqIGxAAMABAAAA.',
Ro='Roflchopr:BAABNQAECn8mAAIKAAgKOxQAjwACAgAKAAgKOxQAjwACAgAAAA==.Roflkin:BAAANQAECgEIAgAAAA==.',
Sa='Sadcow:BAABNQAECn8pAAIMAAkKmhtEIgD9AgAMAAkKmhtEIgD9AgAAAA==.Sandalfon:BAAANQADCgYICQAAAA==.Sanleron:BAAANQAECgcIEgAAAA==.Sarith:BAAANQADCgcIBwAAAA==.Sarloz:BAAANQAECgEIBgAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQAECgEIAQAAAA==.',
Sh='Shadowclawz:BAAANQAECgEIAQAAAA==.Sharayse:BAAANQAECgEIAQAAAA==.Sharmee:BAAANQAECgcIEAAAAA==.Shiftycapone:BAAANQAECgUIBQAAAA==.Shmelverino:BAAANQAECgMIBQAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shogu:BAABNQAECn8fAAMVAAgKegz/qACyAQAVAAgKVAr/qACyAQAhAAEKDhNtPwA+AAAAAA==.Sháde:BAABNQAECn8VAAMdAAcKIw23CwCqAQAdAAcKIw23CwCqAQAYAAEKGgsheAA1AAAAAA==.',
Si='Simpmother:BAEBNQAECn8mAAITAAgKCRI5ggDcAQATAAgKCRI5ggDcAQAAAA==.',
Sl='Sladepriest:BAAANQAECgMIAwAAAA==.Slingablade:BAABNQAECn8mAAIbAAkKXBmDFgCqAgAbAAkKXBmDFgCqAgAAAA==.',
Sm='Smallfoot:BAAANQADCgEIAQAAAA==.',
Sn='Sniffsniff:BAAANQAECgYICwABNQAFFAUIEQAEABkmAA==.',
So='Solvi:BAAANQAECgUICAAAAA==.Sorá:BAABNQAECn8fAAIVAAgK2SDlLwD8AgAVAAgK2SDlLwD8AgABNQAECgkJMQARAJoZAA==.Soulbrand:BAAANQAECgMIBgAAAA==.',
Sp='Spellz:BAAANQADCgcJDAABNQAECgMIBgADAAAAAA==.',
St='Stabathuh:BAABNQAECn8aAAMUAAgKmA93RQCrAQAUAAcKuA93RQCrAQAaAAcKfAkzKQB3AQAAAA==.Stabnskullz:BAAANQAECgQJBQABNQAECggIEAADAAAAAA==.Stacatta:BAAANQAECgQIBAAAAA==.Stinnky:BAAANQAFFAIJAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECggIGgAUAJgPAA==.Stoopidlock:BAAANQADCggIEwABNQAECggIGgAUAJgPAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECggIGgAUAJgPAA==.Stoopidrood:BAAANQAECgEIAQABNQAECggIGgAUAJgPAA==.Stoopidtroll:BAAANQADCgEIAQABNQAECggIGgAUAJgPAA==.Stoopidwarur:BAAANQAECgQIBAABNQAECggIGgAUAJgPAA==.Stormclaw:BAABNQAECn8aAAImAAcKnAhxFwA0AQAmAAcKnAhxFwA0AQAAAA==.Styne:BAAANQADCggICAABNQAECgkJKQAMAJobAA==.',
Su='Sufiya:BAABNQAECn8YAAIHAAgKewZWqgCsAQAHAAgKewZWqgCsAQAAAA==.Suki:BAABNQAECn8tAAIoAAkKdiAfBgA3AwAoAAkKdiAfBgA3AwAAAA==.Sulfion:BAAANQAECgMIBgAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYIEAAAAA==.',
Sy='Sylveria:BAAANQAECgIIBQAAAA==.Sylvershadow:BAAANQAECgQICAAAAA==.Syphon:BAABNQAECn82AAMmAAkKvyGnAQCJAwAmAAkKvyGnAQCJAwAZAAIKVQH1ogAOAAAAAA==.',
['Sý']='Sýrin:BAAANQAECgEIAgAAAA==.',
Ta='Tandarilada:BAAANQADCgMJAwAAAA==.Tanfer:BAAANQAECgEIAQAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAABNQAECn8mAAIVAAgKnhzNawBLAgAVAAgKnhzNawBLAgAAAA==.Thndrstrmlol:BAAANQAECgEIAQAAAA==.',
Ti='Titanic:BAAANQAECgQIBgAAAA==.',
To='Tomcruise:BAABNQAECn8fAAIKAAgKhR67WQCHAgAKAAgKhR67WQCHAgAAAA==.Totemlyawsum:BAAANQAECgYIDgAAAA==.',
Tr='True:BAAANQAECgQICAAAAA==.',
Tw='Twotone:BAAANQADCgEIAQAAAA==.',
Ul='Ulkthar:BAAANQAECgIIAgABNQAFFAQICAAOAJAKAA==.Ultraillness:BAAANQAECgEIAQAAAA==.Ultrauchuva:BAAANQAECgEIAQAAAA==.',
Un='Unholyhammer:BAAANQABCgMIAQABNQAECggIEAADAAAAAA==.',
Va='Vaiyrnlol:BAACNQAFFH8FAAIEAAIK4BKTIACJAAAEAAIK4BKTIACJAAA1AAQKfx0AAgQACQo0Ht4gAOMCAAQACQo0Ht4gAOMCAAAA.Vanlin:BAABNQAECn8XAAIlAAgKWRoXGwBcAgAlAAgKWRoXGwBcAgAAAA==.',
Ve='Vexxdr:BAABNQAECn8pAAMlAAkKwBIkIQAbAgAlAAkKwBIkIQAbAgAGAAYKyhfLSwCwAQABNQAECgkJLQAEAHsgAA==.Vexxs:BAABNQAECn8tAAMEAAkKeyDxDwBDAwAEAAkKeyDxDwBDAwAMAAMKxhTj5wDBAAAAAA==.',
Vo='Voidsuzu:BAABNQAECn8pAAIbAAkKmRbnHABqAgAbAAkKmRbnHABqAgAAAA==.Vormedicus:BAAANQAECgUICQAAAA==.',
Vs='Vsaguzz:BAAANQADCgEJAQABNQAECgkJKAAVAJYRAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgQICwAAAA==.',
Wa='Waroo:BAAANQAECgEIAQAAAA==.',
We='Werewolf:BAAANQADCggICgAAAA==.',
Wi='Wickïdus:BAAANQABCggIEAAAAA==.Windhoof:BAAANQADCgQJBAAAAA==.',
Wu='Wulffric:BAAANQAECgMIDAAAAA==.',
Xa='Xaphelion:BAAANQAECgEIAQAAAA==.Xazio:BAABNQAECn8oAAICAAkKfRKFIADdAQACAAkKfRKFIADdAQAAAA==.',
Yi='Yiang:BAABNQAECn8WAAIWAAcKChs2JQD2AQAWAAcKChs2JQD2AQAAAA==.',
Yl='Ylndrysa:BAABNQAECn9EAAIlAAkKgBVQGAB4AgAlAAkKgBVQGAB4AgAAAA==.',
Ze='Zedrock:BAABNQAECn8gAAMkAAgK7B9nBQC7AgAkAAgK7B9nBQC7AgAOAAEKGgslwgE1AAAAAA==.Zeezu:BAAANQAECgMIAwAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAAANQAECgUICwAAAA==.Zhitolight:BAAANQAECgEIBwABNQAFFAIIAgADAAAAAA==.',
Zu='Zuro:BAABNQAECn8ZAAIHAAcK8AdjvQCDAQAHAAcK8AdjvQCDAQAAAA==.',
['Ðø']='Ðønsý:BAAANQADCgEIAQAAAA==.',
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
