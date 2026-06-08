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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Retribution','Warrior-Fury','Priest-Holy','Priest-Shadow','Monk-Windwalker','Monk-Brewmaster','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','Mage-Frost','DeathKnight-Frost','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Protection','Warlock-Affliction','Rogue-Subtlety','Shaman-Restoration','Hunter-Survival','Warrior-Arms','Druid-Restoration','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Monk-Mistweaver','Druid-Balance','Druid-Feral','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Blood','Druid-Guardian',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abert:BAAALgADCgUJBQAAAA==.Abilify:BAAALgAECgEJAgAAAA==.',
Ac='Acts:BAAALgAECgEJAQAAAA==.',
Ad='Adalinda:BAAALgADCgkJCgABLgAFFAUJGAABABkfAA==.',
Ag='Agnor:BAABLgAECn81AAICAAgJVxr8PAAFAgACAAgJVxr8PAAFAgAAAA==.',
Al='Alatir:BAAALgADCgcJEQAAAA==.Alticus:BAAALgADCgEJAQAAAA==.',
An='Andrew:BAAALgAECgEJAQABLgAFFAUJDgADANEWAA==.Anien:BAAALgAECgYJEQAAAA==.Anklemauler:BAAALgAECgYJBgAAAA==.Anthem:BAAALgAECgYJBgAAAA==.Antibubble:BAABLgAECn8gAAICAAkJYB4DIQB8AgACAAkJYB4DIQB8AgAAAA==.Antipeta:BAAALgAECgEJAgAAAA==.Anwal:BAACLgAFFH8YAAIBAAUJGR/2DQDIAQABAAUJGR/2DQDIAQAuAAQKfy0AAwEACQlXHLsiAAkCAAEACAlIG7siAAkCAAQACQlCDJNxAIABAAAA.',
Ar='Argus:BAABLgAECn8vAAIFAAgJHCNZCQDFAgAFAAgJHCNZCQDFAgAAAA==.Arithana:BAABLgAFFH8IAAMGAAQJaAPNIACfAAAGAAQJaAPNIACfAAAHAAEJIAdQOgA3AAABLgAFFAQJCAAIAHAJAA==.Arithfury:BAAALgAECgIJAgABLgAFFAQJCAAIAHAJAA==.Arithkick:BAACLgAFFH8IAAMIAAQJcAn/JAC2AAAIAAMJ6wr/JAC2AAAJAAMJyQWoPQChAAAuAAQKfyEAAgkACAlFGW8UAGsCAAkACAlFGW8UAGsCAAAA.',
As='Asayo:BAAALgAECgUJEgAAAA==.Asherie:BAAALgAECgQJCQABLgAECggJFAAGAO0RAA==.Aske:BAABLgAECn8kAAIKAAgJIxSPTwCoAQAKAAgJIxSPTwCoAQAAAA==.Astolan:BAAALgAECgEJAgAAAA==.',
At='Atonga:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgcJEQAAAA==.',
Az='Azuresun:BAABLgAECn8fAAILAAkJEAsuMwBhAQALAAkJEAsuMwBhAQAAAA==.',
Ba='Ballak:BAABLgAECn8ZAAIMAAcJzRGWVABrAQAMAAcJzRGWVABrAQAAAA==.Barlee:BAAALgADCgEJAQABLgAFFAIJAQANAAAAAA==.',
Be='Beatin:BAAALgAECgUJCgAAAA==.Belenzr:BAAALgADCgEJAQAAAA==.',
Bi='Bigdikley:BAAALgAECgYJEQAAAA==.Biggtater:BAAALgADCgUJBQAAAA==.',
Bl='Bloodywake:BAAALgAECgMJAwAAAA==.Bloopydoo:BAABLgAECn8VAAIOAAYJNggI0ADsAAAOAAYJNggI0ADsAAAAAA==.Blort:BAAALgADCgEJAQAAAA==.Bláckbird:BAABLgAECn8bAAIMAAkJMhotTwCoAQAMAAkJMhotTwCoAQAAAA==.',
Bo='Bohliang:BAAALgADCgkJEAAAAA==.Boltywolty:BAAALgAECgYJCgAAAA==.Borim:BAAALgAECgEJAQAAAA==.',
Br='Brandymae:BAAALgAECgMJBQAAAA==.Branholy:BAAALgADCgEJAQAAAA==.Brbpoopin:BAAALgAECgYJBgAAAA==.Brotems:BAAALgAECgkJAQAAAA==.Bruwdflight:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebuster:BAAALgAECgYJDAABLgAECgkJIAACAGAeAA==.Bumwarrior:BAAALgADCgEJAQAAAA==.Burnphase:BAAALgADCgQJBwAAAA==.',
By='Byrdreisyl:BAAALgAECgQJBAAAAA==.',
Ca='Caosgonewild:BAAALgAECgUJBQAAAA==.',
Ce='Celestyal:BAAALgADCgMJAwAAAA==.',
Ch='Chestie:BAABLgAECn8hAAMCAAkJdR0hSwDaAQACAAgJ6x0hSwDaAQAPAAIJOBoTJQCRAAAAAA==.Chubbychi:BAAALgAECgIJAgAAAA==.',
Ci='Cinde:BAAALgADCgMJAwABLgAFFAQJCwAMADscAA==.Cindy:BAACLgAFFH8LAAIMAAQJOxx8JQBcAQAMAAQJOxx8JQBcAQAuAAQKfyQAAwwACQkOHr0UAKICAAwACQkOHr0UAKICABAAAQneBZ2RACkAAAAA.Cindyx:BAAALgAECgYJDwABLgAFFAQJCwAMADscAA==.',
Co='Coast:BAABLgAECn8VAAIRAAgJ1wffFgDgAAARAAgJ1wffFgDgAAAAAA==.Coldlock:BAAALgAECggJCAABLgAECgkJMAASAAUaAA==.Coldsore:BAABLgAECn8wAAQSAAkJBRq8CQAlAgASAAkJ4Rm8CQAlAgABAAYJ+wbfUADqAAAEAAMJMQcHHwGDAAAAAA==.Coldwar:BAAALgADCgcJBwAAAA==.Conjuremoney:BAAALgADCgEJAQAAAA==.Cootpal:BAABLgAECn8+AAIEAAkJDB71FwCqAgAEAAkJDB71FwCqAgAAAA==.Costcohotdog:BAAALgADCgMJAwAAAA==.',
Cr='Crazyloon:BAAALgAECgUJCQAAAA==.Crewmix:BAAALgAECgEJAQAAAA==.Croe:BAAALgADCgMJAwAAAA==.',
Cy='Cynawyne:BAAALgAECgEJAQAAAA==.Cynthea:BAAALgAECgkJCgAAAA==.',
Da='Dahm:BAAALgAECgMJBgAAAA==.Dalasaurs:BAACLgAFFH8FAAIFAAIJ/BqxOgChAAAFAAIJ/BqxOgChAAAuAAQKfzAAAgUACAmTGKMoABoCAAUACAmTGKMoABoCAAAA.Dalasnipus:BAAALgADCgMJAwAAAA==.Dalbear:BAAALgADCgYJCQAAAA==.Darkpallas:BAAALgAECgYJCAAAAA==.Darkprophetc:BAABLgAECn8sAAIOAAkJiQtbaQCiAQAOAAkJiQtbaQCiAQAAAA==.',
De='Deathfyre:BAAALgADCgQJBAAAAA==.Deluun:BAAALgADCgkJCQAAAA==.Demious:BAABLgAECn8YAAIMAAgJHCDKHABtAgAMAAgJHCDKHABtAgAAAA==.Demiurge:BAEALgAECgkJEAAAAA==.Demonfister:BAACLgAFFH8JAAIFAAMJwQyCNQDFAAAFAAMJwQyCNQDFAAAuAAQKfygAAgUACQn+G/cLAKMCAAUACQn+G/cLAKMCAAAA.Demonkiller:BAABLgAECn8bAAITAAYJHAawPQCtAAATAAYJHAawPQCtAAAAAA==.Denastiest:BAABLgAECn8rAAIDAAgJ+Q8yWwBqAQADAAgJ+Q8yWwBqAQAAAA==.Denji:BAAALgAECggJEAAAAA==.Devvmonk:BAAALgAECgcJEwAAAA==.',
Di='Dindaratwo:BAAALgAECgEJAQAAAA==.',
Do='Doe:BAABLgAECn8pAAMUAAcJmyM7BQBKAgAUAAcJmyM7BQBKAgATAAMJhhD+UgCdAAAAAA==.Dokta:BAAALgAFFAEJAQAAAA==.',
Dr='Draflex:BAAALgAECgMJBAAAAA==.Drathal:BAABLgAECn8vAAIEAAkJoQQGrQAYAQAEAAkJoQQGrQAYAQAAAA==.Drjay:BAAALgADCgkJCwAAAA==.',
Dv='Dvergar:BAAALgAECgYJDAAAAA==.',
Ea='Eatshrooms:BAAALgAECgMJAwAAAA==.',
Ed='Edd:BAAALgAECgQJBAAAAA==.Eddiedean:BAAALgAECgYJBgAAAA==.',
El='Elfgonewild:BAAALgAECgUJCgAAAA==.Ellessra:BAABLgAECn8kAAIOAAgJxAIt0QDqAAAOAAgJxAIt0QDqAAAAAA==.Elnegrouno:BAABLgAECn8fAAIVAAcJfR/SCgBjAgAVAAcJfR/SCgBjAgAAAA==.Eloper:BAAALgAFFAEJAQAAAA==.',
Em='Emotank:BAAALgAECgMJBAAAAA==.',
Er='Eragone:BAAALgAECgMJBAAAAA==.',
Et='Etoro:BAAALgADCgEJAgAAAA==.',
Ev='Evissier:BAACLgAFFH8OAAIWAAQJZh+fAgBtAQAWAAQJZh+fAgBtAQAuAAQKfx0AAhYACAmuIAcBAAIDABYACAmuIAcBAAIDAAAA.',
Ex='Exsequor:BAACLgAFFH8RAAISAAQJIiGMAgCDAQASAAQJIiGMAgCDAQAuAAQKfx0AAxIABgkLIy4SAJgBABIABgkLIy4SAJgBAAQAAQlyB/tQASsAAAAA.',
Ez='Ezuras:BAAALgADCgIJAgAAAA==.',
Fa='Faeyri:BAABLgAECn8rAAILAAgJnxvzFQAqAgALAAgJnxvzFQAqAgAAAA==.Fassandin:BAAALgAECgIJAgAAAA==.',
Fe='Felli:BAAALgAECgEJAQAAAA==.',
Fi='Fishermon:BAAALgAECgUJCAAAAA==.',
Fl='Flagfarmer:BAABLgAECn8dAAIBAAYJMSY0EACNAgABAAYJMSY0EACNAgAAAA==.Flataxe:BAAALgAECgMJAwAAAA==.Flixunt:BAAALgADCgEJAQAAAA==.',
Fo='Foidepas:BAAALgAECgcJDQAAAA==.Fourid:BAAALgAECgQJCgAAAA==.Foxannee:BAAALgAECgMJBgAAAA==.',
Fr='Freezyweezy:BAACLgAFFH8LAAIOAAQJ4RsCRgBPAQAOAAQJ4RsCRgBPAQAuAAQKfx8AAg4ACQnoI5QbAK8CAA4ACQnoI5QbAK8CAAAA.Frostfirer:BAAALgAECgYJAgAAAA==.',
Fu='Fudgeyenuh:BAAALgAECgkJCQAAAA==.',
Fy='Fyrewar:BAAALgAECgMJAwAAAA==.',
['Fú']='Fúry:BAAALgAECgcJBwAAAA==.',
Ga='Gallyn:BAABLgAFFH8KAAIXAAMJmhvPIgD3AAAXAAMJmhvPIgD3AAAAAA==.Gamm:BAAALgADCgcJEQAAAA==.Garaal:BAAALgAECgcJDQAAAA==.',
Ge='Gerel:BAAALgAECgYJBgAAAA==.',
Gi='Ginyu:BAAALgAECgIJAgAAAA==.',
Gl='Glacierrock:BAAALgADCgQJCgAAAA==.Gloria:BAABLgAECn8hAAIYAAkJ1AlUSQB8AQAYAAkJ1AlUSQB8AQAAAA==.',
Go='Gooblicious:BAAALgAECgEJAQAAAA==.Gori:BAAALgAECgIJAgAAAA==.',
Gr='Grail:BAABLgAECn8eAAIEAAcJ4A2AmwAzAQAEAAcJ4A2AmwAzAQAAAA==.Grelvisse:BAAALgAECgMJBQAAAA==.Grippywippy:BAAALgADCgYJBAAAAA==.',
Gu='Gudren:BAAALgADCgEJAQAAAA==.Guimon:BAAALgAECgMJBAAAAA==.Gunslinger:BAAALgAECgEJAQAAAA==.',
Gw='Gwenie:BAABLgAECn8mAAIKAAkJYhE7OgDsAQAKAAkJYhE7OgDsAQAAAA==.',
Ha='Halenicion:BAAALgAFFAEJAQAAAA==.Hauntfrost:BAAALgAECgEJAQAAAA==.Hazél:BAAALgADCgYJBgAAAA==.',
He='Helix:BAAALgAECgIJAgAAAA==.',
Hi='Hippoltyos:BAABLgAECn8sAAIGAAkJnA4TJACWAQAGAAkJnA4TJACWAQAAAA==.',
Ho='Honestlee:BAAALgAECgQJBAAAAA==.Honourablee:BAAALgAECgYJCQAAAA==.Hortzul:BAAALgADCgMJAwABLgAFFAUJGAABABkfAA==.Hotsaucce:BAAALgADCgEJAQAAAA==.Hotstheboss:BAAALgADCgYJBgAAAA==.Houe:BAAALgADCgUJCAAAAA==.',
Hu='Huffle:BAAALgAECgEJAQAAAA==.Huntardiness:BAABLgAECn8gAAQZAAgJrhGfIwB8AQAZAAgJFgqfIwB8AQAMAAcJ5RJLUAB4AQAQAAEJ7g6pOQAxAAAAAA==.Hunterd:BAAALgADCgEJAQAAAA==.',
Hy='Hymnals:BAACLgAFFH8LAAIFAAQJVCYFCAC+AQAFAAQJVCYFCAC+AQAuAAQKfxcAAwUACAlRJO4OANwCAAUACAlRJO4OANwCABoAAgkHGipPAIUAAAAA.',
Ia='Ianmaris:BAAALgADCgQJBQAAAA==.',
Ic='Icealia:BAAALgAECgEJAQABLgAFFAQJDwAbAL4HAA==.Icelandite:BAAALgAECgYJBgAAAA==.',
Iv='Ive:BAABLgAECn8fAAQRAAkJ/CF2EQDBAQARAAcJzBp2EQDBAQAKAAgJGCKpVwCRAQAWAAIJHBD0JABeAAAAAA==.',
Ja='Jackburton:BAAALgAECgIJAgAAAA==.Jaddie:BAAALgAECggJEQAAAA==.Jarnunvosk:BAABLgAECn8iAAMcAAgJOhUtDQD3AQAcAAgJOhUtDQD3AQAdAAEJbwOAlQAhAAAAAA==.Jasmindinn:BAAALgADCgcJDgAAAA==.Jayber:BAABLgAECn8iAAMeAAcJSg5oLwBUAQAeAAcJSg5oLwBUAQAHAAEJmQAClAAHAAAAAA==.',
Je='Jezadora:BAAALgADCgEJAQAAAA==.',
Jo='Jolkom:BAAALgAECgMJBgABLgAECggJFgAVAEAcAA==.',
Ju='Julantis:BAAALgAECgYJBgAAAA==.',
Ka='Kadri:BAAALgAFFAEJAQAAAA==.Kaffee:BAABLgAECn80AAISAAkJ7A9bEgCVAQASAAkJ7A9bEgCVAQAAAA==.Kamakaz:BAAALgAECgcJCQAAAA==.Kamasdruid:BAAALgAECgMJBQAAAA==.Kamasmage:BAAALgADCgcJBwAAAA==.Kamasmonk:BAAALgAECgYJBwAAAA==.Kamasux:BAAALgADCgYJBwAAAA==.Kandi:BAAALgADCgQJCgAAAA==.Kaviryon:BAAALgAECgEJAwAAAA==.Kaywhy:BAABLgAECn8UAAIHAAgJVxvtNQA2AQAHAAgJVxvtNQA2AQAAAA==.',
Ki='Kichack:BAABLgAECn8rAAMIAAgJ4B87DAB2AgAIAAgJ4B87DAB2AgAfAAYJDxRePQBgAQAAAA==.Kitarvie:BAAALgAECgEJAgAAAA==.',
Kj='Kjdh:BAABLgAECn8oAAITAAgJSCL2CACOAgATAAgJSCL2CACOAgAAAA==.',
Kl='Kladuum:BAAALgADCgYJGQAAAA==.',
Kn='Knuckles:BAABLgAECn8UAAIFAAgJLhZVIADnAQAFAAgJLhZVIADnAQAAAA==.',
Ko='Kogun:BAAALgAECgQJBAAAAA==.Kowala:BAABLgAECn8cAAIgAAkJvw/AJQCRAQAgAAkJvw/AJQCRAQAAAA==.Kowpox:BAAALgADCgkJCgAAAA==.Kozalth:BAAALgADCgEJAgAAAA==.',
Kr='Krabi:BAAALgADCgYJCwAAAA==.Kranks:BAAALgAECgEJAQAAAA==.Kreios:BAAALgAECgYJBwAAAA==.Krelo:BAABLgAECn8kAAIYAAgJ6x1HEwCmAgAYAAgJ6x1HEwCmAgAAAA==.',
Kt='Ktom:BAABLgAECn8zAAILAAkJGiWvAgBDAwALAAkJGiWvAgBDAwAAAA==.',
Ku='Kurimbory:BAAALgAECgUJBQAAAA==.',
Ky='Kyruan:BAAALgADCgEJAQAAAA==.',
['Ký']='Kýlê:BAABLgAECn8ZAAMMAAgJmwdIUgByAQAMAAgJmwdIUgByAQAQAAYJ6gLLWQDdAAAAAA==.',
La='Lancelot:BAAALgAECgYJCAAAAA==.Lanthuil:BAAALgAECgQJBAAAAA==.',
Li='Lifepooll:BAAALgAECgEJAQABLgAFFAIJAQANAAAAAA==.Lilyselah:BAAALgADCgYJBwAAAA==.Littlelocky:BAAALgADCgcJEwAAAA==.Liv:BAABLgAECn8UAAIHAAgJtQu6LgBsAQAHAAgJtQu6LgBsAQAAAA==.',
Ll='Llamallab:BAAALgADCgcJBwAAAA==.',
Lo='Lostmyghoul:BAACLgAFFH8GAAICAAMJTBkWegAAAQACAAMJTBkWegAAAQAuAAQKfycAAgIACQkoH4AUAMUCAAIACQkoH4AUAMUCAAAA.Lostwarrior:BAAALgAECgUJBQAAAA==.Louhi:BAAALgAECgIJAwABLgAECgMJCAANAAAAAA==.',
Lu='Luglug:BAAALgAECgEJAQAAAA==.Lunar:BAABLgAECn8kAAIgAAkJkR8FBwDdAgAgAAkJkR8FBwDdAgAAAA==.Lunasea:BAAALgAECgMJAwAAAA==.',
Ly='Lysol:BAAALgADCgUJBQAAAA==.Lystat:BAAALgAECgUJCwAAAA==.',
Ma='Magicfungus:BAAALgADCgUJCQAAAA==.Magno:BAAALgADCgIJAgAAAA==.Magra:BAABLgAECn8YAAIOAAYJnwzUvQAIAQAOAAYJnwzUvQAIAQAAAA==.Magêyalook:BAABLgAECn8nAAIOAAgJthlkPAAiAgAOAAgJthlkPAAiAgAAAA==.Mangel:BAAALgADCgYJBgAAAA==.Manzz:BAAALgAECgUJCgAAAA==.Marcelline:BAAALgADCgYJEgAAAA==.Mattob:BAAALgADCgcJDAAAAA==.Maximus:BAAALgADCgkJEAAAAA==.Maznificent:BAAALgADCggJDQAAAA==.Mazyme:BAAALgADCgQJCQAAAA==.',
Me='Meandmypal:BAACLgAFFH8UAAIZAAgJzBkfAQBSAgAZAAgJzBkfAQBSAgAuAAQKfy4AAhkACQk4JrsAAH4DABkACQk4JrsAAH4DAAAA.Mello:BAABLgAECn8uAAIaAAkJIBy4BQCeAgAaAAkJIBy4BQCeAgAAAA==.Mesteris:BAAALgADCgYJBgAAAA==.',
Mi='Midiane:BAAALgAECgEJAQAAAA==.Milim:BAAALgAFFAIJAgAAAA==.Mirba:BAABLgAECn8nAAIMAAgJZxRbQgDPAQAMAAgJZxRbQgDPAQAAAA==.',
Mo='Mongo:BAABLgAECn8wAAICAAkJ/R9SDwDpAgACAAkJ/R9SDwDpAgAAAA==.Monochrome:BAAALgAECgIJAgAAAA==.Monsterdeath:BAAALgAECgIJAgAAAA==.Moreicepls:BAABLgAECn8bAAIOAAgJ+wlWjgBVAQAOAAgJ+wlWjgBVAQAAAA==.Morené:BAAALgAECgQJBgAAAA==.Moxxee:BAAALgADCgcJGAAAAA==.',
Mu='Mushhmelu:BAAALgAECgEJAQAAAA==.',
My='Myiko:BAAALgAECgQJBAAAAA==.Mytharu:BAAALgADCgMJAwAAAA==.',
Na='Nareík:BAACLgAFFH8KAAIDAAQJBQa4VQDaAAADAAQJBQa4VQDaAAAuAAQKfyAAAgMACAlZEmhVAKMBAAMACAlZEmhVAKMBAAAA.',
Ne='Neutrallee:BAAALgAECgEJAQAAAA==.Newa:BAAALgAECgUJCQAAAA==.',
Ni='Nightwater:BAACLgAFFH8PAAIbAAQJvgcwNgDQAAAbAAQJvgcwNgDQAAAuAAQKfykABBsACQmLF7olABYCABsACQmLF7olABYCACEAAglfCRQ8AFgAACAAAQmKCL+LACwAAAAA.',
['Né']='Nébulien:BAABLgAECn8dAAIiAAgJNx7oCQAQAgAiAAgJNx7oCQAQAgAAAA==.',
Ok='Okkok:BAABLgAECn8XAAIOAAYJ8hCIwABjAQAOAAYJ8hCIwABjAQAAAA==.',
Or='Orchop:BAABLgAECn8YAAIiAAYJgQlUHwDsAAAiAAYJgQlUHwDsAAAAAA==.Orkrist:BAABLgAECn8XAAIMAAcJpRLgYgBzAQAMAAcJpRLgYgBzAQAAAA==.',
Oz='Oz:BAAALgADCgUJBQAAAA==.',
Pa='Paado:BAAALgADCgUJBQAAAA==.Pantryraider:BAAALgAECgkJAgAAAA==.Patriqt:BAAALgAECgEJAQAAAA==.Paulterian:BAAALgAECgYJBQAAAA==.Paymeforpi:BAAALgAECgMJAwAAAA==.',
Ph='Phelaeshio:BAABLgAECn8eAAICAAkJOxwFJABtAgACAAkJOxwFJABtAgAAAA==.',
Po='Poam:BAAALgAECgUJBQAAAA==.Poldalina:BAAALgADCgcJGAAAAA==.Power:BAABLgAECn8UAAICAAcJQQoQnQAnAQACAAcJQQoQnQAnAQAAAA==.',
Pr='Primevil:BAAALgADCgQJBAAAAA==.Prosthetic:BAAALgAECgEJAQAAAA==.Proverbs:BAAALgAFFAEJAQAAAA==.',
Pu='Pumplord:BAAALgAECgcJEQAAAA==.Punchyou:BAAALgADCgEJAQAAAA==.',
['På']='Pårts:BAAALgAFFAIJAQAAAA==.',
['Pù']='Pùff:BAAALgAECgUJCQAAAA==.',
Qu='Quazeemoto:BAAALgAECgEJAQAAAA==.',
Ra='Raeyna:BAAALgAECgIJAwABLgAECgkJHwARAPwhAA==.Raffern:BAAALgAECgMJAwAAAA==.Rainknuckles:BAABLgAECn8lAAIBAAgJVRZNJADZAQABAAgJVRZNJADZAQAAAA==.Rayshano:BAABLgAECn8WAAISAAcJBRreEQCbAQASAAcJBRreEQCbAQAAAA==.',
Re='Recklessone:BAAALgAECgEJAQAAAA==.Resia:BAAALgADCgQJAQAAAA==.Revocsid:BAAALgADCgcJEwAAAA==.Rezza:BAAALgADCgEJAQAAAA==.',
Ri='Rikka:BAAALgADCgMJAwAAAA==.',
Ro='Rottingtree:BAAALgAECgYJEAAAAA==.',
Ru='Rustynails:BAABLgAECn84AAIjAAkJGSS0AAAjAwAjAAkJGSS0AAAjAwAAAA==.',
Sa='Saffire:BAAALgADCgcJBwAAAA==.Salina:BAAALgAECgEJAQAAAA==.Saly:BAAALgADCgIJAQABLgADCggJDgANAAAAAA==.Samwitch:BAAALgAECgQJCwAAAA==.Sappaho:BAAALgADCgYJBwAAAA==.Satheirel:BAAALgADCgYJBwAAAA==.Savanti:BAAALgAECgEJAQAAAA==.Sazzul:BAAALgAECggJEgAAAA==.',
Sc='Scott:BAACLgAFFH8VAAIVAAQJvCM+AwBiAQAVAAQJvCM+AwBiAQAuAAQKfyMAAhUACAmXJNQDABMDABUACAmXJNQDABMDAAEuAAUUBQkLACQAzxAA.Screamor:BAAALgAECgEJAQAAAA==.Screams:BAAALgADCgEJAQAAAA==.Screamz:BAABLgAECn8eAAITAAYJ6RhwIwBJAQATAAYJ6RhwIwBJAQAAAA==.Scynx:BAAALgAECggJEQAAAA==.',
Se='Seaka:BAABLgAECn8vAAQgAAkJ8RciEgA8AgAgAAkJ8RciEgA8AgAbAAcJYRbIPQCSAQAlAAIJxg4NVABVAAAAAA==.Sebas:BAAALgAECgEJAQAAAA==.Sent:BAAALgADCggJDgAAAA==.Serion:BAAALgAECgQJBQABLgAFFAEJAQANAAAAAA==.Sernix:BAABLgAECn8nAAIYAAgJKxzNFACYAgAYAAgJKxzNFACYAgAAAA==.',
Sh='Shadegrim:BAAALgAECgQJBgAAAA==.Shaeia:BAACLgAFFH8IAAILAAMJzxCEEQDcAAALAAMJzxCEEQDcAAAuAAQKfx8AAgsACQn0HLcNAMYCAAsACQn0HLcNAMYCAAAA.Shambat:BAAALgADCgYJBgAAAA==.Shangi:BAAALgADCgMJAgABLgAFFAQJEQASACIhAA==.Shekinah:BAAALgADCgEJAQAAAA==.Shen:BAAALgAECgQJBgAAAA==.',
Si='Siatrath:BAAALgAECgEJAQABLgAFFAQJEQASACIhAA==.Sivtekeda:BAAALgAECgQJCQAAAA==.',
Sk='Sktibrew:BAACLgAFFH8TAAIJAAYJgSF1BACRAQAJAAYJgSF1BACRAQAuAAQKfxoAAgkACAmDHRMRAI8CAAkACAmDHRMRAI8CAAAA.',
Sl='Slamin:BAAALgADCggJDwAAAA==.Slash:BAABLgAECn8kAAITAAkJxReWEgD1AQATAAkJxReWEgD1AQAAAA==.Slyavane:BAABLgAECn84AAQWAAkJqBU+BgAKAgAWAAkJqBU+BgAKAgARAAcJawf6GQDKAAAKAAQJWwQE4QCYAAAAAA==.Slyice:BAAALgAECgEJBgAAAA==.',
Sm='Smokess:BAACLgAFFH8NAAMSAAUJtRnZBAAzAQASAAUJtRnZBAAzAQAEAAMJDxQiFgD7AAAuAAQKfx8AAxIACAnkIXoGAHICABIACAnKHXoGAHICAAQACAlAGZZKAAMCAAEuAAUUBgkJABUAdQoA.',
Sn='Snowwind:BAABLgAECn8cAAIGAAcJFAsANgAaAQAGAAcJFAsANgAaAQAAAA==.',
So='Solthea:BAAALgAECgkJBwAAAA==.Solymar:BAAALgAECgkJBwAAAA==.Sonar:BAABLgAECn8pAAIMAAkJ8h9IFwCPAgAMAAkJ8h9IFwCPAgAAAA==.Sonasai:BAAALgADCgcJGAAAAA==.Sonnybear:BAAALgADCgUJEQAAAA==.Soulhatcher:BAAALgAECgQJEAAAAA==.Soxs:BAABLgAECn8qAAMfAAkJNBriDgCgAgAfAAkJNBriDgCgAgAIAAIJTg+9bQBnAAAAAA==.',
Sp='Spookymoo:BAAALgADCgQJBAAAAA==.',
St='Stabbywabby:BAAALgAECgYJBwAAAA==.Stardris:BAABLgAECn8bAAIDAAgJawKIqAC/AAADAAgJawKIqAC/AAAAAA==.Stenaris:BAAALgAECgIJAwAAAA==.Stompygnome:BAAALgAECggJEgAAAA==.Strooth:BAAALgADCgQJBAAAAA==.',
Ta='Talavel:BAAALgADCgIJAgAAAA==.Tartanus:BAABLgAECn8tAAIDAAkJXxdBLAALAgADAAkJXxdBLAALAgAAAA==.Taulogit:BAAALgAECgIJAgAAAA==.Tayzetv:BAAALgAECgMJAwABLgAFFAMJBwAiAGcOAA==.',
Te='Teramiah:BAAALgADCgcJFAAAAA==.',
Th='Thanestra:BAAALgAECgkJBwAAAA==.Theadona:BAABLgAECn8nAAIEAAgJNR08KgBOAgAEAAgJNR08KgBOAgAAAA==.Thorall:BAAALgADCgkJDwAAAA==.Thylight:BAAALgADCgMJAwAAAA==.',
Ti='Tikcus:BAAALgADCgcJEAAAAA==.Tils:BAAALgADCggJDwAAAA==.Tippy:BAACLgAFFH8aAAMPAAUJAh1XBwBaAQAPAAQJAh1XBwBaAQAkAAIJuQGePwAgAAAuAAQKfzYABA8ACQloIcsCAMACAA8ACQkQIcsCAMACAAIAAwkNBskDAXAAACQAAgl1DqdGAGYAAAAA.',
To='Toastedwings:BAAALgADCgcJDwAAAA==.Tombstone:BAAALgAECgYJEgAAAA==.Toowongfoo:BAACLgAFFH8ZAAIIAAUJuh8TCgBuAQAIAAUJuh8TCgBuAQAuAAQKfycAAggACQm4I0cDACgDAAgACQm4I0cDACgDAAAA.',
Tr='Trewer:BAAALgADCgIJAgAAAA==.Trisara:BAABLgAECn81AAIgAAkJrwhTMgBDAQAgAAkJrwhTMgBDAQAAAA==.',
Tu='Tunechi:BAAALgAECgEJAQAAAA==.',
Ty='Tygrana:BAAALgAECgEJAQAAAA==.Tyradora:BAAALgAECgEJAQAAAA==.Tytannia:BAAALgADCgEJAQAAAA==.',
['Tö']='Töteman:BAABLgAECn8pAAILAAcJlBbXKQCUAQALAAcJlBbXKQCUAQAAAA==.',
['Tÿ']='Tÿtann:BAAALgAECgMJAwAAAA==.',
Um='Umbranecros:BAAALgAECgEJBQAAAA==.',
Un='Unbok:BAAALgAECgkJAQAAAA==.Underdog:BAABLgAECn8cAAIQAAgJuBT9DQBxAQAQAAgJuBT9DQBxAQAAAA==.',
Up='Upthere:BAAALgADCgQJBAABLgAECgcJEwANAAAAAA==.',
Va='Vaern:BAABLgAECn8dAAIhAAcJhBy/DADbAQAhAAcJhBy/DADbAQAAAA==.Vagindivin:BAAALgAECgcJDwAAAA==.Valrie:BAAALgAECgMJAwAAAA==.Valyteil:BAAALgAECgQJBAAAAA==.',
Ve='Venngance:BAABLgAECn8rAAQPAAgJnCOfAwCZAgAPAAgJTiCfAwCZAgAkAAUJTSTVFwCdAQACAAYJExSjpwAXAQAAAA==.',
Vi='Virus:BAAALgAECggJEQAAAA==.Vitner:BAAALgADCgMJAwAAAA==.',
Vo='Voidkity:BAAALgAECgQJBwAAAA==.Voidpriest:BAAALgAECgEJAQAAAA==.',
Vy='Vyrlet:BAAALgAECgEJAQAAAA==.',
Wa='Walberson:BAAALgADCgYJBgAAAA==.Warfield:BAABLgAECn8fAAMlAAkJYxNSEgC4AQAlAAkJYxNSEgC4AQAhAAEJWgNQWgAcAAAAAA==.',
Wf='Wfbot:BAAALgAECgEJAQAAAA==.',
Wh='Whosbondt:BAAALgAECgYJBgAAAA==.',
Wi='Winafred:BAAALgAECgEJAQAAAA==.Wittwicky:BAAALgAECgEJAQAAAA==.',
Wk='Wkeyonly:BAABLgAECn8fAAIDAAkJYRUZXABoAQADAAkJYRUZXABoAQAAAA==.',
Wo='Woody:BAAALgADCgUJBQAAAA==.Wooter:BAAALgADCgYJDAAAAA==.Worthy:BAAALgAECgkJAwAAAA==.',
Wr='Wrathsome:BAABLgAECn8rAAIbAAgJVxXFKgD3AQAbAAgJVxXFKgD3AQAAAA==.',
Wu='Wunderbilly:BAAALgADCgEJAQAAAA==.',
['Wí']='Wísp:BAAALgAECgEJAQAAAA==.',
Xl='Xloon:BAAALgAECgEJAQAAAA==.',
Xy='Xypherus:BAAALgADCgkJDQAAAA==.',
['Xá']='Xándarl:BAAALgAECgMJBAAAAA==.',
Ya='Yakoda:BAAALgADCgUJBQAAAA==.Yaldabaoth:BAEALgAECgcJBQABLgAECgkJEAANAAAAAA==.Yanza:BAAALgAECgIJAgAAAA==.',
Ye='Yello:BAAALgADCgkJEgAAAA==.',
Za='Zaio:BAAALgAECgYJCQAAAA==.Zarkus:BAAALgAECgQJEgAAAA==.',
Ze='Zelphi:BAAALgAECgQJCAAAAA==.Zenha:BAAALgADCgEJAQAAAA==.Zephaadella:BAAALgAECgEJAQAAAA==.',
Zh='Zhuzi:BAAALgADCgkJDwAAAA==.',
Zs='Zshmokez:BAACLgAFFH8JAAIVAAYJdQrUEgD/AAAVAAYJdQrUEgD/AAAuAAQKfxoAAhUACQlFHhEGAKUCABUACQlFHhEGAKUCAAAA.',
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
