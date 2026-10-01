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

local lookup = {'Unknown-Unknown','Mage-Arcane','Warlock-Destruction','Warlock-Demonology','Mage-Frost','Hunter-BeastMastery','Warrior-Arms','Paladin-Retribution','DemonHunter-Havoc','Paladin-Holy','Shaman-Elemental','Druid-Guardian','Priest-Holy','Druid-Restoration','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Priest-Shadow','Paladin-Protection','Warlock-Affliction','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acelord:BAAANQAECgYIDAAAAA==.Actaeon:BAAANQAECgUIBwAAAA==.',
Ad='Adariom:BAAANQADCgYIBgAAAA==.Adilma:BAAANQADCgUIBwAAAA==.Adriannos:BAAANQAECgQIBQAAAA==.',
Ae='Aelthiriel:BAAANQADCggICAAAAA==.Aerosharpz:BAAANQADCgYIBgAAAA==.',
Ag='Aghatta:BAAANQADCgUIBQAAAA==.',
Ak='Akiji:BAAANQADCggIDwAAAA==.',
Al='Alamauri:BAAANQADCgYIBgAAAA==.Alceste:BAAANQADCgMIAwAAAA==.Ald:BAAANQADCgYIBgAAAA==.Alexextreme:BAAANQAECgIIAgAAAA==.Algea:BAAANQADCgMIAwABNQAECgUIBwABAAAAAA==.Algrixx:BAAANQAECgUIEAAAAA==.Aliaksandr:BAAANQADCgUIDAAAAA==.',
An='Andrëthö:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.Anellÿ:BAAANQADCgQIBAAAAA==.Angelloz:BAAANQAECgIIAgAAAA==.Anggos:BAAANQADCgMJAwAAAA==.Anjakiller:BAAANQADCggICAAAAA==.Anksunamoon:BAAANQAECggIBwAAAA==.Annedin:BAAANQAECgIJAgAAAA==.Annia:BAAANQADCgEIAQAAAA==.Anyid:BAAANQADCgIIAgAAAA==.Anystorm:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.',
Ap='Apökalÿpsïs:BAABNQAECoEdAAICAAcKEhhGmgAHAgACAAcKEhhGmgAHAgAAAA==.',
Aq='Aquadel:BAAANQAECgQIBAAAAA==.',
Ar='Arcandror:BAAANQADCgMIAwAAAA==.Aristostelis:BAAANQAECgMIAwAAAA==.',
As='Asaff:BAAANQADCgQJBgAAAA==.',
At='Atomicdk:BAAANQADCgIIAgAAAA==.Atonos:BAAANQABCggIDAAAAA==.',
Az='Azadium:BAAANQAECgEIAQAAAA==.Azul:BAAANQAECgYICgAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
['Aë']='Aëma:BAAANQAECgUICgAAAA==.',
Ba='Balragouldur:BAAANQADCgUIBgAAAA==.Barkbouncer:BAAANQADCggICAAAAA==.',
Be='Beatriz:BAAANQADCgYJCAAAAA==.Beelgarath:BAAANQADCgEIAQAAAA==.Belorian:BAAANQADCgUIBwAAAA==.Belowlight:BAAANQADCgcIEwAAAA==.Benoboi:BAAANQAECgUJBQAAAA==.Benícia:BAAANQABCgMIAwAAAA==.',
Bl='Blackfear:BAAANQAECgcICAABNQAECggIGgADAOIRAA==.Blackteriaa:BAAANQAECgIIBAAAAA==.Blankis:BAAANQABCggICQAAAA==.Blastoize:BAAANQAECgEIAQAAAA==.Bloodh:BAAANQAECgYIDgAAAA==.Bloodyz:BAAANQADCgYIBgAAAA==.Bluforged:BAEANQAECgYIEQAAAA==.',
Bo='Boamort:BAAANQAECgUICAAAAA==.Boruck:BAAANQABCgEIAQAAAA==.',
Br='Braeon:BAAANQADCgYIDwAAAA==.Bridda:BAAANQAECgEIAQAAAA==.Brinkst:BAAANQAECgEIAQAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
['Bö']='Bömbur:BAAANQADCgQIBAAAAA==.',
['Bø']='Bøamorte:BAAANQADCgEIAQAAAA==.',
Ca='Canaduh:BAAANQADCgUIBQAAAA==.Casuall:BAAANQADCggIEAAAAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAAANQAECgUICQAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Cl='Climps:BAAANQAECgQIDwAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.Corvean:BAAANQADCgUIBQAAAA==.',
Cr='Creuzapriest:BAAANQAECgIIAgAAAA==.Cruzade:BAAANQAECgcIEwABNQAECggIGgADAOIRAA==.Cröwllëy:BAAANQAECgUICwAAAA==.',
Cu='Cubatao:BAAANQAECgEJAQAAAA==.Curatio:BAAANQADCggIEQAAAA==.',
Da='Dahaka:BAAANQAECgMIBQAAAA==.Dahhak:BAAANQADCgQIBAAAAA==.Dakshayani:BAAANQAECgYIDgAAAA==.Dallion:BAAANQADCgUIDAAAAA==.Daportela:BAAANQADCgcICAAAAA==.Dardano:BAAANQABCggIDgAAAA==.Darkfuntz:BAABNQAECoEWAAICAAcKUw5+xgCnAQACAAcKUw5+xgCnAQAAAA==.Darkshaninha:BAAANQAECgQIBAAAAA==.Darkshurea:BAAANQAECgIIAgAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.Darksipa:BAAANQAECgIIAgAAAA==.',
De='Deadvi:BAAANQAECgcIEAAAAA==.Degenerative:BAABNQAECoEYAAIEAAkKKwCXIgEIAAAEAAkKKwCXIgEIAAAAAA==.Derothey:BAAANQAECgcIEgAAAA==.Devendeer:BAAANQABCgIIAgABNQAECgYIDgABAAAAAA==.',
Di='Dioniisio:BAAANQABCgQIBAAAAA==.',
Dk='Dkabeza:BAAANQADCgcIBwAAAA==.',
Dn='Dngkakuzo:BAAANQAECgYIEAAAAA==.',
Do='Doomsman:BAAANQADCgcICgAAAA==.',
Dr='Dracomamante:BAAANQAECgYJEgAAAA==.Draconoide:BAAANQAECgQIDgAAAA==.Dracón:BAAANQADCgYIDAAAAA==.Dragnnyr:BAAANQAECgMIBQAAAA==.Dragondrukc:BAAANQAECgUICwAAAA==.Dreykar:BAAANQAECgQICAAAAA==.Druidaezeki:BAAANQADCgUIBwAAAA==.',
Du='Duquetjb:BAAANQADCgYICAAAAA==.',
['Dä']='Dähäkä:BAAANQAECgYIDQAAAA==.',
Ed='Edasich:BAAANQADCggJCAAAAA==.Edven:BAAANQAECgQICQAAAA==.',
Ei='Eilin:BAAANQADCggICgAAAA==.',
El='Elbruxão:BAAANQAECgYIEQAAAA==.Eldarië:BAAANQABCgYICwAAAA==.Elementais:BAAANQAECgQICgAAAA==.Ellanor:BAABNQAECoEYAAMCAAYKsxEz2QCDAQACAAYKsxEz2QCDAQAFAAEKYwHVQgAYAAAAAA==.Ellocopere:BAAANQAECgYIDwAAAA==.Eltão:BAAANQADCgQIBQAAAA==.',
En='Envie:BAABNQAECoEbAAIGAAkKkSMBDwBFAwAGAAkKkSMBDwBFAwAAAA==.',
Er='Eratia:BAAANQADCgIIAgAAAA==.Eredith:BAAANQADCgQIBAAAAA==.Erhas:BAAANQAECgEIAQAAAA==.Erickya:BAAANQAECgYIDQAAAA==.Ervadocè:BAAANQADCgYIDAAAAA==.Ervelino:BAAANQAECgQIEwAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.Espectrudo:BAAANQADCgIIAgAAAA==.',
Ev='Evely:BAAANQAECgQIDAAAAA==.',
Fa='Falstro:BAAANQADCgYIBgAAAA==.',
Fe='Felenus:BAAANQAECgEIAQAAAA==.Felguk:BAAANQADCgIJAgAAAA==.Ferdruiid:BAAANQABCgUICgAAAA==.Fermoonie:BAAANQAECgIIAgAAAA==.',
Fi='Firexo:BAAANQADCgEIAQAAAA==.',
Fl='Flemma:BAAANQAECgYIDwAAAA==.Flexer:BAAANQAECgEIAQAAAA==.',
Fo='Fonderus:BAAANQADCgMIBAAAAA==.Foxyroxy:BAAANQAECgQIBAAAAA==.',
Fr='Friodokrl:BAAANQAECgcIEwAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAABNQAECoEtAAICAAgKPRnfewBOAgACAAgKPRnfewBOAgAAAA==.',
Ga='Gafgar:BAAANQAECgYIBgAAAA==.Gafowi:BAAANQAECgUIDQAAAA==.Galduin:BAABNQAECoEiAAIHAAcKCBGsgwC8AQAHAAcKCBGsgwC8AQAAAA==.Garrincha:BAAANQADCgYIBwABNQAECgQIBwABAAAAAA==.Gaunterodim:BAAANQAECgEIAwAAAA==.',
Ge='Gentioiroh:BAAANQAECgUIBwAAAA==.Gever:BAAANQADCgUIBQAAAA==.',
Gh='Ghopo:BAAANQAECgEIAgAAAA==.',
Gi='Giradus:BAAANQADCgUIBgAAAA==.',
Gl='Glorcckk:BAAANQADCgUIBgAAAA==.',
Gn='Gnomagga:BAAANQADCgMIAwABNQAECgcICgABAAAAAA==.',
Gr='Grimblade:BAAANQADCgEIAQAAAA==.Grindewald:BAAANQADCgcIBwAAAA==.Grommhell:BAAANQAECgYIEwAAAA==.Grím:BAAANQAECgQIBgAAAA==.',
Gu='Gudangara:BAAANQAECgEIAQAAAA==.Gugans:BAAANQAECgQIBAAAAA==.Guzinbrs:BAAANQADCgcIDAAAAA==.',
Ha='Haakaí:BAAANQAECgcIEQAAAA==.Haandir:BAAANQAECgQJBQAAAA==.Hadassä:BAAANQABCgEIAgAAAA==.Hafessä:BAAANQADCgMIAwAAAA==.Hakuro:BAAANQAECgIIAgAAAA==.Harany:BAAANQAECgIJAgAAAA==.Havatar:BAAANQADCgIIAgAAAA==.',
He='Herablack:BAAANQAECgEIAQAAAA==.',
Hi='Himikonee:BAAANQAECgQIDwAAAA==.',
Ho='Horstmeyer:BAAANQADCgIIAgAAAA==.',
Hu='Hulig:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
['Hø']='Høkulani:BAAANQAECgQIBwAAAA==.',
Ib='Ib:BAAANQADCggICQAAAA==.',
Ig='Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAABNQAECoEdAAIIAAgKIhd+WAA6AgAIAAgKIhd+WAA6AgAAAA==.Iksivokilirt:BAAANQADCgIJAgAAAA==.Ikslawok:BAAANQADCggIDwAAAA==.',
Il='Ileria:BAAANQADCggICgAAAA==.Illusionarc:BAAANQAECgYICwABNQAECgkKJAAJAFsdAA==.',
In='Incognita:BAAANQAECgYIEQAAAA==.Interst:BAAANQADCgcIBwAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQAECgEIAQAAAA==.',
Is='Iscalio:BAAANQAECgUIDgAAAA==.',
It='Itatchii:BAAANQAECgQIBQAAAA==.',
Iu='Iuuh:BAABNQAECoEdAAIKAAgKwBiAMABpAgAKAAgKwBiAMABpAgAAAA==.',
Iz='Izumrud:BAAANQABCgQIBQAAAA==.',
Ja='Jackdawnsong:BAAANQADCgQICAAAAA==.Jahuun:BAABNQAECoEZAAIIAAgK2AyPgwC7AQAIAAgK2AyPgwC7AQAAAA==.Jaihro:BAAANQADCgYIBgAAAA==.',
Je='Jefflich:BAAANQAECgMIBgAAAA==.Jefãoo:BAAANQAECgUIEQAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQADCggJDgAAAA==.Justimonk:BAAANQADCgEIAwAAAA==.',
Ka='Kaelyrah:BAAANQADCgQIBAAAAA==.Kardibito:BAAANQAECgQIBAAAAA==.Karmysh:BAAANQAECgEIAQAAAA==.Kazuopala:BAAANQAECgQIBwAAAA==.',
Kh='Khoj:BAAANQAECgYIEgAAAA==.Kholckk:BAAANQADCgUICgAAAA==.',
Ki='Killerdek:BAAANQAECgEIAQAAAA==.Killersall:BAABNQAECoEXAAILAAgKSghxaACTAQALAAgKSghxaACTAQAAAA==.',
Kl='Kluzlocak:BAAANQAECgMIBgAAAA==.',
Ko='Kore:BAAANQAECgEIAQABNQAECgcIGAAMAPQhAA==.',
Ku='Kutirenzo:BAAANQADCgcIDwAAAA==.',
Ky='Kysed:BAAANQADCgYICQAAAA==.Kyubi:BAAANQAECgMIAwAAAA==.',
La='Lafiel:BAAANQAECgQIBAAAAA==.Lahllis:BAAANQAECgIJAgAAAA==.Lahnara:BAAANQADCggICQAAAA==.Lanadelrei:BAAANQADCgIIAgAAAA==.Lanmo:BAABNQAECoEYAAIMAAcK9CEuBwCwAgAMAAcK9CEuBwCwAgAAAA==.Larrygou:BAAANQADCggICAAAAA==.Laurea:BAABNQAECoEiAAINAAgKxSWSBgB1AwANAAgKxSWSBgB1AwAAAA==.',
Le='Ledor:BAAANQAECgEIAQAAAA==.Lendarion:BAAANQAECgQJDgAAAA==.Leopvazi:BAAANQADCgIIAgAAAA==.Leozadock:BAAANQAECgUIBQAAAA==.Lewandosck:BAAANQAECgQIBAAAAA==.',
Li='Liana:BAAANQAECgQIBwABNQAECggIIgANAMUlAA==.Lichtbaum:BAABNQAECoEbAAMOAAgK7CB0CgDtAgAOAAgK7CB0CgDtAgAPAAEKTg/8lAAtAAAAAA==.Liifecomm:BAABNQAECoEWAAINAAgKhSIYGADoAgANAAgKhSIYGADoAgAAAA==.Lipaodrk:BAABNQAECoEwAAIKAAkKNxoNHwDFAgAKAAkKNxoNHwDFAgAAAA==.Lirobitt:BAAANQADCgMIAwAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lolipop:BAAANQABCgYICgAAAA==.Lordpain:BAABNQAECoEXAAQQAAcK7xdENQD2AQAQAAcK7xdENQD2AQARAAMKbwfYZwCJAAASAAIKVAZjnwBUAAAAAA==.Lorrd:BAAANQADCgcIBwAAAA==.Lortherti:BAAANQADCgQIBgAAAA==.Louisenacioo:BAAANQAECgYIDAAAAA==.',
Lu='Luccablack:BAAANQAECgMIAwAAAA==.Luccagelido:BAAANQADCgUIBQAAAA==.Luidar:BAAANQAECgcIDQAAAA==.Lukaslions:BAAANQAECgUIBgAAAA==.Luministar:BAAANQAECggIBAAAAA==.Luphoe:BAAANQAECgEIAwAAAA==.',
Ma='Madushi:BAAANQAECgcIDgAAAA==.Madzerø:BAAANQAECgQJBAAAAA==.Magatas:BAAANQADCgQJBAAAAA==.Maguul:BAAANQADCggIGQAAAA==.Malandrvs:BAAANQAECgYIDQAAAA==.Maldiçoadora:BAABNQAECoEhAAIEAAgKkh+7JAC8AgAEAAgKkh+7JAC8AgAAAA==.Malfurionsf:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.Malfuysera:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.Mangudah:BAAANQAECgQIBQABNQAECgYIDAABAAAAAA==.Mannaton:BAAANQAECgYIDAAAAA==.Manzagon:BAAANQADCggIHgABNQAECgYIDAABAAAAAA==.Marcijo:BAAANQABCgIIAgAAAA==.Maruh:BAAANQAECgUIBwAAAA==.Marúh:BAABNQAECoEkAAMTAAkKjh7JDwAdAwATAAkKjh7JDwAdAwALAAIKRxF41wByAAAAAA==.Mayarabr:BAAANQABCgYICQAAAA==.Maølayking:BAACNQAFFIEIAAMQAAIKPib/EADWAAAQAAIKziX/EADWAAASAAIKbiPxCwC7AAA1AAQKgTMAAxAACQqmJp4AAPEDABAACQqmJp4AAPEDABIAAworFJx3AMwAAAAA.',
Mc='Mclovingo:BAAANQADCgUIBAAAAA==.',
Me='Mendingu:BAAANQAECgcIEAAAAA==.Mercenarybr:BAAANQAECgYIEQAAAA==.',
Mi='Midrão:BAAANQADCgUIBQAAAA==.Mikasaackerr:BAAANQAECgUICgAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgYICQAAAA==.Miranda:BAAANQAECgQICAABNQAECggIIgANAMUlAA==.',
Mm='Mmenov:BAAANQADCgQIBQAAAA==.Mmenovw:BAAANQADCgEIAQAAAA==.',
Mo='Molior:BAAANQADCgYIBwAAAA==.Momongadk:BAAANQAECgcIEwAAAA==.Monkeydking:BAAANQAECgYICgAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moonluter:BAAANQAECgIJAgAAAA==.Morikenshin:BAAANQADCgUJBQAAAA==.Morinami:BAAANQABCgUJBwAAAA==.Moriyama:BAAANQAECgIIBAAAAA==.Morphizs:BAAANQAECgUICwABNQAECgYIDAABAAAAAA==.Morphoss:BAAANQAECgQIBQABNQAECgYIDAABAAAAAA==.Morsa:BAAANQADCggICAAAAA==.Mortesan:BAAANQAECgIJAgABNQAECgQIBQABAAAAAA==.',
My='Mystian:BAAANQADCgYIBwAAAA==.',
['Mä']='Mäven:BAAANQAECgQIBAABNQAECgkJIwAMAP4hAA==.',
['Må']='Måximus:BAAANQAECgYICwAAAA==.',
Na='Naeryndam:BAAANQADCgYIEQAAAA==.Nagojão:BAAANQADCggICAAAAA==.Naturezo:BAAANQAECgEIBAABNQAECgIJAgABAAAAAA==.Navira:BAAANQADCggICAAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Nedy:BAAANQADCgMIAwAAAA==.Negblack:BAAANQAECgEIAQAAAA==.Netherbane:BAAANQAECgQICgAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgUIBgAAAA==.',
Ni='Nieves:BAAANQADCgEIAQAAAA==.Nightmære:BAAANQAECgEIAQAAAA==.Ninfador:BAAANQADCgUIBQAAAA==.',
['Nø']='Nøsferatu:BAAANQAECgQIBwAAAA==.',
Oa='Oakshlar:BAAANQAECgQIBQAAAA==.Oalxorozco:BAAANQADCgIIAgAAAA==.',
Os='Osmotios:BAAANQAECgQIBgAAAA==.',
Ot='Otton:BAAANQAECgEJAQAAAA==.',
Pa='Paidesanto:BAAANQAECgQIBQAAAA==.Paladinokun:BAAANQAECgQIBQAAAA==.Palamino:BAAANQADCgMIAwAAAA==.Pandadruid:BAAANQADCgYICgAAAA==.Pantanegro:BAAANQADCgUICAAAAA==.',
Pe='Pedrö:BAAANQAECgQIEQAAAA==.Peçanhaa:BAAANQADCgQIBAAAAA==.',
Pi='Pinkfloid:BAAANQADCgcIBwAAAA==.',
Pl='Playsson:BAABNQAECoEZAAIHAAkKyhPEVwBAAgAHAAkKyhPEVwBAAgAAAA==.',
Pq='Pqchoras:BAAANQAECgYIDwAAAA==.',
Pr='Pravios:BAAANQAECgUICAAAAA==.',
Pu='Puherito:BAAANQADCgYIBgAAAA==.Purehito:BAAANQAECgQIBgAAAA==.Purifc:BAAANQAECgEIAQAAAA==.',
Ra='Radathewhite:BAAANQADCgYIBwAAAA==.Ravenblak:BAAANQADCgQIBAAAAA==.',
Rb='Rbarroco:BAAANQAECgQIBAABNQAECgcIEAABAAAAAA==.',
Re='Reigeladinho:BAAANQADCggIEAAAAA==.',
Ro='Robadoom:BAAANQAECgMICAAAAA==.Robeerth:BAAANQAECgYIBgABNQAECggIGgADAOIRAA==.Roderic:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.Rowane:BAAANQADCgQIBAAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQADCgcIGQAAAA==.',
Sa='Saanemi:BAAANQADCgIIAgAAAA==.Safiralc:BAAANQADCgEIAQAAAA==.Salaciel:BAAANQAECgQIBQAAAA==.Sarabifinho:BAAANQADCgQIBAAAAA==.Sardron:BAAANQADCgMIAwAAAA==.Saydrom:BAAANQADCgYJBgAAAA==.Sayur:BAAANQADCgcIDgAAAA==.',
Sc='Scanorr:BAAANQAECgYIBgAAAA==.Scanvyl:BAAANQABCgYICgAAAA==.',
Se='Selver:BAAANQADCgEIAQABNQAFFAYIEAAUAM8RAA==.Sepp:BAAANQADCgIIAgAAAA==.',
Sh='Shaladrasil:BAAANQADCgEIAwAAAA==.Shamjj:BAAANQADCgEIAQAAAA==.Shieldhonor:BAAANQADCggIEgAAAA==.Shisuui:BAAANQAECgYICwAAAA==.',
Si='Silvanna:BAAANQAECgIIBQAAAA==.Silvao:BAAANQADCgEIAgAAAA==.Sinkra:BAAANQADCgMIBAAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQAECgQIBwAAAA==.',
Sl='Sliiluuvrrp:BAAANQAECgQIBAAAAA==.Slyfer:BAAANQADCgIIAgAAAA==.',
So='Sonofroar:BAAANQAECgUJBgAAAA==.Sopharao:BAAANQADCgMIAwAAAA==.Soray:BAAANQAECgIIAwAAAA==.Sorim:BAAANQAECgUIBgAAAA==.',
Sp='Spãrta:BAAANQADCgIIAgAAAA==.',
St='Staffkiller:BAAANQAECgEIAgAAAA==.Strygah:BAAANQAECgMIBQAAAA==.Stx:BAAANQAECgQIBAAAAA==.',
Su='Sunthalas:BAAANQADCgcIDQAAAA==.Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgQJCAABNQAECgcIGAAMAPQhAA==.',
Ta='Taillys:BAAANQADCgcICAAAAA==.Talanis:BAAANQADCggICAABNQAECggIIgANAMUlAA==.Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQAECgEIAgAAAA==.Tarfonir:BAAANQAECgQICQAAAA==.Tarzønys:BAAANQADCgYIBgAAAA==.',
Te='Ted:BAAANQAECgQIBQAAAA==.',
Th='Thanorak:BAAANQADCgIJAgAAAA==.Thejokker:BAAANQADCgcICAAAAA==.Themooster:BAABNQAECoEdAAIVAAgKDRhjEgAsAgAVAAgKDRhjEgAsAgAAAA==.Thepickles:BAAANQADCgYJCQAAAA==.Thepunk:BAAANQAECgIIAgAAAA==.Thomzïn:BAAANQADCgcIDQAAAA==.Thormento:BAAANQAECgYICAAAAA==.Throosh:BAAANQADCggIGQAAAA==.Thundertroll:BAAANQADCgEIAQAAAA==.',
Ti='Tiriricao:BAAANQADCgQIBAAAAA==.Titanicos:BAAANQAECgMIBQAAAA==.Tiãocarneiro:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAABNQAECoEbAAQRAAgKtxH0NgCMAQARAAcKgA/0NgCMAQAQAAcKkw/uUgBjAQASAAIKgQYrogBOAAAAAA==.Torem:BAAANQADCgQIBAAAAA==.',
Tr='Trévor:BAAANQAECgUIDQAAAA==.',
Tu='Tubaras:BAAANQADCgEIAQAAAA==.Tututzz:BAAANQADCgMIAwAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYICwAAAA==.',
Ug='Ugugugana:BAAANQAECgQIBAAAAA==.',
Un='Unitt:BAAANQADCgMIAwAAAA==.Unseendeath:BAAANQAECgYIBgABNQAECgcIDgABAAAAAA==.',
Va='Valmila:BAAANQAECgQIBgAAAA==.Vandlesh:BAAANQADCgIIAgAAAA==.Vandlock:BAAANQABCgEIAQAAAA==.Varka:BAAANQADCgIIAgAAAA==.',
Ve='Velkharun:BAABNQAECoEaAAQDAAgK4hEFDAAkAgADAAgKrBEFDAAkAgAEAAUKlwsvuAD5AAAWAAIKOQ0HGQB7AAAAAA==.',
Vh='Vhaeraun:BAAANQADCgEIAQAAAA==.',
Vi='Viseryss:BAAANQADCgIIAgAAAA==.Vivifirex:BAAANQADCgEIAQAAAA==.',
Vo='Voidbrew:BAAANQAECgQICAAAAA==.',
Vu='Vunks:BAAANQAECgMIAwABNQAECgcIFgACAFMOAA==.',
Vy='Vylkk:BAAANQADCggICAAAAA==.',
['Ví']='Vídarr:BAAANQADCgUIBQAAAA==.',
['Vò']='Vòxs:BAAANQAECgUICgAAAA==.',
['Vö']='Völpina:BAAANQADCggICAAAAA==.',
Wa='Wako:BAABNQAECoEZAAIIAAYKYhIUogBuAQAIAAYKYhIUogBuAQAAAA==.Warlôck:BAAANQAECgIIAgAAAA==.Watdafoxsay:BAAANQAECgEJAQAAAA==.',
Wh='Whitersoul:BAABNQAECoFWAAMFAAkKWx+jAQBIAwAFAAkKWx+jAQBIAwACAAMKHAQoZQGFAAAAAA==.',
Wi='Wiitchkiing:BAAANQADCggIEgAAAA==.Willtratadoo:BAAANQADCgcICgAAAA==.Wiserys:BAABNQAECoEiAAQWAAkKzxm9BwDRAQAEAAgKSxYYUwASAgAWAAYKhhe9BwDRAQADAAMKeg4UQQCqAAAAAA==.',
Wm='Wmarcão:BAAANQAECgUIBgAAAA==.',
Wo='Wolfnwar:BAABNQAECoEiAAMGAAgKMgwcZgDxAQAGAAgKMgwcZgDxAQAXAAIKNASfYABUAAAAAA==.',
Xe='Xenomorpho:BAAANQADCgMIAwAAAA==.Xexnetw:BAAANQAECgIIAwAAAA==.Xexnew:BAABNQAECoEcAAMQAAkKxBspHACbAgAQAAkKxBspHACbAgARAAEKBgbdhQAwAAAAAA==.',
Xi='Xistaminosas:BAAANQABCgUIBgAAAA==.',
Xl='Xladymaladax:BAAANQADCgEJAQAAAA==.',
Xm='Xmari:BAABNQAECoEbAAIGAAgKhQSHpgBOAQAGAAgKhQSHpgBOAQAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xots:BAAANQADCgIIAgABNQAECgcIFgACAFMOAA==.',
Xt='Xtremetanke:BAAANQAECgEJAQAAAA==.',
Xx='Xxcantsidex:BAAANQAECgUIBgAAAA==.',
Ya='Yangyung:BAAANQAECgIIAgAAAA==.Yannadcg:BAAANQAECgUICAAAAA==.',
Yc='Ycantsideyx:BAAANQADCgYICgAAAA==.',
Ym='Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yorickundyer:BAAANQADCgYICQAAAA==.Yormogander:BAAANQADCgYICgABNQAECgcIIgAHAAgRAA==.Yorshka:BAAANQADCgYIBwAAAA==.',
Yr='Yrelistrasza:BAABNQAECoEZAAQYAAcKbQYaJgA9AQAYAAcKbQYaJgA9AQAZAAIKrADKOAAkAAAaAAEK2wHHHwAfAAAAAA==.',
Za='Zarolho:BAAANQADCgYICQAAAA==.',
Ze='Zeddh:BAAANQAECgQIBAABNQAECggIGgAHAFwQAA==.Zenaq:BAAANQADCgYIBgAAAA==.Zerdrax:BAAANQAECgQIDAAAAA==.',
Zi='Ziikiipala:BAAANQADCgIIAgAAAA==.',
['Ál']='Álucard:BAAANQAECgQIBwAAAA==.',
['Éy']='Éyga:BAAANQADCgUIEAAAAA==.',
['Ðw']='Ðwons:BAAANQADCgEIAQAAAA==.',
['Öx']='Öx:BAABNQAECoEXAAIWAAgKoRIqBQAyAgAWAAgKoRIqBQAyAgAAAA==.',
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
