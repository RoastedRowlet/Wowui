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

local lookup = {'Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Hunter-Survival','Warlock-Destruction','Rogue-Subtlety','Warrior-Arms','Warrior-Fury','Unknown-Unknown','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Holy','Warrior-Protection','Druid-Guardian','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Evoker-Preservation','Monk-Brewmaster','Mage-Arcane','Mage-Frost','Monk-Windwalker','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Priest-Discipline','Hunter-Marksmanship','Shaman-Restoration','Warlock-Affliction','Shaman-Enhancement','Warlock-Demonology','Rogue-Assassination',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aashni:BAAANQADCgYIBgAAAA==.',
Ab='Abused:BAAANQADCgUIBQAAAA==.',
Ad='Adelaide:BAACNQAFFIEIAAIBAAUKzBOdDACbAQABAAUKzBOdDACbAQA1AAQKgSAAAwEACQoFIcUUABMDAAEACQoFIcUUABMDAAIAAQpWCnNoAD0AAAE1AAUUBQgIAAMAcxEA.',
Ag='Aglovale:BAABNQAECoEiAAMEAAgKziXaAwBuAwAEAAgKziXaAwBuAwAFAAEKmhZ0XAFKAAAAAA==.Agravaine:BAAANQADCgIIAgABNQAECggIIgAEAM4lAA==.',
Aj='Ajunlucky:BAACNQAFFIEEAAIGAAMKpxPvAAAKAQAGAAMKpxPvAAAKAQA1AAQKgSgAAgYACQrGH+4BACcDAAYACQrGH+4BACcDAAAA.',
Ak='Akuselgunk:BAAANQADCgcIDQAAAA==.',
Al='Alberich:BAAANQADCgEIAQABNQAECggIIgAEAM4lAA==.Alexari:BAAANQADCggICwAAAA==.Alnilam:BAABNQAECoEaAAIHAAcK0BH+FAC9AQAHAAcK0BH+FAC9AQAAAA==.Alphonse:BAAANQADCgUIBwAAAA==.',
Ap='Appypie:BAAANQAECgYIBgAAAA==.',
Ar='Arbys:BAAANQAECggIDAAAAA==.Arcos:BAAANQADCgUIBQAAAA==.Ardith:BAAANQABCgQIBQAAAA==.Arkveld:BAABNQAECoEgAAIIAAgKoCBBBwAAAwAIAAgKoCBBBwAAAwAAAA==.Armados:BAAANQAECgUIDgAAAA==.Aroxw:BAACNQAFFIEHAAIJAAUKfA93EACBAQAJAAUKfA93EACBAQA1AAQKgRwAAwkACQpGIJozAN0CAAkACQoMIJozAN0CAAoAAQpdJZEjAG0AAAAA.Arthritis:BAAANQABCgIIAgAAAA==.',
At='Athaal:BAAANQABCgQIBAAAAA==.Atlim:BAAANQADCgcIGgAAAA==.',
Ay='Aylinn:BAAANQAECgYIDwAAAA==.Aylira:BAAANQAECgEIAgAAAA==.Aymonzo:BAAANQAECgQIBAAAAA==.',
Az='Azulas:BAAANQADCgMIAwABNQADCggICwALAAAAAA==.',
Ba='Bad:BAAANQAECggICAAAAA==.Balfas:BAAANQADCgQIBAABNQAECgkJFwAMACEWAA==.Ballsmasher:BAAANQADCggIEgAAAA==.',
Be='Bearias:BAAANQADCgUIBQAAAA==.Bearnanas:BAAANQADCgQIBAAAAA==.Bernarnold:BAABNQAECoEcAAIKAAgK1hudBQCZAgAKAAgK1hudBQCZAgAAAA==.Bettyspready:BAAANQAECgcIDQAAAA==.',
Bi='Bigmanooshki:BAAANQAECgEIAgAAAA==.Bigpoppapump:BAAANQAECgYJDQAAAA==.Bigthumbb:BAAANQABCgUIBQAAAA==.Binnyi:BAAANQAECgYIEwAAAA==.',
Bl='Blackfoot:BAAANQAECgcIEQAAAA==.Blankjr:BAAANQAECgIIAwAAAA==.Blart:BAAANQAECgQIBAAAAA==.Blathnaid:BAAANQAECgUIBQABNQAFFAUICAADAHMRAA==.Blightmoss:BAAANQAECgEIAQABNQAECgYIDQALAAAAAA==.Blindpov:BAABNQAECoE0AAMNAAkK7iVKAQDkAwANAAkK7iVKAQDkAwAOAAcKPSDjJAAAAgAAAA==.',
Bo='Bodyodyodied:BAAANQADCgQIBAAAAA==.Bonquiquie:BAAANQADCgYICQAAAA==.Boop:BAAANQADCggIDgAAAA==.Bouberry:BAAANQADCgcIDgAAAA==.Bounce:BAAANQADCgYIDAAAAA==.',
Br='Brabiant:BAAANQADCgYIBgAAAA==.Brake:BAABNQAECoEYAAINAAgK9hnnKAAuAgANAAgK9hnnKAAuAgAAAA==.Breakerr:BAAANQAECgEIAQAAAA==.Brøken:BAAANQAECggICgAAAA==.',
Bu='Bubbleaddict:BAABNQAECoEcAAIPAAcKsh/JMACHAgAPAAcKsh/JMACHAgAAAA==.Bubbly:BAABNQAECoEZAAIFAAgKGxs1UAB8AgAFAAgKGxs1UAB8AgAAAA==.',
['Bë']='Bërshton:BAABNQAECoEVAAMGAAgKURpcBgAMAgAGAAcK7xdcBgAMAgADAAMKIBSw/QDNAAAAAA==.',
['Bú']='Búbble:BAAANQAECgEIAQAAAA==.',
Ca='Caitlín:BAAANQADCgYICgAAAA==.Caleris:BAABNQAECoEaAAIQAAcKJApSHQBBAQAQAAcKJApSHQBBAQAAAA==.Cattle:BAABNQAECoEgAAIRAAgKfxp/DQBOAgARAAgKfxp/DQBOAgAAAA==.',
Ce='Celine:BAAANQADCgUIBQAAAA==.',
Ch='Chowdk:BAAANQADCggICAAAAA==.Chowdo:BAAANQADCgcIBwAAAA==.Chowhunt:BAAANQAECgUIBgAAAA==.',
Cl='Clawsofpeace:BAAANQAECgcICgAAAA==.',
Co='Constanse:BAAANQADCgYICgAAAA==.Cottage:BAAANQAECgIIBAAAAA==.',
Cy='Cylic:BAABNQAECoEfAAIIAAgKNCJ9BwD6AgAIAAgKNCJ9BwD6AgAAAA==.Cyrùsdh:BAAANQAECgUIBQAAAA==.',
Da='Daddiestouch:BAAANQAECgUIDAAAAA==.Dampundies:BAAANQAECgcIDwAAAA==.Dangerdream:BAABNQAECoEpAAMOAAkKDSB8CABDAwAOAAkKDSB8CABDAwASAAUKChOrFwACAQAAAA==.Dankheals:BAAANQADCgYIBgAAAA==.Dantee:BAAANQAECgEIAQAAAA==.Daps:BAAANQADCgQIBAAAAA==.Dartini:BAAANQADCgIIAgABNQAECgcJDgALAAAAAA==.Datsmywife:BAABNQAECoEjAAITAAgKLxMwDQAWAgATAAgKLxMwDQAWAgAAAA==.Davis:BAABNQAECoEbAAQUAAgKvR48KwBnAgAUAAgKvR48KwBnAgAVAAMKuBFVcACaAAAWAAEKWBEmtABBAAAAAA==.Dayquill:BAAANQAECgQIBAAAAA==.',
De='Deadasice:BAAANQADCgEIAQABNQADCgIIAgALAAAAAA==.Demonknuts:BAAANQAECggICAAAAA==.Derpdragon:BAABNQAECoEwAAIXAAkK6R5ZCQD/AgAXAAkK6R5ZCQD/AgAAAA==.Derppriest:BAAANQADCggICAABNQAECgkJMAAXAOkeAA==.Deviiarrc:BAACNQAFFIEIAAIXAAQKsww0DAAlAQAXAAQKsww0DAAlAQA1AAQKgTIAAhcACQo7I/cDAGwDABcACQo7I/cDAGwDAAAA.Devviarc:BAAANQADCggICwABNQAFFAQICAAXALMMAA==.',
Di='Dibgargargad:BAAANQAECgYIBgAAAA==.',
Dl='Dlamb:BAAANQAECgQIDQAAAA==.',
Do='Dorik:BAAANQADCgEIAQAAAA==.Doroga:BAAANQAECgYIDgAAAA==.',
Dr='Dracar:BAABNQAECoEdAAIFAAkKwR/SIQAkAwAFAAkKwR/SIQAkAwAAAA==.Drmmrfist:BAABNQAECoEaAAIYAAcKCRBJFQBuAQAYAAcKCRBJFQBuAQAAAA==.',
Dw='Dwippietiggs:BAABNQAECoEbAAIFAAgKBxldcAAgAgAFAAgKBxldcAAgAgAAAA==.',
['Dä']='Däwntouchme:BAAANQADCgYIBgAAAA==.',
Ea='Ealer:BAAANQAECgUIBQABNQAFFAYIFQAPAHgmAA==.Earthfeather:BAAANQADCggIDwAAAA==.Easymac:BAAANQADCgIJAwABNQAECggIGAANAPYZAA==.',
Ee='Eetee:BAAANQAECgMJBQABNQAECggIHAAEAIYKAA==.',
Eh='Ehemingway:BAAANQAECgQIDwAAAA==.',
El='Eleabuser:BAAANQADCgMIAwAAAA==.Elysin:BAAANQAFFAEIAQABNQAFFAUICAADAHMRAA==.',
Em='Emberstone:BAAANQAECgQIBAAAAA==.Emoux:BAAANQADCgYIBgAAAA==.',
En='Endelechia:BAAANQADCgQJBAAAAA==.',
Ep='Epìx:BAAANQADCggIBgAAAA==.',
Er='Eralt:BAAANQAECgYIEwAAAA==.Ereye:BAABNQAECoEYAAIIAAcKjhQbHADhAQAIAAcKjhQbHADhAQAAAA==.',
Es='Esstina:BAAANQAECgIIAgAAAA==.Estuku:BAAANQAECgYIEgAAAA==.',
Et='Etatoned:BAAANQADCgQIBAABNQAECggIHAAEAIYKAA==.Etengaged:BAABNQAECoEcAAIEAAgKhgrrKQBiAQAEAAgKhgrrKQBiAQAAAA==.Ethavoc:BAAANQAECgYICwABNQAECggIHAAEAIYKAA==.',
Ev='Evrae:BAABNQAECoEdAAIIAAgKGhUeEwBCAgAIAAgKGhUeEwBCAgAAAA==.',
Ex='Extragrace:BAAANQADCgcIBwAAAA==.',
Ey='Eyeofjazz:BAAANQABCggICQAAAA==.',
Fa='Faithshand:BAAANQAECgYIEwAAAA==.Fatkow:BAAANQAECggIBQABNQAECgkJIwAUAOglAA==.',
Fe='Feath:BAAANQADCgUIBQAAAA==.Feelzdope:BAAANQAECgQICQAAAA==.Feio:BAAANQADCggIBAAAAA==.Fergus:BAAANQADCgUIBQAAAA==.',
Fi='Finkenator:BAACNQAFFIEdAAMZAAcK/x0qDgDkAQAZAAUKgh0qDgDkAQAaAAIKOR+bAwDBAAA1AAQKgSEAAhkACQqZIMZOANMCABkACQqZIMZOANMCAAAA.Finkler:BAABNQAECoEnAAMZAAkKgx4HZgCeAgAZAAkKIBwHZgCeAgAaAAIK3yQ+HwDNAAABNQAFFAcIHQAZAP8dAA==.Firedanny:BAAANQAECgEIAQAAAA==.Fistsofpeace:BAAANQAECgYJCwABNQAECgcICgALAAAAAA==.',
Fl='Flameshock:BAABNQAECoEhAAMaAAgKwRCxDAC3AQAZAAgKlAzZwADfAQAaAAgKEBCxDAC3AQAAAA==.',
Fo='Forcepull:BAAANQAECgUIDAABNQAECgcIIwAbAJkVAA==.',
Fr='Frankda:BAAANQADCgIIAgAAAA==.Friendshaped:BAAANQAECgMIAwABNQAFFAYKEAADAOgfAA==.Friendship:BAAANQADCgEIAQAAAA==.Frigidbeach:BAAANQAECgEIAQAAAA==.',
Gh='Ghale:BAAANQADCggIFgAAAA==.',
Gl='Glaiveerror:BAAANQADCgYIDwAAAA==.Globoe:BAACNQAFFIEYAAMcAAgKBBzTAgDAAQAcAAUKBxzTAgDAAQAdAAUK9Bo2AwCoAQA1AAQKgR0AAxwACQpjH9MMAHwCABwACQrAHNMMAHwCAB0AAwrmJNANAEEBAAAA.Gloreb:BAABNQAFFIEFAAIbAAUKSxjBBgBdAQAbAAUKSxjBBgBdAQAAAA==.',
Go='Goomi:BAAANQAECgUIBgAAAA==.Gordef:BAAANQAECgYIEwAAAA==.Gotchabch:BAAANQADCgMIAwAAAA==.',
Gr='Grahz:BAAANQAECgMIBgAAAA==.Grismago:BAAANQAECgEIAgAAAA==.Grizzlebee:BAAANQADCgUIBQAAAA==.',
Gu='Gusto:BAAANQAECgYIEAAAAA==.',
Ha='Haakon:BAAANQADCgUIBQAAAA==.Hanaya:BAAANQAECgUIBQAAAA==.Harrowing:BAABNQAECoE7AAIPAAkKzxtgIQDRAgAPAAkKzxtgIQDRAgAAAA==.Haurt:BAABNQAECoEdAAIeAAcK6QhrVwBOAQAeAAcK6QhrVwBOAQAAAA==.',
He='Heavyhooves:BAAANQAECgIIAwAAAA==.Hellful:BAAANQAECgEIAQAAAA==.Hemoladi:BAAANQAECgcIEgAAAA==.',
Hi='Hischier:BAAANQAECgYICgAAAA==.',
Ho='Holycri:BAAANQAECggIDwAAAA==.Holymilkman:BAAANQABCgQIBgAAAA==.Hotdogramen:BAAANQADCgMIAwAAAA==.Hotmess:BAAANQAECgUICgAAAA==.',
['Hô']='Hôly:BAAANQAECgcIDgAAAA==.',
In='Insanê:BAAANQAECggICwABNQAECgkJJwAbAAoUAA==.Insañe:BAABNQAECoEnAAIbAAkKChTWHQAaAgAbAAkKChTWHQAaAgAAAA==.Invi:BAAANQAECgUJCAAAAA==.',
Ir='Ironbeef:BAAANQAECgQIAwAAAA==.',
It='Itsjazz:BAAANQABCgMIAwAAAA==.',
Ja='Jabwingle:BAAANQADCgEIAQABNQAECgQICgALAAAAAA==.Jadengras:BAAANQADCgYIEAAAAA==.Jasminetea:BAAANQADCgcIBwAAAA==.Jayylols:BAAANQAECgYICgAAAA==.',
Je='Jereome:BAAANQADCgYIBgAAAA==.',
Jo='Jokerzwild:BAAANQADCgQJBgAAAA==.',
Ju='Juiice:BAAANQAECgYIEgAAAA==.',
['Jë']='Jësus:BAABNQAECoEjAAMfAAgKvBPLCQCeAQABAAcKTxShYwDCAQAfAAcK1RHLCQCeAQAAAA==.',
Ka='Kalandaelis:BAAANQADCggJFQAAAA==.Kaldren:BAAANQADCgYIFAAAAA==.Kalel:BAAANQAECgQIBQAAAA==.Karmakazie:BAAANQAECgQIBQAAAA==.Kashijinbaba:BAAANQADCgIIAgAAAA==.Katasha:BAAANQAECgUIEwAAAA==.Kazraghand:BAABNQAECoEfAAIGAAgKAA5dBgAMAgAGAAgKAA5dBgAMAgAAAA==.',
Ke='Keetanah:BAAANQADCgYIEAAAAA==.Kei:BAACNQAFFIEGAAIOAAMKlgtkCwDZAAAOAAMKlgtkCwDZAAA1AAQKgSQAAw4ACQr8GvsRAMcCAA4ACQr8GvsRAMcCAA0AAQrpDJR+AD4AAAAA.Kelsio:BAABNQAECoEcAAIDAAgKsBh7VABLAgADAAgKsBh7VABLAgAAAA==.Kess:BAAANQADCgYICAAAAA==.Keyboardcatt:BAAANQAECgEJAQAAAA==.',
Kh='Kharos:BAABNQAECoEhAAIBAAkKGg2hTwALAgABAAkKGg2hTwALAgAAAA==.',
Ki='Kikeo:BAAANQAECgUIBQABNQAFFAMIBgAOAJYLAA==.Kinks:BAAANQAECgQIDQAAAA==.Kirkoth:BAAANQADCgcIEAAAAA==.',
Kn='Knuah:BAAANQADCgYIBgABNQAECggIFwACAJoVAA==.Knuts:BAAANQAECggIBwAAAA==.',
Ko='Korialz:BAAANQADCgYIAQAAAA==.Kovah:BAAANQAECggIDgAAAA==.Kowtagion:BAABNQAECoEjAAMUAAkK6CUdCABwAwAUAAkK6CUdCABwAwAWAAEKeiVapABmAAAAAA==.',
Kp='Kpopped:BAAANQAECgQIBAAAAA==.',
Kr='Krahz:BAAANQAECgUICgAAAA==.Krelsh:BAABNQAECoEbAAQgAAgKbBv6KgDQAQAgAAcKJxn6KgDQAQADAAIKciDABQG1AAAGAAIK4gnuDwBLAAABNQAECgkJIwAZADcaAA==.Krostikard:BAAANQAECgQIBAAAAA==.',
Ku='Kumquat:BAAANQADCgYICQAAAA==.Kungfudegru:BAAANQAECgEIAQAAAA==.Kuraven:BAAANQADCgYIBgAAAA==.',
Ky='Kyruutos:BAAANQAECgMICQAAAA==.',
['Kí']='Kítkat:BAABNQAECoEaAAIhAAcKQR/cLACKAgAhAAcKQR/cLACKAgAAAA==.',
Le='Leibowitzy:BAABNQAECoEjAAMbAAcKmRWYKgCVAQAbAAcKQxKYKgCVAQAYAAUKwxXeFwBCAQAAAA==.Leiptr:BAAANQAECgEIAQAAAA==.Lekramul:BAAANQAECgEIAQAAAA==.Letra:BAAANQADCgMIAwAAAA==.Lexstrasza:BAAANQABCgIIAgAAAA==.',
Lh='Lhehitman:BAABNQAECoEcAAIaAAkKnCAcAgA4AwAaAAkKnCAcAgA4AwAAAA==.',
Li='Lichenric:BAAANQADCgcIDAAAAA==.Lidela:BAAANQAECgEIAgAAAA==.Lightshax:BAABNQAECoEVAAIPAAcKmhA2cQCdAQAPAAcKmhA2cQCdAQAAAA==.Lilchow:BAAANQADCgMIAwAAAA==.Linedra:BAABNQAECoEXAAISAAgKtQ1fDwCPAQASAAgKtQ1fDwCPAQAAAA==.Liv:BAAANQADCgIIAgAAAA==.',
Lo='Loreena:BAAANQADCgEIAQAAAA==.Lovestoned:BAAANQADCgEIAQAAAA==.',
Lu='Luckydog:BAAANQAECgMIAwAAAA==.Ludey:BAABNQAECoEsAAIiAAkKFRj7AwCJAgAiAAkKFRj7AwCJAgAAAA==.Lumidk:BAAANQABCgIIAgAAAA==.Lumiya:BAAANQAECgEIAQAAAA==.Lutray:BAAANQAECgYIDwAAAA==.',
Ma='Maliketh:BAAANQADCggICAAAAA==.Maomao:BAABNQAECoEqAAIBAAkKMhGEPQBPAgABAAkKMhGEPQBPAgAAAA==.Marodd:BAAANQAECgYIEwAAAA==.Mashîra:BAACNQAFFIEFAAIDAAQKexaXCwBjAQADAAQKexaXCwBjAQA1AAQKgR8AAgMACQrCJTsEALsDAAMACQrCJTsEALsDAAAA.Matilda:BAAANQABCgQIBAAAAA==.Mattsz:BAAANQAECgQIBAAAAA==.',
Me='Meanmachine:BAAANQADCgUIBgAAAA==.Meatpocket:BAAANQADCgcIBwAAAA==.Meatwangs:BAABNQAECoErAAQhAAkKOh4PGAD5AgAhAAkKOh4PGAD5AgAjAAEKwgdHMAA3AAAMAAEKOAwnHgEuAAAAAA==.Mekuro:BAAANQAECgQIBgAAAA==.Merihem:BAAANQADCgUICAAAAA==.Mewfasa:BAAANQADCggICAAAAA==.',
Mi='Mia:BAAANQAECgcICgAAAA==.Milize:BAABNQAECoEdAAIFAAgKeCAWOADNAgAFAAgKeCAWOADNAgAAAA==.Minasuzune:BAAANQAECgYIEwAAAA==.Miney:BAAANQADCgYICAAAAA==.Minus:BAAANQADCgIIAgAAAA==.',
Mo='Moondotter:BAAANQAECgMIAwAAAA==.Moongoddess:BAAANQAECgIJAgABNQAECgMIAwALAAAAAA==.Moonslayer:BAAANQAECgYIDwAAAA==.Moovefool:BAAANQAECgIIAwAAAA==.',
My='Mybanknoturs:BAAANQABCgQIBAAAAA==.',
['Mã']='Mãshîrã:BAAANQADCggICAABNQAFFAQIBQADAHsWAA==.',
['Mä']='Mähäret:BAAANQADCgUIBQAAAA==.',
['Må']='Måshìra:BAAANQAECgEIAQABNQAFFAQIBQADAHsWAA==.Måshîrå:BAAANQAECgYICQABNQAFFAQIBQADAHsWAA==.',
Na='Nakor:BAAANQAECgQIDwAAAA==.Nalian:BAAANQAECgYJDgAAAA==.Nalliella:BAABNQAECoEZAAIKAAYK7xDbEAByAQAKAAYK7xDbEAByAQAAAA==.Natashers:BAAANQADCgUIBQAAAA==.',
Ne='Neenzy:BAAANQAECgUIDAAAAA==.Nefeli:BAABNQAECoEjAAIdAAkK8hVnBQBsAgAdAAkK8hVnBQBsAgAAAA==.Nelinne:BAAANQAECgIIAwAAAA==.Nellevene:BAAANQAECgYIDwAAAA==.Nestia:BAAANQAECgIIAwAAAA==.Never:BAACNQAFFIEHAAMHAAMKDBi6CgCmAAAHAAIKIBW6CgCmAAAkAAIKexi6JAClAAA1AAQKgSoAAyQACQrvIV0rAL8CACQACAq6IV0rAL8CAAcABQqrHV8bAIoBAAAA.',
Ni='Nightshade:BAABNQAECoEoAAIDAAkKERjiMwCuAgADAAkKERjiMwCuAgAAAA==.Nimbus:BAAANQAECgcIBwAAAA==.Nix:BAAANQADCgYIBgAAAA==.',
Ny='Nyckels:BAAANQADCgEIAQAAAA==.',
Oa='Oathbreaker:BAAANQADCgcIEQAAAA==.',
Oc='Ocllo:BAAANQAECgYIEwAAAA==.',
Og='Oghealz:BAAANQAECgQICQAAAA==.',
Oj='Ojo:BAAANQAECgYIEQAAAA==.',
On='Oniana:BAABNQAECoEaAAIgAAYKPAp7PQA3AQAgAAYKPAp7PQA3AQAAAA==.',
Op='Openwide:BAAANQADCgYIBgABNQAECgkJIQAeAOAQAA==.',
Ow='Owwmyballs:BAAANQADCgMIAwAAAA==.',
Oz='Ozygo:BAAANQADCgcIDAAAAA==.',
Pa='Pagamas:BAACNQAFFIEIAAIZAAQKjhmYHABkAQAZAAQKjhmYHABkAQA1AAQKgSEAAxkACQpBHlNMANkCABkACQpBHlNMANkCABoAAgqLER0xAF4AAAAA.Palandari:BAAANQAECgQIBgAAAA==.Pandawan:BAAANQAECgMICAAAAA==.Panter:BAAANQAECgIIAwAAAA==.Paperplanes:BAAANQADCgQIBAAAAA==.',
Pe='Pebble:BAAANQAECgQICQAAAA==.',
Ph='Phodoe:BAAANQAECgYIEwAAAA==.',
Pi='Pinquisitor:BAAANQADCgQIAQABNQAECgMICAALAAAAAA==.',
Pl='Platewinslet:BAAANQAECgIIAgAAAA==.Playne:BAAANQAECgQIBgAAAA==.',
Po='Pokeureyeout:BAAANQAECgUICQAAAA==.Port:BAAANQAECgUIBgABNQAECgYIDgALAAAAAA==.',
Pr='Prodyne:BAABNQAECoEsAAIZAAkKeBSndwB4AgAZAAkKeBSndwB4AgAAAA==.',
['Pî']='Pîlot:BAAANQADCgQIBAABNQAECgUIDAALAAAAAA==.',
Qu='Quag:BAAANQADCgUIBQABNQAECgkJKwABAI4fAA==.Quiettreader:BAABNQAECoEjAAIaAAcKdh06BwBTAgAaAAcKdh06BwBTAgAAAA==.Quokka:BAAANQAECgMIBQAAAA==.',
Ra='Raegwin:BAAANQAECgQICwAAAA==.Raidboss:BAAANQAECgYIEAAAAA==.',
Re='Redeath:BAAANQAECgIJAgABNQAECgMIAwALAAAAAA==.Redirect:BAAANQAECgIIAgABNQAECgMIAwALAAAAAA==.Redonculous:BAABNQAECoEXAAICAAgKmhVqIAAPAgACAAgKmhVqIAAPAgAAAA==.Redpool:BAABNQAECoEkAAIhAAkKjQ4IXQDJAQAhAAkKjQ4IXQDJAQAAAA==.Rehvenge:BAAANQADCggJCQAAAA==.Rektroll:BAABNQAECoEkAAIOAAcKnCG6EwC0AgAOAAcKnCG6EwC0AgAAAA==.Revansong:BAAANQADCgYICgABNQAECggIIAAIAKAgAA==.Reymnant:BAAANQAECgIIAwAAAA==.',
Ri='Ricecooker:BAAANQADCgUIBQAAAA==.',
Ro='Ronx:BAAANQAECgQIDAAAAA==.Roxxiloxxi:BAABNQAECoEdAAMHAAgK4AbqHgBvAQAHAAgK4AbqHgBvAQAkAAEKJwIEOgEeAAAAAA==.',
Ru='Rudeboy:BAABNQAECoEgAAIkAAgKMhkiRQBmAgAkAAgKMhkiRQBmAgAAAA==.Rushu:BAABNQAECoEjAAIZAAkKNxo2TgDVAgAZAAkKNxo2TgDVAgAAAA==.',
['Rö']='Röwan:BAAANQADCgUJBQAAAA==.',
Sa='Sabria:BAABNQAECoEnAAMPAAkKvxK4PQBQAgAPAAkKvxK4PQBQAgAFAAcK1QyxvgBmAQAAAA==.Sagitta:BAAANQADCgcIBwABNQAECgYIEAALAAAAAA==.Sahria:BAAANQAECgQIBAAAAA==.Samlosco:BAAANQAECgYIBgAAAA==.Sapphpal:BAAANQAECgYICAABNQAECgcIBwALAAAAAA==.Sarhia:BAAANQADCgUIBQAAAA==.Savanari:BAAANQAECgEIAQABNQABCgIIAgALAAAAAA==.',
Sc='Schizology:BAAANQADCggIEAAAAA==.Schnoze:BAAANQAECgQIDQAAAA==.',
Se='Sebekuul:BAAANQADCgYIBgAAAQ==.Selfie:BAAANQABCgIIAgAAAA==.Selys:BAACNQAFFIEIAAIZAAQKmQjBIwApAQAZAAQKmQjBIwApAQA1AAQKgS0AAxkACQoMFblwAIYCABkACQoMFblwAIYCABoAAgr9B94yAFgAAAAA.Sence:BAAANQABCgQIBAAAAA==.Sepheturix:BAAANQAECgUIBQAAAA==.Sephurik:BAACNQAFFIEQAAMZAAQKkhQOIABEAQAZAAQKkhQOIABEAQAaAAEKXQDfEABDAAA1AAQKgTsAAxkACQp7Ip8iAEgDABkACQomIZ8iAEgDABoAAgpTHmgjALEAAAAA.Serrie:BAAANQADCgUIBQAAAA==.',
Sh='Shadowswife:BAAANQADCgYIBgAAAA==.Shadowwife:BAAANQADCgYIBgAAAA==.Shamaneez:BAAANQADCgYICAAAAA==.Shamanism:BAAANQADCgUIBQAAAA==.Shammuri:BAAANQADCgQIBAAAAA==.Shanamana:BAAANQAECgQIBAAAAA==.Shawnalenee:BAAANQAECgQIBQABNQAECgQIDQALAAAAAA==.Shiestee:BAAANQAECgQIDAAAAA==.Shiriax:BAAANQAECgIJBAAAAA==.',
Si='Sikanda:BAAANQAECgcIDQABNQAECgkJGQAgAC4fAA==.Silvea:BAAANQAECgYIDAAAAA==.Sinara:BAAANQAECgQIBQAAAA==.Sintaxtwo:BAAANQAECgEIAQAAAA==.Sion:BAABNQAECoEfAAICAAgK6h7PEgC2AgACAAgK6h7PEgC2AgAAAA==.Sithlordz:BAAANQADCgYICQAAAA==.',
Sk='Skillertank:BAAANQADCggIDwAAAA==.Sky:BAABNQAECoEgAAIZAAkKvCIwFwBwAwAZAAkKvCIwFwBwAwAAAA==.Skyelf:BAABNQAECoEgAAIDAAgKhwxRdQD3AQADAAgKhwxRdQD3AQAAAA==.',
Sl='Slimshadow:BAAANQABCgIJAgAAAA==.Sloppysloosh:BAAANQAECgYIDAAAAA==.',
Sm='Smallpox:BAAANQADCgUIDgAAAA==.Smokebreak:BAAANQADCggICAAAAA==.',
Sn='Snooflepoof:BAABNQAECoErAAIhAAkKQBrzGwDiAgAhAAkKQBrzGwDiAgAAAA==.',
So='Socks:BAAANQAECggICwABNQAFFAcIGgAjAJ8dAA==.Solunara:BAAANQADCgUIBQABNQAECgYIDQALAAAAAA==.',
Sp='Spectrecles:BAABNQAECoEhAAIeAAkK4BCyMgApAgAeAAkK4BCyMgApAgAAAA==.Spectrecless:BAAANQADCgUIBQABNQAECgkJIQAeAOAQAA==.Speez:BAAANQAECgUIDwAAAA==.Sphester:BAAANQADCgUIBQAAAA==.',
St='Stablehand:BAAANQAECgUICgAAAA==.Steve:BAACNQAFFIEPAAIMAAQKPw/yDABgAQAMAAQKPw/yDABgAQA1AAQKgTIAAwwACQplIqYQAFYDAAwACQplIqYQAFYDACEAAQo+ArQKASkAAAAA.Stonedfel:BAABNQAECoEVAAINAAcK8Q/UPQCWAQANAAcK8Q/UPQCWAQAAAA==.',
Su='Sunhoof:BAAANQAECgYIDQAAAA==.Supahotvile:BAAANQAECgYIDAAAAA==.',
Sy='Syx:BAAANQADCgYIBgAAAA==.',
['Sø']='Sørrow:BAAANQAECgYIEwAAAA==.',
Ta='Tabi:BAAANQAECgYIEwAAAA==.Taiyn:BAAANQADCgYIBgAAAA==.Taldresh:BAAANQADCggJDQAAAA==.Tanorgalaria:BAAANQADCggIEAAAAA==.Taralash:BAAANQAECgMIAwABNQAECgQIBgALAAAAAA==.',
Te='Test:BAAANQAECggJAQAAAA==.',
Th='Thedawg:BAAANQADCgEIAQAAAA==.Thedayman:BAAANQADCggICAAAAA==.Thetaint:BAABNQAECoEjAAIlAAkKkCPJBABzAwAlAAkKkCPJBABzAwAAAA==.',
Ti='Tinee:BAAANQADCggIDwAAAA==.Tinket:BAACNQAFFIEIAAIDAAUKcxFaCACcAQADAAUKcxFaCACcAQA1AAQKgR4AAwMACQr/IsEQAEwDAAMACQr/IsEQAEwDACAAAQpAGV5xAEMAAAAA.Tiplar:BAAANQAECgQIBAABNQAECggIHwACAOoeAA==.',
To='Totemofpeace:BAAANQADCggIEAABNQAECgcICgALAAAAAA==.',
Tr='Travonnis:BAAANQADCggIDAAAAA==.Trentlock:BAACNQAFFIEFAAQiAAMKaQUNDwA+AAAHAAEKBAUyHwBFAAAkAAEK0QSWOwBCAAAiAAEKZwYNDwA+AAA1AAQKgSQAAyQACQqeEthjAAoCACQACQqHDthjAAoCAAcABApsFxYrABkBAAAA.Tristae:BAAANQAECgUICQAAAA==.',
Ts='Tsu:BAAANQAECgYIBwAAAA==.',
Tu='Tuktuk:BAAANQADCgYIBgAAAA==.',
Ty='Tynisa:BAAANQADCggICgAAAA==.',
Uj='Ujamen:BAAANQAECgIIAgAAAA==.',
Un='Unstablesha:BAAANQAECgEIAQAAAA==.',
Ut='Utilities:BAAANQADCggICAAAAA==.',
Va='Vaderbear:BAAANQADCggICAAAAA==.Varandar:BAACNQAFFIEFAAMUAAMKShNsFACaAAAUAAIKqRZsFACaAAAWAAEKjAw7LwApAAA1AAQKgSoAAhQACQoeIhIRABkDABQACQoeIhIRABkDAAAA.',
Vd='Vdomil:BAAANQABCgQIBAAAAA==.',
Vi='Via:BAAANQADCgYICgAAAA==.Viggenwilde:BAAANQAECgIIAgAAAA==.Vil:BAACNQAFFIEdAAICAAgKPB1SAAAOAwACAAgKPB1SAAAOAwA1AAQKgSYAAgIACQqvJrcBAMIDAAIACQqvJrcBAMIDAAAA.Vilonus:BAABNQAECoEcAAIkAAcKEBFGewDHAQAkAAcKEBFGewDHAQAAAA==.Viridiana:BAAANQADCgEIAQAAAA==.Vitiate:BAAANQADCgMIAwABNQAECggIHwACAOoeAA==.',
Vo='Voidbwoy:BAAANQADCggIEwAAAA==.Voy:BAABNQAECoEYAAIGAAgKVwffBwC7AQAGAAgKVwffBwC7AQAAAA==.',
Vu='Vulpes:BAAANQADCgcIBwAAAA==.Vurx:BAAANQAECgEIAQAAAA==.',
We='Weezy:BAAANQAECgYIDwAAAA==.',
Wi='Williie:BAAANQAECgcICwAAAA==.Withengar:BAAANQADCggICAAAAA==.',
Wu='Wuoshi:BAAANQAECgQIBgAAAA==.Wuuzzyy:BAABNQAECoEeAAIeAAkKsxG5MQAvAgAeAAkKsxG5MQAvAgAAAA==.',
Xa='Xaliko:BAAANQAECgYJCQAAAA==.Xanbaran:BAABNQAECoEsAAIBAAkKXQlPYADOAQABAAkKXQlPYADOAQAAAA==.',
Xi='Xiphus:BAAANQABCgMIBQAAAA==.',
Xy='Xyrters:BAAANQADCgIIAgAAAA==.Xyrtrew:BAACNQAFFIEFAAIhAAMK+CKwDgA0AQAhAAMK+CKwDgA0AQA1AAQKgSsAAyEACQr0Ih4OADwDACEACQr0Ih4OADwDAAwAAQpQHFwDAU0AAAAA.',
Ya='Yahenni:BAABNQAECoEZAAMgAAkKLh8/FwCIAgAgAAcKmh8/FwCIAgADAAgK9RddTgBcAgAAAA==.Yati:BAAANQADCgUIBQAAAA==.',
Yl='Ylenna:BAAANQAECgIIAgAAAA==.',
Yu='Yuki:BAAANQAECgYIAwAAAA==.Yukki:BAAANQAECggIBgAAAA==.',
Za='Zambesi:BAAANQAECgQJBAAAAA==.Zaradinna:BAAANQADCgEIAQAAAA==.Zartini:BAAANQAECgcJDgAAAA==.',
Ze='Zerk:BAAANQAECggIDgAAAA==.',
Zu='Zurxes:BAAANQADCgEIAQAAAA==.',
Zy='Zynmonk:BAAANQAECgMIAwAAAA==.',
['Âk']='Âkaeus:BAAANQADCgUIBQAAAA==.',
['Ïn']='Ïnø:BAAANQADCgYIBgAAAA==.',
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
