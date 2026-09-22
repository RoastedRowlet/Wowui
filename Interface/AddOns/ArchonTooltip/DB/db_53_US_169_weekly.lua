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

local lookup = {'Mage-Arcane','Mage-Frost','Priest-Holy','Unknown-Unknown','Paladin-Holy','Druid-Balance','Shaman-Restoration','Warrior-Arms','Warrior-Protection','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Druid-Feral','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Priest-Shadow','Druid-Restoration','DemonHunter-Havoc','Paladin-Retribution','Priest-Discipline','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-BeastMastery','Druid-Guardian','Shaman-Enhancement','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Blood',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aairidari:BAAANQAECgQICQAAAA==.',
Ab='Abruna:BAAANQAECgYJCAABNQAECgkJIgABAOUhAA==.Abruno:BAABNQAECoEiAAMBAAkK5SF3HwA5AwABAAkKDyF3HwA5AwACAAEKWh0AAAAAAAAAAA==.Abruto:BAAANQADCgIJAQABNQAECgkJIgABAOUhAA==.',
Ae='Aeown:BAAANQADCggJGwABNQAECggJGgADALkFAA==.Aerdis:BAAANQADCggIFQABNQAECgQIBwAEAAAAAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Al='Alandrìas:BAAANQAECgYIEQAAAA==.Altera:BAAANQAECgUJCQAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgQIBAAAAA==.Androonatorz:BAABNQAECoEgAAIFAAkKUiD2FADkAgAFAAkKUiD2FADkAgAAAA==.Anfernay:BAAANQAECgcJEQAAAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAAANQAECgMJAwABNQAECgkJJgAGACQeAA==.',
Aq='Aquadab:BAAANQADCgQIBAAAAA==.',
Ar='Arcanodare:BAAANQADCggICAAAAA==.Arkalis:BAAANQADCgYJBgAAAA==.Arveiturace:BAAANQADCggIHgAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAAANQAECgUJEAAAAA==.',
At='Attack:BAAANQAECgEIBAAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgYJCQAAAA==.',
Be='Bearlyseen:BAAANQAECgYJBgABNQAECgkJIQAHAHIcAA==.Beltirra:BAAANQADCgYJFQAAAA==.',
Bh='Bhangbros:BAAANQADCgcJBwAAAA==.',
Bi='Biggums:BAAANQADCgUJBQAAAA==.Bigmobility:BAAANQAECgcIEgAAAA==.Bigwill:BAABNQAECoEZAAICAAgK6iHHAQARAwACAAgK6iHHAQARAwAAAA==.',
Bl='Blargy:BAABNQAECoEZAAIGAAgKnBS8JgAzAgAGAAgKnBS8JgAzAgAAAA==.Bleach:BAAANQAECgEIAQAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBgAAAA==.',
Br='Brighterbonk:BAAANQADCgQJBAABNQADCgYIEQAEAAAAAA==.Brimara:BAAANQAECgQJCwAAAA==.',
Bu='Bucketojoy:BAAANQAECgIIBAAAAA==.',
['Bà']='Bàtman:BAAANQADCggIDQAAAA==.',
Ca='Caliburne:BAABNQAECoEYAAMIAAgKEx2mOgB7AgAIAAgKNxumOgB7AgAJAAMK3R0ZGQD/AAAAAA==.Capz:BAACNQAFFIEUAAIIAAcK2x4TAQCvAgAIAAcK2x4TAQCvAgA1AAQKgRoAAggACQqhJVMOAGcDAAgACQqhJVMOAGcDAAAA.',
Ce='Cedrin:BAAANQADCgYIDgAAAA==.Ceez:BAAANQAECgEIAQAAAA==.',
Ch='Chichujongar:BAAANQAECgEJAQABNQAECgkJJgAKADcUAA==.Chickenstwip:BAAANQADCgEIAgABNQAECgcIEAAEAAAAAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgUICQAAAA==.',
Ci='Cindrella:BAAANQAFFAEIAQAAAA==.',
Cl='Clayre:BAABNQAECoEnAAILAAkKgR9bAQBhAwALAAkKgR9bAQBhAwAAAA==.Clow:BAAANQAECgIIBQAAAA==.',
Co='Colossus:BAAANQAECgEIAQAAAA==.Coolcrush:BAAANQADCgMIBgABNQAECgYIEAAEAAAAAA==.Corven:BAABNQAECoEoAAMMAAkK7SKHBACCAwAMAAkK7SKHBACCAwALAAEKRQW3bgAnAAAAAA==.',
Cr='Critzwar:BAABNQAECoEdAAIIAAkKSyHJFQA2AwAIAAkKSyHJFQA2AwAAAA==.Crönus:BAAANQADCggJEAAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAAANQAECgQICQAAAA==.Daní:BAAANQADCgUIBgABNQADCgYJBgAEAAAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQADCgQJBwAAAA==.Daygath:BAAANQAECgEJAQAAAA==.',
De='Deadlyiris:BAABNQAECoEZAAIIAAgKlR4/KwDAAgAIAAgKlR4/KwDAAgABNQAFFAEIAQAEAAAAAA==.Deadshot:BAAANQADCgMIAwAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQADCggIDQABNQAECgYJEwAEAAAAAA==.Demonbulio:BAAANQAECgMJAwAAAA==.Demonisthicc:BAABNQAECoEaAAINAAgK0hsGBQCtAgANAAgK0hsGBQCtAgAAAA==.Demonslayeer:BAAANQADCggJDQAAAA==.Devi:BAAANQAECgUJCgAAAA==.',
Di='Diaravynn:BAAANQADCgIIAgAAAA==.Dithehealer:BAAANQAECgYJDAAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQADCggIEAAAAA==.',
Do='Dozekar:BAAANQAECgEJAQAAAA==.',
Dr='Drenamai:BAAANQAECgEJAgAAAA==.Drexywexyuwu:BAAANQADCgcJBwAAAA==.',
Du='Duhmptruhk:BAAANQAECgcJEAAAAA==.Dunbroch:BAACNQAFFIEHAAIOAAQK7wrJCQAdAQAOAAQK7wrJCQAdAQA1AAQKgSUAAg4ACQqQHBwMAOICAA4ACQqQHBwMAOICAAAA.Duskforge:BAAANQABCgIJAgAAAA==.',
['Dé']='Démonicblood:BAABNQAECoEZAAIPAAgK1xirGABGAgAPAAgK1xirGABGAgAAAA==.',
Eg='Eggplantgodx:BAAANQAECgcJEgAAAA==.',
Ek='Ekhart:BAAANQAECgEIAQAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAABNQAECoEgAAMQAAkKFRywCQDvAgAQAAkKFRywCQDvAgARAAgK+g29KwAEAQAAAA==.',
Em='Emmy:BAAANQAECgQJDgAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAAANQAECgcIEAAAAA==.Emowrecky:BAAANQAECgQJCgAAAA==.',
En='Endo:BAABNQAECoEmAAMSAAkKnSTsDQAUAwASAAgKbSPsDQAUAwAPAAcK9SDgEwB+AgAAAA==.Endorush:BAAANQAECgYJCQABNQAECgkJJgASAJ0kAA==.Endrigosa:BAAANQADCggJCQAAAA==.Eneldenes:BAAANQAECgQIBgAAAA==.Enjoyer:BAAANQAECgMIAwAAAA==.',
Er='Ereitherla:BAAANQAECgMJBgAAAA==.',
Es='Esmenet:BAAANQAECgYICwAAAA==.Espressð:BAAANQAECgIIAgABNQAECgcIEAAEAAAAAA==.',
Ex='Excalibear:BAAANQAECgUJCQABNQAECgkJIQAHAHIcAA==.',
Ey='Eydis:BAAANQADCgIIAgAAAA==.',
Fe='Feironor:BAAANQADCgQIBgAAAA==.Fenrys:BAAANQADCgcIEgAAAA==.',
Fi='Fikareous:BAAANQADCgUIBQABNQAECgUIBQAEAAAAAA==.',
Fl='Flayre:BAAANQAECgYJDwAAAA==.Fleredil:BAAANQAECgUIEAAAAA==.Flingernle:BAAANQAECgYIEgAAAA==.',
Fo='Forepray:BAABNQAECoEhAAITAAkKcBshCwD2AgATAAkKcBshCwD2AgAAAA==.Forger:BAAANQAECgYJDgAAAA==.Forsakey:BAAANQADCgYICwABNQAECgkJHgAUAGogAA==.',
Fr='Fraun:BAAANQADCggJEQAAAA==.',
Fu='Fullyprotpal:BAAANQADCgcICAAAAA==.Furioustotem:BAAANQAECgMJBgAAAA==.Future:BAAANQADCgUIBgABNQAECgkJIAABANwiAA==.',
Ga='Galten:BAAANQABCgUIBQAAAA==.Gantz:BAAANQADCgIJAgAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECgcIEAAEAAAAAA==.',
Gh='Ghettox:BAAANQADCgIIAgAAAA==.Ghostw:BAAANQAECgMIBwAAAA==.',
Go='Golgotterath:BAABNQAECoEhAAIHAAkKchwsJQB1AgAHAAkKchwsJQB1AgAAAA==.Gorm:BAAANQAECgYICgABNQAECgMIAwAEAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAgABNQAECgkJFwAVAKsgAA==.',
Ha='Halbruck:BAAANQAECgcJEQAAAA==.Haldane:BAABNQAECoEXAAIWAAgKPAaBjQBaAQAWAAgKPAaBjQBaAQABNQAFFAEIAQAEAAAAAA==.Havochunter:BAAANQAECgMIAwAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Helinndealin:BAABNQAECoEiAAMXAAkKkCSsAABZAwAXAAgKvCSsAABZAwADAAgKLSLdIwB3AgAAAA==.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAAANQAECgYICQAAAA==.Hephsdh:BAAANQAECgIIAwAAAA==.Heraois:BAAANQAECgUIBwAAAA==.Heriod:BAAANQABCgEIAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQADCggJDgAAAA==.Holywráth:BAAANQADCgQIBgAAAA==.',
Hu='Hunterdh:BAAANQAECgIJAgAAAA==.',
Hy='Hynixx:BAAANQAECgYJBgABNQAECgkJIQATAHAbAA==.',
Il='Illidope:BAABNQAECoEXAAQVAAkKqyC2BwBHAwAVAAkKjSC2BwBHAwAYAAgKgBvUEwCFAgAZAAEKFBnbGwBJAAAAAA==.',
In='Infinitevoid:BAAANQADCggJDwAAAA==.Innervatez:BAAANQAFFAIJAgAAAA==.Inteaus:BAAANQADCggIFgAAAA==.',
Io='Ionúin:BAAANQADCgQJBAAAAA==.',
Iv='Ivÿ:BAAANQADCgIJAgAAAA==.',
Ja='Jaekir:BAAANQAECgUJCQAAAA==.Jakfrost:BAAANQAECgYJEwAAAA==.Jakie:BAAANQADCgYICgABNQAECgYIDQAEAAAAAA==.Jarten:BAABNQAECoEkAAIPAAkKHRzbDwCwAgAPAAkKHRzbDwCwAgAAAA==.Jayaah:BAAANQADCgYJFQAAAA==.Jaylebate:BAAANQADCggIIwAAAA==.',
Je='Jesseatamer:BAABNQAECoEiAAIaAAkKbyJQCABtAwAaAAkKbyJQCABtAwAAAA==.',
Ji='Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECggJGgAIAJ8SAA==.Jstrawr:BAABNQAECoEaAAIIAAgKnxJsXAD+AQAIAAgKnxJsXAD+AQAAAA==.',
Ka='Karen:BAAANQAECgUJCQAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kastia:BAAANQADCgUJDgAAAA==.Katrynwel:BAAANQAECgQIBAAAAA==.Katsumi:BAAANQADCggJGQAAAA==.',
Ke='Keliki:BAAANQAECgcJEgAAAA==.Kellenah:BAAANQABCgIIAgAAAA==.Kettama:BAAANQADCggIEAABNQAECgcIEAAEAAAAAA==.',
Kh='Khold:BAAANQAECgYIDgAAAA==.Khrogann:BAAANQAECgMIBAAAAA==.',
Ki='Killalltoday:BAAANQAECgUJCgAAAA==.Kirkk:BAAANQAECgEIAQAAAA==.',
Kl='Klaminus:BAAANQADCgQJBAAAAA==.',
Kn='Knixx:BAABNQAECoEnAAMDAAkKayUFAQDOAwADAAkKayUFAQDOAwAXAAYK8xHOCQBWAQAAAA==.Knuppelus:BAAANQADCgYICQAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMJAwABNQAECgcJEAAEAAAAAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAAANQAECgYJDQAAAA==.',
Kr='Krenmonk:BAAANQAECgEIAQAAAA==.Krennic:BAAANQADCgcIBwAAAA==.Krunchee:BAAANQADCgcJCgAAAA==.',
Ku='Kufoo:BAAANQAECgUJCgAAAA==.Kurao:BAAANQAECgEJAgAAAA==.Kurukai:BAAANQADCgIIAgAAAA==.',
Ky='Kyrian:BAACNQAFFIEIAAIRAAUKrRprAgDhAQARAAUKrRprAgDhAQA1AAQKgSAAAhEACQpuIisDAF0DABEACQpuIisDAF0DAAAA.',
La='Lagøless:BAABNQAECoEYAAIaAAkKYSGNBQCOAwAaAAkKYSGNBQCOAwAAAA==.',
Le='Leo:BAAANQAECgEIAQAAAA==.',
Li='Likestoflash:BAEANQADCgYJBgABNQAECggJGgAaAHkbAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAABNQAECoEYAAIMAAgKVBgSMQBaAgAMAAgKVBgSMQBaAgAAAA==.Lohmi:BAAANQAECgQICgAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQADCgUJDgAAAA==.',
Ly='Lyna:BAAANQADCggJDAAAAA==.Lyravega:BAAANQADCggICAAAAA==.Lyshkä:BAAANQAECgYIEwAAAA==.Lyzzardkng:BAAANQAECgUJCAAAAA==.',
['Lý']='Lýra:BAAANQADCggIDwAAAA==.',
Ma='Maango:BAAANQAECggIEAAAAA==.Maemu:BAAANQABCgUIBQAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAAANQAECgUJDAAAAA==.Magiki:BAAANQADCgcICwAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgYIBAAAAA==.Mamadeezy:BAAANQADCgYJCwAAAA==.Mando:BAAANQADCgcJFgABNQAECgMJBgAEAAAAAA==.Manical:BAAANQADCggJFQAAAA==.Marcel:BAAANQADCgYIEQAAAA==.Mashiach:BAABNQAECoEdAAMDAAkKiB+kEwDjAgADAAkKiB+kEwDjAgATAAEKXRNbUgA5AAAAAA==.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQAECgQIBQABNQAECggJGAAWALMcAA==.Melikefire:BAABNQAECoEYAAIBAAcKhxxvggARAgABAAcKhxxvggARAgAAAA==.Memecompdall:BAAANQADCgYIDAAAAA==.Merek:BAAANQAECgUJBwAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQAECgEIAQABNQAFFAEIAQAEAAAAAA==.Mistybdk:BAAANQADCggICAABNQAFFAUICQAbAI4XAA==.Mistyd:BAACNQAFFIEJAAIbAAUKjhekAACiAQAbAAUKjhekAACiAQA1AAQKgSgAAhsACQrEIlIBAJEDABsACQrEIlIBAJEDAAAA.',
Mo='Mogfooyen:BAAANQABCgQIBgAAAA==.Moonbeam:BAAANQAECgEIAQAAAA==.Morgause:BAAANQAECgIJAgAAAA==.Morllan:BAAANQAECgYICQAAAA==.',
Mu='Muirdin:BAAANQADCgEJAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Må']='Mångix:BAAANQADCgcIBwAAAA==.',
['Mé']='Mélusine:BAAANQAECgYJBgAAAA==.',
Na='Naanomage:BAAANQADCgcIFgAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAABNQAECoEXAAIYAAgK2x3XEACrAgAYAAgK2x3XEACrAgAAAA==.Nirath:BAAANQAECgUJCgAAAA==.',
No='Noiire:BAAANQAECgYICAABNQAECgkJIAAQABUcAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAAANQAECgcICgAAAA==.',
Ok='Okami:BAAANQAECgIJAwAAAA==.',
Oo='Ooyagoddess:BAAANQADCgEIAQAAAA==.',
Or='Orryck:BAAANQADCgQIBQAAAA==.',
Pa='Pacamonk:BAAANQAECgcJEwAAAA==.Papatiny:BAAANQADCgIIAgAAAA==.Pawsa:BAAANQAECgQIBgABNQAECgcIEAAEAAAAAA==.Pawthetic:BAABNQAECoEmAAMGAAkKJB7BDwASAwAGAAkKJB7BDwASAwAUAAMKrRCOOACvAAAAAA==.',
Pe='Peelforheals:BAABNQAECoEjAAMTAAkKsBy+DADVAgATAAkKsBy+DADVAgAXAAQKuAuXDwDLAAAAAA==.Penguindemic:BAAANQAECgYJEAAAAA==.Pep:BAAANQAECgQIBwAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Perdator:BAAANQAECgQIBAAAAA==.Petruccius:BAABNQAECoEiAAIGAAkKBhxJDgAkAwAGAAkKBhxJDgAkAwAAAA==.Pewpewlepew:BAAANQAECgQIBwAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAABNQADCgYJBgAEAAAAAA==.',
Pl='Plague:BAAANQAECgIJAgAAAA==.',
Po='Poptartsz:BAAANQAECgMJBQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Precht:BAAANQADCgYJEgAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prumper:BAAANQAECgcJEgAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
Qu='Quesoblanco:BAAANQAECgYJCQAAAA==.',
Qy='Qybxboogietk:BAAANQAECgYJBgAAAA==.',
Ra='Rabid:BAAANQADCgMIAwAAAA==.Raghallov:BAAANQAECgIIBAAAAA==.Rampa:BAAANQADCgYIEQABNQAECgcIEAAEAAAAAA==.',
Re='Reaperan:BAAANQAECgEIAQAAAA==.Regena:BAABNQAECoEaAAMDAAgKuQVdWAB3AQADAAgKuQVdWAB3AQATAAIKaALnTABKAAAAAA==.Remorse:BAABNQAECoEoAAIJAAkKfyH9BQCYAgAJAAkKfyH9BQCYAgAAAA==.Rendwick:BAAANQADCgYICQAAAA==.',
Ri='Rim:BAAANQAECgUIDQAAAA==.',
Ro='Ronfar:BAABNQAECoEnAAIcAAkKZiJGAgBsAwAcAAkKZiJGAgBsAwAAAA==.',
Ru='Rustyglass:BAAANQABCgYIBAAAAA==.Ruttisðir:BAAANQAECgIIAwAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAAANQAECgYJCAAAAA==.Ryù:BAAANQADCggJHAAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Sanazenet:BAAANQADCggJDAAAAA==.Saphiriel:BAAANQAECgIJAgAAAA==.Saviorself:BAAANQADCgMJAwABNQAECgkJJgAGACQeAA==.',
Sc='Scarscar:BAAANQAECgUIBQAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.',
Se='Segarth:BAAANQAECgEJAQAAAA==.Selen:BAAANQAECgcIBwAAAA==.Semballin:BAAANQABCgMJAwAAAA==.Seswatha:BAAANQAECgUIBQABNQAECgkJIQAHAHIcAA==.',
Sh='Shamandroo:BAAANQAECgYJCQABNQAECgkJIAAFAFIgAA==.Shamdi:BAAANQADCgYJBgAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shawtyy:BAAANQADCgMJAwAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgMIAwAEAAAAAA==.Shortandold:BAAANQAECgUICgAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAAANQAECgYIEAAAAA==.',
Si='Sintram:BAAANQABCgIJAgAAAA==.',
Sl='Slighted:BAAANQADCgcJHQABNQAECgQIBwAEAAAAAA==.Slimydruid:BAAANQAECgEIAQAAAA==.Slow:BAABNQAECoEgAAIBAAkK3CLGJgAfAwABAAkK3CLGJgAfAwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECgcIEAAEAAAAAA==.Smokze:BAAANQADCggJCAAAAA==.',
So='Sockoh:BAAANQAECgYJDgAAAA==.Solera:BAEANQADCggICAAAAA==.Sonicberger:BAAANQADCgYIEwABNQAECgYIBwAEAAAAAA==.Soniko:BAAANQAECgQIBwAAAA==.Sonícberger:BAAANQAECgYIBwAAAA==.Soulcaliber:BAAANQADCgQIBAAAAA==.',
St='Stain:BAAANQAECgQJCAAAAA==.Stealth:BAAANQAECgQIBAABNQAECgUJCgAEAAAAAA==.Stinkfist:BAAANQADCgYIBgAAAA==.Stonehenge:BAAANQAFFAEIAQAAAA==.Stonepalm:BAAANQADCgUICAAAAA==.Stratan:BAAANQADCgIIAgABNQADCgQJBAAEAAAAAA==.Strawk:BAAANQAECgUIBwAAAA==.',
Su='Suffer:BAAANQADCggICQABNQAECgkJIAABANwiAA==.Supercat:BAAANQAECgEIAQAAAA==.Surf:BAAANQAECgIIBAAAAA==.',
Sw='Swankydranky:BAABNQAECoEmAAQKAAkKNxTsHQCuAQAKAAkKBhPsHQCuAQAdAAYKMxR4EABuAQAeAAEK9gJ2OwAmAAAAAA==.Swankypally:BAAANQAECgMJAwABNQAECgkJJgAKADcUAA==.',
Sy='Syesc:BAAANQABCgQJBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.',
['Sá']='Sásukeuchiha:BAAANQADCgYIBgABNQAECgQIBwAEAAAAAA==.',
Ta='Tabbz:BAAANQAECgcJEQAAAA==.Tallael:BAAANQAECgYIDgAAAA==.Tallyhochick:BAAANQAECgcJEgAAAA==.Taman:BAABNQAECoEbAAIHAAgKNx30HwCUAgAHAAgKNx30HwCUAgAAAA==.Taylerswift:BAAANQAECgEJAQAAAA==.',
Th='Thebestname:BAAANQAECgUIBwAAAA==.Thebigonion:BAAANQADCgYIEQAAAA==.Theexile:BAAANQAECgcIDwAAAA==.Theigh:BAAANQADCgYJBgAAAA==.Thonard:BAAANQADCgYIBgABNQAECggIFwASAAAkAA==.',
Ti='Tinydeath:BAABNQAECoEYAAIfAAgKARQ2LwDrAQAfAAgKARQ2LwDrAQAAAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAAANQAECgYIDwABNQAECggJGAAfAAEUAA==.',
Tm='Tmakrist:BAAANQAECgEIAQAAAA==.',
To='Toko:BAABNQAECoEbAAIaAAkK0CMyDABFAwAaAAkK0CMyDABFAwAAAA==.Tomblord:BAAANQAECgYJBgAAAA==.',
Tr='Trailblazah:BAAANQAECgIJAgAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgYIBwABNQAECgUJCgAEAAAAAA==.Truths:BAAANQADCgIJAgABNQAECgUJCgAEAAAAAA==.Truthsx:BAAANQAECgUJCgAAAA==.Truthy:BAAANQADCgYICAABNQAECgUJCgAEAAAAAA==.Truthz:BAAANQADCgYJBgABNQAECgUJCgAEAAAAAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCggIDAAAAA==.Tylaatape:BAAANQAECgYICQAAAA==.Tyraell:BAAANQAECgMIBgAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAECgkJGwAaANAjAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgIIAwABNQAECgIIBQAEAAAAAA==.',
Us='Usgasdanelv:BAAANQAECgcIDAAAAA==.',
Uz='Uzala:BAAANQADCggIGQAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAAANQAECgYJEQAAAA==.',
Ve='Vendiyre:BAAANQAECgYIBgAAAA==.Venthyl:BAABNQAECoEaAAIGAAkKESXcBQCLAwAGAAkKESXcBQCLAwAAAA==.',
Vi='Vizan:BAAANQABCgcIBwABNQAECgUJCgAEAAAAAA==.',
We='Wellby:BAAANQADCgcIFgAAAA==.Westerin:BAAANQAECgYJCgAAAA==.',
Wi='Wildnature:BAAANQADCgYIBgAAAA==.Wimateeka:BAAANQAECgYJDQAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJIAABANwiAA==.Windigo:BAAANQAECgIIAgAAAA==.',
Wo='Wooqles:BAAANQADCgUIBQABNQADCgYICAAEAAAAAA==.',
Wr='Wrastelas:BAAANQABCgEIAQAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.',
Xa='Xaala:BAAANQAECgQIBQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgIIBQAEAAAAAA==.',
Ye='Yespaladin:BAABNQAECoEhAAIfAAkKyBvWFAC5AgAfAAkKyBvWFAC5AgAAAA==.',
Yi='Yimity:BAAANQAECgMIAwAAAA==.',
Yo='Yogí:BAABNQAECoEfAAIHAAkKHB4VSQDFAQAHAAkKHB4VSQDFAQAAAA==.Yozomoto:BAABNQAECoEgAAMaAAkKjSDHLgB4AgAaAAkKjSDHLgB4AgAOAAEK5ggmYwAtAAAAAA==.',
Za='Zalandria:BAAANQAECgIJAgAAAA==.',
Ze='Zeltemis:BAAANQAECgQJBwAAAA==.',
Zi='Zipsion:BAAANQAECgYJEgAAAA==.Zivver:BAAANQAECgcJEQAAAA==.Zizka:BAAANQAECgYJDAAAAA==.',
Zo='Zolandir:BAAANQADCgcICgAAAA==.',
['Üt']='Üther:BAABNQAECoEYAAIWAAgKsxwHNgB9AgAWAAgKsxwHNgB9AgAAAA==.',
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
