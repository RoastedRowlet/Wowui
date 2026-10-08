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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Hunter-Marksmanship','Warrior-Arms','Priest-Holy','Priest-Shadow','Warlock-Demonology','Shaman-Elemental','Paladin-Holy','Monk-Brewmaster','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','DeathKnight-Blood','Warrior-Protection','DemonHunter-Havoc','Mage-Frost','Priest-Discipline','Druid-Balance','Druid-Restoration','DemonHunter-Devourer','Warrior-Fury','Evoker-Devastation','Paladin-Protection','Hunter-Survival','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abracadavr:BAAANQADCgUJCQAAAA==.Absolomb:BAAANQABCgMIAwAAAA==.',
Ac='Acell:BAABNQAECoFNAAIBAAkKZiKcCQCBAwABAAkKZiKcCQCBAwAAAA==.',
Ad='Addison:BAAANQAECgQICAAAAA==.Adeleas:BAAANQADCggIFgABNQAECgQIBwACAAAAAA==.Adêrna:BAABNQAECoEkAAIDAAgKaBqENwBZAgADAAgKaBqENwBZAgAAAA==.',
Ag='Agba:BAABNQAECoEcAAMEAAcKQRXlUwCaAQAEAAcKQRXlUwCaAQAFAAEKqAmVmwApAAAAAA==.Aglain:BAAANQADCgMIAwAAAA==.',
Ai='Aibrean:BAAANQAECgIIAgAAAA==.Aiché:BAAANQADCgUIBQAAAA==.',
Ak='Aksel:BAAANQADCgQIBAAAAA==.',
Al='Alaala:BAAANQADCgUIBQAAAA==.Alaidan:BAAANQAECgUIBwAAAA==.Alanus:BAABNQAECoEbAAIGAAcK9w2v2QCuAQAGAAcK9w2v2QCuAQAAAA==.Alarion:BAAANQAECgQICAAAAA==.Aliën:BAAANQAECgQIAwAAAA==.Altana:BAAANQAECgIIAgABNQAECgcICAACAAAAAA==.Alydrus:BAAANQADCgcICAAAAA==.',
An='Angryelf:BAAANQAECgIIAwAAAA==.Angrymanjibs:BAAANQAECgIIAwAAAA==.Anitasummon:BAAANQADCgUICAAAAA==.Annahe:BAAANQAECgYIEwAAAA==.Annale:BAAANQADCgYIBgABNQAECgYIEwACAAAAAA==.Anub:BAABNQAECoEYAAMHAAgKQw3lPACaAQAHAAcKdg3lPACaAQAIAAIKSgrlQQB5AAAAAA==.Anzala:BAAANQAECgMIAwAAAA==.',
Ar='Armsmaster:BAABNQAECoEvAAMEAAgK4yCcHwCuAgAEAAgK4yCcHwCuAgAFAAEK9RPhjQA+AAAAAA==.Arrann:BAAANQAECgMIAwAAAA==.Artemistha:BAAANQAECgUIDAAAAA==.',
Av='Avengharambe:BAAANQADCggIDwAAAA==.Averybug:BAAANQADCgYIBgAAAA==.Avielle:BAAANQADCgUIBQAAAA==.',
['Aø']='Aøi:BAACNQAFFIETAAIJAAYKTiCSAgAsAgAJAAYKTiCSAgAsAgA1AAQKgR0AAgkACQrSJDsEAIUDAAkACQrSJDsEAIUDAAAA.',
Ba='Baey:BAAANQABCgEIAQAAAA==.Bam:BAAANQAECgYIBgAAAA==.Barelycastin:BAABNQAECoEeAAIDAAcKTwzEiQBDAQADAAcKTwzEiQBDAQAAAA==.',
Be='Beautiful:BAAANQADCgYICwAAAA==.Beleriand:BAAANQAECgUIDAAAAA==.Belgarathh:BAAANQAECgYICgAAAA==.Bellei:BAAANQADCgcIBwAAAA==.',
Bl='Blacat:BAAANQAECggIEgAAAA==.Blacksirloin:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Blitzcomets:BAAANQADCgcICwAAAA==.Bloodshunter:BAABNQAECoEcAAMBAAkKYh5SKADXAgABAAgKRiBSKADXAgAKAAUKYRGaPgAtAQAAAA==.Blutauren:BAAANQADCgUICAAAAA==.',
Bo='Borda:BAAANQAECgUJCQAAAA==.',
Br='Brendenhunt:BAAANQADCggICAAAAA==.Broomhilda:BAAANQABCggIDAAAAA==.',
Bu='Buddypal:BAAANQAECgMIAwAAAA==.Buddypriest:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
Ca='Caidi:BAAANQAECgEIAQAAAA==.Carini:BAABNQAECoEZAAIGAAcKjxGRywDKAQAGAAcKjxGRywDKAQAAAA==.Catheryne:BAAANQAECgQIBAAAAA==.',
Ch='Chelsgrin:BAAANQAECgUICQABNQAECggIFAALAIsbAA==.Chickynuggy:BAAANQADCgcIBwAAAA==.Chrischan:BAAANQABCgMIAQAAAA==.Chónk:BAAANQAECgQIBwAAAA==.',
Cl='Clûtch:BAABNQAECoEaAAIEAAgK/h3OHgC0AgAEAAgK/h3OHgC0AgAAAA==.',
Co='Corvax:BAAANQADCgYIBgAAAA==.Corynthe:BAABNQAECoEaAAIMAAcKkhhJVQD2AQAMAAcKkhhJVQD2AQAAAA==.',
Cr='Crickie:BAAANQAECgEIAQAAAA==.Croftypongue:BAAANQADCgcIBwAAAA==.Crovaxis:BAABNQAECoEcAAIKAAcKRR47HwA4AgAKAAcKRR47HwA4AgAAAA==.',
Da='Daddychill:BAAANQAECgUIBQAAAA==.Daedrìc:BAAANQADCgQIBAAAAA==.Damagetaken:BAAANQADCggIAwAAAA==.Darktalyn:BAABNQAECoEeAAINAAcKXgxNLwCBAQANAAcKXgxNLwCBAQAAAA==.Dawi:BAAANQAECgIIAgAAAA==.',
De='Deathgrip:BAAANQADCgUIBgAAAA==.Deathhawkzz:BAABNQAECoEfAAIOAAgKOBp0SABcAgAOAAgKOBp0SABcAgAAAA==.Deekura:BAAANQAECgQICwAAAA==.Delusion:BAAANQADCgEIAQAAAA==.Dezireth:BAABNQAECoEpAAIBAAgKkwz8cQD/AQABAAgKkwz8cQD/AQAAAA==.',
Dh='Dhakastyr:BAAANQAECggICAAAAA==.',
Di='Dinak:BAAANQADCggIGQAAAA==.Dionan:BAAANQAECgYIEwAAAA==.',
Do='Docs:BAAANQAECgcIEAAAAA==.Doks:BAABNQAECoEaAAMDAAkK9xfFMQB0AgADAAkK9xfFMQB0AgAPAAEKxxLPEQE3AAAAAA==.',
Dr='Dragana:BAAANQAECgEIAQAAAA==.Dragster:BAAANQAECgEIAQAAAA==.Dragõn:BAAANQADCgEIAQAAAA==.Dreamfýre:BAAANQABCgIIAgAAAA==.Dridae:BAAANQAECgEIAQAAAA==.Drusilvia:BAAANQADCgcIBwAAAA==.',
Ea='Ealara:BAAANQADCggIDwAAAA==.',
Ec='Echidna:BAAANQADCggICAABNQAFFAcIGwAQAPwBAA==.',
El='Elendor:BAAANQABCgYICQAAAA==.',
Em='Emiira:BAAANQADCggIFQAAAA==.',
En='Enthaii:BAAANQAECgEIAQAAAA==.',
Er='Erithil:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.',
Es='Espe:BAABNQAECoEeAAIRAAcKaRkMDgD2AQARAAcKaRkMDgD2AQAAAA==.',
Ev='Everayn:BAABNQAECoE6AAMQAAcKbRVsZQDCAQAQAAcKbRVsZQDCAQASAAUKRgva+gDwAAABNQAECgkJTQABAGYiAA==.',
Ex='Exhalo:BAABNQAECoEhAAILAAgKtxSZbwAkAgALAAgKtxSZbwAkAgAAAA==.',
Fa='Fallen:BAAANQAECgcIEwAAAA==.Fasebreaker:BAAANQABCgcICQAAAA==.Faynor:BAABNQAECoEaAAIRAAcKPSGXBwCiAgARAAcKPSGXBwCiAgAAAA==.',
Fe='Felwhisper:BAAANQAECgUIBQAAAA==.',
Fi='Finalycalm:BAAANQAECgQIBAAAAA==.Finimus:BAAANQAECgIJAgAAAA==.Finlok:BAAANQABCgMIAgAAAA==.Firêfly:BAAANQAECgUIBQAAAA==.',
Fl='Flingpooh:BAAANQAECgMIAwAAAA==.Flloran:BAAANQAECgQICAAAAA==.',
Fr='Fraggle:BAECNQAFFIEMAAIQAAUK2hLHCQCdAQAQAAUK2hLHCQCdAQA1AAQKgSoAAxAACQrZHM4ZAP0CABAACQrZHM4ZAP0CABIAAQpKDWxuATcAAAAA.Frogchi:BAAANQAECgQIBwAAAA==.Frostbité:BAAANQADCggIGgAAAA==.Fruit:BAAANQAECgIIBAAAAA==.',
Fu='Fubarut:BAAANQABCggIEQAAAA==.Fumikiko:BAAANQADCgYICgABNQAECgcICAACAAAAAA==.Fuzzbâll:BAAANQABCgYICQAAAA==.',
['Fí']='Físh:BAAANQADCgcICAABNQAECgcICAACAAAAAA==.',
Ga='Gali:BAAANQAECgEIAQAAAA==.Gargybyn:BAAANQADCgUIBwAAAA==.',
Gi='Girliepop:BAAANQADCggIEAAAAA==.',
Gl='Glaistiguain:BAABNQAECoEkAAQTAAcKbiPLAgDHAgATAAcKRyPLAgDHAgAUAAMKeSGJKgAdAQAOAAEKjxizGAFMAAABNQAECggILwAEAOMgAA==.Glifin:BAAANQAECgYIBgAAAA==.Glizzeldra:BAAANQADCgUIBQAAAA==.Gloomstalkin:BAAANQAECgIIBgABNQAECggIIgAVAKgSAA==.Glynna:BAAANQADCgUIBQAAAA==.',
Gr='Gr:BAABNQAECoEaAAIHAAcKdQrmPgCPAQAHAAcKdQrmPgCPAQAAAA==.Gryffs:BAABNQAECoEYAAMWAAgK4BpdCgByAgAWAAgK4BpdCgByAgALAAcKQguNswBtAQAAAA==.',
Gu='Guanino:BAAANQADCgYIBgAAAA==.Gutts:BAAANQADCggIDgABNQAECgcIHAAIAG8gAA==.',
Gw='Gworg:BAAANQADCgEIAQAAAA==.',
['Gì']='Gìzmo:BAAANQAECgQIBQAAAA==.',
Ha='Halartion:BAABNQAECoEUAAILAAgKixvlVABwAgALAAgKixvlVABwAgAAAA==.Happirogue:BAAANQAECgYIBgABNQAFFAYIEwAXAGwbAA==.Haruun:BAAANQAECgMIAgAAAA==.',
He='Helridden:BAAANQAECgYIBgAAAA==.Hesmydaddy:BAABNQAECoEgAAIMAAgKgwWTewBuAQAMAAgKgwWTewBuAQAAAA==.',
Ho='Hoztok:BAAANQAECgQIBAAAAA==.',
Ic='Icemann:BAAANQABCggICAAAAA==.',
Im='Imherdaddy:BAABNQAECoEiAAIVAAgKqBLyQwDMAQAVAAgKqBLyQwDMAQAAAA==.',
It='Itakemeds:BAAANQADCgYJDAABNQAECgMIBAACAAAAAA==.',
Ja='Jaderean:BAAANQAECgMJAwAAAA==.Jarrack:BAABNQAECoEaAAMYAAcKyxQRHADlAAAGAAcKcBDBzwDBAQAYAAQK+RYRHADlAAAAAA==.Jaye:BAAANQABCgUICQAAAA==.',
Je='Jessicae:BAABNQAECoEdAAMMAAcKvxdgYwDDAQAMAAcKvxdgYwDDAQAZAAEKfg04JAA4AAAAAA==.Jeuno:BAAANQADCggIDgABNQAECgcICAACAAAAAA==.',
Ji='Jivederpy:BAAANQAECgcIDgAAAA==.',
Ju='Juicybooty:BAAANQADCgUIBgAAAA==.Junazeena:BAAANQAECgYICwAAAA==.',
Ka='Kayfabe:BAAANQAECgcIEgAAAA==.',
Ke='Keirasti:BAAANQAECgQIBwAAAA==.Keishilda:BAAANQAECgEIAQAAAA==.Keladria:BAAANQAECgQIBwAAAA==.Kelirra:BAAANQAECgEIAQAAAA==.Kenel:BAABNQAECoEhAAIaAAcKCBDIRQCsAQAaAAcKCBDIRQCsAQAAAA==.Kerea:BAABNQAECoEaAAIbAAcKcwMHQQDoAAAbAAcKcwMHQQDoAAAAAA==.Kermitt:BAAANQABCggIEAAAAA==.Keyarga:BAAANQADCgYICgABNQAECgUIBgACAAAAAA==.',
Kh='Khazadoom:BAAANQAECgQIBwAAAA==.Khazargon:BAAANQADCggIFQAAAA==.',
Ki='Kicken:BAAANQAECgYIDwAAAA==.Kiitsuna:BAAANQADCgYIBgAAAA==.Kittyflerp:BAAANQADCgEJAQAAAA==.Kittyperry:BAAANQAECggIDgAAAA==.',
Ko='Korthelan:BAABNQAECoEiAAIcAAgKthNzIQAhAgAcAAgKthNzIQAhAgAAAA==.Kothara:BAABNQAECoEZAAIBAAcKDQ/jiADIAQABAAcKDQ/jiADIAQAAAA==.',
Kr='Krimzin:BAACNQAFFIEMAAIBAAUKNBUbCAChAQABAAUKNBUbCAChAQA1AAQKgScAAgEACQo+JZAWACkDAAEACQo+JZAWACkDAAAA.Krystine:BAAANQAECgIIBAAAAA==.',
Ks='Kserasera:BAABNQAECoEdAAIaAAgKwhC6PwDSAQAaAAgKwhC6PwDSAQAAAA==.',
Ku='Kuball:BAABNQAECoEcAAIIAAcKbyAXDQCVAgAIAAcKbyAXDQCVAgAAAA==.Kukuruku:BAAANQAECgUIBQAAAA==.Kumari:BAAANQAECgIIAgAAAA==.',
['Kî']='Kîllara:BAAANQADCgUIBQAAAA==.',
Le='Lebronjames:BAABNQAECoEeAAIEAAgKTiBtHgC3AgAEAAgKTiBtHgC3AgAAAA==.Letheos:BAABNQAECoEwAAIVAAkK/iKPCQBeAwAVAAkK/iKPCQBeAwAAAA==.',
Li='Librarte:BAAANQAECgcIEQAAAA==.Limmewinks:BAAANQADCgUIBQAAAA==.Litty:BAAANQAECgQIDAAAAA==.',
Lo='Loalu:BAAANQAECgEIAQAAAA==.Locktärd:BAAANQAECgQJBAABNQAFFAUICgAVAOEYAA==.Lox:BAABNQAECoEZAAIUAAcKbQtBHwBsAQAUAAcKbQtBHwBsAQAAAA==.',
Lu='Lunatick:BAAANQAECgIIAQABNQAECggIAQACAAAAAA==.',
Ly='Lydirn:BAAANQADCgUIBgAAAA==.',
['Lí']='Lítterbox:BAAANQAECgIIAgAAAA==.',
Ma='Magedzen:BAAANQADCgEIAQAAAA==.Magicguy:BAABNQAECoEYAAIGAAYKiRwKswD6AQAGAAYKiRwKswD6AQAAAA==.Mahariel:BAAANQAECgUICgAAAA==.Mahdy:BAABNQAECoEmAAISAAgK5RSIgAD3AQASAAgK5RSIgAD3AQAAAA==.Mahoe:BAAANQADCgEIAQAAAA==.Malva:BAAANQAECgYIEQAAAA==.Marcie:BAABNQAECoEaAAIaAAcKJAq2VABbAQAaAAcKJAq2VABbAQAAAA==.Marracopa:BAAANQABCgYIBwAAAA==.Martinriggz:BAAANQAECgEIAwAAAA==.',
Mc='Mchammer:BAAANQADCgIIAgAAAA==.',
Me='Meatyloaf:BAAANQAECgQIBwAAAA==.Medsedation:BAABNQAECoEkAAIMAAgKZg7AZAC+AQAMAAgKZg7AZAC+AQAAAA==.Melkedrik:BAAANQAECgQIBwAAAA==.Melleren:BAAANQAECgcICAAAAA==.Meridiane:BAAANQADCgEIAQAAAA==.',
Mi='Mirei:BAAANQAECgYIDwAAAA==.',
Mo='Moolander:BAAANQADCgUIBQAAAA==.Moovidlin:BAAANQAECgUICQAAAA==.',
Mu='Mushhead:BAAANQAECgYJDwAAAA==.Mustepin:BAAANQADCgUJBQABNQAECggIGgAdABIYAA==.',
My='Mythantherox:BAAANQADCgcIDQABNQAECgkJJQAeAPgjAA==.',
Na='Nanlaria:BAAANQADCgEIAQAAAA==.',
Ne='Neon:BAAANQAECgMIAwAAAA==.Nethershade:BAAANQAECgYICQAAAA==.Netherstörm:BAAANQAECgMIBgAAAA==.',
Ni='Niclea:BAAANQADCgUIBQAAAA==.Nightelm:BAAANQAECgcICAAAAA==.Niraani:BAAANQADCggICwAAAA==.',
No='Noborû:BAAANQAECgQIBAABNQAECggIGgAEAP4dAA==.Noslien:BAAANQAECgEIAQAAAA==.Nostradamuz:BAABNQAECoEdAAIfAAgK1BkGEwBNAgAfAAgK1BkGEwBNAgAAAA==.',
Ny='Nymneria:BAAANQAECgQIBwAAAA==.Nyxiera:BAABNQAECoEkAAIWAAgKGxSBEQDgAQAWAAgKGxSBEQDgAQABNQAECggIKQAWAC0ZAA==.Nyxstonia:BAABNQAECoEpAAQWAAgKLRk1DQAzAgAWAAgKLRk1DQAzAgAdAAIK7gYNJgBbAAALAAEK2AFGRQEhAAAAAA==.',
['Nä']='Nämi:BAAANQAECgIIAwAAAA==.',
Ol='Olierra:BAAANQADCgUIBQAAAA==.',
Om='Omnissiah:BAAANQABCgYIBgAAAA==.',
Or='Oreshin:BAAANQAECgUIBgAAAA==.Ornac:BAAANQADCgMIAwAAAA==.Orphantrope:BAAANQABCgEIAQAAAA==.',
Ot='Otto:BAABNQAECoEYAAISAAcKPhDtpwCYAQASAAcKPhDtpwCYAQAAAA==.Ottomagus:BAAANQADCgcIDAAAAA==.',
Pa='Palliate:BAAANQADCgYIBgABNQADCgUIBQACAAAAAA==.Pampoovy:BAEANQADCgYJBgABNQAECggIHgAgAKkVAA==.',
Pe='Persephoneia:BAABNQAECoEeAAINAAcKQgoIMwBiAQANAAcKQgoIMwBiAQAAAA==.',
Ph='Phobos:BAAANQABCgIIAgAAAA==.',
Pi='Piperclip:BAAANQADCgYIBgAAAA==.',
Po='Poraichu:BAAANQABCgYIBgAAAA==.',
Pr='Preacherman:BAAANQAECgMIBQAAAA==.Priority:BAAANQADCgQIBAAAAA==.',
Pu='Purplevane:BAAANQAECgMIAwAAAA==.',
Ra='Rabies:BAAANQABCggICwAAAA==.Rageoverrun:BAAANQAECgIIAgAAAA==.Ragequit:BAAANQAECgMJAwABNQAECgYIEgACAAAAAA==.Ranson:BAAANQAECggICAAAAA==.Ravenloare:BAAANQADCgYIDwAAAA==.',
Re='Remuz:BAAANQADCgYIBgAAAA==.',
Ri='Rilz:BAABNQAECoEeAAMEAAcKAyBSKgBsAgAEAAcKAyBSKgBsAgAFAAIKOBBafgBrAAAAAA==.',
Ro='Rockasham:BAABNQAECoEcAAIPAAgKuAhgcwCXAQAPAAgKuAhgcwCXAQAAAA==.Rodgerwabbet:BAAANQADCgMIAwAAAA==.Rottn:BAAANQAECgYIEgAAAA==.',
Sa='Safmen:BAAANQAECggICAAAAA==.Saintdivine:BAAANQADCgEIAQAAAA==.Sanikoa:BAAANQAECgUIBQAAAA==.Saraid:BAABNQAECoEeAAMbAAcKUxDNLACAAQAbAAcKUxDNLACAAQAaAAMK9xBZgQCdAAAAAA==.Saravase:BAAANQADCgcICAAAAA==.Saurot:BAAANQADCgcICQAAAA==.',
Se='Sev:BAAANQAECgEIAQAAAA==.Señorcleave:BAAANQADCgQICgAAAA==.',
Sh='Shadk:BAEBNQAECoEfAAMVAAcKWhj7PQDoAQAVAAcKWhj7PQDoAQAFAAIKAABnrgAAAAAAAA==.Shadowstorm:BAABNQAECoEiAAIhAAgKHRe+DgBkAgAhAAgKHRe+DgBkAgAAAA==.Shelal:BAAANQADCggICAAAAA==.Shiki:BAAANQADCggIDwABNQAECgYIDwACAAAAAA==.Shinoto:BAAANQADCgYIDQABNQAECgYIDQACAAAAAA==.',
Si='Silvein:BAACNQAFFIEIAAIQAAUKYRGmCgCPAQAQAAUKYRGmCgCPAQA1AAQKgRoAAxAACQqoITAOAEkDABAACArdIzAOAEkDAB8AAQrbCnNqACUAAAAA.Silverpower:BAAANQADCgIIAgAAAA==.',
Sk='Skyë:BAAANQADCgcIBwABNQAECgcICAACAAAAAA==.',
Sn='Snowynn:BAAANQADCgEIAQAAAA==.',
So='Sorrybro:BAAANQADCgcICQAAAA==.',
Sp='Spycatcher:BAAANQADCgMIBAAAAA==.Spyro:BAABNQAECoEaAAQeAAkKoRA/HABsAQAeAAcKew0/HABsAQAiAAUKBQ8/LAAgAQAjAAQKXAsRFADEAAAAAA==.Spyroo:BAAANQAECgcICwAAAA==.',
Sr='Sron:BAABNQAECoEeAAIBAAcKaRglbwAHAgABAAcKaRglbwAHAgAAAA==.',
St='Stankboy:BAAANQABCgQIBwAAAA==.',
Sw='Swooze:BAABNQAECoEZAAMGAAgKJxb3pwARAgAGAAgKBhX3pwARAgAYAAEKgBLSPAA7AAAAAA==.',
Sy='Syndar:BAAANQADCgQIBAABNQAECgYIEgACAAAAAA==.',
Sz='Szuzette:BAAANQAECgMIBQABNQAECgQICQACAAAAAA==.',
Ta='Tankcontrols:BAAANQAECgEIAQAAAA==.Tarlyn:BAAANQAECgQICQABNQAECggIDQACAAAAAA==.',
Te='Temuadêrna:BAAANQADCgYIBgAAAA==.',
Th='Thaenet:BAAANQADCgUIBwAAAA==.Thevelo:BAAANQAECgUIBQABNQAECgUIBgACAAAAAA==.Thunderkatze:BAABNQAECoEaAAIhAAkKnAmMEwAKAgAhAAkKnAmMEwAKAgAAAA==.Thánátós:BAAANQAECgMIAwAAAA==.',
To='Topu:BAAANQAECgUIEAABNQAECgYIBgACAAAAAA==.',
Tr='Tradarynn:BAAANQADCgYIBgAAAA==.',
Tw='Twinkles:BAAANQADCgMIAwAAAA==.',
Un='Unacceptable:BAAANQAECgUIDgAAAA==.',
Ur='Urais:BAAANQAECgMIAwABNQAECgkJKwAKAFYkAA==.',
Us='Usdaprime:BAABNQAECoEWAAIaAAgKmAx4RACzAQAaAAgKmAx4RACzAQAAAA==.',
Va='Valhalia:BAAANQAECgYIDQAAAA==.Vanira:BAAANQADCgYIBgAAAA==.Vanrien:BAAANQADCggICAAAAA==.',
Ve='Velinariae:BAAANQADCgMIBAAAAA==.Vengful:BAAANQAECgYIEgAAAA==.Vexy:BAAANQADCgMJBQAAAA==.',
Vh='Vhalúryn:BAAANQAECgQIBwAAAA==.',
Vi='Vira:BAAANQADCgIIAgAAAA==.',
Vo='Vorumbrae:BAAANQAECgUIBwAAAA==.',
Wa='Wali:BAABNQAECoEZAAIOAAcKihQqeQDNAQAOAAcKihQqeQDNAQAAAA==.',
Wh='Whatupbruh:BAAANQAECgQIBAAAAA==.',
Wi='Wildefaux:BAAANQADCggICAAAAA==.',
Wo='Wooties:BAAANQAECgUIBQABNQAECgkJGgADAPcXAA==.',
Wy='Wyleriya:BAABNQAECoEYAAIUAAgK5wo3FQC7AQAUAAgK5wo3FQC7AQAAAA==.',
Xc='Xcella:BAAANQADCggIKQAAAA==.',
Xe='Xenophon:BAAANQADCgcIBwAAAA==.',
Xu='Xurael:BAAANQAECgUIBwAAAA==.',
Ye='Yelhsa:BAAANQAECgIIAwAAAA==.Yelizaveta:BAAANQAECgMICAAAAA==.',
Yl='Ylfcwen:BAAANQADCgYIBgAAAA==.',
Yu='Yukiri:BAAANQAECgQIBQAAAA==.Yumei:BAAANQAECgYIBgAAAA==.',
Za='Zalarah:BAAANQAECgQIBwAAAA==.Zardan:BAAANQAECgMIBgAAAA==.',
Ze='Zeppik:BAAANQADCgQIBAAAAA==.',
Zu='Zuggerker:BAABNQAECoEaAAILAAcKhBqbbwAkAgALAAcKhBqbbwAkAgAAAA==.',
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
