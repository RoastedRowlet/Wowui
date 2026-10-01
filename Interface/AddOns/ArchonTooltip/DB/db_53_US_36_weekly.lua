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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Warrior-Protection','Rogue-Subtlety','DeathKnight-Blood','Evoker-Preservation','Paladin-Retribution','Shaman-Enhancement','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','Hunter-Survival','Hunter-BeastMastery','Monk-Windwalker','Hunter-Marksmanship','Mage-Frost','Warlock-Destruction','Rogue-Assassination','Warrior-Arms','Shaman-Restoration','Warrior-Fury','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Druid-Guardian','Evoker-Devastation','Druid-Balance','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Monk-Mistweaver','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Vengeance',}
local provider = {region='US',realm="Blade'sEdge",name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acotas:BAAANQADCgQJAwAAAA==.',
Ae='Aephiona:BAAANQADCgcIBwAAAA==.',
Af='Affli:BAABNQAECoEdAAIBAAgKNB28KgCjAgABAAgKNB28KgCjAgAAAA==.',
Ai='Aiunar:BAAANQAECgYIDAAAAA==.Aiupriesty:BAAANQAECgMIBAABNQAECgYIDAACAAAAAA==.',
Ak='Aka:BAAANQADCgIIAgAAAA==.Akaza:BAAANQADCggIDAAAAA==.',
Al='Alastiria:BAAANQAECgQIBQAAAA==.Aleinara:BAAANQAECgQIBgAAAA==.',
Am='Amazngrace:BAAANQADCgYIBgAAAA==.',
An='Andsey:BAAANQADCgcIDQABNQAECgMIBwACAAAAAA==.Annore:BAAANQAECgYIDgAAAA==.',
Aq='Aquelius:BAAANQAECgEIAQAAAA==.Aqular:BAAANQAECgUIEwAAAA==.',
Ar='Argyre:BAABNQAECoEjAAIDAAkKvSQcAQCwAwADAAkKvSQcAQCwAwAAAA==.Artifice:BAABNQAECoEYAAIEAAkKiiPjAQCYAwAEAAkKiiPjAQCYAwAAAA==.',
As='Asynic:BAAANQAECgMIAwAAAA==.Asynicl:BAAANQADCgYIBwAAAA==.',
Av='Avadakedevra:BAAANQAECggIAQAAAA==.',
Aw='Awooing:BAAANQADCggIDgABNQAECgQICQACAAAAAA==.',
Az='Azaziel:BAABNQAECoEbAAIFAAgKKQ4HRQCjAQAFAAgKKQ4HRQCjAQAAAA==.Azells:BAAANQADCgEIAQABNQAECgkJIgAGAMQhAA==.',
Ba='Bail:BAAANQAECgIIAgAAAA==.Bariesh:BAAANQADCgQIBAAAAA==.',
Be='Bearface:BAAANQADCgUIBQAAAA==.Behindyou:BAAANQADCgcICgAAAA==.Belgaria:BAAANQADCgcIFQAAAA==.Belloftrix:BAAANQAECgIIAgAAAA==.Berryknight:BAAANQAECgQICAAAAA==.Bewlzeye:BAAANQAECgQICAAAAA==.',
Bi='Bigjonmachne:BAAANQAECgYIEwABNQAECggIIAAHAC4gAA==.Binky:BAAANQADCgUIBQAAAA==.',
Bl='Blackdog:BAAANQAECgIIAwAAAA==.Blackguyy:BAAANQAECgUIEAAAAA==.Bloodletter:BAAANQABCgIIAgAAAA==.Bloodsail:BAAANQAECgYIBgAAAA==.',
Bo='Bollux:BAABNQAECoEZAAIIAAcKpxM1EQAKAgAIAAcKpxM1EQAKAgAAAA==.Bonetatter:BAAANQAECgEIAQAAAA==.Bongonnaink:BAABNQAECoEYAAMJAAgKbhb6GABCAgAJAAgKbhb6GABCAgAKAAEKjxnTHABLAAAAAA==.Bownyxia:BAAANQAECgYIBwABNQAFFAcIFAALAKsZAA==.Bowties:BAACNQAFFIEUAAQLAAcKqxmLAgCvAQALAAUK6RSLAgCvAQAMAAUKcRrFAwCbAQAFAAEKZw9pJgAuAAA1AAQKgTIABAsACQoBJuQBAL0DAAsACQoLJeQBAL0DAAwACQoKJe0EAI8DAAUAAgrjDFiWAGcAAAAA.',
Br='Brewfú:BAAANQADCgIJAgAAAA==.Brotie:BAACNQAFFIEIAAINAAMK6gzMCwDdAAANAAMK6gzMCwDdAAA1AAQKgSIAAg0ACQoQHOQVAK4CAA0ACQoQHOQVAK4CAAE1AAUUBwgUAAsAqxkA.',
Bt='Btmanight:BAAANQAECgQIBAAAAA==.',
Bu='Bullshiift:BAAANQADCgYIBgAAAA==.Burntbiscuit:BAAANQADCgUIBQAAAA==.Buugada:BAAANQADCggIFAAAAA==.',
Ca='Caedo:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.Caliclysm:BAAANQADCgQIBAAAAA==.Calischism:BAAANQAECgEIAgAAAA==.Canadiangoos:BAAANQADCgUJBQAAAA==.Cantspell:BAAANQAECgIIAgAAAA==.Carobnica:BAAANQADCgQJBAABNQADCgYIBgACAAAAAA==.Cavantes:BAAANQADCgIIAgAAAA==.',
Ce='Celaris:BAAANQADCggIGgAAAA==.Cell:BAAANQABCgIIAgAAAA==.Celleyna:BAAANQABCggICQAAAA==.',
Ch='Chataykay:BAAANQADCgcICgAAAA==.Chathsong:BAAANQADCggICAAAAA==.Chichichikin:BAAANQADCgcIBwAAAA==.Chunkyclaps:BAAANQADCgEIAQAAAA==.',
Ci='Citrus:BAABNQAECoEdAAMOAAgKTROMBABJAgAOAAgKTROMBABJAgAPAAEK6AkcDwFEAAAAAA==.',
Cn='Cn:BAABNQAECoEdAAIHAAgKISFILADbAgAHAAgKISFILADbAgAAAA==.',
Co='Codeman:BAABNQAECoEYAAIFAAgK/Ry4HQCOAgAFAAgK/Ry4HQCOAgAAAA==.Cordine:BAAANQADCgYIBgAAAA==.',
Cp='Cptinsaneo:BAACNQAFFIEKAAIMAAUKGRK0BAB7AQAMAAUKGRK0BAB7AQA1AAQKgSAAAgwACQpEHk8UAOECAAwACQpEHk8UAOECAAAA.',
Cr='Crimdh:BAAANQAECgQJBAABNQAFFAUICAAQAHYOAA==.Crimdk:BAAANQAECgUIBwABNQAFFAUICAAQAHYOAA==.',
Cz='Czin:BAAANQAECgIIAgAAAA==.',
Da='Dalén:BAAANQADCgUIBQAAAA==.',
De='Deathverses:BAACNQAFFIELAAIRAAUKESaMAgA0AgARAAUKESaMAgA0AgA1AAQKgUIAAhEACQrFJrEAAOkDABEACQrFJrEAAOkDAAAA.Demonbiscuit:BAABNQAECoEmAAINAAkKVSagAAD2AwANAAkKVSagAAD2AwAAAA==.Denarkis:BAAANQADCgQIBAAAAA==.Derpydawg:BAAANQADCgYIBgABNQAFFAQIBgASANoEAA==.Destructus:BAAANQAECgEIAgAAAA==.Deviancy:BAAANQAECgcIEwAAAA==.Devocean:BAAANQADCgUIBQAAAA==.Dexxt:BAAANQAECgIIAwAAAA==.',
Di='Dikslapp:BAAANQAECgUIBQAAAA==.Dirlin:BAAANQADCgQIBgAAAA==.Ditto:BAAANQADCggJNgAAAA==.',
Dl='Dlitinaro:BAAANQAECgcIEwAAAA==.',
Do='Donoph:BAAANQAECgcIEwAAAA==.Doomar:BAABNQAECoEaAAMBAAgK7h9zUwAQAgABAAYKyx9zUwAQAgATAAMKox+ALAAHAQAAAA==.Dordire:BAAANQAECgEJAQAAAA==.Dotzilla:BAAANQADCgEIAQAAAA==.',
Dr='Dragindznuts:BAAANQADCgQIBAAAAA==.Drayn:BAABNQAECoEeAAIBAAgK+R4VIQDNAgABAAgK+R4VIQDNAgAAAA==.Dreaveous:BAABNQAECoEdAAMBAAgKGwwrbADCAQABAAgKGwwrbADCAQATAAUKwwShOQDGAAAAAA==.Drugar:BAAANQAECgQIBgAAAA==.',
Du='Duint:BAAANQADCgcJDAAAAA==.',
Eb='Eborsisk:BAAANQADCgEIAQAAAA==.',
Ec='Eclipsion:BAAANQAECgMIBwAAAA==.',
Ee='Eelane:BAAANQAECgQICQAAAA==.',
El='Elementali:BAAANQAECgQIBAAAAA==.Ell:BAAANQADCgYIFAAAAA==.',
En='Endurall:BAAANQADCgQIBAABNQAECggIHgAUAL4WAA==.',
Er='Eradication:BAABNQAECoEaAAIVAAkKOiNnCAChAwAVAAkKOiNnCAChAwAAAA==.',
Et='Etheria:BAAANQAECgEIAQABNQAFFAQICQAWAH8TAA==.',
Ev='Evilexo:BAAANQADCgcIBwAAAA==.',
Ex='Exxotic:BAAANQABCgIIAgAAAA==.',
Fa='Faedia:BAAANQAECgMIAwABNQAECgMIBwACAAAAAA==.Fahlafflez:BAABNQAECoEYAAMXAAgKZg6fCgDSAQAXAAgKZg6fCgDSAQAVAAYKZgbWwwAAAQAAAA==.Fahros:BAABNQAECoEQAAIYAAcKvyM/fgBIAgAYAAcKvyM/fgBIAgAAAA==.Farkhaz:BAAANQADCggICAAAAA==.Faydron:BAAANQADCgMJAwABNQAECgUIDQACAAAAAA==.',
Fe='Felful:BAAANQAECgMIAwABNQAECggIJAAHAPMbAA==.',
Ff='Ffloyd:BAAANQADCgcIBwAAAA==.',
Fi='Fingielock:BAAANQAECgQIBwAAAA==.Firedeezball:BAAANQADCgcIBwAAAA==.Fishinfridge:BAAANQAECgcICQAAAA==.',
Fl='Flloyd:BAABNQAECoEXAAIZAAgKmwumJACcAQAZAAgKmwumJACcAQAAAA==.Floÿd:BAAANQADCgYIDAAAAA==.Fløyd:BAAANQADCgYIBgAAAA==.',
Fo='Folid:BAAANQADCgMIAgAAAA==.Fortwooh:BAAANQADCgYICwAAAA==.',
Fr='Francy:BAAANQAECgUICAAAAA==.',
Fu='Fuzzyspells:BAAANQADCgcIEgAAAA==.',
Ga='Gambling:BAAANQADCggICAAAAA==.Gatzul:BAAANQADCgMIBAABNQADCggICAACAAAAAA==.',
Gh='Ghostbladez:BAAANQAECgQJCAAAAA==.',
Gi='Gib:BAAANQADCgMIAwAAAA==.Girthmaster:BAAANQADCgQIBAAAAA==.',
Gn='Gnomaste:BAAANQADCgcIDQAAAA==.',
Go='Gomga:BAAANQADCggICAABNQAECggIJAAHAPMbAA==.Goththighs:BAACNQAFFIEPAAIYAAUKkR19CgDjAQAYAAUKkR19CgDjAQA1AAQKgR4AAhgACQorJLkmAC4DABgACQorJLkmAC4DAAAA.',
Gr='Grawler:BAAANQADCgYIBwAAAA==.Grimdk:BAAANQAECgIIBAAAAA==.Grissa:BAAANQAECggICgAAAA==.',
Gu='Gumgumfury:BAAANQADCggIFAAAAA==.',
Ha='Halru:BAAANQADCgUIBQAAAA==.Halzlok:BAAANQAECgUIDwAAAA==.Harmful:BAAANQADCgcIBwABNQAECggIHAAaAA4hAA==.',
He='Herøn:BAAANQADCgYICgAAAA==.',
Hi='Hilarie:BAAANQADCgYICwAAAA==.',
Hu='Hundigob:BAAANQABCgUIBgAAAA==.Hunterschmax:BAABNQAECoEWAAMPAAcKORE7cwDOAQAPAAcKORE7cwDOAQARAAMKxgeQUQCMAAAAAA==.',
Ic='Icemachine:BAAANQABCgUIBwAAAA==.',
Ih='Ihot:BAAANQAECgUIBwAAAA==.',
Ik='Ikayhaimahn:BAABNQAECoEaAAIbAAkKCSPTAQCSAwAbAAkKCSPTAQCSAwAAAA==.',
In='Incideranus:BAAANQADCggIBAAAAA==.Indishaman:BAABNQAECoEhAAIWAAgKBSW5CwBBAwAWAAgKBSW5CwBBAwAAAA==.',
Ir='Iris:BAAANQADCgMJAwAAAA==.Ironbound:BAAANQADCgUIBQABNQAECgYIGwAWAP8RAA==.',
Iv='Ivoric:BAAANQAECggICAAAAA==.',
Ja='Jabronygos:BAACNQAFFIEJAAIcAAUKgxJGAwCRAQAcAAUKgxJGAwCRAQA1AAQKgSUAAhwACQoSIA4GAAgDABwACQoSIA4GAAgDAAAA.Jarnroz:BAAANQADCgIIAgAAAA==.',
Je='Jeatalena:BAAANQAECgQICAAAAA==.Jengà:BAAANQADCggICAABNQAECgcIGgAYAPoiAA==.',
Jh='Jhara:BAAANQAECgMIBwAAAA==.',
Jo='Joeheals:BAAANQADCgUIBwAAAA==.',
Ju='Junior:BAAANQAECgEIAQABNQAECgkJIgAGAMQhAA==.',
Ka='Kablinkiaa:BAAANQADCgYICAAAAA==.Kaendas:BAAANQAECgEIAQAAAA==.Kaizayu:BAAANQADCggIEQAAAA==.Kalistria:BAAANQADCgIIAgAAAA==.Kalypso:BAAANQAECgQIBQAAAA==.Kamekazi:BAAANQADCggICQAAAA==.Katastrophic:BAAANQADCggIEwAAAA==.Katieylyn:BAAANQAECgYICQABNQAECgkJIgAGAMQhAA==.',
Ke='Keelanllan:BAAANQADCgYIFAAAAA==.Keilun:BAEANQADCgQIBAAAAA==.Kertzz:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Kew:BAAANQAECgEIAQAAAA==.',
Ki='Kizira:BAAANQABCggIDQABNQAECgMIBwACAAAAAA==.',
Kn='Kneecromance:BAAANQAECgEJAQAAAA==.Knightxl:BAAANQADCgEIAQAAAA==.',
Ko='Kokuten:BAAANQADCgQIBAABNQAFFAQICQAWAH8TAA==.Koral:BAAANQADCggIFAAAAA==.',
Ku='Kungfuhealya:BAAANQAECgYICwAAAA==.Kurog:BAAANQABCgEIAQAAAA==.',
La='Larrydale:BAAANQADCgYICwAAAA==.Lazerturkey:BAAANQADCgcIBwAAAA==.',
Le='Lea:BAAANQADCgcIBwABNQADCgYIBgACAAAAAA==.Lefica:BAAANQABCgIJAgAAAA==.Legacyx:BAAANQADCgcIDAABNQAECgkJGgAVADojAA==.Leonardorich:BAAANQADCgcIEQAAAA==.Leondis:BAABNQAECoEkAAIPAAgKlCDMFwAMAwAPAAgKlCDMFwAMAwAAAA==.Lexifu:BAACNQAFFIEGAAIZAAQKKAd/BgAjAQAZAAQKKAd/BgAjAQA1AAQKgSQAAxkACQrLIKUGADIDABkACQrLIKUGADIDAB0ABQoyDdBfAPsAAAAA.Lexipriest:BAAANQAECgYIDAAAAA==.Leylla:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.',
Li='Lightful:BAABNQAECoEkAAIHAAgK8xuaRQB4AgAHAAgK8xuaRQB4AgAAAA==.Lilbro:BAABNQAECoEiAAIVAAkKESVfBwCpAwAVAAkKESVfBwCpAwAAAA==.Lit:BAAANQADCggIDQABNQAECggIHAAaAA4hAA==.',
Lo='Lobais:BAAANQAECgMIAwABNQAECgUIBQACAAAAAA==.Lokii:BAAANQABCgMIAwAAAA==.',
Lu='Lumiel:BAAANQABCgcICwAAAA==.Lumos:BAAANQADCggICAAAAA==.Lumosmaxiima:BAAANQADCggIFAAAAA==.',
Ma='Madamme:BAAANQAECgYJDQAAAA==.Madkingzack:BAAANQAECgcIDgAAAA==.Madpriest:BAAANQADCgcIBwAAAA==.Maevea:BAAANQAECgMIAwAAAA==.Malagig:BAAANQADCgIJAgAAAA==.Malaviolence:BAAANQABCgcICAAAAA==.Malistavias:BAAANQAECgQIBgAAAA==.Malliki:BAAANQAECgUIBQAAAA==.Marnangus:BAABNQAECoEWAAIVAAcKIhgXawAEAgAVAAcKIhgXawAEAgABNQADCgYICAACAAAAAA==.Marnolkas:BAAANQADCggICgAAAA==.Mathan:BAABNQAECoEWAAIeAAcK2Cb2EAAhAwAeAAcK2Cb2EAAhAwAAAA==.Maudib:BAABNQAECoEbAAMbAAgK0xAWFACbAQAbAAgKbg8WFACbAQAfAAYKCwwGFABGAQAAAA==.Mavie:BAAANQABCgIIAgABNQAECgkJGgAVADojAA==.Mawile:BAAANQAECgYIDwAAAA==.',
Me='Meesha:BAAANQADCgcIEwAAAA==.Mehunta:BAAANQADCgIIAgAAAA==.Melinarra:BAAANQAECgUIBwAAAA==.Messe:BAABNQAECoEeAAMUAAgKvhZMGgBXAgAUAAgKLxZMGgBXAgAgAAYK8hN/CwB8AQAAAA==.Methious:BAAANQAECgMIBAAAAA==.',
Mi='Milicious:BAAANQABCgMJBQAAAA==.Mindcontrol:BAAANQADCgQIBAABNQAECgcIEQACAAAAAA==.',
Mo='Molatile:BAAANQAECgQIBwAAAA==.Montu:BAAANQADCggICAAAAA==.Moogyver:BAAANQABCggIEQAAAA==.Moonsguard:BAAANQADCgcIFwAAAA==.Moovit:BAAANQADCggIGgAAAA==.Mordekaíser:BAAANQAECgIIAgAAAA==.Moth:BAAANQAECgYIEwAAAA==.',
Mu='Murre:BAAANQADCgYIBgAAAA==.',
Na='Nasmiuu:BAAANQAECgIIBQAAAA==.',
Ne='Nekfury:BAAANQAECgQIBAAAAA==.Nepeta:BAAANQAECgYIEAAAAA==.Nevenel:BAAANQADCgMIAwAAAA==.',
Ni='Nivan:BAAANQAECgQIBQAAAA==.Niço:BAAANQAECgcICQAAAA==.',
No='Nocturnall:BAAANQADCgQIBAAAAA==.Noicce:BAABNQAECoEbAAIfAAgKnRs1BwCMAgAfAAgKnRs1BwCMAgAAAA==.Noicewar:BAAANQAECgIIAgAAAA==.Notcrims:BAABNQAFFIEIAAIQAAUKdg4gBQB0AQAQAAUKdg4gBQB0AQAAAA==.Notcrym:BAAANQAECgEIAQABNQAFFAUICAAQAHYOAA==.',
Nu='Nutz:BAAANQAECggICAAAAA==.',
Oa='Oakmoss:BAAANQAECggICwAAAA==.',
Or='Oralian:BAAANQADCggICAAAAA==.Orcleave:BAAANQAECgcIEAAAAA==.Orwan:BAAANQAECgQIBgAAAA==.',
Pi='Pisslowmage:BAAANQAECgEIAQABNQAECgcIEAACAAAAAA==.',
Pr='Pristene:BAAANQADCggICwAAAA==.Priyatama:BAAANQAECgQIBAAAAA==.',
Qu='Quorra:BAAANQADCgUJBgAAAA==.',
Ra='Ragecakes:BAAANQADCgYIBQAAAA==.Rakagar:BAAANQAECgUICQAAAA==.Raktot:BAAANQADCgEIAQAAAA==.Razluz:BAAANQADCgUIDQAAAA==.',
Re='Reue:BAABNQAECoElAAIhAAkKjQ/wEgD6AQAhAAkKjQ/wEgD6AQAAAA==.',
Rh='Rhaegos:BAAANQADCgcIEAABNQADCggICgACAAAAAA==.',
Ri='Riggzz:BAAANQAECgQIBAAAAA==.',
Ru='Ruuna:BAAANQABCgIIAgAAAA==.',
['Rí']='Rígg:BAAANQAECgEIAQAAAA==.',
Sa='Salla:BAAANQAECgQIBAAAAA==.',
Sc='Schmaximus:BAAANQADCgYJDgABNQAECgcIFgAPADkRAA==.Scrapyjack:BAAANQAECgcIDwABNQAECgcIEwACAAAAAA==.',
Se='Senna:BAAANQADCgMIAwAAAA==.',
Sh='Shale:BAABNQAECoEfAAIGAAgK2w1LHADDAQAGAAgK2w1LHADDAQAAAA==.Shammit:BAAANQADCgIIAgAAAA==.Shammytyme:BAAANQAECgYIEQAAAA==.Shampow:BAAANQAECgQIBgAAAA==.Shamyhagar:BAAANQADCgQIBAAAAA==.Shangtsung:BAABNQAECoEpAAMZAAkKPCIwBQBQAwAZAAkKPCIwBQBQAwAdAAIKZwzafgByAAAAAA==.Sharaiya:BAAANQAECgYIDQAAAA==.Sharkmanfive:BAAANQAECgQICAAAAA==.Shaure:BAAANQADCgIIAgAAAA==.Shearwater:BAAANQAECgYIDgAAAA==.',
Si='Silversesu:BAAANQAECgEJAQABNQAECgcIFwAYAM0TAA==.',
Sk='Skirtero:BAAANQADCgYIBgAAAA==.',
Sl='Slava:BAAANQAECggIDwAAAA==.Sledgehammer:BAAANQADCgIIAgAAAA==.Sleepytoker:BAAANQADCgYICwAAAA==.',
So='Softbaked:BAAANQADCgUIBQAAAA==.Soltergeist:BAABNQAECoEcAAIFAAgKuhg1LAArAgAFAAgKuhg1LAArAgAAAA==.',
Sp='Spine:BAAANQAECgUIBQAAAA==.',
Ss='Ssyd:BAAANQADCggICAAAAA==.',
St='Starlsbarkly:BAAANQADCgUIBQAAAA==.Steaknshock:BAAANQAECgYIBgAAAA==.Stormhoofs:BAACNQAFFIEIAAIIAAQKRRnHAQBwAQAIAAQKRRnHAQBwAQA1AAQKgTAAAggACQoMJYsAANkDAAgACQoMJYsAANkDAAAA.',
Su='Subzone:BAABNQAECoEXAAINAAgKHSDHFwCZAgANAAgKHSDHFwCZAgAAAA==.Sumnabiscuit:BAACNQAFFIEGAAMSAAQK2gQTAQATAQASAAQKBgQTAQATAQAYAAIKPwPiOgCDAAA1AAQKgRoAAxgACQpqFJWGADQCABgACQotEpWGADQCABIAAwqGE+4ZAN0AAAAA.Sunder:BAAANQADCgUIBQABNQAECggIJAAHAPMbAA==.Sunmaster:BAAANQAECgYIEQAAAA==.Supercharged:BAAANQADCggICAAAAA==.',
Sy='Synora:BAAANQABCgQIBAABNQAECgMIBwACAAAAAA==.',
Ta='Tackshi:BAAANQADCggIDAAAAA==.Tankinit:BAAANQADCggIGQAAAA==.Tarea:BAAANQADCgQIBwAAAA==.Tatterbone:BAAANQADCgYIEAABNQAECgEIAQACAAAAAA==.',
Te='Temufuzzy:BAAANQADCgEJAQAAAA==.Tenzink:BAABNQAECoEbAAIhAAgK/hpVDQBtAgAhAAgK/hpVDQBtAgAAAA==.',
Tf='Tflow:BAABNQAECoEaAAIYAAcK+iJ5UQC2AgAYAAcK+iJ5UQC2AgAAAA==.',
Th='Théworld:BAAANQABCgIIBAABNQADCgcIFwACAAAAAA==.',
Ti='Tindranga:BAAANQADCggIIQAAAA==.Titansgrippy:BAAANQAECgYIBgAAAA==.',
To='Tolbert:BAAANQADCgMIAwABNQADCgYIBgACAAAAAA==.Totemir:BAABNQAECoEYAAIiAAcKtCA5KAClAgAiAAcKtCA5KAClAgAAAA==.',
Tr='Trammatize:BAAANQAECgYIEwAAAA==.Triptamean:BAAANQADCggIEQAAAA==.',
Tw='Twobladebray:BAABNQAECoEYAAMjAAgKQBXOHQAqAgAjAAgKjxTOHQAqAgAkAAEK2BkpIgBLAAAAAA==.',
Un='Undeadnite:BAAANQADCgQIBQAAAA==.Unglaus:BAAANQAECgYIBgAAAA==.',
Uz='Uzington:BAABNQAECoEhAAIDAAkKSCB/AwAoAwADAAkKSCB/AwAoAwAAAA==.',
Va='Valeta:BAAANQADCggIIgAAAA==.Valzlok:BAAANQAECgMIBAAAAA==.Vanessa:BAAANQAECgcIEQAAAA==.Vanillacream:BAAANQADCgMIAwAAAA==.Vayth:BAAANQADCggICAAAAA==.',
Ve='Veilthorn:BAAANQAECgEIAQAAAA==.Velinieron:BAAANQAECgYICAAAAA==.Velithiri:BAAANQAECgQIDgAAAA==.Vellash:BAAANQADCgEIAQAAAA==.',
Vi='Vilencia:BAAANQABCgUICQAAAA==.Vince:BAAANQADCgUJBgAAAA==.Vinny:BAAANQABCgIIAgAAAA==.',
Vo='Vonulter:BAAANQAECgUICgAAAA==.',
Vy='Vylon:BAAANQAECgUICQAAAA==.Vynlandis:BAAANQAECgEIAQAAAA==.Vyrel:BAAANQADCgYICgAAAA==.',
['Vê']='Vêga:BAAANQAECgcIBwABNQAFFAQIBgASANoEAA==.',
Wa='Warbezerker:BAAANQADCgcIBwAAAA==.Waycores:BAAANQAECgUIBQAAAA==.',
We='Weenbean:BAAANQAECgYICAAAAA==.',
Wh='Whakoopa:BAAANQAECgQIBAAAAA==.Whispertree:BAABNQAECoEcAAIdAAkKohjpHQCqAgAdAAkKohjpHQCqAgAAAA==.Whìspèr:BAAANQAECgIIAgAAAA==.',
Wi='Wilddonut:BAAANQADCgQJBAAAAA==.Wixypoo:BAAANQAECgEIAQAAAA==.',
Wo='Woodnzhood:BAAANQAECgIIAwAAAA==.',
Wr='Wrylah:BAAANQAECgcIEgAAAA==.',
Wu='Wuxian:BAAANQADCgYIBgABNQAFFAQICQAWAH8TAA==.',
Wy='Wyyn:BAAANQADCggJIAAAAA==.',
Xa='Xanboi:BAABNQAECoEYAAMPAAgKOyTjHQDqAgAPAAcKUyXjHQDqAgARAAEKjxzYYABTAAAAAA==.',
Yi='Yikkle:BAAANQABCgIIAwAAAA==.',
Ys='Ysar:BAAANQAECgUIDQAAAA==.',
Yu='Yumzug:BAAANQADCgQIBAAAAA==.',
['Yô']='Yôshi:BAAANQAECggICAAAAA==.',
Ze='Zeebu:BAAANQAECgQICQAAAA==.Zephryyn:BAAANQADCgcIBwAAAA==.',
Zh='Zhilan:BAABNQAECoEgAAIZAAcK9QxnKgBlAQAZAAcK9QxnKgBlAQAAAA==.',
Zo='Zoda:BAAANQADCgQIBgAAAA==.Zoko:BAAANQAECgEIAQAAAA==.',
Zu='Zurgadhunter:BAAANQAECgcIEwAAAA==.Zuzuk:BAAANQADCgMIAwAAAA==.Zuzuki:BAAANQADCgQIBAAAAA==.',
['Zú']='Zúz:BAAANQAECgYICAAAAA==.',
['Ða']='Ðalinor:BAAANQADCggICAAAAA==.',
['Ðe']='Ðemaea:BAAANQADCgUIAwAAAA==.',
['Ði']='Ðittø:BAAANQADCgIIAgABNQADCggJNgACAAAAAA==.',
['Øc']='Øctø:BAAANQABCgEIAQAAAA==.',
['Ør']='Øreø:BAABNQAECoEYAAIkAAgKChyvBQB6AgAkAAgKChyvBQB6AgAAAA==.',
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
