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

local lookup = {'Priest-Shadow','Unknown-Unknown','Paladin-Protection','DemonHunter-Havoc','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Blood','Shaman-Elemental','Mage-Frost','DeathKnight-Frost','Mage-Arcane','Druid-Balance','Druid-Restoration','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Affliction','Druid-Guardian','Monk-Brewmaster','Priest-Holy','Paladin-Holy','DeathKnight-Unholy','Warrior-Fury','Druid-Feral','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Devourer',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abaca:BAAANQADCgYIDAAAAA==.Abacatte:BAAANQAECgQICAAAAA==.',
Ad='Adelaide:BAAANQADCgUIBQABNQAFFAYIEAABAM8RAA==.',
Ae='Aelthor:BAAANQADCggIMgAAAA==.',
Ai='Aioliavictus:BAAANQADCgUIBQAAAA==.',
Al='Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Alfajhor:BAABNQAECoEYAAIDAAcK7yP4CQDAAgADAAcK7yP4CQDAAgAAAA==.Alfajhòr:BAAANQADCgUIBQAAAA==.Alfajhõr:BAAANQAECgYIBgAAAA==.Alkaid:BAAANQAECgcICgAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Alleriane:BAAANQAECgYIEwAAAA==.Allone:BAABNQAECoEXAAIEAAcK+QeIPgBZAQAEAAcK+QeIPgBZAQAAAA==.Allunt:BAAANQAECgQIBAAAAA==.Almin:BAAANQAECgIIBAAAAA==.',
Am='Ametnys:BAAANQAECgUICgAAAA==.Amonhar:BAAANQAECgQIBAABNQAECgYIEgACAAAAAA==.',
An='Anakata:BAAANQADCgYICAAAAA==.Andaliz:BAABNQAECoEiAAIFAAgKzSSZEgBdAwAFAAgKzSSZEgBdAwAAAA==.Andaril:BAAANQADCgcIBwAAAA==.Antonel:BAAANQABCgYIBgAAAA==.Antonellaes:BAAANQADCgcICgABNQADCggIFAACAAAAAA==.',
Ar='Arcanör:BAAANQAECgUICwAAAA==.Arctorius:BAAANQAECgUICAAAAA==.Aronys:BAAANQADCggIDQAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAAANQAECgcIEwAAAA==.Arukäi:BAAANQAECgYIEAAAAA==.Arägørn:BAAANQADCgEIAQAAAA==.',
As='Assintomatic:BAAANQABCgYICQABNQAECgYICwACAAAAAA==.',
At='Atriuz:BAAANQAECgQIDAAAAA==.',
['Aÿ']='Aÿ:BAAANQAECgEIAQAAAA==.',
Ba='Baldraccus:BAAANQADCgcIBwAAAA==.Balk:BAABNQAECoEeAAIGAAgKqR7VLACoAgAGAAgKqR7VLACoAgAAAA==.Bambur:BAAANQADCggICgAAAA==.Barauna:BAAANQABCgIIAgAAAA==.Barbabruto:BAAANQAECgUJCQAAAA==.Barbacancer:BAAANQAECgQJBAAAAA==.Barbasanta:BAAANQAECgEIAQABNQAECgUJCQACAAAAAA==.Batgirl:BAAANQADCgQIBAAAAA==.',
Bi='Bigbag:BAAANQADCgQIBQAAAA==.Biønic:BAAANQAECgMIAwAAAA==.',
Bl='Blackmoonx:BAAANQAECgcICgAAAA==.Blackninja:BAAANQABCggIFwAAAA==.Blu:BAEANQAECgEIAQABNQAECgYIEQACAAAAAA==.',
Bo='Box:BAAANQADCgMIAwAAAA==.',
Br='Brahman:BAAANQAECgEIAQAAAA==.Bright:BAAANQADCgYIBgAAAA==.Bruex:BAAANQADCgIIAgAAAA==.Bruker:BAAANQADCgIIAgAAAA==.',
Bu='Buzzumaaky:BAAANQAECgQIDAAAAA==.',
['Bá']='Bávor:BAAANQADCgEIAQAAAA==.',
['Bí']='Bílly:BAAANQAECgEIAQAAAA==.',
Ca='Callstorm:BAAANQABCgUIBQAAAA==.Calteryeker:BAAANQAECgIIAgAAAA==.Capitu:BAAANQADCggICAABNQAECgQICgACAAAAAA==.Capyvara:BAAANQABCgYIBwAAAA==.Caralh:BAABNQAECoEiAAIHAAkK7iAGCgBJAwAHAAkK7iAGCgBJAwAAAA==.Caroll:BAAANQADCgMIAwAAAA==.Caçaorda:BAAANQAECgMJBAAAAA==.',
Ce='Cecilith:BAABNQAECoEcAAIIAAkKSx7OFAAoAwAIAAkKSx7OFAAoAwAAAA==.Cernûnnos:BAAANQAECgQIDAAAAA==.',
Ch='Champdude:BAAANQAECgcIEwAAAA==.Chopquatro:BAAANQADCggICAAAAA==.Chrnnos:BAAANQAECgIIAgAAAA==.',
Co='Corineus:BAAANQADCgYIBgAAAA==.Cowzeroth:BAABNQAECoEWAAIIAAcKzhldQwAbAgAIAAcKzhldQwAbAgAAAA==.',
Cr='Crassustitan:BAAANQAECgUICwAAAA==.Cristcalad:BAAANQAECgUIBwAAAA==.',
Da='Daemi:BAAANQAECgcIDQAAAA==.Dalaty:BAAANQADCgIJAgAAAA==.Daresh:BAAANQADCgEJAQAAAA==.Dariok:BAAANQAECgUICQAAAA==.Darkove:BAABNQAECoEdAAIJAAgKnhEwCQDwAQAJAAgKnhEwCQDwAQAAAA==.Darrow:BAABNQAECoEZAAIKAAgK5w9tLQDPAQAKAAgK5w9tLQDPAQAAAA==.Daryan:BAAANQAECgIIAgAAAA==.Day:BAAANQAECgQIBAAAAA==.',
De='Deathinhu:BAABNQAECoEcAAILAAgKFB+mSADNAgALAAgKFB+mSADNAgAAAA==.Demoriana:BAAANQADCggIFAAAAA==.Dethroned:BAAANQAECgQIBgAAAA==.',
Di='Dimeros:BAABNQAECoEbAAIMAAgK6QfQRQCHAQAMAAgK6QfQRQCHAQAAAA==.Divano:BAABNQAECoEaAAIBAAkKhhaTFAB9AgABAAkKhhaTFAB9AgAAAA==.',
Dk='Dkats:BAAANQADCgQIBAAAAA==.Dkhalifa:BAAANQADCgYIBgAAAA==.',
Do='Dogowner:BAAANQADCgcICAAAAA==.Donora:BAAANQAECgQIBAAAAA==.Dorfillaw:BAAANQAECgUICQAAAA==.Dorvana:BAAANQADCgMJAwABNQAECggIIgAFAM0kAA==.',
Dr='Dracthyrius:BAAANQADCggJDgAAAA==.Dragonstyle:BAAANQAECgcICwAAAA==.Dragony:BAAANQABCgIIBQAAAA==.Dreez:BAAANQAECgQIBgAAAA==.Drexus:BAAANQADCgMIAwAAAA==.Drigolas:BAAANQADCgYIBgAAAA==.',
Eh='Ehomi:BAAANQADCgIIAgAAAA==.',
Ei='Eirin:BAAANQAECgQIDwAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Ellvarg:BAAANQADCgYIDAAAAA==.Eluuria:BAAANQAECggIBQAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.Ennafaryn:BAAANQABCgQIBAAAAA==.Ensabanú:BAAANQADCgQIBAAAAA==.',
Er='Erilaethaen:BAAANQAECgIIAgAAAA==.Erlek:BAAANQADCgQIBgAAAA==.Ernest:BAABNQAECoEYAAINAAgKjxk7EwBvAgANAAgKjxk7EwBvAgAAAA==.Erulan:BAAANQADCgQIBwAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAABNQAECoEUAAIHAAgKHQ8aQgCxAQAHAAgKHQ8aQgCxAQAAAA==.Etubrutus:BAAANQADCgUIBAAAAA==.',
Ev='Evangelouco:BAAANQADCgQIBAAAAA==.Evilbarba:BAABNQAECoEUAAIFAAgK2hfEWAA5AgAFAAgK2hfEWAA5AgAAAA==.',
Ex='Exort:BAAANQAECgQICAAAAA==.Exothus:BAAANQAECgQJBwAAAA==.',
Fa='Faldark:BAAANQADCgUIBQAAAA==.Fandrall:BAAANQADCgUIBQAAAA==.Faranir:BAAANQADCggIEAAAAA==.Faris:BAABNQAECoEWAAMOAAcKFA46HwCvAQAOAAcK6ww6HwCvAQAPAAIKkxEVYgCJAAAAAA==.Faver:BAAANQADCgMIAwAAAA==.Faölin:BAAANQAECggIEQAAAA==.',
Fe='Ferael:BAABNQAECoEcAAMFAAgKNRnWRgB0AgAFAAgKNRnWRgB0AgADAAQK0g1NPAC2AAAAAA==.',
Fl='Flavors:BAAANQAECgcIEAAAAA==.Florbela:BAAANQAECgQICAAAAA==.',
Fr='Fredericc:BAAANQAECgQIBAAAAA==.Freecs:BAAANQAECgEJAQAAAA==.Freyá:BAAANQAECgYIEgAAAA==.Frostburn:BAAANQAECgYIDQAAAA==.Froststriker:BAAANQAECgEIAQAAAA==.',
Fu='Fulvo:BAAANQADCgQIBQAAAA==.',
Ga='Gadodamorena:BAAANQAECgEIAQAAAA==.Galfur:BAABNQAECoEXAAIMAAUKGQZNaQDSAAAMAAUKGQZNaQDSAAAAAA==.Galhuda:BAAANQADCgMIAwAAAA==.Galica:BAAANQADCgIIAgAAAA==.',
Ge='Geisty:BAAANQAECgEIAQABNQAECgIIBAACAAAAAA==.',
Gl='Glutotwo:BAAANQADCgYJDgAAAA==.',
Go='Goldchain:BAAANQAECgEIAgAAAA==.',
Gr='Grumax:BAABNQAECoEYAAIFAAcKdAxTmwB+AQAFAAcKdAxTmwB+AQAAAA==.',
Gu='Gudeath:BAABNQAECoEhAAIQAAcK2hXRfADQAQAQAAcK2hXRfADQAQAAAA==.Guerrerinhow:BAAANQADCggIFwABNQAECgYICwACAAAAAA==.Guitianki:BAAANQADCgYIBgAAAA==.Gulek:BAAANQAECgUICAAAAA==.Gussg:BAAANQAECgQICwAAAA==.',
['Gà']='Gàladriel:BAAANQADCgEIAQAAAA==.',
['Gö']='Göhan:BAAANQAECgEIAQAAAA==.',
['Gø']='Gøvers:BAAANQAECgUICAAAAA==.',
['Gü']='Güttz:BAABNQAECoEWAAIEAAgKMA3hLwDLAQAEAAgKMA3hLwDLAQAAAA==.',
Ha='Hagires:BAAANQAECgYIBwAAAA==.Hanaluna:BAAANQADCggICAAAAA==.Harchus:BAAANQADCgYICwAAAA==.Hargarthul:BAAANQADCgMIBAAAAA==.Hazell:BAAANQADCggIDQAAAA==.',
He='Hellspont:BAAANQAECgUIDgAAAA==.Hendrikison:BAAANQADCgcICgAAAA==.',
Ho='Horagalles:BAAANQADCgIIAgAAAA==.Hotmojo:BAABNQAECoEtAAILAAkKXh8rMAARAwALAAkKXh8rMAARAwAAAA==.',
Hu='Hunfox:BAABNQAECoEjAAIGAAgK+iLvEwAkAwAGAAgK+iLvEwAkAwAAAA==.',
Hy='Hylana:BAAANQADCgEIAQAAAA==.',
['Hö']='Hölycrüsh:BAABNQAECoEhAAIFAAgKpB+lMwC7AgAFAAgKpB+lMwC7AgAAAA==.',
Ik='Ikoo:BAAANQAECgYJDAAAAA==.',
Il='Illaril:BAACNQAFFIEJAAIRAAQKeQjHAQDdAAARAAQKeQjHAQDdAAA1AAQKgScAAhEACQqaGJoFAH0CABEACQqaGJoFAH0CAAAA.',
In='Interestelar:BAAANQADCgYIBgAAAA==.Invisiblelol:BAAANQAECgUICgAAAA==.',
Ir='Irmãodouther:BAAANQAECgUJBQAAAA==.Irridan:BAAANQADCgQIAwAAAA==.',
Is='Isenhearth:BAAANQABCgUIBQAAAA==.Ishtarie:BAAANQAECgQICQAAAA==.',
It='Itokeszdan:BAAANQADCgYIBAAAAA==.',
Iv='Ivina:BAABNQAECoErAAMSAAkKwhdeMgCFAgASAAkKwhdeMgCFAgATAAEKjwZXKQAwAAAAAA==.',
Iz='Izaar:BAAANQADCgYICAAAAA==.',
Ja='Jangeoffry:BAAANQABCgMIAwAAAA==.',
Jh='Jhonatinha:BAAANQAECgUIBwAAAA==.',
Jk='Jks:BAAANQADCggIDgAAAA==.',
Ju='Jullianxd:BAAANQAECgQIBAAAAA==.',
Ka='Kaallew:BAAANQAECgYICwAAAA==.Kaelonidas:BAAANQAECgQICwAAAA==.Kaelyaa:BAAANQADCgUIBQAAAA==.Kainer:BAAANQADCgYICQAAAA==.Kalazshar:BAAANQAECgYIDgAAAA==.Kalduran:BAAANQADCggIMwAAAA==.Kaluss:BAAANQAECgYIEAAAAA==.Kanduz:BAAANQADCgUIBgAAAA==.Kantaa:BAAANQADCggIHQAAAA==.Karmabb:BAAANQAECgUICgAAAA==.Kauss:BAAANQAECgIJAgAAAA==.Kavartu:BAABNQAECoEgAAIIAAgKtBf2OgBBAgAIAAgKtBf2OgBBAgAAAA==.Kayli:BAAANQADCgcICwAAAA==.Kaysa:BAAANQADCgUJBQAAAA==.',
Ke='Keillor:BAAANQAECgUIDwAAAA==.Kenzou:BAAANQAECgUICwAAAA==.Keytymari:BAAANQAECgQIBQAAAA==.',
Kh='Khaliq:BAAANQAECgQICwAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIBAACAAAAAA==.',
Ki='Kieran:BAAANQADCgYIBgAAAA==.Kimashi:BAAANQAECgEJAgAAAA==.Kissme:BAAANQAECgUIEwAAAA==.Kitamor:BAABNQAECoEbAAMMAAcK3QRwXQAHAQAMAAcK5QNwXQAHAQAUAAEKDQtuRAAmAAAAAA==.',
Ko='Koriakin:BAAANQADCgYIEQAAAA==.Korogth:BAAANQADCggICQAAAA==.Kosmo:BAAANQAECgUICQAAAA==.',
Kr='Krosmu:BAAANQABCgMIAwAAAA==.Kräsus:BAAANQADCgQIBAABNQAECggIGAAVAPIdAA==.',
Ku='Kurado:BAAANQAECgIIAgAAAA==.',
Kz='Kzinn:BAAANQAECgEIAQAAAA==.',
['Kö']='Körn:BAAANQAECgQIBAABNQAECgcIDwACAAAAAA==.',
La='Ladyrichter:BAAANQABCgUIBgAAAA==.Laetus:BAAANQAECgUIDQAAAA==.Laiander:BAAANQAECgUIBwAAAA==.Laiany:BAABNQAECoEaAAIWAAgKmCH+EwABAwAWAAgKmCH+EwABAwAAAA==.Lainarning:BAAANQAECgEIAQAAAA==.Lani:BAAANQABCgEIAQAAAA==.',
Le='Leetohro:BAAANQAECgQJBQAAAA==.Leodoros:BAABNQAECoEXAAILAAYKJQbnCQEqAQALAAYKJQbnCQEqAQAAAA==.',
Li='Lichkíng:BAAANQAECgQIBAAAAA==.Lighty:BAAANQADCgQICAAAAA==.Lijiang:BAABNQAECoEYAAIVAAgK8h1bBgCpAgAVAAgK8h1bBgCpAgAAAA==.Lilibel:BAAANQAECgEIAwAAAA==.Lindaah:BAAANQADCggIKAAAAA==.Lindapriesty:BAAANQADCgIIAgAAAA==.Lislfox:BAAANQAECgYIEgAAAA==.',
Ll='Lledritch:BAAANQADCgUIBQAAAA==.',
Lo='Lockdown:BAABNQAECoEeAAISAAgKQBGoVAAMAgASAAgKQBGoVAAMAgAAAA==.Loukou:BAAANQADCggIGAAAAA==.',
Lu='Luacs:BAAANQAECgcIDwAAAA==.Lucileia:BAAANQADCgcIBwAAAA==.Lucyfary:BAAANQADCgcICAAAAA==.Luhhrogue:BAAANQAECgMIAwAAAA==.Lunirah:BAAANQADCgYICAAAAA==.Luxwind:BAAANQABCgIIAgABNQABCgMIBQACAAAAAA==.',
Ly='Lylka:BAABNQAECoEWAAMDAAgKfR6eDACKAgADAAgKfR6eDACKAgAXAAMKQiIIigAqAQAAAA==.',
['Lé']='Léofar:BAAANQAECgQICwAAAA==.',
Ma='Maanu:BAAANQADCgUIBQABNQADCggIKAACAAAAAA==.Maeghann:BAAANQADCgQIAwAAAA==.Magostosaa:BAAANQABCgIIAgAAAA==.Makani:BAAANQAECgEIAgAAAA==.Malewolyyc:BAABNQAECoEaAAMWAAgKuBiHRgAFAgAWAAgKuBiHRgAFAgABAAQK+A1IPgDiAAAAAA==.Massafera:BAAANQAECgQICwAAAA==.Mathfacbruxo:BAAANQADCgYJBgABNQAECgcIDgACAAAAAA==.Mathfacii:BAAANQAECgcIDgAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Mc='Mcq:BAAANQAECgEIAQAAAA==.',
Md='Mdrdark:BAABNQAECoEfAAIYAAgK+BwRJQBdAgAYAAgK+BwRJQBdAgAAAA==.',
Me='Medz:BAAANQAECgQICwAAAA==.Meetjack:BAAANQAECgEIAQAAAA==.Meizu:BAAANQAECgQJDAAAAA==.Mellkor:BAAANQAECgUIDQAAAA==.Metamorful:BAAANQAECggIDgAAAA==.',
Mi='Milim:BAAANQAECgUJBQAAAA==.Minilock:BAAANQAECgQIBQAAAA==.Mistogunn:BAAANQADCggICAAAAA==.',
Mm='Mmarcão:BAAANQABCgMIAwAAAA==.',
Mo='Modes:BAAANQAECgQICgAAAA==.Moffir:BAAANQADCgYIBgAAAA==.Mogrus:BAAANQADCgUIAgAAAA==.Mohotok:BAAANQAECgcIEQAAAA==.Monshiro:BAAANQAECgEIAQABNQAECgEJAQACAAAAAA==.Mortixxia:BAAANQAECgUIDAAAAA==.',
Mu='Murano:BAABNQAECoEfAAIZAAgKzhVlCAAQAgAZAAgKzhVlCAAQAgAAAA==.',
['Má']='Máia:BAAANQAECgQIBwAAAA==.',
['Mä']='Mändosz:BAAANQAECgQICAAAAA==.',
['Mø']='Mørgane:BAAANQADCggIFgAAAA==.',
['Mÿ']='Mÿstyna:BAAANQADCgUJCQAAAA==.',
Na='Nagts:BAAANQADCggICgAAAA==.Nalathiel:BAAANQAECgQIBAAAAA==.Narrih:BAAANQAECgIIBAAAAA==.Nazzh:BAAANQAECggIDAAAAA==.',
Ne='Nefas:BAAANQAECgcICwAAAA==.Nepthunus:BAAANQAECgUJCwAAAA==.',
No='Notforall:BAAANQADCgIIAgAAAA==.',
Od='Odestruidor:BAAANQAECgEIAgAAAA==.',
Ol='Oluss:BAABNQAECoEdAAMXAAgKVQ3bVQDQAQAXAAgKVQ3bVQDQAQAFAAEKtwd6RAE4AAABNQAECggIIwAGAPoiAA==.',
On='Onys:BAAANQADCgIIAgAAAA==.',
Op='Opus:BAAANQAECgYIDQAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Origon:BAAANQADCgIIAwAAAA==.Orillan:BAAANQAECgcIEgAAAA==.Orsonn:BAAANQAECgQIBAAAAA==.Orucão:BAAANQABCgEIAQAAAA==.Orukam:BAAANQAECgYIEAAAAA==.Orukanorum:BAAANQADCgcIAwAAAA==.Orukrente:BAAANQABCgIIAgAAAA==.Orulord:BAAANQABCgIIAwAAAA==.Orurage:BAAANQABCgYIBAAAAA==.',
Pa='Palatina:BAAANQAECgYIEwABNQAECggIIgAFAM0kAA==.Pandalokodj:BAAANQAECgEIAQAAAA==.Pangedrey:BAAANQAECgcIEgAAAA==.Parký:BAAANQAECgUICgAAAA==.Paullk:BAAANQADCgIIAgAAAA==.',
Pe='Penseur:BAAANQABCgYJBgAAAA==.Peruchi:BAAANQADCgIJAgAAAA==.Perísdra:BAAANQADCgUIBgABNQAECgIIAgACAAAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pitombinha:BAAANQAECggIDwAAAA==.Pixiks:BAAANQABCgYIBwAAAA==.',
Pp='Ppandora:BAAANQADCgUICgAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pä']='Pändero:BAAANQABCgMIAwAAAA==.',
['Pî']='Pîo:BAABNQAECoElAAILAAkKwyGRHABRAwALAAkKwyGRHABRAwAAAA==.',
Qu='Quirow:BAAANQAECgQIDQAAAA==.',
Ra='Radiação:BAAANQAECgMIAwAAAA==.Radunz:BAABNQAECoEXAAIaAAgK4BvaBgCaAgAaAAgK4BvaBgCaAgAAAA==.Ragnaros:BAAANQAECgQIBQAAAA==.Ragnarssön:BAAANQADCgEIAQAAAA==.Ragnarøk:BAAANQABCggICAAAAA==.Raio:BAABNQAECoEZAAILAAcKchqJhAA5AgALAAcKchqJhAA5AgAAAA==.Ramorey:BAAANQADCgQIBgAAAA==.Ranruulfnarm:BAAANQABCgQICAAAAA==.Rargsa:BAAANQAECgEIAQAAAA==.Rargul:BAAANQAECgEIAQAAAA==.Rariel:BAAANQAECgQIBAAAAA==.Raymain:BAABNQAECoEdAAMbAAgKUhmZHAD6AQAbAAcKIxmZHAD6AQAcAAYKmhV5GACgAQAAAA==.Raíka:BAAANQADCggIDQAAAA==.',
Re='Rebimboca:BAAANQAECgEIAQAAAA==.Redoon:BAAANQADCgQIBAAAAA==.Rendoras:BAAANQAECgEIAQAAAA==.Rezadeiro:BAAANQADCgUIBAAAAA==.',
Rh='Rhaumarhu:BAAANQADCgYIBgAAAA==.',
Ro='Rockit:BAAANQADCgMIBgAAAA==.Rodbree:BAAANQAECgcIEgAAAA==.Roguinhu:BAAANQAECgEIAwAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rurumo:BAAANQAECgEJAQAAAA==.Rustovick:BAAANQAECgEIAQAAAA==.',
['Rå']='Råy:BAABNQAECoEhAAMYAAgKXB+CHQCVAgAYAAgKXB+CHQCVAgAKAAEKkg6zfgA+AAAAAA==.',
Sa='Saffír:BAAANQAECgYIDwAAAA==.Saniest:BAAANQAECgQICwAAAA==.Sapekinhä:BAAANQAECgQICQAAAA==.Satanvitória:BAAANQAECgYIEAAAAA==.',
Se='Segavaxx:BAAANQABCgQIBAAAAA==.Seilaa:BAAANQABCgIIAgAAAA==.Selorixie:BAAANQAECgMIBAABNQAECgUIDAACAAAAAA==.Sereiaa:BAAANQAECgIIAwAAAA==.',
Sh='Shamate:BAAANQADCgQJBAAAAA==.Shanoa:BAAANQAECgIIBAAAAA==.Sharae:BAAANQADCggIDQAAAA==.Shedo:BAAANQAECgcIDQAAAA==.Shonja:BAAANQADCgIJAwAAAA==.',
Si='Sialeeds:BAAANQADCgMIAwAAAA==.Siclop:BAAANQAECgIIAgAAAA==.Simplicity:BAAANQAECgUICwAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadrian:BAAANQADCgQIBgAAAA==.Skadryan:BAAANQADCgYIDAAAAA==.Skalnark:BAAANQADCgUIBQAAAA==.Skinme:BAAANQADCgcIBwAAAA==.Skysoul:BAAANQAECgEJAgAAAA==.',
So='Sofiela:BAAANQAECgIIAgAAAA==.Soijiro:BAAANQADCgIIAgAAAA==.Soju:BAAANQADCgIIAgAAAA==.Sombrea:BAAANQADCgYICwAAAA==.',
Sp='Spectrø:BAAANQADCgcIFAAAAA==.Sperber:BAAANQAECgYIEAAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stëlla:BAAANQAECgYIDgAAAA==.',
Su='Suckmyhammer:BAAANQAECgEIAgAAAA==.Sungjinwoo:BAAANQADCggIKAAAAA==.Sunnara:BAAANQAECgcIEgAAAA==.',
Sy='Syuon:BAABNQAECoEbAAIcAAkKxiGfAwBWAwAcAAkKxiGfAwBWAwAAAA==.',
Ta='Talandar:BAABNQAECoEcAAIMAAgK7BJ6LwAeAgAMAAgK7BJ6LwAeAgAAAA==.Tankudo:BAAANQAECgYIDwAAAA==.',
Te='Tennebra:BAAANQADCggICQAAAA==.',
Th='Thabitah:BAABNQAECoEYAAIBAAgK7Q3KIQDZAQABAAgK7Q3KIQDZAQAAAA==.Thanathus:BAAANQADCggIHAAAAA==.Thedragon:BAAANQAECgYIBgAAAA==.Thorkel:BAAANQABCgYIBgAAAA==.Thotamon:BAAANQADCgYIBgAAAA==.',
Ti='Tidim:BAAANQADCgYIBgAAAA==.Tiih:BAAANQABCgUIBQAAAA==.',
To='Tonypaludo:BAAANQAECgEIAQAAAA==.',
Us='Usfull:BAAANQAECgYIEgAAAA==.',
Va='Vaatu:BAAANQADCgMIBAAAAA==.Vallkÿria:BAAANQAECgEIAgAAAA==.Varrex:BAAANQADCgEIAQAAAA==.Vaëllen:BAAANQAECgYICAAAAA==.',
Ve='Vehuiáh:BAAANQAECgUIBgAAAA==.Velen:BAABNQAECoEcAAIYAAcKSRzrLQAhAgAYAAcKSRzrLQAhAgAAAA==.Verno:BAAANQADCgYICAAAAA==.Verzuk:BAAANQAECgQIBgAAAA==.',
Vi='Vintejulgar:BAAANQABCggICQAAAA==.Vintekilo:BAAANQAECggIEwAAAA==.',
Vo='Voiddh:BAABNQAECoEZAAIdAAkKHg1VJgDVAQAdAAkKHg1VJgDVAQAAAA==.',
Vr='Vrenshrrgn:BAAANQADCggIKgAAAA==.',
Vy='Vygh:BAAANQAECgYIEwAAAA==.Vyndrill:BAAANQAECgcIEwAAAA==.',
Wa='Walkers:BAAANQAECgUIEAAAAA==.Warlaka:BAAANQADCgUIBwAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.',
Xa='Xalmoria:BAAANQAECgUIBgAAAA==.',
Xu='Xurumeloun:BAAANQADCgYIBgAAAA==.',
Ya='Yamii:BAAANQAECgQIBgAAAA==.Yasmini:BAAANQABCgEIAQAAAA==.',
Yi='Yingsu:BAAANQAECgYIEAAAAA==.Yippwarr:BAAANQADCgMIBAAAAA==.',
Yu='Yunná:BAAANQADCgQIBAAAAA==.',
Yv='Yvin:BAAANQAECgIIAgAAAA==.',
Za='Zakir:BAAANQAECgEIAgAAAA==.Zaolron:BAAANQADCgIIAQAAAA==.',
Ze='Zeddshm:BAAANQAECgEJAQABNQAECggIGgAQAFwQAA==.Zeeno:BAAANQADCggICwAAAA==.',
Zh='Zhynah:BAAANQADCgUIBQAAAA==.',
Zi='Ziracruz:BAAANQAECgQICAAAAA==.',
Zu='Zulyn:BAAANQADCgcIDwAAAA==.',
['Àr']='Àrdath:BAAANQADCggIDgAAAA==.Àrthemís:BAAANQADCgEIAQAAAA==.',
['Ár']='Áraujo:BAAANQADCgEJAQABNQADCgUIBQACAAAAAA==.Árÿä:BAAANQAECgcIEwAAAA==.',
['Är']='Äraxy:BAAANQAECgEIAQAAAA==.',
['Èv']='Èver:BAAANQADCgIIAgAAAA==.',
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
