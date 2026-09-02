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
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abraxes:BAAANQADCgcIDQAAAA==.',
Ac='Acidemon:BAAANQADCgcIDAAAAA==.',
Ad='Adalaide:BAAANQAECgEIAQAAAA==.Adannis:BAAANQADCggICAAAAA==.Adolyn:BAAANQADCggIEQAAAA==.',
Ae='Aeluna:BAAANQADCgYICgAAAA==.Aethas:BAAANQADCgMIBQAAAA==.',
Af='Affective:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.',
Ai='Aidard:BAAANQABCgQIBAAAAA==.Airdd:BAAANQADCgEIAQAAAA==.Aizlyn:BAAANQADCgQIBwAAAA==.',
Ak='Akio:BAAANQAECgEIAQAAAA==.',
Al='Aldarya:BAAANQADCgcIBwAAAA==.Alisara:BAAANQAECgQIBwAAAA==.Alish:BAAANQADCgYICQAAAA==.Allexx:BAAANQADCggIDgAAAA==.Allyssel:BAAANQAFFAEIAQAAAA==.Alrictus:BAAANQADCggIBwAAAA==.',
Am='Amasu:BAAANQAECgYICgAAAA==.Amazinggrace:BAAANQAECgMIAwAAAA==.Ammathendis:BAAANQADCgQIBAABNQADCgcICQABAAAAAA==.Ampere:BAAANQADCgYIBgAAAA==.',
An='Anastriana:BAAANQADCgYICgAAAA==.Angeal:BAAANQADCgIIAgAAAA==.Angrychef:BAAANQADCgUIBgAAAA==.Animus:BAAANQAECgIIAgAAAA==.Annamei:BAAANQADCgcIDAAAAA==.',
Ao='Aoife:BAAANQAECgEIAQAAAA==.Aorina:BAAANQAECgQICQAAAA==.',
Ar='Arazalor:BAAANQAECgEIAQAAAA==.Arcangel:BAAANQAECgYICgAAAA==.Arrash:BAAANQADCgYICwAAAA==.Arthritic:BAAANQADCgcIDAAAAA==.Arthurdent:BAAANQAECgMIAwAAAA==.',
As='Ashara:BAAANQADCggIDQAAAA==.',
At='Atheren:BAAANQADCggIDQAAAA==.Atulan:BAAANQAECgIIAgAAAA==.',
Au='Auntiemimi:BAAANQADCgUICAAAAA==.',
Av='Avannar:BAAANQADCgUIBwAAAA==.Avelyn:BAAANQADCgEIAQAAAA==.Aveìl:BAAANQADCgUIBQAAAA==.Aviae:BAAANQADCgYICwAAAA==.',
Ay='Ayani:BAAANQADCgcICwAAAA==.',
Az='Azrine:BAAANQADCgcIDAAAAA==.',
Ba='Baddkharma:BAAANQADCgQIBAAAAA==.Badras:BAAANQAECgIIAgAAAA==.Bagelz:BAAANQAECgYICgAAAA==.Bathomula:BAAANQADCgcIDAAAAA==.Bayla:BAAANQADCgUIBQABNQAECgcIDwABAAAAAA==.Bazzwar:BAAANQADCgUIBQABNQADCgYICgABAAAAAA==.',
Be='Beric:BAAANQADCggICAAAAA==.Betadine:BAAANQADCgEIAQAAAA==.Bexy:BAAANQAECgEIAQAAAA==.',
Bl='Blade:BAAANQAECgEIAQAAAA==.',
Bo='Boohaha:BAAANQAECgUICQAAAA==.Bormagh:BAAANQADCgUIBQAAAA==.Borris:BAAANQAECgQIBAAAAA==.',
Br='Brightwing:BAAANQAECgUIBgAAAA==.Brigorath:BAAANQADCgUICgAAAA==.Brokenarro:BAAANQADCgQIBgAAAA==.',
Bu='Bubblebae:BAAANQADCgYIDwAAAA==.Bullshivek:BAAANQADCgcIDAAAAA==.',
Ca='Caecus:BAAANQADCgcIDAAAAA==.Callsaul:BAEANQADCgUIBwAAAA==.Casmus:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Caylissa:BAAANQADCgYICQAAAA==.',
Ce='Cenvoked:BAAANQADCggIDgAAAA==.Cepha:BAAANQADCgQIBAAAAA==.',
Ch='Charbethicc:BAAANQAECgMIAwAAAA==.Charlondrus:BAAANQADCgQIBgABNQAECgMIAwABAAAAAA==.Chijoku:BAAANQAECgEIAQAAAA==.Chimster:BAAANQADCgYIBgAAAA==.Chuckstrike:BAAANQADCgUIBQAAAA==.Chyna:BAAANQADCgEIAQAAAA==.',
Co='Corvò:BAAANQAECgEIAQAAAA==.',
Cr='Craeus:BAAANQADCggIDAAAAA==.Cralk:BAAANQAECgMIAgABNQAECgQIAQABAAAAAA==.Cranked:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.',
Cy='Cyonarah:BAAANQADCgUIBQAAAA==.',
Da='Darem:BAAANQADCgcIDQAAAA==.',
De='Decnahne:BAAANQADCgUIBQAAAA==.Deepwood:BAAANQAECgEIAQAAAA==.Deidra:BAAANQADCgUICgAAAA==.',
Di='Dietdrpeeper:BAAANQAECgQIBAAAAA==.Diggi:BAAANQADCgcIDQAAAA==.Diosa:BAAANQAECgEIAQAAAA==.Divinekat:BAAANQADCgYIBgAAAA==.Dizza:BAAANQADCgUIBQAAAA==.',
Dk='Dkagon:BAAANQAECgIIAgAAAA==.',
Do='Docholiday:BAAANQADCgUICgAAAA==.Dontticklmeh:BAAANQADCgMIAgAAAA==.Doode:BAAANQADCgYIDAAAAA==.Dooderonomy:BAAANQADCgcIDAAAAA==.',
Dr='Dragaan:BAAANQADCgcIDQAAAA==.Dragonbait:BAAANQAECgEIAQAAAA==.Dragonoodles:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Dragonzbane:BAAANQADCgcIDAAAAA==.Dranosh:BAAANQADCgUIBQABNQADCggIEgABAAAAAA==.Dreamawake:BAAANQADCgYIAgAAAA==.Drek:BAAANQAECgIIAgAAAA==.Drenea:BAAANQADCgUIBwAAAA==.Drin:BAAANQADCgcIDAAAAA==.',
Dy='Dyriana:BAAANQADCgUIBQAAAA==.',
['Dä']='Däustin:BAAANQADCgYIBgAAAA==.',
Ec='Ecto:BAAANQAECgIIAgAAAA==.',
El='Eleshn:BAAANQADCggICQAAAA==.Ellasian:BAAANQADCgQIBAAAAA==.Ellewoods:BAAANQADCgYIBwAAAA==.Eltria:BAAANQAECgYICgAAAA==.',
Em='Empathy:BAAANQAECgEIAQAAAA==.',
En='Ennuii:BAAANQADCggIEQAAAA==.',
Ep='Ephel:BAAANQAECgEIAQAAAA==.',
Es='Essential:BAAANQAECgYICgAAAA==.',
Ex='Exces:BAAANQADCgUIBQAAAA==.',
Ez='Ezalth:BAAANQADCgUICAAAAA==.Ezz:BAAANQADCgYIBgAAAA==.',
Fa='Faenara:BAAANQAECgEIAQAAAA==.Falafelguy:BAAANQAECgMIBgAAAA==.Falron:BAAANQADCgEIAQAAAA==.Farhund:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Faruqq:BAAANQADCggIDgAAAA==.',
Fe='Felafel:BAAANQADCgMIBAABNQAECgMIBgABAAAAAA==.Felartamiel:BAAANQADCgUICAAAAA==.Felkieler:BAAANQADCgYICAAAAA==.Fey:BAAANQAECgMIAwAAAA==.',
Fi='Fishron:BAAANQADCgcIDAAAAA==.',
Fl='Flaz:BAAANQAECgQIBAAAAA==.',
Fo='Forestspirit:BAAANQADCggIDgAAAA==.',
Fr='Frawda:BAAANQAECgEIAQAAAA==.',
Fu='Fusillidari:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.',
Ga='Galaxyman:BAAANQADCgMIAwAAAA==.',
Ge='Geist:BAAANQAECgYICgAAAA==.Geraith:BAAANQAECgQICAAAAA==.Gerios:BAAANQAECgEIAQAAAA==.',
Gg='Ggparts:BAAANQABCgIIAwABNQADCgIIAwABAAAAAA==.',
Gh='Ghostflair:BAAANQADCgEIAQAAAA==.Ghostflare:BAAANQADCgYIBwAAAA==.',
Gl='Glendra:BAAANQADCggIDgAAAA==.',
Gn='Gnomércy:BAAANQADCgMIAwAAAA==.',
Go='Goatboat:BAAANQADCgQIBwAAAA==.',
Gr='Grandeeny:BAAANQADCggIDAAAAA==.Greensleeves:BAAANQADCgUIBgAAAA==.Gregoriusz:BAAANQAECgQIBAAAAA==.Greygull:BAAANQADCgUICAAAAA==.',
Gu='Guinness:BAAANQADCgcIDAAAAA==.Guntank:BAAANQAECgEIAQAAAA==.',
Ha='Hategnomer:BAAANQADCgUIBwAAAA==.Havenfell:BAAANQADCggIDgAAAA==.Hawkfist:BAAANQADCggIDgAAAA==.',
He='Hercules:BAAANQAECgcICgAAAA==.',
Hi='Hierodoulos:BAAANQAECgEIAQAAAA==.',
Ho='Holykat:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Hotcha:BAAANQADCgEIAQAAAA==.',
Hr='Hroth:BAAANQADCggIDgAAAA==.',
Hu='Hunteroni:BAAANQADCgYICQABNQAECgEIAQABAAAAAA==.',
Ig='Iggity:BAAANQABCgIIAwAAAA==.',
Ih='Ihri:BAAANQADCggIDQAAAA==.',
Ik='Ikthus:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.',
Il='Illtud:BAAANQADCgUICgAAAA==.Ilyessa:BAAANQAECgYICQAAAA==.',
Ir='Ironpipes:BAAANQADCgcICwAAAA==.',
Is='Iskrå:BAAANQADCgYIDAAAAA==.',
Ja='Jacynth:BAAANQADCgIIAgAAAA==.Jaimers:BAAANQAECgEIAQAAAA==.Jardinn:BAAANQADCgMIAwAAAA==.Jaxen:BAAANQAECgMIAwAAAA==.Jaxon:BAAANQADCgUIBQAAAA==.Jaywilde:BAAANQAECgYICwAAAA==.',
Je='Jerusalaem:BAAANQADCgEIAQAAAA==.',
Ji='Jizakazam:BAAANQAECgEIAQAAAA==.',
Ju='Juggyspally:BAAANQADCggIDgAAAA==.',
Ka='Karotten:BAAANQADCggIDAAAAA==.Karthair:BAAANQADCgYICwAAAA==.Kassoa:BAAANQADCgMIAwAAAA==.Kaszim:BAAANQAECgMIAwAAAA==.',
Ke='Keello:BAAANQADCgYICgAAAA==.Kernelsandrs:BAAANQAECgYICgAAAA==.',
Ki='Killgore:BAAANQADCgYIBgAAAA==.Kintsugi:BAAANQADCgcIDAAAAA==.Kirinmaruu:BAAANQADCgQIBAAAAA==.Kirisatsu:BAAANQADCgYICQAAAA==.Kisatchie:BAAANQADCgYIDAAAAA==.',
Ko='Koalitsiya:BAAANQADCgYIBgAAAA==.Kozãk:BAAANQADCgMIAwAAAA==.',
Kr='Krimez:BAAANQAECgQIBAAAAA==.Krynez:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.',
Ky='Kyrhios:BAAANQAECgIIAgAAAA==.',
['Kä']='Käggai:BAAANQAECgYIBwAAAA==.',
['Kò']='Kòld:BAAANQAECgUICAAAAA==.Kòume:BAAANQADCgMIAgAAAA==.',
La='Lana:BAAANQADCgIIAgAAAA==.Lark:BAAANQADCgUIBQAAAA==.Larthas:BAAANQAECgEIAQAAAA==.Lascie:BAAANQAECgEIAQAAAA==.',
Le='Leafykat:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Leaila:BAAANQADCgUIBwAAAA==.Leiha:BAAANQADCgcICAAAAA==.',
Li='Liams:BAAANQADCgUIBwAAAA==.Lidless:BAAANQAECgEIAQAAAA==.Linux:BAAANQADCgcICQAAAA==.',
Ll='Llamadin:BAAANQADCgcIDAAAAA==.',
Lo='Logknight:BAAANQADCgEIAQAAAA==.',
Lu='Luminianna:BAAANQAECgMIAwAAAA==.',
Ly='Lytol:BAAANQADCgIIAwAAAA==.',
Ma='Macloc:BAAANQADCgcIDAAAAA==.Maggiemae:BAAANQADCgUICgAAAA==.Mahli:BAAANQAECgEIAQAAAA==.Marrias:BAAANQAECgUIBwAAAA==.Mawrix:BAAANQADCggIDgAAAA==.',
Me='Mechchimy:BAAANQAECgEIAQAAAA==.Meith:BAAANQADCgEIAQAAAA==.Melwazul:BAAANQADCgMIAwAAAA==.Merazi:BAAANQADCgMIAwAAAA==.Mesuryte:BAAANQAECgcIDQAAAA==.',
Mi='Mibs:BAAANQADCgYIDAAAAA==.Mickal:BAAANQAECgEIAQAAAA==.Mikaelangelo:BAAANQADCgUIBQAAAA==.Mip:BAAANQADCgUICQAAAA==.Mirie:BAAANQADCgUIBQAAAA==.',
Mn='Mnrogar:BAAANQADCgQIBQAAAA==.',
Mo='Mohegon:BAAANQADCgQIBQAAAA==.Mohini:BAAANQADCggIDgAAAA==.Mojhohammers:BAAANQADCgUIBQAAAA==.Mooter:BAAANQAECgYIBgAAAA==.Morchak:BAAANQADCgYIBgAAAA==.Mornix:BAAANQADCgUIBQAAAA==.',
My='Mystweaver:BAAANQADCgYIBgAAAA==.',
Na='Naota:BAAANQAECgEIAQAAAA==.Narfox:BAAANQADCgcICwAAAA==.Nazzern:BAAANQAECgIIAgAAAA==.',
Ne='Neameto:BAAANQADCggIDgAAAA==.Necrophyle:BAAANQADCggICAAAAA==.Nefarox:BAAANQADCgYICQAAAA==.Nerfslappy:BAAANQADCgUICQAAAA==.',
Ni='Nightman:BAAANQAECgEIAQAAAA==.Nightstealer:BAAANQADCgUICgAAAA==.Nikkikayama:BAAANQAECgYICgAAAA==.Nikol:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
No='Norikoff:BAAANQAECgQIBAAAAA==.',
Ny='Nyalla:BAAANQADCgUIBwAAAA==.',
['Nï']='Nïdalee:BAAANQADCgYIBgAAAA==.',
Oc='Octoberfae:BAAANQADCgMIAwAAAA==.Octwitch:BAAANQADCgUIBQAAAA==.',
Of='Offdensen:BAAANQADCgUICgAAAA==.',
Ok='Okku:BAAANQADCgYICgAAAA==.',
Ol='Oldmims:BAAANQAECgEIAQAAAA==.',
On='Onlybatfans:BAAANQADCggICAAAAA==.',
Op='Ophina:BAAANQADCgQIBAAAAA==.',
Or='Oramu:BAAANQAECgQIBgAAAA==.Orangejello:BAAANQADCgYIDAAAAA==.Orion:BAAANQADCgMIAwABNQAECgYICQABAAAAAA==.Oriòn:BAAANQADCgYICwAAAA==.',
Pa='Paiah:BAAANQADCgIIAgAAAA==.Pallykillers:BAAANQADCgQIBgAAAA==.Pana:BAAANQAECgMIAwAAAA==.Pandy:BAAANQADCgcIDAAAAA==.Pannifer:BAAANQADCgYIDAAAAA==.Paolon:BAAANQADCgYIDAAAAA==.Parple:BAAANQAECgIIAwABNQAECgcICwABAAAAAA==.',
Pe='Penelopei:BAAANQADCgcICwAAAA==.',
Ph='Phantõm:BAAANQADCgMIAwAAAA==.',
Pi='Picker:BAAANQADCgYIBgAAAA==.',
Po='Poledra:BAAANQADCgUIBQAAAA==.Porterah:BAAANQADCggIDwAAAA==.Poutyne:BAAANQAECgQIBQAAAA==.',
Pr='Priestress:BAAANQABCgQIBwAAAA==.Profanus:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.',
Pu='Punchnugget:BAAANQAECgEIAQAAAA==.Punkvc:BAAANQAECgIIAgAAAA==.',
Py='Pyren:BAAANQADCgUIBQAAAA==.',
['Pá']='Párts:BAAANQADCgIIAwAAAA==.',
Qu='Quaeras:BAAANQAECgEIAQAAAA==.',
Ra='Rabiess:BAAANQADCggIDgAAAA==.Ragingnoodle:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Ragingshnoz:BAAANQAECgEIAQAAAA==.Ragé:BAEANQAECgUICQAAAA==.Rakklock:BAAANQADCgQICAAAAA==.Ralphe:BAAANQAECgIIAgAAAA==.Raytow:BAAANQAECgMIAwAAAA==.Razelle:BAAANQADCgcIDAAAAA==.',
Re='Reconpalymix:BAAANQADCgIIAgAAAA==.Relana:BAAANQADCgIIAgAAAA==.Remus:BAAANQADCgYIBgAAAA==.Ressix:BAAANQAECgEIAQAAAA==.',
Rh='Rhaeyn:BAAANQADCgMIAwABNQADCggIDgABAAAAAA==.',
Ri='Ripture:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Rizzwar:BAAANQADCgQIBQAAAA==.',
Ro='Roastbeefin:BAAANQADCgIIAgAAAA==.Ronborules:BAAANQADCgQIBAAAAA==.Rosenta:BAAANQADCgYIDAAAAA==.',
Ru='Rumlock:BAAANQADCgcIDAAAAA==.',
['Rö']='Röwnin:BAAANQADCgQIBgAAAA==.',
Sa='Sabinah:BAAANQADCgcIDAAAAA==.Sabing:BAAANQADCgUIBwAAAA==.Saiah:BAAANQADCgYICgAAAA==.Saintbazz:BAAANQADCgYICgAAAA==.Sal:BAAANQAECgcICwAAAA==.Salivan:BAAANQADCgYICQAAAA==.Sargaris:BAAANQADCggICAAAAA==.Sariva:BAAANQAECgcIDwAAAA==.Saurva:BAAANQAECgYICgAAAA==.Sawfang:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Saxophone:BAAANQADCgcICwAAAA==.Sayna:BAAANQAECgQIBAAAAA==.',
Sc='Scarecro:BAAANQAECgEIAQAAAA==.',
Se='Sedae:BAAANQAECgEIAQAAAA==.Seekvaira:BAAANQAECgMIAQAAAA==.Seiya:BAAANQADCggIDgAAAA==.Selira:BAAANQADCgcIDAAAAA==.Senji:BAAANQADCgUIBAAAAA==.Sevalina:BAAANQADCggIDgAAAA==.',
Sh='Shadowstep:BAAANQADCgUIBQAAAA==.Shalaah:BAAANQADCggIDAAAAA==.Shamhuntzu:BAEANQAECgYICgAAAA==.Shampaign:BAAANQAECgEIAQAAAA==.Shaoevoker:BAAANQADCgIIAgAAAA==.Sharnara:BAAANQADCggIDQAAAA==.Shatterskull:BAAANQADCggIEgAAAA==.Shazira:BAAANQADCgUIBQAAAA==.Shep:BAAANQADCgYIBgAAAA==.',
Si='Sideffects:BAAANQAECgEIAQAAAA==.Sidewinder:BAAANQADCggICAAAAA==.Silvercircle:BAAANQAECgEIAQAAAA==.Silverlord:BAAANQAECgEIAQAAAA==.Sinafay:BAAANQAECgQICAAAAA==.Siv:BAAANQAECgUICQAAAA==.',
Sl='Slaedin:BAAANQADCgQIBAAAAA==.',
Sm='Smokinbarbie:BAAANQADCgQIBgAAAA==.',
Sn='Snackkpack:BAAANQADCgYIBgAAAA==.Snapjutsu:BAAANQAECgUIBwAAAA==.Snorg:BAAANQAECgEIAQAAAA==.Snêaky:BAAANQADCggIDgAAAA==.',
So='Solarnova:BAAANQADCgcIDAAAAA==.Solorn:BAAANQAECgEIAQAAAQ==.',
Sp='Spygon:BAAANQADCgYIBgAAAA==.',
St='Strobila:BAAANQADCggIDAAAAA==.Studdmuffin:BAAANQAECgYICgAAAA==.',
Su='Suuz:BAAANQAECgEIAQAAAA==.',
Sy='Syafone:BAAANQAECgIIAgAAAA==.Sylvië:BAAANQADCgUICgAAAA==.Symuelil:BAAANQADCgUIBQAAAA==.Syphiroth:BAAANQADCggIDwAAAA==.Syrathos:BAAANQAFFAEIAQAAAA==.Syrioforel:BAAANQADCgYIDQAAAA==.',
Ta='Taojîn:BAAANQAECgQIBgAAAA==.Tarted:BAAANQAECgEIAQAAAA==.',
Te='Teclis:BAAANQAECgYICgAAAA==.Telzindrov:BAAANQAECgEIAQAAAA==.Terrorwithin:BAAANQADCggIDgAAAA==.',
Th='Thalgar:BAAANQADCggICAAAAA==.Thalmick:BAAANQAECgUIBgAAAA==.Theblackfish:BAAANQADCgUIBQAAAA==.Thogarn:BAAANQADCggICAAAAA==.Thunderkat:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Thundertem:BAAANQADCgUIBQAAAA==.Théière:BAAANQAECgEIAQAAAA==.',
Ti='Tigglebits:BAAANQABCgIIAgABNQADCgUICgABAAAAAA==.Tiraeda:BAAANQADCgMIAwAAAA==.',
To='Toughlove:BAAANQADCgUIBQAAAA==.',
Tr='Trev:BAAANQAECgMIAQAAAA==.Trustfäll:BAAANQADCgUICgAAAA==.',
Ts='Tsunãmi:BAAANQAECgIIAgAAAA==.',
Tu='Tuc:BAAANQADCgUIBQAAAA==.',
Ty='Tyndareos:BAAANQADCgQIBAAAAA==.Typhoontravv:BAAANQAECgYICQAAAA==.',
['Tø']='Tøkakagé:BAAANQADCgYICQAAAA==.',
Uf='Ufearme:BAAANQADCgYIBgAAAA==.',
Ug='Ugabooga:BAAANQAECgcICgAAAA==.Uggon:BAAANQADCgYICQAAAA==.',
Un='Unable:BAAANQADCgcIDAAAAA==.',
Ur='Urrikahn:BAAANQADCgIIAgAAAA==.',
Ut='Uthur:BAAANQADCgYIDAAAAA==.Utterchaos:BAAANQAECgcICgAAAA==.',
Va='Vaelaven:BAAANQAECgMIBAAAAA==.Valfore:BAAANQAECgMIAwAAAA==.Valizor:BAAANQADCgcIBwAAAA==.Vanidosa:BAAANQADCgIIAgAAAA==.Vayle:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Ve='Velaara:BAAANQADCgQIBgAAAA==.Velaari:BAAANQADCgEIAQAAAA==.Vetta:BAAANQAECgQICAAAAA==.',
Vg='Vger:BAAANQADCgIIAwAAAA==.',
Vi='Vild:BAAANQADCgUIBQAAAA==.Vinick:BAAANQADCgMIAwAAAA==.',
Vo='Vond:BAAANQABCgMIAwAAAA==.',
['Vè']='Vèrity:BAAANQADCgYIBgAAAA==.',
Wa='Wazul:BAAANQADCgUIBgAAAA==.',
Wh='Whisp:BAAANQADCgUIBQAAAA==.Whitespell:BAAANQAECgQIBwAAAA==.',
Wi='Wickfel:BAAANQADCgUIBQAAAA==.',
Wy='Wyldfarmer:BAAANQADCgUICgAAAA==.',
Xa='Xanid:BAAANQADCgUICQAAAA==.',
Xd='Xdwarf:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Xe='Xeroxoxo:BAAANQAECgYICgAAAA==.',
Ym='Ymedead:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.',
Yo='Yoroichi:BAAANQAECgEIAQAAAA==.Yourmomsride:BAAANQADCggICAAAAA==.',
Yu='Yueyue:BAAANQADCgYIBgAAAA==.',
Za='Zarylathanea:BAAANQAECgMIAwAAAA==.',
Ze='Zenheals:BAAANQADCggIBgAAAA==.',
Zi='Zindi:BAAANQADCggIEQAAAA==.',
Zo='Zoni:BAAANQADCgcIBwAAAA==.Zoobee:BAAANQADCgYICgAAAA==.Zoog:BAAANQAECgYICgAAAA==.',
Zy='Zyridal:BAAANQAECgMIAwAAAA==.Zyvara:BAAANQADCgUIBQAAAA==.',
['Zä']='Zärèlíä:BAAANQAECgcIEQAAAA==.',
['Æz']='Æz:BAAANQADCgMIAwAAAA==.',
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
