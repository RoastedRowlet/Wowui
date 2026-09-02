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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abysmal:BAAANQADCggIHAAAAA==.',
Ae='Aeriona:BAAANQAECgEIAQAAAA==.Aerolock:BAAANQADCgQIBAABNQAECgQIBQABAAAAAA==.Aerosong:BAAANQAECgQIBQAAAA==.',
Af='Affalon:BAAANQADCgYICQAAAA==.',
Ag='Agape:BAAANQABCgIIBAAAAA==.',
Ai='Aine:BAAANQADCgQIBwAAAA==.Ainkor:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
Ak='Akyospirit:BAAANQAECgEIAQAAAA==.',
Al='Alergies:BAAANQADCgMIBAAAAA==.Aliashryn:BAAANQADCgQIBAAAAA==.Aliatra:BAAANQAECgEIAQAAAA==.Alpha:BAAANQAECgMIAwAAAA==.',
Am='Amamonk:BAAANQADCggIBwAAAA==.',
An='Anchovy:BAAANQADCgQIBAABNQAFFAEIAQABAAAAAA==.Annei:BAAANQAECgQIBAAAAA==.Anomandaris:BAAANQADCgcIDQAAAA==.',
Ap='Apothicc:BAAANQADCgYIDAAAAA==.Aprionos:BAAANQADCgUIBQAAAA==.',
Ar='Argodin:BAAANQADCgUIBQAAAA==.',
As='Asheritâ:BAAANQADCgcICAAAAA==.Ashvalis:BAAANQADCgYIDAAAAA==.Asillyhunter:BAAANQABCgQIBAAAAA==.Asillypally:BAAANQADCgYIDAAAAA==.Askr:BAAANQADCgcIDQAAAA==.Asphar:BAAANQAECgIIAgAAAA==.Asynic:BAAANQADCgYIBgAAAA==.',
Au='Aung:BAAANQAECgQIBQAAAA==.Auri:BAAANQADCgQIBAAAAA==.',
Ax='Axex:BAAANQADCgMIAwAAAA==.',
Az='Azamii:BAAANQAECgEIAQAAAA==.Azill:BAAANQAECgYIBwAAAA==.Azulon:BAAANQADCgUICAAAAA==.Azureknight:BAAANQADCgcIBwAAAA==.Azwald:BAAANQADCgcIBgAAAA==.',
Ba='Bandi:BAAANQADCgYICwAAAA==.Bartrak:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Be='Bearfucius:BAAANQADCggIFAAAAA==.Bearrific:BAAANQADCgYICwAAAA==.Behomadra:BAAANQADCgMIAwAAAA==.Beldzounn:BAAANQADCgIIAgAAAA==.Bevers:BAAANQADCgcIBwAAAA==.',
Bi='Binksy:BAAANQAECgUICQAAAA==.Biscuit:BAAANQAFFAEIAQAAAA==.',
Bl='Blaam:BAAANQADCgUICQAAAA==.Blazin:BAAANQAECgYICQAAAA==.Blinkzy:BAAANQADCgUICQABNQAECgUICQABAAAAAA==.Blitzoria:BAAANQADCgYIBgAAAA==.Bloui:BAAANQADCgMIAwAAAA==.Blueknight:BAAANQADCgcIDQAAAA==.Bluntroller:BAAANQADCgYIBgAAAA==.',
Bo='Borlok:BAAANQAECgIIAQAAAQ==.',
Br='Brannigan:BAAANQAECgQIBQAAAA==.Brannigandh:BAAANQABCgIIAgAAAA==.Braulioo:BAAANQADCgMIAwAAAA==.Brewbelly:BAAANQADCgYIBgAAAA==.Browncrumb:BAAANQAECgMIAwAAAA==.Brönwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buckets:BAAANQADCggIDwAAAA==.Bullvi:BAAANQADCgUICAAAAA==.',
['Bä']='Bärkler:BAAANQAECgQIBAAAAA==.',
['Bé']='Béckléy:BAAANQAECgYIBgAAAA==.',
Ca='Caleanone:BAAANQAECggIAgAAAA==.Carra:BAAANQAECgEIAQAAAA==.Cassiopeía:BAEANQAECgEIAQAAAA==.Catriona:BAAANQADCggIHAAAAA==.',
Ch='Charcuterie:BAAANQAFFAEIAQAAAA==.Cheezeburg:BAAANQADCgcIDQAAAA==.Chikindalf:BAAANQADCgEIAQAAAA==.Chillidán:BAAANQADCggIDQAAAA==.Choggie:BAAANQADCggICAAAAA==.',
Co='Cons:BAAANQAECgQIBAAAAA==.Corellon:BAAANQADCggICAAAAA==.',
Cr='Cranee:BAAANQAECgQIBQAAAA==.Cranium:BAAANQADCggICQAAAA==.Crazytasty:BAAANQAECgIIAgAAAA==.',
Da='Dabora:BAAANQAECgQICQAAAA==.Dannydevine:BAAANQADCgYIBgABNQADCggIDAABAAAAAA==.Darim:BAAANQAECgQIBAABNQABCgIIAgABAAAAAA==.Darthspawn:BAAANQADCgYICwAAAA==.Daryn:BAAANQADCgUICAAAAA==.',
De='Demonainkor:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.Demonicfury:BAAANQADCgYICwAAAA==.Dencity:BAAANQAECgQIBQAAAA==.Derrial:BAAANQADCgIIAgAAAA==.Devianchi:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Devitodevour:BAAANQAECgEIAQAAAA==.',
Dh='Dhbert:BAAANQADCgYICwAAAA==.Dhomeli:BAAANQADCgUICAAAAA==.',
Di='Dirtchez:BAAANQADCgEIAQAAAA==.Disturbed:BAAANQAECgQIBQAAAA==.',
Dk='Dkson:BAAANQAECgYICwAAAA==.',
Do='Docen:BAAANQADCgYICwAAAA==.Doomtotem:BAAANQADCgYIBgAAAA==.',
Dr='Dragonfist:BAAANQADCgUIBgAAAA==.Dragthyr:BAAANQADCgMIAwAAAA==.Druiaier:BAAANQADCgcICwAAAA==.Druknatsu:BAAANQADCgcICAAAAA==.',
Du='Dustyknight:BAAANQADCgYICwAAAA==.',
Dw='Dwell:BAAANQADCgEIAQAAAA==.',
Ed='Edge:BAAANQADCgcIDQAAAA==.',
El='Elidoria:BAAANQAECgMIAwAAAA==.Elphinia:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
En='Enoki:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.',
Ep='Ephodess:BAAANQADCggIDgAAAA==.',
Er='Eraduckated:BAAANQAECgEIAgAAAA==.',
Es='Esile:BAAANQAECgEIAQAAAA==.Esoryn:BAAANQAECgMIAwAAAA==.',
Ev='Everlife:BAAANQAECgEIAQAAAA==.Evilainkor:BAAANQAECgMIBAAAAA==.',
Ex='Exia:BAAANQAECgcICwAAAA==.',
Fa='Fauzzie:BAAANQADCgcICAAAAA==.Fayrel:BAAANQADCgQIBAAAAA==.',
Fe='Fedders:BAAANQAECgIIBQAAAA==.Felaids:BAAANQAECgQIBAAAAA==.',
Fi='Fillon:BAAANQAECggICwAAAA==.Fishfood:BAAANQAECgEIAQAAAA==.Fixer:BAAANQADCgUICAAAAA==.',
Fl='Flatine:BAAANQADCgEIAQAAAA==.',
Fr='Frankngibbon:BAAANQADCgYIBgAAAA==.Frimthemage:BAAANQAECgQIBAAAAA==.Frostmaster:BAAANQAECgEIAQAAAA==.',
['Fø']='Førd:BAAANQAECgUIBwAAAA==.',
Ga='Gangrene:BAAANQAECgEIAQAAAA==.Gaspasser:BAAANQADCggIDQAAAA==.',
Ge='Gerhart:BAAANQAECgQIBAAAAA==.',
Gi='Gigarius:BAAANQADCggIHAAAAA==.',
Gl='Gloomy:BAAANQADCgYIBgAAAA==.',
Go='Goncor:BAAANQADCggIHAABNQAECgQIBAABAAAAAA==.',
Gr='Gracze:BAAANQAECgEIAQAAAA==.Granolah:BAAANQADCgYICwABNQAECgQICQABAAAAAA==.Grendo:BAAANQABCgIIAgAAAA==.Greninja:BAAANQADCgcICwAAAA==.Grevan:BAAANQADCggIDwAAAA==.Griffmonk:BAAANQAECgEIAQAAAA==.Grumpymage:BAAANQAECgIIAgAAAA==.',
Ha='Hafsac:BAAANQADCgYICwAAAA==.Hardord:BAAANQADCgUICAAAAA==.Harrypooter:BAAANQADCgcICAAAAA==.Hayanne:BAAANQAECgEIAQAAAA==.',
He='Healzjoogewd:BAAANQADCgYIBgAAAA==.Hebmanager:BAAANQADCgcIBwAAAA==.',
Ho='Holikow:BAAANQADCgcIDQAAAA==.Holyherpies:BAAANQADCgUIBQAAAA==.Holyness:BAAANQADCgcICQAAAA==.Honorlife:BAAANQADCgUIBQAAAA==.',
Hr='Hroadar:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.',
Hu='Hurano:BAAANQADCgUIBQAAAA==.',
Hy='Hyam:BAAANQAECgEIAQAAAA==.Hyperious:BAAANQADCgYIBgAAAA==.',
Id='Idyllwild:BAAANQADCggIEQAAAA==.',
In='Inkdot:BAAANQAECgQIBAAAAA==.Inkwell:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Ja='Jakobo:BAAANQAECgEIAQAAAA==.',
Je='Jelly:BAAANQAFFAEIAQAAAA==.',
Jo='Jozalin:BAAANQABCgEIAQAAAA==.',
Ju='Junknthtrunk:BAAANQADCgIIAgAAAA==.',
Ka='Kaelana:BAAANQABCgQIBQAAAA==.Kamahl:BAAANQADCggICAAAAA==.',
Ke='Keanew:BAAANQAECgMIAwAAAA==.Keigaa:BAAANQADCgYIBgAAAA==.Keilien:BAAANQADCgIIAgAAAA==.Kenry:BAAANQADCgYICAAAAA==.Keonna:BAAANQADCgMIAwAAAA==.Keppra:BAAANQADCgQIBAAAAA==.Kerlin:BAAANQAECgEIAgAAAA==.',
Ki='Kilaben:BAAANQADCgEIAQAAAA==.Kinoxo:BAAANQAFFAEIAQAAAA==.Kinozo:BAAANQAECgMIAwAAAA==.',
Ko='Kotahoko:BAAANQADCgcIBwAAAA==.',
La='Largepp:BAAANQADCgMIAwAAAA==.',
Le='Legnase:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.Leiche:BAAANQAECgEIAQAAAA==.Lessgibbon:BAAANQADCgYIBgAAAA==.',
Li='Libáh:BAAANQADCgYICgAAAA==.Ligmabonez:BAAANQADCgUICQAAAA==.Lilnasty:BAAANQADCgMIAwABNQADCggIHAABAAAAAA==.Lindabelcher:BAAANQADCgYIBgAAAA==.Livesey:BAAANQADCgMIBAAAAA==.',
Lo='Longshañk:BAAANQAECgQIBAAAAA==.',
Lu='Lucibrew:BAAANQAECgQIBAAAAA==.',
Ma='Mavramune:BAAANQAECgUICAAAAA==.',
Mc='Mcfürry:BAAANQADCgcIDgAAAA==.',
Me='Meggatron:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Mendinna:BAAANQADCggIEAAAAA==.',
Mi='Mickeysneak:BAAANQADCgQIBAAAAA==.Miffed:BAAANQAECgcIDQAAAA==.',
Mo='Montebrew:BAAANQADCgYIBgAAAA==.Mooky:BAAANQADCggIDwAAAA==.',
Mp='Mpowerz:BAAANQAECgMIBQAAAA==.',
My='Mynoghra:BAAANQADCggIHAAAAA==.',
Na='Naraku:BAAANQAECgQIBQAAAA==.Nazgül:BAAANQABCgIIAgAAAA==.',
Ne='Neshock:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Nettie:BAAANQADCgcICAAAAA==.Netty:BAAANQADCgIIAgABNQADCgcICAABAAAAAA==.',
Nu='Nuclearbomb:BAAANQADCgIIAQAAAA==.',
Ny='Nymphetamine:BAAANQADCgYIBgAAAA==.',
Od='Odessa:BAAANQADCgMIAwAAAA==.',
Om='Omorc:BAAANQAECgQIBAAAAA==.',
On='Onli:BAAANQADCggICAAAAA==.',
Pa='Pandaloco:BAAANQADCgUIBwAAAA==.Pandalôc:BAAANQADCgcICAAAAA==.Pandoe:BAAANQAFFAEIAQAAAA==.',
Pe='Penelopea:BAAANQADCggICAAAAA==.Perun:BAAANQADCggICAAAAA==.',
Ph='Phenomenal:BAAANQADCggICAAAAA==.Pheonyx:BAAANQADCgQIBAAAAA==.',
Pi='Picarus:BAAANQADCgYIBgAAAA==.Picklerìck:BAAANQAECgEIAQAAAA==.',
Po='Porteagarder:BAAANQADCgUICgABNQADCggIDwABAAAAAA==.',
Pr='Preparedpie:BAAANQAECgcIDQAAAA==.Pringler:BAAANQAECgMIAwABNQAFFAEIAQABAAAAAA==.Producktive:BAAANQADCgUIBQABNQAECgEIAgABAAAAAA==.Promise:BAAANQADCgYIBgAAAA==.Príestly:BAAANQADCgMIAwAAAA==.',
Pu='Puffthemagic:BAAANQADCgcIBwAAAA==.Purpledor:BAAANQAECgIIAwAAAA==.',
Pw='Pwnage:BAAANQADCgUIBQAAAA==.',
Py='Pyatt:BAAANQAECgEIAQAAAA==.',
Qu='Quack:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Quackwizard:BAAANQAECgQIBAAAAA==.Quilae:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Qy='Qyburn:BAAANQAECgQIBAAAAA==.',
Ra='Radioface:BAAANQADCgUIBQAAAA==.Rassputin:BAAANQADCgcIDQAAAA==.',
Re='Recipe:BAAANQAECgIIAgAAAA==.Reigwend:BAAANQADCgIIAgAAAA==.Remish:BAAANQABCgQIBgAAAA==.Rendezvous:BAAANQADCgUIBQAAAA==.Renkà:BAAANQAECgQIBQAAAA==.Revaerlous:BAAANQAECgUIBwAAAA==.',
Rh='Rheas:BAAANQADCgYIBgAAAA==.',
Ri='Rice:BAAANQADCgUIBQABNQAFFAEIAQABAAAAAA==.',
Ro='Roketraccoon:BAAANQADCgUIBQAAAA==.Roshamandes:BAAANQADCgYIBgAAAA==.',
Ru='Rubyhunter:BAAANQADCgEIAQABNQADCgcIDQABAAAAAA==.',
Sa='Sabermage:BAAANQADCgYIBgAAAA==.Sacredchikín:BAAANQAECgMIAwAAAA==.Samuel:BAAANQADCgUICQAAAA==.Sanitarìum:BAAANQADCgMIBAAAAA==.Saxa:BAAANQAECgEIAQAAAA==.',
Sc='Screamsoda:BAAANQADCggIBwAAAA==.Scrubzz:BAAANQADCggIDgAAAA==.',
Se='Sev:BAAANQADCgYIBQAAAA==.Seyekosis:BAAANQADCgYIDAAAAA==.',
Sg='Sgathaich:BAEANQADCgIIAgABNQADCgcICwABAAAAAA==.',
Sh='Shallistiah:BAAANQAECgEIAQAAAA==.Shamajama:BAAANQADCgEIAQAAAA==.Shamathore:BAAANQAECgMIAwAAAA==.Shamdwarf:BAAANQADCgMIAwAAAA==.Shobadon:BAAANQADCgEIAQAAAA==.Shockbev:BAAANQADCgMIAwAAAA==.',
Si='Siatral:BAAANQAECgUICAAAAA==.Siete:BAAANQAECgEIAQAAAA==.Siggopotomus:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Silver:BAAANQADCggIDQAAAA==.Sinfulangel:BAAANQADCggIDgAAAA==.Siona:BAAANQAECgEIAQAAAA==.',
Sk='Skadie:BAAANQADCggIDgAAAA==.Skwar:BAAANQAECgEIAQAAAA==.Skwel:BAAANQADCggIDQAAAA==.Skwii:BAAANQAECgMIAwAAAA==.Skwill:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Skwip:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.Skwup:BAAANQAECgUIBgAAAA==.',
Sl='Slackness:BAAANQADCgQIBAAAAA==.Slackpally:BAAANQADCgMIAwAAAA==.Slayj:BAAANQADCggICQABNQAECgYICQABAAAAAA==.Sleepybeard:BAAANQADCgYIEQAAAA==.Slubadub:BAAANQADCgYICwAAAA==.',
Sn='Snivels:BAAANQADCgcICQAAAA==.',
So='Soil:BAAANQAECgIIAgAAAA==.Somna:BAAANQABCgQIBgAAAA==.',
Sp='Sparrkle:BAAANQAECgQIBAAAAA==.Spinecrawler:BAAANQAECgQIBAAAAA==.Spyro:BAAANQADCgYIFAAAAA==.',
St='Starblast:BAAANQADCgYIDgABNQADCgYICwABAAAAAA==.Staryknight:BAAANQADCgYICAAAAA==.Stellanova:BAAANQADCgYIDQAAAA==.Stiick:BAAANQAECgEIAQAAAA==.Stìmpak:BAAANQADCgMIAwAAAA==.',
Sw='Sweetbippy:BAAANQADCgYIBgAAAA==.Swifthealss:BAAANQADCgcIDAAAAA==.Swirls:BAAANQADCgIIAgAAAA==.',
Sy='Syluné:BAAANQADCggIDwAAAA==.',
Ta='Tacozpriest:BAAANQADCgYIBwAAAA==.Taelyx:BAAANQADCggIDgAAAA==.Tambot:BAAANQAECgIIAgAAAA==.Tariced:BAAANQADCgMIAwAAAA==.Tazmina:BAAANQAECgQICQAAAA==.',
Te='Tessa:BAAANQAECgEIAQAAAA==.Teyo:BAAANQADCgIIAgAAAA==.',
Th='Thahtduality:BAAANQADCgYIBgAAAA==.Thalooze:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.',
Ti='Tiathel:BAAANQADCgYIBgAAAA==.Tinyjapeto:BAAANQADCgUICQAAAA==.Titanbow:BAAANQADCgYIDAAAAA==.',
To='Tomcatt:BAAANQAECgEIAQAAAA==.Tortapounder:BAAANQAECgEIAQAAAA==.Toughnutz:BAAANQABCgEIAQAAAA==.',
Tr='Trailis:BAAANQADCgIIAgAAAA==.',
Tu='Turin:BAAANQAECgQIBAAAAA==.Tutonik:BAAANQADCgUIBQAAAA==.',
Tw='Twilghtdawn:BAAANQADCgYIBQAAAA==.',
Ty='Tybo:BAAANQADCgcIDgAAAA==.Tycho:BAAANQADCgIIAgAAAA==.',
Un='Uncás:BAAANQADCgYICwAAAA==.',
Up='Upchucky:BAAANQADCgMIAwAAAA==.',
Va='Vainagos:BAAANQADCgUIBQAAAA==.Valaryon:BAAANQADCgUICAAAAA==.Valoryan:BAAANQAECgEIAQAAAA==.Vaxtur:BAAANQADCggIBAAAAA==.',
Ve='Vegà:BAAANQADCggIHAAAAA==.Vendettis:BAAANQADCgUICAAAAA==.Vextaerin:BAAANQAECgMIBAAAAA==.Vextarin:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Veztaroth:BAAANQADCggIDgAAAA==.',
Vi='Viktorr:BAAANQADCgEIAQAAAA==.',
Vo='Voidyo:BAAANQAECgQIBQAAAA==.',
Wh='Whiskeyjak:BAAANQADCggICAAAAA==.',
Wi='Willowbark:BAAANQADCgMIAwAAAA==.Willowest:BAAANQAECgQIBQAAAA==.Wizbizzler:BAAANQADCggIEAAAAA==.',
Wr='Wrathstorm:BAAANQAECgQIBAAAAA==.',
Xa='Xanier:BAAANQADCgMIAwAAAA==.',
Xe='Xelagos:BAAANQAECgQIBAAAAA==.',
Xi='Xiaowei:BAAANQADCggIDQAAAA==.',
Xx='Xxcor:BAAANQADCgIIAgAAAA==.',
Ya='Yanella:BAAANQAECgQIBAAAAA==.',
Yi='Yisshaman:BAAANQADCgUICQAAAA==.',
Za='Zandarbribbs:BAAANQADCgcIDAAAAA==.',
Ze='Zennya:BAAANQAECgEIAQAAAA==.Zenofchaos:BAAANQADCgQICAAAAA==.',
Zu='Zugdealer:BAAANQADCgQIAwAAAA==.',
Zy='Zygradin:BAAANQAECgEIAQAAAA==.',
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
