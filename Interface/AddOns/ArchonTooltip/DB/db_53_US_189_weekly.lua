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

local lookup = {'Paladin-Holy','Paladin-Protection','Unknown-Unknown','Shaman-Restoration','Evoker-Devastation','Druid-Balance','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Rogue-Assassination','Paladin-Retribution','Monk-Brewmaster','Shaman-Elemental','Priest-Shadow','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Priest-Holy','Warlock-Demonology','Warrior-Arms','Monk-Windwalker','Warlock-Destruction','DemonHunter-Havoc','Rogue-Subtlety','Shaman-Enhancement','DemonHunter-Devourer','Mage-Fire','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Druid-Guardian','Warrior-Protection','Warrior-Fury','Rogue-Outlaw','Druid-Restoration','DemonHunter-Vengeance','Druid-Feral','Monk-Mistweaver',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Ablestract:BAAANQAECgEIAgAAAA==.',
Ac='Acid:BAAANQAECgIIBAAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQAECgQICQAAAA==.',
Ak='Akamma:BAAANQAECgUICgAAAA==.Aktzin:BAAANQADCgIIAgAAAA==.',
Al='Alex:BAAANQADCggIDwAAAA==.Algeriono:BAAANQADCgcIFwAAAA==.Alidawn:BAAANQAECgEIAgAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliluna:BAAANQAECgEIAwAAAA==.Alimortis:BAAANQAECgEIAQAAAA==.Alirain:BAAANQAECgEIAwAAAA==.Aliwings:BAABNQAECn8aAAMBAAcKkiTNJADXAgABAAcKkiTNJADXAgACAAYKDQ3tQwDjAAAAAA==.',
Am='Amarokk:BAAANQAECgUICwAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
An='Ancestor:BAAANQADCggIFQAAAA==.Antumblare:BAAANQAECgUIBgABNQAECgIIAgADAAAAAA==.',
Ar='Arioch:BAAANQAECgYIDAAAAA==.',
As='Ashireg:BAAANQAFFAMIAwAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgcIIAAEAMQWAA==.',
Az='Azimondius:BAABNQAECn8lAAIFAAoKeBcJDQCSAgAFAAoKeBcJDQCSAgAAAA==.Azzix:BAAANQAECgEIAgAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Beefarrows:BAAANQADCgYIBgABNQAECgcIDQADAAAAAA==.Belthora:BAAANQAECgQICQAAAA==.Benry:BAABNQAECn8aAAIGAAgKMRy+JgCeAgAGAAgKMRy+JgCeAgAAAA==.',
Bi='Biblethumpr:BAAANQABCgQIBAAAAA==.Bistroboy:BAAANQAECggIAQAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgcIFwAAAA==.',
Br='Brianjany:BAAANQAECgQICAAAAA==.Browntotem:BAAANQAECgIIBAAAAA==.',
Bu='Bubblehëarth:BAAANQAECgMICwAAAA==.Bubblidan:BAAANQAECgEIAQABNQAECgcIDQADAAAAAA==.Bulgestomper:BAABNQAECn8aAAQHAAkKgBe7PgCuAgAHAAkKgBe7PgCuAgAIAAEKFAPCFAAoAAAJAAEKUwMDnQAiAAAAAA==.Bully:BAAANQAECgYIDQAAAA==.Burbuja:BAAANQAECgMIDAAAAA==.Buschgore:BAAANQADCggIFAAAAA==.',
['Bá']='Bádoink:BAAANQAECgEIAQAAAA==.',
Ca='Calimari:BAAANQADCggICAAAAA==.Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.Caste:BAAANQADCgcIDQABNQAECggIIQAKAJgPAA==.Castr:BAAANQAECgQIBQABNQAECgIIBgADAAAAAA==.',
Ce='Celessaria:BAAANQAECgEIAQAAAA==.Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Chamii:BAAANQADCgYIBgAAAA==.Chargeantrot:BAAANQAECgEIAgABNQAECggIDQADAAAAAA==.Cherrypalaid:BAABNQAECn8bAAMBAAkKcxYsQgBcAgABAAkKcxYsQgBcAgALAAEKdAFp1gEaAAAAAA==.Chicntrl:BAABNQAECn8XAAIMAAcKqBoIDgAWAgAMAAcKqBoIDgAWAgAAAA==.',
Cl='Clingy:BAAANQAECgEIAgAAAA==.',
Co='Cobble:BAABNQAECn8aAAINAAgKSw2qOQDdAAANAAgKSw2qOQDdAAAAAA==.Colhap:BAABNQAECn8rAAIOAAkK5iEmCwAxAwAOAAkK5iEmCwAxAwAAAA==.Conjure:BAAANQAECggIEgAAAA==.Corehammer:BAAANQADCgYIDQAAAA==.',
Cr='Creamsocket:BAAANQAECgQJCgAAAA==.Cru:BAAANQAECgcIDAAAAA==.',
Cu='Culligan:BAABNQAECn9IAAIPAAoKIRdOEgDUAQAPAAoKIRdOEgDUAQAAAA==.Cuttingcrew:BAAANQADCggICAAAAA==.',
Cy='Cygwin:BAABNQAECn8UAAMEAAcKjhnJXgDyAQAEAAcKjhnJXgDyAQANAAEKAADaOAExAAAAAA==.',
Da='Danaforever:BAAANQADCgIJAgAAAA==.Darklon:BAABNQAECn8aAAMQAAkKgQr0ZgB1AQAQAAgKyQr0ZgB1AQARAAIKhwcYnABaAAAAAA==.Datmage:BAAANQAECgEIBQAAAA==.',
De='Decomposed:BAAANQADCgMIAwAAAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECggIEAAAAA==.Demunzz:BAAANQADCggIFgAAAA==.Destruction:BAABNQAECn8dAAISAAgK4wVpbwA3AQASAAgK4wVpbwA3AQAAAA==.Deylei:BAAANQAECgIIAgAAAA==.',
Di='Dithur:BAAANQADCgMIAwAAAA==.Divinespark:BAABNQAECn8dAAITAAgKfRq+RwBPAgATAAgKfRq+RwBPAgAAAA==.',
Do='Doinkbigs:BAABNQAECn8iAAIUAAgK9wskLgA+AQAUAAgK9wskLgA+AQAAAA==.Dolmant:BAAANQAECgUJBQAAAA==.Dooko:BAAANQAECgEIAQAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAAANQAECgMICgABNQAECggIDQADAAAAAA==.',
Dr='Draethno:BAAANQADCgUIBwAAAA==.Drambush:BAAANQADCgMIAwAAAA==.Draqulen:BAAANQAECgEIAwAAAA==.Dredd:BAAANQAECgEIBAAAAA==.Drewsilla:BAAANQADCgIIAgAAAA==.Druidrose:BAAANQAECgUIDgAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAAANQAECggIEgAAAA==.Dustbroom:BAAANQADCgQIBAAAAA==.',
['Dà']='Dàvë:BAAANQAECgQIBAABNQAECggIIQAKAJgPAA==.',
Ea='Eap:BAAANQADCggIEQAAAA==.Eazye:BAABNQAECn84AAIOAAoKEBv7DQAOAwAOAAoKEBv7DQAOAwAAAA==.',
Ec='Ectojudge:BAAANQADCgUIBQAAAA==.',
Ed='Edgeffs:BAABNQAECn8dAAIVAAgKzwf6vQCCAQAVAAgKzwf6vQCCAQAAAA==.',
El='Elentiya:BAABNQAECn8eAAITAAoKpRk4MACnAgATAAoKpRk4MACnAgAAAA==.Elphs:BAABNQAECn8UAAIWAAkKxRciIAAtAgAWAAkKxRciIAAtAgAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Eriius:BAAANQAECgQIBAAAAA==.',
Et='Ethnodust:BAAANQAECgEIAQAAAA==.',
Fa='Faarâm:BAAANQAECgMIAgAAAA==.',
Fe='Felorc:BAABNQAECn8YAAIUAAYKzxA7vgBQAQAUAAYKzxA7vgBQAQAAAA==.Fenton:BAABNQAECn8YAAITAAkK9iAXEQDuAQATAAkK9iAXEQDuAQAAAA==.Fentun:BAABNQAECn8cAAIBAAkKoiajCACDAwABAAkKoiajCACDAwAAAA==.',
Fo='Foulplay:BAAANQAECgUIBQAAAA==.',
Fr='Free:BAAANQAECgEIAgAAAA==.',
Ga='Gabacadabra:BAAANQAECgEIAQAAAA==.Gali:BAAANQABCgcIFAAAAA==.',
Ge='Gelektrael:BAABNQAECn8eAAMXAAgKrhF7DQAhAgAXAAgKrhF7DQAhAgAUAAQKOAdMDgGvAAAAAA==.Getchya:BAAANQAECgQIBQABNQAECggIIQAKAJgPAA==.',
Gh='Ghoostt:BAABNQAECn8XAAIYAAkKGAvyPADQAQAYAAkKGAvyPADQAQABNQAFFAUIEAALAOUVAA==.Ghostzz:BAACNQAFFH8QAAILAAUK5RXkBQAAAQALAAUK5RXkBQAAAQA1AAQKfzgAAgsACgp6IX4HAG0CAAsACgp6IX4HAG0CAAAA.',
Gl='Gloríous:BAAANQAECgEIAQABNQAECgcIHwABAK4SAA==.Glzygldiator:BAAANQAECgIIBQAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgAAAA==.',
Go='Goriath:BAAANQAECgQIBQAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAAANQAECgcIDAAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAECgYIDQABNQAECgcIEgADAAAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAABNQAECn8VAAIEAAgK9BIOdQCsAQAEAAgK9BIOdQCsAQAAAA==.Haldire:BAAANQAECgEIAwAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haruto:BAAANQADCggICAAAAA==.Haschel:BAAANQADCgcICgAAAA==.',
He='Hexhunts:BAAANQADCgEJAQAAAA==.',
Ho='Holiecow:BAABNQAECn8iAAIBAAYKpwn5SgDMAAABAAYKpwn5SgDMAAAAAA==.Hoshi:BAAANQADCgQIBAABNQAECgkJLgAOAGIlAA==.',
Hu='Hurtak:BAAANQAECgYIDwAAAA==.',
Hy='Hycisan:BAABNQAECn8hAAIBAAgKix0gCQAyAgABAAgKix0gCQAyAgAAAA==.Hysteria:BAAANQAECgQICgAAAA==.',
Ic='Icon:BAAANQADCgcIBwAAAA==.Icydoodad:BAAANQAECgUIBQABNQAECggIIQAKAJgPAA==.',
Ik='Ikdutak:BAAANQAECgcIDQAAAA==.',
Il='Illusionwr:BAAANQAECgcIDAABNQAECgoKNAAYACUfAA==.',
Ja='Jagerspell:BAABNQAECn89AAMZAAoKOyLiBAD3AQAZAAkK5x/iBAD3AQAKAAQKfCTlJAC+AAAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAAANQAECgcIDwAAAA==.',
Ji='Jibryl:BAAANQADCgMIAwAAAA==.',
Ka='Kaerina:BAABNQAECn8XAAMaAAYKZgltIABYAQAaAAYKZgltIABYAQAEAAMKpQE/BgFcAAAAAA==.Kanastra:BAABNQAECn8iAAIbAAkK+hPQBADMAQAbAAkK+hPQBADMAQABNQAECgoKJQAFAHgXAA==.Karraa:BAAANQADCgYJBgABNQAECgYIFwAaAGYJAA==.Kaylib:BAABNQAECn8kAAIcAAgKQg47AwDTAQAcAAgKQg47AwDTAQAAAA==.',
Ke='Kesi:BAAANQAECgMJAwAAAA==.',
Kh='Khaztharion:BAAANQAECgcIDAABNQAECggIGAAdACQgAA==.Khendrick:BAABNQAECn8uAAMLAAkKWhbXIACgAQACAAgKjBVIJAC+AQALAAgKLhHXIACgAQAAAA==.',
Ki='Kinarra:BAAANQABCgYIBgAAAA==.Kittykatt:BAABNQAECn8oAAIGAAoKBhqUIgC7AgAGAAoKBhqUIgC7AgAAAA==.',
Kn='Knowledge:BAABNQAECn8dAAIPAAgKviBDSgDtAgAPAAgKviBDSgDtAgAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECgcIIQAVAOUZAA==.',
Kr='Kraggo:BAABNQAECn87AAMUAAoKrR5gCgACAgAUAAoKrR5gCgACAgAXAAIKPA9dWQB0AAAAAA==.Krakk:BAAANQAECgEIAgAAAA==.Krimzin:BAAANQAFFAEIAQABNQAFFAYIDQAHAN8VAA==.',
['Kí']='Kíllerwolf:BAAANQAECgUIDgAAAA==.',
La='Larsen:BAABNQAECn8eAAINAAgKqBpCPQCBAgANAAgKqBpCPQCBAgAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQAECgYIBwAAAA==.',
Le='Leap:BAAANQAECggIDgAAAA==.Legbah:BAAANQADCgYIEAABNQAECggIIQAKAJgPAA==.',
Li='Lightmare:BAAANQAECgEIAQAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lookadragon:BAAANQAECgUIDQAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAgADAAAAAA==.Lunacy:BAAANQAECgUICgAAAA==.',
Ly='Lynngosa:BAABNQAECn84AAMeAAoK8xH3HAD8AQAeAAkKQxL3HAD8AQAfAAYKxgyTDgBdAQAAAA==.',
Ma='Magebob:BAABNQAECn8UAAMPAAcKwgqITQAgAQAPAAcKwgqITQAgAQAgAAEKAAB9UQAkAAAAAA==.Magisterium:BAAANQAECgUIEQAAAA==.Marlfox:BAAANQADCgEIAQAAAA==.Maulware:BAAANQADCgQICwAAAA==.',
Me='Meingaree:BAAANQAECgEIBAAAAA==.Mentery:BAAANQADCgUJBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.Metronome:BAAANQADCgEIAQAAAA==.',
Mi='Mightyguzz:BAABNQAECn8uAAIVAAoKVhAqPwAmAQAVAAoKVhAqPwAmAQAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAABNQAECn8UAAIhAAgKOBtBEABcAgAhAAgKOBtBEABcAgAAAA==.Minimuffn:BAABNQAECn8dAAMQAAgKiBm9QwAMAgAQAAcKgBy9QwAMAgASAAIKtAvutwBYAAAAAA==.Misericordia:BAABNQAECn8kAAIOAAcKVg1+EwDvAAAOAAcKVg1+EwDvAAAAAA==.',
['Mø']='Møønchild:BAAANQAECgUIDQAAAA==.',
Na='Nafega:BAAANQABCgUICAAAAA==.Nanaish:BAAANQAECgMICQAAAA==.Natë:BAABNQAECn83AAIiAAoK/hTfDQBSAgAiAAoK/hTfDQBSAgAAAA==.',
Ne='Nebakenazzer:BAAANQADCgQIBAABNQAECgUICgADAAAAAA==.Necrotalon:BAAANQAECgYIBwAAAA==.Nemesia:BAABNQAECn8hAAMVAAcK5RnLLgBRAQAVAAcK5RnLLgBRAQAjAAUKKBC1GAAVAQAAAA==.Neonsunrise:BAABNQAECn84AAIOAAoKxR44BwBnAwAOAAoKxR44BwBnAwAAAA==.',
Nh='Nharuna:BAABNQAECn8hAAIHAAgKWBBagAAMAgAHAAgKWBBagAAMAgAAAA==.',
Ni='Nieloriel:BAABNQAECn8YAAIBAAkKBA3IiwB5AQABAAkKBA3IiwB5AQAAAA==.Nimbus:BAAANQAECggIDwABNQAFFAcIGgANADwXAA==.Niykee:BAABNQAECn8hAAQKAAkK/B3SFgDGAgAKAAkK/B3SFgDGAgAkAAUKrBgZDgBcAQAZAAEKAACTUgA3AAAAAA==.',
No='Noboundss:BAABNQAECn8kAAMYAAkKbBtGHQCvAgAYAAkK2hpGHQCvAgAbAAUKLxfXPwBNAQAAAA==.Noztra:BAABNQAECn84AAMgAAoKYQtkIADmAAAPAAoKKglaywDvAQAgAAQKPBRkIADmAAAAAA==.',
Ns='Nsolant:BAAANQAECgcIDAAAAA==.',
Nu='Nubsy:BAAANQAECgEIAQAAAA==.Nuker:BAAANQAECgQIEQAAAA==.',
Oh='Ohgr:BAABNQAECn8WAAMjAAcKzwfwHADeAAAVAAcKzwdFzQBaAQAjAAUK4QXwHADeAAAAAA==.Ohshifty:BAABNQAECn87AAMGAAoKNBcnEABYAQAGAAoKNBcnEABYAQAlAAIK5gGIdQA1AAAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgYIDwAAAA==.',
Or='Orbsicles:BAABNQAECn8fAAMbAAgKpxo0IgA5AgAbAAgKpxo0IgA5AgAmAAIKlBc5JgCIAAAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQAECgIIAwAAAA==.Papitomyrey:BAAANQAECgQIBgABNQAECgoKIQACANkeAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIGQAAAA==.Pestílence:BAACNQAFFH8KAAIQAAQKihroDAA+AQAQAAQKihroDAA+AQA1AAQKfzEAAhAACQqpJR4EALIDABAACQqpJR4EALIDAAAA.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQAECgEIAQAAAA==.Pooter:BAABNQAECn8VAAIHAAgKUwUmCgHyAAAHAAgKUwUmCgHyAAAAAA==.Powpow:BAABNQAECn8kAAIZAAoKchQjDAB9AQAZAAoKchQjDAB9AQAAAA==.',
Pr='Prejudice:BAABNQAECn8eAAIBAAgK4g4ydQC4AQABAAgK4g4ydQC4AQAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAACNQAFFH8FAAIlAAIK9gV6CAB4AAAlAAIK9gV6CAB4AAA1AAQKfy4AAyUACgqDDTErAMQBACUACgqDDTErAMQBACcABwo8DcMYAHABAAAA.',
['Pû']='Pûff:BAABNQAECn8pAAIeAAkKGx7pDwCrAgAeAAkKGx7pDwCrAgAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Raiiz:BAAANQAECgMIAwAAAA==.Rainhoof:BAABNQAECn8eAAMnAAgKTBR3FgCTAQAnAAYKqRJ3FgCTAQAlAAUK5An/SQDoAAAAAA==.Ralneth:BAACNQAFFH8iAAIeAAcKkRRjBAAzAgAeAAcKkRRjBAAzAgA1AAQKfzEAAh4ACgoRGMoWAEsCAB4ACgoRGMoWAEsCAAAA.Randomtask:BAAANQADCgcIBwAAAA==.Rapala:BAABNQAECn8dAAIUAAcKbhx6awAbAgAUAAcKbhx6awAbAgAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECgcIHQAUAG4cAA==.Raspútin:BAAANQAECgMIAwABNQAECgYICQADAAAAAA==.Ravos:BAAANQABCgIIAgAAAA==.Rawdoinkers:BAAANQAECgIIAwAAAA==.Rawkfice:BAAANQADCggIHAAAAA==.',
Re='Redlefbarg:BAAANQADCgQIBwAAAA==.Renakir:BAAANQADCgEIAQAAAA==.Renly:BAABNQAECn8hAAICAAgKCRzCFQBRAgACAAgKCRzCFQBRAgAAAA==.Restoral:BAAANQAECgIIAgAAAA==.',
Ri='Riordan:BAABNQAECn8bAAMHAAgKeyMlMADcAgAHAAgKeyMlMADcAgAJAAEKnx2MegBXAAAAAA==.Rivvetear:BAAANQADCgIIAgAAAA==.',
Rj='Rjolz:BAACNQAFFH8RAAQQAAYK2CC7AwDLAAAQAAUK2CC7AwDLAAASAAMKAxW4CwCcAAARAAIKxBNwHQBJAAA1AAQKf0sABBAACgrXJeYCAMgDABAACQomJuYCAMgDABEACQoXHxQCAJ0CABIAAgquIzhFAG0AAAAA.',
Ro='Roflchopr:BAABNQAECn8tAAILAAkKKRMnTQAqAQALAAkKKRMnTQAqAQAAAA==.Roflkin:BAAANQAECgUIBgAAAA==.',
Sa='Sadcow:BAABNQAECn8vAAINAAoKFhu/DACsAQANAAoKFhu/DACsAQAAAA==.Sandalfon:BAAANQADCgYICQAAAA==.Sanleron:BAABNQAECn8YAAMCAAgK+Ba5DgAfAQALAAgK7RXYoADgAQACAAUKzQ25DgAfAQAAAA==.Sarith:BAAANQADCgcIBwAAAA==.Sarloz:BAAANQAECgEIBgAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQAECgEIAQAAAA==.',
Sh='Shadowclawz:BAAANQAECgEIAQAAAA==.Sharayse:BAAANQAECgEIAQAAAA==.Sharmee:BAAANQAECggIEwAAAA==.Shiftycapone:BAAANQAECgcIDwAAAA==.Shmelverino:BAAANQAECgUICQAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shogu:BAABNQAECn8iAAMVAAgKegzsqgCyAQAVAAgKVArsqgCyAQAiAAEKDhNRQAA+AAAAAA==.Sháde:BAABNQAECn8VAAMdAAcKIw3LCwCqAQAdAAcKIw3LCwCqAQAXAAEKGgu+eAA1AAAAAA==.',
Si='Simpmother:BAEBNQAECn8pAAIUAAkKJBA6hADbAQAUAAkKJBA6hADbAQAAAA==.',
Sk='Skadie:BAAANQADCgYIBgABNQAECgoKOAAeAPMRAA==.',
Sl='Sladepriest:BAAANQAECgMIAwAAAA==.Slingablade:BAABNQAECn8tAAMbAAoK3xrGFgCqAgAbAAoK3xrGFgCqAgAmAAMKdQhxFABPAAAAAA==.',
Sm='Smallfoot:BAAANQADCgEIAQAAAA==.',
Sn='Sniffsniff:BAAANQAFFAMIAgABNQAFFAUIEwAEABkmAA==.',
So='Solvi:BAAANQAECgUICwAAAA==.Sorá:BAABNQAECn8hAAIVAAkKFCHNMAD8AgAVAAkKFCHNMAD8AgABNQAECgoKOQASAPAXAA==.Soulbrand:BAAANQAECgMIBgAAAA==.',
Sp='Spellz:BAAANQADCgcIDAABNQAECgUIBgADAAAAAA==.',
St='Stabathuh:BAABNQAECn8hAAMKAAgKmA/zDABgAQAZAAcKfAmrKQB3AQAKAAgK8g7zDABgAQAAAA==.Stabnskullz:BAAANQAECgQJBQABNQAECggIEAADAAAAAA==.Stacatta:BAAANQAECgQIBAAAAA==.Stinnky:BAAANQAFFAIIAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECggIIQAKAJgPAA==.Stoopidlock:BAAANQADCggIGwABNQAECggIIQAKAJgPAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECggIIQAKAJgPAA==.Stoopidrood:BAAANQAECgQIBQABNQAECggIIQAKAJgPAA==.Stoopidtroll:BAAANQADCgEIAQABNQAECggIIQAKAJgPAA==.Stoopidwarur:BAAANQAECgYICQABNQAECggIIQAKAJgPAA==.Stormclaw:BAABNQAECn8cAAImAAgK4weyFwA0AQAmAAgK4weyFwA0AQAAAA==.Styne:BAAANQADCggICAABNQAECgoKLwANABYbAA==.',
Su='Sufiya:BAABNQAECn8ZAAIHAAgKewanrACrAQAHAAgKewanrACrAQAAAA==.Suki:BAABNQAECn8zAAIoAAoKdSA6BgA3AwAoAAoKdSA6BgA3AwAAAA==.Sulfion:BAAANQAECgUIBgAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYIEAAAAA==.',
Sy='Sylveria:BAAANQAECgIIBQAAAA==.Sylvershadow:BAAANQAECgUIDQAAAA==.Syphon:BAABNQAECn9AAAMmAAoKDiFyAADLAgAmAAoKDiFyAADLAgAYAAIKVQGApQAOAAAAAA==.',
['Sý']='Sýrin:BAAANQAECgEIAgAAAA==.',
Ta='Tandarilada:BAAANQADCgMJAwAAAA==.Tanfer:BAAANQAECgEIAQAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAABNQAECn8pAAIVAAkKQRpSbQBKAgAVAAkKQRpSbQBKAgAAAA==.Thndrstrmlol:BAAANQAECgEIAQAAAA==.',
Ti='Titanic:BAAANQAECgYICAAAAA==.',
To='Tomcruise:BAABNQAECn8hAAILAAkKpxulWwCFAgALAAkKpxulWwCFAgAAAA==.Totemlyawsum:BAAANQAECgYIDgAAAA==.',
Tr='True:BAAANQAECgQICAAAAA==.',
Tw='Twotone:BAAANQADCgEIAQAAAA==.',
Ul='Ulkthar:BAAANQAECgUIBgABNQAFFAQICAAPAJAKAA==.Ultraillness:BAAANQAECgEIAQAAAA==.Ultrauchuva:BAAANQAECgEIAQAAAA==.',
Un='Unholyhammer:BAAANQABCgMIAQABNQAECggIEAADAAAAAA==.',
Va='Vacunamatata:BAAANQAECgQIBAAAAA==.Vaiyrnlol:BAACNQAFFH8HAAIEAAIKjBetDQCkAAAEAAIKjBetDQCkAAA1AAQKfyEAAgQACgoLHWIhAOMCAAQACgoLHWIhAOMCAAAA.Vanlin:BAABNQAECn8ZAAIlAAgKGRt0GwBcAgAlAAgKGRt0GwBcAgAAAA==.',
Ve='Vexxdr:BAABNQAECn8wAAMlAAkKsxN5IQAcAgAlAAkKsxN5IQAcAgAGAAcKthjCEQBLAQABNQAECgoKNQAEAJkgAA==.Vexxs:BAABNQAECn81AAMEAAoKmSAMAwDyAgAEAAoKmSAMAwDyAgANAAMKxhTv6gDBAAAAAA==.',
Vo='Voidsuzu:BAABNQAECn8vAAIbAAoKZhRIHQBqAgAbAAoKZhRIHQBqAgAAAA==.Vormedicus:BAAANQAECgYICQAAAA==.',
Vs='Vsaguzz:BAAANQADCggICQABNQAECgoKLgAVAFYQAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgQICwAAAA==.',
Wa='Waroo:BAAANQAECgEIAQAAAA==.',
We='Werewolf:BAAANQADCggICgAAAA==.',
Wi='Wickïdus:BAAANQABCggIEAAAAA==.Windhoof:BAAANQADCgQJBAAAAA==.',
Wu='Wulffric:BAAANQAECgMIDQAAAA==.',
Xa='Xaphelion:BAAANQAECgEIAQAAAA==.Xazio:BAABNQAECn8uAAICAAoKIRITDQAyAQACAAoKIRITDQAyAQAAAA==.',
Yi='Yiang:BAABNQAECn8WAAIWAAcKChujJQD2AQAWAAcKChujJQD2AQAAAA==.',
Yl='Ylndrysa:BAABNQAECn9MAAIlAAoK5BeqGAB5AgAlAAoK5BeqGAB5AgAAAA==.',
Ze='Zedrock:BAABNQAECn8kAAMgAAoKMh1zBQC6AgAgAAoKMh1zBQC6AgAPAAIKWws04ABEAAAAAA==.Zeezu:BAAANQAECgMIAwAAAA==.Zekodian:BAAANQADCgQIBAAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAAANQAECgcIDAAAAA==.Zhitolight:BAAANQAECgQICQABNQAFFAIIAgADAAAAAA==.',
Zu='Zuro:BAABNQAECn8bAAIHAAgKkwcTwACDAQAHAAgKkwcTwACDAQAAAA==.',
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
