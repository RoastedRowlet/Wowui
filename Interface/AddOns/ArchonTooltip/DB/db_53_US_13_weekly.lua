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

local lookup = {'Warlock-Demonology','Monk-Brewmaster','Priest-Holy','Priest-Shadow','Paladin-Holy','Rogue-Assassination','Mage-Arcane','Mage-Frost','Paladin-Retribution','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Druid-Balance','Druid-Feral','Paladin-Protection','Druid-Guardian','Shaman-Elemental','Druid-Restoration','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Warrior-Fury','Hunter-Marksmanship','Shaman-Enhancement','Monk-Mistweaver','Warrior-Arms','Evoker-Preservation','Shaman-Restoration','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Discipline',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abisio:BAAANQAECgEJAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAABNQAECn8qAAIBAAoK5yGXHQAOAwABAAoK5yGXHQAOAwAAAA==.Acursedpeen:BAAANQAECgIIAwAAAA==.',
Ad='Aderna:BAAANQAECgQIBgAAAA==.Adoryn:BAEBNQAECn8gAAICAAkKeglDDQAmAQACAAkKeglDDQAmAQAAAA==.',
Ae='Aelara:BAABNQAECn8dAAMDAAoKeBQxTADOAQADAAoKeBQxTADOAQAEAAQKyAg5OwCSAAABNQAECgoKIAAFAI0UAA==.Aessan:BAAANQAECgcIDgAAAA==.Aethelred:BAAANQADCgYIBgAAAA==.',
Ag='Agares:BAABNQAECn8sAAIGAAoKghc9GABMAQAGAAoKghc9GABMAQAAAA==.',
Ai='Aisathya:BAABNQAECn8ZAAMHAAkKmxp4ygDwAQAHAAgKRht4ygDwAQAIAAEKmBZ0PgBIAAAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Al='Aleysia:BAABNQAECn8gAAMFAAoKjRSxIwB2AgAFAAoKjRSxIwB2AgAJAAIKpASHgwFVAAAAAA==.Alivar:BAAANQABCgIIAgAAAA==.',
Am='Amberfox:BAABNQAECn8eAAIKAAkKVyDqHQCjAgAKAAkKVyDqHQCjAgAAAA==.Amberscale:BAABNQAECn87AAMLAAoKgh6HBgAhAwALAAoKgh6HBgAhAwAMAAIKxRhxEgCJAAAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQAECgIIAwANAAAAAA==.Ancientuur:BAAANQADCgYIBgABNQAECgIIAwANAAAAAA==.Andazaren:BAABNQAECn8+AAIJAAkKRQ0xlABjAQAJAAkKRQ0xlABjAQAAAA==.Andracca:BAAANQAECgIIAgAAAA==.Angrulus:BAABNQAECn81AAIKAAoKaBo2JgB8AgAKAAoKaBo2JgB8AgAAAA==.Animal:BAAANQAECgQIAgAAAA==.Animlshiftr:BAABNQAECn8VAAMOAAkKoAXNOQAVAQAOAAkKnwXNOQAVAQAPAAMKoAMUOwBOAAAAAA==.',
Ap='Apollo:BAABNQAECn8gAAIBAAcKyQeTmADxAAABAAcKyQeTmADxAAAAAA==.',
Ar='Arixx:BAAANQABCgIIAgAAAA==.Arrøw:BAAANQADCgQIBAAAAA==.Aryllyn:BAAANQAECgMIBwAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQAECgQIBgABNQAECgUICgANAAAAAA==.',
At='Atris:BAAANQADCgcIBwAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQAECgQIBAABNQAECggIJwAQAOkRAA==.Banmoor:BAAANQAECgQIDAAAAA==.',
Be='Bearett:BAABNQAECn8zAAIRAAgKUB7bDwBjAgARAAgKUB7bDwBjAgAAAA==.Belyrune:BAABNQAECn8XAAIHAAkKOgVxSQEUAQAHAAkKOgVxSQEUAQABNQAECgoKRQASAKgWAA==.Belysurge:BAABNQAECn9FAAISAAoKqBZFJQAgAgASAAoKqBZFJQAgAgAAAA==.Bernd:BAABNQAECn8kAAIRAAkKBwrXKQADAQARAAkKBwrXKQADAQAAAA==.Beörn:BAABNQAECn8mAAITAAgKmSXRBQBlAwATAAgKmSXRBQBlAwAAAA==.',
Bi='Birgir:BAAANQAECgEIAQAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAABNQAECn8aAAIUAAkKiwuyKgANAQAUAAkKiwuyKgANAQAAAA==.',
Br='Braids:BAAANQAECgUIBwAAAA==.Breezy:BAABNQAECn81AAIJAAoKAR51LgB+AgAJAAoKAR51LgB+AgAAAA==.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAABNQAECn8gAAMVAAkKaho7GAD7AQAVAAkKmhg7GAD7AQAWAAIKhB3hXwCgAAAAAA==.',
Bu='Buttrbiskit:BAAANQAECggIDwAAAA==.',
By='Byanca:BAABNQAECn8XAAIUAAcKRwP+SgDOAAAUAAcKRwP+SgDOAAAAAA==.',
Ca='Caine:BAABNQAECn8hAAIXAAkK/hnpDACxAQAXAAkK/hnpDACxAQAAAA==.Callen:BAAANQADCgEIAQAAAA==.Carlonus:BAAANQADCggICwABNQAECgoKMgAMAGkRAA==.Casey:BAAANQAECgUIDwAAAA==.Castyblasty:BAABNQAECn8zAAMHAAoKDBXCOwA3AgAHAAoKDBXCOwA3AgAIAAEKAAkiRQA5AAAAAA==.Cataaria:BAAANQAECgYIBgABNQAECgcIDgANAAAAAA==.',
Ce='Cellina:BAABNQAECn8UAAIUAAgKrwi0OwCYAAAUAAgKrwi0OwCYAAAAAA==.',
Ch='Chiman:BAAANQADCgcJCQABNQAECgUIBAANAAAAAA==.Chromatica:BAAANQADCgYIBgAAAA==.',
Ci='Cignus:BAAANQAECggICQAAAA==.',
Cl='Classá:BAABNQAECn86AAQTAAoKvh6wCwAPAwATAAoKvh6wCwAPAwAOAAkKrBuYHgDVAgARAAYK4A7LLgAkAQAAAA==.',
Co='Codedd:BAAANQADCgYIDAAAAA==.Corlys:BAABNQAECn8hAAMJAAkKNhIfoADhAQAJAAkKNhIfoADhAQAQAAEKAAC1ewAhAAAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAABNQAECn8bAAIKAAgKZwaKqAAcAQAKAAgKZwaKqAAcAQAAAA==.Crue:BAABNQAECn8wAAMTAAkKTBJ+LwAtAQATAAcKow5+LwAtAQAOAAkKLgeIPQACAQAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIJAgAAAA==.Curthar:BAAANQAECgMIAgABNQAECgQICQANAAAAAA==.',
Cy='Cynboom:BAAANQADCgcIHwAAAA==.Cyndee:BAABNQAECn83AAIYAAoKwBV2BgAjAgAYAAoKwBV2BgAjAgAAAA==.Cynnafrost:BAAANQADCgQICgAAAA==.Cytenk:BAAANQAECgUICQAAAA==.',
Da='Dadda:BAABNQAECn9AAAIZAAoKaB9iBwC0AgAZAAoKaB9iBwC0AgAAAA==.Dagad:BAAANQADCgIIAgAAAA==.Daisynukes:BAABNQAECn8ZAAIHAAoKPQyHXQDTAQAHAAoKPQyHXQDTAQABNQAECgoKLAASAMoOAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAABNQAECn8nAAMQAAgK6RGfLgBpAQAQAAgK6RGfLgBpAQAJAAEKDgoUewEqAAAAAA==.Dankdruid:BAAANQADCgUICgABNQAECgUIEQANAAAAAA==.Darkschi:BAABNQAECn8lAAIUAAkKswn4IABcAQAUAAkKswn4IABcAQAAAA==.Darthsith:BAAANQABCgQIBAAAAA==.Darthwing:BAAANQADCgcIDgAAAA==.Dartos:BAABNQAECn9FAAIVAAoKySP5BQACAwAVAAoKySP5BQACAwAAAA==.',
De='Deepmagic:BAAANQAECggIDQAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.Destrûction:BAAANQADCgUIBQAAAA==.',
Di='Diluvium:BAABNQAECn8hAAIQAAkKlRY3GgAfAgAQAAkKlRY3GgAfAgAAAA==.Discodank:BAAANQAECgUIEQAAAA==.',
Dj='Djpleasant:BAACNQAFFH8OAAIIAAcKIhNOAQBqAQAIAAcKIhNOAQBqAQA1AAQKf0UAAwgACgqaJC8CAFMDAAgACgo/JC8CAFMDAAcABgomIcKIAGcBAAAA.',
Do='Dontcare:BAABNQAECn8oAAMKAAoK0x8JIwCKAgAKAAkKeiEJIwCKAgAZAAMKiQ8dZQCXAAAAAA==.',
Dw='Dwailn:BAAANQABCgMIAwAAAA==.',
['Dû']='Dûo:BAABNQAECn80AAMSAAoKixqnPQCiAQASAAkK/R2nPQCiAQAaAAMKLAvGMgBMAAAAAA==.',
Ea='Eatmorpizza:BAABNQAECn8UAAITAAUK1hFGNgACAQATAAUK1hFGNgACAQAAAA==.',
Ee='Eegnormu:BAAANQAECgQICQAAAA==.Eegroll:BAABNQAECn8+AAQCAAoKZhtZBwDIAgACAAoKWRtZBwDIAgAUAAgKOxN8MwB6AQAbAAcKqgVxLQAAAQAAAA==.',
Eg='Egraw:BAABNQAECn8eAAMcAAgKLyFGVQDJAQAcAAgKLyFGVQDJAQAXAAEK/yDJMABaAAAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Em='Emilwhaury:BAAANQADCgYIBgAAAA==.',
Ep='Epia:BAABNQAECn8iAAMUAAoK/xKgGQCnAQAUAAoK/xKgGQCnAQACAAIKCAbALQBPAAAAAA==.',
Es='Esdéath:BAABNQAECn9NAAIDAAkKmR9+GwAFAwADAAkKmR9+GwAFAwAAAA==.Essaila:BAABNQAECn8xAAIPAAoKehEaFAC7AQAPAAoKehEaFAC7AQAAAA==.',
Et='Etherwalker:BAABNQAECn8WAAIcAAgK2hrebQBJAgAcAAgK2hrebQBJAgAAAA==.',
Ex='Excision:BAABNQAECn8lAAILAAgKzAsYDwAbAQALAAgKzAsYDwAbAQAAAA==.',
Fa='Fahbio:BAABNQAECn8aAAIQAAcKrwQtOAChAAAQAAcKrwQtOAChAAAAAA==.Faleros:BAAANQADCgMIAwAAAA==.Fanskar:BAAANQAECgEIAQABNQAECgQIBAANAAAAAA==.Fatallock:BAABNQAECn99AAIBAAoKLhLjOAD9AQABAAoKLhLjOAD9AQAAAA==.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQAECgEIAQAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgcIBwANAAAAAA==.',
Fl='Flaildh:BAAANQAECgYIBgAAAA==.Flailuid:BAAANQAECgMIBwAAAA==.',
Fo='Forthstryke:BAAANQADCggIEQAAAA==.',
Fr='Fresita:BAABNQAECn8eAAMOAAYKAQ1GTQC8AAAOAAYKAQ1GTQC8AAAPAAQKpAW+NwBAAAAAAA==.Fridaychill:BAABNQAECn9FAAIUAAoK7x9BCgCZAgAUAAoK7x9BCgCZAgAAAA==.Frozarke:BAABNQAECn8yAAMMAAoKaRHdCAD/AQAMAAoKaRHdCAD/AQAdAAEKVACxVgATAAAAAA==.',
Fu='Fudd:BAABNQAECn8XAAIKAAcKJQ61ngAwAQAKAAcKJQ61ngAwAQAAAA==.Funk:BAAANQABCgIIAgABNQAECgQIAgANAAAAAA==.Fupa:BAAANQAECgUICAAAAA==.Furryz:BAAANQADCgYIBgABNQAECggIGgACAGUkAA==.',
Ga='Garou:BAABNQAECn8UAAISAAgKkBhMVQAlAgASAAgKkBhMVQAlAgAAAA==.Garres:BAABNQAECn8zAAQPAAoKxBogCAAnAgAPAAoKYxogCAAnAgARAAgKCRYnGgB7AQAOAAMKYAN3mwBtAAAAAA==.',
Ge='Geedorah:BAAANQADCgUIBQABNQAECgoKQAAFAKIkAA==.Genius:BAAANQAECgYIEgAAAA==.',
Gi='Gibley:BAAANQAECgQIBAAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAAANQAECgUIEQAAAA==.Gnomie:BAAANQAECgYICwAAAA==.Gnomio:BAAANQAECgYICwAAAA==.',
Go='Gouge:BAAANQAECggIQgAAAQ==.',
Gr='Granadithios:BAAANQADCgIIAgAAAA==.Griffynshu:BAABNQAECn8bAAITAAkKrhT5KgDGAQATAAkKrhT5KgDGAQAAAA==.Grrv:BAAANQABCgQIBAAAAA==.Grudgetotem:BAABNQAECn8hAAMeAAoKnRnqPQDtAQAeAAoKnRnqPQDtAQASAAEKSBVTLwE6AAAAAA==.Grunewald:BAAANQAECgQIBwAAAA==.',
Gu='Guinn:BAAANQADCggIDgABNQAECgoKMgAMAGkRAA==.Gungnir:BAABNQAECn8xAAIcAAoK6CEDEQB6AwAcAAoK6CEDEQB6AwAAAA==.',
Ha='Haki:BAAANQAECgQIBwAAAA==.Handiboy:BAABNQAECn8vAAIDAAoK1CUaCQB7AwADAAoK1CUaCQB7AwAAAA==.Hardison:BAAANQADCgYIBgAAAA==.Hayate:BAAANQAECgQIDgAAAA==.',
He='Healabull:BAAANQADCgYIDgABNQAECgcIHAAWABkSAA==.Heimdall:BAABNQAECn9AAAIFAAoKoiSRBQChAwAFAAoKoiSRBQChAwAAAA==.Hellabear:BAAANQADCgQIBAAAAA==.Hellaholy:BAABNQAECn8tAAMQAAkK1ROEGgBnAQAQAAgKuhWEGgBnAQAJAAgKxwduywABAQAAAA==.Hellavva:BAAANQAECgYIBgAAAA==.Help:BAAANQAECgUIBwABNQAECgoKOgAHAEwfAA==.Henchling:BAABNQAECn8rAAMeAAoKaRqjPwBiAgAeAAoKaRqjPwBiAgASAAgKwgtfYgAkAQAAAA==.',
Hi='Hina:BAAANQADCggIDgAAAA==.',
Ho='Holexios:BAAANQAECgUIBAAAAA==.Horine:BAABNQAECn8XAAIKAAkKFgTbuQD6AAAKAAkKFgTbuQD6AAAAAA==.',
['Hö']='Hölyhell:BAAANQADCgUIBwAAAA==.',
Ic='Icieblade:BAAANQAECggIEgAAAA==.',
Im='Immeira:BAABNQAECn85AAIeAAoKeRtUGwCvAgAeAAoKeRtUGwCvAgAAAA==.',
Ir='Ira:BAAANQAECgUIDQABNQAECgoKLQAOAHgTAA==.',
Ja='Jackiix:BAAANQADCgYIBgAAAA==.Jackmends:BAACNQAFFH8HAAIDAAMKCiLBFAAmAQADAAMKCiLBFAAmAQA1AAQKf0QAAwMACgpgJCAHAIwDAAMACgpgJCAHAIwDAAQAAgovA1ZwAEcAAAAA.Jacksprouts:BAAANQAECggIDQAAAA==.Jacktides:BAAANQAECgEIAQABNQAFFAMIBwADAAoiAA==.Jarryl:BAAANQAECggIEAAAAA==.',
Je='Jeffrez:BAAANQAECgQIBQAAAA==.Jelerious:BAAANQAECggICAAAAA==.Jenoside:BAAANQAECggIMAAAAQ==.',
Ji='Jindu:BAAANQAECggICAAAAA==.',
Jo='Journei:BAABNQAECn8vAAMeAAkK9RjGMwAcAgAeAAgKOBfGMwAcAgASAAYK8ASjwwALAQAAAA==.',
Ju='Judging:BAABNQAECn8jAAMFAAkK9we8ngBIAQAFAAkK9we8ngBIAQAJAAgKoRB7xAANAQAAAA==.Jurb:BAAANQAECggIEAAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIGQAAAA==.Kaitos:BAAANQAECgQICQAAAA==.',
Ke='Kegz:BAABNQAECn8aAAMCAAgKZSTBAwBOAwACAAgKZSTBAwBOAwAUAAIK+AoxQQB5AAAAAA==.Kelendrian:BAAANQAECgUIBQAAAA==.Kellayna:BAABNQAECn8UAAIJAAYK6wXeHAHvAAAJAAYK6wXeHAHvAAAAAA==.Keylö:BAABNQAECn8wAAIVAAkKfheBGgDiAQAVAAkKfheBGgDiAQAAAA==.',
Kh='Khoulethius:BAAANQADCgYIBwAAAA==.',
Ki='Kimbot:BAABNQAECn8fAAMKAAoKJheYRQCbAgAKAAoKJheYRQCbAgAZAAEKAACzjgAxAAAAAA==.Kimigosa:BAAANQAECggIBwAAAA==.',
Kl='Klerik:BAACNQAFFH8VAAIBAAQK1xssDQARAQABAAQK1xssDQARAQA1AAQKf0QABAEACgqNIwASAEcDAAEACgqNIwASAEcDAB8ABgo/Di8nAD0BACAAAQoKBiQ0ACoAAAAA.',
Kn='Kníghtmare:BAAANQAECgUICgAAAA==.',
Ko='Koragg:BAACNQAFFH8jAAIWAAcKByLRAgDyAQAWAAcKByLRAgDyAQA1AAQKfzsAAhYACgoSI5wRACADABYACgoSI5wRACADAAAA.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgUIBQAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAABNQAECn8gAAILAAkKoAv+DwAKAQALAAkKoAv+DwAKAQAAAA==.',
Kr='Kratus:BAAANQAECgEIAQAAAA==.Krissia:BAABNQAECn86AAMhAAoKOhexMAAhAgAhAAoKOhexMAAhAgAVAAUKMgbclgDUAAAAAA==.',
Ky='Kymerah:BAAANQABCgYICAAAAA==.Kyntaliia:BAAANQADCgYIDAAAAA==.',
['Kî']='Kîn:BAABNQAECn8aAAIiAAcK9xZvMgCuAQAiAAcK9xZvMgCuAQAAAA==.',
La='Lailey:BAAANQADCggICAAAAA==.Laisera:BAABNQAECn8hAAIDAAoK7AlPewCoAQADAAoK7AlPewCoAQAAAA==.Lalipop:BAABNQAECn8aAAIDAAcKPiGcTwA1AgADAAcKPiGcTwA1AgAAAA==.Landroval:BAABNQAECn8VAAILAAkKMRC/GAC9AQALAAkKMRC/GAC9AQAAAA==.Langedamort:BAAANQADCgEIAQAAAA==.Lastkissgbye:BAAANQABCgIIAgAAAA==.Lawson:BAABNQAECn8nAAIVAAkKlBCIIQChAQAVAAkKlBCIIQChAQAAAA==.',
Le='Leeoh:BAABNQAECn8rAAIHAAoKWwayrQAfAQAHAAoKWwayrQAfAQAAAA==.Leeohd:BAAANQAECgYIDwAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAABNQAECn8cAAITAAYKNwUwRAC3AAATAAYKNwUwRAC3AAAAAA==.',
Lo='Lovenky:BAAANQAECgIIAgAAAA==.',
Lu='Lujuria:BAABNQAECn8tAAIOAAoKeBP7GwDxAQAOAAoKeBP7GwDxAQAAAA==.Lumawig:BAAANQADCgcIBwAAAA==.Lunchdk:BAAANQAECgMIBgAAAA==.',
Ly='Lyreth:BAABNQAECn8iAAMOAAcKqAejcwD8AAAOAAYK1gWjcwD8AAATAAYKEAowOwDkAAAAAA==.',
Ma='Madax:BAABNQAECn81AAIcAAoKLB2BIgCaAgAcAAoKLB2BIgCaAgABNQAECgoKLAAGAIIXAA==.Mambos:BAAANQAECgQIBAAAAA==.Manach:BAAANQAECgMIBgAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAABNQAECn80AAIhAAkKthZoLQC8AQAhAAkKthZoLQC8AQAAAA==.Meganfox:BAAANQAECgQJCAABNQAECgoKKAAKANMfAA==.Melinara:BAAANQADCgYIBgAAAA==.Merilde:BAABNQAECn8fAAQTAAoK/xiTGAAAAgATAAgKtBaTGAAAAgARAAoKsBHSGgDOAQAOAAQK9Am5hAC+AAAAAA==.Metrolinea:BAABNQAECn8oAAIHAAoKpCE+LwAuAwAHAAoKpCE+LwAuAwAAAA==.',
Mi='Micalknight:BAAANQADCggICgAAAA==.Milliy:BAABNQAECn8XAAMPAAkKhgXoHQAtAQAPAAgKBgboHQAtAQAOAAMKQQIibQBWAAAAAA==.Minamel:BAAANQAECgEIAQABNQAECgcIDQANAAAAAA==.Minuette:BAAANQABCgMIAwAAAA==.Missbehaving:BAABNQAECn8ZAAMDAAgKTQp8dQA9AQADAAgKTQp8dQA9AQAEAAEKAAADkQAZAAAAAA==.Misstigger:BAAANQABCgQIBAAAAA==.Mistea:BAAANQABCgYIBgAAAA==.',
Mo='Mojorisin:BAAANQADCgUIBgAAAA==.Morefire:BAABNQAECn8xAAIBAAoK0hfZJgDpAgABAAoK0hfZJgDpAgAAAA==.Mosmos:BAAANQAECgQIBAAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAABNQAECn8lAAMDAAgK0wVMfgAjAQADAAgK0wVMfgAjAQAEAAIKHgJFdwA4AAAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAABNQAECn8ZAAICAAcKwBrPDgAGAgACAAcKwBrPDgAGAgAAAA==.',
Na='Nalassa:BAABNQAECn8fAAITAAoKNBj/FAAzAgATAAoKNBj/FAAzAgABNQAECgoKIAAFAI0UAA==.Nannette:BAAANQAECgYIEwAAAA==.Narag:BAABNQAECn8jAAIKAAkK2BJcYADAAQAKAAkK2BJcYADAAQAAAA==.',
Ne='Neph:BAAANQAECggIAgAAAA==.Nephorma:BAAANQADCggJCgAAAA==.Newport:BAABNQAECn8rAAMeAAgKAh14MQAnAgAeAAgKAh14MQAnAgASAAQKtA2ZswBwAAAAAA==.',
Ni='Niara:BAABNQAECn82AAMXAAoKRBH1DgCNAQAXAAoKRBH1DgCNAQAcAAEKIwdzFQEuAAAAAA==.Ninevolt:BAAANQADCgIIAgABNQAECgkJKQAgAM0eAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAABNQAECn8uAAMeAAoKtRPkSAC8AQAeAAoKtRPkSAC8AQAaAAEKMgJ8OQApAAAAAA==.Nisle:BAAANQABCggICgABNQAECgoKMgAMAGkRAA==.Nithén:BAABNQAECn8XAAMMAAUKPwLQHgBpAAAMAAUKBALQHgBpAAALAAMKAgK+NQBgAAAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Nonenight:BAAANQADCgIIAgABNQAECgoKLAAjAOcJAA==.Nowhere:BAAANQAECgUIBwABNQAECgcIBwANAAAAAA==.Nowon:BAABNQAECn8sAAIjAAoK5wlfNQA3AQAjAAoK5wlfNQA3AQAAAA==.',
Nu='Nudream:BAAANQAECgcIEgAAAA==.Nuka:BAAANQAECgQIBQAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgcIBwANAAAAAA==.',
Oo='Oomdeath:BAAANQADCgIIAgAAAA==.',
Op='Opalyte:BAABNQAECn8ZAAIDAAcK2AqxkQDrAAADAAcK2AqxkQDrAAAAAA==.',
Oq='Oqisa:BAAANQADCgMIAwABNQAECgUIBQANAAAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAABNQAECn8qAAIKAAYK3wCaQwFZAAAKAAYK3wCaQwFZAAAAAA==.',
Ot='Othril:BAAANQAECgEIAQAAAA==.',
Ov='Overtavo:BAABNQAECn8qAAQBAAoK2ReRRQDPAQABAAkKIheRRQDPAQAfAAEK2xzfKgBFAAAgAAEKAAC1KwA/AAAAAA==.',
Pa='Pacobell:BAAANQADCggIEgAAAA==.Pakoros:BAABNQAECn87AAIeAAoKniFXFADpAgAeAAoKniFXFADpAgAAAA==.Palamar:BAABNQAECn8hAAIJAAkKBwWUygADAQAJAAkKBwWUygADAQAAAA==.Pallyanne:BAAANQADCgIIAgAAAA==.Pandsala:BAABNQAECn8vAAIDAAoKMRweFAALAwADAAoKMRweFAALAwABNQAECgoKQAAFAKIkAA==.Papo:BAAANQADCgcIBwAAAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAABNQAECn8lAAIKAAcK4wWovQDyAAAKAAcK4wWovQDyAAAAAA==.',
Pg='Pgorlelgy:BAABNQAECn8kAAIKAAcKbxfXdQAkAgAKAAcKbxfXdQAkAgAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.Phucca:BAAANQADCggICAABNQAECgQIDgANAAAAAA==.',
Pl='Platious:BAABNQAECn8YAAIJAAgKjQ/vyACKAQAJAAgKjQ/vyACKAQAAAA==.',
Po='Pookaboo:BAABNQAECn8dAAIBAAgKOAKzxwCTAAABAAgKOAKzxwCTAAAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAACNQAFFH8LAAIEAAUKfgh1CgBQAQAEAAUKfgh1CgBQAQA1AAQKfy0AAgQACgrsG84YAIoCAAQACgrsG84YAIoCAAE1AAUUBQoLAAQAfggA.',
Pu='Purdie:BAAANQADCgEIAQABNQAECgcIDgANAAAAAA==.Purdiemonk:BAAANQADCgQIBAAAAA==.Purdienir:BAAANQADCgQJBAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECgcIDgANAAAAAA==.',
Py='Pyrolock:BAABNQAECn8XAAMgAAkKMSV2AQBGAwAgAAgKACV2AQBGAwABAAgK+CLAFgAuAwAAAA==.',
['Pì']='Pìke:BAAANQAECgcIBgAAAA==.',
Qe='Qeesa:BAAANQAECgUIBQAAAA==.',
Ra='Radzog:BAAANQAECgYICwAAAA==.Rafikie:BAAANQADCggIDQAAAA==.Ranni:BAABNQAECn8YAAMeAAkKtBA0cQC4AQAeAAgKYxA0cQC4AQASAAUKpA3rzQD3AAABNQAECgoKIAAFAI0UAA==.Rawmeat:BAABNQAECn8kAAMEAAgK4BNaHAByAQAEAAgK4BNaHAByAQADAAUKJA+RrwAIAQAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renix:BAAANQAECgQIBQAAAA==.Reno:BAAANQADCgcIBwAAAA==.',
Rh='Rhainnón:BAAANQAECgcIDQAAAA==.Rheã:BAAANQAECgUIDwAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAABNQAECn8ZAAIHAAkKlhvzbwCeAgAHAAkKlhvzbwCeAgAAAA==.',
Ro='Roombaa:BAAANQADCgYIBgAAAA==.Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sabrefang:BAAANQADCgcIDAAAAA==.Sack:BAAANQAECgQIBgABNQAECggIFAASAJAYAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sai:BAAANQADCggIDwAAAA==.Samsius:BAAANQABCgIIAgAAAA==.Sanctity:BAAANQAECgUIDAAAAA==.Sarson:BAAANQAECgIIAwAAAA==.Satine:BAAANQADCggIEgAAAA==.Saïma:BAAANQADCgYIBAABNQAECgcIDwANAAAAAA==.',
Sc='Scratlord:BAABNQAECn8fAAIZAAUKkwSZWwC2AAAZAAUKkwSZWwC2AAAAAA==.',
Se='Sevinas:BAABNQAECn8WAAIaAAcKFwh8IQBGAQAaAAcKFwh8IQBGAQAAAA==.',
Sh='Shadeira:BAAANQAECgcIBwAAAA==.Shamthis:BAABNQAECn8sAAMSAAoKyg5rcQDMAQASAAoKyg5rcQDMAQAeAAMK7QLHDQFMAAAAAA==.Shamwoww:BAACNQAFFH8FAAMeAAUK+Ai6HgB4AAAeAAMKWQC6HgB4AAASAAIKCgOPIwA/AAA1AAQKfxkAAx4ACAoBFbo2AA8CAB4ACAoBFbo2AA8CABIABAodD5acAJoAAAE1AAUUBQoLAAQAfggA.Shlumpa:BAAANQAECggIDwAAAA==.Shlumpcane:BAABNQAECn8ZAAIHAAYKyQ7+0gDZAAAHAAYKyQ7+0gDZAAAAAA==.Shokcz:BAAANQAECgQICQAAAA==.Shomba:BAAANQAECgEIAQAAAA==.Shámjackson:BAACNQAFFH8VAAIeAAUKpyPnBAAAAgAeAAUKpyPnBAAAAgA1AAQKfyoAAh4ACgpmJewBAMkDAB4ACgpmJewBAMkDAAAA.',
Si='Silvey:BAABNQAECn8kAAMjAAkKeB9TGQARAgAjAAkKeB9TGQARAgAiAAEKAADpcAAtAAAAAA==.Sinroot:BAAANQADCgQIBAAAAA==.Sithknight:BAAANQABCgQIBgAAAA==.Sizzurp:BAAANQAECgMIAwAAAA==.',
Sk='Skeletorque:BAABNQAECn8ZAAMWAAcKdgdbaQCDAAAWAAYKIwlbaQCDAAAVAAQKpAFSzgBQAAABNQAECggIDgANAAAAAA==.',
Sm='Smallwdruid:BAAANQAECggICAAAAA==.',
Sn='Sneezeweed:BAAANQAECgMIAwAAAA==.Snow:BAAANQADCgcIBwABNQAECgoKRQAFAN0lAA==.Snowfawn:BAAANQAECggIDgAAAA==.Snusnurae:BAAANQAECgIIAgAAAA==.',
So='Soape:BAABNQAECn8bAAIJAAkKngPG7QDLAAAJAAkKngPG7QDLAAAAAA==.',
Sp='Specialist:BAABNQAECn8aAAIDAAkKhB7wJACMAgADAAkKhB7wJACMAgABNQAECgoKKAAKANMfAA==.Splishsplásh:BAAANQAECgcIEgAAAA==.Spooties:BAAANQAECggIAwAAAA==.Spoots:BAAANQAECgcIBwAAAA==.Spooty:BAAANQAECggICAAAAA==.Sprattyboii:BAAANQAECgQIBwAAAA==.',
Sq='Squishydk:BAAANQADCgUICgABNQAECgkJIQAQAJUWAA==.',
Ss='Sscarlet:BAAANQAECggIEQAAAA==.',
St='Stabedyou:BAAANQAECgYIBgAAAA==.Staltis:BAAANQAECggICgABNQAECgoKMgAMAGkRAA==.Starzia:BAABNQAECn8nAAIkAAkKXgwyBQCGAQAkAAkKXgwyBQCGAQAAAA==.Storee:BAABNQAECn8uAAIBAAgK8wyapgCHAQABAAgK8wyapgCHAQAAAA==.',
Su='Sunk:BAABNQAECn8kAAIBAAkKfRI6WQCPAQABAAkKfRI6WQCPAQAAAA==.',
Sw='Swiftblossom:BAAANQADCgcILAAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcJCwABNQAECgUIBAANAAAAAA==.Talarus:BAAANQAECgQIBwAAAA==.Tanadria:BAAANQAECgYIBgAAAA==.Tapioca:BAAANQAECgIIAgAAAA==.Taterdot:BAABNQAECn8pAAMgAAkKzR4bAwDUAgAgAAkKzR4bAwDUAgAfAAIKkCDoQAC/AAAAAA==.',
Te='Telm:BAAANQAECgcIDQAAAA==.Tentilious:BAAANQADCgMIAwAAAA==.Tetocoochie:BAAANQADCgcIBwAAAA==.Tetsu:BAAANQAECgEIAQAAAA==.',
Th='Thaka:BAAANQADCgcIBwAAAA==.Thaÿne:BAAANQAECgMIBQAAAA==.Thebestpally:BAABNQAECn9OAAMQAAoK8x2ZBwCqAgAQAAoK8x2ZBwCqAgAJAAYK9g/d5QDXAAAAAA==.Thenemisis:BAAANQAECgQIBgAAAA==.Thiccidàn:BAAANQADCgYIDAABNQAECgQIDAANAAAAAA==.Thiccsister:BAAANQADCgQIBAABNQAECgQIDAANAAAAAA==.Thiccstraza:BAAANQAECgQIDAAAAA==.',
Ti='Tidds:BAAANQAECgQICwAAAA==.Tinker:BAAANQADCgYIDAAAAA==.',
To='To:BAAANQAECggIEwAAAA==.Tobi:BAABNQAECn9FAAMFAAoK3SVDBACxAwAFAAoK3SVDBACxAwAJAAUKMhiH+gApAQAAAA==.Tootsy:BAAANQADCgcIDQAAAA==.Totemdown:BAACNQAFFH8eAAIeAAcKfCNlAQC8AgAeAAcKfCNlAQC8AgA1AAQKfycAAh4ACgqeJWIEAKcDAB4ACgqeJWIEAKcDAAE1AAQKBQgJAA0AAAAA.',
Tr='Traedaei:BAAANQADCgYICAAAAA==.Trazarath:BAABNQAECn9EAAQLAAoKbxXeDgBvAgALAAoKrBLeDgBvAgAMAAgK9BFwCwCoAQAdAAIKIBLOKgByAAAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.Trooged:BAAANQADCggICAABNQAECgoKRAALAG8VAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgMIBQABNQAECgYIEgANAAAAAA==.',
Un='Untiler:BAAANQADCggIBgAAAA==.',
Us='Usdaprime:BAAANQAECggIDgAAAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECggIHAABNQAECggIMAANAAAAAQ==.',
Va='Vaelra:BAABNQAECn8XAAIdAAkKog+GDgDoAQAdAAkKog+GDgDoAQABNQAECgoKIAAFAI0UAA==.Valedaren:BAAANQADCgUIBgAAAA==.Valefyre:BAAANQAECgEIAQAAAA==.Vance:BAAANQAECgQIBAAAAA==.Varala:BAAANQAECgMIBgAAAA==.',
Ve='Vel:BAACNQAFFH8OAAIVAAYKABZuBwCjAQAVAAYKABZuBwCjAQA1AAQKf3oAAxUACgqvJoYAAIoDABUACgqvJoYAAIoDACEAAwqEIO5nAAEBAAAA.Velgrave:BAAANQAECggICQABNQAFFAYIDgAVAAAWAA==.Veritas:BAABNQAECn8lAAIEAAoKHRwIEwDRAgAEAAoKHRwIEwDRAgAAAA==.Veskara:BAAANQAECgEIAQAAAA==.',
Vo='Voltsadin:BAAANQAECgIIAQABNQAECgkJKQAgAM0eAA==.',
Vy='Vylana:BAABNQAECn87AAIeAAkKfBeCLABCAgAeAAkKfBeCLABCAgABNQAFFAYICgAKACkNAA==.',
['Và']='Vàlkyrie:BAAANQAFFAEIAQAAAA==.',
['Vè']='Vèl:BAAANQAECggICgABNQAFFAYIDgAVAAAWAA==.',
Wa='Warity:BAAANQAECggIEQAAAA==.',
We='Weneyan:BAAANQADCgYIBgAAAA==.Wetdotdruid:BAAANQAECgQIBAAAAA==.Wetdotpal:BAABNQAECn8qAAIQAAkK/RCGKQCQAQAQAAkK/RCGKQCQAQAAAA==.Wetdotrogue:BAAANQAECgEIAQAAAA==.Wetdotthirst:BAAANQAECgYIBwAAAA==.Wetdotwar:BAAANQAECgMIAwAAAA==.',
Wh='Whiteabyss:BAABNQAECn80AAMBAAkKohLaUgCjAQABAAkKohLaUgCjAQAfAAEKAAC6fAAwAAAAAA==.',
Wr='Wraith:BAAANQAECgYICwAAAA==.',
Xe='Xeral:BAAANQADCgEIAQAAAA==.Xerxseizee:BAAANQAECgcIBwAAAA==.',
Xo='Xomby:BAABNQAECn8dAAMkAAcKWRAWDgBOAQAkAAcKWRAWDgBOAQAEAAUK/wnZSwDnAAAAAA==.',
['Xì']='Xìon:BAABNQAECn8+AAQWAAoKMhlrFwAiAgAWAAoKMhlrFwAiAgAVAAUKrgWnrQCZAAAhAAIKBAPSqQAfAAAAAA==.',
Ya='Yayrri:BAABNQAECn8aAAISAAkKGAgUngBbAQASAAkKGAgUngBbAQAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQAECgIIAgAAAA==.',
Yu='Yungstabby:BAAANQADCgYIBgABNQAECgYIFgADAF8SAA==.',
Yv='Yverari:BAAANQADCgcIBwAAAA==.',
Za='Zahne:BAAANQAECgYICwABNQAECgoKQgABAEglAA==.Zaideom:BAAANQADCgQIBAAAAA==.Zatarra:BAAANQADCgUIBwAAAA==.Zavya:BAAANQADCgMJAwABNQAECgIIAgANAAAAAA==.',
Ze='Zex:BAAANQADCgUIBwABNQAECggIIwAjAGQKAA==.Zextron:BAABNQAECn8jAAIjAAgKZAppPAANAQAjAAgKZAppPAANAQAAAA==.',
Zi='Ziaya:BAAANQAECgIIAgAAAA==.',
Zo='Zolaeus:BAAANQADCgcIDQABNQAECgUIBAANAAAAAA==.',
Zu='Zuboo:BAABNQAECn8lAAIjAAkKCAUBPgAFAQAjAAkKCAUBPgAFAQAAAA==.',
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
