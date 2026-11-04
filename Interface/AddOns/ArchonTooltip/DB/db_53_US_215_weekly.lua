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

local lookup = {'Warlock-Affliction','Evoker-Augmentation','Shaman-Elemental','Unknown-Unknown','Paladin-Protection','Warlock-Demonology','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Priest-Holy','Evoker-Preservation','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Druid-Guardian','Druid-Balance','Evoker-Devastation','Hunter-BeastMastery','Monk-Windwalker','Mage-Frost','Warrior-Fury','Warlock-Destruction','DemonHunter-Havoc','Mage-Arcane','DemonHunter-Devourer','Priest-Discipline','Hunter-Survival','Warrior-Arms','Druid-Restoration','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Addykikora:BAAANQADCgYIEQABNQAECgcIHAABABoXAA==.',
Ae='Aeonmoksha:BAAANQAECgIIAgAAAA==.',
Ai='Ailuridae:BAAANQAECgEIAQAAAA==.Airo:BAAANQADCgIIAgAAAA==.',
Ak='Akaris:BAABNQAECn8bAAICAAcKIwb6EwDvAAACAAcKIwb6EwDvAAAAAA==.',
Al='Alainea:BAABNQAECn8VAAIDAAgKRARcgwDPAAADAAgKRARcgwDPAAAAAA==.Alorgynn:BAAANQABCgIIAwABNQAECgUICQAEAAAAAA==.Alôra:BAAANQAECgEIAwABNQAECgUICQAEAAAAAA==.',
Am='Amaterasu:BAACNQAFFH8qAAIFAAkKKh81AACVAgAFAAkKKh81AACVAgA1AAQKfywAAgUACgqOJgwDAJUDAAUACgqOJgwDAJUDAAE1AAUUCQoqAAUAKh8A.Ambre:BAAANQAECgcICwAAAA==.',
An='Andross:BAAANQADCggICAABNQAECgcIHgAGAAUPAA==.Angwy:BAAANQAECgUIBgAAAA==.',
Ar='Ara:BAAANQAECgQICAAAAA==.Archhùnter:BAAANQADCgEIAwAAAA==.Ariannae:BAAANQAECgYIBgAAAA==.',
As='Ashamed:BAABNQAFFH8FAAIHAAIKJAi+IABCAAAHAAIKJAi+IABCAAABNQAFFAkKKgAFACofAA==.',
At='Atropa:BAAANQADCgYIBgAAAA==.',
Au='Aura:BAABNQAECn9IAAMIAAoK+x49FgDZAgAIAAoK+x49FgDZAgAJAAIKpxDrZAF+AAAAAA==.',
Ax='Axl:BAAANQAECgIIAwAAAA==.',
Ay='Aylíth:BAAANQAECgQIBwABNQAFFAkKKgAFACofAA==.',
Ba='Bah:BAAANQADCggIPAAAAA==.Banjoo:BAAANQAECgIIAgAAAA==.Baruk:BAABNQAECn87AAMKAAoK9xRHSwA2AgAKAAoK9xRHSwA2AgADAAYKXwR7mgCeAAAAAA==.',
Be='Benny:BAAANQAECgUICQABNQAECgoKKQALAN0hAA==.Bergelmir:BAAANQAECgIIAwAAAA==.',
Bi='Bigçhungi:BAAANQAECgYICQABNQAFFAYIGgAHAKskAA==.',
Bl='Blitzen:BAABNQAECn84AAIMAAoKxBzYCwDnAgAMAAoKxBzYCwDnAgAAAA==.',
Bo='Boozamabeard:BAAANQAECggIDQAAAA==.Borealiss:BAABNQAECn8UAAMLAAYKQQmvvwDcAAALAAYKQQmvvwDcAAANAAUKAQ49NwCnAAABNQAECgoKOAAMAMQcAA==.Boxofmilk:BAAANQAECgIIAgAAAA==.',
Br='Break:BAEANQAECgYICQABNQAFFAcKHwAJAK4lAA==.',
Bw='Bwonsamdi:BAAANQADCgcICwAAAA==.',
['Bâ']='Bârks:BAABNQAECn8bAAILAAkKoBjyNQAwAgALAAkKoBjyNQAwAgAAAA==.',
Ca='Caarij:BAABNQAECn9BAAMOAAoKixZYMQBoAgAOAAkKMBdYMQBoAgAPAAQKkQt+cwCdAAAAAA==.Cadence:BAAANQAECgMIBQAAAA==.Callia:BAAANQADCgIIAgAAAA==.Canoe:BAAANQADCgEIAQAAAA==.',
Ce='Celorana:BAAANQADCgYIBwAAAA==.Cerra:BAAANQAECgEIBQAAAA==.',
Ch='Chijirô:BAAANQAECgEIAQAAAA==.Choleena:BAABNQAECn8ZAAIKAAgKWxHxZABVAQAKAAgKWxHxZABVAQAAAA==.',
Co='Coojotwo:BAAANQADCgUIBQAAAA==.Coppola:BAAANQADCgEIAQAAAA==.',
['Cí']='Círce:BAAANQAECggICAABNQAFFAkKKgAFACofAA==.',
Da='Dangerwithin:BAAANQAECgQIBgABNQAFFAkKKgAFACofAA==.Danklazercat:BAABNQAECn8XAAMQAAoKQxvOCACJAgAQAAoKQxvOCACJAgARAAMKkgRSsAA2AAABNQAFFAYIGgAHAKskAA==.Darius:BAAANQAFFAEIAQAAAA==.Dastinele:BAAANQADCgUIBQAAAA==.Dastraz:BAABNQAECn8WAAMMAAcKuQlYNQDpAAAMAAcKuQlYNQDpAAASAAQKgAZ/MACUAAAAAA==.',
De='Deaconblues:BAAANQADCgEIAQABNQAECggIDQAEAAAAAA==.Devkra:BAABNQAECn8cAAIHAAcKFhSNVwCVAQAHAAcKFhSNVwCVAQAAAA==.',
Dh='Dharma:BAABNQAECn8lAAMNAAoKbxHMMQCUAQANAAoKbxHMMQCUAQALAAIKXQS3ygBdAAAAAA==.',
Do='Doge:BAABNQAECn8gAAITAAgKDQZmqQCyAQATAAgKDQZmqQCyAQAAAA==.',
Dr='Drakona:BAAANQADCgUIBQAAAA==.Drapenthim:BAAANQADCgQIBAAAAA==.',
Du='Dudemachine:BAAANQADCgMIAwABNQAECgoKIwAUAMcfAA==.',
['Dé']='Déadpool:BAAANQAECgIIAwAAAA==.',
['Dø']='Døødemage:BAAANQAECgIIAQAAAA==.',
Ed='Eddison:BAAANQAECgIIAgAAAA==.',
El='Elementhor:BAAANQAECgUIBgAAAA==.Eloralove:BAAANQADCggICAAAAA==.Eltrys:BAAANQADCgYIBgAAAA==.',
En='Enchanted:BAABNQAECn8gAAIOAAkKlB94OgA5AgAOAAkKlB94OgA5AgAAAA==.Ender:BAABNQAECn8fAAIVAAcK1wnVFQBRAQAVAAcK1wnVFQBRAQAAAA==.',
Es='Eskanor:BAAANQADCgQIBAAAAA==.',
Et='Eternalwrath:BAABNQAECn8ZAAMOAAgK3xBWLgBGAQAOAAgK3xBWLgBGAQAHAAEKSwWOlwAuAAAAAA==.',
Fe='Felmary:BAAANQAECgYIEwAAAA==.',
Fi='Firnen:BAAANQADCgMIAwAAAA==.',
Fo='Foxxylady:BAAANQAECgcIEAAAAA==.',
Fr='Freyja:BAABNQAECn8gAAIRAAgKCw/aMABIAQARAAgKCw/aMABIAQAAAA==.',
Fu='Furbees:BAAANQAECgQICQAAAA==.',
Ga='Gaziban:BAAANQADCgEJAQAAAA==.',
Ge='Geenon:BAAANQAECgUIDgAAAA==.',
Gl='Glide:BAAANQADCgEIAQAAAA==.',
Go='Goldlantern:BAAANQADCgcIDwABNQAECgoKOQASANkUAA==.',
Gr='Graubard:BAAANQAECgQICgAAAA==.Grimswhisper:BAAANQAECgYICQAAAA==.Grynsel:BAABNQAECn8aAAITAAgKKQosjwBPAQATAAgKKQosjwBPAQAAAA==.',
Ha='Harlynne:BAAANQADCgYJBwAAAA==.Harukav:BAABNQAECn8sAAIDAAoKQxqxRgBbAgADAAoKQxqxRgBbAgAAAA==.',
He='Hela:BAAANQAECgEIAQABNQAECgMIBgAEAAAAAA==.',
Ho='Homrun:BAAANQAECgMIBwAAAA==.',
Ia='Iamtheman:BAAANQADCgYIDwAAAA==.',
Im='Imtoschmexy:BAAANQADCgcIDgAAAA==.',
In='Inwe:BAAANQADCggIHwAAAA==.',
Je='Jesmarie:BAABNQAECn8rAAILAAoKhxgdSADfAQALAAoKhxgdSADfAQAAAA==.',
Jo='Johnnydodge:BAABNQAECn8xAAIWAAkKShHOCwCLAQAWAAkKShHOCwCLAQAAAA==.Jordon:BAAANQAECgIIAgAAAA==.Joridan:BAAANQADCgEIAQAAAA==.Joyride:BAABNQAECn8ZAAMJAAgKMhAWvgAYAQAJAAgKcw4WvgAYAQAFAAIK0wzBRwBgAAAAAA==.',
Ju='Juiceboxx:BAAANQAECgcIDgAAAA==.Jujudini:BAAANQAECgEIAQAAAA==.Jujuwing:BAABNQAECn8mAAMSAAgK3gmFEwDOAAASAAgKswiFEwDOAAACAAYKmQheEQCaAAAAAA==.',
Ka='Kanrethad:BAABNQAECn81AAMGAAoKyB8eIQAAAwAGAAoKyB8eIQAAAwAXAAIKdhkNRQCxAAAAAA==.',
Ke='Kerrygan:BAABNQAECn8bAAIYAAgKTwVLSwDDAAAYAAgKTwVLSwDDAAAAAA==.',
Ki='Kicat:BAAANQADCggICAAAAA==.Killà:BAAANQADCgMIBAAAAA==.Kilmister:BAAANQAECgMICQABNQAECgQICgAEAAAAAA==.Kitsasune:BAACNQAFFH8MAAIYAAYK6g4GCwBxAQAYAAYK6g4GCwBxAQA1AAQKfzAAAhgACgoOIM0cALMCABgACgoOIM0cALMCAAAA.',
Ko='Koaì:BAAANQAECgUICQAAAA==.Korthank:BAABNQAECn8sAAIKAAkKKSDJFwDMAgAKAAkKKSDJFwDMAgAAAA==.Koyanskaya:BAAANQADCgcIDwABNQAECgIIAwAEAAAAAA==.',
Kw='Kwissy:BAAANQAECgEIAgAAAA==.',
['Ká']='Kátiá:BAABNQAECn8aAAIRAAgKPhEyLgBZAQARAAgKPhEyLgBZAQAAAA==.',
La='Labellanotte:BAAANQAECgcIEgAAAA==.Landair:BAAANQADCgEIAQAAAA==.Landao:BAAANQABCgYIBQAAAA==.Laoftarf:BAAANQADCgIIAgAAAA==.Layssa:BAABNQAECn8mAAIRAAkK6RzcJgCdAgARAAkK6RzcJgCdAgAAAA==.',
Li='Lighter:BAAANQADCgUICgAAAA==.Likaal:BAAANQADCggICQAAAA==.Likal:BAAANQADCgcIDAAAAA==.Likall:BAAANQADCgUICwAAAA==.Liliania:BAAANQAECgIIAgAAAA==.Limper:BAAANQADCggIGQAAAA==.Linda:BAAANQADCgEIAQAAAA==.Lindona:BAAANQADCgEIAQAAAA==.',
Lu='Lucyford:BAABNQAECn8iAAQIAAkKAwz2ZgBPAQAIAAgKlgz2ZgBPAQAFAAcKgAzrNwArAQAJAAQK+A4mOwHBAAAAAA==.Lunafox:BAAANQAECgQICAABNQAECgcIEAAEAAAAAA==.Lunatic:BAAANQAECgcIEAAAAA==.',
Ly='Lyraali:BAAANQAECgcIEAAAAA==.',
['Lã']='Lãtha:BAAANQADCgUICQAAAA==.',
Ma='Magemode:BAABNQAECn8cAAIZAAkK+xgqkQBdAgAZAAkK+xgqkQBdAgAAAA==.Makingfiends:BAABNQAECn8ZAAIGAAkKhxjTfADuAQAGAAkKhxjTfADuAQABNQAECgoKIwAUAMcfAA==.Mar:BAAANQAECgQIBQAAAA==.Marshtonjus:BAAANQADCgQIBAAAAA==.Martyrion:BAAANQADCggIJQAAAA==.Matterhorne:BAAANQADCggIHgAAAA==.',
Me='Melicent:BAAANQAECgIIAgAAAA==.',
Mh='Mhercy:BAAANQAECgQIBwAAAA==.',
Mi='Mikeberetta:BAAANQAECgEIAQAAAA==.Minchin:BAAANQAECgYICgAAAA==.Miniz:BAAANQAECgIIBAAAAA==.Minlea:BAAANQADCgYIFgAAAA==.Mishacal:BAAANQADCgEIAQAAAA==.Mislahd:BAAANQADCggIFgAAAA==.Mistesla:BAAANQAECgUIBQAAAA==.',
Mo='Moktezuma:BAABNQAECn8UAAIZAAYKWgjLKwFDAQAZAAYKWgjLKwFDAQAAAA==.',
Mu='Mutekii:BAABNQAECn8kAAIaAAgK/RIlHwBzAQAaAAgK/RIlHwBzAQAAAA==.',
Na='Natrel:BAAANQAECgYIEQAAAA==.Nausium:BAAANQAECgUICgAAAA==.',
Ni='Niasi:BAAANQADCgYIBgAAAA==.Nier:BAAANQAECgUIBAAAAA==.Niuven:BAAANQAECggIEAAAAA==.',
Oc='Octane:BAAANQADCgEIAQABNQAECgMIBgAEAAAAAA==.Octozm:BAAANQAFFAEIAQAAAA==.',
Ol='Oldetimer:BAAANQADCggIDwAAAA==.Olympi:BAAANQADCgcICAAAAA==.',
Oo='Oolga:BAABNQAECn8zAAIIAAoKESHMGgALAwAIAAoKESHMGgALAwAAAA==.Oopsie:BAAANQADCgQICAAAAA==.Oot:BAAANQADCgEIAgAAAA==.',
Op='Optímusprime:BAAANQAECgIIAgAAAA==.',
Or='Oreofrosting:BAABNQAECn8jAAIUAAoKxx//DAAKAwAUAAoKxx//DAAKAwAAAA==.',
Os='Oshiokiyo:BAAANQADCgEIAQAAAA==.',
Pa='Padraigah:BAAANQADCgEIAQAAAA==.Pally:BAAANQAECggIAgAAAA==.Palmstrike:BAAANQAECgUIBQAAAA==.',
Pe='Penderrin:BAABNQAECn8cAAITAAcKlgykugCOAQATAAcKlgykugCOAQAAAA==.Perseffonee:BAABNQAECn8jAAIIAAgK1xNlVQCMAQAIAAgK1xNlVQCMAQAAAA==.',
Ph='Phrenologist:BAAANQADCggIFgAAAA==.Physics:BAACNQAFFH8IAAMLAAUK7w92EgB6AQALAAUK7w92EgB6AQANAAMKgRMsEADMAAA1AAQKfx8ABAsACgqBGPRLAEECAAsABworHfRLAEECAA0ACgpuEIojABUCABsAAgqnAO4zABMAAAAA.',
Pu='Pub:BAABNQAECn8hAAIaAAoKpxoTHAB1AgAaAAoKpxoTHAB1AgAAAA==.',
Py='Pyzemphx:BAAANQAECgQIDAAAAA==.',
Ra='Raelos:BAAANQAECgQIBgAAAA==.Ragebait:BAABNQAECn8YAAIJAAcKaxMltgAlAQAJAAcKaxMltgAlAQAAAA==.Ranikina:BAAANQAECgUIEQAAAA==.',
Re='Regal:BAAANQAECgEIAQAAAA==.Regansi:BAAANQAECgMIBQAAAA==.Regasus:BAAANQAECgUICAAAAA==.Relious:BAAANQADCgYIBgAAAA==.',
Rh='Rheía:BAAANQAECgIIAgABNQAFFAkKKgAFACofAA==.Rhysi:BAAANQADCggIEAAAAA==.',
Ri='Riteofdeath:BAAANQADCgIIAgAAAA==.',
Ro='Rock:BAAANQAECggIEAAAAA==.Roshkohen:BAAANQAECgEIAQAAAA==.Rowenne:BAAANQAECgMIBwABNQAECggIFQADAEQEAA==.',
Sa='Sableanne:BAAANQAECgEIAgAAAA==.Sahariel:BAABNQAECn8pAAILAAoK3SEgLAC4AgALAAoK3SEgLAC4AgAAAA==.Sarg:BAAANQAECgIIAgABNQAFFAYIDQATAF4OAA==.Sauce:BAAANQADCgIIBAABNQAECgMIBgAEAAAAAA==.Savvylock:BAAANQAECgEIAQABNQAECgkJLgAKAHoaAA==.Savvywone:BAAANQAECgEIAQABNQAECgkJLgAKAHoaAA==.',
Sc='Schwartpheil:BAABNQAECn8eAAITAAgKhAxojADxAQATAAgKhAxojADxAQAAAA==.Scrsaint:BAABNQAECn8tAAMJAAoKnSNADgAgAwAJAAoKnSNADgAgAwAFAAEKKR9SYQBXAAAAAA==.',
Se='Seff:BAABNQAECn8WAAIYAAYKHwluXAARAQAYAAYKHwluXAARAQABNQAECggIIwAIANcTAA==.Seumadruga:BAAANQADCgUIBQAAAA==.',
Sh='Shadowballz:BAAANQADCgMIAwAAAA==.Shamaste:BAAANQAECgMIBQAAAA==.Shardemma:BAAANQADCgUICAAAAA==.Sharona:BAAANQADCgEIAQABNQAECgoKSAAIAPseAA==.Shimmerly:BAAANQAECgMIBgAAAA==.Shytningbolt:BAAANQADCggICAABNQAECgoKMgAHACMhAA==.',
Si='Sintara:BAABNQAECn8mAAICAAoKVAp1DQB3AQACAAoKVAp1DQB3AQAAAA==.',
Sk='Skullsmasher:BAAANQADCgIIAgAAAA==.',
So='Soragga:BAAANQADCgEIAwAAAA==.Sore:BAAANQAECgYICAAAAA==.',
Sq='Squigyçus:BAABNQAECn85AAMTAAkKhSRZCgCLAwATAAkKhSRZCgCLAwAcAAEKwhLAEQBNAAABNQAFFAYIGgAHAKskAA==.',
St='Stolensouls:BAAANQADCgYIEAAAAA==.Strawkun:BAAANQADCgYIBgAAAA==.',
['Sç']='Sçruffy:BAACNQAFFH8aAAIHAAYKqyQUAwBoAgAHAAYKqyQUAwBoAgA1AAQKfzwABAcACgo2JfAIAHIDAAcACgo2JfAIAHIDAA4ACAoYFmNnAHQBAA8ACgo/AMS0AAEAAAAA.',
Ta='Talren:BAAANQADCgYICAAAAA==.',
Te='Teldryn:BAACNQAFFH8FAAIdAAQKCxqzEQDxAAAdAAQKCxqzEQDxAAA1AAQKfzwAAh0ACgr+Ip0SAPYCAB0ACgr+Ip0SAPYCAAAA.',
Th='Thorendire:BAABNQAECn8yAAIYAAkKrAxwLwBcAQAYAAkKrAxwLwBcAQAAAA==.Thundoor:BAABNQAECn8YAAISAAcKKASeKQDeAAASAAcKKASeKQDeAAAAAA==.',
Ti='Tirnz:BAABNQAECn8zAAIPAAoK7gdhOQB9AQAPAAoK7gdhOQB9AQAAAA==.',
Tr='Treeoflife:BAABNQAECn8gAAIeAAcKogkERgAAAQAeAAcKogkERgAAAQAAAA==.Trixielou:BAAANQAECgUIBQAAAA==.',
Tu='Tuskanir:BAAANQADCgEIAQAAAA==.',
Va='Vaelestrix:BAACNQAFFH8NAAMfAAYK3RcBBQDVAQAfAAUKYhgBBQDVAQAgAAMKTBbGEgC5AAA1AAQKf04AAx8ACgq6JncAAJUDAB8ACgq6JncAAJUDACAACQruI+gEAIUDAAAA.Vaelora:BAAANQADCggIEgAAAA==.Vaynn:BAAANQADCggIDgAAAA==.',
Vi='Violetara:BAAANQADCggICAAAAA==.',
Vo='Voiddøøde:BAAANQADCgQIBAAAAA==.Voidsocket:BAAANQADCggICAABNQAECgQIBQAEAAAAAA==.',
Vu='Vulpvs:BAAANQADCgcIDwAAAA==.',
Vv='Vvlpvs:BAAANQADCgYIEAAAAA==.',
Wa='Warcry:BAAANQAECgEIAQAAAA==.Warherald:BAABNQAECn8vAAIhAAgKDg6AGgCPAQAhAAgKDg6AGgCPAQAAAA==.',
We='Wednesday:BAACNQAFFH8XAAIHAAkKBg9/AwBaAgAHAAkKBg9/AwBaAgA1AAQKfyMAAgcACQqpIh4OAD8DAAcACQqpIh4OAD8DAAAA.',
Xa='Xandril:BAAANQAECgQIBAABNQAECgcIFgAMALkJAA==.',
Xi='Xirek:BAABNQAECn8ZAAIhAAgKhw9cFQAwAQAhAAgKhw9cFQAwAQAAAA==.',
['Xì']='Xìlin:BAAANQABCgEIAQABNQAECgUICQAEAAAAAA==.',
Yr='Yreasak:BAABNQAECn8eAAMGAAcKBQ97nwCXAQAGAAcKBQ97nwCXAQAXAAIKYA0vZABcAAAAAA==.Yrisan:BAAANQADCgcIEwABNQAECgcIHgAGAAUPAA==.',
Ys='Yseulde:BAAANQADCgYIDAABNQAECgcIHgAGAAUPAA==.',
Za='Zajin:BAAANQADCgEIAQAAAA==.Zajingo:BAAANQADCgEIAQAAAA==.Zapfren:BAAANQADCgEIAgABNQAECgoKIwAUAMcfAA==.Zarnok:BAAANQADCggIIQAAAA==.',
Ze='Zeratüle:BAAANQADCgcIBwAAAA==.Zerc:BAAANQADCgEIAQAAAA==.Zercmon:BAAANQADCgEIAQAAAA==.',
Zo='Zorox:BAAANQADCgEIAQAAAA==.Zosimos:BAAANQADCgcIBwAAAA==.',
Zu='Zurâ:BAABNQAECn80AAIHAAkKWwUETwDYAAAHAAkKWwUETwDYAAAAAA==.',
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
