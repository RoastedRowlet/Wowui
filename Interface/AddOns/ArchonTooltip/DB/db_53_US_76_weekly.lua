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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Unknown-Unknown','Hunter-BeastMastery','Warrior-Fury','Warrior-Arms','Paladin-Protection','Shaman-Restoration','Mage-Arcane','Shaman-Elemental','DemonHunter-Devourer','Rogue-Subtlety','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Warrior-Protection','Priest-Shadow','Priest-Holy','DeathKnight-Blood','Rogue-Assassination','Warlock-Affliction','Warlock-Demonology','Evoker-Preservation','Monk-Mistweaver','Rogue-Outlaw','DeathKnight-Frost','DemonHunter-Vengeance','Priest-Discipline','Monk-Windwalker','Mage-Frost','Warlock-Destruction','Hunter-Marksmanship','Evoker-Devastation',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Aberaht:BAABNQAECoEbAAIBAAcK9CA3TACIAgABAAcK9CA3TACIAgAAAA==.Absolution:BAAANQAECgQIDAAAAA==.',
Ac='Ackianae:BAAANQAECgYIEAAAAA==.',
Ad='Adenwey:BAAANQADCgQIBAABNQAECgkJKAACALwjAA==.Adewey:BAAANQAECgUICgAAAA==.Adorabull:BAAANQADCgEIAQAAAA==.',
Ae='Aenastian:BAAANQADCgUIDwABNQAECgkJKAACALwjAA==.',
Ak='Akhalla:BAAANQAECgQIBAABNQAECgUIBgADAAAAAA==.Akre:BAAANQADCgcIEQAAAQ==.Akumä:BAAANQADCgcIEQAAAA==.',
Al='Aleannia:BAAANQADCggICAAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAABNQAECoEYAAIBAAgKMBa0ZwA3AgABAAgKMBa0ZwA3AgAAAA==.Algodón:BAAANQADCgEIAgABNQAECgkJLQAEAAQjAA==.Alibrexia:BAABNQAECoEXAAIFAAcKVAbgFAAsAQAFAAcKVAbgFAAsAQAAAA==.Allus:BAAANQABCgUICQAAAA==.Alphaomega:BAAANQAECgEIAQAAAA==.',
An='Anarcy:BAAANQAECgIIAgAAAA==.Anastaysha:BAAANQABCgQIBAABNQAECgEIAgADAAAAAA==.Ankan:BAAANQAECgcIEAABNQAECgkJKAACALwjAA==.',
Ar='Arcticplague:BAAANQADCgEIAQAAAA==.Ardatha:BAAANQADCgIIAgAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.Arlor:BAAANQADCgYIDAAAAA==.',
As='Ashkada:BAAANQADCgQIBAAAAA==.Astrocakes:BAAANQADCgYICgABNQAECggIHgAGAKIcAA==.',
At='Athenä:BAACNQAFFIENAAIHAAUKvBQXBABhAQAHAAUKvBQXBABhAQA1AAQKgRwAAgcACApJG10aAPMBAAcACApJG10aAPMBAAAA.Atsuma:BAAANQADCggICwAAAA==.Atthel:BAAANQAECgYIDQAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgYICgADAAAAAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAAANQAECgEIAgAAAA==.',
Ba='Baela:BAAANQAECgMIAwABNQAFFAUIEQAIABcgAA==.Baelthemar:BAAANQADCgUIBQAAAA==.Bajafresh:BAAANQADCgMIAwAAAA==.Bambita:BAAANQADCgEIAQAAAA==.Battleshaman:BAAANQABCgMIAgAAAA==.',
Be='Benjinana:BAAANQAECgUIDwAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Blackened:BAAANQAECgYIBgAAAA==.Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Boricua:BAAANQAECgIIAgAAAA==.Bountty:BAAANQADCgYIBgAAAA==.',
Br='Brightbane:BAAANQAECgEIAQAAAA==.',
Bu='Buddie:BAAANQADCggICAAAAA==.Buffaloseven:BAAANQAECgIIBQABNQAFFAUICAAJAEwXAA==.Bulleitrye:BAAANQADCgYIBgAAAA==.',
By='Byorn:BAAANQAECgcIDgABNQAFFAIIAgADAAAAAA==.',
Ca='Cairdamane:BAABNQAECoEXAAIKAAgK7g6yZADCAQAKAAgK7g6yZADCAQAAAA==.Calidrina:BAABNQAECoEZAAILAAgK4wxYKQDYAQALAAgK4wxYKQDYAQAAAA==.Caness:BAAANQADCgEIAQAAAA==.',
Ce='Celldrassil:BAAANQAECgUIBQAAAA==.Cereel:BAAANQAECgcICwABNQAECggIHgAGAKIcAA==.',
Ch='Chardaney:BAAANQAECgEIAgAAAA==.',
Ci='Cii:BAABNQAECoEWAAIHAAYKyBMfKwBYAQAHAAYKyBMfKwBYAQAAAA==.Ciine:BAAANQADCgYICAABNQAECgYIFgAHAMgTAA==.Ciruzita:BAAANQADCgUIBQAAAA==.',
Cl='Clampz:BAEANQAECgUIBgABNQAFFAUIDAAMAEkbAA==.',
Co='Colandros:BAAANQADCgEJAQAAAA==.Colara:BAAANQAECgUIDAAAAA==.Colbear:BAAANQABCgUICQAAAA==.Coldspace:BAABNQAECoEpAAIBAAkK3CCkGQBJAwABAAkK3CCkGQBJAwAAAA==.Corlock:BAAANQABCgMIAwAAAA==.',
Cr='Crassberry:BAACNQAFFIEJAAINAAQKThfdCQBNAQANAAQKThfdCQBNAQA1AAQKgR4AAg0ACQopJIQdAL0CAA0ACQopJIQdAL0CAAAA.Creepindeath:BAAANQAECgEJAgAAAA==.',
Cu='Cucaracha:BAAANQAECgUIBQAAAA==.',
Cy='Cyndal:BAAANQADCgcIGAABNQAECgYICgADAAAAAA==.Cyndle:BAAANQADCggIFQABNQAECgYICgADAAAAAA==.Cyntu:BAAANQADCggIGQABNQAECgYICgADAAAAAA==.',
Da='Dankbuds:BAAANQAECggIAQAAAA==.Dankothy:BAAANQAECgEIAQABNQAECggIAQADAAAAAA==.Dantes:BAAANQAECgEJAQAAAA==.Darkryu:BAAANQADCgYIEAAAAA==.Darkspace:BAAANQAECgMIAwABNQAECgkJKQABANwgAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQAECgEIAQAAAA==.',
De='Deathforever:BAAANQADCgYICgAAAA==.Deaus:BAAANQADCggIFQAAAA==.Delrus:BAABNQAECoEaAAMOAAgKmRvvEQCjAgAOAAgKmRvvEQCjAgAPAAMKcBG6gQCbAAAAAA==.Demon:BAABNQAECoEmAAICAAkK4R8NDAA1AwACAAkK4R8NDAA1AwABNQAFFAYIEQAMAOUSAA==.Demowneege:BAAANQADCggICAABNQAFFAUIDAAFAN4RAA==.Denzvic:BAAANQAECgYICwAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Diddyjr:BAABNQAECoEdAAIJAAkKexrTZQCeAgAJAAkKexrTZQCeAgAAAA==.Disowneege:BAAANQAECgUICQABNQAFFAUIDAAFAN4RAA==.',
Do='Doodu:BAAANQAFFAEIAQAAAA==.',
Dr='Dragnas:BAABNQAECoEmAAMQAAgKyBHhEAA9AgAQAAgKyBHhEAA9AgAIAAQKuxLEpgD4AAAAAA==.Dragonisa:BAAANQAECgEIAQAAAA==.Drakass:BAAANQADCggICAAAAA==.Dramakiller:BAAANQAECgIIAgAAAA==.Drcornbread:BAAANQAECgUIDwAAAA==.Drcornellia:BAAANQADCgYIBwABNQAECgUIDwADAAAAAA==.Drdreggs:BAAANQAECgcIEQAAAA==.Drop:BAAANQADCgQIBAABNQAECggIHQABAMMUAA==.Druduwolf:BAAANQAECgQIBQAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgUICAADAAAAAA==.Dustyhunter:BAAANQADCgQIBAAAAA==.',
Ea='Eatbuttforpi:BAAANQADCgUIBwABNQAECggIHgAGAKIcAA==.',
El='Elastar:BAABNQAECoEbAAIRAAcKoBe9EADtAQARAAcKoBe9EADtAQAAAA==.Ellimist:BAEANQAECgcIDAAAAA==.Elsan:BAAANQADCgQIBAAAAA==.Elycee:BAAANQAECggICwAAAA==.',
Em='Emura:BAAANQADCgcIBwAAAA==.',
En='Enveliria:BAAANQAECgUIDgABNQAECgkJKAACALwjAA==.',
Er='Eraser:BAABNQAECoEoAAMSAAgKAhJbMwBfAQASAAYK0xBbMwBfAQATAAYKUgy3iwA5AQAAAA==.Erazar:BAAANQAECgUICQAAAA==.Erickk:BAABNQAECoEhAAIJAAkKzhlrZgCdAgAJAAkKzhlrZgCdAgAAAA==.Eristela:BAAANQADCgUICQAAAA==.',
Es='Escanorlion:BAAANQAECgUIBwAAAA==.Essense:BAABNQAECoEbAAITAAcKVCVpHQDiAgATAAcKVCVpHQDiAgAAAA==.',
Ev='Evokedcat:BAAANQAECgcIDQAAAA==.',
Ex='Exodari:BAABNQAECoEgAAIQAAgKJwwhFAD/AQAQAAgKJwwhFAD/AQAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgIIAgABNQAECggIHgAGAKIcAA==.Fatalgrip:BAAANQADCgUIBQAAAA==.',
Fe='Fel:BAABNQAECoEsAAMCAAkKQyNKBgCEAwACAAkK+yJKBgCEAwALAAcKfBeFKQDWAQAAAA==.Fellius:BAAANQADCgQIBAAAAA==.Fellkarras:BAAANQAECgQIBQABNQAECggIIAAUAJcjAA==.Felprincess:BAAANQABCgYICgAAAA==.',
Fi='Fibitz:BAAANQAECgcICwAAAA==.Findstewie:BAAANQABCgYICgABNQABCggIDgADAAAAAA==.Fiofio:BAABNQAECoEbAAIJAAcKdR2kgwBeAgAJAAcKdR2kgwBeAgAAAA==.Fizban:BAAANQAECgYIEgAAAA==.',
Fl='Flik:BAAANQAECgUICAABNQAECgkJLgATAG8cAA==.',
Fo='Foringojr:BAAANQAECgIIAgAAAA==.',
Fr='Frigidheart:BAAANQAECgUIDAABNQAECgcIDwADAAAAAA==.Frostetute:BAAANQAECgYIBgAAAA==.',
Fu='Furrybawlz:BAAANQADCggICAAAAA==.',
['Fà']='Fàllén:BAAANQAECgEJAgABNQAFFAIIAgADAAAAAA==.',
Ga='Gadogear:BAAANQAECgQIBwAAAA==.Galabren:BAAANQAECgYJDQAAAA==.Garlik:BAAANQADCgUIDQAAAA==.',
Gf='Gfr:BAAANQAECgUICgAAAA==.',
Gi='Giddoo:BAAANQADCggIDAAAAA==.Gilnean:BAAANQABCgEIAQAAAA==.',
Gn='Gnomeanator:BAAANQABCgIIAgAAAA==.',
Go='Goatcheeze:BAAANQAECgYIDAAAAA==.Gohlemsaurus:BAAANQADCggIGAAAAA==.',
Gu='Gulen:BAAANQADCggJGwAAAA==.Gullee:BAAANQABCggIEwAAAA==.',
Gw='Gwennevier:BAAANQABCgYIDAAAAA==.',
['Gí']='Gíga:BAAANQAECgMIAwAAAA==.',
Ha='Halsten:BAAANQAECgUICQAAAA==.Hamish:BAAANQAECgEIAQAAAA==.',
He='Hellenkeller:BAEANQAFFAEIAQABNQAFFAUIDAAMAEkbAA==.Heloisa:BAAANQADCgYIBgAAAA==.',
Hi='Hitt:BAAANQAECgMIBAAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.Hoofingit:BAAANQADCgQIBAAAAA==.',
Hr='Hroc:BAAANQAECgYIEQAAAA==.',
Ic='Icedlatte:BAAANQADCgQICAAAAA==.Icywolfy:BAAANQAECgIIAgAAAA==.',
Ig='Igreetyou:BAAANQAECgMIAwAAAA==.',
Il='Illune:BAAANQAECgUIEQABNQAECgkJIAAHACMhAA==.',
Im='Imleapingit:BAAANQAECgcIEQAAAA==.',
In='Intoodeep:BAABNQAECoEfAAIVAAkKiBDLJAA1AgAVAAkKiBDLJAA1AgAAAA==.',
Ir='Ir:BAABNQAECoEvAAIJAAkKABvYTQDWAgAJAAkKABvYTQDWAgAAAA==.Irrlvntgobbo:BAAANQAECgUICAAAAA==.',
Is='Isawarriorr:BAABNQAECoEcAAMGAAgKWxv7YwBEAgAGAAgKhRn7YwBEAgARAAIKDhsvLgCSAAAAAA==.Ishdo:BAAANQAECgYIEgAAAA==.Ishlok:BAAANQADCgUIBQABNQAECgYIEgADAAAAAA==.Ishmael:BAAANQAECgMIAwABNQAFFAIIAgADAAAAAA==.Ishwar:BAAANQADCgcIEgABNQAECgYIEgADAAAAAA==.',
Ja='Jakytreehorn:BAAANQAECgcIEQAAAA==.Jaydm:BAAANQAECgYICQABNQAFFAUICAAJAEwXAA==.',
Je='Jenevelle:BAAANQAECgMJAwAAAA==.Jerisil:BAAANQADCgUICAAAAA==.Jessiel:BAAANQAECgQIBAAAAA==.Jet:BAABNQAECoEdAAIBAAgKwxQzdAAXAgABAAgKwxQzdAAXAgAAAA==.',
Ju='Julthaenia:BAABNQAECoEaAAIWAAcKpBw1BQBQAgAWAAcKpBw1BQBQAgABNQAECgkJKAACALwjAA==.Junjia:BAAANQADCgUIBQAAAA==.',
Ka='Kagebushin:BAAANQABCgIIAgAAAA==.Kagome:BAAANQADCgQIBgABNQAECgEIAgADAAAAAA==.Kalofelement:BAAANQADCgEIAQAAAA==.Kalysy:BAAANQABCggICAABNQAECgkJKAACALwjAA==.Karash:BAAANQAECgUICAAAAA==.Karmaisab:BAAANQAECgMIAQAAAA==.Karnrae:BAAANQAECgcIEQAAAA==.Karynos:BAABNQAECoEgAAIXAAgK+w+SbQDuAQAXAAgK+w+SbQDuAQAAAA==.Katwolf:BAAANQAECgUICwAAAA==.Katyah:BAAANQAECgYIEwAAAA==.Kavourkaa:BAAANQABCggIFgAAAA==.',
Ke='Keynivas:BAAANQAECgIJAgAAAA==.',
Ki='Killiua:BAAANQAECgYICgAAAA==.',
Ko='Konspiracy:BAAANQAECgYIDgAAAA==.',
Kr='Kraguva:BAAANQAECgQIBAAAAA==.Krataar:BAAANQAECgEIAQABNQAECgYIDQADAAAAAA==.Kroot:BAAANQAECgUICwABNQAECgcICwADAAAAAA==.Krous:BAACNQAFFIEJAAIGAAUKRhZDDgCfAQAGAAUKRhZDDgCfAQA1AAQKgSAAAgYACQqqHQNBAK8CAAYACQqqHQNBAK8CAAAA.Kryph:BAAANQAECgUIDgAAAA==.',
['Kä']='Kämpfer:BAAANQAECgQIBgABNQAECggIKQAYAJYUAA==.',
La='Lafiel:BAABNQAECoEUAAITAAcKuw6vcQCPAQATAAcKuw6vcQCPAQAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Laurandre:BAAANQAECgYIEQAAAA==.Lazeras:BAAANQAECgQIBAABNQAECgcIEgADAAAAAA==.',
Le='Letsgetwet:BAAANQADCgUIBQAAAA==.',
Li='Liefic:BAAANQAECgYIDQAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilienne:BAAANQABCgYIBwAAAA==.Lilstooge:BAAANQABCgYIBwABNQABCggIDgADAAAAAA==.',
Ll='Llylith:BAAANQABCgMIBAAAAA==.',
Lo='Locke:BAAANQAECgIIAgABNQAECggIHQABAMMUAA==.',
Lu='Luckykilla:BAABNQAECoEjAAIVAAgK1RTlLAD+AQAVAAgK1RTlLAD+AQAAAA==.Lucÿ:BAABNQAECoEmAAMIAAkKox4hHADhAgAIAAkKox4hHADhAgAKAAYKpxTJgwBqAQAAAA==.Lune:BAAANQADCgUICwAAAA==.Lurith:BAABNQAECoElAAMNAAcKWxKBbwAyAQANAAUKyhWBbwAyAQAUAAYKPw0MbgAXAQAAAA==.Luxtyrannica:BAAANQAECgQIBQAAAA==.',
Ly='Lydrain:BAAANQADCgIJAwAAAA==.Lylia:BAAANQADCggIDQAAAA==.',
Ma='Marahh:BAAANQABCgIIAgAAAA==.Mattbolt:BAAANQAECgYIDwAAAA==.Maximoose:BAAANQAFFAIIAgAAAA==.Mayu:BAAANQADCggIFQAAAA==.Mazigos:BAAANQAECgUJBQAAAA==.',
Me='Medjrab:BAABNQAECoEoAAINAAkKXyEzCgBZAwANAAkKXyEzCgBZAwAAAA==.Mefi:BAAANQADCgcIDAAAAA==.Melyria:BAAANQAECgcIEQAAAA==.Meristem:BAAANQAECgUIDwAAAA==.Merko:BAAANQADCgEIAQABNQAECgcICwADAAAAAA==.',
Mi='Mignius:BAAANQADCgYIBgAAAA==.Mistified:BAAANQABCgIIBAAAAA==.',
Mo='Moedorai:BAAANQAECgcIDwAAAA==.Mogma:BAAANQAECgUICQAAAA==.Mogsarren:BAAANQABCgIIAgABNQAECgkJLQAUAOElAA==.Momentomori:BAAANQADCgUICwAAAA==.Moonbounds:BAACNQAFFIESAAIIAAYKBhryAwAhAgAIAAYKBhryAwAhAgA1AAQKgTQAAggACQpuIz8GAIMDAAgACQpuIz8GAIMDAAAA.Moondoggey:BAAANQADCgUIBQAAAA==.Morgana:BAAANQADCgUICAAAAA==.Mousechief:BAAANQAECgQIBwAAAA==.Moxxzi:BAABNQAECoEWAAINAAYKXg6saQBGAQANAAYKXg6saQBGAQAAAA==.',
Mu='Muhfookinbak:BAAANQAECgYIEAAAAA==.Muvahmedicin:BAAANQADCgcIBwAAAA==.',
Na='Naksu:BAAANQADCgYJFgABNQAECgcIFwATAEkdAA==.Naksù:BAAANQADCgUIBQABNQAECgcIFwATAEkdAA==.Naksû:BAAANQADCgYIBgABNQAECgcIFwATAEkdAA==.Naksü:BAABNQAECoEXAAITAAcKSR27OQBfAgATAAcKSR27OQBfAgAAAA==.',
Ne='Neifeb:BAABNQAECoEeAAIEAAcKoxAhggDZAQAEAAcKoxAhggDZAQAAAA==.Nerfherder:BAAANQABCgcIDQABNQAECgcIHwAFALoXAA==.',
Ni='Niallivdam:BAAANQAECgEIAgAAAA==.Nights:BAAANQAECgIIAwABNQAFFAYIEQAMAOUSAA==.Ninh:BAABNQAECoEvAAIZAAkK4waKHgB1AQAZAAkK4waKHgB1AQAAAA==.Nintendopsp:BAAANQADCgYICgAAAA==.Ninthgate:BAAANQAECgUIDAAAAA==.',
No='Noble:BAAANQAECgcIEQAAAA==.Nogood:BAAANQAECggIEgAAAA==.Northwest:BAAANQABCgYJBQAAAA==.Notsodemon:BAAANQAECgQICAABNQAECgYIEgADAAAAAA==.Notsomage:BAAANQAECgYIEgAAAA==.',
Ny='Nyorai:BAAANQABCgQIAwAAAA==.Nyxwing:BAAANQAECgQIBQAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAABNQAECoEZAAMOAAcK4BtNGwAzAgAOAAcK4BtNGwAzAgAPAAEKxQLNtAAaAAAAAA==.',
Od='Oddpocalypse:BAAANQADCgQIBAAAAA==.Odinheâthen:BAAANQADCgYJDAAAAA==.',
Ol='Olydwarf:BAAANQAECgEIAQAAAA==.',
On='Onebadmutha:BAAANQAECgYIDAAAAA==.Ontop:BAABNQAECoEvAAIEAAkKIB4yKADYAgAEAAkKIB4yKADYAgAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAAANQAECgYIEgAAAA==.',
Ow='Owneege:BAACNQAFFIEMAAMFAAUK3hGZAQDkAAAGAAMKyxVsHADnAAAFAAMKLA6ZAQDkAAA1AAQKgSMAAwUACQrWIroIACsCAAYACQojIls7AMICAAUABgpkIroIACsCAAAA.',
Pa='Paapaa:BAAANQADCgcIBQAAAA==.Pallideaus:BAAANQAECgUIDwAAAA==.Pallinar:BAAANQAECgUIBQAAAA==.Pasquale:BAAANQAECgQIBgAAAA==.Pauzhaan:BAAANQAECgQIBAABNQAECgcIHwAFALoXAA==.',
Pe='Pebbles:BAABNQAECoEnAAIBAAgKpxSOewADAgABAAgKpxSOewADAgAAAA==.Pedorus:BAAANQABCgYIBwABNQAECgkJJgAIAKMeAA==.Penjerman:BAAANQADCggICAABNQAECggIHgAGAKIcAA==.',
Pi='Picklericky:BAAANQADCggIDQAAAA==.Pilgrimm:BAECNQAFFIEMAAIMAAUKSRtsBADUAQAMAAUKSRtsBADUAQA1AAQKgSEABAwACQp3Jc8CAHoDAAwACQp3Jc8CAHoDABoAAQq5G7IXAE0AABUAAQpBC4GGADwAAAAA.Pinxyl:BAAANQABCgcIBwAAAA==.Pistola:BAAANQAECgQIBAAAAA==.Pixyl:BAAANQADCggIDgAAAA==.',
Pl='Plaguerott:BAABNQAECoEYAAIbAAcKtAf+UAAiAQAbAAcKtAf+UAAiAQAAAA==.Plaguewind:BAAANQADCgQIBQAAAA==.',
Po='Polydh:BAABNQAECoElAAIcAAgKYyX0AQBfAwAcAAgKYyX0AQBfAwAAAA==.Poobah:BAAANQAECgYIEQAAAA==.Popsicles:BAABNQAECoEZAAMdAAgKfhYPBQBHAgAdAAgKfhYPBQBHAgASAAEK5wUtewAiAAAAAA==.Potrat:BAAANQAECgMJAwAAAA==.Pouffant:BAAANQAECgQICQAAAA==.',
Pr='Praddagy:BAAANQADCgUIBQAAAA==.Pronoz:BAAANQAECggIBwAAAA==.',
Pu='Purpyl:BAAANQAECgUIBgAAAA==.',
Pw='Pwnageddon:BAAANQADCgcIFgAAAA==.Pwnjitsu:BAABNQAECoEfAAIeAAcKThvPHgAOAgAeAAcKThvPHgAOAgAAAA==.',
Py='Pyrothermia:BAACNQAFFIEIAAIJAAUKTBcDFACuAQAJAAUKTBcDFACuAQA1AAQKgR8AAwkACQr/GY1oAJgCAAkACQr/GY1oAJgCAB8AAwo7BxQsAHIAAAAA.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Rawhoof:BAABNQAECoEvAAIGAAkKCyFCIQAkAwAGAAkKCyFCIQAkAwAAAA==.Razak:BAABNQAECoEoAAIQAAgKQyHpBgAFAwAQAAgKQyHpBgAFAwAAAA==.',
Rd='Rdnckromeo:BAAANQAECgQIBAAAAA==.',
Re='Redlock:BAAANQAECgUIDwAAAA==.Redrum:BAABNQAECoEgAAIUAAgKlyMWEgAIAwAUAAgKlyMWEgAIAwAAAA==.Renarin:BAABNQAECoEuAAITAAkKbxyGIQDMAgATAAkKbxyGIQDMAgAAAA==.Renisa:BAAANQAECgYIEwAAAA==.Renobagem:BAAANQADCgEIAQAAAA==.Retman:BAAANQADCggIDgAAAA==.Reu:BAAANQADCggJCAAAAA==.Revlyk:BAABNQAECoEcAAIQAAgKahgDDQCEAgAQAAgKahgDDQCEAgABNQAECgkJKAACALwjAA==.',
Rh='Rhoanna:BAAANQADCgcICgAAAA==.Rhoupert:BAAANQAECgUIDAABNQAECgYIEwADAAAAAA==.',
Ri='Rimastus:BAAANQADCgEIAQAAAA==.',
Ro='Roccot:BAABNQAECoEdAAIUAAcKhhvOMAAwAgAUAAcKhhvOMAAwAgAAAA==.Rotjaw:BAAANQADCggIDAAAAA==.Roughedge:BAAANQADCgIIAgAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQABCgYIDAAAAA==.Sallanu:BAAANQADCgQIBAAAAA==.',
Sc='Scalycat:BAAANQAECgUIDAAAAA==.Schuey:BAAANQADCggICAAAAA==.Scum:BAAANQADCgcIDQABNQADCggICAADAAAAAA==.',
Se='Senaeda:BAAANQADCgQIBwAAAA==.Senate:BAABNQAECoEeAAMKAAcKJBEyaQC0AQAKAAcKJBEyaQC0AQAIAAEKqgFLFQEgAAAAAA==.',
Sh='Shaamazing:BAAANQABCgIIAgAAAA==.Shablaam:BAAANQADCggIEQAAAA==.Shadowbear:BAAANQAECgUIBwAAAA==.Sherrilyn:BAAANQADCgYICAAAAA==.Shifdiah:BAAANQAECgUIBQAAAA==.Shocktherapi:BAAANQAECgMIAwAAAA==.Shrimpback:BAAANQAECgEIAQAAAA==.',
Si='Singularity:BAAANQAECgQJBQAAAA==.',
Sk='Skelli:BAECNQAFFIEOAAITAAUK0BIVDQCVAQATAAUK0BIVDQCVAQA1AAQKgRcAAhMACQqSGgk1AHICABMACQqSGgk1AHICAAE1AAQKBwgMAAMAAAAA.Skittlesdan:BAABNQAECoEZAAQXAAgKBhEDaAD+AQAXAAgKBhEDaAD+AQAWAAEKLAhCLQAxAAAgAAEKxQTRewApAAAAAA==.',
Sl='Slaykween:BAAANQAECgUICgAAAA==.',
Sm='Smallz:BAAANQADCgYICwABNQAECgYIEgADAAAAAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAABNQAECoEfAAQFAAcKuheyDADKAQAFAAYKexmyDADKAQAGAAYKXAwgvABUAQARAAIKjhTZMQBrAAAAAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Steakhaus:BAAANQAECgIIAgAAAA==.Stonedragon:BAECNQAFFIEGAAIEAAIKbxftGAC5AAAEAAIKbxftGAC5AAA1AAQKgT0AAgQACQrvJM8DAMEDAAQACQrvJM8DAMEDAAAA.Stormfist:BAAANQADCgQIBgAAAA==.Stormhaven:BAAANQADCgQJBAABNQAECgEIAgADAAAAAA==.Stormrender:BAAANQAECgUICgAAAA==.Stormriders:BAAANQAECgUIEwAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Streea:BAAANQADCggIFgABNQAECgYICgADAAAAAA==.Stubz:BAAANQABCgQIBgAAAA==.',
Su='Sugi:BAAANQABCgIIAgABNQAECgkJJwALAMkdAA==.Sukonamí:BAAANQAECgcIEgAAAA==.Suzhou:BAAANQAECgYICgAAAA==.Suzoomies:BAAANQADCggIDwAAAA==.',
Sw='Swisscheese:BAABNQAECoEXAAMXAAcK4RfMaAD8AQAXAAcK4RfMaAD8AQAgAAEKLwo6dAA0AAAAAA==.Swoopyboop:BAAANQADCgQIBAAAAA==.',
Sy='Sybaek:BAAANQAECgcICAAAAA==.Sycò:BAABNQAECoEhAAMEAAkK8iLRDABnAwAEAAkK8iLRDABnAwAhAAEKkQGxiQAiAAAAAA==.Syraxa:BAAANQAECgMIBAABNQAECgkJJgAOAOwbAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAQABNQAFFAQICAAEAJcOAA==.',
Ta='Taedish:BAAANQADCgQIBAAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.Tannith:BAAANQABCgUIDAABNQABCggIDgADAAAAAA==.Tayy:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Telan:BAAANQADCgUIBQAAAA==.Tempertotems:BAAANQADCggIDQAAAA==.Tenastin:BAAANQADCgQIBAAAAA==.Terragosa:BAAANQAECgUIDwAAAA==.Tetchybono:BAAANQAECgYICAAAAA==.Tettra:BAAANQABCgEIAQABNQAECgYICgADAAAAAA==.',
Th='Thahawtz:BAAANQADCgYJDAAAAA==.Thirinis:BAAANQAECgUIBgAAAA==.Thope:BAAANQADCgYIFgAAAA==.Thundergirl:BAAANQADCgYIDAAAAA==.',
Tr='Traesdyne:BAAANQADCgMIBAAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECgcIEgADAAAAAA==.Trainar:BAAANQAECgQICgABNQAECgYIEgADAAAAAA==.Triggs:BAAANQABCgIIAgAAAA==.Troggdor:BAAANQABCggIDgABNQAECgcIHwAFALoXAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAAANQAECgIIBAAAAA==.Trõnlight:BAAANQAECgEIAQAAAA==.',
Ts='Tsunah:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQAECgEIAQAAAA==.Turim:BAAANQAECgEIAQAAAA==.',
Ty='Tyrawick:BAAANQADCgUIBQAAAA==.Tyrlidd:BAAANQAECgUIDwAAAA==.',
Un='Unavoidable:BAAANQADCgMJAwAAAA==.Unlikelytale:BAABNQAECoEiAAIIAAkK3RvkIwC4AgAIAAkK3RvkIwC4AgAAAA==.',
Ur='Urbanmeyer:BAAANQADCggIFwAAAA==.Uricash:BAABNQAECoEnAAIJAAkKSh3tPwD3AgAJAAkKSh3tPwD3AgAAAA==.Urrax:BAAANQADCgEIAQABNQADCgIIAgADAAAAAA==.Urzual:BAABNQAECoEfAAMQAAcKXRxlEABHAgAQAAcKXRxlEABHAgAIAAYKbhTidgB4AQAAAA==.',
Va='Vandreynna:BAABNQAECoEoAAICAAkKvCMbBgCIAwACAAkKvCMbBgCIAwAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velsiana:BAAANQAECgMIAwAAAA==.Velveetah:BAAANQADCgYIBwABNQAECgUIDwADAAAAAA==.Verbrennen:BAABNQAECoEpAAIYAAgKlhR3FwAqAgAYAAgKlhR3FwAqAgAAAA==.Verita:BAAANQAECgQIBgAAAA==.Verlynne:BAAANQADCgcIBwAAAA==.',
Vi='Viviann:BAABNQAECoEbAAMYAAcKjAk9JgBnAQAYAAcKjAk9JgBnAQAiAAYK/wiJIAAxAQAAAA==.',
Vo='Von:BAAANQADCgEIAQAAAA==.',
Wa='Walee:BAAANQADCgIIAgAAAA==.Walfred:BAAANQAECgMIAwABNQAECgcIJQANAFsSAA==.Warraxe:BAAANQADCgYIBgAAAA==.Waukeen:BAAANQABCgIIAgAAAA==.Wayloren:BAABNQAECoEeAAIBAAcKHAYF2AAxAQABAAcKHAYF2AAxAQAAAA==.Wayverly:BAAANQABCgUIBwABNQAECgEIAgADAAAAAA==.',
We='Wetboycaird:BAAANQADCgMIAwAAAA==.',
Wi='Wickathy:BAABNQAECoEZAAIcAAgKhR5HBQC0AgAcAAgKhR5HBQC0AgAAAA==.Wickcreu:BAAANQAECgIIAgAAAA==.',
Wo='Worstdps:BAABNQAECoEsAAICAAkKChXEIgBeAgACAAkKChXEIgBeAgAAAA==.',
Wu='Wuldorr:BAABNQAECoEaAAIBAAkKChDofwD4AQABAAkKChDofwD4AQAAAA==.',
Wy='Wynnifred:BAAANQAECgMICAAAAA==.',
Xa='Xaltheris:BAAANQAECgEJAQAAAA==.',
Xe='Xenothor:BAAANQAECgEIAQAAAA==.Xethreal:BAAANQAECgUIDwAAAA==.',
Xy='Xype:BAAANQAECggICAAAAA==.',
Xz='Xzara:BAAANQAECgYICgAAAA==.',
Yu='Yura:BAAANQADCggICAAAAA==.',
Yv='Yvvee:BAAANQAECgMIAwAAAA==.',
Za='Zapbranigan:BAAANQADCggIDQAAAA==.',
Zi='Zifao:BAABNQAECoEdAAIJAAgKIyBYUgDLAgAJAAgKIyBYUgDLAgAAAA==.',
Zo='Zonora:BAAANQAECgcIEgAAAA==.',
['Äz']='Äzrael:BAAANQAECgcIEAAAAA==.',
['Çr']='Çréwüsæðèr:BAAANQAECgYIEQAAAA==.',
['Ðì']='Ðìaßlo:BAACNQAFFIEIAAIEAAQKlw6kDQBDAQAEAAQKlw6kDQBDAQA1AAQKgScAAgQACQqeH24fAP4CAAQACQqeH24fAP4CAAAA.',
['Òd']='Òdinn:BAAANQADCgcIBwAAAA==.',
['Ød']='Ødin:BAAANQADCggIFAABNQAECgEIAgADAAAAAA==.',
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
