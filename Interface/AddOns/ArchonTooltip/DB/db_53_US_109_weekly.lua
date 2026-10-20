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

local lookup = {'Priest-Shadow','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Monk-Mistweaver','DemonHunter-Havoc','Priest-Holy','DeathKnight-Frost','Mage-Arcane','Druid-Guardian','Warrior-Fury','Unknown-Unknown','Hunter-BeastMastery','Paladin-Holy','DeathKnight-Blood','Shaman-Elemental','Monk-Windwalker','Druid-Feral','Mage-Frost','Druid-Balance','Monk-Brewmaster','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','DemonHunter-Vengeance','Shaman-Restoration','Warlock-Affliction','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Mage-Fire','DemonHunter-Devourer',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abaca:BAAANQAECgIIAgAAAA==.Abacatte:BAAANQAECgUICQAAAA==.',
Ad='Adelaide:BAAANQADCgUIBwABNQAFFAcIFwABABESAA==.',
Ae='Aelthor:BAAANQAECgEIAQAAAA==.',
Al='Aleriastorm:BAAANQABCgIIAgAAAA==.Alessaxd:BAAANQAECggIEQAAAA==.Alfajhor:BAABNQAECn8yAAMCAAoKkyIUAQCyAgACAAoKkyIUAQCyAgADAAEKAACVIAEAAAAAAA==.Alfajhòr:BAAANQAECgEIBQAAAA==.Alfajhõr:BAAANQAECgYIDQAAAA==.Alkaid:BAABNQAECn8kAAMEAAkK2RPqDgDJAAAFAAcKXxVmpwC6AQAEAAgK+gvqDgDJAAAAAA==.Alladryel:BAAANQADCgYIBgAAAA==.Alleriane:BAABNQAECn8hAAIGAAoKhBmDDwCIAgAGAAoKhBmDDwCIAgAAAA==.Allone:BAABNQAECn8qAAIHAAoK9Qm3HwD/AAAHAAoK9Qm3HwD/AAAAAA==.Allunt:BAAANQAECgcICgAAAA==.Almin:BAAANQAECgIIBgAAAA==.',
Am='Ametnys:BAAANQAECgUIEAAAAA==.Amonhar:BAAANQAECgQIBQABNQAECggIIgAIAE0ZAA==.',
An='Anakata:BAAANQAECgYIDAAAAA==.Andaliz:BAABNQAECn8yAAIDAAkKByR9BwC+AwADAAkKByR9BwC+AwAAAA==.Andaril:BAAANQAECgEIAQAAAA==.Antonel:BAAANQABCgYIBgAAAA==.Antonellaes:BAAANQAECgEIAwABNQAECgYIFAAJALUEAA==.',
Ap='Aprocom:BAAANQAECgQIAwAAAA==.',
Ar='Arcanör:BAABNQAECn8bAAIKAAgKsg0D9QChAQAKAAgKsg0D9QChAQAAAA==.Arctorius:BAABNQAECn8UAAMDAAcKaQxe0AB7AQADAAcKaQxe0AB7AQACAAEKAADzdgAmAAAAAA==.Arkanidas:BAAANQAECgEIAQAAAA==.Aronys:BAAANQAECgYIDQAAAA==.Arquitetö:BAAANQADCgIIAgAAAA==.Arthashand:BAAANQADCgEIAQAAAA==.Artronis:BAABNQAECn8mAAILAAoKIhH6EwAkAgALAAoKIhH6EwAkAgAAAA==.Arukäi:BAABNQAECn8hAAMFAAgKxwr0qwCvAQAFAAgKxwr0qwCvAQAMAAMKgQdWKQBlAAAAAA==.Arägørn:BAAANQAECgQICQAAAA==.',
As='Assintomatic:BAAANQAECgEIAQABNQAECggIDwANAAAAAA==.',
At='Atriuz:BAAANQAECgQIDAAAAA==.Ats:BAAANQAECgEIAQAAAA==.',
Ay='Ayrthwill:BAAANQAECgEIAwAAAA==.',
Az='Azerotiano:BAAANQAECgQICwAAAA==.',
['Aÿ']='Aÿ:BAAANQAECgEIAQAAAA==.',
Ba='Badhealer:BAAANQADCgYIAgAAAA==.Baldraccus:BAAANQADCgcIBwAAAA==.Balk:BAABNQAECn8xAAIOAAoKhSBZIAAWAwAOAAoKhSBZIAAWAwAAAA==.Bambur:BAAANQAECgEIAQAAAA==.Barauna:BAAANQAECgEIAQAAAA==.Barbabruto:BAABNQAECn8lAAMEAAoKfhpECwCIAgAEAAoKShlECwCIAgAMAAIKRxxwDACxAAAAAA==.Barbacancer:BAAANQAECgQIBAAAAA==.Barbasanta:BAAANQAECgMIAwABNQAECgoKJQAEAH4aAA==.Batgirl:BAAANQAECgUIBwAAAA==.',
Be='Belthorsin:BAAANQADCgYIBgAAAA==.Belthorvil:BAAANQADCgEIAQAAAA==.',
Bi='Bigbag:BAAANQADCgQIBQAAAA==.Biønic:BAAANQAECgUIDQAAAA==.',
Bl='Blackheartz:BAAANQAECgEIAQAAAA==.Blackmoonx:BAABNQAECn8VAAIJAAkK2BjLKgBFAgAJAAkK2BjLKgBFAgAAAA==.Blackninja:BAAANQAECgEIAQAAAA==.Blu:BAEANQAECgEIAQABNQAECgcIFQAPALgMAA==.',
Bo='Box:BAAANQADCgMIAwAAAA==.',
Br='Brahman:BAAANQAECgEIAQAAAA==.Bright:BAAANQADCgYIBgAAAA==.Brimathor:BAAANQAECgIIAQAAAA==.Bruex:BAAANQAECgEIAgAAAA==.Bruker:BAAANQADCgIIAgAAAA==.',
Bu='Buzzumaaky:BAABNQAECn8VAAIKAAcKPhdYuAATAgAKAAcKPhdYuAATAgAAAA==.',
By='Bynhu:BAAANQADCggICAAAAA==.',
['Bá']='Bávor:BAAANQADCgEIAQAAAA==.',
['Bí']='Bílly:BAAANQAECgEIAQAAAA==.',
Ca='Callstorm:BAAANQAECgEIAwAAAA==.Calteryeker:BAAANQAECgMIDAAAAA==.Capitu:BAAANQADCggIEwABNQAECggIIQAQAKcbAA==.Capyvara:BAAANQABCgYIBwAAAA==.Caralh:BAABNQAECn8pAAIQAAkKviCrEQAfAwAQAAkKviCrEQAfAwAAAA==.Caroll:BAAANQADCgMIAwAAAA==.Caçaorda:BAAANQAECgMJBAAAAA==.',
Ce='Cecilith:BAACNQAFFH8IAAIRAAMKxgjtBwDVAAARAAMKxgjtBwDVAAA1AAQKfzIAAhEACgrjIBEGAA0CABEACgrjIBEGAA0CAAAA.Cernûnnos:BAAANQAECgQIDwAAAA==.',
Ch='Champdude:BAABNQAECn8tAAMSAAkKwBxrAgA4AgASAAkKwBxrAgA4AgAGAAEKuwwRTAA1AAAAAA==.Chopquatro:BAAANQADCggICAAAAA==.Chrnnos:BAAANQAECgYICQABNQAECgkJIAAMAJcdAA==.',
Co='Corineus:BAAANQADCgYIDQAAAA==.Cowzeroth:BAABNQAECn8nAAIRAAgKDR9NFAB4AQARAAgKDR9NFAB4AQABNQAECgoKMQAOAIUgAA==.',
Cr='Crassustitan:BAAANQAECgcICQAAAA==.Cristcalad:BAABNQAECn8ZAAMEAAYKTxY0EAC7AAAFAAUKTQ5G5gAaAQAEAAYKTxY0EAC7AAAAAA==.',
Da='Daemi:BAAANQAECggIEAAAAA==.Dakael:BAAANQABCgYIDgABNQAECgkJLwATABkcAA==.Dalaty:BAAANQAECgUIDwAAAA==.Daresh:BAAANQADCgEJAQAAAA==.Dariok:BAABNQAECn8YAAIFAAcKJQSY5wAWAQAFAAcKJQSY5wAWAQAAAA==.Darkove:BAABNQAECn8qAAIUAAoKHRAsDQDgAQAUAAoKHRAsDQDgAQAAAA==.Darrow:BAABNQAECn8nAAIJAAoKrQ1sNAALAgAJAAoKrQ1sNAALAgAAAA==.Daryan:BAAANQAECgcIEAAAAA==.Day:BAAANQAECgQIBQAAAA==.',
De='Deathinhu:BAABNQAECn8vAAIKAAkKEx4fTQDnAgAKAAkKEx4fTQDnAgAAAA==.Demoriana:BAABNQAECn8UAAMJAAYKtQQ1fQCzAAAJAAYKNAQ1fQCzAAAQAAQKiwKYtABgAAAAAA==.Dethroned:BAAANQAECgQIDQAAAA==.',
Di='Diefs:BAAANQAECgEIAQABNQAECggIIgAIAE0ZAA==.Digaoxdrx:BAAANQADCgQIBAAAAA==.Dimeros:BAABNQAECn8wAAIVAAkKZgoTDwBiAQAVAAkKZgoTDwBiAQAAAA==.Divano:BAABNQAECn8uAAIBAAoKqRy/CwAqAwABAAoKqRy/CwAqAwAAAA==.',
Dk='Dkats:BAAANQAECgEIAQAAAA==.Dkhalifa:BAAANQADCgYIBgAAAA==.',
Do='Dogowner:BAAANQAECgYIBgAAAA==.Donora:BAAANQAECgQIBAAAAA==.Dorfillaw:BAAANQAECgUICgAAAA==.Dorvana:BAAANQADCgMJAwABNQAECgkJMgADAAckAA==.',
Dr='Dracthyrius:BAAANQAECgEIAQAAAA==.Draenthar:BAAANQADCgQIBQAAAA==.Dragonstyle:BAAANQAECgcIDQAAAA==.Dragony:BAAANQAECgEIAQAAAA==.Dreez:BAAANQAECgYIBgAAAA==.Drexus:BAAANQADCgMIAwAAAA==.Drigolas:BAAANQADCgYIBgAAAA==.Druidblack:BAAANQADCgUIBQAAAA==.',
Eh='Ehomi:BAAANQADCgIIAgAAAA==.',
Ei='Eirin:BAABNQAECn8WAAIWAAUKVBM/HQAUAQAWAAUKVBM/HQAUAQAAAA==.',
El='Eldris:BAAANQADCgEIAQAAAA==.Elidibus:BAAANQADCgQIBAAAAA==.Ellvarg:BAAANQAECgEIAQAAAA==.Eltaelei:BAAANQAECgEIAQAAAA==.Eluuria:BAABNQAECn8VAAIDAAoKiwvNQgBAAQADAAoKiwvNQgBAAQAAAA==.',
En='Enkrenco:BAAANQADCgQIBAAAAA==.Ennafaryn:BAAANQABCgQIBgAAAA==.Ensabanú:BAAANQADCgQIBAAAAA==.',
Er='Erilaethaen:BAAANQAECgIIAgAAAA==.Erlek:BAAANQADCgUIDgAAAA==.Ernest:BAABNQAECn8tAAIXAAkK1yBTAgC2AgAXAAkK1yBTAgC2AgAAAA==.Erulan:BAAANQADCgQIBwAAAA==.',
Es='Estgan:BAAANQADCgMIAwAAAA==.',
Et='Ether:BAABNQAECn8YAAIQAAgKvBFRTQDAAQAQAAgKvBFRTQDAAQAAAA==.Etubrutus:BAAANQAECgEIAQAAAA==.',
Ev='Evangelouco:BAAANQADCgQIBAAAAA==.Evilbarba:BAABNQAECn8jAAIDAAkKyBhZeAA8AgADAAkKyBhZeAA8AgAAAA==.',
Ex='Exodes:BAAANQADCgMIAwAAAA==.Exort:BAAANQAECgQICAAAAA==.Exothus:BAAANQAECgQJCQAAAA==.',
Fa='Faldark:BAAANQADCgUIBQAAAA==.Fandrall:BAAANQAECgEIAQAAAA==.Faranir:BAAANQADCggIEAAAAA==.Faris:BAABNQAECn8nAAMYAAkKqBAxOAD2AQAYAAcK6BUxOAD2AQAZAAgKMgtJIADnAAABNQAECgoKMQAOAIUgAA==.Faver:BAAANQADCgMIAwAAAA==.Fayla:BAAANQAECgEIAwAAAA==.Faölin:BAABNQAECn8lAAIZAAkKbhZhEABTAQAZAAkKbhZhEABTAQAAAA==.',
Fe='Ferael:BAABNQAECn8vAAMDAAoKXBzvOADtAgADAAoKXBzvOADtAgACAAQKPQkPUACmAAAAAA==.Ferrus:BAAANQAECgQIBAAAAA==.',
Fi='Filik:BAAANQAECgEIAQAAAA==.',
Fj='Fjord:BAAANQAECgIIAgAAAA==.',
Fl='Flavors:BAABNQAECn8kAAIFAAkKzyHvKgAQAwAFAAkKzyHvKgAQAwAAAA==.Florbela:BAABNQAECn8dAAIXAAgKygsGEwAtAQAXAAgKygsGEwAtAQAAAA==.Flupy:BAAANQAECgEIAQAAAA==.',
Fr='Fredericc:BAAANQAECgYICgAAAA==.Freecs:BAAANQAECgYICgAAAA==.Freyá:BAABNQAECn8qAAMCAAoK/xllEACXAgACAAoK/xllEACXAgADAAYK2hAp3ABjAQAAAA==.Frostburn:BAAANQAECggIEAAAAA==.Froststriker:BAAANQAECgIIAQAAAA==.',
Fu='Fulvo:BAAANQADCgQIBQAAAA==.',
Ga='Gadodamorena:BAAANQAECgEIAQAAAA==.Galfur:BAABNQAECn8cAAIVAAUKOQeAfwDQAAAVAAUKOQeAfwDQAAAAAA==.Galhuda:BAAANQAECgMIAwAAAA==.Gandwelf:BAAANQADCggICAAAAA==.',
Ge='Geisty:BAAANQAECgEIAQABNQAECgIIBQANAAAAAA==.',
Gl='Glutotwo:BAAANQAECgEIAgAAAA==.',
Go='Goldchain:BAAANQAECgcICQAAAA==.Govers:BAAANQAECgEIAQABNQAECgcICQANAAAAAA==.',
Gr='Grommar:BAAANQADCgUIBQABNQAECgMIDAANAAAAAA==.Grumax:BAABNQAECn8YAAIDAAcKkAvs1wBsAQADAAcKkAvs1wBsAQAAAA==.',
Gu='Gudeath:BAABNQAECn8vAAIFAAkKnxVBJwBpAQAFAAkKnxVBJwBpAQAAAA==.Guerrerinhow:BAAANQAECgEIAQABNQAECgkJIwAVAOcNAA==.Guitianki:BAAANQADCgYICgAAAA==.Gulek:BAAANQAECgYIBAAAAA==.Gussg:BAABNQAECn8hAAMaAAgKkxVhAQCJAQAaAAcKkxVhAQCJAQAbAAUKugjo4QAFAQAAAA==.',
['Gà']='Gàladriel:BAAANQAECgYIDAAAAA==.',
['Gö']='Göhan:BAAANQAECgYICgAAAA==.',
['Gø']='Gøvers:BAAANQAECgcICQAAAA==.',
['Gü']='Güttz:BAABNQAECn8gAAIHAAgK5RCCOwDaAQAHAAgK5RCCOwDaAQAAAA==.',
Ha='Hagires:BAAANQAECgYIBwAAAA==.Hanaluna:BAAANQADCggICAAAAA==.Harchus:BAAANQADCgcIFwAAAA==.Hargarthul:BAAANQAECgEIAQAAAA==.Hazell:BAAANQAECgEIAQAAAA==.',
He='Heaveth:BAAANQADCgYIAgABNQAECgoKNgARAO8ZAA==.Hellspont:BAABNQAECn8ZAAMTAAcKIyG1BAB8AQATAAcKxB+1BAB8AQALAAIKzxv/RgCVAAAAAA==.Hendrikison:BAAANQAECgIIBAAAAA==.',
Ho='Horagalles:BAAANQAECgEIAQAAAA==.Hotmojo:BAACNQAFFH8HAAIKAAIKDhccIQBgAAAKAAIKDhccIQBgAAA1AAQKf0IAAgoACgrtIAwCAAMDAAoACgrtIAwCAAMDAAAA.',
Hu='Hunfox:BAABNQAECn86AAIOAAoK4CLACQCPAwAOAAoK4CLACQCPAwAAAA==.Hunterhearst:BAAANQADCgYIBwAAAA==.Huor:BAAANQADCggIDgAAAA==.',
Hy='Hylana:BAAANQADCggICAAAAA==.',
['Hö']='Hölycrüsh:BAABNQAECn8zAAIDAAkKyB4oFQDUAQADAAkKyB4oFQDUAQAAAA==.',
Ih='Ihntwuaed:BAAANQADCgQIBwAAAA==.',
Ik='Ikoo:BAAANQAECgYJDwAAAA==.',
Il='Illaril:BAACNQAFFH8YAAIcAAUKDQ1tAgAZAQAcAAUKDQ1tAgAZAQA1AAQKfysAAhwACgotGTQJAFkCABwACgotGTQJAFkCAAAA.',
In='Interestelar:BAAANQADCgYIBgAAAA==.Invisiblelol:BAAANQAECgUIDAAAAA==.',
Ir='Irmãodouther:BAAANQAECgUJBQAAAA==.Irridan:BAAANQADCggICQAAAA==.',
Is='Isenhearth:BAAANQABCgUIBQAAAA==.Ishtarie:BAABNQAECn8bAAIdAAgKQB8MLwClAgAdAAgKQB8MLwClAgAAAA==.',
It='Itokeszdan:BAAANQAECgEIAQAAAA==.',
Iv='Ivina:BAABNQAECn81AAMbAAoK2BgBSQB4AgAbAAoK2BgBSQB4AgAeAAEKjwasMwAsAAAAAA==.',
Iz='Izaar:BAAANQADCggIGQAAAA==.',
Ja='Jangeoffry:BAAANQAECgEIAQAAAA==.Jayser:BAAANQAECgEIAwAAAA==.',
Jh='Jhonatinha:BAAANQAECgUICAAAAA==.',
Jk='Jks:BAAANQAECgcIBgAAAA==.',
Ju='Jullianxd:BAAANQAECgQICwAAAA==.Junjih:BAAANQAECgUIBQABNQAECgcIFAAbAAYPAA==.',
Ka='Kaallew:BAAANQAECggIDwAAAA==.Kaallmonge:BAAANQAECgEIAQAAAA==.Kaelonidas:BAAANQAECgQIDgAAAA==.Kaelyaa:BAAANQADCgUIBQAAAA==.Kainer:BAAANQADCgYICQAAAA==.Kalazshar:BAABNQAECn8eAAILAAkKQAqRKQBKAQALAAkKQAqRKQBKAQAAAA==.Kalduran:BAAANQADCggIPQAAAA==.Kalelzinho:BAAANQADCgYIBAAAAA==.Kaluss:BAABNQAECn8dAAIKAAgK1whB6QC3AQAKAAgK1whB6QC3AQAAAA==.Kanduz:BAAANQAECgQIBwAAAA==.Kantaa:BAAANQAECgEIBQAAAA==.Karmabb:BAAANQAECgUIDAAAAA==.Kauss:BAAANQAECgIJAgAAAA==.Kavartu:BAABNQAECn8oAAIRAAoK7xiERQBgAgARAAoK7xiERQBgAgAAAA==.Kayli:BAAANQAECgEIBAAAAA==.Kaysa:BAAANQAECgEIAQAAAA==.',
Ke='Keillor:BAABNQAECn8nAAMdAAYK5hLFHgBvAQAdAAYK5hLFHgBvAQARAAUKQwvxwAAQAQAAAA==.Keldorian:BAAANQADCgQIBAAAAA==.Kenzou:BAABNQAECn8bAAIWAAYKFB8oBQAzAQAWAAYKFB8oBQAzAQAAAA==.Keytymari:BAAANQAECgUICwAAAA==.',
Kh='Khaliq:BAABNQAECn8hAAIHAAgKzhQdEABrAQAHAAgKzhQdEABrAQAAAA==.Khallani:BAAANQADCgIIAgABNQAECgIIBQANAAAAAA==.',
Ki='Kieran:BAAANQADCgYIBgAAAA==.Kimashi:BAAANQAECgIIAwAAAA==.Kissme:BAABNQAECn8oAAMXAAoKPxB3MwB/AQAXAAkKeQ93MwB/AQAVAAYK5AlaYwBBAQAAAA==.Kitamor:BAABNQAECn8rAAMVAAkKhgZSZAA8AQAVAAgKsQRSZAA8AQALAAQKcwnvSwB5AAAAAA==.',
Kl='Kletian:BAAANQAECgEIAQABNQAECgoKMQAOAIUgAA==.',
Ko='Koriakin:BAAANQAECgIIAgAAAA==.Korogth:BAAANQAECgYICwAAAA==.Kosmo:BAABNQAECn8gAAIeAAcKihVuCQDsAQAeAAcKihVuCQDsAQAAAA==.',
Kr='Krisyum:BAAANQAECgEIAQAAAA==.Krosmu:BAAANQADCgcIBgAAAA==.Kräsus:BAAANQADCgQIBAABNQAECggIJgAWANMgAA==.',
Ku='Kurado:BAAANQAECgIIAgAAAA==.',
Ky='Kyrysa:BAAANQAECgEIAgAAAA==.Kyrïn:BAAANQADCgUIBQABNQAFFAYIDwAYAMkWAA==.',
Kz='Kzinn:BAAANQAECgEIAQAAAA==.',
['Kö']='Körn:BAAANQAECgQIBwABNQAECgkJIQAdAPkSAA==.',
La='Ladyrichter:BAAANQAECgEIAQAAAA==.Laetus:BAABNQAECn8fAAIKAAoK8RkJTgDlAgAKAAoK8RkJTgDlAgAAAA==.Lagerthaloth:BAAANQADCgUIBAAAAA==.Laiander:BAABNQAECn8ZAAIVAAgK+AzIFQAvAQAVAAgK+AzIFQAvAQAAAA==.Laiany:BAABNQAECn8rAAIIAAgKWSJMHgD4AgAIAAgKWSJMHgD4AgAAAA==.Lainarning:BAAANQAECgEIAgAAAA==.Lani:BAAANQAECgIIBAAAAA==.Laolong:BAAANQADCgYIBgAAAA==.',
Le='Leeloo:BAAANQABCgUICAAAAA==.Leeoncamillo:BAAANQADCgYIBgABNQAECgYIFAAJALUEAA==.Leetohro:BAAANQAECgUIEAAAAA==.Leodoros:BAABNQAECn8jAAIKAAcKAAuVKgFFAQAKAAcKAAuVKgFFAQAAAA==.Lewellin:BAAANQADCgcICgAAAA==.Leyviosa:BAAANQAECgEIAQAAAA==.',
Li='Lichkíng:BAAANQAECgQIEAAAAA==.Lifeisalie:BAAANQAECgQIBAAAAA==.Lighty:BAAANQADCgQICAAAAA==.Lihr:BAAANQADCggIEAAAAA==.Lijiang:BAABNQAECn8mAAIWAAgK0yBUBgDpAgAWAAgK0yBUBgDpAgAAAA==.Lilianpotter:BAAANQADCgYIBgAAAA==.Lilibel:BAAANQAECgIIBAAAAA==.Lillit:BAAANQAECgUICgAAAA==.Lindaah:BAAANQAECgEIAgAAAA==.Lindapriesty:BAAANQADCgIIAgAAAA==.Lislfox:BAABNQAECn8iAAILAAgK2xunEABWAgALAAgK2xunEABWAgAAAA==.',
Ll='Lledritch:BAAANQAECgEIAQAAAA==.',
Lm='Lmmds:BAAANQADCgcIEwAAAA==.',
Lo='Lockdown:BAABNQAECn8zAAIbAAoKnREfJQBaAQAbAAoKnREfJQBaAQAAAA==.Loukou:BAAANQAECgEIAwAAAA==.',
Lu='Luacs:BAABNQAECn8hAAQdAAkK+RLHZwDVAQAdAAgKMRPHZwDVAQAfAAcKGxoADAA4AQARAAIKfgk3DwFtAAAAAA==.Luccoa:BAAANQAECgcICAABNQAECggIJgAWANMgAA==.Lucyfary:BAAANQADCgcICAAAAA==.Luhhrogue:BAAANQAECgMIBAAAAA==.Lunirah:BAAANQADCgYICAAAAA==.Luxwind:BAAANQAECgEIAgAAAA==.',
Ly='Lylka:BAABNQAECn8tAAMCAAkK3x+hDwCjAgACAAgKRyChDwCjAgAPAAcKxyTPBACVAgAAAA==.',
['Lé']='Léofar:BAABNQAECn8cAAICAAgKcANrGwC0AAACAAgKcANrGwC0AAAAAA==.',
['Lü']='Lücyfer:BAAANQAECgMIAwAAAA==.',
['Lÿ']='Lÿcanthrøpe:BAAANQAECgEIAQAAAA==.',
Ma='Maanu:BAAANQADCgUIBQABNQAECgEIAgANAAAAAA==.Maeghann:BAAANQADCgQIAwAAAA==.Magostosaa:BAAANQAECgEIBAAAAA==.Makani:BAAANQAECgEIAwAAAA==.Malewolyyc:BAABNQAECn8tAAMIAAoKfR+nHQD6AgAIAAoKfR+nHQD6AgABAAQK2w2pTwDTAAAAAA==.Massafera:BAABNQAECn8iAAIDAAgKnBGSMwBmAQADAAgKnBGSMwBmAQAAAA==.Mathfacbruxo:BAAANQADCgYJBgABNQAECggIIQAOAH8gAA==.Mathfacii:BAABNQAECn8hAAIOAAgKfyDlLgDgAgAOAAgKfyDlLgDgAgAAAA==.Mayanyy:BAAANQAECgEIAQAAAA==.',
Mc='Mcq:BAAANQAECgEIBAAAAA==.',
Md='Mdrdark:BAABNQAECn8jAAIgAAkKuRw/LQB+AgAgAAkKuRw/LQB+AgAAAA==.',
Me='Medz:BAABNQAECn8iAAIKAAgK0heSEwDKAQAKAAgK0heSEwDKAQAAAA==.Meetjack:BAAANQAECgEIAwAAAA==.Meinstein:BAAANQAECgEIAwAAAA==.Meizu:BAAANQAECgQJDgAAAA==.Mellkor:BAABNQAECn8jAAIHAAcKWhpHEQBhAQAHAAcKWhpHEQBhAQAAAA==.Meneláu:BAAANQADCggICAAAAA==.Metamorful:BAAANQAECggIEAAAAA==.',
Mi='Mihsi:BAAANQAECgQIBAAAAA==.Milim:BAABNQAECn8YAAQhAAkKkg48HwBgAQAhAAcKuQ08HwBgAQAiAAQKZwZBFgDNAAAjAAIKZwLMUQApAAAAAA==.Minilock:BAAANQAECgQIBgAAAA==.Mistogunn:BAAANQADCggICAAAAA==.Mitchell:BAAANQAECgEIAQABNQAECgEIAwANAAAAAA==.',
Ml='Mls:BAAANQADCgYICwAAAA==.',
Mm='Mmarcão:BAAANQAECgQIBwAAAA==.',
Mo='Modes:BAABNQAECn8hAAIQAAgKpxv2DgBsAQAQAAgKpxv2DgBsAQAAAA==.Moffir:BAAANQADCgYIBgAAAA==.Mogrus:BAAANQAECgEIAQAAAA==.Mohanninha:BAAANQAECgUIBQAAAA==.Mohotok:BAABNQAECn8lAAIDAAkKFgqHMABvAQADAAkKFgqHMABvAQAAAA==.Monshiro:BAAANQAECgEIAQABNQAECgYICgANAAAAAA==.Morkath:BAAANQADCggICAAAAA==.Mortank:BAAANQAECgEIAQABNQAECgcIDgANAAAAAA==.Mortixxia:BAABNQAECn8hAAMaAAYKUx26DgAPAgAaAAYKUx26DgAPAgAbAAIKDQ5atAA7AAAAAA==.',
Mu='Murano:BAABNQAECn8nAAIMAAkK1xaRCABbAgAMAAkK1xaRCABbAgAAAA==.',
['Má']='Máia:BAAANQAECgYIEAAAAA==.',
['Mä']='Mändosz:BAABNQAECn8eAAIJAAgKHRkVKABXAgAJAAgKHRkVKABXAgAAAA==.',
['Mé']='Ménace:BAAANQAECgMIAwABNQAECggIEAANAAAAAA==.',
['Mÿ']='Mÿstyna:BAAANQAECgEIAQAAAA==.',
Na='Nagts:BAAANQADCggICgAAAA==.Nalathiel:BAAANQAECgYIBgAAAA==.Narancia:BAAANQAECgUICwABNQAECgYICgANAAAAAA==.Narrih:BAAANQAECgIIBQAAAA==.Nazawill:BAAANQADCgQIBAAAAA==.Nazzh:BAAANQAECggIDAABNQAFFAUICAAFAN8XAA==.',
Ne='Nefas:BAAANQAECgcIDgAAAA==.Nepthunus:BAABNQAECn8lAAIkAAkK0hY+AAAJAgAkAAkK0hY+AAAJAgAAAA==.',
Ni='Ninde:BAAANQADCggIDgAAAA==.',
No='Notforall:BAAANQADCgIIAgAAAA==.',
['Nï']='Nïix:BAAANQADCgYIBgAAAA==.',
['Nö']='Nöirr:BAAANQAECgEIAgAAAA==.',
Od='Odestruidor:BAAANQAECgYICgAAAA==.',
Oi='Oioimiguel:BAAANQAECgEIAQAAAA==.',
Ol='Oluss:BAABNQAECn8gAAMPAAoKaA8TWgALAgAPAAoKaA8TWgALAgADAAEKtwddqQEyAAABNQAECgoKOgAOAOAiAA==.',
On='Onys:BAAANQADCgIIAgAAAA==.',
Oo='Oob:BAAANQAECgcIDAAAAA==.',
Op='Opus:BAABNQAECn8bAAMPAAgKcBJwZADrAQAPAAgKcBJwZADrAQACAAUKSAWRTQCyAAAAAA==.Opusbergen:BAAANQADCgQIBAAAAA==.',
Or='Origon:BAAANQADCggICwAAAA==.Orillan:BAABNQAECn8nAAIHAAkKPhMwFABKAQAHAAkKPhMwFABKAQAAAA==.Ornsteinsnow:BAAANQAECgEIAQAAAA==.Orsonn:BAAANQAECgUIEwAAAA==.Orucão:BAAANQABCgEIAQAAAA==.Oruism:BAAANQAECgEIAQAAAA==.Orukam:BAAANQAECgcIEwAAAA==.Orukanorum:BAAANQAECgEIAQAAAA==.Orukrente:BAAANQAECgEIAQAAAA==.Orulord:BAAANQABCgIIAwAAAA==.Orurage:BAAANQABCgYIBAAAAA==.',
Pa='Palaha:BAAANQAECgQIBAABNQAECgoKOgAOAOAiAA==.Palatina:BAABNQAECn8gAAIDAAkKyx00OQDsAgADAAkKyx00OQDsAgABNQAECgkJMgADAAckAA==.Pandalokodj:BAAANQAECgEIAQAAAA==.Pangedrey:BAABNQAECn8pAAMSAAkKARguHQBNAgASAAkKARguHQBNAgAGAAEKRxWHSgA9AAAAAA==.Parký:BAAANQAECgcIDwAAAA==.Paullk:BAAANQAECgEIBQAAAA==.',
Pe='Penseur:BAAANQABCgYJBgAAAA==.Peruchi:BAAANQADCgIIAgAAAA==.Perísdra:BAAANQAECgEIAQABNQAECgMIDAANAAAAAA==.',
Pg='Pgms:BAAANQADCggIEgAAAA==.',
Pi='Picu:BAAANQADCgUICQAAAA==.Pitombinha:BAABNQAECn8gAAMMAAkKlx0iAwCeAQAMAAcK0h0iAwCeAQAFAAQKqRg+hwCQAAAAAA==.Pixiks:BAAANQABCgYIBwAAAA==.',
Pp='Ppandora:BAAANQADCgUICgAAAA==.',
Pr='Predadore:BAAANQADCgUIBQAAAA==.',
Pu='Pussytrix:BAAANQADCgIIAgAAAA==.',
Py='Pyrix:BAAANQADCgIIAgAAAA==.',
['Pä']='Pändero:BAAANQAECgEIAQAAAA==.',
['Pî']='Pîo:BAACNQAFFH8FAAIKAAQKRww4LAAtAQAKAAQKRww4LAAtAQA1AAQKfzIAAgoACgoOHQ0sADcDAAoACgoOHQ0sADcDAAAA.',
Qu='Quirow:BAABNQAECn8mAAIRAAkKiQ5SbQDYAQARAAkKiQ5SbQDYAQAAAA==.',
Ra='Radiação:BAAANQAECgMIAwAAAA==.Radunz:BAABNQAECn8vAAMTAAkKGRxRAQAsAgATAAkKGRxRAQAsAgAXAAMKlhURTgDTAAAAAA==.Ragnaros:BAAANQAECgQIBQAAAA==.Ragnarssön:BAAANQAECgIIAwAAAA==.Ragnarøk:BAAANQABCggICAAAAA==.Raio:BAABNQAECn80AAIKAAoKUhwBBgByAgAKAAoKUhwBBgByAgAAAA==.Ramorey:BAAANQAECgIIAwAAAA==.Ramsez:BAAANQAECgEIAQAAAA==.Ranruulfnarm:BAAANQAECgEIAQAAAA==.Rargsa:BAAANQAECgUIEQAAAA==.Rargul:BAAANQAECgIIAwAAAA==.Rariel:BAABNQAECn8VAAIHAAcK9BSKPQDNAQAHAAcK9BSKPQDNAQAAAA==.Raymain:BAABNQAECn8iAAQGAAkKMBnFGQDjAQAGAAcKUxjFGQDjAQASAAgKKxdyKQDSAQAWAAEKUgNhFwAkAAAAAA==.Raíka:BAAANQADCggIDQAAAA==.',
Re='Rebimboca:BAAANQAECgEIBAAAAA==.Redoon:BAAANQAECgIIAgAAAA==.Rendoras:BAAANQAECgEIAQAAAA==.Rezadeiro:BAAANQAECgEIAQAAAA==.',
Rh='Rhaumarhu:BAAANQADCgYIDAAAAA==.',
Ro='Rockit:BAAANQADCgMICAAAAA==.Rodbree:BAABNQAECn8nAAMPAAoKnx9rDQBeAwAPAAoKnx9rDQBeAwADAAIKAADEbwFuAAAAAA==.Roguinhu:BAAANQAECgUICQAAAA==.Roseangel:BAAANQABCgEIAQAAAA==.',
Ru='Rubian:BAAANQADCgYIDAAAAA==.Rudan:BAAANQAECgEIAgAAAA==.Rurumo:BAAANQAECgEJAgAAAA==.Rustovick:BAAANQAECgQIBgAAAA==.',
['Rä']='Rämzä:BAAANQAECgEIAQABNQAECgYICgANAAAAAA==.',
['Rå']='Råy:BAABNQAECn8qAAMgAAoK/hktJwCfAgAgAAoK/hktJwCfAgAJAAEKkg48qwA3AAAAAA==.',
Sa='Saalla:BAAANQABCgYIDwABNQAECgkJLwATABkcAA==.Saffír:BAABNQAECn8gAAIDAAkKTxFijgAIAgADAAkKTxFijgAIAgAAAA==.Sahkev:BAAANQAECgEIAQAAAA==.Samalandraa:BAAANQAECgUICwAAAA==.Sanateia:BAAANQAECgEIAgAAAA==.Saniest:BAABNQAECn8dAAMBAAkKfh/EEwDJAgABAAgKph/EEwDJAgAIAAQKLR4pvwDdAAAAAA==.Sapekinhä:BAABNQAECn8aAAIHAAkKVhWWGAAsAQAHAAkKVhWWGAAsAQAAAA==.Satanvitória:BAAANQAECgYIEQAAAA==.Saturio:BAAANQAECgEIAQAAAA==.',
Se='Segavaxx:BAAANQABCgQIBAAAAA==.Seilaa:BAAANQAECgEIAwAAAA==.Selorixie:BAAANQAECgYIDgABNQAECgYIIQAaAFMdAA==.Sereiaa:BAAANQAECgUIEAAAAA==.',
Sh='Shamate:BAAANQAECgUIAwAAAA==.Shanoa:BAAANQAECgQIBQAAAA==.Sharae:BAAANQADCggIDQAAAA==.Shedo:BAABNQAECn8YAAMFAAkKohkEeQAsAgAFAAgKohkEeQAsAgAMAAIKUhqzJwBvAAAAAA==.Shonja:BAAANQADCgYIDQAAAA==.Shula:BAAANQADCgYIBgAAAA==.',
Si='Sialeeds:BAAANQAECgEIAgAAAA==.Siclop:BAAANQAECgIIAgAAAA==.Simplicity:BAABNQAECn8aAAMIAAgKwBdCZADzAQAIAAgKwBdCZADzAQABAAMKbxJoVwCtAAAAAA==.Sinton:BAAANQABCgIIAgAAAA==.',
Sk='Skadrian:BAAANQAECgQIBAAAAA==.Skadryan:BAAANQAECgQICAAAAA==.Skalnark:BAAANQAECgYICwAAAA==.Skinme:BAAANQAECgEIAQAAAA==.Skysoul:BAAANQAECgEJAwAAAA==.',
Sl='Sleeppanda:BAAANQAECgEIAgABNQAECgoKRgAWADYbAA==.',
So='Sofiela:BAAANQAECgIIAgAAAA==.Soijiro:BAAANQADCgIIAgAAAA==.Soju:BAAANQADCgIIAgAAAA==.Sol:BAAANQADCgQIBAAAAA==.Sombrea:BAAANQAECgEIAgAAAA==.',
Sp='Spectrø:BAAANQADCgcIFAAAAA==.',
Ss='Sstrange:BAAANQADCggICQAAAA==.',
St='Starkz:BAAANQADCgUIBQAAAA==.Stëlla:BAABNQAECn8kAAIdAAkKkBvPDwDaAQAdAAkKkBvPDwDaAQAAAA==.',
Su='Suckmyhammer:BAAANQAECgcIDAAAAA==.Sungjinwoo:BAAANQAECgYIEgAAAA==.Sunnara:BAABNQAECn8gAAIlAAoKJRvxFQC0AgAlAAoKJRvxFQC0AgAAAA==.',
Sy='Syuon:BAABNQAECn87AAIGAAoK/iUQAABDBAAGAAoK/iUQAABDBAAAAA==.',
Sz='Szaa:BAAANQADCgQIBQAAAA==.',
Ta='Talandar:BAABNQAECn81AAIVAAoKnhUUKACVAgAVAAoKnhUUKACVAgAAAA==.Tankoso:BAAANQADCgIIAgAAAA==.Tankudo:BAABNQAECn8iAAIgAAgKVRcSPgAnAgAgAAgKVRcSPgAnAgAAAA==.',
Te='Tennebra:BAAANQADCggICQAAAA==.',
Th='Thabitah:BAABNQAECn8vAAIBAAkKthKfBwB7AQABAAkKthKfBwB7AQAAAA==.Thanathus:BAAANQAECgIIBwAAAA==.Thaumiel:BAAANQADCgEIAQAAAA==.Thedragon:BAABNQAECn8cAAIOAAgKGxwQJACIAQAOAAgKGxwQJACIAQAAAA==.Thorkel:BAAANQAECgEIAQAAAA==.Thotamon:BAAANQADCgYIDgAAAA==.Thýah:BAAANQAECgMIAwAAAA==.',
Ti='Tidim:BAAANQADCgYIBgAAAA==.Tiih:BAAANQABCgUIBwAAAA==.',
To='Tonypaludo:BAAANQAECgEIAwAAAA==.',
Tr='Trueperceval:BAAANQAECgEIAQAAAA==.',
Tu='Tushui:BAAANQAECgEIAQAAAA==.',
Us='Usfull:BAABNQAECn8iAAMIAAgKTRluWwAPAgAIAAgKTRluWwAPAgABAAIKsQOhagBYAAAAAA==.',
Va='Vaatu:BAAANQADCgMIBAAAAA==.Vallkÿria:BAAANQAECgYIBgAAAA==.Varrex:BAAANQADCgEIAQAAAA==.Vaëllen:BAABNQAECn8gAAMLAAgKpQjQEgDxAAALAAgKpQjQEgDxAAAVAAEKAAC7wAAhAAAAAA==.',
Ve='Vehuguito:BAAANQAECgEIAQABNQAECggIEwANAAAAAA==.Vehuiáh:BAAANQAECggIEwAAAA==.Velen:BAABNQAECn8sAAMgAAgK7R1RKQCTAgAgAAgK7R1RKQCTAgAJAAEKswhrZQA8AAAAAA==.Verno:BAAANQAECgIIAgAAAA==.Verzuk:BAAANQAECgQIBwAAAA==.',
Vi='Vintejulgar:BAAANQAECgEIAgAAAA==.Vintekilo:BAABNQAECn8cAAIDAAoKKgyunADpAQADAAoKKgyunADpAQAAAA==.Vinteservir:BAAANQAECgEIAQAAAA==.',
Vo='Voiddh:BAABNQAECn8eAAIlAAoKTBIxJQAdAgAlAAoKTBIxJQAdAgAAAA==.',
Vr='Vrenshrrgn:BAAANQAECgEIAwAAAA==.',
Vy='Vygh:BAABNQAECn8uAAMbAAoKvRolIgD7AgAbAAoKvRolIgD7AgAaAAEKuAs4eQA0AAAAAA==.Vyndrill:BAABNQAECn8fAAIZAAgKvhP4HQDjAQAZAAgKvhP4HQDjAQAAAA==.',
['Vø']='Vølkan:BAAANQAECgEIAgAAAA==.',
Wa='Walkers:BAABNQAECn8iAAIOAAoKxhGXVQBxAgAOAAoKxhGXVQBxAgAAAA==.Warlaka:BAAANQADCgYICwAAAA==.',
We='Weevil:BAAANQADCgYICgAAAA==.',
Wo='Worgenbelfin:BAAANQADCggIDQAAAA==.',
Wy='Wyrel:BAAANQAECgEIAQAAAA==.',
Xa='Xalmoria:BAAANQAECgYIDAAAAA==.',
Xe='Xendor:BAAANQAECgEIAQAAAA==.',
Xu='Xurumeloun:BAAANQAECgEIAQAAAA==.',
Ya='Yamii:BAAANQAECgQIBgAAAA==.Yasmini:BAAANQABCgEIAQAAAA==.',
Yi='Yingsu:BAABNQAECn8YAAMSAAoKohiCGACDAgASAAoKPxiCGACDAgAWAAYK6RAHHAAmAQAAAA==.Yippwarr:BAAANQADCgMIBAAAAA==.',
Yu='Yunná:BAAANQAECgEIAQAAAA==.',
Yv='Yvin:BAAANQAECgIIBQAAAA==.',
Za='Zakir:BAAANQAECgEIBQAAAA==.Zaolron:BAAANQADCgIIAQAAAA==.',
Ze='Zeddshm:BAAANQAECgEJAQABNQAECgoKLwAFAKgVAA==.Zeeno:BAAANQAECgEIAwAAAA==.',
Zh='Zhynah:BAAANQADCgUIBQAAAA==.',
Zi='Zibrautar:BAAANQADCgIIAgAAAA==.Ziracruz:BAAANQAECgQICAAAAA==.',
Zu='Zulyn:BAAANQADCgcIFwAAAA==.',
['Àr']='Àrdath:BAAANQADCggIDgAAAA==.Àrthemís:BAAANQADCgEIAQAAAA==.',
['Ár']='Áraujo:BAAANQADCgEJAQABNQADCgUIBQANAAAAAA==.Árÿä:BAABNQAECn8tAAIOAAkKYhAsEgDfAQAOAAkKYhAsEgDfAQAAAA==.',
['Áy']='Áy:BAAANQADCgIIAgAAAA==.',
['Är']='Äraxy:BAAANQAECgEIAQAAAA==.',
['Èv']='Èver:BAAANQADCgIIAgAAAA==.',
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
