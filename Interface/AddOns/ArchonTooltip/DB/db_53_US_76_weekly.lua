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

local lookup = {'DemonHunter-Havoc','Hunter-BeastMastery','Unknown-Unknown','Warrior-Arms','Paladin-Protection','Shaman-Restoration','Mage-Arcane','Rogue-Subtlety','Paladin-Retribution','DeathKnight-Unholy','Warrior-Fury','DemonHunter-Devourer','DeathKnight-Blood','Priest-Holy','Rogue-Assassination','Evoker-Preservation','Shaman-Elemental','Monk-Mistweaver','Rogue-Outlaw','Mage-Frost','Shaman-Enhancement','Hunter-Marksmanship','Druid-Restoration',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Aberaht:BAAANQAECgYIDQAAAA==.Absolution:BAAANQAECgMJBQAAAA==.',
Ac='Ackianae:BAAANQAECgYIEAAAAA==.',
Ad='Adewey:BAAANQAECgIIBQAAAA==.',
Ae='Aenastian:BAAANQADCgUIDwABNQAECgkJGgABAKwgAA==.',
Ak='Akhalla:BAAANQAECgQIBAAAAA==.Akre:BAAANQADCgcJBwAAAQ==.Akumä:BAAANQADCgcIEQAAAA==.',
Al='Aleannia:BAAANQADCggICAAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAAANQAECgYICQAAAA==.Algodón:BAAANQADCgEIAgABNQAECgkJHgACAFAgAA==.Alibrexia:BAAANQAECgYJBwAAAA==.Allus:BAAANQABCgUJCQAAAA==.Alphaomega:BAAANQADCggIGQAAAA==.',
An='Anarcy:BAAANQADCgQIBgAAAA==.Anastaysha:BAAANQABCgQIBAABNQAECgEIAQADAAAAAA==.Ankan:BAAANQAECgQIBQABNQAECgkJGgABAKwgAA==.',
Ar='Arcticplague:BAAANQADCgEIAQAAAA==.Ardatha:BAAANQADCgIIAgAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.Arlor:BAAANQADCgYIDAAAAA==.',
As='Astrocakes:BAAANQADCgYICgABNQAECggIGgAEAKUbAA==.',
At='Athenä:BAACNQAFFIEFAAIFAAQKGgljAwAFAQAFAAQKGgljAwAFAQA1AAQKgRcAAgUACAqIFdUTAN4BAAUACAqIFdUTAN4BAAAA.Atsuma:BAAANQADCggICAAAAA==.Atthel:BAAANQAECgMIBAAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgYICgADAAAAAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAAANQAECgEJAQAAAA==.',
Ba='Baela:BAAANQAECgMIAwABNQAFFAQICAAGALggAA==.Baelthemar:BAAANQADCgUIBQAAAA==.Bajafresh:BAAANQADCgMIAwAAAA==.Battleshaman:BAAANQABCgMIAgAAAA==.',
Be='Benjinana:BAAANQAECgQICgAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Boricua:BAAANQAECgIIAgAAAA==.Bountty:BAAANQADCgYIBgAAAA==.',
Br='Brightbane:BAAANQAECgEIAQAAAA==.',
Bu='Buddie:BAAANQADCggICAAAAA==.Buffaloseven:BAAANQAECgIIAgABNQAECgkJGQAHAGEXAA==.Bulleitrye:BAAANQADCgYIBgAAAA==.',
By='Byorn:BAAANQAECgYIBwAAAA==.',
Ca='Cairdamane:BAAANQAECgYIEAAAAA==.Calidrina:BAAANQAECgYICAAAAA==.',
Ce='Celldrassil:BAAANQADCggIEgAAAA==.Cereel:BAAANQAECgQJBQABNQAECggIGgAEAKUbAA==.',
Ch='Chardaney:BAAANQAECgEIAQAAAA==.',
Ci='Cii:BAAANQAECgUJCwAAAA==.Ciine:BAAANQADCgYIBgABNQAECgUJCwADAAAAAA==.Ciruzita:BAAANQADCgUIBQAAAA==.',
Cl='Clampz:BAEANQAECgQIBQABNQAFFAQJBAAIAD0TAA==.',
Co='Colandros:BAAANQADCgEJAQAAAA==.Colara:BAAANQAECgEIAgAAAA==.Colbear:BAAANQABCgUICQAAAA==.Coldspace:BAABNQAECoEYAAIJAAgKORozOABzAgAJAAgKORozOABzAgAAAA==.',
Cr='Crassberry:BAACNQAFFIEHAAIKAAQKohV7AwBlAQAKAAQKohV7AwBlAQA1AAQKgRwAAgoACQrMI6UJAEgDAAoACQrMI6UJAEgDAAAA.Creepindeath:BAAANQAECgEJAgAAAA==.',
Cu='Cucaracha:BAAANQAECgUJBQAAAA==.',
Cy='Cyndal:BAAANQADCgcICwABNQAECgYICgADAAAAAA==.Cyndle:BAAANQADCgYIBgABNQAECgYICgADAAAAAA==.Cyntu:BAAANQADCgcICwABNQAECgYICgADAAAAAA==.',
Da='Dankbuds:BAAANQADCgEJAQAAAA==.Dankothy:BAAANQADCggJHAABNQADCgEJAQADAAAAAA==.Dantes:BAAANQAECgEJAQAAAA==.Darkryu:BAAANQADCgYIEAAAAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQADCgYIHAAAAA==.',
De='Deathforever:BAAANQADCgYICgAAAA==.Deaus:BAAANQADCggIFQAAAA==.Delrus:BAAANQAECgYIDgAAAA==.Demon:BAAANQAECgcIEgABNQAECgkJHAAIACAcAA==.Denzvic:BAAANQAECgQJBAAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Diddyjr:BAAANQAECggIEwAAAA==.Disowneege:BAAANQAECgQIBAABNQAFFAQIBgALAJkPAA==.',
Do='Doodu:BAAANQAFFAEIAQAAAA==.',
Dr='Dragnas:BAAANQAECgYJEwAAAA==.Drakass:BAAANQADCggICAAAAA==.Dramakiller:BAAANQADCgcJGwAAAA==.Drcornbread:BAAANQAECgQICgAAAA==.Drcornellia:BAAANQADCgYIBwABNQAECgQICgADAAAAAA==.Drdreggs:BAAANQAECgYJBwAAAA==.Drop:BAAANQADCgQIBAABNQAECgYIDQADAAAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgEJAwADAAAAAA==.Dustyhunter:BAAANQADCgQIBAAAAA==.',
Ea='Eatbuttforpi:BAAANQADCgMIAwABNQAECggIGgAEAKUbAA==.',
El='Elastar:BAAANQAECgYIDQAAAA==.Ellimist:BAEANQAECgcIDAAAAA==.Elsan:BAAANQADCgQIBAAAAA==.Elycee:BAAANQAECgcICgAAAA==.',
En='Enveliria:BAAANQAECgUJCQABNQAECgkJGgABAKwgAA==.',
Er='Eraser:BAAANQAECgYIEwAAAA==.Erazar:BAAANQAECgQIBAAAAA==.Erickk:BAAANQAECggIEgAAAA==.Eristela:BAAANQADCgQICAAAAA==.',
Es='Escanorlion:BAAANQAECgQIBgAAAA==.Essense:BAAANQAECgYIDQAAAA==.',
Ev='Evokedcat:BAAANQAECgcJCAAAAA==.',
Ex='Exodari:BAAANQAECgYJEQAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgIJAgABNQAECggIGgAEAKUbAA==.Fatalgrip:BAAANQADCgUIBQAAAA==.',
Fe='Fel:BAABNQAECoEcAAMBAAgKmyHkCwAFAwABAAgKmyHkCwAFAwAMAAcKyxQOJADRAQAAAA==.Fellkarras:BAAANQAECgEJAQABNQAECggJGAANAFQiAA==.',
Fi='Fibitz:BAAANQAECgcJCwAAAA==.Findstewie:BAAANQABCgYICAABNQABCgYIBgADAAAAAA==.Fiofio:BAAANQAECgYIDQAAAA==.Fizban:BAAANQAECgYICQAAAA==.',
Fl='Flik:BAAANQAECgMJAwABNQAECggJHAAOAKseAA==.',
Fo='Foringojr:BAAANQAECgIIAgAAAA==.',
Fr='Frigidheart:BAAANQAECgUIDAABNQAECgcIDQADAAAAAA==.',
['Fà']='Fàllén:BAAANQAECgEJAgABNQAECgYIBwADAAAAAA==.',
Ga='Gadogear:BAAANQAECgIJAwAAAA==.Galabren:BAAANQAECgYJDQAAAA==.Garlik:BAAANQADCgUICAAAAA==.',
Gf='Gfr:BAAANQAECgIJAwAAAA==.',
Gi='Gilnean:BAAANQABCgEIAQAAAA==.',
Go='Goatcheeze:BAAANQAECgQICQAAAA==.Gohlemsaurus:BAAANQADCgYJCgAAAA==.',
Gu='Gulen:BAAANQADCggJGwAAAA==.Gullee:BAAANQABCgcIDgAAAA==.',
Gw='Gwennevier:BAAANQABCgYJCgAAAA==.',
['Gí']='Gíga:BAAANQAECgMIAwAAAA==.',
Ha='Halsten:BAAANQAECgQJBAAAAA==.',
He='Hellenkeller:BAEANQAFFAEIAQABNQAFFAQJBAAIAD0TAA==.',
Hi='Hitt:BAAANQAECgEIAQAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.',
Hr='Hroc:BAAANQAECgYIDAAAAA==.',
Ic='Icedlatte:BAAANQADCgIJAgAAAA==.Icywolfy:BAAANQAECgIIAgAAAA==.',
Ig='Igreetyou:BAAANQADCgYICgAAAA==.',
Il='Illune:BAAANQAECgIIAgABNQAECgUJDgADAAAAAA==.',
Im='Imleapingit:BAAANQAECgQJBgAAAA==.',
In='Intoodeep:BAABNQAECoEaAAIPAAgKQA/fGgASAgAPAAgKQA/fGgASAgAAAA==.',
Ir='Ir:BAABNQAECoEdAAIHAAgKIhkCXwBxAgAHAAgKIhkCXwBxAgAAAA==.Irrlvntgobbo:BAAANQAECgMIAwAAAA==.',
Is='Isawarriorr:BAAANQAECgcJEwAAAA==.Ishdo:BAAANQAECgYICQAAAA==.Ishlok:BAAANQADCgUIBQABNQAECgYICQADAAAAAA==.Ishwar:BAAANQADCgYIBgABNQAECgYICQADAAAAAA==.',
Ja='Jakytreehorn:BAAANQAECgcIEQAAAA==.',
Je='Jenevelle:BAAANQAECgMJAwAAAA==.Jerisil:BAAANQADCgUICAAAAA==.Jessiel:BAAANQAECgQIBAAAAA==.Jet:BAAANQAECgYIDQAAAA==.',
Ju='Julthaenia:BAAANQAECgUJCgABNQAECgkJGgABAKwgAA==.Junjia:BAAANQADCgUIBQAAAA==.',
Ka='Kagebushin:BAAANQABCgIIAgAAAA==.Kagome:BAAANQADCgQIBAABNQAECgEIAQADAAAAAA==.Kalofelement:BAAANQADCgEIAQAAAA==.Karash:BAAANQAECgEJAwAAAA==.Karmaisab:BAAANQADCggIBgAAAA==.Karnrae:BAAANQAECgYJCgAAAA==.Karynos:BAAANQAECgYJDwAAAA==.Katwolf:BAAANQAECgMIBgAAAA==.Katyah:BAAANQAECgYJDgAAAA==.Kavourkaa:BAAANQABCggJDwAAAA==.',
Ke='Keynivas:BAAANQAECgIJAgAAAA==.',
Ko='Konspiracy:BAAANQAECgQICAAAAA==.',
Kr='Kraguva:BAAANQAECgQIBAAAAA==.Krataar:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.Kroot:BAAANQAECgQJBgABNQAECgcJCwADAAAAAA==.Krous:BAABNQAECoEaAAIEAAkKuhxgMgCfAgAEAAkKuhxgMgCfAgAAAA==.Kryph:BAAANQAECgUJCwAAAA==.',
['Kä']='Kämpfer:BAAANQAECgIIAgABNQAECgcIGQAQALETAA==.',
La='Lafiel:BAAANQAECgUIBgAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Laurandre:BAAANQAECgQIBgAAAA==.',
Le='Letsgetwet:BAAANQADCgUIBQAAAA==.',
Li='Liefic:BAAANQAECgIIAgAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilstooge:BAAANQABCgYIBwABNQABCgYIBgADAAAAAA==.',
Ll='Llylith:BAAANQABCgMIBAAAAA==.',
Lu='Luckykilla:BAAANQAECgYJEAAAAA==.Lucÿ:BAABNQAECoEfAAMGAAkKzR1YEAAFAwAGAAkKzR1YEAAFAwARAAYKpxTwWwCFAQAAAA==.Lune:BAAANQADCgUICwAAAA==.Lurith:BAABNQAECoEXAAMKAAYK9xFqWwAIAQAKAAQKEBZqWwAIAQANAAUKhA0HYQDsAAAAAA==.Luxtyrannica:BAAANQAECgEJAQAAAA==.',
Ly='Lydrain:BAAANQADCgIJAwAAAA==.',
Ma='Marahh:BAAANQABCgIIAgAAAA==.Mattbolt:BAAANQAECgYIBwAAAA==.Maximoose:BAAANQAECgYIBwABNQAECgYIBwADAAAAAA==.Mayu:BAAANQADCggIEgAAAA==.Mazigos:BAAANQAECgUJBQAAAA==.',
Me='Medjrab:BAAANQAECgQICAAAAA==.Mefi:BAAANQADCgUIBQAAAA==.Melyria:BAAANQAECgYJCwAAAA==.Meristem:BAAANQAECgUJBQAAAA==.Merko:BAAANQADCgEIAQABNQAECgcJCwADAAAAAA==.',
Mi='Miau:BAAANQAECgQIBAAAAA==.Mignius:BAAANQADCgYIBgAAAA==.Mistified:BAAANQABCgIIBAAAAA==.',
Mo='Moedorai:BAAANQAECgYJCgAAAA==.Mogma:BAAANQAECgQJBAAAAA==.Momentomori:BAAANQADCgUIBQAAAA==.Moonbounds:BAACNQAFFIEIAAIGAAUKUhYvBACwAQAGAAUKUhYvBACwAQA1AAQKgSQAAgYACQphIe0HAFgDAAYACQphIe0HAFgDAAAA.Moondoggey:BAAANQADCgUIBQAAAA==.Morgana:BAAANQADCgUICAAAAA==.Mousechief:BAAANQAECgEJAQAAAA==.Moxxzi:BAAANQAECgUICwAAAA==.',
Mu='Muhfookinbak:BAAANQAECgQJBgAAAA==.',
Na='Naksu:BAAANQADCgYJFgABNQAECgQIBwADAAAAAA==.Naksù:BAAANQADCgUIBQABNQAECgQIBwADAAAAAA==.Naksü:BAAANQAECgQIBwAAAA==.',
Ne='Neifeb:BAAANQAECgYJDgAAAA==.Nerfherder:BAAANQABCgcIDAABNQAECgYJDgADAAAAAA==.',
Ni='Niallivdam:BAAANQADCggIDQAAAA==.Nights:BAAANQAECgIIAwABNQAECgkJHAAIACAcAA==.Ninh:BAABNQAECoEdAAISAAgKTQTDGwA/AQASAAgKTQTDGwA/AQAAAA==.Ninthgate:BAAANQAECgEIAQAAAA==.',
No='Nogood:BAAANQAECgcIEAAAAA==.Northwest:BAAANQABCgYJBQAAAA==.Notsodemon:BAAANQAECgQICAABNQAECgYIEAADAAAAAA==.Notsomage:BAAANQAECgYIEAAAAA==.',
Ny='Nyorai:BAAANQABCgQIAwAAAA==.Nyxwing:BAAANQAECgEIAQAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAAANQAECgUJDAAAAA==.',
Od='Oddpocalypse:BAAANQADCgQIBAAAAA==.Odinheâthen:BAAANQADCgYJDAAAAA==.',
Ol='Olydwarf:BAAANQAECgEIAQAAAA==.',
On='Onebadmutha:BAAANQAECgQJBgAAAA==.Ontop:BAABNQAECoEdAAICAAgKphsQLQB/AgACAAgKphsQLQB/AgAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAAANQAECgUIBwAAAA==.',
Ow='Owneege:BAACNQAFFIEGAAMLAAQKmQ94AQCPAAAEAAMKNRSTEADkAAALAAIKKgp4AQCPAAA1AAQKgR0AAwQACQooIlMlAN0CAAQACQquIVMlAN0CAAsABQoRIpgIANEBAAAA.',
Pa='Paapaa:BAAANQADCgcIBQAAAA==.Pallideaus:BAAANQAECgUJBQAAAA==.Pallinar:BAAANQADCggIEwAAAA==.Pasquale:BAAANQAECgQIBQAAAA==.',
Pe='Pebbles:BAAANQAECgcIEwAAAA==.Pedorus:BAAANQABCgYIBwABNQAECgkJHwAGAM0dAA==.',
Pi='Picklericky:BAAANQADCgQJBAAAAA==.Pilgrimm:BAECNQAFFIEEAAIIAAMKPRNrBgAJAQAIAAMKPRNrBgAJAQA1AAQKgRwABAgACQofJNECAGsDAAgACQofJNECAGsDABMAAQq5GxYUAFEAAA8AAQpBCyxcAEEAAAAA.Pistola:BAAANQAECgQIBAAAAA==.Pixyl:BAAANQABCggICAAAAA==.',
Pl='Plaguerott:BAAANQAECgYJEQAAAA==.Plaguewind:BAAANQADCgMIBAAAAA==.',
Po='Polydh:BAAANQAECgcIEwAAAA==.Poobah:BAAANQAECgQJBwAAAA==.Popsicles:BAAANQAECgYIEAAAAA==.Potrat:BAAANQAECgMJAwAAAA==.Pouffant:BAAANQAECgQICQAAAA==.',
Pr='Praddagy:BAAANQADCgUJBQAAAA==.Pronoz:BAAANQADCggIBwAAAA==.',
Pu='Purpyl:BAAANQADCggIIQABNQAECgQIBAADAAAAAA==.',
Pw='Pwnageddon:BAAANQADCgcJEwAAAA==.Pwnjitsu:BAAANQAECgUIEQAAAA==.',
Py='Pyrothermia:BAABNQAECoEZAAMHAAkKYRceUwCSAgAHAAkKYRceUwCSAgAUAAMKOwdjHgCIAAAAAA==.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Rawhoof:BAABNQAECoEdAAIEAAgKvx8vLAC7AgAEAAgKvx8vLAC7AgAAAA==.Razak:BAABNQAECoEaAAIVAAgKFBruBwCvAgAVAAgKFBruBwCvAgAAAA==.',
Rd='Rdnckromeo:BAAANQAECgQIBAAAAA==.',
Re='Redlock:BAAANQAECgUJBQAAAA==.Redrum:BAABNQAECoEYAAINAAgKVCI5DQAMAwANAAgKVCI5DQAMAwAAAA==.Renarin:BAABNQAECoEcAAIOAAgKqx5sGwCtAgAOAAgKqx5sGwCtAgAAAA==.Renisa:BAAANQAECgUICQAAAA==.Retman:BAAANQADCggIDgAAAA==.Reu:BAAANQADCggJCAAAAA==.Revlyk:BAAANQAECgQJDAABNQAECgkJGgABAKwgAA==.',
Rh='Rhoanna:BAAANQADCgQIBAAAAA==.Rhoupert:BAAANQAECgIIAgABNQAECgYJDgADAAAAAA==.',
Ro='Roccot:BAAANQAECgYIDwAAAA==.Rotjaw:BAAANQADCggIDAAAAA==.Roughedge:BAAANQADCgIIAgAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQABCgYIDAAAAA==.',
Sc='Scalycat:BAAANQAECgQJCgAAAA==.Schuey:BAAANQADCggICAAAAA==.Scum:BAAANQADCgcIDQAAAA==.',
Se='Senaeda:BAAANQADCgQIBwAAAA==.Senate:BAAANQAECgYIEAAAAA==.',
Sh='Shaamazing:BAAANQABCgIIAgAAAA==.Shablaam:BAAANQADCggJCQAAAA==.Shadowbear:BAAANQAECgEJAQAAAA==.Sherrilyn:BAAANQADCgIIAgAAAA==.Shocktherapi:BAAANQAECgEIAQAAAA==.Shrimpback:BAAANQAECgEIAQAAAA==.',
Si='Singularity:BAAANQAECgQJBQAAAA==.',
Sk='Skelli:BAEBNQAFFIEGAAIOAAQKrQ9yCQBSAQAOAAQKrQ9yCQBSAQABNQAECgcIDAADAAAAAA==.Skittlesdan:BAAANQAECgYIEAAAAA==.',
Sl='Slaykween:BAAANQAECgQIBAAAAA==.',
Sm='Smallz:BAAANQADCgYICwABNQAECgYICQADAAAAAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAAANQAECgYJDgAAAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Stonedragon:BAEBNQAECoEpAAICAAkKjiMKBAClAwACAAkKjiMKBAClAwAAAA==.Stormfist:BAAANQADCgIIAgAAAA==.Stormhaven:BAAANQADCgQJBAABNQAECgEJAQADAAAAAA==.Stormrender:BAAANQAECgUJBQAAAA==.Stormriders:BAAANQAECgQICgAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Streea:BAAANQADCggJDAABNQAECgYICgADAAAAAA==.Stubz:BAAANQABCgQIBgAAAA==.',
Su='Sukonamí:BAAANQAECgYICgAAAA==.Suzhou:BAAANQADCggIEwAAAA==.Suzoomies:BAAANQADCggIDwAAAA==.',
Sw='Swisscheese:BAAANQAECgYIDQAAAA==.Swoopyboop:BAAANQADCgQIBAAAAA==.',
Sy='Sycò:BAABNQAECoEXAAMCAAkKYx9wFAABAwACAAgKHiNwFAABAwAWAAEKkQGBZgAlAAAAAA==.Syraxa:BAAANQADCgcIDQABNQAECggJGQAXAKoaAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAQABNQAECggIHAACAK4eAA==.',
Ta='Taedish:BAAANQADCgQIBAAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.Tannith:BAAANQABCgUICgABNQABCgYIBgADAAAAAA==.Tayy:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Tempertotems:BAAANQADCggICAAAAA==.Tenastin:BAAANQADCgQIBAAAAA==.Terragosa:BAAANQAECgUJBQAAAA==.Tetchybono:BAAANQAECgIIAgAAAA==.Tettra:BAAANQABCgEIAQABNQAECgYICgADAAAAAA==.',
Th='Thahawtz:BAAANQADCgYJDAAAAA==.Thirinis:BAAANQAECgEJAQAAAA==.Thope:BAAANQADCgYIFgAAAA==.Thundergirl:BAAANQADCgYIDAAAAA==.',
Tr='Traesdyne:BAAANQADCgMIBAAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECgYICQADAAAAAA==.Trainar:BAAANQAECgIJAwABNQAECgYICgADAAAAAA==.Triggs:BAAANQABCgIIAgAAAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAAANQADCgcIGwAAAA==.Trõnlight:BAAANQADCgYIBgAAAA==.',
Ts='Tsunah:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQAECgEIAQAAAA==.Turim:BAAANQADCggIFgAAAA==.',
Ty='Tyrawick:BAAANQADCgUIBQAAAA==.Tyrlidd:BAAANQAECgUJBQAAAA==.',
Un='Unavoidable:BAAANQADCgMJAwAAAA==.Unlikelytale:BAAANQAECgYIEQAAAA==.',
Ur='Urbanmeyer:BAAANQADCgcIBwAAAA==.Uricash:BAABNQAECoEaAAIHAAgKxRzdUQCWAgAHAAgKxRzdUQCWAgAAAA==.Urzual:BAAANQAECgYJDgAAAA==.',
Va='Vandreynna:BAABNQAECoEaAAIBAAkKrCDRCAA1AwABAAkKrCDRCAA1AwAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velsiana:BAAANQAECgMIAwAAAA==.Velveetah:BAAANQADCgYIBwABNQAECgQICgADAAAAAA==.Verbrennen:BAABNQAECoEZAAIQAAcKsRMFGADMAQAQAAcKsRMFGADMAQAAAA==.Verita:BAAANQAECgQIBAAAAA==.',
Vi='Viviann:BAAANQAECgYIDQAAAA==.',
Wa='Walee:BAAANQADCgIJAgAAAA==.Walfred:BAAANQAECgMIAwABNQAECgYIFwAKAPcRAA==.Warraxe:BAAANQADCgYJBgAAAA==.Wayloren:BAAANQAECgYJDQAAAA==.Wayverly:BAAANQABCgUIBwABNQAECgEIAQADAAAAAA==.',
Wi='Wickathy:BAAANQAECgcICQAAAA==.Wickcreu:BAAANQADCggJDQAAAA==.',
Wo='Worstdps:BAABNQAECoEaAAIBAAgKURQVHwAkAgABAAgKURQVHwAkAgAAAA==.',
Wu='Wuldorr:BAAANQAECggIEQAAAA==.',
Wy='Wynnifred:BAAANQAECgIJBQAAAA==.',
Xa='Xaltheris:BAAANQAECgEJAQAAAA==.',
Xe='Xethreal:BAAANQAECgUJBQAAAA==.',
Xz='Xzara:BAAANQAECgYICgAAAA==.',
Yv='Yvvee:BAAANQAECgMIAwAAAA==.',
Za='Zapbranigan:BAAANQADCggICAAAAA==.',
Zi='Zifao:BAAANQAECgcJDgAAAA==.',
Zo='Zonora:BAAANQAECgcJDQAAAA==.',
['Äz']='Äzrael:BAAANQAECgYICQAAAA==.',
['Çr']='Çréwüsæðèr:BAAANQAECgQJBwAAAA==.',
['Ðì']='Ðìaßlo:BAABNQAECoEcAAICAAgKrh7xIQCyAgACAAgKrh7xIQCyAgAAAA==.',
['Ød']='Ødin:BAAANQADCgYJBgABNQAECgEJAQADAAAAAA==.',
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
