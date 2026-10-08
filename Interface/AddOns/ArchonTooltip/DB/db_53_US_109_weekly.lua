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

local lookup = {'Priest-Shadow','Paladin-Protection','Monk-Mistweaver','DemonHunter-Havoc','Priest-Holy','Paladin-Retribution','Unknown-Unknown','Druid-Guardian','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','DeathKnight-Blood','Shaman-Elemental','Monk-Windwalker','Mage-Frost','DeathKnight-Frost','Mage-Arcane','Druid-Balance','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Monk-Brewmaster','Shaman-Enhancement','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','DemonHunter-Devourer','Warlock-Destruction',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abaca:BAAANQAECgIIAgAAAA==.Abacatte:BAAANQAECgQICAAAAA==.',
Ad='Adelaide:BAAANQADCgUIBQABNQAFFAYIFQABAJUVAA==.',
Ae='Aelthor:BAAANQADCggIOwAAAA==.',
Ai='Aioliavictus:BAAANQADCgUIBQAAAA==.',
Al='Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAAANQAECgcICAAAAA==.Alfajhor:BAABNQAECoEfAAICAAgK1iJCCAABAwACAAgK1iJCCAABAwAAAA==.Alfajhòr:BAAANQAECgEIAQAAAA==.Alfajhõr:BAAANQAECgYIBgAAAA==.Alkaid:BAAANQAECgcIEQAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Alleriane:BAABNQAECoEaAAIDAAgK1RjIEQA1AgADAAgK1RjIEQA1AgAAAA==.Allone:BAABNQAECoEdAAIEAAcKXgmiRABnAQAEAAcKXgmiRABnAQAAAA==.Allunt:BAAANQAECgUIBQAAAA==.Almin:BAAANQAECgMIBQAAAA==.',
Am='Ametnys:BAAANQAECgUICgAAAA==.Amonhar:BAAANQAECgQIBAABNQAECgcIGQAFAIEaAA==.',
An='Anakata:BAAANQAECgMIAwAAAA==.Andaliz:BAABNQAECoEpAAIGAAgK9STeFwBSAwAGAAgK9STeFwBSAwAAAA==.Andaril:BAAANQADCgcIBwAAAA==.Antonel:BAAANQABCgYIBgAAAA==.Antonellaes:BAAANQADCgcIDAABNQAECgMIAwAHAAAAAA==.',
Ar='Arcanör:BAAANQAECgUIEAAAAA==.Arctorius:BAAANQAECgYIDgAAAA==.Aronys:BAAANQAECgQIBAAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAABNQAECoEbAAIIAAgKzBA5GACqAQAIAAgKzBA5GACqAQAAAA==.Arukäi:BAABNQAECoEaAAMJAAcK2QnorQB8AQAJAAcK2QnorQB8AQAKAAMKiQRcJABnAAAAAA==.Arägørn:BAAANQAECgIIAgAAAA==.',
As='Assintomatic:BAAANQABCgYICQABNQAECggIDAAHAAAAAA==.',
At='Atriuz:BAAANQAECgQIDAAAAA==.Ats:BAAANQADCgcIBwAAAA==.',
Az='Azerotiano:BAAANQADCggICAAAAA==.',
['Aÿ']='Aÿ:BAAANQAECgEIAQAAAA==.',
Ba='Baldraccus:BAAANQADCgcIBwAAAA==.Balk:BAABNQAECoEjAAILAAgK4h+YKwDKAgALAAgK4h+YKwDKAgAAAA==.Bambur:BAAANQADCggICgAAAA==.Barauna:BAAANQABCgIIAgAAAA==.Barbabruto:BAAANQAECgYIDgAAAA==.Barbacancer:BAAANQAECgQJBAAAAA==.Barbasanta:BAAANQAECgEIAQABNQAECgYIDgAHAAAAAA==.Batgirl:BAAANQAECgQIBAAAAA==.',
Bi='Bigbag:BAAANQADCgQIBQAAAA==.Biønic:BAAANQAECgUIBgAAAA==.',
Bl='Blackmoonx:BAAANQAECgcICwAAAA==.Blackninja:BAAANQABCggIGwAAAA==.Blu:BAEANQAECgEIAQABNQAECgYIEQAHAAAAAA==.',
Bo='Box:BAAANQADCgMIAwAAAA==.',
Br='Brahman:BAAANQAECgEIAQAAAA==.Bright:BAAANQADCgYIBgAAAA==.Bruex:BAAANQADCgIIAgAAAA==.Bruker:BAAANQADCgIIAgAAAA==.',
Bu='Buzzumaaky:BAAANQAECgQIDAAAAA==.',
['Bá']='Bávor:BAAANQADCgEIAQAAAA==.',
['Bí']='Bílly:BAAANQAECgEIAQAAAA==.',
Ca='Calteryeker:BAAANQAECgMIBQAAAA==.Capitu:BAAANQADCggICwABNQAECgYIEAAHAAAAAA==.Capyvara:BAAANQABCgYIBwAAAA==.Caralh:BAABNQAECoEkAAIMAAkK7iBlDQA1AwAMAAkK7iBlDQA1AwAAAA==.Caroll:BAAANQADCgMIAwAAAA==.Caçaorda:BAAANQAECgMJBAAAAA==.',
Ce='Cecilith:BAABNQAECoElAAINAAkK2SA6EQBRAwANAAkK2SA6EQBRAwAAAA==.Cernûnnos:BAAANQAECgUIDQAAAA==.',
Ch='Champdude:BAABNQAECoEdAAMOAAgKGR9DFACRAgAOAAcK1yBDFACRAgADAAEKQgcRRgAvAAAAAA==.Chopquatro:BAAANQADCggICAAAAA==.Chrnnos:BAAANQAECgQIBQAAAA==.',
Co='Corineus:BAAANQADCgYIBgAAAA==.Cowzeroth:BAABNQAECoEbAAINAAcK5RpHSAApAgANAAcK5RpHSAApAgAAAA==.',
Cr='Crassustitan:BAAANQAECgYIDQAAAA==.Cristcalad:BAAANQAECgUICwAAAA==.',
Da='Daemi:BAAANQAECgcIDQAAAA==.Dalaty:BAAANQADCgIJAgAAAA==.Daresh:BAAANQADCgEJAQAAAA==.Dariok:BAAANQAECgUIDQAAAA==.Darkove:BAABNQAECoEkAAIPAAgK6BLOCgDlAQAPAAgK6BLOCgDlAQAAAA==.Darrow:BAABNQAECoEcAAIQAAgKQRCENQDGAQAQAAgKQRCENQDGAQAAAA==.Daryan:BAAANQAECgYICAAAAA==.Day:BAAANQAECgQIBAAAAA==.',
De='Deathinhu:BAABNQAECoEkAAIRAAgKOiEpPgD7AgARAAgKOiEpPgD7AgAAAA==.Demoriana:BAAANQAECgMIAwAAAA==.Dethroned:BAAANQAECgQICgAAAA==.',
Di='Dimeros:BAABNQAECoEiAAISAAgKcwmJSwCMAQASAAgKcwmJSwCMAQAAAA==.Divano:BAABNQAECoEkAAIBAAkKvx7cCQAvAwABAAkKvx7cCQAvAwAAAA==.',
Dk='Dkats:BAAANQADCgQIBAAAAA==.Dkhalifa:BAAANQADCgYIBgAAAA==.',
Do='Dogowner:BAAANQADCgcICAAAAA==.Donora:BAAANQAECgQIBAAAAA==.Dorfillaw:BAAANQAECgUICQAAAA==.Dorvana:BAAANQADCgMJAwABNQAECggIKQAGAPUkAA==.',
Dr='Dracthyrius:BAAANQAECgEIAQAAAA==.Dragonstyle:BAAANQAECgcICwAAAA==.Dragony:BAAANQADCgQIBAAAAA==.Dreez:BAAANQAECgQIBgAAAA==.Drexus:BAAANQADCgMIAwAAAA==.Drigolas:BAAANQADCgYIBgAAAA==.',
Eh='Ehomi:BAAANQADCgIIAgAAAA==.',
Ei='Eirin:BAAANQAECgQIDwAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Ellvarg:BAAANQADCgYIDAAAAA==.Eluuria:BAAANQAECggIDQAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.Ennafaryn:BAAANQABCgQIBAAAAA==.Ensabanú:BAAANQADCgQIBAAAAA==.',
Er='Erilaethaen:BAAANQAECgIIAgAAAA==.Erlek:BAAANQADCgUICwAAAA==.Ernest:BAABNQAECoEgAAITAAgK/R4qDgDSAgATAAgK/R4qDgDSAgAAAA==.Erulan:BAAANQADCgQIBwAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAABNQAECoEWAAIMAAgKEBGGRQDEAQAMAAgKEBGGRQDEAQAAAA==.Etubrutus:BAAANQADCgUIBAAAAA==.',
Ev='Evangelouco:BAAANQADCgQIBAAAAA==.Evilbarba:BAABNQAECoEWAAIGAAgKSBhabgAlAgAGAAgKSBhabgAlAgAAAA==.',
Ex='Exort:BAAANQAECgQICAAAAA==.Exothus:BAAANQAECgQJBwAAAA==.',
Fa='Faldark:BAAANQADCgUIBQAAAA==.Faranir:BAAANQADCggIEAAAAA==.Faris:BAABNQAECoEcAAMUAAcKNxR7NwC6AQAUAAYK0xV7NwC6AQAVAAcK6wzwIQCnAQAAAA==.Faver:BAAANQADCgMIAwAAAA==.Faölin:BAABNQAECoEZAAIVAAgKLhSfEwA8AgAVAAgKLhSfEwA8AgAAAA==.',
Fe='Ferael:BAABNQAECoEkAAMGAAgKqhqVUgB1AgAGAAgKqhqVUgB1AgACAAQK0g3NRQCvAAAAAA==.Ferrus:BAAANQAECgQIAwAAAA==.',
Fl='Flavors:BAABNQAECoEaAAIJAAgKTCD8MgDfAgAJAAgKTCD8MgDfAgAAAA==.Florbela:BAAANQAECgYIDgAAAA==.',
Fr='Fredericc:BAAANQAECgQIBAAAAA==.Freecs:BAAANQAECgEJAQABNQAECgIIAwAHAAAAAA==.Freyá:BAABNQAECoEbAAMCAAcKKBy9FQArAgACAAcKBxy9FQArAgAGAAUKFhLo1wAxAQAAAA==.Frostburn:BAAANQAECgYIDQAAAA==.Froststriker:BAAANQAECgEIAQAAAA==.',
Fu='Fulvo:BAAANQADCgQIBQAAAA==.',
Ga='Gadodamorena:BAAANQAECgEIAQAAAA==.Galfur:BAABNQAECoEZAAISAAUKGQZOdQDMAAASAAUKGQZOdQDMAAAAAA==.Galhuda:BAAANQADCgcICgAAAA==.Galica:BAAANQADCgIIAgAAAA==.',
Ge='Geisty:BAAANQAECgEIAQABNQAECgIIBAAHAAAAAA==.',
Gl='Glutotwo:BAAANQADCgYIEgAAAA==.',
Go='Goldchain:BAAANQAECgEIAgAAAA==.Govers:BAAANQAECgEIAQABNQAECgYICgAHAAAAAA==.',
Gr='Grumax:BAABNQAECoEYAAIGAAcKdAyNtwB2AQAGAAcKdAyNtwB2AQAAAA==.',
Gu='Gudeath:BAABNQAECoEiAAIJAAcKWxYHiwDaAQAJAAcKWxYHiwDaAQAAAA==.Guerrerinhow:BAAANQADCggIHgABNQAECgYIDwAHAAAAAA==.Guitianki:BAAANQADCgYIBgAAAA==.Gulek:BAAANQAECgYICQAAAA==.Gussg:BAAANQAECgUIEAAAAA==.',
['Gà']='Gàladriel:BAAANQAECgIIAgAAAA==.',
['Gö']='Göhan:BAAANQAECgEIAQAAAA==.',
['Gø']='Gøvers:BAAANQAECgYICgAAAA==.',
['Gü']='Güttz:BAABNQAECoEcAAIEAAgK0g/LMwDbAQAEAAgK0g/LMwDbAQAAAA==.',
Ha='Hagires:BAAANQAECgYIBwAAAA==.Hanaluna:BAAANQADCggICAAAAA==.Harchus:BAAANQADCgYIDwAAAA==.Hargarthul:BAAANQADCgMIBAAAAA==.Hazell:BAAANQADCggIDQAAAA==.',
He='Hellspont:BAAANQAECgUIDgAAAA==.Hendrikison:BAAANQADCgcIDQAAAA==.',
Ho='Horagalles:BAAANQADCgIIAgAAAA==.Hotmojo:BAABNQAECoE0AAIRAAkK6CB+JwA5AwARAAkK6CB+JwA5AwAAAA==.',
Hu='Hunfox:BAABNQAECoErAAILAAgKAyPUGgAUAwALAAgKAyPUGgAUAwAAAA==.Hunterhearst:BAAANQADCgYIBwAAAA==.',
Hy='Hylana:BAAANQADCgEIAQAAAA==.',
['Hö']='Hölycrüsh:BAABNQAECoEoAAIGAAgKiyBHPgC1AgAGAAgKiyBHPgC1AgAAAA==.',
Ik='Ikoo:BAAANQAECgYJDAAAAA==.',
Il='Illaril:BAACNQAFFIEOAAIWAAUKRQvTAQAhAQAWAAUKRQvTAQAhAQA1AAQKgSoAAhYACQqaGEEHAGoCABYACQqaGEEHAGoCAAAA.',
In='Interestelar:BAAANQADCgYIBgAAAA==.Invisiblelol:BAAANQAECgUICgAAAA==.',
Ir='Irmãodouther:BAAANQAECgUJBQAAAA==.Irridan:BAAANQADCgQIBQAAAA==.',
Is='Isenhearth:BAAANQABCgUIBQAAAA==.Ishtarie:BAAANQAECgYIDwAAAA==.',
It='Itokeszdan:BAAANQADCgYIBAAAAA==.',
Iv='Ivina:BAABNQAECoEwAAMXAAkKGBrHPACBAgAXAAkKGBrHPACBAgAYAAEKjwbdLgAsAAAAAA==.',
Iz='Izaar:BAAANQADCggIEAAAAA==.',
Ja='Jangeoffry:BAAANQABCgMIAwAAAA==.',
Jh='Jhonatinha:BAAANQAECgUIBwAAAA==.',
Jk='Jks:BAAANQADCggIDgAAAA==.',
Ju='Jullianxd:BAAANQAECgQIBwAAAA==.',
Ka='Kaallew:BAAANQAECggIDAAAAA==.Kaallmonge:BAAANQABCgcIBwAAAA==.Kaelonidas:BAAANQAECgQICwAAAA==.Kaelyaa:BAAANQADCgUIBQAAAA==.Kainer:BAAANQADCgYICQAAAA==.Kalazshar:BAABNQAECoEWAAIIAAgKQwrKIABNAQAIAAgKQwrKIABNAQAAAA==.Kalduran:BAAANQADCggIPQAAAA==.Kaluss:BAABNQAECoEaAAIRAAgKEgkY0gC8AQARAAgKEgkY0gC8AQAAAA==.Kanduz:BAAANQADCggIDgAAAA==.Kantaa:BAAANQADCggIJQAAAA==.Karmabb:BAAANQAECgUICgAAAA==.Kauss:BAAANQAECgIJAgAAAA==.Kavartu:BAABNQAECoEkAAINAAkKyxYkOABvAgANAAkKyxYkOABvAgAAAA==.Kayli:BAAANQADCgcIDgAAAA==.Kaysa:BAAANQADCggIDQAAAA==.',
Ke='Keillor:BAABNQAECoEVAAMZAAYKzwgpnwALAQAZAAYKzwgpnwALAQANAAQKXwUe2wCoAAAAAA==.Keldorian:BAAANQADCgQIBAAAAA==.Kenzou:BAAANQAECgUIEAAAAA==.Keytymari:BAAANQAECgUIBgAAAA==.',
Kh='Khaliq:BAAANQAECgYIEQAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIBAAHAAAAAA==.',
Ki='Kieran:BAAANQADCgYIBgAAAA==.Kimashi:BAAANQAECgEIAgAAAA==.Kissme:BAABNQAECoEcAAMTAAgK8w5wLgBxAQATAAcKxQ1wLgBxAQASAAYKTQ1TWQBFAQAAAA==.Kitamor:BAABNQAECoEjAAMSAAgKFgZAWgBAAQASAAgKrQRAWgBAAQAIAAMKhAgcPwBtAAAAAA==.',
Kl='Kletian:BAAANQADCggICAAAAA==.',
Ko='Koriakin:BAAANQADCggIGQAAAA==.Korogth:BAAANQADCggICQAAAA==.Kosmo:BAAANQAECgYIDwAAAA==.',
Kr='Krosmu:BAAANQABCgMIAwAAAA==.Kräsus:BAAANQADCgQIBAABNQAECggIHwAaAGkfAA==.',
Ku='Kurado:BAAANQAECgIIAgAAAA==.',
Ky='Kyrïn:BAAANQADCgUIBQABNQAFFAUIBwAUALMZAA==.',
Kz='Kzinn:BAAANQAECgEIAQAAAA==.',
['Kö']='Körn:BAAANQAECgQIBAABNQAECggIFQAZADETAA==.',
La='Ladyrichter:BAAANQABCgUIBgAAAA==.Laetus:BAAANQAECgcIEgAAAA==.Lagerthaloth:BAAANQADCgUIBAAAAA==.Laiander:BAAANQAECgUICgAAAA==.Laiany:BAABNQAECoEhAAIFAAgKmCGYGgDyAgAFAAgKmCGYGgDyAgAAAA==.Lainarning:BAAANQAECgEIAQAAAA==.Lani:BAAANQAECgIIAQAAAA==.',
Le='Leeoncamillo:BAAANQADCgMIAwABNQAECgMIAwAHAAAAAA==.Leetohro:BAAANQAECgQICAAAAA==.Leodoros:BAABNQAECoEcAAIRAAYKWApGEQFJAQARAAYKWApGEQFJAQAAAA==.',
Li='Lichkíng:BAAANQAECgQIBgAAAA==.Lighty:BAAANQADCgQICAAAAA==.Lijiang:BAABNQAECoEfAAIaAAgKaR9EBgDPAgAaAAgKaR9EBgDPAgAAAA==.Lilianpotter:BAAANQADCgYIBgAAAA==.Lilibel:BAAANQAECgEIAwAAAA==.Lindaah:BAAANQADCggILAAAAA==.Lindapriesty:BAAANQADCgIIAgAAAA==.Lislfox:BAABNQAECoEZAAIIAAcKWR49DQBTAgAIAAcKWR49DQBTAgAAAA==.',
Ll='Lledritch:BAAANQADCgUIBQAAAA==.',
Lm='Lmmds:BAAANQADCgYIBgAAAA==.',
Lo='Lockdown:BAABNQAECoEkAAIXAAgKRBImZQAGAgAXAAgKRBImZQAGAgAAAA==.Loukou:BAAANQADCggIGAAAAA==.',
Lu='Luacs:BAABNQAECoEVAAQZAAgKMRNOVwDeAQAZAAgKMRNOVwDeAQAbAAUKnBJ8HABjAQANAAIKfgms8QBuAAAAAA==.Luccoa:BAAANQADCgMIAwABNQAECggIHwAaAGkfAA==.Lucileia:BAAANQADCgcIBwAAAA==.Lucyfary:BAAANQADCgcICAAAAA==.Luhhrogue:BAAANQAECgMIAwAAAA==.Lunirah:BAAANQADCgYICAAAAA==.',
Ly='Lylka:BAABNQAECoEdAAMCAAgK9x4sDQCnAgACAAgK9x4sDQCnAgAcAAMKQiKfmwAlAQAAAA==.',
['Lé']='Léofar:BAAANQAECgQICwAAAA==.',
['Lü']='Lücyfer:BAAANQAECgMIAwAAAA==.',
Ma='Maanu:BAAANQADCgUIBQABNQADCggILAAHAAAAAA==.Maeghann:BAAANQADCgQIAwAAAA==.Magostosaa:BAAANQABCgIIAgAAAA==.Makani:BAAANQAECgEIAgAAAA==.Malewolyyc:BAABNQAECoEhAAMFAAkKNRxGGwDuAgAFAAkKNRxGGwDuAgABAAQK+A0VRwDZAAAAAA==.Massafera:BAAANQAECgYIEQAAAA==.Mathfacbruxo:BAAANQADCgYJBgABNQAECggIGQALAPwYAA==.Mathfacii:BAABNQAECoEZAAILAAgK/BjuPgCJAgALAAgK/BjuPgCJAgAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Mc='Mcq:BAAANQAECgEIAQAAAA==.',
Md='Mdrdark:BAABNQAECoEhAAIdAAgKkR1LMwA7AgAdAAgKkR1LMwA7AgAAAA==.',
Me='Medz:BAAANQAECgYIEQAAAA==.Meetjack:BAAANQAECgEIAQAAAA==.Meizu:BAAANQAECgQJDAAAAA==.Mellkor:BAAANQAECgcIEwAAAA==.Meneláu:BAAANQADCggICAAAAA==.Metamorful:BAAANQAECggIDgAAAA==.',
Mi='Milim:BAAANQAECgcIDAAAAA==.Minilock:BAAANQAECgQIBQAAAA==.Mistogunn:BAAANQADCggICAAAAA==.',
Ml='Mls:BAAANQADCgUIBQAAAA==.',
Mm='Mmarcão:BAAANQABCgMIAwAAAA==.',
Mo='Modes:BAAANQAECgYIEAAAAA==.Moffir:BAAANQADCgYIBgAAAA==.Mogrus:BAAANQADCgUIAgAAAA==.Mohotok:BAAANQAECgcIEQAAAA==.Monshiro:BAAANQAECgEIAQABNQAECgIIAwAHAAAAAA==.Morkath:BAAANQADCggICAAAAA==.Mortixxia:BAAANQAECgYIEQAAAA==.',
Mu='Murano:BAABNQAECoEgAAIKAAkKYxUPCABAAgAKAAkKYxUPCABAAgAAAA==.',
['Má']='Máia:BAAANQAECgQIBwAAAA==.',
['Mä']='Mändosz:BAAANQAECgYIDgAAAA==.',
['Mé']='Ménace:BAAANQAECgMIAgABNQAECgYIDQAHAAAAAA==.',
['Mø']='Mørgane:BAAANQADCggIFgAAAA==.',
['Mÿ']='Mÿstyna:BAAANQADCgUJCQAAAA==.',
Na='Nagts:BAAANQADCggICgAAAA==.Nalathiel:BAAANQAECgUIBQAAAA==.Narancia:BAAANQAECgIIAwAAAA==.Narrih:BAAANQAECgIIBAAAAA==.Nazzh:BAAANQAECggIDAAAAA==.',
Ne='Nefas:BAAANQAECgcICwAAAA==.Nepthunus:BAAANQAECgcIEgAAAA==.',
No='Notforall:BAAANQADCgIIAgAAAA==.',
['Nö']='Nöirr:BAAANQABCgUIBAAAAA==.',
Od='Odestruidor:BAAANQAECgUIBwAAAA==.',
Ol='Oluss:BAABNQAECoEdAAMcAAgKVQ3uYwDGAQAcAAgKVQ3uYwDGAQAGAAEKtwdvcwE1AAABNQAECggIKwALAAMjAA==.',
On='Onys:BAAANQADCgIIAgAAAA==.',
Op='Opus:BAAANQAECgcIEQAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Origon:BAAANQADCggICwAAAA==.Orillan:BAABNQAECoEZAAIEAAcKhw5+PQCYAQAEAAcKhw5+PQCYAQAAAA==.Orsonn:BAAANQAECgQIBQAAAA==.Orucão:BAAANQABCgEIAQAAAA==.Oruism:BAAANQABCgQIBAAAAA==.Orukam:BAAANQAECgYIEAAAAA==.Orukanorum:BAAANQADCgcIAwAAAA==.Orukrente:BAAANQABCgIIAgAAAA==.Orulord:BAAANQABCgIIAwAAAA==.Orurage:BAAANQABCgYIBAAAAA==.',
Pa='Palaha:BAAANQAECgQIBAABNQAECggIKwALAAMjAA==.Palatina:BAABNQAECoEYAAIGAAcK9h8FUQB5AgAGAAcK9h8FUQB5AgABNQAECggIKQAGAPUkAA==.Pandalokodj:BAAANQAECgEIAQAAAA==.Pangedrey:BAABNQAECoEeAAMOAAgKNxk7GQBPAgAOAAgKNxk7GQBPAgADAAEKRxULQwA9AAAAAA==.Parký:BAAANQAECgcIDQAAAA==.Paullk:BAAANQADCgIIAgAAAA==.',
Pe='Penseur:BAAANQABCgYJBgAAAA==.Peruchi:BAAANQADCgIIAgAAAA==.Perísdra:BAAANQADCgcIDQABNQAECgMIBQAHAAAAAA==.',
Pg='Pgms:BAAANQADCggICAAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pitombinha:BAABNQAECoEVAAMKAAgKrxidCwDkAQAKAAYKshqdCwDkAQAJAAQKiROh2QACAQAAAA==.Pixiks:BAAANQABCgYIBwAAAA==.',
Pp='Ppandora:BAAANQADCgUICgAAAA==.',
Pr='Predadore:BAAANQADCgUIBQAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pä']='Pändero:BAAANQABCgMIAwAAAA==.',
['Pî']='Pîo:BAABNQAECoEoAAIRAAkKwyF1KAA2AwARAAkKwyF1KAA2AwAAAA==.',
Qu='Quirow:BAABNQAECoEcAAINAAcKsA4MdQCRAQANAAcKsA4MdQCRAQAAAA==.',
Ra='Radiação:BAAANQAECgMIAwAAAA==.Radunz:BAABNQAECoEfAAIeAAgKTx2lBwC0AgAeAAgKTx2lBwC0AgAAAA==.Ragnaros:BAAANQAECgQIBQAAAA==.Ragnarssön:BAAANQADCgEIAQAAAA==.Ragnarøk:BAAANQABCggICAAAAA==.Raio:BAABNQAECoEgAAIRAAcKfx1miABUAgARAAcKfx1miABUAgAAAA==.Ramorey:BAAANQADCgQIBgAAAA==.Ranruulfnarm:BAAANQABCgQICAAAAA==.Rargsa:BAAANQAECgIIAwAAAA==.Rargul:BAAANQAECgEIAQAAAA==.Rariel:BAAANQAECgQICAAAAA==.Raymain:BAABNQAECoEeAAMDAAgKAxksFgDqAQADAAcKaRcsFgDqAQAOAAcKIxnuIgDiAQAAAA==.Raíka:BAAANQADCggIDQAAAA==.',
Re='Rebimboca:BAAANQAECgEIAQAAAA==.Redoon:BAAANQADCgQIBQAAAA==.Rendoras:BAAANQAECgEIAQAAAA==.Rezadeiro:BAAANQADCgUIBAAAAA==.',
Rh='Rhaumarhu:BAAANQADCgYIBgAAAA==.',
Ro='Rockit:BAAANQADCgMICAAAAA==.Rodbree:BAABNQAECoEbAAMcAAkK2x3nEgAoAwAcAAkK2x3nEgAoAwAGAAIKzQ/LQQFyAAAAAA==.Roguinhu:BAAANQAECgIIBAAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rurumo:BAAANQAECgEJAQAAAA==.Rustovick:BAAANQAECgEIAQAAAA==.',
['Rå']='Råy:BAABNQAECoEjAAMdAAgKXB8MKwBoAgAdAAgKXB8MKwBoAgAQAAEKkg4VkQA4AAAAAA==.',
Sa='Saffír:BAAANQAECgYIDwAAAA==.Samalandraa:BAAANQAECgQIBAAAAA==.Saniest:BAAANQAECgYIEQAAAA==.Sapekinhä:BAAANQAECgQIDQAAAA==.Satanvitória:BAAANQAECgYIEAAAAA==.',
Se='Segavaxx:BAAANQABCgQIBAAAAA==.Seilaa:BAAANQABCgIIAgAAAA==.Selorixie:BAAANQAECgMIBAABNQAECgYIEQAHAAAAAA==.Sereiaa:BAAANQAECgQIBwAAAA==.',
Sh='Shamate:BAAANQADCgQJBAAAAA==.Shanoa:BAAANQAECgMIBQAAAA==.Sharae:BAAANQADCggIDQAAAA==.Shedo:BAAANQAECgcIEQAAAA==.Shonja:BAAANQADCgIJAwAAAA==.',
Si='Sialeeds:BAAANQADCgMIAwAAAA==.Siclop:BAAANQAECgIIAgAAAA==.Simplicity:BAAANQAECgcIEQAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadrian:BAAANQADCgQIBgAAAA==.Skadryan:BAAANQADCgYIDAAAAA==.Skalnark:BAAANQADCgUIBQAAAA==.Skinme:BAAANQAECgEIAQAAAA==.Skysoul:BAAANQAECgEJAgAAAA==.',
So='Sofiela:BAAANQAECgIIAgAAAA==.Soijiro:BAAANQADCgIIAgAAAA==.Soju:BAAANQADCgIIAgAAAA==.Sombrea:BAAANQADCgYICwAAAA==.',
Sp='Spectrø:BAAANQADCgcIFAAAAA==.Sperber:BAABNQAECoEXAAIGAAYKnyQ8UAB8AgAGAAYKnyQ8UAB8AgAAAA==.',
Ss='Sstrange:BAAANQADCgcIBwAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stëlla:BAAANQAECgcIEwAAAA==.',
Su='Suckmyhammer:BAAANQAECgEIAgAAAA==.Sungjinwoo:BAAANQAECgYIDwAAAA==.Sunnara:BAABNQAECoEYAAIfAAkKyxmMFACrAgAfAAkKyxmMFACrAgAAAA==.',
Sy='Syuon:BAABNQAECoEkAAIDAAkKVCRXAQCwAwADAAkKVCRXAQCwAwAAAA==.',
Ta='Talandar:BAABNQAECoEkAAISAAgKYxcsLgBIAgASAAgKYxcsLgBIAgAAAA==.Tankudo:BAABNQAECoEYAAIdAAcKXxZbSgDFAQAdAAcKXxZbSgDFAQAAAA==.',
Te='Tennebra:BAAANQADCggICQAAAA==.',
Th='Thabitah:BAABNQAECoEgAAIBAAgKUxAKJADpAQABAAgKUxAKJADpAQAAAA==.Thanathus:BAAANQADCggIKQAAAA==.Thaumiel:BAAANQADCgEIAQAAAA==.Thedragon:BAAANQAECggIDwAAAA==.Thorkel:BAAANQADCgYIBwAAAA==.Thotamon:BAAANQADCgYICgAAAA==.',
Ti='Tidim:BAAANQADCgYIBgAAAA==.Tiih:BAAANQABCgUIBQAAAA==.',
To='Tonypaludo:BAAANQAECgEIAQAAAA==.',
Us='Usfull:BAABNQAECoEZAAMFAAcKgRr2TQASAgAFAAcKgRr2TQASAgABAAIK7gYFXwBaAAAAAA==.',
Va='Vaatu:BAAANQADCgMIBAAAAA==.Vallkÿria:BAAANQAECgQIAwAAAA==.Varrex:BAAANQADCgEIAQAAAA==.Vaëllen:BAAANQAECgYIDAAAAA==.',
Ve='Vehuiáh:BAAANQAECgcIDAAAAA==.Velen:BAABNQAECoEjAAIdAAgKAR8dIgCeAgAdAAgKAR8dIgCeAgAAAA==.Verno:BAAANQAECgIIAgAAAA==.Verzuk:BAAANQAECgQIBgAAAA==.',
Vi='Vintejulgar:BAAANQABCggICQAAAA==.Vintekilo:BAABNQAECoEYAAIGAAcKCg+sqQCUAQAGAAcKCg+sqQCUAQAAAA==.Vinteservir:BAAANQABCgQIBAAAAA==.',
Vo='Voiddh:BAABNQAECoEaAAIfAAkKbw6IJgDxAQAfAAkKbw6IJgDxAQAAAA==.',
Vr='Vrenshrrgn:BAAANQAECgIIAgAAAA==.',
Vy='Vygh:BAABNQAECoEeAAMXAAcK0R59QAB1AgAXAAcK0R59QAB1AgAgAAEKuAshcgA2AAAAAA==.Vyndrill:BAABNQAECoEaAAIVAAcK6hHGHADZAQAVAAcK6hHGHADZAQAAAA==.',
Wa='Walkers:BAABNQAECoEZAAILAAkKDBSWSwBkAgALAAkKDBSWSwBkAgAAAA==.Warlaka:BAAANQADCgUICgAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.',
Xa='Xalmoria:BAAANQAECgUIBgAAAA==.',
Xu='Xurumeloun:BAAANQADCgYIBgAAAA==.',
Ya='Yamii:BAAANQAECgQIBgAAAA==.Yasmini:BAAANQABCgEIAQAAAA==.',
Yi='Yingsu:BAAANQAECgYIEAAAAA==.Yippwarr:BAAANQADCgMIBAAAAA==.',
Yu='Yunná:BAAANQADCgQICAAAAA==.',
Yv='Yvin:BAAANQAECgIIAgAAAA==.',
Za='Zakir:BAAANQAECgEIBAAAAA==.Zaolron:BAAANQADCgIIAQAAAA==.',
Ze='Zeddshm:BAAANQAECgEJAQABNQAECgQIBAAHAAAAAA==.Zeeno:BAAANQADCggICwAAAA==.',
Zh='Zhynah:BAAANQADCgUIBQAAAA==.',
Zi='Ziracruz:BAAANQAECgQICAAAAA==.',
Zu='Zulyn:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrdath:BAAANQADCggIDgAAAA==.Àrthemís:BAAANQADCgEIAQAAAA==.',
['Ár']='Áraujo:BAAANQADCgEJAQABNQADCgUIBQAHAAAAAA==.Árÿä:BAABNQAECoEdAAILAAgKRwu8dgD0AQALAAgKRwu8dgD0AQAAAA==.',
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
