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

local lookup = {'Paladin-Retribution','Shaman-Enhancement','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','Hunter-BeastMastery','Paladin-Holy','Warrior-Arms','Paladin-Protection','Priest-Holy','Shaman-Restoration','Warlock-Affliction','Mage-Arcane','DeathKnight-Blood','DeathKnight-Frost','Shaman-Elemental','DemonHunter-Devourer','Rogue-Subtlety','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Hunter-Marksmanship','Priest-Shadow','Mage-Frost','Druid-Feral','Rogue-Assassination','Evoker-Preservation','Monk-Mistweaver','Rogue-Outlaw','Druid-Guardian','DemonHunter-Vengeance','Priest-Discipline','Monk-Windwalker','Evoker-Devastation',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Aberaht:BAABNQAECn8oAAIBAAkKjx9oDAAfAgABAAkKjx9oDAAfAgAAAA==.Abercrombie:BAAANQABCgYICAAAAA==.Absolution:BAABNQAECn8WAAICAAgKUQn4EQDlAAACAAgKUQn4EQDlAAAAAA==.',
Ac='Ackianae:BAAANQAECgYIEAAAAA==.',
Ad='Adenwey:BAAANQAECgUICAABNQAECgoKMwADAKQgAA==.Adewey:BAAANQAECgUICgAAAA==.Adorabull:BAAANQADCgIIAgAAAA==.',
Ae='Aenastian:BAAANQADCgUIDwABNQAECgoKMwADAKQgAA==.Aerynsun:BAAANQABCggIDgABNQAECggIJgAEAK0VAA==.',
Ak='Akhalla:BAAANQAECgQIBAABNQAECgUIBgAFAAAAAA==.Akre:BAAANQAECgEIAQAAAQ==.Akumä:BAAANQADCgcIEQAAAA==.',
Al='Alarmclock:BAAANQABCgcICwABNQAECggIJgAEAK0VAA==.Aleannia:BAAANQADCggICAAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAABNQAECn8eAAIBAAkK/xhhdgBAAgABAAkK/xhhdgBAAgAAAA==.Algodón:BAAANQADCgEIAgABNQAECgoKPQAGACciAA==.Alibrexia:BAABNQAECn8aAAIEAAcK1QdeFgA1AQAEAAcK1QdeFgA1AQAAAA==.Allus:BAAANQABCgUICQAAAA==.Alphaomega:BAAANQAECgUIBQAAAA==.',
An='Anarcy:BAAANQAECgIIAgAAAA==.Anastaysha:BAAANQADCgIIAgABNQAECgMIBQAFAAAAAA==.Anathema:BAAANQADCggIEAAAAA==.Ankan:BAABNQAECn8eAAIHAAoKkxwhLgCuAgAHAAoKkxwhLgCuAgABNQAECgoKMwADAKQgAA==.',
Ar='Arcticplague:BAAANQADCgEIAQAAAA==.Ardatha:BAAANQADCgIIAgAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.Arlor:BAAANQADCgYIDAAAAA==.',
As='Ashkada:BAAANQADCgQIBAAAAA==.Astrocakes:BAAANQADCgYICgABNQAECggIIgAIAIUcAA==.',
At='Athenä:BAACNQAFFH8YAAIJAAYKiRqjAwC+AQAJAAYKiRqjAwC+AQA1AAQKfyYAAgkACgp0HIELAOECAAkACgp0HIELAOECAAAA.Atsuma:BAAANQADCggICwAAAA==.Atthel:BAAANQAECgYIDQAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgYICgAFAAAAAA==.Aylli:BAAANQADCgcIBwABNQAECggIGgAKAI4ZAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAAANQAECgQICAAAAA==.',
Ba='Baconmecrazy:BAAANQADCgMIAwAAAA==.Baela:BAAANQAECgMIAwABNQAFFAYIGwALAF0eAA==.Baelthemar:BAAANQADCgUIBQAAAA==.Bajafresh:BAAANQADCgMIAwAAAA==.Bambita:BAAANQAECgUIBwAAAA==.Battleshaman:BAAANQABCgMIAgAAAA==.',
Be='Benjinana:BAAANQAECgUIDwAAAA==.',
Bi='Bittybombom:BAAANQADCggICAAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Blackened:BAABNQAECn8UAAIMAAcKlRpKAQC3AQAMAAcKlRpKAQC3AQAAAA==.Blessing:BAAANQABCggIGQABNQAECggIJgAEAK0VAA==.Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Bohde:BAAANQAFFAEIAQAAAA==.Boricua:BAAANQAECgIIAgAAAA==.Bountty:BAAANQADCgYIBgAAAA==.',
Br='Brightbane:BAAANQAECgEIAQAAAA==.',
Bu='Buddie:BAAANQADCggICAAAAA==.Buffaloseven:BAAANQAECgQICQABNQAFFAYIDwANAFIVAA==.Bulleitrye:BAAANQADCgYIBgAAAA==.Burninate:BAAANQABCggIEQABNQAECggIJgAEAK0VAA==.',
By='Byorn:BAABNQAECn8UAAMOAAkKcBMwZgBaAQAOAAcKew4wZgBaAQAPAAYKoBSWMwDPAAABNQAFFAQICgAGAPwSAA==.',
Ca='Cairdamane:BAABNQAECn8eAAMQAAoKjg7zcgDIAQAQAAoKjg7zcgDIAQALAAMKPAaHgABWAAAAAA==.Calidrina:BAABNQAECn8mAAIRAAoKpA21CQB2AQARAAoKpA21CQB2AQAAAA==.Caness:BAAANQADCgEIAQAAAA==.',
Ce='Celldrassil:BAAANQAECgcIEQAAAA==.Cellerunn:BAAANQADCgYIBgAAAA==.Cereel:BAAANQAECggIDgABNQAECggIIgAIAIUcAA==.',
Ch='Chardaney:BAAANQAECgMIBQAAAA==.Cheery:BAAANQABCgcIFAABNQAECggIJgAEAK0VAA==.Chickennuggi:BAAANQAECgUICAABNQAECgkJJQAOAIgjAA==.',
Ci='Cii:BAABNQAECn8mAAMJAAkKtRMDCQBqAQAJAAcKwxUDCQBqAQABAAIKXgdmAAEwAAAAAA==.Ciine:BAAANQADCgYICAABNQAECgkJJgAJALUTAA==.Ciruzita:BAAANQADCgUIBQAAAA==.',
Cl='Clampz:BAEANQAECgUIBwABNQAFFAYIEgASAGAeAA==.',
Co='Colabrn:BAAANQADCggIDQAAAA==.Colandros:BAAANQADCgEIAQAAAA==.Colara:BAABNQAECn8bAAIRAAgKFg3RDwA0AQARAAgKFg3RDwA0AQAAAA==.Colbear:BAAANQABCgUICQAAAA==.Coldspace:BAABNQAECn88AAIBAAoKkh+gBQCUAgABAAoKkh+gBQCUAgAAAA==.Corlock:BAAANQABCgUIBQAAAA==.',
Cr='Crassberry:BAACNQAFFH8KAAITAAUK1BsCDABNAQATAAUK1BsCDABNAQA1AAQKfyEAAhMACgpGJEkkALACABMACgpGJEkkALACAAAA.Creepindeath:BAAANQAECgEIAgAAAA==.',
Cu='Cucaracha:BAAANQAECgYICgAAAA==.',
Cy='Cyndal:BAAANQADCgcIHQABNQAECgYICgAFAAAAAA==.Cyndle:BAAANQADCggIHgABNQAECgYICgAFAAAAAA==.',
Da='Dankbuds:BAAANQAECggICwAAAA==.Dankothy:BAAANQAECgIIAQABNQAECggICwAFAAAAAA==.Dantes:BAAANQAECgEJAQAAAA==.Darkryu:BAAANQADCgYIEAAAAA==.Darkspace:BAAANQAECgUICQABNQAECgoKPAABAJIfAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQAECgQIBgAAAA==.',
De='Deadbolt:BAAANQAECgUIBAAAAA==.Deathforever:BAAANQAECgQIBAAAAA==.Deaus:BAAANQADCggIFQAAAA==.Delrus:BAABNQAECn8hAAMUAAoKwx3wEgC2AgAUAAkK7xzwEgC2AgAVAAUKMBBgKQC9AAAAAA==.Demon:BAABNQAECn85AAIDAAoKVR7TAQDCAgADAAoKVR7TAQDCAgABNQAFFAcIHgASAIMTAA==.Demowneege:BAAANQADCggICAABNQAFFAUIFgAEAGUhAA==.Denzvic:BAAANQAECgYICwAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Diddyjr:BAABNQAECn8fAAINAAkKgR27fACFAgANAAkKgR27fACFAgAAAA==.Disowneege:BAAANQAECgYICgABNQAFFAUIFgAEAGUhAA==.',
Do='Doodu:BAAANQAFFAEIAQAAAA==.',
Dr='Dragnas:BAABNQAECn8uAAQCAAoKsw/4EQBKAgACAAoKsw/4EQBKAgALAAQKuxJrvADyAAAQAAEKHg5NLgE6AAAAAA==.Dragonisa:BAAANQAECgIIAQAAAA==.Draiocht:BAAANQADCgQIBwABNQAECggIGgAKAI4ZAA==.Drakass:BAAANQADCggICgAAAA==.Dramakiller:BAAANQAECgQIBgAAAA==.Drcornbread:BAAANQAECgUIDwAAAA==.Drcornellia:BAAANQADCgYIBwABNQAECgUIDwAFAAAAAA==.Drdreggs:BAABNQAECn8cAAMWAAkKzhEzhADbAQAWAAgKcBEzhADbAQAXAAEKBhTVcQA9AAAAAA==.Drop:BAAANQADCgQIBAABNQAECgoKLAABAJ8aAA==.Druduwolf:BAAANQAECgcIEAAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgUICgAFAAAAAA==.Dustyhunter:BAAANQADCgQIBAAAAA==.',
Ea='Eatbuttforpi:BAAANQADCgUIBwABNQAECggIIgAIAIUcAA==.',
El='Elastar:BAABNQAECn8oAAIYAAkK6BQBBwBJAQAYAAkK6BQBBwBJAQAAAA==.Ellimist:BAEANQAECgcIDAAAAA==.Elsan:BAAANQADCgQIBAAAAA==.Elycee:BAABNQAECn8YAAIZAAoK9RBDAwDxAQAZAAoK9RBDAwDxAQAAAA==.',
Em='Emura:BAAANQAECgEIAQAAAA==.',
En='Enveliria:BAAANQAECgUIDgABNQAECgoKMwADAKQgAA==.',
Er='Eraser:BAABNQAECn8yAAMKAAkK/RI/ZADzAQAKAAkK/RI/ZADzAQAaAAcKVQ5KOgBVAQAAAA==.Erazar:BAAANQAECgYIDQAAAA==.Erickk:BAABNQAECn8vAAINAAoK7xh1HQCaAQANAAoK7xh1HQCaAQAAAA==.Eristela:BAAANQAECgEIAQAAAA==.',
Es='Escanorlion:BAAANQAECgUIBwAAAA==.Essense:BAABNQAECn8oAAIKAAkKcCXUBwBsAgAKAAkKcCXUBwBsAgAAAA==.',
Ev='Evokedcat:BAAANQAECgcIDgAAAA==.',
Ex='Exodari:BAABNQAECn8xAAICAAoKUg7xAgD8AQACAAoKUg7xAgD8AQAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgIIAgABNQAECggIIgAIAIUcAA==.Faeliendra:BAAANQADCggICAAAAA==.Fangloria:BAAANQABCggIEwABNQAECggIJgAEAK0VAA==.Fatalgrip:BAAANQADCgUIBgAAAA==.',
Fe='Fel:BAABNQAECn9AAAMDAAoKLSK8BgCLAwADAAkKUSO8BgCLAwARAAgKcxwLBQDFAQAAAA==.Fellius:BAAANQADCgQIBAAAAA==.Fellkarras:BAAANQAECgUICAABNQAECgkJJQAOAIgjAA==.Felprincess:BAAANQABCgYICgAAAA==.',
Fi='Fibitz:BAAANQAECgcICwABNQAECgoKGAAGABweAA==.Findstewie:BAAANQABCgYICgABNQABCggIFgAFAAAAAA==.Fiofio:BAABNQAECn8mAAINAAkKbBtYRAAzAQANAAkKbBtYRAAzAQAAAA==.Fizban:BAABNQAECn8WAAMbAAgKtQzxDwCoAQAbAAgKtQzxDwCoAQANAAQK+AEimwGQAAAAAA==.',
Fl='Flik:BAAANQAECgUICAABNQAECgoKQAAKAEccAA==.',
Fo='Foringojr:BAAANQAECgIIAgAAAA==.',
Fr='Fragglelock:BAAANQABCggIFAABNQAECggIJgAEAK0VAA==.Frigidheart:BAAANQAECgUIDAABNQAECgcIDwAFAAAAAA==.Frostetute:BAAANQAECggICgAAAA==.',
Fu='Furrybawlz:BAAANQADCggICAAAAA==.',
['Fà']='Fàllén:BAAANQAECgEIAwABNQAFFAQICgAGAPwSAA==.',
Ga='Gadogear:BAAANQAECgYIEQAAAA==.Galabren:BAAANQAECgYJDQAAAA==.Garlik:BAAANQADCgUIDQAAAA==.',
Gf='Gfr:BAAANQAECgUIDAAAAA==.',
Gi='Giddoo:BAAANQAECgMIAwAAAA==.Gilnean:BAAANQABCgMIBAAAAA==.',
Gn='Gnomeanator:BAAANQABCgIIAgAAAA==.Gnowanceyi:BAAANQAECgIIAgABNQAECgoKLwANAO8YAA==.',
Go='Goatcheeze:BAAANQAECgcIDQAAAA==.Gohlemsaurus:BAAANQADCggIJAAAAA==.',
Gu='Gulen:BAAANQADCggIGwAAAA==.Gullee:BAAANQABCggIEwAAAA==.',
['Gí']='Gíga:BAAANQAECgMIAwAAAA==.',
Ha='Halsten:BAAANQAECgcIEAAAAA==.Hamish:BAAANQAECgEIAQAAAA==.',
He='Hellenkeller:BAEANQAFFAEIAgABNQAFFAYIEgASAGAeAA==.Heloisa:BAAANQADCgYIBgAAAA==.Helrazor:BAAANQADCgUIBQABNQAECgkJHQAcACYWAA==.',
Hi='Hitt:BAAANQAECgYICgAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.',
Hr='Hroc:BAAANQAECgcIEgAAAA==.',
Ic='Icedlatte:BAAANQADCgUIDQAAAA==.Icywolfy:BAAANQAECgIIAgAAAA==.',
Ig='Igreetyou:BAAANQAECgMIBAAAAA==.',
Il='Illune:BAABNQAECn8dAAINAAYKRRfqSAAqAQANAAYKRRfqSAAqAQABNQAECgkJKQAJALAhAA==.',
Im='Imleapingit:BAABNQAECn8bAAIIAAcKEBfcFwCoAQAIAAcKEBfcFwCoAQAAAA==.Imrelentless:BAAANQABCgYICwAAAA==.',
In='Inaurian:BAAANQADCggICAAAAA==.Intoodeep:BAABNQAECn8yAAIdAAoKxRJ1AwAMAgAdAAoKxRJ1AwAMAgAAAA==.',
Ir='Ir:BAABNQAECn9CAAINAAoKXBthBQCAAgANAAoKXBthBQCAAgAAAA==.Irrlvntgobbo:BAAANQAECgYICwAAAA==.',
Is='Isasham:BAAANQAECgIIAgAAAA==.Isawarriorr:BAABNQAECn8eAAMIAAkKshkqXgByAgAIAAkKmRcqXgByAgAYAAIK0Rv1NACOAAAAAA==.Ishdo:BAABNQAECn8aAAIOAAgKPAwwYQBtAQAOAAgKPAwwYQBtAQAAAA==.Ishdu:BAAANQADCgYIBgABNQAECggIGgAOADwMAA==.Ishlok:BAAANQADCgUIBQABNQAECggIGgAOADwMAA==.Ishmael:BAAANQAECgQIBAABNQAFFAQICgAGAPwSAA==.Ishwar:BAAANQADCggIGAABNQAECggIGgAOADwMAA==.',
Iv='Ivanhöe:BAAANQAECgEIAQAAAA==.',
Ja='Jakytreehorn:BAABNQAECn8UAAIQAAgKZBDVZwDpAQAQAAgKZBDVZwDpAQAAAA==.Jaydm:BAAANQAECgYICQABNQAFFAYIDwANAFIVAA==.',
Je='Jenevelle:BAAANQAECgMJAwAAAA==.Jerisil:BAAANQADCgUICAAAAA==.Jessiel:BAAANQAECgUIBAAAAA==.Jet:BAABNQAECn8sAAIBAAoKnxopDwADAgABAAoKnxopDwADAgAAAA==.',
Ju='Julthaenia:BAABNQAECn8nAAIMAAgK+BmGAQCkAQAMAAgK+BmGAQCkAQABNQAECgoKMwADAKQgAA==.Junjia:BAAANQADCgUIBQAAAA==.',
Ka='Kagebushin:BAAANQABCgIIAgAAAA==.Kagome:BAAANQADCggIDQABNQAECgMIBQAFAAAAAA==.Kalofelement:BAAANQADCgEIAQAAAA==.Kalysy:BAAANQADCggICAABNQAECgoKMwADAKQgAA==.Karash:BAAANQAECgUICgAAAA==.Kargush:BAAANQADCgQIBAABNQADCggIFgAFAAAAAA==.Karmaisab:BAAANQAECgMIAQAAAA==.Karnrae:BAABNQAECn8eAAIBAAkKWBOiIAChAQABAAkKWBOiIAChAQAAAA==.Karynos:BAABNQAECn8tAAIWAAkKZhFRQgAIAQAWAAkKZhFRQgAIAQAAAA==.Katwolf:BAAANQAECgYIEQAAAA==.Katyah:BAABNQAECn8XAAILAAgKCAfIlgBOAQALAAgKCAfIlgBOAQAAAA==.Kavourkaa:BAAANQABCggIHQAAAA==.',
Ke='Keynivas:BAAANQAECgIJAgAAAA==.',
Ki='Killiua:BAAANQAECgcICwAAAA==.',
Ko='Konspiracy:BAABNQAECn8WAAMXAAgK4xBADwAHAgAXAAgK4xBADwAHAgAWAAEKAAAfTAErAAAAAA==.',
Kr='Kraguva:BAAANQAECgQIBAAAAA==.Krataar:BAAANQAECgEIAQABNQAECgYIDQAFAAAAAA==.Kroot:BAABNQAECn8YAAIGAAoKHB4KDQAKAgAGAAoKHB4KDQAKAgAAAA==.Krous:BAACNQAFFH8SAAIIAAYKqRrmCgACAgAIAAYKqRrmCgACAgA1AAQKfyUAAggACgp1GxBPAJwCAAgACgp1GxBPAJwCAAAA.Kryph:BAAANQAECgUIDgAAAA==.',
['Kä']='Kämpfer:BAAANQAECgcICwABNQAECgkJLAAeAD8UAA==.',
La='Lafiel:BAABNQAECn8hAAIKAAkKHBKCJABuAQAKAAkKHBKCJABuAQAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Latrank:BAAANQAECgYIBgAAAA==.Laurandre:BAABNQAECn8jAAMUAAcKiAcRGgDzAAAUAAcKiAcRGgDzAAAVAAEKAABHyQAZAAAAAA==.Lazeras:BAAANQAECgQICAABNQAECgkJHQAcACYWAA==.',
Le='Letsgetwet:BAAANQADCgUIBQAAAA==.',
Li='Liefic:BAABNQAECn8eAAIGAAkKqBgSTwCBAgAGAAkKqBgSTwCBAgAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilienne:BAAANQABCgYIBwAAAA==.Lilstooge:BAAANQABCgYIBwABNQABCggIFgAFAAAAAA==.Limon:BAAANQAECgYIBgAAAA==.',
Ll='Llylith:BAAANQABCgMIBAAAAA==.',
Lo='Locke:BAAANQAECgUIBwABNQAECgoKLAABAJ8aAA==.',
Lu='Luckykilla:BAABNQAECn8qAAIdAAgKjhbVKQBFAgAdAAgKjhbVKQBFAgAAAA==.Lucÿ:BAACNQAFFH8FAAILAAIKERdvHQCpAAALAAIKERdvHQCpAAA1AAQKfy0AAwsACgqzHuQjANcCAAsACgqzHuQjANcCABAABgp7EmyYAGgBAAAA.Lune:BAAANQADCgUICwAAAA==.Lurith:BAABNQAECn8zAAMTAAkKExLcHAACAQAOAAYKjwvKeQARAQATAAcKNRXcHAACAQAAAA==.Luxtyrannica:BAAANQAECgcICwAAAA==.',
Ly='Lydrain:BAAANQAECgQIBQAAAA==.Lylia:BAAANQADCggIGAAAAA==.',
Ma='Malcolm:BAAANQABCgYICwABNQAECggIJgAEAK0VAA==.Marahh:BAAANQABCgIIAgAAAA==.Matt:BAAANQAECgQIBAABNQAFFAcIHgASAIMTAA==.Mattbolt:BAABNQAECn8UAAICAAcKPiMDDwB6AgACAAcKPiMDDwB6AgAAAA==.Maximoose:BAACNQAFFH8KAAIGAAQK/BKDEQBIAQAGAAQK/BKDEQBIAQA1AAQKfxkAAgYACgqwFXhHAJYCAAYACgqwFXhHAJYCAAAA.Mayu:BAAANQADCggIGgAAAA==.Mayumey:BAAANQADCgUIBQAAAA==.Mazigos:BAAANQAECgUJBQAAAA==.',
Me='Medjrab:BAABNQAECn81AAITAAoKTB58CQByAwATAAoKTB58CQByAwAAAA==.Mefi:BAAANQADCgcIEwAAAA==.Melyria:BAABNQAECn8ZAAIRAAgKsQ1AEwAWAQARAAgKsQ1AEwAWAQAAAA==.Meristem:BAABNQAECn8eAAIVAAcKCg3UGgAOAQAVAAcKCg3UGgAOAQAAAA==.Merko:BAAANQADCggICQABNQAECgoKGAAGABweAA==.',
Mi='Mignius:BAAANQADCgYIBgAAAA==.Mistified:BAAANQABCgIIBAAAAA==.',
Mo='Moedorai:BAAANQAECggIEAAAAA==.Mogma:BAAANQAECgUICQAAAA==.Mogsarren:BAAANQABCgIIAgABNQAECgoKQAAOAP0jAA==.Momentomori:BAAANQADCgUICwAAAA==.Mondgrille:BAAANQADCgcIBwABNQADCggICAAFAAAAAA==.Monora:BAAANQADCggICQAAAA==.Moonbounds:BAACNQAFFH8TAAILAAcKSxoGBgAIAgALAAcKSxoGBgAIAgA1AAQKfz8AAgsACgo5IpkFAJoDAAsACgo5IpkFAJoDAAAA.Moondoggey:BAAANQADCgUIBQAAAA==.Morgana:BAAANQADCgYICAAAAA==.Mousechief:BAAANQAECgYIEAAAAA==.Moxxzi:BAABNQAECn8jAAITAAcK9hGODAB9AQATAAcK9hGODAB9AQAAAA==.',
Mu='Muhfookinbak:BAABNQAECn8eAAQQAAgKdCARIgABAwAQAAgKdCARIgABAwACAAEKixMMHgBMAAALAAEKUxD2FwE7AAAAAA==.Muvahmedicin:BAAANQADCgcIBwAAAA==.',
Na='Naksu:BAAANQADCgYJFgABNQAECgkJJQAKAB4eAA==.Naksù:BAAANQADCgUIBQABNQAECgkJJQAKAB4eAA==.Naksû:BAAANQADCgYIBgABNQAECgkJJQAKAB4eAA==.Naksü:BAABNQAECn8lAAIKAAkKHh6WCwArAgAKAAkKHh6WCwArAgAAAA==.',
Ne='Neifeb:BAABNQAECn8hAAIGAAgKphHxggAGAgAGAAgKphHxggAGAgAAAA==.Nerfherder:BAAANQABCgcIDwABNQAECggIJgAEAK0VAA==.',
Ni='Niallivdam:BAAANQAECgMIBQAAAA==.Nights:BAAANQAECgIIAwABNQAFFAcIHgASAIMTAA==.Ninh:BAABNQAECn9CAAIfAAoKJwx9BwBoAQAfAAoKJwx9BwBoAQAAAA==.Nintendopsp:BAAANQAECgIIAgAAAA==.Ninthgate:BAABNQAECn8aAAIWAAYKcAWZ4QAGAQAWAAYKcAWZ4QAGAQAAAA==.',
No='Noble:BAABNQAECn8gAAMRAAoKCA2tDQBIAQARAAoKCA2tDQBIAQADAAEKuQbwUAA1AAAAAA==.Nogood:BAABNQAECn8ZAAIIAAoKRRYzaQBVAgAIAAoKRRYzaQBVAgAAAA==.Northwest:BAAANQABCgYJBQAAAA==.Notsodemon:BAAANQAECgQICAABNQAECgcIFQANAJsLAA==.Notsomage:BAABNQAECn8VAAINAAcKmwsDAwGJAQANAAcKmwsDAwGJAQAAAA==.',
Ny='Nyorai:BAAANQABCgQIAwAAAA==.Nyxwing:BAAANQAECgUIBQAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAABNQAECn8mAAMUAAgKIxymAwBVAgAUAAgKIxymAwBVAgAVAAEKAAC3xwAaAAAAAA==.',
Od='Oddone:BAAANQAECgEIAQAAAA==.Oddpocalypse:BAAANQADCgQIBAAAAA==.Odinheâthen:BAAANQADCgYJDAAAAA==.',
Ok='Okrawindfury:BAAANQABCggIFgABNQAECggIJgAEAK0VAA==.',
Ol='Olydwarf:BAAANQAECgEIAQAAAA==.',
On='Onebadmutha:BAAANQAECgcIEgAAAA==.Ontop:BAABNQAECn9CAAIGAAoK9BvNAwCkAgAGAAoK9BvNAwCkAgAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAABNQAECn8hAAMbAAcKtBcuDQDgAQAbAAcKtBcuDQDgAQANAAMK1wV1swFaAAAAAA==.',
Ow='Owneege:BAACNQAFFH8WAAMEAAUKZSE4AAAnAQAIAAUKYRo7EgCeAQAEAAUKehs4AAAnAQA1AAQKfygAAwQACgrvHpsKAB4CAAgACQrUIQtGALgCAAQABwp5HZsKAB4CAAAA.',
Pa='Paapaa:BAAANQADCgcIBQAAAA==.Pallideaus:BAABNQAECn8ZAAIHAAcKayGTLwCoAgAHAAcKayGTLwCoAgAAAA==.Pallinar:BAAANQAECgcICwAAAA==.Pandamak:BAAANQADCggICAAAAA==.Paradoxx:BAAANQADCgIIBAAAAA==.Pasquale:BAAANQAECgQIBgAAAA==.Pauzhaan:BAAANQAECgQIBAABNQAECggIJgAEAK0VAA==.',
Pe='Pebbles:BAABNQAECn8zAAIBAAoKxxLuFwDDAQABAAoKxxLuFwDDAQAAAA==.Pedorus:BAAANQABCgYIBwABNQAFFAIIBQALABEXAA==.Penjerman:BAAANQAECggICAABNQAECggIIgAIAIUcAA==.',
Pi='Picklericky:BAAANQADCggIEQAAAA==.Pilgrimm:BAECNQAFFH8SAAISAAYKYB7uAQA4AgASAAYKYB7uAQA4AgA1AAQKfyUABBIACgqRJJ4DAGUDABIACgqRJJ4DAGUDACAAAQq5G4YZAEwAAB0AAQpBC42gADoAAAAA.Pinxyl:BAAANQABCgcIBwAAAA==.Pissonmyfood:BAAANQAECgQIBAABNQAFFAcIEwAhAN0PAA==.Pistola:BAAANQAECgQIBAAAAA==.',
Pl='Plaguerott:BAABNQAECn8YAAIPAAcKsgVSYgAbAQAPAAcKsgVSYgAbAQAAAA==.Plaguewind:BAAANQAECgEIAQAAAA==.',
Po='Polydh:BAABNQAECn8xAAIiAAoKGCNVAADzAgAiAAoKGCNVAADzAgAAAA==.Poobah:BAABNQAECn8hAAMQAAcKLwanWACLAAAQAAYKwQanWACLAAALAAIKrgImhQBNAAAAAA==.Popsicles:BAABNQAECn8eAAMjAAgKhxYqBgAyAgAjAAgKhxYqBgAyAgAaAAEKAADjigAfAAAAAA==.Potrat:BAAANQAECgMJAwAAAA==.Pouffant:BAAANQAECgUICgAAAA==.',
Pr='Praddagy:BAAANQADCgUIBQAAAA==.Pronoz:BAAANQAECggIDwAAAA==.',
Pu='Purpyl:BAAANQAECgUIBgAAAA==.',
Pw='Pwnageddon:BAAANQADCgcIHAAAAA==.Pwnjitsu:BAABNQAECn8nAAIkAAoK4BciGgBwAgAkAAoK4BciGgBwAgAAAA==.',
Py='Pyrothermia:BAACNQAFFH8PAAINAAYKUhWIDgADAgANAAYKUhWIDgADAgA1AAQKfyQAAw0ACgqEGWJuAKECAA0ACgqEGWJuAKECABsAAwr+BIsyAHEAAAAA.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Rawhoof:BAABNQAECn9CAAIIAAoKZyDfAgDfAgAIAAoKZyDfAgDfAgAAAA==.Razak:BAABNQAECn84AAICAAoK7B1PAQB3AgACAAoK7B1PAQB3AgAAAA==.',
Rd='Rdnckromeo:BAAANQAECgQIBAAAAA==.',
Re='Redlock:BAABNQAECn8fAAIXAAcKegfrBQDIAAAXAAcKegfrBQDIAAAAAA==.Redrum:BAABNQAECn8lAAIOAAkKiCMZCwBbAwAOAAkKiCMZCwBbAwAAAA==.Reineken:BAAANQADCgMIAwAAAA==.Renarin:BAABNQAECn9AAAIKAAoKRxzYDAAbAgAKAAoKRxzYDAAbAgAAAA==.Renisa:BAABNQAECn8cAAMRAAcKshf6JgANAgARAAcKshf6JgANAgADAAEKMwb6nAAlAAAAAA==.Renobagem:BAAANQADCgUIBgAAAA==.Retman:BAAANQADCggIDgAAAA==.Reu:BAAANQAECgYICQAAAA==.Revlyk:BAABNQAECn8hAAICAAkKxxRBDwB1AgACAAkKxxRBDwB1AgABNQAECgoKMwADAKQgAA==.',
Rh='Rhoanna:BAAANQAECgMIAwAAAA==.Rhoupert:BAABNQAECn8UAAIBAAcKXBZhmQDwAQABAAcKXBZhmQDwAQAAAA==.',
Ri='Rimastus:BAAANQADCgEIAQAAAA==.',
Ro='Roccot:BAABNQAECn8rAAIOAAkKSB35BQDjAQAOAAkKSB35BQDjAQAAAA==.Rotfather:BAAANQADCgYIBgAAAA==.Rotjaw:BAAANQADCggIDAAAAA==.Roughedge:BAAANQADCgIIAgAAAA==.',
Rv='Rvn:BAAANQAECgMIBAAAAA==.',
Ry='Ryppyr:BAAANQADCggICAAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQABCgYIDAAAAA==.Sallanu:BAAANQAECgEIAQAAAA==.Sauron:BAAANQAECgQIAwAAAA==.',
Sc='Scalycat:BAAANQAECgcIDQAAAA==.Schuey:BAAANQADCggICAAAAA==.Scum:BAAANQADCgcIDQABNQADCggICAAFAAAAAA==.',
Se='Senate:BAABNQAECn8rAAMQAAkKfhBdFwBlAQAQAAkKfhBdFwBlAQALAAEKqgFVMQEfAAAAAA==.Servenslay:BAAANQADCggIDgAAAA==.',
Sh='Shaamazing:BAAANQABCgIIAgAAAA==.Shablaam:BAAANQADCggIEQAAAA==.Shadowbear:BAABNQAECn8XAAIaAAgKghPLCABnAQAaAAgKghPLCABnAQAAAA==.Sherrilyn:BAAANQAECgEIAQAAAA==.Shifdiah:BAAANQAECgUICgAAAA==.Shocktherapi:BAAANQAECgcIDAAAAA==.Shrimpback:BAAANQAECgIIAQAAAA==.',
Si='Singularity:BAAANQAECgQJBQAAAA==.',
Sk='Skelli:BAECNQAFFH8ZAAIKAAYKehSXCgDfAQAKAAYKehSXCgDfAQA1AAQKfxwAAgoACgqxGo47AHsCAAoACgqxGo47AHsCAAE1AAQKBwgMAAUAAAAA.Skittlesdan:BAABNQAECn8eAAQWAAgKNRPSfgDpAQAWAAgKNRPSfgDpAQAMAAEKAAB/MgAvAAAXAAEKxQQWgwAoAAAAAA==.',
Sl='Slaykween:BAAANQAECgUIDgAAAA==.',
Sm='Smallz:BAAANQAECgUIBQABNQAECggIFgAbALUMAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAABNQAECn8mAAQEAAgKrRURDwC8AQAEAAYK6xgRDwC8AQAIAAcK0A2+ugCKAQAYAAIKMhpPOQBmAAAAAA==.',
So='Something:BAAANQABCggIEwABNQAECggIJgAEAK0VAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Steakhaus:BAAANQAECgIIAgAAAA==.Stonedragon:BAECNQAFFH8KAAIGAAMKmxVhDACnAAAGAAMKmxVhDACnAAA1AAQKf0sAAgYACgo8JaoFALQDAAYACgo8JaoFALQDAAAA.Stormfang:BAAANQADCgcIDgABNQAECgQICAAFAAAAAA==.Stormfist:BAAANQADCgQIBgAAAA==.Stormhaven:BAAANQADCgQJBAABNQAECgQICAAFAAAAAA==.Stormrender:BAAANQAECgUICgAAAA==.Stormriders:BAABNQAECn8kAAIQAAYKkRBXRAC/AAAQAAYKkRBXRAC/AAAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Streea:BAAANQADCggIHAABNQAECgYICgAFAAAAAA==.Stubz:BAAANQABCgQIBgAAAA==.',
Su='Sugi:BAAANQAECgMIBAABNQAFFAIIBQARAOsNAA==.Sukonamí:BAABNQAECn8YAAIIAAgKFhBAWgDkAAAIAAgKFhBAWgDkAAAAAA==.Suzhou:BAABNQAECn8ZAAIXAAcKmQaBBQDPAAAXAAcKmQaBBQDPAAAAAA==.Suzoomies:BAAANQADCggIDwAAAA==.',
Sw='Swisscheese:BAABNQAECn8eAAMWAAkKqBomXABDAgAWAAkKqBomXABDAgAXAAEKLwpLewAyAAAAAA==.Swoopyboop:BAAANQADCgQIBAAAAA==.',
Sy='Sybaek:BAAANQAECgcICAAAAA==.Sycò:BAABNQAECn8lAAMGAAkKGyOaEgBVAwAGAAkKGyOaEgBVAwAZAAEKkQF3ngAgAAAAAA==.Syraxa:BAAANQAECgMIBAABNQAECgoKNAAUAEQaAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAQABNQAFFAQICwAGAJcTAA==.',
Ta='Taedish:BAAANQADCgQIBAAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.Tannith:BAAANQABCgYIDgABNQABCggIFgAFAAAAAA==.Tayy:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Telan:BAAANQADCgUIBQAAAA==.Tempertotems:BAAANQADCggIDQAAAA==.Tenastin:BAAANQADCgQIBAAAAA==.Terragosa:BAABNQAECn8cAAMNAAcKYBYaMQBeAQANAAcKMRQaMQBeAQAbAAIKFwwBNwBgAAAAAA==.Tetchybono:BAAANQAECgYIDAAAAA==.Tettra:BAAANQADCgIIAgABNQAECgYICgAFAAAAAA==.',
Th='Thaeleon:BAAANQAECgMIAwABNQAFFAQICgAGAPwSAA==.Thahawtz:BAAANQADCgYJDAAAAA==.Thirinis:BAAANQAECgUIDAAAAA==.Thope:BAAANQADCgYIFgAAAA==.Thundergirl:BAAANQAECgIIAgAAAA==.',
Ti='Ticklemychin:BAAANQADCgcIBwAAAA==.',
To='Toughasnails:BAAANQAECgEIAQAAAA==.',
Tr='Traesdyne:BAAANQADCgQIBQAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECgkJHQAcACYWAA==.Trainar:BAAANQAECgUIDQABNQAECgcIGgADADEaAA==.Triggs:BAAANQAECggIBwAAAA==.Troggdor:BAAANQABCggIDgABNQAECggIJgAEAK0VAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAAANQAECgYIDAAAAA==.Truckz:BAAANQAECgUICQAAAA==.Trõnlight:BAAANQAECgEIAQAAAA==.',
Ts='Tsunah:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQAECgEIAQAAAA==.Turim:BAAANQAECgEIAQAAAA==.',
Ty='Tyrawick:BAAANQAECgYIBgAAAA==.Tyrlidd:BAABNQAECn8fAAIGAAcKJgeZWAD9AAAGAAcKJgeZWAD9AAAAAA==.',
Un='Unavoidable:BAAANQADCgMIAwAAAA==.Unlikelytale:BAABNQAECn8uAAMLAAoK2xvFKQC8AgALAAoK2xvFKQC8AgAQAAEKRxbRJgFEAAAAAA==.',
Ur='Urbanmeyer:BAAANQAECgIIAgAAAA==.Uricash:BAABNQAECn82AAINAAoKdxxZRgD2AgANAAoKdxxZRgD2AgAAAA==.Urrax:BAAANQADCgEIAQABNQADCgIIAgAFAAAAAA==.Urzual:BAABNQAECn8mAAMCAAgKFB2BDACoAgACAAgKFB2BDACoAgALAAYKbhSCigBvAQAAAA==.',
Ut='Utiniócast:BAAANQAECgEIAQAAAA==.',
Va='Vandreynna:BAABNQAECn8zAAIDAAoKpCBbBgCQAwADAAoKpCBbBgCQAwAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velsiana:BAAANQAECgMIAwAAAA==.Velveetah:BAAANQADCgYIBwABNQAECgUIDwAFAAAAAA==.Venasia:BAAANQADCgYIBgABNQAECgoKMwADAKQgAA==.Verbren:BAAANQADCgUICgABNQAECgkJLAAeAD8UAA==.Verbrennen:BAABNQAECn8sAAIeAAkKPxQeGgAhAgAeAAkKPxQeGgAhAgAAAA==.Verita:BAAANQAECgQIBgAAAA==.Verlynne:BAAANQADCgcIBwAAAA==.Vetinari:BAAANQABCggIGQABNQAECggIJgAEAK0VAA==.',
Vi='Viviann:BAABNQAECn8lAAMeAAgKSAtsKQBmAQAeAAgKSAtsKQBmAQAlAAYKPAlEIwArAQAAAA==.',
Vo='Von:BAAANQADCgEIAQAAAA==.',
Wa='Walee:BAAANQADCgIIAgAAAA==.Walfred:BAAANQAECgQIBwABNQAECgkJMwATABMSAA==.Warraxe:BAAANQADCgYIBgAAAA==.Waukeen:BAAANQABCgIIAgAAAA==.Wayloren:BAABNQAECn8lAAIBAAgKYAgx0gB3AQABAAgKYAgx0gB3AQAAAA==.Wayverly:BAAANQABCgUIBwABNQAECgMIBQAFAAAAAA==.',
We='Wetboycaird:BAAANQADCgMIAwAAAA==.',
Wi='Wickathy:BAABNQAECn8rAAIiAAoK+yJEAAAOAwAiAAoK+yJEAAAOAwAAAA==.Wickcreu:BAAANQAECgMIAwAAAA==.',
Wo='Woodson:BAAANQADCggICAABNQAECgUIBgAFAAAAAA==.Worstdps:BAACNQAFFH8HAAIDAAMKiQORBwCjAAADAAMKiQORBwCjAAA1AAQKfzUAAgMACgpRFKMTAE4BAAMACgpRFKMTAE4BAAAA.',
Wu='Wuldorr:BAACNQAFFH8HAAIBAAQKAAfYFQAAAQABAAQKAAfYFQAAAQA1AAQKfx8AAgEACgqtDwOcAOsBAAEACgqtDwOcAOsBAAAA.',
Wy='Wynnifred:BAAANQAECgUIEAAAAA==.',
Xa='Xaltheris:BAAANQAECgUIBgAAAA==.',
Xe='Xenothor:BAAANQAECgEIAQAAAA==.Xethreal:BAABNQAECn8fAAILAAcKnx0tGQCQAQALAAcKnx0tGQCQAQAAAA==.',
Xy='Xype:BAAANQAECggICAAAAA==.',
Xz='Xzara:BAAANQAECgYICgAAAA==.',
Yu='Yura:BAAANQADCggICAAAAA==.',
Yv='Yvvee:BAAANQAECgMIAwAAAA==.',
Za='Zapbranigan:BAAANQADCggIDQAAAA==.Zasko:BAAANQADCgIIAgAAAA==.',
Zi='Zifao:BAABNQAECn8nAAINAAoKmyITKQA/AwANAAoKmyITKQA/AwAAAA==.',
Zo='Zonora:BAABNQAECn8YAAIHAAkK/g/kagDXAQAHAAkK/g/kagDXAQAAAA==.',
['Äz']='Äzrael:BAABNQAECn8aAAIKAAgKjhlHSABNAgAKAAgKjhlHSABNAgAAAA==.',
['Çr']='Çréwüsæðèr:BAABNQAECn8cAAIYAAcKXR5NBQB1AQAYAAcKXR5NBQB1AQAAAA==.',
['Ðì']='Ðìaßlo:BAACNQAFFH8LAAIGAAQKlxPuEQBDAQAGAAQKlxPuEQBDAQA1AAQKfywAAgYACgocIPonAPgCAAYACgocIPonAPgCAAAA.',
['Òd']='Òdinn:BAAANQADCgcIBwAAAA==.',
['Ød']='Ødin:BAAANQADCggIFAABNQAECgQICAAFAAAAAA==.',
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
