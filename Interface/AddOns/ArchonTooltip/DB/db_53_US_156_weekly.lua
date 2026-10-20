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

local lookup = {'Hunter-BeastMastery','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Mage-Arcane','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','Druid-Balance','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Rogue-Subtlety','Druid-Restoration','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Druid-Guardian','Hunter-Survival','Druid-Feral','Mage-Frost','Hunter-Marksmanship','Warrior-Arms','Warrior-Fury',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abàddón:BAAANQADCgYIDAAAAA==.',
Ac='Acidburn:BAAANQADCgYICgAAAA==.',
Ae='Aelin:BAAANQADCgYIBgAAAA==.',
Al='Alluna:BAAANQAECgEIAQAAAA==.Alorillan:BAAANQAECgMIBQAAAA==.Altabrew:BAAANQADCgMIAwAAAA==.Altair:BAAANQAECgYIDQAAAA==.',
An='Anker:BAAANQAECgEIAQABNQAFFAQIBQABAFQIAA==.Anomalien:BAAANQAECgMIAwAAAA==.',
Ap='Apocalyspe:BAABNQAECn8YAAIBAAoKsAiEXgDvAAABAAoKsAiEXgDvAAAAAA==.Appless:BAABNQAECn81AAMCAAoKORIiGACTAgACAAkKixQiGACTAgADAAkKgxZvUAAzAgAAAA==.',
Ar='Aridella:BAAANQAECgYIDwAAAA==.',
Au='Aurorá:BAAANQADCgQIBAAAAA==.',
Az='Azusie:BAABNQAECn8mAAIEAAgKwxCXFQAPAgAEAAgKwxCXFQAPAgAAAA==.',
Ba='Bablepopye:BAAANQAECgMIAwAAAA==.Baddate:BAAANQAECgEIAQAAAA==.Baddragøn:BAABNQAECn8cAAMFAAkKNRmOFgBOAgAFAAkKNRmOFgBOAgAGAAIKywLkNwBPAAAAAA==.Balthaas:BAAANQAECggIEQAAAA==.Bangen:BAAANQAECgUIBgAAAA==.Baulters:BAAANQADCgYIBgAAAA==.Baylor:BAAANQADCgUIBQAAAA==.',
Bc='Bckstabber:BAAANQADCgQIBAAAAA==.',
Be='Beenn:BAAANQADCgcJDAAAAA==.Belael:BAAANQADCgcIBwAAAA==.Benrent:BAAANQADCgEIAQABNQADCgcJDAAHAAAAAA==.',
Bi='Biinks:BAAANQADCggIEwAAAA==.Billywitchdr:BAABNQAECn8hAAMIAAgKkRdqLQAIAQAIAAcKZRZqLQAIAQAJAAEK6QwNHQEzAAAAAA==.Bisharp:BAAANQADCggICAABNQAECgoKFQAKAPkXAA==.',
Bl='Blazingelf:BAAANQADCgMIAwAAAA==.Blindedbý:BAAANQABCgYIBgAAAA==.Bluetoykawi:BAABNQAECn8yAAILAAoKqA8HHwAqAQALAAoKqA8HHwAqAQAAAA==.',
Bo='Boltspark:BAAANQADCgYIBgAAAA==.Bonedelivery:BAAANQABCgIIAgAAAA==.',
Br='Breloom:BAAANQAECgYIBgABNQAECgoKFQAKAPkXAA==.',
Bu='Bulkathos:BAAANQAECgEIAwABNQAECgkJGgACAAoJAA==.Bulliedgair:BAAANQAECgEIAQABNQAECgcICwAHAAAAAA==.',
['Bé']='Béorñ:BAAANQAECggIDgAAAA==.',
Ca='Cariandria:BAAANQADCgYICwAAAA==.',
Ch='Charita:BAEBNQAECn8XAAIMAAkKcxX8NgAuAgAMAAkKcxX8NgAuAgAAAA==.Charming:BAEBNQAECn8VAAINAAgKdB0hCwBbAgANAAgKdB0hCwBbAgABNQAECgkJFwAMAHMVAA==.',
Cl='Clanker:BAAANQAECgQIAwAAAA==.Clark:BAAANQADCgEIAQAAAA==.Clouds:BAAANQADCggICAABNQAECgcIEAAHAAAAAA==.',
Co='Coffeecat:BAAANQADCgYIEgABNQAECgMIBAAHAAAAAA==.Contrlurself:BAAANQADCgQIBAABNQAECgkJIQAOAK0QAA==.Cowret:BAABNQAECn8xAAIPAAoKvSLBBQCfAwAPAAoKvSLBBQCfAwAAAA==.',
Cr='Crowleyy:BAAANQADCgUIBQAAAA==.',
Da='Dademurphy:BAAANQADCgIIAgAAAA==.Darc:BAAANQAECgEIAQAAAA==.Darkfoxdemon:BAABNQAECn8hAAQQAAkKnBaXCwAVAgAQAAgKnxiXCwAVAgARAAcKXg0+WQAiAQASAAYKXwWbSwD8AAAAAA==.Darkfoxgrime:BAAANQADCgYIBgABNQAECgkJIQAQAJwWAA==.Darkjager:BAAANQADCgcIBwAAAA==.Darkstaff:BAAANQADCgMIAwAAAA==.Darkways:BAAANQADCgYIBgAAAA==.Darlah:BAAANQAECgYIBgAAAA==.Dayyva:BAAANQAECgQIDQAAAA==.',
De='Deadcobra:BAAANQADCgMIBQAAAA==.Deangilberry:BAAANQADCgQICQAAAA==.Deathbyelf:BAAANQADCgcIBwAAAA==.Delindeyn:BAAANQAECgEIAQAAAA==.Deltria:BAAANQAECgMIBQAAAA==.Demonrot:BAAANQADCggIFgAAAA==.Devils:BAAANQADCgMIAwAAAA==.Deviltank:BAAANQADCgQIBAAAAA==.',
Di='Diaboliq:BAAANQAECgMIBwAAAA==.Diefenbaker:BAAANQADCgcIEgAAAA==.Digmyearth:BAAANQADCgYIBgAAAA==.Dilea:BAAANQAECgEIAQAAAA==.',
Dk='Dkon:BAABNQAECn8eAAMMAAcK1RupQgDxAQAMAAcKHRipQgDxAQATAAUKzBhVfAArAQAAAA==.',
Do='Doppler:BAABNQAECn8aAAIKAAkK3g6HXAAEAQAKAAkK3g6HXAAEAQAAAA==.',
Dr='Dracomyst:BAAANQADCggIAgAAAA==.Driver:BAEANQAECggICgAAAA==.Drruz:BAAANQADCggIHwAAAA==.',
Du='Dumbledorr:BAAANQAECgIIAgAAAQ==.Durzoe:BAABNQAECn8XAAIUAAgKRBEiHwDXAQAUAAgKRBEiHwDXAQAAAA==.',
Dv='Dvsmage:BAAANQADCgcIDQABNQAECgEIAQAHAAAAAA==.',
Dw='Dwod:BAABNQAECn8lAAMLAAgK+BRUIwAVAQALAAgK+BRUIwAVAQAMAAQKLgdIoQCUAAAAAA==.',
['Dí']='Díscø:BAEBNQAECn8aAAICAAkKjxjyGQB+AgACAAkKjxjyGQB+AgAAAA==.',
Ed='Edrian:BAAANQADCgYIBgAAAA==.',
Er='Ereithis:BAAANQAECgEIAQABNQAECgoKLwAVAF4JAA==.Errita:BAAANQADCggICQAAAA==.Ershulie:BAAANQABCggIJwAAAA==.',
Ev='Evilcoffee:BAAANQADCgcIDgABNQAECgMIBAAHAAAAAA==.',
Ew='Ewt:BAABNQAECn8gAAIWAAkKFhgRFADlAQAWAAkKFhgRFADlAQAAAA==.',
Fa='Fastnine:BAABNQAECn8VAAIKAAoK+RdOQwD9AgAKAAoK+RdOQwD9AgAAAA==.',
Fe='Felhound:BAAANQAECgMIBQAAAA==.Felussi:BAABNQAECn8cAAMXAAgK5xHlfgDpAQAXAAgK5xHlfgDpAQAYAAEKtRRGcQA+AAAAAA==.',
Fi='Finnster:BAABNQAECn8wAAIBAAgK1AhFPQA9AQABAAgK1AhFPQA9AQAAAA==.Fionna:BAAANQADCgQIBAAAAA==.',
Fl='Flameon:BAAANQABCgcICgAAAA==.Flarixi:BAAANQADCgcICgAAAA==.Fleurminator:BAAANQAECgYICwAAAA==.',
Fr='Fractor:BAAANQADCgYICwAAAA==.Friedchickn:BAAANQAECgYIAQAAAA==.Frieia:BAAANQAECgUIEAAAAA==.Frostface:BAAANQADCgcICwAAAA==.Frozenjade:BAAANQADCgIIAwAAAA==.',
Fu='Fubuki:BAACNQAFFH8XAAMZAAYKsBK/BADJAAANAAUKtAAmBwDUAAAZAAUKsBK/BADJAAA1AAQKfzAAAxkACgq5HXMQAOACABkACgq5HXMQAOACAA0AAwr7Br8pAHUAAAAA.',
Ga='Galapriest:BAAANQAECgEIAQAAAA==.Galarína:BAABNQAECn8jAAMaAAkK8x5HAgBNAgAaAAkK8x5HAgBNAgAZAAEK0AuuawAzAAAAAA==.Gallitha:BAAANQADCgUIBQAAAA==.Gamewarden:BAAANQADCggIDgABNQAECggIJwADAH4bAA==.Gandora:BAABNQAECn8fAAQTAAkKNw2SXQCZAQATAAkKNw2SXQCZAQALAAMKpwY6kAB4AAAMAAEKAABpzAAxAAAAAA==.Gauge:BAAANQAECgcIDQABNQAECggICgAHAAAAAA==.',
Ge='Getoffme:BAAANQAECgUICAAAAA==.',
Gk='Gkmc:BAABNQAFFH8FAAITAAMKUCCiDgAhAQATAAMKUCCiDgAhAQABNQAFFAgIEQAKADQdAA==.',
Go='Gobbomode:BAAANQADCgYIBgAAAA==.Gorbino:BAABNQAECn8xAAIbAAoK1iPFAgCcAwAbAAoK1iPFAgCcAwAAAA==.',
Gr='Greasemunkey:BAAANQAECgUIDwAAAA==.Gretchaen:BAAANQAECgQICwAAAA==.Griiv:BAABNQAECn80AAIcAAkKOybmDQAPAgAcAAkKOybmDQAPAgABNQAECgoKIAAEAG8kAA==.Grislydemon:BAAANQADCggICAAAAA==.Grislydoom:BAAANQAECgEIAQAAAA==.Grislyshock:BAABNQAECn8mAAIEAAgK5Rz+DACeAgAEAAgK5Rz+DACeAgAAAA==.',
Ha='Hairymartini:BAAANQADCggICwABNQAECggIKAAIAIsiAA==.Hakunamatata:BAAANQADCggIDAAAAA==.Hamburger:BAAANQAECgUIDAAAAA==.Hammerhard:BAAANQADCgIIAgAAAA==.Harcones:BAAANQADCgMJAwAAAA==.',
He='Heights:BAAANQADCgMIAwABNQAECgQIBgAHAAAAAA==.Heliosan:BAABNQAECn8hAAIDAAgKuhdFLwBAAQADAAgKuhdFLwBAAQAAAA==.Hellelements:BAAANQAECggICgAAAA==.Hemoblast:BAAANQADCgIIAgAAAA==.Hemolight:BAAANQADCgYIDAAAAA==.',
Ho='Hojiitaa:BAAANQADCgUIBQAAAA==.Holybean:BAAANQADCgcICwABNQAECgEIAQAHAAAAAA==.',
Hr='Hrshoo:BAAANQAFFAEIAQAAAA==.',
['Hä']='Hädês:BAAANQAECgMIBAAAAA==.',
Je='Jeannaah:BAAANQAECgYICQABNQAECgUIBgAHAAAAAA==.Jekyl:BAAANQADCgMIAwAAAA==.Jekyll:BAAANQADCgUIBQAAAA==.',
Jh='Jharia:BAAANQADCgYIBgAAAA==.',
Jo='Jodiedawn:BAAANQADCggICAAAAA==.',
Ju='Judgment:BAAANQABCgEJAQAAAA==.',
['Já']='Jáckyboy:BAABNQAECn8wAAMVAAoK6RyVGQBuAgAVAAgKhRqVGQBuAgAOAAkKEBolDACBAQAAAA==.',
Ka='Kalestra:BAABNQAECn8fAAMOAAgK2RwuEgBIAQAOAAgK2RwuEgBIAQAdAAcK1wjPMQAQAQAAAA==.Kalithos:BAAANQAECgMIBAAAAA==.Kayelalynn:BAABNQAECn8hAAIOAAkKrRAERgDXAQAOAAkKrRAERgDXAQAAAA==.Kaymoo:BAAANQABCgIIAgAAAA==.',
Ke='Keeghor:BAABNQAECn8gAAIEAAoKbyT5AgB0AwAEAAoKbyT5AgB0AwAAAA==.Kelana:BAAANQAECgMIAwAAAA==.Kendô:BAAANQADCgYIBwABNQAECgcIFgAbAPcMAA==.Keyahi:BAAANQAFFAEIAQABNQAECgEIAQAHAAAAAA==.',
Kh='Khaean:BAABNQAECn8nAAIeAAcK6R9TAgCDAQAeAAcK6R9TAgCDAQAAAA==.',
Ki='Kickandpunch:BAAANQAECgcIEAAAAA==.Kiilan:BAAANQADCgEIAQAAAA==.Kilan:BAAANQAECgUIDQAAAA==.Kimuraakid:BAAANQAECgEIAQAAAA==.',
Ko='Kocaman:BAAANQADCgIIAgAAAA==.Korladin:BAAANQADCgYICQAAAA==.',
Kr='Krutree:BAAANQAECgQIBgAAAA==.',
Ku='Kungfubean:BAAANQADCgcIBwABNQAECgEIAQAHAAAAAA==.Kuromu:BAAANQADCgMIAwAAAA==.Kutbrezbek:BAAANQABCgYIDgAAAA==.',
Ky='Kyleata:BAABNQAECn8wAAIBAAoKbRYpEwDYAQABAAoKbRYpEwDYAQAAAA==.Kylz:BAAANQABCggICQAAAA==.Kyokin:BAABNQAECn8sAAMcAAoKnxh3VwCQAgAcAAoKnxh3VwCQAgAbAAEKTgiWeQAjAAAAAA==.Kyryn:BAAANQADCgMIBwAAAA==.Kyzula:BAABNQAECn8jAAMJAAkKDRWCHQB1AQAJAAgKjhOCHQB1AQAIAAUKMxLtsgAtAQAAAA==.',
['Kê']='Kêndo:BAAANQADCgEIAQABNQAECgcIFgAbAPcMAA==.',
La='Lagrandè:BAABNQAECn8hAAIMAAgKWhr1NgAuAgAMAAgKWhr1NgAuAgAAAA==.',
Le='Leafar:BAAANQADCgQIBAAAAA==.Lextalionis:BAAANQABCgQICAAAAA==.',
Li='Liandrai:BAAANQAECgUICgAAAA==.Lillyith:BAAANQADCgcIGQAAAA==.Lilylocks:BAAANQAECgUIBgAAAA==.Littlelo:BAAANQADCgcIBwAAAA==.',
Ly='Lyanah:BAABNQAECn8vAAQVAAoKXgknNQByAQAVAAoKXgknNQByAQAfAAYKqQjhHwAZAQAOAAMKJQWvowBTAAAAAA==.Lynn:BAAANQABCgMIAwAAAA==.Lyriell:BAAANQADCgYIBgAAAA==.',
Ma='Maelius:BAAANQADCgQIBAABNQAECgkJIAAWABYYAA==.Maggrus:BAAANQABCgYIDAAAAA==.Malical:BAAANQADCgEIAQAAAA==.Manshoon:BAAANQADCgEIAQABNQAECgEIAgAHAAAAAA==.Manshöön:BAAANQADCgUIBQABNQAECgEIAgAHAAAAAA==.Matheney:BAAANQAECgUIBgABNQADCgYIBgAHAAAAAA==.Matsuzo:BAAANQADCgYIBgAAAA==.Mattlock:BAABNQAECn8hAAIYAAkKtRQnCwBFAgAYAAkKtRQnCwBFAgAAAA==.Maverick:BAAANQABCggIDAAAAA==.',
Mc='Mctubby:BAAANQADCgYJCwAAAA==.',
Md='Mdead:BAAANQABCgcICgAAAA==.',
Me='Meigz:BAAANQADCgcIGQAAAA==.Melicious:BAAANQAECgUIBQAAAA==.Melinda:BAABNQAECn8gAAIJAAgKLxiaEwC4AQAJAAgKLxiaEwC4AQAAAA==.Meta:BAAANQAECgEIAQAAAA==.Mewtwo:BAAANQAECgMIAwAAAA==.',
Mi='Milenzha:BAAANQAECgYICQAAAA==.Misaoh:BAAANQAECgQICQAAAA==.',
Mo='Momo:BAAANQAECgYIAQAAAA==.Moonreína:BAAANQAECgYIEgAAAA==.Moons:BAAANQADCgYIBgABNQAFFAUICQARAOoGAA==.Moontann:BAAANQADCggICgAAAA==.Moreia:BAAANQADCgMIAwAAAA==.Mousse:BAAANQAECgUICwAAAA==.',
Mu='Murdalok:BAAANQAECgcIBAAAAA==.',
My='Mysharona:BAAANQADCgYIBgAAAA==.',
Mz='Mzbiscuit:BAAANQADCgYIEQABNQADCgcIFQAHAAAAAA==.',
Na='Narberal:BAAANQADCggIFgABNQAECgoKPQAPACsmAA==.Nasene:BAABNQAECn8ZAAIEAAgK+CBdCwC7AgAEAAgK+CBdCwC7AgAAAA==.Nataltharion:BAAANQADCgcICQAAAA==.Natstryker:BAABNQAECn8qAAQNAAoKVSPLAABkAgANAAoKVSPLAABkAgAaAAcKigfuLgDzAAAZAAQKohePSwDLAAAAAA==.Naturemyth:BAAANQADCgYIBgAAAA==.',
Ne='Necromyst:BAAANQADCggIAQAAAA==.',
No='Noctyra:BAAANQAECgEIAQAAAA==.',
Ok='Okaminooni:BAAANQADCgcIBwAAAA==.',
Om='Omcmoneyshot:BAAANQAECgUIBQAAAA==.',
Or='Organa:BAAANQAECgUIEQAAAA==.',
Pa='Palarina:BAAANQAECgQIBwABNQAECgkJIwAaAPMeAA==.Palyomie:BAAANQAECgYIDgAAAA==.',
Ph='Pho:BAABNQAECn8nAAIDAAgKfhskOwB9AgADAAgKfhskOwB9AgAAAA==.',
Pl='Playwityou:BAAANQAECgMIBQAAAA==.Plugley:BAAANQAECgUIBgAAAA==.',
Po='Poweedman:BAAANQAECgUIAQAAAA==.',
Pu='Pumpkins:BAAANQAECgYIBgAAAA==.',
['Pë']='Përdü:BAAANQAECgMIBQAAAA==.',
Ra='Raethu:BAAANQABCgIIAgAAAA==.Ragedmage:BAAANQADCgYIBgAAAA==.Rakunn:BAAANQAECgUIDgABNQAECgkJLQAbAPEOAA==.Rastlindal:BAAANQABCgQIBAAAAA==.Ratapew:BAAANQAECgMIBQAAAA==.Ratheen:BAAANQABCggIGwAAAA==.Raytar:BAAANQAECgMIBQAAAA==.',
Re='Relaxx:BAAANQAECgMIBQAAAA==.Relthagest:BAAANQAECgMIAwAAAA==.Renn:BAAANQAECgQICAAAAA==.Retix:BAAANQABCgQICAAAAA==.',
Rh='Rhordrin:BAAANQAECgQIBAABNQAECggIGQAEAPggAA==.',
Ri='Riltonge:BAAANQAECgMIBAAAAA==.',
Ro='Roachdirt:BAAANQAECgUJDgAAAA==.Robean:BAAANQADCgQIBAAAAA==.Rogun:BAAANQAECgUICQAAAA==.Roxoxoxanne:BAAANQADCgcICgAAAA==.',
Ru='Rudger:BAAANQABCgIIAgAAAA==.Rustybray:BAABNQAECn8hAAIIAAkKZQiTigCKAQAIAAkKZQiTigCKAQAAAA==.',
Sa='Sageghost:BAAANQABCggIDwAAAA==.Sandryus:BAAANQAECgQIBwAAAA==.Sangol:BAAANQAECgUICwABNQAECggIEwAHAAAAAA==.Sarabi:BAAANQAECgUIEQAAAA==.Saralina:BAAANQAECgYICQABNQAECgoKLAAPANwgAA==.',
Sc='Schnee:BAAANQAECgUICgAAAA==.Schutzhund:BAAANQADCggIGQAAAA==.',
Se='Sekha:BAAANQADCgQIBAABNQAECgoKJAAOAEIWAA==.Sena:BAAANQADCgYIBgAAAA==.Serelia:BAAANQAECgEIAQAAAA==.',
Sh='Shadoweave:BAAANQAECgQIBQABNQAFFAcIHAABALgOAA==.Shalalia:BAAANQAECgEIAQAAAA==.Shambean:BAAANQAECgEIAQAAAA==.Shavox:BAAANQABCgUICQAAAA==.Shhanks:BAAANQAECgIIAgAAAA==.Shieldster:BAABNQAECn8vAAIbAAkKAgbKFwDNAAAbAAkKAgbKFwDNAAAAAA==.Shnizelnazee:BAAANQAECgcIEAAAAA==.',
Si='Siege:BAAANQAECgYICQABNQAECgoKLQALAJ0gAA==.Silvie:BAAANQADCgcIBwAAAA==.',
Sm='Smokeyb:BAABNQAECn8nAAIcAAoKtRGLggAjAgAcAAoKtRGLggAjAgAAAA==.',
Sn='Sneevie:BAAANQADCggIDwAAAA==.Snorehees:BAABNQAECn8bAAIBAAkKaglhmwDQAQABAAkKaglhmwDQAQAAAA==.',
So='Solaeris:BAAANQADCggIDQAAAA==.Solarth:BAAANQADCgIIAgABNQAECgkJIAARADIRAA==.Songstar:BAABNQAECn8hAAIBAAkKex9jRgCZAgABAAkKex9jRgCZAgAAAA==.Soullraven:BAAANQADCgcIEgAAAA==.',
Sp='Spaceboat:BAABNQAECn8VAAIOAAYKDw3aYQBHAQAOAAYKDw3aYQBHAQAAAA==.Sped:BAAANQAECggICAAAAA==.Spy:BAAANQADCgQIBAAAAA==.Spàz:BAAANQABCgMIAgAAAA==.',
St='Staavon:BAAANQAECgQIBwAAAA==.Stalvis:BAAANQABCgIIAgAAAA==.Starblaze:BAAANQAECgUIBwAAAA==.Steeda:BAAANQADCggICAAAAA==.Strikaelis:BAACNQAFFH8NAAIKAAYK1B6rBABlAQAKAAYK1B6rBABlAQA1AAQKfz4AAwoACgrfIykMAKQDAAoACgqkIykMAKQDACAAAQrdI/MzAGsAAAAA.',
Su='Sugarhoof:BAAANQAECgEIAgAAAA==.Sugarlick:BAAANQAECgQIDwAAAA==.Sugarpop:BAABNQAECn8sAAMPAAoK3CD2DgBTAwAPAAoK3CD2DgBTAwAcAAIKrgUjxgBrAAAAAA==.Suplazindh:BAABNQAFFH8FAAISAAUKGw9oCAB2AQASAAUKGw9oCAB2AQABNQAFFAcIGgAGABgkAA==.',
Sw='Swiftstrike:BAAANQADCggJBQAAAA==.',
Sy='Syrebriel:BAAANQADCggIEAAAAA==.',
Ta='Taediah:BAAANQAECgEIAQAAAA==.Tanjiro:BAABNQAECn8ZAAMBAAkK8heMEQDkAQABAAkK8heMEQDkAQAhAAEKegXTkQAuAAAAAA==.Tanthanalas:BAAANQADCgUIBwAAAA==.Tazetack:BAAANQAECggIAwAAAA==.',
Tg='Tgoat:BAAANQADCgEIAQAAAA==.',
Th='Thenâ:BAAANQADCgUIDQAAAA==.Theoutcast:BAAANQAECgMIBAAAAA==.Thesarius:BAAANQAECgYIBAAAAA==.',
Ti='Timeless:BAABNQAECn8aAAICAAkKCgllNQB4AQACAAkKCgllNQB4AQAAAA==.Tinymeatgang:BAAANQADCgUIBwAAAA==.',
To='Toetagger:BAABNQAECn8YAAMTAAcK2AvkfgAhAQATAAYKfAvkfgAhAQALAAcKoglJZQANAQAAAA==.Tonymaster:BAAANQAECgQIEgAAAA==.Toucannon:BAAANQAECggIEgABNQAECgoKFQAKAPkXAA==.',
Tr='Trackinoobs:BAAANQADCgcIFQAAAA==.Trashiepanda:BAAANQADCgQIBQAAAA==.Traumanurse:BAAANQADCgcIBwABNQAECgUICwAHAAAAAA==.Treealia:BAAANQABCgIIAgAAAA==.',
Ty='Tyrrial:BAAANQAECgIIAwAAAA==.Tyshus:BAAANQAECgQICQAAAA==.',
Ua='Ualmar:BAABNQAECn8aAAIDAAoKmxKgGwCcAQADAAoKmxKgGwCcAQAAAA==.',
Un='Unsc:BAAANQADCgYIBgAAAA==.',
Ur='Urgrannargru:BAAANQABCgIIAgAAAA==.',
Ut='Uthgardt:BAAANQAECgYIEQAAAA==.',
Va='Valarion:BAABNQAECn8eAAIiAAkKlQd4vACGAQAiAAkKlQd4vACGAQAAAA==.Validimus:BAAANQADCgEIAQAAAA==.Valorían:BAABNQAECn8jAAQWAAoKFBsgCgCjAgAWAAgKFB4gCgCjAgAiAAYKjxEgLQBWAQAjAAUKxRbSGAAUAQAAAA==.Vanfro:BAAANQAECgYIBAAAAA==.Varthayn:BAABNQAECn8sAAIKAAoKrx1xBwBWAgAKAAoKrx1xBwBWAgAAAA==.Varue:BAAANQAECggICAAAAA==.',
Ve='Velandriel:BAAANQADCgEIAQABNQAECgkJIAARADIRAA==.Verksquirt:BAAANQAECgYICwAAAA==.Verra:BAAANQAECgEIAQAAAA==.Vestaria:BAAANQADCgQIBAAAAA==.',
Vo='Volbain:BAABNQAECn8WAAIRAAYKfhEMSgB8AQARAAYKfhEMSgB8AQAAAA==.',
Vu='Vulpsinculta:BAABNQAECn8WAAIXAAYKcw1VbgCmAAAXAAYKcw1VbgCmAAAAAA==.',
Wa='Warboar:BAAANQADCgIIAgAAAA==.Wasntmee:BAAANQADCgYIBgABNQADCgcIFQAHAAAAAA==.',
We='Weaz:BAAANQADCggIMQAAAA==.',
Wi='Wichita:BAABNQAECn8iAAIMAAkKuRXZNgAvAgAMAAkKuRXZNgAvAgAAAA==.Wildbean:BAAANQAECgQIBwAAAA==.',
Wt='Wtfguën:BAAANQAECgUIEQAAAA==.Wtfmaki:BAAANQADCgcIEgAAAA==.',
Xa='Xaelina:BAAANQADCgQIBAAAAA==.Xanfel:BAAANQABCgQIBgAAAA==.',
Xb='Xbean:BAAANQAECgQICgAAAA==.',
Xo='Xondra:BAAANQAECgQIAwAAAA==.Xorman:BAAANQADCgcJEAAAAA==.',
Xy='Xyo:BAAANQAECgcIEAAAAA==.',
Xz='Xzairi:BAABNQAECn8kAAMOAAoKQhZpKgCFAgAOAAoKQhZpKgCFAgAVAAEKoQm8fgAiAAAAAA==.',
Yn='Yngvar:BAAANQADCgQIBQAAAA==.',
Ze='Zenezal:BAAANQAECgQIBAAAAA==.',
Zi='Zinora:BAAANQADCgcICgAAAA==.Ziyue:BAAANQAECggIDwAAAA==.',
Zn='Zn:BAABNQAECn8eAAIPAAgKCxUBUwAhAgAPAAgKCxUBUwAhAgAAAA==.',
Zo='Zovaal:BAAANQABCgYIBgAAAA==.',
['Àd']='Àddixt:BAAANQABCgIIAgAAAA==.',
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
