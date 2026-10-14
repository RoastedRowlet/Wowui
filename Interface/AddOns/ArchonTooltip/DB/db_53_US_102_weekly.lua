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

local lookup = {'Shaman-Enhancement','Warrior-Arms','Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Havoc','Warlock-Demonology','Paladin-Protection','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Frost','Warlock-Destruction','DemonHunter-Vengeance','Paladin-Retribution','Mage-Frost','Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','Warrior-Fury','Druid-Guardian','Paladin-Holy','DeathKnight-Unholy','Shaman-Elemental','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Warlock-Affliction','Hunter-Marksmanship','Evoker-Devastation',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acelord:BAAANQAECgYIEwAAAA==.Actaeon:BAAANQAECggIEgAAAA==.',
Ad='Adaa:BAAANQADCgQIBAAAAA==.Adariom:BAAANQADCgYIBgAAAA==.Adilma:BAAANQADCgUIBwAAAA==.Adriannos:BAAANQAECgYIDgAAAA==.',
Ae='Aelthiriel:BAAANQADCggICAAAAA==.Aena:BAAANQAECgEIAQAAAA==.Aerosharpz:BAAANQADCggIDgAAAA==.',
Ag='Aghatta:BAAANQADCgUIBQAAAA==.',
Ak='Akiji:BAAANQADCggIDwAAAA==.',
Al='Alamauri:BAAANQADCgYIBgAAAA==.Alceste:BAAANQAECgIIAgAAAA==.Ald:BAAANQADCgYIBgAAAA==.Alexextreme:BAAANQAECgIIAgAAAA==.Algea:BAAANQADCgMIAwAAAA==.Algrixx:BAABNQAECn8aAAIBAAgKmgcWGwCuAQABAAgKmgcWGwCuAQAAAA==.Aliaksandr:BAAANQADCgYIEgAAAA==.',
An='Andrëthö:BAAANQAECgQICwABNQAECgcIHgACAOUbAA==.Anellÿ:BAAANQADCgQIBAAAAA==.Angelloz:BAAANQAECgIIAgAAAA==.Anggos:BAAANQADCgMJAwAAAA==.Anjakiller:BAAANQADCggICAAAAA==.Anksunamoon:BAAANQAECggIDAAAAA==.Annedin:BAAANQAECgIJAgABNQAECgYIBgADAAAAAA==.Annia:BAAANQADCgEIAQAAAA==.Anyid:BAAANQADCgIIAgAAAA==.Anysoul:BAAANQAECgQIBgABNQADCgIIAgADAAAAAA==.Anystorm:BAAANQAECgEIAQABNQADCgIIAgADAAAAAA==.',
Ap='Apökalÿpsïs:BAABNQAECn8gAAIEAAcKgxkNyQDxAQAEAAcKgxkNyQDxAQAAAA==.',
Aq='Aquadel:BAAANQAECgYICgAAAA==.',
Ar='Arcandror:BAAANQADCgYICgAAAA==.Aristostelis:BAAANQAECgMIAwAAAA==.',
As='Asaff:BAAANQADCgQJBgAAAA==.Ashwell:BAAANQAECgQIBAAAAA==.Ashwhiz:BAAANQADCgYIBgAAAA==.',
At='Atomicdk:BAAANQADCgIIAgAAAA==.Atomicoutlaw:BAAANQADCgQIBAAAAA==.Atonos:BAAANQABCggIDAAAAA==.',
Az='Azadium:BAAANQAECgEIAQAAAA==.Azul:BAAANQAECgcIEAAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
['Aë']='Aëma:BAAANQAECgYIEgAAAA==.',
Ba='Balragouldur:BAAANQADCgUIBgAAAA==.Barkbouncer:BAAANQADCggICAAAAA==.',
Be='Beatriz:BAAANQADCgYJCAAAAA==.Beelgarath:BAAANQADCgEIAQAAAA==.Belorian:BAAANQADCgUICwAAAA==.Belowlight:BAAANQADCgcIFAAAAA==.Benoboi:BAAANQAECgUJBQAAAA==.Benícia:BAAANQABCgMIAwAAAA==.Beyoond:BAAANQAECgUIBgAAAA==.',
Bh='Bhaelorn:BAAANQAECgEIAgAAAA==.Bhalin:BAAANQAECgYIBgABNQAECgQIBQADAAAAAA==.',
Bl='Blackfear:BAAANQAECgcICgABNQAECgkJGAAFAJgcAA==.Blackteriaa:BAAANQAECgIIBAAAAA==.Blakwolf:BAAANQAECgYICwAAAA==.Blankis:BAAANQABCggICQAAAA==.Blastoize:BAAANQAECgEIAQAAAA==.Bloodh:BAABNQAECn8dAAIGAAgKCBt0KwBCAgAGAAgKCBt0KwBCAgAAAA==.Bloodyz:BAAANQADCgYIDAAAAA==.Bluforged:BAEANQAECgYIEQAAAA==.',
Bo='Boamort:BAAANQAECgUICAAAAA==.Boruck:BAAANQABCgEIAQAAAA==.',
Br='Braeon:BAAANQADCgYIDwAAAA==.Brandomm:BAAANQAECgEIAQAAAA==.Bridda:BAAANQAECgEIAQAAAA==.Brinkst:BAAANQAECgEIAQAAAA==.',
Bu='Bugadark:BAAANQADCgcIBwAAAA==.Bullkiller:BAAANQADCgQIBAAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
['Bö']='Bömbur:BAAANQADCgQIBAAAAA==.',
['Bø']='Bøamorte:BAAANQADCgEIAQAAAA==.',
Ca='Canaduh:BAAANQADCgUIBQAAAA==.Casuall:BAAANQADCggIEAAAAA==.Catadora:BAAANQAECgYICQABNQAECgkJJwAHAPceAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAAANQAECggIEwAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Cl='Climps:BAABNQAECn8ZAAIFAAcKDA1wpAC5AQAFAAcKDA1wpAC5AQAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.Corvean:BAAANQADCgUIBQAAAA==.',
Cr='Creuzapriest:BAAANQAECgQIBQAAAA==.Crowlinhu:BAAANQAECgIIAgAAAA==.Cruzade:BAABNQAECn8bAAIIAAgKXBWSHgDwAQAIAAgKXBWSHgDwAQABNQAECgkJGAAFAJgcAA==.Cröwllëy:BAAANQAECgYIDwAAAA==.',
Cu='Cubatao:BAAANQAECgEJAQAAAA==.Curatio:BAAANQAECgIIAgAAAA==.',
Da='Dahaka:BAAANQAECgQIEAAAAA==.Dahhak:BAAANQAECgUICQAAAA==.Dakshayani:BAABNQAECn8dAAIJAAgKJg7GdwCgAQAJAAgKJg7GdwCgAQAAAA==.Dallion:BAAANQADCgUIDAAAAA==.Daportela:BAAANQAECgQIBAAAAA==.Dardano:BAAANQABCggIDgAAAA==.Darkfuntz:BAABNQAECn8dAAIEAAcKcREoxgD2AQAEAAcKcREoxgD2AQAAAA==.Darkshaninha:BAAANQAECgQIDgAAAA==.Darkshurea:BAAANQAECgcICwAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.Darksipa:BAAANQAECgQIBgAAAA==.',
De='Deadvi:BAABNQAECn8eAAIKAAcK0RxeNgAvAgAKAAcK0RxeNgAvAgAAAA==.Degenerative:BAABNQAECn8YAAIHAAkKNwBtXQEJAAAHAAkKNwBtXQEJAAAAAA==.Demonicom:BAAANQADCgUIBQAAAA==.Derothey:BAABNQAECn8WAAIEAAgK3QkI4gDBAQAEAAgK3QkI4gDBAQAAAA==.Devendeer:BAAANQABCgIIAgABNQAECggIHQAJACYOAA==.',
Di='Digipatrocin:BAAANQADCgIIAgAAAA==.Dioniisio:BAAANQABCgQIBAAAAA==.',
Dk='Dkabeza:BAAANQADCgcIBwAAAA==.',
Dn='Dngkakuzo:BAABNQAECn8iAAILAAgKPRUdNwD2AQALAAgKPRUdNwD2AQAAAA==.',
Do='Dollynhø:BAAANQAECgcIDQAAAA==.Doomsman:BAAANQADCgcICgAAAA==.',
Dr='Drackulla:BAAANQAECgEIAQAAAA==.Dracomamante:BAAANQAECgYJEgAAAA==.Draconoide:BAABNQAECn8dAAMHAAcKtQrfqAB8AQAHAAcKtQrfqAB8AQAMAAIKswLBZgBUAAAAAA==.Dracón:BAAANQADCgYIDwAAAA==.Dragnnyr:BAAANQAECgUIDQAAAA==.Dragondrukc:BAAANQAECgcIEQAAAA==.Dreykar:BAABNQAECn8VAAINAAgKihgJCgA6AgANAAgKihgJCgA6AgAAAA==.Druidaezeki:BAAANQADCgUIBwAAAA==.',
Du='Duquetjb:BAAANQADCgYICAAAAA==.',
['Dä']='Dähäkä:BAABNQAECn8aAAIOAAgKlhnSfwAlAgAOAAgKlhnSfwAlAgAAAA==.',
Ed='Edasich:BAAANQADCggJCAAAAA==.Edven:BAAANQAECgQICQAAAA==.',
Ei='Eilin:BAAANQAECgUICgAAAA==.',
El='Elbruxão:BAABNQAECn8aAAIHAAcKjA6EpACGAQAHAAcKjA6EpACGAQAAAA==.Eldarië:BAAANQABCgYICwAAAA==.Elementais:BAAANQAECgUIDAAAAA==.Ellanor:BAABNQAECn8nAAMEAAgK0hTSqQAtAgAEAAgK0hTSqQAtAgAPAAEKAADXUwAXAAAAAA==.Ellocopere:BAABNQAECn8bAAQQAAgK7hrDPgBsAgAQAAgK7hrDPgBsAgARAAUKlRP/QAAkAQASAAEKMQeuKwAsAAAAAA==.Elpala:BAAANQAECgQIBAAAAA==.Elpotoco:BAAANQADCgEIAQAAAA==.',
En='Envie:BAABNQAECn8gAAIFAAkKxCK0GQAxAwAFAAkKxCK0GQAxAwAAAA==.',
Er='Eratia:BAAANQADCgIIAgAAAA==.Eredith:BAAANQADCgQIBAAAAA==.Erhas:BAAANQAECgQIBgAAAA==.Erickya:BAABNQAECn8cAAITAAkKrBrDEgDCAgATAAkKrBrDEgDCAgAAAA==.Ervadocè:BAAANQADCgYIDAAAAA==.Ervelino:BAAANQAECgQIEwAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.Espectrudo:BAAANQADCgIIAgAAAA==.',
Eu='Euteinvoco:BAAANQADCggICAABNQAECggIHwALAEMIAA==.',
Ev='Evely:BAAANQAECgUIEQAAAA==.',
Fa='Fabras:BAAANQADCgIIAgAAAA==.Falstro:BAAANQADCgYIBgAAAA==.',
Fe='Felenus:BAAANQAECgUIBgAAAA==.Felguk:BAAANQADCgIJAgAAAA==.Ferdruiid:BAAANQABCgUICgAAAA==.Fermoonie:BAAANQAECgIIBAAAAA==.',
Fi='Firexo:BAAANQADCgEIAQAAAA==.',
Fl='Flemma:BAABNQAECn8bAAMUAAcK2BWpHwDYAQAUAAcK2BWpHwDYAQAVAAMKtAm2HAB9AAAAAA==.Flexer:BAAANQAECgEIAgAAAA==.',
Fo='Fonderus:BAAANQADCgMIBAAAAA==.Foxyroxy:BAAANQAECgUIDwAAAA==.',
Fr='Friodokrl:BAAANQAECgcIEwAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAABNQAECn87AAIEAAkKJxqPVQDVAgAEAAkKJxqPVQDVAgAAAA==.',
Ga='Gafgar:BAAANQAECgcIEAABNQAECggIJAAKAP4YAA==.Gafowi:BAABNQAECn8WAAIWAAUKjBsBFgCXAQAWAAUKjBsBFgCXAQAAAA==.Galduin:BAABNQAECn84AAICAAgK1xbbdgAuAgACAAgK1xbbdgAuAgAAAA==.Galoduro:BAAANQAECgQIBAAAAA==.Garrincha:BAAANQADCgYIBwABNQAECgUIDgADAAAAAA==.Gaunterodim:BAAANQAECggIEwAAAA==.',
Ge='Gentioiroh:BAAANQAECgYICgAAAA==.Gever:BAAANQADCgUIBQAAAA==.',
Gh='Ghopo:BAAANQAECgEIAgABNQAECggIJAAKAP4YAA==.',
Gi='Giradus:BAAANQADCgUIDwAAAA==.',
Gl='Glorcckk:BAAANQADCgUIBgAAAA==.',
Gn='Gnomagga:BAAANQADCgMIAwABNQAECgkJFgAIABIbAA==.',
Gr='Greedom:BAAANQADCgIIAgAAAA==.Grimblade:BAAANQADCgEIAQAAAA==.Grindewald:BAAANQADCgcIBwAAAA==.Grommhell:BAABNQAECn8kAAICAAkKNQ6FgQAUAgACAAkKNQ6FgQAUAgAAAA==.Grím:BAAANQAECgQICgAAAA==.',
Gu='Gudangara:BAAANQAECgEIAQAAAA==.Gugans:BAAANQAECgQIBAAAAA==.Guzinbrs:BAAANQADCgcIDAAAAA==.',
Ha='Haakaí:BAABNQAECn8fAAMCAAgKBBIQhwAGAgACAAgKBBIQhwAGAgAXAAMK3RHUIgCbAAAAAA==.Haandir:BAAANQAECgUIBgAAAA==.Hadassä:BAAANQABCgEIAgAAAA==.Hafessä:BAAANQADCgMIAwAAAA==.Hakuro:BAAANQAECgIIBAAAAA==.Harany:BAAANQAECgIJAgABNQAECgIIBgADAAAAAA==.Havatar:BAAANQAECgIIAgAAAA==.',
He='Healgate:BAAANQABCgIIAgAAAA==.Herablack:BAAANQAECgQIAwAAAA==.',
Hi='Himikonee:BAABNQAECn8WAAIQAAUKIB4fewCkAQAQAAUKIB4fewCkAQAAAA==.',
Ho='Holydread:BAAANQAECgMIAwAAAA==.Horstmeyer:BAAANQADCgIIAgAAAA==.',
Hu='Hulig:BAAANQAECgIIAgABNQAECgQIBQADAAAAAA==.',
['Hø']='Høkulani:BAAANQAECgYIEgAAAA==.',
Ib='Ib:BAAANQADCggICQAAAA==.',
Ig='Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAABNQAECn8qAAIOAAgK6xrBYgBuAgAOAAgK6xrBYgBuAgAAAA==.Iksivokilirt:BAAANQADCgIJAgAAAA==.Ikslawok:BAAANQADCggIEQAAAA==.',
Il='Ileria:BAAANQADCggICgAAAA==.Illusionarc:BAAANQAECgYIEAABNQAECgkKMAAGAEwgAA==.',
In='Incognita:BAABNQAECn8XAAIRAAgKtA+eJwDqAQARAAgKtA+eJwDqAQAAAA==.Infernús:BAAANQADCgYIBgABNQAECggIFQAGAGUXAA==.Interst:BAAANQADCgcIBwAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQAECgEIAQAAAA==.',
Is='Iscalio:BAABNQAECn8cAAMYAAcKABd4HQCvAQAYAAcKABd4HQCvAQAWAAEKAADlPgA5AAAAAA==.',
It='Itadory:BAAANQADCgEIAQAAAA==.Itatchii:BAAANQAECgQIEQAAAA==.',
Iu='Iuuh:BAABNQAECn8qAAMZAAgK0xrvNwCCAgAZAAgK0xrvNwCCAgAOAAMKtBOCNwHAAAAAAA==.',
Ja='Jackdawnsong:BAAANQADCgQICAAAAA==.Jahuun:BAABNQAECn8pAAIOAAkK2wzJmwDmAQAOAAkK2wzJmwDmAQAAAA==.Jaihro:BAAANQADCgYIBgAAAA==.',
Je='Jefflich:BAAANQAECgMIBgAAAA==.Jefãoo:BAABNQAECn8hAAMOAAgKfBKujwABAgAOAAgKfBKujwABAgAIAAMKuQVNVgCDAAAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQADCggIDgAAAA==.Justimonk:BAAANQADCgEIAwAAAA==.',
Ka='Kaelyrah:BAAANQADCgQIBAAAAA==.Kaldonios:BAAANQADCgYICQAAAA==.Kalipho:BAAANQADCgUIBQAAAA==.Karamael:BAAANQAECgQIBAAAAA==.Kardibito:BAAANQAECgUIBgAAAA==.Karmysh:BAAANQAECgEIAQAAAA==.Kazuopala:BAAANQAECgQICwAAAA==.',
Ke='Kentàk:BAAANQAECgIIAgAAAA==.',
Kh='Khoj:BAABNQAECn8cAAMKAAgKvxJyUACwAQAKAAgKvxJyUACwAQAaAAEKAABc/AAYAAAAAA==.Kholckk:BAAANQADCgUICgAAAA==.',
Ki='Killerdek:BAAANQAECgEIAQAAAA==.Killersall:BAABNQAECn8iAAIbAAkKpQosbwDPAQAbAAkKpQosbwDPAQAAAA==.',
Kl='Kluzlocak:BAAANQAECgQIDQAAAA==.',
Ko='Kore:BAAANQAECgEIAQABNQAECgcIIQAYANciAA==.',
Kr='Krosn:BAAANQAECgEIAgAAAA==.',
Ku='Kutirenzo:BAAANQADCgcIDwAAAA==.',
Kx='Kxxtgodx:BAAANQADCgcIBwAAAA==.',
Ky='Kysed:BAAANQADCgYICQAAAA==.Kyubi:BAAANQAECgQICQAAAA==.',
La='Lafiel:BAAANQAECgQIBAAAAA==.Lagertha:BAAANQAECgMIBQAAAA==.Lahllis:BAAANQAECgIJAgAAAA==.Lahnara:BAAANQADCggIDQAAAA==.Lanadelrei:BAAANQADCgIIAgAAAA==.Lanmo:BAABNQAECn8hAAIYAAcK1yK3CwCqAgAYAAcK1yK3CwCqAgAAAA==.Larrygou:BAAANQADCggICAAAAA==.Laurea:BAABNQAECn8nAAIQAAkK5SSeAgDBAwAQAAkK5SSeAgDBAwAAAA==.',
Le='Ledor:BAAANQAECgUICAAAAA==.Lendarion:BAAANQAECgQJDgAAAA==.Leopvazi:BAAANQADCgIIAgAAAA==.Leozadock:BAAANQAECgUICAAAAA==.Leozadok:BAAANQADCgQIBAAAAA==.Lewandosck:BAAANQAECgQICQAAAA==.',
Li='Liana:BAAANQAECgQICwABNQAECgkJJwAQAOUkAA==.Lichtbaum:BAABNQAECn8nAAMcAAgKUSI7DAAFAwAcAAgKUSI7DAAFAwAdAAIKBxBumwBnAAAAAA==.Liifecomm:BAABNQAECn8oAAIQAAkKpCARDwBLAwAQAAkKpCARDwBLAwAAAA==.Lipaodrk:BAABNQAECn80AAIZAAkKrRs0KQDBAgAZAAkKrRs0KQDBAgAAAA==.Lirobitt:BAAANQADCgMIAwAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lolipop:BAAANQABCgYICgAAAA==.Lordpain:BAABNQAECn8kAAQKAAgK/hj8LQBaAgAKAAgK/hj8LQBaAgALAAMKiQjsiQCCAAAaAAIKFwbbygBTAAAAAA==.Lorrd:BAAANQAECgIIAgAAAA==.Lortherti:BAAANQADCgQIBgAAAA==.Louisenacioo:BAABNQAECn8dAAIUAAcKIBGxJACZAQAUAAcKIBGxJACZAQAAAA==.',
Lu='Luanacarniça:BAAANQADCgIIAgAAAA==.Luccablack:BAAANQAECgYICAAAAA==.Luccagelido:BAAANQAECgIIAgAAAA==.Luidar:BAAANQAECgcIDQAAAA==.Lukaslions:BAAANQAECgUIBgAAAA==.Luministar:BAAANQAECggIBwAAAA==.Luphoe:BAAANQAECgEIAwAAAA==.',
Ly='Lyandriis:BAAANQADCggICAAAAA==.',
['Lé']='Léèo:BAAANQADCgYIBgABNQAFFAUKBwARAOsQAA==.',
Ma='Madushi:BAABNQAECn8jAAIOAAkKBB1YKQAfAwAOAAkKBB1YKQAfAwAAAA==.Madzerø:BAAANQAECgUICAAAAA==.Magatas:BAAANQADCgQIBAAAAA==.Maguul:BAAANQAECgUIBQAAAA==.Malandrvs:BAAANQAECgYIDgAAAA==.Maldiçoadora:BAABNQAECn8nAAIHAAkK9x7NJADuAgAHAAkK9x7NJADuAgAAAA==.Malfurionsf:BAAANQAECgQIBAABNQAECgcIHgAKANEcAA==.Malfuysera:BAAANQAECgQICAABNQAECgcIHgAKANEcAA==.Mangudah:BAAANQAECgcIDwABNQAECggIHAAZAMkkAA==.Mannaton:BAABNQAECn8cAAQZAAgKySTPDgBTAwAZAAgKySTPDgBTAwAOAAMKpRfgLgHNAAAIAAIKECAxTAC0AAAAAA==.Manzagon:BAAANQAECgYICAABNQAECggIHAAZAMkkAA==.Marcijo:BAAANQABCgIIAgAAAA==.Maruh:BAAANQAECgUIBwAAAA==.Marúh:BAABNQAECn8oAAMJAAkK7B6FGgAEAwAJAAkK7B6FGgAEAwAbAAIKhxMVDAFsAAAAAA==.Mayarabr:BAAANQABCgYICQAAAA==.Maølayking:BAACNQAFFH8NAAMaAAMKPia+DgAcAQAaAAMKSCW+DgAcAQAKAAIKziW5GQDKAAA1AAQKfzcAAwoACQq2JlQBAOIDAAoACQq2JlQBAOIDABoAAwrBCxObAMUAAAAA.',
Mc='Mclovingo:BAAANQADCgUIBAAAAA==.',
Me='Mekihlvshtak:BAAANQAECgQIBAABNQAECgUIBQADAAAAAA==.Mendingu:BAABNQAECn8eAAICAAcK5Rs4dQAyAgACAAcK5Rs4dQAyAgAAAA==.Mercenarybr:BAABNQAECn8oAAIOAAcKdQsj0QBzAQAOAAcKdQsj0QBzAQAAAA==.',
Mi='Midrão:BAAANQADCgUIBQAAAA==.Mikasaackerr:BAABNQAECn8dAAIFAAcKEBCxoQC/AQAFAAcKEBCxoQC/AQAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgYICgAAAA==.Miranda:BAAANQAECgQICAABNQAECgkJJwAQAOUkAA==.',
Mm='Mmenov:BAAANQADCgQIBQAAAA==.Mmenovw:BAAANQADCgEIAQAAAA==.',
Mo='Molior:BAAANQADCgYIBwAAAA==.Momongadk:BAABNQAECn8gAAIKAAgKPxLOUACvAQAKAAgKPxLOUACvAQAAAA==.Monkeydking:BAAANQAECgYICgAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moonluter:BAAANQAECgIJAgAAAA==.Mordekais:BAAANQAECgYICwAAAA==.Morikenshin:BAAANQADCggICwAAAA==.Morinami:BAAANQABCgUJBwAAAA==.Moriyama:BAAANQAECgUIDQAAAA==.Morphizs:BAABNQAECn8YAAMbAAgKghvaOQCMAgAbAAgKghvaOQCMAgAJAAMKww8a4QCjAAABNQAECggIHAAZAMkkAA==.Morphoss:BAAANQAECgUIBgABNQAECggIHAAZAMkkAA==.Morsa:BAAANQADCggIEAAAAA==.Mortesan:BAAANQAECgIIAgABNQAECgQICQADAAAAAA==.',
My='Mystian:BAAANQAECgEIAQAAAA==.',
['Mä']='Mäven:BAAANQAECggIEwABNQAFFAIIBQAYAMwXAA==.',
['Må']='Måximus:BAAANQAECgcIEgAAAA==.',
Na='Naeryndam:BAAANQADCgYIEQAAAA==.Nagojão:BAAANQAECgEIAQAAAA==.Natcmd:BAAANQADCgUIBQAAAA==.Naturezo:BAAANQAECgIIBgAAAA==.Navira:BAAANQADCggICAAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Nedy:BAAANQADCgMIAwAAAA==.Negblack:BAAANQAECgcIDAAAAA==.Netherbane:BAABNQAECn8ZAAICAAgKbA6foQDEAQACAAgKbA6foQDEAQAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgUIBgAAAA==.',
Ni='Nieves:BAAANQADCgEIAQAAAA==.Nightmære:BAAANQAECgQICAAAAA==.Ninfador:BAAANQADCgUIBQAAAA==.',
['Nø']='Nøsferatu:BAAANQAECgQIBwAAAA==.',
Oa='Oakshlar:BAAANQAECgQIDwAAAA==.Oalxorozco:BAAANQADCgIIAgAAAA==.',
Os='Osmotios:BAAANQAECgQIBgAAAA==.',
Ot='Otton:BAAANQAECgUICwAAAA==.',
Pa='Paidesanto:BAAANQAECgUIBQAAAA==.Paladinokun:BAAANQAECgQICQAAAA==.Palamino:BAAANQADCgMIAwAAAA==.Pandadruid:BAAANQADCgYICgAAAA==.Pantanegro:BAAANQADCgUICAAAAA==.',
Pe='Pedrö:BAABNQAECn8YAAMeAAUKhx3UNwCAAQAeAAUKhx3UNwCAAQAGAAUK9ReAUwA9AQAAAA==.Pepeti:BAAANQADCggICQAAAA==.Pepetí:BAAANQADCgMIAwAAAA==.Peçanhaa:BAAANQAECgEIAQAAAA==.',
Pi='Pinkfloid:BAAANQADCgcICAAAAA==.',
Pl='Placides:BAAANQADCgUIDAAAAA==.Playsson:BAABNQAECn8oAAICAAkKthmTPQDPAgACAAkKthmTPQDPAgAAAA==.',
Pq='Pqchoras:BAABNQAECn8bAAIKAAgKnh97IQCnAgAKAAgKnh97IQCnAgAAAA==.',
Pr='Pravios:BAAANQAECgUICAAAAA==.Proctan:BAAANQADCgYIBgAAAA==.',
Pu='Puherito:BAAANQADCgYIBgAAAA==.Purehito:BAAANQAECgYIDQAAAA==.Purifc:BAAANQAECgQIBAAAAA==.',
Ra='Radathewhite:BAAANQAECgYIDAAAAA==.Ravenblak:BAAANQADCgQIBAAAAA==.Raÿne:BAAANQAECgMIBAAAAA==.',
Rb='Rbarroco:BAAANQAECgQIBAABNQAECgcIHgACAOUbAA==.',
Re='Reanasming:BAAANQADCgEIAQAAAA==.Reigeladinho:BAAANQADCggIFAAAAA==.',
Ro='Robadoom:BAABNQAECn8cAAIeAAgKpgzPLwC/AQAeAAgKpgzPLwC/AQAAAA==.Robeerth:BAABNQAECn8YAAIFAAkKmBxhIQAQAwAFAAkKmBxhIQAQAwAAAA==.Roderic:BAAANQAECgEIAQABNQAECgcIHgACAOUbAA==.Rowane:BAAANQADCgQIBAAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQADCgcIGQAAAA==.',
['Rä']='Räghnar:BAAANQAECgQIBQAAAA==.',
Sa='Saanemi:BAAANQADCgIIAgAAAA==.Safiralc:BAAANQADCgEIAQAAAA==.Salaciel:BAAANQAECgUIEQAAAA==.Sarabifinho:BAAANQADCgQIBAAAAA==.Sardron:BAAANQADCgMIAwAAAA==.Saydrom:BAAANQADCgYJBgAAAA==.Sayur:BAAANQADCgcIDgAAAA==.',
Sc='Scalyroxy:BAAANQADCgUIBQAAAA==.Scanorr:BAAANQAECgYIDAAAAA==.Scanvyl:BAAANQAECgQICQAAAA==.',
Se='Selver:BAAANQADCgIIAwABNQAFFAcIFwARABESAA==.Sepp:BAAANQADCgIIAgAAAA==.',
Sh='Shaladrasil:BAAANQADCgEIAwAAAA==.Shamjj:BAAANQADCgEIAQAAAA==.Shieldhonor:BAAANQADCggIEgAAAA==.Shisuui:BAABNQAECn8bAAIFAAgKLhizUgB2AgAFAAgKLhizUgB2AgAAAA==.',
Si='Silvanna:BAAANQAECgIIBwAAAA==.Silvao:BAAANQAECgEIAQAAAA==.Sinkra:BAAANQADCgMIBAAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQAECgQIBwAAAA==.',
Sk='Skunkbr:BAAANQADCgYIBgAAAA==.',
Sl='Sliiluuvrrp:BAAANQAECgQIDAAAAA==.Slyfer:BAAANQADCgIIBQAAAA==.',
So='Sonofroar:BAAANQAECgUJBgAAAA==.Soray:BAAANQAECgIIAwAAAA==.Sorim:BAAANQAECgUIEQAAAA==.',
Sp='Spãrta:BAAANQAECgMIAwAAAA==.',
St='Staffkiller:BAAANQAECgEIAwAAAA==.Strygah:BAAANQAECgMIBQAAAA==.Stx:BAAANQAECgQIBAAAAA==.',
Su='Sunthalas:BAAANQAECgUIBQAAAA==.Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgQJCAABNQAECgcIIQAYANciAA==.',
Ta='Taillys:BAAANQADCgcICAAAAA==.Talanis:BAAANQAECgIIAgABNQAECgkJJwAQAOUkAA==.Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQAECgEIAgAAAA==.Tarfonir:BAABNQAECn8YAAMcAAcKmBOcLgCiAQAcAAcKmBOcLgCiAQAdAAEKAAB5xQAaAAAAAA==.Tarzønys:BAAANQADCgYIBgAAAA==.',
Te='Ted:BAAANQAECgYICwAAAA==.',
Th='Thanorak:BAAANQADCgIJAgAAAA==.Thejokker:BAAANQADCgcICAAAAA==.Themooster:BAABNQAECn8uAAIIAAkKwBpvDwCjAgAIAAkKwBpvDwCjAgAAAA==.Thepickles:BAAANQADCgYIGQAAAA==.Thepunk:BAAANQAECgIIAgAAAA==.Thiyva:BAAANQADCgIIAgAAAA==.Thomzïn:BAAANQADCgcIDwAAAA==.Thormento:BAAANQAECgYICAAAAA==.Throosh:BAAANQADCggIGQAAAA==.Thundertroll:BAAANQADCgEIAQAAAA==.',
Ti='Timma:BAAANQAECgMIAwAAAA==.Tiriricao:BAAANQAECgUIAwAAAA==.Titanicos:BAAANQAECgcIEQAAAA==.Tiãocarneiro:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAABNQAECn8pAAQLAAkKnBLMQgCzAQALAAgKjg/MQgCzAQAKAAcKeROwYgBkAQAaAAIKgQYTzgBNAAAAAA==.Torem:BAAANQADCgQICAAAAA==.',
Tr='Trelhunter:BAAANQAECgEIAQAAAA==.Trembolono:BAAANQABCgIIAgAAAA==.Trévor:BAABNQAECn8YAAIOAAgKRgk9ygCBAQAOAAgKRgk9ygCBAQAAAA==.',
Tu='Tubaras:BAAANQADCgEIAQAAAA==.Tututzz:BAAANQADCgMIAwAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYICwAAAA==.',
Ug='Ugugugana:BAAANQAECgUIDQAAAA==.',
Un='Unitt:BAAANQADCgMIAwAAAA==.Unseendeath:BAAANQAECgYICQABNQAECgkJIwAOAAQdAA==.',
Va='Valmila:BAAANQAECgQIBgAAAA==.Vandlesh:BAAANQADCgIIAgAAAA==.Vandlock:BAAANQABCgEIAQAAAA==.Vardha:BAAANQADCgUIBQAAAA==.Varka:BAAANQADCgIIAgAAAA==.',
Ve='Velkharun:BAABNQAECn8aAAQMAAgK4QzLDgANAgAMAAgKmgzLDgANAgAHAAUK6wk36gDvAAAfAAIKAAAwIABzAAABNQAECgkJGAAFAJgcAA==.Velmora:BAAANQADCggIEAAAAA==.',
Vh='Vhaeraun:BAAANQAECgEIAQAAAA==.',
Vi='Viseryss:BAAANQADCgIIAgAAAA==.Vivifirex:BAAANQADCgEIAQAAAA==.',
Vo='Voidbrew:BAAANQAECgUICQAAAA==.',
Vu='Vunks:BAAANQAECgMIAwABNQAECgcIHQAEAHERAA==.',
Vy='Vylkk:BAAANQADCggIDwAAAA==.',
['Ví']='Vídarr:BAAANQADCgUIBQAAAA==.',
['Vò']='Vòxs:BAAANQAECgUIDgAAAA==.',
['Vó']='Vóxs:BAAANQAECgQIBAAAAA==.',
['Vö']='Völpina:BAAANQADCggICAAAAA==.',
Wa='Wako:BAABNQAECn8mAAIOAAgKPxeoeAA3AgAOAAgKPxeoeAA3AgAAAA==.Warlôck:BAAANQAECgIIAgAAAA==.Watdafoxsay:BAAANQAECgMIBgAAAA==.',
Wh='Whitersoul:BAABNQAECn9rAAMPAAkKsSGLAQB2AwAPAAkKsSGLAQB2AwAEAAMK2gfAmAGMAAAAAA==.',
Wi='Wiitchkiing:BAAANQADCggIEgAAAA==.Willtratadoo:BAAANQADCgcICgAAAA==.Wiserys:BAABNQAECn8mAAQfAAkKTxgkCwC6AQAHAAgKXxOYdgD6AQAfAAYKsRYkCwC6AQAMAAMKeg5ySQCiAAAAAA==.',
Wm='Wmarcão:BAAANQAECgUIDQAAAA==.',
Wo='Wolfnwar:BAABNQAECn8yAAMFAAkKNhP0VQBtAgAFAAkKNhP0VQBtAgAgAAIKaQPfegBSAAAAAA==.',
Xe='Xenomorpho:BAAANQADCgcICAAAAA==.Xexnest:BAAANQADCgQIBAAAAA==.Xexnetw:BAAANQAECgIIBAAAAA==.Xexnew:BAABNQAECn8gAAMKAAkKOh6VJACTAgAKAAkKOh6VJACTAgALAAEKBgbCsAArAAAAAA==.',
Xi='Xistaminosas:BAAANQABCgUIBgAAAA==.Xiuying:BAAANQAECgUIBQAAAA==.',
Xl='Xladymaladax:BAAANQADCgEJAQAAAA==.',
Xm='Xmari:BAABNQAECn8rAAIFAAkKQQUzqACxAQAFAAkKQQUzqACxAQAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xoliwar:BAAANQAECgUIBQAAAA==.Xots:BAAANQADCgIIAgABNQAECgcIHQAEAHERAA==.',
Xt='Xtremetanke:BAAANQAECgEJAQAAAA==.',
Xx='Xxcantsidex:BAAANQAECgUIBgAAAA==.',
['Xê']='Xêxnew:BAAANQADCgcIBQAAAA==.',
Ya='Yangyung:BAAANQAECgQIBQABNQAECggIJAAKAP4YAA==.Yannadcg:BAAANQAECgcIEAAAAA==.',
Yc='Ycantsideyx:BAAANQADCgYICgAAAA==.',
Ym='Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yormogander:BAAANQAECgEIAQABNQAECggIOAACANcWAA==.Yorshka:BAAANQADCgYIBwAAAA==.',
Yr='Yrelistrasza:BAABNQAECn8oAAQUAAgKUQq2JQCNAQAUAAgKUQq2JQCNAQAhAAIKrADEQgAhAAAVAAEKAAAgKAAeAAAAAA==.',
Yu='Yunat:BAAANQADCgYIBgAAAA==.',
Za='Zapdos:BAAANQADCgIIAgAAAA==.Zarolho:BAAANQADCgYICQAAAA==.',
Ze='Zeddh:BAAANQAECgQIBAABNQAECgkJKwACAIIXAA==.Zenaq:BAAANQAECgEIAgAAAA==.Zerdrax:BAABNQAECn8cAAIEAAcKwxO34QDCAQAEAAcKwxO34QDCAQAAAA==.',
Zi='Ziikiipala:BAAANQADCgIIAgAAAA==.',
['Ál']='Álucard:BAAANQAECgUIDgAAAA==.',
['Éy']='Éyga:BAAANQADCgUIEAAAAA==.',
['Ðw']='Ðwons:BAAANQADCgEIAQAAAA==.',
['Ör']='Örgrekai:BAAANQADCggIEAAAAA==.',
['Öx']='Öx:BAABNQAECn8gAAMfAAkKTxC+BwAaAgAfAAgKlBG+BwAaAgAHAAMK8ghAFgGUAAAAAA==.',
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
