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

local lookup = {'Druid-Balance','DemonHunter-Devourer','Unknown-Unknown','Druid-Restoration','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Druid-Guardian','Paladin-Holy','DemonHunter-Havoc','Shaman-Restoration','DemonHunter-Vengeance','Shaman-Elemental','Warlock-Destruction','Warrior-Arms','Priest-Shadow','Hunter-Survival','Mage-Arcane','Rogue-Assassination','Warlock-Demonology','Warlock-Affliction','Monk-Windwalker','DeathKnight-Unholy','Warrior-Protection','Warrior-Fury','Rogue-Outlaw','Shaman-Enhancement','Monk-Brewmaster',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Absorbency:BAAANQAECgYIBgABNQAECgkJHQABAEATAA==.',
Ae='Aeris:BAAANQAECgQIBQAAAA==.Aethwyn:BAAANQAECgUJBQAAAA==.',
Ag='Agandaur:BAAANQADCgQIBAAAAA==.',
Ah='Ahnkala:BAAANQADCgcIFgAAAA==.',
Ai='Aigirlfriend:BAABNQAECoEXAAICAAcK+wiqKwCJAQACAAcK+wiqKwCJAQAAAA==.',
Al='Allupcreepy:BAAANQAECgQJBwAAAA==.',
Am='Amalyndi:BAAANQAECgMJAwAAAA==.Ambewlance:BAAANQAECgQIBwAAAA==.Amethystra:BAAANQADCggICAAAAA==.Amlu:BAAANQAECgEIAQABNQAECgcJEwADAAAAAA==.',
An='Andaconda:BAAANQAECgQIBQAAAA==.Annimosity:BAAANQADCgYIDQAAAA==.Ansem:BAAANQAECgEJAQAAAA==.Anúbis:BAAANQADCgUIDQAAAA==.',
Ap='Apawllo:BAAANQAECgEJAQAAAA==.Apep:BAAANQADCggIIAAAAA==.Apostle:BAAANQAFFAQIBAAAAA==.',
Ar='Aramìs:BAAANQADCgcICQAAAA==.Arcaya:BAAANQADCgYJEwAAAA==.Ariaka:BAAANQADCgEIAQAAAA==.Arleen:BAAANQAECgQJBQAAAA==.Arlida:BAAANQAECgYJDwAAAA==.Artemys:BAAANQAECgYJDgAAAA==.Aryto:BAAANQADCgUIBQAAAA==.',
As='Asketill:BAAANQADCgYIDwAAAA==.Asmodee:BAAANQAECgUJCAAAAA==.',
Au='Aure:BAAANQADCgYIDAAAAA==.Auren:BAAANQADCgIIAgAAAA==.',
Az='Azkadellia:BAAANQABCgQJCAAAAA==.Azonya:BAAANQABCgQIBAAAAA==.',
Ba='Baaloo:BAAANQABCgQIBAABNQADCgcJGQADAAAAAA==.Bainne:BAAANQADCgUJCAAAAA==.Baitken:BAAANQAECgMIAwABNQAECgQJBwADAAAAAA==.Barktea:BAAANQAECgMJBAAAAA==.Batharel:BAAANQAECgMIAwAAAA==.Battcantdps:BAAANQADCgcJDgAAAA==.Battleground:BAAANQADCgMIAwAAAA==.',
Be='Bearen:BAAANQAECgYJDgAAAA==.Beertrain:BAAANQAECgYIEAAAAA==.Beesechurger:BAAANQAECgMIAwAAAA==.Belladue:BAAANQADCgYJFgAAAA==.Bellezza:BAABNQAECoEcAAIEAAgK6BGQFwD5AQAEAAgK6BGQFwD5AQAAAA==.',
Bh='Bhikku:BAAANQAECgQICAABNQAECgcJEwADAAAAAA==.Bhilly:BAAANQADCggJFgAAAA==.',
Bi='Bigdumbcatqt:BAAANQAFFAEIAQAAAA==.Bigdumbkatqt:BAABNQAFFIENAAIFAAUKzBojBQCYAQAFAAUKzBojBQCYAQAAAA==.Bignjuicy:BAAANQAECgYICgAAAA==.Bimisi:BAAANQAECgYIEAAAAA==.',
Bl='Blades:BAAANQADCgMIBgAAAA==.Bloodshhot:BAABNQAECoEdAAIGAAcKuRKhTwADAgAGAAcKuRKhTwADAgAAAA==.Blueragebar:BAAANQAECgUJCwAAAA==.',
Bo='Bobadasmash:BAAANQAECgcIEQAAAA==.Bobitt:BAAANQAECgEJAQAAAA==.Boddyknocker:BAAANQAECgEIAQAAAA==.Boombox:BAAANQADCgYIBgAAAA==.Boonerichard:BAAANQADCgcIHgAAAA==.Bouchewager:BAAANQADCgYIBgAAAA==.',
Br='Braina:BAAANQAECgQIBgAAAA==.Branwin:BAAANQADCgUJCgAAAA==.Braver:BAACNQAFFIEIAAIHAAUKBw39BgBjAQAHAAUKBw39BgBjAQA1AAQKgSQAAwcACQovHjsNANICAAcACQovHjsNANICAAYAAQq4C6PyADwAAAAA.Braverwar:BAAANQAECgIIAwABNQAFFAUICAAHAAcNAA==.Brayedine:BAAANQADCgcIFwAAAA==.Break:BAACNQAFFIEMAAIIAAYKXiJ/AABzAgAIAAYKXiJ/AABzAgA1AAQKgSAAAggACQpmJiAFALoDAAgACQpmJiAFALoDAAE1AAUUBgoMAAgAXiIA.Bromungandr:BAAANQADCgYIDAAAAA==.',
Bu='Buligerent:BAAANQADCggJEAABNQAECgcJFwAJAO4VAA==.',
By='Bynnyy:BAAANQAECgIIAgAAAA==.',
['Bù']='Bùbbles:BAAANQAECgIJAQAAAA==.',
Ca='Cadelsaya:BAABNQAECoEcAAIKAAgKEA0PRgDbAQAKAAgKEA0PRgDbAQAAAA==.Camandah:BAAANQAECgUICgABNQADCgMIBAADAAAAAA==.Cammandzar:BAAANQAECgIIAgABNQADCgMIBAADAAAAAA==.Candy:BAAANQABCgQIAgAAAA==.Canman:BAAANQADCgcJGQAAAA==.Carlo:BAAANQAECgEIAwAAAA==.Carryout:BAAANQAECggICwAAAA==.Cassei:BAAANQAECgMIAwAAAA==.Castertroy:BAAANQAECgUICAAAAA==.',
Ce='Celenia:BAAANQADCggIIAAAAA==.',
Ch='Chalcey:BAAANQADCgIIAgAAAA==.Charmless:BAAANQADCgUIBQABNQAECggJHAALACsUAA==.Chee:BAAANQADCggJFgAAAA==.Cheetopaly:BAAANQAECgUJCQAAAA==.Chuga:BAAANQADCggICgABNQAECgcIEgADAAAAAA==.Chìgusa:BAAANQAECgYJEAAAAA==.',
Ci='Circa:BAAANQADCgEIAQAAAA==.',
Cl='Clarimonde:BAAANQADCgEIAQAAAA==.Cleaveradius:BAAANQADCggJCAABNQAECggJFwAMAHIdAA==.Clumonk:BAAANQAECgUJCgAAAA==.',
Co='Convoke:BAAANQADCggIEAABNQAFFAQIBAADAAAAAA==.Coosar:BAAANQAECgMJAwAAAA==.Coosedaplug:BAAANQADCgQIBAABNQAECgcIEgADAAAAAA==.Cooseyloosey:BAAANQAECgcIEgAAAA==.Coosinator:BAAANQAECgYJCwABNQAECgcIEgADAAAAAA==.Cooterray:BAAANQAECgUJBwAAAA==.Corellon:BAAANQAECgQJBQAAAA==.Corinth:BAAANQAECgYJEAAAAA==.',
Cr='Cratoz:BAAANQAECgcIEAAAAA==.Croswind:BAABNQAECoEZAAIGAAgKoBB8QgAuAgAGAAgKoBB8QgAuAgAAAA==.',
Cy='Cyndrine:BAABNQAECoEfAAINAAkK4CRwAADHAwANAAkK4CRwAADHAwAAAA==.Cyrani:BAABNQAECoEcAAMOAAgK/CPODQBJAwAOAAgK/CPODQBJAwAMAAYKrCTJIgCDAgAAAA==.',
Da='Dadipps:BAAANQAECgcJEwAAAA==.Daggumit:BAAANQADCgYIEQAAAA==.Dagnei:BAAANQADCgcIEgAAAA==.Daltina:BAAANQAECgUICAAAAA==.Damage:BAAANQAECggIAgAAAA==.Dannyboone:BAAANQADCggICAABNQAECgcJEAADAAAAAA==.Dareael:BAAANQAECgUJCwAAAA==.Daurgoth:BAAANQAECgYJDgAAAA==.Dazoner:BAAANQADCgcIBwAAAA==.',
De='Deadbydrand:BAAANQAECgYJCQAAAA==.Deathndspark:BAAANQAECgYJEAAAAA==.Deathpuma:BAABNQAECoEZAAIFAAkKmht0EwDHAgAFAAkKmht0EwDHAgAAAA==.Deathrowe:BAAANQAECgUJDAAAAA==.Dednevoker:BAAANQAECgEIAQABNQAECgYIDAADAAAAAA==.Deelyte:BAAANQADCggIIAAAAA==.Demonvann:BAAANQADCggICAAAAA==.Demítrá:BAAANQADCgIIAgABNQAECggIGwAMAFAVAA==.Denouncer:BAAANQAECgQIBAABNQAECggJFwAMAHIdAA==.Derca:BAAANQAECgQJBQAAAA==.Dethork:BAAANQADCgcIDAAAAA==.',
Di='Dieds:BAAANQADCgYIBgABNQAECgYIDAADAAAAAA==.Dienne:BAEANQAECgEIAQAAAA==.Dietunicorn:BAAANQADCggIGwAAAA==.Dinarra:BAAANQADCgQIBAAAAA==.Disahzter:BAAANQAECgUJDAAAAA==.',
Do='Docdrood:BAAANQADCgcIBwABNQAECgYJDgADAAAAAA==.Docmonk:BAAANQAECgEIAQABNQAECgYJDgADAAAAAA==.Docpriest:BAAANQAECgYJDgAAAA==.Donlazul:BAAANQADCgQJBAAAAA==.Dotlotto:BAAANQAECgEJAgAAAA==.',
Dr='Draconoth:BAAANQAECgQJBQAAAA==.Dragfin:BAAANQADCgUICgAAAA==.Dragonir:BAAANQAECgUJBwABNQAECgcJEwADAAAAAA==.',
Du='Dunstird:BAAANQADCgQIBAABNQAFFAEIAQADAAAAAA==.',
Dy='Dyami:BAAANQAECgUJBwAAAA==.',
['Dè']='Dèadèyè:BAAANQADCggJDgAAAA==.',
Ea='Eatmorechkn:BAAANQAECgYIEAAAAA==.',
Ee='Eellonwy:BAAANQADCgcIEgAAAA==.Eemerald:BAAANQADCggIIAAAAA==.',
Eg='Egna:BAAANQAECgUIBgAAAA==.',
El='Electricblu:BAAANQAECgMJBAAAAA==.Elizaa:BAAANQAECgYJDwAAAA==.',
Em='Emmadar:BAAANQADCggJDgABNQAECgcJFwAPALUOAA==.',
Eu='Euripidus:BAAANQADCgEIAQAAAA==.',
Ev='Evilclared:BAAANQADCgUICgABNQAECggJHAAQAPAkAA==.Evildean:BAAANQADCgYICgAAAA==.',
Ex='Execute:BAAANQADCgUICQAAAA==.',
Fa='Fanya:BAAANQADCgYIBgABNQAECgkJHQARALAaAA==.Fathernatur:BAAANQADCgYICQAAAA==.',
Fe='Fenrigaar:BAABNQAECoEcAAIBAAkK4BiRFwC+AgABAAkK4BiRFwC+AgAAAA==.',
Ff='Ffsa:BAABNQAECoEaAAQGAAkKOxtOFwDvAgAGAAkKOxtOFwDvAgAHAAQKRQYQPgC8AAASAAEKahW6DABEAAAAAA==.',
Fi='Fillin:BAAANQADCgcJFgAAAA==.Filô:BAAANQAECggJEQAAAA==.',
Fl='Flame:BAAANQADCgEIAQAAAA==.Flintmini:BAAANQADCgQJBAAAAA==.Flossylock:BAAANQAECgEJAQAAAA==.',
Fo='Foxyladie:BAAANQAECgEIAQAAAA==.',
Fr='Frasti:BAAANQADCgcJFwAAAA==.Frodes:BAAANQABCgYJBwAAAA==.Frostmage:BAABNQAECoEXAAITAAcKxxMxmQDZAQATAAcKxxMxmQDZAQAAAA==.',
Fu='Fuegoblazeit:BAAANQABCgIIAgAAAA==.Furbucket:BAAANQAECgQJCAAAAA==.Futonhunts:BAABNQAECoEcAAIGAAgKGCFyFAABAwAGAAgKGCFyFAABAwAAAA==.',
Fy='Fylerw:BAAANQAECgUICwAAAA==.',
Ga='Gailyn:BAAANQADCgYICgAAAA==.Galebb:BAAANQADCgUIBQABNQAECgIIAwADAAAAAA==.Gardros:BAAANQABCgQIBAAAAA==.',
Gh='Ghostrideher:BAAANQAECgUIBgAAAA==.',
Gi='Gigadad:BAABNQAECoEgAAIGAAkKXiV0AgDDAwAGAAkKXiV0AgDDAwAAAA==.Gigafather:BAAANQADCgQIBAAAAA==.',
Go='Gornthemonki:BAAANQADCgcICgAAAA==.Goyahokasinj:BAAANQADCgQJCwAAAA==.',
Gr='Griannee:BAAANQAECgYIEQAAAA==.Grimtoetem:BAAANQABCgYJCQAAAA==.Grislix:BAAANQAECgYJDwAAAA==.Grismistea:BAAANQAECgEIAQABNQAECgYJDwADAAAAAA==.Gryffin:BAAANQAECgYJDwAAAA==.',
Gu='Guidance:BAAANQADCgcIBwAAAA==.Gummies:BAAANQABCgYIDgAAAA==.',
['Gâ']='Gânk:BAAANQAECgUJDwAAAA==.',
Ha='Hanrekt:BAAANQAECgIJAgAAAA==.Happiness:BAAANQAECgQIBQABNQAECggIFwAGAM4eAA==.',
He='Heavensbliss:BAAANQADCggICAABNQAECgcJFwATAMcTAA==.Heavychevy:BAAANQAECggJDgAAAA==.Hellvenger:BAAANQADCgMIAwAAAA==.Heriel:BAAANQAECgUICgABNQAECgcJEwADAAAAAA==.Hexquisite:BAAANQADCgYJBQABNQAFFAQIBAADAAAAAA==.',
Hi='Hildoehealz:BAAANQAECgEJAgAAAA==.',
Ho='Holybit:BAAANQADCggIDwAAAA==.Hotsjkpurge:BAAANQADCgQIBAAAAA==.',
Hu='Humphrees:BAABNQAECoEXAAIUAAcK+w/AIgDDAQAUAAcK+w/AIgDDAQAAAA==.',
Hy='Hydrospin:BAAANQADCgQIBAAAAA==.Hypocrisy:BAAANQADCgUJCgAAAA==.',
['Hà']='Hàtos:BAAANQAECggJDwAAAA==.',
Id='Idot:BAAANQADCgUJDgABNQAECgUICgADAAAAAA==.',
Il='Illidave:BAAANQADCgYIBwABNQAECgUJBwADAAAAAA==.',
In='Inebriatas:BAAANQAECgEIAQABNQAECgQICwADAAAAAA==.Inu:BAAANQABCgIJAgAAAA==.Invissibill:BAAANQAECgUICgAAAA==.',
Is='Ishaa:BAAANQAECgcICQAAAA==.',
Iv='Ivanä:BAAANQAECgQJBQAAAA==.',
Iz='Izax:BAABNQAECoEWAAQVAAYK+guskAAWAQAVAAUKQguskAAWAQAPAAEKjw9nYAA/AAAWAAEKYwZuIwAzAAAAAA==.',
Ja='Jaddzia:BAAANQABCgQIBAAAAA==.Jadestone:BAAANQADCgYIDAAAAA==.Jarcor:BAAANQABCgQIBAAAAA==.',
Je='Jeffray:BAAANQABCgQIBAAAAA==.Jessi:BAAANQAECgUIBQAAAA==.',
Jo='Jonsneew:BAAANQADCgQIBAAAAA==.',
Ju='Judgment:BAAANQADCgMJAwAAAA==.Junglefu:BAAANQADCgIIAgAAAA==.Jupitus:BAAANQAECgUIBQAAAA==.Justin:BAAANQAECgUIBwABNQAECgYIBgADAAAAAA==.',
['Jû']='Jûstin:BAAANQAECgYIBwABNQAECgkJGgABAN0cAA==.',
Ka='Kale:BAAANQABCgIJAwAAAA==.Karma:BAAANQAECgUJCAAAAA==.Katalania:BAAANQAECgUJCAAAAA==.',
Ke='Keeshama:BAAANQADCgIIAgAAAA==.Keiwhenua:BAAANQAECgUJCwAAAA==.Kelinn:BAAANQADCggIFAAAAA==.Kelzier:BAAANQAECgQIBQABNQAECgcJEwADAAAAAA==.Kenthel:BAAANQAECgcIEwAAAA==.Kezt:BAAANQADCgUIBQABNQADCggIDwADAAAAAA==.',
Ki='Kiplander:BAABNQAECoEXAAIBAAUKUA/vTwAXAQABAAUKUA/vTwAXAQAAAA==.Kiplandr:BAAANQABCgEJAQAAAA==.Kitheryn:BAAANQAECgEIAQAAAA==.',
Kl='Klitt:BAAANQAECgEJAQAAAA==.',
Ko='Komosky:BAACNQAFFIEMAAIXAAUKlQRSBABCAQAXAAUKlQRSBABCAQA1AAQKgSMAAhcACQpqFZkRAF0CABcACQpqFZkRAF0CAAAA.Korry:BAAANQADCggIFQAAAA==.Kortanis:BAAANQAECgUJBwAAAA==.',
Kr='Krakìn:BAAANQADCgcIEwAAAA==.',
Ku='Kushage:BAAANQAECgYJDwAAAA==.',
Ky='Kyana:BAAANQADCgYJBgAAAA==.',
['Kü']='Küngfury:BAAANQADCgUIBQAAAA==.',
La='Laerik:BAAANQABCgEIAQAAAA==.Landissa:BAAANQAECgYJDQAAAA==.Larcenciel:BAAANQAECgQJCQAAAA==.Larryholmes:BAAANQABCgQIBAABNQADCggICAADAAAAAA==.',
Le='Leen:BAAANQABCgYICQAAAA==.Letmehelpyou:BAABNQAECoEXAAIMAAgKch1VHwCYAgAMAAgKch1VHwCYAgAAAA==.',
Li='Licky:BAAANQAECgYIDwAAAA==.Lihan:BAAANQAECgQJBgAAAA==.Lilieth:BAAANQADCggICgAAAA==.Lily:BAAANQAECgYJEAAAAA==.Lively:BAAANQAECgQIBwAAAA==.',
Lo='Lockedtoit:BAAANQADCgYIDAAAAA==.Loverocket:BAAANQAECgYJDwAAAA==.',
Lu='Luna:BAAANQADCgUJBQABNQAECgUIBwADAAAAAA==.Lunastorm:BAAANQADCgQJBAAAAA==.',
Ly='Lyshia:BAABNQAECoEcAAITAAgKgRvtWgB8AgATAAgKgRvtWgB8AgAAAA==.',
['Lí']='Líghthand:BAAANQAECggIDQAAAA==.',
['Lý']='Lýght:BAAANQADCgcIDQAAAA==.',
Ma='Magedown:BAAANQAECgYJDwAAAA==.Magician:BAAANQADCggICAAAAA==.Mamachula:BAAANQADCgQJBAAAAA==.Manpumper:BAAANQAECgMIAwAAAA==.Margor:BAAANQAECgMIAwABNQAECgQJBgADAAAAAA==.Mattdemon:BAABNQAECoEcAAMLAAgKKxSsHQAyAgALAAgKPROsHQAyAgACAAcKyBIoJADQAQAAAA==.',
Me='Meanzy:BAAANQADCgQIBAAAAA==.Meliany:BAAANQAECgEIAQAAAA==.Meliorate:BAABNQAECoEdAAMBAAkKQBOWJQA8AgABAAkKQBOWJQA8AgAEAAYKnQk5KAA4AQAAAA==.Meowch:BAAANQAECgYJEAAAAA==.',
Mi='Mikachu:BAAANQAFFAIIAgABNQAFFAUJCQAIAB0OAA==.Miksi:BAAANQADCgYICQABNQADCgcJGQADAAAAAA==.Miradele:BAAANQAECgQJBwAAAA==.Miraxx:BAAANQADCgcJGQAAAA==.Misscleö:BAAANQAECgYJDAAAAA==.Miyoshi:BAAANQAECgYJEAAAAA==.',
Mo='Mobius:BAAANQABCgIIAgAAAA==.Moosakka:BAAANQAECgYJEgAAAA==.Moosesiah:BAAANQABCgYJCgABNQAECgYIDQADAAAAAA==.Moovinthru:BAAANQADCgcIFAAAAA==.Moraxes:BAAANQAECgUJBgAAAA==.Mordenkainen:BAAANQAECgQJBwAAAA==.Morgax:BAAANQAECgYIBgAAAA==.Morgona:BAAANQADCgUIBQAAAA==.Morphidmage:BAAANQADCgUIBQAAAA==.Motoko:BAAANQADCgYIDAAAAA==.',
Mu='Muaadib:BAAANQAECgQJBQABNQAECggJGQAGAKAQAA==.',
My='Mydin:BAAANQAECgYJEAAAAA==.Myssaphra:BAABNQAECoEcAAMMAAkKHhaRKABhAgAMAAkKHhaRKABhAgAOAAEKRAck6gArAAAAAA==.',
['Mì']='Mìsawa:BAAANQAECgMIAwAAAA==.',
Na='Nakai:BAAANQAECgcIEAAAAA==.Nasatra:BAAANQADCgQJCAAAAA==.Nastijiggle:BAAANQAECgYIDwAAAA==.Nazrien:BAAANQABCgUJBQAAAA==.Nazrion:BAAANQABCgEIAQAAAA==.',
Nc='Nc:BAAANQAECgYJDwAAAA==.',
Ne='Nexxa:BAAANQAECgUJCwAAAA==.',
Ni='Nightshadow:BAAANQADCgQIBAAAAA==.Niqkle:BAABNQAECoEWAAMOAAgKzwa5WgCKAQAOAAgKzwa5WgCKAQAMAAYK7Q6AZABdAQAAAA==.Nitebane:BAAANQAECgQJCwAAAA==.',
No='Nohurtscooby:BAAANQADCgYIFwAAAA==.Notadh:BAAANQADCgQJCAAAAA==.Notadruid:BAAANQADCgQJBAAAAA==.Notawrlock:BAAANQAECgEJAQABNQAFFAEIAQADAAAAAA==.',
Ns='Nstagatr:BAAANQAECgUJBwAAAA==.',
Ny='Nyxandria:BAAANQABCgQIBAAAAA==.Nyxi:BAAANQABCgQIBAAAAA==.',
Oa='Oak:BAAANQAECgIJAgAAAA==.',
Ol='Olari:BAAANQABCgIIAgAAAA==.Oldoriel:BAAANQADCgYIBgAAAA==.Olehanna:BAAANQAECgYJEgAAAA==.Olestrid:BAAANQADCggJDgABNQAECgYJEgADAAAAAA==.',
On='Oni:BAAANQADCgYICAAAAA==.',
Op='Opioid:BAAANQAECgMIAwAAAA==.Opsec:BAAANQAECgIJAgABNQAECgYJDwADAAAAAA==.Opsèc:BAAANQAECgYJDwAAAA==.',
Or='Orsa:BAAANQADCggICAAAAA==.',
Pe='Peachshock:BAECNQAFFIEOAAIMAAYKlBevAQApAgAMAAYKlBevAQApAgA1AAQKgR4AAwwACQrQJfsCAKIDAAwACQrQJfsCAKIDAA4ABAroHwNmAGMBAAAA.Peebee:BAAANQADCgYIBgAAAA==.Perfectlock:BAAANQAECgUJCwAAAA==.',
Pi='Pigog:BAAANQAECgIIAgAAAA==.',
Po='Pordgio:BAAANQAECgMJAwAAAA==.Pozzi:BAAANQAECgcIBwAAAA==.',
Pr='Praypal:BAAANQADCgQIBAAAAA==.',
Ps='Psuedolus:BAAANQAECgUICgAAAA==.Psålm:BAAANQAECgcJEAAAAA==.',
Pu='Pulshadow:BAABNQAECoEhAAIRAAkK9COgAwCLAwARAAkK9COgAwCLAwAAAA==.Pumah:BAAANQADCgcJGQAAAA==.',
Qt='Qtclaps:BAAANQADCgcJBwAAAA==.',
Qu='Quartzecoatl:BAAANQADCgUJCQAAAA==.',
Ra='Raamen:BAAANQADCgcJGQAAAA==.Raellia:BAABNQAECoEXAAQPAAcKtQ5XOwCwAAAVAAQK5hBhngD1AAAPAAMKygtXOwCwAAAWAAEKTggVIgA3AAAAAA==.Raimmey:BAAANQADCgYICgAAAA==.Rajia:BAAANQAECgIJAgABNQAECgUJCgADAAAAAA==.Ralune:BAAANQAECgUJCgAAAA==.Ranes:BAABNQAECoEXAAIUAAcKYRtSFwA3AgAUAAcKYRtSFwA3AgAAAA==.Razagual:BAAANQAECggICgAAAA==.',
Re='Redback:BAAANQABCgMIAwAAAA==.Redxelementz:BAABNQAECoEeAAIMAAkK5CQoAQDLAwAMAAkK5CQoAQDLAwAAAA==.Redxpastakan:BAAANQADCgUJBQABNQAECgkJHgAMAOQkAA==.Renasen:BAAANQAECgUJCwAAAA==.Reno:BAAANQAECgUJDAAAAA==.Resiretha:BAAANQAECgUJBwAAAA==.Revelynn:BAAANQAECgYJEgAAAA==.Rexkwondo:BAAANQAECgQJBAAAAA==.',
Ri='Rivliam:BAAANQAECgQJBQAAAA==.Rizzn:BAAANQADCgcIEAABNQAECgcIEwADAAAAAA==.',
Ro='Rook:BAAANQAECgIIAgAAAA==.Rooxxy:BAAANQAECgQIDwAAAA==.Rotawna:BAAANQADCgUIBQAAAA==.Roxxyyzz:BAAANQAECgIJAwABNQAECgQIDwADAAAAAA==.',
Ru='Rumikang:BAAANQADCgIJAgABNQAECgcJFwAPALUOAA==.',
Ry='Rynoh:BAAANQAECgEJAQAAAA==.Rythrik:BAAANQAECggICgAAAA==.',
Sa='Sainted:BAACNQAFFIEHAAIKAAUKJRMGBQCjAQAKAAUKJRMGBQCjAQA1AAQKgSMAAwoACQrjFLglAHYCAAoACQrjFLglAHYCAAgABwrqFEpvAK8BAAAA.Sanoks:BAAANQAECgYJEAAAAA==.Sanokz:BAAANQADCgYIBgAAAA==.Sassafraz:BAAANQADCggJCAABNQAECgYJDwADAAAAAA==.Savira:BAAANQAECgQJBwAAAA==.',
Sc='Scaleorva:BAAANQAECgQJBwAAAA==.',
Se='Seraphìm:BAAANQAECgUJCQAAAA==.Seïnaru:BAAANQAECgMJAwAAAA==.',
Sh='Shadenova:BAAANQADCgUJBgABNQAECgUJCgADAAAAAA==.Shadowpath:BAAANQABCgQIAgAAAA==.Shadyballs:BAAANQAECgUJCgAAAA==.Shakypete:BAAANQAECgQJBQABNQAECgUJFwABAFAPAA==.Shamysosa:BAAANQAECgQJBgAAAA==.Shiionknow:BAAANQADCgQIBAAAAA==.Shinjí:BAAANQAECgUICQABNQAECgkJJwAYAAQlAA==.Shmob:BAAANQAECgEIAgAAAA==.Shnappz:BAAANQAECgQJCwAAAA==.Shwillarou:BAAANQAECgYJEQAAAA==.Shádôws:BAAANQADCgYICwAAAA==.',
Si='Sinergee:BAAANQAECgIJAgAAAA==.Sinnj:BAAANQADCgcIDQAAAA==.',
Sk='Skinsey:BAAANQADCgYIDQAAAA==.Skinzey:BAAANQADCgYJCwAAAA==.Skinzy:BAAANQABCgYJBwAAAA==.Skycrush:BAAANQADCgUICQAAAA==.',
Sl='Slanie:BAAANQAECgUICQAAAA==.Slingerz:BAABNQAECoEcAAMZAAgKxBEJDQDOAQAZAAgKxBEJDQDOAQAaAAEKqAOLJQAnAAAAAA==.Slowmeaux:BAAANQADCgEIAQAAAA==.',
Sm='Smalldragon:BAAANQADCgcIBgAAAA==.Smoky:BAAANQAECgYICQAAAA==.',
Sn='Sneakpastya:BAAANQADCgIIAgAAAA==.Sneakyg:BAAANQAECgQJCQABNQAECgcJEwADAAAAAA==.Snoochie:BAAANQAECgUICwAAAA==.',
So='Sol:BAABNQAECoEjAAIbAAkKeiIBAQB2AwAbAAkKeiIBAQB2AwAAAA==.Solkar:BAAANQADCgUJBQABNQAECgcJEAADAAAAAA==.Sollis:BAAANQAECgMJBAAAAA==.Solohoes:BAAANQAECgIIAgAAAA==.Soulcoil:BAAANQAECgMJAwABNQAECgQJBAADAAAAAA==.Soulfury:BAAANQABCgUIBgABNQAECgQJBAADAAAAAA==.Soulshock:BAAANQAECgQJBAAAAA==.Soulstorm:BAAANQADCgYIBgABNQAECgQJBAADAAAAAA==.',
Sp='Spawntier:BAAANQADCgUIBQABNQADCggICAADAAAAAA==.Spazzchel:BAAANQADCggIIAAAAA==.Spiritbox:BAACNQAFFIEKAAIMAAYKdRr/AQATAgAMAAYKdRr/AQATAgA1AAQKgR8AAgwACQqxJI4EAIYDAAwACQqxJI4EAIYDAAE1AAUUBAgEAAMAAAAA.Spruce:BAAANQADCggJEAAAAA==.Sprucemoose:BAAANQADCgIIBQABNQADCgQJCAADAAAAAA==.',
St='Stahlman:BAAANQAECgUIDQAAAA==.Stalpho:BAAANQAECgYJDwAAAA==.Starblessed:BAAANQADCgUJCwABNQAECgQJBAADAAAAAA==.Starkind:BAAANQAECgQJBAAAAA==.Starliner:BAAANQAECgcIDgAAAA==.Stasis:BAAANQAECgIIAgABNQAFFAQIBAADAAAAAA==.Strahd:BAAANQADCgUJDgAAAA==.Styrke:BAAANQADCgYIBgAAAA==.Styrmir:BAAANQADCgMIAwAAAA==.',
Su='Subza:BAABNQAECoEcAAITAAgK0RGOegAmAgATAAgK0RGOegAmAgAAAA==.Suurik:BAAANQABCgIIAgAAAA==.',
Sw='Swagtistic:BAAANQADCggJFAAAAA==.',
Ta='Tahra:BAAANQADCgcJBwAAAA==.Taliss:BAAANQAECgYJEAAAAA==.Tankmedaddy:BAAANQAECggIEwAAAA==.Tappuccino:BAAANQAECgIIAgAAAA==.Taras:BAABNQAECoEhAAMQAAkKbiMyKgDFAgAQAAgKfSIyKgDFAgAaAAYKnBr8CADEAQAAAA==.Taraxist:BAAANQAECgYJDwAAAA==.Tautology:BAAANQAECgYJDAAAAA==.Tazajin:BAAANQADCgYIBgAAAA==.',
Tc='Tchala:BAAANQAECgcJEwAAAA==.Tchaumb:BAAANQADCgEIAQAAAA==.',
Td='Tdog:BAAANQADCgcJBwAAAA==.',
Te='Teacup:BAAANQADCgYIBgABNQAECgYJDwADAAAAAA==.Teks:BAAANQAECgYJDwAAAA==.Telian:BAAANQADCgUIBQAAAA==.Terracustode:BAAANQABCgIJAgAAAA==.Teth:BAAANQAECgEJAQAAAA==.Tevildo:BAAANQABCgIIAgAAAA==.',
Th='Thaine:BAABNQAECoEcAAIIAAgKYSOrFQAsAwAIAAgKYSOrFQAsAwAAAA==.Theundeadone:BAABNQAECoEdAAIRAAkKsBrDCgD9AgARAAkKsBrDCgD9AgAAAA==.Thndrwzrd:BAAANQADCggIGwAAAA==.Thorphan:BAABNQAECoEbAAQcAAgK7hiCCQCFAgAcAAgKqRiCCQCFAgAOAAUKBxaVdAA3AQAMAAUKcAuMjgDZAAAAAA==.',
Ti='Ticho:BAAANQAECgIIAgAAAA==.',
To='Torez:BAAANQAECgUIBQABNQAECggJHAALACsUAA==.Torodisilis:BAAANQAECgIIAgABNQAECgcJEwADAAAAAA==.Toxicavenger:BAAANQAECggJCAAAAA==.',
Tr='Treygec:BAAANQAECgIIAgAAAA==.Tribolonotus:BAAANQADCgcIFQAAAA==.Trickette:BAAANQADCgUJBQABNQAECgEJAQADAAAAAA==.Trilleong:BAAANQADCgIIAgAAAA==.Trina:BAAANQADCggJCAAAAA==.Trisilla:BAAANQADCggIEAABNQAECggJHwAdAIUKAA==.Troubleshot:BAAANQADCgYJBgAAAA==.Trujal:BAAANQAECgYJEAAAAA==.',
Tu='Turdmonk:BAABNQAECoEaAAIXAAcK0hmXFAAwAgAXAAcK0hmXFAAwAgAAAA==.',
Ty='Tylandon:BAAANQABCgQICAAAAA==.Tyndal:BAAANQADCgMIBAAAAA==.Typhon:BAAANQAECgYJEAAAAA==.',
Un='Unclebób:BAAANQADCgYIDAABNQAECgUJBwADAAAAAA==.',
Va='Vaeshta:BAAANQAECgUJCgAAAA==.Vaku:BAAANQADCgYJBgAAAA==.Valhallarama:BAABNQAECoEZAAIMAAkKPhktHwCZAgAMAAkKPhktHwCZAgAAAA==.Valika:BAAANQABCgYIBgAAAA==.Vampy:BAAANQADCggJDwAAAA==.Vannida:BAAANQADCgMIBAAAAA==.',
Ve='Vengencedawg:BAAANQAECgYJEAAAAA==.Vexxya:BAAANQADCgQIAwAAAA==.',
Vl='Vladus:BAAANQAECgcJEAAAAA==.',
Vo='Voodoo:BAAANQADCgUJCwAAAA==.',
Vy='Vyllian:BAAANQAECgUIDAAAAA==.',
Wa='Wangwang:BAAANQADCgcIFgAAAA==.Wardrag:BAAANQABCgQIBAAAAA==.Wareshesh:BAAANQADCgUIBQAAAA==.Warlakaflaka:BAAANQAECgQJBQABNQAECgUJCgADAAAAAA==.',
Wh='Whale:BAAANQAECgYJDwAAAA==.',
Wi='Windfury:BAAANQAECgYJEQAAAA==.Windfuryous:BAAANQADCgUICQAAAA==.Winston:BAAANQADCgcJEwAAAA==.',
Wo='Wolfsbane:BAAANQADCgYIBgAAAA==.Wonpiece:BAAANQADCgQIBgABNQAECgkJHQABAEATAA==.',
Wu='Wulfnir:BAAANQADCgcIBwAAAA==.',
Wy='Wylestrean:BAAANQAECgcIEAAAAA==.',
Xa='Xanokz:BAAANQADCgEIAQABNQAECgYJEAADAAAAAA==.Xarytha:BAAANQABCgMJAwABNQAECgcJCwADAAAAAA==.',
Xi='Xiaomao:BAEANQADCgcIBwABNQAECgEIAQADAAAAAA==.',
Ye='Yeinn:BAABNQAECoEdAAMQAAcKQiCxQABkAgAQAAcKQiCxQABkAgAaAAEKwx7cHABYAAAAAA==.',
Za='Zandalarthas:BAAANQAECgQJBwAAAA==.',
Zc='Zcredo:BAAANQAECggIEwAAAA==.',
Ze='Zel:BAAANQADCggIIAAAAA==.Zentradei:BAAANQADCgQIBAAAAA==.Zephariel:BAAANQADCgQJCwAAAA==.Zerus:BAAANQABCgMIBAAAAA==.',
Zi='Zieganfuss:BAAANQAECgcJCwAAAA==.Zinrozlek:BAAANQAECgEIAQAAAA==.',
Zo='Zoho:BAABNQAECoEfAAIdAAgKhQrXDwB9AQAdAAgKhQrXDwB9AQAAAA==.',
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
