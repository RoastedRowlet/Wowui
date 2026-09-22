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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Havoc','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Mage-Arcane','Druid-Restoration','Druid-Balance','Warlock-Destruction','Monk-Mistweaver','Shaman-Restoration','Paladin-Retribution','Evoker-Preservation','Monk-Windwalker','Warrior-Arms','Warrior-Fury','DemonHunter-Devourer','Druid-Feral','Paladin-Protection','Hunter-Survival','Rogue-Assassination','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','DemonHunter-Vengeance','Monk-Brewmaster','DeathKnight-Frost','Paladin-Holy','Rogue-Subtlety','Shaman-Enhancement',}
local provider = {region='US',realm='Khadgar',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abonde:BAAANQADCggJCwAAAA==.Abraxes:BAAANQAECgMIBgAAAA==.',
Ac='Acidemon:BAAANQAECgUJBQAAAA==.',
Ad='Adalaide:BAAANQAECgYJCwAAAA==.Adannis:BAAANQAECgIIAgABNQAECgUJBwABAAAAAA==.Adelane:BAAANQAECgEIAQABNQAECgUIEAABAAAAAA==.Adolyn:BAAANQADCggIEQAAAA==.',
Ae='Aeluna:BAAANQAECgQJCQAAAA==.Aethas:BAAANQADCgYICAAAAA==.',
Af='Affective:BAABNQAECoEWAAICAAgKtBUnGwAfAgACAAgKtBUnGwAfAgABNQAECgkJIwADAE0hAA==.Afkk:BAAANQADCggIBAAAAA==.',
Ah='Ahuramazda:BAAANQAECgYIBwAAAA==.',
Ai='Aidard:BAAANQABCggIDwAAAA==.Airdd:BAAANQADCgEIAQAAAA==.Aizlyn:BAAANQADCgcIFgAAAA==.',
Ak='Akio:BAAANQAECgYIEQAAAA==.',
Al='Aldarya:BAAANQAECgMIBAAAAA==.Alisara:BAABNQAECoEdAAIEAAgK1SR5DABCAwAEAAgK1SR5DABCAwAAAA==.Alish:BAAANQADCggIFwAAAA==.Allexx:BAAANQAECgYJDQAAAA==.Allyssel:BAACNQAFFIELAAIFAAUK2RYsAwCxAQAFAAUK2RYsAwCxAQA1AAQKgScAAgUACQqwJloAAAEEAAUACQqwJloAAAEEAAAA.Alrictus:BAAANQADCggIDwAAAA==.',
Am='Amasu:BAABNQAECoEXAAMGAAkKeBpaDQDLAgAGAAkKeBpaDQDLAgAHAAMKGQ4vEQCqAAAAAA==.Amazinggrace:BAAANQAECgUJDwAAAA==.Amentiu:BAAANQADCgMIAwABNQAECgUICgABAAAAAA==.Ammathendis:BAAANQADCgQIBAABNQAECgQJBwABAAAAAA==.Ammiel:BAAANQADCgEIAQABNQAECgkJHQAIAEUbAA==.Ampera:BAAANQADCgYIBgAAAA==.',
An='Anastriana:BAAANQAECgEJAQAAAA==.Angeal:BAAANQAECgQJCAAAAA==.Angrychef:BAAANQADCgYIDAAAAA==.Animus:BAAANQAECgUIEAAAAA==.Annamei:BAAANQAECgUICAAAAA==.',
Ao='Aoife:BAAANQAECgUJDAAAAA==.Aorina:BAABNQAECoEaAAIJAAcKqxKgmQDYAQAJAAcKqxKgmQDYAQAAAA==.',
Ar='Arazalor:BAAANQAECgYJEAAAAA==.Arcangel:BAABNQAECoEbAAMKAAkKjyO3AgB4AwAKAAkKjyO3AgB4AwALAAEK+RljegBIAAAAAA==.Arrash:BAAANQADCgYICwABNQAECgQJBQABAAAAAA==.Arthritic:BAAANQADCgcIEgAAAA==.Arthurdent:BAAANQAECgUIDwAAAA==.Arysa:BAAANQADCgUIBQAAAA==.',
As='Ashara:BAAANQAECgYIDgAAAA==.Ashenrain:BAAANQADCggJEAAAAA==.Ashvia:BAAANQADCggIDwAAAA==.Aspiration:BAAANQABCgMIBQAAAA==.',
At='Atheren:BAAANQAECgYJCwAAAA==.Athshu:BAAANQADCgcIBwAAAA==.Atulan:BAAANQAECgUIDgAAAA==.',
Au='Auntiemimi:BAAANQAECgMIBAAAAA==.',
Av='Avalina:BAAANQAECgYIEQABNQAFFAQIBgAMABEdAA==.Avannar:BAAANQADCgUIEgAAAA==.Avelyn:BAAANQADCgEIAQAAAA==.Aveìl:BAAANQADCgUIBQAAAA==.Aviae:BAAANQAECgEJAQAAAA==.',
Ay='Ayani:BAAANQAECgYJEAAAAA==.',
Az='Azrine:BAAANQADCggIFAAAAA==.',
Ba='Babymanowood:BAAANQADCgcJBwAAAA==.Baddattitude:BAAANQADCgUIBwABNQADCggIGgABAAAAAA==.Baddkharma:BAAANQADCgQIDwAAAA==.Badras:BAAANQAECgYIDAAAAA==.Bagelz:BAABNQAECoEXAAINAAkKYx+RBQACAwANAAkKYx+RBQACAwAAAA==.Bathomula:BAAANQAECgQJCAAAAA==.Bayla:BAAANQADCgUIBQABNQAFFAUJDQANAHsUAA==.Bazzwar:BAAANQADCggICwABNQAECgQJCQABAAAAAA==.',
Be='Beric:BAAANQAECggJDAAAAA==.Betadine:BAAANQAECgQIBAAAAA==.Bexy:BAAANQAECgYIEAABNQAECgcJEgABAAAAAA==.',
Bl='Blade:BAAANQAECgYIEAAAAA==.',
Bo='Boldan:BAAANQADCgIIAgAAAA==.Boohaha:BAABNQAECoEUAAIOAAgKuRZANwAWAgAOAAgKuRZANwAWAgAAAA==.Booze:BAAANQAECgMIAwAAAA==.Bormagh:BAAANQADCgUIBQAAAA==.Borris:BAABNQAECoEYAAIPAAcKFSLYMgCLAgAPAAcKFSLYMgCLAgAAAA==.',
Br='Brightwing:BAABNQAECoEgAAIQAAkKFh2IBgASAwAQAAkKFh2IBgASAwAAAA==.Brigorath:BAAANQADCggJIQAAAA==.Brokenarro:BAAANQADCgcJGQAAAA==.',
Bu='Bubblebae:BAAANQAECgQICAABNQAECgUIBgABAAAAAA==.Bullshivek:BAAANQAECgUJBgAAAA==.',
Ca='Caale:BAAANQAECgQJBgAAAA==.Caecus:BAAANQAECgUJBgAAAA==.Callsaul:BAEANQAECgEJAQAAAA==.Casmus:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Caylissa:BAAANQAECgMIAwAAAA==.',
Ce='Celryth:BAAANQADCgIIAgAAAA==.Cenvoked:BAAANQAECgYJDQAAAA==.Cepha:BAAANQADCgQIBAAAAA==.',
Ch='Charbethicc:BAAANQAECgUJDgAAAA==.Charlicious:BAAANQAECgEIAQABNQAECgUJDgABAAAAAA==.Charlondrus:BAAANQADCgQIBgABNQAECgUJDgABAAAAAA==.Charticulous:BAAANQADCgUIBQABNQAECgUJDgABAAAAAA==.Chijoku:BAAANQAECgcIEwAAAA==.Chimster:BAAANQAECgYJDwAAAA==.Chuckstrike:BAAANQADCgUIBQAAAA==.Chyna:BAAANQADCggJCAAAAA==.',
Co='Corvò:BAAANQAECgUJCAAAAA==.',
Cr='Craeus:BAAANQAECgUICgAAAA==.Cralk:BAAANQAECgYJDAABNQAECggJDAABAAAAAA==.Cranked:BAAANQAECgQIBAABNQAECgkJIAARAKQgAA==.',
Cy='Cyonarah:BAAANQADCggJGQAAAA==.',
Da='Darem:BAAANQAECgQJBAAAAA==.',
De='Decnahne:BAAANQADCgUIBQAAAA==.Deepwood:BAAANQAECgUIDAAAAA==.Deidra:BAAANQADCgcJGAAAAA==.Devilette:BAAANQADCgEIAQAAAA==.Devry:BAAANQABCgMIAwAAAA==.',
Di='Dietdrpeeper:BAABNQAECoEbAAIEAAgKoSOBDQA5AwAEAAgKoSOBDQA5AwAAAA==.Diggi:BAAANQAECgQICQAAAA==.Diosa:BAAANQAECgYJEQAAAA==.Divinekat:BAAANQADCggIFQAAAA==.Dizza:BAAANQAECgEJAQAAAA==.',
Dk='Dkagon:BAAANQAECgYJDAAAAA==.',
Do='Docholiday:BAAANQADCggIGAAAAA==.Dontticklmeh:BAAANQADCgMIAgAAAA==.Doode:BAAANQAECgUICQAAAA==.Dooderonomy:BAAANQAECgUJBgAAAA==.Doria:BAAANQADCgQIBAAAAA==.',
Dr='Dragaan:BAAANQAECgQJCwAAAA==.Dragonbait:BAABNQAECoEnAAIPAAgKCRwOMgCOAgAPAAgKCRwOMgCOAgAAAA==.Dragonoodles:BAAANQAECgUICwAAAA==.Dragonzbane:BAAANQAECgQJCAAAAA==.Dranosh:BAAANQADCgUIBQABNQADCggIHgABAAAAAA==.Dreamawake:BAAANQADCggICgAAAA==.Drek:BAAANQAECgIIAwAAAA==.Drekthanas:BAAANQADCgcJBwABNQAECgIIAwABAAAAAA==.Drenea:BAAANQADCgYJGAAAAA==.Drimlek:BAAANQADCgEIAQAAAA==.Drin:BAAANQAECgQJBgAAAA==.',
Du='Duplicitous:BAAANQADCgcJBwAAAA==.',
Dy='Dyriana:BAAANQADCgYJFQAAAA==.',
['Dä']='Däustin:BAAANQADCgYIBgAAAA==.',
Ec='Ecto:BAAANQAECgYJEAAAAA==.',
El='Eleshn:BAAANQADCggICQAAAA==.Ellasian:BAAANQAECgQJCQAAAA==.Ellewoods:BAAANQADCggIDwABNQAECgMIAwABAAAAAA==.Eloise:BAAANQADCgUIBQAAAA==.Eltria:BAABNQAECoEXAAIJAAkKFyKZKAAZAwAJAAkKFyKZKAAZAwAAAA==.',
Em='Empathy:BAAANQAECgEIAQAAAA==.',
En='Ennuii:BAAANQADCggIEQAAAA==.',
Ep='Ephel:BAAANQAECgYIDQAAAA==.',
Er='Eric:BAAANQAECgIIAgABNQAECgcIFwASAL8aAA==.',
Es='Essential:BAABNQAECoEXAAITAAkKPSDcAQAPAwATAAkKPSDcAQAPAwAAAA==.',
Ex='Exces:BAAANQADCgUIBQAAAA==.',
Ez='Ezalth:BAAANQADCgcIEwAAAA==.Ezz:BAAANQADCggJDwAAAA==.',
Fa='Fachzile:BAAANQADCgQIAQAAAA==.Faden:BAAANQAECgcJDAABNQAECgkJIAARAKQgAA==.Faenara:BAAANQAECgYJEAAAAA==.Falafelguy:BAABNQAECoEZAAIJAAgKsByDXwBwAgAJAAgKsByDXwBwAgAAAA==.Falron:BAAANQADCgEIAQAAAA==.Farhund:BAAANQADCgcIBwABNQADCggIDwABAAAAAA==.Faruqq:BAAANQAECgYJDQAAAA==.',
Fe='Feenux:BAAANQABCgQIBAAAAA==.Felafel:BAAANQADCgMIBAABNQAECggJGQAJALAcAA==.Felartamiel:BAAANQADCgYJGQAAAA==.Felkieler:BAAANQADCgYICAABNQAECgEJAQABAAAAAA==.Fey:BAAANQAECgUICgAAAA==.',
Fi='Fishron:BAAANQAECgUJBgAAAA==.',
Fl='Flaz:BAABNQAECoEYAAILAAkKExphHACQAgALAAkKExphHACQAgAAAA==.Fleury:BAAANQABCgUIBAAAAA==.',
Fo='Forestspirit:BAAANQAECgYJDQAAAA==.Fourneau:BAAANQADCggJCAABNQAECgYIEQABAAAAAA==.',
Fr='Frawda:BAAANQAECgcJEAAAAA==.',
Fu='Fusillidari:BAAANQAECgQJBAABNQAECgUICwABAAAAAA==.Fuzzy:BAAANQADCgEIAQAAAA==.',
Ga='Galaxyman:BAAANQADCggIEQAAAA==.Garlone:BAAANQABCgcIBwAAAA==.',
Ge='Geist:BAAANQAECgcIEgAAAA==.Geraith:BAAANQAFFAEIAQAAAA==.Gerios:BAAANQAECgYJEAAAAA==.Getafix:BAAANQADCgQIBAAAAA==.Getmadbro:BAAANQAECgMIAwAAAA==.',
Gg='Ggparts:BAAANQADCgUIBQAAAA==.',
Gh='Ghostflair:BAAANQADCgEIAQAAAA==.Ghostflare:BAAANQAECgQIBAAAAA==.',
Gl='Glacier:BAAANQABCgYJBgAAAA==.Glendra:BAAANQAECgYJDQAAAA==.Glorificus:BAAANQADCggJDgAAAA==.',
Gn='Gnomércy:BAAANQADCgMIAwAAAA==.',
Go='Goatboat:BAAANQADCgQIBwAAAA==.',
Gr='Grandeeny:BAAANQAECgYJDgAAAA==.Greensleeves:BAAANQADCgYJFwAAAA==.Gregoriusz:BAABNQAECoEYAAICAAcKqxfQHwDmAQACAAcKqxfQHwDmAQAAAA==.Greygull:BAAANQAECgEJAQAAAA==.',
Gu='Guinness:BAAANQAECgUICwAAAA==.Guntank:BAAANQAECgYIEQAAAA==.',
Ha='Hategnomer:BAAANQADCgYJGAAAAA==.Havenfell:BAAANQAECgYJCwAAAA==.Hawkfist:BAAANQAECgYJDQAAAA==.',
He='Hercules:BAABNQAECoEiAAIDAAkKaBw5DgAQAwADAAkKaBw5DgAQAwAAAA==.Herzagon:BAAANQADCgEIAQAAAA==.',
Hi='Hierodoulos:BAAANQAECgYJEQAAAA==.',
Ho='Holykat:BAAANQADCggICwABNQADCggIFQABAAAAAA==.Hotcha:BAAANQADCgEIAQAAAA==.Hotsie:BAAANQADCgMIBQAAAA==.',
Hr='Hroth:BAAANQAECgYJDQAAAA==.Hrothgar:BAAANQADCgIIAgABNQAECgYJDQABAAAAAA==.',
Hu='Hunteroni:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.',
Ia='Ianos:BAAANQAECgQIBAAAAA==.',
Ic='Icenea:BAAANQAECgEIAQABNQAECggJHQAEANUkAA==.',
If='Ifearu:BAAANQADCgYIBgABNQADCgcJGQABAAAAAA==.',
Ig='Iggity:BAAANQABCgIIAwAAAA==.',
Ih='Ihri:BAAANQAECgUIBQAAAA==.',
Ik='Ikthus:BAAANQAECgUJBwAAAA==.',
Il='Illtud:BAAANQAECgQIBAAAAA==.Ilyessa:BAABNQAECoEcAAIRAAkKZiGbBQBEAwARAAkKZiGbBQBEAwAAAA==.',
Ir='Ironfur:BAAANQADCgQIBAABNQADCggIHgABAAAAAA==.Ironpipes:BAAANQAECgEJAwAAAA==.',
Is='Iskrå:BAAANQADCggJGwAAAA==.',
Ja='Jacynth:BAAANQAECgUJCgAAAA==.Jaimers:BAAANQAECgYJEAAAAA==.Jardinn:BAAANQAECgUIBgAAAA==.Jaxen:BAAANQAECgUIEAAAAA==.Jaxon:BAAANQADCggJHAAAAA==.Jaywilde:BAABNQAECoElAAMSAAkKcBUxPQByAgASAAkKcBUxPQByAgATAAEKVAUeIwAyAAAAAA==.',
Je='Jerkpaladin:BAAANQADCggIFgAAAA==.Jerusalaem:BAAANQADCgEIAQAAAA==.Jetsetradio:BAAANQAECgQJBAAAAA==.',
Ji='Jizakazam:BAAANQAECgYIDwAAAA==.',
Jo='Josepha:BAAANQADCgMIBAAAAA==.',
Ju='Juggyspally:BAAANQAECgUICwAAAA==.Justbringit:BAEANQADCgQIBAABNQAECgkJHQAUACkiAA==.Juvens:BAAANQABCgMIAQAAAA==.',
['Jï']='Jïao:BAAANQAFFAEIAQAAAA==.',
Ka='Kairiccars:BAAANQADCgYIBgAAAA==.Karotten:BAAANQAECgUICQAAAA==.Karthair:BAAANQAECgUJBQAAAA==.Kassoa:BAAANQAECgYJBgAAAA==.Kaszim:BAABNQAECoEfAAMEAAkKcSIYBgCIAwAEAAkKcSIYBgCIAwACAAEKzAe7YAAxAAAAAA==.',
Ke='Keello:BAAANQAECggJEQAAAA==.Kelkieran:BAAANQADCgUIBQAAAA==.Kenz:BAAANQAECgYJBwAAAA==.Kernelsandrs:BAABNQAECoEdAAMEAAkKBCOXEgAPAwAEAAkKBCOXEgAPAwACAAMKlQayRQCPAAAAAA==.',
Ki='Kileena:BAAANQADCgQJBAABNQAECgYJDQABAAAAAA==.Killgore:BAAANQADCgYIBgAAAA==.Kintsugi:BAAANQAECgYICgAAAA==.Kirinmaruu:BAAANQAECgQICAAAAA==.Kirisatsu:BAAANQAECgMIBAAAAA==.Kisatchie:BAAANQAECgQIBwAAAA==.',
Ko='Koalitsiya:BAAANQADCggIFgAAAA==.Koko:BAAANQADCgQIBAAAAA==.Kozãk:BAAANQADCgcJCwAAAA==.',
Kr='Kreatos:BAAANQAECgQJBwAAAA==.Krimez:BAAANQAECgYIEQAAAA==.Krynez:BAAANQADCgUIEAABNQAECgYIEQABAAAAAA==.',
Ky='Kyrhios:BAAANQAECgYIDAAAAA==.',
['Kà']='Kàkarot:BAAANQADCgEJAQAAAA==.',
['Kä']='Käggai:BAAANQAECgcIEAAAAA==.',
['Kò']='Kòld:BAABNQAECoEdAAIVAAgKNBiEBgBrAgAVAAgKNBiEBgBrAgAAAA==.Kòume:BAAANQADCgMIAgAAAA==.',
La='Lana:BAAANQADCgcIDgAAAA==.Lark:BAAANQAECgUIBQAAAA==.Larthas:BAAANQAECgYJEAAAAA==.Lary:BAAANQAECgMIAwABNQAECgkJIgAWAPIjAA==.Lascie:BAAANQAECgYJEAAAAA==.',
Le='Leafykat:BAAANQADCgUIBQABNQADCggIFQABAAAAAA==.Leaila:BAAANQAECgQIBgAAAA==.Leiha:BAAANQADCggIEAAAAA==.',
Li='Liams:BAAANQADCgcIDQAAAA==.Lidless:BAAANQAECgYJEAAAAA==.Linux:BAAANQAECgUJBgAAAA==.',
Ll='Llamadin:BAAANQAECgMIBAAAAA==.',
Lo='Logknight:BAAANQADCgUIBQAAAA==.Lohof:BAAANQABCgIIAgAAAA==.',
Lu='Lukis:BAAANQADCgYIBgAAAA==.Luminianna:BAAANQAECgUIEQAAAA==.',
Ly='Lynra:BAAANQAECgQIBQAAAA==.Lytol:BAAANQADCggJGwAAAA==.',
Ma='Macloc:BAAANQAECgQJBwAAAA==.Maggiemae:BAAANQADCgUJDQAAAA==.Mahli:BAAANQAECgYJEAAAAA==.Marrias:BAABNQAECoEXAAIDAAYK3hGfRAB9AQADAAYK3hGfRAB9AQAAAA==.Massacre:BAAANQAECgQIBAABNQAECgQJBwABAAAAAA==.Mawrix:BAAANQAECgYIDgAAAA==.Maxtheyare:BAAANQAECgEIAQAAAA==.',
Me='Mechchimy:BAAANQAECgEJAgABNQAECgYJDwABAAAAAA==.Medîcus:BAAANQADCgIIAgAAAA==.Megumín:BAAANQADCgQIBgAAAA==.Meith:BAAANQADCgUIBgAAAA==.Melwazul:BAAANQADCgMJAwAAAA==.Melz:BAAANQAECgEIAQAAAA==.Merazi:BAAANQADCgMIAwAAAA==.Mesuryte:BAABNQAECoEiAAMXAAkK1yRjAACtAwAXAAkK1yRjAACtAwACAAEKEA0oWwA5AAAAAA==.Meyla:BAAANQADCgcJBgAAAA==.',
Mi='Mibby:BAAANQAECgIJAgABNQAECgIIAgABAAAAAA==.Mibs:BAAANQAECgYJDQAAAA==.Mickal:BAAANQAECgUIDwAAAA==.Mikaelangelo:BAAANQAECgEJAQAAAA==.Mindrash:BAAANQAECgUIBQABNQAECgkJFwAJAN8eAA==.Mip:BAAANQAECgIIAgAAAA==.Mirie:BAAANQADCgUIBQAAAA==.',
Mn='Mnrogar:BAAANQADCgQIBQAAAA==.',
Mo='Mohegon:BAAANQADCgQIBQAAAA==.Mohini:BAAANQAECgYJDQAAAA==.Mojhohammers:BAAANQADCgUIBQAAAA==.Mooquisha:BAAANQADCgYICgAAAA==.Mooter:BAABNQAECoEcAAIYAAgKURVkFgBCAgAYAAgKURVkFgBCAgAAAA==.Morchak:BAAANQADCgYIBgAAAA==.Mornix:BAAANQADCgUIBQABNQAECgQJBQABAAAAAA==.',
Mu='Mushroom:BAAANQAECgUIBQAAAA==.',
My='Mystweaver:BAAANQADCgYIBgAAAA==.',
Na='Naota:BAAANQAECgYIEAAAAA==.Naqilol:BAAANQADCgUICQAAAA==.Narfox:BAAANQAECgUIBQAAAA==.Nazzern:BAAANQAECgIIAgAAAA==.',
Ne='Neameto:BAAANQAECgcIEwAAAA==.Necrophyle:BAAANQAECgQIBgAAAA==.Nefarox:BAAANQAECgMIBAAAAA==.Neilion:BAAANQADCgMIAwAAAA==.Nerfslappy:BAAANQADCggJFwAAAA==.Nethron:BAAANQADCgUIBQAAAA==.',
Ni='Nightman:BAAANQAECgcIEwAAAA==.Nightstealer:BAAANQADCggJIQAAAA==.Nikkikayama:BAABNQAECoEfAAIEAAkKhiDaEwAGAwAEAAkKhiDaEwAGAwAAAA==.Nikol:BAAANQAECgcJEgAAAA==.',
No='Norikoff:BAACNQAFFIEGAAMTAAQKohK3AADvAAATAAMKdxG3AADvAAASAAIKhQ4zGwCIAAA1AAQKgRgAAxMACQroHcUBABgDABMACQroHcUBABgDABIACArVEXFwALoBAAAA.',
Ny='Nyalla:BAAANQADCgYJGAAAAA==.',
['Nï']='Nïdalee:BAAANQAECgMIBwAAAA==.',
Oc='Octoberfae:BAAANQADCgMIAwAAAA==.Octwitch:BAAANQADCggJHAAAAA==.',
Of='Offdensen:BAAANQADCgcIGAAAAA==.',
Ok='Okkotsu:BAAANQAECgIIAwAAAA==.Okku:BAAANQAECgIIAwAAAA==.',
Ol='Oldmims:BAAANQAECgYIEQAAAA==.Oldmimse:BAAANQADCggJCAABNQAECgYIEQABAAAAAA==.',
On='Onlybatfans:BAAANQAECgUJBQAAAA==.',
Op='Ophina:BAAANQAECgEIAQAAAA==.',
Or='Oramu:BAAANQAECgcIDgAAAA==.Orangejello:BAAANQAECgQIBwAAAA==.Orion:BAAANQADCgMIAwABNQAECgkJHAARAGYhAA==.Oriòn:BAAANQAECgIIAwAAAA==.Orpseroth:BAAANQADCgUJBQABNQAECgUJBwABAAAAAA==.',
Ot='Otane:BAAANQAECgYJCgAAAA==.',
Pa='Paiah:BAAANQADCgUIBgAAAA==.Pallykillers:BAAANQADCgUICgAAAA==.Palyephel:BAAANQADCggICAABNQAECgYIDQABAAAAAA==.Pana:BAAANQAECgUIEQAAAA==.Pandhikukka:BAAANQADCgUIBQAAAA==.Pandy:BAAANQAECgQJCAAAAA==.Pannifer:BAAANQAECgQJBwAAAA==.Paolon:BAAANQADCggIFAAAAA==.Papasmurph:BAAANQABCgIIAgAAAA==.Parple:BAAANQAECgQICAABNQAFFAQICAAGAJwXAA==.',
Pe='Penelopei:BAAANQAECgYJCAAAAA==.',
Ph='Phantõm:BAAANQADCggJEQAAAA==.Philkulson:BAAANQADCggJCAABNQAECgkJIwADAE0hAA==.',
Pi='Picker:BAAANQADCgYIBgAAAA==.',
Po='Poledra:BAAANQADCgYJFgAAAA==.Porterah:BAAANQAECgYIBgAAAA==.Potbellypali:BAAANQABCgQIBgAAAA==.Poutyne:BAABNQAECoEbAAILAAgKvh6/FQDQAgALAAgKvh6/FQDQAgAAAA==.',
Pr='Priestress:BAAANQADCggICAAAAA==.Profanus:BAAANQADCgUIBQABNQAECgkJIAARAKQgAA==.',
Pu='Punchnugget:BAAANQAECgQICAAAAA==.Punkvc:BAAANQAECgYIDQAAAA==.',
Py='Pyren:BAAANQADCgcJEgAAAA==.',
['Pá']='Párts:BAAANQADCgMIBAABNQADCgUIBQABAAAAAA==.',
Qu='Quaeras:BAAANQAECgYIDgAAAA==.',
Ra='Rabiess:BAAANQAECgEIAQAAAA==.Ragingnoodle:BAAANQADCgQIBAABNQAECgUICwABAAAAAA==.Ragingshnoz:BAAANQAECgUJDwAAAA==.Ragé:BAEBNQAECoEdAAMUAAkKKSITCAA0AwAUAAgKtSMTCAA0AwAFAAIKzRo6TgCfAAAAAA==.Rakklock:BAAANQAECgIIAgAAAA==.Ralphe:BAAANQAECgUJCQAAAA==.Rashygroin:BAAANQABCgYJBgABNQAECgYJEAABAAAAAA==.Raytow:BAAANQAECgYJDQAAAA==.Razelle:BAAANQAECgMIBAAAAA==.',
Re='Reconpalymix:BAAANQAECgEJAQAAAA==.Relana:BAAANQADCggICgAAAA==.Remus:BAAANQAECggJAgAAAA==.Reshad:BAAANQADCggIEwAAAA==.Ressix:BAAANQAECgYJEAAAAA==.',
Rh='Rhaeyn:BAAANQADCgMIBQABNQADCggIGAABAAAAAA==.',
Ri='Ripture:BAAANQADCgYIBgABNQAECgYJEAABAAAAAA==.Rizzwar:BAAANQAECgQIBQAAAA==.',
Ro='Roastbeefin:BAAANQADCgIIAgAAAA==.Rockhunter:BAAANQADCggJEAAAAA==.Ronborules:BAAANQAECgEIAQAAAA==.Rosenta:BAAANQAECgQJBwAAAA==.',
Ru='Rumlock:BAAANQAECgQJBQAAAA==.',
['Rö']='Röwnin:BAAANQADCgYIEgAAAA==.',
Sa='Sabinah:BAAANQAECgMIBAAAAA==.Sabing:BAAANQADCgYJGAAAAA==.Sacramento:BAAANQADCgMJAwAAAA==.Saeberis:BAAANQADCgUJCQAAAA==.Saiah:BAAANQAECgQJBAAAAA==.Saintbazz:BAAANQAECgQJCQAAAA==.Sal:BAACNQAFFIEIAAIGAAQKnBdRBABrAQAGAAQKnBdRBABrAQA1AAQKgSMAAgYACQoMI6IDAIsDAAYACQoMI6IDAIsDAAAA.Salivan:BAAANQAECgMIBAAAAA==.Sargaris:BAAANQAECgUJBwAAAA==.Sariva:BAACNQAFFIEGAAQMAAQKER3VBAC+AAAMAAIKSB7VBAC+AAAZAAEKiCItAwBlAAAaAAEKKxVXIQBUAAA1AAQKgSMABBoACQqHIAozAFICABoABwp1IQozAFICAAwABQrtFpgeAFgBABkABAr/Gi0KAE0BAAAA.Sathalis:BAAANQADCggIEwAAAA==.Saurva:BAAANQAECgcIEgAAAA==.Sawfang:BAAANQADCgIIAgABNQAECgYIDAABAAAAAA==.Saxophone:BAAANQAECgYIDgAAAA==.Sayna:BAAANQAECgUIEAAAAA==.',
Sc='Scarecro:BAAANQAECgYJEAAAAA==.',
Se='Sedae:BAAANQAECgYIEAAAAA==.Seekvaira:BAABNQAECoEWAAIbAAgKwRw9KgBsAgAbAAgKwRw9KgBsAgAAAA==.Seelenlos:BAAANQADCgcJBwAAAA==.Seiya:BAAANQAECgQICAAAAA==.Selira:BAAANQAECgUJBgAAAA==.Selwynn:BAAANQADCggJCAAAAA==.Senji:BAAANQAECgMJAwAAAA==.Senseitots:BAAANQADCggICAAAAA==.Sevalina:BAAANQAECgYJDQAAAA==.',
Sh='Shadowstep:BAAANQADCggIFAAAAA==.Shalaah:BAAANQAECgUICQAAAA==.Shamhuntzu:BAEBNQAECoEXAAMUAAkKgRRqFgBkAgAUAAkKgRRqFgBkAgAcAAMKyAU6FwCDAAAAAA==.Shampaign:BAAANQAECgYJEAAAAA==.Shaoevoker:BAAANQAECgQJBAAAAA==.Sharnara:BAAANQAECgQIBAAAAA==.Shatterskull:BAAANQADCggIHgAAAA==.Shazira:BAAANQADCggIHAAAAA==.Shep:BAAANQAECgEJAQAAAA==.Sherloch:BAAANQADCgEIAQAAAA==.Shiftyrum:BAAANQAECgMIAwABNQAECgUJDAABAAAAAA==.Shmollboi:BAAANQABCgIIAgAAAA==.',
Si='Sideffects:BAAANQAECgYJDgAAAA==.Sidewinder:BAAANQADCggICAAAAA==.Silvercircle:BAAANQAECgYIDgAAAA==.Silverlord:BAAANQAECgYIDQAAAA==.Sinafay:BAAANQAECggIEwAAAA==.Siv:BAABNQAECoEgAAIRAAkKpCDYBQA/AwARAAkKpCDYBQA/AwAAAA==.',
Sl='Slaedin:BAAANQADCgcICwAAAA==.',
Sm='Smokinbarbie:BAAANQADCggJGgAAAA==.',
Sn='Snackkpack:BAAANQADCggJEgAAAA==.Snapjutsu:BAABNQAECoEZAAMRAAgKBRWlFwAEAgARAAgKBRWlFwAEAgAdAAEKEBWTIwAuAAAAAA==.Snorg:BAAANQAECgYJEAAAAA==.Snêaky:BAAANQAECgYJDQAAAA==.',
So='Solarnova:BAAANQAECgQJCAAAAA==.Solorn:BAAANQAECgYIEQAAAQ==.',
Sp='Splash:BAAANQAECgEIAQAAAA==.Spygon:BAAANQAECgUJBwAAAA==.',
St='Strobila:BAAANQAECgYJCgAAAA==.Studdmuffin:BAABNQAECoEWAAMDAAkKPyDnHgBtAgADAAgK/BvnHgBtAgAeAAUKth8RKwCbAQAAAA==.',
Su='Superkylexy:BAAANQADCgIIAgAAAA==.Suuz:BAAANQAECgYJCwAAAA==.',
Sy='Syafone:BAAANQAECgIIAgAAAA==.Symuelil:BAAANQADCggIDQAAAA==.Syphiroth:BAAANQAECgYIDgAAAA==.Syrathos:BAACNQAFFIETAAIUAAcK3xdrAACwAgAUAAcK3xdrAACwAgA1AAQKgScAAhQACQrrI8UCAKIDABQACQrrI8UCAKIDAAAA.Syrioforel:BAAANQAECgEIAQAAAA==.',
Ta='Taojîn:BAABNQAECoEVAAIfAAkKpQs/OwAKAgAfAAkKpQs/OwAKAgAAAA==.Tarted:BAAANQAECgQIBQAAAA==.',
Te='Teclis:BAABNQAECoEaAAIJAAkKFCEZMQD7AgAJAAkKFCEZMQD7AgAAAA==.Telzindrov:BAAANQAECgYJCAAAAA==.Terrorwithin:BAAANQAECgUICwAAAA==.',
Th='Thalgar:BAAANQAECgIIAgAAAA==.Thalmick:BAABNQAECoEgAAIgAAgKVxgtDQBzAgAgAAgKVxgtDQBzAgAAAA==.Thanoslye:BAAANQADCgcJCgAAAA==.Theblackfish:BAAANQADCgUIBQAAAA==.Thogarn:BAAANQAECgQIBgAAAA==.Thunderkat:BAAANQADCgcJDAABNQADCggIFQABAAAAAA==.Thundertem:BAAANQADCggJHAAAAA==.Théière:BAAANQAECgYIEQAAAA==.',
Ti='Tigglebits:BAAANQABCgQIBgABNQADCgUJDQABAAAAAA==.Tiraeda:BAAANQADCgMIAwAAAA==.Titoxs:BAAANQAECgUJDQABNQAECgcIEAABAAAAAA==.',
To='Tofper:BAAANQADCgYIBgAAAA==.Toughlove:BAAANQADCgcJDAAAAA==.',
Tr='Trev:BAAANQAECgcJEgAAAA==.Trustfäll:BAAANQADCggJIQAAAA==.',
Ts='Tsunãmi:BAABNQAECoEfAAMOAAkKshbqIwB8AgAOAAkKshbqIwB8AgAhAAgKlQ8LDQArAgAAAA==.',
Tu='Tuc:BAAANQAECgUIBQAAAA==.',
Ty='Tyndareos:BAAANQADCgUIBgAAAA==.Typhoontravv:BAABNQAECoEdAAMWAAkKSRyGBwDUAgAWAAkK/xuGBwDUAgAPAAQKrhwFogAnAQAAAA==.',
['Tø']='Tøkakagé:BAAANQAECgUJCAAAAA==.',
Uf='Ufearme:BAAANQADCggIGgAAAA==.',
Ug='Ugabooga:BAABNQAECoElAAIJAAkKHR6oJAAmAwAJAAkKHR6oJAAmAwAAAA==.Uggon:BAAANQAECgMIBAAAAA==.',
Un='Unable:BAAANQAECgMJBQAAAA==.',
Ur='Urrikahn:BAAANQADCgcIDgAAAA==.',
Ut='Uthur:BAAANQAECgUJCAAAAA==.Utterchaos:BAABNQAECoEXAAMaAAkKsxPcWQC9AQAaAAgKeRHcWQC9AQAMAAQK/Aq+NQDHAAAAAA==.',
Va='Vaelaven:BAAANQAECgcIEgAAAA==.Valack:BAAANQAECgMIAwAAAA==.Valfore:BAABNQAECoEaAAIIAAgKQSGoDwDvAgAIAAgKQSGoDwDvAgAAAA==.Valizor:BAAANQAECgMJBwAAAA==.Vanidosa:BAAANQADCgMIAwAAAA==.Varty:BAAANQAECgQJBQAAAA==.Vayle:BAAANQADCggJDgABNQAECgYIEQABAAAAAA==.',
Ve='Velaara:BAAANQADCggICgAAAA==.Velaari:BAAANQADCgEIAQAAAA==.Verdant:BAAANQADCgcIBwAAAA==.Vestoris:BAAANQADCgYICwAAAA==.Vetta:BAAANQAFFAEIAQAAAA==.',
Vg='Vger:BAAANQADCggJEwAAAA==.',
Vi='Vieora:BAAANQADCgYIBgAAAA==.Vikvikvik:BAAANQADCgYICwAAAA==.Vild:BAAANQADCgUIBQAAAA==.Vinick:BAAANQADCgcIBwAAAA==.',
Vo='Volgagrad:BAAANQADCgYICQAAAA==.Vond:BAAANQABCgIJAgAAAA==.',
['Vè']='Vèrity:BAAANQADCgYIDAABNQADCggIDwABAAAAAA==.',
Wa='Wardum:BAAANQAECgIIAgAAAA==.Watt:BAAANQADCggICAABNQAECgkJIAARAKQgAA==.Wazul:BAAANQADCgYJFwAAAA==.',
Wh='Whisp:BAAANQADCggJFQAAAA==.Whitearrows:BAAANQAECgcJDwABNQAECggIEwABAAAAAA==.Whitespell:BAAANQAECggIEwAAAA==.',
Wi='Wickfel:BAAANQADCggIEgAAAA==.Wicus:BAAANQADCggICAAAAA==.',
Wy='Wyldfarmer:BAAANQADCggJIQAAAA==.',
Xa='Xanid:BAAANQAECgQJBQAAAA==.',
Xd='Xdwarf:BAAANQADCgUIDAABNQAECgYIEQABAAAAAA==.',
Xe='Xeroxoxo:BAABNQAECoEbAAIDAAkKuB5wEAD3AgADAAkKuB5wEAD3AgAAAA==.',
Xi='Xieren:BAAANQAECgMJAwABNQAECgQJBwABAAAAAA==.',
Xo='Xoz:BAAANQADCgcJCQAAAA==.',
Ya='Yasman:BAAANQADCggICAAAAA==.',
Ym='Ymedead:BAAANQAECggICwABNQAECgkJHQAEAAQjAA==.',
Yo='Yoroichi:BAAANQAECgYIEQAAAA==.Yourmomsride:BAAANQAECgcIEAAAAA==.Youtube:BAABNQAECoEYAAIfAAkKOAJxogC8AAAfAAkKOAJxogC8AAAAAA==.',
Yu='Yueyue:BAAANQAECgUICQAAAA==.Yungtwizzler:BAAANQADCggICQABNQADCggIHgABAAAAAA==.',
['Yá']='Yáng:BAAANQAECgQICwAAAA==.',
Za='Zarylathanea:BAAANQAECgUIEQAAAA==.',
Ze='Zenheals:BAAANQADCggIBgAAAA==.Zeroskills:BAAANQAECgYJBgAAAA==.',
Zi='Zindi:BAAANQADCggJEQAAAA==.',
Zo='Zoni:BAAANQADCgcIBwAAAA==.Zoobee:BAAANQAECgQJCQAAAA==.Zoog:BAABNQAECoEYAAIfAAkKFRuTFwDRAgAfAAkKFRuTFwDRAgAAAA==.',
Zy='Zyrana:BAAANQADCgMIBQAAAA==.Zyridal:BAAANQAECgUJEAAAAA==.Zyvara:BAAANQAECgQJBgAAAA==.',
['Zä']='Zärèlíä:BAABNQAECoEzAAIRAAkKmiLoAgCQAwARAAkKmiLoAgCQAwABNQAECggIDgABAAAAAA==.',
['Äp']='Äpples:BAAANQAECgEJAgAAAA==.',
['Æz']='Æz:BAAANQAECgYIDwAAAA==.',
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
