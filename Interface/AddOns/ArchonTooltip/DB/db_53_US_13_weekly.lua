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

local lookup = {'Warlock-Demonology','Monk-Brewmaster','Priest-Holy','Druid-Restoration','Rogue-Assassination','Mage-Arcane','Mage-Frost','Paladin-Holy','Paladin-Retribution','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Hunter-BeastMastery','Paladin-Protection','Druid-Guardian','Shaman-Elemental','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Druid-Balance','Warrior-Fury','Hunter-Marksmanship','Shaman-Enhancement','Monk-Mistweaver','Warrior-Arms','Druid-Feral','Evoker-Preservation','Shaman-Restoration','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Priest-Discipline',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abisio:BAAANQAECgEJAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAABNQAECn8pAAIBAAoK5yGHFACGAgABAAoK5yGHFACGAgAAAA==.Acursedpeen:BAAANQAECgIIAwAAAA==.',
Ad='Aderna:BAAANQAECgQIBgAAAA==.Adoryn:BAEBNQAECn8gAAICAAkKegm3CQA9AQACAAkKegm3CQA9AQAAAA==.',
Ae='Aelara:BAABNQAECn8XAAIDAAoKZRILSwCFAQADAAoKZRILSwCFAQABNQAECgoKHwAEADQYAA==.Aessan:BAAANQAECgcIDgAAAA==.Aethelred:BAAANQADCgYIBgAAAA==.',
Ag='Agares:BAABNQAECn8oAAIFAAoKkhUcGgAsAQAFAAoKkhUcGgAsAQAAAA==.',
Ai='Aisathya:BAABNQAECn8VAAMGAAkKbBp4ygDwAQAGAAgKDxt4ygDwAQAHAAEKmBZ0PgBIAAAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Al='Aleysia:BAABNQAECn8cAAMIAAoKbw/4IwArAgAIAAoKbw/4IwArAgAJAAIKpASHgwFVAAABNQAECgoKHwAEADQYAA==.Alivar:BAAANQABCgIIAgAAAA==.',
Am='Amberfox:BAAANQAECgUIEQAAAA==.Amberscale:BAABNQAECn82AAMKAAoKgB4LAwB6AgAKAAoKgB4LAwB6AgALAAIKqxd9DwCCAAAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQAECgIIAwAMAAAAAA==.Ancientuur:BAAANQADCgYIBgABNQAECgIIAwAMAAAAAA==.Andazaren:BAABNQAECn82AAIJAAkKRQ2IbgB3AQAJAAkKRQ2IbgB3AQAAAA==.Andracca:BAAANQAECgIIAgAAAA==.Angrulus:BAABNQAECn8rAAINAAoKiRagOQD6AQANAAoKiRagOQD6AQAAAA==.Animal:BAAANQAECgIIAgAAAA==.Animlshiftr:BAAANQAECggIEgAAAA==.',
Ap='Apollo:BAABNQAECn8aAAIBAAYKEgivoQCtAAABAAYKEgivoQCtAAAAAA==.',
Ar='Arixx:BAAANQABCgIIAgAAAA==.Arrøw:BAAANQADCgQIBAAAAA==.Aryllyn:BAAANQAECgMIBwAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQAECgQIBgABNQAECgUICgAMAAAAAA==.',
At='Atris:BAAANQADCgcIBwAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQAECgQIBAABNQAECggIJgAOAOkRAA==.Banmoor:BAAANQAECgQIDAAAAA==.',
Be='Bearett:BAABNQAECn8tAAIPAAgKKh3bDwBjAgAPAAgKKh3bDwBjAgAAAA==.Belyrune:BAABNQAECn8XAAIGAAkKOgVxSQEUAQAGAAkKOgVxSQEUAQABNQAECgoKOgAQAJMSAA==.Belysurge:BAABNQAECn86AAIQAAoKkxLvJgDNAQAQAAoKkxLvJgDNAQAAAA==.Bernd:BAABNQAECn8gAAIPAAkKUAlZLgAnAQAPAAkKUAlZLgAnAQAAAA==.Beörn:BAABNQAECn8mAAIEAAgKmSXRBQBlAwAEAAgKmSXRBQBlAwAAAA==.',
Bi='Birgir:BAAANQAECgEIAQAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAABNQAECn8aAAIRAAkKewuEIgARAQARAAkKewuEIgARAQAAAA==.',
Br='Braids:BAAANQAECgUIBwAAAA==.Breezy:BAABNQAECn81AAIJAAoKAR5CHQCdAgAJAAoKAR5CHQCdAgAAAA==.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAABNQAECn8YAAMSAAgKoBmtLgASAQASAAcKqxitLgASAQATAAIKhB01UACnAAAAAA==.',
Bu='Buttrbiskit:BAAANQAECggIDwAAAA==.',
By='Byanca:BAABNQAECn8XAAIRAAcKRwP+SgDOAAARAAcKRwP+SgDOAAAAAA==.',
Ca='Caine:BAABNQAECn8hAAIUAAkK/hmVCADJAQAUAAkK/hmVCADJAQAAAA==.Callen:BAAANQADCgEIAQAAAA==.Carlonus:BAAANQADCggICwABNQAECgoKMgALAGQRAA==.Casey:BAAANQAECgUICgAAAA==.Castyblasty:BAABNQAECn8sAAMGAAoKihRoLwA0AgAGAAoKihRoLwA0AgAHAAEKAAkiRQA5AAAAAA==.Cataaria:BAAANQAECgYIBgABNQAECgcIDgAMAAAAAA==.',
Ce='Cellina:BAAANQAECgYIEAAAAA==.',
Ch='Chiman:BAAANQADCgcJCQABNQAECgUIBAAMAAAAAA==.Chromatica:BAAANQADCgYIBgAAAA==.',
Ci='Cignus:BAAANQAECggICQAAAA==.',
Cl='Classá:BAABNQAECn85AAQEAAoK8B6wCwAPAwAEAAkKDh6wCwAPAwAVAAkKrBuYHgDVAgAPAAYK4A7LLgAkAQAAAA==.',
Co='Codedd:BAAANQADCgYIDAAAAA==.Corin:BAABNQAECn9FAAMIAAoK3SVDBACxAwAIAAoK3SVDBACxAwAJAAUKMhiH+gApAQAAAA==.Corlys:BAABNQAECn8dAAMJAAkKNhIfoADhAQAJAAkKNhIfoADhAQAOAAEKAAC1ewAhAAAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAABNQAECn8aAAINAAgKmAVQmgD7AAANAAgKmAVQmgD7AAAAAA==.Crue:BAABNQAECn8oAAMEAAgKSRTGKgAKAQAEAAYK6g/GKgAKAQAVAAgKLgfBOgDcAAAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIJAgAAAA==.Curthar:BAAANQAECgIIAgABNQAECgUIBwAMAAAAAA==.',
Cy='Cynboom:BAAANQADCgYIGAAAAA==.Cyndee:BAABNQAECn8tAAIWAAoK9xKjBgDNAQAWAAoK9xKjBgDNAQAAAA==.Cynnafrost:BAAANQADCgQICgAAAA==.Cytenk:BAAANQAECgUICQAAAA==.',
Da='Dadda:BAABNQAECn83AAIXAAoK/h3SBQCrAgAXAAoK/h3SBQCrAgAAAA==.Dagad:BAAANQADCgIIAgAAAA==.Daisynukes:BAAANQAECgcIEAABNQAECgoKLAAQAMoOAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAABNQAECn8mAAIOAAgK6RGfLgBpAQAOAAgK6RGfLgBpAQAAAA==.Dankdruid:BAAANQADCgUICgABNQAECgUIDQAMAAAAAA==.Darkschi:BAABNQAECn8lAAIRAAkKswnYGQBjAQARAAkKswnYGQBjAQAAAA==.Darthsith:BAAANQABCgQIBAAAAA==.Darthwing:BAAANQADCgcIDgAAAA==.Dartos:BAABNQAECn86AAISAAoKcyHbBgDFAgASAAoKcyHbBgDFAgAAAA==.',
De='Deepmagic:BAAANQAECggIDQAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.Destrûction:BAAANQADCgUIBQAAAA==.',
Di='Diluvium:BAABNQAECn8gAAIOAAkKlRY3GgAfAgAOAAkKlRY3GgAfAgAAAA==.Discodank:BAAANQAECgUIDQAAAA==.',
Dj='Djpleasant:BAACNQAFFH8NAAIHAAYKyg9OAQBqAQAHAAYKyg9OAQBqAQA1AAQKfz0AAwcACgqaJC8CAFMDAAcACgo/JC8CAFMDAAYABgp/IJOhAAMBAAAA.',
Do='Dontcare:BAABNQAECn8hAAMNAAoKKB8bHgBzAgANAAkKtyAbHgBzAgAXAAMKiQ8dZQCXAAAAAA==.',
Dw='Dwailn:BAAANQABCgMIAwAAAA==.',
['Dû']='Dûo:BAABNQAECn80AAMQAAoKixoQLACuAQAQAAkK/R0QLACuAQAYAAMKLAvGMgBMAAAAAA==.',
Ea='Eatmorpizza:BAAANQAECgUIEQAAAA==.',
Ee='Eegnormu:BAAANQAECgQICQAAAA==.Eegroll:BAABNQAECn83AAQCAAoKVRtZBwDIAgACAAoKSRtZBwDIAgARAAgKOxN8MwB6AQAZAAcKqgVxLQAAAQAAAA==.',
Eg='Egraw:BAABNQAECn8XAAMaAAcKgCMmawBQAgAaAAcKgCMmawBQAgAUAAEK/yDlJwBdAAAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Em='Emilwhaury:BAAANQADCgYIBgAAAA==.',
Ep='Epia:BAABNQAECn8fAAMRAAoK/xJZGgBdAQARAAoK/xJZGgBdAQACAAIKCAbALQBPAAAAAA==.',
Es='Esdéath:BAABNQAECn9IAAIDAAkKsx5+GwAFAwADAAkKsx5+GwAFAwAAAA==.Essaila:BAABNQAECn8rAAIbAAoKBQ8aFAC7AQAbAAoKBQ8aFAC7AQAAAA==.',
Et='Etherwalker:BAABNQAECn8WAAIaAAgK2hrebQBJAgAaAAgK2hrebQBJAgAAAA==.',
Ex='Excision:BAABNQAECn8lAAIKAAgKzAvnCwAjAQAKAAgKzAvnCwAjAQAAAA==.',
Fa='Fahbio:BAABNQAECn8UAAIOAAcKNgQMSQDIAAAOAAcKNgQMSQDIAAAAAA==.Faleros:BAAANQADCgMIAwAAAA==.Fanskar:BAAANQAECgEIAQABNQAECgQIBAAMAAAAAA==.Fatallock:BAABNQAECn9hAAIBAAoK6w+GOgC/AQABAAoK6w+GOgC/AQAAAA==.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQAECgEIAQAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgcIBwAMAAAAAA==.',
Fl='Flaildh:BAAANQAECgIIAQAAAA==.Flailuid:BAAANQAECgMIBwAAAA==.',
Fo='Forthstryke:BAAANQADCggIEQAAAA==.',
Fr='Fresita:BAABNQAECn8bAAMVAAYKjww4QQDAAAAVAAYKjww4QQDAAAAbAAQKpAV0KwBEAAAAAA==.Fridaychill:BAABNQAECn9CAAIRAAoK9B70BwCWAgARAAoK9B70BwCWAgAAAA==.Frozarke:BAABNQAECn8yAAMLAAoKZBHdCAD/AQALAAoKZBHdCAD/AQAcAAEKVACxVgATAAAAAA==.',
Fu='Fudd:BAAANQAECgYIDgAAAA==.Funk:BAAANQABCgIIAgABNQAECgIIAgAMAAAAAA==.Fupa:BAAANQAECgUICAAAAA==.Furryz:BAAANQADCgYIBgABNQAECggIGgACAGUkAA==.',
Ga='Garou:BAABNQAECn8UAAIQAAgKkBhMVQAlAgAQAAgKkBhMVQAlAgAAAA==.Garres:BAABNQAECn8tAAQbAAkKrBpfDQBGAgAbAAkKEBpfDQBGAgAPAAgKCRaiEgCJAQAVAAMKYAN3mwBtAAAAAA==.',
Ge='Genius:BAAANQAECgYIEAAAAA==.',
Gi='Gibley:BAAANQAECgQIBAAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAAANQAECgUIDQAAAA==.Gnomie:BAAANQAECgYICwAAAA==.Gnomio:BAAANQAECgYICwAAAA==.',
Go='Gouge:BAAANQAECggINgAAAQ==.',
Gr='Granadithios:BAAANQADCgIIAgAAAA==.Griffynshu:BAABNQAECn8bAAIEAAkKrhT5KgDGAQAEAAkKrhT5KgDGAQAAAA==.Grrv:BAAANQABCgQIBAAAAA==.Grudgetotem:BAABNQAECn8hAAMdAAoKnRlaLAD2AQAdAAoKnRlaLAD2AQAQAAEKSBVTLwE6AAAAAA==.Grunewald:BAAANQAECgQIBwAAAA==.',
Gu='Guinn:BAAANQADCggICAABNQAECgoKMgALAGQRAA==.Gungnir:BAABNQAECn8xAAIaAAoK6CEDEQB6AwAaAAoK6CEDEQB6AwAAAA==.',
Ha='Haki:BAAANQAECgQIBwAAAA==.Handiboy:BAABNQAECn8oAAIDAAoKtSUaCQB7AwADAAoKtSUaCQB7AwAAAA==.Hardison:BAAANQADCgYIBgAAAA==.Hayate:BAAANQAECgQIDgAAAA==.',
He='Healabull:BAAANQADCgYIDgABNQAECgcIHAATABkSAA==.Heimdall:BAABNQAECn84AAIIAAoKoiSRBQChAwAIAAoKoiSRBQChAwAAAA==.Hellabear:BAAANQADCgQIBAAAAA==.Hellaholy:BAABNQAECn8nAAMOAAkKoxNSEwBzAQAOAAgKuhVSEwBzAQAJAAYKngctFgH6AAAAAA==.Hellavva:BAAANQAECgQIBgAAAA==.Help:BAAANQAECgEIAgABNQAECgoKNQAGAEwfAA==.Henchling:BAABNQAECn8iAAMdAAoKORqjPwBiAgAdAAoKORqjPwBiAgAQAAYKfQ1sqABDAQAAAA==.',
Hi='Hina:BAAANQADCggIDgAAAA==.',
Ho='Holexios:BAAANQAECgUIBAAAAA==.Horine:BAABNQAECn8VAAINAAgKMQMfzACaAAANAAgKMQMfzACaAAAAAA==.',
['Hö']='Hölyhell:BAAANQADCgUIBwAAAA==.',
Ic='Icieblade:BAAANQAECggIDQAAAA==.',
Im='Immeira:BAABNQAECn81AAIdAAkKEht1HQBXAgAdAAkKEht1HQBXAgAAAA==.',
Ir='Ira:BAAANQAECgQICAABNQAECgoKIwAVAGIQAA==.',
Ja='Jackiix:BAAANQADCgYIBgAAAA==.Jackmends:BAABNQAECn8/AAMDAAoKYCQgBwCMAwADAAoKYCQgBwCMAwAeAAIKLwNWcABHAAAAAA==.Jacksprouts:BAAANQAECgUICQAAAA==.Jacktides:BAAANQAECgEIAQABNQAECgoKPwADAGAkAA==.Jarryl:BAAANQAECggIEAAAAA==.',
Je='Jeffrez:BAAANQAECgQIBAAAAA==.Jelerious:BAAANQAECggICAAAAA==.Jenoside:BAAANQAECggIMAAAAQ==.',
Ji='Jindu:BAAANQAECggICAAAAA==.',
Jo='Journei:BAABNQAECn8pAAMdAAkKSxi3JAAmAgAdAAgKeRa3JAAmAgAQAAYK8ASjwwALAQAAAA==.',
Ju='Judging:BAABNQAECn8dAAMIAAkK8w68ngBIAQAIAAcKUwi8ngBIAQAJAAYKuxKHHAHvAAAAAA==.Jurb:BAAANQAECggICAAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIGQAAAA==.Kaitos:BAAANQAECgUIBwAAAA==.',
Ke='Kegz:BAABNQAECn8aAAMCAAgKZSTBAwBOAwACAAgKZSTBAwBOAwARAAIK+ApGNwB9AAAAAA==.Kellayna:BAAANQAECgUIDgAAAA==.Keylö:BAABNQAECn8nAAISAAkKfxaCFgDMAQASAAkKfxaCFgDMAQAAAA==.',
Kh='Khoulethius:BAAANQADCgYIBwAAAA==.',
Ki='Kimbot:BAABNQAECn8fAAMNAAoKJheYRQCbAgANAAoKJheYRQCbAgAXAAEKAACzjgAxAAAAAA==.Kimigosa:BAAANQAECgUIBQAAAA==.',
Kl='Klerik:BAACNQAFFH8SAAIBAAMKQhVLFwCdAAABAAMKQhVLFwCdAAA1AAQKf0AABAEACgp3IwASAEcDAAEACgp3IwASAEcDAB8ABgo/Di8nAD0BACAAAQoKBiQ0ACoAAAAA.',
Kn='Kníghtmare:BAAANQAECgUICgAAAA==.',
Ko='Koragg:BAACNQAFFH8dAAITAAYK5yHLAwCIAQATAAYK5yHLAwCIAQA1AAQKfzcAAhMACgqBIpwRACADABMACgqBIpwRACADAAAA.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgUIBQAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAABNQAECn8cAAIKAAkKGAidHwBcAQAKAAkKGAidHwBcAQAAAA==.',
Kr='Kratus:BAAANQAECgEIAQAAAA==.Krissia:BAABNQAECn81AAMhAAoK+RaWIwCxAQAhAAoK+RaWIwCxAQASAAUKMgbclgDUAAAAAA==.',
Ky='Kymerah:BAAANQABCgYICAAAAA==.Kyntaliia:BAAANQADCgYIDAAAAA==.',
['Kî']='Kîn:BAABNQAECn8UAAIiAAcK9xZvMgCuAQAiAAcK9xZvMgCuAQAAAA==.',
La='Lailey:BAAANQADCggICAAAAA==.Laisera:BAABNQAECn8hAAIDAAoK7AlPewCoAQADAAoK7AlPewCoAQAAAA==.Lalipop:BAAANQAECgYIEAAAAA==.Landroval:BAABNQAECn8VAAIKAAkKMRC/GAC9AQAKAAkKMRC/GAC9AQAAAA==.Langedamort:BAAANQADCgEIAQAAAA==.Lastkissgbye:BAAANQABCgIIAgAAAA==.Lawson:BAABNQAECn8nAAISAAkKlBDjGACxAQASAAkKlBDjGACxAQAAAA==.',
Le='Leeoh:BAABNQAECn8kAAIGAAoKUQVnnAAMAQAGAAoKUQVnnAAMAQAAAA==.Leeohd:BAAANQAECgYIDwAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAAANQAECgYIEQAAAA==.',
Lo='Lovenky:BAAANQAECgIIAgAAAA==.',
Lu='Lujuria:BAABNQAECn8jAAIVAAoKYhBIGADVAQAVAAoKYhBIGADVAQAAAA==.Lumawig:BAAANQADCgcIBwAAAA==.Lunchdk:BAAANQAECgMIBgAAAA==.',
Ly='Lyreth:BAABNQAECn8cAAMVAAcKQAejcwD8AAAVAAYK1gWjcwD8AAAEAAYKFQgTSAD0AAAAAA==.',
Ma='Madax:BAABNQAECn8uAAIaAAkK8xtqLAArAgAaAAkK8xtqLAArAgABNQAECgoKKAAFAJIVAA==.Mambos:BAAANQAECgQIBAAAAA==.Manach:BAAANQAECgIIAwAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAABNQAECn8tAAIhAAkK2RX2MwAOAgAhAAkK2RX2MwAOAgAAAA==.Meganfox:BAAANQAECgQJCAABNQAECgoKIQANACgfAA==.Melinara:BAAANQADCgYIBgAAAA==.Merilde:BAAANQAECggIEwAAAA==.Metrolinea:BAABNQAECn8nAAIGAAoKpCE+LwAuAwAGAAoKpCE+LwAuAwAAAA==.',
Mi='Micalknight:BAAANQADCggICgAAAA==.Milliy:BAABNQAECn8XAAMbAAkKhgXoHQAtAQAbAAgKBgboHQAtAQAVAAMKQQLaXgBYAAAAAA==.Minamel:BAAANQAECgEIAQABNQAECgcIDQAMAAAAAA==.Minuette:BAAANQABCgMIAwAAAA==.Missbehaving:BAABNQAECn8YAAMDAAcK0QqVawAUAQADAAcK0QqVawAUAQAeAAEKAAADkQAZAAAAAA==.Misstigger:BAAANQABCgQIBAAAAA==.Mistea:BAAANQABCgYIBgAAAA==.',
Mo='Mojorisin:BAAANQADCgUIBgAAAA==.Morefire:BAABNQAECn8sAAIBAAoK0hfZJgDpAgABAAoK0hfZJgDpAgAAAA==.Mosmos:BAAANQAECgQIBAAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAABNQAECn8jAAMDAAcK4ARGeQDrAAADAAcK4ARGeQDrAAAeAAIKHgJFdwA4AAAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAABNQAECn8ZAAICAAcKwBrPDgAGAgACAAcKwBrPDgAGAgAAAA==.',
Na='Nalassa:BAABNQAECn8fAAIEAAoKNBg9DgBLAgAEAAoKNBg9DgBLAgAAAA==.Nannette:BAAANQAECgYIDQAAAA==.Narag:BAABNQAECn8gAAINAAkK2BLZQwDVAQANAAkK2BLZQwDVAQAAAA==.',
Ne='Neph:BAAANQAECggIAgAAAA==.Nephorma:BAAANQADCggJCgAAAA==.Newport:BAABNQAECn8rAAMdAAgKAh0pIgA2AgAdAAgKAh0pIgA2AgAQAAQKtA2XlwBwAAAAAA==.',
Ni='Niara:BAABNQAECn8uAAIUAAoKRBFyCgCcAQAUAAoKRBFyCgCcAQAAAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAABNQAECn8uAAMdAAoKtROjNADMAQAdAAoKtROjNADMAQAYAAEKMgJ8OQApAAAAAA==.Nisle:BAAANQABCggICgABNQAECgoKMgALAGQRAA==.Nithén:BAAANQAECgUIEgAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Nonenight:BAAANQADCgIIAgABNQAECgoKJAAjALkJAA==.Nowhere:BAAANQAECgUIBwABNQAECgcIBwAMAAAAAA==.Nowon:BAABNQAECn8kAAIjAAoKuQnYSwBxAQAjAAoKuQnYSwBxAQAAAA==.',
Nu='Nudream:BAAANQAECgcIEgAAAA==.Nuka:BAAANQAECgQIBQAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgcIBwAMAAAAAA==.',
Oo='Oomdeath:BAAANQADCgIIAgAAAA==.',
Op='Opalyte:BAAANQAECgUIDwAAAA==.',
Oq='Oqisa:BAAANQADCgMIAwABNQAECgUIBQAMAAAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAABNQAECn8fAAINAAYKxACaQwFZAAANAAYKxACaQwFZAAAAAA==.',
Ot='Othril:BAAANQAECgEIAQAAAA==.',
Ov='Overtavo:BAABNQAECn8gAAQBAAkKGRh7aQAgAgABAAgKThd7aQAgAgAfAAEK2xwYaQBPAAAgAAEKAAC1KwA/AAAAAA==.',
Pa='Pacobell:BAAANQADCggIEgAAAA==.Pakoros:BAABNQAECn8xAAIdAAgKnyJOIgDeAgAdAAgKnyJOIgDeAgAAAA==.Palamar:BAABNQAECn8hAAIJAAkKBwWBnwAVAQAJAAkKBwWBnwAVAQAAAA==.Pallyanne:BAAANQADCgIIAgAAAA==.Pandsala:BAABNQAECn8lAAIDAAoKnRs6DgAGAwADAAoKnRs6DgAGAwABNQAECgoKOAAIAKIkAA==.Papo:BAAANQADCgcIBwAAAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAABNQAECn8fAAINAAYKkwZ+vAC4AAANAAYKkwZ+vAC4AAAAAA==.',
Pg='Pgorlelgy:BAABNQAECn8gAAINAAcKbxfXdQAkAgANAAcKbxfXdQAkAgAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.Phucca:BAAANQADCggICAABNQAECgQIDgAMAAAAAA==.',
Pl='Platious:BAABNQAECn8XAAIJAAcKVBDvyACKAQAJAAcKVBDvyACKAQAAAA==.',
Po='Pookaboo:BAABNQAECn8WAAIBAAcKSwLIugB8AAABAAcKSwLIugB8AAAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAACNQAFFH8LAAIeAAUKfgh1CgBQAQAeAAUKfgh1CgBQAQA1AAQKfygAAh4ACgolGs4YAIoCAB4ACgolGs4YAIoCAAE1AAUUBQoLAB4AfggA.',
Pu='Purdie:BAAANQADCgEIAQABNQAECgcIDgAMAAAAAA==.Purdiemonk:BAAANQADCgQIBAAAAA==.Purdienir:BAAANQADCgQJBAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECgcIDgAMAAAAAA==.',
Py='Pyrolock:BAABNQAECn8XAAMgAAkKMSV2AQBGAwAgAAgKACV2AQBGAwABAAgK+CLAFgAuAwAAAA==.',
['Pì']='Pìke:BAAANQAECgcIBgAAAA==.',
Qe='Qeesa:BAAANQAECgUIBQAAAA==.',
Ra='Radzog:BAAANQAECgYIBgAAAA==.Rafikie:BAAANQADCggIDQAAAA==.Ranni:BAABNQAECn8YAAMdAAkKtBA0cQC4AQAdAAgKYxA0cQC4AQAQAAUKpA3rzQD3AAABNQAECgoKHwAEADQYAA==.Rawmeat:BAABNQAECn8kAAMeAAgK4BNTFQB5AQAeAAgK4BNTFQB5AQADAAUKJA+RrwAIAQAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renix:BAAANQAECgQIBQAAAA==.Reno:BAAANQADCgcIBwAAAA==.',
Rh='Rhainnón:BAAANQAECgcIDQAAAA==.Rheã:BAAANQAECgUIDwAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAABNQAECn8ZAAIGAAkKlhvzbwCeAgAGAAkKlhvzbwCeAgAAAA==.',
Ro='Roombaa:BAAANQADCgYIBgAAAA==.Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sabrefang:BAAANQADCgYIBgAAAA==.Sack:BAAANQAECgQIBgABNQAECggIFAAQAJAYAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sai:BAAANQADCgcIBwAAAA==.Samsius:BAAANQABCgIIAgAAAA==.Sanctity:BAAANQAECgUIDAAAAA==.Sarson:BAAANQAECgIIAwAAAA==.Satine:BAAANQADCggIEgAAAA==.Saïma:BAAANQADCgYIBAABNQAECgcIDwAMAAAAAA==.',
Sc='Scratlord:BAABNQAECn8aAAIXAAUKkwSZWwC2AAAXAAUKkwSZWwC2AAAAAA==.',
Se='Sevinas:BAABNQAECn8UAAIYAAYKYgl8IQBGAQAYAAYKYgl8IQBGAQAAAA==.',
Sh='Shadeira:BAAANQAECgcIBwAAAA==.Shamthis:BAABNQAECn8sAAMQAAoKyg7LQwBGAQAQAAoKyg7LQwBGAQAdAAMK7QLHDQFMAAAAAA==.Shamwoww:BAAANQAFFAIIAgABNQAFFAUKCwAeAH4IAA==.Shlumpa:BAAANQAECggIDwAAAA==.Shlumpcane:BAABNQAECn8YAAIGAAYKZQ4/OQEtAQAGAAYKZQ4/OQEtAQAAAA==.Shokcz:BAAANQAECgQICQAAAA==.Shámjackson:BAACNQAFFH8VAAIdAAUKpyM7AwAGAgAdAAUKpyM7AwAGAgA1AAQKfykAAh0ACgpMJewBAMkDAB0ACgpMJewBAMkDAAAA.',
Si='Silvey:BAABNQAECn8gAAMjAAkKNx6qHgCkAgAjAAkKNx6qHgCkAgAiAAEKAADpcAAtAAAAAA==.Sinroot:BAAANQADCgQIBAAAAA==.Sithtracker:BAAANQABCgYICAAAAA==.Sizzurp:BAAANQAECgMIAwAAAA==.',
Sk='Skeletorque:BAABNQAECn8ZAAMTAAcKdQe2WQCIAAATAAYKIwm2WQCIAAASAAQKpAFSzgBQAAABNQAECggIIgAPABsWAA==.',
Sm='Smallwdruid:BAAANQAECgQIBAAAAA==.',
Sn='Sneezeweed:BAAANQAECgMIAwAAAA==.Snow:BAAANQADCgcIBwABNQAECgoKRQAIAN0lAA==.Snowfawn:BAAANQAECgcICQABNQAECggIFgABAFcIAA==.Snusnurae:BAAANQAECgIIAgAAAA==.',
So='Soape:BAABNQAECn8WAAIJAAgKAAPQNAHLAAAJAAgKAAPQNAHLAAAAAA==.',
Sp='Specialist:BAABNQAECn8VAAIDAAkKUxgrPwC4AQADAAkKUxgrPwC4AQABNQAECgoKIQANACgfAA==.Splishsplásh:BAAANQAECgUIEAAAAA==.Spooties:BAAANQAECgMIAwAAAA==.Spoots:BAAANQAECgYIBwAAAA==.Spooty:BAAANQAECggICAAAAA==.Sprattyboii:BAAANQAECgQIBwAAAA==.',
Sq='Squishydk:BAAANQADCgUICgABNQAECgkJIAAOAJUWAA==.',
Ss='Sscarlet:BAAANQAECgYIEAAAAA==.',
St='Staltis:BAAANQAECgUIBgABNQAECgoKMgALAGQRAA==.Starzia:BAABNQAECn8nAAIkAAkKXgzWAwCHAQAkAAkKXgzWAwCHAQAAAA==.Storee:BAABNQAECn8qAAIBAAgK8wyapgCHAQABAAgK8wyapgCHAQAAAA==.',
Su='Sunk:BAABNQAECn8gAAIBAAkKfRJHjADIAQABAAkKfRJHjADIAQAAAA==.',
Sw='Swiftblossom:BAAANQADCgYIJgAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcJCwABNQAECgUIBAAMAAAAAA==.Talarus:BAAANQAECgQIBwAAAA==.Tanadria:BAAANQAECgYIBgAAAA==.Tapioca:BAAANQAECgIIAgAAAA==.Taterdot:BAABNQAECn8lAAMgAAkKzR4bAwDUAgAgAAkKzR4bAwDUAgAfAAIKkCDoQAC/AAAAAA==.',
Te='Telm:BAAANQAECgcIDQAAAA==.Tentilious:BAAANQADCgMIAwAAAA==.Tetocoochie:BAAANQADCgcIBwAAAA==.Tetsu:BAAANQAECgEIAQAAAA==.',
Th='Thaka:BAAANQADCgcIBwAAAA==.Thaÿne:BAAANQAECgMIBQAAAA==.Thebestpally:BAABNQAECn9FAAMOAAoKEhyZCQAkAgAOAAkKuBuZCQAkAgAJAAYK9g/0uQDnAAAAAA==.Thenemisis:BAAANQAECgQIBgAAAA==.Thiccidàn:BAAANQADCgYIDAABNQAECgQIDAAMAAAAAA==.Thiccsister:BAAANQADCgQIBAABNQAECgQIDAAMAAAAAA==.Thiccstraza:BAAANQAECgQIDAAAAA==.',
Ti='Tidds:BAAANQAECgQICwAAAA==.Tinker:BAAANQADCgYIDAAAAA==.',
To='To:BAAANQAECggIEwAAAA==.Tootsy:BAAANQADCgcIDQAAAA==.Totemdown:BAACNQAFFH8eAAIdAAcKfCNlAQC8AgAdAAcKfCNlAQC8AgA1AAQKfycAAh0ACgqeJWIEAKcDAB0ACgqeJWIEAKcDAAE1AAQKBQgJAAwAAAAA.',
Tr='Traedaei:BAAANQADCgYICAAAAA==.Trazarath:BAABNQAECn9AAAMKAAoKbxXeDgBvAgAKAAoKrBLeDgBvAgALAAgK9BFwCwCoAQAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgIIAwABNQAECgYIDAAMAAAAAA==.',
Un='Untiler:BAAANQADCggIBgAAAA==.',
Us='Usdaprime:BAAANQAECgYIDAABNQAECggIIgAPABsWAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECggIHAABNQAECggIMAAMAAAAAQ==.',
Va='Vaelra:BAABNQAECn8WAAIcAAkKWw//CgDsAQAcAAkKWw//CgDsAQABNQAECgoKHwAEADQYAA==.Valedaren:BAAANQADCgUIBgAAAA==.Valefyre:BAAANQAECgEIAQAAAA==.Vance:BAAANQAECgQIBAAAAA==.Varala:BAAANQAECgIIAwAAAA==.',
Ve='Vel:BAACNQAFFH8NAAISAAYKABZuBwCjAQASAAYKABZuBwCjAQA1AAQKf2gAAxIACgqDJpUBAOcDABIACgqDJpUBAOcDACEAAwqEIO5nAAEBAAAA.Velgrave:BAAANQAECggIBQABNQAFFAYIDQASAAAWAA==.Veritas:BAABNQAECn8jAAIeAAoKHRwIEwDRAgAeAAoKHRwIEwDRAgAAAA==.Veskara:BAAANQAECgEIAQAAAA==.',
Vo='Voltsadin:BAAANQADCgEIAQABNQAECgkJJQAgAM0eAA==.',
Vy='Vylana:BAABNQAECn81AAIdAAgKIRl8LQDwAQAdAAgKIRl8LQDwAQABNQAFFAYICgANACkNAA==.',
['Và']='Vàlkyrie:BAAANQAFFAEIAQAAAA==.',
['Vè']='Vèl:BAAANQAECgIIAgABNQAFFAYIDQASAAAWAA==.',
Wa='Warity:BAAANQAECgcIEAAAAA==.',
We='Weneyan:BAAANQADCgYIBgAAAA==.Wetdotdruid:BAAANQAECgQIBAAAAA==.Wetdotpal:BAABNQAECn8iAAIOAAgKQBGGKQCQAQAOAAgKQBGGKQCQAQAAAA==.Wetdotrogue:BAAANQAECgEIAQAAAA==.Wetdotthirst:BAAANQAECgYIBwAAAA==.Wetdotwar:BAAANQAECgMIAwAAAA==.',
Wh='Whiteabyss:BAABNQAECn80AAMBAAkKohKsPAC2AQABAAkKohKsPAC2AQAfAAEKAAC6fAAwAAAAAA==.',
Wr='Wraith:BAAANQAECgYICwAAAA==.',
Xe='Xeral:BAAANQADCgEIAQAAAA==.Xerxseizee:BAAANQAECgcIBwAAAA==.',
Xo='Xomby:BAABNQAECn8ZAAMkAAcKtA8WDgBOAQAkAAcKtA8WDgBOAQAeAAUKiAjZSwDnAAAAAA==.',
['Xì']='Xìon:BAABNQAECn83AAQTAAoKthiXFgDqAQATAAoKthiXFgDqAQASAAUKrgWnrQCZAAAhAAIKBAPYkwAgAAAAAA==.',
Ya='Yayrri:BAABNQAECn8WAAIQAAkKzAcUngBbAQAQAAkKzAcUngBbAQAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQAECgIIAgAAAA==.',
Yu='Yungstabby:BAAANQADCgYIBgABNQAECgYIFgADAF8SAA==.',
Yv='Yverari:BAAANQADCgcIBwAAAA==.',
Za='Zahne:BAAANQAECgYIBgABNQAECgoKOgABAI8kAA==.Zatarra:BAAANQADCgUIBwAAAA==.Zavya:BAAANQADCgMJAwABNQAECgIIAgAMAAAAAA==.',
Ze='Zex:BAAANQADCgUIBwABNQAECgcIIAAjAHEKAA==.Zextron:BAABNQAECn8gAAIjAAcKcQpcOQDtAAAjAAcKcQpcOQDtAAAAAA==.',
Zi='Ziaya:BAAANQAECgIIAgAAAA==.',
Zo='Zolaeus:BAAANQADCgcIDQABNQAECgUIBAAMAAAAAA==.',
Zu='Zuboo:BAABNQAECn8lAAIjAAkKCAXpMQAZAQAjAAkKCAXpMQAZAQAAAA==.',
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
