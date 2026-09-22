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

local lookup = {'Unknown-Unknown','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Arms','Mage-Arcane','DemonHunter-Vengeance','Monk-Windwalker','Rogue-Assassination','Druid-Feral','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','DemonHunter-Devourer','Rogue-Subtlety','Hunter-Marksmanship','Priest-Holy','Priest-Discipline','Paladin-Retribution','Warlock-Affliction','Warrior-Protection','Shaman-Elemental','Evoker-Preservation','Monk-Mistweaver','Monk-Brewmaster','Warrior-Fury','Mage-Frost',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aarazi:BAAANQAECgUJDAAAAA==.',
Ab='Abbinormal:BAAANQADCgQIBwAAAA==.Abolish:BAAANQABCgIIAgAAAA==.',
Ae='Aeriss:BAAANQADCgUICwAAAA==.Aezili:BAAANQADCgcIBwAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAAANQAECgUICAAAAA==.',
Ah='Ahegao:BAAANQAECgEIAQAAAA==.Ahnari:BAAANQAECgEJAQAAAA==.',
Ak='Akkadien:BAAANQAECgcIEQAAAA==.Akumunter:BAAANQAECgUJBwAAAA==.',
Al='Alacardias:BAAANQAECgUJCQAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.Allthesnacks:BAAANQADCgMIAwAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAAANQAFFAEJAgAAAA==.',
An='Anassand:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.Andimorph:BAAANQAECgUJCQAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAAANQAECgYJCwAAAA==.',
Aq='Aqualight:BAAANQAECgIIAgABNQAECggIFwACAEgiAA==.Aquaterra:BAABNQAECoEXAAICAAgKSCI1DQAhAwACAAgKSCI1DQAhAwAAAA==.Aquina:BAAANQAECgQJBgABNQAECggIFwACAEgiAA==.',
Ar='Arakadia:BAABNQAECoEaAAIDAAcKwQ4tPACpAQADAAcKwQ4tPACpAQAAAA==.Artoriaz:BAAANQADCgcJCwAAAA==.Aruteeru:BAAANQAECgUJBgAAAA==.',
As='Aseanna:BAAANQAECgEIAQAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
Au='Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgABAAAAAA==.',
Av='Avarous:BAAANQAECgUICAAAAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAAANQAFFAMJBAAAAA==.',
Az='Azaireos:BAAANQADCgUIDAAAAA==.Azulpunkt:BAAANQAECgcIEwAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAAANQAECgUICgAAAA==.Barbedwire:BAAANQAECgEIAQAAAA==.',
Be='Bearmao:BAAANQAECgYIEgAAAA==.Beknight:BAAANQAECgcIDgAAAA==.Belfas:BAAANQAECgEIAQAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAAANQAECgMJAwAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAAANQAECgEIAQAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bludnite:BAABNQAECoEcAAIEAAgKxxu9IABQAgAEAAgKxxu9IABQAgAAAA==.',
Bo='Bokchoi:BAAANQAECgUIBQAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQAECgEJAQAAAA==.Bruute:BAABNQAECoEYAAIFAAgK1CJHHQAJAwAFAAgK1CJHHQAJAwAAAA==.',
Bu='Budplatinum:BAAANQADCggIFAAAAA==.',
['Bå']='Båcon:BAAANQABCgQIBAAAAA==.',
Ca='Cairo:BAAANQAECgcJEwAAAA==.Capitalchaos:BAAANQAECgQICQABNQAECggIGwAGACMOAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAABNQAECoEbAAIGAAgKIw6TiAABAgAGAAgKIw6TiAABAgAAAA==.',
Ce='Cell:BAABNQAECoEZAAIHAAgKFyE4AgACAwAHAAgKFyE4AgACAwAAAA==.Ceviche:BAAANQAECgYJCAAAAA==.Ceàrrdòrn:BAAANQAECgMIBAAAAA==.',
Ch='Chibí:BAAANQADCggIFgAAAA==.Chillzmatic:BAAANQAECgEJAgAAAA==.Chudbucket:BAAANQAECgYJEAAAAA==.',
Ci='Cirillø:BAAANQABCggICAABNQAECgcIEAABAAAAAA==.',
Cl='Clovergold:BAAANQAECgcJEwAAAA==.Clyde:BAAANQAECgUIDAAAAA==.',
Co='Corbis:BAEANQAECgUJCwAAAA==.',
Cr='Crevarus:BAAANQADCgUJDAAAAA==.Crimsonjeybi:BAAANQAECgcJCAAAAA==.Crunchwich:BAAANQADCgcJBgAAAA==.',
Cu='Cutename:BAAANQADCgEIAQAAAA==.',
Cy='Cynamyn:BAAANQADCgcJBgAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgUIDAAAAA==.Daevarys:BAAANQADCgEIAQAAAA==.Dakhran:BAAANQADCgIJBAAAAA==.Dan:BAAANQAECgEJAgAAAA==.Darkdemon:BAAANQAECgQJBgAAAA==.Darlord:BAAANQADCgcJBgAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIBAABNQAECggIGQAIAPQhAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQADCgcJBgAAAA==.Demônlock:BAAANQADCgcJAwAAAA==.Desideria:BAAANQAECgMIAwAAAA==.Despondence:BAAANQAFFAEIAQAAAA==.Desynn:BAAANQAECgYJDgAAAA==.',
Di='Divinesyn:BAAANQADCgYIBgAAAA==.',
Dj='Djelysium:BAAANQADCgcJAwAAAA==.Djtaki:BAABNQAECoEaAAIJAAgKDhdBFABZAgAJAAgKDhdBFABZAgAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAUICAAKACofAA==.Doncarlos:BAABNQAECoEdAAILAAgKth3HHwC9AgALAAgKth3HHwC9AgAAAA==.Dorn:BAAANQADCgUIBQAAAA==.Dotty:BAAANQAECgEIAQAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFIEKAAMMAAUKLBJzBgC1AAANAAMKtw7pDgDmAAAMAAIKXRdzBgC1AAA1AAQKgSAAAw0ACQpFIV4XANwCAA0ACAosIV4XANwCAAwABAomGg4kACwBAAAA.',
Dr='Drdevoted:BAAANQADCgIIAgAAAA==.Dròòid:BAAANQADCgQJBAABNQAECggIHAAEAMcbAA==.',
Du='Dubdred:BAAANQADCgUIBwAAAA==.Duhon:BAAANQADCgQIBAAAAA==.Dumptruck:BAAANQAECgYICQAAAA==.',
Dw='Dwín:BAAANQAECgYIDAAAAA==.',
['Dê']='Dêals:BAAANQAECgYJDQAAAA==.',
El='Elasper:BAAANQADCgcIBwAAAA==.Eliselyia:BAAANQADCgQJDAAAAA==.Ellierose:BAAANQAECgUIBwAAAA==.',
Em='Ems:BAAANQADCgcJDQAAAA==.',
En='Enjin:BAAANQAECgcJEwAAAA==.Enragedbeef:BAAANQAECgEJAQABNQAECggIHwAOADUZAA==.Entheogen:BAAANQAECgUJCQAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Et='Ethereall:BAAANQAECgcIEQAAAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgEIAQAAAA==.Evilice:BAAANQAECgcIEgAAAA==.Evoka:BAAANQAECgEIAgAAAA==.',
Fa='Faavibear:BAAANQAECggJAQAAAA==.Fallendevout:BAAANQAECgQJCAAAAA==.Fallentroll:BAABNQAECoEdAAMDAAkKzRkIGACpAgADAAkKPBkIGACpAgAEAAMK4RqkYADuAAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayye:BAAANQADCggJFAAAAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAAANQAECgEIAgAAAA==.Fishstick:BAAANQADCggICAAAAA==.',
Fl='Floatpass:BAABNQAECoEZAAIGAAgKUho0XAB5AgAGAAgKUho0XAB5AgAAAA==.',
Fo='Foot:BAAANQADCgcJCQAAAA==.',
Fr='Frizz:BAAANQADCgcJAwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzypally:BAAANQAECgcJDgAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQJBAABNQAECggIHAAEAMcbAA==.Galiagante:BAAANQADCggJDAAAAA==.Gallynna:BAAANQAECgYJEAAAAA==.Galorfax:BAAANQAECgUICAAAAA==.Galushi:BAAANQADCgUIDAAAAA==.Garm:BAAANQAECgYIEAABNQAECggJGAAFANQiAA==.',
Ge='Gelinea:BAAANQADCgMIBgAAAA==.Genovese:BAEANQADCgYJDAABNQAECgUJCwABAAAAAA==.',
Gi='Gilgaroth:BAAANQAECggIDAAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAUICAAKACofAA==.',
Go='Gobo:BAAANQAECgMICAAAAA==.',
Gr='Graysonn:BAAANQADCggIFAAAAA==.Greafox:BAAANQAECgcICgAAAA==.Grrimreaperr:BAAANQADCgcIBwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAAANQAECgYIBgABNQAFFAUICAAKACofAA==.Gundrakk:BAAANQAECgQICAAAAA==.Gunnr:BAAANQAECgQICQAAAA==.Gunthorian:BAAANQAECgMJAwAAAA==.',
He='Heart:BAAANQAECgUIAwAAAA==.Heid:BAAANQADCgUIDAAAAA==.Helldozer:BAAANQADCgcIBwAAAA==.',
Hi='Higanbana:BAACNQAFFIELAAIPAAUK4g/UAwCgAQAPAAUK4g/UAwCgAQA1AAQKgSgAAg8ACQqwIoYDAI8DAA8ACQqwIoYDAI8DAAAA.Himawari:BAAANQAECgUJDQABNQAFFAUJCwAPAOIPAA==.Himejoshi:BAACNQAFFIEIAAIKAAUKKh82AAD3AQAKAAUKKh82AAD3AQA1AAQKgSsAAgoACQoVJqkAAMwDAAoACQoVJqkAAMwDAAAA.Hippocampus:BAAANQAECgMIAwAAAA==.Hirys:BAABNQAECoEUAAIQAAcKBRD0GQDNAQAQAAcKBRD0GQDNAQAAAA==.',
Ho='Holybeks:BAAANQADCgQIBAABNQAECgcIDgABAAAAAA==.Holydaddy:BAAANQADCgcIBwAAAA==.Holysmite:BAAANQAECgQIBAAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECgYICQABAAAAAA==.',
['Há']='Háldrin:BAABNQAECoEgAAMRAAkKbSA0CAAjAwARAAkK1h80CAAjAwALAAEKNCYv3QBmAAAAAA==.',
Ia='Iamprepared:BAAANQABCgEIAQAAAA==.',
Ic='Icëcrëam:BAAANQADCggICAAAAA==.',
Ih='Ihavegrass:BAAANQADCgYIBgAAAA==.',
Im='Imbue:BAAANQAECgUJCgAAAA==.Imbuer:BAAANQADCggIGQAAAA==.',
In='Innil:BAAANQAECgYJEQAAAA==.',
Je='Jessix:BAAANQAECgEIAQAAAA==.Jezebel:BAAANQAECgUJCgAAAA==.',
Ji='Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMJAwAAAA==.',
Jo='Jomadead:BAAANQAECgUJBgABNQAECgkJFgACAIEUAA==.Jomas:BAABNQAECoEWAAICAAkKgRRbLQBIAgACAAkKgRRbLQBIAgAAAA==.Jovaar:BAAANQADCgUIBQAAAA==.',
Ju='Judera:BAAANQAECgYIDwABNQAECggICAABAAAAAA==.Juditis:BAAANQABCgUJBQAAAA==.',
Ka='Kaing:BAAANQAECgEIAQAAAA==.Kaladen:BAAANQAECgQJCAAAAA==.Kalec:BAAANQADCgUJBQAAAA==.Kalysti:BAAANQAECgMIBAAAAQ==.Kaoticnature:BAAANQADCgQIBwAAAA==.Karolg:BAAANQAECgMIAwAAAA==.Katostrafic:BAAANQAECgUICwAAAA==.Katrynna:BAAANQADCgQICAAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAABNQAECoEdAAMHAAgKvCCIAgDpAgAHAAgKvCCIAgDpAgAPAAcKgA4IJQDHAQAAAA==.',
Ki='Killidan:BAAANQAECgcJDgAAAA==.Kirklees:BAAANQADCgcIBgAAAA==.',
Ko='Kodama:BAAANQAECgUICgAAAA==.Koi:BAAANQADCgcIEgABNQAECgYJEAABAAAAAA==.Kookiemon:BAAANQADCgYJBgAAAA==.Kookiesplz:BAAANQADCggJCAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Kromag:BAAANQADCgYIBgAAAA==.',
Ku='Kunpochiken:BAAANQABCgEIAQABNQAECgUICwABAAAAAA==.',
Ky='Kyanna:BAAANQADCgcJBQAAAA==.',
La='Ladifantasie:BAAANQADCgUIBQAAAA==.Laria:BAAANQAECgUJCQAAAA==.Laxinmedium:BAAANQADCgUIDAAAAA==.',
Le='Leenei:BAAANQADCgcJBgAAAA==.Lenlaar:BAAANQADCgcJAwAAAA==.Levande:BAAANQADCgYIDAAAAA==.',
Li='Lifeblume:BAAANQADCgUIBQAAAA==.Lilithandria:BAAANQAECgYJCQAAAA==.Linamar:BAAANQADCggIHwAAAA==.',
Lo='Loaq:BAABNQAECoEZAAMSAAgKyhJwNwAQAgASAAgKyhJwNwAQAgATAAMK4gjWEgCOAAAAAA==.Longbottom:BAAANQAECgUJBQABNQAECgYICQABAAAAAA==.Lorbert:BAAANQADCgQIAwABNQAECggIGwAFAFETAA==.Lostalot:BAAANQAECgYJEAAAAA==.',
Lu='Luxæterna:BAABNQAECoEZAAIUAAcKGB2kTQAeAgAUAAcKGB2kTQAeAgAAAA==.',
Ly='Lyphiara:BAAANQADCggIFAABNQAECgYJEAABAAAAAA==.',
Ma='Malice:BAABNQAECoEVAAMVAAgK0xPwBAAKAgAVAAgK0xPwBAAKAgAMAAIKZAWXVgBWAAAAAA==.Mandwandos:BAAANQAECgUJBwAAAA==.Maraliss:BAAANQAECgEIAQAAAA==.',
Me='Melaunis:BAAANQADCgYJCwAAAA==.Meowzer:BAAANQAECgQJBgABNQAECggIHwAOADUZAA==.Meteora:BAABNQAECoEWAAIWAAkKNBmeBgCCAgAWAAkKNBmeBgCCAgAAAA==.',
Mi='Mideel:BAAANQADCgcJBgAAAA==.Migolbearcow:BAAANQAECgYJDwAAAA==.Missed:BAAANQAECgIJAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIJAwABAAAAAA==.Missrae:BAAANQADCgYICgAAAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgUICwAAAA==.Mooniè:BAAANQAECgEIAQAAAA==.Moosenuts:BAAANQAECgIJAwAAAA==.Moriavus:BAAANQAECgYIEgAAAA==.Morocha:BAAANQAECgQICAAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.',
Mu='Muragore:BAAANQAECgEIAQAAAA==.',
My='Mychropien:BAAANQAECgUJBwAAAA==.Myylus:BAAANQADCgQICQAAAA==.',
['Mö']='Mökes:BAABNQAECoEbAAIMAAkKeyLnAACPAwAMAAkKeyLnAACPAwAAAA==.',
Na='Nadroj:BAAANQADCgQICAAAAA==.Naosu:BAAANQADCgEJAQAAAA==.Nazzersaurus:BAAANQAECgUJCgAAAA==.',
Ne='Nec:BAAANQADCgcIEQAAAA==.Necrøtic:BAAANQAECgYJDgAAAA==.Nekosmasta:BAAANQABCgIIAgAAAA==.Neodin:BAAANQADCggIHwAAAA==.Nevermiss:BAAANQAECgUICgAAAA==.',
Ni='Nightjewel:BAAANQADCgUIDAAAAA==.',
No='Noggs:BAAANQADCggIDwAAAA==.Notmewasyou:BAAANQAECgQICQAAAA==.',
Nu='Nuali:BAAANQAECgYJBgAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCggJDQAAAA==.',
On='Onlyspins:BAAANQAECgYIBwAAAA==.',
Or='Orý:BAABNQAECoEYAAIXAAgKPRpbJgCFAgAXAAgKPRpbJgCFAgAAAA==.',
Os='Oslatem:BAAANQADCgcIBwAAAA==.',
Ox='Oxosorrel:BAAANQABCggJEAAAAA==.',
Oz='Ozzmodious:BAAANQADCgQIBgAAAA==.',
Pa='Paladan:BAAANQAECgcJDgAAAA==.Palagi:BAAANQAECgIIAwAAAA==.Pallyana:BAAANQAECgUJCgAAAA==.Pallymcbeall:BAAANQADCggIDwAAAA==.Paprikaman:BAAANQADCgcJAwAAAA==.Parallax:BAAANQADCgEIAQAAAA==.Pariahrain:BAAANQAECgMIAwABNQAECgYJDAABAAAAAA==.Parishealton:BAAANQAECgYICgAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgUIBQAAAA==.',
Pe='Perprotrus:BAAANQABCgIIAgABNQAECggIHAAEAMcbAA==.',
Po='Poulsbo:BAAANQADCgcJBgAAAA==.Pozole:BAAANQAECgYJBgAAAA==.',
Pr='Prominence:BAAANQAECgUICgAAAA==.Promisques:BAAANQADCgYJEAAAAA==.Prozak:BAAANQAECgYJCgAAAA==.',
Pw='Pwomf:BAAANQAECgYJBgAAAA==.',
Py='Pyrolily:BAAANQAECgQJBQAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCggIFAAAAA==.',
Ra='Rabyd:BAAANQADCggICAAAAA==.Raegasm:BAAANQADCgYIBgAAAA==.Raha:BAAANQADCgYJDgAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAAANQAECgYJDgAAAA==.Rastakan:BAAANQADCgcJBwABNQAECggJGAAFANQiAA==.',
Re='Reesespiecez:BAAANQAECgcJCwAAAA==.Rellidana:BAAANQADCgcJBgAAAA==.Retradormi:BAAANQADCgQIBQAAAA==.Rexi:BAABNQAECoEeAAIOAAgKvA9cGgAGAgAOAAgKvA9cGgAGAgAAAA==.',
Ri='Rickcando:BAAANQAECgIJAwAAAA==.Ricshard:BAAANQAECgUJCgAAAA==.Ridjeckgron:BAAANQADCgcIBwAAAA==.',
Rm='Rmft:BAAANQADCgMJBgABNQAECgUICAABAAAAAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQAECgEIAQAAAA==.',
Ry='Rylia:BAAANQADCgcIBwAAAA==.Ryuk:BAAANQADCgMIAwAAAA==.',
['Rà']='Ràein:BAAANQAECgQJCwAAAA==.',
['Ró']='Ród:BAABNQAECoEfAAIUAAgKnh8FNQCBAgAUAAgKnh8FNQCBAgAAAA==.',
['Rø']='Røth:BAAANQADCgYJBgAAAA==.',
Sa='Saalira:BAAANQADCgUIDgAAAA==.Sabellice:BAAANQAECgUJCgAAAA==.Sakonna:BAABNQAECoEcAAIOAAgK6RQWFwAzAgAOAAgK6RQWFwAzAgAAAA==.Salinoria:BAAANQAECgQICQABNQAECgYJBgABAAAAAA==.Sandymaw:BAAANQABCgYICgABNQAECggIHwAOADUZAA==.Sarlius:BAABNQAECoEZAAILAAgKUCbYBgB/AwALAAgKUCbYBgB/AwAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAAANQAECgQIBAABNQAECgUIAwABAAAAAA==.Savin:BAAANQAECgEIAQAAAA==.',
Sc='Scavenger:BAAANQAECgEIAQAAAA==.Scorchin:BAAANQAECggIAQAAAA==.',
Se='Selkamonk:BAAANQAECgYJEAAAAA==.Seniorbold:BAAANQAECgYIBwAAAA==.Sentrina:BAABNQAECoEiAAIYAAkKSRyNCADlAgAYAAkKSRyNCADlAgAAAA==.Seraph:BAAANQAECgEIAgAAAA==.Seshy:BAABNQAECoEfAAIOAAgKNRmOEgB4AgAOAAgKNRmOEgB4AgAAAA==.Seshymutedme:BAAANQAECgQIBAABNQAECggIHwAOADUZAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannoon:BAAANQADCggIFAAAAA==.Sharr:BAAANQADCgYJDAAAAA==.Shekzeer:BAABNQAECoEZAAQIAAgK9CGgDgCRAgAIAAYKliWgDgCRAgAZAAYKeRpFEQDlAQAaAAEK5iOaHgBnAAAAAA==.Shiverr:BAAANQAECgUJCAAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQAECgEJAQABNQAECgYIDAABAAAAAA==.',
Si='Siegatrox:BAAANQADCgIIAQAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.',
Sk='Skizem:BAAANQABCgYIDAAAAA==.Skott:BAAANQADCggIHQAAAA==.',
Sl='Sleepadin:BAAANQAECgYJBgAAAA==.Sleepyr:BAAANQAECgYIDQAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECgQICQABAAAAAA==.Snowstorm:BAAANQAECgEIAQAAAA==.',
So='Soakra:BAAANQAECgcJDAAAAA==.Solignis:BAACNQAFFIEKAAMbAAUK+h1yAAA+AQAFAAQKcx2SBwCYAQAbAAMK+SJyAAA+AQA1AAQKgSoAAwUACQqLJkgBAPADAAUACQp8JkgBAPADABsAAgoEJ/wSAOQAAAAA.Soniviolence:BAAANQAECgcIDAAAAA==.Soohots:BAAANQAECgUICAAAAA==.',
Sp='Sparklehappy:BAAANQAECgMIBAAAAA==.',
St='Stausa:BAAANQADCgcIBwAAAA==.Stormcreek:BAAANQADCgUIBgAAAA==.Storri:BAABNQAECoEbAAMSAAcKvhc2PAD5AQASAAcKvhc2PAD5AQAOAAUKngYkOADYAAAAAA==.',
Su='Suzuya:BAAANQADCgcJEQAAAA==.',
Sw='Swiftmage:BAACNQAFFIEKAAMcAAUKDB6RAAAaAQAGAAQKdxW8DwBiAQAcAAMKPh6RAAAaAQA1AAQKgSoAAxwACQrVJRYAAPQDABwACQrCJRYAAPQDAAYACQoJJQAHALMDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sy='Sygh:BAAANQAECgEIAQABNQAECgUIAwABAAAAAA==.Syndragonkin:BAAANQAECgUJCwAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgQIBgAAAA==.',
Ta='Talyndis:BAACNQAFFIEUAAIRAAYK4x6IAQBHAgARAAYK4x6IAQBHAgA1AAQKgSEAAhEACQprI9YDAH8DABEACQprI9YDAH8DAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Taze:BAAANQAECgUJBwABNQAECggIHAAEAMcbAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.Terrika:BAAANQAECgUJBgAAAA==.Tetshajeh:BAABNQAECoEeAAMFAAgKaR+/LgCvAgAFAAgK9h6/LgCvAgAWAAMKCxsWGgDyAAAAAA==.Teyliana:BAAANQADCgcJBgAAAA==.',
Th='Thillarick:BAAANQAECgUICAAAAA==.Thromanor:BAAANQADCgEIAQAAAA==.Thwip:BAABNQAECoEZAAMLAAgKIB1tNgBaAgALAAcK0R5tNgBaAgARAAYKZQeyNAAHAQAAAA==.',
Ti='Tikwid:BAAANQAECgUICAAAAA==.Tiranmyashol:BAABNQAECoEbAAIFAAgKUROdVgATAgAFAAgKUROdVgATAgAAAA==.',
To='Tomoya:BAAANQAECgcIEgAAAA==.Too:BAAANQADCgEIAQAAAA==.Toothdk:BAAANQAECgQJCAAAAA==.',
Tr='Treebreak:BAAANQAECgQJBAAAAA==.',
Ty='Tyrandrea:BAAANQADCgcIBwAAAA==.',
Ud='Udari:BAAANQAECgYJBgAAAA==.Udarii:BAAANQAECgIIAgAAAA==.',
Um='Umàdbrah:BAAANQAECgYICgAAAA==.',
Un='Unbelievable:BAAANQAECgUICAAAAA==.Unprovoked:BAABNQAECoEaAAIGAAgKZh89RgC4AgAGAAgKZh89RgC4AgAAAA==.',
Va='Valamor:BAAANQAECgUJCgAAAA==.Varia:BAAANQADCgQIBQABNQAECgYIDAABAAAAAA==.',
Ve='Veefib:BAAANQAECgUJDQAAAA==.Velvettwitch:BAAANQAECgUIEAAAAA==.Vendler:BAAANQAECgUJCQAAAA==.Verahla:BAAANQADCgQJCAAAAA==.Vermis:BAAANQAECgYJEQAAAA==.Veryaverage:BAAANQAECgMJBQAAAA==.Vexation:BAAANQADCgcIEAAAAA==.',
Vi='Vicarious:BAAANQAECgEIAQAAAA==.Vidreaux:BAAANQAECgUIDgAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.',
Vo='Voidofvoids:BAAANQAECgEIAQAAAA==.Votingromney:BAAANQAECgEJAQABNQAECggIGQAIAPQhAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAAANQAECgYIEwAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
Wa='Waldorf:BAAANQAECgMIAwAAAA==.Walleroot:BAAANQAECgUJBQAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQADCgcIBQAAAA==.',
Wo='Wolfpup:BAAANQAECggICAAAAA==.Worstelf:BAAANQAECgUICwAAAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCgUIDAAAAA==.',
Yf='Yfelshammy:BAAANQAECgYIDAAAAA==.',
Yv='Yvaldi:BAAANQAECgYIBgABNQAFFAEJAgABAAAAAA==.Yvonnél:BAAANQADCgYICgAAAA==.',
Za='Zanebusby:BAAANQAECgcJDAAAAA==.Zankru:BAAANQADCgEIAQAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgUJBgABNQAECggIGQAIAPQhAA==.Zartash:BAAANQAECgUJCwAAAA==.Zatharis:BAAANQAECgEIAQAAAA==.',
Ze='Zelik:BAAANQABCgcJBwABNQAECggIGQALAFAmAA==.Zevellian:BAAANQADCggIDgABNQAECgcIEQABAAAAAA==.',
Zm='Zmona:BAAANQAECgYIDAAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQADCgMIAwAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgUIAwABAAAAAA==.',
['Ðr']='Ðragonshaft:BAAANQAECgYJDwAAAA==.',
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
