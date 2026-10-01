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

local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Druid-Guardian','Priest-Holy','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Warlock-Demonology','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','DemonHunter-Devourer','Rogue-Assassination','Priest-Discipline','Warlock-Affliction','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','Shaman-Elemental','DemonHunter-Vengeance','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Rogue-Subtlety','Warlock-Destruction','Hunter-Survival','Shaman-Restoration','Paladin-Protection',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abashai:BAAANQAECgYIDwAAAA==.',
Ae='Aellyria:BAAANQADCgEIAQAAAA==.Aerrikon:BAAANQAECgEIAQABNQAECgMJCQABAAAAAA==.',
Ak='Akaili:BAAANQAECgQIBwAAAA==.',
Al='Alexiya:BAAANQAECgYIEgAAAA==.Allacari:BAAANQAECgUIDgAAAA==.Allumer:BAAANQAECgEIAQAAAA==.Alodir:BAAANQADCgYICgABNQAECgQJBgABAAAAAA==.Alstadin:BAAANQADCgMJAwAAAA==.Alucardd:BAAANQAECgIIAgAAAA==.',
Am='Amanda:BAAANQAECgUIEQAAAA==.Amonamarth:BAAANQAECgYIDQAAAA==.',
An='Anabelleigh:BAAANQABCggIDwAAAA==.Andrise:BAAANQAECgUIEAAAAA==.Annathesia:BAAANQADCgEIAQAAAA==.Antibear:BAAANQAECgQICgAAAA==.',
Ap='Apol:BAAANQAECgUJDAAAAA==.',
Ar='Arachne:BAABNQAECoEaAAMCAAgK3hgmBgBZAgACAAgK3hgmBgBZAgADAAQKng5aJwH7AAAAAA==.Arakar:BAABNQAECoEdAAIEAAgKegwYWgDAAQAEAAgKegwYWgDAAQAAAA==.Aralynne:BAAANQAECgQICQAAAA==.Arcee:BAAANQADCgIIAgAAAA==.Arch:BAAANQADCggIIAAAAA==.Ardori:BAAANQAECgYICgAAAA==.Arlïnn:BAAANQAECgQIBgABNQAECgcICwABAAAAAA==.Armorya:BAABNQAECoEhAAIFAAkKVxr3RwBwAgAFAAkKVxr3RwBwAgAAAA==.Armyofone:BAAANQAECgMIBAAAAA==.Artaius:BAABNQAECoEWAAIGAAYKYSVGCACQAgAGAAYKYSVGCACQAgAAAA==.Arthonius:BAAANQADCgQIBAAAAA==.Arthuun:BAAANQAECggIEAAAAA==.Artom:BAAANQADCgUJBQAAAA==.',
As='Ashaw:BAAANQADCgYIBgAAAA==.Astariel:BAAANQADCggICAABNQAECgYIDgABAAAAAA==.Astarog:BAAANQAECgUIDQAAAA==.',
At='Atafloosy:BAEANQAECgQICgAAAA==.Athelf:BAAANQAECgcIDgAAAA==.Attina:BAAANQABCgEIAQAAAA==.',
Au='Aubriell:BAAANQAECgQIBAAAAA==.',
Ay='Ayrnerdam:BAAANQAECgUICQAAAA==.',
Ba='Babelfish:BAAANQAECgYIEQAAAA==.Bagleflinger:BAAANQAECgQICAAAAA==.Baldr:BAAANQAECgQJBgAAAA==.Batarang:BAAANQAECgUIEgAAAA==.',
Be='Bealzulbub:BAAANQABCgQIBwAAAA==.Bearbarian:BAABNQAECoEaAAIGAAgKQQvwGABdAQAGAAgKQQvwGABdAQAAAA==.Beastkael:BAAANQAECgMIAwAAAA==.Beg:BAABNQAECoEfAAIHAAgKfxHqTgDiAQAHAAgKfxHqTgDiAQAAAA==.Belfalas:BAAANQABCgQIBgAAAA==.Berghain:BAAANQADCgQJAgAAAA==.Berick:BAAANQAECgEIAgAAAA==.Betzalel:BAAANQAECgYIDgAAAA==.Beytryx:BAAANQAECgIJAwAAAA==.',
Bi='Bittycakes:BAAANQADCgUIBQAAAA==.',
Bl='Bladeoftruth:BAAANQAECgcIEwAAAA==.Blaize:BAAANQADCgMIAwAAAA==.Blitzwing:BAAANQAECgEIAQAAAA==.Bloodyaggro:BAAANQAECgQIBAAAAA==.',
Bo='Bobapstab:BAAANQADCgEIAQAAAA==.Bonnabelle:BAABNQAECoEcAAIHAAgKgAT3bgBkAQAHAAgKgAT3bgBkAQAAAA==.Boombawks:BAAANQAECgEIAQAAAA==.Bos:BAAANQAECgUIBgAAAA==.Bowtoahh:BAAANQABCgEIAQABNQAECgYIEgABAAAAAA==.',
Br='Brewnelle:BAAANQADCggIDgABNQAECgcJFwAIANoaAA==.Briest:BAAANQAECgQIBAABNQAECgcJFwAIANoaAA==.Bruid:BAABNQAECoEXAAMIAAcK2hrBIQC8AQAIAAYKIhnBIQC8AQAJAAcKhRKZPgCzAQAAAA==.Bruneigin:BAAANQAECgIIAgAAAA==.',
Ca='Cailey:BAAANQAECgIIAgAAAA==.Calzone:BAAANQADCgYIBgAAAA==.Cambria:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Cardian:BAAANQADCgcIEwAAAA==.Caridin:BAAANQADCgYIEgAAAA==.Carmey:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.Carrin:BAABNQAECoEvAAIFAAgKBCDZOwCbAgAFAAgKBCDZOwCbAgAAAA==.Catalyia:BAABNQAECoEaAAIKAAgKbQ55WwAPAgAKAAgKbQ55WwAPAgAAAA==.Catris:BAAANQADCggIJgAAAA==.Catset:BAAANQAECgYIEAAAAA==.',
Ce='Cecea:BAAANQABCggIFAAAAA==.',
Ch='Charades:BAAANQADCgYIDAAAAA==.Charlton:BAAANQAECgQIBwABNQAECgcIEAABAAAAAA==.Chazzo:BAAANQAECgcIEwAAAA==.Chazzy:BAAANQADCgcIBwAAAA==.Chila:BAAANQAECgIIAgAAAA==.',
Co='Commy:BAAANQAECgYIEQAAAA==.Concorde:BAAANQAECgQJCAAAAA==.Copiousconns:BAAANQAECgUIEwAAAA==.Corlock:BAAANQADCgYIDAAAAA==.',
Cr='Craitos:BAAANQABCgYIDQAAAA==.Cranjis:BAAANQAECgYIBgAAAA==.Crimsonfury:BAAANQAECgEIAQAAAA==.',
Cu='Cubos:BAABNQAECoEdAAILAAkKYiSXAgC6AwALAAkKYiSXAgC6AwAAAA==.Cutlash:BAAANQADCggIIAAAAA==.Cutslash:BAAANQADCgUJBQABNQADCggIIAABAAAAAA==.',
Cy='Cynaea:BAAANQADCgQJBAABNQAECgcIEAABAAAAAA==.',
Da='Daemona:BAAANQAECgcIEgAAAA==.Daieniceis:BAAANQAECgQICAAAAA==.Dalkurn:BAACNQAFFIELAAIIAAUKAhwIAwDEAQAIAAUKAhwIAwDEAQA1AAQKgSMAAggACQrrI5YEAF4DAAgACQrrI5YEAF4DAAAA.',
De='Decayy:BAACNQAFFIELAAIMAAUK+hcbCACJAQAMAAUK+hcbCACJAQA1AAQKgSMAAgwACQrIIjsNACQDAAwACQrIIjsNACQDAAAA.Deceptakahn:BAABNQAECoEUAAIGAAYKCwP2KADBAAAGAAYKCwP2KADBAAAAAA==.Derailedbeef:BAABNQAECoEhAAMNAAkKZxWDTgBfAgANAAkK9hSDTgBfAgAOAAIK+xkvGwCeAAAAAA==.Deydoralia:BAABNQAECoEmAAIEAAkKMSG4CABnAwAEAAkKMSG4CABnAwAAAA==.',
Di='Diabeetus:BAAANQADCgQICAAAAA==.',
Dn='Dnme:BAABNQAECoEbAAIPAAgKAg1RJADpAQAPAAgKAg1RJADpAQAAAA==.',
Do='Doneldus:BAAANQAECgIIAgAAAA==.Dool:BAAANQADCgcIDgAAAA==.Dorfdragon:BAAANQAECgQIDgAAAA==.Dorfe:BAABNQAECoEeAAIQAAgKqBI/HwAtAgAQAAgKqBI/HwAtAgAAAA==.',
Dr='Drakona:BAAANQABCgQICAAAAA==.Drakthur:BAAANQADCgUIDAAAAA==.Draximus:BAAANQADCgUIBQAAAA==.Drewgarymore:BAAANQAECgYIEgAAAA==.',
Du='Dukker:BAAANQABCgIIAgAAAA==.Durandall:BAACNQAFFIEFAAIFAAIKjwiNGgCDAAAFAAIKjwiNGgCDAAA1AAQKgR4AAgUACQreGY1SAEwCAAUACQreGY1SAEwCAAAA.Durleap:BAAANQAECgQIBAAAAA==.Durthmaul:BAAANQAECgUIBgAAAA==.',
Dw='Dwarflock:BAAANQAECgYIEQAAAA==.',
Dy='Dylpickl:BAAANQAFFAIIAgAAAA==.Dylán:BAAANQAECgQIBAAAAA==.Dymàs:BAAANQAECgQIBwAAAA==.',
Ef='Eft:BAAANQABCgQIBAAAAA==.',
El='Elliemae:BAAANQAECgEIAQAAAA==.Elow:BAAANQADCgIIAgAAAA==.',
Er='Erazminash:BAAANQAECgMJBAAAAA==.',
Es='Esdeáth:BAAANQADCgIIAgAAAA==.Esmae:BAAANQAECgQIBAAAAA==.Ess:BAAANQADCggIIQAAAA==.',
Ev='Evalina:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.Evvie:BAAANQAECgIIAgAAAA==.',
Ex='Executiepie:BAAANQADCggICAAAAA==.',
Fa='Fabulosoo:BAAANQAECgUIEwAAAA==.Falcondor:BAAANQADCgMIAwAAAA==.Fantarius:BAABNQAECoEkAAMHAAkKTiFtHADNAgAHAAkKTiFtHADNAgARAAEKiAVmJQArAAAAAA==.Fantazee:BAAANQADCgUIBQABNQAECgkJJAAHAE4hAA==.Fatdono:BAAANQAECgYIEQAAAA==.',
Fi='Fibbs:BAAANQAECgQICgAAAA==.Fikti:BAABNQAECoEdAAISAAgKMBnZAwBsAgASAAgKMBnZAwBsAgAAAA==.Firetongue:BAAANQADCgUJBQAAAA==.Firocios:BAAANQAECgUIDgAAAA==.',
Fl='Flaminia:BAAANQADCgUICQAAAA==.',
Fo='Fossilz:BAAANQADCggJCAAAAA==.Foxybeans:BAAANQADCgYICgAAAA==.',
Fr='Fran:BAAANQAECgUIDQAAAA==.Frieda:BAAANQABCgIIAgAAAA==.Frink:BAAANQADCggIIgAAAA==.Frostyfella:BAABNQAECoEhAAIDAAkKcx9pMwAHAwADAAkKcx9pMwAHAwABNQABCgIIAgABAAAAAA==.',
Fu='Furman:BAAANQADCgMIAwAAAA==.Fuzzycakes:BAAANQADCggICAAAAA==.',
['Fá']='Fáith:BAAANQADCggIGAAAAA==.',
Ga='Garypotter:BAAANQAECgYIEQAAAA==.Gazooks:BAAANQADCgQIBwAAAA==.',
Ge='Gelantria:BAAANQADCgcIBwAAAA==.',
Gi='Gillacs:BAAANQADCgMJAwAAAA==.',
Gl='Gleave:BAABNQAECoEZAAIKAAgKPSC/HwDhAgAKAAgKPSC/HwDhAgAAAA==.Glâdiátor:BAAANQADCgMIAwAAAA==.',
Go='Goodbrew:BAAANQAECgQICAAAAA==.',
Gr='Greystoke:BAAANQADCgQIBAAAAA==.Greyvee:BAAANQAECgIIBAAAAA==.Grindelbald:BAAANQAECgcIEwAAAA==.',
Gt='Gtfofupá:BAAANQAECgIIAgAAAA==.',
Gu='Gushee:BAAANQAECgQIEAAAAA==.',
Gw='Gwenn:BAAANQADCgYIEgAAAA==.',
Gy='Gyes:BAAANQAECgIIAgAAAA==.',
Ha='Hadez:BAAANQADCgcICwAAAA==.Hae:BAAANQADCgEIAQAAAA==.Haegan:BAAANQABCgYIBwAAAA==.Hagioszoe:BAAANQAECgQJCAAAAA==.Hairypoóter:BAAANQADCgUICQAAAA==.Hanamari:BAACNQAFFIEIAAITAAUKXwe8BQBVAQATAAUKXwe8BQBVAQA1AAQKgRoAAxMACQooFo8aABUCABMACQooFo8aABUCABQAAQrrAV1GAB0AAAAA.Hanoe:BAAANQADCggICAAAAA==.Harakrron:BAAANQADCgUICgAAAA==.Harleyquìnn:BAAANQADCgcIEAAAAA==.Harydresden:BAAANQAECgUICgAAAA==.Hawkesmage:BAAANQAECgIIAgAAAA==.Hawkslayer:BAAANQADCggIHgAAAA==.Hazule:BAAANQAECgIIAwABNQAECgYIEQABAAAAAA==.',
He='Hedgelord:BAABNQAECoEgAAIJAAgKLx/lHACxAgAJAAgKLx/lHACxAgAAAA==.',
Hi='Hisky:BAAANQAECgQIBgAAAA==.',
Ho='Hobe:BAABNQAECoEYAAILAAcKZx/4OQBoAgALAAcKZx/4OQBoAgAAAA==.Holytruck:BAAANQADCgEIAQAAAA==.Hoodmagik:BAAANQABCgYIBwABNQAECgkJFwALAGsUAA==.Hornadus:BAAANQADCgMIAwAAAA==.Hornride:BAAANQADCgMIAwAAAA==.',
Hu='Humoresque:BAAANQADCggIIQAAAA==.Huntaredead:BAAANQAECgQIBgABNQAECgkJIAALAEMhAA==.',
Ic='Icyblades:BAAANQAECgYIDwAAAA==.',
Il='Ilidania:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Ilyna:BAAANQAECgYIEgAAAA==.',
Im='Immortalnut:BAAANQAECgYIEAAAAA==.',
In='Inori:BAAANQADCgcIBwAAAA==.Interrupted:BAAANQAECgIIAgAAAA==.',
It='Itscell:BAAANQADCgEIAQAAAA==.Ittyycakes:BAAANQADCgcIBwAAAA==.',
Ja='Jaedis:BAAANQAECgUICQAAAA==.Jaktar:BAAANQAECgcIDwAAAA==.Jane:BAAANQADCgMIAgAAAA==.Janet:BAAANQAECgcIEwAAAA==.Jani:BAAANQADCgQIBAABNQAECgcIEwABAAAAAA==.Janiina:BAAANQADCgYIDQAAAA==.',
Je='Jezak:BAAANQADCgIIAgABNQAECgQJBgABAAAAAA==.',
Jo='Jol:BAAANQABCgQIBAAAAA==.Jone:BAAANQAECgQIBAAAAA==.Joobs:BAAANQAECgYIDgAAAA==.Joosh:BAAANQAECgUIBQAAAA==.',
Js='Jslice:BAACNQAFFIEHAAINAAQKkBINEABDAQANAAQKkBINEABDAQA1AAQKgRkAAg0ACQqfH742ALMCAA0ACQqfH742ALMCAAAA.',
Ju='Juda:BAAANQAECgQIBQAAAA==.Jurant:BAAANQABCgQJAwAAAA==.Jurucil:BAAANQAECgEIAQAAAA==.',
Ka='Kaelys:BAAANQAECgQICwAAAA==.Kahliea:BAAANQADCggIJgAAAA==.Kaidance:BAAANQAECgEJAQAAAA==.Kaisaze:BAAANQADCggIIAAAAA==.Kapachka:BAAANQAECgIIAgAAAA==.Karbide:BAAANQADCgQIBQAAAA==.Kardisa:BAAANQABCgIIAgAAAA==.Kateri:BAAANQADCgcJHQAAAA==.Katmarie:BAAANQAECgIIAgAAAA==.Kazothor:BAAANQADCggIJgAAAA==.',
Ke='Keria:BAACNQAFFIETAAIVAAcKXx+eAADGAgAVAAcKXx+eAADGAgA1AAQKgTEAAhUACQrPJXIBANwDABUACQrPJXIBANwDAAAA.Keyz:BAAANQAECgYICwAAAA==.',
Ki='Kiretsu:BAABNQAECoEXAAMCAAkKohIjEQBPAQADAAgKew2ctADNAQACAAUKCRQjEQBPAQAAAA==.',
Ko='Kovus:BAAANQAECgIIAgAAAA==.',
Kr='Kragami:BAAANQAECgQIBAAAAA==.Krelien:BAAANQAECgUICgAAAA==.Krispee:BAAANQAECgYICwAAAA==.Kristanya:BAAANQAECgUIEwAAAA==.',
Ks='Ks:BAAANQADCgMIAwAAAA==.',
Ku='Kulaidmage:BAAANQAECgcIEgAAAA==.Kurtcowbain:BAAANQAECgYIEgAAAA==.Kushies:BAAANQADCgUIBQAAAA==.',
Ky='Kynetik:BAAANQAECggICAABNQAFFAQICAAWAIwDAA==.Kyttin:BAAANQADCggICAAAAA==.',
La='Ladamirea:BAABNQAECoEgAAIXAAgKISNTAgAoAwAXAAgKISNTAgAoAwAAAA==.Lamashtu:BAAANQAECgYIEgAAAA==.Lashar:BAAANQADCgYIBgAAAA==.Layssar:BAAANQADCgUJBQAAAA==.',
Le='Leiman:BAAANQABCgQIBQAAAA==.Lenabug:BAAANQABCgIIAgAAAA==.Lexiê:BAAANQAECgUIDQAAAA==.',
Li='Lightninjack:BAAANQAECgEIAQAAAA==.Lightsworn:BAAANQADCgEIAQAAAA==.Lilifa:BAAANQAECgUIDwAAAA==.Lilillidari:BAABNQAECoEcAAIVAAkKChz9EQDZAgAVAAkKChz9EQDZAgABNQAFFAUIDAAYAIQUAA==.Lillirann:BAAANQAECgEIAQAAAA==.Lilmontaro:BAACNQAFFIEMAAQYAAUKhBSDBwADAQAYAAMK5xaDBwADAQAZAAEKORuNEwBSAAAMAAEKpwbKKwAgAAA1AAQKgS8AAxgACQomJi4HAEwDABgACQpUIy4HAEwDABkACAqkIIwdAJQCAAAA.Lilunholy:BAAANQAECgYICAABNQAFFAUIDAAYAIQUAA==.Linali:BAAANQADCggICQAAAA==.Lirianna:BAAANQADCgMIAwAAAA==.Littany:BAABNQAECoEYAAMEAAkKbQmnUADjAQAEAAkKbQmnUADjAQAFAAcK8xC7jACiAQAAAA==.Livane:BAAANQAECgMIBQAAAA==.',
Lo='Loestus:BAAANQADCgQIBAAAAA==.Lowground:BAAANQADCgIIAgAAAA==.',
Lu='Lucïna:BAAANQAECgUIDwAAAA==.Ludk:BAAANQAECgUIEwAAAA==.Luk:BAABNQAECoEhAAMPAAgKWBIUIQAIAgAPAAgKPxIUIQAIAgAXAAQK7QygGAC8AAABNQAECgYICgABAAAAAA==.Lumiela:BAAANQAECgQIBQAAAA==.Luminah:BAAANQAECgIJAgAAAA==.Lunacy:BAAANQADCgYICgAAAA==.Luni:BAAANQAECgEIAQAAAA==.Lunì:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
['Ló']='Lóner:BAAANQAECgYIEAABNQAECggIGwADAMoIAA==.',
['Lü']='Lüni:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Ma='Macbayne:BAAANQADCgEIAQAAAA==.Maebe:BAAANQAECgQIBQAAAA==.Mageblaster:BAAANQADCgYICgAAAA==.Maggnut:BAABNQAECoEeAAINAAgKexAvcAD1AQANAAgKexAvcAD1AQAAAA==.Magicg:BAABNQAECoEaAAMaAAkKDhxCDgDbAgAaAAkKDhxCDgDbAgAHAAEKpgrDxAA8AAAAAA==.Magordito:BAABNQAECoEbAAIDAAgKyggCvwC2AQADAAgKyggCvwC2AQAAAA==.Mairek:BAABNQAECoEpAAIDAAkKqxzFQQDgAgADAAkKqxzFQQDgAgAAAA==.Maleigoron:BAABNQAECoEYAAILAAkKdAlUZwDRAQALAAkKdAlUZwDRAQAAAA==.Malkuri:BAABNQAECoEXAAMbAAgK6hLnLQCEAQAbAAcKkgznLQCEAQAKAAUKfhU4kACDAQAAAA==.Malorysera:BAABNQAECoEYAAQcAAkK1Rj0CwB1AgAcAAkKphf0CwB1AgAdAAYKWRdcHgCmAQAeAAMKXxhKDwDrAAAAAA==.Matsuma:BAAANQAECgEIAQAAAA==.',
Mc='Mcbasketball:BAAANQAECgIIAgAAAA==.',
Me='Mechaljaxon:BAAANQAECgUJCQAAAA==.Menirva:BAAANQAECgcIEQABNQAECggIFwAbAOoSAA==.Merv:BAAANQAECgUIBgAAAA==.Metapal:BAAANQAECggIEgABNQAFFAQICAAWAIwDAA==.Metasham:BAACNQAFFIEIAAIWAAQKjAPqDgADAQAWAAQKjAPqDgADAQA1AAQKgSMAAhYACQrfFkguAIMCABYACQrfFkguAIMCAAAA.',
Mi='Miiaa:BAAANQAECgYJDAAAAA==.Mijoy:BAAANQAECgQIBAAAAA==.Milane:BAAANQADCgYIGgAAAA==.',
Mo='Moirasha:BAAANQAECgQICgAAAA==.Monran:BAAANQAECgQIBQAAAA==.Moonwood:BAAANQADCgYIBgAAAA==.Moosand:BAAANQAECgQJBgAAAA==.Morphingtime:BAAANQAECgQICgAAAA==.Mortivus:BAAANQAECgIIAgAAAA==.',
Mu='Muggs:BAAANQADCggJCAAAAA==.Mulvane:BAAANQAECgIIAgAAAA==.Mustachio:BAAANQAECgQICgAAAA==.',
Mw='Mwc:BAACNQAFFIEMAAMfAAYKzhY5BAC9AQAfAAUK3hM5BAC9AQAQAAIK6RepCwCmAAA1AAQKgRYAAx8ACQoFJZcDAFgDAB8ACQoFJZcDAFgDABAABAp3Fo9HABUBAAAA.',
Mz='Mziao:BAAANQADCggIFQAAAA==.',
Na='Nashia:BAAANQADCgMIAwAAAA==.Nazureshal:BAAANQADCggICAABNQAECgUIDQABAAAAAA==.',
Ne='Neall:BAAANQAECgQIBwAAAA==.Ner:BAAANQADCgEIAQAAAA==.Nethryx:BAAANQADCgMIAwAAAA==.Nevets:BAAANQAECgUICAAAAA==.',
Ni='Nightbird:BAAANQADCggIDwAAAA==.Nightheals:BAAANQADCgYIBgABNQAECgUIEAABAAAAAA==.',
No='Nonna:BAAANQAECgUIEwAAAA==.Noslrac:BAAANQAECgIIAgAAAA==.Notbysight:BAAANQADCgYIBgAAAA==.Notorious:BAAANQAECggIIgAAAQ==.',
Ny='Nyxjr:BAAANQADCgIJAgAAAA==.',
Ob='Oblast:BAABNQAECoErAAIDAAkKWSRACACvAwADAAkKWSRACACvAwAAAA==.',
Od='Odb:BAAANQADCgQIBAAAAA==.Odirtyblasta:BAAANQADCgYIBgAAAA==.',
Ol='Olmanjankins:BAAANQAECgQJCAAAAA==.',
On='Onlydks:BAAANQAECggIDAABNQAECggIFQAOAIQcAA==.Onlyslams:BAABNQAECoEVAAMOAAgKhByuCQDqAQAOAAUKZSGuCQDqAQANAAcKyheJfgDLAQAAAA==.',
Oo='Ooze:BAAANQADCgMIAwAAAA==.',
Or='Orter:BAAANQAECgMJCQAAAA==.',
Ot='Ottan:BAAANQADCgYICwAAAA==.',
Ov='Overkill:BAAANQAECgMIAwAAAA==.Ovo:BAAANQADCgMIAwAAAA==.',
Pa='Pandorasfox:BAAANQADCgcICAAAAA==.Papsfear:BAAANQAECgYIEgAAAA==.Parceh:BAAANQAECgUIEwAAAA==.',
Ph='Phydaux:BAAANQADCggIGwAAAA==.',
Pi='Pinkponyclub:BAAANQADCggICAAAAA==.Pizzaman:BAAANQAECgQIBwAAAA==.',
Pr='Pringle:BAAANQADCgYIEgABNQAECgQIBQABAAAAAA==.Prosciutto:BAAANQAECgQICwAAAA==.Proxima:BAAANQAECgEIAQAAAA==.',
Pt='Ptoughneigh:BAAANQAECgQIBAAAAA==.',
Pu='Puckish:BAACNQAFFIEGAAIHAAQKPwNXEAAjAQAHAAQKPwNXEAAjAQA1AAQKgSEAAwcACQp3DdxQANkBAAcACQp3DdxQANkBABEAAQq8AT0nACQAAAAA.Punn:BAAANQAECgcIDAABNQAECgkJIAALAEMhAA==.Punnisher:BAABNQAECoEgAAMLAAkKQyFFCwBNAwALAAkKQyFFCwBNAwAgAAEKvhv8YQBHAAAAAA==.Pureflow:BAAANQAECgMJBgAAAA==.',
['Pä']='Päiñ:BAAANQADCgUIBQAAAA==.',
Qu='Quackers:BAAANQAECgUICAAAAA==.Quicks:BAABNQAECoEdAAIFAAgK2hrOTgBZAgAFAAgK2hrOTgBZAgAAAA==.',
Ra='Raelianna:BAAANQAECgQIBQABNQAECggIJwADAGskAA==.Raewyna:BAAANQAECgUICgAAAA==.Rahruhai:BAAANQADCgYIBQABNQAECgYICgABAAAAAA==.Raine:BAAANQAECggIDgAAAA==.Rainingblood:BAAANQAECgUICwAAAA==.Rainjar:BAAANQAECgUIBwAAAA==.Rancîd:BAAANQAECgYIEQAAAA==.Ranron:BAAANQAECgYIBgABNQAECgYIEQABAAAAAA==.Raphael:BAAANQAECgUIDgAAAA==.Rasik:BAAANQAECgUIEwAAAA==.Rastafareye:BAAANQADCgYIBwAAAA==.Ravenblood:BAAANQADCggIDQAAAA==.Rayel:BAAANQAECgIIBQAAAA==.Raylyn:BAAANQADCgYICwAAAA==.',
Rh='Rhadamancus:BAAANQAECgIIAwAAAA==.Rhani:BAAANQAECgQIBQAAAA==.Rheanon:BAAANQADCgYIFgAAAA==.Rhome:BAABNQAECoEjAAIHAAgKNSNVDgAqAwAHAAgKNSNVDgAqAwAAAA==.Rhox:BAAANQADCggJEQAAAA==.',
Ri='Rialu:BAABNQAECoEeAAIHAAgK1RG8TQDmAQAHAAgK1RG8TQDmAQAAAA==.Ribald:BAAANQAECgUICQAAAA==.Rickgrimes:BAABNQAECoEgAAMYAAgK0yHpEQDDAgAYAAgKGh7pEQDDAgAZAAcKwB5dNQD0AQAAAA==.',
Ro='Roid:BAABNQAECoEgAAMEAAkKLw4LRAAUAgAEAAkKLw4LRAAUAgAFAAIKawJ7OQFEAAAAAA==.Rotcorpse:BAAANQAECggIDAAAAA==.',
Ru='Ruddam:BAAANQAECgQIBAAAAA==.',
['Rä']='Räveñz:BAAANQAECgYIEgAAAA==.',
Sa='Saintabes:BAABNQAECoEXAAIHAAkKFB8OKwB+AgAHAAkKFB8OKwB+AgAAAA==.Sakurah:BAAANQAECgQICgAAAA==.Samelan:BAAANQABCggIFAAAAA==.Sandara:BAAANQADCgMIAwAAAA==.Sanicor:BAAANQADCggICAAAAA==.Sanrinn:BAAANQAECgYIBwAAAA==.Sappy:BAAANQAECgEIAQAAAA==.Sarahboom:BAACNQAFFIEIAAIDAAQKNAOFIAADAQADAAQKNAOFIAADAQA1AAQKgR0AAgMACQrUEER+AEgCAAMACQrUEER+AEgCAAAA.Sarahjupiter:BAAANQAECgQIBAABNQAFFAQICAADADQDAA==.Sargarach:BAAANQADCgEIAQAAAA==.',
Sc='Scapegoat:BAEANQAECgUIEgAAAQ==.',
Se='Seekýefirst:BAAANQADCgcIBwAAAA==.Seethe:BAAANQADCgYIBgAAAA==.Seilah:BAAANQAECgUICgAAAA==.Seliah:BAAANQAECgUIDQAAAA==.Senuya:BAAANQADCgQIBAABNQAECgYIDQABAAAAAA==.Seräph:BAAANQAECgEIAQAAAA==.',
Sh='Shadowglade:BAAANQAECgUIEwAAAA==.Shadowmourne:BAAANQABCgIIAgAAAA==.Shalltear:BAAANQADCggIIwAAAA==.Shamizzle:BAAANQAECgYIDwAAAA==.Shammydavis:BAAANQAECgUIDgAAAA==.Shaølinstørm:BAAANQADCgMIAwAAAA==.Shiftybud:BAAANQADCgQICwAAAA==.Shinobi:BAAANQAECgEIAQAAAA==.Shocknorris:BAAANQADCgUIBQAAAA==.Shrapnel:BAAANQAECgUIDgAAAA==.Shàmwôw:BAAANQADCgYIBAAAAA==.Shàytan:BAAANQAECgYIEgAAAA==.',
Si='Sinistral:BAAANQAECgIIAgAAAA==.',
Sl='Slise:BAAANQADCgIIAwAAAA==.',
Sm='Smithers:BAAANQAECgQICQAAAA==.',
Sn='Snappycakes:BAAANQAECgEIAQAAAA==.Sneakybunny:BAAANQAECgUIEwAAAA==.',
So='Solómon:BAAANQAECgQIBQAAAA==.Sorabjr:BAAANQADCggIGwAAAA==.Sorin:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.Soulbreaker:BAAANQAECgUIEwAAAA==.Southy:BAAANQAECgYIEgAAAA==.',
Sp='Sparxs:BAAANQADCgMIAwAAAA==.Spookz:BAAANQAECgEIAQAAAA==.',
St='Starblunder:BAAANQADCgUICgAAAA==.Storglen:BAAANQADCgUIBQAAAA==.Stormdeth:BAAANQADCgMIAwAAAA==.Stormmystic:BAAANQAECgIIAgAAAA==.Stormwild:BAAANQADCgUJBQABNQAECgIIAgABAAAAAA==.Stylemonk:BAACNQAFFIETAAITAAYK5yMPAQCJAgATAAYK5yMPAQCJAgA1AAQKgSEAAhMACQoIIzkDAJADABMACQoIIzkDAJADAAAA.',
Su='Sulfalloway:BAAANQAECgMIBAAAAA==.Sumawfulot:BAAANQAECgYIEQAAAA==.Sunsparrow:BAAANQAECgQIAgAAAA==.',
Sw='Swankdave:BAAANQADCgcIBwAAAA==.Swiftysarah:BAAANQADCggICAABNQAFFAQICAADADQDAA==.',
Sy='Syraelia:BAAANQADCggICAAAAA==.Syvarris:BAABNQAECoEeAAQhAAgKxxySAwCKAgAhAAcKaB6SAwCKAgAbAAUKXwlhPQD/AAAKAAEKZRGyCQFNAAAAAA==.',
Ta='Taeveren:BAAANQADCgIIAgAAAA==.Tamesßond:BAAANQAECgQIBAAAAA==.Tandaiff:BAAANQADCgYIBgAAAA==.Tanguo:BAAANQADCgcICQAAAA==.Tanksnotanks:BAAANQADCgYJFAAAAA==.Tanleron:BAAANQADCgMIAwAAAA==.Tarayn:BAAANQAECgUIEwAAAA==.',
Te='Teagan:BAAANQADCgYIEwAAAA==.Tenac:BAAANQADCggIDgAAAA==.Teoritta:BAEANQAECgUIEwAAAA==.Terllin:BAAANQADCgQIBAAAAA==.',
Th='Thalimus:BAAANQADCgYICgAAAA==.Thelle:BAAANQAECgYICwABNQAFFAcIEwAVAF8fAA==.Thewhitelion:BAAANQAECgIIAgAAAA==.',
Ti='Tigg:BAACNQAFFIEJAAIYAAUK8hCUAwCEAQAYAAUK8hCUAwCEAQA1AAQKgSIAAxgACQoBIa8QAM8CABgACQqcIK8QAM8CABkAAQpII9KmAEIAAAAA.Tikifiki:BAAANQAECgYIEAAAAA==.',
To='Tokin:BAAANQADCgYICgAAAA==.Toochill:BAAANQADCgEIAQAAAA==.Toodoo:BAAANQADCgIIAgABNQAECgYIEQABAAAAAA==.Toshidot:BAACNQAFFIEKAAILAAUKuBBYCQBwAQALAAUKuBBYCQBwAQA1AAQKgR8AAgsACQr5IGkVAAgDAAsACQr5IGkVAAgDAAAA.Totemtila:BAAANQAECgEIAgABNQAECggIHQALAMMjAA==.Totendead:BAAANQABCgIIAgAAAA==.',
Tr='Translucent:BAABNQAECoEaAAIiAAcKThAgZgCDAQAiAAcKThAgZgCDAQAAAA==.Trazatra:BAAANQAECgcIEAAAAA==.Truckah:BAAANQAECgYIDQAAAA==.Tràvdog:BAAANQAECgYICwAAAA==.',
Tu='Tunalongarms:BAAANQAECgQICAAAAA==.Tuonadari:BAAANQADCgUJCAAAAA==.Tuonai:BAAANQAECgUIDgAAAA==.Tusknus:BAAANQAECgIIAgAAAA==.',
Ty='Tylordis:BAAANQADCgYICgAAAA==.',
['Tý']='Týr:BAAANQADCgcIBwAAAA==.',
Us='Usodead:BAAANQADCgQIBAAAAA==.Usosquishy:BAAANQAECgcIEgAAAA==.',
Va='Vader:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Valkuridk:BAACNQAFFIEOAAMYAAUKdyJ9AQD3AQAYAAUKdyJ9AQD3AQAZAAEKaRUHFABOAAA1AAQKgSUAAxgACQqaJooBAMcDABgACQqKJooBAMcDABkACAoqJoYUAOACAAAA.Valorlight:BAAANQADCggICAAAAA==.Vandy:BAABNQAECoEeAAMHAAkKFxVVNABUAgAHAAkKNRNVNABUAgARAAQKqRbgDgAKAQAAAA==.',
Ve='Vedo:BAABNQAECoEXAAIbAAkKFRyTEAC9AgAbAAkKFRyTEAC9AgAAAA==.Vedora:BAAANQAECgYIDAAAAA==.Velf:BAAANQADCgEIAQAAAA==.Veradis:BAAANQADCgYIEgAAAA==.Vestiege:BAAANQABCgYIBwAAAA==.',
Vi='Vinland:BAAANQADCgYIEgAAAA==.Vinsmokesanj:BAAANQADCgQIBAAAAA==.Virulent:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.',
Vl='Vladak:BAAANQAECgYIDQAAAA==.',
Vo='Voc:BAAANQAECgcIEQAAAA==.Voz:BAAANQAECgIIAgABNQAECgUIBgABAAAAAA==.',
Vu='Vulkin:BAAANQAECgIIAwAAAA==.',
Vv='Vv:BAABNQAECoEdAAIKAAgKGiIjGQAEAwAKAAgKGiIjGQAEAwAAAA==.',
Vy='Vyridiondk:BAAANQAECgIIAgAAAA==.Vyx:BAAANQADCggIFwAAAA==.',
Wa='Waggi:BAAANQAECgQIBQAAAA==.Waymán:BAAANQADCggIGAAAAA==.',
We='Weebjones:BAAANQADCgQIBAAAAA==.Weelilcurse:BAAANQADCggICAAAAA==.Wegberto:BAAANQADCggICAAAAA==.',
Wu='Wumply:BAACNQAFFIEJAAIaAAQK7AZ7CAAVAQAaAAQK7AZ7CAAVAQA1AAQKgR4AAhoACQq3EWcbACMCABoACQq3EWcbACMCAAAA.',
['Wà']='Wàyman:BAAANQADCgUICwAAAA==.',
['Wä']='Wäyman:BAAANQAECgUIEwAAAA==.',
Xa='Xaranthia:BAAANQAECgcIDQAAAA==.',
Xm='Xmcdizzle:BAAANQAECgQICgAAAA==.',
Xy='Xylarra:BAAANQAECgUIEwAAAA==.',
Ya='Yautja:BAABNQAECoEWAAIbAAYK8BZrKwCdAQAbAAYK8BZrKwCdAQAAAA==.Yazule:BAAANQAECgYIEQAAAA==.',
Yo='Yodawg:BAAANQAECgUIDgABNQAECgcIEQABAAAAAA==.Yoruba:BAAANQADCgMIAwABNQAECgUIDQABAAAAAA==.',
Yu='Yuenna:BAAANQADCggICAABNQAECgYICgABAAAAAA==.',
Za='Zairroth:BAAANQADCgYIBwAAAA==.Zamali:BAAANQAECgYIEgAAAA==.Zantris:BAAANQADCgUIBwABNQAECgQIBQABAAAAAA==.Zartella:BAAANQAECgUIBgABNQAECgYICwABAAAAAA==.Zaxon:BAAANQADCgcIDQAAAA==.',
Ze='Zendraza:BAAANQAECgUJCwAAAA==.Zephyrion:BAABNQAECoEkAAIMAAkK8hjCHQCOAgAMAAkK8hjCHQCOAgABNQAECgUICQABAAAAAA==.Zepplin:BAAANQAECgYIDAAAAA==.Zerenity:BAAANQADCggIFQAAAA==.Zetro:BAABNQAECoEcAAIjAAgKTAmvJQBVAQAjAAgKTAmvJQBVAQAAAA==.',
Zr='Zreydyn:BAAANQADCgYIDgAAAA==.',
Zu='Zuma:BAAANQAECgUIDQAAAA==.Zuraxxus:BAAANQABCgMIAwAAAA==.',
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
