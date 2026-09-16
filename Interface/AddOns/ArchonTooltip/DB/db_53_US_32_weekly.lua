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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Vengeance','Priest-Shadow','Druid-Balance','Monk-Windwalker','Druid-Restoration','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','DeathKnight-Unholy','Warrior-Arms','Warrior-Fury','Monk-Brewmaster',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=53,date='2026-09-15',data={Ae='Aeris:BAAANQAECgMIAwAAAA==.Aethwyn:BAAANQADCggIGgAAAA==.',
Ag='Agandaur:BAAANQADCgQIBAAAAA==.',
Ah='Ahnkala:BAAANQADCgUIDwAAAA==.',
Ai='Aigirlfriend:BAAANQAECgUIDgAAAA==.',
Al='Allupcreepy:BAAANQAECgIIAwAAAA==.',
Am='Amalyndi:BAAANQADCgcIDQAAAA==.Ambewlance:BAAANQAECgQIBAAAAA==.Amethystra:BAAANQADCggICAAAAA==.Amlu:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.',
An='Andaconda:BAAANQAECgEIAQAAAA==.Annimosity:BAAANQADCgUIBwAAAA==.Ansem:BAAANQADCggIDwAAAA==.Anúbis:BAAANQADCgUIDQAAAA==.',
Ap='Apawllo:BAAANQAECgEIAQAAAA==.Apep:BAAANQADCgcIGAAAAA==.Apostle:BAAANQAFFAQIBAAAAA==.',
Ar='Aramìs:BAAANQADCgIIAgAAAA==.Arcaya:BAAANQADCgYIBgAAAA==.Ariaka:BAAANQADCgEIAQAAAA==.Arleen:BAAANQAECgEIAQAAAA==.Arlida:BAAANQAECgUICQAAAA==.Artemys:BAAANQAECgQICAAAAA==.Aryto:BAAANQADCgUIBQAAAA==.',
As='Asketill:BAAANQADCgYIDwAAAA==.Asmodee:BAAANQAECgMIAwAAAA==.',
Au='Aure:BAAANQADCgYIDAAAAA==.Auren:BAAANQADCgIIAgAAAA==.',
Az='Azkadellia:BAAANQABCgQICAAAAA==.',
Ba='Baaloo:BAAANQABCgQIBAABNQADCgYIEgABAAAAAA==.Bainne:BAAANQADCgUICAAAAA==.Baitken:BAAANQADCggIEgABNQAECgIIAwABAAAAAA==.Barktea:BAAANQAECgEIAQAAAA==.Batharel:BAAANQADCggIEwAAAA==.Battcantdps:BAAANQADCgYIBgAAAA==.Battleground:BAAANQADCgMIAwAAAA==.',
Be='Bearen:BAAANQAECgQICAAAAA==.Beertrain:BAAANQAECgUICgAAAA==.Beesechurger:BAAANQAECgEIAQAAAA==.Belladue:BAAANQADCgYIEQAAAA==.Bellezza:BAAANQAECgcIEgAAAA==.',
Bh='Bhikku:BAAANQAECgQIBAABNQAECgYIDQABAAAAAA==.Bhilly:BAAANQADCggIEQAAAA==.',
Bi='Bigdumbcatqt:BAAANQAECgYICwAAAA==.Bigdumbkatqt:BAABNQAFFIEIAAICAAUJVhn/AgCmAQACAAUJVhn/AgCmAQAAAA==.Bignjuicy:BAAANQAECgQIBAAAAA==.Bimisi:BAAANQAECgUICgAAAA==.',
Bl='Blades:BAAANQADCgMIAwAAAA==.Bloodshhot:BAABNQAECoEUAAIDAAYJvgtgYAB9AQADAAYJvgtgYAB9AQAAAA==.Blueragebar:BAAANQAECgUICwAAAA==.',
Bo='Bobadasmash:BAAANQAECgYICgAAAA==.Bobitt:BAAANQADCggIGwAAAA==.Boddyknocker:BAAANQAECgEIAQAAAA==.Boombox:BAAANQADCgYIBgAAAA==.Boonerichard:BAAANQADCgcIFwAAAA==.Bouchewager:BAAANQADCgYIBgAAAA==.',
Br='Braina:BAAANQAECgEIAgAAAA==.Branwin:BAAANQADCgIIBQAAAA==.Braver:BAABNQAECoEiAAMEAAkJ0h2ZCQDzAgAEAAkJ0h2ZCQDzAgADAAEJuAuOyAA+AAAAAA==.Braverwar:BAAANQAECgIIAwABNQAECgkJIgAEANIdAA==.Brayedine:BAAANQADCgcIFAAAAA==.Break:BAACNQAFFIEHAAIFAAQJ5h88AgCOAQAFAAQJ5h88AgCOAQA1AAQKgR0AAgUACQlmJkkCANYDAAUACQlmJkkCANYDAAE1AAUUBAkHAAUA5h8A.Bromungandr:BAAANQADCgYIDAAAAA==.',
Bu='Buligerent:BAAANQADCggICAABNQAECgUIDgABAAAAAA==.',
By='Bynnyy:BAAANQAECgIIAgAAAA==.',
['Bù']='Bùbbles:BAAANQADCggICgAAAA==.',
Ca='Cadelsaya:BAAANQAECgcIEgAAAA==.Camandah:BAAANQAECgUIBQABNQADCgIIAgABAAAAAA==.Cammandzar:BAAANQAECgIIAgABNQADCgIIAgABAAAAAA==.Candy:BAAANQABCgQIAgAAAA==.Canman:BAAANQADCgYIEgAAAA==.Carlo:BAAANQAECgEIAwAAAA==.Carryout:BAAANQAECgQIBAAAAA==.Cassei:BAAANQADCgcIEgAAAA==.Castertroy:BAAANQAECgMIAwAAAA==.',
Ce='Celenia:BAAANQADCgcIGAAAAA==.',
Ch='Chee:BAAANQADCggIDgAAAA==.Cheetopaly:BAAANQAECgMIBAAAAA==.Chìgusa:BAAANQAECgUICgAAAA==.',
Ci='Circa:BAAANQADCgEIAQAAAA==.',
Cl='Clarimonde:BAAANQADCgEIAQAAAA==.Cleaveradius:BAAANQADCggICAABNQAECgcIDwABAAAAAA==.Clumonk:BAAANQAECgUIBQAAAA==.',
Co='Convoke:BAAANQADCggIEAABNQAFFAQIBAABAAAAAA==.Coosar:BAAANQAECgMIAwAAAA==.Coosedaplug:BAAANQADCgQIBAABNQAECgcIDQABAAAAAA==.Cooseyloosey:BAAANQAECgcIDQAAAA==.Coosinator:BAAANQAECgYICwABNQAECgcIDQABAAAAAA==.Cooterray:BAAANQAECgQIBQAAAA==.Corellon:BAAANQAECgEIAQAAAA==.Corinth:BAAANQAECgUICgAAAA==.',
Cr='Cratoz:BAAANQAECgUICQAAAA==.Croswind:BAAANQAECgYIDwAAAA==.',
Cy='Cyndrine:BAABNQAECoEXAAIGAAgJWiQEAQBOAwAGAAgJWiQEAQBOAwAAAA==.Cyrani:BAAANQAECgcIEgAAAA==.',
Da='Dadipps:BAAANQAECgcIDAAAAA==.Daggumit:BAAANQADCgYIEQAAAA==.Dagnei:BAAANQADCgUICwAAAA==.Daltina:BAAANQAECgIIAwAAAA==.Dannyboone:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Dareael:BAAANQAECgUIBgAAAA==.Daurgoth:BAAANQAECgUICAAAAA==.',
De='Deadbydrand:BAAANQAECgMIAwAAAA==.Deathndspark:BAAANQAECgUICgAAAA==.Deathpuma:BAAANQAECggIEQAAAA==.Deathrowe:BAAANQAECgUIBwAAAA==.Dednevoker:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Deelyte:BAAANQADCgcIGAAAAA==.Demonvann:BAAANQADCggICAAAAA==.Demítrá:BAAANQADCgIIAgABNQAECgYIEAABAAAAAA==.Denouncer:BAAANQAECgQIBAABNQAECgcIDwABAAAAAA==.Derca:BAAANQAECgEIAQAAAA==.Dethork:BAAANQADCgcIDAAAAA==.',
Di='Dieds:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Dienne:BAEANQAECgEIAQAAAA==.Dietunicorn:BAAANQADCggIGwABNQAECgcIGQAHAAAXAA==.Dinarra:BAAANQADCgQIBAAAAA==.Disahzter:BAAANQAECgUICAAAAA==.',
Do='Docdrood:BAAANQADCgcIBwABNQAECgUICAABAAAAAA==.Docmonk:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Docpriest:BAAANQAECgUICAAAAA==.Donlazul:BAAANQADCgQIBAAAAA==.Dotlotto:BAAANQAECgEIAQAAAA==.',
Dr='Draconoth:BAAANQAECgEIAQAAAA==.Dragfin:BAAANQADCgQIBAAAAA==.Dragonir:BAAANQAECgIIAgABNQAECgYIDQABAAAAAA==.',
Du='Dunstird:BAAANQADCgIIAgABNQAECgYIBwABAAAAAA==.',
Dy='Dyami:BAAANQAECgEIAgAAAA==.',
['Dè']='Dèadèyè:BAAANQADCggIDgAAAA==.',
Ea='Eatmorechkn:BAAANQAECgUICgAAAA==.',
Ee='Eellonwy:BAAANQADCgUICwAAAA==.Eemerald:BAAANQADCgcIGAAAAA==.',
Eg='Egna:BAAANQAECgEIAQAAAA==.',
El='Eldiablo:BAAANQAECgUIDgAAAA==.Electricblu:BAAANQAECgMIAwAAAA==.Elizaa:BAAANQAECgUICQAAAA==.',
Em='Emmadar:BAAANQADCgYIBgABNQAECgUIDgABAAAAAA==.',
Eu='Euripidus:BAAANQADCgEIAQAAAA==.',
Ev='Evilclared:BAAANQADCgQIBgAAAA==.Evildean:BAAANQADCgYICgAAAA==.',
Ex='Execute:BAAANQADCgUIBQAAAA==.',
Fa='Fanya:BAAANQADCgYIBgABNQAECgkJGQAHADUZAA==.Fathernatur:BAAANQADCgYICQAAAA==.',
Fe='Fenrigaar:BAAANQAECggIEgAAAA==.',
Ff='Ffsa:BAAANQAECgcIEQAAAA==.',
Fi='Fillin:BAAANQADCgYIDwAAAA==.Filô:BAAANQAECggIDwAAAA==.',
Fl='Flame:BAAANQADCgEIAQAAAA==.',
Fo='Foxyladie:BAAANQAECgEIAQAAAA==.',
Fr='Frasti:BAAANQADCgYIEAAAAA==.Frodes:BAAANQABCgYIBwAAAA==.Frostmage:BAAANQAECgUIDgAAAA==.',
Fu='Fuegoblazeit:BAAANQABCgIIAgAAAA==.Furbucket:BAAANQAECgIIBAAAAA==.Futonhunts:BAAANQAECgcIEgAAAA==.',
Fy='Fylerw:BAAANQAECgQIBgAAAA==.',
Ga='Gailyn:BAAANQADCgYICgAAAA==.Gardros:BAAANQABCgQIBAAAAA==.',
Gh='Ghostrideher:BAAANQAECgUIBgAAAA==.',
Gi='Gigadad:BAABNQAECoEYAAIDAAkJYCSWBACHAwADAAkJYCSWBACHAwAAAA==.',
Go='Gornthemonki:BAAANQADCgcICgAAAA==.Goyahokasinj:BAAANQADCgQIBwAAAA==.',
Gr='Griannee:BAAANQAECgUICwAAAA==.Grislix:BAAANQAECgUICQAAAA==.Grismistea:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Gryffin:BAAANQAECgUICQAAAA==.',
Gu='Guidance:BAAANQADCgcIBwAAAA==.Gummies:BAAANQABCgYIDgAAAA==.',
['Gâ']='Gânk:BAAANQAECgUICgAAAA==.',
Ha='Hanrekt:BAAANQADCggICQAAAA==.Happiness:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.',
He='Heavensbliss:BAAANQADCggICAABNQAECgUIDgABAAAAAA==.Heavychevy:BAAANQAECgUIBQAAAA==.Heriel:BAAANQAECgQIBQABNQAECgYIDQABAAAAAA==.Hexquisite:BAAANQADCgIIAgABNQAFFAQIBAABAAAAAA==.',
Hi='Hildoehealz:BAAANQAECgEIAQAAAA==.',
Ho='Holybit:BAAANQADCgcIBwAAAA==.Hotsjkpurge:BAAANQADCgQIBAAAAA==.',
Hu='Humphrees:BAAANQAECgUIDgAAAA==.',
Hy='Hydrospin:BAAANQADCgQIBAAAAA==.Hypocrisy:BAAANQADCgIIBQAAAA==.',
['Hà']='Hàtos:BAAANQAECgYICQAAAA==.',
Id='Idot:BAAANQADCgUICgABNQAECgQIBQABAAAAAA==.',
Il='Illidave:BAAANQADCgYIBwABNQAECgIIAgABAAAAAA==.',
In='Inebriatas:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Invissibill:BAAANQAECgQIBQAAAA==.',
Is='Ishaa:BAAANQAECgEIAgAAAA==.',
Iv='Ivanä:BAAANQAECgEIAQAAAA==.',
Iz='Izax:BAAANQAECgQICgAAAA==.',
Ja='Jaddzia:BAAANQABCgQIBAAAAA==.Jadestone:BAAANQADCgYIDAAAAA==.Jarcor:BAAANQABCgQIBAAAAA==.',
Je='Jeffray:BAAANQABCgQIBAAAAA==.',
Jo='Jonsneew:BAAANQADCgQIBAAAAA==.',
Ju='Junglefu:BAAANQADCgIIAgAAAA==.Jupitus:BAAANQAECgUIBQAAAA==.Justin:BAAANQAECgQIBAAAAA==.',
['Jû']='Jûstin:BAAANQAECgEIAQABNQAECgkJGAAIAGAbAA==.',
Ka='Karma:BAAANQAECgMIAwAAAA==.Katalania:BAAANQAECgMIAwAAAA==.',
Ke='Keeshama:BAAANQADCgIIAgAAAA==.Keiwhenua:BAAANQAECgUIBwAAAA==.Kelinn:BAAANQADCgcIDAAAAA==.Kelzier:BAAANQAECgMIAwABNQAECgYIDQABAAAAAA==.Kenthel:BAAANQAECgcIDwAAAA==.Kezt:BAAANQADCgUIBQABNQADCgcIBwABAAAAAA==.',
Ki='Kiplander:BAAANQAECgQIEAAAAA==.Kitheryn:BAAANQAECgEIAQAAAA==.',
Kl='Klitt:BAAANQADCggIFAAAAA==.',
Ko='Komosky:BAACNQAFFIEHAAIJAAQJLgVUAwANAQAJAAQJLgVUAwANAQA1AAQKgR8AAgkACQnIEW8PAEMCAAkACQnIEW8PAEMCAAAA.Korry:BAAANQADCgcIDQAAAA==.Kortanis:BAAANQAECgQIBQAAAA==.',
Kr='Krakìn:BAAANQADCgcIEwAAAA==.',
Ku='Kushage:BAAANQAECgUICQAAAA==.',
['Kü']='Küngfury:BAAANQADCgQIBAAAAA==.',
La='Laerik:BAAANQABCgEIAQAAAA==.Landissa:BAAANQAECgUICQAAAA==.Larcenciel:BAAANQAECgIIBAAAAA==.Larryholmes:BAAANQABCgQIBAABNQADCggICAABAAAAAA==.',
Le='Letmehelpyou:BAAANQAECgcIDwAAAA==.',
Li='Licky:BAAANQAECgUICQAAAA==.Lihan:BAAANQAECgEIAgAAAA==.Lilieth:BAAANQADCggICgAAAA==.Lily:BAAANQAECgUICgAAAA==.Lively:BAAANQAECgMIAwAAAA==.',
Lo='Lockedtoit:BAAANQADCgYIDAAAAA==.Loverocket:BAAANQAECgUICQAAAA==.',
Lu='Lunastorm:BAAANQABCgQIAwAAAA==.',
Ly='Lyshia:BAAANQAECgcIEgAAAA==.',
['Lí']='Líghthand:BAAANQAECgQIBQAAAA==.',
['Lý']='Lýght:BAAANQADCgcIDQAAAA==.',
Ma='Magedown:BAAANQAECgUICQAAAA==.Magician:BAAANQADCggICAAAAA==.Manpumper:BAAANQAECgMIAwAAAA==.Margor:BAAANQADCggIGAABNQAECgIIAgABAAAAAA==.Mattdemon:BAAANQAECgcIEgAAAA==.',
Me='Meanzy:BAAANQADCgQIBAAAAA==.Meliany:BAAANQADCggIGQAAAA==.Meliorate:BAABNQAECoEYAAMIAAkJJBOkIQAoAgAIAAgJ0xSkIQAoAgAKAAQJLwb1KQDRAAAAAA==.Meowch:BAAANQAECgUICgAAAA==.',
Mi='Mikachu:BAAANQAECggIEwABNQAECgkJGgALAJohAA==.Miksi:BAAANQADCgYICQABNQADCgYIEgABAAAAAA==.Miradele:BAAANQAECgIIAwAAAA==.Miraxx:BAAANQADCgYIEgAAAA==.Misscleö:BAAANQAECgUICAAAAA==.Miyoshi:BAAANQAECgUICgAAAA==.',
Mo='Moosakka:BAAANQAECgUIDAAAAA==.Moosesiah:BAAANQABCgYICgABNQAECgUIBwABAAAAAA==.Moovinthru:BAAANQADCgUIDQAAAA==.Moraxes:BAAANQAECgUIBgAAAA==.Mordenkainen:BAAANQAECgMIAwAAAA==.Morphidmage:BAAANQADCgUIBQAAAA==.Motoko:BAAANQADCgYIDAAAAA==.',
Mu='Muaadib:BAAANQAECgEIAQABNQAECgYIDwABAAAAAA==.',
My='Mydin:BAAANQAECgYICgAAAA==.Myssaphra:BAABNQAECoEWAAMMAAgJnxbIJwApAgAMAAgJnxbIJwApAgANAAEJFwPizAAlAAAAAA==.',
['Mì']='Mìsawa:BAAANQAECgMIAwAAAA==.',
Na='Nakai:BAAANQAECgYICwAAAA==.Nasatra:BAAANQADCgQIBAAAAA==.Nastijiggle:BAAANQAECgUICQAAAA==.Nazrien:BAAANQABCgUIBQAAAA==.Nazrion:BAAANQABCgEIAQAAAA==.',
Nc='Nc:BAAANQAECgUICQAAAA==.',
Ne='Nexxa:BAAANQAECgQIBgAAAA==.',
Ni='Nightshadow:BAAANQADCgQIBAAAAA==.Niqkle:BAAANQAECgcIDQAAAA==.Nitebane:BAAANQAECgIIBwAAAA==.',
No='Nohurtscooby:BAAANQADCgYIEQAAAA==.Notadh:BAAANQADCgQIBAAAAA==.',
Ns='Nstagatr:BAAANQAECgIIAgAAAA==.',
Ny='Nyxandria:BAAANQABCgQIBAAAAA==.Nyxi:BAAANQABCgQIBAAAAA==.',
Oa='Oak:BAAANQAECgIIAgAAAA==.',
Ol='Olari:BAAANQABCgIIAgAAAA==.Oldoriel:BAAANQADCgYIBgAAAA==.Olehanna:BAAANQAECgUIDAAAAA==.Olestrid:BAAANQADCgYIBgABNQAECgUIDAABAAAAAA==.',
On='Oni:BAAANQADCgYICAAAAA==.',
Op='Opioid:BAAANQADCgcIEwAAAA==.Opsec:BAAANQAECgIIAgABNQAECgUICQABAAAAAA==.Opsèc:BAAANQAECgUICQAAAA==.',
Or='Orsa:BAAANQADCggICAAAAA==.',
Pe='Peachshock:BAECNQAFFIEIAAIMAAUJBRJfAgC9AQAMAAUJBRJfAgC9AQA1AAQKgRsAAwwACQnQJXwBALkDAAwACQnQJXwBALkDAA0ABAnhH6ROAG4BAAAA.Peebee:BAAANQADCgYIBgAAAA==.Perfectlock:BAAANQAECgUIBgAAAA==.',
Pi='Pigog:BAAANQAECgIIAgAAAA==.',
Po='Pordgio:BAAANQADCggIEwAAAA==.Pozzi:BAAANQAECgUIBQAAAA==.',
Pr='Praypal:BAAANQADCgQIBAAAAA==.',
Ps='Psuedolus:BAAANQAECgQIBQAAAA==.Psålm:BAAANQAECgYICgAAAA==.',
Pu='Pulshadow:BAABNQAECoEeAAIHAAkJeSOoAgCYAwAHAAkJeSOoAgCYAwAAAA==.Pumah:BAAANQADCgYIEgAAAA==.',
Qt='Qtclaps:BAAANQADCgQIBAAAAA==.',
Qu='Quartzecoatl:BAAANQADCgQIBAAAAA==.',
Ra='Raamen:BAAANQADCgYIEgAAAA==.Raellia:BAAANQAECgUIDgAAAA==.Raimmey:BAAANQADCgYICgAAAA==.Rajia:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Ralune:BAAANQAECgQIBQAAAA==.Ranes:BAAANQAECgUIDgAAAA==.Razagual:BAAANQAECggICAAAAA==.',
Re='Redback:BAAANQABCgEIAQAAAA==.Redxelementz:BAAANQAECggIEgAAAA==.Redxpastakan:BAAANQADCgUIBQABNQAECggIEgABAAAAAA==.Renasen:BAAANQAECgQIBgAAAA==.Reno:BAAANQAECgUIBwAAAA==.Resiretha:BAAANQAECgIIAgAAAA==.Revelynn:BAAANQAECgUIDAAAAA==.Rexkwondo:BAAANQAECgQIBAAAAA==.',
Ri='Rivliam:BAAANQAECgEIAQAAAA==.Rizzn:BAAANQADCgUICQABNQAECgcIDwABAAAAAA==.',
Ro='Rook:BAAANQAECgIIAgAAAA==.Rooxxy:BAAANQAECgQICwAAAA==.Roxxyyzz:BAAANQAECgEIAQABNQAECgQICwABAAAAAA==.',
Ru='Rumikang:BAAANQADCgIIAgABNQAECgUIDgABAAAAAA==.',
Ry='Rynoh:BAAANQADCgcIBwAAAA==.Rythrik:BAAANQAECgIIAwAAAA==.Ryujinorsted:BAAANQADCgUIBQAAAA==.',
Sa='Sainted:BAABNQAECoEfAAMOAAkJzRQIGwCIAgAOAAkJzRQIGwCIAgAFAAcJ6hSJTADEAQAAAA==.Sanoks:BAAANQAECgUICgAAAA==.Sanokz:BAAANQADCgYIBgAAAA==.Savira:BAAANQAECgMIAwAAAA==.',
Sc='Scaleorva:BAAANQAECgIIAwAAAA==.',
Se='Seraphìm:BAAANQAECgMIBAAAAA==.Seïnaru:BAAANQADCggIEwAAAA==.',
Sh='Shadenova:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Shadyballs:BAAANQAECgQIBQAAAA==.Shakypete:BAAANQADCggICAABNQAECgQIEAABAAAAAA==.Shamysosa:BAAANQAECgIIAgAAAA==.Shiionknow:BAAANQADCgQIBAAAAA==.Shinjí:BAAANQAECgUICQABNQAECgkJHwAPAPMiAA==.Shmob:BAAANQAECgEIAgAAAA==.Shnappz:BAAANQAECgQIBwAAAA==.Shwillarou:BAAANQAECgUICwAAAA==.Shádôws:BAAANQADCgYICwAAAA==.',
Si='Sinergee:BAAANQAECgEIAQAAAA==.Sinnj:BAAANQADCgcIDQAAAA==.',
Sk='Skinsey:BAAANQADCgYIDQAAAA==.Skinzey:BAAANQADCgYICwAAAA==.Skinzy:BAAANQABCgYIBwAAAA==.Skycrush:BAAANQADCgUIBQAAAA==.',
Sl='Slanie:BAAANQAECgQIBAAAAA==.Slingerz:BAAANQAECgcIEgAAAA==.Slowmeaux:BAAANQADCgEIAQAAAA==.',
Sm='Smalldragon:BAAANQADCgYIBQAAAA==.Smoky:BAAANQAECgQIBwAAAA==.',
Sn='Sneakpastya:BAAANQADCgIIAgAAAA==.Sneakyg:BAAANQAECgQIBwABNQAECgYIDQABAAAAAA==.Snoochie:BAAANQAECgQIBgAAAA==.',
So='Solkar:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Sollis:BAAANQAECgEIAQAAAA==.Solohoes:BAAANQADCggICQAAAA==.Soulcoil:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Soulshock:BAAANQAECgQIBAAAAA==.',
Sp='Spazzchel:BAAANQADCgcIGAAAAA==.Spiritbox:BAABNQAECoEYAAIMAAkJTyRJAwCLAwAMAAkJTyRJAwCLAwABNQAFFAQIBAABAAAAAA==.Spruce:BAAANQADCggICAAAAA==.Sprucemoose:BAAANQADCgIIBQABNQADCgQIBAABAAAAAA==.',
St='Stahlman:BAAANQAECgQICAAAAA==.Stalpho:BAAANQAECgQICQAAAA==.Starblessed:BAAANQADCgMIBgABNQADCggIHAABAAAAAA==.Starkind:BAAANQADCggIHAAAAA==.Starliner:BAAANQAECgcIDAAAAA==.Stasis:BAAANQAECgIIAgABNQAFFAQIBAABAAAAAA==.Strahd:BAAANQADCgQICQAAAA==.Styrke:BAAANQADCgYIBgAAAA==.Styrmir:BAAANQADCgMIAwAAAA==.',
Su='Subza:BAAANQAECgcIEgAAAA==.',
Sw='Swagtistic:BAAANQADCggIFAAAAA==.',
Ta='Taliss:BAAANQAECgUICgAAAA==.Tankmedaddy:BAAANQAECgcICwAAAA==.Tappuccino:BAAANQADCgYICgAAAA==.Taras:BAABNQAECoEfAAMQAAkJbiNLHADtAgAQAAgJfSJLHADtAgARAAYJnBqDBgDNAQAAAA==.Taraxist:BAAANQAECgUICQAAAA==.Tautology:BAAANQAECgUIBgAAAA==.Tazajin:BAAANQADCgYIBgAAAA==.',
Tc='Tchala:BAAANQAECgYIDQAAAA==.Tchaumb:BAAANQADCgEIAQAAAA==.',
Te='Teacup:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Teks:BAAANQAECgUICQAAAA==.Telian:BAAANQADCgUIBQAAAA==.Teth:BAAANQADCggIGwAAAA==.Tevildo:BAAANQABCgIIAgAAAA==.',
Th='Thaine:BAAANQAECgcIEgAAAA==.Theoalthor:BAAANQADCgYIEAAAAA==.Theundeadone:BAABNQAECoEZAAIHAAkJNRlBCwDKAgAHAAkJNRlBCwDKAgAAAA==.Thndrwzrd:BAAANQADCgcIEwAAAA==.Thorphan:BAAANQAECgcIEAAAAA==.',
Ti='Ticho:BAAANQAECgIIAgAAAA==.',
To='Torez:BAAANQADCgUIBwABNQAECgcIEgABAAAAAA==.Torodisilis:BAAANQADCgUIBQABNQAECgYIDQABAAAAAA==.',
Tr='Treygec:BAAANQADCgUIBgAAAA==.Tribolonotus:BAAANQADCgUIDgAAAA==.Trilleong:BAAANQADCgIIAgAAAA==.Trina:BAAANQADCggICAAAAA==.Trisilla:BAAANQADCggICAABNQAECggIFwASAK8JAA==.Troubleshot:BAAANQADCgYIBgAAAA==.Trujal:BAAANQAECgUICgAAAA==.',
Tu='Turdmonk:BAAANQAECgUIDwAAAA==.',
Ty='Tylandon:BAAANQABCgQICAAAAA==.Tyndal:BAAANQADCgMIBAAAAA==.Typhon:BAAANQAECgUICgAAAA==.',
Un='Unclebób:BAAANQADCgYIDAABNQAECgQIBQABAAAAAA==.',
Va='Vaeshta:BAAANQAECgQIBQAAAA==.Vaku:BAAANQADCgYIBgAAAA==.Valhallarama:BAAANQAECggIEQAAAA==.Valika:BAAANQABCgYIBgAAAA==.Vampy:BAAANQADCggIDwAAAA==.Vannida:BAAANQADCgIIAgAAAA==.',
Ve='Vengencedawg:BAAANQAECgUICgAAAA==.Vexxya:BAAANQADCgQIAwAAAA==.',
Vl='Vladus:BAAANQAECgUICQAAAA==.',
Vo='Voodoo:BAAANQADCgQIBwAAAA==.',
Vy='Vyllian:BAAANQAECgUIBwAAAA==.',
Wa='Wangwang:BAAANQADCgUIDwAAAA==.Wardrag:BAAANQABCgQIBAAAAA==.Wareshesh:BAAANQADCgUIBQAAAA==.Warlakaflaka:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Wh='Whale:BAAANQAECgUICQAAAA==.',
Wi='Windfury:BAAANQAECgYICwAAAA==.Windfuryous:BAAANQADCgUICQAAAA==.Winston:BAAANQADCgcIDgAAAA==.',
Wo='Wolfsbane:BAAANQADCgYIBgAAAA==.Wonpiece:BAAANQADCgQIBgABNQAECgkJGAAIACQTAA==.',
Wy='Wylestrean:BAAANQAECgUICQAAAA==.',
Xa='Xanokz:BAAANQADCgEIAQABNQAECgUICgABAAAAAA==.Xarytha:BAAANQABCgMIAwABNQAECgUIBgABAAAAAA==.',
Xi='Xiaomao:BAEANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Ye='Yeinn:BAAANQAECgUIEwAAAA==.',
Za='Zandalarthas:BAAANQAECgIIAwAAAA==.',
Zc='Zcredo:BAAANQAECgYIDQAAAA==.',
Ze='Zel:BAAANQADCgcIGAAAAA==.Zentradei:BAAANQADCgQIBAAAAA==.Zephariel:BAAANQADCgQIBwAAAA==.Zerus:BAAANQABCgMIBAAAAA==.',
Zi='Zieganfuss:BAAANQAECgUIBgAAAA==.',
Zo='Zoho:BAABNQAECoEXAAISAAgJrwndDACHAQASAAgJrwndDACHAQAAAA==.',
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
