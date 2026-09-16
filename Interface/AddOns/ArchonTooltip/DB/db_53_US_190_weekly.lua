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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','Druid-Feral','Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Paladin-Retribution','Evoker-Preservation','Warrior-Fury','Warrior-Arms','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aarazi:BAAANQAECgQIBwAAAA==.',
Ab='Abbinormal:BAAANQADCgMIAwAAAA==.Abolish:BAAANQABCgIIAgAAAA==.',
Ae='Aeriss:BAAANQADCgQIBgAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAAANQAECgMIAwAAAA==.',
Ah='Ahegao:BAAANQADCggICAAAAA==.Ahnari:BAAANQAECgEIAQAAAA==.',
Ak='Akkadien:BAAANQAECgcIEQAAAA==.Akumunter:BAAANQAECgIIAgAAAA==.',
Al='Alacardias:BAAANQAECgQIBgAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAAANQAFFAEIAQAAAA==.',
An='Anassand:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.Andimorph:BAAANQAECgMIBAAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAAANQAECgQIBQAAAA==.',
Aq='Aqualight:BAAANQAECgIIAgABNQAECgcIDQABAAAAAA==.Aquaterra:BAAANQAECgcIDQAAAA==.Aquina:BAAANQAECgIIAgABNQAECgcIDQABAAAAAA==.',
Ar='Arakadia:BAAANQAECgYIDwAAAA==.Artoriaz:BAAANQADCgcICwAAAA==.Aruteeru:BAAANQAECgEIAQAAAA==.',
As='Aseanna:BAAANQADCggIEQAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
Au='Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgABAAAAAA==.',
Av='Avarous:BAAANQAECgMIAwAAAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAAANQAFFAEIAQAAAA==.',
Az='Azaireos:BAAANQADCgQIBwAAAA==.Azulpunkt:BAAANQAECgcIDwAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAAANQAECgQIBQAAAA==.Barbedwire:BAAANQAECgEIAQAAAA==.',
Be='Bearmao:BAAANQAECgYICwAAAA==.Beknight:BAAANQAECgUIBwAAAA==.Belfas:BAAANQADCgcICQAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAAANQAECgEIAQAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAAANQAECgEIAQAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bludnite:BAABNQAECoEWAAICAAgJzBp6GQBZAgACAAgJzBp6GQBZAgAAAA==.',
Bo='Bokchoi:BAAANQADCggIIwAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQADCggICAAAAA==.Bruute:BAAANQAECgYIDQAAAA==.',
Bu='Budplatinum:BAAANQADCggIDAAAAA==.',
['Bå']='Båcon:BAAANQABCgQIBAAAAA==.',
Ca='Cairo:BAAANQAECgcIDAAAAA==.Capitalchaos:BAAANQAECgMIBQABNQAECgcIEAABAAAAAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAAANQAECgcIEAAAAA==.',
Ce='Cell:BAAANQAECgYIDwAAAA==.Ceviche:BAAANQAECgUIBwAAAA==.Ceàrrdòrn:BAAANQAECgMIBAAAAA==.',
Ch='Chibí:BAAANQADCggIFgAAAA==.Chillzmatic:BAAANQAECgEIAgAAAA==.Chudbucket:BAAANQAECgYIDgAAAA==.',
Ci='Cirillø:BAAANQABCggICAABNQAECgYICQABAAAAAA==.',
Cl='Clovergold:BAAANQAECgcIDgAAAA==.Clyde:BAAANQAECgQIBwAAAA==.',
Co='Corbis:BAEANQAECgQIBgAAAA==.',
Cr='Crevarus:BAAANQADCgUIDAAAAA==.Crimsonjeybi:BAAANQAECgYICAAAAA==.Crunchwich:BAAANQADCgcIBgAAAA==.',
Cu='Cutename:BAAANQADCgEIAQAAAA==.',
Cy='Cynamyn:BAAANQADCgcIBgAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgQIBwAAAA==.Daevarys:BAAANQADCgEIAQAAAA==.Dakhran:BAAANQADCgIIBAAAAA==.Dan:BAAANQADCgEIAQAAAA==.Darkdemon:BAAANQAECgIIAgAAAA==.Darlord:BAAANQADCgcIBgAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIAgABNQAECgUIDQABAAAAAA==.Deandrya:BAAANQADCgQIBAAAAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQADCgcIBgAAAA==.Demônlock:BAAANQADCgcIAwAAAA==.Desideria:BAAANQAECgMIAwAAAA==.Despondence:BAAANQAECgUIBQAAAA==.Desynn:BAAANQAECgQICAAAAA==.',
Di='Divinesyn:BAAANQADCgYIBgAAAA==.',
Dj='Djelysium:BAAANQADCgcIAwAAAA==.Djtaki:BAAANQAECggIEQAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAMIBQADANMbAA==.Doncarlos:BAAANQAECgcIEgAAAA==.Dorn:BAAANQADCgUIBQAAAA==.Dotty:BAAANQADCgQIBgAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFIEFAAMEAAQJMAw8BgCsAAAEAAIJ2Q08BgCsAAAFAAIJhgqnDwCbAAA1AAQKgR0AAwUACQmiINUOAOoCAAUACAl1INUOAOoCAAQABAkmGnEgADYBAAAA.',
Dr='Dròòid:BAAANQADCgQIBAABNQAECggIFgACAMwaAA==.',
Du='Dubdred:BAAANQADCgQIBAAAAA==.Duhon:BAAANQADCgQIBAAAAA==.Dumptruck:BAAANQAECgUIBgAAAA==.',
Dw='Dwín:BAAANQAECgQIBgAAAA==.',
['Dê']='Dêals:BAAANQAECgUICQAAAA==.',
El='Eliselyia:BAAANQADCgQICQAAAA==.Ellierose:BAAANQAECgUIBwAAAA==.',
Em='Ems:BAAANQADCgUICwAAAA==.',
En='Enjin:BAAANQAECgYIDAAAAA==.Enragedbeef:BAAANQADCgQIBAABNQAECgcIEwABAAAAAA==.Entheogen:BAAANQAECgQIBAAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Et='Ethereall:BAAANQAECgcIEQAAAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgEIAQAAAA==.Evilice:BAAANQAECgUICwAAAA==.Evoka:BAAANQAECgEIAQAAAA==.',
Fa='Fallendevout:BAAANQAECgQIBgAAAA==.Fallentroll:BAABNQAECoEaAAIGAAkJHBljEQDJAgAGAAkJHBljEQDJAgAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayye:BAAANQADCggIDAAAAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAAANQAECgEIAQAAAA==.',
Fl='Floatpass:BAAANQAECgcIDwAAAA==.',
Fr='Frizz:BAAANQADCgUIAwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzynuttz:BAAANQADCggICAAAAA==.Fuzzypally:BAAANQAECgUIBwAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQIBAABNQAECggIFgACAMwaAA==.Galiagante:BAAANQADCggIDAAAAA==.Gallynna:BAAANQAECgUICgAAAA==.Galorfax:BAAANQAECgMIAwAAAA==.Galushi:BAAANQADCgQIBwAAAA==.Garm:BAAANQAECgYICwABNQAECgYIDQABAAAAAA==.',
Ge='Gelinea:BAAANQADCgMIBAAAAA==.Genovese:BAEANQADCgYIDAABNQAECgQIBgABAAAAAA==.',
Gi='Gilgaroth:BAAANQAECgUIBwAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAMIBQADANMbAA==.',
Go='Gobo:BAAANQAECgMIBQAAAA==.',
Gr='Graysonn:BAAANQADCggIFAAAAA==.Greafox:BAAANQAECgMIAwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAAANQAECgYIBgABNQAFFAMIBQADANMbAA==.Gundrakk:BAAANQAECgQIBgAAAA==.Gunnr:BAAANQAECgQICQAAAA==.',
He='Heid:BAAANQADCgQIBwAAAA==.',
Hi='Higanbana:BAACNQAFFIEGAAIHAAMJxBPBBAAFAQAHAAMJxBPBBAAFAQA1AAQKgSAAAgcACQkMIioDAI8DAAcACQkMIioDAI8DAAAA.Himawari:BAAANQAECgQICAABNQAFFAMIBgAHAMQTAA==.Himejoshi:BAACNQAFFIEFAAIDAAMJ0xtqAAAtAQADAAMJ0xtqAAAtAQA1AAQKgSgAAgMACQnoJW0AANUDAAMACQnoJW0AANUDAAAA.Hippocampus:BAAANQADCggIGQAAAA==.Hirys:BAAANQAECgcIEgAAAA==.',
Ho='Holybeks:BAAANQADCgQIBAABNQAECgUIBwABAAAAAA==.Holysmite:BAAANQADCgUIBQAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECgUIBgABAAAAAA==.',
['Há']='Háldrin:BAABNQAECoEcAAMIAAkJUBxaCQD4AgAIAAkJuhtaCQD4AgAJAAEJNCZbtABrAAAAAA==.',
Ic='Icëcrëam:BAAANQADCggICAAAAA==.',
Im='Imbue:BAAANQAECgMIBQAAAA==.Imbuer:BAAANQADCggIGQAAAA==.',
In='Innil:BAAANQAECgUICwAAAA==.',
Ja='Jarda:BAAANQAECgUIDwAAAA==.',
Je='Jessix:BAAANQADCgcIBgAAAA==.Jezebel:BAAANQAECgQIBQAAAA==.',
Ji='Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMIAwAAAA==.',
Jo='Jomadead:BAAANQAECgEIAQABNQAECgcIEgABAAAAAA==.Jomas:BAAANQAECgcIEgAAAA==.',
Ju='Judera:BAAANQAECgUICQAAAA==.',
Ka='Kaing:BAAANQADCgcIDQAAAA==.Kaladen:BAAANQAECgMIBgAAAA==.Kalysti:BAAANQAECgMIBAAAAQ==.Kaoticnature:BAAANQADCgIIAwAAAA==.Karolg:BAAANQAECgMIAwAAAA==.Katostrafic:BAAANQAECgUIBwAAAA==.Katrynna:BAAANQADCgQIBAAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAAANQAECgcIEgAAAA==.',
Ki='Killidan:BAAANQAECgUIBwAAAA==.Kirklees:BAAANQADCgcIBgAAAA==.',
Ko='Kodama:BAAANQAECgMIBQAAAA==.Koi:BAAANQADCgcIEgAAAA==.Kookiemon:BAAANQADCgEIAQAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Kromag:BAAANQADCgYIBgAAAA==.',
Ku='Kunpochiken:BAAANQABCgEIAQABNQAECgUIBwABAAAAAA==.',
Ky='Kyanna:BAAANQADCgcIBQAAAA==.',
La='Ladifantasie:BAAANQADCgUIBQAAAA==.Laria:BAAANQAECgQIBAAAAA==.Laxinmedium:BAAANQADCgQIBwAAAA==.',
Le='Leenei:BAAANQADCgcIBgAAAA==.Lenlaar:BAAANQADCgcIAwAAAA==.Levande:BAAANQADCgYIDAAAAA==.',
Li='Lifeblume:BAAANQADCgUIBQAAAA==.Lilithandria:BAAANQAECgUIBgAAAA==.Linamar:BAAANQADCgcIFwAAAA==.',
Lo='Loaq:BAAANQAECgYIDwAAAA==.Longbottom:BAAANQAECgUIBQABNQAECgUIBgABAAAAAA==.Lorbert:BAAANQADCgQIAwABNQAECgcIEAABAAAAAA==.Lostalot:BAAANQAECgUICgAAAA==.',
Lu='Luxæterna:BAAANQAECgYIDwAAAA==.',
Ly='Lyphiara:BAAANQADCgcIDAABNQAECgUICgABAAAAAA==.',
Ma='Malice:BAAANQAECgcIEgAAAA==.Mandwandos:BAAANQAECgUIBwAAAA==.Maraliss:BAAANQADCggIHAAAAA==.',
Me='Melaunis:BAAANQADCgUIBQAAAA==.Meowzer:BAAANQAECgQIBgABNQAECgcIEwABAAAAAA==.Meteora:BAAANQAECggIEgAAAA==.',
Mi='Mideel:BAAANQADCgcIBgAAAA==.Migolbearcow:BAAANQAECgUICQAAAA==.Missed:BAAANQAECgIIAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIIAwABAAAAAA==.Missrae:BAAANQADCgYICgAAAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgQIBgAAAA==.Mooniè:BAAANQADCggIHAAAAA==.Moosenuts:BAAANQAECgIIAgAAAA==.Moriavus:BAAANQAECgQIDAAAAA==.Morocha:BAAANQAECgQIBAAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.',
Mu='Muragore:BAAANQADCgcIFAAAAA==.',
My='Mychropien:BAAANQAECgIIAgAAAA==.Myylus:BAAANQADCgQICQAAAA==.',
['Mö']='Mökes:BAABNQAECoEZAAIEAAkJhCAGAQB0AwAEAAkJhCAGAQB0AwAAAA==.',
Na='Nadroj:BAAANQADCgQIBAAAAA==.Nazzersaurus:BAAANQAECgQIBQAAAA==.',
Ne='Nec:BAAANQADCgYICgAAAA==.Necrøtic:BAAANQAECgUICAAAAA==.Nekosmasta:BAAANQABCgIIAgAAAA==.Neodin:BAAANQADCgcIFwAAAA==.Nevermiss:BAAANQAECgMIBQAAAA==.',
Ni='Nightjewel:BAAANQADCgQIBwAAAA==.',
No='Noggs:BAAANQADCggICAAAAA==.Notmewasyou:BAAANQAECgQIBQAAAA==.',
Nu='Nuali:BAAANQADCggIDAABNQAECgQICQABAAAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCgUIBQAAAA==.',
On='Onlyspins:BAAANQAECgYIBwAAAA==.',
Or='Orý:BAAANQAECgYIDgAAAA==.',
Ox='Oxosorrel:BAAANQABCgYIDgAAAA==.',
Oz='Ozzmodious:BAAANQADCgQIBAAAAA==.',
Pa='Paladan:BAAANQAECgUIBwAAAA==.Palagi:BAAANQAECgEIAQAAAA==.Pallyana:BAAANQAECgQIBQAAAA==.Pallyfosho:BAAANQADCgMIAwAAAA==.Pallymcbeall:BAAANQADCgYIDQAAAA==.Paprikaman:BAAANQADCgcIAwAAAA==.Parallax:BAAANQADCgEIAQAAAA==.Pariahrain:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Parishealton:BAAANQAECgQIBAAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgUIBQAAAA==.',
Po='Poulsbo:BAAANQADCgcIBgAAAA==.Pozole:BAAANQADCggICAAAAA==.',
Pr='Prominence:BAAANQAECgUICgAAAA==.Promisques:BAAANQADCgYICgAAAA==.Prozak:BAAANQAECgMIBAAAAA==.',
Pw='Pwomf:BAAANQAECgQIBAAAAA==.',
Py='Pyrolily:BAAANQAECgEIAQAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCgcIDAAAAA==.',
Ra='Rabyd:BAAANQADCggICAAAAA==.Raegasm:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgUIDQAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAAANQAECgUICAAAAA==.',
Re='Reesespiecez:BAAANQAECgIIBAAAAA==.Rellidana:BAAANQADCgYIBgAAAA==.Rexi:BAABNQAECoEcAAIKAAgJvA8BFAAiAgAKAAgJvA8BFAAiAgAAAA==.',
Ri='Rickcando:BAAANQAECgIIAgAAAA==.Ricshard:BAAANQAECgQIBQAAAA==.',
Rm='Rmft:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQADCggIFQAAAA==.',
Ry='Ryuk:BAAANQADCgMIAwAAAA==.',
['Rà']='Ràein:BAAANQAECgQIBwAAAA==.',
['Ró']='Ród:BAABNQAECoEdAAILAAgJnh/SIgCUAgALAAgJnh/SIgCUAgAAAA==.',
Sa='Saalira:BAAANQADCgQICQAAAA==.Sabellice:BAAANQAECgQIBQAAAA==.Sakonna:BAABNQAECoEaAAIKAAgJrRTWEQBIAgAKAAgJrRTWEQBIAgAAAA==.Salinoria:BAAANQAECgQICQAAAA==.Sandymaw:BAAANQABCgYICgABNQAECgcIEwABAAAAAA==.Sarlius:BAAANQAECgYIDgAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAAANQAECgQIBAAAAA==.Savin:BAAANQADCggIGAAAAA==.',
Sc='Scavenger:BAAANQADCggIHQAAAA==.',
Se='Selkamonk:BAAANQAECgUICgAAAA==.Seniorbold:BAAANQAECgQIBQAAAA==.Sentrina:BAABNQAECoEaAAIMAAgJzR2NCQClAgAMAAgJzR2NCQClAgAAAA==.Seraph:BAAANQAECgEIAgAAAA==.Seshy:BAAANQAECgcIEwAAAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannoon:BAAANQADCggIDAAAAA==.Sharr:BAAANQADCgYIDAAAAA==.Shekzeer:BAAANQAECgUIDQAAAA==.Shiverr:BAAANQAECgMIAwAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQADCgUIBQABNQAECgUICwABAAAAAA==.',
Si='Siegatrox:BAAANQADCgIIAQAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.',
Sk='Skizem:BAAANQABCgUICQAAAA==.Skott:BAAANQADCggIFQAAAA==.',
Sl='Sleepadin:BAAANQADCggIFAAAAA==.Sleepyr:BAAANQAECgYIDAAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.Snowstorm:BAAANQAECgEIAQAAAA==.',
So='Soakra:BAAANQAECgUIBQAAAA==.Solignis:BAACNQAFFIEFAAMNAAMJACT8AABsAAAOAAIJpiOoCwDYAAANAAEJtCT8AABsAAA1AAQKgSEAAw4ACQm1JfoDAMADAA4ACQmYJfoDAMADAA0AAQkQJ2UVAHEAAAAA.Soniviolence:BAAANQAECgUIBQAAAA==.Soohots:BAAANQAECgEIAwAAAA==.',
Sp='Sparklehappy:BAAANQAECgEIAQAAAA==.',
St='Stausa:BAAANQADCgcIBwAAAA==.Stormcreek:BAAANQADCgQIBAAAAA==.Storri:BAAANQAECgYIDwAAAA==.',
Su='Suzuya:BAAANQADCgYICwAAAA==.',
Sw='Swiftmage:BAACNQAFFIEFAAMPAAMJMRhJDgAFAQAPAAMJVRRJDgAFAQAQAAEJ+iL5AQBqAAA1AAQKgSEAAg8ACQkJJQUDAMsDAA8ACQkJJQUDAMsDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sy='Sygh:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Syndragonkin:BAAANQAECgQIBgAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgQIBgAAAA==.',
Ta='Talyndis:BAACNQAFFIEOAAIIAAYJrBrpAAA3AgAIAAYJrBrpAAA3AgA1AAQKgR4AAggACQlnIwsDAIMDAAgACQlnIwsDAIMDAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Taze:BAAANQAECgUIBgABNQAECggIFgACAMwaAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.Terrika:BAAANQAECgEIAQAAAA==.Tetshajeh:BAAANQAECgcIEgAAAA==.Teyliana:BAAANQADCgcIBgAAAA==.',
Th='Thillarick:BAAANQAECgMIAwAAAA==.Thwip:BAABNQAECoEVAAMJAAgJBh3HJwBhAgAJAAcJsx7HJwBhAgAIAAYJZQe+KgAWAQAAAA==.',
Ti='Tikwid:BAAANQAECgMIAwAAAA==.Tiranmyashol:BAAANQAECgcIEAAAAA==.',
To='Tomoya:BAAANQAECgcIEgAAAA==.Too:BAAANQADCgEIAQAAAA==.Toothdk:BAAANQAECgQIBwAAAA==.',
Tr='Treebreak:BAAANQAECgQIBAAAAA==.',
Ud='Udari:BAAANQADCgUIBQAAAA==.Udarii:BAAANQAECgIIAgAAAA==.',
Um='Umàdbrah:BAAANQAECgUIBQAAAA==.',
Un='Unbelievable:BAAANQAECgMIAwAAAA==.Unprovoked:BAAANQAECgYIEQAAAA==.',
Va='Valamor:BAAANQAECgQIBQAAAA==.Varia:BAAANQADCgMIAwABNQAECgUICwABAAAAAA==.',
Ve='Veefib:BAAANQAECgUICAAAAA==.Velvettwitch:BAAANQAECgUICwAAAA==.Vendler:BAAANQAECgMIBAAAAA==.Verahla:BAAANQADCgQIBQAAAA==.Vermis:BAAANQAECgQICwAAAA==.Veryaverage:BAAANQAECgIIBAAAAA==.Vexation:BAAANQADCgUIDAAAAA==.',
Vi='Vicarious:BAAANQADCggIHAAAAA==.Vidreaux:BAAANQAECgQICQAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.',
Vo='Voidofvoids:BAAANQADCggICAAAAA==.Votingromney:BAAANQADCgYIBwABNQAECgUIDQABAAAAAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAAANQAECgYIDQAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
Wa='Waldorf:BAAANQADCgYIDAAAAA==.Walleroot:BAAANQAECgUIBQAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQADCgcIBQAAAA==.',
Wo='Wolfpup:BAAANQAECgIIAQABNQAECgUICQABAAAAAA==.Worstelf:BAAANQAECgQIBwAAAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCgQIBwAAAA==.',
Yf='Yfelshammy:BAAANQAECgQIBgAAAA==.',
Yv='Yvaldi:BAAANQADCggIEgABNQAFFAEIAQABAAAAAA==.Yvonnél:BAAANQADCgYICgAAAA==.',
Za='Zanebusby:BAAANQAECgQIBQAAAA==.Zankru:BAAANQADCgEIAQAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgEIAQABNQAECgUIDQABAAAAAA==.Zartash:BAAANQAECgQIBgAAAA==.Zatharis:BAAANQADCggIGgAAAA==.',
Ze='Zelik:BAAANQABCgcIBwABNQAECgYIDgABAAAAAA==.Zevellian:BAAANQADCggIDgABNQAECgcIEQABAAAAAA==.',
Zm='Zmona:BAAANQAECgUICwAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQADCgMIAwAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgQIBAABAAAAAA==.',
['Ðr']='Ðragonshaft:BAAANQAECgUICQAAAA==.',
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
