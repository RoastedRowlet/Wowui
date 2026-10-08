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

local lookup = {'Mage-Arcane','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Mage-Frost','Druid-Balance','Druid-Feral','DeathKnight-Blood','Mage-Fire','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Restoration','Paladin-Retribution','Paladin-Protection','DeathKnight-Unholy','Monk-Mistweaver','Monk-Windwalker','Paladin-Holy','Priest-Shadow','Evoker-Devastation','Evoker-Preservation','Hunter-Survival',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=53,date='2026-10-06',data={Al='Aletalle:BAAANQAECgQIBAAAAA==.Allice:BAABNQAECoEUAAIBAAcKzhX3sgD6AQABAAcKzhX3sgD6AQAAAA==.Alsheyra:BAAANQADCgYICgAAAA==.Alterion:BAAANQABCgQICgAAAA==.',
An='Anxious:BAAANQADCgYIEAAAAA==.',
As='Ashwalker:BAAANQAECgcIBwAAAA==.',
Au='Aughyst:BAAANQAECgMJBwAAAA==.Augnyxia:BAAANQAECgQICgAAAA==.Augtysm:BAAANQADCggICAAAAA==.Augy:BAAANQAECgQIBAAAAA==.',
Ba='Bandobras:BAAANQADCgcIDgAAAA==.',
Bh='Bhorg:BAAANQADCgMIAwAAAA==.',
Bl='Blackdust:BAAANQADCggIDQAAAA==.Blasters:BAAANQADCgcIEgAAAA==.Bloodjury:BAAANQAECgUICwAAAA==.Blossom:BAAANQABCgIIAgABNQABCgYICwACAAAAAA==.',
Bo='Boejo:BAAANQADCgUIBQAAAA==.Borellus:BAAANQABCgUICQAAAA==.',
Br='Broken:BAAANQADCgYIBgAAAA==.',
Bu='Bunga:BAAANQAECgEIAQAAAA==.Bungis:BAAANQAECgcIDQAAAA==.Bushetti:BAAANQAFFAEIAQAAAA==.',
Ca='Casperface:BAABNQAECoEgAAMDAAkKnxFKYgDKAQADAAgKVQ9KYgDKAQAEAAIKpAnN8QBUAAAAAA==.Cazisham:BAAANQAECgQICwAAAA==.',
Ce='Cestus:BAAANQAECgcJDQAAAA==.Cevianne:BAAANQAECgIIAgAAAA==.',
Ci='Ciaphis:BAAANQAECgQIBgAAAA==.Cinnabuns:BAAANQADCgQIAwAAAA==.',
Co='Coal:BAAANQAECgYIEwAAAA==.Coltonater:BAACNQAFFIEHAAIBAAUKThLmFwCRAQABAAUKThLmFwCRAQA1AAQKgTIAAgEACQpMJHQIALUDAAEACQpMJHQIALUDAAAA.',
['Cá']='Cáséy:BAACNQAFFIEIAAIFAAQK2xYaAQBDAQAFAAQK2xYaAQBDAQA1AAQKgScAAwUACQoSIiMCADUDAAUACQoSIiMCADUDAAEAAgqfCEGJAXQAAAAA.',
['Cä']='Cäsey:BAAANQADCgMIAwABNQAFFAQICAAFANsWAA==.',
Da='Darkshroud:BAAANQADCgYIDgAAAA==.Datbi:BAABNQAECoEgAAMGAAgKdBNDOQD8AQAGAAgKhBJDOQD8AQAHAAEKVhcgMQBJAAAAAA==.Daugi:BAAANQAECgYICAAAAA==.',
De='Deathangel:BAAANQAECgMIAwAAAA==.Deathdeamon:BAAANQADCgMIAwAAAA==.Deathdylan:BAABNQAECoEhAAIIAAkKWh6CFADzAgAIAAkKWh6CFADzAgAAAA==.Delice:BAAANQAECgQIBQAAAA==.Demonikal:BAAANQAECgQIBAAAAA==.Demítríus:BAAANQAECgYIBwAAAA==.Dethh:BAAANQAECgUIEQAAAA==.',
Di='Didona:BAAANQADCgYIBgAAAA==.Distortion:BAAANQADCggIDwAAAA==.Divineflava:BAAANQADCgIIAgABNQAECgkJNwABALMiAA==.',
Do='Dobby:BAAANQADCggIDQAAAA==.',
Dr='Drakeo:BAAANQAECgYIDgAAAA==.Draximus:BAAANQAECgUIBwAAAA==.Drougenin:BAAANQADCgMIBgABNQAECgYIEwACAAAAAA==.Drpumper:BAAANQAECgcIEwAAAA==.Druqz:BAABNQAECoEfAAIFAAkK7BOBCAAoAgAFAAkK7BOBCAAoAgAAAA==.Druski:BAAANQABCgQIBAAAAA==.Drævn:BAABNQAECoEfAAIJAAYKCR1hAgADAgAJAAYKCR1hAgADAgAAAA==.',
Du='Dum:BAACNQAFFIENAAQKAAUKQR1GAgDsAAAKAAMKbxpGAgDsAAALAAIKYyH3CwDFAAAMAAIKvhgeEgCWAAA1AAQKgSYABAsACQoGIxcPAOsCAAsACApzIhcPAOsCAAoABwpVHOYIADECAAwAAwpBIopPAB8BAAAA.Duragon:BAAANQAECgUIEwAAAA==.Durkagon:BAAANQAECgQIBwAAAA==.',
Dw='Dwimbear:BAAANQABCgIIAgAAAA==.Dwimhoof:BAAANQADCgMIAwAAAA==.Dwinnet:BAAANQABCgQICQAAAA==.',
El='Eldin:BAABNQAECoEfAAMNAAkK2SL+AABRAwANAAgKiCT+AABRAwAOAAEKYRXm1wBOAAAAAA==.',
En='Endofdays:BAAANQAECgEIAQAAAA==.Enro:BAABNQAECoEkAAIMAAkK/Rd1HACRAgAMAAkK/Rd1HACRAgAAAA==.',
Er='Erovia:BAABNQAECoEjAAIPAAgKYhGoaQAUAgAPAAgKYhGoaQAUAgAAAA==.',
Es='Esclipse:BAAANQADCgYIBgAAAA==.',
Et='Etclock:BAAANQADCgYIBgAAAA==.',
Fa='Farruq:BAAANQAECgUJCwAAAA==.Fathermoo:BAAANQAECgEIAQAAAA==.',
Fe='Feelsbadmang:BAAANQADCgQIBAABNQAECgcIEQACAAAAAA==.Fellz:BAAANQADCgIIAgAAAA==.Ferer:BAEANQADCgYIBgABNQAECgkJJgAQALwYAA==.Ferian:BAAANQAECgQIDwAAAA==.',
Fl='Flavaflare:BAABNQAECoE3AAIBAAkKsyJYFgBzAwABAAkKsyJYFgBzAwAAAA==.',
Fo='Foodex:BAAANQAFFAEIAQAAAA==.Fourleaf:BAABNQAECoEkAAIQAAkKuBpXEgC9AgAQAAkKuBpXEgC9AgAAAA==.',
Fr='Frogplushy:BAAANQAECgMIAwAAAA==.',
Fu='Furlock:BAAANQAECgMIBgAAAA==.Furral:BAABNQAECoEiAAIHAAkKRRvCBgDTAgAHAAkKRRvCBgDTAgAAAA==.Furretc:BAAANQADCgEIAQAAAA==.',
Ga='Gaeth:BAABNQAECoEgAAIRAAgKUxTEIAD3AQARAAgKUxTEIAD3AQAAAA==.',
Ge='Gengiss:BAAANQADCgQIBAAAAA==.',
Gl='Gleg:BAACNQAFFIEKAAMEAAMKrBknEwDqAAAEAAMKrBknEwDqAAADAAIKughfIQCMAAA1AAQKgSMAAwQACQoTIuIRACEDAAQACQoTIuIRACEDAAMAAQpzFg8OATsAAAAA.',
Go='Goodside:BAAANQADCgYIDAAAAA==.',
Gr='Grimthebrave:BAAANQAECggIDgAAAA==.Grimthecruel:BAABNQAECoEaAAMLAAkKsRNTHQBNAgALAAkKqxNTHQBNAgAMAAEK+RT2fQBAAAAAAA==.Gripless:BAAANQADCgQIBAAAAA==.Griselden:BAABNQAECoEkAAILAAkKVRv3EADVAgALAAkKVRv3EADVAgAAAA==.Grizzlyras:BAAANQADCggICAAAAA==.',
Gu='Gub:BAAANQAECgQJCwAAAA==.',
Ha='Hannsollo:BAAANQADCgMIAwAAAA==.',
Ho='Holyshock:BAAANQABCgYIEAAAAA==.',
['Hâ']='Hâmburger:BAAANQADCgIIAgAAAA==.',
Ir='Iridessa:BAAANQADCgcIEgAAAA==.',
Is='Ishpoo:BAABNQAECoElAAMSAAkKPxYbWABlAgASAAkKPxYbWABlAgATAAEKywRHcQAdAAAAAA==.',
Ja='Jangarinna:BAAANQADCgQIBAAAAA==.',
Ji='Jip:BAAANQAECgQIBAAAAA==.',
Jl='Jlawq:BAAANQADCgUJBQAAAA==.Jlawzzs:BAABNQAECoEeAAIEAAgKsRfwQAAyAgAEAAgKsRfwQAAyAgAAAA==.',
Jo='Job:BAABNQAECoExAAIMAAkK2CURAwC6AwAMAAkK2CURAwC6AwAAAA==.',
Ju='Judgim:BAAANQADCgQIBAAAAA==.Judoriel:BAAANQAECgEIAQAAAA==.Junkyard:BAAANQADCgcIBwAAAA==.',
Ka='Kaimin:BAABNQAECoEhAAIUAAcKoSHvJgB/AgAUAAcKoSHvJgB/AgAAAA==.Karthas:BAAANQADCgUIBQAAAA==.Karuun:BAAANQAECgQIBAABNQAECgUIDQACAAAAAA==.',
Ke='Kezeshi:BAAANQAECgcIEQAAAA==.',
Kh='Khaidralulz:BAABNQAECoEnAAIEAAkKaA7EVgDfAQAEAAkKaA7EVgDfAQAAAA==.Khonsu:BAAANQAECgIIAgAAAA==.',
Ki='Kiba:BAAANQAECgQIEAAAAA==.',
Kr='Kraegen:BAAANQAECgcIDQAAAA==.',
Ky='Kyofu:BAABNQAECoEuAAMVAAkKMxtFCgDIAgAVAAkKMxtFCgDIAgAWAAMKIArlTwB7AAAAAA==.',
La='Larenta:BAABNQAECoEfAAIXAAkKrCDHCwBcAwAXAAkKrCDHCwBcAwAAAA==.Larethiana:BAABNQAECoEfAAIRAAkKPyJTCwD6AgARAAkKPyJTCwD6AgABNQAECggIDQACAAAAAA==.Laria:BAAANQAECggIDQAAAA==.',
Le='Leafmochi:BAAANQAECgQIBQAAAA==.Letloose:BAAANQADCgEIAQAAAA==.',
Li='Lightbright:BAABNQAECoElAAISAAkK6yIAHAA+AwASAAkK6yIAHAA+AwAAAA==.Lildab:BAABNQAECoEhAAIYAAgKWRJXIQAGAgAYAAgKWRJXIQAGAgAAAA==.Linashia:BAABNQAECoEhAAIOAAkKMRNfPgBMAgAOAAkKMRNfPgBMAgAAAA==.',
Lo='Lostwanderer:BAAANQADCggIDgAAAA==.',
Lu='Luhen:BAAANQADCgYIBgAAAA==.',
Ma='Magicology:BAABNQAECoFcAAIBAAkKhSa5AAABBAABAAkKhSa5AAABBAAAAA==.Malacoda:BAABNQAECoElAAIMAAkK1xowGAC4AgAMAAkK1xowGAC4AgAAAA==.Manamommy:BAABNQAECoEYAAIBAAgKOxpyewBwAgABAAgKOxpyewBwAgAAAA==.Marble:BAAANQADCgYIBwAAAA==.',
Me='Merlx:BAAANQADCggIEQAAAA==.',
Mi='Miladee:BAAANQADCgYIBgAAAA==.Mindra:BAAANQAECgcIEQAAAA==.',
Mo='Moatie:BAAANQADCgQIBQAAAA==.Moobundo:BAAANQAECggIDgAAAA==.Moonmama:BAAANQABCgQIBAAAAA==.Moonwren:BAAANQAECggIEQAAAA==.Morgrin:BAAANQAECgYIDwAAAA==.',
Ne='Nezroz:BAAANQAECgEIAQABNQAECgUIEQACAAAAAA==.',
Ni='Nicotine:BAAANQAECgcIDAAAAA==.Nike:BAAANQAECgcIEQAAAA==.Nipsey:BAAANQADCgYIBgAAAA==.Nitwp:BAABNQAECoEsAAMZAAkK4RvUBwDrAgAZAAkK4RvUBwDrAgAaAAEK7AQvSwApAAAAAA==.Nizo:BAAANQAECgUIDwAAAA==.',
Nj='Njal:BAAANQADCgUJBQAAAA==.',
No='Novastrike:BAACNQAFFIEFAAMDAAIKZgZsIgCFAAADAAIKZgZsIgCFAAAEAAEKXQBPLAAwAAA1AAQKgSUAAwMACQr0GYUzAIUCAAMACQr0GYUzAIUCAAQAAgrbA3/wAFcAAAAA.',
Ny='Nymphia:BAAANQAECgUIBQAAAA==.Nyrif:BAABNQAECoEfAAIIAAkK2xqEIACWAgAIAAkK2xqEIACWAgAAAA==.',
Oj='Ojoon:BAAANQAECgYICgAAAA==.',
Om='Omnisllash:BAAANQAECgcIDQAAAA==.',
Pa='Pallamb:BAAANQADCgUIBQAAAA==.',
Ph='Phyter:BAAANQAECgQIBwAAAA==.',
Pi='Pillin:BAAANQAECgYIDAAAAA==.',
Po='Polyestr:BAAANQADCgQIBAAAAA==.Porkchowmein:BAAANQAECgMIAwAAAA==.',
Pr='Previousleon:BAAANQAECggIAQAAAA==.',
Ps='Psylence:BAAANQAECgIIAwAAAA==.Psyrge:BAAANQAECgIIAgAAAA==.',
Qu='Queue:BAAANQAECgUIDQAAAA==.',
Re='Redle:BAAANQADCggICgAAAA==.',
Rh='Rhordric:BAEBNQAECoEmAAQQAAkKvBjvKADiAQAQAAgKkhLvKADiAQAPAAcKXxONggDXAQAbAAEKKweiEgAmAAAAAA==.',
Ro='Roku:BAAANQADCgUIBQAAAA==.Rottenbeef:BAAANQAECgYIBgAAAA==.',
Ru='Runicmommy:BAAANQADCgUIBQAAAA==.',
Sa='Saintbull:BAAANQABCgYIBwAAAA==.Samwinchestr:BAAANQADCgIIAgAAAA==.Sanyoalt:BAAANQADCgEIAQAAAA==.',
Sc='Scemo:BAAANQADCgUIBQAAAA==.',
Se='Sea:BAACNQAFFIEQAAIEAAYKkRuWAwAvAgAEAAYKkRuWAwAvAgA1AAQKgSgAAgQACQrGJK8FAIkDAAQACQrGJK8FAIkDAAAA.Serendipity:BAAANQAECgQIBwAAAA==.',
Sh='Shadowaurora:BAAANQADCggJCAAAAA==.Shadowrose:BAAANQAECgYIDwAAAA==.Shamano:BAAANQAECgQIBgABNQAECgQIEgACAAAAAA==.Shanogadin:BAAANQAECgIIAgAAAA==.Shiemi:BAAANQAECgUIBgAAAA==.',
Sq='Squeaky:BAAANQAECgQIBAAAAA==.',
Su='Sungodess:BAAANQADCgcJDgAAAA==.',
Sy='Syrupp:BAAANQAECggIEgAAAA==.',
Ta='Tayn:BAAANQADCgcJDAAAAA==.',
Th='Thackery:BAAANQADCggICwAAAA==.Thinsheets:BAAANQADCgQIBAABNQAECgUICwACAAAAAA==.',
Tr='Trenetalan:BAAANQADCgIJAgABNQADCggIEAACAAAAAA==.',
Ts='Tsavø:BAAANQAECgQJBAAAAA==.',
Tw='Twinkle:BAAANQAECggIEgAAAA==.',
Un='Unholysage:BAAANQAECgYIDwAAAA==.Untouchable:BAAANQADCgEIAQAAAA==.',
Va='Valenîx:BAAANQAECgEIAQABNQAECgkJGQAaAOMKAA==.',
Ve='Venetrazat:BAABNQAECoEsAAIZAAgKSBilDgBWAgAZAAgKSBilDgBWAgAAAA==.',
Vo='Vo:BAAANQADCgYIDQAAAA==.Vol:BAAANQADCgUIBQAAAA==.',
Vu='Vulpra:BAAANQADCgMIAwAAAA==.',
['Vâ']='Vâlenix:BAABNQAECoEZAAMaAAkK4wr6JQBqAQAaAAcKIAj6JQBqAQAZAAgKMgfLHgBJAQAAAA==.',
['Vä']='Välenix:BAAANQAECgIIAgABNQAECgkJGQAaAOMKAA==.',
Wa='Warder:BAAANQAECgUICwAAAA==.',
We='Wewaskangz:BAAANQAECgMIBAAAAA==.',
Wi='Wincks:BAAANQAECgQIEgAAAA==.',
Xh='Xhosar:BAABNQAECoEpAAIbAAkKOhWsAwCjAgAbAAkKOhWsAwCjAgAAAA==.',
Za='Zachthemage:BAABNQAECoEaAAIBAAgK1AtYwwDaAQABAAgK1AtYwwDaAQAAAA==.Zackman:BAABNQAECoEtAAIXAAkKaw2oTgAQAgAXAAkKaw2oTgAQAgAAAA==.',
Zi='Zinatrax:BAAANQADCgYIDAAAAA==.',
Zo='Zombie:BAABNQAECoEiAAIUAAgKsBwVOwAQAgAUAAgKsBwVOwAQAgAAAA==.',
Zu='Zuldrakar:BAAANQADCgUICQAAAA==.Zulrea:BAABNQAECoEoAAIGAAgK2hhaKgBhAgAGAAgK2hhaKgBhAgAAAA==.',
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
