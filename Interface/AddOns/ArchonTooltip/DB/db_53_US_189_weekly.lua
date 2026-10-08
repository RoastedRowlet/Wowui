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

local lookup = {'Shaman-Restoration','Evoker-Devastation','Unknown-Unknown','Druid-Balance','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Priest-Holy','Warrior-Arms','Priest-Discipline','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','Warlock-Affliction','Hunter-BeastMastery','Shaman-Elemental','Evoker-Preservation','Warrior-Protection','Warrior-Fury','Rogue-Outlaw','Mage-Frost','Druid-Restoration','DemonHunter-Vengeance','Paladin-Protection','Druid-Feral','Monk-Mistweaver',}
local provider = {region='US',realm='Shadowmoon',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Ablestract:BAAANQADCgUIBQAAAA==.',
Ac='Acid:BAAANQAECgEIAgAAAA==.',
Ae='Aeniel:BAAANQADCgQICAAAAA==.',
Ai='Aiselyn:BAAANQAECgQIAwAAAA==.',
Ak='Akamma:BAAANQAECgQIBAAAAA==.Aktzin:BAAANQADCgIIAgAAAA==.',
Al='Alex:BAAANQADCggIDwAAAA==.Algeriono:BAAANQADCgcIFwAAAA==.Alidusk:BAAANQABCgIIAgAAAA==.Aliwings:BAAANQAECgYIEwAAAA==.',
Am='Amarokk:BAAANQAECgMIBQAAAA==.Ameliae:BAAANQADCgEIAQAAAA==.',
An='Ancestor:BAAANQADCgUIDQAAAA==.',
Ar='Arioch:BAAANQAECgQIBAAAAA==.',
As='Ashireg:BAAANQAFFAMIAwAAAA==.Asukasoryu:BAAANQADCgIIAgAAAA==.',
At='Atheowlann:BAAANQADCgUICQABNQAECgcIGwABAMQWAA==.',
Az='Azimondius:BAABNQAECoEfAAICAAkK/xeECwCYAgACAAkK/xeECwCYAgAAAA==.',
Ba='Balefire:BAAANQADCgQIBAAAAA==.',
Be='Beefarrows:BAAANQADCgYIBgABNQAECgYIBgADAAAAAA==.Belthora:BAAANQAECgQICQAAAA==.Benry:BAABNQAECoEaAAIEAAgKRh05IACtAgAEAAgKRh05IACtAgAAAA==.',
Bi='Biblethumpr:BAAANQABCgQIBAAAAA==.',
Bl='Blksntatitdk:BAAANQADCgUIBQAAAA==.Bluteddybear:BAAANQABCgYIEQAAAA==.',
Br='Brianjany:BAAANQAECgQIBwAAAA==.Browntotem:BAAANQADCgUIBQAAAA==.',
Bu='Bubblehëarth:BAAANQAECgMIBgAAAA==.Bulgestomper:BAAANQAECgYIDQAAAA==.Bully:BAAANQAECgYICwAAAA==.Burbuja:BAAANQAECgMIBgAAAA==.Buschgore:BAAANQADCgQICQAAAA==.',
['Bá']='Bádoink:BAAANQADCgcIBwAAAA==.',
Ca='Careco:BAAANQADCgYICwAAAA==.Casperevoker:BAAANQADCgIIAgAAAA==.Caspêr:BAAANQADCgIIAgAAAA==.Castr:BAAANQAECgQIBAABNQAECgIIBAADAAAAAA==.',
Ce='Celessaria:BAAANQADCgYIEgAAAA==.Celzara:BAAANQADCgIIAgAAAA==.Cetraa:BAAANQADCgYIBgAAAA==.',
Ch='Chamii:BAAANQADCgYIBgAAAA==.Chargeantrot:BAAANQAECgEIAQABNQAECgcICgADAAAAAA==.Cherrypalaid:BAABNQAECoEaAAMFAAkKsxXsOABkAgAFAAkKsxXsOABkAgAGAAEKdAHCoAEaAAAAAA==.Chicntrl:BAAANQAECgcIDwAAAA==.',
Co='Cobble:BAAANQAECgQIDQAAAA==.Colhap:BAABNQAECoEnAAIHAAkK9iAFCwAfAwAHAAkK9iAFCwAfAwAAAA==.Conjure:BAAANQAECgQIBgAAAA==.Corehammer:BAAANQADCgYIDQAAAA==.',
Cr='Creamsocket:BAAANQAECgQJBgAAAA==.Cru:BAAANQAECgUIBgAAAA==.',
Cu='Culligan:BAABNQAECoE1AAIIAAgKIhvFdwB4AgAIAAgKIhvFdwB4AgAAAA==.Cuttingcrew:BAAANQADCggICAAAAA==.',
Cy='Cygwin:BAAANQAECgYIEgAAAA==.',
Da='Danaforever:BAAANQADCgIJAgAAAA==.Darklon:BAABNQAECoEZAAMJAAgKagpSZwBOAQAJAAcKowpSZwBOAQAKAAIKhwf1ggBdAAAAAA==.Datmage:BAAANQAECgEIAQAAAA==.',
De='Decomposed:BAAANQADCgMIAwAAAA==.Deku:BAAANQADCgcIBwAAAA==.Demonbreath:BAAANQAECggIDwAAAA==.Demunzz:BAAANQADCggIFgAAAA==.Destruction:BAABNQAECoEZAAILAAcKBQbRbAAcAQALAAcKBQbRbAAcAQAAAA==.Deylei:BAAANQAECgEIAQAAAA==.',
Di='Dithur:BAAANQADCgMJAwAAAA==.Divinespark:BAABNQAECoEZAAIMAAcKZRsCTQAVAgAMAAcKZRsCTQAVAgAAAA==.',
Do='Doinkbigs:BAAANQAECgYIEwAAAA==.Dolmant:BAAANQAECgUJBQAAAA==.Dooko:BAAANQAECgEIAQAAAA==.Doomo:BAAANQADCgUIBQAAAA==.Dotñtrot:BAAANQAECgMICQABNQAECgcICgADAAAAAA==.',
Dr='Draethno:BAAANQADCgMIBwAAAA==.Drambush:BAAANQADCgMIAwAAAA==.Draqulen:BAAANQABCgYICQAAAA==.Dredd:BAAANQAECgEIAQAAAA==.Drewsilla:BAAANQADCgIIAgAAAA==.Druidrose:BAAANQAECgMIAwAAAA==.',
Du='Dunes:BAAANQADCgUIBQAAAA==.Duruk:BAAANQAECgUIBwAAAA==.',
['Dà']='Dàvë:BAAANQADCggIDgABNQAECgcIEwADAAAAAA==.',
Ea='Eap:BAAANQADCggIEQAAAA==.Eazye:BAABNQAECoErAAIHAAkKih4GDQAEAwAHAAkKih4GDQAEAwAAAA==.',
Ed='Edgeffs:BAABNQAECoEZAAINAAcKkQgHtQBpAQANAAcKkQgHtQBpAQAAAA==.',
El='Elentiya:BAABNQAECoEaAAIMAAkKrhl0KgChAgAMAAkKrhl0KgChAgAAAA==.Elphs:BAAANQAECgcIEAAAAA==.Elphzz:BAAANQADCgYIBgAAAA==.',
Er='Eriius:BAAANQADCgcIBwAAAA==.',
Fa='Fabri:BAABNQAECoEYAAMOAAYKvCUECgCYAQAMAAYKvCXzUAAGAgAOAAUKDSEECgCYAQAAAA==.',
Fe='Felorc:BAAANQAECgUIEwAAAA==.Fenton:BAAANQAECgcICwAAAA==.Fentun:BAABNQAECoEZAAIFAAgKqibZBgCJAwAFAAgKqibZBgCJAwAAAA==.',
Fo='Foulplay:BAAANQAECgUIBQAAAA==.',
Fr='Free:BAAANQAECgEIAQAAAA==.',
Ga='Gabacadabra:BAAANQABCgIIAgAAAA==.Gali:BAAANQABCgcIFAAAAA==.',
Ge='Gelektrael:BAABNQAECoEaAAMPAAcKiRULEADzAQAPAAcKiRULEADzAQAQAAQKnQd38wCyAAAAAA==.Getchya:BAAANQAECgQIBQABNQAECgcIEwADAAAAAA==.',
Gh='Ghoostt:BAAANQAECgcIEAABNQAFFAMIBwAGABoNAA==.Ghostzz:BAACNQAFFIEHAAIGAAMKGg2SEwDfAAAGAAMKGg2SEwDfAAA1AAQKgSoAAgYACQoPHocwAOgCAAYACQoPHocwAOgCAAAA.',
Gl='Gloríous:BAAANQADCggICwABNQAECgUIEQADAAAAAA==.Glzygldiator:BAAANQAECgIIBQAAAA==.',
Gn='Gnomelock:BAAANQADCgYIBgAAAA==.',
Go='Goriath:BAAANQADCgcIBwAAAA==.',
Gr='Greenowl:BAAANQADCgYIDQAAAA==.Greyhairs:BAAANQAECgUICQAAAA==.Grimstorm:BAAANQADCgEIAQAAAA==.Gromit:BAAANQAECgYICwABNQAECgcIEgADAAAAAA==.',
Gu='Gustófwind:BAAANQADCggIGAAAAA==.',
Ha='Hacky:BAAANQAECgYIDgAAAA==.Haldire:BAAANQABCgQIBAAAAA==.Harryp:BAAANQADCgQIBAAAAA==.Haruto:BAAANQADCggICAAAAA==.Haschel:BAAANQADCgcICgAAAA==.',
He='Hexhunts:BAAANQADCgEJAQAAAA==.',
Ho='Holiecow:BAABNQAECoEYAAIFAAYKpwkClwAyAQAFAAYKpwkClwAyAQAAAA==.Hoshi:BAAANQADCgQIBAABNQAECgkJKwAHAJ0lAA==.',
Hu='Hurtak:BAAANQAECgUICwAAAA==.',
Hy='Hycisan:BAAANQAECgYIEQAAAA==.Hysteria:BAAANQAECgIIAgAAAA==.',
Ic='Icydoodad:BAAANQAECgUIBQABNQAECgcIEwADAAAAAA==.',
Ik='Ikdutak:BAAANQAECgYIBgAAAA==.',
Il='Illusionwr:BAAANQAECgUIBAABNQAECgkKKQARAO4dAA==.',
Ja='Jagerspell:BAABNQAECoEjAAMSAAkKCiFvCADnAgASAAgKOCFvCADnAgATAAQKsx/8QgB4AQAAAA==.',
Je='Jeezy:BAAANQADCgUIBQAAAA==.Jetmage:BAAANQAECgYIDAAAAA==.',
Ji='Jibryl:BAAANQADCgMIAwAAAA==.',
Ka='Kaerina:BAAANQAECgUIDAAAAA==.Kanastra:BAABNQAECoEYAAIUAAcK6RJkKwDFAQAUAAcK6RJkKwDFAQABNQAECgkJHwACAP8XAA==.Karraa:BAAANQADCgYJBgABNQAECgUIDAADAAAAAA==.Kaylib:BAAANQAECgUIEgAAAA==.',
Ke='Kesi:BAAANQAECgMJAwAAAA==.',
Kh='Khaztharion:BAAANQADCgcIDgABNQAECgcIFgAVAB0eAA==.Khendrick:BAAANQAECgYIEQAAAA==.',
Ki='Kinarra:BAAANQABCgYIBgAAAA==.Kittykatt:BAABNQAECoEkAAIEAAkK6BpLHQDEAgAEAAkK6BpLHQDEAgAAAA==.',
Kn='Knowledge:BAABNQAECoEaAAIIAAcK2iFkZQCfAgAIAAcK2iFkZQCfAgAAAA==.',
Ko='Koof:BAAANQADCgYIBgABNQAECgcIGwANAMYZAA==.',
Kr='Kraggo:BAABNQAECoEpAAMQAAkKPxm0KwC9AgAQAAkKPxm0KwC9AgAPAAIKZgn+XgBdAAAAAA==.Krimzin:BAAANQAFFAEIAQABNQAFFAUIDAAWADQVAA==.',
['Kí']='Kíllerwolf:BAAANQAECgMIBAAAAA==.',
La='Larsen:BAABNQAECoEaAAIXAAcKGB68PgBRAgAXAAcKGB68PgBRAgAAAA==.Lastshot:BAAANQADCgUIBwAAAA==.Laudanum:BAAANQAECgUIBQAAAA==.',
Le='Leap:BAAANQAECgQIBwAAAA==.Legbah:BAAANQADCgYICgABNQAECgcIEwADAAAAAA==.',
Li='Lightmare:BAAANQADCgYIBgAAAA==.',
Ll='Llarker:BAAANQADCgUICwAAAA==.',
Lo='Lookadragon:BAAANQAECgUIDQAAAA==.',
Lu='Ludom:BAAANQADCgYIBwABNQAECgEIAQADAAAAAA==.Lunacy:BAAANQAECgIIAgAAAA==.',
Ly='Lynngosa:BAABNQAECoEmAAIYAAgKNBNuGgABAgAYAAgKNBNuGgABAgAAAA==.',
Ma='Magebob:BAAANQAECgYICQAAAA==.Magisterium:BAAANQAECgMIBAAAAA==.Mario:BAAANQABCgUIBQABNQADCgYIBgADAAAAAA==.Maulware:BAAANQADCgQICwAAAA==.',
Me='Meingaree:BAAANQABCgcICgAAAA==.Mentery:BAAANQADCgUJBwAAAA==.Mestema:BAAANQABCgEIAQAAAA==.',
Mi='Mightyguzz:BAABNQAECoEhAAINAAcKiQujqwCDAQANAAcKiQujqwCDAQAAAA==.Migiggle:BAAANQADCgQIBAAAAA==.Mingi:BAAANQAECgcIDwAAAA==.Minimuffn:BAABNQAECoEaAAIJAAcKLx2ROQAYAgAJAAcKLx2ROQAYAgAAAA==.Misericordia:BAABNQAECoEZAAIHAAcKags2MgBpAQAHAAcKags2MgBpAQAAAA==.',
['Mø']='Møønchild:BAAANQAECgQIBwAAAA==.',
Na='Nanaish:BAAANQAECgMIBgAAAA==.Natë:BAABNQAECoExAAIZAAkKMBSBDgAYAgAZAAkKMBSBDgAYAgAAAA==.',
Ne='Necrotalon:BAAANQAECgUIBQAAAA==.Nemesia:BAABNQAECoEbAAMNAAcKxhlzcwAZAgANAAcKxhlzcwAZAgAaAAUKKxBIFQAlAQAAAA==.Neonsunrise:BAABNQAECoErAAIHAAkK2yGEBgBgAwAHAAkK2yGEBgBgAwAAAA==.',
Nh='Nharuna:BAABNQAECoEeAAIWAAgKUw9zaQAVAgAWAAgKUw9zaQAVAgAAAA==.',
Ni='Nieloriel:BAAANQAECgUIDAAAAA==.Nimbus:BAAANQAECgIIBAABNQAFFAcIEAAXAOMXAA==.Niykee:BAABNQAECoEcAAQTAAgKMiCxEgDFAgATAAgK1B+xEgDFAgAbAAUKOxsKDQBiAQASAAEKSAi4SgA4AAAAAA==.',
No='Noboundss:BAABNQAECoEeAAMRAAgKih2iGQCrAgARAAgK9hyiGQCrAgAUAAUKcBiHNwBhAQAAAA==.Noztra:BAABNQAECoEpAAMcAAgKRg58HADhAAAIAAgKUAvGyQDNAQAcAAQKoRF8HADhAAAAAA==.',
Ns='Nsolant:BAAANQAECgUICQAAAA==.',
Nu='Nubsy:BAAANQAECgEIAQAAAA==.Nuker:BAAANQAECgQIBAAAAA==.Nukron:BAAANQADCggIEAAAAA==.',
Oh='Ohgr:BAAANQAECgYIEwAAAA==.Ohshifty:BAABNQAECoEoAAMEAAgKRBhNKgBiAgAEAAgKRBhNKgBiAgAdAAIK5gH+ZgA2AAAAAA==.',
Ol='Oldmanbuzz:BAAANQADCgYIDwAAAA==.',
Or='Orbsicles:BAABNQAECoEZAAMUAAcKuxfWIwAKAgAUAAcKuxfWIwAKAgAeAAIK5xm1IACMAAAAAA==.Oriøn:BAAANQADCgYICgAAAA==.',
Pa='Paedrig:BAAANQADCgUIBQAAAA==.Papitomyrey:BAAANQAECgMIAwABNQAECggIGwAfAGYhAA==.Pawm:BAAANQAECgIIAgAAAA==.',
Pe='Peenter:BAAANQADCggIGQAAAA==.Pestílence:BAACNQAFFIEHAAIJAAQKaxY5CwAyAQAJAAQKaxY5CwAyAQA1AAQKgTEAAgkACQqRJTgDALcDAAkACQqRJTgDALcDAAAA.',
Ph='Phaesphoros:BAAANQADCgYIBgAAAA==.',
Po='Pokadot:BAAANQABCgQIBQAAAA==.Pooter:BAABNQAECoEVAAIWAAgKoQWR7AD4AAAWAAgKoQWR7AD4AAAAAA==.Powpow:BAABNQAECoEVAAISAAgKTRJgFQAoAgASAAgKTRJgFQAoAgAAAA==.',
Pr='Prejudice:BAABNQAECoEaAAIFAAcKug43dwCKAQAFAAcKug43dwCKAQAAAA==.Proto:BAAANQADCgQIBAAAAA==.Prowlcow:BAABNQAECoEmAAMdAAkKaA2YJADRAQAdAAkKaA2YJADRAQAgAAcKKQ0/FAB/AQAAAA==.',
['Pû']='Pûff:BAABNQAECoEkAAIYAAgKgB1BDgCxAgAYAAgKgB1BDgCxAgAAAA==.',
Qm='Qmpel:BAAANQADCgYIEwAAAA==.',
Ra='Raiiz:BAAANQAECgMIAwAAAA==.Rainhoof:BAABNQAECoEaAAMgAAcKYhZvFgBaAQAgAAUK6BVvFgBaAQAdAAUK5AlLQADuAAAAAA==.Ralneth:BAACNQAFFIEaAAIYAAcKCBJKAwA1AgAYAAcKCBJKAwA1AgA1AAQKgSoAAhgACQorGREUAFkCABgACQorGREUAFkCAAAA.Rapala:BAAANQAECgYIEwAAAA==.Rapalaa:BAAANQABCgYIBwABNQAECgYIEwADAAAAAA==.Raspútin:BAAANQAECgMIAwABNQAECgUIBgADAAAAAA==.Rawdoinkers:BAAANQADCggIHAAAAA==.Rawkfice:BAAANQADCgYIEwAAAA==.',
Re='Redlefbarg:BAAANQADCgMIAwAAAA==.Renakir:BAAANQADCgEIAQAAAA==.Renly:BAABNQAECoEYAAIfAAcKTB5qEgBVAgAfAAcKTB5qEgBVAgAAAA==.Restoral:BAAANQAECgIIAQAAAA==.',
Ri='Riordan:BAAANQAECgUIEAAAAA==.Rivvetear:BAAANQADCgIIAgAAAA==.',
Rj='Rjolz:BAACNQAFFIEJAAIJAAQK2BvaDgDtAAAJAAQK2BvaDgDtAAA1AAQKgTkAAwkACQo3JmACAMsDAAkACQo3JmACAMsDAAoABgryHSMzANUBAAAA.',
Ro='Roflchopr:BAABNQAECoEdAAIGAAcK6BHPoACoAQAGAAcK6BHPoACoAQAAAA==.Roflkin:BAAANQADCgQIBAAAAA==.',
Sa='Sadcow:BAABNQAECoEiAAIXAAgKMxwdMQCRAgAXAAgKMxwdMQCRAgAAAA==.Sandalfon:BAAANQADCgYICQAAAA==.Sanleron:BAAANQAECgcIDgAAAA==.Sarith:BAAANQADCgcIBwAAAA==.Sarloz:BAAANQAECgEIAwAAAA==.Saruna:BAAANQADCgYIBgAAAA==.',
Sc='Scyleia:BAAANQADCgYICAAAAA==.',
Sh='Sharayse:BAAANQADCgYIEwAAAA==.Sharmee:BAAANQAECgcIDwAAAA==.Shmelverino:BAAANQADCggICAAAAA==.Shmoozle:BAAANQABCgIIAgAAAA==.Shogu:BAABNQAECoEaAAMNAAcKJQyarQB9AQANAAcKTQqarQB9AQAZAAEKDhNUOAA+AAAAAA==.Sháde:BAAANQAECgYIEQAAAA==.',
Si='Simpmother:BAEBNQAECoEkAAIQAAgKIhB8bADxAQAQAAgKIhB8bADxAQAAAA==.',
Sl='Sladepriest:BAAANQAECgMIAwAAAA==.Slingablade:BAABNQAECoEfAAIUAAgKDhcPHQBPAgAUAAgKDhcPHQBPAgAAAA==.',
Sm='Smallfoot:BAAANQADCgEIAQAAAA==.',
Sn='Sniffsniff:BAAANQAECgYICwABNQAFFAUIDAABAFsjAA==.',
So='Solvi:BAAANQAECgUIBwAAAA==.Sorá:BAABNQAECoEYAAINAAgKeiBsLgDwAgANAAgKeiBsLgDwAgABNQAECgkJKwALAIEVAA==.Soulbrand:BAAANQAECgMIBQAAAA==.',
Sp='Spellz:BAAANQADCgcJDAABNQAECgIIAgADAAAAAA==.',
St='Stabathuh:BAAANQAECgcIEwAAAA==.Stabnskullz:BAAANQAECgQJBAABNQAECggIDwADAAAAAA==.Stacatta:BAAANQAECgQIBAAAAA==.Stinnky:BAAANQAFFAIJAgAAAA==.Stoopidelf:BAAANQAECgEIAQABNQAECgcIEwADAAAAAA==.Stoopidlock:BAAANQADCggIEwABNQAECgcIEwADAAAAAA==.Stoopidmonk:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.Stoopidrood:BAAANQAECgEIAQABNQAECgcIEwADAAAAAA==.Stoopidtroll:BAAANQADCgEIAQABNQAECgcIEwADAAAAAA==.Stoopidwarur:BAAANQADCgcIEwABNQAECgcIEwADAAAAAA==.Stormclaw:BAABNQAECoEaAAIeAAcKMQviEwA7AQAeAAcKMQviEwA7AQAAAA==.Styne:BAAANQADCggICAABNQAECggIIgAXADMcAA==.',
Su='Sufiya:BAAANQAECgYIEgAAAA==.Suki:BAABNQAECoEmAAIhAAgK0B+8CgC/AgAhAAgK0B+8CgC/AgAAAA==.Sulfion:BAAANQAECgIIAgAAAA==.',
Sw='Swftgrabs:BAAANQADCgMIAwAAAA==.Swiftarrows:BAAANQADCgYIEAAAAA==.',
Sy='Sylveria:BAAANQAECgIIAwAAAA==.Sylvershadow:BAAANQAECgEIAQAAAA==.Syphon:BAABNQAECoEpAAMeAAkKTx3kAwDwAgAeAAgKxyDkAwDwAgARAAIKVQHdkQANAAAAAA==.',
['Sý']='Sýrin:BAAANQADCggJCgAAAA==.',
Ta='Tandarilada:BAAANQADCgMJAwAAAA==.Tanfer:BAAANQADCggIDwAAAA==.',
Te='Testiew:BAAANQADCggIFQAAAA==.',
Th='Thalvint:BAABNQAECoEkAAINAAgKaxtHWQBjAgANAAgKaxtHWQBjAgAAAA==.',
Ti='Titanic:BAAANQAECgQIBAAAAA==.',
To='Tomcruise:BAABNQAECoEZAAIGAAgKDR4MTgCDAgAGAAgKDR4MTgCDAgAAAA==.Totemlyawsum:BAAANQAECgYICwAAAA==.',
Tr='True:BAAANQAECgIIBAAAAA==.',
Tw='Twotone:BAAANQADCgEIAQAAAA==.',
Ul='Ulkthar:BAAANQADCgcIBwABNQAFFAQICAAIAJkIAA==.',
Un='Unholyhammer:BAAANQABCgMIAQABNQAECggIDwADAAAAAA==.',
Va='Vaiyrnlol:BAABNQAECoEbAAIBAAkKNB6FGgDrAgABAAkKNB6FGgDrAgAAAA==.Vanlin:BAAANQAECgYIEgAAAA==.',
Ve='Vexxdr:BAABNQAECoEiAAMdAAkK5BEwHQAeAgAdAAkK5BEwHQAeAgAEAAQKXhWbZQALAQABNQAECgkJJAABANIaAA==.Vexxs:BAABNQAECoEkAAMBAAkK0hpAHADgAgABAAkK0hpAHADgAgAXAAIKWxFg6wB9AAAAAA==.',
Vo='Voidsuzu:BAABNQAECoEiAAIUAAgK4w9jJgDzAQAUAAgK4w9jJgDzAQAAAA==.Vormedicus:BAAANQAECgUIBgAAAA==.',
Vs='Vsaguzz:BAAANQADCgEJAQABNQAECgcIIQANAIkLAA==.',
Vu='Vulpes:BAAANQAECgIIAgAAAA==.',
Vy='Vya:BAAANQAECgQICQAAAA==.',
Wa='Waroo:BAAANQADCggICAAAAA==.',
We='Werewolf:BAAANQADCggICgAAAA==.',
Wi='Wickïdus:BAAANQABCggIEAAAAA==.Windhoof:BAAANQADCgQJBAAAAA==.',
Wu='Wulffric:BAAANQAECgMIBgAAAA==.',
Xa='Xaphelion:BAAANQADCggIGAAAAA==.Xazio:BAABNQAECoEhAAIfAAcKhRR1JQCGAQAfAAcKhRR1JQCGAQAAAA==.',
Yi='Yiang:BAAANQAECgUIEgAAAA==.',
Yl='Ylndrysa:BAABNQAECoE1AAIdAAgK4xM0IAD9AQAdAAgK4xM0IAD9AQAAAA==.',
Ze='Zedrock:BAABNQAECoEZAAIcAAgKhSAyBQCeAgAcAAgKhSAyBQCeAgAAAA==.Zeezu:BAAANQAECgMIAwAAAA==.Zexrous:BAAANQADCgYIBwAAAA==.',
Zh='Zhas:BAAANQAECgUICQAAAA==.Zhitolight:BAAANQAECgEIBAABNQAECggICgADAAAAAA==.',
Zu='Zuro:BAABNQAECoEZAAIWAAcK+QfBpACKAQAWAAcK+QfBpACKAQAAAA==.',
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
