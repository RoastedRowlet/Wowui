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

local lookup = {'Mage-Fire','Monk-Windwalker','Shaman-Restoration','Priest-Holy','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Unknown-Unknown','Shaman-Elemental','Warrior-Protection','Shaman-Enhancement','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Hunter-Survival','Druid-Guardian','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','DemonHunter-Vengeance','Warlock-Demonology','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','Paladin-Protection','Warlock-Destruction','Monk-Mistweaver','Monk-Brewmaster','Druid-Restoration','Druid-Feral','Warlock-Affliction','Evoker-Augmentation','Rogue-Subtlety',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Abanados:BAABLgAECn8VAAIBAAcJLw5ZBQBFAQABAAcJLw5ZBQBFAQAAAA==.',
Ae='Aethelra:BAAALgAECgYJBgAAAA==.',
Ak='Akatsuki:BAABLgAECn84AAICAAkJYCT/AgAeAwACAAkJYCT/AgAeAwAAAA==.Aken:BAAALgAECgQJAQAAAA==.',
Al='Alight:BAAALgAECgcJCgABLgAECgkJIQADADMdAA==.Allera:BAAALgADCgEJAQAAAA==.Althea:BAABLgAECn8kAAIEAAgJNRG8KACrAQAEAAgJNRG8KACrAQAAAA==.',
Am='Ambition:BAAALgAECgEJAQABLgAFFAUJEAAFAAQXAA==.Amoredis:BAAALgADCggJDgAAAA==.',
An='Animorpha:BAAALgAECgMJAwAAAA==.',
Ar='Ariane:BAAALgAECgIJAgAAAA==.Arkaen:BAABLgAECn8mAAIGAAgJMyBLHADAAgAGAAgJMyBLHADAAgAAAA==.Arkhyn:BAAALgAECgUJCAAAAA==.',
As='Ashengor:BAAALgAECgMJBAAAAA==.Asonda:BAEBLgAECn8oAAMEAAgJYRbJHgCsAQAEAAcJphbJHgCsAQAHAAgJFQ5qIACfAQAAAA==.Assi:BAAALgADCgEJAQAAAA==.',
Az='Azshauyssa:BAAALgAECgcJEQAAAA==.',
Ba='Baelsk:BAAALgADCgYJBgABLgAECgYJCAAIAAAAAA==.Bajamama:BAABLgAECn8lAAMJAAgJFxdFHgDGAQAJAAgJFxdFHgDGAQADAAYJ/g7zTABPAQAAAA==.Barkupatree:BAAALgADCgkJCQAAAA==.Batou:BAAALgADCgEJAQAAAA==.',
Be='Beans:BAAALgADCgUJBQAAAA==.Bel:BAAALgAFFAEJAQABLgAECgkJOwAKAAckAA==.Betarius:BAAALgAECgUJCQABLgAECgkJIQADADMdAA==.Betiff:BAABLgAECn8hAAMDAAkJMx1yGABcAgADAAgJHBxyGABcAgAJAAgJshSaMwBCAQAAAA==.',
Bi='Birddog:BAAALgAECgkJCQAAAA==.',
Bl='Blazeschill:BAAALgADCgEJAQABLgAECgkJOwALAO4YAA==.Blooded:BAABLgAECn8XAAIMAAkJgQ03DABxAQAMAAkJgQ03DABxAQAAAA==.Bloodydraco:BAABLgAECn81AAMNAAkJhhk7BgCEAgANAAkJhhk7BgCEAgAOAAEJpwXOIgAuAAAAAA==.Bloodymagus:BAAALgADCgkJCQAAAA==.',
Bo='Bolden:BAAALgADCgkJHQAAAA==.',
Br='Brelm:BAAALgADCgQJBwAAAA==.Brewzin:BAAALgADCgQJBAAAAA==.Bruwu:BAAALgAECgYJCQAAAA==.',
Bu='Bubblez:BAAALgADCgQJBAAAAA==.',
Ca='Cakebro:BAABLgAECn86AAIPAAkJQiFEBwCTAgAPAAkJQiFEBwCTAgAAAA==.Camembert:BAABLgAECn8qAAIQAAkJ7yJbAgD2AgAQAAkJ7yJbAgD2AgAAAA==.Casii:BAAALgAECggJEQAAAA==.',
Ce='Cele:BAAALgAECgMJBAAAAA==.Celyne:BAAALgAECgEJAQAAAA==.',
Ch='Chiizo:BAABLgAECn8UAAIHAAYJsRLWJwBXAQAHAAYJsRLWJwBXAQAAAA==.Chiror:BAAALgADCgYJCQAAAA==.Chubingus:BAABLgAECn8eAAIRAAkJgCDsGQCMAgARAAkJgCDsGQCMAgAAAA==.Chuckmcstabb:BAAALgAECgEJAQAAAA==.Chufeng:BAABLgAECn8UAAISAAcJTh5ULQD+AQASAAcJTh5ULQD+AQABLgAFFAQJCwAFAO0gAA==.',
Co='Coggette:BAABLgAECn8XAAITAAYJxgR8/gD+AAATAAYJxgR8/gD+AAAAAA==.Corvica:BAAALgADCgEJAQAAAA==.',
Cr='Crizadin:BAAALgAECgMJAwAAAA==.Crizuid:BAAALgAECgUJCQABLgAECgcJFwASAEYjAA==.Crocubot:BAAALgAECgIJBQAAAA==.',
Cu='Cucuyknight:BAAALgADCgEJAgAAAA==.',
Da='Danaki:BAABLgAECn8UAAIUAAgJ9xNwFQCVAQAUAAgJ9xNwFQCVAQAAAA==.Dancookerton:BAAALgADCgUJBQAAAA==.Danorace:BAAALgAECgQJBwAAAA==.Darkcurve:BAAALgAECgkJDwAAAA==.Darkhope:BAAALgAECgkJDwAAAA==.',
De='Deija:BAABLgAECn8bAAIVAAgJfx5pKgADAgAVAAgJfx5pKgADAgAAAA==.Dekoo:BAABLgAECn8yAAIKAAcJmiNsCABSAgAKAAcJmiNsCABSAgAAAA==.Demon:BAAALgAECgcJEwAAAA==.Demoneyez:BAAALgAECgYJCQAAAA==.Deusene:BAABLgAECn8YAAIWAAYJHhCzLgBsAQAWAAYJHhCzLgBsAQAAAA==.',
Dr='Drakula:BAAALgAECgcJDwAAAA==.Dreadfang:BAABLgAECn88AAIRAAkJcSO+DgDaAgARAAkJcSO+DgDaAgAAAA==.Droka:BAABLgAECn8zAAIDAAgJsx8RDQDJAgADAAgJsx8RDQDJAgAAAA==.',
El='Elavil:BAAALgADCgYJEAAAAA==.Eldrynath:BAAALgAECgYJCAAAAA==.',
En='Endel:BAAALgADCgcJCwAAAA==.',
Eu='Eurotophobia:BAABLgAECn8bAAIGAAcJbxVUbgBzAQAGAAcJbxVUbgBzAQAAAA==.',
Ex='Exodia:BAABLgAECn8gAAMSAAgJEhkVQAC4AQASAAcJyRkVQAC4AQAPAAMJRw8dJACrAAAAAA==.',
Fa='Faldrithor:BAAALgAECgMJAwAAAA==.',
Fe='Fellaria:BAABLgAECn8oAAMXAAkJ4yPUAQD3AgAXAAkJ4yPUAQD3AgAVAAEJmA2U9gArAAAAAA==.',
Fh='Fhyllo:BAAALgAECggJEwAAAA==.',
Fl='Fluffybella:BAAALgAFFAIJBAAAAA==.',
Fo='Follaglas:BAABLgAECn8mAAISAAkJ9CTLAgBOAwASAAkJ9CTLAgBOAwAAAA==.',
Ga='Gairen:BAABLgAECn8VAAIQAAgJgBmACwD0AQAQAAgJgBmACwD0AQAAAA==.Galadisis:BAABLgAECn88AAMFAAkJqCGvBwDGAgAFAAkJqCGvBwDGAgAKAAIJ/BgsMwCJAAAAAA==.Galtidor:BAAALgAECgIJAgAAAA==.',
Gh='Ghuldana:BAABLgAECn8lAAIYAAgJuiBxHABiAgAYAAgJuiBxHABiAgABLgAECggJFAAUAPcTAA==.',
Gl='Glowgasm:BAAALgADCgMJAgAAAA==.',
Go='Goji:BAAALgADCgMJAwAAAA==.Goon:BAAALgAECgMJBAAAAA==.Goonann:BAAALgAECgkJEwAAAA==.',
Gr='Grimfoul:BAAALgADCgEJAQAAAA==.Gryari:BAAALgAECggJEwAAAA==.',
Gu='Guiche:BAAALgAECgYJCQAAAA==.',
Gw='Gwiynevere:BAABLgAECn8cAAIRAAYJZAZpwgDTAAARAAYJZAZpwgDTAAAAAA==.',
He='Heathclif:BAAALgADCgUJCgABLgAFFAQJCwAFAO0gAA==.Hellao:BAABLgAECn88AAIZAAkJGRuVCwB4AgAZAAkJGRuVCwB4AgAAAA==.Hellmage:BAAALgADCgcJEQAAAA==.Hermano:BAAALgADCgUJBQAAAA==.',
Ho='Holystones:BAAALgADCgIJAgAAAA==.Hoxpox:BAAALgAECgQJBAAAAA==.',
Hr='Hrimceald:BAAALgAECgkJDwAAAA==.',
Hy='Hylts:BAABLgAECn8nAAILAAcJXhRqEAB0AQALAAcJXhRqEAB0AQAAAA==.',
Id='Idpswhileafk:BAAALgADCgEJAQAAAA==.',
Il='Illithian:BAAALgAECgYJCwAAAA==.',
Im='Imalockyo:BAAALgAECggJCgAAAA==.',
Ja='Javi:BAAALgADCgkJCQABLgAECgkJKAAXAOMjAA==.',
Je='Jedus:BAAALgAECgEJAQABLgAECgcJMgAKAJojAA==.',
Ji='Jizzmon:BAAALgAECgEJAQAAAA==.',
Ka='Kaidirra:BAAALgADCgYJBgAAAA==.Kassiandra:BAABLgAECn8zAAMGAAgJ6BgeOQAAAgAGAAgJ6BgeOQAAAgAaAAYJ5gciWQAXAQAAAA==.Katja:BAAALgAECgYJBwABLgAECggJGwAVAH8eAA==.',
Ke='Keeyla:BAAALgAECgEJAQAAAA==.Kejiabaobei:BAABLgAECn8qAAISAAkJkiWIAwBZAwASAAkJkiWIAwBZAwAAAA==.Kesta:BAAALgAECgQJBgAAAA==.Kevsterr:BAAALgAECgUJBQAAAA==.',
Kh='Khaantu:BAAALgADCgEJAQAAAA==.',
Ki='Kirin:BAAALgADCgYJCQABLgAECgYJCAAIAAAAAA==.',
Ko='Koi:BAAALgAECgIJBQABLgADCgEJAQAIAAAAAA==.Korah:BAAALgADCgcJCwAAAA==.',
Kp='Kpöp:BAABLgAECn8mAAMVAAkJBiJfEgCUAgAVAAkJBiJfEgCUAgAbAAIJ2wrnaABBAAAAAA==.',
Kr='Krakens:BAEALgAECgUJBwABLgAECggJKAAEAGEWAA==.Krayel:BAAALgAECgIJAgAAAA==.Krîtz:BAAALgADCgcJBAAAAA==.Krünk:BAABLgAECn8zAAINAAkJIyA+AgA4AwANAAkJIyA+AgA4AwAAAA==.',
Kt='Kt:BAAALgAFFAEJAgAAAA==.',
Ku='Kumquat:BAAALgADCgEJAQAAAA==.Kuubai:BAAALgADCggJCAAAAA==.',
La='Lachdanan:BAABLgAECn8kAAIcAAgJTw6CFwA4AQAcAAgJTw6CFwA4AQAAAA==.Lament:BAABLgAECn8nAAIVAAgJTCJmEgCUAgAVAAgJTCJmEgCUAgAAAA==.Lans:BAAALgADCgEJAQAAAA==.',
Le='Leafbeard:BAAALgAECgYJBgAAAA==.',
Li='Lilean:BAABLgAECn8UAAISAAgJwh4nEwCeAgASAAgJwh4nEwCeAgAAAA==.',
Lo='Lokka:BAABLgAECn8fAAMLAAgJTBk1DQCrAQALAAgJTBk1DQCrAQADAAYJgRVSYAAHAQAAAA==.Lolly:BAAALgAECgQJBAAAAA==.Loralin:BAAALgADCgcJDQAAAA==.',
Ly='Lyreshade:BAABLgAECn8nAAIJAAkJDxI6JQDnAQAJAAkJDxI6JQDnAQAAAA==.Lyreshaded:BAAALgAECgkJEAABLgAECgkJJwAJAA8SAA==.',
Ma='Maatdemon:BAAALgADCgcJCgABLgAECgkJOAACAGAkAA==.Madbunny:BAAALgADCgUJBwAAAA==.Madriina:BAAALgADCgcJEwAAAA==.Mahrah:BAABLgAECn8oAAIQAAgJoBP2EwB/AQAQAAgJoBP2EwB/AQAAAA==.Manashifter:BAAALgAECgYJDgAAAA==.Mar:BAAALgADCgcJBwAAAA==.Marija:BAAALgAECgYJCwABLgAECggJGwAVAH8eAA==.',
Me='Melevolence:BAABLgAECn88AAMYAAkJkx1XFwCDAgAYAAkJkx1XFwCDAgAdAAMJ9wZjQQCvAAAAAA==.Mep:BAAALgAECgcJDQAAAA==.Meplastered:BAABLgAECn8UAAQCAAcJ4hDUQgDLAAACAAUJ8hDUQgDLAAAeAAcJ8AXwVADFAAAfAAEJWRqAcQBMAAAAAA==.',
Mi='Mirithari:BAAALgADCgkJCQAAAA==.',
Mo='Molby:BAABLgAECn8YAAIDAAgJ7xGXMwC4AQADAAgJ7xGXMwC4AQABLgAFFAMJBAAIAAAAAA==.Monkehh:BAAALgAECgUJCgABLgAECggJDgAIAAAAAA==.Moolinda:BAABLgAECn8eAAIDAAgJNhfgLQDUAQADAAgJNhfgLQDUAQAAAA==.Morticia:BAABLgAECn8bAAQUAAkJGRv3DwAMAgAUAAgJjBz3DwAMAgARAAYJkQvKoAAHAQAMAAEJEgthLAAvAAAAAA==.Motgul:BAAALgAECgUJBwABLgAECgcJDQAIAAAAAA==.',
My='Mythbras:BAAALgAECgYJDQAAAA==.Mythfurry:BAABLgAFFH8IAAIDAAQJ1gF5PADBAAADAAQJ1gF5PADBAAABLgAFFAUJGwAgAFsKAA==.',
Na='Nahwey:BAAALgAECgIJAgABLgAECggJFAAUAPcTAA==.Nanon:BAAALgAECgQJBgAAAA==.Naxria:BAABLgAECn8VAAMDAAgJCSApDADTAgADAAgJCSApDADTAgAJAAUJnBuQPwAJAQAAAA==.',
Ne='Nezanu:BAABLgAECn8iAAIhAAgJQyDSBACIAgAhAAgJQyDSBACIAgAAAA==.',
Ni='Nic:BAAALgADCgUJBQAAAA==.Niiko:BAAALgADCgEJAQAAAA==.Nimithriel:BAABLgAECn8lAAIWAAkJGBT8HAC5AQAWAAkJGBT8HAC5AQAAAA==.',
No='Notwesa:BAAALgAECgEJAQAAAA==.Notweso:BAABLgAECn8uAAIVAAkJHyIGDQDEAgAVAAkJHyIGDQDEAgAAAA==.',
Oc='Oconostota:BAAALgAECgEJAQAAAA==.',
Ol='Oliverclutch:BAAALgADCgIJAgAAAA==.',
Or='Oriari:BAAALgADCgQJBAABLgAECgYJFQAeAIESAA==.Oroki:BAAALgAECgUJBQAAAA==.',
Pa='Paarthurnax:BAAALgAECgYJBgAAAA==.Pallywack:BAAALgADCgcJBwAAAA==.Parizade:BAAALgAECgMJAwAAAA==.Pat:BAAALgAECgMJAwAAAA==.',
Pe='Pergi:BAAALgADCgkJDwABLgAECgkJJgASAPQkAA==.',
Pi='Pithikos:BAAALgAECgUJCQABLgAFFAQJCwAFAO0gAA==.',
Po='Pocketrapper:BAAALgAECgUJBQAAAA==.Poovey:BAACLgAFFH8QAAIFAAUJBBdUFQA7AQAFAAUJBBdUFQA7AQAuAAQKfyQAAgUACQmSHb4WABYCAAUACQmSHb4WABYCAAAA.',
Pu='Purpletoe:BAABLgAECn8ZAAMEAAkJkhx4CADBAgAEAAkJkhx4CADBAgAWAAYJihKLMgAqAQAAAA==.',
Py='Pyronae:BAABLgAECn8zAAIYAAgJKBTFPwDIAQAYAAgJKBTFPwDIAQAAAA==.',
Qi='Qit:BAAALgAECgEJAQABLgAECgcJDAAIAAAAAA==.',
Ra='Radrek:BAAALgADCggJCAAAAA==.Rargh:BAABLgAECn8pAAISAAkJuRJbPADFAQASAAkJuRJbPADFAQAAAA==.Raín:BAAALgAECgcJBwAAAA==.',
Re='Reddh:BAAALgADCgQJBAAAAA==.Redonkeylous:BAAALgAECgMJAwAAAA==.Relaina:BAAALgAECgIJAgAAAA==.Rengen:BAABLgAECn8UAAMfAAgJ6A5FLwArAQAfAAcJrQ5FLwArAQACAAEJSBDzfwA1AAAAAA==.Restobear:BAAALgAECgEJAQAAAA==.Reya:BAABLgAECn8iAAMRAAgJmx7zNwAAAgARAAgJ6xzzNwAAAgAUAAYJHhqgGwBQAQAAAA==.',
Ri='Rixadin:BAAALgADCgEJAQAAAA==.',
Ru='Runelord:BAAALgAECgcJEgAAAA==.',
Sa='Saeli:BAABLgAECn8xAAIZAAkJthVPGgDOAQAZAAkJthVPGgDOAQAAAA==.Saeris:BAAALgAECgcJDgAAAA==.Sakagawea:BAAALgADCgMJAwAAAA==.Sanamongolos:BAAALgAECgIJAgAAAA==.Sasinko:BAABLgAECn8zAAIiAAgJGR6bBAAfAgAiAAgJGR6bBAAfAgAAAA==.Sasqüatch:BAAALgADCgQJBAAAAA==.Satjin:BAAALgAECgYJEgAAAA==.Sawlrenuk:BAAALgADCgEJAQAAAA==.',
Sc='Scamander:BAABLgAECn8WAAIjAAcJmRxcHQDNAQAjAAcJmRxcHQDNAQAAAA==.',
Se='Sentien:BAAALgAECgcJBAAAAA==.',
Sh='Shadowstripe:BAABLgAECn8pAAQCAAgJLhUEGQDCAQACAAgJLhUEGQDCAQAeAAMJ8QPyZQA6AAAfAAEJGAaIjAAsAAAAAA==.Shambamtymam:BAAALgADCgMJAwAAAA==.Shaylathia:BAAALgAECgMJAwAAAA==.Shigglez:BAACLgAFFH8GAAITAAMJrRC9aQDmAAATAAMJrRC9aQDmAAAuAAQKfzMAAhMACAmWIt0bAJsCABMACAmWIt0bAJsCAAAA.Shiitake:BAAALgAECgMJAwAAAA==.',
So='Sonatina:BAACLgAFFH8dAAQHAAgJjSFkAQAwAgAHAAgJ0R1kAQAwAgAEAAQJPSTWBgCmAQAWAAEJBCCkKQBfAAAuAAQKfyQAAwcACAmxJR0DAD4DAAcACAmxJR0DAD4DABYABwmwH3sbAMQBAAAA.Soteria:BAAALgAECgYJCQABLgAFFAQJCwAFAO0gAA==.Soulfly:BAABLgAECn9CAAMCAAkJ2Rn9EgACAgACAAkJ2Rn9EgACAgAfAAgJdwdBNQAOAQAAAA==.',
St='Steamedhams:BAAALgAECgYJBgAAAA==.Streat:BAAALgADCgMJAwAAAA==.Streatlight:BAAALgADCgcJDQAAAA==.',
Su='Sugarpants:BAABLgAECn8/AAIeAAgJ6BhdFgAuAgAeAAgJ6BhdFgAuAgAAAA==.Sulfuric:BAAALgAECgEJAQAAAA==.Sumtongue:BAABLgAECn8VAAMeAAYJgRL5NgBIAQAeAAYJgRL5NgBIAQAfAAYJWg/zOAD9AAAAAA==.',
Sy='Sylphrenä:BAABLgAECn8gAAMeAAgJ9x2RGQDvAQAeAAcJQB2RGQDvAQACAAYJ+xRlMAAgAQAAAA==.',
Ta='Tark:BAAALgAECgYJEwABLgAECgcJFwASAKIcAA==.',
Te='Tembtree:BAABLgAECn8aAAMZAAcJzRHRLQA+AQAZAAcJzRHRLQA+AQAgAAEJoQLl3gAcAAABLgAECggJMgAdAHERAA==.Temlock:BAABLgAECn8yAAMdAAgJcRGmCgBrAQAdAAgJcRGmCgBrAQAYAAMJ8AEY+wBkAAAAAA==.',
Th='Thrawnn:BAACLgAFFH8LAAIFAAQJ7SCOCgB8AQAFAAQJ7SCOCgB8AQAuAAQKfy8AAgUACQlRJcMDABMDAAUACQlRJcMDABMDAAAA.',
Tr='Trinia:BAAALgADCgEJAQAAAA==.Tryamarula:BAAALgADCgEJAQAAAA==.Trysomecider:BAAALgADCgIJAwAAAA==.',
Tu='Tuonetar:BAAALgAECgMJAwAAAA==.Turan:BAABLgAECn8XAAISAAcJohyYLQD9AQASAAcJohyYLQD9AQAAAA==.',
Ty='Tyrenari:BAAALgAECgQJCQAAAA==.',
Ul='Ultear:BAABLgAECn8YAAQXAAYJHRhPEQAOAQAVAAYJDg/MZQBwAQAXAAYJqBdPEQAOAQAbAAIJ/xBtXABuAAAAAA==.',
Ve='Velkyn:BAACLgAFFH8JAAIkAAMJTwt7IQDZAAAkAAMJTwt7IQDZAAAuAAQKf0IAAiQACQmjGU0JAG4CACQACQmjGU0JAG4CAAAA.Vetenarae:BAAALgADCgMJAwABLgAECgcJJwALAF4UAA==.',
Vo='Volkren:BAABLgAECn87AAIUAAkJLCBeBQC1AgAUAAkJLCBeBQC1AgAAAA==.',
Wa='Warhunter:BAAALgAECgQJBAAAAA==.',
Xa='Xandor:BAAALgADCgYJBgABLgAECgkJDwAIAAAAAA==.Xaos:BAAALgAECgkJEAAAAA==.',
Xi='Xiaowugui:BAAALgADCgUJBQAAAA==.',
Xz='Xzaroth:BAAALgADCgcJBwAAAA==.',
Ya='Yarrick:BAABLgAECn88AAIDAAkJkx8tCQD6AgADAAkJkx8tCQD6AgAAAA==.',
Yo='Yonst:BAABLgAFFH8GAAIEAAMJxwwmGwC1AAAEAAMJxwwmGwC1AAAAAA==.',
Yu='Yumemi:BAAALgADCgcJAgAAAA==.',
Ze='Zelkiri:BAAALgAECgcJEQAAAA==.Zeref:BAAALgAECgQJBAABLgAECgkJOAACAGAkAA==.Zerotwoo:BAAALgAECgEJAQAAAA==.Zethlahr:BAABLgAECn82AAMWAAkJhh3oCgCBAgAWAAkJhh3oCgCBAgAEAAQJpA2tUgDtAAAAAA==.',
Zo='Zoros:BAAALgAECgYJCgAAAA==.',
Zy='Zytheri:BAAALgADCgEJAQAAAA==.',
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
