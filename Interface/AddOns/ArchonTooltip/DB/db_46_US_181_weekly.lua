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

local lookup = {'Paladin-Holy','Rogue-Subtlety','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Retribution','Warrior-Fury','Priest-Holy','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','Mage-Frost','DeathKnight-Frost','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','DemonHunter-Havoc','Monk-Mistweaver','DemonHunter-Vengeance','Warrior-Protection','Warlock-Affliction','Shaman-Restoration','Hunter-Survival','Warrior-Arms','Druid-Restoration','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Druid-Balance','Druid-Feral','Shaman-Enhancement','Rogue-Outlaw','Druid-Guardian','DeathKnight-Blood',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abert:BAAALgADCgUJBQAAAA==.Abilify:BAAALgAECgEJAgAAAA==.',
Ac='Acts:BAAALgAFFAEJAQAAAA==.',
Ad='Adalinda:BAAALgADCgkJCgABLgAFFAUJGQABABkfAA==.',
Ae='Aegeus:BAAALgADCgEJAQABLgAFFAMJEAACAC4dAA==.',
Ag='Agnor:BAABLgAECn81AAIDAAgJVxrZQAAAAgADAAgJVxrZQAAAAgAAAA==.',
Al='Alatir:BAAALgADCgkJFAAAAA==.Altchoice:BAAALgAECgQJBAABLgAECggJJQABAFUWAA==.Alticus:BAAALgADCgEJAQAAAA==.',
An='Andrew:BAAALgAECgEJAQABLgAFFAYJEgAEAIIUAA==.Anien:BAAALgAECgYJEQAAAA==.Anklemauler:BAAALgAECgYJBgAAAA==.Anthem:BAAALgAECgYJBgAAAA==.Antibubble:BAABLgAECn8gAAIDAAkJYB65IwB3AgADAAkJYB65IwB3AgAAAA==.Antipeta:BAAALgAECgEJAgAAAA==.Anwal:BAACLgAFFH8ZAAIBAAUJGR9YEAC5AQABAAUJGR9YEAC5AQAuAAQKfy0AAwEACQlXHLsiAAkCAAEACAlIG7siAAkCAAUACQlCDDN5AHwBAAAA.',
Ar='Argus:BAABLgAECn8wAAIGAAgJHCNgCgC+AgAGAAgJHCNgCgC+AgAAAA==.Arithana:BAABLgAFFH8IAAMHAAQJaAMOJACbAAAHAAQJaAMOJACbAAAIAAEJIAcGQAA3AAABLgAFFAQJDAAJAOEOAA==.Arithfury:BAAALgAECgIJAgABLgAFFAQJDAAJAOEOAA==.Arithkick:BAACLgAFFH8MAAMJAAQJ4Q4jKQAEAQAJAAQJ4Q4jKQAEAQAKAAMJ6wr3KQCpAAAuAAQKfyEAAgkACAlFGW8UAGsCAAkACAlFGW8UAGsCAAAA.',
As='Asayo:BAAALgAECgUJEgAAAA==.Asherie:BAAALgAECgQJCQABLgAECgkJFgAHAIIRAA==.Aske:BAABLgAECn8nAAILAAkJGBRyOgDwAQALAAkJGBRyOgDwAQAAAA==.Astolan:BAAALgAECgEJAgAAAA==.',
At='Atonga:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgcJEQAAAA==.',
Az='Azuresun:BAABLgAECn8fAAIMAAkJEAtRNgBgAQAMAAkJEAtRNgBgAQAAAA==.',
Ba='Balerion:BAAALgAECgEJAwAAAA==.Ballak:BAABLgAECn8ZAAINAAcJzRGWVABrAQANAAcJzRGWVABrAQAAAA==.Barlee:BAAALgADCgEJAQABLgAFFAIJAQAOAAAAAA==.',
Be='Beatin:BAAALgAECgUJCgAAAA==.Belenzr:BAAALgADCgEJAQAAAA==.',
Bi='Bigdikley:BAAALgAECgYJEQAAAA==.Biggtater:BAAALgADCgUJBQAAAA==.',
Bl='Bloodywake:BAAALgAECgYJCQAAAA==.Bloopydoo:BAABLgAECn8dAAIPAAgJPwetzQD1AAAPAAgJPwetzQD1AAAAAA==.Blort:BAAALgADCgEJAQAAAA==.Bláckbird:BAABLgAECn8bAAINAAkJMhoiVQCkAQANAAkJMhoiVQCkAQAAAA==.',
Bo='Bohliang:BAAALgADCgkJEAAAAA==.Boiorix:BAAALgADCgYJBgAAAA==.Boltywolty:BAAALgAECgYJCgAAAA==.Borim:BAAALgAECgEJAQAAAA==.',
Br='Brandymae:BAAALgAECgMJBQAAAA==.Branholy:BAAALgADCgEJAQAAAA==.Brbpoopin:BAAALgAECgYJDAAAAA==.Brotems:BAAALgAECgkJAQAAAA==.Bruwdflight:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebuster:BAAALgAECgYJDAABLgAECgkJIAADAGAeAA==.Bumwarrior:BAAALgADCgEJAQAAAA==.Burnphase:BAAALgADCgQJBwAAAA==.',
By='Byrdreisyl:BAAALgAECgQJBAAAAA==.',
Ca='Caosgonewild:BAAALgAECgUJBQAAAA==.',
Ce='Celestyal:BAAALgADCgMJAwABLgADCgYJBgAOAAAAAA==.',
Ch='Chestie:BAABLgAECn8hAAMDAAkJdR1ETwDVAQADAAgJ6x1ETwDVAQAQAAIJOBqPKACPAAAAAA==.Chubbychi:BAAALgAECgIJAgAAAA==.',
Ci='Cinde:BAAALgADCgMJAwABLgAFFAQJDAANADscAA==.Cindy:BAACLgAFFH8MAAINAAQJOxzKMABOAQANAAQJOxzKMABOAQAuAAQKfygAAw0ACQn9HhMOAOECAA0ACQn9HhMOAOECABEAAQneBZ2RACkAAAAA.Cindyx:BAAALgAECgYJDwABLgAFFAQJDAANADscAA==.',
Co='Coast:BAABLgAECn8VAAISAAgJ1wcRGQDaAAASAAgJ1wcRGQDaAAAAAA==.Coldlock:BAAALgAECggJCAABLgAECgkJMAATAAUaAA==.Coldsore:BAABLgAECn8wAAQTAAkJBRqACgAhAgATAAkJ4RmACgAhAgABAAYJ+wZ9UwDqAAAFAAMJMQdrLQGDAAAAAA==.Coldwar:BAAALgADCgcJBwAAAA==.Conjuremoney:BAAALgADCgEJAQAAAA==.Cootpal:BAABLgAECn8+AAIFAAkJDB5/GgClAgAFAAkJDB5/GgClAgAAAA==.Costcohotdog:BAAALgADCgMJAwAAAA==.',
Cr='Crazyloon:BAAALgAECgUJCQAAAA==.Crewgr:BAAALgADCgEJAQABLgAECgEJAQAOAAAAAA==.Crewmix:BAAALgAECgEJAQAAAA==.Crewshield:BAAALgADCgMJAwABLgAECgEJAQAOAAAAAA==.Croe:BAAALgADCgMJAwAAAA==.',
Cy='Cynawyne:BAAALgAECgEJAQAAAA==.Cynthea:BAAALgAECgkJCgAAAA==.',
Da='Dahm:BAAALgAECgMJBgAAAA==.Dalasaurs:BAACLgAFFH8LAAIGAAMJxxmaAwDeAAAGAAMJxxmaAwDeAAAuAAQKfzAAAgYACAmTGKMoABoCAAYACAmTGKMoABoCAAAA.Dalasnipus:BAAALgADCgMJAwAAAA==.Dalbear:BAAALgADCgYJCQAAAA==.Darkpallas:BAAALgAECgYJCAAAAA==.Darkprophetc:BAABLgAECn84AAIPAAkJeg0DAwAvAQAPAAkJeg0DAwAvAQAAAA==.',
De='Deathfyre:BAAALgADCgQJBAAAAA==.Deluun:BAAALgADCgkJCQAAAA==.Demious:BAABLgAECn8ZAAINAAkJqh9SEgC/AgANAAkJqh9SEgC/AgAAAA==.Demiurge:BAEALgAECgkJEAAAAA==.Demonfister:BAACLgAFFH8JAAIGAAMJwQweOwDFAAAGAAMJwQweOwDFAAAuAAQKfygAAgYACQn+G0UNAJkCAAYACQn+G0UNAJkCAAAA.Demonkiller:BAABLgAECn8eAAIUAAYJPAZ4QgCsAAAUAAYJPAZ4QgCsAAAAAA==.Denastiest:BAABLgAECn8uAAIEAAkJDA+kTQCdAQAEAAkJDA+kTQCdAQAAAA==.Denji:BAAALgAECggJEAAAAA==.Devistashion:BAAALgAECgEJAQAAAA==.Devvmonk:BAABLgAECn8UAAIVAAcJag0GUAAuAQAVAAcJag0GUAAuAQAAAA==.',
Di='Dindaratwo:BAAALgAFFAEJAQAAAA==.',
Do='Doe:BAABLgAECn8pAAMWAAcJmyOkBQBIAgAWAAcJmyOkBQBIAgAUAAMJhhD+UgCdAAAAAA==.Dokta:BAABLgAECn8YAAIXAAgJMA+jHABRAQAXAAgJMA+jHABRAQAAAA==.',
Dr='Draflex:BAAALgAECgMJBAAAAA==.Drathal:BAABLgAECn82AAIFAAkJ1AfuiwBZAQAFAAkJ1AfuiwBZAQAAAA==.Drjay:BAAALgADCgkJCwAAAA==.',
Dv='Dvergar:BAAALgAECgYJDAAAAA==.',
Ea='Eatshrooms:BAAALgAECgMJBAAAAA==.',
Ed='Edd:BAAALgAECgQJBAAAAA==.Eddiedean:BAAALgAECgYJBgAAAA==.',
El='Elessarr:BAAALgAECgQJBQAAAA==.Elfgonewild:BAAALgAECgUJCgAAAA==.Ellessra:BAABLgAECn8mAAIPAAkJWwNAtQAZAQAPAAkJWwNAtQAZAQAAAA==.Elnegrouno:BAABLgAECn8fAAIXAAcJfR/SCgBjAgAXAAcJfR/SCgBjAgAAAA==.Eloper:BAAALgAFFAEJAQAAAA==.',
Em='Emotank:BAAALgAECgUJBgAAAA==.',
Er='Eragone:BAAALgAECgMJBgAAAA==.',
Et='Etoro:BAAALgADCgEJAgAAAA==.',
Ev='Evissier:BAACLgAFFH8OAAIYAAQJZh9ZAwBiAQAYAAQJZh9ZAwBiAQAuAAQKfx0AAhgACAmuIAcBAAIDABgACAmuIAcBAAIDAAAA.',
Ex='Exsequor:BAACLgAFFH8RAAITAAQJIiEnAwB8AQATAAQJIiEnAwB8AQAuAAQKfx0AAxMABgkLIzwTAJYBABMABgkLIzwTAJYBAAUAAQlyB/tQASsAAAAA.',
Ez='Ezuras:BAAALgAECgMJAwAAAA==.',
Fa='Faeyri:BAABLgAECn8uAAIMAAkJLhpFEQBnAgAMAAkJLhpFEQBnAgAAAA==.Fassandin:BAAALgAECgIJAgAAAA==.',
Fe='Felli:BAAALgAECgEJAQAAAA==.',
Fi='Fishermon:BAAALgAECgUJCAAAAA==.',
Fl='Flagfarmer:BAABLgAECn8dAAIBAAYJMSY+EQCLAgABAAYJMSY+EQCLAgAAAA==.Flataxe:BAAALgAECgMJAwAAAA==.Flixunt:BAAALgADCgEJAQAAAA==.',
Fo='Foidepas:BAAALgAECgcJDQAAAA==.Fourid:BAAALgAECgQJDAAAAA==.Foxannee:BAAALgAECgMJBgAAAA==.',
Fr='Freezyweezy:BAACLgAFFH8LAAIPAAQJ4RuOUQA6AQAPAAQJ4RuOUQA6AQAuAAQKfx8AAg8ACQnoIw0eAKgCAA8ACQnoIw0eAKgCAAAA.Frostfirer:BAAALgAECgYJAgAAAA==.',
Fu='Fudgeyenuh:BAAALgAECgkJCQAAAA==.',
Fy='Fyrewar:BAAALgAECgMJAwAAAA==.',
['Fú']='Fúry:BAAALgAECgcJCgAAAA==.',
Ga='Gallyn:BAABLgAFFH8QAAICAAMJLh3RBAC3AAACAAMJLh3RBAC3AAAAAA==.Gamm:BAAALgADCgcJEQAAAA==.Garaal:BAAALgAECggJEgAAAA==.Gaytorade:BAAALgAECgUJBgAAAA==.',
Ge='Geloise:BAAALgAECgMJAwAAAA==.Gerel:BAAALgAECgYJBgAAAA==.',
Gi='Ginyu:BAAALgAECgIJBQAAAA==.',
Gl='Glacierrock:BAAALgADCgQJCgAAAA==.Gloria:BAABLgAECn8jAAIZAAkJ3gnaTQB6AQAZAAkJ3gnaTQB6AQAAAA==.',
Go='Gooblicious:BAAALgAECgEJAQAAAA==.Gori:BAAALgAECgIJAgAAAA==.',
Gr='Grail:BAABLgAECn8eAAIFAAcJ4A3bpQAvAQAFAAcJ4A3bpQAvAQAAAA==.Grelvisse:BAAALgAECgMJBQAAAA==.Grippywippy:BAAALgADCgYJBAAAAA==.',
Gu='Gudren:BAAALgADCgEJAQAAAA==.Guimon:BAAALgAECgMJBAAAAA==.Gunslinger:BAAALgAECgEJAQAAAA==.',
Gw='Gwenie:BAABLgAECn8mAAILAAkJYhHbPQDlAQALAAkJYhHbPQDlAQAAAA==.',
Ha='Halenicion:BAAALgAFFAEJAQAAAA==.Hauntfrost:BAAALgAECgEJAQAAAA==.Hazél:BAAALgADCgYJBgAAAA==.',
He='Helix:BAAALgAECgIJAgAAAA==.',
Hi='Hippoltyos:BAABLgAECn8sAAIHAAkJnA4bJgCUAQAHAAkJnA4bJgCUAQAAAA==.',
Ho='Honestlee:BAAALgAECgQJBAAAAA==.Honourablee:BAAALgAECgcJCgAAAA==.Hortzul:BAAALgADCgMJAwABLgAFFAUJGQABABkfAA==.Hotsaucce:BAAALgADCgEJAQAAAA==.Hotstheboss:BAAALgADCgYJBgAAAA==.Houe:BAAALgADCgUJCAAAAA==.',
Hu='Huffle:BAAALgAECgEJAQAAAA==.Huntardiness:BAABLgAECn8gAAQaAAgJrhGAJQBxAQANAAcJ5RJLUAB4AQAaAAgJFgqAJQBxAQARAAEJ7g7XPQAuAAAAAA==.Hunterd:BAAALgADCgEJAQAAAA==.',
Hy='Hymnals:BAACLgAFFH8OAAIGAAQJVCYbCgC/AQAGAAQJVCYbCgC/AQAuAAQKfxcAAwYACAlRJO4OANwCAAYACAlRJO4OANwCABsAAgkHGntUAIQAAAAA.',
Ia='Ianmaris:BAAALgAECgMJAwAAAA==.',
Ic='Icealia:BAAALgAECgEJAQABLgAFFAQJFgAcAJIIAA==.Icelandite:BAAALgAECgYJBgAAAA==.',
Iv='Ive:BAABLgAECn8hAAQSAAkJpCJ2EQDBAQASAAcJrBt2EQDBAQALAAgJGCI+WgCPAQAYAAIJHBD0JABeAAAAAA==.',
Ja='Jackburton:BAAALgAECgIJAgAAAA==.Jaddie:BAAALgAECgkJEwAAAA==.Jarnunvosk:BAABLgAECn8lAAMdAAkJxBSrCgA1AgAdAAkJxBSrCgA1AgAeAAEJbwNxnwAeAAAAAA==.Jasmindinn:BAAALgADCgcJDgAAAA==.Jayber:BAABLgAECn8sAAMfAAgJpRFzIADKAQAfAAgJpRFzIADKAQAIAAEJmQBongAGAAAAAA==.',
Je='Jezadora:BAAALgADCgEJAQAAAA==.',
Jo='Jolkom:BAAALgAECgMJBgABLgAECgkJGwAXACQcAA==.',
Ju='Julantis:BAAALgAECgYJBgAAAA==.',
Ka='Kadri:BAAALgAFFAEJAQAAAA==.Kaffee:BAABLgAECn81AAITAAkJ7A9+EwCTAQATAAkJ7A9+EwCTAQAAAA==.Kamakaz:BAAALgAECgcJCQAAAA==.Kamasdruid:BAAALgAECggJDAAAAA==.Kamasmage:BAAALgADCgcJBwAAAA==.Kamasmonk:BAAALgAECgYJBwAAAA==.Kamasux:BAAALgADCgYJBwAAAA==.Kandi:BAAALgADCgQJCgAAAA==.Kaviryon:BAAALgAECgEJAwAAAA==.Kaywhy:BAABLgAECn8VAAIIAAkJUxzxJQCcAQAIAAkJUxzxJQCcAQAAAA==.',
Ki='Kichack:BAABLgAECn8uAAMKAAkJ+B9GBwDVAgAKAAkJ+B9GBwDVAgAVAAYJDxSqQgBjAQAAAA==.Kitarvie:BAAALgAECgEJAgAAAA==.',
Kj='Kjdh:BAABLgAECn8oAAIUAAgJSCLxCQCKAgAUAAgJSCLxCQCKAgAAAA==.',
Kl='Kladuum:BAAALgADCgcJGQAAAA==.',
Kn='Knuckles:BAABLgAECn8VAAIGAAkJTBeLIgDeAQAGAAkJTBeLIgDeAQAAAA==.',
Ko='Kogun:BAAALgAECgQJBAAAAA==.Kowala:BAABLgAECn8cAAIgAAkJvw9EKACPAQAgAAkJvw9EKACPAQAAAA==.Kowpox:BAAALgADCgkJCgAAAA==.Kozalth:BAAALgADCgEJAgAAAA==.',
Kr='Krabi:BAAALgADCgYJCwAAAA==.Kranks:BAAALgAECgEJAQAAAA==.Kreios:BAAALgAECgYJBwAAAA==.Krelo:BAABLgAECn8nAAIZAAkJ0B0qDAD5AgAZAAkJ0B0qDAD5AgAAAA==.',
Kt='Ktom:BAABLgAECn8zAAIMAAkJGiUeAwBAAwAMAAkJGiUeAwBAAwAAAA==.',
Ku='Kurimbory:BAAALgAECgUJBQAAAA==.',
Ky='Kyruan:BAAALgADCgEJAQAAAA==.',
['Ký']='Kýlê:BAABLgAECn8ZAAMNAAgJmwdIUgByAQANAAgJmwdIUgByAQARAAYJ6gLLWQDdAAAAAA==.',
La='Lancelot:BAAALgAECgYJCQAAAA==.Lanthuil:BAAALgAECgQJBAAAAA==.Lazydruid:BAAALgADCgkJCgAAAA==.',
Li='Lifepooll:BAAALgAECgEJAQABLgAFFAIJAQAOAAAAAA==.Lilyselah:BAAALgADCgYJBwAAAA==.Littlelocky:BAAALgADCgcJEwAAAA==.Liv:BAABLgAECn8UAAIIAAgJtQu6LgBsAQAIAAgJtQu6LgBsAQAAAA==.',
Ll='Llamallab:BAAALgADCgcJBwAAAA==.',
Lo='Lostmyghoul:BAACLgAFFH8GAAIDAAMJTBmIiAD5AAADAAMJTBmIiAD5AAAuAAQKfycAAgMACQkoH+IWAL0CAAMACQkoH+IWAL0CAAAA.Lostwarrior:BAAALgAECgYJCAAAAA==.Louhi:BAAALgAECgQJBgABLgAECgMJCAAOAAAAAA==.',
Lu='Luglug:BAAALgAECgEJAQAAAA==.Lunar:BAABLgAECn8mAAIgAAkJkR+5BwDbAgAgAAkJkR+5BwDbAgAAAA==.Lunasea:BAAALgAECgMJAwAAAA==.',
Ly='Lysol:BAAALgADCgUJBQAAAA==.Lystat:BAAALgAECgUJCwAAAA==.',
Ma='Magicfungus:BAAALgADCgUJCQAAAA==.Magno:BAAALgADCgIJAgAAAA==.Magra:BAABLgAECn8YAAIPAAYJnwytxwD+AAAPAAYJnwytxwD+AAAAAA==.Magêyalook:BAABLgAECn8nAAIPAAgJthmVPwAeAgAPAAgJthmVPwAeAgAAAA==.Mancha:BAAALgAECgEJAQAAAA==.Mangel:BAAALgADCgYJBgAAAA==.Manzz:BAAALgAECgUJCgAAAA==.Marcelline:BAAALgADCgYJEgAAAA==.Mattob:BAAALgADCgkJDwAAAA==.Maximus:BAAALgADCgkJEAAAAA==.Maznificent:BAAALgAECgMJAwAAAA==.Mazyme:BAAALgADCgQJCQAAAA==.',
Me='Meandmypal:BAACLgAFFH8UAAIaAAgJzBmzAQBLAgAaAAgJzBmzAQBLAgAuAAQKfy4AAhoACQk4JrsAAH4DABoACQk4JrsAAH4DAAAA.Mello:BAABLgAECn8zAAIbAAkJXx3wBQCmAgAbAAkJXx3wBQCmAgAAAA==.Mesteris:BAAALgADCgYJBgAAAA==.',
Mi='Midiane:BAAALgAECgEJAQAAAA==.Milim:BAAALgAFFAIJAgAAAA==.Mirba:BAABLgAECn8qAAINAAkJbxUWLQAoAgANAAkJbxUWLQAoAgAAAA==.',
Mo='Mongo:BAABLgAECn8wAAIDAAkJ/R8KEQDkAgADAAkJ/R8KEQDkAgAAAA==.Monochrome:BAAALgAECgIJAgAAAA==.Monsterdeath:BAAALgAECgIJAgAAAA==.Moralinth:BAAALgADCgEJAQAAAA==.Moreicepls:BAABLgAECn8bAAIPAAgJ+wmvlgBLAQAPAAgJ+wmvlgBLAQAAAA==.Morené:BAAALgAECgQJBgAAAA==.Moxxee:BAAALgADCgkJGwAAAA==.',
Mu='Mushhmelu:BAAALgAECgEJAQAAAA==.',
My='Myiko:BAAALgAECgQJBAAAAA==.Mytharu:BAAALgADCgMJAwAAAA==.',
Na='Nareík:BAACLgAFFH8PAAMUAAQJpwczGwDIAAAEAAQJBQbWXgDTAAAUAAQJ6wUzGwDIAAAuAAQKfyAAAgQACAlZEmhVAKMBAAQACAlZEmhVAKMBAAAA.',
Ne='Neriak:BAAALgADCgkJCQAAAA==.Neutrallee:BAAALgAECgEJAQAAAA==.Newa:BAAALgAECgUJCQAAAA==.',
Ni='Nightwater:BAACLgAFFH8WAAIcAAQJkggtBQCCAAAcAAQJkggtBQCCAAAuAAQKfykABBwACQmLF6cnABMCABwACQmLF6cnABMCACEAAglfCUFEAFMAACAAAQmKCJuTACwAAAAA.',
['Né']='Nébulien:BAABLgAECn8dAAIiAAgJNx7KCgALAgAiAAgJNx7KCgALAgAAAA==.',
Ok='Okkok:BAABLgAECn8XAAIPAAYJ8hCIwABjAQAPAAYJ8hCIwABjAQAAAA==.',
Or='Orchop:BAABLgAECn8YAAIiAAYJgQk2IgDlAAAiAAYJgQk2IgDlAAAAAA==.Orkrist:BAABLgAECn8XAAINAAcJpRL/agBsAQANAAcJpRL/agBsAQAAAA==.',
Oz='Oz:BAAALgADCgUJBQAAAA==.',
Pa='Paado:BAAALgADCgUJBQAAAA==.Pantryraider:BAAALgAECgkJCAAAAA==.Patriqt:BAAALgAECgEJAQAAAA==.Paulterian:BAAALgAECgYJBQAAAA==.Paymeforpi:BAAALgAECgMJAwAAAA==.',
Ph='Phelaeshio:BAABLgAECn8eAAIDAAkJOxxlJgBqAgADAAkJOxxlJgBqAgAAAA==.',
Po='Poam:BAAALgAECgUJBQAAAA==.Poldalina:BAAALgADCgkJGwAAAA==.Power:BAABLgAECn8UAAIDAAcJQQrypwAgAQADAAcJQQrypwAgAQAAAA==.',
Pr='Primevil:BAAALgADCgQJBAAAAA==.Prosthetic:BAAALgAECgEJAQAAAA==.Proverbs:BAAALgAFFAIJAgAAAA==.',
Pu='Pumplord:BAAALgAECgcJEQAAAA==.Punchyou:BAAALgADCgEJAQAAAA==.',
['På']='Pårts:BAAALgAFFAIJAQAAAA==.',
['Pù']='Pùff:BAAALgAECgUJCQAAAA==.',
Qu='Quazeemoto:BAAALgAECgEJAQAAAA==.',
Ra='Raeyna:BAAALgAECgIJBAABLgAECgkJIQASAKQiAA==.Raffern:BAAALgAECgMJAwAAAA==.Rainknuckles:BAABLgAECn8lAAIBAAgJVRYAJgDYAQABAAgJVRYAJgDYAQAAAA==.Rayshano:BAABLgAECn8WAAITAAcJBRr+EgCZAQATAAcJBRr+EgCZAQAAAA==.',
Re='Recklessone:BAAALgAECgEJAQAAAA==.Renewedfaith:BAAALgADCgQJBAAAAA==.Resia:BAAALgADCgQJAQAAAA==.Revocsid:BAAALgADCgkJFgAAAA==.Rezza:BAAALgADCgEJAQAAAA==.',
Ri='Rikka:BAAALgADCgMJAwAAAA==.',
Ro='Rottingtree:BAAALgAECgYJEAAAAA==.',
Ru='Rustynails:BAABLgAECn84AAIjAAkJGSTNAAAiAwAjAAkJGSTNAAAiAwAAAA==.',
Sa='Saffire:BAAALgADCgcJBwAAAA==.Salina:BAAALgAECgEJAQAAAA==.Saly:BAAALgADCgIJAQABLgADCggJDgAOAAAAAA==.Samwitch:BAAALgAECgUJEgAAAA==.Sappaho:BAAALgADCgYJBwAAAA==.Satheirel:BAAALgADCgYJBwAAAA==.Savanti:BAAALgAECgEJAQAAAA==.Sazzul:BAAALgAECgkJEwAAAA==.',
Sc='Scott:BAACLgAFFH8WAAIXAAUJgyA+AwBiAQAXAAUJgyA+AwBiAQAuAAQKfyUAAhcACQlnJNQDABMDABcACQlnJNQDABMDAAAA.Screamor:BAAALgAECgEJAQAAAA==.Screams:BAAALgADCgEJAQAAAA==.Screamz:BAABLgAECn8eAAIUAAYJ6RgsJgBIAQAUAAYJ6RgsJgBIAQAAAA==.Scynx:BAAALgAFFAIJAwAAAA==.',
Se='Seaka:BAABLgAECn8xAAQgAAkJihjQEgA/AgAgAAkJihjQEgA/AgAcAAcJYRZ0QACQAQAkAAIJxg6fXABVAAAAAA==.Sebas:BAAALgAECgEJAQAAAA==.Sent:BAAALgADCggJDgAAAA==.Serion:BAAALgAECgQJBQABLgAFFAEJAQAOAAAAAA==.Sernix:BAABLgAECn8oAAIZAAgJKxx+FgCWAgAZAAgJKxx+FgCWAgAAAA==.',
Sh='Shadegrim:BAAALgAECgQJBgAAAA==.Shadespawn:BAAALgADCgEJAQAAAA==.Shaeia:BAACLgAFFH8IAAIMAAMJzxCEEQDcAAAMAAMJzxCEEQDcAAAuAAQKfx8AAgwACQn0HLcNAMYCAAwACQn0HLcNAMYCAAAA.Shamanic:BAAALgAECgIJAgAAAA==.Shambat:BAAALgADCgYJBgAAAA==.Shangi:BAAALgADCgMJAgABLgAFFAQJEQATACIhAA==.Shekinah:BAAALgADCgEJAQAAAA==.Shen:BAAALgAECgQJBgAAAA==.Shiftyfans:BAAALgADCgMJAwABLgAECgcJEQAOAAAAAA==.',
Si='Siatrath:BAAALgAECgEJAQABLgAFFAQJEQATACIhAA==.Sivtekeda:BAAALgAECgQJCQAAAA==.',
Sk='Sktibrew:BAACLgAFFH8TAAIJAAYJgSF1BACRAQAJAAYJgSF1BACRAQAuAAQKfxoAAgkACAmDHRMRAI8CAAkACAmDHRMRAI8CAAAA.',
Sl='Slamin:BAAALgAECgQJBwAAAA==.Slash:BAABLgAECn8kAAIUAAkJxRcHFADyAQAUAAkJxRcHFADyAQAAAA==.Slyavane:BAABLgAECn84AAQYAAkJqBX4BgAHAgAYAAkJqBX4BgAHAgASAAcJawc/HADEAAALAAQJWwQE4QCYAAAAAA==.Slyice:BAAALgAECgEJBgAAAA==.',
Sm='Smokess:BAACLgAFFH8QAAMTAAUJmBotBQA3AQATAAUJmBotBQA3AQAFAAMJDxQiFgD7AAAuAAQKfx8AAxMACAnkIRQMAAQCABMACAnKHRQMAAQCAAUACAlAGZZKAAMCAAEuAAUUBgkJABcAdQoA.',
Sn='Snowwind:BAABLgAECn8hAAIHAAgJhArmMwA2AQAHAAgJhArmMwA2AQAAAA==.',
So='Solthea:BAAALgAECgkJBwAAAA==.Solymar:BAAALgAECgkJBwAAAA==.Sonar:BAABLgAECn8pAAINAAkJ8h9aGgCHAgANAAkJ8h9aGgCHAgAAAA==.Sonasai:BAAALgADCgkJGwAAAA==.Sonnybear:BAAALgADCgUJEQAAAA==.Soulhatcher:BAAALgAECgQJEAAAAA==.Soxs:BAABLgAECn8qAAMVAAkJNBo8EACiAgAVAAkJNBo8EACiAgAKAAIJTg+MdABnAAAAAA==.',
Sp='Spookymoo:BAAALgADCgQJBAAAAA==.',
St='Stabbywabby:BAAALgAECgYJBwAAAA==.Stardris:BAABLgAECn8bAAIEAAgJawKIqAC/AAAEAAgJawKIqAC/AAAAAA==.Stenaris:BAAALgAECgYJBwAAAA==.Stompygnome:BAAALgAECgkJEwAAAA==.Strooth:BAAALgADCgQJBAAAAA==.',
Su='Supersteph:BAAALgAECgUJBQABLgAECgkJLgAFALkhAA==.',
Ta='Talavel:BAAALgADCgIJAgAAAA==.Tartanus:BAABLgAECn8tAAIEAAkJXxdpLgANAgAEAAkJXxdpLgANAgAAAA==.Taulogit:BAAALgAECgIJAgAAAA==.Tayzetv:BAAALgAECgMJAwABLgAFFAMJBwAiAGcOAA==.',
Te='Tentaclepwn:BAAALgADCgMJAwAAAA==.Teramiah:BAAALgADCgcJFAAAAA==.',
Th='Thanestra:BAAALgAECgkJBwAAAA==.Theadona:BAABLgAECn8pAAIFAAgJXB3OLQBJAgAFAAgJXB3OLQBJAgAAAA==.Thorall:BAAALgADCgkJDwAAAA==.Thylight:BAAALgADCgMJAwAAAA==.',
Ti='Tikcus:BAAALgADCgcJEAAAAA==.Tils:BAAALgADCggJDwAAAA==.Tippy:BAACLgAFFH8dAAMQAAYJmxpXBAC/AQAQAAUJmxpXBAC/AQAlAAIJuQF9RgAeAAAuAAQKfzYABBAACQloITsDALkCABAACQkQITsDALkCAAMAAwkNBskDAXAAACUAAgl1DmJLAGIAAAAA.',
To='Toastedwings:BAAALgADCgcJDwAAAA==.Tombstone:BAAALgAECgYJEgAAAA==.Toowongfoo:BAACLgAFFH8aAAIKAAYJsB9xBQDFAQAKAAYJsB9xBQDFAQAuAAQKfycAAgoACQm4I7wDACQDAAoACQm4I7wDACQDAAAA.',
Tr='Trewer:BAAALgADCgIJAgAAAA==.Trisara:BAABLgAECn81AAIgAAkJrwi4NQBAAQAgAAkJrwi4NQBAAQAAAA==.',
Tu='Tunechi:BAAALgAECgEJAgAAAA==.',
Ty='Tygrana:BAAALgAECgEJAQAAAA==.Tyradora:BAAALgAECgEJAQAAAA==.Tytannia:BAAALgADCgEJAQAAAA==.',
['Tö']='Töteman:BAABLgAECn8pAAIMAAcJlBa4LACSAQAMAAcJlBa4LACSAQAAAA==.',
['Tÿ']='Tÿtann:BAAALgAECgMJAwAAAA==.',
Um='Umbranecros:BAAALgAECgEJBQAAAA==.',
Un='Unbok:BAAALgAECgkJAQAAAA==.Underdog:BAABLgAECn8jAAMRAAgJyRhjAAAzAQARAAgJyRhjAAAzAQANAAEJAADbVQEAAAAAAA==.',
Up='Upthere:BAAALgADCgQJBAABLgAECgcJFAAVAGoNAA==.',
Va='Vaerie:BAAALgAECgEJAQAAAA==.Vaern:BAABLgAECn8fAAIhAAgJtB1GCABLAgAhAAgJtB1GCABLAgAAAA==.Vaethorn:BAAALgAECgcJCAAAAA==.Vagindivin:BAAALgAECgcJDwAAAA==.Valrie:BAAALgAECgMJAwAAAA==.Valyteil:BAAALgAFFAEJAQAAAA==.',
Ve='Venngance:BAABLgAECn8uAAQQAAkJxSMYBACTAgAQAAgJTiAYBACTAgAlAAYJZiTVFwCdAQADAAYJExSUrgAWAQAAAA==.',
Vi='Virus:BAAALgAECgkJEgAAAA==.Vitner:BAAALgADCgMJAwAAAA==.',
Vo='Voidkity:BAAALgAECgQJBwAAAA==.Voidpriest:BAAALgAECgEJAQAAAA==.',
Vy='Vyrlet:BAAALgAECgEJAQAAAA==.',
Wa='Wakax:BAAALgAECgEJAQAAAA==.Walberson:BAAALgADCgYJBgAAAA==.Warfield:BAABLgAECn8fAAMkAAkJYxP/EwC3AQAkAAkJYxP/EwC3AQAhAAEJWgP8YwAcAAAAAA==.',
Wf='Wfbot:BAAALgAECgEJAQAAAA==.',
Wh='Whosbondt:BAAALgAECgYJDAAAAA==.',
Wi='Winafred:BAAALgAECgEJAQAAAA==.Wittwicky:BAAALgAECgEJAQAAAA==.',
Wk='Wkeyonly:BAABLgAECn8fAAIEAAkJYRVZYABoAQAEAAkJYRVZYABoAQAAAA==.',
Wo='Woody:BAAALgADCgUJBQAAAA==.Wooter:BAAALgADCgYJDAAAAA==.Worthy:BAAALgAECgkJAwAAAA==.',
Wr='Wrathsome:BAABLgAECn8uAAIcAAkJoBPvJQAfAgAcAAkJoBPvJQAfAgAAAA==.',
Wu='Wunderbilly:BAAALgADCgEJAQAAAA==.',
['Wí']='Wísp:BAAALgAECgEJAQAAAA==.',
Xa='Xaernach:BAAALgAECgEJAQAAAA==.Xalome:BAAALgADCgYJBgAAAA==.',
Xl='Xloon:BAAALgAECgEJAQAAAA==.',
Xy='Xypherus:BAAALgADCgkJDQAAAA==.',
['Xá']='Xándarl:BAAALgAECgMJBAAAAA==.',
Ya='Yakoda:BAAALgADCgUJBQAAAA==.Yaldabaoth:BAEALgAECgcJBQABLgAECgkJEAAOAAAAAA==.Yanza:BAAALgAECgIJAwAAAA==.',
Ye='Yello:BAAALgAECgYJBgAAAA==.',
Za='Zaio:BAAALgAECgYJCQAAAA==.Zarkus:BAAALgAECgQJEgAAAA==.',
Ze='Zelphi:BAAALgAECgQJCAAAAA==.Zenha:BAAALgADCgEJAQAAAA==.Zephaadella:BAAALgAECgEJAQAAAA==.',
Zh='Zhuzi:BAAALgADCgkJDwAAAA==.',
Zs='Zshmokez:BAACLgAFFH8JAAIXAAYJdQqnFQDyAAAXAAYJdQqnFQDyAAAuAAQKfxsAAhcACQmrH30FAL8CABcACQmrH30FAL8CAAAA.',
['Åy']='Åylå:BAAALgAECgEJAQABLgAECgQJBAAOAAAAAA==.',
['Ëm']='Ëmo:BAAALgAECgQJBAAAAA==.',
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
