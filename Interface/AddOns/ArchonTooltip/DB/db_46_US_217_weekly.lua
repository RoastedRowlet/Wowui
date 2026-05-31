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

local lookup = {'Mage-Fire','Monk-Windwalker','Shaman-Restoration','Priest-Holy','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Unknown-Unknown','Shaman-Elemental','Warrior-Protection','Shaman-Enhancement','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Hunter-Survival','Druid-Guardian','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','Warlock-Affliction','Warlock-Demonology','DemonHunter-Vengeance','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','Paladin-Protection','Warlock-Destruction','Monk-Mistweaver','Monk-Brewmaster','Druid-Restoration','Druid-Feral','Evoker-Augmentation','Rogue-Subtlety',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=46,date='2026-05-31',data={Ab='Abanados:BAABLgAECn8XAAIBAAgJ+g3DBAB4AQABAAgJ+g3DBAB4AQAAAA==.',
Ae='Aethelra:BAAALgAECgcJCgAAAA==.',
Ak='Akatsuki:BAABLgAECn84AAICAAkJYCSRAwAYAwACAAkJYCSRAwAYAwAAAA==.Aken:BAAALgAECgQJBAAAAA==.',
Al='Alight:BAAALgAECgcJCwABLgAECgkJIQADADMdAA==.Allera:BAAALgADCgEJAQAAAA==.Althea:BAABLgAECn8kAAIEAAgJNRG8KACrAQAEAAgJNRG8KACrAQAAAA==.',
Am='Ambition:BAAALgAECgEJAQABLgAFFAUJFQAFAGUXAA==.Amoredis:BAAALgADCggJDgAAAA==.',
An='Animorpha:BAAALgAECgMJAwAAAA==.',
Ar='Ariane:BAAALgAECgIJAgAAAA==.Arkaen:BAABLgAECn8mAAIGAAgJMyBLHADAAgAGAAgJMyBLHADAAgAAAA==.Arkhyn:BAAALgAECgUJCAAAAA==.',
As='Ashengor:BAAALgAECgMJBAAAAA==.Asonda:BAEBLgAECn8sAAMEAAgJPxkOFQAYAgAEAAgJIhgOFQAYAgAHAAgJkQ90IACpAQAAAA==.Assi:BAAALgADCgEJAQAAAA==.',
Az='Azshauyssa:BAAALgAECgcJEQAAAA==.',
Ba='Baelsk:BAAALgADCgYJBgABLgAECgYJDwAIAAAAAA==.Bagofluff:BAAALgAECgQJBAABLgAFFAcJHQAJANgaAA==.Bajamama:BAABLgAECn8lAAMJAAgJFxdmIQDCAQAJAAgJFxdmIQDCAQADAAYJ/g7zTABPAQAAAA==.Barkupatree:BAAALgADCgkJCQAAAA==.Batou:BAAALgADCgEJAQAAAA==.',
Be='Beans:BAAALgADCgUJBQAAAA==.Bel:BAAALgAFFAEJAQABLgAECgkJPAAKAAAlAA==.Betarius:BAAALgAECgUJCQABLgAECgkJIQADADMdAA==.Betiff:BAABLgAECn8hAAMDAAkJMx1UGwBZAgADAAgJHBxUGwBZAgAJAAgJshToNwA/AQAAAA==.',
Bi='Birddog:BAAALgAECgkJCQAAAA==.',
Bl='Blazeschill:BAAALgADCgEJAQABLgAECgkJOwALAO4YAA==.Blooded:BAABLgAECn8XAAIMAAkJgQ0SDgBnAQAMAAkJgQ0SDgBnAQAAAA==.Bloodydraco:BAABLgAECn81AAMNAAkJhhnfBgCAAgANAAkJhhnfBgCAAgAOAAEJpwV3JQAsAAAAAA==.Bloodymagus:BAAALgADCgkJCQAAAA==.',
Bo='Bolden:BAAALgADCgkJHQAAAA==.',
Br='Brelm:BAAALgADCgQJBwAAAA==.Brewzin:BAAALgADCgQJBAAAAA==.Bruwu:BAAALgAECgcJCgAAAA==.',
Bu='Bubblez:BAAALgADCgQJBAAAAA==.',
Ca='Cakebro:BAABLgAECn86AAIPAAkJQiEoBADeAgAPAAkJQiEoBADeAgAAAA==.Camembert:BAABLgAECn8qAAIQAAkJ7yK5AgD0AgAQAAkJ7yK5AgD0AgAAAA==.Casii:BAABLgAECn8UAAIEAAkJhhC+JgB8AQAEAAkJhhC+JgB8AQAAAA==.',
Ce='Cele:BAAALgAECgMJBAAAAA==.Celyne:BAAALgAECgEJAQAAAA==.',
Ch='Chiizo:BAABLgAECn8UAAIHAAYJsRLWJwBXAQAHAAYJsRLWJwBXAQAAAA==.Chiror:BAAALgADCgYJCQAAAA==.Chubingus:BAACLgAFFH8GAAIRAAMJJCG4WgAmAQARAAMJJCG4WgAmAQAuAAQKfx4AAhEACQmAICkdAIcCABEACQmAICkdAIcCAAAA.Chuckmcstabb:BAAALgAECgEJAQAAAA==.Chufeng:BAABLgAECn8dAAISAAcJuyGSIABQAgASAAcJuyGSIABQAgABLgAFFAQJDAAFAO0gAA==.',
Co='Coggette:BAABLgAECn8XAAITAAYJxgR8/gD+AAATAAYJxgR8/gD+AAAAAA==.Corvica:BAAALgADCgEJAQAAAA==.',
Cr='Crizadin:BAAALgAECgMJAwAAAA==.Crizuid:BAAALgAECgUJCQABLgAECgcJFwASAEYjAA==.Crocubot:BAAALgAECgIJBQAAAA==.',
Cu='Cucuyknight:BAAALgADCgEJAgAAAA==.',
Da='Danaki:BAABLgAECn8bAAIUAAgJWxV3FAC0AQAUAAgJWxV3FAC0AQAAAA==.Dancookerton:BAAALgADCgUJBQAAAA==.Danorace:BAAALgAECgQJBwAAAA==.Darkcurve:BAAALgAECgkJDwAAAA==.Darkhope:BAAALgAECgkJDwAAAA==.',
De='Deija:BAABLgAECn8cAAIVAAgJfx6QLQD9AQAVAAgJfx6QLQD9AQAAAA==.Dekoo:BAABLgAECn80AAIKAAgJoyNTBQCzAgAKAAgJoyNTBQCzAgAAAA==.Demon:BAAALgAECgcJEwAAAA==.Demoneyez:BAAALgAECgYJCQAAAA==.Deusene:BAABLgAECn8YAAIWAAYJHhCzLgBsAQAWAAYJHhCzLgBsAQAAAA==.',
Dr='Drakula:BAABLgAECn8WAAMXAAcJZQS4HAC5AAAYAAcJIgQbtgDRAAAXAAYJnAO4HAC5AAAAAA==.Dreadfang:BAABLgAECn88AAIRAAkJcSMpEQDTAgARAAkJcSMpEQDTAgAAAA==.Droka:BAABLgAECn81AAIDAAkJESAtBwArAwADAAkJESAtBwArAwAAAA==.',
El='Elavil:BAAALgADCgYJEAAAAA==.Eldrynath:BAAALgAECgYJDQAAAA==.',
En='Endel:BAAALgADCgcJCwAAAA==.',
Eu='Eurotophobia:BAABLgAECn8fAAIGAAcJjhZRbAB9AQAGAAcJjhZRbAB9AQAAAA==.',
Ex='Exodia:BAABLgAECn8iAAMSAAgJhBleQwDCAQASAAcJTRpeQwDCAQAPAAMJRw8dJACrAAAAAA==.',
Fa='Faldrithor:BAAALgAECgMJAwAAAA==.',
Fe='Fellaria:BAABLgAECn8oAAMZAAkJ4yPUAQD3AgAZAAkJ4yPUAQD3AgAVAAEJmA2OBAErAAAAAA==.',
Fh='Fhyllo:BAAALgAECggJEwAAAA==.',
Fl='Fluffybella:BAAALgAFFAIJBAAAAA==.',
Fo='Follaglas:BAABLgAECn8mAAISAAkJ9CTOAwBIAwASAAkJ9CTOAwBIAwAAAA==.',
Ga='Gairen:BAABLgAECn8cAAIQAAgJxxmuDAD5AQAQAAgJxxmuDAD5AQAAAA==.Galadisis:BAABLgAECn88AAMFAAkJqCFJCQC8AgAFAAkJqCFJCQC8AgAKAAIJ/Bj7NgCFAAAAAA==.Galtidor:BAAALgAECgIJAgAAAA==.',
Gh='Ghuldana:BAABLgAECn8pAAIYAAgJuiCJGwByAgAYAAgJuiCJGwByAgABLgAECggJGwAUAFsVAA==.',
Gl='Glowgasm:BAAALgADCgMJAgAAAA==.',
Go='Goji:BAAALgADCgMJAwAAAA==.Goon:BAAALgAECgMJBAAAAA==.Goonann:BAAALgAECgkJEwAAAA==.',
Gr='Grimfoul:BAAALgADCgEJAQAAAA==.Gryari:BAABLgAECn8aAAIFAAgJhgp0OABSAQAFAAgJhgp0OABSAQAAAA==.',
Gu='Guiche:BAAALgAECgYJCQAAAA==.',
Gw='Gwiynevere:BAABLgAECn8cAAIRAAYJZAbfzwDTAAARAAYJZAbfzwDTAAAAAA==.',
He='Heathclif:BAAALgAECgQJBAABLgAFFAQJDAAFAO0gAA==.Hellao:BAABLgAECn9BAAIaAAkJ3Rz7CQCfAgAaAAkJ3Rz7CQCfAgAAAA==.Hellmage:BAAALgADCgcJEQAAAA==.Hermano:BAAALgADCgUJBQAAAA==.',
Ho='Holystones:BAAALgADCgIJAgAAAA==.Hoxpox:BAAALgAECgQJBAAAAA==.',
Hr='Hrimceald:BAAALgAECgkJDwAAAA==.',
Hy='Hylts:BAABLgAECn8vAAILAAgJehU/DADUAQALAAgJehU/DADUAQAAAA==.',
Id='Idpswhileafk:BAAALgADCgEJAQAAAA==.',
Il='Illithian:BAAALgAECgcJDwAAAA==.',
Im='Imalockyo:BAAALgAECggJCgAAAA==.',
Ja='Javi:BAAALgADCgkJCQABLgAECgkJKAAZAOMjAA==.Javiolak:BAAALgAECgIJAwABLgAECgkJKAAZAOMjAA==.',
Je='Jedus:BAAALgAECgEJAQABLgAECggJNAAKAKMjAA==.',
Ji='Jizzmon:BAAALgAECgEJAQAAAA==.',
Ka='Kaidirra:BAAALgADCgYJBgAAAA==.Kassiandra:BAABLgAECn81AAMGAAkJuRnUJgBRAgAGAAkJuRnUJgBRAgAbAAYJ5gciWQAXAQAAAA==.Katja:BAAALgAECgYJBwABLgAECggJHAAVAH8eAA==.',
Ke='Keeyla:BAAALgAECgEJAQAAAA==.Kejiabaobei:BAABLgAECn8qAAISAAkJkiWIAwBZAwASAAkJkiWIAwBZAwAAAA==.Kesta:BAAALgAECgQJBgAAAA==.Kevsterr:BAAALgAECgUJBQAAAA==.',
Kh='Khaantu:BAAALgADCgEJAQAAAA==.',
Ki='Kirin:BAAALgADCgYJCQABLgAECgYJDwAIAAAAAA==.',
Ko='Koi:BAAALgAECgIJBQABLgADCgEJAQAIAAAAAA==.Korah:BAAALgADCgcJCwAAAA==.',
Kp='Kpöp:BAABLgAECn8mAAMVAAkJBiJ4FACNAgAVAAkJBiJ4FACNAgAcAAIJ2wrnaABBAAAAAA==.',
Kr='Krakens:BAEALgAECgUJBwABLgAECggJLAAEAD8ZAA==.Krayel:BAAALgAECgIJAgAAAA==.Krîtz:BAAALgADCgcJBAAAAA==.Krünk:BAABLgAECn8zAAINAAkJIyCHAgA1AwANAAkJIyCHAgA1AwAAAA==.',
Kt='Kt:BAAALgAFFAEJAgAAAA==.',
Ku='Kumquat:BAAALgADCgEJAQAAAA==.Kuubai:BAAALgADCggJCAAAAA==.',
La='Lachdanan:BAABLgAECn8rAAIdAAgJkQ4rGQA5AQAdAAgJkQ4rGQA5AQAAAA==.Lament:BAABLgAECn8nAAIVAAgJTCJ1FACNAgAVAAgJTCJ1FACNAgAAAA==.Lans:BAAALgADCgEJAQAAAA==.',
Le='Leafbeard:BAAALgAECgYJBgAAAA==.',
Li='Lilean:BAABLgAECn8UAAISAAgJwh4nEwCeAgASAAgJwh4nEwCeAgAAAA==.',
Lo='Lokka:BAABLgAECn8mAAMLAAgJTBlRDgCxAQALAAgJTBlRDgCxAQADAAYJ+hsJQwCIAQAAAA==.Lolly:BAAALgAECgQJBAAAAA==.Loralin:BAAALgADCgcJDQAAAA==.',
Ly='Lyreshade:BAABLgAECn8nAAIJAAkJDxI6JQDnAQAJAAkJDxI6JQDnAQAAAA==.Lyreshaded:BAAALgAECgkJEAABLgAECgkJJwAJAA8SAA==.',
Ma='Maatdemon:BAAALgADCgcJCgABLgAECgkJOAACAGAkAA==.Madbunny:BAAALgADCgYJBwAAAA==.Madriina:BAAALgADCgcJEwAAAA==.Mahrah:BAABLgAECn8vAAIQAAgJuxTDFACQAQAQAAgJuxTDFACQAQAAAA==.Manashifter:BAAALgAECgYJDgAAAA==.Mar:BAAALgADCgcJBwAAAA==.Marija:BAAALgAECggJEQABLgAECggJHAAVAH8eAA==.',
Me='Melevolence:BAABLgAECn88AAMYAAkJkx0QGgB8AgAYAAkJkx0QGgB8AgAeAAMJ9wZjQQCvAAAAAA==.Mep:BAAALgAECgcJDwAAAA==.Meplastered:BAABLgAECn8VAAQCAAcJ/BIYSADLAAACAAUJ8hAYSADLAAAfAAcJ8AVxYADBAAAgAAIJfx2GUwCnAAAAAA==.',
Mi='Mirithari:BAAALgADCgkJCQAAAA==.',
Mo='Molby:BAABLgAECn8YAAIDAAgJ7xFYOAC1AQADAAgJ7xFYOAC1AQABLgAFFAMJBQAQAIwKAA==.Monkehh:BAAALgAECgYJEAABLgAECggJDwAIAAAAAA==.Moolinda:BAABLgAECn8eAAIDAAgJNhcdMgDSAQADAAgJNhcdMgDSAQAAAA==.Morticia:BAABLgAECn8bAAQUAAkJGRv3DwAMAgAUAAgJjBz3DwAMAgARAAYJkQupqwAHAQAMAAEJEguFMgAuAAAAAA==.Motgul:BAAALgAECgUJBwABLgAECgcJDwAIAAAAAA==.',
My='Mythbras:BAAALgAECgYJDQAAAA==.Mythfurry:BAABLgAFFH8OAAMDAAUJdwPkMAD+AAADAAUJdwPkMAD+AAAJAAEJfgH/UAAnAAABLgAFFAYJHQAhAP0IAA==.',
Na='Nahwey:BAAALgAECgIJAgABLgAECggJGwAUAFsVAA==.Nanon:BAAALgAECgQJBgAAAA==.Navdrag:BAAALgAECgUJBQABLgAECgkJJgAVAAYiAA==.Naxria:BAABLgAECn8cAAMDAAgJNCAbDQDYAgADAAgJNCAbDQDYAgAJAAYJzh6xIQDAAQAAAA==.',
Ne='Nezanu:BAABLgAECn8kAAIiAAkJvCBSAgDyAgAiAAkJvCBSAgDyAgAAAA==.',
Ni='Nic:BAAALgADCgUJBQAAAA==.Niiko:BAAALgADCgEJAQAAAA==.Nili:BAAALgAECgIJAgAAAA==.Nimithriel:BAABLgAECn8lAAIWAAkJGBTfIQCbAQAWAAkJGBTfIQCbAQAAAA==.',
No='Notwesa:BAAALgAECgEJAQAAAA==.Notweso:BAABLgAECn80AAIVAAkJfSIyCgDoAgAVAAkJfSIyCgDoAgAAAA==.',
Oc='Oconostota:BAAALgAECgEJAQAAAA==.',
Ol='Oliverclutch:BAAALgADCgIJAgAAAA==.',
Or='Oriari:BAAALgADCgQJBAABLgAECgYJGQAfAGsVAA==.Oroki:BAAALgAECgYJCwAAAA==.',
Pa='Paarthurnax:BAAALgAECgYJBgAAAA==.Pallywack:BAAALgADCgcJBwAAAA==.Parizade:BAAALgAECgMJAwAAAA==.Pat:BAAALgAECgMJAwAAAA==.',
Pe='Pergi:BAAALgADCgkJDwABLgAECgkJJgASAPQkAA==.',
Pi='Pithikos:BAAALgAECgUJCQABLgAFFAQJDAAFAO0gAA==.',
Po='Pocketrapper:BAAALgAECgUJBQAAAA==.Poovey:BAACLgAFFH8VAAIFAAUJZReWFwA/AQAFAAUJZReWFwA/AQAuAAQKfyQAAgUACQmSHeYZAAwCAAUACQmSHeYZAAwCAAAA.',
Pu='Purpletoe:BAABLgAECn8ZAAMEAAkJkhy8CQC5AgAEAAkJkhy8CQC5AgAWAAYJihLDNQAfAQAAAA==.',
Py='Pyronae:BAABLgAECn81AAIYAAkJ8xJLMwAAAgAYAAkJ8xJLMwAAAgAAAA==.',
Qi='Qit:BAAALgAECgEJAgABLgAECgcJDQAIAAAAAA==.',
Ra='Radrek:BAAALgADCggJCAAAAA==.Rargh:BAABLgAECn8wAAISAAkJvBRGMwD7AQASAAkJvBRGMwD7AQAAAA==.Raín:BAAALgAECgcJDQAAAA==.',
Re='Reddh:BAAALgADCgQJBAAAAA==.Redonkeylous:BAAALgAECgMJAwAAAA==.Relaina:BAAALgAECgIJAgAAAA==.Rengen:BAABLgAECn8VAAMgAAkJeA51JwBkAQAgAAgJNg51JwBkAQACAAEJSBD6iwAzAAAAAA==.Restobear:BAAALgAECgEJAQAAAA==.Reya:BAABLgAECn8pAAMRAAgJyh44LgA0AgARAAgJGx04LgA0AgAUAAYJHhpTHgBLAQAAAA==.',
Ri='Rixadin:BAAALgADCgEJAQAAAA==.',
Ru='Runelord:BAABLgAECn8YAAMjAAcJSwnESQDiAAAjAAcJSwnESQDiAAANAAQJzAqzMABWAAAAAA==.',
Sa='Saeli:BAABLgAECn8xAAIaAAkJthUWHQDHAQAaAAkJthUWHQDHAQAAAA==.Saeris:BAAALgAECgcJDgAAAA==.Sakagawea:BAAALgADCgMJAwAAAA==.Sanamongolos:BAAALgAECgIJAgAAAA==.Sasinko:BAABLgAECn81AAIXAAkJfyAjAgCiAgAXAAkJfyAjAgCiAgAAAA==.Sasqüatch:BAAALgADCgQJBAAAAA==.Satjin:BAAALgAECgYJEgAAAA==.Sawlrenuk:BAAALgADCgEJAQAAAA==.',
Sc='Scamander:BAABLgAECn8XAAIjAAcJwh2fHADaAQAjAAcJwh2fHADaAQAAAA==.',
Se='Sentien:BAAALgAECgcJBAAAAA==.',
Sh='Shadowstripe:BAABLgAECn8pAAQCAAgJLhVWGwC/AQACAAgJLhVWGwC/AQAfAAMJ8QPyZQA6AAAgAAEJGAaIjAAsAAAAAA==.Shambamtymam:BAAALgADCgMJAwAAAA==.Shaylathia:BAAALgAECgMJAwAAAA==.Shigglez:BAACLgAFFH8LAAITAAQJ9RP6TgAyAQATAAQJ9RP6TgAyAQAuAAQKfzMAAhMACAmWImQfAI0CABMACAmWImQfAI0CAAAA.Shiitake:BAAALgAECgMJAwAAAA==.',
So='Sonatina:BAACLgAFFH8hAAQHAAgJjSEsAgAJAwAHAAgJXyEsAgAJAwAEAAQJSCQcCACfAQAWAAEJBCBQLgBaAAAuAAQKfyQAAwcACAmxJR0DAD4DAAcACAmxJR0DAD4DABYABwmwHzweALcBAAAA.Soteria:BAAALgAECgYJCQABLgAFFAQJDAAFAO0gAA==.Soulfly:BAABLgAECn9KAAMCAAkJ2RnoFAD9AQACAAkJ2RnoFAD9AQAgAAgJigjGNQAXAQAAAA==.',
St='Steamedhams:BAAALgAECgYJBgAAAA==.Streat:BAAALgADCgMJAwAAAA==.Streatlight:BAAALgADCgcJDQAAAA==.',
Su='Sugarpants:BAABLgAECn9GAAIfAAgJ6BjqGAAuAgAfAAgJ6BjqGAAuAgAAAA==.Sulfuric:BAAALgAECgEJAQAAAA==.Sumtongue:BAABLgAECn8ZAAMfAAYJaxXhNAB2AQAfAAYJaxXhNAB2AQAgAAYJWg9PPAD6AAAAAA==.',
Sy='Sylphrenä:BAABLgAECn8gAAMfAAgJ9x2RGQDvAQAfAAcJQB2RGQDvAQACAAYJ+xRXNAAeAQAAAA==.',
Ta='Tark:BAAALgAECgYJEwABLgAECggJHgASANAdAA==.',
Te='Tembtree:BAABLgAECn8bAAMaAAgJ7RNEIgCeAQAaAAgJ7RNEIgCeAQAhAAEJoQLp6AAcAAABLgAECggJOAAeAKURAA==.Temlock:BAABLgAECn84AAMeAAgJpREFCwB3AQAeAAgJpREFCwB3AQAYAAMJ8AEY+wBkAAAAAA==.',
Th='Thrawnn:BAACLgAFFH8MAAIFAAQJ7SDHDgBvAQAFAAQJ7SDHDgBvAQAuAAQKfy8AAgUACQlRJaIEAAoDAAUACQlRJaIEAAoDAAAA.',
Tr='Trinia:BAAALgADCgEJAQAAAA==.Tryamarula:BAAALgADCgEJAQAAAA==.Trysomecider:BAAALgADCgIJAwAAAA==.',
Tu='Tuonetar:BAAALgAECgMJAwAAAA==.Turan:BAABLgAECn8eAAISAAgJ0B2PHABmAgASAAgJ0B2PHABmAgAAAA==.',
Ty='Tyrenari:BAAALgAECgUJCgAAAA==.',
Ul='Ultear:BAABLgAECn8aAAQZAAcJVheaEgALAQAVAAcJyg/MZQBwAQAZAAYJqBeaEgALAQAcAAIJ/xBtXABuAAAAAA==.',
Ve='Velkyn:BAACLgAFFH8MAAIkAAMJsQuMJADbAAAkAAMJsQuMJADbAAAuAAQKf0cAAiQACQmjGdYKAGICACQACQmjGdYKAGICAAAA.Vetenarae:BAAALgADCgMJAwABLgAECggJLwALAHoVAA==.',
Vo='Volkren:BAABLgAECn87AAIUAAkJLCBNBgCsAgAUAAkJLCBNBgCsAgAAAA==.',
Wa='Warhunter:BAAALgAECgQJBAAAAA==.',
Xa='Xandor:BAAALgADCgYJBgABLgAECgkJDwAIAAAAAA==.Xaos:BAAALgAECgkJEAAAAA==.',
Xi='Xiaowugui:BAAALgADCgUJBQAAAA==.',
Xz='Xzaroth:BAAALgADCgcJBwAAAA==.',
Ya='Yarrick:BAABLgAECn88AAIDAAkJkx/XCgD1AgADAAkJkx/XCgD1AgAAAA==.',
Yo='Yonst:BAABLgAFFH8GAAIEAAMJxwzDHwCcAAAEAAMJxwzDHwCcAAAAAA==.',
Yu='Yumemi:BAAALgADCgcJAgAAAA==.',
Ze='Zelkiri:BAABLgAECn8UAAIaAAcJyAnuPgD5AAAaAAcJyAnuPgD5AAAAAA==.Zeref:BAAALgAECgQJBAABLgAECgkJOAACAGAkAA==.Zerotwoo:BAAALgAECgEJAQAAAA==.Zethlahr:BAABLgAECn82AAMWAAkJhh1DDAB0AgAWAAkJhh1DDAB0AgAEAAQJpA2tUgDtAAAAAA==.',
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
