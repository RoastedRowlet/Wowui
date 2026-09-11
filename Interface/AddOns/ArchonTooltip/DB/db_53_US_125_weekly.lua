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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Devourer','DeathKnight-Frost','Monk-Windwalker','Paladin-Holy','Rogue-Subtlety','Rogue-Outlaw','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Havoc','Hunter-BeastMastery',}
local provider = {region='US',realm="Jubei'Thos",name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Adelanaa:BAAANQAECgYIDgAAAA==.Adrasta:BAAANQADCgYIDgAAAA==.Adriell:BAAANQAECgUIBwAAAA==.Adura:BAAANQADCgEIAQAAAA==.',
Ae='Aelathe:BAAANQAECgIIAgAAAA==.Aenimma:BAAANQAECggIBgAAAA==.Aerys:BAAANQADCgUIBwAAAA==.',
Ak='Akey:BAAANQAECgEIAQAAAA==.',
Al='Alamwah:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Alaroo:BAAANQADCggICAAAAA==.Alektra:BAAANQAECgQIBgAAAA==.Alexella:BAAANQADCgcICQAAAA==.Allerfala:BAAANQADCgQIBAABNQAECggICwABAAAAAA==.Alliete:BAAANQADCgIIAgAAAA==.Allya:BAAANQAECgEIAQAAAA==.Aloine:BAAANQAECgUICQAAAA==.',
Am='Amogus:BAAANQADCgUIBQAAAA==.',
An='Anchor:BAAANQABCgEIAgAAAA==.Anqu:BAAANQADCgMIAwAAAA==.',
Ar='Arbitera:BAAANQAECgQIBgAAAA==.Arkona:BAAANQADCgQIBAABNQADCgYICAABAAAAAA==.Arzir:BAAANQAECgYICAAAAA==.',
As='Asmonjoel:BAAANQADCgcICAAAAA==.Assumi:BAAANQADCgcICAAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.',
Au='Audree:BAAANQADCgYIBAAAAA==.',
Av='Avoide:BAAANQADCgYICAAAAA==.',
Az='Azamat:BAAANQAECgEIAQAAAA==.Azuredemonx:BAAANQADCgcIFAAAAA==.',
Ba='Backup:BAAANQAECgQIBwAAAA==.Banan:BAAANQADCgYIBgAAAA==.',
Bb='Bbajer:BAAANQAECgEIAQAAAA==.Bbqporkbuns:BAAANQAECgcIDgAAAA==.',
Be='Bearzy:BAAANQAECgEIAgAAAA==.Bearzz:BAAANQADCgYIBgAAAA==.Belledormi:BAAANQAECgIIAgAAAA==.Bellest:BAAANQAECgUIBQAAAA==.Benji:BAAANQAECgcIEAAAAA==.',
Bf='Bfev:BAAANQAECgMIAwAAAA==.',
Bg='Bggestthighs:BAAANQAECgQIBQABNQAECgcIFQACANUPAA==.',
Bi='Bid:BAAANQAECgMIAwAAAA==.Bigado:BAAANQADCggICgAAAA==.Bigalo:BAAANQADCgQIBAAAAA==.Bigarms:BAAANQADCgQICAABNQADCgcIDQABAAAAAA==.Bigfel:BAAANQABCgQIBAAAAA==.Biggesthighz:BAABNQAECoEVAAICAAcJ1Q89FwDKAQACAAcJ1Q89FwDKAQAAAA==.',
Bl='Blindanddeaf:BAAANQADCgIIAgAAAA==.Bluee:BAAANQAECgIIAgAAAA==.',
Bo='Boohbooh:BAAANQADCggIDQAAAA==.Boomakus:BAAANQAECgcIEAAAAA==.',
Br='Brannie:BAAANQAECgEIAQAAAA==.Brenine:BAAANQADCgcIDgAAAA==.Brewskie:BAAANQADCgEIAgAAAA==.Brodess:BAAANQAECgYIDgAAAA==.Brody:BAAANQAECgcIDgAAAA==.Bromorc:BAAANQADCgUICwAAAA==.Broner:BAAANQAECgUICgAAAA==.Bronlite:BAAANQADCgIIAwAAAA==.Brotherlee:BAAANQAECgYIBgAAAA==.',
Bu='Bubski:BAAANQADCgMIAwAAAA==.Bulimio:BAAANQADCgIIAgAAAA==.Bunzbunnie:BAAANQADCgcIEwAAAA==.Bunzbunny:BAAANQADCggICgAAAA==.Buratt:BAAANQADCgUICwAAAA==.',
['Bé']='Béllâ:BAAANQADCggIAgAAAA==.',
['Bõ']='Bõggie:BAAANQAECgYICgABNQAFFAQIBwADAEYRAA==.',
Ca='Capacitør:BAAANQAECgMIAwAAAA==.Cardib:BAAANQAECgcIDAAAAA==.Carlîn:BAAANQADCgYIBgAAAA==.Cattamend:BAAANQAECgUICAAAAA==.Cattawrath:BAAANQAECgQIBAAAAA==.Cattazap:BAAANQAECgMIBQAAAA==.Cauliflawer:BAAANQAECgQIBQAAAA==.Cavoda:BAAANQADCgMIAwAAAA==.',
Ch='Chakrakhan:BAAANQAECgEIAgAAAA==.Char:BAAANQADCgYIBwAAAA==.Chase:BAAANQAECgIIAgAAAA==.Chinadh:BAABNQAECoEYAAIEAAkJZx8bBABbAwAEAAkJZx8bBABbAwAAAA==.Chinahunter:BAAANQABCgYICQABNQAECgkJGAAEAGcfAA==.Chinamage:BAAANQAECgIIAgABNQAECgkJGAAEAGcfAA==.Chopzuey:BAAANQADCgQICAAAAA==.Chugtiki:BAAANQAECgYICwAAAA==.Chuunky:BAAANQABCgIIAgAAAA==.',
Ci='Cinderaz:BAAANQADCgUICwAAAA==.',
Cl='Clikboomboom:BAAANQADCgUIBgAAAA==.',
Co='Cones:BAAANQADCgQIBQABNQADCgcIDQABAAAAAA==.Conesworth:BAAANQAECgUIBgAAAA==.Conesy:BAAANQADCgYIBAAAAA==.Coquina:BAAANQADCgYIBgAAAA==.Cordeilia:BAAANQAECgcIEQAAAA==.Cordi:BAAANQABCgEIAQAAAA==.Corruptax:BAAANQADCgcIDgAAAA==.Costiigan:BAAANQADCgYIBgAAAA==.',
Cr='Critsaquino:BAAANQAECgUIBQAAAA==.Critsngigs:BAAANQAECgYIBgAAAA==.Crotchsniffa:BAAANQAECgEIAQAAAA==.Crowlêy:BAAANQABCgQICAABNQAECgQICQABAAAAAA==.',
Cy='Cyberlust:BAAANQADCggICAAAAA==.Cyklar:BAAANQADCgUICwAAAA==.',
Da='Daddydevito:BAAANQAECgQIBgAAAA==.Daddythyme:BAAANQAECgQIBAAAAA==.Dames:BAAANQADCgYIBgAAAA==.Danky:BAAANQADCggIFwAAAA==.Daqueta:BAAANQADCgUIAwAAAA==.Daquetawar:BAAANQADCgYICQAAAA==.Darkniggura:BAAANQADCgcICAAAAA==.Darknstormy:BAAANQADCgYIBgABNQADCgYICAABAAAAAA==.Darkpal:BAAANQAECgMIAwAAAA==.Dazzi:BAAANQADCgYIEgAAAA==.',
De='Deathdaddy:BAAANQADCgYIDQAAAA==.Decapitation:BAAANQAECgUICAAAAA==.Defacedd:BAAANQADCgYICgAAAA==.Deify:BAAANQAECgQIBAAAAA==.Deifyh:BAAANQADCgQIBAAAAA==.Deliaz:BAAANQADCgUICwAAAA==.',
Di='Dismarryx:BAAANQAECgEIAgAAAA==.',
Dj='Djapana:BAAANQADCgYICAAAAA==.',
Dn='Dnomm:BAAANQADCgUICwAAAA==.',
Do='Dogmuffin:BAAANQADCgMIAwAAAA==.',
Dr='Drakyon:BAAANQAECgEIAQAAAA==.Dreaddlord:BAAANQADCgQIBQABNQAECgEIAgABAAAAAA==.Dreadiedude:BAAANQAECgEIAgAAAA==.Drowlie:BAAANQADCgYIBgABNQADCggIDAABAAAAAA==.',
Du='Durrin:BAAANQADCggIHQAAAA==.Dutchman:BAAANQAECgEIAQAAAA==.',
Ef='Effectus:BAAANQAECgYICgAAAA==.',
Ei='Eith:BAAANQAECgMIBAAAAA==.',
El='Elele:BAAANQABCgUIBQAAAA==.Eljay:BAAANQAECgUICQAAAA==.Ellell:BAAANQAECgQIDAAAAA==.',
Em='Emberly:BAAANQADCgEIAQAAAA==.',
En='Endersfault:BAAANQAECgUIDwAAAA==.',
Ep='Epicdemoness:BAAANQAECgUICAAAAA==.',
Er='Eroni:BAAANQAECgMIAwAAAA==.',
Eu='Euphea:BAAANQADCgQIBQAAAA==.',
Ev='Evaelfie:BAAANQAECgYIDAAAAA==.',
Fe='Fearology:BAAANQADCgMIAwAAAA==.Felicia:BAAANQAECgQIBgAAAA==.Fellordkiki:BAAANQAECgcICwAAAA==.',
Fi='Filthydh:BAAANQADCgYIBgABNQAECggIDgABAAAAAA==.Filthypally:BAAANQAECggIDgAAAA==.Fivëam:BAAANQABCgIIAgAAAA==.',
Fl='Flashheart:BAAANQAECgEIAQAAAA==.Fleabag:BAAANQADCgQIBwAAAA==.',
Fo='Foxe:BAEANQADCgMIAwABNQADCgcIFAABAAAAAA==.',
Fr='Freezefauker:BAAANQAECgEIAgAAAA==.Fridge:BAAANQAECgMIAwAAAA==.Frostxfury:BAAANQADCgcIFAAAAA==.Frøstynips:BAABNQAECoEpAAMFAAkJ8ST4AACjAwAFAAkJ0yP4AACjAwADAAkJUCS2BABoAwAAAA==.',
Fu='Furysgrip:BAAANQAECgYICwAAAA==.',
Ga='Gabagool:BAAANQAECgEIAQAAAA==.Gaidal:BAAANQAECgEIAQAAAA==.Galafrey:BAAANQADCgIIAgABNQAECgYIDAABAAAAAA==.Garaktou:BAAANQADCgQICAAAAA==.',
Ge='Gekyum:BAABNQAECoEXAAICAAkJMyFCCADoAgACAAkJMyFCCADoAgAAAA==.Getinmyspit:BAAANQAECgQIBQAAAA==.',
Gh='Ghazgkhull:BAAANQADCgYIBgAAAA==.',
Gi='Gidyana:BAAANQADCggIEwAAAA==.Girlsnight:BAAANQADCgQIBwAAAA==.',
Gl='Glancelot:BAAANQAECgMIBQAAAA==.Glipglorp:BAAANQADCgQIBAAAAA==.',
Gn='Gnurse:BAAANQADCgYIBgAAAA==.',
Go='Gommo:BAAANQAECgQIBAAAAA==.Gorbad:BAAANQAECgEIAQAAAA==.',
Gr='Greggoryy:BAAANQABCgQICQAAAA==.Groundizzle:BAAANQAECgQIBAAAAA==.',
Gt='Gtoromu:BAAANQADCgYIBgAAAA==.',
Gu='Guanyu:BAAANQADCgcIFAAAAA==.Guccisosa:BAAANQADCgYIBgAAAA==.Guineamon:BAAANQADCgEIAQAAAA==.',
Ha='Haruk:BAAANQAECgYICgAAAA==.',
He='Heatfist:BAAANQAECgQIBAAAAA==.Heåls:BAAANQAECgIIAgAAAA==.',
Ho='Hoelishock:BAAANQAECgEIAQAAAA==.Hollynova:BAAANQADCggIFAAAAA==.Holychad:BAAANQAECgcICwAAAA==.Honeydew:BAABNQAECoEgAAIGAAkJvRh4BwCrAgAGAAkJvRh4BwCrAgAAAA==.Honganteresa:BAAANQADCggICAAAAA==.Hoofmax:BAAANQADCgYICAAAAA==.',
['Hø']='Høtdøts:BAAANQAECgEIAQAAAA==.',
If='Ifrit:BAAANQAECgEIAQABNQAECgkJFgAHAOAfAA==.',
Il='Illidank:BAAANQAECgQIBQAAAA==.',
Im='Imanoob:BAAANQADCgUIBQAAAA==.Imperiex:BAAANQADCgEIAQAAAA==.',
Io='Ionsw:BAAANQAECgYICgAAAA==.',
Ip='Ipsifu:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.',
Ir='Ironski:BAAANQADCgYIBgAAAA==.',
Ja='Jackillz:BAAANQADCgUIBQABNQAECgYICAABAAAAAA==.Jatzsy:BAAANQAECgMIBQAAAA==.Jayar:BAAANQAECgIIAwAAAA==.',
Je='Jee:BAAANQAECgEIAQAAAA==.Jescon:BAAANQAECgIIAgAAAA==.Jeé:BAAANQADCgUIBQAAAA==.',
Ji='Jiamil:BAAANQAECgQICQAAAA==.Jigolow:BAAANQADCgUIBQAAAA==.',
Jo='Johlissa:BAAANQAECgIIAgAAAA==.',
Ju='Jubber:BAAANQAECgMIAwAAAA==.',
Ka='Kadashy:BAAANQAECgEIAQAAAA==.Kadashyy:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Kaherd:BAAANQADCgcIFAAAAA==.Kamikasi:BAAANQADCggICQAAAA==.Kaneshiro:BAAANQAECgQIBgAAAA==.Karytheca:BAAANQADCgYIBAAAAA==.Katae:BAAANQAECgYIEAAAAA==.Kayrali:BAAANQADCgIIAgAAAA==.',
Ke='Kegaz:BAAANQADCgMIAwAAAA==.Kegward:BAAANQADCgUIBQAAAA==.Kelynada:BAAANQAECgUICgAAAA==.Kendd:BAACNQAFFIEFAAIIAAQJmhGnAQB0AQAIAAQJmhGnAQB0AQA1AAQKgRgAAwgACQmaHO0CADwDAAgACQlvHO0CADwDAAkABwlCEK0FAMABAAAA.Kerrigân:BAAANQADCgYICAAAAA==.',
Ki='Kindra:BAAANQADCgYIBgAAAA==.Kithari:BAAANQAECgEIAgAAAA==.',
Kn='Knickerbits:BAAANQABCgEIAQAAAA==.Knotting:BAAANQADCggIFgAAAA==.',
Ko='Kollateral:BAAANQADCgYICwAAAA==.',
Kr='Krankiekunt:BAAANQAECggIEQAAAA==.Krellhim:BAAANQADCggICwAAAA==.',
Ku='Kuanija:BAAANQAECgYICQAAAA==.Kuuga:BAAANQAECgIIAgAAAA==.',
La='Landwalker:BAAANQAFFAEIAQAAAA==.Langas:BAAANQAECgIIAQABNQAECggIBgABAAAAAA==.Langasbrew:BAAANQAECggIBgAAAA==.Latorius:BAAANQAECgQIBQAAAA==.Lavaloadz:BAAANQADCggIDQAAAA==.Lazziel:BAAANQADCgcIDQAAAA==.',
Le='Lexavis:BAAANQAFFAEIAQABNQAECgUIBwABAAAAAA==.Leyiast:BAAANQAECgIIAgAAAA==.Leyissa:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Lh='Lheo:BAAANQADCgYICAAAAA==.',
Li='Liggma:BAAANQAECgQICAAAAA==.Lightborn:BAAANQADCggICAAAAA==.Lilwhite:BAAANQAECgQIBAAAAA==.',
Lo='Lockaboom:BAAANQADCgQIBwAAAA==.Loldruid:BAAANQAECgEIAgAAAA==.Lom:BAAANQAECgYIBgAAAA==.Lomzz:BAAANQADCgIIAgAAAA==.',
Lu='Lukie:BAEANQAECgIIAgAAAA==.',
Ly='Lycan:BAAANQADCgEIAQAAAA==.Lynarium:BAAANQAECgEIAQAAAA==.Lyradaeris:BAAANQABCgIIAgAAAA==.',
Ma='Magepill:BAAANQADCgQIBAAAAA==.Magharitta:BAAANQAECgUIBwAAAA==.Mahwae:BAAANQADCgIIAwAAAA==.Manoliso:BAAANQADCgIIBAAAAA==.',
Me='Medesin:BAAANQADCgUICwAAAA==.Mekhanite:BAAANQAECgEIAgAAAA==.',
Mi='Milspec:BAAANQAECgYIBgAAAA==.Minami:BAAANQAECgEIAgAAAA==.Minhiriath:BAAANQADCgQIBAAAAA==.Mintbadger:BAAANQADCgUIBwAAAA==.Mistea:BAAANQADCgMIAwAAAA==.',
Mo='Mochimask:BAAANQADCgIIAgAAAA==.Moetown:BAAANQADCggICAABNQAECgkJHAAKACkeAA==.Moistmaker:BAAANQAECgQICAAAAA==.Momotaku:BAAANQAECgQIBAAAAA==.Monalisa:BAAANQADCgYICQAAAA==.Monkmon:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Moonoo:BAAANQADCgUIBQAAAA==.Mordok:BAAANQAECgEIAQAAAA==.Morena:BAAANQADCgYIBwAAAA==.Morgaina:BAAANQADCgcIDQAAAA==.',
Mu='Muscleclub:BAAANQAECgYIBgAAAA==.',
['Më']='Mëmëmë:BAAANQADCgUIBwAAAA==.',
Na='Naeff:BAAANQAECgQIAQAAAA==.Natria:BAAANQAECgUIBQAAAA==.Naya:BAAANQAECgUICgAAAA==.',
Ne='Nerfdehoof:BAAANQADCggICAAAAA==.Nerfdelag:BAAANQAECgQIBQAAAA==.Nerfgün:BAAANQAECgYIDAAAAA==.',
Ni='Nicodautroc:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Nintone:BAAANQAECgIIAgAAAA==.',
No='Nonippies:BAAANQAECgMIBAAAAA==.',
Ns='Nsi:BAAANQADCgUICAAAAA==.',
Nu='Nubishe:BAAANQAECgMIAwAAAA==.Nutsdormu:BAAANQAECgQICwAAAA==.',
Ny='Nythe:BAAANQADCgEIAQAAAA==.Nyxmoona:BAAANQADCgUICwAAAA==.',
['Nà']='Nàishà:BAAANQADCggIEAAAAA==.',
Ob='Obskurer:BAAANQAECgYIBgAAAA==.',
Od='Odinwolf:BAAANQAECgMIBQABNQAECgkJFgAHAOAfAA==.',
Oj='Ojisancage:BAAANQAECgQICAAAAA==.',
Om='Omnitract:BAAANQADCgUIBQAAAA==.',
Or='Orinys:BAAANQADCgcIFAAAAA==.Orkky:BAAANQAECgQIBgAAAA==.',
Pa='Page:BAAANQAECgYIDwAAAA==.Pakurruun:BAAANQADCggIFQAAAA==.Pallatress:BAAANQADCgUICwAAAA==.Pandor:BAAANQAECgEIAQAAAA==.Panginoon:BAAANQAECgYICgAAAA==.Paparìch:BAAANQAECgcIDQAAAA==.Paphio:BAAANQADCggIDAAAAA==.',
Pe='Perden:BAAANQADCgYIBgAAAA==.Pesh:BAAANQADCgYIDQAAAA==.',
Pg='Pgundry:BAAANQADCggIEgAAAA==.',
Ph='Phexides:BAAANQAECgMIAwAAAA==.',
Pi='Piddlesworth:BAAANQADCggIFwAAAA==.Pinkyblue:BAAANQAECgcIDAAAAA==.Pipssqeek:BAAANQADCgYICwAAAA==.',
Pj='Pjw:BAABNQAECoEXAAIHAAkJmBWFDgCzAgAHAAkJmBWFDgCzAgAAAA==.',
Pl='Plarrior:BAAANQADCgMIAwAAAA==.Plip:BAABNQAECoEXAAMLAAcJvRSYJADuAQALAAcJvRSYJADuAQAMAAEJjgOXmQAoAAAAAA==.',
Po='Pokerrface:BAAANQADCggICAAAAA==.Poobumhead:BAAANQADCgcIFAAAAA==.Poweredman:BAAANQADCgIIAgAAAA==.Powerheal:BAAANQADCggIBAAAAA==.',
Pr='Prftlybalncd:BAAANQAECgYIDgABNQAECgkJFwAHAJgVAA==.Probably:BAACNQAFFIEGAAIFAAIJ7xsPAwBbAAAFAAIJ7xsPAwBbAAA1AAQKgTQABAUACQnzImYBAIcDAAUACQnzImYBAIcDAA0AAQn/HOZaAFkAAAMAAQnnE+5iAE0AAAAA.Protato:BAAANQADCggICAAAAA==.',
Ps='Psyche:BAAANQADCgYIBgAAAA==.',
Pu='Pudgeyp:BAAANQAECgcICgAAAA==.Punj:BAAANQAECgEIAQAAAA==.Puntarr:BAAANQADCgYIDQAAAA==.Puppybonks:BAAANQAECgIIAgAAAA==.',
Pw='Pwrbottom:BAAANQAECgMIAgAAAA==.',
Qi='Qibla:BAAANQAECgQIBQAAAA==.',
Qu='Quarizma:BAABNQAECoEdAAICAAkJoCJuAgCHAwACAAkJoCJuAgCHAwAAAA==.',
Ra='Radiantbunz:BAAANQADCggIDgAAAA==.Rankone:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Raxe:BAEANQADCgcIFAAAAA==.',
Re='Reaperoffire:BAAANQADCgcIEAAAAA==.Repliod:BAAANQAECgQICAAAAA==.Restho:BAAANQAECgUICgAAAA==.Revarix:BAAANQAECgIIAwAAAA==.',
Rh='Rhaella:BAAANQAECgEIAgAAAA==.Rhuiser:BAAANQAECgUIDwAAAA==.Rhuno:BAAANQABCgMIAwAAAA==.',
Ri='Ritsuki:BAAANQADCgIIAQAAAA==.Ritéboys:BAAANQADCgYIBgABNQAECgUICwABAAAAAA==.Ritëboys:BAAANQAECgUICwAAAA==.',
Ro='Rocketjuice:BAAANQAECgUIDAAAAA==.',
Ru='Rutee:BAAANQAECgUICAAAAA==.',
Sa='Safk:BAAANQAECgUICQAAAA==.Saleina:BAAANQADCgIIAwAAAA==.Sandiwang:BAAANQADCgIIAgAAAA==.Sartoc:BAAANQAECgMIBAABNQAECgYIDAABAAAAAA==.',
Sc='Scabbo:BAAANQAECgEIAQAAAA==.Scalesoul:BAAANQAECgYICgAAAQ==.',
Sd='Sdfgoose:BAAANQAECgEIAQAAAA==.',
Se='Seiferoth:BAABNQAECoEWAAIHAAkJ4B92BABPAwAHAAkJ4B92BABPAwAAAA==.Sergantcolen:BAAANQAECgUIBgAAAA==.Señornanna:BAAANQADCgQIBAAAAA==.',
Sh='Shaddai:BAAANQAECgEIAgAAAA==.Shadowofevil:BAAANQAECgEIAQAAAA==.Shalavoo:BAAANQAECgIIAgAAAA==.Shamankiller:BAAANQAECgMIBgAAAA==.Shamazzle:BAAANQAECgMIBAAAAA==.Shamlen:BAAANQAECgYIDAAAAA==.Shiicho:BAAANQADCgYIBgAAAA==.Shinieedruid:BAAANQAECgcICwAAAA==.Shions:BAAANQADCgYIBgAAAA==.Shockostoob:BAAANQAECgIIAgAAAA==.',
Si='Sidatas:BAAANQADCgcIBwAAAA==.Silverspulse:BAAANQADCgcIDgAAAA==.Sinequanon:BAAANQAECgcIDgAAAA==.Sinfulbeast:BAAANQAECgQICQAAAA==.Sippycup:BAAANQAECgEIAQABNQAECgcICwABAAAAAA==.',
Sk='Skrogan:BAAANQABCgQICAAAAA==.Skulv:BAABNQAECoEXAAMEAAkJ4SDhBQAwAwAEAAgJRiLhBQAwAwAOAAEJuhUAAAAAAAAAAA==.',
Sl='Slakzor:BAAANQADCgQIAwAAAA==.Slammed:BAAANQAECgMIAwAAAA==.Sleepyshark:BAAANQAECgMIAwAAAA==.Slopain:BAAANQAECgMIAwAAAA==.Slåppery:BAAANQAECggIDwAAAA==.',
Sm='Smashy:BAAANQADCggICwAAAA==.Smìtty:BAAANQADCgMIBAAAAA==.',
Sn='Snorlax:BAAANQAECgQIBgAAAA==.Snort:BAAANQAECgMIAwAAAA==.',
So='Sona:BAAANQADCgYIBgAAAA==.Sonotafurry:BAAANQADCgYIBgAAAA==.Soresu:BAAANQADCggICgAAAA==.Soundwit:BAAANQAECgIIAgAAAA==.',
Sp='Sparrowstalk:BAAANQADCgEIAQAAAA==.Spindrift:BAAANQAECgMIAwAAAA==.Spoonyy:BAAANQAECggIEwAAAA==.',
Sq='Squanchie:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
St='Steinlarger:BAAANQAECgQIBAAAAA==.Storrmbender:BAAANQAECgUICAAAAA==.Stoutbrew:BAAANQADCggICQAAAA==.Strípe:BAAANQAECgEIAQAAAA==.Stuy:BAAANQAECgYIDgAAAA==.Stãria:BAAANQADCggIBwAAAA==.Störme:BAAANQADCgQICAAAAA==.',
Su='Sugarburst:BAAANQAECgIIAgAAAA==.',
Sw='Swak:BAAANQAECgYIEgAAAA==.Switchskin:BAAANQAECgcIDwAAAA==.',
Sy='Syvrogue:BAAANQAECgYIBgABNQADCggIFAABAAAAAA==.',
Ta='Tallinor:BAAANQADCgcIFAAAAA==.Tanags:BAAANQAECgIIAgAAAA==.Taumast:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.Tauter:BAAANQADCgUICgAAAA==.Tazzee:BAAANQADCgYIDAAAAA==.',
Te='Temperature:BAAANQADCgMIAwABNQAECgEIAgABAAAAAA==.',
Th='Thael:BAAANQADCgQIBAAAAA==.Thalia:BAAANQAECgYICwAAAA==.Thottydot:BAAANQAECgEIAQAAAA==.Thox:BAAANQADCgIIAgAAAA==.Thyranux:BAAANQADCgMIBAAAAA==.',
Ti='Tienchi:BAAANQAECgQIBgAAAA==.Tierk:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.Tim:BAAANQAECgYICgAAAA==.',
Tl='Tlo:BAAANQADCgcIBwABNQAECgkJGgAPAGUiAA==.',
To='Tollmemaybe:BAAANQAECgUICwAAAA==.Tormént:BAAANQAECgYICgAAAA==.',
Tr='Transport:BAAANQAECgEIAgAAAA==.Traumatizer:BAAANQADCgQIBQAAAA==.Trenbolone:BAAANQADCgIIAwAAAA==.Tronix:BAAANQAECgUICAAAAA==.Trucidario:BAAANQADCgYIBgAAAA==.Truwar:BAAANQAECgYIBwAAAA==.',
Tu='Tubbquake:BAAANQAECgcICAAAAA==.',
Tw='Twatasaurus:BAAANQADCgYIDQAAAA==.',
['Tî']='Tîmmeh:BAAANQAECgUIBgAAAA==.',
Ub='Ubica:BAAANQAECgUICQAAAA==.',
Un='Unholykníght:BAAANQADCgEIAQAAAA==.Unvoid:BAAANQAECgIICAAAAA==.',
Ur='Urzog:BAAANQADCgUIBQAAAA==.',
Us='Useacooldown:BAAANQADCgcIDQAAAA==.',
Va='Valentine:BAAANQAECgcIBwAAAA==.Valithor:BAAANQAECgEIAQAAAA==.Valkyrion:BAAANQAFFAEIAQAAAA==.Valysan:BAAANQADCgEIAQAAAA==.',
Ve='Velathri:BAAANQAECgEIAQAAAA==.Velenlerolan:BAABNQAECoEXAAIDAAgJMyPWBwApAwADAAgJMyPWBwApAwAAAA==.Velrayne:BAAANQAECgUIBgAAAA==.Veng:BAAANQABCgQIBAAAAA==.Verailde:BAAANQADCgUICQAAAA==.Verathriel:BAAANQABCgQIBgAAAA==.Verilence:BAAANQAECgYICQAAAA==.Veventhius:BAAANQADCgIIAgAAAA==.Vext:BAAANQADCgMIAwAAAA==.',
Vo='Voidberg:BAAANQAECgMIAwABNQAECgcIEQABAAAAAA==.Vorndryad:BAAANQADCgcIFAAAAA==.',
Vy='Vynburn:BAAANQAECgYICgAAAA==.',
Wa='Warmon:BAAANQADCgcIEAAAAA==.Watson:BAAANQAECgIIAgAAAA==.Waveryy:BAAANQADCgMIBgAAAA==.',
We='Wemblitz:BAAANQADCgUICwAAAA==.Wesh:BAAANQAECgcIDgAAAA==.',
Wh='Whio:BAAANQAECgMIAwAAAA==.Whtclass:BAAANQAECgMIAwAAAA==.',
Wi='Wintersfence:BAAANQADCgYICAAAAA==.',
Wk='Wkwk:BAAANQAECgQIBwAAAA==.',
Wp='Wpd:BAAANQAECgYIDAAAAA==.',
['Wî']='Wîngman:BAAANQAECgQICAAAAA==.',
Xe='Xenarn:BAEANQADCgcIDgAAAA==.Xenoruin:BAAANQAECgEIAgAAAA==.',
Xi='Xiphios:BAAANQADCgYIBgAAAA==.',
Yo='Yorkie:BAABNQAECoEUAAIKAAgJix0eIwDEAgAKAAgJix0eIwDEAgAAAA==.Yoyogi:BAAANQADCgYIBwAAAA==.',
Yu='Yui:BAAANQADCggICAAAAA==.Yurarzir:BAAANQAECgYICgAAAA==.',
Za='Zanisha:BAAANQADCgcIFAAAAA==.Zaz:BAAANQADCgYIBgAAAA==.',
Ze='Zelendorm:BAAANQAECgQIBgAAAA==.',
['ßa']='ßaccycønes:BAAANQADCgYICwAAAA==.',
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
