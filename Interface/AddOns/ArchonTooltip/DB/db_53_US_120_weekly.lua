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

local lookup = {'Monk-Windwalker','Unknown-Unknown','DeathKnight-Frost','Paladin-Holy','Mage-Arcane','DeathKnight-Blood','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Warrior-Fury','DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Protection','Rogue-Assassination','Shaman-Enhancement','Paladin-Retribution','Druid-Restoration','Druid-Balance','Warrior-Arms','Druid-Feral','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Guardian',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abberleigh:BAAANQAECgIIAgAAAA==.Abron:BAAANQAECgIIAgAAAA==.',
Ad='Adahma:BAAANQADCgYIEQABNQAECgYIFwABACMGAA==.Adelerock:BAAANQAECgUIBwAAAA==.',
Ae='Aerostotle:BAAANQAECgcICwAAAA==.',
Ag='Aganoth:BAAANQAECgcJEwAAAA==.',
Ai='Aideon:BAAANQAECgEIAQABNQAECgUIDQACAAAAAA==.',
Al='Alaraa:BAAANQADCgUIBwABNQAECgkJIwADAHcSAA==.Algonq:BAAANQADCgYIJwABNQAECgYIFwAEAOMBAA==.Alkamaz:BAABNQAECn8WAAIFAAcKcQ3d9gCeAQAFAAcKcQ3d9gCeAQAAAA==.Alkiris:BAAANQADCgEIAQABNQAECgEIAgACAAAAAA==.Alsisst:BAAANQAECgEIAQAAAA==.Alssar:BAAANQAECgIIAgAAAA==.Alstar:BAABNQAECn8aAAIGAAoKQBPwGwATAQAGAAoKQBPwGwATAQAAAA==.Alynis:BAAANQADCgQIBAAAAA==.',
Am='Amac:BAAANQADCgUIBQAAAA==.Amathus:BAABNQAECn8+AAQHAAgKKRWgAgBRAQAHAAgKIBWgAgBRAQAIAAYKRhCMwQBIAQAJAAIKwwtiFQA7AAAAAA==.',
An='Andarial:BAAANQAECgUIBQAAAA==.Andreth:BAAANQAECgIIAwAAAA==.Anoxyn:BAAANQAECgQIBAAAAA==.Anthe:BAAANQADCgUIFAAAAA==.',
Ar='Arcanmaggy:BAAANQAECgEIAgABNQAECgoKJQAIAEwRAA==.Arcee:BAAANQADCgQIBgAAAA==.Ares:BAAANQAECgQIEgABNQADCgMJAwACAAAAAA==.Aryxi:BAAANQADCgUJBQABNQADCgMJAwACAAAAAA==.',
As='Asiägo:BAAANQABCgcJCgAAAA==.',
At='Atlas:BAAANQAECgQIBwAAAA==.',
Ba='Baelhal:BAABNQAECn8pAAIGAAgKKxEbTQDBAQAGAAgKKxEbTQDBAQAAAA==.',
Be='Bearypotter:BAAANQADCgUIBQAAAA==.Benedin:BAAANQADCgcJDAABNQAECgoKKAAKAM0eAA==.',
Bi='Bigtex:BAABNQAECn8XAAILAAYK9AdcGgD/AAALAAYK9AdcGgD/AAAAAA==.Biped:BAABNQAECn8iAAIHAAcKHxg8CAAOAgAHAAcKHxg8CAAOAgAAAA==.Bishul:BAAANQAECgQIBQAAAA==.',
Bl='Blackdeath:BAABNQAECn8WAAIMAAoKdA2KUADRAQAMAAoKdA2KUADRAQAAAA==.Bloodsport:BAAANQADCgIIAgAAAA==.',
Bo='Bofadees:BAAANQADCggIFAAAAA==.Boloevo:BAAANQADCgUIBQABNQAECgYIEgACAAAAAA==.Bolopal:BAAANQAECgIIAgABNQAECgYIEgACAAAAAA==.Boolin:BAAANQADCgQIBAABNQAECgoKKAAJAIQgAA==.Boomstique:BAABNQAECn8XAAINAAYKnRLVbwDMAAANAAYKnRLVbwDMAAAAAA==.Boondocka:BAABNQAECn8oAAINAAkKzhbYUAB9AgANAAkKzhbYUAB9AgAAAA==.',
Br='Brex:BAAANQAECggIAQAAAA==.Brissennissa:BAABNQAECn8sAAIOAAkK5hzjEgDUAgAOAAkK5hzjEgDUAgAAAA==.Brokkr:BAAANQADCggIEwAAAA==.Bronar:BAAANQADCgMIAwAAAA==.Brutalís:BAABNQAECn8bAAINAAcKcw7mnwDHAQANAAcKcw7mnwDHAQAAAA==.Brèwtality:BAAANQADCgUICwAAAA==.',
Bt='Btrain:BAAANQAECgQIDgAAAA==.',
Bu='Bubblebae:BAAANQADCggIFgABNQAECgcICwACAAAAAA==.',
['Bó']='Bóunty:BAABNQAECn8XAAINAAcKJiEcVgBwAgANAAcKJiEcVgBwAgAAAA==.',
Ca='Calypsto:BAAANQAECgIIAgAAAA==.',
Ce='Cenobité:BAABNQAECn8cAAIDAAkKIQ1fLQDmAAADAAkKIQ1fLQDmAAAAAA==.',
Ch='Chialing:BAAANQAECgUICwAAAA==.Chichi:BAAANQAECggICwAAAA==.Chickenhead:BAAANQAECgEIAwAAAA==.Chip:BAAANQADCgYIGwAAAA==.Chuckfinley:BAAANQAECgIIAwAAAA==.Chuong:BAAANQADCgIIAgABNQAECgQIBgACAAAAAA==.',
Ci='Cirax:BAABNQAECn8VAAINAAYKvROotQCZAQANAAYKvROotQCZAQAAAA==.',
Cl='Classic:BAAANQADCgYIDQABNQAECgYIFwAPAIcXAA==.Cleetess:BAAANQADCgUIDQAAAA==.Clenton:BAABNQAECn8uAAIPAAkKPg0kDQAxAQAPAAkKPg0kDQAxAQAAAA==.',
Co='Cobrakai:BAAANQADCgEIAQAAAA==.Cosplay:BAAANQAECgcIEgABNQAFFAIICAAQAJQFAA==.',
Cr='Crichton:BAABNQAECn83AAIOAAoKtyG8BwBWAwAOAAoKtyG8BwBWAwAAAA==.Crowford:BAAANQAECgcIEQAAAA==.',
Cy='Cyris:BAAANQADCgUICwABNQAECgYIFQARABoDAA==.',
['Cá']='Cástle:BAAANQAECgQIBwAAAA==.',
Da='Daevahna:BAAANQADCggIEQAAAA==.Dak:BAABNQAECn8lAAMPAAkKgBpSEgB9AgAPAAkKgBpSEgB9AgASAAIKAgsB9AA5AAABNQAECgoKFgARAEMTAA==.Dakstorm:BAABNQAECn8WAAIRAAoKQxP3DQCNAgARAAoKQxP3DQCNAgAAAA==.Darkmiza:BAABNQAECn8lAAIIAAoKTBEzcQAMAgAIAAoKTBEzcQAMAgAAAA==.Dawnstrike:BAAANQADCggICAAAAA==.',
De='Deadmangalad:BAAANQADCgYIGwAAAA==.Deedees:BAAANQAECgQICwAAAA==.Demonhandler:BAAANQADCgUICQAAAA==.Demonikk:BAAANQAECgQICAAAAA==.Deo:BAAANQAECgYIDgABNQAFFAIICAAQAJQFAA==.Depression:BAAANQAECggIBwAAAA==.',
Di='Diioo:BAAANQAECgMIBQAAAA==.Dirtnåp:BAAANQADCgYIGgAAAA==.Diskbänk:BAAANQADCgUIBQAAAA==.',
Dr='Dragonthorns:BAAANQAECgEIBAAAAA==.Dragontoast:BAAANQAECgIIAgAAAA==.Dral:BAEANQAECgEIAQAAAA==.Drama:BAAANQAECgUIBQAAAA==.Druidïan:BAABNQAECn8VAAMTAAcKeBAfFgASAQATAAcKeBAfFgASAQAUAAIKHgJKVQAuAAAAAA==.',
Dy='Dynwor:BAAANQADCggICwAAAA==.',
Ea='Easme:BAAANQAECgcIEAAAAA==.',
El='Elaric:BAAANQAECgUIBQAAAA==.',
En='Engi:BAABNQAECn8gAAMVAAgKoBDGkQDwAQAVAAgKoBDGkQDwAQALAAEKjQUnGAAwAAAAAA==.Enhuna:BAAANQADCgIIAgAAAA==.',
Es='Escaper:BAABNQAECn8nAAIDAAgKwxTDMwAPAgADAAgKwxTDMwAPAgAAAA==.',
Ev='Eversteel:BAAANQADCgUIBQABNQAECgYIFwAPAIcXAA==.',
Ex='Extrema:BAAANQAECgIIAgAAAA==.',
Fe='Felesha:BAAANQADCgQIBAAAAA==.',
Fh='Fhait:BAAANQADCgcIIwABNQAECgYIFwABACMGAA==.',
Fi='Fionab:BAAANQADCgIIAgAAAA==.',
Fo='Foxfu:BAAANQADCgYICwAAAA==.',
Fu='Fujika:BAAANQADCgQIBAAAAA==.',
Ga='Galadan:BAABNQAECn8XAAIWAAYKGgWgJgDYAAAWAAYKGgWgJgDYAAABNQADCgYIGwACAAAAAA==.Garrekton:BAABNQAECn8oAAMKAAoKzR5WBADaAgAKAAoKzR5WBADaAgAXAAEKAACghQAjAAAAAA==.Gaskelmarg:BAAANQADCgUIFwAAAA==.',
Ge='Gellane:BAAANQAECgMIAwAAAA==.',
Gh='Ghozt:BAAANQADCgUICgABNQAECgQIBwACAAAAAA==.',
Gl='Glory:BAABNQAECn8mAAMEAAkKfRhrLgCtAgAEAAkKfRhrLgCtAgASAAEKYwqU7QA+AAAAAA==.',
Go='Goldtusk:BAAANQAECgUIDQAAAA==.',
Gr='Graveyard:BAAANQADCgcICwABNQAECgQIBwACAAAAAA==.Grundler:BAAANQAECgEIAgAAAA==.Gryphone:BAAANQADCggIEAAAAA==.',
Ha='Hakmud:BAAANQADCgYIGgAAAA==.Harandee:BAAANQADCgYICwAAAA==.Hasmus:BAAANQADCgUIBQAAAA==.Haufa:BAAANQAECgIIBAAAAA==.',
He='Headstrong:BAAANQADCgcIBwAAAA==.Hettokal:BAAANQADCgQIBAAAAA==.Heximal:BAAANQADCgQIBwABNQAECgkJKAANAM4WAA==.',
Ho='Hondojoe:BAEBNQAECn8dAAMKAAkKGBKlbQDVAQAKAAkKGBKlbQDVAQAXAAQKpg2mTgDZAAAAAA==.Honeydrake:BAAANQAECggIEgAAAA==.Hopewell:BAABNQAECn8XAAIEAAYK4wHQbQBxAAAEAAYK4wHQbQBxAAAAAA==.',
Hu='Hugnsnuggle:BAABNQAECn8XAAIYAAYKeQm/GwD+AAAYAAYKeQm/GwD+AAABNQAECgYIFwABACMGAA==.Huhu:BAAANQAECggIDQAAAA==.Humilitas:BAAANQADCgUICQAAAA==.',
Ib='Ibn:BAABNQAECn8eAAIVAAcKfAb4agDEAAAVAAcKfAb4agDEAAAAAA==.',
Il='Illadus:BAAANQADCgYICwAAAA==.Illidab:BAABNQAECn8lAAIZAAoKtxyBFAD5AgAZAAoKtxyBFAD5AgAAAA==.',
In='Infectus:BAABNQAECn8YAAMMAAkKgQM9rACcAAAMAAgKTQM9rACcAAADAAkKvgHUlABsAAAAAA==.',
Ir='Irielle:BAAANQADCgYIIQAAAA==.',
Iv='Ivylyn:BAAANQAECgUICgAAAA==.',
Ix='Ixiyá:BAABNQAECn8dAAIaAAoKFiMqBQCeAwAaAAoKFiMqBQCeAwAAAA==.Ixií:BAAANQADCgYIBgAAAA==.Ixì:BAAANQADCgEIAQAAAA==.',
Ja='Jakbenimble:BAAANQADCgcIDQAAAA==.Jakeyprogue:BAAANQAECgMIBAAAAA==.Jakota:BAAANQADCgYIEQAAAA==.Jakskeleton:BAAANQAECgUIEgAAAA==.',
Je='Jeamica:BAAANQADCggICwAAAA==.Jethroy:BAAANQADCgQIBAAAAA==.',
Jo='Joerollin:BAEANQADCggICQABNQAECgkJHQAKABgSAA==.Johnjrambo:BAAANQADCgcIBwAAAA==.',
Ju='Judax:BAABNQAECn8xAAIbAAoK+hP0TwA4AgAbAAoK+hP0TwA4AgAAAA==.Justagirl:BAABNQAECn8XAAIBAAYKIwYuRQDxAAABAAYKIwYuRQDxAAAAAA==.Juti:BAAANQADCgYIEQAAAA==.Juvu:BAAANQADCgQIBAAAAA==.',
Ka='Kadooka:BAABNQAECn8YAAINAAcKERfMjQDuAQANAAcKERfMjQDuAQAAAA==.Kahlyn:BAAANQADCgQIBAAAAA==.Kai:BAAANQAECgYIEAAAAA==.Kaldaran:BAAANQADCgcIBwABNQAECgkJFgAVAL4aAA==.Kallan:BAAANQADCgQJBAABNQAECgYIFwAPAIcXAA==.Kaléanor:BAABNQAECn8WAAIVAAkKvhqnFQCzAQAVAAkKvhqnFQCzAQAAAA==.Karen:BAAANQADCgUIBwAAAA==.Katabell:BAABNQAECn8XAAMXAAYKrATLUwC/AAAXAAYKrATLUwC/AAAKAAIKXwLa9wA+AAAAAA==.Katira:BAAANQADCgUIDgAAAA==.',
Ke='Keeganw:BAAANQAECgUIDAAAAA==.Keelay:BAAANQAECgcIEgAAAA==.Kelste:BAAANQAECggIEQAAAA==.',
Ki='Killaclowns:BAAANQADCgUIEwAAAA==.Kimiko:BAAANQADCgUICQAAAA==.Kioki:BAAANQADCgYICAAAAA==.',
Kl='Klitess:BAAANQADCgIIAgAAAA==.',
Ko='Koffcmorbius:BAAANQADCgYIFAAAAA==.Kostian:BAAANQADCgUICQABNQAECgYIFwAPAIcXAA==.',
Kr='Kraken:BAABNQAECn8oAAIJAAoKhCClAQBpAwAJAAoKhCClAQBpAwAAAA==.',
Ku='Kubb:BAABNQAECn8VAAIRAAYKGgOwJAARAQARAAYKGgOwJAARAQAAAA==.',
Kw='Kweh:BAACNQAFFH8JAAIWAAMKOBTRAADTAAAWAAMKOBTRAADTAAA1AAQKfyoAAhYACgpRHx0GABADABYACgpRHx0GABADAAAA.',
['Kê']='Kêlsen:BAAANQAECgIIAwAAAA==.',
La='Laero:BAAANQADCgYICwABNQAECgYIFQARABoDAA==.Larrissa:BAAANQADCgYIFAAAAA==.Laurlynn:BAAANQADCgYICwAAAA==.',
Le='Lenwe:BAAANQAECgQIBgAAAA==.Lettuceprey:BAAANQAECgMIBAAAAA==.',
Li='Lierise:BAAANQAECgEIAQAAAA==.Lilindra:BAABNQAECn8jAAQDAAkKdxLKXQAwAQADAAcKlxHKXQAwAQAMAAYK0xOTgQAYAQAGAAEKAAAa0gArAAAAAA==.Lillymay:BAAANQAECgEIAQAAAA==.Lilspazz:BAAANQAECgEIAQAAAA==.',
Ll='Lluiz:BAAANQADCgYICgAAAA==.',
Lo='Lockdeath:BAAANQADCgcIDAAAAA==.Logoruk:BAAANQADCgQIBAAAAA==.Lorelleya:BAAANQADCgEIAQAAAA==.Loxia:BAAANQAECgUICwAAAA==.',
Lu='Lucille:BAAANQADCgYIBgAAAA==.Luckett:BAAANQAECgEIAQAAAA==.Lui:BAAANQAECgIIAwAAAA==.Lumi:BAAANQAECgUIDgAAAA==.',
Ma='Maavarra:BAAANQAECgUICwAAAA==.Madischa:BAAANQAECgEIAgAAAA==.Madshaggy:BAABNQAECn8mAAIPAAcKQR3NCgBOAQAPAAcKQR3NCgBOAQAAAA==.Magicdance:BAAANQAECgUIBgAAAA==.Magikern:BAAANQADCgMIAwABNQADCgUIBQACAAAAAA==.Magy:BAAANQADCgIIAgAAAA==.Mahallomi:BAAANQADCgQIBAABNQAECgUIDgACAAAAAA==.Maldreth:BAAANQADCgYIBgAAAA==.Maxlin:BAAANQAECgcIEAAAAA==.',
Me='Mehänemäntä:BAAANQADCggIEgAAAA==.Melarii:BAAANQADCgYIEQAAAA==.Merixa:BAAANQAECgUIDQAAAA==.',
Mi='Midou:BAAANQAECgIIAQABNQAECgUIBgACAAAAAA==.Misstreater:BAAANQAECgUICgAAAA==.',
Mo='Momentomori:BAABNQAECn8XAAIIAAkKIAf8zQAuAQAIAAkKIAf8zQAuAQAAAA==.Monbeau:BAABNQAECn8hAAIFAAoKeRbQZAC0AgAFAAoKeRbQZAC0AgAAAA==.Monocerotis:BAABNQAECn8hAAIDAAkKrg/aOADxAQADAAkKrg/aOADxAQAAAA==.Moosebear:BAAANQADCgYIBgAAAA==.Morishima:BAABNQAECn87AAMQAAoKxB1mEwDhAgAQAAkKpBtmEwDhAgAcAAkKKhvTFAAzAQAAAA==.',
Mu='Multipàss:BAAANQADCgQIBQAAAA==.',
My='Mydarling:BAACNQAFFH8IAAMEAAUK/BNhFwDtAAAEAAMK6AxhFwDtAAASAAMK0wMSIQCdAAA1AAQKfyoAAxIACgo8GvR4ADoCABIACQr6GPR4ADoCAAQABgrxDy20ABYBAAAA.Mymoon:BAAANQAECgUIDQAAAA==.Myris:BAABNQAECn8fAAIMAAgKFByjLQB8AgAMAAgKFByjLQB8AgAAAA==.',
['Mî']='Mîsgüïdëð:BAAANQAECgEIAQAAAA==.',
Na='Naturalchi:BAABNQAECn8gAAIBAAcK1SGhFQClAgABAAcK1SGhFQClAgAAAA==.',
Nb='Nbi:BAAANQAECgEIAgAAAA==.',
Ne='Nefilion:BAAANQAECgEIAwAAAA==.Nefy:BAAANQAECgYIBQAAAA==.Nezin:BAAANQADCgMJAwAAAA==.',
Ni='Niselo:BAAANQADCgUIBQAAAA==.',
No='Nohzul:BAACNQAFFH8PAAIbAAUKNx2jCwCwAQAbAAUKNx2jCwCwAQA1AAQKfx4AAhsACgoHIncVAEgDABsACgoHIncVAEgDAAAA.Nomik:BAAANQAECgIIAgABNQAECgQIBgACAAAAAA==.Nonah:BAAANQADCgYIBwAAAA==.',
Nu='Nullspace:BAABNQAECn8ZAAIKAAkK3ReyQABoAgAKAAkK3ReyQABoAgAAAA==.',
['Ní']='Níght:BAAANQAECgEIAQAAAA==.',
Om='Omfega:BAAANQAECgEIAQAAAA==.',
Or='Orgresh:BAAANQADCggICAAAAA==.Orym:BAAANQAECgUIDQAAAA==.',
Pa='Palacia:BAABNQAECn8bAAMPAAcKoRCAMQBUAQAPAAYK9xOAMQBUAQASAAYKdAPzxABsAAAAAA==.Pallythetank:BAAANQAECgUIDgAAAA==.Pappabeary:BAAANQAECgEIAQAAAA==.',
Pe='Peerow:BAAANQADCgUIGwAAAA==.Petrichorica:BAAANQADCgcICgAAAA==.',
Pi='Pintobeans:BAABNQAECn8UAAINAAgK9APk6AAvAQANAAgK9APk6AAvAQAAAA==.',
Pr='Preachêr:BAAANQABCgQIBAABNQAECgYIFwAPAIcXAA==.Preistytute:BAAANQAECgEIBAAAAA==.Primeatheist:BAAANQAECggIDwAAAA==.',
Pu='Puuhceew:BAABNQAECn8UAAIKAAcKtgXanwA1AQAKAAcKtgXanwA1AQAAAA==.',
Ra='Rainbrews:BAAANQAECgEIAwAAAA==.Rainera:BAABNQAECn8iAAIHAAgK5R+CAwC9AgAHAAgK5R+CAwC9AgABNQAFFAQICwAYAOMhAA==.Ramanas:BAAANQAECgQIBAAAAA==.Ramrod:BAAANQAECgUJCQAAAA==.Ramstank:BAAANQAECgMIBQAAAA==.Rattles:BAAANQAECgIIAwAAAA==.',
Re='Redgicide:BAAANQAECgYIDwABNQAECgkJKAANAM4WAA==.Releafme:BAACNQAFFH8SAAITAAYKIR4zAQDnAQATAAYKIR4zAQDnAQA1AAQKfzAAAhMACgqOJaQBALsDABMACgqOJaQBALsDAAAA.Resurgencê:BAABNQAECn8XAAIPAAYKhxfuJAC5AQAPAAYKhxfuJAC5AQAAAA==.',
Ri='Riordan:BAABNQAECn8VAAISAAYKJwxi5gBOAQASAAYKJwxi5gBOAQAAAA==.',
Ro='Rojeton:BAAANQADCgIIAgAAAA==.Rothema:BAABNQAECn8UAAIbAAYK9gN50gDvAAAbAAYK9gN50gDvAAAAAA==.Routh:BAAANQAECgEIAgAAAA==.',
Ru='Rubee:BAAANQADCgMIAwAAAA==.',
Rw='Rwlmaster:BAABNQAECn8gAAIGAAgKNRLPRADoAQAGAAgKNRLPRADoAQAAAA==.',
Sa='Sandwiches:BAAANQAECgEIAgAAAA==.',
Sc='Scerra:BAABNQAECn8mAAMDAAgK+Rj4CgCxAQADAAgK+Rj4CgCxAQAMAAMKogJewQBoAAAAAA==.Scridders:BAAANQAECgcIEAAAAA==.Scridderz:BAAANQAECgEIAQAAAA==.Scriddle:BAAANQAECgUIBAAAAA==.',
Se='Secre:BAAANQADCgQJBAAAAA==.Sellandre:BAAANQADCgYIBgABNQAECgcIEgACAAAAAA==.Seru:BAAANQAECgIIAgAAAA==.',
Sh='Shamarha:BAABNQAECn8bAAIaAAcKciA3DAAFAgAaAAcKciA3DAAFAgAAAA==.Shamonbo:BAAANQADCgUIBQABNQAECgoKIQAFAHkWAA==.Sharriavolf:BAABNQAECn8cAAMIAAcKPR3dmgCjAQAIAAUK+RzdmgCjAQAJAAIKox1lSQCjAAAAAA==.Shion:BAAANQAECgQIBAABNQAFFAYIIAAOALcgAA==.Shreder:BAAANQADCgIIAgAAAA==.Shuma:BAAANQADCgUIBgAAAA==.',
Si='Simichaelton:BAECNQAFFH8GAAMdAAIKTBHOEgBJAAAFAAEKbRIhWABQAAAdAAEKKxDOEgBJAAA1AAQKfzYAAx0ACgqxGhAbABoBAAUACQqhFwGxACECAB0ABAp+HBAbABoBAAAA.Sinahi:BAAANQAECgEIAQAAAA==.Sinpal:BAAANQAECgcIDgAAAA==.Sinthea:BAAANQAECggIBAAAAA==.',
Sn='Sneakysoul:BAACNQAFFH8IAAIQAAIKlAVqFACmAAAQAAIKlAVqFACmAAA1AAQKfx0AAhAACgp2GjAYALsCABAACgp2GjAYALsCAAAA.',
So='Solyn:BAABNQAECn8YAAISAAcKQwal8QA5AQASAAcKQwal8QA5AQAAAA==.Sonic:BAAANQADCgUIBQAAAA==.',
Sp='Spagooti:BAAANQAECgYIEAAAAA==.Spanxya:BAAANQADCgQIBAAAAA==.Spartaaxd:BAABNQAECn8YAAIDAAgKnw0NRgCoAQADAAgKnw0NRgCoAQAAAA==.',
St='Stabbard:BAAANQADCgQIBAAAAA==.Stagerrind:BAAANQADCgMIAwAAAA==.Steiner:BAAANQADCgUIBwAAAA==.Stejamarha:BAAANQADCgQIBAAAAA==.',
Su='Sugarseer:BAABNQAECn8ZAAIaAAoKcxN2UwAZAgAaAAoKcxN2UwAZAgAAAA==.Suka:BAAANQADCgYIJAAAAA==.Suzi:BAABNQAECn8VAAINAAcKMwbufACzAAANAAcKMwbufACzAAAAAA==.',
Sw='Swiftleaf:BAAANQADCggICAAAAA==.',
Sy='Syevoid:BAAANQADCgIIAwAAAA==.Sylentcurse:BAAANQAECgUICgABNQAECgcIGwANAHMOAA==.Sylentstorm:BAAANQAECgEIAgABNQAECgcIGwANAHMOAA==.Sylentwolvez:BAAANQAECgUIBwAAAA==.Syleta:BAAANQADCgEIAQABNQAECgkJIwADAHcSAA==.Sylvarus:BAAANQADCgQIBAAAAA==.',
Ta='Tabraxis:BAAANQAECgEIAwAAAA==.Tagalorc:BAABNQAECn8eAAIFAAcKcwvTbADiAAAFAAcKcwvTbADiAAAAAA==.Takamaki:BAAANQADCgUIFwAAAA==.Talionwrite:BAAANQADCgMIAwAAAA==.Tanksbacon:BAAANQAECgUIBgAAAA==.',
Te='Teana:BAAANQAECgcIEwAAAA==.Tempestas:BAAANQADCgUIBgAAAA==.',
Th='Thechadd:BAAANQAECggIBgAAAA==.Thelegendáry:BAABNQAECn8nAAMaAAgKQhydNwCBAgAaAAgKQhydNwCBAgAbAAEKRhKCjAA8AAAAAA==.Themigrant:BAAANQAECgEIAgAAAA==.Thomm:BAAANQAECgEIAQAAAA==.Thorgrimm:BAAANQADCgYIBgAAAA==.Thraine:BAAANQAECgYIDgAAAA==.Threedog:BAAANQADCgIIAgAAAA==.',
Ti='Tinder:BAAANQAECgEIAQAAAA==.Tione:BAABNQAECn8ZAAMTAAYKdx5KDQBoAQATAAYKdx5KDQBoAQAUAAEKAABOwAAhAAAAAA==.',
To='Toadvoker:BAABNQAECn8hAAMeAAoK+hb/EwBuAgAeAAoK+hb/EwBuAgAfAAEKxwB0KQARAAAAAA==.Topao:BAAANQADCgYIBgABNQAECgEIAgACAAAAAA==.Toriee:BAAANQAECgEIAgAAAA==.Totembish:BAABNQAECn8ZAAIbAAcKdgbTMAD8AAAbAAcKdgbTMAD8AAAAAA==.',
Tr='Trisstan:BAABNQAECn8XAAIdAAYK4wa2IADjAAAdAAYK4wa2IADjAAAAAA==.Trollthrall:BAAANQAECgIIAgAAAA==.',
Ty='Tyster:BAABNQAECn8iAAISAAoKxxxiXwB7AgASAAoKxxxiXwB7AgAAAA==.',
['Tï']='Tïghtgrïp:BAABNQAECn8eAAQDAAoKChcVJQBqAgADAAoKyRYVJQBqAgAGAAYKGxVYXgB4AQAMAAIK2gjTzgBPAAAAAA==.',
['Tø']='Tørmented:BAAANQADCgUIBQAAAA==.',
Un='Undol:BAAANQADCgcIFAABNQAECgYIFQARABoDAA==.',
Va='Vaellborn:BAAANQADCgEIAQAAAA==.Vandress:BAAANQADCgMIAQABNQAECgEIAgACAAAAAA==.',
Ve='Velobeef:BAAANQADCgEIAQAAAA==.Veloth:BAACNQAFFH8YAAMdAAYKIBYxAABVAQAdAAYKIBYxAABVAQAFAAMKbA0IOgDdAAA1AAQKfzoAAx0ACgqWIp4BAHQDAB0ACgq7IZ4BAHQDAAUACQqYHrtIAPECAAAA.Verminus:BAABNQAECn8aAAQTAAkKygsgNgBrAQATAAgKlgsgNgBrAQAUAAYKCgapcwD8AAAWAAEK6gZqSAApAAAAAA==.',
Vi='Viggle:BAAANQADCgUICAABNQAECgYIFwAPAIcXAA==.Viho:BAABNQAECn8iAAISAAgKvhNjmgDuAQASAAgKvhNjmgDuAQAAAA==.Vilekin:BAAANQAECgUIBwAAAA==.Vithaxa:BAAANQAECgMIBgAAAA==.',
Vo='Voidra:BAAANQAECgEIAQAAAA==.',
Vy='Vyinson:BAAANQAECgQIBAABNQAECgUIDQACAAAAAA==.',
Wa='Warloque:BAAANQADCgMIAwAAAA==.',
We='Weechuup:BAAANQAECgQIBgAAAA==.',
Wi='Wifeotusk:BAAANQAECgQIBAAAAA==.Wiggle:BAAANQADCgYICwAAAA==.Willmar:BAAANQAECgYIEQAAAA==.Window:BAAANQAECgEIAgABNQAECgQIBwACAAAAAA==.Windrun:BAAANQAECgQICwAAAA==.',
Wo='Wolf:BAABNQAECn8gAAIgAAoKhRFOBgCgAQAgAAoKhRFOBgCgAQAAAA==.Woodtique:BAAANQADCgYIFgAAAA==.',
Wu='Wulthan:BAAANQADCgYICwAAAA==.',
Xa='Xandercruise:BAAANQAECgEIAwAAAA==.',
Xe='Xelphie:BAAANQADCggICQAAAA==.',
Xu='Xuchilbara:BAABNQAECn8WAAIWAAYKXx3FEAD7AQAWAAYKXx3FEAD7AQAAAA==.',
Ya='Yamato:BAAANQAECgYIDgAAAA==.',
Za='Zaledron:BAAANQAECgcIDgAAAA==.',
Zb='Zbelladonna:BAAANQAECgEIAgABNQAECgoKRgADADohAA==.',
Ze='Zezera:BAAANQAECgIIAgAAAA==.',
Zh='Zhades:BAABNQAECn9GAAMDAAoKOiGMAQDOAgADAAoKOiGMAQDOAgAMAAkKOBEuWwCjAQAAAA==.Zhort:BAAANQAECgIIAgAAAA==.',
Zi='Zioki:BAAANQADCggICQAAAA==.',
Zo='Zodgul:BAAANQADCggICAAAAA==.Zomby:BAEANQAECggICwABNQAFFAIIBgAdAEwRAA==.',
Zu='Zultan:BAABNQAECn8sAAIIAAkKtwrYiwDJAQAIAAkKtwrYiwDJAQAAAA==.',
Zy='Zynblasted:BAAANQADCgQIBAAAAA==.Zynhunter:BAAANQADCgUIFAAAAA==.Zyuxis:BAAANQAECgEIAQABNQAECgYICAACAAAAAA==.',
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
