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

local lookup = {'Warlock-Demonology','Monk-Brewmaster','Priest-Holy','Priest-Shadow','Paladin-Holy','Rogue-Assassination','Mage-Arcane','Mage-Frost','Paladin-Retribution','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Druid-Balance','Druid-Feral','Paladin-Protection','Druid-Guardian','Shaman-Elemental','Druid-Restoration','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Warrior-Fury','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','Monk-Mistweaver','Warrior-Arms','Evoker-Preservation','Shaman-Restoration','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Havoc',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abisio:BAAANQAECgEJAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAABNQAECn8qAAIBAAoK5yGXHQAOAwABAAoK5yGXHQAOAwAAAA==.Acursedpeen:BAAANQAECgIIAwAAAA==.',
Ad='Aderna:BAAANQAECgQIBgAAAA==.Adoryn:BAEBNQAECn8lAAICAAoKiAl9DABTAQACAAoKiAl9DABTAQAAAA==.',
Ae='Aelara:BAABNQAECn8eAAMDAAoKeBS1VwDHAQADAAoKeBS1VwDHAQAEAAQKyAjGQQCSAAABNQAECgoKJgAFAJkWAA==.Aessan:BAAANQAECggIDgAAAA==.Aethelred:BAAANQADCgYIBgAAAA==.',
Ag='Agares:BAABNQAECn8uAAIGAAoK5xdFGQBSAQAGAAoK5xdFGQBSAQAAAA==.',
Ai='Aisathya:BAABNQAECn8aAAMHAAoKtxl4ygDwAQAHAAkKKRp4ygDwAQAIAAEKmBZ0PgBIAAAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Al='Aleysia:BAABNQAECn8mAAMFAAoKmRZvIQCkAgAFAAoKmRZvIQCkAgAJAAIKpASHgwFVAAAAAA==.Alivar:BAAANQABCgIIAgAAAA==.',
Am='Amberfox:BAABNQAECn8jAAIKAAkKVyBLJgCYAgAKAAkKVyBLJgCYAgAAAA==.Amberscale:BAABNQAECn8/AAMLAAoKgh6HBgAhAwALAAoKgh6HBgAhAwAMAAIKxRhtFACGAAAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQAECgIIAwANAAAAAA==.Ancientuur:BAAANQADCgYIBgABNQAECgIIAwANAAAAAA==.Andazaren:BAABNQAECn9DAAIJAAoKtgwXjQCdAQAJAAoKtgwXjQCdAQAAAA==.Andracca:BAAANQAECgIIAgAAAA==.Angrulus:BAABNQAECn8/AAIKAAoKjhu2KQCLAgAKAAoKjhu2KQCLAgAAAA==.Animal:BAAANQAECgQIAgAAAA==.Animlshiftr:BAABNQAECn8aAAMOAAoKAAepMwBYAQAOAAoK/wapMwBYAQAPAAMKoAMUOwBOAAAAAA==.',
Ap='Apollo:BAABNQAECn8mAAIBAAgKuAfOkgAgAQABAAgKuAfOkgAgAQAAAA==.',
Ar='Aradunn:BAAANQAECgEIAQAAAA==.Arixx:BAAANQABCgIIAgAAAA==.Arrøw:BAAANQADCgQIBAAAAA==.Aryllyn:BAAANQAECgMIBwAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQAECgQIBgABNQAECgUICgANAAAAAA==.',
At='Atris:BAAANQADCgcIBwAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQAECgQIBAABNQAECgkJKwAQAOcQAA==.Banmoor:BAAANQAECgQIDAAAAA==.',
Be='Bearett:BAABNQAECn84AAIRAAgKUB7bDwBjAgARAAgKUB7bDwBjAgAAAA==.Belyrune:BAABNQAECn8XAAIHAAkKOgVxSQEUAQAHAAkKOgVxSQEUAQABNQAECgoKSwASAAwXAA==.Belysurge:BAABNQAECn9LAAISAAoKDBfFJABDAgASAAoKDBfFJABDAgAAAA==.Bernd:BAABNQAECn8lAAIRAAoKJArlKQAkAQARAAoKJArlKQAkAQAAAA==.Beörn:BAABNQAECn8mAAITAAgKmSXRBQBlAwATAAgKmSXRBQBlAwAAAA==.',
Bi='Birgir:BAAANQAECgEIAQAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAABNQAECn8aAAIUAAkKiwtyOABQAQAUAAkKiwtyOABQAQAAAA==.',
Br='Braids:BAAANQAECgUIBwAAAA==.Breezy:BAACNQAFFH8GAAIJAAIKIA4JIgCIAAAJAAIKIA4JIgCIAAA1AAQKfzYAAgkACgoCHiw3AHoCAAkACgoCHiw3AHoCAAAA.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAABNQAECn8oAAMVAAkKTxvjGAAQAgAVAAkKfxnjGAAQAgAWAAIKhB2RaACcAAAAAA==.',
Bu='Buttrbiskit:BAAANQAECggIDwAAAA==.',
By='Byanca:BAABNQAECn8XAAIUAAcKRwP+SgDOAAAUAAcKRwP+SgDOAAAAAA==.',
Ca='Caine:BAABNQAECn8hAAIXAAkK/hmsDwAvAgAXAAkK/hmsDwAvAgAAAA==.Callen:BAAANQADCgEIAQAAAA==.Carlonus:BAAANQADCggICwABNQAECgoKMgAMAGkRAA==.Casey:BAAANQAECgUIEAAAAA==.Castyblasty:BAABNQAECn85AAMHAAoKzRWaQQA6AgAHAAoKzRWaQQA6AgAIAAEKAAkiRQA5AAAAAA==.Cataaria:BAAANQAECgYIBgABNQAECggIDgANAAAAAA==.',
Ce='Cellina:BAABNQAECn8XAAIUAAgKpApzNADlAAAUAAgKpApzNADlAAAAAA==.',
Ch='Chiman:BAAANQADCgcJCQABNQAECgUIBAANAAAAAA==.Chromatica:BAAANQADCgYIBgAAAA==.',
Ci='Cignus:BAAANQAECggICQAAAA==.',
Cl='Classá:BAABNQAECn8/AAQTAAoKvh6wCwAPAwATAAoKvh6wCwAPAwAOAAkKrBuYHgDVAgARAAcKAw/LLgAkAQAAAA==.',
Co='Codedd:BAAANQADCgYIDAAAAA==.Corlys:BAABNQAECn8iAAMJAAoKmREfoADhAQAJAAoKmREfoADhAQAQAAEKAAC1ewAhAAAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAABNQAECn8dAAIKAAkKbwYpowBRAQAKAAkKbwYpowBRAQAAAA==.Crue:BAABNQAECn85AAMTAAkKIQ9SMABSAQATAAgKcA1SMABSAQAOAAkKfghcNwBCAQAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIJAgAAAA==.Curthar:BAAANQAECgQIAwABNQAECgQICQANAAAAAA==.',
Cy='Cynboom:BAAANQADCggIJwAAAA==.Cyndee:BAABNQAECn9BAAIYAAoKihZkBwAnAgAYAAoKihZkBwAnAgAAAA==.Cynnafrost:BAAANQADCgQICgAAAA==.Cytenk:BAAANQAECgUICQAAAA==.',
Da='Dadda:BAABNQAECn9IAAIZAAoK/x9+BwDHAgAZAAoK/x9+BwDHAgAAAA==.Dagad:BAAANQADCgIIAgAAAA==.Daisynukes:BAABNQAECn8ZAAIHAAoKPQzHaADRAQAHAAoKPQzHaADRAQABNQAECgoKLAASAMoOAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAABNQAECn8rAAMQAAkK5xDPJgAlAQAQAAkK5xDPJgAlAQAJAAEKDgq3lwEqAAAAAA==.Dankdruid:BAAANQADCgUICgABNQAECgUIFgAaAEcSAA==.Darkschi:BAABNQAECn8qAAIUAAoKAAu6HgCTAQAUAAoKAAu6HgCTAQAAAA==.Darthsith:BAAANQABCgQIBAAAAA==.Darthwing:BAAANQADCgcIDgAAAA==.Dartos:BAABNQAECn9OAAIVAAoKDCWCBAArAwAVAAoKDCWCBAArAwAAAA==.',
De='Deepmagic:BAAANQAECggIDQAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.Destrûction:BAAANQADCgUIBQAAAA==.',
Di='Diluvium:BAABNQAECn8nAAIQAAoK2xU3GgAfAgAQAAoK2xU3GgAfAgAAAA==.Discodank:BAABNQAECn8WAAMaAAUKRxKxCAAYAQAaAAUKRxKxCAAYAQAEAAUK5QYwOwCyAAAAAA==.',
Dj='Djpleasant:BAACNQAFFH8OAAIIAAcKIhNOAQBqAQAIAAcKIhNOAQBqAQA1AAQKf0wAAwgACgquJC8CAFMDAAgACgpSJC8CAFMDAAcABgomIQScAFoBAAAA.',
Do='Dontcare:BAABNQAECn8pAAMKAAoK0x9RLACCAgAKAAkKeiFRLACCAgAZAAMKiQ8dZQCXAAAAAA==.',
Dw='Dwailn:BAAANQABCgMIAwAAAA==.',
['Dû']='Dûo:BAABNQAECn80AAMSAAoKixpkRwCgAQASAAkK/R1kRwCgAQAbAAMKLAvGMgBMAAAAAA==.',
Ea='Eatmorpizza:BAABNQAECn8VAAITAAYK7BBfNQAwAQATAAYK7BBfNQAwAQAAAA==.',
Ee='Eegnormu:BAAANQAECgQICQAAAA==.Eegroll:BAABNQAECn9DAAQCAAoKaRtZBwDIAgACAAoKXRtZBwDIAgAUAAgKOxN8MwB6AQAcAAcKqgVxLQAAAQAAAA==.',
Eg='Egraw:BAABNQAECn8lAAMdAAgKNyHxUQD2AQAdAAgKNyHxUQD2AQAXAAEK/yBqNgBXAAAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Em='Emilwhaury:BAAANQAECgYIBwAAAA==.',
Ep='Epia:BAABNQAECn8mAAMUAAoK/xLpHACkAQAUAAoK/xLpHACkAQACAAIKCAbALQBPAAAAAA==.',
Es='Esdéath:BAABNQAECn9UAAIDAAkKEyB+GwAFAwADAAkKEyB+GwAFAwAAAA==.Essaila:BAABNQAECn8xAAIPAAoKehEaFAC7AQAPAAoKehEaFAC7AQAAAA==.',
Et='Etherwalker:BAABNQAECn8WAAIdAAgK2hrebQBJAgAdAAgK2hrebQBJAgAAAA==.',
Ex='Excision:BAABNQAECn8lAAILAAgKzAvMEAAYAQALAAgKzAvMEAAYAQAAAA==.',
Fa='Fahbio:BAABNQAECn8aAAIQAAcKsAQ+PgCeAAAQAAcKsAQ+PgCeAAAAAA==.Faleros:BAAANQADCgMIAwAAAA==.Fanskar:BAAANQAECgEIAQABNQAECgQIBAANAAAAAA==.Fatallock:BAACNQAFFH8FAAIBAAMKoAMmKgBuAAABAAMKoAMmKgBuAAA1AAQKf4QAAgEACgo0Ehk/AAgCAAEACgo0Ehk/AAgCAAAA.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQAECgEIAQAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgcIBwANAAAAAA==.',
Fl='Flaildh:BAAANQAECgYIBgAAAA==.Flailuid:BAAANQAECgMIBwAAAA==.',
Fo='Forthstryke:BAAANQADCggIEQAAAA==.',
Fr='Fresita:BAABNQAECn8eAAMOAAYKAQ1qVAC7AAAOAAYKAQ1qVAC7AAAPAAQKpAXDPwBAAAAAAA==.Fridaychill:BAABNQAECn9KAAIUAAoKECDACgCoAgAUAAoKECDACgCoAgAAAA==.Frozarke:BAABNQAECn8yAAMMAAoKaRHdCAD/AQAMAAoKaRHdCAD/AQAeAAEKVACxVgATAAAAAA==.',
Fu='Fudd:BAABNQAECn8XAAIKAAcKJQ7YswAvAQAKAAcKJQ7YswAvAQAAAA==.Funk:BAAANQABCgIIAgABNQAECgQIAgANAAAAAA==.Fupa:BAAANQAECgUICAAAAA==.Furryz:BAAANQADCgYIBgABNQAECgkJGwACAPkhAA==.',
Ga='Ganymede:BAAANQAECgUIBQABNQAECgoKPwATAL4eAA==.Garou:BAABNQAECn8UAAISAAgKkBhMVQAlAgASAAgKkBhMVQAlAgAAAA==.Garres:BAABNQAECn85AAQPAAoKxBpACgAdAgAPAAoKYxpACgAdAgARAAkKIhSoGgCZAQAOAAMKYAN3mwBtAAAAAA==.',
Ge='Geedorah:BAAANQADCgUIBQABNQAECgoKSQAFAKIkAA==.Genius:BAAANQAECgYIEgAAAA==.',
Gi='Gibley:BAAANQAECgQIBAAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAABNQAECn8XAAIVAAYKTAe0TQDAAAAVAAYKTAe0TQDAAAAAAA==.Gnomie:BAAANQAECgYICwAAAA==.Gnomio:BAAANQAECgYICwAAAA==.',
Go='Gouge:BAAANQAECggISgAAAQ==.',
Gr='Granadithios:BAAANQADCgIIAgAAAA==.Griffynshu:BAABNQAECn8gAAITAAoKQhUwIQDUAQATAAoKQhUwIQDUAQAAAA==.Grrv:BAAANQABCgQIBAAAAA==.Grudgetotem:BAABNQAECn8hAAMfAAoKnRkXSQDXAQAfAAoKnRkXSQDXAQASAAEKSBVTLwE6AAAAAA==.Grunewald:BAAANQAECgQIBwAAAA==.',
Gu='Guinn:BAAANQADCggIDgABNQAECgoKMgAMAGkRAA==.Gungnir:BAABNQAECn8xAAIdAAoK6CEDEQB6AwAdAAoK6CEDEQB6AwAAAA==.',
Ha='Haki:BAAANQAECgQIBwAAAA==.Handiboy:BAABNQAECn8vAAIDAAoK1CUaCQB7AwADAAoK1CUaCQB7AwAAAA==.Hardison:BAAANQADCgYIBgAAAA==.Hayate:BAAANQAECgQIDgAAAA==.',
He='Healabull:BAAANQADCgYIDgABNQAECggIHgAWADwSAA==.Heimdall:BAABNQAECn9JAAIFAAoKoiSRBQChAwAFAAoKoiSRBQChAwAAAA==.Hellabear:BAAANQADCgQIBAAAAA==.Hellaholy:BAABNQAECn8tAAMQAAkK1RM4HwBfAQAQAAgKuhU4HwBfAQAJAAgKxwdv3AANAQAAAA==.Hellavva:BAAANQAECgYIBgAAAA==.Help:BAAANQAECgUIBwABNQAECgoKOgAHAEwfAA==.Henchling:BAABNQAECn8rAAMfAAoKaRqjPwBiAgAfAAoKaRqjPwBiAgASAAgKwgsqbwAkAQAAAA==.',
Hi='Hina:BAAANQADCggIDgAAAA==.',
Ho='Holexios:BAAANQAECgUIBAAAAA==.Horine:BAABNQAECn8aAAIKAAkKxQS5uwAfAQAKAAkKxQS5uwAfAQAAAA==.',
['Hö']='Hölyhell:BAAANQADCgUIBwAAAA==.',
Ic='Icieblade:BAABNQAECn8dAAMFAAkKdhnRIACoAgAFAAkKdhnRIACoAgAJAAkKUxdnWQASAgAAAA==.',
Im='Immeira:BAABNQAECn89AAIfAAoK/xsCHwCvAgAfAAoK/xsCHwCvAgAAAA==.',
Ir='Ira:BAABNQAECn8aAAIJAAkKsxTcbgDeAQAJAAkKsxTcbgDeAQABNQAECgoKLQAOAHgTAA==.',
Ja='Jackiix:BAAANQADCgYIBgAAAA==.Jackmends:BAACNQAFFH8JAAIDAAQKaSL1DwCKAQADAAQKaSL1DwCKAQA1AAQKf0cAAwMACgq+JCAHAIwDAAMACgq+JCAHAIwDAAQAAgovA1ZwAEcAAAAA.Jacksprouts:BAAANQAECgcIEwAAAA==.Jacktides:BAAANQAECgEIAQABNQAFFAQICQADAGkiAA==.Jarryl:BAAANQAECggIEAAAAA==.',
Je='Jeffrez:BAAANQAECgQIBQAAAA==.Jelerious:BAAANQAECggICAAAAA==.Jenoside:BAAANQAECggIMAAAAQ==.',
Ji='Jindu:BAAANQAECggICAAAAA==.',
Jo='Journei:BAABNQAECn83AAMfAAoKZhdqMgA+AgAfAAkKrhVqMgA+AgASAAYK8ASjwwALAQAAAA==.',
Ju='Judging:BAABNQAECn8oAAMJAAoKQBFPtQBQAQAJAAkK2BBPtQBQAQAFAAkKGAi8ngBIAQAAAA==.Juggernaught:BAAANQAECggICAAAAA==.Jurb:BAAANQAECggIEAAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIGQAAAA==.Kaitos:BAAANQAECgQICQAAAA==.',
Ke='Kegz:BAABNQAECn8bAAMCAAkK+SHBAwBOAwACAAgKZSTBAwBOAwAUAAMKzA03PACyAAAAAA==.Kelendrian:BAAANQAECgUIBQAAAA==.Kellayna:BAABNQAECn8YAAIJAAYK8QXeHAHvAAAJAAYK8QXeHAHvAAAAAA==.Keylö:BAABNQAECn8xAAIVAAkKfhdSHgDcAQAVAAkKfhdSHgDcAQAAAA==.',
Kh='Khoulethius:BAAANQADCgYIBwAAAA==.',
Ki='Kimbot:BAABNQAECn8fAAMKAAoKJheYRQCbAgAKAAoKJheYRQCbAgAZAAEKAACzjgAxAAAAAA==.Kimigosa:BAAANQAECggIBwAAAA==.',
Kl='Klerik:BAACNQAFFH8VAAIBAAQK1xu/EAAMAQABAAQK1xu/EAAMAQA1AAQKf0cABAEACgqpJAASAEcDAAEACgqpJAASAEcDACAABgo/Di8nAD0BACEAAQoKBiQ0ACoAAAAA.',
Kn='Kníghtmare:BAAANQAECgUICgAAAA==.',
Ko='Koragg:BAACNQAFFH8pAAIWAAcKByJoBADpAQAWAAcKByJoBADpAQA1AAQKfzwAAhYACgoSI5wRACADABYACgoSI5wRACADAAAA.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgUIBQAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAABNQAECn8hAAILAAoKfgsmDwA8AQALAAoKfgsmDwA8AQAAAA==.',
Kr='Kratus:BAAANQAECgEIAQAAAA==.Krissia:BAABNQAECn9AAAMiAAoKOhcVIgAsAgAiAAoKOhcVIgAsAgAVAAUKMgbclgDUAAAAAA==.',
Ky='Kymerah:BAAANQABCgYICAAAAA==.Kyntaliia:BAAANQADCgYIDAAAAA==.',
['Kî']='Kîn:BAABNQAECn8aAAIjAAcK9xZvMgCuAQAjAAcK9xZvMgCuAQAAAA==.',
La='Lailey:BAAANQADCggICAAAAA==.Laisera:BAABNQAECn8jAAIDAAoKCQpPewCoAQADAAoKCQpPewCoAQAAAA==.Lalipop:BAABNQAECn8aAAIDAAcKPiGcTwA1AgADAAcKPiGcTwA1AgAAAA==.Landroval:BAABNQAECn8WAAILAAoK2Q+/GAC9AQALAAoK2Q+/GAC9AQAAAA==.Langedamort:BAAANQADCgEIAQAAAA==.Lastkissgbye:BAAANQABCgIIAgAAAA==.Lawson:BAABNQAECn8sAAIVAAoKtRDAHgDYAQAVAAoKtRDAHgDYAQAAAA==.',
Le='Leeoh:BAABNQAECn8rAAIHAAoKXgZmvAAbAQAHAAoKXgZmvAAbAQAAAA==.Leeohd:BAAANQAECgYIDwAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAABNQAECn8gAAITAAYKNwXYSwC3AAATAAYKNwXYSwC3AAAAAA==.',
Lo='Lovenky:BAAANQAECgIIAgAAAA==.',
Lu='Lujuria:BAABNQAECn8tAAIOAAoKeBOfHwDuAQAOAAoKeBOfHwDuAQAAAA==.Lumawig:BAAANQADCgcIBwAAAA==.Lunchdk:BAAANQAECgMIBgAAAA==.',
Ly='Lyreth:BAABNQAECn8iAAMOAAcKqAejcwD8AAAOAAYK1gWjcwD8AAATAAYKEAp2QgDkAAAAAA==.',
Ma='Madax:BAABNQAECn88AAMdAAoK4B6KIQCyAgAdAAoKLB6KIQCyAgAXAAMKqx+DJQC5AAABNQAECgoKLgAGAOcXAA==.Mambos:BAAANQAECgQIBAAAAA==.Manach:BAAANQAECgQICQAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAABNQAECn87AAIiAAkKRRcyMADTAQAiAAkKRRcyMADTAQAAAA==.Meganfox:BAAANQAECgQJCAABNQAECgoKKQAKANMfAA==.Melinara:BAAANQADCgYIBgAAAA==.Merilde:BAABNQAECn8fAAQTAAoK/xhMHQD8AQATAAgKtBZMHQD8AQARAAoKsBHSGgDOAQAOAAQK9Am5hAC+AAAAAA==.Metrolinea:BAABNQAECn8oAAIHAAoKpCE+LwAuAwAHAAoKpCE+LwAuAwAAAA==.',
Mi='Micalknight:BAAANQADCggICgAAAA==.Milliy:BAABNQAECn8XAAMPAAkKhgXoHQAtAQAPAAgKBgboHQAtAQAOAAMKQQLddABWAAAAAA==.Minamel:BAAANQAECgEIAQABNQAECggIDQANAAAAAA==.Minuette:BAAANQABCgMIAwAAAA==.Missbehaving:BAABNQAECn8dAAMDAAkKtQtAbQB9AQADAAkKtQtAbQB9AQAEAAEKAAADkQAZAAAAAA==.Misstigger:BAAANQABCgQIBAAAAA==.Mistea:BAAANQABCgYIBgAAAA==.',
Mo='Mojorisin:BAAANQADCgUIBgAAAA==.Morefire:BAABNQAECn84AAIBAAoKMBrZJgDpAgABAAoKMBrZJgDpAgAAAA==.Mosmos:BAAANQAECgUIBAAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAABNQAECn8pAAMDAAgKxwvNcABxAQADAAgKxwvNcABxAQAEAAIKHgJFdwA4AAAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAABNQAECn8ZAAICAAcKwBrPDgAGAgACAAcKwBrPDgAGAgAAAA==.',
Na='Nalassa:BAABNQAECn8fAAITAAoKNBiQGAA0AgATAAoKNBiQGAA0AgABNQAECgoKJgAFAJkWAA==.Nannette:BAABNQAECn8XAAIJAAcKHQIAVQGYAAAJAAcKHQIAVQGYAAAAAA==.Narag:BAABNQAECn8mAAIKAAoKeRPJUQATAgAKAAoKeRPJUQATAgAAAA==.',
Ne='Neph:BAAANQAECggIAgAAAA==.Nephorma:BAAANQADCggJCgAAAA==.Newport:BAABNQAECn8rAAMfAAgKAh0mOgAZAgAfAAgKAh0mOgAZAgASAAQKtA1u9QCqAAAAAA==.',
Ni='Niara:BAABNQAECn9AAAMXAAoKTRHeDwCgAQAXAAoKTRHeDwCgAQAdAAIKGQftBgFYAAAAAA==.Ninevolt:BAAANQADCgIIAgABNQAECgoKKgAhACkfAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAABNQAECn83AAMfAAoKuBSMQgDzAQAfAAoKuBSMQgDzAQAbAAEKMgJ8OQApAAAAAA==.Nisle:BAAANQABCggICgABNQAECgoKMgAMAGkRAA==.Nithén:BAABNQAECn8XAAMMAAUKPwLQHgBpAAAMAAUKBALQHgBpAAALAAMKAgK+NQBgAAAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Nonenight:BAAANQADCgIIAgABNQAECgoKLAAkAPUJAA==.Nowhere:BAAANQAECgUIBwABNQAECgcIBwANAAAAAA==.Nowon:BAABNQAECn8sAAIkAAoK9QlYPAA0AQAkAAoK9QlYPAA0AQAAAA==.',
Nu='Nudream:BAABNQAECn8WAAIJAAoKwQNCBQHMAAAJAAoKwQNCBQHMAAAAAA==.Nuka:BAAANQAECgQIBQAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgcIBwANAAAAAA==.',
Oo='Oomdeath:BAAANQADCgIIAgAAAA==.',
Op='Opalyte:BAABNQAECn8ZAAIDAAcK2QoBpwAgAQADAAcK2QoBpwAgAQAAAA==.',
Oq='Oqisa:BAAANQADCgMIAwABNQAECgUIBQANAAAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAABNQAECn8tAAIKAAYK4wCaQwFZAAAKAAYK4wCaQwFZAAAAAA==.',
Ot='Othril:BAAANQAECgEIAQAAAA==.',
Ov='Overtavo:BAABNQAECn8qAAQBAAoK2RfgTwDRAQABAAkKIhfgTwDRAQAgAAEK2xycLgBFAAAhAAEKAAC1KwA/AAAAAA==.',
Ox='Oxmink:BAAANQAECgMIAwAAAA==.',
Pa='Pacobell:BAAANQADCggIEgAAAA==.Pakoros:BAABNQAECn87AAIfAAoKniFSGQDYAgAfAAoKniFSGQDYAgAAAA==.Palamar:BAABNQAECn8mAAIJAAoKrwXmvwA9AQAJAAoKrwXmvwA9AQAAAA==.Pallyanne:BAAANQADCgIIAgAAAA==.Pandsala:BAABNQAECn83AAIDAAoKZSArCQCVAwADAAoKZSArCQCVAwABNQAECgoKSQAFAKIkAA==.Papo:BAAANQADCgcIBwAAAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAABNQAECn8rAAIKAAgKrwZ3sAA2AQAKAAgKrwZ3sAA2AQAAAA==.',
Pg='Pgorlelgy:BAABNQAECn8mAAIKAAgKTRfXdQAkAgAKAAgKTRfXdQAkAgAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.Phucca:BAAANQADCggICAABNQAECgQIDgANAAAAAA==.',
Pl='Platious:BAABNQAECn8cAAIJAAkK+w9NtABSAQAJAAkK+w9NtABSAQAAAA==.',
Po='Pookaboo:BAABNQAECn8kAAIBAAgKZgJKzwChAAABAAgKZgJKzwChAAAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAACNQAFFH8LAAIEAAUKfgh1CgBQAQAEAAUKfgh1CgBQAQA1AAQKfy0AAgQACgrsG84YAIoCAAQACgrsG84YAIoCAAE1AAUUBQoLAAQAfggA.',
Pu='Purdie:BAAANQADCgEIAQABNQAECggIDgANAAAAAA==.Purdiemonk:BAAANQADCgQIBAAAAA==.Purdienir:BAAANQADCgQJBAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECggIDgANAAAAAA==.',
Py='Pyrolock:BAABNQAECn8XAAMhAAkKMSV2AQBGAwAhAAgKACV2AQBGAwABAAgK+CLAFgAuAwAAAA==.',
['Pì']='Pìke:BAAANQAECgcIBgAAAA==.',
Qe='Qeesa:BAAANQAECgUIBQAAAA==.',
Ra='Radzog:BAAANQAECgYICwAAAA==.Rafikie:BAAANQADCggIDQAAAA==.Ranni:BAABNQAECn8aAAMfAAoKMhI0cQC4AQAfAAkKFRI0cQC4AQASAAUKpA3rzQD3AAABNQAECgoKJgAFAJkWAA==.Rawmeat:BAABNQAECn8pAAMEAAoKExTXFAD7AQAEAAoKExTXFAD7AQADAAUKJA+RrwAIAQAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renew:BAAANQAECgIIAgAAAA==.Renix:BAAANQAECgQIBQAAAA==.Reno:BAAANQADCgcIBwAAAA==.',
Rh='Rhainnón:BAAANQAECgcIDQAAAA==.Rheã:BAAANQAECgUIDwAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAABNQAECn8ZAAIHAAkKlhvzbwCeAgAHAAkKlhvzbwCeAgAAAA==.',
Ro='Roombaa:BAAANQADCggICQAAAA==.Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sabrefang:BAAANQADCgcIDAAAAA==.Sack:BAAANQAECgQIBgABNQAECggIFAASAJAYAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sai:BAAANQADCggIDwAAAA==.Samsius:BAAANQABCgIIAgAAAA==.Sanctity:BAAANQAECgUIDAAAAA==.Sarson:BAAANQAECgIIAwAAAA==.Satine:BAAANQADCggIEgAAAA==.Saïma:BAAANQADCgYIBAABNQAECgcIDwANAAAAAA==.',
Sc='Scratlord:BAABNQAECn8kAAIZAAUKkwSZWwC2AAAZAAUKkwSZWwC2AAAAAA==.',
Se='Sevinas:BAABNQAECn8WAAIbAAcKFwh8IQBGAQAbAAcKFwh8IQBGAQAAAA==.',
Sh='Shadeira:BAAANQAECgcIBwAAAA==.Shamthis:BAABNQAECn8sAAMSAAoKyg5rcQDMAQASAAoKyg5rcQDMAQAfAAMK7QLHDQFMAAAAAA==.Shamwoww:BAACNQAFFH8GAAMfAAYK0wfsGQC8AAAfAAQKyQDsGQC8AAASAAIKCgOoJwA9AAA1AAQKfxoAAx8ACAoBFQFAAP4BAB8ACAoBFQFAAP4BABIABAodD9ysAJoAAAE1AAUUBQoLAAQAfggA.Shlumpa:BAAANQAECggIDwAAAA==.Shlumpcane:BAABNQAECn8ZAAIHAAYKxw7f5QDPAAAHAAYKxw7f5QDPAAAAAA==.Shokcz:BAAANQAECgUICQAAAA==.Shomba:BAAANQAECgEIAQAAAA==.Shámjackson:BAACNQAFFH8WAAIfAAYKBSPsAwBeAgAfAAYKBSPsAwBeAgA1AAQKfysAAh8ACgpmJewBAMkDAB8ACgpmJewBAMkDAAAA.',
Si='Silvey:BAABNQAECn8oAAMkAAoKxB+IEwB1AgAkAAoKxB+IEwB1AgAjAAEKAADpcAAtAAAAAA==.Sinroot:BAAANQADCgQIBAAAAA==.Sithknight:BAAANQABCgQIBgAAAA==.Sithtracker:BAAANQABCgYICAAAAA==.Sizzurp:BAAANQAECgMIAwAAAA==.',
Sk='Skeletorque:BAABNQAECn8bAAMWAAcKCgjlcACDAAAWAAYKIwnlcACDAAAVAAQKmwJSzgBQAAAAAA==.',
Sm='Smallwdruid:BAAANQAECgcICgAAAA==.',
Sn='Sneezeweed:BAAANQAECgMIAwAAAA==.Snow:BAAANQADCgcIBwABNQAECgoKRQAFAN0lAA==.Snowfawn:BAABNQAECn8UAAIKAAYKwQr02wDeAAAKAAYKwQr02wDeAAABNQAECggIFgABAFcIAA==.Snusnurae:BAAANQAECgIIAgAAAA==.',
So='Soape:BAABNQAECn8lAAIJAAoKggTX2QASAQAJAAoKggTX2QASAQAAAA==.Soloment:BAAANQADCgEIAQABNQADCggIGAANAAAAAA==.',
Sp='Specialist:BAABNQAECn8fAAIDAAkK8x6FGwDrAgADAAkK8x6FGwDrAgABNQAECgoKKQAKANMfAA==.Splishsplásh:BAAANQAECgcIEgAAAA==.Spooties:BAAANQAECggIAwAAAA==.Spoots:BAAANQAECgcIBwAAAA==.Spooty:BAAANQAECggICAAAAA==.Sprattyboii:BAAANQAECgQIBwAAAA==.',
Sq='Squishydk:BAAANQADCgUICgABNQAECgoKJwAQANsVAA==.',
Ss='Sscarlet:BAAANQAECggIEgAAAA==.',
St='Stabedyou:BAAANQAECgYIBgAAAA==.Staltis:BAAANQAECgcIDQABNQAECgoKMgAMAGkRAA==.Starzia:BAABNQAECn8sAAIaAAoKOw0QBQC5AQAaAAoKOw0QBQC5AQAAAA==.Storee:BAABNQAECn8xAAIBAAgK8wyapgCHAQABAAgK8wyapgCHAQAAAA==.',
Su='Sunk:BAABNQAECn8lAAIBAAoKRhLZUQDLAQABAAoKRhLZUQDLAQAAAA==.',
Sw='Swiftblossom:BAAANQADCggINAAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcJCwABNQAECgUIBAANAAAAAA==.Talarus:BAAANQAECgUIBwAAAA==.Tanadria:BAAANQAECggICgAAAA==.Tapioca:BAAANQAECgIIAgAAAA==.Taterdot:BAABNQAECn8qAAMhAAoKKR8bAwDUAgAhAAoKKR8bAwDUAgAgAAIKkCDoQAC/AAAAAA==.',
Te='Telm:BAAANQAECggIDQAAAA==.Tentilious:BAAANQADCgMIAwAAAA==.Tetocoochie:BAAANQADCgcIBwAAAA==.Tetsu:BAAANQAECgEIAQAAAA==.',
Th='Thaka:BAAANQADCgcIBwAAAA==.Thaÿne:BAAANQAECgMIBQAAAA==.Thebestpally:BAABNQAECn9ZAAMQAAoK8B+GBgDfAgAQAAoKuh+GBgDfAgAJAAYK+xAt7QDyAAAAAA==.Thenemisis:BAAANQAECgQIBgAAAA==.Thiccidàn:BAAANQADCgYIDAABNQAECgQIDAANAAAAAA==.Thiccsister:BAAANQADCgQIBAABNQAECgQIDAANAAAAAA==.Thiccstraza:BAAANQAECgQIDAAAAA==.',
Ti='Tidds:BAAANQAECgUICwAAAA==.Tinker:BAAANQADCgYIDAAAAA==.',
To='To:BAAANQAECggIEwAAAA==.Tobi:BAABNQAECn9FAAMFAAoK3SVDBACxAwAFAAoK3SVDBACxAwAJAAUKMhiH+gApAQAAAA==.Tootsy:BAAANQADCgcIDQAAAA==.Totemdown:BAACNQAFFH8eAAIfAAcKfCNlAQC8AgAfAAcKfCNlAQC8AgA1AAQKfycAAh8ACgqeJWIEAKcDAB8ACgqeJWIEAKcDAAE1AAQKBQgJAA0AAAAA.',
Tr='Traedaei:BAAANQADCgYICAAAAA==.Trazarath:BAABNQAECn9EAAQLAAoKbxXeDgBvAgALAAoKrBLeDgBvAgAMAAgK9BFwCwCoAQAeAAIKIBJ+LgBzAAAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.Trooged:BAAANQADCggICAABNQAECgoKRAALAG8VAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgMIBQABNQAECgYIEgANAAAAAA==.',
Un='Untiler:BAAANQADCggIBgAAAA==.',
Us='Usdaprime:BAABNQAECn8XAAIdAAcK0gZYyADPAAAdAAcK0gZYyADPAAABNQAECgcIGwAWAAoIAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECggIHAABNQAECggIMAANAAAAAQ==.',
Va='Vaelra:BAABNQAECn8YAAIeAAkKlRAgEADtAQAeAAkKlRAgEADtAQABNQAECgoKJgAFAJkWAA==.Valedaren:BAAANQADCgUIBgAAAA==.Valefyre:BAAANQAECgEIAQAAAA==.Vance:BAAANQAECgQIBAAAAA==.Varala:BAAANQAECgQICQAAAA==.',
Ve='Vel:BAACNQAFFH8QAAIVAAcKnhduBwCjAQAVAAcKnhduBwCjAQA1AAQKf30AAxUACgrAJpUAAIwDABUACgrAJpUAAIwDACIAAwqEIO5nAAEBAAAA.Velgrave:BAAANQAECggICgABNQAFFAcIEAAVAJ4XAA==.Veritas:BAABNQAECn8lAAIEAAoKHRwIEwDRAgAEAAoKHRwIEwDRAgAAAA==.Veskara:BAAANQAECgIIAQAAAA==.',
Vo='Voltsadin:BAAANQAECgEIAQABNQAECgoKKgAhACkfAA==.',
Vy='Vylana:BAABNQAECn9AAAMfAAoKMhq/MABGAgAfAAkK5xi/MABGAgASAAMKAwb2wAB1AAABNQAFFAYICgAKACkNAA==.',
['Và']='Vàlkyrie:BAAANQAFFAEIAQAAAA==.',
['Vè']='Vèl:BAAANQAECggIDQABNQAFFAcIEAAVAJ4XAA==.',
Wa='Warity:BAABNQAECn8UAAIBAAoKEA3EnQCcAQABAAoKEA3EnQCcAQAAAA==.',
We='Weneyan:BAAANQADCgYIBgAAAA==.Wetdotdruid:BAAANQAECgQIBAAAAA==.Wetdotpal:BAABNQAECn8tAAIQAAkKahMqIABXAQAQAAkKahMqIABXAQAAAA==.Wetdotrogue:BAAANQAECgIIAQAAAA==.Wetdotthirst:BAAANQAECgYIBwAAAA==.Wetdotwar:BAAANQAECgMIAwAAAA==.',
Wh='Whiteabyss:BAABNQAECn83AAMBAAoKMhO0SADoAQABAAoKMhO0SADoAQAgAAEKAAC6fAAwAAAAAA==.',
Wr='Wraith:BAAANQAECgYICwAAAA==.',
Xe='Xeral:BAAANQADCgEIAQAAAA==.Xerxseizee:BAAANQAECgcIBwAAAA==.',
Xo='Xomby:BAABNQAECn8dAAMaAAcKWRAWDgBOAQAaAAcKWRAWDgBOAQAEAAUK/wnZSwDnAAAAAA==.',
['Xì']='Xìon:BAABNQAECn9EAAQWAAoKxRlTGQAnAgAWAAoKxRlTGQAnAgAVAAUKrgWnrQCZAAAiAAUKfQpGgACYAAAAAA==.',
Ya='Yayrri:BAABNQAECn8bAAISAAoKNghDeAANAQASAAoKNghDeAANAQAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQAECgIIAgAAAA==.',
Yu='Yungstabby:BAAANQADCgYIBgABNQAECgYIFgADAF8SAA==.',
Yv='Yverari:BAAANQADCggIDwAAAA==.',
Za='Zahne:BAAANQAECgYICwABNQAECgoKQgABAEglAA==.Zaideom:BAAANQADCgQIBAAAAA==.Zatarra:BAAANQADCgUIBwAAAA==.Zavya:BAAANQADCgMJAwABNQAECgIIAgANAAAAAA==.',
Ze='Zex:BAAANQADCgUIBwABNQAECgkJJAAkAOQJAA==.Zextron:BAABNQAECn8kAAIkAAkK5AmMOgA+AQAkAAkK5AmMOgA+AQAAAA==.',
Zi='Ziaya:BAAANQAECgIIAgAAAA==.',
Zo='Zolaeus:BAAANQADCgcIDQABNQAECgUIBAANAAAAAA==.',
Zu='Zuboo:BAABNQAECn8qAAIkAAoKGAaKOgA+AQAkAAoKGAaKOgA+AQAAAA==.',
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
