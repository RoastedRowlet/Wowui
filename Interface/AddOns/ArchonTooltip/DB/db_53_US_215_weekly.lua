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

local lookup = {'Warlock-Affliction','Evoker-Augmentation','Unknown-Unknown','Paladin-Protection','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Priest-Holy','DeathKnight-Blood','Evoker-Preservation','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Hunter-BeastMastery','Monk-Windwalker','Mage-Frost','Evoker-Devastation','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Druid-Balance','Mage-Arcane','DemonHunter-Devourer','Priest-Discipline','Hunter-Survival','Warrior-Arms','DemonHunter-Havoc','Druid-Restoration','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Addykikora:BAAANQADCgYIBgABNQAECgYIGwABAKYZAA==.',
Ae='Aeonmoksha:BAAANQAECgIIAgAAAA==.',
Ai='Airo:BAAANQADCgIIAgAAAA==.',
Ak='Akaris:BAABNQAECn8VAAICAAYK9Qb6EwDvAAACAAYK9Qb6EwDvAAAAAA==.',
Al='Alainea:BAAANQAECgYIEwAAAA==.Alorgynn:BAAANQABCgIIAwABNQAECgQIBgADAAAAAA==.',
Am='Amaterasu:BAACNQAFFH8bAAIEAAgKhiDWAACkAgAEAAgKhiDWAACkAgA1AAQKfyoAAgQACgorJgwDAJUDAAQACgorJgwDAJUDAAE1AAUUCAobAAQAhiAA.Ambre:BAAANQAECgcICwAAAA==.',
An='Angwy:BAAANQAECgIIAgAAAA==.',
Ar='Ara:BAAANQAECgQICAAAAA==.Archhùnter:BAAANQABCgQIBAAAAA==.Ariannae:BAAANQAECgYIBgAAAA==.',
As='Ashamed:BAAANQAFFAEIAQABNQAFFAgKGwAEAIYgAA==.',
At='Atropa:BAAANQADCgYIBgAAAA==.',
Au='Aura:BAABNQAECn85AAMFAAoKHx1hJADZAgAFAAoKHx1hJADZAgAGAAIKpxDrZAF+AAAAAA==.',
Ax='Axl:BAAANQAECgIIAwAAAA==.',
Ay='Aylíth:BAAANQAECgQIBwABNQAFFAgKGwAEAIYgAA==.',
Ba='Bah:BAAANQADCggIKwAAAA==.Banjoo:BAAANQAECgIIAgAAAA==.Baruk:BAABNQAECn8wAAMHAAoKtBRHSwA2AgAHAAoKtBRHSwA2AgAIAAMKagP0EwFlAAAAAA==.',
Be='Benny:BAAANQAECgQIBAABNQAECgkJJwAJALUhAA==.',
Bi='Bigçhungi:BAAANQAECgYICQABNQAFFAYIGgAKAKskAA==.',
Bl='Blitzen:BAABNQAECn8xAAILAAoKIhrYCwDnAgALAAoKIhrYCwDnAgAAAA==.',
Bo='Boozamabeard:BAAANQAECggIDQAAAA==.Borealiss:BAAANQAECgUIDgABNQAECgoKMQALACIaAA==.',
Br='Break:BAAANQAECgYICQABNQAFFAcKHwAGAK4lAA==.',
Bw='Bwonsamdi:BAAANQADCgcIBwAAAA==.',
['Bâ']='Bârks:BAAANQAECgUIEAAAAA==.',
Ca='Caarij:BAABNQAECn8vAAMMAAkKGRUfDwBlAQAMAAgKkRcfDwBlAQANAAMK4AizUgBpAAAAAA==.Cadence:BAAANQAECgMIBQAAAA==.Callia:BAAANQADCgIIAgAAAA==.',
Ce='Celorana:BAAANQADCgYIBgAAAA==.',
Ch='Chijirô:BAAANQAECgEIAQAAAA==.Choleena:BAAANQAECgUIEAAAAA==.',
Co='Coojotwo:BAAANQADCgUIBQAAAA==.Coppola:BAAANQABCgUJAwAAAA==.',
['Cí']='Círce:BAAANQAECggICAABNQAFFAgKGwAEAIYgAA==.',
Da='Dangerwithin:BAAANQAECgMIAwABNQAFFAgKGwAEAIYgAA==.Danklazercat:BAAANQAECgQIAwABNQAFFAYIGgAKAKskAA==.Darius:BAAANQAFFAEIAQAAAA==.Dastinele:BAAANQADCgUIBQAAAA==.Dastraz:BAAANQAECgcIEgAAAA==.',
De='Deaconblues:BAAANQABCgMIBQABNQAECggIDQADAAAAAA==.Devkra:BAABNQAECn8bAAIKAAYK4haNVwCVAQAKAAYK4haNVwCVAQAAAA==.',
Dh='Dharma:BAABNQAECn8dAAMOAAkKeBDMMQCUAQAOAAgKiA7MMQCUAQAJAAEK0AWongAxAAAAAA==.',
Do='Doge:BAABNQAECn8aAAIPAAgK/AVmqQCyAQAPAAgK/AVmqQCyAQAAAA==.',
Dr='Drakona:BAAANQADCgUIBQAAAA==.Drapenthim:BAAANQADCgQIAwAAAA==.',
Du='Dudemachine:BAAANQADCgMIAwABNQAECgoKIAAQAOgdAA==.',
['Dø']='Døødemage:BAAANQAECgIIAQAAAA==.',
Ed='Eddison:BAAANQAECgIIAgAAAA==.',
El='Elementhor:BAAANQAECgUIBAAAAA==.Eloralove:BAAANQADCggICAAAAA==.',
En='Enchanted:BAABNQAECn8gAAIMAAkKlB94OgA5AgAMAAkKlB94OgA5AgAAAA==.Ender:BAABNQAECn8ZAAIRAAcK1wnVFQBRAQARAAcK1wnVFQBRAQAAAA==.',
Es='Eskanor:BAAANQADCgQJBAAAAA==.',
Et='Eternalwrath:BAAANQAECgUIEAAAAA==.',
Fe='Felmary:BAAANQAECgUIDQAAAA==.',
Fi='Firnen:BAAANQADCgMIAwAAAA==.',
Fo='Foxxylady:BAAANQAECgUIBAAAAA==.',
Fr='Freyja:BAAANQAECgYIDQAAAA==.',
Fu='Furbees:BAAANQAECgQICQAAAA==.',
Ga='Gaziban:BAAANQADCgEJAQAAAA==.',
Ge='Geenon:BAAANQAECgQIBwAAAA==.',
Gl='Glide:BAAANQABCgcIBwAAAA==.',
Go='Goldlantern:BAAANQADCgcIDQABNQAECggILgASABQXAA==.',
Gr='Graubard:BAAANQAECgQICAAAAA==.Grimswhisper:BAAANQAECgUICAAAAA==.Grynsel:BAAANQAECgUIEQAAAA==.',
Ha='Harlynne:BAAANQADCgYJBgAAAA==.Harukav:BAABNQAECn8kAAIIAAoKJBkgFwBnAQAIAAoKJBkgFwBnAQAAAA==.',
He='Hela:BAAANQAECgEIAQAAAA==.',
Ho='Homrun:BAAANQAECgIIAgAAAA==.',
Ia='Iamtheman:BAAANQADCgYIDgAAAA==.',
Im='Imtoschmexy:BAAANQADCgcIDgAAAA==.',
In='Inwe:BAAANQADCggIHQAAAA==.',
Je='Jesmarie:BAABNQAECn8gAAIJAAkK7Re8XAALAgAJAAkK7Re8XAALAgAAAA==.',
Jo='Johnnydodge:BAABNQAECn8iAAITAAcKPxLoBgAsAQATAAcKPxLoBgAsAQAAAA==.Jordon:BAAANQAECgIIAgAAAA==.Joyride:BAAANQAECgUIEAAAAA==.',
Ju='Juiceboxx:BAAANQAECgcIDgAAAA==.Jujuwing:BAABNQAECn8bAAMCAAYKJAzmBgCuAAASAAYKZAqwIwAlAQACAAUKmQjmBgCuAAAAAA==.',
['Jù']='Jùde:BAAANQAECgIIAwAAAA==.',
Ka='Kanrethad:BAABNQAECn8uAAMUAAkKSx8eIQAAAwAUAAkKSx8eIQAAAwAVAAIKdhkNRQCxAAAAAA==.',
Ke='Kerrygan:BAAANQAECgYIEgAAAA==.',
Ki='Kicat:BAAANQADCggICAAAAA==.Killà:BAAANQADCgMIAwAAAA==.Kilmister:BAAANQAECgMIBgABNQAECgQICAADAAAAAA==.',
Ko='Koaì:BAAANQAECgQIBgAAAA==.Korthank:BAABNQAECn8iAAIHAAgKkxZVWwD9AQAHAAgKkxZVWwD9AQAAAA==.Koyanskaya:BAAANQADCgcIDwABNQAECgIIAwADAAAAAA==.',
Kw='Kwissy:BAAANQAECgEIAQAAAA==.',
['Ká']='Kátiá:BAAANQAECgYIDwAAAA==.',
La='Labellanotte:BAAANQAECgUIEAAAAA==.Landair:BAAANQABCgIIAgAAAA==.Landao:BAAANQABCgYIBQAAAA==.Laoftarf:BAAANQADCgIIAgAAAA==.Layssa:BAABNQAECn8jAAIWAAkK6RzcJgCdAgAWAAkK6RzcJgCdAgAAAA==.',
Li='Lighter:BAAANQADCgUICgAAAA==.Likal:BAAANQADCgcIDAAAAA==.Likall:BAAANQADCgUICgAAAA==.Liliania:BAAANQAECgIIAgAAAA==.Limper:BAAANQADCggIEAAAAA==.Linda:BAAANQABCgYICgAAAA==.Lindona:BAAANQABCgIIAgAAAA==.',
Lu='Lucyford:BAABNQAECn8ZAAQEAAkK3g/rNwArAQAEAAcKgAzrNwArAQAFAAYKXQsUTQDGAAAGAAQK+A4mOwHBAAAAAA==.Lunafox:BAAANQAECgIIBAABNQAECgUIDAADAAAAAA==.Lunatic:BAAANQAECgUIDAAAAA==.',
Ly='Lyraali:BAAANQAECgQICAAAAA==.',
['Lã']='Lãtha:BAAANQADCgUICQAAAA==.',
Ma='Magemode:BAABNQAECn8YAAIXAAkKVxgqkQBdAgAXAAkKVxgqkQBdAgAAAA==.Makingfiends:BAABNQAECn8WAAIUAAkK2hY9MAA3AQAUAAkK2hY9MAA3AQABNQAECgoKIAAQAOgdAA==.Mar:BAAANQAECgQIBAAAAA==.Marshtonjus:BAAANQADCgQIBAAAAA==.Martyrion:BAAANQADCggIJQAAAA==.Matterhorne:BAAANQADCggIHgAAAA==.',
Me='Melicent:BAAANQAECgIIAgAAAA==.',
Mh='Mhercy:BAAANQAECgQIBwAAAA==.',
Mi='Mikeberetta:BAAANQAECgEIAQAAAA==.Minchin:BAAANQAECgUIBgAAAA==.Miniz:BAAANQAECgIIBAAAAA==.Minlea:BAAANQADCgYICgAAAA==.Mislahd:BAAANQADCgcIDQAAAA==.Mistesla:BAAANQAECgUIBQAAAA==.',
Mo='Moktezuma:BAAANQAECgYIDwAAAA==.',
Mu='Mutekii:BAABNQAECn8fAAIYAAgKOBK7CACFAQAYAAgKOBK7CACFAQAAAA==.',
Na='Natrel:BAAANQAECgcIEAAAAA==.Nausium:BAAANQAECgUICgAAAA==.',
Ni='Niasi:BAAANQADCgYIBgAAAA==.Nier:BAAANQAECgQIBAAAAA==.Niuven:BAAANQAECggIEAAAAA==.',
Oc='Octane:BAAANQADCgEIAQABNQAECgEIAQADAAAAAA==.Octozm:BAAANQAECgYIDQAAAA==.',
Ol='Oldetimer:BAAANQADCggIDwAAAA==.Olympi:BAAANQABCggIDQAAAA==.',
Oo='Oolga:BAABNQAECn8uAAIFAAkKViLMGgALAwAFAAkKViLMGgALAwAAAA==.Oopsie:BAAANQADCgQICAAAAA==.',
Op='Optímusprime:BAAANQADCgYIBgAAAA==.',
Or='Oreofrosting:BAABNQAECn8gAAIQAAoK6B3/DAAKAwAQAAoK6B3/DAAKAwAAAA==.',
Pa='Pally:BAAANQAECggIAgAAAA==.Palmstrike:BAAANQAECgUIBQAAAA==.',
Pe='Penderrin:BAABNQAECn8bAAIPAAYKVg2kugCOAQAPAAYKVg2kugCOAQAAAA==.Perseffonee:BAABNQAECn8hAAIFAAcK0BThJABQAQAFAAcK0BThJABQAQAAAA==.',
Ph='Phrenologist:BAAANQADCggIFgAAAA==.Physics:BAACNQAFFH8IAAMJAAUK7w92EgB6AQAJAAUK7w92EgB6AQAOAAMKgRMsEADMAAA1AAQKfx0ABAkACgqBGPRLAEECAAkABworHfRLAEECAA4ACgpuEIojABUCABkAAgqnAO4zABMAAAAA.',
Pu='Pub:BAABNQAECn8YAAIYAAkKpBwTHAB1AgAYAAkKpBwTHAB1AgAAAA==.',
Py='Pyzemphx:BAAANQAECgQIDAAAAA==.',
Ra='Raelos:BAAANQAECgIIAwAAAA==.Ragebait:BAAANQAECgUIEAAAAA==.Ranikina:BAAANQAECgUIEAAAAA==.',
Re='Regal:BAAANQAECgEIAQAAAA==.Regansi:BAAANQADCgIIBAAAAA==.Regasus:BAAANQAECgMIBQAAAA==.',
Rh='Rheía:BAAANQAECgMIAgABNQAFFAgKGwAEAIYgAA==.Rhysi:BAAANQADCggIDgAAAA==.',
Ri='Riteofdeath:BAAANQADCgIIAgAAAA==.',
Ro='Rock:BAAANQAECgUIBQAAAA==.Rowenne:BAAANQAECgEIAQABNQAECgYIEwADAAAAAA==.',
Sa='Sahariel:BAABNQAECn8nAAIJAAkKtSEgLAC4AgAJAAkKtSEgLAC4AgAAAA==.Sarg:BAAANQAECgIIAgABNQAFFAUICwAPAMASAA==.Sauce:BAAANQADCgIJAwABNQAECgEIAQADAAAAAA==.',
Sc='Schwartpheil:BAABNQAECn8eAAIPAAgKhAxojADxAQAPAAgKhAxojADxAQAAAA==.Scrsaint:BAABNQAECn8ZAAMGAAkKsyCrJAAyAwAGAAkKsyCrJAAyAwAEAAEKKR9SYQBXAAAAAA==.',
Se='Seff:BAAANQAECgUIDwABNQAECgcIIQAFANAUAA==.Seumadruga:BAAANQADCgUIBQAAAA==.',
Sh='Shadowballz:BAAANQADCgMIAwAAAA==.Shardemma:BAAANQADCgUICAAAAA==.Shytningbolt:BAAANQADCggICAABNQAECgkJLAAKABghAA==.',
Si='Sintara:BAABNQAECn8kAAICAAgKfAx1DQB3AQACAAgKfAx1DQB3AQAAAA==.',
So='Sore:BAAANQAECgYICAAAAA==.',
Sq='Squigyçus:BAABNQAECn85AAMPAAkKhSRZCgCLAwAPAAkKhSRZCgCLAwAaAAEKwhLAEQBNAAABNQAFFAYIGgAKAKskAA==.',
St='Stolensouls:BAAANQADCgYICgAAAA==.Strawkun:BAAANQADCgYIBgAAAA==.',
['Sç']='Sçruffy:BAACNQAFFH8aAAIKAAYKqyQUAwBoAgAKAAYKqyQUAwBoAgA1AAQKfygABAoACgo2JfAIAHIDAAoACgo2JfAIAHIDAAwABwqDGmNnAHQBAA0AAwoAAAAAAAAAAAAA.',
Ta='Talren:BAAANQADCgYICAAAAA==.',
Te='Teldryn:BAABNQAECn8uAAIbAAoK8hz3MQD4AgAbAAoK8hz3MQD4AgAAAA==.',
Th='Thorendire:BAABNQAECn8rAAIcAAkKHwz9HAAPAQAcAAkKHwz9HAAPAQAAAA==.Thundoor:BAAANQAECgYIDwAAAA==.',
Ti='Tirnz:BAABNQAECn8fAAINAAkK3waaVQBXAQANAAkK3waaVQBXAQAAAA==.',
Tr='Treeoflife:BAABNQAECn8bAAIdAAYKugoERgAAAQAdAAYKugoERgAAAQAAAA==.Trilldt:BAAANQAECggIBQAAAA==.Trixielou:BAAANQAECgUIBQAAAA==.',
Tu='Tuskanir:BAAANQABCgIJAgAAAA==.',
Va='Vaelestrix:BAACNQAFFH8NAAMeAAYK3RcBBQDVAQAeAAUKYhgBBQDVAQAfAAMKTBbGEgC5AAA1AAQKfzoAAx4ACgqNJaMAAOMDAB4ACgqNJaMAAOMDAB8ACQruI+gEAIUDAAAA.Vaelora:BAAANQADCgcIEQAAAA==.Vaynn:BAAANQADCggIDgAAAA==.',
Vi='Violetara:BAAANQADCggICAAAAA==.',
Vo='Voiddøøde:BAAANQADCgQIBAAAAA==.Voidsocket:BAAANQADCggICAABNQAECgMIBQADAAAAAA==.',
Vu='Vulpvs:BAAANQADCgcIDwAAAA==.',
Vv='Vvlpvs:BAAANQADCgYIEAAAAA==.',
Wa='Warherald:BAABNQAECn8hAAIgAAcKJw+AGgCPAQAgAAcKJw+AGgCPAQAAAA==.',
We='Wednesday:BAACNQAFFH8WAAIKAAgKxxB/AwBaAgAKAAgKxxB/AwBaAgA1AAQKfyMAAgoACQqpIh4OAD8DAAoACQqpIh4OAD8DAAAA.',
Xa='Xandril:BAAANQAECgQIBAABNQAECgcIEgADAAAAAA==.',
Xi='Xirek:BAAANQAECgUIEAAAAA==.',
['Xì']='Xìlin:BAAANQABCgEIAQABNQAECgQIBgADAAAAAA==.',
Yr='Yreasak:BAABNQAECn8YAAMUAAcKBQ97nwCXAQAUAAcKBQ97nwCXAQAVAAIKYA0vZABcAAAAAA==.Yrisan:BAAANQADCgcIEgABNQAECgcIGAAUAAUPAA==.',
Ys='Yseulde:BAAANQADCgYIDAABNQAECgcIGAAUAAUPAA==.',
Za='Zapfren:BAAANQADCgEIAgABNQAECgoKIAAQAOgdAA==.Zarnok:BAAANQADCggIGQAAAA==.',
Ze='Zeratüle:BAAANQADCgcIBwAAAA==.',
Zo='Zosimos:BAAANQADCgcIBwAAAA==.',
Zu='Zurâ:BAABNQAECn8nAAIKAAgKfgQWMgCuAAAKAAgKfgQWMgCuAAAAAA==.',
['Çh']='Çhief:BAAANQAECgIIAgABNQAECgkJJQANAKgUAA==.',
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
