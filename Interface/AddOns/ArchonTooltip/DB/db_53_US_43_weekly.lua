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

local lookup = {'Unknown-Unknown','Druid-Balance','Druid-Restoration','DemonHunter-Devourer','Mage-Arcane','Mage-Frost','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Rogue-Outlaw',}
local provider = {region='US',realm='BoreanTundra',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abones:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ag='Agrios:BAAANQAECgcIEQAAAA==.',
Ak='Akias:BAAANQADCgYIHwAAAA==.',
Al='Alynnei:BAAANQAECgIIAwABNQABCgQIBAABAAAAAA==.',
Am='Amare:BAAANQADCggIGgAAAA==.',
An='Andros:BAAANQAECgEIAQAAAA==.Antigone:BAAANQADCgYIBgAAAA==.',
Ar='Arroyo:BAAANQAECgUICAAAAA==.',
As='Askadar:BAAANQAECgcIEgAAAA==.',
Az='Azora:BAAANQAECgUIBwAAAA==.Azzura:BAAANQADCggIDAAAAA==.',
Ba='Baheem:BAAANQADCgYIEAAAAA==.Bams:BAAANQAECgEIAQAAAA==.Banthisname:BAAANQADCgIIAgAAAA==.Barnie:BAAANQAECgUIBwAAAA==.Basquiat:BAAANQADCgYIBQAAAA==.Bauer:BAAANQAECgYIDAAAAA==.',
Be='Beasthunter:BAAANQADCgYIBgAAAA==.Beeftruck:BAAANQADCgYICQAAAA==.',
Bi='Bifrons:BAAANQADCgUIDAAAAA==.',
Bj='Björk:BAAANQADCgEIAQAAAA==.',
Bl='Blackkheartt:BAAANQADCgUIBQAAAA==.Bluè:BAAANQADCgQIBAAAAA==.',
Bo='Bobble:BAAANQADCgUIBQAAAA==.Boneman:BAAANQAECgEIAQAAAA==.Bookwyrm:BAAANQADCgQIBAAAAA==.Boolil:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Boolovesit:BAAANQAECgYIDQAAAA==.',
Br='Broxx:BAAANQADCgcICQAAAA==.',
By='Byssrak:BAAANQADCggIEgAAAA==.',
Ca='Carmêl:BAAANQADCggIFwABNQAECgQICAABAAAAAA==.',
Ce='Cerealmilk:BAAANQADCgQIBAABNQADCggIEQABAAAAAA==.',
Ch='Christopher:BAAANQAECgUIBwAAAA==.',
Cr='Creepydemise:BAAANQADCgYICwAAAA==.Croixsmash:BAAANQAECgIIBQAAAA==.',
Cu='Cuculain:BAAANQAECgYIBgAAAA==.',
Cy='Cylvanna:BAAANQADCggIDgAAAA==.',
Da='Darkagedemon:BAAANQADCgQIBAAAAA==.Dartboofer:BAAANQADCgYIBgABNQAECgIIBQABAAAAAA==.Daslouse:BAAANQADCggIFAAAAA==.Davennial:BAAANQAECgUICQAAAA==.Dawnn:BAAANQAECgEIAQAAAA==.',
De='Deanwnchestr:BAAANQADCggIHAAAAA==.Deatnshadow:BAAANQADCggIEAAAAA==.Dendin:BAAANQADCgcIBwAAAA==.',
Dm='Dmncgdss:BAAANQADCgYIBwAAAA==.',
Dr='Draakell:BAAANQADCgcIBwAAAA==.Drausella:BAAANQADCgMIAwAAAA==.Dregomalfoy:BAAANQADCggICQAAAA==.Drizzle:BAAANQABCgIIAgAAAA==.',
['Dâ']='Dâggèr:BAAANQAECgQIBAAAAA==.',
['Dí']='Dímoní:BAAANQADCgUIBgAAAA==.',
Ec='Echidna:BAAANQABCgcICAAAAA==.',
El='Elarae:BAAANQAECgUICAAAAA==.Elementblah:BAAANQADCggIFQAAAA==.Elfkinn:BAABNQAECoEZAAMCAAkJYB1UDgADAwACAAkJYB1UDgADAwADAAEJhwGLRwAZAAAAAA==.Elivaniel:BAAANQADCgYIBgAAAA==.',
Em='Empathyforyo:BAAANQAECgYIBgAAAA==.',
En='Enna:BAAANQADCgUIDAAAAA==.',
Eq='Equinox:BAAANQAECgQIBgAAAA==.',
Er='Ericcdraven:BAAANQADCgQIBAAAAA==.Erodoria:BAAANQAECgEIAQAAAA==.',
Ev='Eve:BAAANQADCgEIAQAAAA==.',
Ex='Exkwon:BAAANQAECgEIAQAAAA==.Exzanthia:BAAANQADCgcIBwAAAA==.',
Ey='Eyln:BAAANQAECgQIBQAAAA==.',
Fa='Falkor:BAAANQAECgYIDQAAAA==.Fayway:BAAANQAECgYICgAAAA==.',
Fe='Fentlord:BAAANQADCgYIBgAAAA==.Ferral:BAAANQAECgYIDAAAAA==.',
Fi='Figgy:BAAANQAECgQIBAAAAA==.Firepower:BAAANQAECgQICQABNQAECgYICAABAAAAAA==.',
Fo='Forevershy:BAAANQADCgYIBgAAAA==.',
Fr='Fries:BAEANQAECggIBgAAAA==.',
Ga='Galvianick:BAAANQADCggICQAAAA==.',
Go='Gothrim:BAAANQADCgEIAQAAAA==.',
Gr='Greenbean:BAAANQADCggICAABNQAECgkJGQACAGAdAA==.Groto:BAAANQADCgIIAgAAAA==.Grrum:BAAANQADCgcICAAAAA==.Grèy:BAAANQAECgIIAgAAAA==.',
Gu='Gullible:BAAANQADCgYIBgAAAA==.',
Ha='Halbin:BAAANQADCgEIAQAAAA==.Hamburgrtime:BAAANQADCgYIBgAAAA==.Hanjo:BAAANQAECgEIAQAAAA==.Hatookorr:BAAANQAECgYICAAAAA==.',
He='Heledrianis:BAAANQADCggIDQAAAA==.Heledriann:BAAANQADCgUIBQAAAA==.',
Ho='Hornet:BAAANQADCggIFAAAAA==.',
Hy='Hydé:BAAANQAFFAEIAQAAAA==.',
Im='Immatry:BAAANQADCgcIBwAAAA==.',
Is='Ismeldbad:BAAANQAECgIIAgAAAA==.',
Je='Jellybreak:BAAANQAECgQIBQAAAA==.',
Jo='Joeewee:BAAANQADCgcIBwAAAA==.',
Ka='Kaanâ:BAAANQAECgEIAQAAAA==.Kateblue:BAAANQAECgEIAQAAAA==.',
Ke='Kegstand:BAAANQADCgUIBQAAAA==.Kelser:BAAANQAECgQIBgAAAA==.Kelsyyr:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Kenpachi:BAAANQADCgEIAQAAAA==.',
Ki='Kidneysweeny:BAAANQAECgUIBQAAAA==.Kikyou:BAAANQAECgEIAQABNQAFFAMIBgAEAMQTAA==.Kim:BAAANQAECgEIAQAAAA==.Kissofdeáth:BAAANQADCggIDwAAAA==.',
Kr='Kreepywife:BAAANQADCgUIBQAAAA==.Krelbelorll:BAAANQAECgYIDAAAAA==.Krowley:BAAANQAECgEIAQAAAA==.',
Ku='Kurast:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Kuz:BAAANQADCgUIBgAAAA==.Kuzan:BAABNQAECoEYAAMFAAkJ9CD2GQAyAwAFAAkJ9CD2GQAyAwAGAAEJfR38JAA+AAAAAA==.',
Kx='Kxwono:BAAANQADCgYICQAAAA==.',
La='Ladýshinobu:BAAANQAECggIBAAAAA==.',
Le='Leahu:BAAANQAECgMIBAAAAA==.Lediaa:BAAANQADCgQIBAAAAA==.Lemonweed:BAAANQADCgIIAgAAAA==.Leonidus:BAAANQADCgQIBAAAAA==.',
Li='Lisavia:BAAANQAECgEIAQAAAA==.',
Lo='Locholovis:BAAANQADCgYIBwAAAA==.Locklicous:BAAANQAECgYICQABNQAECgIIBQABAAAAAA==.Lonewolf:BAAANQAECgEIAQAAAA==.Longhorse:BAABNQAECoEfAAMHAAkJqhytDgDUAgAHAAkJqhytDgDUAgAIAAEJFh3TdQBVAAAAAA==.',
Lu='Luminouss:BAABNQAECoEcAAIJAAkJ0ho+FgClAgAJAAkJ0ho+FgClAgAAAA==.Lustnnbustin:BAAANQADCgcIDwAAAA==.',
Ly='Lyrium:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Lysandora:BAAANQADCgQIBAAAAA==.',
Ma='Magicgal:BAAANQADCgYICwAAAA==.Magnuus:BAAANQADCgcIDAAAAA==.Malvorak:BAAANQADCggICwAAAA==.Mantis:BAAANQAECgQIBgABNQAECgYIDQABAAAAAA==.',
Me='Mechacattie:BAAANQAECgQIBAAAAA==.Meekerz:BAAANQADCgMIAwAAAA==.Melissandra:BAAANQAECgEIAQAAAA==.Merab:BAAANQADCgIIAgAAAA==.Mezi:BAAANQAECgQIBQAAAA==.',
Mg='Mg:BAAANQADCgUIDQAAAA==.',
Mi='Middleman:BAAANQADCgQIBAAAAA==.',
Mu='Mulron:BAAANQAECgEIAQAAAA==.',
My='Myrica:BAAANQAECgEIAQAAAA==.',
Oa='Oakenshíeld:BAABNQAECoEZAAICAAgJpBnvFwCPAgACAAgJpBnvFwCPAgAAAA==.',
Od='Odyn:BAAANQAECgEIAQAAAA==.',
Ol='Olkwon:BAAANQADCgUICQAAAA==.',
Oo='Oozwoz:BAAANQADCgcIAgAAAA==.',
Ou='Outfoxed:BAAANQADCgYIBgABNQAECgkJHgAKAPgaAA==.',
Ox='Oxwon:BAAANQADCggIDgAAAA==.',
Pa='Palliera:BAAANQADCgMIAwAAAA==.',
Pe='Peetufo:BAAANQAECgEIAQAAAA==.Pewpewtazarz:BAAANQADCggICAAAAA==.',
Ph='Phrizzle:BAAANQADCgQIBQAAAA==.',
Pl='Plaguebeard:BAAANQADCgcICAABNQAECgcIEAABAAAAAA==.Plagueblade:BAAANQAECgEIAQAAAA==.',
Ra='Ragingrain:BAAANQADCgUIBQAAAA==.Rainsshammy:BAAANQAECgUICAAAAA==.',
Re='Realhelz:BAAANQADCgcICQAAAA==.Redsamilf:BAAANQADCgcIGAAAAA==.Rekka:BAAANQADCgYICgAAAA==.Requizik:BAAANQADCgYIDgAAAA==.Resaana:BAAANQADCgcIDgABNQADCggICwABAAAAAA==.Restofarian:BAAANQAECggIEAAAAA==.',
Rh='Rhaegaria:BAAANQADCgEIAQAAAA==.Rhaegarina:BAAANQADCgQIBAAAAA==.Rhagnor:BAAANQAECgYICAAAAA==.',
Ri='Rianon:BAAANQADCgEIAQABNQAECgUIBgABAAAAAA==.Rizzy:BAAANQAECgYIEQAAAA==.',
Ro='Rotinshot:BAAANQAECggIDwAAAA==.',
Ru='Rutikee:BAAANQAECgUICQAAAA==.',
Ry='Ryomensukuna:BAAANQAFFAIIAgAAAA==.',
Sa='Sandrill:BAAANQAECgMIBAABNQAECgYICAABAAAAAA==.Savior:BAAANQADCggIFgAAAA==.',
Sc='Scrabble:BAAANQADCggICAAAAA==.',
Se='Seamisty:BAAANQADCgEIAQAAAA==.Seastorm:BAAANQADCgMIAwAAAA==.Seizon:BAAANQAECgEIAQAAAA==.Serom:BAAANQADCggIGwAAAA==.Sethic:BAAANQADCgYIBAAAAA==.',
Sh='Shadowguidem:BAAANQADCgMIAwAAAA==.Sharkie:BAAANQADCggICQAAAA==.Sherunn:BAAANQADCggIFgAAAA==.Shimakaze:BAAANQAECgQIBQAAAA==.Shmitty:BAAANQAECgYICwABNQAECgQIBAABAAAAAA==.Shooters:BAAANQAECgMIBAAAAA==.Shymistress:BAAANQAECgUICQAAAA==.Shåmmy:BAAANQAECgYIDAAAAA==.',
Si='Sindralea:BAAANQADCggIHAAAAA==.',
Sk='Skiá:BAAANQAECgUICAAAAA==.',
Sp='Spareparts:BAAANQADCgIIAgABNQADCgYIDAABAAAAAA==.Splaat:BAAANQADCgIIAgAAAA==.Splàsh:BAAANQAFFAIIAgAAAA==.',
St='Stoneboot:BAAANQAECgQICAAAAA==.Stonefist:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Stormfox:BAAANQAECgQIBwAAAA==.Strawhat:BAAANQAECgIIAwAAAA==.',
Su='Suljin:BAAANQADCgUIBQAAAA==.Sumaria:BAAANQADCggIEwAAAA==.Superman:BAAANQADCgMIAwAAAA==.',
Sw='Sweetvixen:BAAANQADCgYIDAAAAA==.',
Sy='Sylvanasthot:BAAANQADCgMIAwAAAA==.',
Ta='Tabiaia:BAAANQADCgIIAgAAAA==.Taler:BAAANQADCggICgAAAA==.Tannuk:BAAANQAECgUIBwAAAA==.Tauru:BAAANQADCgcICwAAAA==.',
Te='Tea:BAAANQADCgcIBwAAAA==.Teessedra:BAAANQADCgUIBQAAAA==.Terdanator:BAAANQAECgUICAAAAA==.',
Th='Thundaris:BAAANQABCgMIAwAAAA==.',
Ti='Tiari:BAAANQAECgQICAAAAA==.Tidepod:BAAANQAECgEIAQAAAA==.',
Tr='Tridius:BAAANQAECgUIEAAAAA==.Trixx:BAAANQAECgQIBgAAAA==.',
Tu='Tuffcracker:BAAANQADCgYIEgAAAA==.Turdanator:BAAANQADCgYIBgAAAA==.',
Tw='Twinturboj:BAAANQADCgQIBAAAAA==.Twittle:BAAANQAECgMIAwAAAA==.',
Ty='Tylovastus:BAAANQAECgEIAQAAAA==.Tyrmin:BAAANQAECgEIAQAAAA==.',
Ub='Ube:BAAANQAECgUIBwAAAA==.',
Ur='Uriah:BAAANQADCggIGwAAAA==.Ursúla:BAAANQADCgMIAwABNQAECgkJGQACAGAdAA==.',
Ut='Utherr:BAAANQADCggIEAAAAA==.',
Va='Valaravaus:BAAANQADCgcIBwAAAA==.Varjo:BAAANQADCgQIBAAAAA==.Vashirr:BAAANQADCgIIAgAAAA==.',
Ve='Vergus:BAAANQADCgYIBgAAAA==.',
Vi='Viral:BAAANQAECggIBwAAAA==.',
Vo='Vonnie:BAAANQADCggIFwAAAA==.',
['Vé']='Végeta:BAAANQADCgUIBQABNQAECgYIDQABAAAAAA==.',
Wa='Wardwhelp:BAAANQADCggIEQAAAA==.',
Wo='Wooloo:BAACNQAFFIEKAAQLAAYJohxQAwBeAQALAAQJpxlQAwBeAQAMAAEJbiM1CABsAAANAAEJxCELAgBkAAA1AAQKgRoAAwwACQn7IDUKACsCAAsABQmYJgcrADICAAwABwlyGzUKACsCAAAA.',
Wy='Wynona:BAAANQAECgcIDQAAAA==.',
Xa='Xanagore:BAAANQAECgQICgAAAA==.',
Xk='Xkwon:BAAANQADCggIDAAAAA==.Xkwøn:BAABNQAECoEdAAIOAAkJEx6WAQAdAwAOAAkJEx6WAQAdAwAAAA==.Xkwønn:BAAANQADCgUICAAAAA==.Xkwønxø:BAAANQAECgQIBgAAAA==.',
Xu='Xunie:BAAANQADCgcIDgAAAA==.',
Yl='Yloh:BAAANQAECgYICgAAAA==.',
Yo='Yoquiere:BAAANQADCgYICQAAAA==.',
Za='Zaisplash:BAAANQAECgMIAwAAAA==.Zana:BAAANQADCgUIBQAAAA==.Zaphi:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Zb='Zbrute:BAAANQAECgEIAQAAAA==.',
Ze='Zees:BAAANQAECgEIAQAAAA==.',
Zo='Zokohjin:BAAANQAFFAEIAQAAAA==.',
Zu='Zulpher:BAAANQADCgQICgAAAA==.',
['Ðe']='Ðepz:BAAANQAECgUICQAAAA==.',
['Øk']='Økwøn:BAAANQAECgcIDgAAAA==.',
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
