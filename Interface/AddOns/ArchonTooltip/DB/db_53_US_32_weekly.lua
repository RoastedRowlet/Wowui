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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Retribution','Druid-Balance','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Warrior-Arms','Warrior-Fury',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=53,date='2026-09-08',data={Ae='Aeris:BAAANQAECgEIAQAAAA==.Aethwyn:BAAANQADCggIEgAAAA==.',
Ah='Ahnkala:BAAANQADCgQICgAAAA==.',
Ai='Aigirlfriend:BAAANQAECgUICQAAAA==.',
Al='Allupcreepy:BAAANQAECgEIAQAAAA==.',
Am='Amalyndi:BAAANQADCgcIDQAAAA==.Ambewlance:BAAANQADCggIFQAAAA==.',
An='Andaconda:BAAANQADCgcIBwAAAA==.Annimosity:BAAANQADCgIIAgAAAA==.Ansem:BAAANQADCggIDwAAAA==.Anúbis:BAAANQADCgQICAAAAA==.',
Ap='Apawllo:BAAANQAECgEIAQAAAA==.Apep:BAAANQADCgYIEQAAAA==.Apostle:BAAANQAECgEIAQAAAA==.',
Ar='Aramìs:BAAANQADCgIIAgAAAA==.Arcaya:BAAANQADCgYIBgAAAA==.Ariaka:BAAANQADCgEIAQAAAA==.Arleen:BAAANQADCggIDwAAAA==.Arlida:BAAANQAECgMIBAAAAA==.Artemys:BAAANQAECgQIBAAAAA==.Aryto:BAAANQADCgUIBQAAAA==.',
As='Asketill:BAAANQADCgYIDwAAAA==.Asmodee:BAAANQAECgEIAQAAAA==.',
Au='Aure:BAAANQADCgYIDAAAAA==.',
Az='Azkadellia:BAAANQABCgQICAAAAA==.',
Ba='Bainne:BAAANQADCgMIAwAAAA==.Baitken:BAAANQADCgYIEAABNQAECgEIAQABAAAAAA==.Barktea:BAAANQAECgEIAQAAAA==.Batharel:BAAANQADCgYIEQAAAA==.Battcantdps:BAAANQADCgYIBgAAAA==.Battleground:BAAANQADCgMIAwAAAA==.',
Be='Bearen:BAAANQAECgQIBAAAAA==.Beertrain:BAAANQAECgQIBQAAAA==.Beesechurger:BAAANQADCggIFgAAAA==.Belladue:BAAANQADCgYIDQAAAA==.Bellezza:BAAANQAECgYICwAAAA==.',
Bh='Bhilly:BAAANQADCggIDQAAAA==.',
Bi='Bigdumbcatqt:BAAANQAECgUIBQAAAA==.Bigdumbkatqt:BAAANQAFFAIIAgAAAA==.Bignjuicy:BAAANQADCgcIBwAAAA==.Bimisi:BAAANQAECgQIBQAAAA==.',
Bl='Bloodshhot:BAAANQAECgUIDQAAAA==.Blueragebar:BAAANQAECgQIBgAAAA==.',
Bo='Bobadasmash:BAAANQAECgQIBAAAAA==.Bobitt:BAAANQADCggIEwAAAA==.Boddyknocker:BAAANQAECgEIAQAAAA==.Boombox:BAAANQADCgYIBgAAAA==.Boonerichard:BAAANQADCgYIEAAAAA==.',
Br='Braina:BAAANQAECgEIAQAAAA==.Branwin:BAAANQADCgIIAwAAAA==.Braver:BAABNQAECoEYAAMCAAkJORySCADiAgACAAkJORySCADiAgADAAEJuAupkwA/AAAAAA==.Braverwar:BAAANQAECgIIAwABNQAECgkJGAACADkcAA==.Brayedine:BAAANQADCgcIEAAAAA==.Break:BAABNQAECoEaAAIEAAkJUyY3AQDdAwAEAAkJUyY3AQDdAwABNQAECgkJGgAEAFMmAA==.Bromungandr:BAAANQADCgYIBgAAAA==.',
By='Bynnyy:BAAANQAECgIIAgAAAA==.',
['Bù']='Bùbbles:BAAANQADCgQIBAAAAA==.',
Ca='Cadelsaya:BAAANQAECgYICwAAAA==.Camandah:BAAANQADCggIDAAAAA==.Cammandzar:BAAANQADCgQIBAABNQADCggIDAABAAAAAA==.Candy:BAAANQABCgQIAgAAAA==.Canman:BAAANQADCgYIDAAAAA==.Carlo:BAAANQAECgEIAQAAAA==.Carryout:BAAANQADCggIEAAAAA==.Cassei:BAAANQADCgYIEQAAAA==.Castertroy:BAAANQAECgMIAwAAAA==.',
Ce='Celenia:BAAANQADCgYIEQAAAA==.',
Ch='Chee:BAAANQADCgYIBgAAAA==.Cheetopaly:BAAANQAECgEIAQAAAA==.Chìgusa:BAAANQAECgQIBQAAAA==.',
Ci='Circa:BAAANQADCgEIAQAAAA==.',
Cl='Cleaveradius:BAAANQADCggICAABNQAECgYIDAABAAAAAA==.Clumonk:BAAANQADCggIFgAAAA==.',
Co='Convoke:BAAANQADCggIEAABNQAECgEIAQABAAAAAA==.Coosar:BAAANQAECgMIAwAAAA==.Coosedaplug:BAAANQADCgQIBAABNQAECgYIBwABAAAAAA==.Cooseyloosey:BAAANQAECgUIBgABNQAECgYIBwABAAAAAA==.Coosinator:BAAANQAECgYIBwAAAA==.Cooterray:BAAANQAECgEIAQAAAA==.Corellon:BAAANQAECgEIAQAAAA==.Corinth:BAAANQAECgQIBQAAAA==.',
Cr='Cratoz:BAAANQAECgQIBAAAAA==.Croswind:BAAANQAECgYICQAAAA==.',
Cy='Cyndrine:BAAANQAECgYIDQAAAA==.Cyrani:BAAANQAECgYICwAAAA==.',
Da='Dadipps:BAAANQAECgUIBgAAAA==.Daggumit:BAAANQADCgYICwAAAA==.Dagnei:BAAANQADCgQIBgAAAA==.Daltina:BAAANQAECgEIAQAAAA==.Dannyboone:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Dareael:BAAANQAECgIIAgAAAA==.Daurgoth:BAAANQAECgMIAwAAAA==.',
De='Deadbydrand:BAAANQAECgMIAwAAAA==.Deathndspark:BAAANQAECgMIBQAAAA==.Deathpuma:BAAANQAECgcICQAAAA==.Deathrowe:BAAANQAECgIIAgAAAA==.Dednevoker:BAAANQAECgEIAQAAAA==.Deelyte:BAAANQADCgYIEQAAAA==.Demítrá:BAAANQADCgIIAgABNQAECgUICgABAAAAAA==.Denouncer:BAAANQADCgMIBAABNQAECgYIDAABAAAAAA==.Derca:BAAANQADCgcIEAAAAA==.Dethork:BAAANQADCgQIBQAAAA==.',
Di='Dieds:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Dienne:BAEANQAECgEIAQAAAA==.Dietunicorn:BAAANQADCggIEwAAAA==.Dinarra:BAAANQADCgQIBAAAAA==.Disahzter:BAAANQAECgMIAwAAAA==.',
Do='Docdrood:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Docmonk:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Docpriest:BAAANQAECgQIBAAAAA==.Donlazul:BAAANQADCgQIBAAAAA==.',
Dr='Draconoth:BAAANQAECgEIAQAAAA==.',
Du='Dunstird:BAAANQADCgIIAgABNQAECgUIBgABAAAAAA==.',
Dy='Dyami:BAAANQAECgEIAQAAAA==.',
['Dè']='Dèadèyè:BAAANQADCgYIBgAAAA==.',
Ea='Eatmorechkn:BAAANQAECgQIBQAAAA==.',
Ee='Eellonwy:BAAANQADCgQIBgAAAA==.Eemerald:BAAANQADCgYIEQAAAA==.',
Eg='Egna:BAAANQAECgEIAQAAAA==.',
El='Eldiablo:BAAANQAECgUICQAAAA==.Elizaa:BAAANQAECgMIBAAAAA==.',
Ev='Evilclared:BAAANQADCgMIAwABNQAFFAEIAQABAAAAAA==.Evildean:BAAANQADCgYICgAAAA==.',
Fa='Fanya:BAAANQADCgYIBgABNQAECgUIDgABAAAAAA==.Fathernatur:BAAANQADCgIIAwAAAA==.',
Fe='Fenrigaar:BAAANQAECgcICwAAAA==.',
Ff='Ffsa:BAAANQAECgUICwAAAA==.',
Fi='Fillin:BAAANQADCgUICwAAAA==.Filô:BAAANQAECggIDwAAAA==.',
Fl='Flame:BAAANQADCgEIAQAAAA==.',
Fo='Foxyladie:BAAANQADCgUIBwAAAA==.',
Fr='Frasti:BAAANQADCgYICgAAAA==.Frodes:BAAANQABCgYIBwAAAA==.Frostmage:BAAANQAECgUICQAAAA==.',
Fu='Fuegoblazeit:BAAANQABCgIIAgAAAA==.Furbucket:BAAANQAECgEIAgAAAA==.Futonhunts:BAAANQAECgYICwAAAA==.',
Fy='Fylerw:BAAANQAECgEIAgAAAA==.',
Ga='Gailyn:BAAANQADCgYIBgAAAA==.',
Gh='Ghostrideher:BAAANQAECgEIAQAAAA==.',
Gi='Gigadad:BAAANQAECgcIDgAAAA==.',
Go='Gornthemonki:BAAANQADCgcICgAAAA==.Goyahokasinj:BAAANQADCgQIBAAAAA==.',
Gr='Griannee:BAAANQAECgQIBgAAAA==.Grislix:BAAANQAECgMIAwAAAA==.Grismistea:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Gryffin:BAAANQAECgMIBAAAAA==.',
Gu='Guidance:BAAANQADCgcIBwAAAA==.Gummies:BAAANQABCgYIDgAAAA==.',
['Gâ']='Gânk:BAAANQAECgQIBQAAAA==.',
Ha='Hanrekt:BAAANQADCggICQAAAA==.Happiness:BAAANQADCgcIDAABNQAECgYICgABAAAAAA==.',
He='Heavychevy:BAAANQAECgIIAgAAAA==.Heriel:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.Hexquisite:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Hi='Hildoehealz:BAAANQADCgQICgAAAA==.',
Hu='Humphrees:BAAANQAECgUICQAAAA==.',
Hy='Hydrospin:BAAANQADCgQIBAAAAA==.Hypocrisy:BAAANQADCgIIBAAAAA==.',
['Hà']='Hàtos:BAAANQAECgYIBAAAAA==.',
Id='Idot:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Il='Illidave:BAAANQADCgYIBwABNQAECgIIAgABAAAAAA==.',
In='Inebriatas:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Invissibill:BAAANQAECgEIAQAAAA==.',
Is='Ishaa:BAAANQAECgEIAQAAAA==.',
Iv='Ivanä:BAAANQAECgEIAQAAAA==.',
Iz='Izax:BAAANQAECgIIAwAAAA==.',
Ja='Jaddzia:BAAANQABCgQIBAAAAA==.Jadestone:BAAANQADCgYIDAAAAA==.',
Ju='Junglefu:BAAANQADCgIIAgAAAA==.Jupitus:BAAANQADCggIFQAAAA==.Justin:BAAANQAECgQIBAAAAA==.',
['Jû']='Jûstin:BAAANQADCgYIEgABNQAECggIFwAFABEdAA==.',
Ka='Karma:BAAANQADCggIDgAAAA==.Katalania:BAAANQADCggIDgAAAA==.',
Ke='Keeshama:BAAANQADCgIIAgAAAA==.Keiwhenua:BAAANQAECgIIAgAAAA==.Kelinn:BAAANQADCgUIBQAAAA==.Kenthel:BAAANQAECgcICwAAAA==.Kezt:BAAANQADCgUIBQAAAA==.',
Ki='Kiplander:BAAANQAECgQICwAAAA==.Kitheryn:BAAANQAECgEIAQAAAA==.',
Kl='Klitt:BAAANQADCggIFAAAAA==.',
Ko='Komosky:BAABNQAECoEWAAIGAAkJhQ2HDQAJAgAGAAkJhQ2HDQAJAgAAAA==.Korry:BAAANQADCgYIBgAAAA==.Kortanis:BAAANQAECgEIAQAAAA==.',
Kr='Krakìn:BAAANQADCgYIDAAAAA==.',
Ku='Kushage:BAAANQAECgMIBAAAAA==.',
La='Laerik:BAAANQABCgEIAQAAAA==.Landissa:BAAANQAECgMIBAAAAA==.Larcenciel:BAAANQAECgIIBAAAAA==.Larryholmes:BAAANQABCgQIBAABNQADCggICAABAAAAAA==.',
Le='Letmehelpyou:BAAANQAECgYIDAAAAA==.',
Li='Licky:BAAANQAECgQIBAAAAA==.Lihan:BAAANQAECgEIAQAAAA==.Lilieth:BAAANQADCggICgAAAA==.Lily:BAAANQAECgQIBQAAAA==.Lively:BAAANQADCgcIEAAAAA==.',
Lo='Lockedtoit:BAAANQADCgYIDAAAAA==.Loverocket:BAAANQAECgQIBAAAAA==.',
Lu='Lunastorm:BAAANQABCgQIAwAAAA==.',
Ly='Lyshia:BAAANQAECgYICwAAAA==.',
['Lí']='Líghthand:BAAANQAECgQIBQAAAA==.',
['Lý']='Lýght:BAAANQADCgcIBwAAAA==.',
Ma='Magedown:BAAANQAECgQIBAAAAA==.Magician:BAAANQADCggICAAAAA==.Manpumper:BAAANQADCggIDAAAAA==.Margor:BAAANQADCgYIEQAAAA==.Mattdemon:BAAANQAECgYICwAAAA==.',
Me='Meliany:BAAANQADCggIEgAAAA==.Meliorate:BAAANQAECgYIDgAAAA==.Meowch:BAAANQAECgQIBQAAAA==.',
Mi='Mikachu:BAAANQAECggIEQABNQAFFAIIAgABAAAAAA==.Miksi:BAAANQADCgYICQABNQADCgYIDAABAAAAAA==.Miradele:BAAANQAECgEIAQAAAA==.Miraxx:BAAANQADCgYIDAAAAA==.Misscleö:BAAANQAECgIIAwAAAA==.Miyoshi:BAAANQAECgQIBQAAAA==.',
Mo='Moosakka:BAAANQAECgQIBwAAAA==.Moosesiah:BAAANQABCgYICAABNQAECgEIAgABAAAAAA==.Moovinthru:BAAANQADCgQICAAAAA==.Moraxes:BAAANQAECgEIAQAAAA==.Mordenkainen:BAAANQADCggIDwAAAA==.Morphidmage:BAAANQADCgUIBQAAAA==.Motoko:BAAANQADCgYIBwAAAA==.',
Mu='Muaadib:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.',
My='Mydin:BAAANQAECgYICgAAAA==.Myssaphra:BAAANQAECgcIDQAAAA==.',
['Mì']='Mìsawa:BAAANQAECgEIAQAAAA==.',
Na='Nakai:BAAANQAECgUIBQAAAA==.Nastijiggle:BAAANQAECgMIBAAAAA==.Nazrien:BAAANQABCgUIBQAAAA==.Nazrion:BAAANQABCgEIAQAAAA==.',
Nc='Nc:BAAANQAECgMIBAAAAA==.',
Ne='Nexxa:BAAANQAECgIIAgAAAA==.',
Ni='Nightshadow:BAAANQADCgQIBAAAAA==.Niqkle:BAAANQAECgYICwAAAA==.Nitetbane:BAAANQAECgIIBwAAAA==.',
No='Nohurtscooby:BAAANQADCgUICwAAAA==.Notadh:BAAANQADCgQIBAAAAA==.',
Ns='Nstagatr:BAAANQAECgIIAgAAAA==.',
Ny='Nyxi:BAAANQABCgQIBAAAAA==.',
Ol='Olari:BAAANQABCgIIAgAAAA==.Oldoriel:BAAANQABCgQIBAAAAA==.Olehanna:BAAANQAECgUIBwAAAA==.',
On='Oni:BAAANQADCgYICAAAAA==.',
Op='Opioid:BAAANQADCgcIEwAAAA==.Opsèc:BAAANQAECgMIBAAAAA==.',
Or='Orsa:BAAANQADCggICAAAAA==.',
Pe='Peachshock:BAEBNQAECoEXAAMHAAkJNCXaAAC+AwAHAAkJNCXaAAC+AwAIAAMJWiEmSAArAQAAAA==.Perfectlock:BAAANQAECgEIAQAAAA==.',
Pi='Pigog:BAAANQADCggIFAAAAA==.',
Po='Pordgio:BAAANQADCggIEwAAAA==.Pozzi:BAAANQAECgUIBQAAAA==.',
Pr='Praypal:BAAANQADCgEIAQAAAA==.',
Ps='Psuedolus:BAAANQAECgEIAQAAAA==.Psålm:BAAANQAECgQIBAAAAA==.',
Pu='Pulshadow:BAAANQAECggIEgAAAA==.Pumah:BAAANQADCgYIDAAAAA==.',
Ra='Raamen:BAAANQADCgYIDAAAAA==.Raellia:BAAANQAECgUICQAAAA==.Raimmey:BAAANQADCgIIBAAAAA==.Rajia:BAAANQADCgcIEwABNQAECgEIAQABAAAAAA==.Ralune:BAAANQAECgEIAQAAAA==.Ranes:BAAANQAECgUICQAAAA==.',
Re='Redback:BAAANQABCgEIAQAAAA==.Redxelementz:BAAANQAECgYIDAAAAA==.Redxpastakan:BAAANQADCgUIBQABNQAECgYIDAABAAAAAA==.Renasen:BAAANQAECgIIAgAAAA==.Reno:BAAANQAECgIIAgAAAA==.Resiretha:BAAANQAECgIIAgAAAA==.Revelynn:BAAANQAECgQIBwAAAA==.Rexkwondo:BAAANQAECgIIAgAAAA==.',
Ri='Rivliam:BAAANQAECgEIAQAAAA==.Rizzn:BAAANQADCgQIBAABNQAECgcICwABAAAAAA==.',
Ro='Rook:BAAANQAECgIIAgAAAA==.Rooxxy:BAAANQAECgQIBwAAAA==.Roxxyyzz:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.',
Ry='Rynoh:BAAANQADCgcIBwAAAA==.Rythrik:BAAANQAECgEIAgAAAA==.Ryujinorsted:BAAANQADCgUIBQAAAA==.',
Sa='Sainted:BAAANQAFFAEIAQAAAA==.Sanoks:BAAANQAECgQIBQAAAA==.Sanokz:BAAANQADCgYIBgAAAA==.Savira:BAAANQADCggICQAAAA==.',
Sc='Scaleorva:BAAANQAECgEIAQAAAA==.',
Se='Seraphìm:BAAANQAECgEIAQAAAA==.Seïnaru:BAAANQADCgYIDAAAAA==.',
Sh='Shadyballs:BAAANQAECgEIAQAAAA==.Shakypete:BAAANQADCggICAABNQAECgQICwABAAAAAA==.Shamysosa:BAAANQADCgYICgABNQADCgYIEQABAAAAAA==.Shiionknow:BAAANQADCgQIBAAAAA==.Shinjí:BAAANQAECgUICQABNQAECgkJGQAJAPQfAA==.Shmob:BAAANQAECgEIAQAAAA==.Shnappz:BAAANQAECgEIAQAAAA==.Shwillarou:BAAANQAECgUIBgAAAA==.Shádôws:BAAANQADCgYICwAAAA==.',
Si='Sinergee:BAAANQAECgEIAQAAAA==.Sinnj:BAAANQADCgcIDQAAAA==.',
Sk='Skinsey:BAAANQADCgYIDQAAAA==.Skinzey:BAAANQADCgUIBQAAAA==.Skinzy:BAAANQABCgYIBwAAAA==.Skycrush:BAAANQADCgUIBQAAAA==.',
Sl='Slanie:BAAANQADCggIEwAAAA==.Slingerz:BAAANQAECgYICwAAAA==.',
Sm='Smalldragon:BAAANQADCgYIBQAAAA==.Smoky:BAAANQAECgQIBgAAAA==.',
Sn='Sneakpastya:BAAANQADCgIIAgAAAA==.Sneakyg:BAAANQAECgMIAwABNQAECgQIBwABAAAAAA==.Snoochie:BAAANQAECgIIAgAAAA==.',
So='Solkar:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Sollis:BAAANQADCgYIDAAAAA==.',
Sp='Spazzchel:BAAANQADCgYIEQAAAA==.Spiritbox:BAABNQAECoEXAAIHAAkJTyRVAQCoAwAHAAkJTyRVAQCoAwABNQAECgEIAQABAAAAAA==.Sprucemoose:BAAANQADCgIIBQAAAA==.',
St='Stahlman:BAAANQAECgQICAAAAA==.Stalpho:BAAANQAECgQIBQAAAA==.Starblessed:BAAANQADCgMIBgABNQADCggIFAABAAAAAA==.Starkind:BAAANQADCggIFAAAAA==.Starliner:BAAANQAECgQIBQAAAA==.Stasis:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.Strahd:BAAANQADCgMIBQAAAA==.Styrke:BAAANQADCgYIBgAAAA==.',
Su='Subza:BAAANQAECgYICwAAAA==.',
Sw='Swagtistic:BAAANQADCggIFAAAAA==.',
Ta='Taliss:BAAANQAECgQIBQAAAA==.Tankmedaddy:BAAANQAECgMIBAAAAA==.Tappuccino:BAAANQADCgYICgAAAA==.Taras:BAABNQAECoEaAAMKAAkJcCLSEAAFAwAKAAgJjiHSEAAFAwALAAYJXBpBBADdAQAAAA==.Taraxist:BAAANQAECgMIBAAAAA==.Tautology:BAAANQAECgQIBQAAAA==.Tazajin:BAAANQADCgYIBgAAAA==.',
Tc='Tchala:BAAANQAECgQIBwAAAA==.Tchallah:BAAANQADCggICQAAAA==.Tchaumb:BAAANQADCgEIAQAAAA==.',
Te='Teacup:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Teks:BAAANQAECgMIBAAAAA==.Telian:BAAANQADCgUIBQAAAA==.Teth:BAAANQADCggIFAAAAA==.Tevildo:BAAANQABCgIIAgAAAA==.',
Th='Thaine:BAAANQAECgYICwAAAA==.Theoalthor:BAAANQADCgYICgAAAA==.Theundeadone:BAAANQAECgUIDgAAAA==.Thndrwzrd:BAAANQADCgYIDAAAAA==.Thorphan:BAAANQAECgYICgAAAA==.',
Ti='Ticho:BAAANQADCggIFQAAAA==.',
To='Torez:BAAANQADCgUIBwABNQAECgYICwABAAAAAA==.',
Tr='Treygec:BAAANQADCgUIBgAAAA==.Tribolonotus:BAAANQADCgQICQAAAA==.Trilleong:BAAANQADCgIIAgAAAA==.Trisilla:BAAANQADCggICAABNQAECgYIDQABAAAAAA==.Troubleshot:BAAANQADCgYIBgAAAA==.Trujal:BAAANQAECgQIBQAAAA==.',
Tu='Turdmonk:BAAANQAECgQIBQAAAA==.',
Ty='Tylandon:BAAANQABCgQIBgAAAA==.Tyndal:BAAANQADCgMIAwAAAA==.Typhon:BAAANQAECgQIBQAAAA==.',
Un='Unclebób:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.',
Va='Vaeshta:BAAANQAECgEIAQAAAA==.Vaku:BAAANQADCgYIBgAAAA==.Valhallarama:BAAANQAECgcICQAAAA==.Valika:BAAANQABCgYIBgAAAA==.Vampy:BAAANQADCggIDwAAAA==.',
Ve='Vengencedawg:BAAANQAECgQIBQAAAA==.Vexxya:BAAANQADCgQIAwAAAA==.',
Vl='Vladus:BAAANQAECgQIBAAAAA==.',
Vo='Voodoo:BAAANQADCgQIBwAAAA==.',
Vy='Vyllian:BAAANQAECgIIAgAAAA==.',
Wa='Wangwang:BAAANQADCgQICgAAAA==.Wardrag:BAAANQABCgQIBAAAAA==.Wareshesh:BAAANQADCgUIBQAAAA==.Warlakaflaka:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Wh='Whale:BAAANQAECgQIBAAAAA==.',
Wi='Windfury:BAAANQAECgUIBwAAAA==.Windfuryous:BAAANQADCgUICQAAAA==.Winston:BAAANQADCgcICwAAAA==.',
Wo='Wolfsbane:BAAANQADCgYIBgAAAA==.Wonpiece:BAAANQADCgQIBgABNQAECgYIDgABAAAAAA==.',
Wy='Wylestrean:BAAANQAECgMIBAAAAA==.',
Xa='Xanokz:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Xarytha:BAAANQABCgMIAwABNQAECgQIBQABAAAAAA==.',
Xi='Xiaomao:BAEANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Ye='Yeinn:BAAANQAECgUIDAAAAA==.',
Za='Zandalarthas:BAAANQAECgEIAQAAAA==.',
Zc='Zcredo:BAAANQAECgYIBgAAAA==.',
Ze='Zel:BAAANQADCgYIEQAAAA==.Zentradei:BAAANQADCgQIBAAAAA==.Zephariel:BAAANQADCgQIBAAAAA==.Zerus:BAAANQABCgMIAwAAAA==.',
Zi='Zieganfuss:BAAANQAECgQIBQAAAA==.',
Zo='Zoho:BAAANQAECgYIDQAAAA==.',
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
