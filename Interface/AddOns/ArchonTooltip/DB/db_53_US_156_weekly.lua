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

local lookup = {'Hunter-BeastMastery','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','Paladin-Retribution','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','Druid-Balance','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Rogue-Subtlety','Druid-Restoration','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Monk-Mistweaver','Druid-Guardian','Hunter-Survival','Warlock-Affliction','Druid-Feral','Warrior-Fury','Priest-Discipline','Mage-Frost','Hunter-Marksmanship','Warrior-Arms',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abàddón:BAAANQADCgYIDAAAAA==.',
Ac='Acidburn:BAAANQADCgYICgAAAA==.',
Ae='Aelin:BAAANQADCgYIBgAAAA==.',
Al='Alluna:BAAANQAECgEIAQAAAA==.Alorillan:BAAANQAECgQIBgAAAA==.Altabrew:BAAANQADCgMIAwAAAA==.Altair:BAAANQAECgYIDQAAAA==.',
An='Anker:BAAANQAECgEIAQABNQAFFAQIBQABAFQIAA==.Anomalien:BAAANQAECgMIAwAAAA==.',
Ap='Apocalyspe:BAABNQAECn8YAAIBAAoKsAgk0wBaAQABAAoKsAgk0wBaAQAAAA==.Appless:BAABNQAECn9BAAMCAAoKwBYiGACTAgACAAoKwBYiGACTAgADAAoKVxdvUAAzAgAAAA==.',
Ar='Aridella:BAAANQAECgYIDwAAAA==.',
Au='Aurorá:BAAANQADCgUICAAAAA==.',
Az='Azusie:BAABNQAECn8tAAIEAAgKFxGXFQAPAgAEAAgKFxGXFQAPAgAAAA==.',
Ba='Bablepopye:BAAANQAECgMIAwAAAA==.Baddate:BAAANQAECgIIAQAAAA==.Baddragøn:BAABNQAECn8cAAMFAAkKNRmOFgBOAgAFAAkKNRmOFgBOAgAGAAIKywLkNwBPAAAAAA==.Balthaas:BAABNQAECn8ZAAMHAAoKAAzDLgBoAQAHAAkKogzDLgBoAQAIAAEKkAcftAEuAAAAAA==.Bangen:BAAANQAECgUIBgAAAA==.Baulters:BAAANQADCgYIBgAAAA==.Baylor:BAAANQADCgUIBQAAAA==.',
Bc='Bckstabber:BAAANQADCgQIBAAAAA==.',
Be='Beenn:BAAANQADCgcJDAAAAA==.Belael:BAAANQADCgcIBwAAAA==.Benrent:BAAANQADCgEIAQABNQADCgcJDAAJAAAAAA==.',
Bi='Biinks:BAAANQADCggIEwAAAA==.Billywitchdr:BAABNQAECn8pAAQKAAkKXRYNOQBxAQAKAAkKXRYNOQBxAQALAAEK6QwNHQEzAAAEAAEKvgG2KwAqAAAAAA==.Bisharp:BAAANQADCggICAABNQAECgoKFQAMAPkXAA==.',
Bl='Blazingelf:BAAANQADCgMIAwAAAA==.Blindedbý:BAAANQABCgYIBgAAAA==.Bluetoykawi:BAABNQAECn88AAINAAoKhxFlJgCeAQANAAoKhxFlJgCeAQAAAA==.',
Bo='Boltspark:BAAANQADCgYIBgAAAA==.Bonedelivery:BAAANQABCgIIAgAAAA==.',
Br='Breloom:BAAANQAECgYIBgABNQAECgoKFQAMAPkXAA==.',
Bu='Bulkathos:BAAANQAECgEIAwABNQAECgkJHgACAEkJAA==.Bulliedgair:BAAANQAECgIIAgABNQAECgcIDQAJAAAAAA==.',
['Bé']='Béorñ:BAAANQAECggIDgAAAA==.',
Ca='Cariandria:BAAANQADCgYICwAAAA==.',
Ch='Charita:BAECNQAFFH8FAAIOAAMKsgThEgCIAAAOAAMKsgThEgCIAAA1AAQKfxsAAg4ACQrcFvw2AC4CAA4ACQrcFvw2AC4CAAAA.Charming:BAEBNQAECn8VAAIPAAgKdB0hCwBbAgAPAAgKdB0hCwBbAgABNQAFFAMIBQAOALIEAA==.',
Cl='Clanker:BAAANQAECgQIAwAAAA==.Clark:BAAANQADCgEIAQAAAA==.Clouds:BAAANQADCggICAABNQAECgcIEAAJAAAAAA==.',
Co='Coffeecat:BAAANQADCgYIEgABNQADCgcIDgAJAAAAAA==.Contrlurself:BAAANQADCgQIBAABNQAECgoKJgAQADcSAA==.Cowret:BAABNQAECn81AAIRAAoKxiPBBQCfAwARAAoKxiPBBQCfAwAAAA==.',
Cr='Crowleyy:BAAANQADCgUIBQAAAA==.',
Da='Dademurphy:BAAANQADCgIIAgAAAA==.Darc:BAAANQAECgIIAgAAAA==.Darkfoxdemon:BAABNQAECn8iAAQSAAoK6hSXCwAVAgASAAgKnxiXCwAVAgATAAgKpgw+WQAiAQAUAAYKXwWbSwD8AAAAAA==.Darkfoxgrime:BAAANQAECgMIAwABNQAECgoKIgASAOoUAA==.Darkjager:BAAANQADCgcIBwAAAA==.Darkstaff:BAAANQADCgMIAwAAAA==.Darkways:BAAANQADCgYIBgAAAA==.Darlah:BAAANQAECgcIDAAAAA==.Dayyva:BAAANQAECgQIDQAAAA==.',
De='Deadcobra:BAAANQADCgMIBQAAAA==.Deangilberry:BAAANQADCgQICQAAAA==.Deathbyelf:BAAANQADCgcIBwAAAA==.Delindeyn:BAAANQAECgIIAQAAAA==.Deltria:BAAANQAECgQIBgAAAA==.Devils:BAAANQADCgMIAwAAAA==.Deviltank:BAAANQADCgQIBAAAAA==.',
Di='Diaboliq:BAAANQAECgQICwAAAA==.Diefenbaker:BAAANQADCgcIEgAAAA==.Digmyearth:BAAANQADCgYIBgAAAA==.Dilea:BAAANQAECgEIAQAAAA==.',
Dk='Dkon:BAABNQAECn8gAAMOAAgKqBmpQgDxAQAOAAcKHRipQgDxAQAVAAYKWxZVfAArAQAAAA==.',
Do='Doppler:BAABNQAECn8cAAIMAAkKYw+Y8QCoAQAMAAkKYw+Y8QCoAQAAAA==.',
Dr='Dracomyst:BAAANQADCggIAgAAAA==.Driver:BAEANQAECggICgAAAA==.Drruz:BAAANQADCggIJAAAAA==.',
Du='Dumbledorr:BAAANQAECgIIAgAAAQ==.Durzoe:BAABNQAECn8YAAIWAAgKWhEiHwDXAQAWAAgKWhEiHwDXAQAAAA==.',
Dv='Dvsmage:BAAANQADCgcIDQABNQAECgEIAQAJAAAAAA==.',
Dw='Dwod:BAABNQAECn8rAAMNAAkKiRSYJQCkAQANAAkKiRSYJQCkAQAOAAQKLgdIoQCUAAAAAA==.',
['Dí']='Díscø:BAEBNQAECn8aAAICAAkKjxjyGQB+AgACAAkKjxjyGQB+AgAAAA==.',
Ed='Edrian:BAAANQADCgYIBgAAAA==.',
Er='Ereithis:BAAANQAECgEIAQABNQAECgoKLwAXAF4JAA==.Errita:BAAANQAECgQIBAAAAA==.Ershulie:BAAANQABCggIJwAAAA==.',
Ev='Evilcoffee:BAAANQADCgcIDgAAAA==.',
Ew='Ewt:BAABNQAECn8lAAIYAAoK1RURFADlAQAYAAoK1RURFADlAQAAAA==.',
Fa='Fastnine:BAABNQAECn8VAAIMAAoK+RdOQwD9AgAMAAoK+RdOQwD9AgAAAA==.',
Fe='Felhound:BAAANQAECgQIBgAAAA==.Felussi:BAABNQAECn8cAAMZAAgK5xHlfgDpAQAZAAgK5xHlfgDpAQAaAAEKtRRGcQA+AAAAAA==.',
Fi='Finnster:BAABNQAECn84AAIBAAkK0AlBZAB0AQABAAkK0AlBZAB0AQAAAA==.Fionna:BAAANQADCgQIBAAAAA==.',
Fl='Flameon:BAAANQABCgcICwAAAA==.Flarixi:BAAANQADCgcICgAAAA==.Fleurminator:BAAANQAECgYICwAAAA==.Flipmaster:BAAANQADCgEIAQAAAA==.',
Fr='Fractor:BAAANQADCgYICwAAAA==.Friedchickn:BAAANQAECgcIAQAAAA==.Frieia:BAABNQAECn8XAAMXAAYKAQOxPgCbAAAXAAYKAQOxPgCbAAAQAAEKAACdggAAAAAAAA==.Frostface:BAAANQADCgcICwAAAA==.Frozenjade:BAAANQADCgIIAwAAAA==.',
Fu='Fubuki:BAACNQAFFH8XAAMbAAYKsBLIBwC8AAAPAAUKtAAmBwDUAAAbAAUKsBLIBwC8AAA1AAQKfzMAAxsACgppIHMQAOACABsACgppIHMQAOACAA8AAwr7Br8pAHUAAAAA.Fupasniffer:BAAANQADCgcICQAAAA==.',
Ga='Galapriest:BAAANQAECgEIAQAAAA==.Galarína:BAABNQAECn8pAAMcAAoK4x64BQC2AgAcAAoK4x64BQC2AgAbAAEK0AuuawAzAAAAAA==.Gallitha:BAAANQADCgUIBQAAAA==.Gamewarden:BAAANQADCggIDgABNQAECgkJKwADAHYcAA==.Gandora:BAABNQAECn8kAAQVAAoKhgySXQCZAQAVAAoKhgySXQCZAQANAAMKpwY6kAB4AAAOAAEKAABpzAAxAAAAAA==.Gauge:BAAANQAECgcIDQABNQAECggIDAAJAAAAAA==.',
Ge='Getoffme:BAAANQAECgUICAAAAA==.',
Gk='Gkmc:BAACNQAFFH8FAAIVAAMKUCCiDgAhAQAVAAMKUCCiDgAhAQA1AAQKfxoAAhUACQqaJLcEAPsCABUACQqaJLcEAPsCAAE1AAUUCAgRAAwANB0A.',
Go='Gobbomode:BAAANQADCgYIBgAAAA==.Gorbino:BAABNQAECn81AAIHAAoKjCTFAgCcAwAHAAoKjCTFAgCcAwAAAA==.',
Gr='Greasemunkey:BAAANQAECgUIDwAAAA==.Gretchaen:BAAANQAECgUIDgAAAA==.Griiv:BAABNQAECn81AAIIAAkKOyYLGABkAwAIAAkKOyYLGABkAwABNQAECgoKJAAEAG8kAA==.Grislydemon:BAAANQADCggICAAAAA==.Grislydoom:BAAANQAECgEIAQAAAA==.Grislyshock:BAABNQAECn8tAAIEAAoKVhv+DACeAgAEAAoKVhv+DACeAgAAAA==.',
Ha='Hairymartini:BAAANQAECgQIBAABNQAECgoKLQAKAE8fAA==.Hakunamatata:BAAANQAECgEIAQAAAA==.Hamburger:BAABNQAECn8VAAICAAgK5Q4wFgBtAQACAAgK5Q4wFgBtAQAAAA==.Hammerhard:BAAANQADCgIIAgAAAA==.Harcones:BAAANQADCgMJAwAAAA==.',
He='Heights:BAAANQADCgMIAwABNQAECgQIBgAJAAAAAA==.Heliosan:BAABNQAECn8iAAIDAAgKuhfcbADXAQADAAgKuhfcbADXAQAAAA==.Hellelements:BAAANQAECggIDAAAAA==.Hemoblast:BAAANQADCgIIAgAAAA==.Hemolight:BAAANQADCgYIDAAAAA==.',
Ho='Hojiitaa:BAAANQADCgUIBQAAAA==.Holybean:BAAANQADCgcICwABNQAECgEIAQAJAAAAAA==.',
Hr='Hrshoo:BAAANQAFFAEIAQAAAA==.',
['Hä']='Hädês:BAAANQAECgQIBQAAAA==.',
Je='Jeannaah:BAAANQAECgYICQABNQAECgUIBgAJAAAAAA==.Jekyl:BAAANQADCgMIAwAAAA==.Jekyll:BAAANQADCgUIBQAAAA==.',
Jh='Jharia:BAAANQADCgYIBgAAAA==.',
Jo='Jodiedawn:BAAANQAECgMIAwAAAA==.',
Ju='Judgment:BAAANQABCgEJAQAAAA==.',
['Já']='Jáckyboy:BAABNQAECn87AAMXAAoK6xmVGQBuAgAXAAkKfRiVGQBuAgAQAAoK9xqeGQDFAQAAAA==.',
Ka='Kalestra:BAABNQAECn8nAAMQAAkKyRv1FAABAgAQAAkKyRv1FAABAgAdAAcK1wjPMQAQAQAAAA==.Kalithos:BAAANQAECgQIBQAAAA==.Kayelalynn:BAABNQAECn8mAAIQAAoKNxIERgDXAQAQAAoKNxIERgDXAQAAAA==.',
Ke='Keeghor:BAABNQAECn8kAAIEAAoKbyT5AgB0AwAEAAoKbyT5AgB0AwAAAA==.Kelana:BAAANQAECgMIAwAAAA==.Kendô:BAAANQADCgYIBwABNQAECgcIFgAHAPcMAA==.Keyahi:BAAANQAFFAEIAQABNQAECgEIAQAJAAAAAA==.',
Kh='Khaean:BAABNQAECn8vAAIeAAgKPxy7BACQAgAeAAgKPxy7BACQAgAAAA==.',
Ki='Kickandpunch:BAAANQAECgcIEAAAAA==.Kiilan:BAAANQADCgEIAQAAAA==.Kilan:BAABNQAECn8UAAIIAAYKhRGruwDkAAAIAAYKhRGruwDkAAAAAA==.Kimuraakid:BAAANQAECgEIAQAAAA==.',
Ko='Kocaman:BAAANQADCgIIAgAAAA==.Korladin:BAAANQADCgYICQAAAA==.',
Kr='Krutree:BAAANQAECgQIBgAAAA==.',
Ku='Kungfubean:BAAANQADCgcIBwABNQAECgEIAQAJAAAAAA==.Kuromu:BAAANQADCgMIAwAAAA==.Kutbrezbek:BAAANQABCgYIDgAAAA==.',
Ky='Kyleata:BAABNQAECn86AAIBAAoKiBkONwDFAgABAAoKiBkONwDFAgAAAA==.Kylz:BAAANQABCggICQAAAA==.Kyokin:BAACNQAFFH8GAAIIAAMKFh2GEQC1AAAIAAMKFh2GEQC1AAA1AAQKfzQAAwgACgoTG3Q8AAgCAAgACgoTG3Q8AAgCAAcAAQpOCJZ5ACMAAAAA.Kyryn:BAAANQADCgMIBwAAAA==.Kyz:BAAANQADCgEIAQAAAA==.Kyzula:BAABNQAECn8tAAMLAAoK+hb2FAChAgALAAoK+hb2FAChAgAKAAUKMxLtsgAtAQAAAA==.',
['Kê']='Kêndo:BAAANQADCgEIAQABNQAECgcIFgAHAPcMAA==.',
La='Lagrandè:BAABNQAECn8pAAIOAAkK0RnaHACqAQAOAAkK0RnaHACqAQAAAA==.',
Le='Leafar:BAAANQADCgQIBAABNQAECgkJKQAfANYMAA==.Lextalionis:BAAANQABCgQICAAAAA==.',
Li='Liandrai:BAAANQAECgYICgAAAA==.Lillyith:BAAANQADCgcIGQAAAA==.Lilylocks:BAAANQAECgUIBgAAAA==.Littlelo:BAAANQAECgYIBgAAAA==.',
Ly='Lyanah:BAABNQAECn8vAAQXAAoKXgknNQByAQAXAAoKXgknNQByAQAgAAYKqQjhHwAZAQAQAAMKJQWvowBTAAAAAA==.Lycota:BAAANQAECgYIBAAAAA==.Lynn:BAAANQABCgMIBAAAAA==.Lyriell:BAAANQADCgYIBgAAAA==.',
Ma='Maelius:BAAANQADCgQIBAABNQAECgoKJQAYANUVAA==.Maggrus:BAAANQABCgYIDAAAAA==.Malical:BAAANQADCgEIAQAAAA==.Manshoon:BAAANQADCgEIAQABNQAECgEIAgAJAAAAAA==.Manshöön:BAAANQADCgUIBQABNQAECgEIAgAJAAAAAA==.Matheney:BAAANQAECgUIBgABNQADCgYIBgAJAAAAAA==.Matsuzo:BAAANQADCgYIBgAAAA==.Mattlock:BAABNQAECn8hAAIaAAkKtRQnCwBFAgAaAAkKtRQnCwBFAgAAAA==.Maverick:BAAANQABCggIDQAAAA==.',
Mc='Mcpuff:BAAANQAECgUIBQAAAA==.Mctubby:BAAANQADCgYJCwAAAA==.',
Md='Mdead:BAAANQABCgcICgAAAA==.',
Me='Meigz:BAAANQADCgcIGQAAAA==.Melicious:BAAANQAECgUIBQAAAA==.Melicrime:BAAANQAECgQIBQAAAA==.Melinda:BAABNQAECn8lAAILAAoKbhd+IABBAgALAAoKbhd+IABBAgAAAA==.Meta:BAAANQAECgIIAwAAAA==.Mewtwo:BAAANQAECgMIAwAAAA==.',
Mi='Milenzha:BAABNQAECn8UAAIBAAgKwg+8lgADAQABAAgKwg+8lgADAQAAAA==.Misaoh:BAAANQAECgYIDwAAAA==.',
Mo='Momo:BAAANQAECggIDgAAAA==.Moneysdmnhtr:BAAANQADCgEIAQAAAA==.Moonreína:BAABNQAECn8aAAIQAAYKLQ+pYQBIAQAQAAYKLQ+pYQBIAQAAAA==.Moons:BAAANQADCgYIBgABNQAFFAUICQATAOoGAA==.Moontann:BAAANQADCggICgAAAA==.Moreia:BAAANQADCgMIAwAAAA==.Mousse:BAAANQAECgUIEAAAAA==.',
Mu='Murdalok:BAAANQAECgcIEQAAAA==.',
My='Mysharona:BAAANQADCgYIBgAAAA==.',
Mz='Mzbiscuit:BAAANQADCgYIEQABNQADCgcIFQAJAAAAAA==.',
Na='Narberal:BAAANQADCggIFgABNQAECgoKRAARAOcmAA==.Nasene:BAABNQAECn8ZAAIEAAgK+CBdCwC7AgAEAAgK+CBdCwC7AgAAAA==.Nataltharion:BAAANQADCgcICQAAAA==.Natstryker:BAABNQAECn8zAAQPAAoKyCPZAQCcAwAPAAoKyCPZAQCcAwAbAAYK8RXlJQD1AAAcAAcKigfuLgDzAAAAAA==.Naturemyth:BAAANQADCgYIBgAAAA==.',
Ne='Necromyst:BAAANQADCggIAQAAAA==.',
No='Noctyra:BAAANQAECgEIAQAAAA==.',
Nu='Nuciferas:BAAANQAECgMIAwAAAA==.',
Ok='Okaminooni:BAAANQAECgUIBQAAAA==.',
Om='Omcmoneyshot:BAAANQAECgUIBQAAAA==.',
Op='Opktix:BAAANQADCgYIBgAAAA==.',
Or='Organa:BAABNQAECn8YAAIhAAYKwQvkFQA9AQAhAAYKwQvkFQA9AQAAAA==.',
Pa='Palarina:BAAANQAECgQICgABNQAECgoKKQAcAOMeAA==.Palyomie:BAAANQAECgYIDgAAAA==.',
Ph='Pho:BAABNQAECn8rAAIDAAkKdhwkOwB9AgADAAkKdhwkOwB9AgAAAA==.',
Pl='Playwityou:BAAANQAECgQIBgAAAA==.Plugley:BAAANQAECgUIBgAAAA==.',
Po='Popmybubbel:BAAANQABCgEIAQAAAA==.Poweedman:BAAANQAECggICgAAAA==.',
Pr='Pray:BAACNQAFFH8GAAMCAAQKvRM4BgD3AAACAAQKvRM4BgD3AAADAAEKwAjfOAA9AAA1AAQKf0oABCIACgqnHaQGAB0CAAMABwpGHmBAAGoCACIACAq9FaQGAB0CAAIACQrCGyATAJgBAAE1AAUUBAgGAAIAvRMA.',
Pu='Pumpkins:BAAANQAECgYIBgAAAA==.',
['Pë']='Përdü:BAAANQAECgQIBgAAAA==.',
Ra='Raethu:BAAANQABCgIIAgAAAA==.Rakunn:BAAANQAECggIEQAAAA==.Rastlindal:BAAANQABCgQIBAAAAA==.Ratapew:BAAANQAECgUICgAAAA==.Ratheen:BAAANQABCggIHwAAAA==.Raytar:BAAANQAECgMIBQAAAA==.',
Re='Relaxx:BAAANQAECgUICgAAAA==.Relthagest:BAAANQAECgMIAwAAAA==.Renn:BAAANQAECgQICAAAAA==.Retix:BAAANQABCgQICAAAAA==.',
Rh='Rhordrin:BAAANQAECgQIBAABNQAECggIGQAEAPggAA==.',
Ri='Riltonge:BAAANQAECgQIBAAAAA==.',
Ro='Roachdirt:BAAANQAECgUJDgAAAA==.Robean:BAAANQADCgQIBAAAAA==.Rogun:BAAANQAECgcIDgAAAA==.Roxoxoxanne:BAAANQADCgcICgAAAA==.',
Ru='Rudger:BAAANQABCgMIAwAAAA==.Rustybray:BAABNQAECn8kAAIKAAkKdAiTigCKAQAKAAkKdAiTigCKAQAAAA==.',
Sa='Sageghost:BAAANQABCggIEQAAAA==.Sandryus:BAAANQAECgQIBwAAAA==.Sangol:BAAANQAECgUICwABNQAECggIEwAJAAAAAA==.Sarabi:BAABNQAECn8dAAIcAAcK+hftDgCRAQAcAAcK+hftDgCRAQAAAA==.Saralina:BAAANQAECgYICQABNQAECgoKLgARANwgAA==.',
Sc='Schnee:BAAANQAECgUICgAAAA==.Schutzhund:BAAANQADCggIGQAAAA==.',
Se='Sekha:BAAANQADCgQIBAABNQAECgoKJgAQACUXAA==.Sena:BAAANQADCgYIBgAAAA==.Serelia:BAAANQAECgEIAgAAAA==.',
Sh='Shadoweave:BAAANQAECgQIBQABNQAFFAcIHAABALgOAA==.Shalalia:BAAANQAECgEIAgAAAA==.Shambean:BAAANQAECgEIAQAAAA==.Shavox:BAAANQABCgUICQAAAA==.Shhanks:BAAANQAECgIIAgAAAA==.Shieldster:BAEBNQAECn84AAIHAAoKPAafIQDvAAAHAAoKPAafIQDvAAAAAA==.Shnizelnazee:BAABNQAECn8VAAIIAAcKgQqT8QA5AQAIAAcKgQqT8QA5AQAAAA==.',
Si='Siege:BAAANQAECgYICQABNQAFFAMIBwANAB0aAA==.Silvie:BAAANQADCgcIBwAAAA==.',
Sm='Smokeyb:BAABNQAECn8sAAIIAAoKXhKLggAjAgAIAAoKXhKLggAjAgAAAA==.',
Sn='Sneevie:BAAANQADCggIDwAAAA==.Snorehees:BAABNQAECn8bAAIBAAkKaglhmwDQAQABAAkKaglhmwDQAQAAAA==.',
So='Solaeris:BAAANQADCggIDQAAAA==.Solarth:BAAANQADCgIIAgABNQAECgoKJgATALMTAA==.Songstar:BAABNQAECn8mAAIBAAoKEh9jRgCZAgABAAoKEh9jRgCZAgAAAA==.Soullraven:BAAANQADCggIGAAAAA==.',
Sp='Spaceboat:BAABNQAECn8YAAIQAAgKOQvaYQBHAQAQAAgKOQvaYQBHAQAAAA==.Sped:BAAANQAECgcICQAAAA==.Spàz:BAAANQABCgMIAgAAAA==.',
St='Staavon:BAAANQAECgUIDAAAAA==.Stalvis:BAAANQABCgIIAgAAAA==.Starblaze:BAAANQAECgUIBwAAAA==.Steeda:BAAANQADCggICAAAAA==.Stonehench:BAAANQADCgUIBQAAAA==.Strika:BAACNQAFFH8PAAMMAAcKWh7QCQBUAQAMAAYK1B7QCQBUAQAjAAEKcxzyBwBeAAA1AAQKf0cAAwwACgplJSkMAKQDAAwACgoqJSkMAKQDACMAAQrdI/MzAGsAAAAA.',
Su='Sugarhoof:BAAANQAECgIIBAAAAA==.Sugarlick:BAAANQAECgQIDwAAAA==.Sugarpop:BAABNQAECn8uAAMRAAoK3CD2DgBTAwARAAoK3CD2DgBTAwAIAAMKtwkw5QCkAAAAAA==.Suplazindh:BAABNQAFFH8FAAIUAAUKGw9oCAB2AQAUAAUKGw9oCAB2AQABNQAFFAkJIAAMACAgAA==.',
Sw='Swiftstrike:BAAANQADCggJBQAAAA==.',
Sy='Syrebriel:BAAANQADCggIEAAAAA==.',
['Sí']='Sílíbrítí:BAAANQAECgcIBwABNQAECgoKSgAFANIZAA==.',
Ta='Taediah:BAAANQAECgEIAQAAAA==.Tanjiro:BAABNQAECn8fAAMBAAkKsxmhQgDZAQABAAkKsxmhQgDZAQAkAAEKegXTkQAuAAAAAA==.Tanthanalas:BAAANQADCgUIBwAAAA==.Tazetack:BAAANQAECggIBQAAAA==.',
Tg='Tgoat:BAAANQADCgEIAQAAAA==.',
Th='Thenâ:BAAANQADCgUIDQAAAA==.Theoutcast:BAAANQAECgMIBAAAAA==.Thesarius:BAAANQAECggIEQAAAA==.',
Ti='Timeless:BAABNQAECn8eAAICAAkKSQllNQB4AQACAAkKSQllNQB4AQAAAA==.Tinymeatgang:BAAANQADCgUIBwAAAA==.',
To='Toetagger:BAABNQAECn8eAAMNAAgKNwtZQQATAQAVAAYKfAvkfgAhAQANAAgKYAlZQQATAQAAAA==.Tonymaster:BAAANQAECgQIEgAAAA==.Toucannon:BAAANQAECggIEgABNQAECgoKFQAMAPkXAA==.',
Tr='Trackinoobs:BAAANQADCgcIFQAAAA==.Trashiepanda:BAAANQADCgQIBQAAAA==.Traumanurse:BAAANQADCgcIBwABNQAECgUIEAAJAAAAAA==.Treealia:BAAANQABCgIIAgAAAA==.',
Ty='Tyrrial:BAAANQAECgMIBAAAAA==.Tyshus:BAAANQAECgQICQAAAA==.',
Ua='Ualmar:BAABNQAECn8kAAMDAAoKSBXNLAARAgADAAoKSBXNLAARAgACAAEKAAAnVgAAAAAAAA==.',
Un='Unsc:BAAANQAECgQIBAAAAA==.',
Ur='Urgrannargru:BAAANQABCgIIAgAAAA==.',
Ut='Uthgardt:BAAANQAECgYIEQAAAA==.',
Va='Valarion:BAABNQAECn8eAAIlAAkKlQd4vACGAQAlAAkKlQd4vACGAQAAAA==.Validimus:BAAANQADCgEIAQAAAA==.Valinis:BAAANQABCgEIAQAAAA==.Valorían:BAABNQAECn8rAAQYAAoK/hwgCgCjAgAYAAkK4B0gCgCjAgAlAAcKbBPDQQDIAQAhAAUKxRbSGAAUAQAAAA==.Vanfro:BAAANQAECggIDQAAAA==.Varthayn:BAABNQAECn8zAAIMAAoK2h3JLQA7AgAMAAoK2h3JLQA7AgAAAA==.Varue:BAAANQAECggICAAAAA==.',
Ve='Velandriel:BAAANQADCgEIAQABNQAECgoKJgATALMTAA==.Verksquirt:BAAANQAECgYICwAAAA==.Verra:BAAANQAECgEIAQAAAA==.Vestaria:BAAANQADCgQIBAAAAA==.',
Vo='Volbain:BAABNQAECn8aAAITAAYKFRMMSgB8AQATAAYKFRMMSgB8AQAAAA==.',
Vu='Vulpsinculta:BAABNQAECn8dAAIZAAcKWgzgfQD7AAAZAAcKWgzgfQD7AAAAAA==.',
Wa='Warboar:BAAANQADCgIIAgAAAA==.Wasntmee:BAAANQADCgYIBgABNQADCgcIFQAJAAAAAA==.',
We='Weaz:BAAANQAECgIIAQAAAA==.',
Wi='Wichita:BAABNQAECn8lAAIOAAkKcxbZNgAvAgAOAAkKcxbZNgAvAgAAAA==.Wildbean:BAAANQAECgUIDAAAAA==.',
Wt='Wtfguën:BAABNQAECn8YAAIdAAYKhRVDJADoAAAdAAYKhRVDJADoAAAAAA==.Wtfmaki:BAAANQADCgcIEgAAAA==.',
Xa='Xaelina:BAAANQADCgQIBAAAAA==.Xanfel:BAAANQABCgQIBgAAAA==.',
Xb='Xbean:BAAANQAECgQICgAAAA==.',
Xo='Xondra:BAAANQAECgMIAwABNQAECggIGAAIAFQJAA==.Xorman:BAAANQADCgcJEAAAAA==.',
Xy='Xyo:BAAANQAECgcIEAAAAA==.',
Xz='Xzairi:BAABNQAECn8mAAMQAAoKJRdpKgCFAgAQAAoKJRdpKgCFAgAXAAEKoQm8fgAiAAAAAA==.',
Yn='Yngvar:BAAANQADCgQIBQAAAA==.',
Ze='Zenezal:BAAANQAECgQIBAAAAA==.',
Zi='Zinora:BAAANQADCgcICgAAAA==.Ziyue:BAAANQAECggIEAAAAA==.',
Zn='Zn:BAABNQAECn8nAAIRAAoKZxIBUwAhAgARAAoKZxIBUwAhAgAAAA==.',
Zo='Zovaal:BAAANQABCgYIBgAAAA==.',
['Àd']='Àddixt:BAAANQABCgIIAgAAAA==.',
['Åd']='Åddixt:BAAANQABCgMIAQAAAA==.',
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
