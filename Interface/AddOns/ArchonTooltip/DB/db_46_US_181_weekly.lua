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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Retribution','Warrior-Fury','Unknown-Unknown','Monk-Windwalker','Monk-Brewmaster','Warlock-Demonology','Hunter-BeastMastery','DeathKnight-Frost','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection','Warlock-Affliction','Shaman-Elemental','Rogue-Subtlety','Shaman-Restoration','Priest-Holy','Hunter-Survival','Warrior-Arms','Evoker-Preservation','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Blood','Druid-Guardian',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abert:BAAALgADCgUJBQAAAA==.Abilify:BAAALgAECgEJAgAAAA==.',
Ad='Adalinda:BAAALgADCgEJAQABLgAFFAQJEAABADEaAA==.',
Ag='Agnor:BAABLgAECn81AAICAAgJVxrrMwALAgACAAgJVxrrMwALAgAAAA==.',
Al='Alatir:BAAALgADCgcJEQAAAA==.Alticus:BAAALgADCgEJAQAAAA==.',
An='Andrew:BAAALgAECgEJAQABLgAFFAUJBQADAP0NAA==.Anien:BAAALgAECgYJEQAAAA==.Anklemauler:BAAALgAECgYJBgAAAA==.Antibubble:BAABLgAECn8gAAICAAkJYB7vGgCDAgACAAkJYB7vGgCDAgAAAA==.Antipeta:BAAALgAECgEJAgAAAA==.Anwal:BAACLgAFFH8QAAIBAAQJMRoGGgAeAQABAAQJMRoGGgAeAQAuAAQKfy0AAwEACQlXHLsiAAkCAAEACAlIG7siAAkCAAQACQlCDBFdAJgBAAAA.',
Ar='Argus:BAABLgAECn8kAAIFAAgJwCFwCQCrAgAFAAgJwCFwCQCrAgAAAA==.Arithana:BAAALgAFFAQJBAAAAA==.Arithfury:BAAALgAECgIJAgABLgAFFAQJBAAGAAAAAA==.Arithkick:BAACLgAFFH8FAAMHAAMJagx2HADBAAAHAAMJ6wp2HADBAAAIAAEJ+AtvTgA8AAAuAAQKfyAAAggACAnkF28UAGsCAAgACAnkF28UAGsCAAEuAAUUBAkEAAYAAAAA.',
As='Asayo:BAAALgAECgUJEgAAAA==.Asherie:BAAALgAECgQJBQABLgAECggJEQAGAAAAAA==.Aske:BAABLgAECn8cAAIJAAYJkBWfcwA9AQAJAAYJkBWfcwA9AQAAAA==.Astolan:BAAALgAECgEJAQAAAA==.',
At='Atonga:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgcJEQAAAA==.',
Az='Azuresun:BAAALgAECggJDwAAAA==.',
Ba='Ballak:BAABLgAECn8ZAAIKAAcJzRGWVABrAQAKAAcJzRGWVABrAQAAAA==.Barlee:BAAALgADCgEJAQABLgAFFAIJAQAGAAAAAA==.',
Be='Beatin:BAAALgAECgQJBgAAAA==.Belenzr:BAAALgADCgEJAQAAAA==.',
Bi='Bigdikley:BAAALgAECgYJEQAAAA==.Biggtater:BAAALgADCgUJBQAAAA==.Biscüits:BAAALgADCgUJBQAAAA==.',
Bl='Bloopydoo:BAAALgAECgYJDgAAAA==.Blort:BAAALgADCgEJAQAAAA==.Bláckbird:BAABLgAECn8bAAIKAAkJMhoyQgCwAQAKAAkJMhoyQgCwAQAAAA==.',
Bo='Bohliang:BAAALgADCgkJEAAAAA==.Boltywolty:BAAALgAECgYJCgAAAA==.Borim:BAAALgAECgEJAQAAAA==.',
Br='Brandymae:BAAALgADCgUJCwAAAA==.Branholy:BAAALgADCgEJAQAAAA==.Brbpoopin:BAAALgAECgEJAQAAAA==.Brotems:BAAALgAECgkJAQAAAA==.Bruwdflight:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebuster:BAAALgAECgYJDAABLgAECgkJIAACAGAeAA==.Bumwarrior:BAAALgADCgEJAQAAAA==.Burnphase:BAAALgADCgQJBwAAAA==.',
By='Byrdreisyl:BAAALgAECgQJBAAAAA==.',
Ca='Caosgonewild:BAAALgAECgMJAwAAAA==.',
Ch='Chestie:BAABLgAECn8hAAMCAAkJdR0bQADhAQACAAgJ6x0bQADhAQALAAIJOBpEHQCVAAAAAA==.Chubbychi:BAAALgAECgIJAgAAAA==.',
Ci='Cindy:BAABLgAECn8jAAMKAAkJDh78DgCxAgAKAAkJDh78DgCxAgAMAAEJ3gWdkQApAAAAAA==.Cindyx:BAAALgAECgUJCwABLgAECgkJIwAKAA4eAA==.',
Co='Coast:BAABLgAECn8VAAINAAgJ1wdeEwDoAAANAAgJ1wdeEwDoAAAAAA==.Coldlock:BAAALgAECggJCAABLgAECgkJMAAOAAUaAA==.Coldsore:BAABLgAECn8wAAQOAAkJBRrbBwAuAgAOAAkJ4RnbBwAuAgABAAYJ+wbMSQDrAAAEAAMJMQff/gCKAAAAAA==.Coldwar:BAAALgADCgcJBwAAAA==.Conjuremoney:BAAALgADCgEJAQAAAA==.Cootpal:BAABLgAECn8+AAIEAAkJDB4eEgC8AgAEAAkJDB4eEgC8AgAAAA==.Costcohotdog:BAAALgADCgMJAwAAAA==.',
Cr='Crazyloon:BAAALgAECgQJBAAAAA==.Croe:BAAALgADCgMJAwAAAA==.',
Cy='Cynawyne:BAAALgAECgEJAQAAAA==.Cynthea:BAAALgAECgkJCgAAAA==.',
Da='Dahm:BAAALgAECgMJBgAAAA==.Dalasaurs:BAABLgAECn8wAAIFAAgJkxijKAAaAgAFAAgJkxijKAAaAgAAAA==.Dalasnipus:BAAALgADCgMJAwAAAA==.Dalbear:BAAALgADCgYJCQAAAA==.Darkpallas:BAAALgAECgYJBwAAAA==.Darkprophetc:BAABLgAECn8kAAIPAAkJ8AdZcAB9AQAPAAkJ8AdZcAB9AQAAAA==.',
De='Deathfyre:BAAALgADCgQJBAAAAA==.Deluun:BAAALgADCgkJCQAAAA==.Demious:BAAALgAECggJEwAAAA==.Demiurge:BAEALgAECgkJEAAAAA==.Demonfister:BAACLgAFFH8GAAIFAAMJKAwVKwDLAAAFAAMJKAwVKwDLAAAuAAQKfyAAAgUACQkSGjYcAGsCAAUACQkSGjYcAGsCAAAA.Demonkiller:BAAALgAECgUJDAAAAA==.Denastiest:BAABLgAECn8jAAIDAAcJcA5ZZwAxAQADAAcJcA5ZZwAxAQAAAA==.Denji:BAAALgAECggJEAAAAA==.Devvmonk:BAAALgAECgYJCQAAAA==.',
Di='Dindaratwo:BAAALgAECgEJAQAAAA==.',
Do='Doe:BAABLgAECn8pAAMQAAcJmyNhBABSAgAQAAcJmyNhBABSAgARAAMJhhD+UgCdAAAAAA==.Dokta:BAAALgAECgYJEAAAAA==.',
Dr='Draflex:BAAALgAECgMJBAAAAA==.Drathal:BAABLgAECn8gAAIEAAgJZQIa3gC5AAAEAAgJZQIa3gC5AAAAAA==.Drippydraws:BAAALgADCgIJAgAAAA==.Drjay:BAAALgADCgkJCwAAAA==.',
Dv='Dvergar:BAAALgAECgYJDAAAAA==.',
Ea='Eatshrooms:BAAALgADCgEJAQAAAA==.',
Ed='Edd:BAAALgAECgQJBAAAAA==.Eddiedean:BAAALgAECgQJBgAAAA==.',
El='Elfgonewild:BAAALgAECgMJBwAAAA==.Ellessra:BAABLgAECn8cAAIPAAcJYQIw1wDGAAAPAAcJYQIw1wDGAAAAAA==.Elnegrouno:BAABLgAECn8fAAISAAcJfR/SCgBjAgASAAcJfR/SCgBjAgAAAA==.Eloper:BAAALgAECgEJAQAAAA==.',
Em='Emotank:BAAALgADCgYJBgAAAA==.',
Er='Eragone:BAAALgAECgMJAwAAAA==.',
Et='Etoro:BAAALgADCgEJAgAAAA==.',
Ev='Evissier:BAACLgAFFH8MAAITAAQJ2xmrAQBqAQATAAQJ2xmrAQBqAQAuAAQKfx0AAhMACAmuIAcBAAIDABMACAmuIAcBAAIDAAAA.',
Ex='Exsequor:BAACLgAFFH8KAAIOAAIJ4R1yCQCuAAAOAAIJ4R1yCQCuAAAuAAQKfx0AAw4ABgkLI7gPAJsBAA4ABgkLI7gPAJsBAAQAAQlyB/tQASsAAAEuAAUUAwkIAAgAJAoA.',
Ez='Ezuras:BAAALgADCgIJAgAAAA==.',
Fa='Faeyri:BAABLgAECn8jAAIUAAcJcxk5HwC8AQAUAAcJcxk5HwC8AQAAAA==.Fassandin:BAAALgAECgIJAgAAAA==.',
Fe='Felli:BAAALgAECgEJAQAAAA==.',
Fi='Fishermon:BAAALgAECgUJCAAAAA==.',
Fl='Flagfarmer:BAABLgAECn8XAAIBAAYJGiYGDgCNAgABAAYJGiYGDgCNAgAAAA==.Flataxe:BAAALgAECgMJAwAAAA==.Flixunt:BAAALgADCgEJAQAAAA==.',
Fo='Foidepas:BAAALgAECgcJDQAAAA==.Fourid:BAAALgAECgQJBgAAAA==.Foxannee:BAAALgAECgMJBgAAAA==.',
Fr='Freezyweezy:BAACLgAFFH8LAAIPAAQJ4RsBMwBeAQAPAAQJ4RsBMwBeAQAuAAQKfx8AAg8ACQnoI4YWALcCAA8ACQnoI4YWALcCAAAA.Frostfirer:BAAALgAECgYJAgAAAA==.',
Fu='Fudgeyenuh:BAAALgAECgkJCQAAAA==.',
Fy='Fyrewar:BAAALgAECgMJAwAAAA==.',
Ga='Gallyn:BAABLgAFFH8HAAIVAAMJmhvnGwAAAQAVAAMJmhvnGwAAAQAAAA==.Gamm:BAAALgADCgcJEQAAAA==.',
Ge='Gerel:BAAALgAECgYJBgAAAA==.',
Gi='Ginyu:BAAALgAECgEJAQAAAA==.',
Gl='Glacierrock:BAAALgADCgQJCgAAAA==.Gloria:BAABLgAECn8aAAIWAAgJYgmNTABJAQAWAAgJYgmNTABJAQAAAA==.',
Go='Gooblicious:BAAALgAECgEJAQAAAA==.Gori:BAAALgAECgIJAgAAAA==.',
Gr='Grail:BAAALgAECgcJEwAAAA==.Grelvisse:BAAALgAECgMJBQAAAA==.Grippywippy:BAAALgADCgYJBAAAAA==.',
Gu='Gudren:BAAALgADCgEJAQAAAA==.Guimon:BAAALgAECgMJBAAAAA==.Gunslinger:BAAALgAECgEJAQAAAA==.',
Gw='Gwenie:BAABLgAECn8UAAIJAAYJ6wxkkAAFAQAJAAYJ6wxkkAAFAQAAAA==.',
Ha='Halenicion:BAAALgAFFAEJAQAAAA==.Hauntfrost:BAAALgAECgEJAQAAAA==.Hazél:BAAALgADCgYJBgAAAA==.',
He='Helix:BAAALgAECgIJAgAAAA==.',
Hi='Hippoltyos:BAABLgAECn8qAAIXAAgJqA9jJAB9AQAXAAgJqA9jJAB9AQAAAA==.',
Ho='Honestlee:BAAALgAECgQJBAAAAA==.Honourablee:BAAALgAECgYJCQAAAA==.Hortzul:BAAALgADCgMJAwABLgAFFAQJEAABADEaAA==.Hotsaucce:BAAALgADCgEJAQAAAA==.Houe:BAAALgADCgUJCAAAAA==.',
Hu='Huntardiness:BAABLgAECn8bAAMYAAgJ/Q7uIAB1AQAKAAYJ3RFLUAB4AQAYAAgJnQnuIAB1AQAAAA==.Hunterd:BAAALgADCgEJAQAAAA==.',
Hy='Hymnals:BAACLgAFFH8HAAIFAAQJ4CRxBQCxAQAFAAQJ4CRxBQCxAQAuAAQKfxcAAwUACAlRJO4OANwCAAUACAlRJO4OANwCABkAAgkHGpVCAIYAAAAA.',
Ia='Ianmaris:BAAALgADCgQJBQAAAA==.',
Ic='Icelandite:BAAALgAECgUJBQAAAA==.',
Iv='Ive:BAABLgAECn8fAAQNAAkJ/CF2EQDBAQANAAcJzBp2EQDBAQAJAAgJGCL2TgCXAQATAAIJHBD0JABeAAAAAA==.',
Ja='Jackburton:BAAALgAECgIJAgAAAA==.Jaddie:BAAALgAECgYJDwAAAA==.Jarnunvosk:BAABLgAECn8cAAIaAAcJBBKNEQCMAQAaAAcJBBKNEQCMAQAAAA==.Jasmindinn:BAAALgADCgcJDgAAAA==.Jayber:BAABLgAECn8iAAMbAAcJSg4mKQBaAQAbAAcJSg4mKQBaAQAcAAEJmQD4fwAHAAAAAA==.',
Je='Jezadora:BAAALgADCgEJAQAAAA==.',
Jo='Jolkom:BAAALgAECgMJBgABLgAECggJEgAGAAAAAA==.',
Ka='Kadri:BAAALgAFFAEJAQAAAA==.Kaffee:BAABLgAECn8pAAIOAAgJVgx0GQAiAQAOAAgJVgx0GQAiAQAAAA==.Kamakaz:BAAALgAECgYJCAAAAA==.Kamasdruid:BAAALgAECgMJBQAAAA==.Kamasmage:BAAALgADCgcJBwAAAA==.Kamasmonk:BAAALgAECgYJBwAAAA==.Kamasux:BAAALgADCgYJBwAAAA==.Kandi:BAAALgADCgQJCgAAAA==.Kaywhy:BAABLgAECn8UAAIcAAgJVxsNLwA7AQAcAAgJVxsNLwA7AQAAAA==.',
Ki='Kichack:BAABLgAECn8jAAMHAAcJfh8qEQAXAgAHAAcJfh8qEQAXAgAdAAYJDxThMQBeAQAAAA==.Kitarvie:BAAALgAECgEJAgAAAA==.',
Kj='Kjdh:BAABLgAECn8kAAIRAAgJYSEbCACAAgARAAgJYSEbCACAAgAAAA==.',
Kl='Kladuum:BAAALgADCgYJGQAAAA==.',
Kn='Knuckles:BAAALgAECgcJCwAAAA==.',
Ko='Kogun:BAAALgAECgQJBAAAAA==.Kowala:BAAALgAECgcJEwAAAA==.Kowpox:BAAALgADCgkJCgAAAA==.Kozalth:BAAALgADCgEJAgAAAA==.',
Kr='Krabi:BAAALgADCgYJCwAAAA==.Kranks:BAAALgAECgEJAQAAAA==.Krelo:BAABLgAECn8dAAIWAAcJcRseHgAvAgAWAAcJcRseHgAvAgAAAA==.',
Kt='Ktom:BAABLgAECn8qAAIUAAkJjyRLAwAcAwAUAAkJjyRLAwAcAwAAAA==.',
Ku='Kurimbory:BAAALgAECgUJBQAAAA==.',
Ky='Kyruan:BAAALgADCgEJAQAAAA==.',
['Ký']='Kýlê:BAABLgAECn8ZAAMKAAgJmwdIUgByAQAKAAgJmwdIUgByAQAMAAYJ6gLLWQDdAAAAAA==.',
La='Lancelot:BAAALgAECgEJAQAAAA==.Lanthuil:BAAALgAECgQJBAAAAA==.',
Li='Lifepooll:BAAALgAECgEJAQABLgAFFAIJAQAGAAAAAA==.Lilyselah:BAAALgADCgYJBwAAAA==.Littlelocky:BAAALgADCgcJEwAAAA==.Liv:BAABLgAECn8UAAIcAAgJtQu6LgBsAQAcAAgJtQu6LgBsAQAAAA==.',
Ll='Llamallab:BAAALgADCgcJBwAAAA==.',
Lo='Lostmyghoul:BAABLgAECn8hAAICAAkJAB3GIABjAgACAAkJAB3GIABjAgAAAA==.Lostwarrior:BAAALgAECgUJBQAAAA==.Louhi:BAAALgAECgEJAQABLgAECgMJCAAGAAAAAA==.',
Lu='Luglug:BAAALgAECgEJAQAAAA==.Lunar:BAABLgAECn8aAAIeAAkJSRvJCQCSAgAeAAkJSRvJCQCSAgAAAA==.Lunasea:BAAALgAECgMJAwAAAA==.',
Ly='Lysol:BAAALgADCgUJBQAAAA==.Lystat:BAAALgAECgUJCwAAAA==.',
Ma='Magicfungus:BAAALgADCgUJCQAAAA==.Magno:BAAALgADCgIJAgAAAA==.Magra:BAAALgAECgYJEwAAAA==.Magêyalook:BAABLgAECn8nAAIPAAgJthmlMwAsAgAPAAgJthmlMwAsAgAAAA==.Manzz:BAAALgAECgUJCgAAAA==.Marcelline:BAAALgADCgYJEgAAAA==.Mattob:BAAALgADCgcJDAAAAA==.Maximus:BAAALgADCgkJEAAAAA==.Maznificent:BAAALgADCggJCAAAAA==.Mazyme:BAAALgADCgQJCAAAAA==.',
Me='Meandmypal:BAACLgAFFH8TAAIYAAcJeR34AAAoAgAYAAcJeR34AAAoAgAuAAQKfy0AAhgACAkiJrsAAH4DABgACAkiJrsAAH4DAAAA.Mello:BAABLgAECn8mAAIZAAkJdxv5BACcAgAZAAkJdxv5BACcAgAAAA==.Mesteris:BAAALgADCgYJBgAAAA==.',
Mi='Midiane:BAAALgADCgMJAwAAAA==.Milim:BAAALgAECgIJAwAAAA==.Mirba:BAABLgAECn8jAAIKAAcJChMZUACEAQAKAAcJChMZUACEAQAAAA==.',
Mo='Mongo:BAABLgAECn8nAAICAAkJOB0MHwBsAgACAAkJOB0MHwBsAgAAAA==.Monsterdeath:BAAALgAECgIJAgAAAA==.Moreicepls:BAABLgAECn8aAAIPAAgJ+wmHkAA7AQAPAAgJ+wmHkAA7AQAAAA==.Morené:BAAALgAECgQJBgAAAA==.Moxxee:BAAALgADCgcJGAAAAA==.',
Mu='Mushhmelu:BAAALgAECgEJAQAAAA==.',
My='Myiko:BAAALgAECgQJBAAAAA==.Mytharu:BAAALgADCgMJAwAAAA==.',
Na='Nareík:BAABLgAECn8fAAIDAAgJYg9oVQCjAQADAAgJYg9oVQCjAQAAAA==.',
Ne='Neutrallee:BAAALgAECgEJAQAAAA==.Newa:BAAALgAECgUJCQAAAA==.',
Ni='Nightwater:BAACLgAFFH8IAAIfAAMJeQk2NwC2AAAfAAMJeQk2NwC2AAAuAAQKfykABB8ACQmLFxEhAB0CAB8ACQmLFxEhAB0CACAAAglfCRswAF8AAB4AAQmKCAp7ACwAAAAA.',
['Né']='Nébulien:BAABLgAECn8dAAIhAAgJNx7hBwAaAgAhAAgJNx7hBwAaAgAAAA==.',
Ok='Okkok:BAABLgAECn8XAAIPAAYJ8hCIwABjAQAPAAYJ8hCIwABjAQAAAA==.',
Or='Orchop:BAAALgAECgYJEQAAAA==.Orkrist:BAABLgAECn8XAAIKAAcJpRI3VQB1AQAKAAcJpRI3VQB1AQAAAA==.',
Oz='Oz:BAAALgADCgUJBQAAAA==.',
Pa='Paado:BAAALgADCgUJBQAAAA==.Pantryraider:BAAALgAECgkJAgAAAA==.Patriqt:BAAALgAECgEJAQAAAA==.Paulterian:BAAALgAECgUJBQAAAA==.Paymeforpi:BAAALgAECgMJAwAAAA==.',
Ph='Phelaeshio:BAABLgAECn8eAAICAAkJOxyiHQB0AgACAAkJOxyiHQB0AgAAAA==.',
Po='Poam:BAAALgAECgUJBQAAAA==.Poldalina:BAAALgADCgcJFwAAAA==.Power:BAAALgAECgcJEwAAAA==.',
Pr='Primevil:BAAALgADCgQJBAAAAA==.Prosthetic:BAAALgAECgEJAQAAAA==.',
Pu='Pumplord:BAAALgAECgcJEQAAAA==.Punchyou:BAAALgADCgEJAQAAAA==.',
['På']='Pårts:BAAALgAFFAIJAQAAAA==.',
['Pù']='Pùff:BAAALgAECgUJCQAAAA==.',
Qu='Quazeemoto:BAAALgAECgEJAQAAAA==.',
Ra='Raeyna:BAAALgAECgIJAwABLgAECgkJHwANAPwhAA==.Raffern:BAAALgAECgMJAwAAAA==.Rainknuckles:BAABLgAECn8lAAIBAAgJVRbtHwDdAQABAAgJVRbtHwDdAQAAAA==.Rayshano:BAABLgAECn8VAAIOAAcJ8xjQEACKAQAOAAcJ8xjQEACKAQAAAA==.',
Re='Resia:BAAALgADCgQJAQAAAA==.Revocsid:BAAALgADCgcJEwAAAA==.Rezza:BAAALgADCgEJAQAAAA==.',
Ri='Rikka:BAAALgADCgMJAwAAAA==.',
Ro='Rottingtree:BAAALgAECgYJDAAAAA==.',
Ru='Rustynails:BAABLgAECn8vAAIiAAkJoSPKAAACAwAiAAkJoSPKAAACAwAAAA==.',
Sa='Saffire:BAAALgADCgcJBwAAAA==.Salina:BAAALgADCgIJAgAAAA==.Saly:BAAALgADCgIJAQABLgADCggJDgAGAAAAAA==.Samwitch:BAAALgAECgMJBAAAAA==.Sappaho:BAAALgADCgYJBwAAAA==.Satheirel:BAAALgADCgYJBwAAAA==.Savanti:BAAALgAECgEJAQAAAA==.Sazzul:BAAALgAECgYJCQAAAA==.',
Sc='Scott:BAACLgAFFH8VAAISAAQJvCM+AwBiAQASAAQJvCM+AwBiAQAuAAQKfyMAAhIACAmXJNQDABMDABIACAmXJNQDABMDAAAA.Screamor:BAAALgAECgEJAQAAAA==.Screams:BAAALgADCgEJAQAAAA==.Screamz:BAABLgAECn8eAAIRAAYJ6RjEHQBQAQARAAYJ6RjEHQBQAQAAAA==.Scynx:BAAALgAECggJDwAAAA==.',
Se='Seaka:BAABLgAECn8nAAMeAAkJ3RZDEQAoAgAeAAkJ3RZDEQAoAgAfAAcJYRaLOACSAQAAAA==.Sebas:BAAALgAECgEJAQAAAA==.Sent:BAAALgADCggJDgAAAA==.Serion:BAAALgAECgQJBQABLgAFFAEJAQAGAAAAAA==.Sernix:BAABLgAECn8VAAIWAAgJwBb1HwAiAgAWAAgJwBb1HwAiAgAAAA==.',
Sh='Shadegrim:BAAALgAECgQJBgAAAA==.Shadowloons:BAAALgAECgEJAQAAAA==.Shaeia:BAACLgAFFH8IAAIUAAMJzxCEEQDcAAAUAAMJzxCEEQDcAAAuAAQKfx8AAhQACQn0HLcNAMYCABQACQn0HLcNAMYCAAAA.Shangi:BAAALgADCgMJAgABLgAFFAMJCAAIACQKAA==.Shekinah:BAAALgADCgEJAQAAAA==.Shen:BAAALgAECgQJBgAAAA==.',
Si='Siatrath:BAAALgAECgEJAQABLgAFFAMJCAAIACQKAA==.Sivtekeda:BAAALgAECgQJCQAAAA==.',
Sk='Sktibrew:BAACLgAFFH8TAAIIAAYJgSF1BACRAQAIAAYJgSF1BACRAQAuAAQKfxoAAggACAmDHRMRAI8CAAgACAmDHRMRAI8CAAAA.',
Sl='Slamin:BAAALgADCggJDwAAAA==.Slash:BAABLgAECn8kAAIRAAkJxRc6DwD+AQARAAkJxRc6DwD+AQAAAA==.Slyavane:BAABLgAECn84AAQTAAkJqBVnBAAjAgATAAkJqBVnBAAjAgANAAcJawcWFgDRAAAJAAQJWwQE4QCYAAAAAA==.Slyice:BAAALgAECgEJBgAAAA==.',
Sm='Smokess:BAACLgAFFH8IAAIEAAMJDxQiFgD7AAAEAAMJDxQiFgD7AAAuAAQKfxkAAw4ACAkhHqYKAPMBAAQACAlAGZZKAAMCAA4ACAkHGqYKAPMBAAEuAAUUBQkHABIA+woA.',
Sn='Snowwind:BAABLgAECn8VAAIXAAYJMAu6NgD/AAAXAAYJMAu6NgD/AAAAAA==.',
So='Solthea:BAAALgAECgkJBwAAAA==.Solymar:BAAALgAECgkJBwAAAA==.Sonar:BAABLgAECn8pAAIKAAkJ8h9BEQCeAgAKAAkJ8h9BEQCeAgAAAA==.Sonasai:BAAALgADCgcJGAAAAA==.Sonnybear:BAAALgADCgUJEQAAAA==.Soulhatcher:BAAALgAECgQJEAAAAA==.Soxs:BAABLgAECn8qAAMdAAkJNBpoDACfAgAdAAkJNBpoDACfAgAHAAIJTg9oXwBpAAAAAA==.',
Sp='Spookymoo:BAAALgADCgQJBAAAAA==.',
St='Stabbywabby:BAAALgAECgYJBwAAAA==.Stardris:BAABLgAECn8aAAIDAAgJOQKIqAC/AAADAAgJOQKIqAC/AAAAAA==.Stompygnome:BAAALgAECgYJCgAAAA==.Strooth:BAAALgADCgQJBAAAAA==.',
Ta='Talavel:BAAALgADCgIJAgAAAA==.Tartanus:BAABLgAECn8tAAIDAAkJXxdhJQAaAgADAAkJXxdhJQAaAgAAAA==.Taulogit:BAAALgAECgIJAgAAAA==.Tayzetv:BAAALgAECgMJAwABLgAECgcJHQAhAMUfAA==.',
Te='Teramiah:BAAALgADCgcJFAAAAA==.',
Th='Theadona:BAABLgAECn8VAAIEAAgJkxcmQQDkAQAEAAgJkxcmQQDkAQAAAA==.Thorall:BAAALgADCgkJDwAAAA==.',
Ti='Tikcus:BAAALgADCgcJEAAAAA==.Tils:BAAALgADCggJDwAAAA==.Tippy:BAACLgAFFH8RAAMLAAQJdBwMBgBMAQALAAQJdBwMBgBMAQAjAAEJuQEhMwAlAAAuAAQKfzYABAsACQloIegBAMoCAAsACQkQIegBAMoCAAIAAwkNBskDAXAAACMAAgl1DiE+AGYAAAAA.',
To='Toastedwings:BAAALgADCgcJDwAAAA==.Tombstone:BAAALgAECgYJEgAAAA==.Toowongfoo:BAACLgAFFH8VAAIHAAUJ0x4rCABmAQAHAAUJ0x4rCABmAQAuAAQKfyUAAgcACAmHJCoGAMsCAAcACAmHJCoGAMsCAAAA.',
Tr='Trewer:BAAALgADCgIJAgAAAA==.Trisara:BAABLgAECn81AAIeAAkJrwi6KwBIAQAeAAkJrwi6KwBIAQAAAA==.',
Ty='Tygrana:BAAALgAECgEJAQAAAA==.Tyradora:BAAALgAECgEJAQAAAA==.Tytannia:BAAALgADCgEJAQAAAA==.',
['Tö']='Töteman:BAABLgAECn8kAAIUAAcJ2xVbJgCKAQAUAAcJ2xVbJgCKAQAAAA==.',
['Tÿ']='Tÿtann:BAAALgAECgMJAwAAAA==.',
Um='Umbranecros:BAAALgAECgEJBQAAAA==.',
Un='Underdog:BAABLgAECn8bAAIMAAgJqROsDABwAQAMAAgJqROsDABwAQAAAA==.',
Va='Vaern:BAABLgAECn8dAAIgAAcJhBx/CgDjAQAgAAcJhBx/CgDjAQAAAA==.Vagindivin:BAAALgAECgUJCQAAAA==.Valrie:BAAALgAECgMJAwAAAA==.Valyteil:BAAALgAECgQJBAAAAA==.',
Ve='Venngance:BAABLgAECn8jAAQLAAcJiCSwBAA8AgALAAcJNSCwBAA8AgAjAAUJTSTVFwCdAQACAAYJExQvlAAYAQAAAA==.',
Vi='Virus:BAAALgAECgUJCAAAAA==.Vitner:BAAALgADCgMJAwAAAA==.',
Vo='Voidkity:BAAALgAECgQJBwAAAA==.Voidpriest:BAAALgAECgEJAQAAAA==.',
Vy='Vyrlet:BAAALgAECgEJAQAAAA==.',
Wa='Warfield:BAABLgAECn8dAAMkAAgJZRM0EwCDAQAkAAgJZRM0EwCDAQAgAAEJWgP2RwAfAAAAAA==.',
Wf='Wfbot:BAAALgAECgEJAQAAAA==.',
Wi='Winafred:BAAALgAECgEJAQAAAA==.',
Wk='Wkeyonly:BAABLgAECn8fAAIDAAkJYRXdTgB2AQADAAkJYRXdTgB2AQAAAA==.',
Wo='Woody:BAAALgADCgUJBQAAAA==.Wooter:BAAALgADCgYJDAAAAA==.Worthy:BAAALgAECgkJAwAAAA==.',
Wr='Wrathsome:BAABLgAECn8jAAIfAAcJFBToMwCpAQAfAAcJFBToMwCpAQAAAA==.',
Wu='Wunderbilly:BAAALgADCgEJAQAAAA==.',
['Wí']='Wísp:BAAALgAECgEJAQAAAA==.',
Xl='Xloon:BAAALgAECgEJAQAAAA==.',
Xy='Xypherus:BAAALgADCgkJDQAAAA==.',
['Xá']='Xándarl:BAAALgAECgMJBAAAAA==.',
Ya='Yaldabaoth:BAEALgAECgcJBQABLgAECgkJEAAGAAAAAA==.Yanza:BAAALgAECgIJAgAAAA==.',
Za='Zaio:BAAALgAECgMJAwAAAA==.Zarkus:BAAALgAECgQJEAAAAA==.',
Ze='Zelphi:BAAALgAECgQJCAAAAA==.Zenha:BAAALgADCgEJAQAAAA==.Zephaadella:BAAALgAECgEJAQAAAA==.',
Zh='Zhuzi:BAAALgADCgkJDwAAAA==.',
Zs='Zshmokez:BAACLgAFFH8HAAISAAUJ+wqlEwDgAAASAAUJ+wqlEwDgAAAuAAQKfxoAAhIACQlFHpAEAL0CABIACQlFHpAEAL0CAAAA.',
['Åy']='Åylå:BAAALgAECgEJAQAAAA==.',
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
