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

local lookup = {'Mage-Arcane','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','Druid-Balance','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Blood','DeathKnight-Unholy','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Druid-Restoration','Druid-Guardian','Hunter-Survival','Druid-Feral','Mage-Frost','Warrior-Arms','Warrior-Fury',}
local provider = {region='US',realm='Misha',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abàddón:BAAANQADCgYIDAAAAA==.',
Ac='Acidburn:BAAANQADCgYICgAAAA==.',
Al='Alluna:BAAANQAECgEIAQAAAA==.Alorillan:BAAANQAECgMIBAAAAA==.Altabrew:BAAANQADCgMIAwAAAA==.Altair:BAAANQAECgYIDQAAAA==.',
An='Anker:BAAANQAECgEIAQABNQAFFAIIBgABAN4bAA==.Anomalien:BAAANQAECgMIAwAAAA==.',
Ap='Apocalyspe:BAAANQAECgcIEAAAAA==.Appless:BAABNQAECn8xAAMCAAkKixToFwCTAgACAAkKixToFwCTAgADAAgKSxVCTwAzAgAAAA==.',
Ar='Aridella:BAAANQAECgYIDwAAAA==.',
Az='Azusie:BAABNQAECn8hAAIEAAgKMRBYFQAPAgAEAAgKMRBYFQAPAgAAAA==.',
Ba='Bablepopye:BAAANQAECgMIAwAAAA==.Baddate:BAAANQAECgEIAQAAAA==.Baddragøn:BAABNQAECn8fAAMFAAgKwBwREACmAgAFAAgKwBwREACmAgAGAAIKywJhNwBPAAAAAA==.Balthaas:BAAANQAECgcIEAAAAA==.Bangen:BAAANQAECgUIBgAAAA==.Baulters:BAAANQADCgYIBgAAAA==.Baylor:BAAANQADCgUIBQAAAA==.',
Bc='Bckstabber:BAAANQADCgQIBAAAAA==.',
Be='Beenn:BAAANQADCgcJDAAAAA==.Belael:BAAANQADCgcIBwAAAA==.Benrent:BAAANQADCgEIAQABNQADCgcJDAAHAAAAAA==.',
Bi='Biinks:BAAANQADCggIEwAAAA==.Billywitchdr:BAABNQAECn8dAAMIAAgK5hYLfQCoAQAIAAcKlxULfQCoAQAJAAEK6QzjGQEzAAAAAA==.Bisharp:BAAANQADCggICAABNQAECggIEgAHAAAAAA==.',
Bl='Blazingelf:BAAANQADCgMIAwAAAA==.Blindedbý:BAAANQABCgQIBAAAAA==.Bluetoykawi:BAABNQAECn8rAAIKAAkK5BClNAAEAgAKAAkK5BClNAAEAgAAAA==.',
Bo='Bonedelivery:BAAANQABCgIIAgAAAA==.',
Br='Breloom:BAAANQAECgYIBgABNQAECggIEgAHAAAAAA==.',
Bu='Bulkathos:BAAANQAECgEIAgABNQAECggIEQAHAAAAAA==.Bulliedgair:BAAANQADCgMIAwABNQAECgcICgAHAAAAAA==.',
['Bé']='Béorñ:BAAANQAECggIDgAAAA==.',
Ca='Cariandria:BAAANQADCgYIBgAAAA==.',
Ch='Charita:BAEANQAFFAIIAgAAAA==.Charming:BAEANQAECgcJEgABNQAFFAIIAgAHAAAAAA==.',
Cl='Clanker:BAAANQAECgQIAwAAAA==.Clark:BAAANQADCgEIAQAAAA==.Clouds:BAAANQADCggICAABNQAECgcIEAAHAAAAAA==.',
Co='Coffeecat:BAAANQADCgYIEQABNQAECgEIAQAHAAAAAA==.Contrlurself:BAAANQADCgQIBAABNQAECggIHwALAJQQAA==.Cowret:BAABNQAECn8tAAIMAAkKSCOkBQCfAwAMAAkKSCOkBQCfAwAAAA==.',
Cr='Crowleyy:BAAANQADCgUIBQAAAA==.',
Da='Dademurphy:BAAANQADCgIIAgAAAA==.Darc:BAAANQADCgcIBwAAAA==.Darkfoxdemon:BAABNQAECn8fAAQNAAgKnxh1CwAUAgANAAgKnxh1CwAUAgAOAAYKEw4nWAAiAQAPAAYKXwWcSgD8AAAAAA==.Darkfoxgrime:BAAANQADCgYIBgABNQAECggIHwANAJ8YAA==.Darkjager:BAAANQADCgcIBwAAAA==.Darkstaff:BAAANQADCgMIAwAAAA==.Darkways:BAAANQADCgYIBgAAAA==.Darlah:BAAANQADCggIFwAAAA==.Dayyva:BAAANQAECgQIDQAAAA==.',
De='Deadcobra:BAAANQADCgMIBQAAAA==.Deangilberry:BAAANQADCgQICQAAAA==.Deathbyelf:BAAANQADCgcIBwAAAA==.Delindeyn:BAAANQADCgcIGQAAAA==.Deltria:BAAANQAECgMIBAAAAA==.Demonrot:BAAANQADCggIFgAAAA==.Deviltank:BAAANQADCgQIBAAAAA==.',
Di='Diaboliq:BAAANQAECgMIBgAAAA==.Diefenbaker:BAAANQADCgcIDgAAAA==.Digmyearth:BAAANQADCgYIBgAAAA==.Dilea:BAAANQAECgEIAQAAAA==.',
Dk='Dkon:BAABNQAECn8dAAMQAAcK1RsAQgDyAQAQAAcKHRgAQgDyAQARAAUKzBgxewArAQAAAA==.',
Do='Doppler:BAAANQAECgYIEQAAAA==.',
Dr='Dracomyst:BAAANQADCggIAgAAAA==.Driver:BAEANQAECggICgAAAA==.Drruz:BAAANQADCggIHgAAAA==.',
Du='Dumbledorr:BAAANQAECgIIAgAAAQ==.Durzoe:BAAANQAECgYIEgAAAA==.',
Dv='Dvsmage:BAAANQADCgcIDQABNQAECgEIAQAHAAAAAA==.',
Dw='Dwod:BAABNQAECn8gAAMKAAgK8RPaPgDJAQAKAAcKnRXaPgDJAQAQAAQKLgfqnwCUAAAAAA==.',
['Dí']='Díscø:BAEBNQAECn8aAAICAAkKjxi8GQB9AgACAAkKjxi8GQB9AgAAAA==.',
Ed='Edrian:BAAANQADCgYIBgAAAA==.',
Er='Errita:BAAANQADCgEIAQAAAA==.Ershulie:BAAANQABCggIJgAAAA==.',
Ev='Evilcoffee:BAAANQADCgYIBgABNQAECgEIAQAHAAAAAA==.',
Ew='Ewt:BAABNQAECn8eAAISAAgK8RbPEwDlAQASAAgK8RbPEwDlAQAAAA==.',
Fa='Fastnine:BAAANQAECggIDQABNQAECggIEgAHAAAAAA==.',
Fe='Felhound:BAAANQAECgMIBAAAAA==.Felussi:BAABNQAECn8cAAMTAAgK5xEDfQDpAQATAAgK5xEDfQDpAQAUAAEKtRS0cAA+AAAAAA==.',
Fi='Finnster:BAABNQAECn8pAAIVAAcKvQcSvwB/AQAVAAcKvQcSvwB/AQAAAA==.Fionna:BAAANQADCgQIBAAAAA==.',
Fl='Flameon:BAAANQABCgcICgAAAA==.Flarixi:BAAANQADCgcICgAAAA==.Fleurminator:BAAANQAECgYICwAAAA==.',
Fr='Fractor:BAAANQADCgYICwAAAA==.Frieia:BAAANQAECgUIDAAAAA==.Frostface:BAAANQADCgcICwAAAA==.Frozenjade:BAAANQADCgIIAgAAAA==.',
Fu='Fubuki:BAACNQAFFH8RAAMWAAUKmBGmCgAOAQAWAAQKmBGmCgAOAQAXAAUKsQDxBgDVAAA1AAQKfywAAxYACQo5IToQAOACABYACQo5IToQAOACABcAAwr7Bk8pAHUAAAAA.',
Ga='Galapriest:BAAANQAECgEIAQAAAA==.Galarína:BAABNQAECn8cAAMYAAgKGiBxDAC5AgAYAAgKGiBxDAC5AgAWAAEK0AvcaQAzAAAAAA==.Gallitha:BAAANQADCgUIBQAAAA==.Gamewarden:BAAANQADCggIDgABNQAECggIJQADAIgaAA==.Gandora:BAABNQAECn8dAAQRAAgKaA2cXACZAQARAAgKaA2cXACZAQAKAAMKpwY2jQB4AAAQAAEKAACIygAxAAAAAA==.Gauge:BAAANQAECgcIDQABNQAECggICAAHAAAAAA==.',
Ge='Getoffme:BAAANQAECgUICAAAAA==.',
Gk='Gkmc:BAABNQAFFH8FAAIRAAMKUCBoDgAhAQARAAMKUCBoDgAhAQABNQAFFAcIDwABAA0hAA==.',
Go='Gobbomode:BAAANQADCgYIBgAAAA==.Gorbino:BAABNQAECn8tAAIZAAkKeiS9AgCcAwAZAAkKeiS9AgCcAwAAAA==.',
Gr='Greasemunkey:BAAANQAECgUIDwAAAA==.Gretchaen:BAAANQAECgQICAAAAA==.Griiv:BAABNQAECn8tAAIaAAgKQSaVFwBlAwAaAAgKQSaVFwBlAwABNQAECgkJGgAEAJ0kAA==.Grislydemon:BAAANQADCggICAAAAA==.Grislydoom:BAAANQAECgEIAQAAAA==.Grislyshock:BAABNQAECn8kAAIEAAgK5RzCDACgAgAEAAgK5RzCDACgAgAAAA==.',
Ha='Hairymartini:BAAANQADCgMIAwABNQAECggIIQAIAIsiAA==.Hakunamatata:BAAANQADCggIDAAAAA==.Hamburger:BAAANQAECgUICgAAAA==.Hammerhard:BAAANQADCgIIAgAAAA==.Harcones:BAAANQADCgMJAwAAAA==.',
He='Heights:BAAANQADCgMIAwABNQAECgQIBgAHAAAAAA==.Heliosan:BAABNQAECn8dAAIDAAcKDxdcawDYAQADAAcKDxdcawDYAQAAAA==.Hellelements:BAAANQAECggICAAAAA==.Hemoblast:BAAANQADCgIIAgAAAA==.Hemolight:BAAANQADCgYIDAAAAA==.',
Ho='Hojiitaa:BAAANQADCgUIBQAAAA==.Holybean:BAAANQADCgcIBwABNQAECgEIAQAHAAAAAA==.',
Hr='Hrshoo:BAAANQAFFAEIAQAAAA==.',
['Hä']='Hädês:BAAANQAECgMIAwAAAA==.',
Je='Jeannaah:BAAANQAECgYICQABNQAECgUIBgAHAAAAAA==.Jekyl:BAAANQADCgMIAwAAAA==.Jekyll:BAAANQADCgUIBQAAAA==.',
Jh='Jharia:BAAANQADCgYIBgAAAA==.',
Ju='Judgment:BAAANQABCgEJAQAAAA==.',
['Já']='Jáckyboy:BAABNQAECn8oAAMbAAkKFSA0GQBvAgAbAAcKQR40GQBvAgALAAgK5xWHRQDWAQAAAA==.',
Ka='Kalestra:BAABNQAECn8bAAMLAAgKLRcvNABDAgALAAgKLRcvNABDAgAcAAcK1wjlMAAQAQAAAA==.Kalithos:BAAANQAECgMIBAAAAA==.Kayelalynn:BAABNQAECn8fAAILAAgKlBBkRQDXAQALAAgKlBBkRQDXAQAAAA==.Kaymoo:BAAANQABCgIIAgAAAA==.',
Kd='Kd:BAAANQADCggIDAAAAA==.',
Ke='Keeghor:BAABNQAECn8aAAIEAAkKnSTaAgB2AwAEAAkKnSTaAgB2AwAAAA==.Kelana:BAAANQAECgMIAwAAAA==.Kendô:BAAANQADCgYIBwABNQAECgYIEAAHAAAAAA==.Keyahi:BAAANQAFFAEIAQABNQAECgEIAQAHAAAAAA==.',
Kh='Khaean:BAABNQAECn8hAAIdAAcKxB+yBACRAgAdAAcKxB+yBACRAgAAAA==.',
Ki='Kickandpunch:BAAANQAECgcIEAAAAA==.Kiilan:BAAANQADCgEIAQAAAA==.Kilan:BAAANQAECgUICQAAAA==.Kimuraakid:BAAANQAECgEIAQAAAA==.',
Ko='Kocaman:BAAANQADCgIIAgAAAA==.Korladin:BAAANQADCgYICQAAAA==.',
Kr='Krutree:BAAANQAECgQIBgAAAA==.',
Ku='Kungfubean:BAAANQADCgcIBwABNQAECgEIAQAHAAAAAA==.Kuromu:BAAANQADCgMIAwAAAA==.Kutbrezbek:BAAANQABCgYIDgAAAA==.',
Ky='Kyleata:BAABNQAECn8nAAIVAAkKZhfVNQDHAgAVAAkKZhfVNQDHAgAAAA==.Kylz:BAAANQABCggICQAAAA==.Kyokin:BAABNQAECn8mAAMaAAkKOxkFVgCQAgAaAAkKOxkFVgCQAgAZAAEKTgg3eAAjAAAAAA==.Kyryn:BAAANQADCgMIBQAAAA==.Kyzula:BAABNQAECn8ZAAMJAAcKFBLrlABPAQAJAAYKChDrlABPAQAIAAUKygyEsAAtAQAAAA==.',
['Kê']='Kêndo:BAAANQADCgEIAQABNQAECgYIEAAHAAAAAA==.',
La='Lagrandè:BAABNQAECn8dAAIQAAgKWhpMNgAvAgAQAAgKWhpMNgAvAgAAAA==.',
Le='Lextalionis:BAAANQABCgQICAAAAA==.',
Li='Liandrai:BAAANQAECgQIBgAAAA==.Lillyith:BAAANQADCgcIFQAAAA==.Lilylocks:BAAANQAECgUIBgAAAA==.Littlelo:BAAANQADCgcIBwAAAA==.',
Ly='Lyanah:BAABNQAECn8pAAQbAAgKKAqSNABxAQAbAAgKKAqSNABxAQAeAAYKgwg4HwAcAQALAAIKJQXgoQBTAAAAAA==.Lynn:BAAANQABCgIIAgAAAA==.Lyriell:BAAANQADCgYIBgAAAA==.',
Ma='Maelius:BAAANQADCgQIBAABNQAECggIHgASAPEWAA==.Maggrus:BAAANQABCgYIDAAAAA==.Malical:BAAANQADCgEIAQAAAA==.Manshöön:BAAANQADCgUIBQABNQAECgEIAQAHAAAAAA==.Matheney:BAAANQAECgUIBgABNQADCgYIBgAHAAAAAA==.Mattlock:BAABNQAECn8lAAIUAAgKbxXDCgBKAgAUAAgKbxXDCgBKAgAAAA==.Maverick:BAAANQABCggIDAAAAA==.',
Mc='Mctubby:BAAANQADCgYJCwAAAA==.',
Md='Mdead:BAAANQABCgcICAAAAA==.',
Me='Meigz:BAAANQADCgcIFQAAAA==.Melicious:BAAANQAECgQIBAAAAA==.Melinda:BAABNQAECn8bAAIJAAcKURbVaADOAQAJAAcKURbVaADOAQAAAA==.Mewtwo:BAAANQAECgMIAwAAAA==.',
Mi='Milenzha:BAAANQAECgUIBQAAAA==.Misaoh:BAAANQAECgQICQAAAA==.',
Mo='Momo:BAAANQAECgYIAQAAAA==.Moonreína:BAAANQAECgUIDgAAAA==.Moons:BAAANQADCgYIBgABNQAFFAQIBAAHAAAAAA==.Moontann:BAAANQADCggICgAAAA==.Moreia:BAAANQADCgMIAwAAAA==.Mousse:BAAANQAECgQICAAAAA==.',
Mu='Murdalok:BAAANQAECgYIBAAAAA==.',
My='Mysharona:BAAANQADCgYIBgAAAA==.',
Mz='Mzbiscuit:BAAANQADCgYIEQABNQADCgcIFQAHAAAAAA==.',
Na='Narberal:BAAANQADCggIFgABNQAECgkJGAAeAFUYAA==.Nasene:BAABNQAECn8ZAAIEAAgK+CAaCwC9AgAEAAgK+CAaCwC9AgAAAA==.Nataltharion:BAAANQADCgcICQAAAA==.Natstryker:BAABNQAECn8hAAQXAAkKsCPTAQCcAwAXAAkKsCPTAQCcAwAYAAYKKAdhLgDzAAAWAAMKahiVSgDLAAAAAA==.Naturemyth:BAAANQADCgYIBgAAAA==.',
Ne='Necromyst:BAAANQADCggIAQAAAA==.',
No='Noctyra:BAAANQADCgcIDQAAAA==.',
Ok='Okaminooni:BAAANQADCgcIBwAAAA==.',
Om='Omcmoneyshot:BAAANQAECgEIAQAAAA==.',
Or='Organa:BAAANQAECgUIDQAAAA==.',
Pa='Palarina:BAAANQAECgQIBwABNQAECggIHAAYABogAA==.Palyomie:BAAANQAECgYIDgAAAA==.',
Ph='Pho:BAABNQAECn8lAAIDAAgKiBonOgB9AgADAAgKiBonOgB9AgAAAA==.',
Pl='Playwityou:BAAANQAECgMIBAAAAA==.Plugley:BAAANQAECgUIBgAAAA==.',
Po='Poweedman:BAAANQAECgUIAQAAAA==.',
Pu='Pumpkins:BAAANQAECgYIBgAAAA==.',
['Pë']='Përdü:BAAANQAECgMIBAAAAA==.',
Ra='Raethu:BAAANQABCgIIAgAAAA==.Rakunn:BAAANQAECgUICgABNQAECgcIKgAZAC0RAA==.Ratapew:BAAANQAECgMIBAAAAA==.Ratheen:BAAANQABCggIFQAAAA==.Raytar:BAAANQAECgMIBQAAAA==.',
Re='Relaxx:BAAANQAECgIIAgAAAA==.Relthagest:BAAANQAECgMIAwAAAA==.Renn:BAAANQAECgQICAAAAA==.Retix:BAAANQABCgQICAAAAA==.',
Rh='Rhordrin:BAAANQAECgQIBAABNQAECggIGQAEAPggAA==.',
Ri='Riltonge:BAAANQAECgMIBAAAAA==.',
Ro='Roachdirt:BAAANQAECgUJDgAAAA==.Robean:BAAANQADCgQJBAAAAA==.Rogun:BAAANQAECgUIBQAAAA==.Roxoxoxanne:BAAANQADCgcICgAAAA==.',
Ru='Rudger:BAAANQABCgEIAQAAAA==.Rustybray:BAABNQAECn8kAAIIAAgK+wj7hgCOAQAIAAgK+wj7hgCOAQAAAA==.',
Sa='Sageghost:BAAANQABCggIDwAAAA==.Sandryus:BAAANQAECgQIBwAAAA==.Sangol:BAAANQAECgUIBgABNQAECggIEwAHAAAAAA==.Sarabi:BAAANQAECgUIDQAAAA==.Saralina:BAAANQAECgYICQABNQAECgkJKAAMAFEhAA==.',
Sc='Schnee:BAAANQAECgUICgAAAA==.Schutzhund:BAAANQADCggIGQAAAA==.',
Se='Sekha:BAAANQADCgQIBAABNQAECgkJIgALAP4VAA==.Sena:BAAANQADCgYIBgAAAA==.Serelia:BAAANQADCgYIBgAAAA==.',
Sh='Shadoweave:BAAANQAECgQIBQABNQAFFAYIGgAVAPUQAA==.Shalalia:BAAANQAECgEIAQAAAA==.Shambean:BAAANQAECgEIAQAAAA==.Shavox:BAAANQABCgUICQAAAA==.Shhanks:BAAANQAECgIIAgAAAA==.Shieldster:BAABNQAECn8jAAIZAAkKAgY2NgAxAQAZAAkKAgY2NgAxAQAAAA==.Shnizelnazee:BAAANQAECgYIDwAAAA==.',
Si='Siege:BAAANQAECgQIBAABNQAECgkJKQAKAKIjAA==.Silvie:BAAANQADCgcIBwAAAA==.',
Sm='Smokeyb:BAABNQAECn8kAAIaAAkKEBNvgAAjAgAaAAkKEBNvgAAjAgAAAA==.',
Sn='Sneevie:BAAANQADCggIDwAAAA==.Snorehees:BAABNQAECn8eAAIVAAgKZQq3lwDUAQAVAAgKZQq3lwDUAQAAAA==.',
So='Solaeris:BAAANQADCggIDQAAAA==.Solarth:BAAANQADCgIIAgABNQAECggIHQAOAIIRAA==.Songstar:BAABNQAECn8fAAIVAAgKzB90RQCZAgAVAAgKzB90RQCZAgAAAA==.Soullraven:BAAANQADCgYIDwAAAA==.',
Sp='Spaceboat:BAAANQAECgUIEQAAAA==.Sped:BAAANQAECgYIBgAAAA==.Spy:BAAANQADCgQIBAAAAA==.Spàz:BAAANQABCgMIAgAAAA==.',
St='Staavon:BAAANQAECgQIBgAAAA==.Stalvis:BAAANQABCgIIAgAAAA==.Starblaze:BAAANQAECgUIBwAAAA==.Steeda:BAAANQADCggICAAAAA==.Strikaelis:BAACNQAFFH8IAAIBAAUK/hxGGwCdAQABAAUK/hxGGwCdAQA1AAQKfzkAAwEACQp2JNgLAKYDAAEACQozJNgLAKYDAB8AAQrdI08zAGsAAAAA.',
Su='Sugarhoof:BAAANQAECgEIAgAAAA==.Sugarlick:BAAANQAECgQICwAAAA==.Sugarpop:BAABNQAECn8oAAIMAAkKUSHLDgBTAwAMAAkKUSHLDgBTAwAAAA==.Suplazindh:BAAANQAFFAQIBAABNQAFFAcIGgAGABgkAA==.',
Sw='Swiftstrike:BAAANQADCggJBQAAAA==.',
Sy='Sylvqt:BAAANQABCgYICQAAAA==.Syrebriel:BAAANQADCggIEAAAAA==.',
Ta='Taediah:BAAANQAECgEIAQAAAA==.Tanjiro:BAAANQAECggIDgAAAA==.Tanthanalas:BAAANQADCgUIBwAAAA==.Tazetack:BAAANQAECggIAgAAAA==.',
Tg='Tgoat:BAAANQADCgEIAQAAAA==.',
Th='Thenâ:BAAANQADCgUICQAAAA==.Theoutcast:BAAANQADCgIJAgAAAA==.Thesarius:BAAANQAECgYIBAAAAA==.',
Ti='Timeless:BAAANQAECggIEQAAAA==.Tinymeatgang:BAAANQADCgUIBwAAAA==.',
To='Toetagger:BAAANQAECgUIEgAAAA==.Tonymaster:BAAANQAECgQIDgAAAA==.Toucannon:BAAANQAECggIEgAAAA==.',
Tr='Trackinoobs:BAAANQADCgcIFQAAAA==.Trashiepanda:BAAANQADCgQIBQAAAA==.Traumanurse:BAAANQADCgcIBwABNQAECgQICAAHAAAAAA==.Treealia:BAAANQABCgIIAgAAAA==.',
Ty='Tyrrial:BAAANQAECgIIAwAAAA==.Tyshus:BAAANQAECgIIBgAAAA==.',
Ua='Ualmar:BAAANQAECggIEAAAAA==.',
Ur='Urgrannargru:BAAANQABCgIIAgAAAA==.',
Ut='Uthgardt:BAAANQAECgYIEQAAAA==.',
Va='Valarion:BAABNQAECn8dAAIgAAgKqghUugCGAQAgAAgKqghUugCGAQAAAA==.Validimus:BAAANQADCgEIAQAAAA==.Valorían:BAABNQAECn8cAAQSAAkKCh0BCgCjAgASAAgKFB4BCgCjAgAhAAQKxRanGAAUAQAgAAIKkA/lLwFtAAAAAA==.Vanfro:BAAANQAECgYIBAAAAA==.Varthayn:BAABNQAECn8lAAIBAAgKthrFgQB6AgABAAgKthrFgQB6AgAAAA==.Varue:BAAANQAECggICAAAAA==.',
Ve='Velandriel:BAAANQADCgEIAQABNQAECggIHQAOAIIRAA==.Verksquirt:BAAANQAECgYICwAAAA==.Verra:BAAANQAECgEIAQAAAA==.Vestaria:BAAANQADCgQIBAAAAA==.',
Vo='Volbain:BAAANQAECgUIDgAAAA==.',
Vu='Vulpsinculta:BAAANQAECgUIDQAAAA==.',
Wa='Warboar:BAAANQADCgIIAgAAAA==.Wasntmee:BAAANQADCgYJBgABNQADCgcIFQAHAAAAAA==.',
We='Weaz:BAAANQADCggIKgAAAA==.',
Wi='Wichita:BAABNQAECn8lAAIQAAgK/xeRMQBHAgAQAAgK/xeRMQBHAgAAAA==.Wildbean:BAAANQAECgQIBAAAAA==.',
Wt='Wtfguën:BAAANQAECgUIDQAAAA==.Wtftiff:BAAANQADCgcIDgAAAA==.',
Xa='Xanfel:BAAANQABCgQIBgAAAA==.',
Xb='Xbean:BAAANQAECgQICQAAAA==.',
Xo='Xondra:BAAANQAECgMIAwABNQAECgYICgAHAAAAAA==.Xorman:BAAANQADCgcJEAAAAA==.',
Xy='Xyo:BAAANQAECgcIEAAAAA==.',
Xz='Xzairi:BAABNQAECn8iAAMLAAkK/hXwKQCFAgALAAkK/hXwKQCFAgAbAAEKoQmyfAAiAAAAAA==.',
Yn='Yngvar:BAAANQADCgQIBQAAAA==.',
Ze='Zenezal:BAAANQAECgQIBAAAAA==.',
Zi='Zinora:BAAANQADCgcICgAAAA==.Ziyue:BAAANQAECggIDgAAAA==.',
Zn='Zn:BAABNQAECn8eAAIMAAgKCxUmUgAhAgAMAAgKCxUmUgAhAgAAAA==.',
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
