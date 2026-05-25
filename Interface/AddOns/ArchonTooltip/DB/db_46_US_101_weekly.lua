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

local lookup = {'Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Shaman-Restoration','Priest-Discipline','Monk-Mistweaver','Unknown-Unknown','Evoker-Preservation','Rogue-Assassination','Warlock-Affliction','Paladin-Retribution','Mage-Frost','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Priest-Holy','Monk-Brewmaster','Paladin-Protection','Monk-Windwalker','DeathKnight-Blood','Warlock-Demonology','Paladin-Holy','DemonHunter-Vengeance','Druid-Balance','Priest-Shadow','Druid-Feral','Hunter-Marksmanship','Hunter-Survival','Warlock-Destruction','DeathKnight-Frost','Warrior-Fury','Shaman-Enhancement','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-05-23',data={Ae='Aegisthal:BAACLgAFFH8FAAIBAAMJ+BpOEgDtAAABAAMJ+BpOEgDtAAAuAAQKfxkAAgEACAnEHk4JAD0CAAEACAnEHk4JAD0CAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgADCgcJBwAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJJgACAEMLAA==.',
Al='Alanerazza:BAAALgADCgcJDQAAAA==.Althenzdormu:BAABLgAECn8gAAMDAAcJQwvrDwDpAAAEAAcJiAplPQANAQADAAYJOAnrDwDpAAAAAA==.Altruist:BAABLgAECn8dAAMFAAcJBhrYEQDXAQAFAAcJBhrYEQDXAQAGAAIJnAQt4gBBAAABLgAECggJLgABABsYAA==.',
Am='Amaethon:BAAALgAECgYJDwAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8wAAIHAAkJOR3FCwDWAgAHAAkJOR3FCwDWAgAAAA==.Andorra:BAAALgADCgUJBAAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn8uAAIIAAgJBiBQBwDfAgAIAAgJBiBQBwDfAgAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIJAAgJTAgWOwD6AAAJAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAKAAAAAA==.Around:BAAALgADCgIJAgAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8uAAQDAAgJ9xXvBQDTAQADAAgJ9xXvBQDTAQALAAQJpxRxHAD2AAAEAAEJsQOmhAAnAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn8uAAIMAAgJPgw5CgBzAQAMAAgJPgw5CgBzAQAAAA==.',
Az='Azbogah:BAAALgADCgkJGgAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAANAGkVAA==.Balthenor:BAACLgAFFH8GAAIOAAIJqxMpIgCoAAAOAAIJqxMpIgCoAAAuAAQKfx4AAg4ACAn+IZMRAAQDAA4ACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8fAAIJAAkJyRoeCwC0AgAJAAkJyRoeCwC0AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAKAAAAAA==.Berse:BAABLgAECn8YAAICAAYJRB/mXQBeAQACAAYJRB/mXQBeAQAAAA==.',
Bi='Bilko:BAAALgADCgEJAQAAAA==.Birdymage:BAABLgAECn8VAAIPAAUJHBRWsAAGAQAPAAUJHBRWsAAGAQAAAA==.',
Bl='Blightbeard:BAABLgAECn8VAAIQAAgJLAj5ewBFAQAQAAgJLAj5ewBFAQAAAA==.Blîss:BAAALgAECgUJBwAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAYJHgAQAA4VAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgkJFAAAAA==.',
Br='Brut:BAABLgAECn8aAAIGAAkJmh0EOQAQAgAGAAkJmh0EOQAQAgAAAA==.',
Bu='Bustus:BAABLgAECn8rAAIRAAgJJw1pRABbAQARAAgJJw1pRABbAQAAAA==.',
Ca='Carmasutra:BAAALgADCgYJBQAAAA==.Caroll:BAAALgAECgcJDQAAAA==.Carsomavra:BAAALgADCggJHQAAAA==.Cathercy:BAABLgAECn8YAAIOAAUJ5Av2yQDWAAAOAAUJ5Av2yQDWAAAAAA==.',
Ch='Chenzhen:BAAALgAECgUJBwAAAA==.Chilly:BAAALgAECgYJDwABLgAFFAQJBwAJAAsNAA==.Chunt:BAAALgAECgQJBAAAAA==.',
Co='Compliance:BAABLgAECn8uAAIBAAgJGxiJDQDnAQABAAgJGxiJDQDnAQAAAA==.Corannis:BAABLgAECn8iAAISAAgJdxEQKwBuAQASAAgJdxEQKwBuAQAAAA==.Cowabunga:BAAALgADCgkJCQABLgAECgkJKwATAHMRAA==.',
Cr='Cranberries:BAABLgAECn8bAAMUAAcJyxeTIACbAQAUAAYJpxiTIACbAQAIAAcJNRAmJgBvAQAAAA==.Crockett:BAAALgADCgIJAgABLgAECgUJDwAKAAAAAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Curtis:BAAALgAECgYJDQABLgAECggJIAAVAFkeAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJCAAAAA==.Dalra:BAAALgADCgUJBQABLgAECggJNQAFACwVAA==.Dantez:BAAALgAECgcJDAAAAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAABLgAECn8kAAIGAAgJ8xq7KQAEAgAGAAgJ8xq7KQAEAgAAAA==.',
De='Delderach:BAABLgAECn8YAAIWAAUJahGAIgDQAAAWAAUJahGAIgDQAAAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn8tAAIQAAgJYRvoMwALAgAQAAgJYRvoMwALAgAAAA==.',
Di='Dirkette:BAABLgAECn8oAAIIAAkJKARCLABGAQAIAAkJKARCLABGAQAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECgkJKAAIACgEAA==.Dirksavoid:BAAALgAECgUJBQABLgAECgkJKAAIACgEAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dokai:BAABLgAECn8qAAIXAAgJ2BkjEwD/AQAXAAgJ2BkjEwD/AQAAAA==.',
Dr='Dracmiz:BAAALgADCgYJBgAAAA==.Dragenous:BAAALgAECgMJBAAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECgUJCgAKAAAAAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drathan:BAAALgADCgYJBQAAAA==.Drewella:BAAALgADCgkJCQAAAA==.',
El='Elaenei:BAAALgADCgkJHQAAAA==.Eliance:BAABLgAECn8YAAIMAAUJRQP6FgCSAAAMAAUJRQP6FgCSAAAAAA==.Elienn:BAAALgADCgcJBwAAAA==.Elsewhere:BAABLgAECn8bAAMEAAkJtQyIKQB4AQAEAAkJtQyIKQB4AQALAAEJwQjqOAAkAAAAAA==.',
Em='Emberly:BAAALgAECgYJBgAAAA==.Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8jAAIYAAgJoRaAFQCQAQAYAAgJoRaAFQCQAQAAAA==.',
Eu='Eunja:BAEALgAECgYJDAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.',
Fa='Fatherbetter:BAAALgAECgEJAQABLgAECggJIwAGAHEcAA==.',
Fe='Feeltheburn:BAAALgAECgYJEAAAAA==.Feloras:BAAALgAECgYJCwAAAA==.',
Fl='Flamemane:BAAALgADCgIJAgAAAA==.',
Fo='Foxina:BAAALgADCgcJBwAAAA==.',
Fu='Fusaa:BAABLgAECn8xAAIZAAkJnhSuLQAKAgAZAAkJnhSuLQAKAgAAAA==.',
Ga='Gallindo:BAAALgADCgYJBgABLgAECgYJDgAKAAAAAA==.Gangry:BAAALgAECgQJCQAAAA==.',
Ge='Gelst:BAAALgADCgUJBQAAAA==.Gerbzarrion:BAABLgAECn8YAAIPAAUJfAWC4wCxAAAPAAUJfAWC4wCxAAAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAABLgAECn81AAIFAAgJLBULFQCtAQAFAAgJLBULFQCtAQAAAA==.',
Gl='Glyslam:BAAALgAFFAEJAQAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAKAAAAAA==.Hawknnin:BAABLgAECn8VAAIaAAUJPyWhGQARAgAaAAUJPyWhGQARAgAAAA==.',
He='Hechicera:BAAALgAECgkJEgAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.Here:BAAALgADCgUJBQAAAA==.',
Hu='Hunterpulled:BAAALgAFFAEJAQAAAA==.Huntrod:BAAALgADCgEJBQAAAA==.Huroona:BAAALgADCgcJEAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJGwAUAMsXAA==.',
Ip='Ipwnallnoobs:BAABLgAECn8cAAIQAAkJcA0+SgDBAQAQAAkJcA0+SgDBAQAAAA==.',
Ir='Irisila:BAAALgAECgEJAQABLgAECgYJDgAKAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAABLgAECn8gAAIRAAcJFhrvJAACAgARAAcJFhrvJAACAgAAAA==.',
Jo='Johalea:BAAALgADCgYJBQAAAA==.',
['Jå']='Jåsper:BAABLgAECn8UAAIOAAcJMxxCQwDdAQAOAAcJMxxCQwDdAQAAAA==.',
Ka='Kaileena:BAABLgAECn8xAAIbAAkJ0heBBQAkAgAbAAkJ0heBBQAkAgAAAA==.Kaimare:BAAALgADCgUJCAAAAA==.Kandistars:BAABLgAECn8gAAIcAAgJHxHJJQBvAQAcAAgJHxHJJQBvAQAAAA==.Kasia:BAABLgAECn8gAAIHAAcJ6x2WJwDzAQAHAAcJ6x2WJwDzAQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8aAAIQAAgJiBb0TwCwAQAQAAgJiBb0TwCwAQAAAA==.Kirarah:BAABLgAECn8pAAICAAgJ2yJkEACmAgACAAgJ2yJkEACmAgAAAA==.Kirarose:BAACLgAFFH8OAAMdAAQJGBPMEgA1AQAdAAQJGBPMEgA1AQAUAAIJ2gE7JgBZAAAuAAQKfxwAAx0ACQmmIlgNAFoCAB0ACQmmIlgNAFoCABQAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn8qAAIJAAkJNQ+6IwC6AQAJAAkJNQ+6IwC6AQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgADCgIJAgAAAA==.',
Kr='Krornik:BAAALgADCgkJGAAAAA==.Krunch:BAAALgADCgkJCQABLgAECgYJCgAKAAAAAA==.',
Ky='Kylia:BAABLgAECn8YAAINAAcJoBqRBwDAAQANAAcJoBqRBwDAAQAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8mAAICAAkJjyBGDwCvAgACAAkJjyBGDwCvAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Leangra:BAAALgADCgQJBAAAAA==.Legenddairy:BAABLgAECn8rAAMTAAkJcxFcFQBsAQAcAAkJ7Q/xLwCIAQATAAkJrw1cFQBsAQAAAA==.',
Li='Lizardath:BAABLgAECn8iAAICAAgJIwrfYwBPAQACAAgJIwrfYwBPAQAAAA==.',
Lj='Ljósálfr:BAABLgAECn80AAIBAAkJWSMqAgAVAwABAAkJWSMqAgAVAwAAAA==.',
Lo='Lochramae:BAABLgAECn8xAAIYAAkJ8BWqFACbAQAYAAkJ8BWqFACbAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJCwAAAA==.',
Lu='Lumanoughty:BAAALgADCgkJHQAAAA==.Lunargaze:BAABLgAECn8jAAIGAAgJcRz+HQBDAgAGAAgJcRz+HQBDAgAAAA==.',
Ly='Lyssena:BAAALgAECgUJBQABLgAFFAEJAQAKAAAAAA==.',
Ma='Macha:BAAALgADCgEJAQAAAA==.Madmartigan:BAAALgADCggJDgABLgAECgUJCgAKAAAAAA==.Mahangi:BAAALgADCgkJEAAAAA==.Mamimisan:BAABLgAECn8rAAIHAAkJHR/eCAD8AgAHAAkJHR/eCAD8AgAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAOAKsTAA==.Medios:BAAALgAECgkJDwAAAA==.Mehumah:BAAALgADCggJCAAAAA==.Melusine:BAAALgADCgcJBwAAAA==.Metalicfox:BAAALgAECgUJCgAAAA==.',
Mi='Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAABLgAECn8WAAMTAAcJoRh8EAClAQATAAcJoRh8EAClAQARAAMJ7AbNnwBWAAAAAA==.Mizkat:BAABLgAECn8gAAQTAAkJBhl3CQAYAgATAAkJBhl3CQAYAgAeAAEJSw7HPAA0AAARAAIJHA2bzwAvAAAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Mormra:BAABLgAECn8mAAMCAAgJQwtfXgBdAQACAAgJQwtfXgBdAQAfAAEJ1QGPOwAeAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQgAAgJlSV1CwBQAgAgAAcJ4iR1CwBQAgACAAYJliTyMADvAQAfAAIJ/SOqGgC3AAAAAA==.',
['Më']='Mërcy:BAAALgADCgcJBwAAAA==.',
Na='Naklus:BAAALgAECgUJBQAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAAALgAECggJEQABLgAECggJNQAFACwVAA==.Nekra:BAAALgAECgEJAQAAAA==.Nezot:BAAALgADCgkJDgAAAA==.',
Ni='Nitehawk:BAAALgADCgEJAQAAAA==.Nixilia:BAAALgADCgUJBQAAAA==.',
Nl='Nlani:BAAALgAECgYJCgAAAA==.',
Nu='Nuncadragon:BAAALgADCgQJBAAAAA==.Nuvi:BAAALgAECgYJCAAAAA==.',
Ol='Olivia:BAAALgAECgYJBgABLgAFFAgJGQAGACshAA==.',
Or='Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAAALgAECgYJEgAAAA==.',
Pa='Parne:BAAALgADCgUJBQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn8jAAIaAAgJ+Rm1FQA3AgAaAAgJ+Rm1FQA3AgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJBgAAAA==.Rajia:BAABLgAECn8uAAIhAAgJqhBoCgBvAQAhAAgJqhBoCgBvAQAAAA==.Ranron:BAAALgAECgMJAwAAAA==.Rassaphore:BAABLgAECn8UAAIXAAgJfB7DCQCDAgAXAAgJfB7DCQCDAgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAABLgAECn8gAAIiAAcJCBc5CwCAAQAiAAcJCBc5CwCAAQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgkJGgAGAJodAA==.Rionach:BAABLgAECn8uAAITAAgJjgfzKgC/AAATAAgJjgfzKgC/AAAAAA==.Ritsara:BAABLgAECn8UAAIWAAcJyQ2aHwDnAAAWAAcJyQ2aHwDnAAAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAKAAAAAA==.Rivon:BAABLgAECn8jAAMaAAkJgxgFGwAFAgAaAAgJWBcFGwAFAgAOAAEJagvAPwFCAAAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgUJBwABLgAECgkJHgAGAF0ZAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgMJBAAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAAALgAECgUJCgAAAA==.',
Se='Seanan:BAAALgAECgkJCgABLgAECgkJKQAOAHgdAA==.Seanx:BAABLgAECn8pAAMOAAkJeB1sGACTAgAOAAkJeB1sGACTAgAWAAYJhhLHHQD4AAAAAA==.',
Sh='Shenlong:BAABLgAFFH8GAAIQAAIJrhmcnwCYAAAQAAIJrhmcnwCYAAAAAA==.Shigurexx:BAABLgAECn8qAAMCAAkJGR3KFACDAgACAAkJGR3KFACDAgAfAAYJzxPgGADHAAAAAA==.Shoe:BAABLgAECn8/AAMDAAkJBhx9AgB2AgADAAkJBhx9AgB2AgAEAAcJyxCLIQCqAQAAAA==.Shootup:BAAALgADCgYJBgAAAA==.',
Si='Sigmandis:BAABLgAECn8UAAIOAAcJ8gNozADTAAAOAAcJ8gNozADTAAAAAA==.Siph:BAAALgAECgYJCQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgADCgcJFgAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sq='Squanchy:BAAALgADCgUJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJDQAAAA==.Surtrr:BAAALgAECgkJDwAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Ta='Taliadrin:BAAALgAECgIJAgAAAA==.Tamarins:BAABLgAECn8gAAIBAAcJgxgSFACGAQABAAcJgxgSFACGAQAAAA==.Taryeth:BAAALgADCgMJAwAAAA==.',
Te='Terkarakk:BAACLgAFFH8JAAITAAQJiBCICwDsAAATAAQJiBCICwDsAAAuAAQKfxwAAhMACQmwH8YDALwCABMACQmwH8YDALwCAAAA.',
Th='There:BAAALgAECgQJBQAAAA==.Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAAALgAECgQJCAAAAA==.',
To='Toom:BAABLgAECn8YAAICAAUJ5wrXlwDbAAACAAUJ5wrXlwDbAAAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgADCggJEAABLgAECggJNQAFACwVAA==.Trophyhubby:BAABLgAECn8jAAMUAAgJqAxdMgAaAQAUAAcJOwxdMgAaAQAdAAgJBQbLNgASAQAAAA==.',
Tu='Tuknark:BAAALgADCgYJBgAAAA==.Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgcJEAAAAA==.Tyeriel:BAACLgAFFH8eAAMQAAYJDhUuHgCYAQAQAAUJDhUuHgCYAQAYAAEJAABHQAAAAAAuAAQKfx8AAxAACQnZHtkiALQCABAACAn/HtkiALQCABgAAwkMGkYqANYAAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAYJHgAQAA4VAA==.',
Us='Usato:BAAALgAECgUJCgAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAAALgAECgUJEgAAAA==.Valvet:BAAALgADCgkJKwAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAABLgAECn8VAAMYAAcJ5xQjHQA9AQAYAAUJuxsjHQA9AQAQAAYJsQc7sQDoAAAAAA==.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIGAAcJHiTjJQBvAgAGAAcJHiTjJQBvAgAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAKAAAAAA==.',
Vy='Vylus:BAAALgAECgQJBwAAAA==.',
['Vá']='Vásh:BAAALgADCgkJEQAAAA==.',
We='Webjibaro:BAAALgAECgMJBgAAAA==.Weeblewobble:BAAALgADCggJCgAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCQAAAA==.William:BAABLgAECn8cAAICAAgJiSF/DwCtAgACAAgJiSF/DwCtAgAAAA==.Windee:BAAALgAECgYJEwAAAA==.',
Wr='Wrast:BAABLgAECn8bAAMfAAcJTwcMFwDZAAAfAAcJkwYMFwDZAAACAAQJWAdhoADIAAAAAA==.Wravyn:BAAALgAECgQJBAAAAA==.',
Xy='Xyara:BAACLgAFFH8JAAMNAAQJuw61BwCuAAAZAAMJgAgFZgDLAAANAAIJuhW1BwCuAAAuAAQKfyYABA0ACQk0HdcCAGoCAA0ACQk0HdcCAGoCABkABgmmEmJgAGkBACEAAwmgE2Y7AMYAAAAA.Xylaara:BAAALgAECgYJBgAAAA==.',
Ya='Yarine:BAAALgAECgIJAgAAAA==.',
Yo='Yoghurt:BAABLgAECn8xAAIjAAkJvx97CQCqAgAjAAkJvx97CQCqAgAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zaisum:BAAALgADCgYJBgAAAA==.Zalidus:BAACLgAFFH8JAAIkAAQJMwzPBgAZAQAkAAQJMwzPBgAZAQAuAAQKfxYAAiQACAmbG4kIAAcCACQACAmbG4kIAAcCAAAA.Zatika:BAABLgAECn8zAAMPAAkJHhgONAArAgAPAAkJKRUONAArAgAlAAcJ1xjmBgCgAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAABLgAECn8YAAIcAAUJXwZBVACNAAAcAAUJXwZBVACNAAAAAA==.',
Zm='Zmija:BAAALgAECgIJAgAAAA==.',
Zo='Zoeya:BAAALgADCgkJCQAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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
