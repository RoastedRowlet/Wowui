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

local lookup = {'Warlock-Affliction','Evoker-Augmentation','Shaman-Elemental','Unknown-Unknown','Paladin-Protection','Warlock-Demonology','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Priest-Holy','Evoker-Preservation','DeathKnight-Unholy','DeathKnight-Frost','Druid-Guardian','Druid-Balance','Evoker-Devastation','Priest-Shadow','Hunter-BeastMastery','Monk-Windwalker','Mage-Frost','DemonHunter-Havoc','Warrior-Fury','Warlock-Destruction','Druid-Restoration','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Devourer','Mage-Arcane','Priest-Discipline','Hunter-Survival','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Addykikora:BAAANQADCgYIEQABNQAECggIHgABADUXAA==.',
Ae='Aeonmoksha:BAAANQAECgIIAgAAAA==.',
Ai='Ailuridae:BAAANQAECgEIAQAAAA==.Airo:BAAANQADCgIIAgAAAA==.',
Ak='Akaris:BAABNQAECn8cAAICAAgK5AX6EwDvAAACAAgK5AX6EwDvAAAAAA==.',
Al='Alainea:BAABNQAECn8VAAIDAAgKRAQVkgDPAAADAAgKRAQVkgDPAAAAAA==.Alorgynn:BAAANQABCgIIAwABNQAECgUIBgAEAAAAAA==.Alôra:BAAANQADCgcIBwABNQAECgUIBgAEAAAAAA==.',
Am='Amaterasu:BAACNQAFFH8sAAIFAAkKVB9GAACPAgAFAAkKVB9GAACPAgA1AAQKfywAAgUACgqOJgwDAJUDAAUACgqOJgwDAJUDAAE1AAUUCQosAAUAVB8A.Ambre:BAAANQAECgcICwAAAA==.',
An='Andross:BAAANQADCggICAABNQAECgcIHgAGAAUPAA==.Angwy:BAAANQAECgUIBgAAAA==.',
Ar='Ara:BAAANQAECgQICAAAAA==.Archhùnter:BAAANQABCgQIBAAAAA==.Ariannae:BAAANQAECgYIBgAAAA==.',
As='Ashamed:BAABNQAFFH8GAAIHAAIKYwiiJABCAAAHAAIKYwiiJABCAAABNQAFFAkKLAAFAFQfAA==.',
At='Atropa:BAAANQADCgYIBgAAAA==.',
Au='Aura:BAABNQAECn9MAAMIAAoK+x4HFwDvAgAIAAoK+x4HFwDvAgAJAAIKpxDrZAF+AAAAAA==.',
Ax='Axl:BAAANQAECgIIAwAAAA==.',
Ay='Aylíth:BAAANQAECgQIBwABNQAFFAkKLAAFAFQfAA==.',
Ba='Bah:BAAANQADCggIOwAAAA==.Banjoo:BAAANQAECgIIAgAAAA==.Baruk:BAABNQAECn9BAAMKAAoKgxavPQAIAgAKAAoKgxavPQAIAgADAAYKXwSuqgCeAAAAAA==.',
Be='Benny:BAAANQAECgUIBwABNQAECgoKLwALAOghAA==.Bergelmir:BAAANQAECgIIAwAAAA==.',
Bi='Bigçhungi:BAAANQAECggIEQABNQAFFAYIGgAHAKskAA==.',
Bl='Blitzen:BAABNQAECn84AAIMAAoKxBzYCwDnAgAMAAoKxBzYCwDnAgAAAA==.',
Bo='Boozamabeard:BAAANQAECggIDQAAAA==.Borealiss:BAAANQAECgUIEwABNQAECgoKOAAMAMQcAA==.Boxofmilk:BAAANQAECgIIAgAAAA==.',
Br='Break:BAEANQAECgYICQABNQAFFAgKIQAJALgiAA==.',
Bw='Bwonsamdi:BAAANQADCgcICgAAAA==.',
['Bâ']='Bârks:BAABNQAECn8hAAILAAkKnhl8MABsAgALAAkKnhl8MABsAgAAAA==.',
Ca='Caarij:BAABNQAECn9KAAMNAAoK5xZYMQBoAgANAAkK6BdYMQBoAgAOAAQKkQs7fwCcAAAAAA==.Cadence:BAAANQAECgMIBQAAAA==.Callia:BAAANQADCgIIAgAAAA==.',
Ce='Celorana:BAAANQADCgYIBgAAAA==.Cerra:BAAANQAECgEIAQAAAA==.',
Ch='Chijirô:BAAANQAECgEIAQAAAA==.Choleena:BAABNQAECn8fAAIKAAgK/BFRbgBRAQAKAAgK/BFRbgBRAQAAAA==.',
Co='Coojotwo:BAAANQADCgUIBQAAAA==.Coppola:BAAANQABCgcIBQAAAA==.',
['Cí']='Círce:BAAANQAECggICAABNQAFFAkKLAAFAFQfAA==.',
Da='Dangerwithin:BAAANQAECgQIBgABNQAFFAkKLAAFAFQfAA==.Danklazercat:BAABNQAECn8XAAMPAAoKQxusCgCBAgAPAAoKQxusCgCBAgAQAAMKkgRSsAA2AAABNQAFFAYIGgAHAKskAA==.Darius:BAAANQAFFAEIAQAAAA==.Dastinele:BAAANQADCgUIBQAAAA==.Dastraz:BAABNQAECn8WAAMMAAcKuQlYNQDpAAAMAAcKuQlYNQDpAAARAAQKgAZ/MACUAAAAAA==.',
De='Deaconblues:BAAANQABCgMIBQABNQAECggIDQAEAAAAAA==.Devkra:BAABNQAECn8eAAIHAAgKiRKNVwCVAQAHAAgKiRKNVwCVAQAAAA==.',
Dh='Dharma:BAABNQAECn8pAAMSAAoKAhVAIABvAQASAAoKAhVAIABvAQALAAIKXQTb1wBcAAAAAA==.',
Do='Doge:BAABNQAECn8iAAITAAkK1AZmqQCyAQATAAkK1AZmqQCyAQAAAA==.',
Dr='Drakona:BAAANQADCgUIBQAAAA==.Drapenthim:BAAANQADCgQIAwAAAA==.',
Du='Dudemachine:BAAANQADCgMIAwABNQAECgoKIwAUAMcfAA==.',
['Dø']='Døødemage:BAAANQAECgIIAQAAAA==.',
Ed='Eddison:BAAANQAECgIIAgAAAA==.',
El='Elementhor:BAAANQAECgUIBAAAAA==.Eloralove:BAAANQADCggICAAAAA==.Eltrys:BAAANQADCgYIBgAAAA==.',
En='Enchanted:BAABNQAECn8gAAINAAkKlB94OgA5AgANAAkKlB94OgA5AgAAAA==.Ender:BAABNQAECn8mAAIVAAgKEAnVFQBRAQAVAAgKEAnVFQBRAQAAAA==.',
Es='Eskanor:BAAANQADCgQIBAAAAA==.',
Et='Eternalwrath:BAABNQAECn8fAAMNAAgK3xB0MQBPAQANAAgK3xB0MQBPAQAHAAEKSwXJoQAtAAAAAA==.',
Fe='Felmary:BAABNQAECn8XAAIWAAYKGwbMXQAKAQAWAAYKGwbMXQAKAQAAAA==.',
Fi='Firnen:BAAANQADCgMIAwAAAA==.',
Fo='Foxxylady:BAAANQAECgcIEAAAAA==.',
Fr='Freyja:BAABNQAECn8hAAIQAAgKoA8sNABVAQAQAAgKoA8sNABVAQAAAA==.',
Fu='Furbees:BAAANQAECgQICQAAAA==.',
Ga='Gandaulf:BAAANQADCgYIBgAAAA==.Gaziban:BAAANQADCgEJAQAAAA==.',
Ge='Geenon:BAAANQAECgYIDwAAAA==.',
Gl='Glide:BAAANQABCgcIBwAAAA==.',
Go='Goldlantern:BAAANQADCgcIDQABNQAECgoKQwARAC4WAA==.',
Gr='Graubard:BAAANQAECgQICQABNQAECgYIFgANAOUEAA==.Grimswhisper:BAAANQAECgYICQAAAA==.Grynsel:BAABNQAECn8gAAITAAgK2goHmgBkAQATAAgK2goHmgBkAQAAAA==.',
Ha='Harlynne:BAAANQADCgYJBgAAAA==.Harukav:BAABNQAECn82AAIDAAoKQxr+KwAZAgADAAoKQxr+KwAZAgAAAA==.',
He='Hela:BAAANQAECgEIAQABNQAECgMIAwAEAAAAAA==.',
Ho='Homrun:BAAANQAECgIIBQAAAA==.',
Ia='Iamtheman:BAAANQADCgYIDgAAAA==.',
Im='Imtoschmexy:BAAANQADCgcIDgAAAA==.',
In='Inwe:BAAANQADCggIIwAAAA==.',
Je='Jesmarie:BAABNQAECn8vAAILAAoKhxh/VADTAQALAAoKhxh/VADTAQAAAA==.',
Jo='Johnnydodge:BAABNQAECn86AAIXAAoKRxKbCQDnAQAXAAoKRxKbCQDnAQAAAA==.Jordon:BAAANQAECgIIAgAAAA==.Joyride:BAABNQAECn8fAAMJAAgK2xBkvABDAQAJAAgKHQ9kvABDAQAFAAMKFAwrQgCMAAAAAA==.',
Ju='Juiceboxx:BAAANQAECgcIDgAAAA==.Jujudini:BAAANQADCgIIAwAAAA==.Jujuwing:BAABNQAECn8wAAMRAAgKXwxyDwA0AQARAAgKXwxyDwA0AQACAAYKmQg3EwCZAAAAAA==.',
Ka='Kanrethad:BAABNQAECn81AAMGAAoKyB8eIQAAAwAGAAoKyB8eIQAAAwAYAAIKdhkNRQCxAAAAAA==.',
Ke='Kerrygan:BAABNQAECn8bAAIWAAgKTwVZUgDGAAAWAAgKTwVZUgDGAAAAAA==.',
Ki='Kicat:BAAANQADCggICAAAAA==.Killà:BAAANQADCgMIAwAAAA==.Kilmister:BAABNQAECn8WAAINAAYK5QTFVQChAAANAAYK5QTFVQChAAAAAA==.Kitsasune:BAACNQAFFH8NAAIWAAcKIQ8GCwBxAQAWAAcKIQ8GCwBxAQA1AAQKfzIAAhYACgqDIFILAN0CABYACgqDIFILAN0CAAAA.',
Ko='Koaì:BAAANQAECgUIBgAAAA==.Korthank:BAABNQAECn8sAAIKAAkKKSDjHAC+AgAKAAkKKSDjHAC+AgAAAA==.Koyanskaya:BAAANQADCgcIDwABNQAECgIIAwAEAAAAAA==.',
Kw='Kwissy:BAAANQAECgEIAQAAAA==.',
['Ká']='Kátiá:BAABNQAECn8gAAIQAAgK7RESMgBhAQAQAAgK7RESMgBhAQAAAA==.',
La='Labellanotte:BAABNQAECn8YAAMZAAgK/QdsVQCNAAAZAAYKEwRsVQCNAAAaAAUKFQW9OQBUAAAAAA==.Landair:BAAANQABCgIIAgAAAA==.Landao:BAAANQABCgYIBQAAAA==.Laoftarf:BAAANQADCgIIAgAAAA==.Layssa:BAABNQAECn8mAAIQAAkK6RzcJgCdAgAQAAkK6RzcJgCdAgAAAA==.',
Li='Lighter:BAAANQADCgUICgAAAA==.Likaal:BAAANQADCggICQAAAA==.Likal:BAAANQADCgcIDAAAAA==.Likall:BAAANQADCgUICgAAAA==.Liliania:BAAANQAECgIIAgAAAA==.Limper:BAAANQADCggIGQAAAA==.Linda:BAAANQABCgYICgAAAA==.Lindona:BAAANQABCgIIAgAAAA==.',
Lu='Lucyford:BAABNQAECn8nAAQIAAoKpgsBZQB1AQAIAAkKHgwBZQB1AQAFAAcKgAzrNwArAQAJAAQK+A4mOwHBAAAAAA==.Lunafox:BAAANQAECgQICAABNQAECggIFwAbAJAQAA==.Lunatic:BAABNQAECn8XAAMbAAgKkBAUFwA9AQAbAAcK/xEUFwA9AQAcAAIK3gciSABlAAAAAA==.',
Ly='Lyraali:BAABNQAECn8WAAITAAcKbBF0gQCcAQATAAcKbBF0gQCcAQAAAA==.',
['Lã']='Lãtha:BAAANQADCgUICQAAAA==.',
Ma='Magemode:BAABNQAECn8lAAIdAAoKMR11JgCaAgAdAAoKMR11JgCaAgAAAA==.Makingfiends:BAABNQAECn8ZAAIGAAkKhxjTfADuAQAGAAkKhxjTfADuAQABNQAECgoKIwAUAMcfAA==.Mar:BAAANQAECgQIBQAAAA==.Marshtonjus:BAAANQADCgQIBAAAAA==.Martyrion:BAAANQADCggIJQAAAA==.Matterhorne:BAAANQADCggIHgAAAA==.',
Me='Melicent:BAAANQAECgIIAgAAAA==.',
Mh='Mhercy:BAAANQAECgQIBwAAAA==.',
Mi='Mikeberetta:BAAANQAECgEIAQAAAA==.Minchin:BAAANQAECgYIDwAAAA==.Miniz:BAAANQAECgIIBAAAAA==.Minlea:BAAANQADCgYIGwAAAA==.Mishacal:BAAANQADCgEIAQAAAA==.Mislahd:BAAANQADCggIHQAAAA==.Mistesla:BAAANQAECgUIBQAAAA==.',
Mo='Moktezuma:BAABNQAECn8WAAIdAAcK6Adh0wDyAAAdAAcK6Adh0wDyAAAAAA==.Moosifer:BAAANQADCgYIBgABNQAECggIHgABADUXAA==.',
Mu='Mutekii:BAABNQAECn8kAAIcAAgK/RI2IwBuAQAcAAgK/RI2IwBuAQAAAA==.',
Na='Natrel:BAAANQAECgYIEAAAAA==.Nausium:BAAANQAECgUICgAAAA==.',
Ni='Niasi:BAAANQADCgYIBgAAAA==.Nier:BAAANQAECgUIBAAAAA==.Niuven:BAAANQAECggIEAAAAA==.',
Oc='Octane:BAAANQADCgEIAQABNQAECgMIAwAEAAAAAA==.Octozm:BAAANQAECgYIDQAAAA==.',
Ol='Oldetimer:BAAANQADCggIDwAAAA==.Olympi:BAAANQADCgcIBwAAAA==.',
Oo='Oolga:BAABNQAECn8zAAIIAAoKESHMGgALAwAIAAoKESHMGgALAwAAAA==.Oopsie:BAAANQADCgQICAAAAA==.',
Op='Optímusprime:BAAANQADCgYIBgAAAA==.',
Or='Oreofrosting:BAABNQAECn8jAAIUAAoKxx//DAAKAwAUAAoKxx//DAAKAwAAAA==.',
Pa='Pally:BAAANQAECggIAgAAAA==.Palmstrike:BAAANQAECgUICQAAAA==.',
Pe='Penderrin:BAABNQAECn8eAAITAAgKjAykugCOAQATAAgKjAykugCOAQAAAA==.Perseffonee:BAABNQAECn8lAAIIAAgKNRTCUQC7AQAIAAgKNRTCUQC7AQAAAA==.',
Ph='Phrenologist:BAAANQADCggIFgAAAA==.Physics:BAACNQAFFH8IAAMLAAUK7w92EgB6AQALAAUK7w92EgB6AQASAAMKgRMsEADMAAA1AAQKfx8ABAsACgqBGPRLAEECAAsABworHfRLAEECABIACgpuEIojABUCAB4AAgqnAO4zABMAAAAA.',
Pu='Pub:BAABNQAECn8lAAIcAAoKoBx9FAALAgAcAAoKoBx9FAALAgAAAA==.',
Py='Pyzemphx:BAAANQAECgQIDAAAAA==.',
Ra='Raelos:BAAANQAECgQIBgAAAA==.Ragebait:BAABNQAECn8eAAIJAAgKnhM2mQCFAQAJAAgKnhM2mQCFAQAAAA==.Ranikina:BAAANQAECgcIEQAAAA==.',
Re='Regal:BAAANQAECgEIAQAAAA==.Regansi:BAAANQAECgMIAwAAAA==.Regasus:BAAANQAECgcIDQAAAA==.Relious:BAAANQADCgYIBgAAAA==.',
Rh='Rheía:BAAANQAECgIIAgABNQAFFAkKLAAFAFQfAA==.Rhysi:BAAANQADCggIDgAAAA==.',
Ri='Riteofdeath:BAAANQADCgIIAgAAAA==.',
Ro='Rock:BAAANQAECgcIDwAAAA==.Rowenne:BAAANQAECgMIBwABNQAECggIFQADAEQEAA==.',
Sa='Sableanne:BAAANQAECgYIBwAAAA==.Sahariel:BAABNQAECn8vAAILAAoK6CEgLAC4AgALAAoK6CEgLAC4AgAAAA==.Sarg:BAAANQAECgIIAgABNQAFFAYIDQATAF4OAA==.Sauce:BAAANQADCgIIAwABNQAECgMIAwAEAAAAAA==.',
Sc='Schwartpheil:BAABNQAECn8eAAITAAgKhAxojADxAQATAAgKhAxojADxAQAAAA==.Scrsaint:BAABNQAECn8tAAMJAAoKnSPxEgAVAwAJAAoKnSPxEgAVAwAFAAEKKR9SYQBXAAAAAA==.',
Se='Seff:BAABNQAECn8dAAIWAAgKnw0rOgBAAQAWAAgKnw0rOgBAAQABNQAECggIJQAIADUUAA==.Selenay:BAAANQAECggICAAAAA==.Seumadruga:BAAANQADCgUIBQAAAA==.',
Sh='Shadowballz:BAAANQADCgMIAwAAAA==.Shamaste:BAAANQAECgMIBQAAAA==.Shardemma:BAAANQADCgUICAAAAA==.Shimmerly:BAAANQAECgMIAwAAAA==.Shytningbolt:BAAANQADCggICAABNQAECgoKMgAHACMhAA==.',
Si='Sintara:BAABNQAECn8mAAICAAoKVAp1DQB3AQACAAoKVAp1DQB3AQAAAA==.',
Sk='Skullsmasher:BAAANQADCgIIAgAAAA==.',
So='Sore:BAAANQAECgYICAAAAA==.',
Sq='Squigyçus:BAABNQAECn9DAAMTAAoKBSRZCgCLAwATAAoKBSRZCgCLAwAfAAEKwhLAEQBNAAABNQAFFAYIGgAHAKskAA==.',
St='Stolensouls:BAAANQADCgYIDwAAAA==.Strawkun:BAAANQADCgYIBgAAAA==.',
['Sç']='Sçruffy:BAACNQAFFH8aAAIHAAYKqyQUAwBoAgAHAAYKqyQUAwBoAgA1AAQKfzwABAcACgo2JfAIAHIDAAcACgo2JfAIAHIDAA0ACAoYFmNnAHQBAA4ACgo/ADnDAAEAAAAA.',
Ta='Talren:BAAANQADCgYICAAAAA==.Talrou:BAAANQADCgIIAgAAAA==.',
Te='Teldryn:BAACNQAFFH8FAAIgAAQKCxqPFQDrAAAgAAQKCxqPFQDrAAA1AAQKf0EAAiAACgoFI2kTAP4CACAACgoFI2kTAP4CAAAA.',
Th='Thorendire:BAABNQAECn8zAAIWAAoKwQ1eKwCeAQAWAAoKwQ1eKwCeAQAAAA==.Thundoor:BAABNQAECn8fAAIRAAgKCgUfFgDCAAARAAgKCgUfFgDCAAAAAA==.',
Ti='Tirnz:BAABNQAECn83AAIOAAoKVgiPPwCHAQAOAAoKVgiPPwCHAQAAAA==.',
Tr='Treeoflife:BAABNQAECn8gAAIZAAcKogkERgAAAQAZAAcKogkERgAAAQAAAA==.Trixielou:BAAANQAECgUICQAAAA==.',
Tu='Tuskanir:BAAANQABCgIJAgAAAA==.',
Va='Vaelestrix:BAACNQAFFH8PAAMhAAcKwxkBBQDVAQAhAAUKYhgBBQDVAQAiAAQK1BuDBwC+AAA1AAQKf04AAyEACgq6JoEAAJkDACEACgq6JoEAAJkDACIACQruI+gEAIUDAAAA.Vaelora:BAAANQADCggIEQAAAA==.Vaynn:BAAANQADCggIDgAAAA==.',
Vi='Violetara:BAAANQADCggICAAAAA==.',
Vo='Voiddøøde:BAAANQADCgQIBAAAAA==.Voidsocket:BAAANQADCggICAABNQAECgQIBQAEAAAAAA==.',
Vu='Vulpvs:BAAANQADCgcIDwAAAA==.',
Vv='Vvlpvs:BAAANQADCgYIEAAAAA==.',
Wa='Warherald:BAABNQAECn81AAIjAAkKJw3+GQAfAQAjAAkKJw3+GQAfAQAAAA==.',
We='Wednesday:BAACNQAFFH8XAAIHAAkKBg9/AwBaAgAHAAkKBg9/AwBaAgA1AAQKfyMAAgcACQqpIh4OAD8DAAcACQqpIh4OAD8DAAAA.',
Xa='Xandril:BAAANQAECgQIBAABNQAECgcIFgAMALkJAA==.',
Xi='Xirek:BAABNQAECn8fAAIjAAgKhw8VGQAoAQAjAAgKhw8VGQAoAQAAAA==.',
['Xì']='Xìlin:BAAANQABCgEIAQABNQAECgUIBgAEAAAAAA==.',
Yr='Yreasak:BAABNQAECn8eAAMGAAcKBQ97nwCXAQAGAAcKBQ97nwCXAQAYAAIKYA0vZABcAAAAAA==.Yrisan:BAAANQADCgcIEgABNQAECgcIHgAGAAUPAA==.',
Ys='Yseulde:BAAANQADCgYIDAABNQAECgcIHgAGAAUPAA==.',
Za='Zapfren:BAAANQADCgEIAgABNQAECgoKIwAUAMcfAA==.Zarnok:BAAANQADCggIHgAAAA==.',
Ze='Zeratüle:BAAANQADCgcIBwAAAA==.',
Zo='Zosimos:BAAANQADCgcIBwAAAA==.',
Zu='Zurâ:BAABNQAECn86AAIHAAoKpwWFTwDwAAAHAAoKpwWFTwDwAAAAAA==.',
['Çh']='Çhief:BAAANQAECgMIAwAAAA==.',
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
