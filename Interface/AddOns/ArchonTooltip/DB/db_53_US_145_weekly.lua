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

local lookup = {'Unknown-Unknown','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Hunter-Marksmanship','Warrior-Arms','DeathKnight-Frost',}
local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaliara:BAAANQADCgUIBQAAAA==.',
Ac='Ackreser:BAAANQADCgUIBQAAAA==.',
Ae='Aeven:BAAANQADCgEIAQABNQAECgYICQABAAAAAA==.',
Ai='Aidan:BAABNQAFFIEKAAMCAAcJ9yMBAACtAgACAAYJWyUBAACtAgADAAEJoBubAABwAAAAAA==.Aidhan:BAAANQAECggIEAABNQAFFAcICgACAPcjAA==.Aileron:BAAANQAECgYICQAAAA==.',
Al='Alcore:BAAANQADCgMIAwAAAA==.Aldrigor:BAAANQADCggIDAAAAA==.Alett:BAAANQADCgUIBwAAAA==.Alivathus:BAAANQAECgUIBwAAAA==.Alsong:BAAANQADCgQIBwAAAA==.Alvart:BAAANQADCgQIBgAAAA==.',
Am='Ambervoid:BAAANQAECgIIAgAAAA==.',
Ar='Arbark:BAAANQAECgcIDAAAAA==.Ardone:BAAANQABCgIIAgAAAA==.Arkadis:BAAANQADCgMIAgAAAA==.Armina:BAAANQADCgMIAwAAAA==.Arrothin:BAAANQABCgQIBAAAAA==.',
As='Asdanoth:BAAANQADCgMIAwAAAA==.Ashenbrawl:BAAANQAECgYIBgAAAA==.Ashenclaw:BAAANQADCgYICgAAAA==.Aspinks:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.',
Au='Auxie:BAAANQAECgIIAgAAAA==.',
Av='Avatipup:BAAANQADCgIIAgAAAA==.',
Aw='Aweinon:BAAANQADCgQIBAAAAA==.',
Ay='Aydin:BAAANQAFFAMIAwABNQAFFAcICgACAPcjAA==.Aylan:BAAANQADCgIIAgAAAA==.',
Az='Azelous:BAAANQADCggICAABNQAECgUIBwABAAAAAA==.Azumaa:BAAANQADCgYICgAAAA==.Azureth:BAAANQADCgEIAQAAAA==.',
Ba='Bainironwind:BAAANQADCgUIBQAAAA==.Baiwushi:BAAANQADCggICgAAAA==.',
Be='Becbec:BAAANQADCgYICgAAAA==.Ben:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Bestricer:BAAANQAECgIIAgABNQAFFAYICAACAJcRAA==.',
Bi='Biggles:BAEANQAECgcIDQAAAA==.Bighuntarizo:BAAANQADCggICAAAAA==.',
Bl='Blobney:BAAANQAFFAIIAgAAAA==.Bluechip:BAAANQAECgEIAQAAAA==.Blueeagle:BAAANQAECgYICwAAAA==.Bluespell:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.',
Bo='Bolts:BAAANQADCgYIDQAAAA==.',
Br='Broaahhaha:BAAANQADCgUIBQAAAA==.',
Bu='Butterflyy:BAAANQAECgQIBAAAAA==.',
Ca='Caelena:BAAANQADCgcIDAAAAA==.',
Ce='Celestial:BAAANQAECgMIAwAAAA==.',
Ch='Chilltest:BAAANQAECgQIBgAAAA==.Chronobacon:BAAANQADCgYICgABNQAECgUIBQABAAAAAA==.Chupacabra:BAAANQADCgYICgAAAA==.Chuyz:BAAANQAECgEIAQAAAA==.Chuyzz:BAAANQAECgEIAQAAAA==.',
Cl='Clickchi:BAAANQADCgMIAwAAAA==.Cloudwarrior:BAAANQADCgEIAQABNQAFFAIIAgABAAAAAA==.',
Co='Cokediet:BAAANQADCgIIAgAAAA==.Cooties:BAAANQADCgUIBQAAAA==.Cordeliaa:BAAANQADCgYIBgAAAA==.Coven:BAAANQADCgUICQAAAA==.',
Cr='Crunch:BAAANQAECgQIBQAAAA==.',
Cy='Cynikka:BAAANQAECgMIAwAAAA==.Cynthor:BAAANQADCgcICgAAAA==.',
Da='Daghahi:BAAANQAECgEIAQAAAA==.Dalethyr:BAAANQADCgYICwAAAA==.Darkseid:BAAANQADCgQIBAAAAA==.Dawuffman:BAAANQADCggIEAAAAA==.',
De='Deathdruid:BAAANQADCggIDgAAAA==.Delmus:BAAANQADCgUICQABNQADCgcIDgABAAAAAA==.Delphinae:BAAANQADCgYICgAAAA==.Demontwink:BAAANQADCggIDwAAAA==.Devera:BAAANQAECggIEAAAAA==.',
Di='Dinkylock:BAAANQADCgUICAAAAA==.Dirtykahuna:BAAANQADCgYIDAAAAA==.Discosticks:BAAANQADCgUIBQAAAA==.Distress:BAAANQADCgUIBQAAAA==.',
Do='Dojoshaman:BAAANQAECgQIBAAAAA==.Doodman:BAAANQADCgIIAgAAAA==.',
Dr='Dragondeez:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Drwn:BAAANQADCggICAAAAA==.',
Dw='Dwelknarr:BAAANQADCgYICAAAAA==.',
Ea='Eadric:BAAANQADCgYICAAAAA==.Earendur:BAAANQADCgUICQAAAA==.Earthfury:BAAANQADCggIEAAAAA==.',
Ed='Edallen:BAAANQADCggIDgAAAA==.',
Ee='Eelyroc:BAAANQADCgMIAwAAAA==.',
El='Elbrujo:BAAANQAECgEIAQAAAA==.',
Em='Emaytete:BAAANQADCgQIBAAAAA==.Emayteteheww:BAAANQADCgcICAAAAA==.Emillyra:BAAANQADCgUICAAAAA==.',
Ep='Ephemra:BAAANQADCggIBwAAAA==.',
Es='Esteban:BAAANQADCggIDAAAAA==.',
Fa='Famidore:BAAANQADCgIIBAAAAA==.',
Fe='Felflamel:BAAANQAECgMIAwAAAA==.Ferdinan:BAAANQAECgEIAQAAAA==.',
Fl='Flashter:BAAANQADCgcIBwAAAA==.Fluffycuddle:BAAANQADCgUICQAAAA==.',
Fo='Forrealzies:BAAANQADCgYICAAAAA==.Fortunato:BAAANQADCgEIAQAAAA==.',
Fr='Frankhs:BAAANQADCgQIBAAAAA==.',
Ga='Galdrel:BAAANQADCgYIBQAAAA==.Gallince:BAAANQAECgcIBwAAAA==.Garbich:BAAANQADCgEIAgAAAA==.Gary:BAAANQADCgcIBwAAAA==.',
Ge='Gerhart:BAAANQADCgYICgAAAA==.',
Gh='Ghostsham:BAABNQAFFIEHAAIEAAYJRhYMAAA9AgAEAAYJRhYMAAA9AgAAAA==.Ghðst:BAAANQADCgYIBgABNQAFFAYIBwAEAEYWAA==.',
Gl='Glizzyman:BAAANQAECgIIAgAAAA==.',
Go='Go:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Goldoran:BAAANQADCgIIAgAAAA==.Gonette:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Goniff:BAAANQAECgMIAwAAAA==.Goransk:BAAANQADCgYIBgAAAA==.',
Gr='Gracelious:BAAANQAECgUIBwAAAA==.Graebeard:BAAANQADCgQIBgAAAA==.Graehame:BAAANQADCgQIBAAAAA==.Greyshadow:BAAANQADCgUIBQAAAA==.Grüb:BAAANQADCgUICQAAAA==.',
Gu='Guntran:BAAANQAECgQIBAAAAA==.Gurthock:BAAANQAECgQIBAAAAA==.',
Gw='Gwenixx:BAAANQADCgUICQAAAA==.',
He='Headhuntin:BAAANQADCggICwAAAA==.Heatfang:BAAANQADCgUIBwAAAA==.Hellione:BAAANQADCgYIDAAAAA==.Hellmaree:BAAANQADCgEIAQAAAA==.Helltest:BAAANQADCgQIBAAAAA==.',
Ho='Holywater:BAAANQAECgEIAQAAAA==.Honkinhammer:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Hotdogman:BAABNQAFFIEHAAIFAAUJJA98AACtAQAFAAUJJA98AACtAQABNQADCgIIAgABAAAAAA==.Hotdumpling:BAAANQADCgMIAgAAAA==.',
Hy='Hyle:BAAANQADCggIDgAAAA==.',
Il='Illuminator:BAAANQADCgUICQAAAA==.',
In='Inspectadeck:BAAANQAECgcIDAAAAA==.',
Is='Istariel:BAAANQAECgIIAgABNQAFFAYIBwAEAEYWAA==.',
It='Ithoron:BAAANQAECgIIAgAAAA==.',
Ja='Jazu:BAAANQADCggIDgAAAA==.',
Je='Jerks:BAAANQAECgIIAgAAAA==.',
Jo='Jost:BAAANQADCgMIAwABNQAECgUIBgABAAAAAA==.Joval:BAAANQADCgUICQAAAA==.Jozeph:BAAANQAECgEIAQAAAA==.',
['Jà']='Jàmie:BAAANQADCgEIAQAAAA==.',
Ka='Kaalar:BAAANQAECgIIAgAAAA==.Kamoura:BAAANQAECgEIAQAAAA==.Kapeta:BAAANQADCgYIBwAAAA==.Karmen:BAAANQAECgcIDQAAAA==.Karnatron:BAAANQADCgUICQAAAA==.Karnvoid:BAAANQADCgIIAgABNQADCgUICQABAAAAAA==.Katalain:BAAANQADCggICQABNQAECgUIBwABAAAAAA==.',
Ke='Keattz:BAABNQAFFIEGAAIGAAQJCg/2AABjAQAGAAQJCg/2AABjAQABNQAECgQIBgABAAAAAA==.Keattzxd:BAAANQAECgQIBgAAAA==.Keedill:BAAANQAECgMIAwAAAA==.Keelu:BAAANQADCgEIAQAAAA==.Keggerz:BAAANQADCgYIBgAAAA==.Kennagi:BAAANQAECgIIAgAAAA==.Kenshunterl:BAAANQADCgYICgAAAA==.',
Kh='Khanzen:BAAANQADCgcIBwAAAA==.Khovastis:BAAANQAECgcIDQAAAA==.',
Ki='Kianll:BAAANQADCgIIAgAAAA==.Kitchntabls:BAAANQAECggIDQAAAA==.',
Kj='Kjirou:BAAANQAECgIIAgAAAA==.',
Ko='Koenji:BAAANQAECgcICgAAAA==.Korgrim:BAAANQADCgUIBQAAAA==.',
Ku='Kurannas:BAAANQADCggICAAAAA==.',
Ky='Kymal:BAAANQADCgYIBgAAAA==.Kyndel:BAAANQADCgQIBwAAAA==.Kyndrah:BAAANQAECgUIBwABNQADCgQIBwABAAAAAA==.',
['Kä']='Käne:BAAANQADCggIDgAAAA==.',
['Kì']='Kìn:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
['Kí']='Kín:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
La='Lableue:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.Lavacask:BAAANQADCgUICAAAAA==.',
Le='Leodk:BAAANQAFFAEIAQABNQAECggIDQAHAHIiAA==.Lerann:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Levey:BAAANQAECgUIBgAAAA==.',
Li='Lict:BAAANQAECgYICQABNQADCggIDwABAAAAAA==.Liekki:BAAANQADCgEIAQABNQADCgYICAABAAAAAA==.Lillea:BAAANQADCgcIDAAAAA==.Listurfiend:BAAANQADCgIIAgAAAA==.',
Lo='Loktalaan:BAAANQAECgcIDAAAAA==.',
Lu='Luan:BAAANQAECgQIBAAAAA==.Lucien:BAAANQAECgUIBwAAAA==.Lute:BAAANQAECgMIAwAAAA==.',
Ly='Lyfeguard:BAAANQADCggIDgAAAA==.',
Ma='Machoke:BAAANQADCgYIDQAAAA==.Mahito:BAAANQAECgQIBAAAAA==.Malenia:BAAANQAECgYICwAAAA==.Malume:BAAANQADCgYICAAAAA==.Malístra:BAAANQADCgcICAAAAA==.Manaless:BAAANQAECgEIAQABNQAECggIDQAHAHIiAA==.Marderer:BAAANQAECgEIAQAAAA==.Masakari:BAAANQAECgEIAQAAAA==.Materia:BAAANQADCgUIBQAAAA==.Mathmagician:BAAANQAECgIIAgAAAA==.Maulfarm:BAAANQAECgcICgAAAA==.Mazzlock:BAAANQADCgYICgAAAA==.',
Me='Megameow:BAAANQAECgUIBQAAAA==.Mercuria:BAAANQADCgMIAwAAAA==.',
Mi='Mitrixx:BAAANQADCgcIDAAAAA==.',
Mo='Mobius:BAAANQADCgQIBAAAAA==.Moonthorn:BAAANQADCgYICwAAAA==.Mort:BAAANQADCgYICgAAAA==.Moxou:BAAANQAECgEIAQAAAA==.Moxxou:BAAANQAFFAEIAQAAAA==.',
Mu='Mulch:BAAANQAECgMIAwAAAA==.',
My='Mybelle:BAAANQADCgIIAgAAAA==.Mysticle:BAAANQADCgMIAwAAAA==.Mythaltis:BAAANQAECgEIAQAAAA==.',
Na='Naizhruk:BAAANQADCgEIAQAAAA==.Nall:BAAANQADCgIIAgAAAA==.Naoh:BAAANQADCgQIBAAAAA==.Narache:BAAANQADCgYIBwAAAA==.Naul:BAAANQAECgMIAwAAAA==.Naull:BAAANQAECgEIAgAAAA==.Naysayer:BAAANQADCgEIAQAAAA==.',
Ne='Necrokai:BAAANQADCgYIBgAAAA==.Necroscourge:BAAANQADCggICAABNQADCgYIBgABAAAAAA==.Neighter:BAAANQADCgcIDAAAAA==.Nerevar:BAAANQADCgUIBwAAAA==.Nevergoback:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ni='Ninejuanjuan:BAAANQAECgMIAwAAAA==.Nishikienrai:BAAANQADCgUIBQAAAA==.',
No='Nochit:BAAANQAECggIDgAAAA==.Noctula:BAAANQAECgIIAgABNQADCgYIBgABAAAAAA==.Norne:BAAANQAECgYIBgAAAA==.Nowfaleena:BAAANQADCgEIAQAAAA==.',
Ny='Nytkiller:BAAANQADCgUIBQAAAA==.Nyzul:BAAANQADCgcIDgAAAA==.',
Od='Odlinn:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
On='Onlyhorns:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.',
Op='Opalia:BAAANQADCgcIDAAAAA==.Opallea:BAAANQADCgUICQABNQADCgUICQABAAAAAA==.',
Or='Orch:BAAANQADCggIDgAAAQ==.',
Ov='Overclocked:BAAANQAECgQIBAAAAA==.',
Pa='Paddington:BAAANQADCgcICAAAAA==.Pahbi:BAAANQADCgEIAQAAAA==.Paul:BAAANQAECgEIAQAAAA==.',
Pe='Pendojo:BAAANQADCgMIAwAAAA==.Pendomage:BAAANQADCgMIAwAAAA==.',
Pi='Pip:BAAANQAECggIEAABNQAECggIEAABAAAAAA==.Pipium:BAAANQAECggIEAABNQAECggIEAABAAAAAA==.',
Po='Pookiehandz:BAAANQAECgEIAQAAAA==.Porpul:BAAANQAECgIIAgAAAA==.',
Pr='Prophet:BAAANQADCgcIBwAAAA==.',
Pu='Purples:BAAANQADCgQIBAAAAA==.',
Ra='Raikan:BAAANQAECgIIAgAAAA==.Rainwater:BAAANQADCgEIAQAAAA==.Raisyns:BAAANQAECgcIDQAAAA==.Rammic:BAAANQADCgIIAgAAAA==.Randstohl:BAAANQADCgYIBgAAAA==.Ratakhan:BAAANQADCgUIBQAAAA==.Raulothim:BAAANQADCggIDgAAAA==.',
Re='Rebell:BAAANQAECgIIAgAAAA==.Reny:BAAANQADCgYICgAAAA==.Repentance:BAAANQADCgEIAQABNQADCgYIBwABAAAAAA==.Retribussy:BAAANQAECgEIAQAAAA==.',
Ri='Ricemachinex:BAAANQAECgQIBAABNQAFFAYICAACAJcRAA==.',
Ro='Rocthar:BAAANQAECgIIAgAAAA==.Romarus:BAAANQADCgYIBgAAAA==.Romeoposter:BAAANQADCgYIBgAAAA==.',
Ru='Rukarazyll:BAAANQADCgYICwAAAA==.Rumble:BAAANQADCgIIAgAAAA==.',
Ry='Ryunohige:BAAANQADCggICAAAAA==.',
['Rú']='Rúúsh:BAAANQADCgcICAAAAA==.',
Sa='Safeword:BAAANQADCgMIAwAAAA==.Saihua:BAAANQADCgYIBgAAAA==.Saintjonn:BAAANQAECgYIBwAAAA==.Sarthdidius:BAAANQAECgIIAgAAAA==.Sassparilluh:BAAANQADCgUICQAAAA==.Savalla:BAAANQADCgYIBgAAAA==.',
Sc='Schadenfreud:BAAANQAECgEIAQAAAA==.Scholoman:BAAANQADCggIDgAAAA==.Scratchbelly:BAAANQADCgUIBQAAAA==.',
Se='Senpai:BAAANQAECgcIDAAAAA==.Seoli:BAAANQADCgIIAgAAAA==.',
Sh='Shalanthra:BAAANQADCgMIAwAAAA==.Shamallow:BAAANQADCgQIBAAAAA==.Shammunition:BAAANQAECgQIBgAAAA==.Shartz:BAAANQADCgcIDAAAAA==.Shaysa:BAEANQADCggIDwAAAA==.Sheraa:BAAANQADCgUICAAAAA==.Shinigamisan:BAAANQAECgEIAQAAAA==.Shynox:BAAANQADCgYIBgAAAA==.',
Si='Sinnerchrono:BAAANQADCggIBwAAAA==.Sinnwoo:BAAANQABCgQIBgAAAA==.Sitharco:BAAANQADCgcIDAAAAA==.',
Sm='Smorc:BAAANQADCgMIAwAAAA==.',
Sn='Snackwitch:BAAANQADCgYICgAAAA==.Sneaki:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
So='Sommin:BAAANQADCgQIBAAAAA==.Sorakah:BAAANQADCgYIBgAAAA==.Soulviper:BAAANQAECgYICwAAAA==.',
Sp='Spankmyflank:BAAANQADCgUICQAAAA==.Spurb:BAAANQADCgUICQAAAA==.',
Sq='Squaleon:BAAANQADCgQIBAAAAA==.',
St='Stabbyfinch:BAAANQADCgYIBgAAAA==.Stonestriker:BAAANQADCgYICgAAAA==.Stooben:BAAANQAECgMIAwAAAA==.Sturge:BAAANQADCgUIBwAAAA==.',
Su='Supahsayajin:BAAANQAECgUICQABNQABCgIIAgABAAAAAA==.',
Sw='Sweetbee:BAAANQADCgcIDAAAAA==.Swole:BAAANQAECgQIBQAAAA==.',
Sy='Syanalody:BAAANQADCgUICQAAAA==.Sylenn:BAAANQADCgMIAwAAAA==.Syn:BAAANQAECgEIAQAAAA==.Synchro:BAAANQADCgQIBAAAAA==.',
Ta='Tanstaafl:BAAANQAECgIIAgAAAA==.Taralom:BAAANQADCgYICgAAAA==.Taz:BAEANQAECgYIBQAAAA==.',
Te='Tenebrix:BAAANQAECgEIAQAAAA==.',
Th='Thadex:BAAANQAECgQIBAAAAA==.Thedood:BAAANQADCgYIBgAAAA==.Theldrid:BAAANQAECgQIBQAAAA==.Thepallyguy:BAAANQADCgcIDAABNQAECgEIAQABAAAAAA==.Thepriestguy:BAAANQAECgEIAQAAAA==.Theralethia:BAAANQADCgEIAQAAAA==.Therian:BAAANQADCgIIAgAAAA==.Thorseas:BAAANQAECgEIAQAAAA==.',
Ti='Tirissa:BAAANQADCgEIAQAAAA==.',
To='Tooyoo:BAAANQAECgQIBAAAAA==.Torpedotaka:BAAANQAECgMIBAAAAA==.',
Tp='Tpala:BAAANQAECgIIAwAAAA==.',
Tr='Triggerfarm:BAAANQADCgcIDAAAAA==.Tristis:BAAANQADCgUIBQAAAA==.',
Tu='Turthunt:BAAANQAFFAEIAQAAAA==.',
Ty='Tyesham:BAAANQADCgMIAwABNQADCgYIBwABAAAAAA==.Tyice:BAAANQADCgYIBwAAAA==.',
Va='Valaidpriest:BAAANQAECgIIAgAAAA==.Valoth:BAAANQADCgUICAAAAA==.Vanelura:BAAANQADCgUIBwAAAA==.',
Ve='Velorth:BAAANQADCgUIBQAAAA==.',
Vr='Vrahmageddon:BAAANQADCgYICgAAAA==.',
Vy='Vynlorin:BAAANQAECggIDgAAAA==.',
Wa='Wahstella:BAAANQAFFAMIBAAAAA==.Waraight:BAAANQAFFAIIAgAAAA==.Waterdroplet:BAAANQADCgMIAwAAAA==.',
Wh='Whodofthunk:BAAANQADCgUIBwAAAA==.',
Wi='Wighttrash:BAAANQAECgQIBAABNQADCggICAABAAAAAA==.Wilferth:BAAANQAECgYICgAAAA==.Wirl:BAAANQADCggICAAAAA==.',
Wo='Woozi:BAAANQAECgEIAQAAAA==.',
Wr='Wrinklz:BAAANQAECgQIBQAAAA==.',
Xa='Xavierson:BAAANQADCgUICQAAAA==.',
Xi='Xilone:BAAANQADCgUICQAAAA==.',
Ya='Yangchengfu:BAAANQADCgYIBgAAAA==.',
Yi='Yi:BAAANQADCggIDwAAAA==.',
Za='Zaaga:BAAANQADCggIDQAAAA==.Zamon:BAAANQADCgUIBQAAAA==.Zamyk:BAAANQADCgIIAgAAAA==.Zaqor:BAAANQABCgIIAgAAAA==.Zarf:BAAANQAECgMIAwAAAA==.Zayra:BAAANQADCgUIBQAAAA==.',
Ze='Zeld:BAAANQAECgEIAQAAAA==.Zelgius:BAAANQAECgQIBAAAAA==.Zenfel:BAAANQADCggIDgAAAA==.',
Zh='Zhulee:BAAANQAECgEIAQAAAA==.',
Zi='Zikaja:BAAANQADCggICwABNQAECggIDgABAAAAAA==.Zir:BAAANQAECgEIAQAAAA==.',
Zo='Zoark:BAAANQADCgUICAAAAA==.Zorgap:BAAANQADCggIDgAAAA==.',
Zu='Zuggwithin:BAAANQADCgUIBwAAAA==.',
Zy='Zygo:BAAANQAECgEIAQAAAA==.Zyprexen:BAAANQADCgUICAAAAA==.Zyprexius:BAAANQAECgIIAgAAAA==.',
['Ða']='Ðadgar:BAAANQADCgYICwAAAA==.',
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
