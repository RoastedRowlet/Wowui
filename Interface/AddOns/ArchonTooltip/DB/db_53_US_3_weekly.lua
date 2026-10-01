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

local lookup = {'Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Priest-Discipline','Warrior-Arms','Warrior-Fury','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Warlock-Demonology','Priest-Shadow','Mage-Arcane','DeathKnight-Blood','Priest-Holy','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','DeathKnight-Unholy','DeathKnight-Frost','Mage-Frost','Shaman-Elemental','Shaman-Restoration','DemonHunter-Havoc','Evoker-Augmentation','Monk-Brewmaster','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=53,date='2026-09-29',data={Ae='Aegrias:BAABNQAECoEXAAIBAAkKwx26KgDiAgABAAkKwx26KgDiAgAAAA==.Aerodria:BAABNQAECoEkAAICAAgKuRz2DQBxAgACAAgKuRz2DQBxAgAAAA==.',
Al='Alanril:BAAANQADCgMIAwAAAA==.Alarthevel:BAAANQAECgMIAwAAAA==.Albince:BAAANQADCgQIBAAAAA==.',
Am='Amellis:BAAANQADCgIIAgAAAA==.',
An='Andreaswar:BAAANQAECgMIAwAAAA==.Anniferal:BAAANQAECgMIBAABNQAFFAIIBAADAAAAAA==.Annisseda:BAAANQAFFAIIBAAAAA==.Anzak:BAAANQAECgQIBQAAAA==.',
Ar='Ardrayshock:BAAANQABCgcJCgAAAA==.Arrhythmia:BAAANQAECgIIAgABNQAFFAMIBgADAAAAAQ==.',
As='Astrayn:BAAANQADCgIIAgAAAA==.',
Az='Azala:BAAANQAECgIIAgAAAA==.Azryx:BAAANQADCgcICQABNQAECggIJwAEAD0XAA==.Azzy:BAACNQAFFIEKAAIFAAUKcAzdDAB7AQAFAAUKcAzdDAB7AQA1AAQKgTIAAwUACQq4JI0HAKgDAAUACQpeJI0HAKgDAAYACQonIe4BADsDAAAA.',
Ba='Bananski:BAAANQADCgcIBwAAAA==.',
Be='Bearpong:BAAANQAECggIAQABNQAECggIEAADAAAAAA==.Beefychunks:BAAANQAECgYIEgAAAA==.',
Bi='Bigdraco:BAAANQADCgQIBQAAAA==.Biggums:BAAANQADCgQIBAAAAA==.Billyspikepd:BAAANQAECgUIDAAAAA==.Billyspikepr:BAAANQADCggIDQABNQAECgUIDAADAAAAAA==.Billyspikerg:BAAANQADCggIEwABNQAECgUIDAADAAAAAA==.',
Bl='Black:BAAANQADCgEJAQAAAA==.Blobcat:BAAANQAECgcIDwAAAA==.Blobknight:BAAANQADCggIFwAAAA==.Bloodhase:BAAANQAECgYJDgAAAA==.Bluecard:BAAANQAFFAIIAgAAAA==.',
Bo='Bothenheim:BAAANQAFFAIIBAAAAA==.Bowdaddy:BAAANQAECgMIAwAAAA==.',
Br='Breakdown:BAAANQAECgQICAAAAA==.Brewsimmons:BAAANQADCggIEAABNQAFFAYIEQAHAMELAA==.',
Bu='Bublz:BAAANQADCgIIAgAAAA==.Bumpinuglies:BAAANQADCgMIAwAAAA==.',
Ca='Cailey:BAAANQAECggICgAAAA==.Calcshortfor:BAAANQADCgQIBAAAAA==.Callamdrake:BAAANQADCgQJBQAAAA==.Callamsvoid:BAAANQADCgEIAQAAAA==.Calyrex:BAAANQADCgEJAQAAAA==.Camazotz:BAAANQADCgYIBgAAAA==.Capulse:BAAANQAFFAIIBAAAAA==.',
Ce='Centri:BAAANQAECggIEQAAAA==.',
Cl='Clapdatazz:BAAANQAECgQIBAAAAA==.Cleverlev:BAAANQADCgUIBwABNQAECgcIEgADAAAAAA==.',
Co='Colapse:BAAANQADCgMIAwAAAA==.',
Cr='Crunchrr:BAAANQADCgEIAQAAAA==.',
Cu='Cubensis:BAAANQADCgcJFgAAAA==.',
Cy='Cyiera:BAAANQAECggICQABNQAECggICgADAAAAAA==.',
Da='Daeland:BAAANQAECgEIAQAAAA==.Daisyshot:BAABNQAECoElAAMIAAkKyiIkEgAwAwAIAAgKMiQkEgAwAwAJAAYKERz4LQCDAQAAAA==.',
De='Deathsgrace:BAAANQADCggICAAAAA==.Decima:BAABNQAECoEXAAIKAAcKHweDUABKAQAKAAcKHweDUABKAQAAAA==.Dejustinfox:BAAANQADCgQIBwAAAA==.Demeter:BAABNQAECoEWAAMJAAkKiR28GABfAgAJAAgK1Ry8GABfAgAIAAQKyRU3xgAKAQAAAA==.Demonpunter:BAAANQAECgUIDQABNQAFFAMICAALACAlAA==.',
Di='Diabloa:BAAANQADCgQICAAAAA==.Diamba:BAAANQADCgMIAwAAAA==.Dinoscarr:BAAANQAECgQIBAAAAA==.',
Do='Doohickey:BAAANQADCggIEAAAAA==.Doohicky:BAAANQADCggIGAAAAA==.Dorgrim:BAAANQADCgMIAwAAAA==.Dotsndash:BAABNQAECoEkAAIMAAgKMRrKFQBuAgAMAAgKMRrKFQBuAgAAAA==.',
Dp='Dpsshaman:BAAANQABCgYIBgABNQAFFAUICgAJAOUQAA==.',
Du='Dungpoo:BAAANQADCgEIAQAAAA==.',
Ea='Eargox:BAAANQAECgMIBAAAAA==.',
Ee='Eesa:BAAANQAECgYIBgAAAA==.',
El='Elinia:BAAANQADCgMIBAAAAA==.Elmdor:BAAANQAECgMIAwAAAA==.Elyndra:BAAANQAECgMIBAAAAA==.',
En='Eniacoc:BAAANQAECgEIAQAAAA==.',
Ex='Excentric:BAAANQAECgIIAgABNQAECggIEQADAAAAAA==.',
Fa='Falarth:BAAANQAECgUIDAAAAA==.Falloutman:BAAANQAECgUIBwAAAA==.Farther:BAAANQADCgUIBQABNQAFFAUICQANACQPAA==.Fayne:BAAANQADCgcICQAAAA==.',
Fe='Felfart:BAAANQADCgUIBQAAAA==.',
Fi='Firefox:BAACNQAFFIEFAAIOAAIKXhEWGAB/AAAOAAIKXhEWGAB/AAA1AAQKgRkAAg4ACQq1GNcmAE8CAA4ACQq1GNcmAE8CAAAA.',
Fl='Flechillas:BAAANQADCgcIDQAAAA==.Flán:BAAANQAECgQIBwAAAA==.',
Fr='Fraternite:BAAANQAECgMIAwAAAA==.',
Fu='Furrymoon:BAAANQADCgcIBwAAAA==.',
Ga='Gabriellad:BAAANQAECgEIAQAAAA==.',
Ge='Gerrakha:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Gi='Giterdonee:BAABNQAECoEgAAMGAAkK1h4IAwDvAgAGAAkKIh4IAwDvAgAFAAUKGhAltgAnAQAAAA==.',
Go='Gotchoo:BAAANQAECgQIDgABNQADCgQIBAADAAAAAA==.Gothmommy:BAABNQAECoEZAAIPAAgK1Bi+PAAuAgAPAAgK1Bi+PAAuAgAAAA==.',
Gr='Grilledchis:BAAANQADCgIIAgAAAA==.Groldin:BAAANQADCgEIAQABNQADCgQIBAADAAAAAA==.Grumble:BAAANQAECgQIBAAAAA==.',
['Gõ']='Gõtchoo:BAAANQADCgQIBAAAAA==.',
Ha='Hairball:BAAANQAECgUIDQAAAA==.Hammerthumb:BAAANQADCgcICQABNQAECgUIDwADAAAAAA==.Hardawn:BAAANQABCgEIAQABNQAFFAUICQANACQPAA==.',
Ho='Hotsoup:BAAANQADCgQJBAAAAA==.Hozzluzzak:BAAANQADCggICAAAAA==.',
Hy='Hyara:BAABNQAECoEtAAIIAAkKsyMCBQCkAwAIAAkKsyMCBQCkAwAAAA==.',
['Hù']='Hùñtarð:BAAANQAECgEIAgAAAA==.',
Ic='Iceagent:BAAANQABCgMIAwAAAA==.',
Im='Imnaked:BAAANQADCgYIBgABNQAECggIEAADAAAAAA==.',
In='Invisimitch:BAAANQADCgEIAQAAAA==.',
Ip='Ips:BAAANQADCgIIAgABNQADCgUIBQADAAAAAA==.',
Jo='Jordi:BAABNQAECoEXAAIIAAcKbBycQgBZAgAIAAcKbBycQgBZAgAAAA==.Jotarcyon:BAAANQABCgIJAgAAAA==.',
Ju='Jukkes:BAAANQADCgcIBwAAAA==.Justinfox:BAAANQADCgEIAQAAAA==.Juukess:BAAANQAECgIIAgAAAA==.',
Ka='Kannarri:BAAANQADCggIFgAAAA==.Kanree:BAACNQAFFIEKAAIQAAUKrQPGAwBKAQAQAAUKrQPGAwBKAQA1AAQKgTIAAhAACQq8ErERABICABAACQq8ErERABICAAAA.Kayaa:BAAANQADCggICAAAAA==.',
Ke='Kea:BAABNQAECoEtAAQEAAkK+CRXAACdAwAEAAkKqSJXAACdAwAPAAkKBCTTBgByAwAMAAMKfRLvRgCpAAAAAA==.Kek:BAAANQAECgIIAgAAAA==.',
Kh='Khaalid:BAAANQADCgQIBAABNQAECggIJwAEAD0XAA==.Kharok:BAAANQAECgYIDAABNQAECggIJwAEAD0XAA==.',
Ki='Kincane:BAAANQADCgcICQAAAA==.',
Ko='Korxin:BAABNQAECoErAAMIAAkKeyE3GwD4AgAIAAkKeyE3GwD4AgAJAAUKiw94OQAeAQAAAA==.Kota:BAAANQADCgEIAQAAAA==.',
Ku='Kurnhaspios:BAAANQADCgQIBAAAAA==.Kurquaan:BAAANQAECgMIBAAAAA==.',
Ky='Kydraeth:BAAANQADCgcIEgAAAA==.',
La='Lanstyn:BAABNQAECoEnAAIEAAgKPRd4BABHAgAEAAgKPRd4BABHAgAAAA==.Laufey:BAABNQAECoEXAAINAAUKORn89ABPAQANAAUKORn89ABPAQAAAA==.',
Le='Lemone:BAAANQADCgUIBQAAAA==.Lemonsk:BAAANQADCgUICAAAAA==.Lenton:BAAANQAECgEIAQAAAA==.',
Li='Lightfury:BAAANQADCgYIDAAAAA==.Limone:BAAANQAECgEIAQAAAA==.Listradra:BAAANQADCgQIBAAAAA==.',
Lo='Loganwater:BAAANQADCgQIBAAAAA==.Lohcolo:BAAANQAECgEIAQAAAA==.Loinari:BAAANQADCgUICwAAAA==.Lokano:BAAANQADCgIIAgAAAA==.',
Lu='Ludmylha:BAAANQAECgIIAwAAAA==.Luisda:BAAANQADCggIFwAAAA==.Lull:BAAANQADCggIDgAAAA==.Lushil:BAAANQAFFAEIAQAAAA==.',
Ly='Lyrea:BAAANQAECggICAAAAA==.',
Ma='Man:BAAANQADCgUIBQAAAA==.Marsangel:BAAANQADCgEIAQAAAA==.Maybell:BAAANQAECgEIAQAAAA==.',
Me='Meepmeepmomp:BAAANQADCgUIBQAAAA==.Megumín:BAAANQADCgUIBQAAAA==.Melt:BAACNQAFFIEJAAQRAAUKwBJ+CgCpAAARAAIKjBB+CgCpAAALAAIK5hYlHgCjAAASAAEK3Q4PCgBKAAA1AAQKgS8AAwsACQrjIqQTABMDAAsACAryIqQTABMDABEABAqhIbUcAHkBAAAA.Mepha:BAABNQAECoEcAAMTAAkKMxm0KABEAgATAAgKeBu0KABEAgAUAAgKtAwsNACgAQAAAA==.',
Mi='Mike:BAACNQAFFIEJAAINAAUKJA+JEgCSAQANAAUKJA+JEgCSAQA1AAQKgUUAAw0ACQp1Ii4cAFMDAA0ACQpzIi4cAFMDABUABQrGEzcWAAoBAAAA.Mikevoker:BAAANQADCgEIAQABNQAFFAUICQANACQPAA==.Mipz:BAAANQADCgUIBQAAAA==.Mistfox:BAAANQADCgYIDAAAAA==.Mistmommy:BAAANQAECgYIDQAAAA==.',
Mo='Mommon:BAAANQADCgEIAQAAAA==.Morrighan:BAAANQADCgMIAwAAAA==.',
['Mâ']='Mâlus:BAAANQAECgQIBgAAAA==.',
['Mä']='Märs:BAAANQADCgYICgAAAA==.',
Na='Nadra:BAAANQADCgYIBgAAAA==.Naminé:BAAANQADCgQIBAABNQAECgUIFwANADkZAA==.Nattyrav:BAABNQAECoEiAAMWAAkKvBnDKQCcAgAWAAkKvBnDKQCcAgAXAAEKUB1K2wBUAAAAAA==.',
Ne='Neemesis:BAAANQAECgQIBAAAAA==.Nemonk:BAAANQAECgcIDAAAAA==.Nemoz:BAAANQAECgcIBwABNQAECgcIDAADAAAAAA==.Nerfling:BAAANQADCgYICAAAAA==.',
No='Nocter:BAAANQAECgUIBQAAAA==.Noktor:BAAANQADCgYIBgAAAA==.Noktra:BAAANQAECgQIDwAAAA==.',
Ny='Nymura:BAAANQAECgQICAAAAA==.',
Oa='Oakhugger:BAAANQAECgUIDwAAAA==.',
Ol='Olyvivia:BAAANQADCgUIBQAAAA==.',
Om='Omgega:BAAANQAECgUIEgAAAA==.',
On='Onichan:BAAANQAECgEIAQABNQAFFAcIEgAWANkXAA==.Onimeek:BAABNQAECoEkAAIYAAgKvRnbIQBBAgAYAAgKvRnbIQBBAgAAAA==.Onionknightt:BAAANQAECgEIAQAAAA==.',
Or='Oryn:BAAANQAECggIDgAAAA==.Oryx:BAAANQADCgEIAQAAAA==.',
Os='Osoloco:BAAANQADCgUIAwAAAA==.',
Pa='Palmpower:BAAANQADCgYICQAAAA==.Palpitations:BAAANQAECgEIAQAAAA==.Paper:BAAANQAFFAMIBgAAAQ==.',
Pe='Peacefullev:BAAANQAECgcIEgAAAA==.Pewpewpew:BAAANQADCggIHAAAAA==.',
Ph='Phantomthief:BAAANQADCgcIDwAAAA==.',
Pi='Pipeleto:BAABNQAECoEgAAIFAAgKLB8QMgDGAgAFAAgKLB8QMgDGAgAAAA==.Pizzaroll:BAABNQAECoEkAAIZAAgKBBkTBQBXAgAZAAgKBBkTBQBXAgAAAA==.',
Po='Podvoddonut:BAAANQADCgYIBgAAAA==.',
Pr='Previdius:BAAANQADCgUIBQAAAA==.Priesstess:BAAANQADCgYICQAAAA==.',
['Pé']='Pépega:BAAANQADCgQIBwAAAA==.',
Ri='Riven:BAAANQADCgYIBgAAAA==.Rixin:BAEBNQAECoEmAAITAAkKXyC7EgDvAgATAAkKXyC7EgDvAgAAAA==.',
Ro='Rokom:BAABNQAECoEhAAMGAAkK/htbCgDYAQAGAAYKrB1bCgDYAQAFAAQKYxecvQARAQAAAA==.Roonrano:BAAANQADCggJCAAAAA==.',
Ru='Rumpus:BAAANQADCgcIBwAAAA==.Runed:BAAANQAECgEIAQAAAA==.',
Ry='Ryuk:BAAANQADCgYICgAAAA==.',
Sa='Saberee:BAAANQADCgUIBQAAAA==.Salla:BAAANQADCgYICQAAAA==.Sanlennicus:BAAANQADCggIDwAAAA==.Saphh:BAAANQAECgEIAQABNQAFFAQICQAUAF4TAA==.Saudencheek:BAAANQAECgQIBAAAAA==.',
Se='Seanster:BAAANQAECggIEgABNQAFFAUICAALADkMAA==.Senecca:BAAANQAECgcIEQAAAA==.',
Sh='Shadowms:BAAANQAECgUIDgAAAA==.Shadowxd:BAAANQAECgYIDAAAAA==.Shamanpwnz:BAAANQAECgQIBgAAAA==.Shambassador:BAAANQAECgYIDgAAAA==.Shamwowha:BAAANQADCgQIBAAAAA==.Sharkdancer:BAAANQAFFAIIAgABNQAFFAUICwAQAFwhAA==.Shaulana:BAAANQADCggIFwAAAA==.Shenwu:BAABNQAECoEYAAIaAAcKwRjlDADtAQAaAAcKwRjlDADtAQAAAA==.Shirokuma:BAABNQAECoEZAAMKAAkKdR0zFAAAAwAKAAkKdR0zFAAAAwAbAAEK8RdCOABPAAAAAA==.Shocktopuus:BAAANQADCgQIBAAAAA==.Shwizzle:BAAANQADCggIDgAAAA==.',
Si='Sidvicious:BAAANQADCgUIBAAAAA==.',
Sk='Sköllati:BAAANQAECgQIBAAAAA==.',
Sn='Sneakylev:BAAANQAECggIEwABNQAECgcIEgADAAAAAA==.',
So='Solari:BAABNQAECoEoAAMcAAkKNSA5BgBcAwAcAAkKNSA5BgBcAwAdAAUKwQ8YFAAEAQAAAA==.Soleon:BAAANQAECgQIBAAAAA==.Solune:BAAANQAECgYIDAAAAA==.Souprage:BAAANQAECgMIBAAAAA==.',
Sp='Spypal:BAAANQADCgYIDAAAAA==.',
St='Stabwei:BAAANQADCggICAAAAA==.',
Sw='Swagmastrflx:BAAANQADCgQIBAAAAA==.Swëëtdee:BAAANQADCgMICAAAAA==.',
Ta='Taehausx:BAAANQAFFAEIAQABNQAFFAYIEAAOAIkbAA==.Taraka:BAAANQADCggICAAAAA==.',
Td='Tdolokk:BAAANQADCgYJEAAAAA==.',
Te='Teeward:BAAANQADCgYIBgAAAA==.Tenath:BAAANQAECgMIBAAAAA==.',
Th='Thaleon:BAAANQADCggICAAAAA==.Thauriel:BAAANQAECgEIAQAAAA==.Therella:BAAANQADCgUIBQAAAA==.',
To='Totemtotebag:BAAANQAECgQIDwABNQAECgcIEwADAAAAAA==.',
Tr='Trollztoll:BAAANQADCgIIAgAAAA==.',
Tw='Twochain:BAAANQAECggIEAAAAA==.',
Un='Una:BAAANQADCgQIBAAAAA==.Unholytato:BAAANQADCgQIBAAAAA==.',
Ut='Uthok:BAAANQADCgEJAQAAAA==.',
Uz='Uzol:BAAANQADCgEIAQAAAA==.',
Va='Vacalocà:BAAANQAECgIIAgAAAA==.Valerian:BAAANQAECgUICwAAAA==.',
Ve='Veinke:BAAANQAECgcIEwAAAA==.Velanthir:BAAANQADCggIFAAAAA==.Verd:BAEANQAECgIIAgAAAA==.Veronica:BAAANQABCgYIBgAAAA==.Versaacee:BAAANQADCgYIBgAAAA==.Vessarind:BAAANQADCgUIBQAAAA==.',
Vi='Vivrian:BAAANQADCgUIBQAAAA==.',
['Vä']='Vänillaicë:BAAANQADCgcIBwAAAA==.',
Wa='Waally:BAAANQAECgQIBQAAAA==.',
We='Weebsora:BAAANQAECgQIBQAAAA==.',
Wo='Worldtree:BAAANQADCgEIAQAAAA==.',
Xa='Xaelthira:BAAANQADCgcIBwAAAA==.',
Ya='Yadhi:BAAANQAECgUIBQABNQAECggIJwAEAD0XAA==.',
Yi='Yimomo:BAABNQAECoEeAAIPAAgKix3mIgCpAgAPAAgKix3mIgCpAgAAAA==.',
Za='Zalconn:BAABNQAECoEZAAMeAAkKgCMzCgC5AgAeAAcK6yMzCgC5AgAfAAQK/B+YNwB4AQAAAA==.Zarrona:BAAANQAECgIIAwABNQAECgUIFwANADkZAA==.Zayah:BAAANQAECggIDwAAAA==.',
Zi='Zikony:BAAANQAECgEIAQAAAA==.',
Zu='Zuber:BAABNQAECoEeAAIfAAgKKSLkDADnAgAfAAgKKSLkDADnAgAAAA==.',
['År']='Årtimus:BAAANQADCgYIDAAAAA==.',
['Üw']='Üwü:BAAANQAECgQIBQAAAA==.',
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
