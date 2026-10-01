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

local lookup = {'Unknown-Unknown','Druid-Balance','DeathKnight-Unholy','Warrior-Protection','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Mage-Arcane','Druid-Restoration','Shaman-Elemental','Hunter-BeastMastery','Evoker-Preservation','Druid-Feral','Mage-Frost','Shaman-Restoration','Druid-Guardian','DemonHunter-Devourer','Warlock-Demonology','DeathKnight-Blood','Priest-Holy','Warrior-Arms','DeathKnight-Frost','Paladin-Protection','Paladin-Holy','Warlock-Destruction','Warlock-Affliction','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ad='Adonìs:BAAANQADCgUIBAAAAA==.',
Ag='Agrios:BAABNQAECoEkAAICAAkKfRg0HAC3AgACAAkKfRg0HAC3AgAAAA==.',
Ak='Akias:BAAANQADCggINAAAAA==.',
Al='Alexandra:BAAANQADCgMIAwABNQABCgQIBAABAAAAAA==.Alliekill:BAAANQADCgIIAgABNQAECgQICAABAAAAAA==.Altaurus:BAAANQAECgUICQAAAA==.Alynnei:BAAANQAECgIIAwABNQABCgQIBAABAAAAAA==.',
Am='Amare:BAAANQAECgIIAwAAAA==.',
An='Andros:BAAANQAECgIIBAAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Arroyo:BAABNQAECoEZAAIDAAcKfiNRGAC/AgADAAcKfiNRGAC/AgAAAA==.',
As='Askadar:BAABNQAECoEgAAIEAAkK+yYHAAAUBAAEAAkK+yYHAAAUBAAAAA==.',
Az='Azora:BAAANQAECgcIDwAAAA==.Azzura:BAAANQAECgEJAQAAAA==.',
Ba='Baheem:BAAANQADCgcIHQAAAA==.Bams:BAAANQAECgUICwAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAABNQAECoEYAAMFAAgKPhgrDgBDAgAFAAgKPhgrDgBDAgAGAAEK3AHhHwAeAAAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bastile:BAAANQADCggICQAAAA==.Bauer:BAABNQAECoEdAAIHAAgKIBM9aQAGAgAHAAgKIBM9aQAGAgAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAAANQADCgYIEAAAAA==.',
Bi='Bifrons:BAAANQADCgYIEgAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Blahwithpets:BAAANQADCgMIAwAAAA==.Bluè:BAAANQADCgQIBAAAAA==.',
Bo='Bobble:BAAANQADCgUIBQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCgUIDQAAAA==.Boolil:BAAANQAECgQIBAABNQAECggIHAAIAMkLAA==.Boolove:BAAANQABCgUIAwABNQAECggIHAAIAMkLAA==.Booloved:BAABNQAECoEcAAMIAAgKyQt7DAA9AQAIAAYKLw57DAA9AQAJAAgKsQOWMwAyAQAAAA==.',
Bq='Bqcritraven:BAAANQADCgUJBQAAAA==.',
Br='Broxx:BAAANQADCgcICQAAAA==.',
By='Byssrak:BAAANQADCggJGAAAAA==.',
Ca='Carmêl:BAAANQADCggJFwABNQAECgcIGQAKAGEiAA==.',
Ce='Celoraning:BAAANQADCgcIBwAAAA==.Cerealmilk:BAAANQADCgQIBAABNQADCggJEQABAAAAAA==.',
Ch='Christopher:BAABNQAECoEYAAIKAAgKehgcewBQAgAKAAgKehgcewBQAgAAAA==.',
Cr='Creepydemise:BAAANQADCggIEwAAAA==.Croixsmash:BAAANQAECgUICwAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.',
Cy='Cylvanna:BAAANQAECgIIAwAAAA==.',
Da='Darkagedemon:BAAANQADCgQIBAAAAA==.Dartboofer:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAABNQAECoEWAAIHAAcKMwmsqwBXAQAHAAcKMwmsqwBXAQAAAA==.Dawnn:BAAANQAECgUICwAAAA==.',
De='Deanwnchestr:BAAANQAECgEIAQAAAA==.Deatnshadow:BAAANQADCggIEAAAAA==.Dendin:BAAANQADCgcIBwAAAA==.',
Dm='Dmncgdss:BAAANQAECgIIAwAAAA==.',
Dr='Draakell:BAAANQADCgcIBwAAAA==.Dragonstew:BAAANQADCgYIBgAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dreamsicle:BAAANQAECgIIAgAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.',
Du='Dudè:BAAANQAECgQIBwAAAA==.',
['Dâ']='Dâggèr:BAAANQAFFAEIAgAAAA==.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQABCggIDAAAAA==.',
El='Elarae:BAAANQAECgYIEQAAAA==.Elementblah:BAAANQAECgUICQAAAA==.Elfkinn:BAACNQAFFIEHAAICAAMKhRZ7EADoAAACAAMKhRZ7EADoAAA1AAQKgSEAAwIACQoaHxkUAAEDAAIACQoaHxkUAAEDAAsAAQqHAQlmABkAAAAA.Elivaniel:BAAANQADCgYIBgAAAA==.',
Em='Emeryl:BAAANQAECgEIAQABNQAFFAYIDQAMAKMZAA==.Empathyforyo:BAABNQAECoEXAAINAAgK5xlcNgCEAgANAAgK5xlcNgCEAgAAAA==.',
En='Enna:BAAANQADCgYIEgAAAA==.',
Eq='Equinox:BAABNQAECoEXAAICAAgKohP/MgAEAgACAAgKohP/MgAEAgAAAA==.',
Er='Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAAANQAECgUICwAAAA==.',
Es='Eshtar:BAAANQADCggICAAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAAANQAECggIDgAAAA==.Exzanthia:BAAANQADCgcIBwAAAA==.',
Ey='Eyln:BAAANQAECgUJCgAAAA==.',
Fa='Falkor:BAABNQAECoEaAAIOAAgKaBfdEgBRAgAOAAgKaBfdEgBRAgAAAA==.Fayway:BAAANQAECgcIEQAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAABNQAECoEdAAIPAAgKfB8PBQDjAgAPAAgKfB8PBQDjAgAAAA==.',
Fi='Figgy:BAAANQAECgQIBAAAAA==.Firepower:BAABNQAECoEaAAMKAAgKNxZYfQBKAgAKAAgKhxVYfQBKAgAQAAEKvhmaMQBIAAAAAA==.',
Fo='Forevershy:BAAANQADCggIDgAAAA==.',
Fr='Fries:BAEANQAECggICwAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Gi='Giggles:BAAANQAECgQIBAAAAA==.',
Go='Gomugomu:BAAANQADCgEIAQAAAA==.Gonzo:BAAANQAECgcIBwABNQAECgkJHwARAIshAA==.Gothrim:BAAANQADCggICAAAAA==.',
Gr='Greenbean:BAAANQADCggJCAABNQAFFAMIBwACAIUWAA==.Groto:BAAANQAECgMIAwAAAA==.Grrum:BAAANQADCgcICAAAAA==.Grèy:BAAANQAECgQJBQAAAA==.',
Gu='Gullible:BAAANQADCgYJBgAAAA==.',
Ha='Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAAANQADCgYIBwAAAA==.Hanjo:BAAANQAECgUICgAAAA==.Hatookorr:BAAANQAECgcIDwABNQAECggIGgAKADcWAA==.',
He='Heledrianis:BAAANQADCggIDQAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.Herunn:BAAANQADCggICAAAAA==.',
Ho='Hornet:BAAANQADCggIJAAAAA==.',
Hy='Hydé:BAABNQAFFIEIAAISAAQKWR1ZAQBgAQASAAQKWR1ZAQBgAQAAAA==.',
Ik='Ikwon:BAAANQADCgIIAgAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
Is='Ishmael:BAAANQADCgUIBQAAAA==.Ismeldbad:BAAANQAECgIIAwAAAA==.',
Je='Jellybreak:BAAANQAECgUIDwAAAA==.',
Jo='Joeewee:BAAANQAECgMIBQAAAA==.',
Ka='Kaanâ:BAAANQAECgUICgAAAA==.Kateblue:BAAANQAECgUICgAAAA==.',
Ke='Keeble:BAAANQADCgMIAwAAAA==.Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAAANQAECgYIEQAAAA==.Kelsyyr:BAAANQAECgEIAgABNQAECgYIEQABAAAAAA==.Kenpachi:BAAANQADCgEIAQAAAA==.',
Ki='Kidneysweeny:BAAANQAECgcIDQAAAA==.Kikyou:BAAANQAECgYICQABNQAFFAUIEAATAMIZAA==.Kim:BAAANQAECgQIBwAAAA==.Kissofdeáth:BAAANQADCggIDwAAAA==.',
Kr='Kreepywife:BAAANQADCgUIBQAAAA==.Krelbelorll:BAABNQAECoEeAAITAAgKyw30IwDsAQATAAgKyw30IwDsAQAAAA==.Krowley:BAAANQAECgUICwAAAA==.',
Ku='Kurast:BAAANQAECgUIBgABNQAECggIGgAOAGgXAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAACNQAFFIEHAAIKAAUKKQ7ZEgCPAQAKAAUKKQ7ZEgCPAQA1AAQKgR4AAwoACQp0IZIrAB8DAAoACQp0IZIrAB8DABAAAQp9Hbs4ADcAAAAA.',
Kx='Kxwono:BAAANQAECgUIBQAAAA==.',
La='Ladýshinobu:BAAANQAECggIDQAAAA==.',
Le='Leahu:BAAANQAECgMIBAAAAA==.Lediaa:BAAANQADCgQIBAAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQAECgEIAQAAAA==.',
Li='Lisavia:BAAANQAECgUICQAAAA==.',
Lo='Locholovis:BAAANQAECgEIAQAAAA==.Locklicous:BAABNQAECoEWAAIUAAgKFxkaMgCFAgAUAAgKFxkaMgCFAgABNQAECgUICwABAAAAAA==.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAACNQAFFIEFAAIVAAIKzxFTGAB9AAAVAAIKzxFTGAB9AAA1AAQKgScAAxUACQrRHt0aAKUCABUACQrVHN0aAKUCAAMABAo+Hu5ZAEIBAAAA.',
Lu='Luminouss:BAACNQAFFIEGAAIRAAQKTRPkCQBRAQARAAQKTRPkCQBRAQA1AAQKgS4AAhEACQp0HX8XAOcCABEACQp0HX8XAOcCAAAA.Lumpia:BAAANQAECgcIBwAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lyrium:BAAANQADCgYIBgABNQAECgYIEAABAAAAAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQADCgYICwAAAA==.Magnuus:BAAANQADCgcIFQAAAA==.Majin:BAAANQAECgIIAgAAAA==.Malvorak:BAAANQADCggICwABNQAECgEIAQABAAAAAA==.Mantis:BAAANQAECgUIDwABNQAECggIGgAOAGgXAA==.',
Me='Mechacattie:BAAANQAECgUIDQAAAA==.Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAAANQAECgUICgAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mezi:BAAANQAECgUIDwAAAA==.',
Mg='Mg:BAAANQADCgUIDQAAAA==.',
Mi='Middleman:BAAANQADCgQIBAAAAA==.Mildchaos:BAAANQAECgQICAAAAA==.',
Mu='Mulron:BAAANQAECgUICwAAAA==.',
My='Myrica:BAAANQAECgEIAQAAAA==.',
Oa='Oakenshíeld:BAABNQAECoEpAAICAAkKdRxpEwAHAwACAAkKdRxpEwAHAwAAAA==.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Ok='Okwonz:BAAANQADCggICAAAAA==.',
Ol='Olkwon:BAAANQADCgcICwAAAA==.',
Oo='Oozwoz:BAAANQADCggIBAAAAA==.',
Ou='Outfoxed:BAAANQAECggIDgABNQAFFAQICQAWAH0MAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAAANQAECgUICgAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCgQJCAAAAA==.',
Pl='Plaguebeard:BAAANQAECgIJAwABNQAECggJGgAXAIgTAA==.Plagueblade:BAAANQAECgUICgAAAA==.',
Pr='Progression:BAAANQAECggIBgAAAA==.',
Ra='Ragingrain:BAAANQADCgUIBQAAAA==.Rainsshammy:BAAANQAECgYIEgAAAA==.Rawktuah:BAAANQADCgMIAwABNQADCgYJCAABAAAAAA==.',
Re='Realhelz:BAAANQADCgcICQAAAA==.Redsamilf:BAAANQAECgIIAgAAAA==.Rekka:BAAANQADCgYICgAAAA==.Requizik:BAAANQAECgMIBQAAAA==.Resaana:BAAANQAECgEIAQAAAA==.Restofarian:BAABNQAECoEfAAMRAAkKiyEwCABkAwARAAkKiyEwCABkAwAMAAQKURDcqQDqAAAAAA==.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAAANQAECgYIDgAAAA==.',
Ri='Rianon:BAAANQADCgEIAQABNQAECgcICwABAAAAAA==.Rizzy:BAABNQAECoEkAAMDAAkK0xBvNQDzAQADAAkK0xBvNQDzAQAYAAEKJwjSkAAfAAAAAA==.',
Ro='Rotinshot:BAABNQAECoEXAAINAAkKthsSIQDbAgANAAkKthsSIQDbAgAAAA==.',
Ru='Rutikee:BAABNQAECoEYAAMLAAgKyg2MKwBaAQALAAcKLAuMKwBaAQACAAIKvgLghQBWAAAAAA==.',
Ry='Ryomensukuna:BAAANQAFFAIIAgAAAA==.',
Sa='Sandrill:BAAANQAECgQJBQABNQAECggIGgAKADcWAA==.Savior:BAAANQADCggIHAAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.',
Se='Seamisty:BAAANQADCgIJAgAAAA==.Seastorm:BAAANQADCgMIAwAAAA==.Seizon:BAAANQAECgEIAgAAAA==.Senseicanz:BAAANQABCgIIAgAAAA==.Serom:BAAANQAECgIIAgAAAA==.Sethic:BAAANQADCgYJBAAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkie:BAAANQADCggJCwAAAA==.Sharkyn:BAAANQADCgQIBAAAAA==.Sherunn:BAAANQAECgIIAgAAAA==.Shimakaze:BAAANQAECgUIDgAAAA==.Shmitty:BAAANQAECgYICwABNQAFFAEIAgABAAAAAA==.Shooters:BAAANQAECgYIDgAAAA==.Shymistress:BAAANQAECgcIEAAAAA==.Shåmmy:BAABNQAECoEdAAIRAAgKNxa+PwAWAgARAAgKNxa+PwAWAgAAAA==.',
Si='Sindralea:BAAANQAECgUICAAAAA==.',
Sk='Skiá:BAABNQAECoEZAAIPAAcKxRiYCgAhAgAPAAcKxRiYCgAhAgAAAA==.',
Sl='Slicedbread:BAAANQAECgEIAQAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQADCggIHAABAAAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAAANQAECgUIEQAAAA==.Stonefist:BAAANQAECgEIAQABNQAFFAEIAgABAAAAAA==.Stormfox:BAAANQAECgUICgAAAA==.Strawhat:BAAANQAECgMIBwAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQAECgIIAwAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQADCggIHAAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAAANQAECgQIBwAAAA==.Tannuk:BAABNQAECoEZAAIZAAgKrRLTGQDNAQAZAAgKrRLTGQDNAQAAAA==.Tauru:BAAANQAECgIIAgAAAA==.',
Te='Tea:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAAANQAECgYIEgAAAA==.',
Th='Thundaris:BAAANQABCgMIAwAAAA==.',
Ti='Tiari:BAABNQAECoEWAAIaAAgK7xGrSwD2AQAaAAgK7xGrSwD2AQAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
Tr='Tridius:BAABNQAECoEkAAMWAAcK0iHDJACfAgAWAAcK0iHDJACfAgAJAAEKpBUiXAA+AAAAAA==.Trixx:BAAANQAECgUICwAAAA==.',
Tu='Tuffcracker:BAAANQAECgIIAgAAAA==.Turdanator:BAAANQADCggIDAAAAA==.',
Tw='Twinturboj:BAAANQAECgIIAwAAAA==.Twittle:BAAANQAECgMIBAAAAA==.',
Ty='Tylovastus:BAAANQAECgcICgAAAA==.Tyrmin:BAAANQAECgEJAQAAAA==.',
Ub='Ube:BAAANQAECgcIDwAAAA==.',
Ur='Uriah:BAAANQAECgMIAwAAAA==.Ursúla:BAAANQADCgMIAwABNQAFFAMIBwACAIUWAA==.Urïah:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.',
Ut='Utherr:BAAANQADCggIEAAAAA==.',
Va='Valaravaus:BAAANQADCgcIBwAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.',
Vi='Viral:BAAANQAECggICQAAAA==.',
Vo='Vonnie:BAAANQAECgEIAQAAAA==.',
['Vé']='Végeta:BAAANQAECgQIBAABNQAECggIGgAOAGgXAA==.',
Wa='Wardwhelp:BAAANQADCggJEQAAAA==.',
Wh='Whitecoma:BAAANQABCgIIAgAAAA==.',
Wo='Wooloo:BAACNQAFFIELAAQUAAYKohwiDABFAQAUAAQKpxkiDABFAQAbAAEKbiMDEABiAAAcAAEKxCFcBQBeAAA1AAQKgR8AAxsACQr7IDQNABICABQABgpcJpQwAIwCABsABwpyGzQNABICAAAA.',
Wy='Wynona:BAABNQAECoEfAAIKAAkKahbiVgCoAgAKAAkKahbiVgCoAgAAAA==.',
Xa='Xanagore:BAABNQAECoEXAAMXAAcK1w9XkwCOAQAXAAcK1w9XkwCOAQAEAAIKlgjOLgBQAAAAAA==.',
Xk='Xkwon:BAAANQADCggIDgAAAA==.Xkwøn:BAACNQAFFIEGAAIdAAIK8hLtAQChAAAdAAIK8hLtAQChAAA1AAQKgSoAAh0ACQqfIi4BAHUDAB0ACQqfIi4BAHUDAAAA.Xkwønn:BAAANQADCgUICgAAAA==.Xkwønxø:BAAANQAECgUJCwAAAA==.',
Xu='Xunie:BAAANQADCgcIGwAAAA==.',
Yl='Yloh:BAABNQAECoEbAAQWAAgKHyTyDAA1AwAWAAgKHyTyDAA1AwAJAAYKVwSYRQCyAAAIAAIK3Q0+GQBoAAAAAA==.',
Yo='Yoquiere:BAAANQADCgcIFQAAAA==.',
Za='Zaisplash:BAAANQAECgMIBQAAAA==.Zana:BAAANQADCgUIBQAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Zaretan:BAAANQADCggIDQAAAA==.',
Zb='Zbrute:BAAANQAECgUICwAAAA==.',
Ze='Zees:BAAANQAECggIAQAAAA==.',
Zo='Zokohjin:BAABNQAFFIEIAAMYAAQKnQz8CADlAAAYAAMKjw78CADlAAAVAAEKyAbkKwAgAAAAAA==.',
Zu='Zulpher:BAAANQADCggIFQAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUIEQAAAA==.',
['Øk']='Økwøn:BAAANQAFFAEIAQAAAA==.',
['ße']='ßeorn:BAAANQABCgIJAgAAAA==.',
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
