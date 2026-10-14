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

local lookup = {'Warlock-Demonology','Shaman-Restoration','Rogue-Assassination','Evoker-Devastation','Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Paladin-Protection','Druid-Guardian','Shaman-Elemental','Druid-Restoration','Evoker-Augmentation','Mage-Arcane','Mage-Frost','Druid-Balance','Paladin-Holy','Warrior-Fury','Hunter-Marksmanship','DeathKnight-Unholy','Shaman-Enhancement','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Druid-Feral','Evoker-Preservation','Warrior-Arms','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Frost','Warrior-Protection','DemonHunter-Havoc','Priest-Discipline',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abisio:BAAANQAECgEJAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAABNQAECn8bAAIBAAkKjhzAHAAPAwABAAkKjhzAHAAPAwAAAA==.Acursedpeen:BAAANQAECgIIAwAAAA==.',
Ad='Aderna:BAAANQAECgQIBgAAAA==.Adoryn:BAEANQAECgUIDwAAAA==.',
Ae='Aelara:BAAANQAECggIDwABNQAECgkJGAACALQQAA==.Aessan:BAAANQAECgcIDgAAAA==.',
Ag='Agares:BAABNQAECn8gAAIDAAgKdhTELgAkAgADAAgKdhTELgAkAgAAAA==.',
Ai='Aisathya:BAAANQAECgYIDQAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Al='Aleysia:BAAANQAECgUICQABNQAECgkJGAACALQQAA==.',
Am='Amberfox:BAAANQAECgUICgAAAA==.Amberscale:BAABNQAECn8nAAIEAAkKKh9oBgAiAwAEAAkKKh9oBgAiAwAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQAECgIIAwAFAAAAAA==.Ancientuur:BAAANQADCgYIBgABNQAECgIIAwAFAAAAAA==.Andazaren:BAABNQAECn8lAAIGAAgKDQs0uwCgAQAGAAgKDQs0uwCgAQAAAA==.Andracca:BAAANQAECgIIAgAAAA==.Angrulus:BAABNQAECn8cAAIHAAgKnBDZdgAfAgAHAAgKnBDZdgAfAgAAAA==.Animal:BAAANQADCgMIAwAAAA==.Animlshiftr:BAAANQAECgYICgAAAA==.',
Ap='Apollo:BAAANQAECgQIEAAAAA==.',
Ar='Arixx:BAAANQABCgIIAgAAAA==.Aryllyn:BAAANQAECgMIBAAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQAECgQIBgABNQAECgUICgAFAAAAAA==.',
At='Atris:BAAANQADCgcIBwAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQAECgQIBAABNQAECgcIHQAIAGIRAA==.Banmoor:BAAANQAECgQIBwAAAA==.',
Be='Bearett:BAABNQAECn8hAAIJAAcKJR+RDwBjAgAJAAcKJR+RDwBjAgAAAA==.Belyrune:BAAANQAECggIEAABNQAECggIKgAKAHkSAA==.Belysurge:BAABNQAECn8qAAIKAAgKeRIUVAAlAgAKAAgKeRIUVAAlAgAAAA==.Bernd:BAAANQAECgYIEwAAAA==.Beörn:BAABNQAECn8jAAILAAgKmSWuBQBmAwALAAgKmSWuBQBmAwAAAA==.',
Bi='Birgir:BAAANQAECgEIAQAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAAANQAECgYIEQAAAA==.',
Br='Braids:BAAANQAECgUIBwAAAA==.Breezy:BAABNQAECn8qAAIGAAkKhhsOQQDOAgAGAAkKhhsOQQDOAgAAAA==.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAAANQAECgQIDQAAAA==.',
Bu='Buttrbiskit:BAAANQAECggIDwAAAA==.',
By='Byanca:BAAANQAECgYIEwAAAA==.',
Ca='Caine:BAAANQAECgYIEAAAAA==.Callen:BAAANQADCgEIAQAAAA==.Carlonus:BAAANQADCggICwABNQAECggIKAAMADwUAA==.Casey:BAAANQAECgIIAgAAAA==.Castyblasty:BAABNQAECn8eAAMNAAgKnhDMzADqAQANAAgKnhDMzADqAQAOAAEKAAlORAA5AAAAAA==.',
Ce='Cellina:BAAANQAECgQICgAAAA==.',
Ch='Chiman:BAAANQADCgcJCQABNQAECgQIBAAFAAAAAA==.Chromatica:BAAANQADCgYIBgAAAA==.',
Ci='Cignus:BAAANQAECgcICAAAAA==.',
Cl='Classá:BAABNQAECn8zAAQLAAkKkh15CwAPAwALAAkKkh15CwAPAwAPAAgKih07HgDWAgAJAAYK4A7wLQAkAQAAAA==.',
Co='Codedd:BAAANQADCgYIDAAAAA==.Corin:BAABNQAECn83AAMQAAkKyiMfBACyAwAQAAkKyiMfBACyAwAGAAUKMhjt9gApAQAAAA==.Corlys:BAAANQAECgYIEwAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAAANQAECgYIEwAAAA==.Crue:BAABNQAECn8YAAMPAAcKvwVYZwArAQAPAAcKvwVYZwArAQALAAUKow50RgD4AAAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIJAgAAAA==.',
Cy='Cynboom:BAAANQADCgUIDgAAAA==.Cyndee:BAABNQAECn8eAAIRAAgKhxGhCwAFAgARAAgKhxGhCwAFAgAAAA==.Cynnafrost:BAAANQADCgQICgAAAA==.Cytenk:BAAANQAECgIIAgAAAA==.',
Da='Dadda:BAABNQAECn8lAAISAAkK7Rk5EgDQAgASAAkK7Rk5EgDQAgAAAA==.Daisynukes:BAAANQAECgQIBwABNQAECggIIgAKAFgOAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAABNQAECn8dAAIIAAcKYhEELgBpAQAIAAcKYhEELgBpAQAAAA==.Dankdruid:BAAANQADCgUICgABNQAECgQIBwAFAAAAAA==.Darkschi:BAAANQAECgYIEwAAAA==.Darthwing:BAAANQADCgcIDgAAAA==.Dartos:BAABNQAECn8oAAITAAgKcyTYDQBJAwATAAgKcyTYDQBJAwAAAA==.',
De='Deepmagic:BAAANQAECgYIDQAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.Destrûction:BAAANQADCgUIBQAAAA==.',
Di='Diluvium:BAABNQAECn8eAAIIAAcKNRrfGQAhAgAIAAcKNRrfGQAhAgAAAA==.Discodank:BAAANQAECgQIBwAAAA==.',
Dj='Djpleasant:BAACNQAFFH8MAAIOAAUKkg1FAQBqAQAOAAUKkg1FAQBqAQA1AAQKfzAAAw4ACQrDIx8CAFQDAA4ACQrDIx8CAFQDAA0ABQq2HaIxATUBAAAA.',
Do='Dontcare:BAABNQAECn8VAAMHAAkKzh1ISACSAgAHAAgKZh9ISACSAgASAAMKiQ/VYwCXAAAAAA==.',
Dw='Dwailn:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûo:BAABNQAECn8kAAMKAAkKZx1xeQCyAQAKAAkKZx1xeQCyAQAUAAIKjg8rMgBMAAAAAA==.',
Ea='Eatmorpizza:BAAANQAECgQICgAAAA==.',
Ee='Eegnormu:BAAANQAECgQICQAAAA==.Eegroll:BAABNQAECn8uAAQVAAkK4BpIBwDIAgAVAAkK0RpIBwDIAgAWAAcKyRHjMgB6AQAXAAcKqgXtLAAAAQAAAA==.',
Eg='Egraw:BAAANQAECgUIDQAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Em='Emilwhaury:BAAANQADCgYIBgAAAA==.',
Ep='Epia:BAABNQAECn8VAAMWAAkKVBFDKQDQAQAWAAkKVBFDKQDQAQAVAAIKCAY8LQBPAAAAAA==.',
Es='Esdéath:BAABNQAECn8/AAIYAAkKhB36GgAFAwAYAAkKhB36GgAFAwAAAA==.Essaila:BAABNQAECn8hAAIZAAgK0g28EwC+AQAZAAgK0g28EwC+AQAAAA==.',
Et='Etherwalker:BAAANQAECgcIEwAAAA==.',
Ex='Excision:BAABNQAECn8cAAIEAAgKTAolGwCVAQAEAAgKTAolGwCVAQAAAA==.',
Fa='Fahbio:BAAANQAECgUIDwAAAA==.Faleros:BAAANQADCgMIAwAAAA==.Fatallock:BAABNQAECn9FAAIBAAkK0g0MdQD+AQABAAkK0g0MdQD+AQAAAA==.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQAECgEIAQAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgcIBwAFAAAAAA==.',
Fl='Flaildh:BAAANQADCggIDwAAAA==.Flailuid:BAAANQAECgMIBwAAAA==.',
Fo='Forthstryke:BAAANQADCggIEQAAAA==.',
Fr='Fresita:BAAANQAECgQIDAAAAA==.Fridaychill:BAABNQAECn8oAAIWAAkKFhzrDgDxAgAWAAkKFhzrDgDxAgAAAA==.Frozarke:BAABNQAECn8oAAMMAAgKPBTNCAAAAgAMAAgKPBTNCAAAAgAaAAEKVACSVQATAAAAAA==.',
Fu='Fudd:BAAANQAECgUIDQAAAA==.Funk:BAAANQABCgIIAgABNQADCgMIAwAFAAAAAA==.Fupa:BAAANQAECgQICAAAAA==.Furryz:BAAANQADCgYIBgABNQAECggIGAAVAGUkAA==.',
Ga='Garou:BAAANQAECgcIEQAAAA==.Garres:BAABNQAECn8cAAQZAAgKBBk1DQBGAgAZAAgKBBk1DQBGAgAJAAQKEQ+ZOwDMAAAPAAMKYAPMmQBtAAAAAA==.',
Ge='Genius:BAAANQAECgUIDgAAAA==.',
Gi='Gibley:BAAANQAECgQIBAAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAAANQAECgQIBwAAAA==.Gnomie:BAAANQAECgUICgAAAA==.Gnomio:BAAANQAECgUICgAAAA==.',
Go='Gouge:BAAANQAECgcIJwAAAQ==.',
Gr='Griffynshu:BAAANQAECgYIEAAAAA==.Grrv:BAAANQABCgQIBAAAAA==.Grudgetotem:BAAANQAECgYIEwABNQAECgcICwAFAAAAAA==.Grunewald:BAAANQAECgIIAwAAAA==.',
Gu='Guinn:BAAANQADCggICAABNQAECggIKAAMADwUAA==.Gungnir:BAABNQAECn8nAAIbAAkK4iGdEwBsAwAbAAkK4iGdEwBsAwAAAA==.',
Ha='Haki:BAAANQAECgQIBwAAAA==.Handiboy:BAABNQAECn8cAAIYAAkKPSXVCAB7AwAYAAkKPSXVCAB7AwAAAA==.Hardison:BAAANQADCgYIBgAAAA==.Hayate:BAAANQAECgQICgAAAA==.',
He='Healabull:BAAANQADCgYIDgAAAA==.Heimdall:BAABNQAECn8qAAIQAAkKxSN0BQChAwAQAAkKxSN0BQChAwAAAA==.Hellabear:BAAANQADCgQIBAAAAA==.Hellaholy:BAAANQAECgQIDQAAAA==.Hellavva:BAAANQAECgQIBAAAAA==.Help:BAAANQAECgEIAQABNQAECgkJJwANALcfAA==.Henchling:BAABNQAECn8bAAMCAAgK+RvRPgBiAgACAAgK+RvRPgBiAgAKAAYKfQ1dpgBEAQAAAA==.',
Hi='Hina:BAAANQADCggIDgAAAA==.',
Ho='Holexios:BAAANQAECgQIBAAAAA==.Horine:BAAANQAECgcIDgAAAA==.',
Ic='Icieblade:BAAANQAECgUIBQAAAA==.',
Im='Immeira:BAABNQAECn8oAAICAAgKHxzxPwBeAgACAAgKHxzxPwBeAgAAAA==.',
Ir='Ira:BAAANQAECgMIAwABNQAECgYIDgAFAAAAAA==.',
Ja='Jackiix:BAAANQADCgYIBgAAAA==.Jackmends:BAABNQAECn82AAMYAAkK5yPrBgCMAwAYAAkK5yPrBgCMAwAcAAIKLwPsbgBHAAAAAA==.Jacksprouts:BAAANQAECgIIAgAAAA==.Jacktides:BAAANQAECgEIAQABNQAECgkJNgAYAOcjAA==.Jarryl:BAAANQAECggICAAAAA==.',
Je='Jelerious:BAAANQAECggICAAAAA==.Jenoside:BAAANQAECggIJwAAAQ==.',
Ji='Jindu:BAAANQAECggICAAAAA==.',
Jo='Joldada:BAAANQADCgEIAQAAAA==.Journei:BAABNQAECn8dAAMCAAcK7RQmgACHAQACAAYK7xEmgACHAQAKAAYK8AQnwQALAQAAAA==.',
Ju='Judging:BAAANQAECgYIEwAAAA==.Jurb:BAAANQAECggICAAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIGQAAAA==.Kaitos:BAAANQAECgEIAQAAAA==.',
Ke='Kegz:BAABNQAECn8YAAIVAAgKZSSzAwBPAwAVAAgKZSSzAwBPAwAAAA==.Kellayna:BAAANQAECgUICgAAAA==.Keylö:BAABNQAECn8YAAITAAcK0RhrRQD/AQATAAcK0RhrRQD/AQAAAA==.',
Kh='Khoulethius:BAAANQADCgYIBwAAAA==.',
Ki='Kimbot:BAAANQAECggIEwAAAA==.',
Kl='Klerik:BAACNQAFFH8MAAIBAAMKeRC8IgDoAAABAAMKeRC8IgDoAAA1AAQKfzMABAEACQoZJHERAEgDAAEACQoZJHERAEgDAB0ABgo/DvwmAD0BAB4AAQoKBq0zACoAAAAA.',
Kn='Kníghtmare:BAAANQAECgUICgAAAA==.',
Ko='Koragg:BAACNQAFFH8UAAIfAAUKGx+ECwCYAQAfAAUKGx+ECwCYAQA1AAQKfy8AAh8ACQrDIlARACADAB8ACQrDIlARACADAAAA.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgUIBQAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAAANQAECgYIEwAAAA==.',
Kr='Kratus:BAAANQAECgEIAQAAAA==.Krissia:BAABNQAECn8qAAMgAAgKEBW3LwAiAgAgAAgKEBW3LwAiAgATAAUKMgZulQDUAAAAAA==.',
Ky='Kymerah:BAAANQABCgYICAAAAA==.Kyntaliia:BAAANQADCgYIDAAAAA==.',
['Kî']='Kîn:BAAANQAECgUIDwAAAA==.',
La='Laisera:BAABNQAECn8dAAIYAAgKQgvseQCoAQAYAAgKQgvseQCoAQAAAA==.Lalipop:BAAANQAECgUIDwAAAA==.Landroval:BAAANQAECgYIDQAAAA==.Langedamort:BAAANQADCgEIAQAAAA==.Lastkissgbye:BAAANQABCgIIAgAAAA==.Lawson:BAABNQAECn8ZAAITAAcK2BCBYgCCAQATAAcK2BCBYgCCAQAAAA==.',
Le='Leeoh:BAABNQAECn8cAAINAAcK9gU6IAFSAQANAAcK9gU6IAFSAQAAAA==.Leeohd:BAAANQAECgYICAAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAAANQAECgQIDAAAAA==.',
Lo='Lovenky:BAAANQADCgUIBgAAAA==.',
Lu='Lujuria:BAAANQAECgYIDgAAAA==.Lumawig:BAAANQADCgcIBwAAAA==.Lunchdk:BAAANQAECgMIBgAAAA==.',
Ly='Lyreth:BAABNQAECn8ZAAMPAAcKAgeFcgD8AAAPAAYK1gWFcgD8AAALAAYKAgcyRwD0AAAAAA==.',
Ma='Madax:BAABNQAECn8bAAIbAAgKwxdhXwBsAgAbAAgKwxdhXwBsAgABNQAECggIIAADAHYUAA==.Mambos:BAAANQADCggICAAAAA==.Manach:BAAANQADCggIKAAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAABNQAECn8pAAIgAAkKYBX7MgAOAgAgAAkKYBX7MgAOAgAAAA==.Meganfox:BAAANQAECgQJCAABNQAECgkJFQAHAM4dAA==.Melinara:BAAANQADCgYIBgAAAA==.Merilde:BAAANQAECgcIDAAAAA==.Metrolinea:BAABNQAECn8fAAINAAkKhiJfLgAwAwANAAkKhiJfLgAwAwAAAA==.',
Mi='Micalknight:BAAANQADCgMIAwAAAA==.Milliy:BAAANQAECgcIEQAAAA==.Minamel:BAAANQAECgEIAQABNQAECgcIDQAFAAAAAA==.Minuette:BAAANQABCgMIAwAAAA==.Missbehaving:BAAANQAECgYIEAAAAA==.Misstigger:BAAANQABCgQIBAAAAA==.Mistea:BAAANQABCgYIBgAAAA==.',
Mo='Mojorisin:BAAANQADCgUIBgAAAA==.Morefire:BAABNQAECn8gAAIBAAkK9hrgJQDqAgABAAkK9hrgJQDqAgAAAA==.Mosmos:BAAANQAECgQIBAAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAABNQAECn8aAAMYAAcKxwJ9rgAFAQAYAAcKxwJ9rgAFAQAcAAIKHgKwdQA4AAAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAABNQAECn8ZAAIVAAcKwBqmDgAHAgAVAAcKwBqmDgAHAgAAAA==.',
Na='Nalassa:BAABNQAECn8VAAILAAkKRxUJGwBcAgALAAkKRxUJGwBcAgABNQAECgkJGAACALQQAA==.Nannette:BAAANQAECgUIDQAAAA==.Narag:BAABNQAECn8VAAIHAAcKRROxjADtAQAHAAcKRROxjADtAQAAAA==.',
Ne='Neph:BAAANQAECggIAgAAAA==.Nephorma:BAAANQADCggJCgAAAA==.Newport:BAABNQAECn8cAAMCAAgKnxxfUwAWAgACAAcKuBxfUwAWAgAKAAMKtA0d8gCqAAAAAA==.',
Ni='Niara:BAABNQAECn8eAAIhAAgKshBhGQCZAQAhAAgKshBhGQCZAQAAAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAABNQAECn8cAAMCAAgKIxRhXwDtAQACAAgKIxRhXwDtAQAUAAEKMgLQOAApAAAAAA==.Nithén:BAAANQAECgUICAAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Nonenight:BAAANQADCgIIAgABNQAECggIHQAiAK4IAA==.Novaa:BAAANQADCgUICAAAAA==.Nowhere:BAAANQAECgUIBwABNQAECgcIBwAFAAAAAA==.Nowon:BAABNQAECn8dAAIiAAgKrgj/SgBxAQAiAAgKrgj/SgBxAQAAAA==.',
Nu='Nudream:BAAANQAECgQICwAAAA==.Nuka:BAAANQAECgQIBQAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgcIBwAFAAAAAA==.',
Op='Opalyte:BAAANQAECgUIDwAAAA==.',
Oq='Oqisa:BAAANQADCgMIAwABNQAECgUIBQAFAAAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAABNQAECn8aAAIHAAYKwQBhPwFZAAAHAAYKwQBhPwFZAAAAAA==.',
Ot='Othril:BAAANQAECgEIAQAAAA==.',
Ov='Overtavo:BAABNQAECn8gAAQBAAkKGRjLZwAgAgABAAgKThfLZwAgAgAdAAEK2xx3aABPAAAeAAEKAABIKwA/AAAAAA==.',
Pa='Pacobell:BAAANQADCggIEgAAAA==.Pakoros:BAABNQAECn8oAAICAAgKKSHOIQDfAgACAAgKKSHOIQDfAgAAAA==.Palamar:BAAANQAECgUIDwAAAA==.Pallyanne:BAAANQADCgIIAgAAAA==.Pandsala:BAAANQAECggIDwABNQAECgkJKgAQAMUjAA==.Papo:BAAANQADCgcIBwAAAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAAANQAECgQIDwAAAA==.',
Pg='Pgorlelgy:BAABNQAECn8dAAIHAAcKYRbXcwAmAgAHAAcKYRbXcwAmAgAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.Phucca:BAAANQADCggICAABNQAECgQICgAFAAAAAA==.',
Pl='Platious:BAAANQAECgYIEAAAAA==.',
Po='Pookaboo:BAAANQAECgUIDAAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAACNQAFFH8KAAIcAAUKfgg1CgBRAQAcAAUKfgg1CgBRAQA1AAQKfx8AAhwACQq4GZMYAIoCABwACQq4GZMYAIoCAAE1AAUUBQoKABwAfggA.',
Pu='Purdie:BAAANQADCgEIAQABNQAECgcIDgAFAAAAAA==.Purdiemonk:BAAANQADCgQIBAAAAA==.Purdienir:BAAANQADCgQJBAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECgcIDgAFAAAAAA==.',
Py='Pyrolock:BAABNQAECn8XAAMeAAkKMSV0AQBHAwAeAAgKACV0AQBHAwABAAgK+CI7FgAuAwAAAA==.',
['Pì']='Pìke:BAAANQADCgMJAwAAAA==.',
Qe='Qeesa:BAAANQAECgUIBQAAAA==.',
Ra='Radzog:BAAANQAECgYIBgAAAA==.Rafikie:BAAANQADCggIDQAAAA==.Ranni:BAABNQAECn8YAAMCAAkKtBDhbwC4AQACAAgKYxDhbwC4AQAKAAUKpA1YywD4AAAAAA==.Rawmeat:BAABNQAECn8XAAMcAAcKnxPoKQDVAQAcAAcKnxPoKQDVAQAYAAUKJA+PrQAIAQAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renix:BAAANQAECgQIBQAAAA==.Reno:BAAANQADCgcIBwAAAA==.',
Rh='Rhainnón:BAAANQAECgcIDQAAAA==.Rheã:BAAANQAECgQIDgAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAABNQAECn8ZAAINAAkKlhuGbQCjAgANAAkKlhuGbQCjAgAAAA==.',
Ro='Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sack:BAAANQAECgQIBgABNQAECgcIEQAFAAAAAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sanctity:BAAANQAECgMIBwAAAA==.Sarson:BAAANQAECgIIAgAAAA==.Satine:BAAANQADCggIEgAAAA==.Saïma:BAAANQADCgYIBAABNQAECgcIDwAFAAAAAA==.',
Sc='Scratlord:BAAANQAECgQICQAAAA==.',
Se='Sevinas:BAAANQAECgUIDAAAAA==.',
Sh='Shadeira:BAAANQAECgcIBwAAAA==.Shamthis:BAABNQAECn8iAAMKAAgKWA7rbwDNAQAKAAgKWA7rbwDNAQACAAIKsQKoCgFMAAAAAA==.Shamwoww:BAAANQAECgQICgABNQAFFAUKCgAcAH4IAA==.Shelly:BAAANQADCgcIGwAAAA==.Shlumpa:BAAANQAECgUIBwAAAA==.Shlumpcane:BAAANQAECggIDQAAAA==.Shokcz:BAAANQAECgQICQAAAA==.Shámjackson:BAACNQAFFH8MAAICAAQKUiT/CQCqAQACAAQKUiT/CQCqAQA1AAQKfyUAAgIACQowJtwBAMkDAAIACQowJtwBAMkDAAAA.',
Si='Silvey:BAAANQAECgYIEwAAAA==.Sinroot:BAAANQADCgQIBAAAAA==.Sithknight:BAAANQABCgQIBgAAAA==.Sithtracker:BAAANQABCgYICAAAAA==.Sizzurp:BAAANQAECgMIAwAAAA==.',
Sk='Skeletorque:BAAANQAECgUICgABNQAECgYIBAAFAAAAAA==.',
Sm='Smallwdruid:BAAANQADCgIIAgAAAA==.',
Sn='Sneezeweed:BAAANQAECgMIAwAAAA==.Snow:BAAANQADCgcIBwABNQAECgkJNwAQAMojAA==.Snowfawn:BAAANQAECgUIAwABNQAECggIFQABAFcIAA==.Snusnurae:BAAANQAECgIIAgAAAA==.',
So='Soape:BAAANQAECgYICgAAAA==.',
Sp='Specialist:BAAANQAECggIDgABNQAECgkJFQAHAM4dAA==.Splishsplásh:BAAANQAECgUIDAAAAA==.Spooties:BAAANQAECgMIAwAAAA==.Spooty:BAAANQAECggICAAAAA==.Sprattyboii:BAAANQAECgQIBwAAAA==.',
Sq='Squishydk:BAAANQADCgUICgABNQAECgcIHgAIADUaAA==.',
Ss='Sscarlet:BAAANQAECgUIDwAAAA==.',
St='Staltis:BAAANQAECgUIBQABNQAECggIKAAMADwUAA==.Starzia:BAABNQAECn8ZAAIjAAcKRwn1DgA7AQAjAAcKRwn1DgA7AQAAAA==.Storee:BAABNQAECn8eAAIBAAcK4A1gpACHAQABAAcK4A1gpACHAQAAAA==.',
Su='Sunk:BAAANQAECgYIEwAAAA==.',
Sw='Swiftblossom:BAAANQADCgUIHAAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcJCwABNQAECgQIBAAFAAAAAA==.Talarus:BAAANQAECgQIBwAAAA==.Tanadria:BAAANQADCggICwAAAA==.Tapioca:BAAANQAECgIIAgAAAA==.Taterdot:BAABNQAECn8gAAMeAAcKfSMSAwDUAgAeAAcKfSMSAwDUAgAdAAIKkCCGQAC/AAAAAA==.',
Te='Telm:BAAANQAECgcIDQAAAA==.Tentilious:BAAANQADCgMIAwAAAA==.Tetocoochie:BAAANQADCgcIBwAAAA==.Tetsu:BAAANQAECgEIAQAAAA==.',
Th='Thaka:BAAANQADCgcIBwAAAA==.Thaÿne:BAAANQAECgMIBQAAAA==.Thebestpally:BAABNQAECn8vAAMIAAkKuxoMFQBXAgAIAAgKzxoMFQBXAgAGAAUK9grAGAHvAAAAAA==.Thenemisis:BAAANQAECgIIAgAAAA==.Thiccidàn:BAAANQADCgYIDAABNQAECgQICAAFAAAAAA==.Thiccsister:BAAANQADCgQIBAABNQAECgQICAAFAAAAAA==.Thiccstraza:BAAANQAECgQICAAAAA==.',
Ti='Tidds:BAAANQAECgQICwAAAA==.Tinker:BAAANQADCgYICQAAAA==.',
To='To:BAAANQAECggICwAAAA==.Tootsy:BAAANQADCgcIBwAAAA==.Totemdown:BAACNQAFFH8cAAICAAcK6SJFAQC/AgACAAcK6SJFAQC/AgA1AAQKfyUAAgIACQqQJUMEAKcDAAIACQqQJUMEAKcDAAE1AAQKBQgJAAUAAAAA.',
Tr='Traedaei:BAAANQADCgQIBAAAAA==.Trazarath:BAABNQAECn8wAAMEAAkKGRa/DgBwAgAEAAkKMhO/DgBwAgAMAAcKLRFYCwCoAQAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgIIAwABNQAECgUICwAFAAAAAA==.',
Us='Usdaprime:BAAANQAECgYIBAAAAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECgcIGQABNQAECggIJwAFAAAAAQ==.',
Va='Vaelra:BAAANQAECgYIBQABNQAECgkJGAACALQQAA==.Valedaren:BAAANQADCgUIBgAAAA==.Valefyre:BAAANQAECgEIAQAAAA==.Vance:BAAANQAECgQIBAAAAA==.Varala:BAAANQADCggIJgAAAA==.',
Ve='Vel:BAACNQAFFH8LAAITAAUKzBhXBwCjAQATAAUKzBhXBwCjAQA1AAQKf0wAAxMACQqDJpUBAOYDABMACQqDJpUBAOYDACAAAwqEIKhlAAEBAAAA.Velgrave:BAAANQAECggIAQABNQAFFAUICwATAMwYAA==.Veritas:BAABNQAECn8fAAIcAAkKxR7WEgDRAgAcAAkKxR7WEgDRAgAAAA==.Veskara:BAAANQAECgEIAQAAAA==.',
Vo='Voltsadin:BAAANQADCgEIAQABNQAECgcIIAAeAH0jAA==.',
Vy='Vylana:BAABNQAECn8rAAICAAcK1xYWYQDnAQACAAcK1xYWYQDnAQABNQAFFAQICAAHAE0QAA==.',
['Và']='Vàlkyrie:BAAANQAFFAEIAQAAAA==.',
['Vè']='Vèl:BAAANQAECgIIAgABNQAFFAUICwATAMwYAA==.',
Wa='Warity:BAAANQAECgYIDwAAAA==.',
We='Weneyan:BAAANQADCgYIBgAAAA==.Wetdotdruid:BAAANQAECgQIBAAAAA==.Wetdotpal:BAABNQAECn8aAAIIAAcKkBPxKACSAQAIAAcKkBPxKACSAQAAAA==.Wetdotrogue:BAAANQAECgEIAQAAAA==.Wetdotthirst:BAAANQAECgYIBwAAAA==.Wetdotwar:BAAANQAECgMIAwAAAA==.',
Wh='Whiteabyss:BAABNQAECn8iAAMBAAgKlBPuaQAbAgABAAgKlBPuaQAbAgAdAAEKAAATfAAwAAAAAA==.',
Wr='Wraith:BAAANQAECgUICgAAAA==.',
Xe='Xeral:BAAANQADCgEIAQAAAA==.Xerxseizee:BAAANQAECgIIAgAAAA==.',
Xo='Xomby:BAAANQAECgYIEAAAAA==.',
['Xì']='Xìon:BAABNQAECn8nAAMfAAkKbhiZLwBRAgAfAAgKfRuZLwBRAgATAAUKrgUWrACYAAAAAA==.',
Ya='Yayrri:BAAANQAECgYIDgAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQAECgIIAgAAAA==.',
Za='Zahne:BAAANQAECgYIBgAAAA==.Zatarra:BAAANQADCgUIBwAAAA==.Zavya:BAAANQADCgMJAwABNQAECgIJAgAFAAAAAA==.',
Ze='Zex:BAAANQADCgUIBwABNQAECgYIGAAiAFYKAA==.Zextron:BAABNQAECn8YAAIiAAYKVgrFUwA8AQAiAAYKVgrFUwA8AQAAAA==.',
Zi='Ziaya:BAAANQAECgIJAgAAAA==.',
Zo='Zolaeus:BAAANQADCgcIDQABNQAECgQIBAAFAAAAAA==.',
Zu='Zuboo:BAAANQAECgYIEwAAAA==.',
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
