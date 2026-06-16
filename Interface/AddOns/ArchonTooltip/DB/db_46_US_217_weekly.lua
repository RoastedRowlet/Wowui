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
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=46,date='2026-06-14',data={Ab='Abanados:BAABLgAECn8XAAIBAAgJ+g3aBQBiAQABAAgJ+g3aBQBiAQAAAA==.',
Ad='Aday:BAAALgADCgEJAQAAAA==.',
Ae='Aethelra:BAAALgAECggJCwAAAA==.',
Ak='Akatsuki:BAABLgAECn84AAICAAkJYCR1BAAPAwACAAkJYCR1BAAPAwAAAA==.Aken:BAAALgAECgQJBAAAAA==.',
Al='Alight:BAAALgAECgcJDAABLgAECgkJIgADABYeAA==.Allera:BAAALgADCgEJAQAAAA==.Althea:BAABLgAECn8kAAIEAAgJNRG8KACrAQAEAAgJNRG8KACrAQAAAA==.',
Am='Ambition:BAAALgAECgEJAQABLgAFFAYJFgAFAMAVAA==.Amoredis:BAAALgADCggJDgAAAA==.',
An='Animorpha:BAAALgAECgYJCgAAAA==.',
Ar='Argath:BAAALgAECgEJAQABLgAECggJJgAGADMgAA==.Ariane:BAAALgAECgIJAgAAAA==.Arkaen:BAABLgAECn8mAAIGAAgJMyBLHADAAgAGAAgJMyBLHADAAgAAAA==.Arkhyn:BAAALgAECgUJCAAAAA==.',
As='Ashengor:BAAALgAECgMJBAAAAA==.Asonda:BAEBLgAECn8yAAMEAAkJtBjiFwAMAgAEAAgJIhjiFwAMAgAHAAkJGRDZGwDuAQAAAA==.Assi:BAAALgADCgEJAQAAAA==.',
Az='Azshauyssa:BAAALgAECgcJEQAAAA==.',
Ba='Baelsk:BAAALgADCgYJBgABLgAECggJEQAIAAAAAA==.Bagofluff:BAAALgAECgQJBAABLgAFFAgJIwAJAGgXAA==.Bajamama:BAABLgAECn8lAAMJAAgJFxd1JQC7AQAJAAgJFxd1JQC7AQADAAYJ/g7zTABPAQAAAA==.Barkupatree:BAAALgADCgkJCQAAAA==.Batmanuel:BAAALgADCgEJAQAAAA==.Batou:BAAALgADCgEJAQAAAA==.',
Be='Beans:BAAALgADCgUJBQAAAA==.Bel:BAAALgAFFAIJAgABLgAECgkJPQAKAAAlAA==.Betarius:BAAALgAECgUJCwABLgAECgkJIgADABYeAA==.Betiff:BAABLgAECn8iAAMDAAkJFh6oGwBsAgADAAgJHB2oGwBsAgAJAAgJshTIPQA7AQAAAA==.',
Bi='Birddog:BAAALgAECgkJCQAAAA==.',
Bl='Blazeschill:BAAALgADCgEJAQABLgAECgkJOwALAO4YAA==.Blooded:BAABLgAECn8XAAIMAAkJgQ1TEABuAQAMAAkJgQ1TEABuAQAAAA==.Bloodydraco:BAABLgAECn81AAMNAAkJhhl1BwB+AgANAAkJhhl1BwB+AgAOAAEJpwUwKAArAAAAAA==.Bloodymagus:BAAALgADCgkJCQAAAA==.',
Bo='Bolden:BAAALgADCgkJHQAAAA==.',
Br='Brelm:BAAALgADCgQJBwAAAA==.Brewzin:BAAALgADCgQJBAAAAA==.Bruwu:BAAALgAECgcJCgAAAA==.',
Bu='Bubblez:BAAALgADCgQJBAAAAA==.',
Ca='Cakebro:BAABLgAECn86AAIPAAkJQiEoBADeAgAPAAkJQiEoBADeAgAAAA==.Camembert:BAABLgAECn8qAAIQAAkJ7yJhAwDvAgAQAAkJ7yJhAwDvAgAAAA==.Casii:BAABLgAECn8XAAIEAAkJohEzIwCmAQAEAAkJohEzIwCmAQAAAA==.',
Ce='Cele:BAAALgAECgMJBAAAAA==.Celyne:BAAALgAECgEJAQAAAA==.',
Ch='Chiizo:BAABLgAECn8UAAIHAAYJsRLWJwBXAQAHAAYJsRLWJwBXAQAAAA==.Chiror:BAAALgADCgYJCQAAAA==.Chubingus:BAACLgAFFH8GAAIRAAMJ3CAvdAAVAQARAAMJ3CAvdAAVAQAuAAQKfx4AAhEACQmAIHkhAIACABEACQmAIHkhAIACAAAA.Chuckmcstabb:BAAALgAECgEJAQAAAA==.Chufeng:BAABLgAECn8fAAISAAcJuyE1JgBGAgASAAcJuyE1JgBGAgABLgAFFAUJEwAFAIkiAA==.',
Co='Coggette:BAABLgAECn8XAAITAAYJxgR8/gD+AAATAAYJxgR8/gD+AAAAAA==.Corvica:BAAALgADCgEJAQAAAA==.',
Cr='Crizadin:BAAALgAECgMJAwAAAA==.Crizuid:BAAALgAECgUJCQABLgAECgcJFwASAEYjAA==.Crizunter:BAAALgADCgYJBgAAAA==.Crocubot:BAAALgAECgIJBQAAAA==.',
Cu='Cucuyknight:BAAALgADCgEJAgAAAA==.',
Da='Danaki:BAABLgAECn8dAAIUAAgJNBY+FQDBAQAUAAgJNBY+FQDBAQAAAA==.Dancookerton:BAAALgADCgUJBQAAAA==.Danorace:BAAALgAECgYJDAAAAA==.Darkcurve:BAAALgAECgkJDwAAAA==.Darkhope:BAAALgAECgkJDwAAAA==.Dawnest:BAAALgADCgQJBAAAAA==.',
De='Deija:BAABLgAECn8dAAIVAAkJ+h3mIABNAgAVAAkJ+h3mIABNAgAAAA==.Dekoo:BAABLgAECn80AAIKAAgJoyNSBgCmAgAKAAgJoyNSBgCmAgAAAA==.Demon:BAAALgAECgcJEwAAAA==.Demoneyez:BAAALgAECgYJCQAAAA==.Deusene:BAABLgAECn8YAAIWAAYJHhCzLgBsAQAWAAYJHhCzLgBsAQAAAA==.',
Dr='Drakula:BAABLgAECn8aAAMXAAgJJQU4GAD/AAAXAAgJ8gM4GAD/AAAYAAcJyQT5twDZAAAAAA==.Dreadfang:BAABLgAECn88AAIRAAkJcSNpFADLAgARAAkJcSNpFADLAgAAAA==.Droka:BAABLgAECn81AAIDAAkJESB9CAAnAwADAAkJESB9CAAnAwAAAA==.',
El='Elavil:BAAALgADCgYJEAAAAA==.Eldrynath:BAAALgAECgYJDQAAAA==.',
En='Endel:BAAALgADCgkJDQAAAA==.',
Eu='Eurotophobia:BAABLgAECn8fAAIGAAcJjhZVdgCAAQAGAAcJjhZVdgCAAQAAAA==.',
Ex='Exodia:BAABLgAECn8lAAMSAAkJHBl9NQAEAgASAAgJuRl9NQAEAgAPAAMJRw8dJACrAAAAAA==.',
Fa='Faldrithor:BAAALgAECgMJAwAAAA==.',
Fe='Fellaria:BAABLgAECn8oAAMZAAkJ4yPUAQD3AgAZAAkJ4yPUAQD3AgAVAAEJmA2ZGgEsAAAAAA==.',
Fh='Fhyllo:BAAALgAECggJEwAAAA==.',
Fl='Fluffybella:BAAALgAFFAIJBAAAAA==.',
Fo='Follaglas:BAACLgAFFH8FAAISAAMJNxJzWQDsAAASAAMJNxJzWQDsAAAuAAQKfyYAAhIACQn0JE8FADwDABIACQn0JE8FADwDAAAA.',
Ga='Gairen:BAABLgAECn8iAAMQAAgJJhoPDgD/AQAQAAgJJhoPDgD/AQAaAAQJ6wRIpgBkAAAAAA==.Galadisis:BAABLgAECn88AAMFAAkJqCFBCwCyAgAFAAkJqCFBCwCyAgAKAAIJ/BhOPAB+AAAAAA==.Galtidor:BAAALgAECgIJAgAAAA==.',
Gh='Ghuldana:BAABLgAECn82AAIYAAgJ6SG4FQCiAgAYAAgJ6SG4FQCiAgABLgAECggJHQAUADQWAA==.',
Gl='Glowgasm:BAAALgADCgMJAgAAAA==.',
Go='Goji:BAAALgADCgMJAwAAAA==.Goon:BAAALgAECgMJBAAAAA==.Goonann:BAAALgAECgkJEwAAAA==.',
Gr='Grimfoul:BAAALgADCgEJAQAAAA==.Gryari:BAABLgAECn8cAAIFAAgJVgtDPABVAQAFAAgJVgtDPABVAQAAAA==.',
Gu='Guiche:BAAALgAECgYJCQAAAA==.',
Gw='Gwiynevere:BAABLgAECn8fAAIRAAYJvwaB3QDVAAARAAYJvwaB3QDVAAAAAA==.',
He='Heathclif:BAAALgAECgUJCAABLgAFFAUJEwAFAIkiAA==.Hellao:BAABLgAECn9KAAIbAAkJ4B2wCQC3AgAbAAkJ4B2wCQC3AgAAAA==.Hellmage:BAAALgADCgcJEQAAAA==.Hermano:BAAALgADCgUJBQAAAA==.',
Ho='Holystones:BAAALgADCgIJAgAAAA==.Hoxpox:BAAALgAECgQJBAAAAA==.',
Hr='Hrimceald:BAAALgAECgkJDwAAAA==.',
Hy='Hylts:BAABLgAECn9AAAILAAkJJxcpCABBAgALAAkJJxcpCABBAgAAAA==.',
Id='Idpswhileafk:BAAALgADCgEJAQAAAA==.',
Il='Illithian:BAAALgAECggJEAAAAA==.',
Im='Imalockyo:BAAALgAECggJCgAAAA==.',
Ja='Javi:BAAALgADCgkJCQABLgAECgkJKAAZAOMjAA==.Javiolak:BAAALgAECgIJAwABLgAECgkJKAAZAOMjAA==.Javisham:BAAALgAECgEJAQABLgAECgkJKAAZAOMjAA==.',
Je='Jedus:BAAALgAECgEJAQABLgAECggJNAAKAKMjAA==.',
Ji='Jizzmon:BAAALgAECgEJAQAAAA==.',
Ka='Kaidirra:BAAALgADCgYJBgAAAA==.Kassiandra:BAABLgAECn81AAMGAAkJtBnoLABMAgAGAAkJtBnoLABMAgAcAAYJ5gciWQAXAQAAAA==.Katja:BAAALgAECgYJBwABLgAECgkJHQAVAPodAA==.',
Ke='Keeyla:BAAALgAECgEJAQAAAA==.Kejiabaobei:BAABLgAECn8qAAISAAkJkiWIAwBZAwASAAkJkiWIAwBZAwAAAA==.Kesta:BAAALgAECgQJBgAAAA==.Kevsterr:BAAALgAECgUJBQAAAA==.',
Kh='Khaantu:BAAALgADCgEJAQAAAA==.',
Ki='Kirin:BAAALgADCgYJCQABLgAECggJEQAIAAAAAA==.',
Ko='Koi:BAAALgAECgIJBQABLgADCgEJAQAIAAAAAA==.Korah:BAAALgADCgcJCwAAAA==.',
Kp='Kpöp:BAABLgAECn8mAAMVAAkJBiLeFgCMAgAVAAkJBiLeFgCMAgAdAAIJ2wrnaABBAAAAAA==.',
Kr='Krakens:BAEALgAECgUJBwABLgAECgkJMgAEALQYAA==.Krayel:BAAALgAECgIJAgAAAA==.Krîtz:BAAALgADCgcJBAAAAA==.Krünk:BAABLgAECn8zAAINAAkJIyDDAgAxAwANAAkJIyDDAgAxAwAAAA==.',
Kt='Kt:BAAALgAFFAEJAgAAAA==.',
Ku='Kumquat:BAAALgADCgEJAQAAAA==.Kuubai:BAAALgADCggJCAAAAA==.',
La='Lachdanan:BAABLgAECn8xAAIeAAkJOw7SFgBpAQAeAAkJOw7SFgBpAQAAAA==.Lament:BAABLgAECn8qAAIVAAgJTCLxFQCSAgAVAAgJTCLxFQCSAgAAAA==.Lans:BAAALgADCgEJAQAAAA==.',
Le='Leafbeard:BAAALgAECgYJBgAAAA==.',
Li='Lilean:BAABLgAECn8UAAISAAgJwh4nEwCeAgASAAgJwh4nEwCeAgAAAA==.',
Lo='Lokka:BAABLgAECn8nAAMLAAkJUhp6CgAPAgALAAkJUhp6CgAPAgADAAYJ+hueSQCFAQAAAA==.Lolly:BAAALgAECgQJBAAAAA==.Loralin:BAAALgADCgcJDQAAAA==.',
Ly='Lyreshade:BAABLgAECn8nAAIJAAkJDxI6JQDnAQAJAAkJDxI6JQDnAQAAAA==.Lyreshaded:BAAALgAECgkJEQABLgAECgkJJwAJAA8SAA==.',
Ma='Maatdemon:BAAALgADCgcJCgABLgAECgkJOAACAGAkAA==.Madbunny:BAAALgADCgYJBwAAAA==.Madriina:BAAALgADCgcJEwAAAA==.Mahrah:BAABLgAECn8wAAIQAAkJyxJcFACwAQAQAAkJyxJcFACwAQAAAA==.Manashifter:BAAALgAECgYJDgAAAA==.Mar:BAAALgAECgUJBQAAAA==.Marija:BAABLgAECn8UAAQaAAgJGxw6HgBSAgAaAAcJXB06HgBSAgAfAAUJHx4aFwBYAQAQAAEJgw1WfgAgAAABLgAECgkJHQAVAPodAA==.',
Me='Melevolence:BAABLgAECn88AAMYAAkJkx0UHQB1AgAYAAkJkx0UHQB1AgAgAAMJ9wZjQQCvAAAAAA==.Mep:BAAALgAECgcJEQAAAA==.Meplastered:BAABLgAECn8VAAQCAAcJ/BLrTgDIAAACAAUJ8hDrTgDIAAAhAAcJ8AWkbwDDAAAiAAIJfx0WWACmAAAAAA==.',
Mi='Mirithari:BAAALgADCgkJEQAAAA==.',
Mo='Molby:BAACLgAFFH8FAAMDAAMJsw7CawBhAAADAAIJiAbCawBhAAAJAAEJkQLEXgArAAAuAAQKfxgAAgMACAnvEZg9ALUBAAMACAnvEZg9ALUBAAEuAAUUBQkFAAoALxIA.Monkehh:BAAALgAECgYJEgABLgAECggJDwAIAAAAAA==.Moolinda:BAABLgAECn8eAAIDAAgJNhdCNwDQAQADAAgJNhdCNwDQAQAAAA==.Morticia:BAABLgAECn8bAAQUAAkJGRv3DwAMAgAUAAgJjBz3DwAMAgARAAYJkQtbugAEAQAMAAEJEguqPQApAAAAAA==.Motgul:BAAALgAECgUJBwABLgAECgcJEQAIAAAAAA==.',
My='Mythbras:BAABLgAECn8VAAITAAYJ0ARh7gDDAAATAAYJ0ARh7gDDAAAAAA==.Mythfurry:BAABLgAFFH8QAAMDAAUJiwYhOgD1AAADAAUJiwYhOgD1AAAJAAEJfgF6YAAjAAABLgAFFAYJIAAaAHkJAA==.',
Na='Nahwey:BAAALgAECgIJAgABLgAECggJHQAUADQWAA==.Nanon:BAAALgAECgQJBgAAAA==.Navdrag:BAAALgAECggJDQABLgAECgkJJgAVAAYiAA==.Naxria:BAABLgAECn8dAAMDAAgJOCBTDwDVAgADAAgJOCBTDwDVAgAJAAYJzh5vJQC7AQAAAA==.',
Ne='Nezanu:BAABLgAECn8kAAIfAAkJvCD/AgDrAgAfAAkJvCD/AgDrAgAAAA==.',
Ni='Nic:BAAALgADCgUJBQAAAA==.Niiko:BAAALgADCgEJAQAAAA==.Nili:BAAALgAECgIJAwAAAA==.Nimithriel:BAABLgAECn8lAAIWAAkJGBSxIwCrAQAWAAkJGBSxIwCrAQAAAA==.',
No='Notwesa:BAAALgAECgEJAQAAAA==.Notweso:BAABLgAECn81AAIVAAkJfSIVDADkAgAVAAkJfSIVDADkAgAAAA==.',
Oc='Oconostota:BAAALgAECgEJAQAAAA==.',
Ol='Oliverclutch:BAAALgADCgIJAgAAAA==.',
Or='Oriari:BAAALgADCgQJBwABLgAECgYJGwAhAGsVAA==.Oroki:BAAALgAECgYJCwAAAA==.',
Pa='Paarthurnax:BAAALgAECgYJBgAAAA==.Pallywack:BAAALgADCgcJBwAAAA==.Parizade:BAAALgAECgQJBQAAAA==.Pat:BAAALgAECgMJAwAAAA==.',
Pe='Pergi:BAAALgADCgkJDwABLgAFFAMJBQASADcSAA==.',
Pi='Pithikos:BAAALgAECgUJCQABLgAFFAUJEwAFAIkiAA==.',
Po='Pocketrapper:BAAALgAECgUJBQAAAA==.Poovey:BAACLgAFFH8WAAIFAAYJwBU+DgCOAQAFAAYJwBU+DgCOAQAuAAQKfyQAAgUACQmSHUEdAAQCAAUACQmSHUEdAAQCAAAA.',
Pu='Purpletoe:BAABLgAECn8aAAMEAAkJkhwXCwCyAgAEAAkJkhwXCwCyAgAWAAYJihJIOwAkAQAAAA==.',
Py='Pyronae:BAABLgAECn81AAIYAAkJ8xIpOQD1AQAYAAkJ8xIpOQD1AQAAAA==.',
Qi='Qit:BAAALgAECgEJAwABLgAECgcJDQAIAAAAAA==.',
Ra='Radrek:BAAALgADCggJCAABLgAFFAEJAQAIAAAAAA==.Rargh:BAABLgAECn8yAAISAAkJxhe+IgBWAgASAAkJxhe+IgBWAgAAAA==.Rawrparade:BAAALgADCgMJAwABLgAFFAcJHQAiADwTAA==.Raín:BAAALgAECgcJEQAAAA==.',
Re='Reddh:BAAALgAECgEJAQAAAA==.Redonkeylous:BAAALgAECgMJAwAAAA==.Relaina:BAAALgAECggJCAAAAA==.Rengen:BAABLgAECn8VAAMiAAkJeA4YKgBjAQAiAAgJNg4YKgBjAQACAAEJSBAYmgAzAAAAAA==.Restobear:BAAALgAECgEJAgAAAA==.Reya:BAABLgAECn8vAAMRAAkJmh3KIACEAgARAAkJIBzKIACEAgAUAAYJHhp4IQBFAQAAAA==.',
Ri='Rileymage:BAAALgAECgEJAgAAAA==.Rixadin:BAAALgADCgEJAQAAAA==.',
Ru='Runelord:BAABLgAECn8aAAMjAAcJSwlaTgDxAAAjAAcJSwlaTgDxAAANAAUJUAo7LQB9AAAAAA==.',
Sa='Saeli:BAABLgAECn8xAAIbAAkJthWQIADBAQAbAAkJthWQIADBAQAAAA==.Saeris:BAAALgAECgcJEwAAAA==.Sakagawea:BAAALgADCgMJAwAAAA==.Salazzle:BAAALgAECgEJAQAAAA==.Sanamongolos:BAAALgAECgIJAgAAAA==.Sasinko:BAABLgAECn81AAIXAAkJfyDLAgCZAgAXAAkJfyDLAgCZAgAAAA==.Sasqüatch:BAAALgADCgQJBAAAAA==.Satjin:BAAALgAECgYJEgAAAA==.Sawlrenuk:BAAALgADCgEJAQAAAA==.',
Sc='Scamander:BAACLgAFFH8HAAIjAAQJcB3yHQBpAQAjAAQJcB3yHQBpAQAuAAQKfxcAAiMABwnCHQEfAN8BACMABwnCHQEfAN8BAAAA.',
Se='Seldszar:BAACLgAFFH8OAAIkAAMJsQsuKgDWAAAkAAMJsQsuKgDWAAAuAAQKf08AAiQACQl/GqUKAHgCACQACQl/GqUKAHgCAAAA.Sentien:BAAALgAECgcJBAAAAA==.',
Sh='Shadowstripe:BAABLgAECn8/AAQCAAkJzhr+CwCCAgACAAkJzhr+CwCCAgAhAAMJ8QPyZQA6AAAiAAEJGAaIjAAsAAAAAA==.Shambamtymam:BAAALgADCgMJAwAAAA==.Shart:BAAALgAECgEJAQAAAA==.Shaylathia:BAAALgAECgMJAwAAAA==.Shigglez:BAACLgAFFH8NAAITAAUJ9RORXQAsAQATAAUJ9RORXQAsAQAuAAQKfzQAAhMACAmWIv8iAI8CABMACAmWIv8iAI8CAAAA.Shiitake:BAAALgAECgMJAwAAAA==.',
So='Socorro:BAAALgAECgEJAQAAAA==.Sonatina:BAACLgAFFH8iAAQHAAkJeCFkAQAwAgAHAAgJXyFkAQAwAgAEAAUJlyOeBQD+AQAWAAEJBCAqNgBVAAAuAAQKfyQAAwcACAmxJR0DAD4DAAcACAmxJR0DAD4DABYABwmwHwYhAL0BAAAA.Soteria:BAAALgAECgYJCQABLgAFFAUJEwAFAIkiAA==.Soulfly:BAABLgAECn9LAAMCAAkJCBsDFQAQAgACAAkJCBsDFQAQAgAiAAgJigiJOQAUAQAAAA==.',
St='Steamedhams:BAAALgAECgYJBgAAAA==.Streat:BAAALgADCgMJAwAAAA==.Streatlight:BAAALgADCgcJDQAAAA==.',
Su='Sugarpants:BAABLgAECn9WAAIhAAgJChsFFgBmAgAhAAgJChsFFgBmAgAAAA==.Sulfuric:BAAALgAECgEJAQAAAA==.Sumtongue:BAABLgAECn8bAAMhAAYJaxXWPAB3AQAhAAYJaxXWPAB3AQAiAAYJiRF1OAAZAQAAAA==.',
Sy='Sylphrenä:BAABLgAECn8gAAMhAAgJ9x2RGQDvAQAhAAcJQB2RGQDvAQACAAYJ+xTyOAAcAQAAAA==.',
Ta='Tanglepriest:BAAALgAECgEJAQABLgAECgEJAgAIAAAAAA==.Tark:BAABLgAECn8YAAIGAAYJAhZMlQBIAQAGAAYJAhZMlQBIAQABLgAECgkJIAASADAeAA==.',
Te='Tembermental:BAAALgAECgUJBQABLgAECgkJOQAgAMQQAA==.Tembtree:BAABLgAECn8dAAMbAAgJ7RPCJQCbAQAbAAgJ7RPCJQCbAQAaAAEJoQK89QAcAAABLgAECgkJOQAgAMQQAA==.Temlock:BAABLgAECn85AAMgAAkJxBDECQCmAQAgAAkJxBDECQCmAQAYAAMJ8AEY+wBkAAAAAA==.',
Th='Thistletea:BAAALgAECgEJAQABLgAECggJJwACAJwaAA==.Thrawnn:BAACLgAFFH8TAAIFAAUJiSKIDgCMAQAFAAUJiSKIDgCMAQAuAAQKfzAAAgUACQlvJVwFAAsDAAUACQlvJVwFAAsDAAAA.',
Tr='Trinia:BAAALgADCgEJAQAAAA==.Tryamarula:BAAALgADCgEJAQAAAA==.Trysomecider:BAAALgADCgIJAwAAAA==.',
Tu='Tuonetar:BAAALgAECgMJAwAAAA==.Turan:BAABLgAECn8gAAISAAkJMB48EgC9AgASAAkJMB48EgC9AgAAAA==.',
Ty='Tyrenari:BAAALgAECgUJCgAAAA==.',
Ul='Ultear:BAABLgAECn8bAAQZAAcJFhhzFAALAQAVAAcJyg/MZQBwAQAZAAYJqBdzFAALAQAdAAMJMxNtXABuAAAAAA==.',
Ve='Vetenarae:BAAALgADCgMJAwABLgAECgkJQAALACcXAA==.',
Vo='Volkren:BAABLgAECn88AAIUAAkJsCClBgCzAgAUAAkJsCClBgCzAgAAAA==.',
Wa='Warhunter:BAAALgAECgQJBAAAAA==.',
Xa='Xandor:BAAALgADCgYJBgABLgAECgkJDwAIAAAAAA==.Xaos:BAAALgAECgkJEAAAAA==.',
Xi='Xiaowugui:BAAALgADCgUJBQAAAA==.',
Xz='Xzaroth:BAAALgADCgcJBwAAAA==.',
Ya='Yarrick:BAABLgAECn88AAIDAAkJkx+lDADxAgADAAkJkx+lDADxAgAAAA==.',
Yo='Yonst:BAABLgAFFH8GAAIEAAMJxwyKJQCOAAAEAAMJxwyKJQCOAAAAAA==.',
Yu='Yumemi:BAAALgADCgcJAgAAAA==.',
Ze='Zelkiri:BAABLgAECn8XAAIbAAcJyAmmRAD3AAAbAAcJyAmmRAD3AAAAAA==.Zeref:BAAALgAECgQJBAABLgAECgkJOAACAGAkAA==.Zerotwoo:BAAALgAECgEJAQAAAA==.Zestama:BAAALgADCgUJBQABLgAFFAUJEwAFAIkiAA==.Zethlahr:BAABLgAECn82AAMWAAkJhh3qDQB3AgAWAAkJhh3qDQB3AgAEAAQJpA2tUgDtAAAAAA==.',
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
