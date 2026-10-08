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

local lookup = {'Unknown-Unknown','Shaman-Elemental','Druid-Balance','DeathKnight-Unholy','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Priest-Holy','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','Evoker-Preservation','Druid-Feral','Mage-Frost','Shaman-Restoration','Druid-Guardian','Rogue-Subtlety','Warlock-Affliction','Rogue-Assassination','DemonHunter-Devourer','DeathKnight-Blood','Warrior-Arms','DeathKnight-Frost','Paladin-Protection','Paladin-Holy','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ad='Adonìs:BAAANQAECgYIBgAAAA==.',
Ae='Aeolos:BAAANQADCgYIBgAAAA==.Aesthetic:BAAANQAECgYIBwABNQAFFAYIEQACAKMZAA==.',
Ag='Agrios:BAABNQAECoEnAAIDAAkKihnuHgC3AgADAAkKihnuHgC3AgAAAA==.',
Ak='Akias:BAAANQADCggIPAAAAA==.',
Al='Alexandra:BAAANQADCgMIAwABNQABCgQIBAABAAAAAA==.Alliekill:BAAANQADCgQIBQABNQAECgUIDAABAAAAAA==.Altaurus:BAAANQAECgUIDQAAAA==.Alynnei:BAAANQAECgIIAwABNQABCgQIBAABAAAAAA==.',
Am='Amare:BAAANQAECgIIBQAAAA==.Amiria:BAAANQADCggICAAAAA==.',
An='Andros:BAAANQAECgUICAAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Arroyo:BAABNQAECoEfAAIEAAgKhiM+DwApAwAEAAgKhiM+DwApAwAAAA==.',
As='Askadar:BAABNQAECoEjAAIFAAkK/CYRAAAPBAAFAAkK/CYRAAAPBAAAAA==.',
Az='Azora:BAABNQAECoEaAAMGAAgKkhl8CwA0AgAGAAcKUBt8CwA0AgAHAAYKyBQdjACZAQAAAA==.Azzura:BAAANQAECgEJAQAAAA==.',
Ba='Baheem:BAAANQADCggIHwAAAA==.Bams:BAAANQAECgYIEQAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAABNQAECoEdAAMIAAgKkBzQCwCRAgAIAAgKkBzQCwCRAgAJAAEK3AH/IwAeAAAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bastile:BAAANQADCggICQAAAA==.Bauer:BAABNQAECoEgAAIKAAgKXRQ0eAAMAgAKAAgKXRQ0eAAMAgAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAAANQADCgYIFwAAAA==.',
Bi='Bifrons:BAAANQADCgYIEgAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Blahwithpets:BAAANQADCgMIBgAAAA==.Bluè:BAAANQADCgQIBAAAAA==.',
Bo='Bobble:BAAANQADCgUIBQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCgUIEgAAAA==.Boolil:BAAANQAECgQICAABNQAECgkJIwALAPAMAA==.Boolove:BAAANQABCgUIAwABNQAECgkJIwALAPAMAA==.Booloved:BAABNQAECoEjAAQLAAkK8AxJCwB3AQALAAcKUw9JCwB3AQAMAAgKsQPaOgAoAQANAAUKlQEtwAChAAAAAA==.',
Bq='Bqcritraven:BAAANQADCgUJBQAAAA==.',
Br='Broxx:BAAANQADCgcICQAAAA==.',
By='Byssrak:BAAANQADCggIGAAAAA==.',
Ca='Carmêl:BAAANQAECgMIAwABNQAECggIHwAOAHwhAA==.Cattiegreen:BAABNQAECoEbAAIPAAcKxRm1WQA9AgAPAAcKxRm1WQA9AgAAAA==.',
Ce='Celoraning:BAAANQADCgcIBwAAAA==.Cerealmilk:BAAANQADCgQIBAABNQADCggJEQABAAAAAA==.',
Ch='Chopshop:BAAANQADCgUIBQAAAA==.Christopher:BAABNQAECoEfAAIOAAgKsBjXigBOAgAOAAgKsBjXigBOAgAAAA==.',
Co='Costica:BAAANQADCgUIBQAAAA==.',
Cr='Creepydemise:BAAANQADCggIEwAAAA==.Croixsmash:BAAANQAECgYIDAAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.',
Cy='Cylvanna:BAAANQAECgIIBQAAAA==.',
Da='Darkagedemon:BAAANQADCgQIBAAAAA==.Darkrest:BAAANQADCgUIBQAAAA==.Dartboofer:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAABNQAECoEeAAIKAAkK0AnUmgC2AQAKAAkK0AnUmgC2AQAAAA==.Dawnn:BAAANQAECgUICwAAAA==.',
De='Deanwnchestr:BAAANQAECgIIAwAAAA==.Deatnshadow:BAAANQADCggIEAAAAA==.Dendin:BAAANQADCgcIBwAAAA==.',
Dm='Dmncgdss:BAAANQAECgIIAwAAAA==.',
Dr='Draakell:BAAANQAECgUIBQAAAA==.Dragonstew:BAAANQADCgYIBgAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dreamsicle:BAAANQAECgUIBwAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.Dryrain:BAAANQADCggICAAAAA==.',
Du='Dudè:BAAANQAECgUIDAAAAA==.',
['Dâ']='Dâggèr:BAAANQAFFAIIBAAAAA==.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQABCggIDAAAAA==.',
El='Elarae:BAABNQAECoEZAAIPAAgKrxhMRgBzAgAPAAgKrxhMRgBzAgAAAA==.Elementblah:BAAANQAECgUIDgAAAA==.Elfkinn:BAACNQAFFIEMAAIDAAUKrxQHCwCNAQADAAUKrxQHCwCNAQA1AAQKgSEAAwMACQoaH0IYAOwCAAMACQoaH0IYAOwCABAAAQqHASJ1ABUAAAAA.Elivaniel:BAAANQADCgYIBgAAAA==.',
Em='Emeryl:BAAANQAECgQIBQABNQAFFAYIEQACAKMZAA==.Empathyforyo:BAABNQAECoEeAAIPAAgKOBumOQCbAgAPAAgKOBumOQCbAgAAAA==.',
En='Enna:BAAANQADCgYIEgAAAA==.',
Eq='Equinox:BAABNQAECoEXAAIDAAgKohM9OwDvAQADAAgKohM9OwDvAQAAAA==.',
Er='Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAAANQAECgYIEQAAAA==.',
Es='Eshtar:BAAANQADCggICAAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAAANQAECggIEQAAAA==.Exzanthia:BAAANQADCgcIBwAAAA==.',
Ey='Eyln:BAAANQAECgYIEAAAAA==.',
Fa='Falkor:BAABNQAECoEfAAIRAAkKPRWyEQB7AgARAAkKPRWyEQB7AgAAAA==.Fayway:BAABNQAECoEaAAMQAAgK/hyEEAC0AgAQAAgK/hyEEAC0AgADAAEKLAJCtgAZAAAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAABNQAECoElAAISAAgK8h8ZBgDnAgASAAgK8h8ZBgDnAgAAAA==.',
Fi='Figgy:BAAANQAECgYICgAAAA==.Firepower:BAABNQAECoEjAAMOAAkKfhmQUQDNAgAOAAkKbxmQUQDNAgATAAEKvhnHOgBAAAAAAA==.',
Fo='Forevershy:BAAANQADCggIFgAAAA==.',
Fr='Fries:BAEANQAECggIDAAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Gi='Giggles:BAAANQAECgUIBwAAAA==.',
Go='Goh:BAAANQAECgQIBAAAAA==.Gomugomu:BAAANQADCgEIAQAAAA==.Gonzo:BAAANQAECgcIDgABNQAECgkJIwAUAIshAA==.Gothrim:BAAANQADCggICAAAAA==.',
Gr='Greenbean:BAAANQADCggJCAABNQAFFAUIDAADAK8UAA==.Groto:BAAANQAECgYICQAAAA==.Grrum:BAAANQAECgIIAgAAAA==.Grèy:BAAANQAECgQIBQAAAA==.',
Gu='Gullible:BAAANQAECgYIBgAAAA==.',
Ha='Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAAANQADCgYICwAAAA==.Hanjo:BAAANQAECgUIDwAAAA==.Hatookorr:BAAANQAECggIEgABNQAECgkJIwAOAH4ZAA==.',
He='Heledrianis:BAAANQADCggIDQAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.Herunn:BAAANQADCggICAAAAA==.',
Ho='Hornet:BAAANQADCggIJAAAAA==.',
Hy='Hydé:BAACNQAFFIENAAIVAAUKbR/sAADPAQAVAAUKbR/sAADPAQA1AAQKgRgAAhUACQr2GokIAMACABUACQr2GokIAMACAAAA.',
Ik='Ikwon:BAAANQADCgIIAgAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
Is='Ishmael:BAAANQADCgYIBwAAAA==.Ismeldbad:BAAANQAECgIIAwABNQAECggIFgAWAP4ZAA==.',
Ja='Jaland:BAAANQABCgQIBAAAAA==.',
Je='Jellybreak:BAAANQAECgYIEgAAAA==.',
Jo='Joeewee:BAAANQAECgMIBQAAAA==.',
Ka='Kaanâ:BAAANQAECgUIDwAAAA==.Kateblue:BAAANQAECgUIDwAAAA==.',
Ke='Keeble:BAAANQADCgMIAwAAAA==.Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAABNQAECoEVAAMXAAcKVhm6BgAXAgAXAAcKVhm6BgAXAgAHAAMKNQb9BgF9AAAAAA==.Kelsyyr:BAAANQAECgUIBwABNQAECgcIFQAXAFYZAA==.Kenpachi:BAAANQADCgEIAQAAAA==.',
Ki='Kidneysweeny:BAABNQAECoEWAAMWAAgK/hnkHQDOAQAWAAYKrBfkHQDOAQAYAAMK2hnHXgDqAAAAAA==.Kikyou:BAAANQAECgYIDAABNQAFFAYIFgAZAOoZAA==.Kim:BAAANQAECgYIDQAAAA==.Kissofdeáth:BAAANQADCggIDwAAAA==.',
Kr='Kreepywife:BAAANQADCgUIBQAAAA==.Krelbelorll:BAABNQAECoEeAAIZAAgKyw1VKADhAQAZAAgKyw1VKADhAQAAAA==.Krowley:BAAANQAECgYIEQAAAA==.',
Ku='Kurast:BAAANQAECgUICgABNQAECgkJHwARAD0VAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAACNQAFFIELAAIOAAUKOBFvFwCVAQAOAAUKOBFvFwCVAQA1AAQKgR4AAw4ACQp0IS04AAoDAA4ACQp0IS04AAoDABMAAQp9Hec/ADUAAAAA.',
Kx='Kxwono:BAAANQAECgUICgAAAA==.',
La='Ladýshinobu:BAAANQAECggIEgAAAA==.',
Le='Leahu:BAAANQAECgMIBAAAAA==.Lediaa:BAAANQADCgQIBAAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQAECgMIAwAAAA==.',
Li='Lisavia:BAAANQAECgYIDwAAAA==.',
Lo='Locholovis:BAAANQAECgEIAQAAAA==.Locklicous:BAABNQAECoEeAAIHAAkKnxphJQDWAgAHAAkKnxphJQDWAgABNQAECgYIDAABAAAAAA==.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAACNQAFFIEJAAIaAAQKBA50EwDvAAAaAAQKBA50EwDvAAA1AAQKgSoAAxoACQrRHiseAKcCABoACQomHSseAKcCAAQABAo+HutwACwBAAAA.',
Lu='Luminouss:BAACNQAFFIEKAAIUAAUK8BSICACoAQAUAAUK8BSICACoAQA1AAQKgTEAAhQACQp0HYsdANkCABQACQp0HYsdANkCAAAA.Lumpia:BAAANQAECgcIBwAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lyrium:BAAANQADCgYIBgABNQAECgcIGQAaALoaAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQAECgEIAQAAAA==.Magnuus:BAAANQAECgEIAQAAAA==.Majin:BAAANQAECgIIAgAAAA==.Malvorak:BAAANQADCggIEwABNQAECgIIAwABAAAAAA==.Mantis:BAABNQAECoEXAAIUAAYKcSPrOQBPAgAUAAYKcSPrOQBPAgABNQAECgkJHwARAD0VAA==.',
Me='Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAAANQAECgUIDwAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mercas:BAAANQAECgMIAwABNQAECggIHAAOAL0XAA==.Mezi:BAABNQAECoEVAAINAAYKfhb+cwCHAQANAAYKfhb+cwCHAQAAAA==.',
Mg='Mg:BAAANQADCgUIDQAAAA==.',
Mi='Miasma:BAAANQADCggICAAAAA==.Middleman:BAAANQADCgQIBAAAAA==.Mildchaos:BAAANQAECgQIDAAAAA==.',
Mu='Mulron:BAAANQAECgYIEQAAAA==.',
My='Myrica:BAAANQAECgIIAgAAAA==.',
Ni='Nishand:BAAANQADCgEIAQAAAA==.',
Oa='Oakenshíeld:BAACNQAFFIEIAAIDAAQKnA0ZEAAtAQADAAQKnA0ZEAAtAQA1AAQKgSwAAgMACQqPHD4WAP4CAAMACQqPHD4WAP4CAAAA.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Ok='Okwonz:BAAANQADCggICAAAAA==.',
Ol='Olkwon:BAAANQAECgUIBgAAAA==.',
Oo='Oozwoz:BAAANQADCggIBAAAAA==.',
Ou='Outfoxed:BAAANQAECggIDgABNQAFFAQIDQANALsZAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAAANQAECgUIDwAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCgQIDAAAAA==.',
Pl='Plaguebeard:BAAANQAECgIJAwABNQAECggJGgAbAIgTAA==.Plagueblade:BAAANQAECgUIDwAAAA==.',
Pr='Progression:BAAANQAECggICwAAAA==.',
Ra='Ragingrain:BAAANQADCgUIBQAAAA==.Rainsshammy:BAABNQAECoEaAAIUAAgKPht4LACMAgAUAAgKPht4LACMAgAAAA==.Rawak:BAAANQABCggIDQAAAA==.Rawktuah:BAAANQADCgMIAwAAAA==.',
Re='Realhelz:BAAANQADCgcICQAAAA==.Redsamilf:BAAANQAECgMIBQAAAA==.Rekka:BAAANQADCgYICgAAAA==.Requizik:BAAANQAECgMIBQAAAA==.Resaana:BAAANQAECgIIAwAAAA==.Restofarian:BAABNQAECoEjAAMUAAkKiyG/CwBOAwAUAAkKiyG/CwBOAwACAAQKURB6wgDfAAAAAA==.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAAANQAECgYIDwAAAA==.',
Ri='Rianon:BAAANQADCgEIAQABNQAECgcIDAABAAAAAA==.Rizzy:BAABNQAECoEsAAMEAAkKNhFXQwDnAQAEAAkKNhFXQwDnAQAcAAEKJwjengAkAAAAAA==.',
Ro='Rotinshot:BAABNQAECoEaAAIPAAkKfR2nHwD9AgAPAAkKfR2nHwD9AgAAAA==.',
Ru='Rutikee:BAABNQAECoEgAAMQAAgKiAwxKgCaAQAQAAgKiAwxKgCaAQADAAIKvgK/lABRAAAAAA==.',
Ry='Ryomensukuna:BAAANQAFFAIIAgAAAA==.',
Sa='Sandrill:BAAANQAECgQJBQABNQAECgkJIwAOAH4ZAA==.Savior:BAAANQAECgIIAgAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.',
Se='Seamisty:BAAANQADCgIJAgAAAA==.Seastorm:BAAANQADCgQIBAAAAA==.Seizon:BAAANQAECgMIBQAAAA==.Senseicanz:BAAANQADCgYIBgAAAA==.Serom:BAAANQAECgIIBAAAAA==.Sethic:BAAANQADCgYJBAAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkie:BAAANQADCggJCwAAAA==.Sharkyn:BAAANQADCgQIBAAAAA==.Sherunn:BAAANQAECgIIBAAAAA==.Shimakaze:BAABNQAECoEVAAIPAAcKBQkpqgB9AQAPAAcKBQkpqgB9AQAAAA==.Shmitty:BAAANQAECgYICwABNQAFFAIIBAABAAAAAA==.Shooters:BAAANQAECgYIDwAAAA==.Shymistress:BAABNQAECoEbAAIPAAgKlBhbSwBkAgAPAAgKlBhbSwBkAgAAAA==.Shåmmy:BAABNQAECoElAAIUAAgKeRbNSQAPAgAUAAgKeRbNSQAPAgAAAA==.',
Si='Sindralea:BAAANQAECgUIDQAAAA==.',
Sk='Skiá:BAABNQAECoEfAAISAAgKuBk2CQCEAgASAAgKuBk2CQCEAgAAAA==.',
Sl='Slicedbread:BAAANQAECgEIAQAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQADCggIJAABAAAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAABNQAECoEYAAIKAAYKlxuMjADZAQAKAAYKlxuMjADZAQAAAA==.Stonefist:BAAANQAECgEIAQABNQAFFAIIBAABAAAAAA==.Stormfox:BAAANQAECgUICgAAAA==.Strawhat:BAAANQAECgQICwAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQAECgIIBQAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQADCggIJAAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAAANQAECgQICQAAAA==.Tannuk:BAABNQAECoEhAAIdAAgKnBQ4GwDqAQAdAAgKnBQ4GwDqAQAAAA==.Tarz:BAAANQABCgIIAgAAAA==.Tauru:BAAANQAECgIIAgAAAA==.',
Te='Tea:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAABNQAECoEbAAICAAgKSRxEMQCQAgACAAgKSRxEMQCQAgAAAA==.',
Th='Thekingbak:BAAANQAECgEIAQAAAA==.Thundaris:BAAANQABCgMIAwAAAA==.',
Ti='Tiari:BAABNQAECoEeAAIeAAgK2xOAUAAKAgAeAAgK2xOAUAAKAgAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
To='Totems:BAAANQAECgYICgABNQAECgIIAgABAAAAAA==.',
Tr='Tridius:BAABNQAECoE2AAMNAAkKYCCgCgBbAwANAAkKYCCgCgBbAwAMAAEKpBXvZwA9AAAAAA==.Trixx:BAAANQAECgUICwAAAA==.',
Tu='Tuffcracker:BAAANQAECgIIBAAAAA==.Turdanator:BAAANQADCggIDAAAAA==.',
Tw='Twinturboj:BAAANQAECgIIAwAAAA==.Twittle:BAAANQAECgMIBQAAAA==.',
Ty='Tylovastus:BAAANQAECgcICwAAAA==.Tyrmin:BAAANQAECgEIAQAAAA==.',
Ub='Ube:BAABNQAECoEZAAIbAAgKcx+cNgDSAgAbAAgKcx+cNgDSAgAAAA==.',
Ur='Uriah:BAAANQAECgUICAAAAA==.Ursúla:BAAANQAECggICgABNQAFFAUIDAADAK8UAA==.Urïah:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.',
Ut='Utherr:BAAANQADCggIEAAAAA==.',
Va='Valaravaus:BAAANQADCgcIBwAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.',
Vi='Viral:BAAANQAECggICQAAAA==.',
Vo='Vonnie:BAAANQAECgEIAQAAAA==.',
['Vé']='Végeta:BAAANQAECgQICAABNQAECgkJHwARAD0VAA==.',
Wa='Wardwhelp:BAAANQADCggJEQAAAA==.',
Wh='Whitecoma:BAAANQABCgIIAgAAAA==.',
Wo='Wooloo:BAACNQAFFIEMAAQHAAYKohwUEgA8AQAHAAQKpxkUEgA8AQAGAAEKbiPgEgBcAAAXAAEKxCE7BwBbAAA1AAQKgR8AAwYACQr7IHYOAAcCAAcABgpcJr48AIECAAYABwpyG3YOAAcCAAAA.',
Wy='Wynona:BAABNQAECoEfAAIOAAkKaha1aQCWAgAOAAkKaha1aQCWAgAAAA==.',
Xa='Xanagore:BAABNQAECoEeAAMbAAcKdBKwkwDDAQAbAAcKdBKwkwDDAQAFAAMKAQ2ILgCOAAAAAA==.',
Xk='Xkwon:BAAANQADCggIDgAAAA==.Xkwøn:BAACNQAFFIEIAAIfAAIK1hkGAgCvAAAfAAIK1hkGAgCvAAA1AAQKgSwAAh8ACQqfIo4BAGIDAB8ACQqfIo4BAGIDAAAA.Xkwønn:BAAANQADCgUICgAAAA==.Xkwønxø:BAAANQAECgUJCwAAAA==.',
Xu='Xunie:BAAANQADCgcIIQAAAA==.',
Yl='Yloh:BAABNQAECoEbAAQNAAgKHyRxEQAoAwANAAgKHyRxEQAoAwAMAAYKVwQJTwCrAAALAAIK3Q14HABmAAAAAA==.',
Yo='Yoquiere:BAAANQADCggIHQAAAA==.',
Za='Zaisplash:BAAANQAECgUICgAAAA==.Zana:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgUICwABAAAAAA==.Zaretan:BAAANQADCggIEwAAAA==.',
Zb='Zbrute:BAAANQAECgYIEQAAAA==.',
Ze='Zees:BAAANQAECggIAQAAAA==.',
Zo='Zokohjin:BAACNQAFFIENAAQcAAUKuA1rCwDfAAAcAAMKjw5rCwDfAAAEAAIKpgoZFgCNAAAaAAEKpA6gLQAtAAA1AAQKgRgAAwQACQoGEio4ACACAAQACQqpESo4ACACABwABArMFZJXAP4AAAAA.',
Zu='Zulpher:BAAANQADCggIGwAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUIEQAAAA==.',
['Øk']='Økwøn:BAABNQAECoEVAAIOAAkKFRgJdwB6AgAOAAkKFRgJdwB6AgAAAA==.',
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
