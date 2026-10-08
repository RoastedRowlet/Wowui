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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Warlock-Destruction','Hunter-Marksmanship','Warrior-Fury','Warrior-Arms','Druid-Balance','Paladin-Holy','Shaman-Restoration','Warrior-Protection','Mage-Arcane','Hunter-Survival','Paladin-Retribution','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','Monk-Windwalker','Paladin-Protection','Shaman-Elemental','Druid-Guardian','DeathKnight-Frost','Mage-Fire','Warlock-Demonology','Shaman-Enhancement','DemonHunter-Havoc','Druid-Restoration',}
local provider = {region='US',realm='SteamwheedleCartel',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aalwein:BAAANQAECgYIEgAAAA==.',
Ad='Adehn:BAAANQADCgEIAQAAAA==.',
Al='Alfrus:BAAANQADCggICQAAAA==.',
Am='Amarii:BAAANQAECgUIDQAAAA==.',
An='Andent:BAAANQABCgYICAABNQADCggIEgABAAAAAA==.',
Ap='Appostle:BAAANQADCgYICgAAAA==.',
Ar='Ara:BAABNQAECoEiAAICAAkKoBnDMQC1AgACAAkKoBnDMQC1AgAAAA==.',
As='Asteryn:BAAANQAECgIIAwAAAA==.',
Av='Avigar:BAAANQAECgUIBgAAAA==.',
Ba='Bangan:BAAANQAECgEIAQAAAA==.Banisary:BAAANQADCgYIBgAAAA==.',
Be='Belakor:BAAANQAECgMIAwAAAA==.Bep:BAAANQAECgEIAQABNQAECgkJIAADAKQTAA==.Bepragosa:BAABNQAECoEgAAIDAAkKpBPcBwB4AgADAAkKpBPcBwB4AgAAAA==.',
Bi='Binpharteen:BAAANQADCgcICwAAAA==.Birgitè:BAAANQADCgYIBwAAAA==.',
Bl='Blaque:BAAANQAECgYIDwAAAA==.',
Bo='Bowguytome:BAABNQAFFIEFAAIEAAUK+CU9AwA3AgAEAAUK+CU9AwA3AgAAAA==.',
Br='Brownbelt:BAABNQAECoEZAAMFAAcKtA4RDwCXAQAFAAcKtA4RDwCXAQAGAAUK8QPQ9wC9AAAAAA==.Brîn:BAAANQAECgUICgAAAA==.',
Bu='Buteihunter:BAAANQAECgcIEwAAAA==.Butherts:BAAANQAECggIDAAAAA==.',
Ch='Chelali:BAABNQAECoEhAAIGAAcKpxvbeQAIAgAGAAcKpxvbeQAIAgAAAA==.Chicharrone:BAABNQAECoEgAAIHAAcKbQf5WQBBAQAHAAcKbQf5WQBBAQAAAA==.Chizaru:BAABNQAECoEfAAIIAAgK3B4oIgDNAgAIAAgK3B4oIgDNAgAAAA==.Chlorophyll:BAAANQADCggICAAAAA==.Chyntobelt:BAAANQAECgQIBwABNQAECgcIGQAFALQOAA==.',
Cr='Cryption:BAAANQAECgcIDgAAAA==.',
Da='Daelyn:BAAANQADCgQIBAAAAA==.',
De='Deafenned:BAAANQADCggIDQAAAA==.Deafnight:BAAANQADCggIDAABNQADCggIDQABAAAAAA==.Deliquesce:BAAANQADCggICgAAAA==.',
Di='Diamante:BAABNQAECoElAAIJAAgKjxhuQQAwAgAJAAgKjxhuQQAwAgAAAA==.Dignifeyed:BAAANQADCgcIBwAAAA==.Discoelsi:BAAANQAECgMIAwAAAA==.',
Dr='Dracarnoir:BAAANQADCgcIDQAAAA==.Dragonite:BAABNQAECoEjAAMGAAgKXSRRGwA+AwAGAAgKXSRRGwA+AwAKAAMK2xGWLQCYAAAAAA==.Dremu:BAABNQAECoEaAAIHAAcKYx9jJwB4AgAHAAcKYx9jJwB4AgAAAA==.',
Du='Duskhunter:BAAANQAECgUICgAAAA==.',
Dy='Dysraxis:BAAANQABCggICgAAAA==.',
['Dï']='Dïnhö:BAAANQAECgEIAQAAAA==.',
El='Elahna:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Elamaun:BAABNQAECoEXAAIIAAcKWRLEaAC3AQAIAAcKWRLEaAC3AQAAAA==.Eltiana:BAABNQAECoEdAAILAAcK2gqd6QCQAQALAAcK2gqd6QCQAQAAAA==.',
Em='Emisa:BAAANQADCgIIAgAAAA==.',
Ep='Ephex:BAAANQADCgUIBAAAAA==.Ephriest:BAAANQADCgMIBAABNQAECgYIDgABAAAAAA==.Ephury:BAAANQAECgYIDgAAAA==.Epic:BAAANQADCgIIAgAAAA==.',
Fa='Faelyna:BAABNQAECoEZAAIMAAcKQQ6NBwDJAQAMAAcKQQ6NBwDJAQAAAA==.',
Fe='Fearbear:BAAANQADCgUJAwAAAA==.',
Fo='Forged:BAABNQAECoEpAAINAAkKCSTREAB2AwANAAkKCSTREAB2AwAAAA==.',
Fu='Fufufu:BAAANQADCgQIBAABNQAECggIJQAJAI8YAA==.',
Gi='Githyanki:BAAANQADCgUICQAAAA==.',
Go='Goop:BAAANQADCgUIBQABNQAECgkJIAAOAC0jAA==.',
Gr='Grangshammy:BAAANQAECgQICwAAAA==.Grimskull:BAAANQADCgMIAwAAAA==.Grimvault:BAAANQAECgEIAQABNQAECgUIEwABAAAAAA==.',
Ha='Hacelian:BAAANQADCgYIBgAAAA==.Han:BAABNQAECoEgAAMPAAkKLBTJIQBKAgAPAAkKBRTJIQBKAgAQAAYK3AzYLAA+AQAAAA==.Hargoroth:BAAANQADCggICwAAAA==.',
He='Henudorf:BAAANQAECgUIBwAAAA==.',
Ho='Holyverdict:BAAANQADCgQIAwAAAA==.',
Ic='Icaina:BAABNQAECoEiAAIJAAgKhSEkGwDnAgAJAAgKhSEkGwDnAgAAAA==.',
In='Infernnape:BAAANQAECgEIAgAAAA==.',
Ja='Jakana:BAAANQADCgcIBwAAAA==.Jathy:BAAANQADCgQIBAAAAA==.',
Je='Jeisa:BAAANQAECgUIEQAAAA==.',
Jh='Jhedu:BAAANQADCgcJBwAAAA==.',
Ju='Juanns:BAAANQADCgcJBwAAAA==.',
Ka='Kaj:BAABNQAECoEdAAIIAAcKIRTYYgDLAQAIAAcKIRTYYgDLAQAAAA==.Kallotera:BAAANQADCggICAAAAA==.Kalrou:BAAANQADCgUIBQABNQAECgkJIgARALohAA==.Kastoria:BAAANQADCgUIBQAAAA==.Katnipp:BAAANQAECgcIEgAAAA==.Kaylazune:BAAANQAECgUIDgAAAA==.',
Kh='Kharybdis:BAAANQAECgEIAQAAAA==.Khrala:BAAANQAECgQICwAAAA==.',
Ki='Kindlana:BAAANQADCggICAAAAA==.Kiye:BAACNQAFFIENAAICAAUKrhXSBgC5AQACAAUKrhXSBgC5AQA1AAQKgS0AAgIACQotIxITADwDAAIACQotIxITADwDAAAA.',
Ku='Kushan:BAAANQADCgEIAQAAAA==.Kuuro:BAAANQAECgUIEQAAAA==.',
La='Lattymag:BAAANQAECgUICQAAAA==.Laughystabby:BAAANQADCgcIDgAAAA==.',
Le='Leibniz:BAAANQAECgUIDgAAAA==.Leisa:BAAANQAECgUIEQAAAA==.Lelwindae:BAAANQAECgQIBwAAAA==.',
Li='Lifemoon:BAAANQADCgQIAQAAAA==.Lildangerus:BAAANQADCgYIDQAAAA==.Liminara:BAEBNQAECoEbAAINAAkKBg/HkADPAQANAAkKBg/HkADPAQABNQAFFAYIEAACAH0cAA==.Linaste:BAAANQAECgYIDAAAAA==.',
Lo='Lohha:BAAANQADCgIIAgAAAA==.',
Lu='Lulu:BAACNQAFFIEhAAISAAkKMCISAAC+AwASAAkKMCISAAC+AwA1AAQKgSQAAhIACQp2JlMCALIDABIACQp2JlMCALIDAAAA.Lumaria:BAAANQAECgQICAAAAA==.',
Ly='Lyllia:BAAANQAECgYIDgAAAA==.Lynoia:BAAANQADCggICAAAAA==.',
Ma='Makunel:BAAANQADCggICAAAAA==.Mandevu:BAAANQAECgEIAQAAAA==.Mangan:BAAANQAECgEJAwAAAA==.Manknus:BAABNQAECoEbAAIFAAcK1g4iDwCWAQAFAAcK1g4iDwCWAQAAAA==.Manthrax:BAABNQAECoEYAAIJAAgKrQgigABeAQAJAAgKrQgigABeAQAAAA==.Mathiyis:BAAANQABCgcICwABNQAECgQIBwABAAAAAA==.',
Me='Mexecutioner:BAABNQAECoEYAAIGAAcKNwzYqACKAQAGAAcKNwzYqACKAQAAAA==.',
Mi='Milkadin:BAAANQADCgIIAgAAAA==.Mirzan:BAAANQADCgEIAQAAAA==.Missmolt:BAAANQAECgYIEQAAAA==.',
Mo='Mogok:BAABNQAECoEVAAITAAYKVQppNQAQAQATAAYKVQppNQAQAQAAAA==.Molting:BAAANQAECgMJBwAAAA==.Moonkin:BAAANQABCgQIBQAAAA==.',
Mu='Musclegary:BAABNQAECoEoAAMUAAgKsyPXFQAxAwAUAAgKsyPXFQAxAwAJAAEK9Ro/+gBDAAAAAA==.',
My='Mykie:BAAANQADCggIDwAAAA==.Mylor:BAABNQAECoEfAAITAAcKrx2FEgBTAgATAAcKrx2FEgBTAgAAAA==.Myrddral:BAAANQAECgUIEAAAAA==.Mystifeyed:BAABNQAECoEdAAIVAAcKRA6+IABOAQAVAAcKRA6+IABOAQAAAA==.',
['Mü']='Mürsaat:BAAANQAECgYIDAAAAA==.',
Na='Nagrad:BAAANQAECgEIAQAAAA==.Namrekcah:BAAANQAECgEIAQABNQAFFAcIGwARAMcbAA==.',
Ni='Nilaya:BAAANQADCggICAAAAA==.Nimbledragon:BAAANQADCgYIDQAAAA==.',
Nt='Ntayu:BAAANQAECgUIEQAAAA==.',
Ol='Olizia:BAABNQAECoEZAAIWAAcKhxcsMADrAQAWAAcKhxcsMADrAQAAAA==.',
Op='Opex:BAABNQAECoEdAAICAAcKTg/YhADSAQACAAcKTg/YhADSAQAAAA==.',
Or='Oril:BAAANQADCgMIAwAAAA==.',
Os='Osairis:BAAANQADCgUIBQAAAA==.',
Ot='Otura:BAAANQADCgIIAgAAAA==.',
Pe='Perkyblade:BAABNQAECoEaAAMFAAYKGBHoEABxAQAFAAYKGBHoEABxAQAKAAIKhQW0NgBJAAAAAA==.',
Pl='Planeswalker:BAAANQADCggICQAAAA==.',
Po='Poxic:BAAANQAECgIJBAAAAA==.',
Pr='Protection:BAAANQABCgYIBgAAAA==.',
Ps='Psychotic:BAAANQADCgMIAwAAAA==.',
Ra='Ravinar:BAABNQAECoEZAAIXAAcKohr/AQAwAgAXAAcKohr/AQAwAgAAAA==.Razzle:BAABNQAECoEkAAIYAAkKhRQmQAB2AgAYAAkKhRQmQAB2AgAAAA==.Raàm:BAAANQADCgQIBAAAAA==.',
Re='Relia:BAAANQADCgMIAwAAAA==.',
Ri='Rizzstoned:BAAANQADCggIEwAAAA==.',
Ro='Romulus:BAAANQAECgUIEQAAAA==.',
Sa='Sarbarola:BAAANQADCgYIGwAAAA==.',
Se='Seraid:BAAANQADCggIFwAAAA==.',
Sh='Shallbedo:BAAANQAECgEIAQABNQAECgkJKAAZAIgSAA==.Shallmagi:BAAANQADCgUIBQABNQAECgkJKAAZAIgSAA==.Shmalexia:BAAANQABCgEJAQAAAA==.',
Si='Siatraler:BAAANQADCgUIBQAAAA==.Sigarette:BAACNQAFFIEbAAIRAAcKxxurAQB/AgARAAcKxxurAQB/AgA1AAQKgS0AAhEACQoXImQJAF8DABEACQoXImQJAF8DAAAA.Sinardi:BAABNQAECoEZAAIaAAcKcgudQgB1AQAaAAcKcgudQgB1AQAAAA==.',
Sk='Skymane:BAAANQAECgYIEAAAAA==.',
Sn='Snaggletooth:BAAANQADCgYIBgAAAA==.',
So='Soongxiao:BAAANQAECgQIBgAAAA==.Sorce:BAAANQADCgYIDAABNQAECggIJQAJAI8YAA==.Sovan:BAAANQADCgYIBgAAAA==.Sovix:BAAANQADCgYIBAAAAA==.Sovo:BAABNQAECoEWAAILAAgK6BB9owAbAgALAAgK6BB9owAbAgABNQAFFAUIEAAYAEMOAA==.',
Sp='Sprick:BAAANQADCgQIBQAAAA==.',
St='Steaknquake:BAABNQAECoEZAAIJAAcKMB8oNABpAgAJAAcKMB8oNABpAgAAAA==.',
Su='Sumdumfun:BAAANQADCgIIAgAAAA==.Sunflower:BAAANQAECgIIAgAAAA==.',
Sy='Sybri:BAABNQAECoEaAAICAAcKOB7aTABgAgACAAcKOB7aTABgAgAAAA==.Sylvandel:BAAANQAECgUIEAAAAA==.Sylvrshado:BAAANQADCgQIBAAAAA==.',
Sz='Szilvia:BAAANQAECgQIBAAAAA==.',
Ta='Talanthar:BAAANQAECgUIEwAAAA==.Talarrond:BAAANQAECgQIBAAAAA==.',
Te='Teagen:BAABNQAECoEZAAMbAAcKOQk8NgA1AQAbAAcKOQk8NgA1AQAHAAUKTgXBfACvAAAAAA==.Teilssra:BAAANQAECgQIBwAAAA==.',
Th='Thalius:BAAANQAECgUIDgAAAA==.Thamachine:BAAANQADCgMIAwAAAA==.Thebear:BAAANQADCgcICgAAAA==.Thóridal:BAAANQAECgIIAgAAAA==.',
To='Toomanydeths:BAABNQAECoEZAAIRAAcKnAvjXwBRAQARAAcKnAvjXwBRAQAAAA==.',
Tr='Trickledeath:BAAANQABCgIIAgAAAA==.Trunx:BAAANQAECgEIAQABNQAECgkJIAAOAC0jAA==.',
Tu='Tuminettlpot:BAAANQADCgYIBgAAAA==.',
Ud='Udaz:BAAANQADCgEIAQAAAA==.',
Un='Untz:BAAANQADCgYICgAAAA==.',
Ur='Ursusmanny:BAAANQADCgEIAQAAAA==.',
Va='Vanthrall:BAAANQAECgQIDQAAAA==.',
Ve='Velysa:BAAANQAECgYIEwAAAA==.',
Wa='Warseeker:BAABNQAECoEZAAIUAAcKUhUJWwDjAQAUAAcKUhUJWwDjAQAAAA==.',
We='Weatherworn:BAAANQAECgIIAwAAAA==.Wera:BAAANQAECgUJCQAAAA==.Weslow:BAAANQADCgMIAwAAAA==.',
Wo='Woodcrest:BAAANQADCgcIBwAAAA==.',
['Ës']='Ëscänör:BAAANQAECgUIDQAAAA==.',
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
