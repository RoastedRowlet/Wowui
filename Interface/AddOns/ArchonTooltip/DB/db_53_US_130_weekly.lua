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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Warrior-Arms','DemonHunter-Devourer','Hunter-Marksmanship','Paladin-Protection','Hunter-Survival','Warrior-Fury','Priest-Shadow','Warlock-Demonology','Warlock-Affliction','Monk-Brewmaster','Mage-Arcane','Paladin-Retribution',}
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abonde:BAAANQADCggICAAAAA==.Abraxes:BAAANQAECgMIBAAAAA==.',
Ac='Acidemon:BAAANQADCggIHAAAAA==.',
Ad='Adalaide:BAAANQAECgQIBQAAAA==.Adannis:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.Adelane:BAAANQAECgEIAQABNQAECgUIDAABAAAAAA==.Adolyn:BAAANQADCggIEQAAAA==.',
Ae='Aeluna:BAAANQAECgEIAQAAAA==.Aethas:BAAANQADCgYICAAAAA==.',
Af='Affective:BAAANQAECgcIDQABNQAECgkJHgACACchAA==.Afkk:BAAANQADCggIBAAAAA==.',
Ah='Ahuramazda:BAAANQAECgEIAQAAAA==.',
Ai='Aidard:BAAANQABCggIDwAAAA==.Airdd:BAAANQADCgEIAQAAAA==.Aizlyn:BAAANQADCgcIDwAAAA==.',
Ak='Akio:BAAANQAECgYICwAAAA==.',
Al='Aldarya:BAAANQAECgMIBAAAAA==.Alisara:BAABNQAECoEVAAIDAAgJjCTMCABHAwADAAgJjCTMCABHAwAAAA==.Alish:BAAANQADCggIFwAAAA==.Allexx:BAAANQAECgUIBwAAAA==.Allyssel:BAACNQAFFIEGAAIEAAMJZxQZBAANAQAEAAMJZxQZBAANAQA1AAQKgR8AAgQACQl8JmcAAPwDAAQACQl8JmcAAPwDAAAA.Alrictus:BAAANQADCggIDwAAAA==.',
Am='Amasu:BAAANQAECgcIEgAAAA==.Amazinggrace:BAAANQAECgUIDAAAAA==.Amentiu:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Ammathendis:BAAANQADCgQIBAABNQAECgIIAwABAAAAAA==.Ammiel:BAAANQADCgEIAQABNQAECgkJFwAFAH0ZAA==.Ampera:BAAANQADCgYIBgAAAA==.',
An='Anastriana:BAAANQAECgEIAQAAAA==.Angeal:BAAANQAECgMIBAAAAA==.Angrychef:BAAANQADCgYIDAAAAA==.Animus:BAAANQAECgUICwAAAA==.Annamei:BAAANQAECgMIAwAAAA==.',
Ao='Aoife:BAAANQAECgQIBwAAAA==.Aorina:BAAANQAECgYIEwAAAA==.',
Ar='Arazalor:BAAANQAECgUICgAAAA==.Arcangel:BAABNQAECoEYAAMGAAkJ/CK0AQCEAwAGAAkJ/CK0AQCEAwAHAAEJ+RmWaABKAAAAAA==.Arrash:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Arthritic:BAAANQADCgcIEgAAAA==.Arthurdent:BAAANQAECgUICgAAAA==.',
As='Ashara:BAAANQAECgUICAAAAA==.Ashenrain:BAAANQADCggICAAAAA==.Ashvia:BAAANQADCgcIBwAAAA==.Aspiration:BAAANQABCgMIBQAAAA==.',
At='Atheren:BAAANQAECgUIBQAAAA==.Athshu:BAAANQADCgcIBwAAAA==.Atulan:BAAANQAECgUICwAAAA==.',
Au='Auntiemimi:BAAANQAECgEIAQAAAA==.',
Av='Avalina:BAAANQAECgYICgABNQAECgkJHQAIAK8fAA==.Avannar:BAAANQADCgUIDgAAAA==.Avelyn:BAAANQADCgEIAQAAAA==.Aveìl:BAAANQADCgUIBQAAAA==.Aviae:BAAANQADCgcIEgAAAA==.',
Ay='Ayani:BAAANQAECgYICgAAAA==.',
Az='Azrine:BAAANQADCggIFAAAAA==.',
Ba='Baddattitude:BAAANQADCgUIBwABNQADCggIEwABAAAAAA==.Baddkharma:BAAANQADCgQICwAAAA==.Badras:BAAANQAECgYIDAAAAA==.Bagelz:BAAANQAECgcIEgAAAA==.Bathomula:BAAANQAECgMIBAAAAA==.Bayla:BAAANQADCgUIBQABNQAFFAQICAAJAKwXAA==.Bazzwar:BAAANQADCggICwABNQAECgEIAQABAAAAAA==.',
Be='Beric:BAAANQAECgcIBwAAAA==.Betadine:BAAANQAECgQIBAAAAA==.Bexy:BAAANQAECgUICwABNQAECgcIDAABAAAAAA==.',
Bl='Blade:BAAANQAECgUICgAAAA==.',
Bo='Boldan:BAAANQABCgEIAQAAAA==.Boohaha:BAAANQAECggIDwAAAA==.Booze:BAAANQAECgMIAwAAAA==.Bormagh:BAAANQADCgUIBQAAAA==.Borris:BAAANQAECgcIEgAAAA==.',
Br='Brightwing:BAAANQAECgcIEwAAAA==.Brigorath:BAAANQADCggIGQAAAA==.Brokenarro:BAAANQADCgYIEgAAAA==.',
Bu='Bubblebae:BAAANQAECgQIBgAAAA==.Bullshivek:BAAANQAECgEIAQAAAA==.',
Ca='Caale:BAAANQAECgIIAgAAAA==.Caecus:BAAANQAECgEIAQAAAA==.Callsaul:BAEANQAECgEIAQAAAA==.Casmus:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Caylissa:BAAANQAECgEIAQAAAA==.',
Ce='Celryth:BAAANQADCgIIAgAAAA==.Cenvoked:BAAANQAECgUIBwAAAA==.Cepha:BAAANQADCgQIBAAAAA==.',
Ch='Charbethicc:BAAANQAECgUICgAAAA==.Charlondrus:BAAANQADCgQIBgABNQAECgUICgABAAAAAA==.Charticulous:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Chijoku:BAAANQAECgYIDAAAAA==.Chimster:BAAANQAECgYICwAAAA==.Chuckstrike:BAAANQADCgUIBQAAAA==.Chyna:BAAANQADCggICAAAAA==.',
Co='Corvò:BAAANQAECgEIAwAAAA==.',
Cr='Craeus:BAAANQAECgUIBQAAAA==.Cralk:BAAANQAECgYICQABNQAECgcIBQABAAAAAA==.Cranked:BAAANQAECgQIBAABNQAECggIGgAKAJ8fAA==.',
Cy='Cyonarah:BAAANQADCgcIEQAAAA==.',
Da='Darem:BAAANQADCggIEAAAAA==.',
De='Decnahne:BAAANQADCgUIBQAAAA==.Deepwood:BAAANQAECgQIBwAAAA==.Deidra:BAAANQADCgcIEQAAAA==.Devilette:BAAANQADCgEIAQAAAA==.Devry:BAAANQABCgMIAwAAAA==.',
Di='Dietdrpeeper:BAAANQAECgcIEQAAAA==.Diggi:BAAANQAECgMIBQAAAA==.Diosa:BAAANQAECgYICwAAAA==.Divinekat:BAAANQADCggIDgAAAA==.Dizza:BAAANQAECgEIAQAAAA==.',
Dk='Dkagon:BAAANQAECgYICAAAAA==.',
Do='Docholiday:BAAANQADCggIGAAAAA==.Dontticklmeh:BAAANQADCgMIAgAAAA==.Doode:BAAANQAECgQIBAAAAA==.Dooderonomy:BAAANQAECgEIAQAAAA==.Doria:BAAANQADCgQIBAAAAA==.',
Dr='Dragaan:BAAANQAECgQIBwAAAA==.Dragonbait:BAAANQAECgYIEQAAAA==.Dragonoodles:BAAANQAECgQIBgAAAA==.Dragonzbane:BAAANQAECgMIBAAAAA==.Dranosh:BAAANQADCgUIBQABNQADCggIHgABAAAAAA==.Dreamawake:BAAANQADCggICgAAAA==.Drek:BAAANQAECgIIAwAAAA==.Drenea:BAAANQADCgYIEgAAAA==.Drin:BAAANQAECgEIAgAAAA==.',
Dy='Dyriana:BAAANQADCgUIDwAAAA==.',
['Dä']='Däustin:BAAANQADCgYIBgAAAA==.',
Ec='Ecto:BAAANQAECgYIDAAAAA==.',
El='Eleshn:BAAANQADCggICQAAAA==.Ellasian:BAAANQAECgEIAQAAAA==.Ellewoods:BAAANQADCggIDwAAAA==.Eloise:BAAANQADCgUIBQAAAA==.Eltria:BAAANQAECgcIEgAAAA==.',
Em='Empathy:BAAANQAECgEIAQAAAA==.',
En='Ennuii:BAAANQADCggIEQAAAA==.',
Ep='Ephel:BAAANQAECgYICAAAAA==.',
Es='Essential:BAAANQAECgcIEgAAAA==.',
Ex='Exces:BAAANQADCgUIBQAAAA==.',
Ez='Ezalth:BAAANQADCgUIDAAAAA==.Ezz:BAAANQADCggIDwAAAA==.',
Fa='Fachzile:BAAANQADCgQIAQAAAA==.Faden:BAAANQAECgQIBAABNQAECggIGgAKAJ8fAA==.Faenara:BAAANQAECgUICgAAAA==.Falafelguy:BAAANQAECgYIEAAAAA==.Falron:BAAANQADCgEIAQAAAA==.Farhund:BAAANQADCgcIBwABNQADCgcIBwABAAAAAA==.Faruqq:BAAANQAECgUIBwAAAA==.',
Fe='Feenux:BAAANQABCgQIBAAAAA==.Felafel:BAAANQADCgMIBAABNQAECgYIEAABAAAAAA==.Felartamiel:BAAANQADCgYIEwAAAA==.Felkieler:BAAANQADCgYICAABNQAECgEIAQABAAAAAA==.Fey:BAAANQAECgUICgAAAA==.',
Fi='Fishron:BAAANQAECgEIAQAAAA==.',
Fl='Flaz:BAAANQAECgcIEQAAAA==.Fleury:BAAANQABCgUIBAAAAA==.',
Fo='Forestspirit:BAAANQAECgUIBwAAAA==.',
Fr='Frawda:BAAANQAECgUICQAAAA==.',
Fu='Fusillidari:BAAANQADCggIGwABNQAECgQIBgABAAAAAA==.Fuzzy:BAAANQADCgEIAQAAAA==.',
Ga='Galaxyman:BAAANQADCggIEQAAAA==.Garlone:BAAANQABCgcIBwAAAA==.',
Ge='Geist:BAAANQAECgcIEgAAAA==.Geraith:BAAANQAECgcIEAAAAA==.Gerios:BAAANQAECgUICgAAAA==.',
Gg='Ggparts:BAAANQADCgUIBQAAAA==.',
Gh='Ghostflair:BAAANQADCgEIAQAAAA==.Ghostflare:BAAANQAECgQIBAAAAA==.',
Gl='Glacier:BAAANQABCgQIBAAAAA==.Glendra:BAAANQAECgUIBwAAAA==.Glorificus:BAAANQADCggICAAAAA==.',
Gn='Gnomércy:BAAANQADCgMIAwAAAA==.',
Go='Goatboat:BAAANQADCgQIBwAAAA==.',
Gr='Grandeeny:BAAANQAECgQICAAAAA==.Greensleeves:BAAANQADCgYIEQAAAA==.Gregoriusz:BAAANQAECgYICgAAAA==.Greygull:BAAANQADCgcIFQAAAA==.',
Gu='Guinness:BAAANQAECgUIBgAAAA==.Guntank:BAAANQAECgYICwAAAA==.',
Ha='Hategnomer:BAAANQADCgYIEgAAAA==.Havenfell:BAAANQAECgUIBQAAAA==.Hawkfist:BAAANQAECgUIBwAAAA==.',
He='Hercules:BAABNQAECoEbAAICAAgJ1xgaGgBwAgACAAgJ1xgaGgBwAgAAAA==.Herzagon:BAAANQADCgEIAQAAAA==.',
Hi='Hierodoulos:BAAANQAECgYICwAAAA==.',
Ho='Holykat:BAAANQADCggICwABNQADCggIDgABAAAAAA==.Hotcha:BAAANQADCgEIAQAAAA==.Hotsie:BAAANQADCgMIBQAAAA==.',
Hr='Hroth:BAAANQAECgUIBwAAAA==.Hrothgar:BAAANQADCgIIAgABNQAECgUIBwABAAAAAA==.',
Hu='Hunteroni:BAAANQADCgcIFQABNQAECgQIBgABAAAAAA==.',
If='Ifearu:BAAANQADCgYIBgABNQADCgYIEgABAAAAAA==.',
Ig='Iggity:BAAANQABCgIIAwAAAA==.',
Ih='Ihri:BAAANQADCggIFQAAAA==.',
Ik='Ikthus:BAAANQAECgIIAgAAAA==.',
Il='Illtud:BAAANQADCgYIEAAAAA==.Ilyessa:BAABNQAECoEcAAIKAAkJZiF1AwBnAwAKAAkJZiF1AwBnAwAAAA==.',
Ir='Ironfur:BAAANQADCgQIBAABNQADCggIHgABAAAAAA==.Ironpipes:BAAANQAECgEIAQAAAA==.',
Is='Iskrå:BAAANQADCggIGwAAAA==.',
Ja='Jacynth:BAAANQAECgUICQAAAA==.Jaimers:BAAANQAECgUICgAAAA==.Jardinn:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Jaxen:BAAANQAECgUICwAAAA==.Jaxon:BAAANQADCggIFAAAAA==.Jaywilde:BAABNQAECoEcAAILAAgJjRMXRQAfAgALAAgJjRMXRQAfAgAAAA==.',
Je='Jerkpaladin:BAAANQADCggIDwAAAA==.Jerusalaem:BAAANQADCgEIAQAAAA==.',
Ji='Jizakazam:BAAANQAECgYICgAAAA==.',
Jo='Josepha:BAAANQADCgEIAQAAAA==.',
Ju='Juggyspally:BAAANQAECgUIBgAAAA==.Justbringit:BAEANQADCgQIBAABNQAECggIFwAMAGwjAA==.Juvens:BAAANQABCgMIAQAAAA==.',
['Jï']='Jïao:BAAANQAECgEIAQAAAA==.',
Ka='Kairiccars:BAAANQADCgYIBgAAAA==.Karotten:BAAANQAECgUIBQAAAA==.Karthair:BAAANQADCggIEwAAAA==.Kassoa:BAAANQADCgMIAwAAAA==.Kaszim:BAAANQAECgcIEAAAAA==.',
Ke='Keello:BAAANQAECggIAQAAAA==.Kelkieran:BAAANQADCgUIBQAAAA==.Kenz:BAAANQAECgEIAQAAAA==.Kernelsandrs:BAABNQAECoEXAAMDAAkJBCOECQA8AwADAAkJBCOECQA8AwANAAIJ8APLQgBeAAAAAA==.',
Ki='Killgore:BAAANQADCgYIBgAAAA==.Kintsugi:BAAANQAECgQIBAAAAA==.Kirinmaruu:BAAANQADCgUICQAAAA==.Kirisatsu:BAAANQAECgEIAQAAAA==.Kisatchie:BAAANQAECgIIAwAAAA==.',
Ko='Koalitsiya:BAAANQADCggIFgAAAA==.Kozãk:BAAANQADCgYICQAAAA==.',
Kr='Kreatos:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.Krimez:BAAANQAECgUIDAAAAA==.Krynez:BAAANQADCgUIDgABNQAECgUIDAABAAAAAA==.',
Ky='Kyrhios:BAAANQAECgYICAAAAA==.',
['Kä']='Käggai:BAAANQAECgcIDgAAAA==.',
['Kò']='Kòld:BAAANQAECgcIEwAAAA==.Kòume:BAAANQADCgMIAgAAAA==.',
La='Lana:BAAANQADCgQIBgAAAA==.Lark:BAAANQADCggIHAAAAA==.Larthas:BAAANQAECgUICgAAAA==.Lary:BAAANQADCgIIAgABNQAECgkJGwAOAPIjAA==.Lascie:BAAANQAECgUICgAAAA==.',
Le='Leafykat:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Leaila:BAAANQAECgEIAgAAAA==.Leiha:BAAANQADCggIDwAAAA==.',
Li='Liams:BAAANQADCgUIBwAAAA==.Lidless:BAAANQAECgYICgAAAA==.Linux:BAAANQAECgEIAQAAAA==.',
Ll='Llamadin:BAAANQAECgEIAQAAAA==.',
Lo='Logknight:BAAANQADCgUIBQAAAA==.',
Lu='Lukis:BAAANQADCgYIBgAAAA==.Luminianna:BAAANQAECgUIDAAAAA==.',
Ly='Lynra:BAAANQAECgEIAQAAAA==.Lytol:BAAANQADCggIEwAAAA==.',
Ma='Macloc:BAAANQAECgMIAwAAAA==.Maggiemae:BAAANQADCgUICgAAAA==.Mahli:BAAANQAECgUICgAAAA==.Marrias:BAAANQAECgYIEgAAAA==.Massacre:BAAANQAECgQIBAAAAA==.Mawrix:BAAANQAECgUICAAAAA==.',
Me='Mechchimy:BAAANQAECgEIAgAAAA==.Medîcus:BAAANQADCgIIAgAAAA==.Meith:BAAANQADCgUIBgAAAA==.Melwazul:BAAANQADCgMIAwAAAA==.Merazi:BAAANQADCgMIAwAAAA==.Mesuryte:BAABNQAECoEgAAMPAAkJ1yQzAADSAwAPAAkJ1yQzAADSAwANAAEJEA25SQA9AAAAAA==.Meyla:BAAANQADCgcIBgAAAA==.',
Mi='Mibby:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Mibs:BAAANQAECgUIBwAAAA==.Mickal:BAAANQAECgUICgAAAA==.Mikaelangelo:BAAANQAECgEIAQAAAA==.Mindrash:BAAANQAECgUIBQABNQAECgcIEgABAAAAAA==.Mip:BAAANQAECgIIAgAAAA==.Mirie:BAAANQADCgUIBQAAAA==.',
Mn='Mnrogar:BAAANQADCgQIBQAAAA==.',
Mo='Mohegon:BAAANQADCgQIBQAAAA==.Mohini:BAAANQAECgUIBwAAAA==.Mojhohammers:BAAANQADCgUIBQAAAA==.Mooquisha:BAAANQADCgYIBgAAAA==.Mooter:BAAANQAECgcIEQAAAA==.Morchak:BAAANQADCgYIBgAAAA==.Mornix:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Mu='Mushroom:BAAANQADCggICAAAAA==.',
My='Mystweaver:BAAANQADCgYIBgAAAA==.',
Na='Naota:BAAANQAECgUICgAAAA==.Naqilol:BAAANQADCgUICQAAAA==.Narfox:BAAANQADCggIGwAAAA==.Nazzern:BAAANQAECgIIAgAAAA==.',
Ne='Neameto:BAAANQAECgYIDAAAAA==.Necrophyle:BAAANQAECgQIBgAAAA==.Nefarox:BAAANQAECgEIAQAAAA==.Neilion:BAAANQADCgMIAwAAAA==.Nerfslappy:BAAANQADCgcIFgAAAA==.Nethron:BAAANQADCgUIBQAAAA==.',
Ni='Nightman:BAAANQAECgYIDAAAAA==.Nightstealer:BAAANQADCggIGQAAAA==.Nikkikayama:BAABNQAECoEdAAIDAAkJhh//CwAfAwADAAkJhh//CwAfAwAAAA==.Nikol:BAAANQAECgcIDAAAAA==.',
No='Norikoff:BAABNQAFFIEGAAMQAAQJohJaAAAEAQAQAAMJdxFaAAAEAQALAAIJhQ5/EQCYAAAAAA==.',
Ny='Nyalla:BAAANQADCgYIEgAAAA==.',
['Nï']='Nïdalee:BAAANQAECgMIBgAAAA==.',
Oc='Octoberfae:BAAANQADCgMIAwAAAA==.Octwitch:BAAANQADCggIFAAAAA==.',
Of='Offdensen:BAAANQADCgcIGAAAAA==.',
Ok='Okkotsu:BAAANQADCgcIBwAAAA==.Okku:BAAANQAECgEIAQAAAA==.',
Ol='Oldmims:BAAANQAECgYICwAAAA==.',
On='Onlybatfans:BAAANQADCggIDwAAAA==.',
Op='Ophina:BAAANQAECgEIAQAAAA==.',
Or='Oramu:BAAANQAECgYIDAAAAA==.Orangejello:BAAANQAECgIIAwAAAA==.Orion:BAAANQADCgMIAwABNQAECgkJHAAKAGYhAA==.Oriòn:BAAANQAECgEIAQAAAA==.',
Ot='Otane:BAAANQAECgYICgAAAA==.',
Pa='Paiah:BAAANQADCgIIAgAAAA==.Pallykillers:BAAANQADCgUICgAAAA==.Palyephel:BAAANQADCggICAABNQAECgYICAABAAAAAA==.Pana:BAAANQAECgUIDAAAAA==.Pandhikukka:BAAANQADCgUIBQAAAA==.Pandy:BAAANQAECgMIBAAAAA==.Pannifer:BAAANQAECgIIAwAAAA==.Paolon:BAAANQADCggIFAAAAA==.Papasmurph:BAAANQABCgIIAgAAAA==.Parple:BAAANQAECgQICAABNQAFFAMIBQARALcMAA==.',
Pe='Penelopei:BAAANQAECgMIBAAAAA==.',
Ph='Phantõm:BAAANQADCgYICQAAAA==.',
Pi='Picker:BAAANQADCgYIBgAAAA==.',
Po='Poledra:BAAANQADCgYIEAAAAA==.Porterah:BAAANQADCggIHwAAAA==.Poutyne:BAAANQAECgUIDwAAAA==.',
Pr='Priestress:BAAANQADCggICAAAAA==.Profanus:BAAANQADCgUIBQABNQAECggIGgAKAJ8fAA==.',
Pu='Punchnugget:BAAANQAECgQIBgAAAA==.Punkvc:BAAANQAECgUIBwAAAA==.',
Py='Pyren:BAAANQADCgYICwAAAA==.',
['Pá']='Párts:BAAANQADCgMIBAABNQADCgUIBQABAAAAAA==.',
Qu='Quaeras:BAAANQAECgQICAAAAA==.',
Ra='Rabiess:BAAANQAECgEIAQAAAA==.Ragingnoodle:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Ragingshnoz:BAAANQAECgUICgAAAA==.Ragé:BAEBNQAECoEXAAMMAAgJbCMBBwA3AwAMAAgJbCMBBwA3AwAEAAEJ0h8BRwBdAAAAAA==.Rakklock:BAAANQADCgcIDwAAAA==.Ralphe:BAAANQAECgQICAAAAA==.Raytow:BAAANQAECgYICQAAAA==.Razelle:BAAANQAECgEIAQAAAA==.',
Re='Reconpalymix:BAAANQAECgEIAQAAAA==.Relana:BAAANQADCgIIAgAAAA==.Remus:BAAANQAECgYIAgAAAA==.Reshad:BAAANQADCggIDQAAAA==.Ressix:BAAANQAECgUICgAAAA==.',
Rh='Rhaeyn:BAAANQADCgMIBQABNQADCggIGAABAAAAAA==.',
Ri='Ripture:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Rizzwar:BAAANQAECgQIBQAAAA==.',
Ro='Roastbeefin:BAAANQADCgIIAgAAAA==.Rockhunter:BAAANQADCggICAAAAA==.Ronborules:BAAANQADCgUIBAAAAA==.Rosenta:BAAANQAECgIIAwAAAA==.',
Ru='Rumlock:BAAANQAECgEIAQAAAA==.',
['Rö']='Röwnin:BAAANQADCgYIEgAAAA==.',
Sa='Sabinah:BAAANQAECgMIAwAAAA==.Sabing:BAAANQADCgYIEgAAAA==.Saeberis:BAAANQADCgUIBQAAAA==.Saiah:BAAANQADCggIEgAAAA==.Saintbazz:BAAANQAECgEIAQAAAA==.Sal:BAACNQAFFIEFAAIRAAMJtwytBAACAQARAAMJtwytBAACAQA1AAQKgRsAAhEACQl+HkUHACQDABEACQl+HkUHACQDAAAA.Salivan:BAAANQAECgEIAQAAAA==.Sargaris:BAAANQAECgIIAgAAAA==.Sariva:BAABNQAECoEdAAQIAAkJrx8MGwBmAQASAAYJWCC6OADuAQAIAAUJ7RYMGwBmAQATAAIJRxOfEACDAAAAAA==.Sathalis:BAAANQADCgYICwAAAA==.Saurva:BAAANQAECgcIEgAAAA==.Sawfang:BAAANQADCgIIAgABNQAECgYIDAABAAAAAA==.Saxophone:BAAANQAECgQICAAAAA==.Sayna:BAAANQAECgUIDAAAAA==.',
Sc='Scarecro:BAAANQAECgUICgAAAA==.',
Se='Sedae:BAAANQAECgYIBgAAAA==.Seekvaira:BAAANQAECgYIDQAAAA==.Seiya:BAAANQAECgQIBQAAAA==.Selira:BAAANQAECgEIAQAAAA==.Senji:BAAANQAECgMIAwAAAA==.Senseitots:BAAANQABCgQIBAAAAA==.Sevalina:BAAANQAECgUIBwAAAA==.',
Sh='Shadowstep:BAAANQADCggIFAAAAA==.Shalaah:BAAANQAECgMIBAAAAA==.Shamhuntzu:BAEANQAECgcIEgAAAA==.Shampaign:BAAANQAECgUICgAAAA==.Shaoevoker:BAAANQADCggIEgAAAA==.Sharnara:BAAANQAECgQIBAAAAA==.Shatterskull:BAAANQADCggIHgAAAA==.Shazira:BAAANQADCggIFAAAAA==.Shep:BAAANQAECgEIAQAAAA==.Sherloch:BAAANQADCgEIAQAAAA==.Shmollboi:BAAANQABCgIIAgAAAA==.',
Si='Sideffects:BAAANQAECgUICAAAAA==.Sidewinder:BAAANQADCggICAAAAA==.Silvercircle:BAAANQAECgUICQAAAA==.Silverlord:BAAANQAECgYICQAAAA==.Sinafay:BAAANQAECgcIEAAAAA==.Siv:BAABNQAECoEaAAIKAAgJnx/0CADOAgAKAAgJnx/0CADOAgAAAA==.',
Sl='Slaedin:BAAANQADCgcICwAAAA==.',
Sm='Smokinbarbie:BAAANQADCgYIEgAAAA==.',
Sn='Snackkpack:BAAANQADCgcIDgAAAA==.Snapjutsu:BAABNQAECoEVAAMKAAgJxRQ+EQAgAgAKAAgJxRQ+EQAgAgAUAAEJEBXJHQAuAAAAAA==.Snorg:BAAANQAECgUICgAAAA==.Snêaky:BAAANQAECgUIBwAAAA==.',
So='Solarnova:BAAANQAECgMIBAAAAA==.Solorn:BAAANQAECgYICwAAAQ==.',
Sp='Spygon:BAAANQAECgIIAgAAAA==.',
St='Strobila:BAAANQAECgMIBAAAAA==.Studdmuffin:BAAANQAECgcIEgAAAA==.',
Su='Superkylexy:BAAANQADCgIIAgAAAA==.Suuz:BAAANQAECgQIBQAAAA==.',
Sy='Syafone:BAAANQAECgIIAgAAAA==.Symuelil:BAAANQADCggIDQAAAA==.Syphiroth:BAAANQAECgUICAAAAA==.Syrathos:BAACNQAFFIEMAAIMAAYJLRXYAAAwAgAMAAYJLRXYAAAwAgA1AAQKgSQAAgwACQmLIy0CAKkDAAwACQmLIy0CAKkDAAAA.Syrioforel:BAAANQADCgYIDQAAAA==.',
Ta='Taojîn:BAAANQAECgcIEwAAAA==.Tarted:BAAANQAECgQIBQAAAA==.',
Te='Teclis:BAABNQAECoEYAAIVAAkJ6x5KKgDoAgAVAAkJ6x5KKgDoAgAAAA==.Telzindrov:BAAANQAECgEIAgAAAA==.Terrorwithin:BAAANQAECgMIBgAAAA==.',
Th='Thalgar:BAAANQAECgIIAgAAAA==.Thalmick:BAAANQAECgcIEwAAAA==.Thanoslye:BAAANQADCgQIBAAAAA==.Theblackfish:BAAANQADCgUIBQAAAA==.Thogarn:BAAANQAECgMIAwAAAA==.Thunderkat:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Thundertem:BAAANQADCggIFAAAAA==.Théière:BAAANQAECgYICwAAAA==.',
Ti='Tigglebits:BAAANQABCgQIBgABNQADCgUICgABAAAAAA==.Tiraeda:BAAANQADCgMIAwAAAA==.Titoxs:BAAANQAECgQICAABNQAECgcIEAABAAAAAA==.',
To='Tofper:BAAANQADCgYIBgAAAA==.Toughlove:BAAANQADCgYIBgAAAA==.',
Tr='Trev:BAAANQAECgYICwAAAA==.Trustfäll:BAAANQADCggIGQAAAA==.',
Ts='Tsunãmi:BAAANQAFFAEIAQAAAA==.',
Tu='Tuc:BAAANQADCggIFAAAAA==.',
Ty='Tyndareos:BAAANQADCgUIBgAAAA==.Typhoontravv:BAABNQAECoEaAAMOAAgJXRxdBwCWAgAOAAgJChxdBwCWAgAWAAQJrhzHdgA2AQAAAA==.',
['Tø']='Tøkakagé:BAAANQAECgMIAwAAAA==.',
Uf='Ufearme:BAAANQADCggIEwAAAA==.',
Ug='Ugabooga:BAABNQAECoEdAAIVAAkJYhtOJgD5AgAVAAkJYhtOJgD5AgAAAA==.Uggon:BAAANQAECgEIAQAAAA==.',
Un='Unable:BAAANQAECgIIAgAAAA==.',
Ur='Urrikahn:BAAANQADCgQIBgAAAA==.',
Ut='Uthur:BAAANQAECgQIBwAAAA==.Utterchaos:BAAANQAECgcIEgAAAA==.',
Va='Vaelaven:BAAANQAECgYIEAAAAA==.Valack:BAAANQAECgMIAwAAAA==.Valfore:BAAANQAECgYIDwAAAA==.Valizor:BAAANQAECgMIBAAAAA==.Vanidosa:BAAANQADCgMIAwAAAA==.Varty:BAAANQAECgEIAQAAAA==.Vayle:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.',
Ve='Velaara:BAAANQADCgcICQAAAA==.Velaari:BAAANQADCgEIAQAAAA==.Verdant:BAAANQADCgcIBwAAAA==.Vestoris:BAAANQADCgUIBQAAAA==.Vetta:BAAANQAECgcIEAAAAA==.',
Vg='Vger:BAAANQADCggICwAAAA==.',
Vi='Vieora:BAAANQADCgYIBgAAAA==.Vikvikvik:BAAANQADCgYICwAAAA==.Vild:BAAANQADCgUIBQAAAA==.Vinick:BAAANQADCgYIBgAAAA==.',
Vo='Volgagrad:BAAANQADCgUIBQAAAA==.Vond:BAAANQABCgIIAgAAAA==.',
['Vè']='Vèrity:BAAANQADCgYIDAABNQADCgcIBwABAAAAAA==.',
Wa='Wardum:BAAANQAECgIIAgAAAA==.Watt:BAAANQADCggICAABNQAECggIGgAKAJ8fAA==.Wazul:BAAANQADCgYIEQAAAA==.',
Wh='Whisp:BAAANQADCggIDQAAAA==.Whitearrows:BAAANQAECgYIBgABNQAECggIDQABAAAAAA==.Whitespell:BAAANQAECggIDQAAAA==.',
Wi='Wickfel:BAAANQADCggIEgAAAA==.Wicus:BAAANQADCggICAAAAA==.',
Wy='Wyldfarmer:BAAANQADCggIGQAAAA==.',
Xa='Xanid:BAAANQAECgQIBAAAAA==.',
Xd='Xdwarf:BAAANQADCgUIDAABNQAECgUICwABAAAAAA==.',
Xe='Xeroxoxo:BAABNQAECoEXAAICAAgJjR0IEwC4AgACAAgJjR0IEwC4AgAAAA==.',
Ym='Ymedead:BAAANQAECgYIBgABNQAECgkJFwADAAQjAA==.',
Yo='Yoroichi:BAAANQAECgUICwAAAA==.Yourmomsride:BAAANQAECgcIDwAAAA==.Youtube:BAAANQAECggIDgAAAA==.',
Yu='Yueyue:BAAANQAECgMIBAAAAA==.Yungtwizzler:BAAANQADCggICQABNQADCggIHgABAAAAAA==.',
['Yá']='Yáng:BAAANQAECgQIBwAAAA==.',
Za='Zarylathanea:BAAANQAECgUIDAAAAA==.',
Ze='Zenheals:BAAANQADCggIBgAAAA==.Zeroskills:BAAANQADCgcIBwAAAA==.',
Zi='Zindi:BAAANQADCggIEQAAAA==.',
Zo='Zoni:BAAANQADCgcIBwAAAA==.Zoobee:BAAANQAECgEIAQAAAA==.Zoog:BAAANQAECgcIEgAAAA==.',
Zy='Zyrana:BAAANQADCgMIBQAAAA==.Zyridal:BAAANQAECgQICwAAAA==.Zyvara:BAAANQAECgEIAgAAAA==.',
['Zä']='Zärèlíä:BAABNQAECoElAAIKAAkJ6x1HBgAQAwAKAAkJ6x1HBgAQAwABNQAECgYIBgABAAAAAA==.',
['Äp']='Äpples:BAAANQADCgEIAQAAAA==.',
['Æz']='Æz:BAAANQAECgUICQAAAA==.',
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
