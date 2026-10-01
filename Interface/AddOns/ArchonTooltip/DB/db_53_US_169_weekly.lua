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

local lookup = {'Mage-Arcane','Mage-Frost','Priest-Holy','Unknown-Unknown','DemonHunter-Vengeance','Paladin-Holy','Druid-Balance','Warrior-Arms','Shaman-Restoration','DeathKnight-Blood','Warrior-Protection','Monk-Brewmaster','Warlock-Destruction','Shaman-Enhancement','Warlock-Demonology','Druid-Feral','Hunter-Marksmanship','DeathKnight-Frost','DemonHunter-Havoc','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Shaman-Elemental','Priest-Shadow','Druid-Restoration','Paladin-Retribution','Priest-Discipline','DemonHunter-Devourer','Hunter-BeastMastery','Monk-Mistweaver','Druid-Guardian','Monk-Windwalker',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aairidari:BAAANQAECgYIDwAAAA==.',
Ab='Abruna:BAAANQAECgcIDgABNQAFFAMIBwABAOAWAA==.Abruno:BAACNQAFFIEHAAIBAAMK4BadIQD9AAABAAMK4BadIQD9AAA1AAQKgSUAAwEACQrlIagtABgDAAEACQoPIagtABgDAAIAAQpaHQAAAAAAAAAA.Abruto:BAAANQADCgIIAQABNQAFFAMIBwABAOAWAA==.',
Ae='Aeown:BAAANQAECgEIAQABNQAECggIIwADAEoGAA==.Aerdis:BAAANQADCggIFQABNQAECgUIDAAEAAAAAA==.',
Ah='Aharuka:BAAANQADCgEIAQAAAA==.',
Al='Alandrìas:BAABNQAECoEdAAIFAAgKhwc8EABKAQAFAAgKhwc8EABKAQAAAA==.Altera:BAAANQAECgYIDwAAAA==.',
An='Andelarenn:BAAANQABCgIIAgAAAA==.Andere:BAAANQAECgQIBAAAAA==.Androonatorz:BAACNQAFFIEHAAIGAAMKdh0+DQASAQAGAAMKdh0+DQASAQA1AAQKgSIAAgYACQrTIJ0YAOsCAAYACQrTIJ0YAOsCAAAA.Anfernay:BAAANQAECgcJEQAAAA==.Antiaxxis:BAAANQADCgEIAQAAAA==.',
Ap='Apawthetic:BAAANQAECgQIAwABNQAECgkJLgAHACQeAA==.',
Aq='Aquadab:BAAANQADCgQICAAAAA==.',
Ar='Arcanodare:BAAANQADCggICAAAAA==.Arkalis:BAAANQADCgYIBgAAAA==.Arveiturace:BAAANQADCggIHgAAAA==.',
As='Ashborrn:BAAANQADCgUIBQAAAA==.Ashtar:BAABNQAECoEbAAIIAAcKzRIPggDBAQAIAAcKzRIPggDBAQAAAA==.',
At='Attack:BAAANQAECgQIBgAAAA==.',
Ax='Axhure:BAAANQABCgMIAgAAAA==.',
Ba='Babydoll:BAAANQAECgQICAAAAA==.Bajablast:BAAANQADCgcIDQAAAA==.Barma:BAAANQAECgYICQAAAA==.',
Be='Bearlyseen:BAAANQAECgYIDAABNQAECgkJKQAJAHIcAA==.Beltirra:BAAANQADCgcIFgAAAA==.',
Bh='Bhangbros:BAAANQADCgcJBwAAAA==.',
Bi='Biggums:BAAANQADCggIDQAAAA==.Bigmobility:BAABNQAECoEcAAIKAAgKJSEoEQD9AgAKAAgKJSEoEQD9AgAAAA==.Bigwill:BAABNQAECoEfAAICAAgKPSKnAgABAwACAAgKPSKnAgABAwAAAA==.',
Bl='Blargy:BAABNQAECoEhAAIHAAgKPRk/JQBtAgAHAAgKPRk/JQBtAgAAAA==.Bleach:BAAANQAECgQIBQAAAA==.',
Bo='Borealslam:BAAANQADCgQIBAAAAA==.Bouzol:BAAANQAECgYIBgAAAA==.',
Br='Brighterbonk:BAAANQADCgUIBQABNQADCgYIEQAEAAAAAA==.Brimara:BAAANQAECgUIDAAAAA==.Brothaagamor:BAAANQADCgEIAQAAAA==.',
Bu='Bucketojoy:BAAANQAECgcICwAAAA==.',
['Bà']='Bàtman:BAAANQAECgMIAwAAAA==.',
Ca='Caliburne:BAABNQAECoEgAAMIAAgKnx2bQACPAgAIAAgK3BybQACPAgALAAMK3R0zHwDzAAAAAA==.Captamerica:BAAANQABCgQIBgAAAA==.Capz:BAACNQAFFIEUAAIIAAcK2x4nAgCRAgAIAAcK2x4nAgCRAgA1AAQKgR0AAggACQqsJXUTAFUDAAgACQqsJXUTAFUDAAAA.',
Ce='Cedrin:BAAANQADCgYIFAAAAA==.Ceez:BAAANQAECgIIAwAAAA==.',
Ch='Chichujongar:BAAANQAECgEIAQABNQAECgkJJwAMANkUAA==.Chickenstwip:BAAANQADCgEIAgABNQAECggIGwABAAgaAA==.Chosenöne:BAAANQADCgEIAQAAAA==.Chèn:BAAANQAECgYICwAAAA==.',
Ci='Cindrella:BAABNQAECoEeAAICAAkKdCVAAADZAwACAAkKdCVAAADZAwAAAA==.',
Cl='Clayre:BAABNQAECoE0AAINAAkKFiOaAAC1AwANAAkKFiOaAAC1AwAAAA==.Clow:BAAANQAECgMIBwAAAA==.',
Co='Colossus:BAAANQAECgEIAgAAAA==.Coolcrush:BAAANQADCgMIBgABNQAECgcIGAAOAGgkAA==.Corven:BAACNQAFFIEHAAIPAAMKiCDPDgAkAQAPAAMKiCDPDgAkAQA1AAQKgTEAAw8ACQpcI6gFAIUDAA8ACQpcI6gFAIUDAA0AAQpFBdh2ACcAAAAA.',
Cr='Craziks:BAAANQADCgIIAgAAAA==.Critzwar:BAABNQAECoEfAAIIAAkK3CFmGwAsAwAIAAkK3CFmGwAsAwAAAA==.Crönus:BAAANQADCggIEwAAAA==.',
Ct='Cthuluwu:BAAANQADCggICAAAAA==.',
Da='Daedyxes:BAAANQAECgUIDgAAAA==.Daní:BAAANQADCgUIBwABNQAECgEIAQAEAAAAAA==.Darkensi:BAAANQABCgYICQAAAA==.Dasherdeez:BAAANQADCgQJBwAAAA==.Daygath:BAAANQAECgEJAQAAAA==.',
De='Deadlyiris:BAABNQAECoEcAAIIAAgKlR6xPACdAgAIAAgKlR6xPACdAgABNQAFFAEIAQAEAAAAAA==.Deadshot:BAAANQADCgUICAAAAA==.Deatharin:BAAANQADCgUIBgAAAA==.Deathjak:BAAANQAECgYIBgABNQAECgYJEwAEAAAAAA==.Demonbulio:BAAANQAECgMIAwAAAA==.Demonisthicc:BAABNQAECoEiAAIQAAgK9Rw8BgC0AgAQAAgK9Rw8BgC0AgAAAA==.Demonslayeer:BAAANQADCggJDQAAAA==.Devi:BAAANQAECgUICwAAAA==.',
Di='Diaravynn:BAAANQADCgIIAgAAAA==.Dithehealer:BAAANQAECgYIEgAAAA==.Divain:BAAANQADCgQIBgAAAA==.',
Dk='Dkdi:BAAANQADCggIFwAAAA==.',
Do='Dozekar:BAAANQAECgEIAQAAAA==.',
Dr='Drenamai:BAAANQAECgIIBAAAAA==.Drexywexyuwu:BAAANQADCgcJBwAAAA==.',
Du='Duhmptruhk:BAABNQAECoEaAAIIAAgKXBZiWAA+AgAIAAgKXBZiWAA+AgAAAA==.Dunbroch:BAACNQAFFIENAAIRAAYK+wtBBQDCAQARAAYK+wtBBQDCAQA1AAQKgScAAhEACQqkHKUPAMgCABEACQqkHKUPAMgCAAAA.Duskforge:BAAANQABCgIJAgAAAA==.',
Dw='Dwagen:BAAANQAECgQIBAAAAA==.',
['Dé']='Démonicblood:BAABNQAECoEcAAISAAkKTRoEFwCNAgASAAkKTRoEFwCNAgAAAA==.',
Eg='Eggplantgodx:BAABNQAECoEdAAITAAgK0xiIHwBVAgATAAgK0xiIHwBVAgAAAA==.',
Ek='Ekhart:BAAANQAECgEIAQAAAA==.',
El='Elfajah:BAAANQADCgYICQAAAA==.Eliicia:BAABNQAECoEiAAMUAAkKFRzWDgDOAgAUAAkKFRzWDgDOAgAVAAgK+g16KgA7AQAAAA==.',
Em='Emmy:BAAANQAECgQIDwAAAA==.Emofineshyt:BAAANQADCgcICgAAAA==.Emogothbabe:BAABNQAECoEbAAMBAAgKCBp7awB1AgABAAgKCBp7awB1AgACAAMK8w5BIACrAAAAAA==.Emowrecky:BAAANQAECgcIEgAAAA==.',
En='Endo:BAABNQAECoErAAMWAAkK9iQsDwASAwAWAAgKIiQsDwASAwASAAcK9SCAHQBTAgAAAA==.Endorush:BAAANQAECgcIEAABNQAECgkJKwAWAPYkAA==.Endrigosa:BAAANQAECgIIAgAAAA==.Eneldenes:BAAANQAECgQIBgAAAA==.Enjoyer:BAAANQAECgQIBQAAAA==.',
Er='Ereitherla:BAAANQAECgMICAAAAA==.',
Es='Esmenet:BAAANQAECgYICwAAAA==.Espressð:BAAANQAECgYICAABNQAECggIGwABAAgaAA==.',
Ex='Excalibear:BAAANQAECgUICQABNQAECgkJKQAJAHIcAA==.',
Ey='Eydis:BAAANQADCgUIBwAAAA==.',
Fe='Feironor:BAAANQADCgQIBgAAAA==.Fenrys:BAAANQADCggIEwAAAA==.',
Fi='Fikareous:BAAANQADCggIDQABNQAECgUIBQAEAAAAAA==.',
Fl='Flayre:BAABNQAECoEaAAMXAAgKRhXFWQDEAQAXAAcKcBPFWQDEAQAJAAMKHAjZwwCNAAAAAA==.Fleredil:BAABNQAECoEZAAIYAAYKnSGNGABIAgAYAAYKnSGNGABIAgAAAA==.Flingernle:BAABNQAECoEUAAIXAAcKIB+TMAB2AgAXAAcKIB+TMAB2AgAAAA==.',
Fo='Forepray:BAABNQAECoEmAAIYAAkKHx/hCQAeAwAYAAkKHx/hCQAeAwAAAA==.Forger:BAABNQAECoEZAAILAAgKvwlQFgBlAQALAAgKvwlQFgBlAQAAAA==.Forsakey:BAAANQADCgYICwABNQAFFAQIBwAZACsZAA==.',
Fr='Fraun:BAAANQADCggJEQAAAA==.',
Fu='Fullyprotpal:BAAANQAECgEIAQAAAA==.Furioustotem:BAAANQAECgMICAAAAA==.Future:BAAANQADCgUIBgABNQAECgkJKAABABskAA==.',
Ga='Galten:BAAANQABCgUIBQAAAA==.Gantz:BAAANQADCgIJAgAAAA==.',
Ge='Geekbarr:BAAANQADCgUIBQABNQAECggIGwABAAgaAA==.',
Gh='Ghettox:BAAANQADCgIIAgAAAA==.Ghostw:BAAANQAECgQICAAAAA==.',
Gi='Giovanni:BAAANQAECggICAAAAA==.Gizik:BAAANQADCgcIBwABNQAFFAYIEAAYAM8RAA==.',
Gn='Gnasher:BAAANQABCgQIBAAAAA==.',
Go='Golgotterath:BAABNQAECoEpAAIJAAkKchzKMQBWAgAJAAkKchzKMQBWAgAAAA==.Gorm:BAAANQAECgcIEQABNQAECgQIBQAEAAAAAA==.',
Gr='Grippyshocks:BAAANQAECgIIAQABNQAECgkJGAATAKsgAA==.',
Ha='Halbruck:BAAANQAECgcIEQAAAA==.Haldane:BAABNQAECoEfAAIaAAgKAArHmgB/AQAaAAgKAArHmgB/AQABNQAFFAEIAQAEAAAAAA==.Harrydottur:BAAANQAECgYIBgABNQAECgkJKQAPAB8fAA==.Havochunter:BAAANQAECgMIAwAAAA==.',
He='Heidegger:BAAANQADCgYICgAAAA==.Helinndealin:BAABNQAECoElAAMbAAkKkCTiAABRAwAbAAgKvCTiAABRAwADAAgKLSL1LwBnAgAAAA==.Hellin:BAAANQADCgMIAQAAAA==.Heolstor:BAAANQAECggIEQAAAA==.Hephsdh:BAAANQAECgIIAwAAAA==.Heraois:BAAANQAECgUIDAAAAA==.Heriod:BAAANQABCgEIAQAAAA==.',
Hg='Hgshake:BAAANQADCgYIBgAAAA==.',
Ho='Holytës:BAAANQADCggIFQAAAA==.Holywráth:BAAANQADCgQIBgAAAA==.',
Hu='Hunterdh:BAAANQAECgQIBgAAAA==.',
Hy='Hynixx:BAAANQAECgcIDQABNQAECgkJJgAYAB8fAA==.',
Il='Illidope:BAABNQAECoEYAAQTAAkKqyAJDAAgAwATAAkKjSAJDAAgAwAcAAgKgBu5GABjAgAFAAEKFBmQIgBIAAAAAA==.',
In='Infinitevoid:BAAANQADCggIFQAAAA==.Innervatez:BAABNQAFFIEHAAIZAAUKix9SAgDtAQAZAAUKix9SAgDtAQAAAA==.Inteaus:BAAANQADCggIFgAAAA==.',
Io='Ionúin:BAAANQADCgQJBAAAAA==.',
Iv='Ivÿ:BAAANQADCgIJAgAAAA==.',
Ja='Jaekir:BAAANQAECgYIDwAAAA==.Jakfrost:BAAANQAECgYJEwAAAA==.Jakie:BAAANQADCgYICgABNQAECggIFwAIAM4YAA==.Jarten:BAABNQAECoErAAISAAkKsB2YDgDnAgASAAkKsB2YDgDnAgAAAA==.Jayaah:BAAANQADCgcIFgAAAA==.Jaylebate:BAAANQAECgMIAwAAAA==.',
Je='Jesseatamer:BAABNQAECoEpAAIdAAkKsSPVBgCOAwAdAAkKsSPVBgCOAwAAAA==.',
Ji='Jitsuru:BAAANQADCgUIBQAAAA==.',
Jo='Jox:BAAANQABCgUIBQAAAA==.Joxor:BAAANQABCgUIBQAAAA==.',
Js='Jstdeath:BAAANQADCgEIAQABNQAECgkJIgAIAIATAA==.Jstrawr:BAABNQAECoEiAAIIAAkKgBNbVABLAgAIAAkKgBNbVABLAgAAAA==.',
Ka='Kaln:BAAANQAECgIIAwABNQAECgQIBQAEAAAAAA==.Karen:BAAANQAECgUIDgAAAA==.Kasalu:BAAANQABCgQIBAAAAA==.Kastia:BAAANQADCgUJDgAAAA==.Katrynwel:BAAANQAECgQIBAAAAA==.Katsumi:BAAANQADCggIIQAAAA==.',
Ke='Keliki:BAAANQAECgcJEgAAAA==.Kellenah:BAAANQADCgUIBQAAAA==.Kettama:BAAANQADCggIEAABNQAECggIGwABAAgaAA==.',
Kh='Khold:BAAANQAECgYIDgAAAA==.Khrogann:BAAANQAECgMIBQAAAA==.',
Ki='Killalltoday:BAAANQAECgYIEAAAAA==.Kirkk:BAAANQAECgEIAQAAAA==.',
Kl='Klaminus:BAAANQADCgQJBAAAAA==.',
Kn='Knixx:BAACNQAFFIEHAAIDAAMKIRSNEgADAQADAAMKIRSNEgADAQA1AAQKgS8AAwMACQprJXcBAMgDAAMACQprJXcBAMgDABsABgrzEbULAE8BAAAA.Knuppelus:BAAANQADCgYICQAAAA==.',
Ko='Kobyashimaru:BAAANQADCgUIBQAAAA==.Koshi:BAAANQADCgMIAwAAAA==.Kotastrophe:BAAANQAECgMIAwABNQAECggIGgAIAFwWAA==.Koveras:BAAANQADCgYIBwAAAA==.Koyaanis:BAAANQADCggIDgAAAA==.Koyya:BAAANQAECgYJDQAAAA==.',
Kr='Krenmonk:BAAANQAECgEIAQAAAA==.Krennic:BAAANQADCgcIBwAAAA==.Krunchee:BAAANQADCggIEgAAAA==.',
Ku='Kufoo:BAAANQAECgYIEAAAAA==.Kurao:BAAANQAECgEJAgAAAA==.Kurukai:BAAANQADCgIIAgAAAA==.',
Ky='Kyrian:BAACNQAFFIENAAIVAAUK2huiAwDRAQAVAAUK2huiAwDRAQA1AAQKgSYAAhUACQrhIt8DAE8DABUACQrhIt8DAE8DAAAA.',
La='Lagøless:BAABNQAECoEYAAIdAAkKYSH+CAB3AwAdAAkKYSH+CAB3AwAAAA==.',
Le='Leo:BAAANQAECgEIAQAAAA==.',
Li='Likestoflash:BAEANQADCgYJBgABNQAECgkJJQAdAKMdAA==.Lissaris:BAAANQADCgEIAgAAAA==.',
Lo='Lohal:BAABNQAECoEgAAIPAAgKgxn+OQBoAgAPAAgKgxn+OQBoAgAAAA==.Lohmi:BAAANQAECgQIDgAAAA==.Lormn:BAAANQADCgEIAQAAAA==.',
Lu='Luania:BAAANQADCgUJDgAAAA==.',
Ly='Lyna:BAAANQADCggJDAAAAA==.Lyravega:BAAANQADCggICAAAAA==.Lyshkä:BAABNQAECoEeAAIeAAgKLxquDQBkAgAeAAgKLxquDQBkAgAAAA==.Lyzzardkng:BAAANQAECgcIDwAAAA==.',
['Lý']='Lýra:BAAANQAECgMIAwAAAA==.',
Ma='Maango:BAAANQAECggIEAAAAA==.Maemu:BAAANQABCgUIBQAAAA==.Magerthat:BAAANQADCgQIBgAAAA==.Magicaltickl:BAAANQAECgcIEwAAAA==.Magiki:BAAANQADCgcICwAAAA==.Malkala:BAAANQADCgMIAwAAAA==.Malonormu:BAAANQABCgYIBAAAAA==.Mamadeezy:BAAANQADCgYJCwAAAA==.Mando:BAAANQADCggIHgABNQAECgMICAAEAAAAAA==.Manical:BAAANQAECgIIAgAAAA==.Marcel:BAAANQADCgYIEQAAAA==.Mashiach:BAABNQAECoEiAAMDAAkKZyMACABkAwADAAkKZyMACABkAwAYAAEKXRMWXwA4AAAAAA==.Matthyjsz:BAAANQADCgIIAgAAAA==.',
Me='Megumin:BAAANQAECgQIBwABNQAECggIIAAaABghAA==.Melikefire:BAABNQAECoEbAAIBAAkKWRj6awB0AgABAAkKWRj6awB0AgAAAA==.Memecompdall:BAAANQADCgcIDQAAAA==.Merek:BAAANQAECgYIDQAAAA==.Mettix:BAAANQADCgIIAgAAAA==.',
Mi='Mirigosa:BAAANQAECgEIAQABNQAECgkJHgACAHQlAA==.Mistybdk:BAAANQAECgUIBQABNQAFFAUIDgAfALwZAA==.Mistyd:BAACNQAFFIEOAAIfAAUKvBncAACsAQAfAAUKvBncAACsAQA1AAQKgS4AAh8ACQq4I30BAKcDAB8ACQq4I30BAKcDAAAA.',
Mo='Mogfooyen:BAAANQABCgQIBgAAAA==.Moonbeam:BAAANQAECgEIAQAAAA==.Morgause:BAAANQAECgQIBQAAAA==.Morllan:BAAANQAECgcIEAAAAA==.',
Mu='Muirdin:BAAANQADCgEJAQAAAA==.',
My='Mykinlive:BAAANQADCgIIAgAAAA==.',
['Må']='Mångix:BAAANQADCgcICQAAAA==.',
['Mé']='Mélusine:BAAANQAECgcIDQAAAA==.',
Na='Naanomage:BAAANQADCggIGQAAAA==.Naija:BAAANQADCgIIAgAAAA==.Narcotx:BAAANQADCgIIAgAAAA==.',
Ne='Necrotoxin:BAAANQADCgYIBgAAAA==.',
Ni='Nightmaratic:BAAANQADCgYIBgAAAA==.Nightsdeath:BAAANQAECgEIAQAAAA==.Nightsever:BAABNQAECoEfAAIcAAgKEyRqBwBIAwAcAAgKEyRqBwBIAwAAAA==.Nirath:BAAANQAECgYIEAAAAA==.',
No='Noiire:BAAANQAECgcICQABNQAECgkJIgAUABUcAA==.',
Od='Odysse:BAAANQADCgYICQAAAA==.Odyssé:BAAANQAECgcIDwAAAA==.',
Ok='Okami:BAAANQAECgQIBwAAAA==.',
Oo='Ooyagoddess:BAAANQADCgEIAQAAAA==.',
Or='Orryck:BAAANQADCgQIBQAAAA==.',
Pa='Pacamonk:BAABNQAECoEdAAIgAAgKRiHcCgD6AgAgAAgKRiHcCgD6AgAAAA==.Papatiny:BAAANQADCgIIAgAAAA==.Pawsa:BAAANQAECgQIBgABNQAECggIGwABAAgaAA==.Pawthetic:BAABNQAECoEuAAMHAAkKJB4JFQD3AgAHAAkKJB4JFQD3AgAZAAgKfh38DADHAgAAAA==.',
Pe='Peelforheals:BAABNQAECoEnAAMYAAkKoh1KCwAIAwAYAAkKoh1KCwAIAwAbAAQKuAt3EgDGAAAAAA==.Penguindemic:BAABNQAECoEXAAMPAAcKpSWeGAD2AgAPAAcKpSWeGAD2AgANAAEKoCJ1XgBRAAAAAA==.Pep:BAAANQAECgQIBwAAAA==.Pepperoni:BAAANQADCggIDQAAAA==.Perdator:BAAANQAECgQIBQAAAA==.Petruccius:BAACNQAFFIEHAAIHAAMK0hRtDwD9AAAHAAMK0hRtDwD9AAA1AAQKgTEAAgcACQqyHpQNAEADAAcACQqyHpQNAEADAAAA.Pewpewlepew:BAAANQAECgQICQAAAA==.',
Ph='Phaeku:BAAANQADCgMIAwAAAA==.',
Pi='Picklebreath:BAAANQADCgUICgAAAA==.Pinksparklez:BAAANQADCgUICAABNQAECgEIAQAEAAAAAA==.',
Pl='Plague:BAAANQAECgMIAgAAAA==.',
Po='Poptartsz:BAAANQAECgQICQAAAA==.Potatolockx:BAAANQAECgQIAwAAAA==.',
Pr='Precht:BAAANQADCgcIEwAAAA==.Prikarea:BAAANQAECgUIBQAAAA==.Prumper:BAABNQAECoEYAAIBAAgKThMElQASAgABAAgKThMElQASAgAAAA==.',
Pu='Purah:BAAANQADCgEIAgAAAA==.',
Qu='Quesoblanco:BAAANQAECgYIDQAAAA==.',
Qy='Qybxboogietk:BAAANQAECgcIDQAAAA==.',
Ra='Rabid:BAAANQADCgUICAAAAA==.Raghallov:BAAANQAECgIIBAAAAA==.Rampa:BAAANQADCgYIEQABNQAECggIGwABAAgaAA==.',
Re='Reaperan:BAAANQAECgEIAQAAAA==.Regena:BAABNQAECoEjAAMDAAgKSgY8aQB6AQADAAgKSgY8aQB6AQAYAAIKaALFWQBGAAAAAA==.Remorse:BAACNQAFFIEHAAILAAMK0xakAgDZAAALAAMK0xakAgDZAAA1AAQKgTEAAgsACQoWItMEAPMCAAsACQoWItMEAPMCAAAA.Rendwick:BAAANQADCgYICQAAAA==.',
Ri='Rim:BAAANQAECgYIEwAAAA==.',
Ro='Ronfar:BAACNQAFFIEFAAIOAAMK5BZLAgAeAQAOAAMK5BZLAgAeAQA1AAQKgS8AAg4ACQpxIh8DAFkDAA4ACQpxIh8DAFkDAAAA.',
Ru='Rustyglass:BAAANQABCgYIBAAAAA==.Ruttisðir:BAAANQAECgIIAwAAAA==.',
Ry='Ryhorn:BAAANQADCggIDgAAAA==.Ryno:BAAANQADCgUIBwAAAA==.Ryujin:BAAANQAECgYIDAAAAA==.Ryù:BAAANQADCggIIAAAAA==.',
Sa='Salo:BAAANQADCgMIBgAAAA==.Sanazenet:BAAANQADCggJDAAAAA==.Saphiriel:BAAANQAECgMIBAAAAA==.Saviorself:BAAANQADCgMIAwABNQAECgkJLgAHACQeAA==.',
Sc='Scarscar:BAAANQAECgUICAAAAA==.Schwinn:BAAANQADCgQIBAAAAA==.',
Se='Segarth:BAAANQAECgYIBwAAAA==.Selen:BAAANQAECgcIDQAAAA==.Semballin:BAAANQABCgMJAwAAAA==.Seswatha:BAAANQAECgUIBQABNQAECgkJKQAJAHIcAA==.',
Sh='Shamandroo:BAAANQAECgcIEAABNQAFFAMIBwAGAHYdAA==.Shamdi:BAAANQADCgYIBgAAAA==.Shanghaied:BAAANQADCgcIDAAAAA==.Shawtyy:BAAANQADCgMJAwAAAA==.Shmongus:BAAANQADCgIIAgABNQAECgQIBQAEAAAAAA==.Shortandold:BAAANQAECgYIDAAAAA==.Shådowfire:BAAANQAECgEIAQAAAA==.Shìft:BAABNQAECoEcAAIZAAgKBhhaFQBSAgAZAAgKBhhaFQBSAgAAAA==.',
Si='Sintram:BAAANQAECgMIAwAAAA==.',
Sl='Slighted:BAAANQADCggIJQABNQAECgUIDAAEAAAAAA==.Slimydruid:BAAANQAECgIIAwAAAA==.Slow:BAABNQAECoEoAAIBAAkKGyQdEQCAAwABAAkKGyQdEQCAAwAAAA==.',
Sm='Smokinontech:BAAANQADCgQIBAABNQAECggIGwABAAgaAA==.Smokze:BAAANQADCggJCAAAAA==.',
So='Sockoh:BAAANQAECgYJDgAAAA==.Solera:BAEANQADCggICAAAAA==.Sonicberger:BAAANQADCgYIGQABNQAECgYIDQAEAAAAAA==.Soniko:BAAANQAECgUIDAAAAA==.Sonícberger:BAAANQAECgYIDQAAAA==.Soulcaliber:BAAANQADCgQIBAAAAA==.',
St='Stain:BAAANQAECgQJCAAAAA==.Stealth:BAAANQAECgQIBAABNQAECgYIEAAEAAAAAA==.Stinkfist:BAAANQADCgYICgAAAA==.Stonehenge:BAAANQAFFAEIAQAAAA==.Stonepalm:BAAANQADCgYIDgAAAA==.Stratan:BAAANQADCgIIAgABNQADCgQJBAAEAAAAAA==.Strawk:BAAANQAECgYIDQAAAA==.',
Su='Suffer:BAAANQADCggICQABNQAECgkJKAABABskAA==.Sunlight:BAAANQADCgYIBgAAAA==.Supercat:BAAANQAECgEIAQAAAA==.Surf:BAAANQAECgMIBQAAAA==.',
Sw='Swankydranky:BAABNQAECoEnAAQMAAkK2RSMEACcAQAMAAcK+hOMEACcAQAgAAkKBhNMJQCWAQAeAAEK9gK+QwAkAAAAAA==.Swankypally:BAAANQAECgcICgABNQAECgkJJwAMANkUAA==.',
Sy='Syesc:BAAANQABCgQJBAAAAA==.Sylandris:BAAANQADCgIIAgAAAA==.',
['Sá']='Sásukeuchiha:BAAANQADCgYIBgABNQAECgYIDQAEAAAAAA==.',
Ta='Tabbz:BAABNQAECoEYAAIXAAcKmRnWRQARAgAXAAcKmRnWRQARAgAAAA==.Tallael:BAAANQAECgcIEQAAAA==.Tallyhochick:BAABNQAECoEaAAIdAAgKPQ0wYQD/AQAdAAgKPQ0wYQD/AQAAAA==.Taman:BAABNQAECoEbAAIJAAgKNx2IKwB1AgAJAAgKNx2IKwB1AgAAAA==.Taylerswift:BAAANQAECgEJAQAAAA==.',
Th='Thebestname:BAAANQAECgYICAAAAA==.Thebigonion:BAAANQADCgcIEwAAAA==.Theexile:BAABNQAECoEaAAMVAAgK3hkcGwDYAQAVAAYKVRgcGwDYAQAUAAYKxhMGMwCWAQAAAA==.Theigh:BAAANQAECgEIAQAAAA==.Thonard:BAAANQAECgUIBQABNQAECggIHgAWANckAA==.',
Ti='Tinydeath:BAABNQAECoEfAAIKAAgKARWLNgDvAQAKAAgKARWLNgDvAQAAAA==.Tinyfu:BAAANQADCgQIBAAAAA==.Tinytamer:BAAANQAECgcIEQABNQAECggIHwAKAAEVAA==.',
Tm='Tmakrist:BAAANQAECgEIAgAAAA==.',
To='Toko:BAABNQAECoEhAAIdAAkK0COwDwBAAwAdAAkK0COwDwBAAwAAAA==.Tomblord:BAAANQAECgYICgAAAA==.',
Tr='Trailblazah:BAAANQAECgUIBwAAAA==.Treeheals:BAAANQADCggICAAAAA==.Truthes:BAAANQADCgYIBwABNQAECgYIEAAEAAAAAA==.Truths:BAAANQADCgIJAgABNQAECgYIEAAEAAAAAA==.Truthsx:BAAANQAECgYIEAAAAA==.Truthy:BAAANQADCgYICAABNQAECgYIEAAEAAAAAA==.Truthz:BAAANQADCgYJBgABNQAECgYIEAAEAAAAAA==.',
Ts='Tsukúne:BAAANQADCgQIBAAAAA==.',
Ty='Tyg:BAAANQADCggIDAAAAA==.Tylaatape:BAAANQAECggIDQAAAA==.Tyraell:BAAANQAECgMIBgAAAA==.',
['Tõ']='Tõkó:BAAANQADCgUIBQABNQAECgkJIQAdANAjAA==.',
Um='Umbrae:BAAANQADCgMIAQAAAA==.Umfray:BAAANQAECgIIAwABNQAECgMIBwAEAAAAAA==.',
Us='Usgasdanelv:BAABNQAECoEWAAIOAAkKQhYZCQCzAgAOAAkKQhYZCQCzAgAAAA==.',
Uz='Uzala:BAAANQAECgIIAgAAAA==.',
Va='Vanleiden:BAAANQADCgEIAQAAAA==.Vazro:BAABNQAECoEdAAMGAAcKWhQgWQDEAQAGAAcKWhQgWQDEAQAaAAYKMgYxzwAJAQAAAA==.',
Ve='Vendiyre:BAAANQAECgYIBgAAAA==.Venthyl:BAABNQAECoEgAAIHAAkKESUHBwCIAwAHAAkKESUHBwCIAwAAAA==.Veyra:BAAANQABCgMIAwAAAA==.',
Vi='Vizan:BAAANQABCgcIBwABNQAECgYIEAAEAAAAAA==.',
Wa='Warzone:BAAANQADCgUIBQAAAA==.',
We='Wellby:BAAANQADCgcIGgAAAA==.Westerin:BAAANQAECgYIEAAAAA==.',
Wi='Wildnature:BAAANQADCgYIBgAAAA==.Wimateeka:BAAANQAECgYIEwAAAA==.Windfury:BAAANQAECgYICAABNQAECgkJKAABABskAA==.Windigo:BAAANQAECgIIAgAAAA==.Winginit:BAAANQAECgEIAQABNQAECgkJLgAHACQeAA==.',
Wo='Wooqles:BAAANQADCgUIBQABNQADCgYICAAEAAAAAA==.',
Wr='Wrastelas:BAAANQABCgEIAQABNQABCgIIAgAEAAAAAA==.',
Wu='Wuilhem:BAAANQADCgEIAQAAAA==.',
Xa='Xaala:BAAANQAECgQIBQAAAA==.',
Xo='Xosderdk:BAAANQADCgIIAgAAAA==.',
Ya='Yarjuul:BAAANQAECgIIAgABNQAECgMIBwAEAAAAAA==.',
Ye='Yespaladin:BAABNQAECoEqAAIKAAkKJR/TDQAeAwAKAAkKJR/TDQAeAwAAAA==.',
Yi='Yimity:BAAANQAECgMIAwAAAA==.',
Yo='Yogí:BAACNQAFFIEHAAIJAAMKxxXWDgDxAAAJAAMKxxXWDgDxAAA1AAQKgSYAAgkACQodIdEYAN8CAAkACQodIdEYAN8CAAAA.Yozomoto:BAABNQAECoEoAAMdAAkKcCERHgDqAgAdAAkKcCERHgDqAgARAAIKEQw3XABmAAAAAA==.',
Za='Zalandria:BAAANQAECgUIBwAAAA==.',
Ze='Zeltemis:BAAANQAECgYIDQAAAA==.',
Zi='Zipsion:BAABNQAECoEZAAIdAAcKmyHZLQCkAgAdAAcKmyHZLQCkAgAAAA==.Zivver:BAABNQAECoEYAAILAAcKCyIYBwCmAgALAAcKCyIYBwCmAgAAAA==.Zizka:BAAANQAECgYIEgAAAA==.',
Zo='Zolandir:BAAANQADCggICwAAAA==.',
['Üt']='Üther:BAABNQAECoEgAAIaAAgKGCGBKQDnAgAaAAgKGCGBKQDnAgAAAA==.',
['ßu']='ßubbleøseven:BAAANQAECgEIAQAAAA==.',
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
