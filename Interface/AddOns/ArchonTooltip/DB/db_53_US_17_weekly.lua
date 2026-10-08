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

local lookup = {'Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Elemental','Unknown-Unknown','Priest-Holy','Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Devourer','Evoker-Devastation','Paladin-Holy','DemonHunter-Havoc','Druid-Restoration','Hunter-BeastMastery','Shaman-Restoration','Paladin-Retribution','Monk-Windwalker','DeathKnight-Unholy','Monk-Mistweaver','Warlock-Affliction','DeathKnight-Blood','Evoker-Augmentation','Priest-Shadow','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Mage-Frost',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAABNQAECoElAAQBAAkKyBsrPAC/AgABAAkKyBsrPAC/AgACAAEK2BoaNgBNAAADAAIK+ARCKQBGAAAAAA==.Adellon:BAABNQAECoEaAAIEAAkKfRvlKgCwAgAEAAkKfRvlKgCwAgAAAA==.Adhar:BAAANQADCgYICgAAAA==.Adrielle:BAAANQAECgUIBwAAAA==.',
Ak='Akakage:BAAANQAECgYIEQAAAA==.Akakaji:BAAANQAECgMIAwABNQAECgYIEQAFAAAAAA==.Akutoku:BAAANQAECgcIDwAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAAANQAECgQIEgAAAA==.',
Ar='Ar:BAABNQAECoEYAAIGAAgKXQsJZgC5AQAGAAgKXQsJZgC5AQABNQAECgkJJQABAMgbAA==.Archon:BAABNQAECoEnAAMBAAgK0iAvMQDmAgABAAgK0iAvMQDmAgADAAEKJR3ZJgBVAAAAAA==.Arienca:BAABNQAECoElAAMHAAgK9A4JEgDbAQAHAAgK9A4JEgDbAQAIAAUKpASv6ADKAAAAAA==.',
As='Aspir:BAEANQAECgcIBwABNQAFFAQICAAJACIVAA==.',
At='At:BAAANQAECgYIBwABNQAECgkJJQABAMgbAA==.',
Ba='Baidoogh:BAAANQADCgIIAgAAAA==.Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCgYICQAAAA==.Bepis:BAABNQAECoEjAAIKAAkKNyEiAgBRAwAKAAkKNyEiAgBRAwAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgUICwAAAA==.',
Bl='Blazerunner:BAABNQAECoEgAAILAAgKTAyjvgDjAQALAAgKTAyjvgDjAQAAAA==.Blitzkreig:BAAANQAECgMIAwAAAA==.Blured:BAABNQAECoEqAAIMAAkKjSOnAgCwAwAMAAkKjSOnAgCwAwAAAA==.',
Bo='Booty:BAABNQAECoEjAAICAAkKkx/yBAAQAwACAAkKkx/yBAAQAwAAAA==.Bort:BAABNQAECoEcAAINAAkK5ghaFwCzAQANAAkK5ghaFwCzAQAAAA==.',
Br='Brevyn:BAAANQAECgcIEgAAAA==.',
Bu='Bubblebutt:BAAANQAECgQICAABNQAECggIDAAFAAAAAA==.Bulla:BAAANQAECgMIAwAAAA==.Bung:BAABNQAECoEjAAIOAAkKXBcbNQB0AgAOAAkKXBcbNQB0AgAAAA==.Buum:BAAANQAECgMIAwAAAA==.',
['Bä']='Bämba:BAAANQADCgcIDQABNQAECgYIEQAFAAAAAA==.',
Ca='Cali:BAACNQAFFIEVAAMPAAcKRwypBgCsAQAPAAYKpQupBgCsAQAMAAQKZAreCAAyAQA1AAQKgSwAAwwACQo7IMEOAO4CAAwACQpdH8EOAO4CAA8ABQoJHc48AJwBAAAA.Calipari:BAAANQADCgQIBAABNQAFFAcIFQAPAEcMAA==.Catamara:BAAANQADCggICQAAAA==.',
Ce='Cephus:BAABNQAECoEnAAIQAAkK1BF3HgAQAgAQAAkK1BF3HgAQAgAAAA==.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAACNQAFFIEQAAIRAAUKGxCBCACaAQARAAUKGxCBCACaAQA1AAQKgSsAAhEACQo5IbgRAEUDABEACQo5IbgRAEUDAAAA.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAACNQAFFIELAAMPAAQKvBdUCgBEAQAPAAQKvBdUCgBEAQAMAAEKxQoYEwBDAAA1AAQKgSkAAwwACQq7IP8QANQCAAwACQomHf8QANQCAA8ABAoUId1CAHMBAAAA.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAABNQAECoEsAAMSAAkK6hwpFgAEAwASAAkK6hwpFgAEAwAEAAUKggx2rAALAQAAAA==.',
Cy='Cynestra:BAAANQAECgMIAwAAAA==.Cyni:BAAANQAECgEIAQABNQAECgkJHwAOAGkdAA==.',
Da='Dadudadu:BAACNQAFFIEJAAITAAUKTgoqCwBjAQATAAUKTgoqCwBjAQA1AAQKgTMAAhMACQpnHVs2ANMCABMACQpnHVs2ANMCAAAA.Daftmonk:BAACNQAFFIELAAIUAAQKiBpyBwA9AQAUAAQKiBpyBwA9AQA1AAQKgToAAhQACQqFJd8BAL4DABQACQqFJd8BAL4DAAAA.Darj:BAABNQAECoEZAAIBAAkKahVyWABlAgABAAkKahVyWABlAgAAAA==.Darmonevil:BAAANQAECgQICAAAAA==.Dasarus:BAAANQAECgUIBwAAAA==.Dauntless:BAAANQAECgMIAwAAAA==.',
De='Deth:BAAANQADCgYIBgABNQAECgQIBQAFAAAAAA==.Dethblades:BAAANQAECgEIAQABNQAECgQIBQAFAAAAAA==.Dethblow:BAAANQAECgQIBQAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgQIBQAFAAAAAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQAECgIIAgAAAA==.Diwa:BAABNQAECoEpAAMSAAkK/Qe4bQCTAQASAAkK/Qe4bQCTAQAEAAcKKwO9rAALAQAAAA==.',
Dk='Dklot:BAABNQAECoEgAAIVAAkKWxsGLgBXAgAVAAkKWxsGLgBXAgAAAA==.',
Do='Doomkin:BAAANQAECgUIBgAAAA==.',
Dr='Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgQIBgAAAA==.Draviin:BAABNQAECoEmAAIRAAgKVxo1RgBzAgARAAgKVxo1RgBzAgAAAA==.Dreadgrave:BAAANQAECgcIEgAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIJAgABNQAECgkJHwAOAGkdAA==.',
Du='Dunkyn:BAAANQAECgYIDwAAAA==.',
El='Elendryl:BAAANQADCggIEgAAAA==.',
En='Enkeke:BAABNQAECoEoAAIVAAkKKxsFJwB/AgAVAAkKKxsFJwB/AgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgAFAAAAAA==.Eresanna:BAABNQAECoEZAAILAAgKSxAXuQDuAQALAAgKSxAXuQDuAQAAAA==.Erf:BAABNQAECoEhAAIWAAkKew7BFwDRAQAWAAkKew7BFwDRAQAAAA==.Erinis:BAAANQADCggIFgABNQAECggIGwAPAKMaAA==.',
Es='Esdeath:BAAANQADCgcICwABNQAECggIGwAPAKMaAA==.',
Ex='Extremefear:BAAANQAECgYIEgAAAA==.',
Fe='Fearious:BAACNQAFFIEMAAQXAAUKSyN5BAB1AAAIAAMKmiHcFAAgAQAXAAEK9yZ5BAB1AAAHAAEKsiSpEQBnAAA1AAQKgRcABAgACQqnJLVSADwCAAgABgq1JLVSADwCAAcAAgpYI+tDAKsAABcAAQr0JoMcAHUAAAAA.Feroond:BAAANQAECgYIDwAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fr='Frogteeth:BAAANQAECgUIDAAAAA==.Frozath:BAAANQADCggICQAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgAFAAAAAA==.Fussypants:BAAANQAECgYIEwAAAA==.',
Ga='Gallindral:BAABNQAECoEnAAIMAAkKoxRRGwBgAgAMAAkKoxRRGwBgAgAAAA==.Gatito:BAAANQAECggIDAAAAA==.',
Ge='Genericnpc:BAAANQAECgUICAAAAA==.Geobrando:BAABNQAECoEjAAMSAAgKEhkaOwBKAgASAAgKEhkaOwBKAgAEAAUK3RSAnAAuAQAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gn='Gnosh:BAAANQAECgMIAwAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggIEQAFAAAAAA==.',
Gr='Grippindeez:BAABNQAECoEVAAMJAAcKwA4hQwBxAQAJAAcK7gshQwBxAQAYAAEKhiHMpgBfAAAAAA==.Grêêd:BAAANQADCgMIAwAAAA==.',
Gu='Guidosarduci:BAABNQAECoEeAAMSAAcKzg5yfwBgAQASAAcKzg5yfwBgAQAEAAIKrwN+/gBWAAAAAA==.Guiseppe:BAABNQAECoEbAAMNAAcKhhD7GACZAQANAAcK/A/7GACZAQAZAAMKswzUGACDAAAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQAECgMIAwAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECoFMAAIBAAkKOBixQACwAgABAAkKOBixQACwAgAAAA==.',
Ho='Holyshortguy:BAACNQAFFIEHAAIGAAQKJQrvEwAuAQAGAAQKJQrvEwAuAQA1AAQKgRsAAwYACQriGfogAM8CAAYACQriGfogAM8CABoAAQp8DeJyACoAAAAA.',
Hu='Hustlermag:BAABNQAECoElAAQXAAcK8xWEEQALAQAIAAYKaxKplACDAQAXAAQKtRSEEQALAQAHAAQKzRVhLgAGAQAAAA==.',
Ic='Icelmo:BAACNQAFFIEFAAIBAAIKrgadLAB+AAABAAIKrgadLAB+AAA1AAQKgSEAAgEACQphGgBEAKUCAAEACQphGgBEAKUCAAAA.',
Im='Impact:BAAANQADCgIJAgABNQAFFAQIDgAEABcWAA==.',
Ja='Jaskow:BAABNQAECoEeAAIQAAgKyxvXFgBmAgAQAAgKyxvXFgBmAgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Ju='Jusdatip:BAABNQAECoEYAAIbAAcKfw8hHwDCAQAbAAcKfw8hHwDCAQABNQAECgcIHgASAM4OAA==.',
Ka='Kalessandra:BAAANQAECgQIBAAAAA==.Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQAECgMIBAAAAA==.',
Ke='Keir:BAAANQADCggJDAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.Kimlin:BAAANQADCgMIAwAAAA==.',
Kr='Krag:BAAANQADCgcICQABNQAECgkJIQAcABklAA==.Krasis:BAAANQAECggIEAAAAA==.Krazermonk:BAABNQAECoEnAAIUAAkKSxrTEQCwAgAUAAkKSxrTEQCwAgAAAA==.Kristysavage:BAABNQAECoEoAAIRAAkKHyM3CACNAwARAAkKHyM3CACNAwAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgYIDQABNQAFFAUICwAQAG4XAA==.',
Li='Lichdawg:BAACNQAFFIENAAIJAAQKgxezBgBGAQAJAAQKgxezBgBGAQA1AAQKgSIAAgkACQqUI+4PAPMCAAkACQqUI+4PAPMCAAAA.Lilthorn:BAAANQADCggICQAAAA==.',
Lo='Lofometa:BAAANQADCgQIBAAAAA==.Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAFFAQIBwAGACUKAA==.',
Lu='Lubu:BAABNQAECoEbAAIPAAgKoxomIQBqAgAPAAgKoxomIQBqAgAAAA==.Lumen:BAAANQAECgUIBgAAAA==.Lumiette:BAAANQAECgYIDwAAAA==.',
Lv='Lvispriestly:BAAANQAECgEJAQABNQABCgIIAgAFAAAAAA==.',
Ly='Lynai:BAAANQAECgYIDwAAAA==.',
['Lá']='Lándwhale:BAABNQAECoE0AAMbAAkK6yUWAQDHAwAbAAkKRyUWAQDHAwAdAAQKxyN1PQCXAQAAAA==.',
['Læ']='Lægolas:BAAANQAECgIIBAAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQAFAAAAAA==.',
Ma='Macktimus:BAAANQAECgcIEgAAAA==.Madeinchina:BAAANQADCgYICQAAAA==.Magickrag:BAAANQADCgMIAwABNQAECgkJIQAcABklAA==.Magictonyp:BAAANQADCggIFAAAAA==.Makili:BAABNQAECoFGAAMLAAkKTSGMMQAcAwALAAkKTSGMMQAcAwAeAAEKeAy6RgAqAAAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAAANQAECgIIAgABNQAECgUIBQAFAAAAAA==.Mepha:BAAANQADCgYIBgAAAA==.Merlîn:BAAANQADCgUIDAAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
Mo='Moga:BAAANQAECgEJAQAAAA==.Mornedelth:BAAANQAECgUIBQAAAA==.',
My='Mylodon:BAAANQABCgIIAwAAAA==.Mysternia:BAAANQAECgMIAwAAAA==.',
Ni='Niade:BAABNQAECoEfAAMOAAkKaR0MGgD7AgAOAAkKaR0MGgD7AgATAAUKegcBAgHjAAAAAA==.',
No='Notorckrag:BAABNQAECoEhAAIcAAkKGSUQAQC+AwAcAAkKGSUQAQC+AwAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQADCggICAABNQAFFAUIDQAaAKEaAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Od='Odimeer:BAAANQAECgQIBwAAAA==.',
Of='Offbrandcleo:BAAANQABCggIDgAAAA==.',
Ok='Okibi:BAAANQAECgQICAABNQAECggIGwAPAKMaAA==.',
Ol='Oldrecipe:BAABNQAECoEeAAIOAAkK6RHrPwBHAgAOAAkK6RHrPwBHAgAAAA==.Oliange:BAAANQAECgYIEQAAAA==.',
Oo='Oopsrofl:BAAANQAECgEIAgAAAA==.',
Op='Optimuze:BAAANQAECgEIAgAAAA==.',
Or='Originalgank:BAABNQAECoEjAAMLAAgKVSFpQQDzAgALAAgKVSFpQQDzAgAeAAEK9RE/QwAwAAAAAA==.Orthox:BAAANQADCgUIBQAAAA==.',
Ot='Otoha:BAAANQADCgYIBgAAAA==.',
Pe='Peachcobbler:BAAANQAECgcIEQAAAA==.Peachcrumpet:BAAANQADCgEIAQAAAA==.Peppermint:BAAANQAECgUIBQAAAA==.Pewpsmadness:BAAANQAECgQIBAAAAA==.',
Pi='Pinkchadp:BAAANQADCgcJBwAAAA==.Pinkk:BAAANQAECgMIBAAAAA==.',
Pl='Plaguerism:BAABNQAECoEfAAMVAAkKxSHtDAA9AwAVAAkKaCHtDAA9AwAYAAMKghhCgQDQAAABNQAFFAUIDAAXAEsjAA==.',
Po='Poo:BAACNQAFFIEFAAIdAAMKHA2HCwDwAAAdAAMKHA2HCwDwAAA1AAQKgSkAAh0ACQowIYEIADgDAB0ACQowIYEIADgDAAAA.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgIIAgAFAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
Pu='Puck:BAAANQADCgQIBgABNQAECggIGwAPAKMaAA==.',
['Pâ']='Pâiñ:BAAANQADCggIFgAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAAANQAECgcIEgAAAA==.Rahor:BAAANQAECgYICgAAAA==.Rainesage:BAAANQAECgYIEgAAAA==.Ralphel:BAAANQAECgUICAAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Re='Reddyeforty:BAAANQAECgYIBgAAAA==.',
Rh='Rhubarb:BAABNQAECoEWAAIBAAkKqSBYGwA+AwABAAkKqSBYGwA+AwAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ry='Rylosh:BAACNQAFFIESAAIQAAUKoQrcBgBnAQAQAAUKoQrcBgBnAQA1AAQKgTIAAhAACQqIEmUcACYCABAACQqIEmUcACYCAAAA.',
Sa='Sabot:BAAANQAECgMIAwAAAA==.Sashafierce:BAAANQAECgEIAQABNQAECgIIAgAFAAAAAA==.',
Sc='Scottpaladin:BAAANQAECgQICAAAAA==.',
Se='Seath:BAAANQAECgIIAgABNQAECgkJJwAJAMQeAA==.',
Sh='Shamantics:BAAANQAECgEIAQABNQAFFAUIDAAXAEsjAA==.Shamerica:BAACNQAFFIEMAAIEAAYK/BZYBQAEAgAEAAYK/BZYBQAEAgA1AAQKgTAAAgQACQp8JGIGAKwDAAQACQp8JGIGAKwDAAAA.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEIAwAAAA==.',
Sk='Skilleaz:BAABNQAECoEdAAIYAAkKOiMSDABCAwAYAAkKOiMSDABCAwAAAA==.',
Sl='Slagothor:BAABNQAECoEaAAIVAAgK/wXWagBCAQAVAAgK/wXWagBCAQAAAA==.',
So='Soultax:BAAANQAECgMIAwAAAA==.',
Sp='Spekaleks:BAAANQAECgIIAwAAAA==.Spinfat:BAACNQAFFIEHAAIUAAUKrhtYBQCXAQAUAAUKrhtYBQCXAQA1AAQKgSQAAhQACQosI1YIADcDABQACQosI1YIADcDAAAA.Spiritbox:BAAANQAECgQIBAAAAA==.',
St='Stapler:BAAANQAECgYIEQAAAA==.Starbux:BAAANQADCgUIDQABNQAECgcICwAFAAAAAA==.',
Su='Sugarr:BAAANQADCgYIBgAAAA==.',
Sy='Syb:BAAANQAECgMIAwAAAA==.',
Ta='Taeyang:BAABNQAECoEfAAQIAAkK7iNhFQAhAwAIAAgK0SNhFQAhAwAHAAEKlyP1WwBlAAAXAAEKFiEZIgBUAAAAAA==.Tamerlein:BAAANQADCgUIBwAAAA==.Tankadin:BAAANQADCgcIBwABNQAECgUIEgAFAAAAAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Terraform:BAAANQADCgEIAQAAAA==.',
Th='Theinsider:BAAANQAECgQICAABNQAECgkJJwAJAMQeAA==.Theoutsider:BAABNQAECoEnAAMJAAkKxB5aFQC+AgAJAAgKch5aFQC+AgAVAAgKXhzjOQAXAgAAAA==.',
Ti='Timhair:BAAANQADCgYIDgAAAA==.Tindril:BAAANQADCgYIBgAAAA==.',
To='Toekneess:BAABNQAECoEdAAIGAAkKBiUDAwCwAwAGAAkKBiUDAwCwAwAAAA==.Toekneez:BAAANQAECgYICAABNQAECgkJHQAGAAYlAA==.Toekneezz:BAABNQAECoEdAAIWAAkKRiKCAwBlAwAWAAkKRiKCAwBlAwABNQAECgkJHQAGAAYlAA==.Totemmalotes:BAAANQADCgMIAwAAAA==.Totemofbear:BAAANQAECgYIEgAAAA==.',
Tr='Trandis:BAABNQAECoEfAAIUAAkK9yKzBgBRAwAUAAkK9yKzBgBRAwAAAA==.Tranza:BAAANQAECgUIEgAAAA==.Trash:BAAANQAECgEIAQAAAA==.',
Tx='Tx:BAACNQAFFIEOAAIEAAQKFxYXDgBMAQAEAAQKFxYXDgBMAQA1AAQKgSIAAgQACQpDIG0aABMDAAQACQpDIG0aABMDAAAA.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECgcIEgAFAAAAAA==.Utterchaos:BAAANQAECgQIEQABNQAECgcIHgASAM4OAA==.',
Va='Vandrina:BAAANQADCgMIAwAAAA==.Vaporeon:BAAANQADCggIEQAAAA==.',
Ve='Vekris:BAAANQAECgQIBAAAAA==.',
We='Wematanye:BAAANQADCgQICwABNQAECgQIDgAFAAAAAA==.Wetheals:BAAANQAECgcIDAAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQAFAAAAAA==.',
Wo='Worgnfreeman:BAAANQAECggICAAAAA==.',
Wt='Wtfmonk:BAABNQAECoEiAAIWAAkKgxh3DQCHAgAWAAkKgxh3DQCHAgABNQAFFAQIBwAGACUKAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQAECgMIAwAAAA==.',
Xo='Xorcopressor:BAAANQAECgYICAABNQAECggIDAAFAAAAAA==.',
Xs='Xsaber:BAAANQADCggIJgAAAA==.',
Ya='Yazmo:BAACNQAFFIENAAIaAAUKoRooBQC3AQAaAAUKoRooBQC3AQA1AAQKgScAAhoACQrnJPUDAI4DABoACQrnJPUDAI4DAAAA.',
Yu='Yushe:BAAANQAECgIIAgAAAA==.Yuuky:BAABNQAECoEnAAIQAAkKkxuSDgDNAgAQAAkKkxuSDgDNAgAAAA==.',
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
