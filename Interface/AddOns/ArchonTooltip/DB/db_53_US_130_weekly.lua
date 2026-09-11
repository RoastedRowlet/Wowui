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

local lookup = {'Unknown-Unknown','Monk-Mistweaver','Hunter-Survival','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker',}
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abonde:BAAANQADCggICAAAAA==.Abraxes:BAAANQAECgEIAQAAAA==.',
Ac='Acidemon:BAAANQADCggIFAAAAA==.',
Ad='Adalaide:BAAANQAECgEIAQAAAA==.Adannis:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Adelane:BAAANQADCgUIBQABNQAECgQICAABAAAAAA==.Adolyn:BAAANQADCggIEQAAAA==.',
Ae='Aeluna:BAAANQADCgYICgAAAA==.Aethas:BAAANQADCgUIBwAAAA==.',
Af='Affective:BAAANQAECgUIBgAAAA==.Afkk:BAAANQADCgEIAQAAAA==.',
Ah='Ahuramazda:BAAANQADCgQIBAAAAA==.',
Ai='Aidard:BAAANQABCgYICgAAAA==.Airdd:BAAANQADCgEIAQAAAA==.Aizlyn:BAAANQADCgYICQAAAA==.',
Ak='Akio:BAAANQAECgQIBQAAAA==.',
Al='Aldarya:BAAANQAECgEIAQAAAA==.Alisara:BAAANQAECgYIDQAAAA==.Alish:BAAANQADCgYIDwAAAA==.Allexx:BAAANQAECgIIAgAAAA==.Allyssel:BAAANQAFFAIIAwAAAA==.Alrictus:BAAANQADCggIDwAAAA==.',
Am='Amasu:BAAANQAECgcIEQAAAA==.Amazinggrace:BAAANQAECgQIBwAAAA==.Ammathendis:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Ampera:BAAANQADCgYIBgAAAA==.',
An='Anastriana:BAAANQADCgYICgAAAA==.Angeal:BAAANQAECgEIAQAAAA==.Angrychef:BAAANQADCgYIDAAAAA==.Animus:BAAANQAECgQIBgAAAA==.Annamei:BAAANQADCgcIEwAAAA==.',
Ao='Aoife:BAAANQAECgIIAwAAAA==.Aorina:BAAANQAECgYIDwAAAA==.',
Ar='Arazalor:BAAANQAECgQIBQAAAA==.Arcangel:BAAANQAECgcIEQAAAA==.Arrash:BAAANQADCgYICwAAAA==.Arthritic:BAAANQADCgcIEgAAAA==.Arthurdent:BAAANQAECgQIBwAAAA==.',
As='Ashara:BAAANQAECgMIAwAAAA==.Aspiration:BAAANQABCgMIBQAAAA==.',
At='Atheren:BAAANQADCggIDQAAAA==.Athshu:BAAANQADCgcIBwAAAA==.Atulan:BAAANQAECgUIBwAAAA==.',
Au='Auntiemimi:BAAANQADCggIEAAAAA==.',
Av='Avannar:BAAANQADCgUIDgAAAA==.Avelyn:BAAANQADCgEIAQAAAA==.Aveìl:BAAANQADCgUIBQAAAA==.Aviae:BAAANQADCgcIEgAAAA==.',
Ay='Ayani:BAAANQAECgQIBAAAAA==.',
Az='Azrine:BAAANQADCggIFAAAAA==.',
Ba='Baddattitude:BAAANQADCgUIBwABNQADCgYICwABAAAAAA==.Baddkharma:BAAANQADCgQICAAAAA==.Badras:BAAANQAECgQIBgAAAA==.Bagelz:BAAANQAECgcIEQAAAA==.Bathomula:BAAANQAECgEIAQAAAA==.Bayla:BAAANQADCgUIBQABNQAECgkJGgACAA4cAA==.Bazzwar:BAAANQADCgcICgAAAA==.',
Be='Beric:BAAANQADCggICAAAAA==.Betadine:BAAANQADCgEIAQAAAA==.Bexy:BAAANQAECgUIBgAAAA==.',
Bl='Blade:BAAANQAECgQIBQAAAA==.',
Bo='Boldan:BAAANQABCgEIAQAAAA==.Boohaha:BAAANQAECggIDQAAAA==.Booze:BAAANQADCggIBwAAAA==.Bormagh:BAAANQADCgUIBQAAAA==.Borris:BAAANQAECgcICwAAAA==.',
Br='Brightwing:BAAANQAECgYIDAAAAA==.Brigorath:BAAANQADCgcIEQAAAA==.Brokenarro:BAAANQADCgYIDAAAAA==.',
Bu='Bubblebae:BAAANQAECgEIAgAAAA==.Bullshivek:BAAANQADCggIFAAAAA==.',
Ca='Caecus:BAAANQADCggIFAAAAA==.Callsaul:BAEANQAECgEIAQAAAA==.Casmus:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Caylissa:BAAANQADCggIEQAAAA==.',
Ce='Cenvoked:BAAANQAECgIIAgAAAA==.Cepha:BAAANQADCgQIBAAAAA==.',
Ch='Charbethicc:BAAANQAECgQIBwAAAA==.Charlondrus:BAAANQADCgQIBgABNQAECgQIBwABAAAAAA==.Charticulous:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.Chijoku:BAAANQAECgQIBQAAAA==.Chimster:BAAANQAECgQIBAAAAA==.Chuckstrike:BAAANQADCgUIBQAAAA==.Chyna:BAAANQADCggICAAAAA==.',
Co='Corvò:BAAANQAECgEIAgAAAA==.',
Cr='Craeus:BAAANQADCggIFAAAAA==.Cralk:BAAANQAECgMIAwABNQAECgYIBAABAAAAAA==.Cranked:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.',
Cy='Cyonarah:BAAANQADCgcIDAAAAA==.',
Da='Darem:BAAANQADCggIEAAAAA==.',
De='Decnahne:BAAANQADCgUIBQAAAA==.Deepwood:BAAANQAECgMIAwAAAA==.Deidra:BAAANQADCgYIEAAAAA==.Devilette:BAAANQADCgEIAQAAAA==.Devry:BAAANQABCgMIAwAAAA==.',
Di='Dietdrpeeper:BAAANQAECgYICgAAAA==.Diggi:BAAANQAECgIIAgAAAA==.Diosa:BAAANQAECgQIBQAAAA==.Divinekat:BAAANQADCgYIDAABNQADCggICwABAAAAAA==.Dizza:BAAANQADCgUIBQAAAA==.',
Dk='Dkagon:BAAANQAECgYICAAAAA==.',
Do='Docholiday:BAAANQADCgYIEAAAAA==.Dontticklmeh:BAAANQADCgMIAgAAAA==.Doode:BAAANQADCgcIDQAAAA==.Dooderonomy:BAAANQADCggIFAAAAA==.',
Dr='Dragaan:BAAANQAECgMIAwAAAA==.Dragonbait:BAAANQAECgUIBwAAAA==.Dragonoodles:BAAANQAECgIIAgAAAA==.Dragonzbane:BAAANQAECgEIAQAAAA==.Dranosh:BAAANQADCgUIBQABNQADCggIFgABAAAAAA==.Dreamawake:BAAANQADCggICgAAAA==.Drek:BAAANQAECgIIAgAAAA==.Drenea:BAAANQADCgUIDAAAAA==.Drin:BAAANQAECgEIAQAAAA==.',
Dy='Dyriana:BAAANQADCgUICgAAAA==.',
['Dä']='Däustin:BAAANQADCgYIBgAAAA==.',
Ec='Ecto:BAAANQAECgYICAAAAA==.',
El='Eleshn:BAAANQADCggICQAAAA==.Ellasian:BAAANQADCgUIBQAAAA==.Ellewoods:BAAANQADCggIDwAAAA==.Eltria:BAAANQAECgcIEQAAAA==.',
Em='Empathy:BAAANQAECgEIAQAAAA==.',
En='Ennuii:BAAANQADCggIEQAAAA==.',
Ep='Ephel:BAAANQAECgEIAgAAAA==.',
Es='Essential:BAAANQAECgcIEQAAAA==.',
Ex='Exces:BAAANQADCgUIBQAAAA==.',
Ez='Ezalth:BAAANQADCgUICAAAAA==.Ezz:BAAANQADCggIDwAAAA==.',
Fa='Faden:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.Faenara:BAAANQAECgQIBQAAAA==.Falafelguy:BAAANQAECgQICgAAAA==.Falron:BAAANQADCgEIAQAAAA==.Farhund:BAAANQADCgcIBwAAAA==.Faruqq:BAAANQAECgIIAgAAAA==.',
Fe='Feenux:BAAANQABCgQIBAAAAA==.Felafel:BAAANQADCgMIBAABNQAECgQICgABAAAAAA==.Felartamiel:BAAANQADCgUIDQAAAA==.Felkieler:BAAANQADCgYICAABNQAECgEIAQABAAAAAA==.Fey:BAAANQAECgUICAAAAA==.',
Fi='Fishron:BAAANQADCggIFAAAAA==.',
Fl='Flaz:BAAANQAECgYICgAAAA==.',
Fo='Forestspirit:BAAANQAECgIIAgAAAA==.',
Fr='Frawda:BAAANQAECgQIBQAAAA==.',
Fu='Fusillidari:BAAANQADCgcIEwABNQAECgIIAgABAAAAAA==.Fuzzy:BAAANQADCgEIAQAAAA==.',
Ga='Galaxyman:BAAANQADCggICQAAAA==.',
Ge='Geist:BAAANQAECgcIEQAAAA==.Geraith:BAAANQAECgcIDwAAAA==.Gerios:BAAANQAECgQIBQAAAA==.',
Gg='Ggparts:BAAANQADCgUIBQAAAA==.',
Gh='Ghostflair:BAAANQADCgEIAQAAAA==.Ghostflare:BAAANQADCgYICQAAAA==.',
Gl='Glacier:BAAANQABCgIIAgAAAA==.Glendra:BAAANQAECgIIAgAAAA==.Glorificus:BAAANQADCggICAAAAA==.',
Gn='Gnomércy:BAAANQADCgMIAwAAAA==.',
Go='Goatboat:BAAANQADCgQIBwAAAA==.',
Gr='Grandeeny:BAAANQAECgQIBAAAAA==.Greensleeves:BAAANQADCgUICwAAAA==.Gregoriusz:BAAANQAECgYICgAAAA==.Greygull:BAAANQADCgYIDgAAAA==.',
Gu='Guinness:BAAANQAECgEIAQAAAA==.Guntank:BAAANQAECgQIBQAAAA==.',
Ha='Hategnomer:BAAANQADCgUIDAAAAA==.Havenfell:BAAANQADCggIDgAAAA==.Hawkfist:BAAANQAECgIIAgAAAA==.',
He='Hercules:BAAANQAECgcIEQAAAA==.',
Hi='Hierodoulos:BAAANQAECgQIBQAAAA==.',
Ho='Holykat:BAAANQADCggICwAAAA==.Hotcha:BAAANQADCgEIAQAAAA==.Hotsie:BAAANQADCgIIAgAAAA==.',
Hr='Hroth:BAAANQAECgIIAgAAAA==.Hrothgar:BAAANQABCgIIAgABNQAECgIIAgABAAAAAA==.',
Hu='Hunteroni:BAAANQADCgcIDwABNQAECgIIAgABAAAAAA==.',
If='Ifearu:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Ig='Iggity:BAAANQABCgIIAwAAAA==.',
Ih='Ihri:BAAANQADCggIFQAAAA==.',
Ik='Ikthus:BAAANQAECgIIAgAAAA==.',
Il='Illtud:BAAANQADCgUICwAAAA==.Ilyessa:BAAANQAECggIEQAAAA==.',
Ir='Ironfur:BAAANQADCgQIBAABNQADCggIFgABAAAAAA==.Ironpipes:BAAANQADCgcIEAAAAA==.',
Is='Iskrå:BAAANQADCgcIEwAAAA==.',
Ja='Jacynth:BAAANQAECgQIBAAAAA==.Jaimers:BAAANQAECgQIBQAAAA==.Jardinn:BAAANQADCgMIBgABNQAECgEIAgABAAAAAA==.Jaxen:BAAANQAECgQIBgAAAA==.Jaxon:BAAANQADCgcIDAAAAA==.Jaywilde:BAAANQAECgYIEQAAAA==.',
Je='Jerkpaladin:BAAANQADCggICAAAAA==.Jerusalaem:BAAANQADCgEIAQAAAA==.',
Ji='Jizakazam:BAAANQAECgMIBAAAAA==.',
Jo='Josepha:BAAANQADCgEIAQAAAA==.',
Ju='Juggyspally:BAAANQAECgEIAQAAAA==.Justbringit:BAEANQADCgQIBAABNQAECgcIEAABAAAAAA==.',
Ka='Karotten:BAAANQADCggIFAAAAA==.Karthair:BAAANQADCggIEwAAAA==.Kassoa:BAAANQADCgMIAwAAAA==.Kaszim:BAAANQAECgYICQAAAA==.',
Ke='Keello:BAAANQADCgYIDgAAAA==.Kelkieran:BAAANQADCgUIBQAAAA==.Kernelsandrs:BAAANQAECgcIEQAAAA==.',
Ki='Killgore:BAAANQADCgYIBgAAAA==.Kintsugi:BAAANQADCgcIDAAAAA==.Kirinmaruu:BAAANQADCgQIBAAAAA==.Kirisatsu:BAAANQADCggIEQAAAA==.Kisatchie:BAAANQAECgEIAQAAAA==.',
Ko='Koalitsiya:BAAANQADCggIDgAAAA==.Kozãk:BAAANQADCgUICAAAAA==.',
Kr='Kreatos:BAAANQADCgYIBgAAAA==.Krimez:BAAANQAECgQIBwAAAA==.Krynez:BAAANQADCgUICQABNQAECgQIBwABAAAAAA==.',
Ky='Kyrhios:BAAANQAECgYICAAAAA==.',
['Kä']='Käggai:BAAANQAECgcIDgAAAA==.',
['Kò']='Kòld:BAAANQAECgcIDAAAAA==.Kòume:BAAANQADCgMIAgAAAA==.',
La='Lana:BAAANQADCgIIAgAAAA==.Lark:BAAANQADCggIHAAAAA==.Larthas:BAAANQAECgQIBQAAAA==.Lascie:BAAANQAECgQIBQAAAA==.',
Le='Leafykat:BAAANQADCgUIBQABNQADCggICwABAAAAAA==.Leaila:BAAANQAECgEIAQAAAA==.Leiha:BAAANQADCggIDAAAAA==.',
Li='Liams:BAAANQADCgUIBwAAAA==.Lidless:BAAANQAECgQIBAAAAA==.Linux:BAAANQADCggIEQAAAA==.',
Ll='Llamadin:BAAANQADCggIFAAAAA==.',
Lo='Logknight:BAAANQADCgUIBQAAAA==.',
Lu='Lukis:BAAANQADCgYIBgAAAA==.Luminianna:BAAANQAECgQIBwAAAA==.',
Ly='Lynra:BAAANQADCggICAAAAA==.Lytol:BAAANQADCggICwAAAA==.',
Ma='Macloc:BAAANQADCggIEgAAAA==.Maggiemae:BAAANQADCgUICgAAAA==.Mahli:BAAANQAECgQIBQAAAA==.Marrias:BAAANQAECgYIDAAAAA==.Massacre:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Mawrix:BAAANQAECgMIAwAAAA==.',
Me='Mechchimy:BAAANQAECgEIAgAAAA==.Meith:BAAANQADCgQIBAAAAA==.Melwazul:BAAANQADCgMIAwAAAA==.Merazi:BAAANQADCgMIAwAAAA==.Mesuryte:BAABNQAECoEYAAMDAAkJuyMyAACtAwADAAkJuyMyAACtAwAEAAEJEA0ZOABEAAAAAA==.',
Mi='Mibby:BAAANQABCgYIBgABNQADCgcIEAABAAAAAA==.Mibs:BAAANQAECgIIAgAAAA==.Mickal:BAAANQAECgQIBQAAAA==.Mikaelangelo:BAAANQAECgEIAQAAAA==.Mip:BAAANQADCgcIEAAAAA==.Mirie:BAAANQADCgUIBQAAAA==.',
Mn='Mnrogar:BAAANQADCgQIBQAAAA==.',
Mo='Mohegon:BAAANQADCgQIBQAAAA==.Mohini:BAAANQAECgIIAgAAAA==.Mojhohammers:BAAANQADCgUIBQAAAA==.Mooter:BAAANQAECgYICgAAAA==.Morchak:BAAANQADCgYIBgAAAA==.Mornix:BAAANQADCgUIBQABNQADCgYIBAABAAAAAA==.',
Mu='Mushroom:BAAANQADCggICAAAAA==.',
My='Mystweaver:BAAANQADCgYIBgAAAA==.',
Na='Naota:BAAANQAECgQIBQAAAA==.Naqilol:BAAANQADCgQIBAAAAA==.Narfox:BAAANQADCggIEwAAAA==.Nazzern:BAAANQAECgIIAgAAAA==.',
Ne='Neameto:BAAANQAECgYIBgAAAA==.Necrophyle:BAAANQAECgIIAgAAAA==.Nefarox:BAAANQADCggIEQAAAA==.Nerfslappy:BAAANQADCgYIDwAAAA==.Nethron:BAAANQADCgUIBQAAAA==.',
Ni='Nightman:BAAANQAECgUIBgAAAA==.Nightstealer:BAAANQADCgcIEQAAAA==.Nikkikayama:BAAANQAECgcIEQAAAA==.Nikol:BAAANQAECgUIBQABNQAECgUIBgABAAAAAA==.',
No='Norikoff:BAAANQAFFAIIAgAAAA==.',
Ny='Nyalla:BAAANQADCgUIDAAAAA==.',
['Nï']='Nïdalee:BAAANQAECgIIAgAAAA==.',
Oc='Octoberfae:BAAANQADCgMIAwAAAA==.Octwitch:BAAANQADCgcIDAAAAA==.',
Of='Offdensen:BAAANQADCgcIEQAAAA==.',
Ok='Okkotsu:BAAANQABCgQIBAAAAA==.Okku:BAAANQAECgEIAQAAAA==.',
Ol='Oldmims:BAAANQAECgUIBQAAAA==.',
On='Onlybatfans:BAAANQADCggIDwAAAA==.',
Op='Ophina:BAAANQADCgcICwAAAA==.',
Or='Oramu:BAAANQAECgUICwAAAA==.Orangejello:BAAANQAECgEIAQAAAA==.Orion:BAAANQADCgMIAwABNQAECggIEQABAAAAAA==.Oriòn:BAAANQADCggIFAAAAA==.',
Ot='Otane:BAAANQAECgQIBAAAAA==.',
Pa='Paiah:BAAANQADCgIIAgAAAA==.Pallykillers:BAAANQADCgUICgAAAA==.Palyephel:BAAANQADCggICAABNQAECgEIAgABAAAAAA==.Pana:BAAANQAECgQIBwAAAA==.Pandhikukka:BAAANQADCgUIBQAAAA==.Pandy:BAAANQAECgEIAQAAAA==.Pannifer:BAAANQAECgEIAQAAAA==.Paolon:BAAANQADCgYIDAAAAA==.Papasmurph:BAAANQABCgIIAgAAAA==.Parple:BAAANQAECgQICAABNQAFFAIIAgABAAAAAA==.',
Pe='Penelopei:BAAANQAECgIIAgAAAA==.',
Ph='Phantõm:BAAANQADCgQIBAAAAA==.',
Pi='Picker:BAAANQADCgYIBgAAAA==.',
Po='Poledra:BAAANQADCgUICgAAAA==.Porterah:BAAANQADCggIFwAAAA==.Poutyne:BAAANQAECgUICgAAAA==.',
Pr='Priestress:BAAANQADCggICAAAAA==.Profanus:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.',
Pu='Punchnugget:BAAANQAECgEIAQAAAA==.Punkvc:BAAANQAECgUIBwAAAA==.',
Py='Pyren:BAAANQADCgYICwAAAA==.',
['Pá']='Párts:BAAANQADCgMIBAABNQADCgUIBQABAAAAAA==.',
Qu='Quaeras:BAAANQAECgMIBAAAAA==.',
Ra='Rabiess:BAAANQAECgEIAQAAAA==.Ragingnoodle:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Ragingshnoz:BAAANQAECgQIBQAAAA==.Ragé:BAEANQAECgcIEAAAAA==.Rakklock:BAAANQADCgQICAAAAA==.Ralphe:BAAANQAECgQIBAAAAA==.Raytow:BAAANQAECgYICQAAAA==.Razelle:BAAANQADCggIFAAAAA==.',
Re='Reconpalymix:BAAANQADCgUIBwAAAA==.Relana:BAAANQADCgIIAgAAAA==.Ressix:BAAANQAECgQIBQAAAA==.',
Rh='Rhaeyn:BAAANQADCgMIBQABNQADCggIFAABAAAAAA==.',
Ri='Ripture:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Rizzwar:BAAANQAECgEIAQAAAA==.',
Ro='Roastbeefin:BAAANQADCgIIAgAAAA==.Rockhunter:BAAANQADCggICAAAAA==.Ronborules:BAAANQADCgQIBAAAAA==.Rosenta:BAAANQAECgEIAQAAAA==.',
Ru='Rumlock:BAAANQADCggIFAAAAA==.',
['Rö']='Röwnin:BAAANQADCgYIDAAAAA==.',
Sa='Sabinah:BAAANQADCgcIDAAAAA==.Sabing:BAAANQADCgUIDAAAAA==.Saeberis:BAAANQADCgUIBQAAAA==.Saiah:BAAANQADCgYICgAAAA==.Saintbazz:BAAANQADCgYICgABNQADCgcICgABAAAAAA==.Sal:BAAANQAFFAIIAgAAAA==.Salivan:BAAANQADCggIEQAAAA==.Sargaris:BAAANQADCggICAAAAA==.Sariva:BAABNQAECoEaAAQFAAkJextdKQDFAQAFAAYJRhldKQDFAQAGAAUJeRZ3GQBfAQAHAAIJRxPOCwCOAAAAAA==.Saurva:BAAANQAECgcIEQAAAA==.Sawfang:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Saxophone:BAAANQAECgQIBAAAAA==.Sayna:BAAANQAECgQICAAAAA==.',
Sc='Scarecro:BAAANQAECgQIBQAAAA==.',
Se='Sedae:BAAANQAECgQIBAAAAA==.Seekvaira:BAAANQAECgYIBwAAAA==.Seiya:BAAANQAECgEIAQAAAA==.Selira:BAAANQADCggIFAAAAA==.Senji:BAAANQADCgYICQAAAA==.Sevalina:BAAANQAECgIIAgAAAA==.',
Sh='Shadowstep:BAAANQADCgcIDAAAAA==.Shalaah:BAAANQAECgEIAQAAAA==.Shamhuntzu:BAEANQAECgcIEQAAAA==.Shampaign:BAAANQAECgQIBQAAAA==.Shaoevoker:BAAANQADCggICgAAAA==.Sharnara:BAAANQAECgMIAwAAAA==.Shatterskull:BAAANQADCggIFgAAAA==.Shazira:BAAANQADCgcIDAAAAA==.Shep:BAAANQADCgcIBgAAAA==.Shmollboi:BAAANQABCgIIAgAAAA==.',
Si='Sideffects:BAAANQAECgQIBQAAAA==.Sidewinder:BAAANQADCggICAAAAA==.Silvercircle:BAAANQAECgMIBAAAAA==.Silverlord:BAAANQAECgUIBgAAAA==.Sinafay:BAAANQAECgcIDwAAAA==.Siv:BAAANQAECgcIEAAAAA==.',
Sl='Slaedin:BAAANQADCgcICwAAAA==.',
Sm='Smokinbarbie:BAAANQADCgYIDAAAAA==.',
Sn='Snackkpack:BAAANQADCgcIBwAAAA==.Snapjutsu:BAAANQAECgYIDQAAAA==.Snorg:BAAANQAECgQIBQAAAA==.Snêaky:BAAANQAECgIIAgAAAA==.',
So='Solarnova:BAAANQAECgEIAQAAAA==.Solorn:BAAANQAECgQIBQAAAQ==.',
Sp='Spygon:BAAANQADCggIDgAAAA==.',
St='Strobila:BAAANQAECgIIAgAAAA==.Studdmuffin:BAAANQAECgcIEQAAAA==.',
Su='Superkylexy:BAAANQADCgIIAgAAAA==.Suuz:BAAANQAECgQIBQAAAA==.',
Sy='Syafone:BAAANQAECgIIAgAAAA==.Symuelil:BAAANQADCggIDQAAAA==.Syphiroth:BAAANQAECgMIAwAAAA==.Syrathos:BAACNQAFFIEGAAIIAAUJcgweAQC5AQAIAAUJcgweAQC5AQA1AAQKgRoAAggACQn6IhYCAJsDAAgACQn6IhYCAJsDAAAA.Syrioforel:BAAANQADCgYIDQAAAA==.',
Ta='Taojîn:BAAANQAECgcIDQAAAA==.Tarted:BAAANQAECgQIBQAAAA==.',
Te='Teclis:BAAANQAECgcIEQAAAA==.Telzindrov:BAAANQAECgEIAgAAAA==.Terrorwithin:BAAANQAECgMIAwAAAA==.',
Th='Thalgar:BAAANQADCggICAAAAA==.Thalmick:BAAANQAECgcIDQAAAA==.Thanoslye:BAAANQADCgIIAgAAAA==.Theblackfish:BAAANQADCgUIBQAAAA==.Thogarn:BAAANQADCggIEAAAAA==.Thunderkat:BAAANQADCgUIBQABNQADCggICwABAAAAAA==.Thundertem:BAAANQADCgcIDAAAAA==.Théière:BAAANQAECgQIBQAAAA==.',
Ti='Tigglebits:BAAANQABCgQIBgABNQADCgUICgABAAAAAA==.Tiraeda:BAAANQADCgMIAwAAAA==.Titoxs:BAAANQAECgMIBAABNQAECgYICQABAAAAAA==.',
To='Toughlove:BAAANQADCgUIBQAAAA==.',
Tr='Trev:BAAANQAECgQIBQAAAA==.Trustfäll:BAAANQADCgcIEQAAAA==.',
Ts='Tsunãmi:BAAANQAECgQIBgAAAA==.',
Tu='Tuc:BAAANQADCggIFAAAAA==.',
Ty='Tyndareos:BAAANQADCgQIBQAAAA==.Typhoontravv:BAAANQAECgcIEgAAAA==.',
['Tø']='Tøkakagé:BAAANQADCgcIEAAAAA==.',
Uf='Ufearme:BAAANQADCgYICwAAAA==.',
Ug='Ugabooga:BAAANQAECggIEgAAAA==.Uggon:BAAANQADCggIEQAAAA==.',
Un='Unable:BAAANQADCgcIEQAAAA==.',
Ur='Urrikahn:BAAANQADCgIIAgAAAA==.',
Ut='Uthur:BAAANQAECgMIAwAAAA==.Utterchaos:BAAANQAECgcIEQAAAA==.',
Va='Vaelaven:BAAANQAECgYICgAAAA==.Valack:BAAANQADCgUIBQAAAA==.Valfore:BAAANQAECgYICQAAAA==.Valizor:BAAANQAECgEIAQAAAA==.Vanidosa:BAAANQADCgMIAwAAAA==.Varty:BAAANQADCgYIBAAAAA==.Vayle:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.',
Ve='Velaara:BAAANQADCgYICAAAAA==.Velaari:BAAANQADCgEIAQAAAA==.Verdant:BAAANQADCgcIBwAAAA==.Vetta:BAAANQAECgcIDwAAAA==.',
Vg='Vger:BAAANQADCgIIAwAAAA==.',
Vi='Vikvikvik:BAAANQADCgUIBQAAAA==.Vild:BAAANQADCgUIBQAAAA==.Vinick:BAAANQADCgUIBQAAAA==.',
Vo='Vond:BAAANQABCgIIAgAAAA==.',
['Vè']='Vèrity:BAAANQADCgYIDAABNQADCgcIBwABAAAAAA==.',
Wa='Wazul:BAAANQADCgUICwAAAA==.',
Wh='Whisp:BAAANQADCgUIBQAAAA==.Whitespell:BAAANQAECgQICwAAAA==.',
Wi='Wickfel:BAAANQADCgcIDAAAAA==.',
Wy='Wyldfarmer:BAAANQADCgcIEQAAAA==.',
Xa='Xanid:BAAANQAECgQIBAAAAA==.',
Xd='Xdwarf:BAAANQADCgUIBwABNQAECgUIBgABAAAAAA==.',
Xe='Xeroxoxo:BAABNQAECoERAAIJAAcJax7OEgCDAgAJAAcJax7OEgCDAgAAAA==.',
Ym='Ymedead:BAAANQADCgYIBgABNQAECgcIEQABAAAAAA==.',
Yo='Yoroichi:BAAANQAECgUIBgAAAA==.Yourmomsride:BAAANQAECgcIDAAAAA==.Youtube:BAAANQAECggIBwAAAA==.',
Yu='Yueyue:BAAANQAECgEIAQAAAA==.Yungtwizzler:BAAANQADCgMIAwABNQADCggIFgABAAAAAA==.',
['Yá']='Yáng:BAAANQAECgMIAwAAAA==.',
Za='Zarylathanea:BAAANQAECgQIBwAAAA==.',
Ze='Zenheals:BAAANQADCggIBgAAAA==.',
Zi='Zindi:BAAANQADCggIEQAAAA==.',
Zo='Zoni:BAAANQADCgcIBwAAAA==.Zoobee:BAAANQADCgcIDwAAAA==.Zoog:BAAANQAECgcIEQAAAA==.',
Zy='Zyrana:BAAANQADCgIIAgAAAA==.Zyridal:BAAANQAECgQIBwAAAA==.Zyvara:BAAANQAECgEIAQAAAA==.',
['Zä']='Zärèlíä:BAABNQAECoEcAAIKAAkJmx0HBAAhAwAKAAkJmx0HBAAhAwAAAA==.',
['Æz']='Æz:BAAANQAECgQIBAAAAA==.',
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
