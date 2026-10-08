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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Unknown-Unknown','Druid-Feral','Monk-Windwalker','DeathKnight-Frost','Druid-Restoration','Druid-Balance','Mage-Arcane','Priest-Holy','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','DeathKnight-Blood','Evoker-Preservation','Warrior-Arms','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','Rogue-Assassination','Warrior-Protection',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Accursed:BAABNQAECoEmAAIBAAkKmyOWAQB4AwABAAkKmyOWAQB4AwAAAA==.Activesloth:BAAANQADCgQJBAABNQAECggIGAACABUdAA==.',
Ad='Adekeai:BAAANQAECgQIDQAAAA==.Adol:BAAANQADCgYIBgAAAA==.',
Ae='Aelys:BAAANQAECgQIBQAAAA==.',
Al='Aleighta:BAAANQAECgcIDwAAAA==.Alenara:BAAANQADCgMJAwAAAA==.Allblond:BAAANQADCgYIBgAAAA==.Alyx:BAAANQADCgYIBgAAAA==.',
Am='Amouri:BAAANQABCgIIAgAAAA==.',
An='Anacreon:BAAANQAECgQIAgAAAA==.Anaiah:BAAANQADCggICwABNQAECgUIDAADAAAAAA==.',
Ar='Arcey:BAAANQADCgIIAgAAAA==.Arun:BAAANQADCgQIBAABNQAECgUIBgADAAAAAA==.',
As='Aspros:BAAANQAECggIDAAAAA==.',
At='Atlantis:BAAANQAECgMIBQAAAA==.Atonement:BAAANQAECgUIDAAAAA==.',
Av='Avengence:BAAANQADCgIIAgAAAA==.',
Ba='Badoussi:BAAANQAECgQIBAABNQAECgkJHAAEALIcAA==.Bananas:BAAANQAECgEIAQAAAA==.',
Be='Beansy:BAAANQADCgUICgAAAA==.Beefomancer:BAAANQAECgMIAwAAAA==.Belladin:BAABNQAECoEbAAICAAkKjReAVwBmAgACAAkKjReAVwBmAgAAAA==.Belzugaim:BAAANQAECgcIDgABNQADCgQIBwADAAAAAA==.',
Bi='Bipolarcurys:BAAANQAECgQICAAAAA==.Bismuth:BAAANQAECgUIBgAAAA==.',
Bl='Blamethedps:BAAANQAECgQIBgABNQAECgYIDwADAAAAAA==.Blameyomomma:BAAANQAECgUIBgABNQAECgYIDwADAAAAAA==.Blamezuko:BAAANQAECgYIDwAAAA==.Blite:BAAANQADCgUICQAAAA==.Blumoon:BAAANQADCgcIBwAAAA==.',
Bo='Bombakaap:BAACNQAFFIEFAAIFAAMKjQdqCwC0AAAFAAMKjQdqCwC0AAA1AAQKgRUAAgUACQo/GswRALECAAUACQo/GswRALECAAAA.Bomburst:BAAANQAECgIIAwAAAA==.Bonelespizza:BAACNQAFFIEFAAIGAAIKRBRZEACVAAAGAAIKRBRZEACVAAA1AAQKgSMAAgYACQqBIiELACsDAAYACQqBIiELACsDAAAA.Bonkthump:BAAANQABCggICwAAAA==.Boogiebabe:BAABNQAECoEgAAMHAAgKTha3HAAjAgAHAAgKTha3HAAjAgAIAAQKtwaNeAC/AAAAAA==.Bornix:BAAANQADCgUIBQABNQAECgcIKQAJANEUAA==.',
Br='Briaris:BAAANQAECgcIDwABNQAECgkJHwAEAJ4cAA==.Brosar:BAAANQAECgEIAQAAAA==.Brugaras:BAAANQABCgIIAgAAAA==.',
['Bê']='Bêz:BAAANQADCgUICwAAAA==.',
['Bë']='Bëz:BAAANQAECgUICgAAAA==.',
Ca='Cadzan:BAAANQABCgUIAwAAAA==.Caith:BAAANQABCgYIBAAAAA==.Calabretta:BAAANQADCgcIGQAAAA==.Cannan:BAAANQADCgYIBgAAAA==.Captcow:BAAANQABCgYIBgAAAA==.Caver:BAAANQADCgcIDQAAAA==.',
Ch='Charysmaa:BAAANQADCgUICQAAAA==.Cheoekar:BAAANQAECgUIBwABNQAFFAQICgAKADMYAA==.',
Co='Cobey:BAABNQAECoEcAAICAAgK6RZjdgARAgACAAgK6RZjdgARAgAAAA==.Coldrick:BAAANQADCgYIBgABNQAECgYIBgADAAAAAA==.Cosmicjay:BAACNQAFFIEFAAILAAMKygfDFwDUAAALAAMKygfDFwDUAAA1AAQKgR0AAgsACAokIBwjANwCAAsACAokIBwjANwCAAAA.Cosmicnova:BAAANQAECgYIDQABNQAFFAMIBQALAMoHAA==.',
Cr='Crow:BAAANQAECgQIBgAAAQ==.Crumpet:BAAANQAECggIAgAAAA==.',
Cu='Cursedknight:BAAANQADCgYIEgAAAA==.',
Da='Daegán:BAAANQADCgMIAwAAAA==.Daffodil:BAAANQAECgUICgAAAA==.Dalavian:BAAANQABCgQIBAAAAA==.Dannyhurt:BAAANQADCgcIDwAAAA==.Dantruis:BAACNQAFFIEGAAIMAAQKSxI9CwAyAQAMAAQKSxI9CwAyAQA1AAQKgSAAAgwACQrUH5oXAOcCAAwACQrUH5oXAOcCAAAA.Darlins:BAAANQADCgYIBgAAAA==.',
Di='Dianah:BAAANQADCgUICgAAAA==.Dinsfirë:BAAANQADCgIIAgAAAA==.Diothorn:BAAANQAECgUICwAAAA==.Divanas:BAAANQAECgQIBAAAAA==.Divi:BAAANQAECgUICAAAAA==.Divinium:BAAANQADCgQIBAABNQAECgUICAADAAAAAA==.',
Do='Dogfacethug:BAAANQABCggIEAAAAA==.Dorianna:BAAANQAECgUICQAAAA==.',
Dr='Dreamit:BAAANQADCgMIAwAAAA==.Drease:BAAANQADCgEIAQAAAA==.Drpepperz:BAAANQAECgEIAQAAAA==.Drunkdragon:BAAANQADCgYICwAAAA==.',
Ea='Earthtide:BAAANQADCgYJCwAAAA==.',
El='Elfsa:BAAANQADCgYIDAAAAA==.Ellayria:BAAANQAECgUICgAAAA==.Elymaria:BAAANQAECgQIBwAAAA==.',
Em='Emberrose:BAAANQAECgQICAAAAA==.',
En='Enhancedpant:BAAANQAECgYIDwAAAA==.Ensetral:BAAANQAECgQIBAAAAA==.',
Ev='Evernight:BAAANQAECgYIBgAAAA==.',
Fa='Fakedruid:BAAANQAECgEIAQABNQAECgMIAwADAAAAAA==.',
Fe='Feerahion:BAAANQADCgIIAgAAAA==.Feledris:BAAANQADCggIFAAAAA==.Felwynne:BAAANQAECgUIBwAAAA==.Feybeasts:BAAANQAECgQIBwAAAA==.Feárbomber:BAABNQAECoEYAAMNAAgK+hDqiQCfAQANAAcKpQ/qiQCfAQAOAAIK9g70VAB1AAAAAA==.',
Fh='Fhala:BAAANQADCggICAAAAA==.Fharia:BAAANQAECgUIBQAAAA==.',
Fi='Fivo:BAAANQABCgEIAQAAAA==.',
Fl='Flayr:BAAANQADCgIIAgAAAA==.Flopper:BAAANQABCgQIBAAAAA==.',
Fr='Fries:BAEANQAECggIBwABNQAECggIDAADAAAAAA==.',
Fu='Fusky:BAAANQAECgQIBwAAAA==.',
Fy='Fynn:BAABNQAECoEgAAIPAAkK0RlbCQDOAgAPAAkK0RlbCQDOAgAAAA==.',
Ga='Galadria:BAABNQAECoEnAAIIAAkK8BjuIQCgAgAIAAkK8BjuIQCgAgAAAA==.Garamond:BAAANQADCggICQAAAA==.Garnd:BAAANQADCgIIAgAAAA==.Garrish:BAAANQABCgQIBgAAAA==.',
Ge='Gerwik:BAAANQAECgIIAwAAAA==.',
Gi='Gimlih:BAAANQADCgEIAQAAAA==.',
Go='Gogetta:BAAANQAECgIIAgAAAA==.Goldenlock:BAAANQABCgYICQAAAA==.Govana:BAAANQAECgEIAQAAAA==.',
Gr='Greenleaves:BAAANQAECgIJAgAAAA==.',
Gu='Gummiwormz:BAAANQADCgQIBAAAAA==.',
Gy='Gyat:BAAANQADCgUJBwABNQAECgcIGQAMAJEaAA==.',
Ha='Hailin:BAABNQAECoEfAAICAAkKCBkVRwCaAgACAAkKCBkVRwCaAgAAAA==.Haunter:BAAANQAECgMIBAAAAA==.',
He='Heherawr:BAAANQADCgEIAQABNQADCgMIBgADAAAAAA==.',
Hi='Hima:BAAANQAECgUIBgAAAA==.',
Ho='Holyjenkins:BAAANQAECgQIBAAAAA==.Horngrry:BAAANQAECgUICgAAAA==.',
Il='Illtrytoheal:BAAANQADCgYICgAAAA==.',
Im='Imkillho:BAAANQAECgQJBAABNQAECgUICgADAAAAAA==.',
In='Inspiredbox:BAAANQAECgIIAgAAAA==.',
Ja='Jankismith:BAAANQAECgQIDQAAAA==.Jayy:BAAANQAECgUICgAAAA==.',
Jf='Jflyer:BAAANQADCgIIAgABNQAFFAMIBQALAMoHAA==.',
Ji='Jimin:BAAANQAECgcIDQAAAA==.Jitoflight:BAAANQADCgEIAQAAAA==.',
Jm='Jmajk:BAAANQABCgcICAAAAA==.',
Ka='Kachiko:BAAANQADCgQIAwAAAA==.Kaethis:BAAANQABCgUJBQAAAA==.Kaia:BAAANQAECgYIDAAAAA==.Kamchan:BAAANQAECgQIBQABNQAFFAMIBwAKAB8MAA==.Kamerth:BAAANQAECgUICgAAAA==.Kapbam:BAAANQADCggICgAAAA==.Karluron:BAAANQAECgQICgAAAA==.Karlutros:BAAANQAECgYIEwAAAA==.Katbaka:BAAANQADCggIDAABNQAFFAMICAAQAEklAA==.Katmoreahh:BAAANQADCgcIBwABNQAFFAMICAAQAEklAA==.Katuwuagain:BAACNQAFFIEIAAIQAAMKSSWDDQBKAQAQAAMKSSWDDQBKAQA1AAQKgSYAAhAACApEJVAMAD8DABAACApEJVAMAD8DAAAA.Kayonalani:BAAANQAECgEIAQAAAA==.Kazure:BAABNQAECoEbAAIRAAkKNQXGIgCRAQARAAkKNQXGIgCRAQAAAA==.',
Ke='Kelilia:BAABNQAECoEkAAISAAgKIRQydgARAgASAAgKIRQydgARAgAAAA==.Kenilar:BAAANQADCgYICAAAAA==.Keybricker:BAAANQADCgMIAwABNQAECgMIAwADAAAAAA==.',
Ko='Konga:BAAANQAECgQIBAAAAA==.Korngry:BAAANQADCgQIBAABNQAECgUICgADAAAAAA==.',
Kr='Krakkin:BAAANQADCgYIFAAAAA==.Krenil:BAAANQADCgQIBwAAAA==.',
Ku='Kuassei:BAAANQAECgcIEQAAAA==.',
Ky='Kyatto:BAAANQAECgcIDwABNQAFFAMICAAQAEklAA==.Kyllea:BAAANQAECgMIAwAAAA==.',
La='Laaksy:BAAANQAECgUIBwABNQAECgkJHwATAKccAA==.Ladraina:BAAANQADCgYIBgAAAA==.Landock:BAAANQADCgYIEgAAAA==.Larynnoelle:BAAANQAECgYIEQAAAA==.',
Le='Lebronjames:BAAANQAECgEIAQABNQAECgkJKgAGAPgeAA==.Leotart:BAABNQAECoEaAAIHAAYKRRAONwAvAQAHAAYKRRAONwAvAQAAAA==.Lesbians:BAAANQAECgQJCgAAAA==.Leyland:BAAANQADCgcIGwAAAA==.',
Li='Lilsus:BAAANQADCggICAABNQAECgQIBAADAAAAAA==.Linaraline:BAAANQADCgQIBAAAAA==.Linni:BAAANQAECgYIEQAAAA==.',
Lo='Lortnok:BAAANQAECgEIAQAAAA==.Lotharlock:BAAANQADCgQIBAAAAA==.Lotharpally:BAAANQAECgUIBQAAAA==.',
Lu='Lukadoncic:BAABNQAECoEqAAMGAAkK+B6yEgDYAgAGAAkK+B6yEgDYAgAMAAYKohdiaABLAQAAAA==.',
['Lö']='Lögäñ:BAAANQAECgYICgAAAA==.',
Ma='Maeby:BAAANQADCggIEwABNQAECggIDwADAAAAAA==.Magnessa:BAAANQAECgYICwAAAA==.Malekai:BAAANQADCgYICAAAAA==.Malovious:BAAANQADCggIHwAAAA==.Mano:BAAANQADCggICAAAAA==.Marist:BAAANQAECgcIDwAAAA==.Marshabrady:BAAANQABCgcIDgAAAA==.Marwowi:BAAANQADCgIIAgAAAA==.',
Me='Memelord:BAAANQADCgQIBAAAAA==.Menadare:BAAANQAECgUICQAAAA==.Metaslave:BAAANQAECgUICgABNQAECggIGAACABUdAA==.Meteion:BAAANQAECgEIAQAAAA==.',
Mi='Mianceden:BAAANQAECgQICgAAAA==.Miansbane:BAAANQAECgQIBwAAAA==.Micahscream:BAAANQAECgIIAgAAAA==.Midheaven:BAAANQAECgQIBAAAAA==.Miku:BAAANQADCgcIDwABNQAECgkJHwACAAgZAA==.Milent:BAAANQAECgYIDQAAAA==.Miquiztli:BAAANQAECggIAwAAAA==.Mizoci:BAAANQAECgEIAQAAAA==.',
Mo='Mongoose:BAABNQAECoEfAAITAAkKpxyYGgAVAwATAAkKpxyYGgAVAwAAAA==.',
Ms='Msspelled:BAAANQAECgUICwAAAA==.',
Mv='Mvpiam:BAAANQAECgYIBwAAAA==.Mvpsevoker:BAAANQADCgcICQAAAA==.Mvpspally:BAAANQADCgEIAQAAAA==.',
Mx='Mximus:BAAANQADCgMIAwABNQAECgYIBgADAAAAAA==.',
My='Mystí:BAAANQAECggIEAAAAA==.',
['Má']='Májorpáin:BAAANQADCggICwABNQAECggIGAANAPoQAA==.',
Na='Nabstarr:BAAANQAECgYIEAAAAA==.Namaiki:BAAANQADCgUICQAAAA==.Nasroth:BAAANQAECgYIDQAAAA==.Nasstina:BAAANQAECgEIAQABNQAECggICQADAAAAAA==.Natureterror:BAAANQADCggIFQAAAA==.Naví:BAAANQADCgIIAgAAAA==.',
Ni='Nicefella:BAAANQAECgEIAQAAAA==.Niibyter:BAAANQAECgUICgAAAA==.Nitrolan:BAAANQADCgUIBQAAAA==.',
Oc='Oceanbreeze:BAAANQADCgYIBgAAAA==.',
Oj='Ojasam:BAAANQADCgEIAQAAAA==.',
On='Onlylocks:BAAANQAECgYIDAAAAA==.',
Or='Oralia:BAAANQADCgQIBAAAAA==.Orlisman:BAAANQAECgcIDAAAAA==.',
Pa='Palobo:BAAANQABCgQIBAAAAA==.Pandamunx:BAAANQADCgEJAQAAAA==.',
Ph='Phaka:BAABNQAECoEZAAIMAAcKkRouQgDtAQAMAAcKkRouQgDtAQAAAA==.Phelanx:BAAANQAECgIIAgAAAA==.Philanthropy:BAABNQAECoEiAAIRAAgKZx4GDQDDAgARAAgKZx4GDQDDAgAAAA==.Philsoom:BAAANQAECgUIBQAAAA==.',
Pi='Pizzeroloko:BAABNQAECoEfAAIEAAkKnhxCBQADAwAEAAkKnhxCBQADAwAAAA==.',
Pl='Placebo:BAAANQAECggIDwAAAA==.Playforever:BAAANQADCgQIBwAAAA==.Pläze:BAAANQAECgIIAgAAAA==.',
Pr='Prahd:BAAANQAECgUICQAAAA==.',
Pu='Purrsephonie:BAAANQAECgQICQAAAA==.',
Pw='Pweist:BAAANQADCggIFwABNQAECgMIAwADAAAAAA==.',
Py='Pyronorish:BAAANQADCgQIDQAAAA==.Pytthia:BAABNQAECoEYAAMUAAcK1w6nLQCPAQAUAAcK1w6nLQCPAQAVAAUKLg2GEAAJAQAAAA==.',
Ra='Raptalia:BAAANQADCggIDAABNQAECgkJHwACAAgZAA==.Rayquaza:BAAANQADCgIIAgABNQAFFAcIGQAHAKwVAA==.Raziel:BAAANQAECgIIAgAAAA==.',
Re='Reldruin:BAAANQADCgUICAAAAA==.Rexi:BAAANQADCgQIBAAAAA==.',
Rh='Rhaena:BAAANQAECgIIAgAAAA==.Rhombus:BAAANQAECgUICgAAAA==.',
Ri='Rickjamesbia:BAAANQAECgEIAQAAAA==.Riorson:BAABNQAECoEaAAIQAAgKixLHQQDXAQAQAAgKixLHQQDXAQAAAA==.Rizhir:BAAANQADCgQICgAAAA==.',
Ro='Ronkey:BAAANQAECgIIAgAAAA==.Ronkzar:BAAANQADCgUIBgAAAA==.',
Sa='Sacklord:BAAANQADCggICAAAAA==.Sakai:BAAANQADCgcIBwAAAA==.Saltydog:BAAANQADCgQIDAAAAA==.',
Sc='Scurge:BAAANQAECgYIBgAAAA==.',
Se='Seizo:BAAANQAECgQIBwAAAA==.Serazen:BAAANQAECgUICQAAAA==.Setal:BAAANQAECgEIAQAAAA==.',
Sh='Shallteàr:BAAANQADCgMIBAAAAA==.Shammysathh:BAAANQAECgIIAgAAAA==.Shamurloc:BAAANQADCgEIAQAAAA==.Sheenatonic:BAAANQADCgYIDAABNQAECgYIEQADAAAAAA==.Sheenzilla:BAAANQADCgYIDAABNQAECgYIEQADAAAAAA==.Shockaholix:BAAANQADCgUIBQABNQAECgYIBgADAAAAAA==.Shoinked:BAAANQAECgUIDQAAAA==.',
Si='Sices:BAAANQADCgQJBAAAAA==.Silentpaw:BAAANQAECgQIDgABNQAECggIGAANAPoQAA==.',
Sm='Smallblades:BAAANQADCgUIBQAAAA==.Smallêntropy:BAAANQAECgUICAAAAA==.Smelt:BAAANQADCgYICAAAAA==.Smuurfdk:BAEANQADCggICAABNQAECgcIDQADAAAAAA==.Smuurfhands:BAEANQAECgcIDQAAAA==.',
Sp='Spriggy:BAAANQAECgMIBgAAAA==.',
St='Stabbytrout:BAABNQAECoEcAAIWAAkKICGHBQBmAwAWAAkKICGHBQBmAwAAAA==.Stabyotoe:BAAANQADCgUIBQAAAA==.',
Su='Sugar:BAAANQADCggICAAAAA==.Sunetra:BAAANQAECgYIDQAAAA==.Sushi:BAAANQADCgcIDwAAAA==.',
['Sà']='Sàlanis:BAAANQADCgMIAwABNQAECgYIEQADAAAAAA==.',
['Sã']='Sãlanis:BAAANQAECgEIAQABNQAECgYIEQADAAAAAA==.',
['Sä']='Sälanis:BAAANQAECgYIEQAAAA==.',
Ta='Taal:BAAANQADCgQIBAABNQAECgkJIAAPANEZAA==.Taehyung:BAAANQAECgUICAAAAA==.Tainthel:BAAANQADCgUIBQAAAA==.Tairyn:BAABNQAECoEjAAMSAAkKliC+HAA4AwASAAkKliC+HAA4AwAXAAIKPhWHMAB4AAAAAA==.Taloki:BAAANQADCgYIFwAAAA==.Tatsuhisa:BAAANQADCgYIEAAAAA==.',
Te='Telavore:BAAANQADCgUIBQAAAA==.Telle:BAAANQAECgQIBgAAAA==.Terregoat:BAAANQADCgUIBQAAAA==.',
Th='Thrallmarr:BAAANQADCgIIAgAAAA==.Thruder:BAAANQADCgQIBgAAAA==.',
Ti='Titfortat:BAAANQADCgYICwAAAA==.',
To='Tophdh:BAAANQAECgQIBQAAAA==.Totemicblank:BAAANQAECgIIAgAAAA==.',
Tr='Traydle:BAAANQAECgYICwAAAA==.Trondur:BAAANQAECgcIEQAAAA==.Trydel:BAAANQADCgcIEQABNQAECgYICwADAAAAAA==.Trygon:BAAANQADCgYIBgABNQAECgYICwADAAAAAA==.',
Tu='Tuffnnice:BAAANQABCgcICgAAAA==.Tuini:BAAANQADCgcIFAAAAA==.',
Ty='Tydis:BAAANQADCgYIGgAAAA==.',
['Tá']='Tálonstorm:BAAANQAECgQIDQAAAA==.',
Ul='Ultra:BAAANQABCgIIAgAAAA==.',
Va='Valynaria:BAAANQAECgEIAQAAAA==.Vani:BAAANQAECgMIBAAAAA==.',
Vi='Victim:BAAANQABCgIIAgAAAA==.Vilthrax:BAAANQAECgIIAwAAAA==.',
Vu='Vulcanus:BAAANQAECgEIAQAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUJBQAAAA==.',
Wa='Warchiéf:BAAANQAECgYIEgAAAA==.Warent:BAAANQABCgIIAgAAAA==.Watermelon:BAABNQAECoEYAAISAAYKthUppgCRAQASAAYKthUppgCRAQAAAA==.',
Wh='Whalaski:BAABNQAECoEgAAITAAgKrRNgYQApAgATAAgKrRNgYQApAgAAAA==.Whistledown:BAAANQADCgYIBgAAAA==.',
Wi='Wickedsin:BAAANQADCgYIEAAAAA==.Wickedstorm:BAAANQADCgYICwAAAA==.',
Wr='Wreckitman:BAABNQAECoEmAAMHAAkK7RhmDwDCAgAHAAkK7RhmDwDCAgAIAAcKeQVtXAA3AQAAAA==.',
Xa='Xaalath:BAAANQAECgQIDgAAAA==.',
['Xé']='Xéno:BAABNQAECoEgAAIRAAcK1w8xIgCZAQARAAcK1w8xIgCZAQAAAA==.',
Yo='Yobaz:BAAANQADCgUIDQAAAA==.Yohanan:BAAANQABCgYICwAAAA==.Yozomi:BAAANQADCgYIFQAAAA==.',
Za='Zappya:BAAANQABCgYIDQAAAA==.Zarorisk:BAAANQAECgUIBgABNQAECgkJHAAEALIcAA==.',
Ze='Zedd:BAAANQAECgUIDQABNQADCgcIFAADAAAAAA==.',
['ße']='ßez:BAAANQADCgIIAgAAAA==.',
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
