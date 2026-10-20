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

local lookup = {'Warlock-Demonology','Monk-Brewmaster','Druid-Restoration','Rogue-Assassination','Evoker-Devastation','Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Paladin-Protection','Druid-Guardian','Mage-Arcane','Shaman-Elemental','Monk-Windwalker','DeathKnight-Unholy','Warrior-Protection','Evoker-Augmentation','Mage-Frost','Druid-Balance','Paladin-Holy','Warrior-Fury','Hunter-Marksmanship','Shaman-Enhancement','Monk-Mistweaver','Warrior-Arms','Priest-Holy','Druid-Feral','Evoker-Preservation','Shaman-Restoration','DeathKnight-Blood','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Discipline',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abisio:BAAANQAECgEJAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAABNQAECn8hAAIBAAoKnByXHQAOAwABAAoKnByXHQAOAwAAAA==.Acursedpeen:BAAANQAECgIIAwAAAA==.',
Ad='Aderna:BAAANQAECgQIBgAAAA==.Adoryn:BAEBNQAECn8YAAICAAcKJgkECADgAAACAAcKJgkECADgAAAAAA==.',
Ae='Aelara:BAAANQAECggIEwABNQAECgoKHwADADQYAA==.Aessan:BAAANQAECgcIDgAAAA==.Aethelred:BAAANQADCgYIBgAAAA==.',
Ag='Agares:BAABNQAECn8kAAIEAAoKIBRYFQAcAQAEAAoKIBRYFQAcAQAAAA==.',
Ai='Aisathya:BAAANQAECgYIDQAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Al='Aleysia:BAAANQAECgcIDwABNQAECgoKHwADADQYAA==.Alivar:BAAANQABCgIIAgAAAA==.',
Am='Amberfox:BAAANQAECgUICwAAAA==.Amberscale:BAABNQAECn8rAAIFAAoKGRyHBgAhAwAFAAoKGRyHBgAhAwAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQAECgIIAwAGAAAAAA==.Ancientuur:BAAANQADCgYIBgABNQAECgIIAwAGAAAAAA==.Andazaren:BAABNQAECn8uAAIHAAkKYwswLQB4AQAHAAkKYwswLQB4AQAAAA==.Andracca:BAAANQAECgIIAgAAAA==.Angrulus:BAABNQAECn8jAAIIAAkKjxCnGwCpAQAIAAkKjxCnGwCpAQAAAA==.Animal:BAAANQADCgMIAwAAAA==.Animlshiftr:BAAANQAECgcIDwAAAA==.',
Ap='Apollo:BAABNQAECn8UAAIBAAUKxQe+5QD9AAABAAUKxQe+5QD9AAAAAA==.',
Ar='Arixx:BAAANQABCgIIAgAAAA==.Arrøw:BAAANQADCgQIBAAAAA==.Aryllyn:BAAANQAECgMIBwAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQAECgQIBgABNQAECgUICgAGAAAAAA==.',
At='Atris:BAAANQADCgcIBwAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQAECgQIBAABNQAECgcIIQAJAPgRAA==.Banmoor:BAAANQAECgQICwAAAA==.',
Be='Bearett:BAABNQAECn8nAAIKAAgK6BygBwCFAQAKAAgK6BygBwCFAQAAAA==.Belyrune:BAABNQAECn8XAAILAAkKOgVClACfAAALAAkKOgVClACfAAABNQAECgoKMQAMANARAA==.Belysurge:BAABNQAECn8xAAIMAAoK0BGGKAAbAQAMAAoK0BGGKAAbAQAAAA==.Bernd:BAABNQAECn8aAAIKAAgKNghZLgAnAQAKAAgKNghZLgAnAQAAAA==.Beörn:BAABNQAECn8mAAIDAAgKmSXRBQBlAwADAAgKmSXRBQBlAwAAAA==.',
Bi='Birgir:BAAANQAECgEIAQAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAABNQAECn8VAAINAAcKAwtyOABQAQANAAcKAwtyOABQAQAAAA==.',
Br='Braids:BAAANQAECgUIBwAAAA==.Breezy:BAABNQAECn8rAAIHAAkKhhtoQgDNAgAHAAkKhhtoQgDNAgAAAA==.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAABNQAECn8UAAIOAAcKiBbpGAAcAQAOAAcKiBbpGAAcAQAAAA==.',
Bu='Buttrbiskit:BAAANQAECggIDwAAAA==.',
By='Byanca:BAABNQAECn8XAAINAAcKRwP+SgDOAAANAAcKRwP+SgDOAAAAAA==.',
Ca='Caine:BAABNQAECn8ZAAIPAAcKuRxJBQB1AQAPAAcKuRxJBQB1AQAAAA==.Callen:BAAANQADCgEIAQAAAA==.Carlonus:BAAANQADCggICwABNQAECgkJLgAQAMwRAA==.Casey:BAAANQAECgMIBQAAAA==.Castyblasty:BAABNQAECn8iAAMLAAoKURF4UgAXAQALAAoKURF4UgAXAQARAAEKAAkiRQA5AAAAAA==.',
Ce='Cellina:BAAANQAECgQICgAAAA==.',
Ch='Chiman:BAAANQADCgcJCQABNQAECgUIBAAGAAAAAA==.Chromatica:BAAANQADCgYIBgAAAA==.',
Ci='Cignus:BAAANQAECgcICAAAAA==.',
Cl='Classá:BAABNQAECn8zAAQDAAkKkh2wCwAPAwADAAkKkh2wCwAPAwASAAgKih2YHgDVAgAKAAYK4A7LLgAkAQAAAA==.',
Co='Codedd:BAAANQADCgYIDAAAAA==.Corin:BAABNQAECn87AAMTAAoKzCNDBACxAwATAAoKzCNDBACxAwAHAAUKMhiH+gApAQAAAA==.Corlys:BAABNQAECn8aAAMHAAgK/xIfoADhAQAHAAgK/xIfoADhAQAJAAEKAAC1ewAhAAAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAABNQAECn8UAAIIAAcKMAQ5BAH9AAAIAAcKMAQ5BAH9AAAAAA==.Crue:BAABNQAECn8hAAMDAAcK7RAIIADNAAADAAYK+Q4IIADNAAASAAcKUQemKADBAAAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIJAgAAAA==.Curthar:BAAANQAECgIIAgABNQAECgQIBAAGAAAAAA==.',
Cy='Cynboom:BAAANQADCgUIEgAAAA==.Cyndee:BAABNQAECn8lAAIUAAkK0xF4AwCQAQAUAAkK0xF4AwCQAQAAAA==.Cynnafrost:BAAANQADCgQICgAAAA==.Cytenk:BAAANQAECgMIBAAAAA==.',
Da='Dadda:BAABNQAECn8pAAIVAAoKTBl5EgDPAgAVAAoKTBl5EgDPAgAAAA==.Dagad:BAAANQADCgIIAgAAAA==.Daisynukes:BAAANQAECgQICwABNQAECgkJJgAMAPQOAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAABNQAECn8hAAIJAAcK+BGfLgBpAQAJAAcK+BGfLgBpAQAAAA==.Dankdruid:BAAANQADCgUICgABNQAECgQICAAGAAAAAA==.Darkschi:BAABNQAECn8dAAINAAcKfQmWFAAGAQANAAcKfQmWFAAGAQAAAA==.Darthwing:BAAANQADCgcIDgAAAA==.Dartos:BAABNQAECn8zAAIOAAoKCSHSAADoAgAOAAoKCSHSAADoAgAAAA==.',
De='Deepmagic:BAAANQAECggIDQAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.Destrûction:BAAANQADCgUIBQAAAA==.',
Di='Diluvium:BAABNQAECn8eAAIJAAcKNRo3GgAfAgAJAAcKNRo3GgAfAgAAAA==.Discodank:BAAANQAECgQICAAAAA==.',
Dj='Djpleasant:BAACNQAFFH8MAAIRAAUKkg1OAQBqAQARAAUKkg1OAQBqAQA1AAQKfzAAAxEACQrDIy8CAFMDABEACQrDIy8CAFMDAAsABQq2HSk0ATUBAAAA.',
Do='Dontcare:BAABNQAECn8bAAMIAAoK7R3yEgDaAQAIAAkKTh/yEgDaAQAVAAMKiQ8dZQCXAAAAAA==.',
Dw='Dwailn:BAAANQABCgMIAwAAAA==.',
['Dû']='Dûo:BAABNQAECn8tAAMMAAoKgRr2CQDHAQAMAAkK8h32CQDHAQAWAAMKLAvGMgBMAAAAAA==.',
Ea='Eatmorpizza:BAAANQAECgQIDAAAAA==.',
Ee='Eegnormu:BAAANQAECgQICQAAAA==.Eegroll:BAABNQAECn8uAAQCAAkK4BpZBwDIAgACAAkK0RpZBwDIAgANAAcKyRF8MwB6AQAXAAcKqgVxLQAAAQAAAA==.',
Eg='Egraw:BAABNQAECn8XAAMYAAcKgCPHMgBGAQAYAAcKgCPHMgBGAQAPAAEK/yC2GQBlAAAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Em='Emilwhaury:BAAANQADCgYIBgAAAA==.',
Ep='Epia:BAABNQAECn8XAAMNAAoKBhG6KQDQAQANAAoKBhG6KQDQAQACAAIKCAbALQBPAAAAAA==.',
Es='Esdéath:BAABNQAECn9CAAIZAAkKJx5+GwAFAwAZAAkKJx5+GwAFAwAAAA==.Essaila:BAABNQAECn8kAAIaAAkKmg0aFAC7AQAaAAkKmg0aFAC7AQAAAA==.',
Et='Etherwalker:BAABNQAECn8WAAIYAAgK2hrebQBJAgAYAAgK2hrebQBJAgAAAA==.',
Ex='Excision:BAABNQAECn8jAAIFAAgKzAs4BQA6AQAFAAgKzAs4BQA6AQAAAA==.',
Fa='Fahbio:BAAANQAECgYIEAAAAA==.Faleros:BAAANQADCgMIAwAAAA==.Fanskar:BAAANQAECgEIAQABNQAECgQIBAAGAAAAAA==.Fatallock:BAABNQAECn9QAAIBAAoKwg50EgCxAQABAAoKwg50EgCxAQAAAA==.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQAECgEIAQAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgcIBwAGAAAAAA==.',
Fl='Flaildh:BAAANQAECgEIAQAAAA==.Flailuid:BAAANQAECgMIBwAAAA==.',
Fr='Fresita:BAAANQAECgQIEQAAAA==.Fridaychill:BAABNQAECn80AAINAAoKXBtHAQCdAgANAAoKXBtHAQCdAgAAAA==.Frozarke:BAABNQAECn8uAAMQAAkKzBHdCAD/AQAQAAkKzBHdCAD/AQAbAAEKVACxVgATAAAAAA==.',
Fu='Fudd:BAAANQAECgYIDgAAAA==.Funk:BAAANQABCgIIAgABNQADCgMIAwAGAAAAAA==.Fupa:BAAANQAECgUICAAAAA==.Furryz:BAAANQADCgYIBgABNQAECggIGgACAGUkAA==.',
Ga='Garou:BAABNQAECn8UAAIMAAgKkBhMVQAlAgAMAAgKkBhMVQAlAgAAAA==.Garres:BAABNQAECn8kAAQKAAkK8RczBwCOAQAaAAkKiRdfDQBGAgAKAAgKkRIzBwCOAQASAAMKYAN3mwBtAAAAAA==.',
Ge='Genius:BAAANQAECgUIDgAAAA==.',
Gi='Gibley:BAAANQAECgQIBAAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAAANQAECgQICAAAAA==.Gnomie:BAAANQAECgUICgAAAA==.Gnomio:BAAANQAECgUICgAAAA==.',
Go='Gouge:BAAANQAECggILgAAAQ==.',
Gr='Granadithios:BAAANQADCgIIAgAAAA==.Griffynshu:BAAANQAECgYIEwAAAA==.Grrv:BAAANQABCgQIBAAAAA==.Grudgetotem:BAABNQAECn8YAAMcAAgKfBsfWAAJAgAcAAgKfBsfWAAJAgAMAAEKSBVTLwE6AAAAAA==.Grunewald:BAAANQAECgQIBwAAAA==.',
Gu='Gungnir:BAABNQAECn8sAAIYAAoKcSEDEQB6AwAYAAoKcSEDEQB6AwAAAA==.',
Ha='Haki:BAAANQAECgQIBwAAAA==.Handiboy:BAABNQAECn8iAAIZAAoKZCUaCQB7AwAZAAoKZCUaCQB7AwAAAA==.Hardison:BAAANQADCgYIBgAAAA==.Hayate:BAAANQAECgQIDgAAAA==.',
He='Healabull:BAAANQADCgYIDgABNQAECgcIHAAdABkSAA==.Heimdall:BAABNQAECn8xAAITAAoKoiSRBQChAwATAAoKoiSRBQChAwAAAA==.Hellabear:BAAANQADCgQIBAAAAA==.Hellaholy:BAABNQAECn8ZAAMJAAYKmw4/GwC1AAAHAAUKygctFgH6AAAJAAQKixA/GwC1AAAAAA==.Hellavva:BAAANQAECgQIBgAAAA==.Help:BAAANQAECgEIAgABNQAECgoKKwALAFseAA==.Henchling:BAABNQAECn8dAAMcAAkKbBqjPwBiAgAcAAkKbBqjPwBiAgAMAAYKfQ1sqABDAQAAAA==.',
Hi='Hina:BAAANQADCggIDgAAAA==.',
Ho='Holexios:BAAANQAECgUIBAAAAA==.Horine:BAAANQAECggIDgAAAA==.',
['Hö']='Hölyhell:BAAANQADCgIIAgAAAA==.',
Ic='Icieblade:BAAANQAECgUIBQAAAA==.',
Im='Immeira:BAABNQAECn8wAAIcAAkKzRqNBwBOAgAcAAkKzRqNBwBOAgAAAA==.',
Ir='Ira:BAAANQAECgQIBwABNQAECgoKHQASAB8QAA==.',
Ja='Jackiix:BAAANQADCgYIBgAAAA==.Jackmends:BAABNQAECn87AAMZAAoK8yMgBwCMAwAZAAoK8yMgBwCMAwAeAAIKLwNWcABHAAAAAA==.Jacksprouts:BAAANQAECgUIBgAAAA==.Jacktides:BAAANQAECgEIAQABNQAECgoKOwAZAPMjAA==.Jarryl:BAAANQAECggICAAAAA==.',
Je='Jeffrez:BAAANQAECgMIAwAAAA==.Jelerious:BAAANQAECggICAAAAA==.Jenoside:BAAANQAECggIKwAAAQ==.',
Ji='Jindu:BAAANQAECggICAAAAA==.',
Jo='Journei:BAABNQAECn8iAAMMAAgKjgujwwALAQAMAAYK8ASjwwALAQAcAAcKHBIkOQACAQAAAA==.',
Ju='Judging:BAAANQAECgYIEwAAAA==.Jurb:BAAANQAECggICAAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIGQAAAA==.Kaitos:BAAANQAECgQIBAAAAA==.',
Ke='Kegz:BAABNQAECn8aAAMCAAgKZSTBAwBOAwACAAgKZSTBAwBOAwANAAIK+AoLJgCDAAAAAA==.Kellayna:BAAANQAECgYIDgAAAA==.Keylö:BAABNQAECn8fAAIOAAkKfxb3CQCZAQAOAAkKfxb3CQCZAQAAAA==.',
Kh='Khoulethius:BAAANQADCgYIBwAAAA==.',
Ki='Kimbot:BAABNQAECn8YAAMIAAkK0xSYRQCbAgAIAAkK0xSYRQCbAgAVAAEKAACzjgAxAAAAAA==.',
Kl='Klerik:BAACNQAFFH8PAAIBAAMKQhIfIwDjAAABAAMKQhIfIwDjAAA1AAQKfzkABAEACgp3I0EIACQCAAEACgp3I0EIACQCAB8ABgo/Di8nAD0BACAAAQoKBiQ0ACoAAAAA.',
Kn='Kníghtmare:BAAANQAECgUICgAAAA==.',
Ko='Koragg:BAACNQAFFH8YAAIdAAUKuR/PCwCYAQAdAAUKuR/PCwCYAQA1AAQKfzMAAh0ACgq6IZwRACADAB0ACgq6IZwRACADAAAA.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgUIBQAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAABNQAECn8ZAAIFAAgKswedHwBcAQAFAAgKswedHwBcAQAAAA==.',
Kr='Kratus:BAAANQAECgEIAQAAAA==.Krissia:BAABNQAECn8vAAMhAAoKrhSxMAAhAgAhAAoKrhSxMAAhAgAOAAUKMgbclgDUAAAAAA==.',
Ky='Kymerah:BAAANQABCgYICAAAAA==.Kyntaliia:BAAANQADCgYIDAAAAA==.',
['Kî']='Kîn:BAAANQAECgYIEAAAAA==.',
La='Lailey:BAAANQADCggICAAAAA==.Laisera:BAABNQAECn8eAAIZAAkKVwpPewCoAQAZAAkKVwpPewCoAQAAAA==.Lalipop:BAAANQAECgYIEAAAAA==.Landroval:BAAANQAECgYIDQAAAA==.Langedamort:BAAANQADCgEIAQAAAA==.Lastkissgbye:BAAANQABCgIIAgAAAA==.Lawson:BAABNQAECn8fAAIOAAcKvxF1FAA7AQAOAAcKvxF1FAA7AQAAAA==.',
Le='Leeoh:BAABNQAECn8kAAILAAoKUQVoTQAhAQALAAoKUQVoTQAhAQAAAA==.Leeohd:BAAANQAECgYIDwAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAAANQAECgQIDAAAAA==.',
Lo='Lovenky:BAAANQADCgUIBgAAAA==.',
Lu='Lujuria:BAABNQAECn8dAAISAAoKHxALBQD9AQASAAoKHxALBQD9AQAAAA==.Lumawig:BAAANQADCgcIBwAAAA==.Lunchdk:BAAANQAECgMIBgAAAA==.',
Ly='Lyreth:BAABNQAECn8bAAMSAAcKQAejcwD8AAASAAYK1gWjcwD8AAADAAYKAgcTSAD0AAAAAA==.',
Ma='Madax:BAABNQAECn8lAAIYAAkKehi3DQDuAQAYAAkKehi3DQDuAQABNQAECgoKJAAEACAUAA==.Mambos:BAAANQADCggICAAAAA==.Manach:BAAANQAECgEIAQAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAABNQAECn8rAAIhAAkKYBX2MwAOAgAhAAkKYBX2MwAOAgAAAA==.Meganfox:BAAANQAECgQJCAABNQAECgoKGwAIAO0dAA==.Melinara:BAAANQADCgYIBgAAAA==.Merilde:BAAANQAECgcIDgAAAA==.Metrolinea:BAABNQAECn8lAAILAAoKpCGJCgAjAgALAAoKpCGJCgAjAgAAAA==.',
Mi='Micalknight:BAAANQADCggICgAAAA==.Milliy:BAABNQAECn8XAAMaAAkKhgXoHQAtAQAaAAgKBgboHQAtAQASAAMKQQLgQQBeAAAAAA==.Minamel:BAAANQAECgEIAQABNQAECgcIDQAGAAAAAA==.Minuette:BAAANQABCgMIAwAAAA==.Missbehaving:BAAANQAECgcIEAAAAA==.Misstigger:BAAANQABCgQIBAAAAA==.Mistea:BAAANQABCgYIBgAAAA==.',
Mo='Mojorisin:BAAANQADCgUIBgAAAA==.Morefire:BAABNQAECn8mAAIBAAkK9hrZJgDpAgABAAkK9hrZJgDpAgAAAA==.Mosmos:BAAANQAECgQIBAAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAABNQAECn8hAAMZAAcK4gKoRwDwAAAZAAcK4gKoRwDwAAAeAAIKHgJFdwA4AAAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAABNQAECn8ZAAICAAcKwBrPDgAGAgACAAcKwBrPDgAGAgAAAA==.',
Na='Nalassa:BAABNQAECn8fAAIDAAoKNBgcAwB3AgADAAoKNBgcAwB3AgAAAA==.Nannette:BAAANQAECgYIDQAAAA==.Narag:BAABNQAECn8bAAIIAAcKRRPxNABTAQAIAAcKRRPxNABTAQAAAA==.',
Ne='Neph:BAAANQAECggIAgAAAA==.Nephorma:BAAANQADCggJCgAAAA==.Newport:BAABNQAECn8jAAMcAAgKAh3JCQAmAgAcAAgKAh3JCQAmAgAMAAMKtA1u9QCqAAAAAA==.',
Ni='Niara:BAABNQAECn8mAAIPAAgKSBH5BwA3AQAPAAgKSBH5BwA3AQAAAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAABNQAECn8kAAMcAAoKRhPBGQCMAQAcAAoKRhPBGQCMAQAWAAEKMgJ8OQApAAAAAA==.Nisle:BAAANQABCggICgABNQAECgkJLgAQAMwRAA==.Nithén:BAAANQAECgUIDQAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Nonenight:BAAANQADCgIIAgABNQAECgoKIwAiALcIAA==.Nowhere:BAAANQAECgUIBwABNQAECgcIBwAGAAAAAA==.Nowon:BAABNQAECn8jAAIiAAoKtwitJwDRAAAiAAoKtwitJwDRAAAAAA==.',
Nu='Nudream:BAAANQAECgQICwAAAA==.Nuka:BAAANQAECgQIBQAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgcIBwAGAAAAAA==.',
Oo='Oomdeath:BAAANQADCgIIAgAAAA==.',
Op='Opalyte:BAAANQAECgUIDwAAAA==.',
Oq='Oqisa:BAAANQADCgMIAwABNQAECgUIBQAGAAAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAABNQAECn8eAAIIAAYKxACaQwFZAAAIAAYKxACaQwFZAAAAAA==.',
Ot='Othril:BAAANQAECgEIAQAAAA==.',
Ov='Overtavo:BAABNQAECn8gAAQBAAkKGRh7aQAgAgABAAgKThd7aQAgAgAfAAEK2xwYaQBPAAAgAAEKAAC1KwA/AAAAAA==.',
Pa='Pacobell:BAAANQADCggIEgAAAA==.Pakoros:BAABNQAECn8qAAIcAAgKnyJOIgDeAgAcAAgKnyJOIgDeAgAAAA==.Palamar:BAABNQAECn8ZAAIHAAcKpgQTgADMAAAHAAcKpgQTgADMAAAAAA==.Pallyanne:BAAANQADCgIIAgAAAA==.Pandsala:BAABNQAECn8aAAIZAAoKhhr5BgB/AgAZAAoKhhr5BgB/AgABNQAECgoKMQATAKIkAA==.Papo:BAAANQADCgcIBwAAAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAABNQAECn8ZAAIIAAUK8waR8gAcAQAIAAUK8waR8gAcAQAAAA==.',
Pg='Pgorlelgy:BAABNQAECn8fAAIIAAcKYRbXdQAkAgAIAAcKYRbXdQAkAgAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.Phucca:BAAANQADCggICAABNQAECgQIDgAGAAAAAA==.',
Pl='Platious:BAAANQAECgcIEAAAAA==.',
Po='Pookaboo:BAABNQAECn8WAAIBAAcKSwLhfQCHAAABAAcKSwLhfQCHAAAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAACNQAFFH8LAAIeAAUKfgh1CgBQAQAeAAUKfgh1CgBQAQA1AAQKfyMAAh4ACgryGM4YAIoCAB4ACgryGM4YAIoCAAE1AAUUBQoLAB4AfggA.',
Pu='Purdie:BAAANQADCgEIAQABNQAECgcIDgAGAAAAAA==.Purdiemonk:BAAANQADCgQIBAAAAA==.Purdienir:BAAANQADCgQJBAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECgcIDgAGAAAAAA==.',
Py='Pyrolock:BAABNQAECn8XAAMgAAkKMSV2AQBGAwAgAAgKACV2AQBGAwABAAgK+CLAFgAuAwAAAA==.',
['Pì']='Pìke:BAAANQADCgMJAwAAAA==.',
Qe='Qeesa:BAAANQAECgUIBQAAAA==.',
Ra='Radzog:BAAANQAECgYIBgAAAA==.Rafikie:BAAANQADCggIDQAAAA==.Ranni:BAABNQAECn8YAAMcAAkKtBA0cQC4AQAcAAgKYxA0cQC4AQAMAAUKpA3rzQD3AAABNQAECgoKHwADADQYAA==.Rawmeat:BAABNQAECn8dAAMeAAcKhxRYKgDVAQAeAAcKhxRYKgDVAQAZAAUKJA8OZgCiAAAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renix:BAAANQAECgQIBQAAAA==.Reno:BAAANQADCgcIBwAAAA==.',
Rh='Rhainnón:BAAANQAECgcIDQAAAA==.Rheã:BAAANQAECgUIDwAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAABNQAECn8ZAAILAAkKlhvzbwCeAgALAAkKlhvzbwCeAgAAAA==.',
Ro='Roombaa:BAAANQADCgYIBgAAAA==.Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sack:BAAANQAECgQIBgABNQAECggIFAAMAJAYAA==.Saetyl:BAAANQADCgUIBwAAAA==.Samsius:BAAANQABCgIIAgAAAA==.Sanctity:BAAANQAECgQIBwAAAA==.Sarson:BAAANQAECgIIAgAAAA==.Satine:BAAANQADCggIEgAAAA==.Saïma:BAAANQADCgYIBAABNQAECgcIDwAGAAAAAA==.',
Sc='Scratlord:BAAANQAECgQIDwAAAA==.',
Se='Sevinas:BAAANQAECgYIDAAAAA==.',
Sh='Shadeira:BAAANQAECgcIBwAAAA==.Shamthis:BAABNQAECn8mAAMMAAkK9A5rcQDMAQAMAAgKeA5rcQDMAQAcAAMK7QLHDQFMAAAAAA==.Shamwoww:BAAANQAFFAIIAgABNQAFFAUKCwAeAH4IAA==.Shelly:BAAANQADCgcIGwAAAA==.Shlumpa:BAAANQAECgUIBwAAAA==.Shlumpcane:BAAANQAECggIDwAAAA==.Shokcz:BAAANQAECgQICQAAAA==.Shámjackson:BAACNQAFFH8RAAIcAAUKbSPjAQD4AQAcAAUKbSPjAQD4AQA1AAQKfygAAhwACQowJuwBAMkDABwACQowJuwBAMkDAAAA.',
Si='Silvey:BAABNQAECn8aAAMiAAgKth2qHgCkAgAiAAgKth2qHgCkAgAjAAEKAADpcAAtAAAAAA==.Sinroot:BAAANQADCgQIBAAAAA==.Sithknight:BAAANQABCgQIBgAAAA==.Sithtracker:BAAANQABCgYICAAAAA==.Sizzurp:BAAANQAECgMIAwAAAA==.',
Sk='Skeletorque:BAAANQAECgYIDAAAAA==.',
Sm='Smallwdruid:BAAANQADCgIIAgAAAA==.',
Sn='Sneezeweed:BAAANQAECgMIAwAAAA==.Snow:BAAANQADCgcIBwABNQAECgoKOwATAMwjAA==.Snowfawn:BAAANQAECgYIBwABNQAECggIFgABAFcIAA==.Snusnurae:BAAANQAECgIIAgAAAA==.',
So='Soape:BAAANQAECgcIDgAAAA==.',
Sp='Specialist:BAAANQAECggIDgABNQAECgoKGwAIAO0dAA==.Splishsplásh:BAAANQAECgYIDAAAAA==.Spooties:BAAANQAECgMIAwAAAA==.Spoots:BAAANQAECgIIAQAAAA==.Spooty:BAAANQAECggICAAAAA==.Sprattyboii:BAAANQAECgQIBwAAAA==.',
Sq='Squishydk:BAAANQADCgUICgABNQAECgcIHgAJADUaAA==.',
Ss='Sscarlet:BAAANQAECgUIDwAAAA==.',
St='Staltis:BAAANQAECgUIBQABNQAECgkJLgAQAMwRAA==.Starzia:BAABNQAECn8fAAIkAAcK0At7AgArAQAkAAcK0At7AgArAQAAAA==.Storee:BAABNQAECn8kAAIBAAgKYgyoRQAAAQABAAgKYgyoRQAAAQAAAA==.',
Su='Sunk:BAABNQAECn8aAAIBAAgKMRNHjADIAQABAAgKMRNHjADIAQAAAA==.',
Sw='Swiftblossom:BAAANQADCgUIIAAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcJCwABNQAECgUIBAAGAAAAAA==.Talarus:BAAANQAECgQIBwAAAA==.Tanadria:BAAANQAECgYIBgAAAA==.Tapioca:BAAANQAECgIIAgAAAA==.Taterdot:BAABNQAECn8iAAMgAAgKfR4bAwDUAgAgAAgKfR4bAwDUAgAfAAIKkCDoQAC/AAAAAA==.',
Te='Telm:BAAANQAECgcIDQAAAA==.Tentilious:BAAANQADCgMIAwAAAA==.Tetocoochie:BAAANQADCgcIBwAAAA==.Tetsu:BAAANQAECgEIAQAAAA==.',
Th='Thaka:BAAANQADCgcIBwAAAA==.Thaÿne:BAAANQAECgMIBQAAAA==.Thebestpally:BAABNQAECn86AAMJAAoKkhqOBQCoAQAJAAgKCBuOBQCoAQAHAAYKKQ0PoQCcAAAAAA==.Thenemisis:BAAANQAECgQIBgAAAA==.Thiccidàn:BAAANQADCgYIDAABNQAECgQIDAAGAAAAAA==.Thiccsister:BAAANQADCgQIBAABNQAECgQIDAAGAAAAAA==.Thiccstraza:BAAANQAECgQIDAAAAA==.',
Ti='Tidds:BAAANQAECgQICwAAAA==.Tinker:BAAANQADCgYIDAAAAA==.',
To='To:BAAANQAECggIEwAAAA==.Tootsy:BAAANQADCgcIBwAAAA==.Totemdown:BAACNQAFFH8dAAIcAAcKbyNlAQC8AgAcAAcKbyNlAQC8AgA1AAQKfyYAAhwACgqMJWIEAKcDABwACgqMJWIEAKcDAAE1AAQKBQgJAAYAAAAA.',
Tr='Traedaei:BAAANQADCgQIBAAAAA==.Trazarath:BAABNQAECn86AAMFAAoKuxTeDgBvAgAFAAoK+BHeDgBvAgAQAAcKlRJwCwCoAQAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgIIAwABNQAECgYIDAAGAAAAAA==.',
Un='Untiler:BAAANQADCggICAAAAA==.',
Us='Usdaprime:BAAANQAECgYICAABNQAECgYIDAAGAAAAAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECgcIGwABNQAECggIKwAGAAAAAQ==.',
Va='Vaelra:BAAANQAECggIDQABNQAECgoKHwADADQYAA==.Valedaren:BAAANQADCgUIBgAAAA==.Valefyre:BAAANQAECgEIAQAAAA==.Vance:BAAANQAECgQIBAAAAA==.Varala:BAAANQAECgEIAQAAAA==.',
Ve='Vel:BAACNQAFFH8MAAIOAAYKABZuBwCjAQAOAAYKABZuBwCjAQA1AAQKf1YAAw4ACgplJpUBAOcDAA4ACgplJpUBAOcDACEAAwqEIO5nAAEBAAAA.Velgrave:BAAANQAECggIAwABNQAFFAYIDAAOAAAWAA==.Veritas:BAABNQAECn8jAAIeAAoKHRwIEwDRAgAeAAoKHRwIEwDRAgAAAA==.Veskara:BAAANQAECgEIAQAAAA==.',
Vo='Voltsadin:BAAANQADCgEIAQABNQAECggIIgAgAH0eAA==.',
Vy='Vylana:BAABNQAECn8uAAIcAAcKfRhKYgDnAQAcAAcKfRhKYgDnAQABNQAFFAUICQAIAE0QAA==.',
['Và']='Vàlkyrie:BAAANQAFFAEIAQAAAA==.',
['Vè']='Vèl:BAAANQAECgIIAgABNQAFFAYIDAAOAAAWAA==.',
Wa='Warity:BAAANQAECgYIDwAAAA==.',
We='Weneyan:BAAANQADCgYIBgAAAA==.Wetdotdruid:BAAANQAECgQIBAAAAA==.Wetdotpal:BAABNQAECn8hAAIJAAgKQBFRDwAaAQAJAAgKQBFRDwAaAQAAAA==.Wetdotrogue:BAAANQAECgEIAQAAAA==.Wetdotthirst:BAAANQAECgYIBwAAAA==.Wetdotwar:BAAANQAECgMIAwAAAA==.',
Wh='Whiteabyss:BAABNQAECn8rAAMBAAkKMxJsFgCbAQABAAkKMxJsFgCbAQAfAAEKAAC6fAAwAAAAAA==.',
Wr='Wraith:BAAANQAECgYICwAAAA==.',
Xe='Xeral:BAAANQADCgEIAQAAAA==.Xerxseizee:BAAANQAECgIIAgAAAA==.',
Xo='Xomby:BAABNQAECn8ZAAMkAAcKtA8CAwAJAQAkAAcKtA8CAwAJAQAeAAUKiAjZSwDnAAAAAA==.',
['Xì']='Xìon:BAABNQAECn8tAAQdAAkKbhg1MABRAgAdAAgKfRs1MABRAgAOAAUKrgWnrQCZAAAhAAIKBAOMbwAjAAAAAA==.',
Ya='Yayrri:BAAANQAECgYIDgAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQAECgIIAgAAAA==.',
Yu='Yungstabby:BAAANQADCgYIBgABNQAECgYIFgAZAF8SAA==.',
Za='Zahne:BAAANQAECgYIBgABNQAECgoKMAABAG4jAA==.Zatarra:BAAANQADCgUIBwAAAA==.Zavya:BAAANQADCgMJAwABNQAECgIIAgAGAAAAAA==.',
Ze='Zex:BAAANQADCgUIBwABNQAECgcIHwAiAHEKAA==.Zextron:BAABNQAECn8fAAIiAAcKcQr8IQDwAAAiAAcKcQr8IQDwAAAAAA==.',
Zi='Ziaya:BAAANQAECgIIAgAAAA==.',
Zo='Zolaeus:BAAANQADCgcIDQABNQAECgUIBAAGAAAAAA==.',
Zu='Zuboo:BAABNQAECn8dAAIiAAcKVwQzKwDAAAAiAAcKVwQzKwDAAAAAAA==.',
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
