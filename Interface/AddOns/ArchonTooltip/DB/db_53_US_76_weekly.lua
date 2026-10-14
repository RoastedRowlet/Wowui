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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Unknown-Unknown','Hunter-BeastMastery','Warrior-Fury','Paladin-Holy','Warrior-Arms','Paladin-Protection','Priest-Holy','Shaman-Restoration','Mage-Arcane','Shaman-Elemental','DemonHunter-Devourer','DeathKnight-Blood','Rogue-Subtlety','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Priest-Shadow','Mage-Frost','Rogue-Assassination','Warlock-Affliction','Evoker-Preservation','Druid-Feral','Monk-Mistweaver','Rogue-Outlaw','DeathKnight-Frost','DemonHunter-Vengeance','Priest-Discipline','Monk-Windwalker','Hunter-Survival','Hunter-Marksmanship','Evoker-Devastation',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Aberaht:BAABNQAECn8iAAIBAAcK6iAVVQCTAgABAAcK6iAVVQCTAgAAAA==.Abercrombie:BAAANQABCgYICAAAAA==.Absolution:BAAANQAECgUIEQAAAA==.',
Ac='Ackianae:BAAANQAECgYIEAAAAA==.',
Ad='Adenwey:BAAANQAECgMIAwABNQAECgkJLgACAHAkAA==.Adewey:BAAANQAECgUICgAAAA==.Adorabull:BAAANQADCgIIAgAAAA==.',
Ae='Aenastian:BAAANQADCgUIDwABNQAECgkJLgACAHAkAA==.',
Ak='Akhalla:BAAANQAECgQIBAABNQAECgUIBgADAAAAAA==.Akre:BAAANQADCggIEwAAAQ==.Akumä:BAAANQADCgcIEQAAAA==.',
Al='Aleannia:BAAANQADCggICAAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAABNQAECn8cAAIBAAgKnRgndABBAgABAAgKnRgndABBAgAAAA==.Algodón:BAAANQADCgEIAgABNQAECgkJMQAEAPoiAA==.Alibrexia:BAABNQAECn8aAAIFAAcK1QcpFgA1AQAFAAcK1QcpFgA1AQAAAA==.Allus:BAAANQABCgUICQAAAA==.Alphaomega:BAAANQAECgQIBQAAAA==.',
An='Anarcy:BAAANQAECgIIAgAAAA==.Anastaysha:BAAANQADCgIIAgABNQAECgEIAgADAAAAAA==.Anathema:BAAANQADCggICAAAAA==.Ankan:BAABNQAECn8bAAIGAAgKrh2ILQCuAgAGAAgKrh2ILQCuAgABNQAECgkJLgACAHAkAA==.',
Ar='Arcticplague:BAAANQADCgEIAQAAAA==.Ardatha:BAAANQADCgIIAgAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.Arlor:BAAANQADCgYIDAAAAA==.',
As='Ashkada:BAAANQADCgQIBAAAAA==.Astrocakes:BAAANQADCgYICgABNQAECggIIgAHAIUcAA==.',
At='Athenä:BAACNQAFFH8TAAIIAAYKvxaIAwC+AQAIAAYKvxaIAwC+AQA1AAQKfyMAAggACQpEHWMLAOECAAgACQpEHWMLAOECAAAA.Atsuma:BAAANQADCggICwAAAA==.Atthel:BAAANQAECgYIDQAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgYICgADAAAAAA==.Aylli:BAAANQADCgcIBwABNQAECggIGQAJADYZAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAAANQAECgMIBQAAAA==.',
Ba='Baela:BAAANQAECgMIAwABNQAFFAUIFgAKAMggAA==.Baelthemar:BAAANQADCgUIBQAAAA==.Bajafresh:BAAANQADCgMIAwAAAA==.Bambita:BAAANQADCgUIBAAAAA==.Battleshaman:BAAANQABCgMIAgAAAA==.',
Be='Benjinana:BAAANQAECgUIDwAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Blackened:BAAANQAECgcIDQAAAA==.Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Boricua:BAAANQAECgIIAgAAAA==.Bountty:BAAANQADCgYIBgAAAA==.',
Br='Brightbane:BAAANQAECgEIAQAAAA==.',
Bu='Buddie:BAAANQADCggICAAAAA==.Buffaloseven:BAAANQAECgQICQABNQAFFAYIDAALAKYSAA==.Bulleitrye:BAAANQADCgYIBgAAAA==.',
By='Byorn:BAAANQAECgcIDwABNQAFFAQICAAEAPwSAA==.',
Ca='Cairdamane:BAABNQAECn8aAAMMAAgKRxB5cQDIAQAMAAgKRxB5cQDIAQAKAAEK5gEJKQEiAAAAAA==.Calidrina:BAABNQAECn8gAAINAAgK5gzxKwDfAQANAAgK5gzxKwDfAQAAAA==.Caness:BAAANQADCgEIAQAAAA==.',
Ce='Celldrassil:BAAANQAECgYICwAAAA==.Cellerunn:BAAANQADCgYIBgAAAA==.Cereel:BAAANQAECgcIDQABNQAECggIIgAHAIUcAA==.',
Ch='Chardaney:BAAANQAECgEIAgAAAA==.Chickennuggi:BAAANQAECgIIAgABNQAECgkJIQAOAIgjAA==.',
Ci='Cii:BAABNQAECn8eAAMIAAcK9RMeLwBhAQAIAAYK9RMeLwBhAQABAAEKAADkuwEnAAAAAA==.Ciine:BAAANQADCgYICAABNQAECgcIHgAIAPUTAA==.Ciruzita:BAAANQADCgUIBQAAAA==.',
Cl='Clampz:BAEANQAECgUIBwABNQAFFAYIEgAPAGAeAA==.',
Co='Colabrn:BAAANQADCgUIBQAAAA==.Colandros:BAAANQADCgEIAQAAAA==.Colara:BAAANQAECgUIEQAAAA==.Colbear:BAAANQABCgUICQAAAA==.Coldspace:BAABNQAECn8yAAIBAAkK5CFCGQBdAwABAAkK5CFCGQBdAwAAAA==.Corlock:BAAANQABCgMIAwAAAA==.',
Cr='Crassberry:BAACNQAFFH8JAAIQAAQK1BvVCwBNAQAQAAQK1BvVCwBNAQA1AAQKfx4AAhAACQpvJPEjALACABAACQpvJPEjALACAAAA.Creepindeath:BAAANQAECgEIAgAAAA==.',
Cu='Cucaracha:BAAANQAECgUIBQAAAA==.',
Cy='Cyndal:BAAANQADCgcIHAABNQAECgYICgADAAAAAA==.Cyndle:BAAANQADCggIGwABNQAECgYICgADAAAAAA==.Cyntu:BAAANQADCggIIAABNQAECgYICgADAAAAAA==.',
Da='Dankbuds:BAAANQAECggIBQAAAA==.Dankothy:BAAANQAECgEIAQABNQAECggIBQADAAAAAA==.Dantes:BAAANQAECgEJAQAAAA==.Darkryu:BAAANQADCgYIEAAAAA==.Darkspace:BAAANQAECgUIBwABNQAECgkJMgABAOQhAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQAECgIIAwAAAA==.',
De='Deadbolt:BAAANQADCgYIBgAAAA==.Deathforever:BAAANQAECgQIBAAAAA==.Deaus:BAAANQADCggIFQAAAA==.Delrus:BAABNQAECn8dAAMRAAgK/B2oEgC2AgARAAgK/B2oEgC2AgASAAMK/xKljQCaAAAAAA==.Demon:BAABNQAECn8vAAICAAkKXSDHDABBAwACAAkKXSDHDABBAwABNQAFFAYIFwAPALwVAA==.Demowneege:BAAANQADCggICAABNQAFFAUIEQAHAGEaAA==.Denzvic:BAAANQAECgYICwAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Diddyjr:BAABNQAECn8dAAILAAkKkRwPegCKAgALAAkKkRwPegCKAgAAAA==.Disowneege:BAAANQAECgUICQABNQAFFAUIEQAHAGEaAA==.',
Do='Doodu:BAAANQAFFAEIAQAAAA==.',
Dr='Dragnas:BAABNQAECn8qAAQTAAkKoRC8EQBLAgATAAkKoRC8EQBLAgAKAAQKuxJZugDyAAAMAAEKHg6vKQE7AAAAAA==.Dragonisa:BAAANQAECgEIAQAAAA==.Drakass:BAAANQADCggICAAAAA==.Dramakiller:BAAANQAECgIIAgAAAA==.Drcornbread:BAAANQAECgUIDwAAAA==.Drcornellia:BAAANQADCgYIBwABNQAECgUIDwADAAAAAA==.Drdreggs:BAABNQAECn8aAAMUAAkKsA9XggDcAQAUAAgK9w5XggDcAQAVAAEKBhQ+cQA9AAAAAA==.Drop:BAAANQADCgQIBAABNQAECggIJQABAE0XAA==.Druduwolf:BAAANQAECgUICgAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgYICAADAAAAAA==.Dustyhunter:BAAANQADCgQIBAAAAA==.',
Ea='Eatbuttforpi:BAAANQADCgUIBwABNQAECggIIgAHAIUcAA==.',
El='Elastar:BAABNQAECn8iAAIWAAcK2BdYEgD9AQAWAAcK2BdYEgD9AQAAAA==.Ellimist:BAEANQAECgcIDAAAAA==.Elsan:BAAANQADCgQIBAAAAA==.Elycee:BAAANQAECggIDAAAAA==.',
Em='Emura:BAAANQAECgEIAQAAAA==.',
En='Enveliria:BAAANQAECgUIDgABNQAECgkJLgACAHAkAA==.',
Er='Eraser:BAABNQAECn8vAAMJAAgKMRQBYwDzAQAJAAgKMRQBYwDzAQAXAAYK/A+7OQBVAQAAAA==.Erazar:BAAANQAECgUIDQAAAA==.Erickk:BAABNQAECn8oAAILAAkKFhsITgDlAgALAAkKFhsITgDlAgAAAA==.Eristela:BAAANQADCgYICgAAAA==.',
Es='Escanorlion:BAAANQAECgUIBwAAAA==.Essense:BAABNQAECn8iAAIJAAcKZiVVIwDdAgAJAAcKZiVVIwDdAgAAAA==.',
Ev='Evokedcat:BAAANQAECgcIDgAAAA==.',
Ex='Exodari:BAABNQAECn8oAAITAAkKPQ/CEgA6AgATAAkKPQ/CEgA6AgAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgIIAgABNQAECggIIgAHAIUcAA==.Fatalgrip:BAAANQADCgUIBQAAAA==.',
Fe='Fel:BAABNQAECn82AAMCAAkKASSiBgCLAwACAAkK7iKiBgCLAwANAAcKaB6sFwCdAgAAAA==.Fellius:BAAANQADCgQIBAAAAA==.Fellkarras:BAAANQAECgUIBwABNQAECgkJIQAOAIgjAA==.Felprincess:BAAANQABCgYICgAAAA==.',
Fi='Fibitz:BAAANQAECgcICwABNQAECgcIDwADAAAAAA==.Findstewie:BAAANQABCgYICgABNQABCggIDgADAAAAAA==.Fiofio:BAABNQAECn8iAAILAAcKxhx+kgBaAgALAAcKxhx+kgBaAgAAAA==.Fizban:BAABNQAECn8WAAMYAAgKtQzGDwCoAQAYAAgKtQzGDwCoAQALAAQK+AFrlwGQAAAAAA==.',
Fl='Flik:BAAANQAECgUICAABNQAECgkJNgAJAL0dAA==.',
Fo='Foringojr:BAAANQAECgIIAgAAAA==.',
Fr='Frigidheart:BAAANQAECgUIDAABNQAECgcIDwADAAAAAA==.Frostetute:BAAANQAECgYIBgAAAA==.',
Fu='Furrybawlz:BAAANQADCggICAAAAA==.',
['Fà']='Fàllén:BAAANQAECgEIAwABNQAFFAQICAAEAPwSAA==.',
Ga='Gadogear:BAAANQAECgQICwAAAA==.Galabren:BAAANQAECgYJDQAAAA==.Garlik:BAAANQADCgUIDQAAAA==.',
Gf='Gfr:BAAANQAECgUICgAAAA==.',
Gi='Giddoo:BAAANQAECgMIAwAAAA==.Gilnean:BAAANQABCgEIAQAAAA==.',
Gn='Gnomeanator:BAAANQABCgIIAgAAAA==.Gnowanceyi:BAAANQAECgEIAQABNQAECgkJKAALABYbAA==.',
Go='Goatcheeze:BAAANQAECgcIDQAAAA==.Gohlemsaurus:BAAANQADCggIIAAAAA==.',
Gu='Gulen:BAAANQADCggJGwAAAA==.Gullee:BAAANQABCggIEwAAAA==.',
Gw='Gwennevier:BAAANQABCgcIDQAAAA==.',
['Gí']='Gíga:BAAANQAECgMIAwAAAA==.',
Ha='Halsten:BAAANQAECgUIDgAAAA==.Hamish:BAAANQAECgEIAQAAAA==.',
He='Hellenkeller:BAEANQAFFAEIAQABNQAFFAYIEgAPAGAeAA==.Heloisa:BAAANQADCgYIBgAAAA==.',
Hi='Hitt:BAAANQAECgYICgAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.Hoofingit:BAAANQADCgQIBAAAAA==.',
Hr='Hroc:BAAANQAECgcIEgAAAA==.',
Ic='Icedlatte:BAAANQADCgUIDQAAAA==.Icywolfy:BAAANQAECgIIAgAAAA==.',
Ig='Igreetyou:BAAANQAECgMIAwAAAA==.',
Il='Illune:BAAANQAECgUIEQABNQAECgkJIgAIAJghAA==.',
Im='Imleapingit:BAABNQAECn8UAAIHAAcKqRTInADQAQAHAAcKqRTInADQAQAAAA==.Imrelentless:BAAANQABCgYICwAAAA==.',
In='Inaurian:BAAANQADCggICAAAAA==.Intoodeep:BAABNQAECn8oAAIZAAkKkRMbJABjAgAZAAkKkRMbJABjAgAAAA==.',
Ir='Ir:BAABNQAECn84AAILAAkK+BxFOwAQAwALAAkK+BxFOwAQAwAAAA==.Irrlvntgobbo:BAAANQAECgYICwAAAA==.',
Is='Isasham:BAAANQAECgIIAgAAAA==.Isawarriorr:BAABNQAECn8eAAMHAAkKshkVXQByAgAHAAkKmRcVXQByAgAWAAIK0Rs3NACOAAAAAA==.Ishdo:BAABNQAECn8aAAIOAAgKPAxxYABtAQAOAAgKPAxxYABtAQAAAA==.Ishlok:BAAANQADCgUIBQABNQAECggIGgAOADwMAA==.Ishmael:BAAANQAECgMIAwABNQAFFAQICAAEAPwSAA==.Ishwar:BAAANQADCggIGAABNQAECggIGgAOADwMAA==.',
Iv='Ivanhöe:BAAANQAECgEIAQAAAA==.',
Ja='Jakytreehorn:BAAANQAECgcIEQAAAA==.Jaydm:BAAANQAECgYICQABNQAFFAYIDAALAKYSAA==.',
Je='Jenevelle:BAAANQAECgMJAwAAAA==.Jerisil:BAAANQADCgUICAAAAA==.Jessiel:BAAANQAECgQIBAAAAA==.Jet:BAABNQAECn8lAAIBAAgKTRdacABLAgABAAgKTRdacABLAgAAAA==.',
Ju='Julthaenia:BAABNQAECn8gAAIaAAgKaxnMAwCwAgAaAAgKaxnMAwCwAgABNQAECgkJLgACAHAkAA==.Junjia:BAAANQADCgUIBQAAAA==.',
Ka='Kagebushin:BAAANQABCgIIAgAAAA==.Kagome:BAAANQADCgQIBgABNQAECgEIAgADAAAAAA==.Kalofelement:BAAANQADCgEIAQAAAA==.Kalysy:BAAANQADCggICAABNQAECgkJLgACAHAkAA==.Karash:BAAANQAECgYICAAAAA==.Karmaisab:BAAANQAECgMIAQAAAA==.Karnrae:BAABNQAECn8WAAIBAAgKUBWDlwDwAQABAAgKUBWDlwDwAQAAAA==.Karynos:BAABNQAECn8nAAIUAAgKyRKZfgDlAQAUAAgKyRKZfgDlAQAAAA==.Katwolf:BAAANQAECgYIEQAAAA==.Katyah:BAABNQAECn8XAAIKAAgKCAc8lQBOAQAKAAgKCAc8lQBOAQAAAA==.Kavourkaa:BAAANQABCggIGgAAAA==.',
Ke='Keynivas:BAAANQAECgIJAgAAAA==.',
Ki='Killiua:BAAANQAECgYICgAAAA==.',
Ko='Konspiracy:BAABNQAECn8WAAMVAAgK4xAsDwAIAgAVAAgK4xAsDwAIAgAUAAEKAAA1SAErAAAAAA==.',
Kr='Kraguva:BAAANQAECgQIBAAAAA==.Krataar:BAAANQAECgEIAQABNQAECgYIDQADAAAAAA==.Kroot:BAAANQAECgcIDwAAAA==.Krous:BAACNQAFFH8NAAIHAAYKlBaCCgADAgAHAAYKlBaCCgADAgA1AAQKfyIAAgcACQr9Hu1NAJ0CAAcACQr9Hu1NAJ0CAAAA.Kryph:BAAANQAECgUIDgAAAA==.',
['Kä']='Kämpfer:BAAANQAECgYICwABNQAECggIKQAbAJYUAA==.',
La='Lafiel:BAABNQAECn8bAAIJAAcKZRCffACfAQAJAAcKZBCffACfAQAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Laurandre:BAABNQAECn8cAAMRAAcKVgcoQAAfAQARAAcKVgcoQAAfAQASAAEKAAAHxwAZAAAAAA==.Lazeras:BAAANQAECgQIBAABNQAECggIGgAcAPsXAA==.',
Le='Letsgetwet:BAAANQADCgUIBQAAAA==.',
Li='Liefic:BAAANQAECgcIEwAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilienne:BAAANQABCgYIBwAAAA==.Lilstooge:BAAANQABCgYIBwABNQABCggIDgADAAAAAA==.',
Ll='Llylith:BAAANQABCgMIBAAAAA==.',
Lo='Locke:BAAANQAECgUIBwABNQAECggIJQABAE0XAA==.',
Lu='Luckykilla:BAABNQAECn8qAAIZAAgKjhYEKQBFAgAZAAgKjhYEKQBFAgAAAA==.Lucÿ:BAABNQAECn8pAAMKAAkKox50IwDXAgAKAAkKox50IwDXAgAMAAYKexJrlgBoAQAAAA==.Lune:BAAANQADCgUICwAAAA==.Lurith:BAABNQAECn8rAAMQAAcK1BH0dgA5AQAQAAUKhBf0dgA5AQAOAAYKFQu4eAARAQAAAA==.Luxtyrannica:BAAANQAECgUICgAAAA==.',
Ly='Lydrain:BAAANQAECgQIBAAAAA==.Lylia:BAAANQADCggIEwAAAA==.',
Ma='Marahh:BAAANQABCgIIAgAAAA==.Matt:BAAANQAECgQIBAABNQAFFAYIFwAPALwVAA==.Mattbolt:BAAANQAECgYIEQAAAA==.Maximoose:BAABNQAFFH8IAAIEAAQK/BL4EABIAQAEAAQK/BL4EABIAQAAAA==.Mayu:BAAANQADCggIGgAAAA==.Mayumey:BAAANQADCgUIBQAAAA==.Mazigos:BAAANQAECgUJBQAAAA==.',
Me='Medjrab:BAABNQAECn8vAAIQAAkK8CFiCQByAwAQAAkK8CFiCQByAwAAAA==.Mefi:BAAANQADCgcIDAAAAA==.Melyria:BAAANQAECgcIEQAAAA==.Meristem:BAABNQAECn8YAAISAAcKNAqRWABuAQASAAcKNAqRWABuAQAAAA==.Merko:BAAANQADCggICQABNQAECgcIDwADAAAAAA==.',
Mi='Mignius:BAAANQADCgYIBgAAAA==.Mistified:BAAANQABCgIIBAAAAA==.',
Mo='Moedorai:BAAANQAECggIEAAAAA==.Mogma:BAAANQAECgUICQAAAA==.Mogsarren:BAAANQABCgIIAgABNQAECgkJNgAOAAAmAA==.Momentomori:BAAANQADCgUICwAAAA==.Monora:BAAANQADCggICQAAAA==.Moonbounds:BAACNQAFFH8SAAIKAAYKBhrIBQAIAgAKAAYKBhrIBQAIAgA1AAQKfzwAAgoACQr6I3QFAJoDAAoACQr6I3QFAJoDAAAA.Moondoggey:BAAANQADCgUIBQAAAA==.Moonshift:BAAANQABCggIEwAAAA==.Morgana:BAAANQADCgUICAAAAA==.Mousechief:BAAANQAECgUIDAAAAA==.Moxxzi:BAABNQAECn8cAAIQAAYKbg/fcwBEAQAQAAYKbg/fcwBEAQAAAA==.',
Mu='Muhfookinbak:BAABNQAECn8YAAMMAAgKdCCTIQABAwAMAAgKdCCTIQABAwAKAAEKUxDVFAE7AAAAAA==.Muvahmedicin:BAAANQADCgcIBwAAAA==.',
Na='Naksu:BAAANQADCgYJFgABNQAECgcIHgAJABQiAA==.Naksù:BAAANQADCgUIBQABNQAECgcIHgAJABQiAA==.Naksû:BAAANQADCgYIBgABNQAECgcIHgAJABQiAA==.Naksü:BAABNQAECn8eAAIJAAcKFCKlLQCvAgAJAAcKFCKlLQCvAgAAAA==.',
Ne='Neifeb:BAABNQAECn8hAAIEAAgKphEAgQAHAgAEAAgKphEAgQAHAgAAAA==.Nerfherder:BAAANQABCgcIDgABNQAECggIJgAFAK0VAA==.',
Ni='Niallivdam:BAAANQAECgEIAgAAAA==.Nights:BAAANQAECgIIAwABNQAFFAYIFwAPALwVAA==.Ninh:BAABNQAECn84AAIdAAkKrwwAHAC/AQAdAAkKrwwAHAC/AQAAAA==.Nintendopsp:BAAANQADCgYICgAAAA==.Ninthgate:BAAANQAECgUIEwAAAA==.',
No='Noble:BAABNQAECn8cAAINAAgKARKDKwDiAQANAAgKARKDKwDiAQAAAA==.Nogood:BAABNQAECn8VAAIHAAkK4hcnaABUAgAHAAkK4hcnaABUAgAAAA==.Northwest:BAAANQABCgYJBQAAAA==.Notsodemon:BAAANQAECgQICAABNQAECgYIEgADAAAAAA==.Notsomage:BAAANQAECgYIEgAAAA==.',
Ny='Nyorai:BAAANQABCgQIAwAAAA==.Nyxwing:BAAANQAECgQIBQAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAABNQAECn8fAAMRAAcK4BvfHgAzAgARAAcK4BvfHgAzAgASAAEKAACHxQAaAAAAAA==.',
Od='Oddone:BAAANQADCgEIAQAAAA==.Oddpocalypse:BAAANQADCgQIBAAAAA==.Odinheâthen:BAAANQADCgYJDAAAAA==.',
Ol='Olydwarf:BAAANQAECgEIAQAAAA==.',
On='Onebadmutha:BAAANQAECgYIDAAAAA==.Ontop:BAABNQAECn84AAIEAAkK9B1ZJwD5AgAEAAkK9B1ZJwD5AgAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAABNQAECn8cAAMYAAcKtBcEDQDgAQAYAAcKtBcEDQDgAQALAAIK1wV1rwFaAAAAAA==.',
Ow='Owneege:BAACNQAFFH8RAAMHAAUKYRqtEQCfAQAHAAUKYRqtEQCfAQAFAAMKjRIqAgDbAAA1AAQKfyUAAwUACQqGIoYKAB4CAAcACQrUIfZEALgCAAUABgpiI4YKAB4CAAAA.',
Pa='Paapaa:BAAANQADCgcIBQAAAA==.Pallideaus:BAABNQAECn8ZAAIGAAcKayHzLgCoAgAGAAcKayHzLgCoAgAAAA==.Pallinar:BAAANQAECgYICwAAAA==.Pandamak:BAAANQADCggICAAAAA==.Pasquale:BAAANQAECgQIBgAAAA==.Pauzhaan:BAAANQAECgQIBAABNQAECggIJgAFAK0VAA==.',
Pe='Pebbles:BAABNQAECn8rAAIBAAkKPxNTegAyAgABAAkKPxNTegAyAgAAAA==.Pedorus:BAAANQABCgYIBwABNQAECgkJKQAKAKMeAA==.Penjerman:BAAANQAECggICAABNQAECggIIgAHAIUcAA==.',
Pi='Picklericky:BAAANQADCggIDQAAAA==.Pilgrimm:BAECNQAFFH8SAAIPAAYKYB7cAQA5AgAPAAYKYB7cAQA5AgA1AAQKfyIABA8ACQraJZYDAGYDAA8ACQraJZYDAGYDAB4AAQq5G04ZAEwAABkAAQpBC+2cADoAAAAA.Pinxyl:BAAANQABCgcIBwAAAA==.Pistola:BAAANQAECgQIBAAAAA==.Pixyl:BAAANQADCggIFgAAAA==.',
Pl='Plaguerott:BAABNQAECn8YAAIfAAcKsgViYAAbAQAfAAcKsgViYAAbAQAAAA==.Plaguewind:BAAANQADCgQIBQAAAA==.',
Po='Polydh:BAABNQAECn8pAAIgAAkKDiQJAQC1AwAgAAkKDiQJAQC1AwAAAA==.Poobah:BAABNQAECn8bAAMMAAcKywVuwAANAQAMAAYKwQZuwAANAQAKAAEK5gPzIQEoAAAAAA==.Popsicles:BAABNQAECn8bAAMhAAgKfhYaBgAyAgAhAAgKfhYaBgAyAgAXAAEKAAAXiQAfAAAAAA==.Potrat:BAAANQAECgMJAwAAAA==.Pouffant:BAAANQAECgUICgAAAA==.',
Pr='Praddagy:BAAANQADCgUIBQAAAA==.Pronoz:BAAANQAECggIDwAAAA==.',
Pu='Purpyl:BAAANQAECgUIBgAAAA==.',
Pw='Pwnageddon:BAAANQADCgcIFwAAAA==.Pwnjitsu:BAABNQAECn8jAAIiAAkKDRnCGQBwAgAiAAkKDRnCGQBwAgAAAA==.',
Py='Pyrothermia:BAACNQAFFH8MAAILAAYKphLkDQADAgALAAYKphLkDQADAgA1AAQKfyEAAwsACQoKGnxtAKMCAAsACQoKGnxtAKMCABgAAwr+BPUxAHEAAAAA.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Rawhoof:BAABNQAECn84AAIHAAkKEyLcHQA/AwAHAAkKEyLcHQA/AwAAAA==.Razak:BAABNQAECn8vAAITAAkKyyHtBQAnAwATAAkKyyHtBQAnAwAAAA==.',
Rd='Rdnckromeo:BAAANQAECgQIBAAAAA==.',
Re='Redlock:BAABNQAECn8ZAAIVAAcKBQYKKQAxAQAVAAcKBQYKKQAxAQAAAA==.Redrum:BAABNQAECn8hAAIOAAkKiCPxCgBcAwAOAAkKiCPxCgBcAwAAAA==.Renarin:BAABNQAECn82AAIJAAkKvR3eHwDuAgAJAAkKvR3eHwDuAgAAAA==.Renisa:BAABNQAECn8bAAMNAAcKsheNJgAOAgANAAcKsheNJgAOAgACAAEKMwavmgAlAAAAAA==.Renobagem:BAAANQADCgUIBgAAAA==.Retman:BAAANQADCggIDgAAAA==.Reu:BAAANQAECgUIBQAAAA==.Revlyk:BAABNQAECn8eAAITAAgKlRYRDwB3AgATAAgKlRYRDwB3AgABNQAECgkJLgACAHAkAA==.',
Rh='Rhoanna:BAAANQAECgMIAwAAAA==.Rhoupert:BAAANQAECgYIEgABNQAECggIFwAjACcaAA==.',
Ri='Rimastus:BAAANQADCgEIAQAAAA==.',
Ro='Roccot:BAABNQAECn8lAAIOAAgKFh22KAB4AgAOAAgKFh22KAB4AgAAAA==.Rotjaw:BAAANQADCggIDAAAAA==.Roughedge:BAAANQADCgIIAgAAAA==.',
Rv='Rvn:BAAANQAECgIIAgAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQABCgYIDAAAAA==.Sallanu:BAAANQAECgEIAQAAAA==.',
Sc='Scalycat:BAAANQAECgYIDQAAAA==.Schuey:BAAANQADCggICAAAAA==.Scum:BAAANQADCgcIDQABNQADCggICAADAAAAAA==.',
Se='Senaeda:BAAANQADCgQIBwAAAA==.Senate:BAABNQAECn8lAAMMAAcKZROvaQDgAQAMAAcKZROvaQDgAQAKAAEKqgH8LQEfAAAAAA==.Servenslay:BAAANQADCggICAAAAA==.',
Sh='Shaamazing:BAAANQABCgIIAgAAAA==.Shablaam:BAAANQADCggIEQAAAA==.Shadowbear:BAAANQAECgUIDAAAAA==.Sherrilyn:BAAANQADCgYICAAAAA==.Shifdiah:BAAANQAECgUICgAAAA==.Shocktherapi:BAAANQAECgYICAAAAA==.Shrimpback:BAAANQAECgEIAQAAAA==.',
Si='Singularity:BAAANQAECgQJBQAAAA==.',
Sk='Skelli:BAECNQAFFH8UAAIJAAYKYxNECgDfAQAJAAYKYxNECgDfAQA1AAQKfxkAAgkACQr7G7U6AHsCAAkACQr7G7U6AHsCAAE1AAQKBwgMAAMAAAAA.Skittlesdan:BAABNQAECn8bAAQUAAgKNRPmfADqAQAUAAgKNRPmfADqAQAaAAEKAAAIMgAvAAAVAAEKxQRmggAoAAAAAA==.',
Sl='Slaykween:BAAANQAECgUIDgAAAA==.',
Sm='Smallz:BAAANQAECgUIBQABNQAECggIFgAYALUMAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAABNQAECn8mAAQFAAgKrRXyDgC8AQAFAAYK6xjyDgC8AQAHAAcK0A2quACKAQAWAAIKMhp/OABnAAAAAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Steakhaus:BAAANQAECgIIAgAAAA==.Stonedragon:BAECNQAFFH8IAAIEAAIKoRd0HgC4AAAEAAIKoRd0HgC4AAA1AAQKf0MAAgQACQqjJJAFALUDAAQACQqjJJAFALUDAAAA.Stormfang:BAAANQADCgcIBwABNQAECgMIBQADAAAAAA==.Stormfist:BAAANQADCgQIBgAAAA==.Stormhaven:BAAANQADCgQJBAABNQAECgMIBQADAAAAAA==.Stormrender:BAAANQAECgUICgAAAA==.Stormriders:BAABNQAECn8dAAIMAAYKkRBRlQBrAQAMAAYKkRBRlQBrAQAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Streea:BAAANQADCggIGwABNQAECgYICgADAAAAAA==.Stubz:BAAANQABCgQIBgAAAA==.',
Su='Sugi:BAAANQABCgIIAgABNQAECgkJKgANAIMeAA==.Sukonamí:BAABNQAECn8VAAIHAAcKPQy1uACKAQAHAAcKPQy1uACKAQAAAA==.Suzhou:BAAANQAECgYIDwAAAA==.Suzoomies:BAAANQADCggIDwAAAA==.',
Sw='Swisscheese:BAABNQAECn8dAAMUAAgKyRqwWgBDAgAUAAgKyRqwWgBDAgAVAAEKLwqmegAyAAAAAA==.Swoopyboop:BAAANQADCgQIBAAAAA==.',
Sy='Sybaek:BAAANQAECgcICAAAAA==.Sycò:BAABNQAECn8lAAMEAAkKGyMQEgBXAwAEAAkKGyMQEgBXAwAkAAEKkQEonAAgAAAAAA==.Syraxa:BAAANQAECgMIBAABNQAECgkJLgARAOwbAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAQABNQAFFAQICwAEAJcTAA==.',
Ta='Taedish:BAAANQADCgQIBAAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.Tannith:BAAANQABCgYIDgABNQABCggIDgADAAAAAA==.Tayy:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Telan:BAAANQADCgUIBQAAAA==.Tempertotems:BAAANQADCggIDQAAAA==.Tenastin:BAAANQADCgQIBAAAAA==.Terragosa:BAAANQAECgYIEwAAAA==.Tetchybono:BAAANQAECgYIDAAAAA==.Tettra:BAAANQABCgEIAQABNQAECgYICgADAAAAAA==.',
Th='Thaeleon:BAAANQAECgMIAwABNQAFFAQICAAEAPwSAA==.Thahawtz:BAAANQADCgYJDAAAAA==.Thirinis:BAAANQAECgUICQAAAA==.Thope:BAAANQADCgYIFgAAAA==.Thundergirl:BAAANQADCgYIDAAAAA==.',
Ti='Ticklemychin:BAAANQADCgcIBwAAAA==.',
To='Toughasnails:BAAANQAECgEIAQAAAA==.',
Tr='Traesdyne:BAAANQADCgQIBQAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECggIGgAcAPsXAA==.Trainar:BAAANQAECgQIDQABNQAECgcIGgACADEaAA==.Triggs:BAAANQAECgQIBQAAAA==.Troggdor:BAAANQABCggIDgABNQAECggIJgAFAK0VAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAAANQAECgUICQAAAA==.Truckz:BAAANQAECgQIBAAAAA==.Trõnlight:BAAANQAECgEIAQAAAA==.',
Ts='Tsunah:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQAECgEIAQAAAA==.Turim:BAAANQAECgEIAQAAAA==.',
Ty='Tyrawick:BAAANQAECgUIBQAAAA==.Tyrlidd:BAABNQAECn8ZAAIEAAcKqwbyvACEAQAEAAcKqwbyvACEAQAAAA==.',
Un='Unavoidable:BAAANQADCgMIAwAAAA==.Unlikelytale:BAABNQAECn8qAAMKAAkKAhxWKQC8AgAKAAkKAhxWKQC8AgAMAAEKRxaKIgFEAAAAAA==.',
Ur='Urbanmeyer:BAAANQAECgIIAgAAAA==.Uricash:BAABNQAECn8vAAILAAkKLh4uRAD7AgALAAkKLh4uRAD7AgAAAA==.Urrax:BAAANQADCgEIAQABNQADCgIIAgADAAAAAA==.Urzual:BAABNQAECn8mAAMTAAgKFB1MDACqAgATAAgKFB1MDACqAgAKAAYKbhT3iABvAQAAAA==.',
Ut='Utiniócast:BAAANQAECgEIAQAAAA==.',
Va='Vandreynna:BAABNQAECn8uAAICAAkKcCQ+BgCQAwACAAkKcCQ+BgCQAwAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velsiana:BAAANQAECgMIAwAAAA==.Velveetah:BAAANQADCgYIBwABNQAECgUIDwADAAAAAA==.Verbren:BAAANQADCgUIBQABNQAECggIKQAbAJYUAA==.Verbrennen:BAABNQAECn8pAAIbAAgKlhT2GQAhAgAbAAgKlhT2GQAhAgAAAA==.Verita:BAAANQAECgQIBgAAAA==.Verlynne:BAAANQADCgcIBwAAAA==.',
Vi='Viviann:BAABNQAECn8iAAMbAAcKqQocKQBmAQAbAAcKqQocKQBmAQAlAAYKPAkFIwArAQAAAA==.',
Vo='Von:BAAANQADCgEIAQAAAA==.',
Wa='Walee:BAAANQADCgIIAgAAAA==.Walfred:BAAANQAECgQIBwABNQAECgcIKwAQANQRAA==.Warraxe:BAAANQADCgYIBgAAAA==.Waukeen:BAAANQABCgIIAgAAAA==.Wayloren:BAABNQAECn8lAAIBAAgKYAgRzwB3AQABAAgKYAgRzwB3AQAAAA==.Wayverly:BAAANQABCgUIBwABNQAECgEIAgADAAAAAA==.',
We='Wetboycaird:BAAANQADCgMIAwAAAA==.',
Wi='Wickathy:BAABNQAECn8iAAIgAAkKhiJsAQCTAwAgAAkKhiJsAQCTAwAAAA==.Wickcreu:BAAANQAECgIIAgAAAA==.',
Wo='Woodson:BAAANQADCggICAABNQAECgUIBgADAAAAAA==.Worstdps:BAABNQAECn8vAAICAAkKNRWsKQBPAgACAAkKNRWsKQBPAgAAAA==.',
Wu='Wuldorr:BAACNQAFFH8FAAIBAAQKkQY+FQAAAQABAAQKkQY+FQAAAQA1AAQKfxwAAgEACQq2DruZAOsBAAEACQq2DruZAOsBAAAA.',
Wy='Wynnifred:BAAANQAECgMICQAAAA==.',
Xa='Xaltheris:BAAANQAECgUIBgAAAA==.',
Xe='Xenothor:BAAANQAECgEIAQAAAA==.Xethreal:BAABNQAECn8ZAAIKAAcKnx3gQwBPAgAKAAcKnx3gQwBPAgAAAA==.',
Xy='Xype:BAAANQAECggICAAAAA==.',
Xz='Xzara:BAAANQAECgYICgAAAA==.',
Yu='Yura:BAAANQADCggICAAAAA==.',
Yv='Yvvee:BAAANQAECgMIAwAAAA==.',
Za='Zapbranigan:BAAANQADCggIDQAAAA==.',
Zi='Zifao:BAABNQAECn8kAAILAAkKzCBwJwBEAwALAAkKzCBwJwBEAwAAAA==.',
Zo='Zonora:BAAANQAECgcIEgAAAA==.',
['Äz']='Äzrael:BAABNQAECn8ZAAIJAAgKNhkWRwBOAgAJAAgKNhkWRwBOAgAAAA==.',
['Çr']='Çréwüsæðèr:BAAANQAECgYIEQAAAA==.',
['Ðì']='Ðìaßlo:BAACNQAFFH8LAAIEAAQKlxNmEQBDAQAEAAQKlxNmEQBDAQA1AAQKfykAAgQACQqNIBInAPoCAAQACQqNIBInAPoCAAAA.',
['Òd']='Òdinn:BAAANQADCgcIBwAAAA==.',
['Ød']='Ødin:BAAANQADCggIFAABNQAECgMIBQADAAAAAA==.',
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
