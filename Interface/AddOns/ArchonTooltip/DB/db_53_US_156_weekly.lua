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

local lookup = {'Hunter-BeastMastery','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','Paladin-Retribution','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','Druid-Balance','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Rogue-Subtlety','Druid-Restoration','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Monk-Mistweaver','Druid-Guardian','Hunter-Survival','Warlock-Affliction','Druid-Feral','Warrior-Fury','Priest-Discipline','Rogue-Outlaw','Mage-Frost','Hunter-Marksmanship','Warrior-Arms',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abàddón:BAAANQADCgYIDAAAAA==.',
Ac='Acidburn:BAAANQADCgYICgAAAA==.',
Ae='Aelin:BAAANQADCgYIBgAAAA==.',
Al='Alluna:BAAANQAECgEIAQAAAA==.Alorillan:BAAANQAECgQIBgAAAA==.Altabrew:BAAANQADCgMIAwAAAA==.Altair:BAAANQAECgYIDQAAAA==.',
An='Anker:BAAANQAECgEIAQABNQAFFAQIBQABAFQIAA==.Anomalien:BAAANQAECgMIAwAAAA==.',
Ap='Apocalyspe:BAABNQAECn8fAAIBAAoKwQ0pegB+AQABAAoKwQ0pegB+AQAAAA==.Appless:BAABNQAECn9LAAMCAAoKURm4DQBNAgACAAoKURm4DQBNAgADAAoKZhdvUAAzAgAAAA==.',
Ar='Aridella:BAAANQAECgYIDwAAAA==.',
Au='Aurorá:BAAANQADCgUICAAAAA==.',
Az='Azusie:BAABNQAECn81AAIEAAkKyxAiEQDEAQAEAAkKyxAiEQDEAQAAAA==.',
Ba='Bablepopye:BAAANQAECgMIAwAAAA==.Baddate:BAAANQAECgUIBgAAAA==.Baddragøn:BAABNQAECn8dAAMFAAkKNRmOFgBOAgAFAAkKNRmOFgBOAgAGAAIKywLkNwBPAAAAAA==.Balthaas:BAABNQAECn8aAAMHAAoKxQzDLgBoAQAHAAoKxQzDLgBoAQAIAAEKkAcftAEuAAAAAA==.Bangen:BAAANQAECgUIBgAAAA==.Baulters:BAAANQADCgYIBgAAAA==.Baylor:BAAANQADCgUIBQAAAA==.',
Bc='Bckstabber:BAAANQADCgQIBAAAAA==.',
Be='Beenn:BAAANQADCgcJDAAAAA==.Belael:BAAANQADCgcIBwAAAA==.Benrent:BAAANQADCgEIAQABNQADCgcJDAAJAAAAAA==.',
Bi='Biinks:BAAANQADCggIEwAAAA==.Billywitchdr:BAABNQAECn8sAAQKAAoKSBXANADKAQAKAAoKSBXANADKAQALAAEK6QwNHQEzAAAEAAEKvgFzMgApAAAAAA==.Bisharp:BAAANQADCggICAABNQAECgoKFQAMAPkXAA==.',
Bl='Blazingelf:BAAANQADCgMIAwAAAA==.Blindedbý:BAAANQABCgYICAAAAA==.Bluetoykawi:BAABNQAECn9HAAINAAoK/RMjIQANAgANAAoK/RMjIQANAgAAAA==.',
Bo='Boltspark:BAAANQADCgYIBgAAAA==.Bonedelivery:BAAANQABCgIIAgAAAA==.',
Br='Breloom:BAAANQAECgYIBgABNQAECgoKFQAMAPkXAA==.',
Bu='Bulkathos:BAAANQAECgEIAwABNQAECgoKJAACAEIJAA==.Bulliedgair:BAAANQAECgQIBQABNQAECgcIDQAJAAAAAA==.',
['Bé']='Béorñ:BAAANQAECggIDgAAAA==.',
Ca='Cariandria:BAAANQADCgYICwAAAA==.',
Ch='Charita:BAECNQAFFH8GAAIOAAQKsgTHFwCAAAAOAAQKsgTHFwCAAAA1AAQKfxsAAg4ACQrcFvw2AC4CAA4ACQrcFvw2AC4CAAAA.Charming:BAEBNQAECn8ZAAIPAAoKkhwhCwBbAgAPAAoKkhwhCwBbAgABNQAFFAQIBgAOALIEAA==.',
Cl='Clanker:BAAANQAECgQIAwAAAA==.Clark:BAAANQADCgEIAQAAAA==.Clouds:BAAANQADCggICAABNQAECgcIEAAJAAAAAA==.',
Co='Coffeecat:BAAANQADCgYIGAABNQAECgMIBQAJAAAAAA==.Contrlurself:BAAANQADCgQIBAABNQAECgoKLwAQAIMSAA==.Cowret:BAABNQAECn81AAIRAAoKxiPBBQCfAwARAAoKxiPBBQCfAwAAAA==.',
Cr='Crowleyy:BAAANQADCgUIBQAAAA==.',
Da='Dademurphy:BAAANQADCgIIAgAAAA==.Darc:BAAANQAECgMIAwAAAA==.Darkfoxdemon:BAABNQAECn8iAAQSAAoK6hSXCwAVAgASAAgKnxiXCwAVAgATAAgKpgw+WQAiAQAUAAYKXwWbSwD8AAAAAA==.Darkfoxgrime:BAAANQAECgcICgABNQAECgoKIgASAOoUAA==.Darkjager:BAAANQADCgcIBwAAAA==.Darkstaff:BAAANQADCgMIAwAAAA==.Darkways:BAAANQADCgYIBgAAAA==.Darlah:BAAANQAECgcIDAAAAA==.Dayyva:BAAANQAECgQIDQAAAA==.',
De='Deadcobra:BAAANQADCgMIBQAAAA==.Deangilberry:BAAANQADCgQICQAAAA==.Deathbyelf:BAAANQADCgcIBwAAAA==.Delindeyn:BAAANQAECgQIBQAAAA==.Deltria:BAAANQAECgQIBgAAAA==.Demonrot:BAAANQADCggIFgAAAA==.Devils:BAAANQADCgMIAwAAAA==.Deviltank:BAAANQADCgQIBAAAAA==.',
Di='Diaboliq:BAAANQAECgQIDwAAAA==.Digmyearth:BAAANQADCgYIBgAAAA==.Dilea:BAAANQAECgEIAQAAAA==.',
Dk='Dkon:BAABNQAECn8hAAMOAAgKlhqpQgDxAQAOAAgKZhepQgDxAQAVAAYKWxZVfAArAQAAAA==.',
Do='Doppler:BAABNQAECn8cAAIMAAkKYw+Y8QCoAQAMAAkKYw+Y8QCoAQAAAA==.',
Dr='Dracomyst:BAAANQADCggIAgAAAA==.Driver:BAEANQAECggICgAAAA==.Drruz:BAAANQADCggIKAAAAA==.',
Du='Dumbledorr:BAAANQAECgIIAgAAAQ==.Durzoe:BAABNQAECn8YAAIWAAgKWhEiHwDXAQAWAAgKWhEiHwDXAQAAAA==.',
Dv='Dvsmage:BAAANQADCgcIDQABNQAECgEIAQAJAAAAAA==.',
Dw='Dwod:BAABNQAECn8rAAMNAAkKiRR+NQCQAQANAAkKiRR+NQCQAQAOAAQKLgdIoQCUAAAAAA==.',
['Dí']='Díscø:BAEBNQAECn8aAAICAAkKjxjyGQB+AgACAAkKjxjyGQB+AgAAAA==.',
Ed='Edrian:BAAANQADCgYIBgAAAA==.',
Er='Ereithis:BAAANQAECgEIAQABNQAECgoKLwAXAF4JAA==.Errita:BAAANQAECgUICQAAAA==.Ershulie:BAAANQABCggIJwAAAA==.',
Ev='Evilcoffee:BAAANQADCgcIDgABNQAECgMIBQAJAAAAAA==.',
Ew='Ewt:BAABNQAECn8tAAIYAAoKKRagDwCDAQAYAAoKKRagDwCDAQAAAA==.',
Ez='Ezili:BAAANQAECgEIAQAAAA==.',
Fa='Fastnine:BAABNQAECn8VAAIMAAoK+RdOQwD9AgAMAAoK+RdOQwD9AgAAAA==.',
Fe='Felhound:BAAANQAECgQIBgAAAA==.Felussi:BAABNQAECn8cAAMZAAgK5xHlfgDpAQAZAAgK5xHlfgDpAQAaAAEKtRRGcQA+AAAAAA==.',
Fi='Finnster:BAABNQAECn8+AAIBAAoK0QurVwDYAQABAAoK0QurVwDYAQAAAA==.Fionna:BAAANQADCgQIBAAAAA==.',
Fl='Flameon:BAAANQABCgcICgAAAA==.Flarixi:BAAANQADCgcICgAAAA==.Fleurminator:BAAANQAECgYICwAAAA==.Flipmaster:BAAANQADCgEIAQAAAA==.',
Fr='Fractor:BAAANQADCgYICwAAAA==.Friedchickn:BAAANQAECgcIAQAAAA==.Frieia:BAABNQAECn8XAAMXAAYKAQNPSwCWAAAXAAYKAQNPSwCWAAAQAAEKAADQlAAAAAAAAA==.Frostface:BAAANQADCgcICwAAAA==.Frozenjade:BAAANQADCgIIAwAAAA==.',
Fu='Fubuki:BAACNQAFFH8XAAMbAAYKsBLhCgAOAQAbAAUKsBLhCgAOAQAPAAUKtAAmBwDUAAA1AAQKfzsAAxsACgpkITkMAHECABsACgpkITkMAHECAA8AAwr7Br8pAHUAAAAA.Fupasniffer:BAAANQADCggIEQAAAA==.',
Ga='Galapriest:BAAANQAECgEIAQAAAA==.Galarína:BAABNQAECn8xAAMcAAoK4x5bCAClAgAcAAoK4x5bCAClAgAbAAgK2g7wIQBTAQAAAA==.Gallitha:BAAANQADCgUIBQAAAA==.Gamewarden:BAAANQADCggIDgABNQAECgkJKwADAHYcAA==.Gandora:BAABNQAECn8sAAQVAAoKlw3/JgB4AQAVAAoKlw3/JgB4AQANAAMKpwY6kAB4AAAOAAEKAABpzAAxAAAAAA==.Gauge:BAAANQAECgcIDQABNQAECggIDAAJAAAAAA==.',
Ge='Getoffme:BAAANQAECgUICAAAAA==.',
Gk='Gkmc:BAACNQAFFH8FAAIVAAMKUCCiDgAhAQAVAAMKUCCiDgAhAQA1AAQKfx8AAhUACQrUJKgGAPQCABUACQrUJKgGAPQCAAE1AAUUCAgRAAwANB0A.',
Go='Gobbomode:BAAANQADCgYIBgAAAA==.Gorbino:BAABNQAECn82AAMHAAoKjCTFAgCcAwAHAAoKjCTFAgCcAwAIAAEKKhe7VAFFAAAAAA==.',
Gr='Greasemunkey:BAAANQAECgUIDwAAAA==.Gretchaen:BAAANQAECgUIEgAAAA==.Griiv:BAABNQAECn88AAIIAAkKYCYLGABkAwAIAAkKYCYLGABkAwABNQAECgoKKgAEAH8kAA==.Grislydemon:BAAANQADCggICAAAAA==.Grislydoom:BAAANQAECgEIAQAAAA==.Grislyshock:BAABNQAECn8tAAIEAAoKVhv+DACeAgAEAAoKVhv+DACeAgAAAA==.',
Ha='Haendor:BAAANQADCgMIAwAAAA==.Hairymartini:BAAANQAECgQIBAABNQAECgoKMwAKAKYfAA==.Hakunamatata:BAAANQAECgEIAgAAAA==.Hamburger:BAABNQAECn8VAAICAAgK5Q6MHQBmAQACAAgK5Q6MHQBmAQAAAA==.Hammerhard:BAAANQAECgMIAgAAAA==.Harcones:BAAANQADCgMJAwAAAA==.',
He='Heights:BAAANQADCgMIAwABNQAECgQIBgAJAAAAAA==.Heliosan:BAABNQAECn8mAAIDAAgKNxjvUwCxAQADAAgKNxjvUwCxAQAAAA==.Hellelements:BAAANQAECggIDAAAAA==.Hemoblast:BAAANQADCgIIAgAAAA==.Hemolight:BAAANQADCgYIDAAAAA==.',
Ho='Hojiitaa:BAAANQADCgUIBQAAAA==.',
Hr='Hrshoo:BAAANQAFFAEIAQAAAA==.',
['Hä']='Hädês:BAAANQAECgQIBQAAAA==.',
Je='Jeannaah:BAAANQAECgYICQABNQAECgUIBgAJAAAAAA==.Jekyl:BAAANQADCgMIAwAAAA==.Jekyll:BAAANQADCgUIBQAAAA==.',
Jh='Jharia:BAAANQADCgYIBgAAAA==.',
Jo='Jodiedawn:BAAANQAECgMIAwAAAA==.',
Ju='Judgment:BAAANQABCgEJAQAAAA==.',
['Já']='Jáckyboy:BAABNQAECn9DAAMXAAoK2xxIEAB8AgAXAAoK2xxIEAB8AgAQAAoK9xpjIgC0AQAAAA==.',
Ka='Kalestra:BAABNQAECn8pAAMQAAkKyRvlGwDyAQAQAAkKyRvlGwDyAQAdAAcK1wjPMQAQAQAAAA==.Kalithos:BAAANQAECgQIBQAAAA==.Kayelalynn:BAABNQAECn8vAAIQAAoKgxKXIwCpAQAQAAoKgxKXIwCpAQAAAA==.',
Ke='Keeghor:BAABNQAECn8qAAIEAAoKfyT5AgB0AwAEAAoKfyT5AgB0AwAAAA==.Kelana:BAAANQAECgQIBQAAAA==.Kendô:BAAANQADCgYIBwABNQAECggIHgAHAIoMAA==.Keyahi:BAAANQAFFAEIAQABNQAECgEIAQAJAAAAAA==.',
Kh='Khaean:BAABNQAECn84AAIeAAkKVR7SAgBsAgAeAAkKVR7SAgBsAgAAAA==.',
Ki='Kickandpunch:BAAANQAECgcIEAAAAA==.Kiilan:BAAANQADCgEIAQAAAA==.Kilan:BAABNQAECn8YAAIIAAcK2Q8bwQATAQAIAAcK2Q8bwQATAQAAAA==.Kimuraakid:BAAANQAECgEIAQAAAA==.',
Ko='Kocaman:BAAANQADCgIIAgAAAA==.Konite:BAAANQABCgIIAgAAAA==.Korladin:BAAANQADCgYICQAAAA==.',
Kr='Krutree:BAAANQAECgQIBgAAAA==.',
Ku='Kungfubean:BAAANQADCgcIBwABNQAECgEIAQAJAAAAAA==.Kuromu:BAAANQADCgMIAwAAAA==.Kutbrezbek:BAAANQABCgYIDgAAAA==.',
Ky='Kyleata:BAABNQAECn8/AAIBAAoKtxkONwDFAgABAAoKtxkONwDFAgAAAA==.Kylz:BAAANQABCggICQAAAA==.Kyokin:BAACNQAFFH8GAAIIAAMKFh26FgCwAAAIAAMKFh26FgCwAAA1AAQKfzsAAwgACgrRHM9EACgCAAgACgrRHM9EACgCAAcAAQpOCJZ5ACMAAAAA.Kyryn:BAAANQADCggIDwAAAA==.Kyz:BAAANQADCgEIAQAAAA==.Kyzula:BAABNQAECn88AAMLAAoKXBfwHQCdAgALAAoKXBfwHQCdAgAKAAYKBBV+bQAGAQAAAA==.',
['Kê']='Kêndo:BAAANQADCgEIAQABNQAECggIHgAHAIoMAA==.',
La='Lagrandè:BAABNQAECn8sAAIOAAoKdhmMHQDkAQAOAAoKdhmMHQDkAQAAAA==.',
Le='Leafar:BAAANQAECgQIBAABNQAECgkJKQAfANYMAA==.Lextalionis:BAAANQABCgQICAAAAA==.',
Li='Liandrai:BAAANQAECgYIDAAAAA==.Lillyith:BAAANQADCggIIQAAAA==.Lilylocks:BAAANQAECgUIBgAAAA==.Littlelo:BAAANQAECgYIBgAAAA==.',
Lp='Lp:BAAANQAECgQIBQAAAA==.',
Ly='Lyanah:BAABNQAECn8vAAQXAAoKXgknNQByAQAXAAoKXgknNQByAQAgAAYKqQjhHwAZAQAQAAMKJQWvowBTAAAAAA==.Lycota:BAAANQAECgYIBAAAAA==.Lynn:BAAANQABCgMIAwAAAA==.Lyriell:BAAANQADCgYIBgAAAA==.',
Ma='Maelius:BAAANQADCgQIBAABNQAECgoKLQAYACkWAA==.Maggrus:BAAANQABCgYIDAAAAA==.Malical:BAAANQADCgEIAQAAAA==.Manshoon:BAAANQADCgEIAQABNQAECgYIBgAJAAAAAA==.Manshöön:BAAANQADCgUIBQABNQAECgYIBgAJAAAAAA==.Matheney:BAAANQAECgUIBgABNQAECgEIAQAJAAAAAA==.Matsuzo:BAAANQADCgYIBgAAAA==.Mattlock:BAABNQAECn8hAAIaAAkKtRQnCwBFAgAaAAkKtRQnCwBFAgAAAA==.Maverick:BAAANQABCggIDAAAAA==.',
Mc='Mcpuff:BAAANQAECgUIBQAAAA==.Mctubby:BAAANQADCgYJCwAAAA==.',
Md='Mdead:BAAANQABCgcICgAAAA==.',
Me='Meigz:BAAANQADCgcIGQAAAA==.Melicious:BAAANQAECgUIBQAAAA==.Melicrime:BAAANQAECggICAAAAA==.Melinda:BAABNQAECn8sAAILAAoKgBdgGwCvAgALAAoKgBdgGwCvAgAAAA==.Meta:BAAANQAECgQIBwAAAA==.Mewtwo:BAAANQAECgMIAwAAAA==.',
Mi='Milenzha:BAABNQAECn8aAAIBAAgKKBDykwBGAQABAAgKKBDykwBGAQAAAA==.Misaoh:BAAANQAECgYIDwAAAA==.',
Mo='Momo:BAAANQAECggIDgAAAA==.Moneysdmnhtr:BAAANQADCgEIAQAAAA==.Moonlightbae:BAAANQAFFAIIAgAAAA==.Moonreína:BAABNQAECn8fAAIQAAcKtQ5EPwD6AAAQAAcKtQ5EPwD6AAAAAA==.Moons:BAAANQADCgYIBgABNQAFFAUICQATAOoGAA==.Moontann:BAAANQADCggICgAAAA==.Moreia:BAAANQADCgMIAwAAAA==.Mousse:BAAANQAECgUIEAAAAA==.',
Mu='Murdalok:BAAANQAECgcIEQAAAA==.',
My='Mysharona:BAAANQADCgYIBgAAAA==.Mysticfennec:BAAANQADCgQIBQAAAA==.',
Mz='Mzbiscuit:BAAANQADCgYIEQABNQADCgcIFQAJAAAAAA==.',
Na='Nanashi:BAAANQADCgMIBAAAAA==.Narberal:BAAANQADCggIFgABNQAECgoKRAARAOcmAA==.Nasene:BAABNQAECn8aAAIEAAkKPCFdCwC7AgAEAAkKPCFdCwC7AgAAAA==.Nataltharion:BAAANQADCgcICQAAAA==.Natstryker:BAABNQAECn80AAQPAAoKyCPZAQCcAwAPAAoKyCPZAQCcAwAbAAcK5BJ7KgAOAQAcAAcKigfuLgDzAAAAAA==.Naturemyth:BAAANQADCgYIBgAAAA==.',
Ne='Necromyst:BAAANQADCggIAQAAAA==.',
No='Noctyra:BAAANQAECgEIAQAAAA==.',
Nu='Nuciferas:BAAANQAECgcICgAAAA==.',
Ok='Okaminooni:BAAANQAECgUIBQAAAA==.',
Om='Omcmoneyshot:BAAANQAECgUIBQAAAA==.',
Op='Opktix:BAAANQADCgYIBgAAAA==.',
Or='Organa:BAABNQAECn8dAAIhAAcKDArkFQA9AQAhAAcKDArkFQA9AQAAAA==.',
Pa='Palarina:BAAANQAECgQICgABNQAECgoKMQAcAOMeAA==.Palyomie:BAAANQAECgYIDgAAAA==.',
Ph='Pho:BAABNQAECn8rAAIDAAkKdhwkOwB9AgADAAkKdhwkOwB9AgAAAA==.',
Pl='Playwityou:BAAANQAECgQIBgAAAA==.Plugley:BAAANQAECgUIBgAAAA==.',
Po='Poweedman:BAAANQAECggICgAAAA==.',
Pr='Pray:BAACNQAFFH8JAAMCAAQK/xMACADtAAACAAQK/xMACADtAAADAAMK4A7nIgCVAAA1AAQKf1oABAIACgqQHcELAHUCAAIACgqQHcELAHUCAAMACApJH2BAAGoCACIACAq9FaQGAB0CAAE1AAUUBAgJAAIA/xMA.',
Pu='Pumpkins:BAAANQAECgYIBgAAAA==.',
['Pë']='Përdü:BAAANQAECgQIBgAAAA==.',
Ra='Rakunn:BAAANQAECggIEgAAAA==.Rastlindal:BAAANQABCgQIBAAAAA==.Ratapew:BAAANQAECgUIDwAAAA==.Ratheen:BAAANQABCggIIQAAAA==.Raytar:BAAANQAECgMIBQAAAA==.',
Re='Relaxx:BAABNQAECn8VAAIIAAgKiQ84nwBOAQAIAAgKiQ84nwBOAQAAAA==.Relthagest:BAAANQAECgUIBgAAAA==.Renn:BAAANQAECgQICAAAAA==.Retix:BAAANQABCgQICAAAAA==.',
Rh='Rhordrin:BAAANQAECgQIBAABNQAECgkJGgAEADwhAA==.',
Ri='Riltonge:BAAANQAECgQIBgAAAA==.',
Ro='Roachdirt:BAAANQAECgUJDgAAAA==.Robean:BAAANQADCgQIBAAAAA==.Rogun:BAABNQAECn8aAAIjAAkKgwdCBQAIAQAjAAkKgwdCBQAIAQAAAA==.Roxoxoxanne:BAAANQADCgcICgAAAA==.',
Ru='Rudger:BAAANQABCgIIAgAAAA==.Rustybray:BAABNQAECn8oAAIKAAoKjwmTigCKAQAKAAoKjwmTigCKAQAAAA==.',
Sa='Sageghost:BAAANQABCggIEQAAAA==.Sandryus:BAAANQAECgQIBwAAAA==.Sangol:BAAANQAECgUICwABNQAECggIEwAJAAAAAA==.Sarabi:BAABNQAECn8jAAIcAAgK3RVDEQC2AQAcAAgK3RVDEQC2AQAAAA==.Saralina:BAAANQAECgYICQABNQAECgoKMAARANwgAA==.',
Sc='Schnee:BAAANQAECgUICgAAAA==.Schutzhund:BAAANQADCggIGQAAAA==.',
Se='Sekha:BAAANQADCgQIBwABNQAECgoKJwAQADAYAA==.Sena:BAAANQADCgYIBgAAAA==.Serelia:BAAANQAECgMIBgAAAA==.Seshiro:BAAANQABCgIIAwABNQAECgoKOgAIAFQfAA==.',
Sh='Shadoweave:BAAANQAECgYICwABNQAFFAgIHgABAGYNAA==.Shalalia:BAAANQAECgYIBwAAAA==.Shambean:BAAANQAECgEIAQAAAA==.Shavox:BAAANQABCgUICQAAAA==.Shhanks:BAAANQAECgIIAgAAAA==.Shieldster:BAEBNQAECn9HAAIHAAoKDgvNGQBuAQAHAAoKDgvNGQBuAQAAAA==.Shnizelnazee:BAABNQAECn8VAAIIAAcKgQqT8QA5AQAIAAcKgQqT8QA5AQAAAA==.',
Si='Siege:BAAANQAECgYICQABNQAFFAMIBwANAB0aAA==.Silvie:BAAANQADCgcIBwAAAA==.',
Sm='Smokeyb:BAABNQAECn8zAAIIAAoKYRQlbgC0AQAIAAoKYRQlbgC0AQAAAA==.',
Sn='Sneevie:BAAANQADCggIDwAAAA==.Snorehees:BAABNQAECn8cAAIBAAoKMglhmwDQAQABAAoKMglhmwDQAQAAAA==.',
So='Solaeris:BAAANQADCggIDQAAAA==.Solarth:BAAANQADCgIIAgABNQAECgoKKgATANoUAA==.Songstar:BAABNQAECn8vAAIBAAoKiR8dJgB8AgABAAoKiR8dJgB8AgAAAA==.Soullraven:BAAANQAECgYIBgAAAA==.',
Sp='Spaceboat:BAABNQAECn8cAAIQAAkKTwvaYQBHAQAQAAkKTwvaYQBHAQAAAA==.Sped:BAAANQAECgcICQAAAA==.',
St='Staavon:BAAANQAECgUIEAAAAA==.Stalvis:BAAANQABCgIIAgAAAA==.Starblaze:BAAANQAECgUIBwAAAA==.Steeda:BAAANQADCggICAAAAA==.Stonehench:BAAANQADCgUIBQAAAA==.Strika:BAACNQAFFH8PAAMMAAcKWh62DgBGAQAMAAYK1B62DgBGAQAkAAEKcxy4CgBeAAA1AAQKf04AAwwACgplJSkMAKQDAAwACgoqJSkMAKQDACQAAQrdI/MzAGsAAAAA.',
Su='Sugarhoof:BAAANQAECgQICAAAAA==.Sugarlick:BAAANQAECgQIDwAAAA==.Sugarpop:BAABNQAECn8wAAMRAAoK3CD2DgBTAwARAAoK3CD2DgBTAwAIAAMKewoyEQGYAAAAAA==.Suplazindh:BAABNQAFFH8FAAIUAAUKGw9oCAB2AQAUAAUKGw9oCAB2AQABNQAFFAkJKQAMAKwkAA==.',
Sw='Swiftstrike:BAAANQADCggJBQAAAA==.',
Sy='Syrebriel:BAAANQADCggIEAAAAA==.',
['Sí']='Sílíbrítí:BAAANQAECgcIBwABNQAFFAEIBQAFANUOAA==.',
Ta='Taediah:BAAANQAECgEIAgAAAA==.Tanjiro:BAABNQAECn8lAAMBAAkK6BroTQD0AQABAAkK6BroTQD0AQAlAAEKegXTkQAuAAAAAA==.Tanthanalas:BAAANQADCgUIBwAAAA==.Tazetack:BAAANQAECggIBQAAAA==.',
Tg='Tgoat:BAAANQADCgEIAQAAAA==.',
Th='Thenâ:BAAANQADCgUIDQAAAA==.Theoutcast:BAAANQAECgMIBAAAAA==.Thesarius:BAAANQAECggIEQAAAA==.',
Ti='Timeless:BAABNQAECn8kAAICAAoKQgllNQB4AQACAAoKQgllNQB4AQAAAA==.Tinymeatgang:BAAANQADCgUIBwAAAA==.',
To='Toetagger:BAABNQAECn8eAAMNAAgKNwtQUwALAQAVAAYKfAvkfgAhAQANAAgKYAlQUwALAQAAAA==.Tonymaster:BAAANQAECgYIEwAAAA==.Toucannon:BAAANQAECggIEgABNQAECgoKFQAMAPkXAA==.',
Tr='Trackinoobs:BAAANQADCgcIFQAAAA==.Trashiepanda:BAAANQADCgQIBQAAAA==.Traumanurse:BAAANQADCgcIBwABNQAECgUIEAAJAAAAAA==.Treealia:BAAANQABCgIIAgAAAA==.',
Ty='Tyrrial:BAAANQAECgUICAAAAA==.Tyshus:BAAANQAECgQICQAAAA==.',
Ua='Ualmar:BAABNQAECn8lAAMDAAoKSBW7QAD/AQADAAoKSBW7QAD/AQACAAEKAAAJZwAAAAAAAA==.',
Un='Unsc:BAAANQAECgYIBQAAAA==.',
Ur='Urgrannargru:BAAANQABCgIIAgAAAA==.',
Ut='Uthgardt:BAAANQAECgYIEQAAAA==.',
Va='Valarion:BAABNQAECn8eAAImAAkKlQd4vACGAQAmAAkKlQd4vACGAQAAAA==.Validimus:BAAANQADCgEIAQAAAA==.Valorían:BAABNQAECn8rAAQYAAoK/hwgCgCjAgAYAAkK4B0gCgCjAgAmAAcKbBMAWQC8AQAhAAUKxRbSGAAUAQAAAA==.Vanfro:BAAANQAECggIDQAAAA==.Varthayn:BAABNQAECn83AAIMAAoK3SCZLgBnAgAMAAoK3SCZLgBnAgAAAA==.Varue:BAAANQAECggICAAAAA==.',
Ve='Velandriel:BAAANQADCgEIAQABNQAECgoKKgATANoUAA==.Verksquirt:BAAANQAECgYICwAAAA==.Verra:BAAANQAECgEIAQAAAA==.Vestaria:BAAANQADCgQIBAAAAA==.',
Vo='Volbain:BAABNQAECn8fAAITAAcK0BGeOQAeAQATAAcK0BGeOQAeAQAAAA==.',
Vu='Vulpsinculta:BAABNQAECn8jAAIZAAgKhw5ebwBRAQAZAAgKhw5ebwBRAQAAAA==.',
Wa='Warboar:BAAANQADCgIIAgAAAA==.Wasntmee:BAAANQADCgYIBgABNQADCgcIFQAJAAAAAA==.',
We='Weaz:BAAANQAECgIIAQAAAA==.',
Wi='Wichita:BAABNQAECn8pAAIOAAoKhBbZNgAvAgAOAAoKhBbZNgAvAgAAAA==.Wildbean:BAAANQAECgYIEAAAAA==.Windedworryr:BAAANQADCgYIBgAAAA==.',
Wt='Wtfguën:BAABNQAECn8dAAIdAAcKTBUEIwAyAQAdAAcKTBUEIwAyAQAAAA==.Wtfmaki:BAAANQADCgcIEgAAAA==.',
Xa='Xaelina:BAAANQADCgQIBAAAAA==.',
Xb='Xbean:BAAANQAECgQICgAAAA==.',
Xo='Xondra:BAAANQAECgQIAwABNQAECggIHgAIACUKAA==.Xorman:BAAANQADCgcJEAAAAA==.',
Xy='Xyo:BAAANQAECgcIEAAAAA==.',
Xz='Xzairi:BAABNQAECn8nAAMQAAoKMBhpKgCFAgAQAAoKMBhpKgCFAgAXAAEKoQm8fgAiAAAAAA==.',
Ye='Yennefer:BAAANQADCgYIBgABNQADCgcIFQAJAAAAAA==.',
Yn='Yngvar:BAAANQADCgQIBQAAAA==.',
Ze='Zenezal:BAAANQAECgQIBAAAAA==.',
Zi='Zinora:BAAANQADCgcICgAAAA==.Ziyue:BAAANQAECggIEAAAAA==.',
Zn='Zn:BAABNQAECn8nAAIRAAoKZxIBUwAhAgARAAoKZxIBUwAhAgAAAA==.',
Zo='Zovaal:BAAANQABCgYIBgAAAA==.',
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
