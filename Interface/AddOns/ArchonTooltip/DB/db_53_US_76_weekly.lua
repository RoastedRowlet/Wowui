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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Unknown-Unknown','Hunter-BeastMastery','Warrior-Arms','Paladin-Protection','Shaman-Restoration','Mage-Arcane','Rogue-Subtlety','DeathKnight-Unholy','Warrior-Fury','Shaman-Enhancement','Warrior-Protection','Priest-Holy','Priest-Shadow','DemonHunter-Devourer','DeathKnight-Blood','Rogue-Assassination','Warlock-Demonology','Evoker-Preservation','Shaman-Elemental','Monk-Mistweaver','Rogue-Outlaw','DeathKnight-Frost','DemonHunter-Vengeance','Monk-Windwalker','Mage-Frost','Hunter-Marksmanship',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Aberaht:BAABNQAECoEUAAIBAAcKFyCkRAB8AgABAAcKFyCkRAB8AgAAAA==.Absolution:BAAANQAECgQICAAAAA==.',
Ac='Ackianae:BAAANQAECgYIEAAAAA==.',
Ad='Adewey:BAAANQAECgUICgAAAA==.Adorabull:BAAANQADCgEIAQAAAA==.',
Ae='Aenastian:BAAANQADCgUIDwABNQAECgkJIgACAEwjAA==.',
Ak='Akhalla:BAAANQAECgQIBAABNQAECgUIBQADAAAAAA==.Akre:BAAANQADCgcIDAAAAQ==.Akumä:BAAANQADCgcIEQAAAA==.',
Al='Aleannia:BAAANQADCggICAAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAAANQAECgYIDgAAAA==.Algodón:BAAANQADCgEIAgABNQAECgkJJgAEACQiAA==.Alibrexia:BAAANQAECgYIDQAAAA==.Allus:BAAANQABCgUICQAAAA==.Alphaomega:BAAANQADCggIIQAAAA==.',
An='Anarcy:BAAANQAECgIIAgAAAA==.Anastaysha:BAAANQABCgQIBAABNQAECgEIAgADAAAAAA==.Ankan:BAAANQAECgYICwABNQAECgkJIgACAEwjAA==.',
Ar='Arcticplague:BAAANQADCgEIAQAAAA==.Ardatha:BAAANQADCgIIAgAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.Arlor:BAAANQADCgYIDAAAAA==.',
As='Astrocakes:BAAANQADCgYICgABNQAECggIHAAFAFYcAA==.',
At='Athenä:BAACNQAFFIEIAAIGAAQKYw56BAAJAQAGAAQKYw56BAAJAQA1AAQKgRoAAgYACApJG64UAAwCAAYACApJG64UAAwCAAAA.Atsuma:BAAANQADCggICwAAAA==.Atthel:BAAANQAECgYICQAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgYICgADAAAAAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAAANQAECgEIAQAAAA==.',
Ba='Baela:BAAANQAECgMIAwABNQAFFAUIDAAHAK4eAA==.Baelthemar:BAAANQADCgUIBQAAAA==.Bajafresh:BAAANQADCgMIAwAAAA==.Battleshaman:BAAANQABCgMIAgAAAA==.',
Be='Benjinana:BAAANQAECgUIDwAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Boricua:BAAANQAECgIIAgAAAA==.Bountty:BAAANQADCgYIBgAAAA==.',
Br='Brightbane:BAAANQAECgEIAQAAAA==.',
Bu='Buddie:BAAANQADCggICAAAAA==.Buffaloseven:BAAANQAECgIIBAABNQAECgkJHAAIAM8YAA==.Bulleitrye:BAAANQADCgYIBgAAAA==.',
By='Byorn:BAAANQAECgcIDQAAAA==.',
Ca='Cairdamane:BAAANQAECgYIEAAAAA==.Calidrina:BAAANQAECgcIDwAAAA==.Caness:BAAANQADCgEIAQAAAA==.',
Ce='Celldrassil:BAAANQADCggIEgAAAA==.Cereel:BAAANQAECgUICQABNQAECggIHAAFAFYcAA==.',
Ch='Chardaney:BAAANQAECgEIAgAAAA==.',
Ci='Cii:BAAANQAECgYIEQAAAA==.Ciine:BAAANQADCgYICAABNQAECgYIEQADAAAAAA==.Ciruzita:BAAANQADCgUIBQAAAA==.',
Cl='Clampz:BAEANQAECgQIBQABNQAFFAQIBwAJAAgXAA==.',
Co='Colandros:BAAANQADCgEJAQAAAA==.Colara:BAAANQAECgUIBwAAAA==.Colbear:BAAANQABCgUICQAAAA==.Coldspace:BAABNQAECoEhAAIBAAkKGh82HAAnAwABAAkKGh82HAAnAwAAAA==.',
Cr='Crassberry:BAACNQAFFIEJAAIKAAQKThd4BQBjAQAKAAQKThd4BQBjAQA1AAQKgR4AAgoACQopJPwQAP8CAAoACQopJPwQAP8CAAAA.Creepindeath:BAAANQAECgEJAgAAAA==.',
Cu='Cucaracha:BAAANQAECgUIBQAAAA==.',
Cy='Cyndal:BAAANQADCgcIEgABNQAECgYICgADAAAAAA==.Cyndle:BAAANQADCggIDQABNQAECgYICgADAAAAAA==.Cyntu:BAAANQADCggIEwABNQAECgYICgADAAAAAA==.',
Da='Dankbuds:BAAANQADCgEJAQAAAA==.Dankothy:BAAANQADCggJHAABNQADCgEJAQADAAAAAA==.Dantes:BAAANQAECgEJAQAAAA==.Darkryu:BAAANQADCgYIEAAAAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQADCggIJAAAAA==.',
De='Deathforever:BAAANQADCgYICgAAAA==.Deaus:BAAANQADCggIFQAAAA==.Delrus:BAAANQAECgYIDgAAAA==.Demon:BAABNQAECoEeAAICAAkKeBwREADsAgACAAkKeBwREADsAgABNQAFFAYIDAAJAOMQAA==.Demowneege:BAAANQADCggICAABNQAFFAQICQALAJkQAA==.Denzvic:BAAANQAECgYICwAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Diddyjr:BAABNQAECoEaAAIIAAkKFhmOZwB+AgAIAAkKFhmOZwB+AgAAAA==.Disowneege:BAAANQAECgUICQABNQAFFAQICQALAJkQAA==.',
Do='Doodu:BAAANQAFFAEIAQAAAA==.',
Dr='Dragnas:BAABNQAECoEfAAMMAAgKnQ5sEAAcAgAMAAgKnQ5sEAAcAgAHAAQKuxIEkwAAAQAAAA==.Dragonisa:BAAANQADCgUIBQAAAA==.Drakass:BAAANQADCggICAAAAA==.Dramakiller:BAAANQAECgIIAgAAAA==.Drcornbread:BAAANQAECgUIDwAAAA==.Drcornellia:BAAANQADCgYIBwABNQAECgUIDwADAAAAAA==.Drdreggs:BAAANQAECgcIDQAAAA==.Drop:BAAANQADCgQIBAABNQAECggIFQABAOQSAA==.Druduwolf:BAAANQAECgQIBAAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgQIBwADAAAAAA==.Dustyhunter:BAAANQADCgQIBAAAAA==.',
Ea='Eatbuttforpi:BAAANQADCgUIBwABNQAECggIHAAFAFYcAA==.',
El='Elastar:BAABNQAECoEUAAINAAcK5hXgDwDMAQANAAcK5hXgDwDMAQAAAA==.Ellimist:BAEANQAECgcIDAAAAA==.Elsan:BAAANQADCgQIBAAAAA==.Elycee:BAAANQAECggICwAAAA==.',
Em='Emura:BAAANQADCgcIBwAAAA==.',
En='Enveliria:BAAANQAECgUIDgABNQAECgkJIgACAEwjAA==.',
Er='Eraser:BAABNQAECoEfAAMOAAgKVA4ReQA/AQAOAAYKogsReQA/AQAPAAUKLBHzNAAnAQAAAA==.Erazar:BAAANQAECgUICQAAAA==.Erickk:BAABNQAECoEbAAIIAAkKdBf3XgCUAgAIAAkKdBf3XgCUAgAAAA==.Eristela:BAAANQADCgUICQAAAA==.',
Es='Escanorlion:BAAANQAECgUIBwAAAA==.Essense:BAABNQAECoEUAAIOAAcKOCW0GADkAgAOAAcKOCW0GADkAgAAAA==.',
Ev='Evokedcat:BAAANQAECgcIDQAAAA==.',
Ex='Exodari:BAABNQAECoEZAAIMAAgKAQr/EgDnAQAMAAgKAQr/EgDnAQAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgIIAgABNQAECggIHAAFAFYcAA==.Fatalgrip:BAAANQADCgUIBQAAAA==.',
Fe='Fel:BAABNQAECoEjAAMCAAkKeSE1CQBFAwACAAkKHCE1CQBFAwAQAAcKfBf6JADiAQAAAA==.Fellius:BAAANQADCgQIBAAAAA==.Fellkarras:BAAANQAECgEIAQABNQAECggIHwARAJAjAA==.Felprincess:BAAANQABCgQIBAAAAA==.',
Fi='Fibitz:BAAANQAECgcICwAAAA==.Findstewie:BAAANQABCgYICgABNQABCggIDgADAAAAAA==.Fiofio:BAABNQAECoEUAAIIAAcKIxeylgAPAgAIAAcKIxeylgAPAgAAAA==.Fizban:BAAANQAECgYIDAAAAA==.',
Fl='Flik:BAAANQAECgMJAwABNQAECgkJJQAOAGscAA==.',
Fo='Foringojr:BAAANQAECgIIAgAAAA==.',
Fr='Frigidheart:BAAANQAECgUIDAABNQAECgcIDwADAAAAAA==.',
['Fà']='Fàllén:BAAANQAECgEJAgABNQAECgcIDQADAAAAAA==.',
Ga='Gadogear:BAAANQAECgIIAwAAAA==.Galabren:BAAANQAECgYJDQAAAA==.Garlik:BAAANQADCgUIDQAAAA==.',
Gf='Gfr:BAAANQAECgIIBQAAAA==.',
Gi='Giddoo:BAAANQADCggICAAAAA==.Gilnean:BAAANQABCgEIAQAAAA==.',
Gn='Gnomeanator:BAAANQABCgIIAgAAAA==.',
Go='Goatcheeze:BAAANQAECgYIDAAAAA==.Gohlemsaurus:BAAANQADCggIEwAAAA==.',
Gu='Gulen:BAAANQADCggJGwAAAA==.Gullee:BAAANQABCgcIDgAAAA==.',
Gw='Gwennevier:BAAANQABCgYIDAAAAA==.',
['Gí']='Gíga:BAAANQAECgMIAwAAAA==.',
Ha='Halsten:BAAANQAECgUICQAAAA==.',
He='Hellenkeller:BAEANQAFFAEIAQABNQAFFAQIBwAJAAgXAA==.',
Hi='Hitt:BAAANQAECgMIBAAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.Hoofingit:BAAANQADCgQIBAAAAA==.',
Hr='Hroc:BAAANQAECgYIDAAAAA==.',
Ic='Icedlatte:BAAANQADCgQIBgAAAA==.Icywolfy:BAAANQAECgIIAgAAAA==.',
Ig='Igreetyou:BAAANQAECgMIAwAAAA==.',
Il='Illune:BAAANQAECgUICwABNQAECgcIFwAGAK8hAA==.',
Im='Imleapingit:BAAANQAECgUICwAAAA==.',
In='Intoodeep:BAABNQAECoEcAAISAAkKwQ83HQA+AgASAAkKwQ83HQA+AgAAAA==.',
Ir='Ir:BAABNQAECoEmAAIIAAkKHBnZTADCAgAIAAkKHBnZTADCAgAAAA==.Irrlvntgobbo:BAAANQAECgUICAAAAA==.',
Is='Isawarriorr:BAABNQAECoEbAAMFAAgKWxuTUgBRAgAFAAgKhRmTUgBRAgANAAIKDhvDJwCYAAAAAA==.Ishdo:BAAANQAECgYIDAAAAA==.Ishlok:BAAANQADCgUIBQABNQAECgYIDAADAAAAAA==.Ishwar:BAAANQADCgcIDAABNQAECgYIDAADAAAAAA==.',
Ja='Jakytreehorn:BAAANQAECgcIEQAAAA==.Jaydm:BAAANQAECgMIAwABNQAECgkJHAAIAM8YAA==.',
Je='Jenevelle:BAAANQAECgMJAwAAAA==.Jerisil:BAAANQADCgUICAAAAA==.Jessiel:BAAANQAECgQIBAAAAA==.Jet:BAABNQAECoEVAAIBAAgK5BI5agADAgABAAgK5BI5agADAgAAAA==.',
Ju='Julthaenia:BAAANQAECgYIEAABNQAECgkJIgACAEwjAA==.Junjia:BAAANQADCgUIBQAAAA==.',
Ka='Kagebushin:BAAANQABCgIIAgAAAA==.Kagome:BAAANQADCgQIBAABNQAECgEIAgADAAAAAA==.Kalofelement:BAAANQADCgEIAQAAAA==.Kalysy:BAAANQABCggICAABNQAECgkJIgACAEwjAA==.Karash:BAAANQAECgQIBwAAAA==.Karmaisab:BAAANQAECgEIAQAAAA==.Karnrae:BAAANQAECgYIEAAAAA==.Karynos:BAABNQAECoEZAAITAAgKPQ3dZQDVAQATAAgKPQ3dZQDVAQAAAA==.Katwolf:BAAANQAECgQICgAAAA==.Katyah:BAAANQAECgYIEwAAAA==.Kavourkaa:BAAANQABCggIFgAAAA==.',
Ke='Keynivas:BAAANQAECgIJAgAAAA==.',
Ki='Killiua:BAAANQAECgQIBAAAAA==.',
Ko='Konspiracy:BAAANQAECgUICQAAAA==.',
Kr='Kraguva:BAAANQAECgQIBAAAAA==.Krataar:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.Kroot:BAAANQAECgUICwABNQAECgcICwADAAAAAA==.Krous:BAACNQAFFIEFAAIFAAMKlw1zGADUAAAFAAMKlw1zGADUAAA1AAQKgR0AAgUACQrsHE06AKYCAAUACQrsHE06AKYCAAAA.Kryph:BAAANQAECgUJCwAAAA==.',
['Kä']='Kämpfer:BAAANQAECgMIBQABNQAECggIIQAUAFkSAA==.',
La='Lafiel:BAAANQAECgcIDQAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Laurandre:BAAANQAECgUICwAAAA==.',
Le='Letsgetwet:BAAANQADCgUIBQAAAA==.',
Li='Liefic:BAAANQAECgUIBwAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilstooge:BAAANQABCgYIBwABNQABCggIDgADAAAAAA==.',
Ll='Llylith:BAAANQABCgMIBAAAAA==.',
Lo='Locke:BAAANQAECgIIAgABNQAECggIFQABAOQSAA==.',
Lu='Luckykilla:BAABNQAECoEcAAISAAgKexTiJAD/AQASAAgKexTiJAD/AQAAAA==.Lucÿ:BAABNQAECoEjAAMHAAkKox7XFQDyAgAHAAkKox7XFQDyAgAVAAYKpxTlcAB4AQAAAA==.Lune:BAAANQADCgUICwAAAA==.Lurith:BAABNQAECoEdAAMKAAcKfhECYgAgAQAKAAUKlBQCYgAgAQARAAYKKQ3nYgAdAQAAAA==.Luxtyrannica:BAAANQAECgEJAQAAAA==.',
Ly='Lydrain:BAAANQADCgIJAwAAAA==.',
Ma='Marahh:BAAANQABCgIIAgAAAA==.Mattbolt:BAAANQAECgYIDgAAAA==.Maximoose:BAAANQAECgYICQABNQAECgcIDQADAAAAAA==.Mayu:BAAANQADCggIEwAAAA==.Mazigos:BAAANQAECgUJBQAAAA==.',
Me='Medjrab:BAABNQAECoEZAAIKAAgKXB6mGAC8AgAKAAgKXB6mGAC8AgAAAA==.Mefi:BAAANQADCgcIDAAAAA==.Melyria:BAAANQAECgcIEQAAAA==.Meristem:BAAANQAECgUICgAAAA==.Merko:BAAANQADCgEIAQABNQAECgcICwADAAAAAA==.',
Mi='Mignius:BAAANQADCgYIBgAAAA==.Mistified:BAAANQABCgIIBAAAAA==.',
Mo='Moedorai:BAAANQAECgYIDQAAAA==.Mogma:BAAANQAECgQJBAAAAA==.Momentomori:BAAANQADCgUICQAAAA==.Moonbounds:BAACNQAFFIENAAIHAAUKZxsYBQDUAQAHAAUKZxsYBQDUAQA1AAQKgSwAAgcACQqSIh0HAHADAAcACQqSIh0HAHADAAAA.Moondoggey:BAAANQADCgUIBQAAAA==.Morgana:BAAANQADCgUICAAAAA==.Mousechief:BAAANQAECgIIAwAAAA==.Moxxzi:BAAANQAECgYIEQAAAA==.',
Mu='Muhfookinbak:BAAANQAECgUICwAAAA==.Muvahmedicin:BAAANQADCgcIBwAAAA==.',
Na='Naksu:BAAANQADCgYJFgABNQAECgUIDAADAAAAAA==.Naksù:BAAANQADCgUIBQABNQAECgUIDAADAAAAAA==.Naksü:BAAANQAECgUIDAAAAA==.',
Ne='Neifeb:BAABNQAECoEYAAIEAAcKUA0BfAC3AQAEAAcKUA0BfAC3AQAAAA==.Nerfherder:BAAANQABCgcIDQABNQAECgcIGAALALcUAA==.',
Ni='Niallivdam:BAAANQADCggIEwAAAA==.Nights:BAAANQAECgIIAwABNQAFFAYIDAAJAOMQAA==.Ninh:BAABNQAECoEmAAIWAAkKVAUjHABmAQAWAAkKVAUjHABmAQAAAA==.Nintendopsp:BAAANQADCgUIBQAAAA==.Ninthgate:BAAANQAECgUIBwAAAA==.',
No='Noble:BAAANQAECgYICgAAAA==.Nogood:BAAANQAECgcIEQAAAA==.Northwest:BAAANQABCgYJBQAAAA==.Notsodemon:BAAANQAECgQICAABNQAECgYIEgADAAAAAA==.Notsomage:BAAANQAECgYIEgAAAA==.',
Ny='Nyorai:BAAANQABCgQIAwAAAA==.Nyxwing:BAAANQAECgQIBQAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAAANQAECgYIEgAAAA==.',
Od='Oddpocalypse:BAAANQADCgQIBAAAAA==.Odinheâthen:BAAANQADCgYJDAAAAA==.',
Ol='Olydwarf:BAAANQAECgEIAQAAAA==.',
On='Onebadmutha:BAAANQAECgUICwAAAA==.Ontop:BAABNQAECoEmAAIEAAkKURzGJADLAgAEAAkKURzGJADLAgAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAAANQAECgUIDAAAAA==.',
Ow='Owneege:BAACNQAFFIEJAAMLAAQKmRA2AgCPAAAFAAMKihVlFgDnAAALAAIKKgo2AgCPAAA1AAQKgSAAAwsACQqyIhkHADUCAAUACQquIUk0AL0CAAsABgpkIhkHADUCAAAA.',
Pa='Paapaa:BAAANQADCgcIBQAAAA==.Pallideaus:BAAANQAECgUICgAAAA==.Pallinar:BAAANQAECgUIBQAAAA==.Pasquale:BAAANQAECgQIBgAAAA==.',
Pe='Pebbles:BAABNQAECoEfAAIBAAgKOhRjaAAIAgABAAgKOhRjaAAIAgAAAA==.Pedorus:BAAANQABCgYIBwABNQAECgkJIwAHAKMeAA==.Penjerman:BAAANQADCggICAABNQAECggIHAAFAFYcAA==.',
Pi='Picklericky:BAAANQADCggIBAAAAA==.Pilgrimm:BAECNQAFFIEHAAIJAAQKCBdXBgBmAQAJAAQKCBdXBgBmAQA1AAQKgR8ABAkACQoQJWoCAIEDAAkACQoQJWoCAIEDABcAAQq5GwMWAE0AABIAAQpBC+9yAD0AAAAA.Pinxyl:BAAANQABCgcIBwAAAA==.Pistola:BAAANQAECgQIBAAAAA==.Pixyl:BAAANQADCggICQAAAA==.',
Pl='Plaguerott:BAABNQAECoEYAAIYAAcKtAf5RQApAQAYAAcKtAf5RQApAQAAAA==.Plaguewind:BAAANQADCgQIBQAAAA==.',
Po='Polydh:BAABNQAECoEfAAIZAAgKQSWRAQBjAwAZAAgKQSWRAQBjAwAAAA==.Poobah:BAAANQAECgUICwAAAA==.Popsicles:BAAANQAECgYIEAAAAA==.Potrat:BAAANQAECgMJAwAAAA==.Pouffant:BAAANQAECgQICQAAAA==.',
Pr='Praddagy:BAAANQADCgUJBQAAAA==.Pronoz:BAAANQAECggIBwAAAA==.',
Pu='Purpyl:BAAANQAECgUIBQAAAA==.',
Pw='Pwnageddon:BAAANQADCgcIEwAAAA==.Pwnjitsu:BAABNQAECoEZAAIaAAYKVxqfIQDAAQAaAAYKVxqfIQDAAQAAAA==.',
Py='Pyrothermia:BAABNQAECoEcAAMIAAkKzxgZYgCMAgAIAAkKzxgZYgCMAgAbAAMKOwc0JQCAAAAAAA==.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Rawhoof:BAABNQAECoEmAAIFAAkK1CCLGwArAwAFAAkK1CCLGwArAwAAAA==.Razak:BAABNQAECoEhAAIMAAgKPCE9BQAaAwAMAAgKPCE9BQAaAwAAAA==.',
Rd='Rdnckromeo:BAAANQAECgQIBAAAAA==.',
Re='Redlock:BAAANQAECgUICgAAAA==.Redrum:BAABNQAECoEfAAIRAAgKkCPMDgAUAwARAAgKkCPMDgAUAwAAAA==.Renarin:BAABNQAECoElAAIOAAkKaxxeGQDgAgAOAAkKaxxeGQDgAgAAAA==.Renisa:BAAANQAECgYIDgAAAA==.Renobagem:BAAANQADCgEIAQAAAA==.Retman:BAAANQADCggIDgAAAA==.Reu:BAAANQADCggJCAAAAA==.Revlyk:BAAANQAECgYIEgABNQAECgkJIgACAEwjAA==.',
Rh='Rhoanna:BAAANQADCgcICgAAAA==.Rhoupert:BAAANQAECgUIBwABNQAECgYIEwADAAAAAA==.',
Ro='Roccot:BAABNQAECoEWAAIRAAcK5xb/OQDdAQARAAcK5xb/OQDdAQAAAA==.Rotjaw:BAAANQADCggIDAAAAA==.Roughedge:BAAANQADCgIIAgAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQABCgYIDAAAAA==.',
Sc='Scalycat:BAAANQAECgQJCgAAAA==.Schuey:BAAANQADCggICAAAAA==.Scum:BAAANQADCgcIDQAAAA==.',
Se='Senaeda:BAAANQADCgQIBwAAAA==.Senate:BAABNQAECoEXAAMVAAcKmA+bXwCwAQAVAAcKmA+bXwCwAQAHAAEKqgH4+AAjAAAAAA==.',
Sh='Shaamazing:BAAANQABCgIIAgAAAA==.Shablaam:BAAANQADCggIEQAAAA==.Shadowbear:BAAANQAECgEIAgAAAA==.Sherrilyn:BAAANQADCgYICAAAAA==.Shocktherapi:BAAANQAECgEIAQAAAA==.Shrimpback:BAAANQAECgEIAQAAAA==.',
Si='Singularity:BAAANQAECgQJBQAAAA==.',
Sk='Skelli:BAECNQAFFIEJAAIOAAQKJRRNDQBZAQAOAAQKJRRNDQBZAQA1AAQKgRUAAg4ACQqSGqkpAIUCAA4ACQqSGqkpAIUCAAE1AAQKBwgMAAMAAAAA.Skittlesdan:BAAANQAECgYIEAAAAA==.',
Sl='Slaykween:BAAANQAECgUICQAAAA==.',
Sm='Smallz:BAAANQADCgYICwABNQAECgYIDAADAAAAAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAABNQAECoEYAAQLAAcKtxQ+DQCSAQALAAYKyhU+DQCSAQAFAAYKZguYqABOAQANAAEKMhq8MABCAAAAAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Steakhaus:BAAANQAECgIIAgAAAA==.Stonedragon:BAECNQAFFIEFAAIEAAIKbxewEgC7AAAEAAIKbxewEgC7AAA1AAQKgTQAAgQACQrVI9EEAKYDAAQACQrVI9EEAKYDAAAA.Stormfist:BAAANQADCgQIBgAAAA==.Stormhaven:BAAANQADCgQJBAABNQAECgEIAQADAAAAAA==.Stormrender:BAAANQAECgUICQAAAA==.Stormriders:BAAANQAECgUIDwAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Streea:BAAANQADCggIEwABNQAECgYICgADAAAAAA==.Stubz:BAAANQABCgQIBgAAAA==.',
Su='Sugi:BAAANQABCgIIAgABNQAECgkJJAAQAPkcAA==.Sukonamí:BAAANQAECgcIDQAAAA==.Suzhou:BAAANQAECgUIBAAAAA==.Suzoomies:BAAANQADCggIDwAAAA==.',
Sw='Swisscheese:BAAANQAECgYIEQAAAA==.Swoopyboop:BAAANQADCgQIBAAAAA==.',
Sy='Sybaek:BAAANQAECgEIAQAAAA==.Sycò:BAABNQAECoEYAAMEAAkKYx/IHwDhAgAEAAgKHiPIHwDhAgAcAAEKkQHceAAjAAAAAA==.Syraxa:BAAANQAECgEIAQAAAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAQABNQAECgkJJAAEAN8eAA==.',
Ta='Taedish:BAAANQADCgQIBAAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.Tannith:BAAANQABCgUIDAABNQABCggIDgADAAAAAA==.Tayy:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Telan:BAAANQADCgUIBQAAAA==.Tempertotems:BAAANQADCggICAAAAA==.Tenastin:BAAANQADCgQIBAAAAA==.Terragosa:BAAANQAECgUICgAAAA==.Tetchybono:BAAANQAECgIIAgAAAA==.Tettra:BAAANQABCgEIAQABNQAECgYICgADAAAAAA==.',
Th='Thahawtz:BAAANQADCgYJDAAAAA==.Thirinis:BAAANQAECgEJAQAAAA==.Thope:BAAANQADCgYIFgAAAA==.Thundergirl:BAAANQADCgYIDAAAAA==.',
Tr='Traesdyne:BAAANQADCgMIBAAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECgcIDAADAAAAAA==.Trainar:BAAANQAECgQIBwABNQAECgYIDgADAAAAAA==.Triggs:BAAANQABCgIIAgAAAA==.Troggdor:BAAANQABCggIDQABNQAECgcIGAALALcUAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAAANQAECgIIAgAAAA==.Trõnlight:BAAANQADCgYIBgAAAA==.',
Ts='Tsunah:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQAECgEIAQAAAA==.Turim:BAAANQADCggIFgAAAA==.',
Ty='Tyrawick:BAAANQADCgUIBQAAAA==.Tyrlidd:BAAANQAECgUICgAAAA==.',
Un='Unavoidable:BAAANQADCgMJAwAAAA==.Unlikelytale:BAABNQAECoEaAAIHAAgK7RslLQBtAgAHAAgK7RslLQBtAgAAAA==.',
Ur='Urbanmeyer:BAAANQADCggIDwAAAA==.Uricash:BAABNQAECoEhAAIIAAgKCx7CVQCrAgAIAAgKCx7CVQCrAgAAAA==.Urzual:BAABNQAECoEYAAMMAAcKzBn4DgA4AgAMAAcKzBn4DgA4AgAHAAYKbhRYZgCDAQAAAA==.',
Va='Vandreynna:BAABNQAECoEiAAICAAkKTCMwBgB1AwACAAkKTCMwBgB1AwAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velsiana:BAAANQAECgMIAwAAAA==.Velveetah:BAAANQADCgYIBwABNQAECgUIDwADAAAAAA==.Verbrennen:BAABNQAECoEhAAIUAAgKWRIBGAADAgAUAAgKWRIBGAADAgAAAA==.Verita:BAAANQAECgQIBgAAAA==.Verlynne:BAAANQADCgcIBwAAAA==.',
Vi='Viviann:BAABNQAECoEUAAIUAAcKjAmKIgBtAQAUAAcKjAmKIgBtAQAAAA==.',
Wa='Walee:BAAANQADCgIJAgAAAA==.Walfred:BAAANQAECgMIAwABNQAECgcIHQAKAH4RAA==.Warraxe:BAAANQADCgYIBgAAAA==.Wayloren:BAAANQAECgYIEwAAAA==.Wayverly:BAAANQABCgUIBwABNQAECgEIAgADAAAAAA==.',
We='Wetboycaird:BAAANQADCgMIAwAAAA==.',
Wi='Wickathy:BAAANQAECgcIEAAAAA==.Wickcreu:BAAANQAECgIIAgAAAA==.',
Wo='Worstdps:BAABNQAECoEhAAICAAgKYRULKAAMAgACAAgKYRULKAAMAgAAAA==.',
Wu='Wuldorr:BAAANQAECggIEgAAAA==.',
Wy='Wynnifred:BAAANQAECgIIBQAAAA==.',
Xa='Xaltheris:BAAANQAECgEJAQAAAA==.',
Xe='Xethreal:BAAANQAECgUICgAAAA==.',
Xy='Xype:BAAANQAECggICAAAAA==.',
Xz='Xzara:BAAANQAECgYICgAAAA==.',
Yu='Yura:BAAANQADCggICAAAAA==.',
Yv='Yvvee:BAAANQAECgMIAwAAAA==.',
Za='Zapbranigan:BAAANQADCggICwAAAA==.',
Zi='Zifao:BAABNQAECoEYAAIIAAgKmx/aRwDQAgAIAAgKmx/aRwDQAgAAAA==.',
Zo='Zonora:BAAANQAECgcIEgAAAA==.',
['Äz']='Äzrael:BAAANQAECgcIDQAAAA==.',
['Çr']='Çréwüsæðèr:BAAANQAECgUICwAAAA==.',
['Ðì']='Ðìaßlo:BAABNQAECoEkAAIEAAkK3x6mGwD2AgAEAAkK3x6mGwD2AgAAAA==.',
['Òd']='Òdinn:BAAANQADCgcIBwAAAA==.',
['Ød']='Ødin:BAAANQADCgYIDAABNQAECgEIAQADAAAAAA==.',
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
