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

local lookup = {'Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Elemental','Unknown-Unknown','Priest-Holy','Warlock-Destruction','Warlock-Demonology','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Devourer','Evoker-Devastation','Paladin-Holy','DemonHunter-Havoc','Druid-Restoration','Hunter-BeastMastery','Shaman-Restoration','Paladin-Retribution','Monk-Windwalker','DeathKnight-Unholy','Monk-Mistweaver','Warlock-Affliction','Monk-Brewmaster','DeathKnight-Frost','Rogue-Subtlety','Rogue-Assassination','Mage-Frost','Priest-Shadow','DeathKnight-Blood',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAABNQAECoEfAAQBAAkKnhtDOQCqAgABAAkKWBpDOQCqAgACAAEK2BrlLgBQAAADAAIK+AR0IwBKAAAAAA==.Adellon:BAABNQAECoEaAAIEAAkKfRtZIgDIAgAEAAkKfRtZIgDIAgAAAA==.Adhar:BAAANQADCgQIBAAAAA==.Adrielle:BAAANQAECgIJAgAAAA==.',
Ak='Akakage:BAAANQAECgYIDQAAAA==.Akakaji:BAAANQAECgMIAwABNQAECgYIDQAFAAAAAA==.Akutoku:BAAANQAECgUICQAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAAANQAECgQIDgAAAA==.',
Ar='Ar:BAABNQAECoEWAAIGAAgKIAp+WwCuAQAGAAgKIAp+WwCuAQABNQAECgkJHwABAJ4bAA==.Archon:BAABNQAECoEfAAIBAAgKixzpQACOAgABAAgKixzpQACOAgAAAA==.Arienca:BAABNQAECoEfAAMHAAgK6wuxEwDFAQAHAAgK6wuxEwDFAQAIAAUKpARVzADNAAAAAA==.',
At='At:BAAANQAECgYIBwABNQAECgkJHwABAJ4bAA==.',
Ba='Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCgYICQAAAA==.Bepis:BAABNQAECoEgAAIJAAgKlCAvAwDvAgAJAAgKlCAvAwDvAgAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgUICwAAAA==.',
Bl='Blazerunner:BAABNQAECoEZAAIKAAgKrgq6sADVAQAKAAgKrgq6sADVAQAAAA==.Blitzkreig:BAAANQADCggIFQAAAA==.Blured:BAABNQAECoEiAAILAAgKBiMwCQArAwALAAgKBiMwCQArAwAAAA==.',
Bo='Booty:BAABNQAECoEgAAICAAgKcCC9BQDUAgACAAgKcCC9BQDUAgAAAA==.Bort:BAABNQAECoEZAAIMAAgKLAktFwCWAQAMAAgKLAktFwCWAQAAAA==.',
Br='Brevyn:BAAANQAECgYICwAAAA==.',
Bu='Bubblebutt:BAAANQAECgIIBAABNQAECggIDAAFAAAAAA==.Bulla:BAAANQAECgMIAwAAAA==.Bung:BAABNQAECoEgAAINAAgKshcEPAA1AgANAAgKshcEPAA1AgAAAA==.Buum:BAAANQADCggIGwAAAA==.',
['Bä']='Bämba:BAAANQADCgcIDQABNQAECgYICwAFAAAAAA==.',
Ca='Cali:BAACNQAFFIEQAAMOAAYKQwr7BACuAQAOAAYKgQj7BACuAQALAAMKmQqFCQDeAAA1AAQKgSkAAwsACQr9H8QLAAYDAAsACQpdH8QLAAYDAA4ABQqaHMk2AJUBAAAA.Calipari:BAAANQADCgQIBAABNQAFFAYIEAAOAEMKAA==.Catamara:BAAANQADCggICQAAAA==.',
Ce='Cephus:BAABNQAECoEkAAIPAAkKtBFRGgAVAgAPAAkKtBFRGgAVAgAAAA==.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAACNQAFFIELAAIQAAUK+A0LBgCSAQAQAAUK+A0LBgCSAQA1AAQKgScAAhAACQr1II8OAEgDABAACQr1II8OAEgDAAAA.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAACNQAFFIEHAAMOAAMKuRTOCgDxAAAOAAMKuRTOCgDxAAALAAEKxQrYEABDAAA1AAQKgSYAAwsACQoaIBcOAOUCAAsACQomHRcOAOUCAA4ABAp1H/c9AF0BAAAA.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAABNQAECoEjAAIRAAkKwBzvEQANAwARAAkKwBzvEQANAwAAAA==.',
Cy='Cynestra:BAAANQADCggIFAAAAA==.Cyni:BAAANQAECgEIAQABNQAECgkJHAANAGkdAA==.',
Da='Dadudadu:BAACNQAFFIEGAAISAAQKngavCwAVAQASAAQKngavCwAVAQA1AAQKgTAAAhIACQqdHGcrAN8CABIACQqdHGcrAN8CAAAA.Daftmonk:BAACNQAFFIEHAAITAAMKWxt5BwD3AAATAAMKWxt5BwD3AAA1AAQKgTYAAhMACQouJbUBAL4DABMACQouJbUBAL4DAAAA.Darj:BAAANQAECggIDgAAAA==.Darmonevil:BAAANQAECgQIBQAAAA==.Dasarus:BAAANQAECgIIAgAAAA==.Dauntless:BAAANQADCggIFQAAAA==.',
De='Deth:BAAANQADCgYIBgABNQAECgQIBAAFAAAAAA==.Dethblades:BAAANQADCgYIBgABNQAECgQIBAAFAAAAAA==.Dethblow:BAAANQAECgQIBAAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgQIBAAFAAAAAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQAECgIIAgAAAA==.Diwa:BAABNQAECoEgAAMRAAkKEgQFdQBUAQARAAkKEgQFdQBUAQAEAAcKKwPvlQAWAQAAAA==.',
Dk='Dklot:BAABNQAECoEdAAIUAAkK5xnJJwBJAgAUAAkK5xnJJwBJAgAAAA==.',
Do='Doomkin:BAAANQAECgEIAQAAAA==.',
Dr='Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgQIBgAAAA==.Draviin:BAABNQAECoEeAAIQAAgK5hlAPQBrAgAQAAgK5hlAPQBrAgAAAA==.Dreadgrave:BAAANQAECgYIEQAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIJAgABNQAECgkJHAANAGkdAA==.',
Du='Dunkyn:BAAANQAECgYIDwAAAA==.',
El='Elendryl:BAAANQADCggIEgAAAA==.',
En='Enkeke:BAABNQAECoEgAAIUAAgKzxv8JgBPAgAUAAgKzxv8JgBPAgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgAFAAAAAA==.Eresanna:BAABNQAECoEZAAIKAAgKSxDhoQD2AQAKAAgKSxDhoQD2AQAAAA==.Erf:BAABNQAECoEeAAIVAAgK5w7yFwCnAQAVAAgK5w7yFwCnAQAAAA==.Erinis:BAAANQADCggIEAABNQAECggIFQAOAGsYAA==.',
Es='Esdeath:BAAANQADCgcIBwABNQAECggIFQAOAGsYAA==.',
Ex='Extremefear:BAAANQAECgUIDAAAAA==.',
Fe='Fearious:BAACNQAFFIEIAAMIAAMKICVoFwDWAAAIAAIKVyVoFwDWAAAHAAEKsiRADwBsAAA1AAQKgRcABAgACQqnJKtAAFACAAgABgq1JKtAAFACAAcAAgpYI48/AK8AABYAAQr0JpIZAHYAAAAA.Feroond:BAAANQAECgUICgAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fr='Frogteeth:BAAANQAECgUIBwAAAA==.Frozath:BAAANQADCggICQAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgAFAAAAAA==.Fussypants:BAAANQAECgYIEAAAAA==.',
Ga='Gallindral:BAABNQAECoEkAAILAAgKaxWIHQAtAgALAAgKaxWIHQAtAgAAAA==.Gatito:BAAANQAECggIDAAAAA==.',
Ge='Genericnpc:BAAANQAECgMIAwAAAA==.Geobrando:BAABNQAECoEcAAMRAAgKEhlDMQBYAgARAAgKEhlDMQBYAgAEAAUK3RQiiAA4AQAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gn='Gnosh:BAAANQADCggIGwAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggIEQAFAAAAAA==.',
Gr='Grippindeez:BAAANQAECgcIDgAAAA==.',
Gu='Guidosarduci:BAABNQAECoEZAAMRAAcKkg6DbwBlAQARAAcKkg6DbwBlAQAEAAIKrwPZ4wBZAAAAAA==.Guiseppe:BAAANQAECgQIEwAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQADCggIGwAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECoFHAAIBAAkKJBj8NQC2AgABAAkKJBj8NQC2AgAAAA==.',
Ho='Holyshortguy:BAAANQAFFAMIBAAAAA==.',
Hu='Hustlermag:BAABNQAECoEfAAQWAAcK8xW6DgAbAQAIAAUKNBCXngA1AQAWAAQKtRS6DgAbAQAHAAQKzRX4KwAKAQAAAA==.',
Ic='Icelmo:BAABNQAECoEeAAIBAAkKHhmvQQCLAgABAAkKHhmvQQCLAgAAAA==.',
Im='Impact:BAAANQADCgIJAgABNQAFFAQICgAEAH8UAA==.',
Ja='Jaskow:BAABNQAECoEcAAIPAAgKfhv/EgBxAgAPAAgKfhv/EgBxAgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Ju='Jusdatip:BAAANQAECgYIEAAAAA==.',
Ka='Kalessandra:BAAANQADCgMIAwAAAA==.Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQAECgMIBAAAAA==.',
Ke='Keir:BAAANQADCggJDAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.',
Kr='Krag:BAAANQADCgcICQABNQAECggIIAAXAFAlAA==.Krasis:BAAANQAECggIDgAAAA==.Krazermonk:BAABNQAECoEgAAITAAkKhhgqEQCXAgATAAkKhhgqEQCXAgAAAA==.Kristysavage:BAABNQAECoEhAAIQAAkKMyFyCwBhAwAQAAkKMyFyCwBhAwAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgUICgAAAA==.',
Li='Lichdawg:BAACNQAFFIEJAAIYAAQKxhWaBQA7AQAYAAQKxhWaBQA7AQA1AAQKgR8AAhgACQoNIyQRAMoCABgACQoNIyQRAMoCAAAA.Lilthorn:BAAANQADCggICQAAAA==.',
Lo='Lofometa:BAAANQADCgQIBAAAAA==.Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAFFAMIBAAFAAAAAA==.',
Lu='Lubu:BAABNQAECoEVAAIOAAgKaxi2HwBTAgAOAAgKaxi2HwBTAgAAAA==.Lumen:BAAANQAECgEIAQAAAA==.Lumiette:BAAANQAECgQICQAAAA==.',
Lv='Lvispriestly:BAAANQAECgEJAQABNQABCgIIAgAFAAAAAA==.',
Ly='Lynai:BAAANQAECgUIDgAAAA==.',
['Lá']='Lándwhale:BAABNQAECoEuAAMZAAkKJyX+AADFAwAZAAkKByX+AADFAwAaAAMKER7cSAAOAQAAAA==.',
['Læ']='Lægolas:BAAANQAECgIIAwAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQAFAAAAAA==.',
Ma='Macktimus:BAAANQAECgYIDwAAAA==.Madeinchina:BAAANQADCgYICQAAAA==.Magickrag:BAAANQADCgMIAwABNQAECggIIAAXAFAlAA==.Magictonyp:BAAANQADCggIFAAAAA==.Makili:BAABNQAECoFFAAMKAAkKTSG4JAA1AwAKAAkKTSG4JAA1AwAbAAEKeAyoPgArAAAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAAANQAECgIIAgAAAA==.Mepha:BAAANQADCgYIBgAAAA==.Merlîn:BAAANQADCgUICwAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
Mo='Moga:BAAANQAECgEJAQAAAA==.',
My='Mylodon:BAAANQABCgIIAwAAAA==.Mysternia:BAAANQADCggIGwAAAA==.',
Ni='Niade:BAABNQAECoEcAAMNAAkKaR37FAAEAwANAAkKaR37FAAEAwASAAUKegdR3wDpAAAAAA==.',
No='Notorckrag:BAABNQAECoEgAAIXAAgKUCVrAgBiAwAXAAgKUCVrAgBiAwAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQADCggICAABNQAFFAQICQAcAOofAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Od='Odimeer:BAAANQAECgMIAwAAAA==.',
Of='Offbrandcleo:BAAANQABCggIDgAAAA==.',
Ok='Okibi:BAAANQAECgQIBAABNQAECggIFQAOAGsYAA==.',
Ol='Oldrecipe:BAABNQAECoEbAAINAAkK6RHRNQBRAgANAAkK6RHRNQBRAgAAAA==.Oliange:BAAANQAECgYICwAAAA==.',
Oo='Oopsrofl:BAAANQAECgEIAgAAAA==.',
Op='Optimuze:BAAANQAECgEIAQAAAA==.',
Or='Originalgank:BAABNQAECoEiAAMKAAgK0CCsNQABAwAKAAgK0CCsNQABAwAbAAEK9RGBOgA0AAAAAA==.Orthox:BAAANQADCgMIAwAAAA==.',
Ot='Otoha:BAAANQADCgYIBgAAAA==.',
Pe='Peachcobbler:BAAANQAECgcIDwAAAA==.Peppermint:BAAANQADCgMIAwAAAA==.Pewpsmadness:BAAANQADCggICAAAAA==.',
Pi='Pinkchadp:BAAANQADCgcJBwAAAA==.Pinkk:BAAANQAECgIIAgAAAA==.',
Pl='Plaguerism:BAABNQAECoEZAAMUAAkKZyBpDAAvAwAUAAkKhR9pDAAvAwAdAAMKghh0dADVAAABNQAFFAMICAAIACAlAA==.',
Po='Poo:BAABNQAECoEhAAIaAAkKrCDRCwD0AgAaAAkKrCDRCwD0AgAAAA==.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgIIAgAFAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
Pu='Puck:BAAANQADCgIIAgABNQAECggIFQAOAGsYAA==.',
['Pâ']='Pâiñ:BAAANQADCggIFAAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAAANQAECgcICwAAAA==.Rahor:BAAANQAECgIJBAAAAA==.Rainesage:BAAANQAECgUIDAAAAA==.Ralphel:BAAANQAECgMIAwAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Re='Reddyeforty:BAAANQADCgEIAQAAAA==.',
Rh='Rhubarb:BAAANQAECgcIEQAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ry='Rylosh:BAACNQAFFIENAAIPAAUKdwrxBABsAQAPAAUKdwrxBABsAQA1AAQKgS4AAg8ACQo+EvwXADECAA8ACQo+EvwXADECAAAA.',
Sa='Sabot:BAAANQADCggIGwAAAA==.Sashafierce:BAAANQAECgEIAQABNQAECgIIAgAFAAAAAA==.',
Sc='Scottpaladin:BAAANQAECgQICAAAAA==.',
Se='Seath:BAAANQAECgIIAgABNQAECggIHwAUAI8dAA==.',
Sh='Shamerica:BAACNQAFFIEHAAIEAAQK0xT7CgBIAQAEAAQK0xT7CgBIAQA1AAQKgSoAAgQACQpTI8IJAIYDAAQACQpTI8IJAIYDAAAA.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEIAwAAAA==.',
Sk='Skilleaz:BAABNQAECoEaAAIdAAkK+iKICgBDAwAdAAkK+iKICgBDAwAAAA==.',
Sl='Slagothor:BAABNQAECoEYAAIUAAgKZwXzWABGAQAUAAgKZwXzWABGAQAAAA==.',
So='Soultax:BAAANQADCggIEQAAAA==.',
Sp='Spekaleks:BAAANQAECgIIAwAAAA==.Spinfat:BAABNQAECoEhAAITAAkKLCP4BgA/AwATAAkKLCP4BgA/AwAAAA==.Spiritbox:BAAANQAECgQIBAAAAA==.',
St='Stapler:BAAANQAECgYIEQAAAA==.Starbux:BAAANQADCgUIDQABNQAECgYICgAFAAAAAA==.',
Su='Sugarr:BAAANQADCgYIBgAAAA==.',
Sy='Syb:BAAANQADCgYIDAAAAA==.',
Ta='Taeyang:BAABNQAECoEbAAQIAAkKwCIWFAAQAwAIAAgKfSIWFAAQAwAHAAEKlyNCVwBnAAAWAAEKFiHRHQBZAAAAAA==.Tamerlein:BAAANQADCgUIBwAAAA==.Tankadin:BAAANQADCgcIBwABNQAECgUIDQAFAAAAAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Terraform:BAAANQADCgEIAQAAAA==.',
Th='Theinsider:BAAANQAECgQICAABNQAECggIHwAUAI8dAA==.Theoutsider:BAABNQAECoEfAAMUAAgKjx0ZKABHAgAUAAgKXhwZKABHAgAYAAcKchndJgACAgAAAA==.',
Ti='Timhair:BAAANQADCgYIDgAAAA==.Tindril:BAAANQADCgYIBgAAAA==.',
To='Toekneess:BAABNQAECoEZAAIGAAkKfyT6BACJAwAGAAkKfyT6BACJAwAAAA==.Toekneezz:BAABNQAECoEbAAIVAAkK1SDkAwBMAwAVAAkK1SDkAwBMAwABNQAECgkJGQAGAH8kAA==.Totemofbear:BAAANQAECgYIDAAAAA==.',
Tr='Trandis:BAABNQAECoEcAAITAAgK0CNOCQAUAwATAAgK0CNOCQAUAwAAAA==.Tranza:BAAANQAECgUIDQAAAA==.Trash:BAAANQAECgEIAQAAAA==.',
Tx='Tx:BAACNQAFFIEKAAIEAAQKfxS2CgBMAQAEAAQKfxS2CgBMAQA1AAQKgR0AAgQACQrGH98ZAAIDAAQACQrGH98ZAAIDAAAA.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECgYIEQAFAAAAAA==.Utterchaos:BAAANQAECgQICgABNQAECgcIGQARAJIOAA==.',
Va='Vandrina:BAAANQADCgMIAwAAAA==.Vaporeon:BAAANQADCggIEQAAAA==.',
Ve='Vekris:BAAANQABCgIJAgAAAA==.',
We='Wematanye:BAAANQADCgQIBwABNQAECgQICgAFAAAAAA==.Wetheals:BAAANQAECgcICgAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQAFAAAAAA==.',
Wo='Worgnfreeman:BAAANQAECggICAAAAA==.',
Wt='Wtfmonk:BAABNQAECoEiAAIVAAkKgxjiCgCiAgAVAAkKgxjiCgCiAgABNQAFFAMIBAAFAAAAAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQADCggIGwAAAA==.',
Xo='Xorcopressor:BAAANQAECgYICAABNQAECggIDAAFAAAAAA==.',
Xs='Xsaber:BAAANQADCggIHgAAAA==.',
Ya='Yazmo:BAACNQAFFIEJAAIcAAQK6h+YBQCCAQAcAAQK6h+YBQCCAQA1AAQKgSQAAhwACQqvJAgEAIIDABwACQqvJAgEAIIDAAAA.',
Yu='Yushe:BAAANQAECgIIAgAAAA==.Yuuky:BAABNQAECoEfAAIPAAgKXBq+EwBoAgAPAAgKXBq+EwBoAgAAAA==.',
Za='Zarivia:BAAANQADCgQIBAAAAA==.',
['Ör']='Ördög:BAAANQADCggICwAAAA==.',
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
