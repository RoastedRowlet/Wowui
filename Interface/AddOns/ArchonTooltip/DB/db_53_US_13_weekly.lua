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

local lookup = {'Warlock-Demonology','Monk-Brewmaster','Priest-Holy','Priest-Shadow','Paladin-Holy','Rogue-Assassination','Warrior-Arms','Mage-Arcane','Mage-Frost','Paladin-Retribution','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Druid-Balance','Druid-Feral','Paladin-Protection','Druid-Guardian','Shaman-Elemental','Druid-Restoration','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Warrior-Fury','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','Monk-Mistweaver','Evoker-Preservation','Shaman-Restoration','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abisio:BAAANQAECgEJAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAABNQAECn8qAAIBAAoK5yGXHQAOAwABAAoK5yGXHQAOAwAAAA==.Acursedpeen:BAAANQAECgIIAwAAAA==.',
Ad='Aderna:BAAANQAECgQIBgAAAA==.Adoryn:BAEBNQAECn8rAAICAAoK3AktDQBZAQACAAoK3AktDQBZAQAAAA==.',
Ae='Aelara:BAABNQAECn8eAAMDAAoKeBS3XwACAgADAAoKeBS3XwACAgAEAAQKyAhaRgCSAAABNQAECgoKJwAFAG4XAA==.Aessan:BAAANQAECggIDgAAAA==.Aethelred:BAAANQADCgYIBgAAAA==.',
Ag='Agares:BAABNQAECn8uAAIGAAoK5xebGgBQAQAGAAoK5xebGgBQAQABNQAECgoKQgAHAOAeAA==.',
Ai='Aisathya:BAABNQAECn8aAAMIAAoKtxl4ygDwAQAIAAkKKRp4ygDwAQAJAAEKmBZ0PgBIAAAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Al='Aleysia:BAABNQAECn8nAAMFAAoKbhdGIwCpAgAFAAoKbhdGIwCpAgAKAAIKpASHgwFVAAAAAA==.Alivar:BAAANQABCgIIAgAAAA==.',
Am='Amberfox:BAABNQAECn8jAAILAAkKVyAxLACRAgALAAkKVyAxLACRAgAAAA==.Amberscale:BAABNQAECn9DAAMMAAoKYR+HBgAhAwAMAAoKYR+HBgAhAwANAAIKxRi2FQCHAAAAAA==.',
An='Anahexic:BAAANQADCgEIAQAAAA==.Ancientiur:BAAANQADCgIIAgABNQAECgIIAwAOAAAAAA==.Ancientuur:BAAANQADCgYIBgABNQAECgIIAwAOAAAAAA==.Andazaren:BAABNQAECn9FAAIKAAoKEg11lACjAQAKAAoKEg11lACjAQAAAA==.Andracca:BAAANQAECgIIAgAAAA==.Angrulus:BAABNQAECn9JAAILAAoKxByCJQCpAgALAAoKxByCJQCpAgAAAA==.Animal:BAAANQAECgQIAgAAAA==.Animlshiftr:BAABNQAECn8gAAMPAAoKswdkNQBkAQAPAAoKswdkNQBkAQAQAAMKoAMUOwBOAAAAAA==.',
Ap='Apollo:BAABNQAECn8sAAIBAAgKgwhmlgAtAQABAAgKgwhmlgAtAQAAAA==.',
Ar='Aradunn:BAAANQAECgEIAQAAAA==.Arixx:BAAANQABCgIIAgAAAA==.Arrøw:BAAANQADCgQIBAAAAA==.Aryllyn:BAAANQAECgMIBwAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQAECgQIBgABNQAECgUICgAOAAAAAA==.',
At='Atris:BAAANQADCgcIBwAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQAECgQIBAABNQAECgoKLAARALQQAA==.Banmoor:BAAANQAECgQIDAAAAA==.',
Be='Bearett:BAABNQAECn87AAISAAkK6h7bDwBjAgASAAkK6h7bDwBjAgAAAA==.Belyrune:BAABNQAECn8XAAIIAAkKOgVxSQEUAQAIAAkKOgVxSQEUAQABNQAECgoKUQATAAwXAA==.Belysurge:BAABNQAECn9RAAITAAoKDBdRKABBAgATAAoKDBdRKABBAgAAAA==.Bernd:BAABNQAECn8lAAISAAoKJArZLQAiAQASAAoKJArZLQAiAQAAAA==.Beörn:BAABNQAECn8mAAIUAAgKmSXRBQBlAwAUAAgKmSXRBQBlAwAAAA==.',
Bi='Birgir:BAAANQAECgEIAQAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAABNQAECn8aAAIVAAkKiwtyOABQAQAVAAkKiwtyOABQAQAAAA==.',
Br='Braids:BAAANQAECgUIBwAAAA==.Breezy:BAACNQAFFH8GAAIKAAIKIA6rJQCGAAAKAAIKIA6rJQCGAAA1AAQKfzYAAgoACgoCHhY+AHACAAoACgoCHhY+AHACAAAA.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAABNQAECn8qAAMWAAoKgxtyEQBvAgAWAAoK8RpyEQBvAgAXAAIKhB1zbQCaAAAAAA==.',
Bu='Buttrbiskit:BAAANQAECggIDwAAAA==.',
By='Byanca:BAABNQAECn8XAAIVAAcKRwP+SgDOAAAVAAcKRwP+SgDOAAAAAA==.',
Ca='Caine:BAABNQAECn8nAAIYAAoKlxjVDQDgAQAYAAoKlxjVDQDgAQAAAA==.Callen:BAAANQADCgEIAQAAAA==.Carlonus:BAAANQADCggICwABNQAECgoKMgANAGkRAA==.Casey:BAAANQAECgUIEAAAAA==.Castyblasty:BAABNQAECn9BAAMIAAoK2hYCQwBEAgAIAAoK2hYCQwBEAgAJAAEKAAkiRQA5AAAAAA==.Cataaria:BAAANQAECgYIBgABNQAECggIDgAOAAAAAA==.',
Ce='Cellina:BAABNQAECn8XAAIVAAgKpArYNwDlAAAVAAgKpArYNwDlAAAAAA==.',
Ch='Chiman:BAAANQADCgcJCQABNQAECgUIBAAOAAAAAA==.Chromatica:BAAANQADCgYIBgAAAA==.',
Ci='Cignus:BAAANQAECggICQAAAA==.',
Cl='Classá:BAABNQAECn9EAAQUAAoK+R6wCwAPAwAUAAoK+R6wCwAPAwAPAAoK6R2YHgDVAgASAAcKAw/LLgAkAQAAAA==.Clawz:BAAANQAECgEIAQABNQAECgQICQAOAAAAAA==.',
Co='Codedd:BAAANQADCgYIDAAAAA==.Corlys:BAABNQAECn8iAAMKAAoKmREfoADhAQAKAAoKmREfoADhAQARAAEKAAC1ewAhAAAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAABNQAECn8lAAILAAkKnAZ3qgBdAQALAAkKnAZ3qgBdAQAAAA==.Crue:BAABNQAECn8+AAMUAAoKtg7kLACJAQAUAAkKKQ3kLACJAQAPAAkKfghoOwBCAQAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIJAgAAAA==.Curthar:BAAANQAECgQIBAABNQAECgQICQAOAAAAAA==.',
Cy='Cynboom:BAAANQAECgEIAQAAAA==.Cyndee:BAABNQAECn9LAAIZAAoKtxiJBgBZAgAZAAoKtxiJBgBZAgAAAA==.Cynnafrost:BAAANQADCgQICgAAAA==.Cytenk:BAAANQAECgUICQAAAA==.',
Da='Dadda:BAABNQAECn9MAAIaAAoK/x8LCADFAgAaAAoK/x8LCADFAgAAAA==.Dagad:BAAANQADCgIIAgAAAA==.Daisynukes:BAABNQAECn8ZAAIIAAoKPQwycADRAQAIAAoKPQwycADRAQABNQAECgoKLAATAMoOAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAABNQAECn8sAAMRAAoKtBDfIgBYAQARAAoKtBDfIgBYAQAKAAEKDgoaqQEqAAAAAA==.Dankdruid:BAAANQADCgUICgABNQAECgUIFgAbAEcSAA==.Darkschi:BAABNQAECn8wAAIVAAoKLwxPHwClAQAVAAoKLwxPHwClAQAAAA==.Darthsith:BAAANQABCgQIBAAAAA==.Darthwing:BAAANQADCgcIDgAAAA==.Dartos:BAABNQAECn9OAAIWAAoKDCUjBQAmAwAWAAoKDCUjBQAmAwAAAA==.',
De='Deepmagic:BAAANQAECggIDQAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.Destrûction:BAAANQADCgUIBQAAAA==.',
Di='Diluvium:BAABNQAECn8nAAIRAAoK2xU3GgAfAgARAAoK2xU3GgAfAgAAAA==.Discodank:BAABNQAECn8WAAMbAAUKRxJnCQATAQAbAAUKRxJnCQATAQAEAAUK5QZjPwCyAAAAAA==.',
Dj='Djpleasant:BAACNQAFFH8OAAIJAAcKIhNOAQBqAQAJAAcKIhNOAQBqAQA1AAQKf08AAwkACgquJC8CAFMDAAkACgpSJC8CAFMDAAgABgomIe+mAFYBAAAA.',
Do='Dontcare:BAABNQAECn8pAAMLAAoK0x8xMwB6AgALAAkKeiExMwB6AgAaAAMKiQ8dZQCXAAAAAA==.',
Dr='Drakraa:BAAANQAECgEIAQABNQAECgQICQAOAAAAAA==.',
Dw='Dwailn:BAAANQABCgMIAwAAAA==.',
['Dû']='Dûo:BAABNQAECn80AAMTAAoKixoYTgCfAQATAAkK/R0YTgCfAQAcAAMKLAvGMgBMAAAAAA==.',
Ea='Eatmorpizza:BAABNQAECn8VAAIUAAYK7BDvOQAuAQAUAAYK7BDvOQAuAQAAAA==.',
Ee='Eegnormu:BAAANQAECgQICQAAAA==.Eegroll:BAABNQAECn9DAAQCAAoKaRtZBwDIAgACAAoKXRtZBwDIAgAVAAgKOxN8MwB6AQAdAAcKqgVxLQAAAQAAAA==.',
Eg='Egraw:BAABNQAECn8nAAMHAAkKEyBsPwBFAgAHAAkKEyBsPwBFAgAYAAEK/yBXOgBWAAAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Em='Emilwhaury:BAAANQAECgYIDAAAAA==.',
Ep='Epia:BAABNQAECn8sAAMVAAoKQBTqGADqAQAVAAoKQBTqGADqAQACAAIKCAbALQBPAAAAAA==.',
Es='Esdéath:BAABNQAECn9UAAIDAAkKEyB+GwAFAwADAAkKEyB+GwAFAwAAAA==.Essaila:BAABNQAECn8xAAIQAAoKehEaFAC7AQAQAAoKehEaFAC7AQAAAA==.',
Et='Etherwalker:BAABNQAECn8WAAIHAAgK2hrebQBJAgAHAAgK2hrebQBJAgAAAA==.',
Ex='Excision:BAABNQAECn8pAAIMAAkK1wuNDgBdAQAMAAkK1wuNDgBdAQAAAA==.',
Fa='Fahbio:BAABNQAECn8cAAIRAAgKIwWBOwC+AAARAAgKIwWBOwC+AAAAAA==.Faleros:BAAANQADCgMIAwAAAA==.Fanskar:BAAANQAECgEIAQABNQAECgQIBAAOAAAAAA==.Fatallock:BAACNQAFFH8IAAIBAAQKMgX3HgC5AAABAAQKMgX3HgC5AAA1AAQKf5AAAgEACgo0EqdFAAQCAAEACgo0EqdFAAQCAAAA.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQAECgEIAQAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgcIBwAOAAAAAA==.',
Fl='Flaildh:BAAANQAECgYIBgAAAA==.Flailuid:BAAANQAECgMIBwAAAA==.',
Fo='Forthstryke:BAAANQADCggIEQAAAA==.',
Fr='Fresita:BAABNQAECn8eAAMPAAYKAQ16WQC6AAAPAAYKAQ16WQC6AAAQAAQKpAU4RQBAAAAAAA==.Fridaychill:BAABNQAECn9KAAIVAAoKECCgCwClAgAVAAoKECCgCwClAgAAAA==.Frozarke:BAABNQAECn8yAAMNAAoKaRHdCAD/AQANAAoKaRHdCAD/AQAeAAEKVACxVgATAAAAAA==.',
Fu='Fudd:BAABNQAECn8ZAAILAAgKdA6dnwB0AQALAAgKdA6dnwB0AQAAAA==.Funk:BAAANQABCgIIAgABNQAECgQIAgAOAAAAAA==.Fupa:BAAANQAECgUICAAAAA==.Furryz:BAAANQADCgYIBgABNQAECgkJGwACAPkhAA==.',
Ga='Ganymede:BAAANQAECgUIBQABNQAECgoKRAAUAPkeAA==.Garou:BAABNQAECn8UAAITAAgKkBhMVQAlAgATAAgKkBhMVQAlAgAAAA==.Garres:BAABNQAECn86AAQQAAoK8huMCgAzAgAQAAoKkhuMCgAzAgASAAkKIhQcHgCSAQAPAAMKYAN3mwBtAAAAAA==.',
Ge='Geedorah:BAAANQADCgUIBQABNQAECgoKTAAFAKIkAA==.Genius:BAAANQAECgYIEgAAAA==.',
Gi='Gibley:BAAANQAECgQIBAAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAABNQAECn8XAAIWAAYKTAdWUQC/AAAWAAYKTAdWUQC/AAAAAA==.Gnomie:BAAANQAECgUICwAAAA==.Gnomio:BAAANQAECgYICwAAAA==.',
Go='Gouge:BAAANQAECggISgAAAQ==.',
Gr='Granadithios:BAAANQADCgIIAgAAAA==.Griffynshu:BAABNQAECn8gAAIUAAoKQhVrJADTAQAUAAoKQhVrJADTAQAAAA==.Grrv:BAAANQABCgQIBAAAAA==.Grudgetotem:BAABNQAECn8hAAMfAAoKnRkfWAAJAgAfAAoKnRkfWAAJAgATAAEKSBVTLwE6AAAAAA==.Grunewald:BAAANQAECgQIBwAAAA==.',
Gu='Guinn:BAAANQADCggIDgABNQAECgoKMgANAGkRAA==.Gungnir:BAABNQAECn8xAAIHAAoK6CEDEQB6AwAHAAoK6CEDEQB6AwAAAA==.',
Ha='Haki:BAAANQAECgQIBwAAAA==.Handiboy:BAABNQAECn8vAAIDAAoK1CUaCQB7AwADAAoK1CUaCQB7AwAAAA==.Hardison:BAAANQADCgYIBgAAAA==.Hayate:BAAANQAECgQIDgAAAA==.',
He='Healabull:BAAANQADCgYIDgABNQAECggIHgAXADwSAA==.Heimdall:BAABNQAECn9MAAIFAAoKoiSRBQChAwAFAAoKoiSRBQChAwAAAA==.Hellabear:BAAANQADCgQIBAAAAA==.Hellaholy:BAABNQAECn8tAAMRAAkK1RNRIgBcAQARAAgKuhVRIgBcAQAKAAgKxwfn6wAKAQAAAA==.Hellavva:BAAANQAECgYIBgAAAA==.Help:BAAANQAECgUICQABNQAECgoKOgAIAEwfAA==.Henchling:BAABNQAECn8rAAMfAAoKaRqjPwBiAgAfAAoKaRqjPwBiAgATAAgKwgtEeAAjAQAAAA==.',
Hi='Hina:BAAANQADCggIDgAAAA==.',
Ho='Holexios:BAAANQAECgUIBAAAAA==.Horine:BAABNQAECn8aAAILAAkKxQTsyQAeAQALAAkKxQTsyQAeAQAAAA==.',
['Hö']='Hölyhell:BAAANQADCgUIBwAAAA==.',
Ic='Icieblade:BAABNQAECn8hAAMFAAkKyxmLIwCoAgAFAAkKyxmLIwCoAgAKAAkKUxeDYwALAgAAAA==.',
Im='Immeira:BAABNQAECn9GAAIfAAoKJhzkIgCrAgAfAAoKJhzkIgCrAgAAAA==.',
Ir='Ira:BAABNQAECn8aAAIKAAkKsxR8egDZAQAKAAkKsxR8egDZAQABNQAECgoKLQAPAHgTAA==.',
Ja='Jackiix:BAAANQADCgYIBgAAAA==.Jackmends:BAACNQAFFH8JAAIDAAQKaSIKGwAbAQADAAQKaSIKGwAbAQA1AAQKf0cAAwMACgq+JCAHAIwDAAMACgq+JCAHAIwDAAQAAgovA1ZwAEcAAAAA.Jacksprouts:BAAANQAECgcIEwAAAA==.Jacktides:BAAANQAECgEIAQABNQAFFAQICQADAGkiAA==.Jarryl:BAAANQAECggIEAAAAA==.',
Je='Jeffrez:BAAANQAECgQIBQAAAA==.Jelerious:BAAANQAECggICAAAAA==.Jenoside:BAAANQAECggIMAAAAQ==.',
Ji='Jindu:BAAANQAECggICAAAAA==.',
Jo='Journei:BAABNQAECn9CAAMfAAoKbhXHLABxAgAfAAoKbhXHLABxAgATAAYK8ASjwwALAQAAAA==.',
Ju='Judging:BAABNQAECn8oAAMKAAoKQBH9wwBMAQAKAAkK2BD9wwBMAQAFAAkKGAi8ngBIAQAAAA==.Juggernaught:BAAANQAECggICAAAAA==.Jurb:BAAANQAECggIEAAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIGQAAAA==.Kaitos:BAAANQAECgQICQAAAA==.',
Ke='Kegz:BAABNQAECn8bAAMCAAkK+SHBAwBOAwACAAgKZSTBAwBOAwAVAAMKzA3cPwCyAAAAAA==.Kelendrian:BAAANQAECgUIBQAAAA==.Kellayna:BAABNQAECn8bAAIKAAgKbAZsAwHkAAAKAAgKbAZsAwHkAAAAAA==.Keylö:BAABNQAECn8xAAIWAAkKfhf0IADZAQAWAAkKfhf0IADZAQAAAA==.',
Kh='Khoulethius:BAAANQADCgYIBwAAAA==.',
Ki='Kimbot:BAABNQAECn8fAAMLAAoKJheYRQCbAgALAAoKJheYRQCbAgAaAAEKAACzjgAxAAAAAA==.Kimigosa:BAAANQAECggIDgAAAA==.',
Kl='Klerik:BAACNQAFFH8WAAIBAAQK1xvhEwAHAQABAAQK1xvhEwAHAQA1AAQKf0oABAEACgqpJAASAEcDAAEACgqpJAASAEcDACAABgo/Di8nAD0BACEAAQoKBiQ0ACoAAAAA.',
Kn='Kníghtmare:BAAANQAECgUICgAAAA==.',
Ko='Koragg:BAACNQAFFH8pAAIXAAcKByIGBgDfAQAXAAcKByIGBgDfAQA1AAQKfzwAAhcACgoSI5wRACADABcACgoSI5wRACADAAAA.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgUIBQAAAA==.Korath:BAAANQADCgEIAQAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAABNQAECn8hAAIMAAoKfgsvEAA7AQAMAAoKfgsvEAA7AQAAAA==.',
Kr='Kratus:BAAANQAECgEIAQAAAA==.Krissia:BAABNQAECn9FAAMiAAoK6ReyJAAuAgAiAAoK6ReyJAAuAgAWAAUKMgbclgDUAAAAAA==.',
Ky='Kymerah:BAAANQABCgYICAAAAA==.Kyntaliia:BAAANQADCgYIDAAAAA==.',
['Kî']='Kîn:BAABNQAECn8cAAIjAAgKfhVQJwBgAQAjAAgKfhVQJwBgAQAAAA==.',
La='Lailey:BAAANQADCggICAAAAA==.Laisera:BAABNQAECn8jAAIDAAoKCQpPewCoAQADAAoKCQpPewCoAQAAAA==.Lalipop:BAABNQAECn8cAAIDAAgK9CCbSAAWAgADAAgK9CCbSAAWAgAAAA==.Landroval:BAABNQAECn8WAAIMAAoK2Q+/GAC9AQAMAAoK2Q+/GAC9AQAAAA==.Langedamort:BAAANQADCgEIAQAAAA==.Lastkissgbye:BAAANQABCgIIAgAAAA==.Lawson:BAABNQAECn8yAAIWAAoKzRAcIADgAQAWAAoKzRAcIADgAQAAAA==.',
Le='Leeoh:BAABNQAECn8rAAIIAAoKXgZ/xgAaAQAIAAoKXgZ/xgAaAQAAAA==.Leeohd:BAAANQAECgYIDwAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAABNQAECn8gAAIUAAYKNwXdUAC3AAAUAAYKNwXdUAC3AAAAAA==.',
Lo='Lovenky:BAAANQAECgIIAwAAAA==.',
Lu='Lujuria:BAABNQAECn8tAAIPAAoKeBMRIgDtAQAPAAoKeBMRIgDtAQAAAA==.Lumawig:BAAANQADCgcIBwAAAA==.Lunchdk:BAAANQAECgMIBgAAAA==.',
Ly='Lyreth:BAABNQAECn8iAAMPAAcKqAejcwD8AAAPAAYK1gWjcwD8AAAUAAYKEApURwDjAAAAAA==.',
Ma='Madax:BAABNQAECn9CAAMHAAoK4B7CIwCyAgAHAAoKWR7CIwCyAgAYAAMKqx+qKAC4AAAAAA==.Mambos:BAAANQAECgQIBAAAAA==.Manach:BAAANQAECgMIDAAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAABNQAECn9CAAIiAAkKvRdPMADpAQAiAAkKvRdPMADpAQAAAA==.Meganfox:BAAANQAECgQJCAABNQAECgoKKQALANMfAA==.Melinara:BAAANQADCgYIBgAAAA==.Merilde:BAABNQAECn8fAAQUAAoK/xhSIAD5AQAUAAgKtBZSIAD5AQASAAoKsBHSGgDOAQAPAAQK9Am5hAC+AAAAAA==.Metrolinea:BAABNQAECn8oAAIIAAoKpCE+LwAuAwAIAAoKpCE+LwAuAwAAAA==.',
Mi='Milliy:BAABNQAECn8XAAMQAAkKhgXoHQAtAQAQAAgKBgboHQAtAQAPAAMKQQJcegBWAAAAAA==.Minamel:BAAANQAECgEIAQABNQAECggIDQAOAAAAAA==.Minuette:BAAANQABCgMIAwAAAA==.Missbehaving:BAABNQAECn8gAAMDAAkKtQvedQB5AQADAAkKtQvedQB5AQAEAAEKAAADkQAZAAAAAA==.Misstigger:BAAANQABCgQIBAAAAA==.Mistea:BAAANQABCgYIBgAAAA==.',
Mo='Mojorisin:BAAANQADCgUIBgAAAA==.Morefire:BAABNQAECn84AAIBAAoKMBrZJgDpAgABAAoKMBrZJgDpAgAAAA==.Mosmos:BAAANQAECgUIBAAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAABNQAECn8tAAMDAAgKTA9jYwC2AQADAAgKTA9jYwC2AQAEAAIKHgJFdwA4AAAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAABNQAECn8ZAAICAAcKwBrPDgAGAgACAAcKwBrPDgAGAgAAAA==.',
Na='Nalassa:BAABNQAECn8fAAIUAAoKNBhNGwAxAgAUAAoKNBhNGwAxAgABNQAECgoKJwAFAG4XAA==.Nannette:BAABNQAECn8XAAIKAAcKHQIAVQGYAAAKAAcKHQIAVQGYAAAAAA==.Narag:BAABNQAECn8sAAILAAoK7xNbVgAfAgALAAoK7xNbVgAfAgAAAA==.Narishma:BAAANQADCgUICAAAAA==.',
Ne='Neph:BAAANQAECggIAgAAAA==.Nephorma:BAAANQADCggJCgAAAA==.Newport:BAABNQAECn8vAAMfAAkKjhxaLwBkAgAfAAkKjhxaLwBkAgATAAQKtA1u9QCqAAAAAA==.',
Ni='Niara:BAABNQAECn9AAAMYAAoKTRGqEQCdAQAYAAoKTRGqEQCdAQAHAAIKGQfKEQFYAAAAAA==.Ninevolt:BAAANQADCgIIAgABNQAECgoKKgAhACkfAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAABNQAECn86AAMfAAoKThX3RwDzAQAfAAoKThX3RwDzAQAcAAEKMgJ8OQApAAAAAA==.Nisle:BAAANQABCggICgABNQAECgoKMgANAGkRAA==.Nithén:BAABNQAECn8YAAMNAAUKPwLQHgBpAAANAAUKBALQHgBpAAAMAAMKAgK+NQBgAAAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Nonenight:BAAANQADCgIIAgABNQAECgoKLQAkAPUJAA==.Nowhere:BAAANQAECgUIBwABNQAECgcIBwAOAAAAAA==.Nowon:BAABNQAECn8tAAIkAAoK9QlCQQAxAQAkAAoK9QlCQQAxAQAAAA==.',
Nu='Nudream:BAABNQAECn8WAAIKAAoKwQO2FAHKAAAKAAoKwQO2FAHKAAAAAA==.Nuka:BAAANQAECgUICwAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgcIBwAOAAAAAA==.',
Oo='Oomdeath:BAAANQADCgIIAgAAAA==.',
Op='Opalyte:BAABNQAECn8bAAIDAAgK3Qp4kwAfAQADAAgK3Qp4kwAfAQAAAA==.',
Oq='Oqisa:BAAANQADCgMIAwABNQAECgUIBQAOAAAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAABNQAECn8wAAILAAcK/ACaQwFZAAALAAcK/ACaQwFZAAAAAA==.',
Ot='Othril:BAAANQAECgEIAQAAAA==.',
Ov='Overtavo:BAABNQAECn8qAAQBAAoK2RepVwDNAQABAAkKIhepVwDNAQAgAAEK2xwoMQBFAAAhAAEKAAC1KwA/AAAAAA==.',
Ox='Oxmink:BAAANQAECgMIAwAAAA==.',
Pa='Pacobell:BAAANQADCggIEgAAAA==.Pakoros:BAABNQAECn87AAIfAAoKniH6HADRAgAfAAoKniH6HADRAgAAAA==.Palamar:BAABNQAECn8sAAIKAAoK6wX3yABEAQAKAAoK6wX3yABEAQAAAA==.Pallyanne:BAAANQADCgIIAgAAAA==.Pandsala:BAABNQAECn88AAIDAAoKZSDWCgCPAwADAAoKZSDWCgCPAwABNQAECgoKTAAFAKIkAA==.Papo:BAAANQADCgcIBwAAAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAABNQAECn8xAAILAAgK3AYevQA3AQALAAgK3AYevQA3AQAAAA==.',
Pg='Pgorlelgy:BAABNQAECn8mAAILAAgKTRfXdQAkAgALAAgKTRfXdQAkAgAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.Phucca:BAAANQADCggICAABNQAECgQIDgAOAAAAAA==.',
Pl='Platious:BAABNQAECn8fAAIKAAkKphGWsQBtAQAKAAkKphGWsQBtAQAAAA==.',
Po='Pookaboo:BAABNQAECn8mAAIBAAkKvgI2ygC8AAABAAkKvgI2ygC8AAAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAACNQAFFH8LAAIEAAUKfgh1CgBQAQAEAAUKfgh1CgBQAQA1AAQKfy0AAgQACgrsG84YAIoCAAQACgrsG84YAIoCAAE1AAUUBQoLAAQAfggA.',
Pu='Purdie:BAAANQADCgEIAQABNQAECggIDgAOAAAAAA==.Purdiemonk:BAAANQADCgQIBAAAAA==.Purdienir:BAAANQADCgQJBAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECggIDgAOAAAAAA==.',
Py='Pyrolock:BAABNQAECn8XAAMhAAkKMSV2AQBGAwAhAAgKACV2AQBGAwABAAgK+CLAFgAuAwAAAA==.',
['Pì']='Pìke:BAAANQAECgcIBgAAAA==.',
Qe='Qeesa:BAAANQAECgUIBQAAAA==.',
Ra='Radzog:BAAANQAECgYICwAAAA==.Rafikie:BAAANQADCggIDQAAAA==.Ranni:BAABNQAECn8gAAMfAAoKJBWXWgCrAQAfAAkKWRWXWgCrAQATAAUKpA3rzQD3AAABNQAECgoKJwAFAG4XAA==.Rawmeat:BAABNQAECn8pAAMEAAoKExRxFgD8AQAEAAoKExRxFgD8AQADAAUKJA+RrwAIAQAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renew:BAAANQAECgIIAgAAAA==.Renix:BAAANQAECgQIBQAAAA==.Reno:BAAANQADCgcIBwAAAA==.',
Rh='Rhainnón:BAAANQAECgcIDQAAAA==.Rheã:BAAANQAECgUIDwAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAABNQAECn8ZAAIIAAkKlhvzbwCeAgAIAAkKlhvzbwCeAgAAAA==.',
Ro='Roombaa:BAAANQADCggICQAAAA==.Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sabrefang:BAAANQADCgcIDAAAAA==.Sack:BAAANQAECgQIBgABNQAECggIFAATAJAYAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sai:BAAANQADCggIDwAAAA==.Samsius:BAAANQABCgIIAgAAAA==.Sanctity:BAAANQAECgcIDwAAAA==.Sarson:BAAANQAECgIIAwAAAA==.Satine:BAAANQADCggIEgAAAA==.Saïma:BAAANQADCgYIBAABNQAECgcIDwAOAAAAAA==.',
Sc='Scratlord:BAABNQAECn8lAAIaAAUKkwSZWwC2AAAaAAUKkwSZWwC2AAAAAA==.',
Se='Sevinas:BAABNQAECn8WAAIcAAcKFwh8IQBGAQAcAAcKFwh8IQBGAQAAAA==.',
Sh='Shadeira:BAAANQAECgcIBwAAAA==.Shamthis:BAABNQAECn8sAAMTAAoKyg5rcQDMAQATAAoKyg5rcQDMAQAfAAMK7QLHDQFMAAAAAA==.Shamwoww:BAACNQAFFH8HAAMfAAcKkweqHAC8AAAfAAQKyQCqHAC8AAATAAMKCgNMKgA9AAA1AAQKfxsAAx8ACQpFFHhGAPkBAB8ACAoBFXhGAPkBABMABQo0DkGaANMAAAE1AAUUBQoLAAQAfggA.Shelly:BAAANQAECgIIAgAAAA==.Shlumpa:BAAANQAECggIDwAAAA==.Shlumpcane:BAABNQAECn8ZAAIIAAYKxw4S8ADPAAAIAAYKxw4S8ADPAAAAAA==.Shokcz:BAAANQAECgUICQAAAA==.Shomba:BAAANQAECgEIAQAAAA==.Shámjackson:BAACNQAFFH8WAAIfAAYKBSNFBQBbAgAfAAYKBSNFBQBbAgA1AAQKfysAAh8ACgpmJewBAMkDAB8ACgpmJewBAMkDAAAA.',
Si='Silvey:BAABNQAECn8oAAMkAAoKxB9pFQBxAgAkAAoKxB9pFQBxAgAjAAEKAADpcAAtAAAAAA==.Sinroot:BAAANQADCgQIBAAAAA==.Sithknight:BAAANQABCgQIBgAAAA==.Sithtracker:BAAANQABCgYICAAAAA==.Sizzurp:BAAANQAECgMIAwAAAA==.',
Sk='Skeletorque:BAABNQAECn8bAAMXAAcKCgjUdgB+AAAXAAYKIwnUdgB+AAAWAAQKmwJSzgBQAAAAAA==.',
Sm='Smallwdruid:BAAANQAECgcICgAAAA==.',
Sn='Sneezeweed:BAAANQAECgMIAwAAAA==.Snow:BAAANQADCgcIBwABNQAECgoKRQAFAN0lAA==.Snowfawn:BAABNQAECn8ZAAILAAYKTQxE4gDsAAALAAYKTQxE4gDsAAAAAA==.Snusnurae:BAAANQAECgIIAgAAAA==.',
So='Soape:BAABNQAECn8sAAIKAAoKkwVgzwA5AQAKAAoKkwVgzwA5AQAAAA==.Soloment:BAAANQADCgEIAQABNQADCggIGAAOAAAAAA==.',
Sp='Specialist:BAABNQAECn8fAAIDAAkK8x7oHwDgAgADAAkK8x7oHwDgAgABNQAECgoKKQALANMfAA==.Splishsplásh:BAAANQAECgcIEgAAAA==.Spooties:BAAANQAECggIAwAAAA==.Spoots:BAAANQAECgcIBwAAAA==.Spooty:BAAANQAECggICAAAAA==.Sprattyboii:BAAANQAECgQIBwAAAA==.',
Sq='Squishydk:BAAANQADCgUICgABNQAECgoKJwARANsVAA==.',
Ss='Sscarlet:BAAANQAECggIEgAAAA==.',
St='Stabedyou:BAAANQAECgcICAAAAA==.Staltis:BAAANQAECgcIEAABNQAECgoKMgANAGkRAA==.Starzia:BAABNQAECn8yAAIbAAoKxw2ABQC0AQAbAAoKxw2ABQC0AQAAAA==.Storee:BAABNQAECn80AAIBAAkKJwyapgCHAQABAAkKJwyapgCHAQAAAA==.',
Su='Sunk:BAABNQAECn8lAAIBAAoKRhI0WQDIAQABAAoKRhI0WQDIAQAAAA==.',
Sw='Swiftblossom:BAAANQAECgEIAQAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcJCwABNQAECgUIBAAOAAAAAA==.Talarus:BAAANQAECgUIBwAAAA==.Tanadria:BAAANQAECggIDwAAAA==.Tapioca:BAAANQAECgIIAgAAAA==.Taterdot:BAABNQAECn8qAAMhAAoKKR8bAwDUAgAhAAoKKR8bAwDUAgAgAAIKkCDoQAC/AAAAAA==.',
Te='Telm:BAAANQAECggIDQAAAA==.Tentilious:BAAANQADCgMIAwAAAA==.Tetocoochie:BAAANQADCgcIBwAAAA==.Tetsu:BAAANQAECgEIAQAAAA==.',
Th='Thaka:BAAANQADCgcIBwAAAA==.Thaÿne:BAAANQAECgMIBQAAAA==.Thebestpally:BAABNQAECn9dAAMRAAoKdyB4BgDuAgARAAoKbSB4BgDuAgAKAAYKARHO+QDzAAAAAA==.Thenemisis:BAAANQAECgQIBgAAAA==.Thiccidàn:BAAANQADCgYIDAABNQAECgQIDAAOAAAAAA==.Thiccsister:BAAANQADCgQIBAABNQAECgQIDAAOAAAAAA==.Thiccstraza:BAAANQAECgQIDAAAAA==.',
Ti='Tidds:BAAANQAECgUICwAAAA==.Tinker:BAAANQADCgYIDAAAAA==.',
To='To:BAAANQAECggIEwAAAA==.Tobi:BAABNQAECn9FAAMFAAoK3SVDBACxAwAFAAoK3SVDBACxAwAKAAUKMhiH+gApAQAAAA==.Tootsy:BAAANQADCgcIDQAAAA==.Totemdown:BAACNQAFFH8eAAIfAAcKfCNlAQC8AgAfAAcKfCNlAQC8AgA1AAQKfzAAAh8ACgoIJmIEAKcDAB8ACgoIJmIEAKcDAAE1AAQKBQgJAA4AAAAA.',
Tr='Traedaei:BAAANQADCgYICAAAAA==.Trazarath:BAABNQAECn9EAAQMAAoKbxXeDgBvAgAMAAoKrBLeDgBvAgANAAgK9BFwCwCoAQAeAAIKIBLjMABzAAAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.Trooged:BAAANQADCggICAABNQAECgoKRAAMAG8VAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgMIBQABNQAECggIGQATALUJAA==.',
Un='Untiler:BAAANQAECgQIBAAAAA==.',
Us='Usdaprime:BAABNQAECn8ZAAIHAAcK0wbTzgDWAAAHAAcK0wbTzgDWAAABNQAECgcIGwAXAAoIAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECggIHAABNQAECggIMAAOAAAAAQ==.',
Va='Vaelra:BAABNQAECn8YAAIeAAkKlRBeEQDsAQAeAAkKlRBeEQDsAQABNQAECgoKJwAFAG4XAA==.Valedaren:BAAANQADCgUIBgAAAA==.Valefyre:BAAANQAECgEIAQAAAA==.Vance:BAAANQAECgQIBAAAAA==.Varala:BAAANQAECgMIDAAAAA==.',
Ve='Vel:BAACNQAFFH8ZAAIWAAgKJR1MAQDkAQAWAAgKJR1MAQDkAQA1AAQKf30AAxYACgrAJrMAAIkDABYACgrAJrMAAIkDACIAAwqEIO5nAAEBAAAA.Velgrave:BAAANQAECggICgABNQAFFAgIGQAWACUdAA==.Veritas:BAABNQAECn8lAAIEAAoKHRwIEwDRAgAEAAoKHRwIEwDRAgAAAA==.Veskara:BAAANQAECgIIAQAAAA==.',
Vo='Voltsadin:BAAANQAECgEIAQABNQAECgoKKgAhACkfAA==.',
Vy='Vylana:BAABNQAECn9UAAMfAAoKJhdeJQCbAgAfAAoKJhdeJQCbAgATAAMKBwaTywB1AAABNQAFFAcICwALAOwLAA==.',
['Và']='Vàlkyrie:BAAANQAFFAEIAQAAAA==.',
['Vè']='Vèl:BAAANQAECggIDQABNQAFFAgIGQAWACUdAA==.',
Wa='Warity:BAABNQAECn8UAAIBAAoKEA3EnQCcAQABAAoKEA3EnQCcAQAAAA==.',
We='Weneyan:BAAANQADCgYIBgAAAA==.Wetdotdruid:BAAANQAECgYICgAAAA==.Wetdotpal:BAABNQAECn8xAAIRAAoKQxI4HACPAQARAAoKQxI4HACPAQAAAA==.Wetdotrogue:BAAANQAECgIIAQAAAA==.Wetdotsham:BAAANQAECgYIBgAAAA==.Wetdotthirst:BAAANQAECgcICAAAAA==.Wetdotwar:BAAANQAECgcICwAAAA==.',
Wh='Whiteabyss:BAABNQAECn83AAMBAAoKMhN5TwDmAQABAAoKMhN5TwDmAQAgAAEKAAC6fAAwAAAAAA==.',
Wr='Wraith:BAAANQAECgYICwAAAA==.',
Xe='Xeral:BAAANQADCgEIAQAAAA==.Xerxseizee:BAAANQAECgcIBwAAAA==.',
Xo='Xomby:BAABNQAECn8dAAMbAAcKWRAWDgBOAQAbAAcKWRAWDgBOAQAEAAUK/wnZSwDnAAAAAA==.',
['Xì']='Xìon:BAABNQAECn9HAAQXAAoKnRqMGQA3AgAXAAoKnRqMGQA3AgAWAAUKrgWnrQCZAAAiAAUKfQruhwCXAAAAAA==.',
Ya='Yayrri:BAABNQAECn8bAAITAAoKNgingQANAQATAAoKNgingQANAQAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQAECgIIAgAAAA==.',
Yu='Yungstabby:BAAANQADCgYIBgABNQAECgYIFgADAF8SAA==.',
Yv='Yverari:BAAANQADCggIFgAAAA==.',
Za='Zahne:BAAANQAECgYICwABNQAECgoKQgABAEglAA==.Zaideom:BAAANQADCgQIBAAAAA==.Zaleon:BAAANQAECgIIAgABNQAECgQICQAOAAAAAA==.Zatarra:BAAANQADCgUIBwAAAA==.Zavya:BAAANQADCgMJAwABNQAECgIIAgAOAAAAAA==.',
Ze='Zex:BAAANQAECgIIAgABNQAECgoKJwAkAAoKAA==.Zextron:BAABNQAECn8nAAIkAAoKCgqxNwBoAQAkAAoKCgqxNwBoAQAAAA==.',
Zi='Ziaya:BAAANQAECgIIAgAAAA==.',
Zo='Zolaeus:BAAANQADCgcIDQABNQAECgUIBAAOAAAAAA==.',
Zu='Zuboo:BAABNQAECn8wAAIkAAoKdAYkPgBDAQAkAAoKdAYkPgBDAQAAAA==.',
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
