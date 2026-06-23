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

local lookup = {'Mage-Fire','Monk-Windwalker','Shaman-Restoration','Priest-Holy','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Unknown-Unknown','Shaman-Elemental','Warrior-Protection','Shaman-Enhancement','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Hunter-Survival','Druid-Guardian','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','Warlock-Affliction','Warlock-Demonology','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','Paladin-Protection','Druid-Feral','Warlock-Destruction','Monk-Mistweaver','Monk-Brewmaster','Evoker-Augmentation','Rogue-Subtlety',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=46,date='2026-06-21',data={Ab='Abanados:BAABLgAECn8XAAIBAAgJ+g33BQBiAQABAAgJ+g33BQBiAQAAAA==.',
Ad='Aday:BAAALgADCgEJAQAAAA==.',
Ae='Aethelra:BAAALgAECggJDAAAAA==.',
Ak='Akatsuki:BAABLgAECn84AAICAAkJYCSRBAAOAwACAAkJYCSRBAAOAwAAAA==.Aken:BAAALgAECgkJDQAAAA==.',
Al='Alight:BAAALgAECgcJDAABLgAECgkJIgADABYeAA==.Allera:BAAALgADCgEJAQAAAA==.Althea:BAABLgAECn8kAAIEAAgJNRG8KACrAQAEAAgJNRG8KACrAQAAAA==.',
Am='Ambition:BAAALgAECgEJAQABLgAFFAYJFgAFAMAVAA==.Amoredis:BAAALgADCggJDgAAAA==.',
An='Animorpha:BAAALgAECgYJCgAAAA==.',
Ar='Argath:BAAALgAECgEJAQABLgAECggJJgAGADMgAA==.Ariane:BAAALgAECgIJAgAAAA==.Arkaen:BAABLgAECn8mAAIGAAgJMyBLHADAAgAGAAgJMyBLHADAAgAAAA==.Arkhyn:BAAALgAECgUJCAAAAA==.',
As='Ashengor:BAAALgAECgMJBAAAAA==.Asonda:BAEBLgAECn8yAAMEAAkJtBgvGAAMAgAEAAgJIhgvGAAMAgAHAAkJGRCWHADpAQAAAA==.Assi:BAAALgADCgEJAQAAAA==.',
Az='Azshauyssa:BAAALgAECgcJEQAAAA==.',
Ba='Baelsk:BAAALgADCgYJBgABLgAECggJEQAIAAAAAA==.Bagofluff:BAAALgAECgQJBAABLgAFFAgJIwAJAGgXAA==.Bajamama:BAABLgAECn8lAAMJAAgJFxcKJgC6AQAJAAgJFxcKJgC6AQADAAYJ/g7zTABPAQAAAA==.Barkupatree:BAAALgADCgkJCQAAAA==.Batmanuel:BAAALgADCgEJAgAAAA==.Batou:BAAALgADCgEJAQAAAA==.',
Be='Beans:BAAALgADCgUJBQAAAA==.Bel:BAAALgAFFAIJAgABLgAECgkJRAAKAAAlAA==.Betarius:BAAALgAECgUJCwABLgAECgkJIgADABYeAA==.Betiff:BAABLgAECn8iAAMDAAkJFh4CHABsAgADAAgJHB0CHABsAgAJAAgJshSgPgA6AQAAAA==.',
Bi='Birddog:BAAALgAECgkJCQAAAA==.',
Bl='Blazeschill:BAAALgADCgEJAQABLgAECgkJOwALAO4YAA==.Blooded:BAABLgAECn8XAAIMAAkJgQ3gEABpAQAMAAkJgQ3gEABpAQAAAA==.Bloodydraco:BAABLgAECn81AAMNAAkJhhmLBwB+AgANAAkJhhmLBwB+AgAOAAEJpwWsKAArAAAAAA==.Bloodymagus:BAAALgADCgkJCQAAAA==.',
Bo='Bolden:BAAALgADCgkJHQAAAA==.',
Br='Brelm:BAAALgADCgQJBwAAAA==.Brewzin:BAAALgADCgQJBAAAAA==.Bruwu:BAAALgAECgcJCgAAAA==.',
Bu='Bubblez:BAAALgADCgQJBAAAAA==.',
Ca='Cakebro:BAABLgAECn86AAIPAAkJQiEoBADeAgAPAAkJQiEoBADeAgAAAA==.Camembert:BAABLgAECn8qAAIQAAkJ7yJ2AwDuAgAQAAkJ7yJ2AwDuAgAAAA==.Casii:BAABLgAECn8XAAIEAAkJohGJIwCmAQAEAAkJohGJIwCmAQAAAA==.',
Ce='Cele:BAAALgAECgMJBAAAAA==.Celyne:BAAALgAECgEJAQAAAA==.',
Ch='Chiizo:BAABLgAECn8UAAIHAAYJsRLWJwBXAQAHAAYJsRLWJwBXAQAAAA==.Chiror:BAAALgADCgYJCQAAAA==.Chubingus:BAACLgAFFH8GAAIRAAMJ3CAZeAATAQARAAMJ3CAZeAATAQAuAAQKfx4AAhEACQmAIOEhAIACABEACQmAIOEhAIACAAAA.Chuckmcstabb:BAAALgAECgEJAQAAAA==.Chufeng:BAABLgAECn8fAAISAAcJuyHuJgBFAgASAAcJuyHuJgBFAgABLgAFFAUJEwAFAIkiAA==.',
Co='Coggette:BAABLgAECn8XAAITAAYJxgR8/gD+AAATAAYJxgR8/gD+AAAAAA==.Corvica:BAAALgAECgEJAQAAAA==.',
Cr='Crizadin:BAAALgAECgMJAwAAAA==.Crizuid:BAAALgAECgUJCgABLgAECgcJGAASAEYjAA==.Crizunter:BAAALgADCgYJBgAAAA==.Crocubot:BAAALgAECgIJBQAAAA==.',
Cu='Cucuyknight:BAAALgADCgEJAgAAAA==.',
Da='Danaki:BAABLgAECn8dAAIUAAgJNBaXFQC/AQAUAAgJNBaXFQC/AQAAAA==.Dancookerton:BAAALgADCgUJBQAAAA==.Danorace:BAAALgAECgYJDgAAAA==.Darkcurve:BAAALgAECgkJDwAAAA==.Darkhope:BAAALgAECgkJDwAAAA==.Dashypants:BAAALgAECggJCAAAAA==.Dawnest:BAAALgADCgYJCQAAAA==.',
De='Deija:BAABLgAECn8dAAIVAAkJ+h1BIQBOAgAVAAkJ+h1BIQBOAgAAAA==.Dekoo:BAABLgAECn80AAIKAAgJoyNrBgClAgAKAAgJoyNrBgClAgAAAA==.Demon:BAAALgAECgcJEwAAAA==.Demoneyez:BAAALgAECgYJCQAAAA==.Deusene:BAABLgAECn8YAAIWAAYJHhCzLgBsAQAWAAYJHhCzLgBsAQAAAA==.',
Dr='Drakula:BAABLgAECn8eAAMXAAgJqgWcGAD+AAAXAAgJ8gOcGAD+AAAYAAgJowXKCABfAAAAAA==.Dreadfang:BAABLgAECn88AAIRAAkJcSPDFADLAgARAAkJcSPDFADLAgAAAA==.Droka:BAABLgAECn81AAIDAAkJESCuCAAmAwADAAkJESCuCAAmAwAAAA==.',
El='Elavil:BAAALgADCgYJEAAAAA==.Eldrynath:BAAALgAECgYJDQAAAA==.',
En='Endel:BAAALgADCgkJDQAAAA==.',
Eu='Eurotophobia:BAABLgAECn8gAAIGAAgJVRZKdwB/AQAGAAgJVRZKdwB/AQAAAA==.',
Ex='Exodia:BAABLgAECn8lAAMSAAkJHBlqNgAEAgASAAgJuRlqNgAEAgAPAAMJRw8dJACrAAAAAA==.',
Fa='Faldrithor:BAAALgAECgMJAwAAAA==.',
Fe='Fellaria:BAABLgAECn8oAAMZAAkJ4yPUAQD3AgAZAAkJ4yPUAQD3AgAVAAEJmA3vHQEsAAAAAA==.',
Fh='Fhyllo:BAABLgAECn8UAAMVAAkJERTCVgCDAQAVAAkJPhLCVgCDAQAZAAMJQhV9HACpAAAAAA==.',
Fl='Fluffybella:BAAALgAFFAIJBAAAAA==.',
Fo='Follaglas:BAACLgAFFH8FAAISAAMJNxKwXADrAAASAAMJNxKwXADrAAAuAAQKfyYAAhIACQn0JHQFADsDABIACQn0JHQFADsDAAAA.',
Ga='Gairen:BAABLgAECn8jAAMQAAgJXBpNDgD/AQAQAAgJXBpNDgD/AQAaAAQJ6wRkpwBkAAAAAA==.Galadisis:BAABLgAECn88AAMFAAkJqCFwCwCxAgAFAAkJqCFwCwCxAgAKAAIJ/BgEPQB+AAAAAA==.Galtidor:BAAALgAECgIJAgAAAA==.',
Gh='Ghuldana:BAABLgAECn82AAIYAAgJ6SEjFgCgAgAYAAgJ6SEjFgCgAgABLgAECggJHQAUADQWAA==.',
Gl='Glowgasm:BAAALgADCgMJAgAAAA==.',
Go='Goji:BAAALgADCgMJAwAAAA==.Goon:BAAALgAECgMJBAAAAA==.Goonann:BAAALgAECgkJEwAAAA==.',
Gr='Grimfoul:BAAALgADCgEJAQAAAA==.Gryari:BAABLgAECn8cAAIFAAgJVgu7PQBPAQAFAAgJVgu7PQBPAQAAAA==.',
Gu='Guiche:BAAALgAECgYJCQAAAA==.',
Gw='Gwiynevere:BAABLgAECn8fAAIRAAYJvwZY4ADUAAARAAYJvwZY4ADUAAAAAA==.',
He='Heathclif:BAAALgAECgUJCAABLgAFFAUJEwAFAIkiAA==.Hellao:BAABLgAECn9LAAIbAAkJ4B3OCQC4AgAbAAkJ4B3OCQC4AgAAAA==.Hellmage:BAAALgADCgcJEQAAAA==.Hermano:BAAALgADCgUJBQAAAA==.',
Ho='Holystones:BAAALgADCgIJAgAAAA==.Hoxpox:BAAALgAECgQJBAAAAA==.',
Hr='Hrimceald:BAAALgAECgkJDwAAAA==.',
Hy='Hylts:BAABLgAECn9JAAILAAkJnBgoAABrAgALAAkJnBgoAABrAgAAAA==.',
Id='Idpswhileafk:BAAALgADCgEJAQAAAA==.',
Il='Illithian:BAAALgAECggJEQAAAA==.',
Im='Imalockyo:BAAALgAECggJCgAAAA==.',
Ja='Javi:BAAALgADCgkJCQABLgAECgkJKAAZAOMjAA==.Javiolak:BAAALgAECgIJAwABLgAECgkJKAAZAOMjAA==.Javisham:BAAALgAECgEJAQABLgAECgkJKAAZAOMjAA==.',
Je='Jedus:BAAALgAECgEJAQABLgAECggJNAAKAKMjAA==.',
Ji='Jizzmon:BAAALgAECgEJAQAAAA==.',
Ju='Juansolo:BAAALgADCgEJAQAAAA==.',
Ka='Kaidirra:BAAALgADCgYJBgAAAA==.Kassiandra:BAABLgAECn81AAMGAAkJtBl8LQBLAgAGAAkJtBl8LQBLAgAcAAYJ5gciWQAXAQAAAA==.Katja:BAAALgAECgYJBwABLgAECgkJHQAVAPodAA==.',
Ke='Keeyla:BAAALgAECgEJAQAAAA==.Kejiabaobei:BAABLgAECn8qAAISAAkJkiWIAwBZAwASAAkJkiWIAwBZAwAAAA==.Kesta:BAAALgAECgQJBgAAAA==.Kevsterr:BAAALgAECgUJBQAAAA==.',
Kh='Khaantu:BAAALgADCgEJAQAAAA==.',
Ki='Kirin:BAAALgAECgEJAQABLgAECggJEQAIAAAAAA==.',
Ko='Koi:BAAALgAECgIJBQABLgADCgEJAQAIAAAAAA==.Korah:BAAALgADCgcJCwAAAA==.',
Kp='Kpöp:BAABLgAECn8mAAMVAAkJBiIXFwCMAgAVAAkJBiIXFwCMAgAdAAIJ2wrnaABBAAAAAA==.',
Kr='Krakens:BAEALgAECgUJBwABLgAECgkJMgAEALQYAA==.Krayel:BAAALgAECgIJAgAAAA==.Krîtz:BAAALgADCgcJBAAAAA==.Krünk:BAABLgAECn8zAAINAAkJIyDHAgAyAwANAAkJIyDHAgAyAwAAAA==.',
Kt='Kt:BAAALgAFFAEJAgAAAA==.',
Ku='Kumquat:BAAALgADCgEJAQAAAA==.Kuubai:BAAALgADCggJCAAAAA==.',
La='Lachdanan:BAABLgAECn8xAAIeAAkJOw4GFwBpAQAeAAkJOw4GFwBpAQAAAA==.Lament:BAABLgAECn8vAAIVAAgJTCIkFgCSAgAVAAgJTCIkFgCSAgAAAA==.Lans:BAAALgADCgEJAQAAAA==.',
Le='Leafbeard:BAAALgAECgYJBgAAAA==.',
Li='Lilean:BAABLgAECn8UAAISAAgJwh4nEwCeAgASAAgJwh4nEwCeAgAAAA==.',
Lo='Lokka:BAABLgAECn8nAAMLAAkJUhqzCgANAgALAAkJUhqzCgANAgADAAYJ+ht0SgCFAQAAAA==.Lolly:BAAALgAECgQJBAAAAA==.Loralin:BAAALgADCgcJDQAAAA==.',
Ly='Lyreshade:BAABLgAECn8nAAIJAAkJDxI6JQDnAQAJAAkJDxI6JQDnAQAAAA==.Lyreshaded:BAAALgAECgkJEQABLgAECgkJJwAJAA8SAA==.',
Ma='Maatdemon:BAAALgADCgcJCgABLgAECgkJOAACAGAkAA==.Madbunny:BAAALgADCgYJBwAAAA==.Madriina:BAAALgADCgcJEwAAAA==.Mahrah:BAABLgAECn8wAAIQAAkJyxK3FACwAQAQAAkJyxK3FACwAQAAAA==.Manashifter:BAAALgAECgYJDgAAAA==.Mar:BAAALgAECgUJBQAAAA==.Marija:BAABLgAECn8UAAQaAAgJGxyHHgBSAgAaAAcJXB2HHgBSAgAfAAUJHx57FwBYAQAQAAEJgw0vgQAgAAABLgAECgkJHQAVAPodAA==.',
Me='Melevolence:BAABLgAECn88AAMYAAkJkx12HQB0AgAYAAkJkx12HQB0AgAgAAMJ9wZjQQCvAAAAAA==.Mep:BAABLgAECn8XAAQHAAkJSxGDAwCgAAAHAAQJcQqDAwCgAAAWAAgJBwrLAwCWAAAEAAEJWAmcdgAjAAAAAA==.Meplastered:BAABLgAECn8VAAQCAAcJ/BI8UADFAAACAAUJ8hA8UADFAAAhAAcJ8AXscQDDAAAiAAIJfx3BWACmAAAAAA==.',
Mi='Mirithari:BAAALgADCgkJEQAAAA==.',
Mo='Molby:BAACLgAFFH8FAAMDAAMJsw4YbgBhAAADAAIJiAYYbgBhAAAJAAEJkQJ7YQArAAAuAAQKfxgAAgMACAnvETo+ALUBAAMACAnvETo+ALUBAAEuAAUUBQkFAAoALxIA.Monkehh:BAAALgAECgYJEgABLgAECggJEAAIAAAAAA==.Moolinda:BAABLgAECn8eAAIDAAgJNhfeNwDQAQADAAgJNhfeNwDQAQAAAA==.Moonglaive:BAAALgADCgMJAwABLgAECgcJDQAIAAAAAA==.Morticia:BAABLgAECn8bAAQUAAkJGRv3DwAMAgAUAAgJjBz3DwAMAgARAAYJkQuzvAACAQAMAAEJEgurPgApAAAAAA==.Motgul:BAAALgAECgUJBwABLgAECgkJFwAHAEsRAA==.',
My='Mythbras:BAABLgAECn8VAAITAAYJ0ARu8ADDAAATAAYJ0ARu8ADDAAAAAA==.Mythfurry:BAABLgAFFH8TAAMDAAUJiwZ1OwD1AAADAAUJiwZ1OwD1AAAJAAEJfgFHYwAjAAABLgAFFAYJIAAaAHkJAA==.',
Na='Nahwey:BAAALgAECgIJAgABLgAECggJHQAUADQWAA==.Nanon:BAAALgAECgQJBgAAAA==.Navdrag:BAAALgAECggJEwABLgAECgkJJgAVAAYiAA==.Naxria:BAABLgAECn8eAAMDAAgJOCCfDwDVAgADAAgJOCCfDwDVAgAJAAYJzh7bJQC7AQAAAA==.',
Ne='Nezanu:BAABLgAECn8kAAIfAAkJvCAKAwDsAgAfAAkJvCAKAwDsAgAAAA==.',
Ni='Nic:BAAALgADCgUJBQAAAA==.Niiko:BAAALgADCgEJAQAAAA==.Nili:BAAALgAECgIJAwAAAA==.Nimithriel:BAABLgAECn8lAAIWAAkJGBTAJACkAQAWAAkJGBTAJACkAQAAAA==.',
No='Notwesa:BAAALgAECgEJAQAAAA==.Notweso:BAABLgAECn81AAIVAAkJfSI9DADkAgAVAAkJfSI9DADkAgAAAA==.',
Oc='Oconostota:BAAALgAECgEJAQAAAA==.',
Ol='Oliverclutch:BAAALgADCgIJAgAAAA==.',
Or='Oriari:BAAALgAECgMJAwABLgAECgYJGwAhAGsVAA==.Oroki:BAAALgAECgYJCwAAAA==.',
Pa='Paarthurnax:BAAALgAECgYJBgAAAA==.Pallywack:BAAALgADCgcJBwAAAA==.Parizade:BAAALgAECgQJBgAAAA==.Pat:BAAALgAECgMJAwAAAA==.',
Pe='Pergi:BAAALgADCgkJDwABLgAFFAMJBQASADcSAA==.',
Pi='Pithikos:BAAALgAECgUJCQABLgAFFAUJEwAFAIkiAA==.',
Po='Pocketrapper:BAAALgAECgUJBQAAAA==.Poovey:BAACLgAFFH8WAAIFAAYJwBXfDgCOAQAFAAYJwBXfDgCOAQAuAAQKfyQAAgUACQmSHYodAAICAAUACQmSHYodAAICAAAA.',
Pu='Purpletoe:BAABLgAECn8aAAMEAAkJkhw+CwCyAgAEAAkJkhw+CwCyAgAWAAYJihKjOwAjAQAAAA==.',
Py='Pyronae:BAABLgAECn81AAIYAAkJ8xKIOQD0AQAYAAkJ8xKIOQD0AQAAAA==.',
Qi='Qit:BAAALgAECgEJAwABLgAECgcJDQAIAAAAAA==.',
Ra='Radrek:BAAALgADCggJCAABLgAFFAEJAQAIAAAAAA==.Rargh:BAABLgAECn8yAAISAAkJxhdmIwBWAgASAAkJxhdmIwBWAgAAAA==.Rawrparade:BAAALgADCgMJAwABLgAFFAcJHgAiADwTAA==.Raín:BAAALgAECgcJEQAAAA==.',
Re='Reddh:BAAALgAECgEJAQAAAA==.Redonkeylous:BAAALgAECgMJAwAAAA==.Relaina:BAAALgAECggJCAAAAA==.Rengen:BAABLgAECn8VAAMiAAkJeA5lKgBjAQAiAAgJNg5lKgBjAQACAAEJSBAznAAzAAAAAA==.Restobear:BAAALgAECgEJAgAAAA==.Reya:BAABLgAECn8vAAMRAAkJmh00IQCDAgARAAkJIBw0IQCDAgAUAAYJHhrRIQBEAQAAAA==.',
Ri='Rileymage:BAAALgAECgEJAgAAAA==.Rixadin:BAAALgADCgEJAQAAAA==.',
Ru='Runelord:BAABLgAECn8bAAMjAAcJKgrDTwDvAAAjAAcJKgrDTwDvAAANAAUJUAqsLQB9AAAAAA==.',
Sa='Saeli:BAABLgAECn8xAAIbAAkJthXnIADBAQAbAAkJthXnIADBAQAAAA==.Saeris:BAAALgAECgcJEwAAAA==.Sakagawea:BAAALgADCgMJAwAAAA==.Salazzle:BAAALgAECgEJAQAAAA==.Sanamongolos:BAAALgAECgIJAgAAAA==.Sasinko:BAABLgAECn81AAIXAAkJfyDfAgCYAgAXAAkJfyDfAgCYAgAAAA==.Sasqüatch:BAAALgADCgQJBAAAAA==.Satjin:BAAALgAECgYJEgAAAA==.Sawlrenuk:BAAALgADCgEJAQAAAA==.',
Sc='Scamander:BAACLgAFFH8HAAIjAAQJcB1SHwBmAQAjAAQJcB1SHwBmAQAuAAQKfxcAAiMABwnCHTAfAN8BACMABwnCHTAfAN8BAAAA.',
Se='Seldszar:BAACLgAFFH8OAAIkAAMJsQshKwDWAAAkAAMJsQshKwDWAAAuAAQKf08AAiQACQl/GuIKAHYCACQACQl/GuIKAHYCAAAA.Sentien:BAAALgAECgcJBAAAAA==.',
Sh='Shadowstripe:BAABLgAECn8/AAQCAAkJzhoqDACBAgACAAkJzhoqDACBAgAhAAMJ8QPyZQA6AAAiAAEJGAaIjAAsAAAAAA==.Shambamtymam:BAAALgADCgMJAwAAAA==.Shaylathia:BAAALgAECgMJAwAAAA==.Shigglez:BAACLgAFFH8OAAITAAUJ9RPHXwAhAQATAAUJ9RPHXwAhAQAuAAQKfzYAAhMACQk2I6INAAwDABMACQk2I6INAAwDAAAA.Shiitake:BAAALgAECgMJAwAAAA==.',
So='Socorro:BAAALgAECgEJAQAAAA==.Sonatina:BAACLgAFFH8pAAQHAAkJeCHvAwARAwAHAAgJiiHvAwARAwAEAAUJlyMJBgD9AQAWAAEJBCB6NwBVAAAuAAQKfyQAAwcACAmxJR0DAD4DAAcACAmxJR0DAD4DABYABwmwH0EhALwBAAAA.Soteria:BAAALgAECgYJCQABLgAFFAUJEwAFAIkiAA==.Soulfly:BAABLgAECn9RAAMCAAkJCBs+FQAQAgACAAkJCBs+FQAQAgAiAAgJMQqjAQDFAAAAAA==.',
St='Steamedhams:BAAALgAECgYJBgAAAA==.Streat:BAAALgADCgMJAwAAAA==.Streatlight:BAAALgADCgcJDQAAAA==.',
Su='Sugarpants:BAABLgAECn9eAAIhAAgJChtQAQCyAQAhAAgJChtQAQCyAQAAAA==.Sulfuric:BAAALgAECgEJAQAAAA==.Sumtongue:BAABLgAECn8bAAMhAAYJaxXVPQB4AQAhAAYJaxXVPQB4AQAiAAYJiRHROAAZAQAAAA==.',
Sy='Sylphrenä:BAABLgAECn8gAAMhAAgJ9x2RGQDvAQAhAAcJQB2RGQDvAQACAAYJ+xSDOQAbAQAAAA==.',
Ta='Tanglepriest:BAAALgAECgEJAQABLgAECgEJAgAIAAAAAA==.Tark:BAABLgAECn8YAAIGAAYJAha+lgBHAQAGAAYJAha+lgBHAQABLgAECgkJIAASADAeAA==.',
Te='Tembermental:BAAALgAECgUJBQABLgAECgkJOQAgAMQQAA==.Tembtree:BAABLgAECn8fAAMbAAkJFRQqJgCbAQAbAAkJFRQqJgCbAQAaAAEJoQKD9wAcAAABLgAECgkJOQAgAMQQAA==.Temlock:BAABLgAECn85AAMgAAkJxBD5CQCmAQAgAAkJxBD5CQCmAQAYAAMJ8AEY+wBkAAAAAA==.',
Th='Thistletea:BAAALgAECgEJAQABLgAECggJJwACAJwaAA==.Thrawnn:BAACLgAFFH8TAAIFAAUJiSJhDwCKAQAFAAUJiSJhDwCKAQAuAAQKfzAAAgUACQlvJXsFAAkDAAUACQlvJXsFAAkDAAAA.',
Tr='Trinia:BAAALgADCgEJAQAAAA==.Tryamarula:BAAALgAECgEJAQAAAA==.Trysomecider:BAAALgADCgIJAwAAAA==.',
Tu='Tuonetar:BAAALgAECgMJAwAAAA==.Turan:BAABLgAECn8gAAISAAkJMB66EgC8AgASAAkJMB66EgC8AgAAAA==.',
Ty='Tyrenari:BAAALgAECgUJCgAAAA==.',
Ul='Ultear:BAABLgAECn8bAAQZAAcJFhinFAALAQAVAAcJyg/MZQBwAQAZAAYJqBenFAALAQAdAAMJMxNtXABuAAAAAA==.',
Ve='Vetenarae:BAAALgADCgMJAwABLgAECgkJSQALAJwYAA==.',
Vo='Volkren:BAABLgAECn9CAAIUAAkJ2SDIBgCxAgAUAAkJ2SDIBgCxAgAAAA==.',
Wa='Warhunter:BAAALgAECgQJBAAAAA==.',
Xa='Xandor:BAAALgADCgYJBgABLgAECgkJDwAIAAAAAA==.Xaos:BAAALgAECgkJEAAAAA==.',
Xi='Xiaowugui:BAAALgADCgUJBQAAAA==.',
Xz='Xzaroth:BAAALgADCgcJBwAAAA==.',
Ya='Yarrick:BAABLgAECn88AAIDAAkJkx/iDADxAgADAAkJkx/iDADxAgAAAA==.',
Yo='Yonst:BAABLgAFFH8GAAIEAAMJxww6JgCOAAAEAAMJxww6JgCOAAAAAA==.',
Yu='Yumemi:BAAALgADCgcJAgAAAA==.',
Ze='Zelkiri:BAABLgAECn8XAAIbAAcJyAloRQD3AAAbAAcJyAloRQD3AAAAAA==.Zeref:BAAALgAECgQJBAABLgAECgkJOAACAGAkAA==.Zerotwoo:BAAALgAECgEJAQAAAA==.Zestama:BAAALgADCgUJBQABLgAFFAUJEwAFAIkiAA==.Zethlahr:BAABLgAECn82AAMWAAkJhh1QDgBxAgAWAAkJhh1QDgBxAgAEAAQJpA2tUgDtAAAAAA==.',
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
