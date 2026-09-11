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

local lookup = {'Unknown-Unknown','Warrior-Arms','Evoker-Devastation','Paladin-Holy','Rogue-Assassination','DemonHunter-Devourer','Evoker-Preservation','Mage-Arcane','DeathKnight-Frost','DeathKnight-Blood','Warrior-Fury','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','Warlock-Destruction','Warlock-Demonology',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acronica:BAAANQADCgQIBAAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Ak='Akassa:BAAANQADCgcIBwAAAA==.Aknologia:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.',
Al='Alecto:BAAANQAECgEIAQAAAA==.Allele:BAAANQADCggIEgAAAA==.',
Am='Amarah:BAAANQAECgQICwAAAA==.Ameilie:BAAANQAECgYICQAAAA==.',
An='Anapuwae:BAAANQAECgQIBgAAAA==.Animehero:BAAANQAECgUICgAAAA==.',
Ar='Arcant:BAAANQAECgIIAgAAAA==.Ardicov:BAAANQADCgQIBQAAAA==.Argadin:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.Argrekh:BAAANQAECgcIDAAAAA==.Argrekt:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.Aridol:BAAANQADCgYIBgAAAA==.Aronna:BAAANQADCgIIAQAAAA==.Arthaslk:BAAANQAECggIEgABNQAECggIFgACAEUOAA==.Aryssol:BAAANQADCggICAAAAA==.',
At='Ate:BAAANQAECgQIBQABNQAECgQICQABAAAAAA==.Attman:BAAANQAECgcICQAAAA==.',
Au='Auradawn:BAAANQADCgUICAAAAA==.',
Ba='Baeator:BAAANQAECgEIAQABNQAECgkJGQADAJweAA==.',
Be='Bearmane:BAAANQAECgYICQAAAA==.Beastarsfan:BAAANQAECgQIBQAAAA==.Behmow:BAAANQAECgcIDgAAAA==.Belithel:BAAANQAECgQIBgAAAA==.Bencreepin:BAAANQAECgIIAgAAAA==.Bernoulli:BAAANQAECgQIBQAAAA==.',
Bi='Bigspitter:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
Bl='Blessedxx:BAAANQADCggIFAAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAABNQAECoEaAAIEAAkJ/RYPCwDeAgAEAAkJ/RYPCwDeAgAAAA==.',
Bo='Boopsnoopems:BAAANQADCgcIEgAAAA==.',
Br='Bradcrit:BAAANQADCgEIAQAAAA==.',
Bu='Bubble:BAAANQADCgQIBAAAAA==.Burrfoot:BAAANQAECgEIAQAAAA==.Bustah:BAAANQAECgYIBgABNQAECgcIDgABAAAAAA==.',
Bw='Bwoodmorgan:BAAANQADCggICAAAAA==.',
Ca='Calene:BAABNQAECoEYAAIFAAkJ+R68BADHAgAFAAkJ+R68BADHAgAAAA==.Casare:BAAANQADCgYIEAAAAA==.',
Ce='Celestinee:BAAANQADCgcICQAAAA==.Cenarian:BAAANQABCgQIBgAAAA==.',
Ch='Chape:BAAANQAFFAEIAQAAAA==.',
Ci='Cinderlee:BAAANQADCggIEgAAAA==.',
Co='Colexn:BAAANQAECgYICQAAAA==.Cong:BAAANQAECgcICAABNQAECgkJFwAGAIYgAA==.Cornchipz:BAAANQAECgYIBwAAAA==.',
Cr='Croski:BAAANQADCgEIAQAAAA==.Cryonidus:BAAANQAECgEIAQAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Da='Daangalanng:BAAANQAECgQICQAAAA==.Daegra:BAAANQAECgMIBQAAAA==.Dankkush:BAAANQADCgQIBAAAAA==.Darkacedia:BAAANQAECgUICQAAAA==.',
De='Dealosed:BAAANQAECgUICQAAAA==.Deathawolf:BAAANQAECgEIAQAAAA==.Deathkilera:BAAANQADCgQIBAAAAA==.Delenn:BAAANQAECgcIDgAAAA==.Derzy:BAAANQADCgIIAgAAAA==.Dewygirl:BAAANQADCgMIAwAAAA==.',
Di='Disastastab:BAAANQAECgcICwAAAA==.Dive:BAAANQAECggIEQAAAA==.',
Do='Doogru:BAAANQAECgQIBwAAAA==.Doogtwo:BAAANQADCgYIDgABNQAECgQIBwABAAAAAA==.Doryndoran:BAAANQADCgYIBwAAAA==.Dorynhashots:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.Dovah:BAAANQADCgIIAgAAAA==.',
Dr='Dragoneggs:BAAANQAECgYIBwAAAA==.Dragonforce:BAAANQADCggIEgAAAA==.Drakonutz:BAAANQAECgEIAQAAAA==.Draxx:BAAANQAECggIBwAAAA==.Dreammachine:BAAANQADCgQIBwAAAA==.Drjoel:BAAANQADCgcIEQAAAA==.Drunkenutz:BAAANQAECgIIAgAAAA==.Dräx:BAAANQAECggIBwAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.Dwightschrut:BAAANQADCgQIBAAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAUICAAHAKkHAA==.',
Ea='Earthshocker:BAAANQAECgIIAgAAAA==.',
El='Elenix:BAAANQAECgcIAQAAAA==.Elmesia:BAAANQADCgYICAAAAA==.Eloris:BAAANQAECgQIBQAAAA==.Elthyn:BAAANQADCgQIBAAAAA==.',
Em='Emachine:BAAANQADCggICAAAAA==.Emeraldrin:BAAANQADCgEIAQAAAA==.Emz:BAAANQAECggIDQAAAA==.',
En='Eniar:BAAANQAECgEIAQAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Erianda:BAAANQABCgIIAgAAAA==.Eric:BAAANQAECgYICQAAAA==.Eroninja:BAAANQADCgUIBwABNQAECgQIBgABAAAAAA==.Erín:BAAANQADCggIFAAAAA==.',
Eu='Eurong:BAAANQAECggIDwAAAA==.',
Ez='Ezynuff:BAAANQADCggIDgAAAA==.',
Fa='Faïry:BAAANQAECgcIDAAAAA==.',
Fe='Felwyrm:BAAANQAECgcIDgAAAA==.',
Fo='Foragh:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Foxi:BAAANQADCgcICQABNQAECgMIBQABAAAAAA==.',
Fr='Freakbeast:BAAANQAECgUICQAAAA==.Fries:BAEANQADCgUIBQABNQAECggIBgABAAAAAA==.',
Fu='Fullkidney:BAAANQAECgIIAgAAAA==.Funch:BAAANQAECgQIBwAAAA==.',
Ga='Gaefaeryn:BAAANQAECgQICQAAAA==.Garonnaa:BAAANQAECgYICgAAAA==.Garthel:BAAANQADCgUIBgAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAAANQAECgUICAAAAA==.',
Gi='Gingerlock:BAAANQADCggIDQAAAA==.Giyuu:BAAANQADCgUIBQAAAA==.',
Gn='Gnoblin:BAAANQADCgcIBwAAAA==.',
Gr='Greka:BAAANQADCgcIEgAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAAANQAECgQIBgAAAA==.',
Ha='Happyfriend:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.',
He='Healalle:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Healhole:BAAANQAECgQIBQAAAA==.Heàl:BAAANQAECgEIAQAAAA==.',
Hi='Hidolo:BAAANQADCgYIBwAAAA==.',
Hu='Hunterishard:BAAANQAECgQIBAAAAA==.',
Hy='Hylaina:BAAANQADCgYICgAAAA==.',
['Hô']='Hôlÿ:BAAANQADCgYIBgABNQADCgcIEgABAAAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgYICQAAAA==.',
It='Itiswhatitiz:BAAANQAECgQICAAAAA==.Itsybityshiv:BAAANQAECgMIBgAAAA==.',
Jh='Jhani:BAAANQADCggIEwAAAA==.',
Ji='Jiu:BAAANQAECgIIAgABNQAECgcIDgABAAAAAA==.',
Jo='Joethemage:BAAANQAECgIIAgAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kamin:BAAANQAECgYIBgABNQAECgkJFgAIADodAA==.Kaykaypally:BAAANQAECgEIAgAAAA==.',
Kh='Khybyr:BAAANQADCgMIAwAAAA==.',
Ki='Kidata:BAAANQAECgQIBQAAAA==.Kinji:BAAANQADCggIEAABNQAECgQIBgABAAAAAA==.',
Ko='Konfu:BAAANQADCgcIDQAAAA==.Korral:BAAANQADCggIDQAAAA==.',
Kr='Krispies:BAAANQAECgEIAQAAAA==.Kristysavage:BAAANQAECgQIBgAAAA==.',
Ku='Kulaesca:BAAANQAECgYIDQAAAA==.',
Ky='Kynar:BAABNQAECoEbAAMJAAkJziRAAQCTAwAJAAkJziRAAQCTAwAKAAEJThhXXwBIAAAAAA==.Kyua:BAAANQADCgcIBwAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Lambshot:BAAANQAECgQIBAAAAA==.Lambsy:BAABNQAECoEcAAMCAAkJiiH6BgB6AwACAAkJhiH6BgB6AwALAAMJAhM8DADHAAAAAA==.Lanamama:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Lanana:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Le='Lerat:BAAANQAECgQIBQAAAA==.',
Li='Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAAANQAECgcICwAAAA==.Lisanalgaib:BAAANQAECgUICgAAAA==.Lizzimcguire:BAAANQAECgcIDAAAAA==.',
Lo='Lobobare:BAABNQAECoEUAAIMAAgJOxw4BwCMAgAMAAgJOxw4BwCMAgAAAA==.Loraen:BAAANQADCgcICAAAAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAAANQAECgMIAwAAAA==.',
Ma='Maevora:BAAANQADCggIDQAAAA==.Makaroni:BAAANQADCgUIBwAAAA==.Manticus:BAAANQADCgYICAAAAA==.Marni:BAAANQADCgQIBAAAAA==.Martel:BAAANQADCgQIBAAAAA==.Matroxx:BAAANQAECggIEwAAAA==.',
Me='Meenoi:BAAANQAECgcIDgAAAA==.Mellotots:BAAANQABCgIIBAAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQAECgMIAwABNQAECggIDgABAAAAAA==.Mimikyu:BAAANQABCgYIBgAAAA==.',
Mo='Moardotsnow:BAAANQAECgQIBgAAAA==.Moby:BAAANQAECgEIAgAAAA==.Moistmender:BAAANQADCgYIBgAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
Mu='Murridan:BAAANQAECgEIAQAAAA==.',
My='Mykaela:BAAANQADCgcIBwAAAA==.',
['Më']='Mëow:BAAANQAECgIIAgAAAA==.',
Na='Narrath:BAAANQADCgMIAwAAAA==.Nayalaah:BAAANQADCgcIBwAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nephelym:BAAANQAECgMIAwAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nicolasmage:BAAANQABCgMIAwAAAA==.Nirina:BAAANQADCgcIEgAAAA==.',
No='Nohtil:BAAANQADCgMIBwAAAA==.Notstephen:BAAANQADCgYIBgABNQAECgMIBQABAAAAAA==.Nourishnutz:BAAANQADCgYIBgAAAA==.',
Nu='Nut:BAAANQAECgQICQAAAA==.',
Nw='Nwalliance:BAAANQADCgIIAgAAAA==.',
['Nö']='Nötprepared:BAAANQADCgUIBgABNQADCgYIDgABAAAAAA==.',
Oi='Oiflar:BAAANQAECgQIBQABNQAECgQIBgABAAAAAA==.',
Ol='Olangi:BAAANQAECgEIAQAAAA==.',
Om='Omnidh:BAAANQADCggIEAABNQAECgcIDgABAAAAAA==.Omnipotent:BAAANQADCggICAAAAA==.',
On='Onepavo:BAAANQAECgIIAwAAAA==.',
Oo='Oogie:BAAANQADCgYIBgAAAA==.',
Op='Oppose:BAAANQAECgEIAQAAAA==.',
Or='Orexion:BAAANQADCggIFwAAAA==.Ormagöden:BAAANQAECgUIBgAAAA==.',
Pa='Palladean:BAAANQADCgcIEQAAAA==.Palphen:BAAANQAECgMIBQAAAA==.Pastasauce:BAAANQAECgQIBwAAAA==.',
Pe='Pegero:BAAANQADCgYIDQABNQAECggIAwABAAAAAA==.Penelohpe:BAABNQAECoEWAAIIAAkJOh3fFwAIAwAIAAkJOh3fFwAIAwAAAA==.',
Ph='Phatt:BAAANQADCgYIBgAAAA==.Phoenixdrac:BAAANQADCggICQAAAA==.Phoon:BAAANQAECggIDQAAAA==.Phoondk:BAAANQAECgUICAABNQAECggIDQABAAAAAA==.',
Pi='Piggy:BAAANQAECgEIAQAAAA==.Pita:BAAANQABCgYIBgAAAA==.Pizzadriver:BAABNQAECoEaAAMCAAkJGCQDBQCWAwACAAkJGCQDBQCWAwALAAEJ1SPtEABnAAAAAA==.',
Pl='Plaguefist:BAAANQADCgcIBwABNQADCggIEgABAAAAAA==.Plata:BAAANQADCgQIBAAAAA==.',
Po='Poosycat:BAAANQABCgYICAAAAA==.',
Pr='Praytroxx:BAAANQADCgYICAABNQAECggIEwABAAAAAA==.Premonitions:BAAANQADCggICAAAAA==.Premune:BAAANQAECgUICgAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgQIBQAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Rahdek:BAAANQADCgMIAwAAAA==.Raine:BAABNQAECoEZAAMNAAkJtg1wHwAPAgANAAkJtg1wHwAPAgAOAAQJWhSfTgASAQAAAA==.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAAANQAECgQIBgAAAA==.Rat:BAAANQAECggIEwAAAA==.Raynith:BAAANQAECggIDgAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAAANQAECgMIAwAAAA==.Reflex:BAAANQADCggICAABNQADCggICAABAAAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQAECgIIAgAAAA==.Remulous:BAAANQAECgEIAQAAAA==.Retallica:BAAANQAECgEIAQAAAA==.Revali:BAABNQAECoEcAAMPAAkJxR3yCwDZAgAPAAkJCBvyCwDZAgAQAAYJ2RjDFwDCAQAAAA==.Revelaen:BAAANQAECgEIAQABNQAECgkJHAAPAMUdAA==.',
Ri='Rick:BAAANQAECgcIEAAAAA==.',
Rm='Rmagep:BAAANQAECgUIBwAAAA==.',
Ro='Roshango:BAAANQADCgYIBgAAAA==.Rowgar:BAAANQADCgUICAAAAA==.',
Ru='Rubenslik:BAAANQAECgQIBAAAAA==.',
['Rá']='Ráts:BAAANQAECgEIAQAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAAANQADCgYIDAAAAA==.Saggypants:BAAANQAECgQIBAAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgcICwABAAAAAA==.Sammel:BAAANQAECgQIBgAAAA==.Sanari:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Sapphica:BAAANQADCgQIBAAAAA==.Sathreina:BAAANQAECgYICQAAAA==.',
Sc='Scaries:BAAANQAECgIIAgAAAA==.Scootko:BAAANQAECgYIBgABNQAECgkJFwACAGoeAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sego:BAAANQADCgYIDgAAAA==.Sekimura:BAAANQAECgcICwAAAA==.Severson:BAAANQAECgMIAwAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Shadowisbad:BAAANQAECgUICQAAAA==.Shadvoker:BAAANQAECgQIBQAAAA==.Shamatroxx:BAAANQAECgUIBgABNQAECggIEwABAAAAAA==.Shamberry:BAAANQADCgIIAgAAAA==.Shambles:BAAANQADCgYICQAAAA==.Shieldwalle:BAAANQAECgIIAgAAAA==.',
Si='Sidric:BAAANQAECgMIAwAAAA==.Silre:BAAANQADCgYIDwAAAA==.Sim:BAAANQAECgQIBQAAAA==.Sipplex:BAAANQADCgQIBAAAAA==.',
Sl='Slander:BAAANQAECgQIBAAAAA==.Slanderous:BAAANQADCgEIAQAAAA==.',
Sn='Snuudle:BAAANQAECgcIDwABNQAECggICQABAAAAAA==.',
So='Solokills:BAAANQADCgMIAwABNQAECggIAwABAAAAAA==.Sophia:BAAANQAECgMIBAAAAA==.Soundtrack:BAAANQADCgYICAABNQADCggICAABAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sq='Squab:BAAANQAECgYICQAAAA==.Squanchy:BAAANQADCgYICAAAAA==.',
St='Stabbywixx:BAAANQADCgcIBwAAAA==.Starwnd:BAAANQAECgcIBwABNQAECgkJGAARACUdAA==.Sterìs:BAAANQAECgEIAQAAAA==.Stickman:BAAANQADCggICAABNQAECgcIDgABAAAAAA==.Stillcreepin:BAAANQADCgYICAAAAA==.Storienn:BAAANQAECgUIBQAAAA==.Stormzpaly:BAAANQAECgEIAQAAAA==.',
Su='Suküna:BAAANQADCggIEwAAAA==.Sunbur:BAAANQADCgQIBAAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAAANQAECgUIBQAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAAANQAECgYIBwAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tassarosea:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Tauloe:BAAANQADCggIDwAAAA==.Tayna:BAAANQABCgMIBAAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thomosaurus:BAAANQADCgQIBAAAAA==.Thunk:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.',
Ti='Timdawg:BAAANQAECgEIAQABNQAECgkJGgASABogAA==.Timmolate:BAABNQAECoEaAAMSAAkJGiB/BQCLAgASAAgJARd/BQCLAgATAAcJPBdOIAD/AQAAAA==.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAAANQAECgYICwAAAA==.',
Tr='Tristîtia:BAAANQAECgMIAwAAAA==.',
Ts='Tsuma:BAAANQABCgIIAgAAAA==.Tsume:BAAANQADCgcIBwAAAA==.',
Tt='Ttomas:BAAANQAECgUIBQAAAA==.',
Ty='Tyv:BAAANQAECgQIBAAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQADCgYIDgAAAA==.Vallodon:BAAANQAECgIIAwAAAA==.Vantablack:BAAANQABCgIIAgABNQABCgQICQABAAAAAA==.Vanwolfy:BAAANQAECgEIAQAAAA==.Vaylorian:BAAANQADCggIEAAAAA==.',
Ve='Velectran:BAAANQADCgUICgABNQAECgYIBwABAAAAAA==.Velorian:BAAANQADCgMIAwAAAA==.',
Vi='Vikav:BAAANQADCgIIAgAAAA==.',
Vo='Voodoomike:BAAANQADCgYIBwAAAA==.Vortash:BAAANQADCgUIBwAAAA==.',
Vy='Vynle:BAAANQAECgEIAQAAAA==.',
Wa='Warheimer:BAAANQADCggIEwAAAA==.Warrgodx:BAABNQAECoEWAAMCAAgJRQ7NNAAHAgACAAgJRQ7NNAAHAgALAAEJyggrFQA9AAAAAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wr='Wrongwookie:BAAANQAECgUICgAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQAECgIIAgAAAA==.',
Za='Zabada:BAAANQADCgYIBwAAAA==.Zariee:BAAANQABCgIIAwAAAA==.',
Ze='Zemsen:BAABNQAECoEVAAIIAAgJMxjNNwBcAgAIAAgJMxjNNwBcAgAAAA==.Zenyea:BAAANQAECgIIAwABNQAECggIDQABAAAAAA==.Zetta:BAAANQAECggIDQAAAA==.',
Zo='Zome:BAAANQAECgYICgAAAA==.',
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
