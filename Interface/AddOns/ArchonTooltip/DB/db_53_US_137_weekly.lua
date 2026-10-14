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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Shaman-Restoration','Unknown-Unknown','Druid-Feral','Monk-Windwalker','DeathKnight-Frost','Druid-Restoration','Druid-Balance','Mage-Arcane','Priest-Holy','Shaman-Elemental','DeathKnight-Unholy','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','DeathKnight-Blood','Evoker-Preservation','Warrior-Arms','Hunter-BeastMastery','Priest-Discipline','Rogue-Assassination','Paladin-Holy','Warrior-Protection',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Accursed:BAACNQAFFH8HAAIBAAMKPB9wAgARAQABAAMKPB9wAgARAQA1AAQKfykAAgEACQoxJO0BAHkDAAEACQoxJO0BAHkDAAAA.Activesloth:BAAANQADCgQJBAABNQAECgkJHQACAEgeAA==.',
Ad='Adekeai:BAAANQAECgUIEgAAAA==.Adol:BAAANQADCgYIBgAAAA==.',
Ae='Aelys:BAAANQAECgQIBQAAAA==.',
Al='Aleighta:BAABNQAECn8VAAIDAAgK4QqfhgB2AQADAAgK4QqfhgB2AQAAAA==.Alenara:BAAANQADCgMJAwAAAA==.Allblond:BAAANQADCgYIBgAAAA==.Alyx:BAAANQADCgYIBgAAAA==.',
Am='Amouri:BAAANQABCgIIAgAAAA==.',
An='Anacreon:BAAANQAECgQIAgAAAA==.Anaiah:BAAANQADCggICwABNQAECgUIEQAEAAAAAA==.',
Ar='Arcey:BAAANQADCgIIAgAAAA==.Arun:BAAANQADCgQIBAABNQAECgUICgAEAAAAAA==.',
As='Aspros:BAAANQAECggIDgAAAA==.',
At='Atlantis:BAAANQAECgQICQAAAA==.Atonement:BAABNQAECn8VAAICAAgKbBWThAAaAgACAAgKbBWThAAaAgAAAA==.',
Av='Avengence:BAAANQADCgIIAgAAAA==.',
Ay='Ayshan:BAAANQAECgIIAgABNQAECgQIBQAEAAAAAA==.',
Ba='Badoussi:BAAANQAECgQIBAABNQAECgkJHwAFAFAeAA==.Bakugo:BAAANQADCgMIAwAAAA==.Bananas:BAAANQAECgEIAQAAAA==.',
Be='Beansy:BAAANQADCgUICgAAAA==.Beefomancer:BAAANQAECgMIAwAAAA==.Belladin:BAABNQAECn8eAAICAAkKFxihbwBNAgACAAkKFxihbwBNAgAAAA==.Belzugaim:BAAANQAECgcIDgABNQADCgQIBwAEAAAAAA==.',
Bi='Bipolarcurys:BAAANQAECgQICwAAAA==.Bismuth:BAAANQAECgUICgAAAA==.',
Bl='Blamethedps:BAAANQAECgQIBgABNQAECgYIEgAEAAAAAA==.Blameyomomma:BAAANQAECgUICAABNQAECgYIEgAEAAAAAA==.Blamezuko:BAAANQAECgYIEgAAAA==.Blite:BAAANQADCgUICQAAAA==.Blumoon:BAAANQADCgcIBwAAAA==.',
Bo='Bombakaap:BAABNQAECn8cAAIGAAkKPR3hEgDAAgAGAAkKPR3hEgDAAgAAAA==.Bomburst:BAAANQAECgQIBwAAAA==.Bonelespizza:BAABNQAECn8qAAIHAAkKbCGJEAAIAwAHAAkKbCGJEAAIAwAAAA==.Bonkthump:BAAANQABCggIDQAAAA==.Boogiebabe:BAABNQAECn8oAAMIAAgKaxb8IQATAgAIAAgKaxb8IQATAgAJAAQKOwcLhAC8AAAAAA==.Bornix:BAAANQADCgUIBQABNQAECgcIMAAKAMcaAA==.',
Br='Briaris:BAAANQAECggIEAABNQAECgkJJAAFALwaAA==.Brosar:BAAANQAECgEIAQAAAA==.Brugaras:BAAANQABCgIIAgAAAA==.',
['Bê']='Bêz:BAAANQAECgMIAwAAAA==.',
['Bë']='Bëz:BAAANQAECgUIDwAAAA==.',
Ca='Cadzan:BAAANQABCgUIAwAAAA==.Caith:BAAANQABCgYIBgAAAA==.Calabretta:BAAANQADCgcIGQAAAA==.Cannan:BAAANQADCgYIBgAAAA==.Captcow:BAAANQABCgYIBgAAAA==.Caver:BAAANQADCgcIDQAAAA==.',
Ch='Charysmaa:BAAANQADCgUICwAAAA==.Cheoekar:BAAANQAECgUIBwABNQAFFAQIDAALAN4YAA==.',
Co='Cobey:BAABNQAECn8iAAICAAgKzRcWigANAgACAAgKzRcWigANAgAAAA==.Coldrick:BAAANQAECgIIAgABNQAECgYIBwAEAAAAAA==.Cosmicjay:BAABNQAECn8fAAIMAAgKoSDvKwDMAgAMAAgKoSDvKwDMAgAAAA==.Cosmicnova:BAAANQAECgYIEgABNQAECggIHwAMAKEgAA==.',
Cr='Crumpet:BAAANQAECggIAgAAAA==.',
Cu='Cursedknight:BAAANQADCgYIEgAAAA==.',
Da='Daegán:BAAANQADCgMIAwAAAA==.Daffodil:BAAANQAECgUIDwAAAA==.Dalavian:BAAANQABCgQIBAAAAA==.Dannyhurt:BAAANQADCgcIDwAAAA==.Dantruis:BAACNQAFFH8IAAINAAQKBBVoDQAyAQANAAQKBBVoDQAyAQA1AAQKfyIAAg0ACQrCH4YcAN8CAA0ACQrCH4YcAN8CAAAA.Darlins:BAAANQADCgYIBgAAAA==.',
Di='Dianah:BAAANQADCgUICgAAAA==.Diggy:BAAANQADCgUIBQAAAA==.Dinsfirë:BAAANQADCgIIAgAAAA==.Diothorn:BAAANQAECgYIEQAAAA==.Divanas:BAAANQAECgUICQAAAA==.Divi:BAAANQAECgUIDAAAAA==.Divinium:BAAANQADCgQIBAABNQAECgUIDAAEAAAAAA==.',
Do='Dogfacethug:BAAANQABCggIEAAAAA==.Dorianna:BAAANQAECgUICQAAAA==.',
Dr='Dreamit:BAAANQADCgMIAwAAAA==.Drease:BAAANQADCgEIAQAAAA==.Drpepperz:BAAANQAECgEIAQAAAA==.Drunkdragon:BAAANQADCgYICwAAAA==.',
Ea='Earthtide:BAAANQADCgYICwAAAA==.',
El='Elfsa:BAAANQAECgQIBAAAAA==.Ellayria:BAAANQAECgUIDgAAAA==.Elymaria:BAAANQAECgQICwAAAA==.',
Em='Emberrose:BAAANQAECgUIDQAAAA==.',
En='Enhancedpant:BAABNQAECn8ZAAIOAAcKjRmdFQALAgAOAAcKjRmdFQALAgAAAA==.Ensetral:BAAANQAECgQICAAAAA==.',
Ev='Evernight:BAAANQAECgYIDAAAAA==.',
Fa='Fakedruid:BAAANQAECgEIAQABNQAECgMIAwAEAAAAAA==.',
Fe='Feerahion:BAAANQADCgMIAwAAAA==.Feledris:BAAANQAECgcIBwAAAA==.Felwynne:BAAANQAECgUICwAAAA==.Feybeasts:BAAANQAECgQIBwAAAA==.Feárbomber:BAABNQAECn8eAAMPAAkKtRK1ewDtAQAPAAgKDRG1ewDtAQAQAAIKIxAxVgB7AAAAAA==.',
Fh='Fhala:BAAANQADCggICAAAAA==.Fharia:BAAANQAECgUICQAAAA==.',
Fi='Fivo:BAAANQABCgEIAQAAAA==.',
Fl='Flayr:BAAANQADCgIIAgAAAA==.Flopper:BAAANQABCgQIBAAAAA==.',
Fr='Fries:BAEANQAECggIBwABNQAECggIDQAEAAAAAA==.',
Fu='Fusky:BAAANQAECgQICwAAAA==.',
Fy='Fynn:BAABNQAECn8oAAIOAAkK4h03CQDhAgAOAAkK4h03CQDhAgAAAA==.',
['Fé']='Férn:BAAANQAECgEIAQAAAA==.',
Ga='Galadria:BAABNQAECn8uAAIJAAkKaxwKHQDfAgAJAAkKaxwKHQDfAgAAAA==.Garamond:BAAANQADCggIDwAAAA==.Garnd:BAAANQADCgIIAgAAAA==.Garrish:BAAANQABCgQIBgAAAA==.Gastly:BAAANQADCgEIAQAAAA==.',
Ge='Gerwik:BAAANQAECgQIBgAAAA==.',
Gi='Gimlih:BAAANQADCgEIAQAAAA==.',
Go='Gogetta:BAAANQAECgcICAAAAA==.Goldenlock:BAAANQABCggICwAAAA==.Govana:BAAANQAECgEIAQAAAA==.',
Gr='Greenleaves:BAAANQAECgIJAgAAAA==.',
Gu='Gummiwormz:BAAANQADCgQIBAAAAA==.',
Gy='Gyat:BAAANQADCgUJBwABNQAECgcIHwANAOcaAA==.',
Ha='Hailin:BAABNQAECn8mAAICAAkKJhnGVACUAgACAAkKJhnGVACUAgAAAA==.Haunter:BAAANQAECgUICQAAAA==.',
He='Heherawr:BAAANQADCgEIAQABNQADCgMIBgAEAAAAAA==.',
Hi='Hima:BAAANQAECgUICgAAAA==.',
Ho='Holyjenkins:BAAANQAECgQIBAAAAA==.Horngrry:BAAANQAECgUIDQAAAA==.',
Il='Illtrytoheal:BAAANQADCgYICgAAAA==.',
Im='Imkillho:BAAANQAECgQJBAABNQAECgUIDQAEAAAAAA==.',
In='Inosuke:BAAANQADCgQIBAAAAA==.Inspiredbox:BAAANQAECgIIAwAAAA==.',
Is='Issyo:BAAANQADCgEIAQAAAA==.',
Ja='Jankismith:BAAANQAECgQIEQAAAA==.Jayy:BAAANQAECgUIDwAAAA==.',
Jf='Jflyer:BAAANQADCgIIAgABNQAECggIHwAMAKEgAA==.',
Ji='Jimin:BAAANQAECgcIEAAAAA==.Jitoflight:BAAANQADCgEIAQAAAA==.',
Jm='Jmajk:BAAANQABCgcICAAAAA==.',
Ju='Jugger:BAAANQADCgIIAgAAAA==.',
Ka='Kachiko:BAAANQADCgQIAwAAAA==.Kaethis:BAAANQABCgUJBQAAAA==.Kaia:BAAANQAECgYIDAAAAA==.Kamchan:BAAANQAECgQIBQABNQAFFAUICwALAH4JAA==.Kamerth:BAAANQAECgUIDwAAAA==.Kapbam:BAAANQADCggICgAAAA==.Karluron:BAAANQAECgYIEAAAAA==.Karlutros:BAABNQAECn8dAAIRAAcKZBeCJwDrAQARAAcKZBeCJwDrAQAAAA==.Katbaka:BAAANQADCggIDAABNQAFFAQIDAASAIklAA==.Katmoreahh:BAAANQADCgcIBwABNQAFFAQIDAASAIklAA==.Katuwuagain:BAACNQAFFH8MAAISAAQKiSVKCwCcAQASAAQKiSVKCwCcAQA1AAQKfysAAhIACAoMJuEIAHIDABIACAoMJuEIAHIDAAAA.Kayonalani:BAAANQAECgEIAQAAAA==.Kazure:BAABNQAECn8eAAITAAkKmQVMJQCSAQATAAkKmQVMJQCSAQAAAA==.',
Ke='Kelilia:BAABNQAECn8tAAIUAAkKBhLBcAA+AgAUAAkKBhLBcAA+AgAAAA==.Kenilar:BAAANQAECgMIAwAAAA==.Keybricker:BAAANQADCgMIAwABNQAECgMIAwAEAAAAAA==.',
Ko='Konga:BAAANQAECgQICAAAAA==.Korngry:BAAANQADCgUIBgABNQAECgUIDQAEAAAAAA==.',
Kr='Krakkin:BAAANQADCgYIGAAAAA==.Krenil:BAAANQADCgQICwAAAA==.',
Ku='Kuassei:BAAANQAECgcIEQAAAA==.',
Ky='Kyatto:BAAANQAECgcIDwABNQAFFAQIDAASAIklAA==.Kyllea:BAAANQAECgQIBwAAAA==.',
La='Laaksy:BAAANQAECgUIBwABNQAECgkJHwAVAG4aAA==.Ladraina:BAAANQADCgYIBgAAAA==.Landock:BAAANQADCgYIFgAAAA==.Larynnoelle:BAAANQAECgcIEgAAAA==.',
Le='Lebronjames:BAAANQAECgEIAQABNQAFFAIIBQASAH0YAA==.Leotart:BAABNQAECn8hAAIIAAcKgxDuMgB/AQAIAAcKgxDuMgB/AQAAAA==.Lesbians:BAAANQAECgUICwAAAA==.Leyland:BAAANQADCgcIGwAAAA==.',
Li='Lilsus:BAAANQADCggICAABNQAECgQIBAAEAAAAAA==.Linaraline:BAAANQADCgQIBAAAAA==.Linni:BAABNQAECn8ZAAIIAAcKOAr/PAA2AQAIAAcKOAr/PAA2AQAAAA==.Lizawizah:BAAANQAECgQIBAAAAA==.',
Lo='Lortnok:BAAANQAECgIIAwAAAA==.Lotharlock:BAAANQADCgQIBAAAAA==.Lotharpally:BAAANQAECgUIBwAAAA==.Lotharshammy:BAAANQAECgEIAQAAAA==.',
Lu='Lukadoncic:BAACNQAFFH8FAAMSAAIKfRi0HwCHAAAHAAIKfRiHFACVAAASAAIKCxe0HwCHAAA1AAQKfy0ABAcACQp6HoUaALMCAAcACQp0HoUaALMCAA0ABgpbGARzAEcBABIAAwqcGCKJANcAAAAA.Lunila:BAAANQADCgEIAQABNQAECgMIAwAEAAAAAA==.',
['Lö']='Lögäñ:BAAANQAECgYICwAAAA==.',
Ma='Maeby:BAAANQAECgUIBQABNQAECgkJFwALAJAYAA==.Magnessa:BAAANQAECgYICwAAAA==.Malekai:BAAANQADCgYICAAAAA==.Malovious:BAAANQADCggIHwAAAA==.Mano:BAAANQAECgUIBQAAAA==.Marist:BAABNQAECn8VAAIMAAgKmQsvegCwAQAMAAgKmQsvegCwAQAAAA==.Marshabrady:BAAANQABCgcIEAAAAA==.Marwowi:BAAANQADCgIIAgAAAA==.',
Me='Memelord:BAAANQADCgQIBAAAAA==.Menadare:BAAANQAECgUICQAAAA==.Metaslave:BAAANQAECgUICgABNQAECgkJHQACAEgeAA==.Meteion:BAAANQAECgEIAQAAAA==.',
Mi='Mianceden:BAAANQAECgQIDgAAAA==.Miansbane:BAAANQAECgQIBwAAAA==.Micahscream:BAAANQAECgIIAgAAAA==.Midheaven:BAAANQAECgUICgAAAA==.Miku:BAAANQADCgcIDwABNQAECgkJJgACACYZAA==.Milent:BAAANQAECgYIDQAAAA==.Miquiztli:BAAANQAECggIAwAAAA==.Mizoci:BAAANQAECgEIAgAAAA==.',
Mo='Mongoose:BAABNQAECn8fAAIVAAkKbhrGIwAGAwAVAAkKbhrGIwAGAwAAAA==.Monkeyk:BAAANQADCgMIAwAAAA==.',
Ms='Msspelled:BAAANQAECgUIDgAAAA==.',
Mu='Muichiro:BAAANQADCgQIBAAAAA==.',
Mv='Mvpiam:BAAANQAECgYIBwAAAA==.Mvpsevoker:BAAANQADCgcICQAAAA==.Mvpspally:BAAANQADCgEIAQAAAA==.',
Mx='Mximus:BAAANQADCgMIAwABNQAECgYIBwAEAAAAAA==.',
My='Mystí:BAAANQAECggIEQAAAA==.',
['Má']='Májorpáin:BAAANQAECgQIBAABNQAECgkJHgAPALUSAA==.',
Na='Nabstarr:BAAANQAECgYIEAAAAA==.Namaiki:BAAANQADCgUICQAAAA==.Nasroth:BAAANQAECgYIDQAAAA==.Nasstina:BAAANQAECgEIAQABNQAECggICQAEAAAAAA==.Natureterror:BAAANQADCggIFQAAAA==.Naví:BAAANQADCgIIAgAAAA==.',
Ni='Nicefella:BAAANQAECgEIAQAAAA==.Niibyter:BAAANQAECgUIDwAAAA==.Nitrolan:BAAANQADCgUIBQAAAA==.',
No='Nodiddles:BAAANQADCgYIBgAAAA==.',
Ob='Oberon:BAAANQABCgEIAQAAAA==.',
Oc='Oceanbreeze:BAAANQADCgYIBgAAAA==.',
Oj='Ojasam:BAAANQADCgEIAQAAAA==.',
On='Onlylocks:BAAANQAECgYIDAAAAA==.',
Or='Oralia:BAAANQADCgQIBAAAAA==.Orlisman:BAAANQAECggIDwAAAA==.',
Pa='Palobo:BAAANQABCgQIBAAAAA==.Pandamunx:BAAANQADCgEJAQAAAA==.',
Ph='Phaka:BAABNQAECn8fAAINAAcK5xp4SwDkAQANAAcK5xp4SwDkAQAAAA==.Phelanx:BAAANQAECgIIAgAAAA==.Philanthropy:BAABNQAECn8qAAITAAgK2h+EDADbAgATAAgK2h+EDADbAgAAAA==.Philsoom:BAAANQAECgUIBQAAAA==.',
Pi='Pizzeroloko:BAABNQAECn8kAAIFAAkKvBq0BgD7AgAFAAkKvBq0BgD7AgAAAA==.',
Pl='Placebo:BAABNQAECn8XAAILAAkKkBjfKgC7AgALAAkKkBjfKgC7AgAAAA==.Playforever:BAAANQADCgQIBwAAAA==.Pläze:BAAANQAECgIIAgAAAA==.',
Pr='Prahd:BAAANQAECgUIDQAAAA==.',
Pu='Purrsephonie:BAAANQAECgQIDQAAAA==.',
Pw='Pweist:BAAANQADCggIFwABNQAECgMIAwAEAAAAAA==.',
Py='Pyronorish:BAAANQADCgQIEQAAAA==.Pytthia:BAABNQAECn8YAAMRAAcKAg04MwCFAQARAAcKAg04MwCFAQAWAAUKLg0fEgADAQAAAA==.',
Ra='Raptalia:BAAANQAECgEIAQABNQAECgkJJgACACYZAA==.Rayquaza:BAAANQADCgIIAgABNQAFFAcIGQAIAKwVAA==.Raziel:BAAANQAECgIIAwAAAA==.',
Re='Reldruin:BAAANQADCgUICAAAAA==.Rexi:BAAANQADCgQICAAAAA==.',
Rh='Rhaena:BAAANQAECgIIAgAAAA==.Rhombus:BAAANQAECgUIDwAAAA==.',
Ri='Rickjamesbia:BAAANQAECgEIAQAAAA==.Riorson:BAABNQAECn8cAAISAAgKrxE9SwDHAQASAAgKrxE9SwDHAQAAAA==.Rizhir:BAAANQADCgQIDgAAAA==.',
Ro='Ronkey:BAAANQAECgIIAgAAAA==.Ronkzar:BAAANQADCgUICAAAAA==.',
Sa='Sacklord:BAAANQADCggICAAAAA==.Sakai:BAAANQADCgcIBwAAAA==.Saltydog:BAAANQADCgQIEAAAAA==.',
Sc='Scurge:BAAANQAECgYIBwAAAA==.',
Se='Seizo:BAAANQAECgQIBwAAAA==.Serazen:BAAANQAECgUICQAAAA==.Setal:BAAANQAECgEIAQAAAA==.',
Sh='Shallteàr:BAAANQADCgMIBAAAAA==.Shammysathh:BAAANQAECgIIAgAAAA==.Shamurloc:BAAANQADCgEIAQAAAA==.Sheenatonic:BAAANQADCgYIDAABNQAECgcIEgAEAAAAAA==.Sheenzilla:BAAANQADCgYIDAABNQAECgcIEgAEAAAAAA==.Shockaholix:BAAANQADCgUIBQABNQAECgYIBwAEAAAAAA==.Shoinked:BAAANQAECgUIDQAAAA==.Shoveldin:BAAANQAECgQIBAAAAA==.',
Si='Sices:BAAANQADCgQIBAAAAA==.Silentpaw:BAAANQAECgQIEgABNQAECgkJHgAPALUSAA==.',
Sm='Smallblades:BAAANQADCgUIBQAAAA==.Smallêntropy:BAAANQAECgUIDAAAAA==.Smelt:BAAANQADCgYICAAAAA==.Smuurfdk:BAEANQADCggICAABNQAECgcIDwAEAAAAAA==.Smuurfhands:BAEANQAECgcIDwAAAA==.',
So='Sogekin:BAAANQADCgIIAgAAAA==.',
Sp='Spriggy:BAAANQAECgMIBwAAAA==.',
St='Stabbytrout:BAABNQAECn8fAAIXAAkKKCMhCABSAwAXAAkKKCMhCABSAwAAAA==.Stabyotoe:BAAANQADCgUIBQAAAA==.',
Su='Sugar:BAAANQADCggICAAAAA==.Sunetra:BAAANQAECgYIEQAAAA==.Sushi:BAAANQADCgcIDwAAAA==.',
['Sà']='Sàlanis:BAAANQADCgMIAwABNQAECggIGgAYABoiAA==.',
['Sã']='Sãlanis:BAAANQAECgEIAQABNQAECggIGgAYABoiAA==.',
['Sä']='Sälanis:BAABNQAECn8aAAMYAAgKGiKZGgAKAwAYAAgKGiKZGgAKAwACAAEKAAB8swErAAAAAA==.',
Ta='Taal:BAAANQADCgQIBAABNQAECgkJKAAOAOIdAA==.Taehyung:BAAANQAECgUICAAAAA==.Tainthel:BAAANQADCgUIBQAAAA==.Tairyn:BAABNQAECn8nAAMUAAkKuyAQIAA2AwAUAAkKuyAQIAA2AwAZAAIKZxbaNgB0AAAAAA==.Taloki:BAAANQADCgYIHQAAAA==.Tatsuhisa:BAAANQADCgYIEAAAAA==.',
Te='Telavore:BAAANQADCgUIBQAAAA==.Telle:BAAANQAECgQIBgAAAA==.Terciodk:BAAANQAECgQIBAAAAA==.Terregoat:BAAANQADCgUIBQAAAA==.',
Th='Thrallmarr:BAAANQADCgIIAgAAAA==.Thruder:BAAANQADCgQIBgAAAA==.',
Ti='Titfortat:BAAANQADCgYICwAAAA==.',
To='Tophdh:BAAANQAECgQIBQAAAA==.Totemicblank:BAAANQAECgIIAgAAAA==.',
Tr='Traydle:BAAANQAECgcIDAAAAA==.Trondur:BAABNQAECn8XAAIUAAgKLR+kTgCaAgAUAAgKLR+kTgCaAgAAAA==.Trydel:BAAANQADCgcIEQABNQAECgcIDAAEAAAAAA==.Trygon:BAAANQADCgYIBgABNQAECgcIDAAEAAAAAA==.',
Tu='Tuffnnice:BAAANQABCgcICgAAAA==.Tuini:BAAANQADCgcIFAAAAA==.',
Ty='Tydis:BAAANQADCgYIGgAAAA==.',
['Tá']='Tálonstorm:BAAANQAECgQIEQAAAA==.',
Ul='Ultra:BAAANQABCgIIAgAAAA==.',
Va='Valynaria:BAAANQAECgEIAgAAAA==.Vani:BAAANQAECgQICAAAAA==.',
Vi='Victim:BAAANQABCgIIAgAAAA==.Vilthrax:BAAANQAECgIIAwAAAA==.',
Vu='Vulcanus:BAAANQAECgEIAQAAAA==.',
['Vè']='Vèngeance:BAAANQAECgUJBQAAAA==.',
Wa='Warchiéf:BAAANQAECgYIEgAAAA==.Warent:BAAANQABCgIIAgAAAA==.',
Wh='Whalaski:BAABNQAECn8oAAIVAAkKZRksSwCKAgAVAAkKZRksSwCKAgAAAA==.Whistledown:BAAANQADCgYIBgAAAA==.',
Wi='Wickedsin:BAAANQADCgYIFgAAAA==.Wickedstorm:BAAANQADCggIFAAAAA==.Wingstop:BAAANQADCgIIAgABNQAECgUICQAEAAAAAA==.',
Wr='Wreckitman:BAACNQAFFH8FAAMIAAMKQQczDgC8AAAIAAMKQQczDgC8AAAJAAEKVAAeLAAqAAA1AAQKfykAAwgACQp3GvgRAL4CAAgACQp3GvgRAL4CAAkABwrUBNllADEBAAAA.',
Xa='Xaalath:BAAANQAECgQIEgAAAA==.',
['Xé']='Xéno:BAABNQAECn8kAAITAAgKvw8oIADRAQATAAgKvw8oIADRAQAAAA==.',
Yo='Yobaz:BAAANQADCgUIDQAAAA==.Yohanan:BAAANQABCgYICwAAAA==.Yozomi:BAAANQADCgYIGQAAAA==.',
Za='Zappya:BAAANQABCgYIDgAAAA==.Zarorisk:BAAANQAECgUIBgABNQAECgkJHwAFAFAeAA==.',
Ze='Zedd:BAAANQAECgYIEwABNQADCgcIFAAEAAAAAA==.',
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
