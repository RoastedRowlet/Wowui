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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Retribution','Warrior-Fury','Priest-Holy','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','Mage-Frost','DeathKnight-Frost','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Protection','Warlock-Affliction','Rogue-Subtlety','Shaman-Restoration','Hunter-Survival','Warrior-Arms','Druid-Restoration','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Monk-Mistweaver','Druid-Balance','Druid-Feral','Shaman-Enhancement','Rogue-Outlaw','Druid-Guardian','DeathKnight-Blood',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abert:BAAALgADCgUJBQAAAA==.Abilify:BAAALgAECgEJAgAAAA==.',
Ac='Acts:BAAALgAFFAEJAQAAAA==.',
Ad='Adalinda:BAAALgADCgkJCgABLgAFFAUJGQABABkfAA==.',
Ag='Agnor:BAABLgAECn81AAICAAgJVxq3PwACAgACAAgJVxq3PwACAgAAAA==.',
Al='Alatir:BAAALgADCgkJFAAAAA==.Alticus:BAAALgADCgEJAQAAAA==.',
An='Andrew:BAAALgAECgEJAQABLgAFFAUJEQADANEWAA==.Anien:BAAALgAECgYJEQAAAA==.Anklemauler:BAAALgAECgYJBgAAAA==.Anthem:BAAALgAECgYJBgAAAA==.Antibubble:BAABLgAECn8gAAICAAkJYB75IgB4AgACAAkJYB75IgB4AgAAAA==.Antipeta:BAAALgAECgEJAgAAAA==.Anwal:BAACLgAFFH8ZAAIBAAUJGR98DwC6AQABAAUJGR98DwC6AQAuAAQKfy0AAwEACQlXHLsiAAkCAAEACAlIG7siAAkCAAQACQlCDKB2AH4BAAAA.',
Ar='Argus:BAABLgAECn8wAAIFAAgJHCMdCgDBAgAFAAgJHCMdCgDBAgAAAA==.Arithana:BAABLgAFFH8IAAMGAAQJaAMbIwCcAAAGAAQJaAMbIwCcAAAHAAEJIAcxPgA3AAABLgAFFAQJDAAIAOEOAA==.Arithfury:BAAALgAECgIJAgABLgAFFAQJDAAIAOEOAA==.Arithkick:BAACLgAFFH8MAAMIAAQJ4Q4SKAAFAQAIAAQJ4Q4SKAAFAQAJAAMJ6wqgKACpAAAuAAQKfyEAAggACAlFGW8UAGsCAAgACAlFGW8UAGsCAAAA.',
As='Asayo:BAAALgAECgUJEgAAAA==.Asherie:BAAALgAECgQJCQABLgAECgkJFgAGAIIRAA==.Aske:BAABLgAECn8mAAIKAAkJghPqOQDxAQAKAAkJghPqOQDxAQAAAA==.Astolan:BAAALgAECgEJAgAAAA==.',
At='Atonga:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgcJEQAAAA==.',
Az='Azuresun:BAABLgAECn8fAAILAAkJEAtmNQBhAQALAAkJEAtmNQBhAQAAAA==.',
Ba='Balerion:BAAALgAECgEJAgAAAA==.Ballak:BAABLgAECn8ZAAIMAAcJzRGWVABrAQAMAAcJzRGWVABrAQAAAA==.Barlee:BAAALgADCgEJAQABLgAFFAIJAQANAAAAAA==.',
Be='Beatin:BAAALgAECgUJCgAAAA==.Belenzr:BAAALgADCgEJAQAAAA==.',
Bi='Bigdikley:BAAALgAECgYJEQAAAA==.Biggtater:BAAALgADCgUJBQAAAA==.',
Bl='Bloodywake:BAAALgAECgYJCQAAAA==.Bloopydoo:BAABLgAECn8YAAIOAAYJowja0wDoAAAOAAYJowja0wDoAAAAAA==.Blort:BAAALgADCgEJAQAAAA==.Bláckbird:BAABLgAECn8bAAIMAAkJMhpTUwClAQAMAAkJMhpTUwClAQAAAA==.',
Bo='Bohliang:BAAALgADCgkJEAAAAA==.Boltywolty:BAAALgAECgYJCgAAAA==.Borim:BAAALgAECgEJAQAAAA==.',
Br='Brandymae:BAAALgAECgMJBQAAAA==.Branholy:BAAALgADCgEJAQAAAA==.Brbpoopin:BAAALgAECgYJBgAAAA==.Brotems:BAAALgAECgkJAQAAAA==.Bruwdflight:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebuster:BAAALgAECgYJDAABLgAECgkJIAACAGAeAA==.Bumwarrior:BAAALgADCgEJAQAAAA==.Burnphase:BAAALgADCgQJBwAAAA==.',
By='Byrdreisyl:BAAALgAECgQJBAAAAA==.',
Ca='Caosgonewild:BAAALgAECgUJBQAAAA==.',
Ce='Celestyal:BAAALgADCgMJAwAAAA==.',
Ch='Chestie:BAABLgAECn8hAAMCAAkJdR1XTgDVAQACAAgJ6x1XTgDVAQAPAAIJOBqtJwCPAAAAAA==.Chubbychi:BAAALgAECgIJAgAAAA==.',
Ci='Cinde:BAAALgADCgMJAwABLgAFFAQJCwAMADscAA==.Cindy:BAACLgAFFH8LAAIMAAQJOxxGLQBQAQAMAAQJOxxGLQBQAQAuAAQKfyQAAwwACQkOHpgWAJwCAAwACQkOHpgWAJwCABAAAQneBZ2RACkAAAAA.Cindyx:BAAALgAECgYJDwABLgAFFAQJCwAMADscAA==.',
Co='Coast:BAABLgAECn8VAAIRAAgJ1weJGADbAAARAAgJ1weJGADbAAAAAA==.Coldlock:BAAALgAECggJCAABLgAECgkJMAASAAUaAA==.Coldsore:BAABLgAECn8wAAQSAAkJBRpSCgAiAgASAAkJ4RlSCgAiAgABAAYJ+wbfUgDqAAAEAAMJMQcLKQGDAAAAAA==.Coldwar:BAAALgADCgcJBwAAAA==.Conjuremoney:BAAALgADCgEJAQAAAA==.Cootpal:BAABLgAECn8+AAIEAAkJDB7YGQCnAgAEAAkJDB7YGQCnAgAAAA==.Costcohotdog:BAAALgADCgMJAwAAAA==.',
Cr='Crazyloon:BAAALgAECgUJCQAAAA==.Crewmix:BAAALgAECgEJAQAAAA==.Crewshield:BAAALgADCgMJAwAAAA==.Croe:BAAALgADCgMJAwAAAA==.',
Cy='Cynawyne:BAAALgAECgEJAQAAAA==.Cynthea:BAAALgAECgkJCgAAAA==.',
Da='Dahm:BAAALgAECgMJBgAAAA==.Dalasaurs:BAACLgAFFH8IAAIFAAMJxxm1LgDvAAAFAAMJxxm1LgDvAAAuAAQKfzAAAgUACAmTGKMoABoCAAUACAmTGKMoABoCAAAA.Dalasnipus:BAAALgADCgMJAwAAAA==.Dalbear:BAAALgADCgYJCQAAAA==.Darkpallas:BAAALgAECgYJCAAAAA==.Darkprophetc:BAABLgAECn8xAAIOAAkJTwwdZQCwAQAOAAkJTwwdZQCwAQAAAA==.',
De='Deathfyre:BAAALgADCgQJBAAAAA==.Deluun:BAAALgADCgkJCQAAAA==.Demious:BAABLgAECn8ZAAIMAAkJqh+pEQDAAgAMAAkJqh+pEQDAAgAAAA==.Demiurge:BAEALgAECgkJEAAAAA==.Demonfister:BAACLgAFFH8JAAIFAAMJwQxcOQDFAAAFAAMJwQxcOQDFAAAuAAQKfygAAgUACQn+G/YMAJsCAAUACQn+G/YMAJsCAAAA.Demonkiller:BAABLgAECn8eAAITAAYJPAbXQACuAAATAAYJPAbXQACuAAAAAA==.Denastiest:BAABLgAECn8tAAIDAAkJDA+nTACcAQADAAkJDA+nTACcAQAAAA==.Denji:BAAALgAECggJEAAAAA==.Devvmonk:BAAALgAECgcJEwAAAA==.',
Di='Dindaratwo:BAAALgAFFAEJAQAAAA==.',
Do='Doe:BAABLgAECn8pAAMUAAcJmyOKBQBJAgAUAAcJmyOKBQBJAgATAAMJhhD+UgCdAAAAAA==.Dokta:BAABLgAECn8YAAIVAAgJMA8yHABRAQAVAAgJMA8yHABRAQAAAA==.',
Dr='Draflex:BAAALgAECgMJBAAAAA==.Drathal:BAABLgAECn81AAIEAAkJ1AfeiABcAQAEAAkJ1AfeiABcAQAAAA==.Drjay:BAAALgADCgkJCwAAAA==.',
Dv='Dvergar:BAAALgAECgYJDAAAAA==.',
Ea='Eatshrooms:BAAALgAECgMJBAAAAA==.',
Ed='Edd:BAAALgAECgQJBAAAAA==.Eddiedean:BAAALgAECgYJBgAAAA==.',
El='Elessarr:BAAALgAECgEJAQAAAA==.Elfgonewild:BAAALgAECgUJCgAAAA==.Ellessra:BAABLgAECn8mAAIOAAkJWwPjsgAaAQAOAAkJWwPjsgAaAQAAAA==.Elnegrouno:BAABLgAECn8fAAIVAAcJfR/SCgBjAgAVAAcJfR/SCgBjAgAAAA==.Eloper:BAAALgAFFAEJAQAAAA==.',
Em='Emotank:BAAALgAECgUJBgAAAA==.',
Er='Eragone:BAAALgAECgMJBQAAAA==.',
Et='Etoro:BAAALgADCgEJAgAAAA==.',
Ev='Evissier:BAACLgAFFH8OAAIWAAQJZh8hAwBkAQAWAAQJZh8hAwBkAQAuAAQKfx0AAhYACAmuIAcBAAIDABYACAmuIAcBAAIDAAAA.',
Ex='Exsequor:BAACLgAFFH8RAAISAAQJIiH9AgB+AQASAAQJIiH9AgB+AQAuAAQKfx0AAxIABgkLI/ASAJcBABIABgkLI/ASAJcBAAQAAQlyB/tQASsAAAAA.',
Ez='Ezuras:BAAALgADCgIJAgAAAA==.',
Fa='Faeyri:BAABLgAECn8tAAILAAkJLhryEABoAgALAAkJLhryEABoAgAAAA==.Fassandin:BAAALgAECgIJAgAAAA==.',
Fe='Felli:BAAALgAECgEJAQAAAA==.',
Fi='Fishermon:BAAALgAECgUJCAAAAA==.',
Fl='Flagfarmer:BAABLgAECn8dAAIBAAYJMSb8EACMAgABAAYJMSb8EACMAgAAAA==.Flataxe:BAAALgAECgMJAwAAAA==.Flixunt:BAAALgADCgEJAQAAAA==.',
Fo='Foidepas:BAAALgAECgcJDQAAAA==.Fourid:BAAALgAECgQJDAAAAA==.Foxannee:BAAALgAECgMJBgAAAA==.',
Fr='Freezyweezy:BAACLgAFFH8LAAIOAAQJ4RtdTQBLAQAOAAQJ4RtdTQBLAQAuAAQKfx8AAg4ACQnoI2cdAKkCAA4ACQnoI2cdAKkCAAAA.Frostfirer:BAAALgAECgYJAgAAAA==.',
Fu='Fudgeyenuh:BAAALgAECgkJCQAAAA==.',
Fy='Fyrewar:BAAALgAECgMJAwAAAA==.',
['Fú']='Fúry:BAAALgAECgcJCQAAAA==.',
Ga='Gallyn:BAABLgAFFH8OAAIXAAMJLh2cJAD3AAAXAAMJLh2cJAD3AAAAAA==.Gamm:BAAALgADCgcJEQAAAA==.Garaal:BAAALgAECgcJEAAAAA==.',
Ge='Gerel:BAAALgAECgYJBgAAAA==.',
Gi='Ginyu:BAAALgAECgIJBAAAAA==.',
Gl='Glacierrock:BAAALgADCgQJCgAAAA==.Gloria:BAABLgAECn8hAAIYAAkJ1AmjTAB6AQAYAAkJ1AmjTAB6AQAAAA==.',
Go='Gooblicious:BAAALgAECgEJAQAAAA==.Gori:BAAALgAECgIJAgAAAA==.',
Gr='Grail:BAABLgAECn8eAAIEAAcJ4A0CogAyAQAEAAcJ4A0CogAyAQAAAA==.Grelvisse:BAAALgAECgMJBQAAAA==.Grippywippy:BAAALgADCgYJBAAAAA==.',
Gu='Gudren:BAAALgADCgEJAQAAAA==.Guimon:BAAALgAECgMJBAAAAA==.Gunslinger:BAAALgAECgEJAQAAAA==.',
Gw='Gwenie:BAABLgAECn8mAAIKAAkJYhE5PQDmAQAKAAkJYhE5PQDmAQAAAA==.',
Ha='Halenicion:BAAALgAFFAEJAQAAAA==.Hauntfrost:BAAALgAECgEJAQAAAA==.Hazél:BAAALgADCgYJBgAAAA==.',
He='Helix:BAAALgAECgIJAgAAAA==.',
Hi='Hippoltyos:BAABLgAECn8sAAIGAAkJnA59JQCUAQAGAAkJnA59JQCUAQAAAA==.',
Ho='Honestlee:BAAALgAECgQJBAAAAA==.Honourablee:BAAALgAECgcJCgAAAA==.Hortzul:BAAALgADCgMJAwABLgAFFAUJGQABABkfAA==.Hotsaucce:BAAALgADCgEJAQAAAA==.Hotstheboss:BAAALgADCgYJBgAAAA==.Houe:BAAALgADCgUJCAAAAA==.',
Hu='Huffle:BAAALgAECgEJAQAAAA==.Huntardiness:BAABLgAECn8gAAQZAAgJrhH/JAB1AQAMAAcJ5RJLUAB4AQAZAAgJFgr/JAB1AQAQAAEJ7g7pPAAuAAAAAA==.Hunterd:BAAALgADCgEJAQAAAA==.',
Hy='Hymnals:BAACLgAFFH8NAAIFAAQJVCZkCQDAAQAFAAQJVCZkCQDAAQAuAAQKfxcAAwUACAlRJO4OANwCAAUACAlRJO4OANwCABoAAgkHGn1SAIQAAAAA.',
Ia='Ianmaris:BAAALgADCgQJBQAAAA==.',
Ic='Icealia:BAAALgAECgEJAQABLgAFFAQJEwAbAJIIAA==.Icelandite:BAAALgAECgYJBgAAAA==.',
Iv='Ive:BAABLgAECn8fAAQRAAkJ/CF2EQDBAQARAAcJzBp2EQDBAQAKAAgJGCIjWgCOAQAWAAIJHBD0JABeAAAAAA==.',
Ja='Jackburton:BAAALgAECgIJAgAAAA==.Jaddie:BAAALgAECgkJEwAAAA==.Jarnunvosk:BAABLgAECn8kAAMcAAkJxBSHCgA0AgAcAAkJxBSHCgA0AgAdAAEJbwOxmwAhAAAAAA==.Jasmindinn:BAAALgADCgcJDgAAAA==.Jayber:BAABLgAECn8qAAMeAAgJpRG9HwDNAQAeAAgJpRG9HwDNAQAHAAEJmQA5mwAHAAAAAA==.',
Je='Jezadora:BAAALgADCgEJAQAAAA==.',
Jo='Jolkom:BAAALgAECgMJBgABLgAECgkJFwAVACQcAA==.',
Ju='Julantis:BAAALgAECgYJBgAAAA==.',
Ka='Kadri:BAAALgAFFAEJAQAAAA==.Kaffee:BAABLgAECn81AAISAAkJ7A8xEwCTAQASAAkJ7A8xEwCTAQAAAA==.Kamakaz:BAAALgAECgcJCQAAAA==.Kamasdruid:BAAALgAECggJDAAAAA==.Kamasmage:BAAALgADCgcJBwAAAA==.Kamasmonk:BAAALgAECgYJBwAAAA==.Kamasux:BAAALgADCgYJBwAAAA==.Kandi:BAAALgADCgQJCgAAAA==.Kaviryon:BAAALgAECgEJAwAAAA==.Kaywhy:BAABLgAECn8VAAIHAAkJUxxmJQCeAQAHAAkJUxxmJQCeAQAAAA==.',
Ki='Kichack:BAABLgAECn8tAAMJAAkJ+B8gBwDWAgAJAAkJ+B8gBwDWAgAfAAYJDxQbQQBhAQAAAA==.Kitarvie:BAAALgAECgEJAgAAAA==.',
Kj='Kjdh:BAABLgAECn8oAAITAAgJSCKyCQCMAgATAAgJSCKyCQCMAgAAAA==.',
Kl='Kladuum:BAAALgADCgYJGQAAAA==.',
Kn='Knuckles:BAABLgAECn8UAAIFAAgJLhb3IQDhAQAFAAgJLhb3IQDhAQAAAA==.',
Ko='Kogun:BAAALgAECgQJBAAAAA==.Kowala:BAABLgAECn8cAAIgAAkJvw9iJwCQAQAgAAkJvw9iJwCQAQAAAA==.Kowpox:BAAALgADCgkJCgAAAA==.Kozalth:BAAALgADCgEJAgAAAA==.',
Kr='Krabi:BAAALgADCgYJCwAAAA==.Kranks:BAAALgAECgEJAQAAAA==.Kreios:BAAALgAECgYJBwAAAA==.Krelo:BAABLgAECn8mAAIYAAkJ0B3MCwD6AgAYAAkJ0B3MCwD6AgAAAA==.',
Kt='Ktom:BAABLgAECn8zAAILAAkJGiX9AgBBAwALAAkJGiX9AgBBAwAAAA==.',
Ku='Kurimbory:BAAALgAECgUJBQAAAA==.',
Ky='Kyruan:BAAALgADCgEJAQAAAA==.',
['Ký']='Kýlê:BAABLgAECn8ZAAMMAAgJmwdIUgByAQAMAAgJmwdIUgByAQAQAAYJ6gLLWQDdAAAAAA==.',
La='Lancelot:BAAALgAECgYJCAAAAA==.Lanthuil:BAAALgAECgQJBAAAAA==.',
Li='Lifepooll:BAAALgAECgEJAQABLgAFFAIJAQANAAAAAA==.Lilyselah:BAAALgADCgYJBwAAAA==.Littlelocky:BAAALgADCgcJEwAAAA==.Liv:BAABLgAECn8UAAIHAAgJtQu6LgBsAQAHAAgJtQu6LgBsAQAAAA==.',
Ll='Llamallab:BAAALgADCgcJBwAAAA==.',
Lo='Lostmyghoul:BAACLgAFFH8GAAICAAMJTBkjhQD6AAACAAMJTBkjhQD6AAAuAAQKfycAAgIACQkoH0EWAL8CAAIACQkoH0EWAL8CAAAA.Lostwarrior:BAAALgAECgUJBQAAAA==.Louhi:BAAALgAECgMJBQABLgAECgMJCAANAAAAAA==.',
Lu='Luglug:BAAALgAECgEJAQAAAA==.Lunar:BAABLgAECn8mAAIgAAkJkR+OBwDbAgAgAAkJkR+OBwDbAgAAAA==.Lunasea:BAAALgAECgMJAwAAAA==.',
Ly='Lysol:BAAALgADCgUJBQAAAA==.Lystat:BAAALgAECgUJCwAAAA==.',
Ma='Magicfungus:BAAALgADCgUJCQAAAA==.Magno:BAAALgADCgIJAgAAAA==.Magra:BAABLgAECn8YAAIOAAYJnwxixQD+AAAOAAYJnwxixQD+AAAAAA==.Magêyalook:BAABLgAECn8nAAIOAAgJthlxPgAfAgAOAAgJthlxPgAfAgAAAA==.Mangel:BAAALgADCgYJBgAAAA==.Manzz:BAAALgAECgUJCgAAAA==.Marcelline:BAAALgADCgYJEgAAAA==.Mattob:BAAALgADCgkJDwAAAA==.Maximus:BAAALgADCgkJEAAAAA==.Maznificent:BAAALgADCggJDQAAAA==.Mazyme:BAAALgADCgQJCQAAAA==.',
Me='Meandmypal:BAACLgAFFH8UAAIZAAgJzBmFAQBMAgAZAAgJzBmFAQBMAgAuAAQKfy4AAhkACQk4JrsAAH4DABkACQk4JrsAAH4DAAAA.Mello:BAABLgAECn8xAAIaAAkJXx3LBQCmAgAaAAkJXx3LBQCmAgAAAA==.Mesteris:BAAALgADCgYJBgAAAA==.',
Mi='Midiane:BAAALgAECgEJAQAAAA==.Milim:BAAALgAFFAIJAgAAAA==.Mirba:BAABLgAECn8pAAIMAAkJbxX+KwApAgAMAAkJbxX+KwApAgAAAA==.',
Mo='Mongo:BAABLgAECn8wAAICAAkJ/R+qEADmAgACAAkJ/R+qEADmAgAAAA==.Monochrome:BAAALgAECgIJAgAAAA==.Monsterdeath:BAAALgAECgIJAgAAAA==.Moreicepls:BAABLgAECn8bAAIOAAgJ+wmClABMAQAOAAgJ+wmClABMAQAAAA==.Morené:BAAALgAECgQJBgAAAA==.Moxxee:BAAALgADCgkJGwAAAA==.',
Mu='Mushhmelu:BAAALgAECgEJAQAAAA==.',
My='Myiko:BAAALgAECgQJBAAAAA==.Mytharu:BAAALgADCgMJAwAAAA==.',
Na='Nareík:BAACLgAFFH8OAAMTAAQJpwfBGQDMAAADAAQJBQZOXADTAAATAAQJYAXBGQDMAAAuAAQKfyAAAgMACAlZEmhVAKMBAAMACAlZEmhVAKMBAAAA.',
Ne='Neriak:BAAALgADCgkJCQAAAA==.Neutrallee:BAAALgAECgEJAQAAAA==.Newa:BAAALgAECgUJCQAAAA==.',
Ni='Nightwater:BAACLgAFFH8TAAIbAAQJkgjUOQDBAAAbAAQJkgjUOQDBAAAuAAQKfykABBsACQmLFwknABUCABsACQmLFwknABUCACEAAglfCUxCAFMAACAAAQmKCN+QACwAAAAA.',
['Né']='Nébulien:BAABLgAECn8dAAIiAAgJNx6LCgAMAgAiAAgJNx6LCgAMAgAAAA==.',
Ok='Okkok:BAABLgAECn8XAAIOAAYJ8hCIwABjAQAOAAYJ8hCIwABjAQAAAA==.',
Or='Orchop:BAABLgAECn8YAAIiAAYJgQldIQDmAAAiAAYJgQldIQDmAAAAAA==.Orkrist:BAABLgAECn8XAAIMAAcJpRLPaABsAQAMAAcJpRLPaABsAQAAAA==.',
Oz='Oz:BAAALgADCgUJBQAAAA==.',
Pa='Paado:BAAALgADCgUJBQAAAA==.Pantryraider:BAAALgAECgkJCAAAAA==.Patriqt:BAAALgAECgEJAQAAAA==.Paulterian:BAAALgAECgYJBQAAAA==.Paymeforpi:BAAALgAECgMJAwAAAA==.',
Ph='Phelaeshio:BAABLgAECn8eAAICAAkJOxzcJQBqAgACAAkJOxzcJQBqAgAAAA==.',
Po='Poam:BAAALgAECgUJBQAAAA==.Poldalina:BAAALgADCgkJGwAAAA==.Power:BAABLgAECn8UAAICAAcJQQoepAAjAQACAAcJQQoepAAjAQAAAA==.',
Pr='Primevil:BAAALgADCgQJBAAAAA==.Prosthetic:BAAALgAECgEJAQAAAA==.Proverbs:BAAALgAFFAIJAgAAAA==.',
Pu='Pumplord:BAAALgAECgcJEQAAAA==.Punchyou:BAAALgADCgEJAQAAAA==.',
['På']='Pårts:BAAALgAFFAIJAQAAAA==.',
['Pù']='Pùff:BAAALgAECgUJCQAAAA==.',
Qu='Quazeemoto:BAAALgAECgEJAQAAAA==.',
Ra='Raeyna:BAAALgAECgIJBAABLgAECgkJHwARAPwhAA==.Raffern:BAAALgAECgMJAwAAAA==.Rainknuckles:BAABLgAECn8lAAIBAAgJVRaMJQDZAQABAAgJVRaMJQDZAQAAAA==.Rayshano:BAABLgAECn8WAAISAAcJBRqtEgCaAQASAAcJBRqtEgCaAQAAAA==.',
Re='Recklessone:BAAALgAECgEJAQAAAA==.Resia:BAAALgADCgQJAQAAAA==.Revocsid:BAAALgADCgkJFgAAAA==.Rezza:BAAALgADCgEJAQAAAA==.',
Ri='Rikka:BAAALgADCgMJAwAAAA==.',
Ro='Rottingtree:BAAALgAECgYJEAAAAA==.',
Ru='Rustynails:BAABLgAECn84AAIjAAkJGSTMAAAjAwAjAAkJGSTMAAAjAwAAAA==.',
Sa='Saffire:BAAALgADCgcJBwAAAA==.Salina:BAAALgAECgEJAQAAAA==.Saly:BAAALgADCgIJAQABLgADCggJDgANAAAAAA==.Samwitch:BAAALgAECgQJDwAAAA==.Sappaho:BAAALgADCgYJBwAAAA==.Satheirel:BAAALgADCgYJBwAAAA==.Savanti:BAAALgAECgEJAQAAAA==.Sazzul:BAAALgAECggJEgAAAA==.',
Sc='Scott:BAACLgAFFH8WAAIVAAUJgyA+AwBiAQAVAAUJgyA+AwBiAQAuAAQKfyUAAhUACQlnJNQDABMDABUACQlnJNQDABMDAAAA.Screamor:BAAALgAECgEJAQAAAA==.Screams:BAAALgADCgEJAQAAAA==.Screamz:BAABLgAECn8eAAITAAYJ6RhnJQBIAQATAAYJ6RhnJQBIAQAAAA==.Scynx:BAAALgAECggJEQAAAA==.',
Se='Seaka:BAABLgAECn8xAAQgAAkJihgrEgBCAgAgAAkJihgrEgBCAgAbAAcJYRaPPwCRAQAkAAIJxg7bWQBVAAAAAA==.Sebas:BAAALgAECgEJAQAAAA==.Sent:BAAALgADCggJDgAAAA==.Serion:BAAALgAECgQJBQABLgAFFAEJAQANAAAAAA==.Sernix:BAABLgAECn8oAAIYAAgJKxwCFgCXAgAYAAgJKxwCFgCXAgAAAA==.',
Sh='Shadegrim:BAAALgAECgQJBgAAAA==.Shadespawn:BAAALgADCgEJAQAAAA==.Shaeia:BAACLgAFFH8IAAILAAMJzxCEEQDcAAALAAMJzxCEEQDcAAAuAAQKfx8AAgsACQn0HLcNAMYCAAsACQn0HLcNAMYCAAAA.Shamanic:BAAALgAECgIJAgAAAA==.Shambat:BAAALgADCgYJBgAAAA==.Shangi:BAAALgADCgMJAgABLgAFFAQJEQASACIhAA==.Shekinah:BAAALgADCgEJAQAAAA==.Shen:BAAALgAECgQJBgAAAA==.Shiftyfans:BAAALgADCgMJAwABLgAECgcJEQANAAAAAA==.',
Si='Siatrath:BAAALgAECgEJAQABLgAFFAQJEQASACIhAA==.Sivtekeda:BAAALgAECgQJCQAAAA==.',
Sk='Sktibrew:BAACLgAFFH8TAAIIAAYJgSF1BACRAQAIAAYJgSF1BACRAQAuAAQKfxoAAggACAmDHRMRAI8CAAgACAmDHRMRAI8CAAAA.',
Sl='Slamin:BAAALgAECgEJAQAAAA==.Slash:BAABLgAECn8kAAITAAkJxReqEwD0AQATAAkJxReqEwD0AQAAAA==.Slyavane:BAABLgAECn84AAQWAAkJqBXGBgAJAgAWAAkJqBXGBgAJAgARAAcJaweaGwDFAAAKAAQJWwQE4QCYAAAAAA==.Slyice:BAAALgAECgEJBgAAAA==.',
Sm='Smokess:BAACLgAFFH8QAAMSAAUJmBrnBAA5AQASAAUJmBrnBAA5AQAEAAMJDxQiFgD7AAAuAAQKfx8AAxIACAnkIeAGAHECABIACAnKHeAGAHECAAQACAlAGZZKAAMCAAEuAAUUBgkJABUAdQoA.',
Sn='Snowwind:BAABLgAECn8fAAIGAAgJfQoZMwA2AQAGAAgJfQoZMwA2AQAAAA==.',
So='Solthea:BAAALgAECgkJBwAAAA==.Solymar:BAAALgAECgkJBwAAAA==.Sonar:BAABLgAECn8pAAIMAAkJ8h9xGQCIAgAMAAkJ8h9xGQCIAgAAAA==.Sonasai:BAAALgADCgkJGwAAAA==.Sonnybear:BAAALgADCgUJEQAAAA==.Soulhatcher:BAAALgAECgQJEAAAAA==.Soxs:BAABLgAECn8qAAMfAAkJNBrXDwChAgAfAAkJNBrXDwChAgAJAAIJTg+vcgBnAAAAAA==.',
Sp='Spookymoo:BAAALgADCgQJBAAAAA==.',
St='Stabbywabby:BAAALgAECgYJBwAAAA==.Stardris:BAABLgAECn8bAAIDAAgJawKIqAC/AAADAAgJawKIqAC/AAAAAA==.Stenaris:BAAALgAECgIJAwAAAA==.Stompygnome:BAAALgAECggJEgAAAA==.Strooth:BAAALgADCgQJBAAAAA==.',
Ta='Talavel:BAAALgADCgIJAgAAAA==.Tartanus:BAABLgAECn8tAAIDAAkJXxflLQAMAgADAAkJXxflLQAMAgAAAA==.Taulogit:BAAALgAECgIJAgAAAA==.Tayzetv:BAAALgAECgMJAwABLgAFFAMJBwAiAGcOAA==.',
Te='Tentaclepwn:BAAALgADCgMJAwAAAA==.Teramiah:BAAALgADCgcJFAAAAA==.',
Th='Thanestra:BAAALgAECgkJBwAAAA==.Theadona:BAABLgAECn8oAAIEAAgJNR3zLABLAgAEAAgJNR3zLABLAgAAAA==.Thorall:BAAALgADCgkJDwAAAA==.Thylight:BAAALgADCgMJAwAAAA==.',
Ti='Tikcus:BAAALgADCgcJEAAAAA==.Tils:BAAALgADCggJDwAAAA==.Tippy:BAACLgAFFH8bAAMPAAYJmho8BACwAQAPAAUJmho8BACwAQAlAAIJuQE0RAAgAAAuAAQKfzYABA8ACQloISQDALsCAA8ACQkQISQDALsCAAIAAwkNBskDAXAAACUAAgl1Di1KAGIAAAAA.',
To='Toastedwings:BAAALgADCgcJDwAAAA==.Tombstone:BAAALgAECgYJEgAAAA==.Toowongfoo:BAACLgAFFH8aAAIJAAYJsB8QBQDGAQAJAAYJsB8QBQDGAQAuAAQKfycAAgkACQm4I54DACUDAAkACQm4I54DACUDAAAA.',
Tr='Trewer:BAAALgADCgIJAgAAAA==.Trisara:BAABLgAECn81AAIgAAkJrwhxNABCAQAgAAkJrwhxNABCAQAAAA==.',
Tu='Tunechi:BAAALgAECgEJAQAAAA==.',
Ty='Tygrana:BAAALgAECgEJAQAAAA==.Tyradora:BAAALgAECgEJAQAAAA==.Tytannia:BAAALgADCgEJAQAAAA==.',
['Tö']='Töteman:BAABLgAECn8pAAILAAcJlBbiKwCTAQALAAcJlBbiKwCTAQAAAA==.',
['Tÿ']='Tÿtann:BAAALgAECgMJAwAAAA==.',
Um='Umbranecros:BAAALgAECgEJBQAAAA==.',
Un='Unbok:BAAALgAECgkJAQAAAA==.Underdog:BAABLgAECn8fAAMQAAgJuBR5DgByAQAQAAgJuBR5DgByAQAMAAEJAABBTgEAAAAAAA==.',
Up='Upthere:BAAALgADCgQJBAABLgAECgcJEwANAAAAAA==.',
Va='Vaerie:BAAALgAECgEJAQAAAA==.Vaern:BAABLgAECn8fAAIhAAgJtB0gCABKAgAhAAgJtB0gCABKAgAAAA==.Vaethorn:BAAALgAECgcJCAAAAA==.Vagindivin:BAAALgAECgcJDwAAAA==.Valrie:BAAALgAECgMJAwAAAA==.Valyteil:BAAALgAECgQJBAAAAA==.',
Ve='Venngance:BAABLgAECn8tAAQPAAkJxSP8AwCVAgAPAAgJTiD8AwCVAgAlAAYJZiTVFwCdAQACAAYJExSOrAAWAQAAAA==.',
Vi='Virus:BAAALgAECggJEQAAAA==.Vitner:BAAALgADCgMJAwAAAA==.',
Vo='Voidkity:BAAALgAECgQJBwAAAA==.Voidpriest:BAAALgAECgEJAQAAAA==.',
Vy='Vyrlet:BAAALgAECgEJAQAAAA==.',
Wa='Wakax:BAAALgAECgEJAQAAAA==.Walberson:BAAALgADCgYJBgAAAA==.Warfield:BAABLgAECn8fAAMkAAkJYxOIEwC3AQAkAAkJYxOIEwC3AQAhAAEJWgPkYAAcAAAAAA==.',
Wf='Wfbot:BAAALgAECgEJAQAAAA==.',
Wh='Whosbondt:BAAALgAECgYJCwAAAA==.',
Wi='Winafred:BAAALgAECgEJAQAAAA==.Wittwicky:BAAALgAECgEJAQAAAA==.',
Wk='Wkeyonly:BAABLgAECn8fAAIDAAkJYRUEXwBoAQADAAkJYRUEXwBoAQAAAA==.',
Wo='Woody:BAAALgADCgUJBQAAAA==.Wooter:BAAALgADCgYJDAAAAA==.Worthy:BAAALgAECgkJAwAAAA==.',
Wr='Wrathsome:BAABLgAECn8tAAIbAAkJoBOLJQAeAgAbAAkJoBOLJQAeAgAAAA==.',
Wu='Wunderbilly:BAAALgADCgEJAQAAAA==.',
['Wí']='Wísp:BAAALgAECgEJAQAAAA==.',
Xa='Xaernach:BAAALgAECgEJAQAAAA==.',
Xl='Xloon:BAAALgAECgEJAQAAAA==.',
Xy='Xypherus:BAAALgADCgkJDQAAAA==.',
['Xá']='Xándarl:BAAALgAECgMJBAAAAA==.',
Ya='Yakoda:BAAALgADCgUJBQAAAA==.Yaldabaoth:BAEALgAECgcJBQABLgAECgkJEAANAAAAAA==.Yanza:BAAALgAECgIJAgAAAA==.',
Ye='Yello:BAAALgADCgkJGwAAAA==.',
Za='Zaio:BAAALgAECgYJCQAAAA==.Zarkus:BAAALgAECgQJEgAAAA==.',
Ze='Zelphi:BAAALgAECgQJCAAAAA==.Zenha:BAAALgADCgEJAQAAAA==.Zephaadella:BAAALgAECgEJAQAAAA==.',
Zh='Zhuzi:BAAALgADCgkJDwAAAA==.',
Zs='Zshmokez:BAACLgAFFH8JAAIVAAYJdQrxFADzAAAVAAYJdQrxFADzAAAuAAQKfxsAAhUACQmrH1kFAMECABUACQmrH1kFAMECAAAA.',
['Åy']='Åylå:BAAALgAECgEJAQABLgAECgkJGAAXAO4VAA==.',
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
