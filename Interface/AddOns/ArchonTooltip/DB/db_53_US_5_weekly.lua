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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Warrior-Arms','Evoker-Devastation','Paladin-Holy','DeathKnight-Unholy','Rogue-Assassination','Druid-Feral','Evoker-Preservation','Warlock-Demonology','Mage-Arcane','Warlock-Destruction','DeathKnight-Blood','DeathKnight-Frost','Warrior-Protection','Warrior-Fury','Druid-Restoration','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Accost:BAAANQADCgcIDQAAAA==.Acronica:BAAANQADCggICwAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcICwAAAA==.Aknologia:BAAANQAECgQIBAABNQAECgYIBwABAAAAAA==.',
Al='Alecto:BAAANQAECgEIAgAAAA==.Allele:BAAANQADCggIEgAAAA==.',
Am='Amarah:BAAANQAFFAEIAQAAAA==.Ameilie:BAAANQAECgcIEQAAAA==.',
An='Anapuwae:BAAANQAECgQIDAAAAA==.Animehero:BAAANQAECgYIEAAAAA==.',
Ar='Arcant:BAAANQAECgQIBgAAAA==.Ardicov:BAAANQADCgQIBQAAAA==.Argadin:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.Argrekh:BAAANQAFFAEIAQAAAA==.Argrekt:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.Aridol:BAAANQADCgYIBgAAAA==.Aronna:BAAANQADCgYIBwAAAA==.Arosea:BAAANQADCgYIBgAAAA==.Arthaslk:BAABNQAECoEbAAMCAAkJpxf0KQBqAgACAAkJsBb0KQBqAgADAAIJBAk9MgBlAAABNQAECggIIgAEABUZAA==.Aryssol:BAAANQADCggIDgAAAA==.',
At='Ate:BAAANQAECgQICQABNQAECgQIDAABAAAAAA==.Attman:BAAANQAECggIEAAAAA==.',
Au='Auradawn:BAAANQADCgcIDwAAAA==.',
Ba='Baeator:BAAANQAECgEIAQABNQAFFAYICQAFAAkHAA==.',
Be='Bearmane:BAAANQAECgcIEQAAAA==.Beastarsfan:BAAANQAECgUIBwAAAA==.Behmow:BAAANQAECggIEQAAAA==.Belithel:BAAANQAECgQIBgABNQAECgYIBgABAAAAAA==.Bencreepin:BAAANQAECgIIAwAAAA==.Bernoulli:BAAANQAECgUICQAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Bis:BAAANQADCgUIBQABNQAECggIEwABAAAAAA==.',
Bl='Blessedxx:BAAANQAECgEIAQAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAACNQAFFIEKAAIGAAYJBhREAQANAgAGAAYJBhREAQANAgA1AAQKgRwAAgYACQm1GEAPAOwCAAYACQm1GEAPAOwCAAAA.',
Bo='Boopsnoopems:BAAANQADCggIFgAAAA==.',
Br='Bradcrit:BAAANQADCgEIAQAAAA==.',
Bu='Bubble:BAAANQAECgQIBAAAAA==.Burrfoot:BAAANQAECgIIAwAAAA==.Bustah:BAAANQAECgcICwABNQAECggIFwAHAC8cAA==.',
Bw='Bwoodmorgan:BAAANQAECgQIBAAAAA==.',
Ca='Calene:BAABNQAECoEoAAIIAAkJ5SBjAwBMAwAIAAkJ5SBjAwBMAwAAAA==.Casare:BAAANQADCgYIFAAAAA==.',
Ce='Celestinee:BAAANQADCgcICQAAAA==.Cenarian:BAAANQABCgQIBgAAAA==.',
Ch='Chape:BAABNQAECoEbAAMGAAkJURa5GACZAgAGAAkJURa5GACZAgACAAUJlBB9fQAjAQAAAA==.',
Ci='Cinderlee:BAAANQADCggIGgAAAA==.',
Co='Colexn:BAAANQAECgcIDwAAAA==.Cong:BAABNQAECoEUAAIEAAgJAxcQMAB+AgAEAAgJAxcQMAB+AgAAAA==.Corg:BAAANQADCgYIBgAAAA==.Cornchipz:BAAANQAECgYIBwAAAA==.',
Cr='Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Da='Daangalanng:BAAANQAECgQICwAAAA==.Daegra:BAAANQAECgYICwAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAAANQAECgcIEAAAAA==.',
De='Dealosed:BAAANQAECgcIEAAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathkilera:BAAANQADCgUIBwAAAA==.Delenn:BAABNQAECoEXAAIJAAgJERuDBACCAgAJAAgJERuDBACCAgAAAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgQIBwAAAA==.',
Di='Disastastab:BAAANQAECgcIEgAAAA==.Dive:BAAANQAECggIEwAAAA==.',
Do='Doogru:BAAANQAECgQICwAAAA==.Doogtwo:BAAANQADCggIFgABNQAECgQICwABAAAAAA==.Doryndoran:BAAANQADCgYIBwAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Dotsrock:BAAANQAECgIIAgAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAAANQAECggIDwAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgQIBQAAAA==.Draxx:BAAANQAECggIBwAAAA==.Dreammachine:BAAANQADCgQIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAAANQAECgMIBQAAAA==.Dräx:BAAANQAECggIDQAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAYICgAKAAAHAA==.',
Ea='Earthshocker:BAAANQAECgIIAgAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elmesia:BAAANQAECgMIAwAAAA==.Eloris:BAAANQAECgYICwAAAA==.Elpato:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.Elthyn:BAAANQADCgUIBQAAAA==.',
Em='Emachine:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Emeraldrin:BAAANQADCgEIAQAAAA==.Emz:BAAANQAECggIEwAAAA==.',
En='Eniar:BAAANQAECgEIAQAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgQIBAAAAA==.Eric:BAAANQAECgcIEAAAAA==.Eroninja:BAAANQADCgUIBwABNQAECgYIBgABAAAAAA==.Erín:BAAANQAECgEIAQAAAA==.',
Eu='Eurong:BAAANQAFFAEIAQAAAA==.',
Ez='Ezynuff:BAAANQAECgMIAwAAAA==.',
Fa='Fapple:BAAANQADCgQIBAABNQAECgYIDAABAAAAAA==.Fatesworn:BAAANQADCgcIBwAAAA==.Faïry:BAAANQAECgcIEwAAAA==.',
Fe='Felwyrm:BAABNQAECoEYAAILAAgJhBVZKABBAgALAAgJhBVZKABBAgAAAA==.',
Fo='Foragh:BAAANQAECgEIAQABNQAECgMIBgABAAAAAA==.Foxi:BAAANQADCggIEQABNQAECgQICQABAAAAAA==.',
Fr='Freakbeast:BAAANQAECgUIDQAAAA==.Fries:BAEANQADCgUIBQABNQAECggIBgABAAAAAA==.',
Fu='Fullkidney:BAAANQAFFAEIAQAAAA==.Funch:BAAANQAECgYIDQAAAA==.',
Ga='Gaefaeryn:BAAANQAECgYIDgAAAA==.Garonnaa:BAAANQAECgcIDwAAAA==.Garthel:BAAANQADCgYIDAAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAAANQAECgUICwAAAA==.',
Gi='Gingerlock:BAAANQAECgUIBQAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCggIDQAAAA==.',
Gr='Greka:BAAANQADCgcIGQAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAAANQAECgUICwAAAA==.',
['Gö']='Gözër:BAAANQADCgMIAwAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAECggIGAALAIQVAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgMIBQABAAAAAA==.Healhole:BAAANQAECgYICwAAAA==.Heàl:BAAANQAECgEIAgAAAA==.',
Hi='Hidolo:BAAANQADCgYIDAAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAAAAA==.',
Hy='Hylaina:BAAANQADCgYICgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCggIDgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYIDgAAAA==.',
It='Itiswhatitiz:BAAANQAECgYIDgAAAA==.Itsybityshiv:BAAANQAECgYIDAAAAA==.',
Jh='Jhani:BAAANQADCggIGwAAAA==.',
Ji='Jiu:BAAANQAECgQIBgABNQAECggIFwAHAC8cAA==.',
Jo='Joethemage:BAAANQAECgQIBgAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kamin:BAAANQAECgYIBgABNQAECgkJHQAMAEgdAA==.Kaykaypally:BAAANQAECgUIBwAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAAANQAECgYICwAAAA==.Kinji:BAAANQADCggIEAABNQAECgYIBgABAAAAAA==.',
Ko='Konfu:BAAANQADCgcIEQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgIIAwAAAA==.Kristysavage:BAAANQAECgQICgAAAA==.',
Ku='Kulaesca:BAABNQAECoEXAAMLAAkJ3xVaHACGAgALAAkJ3xVaHACGAgANAAEJ7QDqZQAjAAAAAA==.',
Ky='Kynar:BAACNQAFFIEKAAMOAAYJjxC7AwCAAQAOAAYJEQm7AwCAAQAPAAIJFhxbBACxAAA1AAQKgR0AAw8ACQnOJDEDAG4DAA8ACQnOJDEDAG4DAA4AAwkfFQZaAMUAAAAA.Kyua:BAAANQADCgcIBwAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Lambshot:BAAANQAECgYICAAAAA==.Lambsy:BAACNQAFFIELAAMEAAYJAw3KAgD1AQAEAAYJFAzKAgD1AQAQAAEJEAxGAwBDAAA1AAQKgR4AAwQACQl4Ik4NAF4DAAQACQl0Ik4NAF4DABEAAwkCEygRALsAAAAA.Lanamama:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Le='Lerat:BAAANQAECgQICAAAAA==.',
Li='Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAAANQAECgcIEgAAAA==.Lisanalgaib:BAAANQAECgYIEAAAAA==.Lizzimcguire:BAAANQAECgcIEwAAAA==.',
Lo='Lobobare:BAABNQAECoEbAAISAAgJ2x0uCgCUAgASAAgJ2x0uCgCUAgAAAA==.Loraen:BAAANQADCgcIDQAAAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAAANQAECgMIBgAAAA==.',
Ma='Maevora:BAAANQAECgEIAQAAAA==.Makaroni:BAAANQADCgUIBwAAAA==.Manticus:BAAANQADCgYICAAAAA==.Marni:BAAANQADCgQIBAAAAA==.Marsrover:BAAANQAECgIIAgABNQAFFAYICgAEAKYTAA==.Martel:BAAANQADCgQIBAAAAA==.Matroxx:BAABNQAECoEfAAITAAkJliI9AwBxAwATAAkJliI9AwBxAwAAAA==.',
Me='Meenoi:BAABNQAECoEXAAIHAAgJLxyrFACnAgAHAAgJLxyrFACnAgAAAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECggIFAAJAA0bAA==.Mimikyu:BAAANQABCgYIBgAAAA==.',
Mo='Moardotsnow:BAAANQAECgYIDAAAAA==.Moby:BAAANQAECgEIAgAAAA==.Moistmender:BAAANQADCgYIBgAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murridan:BAAANQAECgUIBgAAAA==.',
My='Mykaela:BAAANQADCgcIBwAAAA==.',
['Më']='Mëow:BAAANQAECgIIAgAAAA==.',
Na='Narrath:BAAANQADCgMIAwAAAA==.Nayalaah:BAAANQADCgcIBwAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nephelym:BAAANQAECgUIBwAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgMIAwAAAA==.Nirina:BAAANQADCggIFAAAAA==.',
No='Nohtil:BAAANQADCgMIBwAAAA==.Notstephen:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nut:BAAANQAECgQIDAAAAA==.',
Nw='Nwalliance:BAAANQADCgIIAgAAAA==.',
['Nö']='Nötprepared:BAAANQADCgUICwABNQADCgYIDgABAAAAAA==.',
Oi='Oiflar:BAAANQAECgQICQABNQAECgYIDAABAAAAAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggIEAABNQAECggIEwABAAAAAA==.Omnipotent:BAAANQADCggICAAAAA==.',
On='Onepavo:BAAANQAECgIIAwAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.Oogrikusk:BAAANQADCgIIAgAAAA==.',
Op='Oppose:BAAANQAECgQIBAAAAA==.',
Or='Orexion:BAAANQAECgQIBAAAAA==.Ormagöden:BAAANQAECgYIDAAAAA==.',
Pa='Palladean:BAAANQAECgIIAgAAAA==.Palphen:BAAANQAECgYICwAAAA==.Pastasauce:BAAANQAECgQICwAAAA==.',
Pe='Pegero:BAAANQADCgYIDQABNQAECggICQABAAAAAA==.Penelohpe:BAABNQAECoEdAAIMAAkJSB23LQDaAgAMAAkJSB23LQDaAgAAAA==.',
Ph='Phatt:BAAANQADCgYIBgAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAEBNQAECoEWAAMLAAkJbSCTFQC2AgALAAcJySKTFQC2AgANAAMJbxlPKgDvAAAAAA==.Phoondk:BAEANQAECgUICAABNQAECgkJFgALAG0gAA==.',
Pi='Piggy:BAAANQAECgEIAQAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pizzadriver:BAACNQAFFIEKAAIEAAYJphMfAgAdAgAEAAYJphMfAgAdAgA1AAQKgRwAAwQACQl3JMsJAH4DAAQACQl3JMsJAH4DABEAAQnVI+UWAGIAAAAA.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgABAAAAAA==.Plata:BAAANQADCgQIBAAAAA==.',
Po='Poosicat:BAAANQABCgYIBgAAAA==.Poosycat:BAAANQABCgYICAAAAA==.',
Pr='Praytroxx:BAAANQAECgEIAQABNQAECgkJHwATAJYiAA==.Premonitions:BAAANQAECgIIAgAAAA==.Premune:BAAANQAECgYIEAAAAA==.Prion:BAAANQADCgQIBAAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgUICgAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAACNQAFFIELAAIUAAYJhgmpAQDmAQAUAAYJhgmpAQDmAQA1AAQKgR4AAxQACQk/En4mADECABQACQk/En4mADECABUABAlaFPpuAAEBAAAA.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAAANQAECgYIDAAAAA==.Rat:BAAANQAECggIEwAAAA==.Raynith:BAABNQAECoEUAAMJAAgJDRvfBwDbAQAWAAcJBRYFJgD6AQAJAAUJ2h3fBwDbAQAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAAANQAECgQIBQAAAA==.Reflex:BAAANQAECgIIAgAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAAANQAECgMIBAAAAA==.Retallica:BAAANQAECgEIAQAAAA==.Revali:BAABNQAECoEgAAMXAAkJNR7wGAC0AgAXAAkJCBvwGAC0AgAYAAcJHxlmGQD6AQAAAA==.Revelaen:BAAANQAECgEIAQABNQAECgkJIAAXADUeAA==.',
Ri='Rick:BAAANQAECggIEgAAAA==.',
Rm='Rmagep:BAAANQAECgUICQAAAA==.',
Ro='Roadhouse:BAAANQADCgQIBQAAAA==.Roshango:BAAANQADCgYIBgAAAA==.Rowgar:BAAANQAECgQIBAAAAA==.',
Ru='Rubenslik:BAAANQAECgYICgAAAA==.',
['Rá']='Ráts:BAAANQAECgQIBQAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAAANQADCgcIEAAAAA==.Saggypants:BAAANQAECgQIBAAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.Salamander:BAAANQAECgUIBgAAAA==.Sammel:BAAANQAECgQICgAAAA==.Sanari:BAAANQADCgUIBwABNQAECgYIBgABAAAAAA==.Sapphica:BAAANQADCgYICAAAAA==.Sathreina:BAAANQAECgcIDwAAAA==.',
Sc='Scaries:BAAANQAECgcICQAAAA==.Scootko:BAAANQAFFAIIAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sego:BAAANQADCgYIFAAAAA==.Severson:BAAANQAECgYICQAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Shadowisbad:BAAANQAECgYIDwAAAA==.Shadvoker:BAAANQAECgYICwAAAA==.Shamaneggs:BAAANQAECgEIAQAAAA==.Shamatroxx:BAAANQAECgYICwABNQAECgkJHwATAJYiAA==.Shamberry:BAAANQADCgIIAgAAAA==.Shambles:BAAANQADCgYICQAAAA==.Shieldwalle:BAAANQAECgMIBQAAAA==.Shotigolova:BAAANQADCgEIAQAAAA==.',
Si='Sidesalad:BAAANQADCgMIAwAAAA==.Sidric:BAAANQAECgQIBwAAAA==.Silre:BAAANQADCgcIEAAAAA==.Sim:BAAANQAECgcIDAAAAA==.Sipplex:BAAANQADCgQIBAAAAA==.',
Sl='Slander:BAAANQAECgQIBAAAAA==.Slanderous:BAAANQADCgEIAQAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECggIEQABAAAAAA==.',
So='Solokills:BAAANQADCgMIAwABNQAECggICQABAAAAAA==.Sophia:BAAANQAECgUICQAAAA==.Soundtrack:BAAANQADCgYICQABNQAECgIIAgABAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sq='Squab:BAAANQAECgcIEAAAAA==.Squanchy:BAAANQADCgYICAAAAA==.',
St='Stabbywixx:BAAANQAECgIIAgAAAA==.Starwnd:BAAANQAECgcIDgABNQAECgkJHAAZADYfAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stickman:BAAANQADCggICAABNQAECggIGAALAIQVAA==.Stillcreepin:BAAANQADCgcIDgAAAA==.Storienn:BAAANQAECgUIBwAAAA==.Stormzpaly:BAAANQAECgQIBQAAAA==.',
Su='Suküna:BAAANQADCggIFwAAAA==.Sunbur:BAAANQADCgQIBAAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAAANQAECgcICgAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAAANQAECgYIDgAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tassarosea:BAAANQADCggIEAABNQAECgcIEwABAAAAAA==.Tauloe:BAAANQADCggIFwAAAA==.Tayna:BAAANQABCgMIBAAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thomosaurus:BAAANQADCggIDAAAAA==.Thraly:BAAANQADCgYIBwAAAA==.Thunk:BAAANQAECgQIBAABNQAECgcIDAABAAAAAA==.',
Ti='Timdawg:BAAANQAECgQIBQABNQAFFAUICgALAO8SAA==.Timmolate:BAACNQAFFIEKAAMLAAUJ7xIhBAA/AQALAAQJlQ4hBAA/AQANAAIJwRfeAwC8AAA1AAQKgRwAAw0ACQlUIa0GAHoCAA0ACAkBF60GAHoCAAsABwm+GTguACECAAAA.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAAANQAECgcIEgAAAA==.',
Tr='Tristîtia:BAAANQAECgcICgAAAA==.',
Ts='Tsuma:BAAANQABCgIIAgAAAA==.Tsume:BAAANQADCgcIBwAAAA==.',
Tt='Ttomas:BAAANQAECgcICwAAAA==.',
Ty='Tyv:BAAANQAECgUICQAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQADCgYIDgAAAA==.Vallodon:BAAANQAECgUICAAAAA==.Vantablack:BAAANQABCgIIAgABNQABCgQICQABAAAAAA==.Vanwolfy:BAAANQAECgUIBgAAAA==.Vaylorian:BAAANQADCggIGAAAAA==.',
Ve='Velectran:BAAANQADCgUICgABNQAECgYIDgABAAAAAA==.Velorian:BAAANQADCgMIAwAAAA==.Velveeta:BAAANQAECgEIAQAAAA==.',
Vf='Vfacer:BAAANQADCgEIAQAAAA==.',
Vi='Vikav:BAAANQADCgIIAgAAAA==.',
Vo='Voodoomike:BAAANQAECgEIAQAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAAANQAECgMIAwAAAA==.Warrgodx:BAABNQAECoEiAAMEAAgJFRmGMAB8AgAEAAgJFRmGMAB8AgARAAEJygg6HAA3AAAAAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wo='Woogi:BAAANQADCgUIBQAAAA==.',
Wr='Wrongwookie:BAAANQAECgYIEAAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.',
Za='Zabada:BAAANQADCgcIDQAAAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zemsen:BAABNQAECoEeAAIMAAkJgh25JwDyAgAMAAkJgh25JwDyAgAAAA==.Zenyea:BAAANQAECgIIAwABNQAFFAEIAQABAAAAAA==.Zetta:BAAANQAFFAEIAQAAAA==.',
Zo='Zome:BAAANQAECgcIEwAAAA==.',
Zy='Zyndrael:BAAANQADCgQIBAAAAA==.',
['Èl']='Èlytz:BAAANQADCgYICQAAAA==.',
['Êl']='Êlytz:BAAANQADCggICAAAAA==.',
['ßl']='ßlue:BAAANQAECgEIAQAAAA==.',
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
