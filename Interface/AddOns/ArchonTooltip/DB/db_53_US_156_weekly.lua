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

local lookup = {'Hunter-BeastMastery','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','Paladin-Retribution','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','Priest-Discipline','Druid-Balance','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Rogue-Subtlety','Druid-Restoration','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Monk-Mistweaver','Druid-Guardian','Hunter-Survival','Warlock-Affliction','Druid-Feral','Warrior-Fury','Rogue-Outlaw','Mage-Frost','Hunter-Marksmanship','Warrior-Arms',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abàddón:BAAANQADCgYIDAAAAA==.',
Ac='Acidburn:BAAANQADCgYICgAAAA==.',
Ae='Aelin:BAAANQAECgEIAQAAAA==.',
Al='Alluna:BAAANQAECgEIAQAAAA==.Alorillan:BAAANQAECgQIBgAAAA==.Altabrew:BAAANQADCgMIAwAAAA==.Altair:BAAANQAECgYIDwAAAA==.',
An='Anker:BAAANQAECgEIAgABNQAFFAQIBQABAFQIAA==.Anomalien:BAAANQAECgMIBAAAAA==.',
Ap='Apocalyspe:BAABNQAECn8iAAIBAAoKyg4UhwCOAQABAAoKyg4UhwCOAQAAAA==.Appless:BAABNQAECn9SAAMCAAoKURm0DwBLAgACAAoKURm0DwBLAgADAAoK5hrjPAAyAgAAAA==.',
Ar='Aridella:BAAANQAECgYIEAAAAA==.',
Au='Aurorá:BAAANQADCggIEAAAAA==.',
Az='Azusie:BAABNQAECn8+AAIEAAoKIBLaDQAjAgAEAAoKIBLaDQAjAgAAAA==.',
Ba='Bablepopye:BAAANQAECgMIAwAAAA==.Baddate:BAAANQAECgYIEAAAAA==.Baddragøn:BAABNQAECn8dAAMFAAkKNRmOFgBOAgAFAAkKNRmOFgBOAgAGAAIKywLkNwBPAAAAAA==.Balthaas:BAABNQAECn8aAAMHAAoKxQzDLgBoAQAHAAoKxQzDLgBoAQAIAAEKkAcftAEuAAAAAA==.Bangen:BAAANQAECgUIBgAAAA==.Baulters:BAAANQADCgYIBgAAAA==.Baylor:BAAANQADCgUIBQAAAA==.',
Bc='Bckstabber:BAAANQADCgQIBAAAAA==.',
Be='Beenn:BAAANQADCgcJDAAAAA==.Belael:BAAANQADCgcIBwAAAA==.Benchpress:BAAANQAECgEIAQAAAA==.Benrent:BAAANQADCgEIAQABNQADCgcJDAAJAAAAAA==.',
Bi='Biinks:BAAANQADCggIEwAAAA==.Biinkss:BAAANQAECgEIAQAAAA==.Billywitchdr:BAABNQAECn80AAQKAAoKghjNLgAKAgAKAAoKghjNLgAKAgAEAAQKzgSjJgC7AAALAAEK6QwNHQEzAAAAAA==.Bisharp:BAAANQADCggICAABNQAECgoKFQAMAPkXAA==.',
Bl='Blazingelf:BAAANQADCgMIAwAAAA==.Blindedbý:BAAANQABCgYICAAAAA==.Bluetoykawi:BAABNQAECn9KAAINAAoKXBX1IgAmAgANAAoKXBX1IgAmAgAAAA==.',
Bo='Boltspark:BAAANQADCgYIBgAAAA==.Bonedelivery:BAAANQAECgEIAgAAAA==.',
Br='Breloom:BAAANQAECgYIBgABNQAECgoKFQAMAPkXAA==.',
Bu='Bulkathos:BAAANQAECgEIAwABNQAECgoKJAACAEIJAA==.Bulliedgair:BAAANQAECgQIBQABNQAECgcIEQAJAAAAAA==.',
['Bé']='Béorñ:BAAANQAECggIEQAAAA==.',
Ca='Cariandria:BAAANQADCgYICwAAAA==.',
Ch='Charita:BAECNQAFFH8GAAIOAAQKsgS+GwB+AAAOAAQKsgS+GwB+AAA1AAQKfxwAAg4ACQodF/w2AC4CAA4ACQodF/w2AC4CAAAA.Charming:BAEBNQAECn8ZAAIPAAoKkhwhCwBbAgAPAAoKkhwhCwBbAgABNQAFFAQIBgAOALIEAA==.',
Cl='Clanker:BAAANQAECgQIBAAAAA==.Clark:BAAANQADCgEIAQAAAA==.Clouds:BAAANQAECgEIAQABNQAECggIFQAQALERAA==.',
Co='Coffeecat:BAAANQADCgYIGAABNQAECgYIDAAJAAAAAA==.Contrlurself:BAAANQADCgQIBAABNQAECgoKLwARAIMSAA==.Cowret:BAABNQAECn81AAISAAoKxiPBBQCfAwASAAoKxiPBBQCfAwAAAA==.',
Cr='Crowleyy:BAAANQADCgUIBQAAAA==.',
Da='Dademurphy:BAAANQADCgIIAgAAAA==.Darc:BAAANQAECgEICQAAAA==.Darkfoxdemon:BAABNQAECn8iAAQTAAoK6hSXCwAVAgATAAgKnxiXCwAVAgAUAAgKpgw+WQAiAQAVAAYKXwWbSwD8AAAAAA==.Darkfoxgrime:BAAANQAECgcICgABNQAECgoKIgATAOoUAA==.Darkjager:BAAANQADCgcIBwAAAA==.Darkstaff:BAAANQADCgMIAwAAAA==.Darkways:BAAANQADCgYIBgAAAA==.Darlah:BAAANQAECgcIDAAAAA==.Dayyva:BAAANQAECgQIEgAAAA==.',
De='Deadcobra:BAAANQADCgMIBQAAAA==.Deangilberry:BAAANQAECgEIAgAAAA==.Deathbyelf:BAAANQADCgcIBwAAAA==.Delindeyn:BAAANQAECgQIBgAAAA==.Deltria:BAAANQAECgQIBgAAAA==.Demonrot:BAAANQAECggICAAAAA==.Devils:BAAANQADCgMIAwAAAA==.Deviltank:BAAANQADCgQIBAAAAA==.',
Di='Diaboliq:BAABNQAECn8UAAIOAAUKvgtVXwC6AAAOAAUKvgtVXwC6AAAAAA==.Digmyearth:BAAANQADCgYIBgAAAA==.Dilea:BAAANQAECgEIAQAAAA==.',
Dk='Dkon:BAABNQAECn8hAAMOAAgKlhqpQgDxAQAOAAgKZhepQgDxAQAWAAYKWxZVfAArAQAAAA==.',
Do='Doppler:BAABNQAECn8cAAIMAAkKYw+Y8QCoAQAMAAkKYw+Y8QCoAQAAAA==.',
Dr='Dracomyst:BAAANQADCggIAgAAAA==.Driver:BAEANQAECggICgAAAA==.Drruz:BAAANQADCggIKAAAAA==.',
Du='Dumbledorr:BAAANQAECgIIAwAAAQ==.Durzoe:BAABNQAECn8YAAIXAAgKWhEiHwDXAQAXAAgKWhEiHwDXAQAAAA==.',
Dv='Dvsmage:BAAANQADCgcIDQABNQAECgEIAQAJAAAAAA==.',
Dw='Dwod:BAABNQAECn8rAAMNAAkKiRQNQADIAQANAAkKiRQNQADIAQAOAAQKLgdIoQCUAAAAAA==.',
['Dí']='Díscø:BAEBNQAECn8aAAICAAkKjxjyGQB+AgACAAkKjxjyGQB+AgAAAA==.',
Ed='Edrian:BAAANQADCgYIBgAAAA==.',
Er='Ereithis:BAAANQAECgEIAQABNQAECgoKLwAYAF4JAA==.Errita:BAAANQAECgcIDAAAAA==.Ershulie:BAAANQABCggIJwAAAA==.',
Ev='Evilcoffee:BAAANQADCgcIDgABNQAECgYIDAAJAAAAAA==.',
Ew='Ewt:BAABNQAECn8tAAIZAAoKKRZ6EgB6AQAZAAoKKRZ6EgB6AQAAAA==.',
Ez='Ezili:BAAANQAECgEIAQAAAA==.',
Fa='Fastnine:BAABNQAECn8VAAIMAAoK+RdOQwD9AgAMAAoK+RdOQwD9AgAAAA==.',
Fe='Felhound:BAAANQAECgQIBgAAAA==.Felussi:BAABNQAECn8cAAMaAAgK5xHlfgDpAQAaAAgK5xHlfgDpAQAbAAEKtRRGcQA+AAAAAA==.',
Fi='Finnster:BAABNQAECn9EAAIBAAoKmgyCWwD6AQABAAoKmgyCWwD6AQAAAA==.Fionna:BAAANQADCgQIBAAAAA==.Firereina:BAAANQADCggICAABNQADCggIIQAJAAAAAA==.',
Fl='Flameon:BAAANQABCgcICgAAAA==.Flarixi:BAAANQADCgcICgAAAA==.Fleurminator:BAAANQAECgYIDQAAAA==.Flipmaster:BAAANQADCgEIAQAAAA==.',
Fr='Fractor:BAAANQADCgYICwAAAA==.Friedchickn:BAAANQAECgcIAQAAAA==.Frieia:BAABNQAECn8XAAMYAAYKAQNoUwCWAAAYAAYKAQNoUwCWAAARAAEKAAB7nwAAAAAAAA==.Frostface:BAAANQADCgcICwAAAA==.Frozenjade:BAAANQADCgIIAwAAAA==.',
Fu='Fubuki:BAACNQAFFH8XAAMcAAYKsBLhCgAOAQAcAAUKsBLhCgAOAQAPAAUKtAAmBwDUAAA1AAQKfzsAAxwACgpkIXMQAOACABwACgpkIXMQAOACAA8AAwr7Br8pAHUAAAAA.Fupasniffer:BAAANQAECgIIAgAAAA==.',
Ga='Galahad:BAAANQAECggICAAAAA==.Galapriest:BAAANQAECgEIAQAAAA==.Galarína:BAABNQAECn8xAAMdAAoK4x7SCQCcAgAdAAoK4x7SCQCcAgAcAAgK2g5FJgBQAQAAAA==.Gallitha:BAAANQADCgUIBQAAAA==.Gamewarden:BAAANQADCggIDgABNQAECgkJMAADAHYcAA==.Gandora:BAABNQAECn8sAAQWAAoKlw2hKwB1AQAWAAoKlw2hKwB1AQANAAMKpwY6kAB4AAAOAAEKAABpzAAxAAAAAA==.Gauge:BAAANQAECgcIDwABNQAECggIDAAJAAAAAA==.',
Ge='Getoffme:BAAANQAECgUICgAAAA==.',
Gk='Gkmc:BAACNQAFFH8FAAIWAAMKUCCiDgAhAQAWAAMKUCCiDgAhAQA1AAQKfx8AAhYACQrUJA4IAOwCABYACQrUJA4IAOwCAAE1AAUUCQkTAAwAAR0A.',
Go='Gobbomode:BAAANQADCgYIBgAAAA==.Gorbino:BAABNQAECn82AAMHAAoKjCTFAgCcAwAHAAoKjCTFAgCcAwAIAAEKKheZcAFFAAAAAA==.',
Gr='Greasemunkey:BAAANQAECgUIDwAAAA==.Gretchaen:BAABNQAECn8XAAIeAAUKDhFSOQDLAAAeAAUKDhFSOQDLAAAAAA==.Griiv:BAABNQAECn9CAAIIAAkKYCYLGABkAwAIAAkKYCYLGABkAwABNQAECgoKKgAEAH8kAA==.Grislydemon:BAAANQAECgEIAQAAAA==.Grislydoom:BAAANQAECgEIAQAAAA==.Grislyshock:BAABNQAECn8tAAIEAAoKVhv+DACeAgAEAAoKVhv+DACeAgAAAA==.',
Ha='Haendor:BAAANQADCgMIAwAAAA==.Hairymartini:BAAANQAECgQICAABNQAECgoKNwAKALogAA==.Hakunamatata:BAAANQAECgEIAgAAAA==.Hamburger:BAABNQAECn8VAAICAAgK5Q5XIQBlAQACAAgK5Q5XIQBlAQAAAA==.Hammerhard:BAAANQAECgMIAwAAAA==.Harcones:BAAANQADCgMJAwAAAA==.',
He='Heights:BAAANQADCgMIAwABNQAECgQIBwAJAAAAAA==.Heliosan:BAABNQAECn8mAAIDAAgKNxhaYwCeAQADAAgKNxhaYwCeAQAAAA==.Hellelements:BAAANQAECggIDAAAAA==.Hemoblast:BAAANQAECgEIAQAAAA==.Hemolight:BAAANQAECgEIAgAAAA==.',
Ho='Hojiitaa:BAAANQADCgUIBQAAAA==.Holybean:BAAANQADCggIGwABNQAECgEIAQAJAAAAAA==.',
Hr='Hrshoo:BAAANQAFFAEIAQAAAA==.',
['Hä']='Hädês:BAAANQAECgQIBQAAAA==.',
Is='Isaack:BAAANQADCgMIAwAAAA==.',
Je='Jeannaah:BAAANQAECgYICQABNQAECgUIBgAJAAAAAA==.Jekyl:BAAANQADCgMIAwAAAA==.Jekyll:BAAANQAECgEIAQAAAA==.',
Jh='Jharia:BAAANQADCgYIBgAAAA==.',
Jo='Jodiedawn:BAAANQAECgQIBwAAAA==.',
Ju='Judgment:BAAANQABCgEJAQAAAA==.',
['Já']='Jáckyboy:BAABNQAECn9DAAMYAAoK2xxQEwB8AgAYAAoK2xxQEwB8AgARAAoK9xoXJwCwAQAAAA==.',
Ka='Kalestra:BAABNQAECn8wAAMRAAoKThsyFwBIAgARAAoKThsyFwBIAgAeAAcK1wjPMQAQAQAAAA==.Kalithos:BAAANQAECgQIBQAAAA==.Kayelalynn:BAABNQAECn8vAAIRAAoKgxIuKACoAQARAAoKgxIuKACoAQAAAA==.Kaymoo:BAAANQAECgEIAgAAAA==.',
Kd='Kd:BAAANQAECgEIAQAAAA==.',
Ke='Keeghor:BAABNQAECn8qAAIEAAoKfyT5AgB0AwAEAAoKfyT5AgB0AwAAAA==.Kelana:BAAANQAECgQIBQAAAA==.Kendô:BAAANQADCgYIBwABNQAECggIHgAHAIoMAA==.Keyahi:BAAANQAFFAEIAQABNQAECgEIAgAJAAAAAA==.',
Kh='Khaean:BAABNQAECn9BAAIfAAkKEx/FAgCKAgAfAAkKEx/FAgCKAgAAAA==.',
Ki='Kickandpunch:BAAANQAECgcIEwAAAA==.Kiilan:BAAANQADCgEIAQAAAA==.Kilan:BAABNQAECn8YAAIIAAcK2Q9A2wAPAQAIAAcK2Q9A2wAPAQAAAA==.Kimuraakid:BAAANQAECgQIBwAAAA==.',
Ko='Kocaman:BAAANQADCgIIAgAAAA==.Konite:BAAANQABCgIIAgAAAA==.Korladin:BAAANQADCgYICQAAAA==.',
Kr='Krutree:BAAANQAECgQIBgAAAA==.',
Ku='Kungfubean:BAAANQADCgcIBwABNQAECgEIAQAJAAAAAA==.Kuromu:BAAANQADCgMIAwAAAA==.Kutbrezbek:BAAANQAECgEIAQAAAA==.',
Ky='Kyleata:BAABNQAECn9HAAIBAAoKghsONwDFAgABAAoKghsONwDFAgAAAA==.Kylz:BAAANQABCggICQAAAA==.Kyokin:BAACNQAFFH8GAAIIAAMKFh0AGwCqAAAIAAMKFh0AGwCqAAA1AAQKfz8AAwgACgooHfdLADcCAAgACgooHfdLADcCAAcAAQpOCJZ5ACMAAAAA.Kyryn:BAAANQADCggIDwAAAA==.Kyz:BAAANQADCgEIAQAAAA==.Kyzula:BAABNQAECn88AAMLAAoKXBeyJACKAgALAAoKXBeyJACKAgAKAAYKBBUMfAAEAQAAAA==.',
['Kê']='Kêndo:BAAANQADCgEIAQABNQAECggIHgAHAIoMAA==.',
La='Lagrandè:BAABNQAECn80AAIOAAoKiRrSHAAIAgAOAAoKiRrSHAAIAgAAAA==.',
Le='Leafar:BAAANQAECgQIBAABNQAECgkJKQAgANYMAA==.Lextalionis:BAAANQAECgEIAQAAAA==.',
Li='Liandrai:BAAANQAECgYIDwAAAA==.Lillyith:BAAANQADCggIIQAAAA==.Lilylocks:BAAANQAECgUIBgAAAA==.Littlelo:BAAANQAECgYIBwAAAA==.',
Lp='Lp:BAAANQAECgQIBwAAAA==.',
Ly='Lyanah:BAABNQAECn8vAAQYAAoKXgknNQByAQAYAAoKXgknNQByAQAhAAYKqQjhHwAZAQARAAMKJQWvowBTAAAAAA==.Lycota:BAAANQAECgYIBQAAAA==.Lydia:BAAANQAECgEIAwAAAA==.Lynn:BAAANQABCgMIAwAAAA==.Lyriell:BAAANQADCgYIBgAAAA==.',
Ma='Maelius:BAAANQADCgQIBAABNQAECgoKLQAZACkWAA==.Maggrus:BAAANQABCgYIDAAAAA==.Malical:BAAANQADCgEIAQAAAA==.Manshoon:BAAANQAECgIIAgABNQAECgUICQAJAAAAAA==.Manshöön:BAAANQADCgUIBQABNQAECgUICQAJAAAAAA==.Matheney:BAAANQAECgUIBwABNQAECggICAAJAAAAAA==.Matsuzo:BAAANQADCgYIBgAAAA==.Mattlock:BAABNQAECn8hAAIbAAkKtRQnCwBFAgAbAAkKtRQnCwBFAgAAAA==.Maverick:BAAANQABCggIDAAAAA==.',
Mc='Mcpuff:BAAANQAECgUIBQAAAA==.Mctubby:BAAANQADCgYJCwAAAA==.',
Md='Mdead:BAAANQABCgcICgAAAA==.',
Me='Meigz:BAAANQADCggIIQAAAA==.Melicious:BAAANQAECgUIBQAAAA==.Melicrime:BAAANQAECggICAAAAA==.Melinda:BAABNQAECn8uAAILAAoKgBeXIQCeAgALAAoKgBeXIQCeAgAAAA==.Meta:BAAANQAECgQICgAAAA==.Mewtwo:BAAANQAECgMIAwAAAA==.',
Mi='Milenzha:BAABNQAECn8fAAIBAAkKYA8vkAB5AQABAAkKYA8vkAB5AQAAAA==.Misaoh:BAAANQAECgYIDwAAAA==.',
Mo='Momo:BAABNQAECn8WAAMRAAoKnRP3IADhAQARAAoKnRP3IADhAQAYAAEK0gGbgQAUAAAAAA==.Moneysdmnhtr:BAAANQADCgEIAQAAAA==.Moonlightbae:BAAANQAFFAIIAgAAAA==.Moonreína:BAABNQAECn8fAAIRAAcKtQ7lRQD5AAARAAcKtQ7lRQD5AAAAAA==.Moons:BAAANQADCgYIBgABNQAFFAUICQAUAOoGAA==.Moontann:BAAANQADCggICgAAAA==.Moreia:BAAANQADCgMIAwAAAA==.Mousse:BAAANQAECgUIEQAAAA==.',
Mu='Murdalok:BAAANQAECggIEwAAAA==.',
My='Mysharona:BAAANQADCgYIBgAAAA==.Mysticfennec:BAAANQADCgQIBQAAAA==.',
Mz='Mzbiscuit:BAAANQADCgYIEQABNQADCgcIFQAJAAAAAA==.',
Na='Nanashi:BAAANQADCgQIBgAAAA==.Narberal:BAAANQAECgEIAQABNQAECgoKRAASAOcmAA==.Nasene:BAABNQAECn8aAAIEAAkKPCFdCwC7AgAEAAkKPCFdCwC7AgAAAA==.Nataltharion:BAAANQADCgcICQAAAA==.Natstryker:BAABNQAECn88AAQPAAoK1CTZAQCcAwAPAAoK1CTZAQCcAwAcAAcK5BK9LgAOAQAdAAcKigfuLgDzAAAAAA==.Naturemyth:BAAANQADCgYIBgAAAA==.',
Ne='Necromyst:BAAANQADCggIAQAAAA==.',
No='Noctyra:BAAANQAECgEIAQAAAA==.',
Nu='Nuciferas:BAAANQAECggIDQAAAA==.',
Od='Odosen:BAAANQAECgEIAgAAAA==.',
Ok='Okaminooni:BAAANQAECgUIBQAAAA==.',
Om='Omcmoneyshot:BAAANQAECgUIBgAAAA==.',
Op='Opktix:BAAANQADCgYIBgAAAA==.',
Or='Organa:BAABNQAECn8dAAIiAAcKDArkFQA9AQAiAAcKDArkFQA9AQAAAA==.',
Pa='Palarina:BAAANQAECgQICgABNQAECgoKMQAdAOMeAA==.Palyomie:BAAANQAECgYIEAAAAA==.',
Ph='Pho:BAABNQAECn8wAAIDAAkKdhwkOwB9AgADAAkKdhwkOwB9AgAAAA==.',
Pl='Playwityou:BAAANQAECgQIBgAAAA==.Plugley:BAAANQAECgUIBgAAAA==.',
Po='Poweedman:BAAANQAECggICgAAAA==.',
Pr='Pray:BAACNQAFFH8JAAMCAAQK/xN+CQDnAAACAAQK/xN+CQDnAAADAAMK4A5VJwCRAAA1AAQKf2QABAIACgqQHXMNAHECAAIACgqQHXMNAHECAAMACQrzIYA1AFMCABAACAq9FaQGAB0CAAE1AAUUBAgJAAIA/xMA.',
Pu='Pumpkins:BAAANQAECgYICAAAAA==.',
['Pë']='Përdü:BAAANQAECgQIBgAAAA==.',
Ra='Raethu:BAAANQAECgEIAwAAAA==.Rakunn:BAABNQAECn8WAAMLAAkKzgvubABWAQALAAkKzgvubABWAQAKAAEKnwEoWQEgAAAAAA==.Rastlindal:BAAANQABCgQIBAAAAA==.Ratapew:BAAANQAECgUIDwAAAA==.Ratheen:BAAANQABCggIJQAAAA==.Raytar:BAAANQAECgMIBwAAAA==.',
Re='Relaxx:BAABNQAECn8VAAIIAAgKiQ+6rwBaAQAIAAgKiQ+6rwBaAQAAAA==.Relthagest:BAAANQAECgYIDAAAAA==.Renn:BAAANQAECgQICQAAAA==.Retix:BAAANQAECgEIAQAAAA==.',
Rh='Rhordrin:BAAANQAECgQIBAABNQAECgkJGgAEADwhAA==.',
Ri='Riltonge:BAAANQAECgUICgAAAA==.',
Ro='Roachdirt:BAAANQAECgUJEQAAAA==.Robean:BAAANQADCgQIBAAAAA==.Rogun:BAABNQAECn8cAAIjAAoKwQfOBAA5AQAjAAoKwQfOBAA5AQAAAA==.Roxoxoxanne:BAAANQADCgcICgAAAA==.',
Ru='Rudger:BAAANQABCgIIAgAAAA==.Rustybray:BAABNQAECn8sAAIKAAoKAQuTigCKAQAKAAoKAQuTigCKAQAAAA==.',
Sa='Sageghost:BAAANQABCggIEQAAAA==.Sandryus:BAAANQAECgQIBwAAAA==.Sangol:BAAANQAECgUICwABNQAECgoKFgALAJMWAA==.Sarabi:BAABNQAECn8pAAIdAAgKKxYzEwC7AQAdAAgKKxYzEwC7AQAAAA==.Saralina:BAAANQAECgYICQABNQAECgoKMAASANwgAA==.',
Sc='Schnee:BAAANQAECgUIDQAAAA==.Schutzhund:BAAANQADCggIGQAAAA==.',
Se='Sekha:BAAANQADCgQIBwABNQAECgoKJwARADAYAA==.Sena:BAAANQADCgYIBgAAAA==.Serelia:BAAANQAECgMICAAAAA==.Seshiro:BAAANQAECgQIBAAAAA==.',
Sh='Shadoweave:BAAANQAECgYICwABNQAFFAgIIAABALkOAA==.Shalalia:BAAANQAECgYICgAAAA==.Shambean:BAAANQAECgEIAQAAAA==.Shavox:BAAANQABCgUICQAAAA==.Shhanks:BAAANQAECgIIAgAAAA==.Shieldster:BAEBNQAECn9SAAIHAAoKvhAZFgC3AQAHAAoKvhAZFgC3AQAAAA==.Shnizelnazee:BAABNQAECn8VAAIIAAcKgQqT8QA5AQAIAAcKgQqT8QA5AQAAAA==.',
Si='Siege:BAAANQAECgYICQABNQAFFAMIBwANAB0aAA==.Silvie:BAAANQADCgcIBwAAAA==.',
Sm='Smokeyb:BAABNQAECn8zAAIIAAoKYRSLggAjAgAIAAoKYRSLggAjAgAAAA==.',
Sn='Sneevie:BAAANQADCggIDwAAAA==.Snifra:BAAANQAECgEIAQAAAA==.Snorehees:BAABNQAECn8gAAIBAAoKXAphmwDQAQABAAoKXAphmwDQAQAAAA==.',
So='Solaeris:BAAANQADCggIDQAAAA==.Solarth:BAAANQADCgIIAgABNQAECgoKKgAUANoUAA==.Songstar:BAABNQAECn8vAAIBAAoKiR8HMgBtAgABAAoKiR8HMgBtAgAAAA==.Soullraven:BAAANQAECgYICgAAAA==.',
Sp='Spaceboat:BAABNQAECn8cAAIRAAkKTwvaYQBHAQARAAkKTwvaYQBHAQAAAA==.Sped:BAAANQAECgcICgAAAA==.Spy:BAAANQAECgEIAgAAAA==.Spàz:BAAANQAECgEIAQAAAA==.',
St='Staavon:BAABNQAECn8VAAIMAAUKXQUv8AC9AAAMAAUKXQUv8AC9AAAAAA==.Stalvis:BAAANQABCgIIAgAAAA==.Starblaze:BAAANQAECgUIBwAAAA==.Steeda:BAAANQADCggICAAAAA==.Stonehench:BAAANQADCgUIBQAAAA==.Strika:BAACNQAFFH8PAAMMAAcKWh5TEwA/AQAMAAYK1B5TEwA/AQAkAAEKcxxCDQBVAAA1AAQKf1kAAwwACgqQJSkMAKQDAAwACgo4JSkMAKQDACQAAQrBJPMzAGsAAAAA.',
Su='Sugarhoof:BAAANQAECgUIDwAAAA==.Sugarlick:BAAANQAECgQIDwAAAA==.Sugarpop:BAABNQAECn8wAAMSAAoK3CD2DgBTAwASAAoK3CD2DgBTAwAIAAMKewoRIQGkAAAAAA==.Suplazindh:BAABNQAFFH8FAAIVAAUKGw9oCAB2AQAVAAUKGw9oCAB2AQABNQAFFAkJKgAMAKwkAA==.',
Sw='Swiftstrike:BAAANQADCggJBQAAAA==.',
Sy='Sylvqt:BAAANQAECgEIAQAAAA==.Syntheticsyn:BAAANQAECgEIAwAAAA==.Syrebriel:BAAANQADCggIEAAAAA==.',
['Sí']='Sílíbrítí:BAAANQAECgcIBwABNQAFFAEIBQAFANUOAA==.',
Ta='Taediah:BAAANQAECgQIBgAAAA==.Tanjiro:BAABNQAECn8pAAMBAAoK8BiZTwAaAgABAAoK8BiZTwAaAgAlAAEKegXTkQAuAAAAAA==.Tanthanalas:BAAANQADCgUIBwAAAA==.Tazetack:BAAANQAECggIBgAAAA==.',
Tg='Tgoat:BAAANQADCgEIAQAAAA==.',
Th='Thenâ:BAAANQADCgUIDQAAAA==.Theoutcast:BAAANQAECgMIBAAAAA==.Thesarius:BAAANQAECggIEwAAAA==.',
Ti='Timeless:BAABNQAECn8kAAICAAoKQgllNQB4AQACAAoKQgllNQB4AQAAAA==.Tinymeatgang:BAAANQADCgUIBwAAAA==.',
To='Toetagger:BAABNQAECn8fAAMNAAkK/QofUQA5AQANAAkKaQkfUQA5AQAWAAYKfAvkfgAhAQAAAA==.Tonymaster:BAAANQAECgQIEwAAAA==.Toucannon:BAAANQAECggIEgABNQAECgoKFQAMAPkXAA==.',
Tr='Trackinoobs:BAAANQADCgcIFQAAAA==.Trashiepanda:BAAANQADCgQIBQAAAA==.Traumanurse:BAAANQADCgcIBwABNQAECgUIEQAJAAAAAA==.Treealia:BAAANQABCgIIAgAAAA==.',
Ty='Tyrrial:BAAANQAECgUICAAAAA==.Tyshus:BAAANQAECgQICwAAAA==.',
Ua='Ualmar:BAABNQAECn8lAAMDAAoKSBXCSgD4AQADAAoKSBXCSgD4AQACAAEKAADecAAAAAAAAA==.',
Un='Unsc:BAAANQAECgYIBQAAAA==.',
Ur='Urgrannargru:BAAANQAECgEIAgAAAA==.',
Ut='Uthgardt:BAAANQAECgYIEQAAAA==.',
Va='Valarion:BAABNQAECn8mAAImAAkKNwhxkgBHAQAmAAkKNwhxkgBHAQAAAA==.Validimus:BAAANQADCgEIAQAAAA==.Valorían:BAABNQAECn8zAAQZAAoKoB2BCABDAgAZAAkKmR6BCABDAgAmAAcKbBMVZgC4AQAiAAUKxRbSGAAUAQAAAA==.Vanfro:BAAANQAECggIDgAAAA==.Varthayn:BAABNQAECn8+AAIMAAoKMiEKHwC7AgAMAAoKMiEKHwC7AgAAAA==.Varue:BAAANQAECggICAAAAA==.',
Ve='Velandriel:BAAANQADCgEIAQABNQAECgoKKgAUANoUAA==.Verksquirt:BAAANQAECgYICwAAAA==.Verra:BAAANQAECgEIAgAAAA==.Vestaria:BAAANQADCgQIBAAAAA==.',
Vo='Volbain:BAABNQAECn8fAAIUAAcK0BHrQAAaAQAUAAcK0BHrQAAaAQAAAA==.Voodussy:BAAANQABCgQIBAAAAA==.',
Vu='Vulpsinculta:BAABNQAECn8pAAIaAAgKug5CeQBdAQAaAAgKug5CeQBdAQAAAA==.',
Wa='Warboar:BAAANQADCgIIAgAAAA==.Wasntmee:BAAANQADCgYIBgABNQADCgcIFQAJAAAAAA==.',
We='Weaz:BAAANQAECgIIAgAAAA==.',
Wi='Wichita:BAABNQAECn8tAAIOAAoKmxbZNgAvAgAOAAoKmxbZNgAvAgAAAA==.Wildbean:BAAANQAECgYIEAAAAA==.Windedworryr:BAAANQADCgYIBgAAAA==.',
Wt='Wtfguën:BAABNQAECn8dAAIeAAcKTBXJKAAsAQAeAAcKTBXJKAAsAQAAAA==.Wtfmaki:BAAANQADCggIGgAAAA==.',
Xa='Xaelina:BAAANQADCgQIBAAAAA==.Xanfel:BAAANQAECgEIAgAAAA==.',
Xb='Xbean:BAAANQAECgQICgAAAA==.',
Xo='Xondra:BAAANQAECgQIBAABNQAECggIIAAIACUKAA==.Xorman:BAAANQADCgcJEAAAAA==.',
Xy='Xyo:BAAANQAECgcIEwAAAA==.',
Xz='Xzairi:BAABNQAECn8nAAMRAAoKMBhpKgCFAgARAAoKMBhpKgCFAgAYAAEKoQm8fgAiAAAAAA==.',
Ye='Yennefer:BAAANQADCgYIBgABNQADCgcIFQAJAAAAAA==.',
Yn='Yngvar:BAAANQADCgQIBQAAAA==.',
Ze='Zenezal:BAAANQAECgQIBQAAAA==.',
Zi='Zinora:BAAANQADCgcICgAAAA==.Ziyue:BAAANQAECggIEAAAAA==.',
Zn='Zn:BAABNQAECn8nAAISAAoKZxIBUwAhAgASAAoKZxIBUwAhAgAAAA==.',
Zo='Zovaal:BAAANQAECgEIAQAAAA==.',
['Òm']='Òmcmoneyshot:BAAANQADCgYIEQAAAA==.',
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
