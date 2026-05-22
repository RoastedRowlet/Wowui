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

local lookup = {'Priest-Shadow','Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Devourer','Monk-Brewmaster','Evoker-Preservation','Hunter-BeastMastery','Monk-Windwalker','Priest-Holy','Paladin-Protection','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Protection','Warrior-Fury','Mage-Frost','Hunter-Marksmanship','Hunter-Survival','Druid-Balance','Unknown-Unknown','Druid-Restoration','Druid-Guardian','Druid-Feral','Shaman-Restoration','Warrior-Arms','Evoker-Augmentation','Priest-Discipline','Warlock-Destruction','Warlock-Demonology','Monk-Mistweaver','Shaman-Elemental','Rogue-Assassination','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','Evoker-Devastation','DemonHunter-Vengeance','Paladin-Holy',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abukuma:BAAALgAECgIJAgAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8RAAIBAAgJAQYXQgDpAAABAAgJAQYXQgDpAAAAAA==.Aenstalash:BAABLgAECn8cAAICAAgJPiN9FQCEAgACAAgJPiN9FQCEAgAAAA==.Aephium:BAAALgAECgcJDQAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8jAAIDAAgJSRfpQgCzAQADAAgJSRfpQgCzAQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alaure:BAAALgADCgIJAgAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAAALgAECgcJEwAAAA==.',
Am='Amoona:BAAALgAECgYJEgABLgAECggJHQAEAPMiAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arfas:BAAALgADCgQJBAAAAA==.Arthraz:BAABLgAECn8jAAIFAAgJeh4VCwBIAgAFAAgJeh4VCwBIAgAAAA==.',
As='Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn8aAAIGAAYJyQ6fFAA1AQAGAAYJyQ6fFAA1AQAAAA==.',
Au='Aunaturale:BAAALgAECgkJAwAAAA==.Aureliá:BAABLgAECn8XAAIHAAcJnAqtXgAuAQAHAAcJnAqtXgAuAQAAAA==.',
['Aü']='Aütobot:BAABLgAECn8ZAAIIAAgJ0gwoIgBKAQAIAAgJ0gwoIgBKAQAAAA==.',
Ba='Badgirl:BAACLgAFFH8HAAIJAAMJowsHFwCzAAAJAAMJowsHFwCzAAAuAAQKfxcAAwkACAnqEe46AE8BAAkABglSFO46AE8BAAEABgktCjw2AOgAAAAA.Balnar:BAAALgAECgUJDgABLgAECgcJGwAKADkUAA==.Balraga:BAABLgAECn8ZAAILAAgJUAp+GwA5AQALAAgJUAp+GwA5AQAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Bega:BAACLgAFFH8XAAMDAAYJcB1LEgCtAQADAAUJcB1LEgCtAQAMAAEJAADqNQAAAAAuAAQKf0AAAwMACQnnJUgCAF4DAAMACQnnJUgCAF4DAAwABgkrFzslABUBAAAA.Benton:BAAALgAECgQJBwAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8lAAMNAAkJXhYOEgB4AQANAAgJKw8OEgB4AQAOAAcJahxZJwBwAQAAAA==.',
Bo='Bobster:BAABLgAECn8jAAIPAAgJ5RE5XwCBAQAPAAgJ5RE5XwCBAQAAAA==.Booyea:BAABLgAECn8vAAIMAAkJ/hkECABNAgAMAAkJ/hkECABNAgAAAA==.',
Br='Brewwnor:BAAALgAECgMJAwAAAA==.Brickdemkeys:BAABLgAECn8fAAIPAAgJPBr9QgDRAQAPAAgJPBr9QgDRAQAAAA==.Brisfloggnaw:BAAALgAFFAEJAQAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAYJEQAQAGQhAA==.Calamuelis:BAACLgAFFH8RAAQQAAYJZCHWBwCeAQAQAAYJjSDWBwCeAQARAAMJOiH4DgAgAQAHAAEJYx9dXQBTAAAuAAQKfx0ABBAACAnSJLsNANcCABAACAmWJLsNANcCABEABAn5JEUiADkBAAcAAQkIJq2vAGwAAAAA.Caliope:BAAALgAECgcJDgAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAECgkJBwAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgADCgQJBwABLgAECggJIwAFAHoeAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8dAAISAAUJARDLSQAEAQASAAUJARDLSQAEAQAAAA==.Cerelus:BAABLgAECn8XAAIPAAgJtQqEcgBVAQAPAAgJtQqEcgBVAQAAAA==.',
Ch='Chaac:BAAALgAECgYJBgABLgAECgYJBwATAAAAAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAABLgAECn8WAAUUAAgJVh7qLgCfAQAUAAYJUyDqLgCfAQAVAAQJCx7wEQBVAQASAAIJih97QQCwAAAWAAEJLwbeMgA2AAAAAA==.',
Cl='Clax:BAAALgAECgIJBQAAAA==.',
Co='Cobeam:BAAALgAECgQJCAAAAA==.Cowpernicus:BAABLgAECn8gAAIUAAgJWiFjCAD2AgAUAAgJWiFjCAD2AgABLgAECgkJPQAXALYiAA==.',
Cr='Crungleman:BAABLgAECn8UAAIHAAYJcxu+PwCwAQAHAAYJcxu+PwCwAQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECgYJBwATAAAAAA==.',
Cu='Curoi:BAABLgAECn8iAAMWAAgJ9w4fDgBzAQAWAAgJ9w4fDgBzAQAUAAcJUwgzeQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8MAAIOAAMJVhx0HAD7AAAOAAMJVhx0HAD7AAAuAAQKf0YAAw4ACQkSITgGAL8CAA4ACQkSITgGAL8CABgAAgl5H2ksAJEAAAAA.',
['Cê']='Cêlestial:BAABLgAECn8dAAMEAAgJ8yKjEQB0AgAEAAgJ8yKjEQB0AgALAAIJfBzuQABPAAAAAA==.',
Da='Daedalas:BAAALgAECgcJEAAAAA==.Damonk:BAAALgADCgYJBgABLgAECggJHwANAFcbAA==.Danevolent:BAABLgAECn8gAAMJAAcJ9yJ9DQCAAgAJAAcJ9yJ9DQCAAgABAAQJEA0pRQCeAAABLgAECggJHwANAFcbAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAABLgAECn8bAAIKAAcJORT8EABbAQAKAAcJORT8EABbAQAAAA==.Darthknull:BAACLgAFFH8JAAICAAMJLgpGQwDjAAACAAMJLgpGQwDjAAAuAAQKfygAAgIACQnAGQFNAPsBAAIACQnAGQFNAPsBAAAA.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBQABLgAECgEJAQATAAAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8iAAIQAAgJZhmcBwDBAQAQAAgJZhmcBwDBAQAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestrea:BAAALgAECgYJDwAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dippindots:BAAALgAECgYJCAAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAcJHQAZAIQiAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Donkform:BAAALgAECggJDQAAAA==.Donniyii:BAAALgADCgcJBwABLgAECgkJLwAaAJQfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAABLgAECn8aAAIbAAYJ8B0iCgBQAQAbAAYJ8B0iCgBQAQAAAA==.',
Dr='Draconith:BAACLgAFFH8GAAIGAAMJ7wnKFwC2AAAGAAMJ7wnKFwC2AAAuAAQKfysAAgYACQnfF/sFAGkCAAYACQnfF/sFAGkCAAAA.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAAALgAECgYJDwAAAA==.Dreddwing:BAAALgAECgYJBwAAAA==.',
Du='Dunsparrow:BAABLgAECn89AAIXAAkJtiI/AgBrAwAXAAkJtiI/AgBrAwAAAA==.Durzul:BAAALgAECgEJAQAAAA==.',
Ei='Eightyone:BAAALgAECggJDwAAAA==.Eindraken:BAABLgAECn8qAAIGAAkJiBJiCQAIAgAGAAkJiBJiCQAIAgAAAA==.Eisis:BAABLgAECn8wAAIWAAkJLBAqDACWAQAWAAkJLBAqDACWAQAAAA==.',
El='Elanalué:BAAALgAECgEJAgABLgAECgcJDgATAAAAAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.Erroz:BAAALgADCgIJAQAAAA==.',
Es='Eshonäi:BAABLgAECn8UAAIcAAYJdQ/NegAHAQAcAAYJdQ/NegAHAQAAAA==.Espriesso:BAAALgAECgUJCQABLgAECggJHwAdAHYNAA==.',
Ev='Evodragker:BAABLgAECn8jAAMZAAgJfBXYHgCQAQAZAAgJfBXYHgCQAQAGAAEJcwkdLwA0AAAAAA==.',
Fe='Feldron:BAAALgAECgcJEwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgAECgYJDAAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgADCgcJCAAAAA==.Flashx:BAAALgAECgYJEwAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8sAAMHAAkJYh+kEgCiAgAHAAkJYh+kEgCiAgAQAAUJAxLZTgAUAQAAAA==.Frofrolock:BAAALgAECgcJCwAAAA==.Froggie:BAABLgAECn8UAAMXAAcJfBVtNgB4AQAXAAcJfBVtNgB4AQAeAAMJXQ/iaACgAAAAAA==.Froshaman:BAAALgADCgkJCQAAAA==.',
Fu='Fuzywuuzy:BAACLgAFFH8FAAIUAAIJyw9JOQCJAAAUAAIJyw9JOQCJAAAuAAQKfx8AAxQACAnUI0IHAAoDABQACAnUI0IHAAoDABIAAwkXEwJPAHcAAAAA.',
Ga='Gazdorn:BAABLgAECn8hAAINAAgJZhO3EACNAQANAAgJZhO3EACNAQAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8gAAIfAAgJXBj3AwAYAgAfAAgJXBj3AwAYAgAAAA==.',
Gi='Gigof:BAABLgAECn8jAAMSAAkJ/xBsHwByAQASAAgJZBFsHwByAQAUAAYJQwlQigDAAAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQgAAcJdCWRAQDTAgAgAAcJEiWRAQDTAgAcAAMJhSJYogAUAQAbAAIJjxpcRACkAAAAAA==.',
Go='Gobah:BAABLgAECn8YAAMhAAgJ5hX4DQD4AQAhAAgJ5hX4DQD4AQAiAAUJsQerDwCrAAAAAA==.',
Gt='Gt:BAAALgAECgMJBQAAAA==.',
Gu='Gulldan:BAAALgAECgYJEQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Habanero:BAAALgAECgIJAwABLgAECggJIwAFAHoeAA==.Hadory:BAAALgAECgQJBQABLgAECgcJEgATAAAAAA==.Harrowhark:BAABLgAECn8dAAMgAAcJAwnnDQAMAQAgAAcJfwjnDQAMAQAbAAQJyQUCIwBeAAAAAA==.',
He='Hellzzdemon:BAAALgAECgcJCgAAAA==.Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJBQAAAA==.Hezekiiah:BAAALgAECgQJBAAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAECgkJPQAXALYiAA==.Holycannoli:BAAALgAECgcJCgAAAA==.Horiffic:BAAALgAECgcJEgAAAA==.Horok:BAAALgAECgYJDAAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAAALgAECgYJEQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAYJEwAEAAoVAA==.',
Ic='Ichaerus:BAAALgAECgQJBQABLgAECgcJEAATAAAAAA==.',
Ii='Iilli:BAABLgAECn8vAAMaAAkJlB/oAwAcAwAaAAkJlB/oAwAcAwABAAcJOxTYIABqAQAAAA==.',
In='Inari:BAAALgAECgYJEwAAAA==.Inkkubus:BAACLgAFFH8PAAQbAAUJbhkxDACXAAAcAAMJbBrhSQDrAAAbAAIJ+g4xDACXAAAgAAEJAAC5FgAAAAAuAAQKfxUABBsABwlqHfsPAPQAABwABQnFHuNkADYBABsAAwnpG/sPAPQAACAAAQkAABEnAFUAAAAA.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Iw='Iwkms:BAACLgAFFH8OAAIWAAQJihYvAwBlAQAWAAQJihYvAwBlAQAuAAQKfyMAAhYACAliIzMCADEDABYACAliIzMCADEDAAAA.',
Ja='Jade:BAABLgAECn8dAAIFAAYJ9CR9DwAHAgAFAAYJ9CR9DwAHAgAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQATAAAAAA==.Jeronor:BAAALgAECgIJAgAAAA==.',
Ji='Jimmick:BAAALgAECgcJEgAAAA==.Jisung:BAAALgAECgYJCwAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Jt='Jtheman:BAAALgAECgIJAgAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgYJCwAAAA==.Kaissa:BAAALgAECgEJAQAAAA==.Kalena:BAABLgAECn8vAAIPAAkJYg0kSgC6AQAPAAkJYg0kSgC6AQAAAA==.Kaos:BAABLgAECn8iAAIPAAgJIRNJWACSAQAPAAgJIRNJWACSAQAAAA==.Kariatyda:BAABLgAECn8uAAIHAAkJMBjZGQA+AgAHAAkJMBjZGQA+AgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgYJEwATAAAAAA==.Kassandra:BAABLgAECn8vAAIPAAkJnBnIHgBpAgAPAAkJnBnIHgBpAgAAAA==.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIdAAYJhBh2JACQAQAdAAYJhBh2JACQAQABLgAECggJEAATAAAAAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kelisola:BAAALgADCgEJAQAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.',
Ki='Kiloton:BAABLgAECn8eAAIVAAgJ3hAREwBMAQAVAAgJ3hAREwBMAQAAAA==.Kitzy:BAABLgAECn8ZAAIPAAgJ9wTTkAAcAQAPAAgJ9wTTkAAcAQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAABLgAECn8oAAIDAAkJUBZkKAAYAgADAAkJUBZkKAAYAgAAAA==.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAABLgAECn8hAAIUAAgJmwuvPwBKAQAUAAgJmwuvPwBKAQAAAA==.',
Ko='Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAABLgAECn82AAMOAAkJDCKzAwD6AgAOAAkJDCKzAwD6AgANAAUJrRIvKQCiAAAAAA==.',
Ky='Kylarian:BAABLgAECn8ZAAILAAgJSATEJwDVAAALAAgJSATEJwDVAAAAAA==.Kyntara:BAAALgAECgYJDAAAAA==.Kyronian:BAAALgAECgYJDwAAAA==.',
['Kâ']='Kâsâi:BAAALgAECgYJEwAAAA==.',
La='Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECgcJEAAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAABLgAECn8sAAICAAkJDBJlPADKAQACAAkJDBJlPADKAQAAAA==.',
Li='Lightbehunt:BAAALgAECgQJBgAAAA==.Lightfivhapy:BAAALgAECgUJBQAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Livaless:BAAALgADCgQJBAABLgAECgkJHwAcACoiAA==.',
Lu='Lucialyn:BAAALgAECgcJDAABLgAECgcJFwAaAOojAA==.',
Ly='Lyllith:BAABLgAECn8WAAIfAAYJjRG2CwAwAQAfAAYJjRG2CwAwAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECggJHwANAFcbAA==.Magnius:BAAALgADCgEJAQAAAA==.Mastablasta:BAAALgAECgIJBQAAAA==.Maursaline:BAABLgAECn8hAAIUAAgJMwhHTQASAQAUAAgJMwhHTQASAQAAAA==.Mawea:BAAALgAECgUJBQAAAA==.Mawks:BAABLgAECn8YAAIRAAgJaBdVCgA3AgARAAgJaBdVCgA3AgAAAA==.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgUJCgAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgADCgEJAQAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Mixxon:BAAALgAECgYJDgAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAABLgAECn8fAAIeAAkJMhewEgAGAgAeAAkJMhewEgAGAgAAAA==.Morhgana:BAAALgAECgYJDwAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMJAAgJygG3OADMAAAJAAgJygG3OADMAAABAAIJXwHWZQAtAAAAAA==.',
['Mö']='Mördecai:BAAALgAECgQJBAAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Nephele:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAECgQJCAAAAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAYJEwAEAAoVAA==.Nilius:BAAALgADCgcJBwABLgAECgcJEAATAAAAAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECgYJDAATAAAAAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAABLgAECn8XAAIKAAcJ6xC6FQAiAQAKAAcJ6xC6FQAiAQAAAA==.',
['Ní']='Níce:BAAALgAECgEJAgAAAA==.',
['Nü']='Nügs:BAAALgAECggJEwAAAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painlink:BAAALgAECgQJBAABLgAECgkJIAAOADsQAA==.Painnkiller:BAABLgAECn8sAAIHAAkJfhx0DwCOAgAHAAkJfhx0DwCOAgAAAA==.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAAALgAECgYJEQABLgAECggJIwAFAHoeAA==.Paxis:BAAALgAECggJDQAAAA==.',
Pe='Perriwinkle:BAABLgAECn8pAAQWAAgJahkpCwAQAgAWAAgJ0xcpCwAQAgAVAAcJ/xEHFgAoAQAUAAQJPwxMbgCnAAAAAA==.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAABLgAECn8UAAIUAAcJQhm2JgDTAQAUAAcJQhm2JgDTAQAAAA==.Phylloxeras:BAABLgAECn8vAAIDAAkJ8SLaBwABAwADAAkJ8SLaBwABAwAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powders:BAABLgAECn8yAAIPAAgJTxuBLAAlAgAPAAgJTxuBLAAlAgAAAA==.',
Pr='Proshot:BAABLgAECn8nAAIRAAgJ5SAZBQChAgARAAgJ5SAZBQChAgAAAA==.',
Pu='Puddles:BAAALgAECgEJAQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECggJHgAjAIkWAA==.',
Ra='Raccoon:BAABLgAECn8vAAIcAAkJkA3oOwCsAQAcAAkJkA3oOwCsAQAAAA==.Ravenhawk:BAAALgAECgQJCQAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAAALgAECgcJEAAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAACLgAFFH8TAAIEAAYJChWzFwBxAQAEAAYJChWzFwBxAQAuAAQKfyAAAwQACQlIH2ojAH0CAAQACQlIH2ojAH0CACQAAglxEwUmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8hAAMOAAgJOxGUKwBWAQAOAAgJOxGUKwBWAQAYAAIJtgb8RgBGAAAAAA==.Ryrín:BAAALgAECgYJBgAAAA==.',
Sa='Samidrac:BAAALgAECgUJDQAAAA==.Sammidormu:BAABLgAECn8jAAQjAAgJ5BMQBwCLAQAjAAcJABUQBwCLAQAZAAcJbAtZNgAgAQAGAAEJ2QEPTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Sarzul:BAABLgAECn8VAAMbAAYJ/A8VNADnAAAcAAYJ2gzAmwAiAQAbAAUJThEVNADnAAAAAA==.Satoshie:BAAALgAECgcJBwAAAA==.',
Sc='Scerevisiae:BAAALgAECgYJEAAAAA==.',
Se='Sedelis:BAABLgAECn8cAAIlAAgJoAv0KgBpAQAlAAgJoAv0KgBpAQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgAECgEJAQAAAA==.Semnai:BAABLgAECn8bAAIUAAYJ1RqdKgC5AQAUAAYJ1RqdKgC5AQAAAA==.Serafín:BAABLgAECn8vAAIFAAkJNQvTHgBxAQAFAAkJNQvTHgBxAQAAAA==.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAECgYJDgAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shadowpyro:BAAALgAECgEJAQAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shazzam:BAAALgAECgQJBQAAAA==.Shieldwall:BAABLgAECn8iAAINAAgJugiHGwAKAQANAAgJugiHGwAKAQAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8ZAAICAAgJ9RCTVgB9AQACAAgJ9RCTVgB9AQAAAA==.',
So='Solone:BAAALgAECgEJAQAAAA==.Sopidia:BAABLgAECn8kAAMXAAgJSRfqKADBAQAXAAcJtBbqKADBAQAeAAUJHQa1UQCYAAAAAA==.Sorvato:BAABLgAECn8bAAIEAAYJbRU6XgAcAQAEAAYJbRU6XgAcAQAAAA==.',
Sp='Spoonzz:BAABLgAECn8vAAMIAAkJrSO1AgAQAwAIAAkJrSO1AgAQAwAFAAIJKx/ZRQCrAAAAAA==.',
St='Stamavan:BAABLgAECn8jAAIVAAgJoCM5AwCtAgAVAAgJoCM5AwCtAgAAAA==.Starflayer:BAABLgAECn8nAAMEAAkJXhyqGABAAgAEAAkJbRuqGABAAgAkAAIJYxr3IAB8AAAAAA==.Sterjariger:BAAALgAECgYJBgABLgAECgkJHAAMAIIeAA==.',
Su='Sunari:BAAALgAECgMJBAAAAA==.Supermelon:BAAALgAECgcJEwAAAA==.',
Sw='Swenior:BAAALgADCgEJAQAAAA==.',
Sy='Sylvanaria:BAABLgAECn8vAAIXAAkJXCZeAADRAwAXAAkJXCZeAADRAwAAAA==.Sylvanaris:BAAALgAECgYJEQAAAA==.Systyx:BAABLgAECn8bAAIcAAcJbB9hNADHAQAcAAcJbB9hNADHAQAAAA==.',
Ta='Takura:BAAALgAECgcJBwABLgAECgkJCwATAAAAAA==.Talenel:BAAALgAECgQJBAAAAA==.Talyzien:BAAALgADCgYJBwAAAA==.',
Te='Tealan:BAABLgAECn8wAAMZAAkJtBgQDQBGAgAZAAkJtBgQDQBGAgAGAAgJqBLpHACeAQAAAA==.Tealyn:BAAALgADCgYJCgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8kAAIDAAgJCyWGFAAAAwADAAgJCyWGFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8dAAICAAYJ7Q6KpAA3AQACAAYJ7Q6KpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAABLgAECn82AAIMAAkJtx45BQCbAgAMAAkJtx45BQCbAgAAAA==.Thràll:BAAALgAECgUJBQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJEgATAAAAAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
To='Totemtuggér:BAAALgADCgIJAgAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trout:BAAALgADCgYJDAABLgAECgYJCgATAAAAAA==.Trovikk:BAAALgADCgUJBgAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwATAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgYJBwAAAA==.',
Ul='Ulfast:BAABLgAECn8eAAIeAAgJ/x1nEQAUAgAeAAgJ/x1nEQAUAgAAAA==.',
Va='Valarios:BAAALgAECgYJCgAAAA==.Vannhellsing:BAABLgAECn8iAAIDAAgJCwijcgA1AQADAAgJCwijcgA1AQAAAA==.Vanyel:BAABLgAECn83AAIPAAgJNxAfVwCWAQAPAAgJNxAfVwCWAQAAAA==.Vaudorka:BAABLgAECn8bAAIjAAgJ2R7/AgA6AgAjAAgJ2R7/AgA6AgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJEAATAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn8pAAMaAAkJjg8/FADjAQAaAAkJYQ4/FADjAQAJAAcJzghEMgD3AAAAAA==.Vemal:BAABLgAECn8eAAIHAAkJuQ4MNQC2AQAHAAkJuQ4MNQC2AQAAAA==.',
Vo='Vociferoy:BAABLgAECn81AAIHAAkJWSHgBwDgAgAHAAkJWSHgBwDgAgAAAA==.Voidsteffan:BAAALgAECgYJEwAAAA==.',
Vr='Vryadox:BAAALgAECgcJDQABLgAFFAMJBQAYABkgAA==.',
Vv='Vv:BAACLgAFFH8vAAIEAAgJrCRnAAACAwAEAAgJrCRnAAACAwAuAAQKfzAAAgQACQm1JucAANoDAAQACQm1JucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgMJAwAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
Xa='Xalmo:BAAALgADCgUJBQAAAA==.Xalzi:BAAALgADCggJCQABLgAECgcJFAAXAHwVAA==.',
Xi='Xingwong:BAABLgAECn8uAAIhAAgJGiUtAwDbAgAhAAgJGiUtAwDbAgAAAA==.',
Za='Zannytoes:BAABLgAECn8iAAMdAAgJLA0GLQA6AQAdAAgJLA0GLQA6AQAIAAEJLxFobwAzAAAAAA==.',
Ze='Zead:BAAALgAECgEJAwAAAA==.Zerana:BAABLgAECn8UAAIbAAkJowscCQBmAQAbAAkJowscCQBmAQAAAA==.Zeriea:BAAALgADCgEJAQAAAA==.Zevtra:BAAALgADCgEJAQAAAA==.',
Zi='Zie:BAABLgAECn82AAIBAAgJsxREGACxAQABAAgJsxREGACxAQAAAA==.Zikren:BAAALgAECggJCAAAAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAABLgAECn8TAAIEAAgJlxzBHAAkAgAEAAgJlxzBHAAkAgAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAACLgAFFH8OAAIOAAQJmCOPBACgAQAOAAQJmCOPBACgAQAuAAQKfxcAAg4ACAljHbUaAMkBAA4ACAljHbUaAMkBAAAA.',
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
