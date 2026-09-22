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

local lookup = {'Warrior-Arms','Warrior-Fury','Priest-Holy','Warlock-Destruction','Warlock-Demonology','DemonHunter-Vengeance','DemonHunter-Devourer','Warrior-Protection','Evoker-Devastation','Unknown-Unknown','Paladin-Holy','DemonHunter-Havoc','Druid-Restoration','Hunter-BeastMastery','Shaman-Restoration','Paladin-Retribution','Monk-Windwalker','Shaman-Elemental','DeathKnight-Unholy','Mage-Arcane','Monk-Mistweaver','Warlock-Affliction','Monk-Brewmaster','DeathKnight-Frost','Rogue-Subtlety','Rogue-Assassination','Mage-Frost','Priest-Shadow','DeathKnight-Blood',}
local provider = {region='US',realm='Archimonde',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aanaleaa:BAAANQADCggIGwAAAA==.',
Ad='Ad:BAABNQAECoEXAAMBAAkKTBrQKgDCAgABAAkKTBrQKgDCAgACAAIK+AT9HQBNAAAAAA==.Adellon:BAAANQAECgcIEwAAAA==.Adhar:BAAANQADCgQIBAAAAA==.Adrielle:BAAANQAECgIJAgAAAA==.',
Ak='Akakage:BAAANQAECgUICAAAAA==.Akutoku:BAAANQAECgQJBAAAAA==.',
An='Anaki:BAAANQADCggIDAAAAA==.Annakkin:BAAANQAECgQJCwAAAA==.',
Ar='Ar:BAABNQAECoEUAAIDAAgKdgkUSwCyAQADAAgKdgkUSwCyAQABNQAECgkJFwABAEwaAA==.Archon:BAABNQAECoEXAAIBAAcKbRvdSQBBAgABAAcKbRvdSQBBAgAAAA==.Arienca:BAABNQAECoEYAAMEAAgKuAr/EgDBAQAEAAgKuAr/EgDBAQAFAAIKzQHd2gBGAAAAAA==.',
At='At:BAAANQAECgEIAQABNQAECgkJFwABAEwaAA==.',
Ba='Barbato:BAAANQADCgcICQAAAA==.',
Be='Beavesfault:BAAANQADCgYIBgAAAA==.Beldent:BAAANQADCgYICQAAAA==.Bepis:BAABNQAECoEbAAIGAAgK2x+PAgDoAgAGAAgK2x+PAgDoAgAAAA==.',
Bi='Bigleif:BAAANQADCgIIAgAAAA==.Bitsakura:BAAANQADCgUICwAAAA==.',
Bl='Blazerunner:BAAANQAECgYJEQAAAA==.Blitzkreig:BAAANQADCggIFQAAAA==.Blured:BAABNQAECoEbAAIHAAgKDiAcCwD/AgAHAAgKDiAcCwD/AgAAAA==.',
Bo='Booty:BAABNQAECoEbAAIIAAgK9h7YBADGAgAIAAgK9h7YBADGAgAAAA==.Bort:BAABNQAECoEZAAIJAAgKLAnwEwCwAQAJAAgKLAnwEwCwAQAAAA==.',
Br='Brevyn:BAAANQAECgYJBgAAAA==.',
Bu='Bubblebutt:BAAANQAECgIIAgABNQAECgcIBwAKAAAAAA==.Bulla:BAAANQAECgEJAQAAAA==.Bung:BAABNQAECoEbAAILAAgKshcwMAA+AgALAAgKshcwMAA+AgAAAA==.Buum:BAAANQADCggIGwAAAA==.',
['Bä']='Bämba:BAAANQADCgcIDQABNQAECgMIBQAKAAAAAA==.',
Ca='Cali:BAACNQAFFIELAAMMAAYK1QmaBABxAQAMAAUKKweaBABxAQAHAAMKWAqNBwDkAAA1AAQKgSUAAwcACQpkHyEKABEDAAcACQpdHyEKABEDAAwABQqGGxQsAKYBAAAA.Calipari:BAAANQADCgQIBAABNQAFFAYICwAMANUJAA==.Catamara:BAAANQADCggICQAAAA==.',
Ce='Cephus:BAABNQAECoEgAAINAAkKgBGWFAAkAgANAAkKgBGWFAAkAgAAAA==.Cerafina:BAAANQADCgUICgAAAA==.',
Ch='Chayse:BAABNQAECoEjAAIOAAkK9SAwCgBZAwAOAAkK9SAwCgBZAwAAAA==.Chumléé:BAAANQADCgEIAQAAAA==.Chérry:BAABNQAECoEjAAMHAAkK+h/WCgAEAwAHAAkKJh3WCgAEAwAMAAIKHhxjTgCdAAAAAA==.',
Cl='Climpwimp:BAAANQADCgUIBQAAAA==.',
Co='Conneer:BAAANQADCgUIBQAAAA==.Consham:BAABNQAECoEZAAIPAAkKDxhmGwCyAgAPAAkKDxhmGwCyAgAAAA==.',
Cy='Cynestra:BAAANQADCggIFAAAAA==.Cyni:BAAANQAECgEIAQABNQAECgkJGQALAM4cAA==.',
Da='Dadudadu:BAABNQAECoEnAAIQAAkKQBvnJQDLAgAQAAkKQBvnJQDLAgAAAA==.Daftmonk:BAABNQAECoEyAAIRAAkKJCV7AQDCAwARAAkKJCV7AQDCAwAAAA==.Darj:BAAANQAECgcJDAAAAA==.Darmonevil:BAAANQAECgEJAQAAAA==.Dasarus:BAAANQADCgYIDAAAAA==.Dauntless:BAAANQADCggIFQAAAA==.',
De='Deth:BAAANQADCgYIBgABNQAECgQIBAAKAAAAAA==.Dethblades:BAAANQADCgYIBgABNQAECgQIBAAKAAAAAA==.Dethblow:BAAANQAECgQIBAAAAA==.Dethcurse:BAAANQADCgYIBgABNQAECgQIBAAKAAAAAA==.Deuterium:BAAANQADCgYIBgAAAA==.',
Di='Disturbbed:BAAANQABCgIJAwAAAA==.Diwa:BAABNQAECoEYAAMSAAkKMwdzfQAeAQASAAcKKwNzfQAeAQAPAAcKrgFBgQABAQAAAA==.',
Dk='Dklot:BAAANQAECgYIEgAAAA==.',
Do='Doomkin:BAAANQAECgEIAQAAAA==.',
Dr='Draken:BAAANQAECgQIBAAAAA==.Drama:BAAANQAECgMIAwAAAA==.Draviin:BAAANQAECgYIEwAAAA==.Dreadgrave:BAAANQAECgYICwAAAA==.Drequan:BAAANQADCgEIAQAAAA==.Driade:BAAANQADCgIJAgABNQAECgkJGQALAM4cAA==.',
Du='Dunkyn:BAAANQAECgYIDwAAAA==.',
El='Elendryl:BAAANQADCgUJCgAAAA==.',
En='Enkeke:BAABNQAECoEZAAITAAgKsxqLHgBwAgATAAgKsxqLHgBwAgAAAA==.',
Ep='Epitaph:BAAANQADCggIDAAAAA==.',
Er='Erena:BAAANQADCgUIBQABNQABCgIIAgAKAAAAAA==.Eresanna:BAABNQAECoEZAAIUAAgKSxBqhAAMAgAUAAgKSxBqhAAMAgAAAA==.Erf:BAABNQAECoEZAAIVAAgKeA17FACtAQAVAAgKeA17FACtAQAAAA==.Erinis:BAAANQADCggICQABNQAECggIDgAKAAAAAA==.',
Ex='Extremefear:BAAANQAECgMJBwAAAA==.',
Fe='Fearious:BAACNQAFFIEFAAMFAAMKxSTpDwDYAAAFAAIKzyTpDwDYAAAEAAEKsiSxCwBwAAA1AAQKgRYABAUACQpmJIIuAGYCAAUABgq1JIIuAGYCAAQAAgpYIwc6ALYAABYAAQqqJN4WAGsAAAAA.Feroond:BAAANQAECgUJCAAAAA==.Feyrah:BAAANQADCgUIBQAAAA==.',
Fr='Frogteeth:BAAANQAECgIIAgAAAA==.Frozath:BAAANQADCggICQAAAA==.',
Fu='Furibeav:BAAANQADCgQIBQABNQADCgYIBgAKAAAAAA==.Fussypants:BAAANQAECgUIDQAAAA==.',
Ga='Gallindral:BAABNQAECoEcAAIHAAgKghCOHQARAgAHAAgKghCOHQARAgAAAA==.Gatito:BAAANQAECgcIBwAAAA==.',
Ge='Genericnpc:BAAANQADCggIFwAAAA==.Geobrando:BAAANQAECgcIEgAAAA==.',
Gg='Ggbrews:BAAANQAECgQIBAAAAA==.',
Gn='Gnosh:BAAANQADCggIGwAAAA==.',
Go='Goofypally:BAAANQAECgEIAgABNQAECggIEAAKAAAAAA==.',
Gr='Grippindeez:BAAANQAECgYIBgAAAA==.',
Gu='Guidosarduci:BAAANQAECgUIDgAAAA==.Guiseppe:BAAANQAECgQIEAAAAA==.Gungfu:BAAANQADCgYIBgAAAA==.',
Ha='Harle:BAAANQADCggIGwAAAA==.Hatari:BAAANQADCgEIAQAAAA==.',
He='Heavyg:BAABNQAECoE3AAIBAAkKgxLJRwBJAgABAAkKgxLJRwBJAgAAAA==.',
Ho='Holyshortguy:BAAANQAFFAEJAQAAAA==.',
Hu='Hustlermag:BAABNQAECoEZAAQWAAcK8xUEDAAfAQAWAAQKtRQEDAAfAQAEAAQKzRVhKAAPAQAFAAQKoBDOmQD/AAAAAA==.',
Ic='Icelmo:BAABNQAECoEbAAIBAAkKbhj9MwCYAgABAAkKbhj9MwCYAgAAAA==.',
Im='Impact:BAAANQADCgIJAgABNQAFFAMIBgASAOwUAA==.',
Ja='Jaskow:BAABNQAECoEYAAINAAgKfhuRDgCAAgANAAgKfhuRDgCAAgAAAA==.Jaymick:BAAANQADCggIGQAAAA==.',
Ju='Jusdatip:BAAANQAECgYJCwAAAA==.',
Ka='Kai:BAAANQABCgEIAQAAAA==.Kameshoga:BAAANQAECgEIAQAAAA==.Karten:BAAANQAECgEIAQAAAA==.',
Ke='Keir:BAAANQADCggJDAAAAA==.',
Ki='Killjoyss:BAAANQADCgYIBgAAAA==.',
Kr='Krag:BAAANQADCgcICQABNQAECggIGQAXAPkkAA==.Krasis:BAAANQAECggIDAAAAA==.Krazermonk:BAABNQAECoEaAAIRAAgKbxfdFQAdAgARAAgKbxfdFQAdAgAAAA==.Kristysavage:BAABNQAECoEaAAIOAAgKzh8LEwAMAwAOAAgKzh8LEwAMAwAAAA==.',
Ku='Kumpell:BAAANQABCgEIAQAAAA==.',
La='Lanc:BAAANQADCggIFwAAAA==.',
Le='Leafsrock:BAAANQADCgEIAQAAAA==.Lealta:BAAANQAECgQIBQABNQAECgkJJAANABEmAA==.',
Li='Lichdawg:BAACNQAFFIEGAAIYAAMKdBaABQD9AAAYAAMKdBaABQD9AAA1AAQKgRwAAhgACQrhIjoLAPUCABgACQrhIjoLAPUCAAAA.Lilthorn:BAAANQADCggICQAAAA==.',
Lo='Lofometa:BAAANQADCgQIBAAAAA==.Lover:BAAANQAECgEIAQAAAA==.',
Lt='Ltroflcopter:BAAANQAECgEIAQABNQAFFAEJAQAKAAAAAA==.',
Lu='Lubu:BAAANQAECggIDgAAAA==.Lumen:BAAANQADCggIFQAAAA==.Lumiette:BAAANQAECgMJBAAAAA==.',
Lv='Lvispriestly:BAAANQAECgEJAQABNQABCgIIAgAKAAAAAA==.',
Ly='Lynai:BAAANQAECgUJCQAAAA==.',
['Lá']='Lándwhale:BAABNQAECoEjAAMZAAkK/yQSAQC+AwAZAAkK3yQSAQC+AwAaAAEK/yU0VABsAAAAAA==.',
['Læ']='Lægolas:BAAANQAECgEIAQAAAA==.',
['Lö']='Löver:BAAANQADCggICAABNQAECgEIAQAKAAAAAA==.',
Ma='Macktimus:BAAANQAECgYICQAAAA==.Madeinchina:BAAANQADCgMJAwAAAA==.Magictonyp:BAAANQADCgUJDgAAAA==.Makili:BAABNQAECoFDAAMUAAkKTSHmGABUAwAUAAkKTSHmGABUAwAbAAEKeAyHMwAxAAAAAA==.Malonion:BAAANQADCgYIBgAAAA==.',
Mc='Mcfire:BAAANQAECgUIBgAAAA==.',
Me='Melotte:BAAANQADCggIGgAAAA==.Mepha:BAAANQADCgYJBgAAAA==.Merlîn:BAAANQADCgUICwAAAA==.',
Mi='Mickallv:BAAANQADCgcIBwAAAA==.',
Mo='Moga:BAAANQAECgEJAQAAAA==.',
My='Mylodon:BAAANQABCgIIAwAAAA==.Mysternia:BAAANQADCggIGwAAAA==.',
Ni='Niade:BAABNQAECoEZAAMLAAkKzhzyDwAMAwALAAkKzhzyDwAMAwAQAAUKegcCuAD1AAAAAA==.',
No='Notorckrag:BAABNQAECoEZAAIXAAgK+SQjAgBfAwAXAAgK+SQjAgBfAwAAAA==.',
Ny='Nythor:BAAANQADCgMIAwAAAA==.Nythoz:BAAANQADCggICAABNQAECgkJIQAcAGwkAA==.',
['Nê']='Nêz:BAAANQADCgYIDAAAAA==.',
Oa='Oathbringer:BAAANQADCgYICQAAAA==.',
Od='Odimeer:BAAANQAECgMJAwAAAA==.',
Of='Offbrandcleo:BAAANQABCgcICAAAAA==.',
Ol='Oldrecipe:BAAANQAECgcIEwAAAA==.Oliange:BAAANQAECgMIBQAAAA==.',
Oo='Oopsrofl:BAAANQAECgEIAgAAAA==.',
Or='Originalgank:BAABNQAECoEbAAMUAAgKNyAsMgD3AgAUAAgKNyAsMgD3AgAbAAEK9RE1MQA2AAAAAA==.',
Ot='Otoha:BAAANQADCgYIBgAAAA==.',
Pe='Peachcobbler:BAAANQAECgcIDQAAAA==.',
Pi='Pinkchadp:BAAANQADCgcJBwAAAA==.Pinkk:BAAANQAECgIJAgAAAA==.',
Pl='Plaguerism:BAAANQAECggJEwABNQAFFAMIBQAFAMUkAA==.',
Po='Poo:BAABNQAECoEfAAIaAAkK5R/gBwANAwAaAAkK5R/gBwANAwAAAA==.Pooq:BAAANQAECgEIAQAAAA==.Popcorn:BAAANQADCgEIAQABNQAECgIJAgAKAAAAAA==.',
Pr='Promkang:BAAANQADCgUICQAAAA==.',
['Pâ']='Pâiñ:BAAANQADCggJEAAAAA==.',
Qm='Qmpell:BAAANQADCgYIBgAAAA==.',
Ra='Ragel:BAAANQAECgYJBgAAAA==.Rahor:BAAANQAECgIJBAAAAA==.Rainesage:BAAANQAECgMJBwAAAA==.Ralphel:BAAANQADCggIGgAAAA==.Razzberry:BAAANQADCgQIBAAAAA==.',
Rh='Rhubarb:BAAANQAECgYIEAAAAA==.',
Ro='Rohiem:BAAANQADCgMIAwAAAA==.',
Ry='Rylosh:BAACNQAFFIEIAAINAAQK+wpEBAAmAQANAAQK+wpEBAAmAQA1AAQKgSoAAg0ACQowEl0SAEMCAA0ACQowEl0SAEMCAAAA.',
Sa='Sabot:BAAANQADCggIGwAAAA==.Sashafierce:BAAANQAECgEIAQABNQAECgIJAgAKAAAAAA==.',
Sc='Scottpaladin:BAAANQAECgQJBwAAAA==.',
Se='Seath:BAAANQADCgYIEAABNQAECggIGAATAI4cAA==.',
Sh='Shamerica:BAABNQAECoEiAAISAAkK6iEXDABaAwASAAkK6iEXDABaAwAAAA==.Shielderon:BAAANQADCgYIBgAAAA==.Shmooythefox:BAAANQADCgYICgAAAA==.Shòckwave:BAAANQAECgEJAwAAAA==.',
Sk='Skilleaz:BAABNQAECoEXAAIdAAkKpCFoCgAxAwAdAAkKpCFoCgAxAwAAAA==.',
Sl='Slagothor:BAABNQAECoEYAAITAAgKZwX8QwCAAQATAAgKZwX8QwCAAQAAAA==.',
So='Soultax:BAAANQADCggJEQAAAA==.',
Sp='Spekaleks:BAAANQAECgIIAwAAAA==.Spinfat:BAABNQAECoEeAAIRAAkKnyEOBQBSAwARAAkKnyEOBQBSAwAAAA==.Spiritbox:BAAANQAECgQIBAAAAA==.',
St='Stapler:BAAANQAECgYIEQAAAA==.Starbux:BAAANQADCgUIDQABNQAECgQICAAKAAAAAA==.',
Su='Sugarr:BAAANQADCgYIBgAAAA==.',
Sy='Syb:BAAANQADCgYIDAAAAA==.',
Ta='Taeyang:BAAANQAECgcIEgAAAA==.Tamerlein:BAAANQADCgUIBwAAAA==.Tankadin:BAAANQADCgcIBwABNQAECgUICQAKAAAAAA==.Tanookii:BAAANQAECgEIAgAAAA==.',
Te='Terraform:BAAANQADCgEIAQAAAA==.',
Th='Theinsider:BAAANQAECgQICAABNQAECggIGAATAI4cAA==.Theoutsider:BAABNQAECoEYAAMTAAgKjhw2JQA6AgATAAcKoBw2JQA6AgAYAAIKnRe1UgCaAAAAAA==.',
Ti='Timhair:BAAANQADCgUJBQAAAA==.Tindril:BAAANQADCgYIBgAAAA==.',
To='Toekneess:BAAANQAFFAEIAQAAAA==.Toekneezz:BAABNQAECoEXAAIVAAkKEx5PBAApAwAVAAkKEx5PBAApAwABNQAFFAEIAQAKAAAAAA==.Totemofbear:BAAANQAECgUJBgAAAA==.',
Tr='Trandis:BAABNQAECoEXAAIRAAgKpiOIBgAvAwARAAgKpiOIBgAvAwAAAA==.Tranza:BAAANQAECgUICQAAAA==.Trash:BAAANQAECgEIAQAAAA==.',
Tx='Tx:BAACNQAFFIEGAAISAAMK7BRxCgD+AAASAAMK7BRxCgD+AAA1AAQKgRsAAhIACQqZH/gTAA4DABIACQqZH/gTAA4DAAAA.',
Ty='Tyrannius:BAAANQADCgUIBQAAAA==.',
Ut='Uthros:BAAANQADCgMIAwABNQAECgYICwAKAAAAAA==.Utterchaos:BAAANQAECgQJBgAAAA==.',
Va='Vaporeon:BAAANQADCggIEQAAAA==.',
Ve='Vekris:BAAANQABCgIJAwAAAA==.',
We='Wematanye:BAAANQADCgMIAwABNQAECgQJBgAKAAAAAA==.Wetheals:BAAANQAECgMJBAAAAA==.',
Wi='Wimpykid:BAAANQADCgIIAgAAAA==.Winter:BAAANQADCgQIBAABNQAECgEIAQAKAAAAAA==.',
Wo='Worgnfreeman:BAAANQAECggIBgAAAA==.',
Wt='Wtfmonk:BAABNQAECoEfAAIVAAgKoxgqCwBvAgAVAAgKoxgqCwBvAgABNQAFFAEJAQAKAAAAAA==.',
Xa='Xazia:BAAANQADCgEIAQAAAA==.',
Xe='Xethani:BAAANQADCggIGwAAAA==.',
Xo='Xorcopressor:BAAANQAECgMIAwABNQAECgcIBwAKAAAAAA==.',
Xs='Xsaber:BAAANQADCggJFwAAAA==.',
Ya='Yazmo:BAABNQAECoEhAAIcAAkKbCR9AgCmAwAcAAkKbCR9AgCmAwAAAA==.',
Yu='Yushe:BAAANQAECgIJAgAAAA==.Yuuky:BAABNQAECoEbAAINAAgK7xhYEABkAgANAAgK7xhYEABkAgAAAA==.',
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
