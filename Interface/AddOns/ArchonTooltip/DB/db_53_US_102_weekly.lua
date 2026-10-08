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

local lookup = {'Unknown-Unknown','Shaman-Enhancement','Warrior-Arms','Mage-Arcane','Warlock-Destruction','DemonHunter-Havoc','Warlock-Demonology','Paladin-Protection','DeathKnight-Blood','DeathKnight-Frost','Mage-Frost','Hunter-BeastMastery','Monk-Windwalker','Evoker-Preservation','Evoker-Augmentation','Warrior-Fury','Paladin-Retribution','Priest-Shadow','Paladin-Holy','Shaman-Elemental','Druid-Guardian','Priest-Holy','Druid-Restoration','Druid-Balance','DeathKnight-Unholy','Shaman-Restoration','Warlock-Affliction','Hunter-Marksmanship','Evoker-Devastation',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acelord:BAAANQAECgYIDQAAAA==.Actaeon:BAAANQAECgYIDQAAAA==.',
Ad='Adariom:BAAANQADCgYIBgAAAA==.Adilma:BAAANQADCgUIBwAAAA==.Adriannos:BAAANQAECgYICwAAAA==.',
Ae='Aelthiriel:BAAANQADCggICAAAAA==.Aerosharpz:BAAANQADCgYIBgAAAA==.',
Ag='Aghatta:BAAANQADCgUIBQAAAA==.',
Ak='Akiji:BAAANQADCggIDwAAAA==.',
Al='Alamauri:BAAANQADCgYIBgAAAA==.Alceste:BAAANQADCgMIAwAAAA==.Ald:BAAANQADCgYIBgAAAA==.Alexextreme:BAAANQAECgIIAgAAAA==.Algea:BAAANQADCgMIAwABNQAECgUIDAABAAAAAA==.Algrixx:BAABNQAECoEYAAICAAgKKgd0FwDDAQACAAgKKgd0FwDDAQAAAA==.Aliaksandr:BAAANQADCgUIEAAAAA==.',
An='Andrëthö:BAAANQAECgQIBwABNQAECgcIFwADAJ8YAA==.Anellÿ:BAAANQADCgQIBAAAAA==.Angelloz:BAAANQAECgIIAgAAAA==.Anggos:BAAANQADCgMJAwAAAA==.Anjakiller:BAAANQADCggICAAAAA==.Anksunamoon:BAAANQAECggICQAAAA==.Annedin:BAAANQAECgIJAgAAAA==.Annia:BAAANQADCgEIAQAAAA==.Anyid:BAAANQADCgIIAgAAAA==.Anysoul:BAAANQAECgQIBAABNQADCgIIAgABAAAAAA==.Anystorm:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.',
Ap='Apökalÿpsïs:BAABNQAECoEgAAIEAAcKPBh/rwACAgAEAAcKPBh/rwACAgAAAA==.',
Aq='Aquadel:BAAANQAECgYICAAAAA==.',
Ar='Arcandror:BAAANQADCgQIBAAAAA==.Aristostelis:BAAANQAECgMIAwAAAA==.',
As='Asaff:BAAANQADCgQJBgAAAA==.Ashwell:BAAANQADCgUIBQAAAA==.',
At='Atomicdk:BAAANQADCgIIAgAAAA==.Atomicoutlaw:BAAANQADCgQIBAAAAA==.Atonos:BAAANQABCggIDAAAAA==.',
Az='Azadium:BAAANQAECgEIAQAAAA==.Azul:BAAANQAECgcIDwAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
['Aë']='Aëma:BAAANQAECgYIEgAAAA==.',
Ba='Balragouldur:BAAANQADCgUIBgAAAA==.Barkbouncer:BAAANQADCggICAAAAA==.',
Be='Beatriz:BAAANQADCgYJCAAAAA==.Beelgarath:BAAANQADCgEIAQAAAA==.Belorian:BAAANQADCgUICwAAAA==.Belowlight:BAAANQADCgcIFAAAAA==.Benoboi:BAAANQAECgUJBQAAAA==.Benícia:BAAANQABCgMIAwAAAA==.',
Bh='Bhaelorn:BAAANQAECgEIAQAAAA==.',
Bl='Blackfear:BAAANQAECgcICgABNQAECggIGgAFAOIRAA==.Blackteriaa:BAAANQAECgIIBAAAAA==.Blakwolf:BAAANQADCgEIAQAAAA==.Blankis:BAAANQABCggICQAAAA==.Blastoize:BAAANQAECgEIAQAAAA==.Bloodh:BAABNQAECoEWAAIGAAgK0RYuKQAsAgAGAAgK0RYuKQAsAgAAAA==.Bloodyz:BAAANQADCgYIDAAAAA==.Bluforged:BAEANQAECgYIEQAAAA==.',
Bo='Boamort:BAAANQAECgUICAAAAA==.Boruck:BAAANQABCgEIAQAAAA==.',
Br='Braeon:BAAANQADCgYIDwAAAA==.Brandomm:BAAANQAECgEIAQAAAA==.Bridda:BAAANQAECgEIAQAAAA==.Brinkst:BAAANQAECgEIAQAAAA==.',
Bu='Bugadark:BAAANQADCgcIBwAAAA==.Bullkiller:BAAANQADCgQIBAAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
['Bö']='Bömbur:BAAANQADCgQIBAAAAA==.',
['Bø']='Bøamorte:BAAANQADCgEIAQAAAA==.',
Ca='Canaduh:BAAANQADCgUIBQAAAA==.Casuall:BAAANQADCggIEAAAAA==.Catadora:BAAANQAECgMIAwABNQAECgkJJAAHAPYeAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAAANQAECgYIDgAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Cl='Climps:BAAANQAECgYIEwAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.Corvean:BAAANQADCgUIBQAAAA==.',
Cr='Creuzapriest:BAAANQAECgIIAgAAAA==.Crowlinhu:BAAANQAECgIIAgAAAA==.Cruzade:BAABNQAECoEZAAIIAAgKCxYvGQAAAgAIAAgKCxYvGQAAAgABNQAECggIGgAFAOIRAA==.Cröwllëy:BAAANQAECgUIDQAAAA==.',
Cu='Cubatao:BAAANQAECgEJAQAAAA==.Curatio:BAAANQAECgIIAgAAAA==.',
Da='Dahaka:BAAANQAECgQIDAAAAA==.Dahhak:BAAANQAECgUIBQAAAA==.Dakshayani:BAAANQAECgYIEwAAAA==.Dallion:BAAANQADCgUIDAAAAA==.Daportela:BAAANQADCgcICAAAAA==.Dardano:BAAANQABCggIDgAAAA==.Darkfuntz:BAABNQAECoEbAAIEAAcK2xRMrwACAgAEAAcK2xRMrwACAgAAAA==.Darkshaninha:BAAANQAECgUIBgAAAA==.Darkshurea:BAAANQAECgQIBgAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.Darksipa:BAAANQAECgMIAwAAAA==.',
De='Deadvi:BAABNQAECoEXAAIJAAcK4hk1OQABAgAJAAcK4hk1OQABAgAAAA==.Degenerative:BAABNQAECoEYAAIHAAkKKwBSQQEIAAAHAAkKKwBSQQEIAAAAAA==.Derothey:BAAANQAECgcIEgAAAA==.Devendeer:BAAANQABCgIIAgABNQAECgYIEwABAAAAAA==.',
Di='Dioniisio:BAAANQABCgQIBAAAAA==.',
Dk='Dkabeza:BAAANQADCgcIBwAAAA==.',
Dn='Dngkakuzo:BAABNQAECoEcAAIKAAgK8BNWLQD+AQAKAAgK8BNWLQD+AQAAAA==.',
Do='Dollynhø:BAAANQAECgUIBQAAAA==.Doomsman:BAAANQADCgcICgAAAA==.',
Dr='Dracomamante:BAAANQAECgYJEgAAAA==.Draconoide:BAAANQAECgUIEwAAAA==.Dracón:BAAANQADCgYIDAAAAA==.Dragnnyr:BAAANQAECgUICQAAAA==.Dragondrukc:BAAANQAECgcIEQAAAA==.Dreykar:BAAANQAECgYIDgAAAA==.Druidaezeki:BAAANQADCgUIBwAAAA==.',
Du='Duquetjb:BAAANQADCgYICAAAAA==.',
['Dä']='Dähäkä:BAAANQAECgcIEwAAAA==.',
Ed='Edasich:BAAANQADCggJCAAAAA==.Edven:BAAANQAECgQICQAAAA==.',
Ei='Eilin:BAAANQAECgUIBQAAAA==.',
El='Elbruxão:BAAANQAECgYIEwAAAA==.Eldarië:BAAANQABCgYICwAAAA==.Elementais:BAAANQAECgUIDAAAAA==.Ellanor:BAABNQAECoEgAAMEAAgKRxIppQAXAgAEAAgKRxIppQAXAgALAAEKYwHoSwAXAAAAAA==.Ellocopere:BAAANQAECgcIEwAAAA==.Elpala:BAAANQAECgQIBAAAAA==.Elpotoco:BAAANQADCgEIAQAAAA==.',
En='Envie:BAABNQAECoEgAAIMAAkKkSNCEQBIAwAMAAkKkSNCEQBIAwAAAA==.',
Er='Eratia:BAAANQADCgIIAgAAAA==.Eredith:BAAANQADCgQIBAAAAA==.Erhas:BAAANQAECgIIAwAAAA==.Erickya:BAABNQAECoEWAAINAAkKoBd9FQB/AgANAAkKoBd9FQB/AgAAAA==.Ervadocè:BAAANQADCgYIDAAAAA==.Ervelino:BAAANQAECgQIEwAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.Espectrudo:BAAANQADCgIIAgAAAA==.',
Eu='Euteinvoco:BAAANQADCggICAABNQAECggIGQAKAIQIAA==.',
Ev='Evely:BAAANQAECgUIEQAAAA==.',
Fa='Fabras:BAAANQADCgIIAgAAAA==.Falstro:BAAANQADCgYIBgAAAA==.',
Fe='Felenus:BAAANQAECgUIBgAAAA==.Felguk:BAAANQADCgIJAgAAAA==.Ferdruiid:BAAANQABCgUICgAAAA==.Fermoonie:BAAANQAECgIIAwAAAA==.',
Fi='Firexo:BAAANQADCgEIAQAAAA==.',
Fl='Flemma:BAABNQAECoEVAAMOAAcKzxL9IACpAQAOAAcKzxL9IACpAQAPAAMKgAkxGQB/AAAAAA==.Flexer:BAAANQAECgEIAgAAAA==.',
Fo='Fonderus:BAAANQADCgMIBAAAAA==.Foxyroxy:BAAANQAECgQICgAAAA==.',
Fr='Friodokrl:BAAANQAECgcIEwAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAABNQAECoEzAAIEAAgKkxozeQB1AgAEAAgKkxozeQB1AgAAAA==.',
Ga='Gafgar:BAAANQAECggICwAAAA==.Gafowi:BAAANQAECgUIEgAAAA==.Galduin:BAABNQAECoExAAIDAAgK4hTUbgAmAgADAAgK4hTUbgAmAgAAAA==.Garrincha:BAAANQADCgYIBwABNQAECgQIBwABAAAAAA==.Gaunterodim:BAAANQAECgYICwAAAA==.',
Ge='Gentioiroh:BAAANQAECgUIBwAAAA==.Gever:BAAANQADCgUIBQAAAA==.',
Gh='Ghopo:BAAANQAECgEIAgAAAA==.',
Gi='Giradus:BAAANQADCgUICgAAAA==.',
Gl='Glorcckk:BAAANQADCgUIBgAAAA==.',
Gn='Gnomagga:BAAANQADCgMIAwABNQAECggIEgABAAAAAA==.',
Gr='Greedom:BAAANQADCgIIAgAAAA==.Grimblade:BAAANQADCgEIAQAAAA==.Grindewald:BAAANQADCgcIBwAAAA==.Grommhell:BAABNQAECoEcAAIDAAgKAAs9lgC8AQADAAgKAAs9lgC8AQAAAA==.Grím:BAAANQAECgQIBgAAAA==.',
Gu='Gudangara:BAAANQAECgEIAQAAAA==.Gugans:BAAANQAECgQIBAAAAA==.Guzinbrs:BAAANQADCgcIDAAAAA==.',
Ha='Haakaí:BAABNQAECoEYAAMDAAcK6BDQkgDFAQADAAcK6BDQkgDFAQAQAAMKkQ9rHgCnAAAAAA==.Haandir:BAAANQAECgUIBgAAAA==.Hadassä:BAAANQABCgEIAgAAAA==.Hafessä:BAAANQADCgMIAwAAAA==.Hakuro:BAAANQAECgIIAwAAAA==.Harany:BAAANQAECgIJAgABNQAECgMIBgABAAAAAA==.Havatar:BAAANQADCgQIBAAAAA==.',
He='Herablack:BAAANQAECgQIAwAAAA==.',
Hi='Himikonee:BAAANQAECgQIDwAAAA==.',
Ho='Horstmeyer:BAAANQADCgIIAgAAAA==.',
Hu='Hulig:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
['Hø']='Høkulani:BAAANQAECgYIDQAAAA==.',
Ib='Ib:BAAANQADCggICQAAAA==.',
Ig='Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAABNQAECoEjAAIRAAgKqBkTVwBoAgARAAgKqBkTVwBoAgAAAA==.Iksivokilirt:BAAANQADCgIJAgAAAA==.Ikslawok:BAAANQADCggIDwAAAA==.',
Il='Ileria:BAAANQADCggICgAAAA==.Illusionarc:BAAANQAECgYIDwABNQAECgkKKQAGAO4dAA==.',
In='Incognita:BAABNQAECoEXAAISAAgKZBGeIgD4AQASAAgKZBGeIgD4AQAAAA==.Infernús:BAAANQADCgYIBgABNQAECgQIDQABAAAAAA==.Interst:BAAANQADCgcIBwAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQAECgEIAQAAAA==.',
Is='Iscalio:BAAANQAECgUIEQAAAA==.',
It='Itatchii:BAAANQAECgQIDAAAAA==.',
Iu='Iuuh:BAABNQAECoEiAAITAAgK6xiHOABmAgATAAgK6xiHOABmAgAAAA==.',
Ja='Jackdawnsong:BAAANQADCgQICAAAAA==.Jahuun:BAABNQAECoEgAAIRAAgKtg0AlwDAAQARAAgKtg0AlwDAAQAAAA==.Jaihro:BAAANQADCgYIBgAAAA==.',
Je='Jefflich:BAAANQAECgMIBgAAAA==.Jefãoo:BAABNQAECoEZAAMRAAgKGxPLfgD7AQARAAgKGxPLfgD7AQAIAAEKWw6DZgArAAAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQADCggJDgAAAA==.Justimonk:BAAANQADCgEIAwAAAA==.',
Ka='Kaelyrah:BAAANQADCgQIBAAAAA==.Kaldonios:BAAANQADCgQIAwAAAA==.Kalipho:BAAANQADCgUIBQAAAA==.Kardibito:BAAANQAECgUIBgAAAA==.Karmysh:BAAANQAECgEIAQAAAA==.Kazuopala:BAAANQAECgQIBwAAAA==.',
Ke='Kentàk:BAAANQAECgIIAgAAAA==.',
Kh='Khoj:BAAANQAECgYIEwAAAA==.Kholckk:BAAANQADCgUICgAAAA==.',
Ki='Killerdek:BAAANQAECgEIAQAAAA==.Killersall:BAABNQAECoEcAAIUAAgKXAqlcgCZAQAUAAgKXAqlcgCZAQAAAA==.',
Kl='Kluzlocak:BAAANQAECgMICQAAAA==.',
Ko='Kore:BAAANQAECgEIAQABNQAECgcIHAAVAP4hAA==.',
Ku='Kutirenzo:BAAANQADCgcIDwAAAA==.',
Ky='Kysed:BAAANQADCgYICQAAAA==.Kyubi:BAAANQAECgQIBwAAAA==.',
La='Lafiel:BAAANQAECgQIBAAAAA==.Lagertha:BAAANQAECgMIAwAAAA==.Lahllis:BAAANQAECgIJAgAAAA==.Lahnara:BAAANQADCggICQAAAA==.Lanadelrei:BAAANQADCgIIAgAAAA==.Lanmo:BAABNQAECoEcAAIVAAcK/iFdCQCpAgAVAAcK/iFdCQCpAgAAAA==.Larrygou:BAAANQADCggICAAAAA==.Laurea:BAABNQAECoElAAIWAAkKoCLuAgCxAwAWAAkKoCLuAgCxAwAAAA==.',
Le='Ledor:BAAANQAECgUIBgAAAA==.Lendarion:BAAANQAECgQJDgAAAA==.Leopvazi:BAAANQADCgIIAgAAAA==.Leozadock:BAAANQAECgUIBgAAAA==.Leozadok:BAAANQADCgQIBAAAAA==.Lewandosck:BAAANQAECgQICQAAAA==.',
Li='Liana:BAAANQAECgQICwABNQAECgkJJQAWAKAiAA==.Lichtbaum:BAABNQAECoEhAAMXAAgKAyJYCgAIAwAXAAgKAyJYCgAIAwAYAAIKqw9JjgBnAAAAAA==.Liifecomm:BAABNQAECoEkAAIWAAkKnyCvCwBTAwAWAAkKnyCvCwBTAwAAAA==.Lipaodrk:BAABNQAECoEzAAITAAkKNxoZJgC5AgATAAkKNxoZJgC5AgAAAA==.Lirobitt:BAAANQADCgMIAwAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lolipop:BAAANQABCgYICgAAAA==.Lordpain:BAABNQAECoEeAAQJAAgKvxknKwBRAgAJAAgKvxknKwBRAgAKAAMKbweJdgCDAAAZAAIKVAZEuwBTAAAAAA==.Lorrd:BAAANQADCgcIBwAAAA==.Lortherti:BAAANQADCgQIBgAAAA==.Louisenacioo:BAAANQAECgYIEQAAAA==.',
Lu='Luanacarniça:BAAANQADCgIIAgAAAA==.Luccablack:BAAANQAECgUIBAAAAA==.Luccagelido:BAAANQAECgIIAgAAAA==.Luidar:BAAANQAECgcIDQAAAA==.Lukaslions:BAAANQAECgUIBgAAAA==.Luministar:BAAANQAECggIBgAAAA==.Luphoe:BAAANQAECgEIAwAAAA==.',
Ly='Lyandriis:BAAANQADCggICAAAAA==.',
Ma='Madushi:BAABNQAECoEdAAIRAAkKoh2AIwAdAwARAAkKoh2AIwAdAwAAAA==.Madzerø:BAAANQAECgUICAAAAA==.Magatas:BAAANQADCgQIBAAAAA==.Maguul:BAAANQADCggIGQAAAA==.Malandrvs:BAAANQAECgYIDQAAAA==.Maldiçoadora:BAABNQAECoEkAAIHAAkK9h7MGQALAwAHAAkK9h7MGQALAwAAAA==.Malfurionsf:BAAANQAECgQIBAABNQAECgcIFwAJAOIZAA==.Malfuysera:BAAANQAECgQIBAABNQAECgcIFwAJAOIZAA==.Mangudah:BAAANQAECgYICwABNQAECgcIEQABAAAAAA==.Mannaton:BAAANQAECgcIEQAAAA==.Manzagon:BAAANQAECgQIBAABNQAECgcIEQABAAAAAA==.Marcijo:BAAANQABCgIIAgAAAA==.Maruh:BAAANQAECgUIBwAAAA==.Marúh:BAABNQAECoEmAAMaAAkKjh7WFQAHAwAaAAkKjh7WFQAHAwAUAAIKRxFp8gBsAAAAAA==.Mayarabr:BAAANQABCgYICQAAAA==.Maølayking:BAACNQAFFIELAAMZAAMKLyJCDAAdAQAZAAMKiyFCDAAdAQAJAAIKziV3FQDRAAA1AAQKgTUAAwkACQquJs8AAOwDAAkACQquJs8AAOwDABkAAworFPOOAMYAAAAA.',
Mc='Mclovingo:BAAANQADCgUIBAAAAA==.',
Me='Mendingu:BAABNQAECoEXAAIDAAcKnxjycQAdAgADAAcKnxjycQAdAgAAAA==.Mercenarybr:BAABNQAECoEcAAIRAAcKPwyctgB4AQARAAcKPwyctgB4AQAAAA==.',
Mi='Midrão:BAAANQADCgUIBQAAAA==.Mikasaackerr:BAAANQAECgYIDgAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgYICgAAAA==.Miranda:BAAANQAECgQICAABNQAECgkJJQAWAKAiAA==.',
Mm='Mmenov:BAAANQADCgQIBQAAAA==.Mmenovw:BAAANQADCgEIAQAAAA==.',
Mo='Molior:BAAANQADCgYIBwAAAA==.Momongadk:BAABNQAECoEbAAIJAAgKnwygUgCIAQAJAAgKnwygUgCIAQAAAA==.Monkeydking:BAAANQAECgYICgAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moonluter:BAAANQAECgIJAgAAAA==.Mordekais:BAAANQAECgYIBgAAAA==.Morikenshin:BAAANQADCgUJBQAAAA==.Morinami:BAAANQABCgUJBwAAAA==.Moriyama:BAAANQAECgQICAAAAA==.Morphizs:BAAANQAECgcIEAABNQAECgcIEQABAAAAAA==.Morphoss:BAAANQAECgUIBQABNQAECgcIEQABAAAAAA==.Morsa:BAAANQADCggICAAAAA==.Mortesan:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.',
My='Mystian:BAAANQADCgYIBwAAAA==.',
['Mä']='Mäven:BAAANQAECgQICQABNQAECgkJKgAVAE0iAA==.',
['Må']='Måximus:BAAANQAECgcIEAAAAA==.',
Na='Naeryndam:BAAANQADCgYIEQAAAA==.Nagojão:BAAANQADCggICAAAAA==.Naturezo:BAAANQAECgMIBgAAAA==.Navira:BAAANQADCggICAAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Nedy:BAAANQADCgMIAwAAAA==.Negblack:BAAANQAECgQIBQAAAA==.Netherbane:BAAANQAECggIEQAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgUIBgAAAA==.',
Ni='Nieves:BAAANQADCgEIAQAAAA==.Nightmære:BAAANQAECgMIBAAAAA==.Ninfador:BAAANQADCgUIBQAAAA==.',
['Nø']='Nøsferatu:BAAANQAECgQIBwAAAA==.',
Oa='Oakshlar:BAAANQAECgQICgAAAA==.Oalxorozco:BAAANQADCgIIAgAAAA==.',
Os='Osmotios:BAAANQAECgQIBgAAAA==.',
Ot='Otton:BAAANQAECgUIBgAAAA==.',
Pa='Paidesanto:BAAANQAECgUIBQAAAA==.Paladinokun:BAAANQAECgQIBQAAAA==.Palamino:BAAANQADCgMIAwAAAA==.Pandadruid:BAAANQADCgYICgAAAA==.Pantanegro:BAAANQADCgUICAAAAA==.',
Pe='Pedrö:BAAANQAECgQIEQAAAA==.Pepeti:BAAANQADCgcIBwAAAA==.Peçanhaa:BAAANQAECgEIAQAAAA==.',
Pi='Pinkfloid:BAAANQADCgcICAAAAA==.',
Pl='Placides:BAAANQADCgUIBwAAAA==.Playsson:BAABNQAECoEhAAIDAAkKbBY0SgCRAgADAAkKbBY0SgCRAgAAAA==.',
Pq='Pqchoras:BAABNQAECoEZAAIJAAgK+x3wHACwAgAJAAgK+x3wHACwAgAAAA==.',
Pr='Pravios:BAAANQAECgUICAAAAA==.',
Pu='Puherito:BAAANQADCgYIBgAAAA==.Purehito:BAAANQAECgQICAAAAA==.Purifc:BAAANQAECgQIBAAAAA==.',
Ra='Radathewhite:BAAANQAECgUIBQAAAA==.Ravenblak:BAAANQADCgQIBAAAAA==.Raÿne:BAAANQAECgEIAQAAAA==.',
Rb='Rbarroco:BAAANQAECgQIBAABNQAECgcIFwADAJ8YAA==.',
Re='Reigeladinho:BAAANQADCggIFAAAAA==.',
Ro='Robadoom:BAAANQAECgYIDgAAAA==.Robeerth:BAAANQAECggIDgABNQAECggIGgAFAOIRAA==.Roderic:BAAANQAECgEIAQABNQAECgcIFwADAJ8YAA==.Rowane:BAAANQADCgQIBAAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQADCgcIGQAAAA==.',
['Rä']='Räghnar:BAAANQAECgEIAQAAAA==.',
Sa='Saanemi:BAAANQADCgIIAgAAAA==.Safiralc:BAAANQADCgEIAQAAAA==.Salaciel:BAAANQAECgUICQAAAA==.Sarabifinho:BAAANQADCgQIBAAAAA==.Sardron:BAAANQADCgMIAwAAAA==.Saydrom:BAAANQADCgYJBgAAAA==.Sayur:BAAANQADCgcIDgAAAA==.',
Sc='Scanorr:BAAANQAECgYIDAAAAA==.Scanvyl:BAAANQAECgQIBQAAAA==.',
Se='Selver:BAAANQADCgIIAwABNQAFFAYIFQASAJUVAA==.Sepp:BAAANQADCgIIAgAAAA==.',
Sh='Shaladrasil:BAAANQADCgEIAwAAAA==.Shamjj:BAAANQADCgEIAQAAAA==.Shieldhonor:BAAANQADCggIEgAAAA==.Shisuui:BAAANQAECgYIEQAAAA==.',
Si='Silvanna:BAAANQAECgIIBwAAAA==.Silvao:BAAANQAECgEIAQAAAA==.Sinkra:BAAANQADCgMIBAAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQAECgQIBwAAAA==.',
Sl='Sliiluuvrrp:BAAANQAECgQICAAAAA==.Slyfer:BAAANQADCgIIBAAAAA==.',
So='Sonofroar:BAAANQAECgUJBgAAAA==.Sopharao:BAAANQADCgMIAwAAAA==.Soray:BAAANQAECgIIAwAAAA==.Sorim:BAAANQAECgUIDAAAAA==.',
Sp='Spãrta:BAAANQADCgIIAgAAAA==.',
St='Staffkiller:BAAANQAECgEIAwAAAA==.Strygah:BAAANQAECgMIBQAAAA==.Stx:BAAANQAECgQIBAAAAA==.',
Su='Sunthalas:BAAANQADCggIFQAAAA==.Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgQJCAABNQAECgcIHAAVAP4hAA==.',
Ta='Taillys:BAAANQADCgcICAAAAA==.Talanis:BAAANQADCggICAABNQAECgkJJQAWAKAiAA==.Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQAECgEIAgAAAA==.Tarfonir:BAAANQAECgcIDwAAAA==.Tarzønys:BAAANQADCgYIBgAAAA==.',
Te='Ted:BAAANQAECgYICQAAAA==.',
Th='Thanorak:BAAANQADCgIJAgAAAA==.Thejokker:BAAANQADCgcICAAAAA==.Themooster:BAABNQAECoElAAIIAAkKtRlaDgCSAgAIAAkKtRlaDgCSAgAAAA==.Thepickles:BAAANQADCgYIDwAAAA==.Thepunk:BAAANQAECgIIAgAAAA==.Thiyva:BAAANQADCgIIAgAAAA==.Thomzïn:BAAANQADCgcIDwAAAA==.Thormento:BAAANQAECgYICAAAAA==.Throosh:BAAANQADCggIGQAAAA==.Thundertroll:BAAANQADCgEIAQAAAA==.',
Ti='Tiriricao:BAAANQAECgMIAwAAAA==.Titanicos:BAAANQAECgUICwAAAA==.Tiãocarneiro:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAABNQAECoEjAAQKAAgK2xJkPACbAQAKAAcKzRBkPACbAQAJAAcKBBGYWABvAQAZAAIKgQYWvgBNAAAAAA==.Torem:BAAANQADCgQICAAAAA==.',
Tr='Trelhunter:BAAANQAECgEIAQAAAA==.Trévor:BAAANQAECgYIEQAAAA==.',
Tu='Tubaras:BAAANQADCgEIAQAAAA==.Tututzz:BAAANQADCgMIAwAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYICwAAAA==.',
Ug='Ugugugana:BAAANQAECgQICAAAAA==.',
Un='Unitt:BAAANQADCgMIAwAAAA==.Unseendeath:BAAANQAECgYIBwABNQAECgkJHQARAKIdAA==.',
Va='Valmila:BAAANQAECgQIBgAAAA==.Vandlesh:BAAANQADCgIIAgAAAA==.Vandlock:BAAANQABCgEIAQAAAA==.Varka:BAAANQADCgIIAgAAAA==.',
Ve='Velkharun:BAABNQAECoEaAAQFAAgK4hGDDQAVAgAFAAgKrBGDDQAVAgAHAAUKlwtn0gD4AAAbAAIKOQ1IHAB3AAAAAA==.Velmora:BAAANQADCgUIBgAAAA==.',
Vh='Vhaeraun:BAAANQAECgEIAQAAAA==.',
Vi='Viseryss:BAAANQADCgIIAgAAAA==.Vivifirex:BAAANQADCgEIAQAAAA==.',
Vo='Voidbrew:BAAANQAECgUICQAAAA==.',
Vu='Vunks:BAAANQAECgMIAwABNQAECgcIGwAEANsUAA==.',
Vy='Vylkk:BAAANQADCggIDwAAAA==.',
['Ví']='Vídarr:BAAANQADCgUIBQAAAA==.',
['Vò']='Vòxs:BAAANQAECgUICgAAAA==.',
['Vö']='Völpina:BAAANQADCggICAAAAA==.',
Wa='Wako:BAABNQAECoEgAAIRAAcK3xWKjQDWAQARAAcK3xWKjQDWAQAAAA==.Warlôck:BAAANQAECgIIAgAAAA==.Watdafoxsay:BAAANQAECgEIAQAAAA==.',
Wh='Whitersoul:BAABNQAECoFlAAMLAAkKiSDMAQBPAwALAAkKiSDMAQBPAwAEAAMK0Ab9fAGTAAAAAA==.',
Wi='Wiitchkiing:BAAANQADCggIEgAAAA==.Willtratadoo:BAAANQADCgcICgAAAA==.Wiserys:BAABNQAECoEkAAQbAAkKzxl0CQDDAQAHAAgKSxYvZQAGAgAbAAYKhhd0CQDDAQAFAAMKeg6LRQClAAAAAA==.',
Wm='Wmarcão:BAAANQAECgUICQAAAA==.',
Wo='Wolfnwar:BAABNQAECoEpAAMMAAgKvA4zagATAgAMAAgKvA4zagATAgAcAAIKNASrbQBTAAAAAA==.',
Xe='Xenomorpho:BAAANQADCgcICAAAAA==.Xexnetw:BAAANQAECgIIBAAAAA==.Xexnew:BAABNQAECoEeAAMJAAkKxBuhIgCIAgAJAAkKxBuhIgCIAgAKAAEKBgZsmQAsAAAAAA==.',
Xi='Xistaminosas:BAAANQABCgUIBgAAAA==.',
Xl='Xladymaladax:BAAANQADCgEJAQAAAA==.',
Xm='Xmari:BAABNQAECoEiAAIMAAgKAgbwogCOAQAMAAgKAgbwogCOAQAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xots:BAAANQADCgIIAgABNQAECgcIGwAEANsUAA==.',
Xt='Xtremetanke:BAAANQAECgEJAQAAAA==.',
Xx='Xxcantsidex:BAAANQAECgUIBgAAAA==.',
Ya='Yangyung:BAAANQAECgQIBQAAAA==.Yannadcg:BAAANQAECgYIDgAAAA==.',
Yc='Ycantsideyx:BAAANQADCgYICgAAAA==.',
Ym='Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yormogander:BAAANQADCgYICgABNQAECggIMQADAOIUAA==.Yorshka:BAAANQADCgYIBwAAAA==.',
Yr='Yrelistrasza:BAABNQAECoEhAAQOAAgKcQeoJAB6AQAOAAgKcQeoJAB6AQAdAAIKrADnPQAjAAAPAAEK2wH5IwAeAAAAAA==.',
Za='Zapdos:BAAANQADCgIIAgAAAA==.Zarolho:BAAANQADCgYICQAAAA==.',
Ze='Zeddh:BAAANQAECgQIBAAAAA==.Zenaq:BAAANQAECgEIAQAAAA==.Zerdrax:BAABNQAECoEXAAIEAAcKNhEzygDNAQAEAAcKNhEzygDNAQAAAA==.',
Zi='Ziikiipala:BAAANQADCgIIAgAAAA==.',
['Ál']='Álucard:BAAANQAECgQIBwAAAA==.',
['Éy']='Éyga:BAAANQADCgUIEAAAAA==.',
['Ðw']='Ðwons:BAAANQADCgEIAQAAAA==.',
['Ör']='Örgrekai:BAAANQADCggICAAAAA==.',
['Öx']='Öx:BAABNQAECoEaAAIbAAgKoRKMBgAeAgAbAAgKoRKMBgAeAgAAAA==.',
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
