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

local lookup = {'Monk-Windwalker','Unknown-Unknown','Warrior-Protection','Monk-Brewmaster','Paladin-Holy','Warrior-Arms','Hunter-BeastMastery','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Havoc',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaragon:BAAANQAECgYIBgABNQAFFAcIDgABAAwZAA==.',
Ab='Abysmal:BAAANQADCggIHwAAAA==.',
Ae='Aeriona:BAAANQAECgQIBQAAAA==.Aerolock:BAAANQADCgQIBAABNQAECgQIBQACAAAAAA==.Aerosong:BAAANQAECgQIBQAAAA==.',
Af='Affalon:BAAANQADCgYICQAAAA==.',
Ag='Agape:BAAANQABCgIIBAAAAA==.',
Ai='Ainkor:BAAANQAECgQIBQABNQAECgUICQACAAAAAA==.',
Ak='Akyospirit:BAAANQAECgQIBQAAAA==.',
Al='Aliashryn:BAAANQADCgQIBAAAAA==.Aliatra:BAAANQAECgEIAQAAAA==.Alpha:BAAANQAECgQIBwAAAA==.',
Am='Amamonk:BAAANQADCggIBwAAAA==.',
An='Anchovy:BAAANQADCgQIBAABNQAECgkJGQADAF4iAA==.Annei:BAAANQAECgUICQAAAA==.Anomandaris:BAAANQAECgEIAQAAAA==.',
Ap='Apothica:BAAANQADCgUIBgABNQAECgEIAQACAAAAAA==.Apothicc:BAAANQAECgEIAQAAAA==.Apraxia:BAAANQADCgQIBAAAAA==.Aprionos:BAAANQAECgMIAwAAAA==.',
Aq='Aquae:BAAANQADCgQIBAAAAA==.',
Ar='Arcohunt:BAAANQADCgcIBwABNQAECgMIAwACAAAAAA==.Aredhël:BAAANQADCgEIAQAAAA==.Argodin:BAAANQADCggIDQAAAA==.',
As='Asheritâ:BAAANQAECgEIAQAAAA==.Ashvalis:BAAANQAECgQIBAAAAA==.Asillyhunter:BAAANQABCgYICAAAAA==.Asillypally:BAAANQAECgUIBgAAAA==.Askr:BAAANQAECgEIAQAAAA==.Asphar:BAAANQAECgQIBgAAAA==.Asynic:BAAANQADCgYICwAAAA==.',
Au='Aung:BAAANQAECggIDQAAAA==.Auri:BAAANQADCgcICwAAAA==.',
Ax='Axex:BAAANQADCgMIAwAAAA==.',
Az='Azamii:BAAANQAECgQIBQAAAA==.Azill:BAAANQAFFAEIAQAAAA==.Azrëiäl:BAAANQABCgEIAQAAAA==.Azulon:BAAANQAECgIIAgAAAA==.Azureknight:BAAANQAECgEIAQAAAA==.Azwald:BAAANQADCgYIBgAAAA==.',
Ba='Bandi:BAAANQAECgEIAQAAAA==.Bartrak:BAAANQADCgIIAgABNQAECgIIAwACAAAAAA==.Battôsai:BAAANQADCgYIBgAAAA==.',
Be='Bearfucius:BAAANQAECgEIAQAAAA==.Bearrific:BAAANQAECgIIAgAAAA==.Behomadra:BAAANQADCgMIAwAAAA==.Beldzounn:BAAANQADCgIIAgAAAA==.Bevers:BAAANQAECgMIAwAAAA==.',
Bi='Binksy:BAAANQAECgcIEAAAAA==.Biscuit:BAABNQAECoEZAAIDAAkJXiKKAACiAwADAAkJXiKKAACiAwAAAA==.',
Bl='Blaam:BAAANQADCgYIDwAAAA==.Blazin:BAAANQAECggIEQAAAA==.Blinkzy:BAAANQADCgUICQABNQAECgcIEAACAAAAAA==.Blitzoria:BAAANQADCgYIBgAAAA==.Bloui:BAAANQADCgMIAwAAAA==.Blueknight:BAAANQAECgEIAQAAAA==.Bluntroller:BAAANQADCgYIBgAAAA==.',
Bo='Borlok:BAAANQAECgQIBQAAAQ==.',
Br='Brannigan:BAAANQAECgQICQAAAA==.Brannigandh:BAAANQAECgIIAgAAAA==.Braulioo:BAAANQADCgMIBAAAAA==.Brewbelly:BAAANQADCgYIBgAAAA==.Brewcifer:BAAANQADCgYIBgAAAA==.Brickfelt:BAAANQABCgYICgAAAA==.Brickitphil:BAAANQAECgUIBQAAAA==.Browncrumb:BAAANQAECgMIAwAAAA==.Brönwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buckets:BAAANQAECgIIAgAAAA==.Bullvi:BAAANQADCgYIDgAAAA==.',
['Bä']='Bärkler:BAAANQAECgQIBAAAAA==.',
['Bé']='Béckléy:BAAANQAECgcIDQAAAA==.',
Ca='Caleanone:BAAANQAECggIAgAAAA==.Carra:BAAANQAECgQIBQAAAA==.Cassiopeía:BAEANQAECgQIBQAAAA==.Catriona:BAAANQADCggIHAAAAA==.',
Ch='Charcuterie:BAABNQAECoEZAAIEAAkJ5x5+AQA4AwAEAAkJ5x5+AQA4AwAAAA==.Cheesedanish:BAAANQADCgYIBgAAAA==.Cheezeburg:BAAANQAECgEIAQAAAA==.Chicken:BAAANQAECgEIAQABNQAECgkJGQADAF4iAA==.Chikindalf:BAAANQADCgEIAQAAAA==.Chillidán:BAAANQAECgMIAwAAAA==.Choggie:BAAANQAECgUIBQAAAA==.',
Co='Cons:BAAANQAECgYICgAAAA==.Corellon:BAAANQAECgIIAgAAAA==.',
Cr='Cranee:BAAANQAECgYICwAAAA==.Cranium:BAAANQADCggIEQAAAA==.Crazytasty:BAAANQAECgQIBgAAAA==.',
Da='Dabora:BAAANQAECgUIDgAAAA==.Damda:BAAANQADCgYIBgAAAA==.Dannydevine:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Darim:BAAANQAECgUICQABNQADCgYIBgACAAAAAA==.Darthspawn:BAAANQADCgcIEgAAAA==.Daryn:BAAANQADCgUIDQAAAA==.',
De='Deathollow:BAAANQADCgYIBgAAAA==.Demonainkor:BAAANQADCgcICAABNQAECgUICQACAAAAAA==.Demonicfury:BAAANQADCgcIDAAAAA==.Dencity:BAAANQAECgYICwAAAA==.Derrial:BAAANQADCgQIBAAAAA==.Devianchi:BAAANQADCgcICwABNQAECgQIBQACAAAAAA==.Devitodevour:BAAANQAECgQIBQAAAA==.Devwarr:BAAANQAECgEIAQAAAA==.',
Dh='Dhbert:BAAANQADCgcIDAAAAA==.Dhomeli:BAAANQAECgIIAgAAAA==.',
Di='Dirtchez:BAAANQADCgcICAAAAA==.Disastrophy:BAAANQADCgEIAQABNQADCgYICQACAAAAAA==.Disturbed:BAAANQAECgYICwAAAA==.',
Dk='Dkson:BAAANQAECgcIEgAAAA==.',
Do='Docen:BAAANQADCggIEQAAAA==.Doomtotem:BAAANQADCgYIDAAAAA==.',
Dr='Dragonfist:BAAANQADCgUIBgAAAA==.Dragthyr:BAAANQADCgMIAwAAAA==.Druiaier:BAAANQADCggIEwAAAA==.Druknatsu:BAAANQAECgEIAQAAAA==.',
Du='Dustyknight:BAAANQADCgcIEgAAAA==.',
Dw='Dwalyn:BAAANQADCgcIBwAAAA==.Dwell:BAAANQADCgYIBwAAAA==.',
Ed='Edge:BAAANQAECgEIAQAAAA==.',
El='Elidoria:BAAANQAECgUICAAAAA==.Elphinia:BAAANQADCgYIBgABNQAECgYIBwACAAAAAA==.',
En='Enoki:BAAANQAECgYICQABNQAECgkJGQAFAFMeAA==.',
Ep='Ephodess:BAAANQADCggIGAAAAA==.',
Er='Eraduckated:BAAANQAECgIIBAAAAA==.',
Es='Esile:BAAANQAECgQIBQAAAA==.Esoryn:BAAANQAECgQIBwAAAA==.',
Ev='Everlife:BAAANQAECgEIAQAAAA==.Evilainkor:BAAANQAECgUICQAAAA==.',
Ex='Exia:BAAANQAECggIDAAAAA==.',
Fa='Fauzzie:BAAANQAECgEIAQAAAA==.Fayrel:BAAANQAECgMIAwAAAA==.',
Fe='Fedders:BAAANQAECgUICgAAAA==.Felaids:BAAANQAECgQICAAAAA==.Felnyx:BAAANQADCgQIBAAAAA==.Feor:BAAANQADCgUIBQAAAA==.Feralyn:BAAANQADCgYIBgAAAA==.Fero:BAAANQADCgUIBwAAAA==.',
Fi='Fillon:BAAANQAFFAIIAgAAAA==.Fishfood:BAAANQAECgQIBQAAAA==.Fixer:BAAANQADCgUICAAAAA==.',
Fl='Flatine:BAAANQADCgEIAQAAAA==.',
Fr='Frankngibbon:BAAANQAECgIIAgAAAA==.Frimthemage:BAAANQAECgUICQAAAA==.Frostmaster:BAAANQAECgQIBQAAAA==.',
Fu='Funbunz:BAAANQADCgMIAQAAAA==.',
['Fø']='Førd:BAAANQAECgYIEQAAAA==.',
Ga='Gangrene:BAAANQAECgQIBQAAAA==.Gaspasser:BAAANQADCggIDQAAAA==.',
Ge='Genovia:BAAANQADCgQIBAABNQADCgYIDAACAAAAAA==.Gerhart:BAAANQAECgUICQAAAA==.',
Gi='Gigarius:BAAANQADCggIHAAAAA==.',
Gl='Gloomy:BAAANQADCgYIBgAAAA==.',
Go='Goncor:BAAANQAECgEIAQABNQAECgUICQACAAAAAA==.',
Gr='Gracze:BAAANQAECgMIAwAAAA==.Granolah:BAAANQADCgcIEwABNQAECgUIDgACAAAAAA==.Grendo:BAAANQABCgIIAgAAAA==.Greninja:BAAANQADCgcICwAAAA==.Grevan:BAAANQAECgEIAQAAAA==.Griffmonk:BAAANQAECgQIBQAAAA==.Grumpymage:BAAANQAECgQIBgAAAA==.',
Ha='Hafsac:BAAANQADCgYICwAAAA==.Hardord:BAAANQADCgYIDgAAAA==.Harrypooter:BAAANQAECgEIAQAAAA==.Hayanne:BAAANQAECgQIBQAAAA==.',
He='Healzjoogewd:BAAANQADCgYIBgAAAA==.Hebmanager:BAAANQADCgcIBwAAAA==.',
Ho='Hochunk:BAAANQAECgQIBAAAAA==.Holikow:BAAANQAECgEIAQAAAA==.Holyherpies:BAAANQADCgYICwAAAA==.Holyness:BAAANQAECgIIAgAAAA==.Honorlife:BAAANQADCgUIBQAAAA==.',
Hr='Hroadar:BAAANQAECgUICAABNQAECgcIDwACAAAAAA==.',
Hu='Hurano:BAAANQAECgIIAgAAAA==.',
Hy='Hyam:BAAANQAECgEIAQAAAA==.Hyperious:BAAANQADCgcICAAAAA==.',
['Hø']='Hølyhéll:BAAANQADCgcIBwAAAA==.',
Id='Idyllwild:BAAANQADCggIFgAAAA==.',
In='Inkdot:BAAANQAECgQICQAAAA==.Inkshield:BAAANQADCgYIBgABNQAECggIAQACAAAAAA==.Inkwell:BAAANQADCgYIBgABNQAECgQICQACAAAAAA==.',
Ir='Irritate:BAAANQADCgIIAgAAAA==.',
Ja='Jakobo:BAAANQAECgQIBQAAAA==.Jarthas:BAAANQADCgYIBgAAAA==.',
Je='Jelly:BAABNQAECoEZAAIFAAkJUx5CBQA/AwAFAAkJUx5CBQA/AwAAAA==.Jenivira:BAAANQADCgMIAwAAAA==.',
Jo='Jozalin:BAAANQABCgMIBAAAAA==.',
Ju='Jubilee:BAAANQADCgQIBAAAAA==.Judokeg:BAAANQAECgEIAQAAAA==.Junknthtrunk:BAAANQADCgIIAgAAAA==.',
Ka='Kaelana:BAAANQABCgQIBQAAAA==.Kamahl:BAAANQADCggICgAAAA==.',
Ke='Keanew:BAAANQAECgQICAAAAA==.Keigaa:BAAANQADCgYIBgAAAA==.Keilien:BAAANQADCgIIAgAAAA==.Kenry:BAAANQADCgYIDQAAAA==.Keonna:BAAANQADCgMIAwAAAA==.Keppra:BAAANQADCgcICwAAAA==.Kerlin:BAAANQAECgEIAwAAAA==.',
Ki='Kilaben:BAAANQAECgQIBwAAAA==.Kinoxo:BAABNQAECoEZAAIGAAkJQyCCBwBzAwAGAAkJQyCCBwBzAwAAAA==.Kinozo:BAAANQAECgMIAwAAAA==.Kittyclysm:BAAANQADCgYIBgAAAA==.',
Ko='Kotahoko:BAAANQADCgcIBwAAAA==.',
Kr='Krag:BAAANQADCgQIBAAAAA==.',
La='Largepp:BAAANQADCgMIAwAAAA==.',
Le='Leb:BAAANQAECgQIBAABNQAECgcIEAACAAAAAA==.Legnase:BAAANQAECgQIBAABNQAECgQIBQACAAAAAA==.Leiche:BAAANQAECgEIAgAAAA==.Lessgibbon:BAAANQADCgYIBgAAAA==.',
Li='Libáh:BAAANQADCgYICgAAAA==.Ligmabonez:BAAANQADCgYIDwAAAA==.Lilnasty:BAAANQADCgMIAwABNQADCggIHwACAAAAAA==.Lindabelcher:BAAANQADCgYIBgAAAA==.Livesey:BAAANQAECgIIAgAAAA==.',
Lo='Longshañk:BAAANQAECgUIBwAAAA==.',
Lu='Lucibrew:BAAANQAECgYICgAAAA==.',
Ma='Macpreizy:BAAANQADCgQIBAAAAA==.Mavramune:BAAANQAECgcIDwAAAA==.',
Mc='Mcfürry:BAAANQADCgcIFAAAAA==.',
Me='Meggatron:BAAANQADCgcIDAABNQAECgUICQACAAAAAA==.Mendinna:BAAANQADCggIFgAAAA==.',
Mi='Mickeysneak:BAAANQADCgQIBAAAAA==.Miffed:BAABNQAECoEYAAIHAAkJOSRsAQCtAwAHAAkJOSRsAQCtAwAAAA==.Mistborn:BAAANQAECggIAQAAAA==.',
Mo='Montebrew:BAAANQADCgYIBgABNQADCgcIBwACAAAAAA==.Montecane:BAAANQADCgcIBwAAAA==.Mooky:BAAANQAECgMIAwAAAA==.',
Mp='Mpowerz:BAAANQAECgQICQAAAA==.',
My='Mynoghra:BAAANQADCggIHAAAAA==.',
Na='Naraku:BAAANQAECgYICwAAAA==.Natifia:BAAANQADCgcIBwAAAA==.Nazgül:BAAANQABCgIIAgAAAA==.',
Ne='Neshock:BAAANQAECgIIAgABNQAECgYICwACAAAAAA==.Nettie:BAAANQAECgEIAQAAAA==.Netty:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.',
Nu='Nuclearbomb:BAAANQADCgIIAQAAAA==.',
Ny='Nymphetamine:BAAANQAECgIIAgAAAA==.',
Od='Odessa:BAAANQADCgMIAwAAAA==.',
Om='Omorc:BAAANQAECgUICQAAAA==.',
On='Onli:BAAANQADCggICAAAAA==.',
Ow='Owenwilson:BAAANQADCgUIBQAAAA==.',
Pa='Pandaloco:BAAANQADCgUIBwAAAA==.Pandalôc:BAAANQAECgEIAQAAAA==.Pandoe:BAABNQAECoEZAAIIAAkJiSJeAAC6AwAIAAkJiSJeAAC6AwAAAA==.',
Pe='Penelopea:BAAANQADCggIDgAAAA==.Perun:BAAANQAECgIIAgAAAA==.',
Ph='Phenomenal:BAAANQADCggIEAAAAA==.Pheonyx:BAAANQADCgUICQAAAA==.',
Pi='Picarus:BAAANQADCgYIBgAAAA==.Picklerìck:BAAANQAECgEIAgAAAA==.',
Pl='Planb:BAAANQAECgIIAgABNQAECgYICwACAAAAAA==.',
Po='Porteagarder:BAAANQADCgcIEQABNQADCggIFgACAAAAAA==.',
Pr='Preparedpie:BAABNQAECoEaAAMJAAkJtxqDBwALAwAJAAkJtxqDBwALAwAKAAQJfg+VJQDQAAAAAA==.Pringler:BAAANQAECgYICgABNQAECgkJGQADAF4iAA==.Producktive:BAAANQAECgIIAgABNQAECgIIBAACAAAAAA==.Promise:BAAANQADCgcIDQAAAA==.Pruulia:BAAANQADCggICAABNQAECgQIBQACAAAAAA==.Príestly:BAAANQADCgYICAAAAA==.',
Pu='Puffthemagic:BAAANQADCgcIBwAAAA==.Purpledor:BAAANQAECgIIBAAAAA==.',
Pw='Pwnage:BAAANQADCggIDwAAAA==.',
Py='Pyatt:BAAANQAECgMIAwAAAA==.',
Qu='Quack:BAAANQAECgYIBgAAAA==.Quackwizard:BAAANQAECgQIBAABNQAECgYIBgACAAAAAA==.Quilae:BAAANQADCgYIBgABNQADCggIFgACAAAAAA==.',
Qy='Qyburn:BAAANQAECgUICAAAAA==.',
Ra='Radioface:BAAANQADCggICgAAAA==.Ragecage:BAAANQADCggICAABNQAECgUICQACAAAAAA==.Randivh:BAAANQADCgEIAQAAAA==.Rassputin:BAAANQAECgIIAgAAAA==.',
Re='Reigwend:BAAANQADCgIIAgAAAA==.Remish:BAAANQABCgQIBgAAAA==.Rendezvous:BAAANQADCgUIBQAAAA==.Renkà:BAAANQAECgYIBwAAAA==.Resmondo:BAAANQADCgcIBwAAAA==.Revaerlous:BAAANQAECgYIDQAAAA==.',
Rh='Rheas:BAAANQADCgYIDAAAAA==.',
Ri='Rice:BAAANQADCgUIBQABNQAECgkJGQADAF4iAA==.',
Ro='Robbnz:BAAANQABCgQIAgAAAA==.Roflsummon:BAAANQADCgEIAQABNQADCgYIDAACAAAAAA==.Roflthump:BAAANQADCgYIBgAAAA==.Roketraccoon:BAAANQADCgYICwAAAA==.Roshamandes:BAAANQAECgIIAgAAAA==.',
Ru='Rubyhunter:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.Runestipidos:BAAANQADCgQIBQAAAA==.',
Sa='Sabermage:BAAANQADCggIDgAAAA==.Sacredchikín:BAAANQAECgUICAAAAA==.Samuel:BAAANQADCgYIDwAAAA==.Sandvichus:BAAANQAECgEIAQAAAA==.Sanitarìum:BAAANQADCgMIBAAAAA==.Saxa:BAAANQAECgIIAwAAAA==.',
Sc='Screamsoda:BAAANQAECgEIAQABNQAECggIAQACAAAAAA==.Scrubzz:BAAANQAECgQIBAAAAA==.',
Se='Sev:BAAANQADCgYIBQAAAA==.Seyekolock:BAAANQADCgUIBQAAAA==.Seyekosis:BAAANQAECgEIAQAAAA==.',
Sg='Sgathaich:BAEANQAECgIIAgAAAA==.',
Sh='Shallistiah:BAAANQAECgQIBQAAAA==.Shamajama:BAAANQADCgEIAQAAAA==.Shamathore:BAAANQAECgQIBwAAAA==.Shamdwarf:BAAANQADCgcICgAAAA==.Shiftnfard:BAAANQADCgQIBAAAAA==.Shobadon:BAAANQADCgEIAQAAAA==.Shockbev:BAAANQADCgMIAwAAAA==.Shotcaller:BAAANQAECgMIAwAAAA==.',
Si='Siatral:BAAANQAECgcIDwAAAA==.Siete:BAAANQAECgQIBQAAAA==.Siggopotomus:BAAANQADCgYIBgABNQADCgYIDAACAAAAAA==.Silchar:BAAANQABCgMIBQAAAA==.Silicon:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.Silver:BAAANQAECgIIAgAAAA==.Sinfulangel:BAEANQAECgIIAgAAAA==.Siona:BAAANQAECgQIBQAAAA==.Sixpaths:BAAANQAECgUIBwABNQAECggIAQACAAAAAA==.Siyunkai:BAEANQAECgEIAQAAAA==.',
Sk='Skadie:BAAANQAECgEIAQAAAA==.Skiye:BAAANQADCgEIAQAAAA==.Skwar:BAAANQAECgEIAQAAAA==.Skwel:BAAANQADCggIDQAAAA==.Skwii:BAAANQAECgMIAwABNQAECgYIBgACAAAAAA==.Skwill:BAAANQAECgYIBgAAAA==.Skwip:BAAANQADCggICAABNQAECgYIBgACAAAAAA==.Skwup:BAAANQAECgcIDQAAAA==.',
Sl='Slackness:BAAANQADCgQIBAAAAA==.Slackpally:BAAANQADCgcICQAAAA==.Slapstîck:BAAANQADCggICAAAAA==.Slayj:BAAANQADCggICQABNQAECggIEQACAAAAAA==.Sleepybeard:BAAANQADCgYIEwAAAA==.Slubadub:BAAANQAECgIIAgAAAA==.',
Sm='Smiteslay:BAAANQAECgQIBAABNQAECggIEQACAAAAAA==.',
Sn='Snivels:BAAANQAECgIIAgAAAA==.',
So='Soil:BAAANQAECgQIBgAAAA==.Somna:BAAANQAECgIIAgAAAA==.',
Sp='Sparrkle:BAAANQAECgUICQAAAA==.Spinecrawler:BAAANQAECgUICQAAAA==.Spyro:BAAANQADCgcIGwAAAA==.',
St='Starblast:BAAANQAECgEIAQABNQADCgcIDAACAAAAAA==.Staryknight:BAAANQAECgEIAQAAAA==.Stellanova:BAAANQADCgYIDQAAAA==.Stiick:BAAANQAECgQIBQAAAA==.Stìmpak:BAAANQADCgYICQAAAA==.',
Su='Subhuman:BAAANQADCgQIBAAAAA==.',
Sw='Sweetbippy:BAAANQADCggIDgAAAA==.Swifthealss:BAAANQADCggIFAAAAA==.Swirls:BAAANQADCgcICQAAAA==.',
Sy='Sylunae:BAAANQADCgUIBQABNQADCggIFgACAAAAAA==.Syluné:BAAANQADCggIFgAAAA==.',
Ta='Tacozpriest:BAAANQADCgYIDAAAAA==.Taelyx:BAAANQAECgMIAwAAAA==.Tambot:BAAANQAECgYICAAAAA==.Tanalee:BAAANQADCgQIBAAAAA==.Tariced:BAAANQADCgMIAwAAAA==.Tazmina:BAABNQAECoEVAAIKAAYJIx7zEADuAQAKAAYJIx7zEADuAQAAAA==.',
Te='Tessa:BAAANQAECgQIBQAAAA==.Teyo:BAAANQADCgIIAgAAAA==.',
Th='Thahtduality:BAAANQAECgYIBgAAAA==.Thalooze:BAAANQADCgEIAQABNQADCgcIDAACAAAAAA==.',
Ti='Tiathel:BAAANQADCgYIBgAAAA==.Tinyjapeto:BAAANQADCgYICgAAAA==.Titanbow:BAAANQADCgYIDAAAAA==.',
To='Tomcatt:BAAANQAECgQIBQAAAA==.Tortapounder:BAAANQAECgIIAgAAAA==.Toughnutz:BAAANQABCgEIAQAAAA==.',
Tr='Trailis:BAAANQADCgIIAgAAAA==.',
Tu='Turin:BAAANQAECgUICQAAAA==.Tutonik:BAAANQADCgUIBQAAAA==.',
Tw='Twilghtdawn:BAAANQADCgYIBQAAAA==.Twotone:BAAANQADCgQIBAAAAA==.',
Ty='Tybo:BAAANQAECgEIAQAAAA==.Tycho:BAAANQADCgIIAgAAAA==.Tychondrius:BAAANQADCgQIBAAAAA==.',
Un='Uncás:BAAANQAECgQIBAAAAA==.Undyinggnome:BAAANQADCggICAAAAA==.',
Up='Upchucky:BAAANQADCgMIAwAAAA==.',
Va='Vainagos:BAAANQADCgUIBQAAAA==.Valaryon:BAAANQADCgUICAAAAA==.Valoryan:BAAANQAECgQIBQAAAA==.Vasoline:BAAANQADCgMIAwABNQAECgMIAwACAAAAAA==.Vaxtur:BAAANQAECggICAAAAA==.',
Ve='Vegà:BAAANQAECgMIAwAAAA==.Vendettis:BAAANQADCgUIDQAAAA==.Vextaerin:BAAANQAECgMIBAAAAA==.Vextarin:BAAANQADCgYIBgABNQAECgMIBAACAAAAAA==.Veylyn:BAAANQAECgIIAgAAAA==.Veztaroth:BAAANQAECgIIAgAAAA==.',
Vi='Viktorr:BAAANQADCgEIAQAAAA==.',
Vo='Voidsham:BAAANQADCgEIAQAAAA==.Voidyo:BAAANQAECgQICQAAAA==.',
Wh='Whiskeyjak:BAAANQAECgIIAgAAAA==.',
Wi='Willowbark:BAAANQADCgMIAwAAAA==.Willowest:BAAANQAECgYICwAAAA==.Wizbizzler:BAAANQAECgQIBAAAAA==.',
Wr='Wrathstorm:BAAANQAECgUICQAAAA==.',
Xa='Xalatoes:BAAANQABCgYIBgAAAA==.Xanatose:BAAANQADCggICAABNQAECgIIAgACAAAAAA==.Xanier:BAAANQADCgMIAwAAAA==.',
Xe='Xelagos:BAAANQAECgQIBAAAAA==.',
Xi='Xiaowei:BAAANQAECgEIAQAAAA==.',
Xx='Xxcor:BAAANQADCgMIBQAAAA==.',
Xy='Xyndylyne:BAAANQADCgYIBgAAAA==.',
Ya='Yanella:BAAANQAECgUICQAAAA==.',
Yi='Yisdk:BAAANQADCgYIBgAAAA==.Yisshaman:BAAANQAECgUIBQAAAA==.',
Yo='Yogibearz:BAAANQADCgYIBgABNQAECgQICQACAAAAAA==.',
Za='Zandarbribbs:BAAANQADCgcIDQAAAA==.',
Ze='Zennya:BAAANQAECgIIAwAAAA==.Zenofchaos:BAAANQADCgQICAAAAA==.',
Zu='Zugdealer:BAAANQADCgQIAwAAAA==.',
Zy='Zygradin:BAAANQAECgEIAQAAAA==.Zyrx:BAAANQADCgcIBwAAAA==.',
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
