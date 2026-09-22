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

local lookup = {'Unknown-Unknown','Druid-Balance','Warrior-Protection','Druid-Restoration','DemonHunter-Devourer','Mage-Arcane','Mage-Frost','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Priest-Holy','Warrior-Arms','Shaman-Elemental','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ag='Agrios:BAABNQAECoEcAAICAAgKuxcsIgBbAgACAAgKuxcsIgBbAgAAAA==.',
Ak='Akias:BAAANQADCggJJAAAAA==.',
Al='Altaurus:BAAANQAECgQIBAAAAA==.Alynnei:BAAANQAECgIIAwABNQABCgQIBAABAAAAAA==.',
Am='Amare:BAAANQAECgEIAQAAAA==.',
An='Andros:BAAANQAECgEJAgAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Arroyo:BAAANQAECgYJDgAAAA==.',
As='Askadar:BAABNQAECoEcAAIDAAgK7iYgAQChAwADAAgK7iYgAQChAwAAAA==.',
Az='Azora:BAAANQAECgYJCAAAAA==.Azzura:BAAANQAECgEJAQAAAA==.',
Ba='Baheem:BAAANQADCgYIFgAAAA==.Bams:BAAANQAECgUJBgAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAAANQAECgcJDgAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bastile:BAAANQADCggJCAAAAA==.Bauer:BAAANQAECgcJEwAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAAANQADCgYJDwAAAA==.',
Bi='Bifrons:BAAANQADCgUIDAAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Bluè:BAAANQADCgQIBAAAAA==.',
Bo='Bobble:BAAANQADCgUIBQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCgQICAAAAA==.Boolil:BAAANQAECgQIBAABNQAECgcIEwABAAAAAA==.Boolove:BAAANQABCgUIAwABNQAECgcIEwABAAAAAA==.Booloved:BAAANQAECgcIEwAAAA==.',
Bq='Bqcritraven:BAAANQADCgUJBQAAAA==.',
Br='Broxx:BAAANQADCgcICQAAAA==.',
By='Byssrak:BAAANQADCggJGAAAAA==.',
Ca='Carmêl:BAAANQADCggJFwABNQAECgUJDgABAAAAAA==.',
Ce='Cerealmilk:BAAANQADCgQIBAABNQADCggJEQABAAAAAA==.',
Ch='Christopher:BAAANQAECgcJDgAAAA==.',
Cr='Creepydemise:BAAANQADCgYICwAAAA==.Croixsmash:BAAANQAECgUJCgAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.',
Cy='Cylvanna:BAAANQAECgEIAQAAAA==.',
Da='Darkagedemon:BAAANQADCgQIBAAAAA==.Dartboofer:BAAANQADCgYIBgABNQAECgUJCgABAAAAAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAAANQAECgYIDwAAAA==.Dawnn:BAAANQAECgUJBgAAAA==.',
De='Deanwnchestr:BAAANQAECgEIAQAAAA==.Deatnshadow:BAAANQADCggIEAAAAA==.Dendin:BAAANQADCgcIBwAAAA==.',
Dm='Dmncgdss:BAAANQAECgEIAQAAAA==.',
Dr='Draakell:BAAANQADCgcIBwAAAA==.Dragonstew:BAAANQADCgYIBgAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.',
Du='Dudè:BAAANQAECgMJAwAAAA==.',
['Dâ']='Dâggèr:BAAANQAFFAEIAQAAAA==.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQABCggJCgAAAA==.',
El='Elarae:BAAANQAECgUICwAAAA==.Elementblah:BAAANQAECgQIBAAAAA==.Elfkinn:BAABNQAECoEdAAMCAAkKsx16EwDpAgACAAkKsx16EwDpAgAEAAEKhwHYVgAZAAAAAA==.Elivaniel:BAAANQADCgYIBgAAAA==.',
Em='Empathyforyo:BAAANQAECgcJDQAAAA==.',
En='Enna:BAAANQADCgUIDAAAAA==.',
Eq='Equinox:BAAANQAECgcJDQAAAA==.',
Er='Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAAANQAECgUJBgAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAAANQAECgcICAAAAA==.Exzanthia:BAAANQADCgcIBwAAAA==.',
Ey='Eyln:BAAANQAECgUJCgAAAA==.',
Fa='Falkor:BAAANQAECgcJEgAAAA==.Fayway:BAAANQAECgYJCgAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAAANQAECgcIEwAAAA==.',
Fi='Figgy:BAAANQAECgQIBAAAAA==.Firepower:BAAANQAECgUIDgABNQAECgYJCQABAAAAAA==.',
Fo='Forevershy:BAAANQADCgYIBgAAAA==.',
Fr='Fries:BAEANQAECggJBwAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Go='Gothrim:BAAANQADCgMJAwAAAA==.',
Gr='Greenbean:BAAANQADCggJCAABNQAECgkJHQACALMdAA==.Groto:BAAANQAECgIJAgAAAA==.Grrum:BAAANQADCgcICAAAAA==.Grèy:BAAANQAECgQJBQAAAA==.',
Gu='Gullible:BAAANQADCgYJBgAAAA==.',
Ha='Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAAANQADCgYJBgAAAA==.Hanjo:BAAANQAECgQIBQAAAA==.Hatookorr:BAAANQAECgYJCQAAAA==.',
He='Heledrianis:BAAANQADCggIDQAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.',
Ho='Hornet:BAAANQADCggIHAAAAA==.',
Hy='Hydé:BAAANQAFFAIJAwAAAA==.',
Ik='Ikwon:BAAANQADCgEJAQAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
Is='Ismeldbad:BAAANQAECgIIAwAAAA==.',
Je='Jellybreak:BAAANQAECgUJCgAAAA==.',
Jo='Joeewee:BAAANQAECgMIBQAAAA==.',
Ka='Kaanâ:BAAANQAECgQIBQAAAA==.Kateblue:BAAANQAECgQIBQAAAA==.',
Ke='Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAAANQAECgUICwAAAA==.Kelsyyr:BAAANQADCgQIBAABNQAECgUICwABAAAAAA==.Kenpachi:BAAANQADCgEIAQAAAA==.',
Ki='Kidneysweeny:BAAANQAECgYJBgAAAA==.Kikyou:BAAANQAECgYJBQABNQAFFAUJCwAFAOIPAA==.Kim:BAAANQAECgMJBAAAAA==.Kissofdeáth:BAAANQADCggIDwAAAA==.',
Kr='Kreepywife:BAAANQADCgUIBQAAAA==.Krelbelorll:BAAANQAECgcJEwAAAA==.Krowley:BAAANQAECgUJBgAAAA==.',
Ku='Kurast:BAAANQAECgUIBgABNQAECgcJEgABAAAAAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAABNQAECoEcAAMGAAkKdCEpHgA+AwAGAAkKdCEpHgA+AwAHAAEKfR1uLQA+AAAAAA==.',
Kx='Kxwono:BAAANQADCgcICgAAAA==.',
La='Ladýshinobu:BAAANQAECggJCQAAAA==.',
Le='Leahu:BAAANQAECgMIBAAAAA==.Lediaa:BAAANQADCgQIBAAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQADCgUJBQAAAA==.',
Li='Lisavia:BAAANQAECgMJBAAAAA==.',
Lo='Locholovis:BAAANQADCgYJBwAAAA==.Locklicous:BAAANQAECgYJCwABNQAECgUJCgABAAAAAA==.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAABNQAECoEjAAMIAAkK1RySFAC8AgAIAAkK1RySFAC8AgAJAAEKFh2jhgBRAAAAAA==.',
Lu='Luminouss:BAABNQAECoElAAIKAAkK+xuaGQC+AgAKAAkK+xuaGQC+AgAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lyrium:BAAANQADCgYIBgABNQADCggJCQABAAAAAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQADCgYICwAAAA==.Magnuus:BAAANQADCgcIEQAAAA==.Majin:BAAANQABCgIIAgAAAA==.Malvorak:BAAANQADCggICwABNQAECgEIAQABAAAAAA==.Mantis:BAAANQAECgUICwABNQAECgcJEgABAAAAAA==.',
Me='Mechacattie:BAAANQAECgQICAAAAA==.Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAAANQAECgQIBQAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mezi:BAAANQAECgUJCgAAAA==.',
Mg='Mg:BAAANQADCgUIDQAAAA==.',
Mi='Middleman:BAAANQADCgQIBAAAAA==.Mildchaos:BAAANQAECgQJBAAAAA==.',
Mu='Mulron:BAAANQAECgUJBgAAAA==.',
My='Myrica:BAAANQAECgEIAQAAAA==.',
Oa='Oakenshíeld:BAABNQAECoEhAAICAAkKIxhFGAC3AgACAAkKIxhFGAC3AgAAAA==.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Ol='Olkwon:BAAANQADCgUICQAAAA==.',
Oo='Oozwoz:BAAANQADCgcJAgAAAA==.',
Ou='Outfoxed:BAAANQAECggJCQABNQAFFAIIBQALAAgOAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAAANQAECgQIBQAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCgQJCAAAAA==.',
Pl='Plaguebeard:BAAANQAECgIJAwABNQAECggJGgAMAIgTAA==.Plagueblade:BAAANQAECgQIBQAAAA==.',
Pr='Progression:BAAANQAECggJAwAAAA==.',
Ra='Ragingrain:BAAANQADCgUIBQAAAA==.Rainsshammy:BAAANQAECgUIDAAAAA==.',
Re='Realhelz:BAAANQADCgcICQAAAA==.Redsamilf:BAAANQADCgcIGAAAAA==.Rekka:BAAANQADCgYICgAAAA==.Requizik:BAAANQAECgMIAwAAAA==.Resaana:BAAANQAECgEIAQAAAA==.Restofarian:BAABNQAECoEYAAMKAAkKLRkoFwDOAgAKAAkKLRkoFwDOAgANAAQKURCZjQD1AAAAAA==.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAAANQAECgYIDgAAAA==.',
Ri='Rianon:BAAANQADCgEIAQABNQAECgYJCQABAAAAAA==.Rizzy:BAABNQAECoEcAAMJAAgK/w+JLwDzAQAJAAgK/w+JLwDzAQAOAAEKJwh/dQAnAAAAAA==.',
Ro='Rotinshot:BAABNQAECoEXAAIPAAkKthuEFQD5AgAPAAkKthuEFQD5AgAAAA==.',
Ru='Rutikee:BAAANQAECgUIDQAAAA==.',
Ry='Ryomensukuna:BAAANQAFFAIIAgAAAA==.',
Sa='Sandrill:BAAANQAECgQJBQABNQAECgYJCQABAAAAAA==.Savior:BAAANQADCggJFgAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.',
Se='Seamisty:BAAANQADCgIJAgAAAA==.Seastorm:BAAANQADCgMIAwAAAA==.Seizon:BAAANQAECgEJAQAAAA==.Senseicanz:BAAANQABCgIIAgAAAA==.Serom:BAAANQADCggIGwAAAA==.Sethic:BAAANQADCgYJBAAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkie:BAAANQADCggJCwAAAA==.Sherunn:BAAANQADCggIFgAAAA==.Shimakaze:BAAANQAECgQICQAAAA==.Shmitty:BAAANQAECgYICwABNQAFFAEIAQABAAAAAA==.Shooters:BAAANQAECgYICgAAAA==.Shymistress:BAAANQAECgUICQAAAA==.Shåmmy:BAAANQAECgcIEwAAAA==.',
Si='Sindralea:BAAANQAECgMIAwAAAA==.',
Sk='Skiá:BAAANQAECgYIDgAAAA==.',
Sl='Slicedbread:BAAANQAECgEIAQAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQADCggIFAABAAAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAAANQAECgQIDAAAAA==.Stonefist:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Stormfox:BAAANQAECgUJCQAAAA==.Strawhat:BAAANQAECgIJBAAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQAECgEIAQAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQADCggIFAAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAAANQAECgMIAwAAAA==.Tannuk:BAAANQAECgcIDgAAAA==.Tauru:BAAANQADCgcICwAAAA==.',
Te='Tea:BAAANQADCgcIBwAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAAANQAECgUIDAAAAA==.',
Th='Thundaris:BAAANQABCgMIAwAAAA==.',
Ti='Tiari:BAAANQAECgYIDgAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
Tr='Tridius:BAAANQAECgYIEwAAAA==.Trixx:BAAANQAECgUICwAAAA==.',
Tu='Tuffcracker:BAAANQADCggJFAAAAA==.Turdanator:BAAANQADCgYICgAAAA==.',
Tw='Twinturboj:BAAANQAECgEJAQAAAA==.Twittle:BAAANQAECgMJAwAAAA==.',
Ty='Tylovastus:BAAANQAECgYJBwAAAA==.Tyrmin:BAAANQAECgEJAQAAAA==.',
Ub='Ube:BAAANQAECgcJDgAAAA==.',
Ur='Uriah:BAAANQADCggJIwAAAA==.Ursúla:BAAANQADCgMIAwABNQAECgkJHQACALMdAA==.',
Ut='Utherr:BAAANQADCggIEAAAAA==.',
Va='Valaravaus:BAAANQADCgcIBwAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.',
Vi='Viral:BAAANQAECggJCQAAAA==.',
Vo='Vonnie:BAAANQAECgEIAQAAAA==.',
['Vé']='Végeta:BAAANQAECgQIBAABNQAECgcJEgABAAAAAA==.',
Wa='Wardwhelp:BAAANQADCggJEQAAAA==.',
Wo='Wooloo:BAACNQAFFIEKAAQQAAYKohwBBwBOAQAQAAQKpxkBBwBOAQARAAEKbiMsDABnAAASAAEKxCGTAwBgAAA1AAQKgRwAAxEACQr7ILsLABsCABAABgpcJsYkAJICABEABwpyG7sLABsCAAAA.',
Wy='Wynona:BAABNQAECoEXAAIGAAgKahQ5dAA3AgAGAAgKahQ5dAA3AgAAAA==.',
Xa='Xanagore:BAAANQAECgYJEAAAAA==.',
Xk='Xkwon:BAAANQADCggIDAAAAA==.Xkwøn:BAABNQAECoEmAAITAAkKbCLeAACJAwATAAkKbCLeAACJAwAAAA==.Xkwønn:BAAANQADCgUICAAAAA==.Xkwønxø:BAAANQAECgUJCwAAAA==.',
Xu='Xunie:BAAANQADCgcIFAAAAA==.',
Yl='Yloh:BAAANQAECgYIEAAAAA==.',
Yo='Yoquiere:BAAANQADCgYICQAAAA==.',
Za='Zaisplash:BAAANQAECgMIAwAAAA==.Zana:BAAANQADCgUIBQAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgUJBgABAAAAAA==.Zaretan:BAAANQADCgcJBwAAAA==.',
Zb='Zbrute:BAAANQAECgUJBgAAAA==.',
Ze='Zees:BAAANQAECgEIAQAAAA==.',
Zo='Zokohjin:BAAANQAFFAIJAwAAAA==.',
Zu='Zulpher:BAAANQADCgYJEgAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUJDQAAAA==.',
['Øk']='Økwøn:BAAANQAECggIEQAAAA==.',
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
