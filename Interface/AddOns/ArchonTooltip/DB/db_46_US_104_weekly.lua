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

local lookup = {'Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Warlock-Destruction','DeathKnight-Frost','Monk-Mistweaver','Priest-Discipline','Shaman-Elemental','Hunter-BeastMastery','Druid-Balance','Paladin-Protection','Unknown-Unknown','Mage-Frost','Druid-Restoration','Paladin-Retribution','Paladin-Holy','Monk-Brewmaster','Hunter-Marksmanship','Hunter-Survival','Priest-Holy','Priest-Shadow','Warrior-Fury','Shaman-Enhancement','Monk-Windwalker','Evoker-Devastation','Warrior-Protection','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Affliction','DeathKnight-Unholy','DeathKnight-Blood','Mage-Arcane','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms','Mage-Fire',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aartoo:BAAALgADCgUJBwAAAA==.',
Ac='Ace:BAAALgAFFAIJAwAAAA==.Ackreshanot:BAABLgAECn8VAAMBAAcJ2gvJOQAdAQABAAcJ2gvJOQAdAQACAAUJcxJRGgAPAQABLgAFFAQJFAADAGEdAA==.Acuminada:BAAALgADCgcJCwAAAA==.Acuna:BAABLgAECn8qAAIEAAcJfxPgCwBTAQAEAAcJfxPgCwBTAQAAAA==.',
Ad='Adamantine:BAAALgAECgcJEQAAAA==.',
Ae='Aere:BAABLgAECn8aAAIFAAcJ+iRSAwB3AgAFAAcJ+iRSAwB3AgAAAA==.Aerotika:BAAALgADCgcJBwAAAA==.',
Ai='Airz:BAABLgAECn8nAAIGAAgJvhwEDQCVAgAGAAgJvhwEDQCVAgAAAA==.',
Ak='Akennethpaly:BAAALgADCgQJBwAAAA==.Aknou:BAAALgADCgQJBAAAAA==.Akrichie:BAAALgAECgEJAQABLgAFFAgJEwAHAMcJAA==.Akudama:BAAALgAECgUJCAAAAA==.Akâkiôs:BAABLgAECn8pAAIIAAgJKxYDHgDFAQAIAAgJKxYDHgDFAQAAAA==.',
Al='Aladorman:BAABLgAECn8eAAIJAAcJPwj/ewAYAQAJAAcJPwj/ewAYAQAAAA==.Albertlin:BAABLgAECn8WAAIKAAgJ8xS8GwC9AQAKAAgJ8xS8GwC9AQAAAA==.Aldin:BAABLgAECn8aAAILAAYJnA3LJgCxAAALAAYJnA3LJgCxAAAAAA==.Aleisterr:BAAALgADCgEJAQAAAA==.Alexpaladin:BAAALgADCgEJAQAAAA==.Altarya:BAAALgAECgYJBgABLgAECgcJDgAMAAAAAA==.Altex:BAABLgAECn8tAAINAAkJ8hqqIgB3AgANAAkJ8hqqIgB3AgAAAA==.Altexa:BAAALgADCgMJAwABLgAFFAMJBAAMAAAAAA==.Altriimus:BAAALgAECgQJDgAAAA==.',
Am='Amakuagsak:BAABLgAECn8rAAIJAAgJ0g+MUACDAQAJAAgJ0g+MUACDAQAAAA==.Amaterásu:BAAALgAECgEJAQAAAA==.Amicus:BAABLgAECn8lAAIOAAgJyxC4NQCgAQAOAAgJyxC4NQCgAQAAAA==.Amistadcurry:BAAALgAECgMJAgAAAA==.',
An='Anadarmas:BAAALgAECgUJBwAAAA==.Ancestor:BAAALgADCgUJBQAAAA==.Aneki:BAAALgAECgEJAQAAAA==.Angelcastiel:BAAALgADCgEJAQAAAA==.Anothertalas:BAAALgAECgIJAQAAAA==.Anthracss:BAAALgAFFAMJAwAAAA==.Anthren:BAAALgADCgYJBgABLgAECgIJAwAMAAAAAA==.Anthrun:BAAALgADCgEJAgABLgAECgIJAwAMAAAAAA==.',
Ao='Aoifè:BAAALgAECgMJDwAAAA==.',
Ap='Apollo:BAACLgAFFH8HAAMPAAMJvgksUwDbAAAPAAMJvgksUwDbAAAQAAMJ2QZQKgCqAAAuAAQKfyQAAw8ACAnVGpFUAK0BAA8ACAnVGpFUAK0BABAAAwnPC2xmAGgAAAAA.Apolynnae:BAAALgADCgMJAwABLgAECgkJNgANAB8cAA==.Apolynnæ:BAABLgAECn8bAAIBAAkJNCCGBQDwAgABAAkJNCCGBQDwAgABLgAECgkJNgANAB8cAA==.',
Aq='Aquanoria:BAAALgADCggJEwAAAA==.',
Ar='Aragaren:BAAALgAECgYJDAAAAA==.Arasthel:BAAALgAECgkJDAAAAA==.Arauco:BAAALgAECgIJAgABLgAFFAMJBgARAHsTAA==.Arthalion:BAAALgAECgEJAQAAAA==.Arvellonwen:BAAALgADCgEJAQAAAA==.Aryasilly:BAABLgAECn8UAAIJAAkJphOzJAAkAgAJAAkJphOzJAAkAgAAAA==.',
As='Ascalapha:BAAALgAECgcJBwAAAA==.Ashe:BAACLgAFFH8eAAMSAAYJQyaFAwAMAgASAAYJbSWFAwAMAgATAAQJTSX3AwChAQAuAAQKfzcAAxIACQmhJkIAAPADABIACQmdJkIAAPADABMABwl5JPYJAGYCAAAA.',
At='Athenix:BAAALgAECgkJCQAAAA==.Atownbrew:BAAALgADCgkJCQAAAA==.Attabubble:BAAALgADCgEJAQABLgAFFAYJEgAJAM8bAA==.Attaraxia:BAACLgAFFH8SAAIJAAYJzxvdDgCKAQAJAAYJzxvdDgCKAQAuAAQKfywAAwkACQlFI/sJAPgCAAkACQlFI/sJAPgCABIAAQm4AYiZABsAAAAA.',
Au='Aure:BAAALgADCgMJAwAAAA==.Aurelith:BAAALgADCgMJBAAAAA==.Auvona:BAAALgAECgYJCAAAAA==.',
Av='Avalora:BAAALgADCgcJCQAAAA==.',
Az='Azaleth:BAAALgAECgYJBgAAAA==.Azavin:BAABLgAECn8WAAIQAAgJNgwLNgCkAQAQAAgJNgwLNgCkAQABLgAFFAQJCgABAHEQAA==.Azol:BAAALgAECgEJAQABLgAECgEJAgAMAAAAAA==.Azu:BAAALgADCgEJAQAAAA==.',
Ba='Babba:BAAALgADCgQJBAAAAA==.Baddington:BAABLgAECn8WAAIPAAkJDxx9EwCyAgAPAAkJDxx9EwCyAgAAAA==.Baegar:BAAALgAECggJCQAAAA==.Bakugo:BAACLgAFFH8ZAAIHAAUJ/htmDwDBAQAHAAUJ/htmDwDBAQAuAAQKfzIABAcACQmXIeoDAD8DAAcACQmXIeoDAD8DABQABgmNH/EgANsBABUABgmEFyotAEYBAAAA.Bamfbutcher:BAABLgAECn8aAAIWAAkJXxfKIgA/AgAWAAkJXxfKIgA/AgAAAA==.Banang:BAAALgADCgUJBQAAAA==.Barrimen:BAABLgAECn8sAAIPAAkJSgx1XACaAQAPAAkJSgx1XACaAQAAAA==.Bartolomew:BAAALgAECgkJMQAAAQ==.Bashton:BAAALgADCgMJAwAAAA==.Bastian:BAAALgADCgEJAQAAAA==.Batboy:BAAALgAECgYJEgAAAA==.',
Be='Bealzabung:BAAALgADCgMJAwABLgAECgcJCAAMAAAAAA==.Bedemere:BAAALgAECgEJAQAAAA==.Beepers:BAABLgAECn8fAAIJAAkJKg5kSgCWAQAJAAkJKg5kSgCWAQAAAA==.Behodahlia:BAABLgAECn8lAAIGAAkJrgmsOQAzAQAGAAkJrgmsOQAzAQAAAA==.Benezra:BAAALgAECgEJAQAAAA==.Bexurk:BAABLgAECn8bAAMXAAkJIwUnEwBEAQAXAAkJIwUnEwBEAQAIAAEJwgOSmAAiAAAAAA==.',
Bi='Biaku:BAAALgADCgIJAgAAAA==.Bibleman:BAAALgADCgIJAgABLgAECgcJHgAGAB8YAA==.Bigbilly:BAAALgADCgkJCQAAAA==.Bigcalcium:BAABLgAECn82AAIPAAgJFiaOBgBmAwAPAAgJFiaOBgBmAwAAAA==.Bigdemon:BAAALgAECgcJCwAAAA==.Bighimbo:BAABLgAECn8aAAIGAAYJYyBfGQAOAgAGAAYJYyBfGQAOAgAAAA==.Biltix:BAACLgAFFH8SAAMRAAUJnyEyDACJAQARAAQJnyEyDACJAQAYAAEJAABkOAAAAAAuAAQKfyIAAhEACQnpHsgSAHwCABEACQnpHsgSAHwCAAAA.Bimzelx:BAAALgAECgMJBQAAAA==.Bipolar:BAAALgAECgUJDAAAAA==.Bitterblood:BAABLgAECn8eAAIJAAcJwBU4UQCBAQAJAAcJwBU4UQCBAQAAAA==.',
Bl='Blanche:BAAALgADCgYJBgAAAA==.Blastgamer:BAAALgAECgMJBQAAAA==.Blindbob:BAAALgADCgUJBwAAAA==.Blindolomew:BAAALgAECgQJBAAAAA==.Blueb:BAAALgADCgkJEgABLgAFFAQJCgAUAGgTAA==.',
Bo='Boboe:BAAALgAECgIJAgABLgAFFAIJCAAHAD8cAA==.Bocaj:BAAALgADCgEJAQABLgAECggJLwANAHMdAA==.Boltbourne:BAAALgADCgUJBQAAAA==.Bolyn:BAAALgAECgIJAgAAAA==.Bonami:BAAALgADCgYJBgAAAA==.Bongwizard:BAAALgADCgUJBQAAAA==.Boogapib:BAAALgADCgEJAQAAAA==.Booshi:BAABLgAECn8dAAIOAAgJbhUdNwDLAQAOAAgJbhUdNwDLAQAAAA==.Bowiiesenpai:BAABLgAECn8lAAIVAAkJ6h82DQBcAgAVAAkJ6h82DQBcAgAAAA==.Bowmarc:BAABLgAECn8lAAIPAAkJ2RIVPQDwAQAPAAkJ2RIVPQDwAQAAAA==.Boykisser:BAAALgAECgUJBgAAAA==.',
Br='Bravehearth:BAAALgAECgMJBgABLgAECgcJCAAMAAAAAA==.Brewcifer:BAAALgADCgYJBgAAAA==.Brightxan:BAACLgAFFH8FAAILAAIJsREKDQBwAAALAAIJsREKDQBwAAAuAAQKfzQAAgsACQnaGkkGAFkCAAsACQnaGkkGAFkCAAAA.Broamdar:BAAALgAECgkJBgAAAA==.Brotha:BAAALgADCgUJCgAAAA==.Brownbeard:BAABLgAECn8qAAIFAAgJ6BJgCwB8AQAFAAgJ6BJgCwB8AQAAAA==.',
Bu='Bubbapriest:BAAALgADCgMJAwAAAA==.Bubbashaman:BAAALgAECgYJDQAAAA==.Budgetsushi:BAAALgADCgcJCwAAAA==.Burninator:BAABLgAECn8ZAAQZAAkJ5BWIEwCrAQAZAAYJrhmIEwCrAQABAAkJYhG3IgCpAQACAAIJJw1NQABoAAAAAA==.Bus:BAABLgAFFH8TAAIaAAcJoiEeAQD4AQAaAAcJoiEeAQD4AQABLgAFFAkJFwAbAJ8jAA==.Butterrs:BAAALgAECgUJGAAAAQ==.Butterz:BAABLgAECn8fAAIIAAkJuB5HCwDkAgAIAAkJuB5HCwDkAgABLgAECgUJGAAMAAAAAA==.',
Ca='Cadjin:BAAALgAECgEJAQAAAA==.Caelan:BAAALgAECgcJDAAAAA==.Caloren:BAACLgAFFH8HAAIcAAMJJxHlSADeAAAcAAMJJxHlSADeAAAuAAQKfzsABBwACQn7Ij0HAAQDABwACQn7Ij0HAAQDAB0AAwmfG48pAPYAAB4AAQnRGUYnAEMAAAAA.Calqlated:BAAALgADCgYJBgABLgAECggJHQAfAIsgAA==.Caorou:BAAALgADCgYJBgAAAA==.Captflower:BAAALgADCgUJBQAAAA==.',
Ce='Cedrid:BAAALgAECgcJDQAAAA==.Cenauria:BAAALgADCgYJBgAAAA==.',
Ch='Chanit:BAABLgAECn8dAAIPAAgJHxVzVgCpAQAPAAgJHxVzVgCpAQAAAA==.Chaosbeast:BAAALgADCgEJAQAAAA==.Charlemagnê:BAAALgAECgQJBAABLgAECggJKQAIACsWAA==.Charuzu:BAABLgAECn8UAAIGAAkJehqMFQAyAgAGAAkJehqMFQAyAgAAAA==.Chaurana:BAABLgAECn8uAAIeAAgJrBcvCADKAQAeAAgJrBcvCADKAQAAAA==.Chenzio:BAAALgADCgUJBQAAAA==.Chikorita:BAAALgAECgcJDgAAAA==.Chilidan:BAAALgAECgIJAgAAAA==.Chimichurri:BAAALgAECgMJAwAAAA==.Chipo:BAAALgAECgEJAgAAAA==.Chrilynn:BAABLgAECn8gAAMPAAcJnBsyeQBbAQAPAAYJiRkyeQBbAQALAAYJlBXmIgDNAAAAAA==.Chuwee:BAAALgADCgIJAgAAAA==.',
Ci='Cind:BAAALgADCgcJCAABLgAECgcJCQAMAAAAAA==.Cinderatrath:BAACLgAFFH8aAAMBAAYJxBQcEgB9AQABAAYJlRQcEgB9AQAZAAUJnxJaAwA4AQAuAAQKfzEAAxkACAkTIkkDAOsCABkACAkRIkkDAOsCAAEABwlcHBIYAPUBAAAA.Cindoreon:BAAALgAECgcJCQAAAA==.',
Cn='Cnydemon:BAAALgADCgEJAQAAAA==.',
Co='Corolla:BAAALgADCgYJBgAAAA==.Corsaro:BAAALgAECgYJEQAAAA==.Corvixius:BAABLgAECn8cAAIWAAgJ1gk4PQAoAQAWAAgJ1gk4PQAoAQAAAA==.',
Cr='Crunchwrap:BAAALgAECgYJEAAAAA==.',
Cu='Cuigy:BAABLgAECn8iAAIDAAgJ3CEADwCxAgADAAgJ3CEADwCxAgAAAA==.',
Cy='Cyriene:BAABLgAECn8hAAIJAAcJaRF9YgBTAQAJAAcJaRF9YgBTAQAAAA==.Cyrik:BAABLgAECn8fAAMgAAkJphsBAwBiAgAgAAkJphsBAwBiAgAEAAUJYhEXKQAeAQAAAA==.',
Da='Daevas:BAAALgADCgEJAQABLgAECgcJHgAGAB8YAA==.Dancinrain:BAAALgAECgEJAQAAAA==.Danksinatra:BAABLgAECn8aAAIhAAgJPxXPTgCzAQAhAAgJPxXPTgCzAQAAAA==.Danté:BAABLgAECn8dAAINAAgJrBrAUgA/AgANAAgJrBrAUgA/AgAAAA==.Dardorian:BAAALgAECgEJAgAAAA==.Darkfist:BAAALgAECgYJCgAAAA==.Darko:BAAALgAECgQJCgAAAA==.Darou:BAABLgAECn8gAAMFAAgJZA0lEQAcAQAFAAgJZA0lEQAcAQAiAAEJHQL5TwAVAAAAAA==.Daylen:BAABLgAECn8qAAMUAAgJFBD3JAB5AQAUAAgJFBD3JAB5AQAHAAEJSgHebwAZAAAAAA==.',
Dd='Ddeathchura:BAAALgAECgEJAQAAAA==.',
De='Deactrim:BAABLgAECn8WAAIiAAYJqRM2JAADAQAiAAYJqRM2JAADAQAAAA==.Deadploo:BAAALgADCgMJAwAAAA==.Deadpòól:BAAALgADCgUJBQABLgAECgIJAgAMAAAAAA==.Deafknights:BAAALgAFFAMJBAAAAA==.Deathgoat:BAAALgADCgIJAgAAAA==.Deku:BAAALgAECgQJCgABLgAECggJIAAbABkWAA==.Demiglace:BAABLgAECn8oAAQRAAgJmSYtAwAIAwARAAgJmSYtAwAIAwAYAAEJMRnAcwBEAAAGAAEJxxTDaAAwAAABLgAFFAgJLAAcADklAA==.Demonfloozie:BAAALgADCgkJCQAAAA==.Demongal:BAAALgADCgQJBAAAAA==.Dendrada:BAABLgAECn8oAAMhAAgJNyK8FwCXAgAhAAgJNyK8FwCXAgAFAAEJZyIlIgBkAAAAAA==.Deuce:BAAALgAECgYJBgAAAA==.Dewbie:BAACLgAFFH8OAAITAAYJDxfuAwChAQATAAYJDxfuAwChAQAuAAQKfy8AAhMACQkCHIsMAEECABMACQkCHIsMAEECAAAA.',
Di='Dirtyshim:BAAALgAECgMJAwAAAA==.Dizimo:BAABLgAECn8eAAIOAAgJYyJfCAAXAwAOAAgJYyJfCAAXAwAAAA==.',
Dm='Dminn:BAAALgAECgQJBQAAAA==.',
Do='Dogmeat:BAACLgAFFH8QAAIJAAUJEx1UAgB6AQAJAAUJEx1UAgB6AQAuAAQKfx8AAgkABwmiIqUWAIMCAAkABwmiIqUWAIMCAAEuAAUUBwkOAAoAyQ4A.Doncowleone:BAAALgADCgMJAwABLgAECgcJCAAMAAAAAA==.Doomslayer:BAAALgADCgcJDgAAAA==.Doreniel:BAAALgAECgkJAgAAAA==.Dormo:BAAALgAECgcJEAABLgAECgcJHgAGAB8YAA==.Dotisa:BAABLgAECn8VAAIKAAYJoA2fPADsAAAKAAYJoA2fPADsAAAAAA==.',
Dr='Dracks:BAABLgAECn8ZAAMNAAYJJByVdABzAQANAAYJJByVdABzAQAjAAEJww7zHAA5AAAAAA==.Drave:BAAALgAECgEJAQAAAA==.Draxker:BAABLgAECn8gAAIZAAkJZg78BgCvAQAZAAkJZg78BgCvAQAAAA==.Dreadmourne:BAAALgAECgUJBgAAAA==.Drfumanchu:BAAALgADCgkJEQABLgAECgcJCAAMAAAAAA==.Druddigon:BAAALgAECgUJCAABLgAECggJHQAfAIsgAA==.Druidtime:BAAALgAECgkJAwAAAA==.',
Du='Duna:BAABLgAECn8fAAINAAgJQAoagABbAQANAAgJQAoagABbAQAAAA==.Duvidressra:BAABLgAECn8wAAMgAAgJtxRxBwDDAQAgAAgJtxRxBwDDAQAfAAMJTAV7/QBgAAAAAA==.',
Dx='Dxmvn:BAAALgADCgEJAQAAAA==.',
Dy='Dyingmight:BAAALgAECgQJBAAAAA==.',
['Dä']='Dävïs:BAAALgAECggJEwABLgAECgkJIgAhAAYTAA==.',
Ed='Edea:BAABLgAECn8UAAIfAAcJlgV4ngDqAAAfAAcJlgV4ngDqAAAAAA==.Edisonn:BAACLgAFFH8OAAIfAAYJXgvSJwBiAQAfAAYJXgvSJwBiAQAuAAQKfykAAx8ACAm1IF4eAFUCAB8ACAm1IF4eAFUCAAQAAwmYHD07AMcAAAAA.',
El='Eldarya:BAAALgAECgYJCwAAAA==.Eldermoon:BAAALgAECgYJCAAAAA==.Elghinn:BAABLgAECn89AAIdAAkJ0hRmDwD7AQAdAAkJ0hRmDwD7AQAAAA==.Ellie:BAABLgAECn85AAIJAAgJqR+KIQA1AgAJAAgJqR+KIQA1AgAAAA==.Elponch:BAAALgAECgcJBwAAAA==.Elroy:BAABLgAECn84AAIPAAkJXBTqNgAFAgAPAAkJXBTqNgAFAgAAAA==.',
Em='Embold:BAACLgAFFH8WAAISAAYJZyISAgBRAgASAAYJZyISAgBRAgAuAAQKfy0AAhIACQnqJWcAAOcDABIACQnqJWcAAOcDAAEuAAUUCAkaABUASSAA.Emernantus:BAABLgAECn8tAAILAAgJQg8KGQAmAQALAAgJQg8KGQAmAQAAAA==.Emozi:BAABLgAECn8sAAMfAAkJ1xGIPADQAQAfAAkJExGIPADQAQAgAAYJoBHQCwB9AQAAAA==.',
Eu='Eunbyeol:BAABLgAECn8pAAIWAAkJrhxyFgAXAgAWAAkJrhxyFgAXAgAAAA==.',
Ex='Excidium:BAAALgAECgYJDQAAAA==.Expired:BAAALgAECgUJBQAAAA==.',
Fa='Faeria:BAABLgAECn8rAAIUAAgJQh7CCQCoAgAUAAgJQh7CCQCoAgAAAA==.Fangwalker:BAAALgAECgQJEAAAAA==.Farmerdotcom:BAAALgADCgEJAQAAAA==.Fatnchunkydk:BAABLgAECn8lAAIiAAgJGw6CHgAwAQAiAAgJGw6CHgAwAQAAAA==.Fatpigeon:BAABLgAECn8WAAIPAAYJnAzvpgALAQAPAAYJnAzvpgALAQAAAA==.',
Fe='Feeblemind:BAABLgAECn8qAAIJAAgJBxkTOgDLAQAJAAgJBxkTOgDLAQAAAA==.Feesherman:BAACLgAFFH8NAAIPAAUJYiS4EACVAQAPAAUJYiS4EACVAQAuAAQKfxgAAg8ABwnDJcESAP0CAA8ABwnDJcESAP0CAAAA.Feli:BAABLgAECn8cAAIWAAkJbgyNJACsAQAWAAkJbgyNJACsAQAAAA==.Felldor:BAAALgADCgUJAgAAAA==.Felmommy:BAAALgADCgYJBgAAAA==.Felrindan:BAAALgAECgYJDAAAAA==.Felscream:BAAALgADCgUJBQAAAA==.Fender:BAABLgAECn8nAAIkAAgJixgeCQADAgAkAAgJixgeCQADAgAAAA==.Ferchrian:BAAALgADCgEJAQAAAA==.',
Fi='Finfangfoom:BAAALgAECgQJBwABLgAECgcJCAAMAAAAAA==.Fingertoes:BAABLgAECn8vAAMNAAgJcx0mNwAfAgANAAgJcx0mNwAfAgAjAAEJNxDSEQA1AAAAAA==.Fishermonk:BAAALgADCgMJAwABLgABCgEJAQAMAAAAAA==.Fizban:BAAALgADCggJFAAAAA==.',
Fl='Flaygar:BAAALgAECgYJDAAAAA==.Flory:BAABLgAECn8qAAIPAAkJLhvGKAA9AgAPAAkJLhvGKAA9AgAAAA==.Flowpro:BAAALgADCgMJAwAAAA==.Flyinweasle:BAAALgAECgUJBQAAAA==.',
Fo='Foundation:BAAALgAECgYJCgAAAA==.Foxxycontin:BAABLgAECn8gAAQUAAcJDxDpMAB9AQAUAAcJDxDpMAB9AQAHAAQJYAceSQCeAAAVAAEJFQZ8ZgAsAAAAAA==.',
Fr='Freemay:BAAALgAECgUJBQAAAA==.Frostyrican:BAAALgAECgEJAQAAAA==.',
Fu='Fuglybaby:BAAALgAECgEJAQAAAA==.Furyofheaven:BAAALgADCgEJAQAAAA==.',
Fw='Fwakos:BAAALgADCgUJCQAAAA==.',
['Fé']='Fénnie:BAAALgADCgMJAwAAAA==.',
Ga='Gaivahros:BAABLgAECn8XAAIPAAgJDQXGsQD6AAAPAAgJDQXGsQD6AAAAAA==.Gakpaladin:BAABLgAECn89AAILAAkJ9Rw7BQB3AgALAAkJ9Rw7BQB3AgAAAA==.Galileo:BAABLgAECn8kAAIOAAgJPhVgJgD5AQAOAAgJPhVgJgD5AQAAAA==.Garland:BAAALgAECgcJDQAAAA==.',
Gd='Gdlez:BAAALgAECgEJAgAAAA==.',
Ge='Gerasstrois:BAABLgAECn8UAAINAAcJ3QhHuQD3AAANAAcJ3QhHuQD3AAABLgAECggJMAAgALcUAA==.Gerionier:BAAALgADCgEJAQABLgAECgYJFQAUAIAcAA==.Gethael:BAAALgAFFAEJAQAAAA==.',
Gh='Ghalathor:BAAALgAECgQJBAAAAA==.',
Gl='Glimsy:BAAALgADCgYJCQAAAA==.Glittermilk:BAAALgADCgUJBQAAAA==.Glizzyglock:BAAALgADCgcJCwABLgAECggJLwANAHMdAA==.',
Go='Golosan:BAABLgAECn8iAAIRAAkJKR3MCwBZAgARAAkJKR3MCwBZAgAAAA==.Goododie:BAABLgAECn8jAAIPAAgJQh0tMAAeAgAPAAgJQh0tMAAeAgAAAA==.Gordil:BAAALgAECgUJBQAAAA==.Gorokan:BAAALgAECgIJAwAAAA==.',
Gr='Grayback:BAAALgAECgcJBgABLgAECggJJgAfAEgZAA==.Grimsdeath:BAAALgADCgUJBQAAAA==.',
Gu='Guila:BAABLgAECn8eAAIfAAgJigzRZQBbAQAfAAgJigzRZQBbAQAAAA==.Gulaken:BAABLgAECn8VAAIJAAYJoRBRcAAxAQAJAAYJoRBRcAAxAQAAAA==.',
Ha='Hafnia:BAABLgAECn8YAAMUAAcJ/BiKGQDXAQAUAAcJ/BiKGQDXAQAHAAIJOAegVwBVAAAAAA==.Hahkon:BAAALgADCgEJAQAAAA==.Hai:BAAALgAECgEJAQAAAA==.Halphion:BAAALgADCgYJBwABLgAECgkJIgAQACIdAA==.Hangry:BAAALgAECgEJAQAAAA==.Hanoe:BAAALgADCgYJBgAAAA==.Haoasakura:BAABLgAECn9BAAIPAAkJkSM6CAAQAwAPAAkJkSM6CAAQAwAAAA==.Hawkeyegold:BAAALgAECgIJAgAAAA==.Haybuse:BAABLgAECn8nAAITAAkJkCABCgBmAgATAAkJkCABCgBmAgAAAA==.',
He='Healmd:BAAALgADCgMJAwAAAA==.Healsforhugs:BAAALgADCgMJAwAAAA==.Healzforfood:BAAALgAECggJDwAAAA==.Healzyou:BAAALgADCgMJAwAAAA==.Heap:BAABLgAECn8sAAIbAAkJIRT5CwDnAQAbAAkJIRT5CwDnAQAAAA==.Hectavius:BAAALgAECgIJAwAAAA==.Hells:BAAALgAECgEJAQAAAA==.Hellslinger:BAAALgAECgQJBwAAAA==.Hewnoshaqa:BAABLgAECn8cAAIJAAgJ9AygXgBcAQAJAAgJ9AygXgBcAQAAAA==.Hexeñ:BAABLgAECn8XAAIDAAgJBBNuMwC1AQADAAgJBBNuMwC1AQAAAA==.Hexorcist:BAACLgAFFH8UAAIDAAUJuBkXFwBmAQADAAUJuBkXFwBmAQAuAAQKfxcAAwMACAnPGYQbADwCAAMACAnPGYQbADwCAAgAAwnVGcNaANkAAAAA.',
Hi='Hibuse:BAAALgAECgMJAwABLgAECgkJJwATAJAgAA==.Hickerbilly:BAAALgAECgkJEAAAAA==.Higgintoot:BAAALgAECgIJAgABLgAECggJGwATAD4PAA==.Hitormist:BAABLgAECn8eAAIGAAcJHxhDIADUAQAGAAcJHxhDIADUAQAAAA==.',
Ho='Holyshoot:BAAALgAECgMJBQAAAA==.Holyspanks:BAAALgADCgEJAQABLgAECgkJKgABADIdAA==.Horous:BAAALgAECgcJAwAAAA==.Hotdoog:BAAALgADCgcJDQABLgAECgQJCgAMAAAAAA==.',
Hr='Hruuli:BAAALgAECgIJAgAAAA==.',
Hu='Hungweilow:BAAALgADCgUJBgABLgAECgcJCAAMAAAAAA==.Hutsa:BAAALgAECgQJBAABLgAECggJMAAPAH0YAA==.Huugar:BAABLgAECn8mAAIIAAcJkhDVNwAoAQAIAAcJkhDVNwAoAQAAAA==.Huulhai:BAAALgAECgYJEgAAAA==.',
['Hæ']='Hædés:BAABLgAECn8hAAILAAgJthskCwDpAQALAAgJthskCwDpAQAAAA==.',
['Hè']='Hèxén:BAAALgAECgYJBgABLgAECggJFwADAAQTAA==.',
Ib='Ibeamwork:BAAALgAECgcJEAABLgAFFAIJAgAMAAAAAA==.',
Ic='Icoulddowork:BAAALgAFFAIJAgAAAA==.Icyconjurer:BAAALgADCgMJAwAAAA==.',
Id='Idoworkz:BAAALgADCgcJBwABLgAFFAIJAgAMAAAAAA==.',
Ii='Iiquorice:BAAALgAECgMJAwAAAA==.',
Ik='Ikazuchi:BAABLgAECn81AAIFAAkJ3RhjBABJAgAFAAkJ3RhjBABJAgAAAA==.',
Il='Illcutabish:BAABLgAECn80AAIlAAkJCxx0BgCkAgAlAAkJCxx0BgCkAgAAAA==.',
Im='Imk:BAABLgAECn8sAAMcAAgJFhIrSQCIAQAcAAgJFhIrSQCIAQAeAAMJNAKXJABQAAAAAA==.',
In='Ineedatarget:BAAALgADCgEJAQAAAA==.Intbuff:BAAALgAECgMJAwABLgAECgYJGwAOAMwSAA==.Invadiah:BAAALgAECgcJDQAAAA==.Invited:BAAALgAFFAEJAQAAAA==.',
Io='Iock:BAEALgAECgUJCAAAAA==.',
Ir='Ironarms:BAAALgADCgUJBQAAAA==.',
Iw='Iwdominate:BAAALgAECgYJCwAAAA==.',
Iy='Iyana:BAAALgAECgMJBgAAAA==.',
Iz='Izümi:BAABLgAECn8hAAITAAgJbxpzEwDxAQATAAgJbxpzEwDxAQAAAA==.',
Ja='Jazz:BAAALgADCgcJDgAAAA==.',
Je='Jennypoo:BAABLgAECn9BAAMOAAkJLh5SCQAGAwAOAAkJLh5SCQAGAwAKAAIJQwrKawBHAAAAAA==.Jessd:BAAALgAECgIJBAAAAA==.',
Jh='Jhonywalker:BAAALgAECgUJBQAAAA==.',
Ji='Jild:BAAALgAECgQJBwAAAA==.Jinwoosung:BAAALgAECgYJDQAAAA==.',
Jo='Johnwarrior:BAABLgAECn8nAAIWAAgJnx2xEABQAgAWAAgJnx2xEABQAgAAAA==.Jorrix:BAABLgAECn8sAAIPAAkJHBZQMAAeAgAPAAkJHBZQMAAeAgAAAA==.',
Ju='Juduspriestt:BAABLgAECn8wAAIPAAgJfRhwPgDsAQAPAAgJfRhwPgDsAQAAAA==.Jurt:BAAALgADCgcJDQAAAA==.',
Ka='Kaalysto:BAAALgADCgMJAwAAAA==.Kadao:BAAALgAECgUJCAAAAA==.Kaekko:BAAALgADCgYJBgABLgAECgkJKgAPAKcgAA==.Kaeko:BAABLgAECn8eAAIVAAgJFxxvEACAAgAVAAgJFxxvEACAAgABLgAECgkJKgAPAKcgAA==.Kaelathaniel:BAACLgAFFH8JAAIfAAMJQwWGbAC7AAAfAAMJQwWGbAC7AAAuAAQKfzIAAx8ACAlnEcdPAJUBAB8ACAllEcdPAJUBAAQAAQl4Ds51AC8AAAAA.Kalerito:BAABLgAECn80AAIOAAkJTiJiAwB3AwAOAAkJTiJiAwB3AwAAAA==.Kalistae:BAABLgAECn8nAAMVAAkJoCCsBQDdAgAVAAkJoCCsBQDdAgAUAAEJ6h/GcwBZAAAAAA==.Kallivath:BAAALgAECgUJBQAAAA==.Kamdrixa:BAAALgADCgYJDAAAAA==.Kardie:BAAALgAECgcJDAAAAA==.Karinus:BAAALgADCgUJBQAAAA==.Karkaroff:BAAALgAECgcJAwABLgAECggJJgAfAEgZAA==.Karl:BAABLgAECn8mAAINAAgJdgrKfgBdAQANAAgJdgrKfgBdAQAAAA==.Karlack:BAAALgADCgUJBQAAAA==.Kaserr:BAACLgAFFH8TAAIlAAYJKh7OBwCuAQAlAAYJKh7OBwCuAQAuAAQKfzAAAiUACQmCIOUCAHYDACUACQmCIOUCAHYDAAAA.Kayserdh:BAABLgAECn8VAAMdAAYJBBvhIwCeAQAdAAYJlBjhIwCeAQAcAAUJXBauegAEAQAAAA==.Kazaf:BAABLgAECn8YAAIiAAUJOhonJwDsAAAiAAUJOhonJwDsAAAAAA==.',
Ke='Keeirian:BAAALgADCgEJAQAAAA==.Kegar:BAAALgADCgEJAQABLgAECggJLwANAHMdAA==.Keikoh:BAABLgAECn8qAAIPAAkJpyDdCwDrAgAPAAkJpyDdCwDrAgAAAA==.Keitrek:BAABLgAECn80AAIQAAkJlgsBJQC4AQAQAAkJlgsBJQC4AQAAAA==.Kelleta:BAAALgAECgYJCgAAAA==.Kelthias:BAAALgADCgYJCgAAAA==.Kelypsoc:BAAALgAECgQJBgAAAA==.Kenichï:BAAALgAECgYJDwABLgAECggJFwADAAQTAA==.Keomag:BAAALgAECgQJBwAAAA==.Kerwîck:BAABLgAECn8oAAIQAAkJhx50BQAcAwAQAAkJhx50BQAcAwAAAA==.Keyen:BAABLgAECn8xAAIQAAgJ2wduPAAtAQAQAAgJ2wduPAAtAQAAAA==.',
Kh='Khallan:BAABLgAECn8lAAIOAAkJDQbjUQAlAQAOAAkJDQbjUQAlAQAAAA==.',
Ki='Kibalion:BAABLgAECn8XAAIUAAkJgRNrIACcAQAUAAkJgRNrIACcAQAAAA==.Kiljaezyn:BAAALgAECgEJAgAAAA==.Killbent:BAABLgAECn8YAAIkAAcJ8weLHADqAAAkAAcJ8weLHADqAAAAAA==.Kilowatts:BAAALgADCgYJBgAAAA==.Kimjongheäl:BAAALgAECgkJEgAAAA==.Kimjongwork:BAAALgAECgEJAQABLgAFFAIJAgAMAAAAAA==.Kinnky:BAABLgAECn8kAAINAAkJFBTWPwABAgANAAkJFBTWPwABAgAAAA==.Kino:BAAALgAECgUJCQAAAA==.Kiratsuna:BAAALgAECgYJBwAAAA==.Kiriya:BAABLgAECn8eAAIOAAcJPgcaaADbAAAOAAcJPgcaaADbAAAAAA==.Kismiasu:BAAALgAECgYJCAAAAA==.Kitticakes:BAAALgADCgUJBQAAAA==.Kivdruid:BAACLgAFFH8OAAIOAAUJ9hamEgCQAQAOAAUJ9hamEgCQAQAuAAQKfywAAw4ACQlVH6kHACIDAA4ACQlVH6kHACIDAAoABAn3GDdAANsAAAAA.Kivpriest:BAABLgAFFH8FAAMUAAMJtgcZIwBzAAAUAAIJyQoZIwBzAAAHAAEJkAGCOwA+AAABLgAFFAUJDgAOAPYWAA==.',
Kk='Kkty:BAAALgADCgQJBwAAAA==.',
Ko='Koore:BAABLgAECn8mAAILAAkJmx0bBACcAgALAAkJmx0bBACcAgAAAA==.Korraavatar:BAAALgAECgIJAgAAAA==.',
Kp='Kpop:BAABLgAECn8eAAIcAAkJXiPlBAAnAwAcAAkJXiPlBAAnAwAAAA==.Kpopkhan:BAABLgAECn8PAAIcAAgJSQz7awBfAQAcAAgJSQz7awBfAQAAAA==.',
Kr='Kreettip:BAABLgAECn80AAIUAAkJyxKBHAC8AQAUAAkJyxKBHAC8AQAAAA==.Krispy:BAAALgADCggJEAABLgAECggJKQAOAGYZAA==.',
Ku='Kugamoo:BAABLgAECn8hAAIKAAkJqRV7IQCQAQAKAAkJqRV7IQCQAQAAAA==.Kulgen:BAAALgADCgIJAgAAAA==.Kurgen:BAABLgAECn8lAAIPAAgJwxN/VgCpAQAPAAgJwxN/VgCpAQAAAA==.',
Ky='Kylex:BAAALgAECgEJAgAAAA==.Kyuyoung:BAAALgAECgEJAQABLgAECgkJKQAWAK4cAA==.',
['Kà']='Kàkárót:BAAALgAECgQJBAAAAA==.',
['Kí']='Kísámé:BAAALgAECgEJAQABLgAECggJIQATAG8aAA==.',
La='Lamasacre:BAAALgAECgEJAQAAAA==.Lamiah:BAAALgAECgIJAwABLgAECgQJBAAMAAAAAA==.Lannybarby:BAABLgAECn8mAAIPAAYJfw/SogARAQAPAAYJfw/SogARAQAAAA==.Laotzu:BAABLgAECn8ZAAMBAAgJ0wi+LgBNAQABAAcJNQm+LgBNAQACAAgJ7AN7JwA4AQABLgAFFAMJAwAMAAAAAA==.',
Lc='Lckdown:BAABLgAECn8dAAMfAAgJiyAHFACXAgAfAAgJiyAHFACXAgAEAAEJAADhSQAAAAAAAA==.',
Le='Legomyegolas:BAABLgAECn8mAAQJAAgJjyLMFACDAgAJAAgJjyLMFACDAgASAAMJNxpuWgDaAAATAAEJAABRKgBdAAAAAA==.Lelaeh:BAAALgAECggJCAAAAA==.Leviticus:BAAALgADCgEJAQAAAA==.',
Li='Liara:BAAALgADCgEJAQAAAA==.Licentious:BAAALgADCgIJAgAAAA==.Lightsauce:BAAALgAECgkJDAAAAA==.Lilianis:BAAALgAECgIJAgAAAA==.Lilybloom:BAAALgAECgQJBAAAAA==.',
Lo='Loden:BAACLgAFFH8cAAMhAAUJTSCMEQBbAQAhAAUJTSCMEQBbAQAFAAMJlAuwDQDWAAAuAAQKfx8AAyEACQk2IxAZAOYCACEACQk2IxAZAOYCAAUAAQkAAAozAAAAAAAA.Lodex:BAAALgAECgEJAQAAAA==.Lokthal:BAAALgADCgYJBgAAAA==.Lootzu:BAAALgAECgkJAQAAAA==.Lovi:BAABLgAECn8uAAIDAAgJRRwpIgAUAgADAAgJRRwpIgAUAgAAAA==.',
Lu='Luckyboi:BAAALgAECgYJEwAAAA==.Luckymonk:BAABLgAECn8tAAQRAAkJfxBxHACjAQARAAkJfxBxHACjAQAGAAQJMQP7cQBdAAAYAAIJQglDbABQAAABLgAECgYJEwAMAAAAAA==.Lucyl:BAAALgAECgMJAwAAAA==.Lumina:BAABLgAECn8XAAIPAAgJAQnjiAA9AQAPAAgJAQnjiAA9AQAAAA==.Lunaruu:BAAALgADCgEJAQAAAA==.Lusciifi:BAACLgAFFH8bAAIPAAcJDSUPAgCDAgAPAAcJDSUPAgCDAgAuAAQKfywAAw8ACAkkJh0GAGwDAA8ACAn2JR0GAGwDAAsAAQnkJQ0zAGgAAAAA.Luvva:BAAALgAECgIJAgAAAA==.',
Ly='Lykie:BAABLgAECn8sAAILAAkJfR9rBQByAgALAAkJfR9rBQByAgAAAA==.Lykiechi:BAAALgAECgYJBgABLgAECgkJLAALAH0fAA==.Lyllith:BAAALgADCgYJBgAAAA==.Lyone:BAABLgAECn8gAAIaAAgJgiEnBgCKAgAaAAgJgiEnBgCKAgAAAA==.Lyrykal:BAAALgADCgEJAQAAAA==.',
['Lú']='Lúvaa:BAACLgAFFH8JAAIhAAMJ2x/yVQAiAQAhAAMJ2x/yVQAiAQAuAAQKfywAAyEACQloILkUAKsCACEACQloILkUAKsCACIABQkLH6kkABsBAAAA.',
Ma='Maahun:BAAALgAECgEJBAAAAA==.Macavity:BAAALgAECgEJAQAAAA==.Maficwar:BAACLgAFFH8FAAIaAAMJAhj2EwDcAAAaAAMJAhj2EwDcAAAuAAQKfzYAAhoACQnKHe4FAJACABoACQnKHe4FAJACAAAA.Magalis:BAAALgADCgQJBAAAAA==.Mageyuwu:BAAALgAECgEJAQAAAA==.Magikkisback:BAAALgAECgcJEAAAAA==.Manarez:BAAALgAECgYJCgAAAA==.Mandorius:BAABLgAECn8XAAIJAAgJJx3jKwAEAgAJAAgJJx3jKwAEAgAAAA==.Manywagons:BAAALgAECgcJDQABLgAFFAkJPAANABcmAA==.Margherita:BAAALgAECgUJBQAAAA==.Mariora:BAAALgAECgEJAQAAAA==.Marvolo:BAAALgAECgkJBQABLgAECggJJgAfAEgZAA==.Masacre:BAAALgAECgQJCAAAAA==.Mavalynal:BAAALgADCgcJEgAAAA==.Mavdeath:BAABLgAECn8aAAMhAAkJNiHZDwDPAgAhAAkJNiHZDwDPAgAFAAUJpBylEQAWAQAAAA==.Maverogue:BAAALgAECgkJCQAAAA==.Mavidari:BAABLgAECn8ZAAIcAAgJDB4iIQCKAgAcAAgJDB4iIQCKAgAAAA==.',
Mc='Mchammered:BAAALgADCgMJBgAAAA==.',
Me='Meeshie:BAACLgAFFH8KAAIUAAQJaBPqDwAfAQAUAAQJaBPqDwAfAQAuAAQKfzYABBQACQnYGjwQAGQCABQACQnYGjwQAGQCAAcABwnkFYwlAHQBABUABwnjCwAyACoBAAAA.Meleys:BAAALgADCgcJCAAAAA==.Methylphine:BAAALgAECggJCgAAAA==.',
Mi='Midoriya:BAACLgAFFH8ZAAQfAAUJ0CbxEADEAQAfAAQJ0CbxEADEAQAgAAIJSSYPCwByAAAEAAEJNhdjEwBYAAAuAAQKfycABB8ACQlAJuYIAPkCAB8ABwkUJuYIAPkCAAQAAwn5JZchAEgBACAAAgmBJh8gAHIAAAAA.Mightyhunts:BAAALgAECgQJBQAAAA==.Mikearuba:BAAALgAECgQJBAAAAA==.Mikuzume:BAAALgAECgYJEQAAAA==.Milkmage:BAABLgAECn8rAAINAAkJzB4tGwCdAgANAAkJzB4tGwCdAgAAAA==.Mintt:BAAALgAECgEJAQAAAA==.Mistonyaface:BAAALgAECgQJBAABLgAECggJLwANAHMTAA==.Mistypaksz:BAABLgAECn8dAAMGAAgJMRrtEgBOAgAGAAgJMRrtEgBOAgAYAAMJ8w5TUQCWAAAAAA==.Miznewbooty:BAABLgAECn8rAAMHAAkJpQ+cFwDqAQAHAAkJpQ+cFwDqAQAVAAQJog5ZRADaAAAAAA==.',
Mo='Moggark:BAAALgADCggJEgAAAA==.Monknack:BAAALgAFFAEJAQAAAA==.Moondofrond:BAAALgAECgUJCQAAAA==.Moonq:BAABLgAECn8rAAIOAAgJvAYXXAACAQAOAAgJvAYXXAACAQAAAA==.Moosaurus:BAABLgAECn8vAAIeAAkJ4xTVBwDVAQAeAAkJ4xTVBwDVAQAAAA==.Morenack:BAAALgADCgEJAQAAAA==.Mosrael:BAAALgADCgEJAgAAAA==.',
Mu='Muerte:BAAALgAECgIJAgABLgAECggJIAAbABkWAA==.Muffy:BAABLgAECn8eAAICAAgJOxLbDgC8AQACAAgJOxLbDgC8AQAAAA==.Muggyx:BAAALgADCgUJBQAAAA==.Multishoted:BAAALgADCgEJAQAAAA==.Murlouh:BAAALgADCgUJCAAAAA==.Mushudoobey:BAAALgAECgIJAgABLgAFFAMJBgANAGMVAA==.',
My='Mylthrad:BAAALgADCgMJAwAAAA==.Mythnarra:BAACLgAFFH8XAAMeAAUJSSaeAADJAQAeAAUJSSaeAADJAQAcAAEJUgc1fQBEAAAuAAQKfzMAAx4ACQn2JVMAAFwDAB4ACQn2JVMAAFwDABwABgk/HL9FAJMBAAAA.',
['Mí']='Mísanthrope:BAAALgAECgYJEgAAAA==.',
['Mô']='Mônster:BAAALgAECgUJCQAAAA==.',
['Mö']='Mönk:BAACLgAFFH8FAAIGAAMJthfmCgD7AAAGAAMJthfmCgD7AAAuAAQKfx8AAgYACAmsHs0MAIYCAAYACAmsHs0MAIYCAAAA.',
['Mø']='Mønstèr:BAAALgAECgcJDAAAAA==.',
Na='Nachtimbess:BAAALgADCgYJBgABLgAECgkJNgANAB8cAA==.Nadaline:BAAALgADCgcJBwAAAA==.Nadíne:BAACLgAFFH8OAAINAAQJOhHWTgArAQANAAQJOhHWTgArAQAuAAQKfxwAAg0ACQkSHkRDAG4CAA0ACQkSHkRDAG4CAAAA.Naha:BAAALgAECgkJBwAAAA==.Naimi:BAABLgAECn8ZAAMOAAYJcxWRQQBoAQAOAAYJcxWRQQBoAQAKAAQJ9AqTTQClAAAAAA==.Nanukimon:BAABLgAECn8iAAMXAAgJoRVMDAC3AQAXAAgJoRVMDAC3AQADAAYJQwsKZAD3AAAAAA==.Nastymcdirty:BAAALgADCgcJBwAAAA==.',
Ne='Nedgamingttv:BAEALgAECgkJCQAAAA==.Nelivath:BAAALgAECgEJAQAAAA==.Nene:BAABLgAFFH8HAAINAAIJkhHsgACeAAANAAIJkhHsgACeAAAAAA==.Nevaera:BAABLgAECn8XAAINAAcJBw6BiABKAQANAAcJBw6BiABKAQAAAA==.',
Ni='Nichan:BAAALgAECgEJAwAAAA==.Nick:BAACLgAFFH8vAAMhAAgJxR6KAQDSAgAhAAgJxR6KAQDSAgAiAAEJAAB6OwAAAAAuAAQKfzQAAiEACQlVJP4EAIQDACEACQlVJP4EAIQDAAAA.Nightcraft:BAAALgAECgEJAQAAAA==.Nightshine:BAAALgAECgcJEQAAAA==.Nikor:BAABLgAECn8fAAILAAgJBh6gBgBPAgALAAgJBh6gBgBPAgAAAA==.Nisan:BAAALgADCgcJBwAAAA==.',
No='Noah:BAAALgAECgIJAgAAAA==.Nocabevoli:BAAALgADCgUJBQABLgAECgIJAwAMAAAAAA==.Nokorii:BAABLgAECn8jAAIUAAgJbxH3HgCoAQAUAAgJbxH3HgCoAQAAAA==.Nomecoma:BAAALgAECgQJAQAAAA==.Nomercy:BAAALgAECgEJAgAAAA==.Norgatha:BAAALgAECgUJCwAAAA==.Notches:BAAALgAECgQJBwAAAA==.Nowheres:BAAALgAECgIJAwABLgAECgUJEgAMAAAAAA==.Noxturn:BAABLgAECn8VAAIJAAgJtBFGUQB1AQAJAAgJtBFGUQB1AQAAAA==.',
Nu='Nuikang:BAAALgAECgEJAQAAAA==.',
Ny='Nyxx:BAABLgAECn8XAAMmAAgJkhyxBAAbAgAmAAgJkhyxBAAbAgAnAAEJXAVIDwAsAAABLgAECgUJCQAMAAAAAA==.',
['Nè']='Nèlo:BAABLgAECn8lAAIaAAkJGw7YEgCVAQAaAAkJGw7YEgCVAQAAAA==.',
Oc='Oceansoul:BAABLgAECn8oAAMgAAgJySHKAwA6AgAgAAgJoyHKAwA6AgAfAAUJ3BqVVQCFAQAAAA==.',
Oh='Ohh:BAAALgADCgMJAQAAAA==.Ohthathurtu:BAAALgADCgEJAQAAAA==.',
Ok='Ok:BAAALgADCgYJCgAAAA==.',
On='Ondestra:BAAALgAECgIJAgAAAA==.Onlytoez:BAAALgADCggJCAABLgAFFAQJCgAUAGgTAA==.',
Op='Ophanym:BAAALgADCgEJAQAAAA==.Oppenheimerx:BAAALgADCgMJBQAAAA==.',
Or='Orave:BAABLgAECn8ZAAIUAAgJXR5oCgCbAgAUAAgJXR5oCgCbAgAAAA==.Origin:BAAALgAECgIJAwABLgAECgcJHwAGAPQeAA==.Orionah:BAAALgAECggJDgAAAA==.',
Os='Ostena:BAAALgAECgcJBwAAAA==.Osymonka:BAAALgADCgYJBgABLgAECgkJNgANAB8cAA==.Osywar:BAAALgAECgYJEwABLgAECgkJNgANAB8cAA==.',
Ou='Oulawdpriest:BAACLgAFFH8UAAIVAAYJYQz6CgB2AQAVAAYJYQz6CgB2AQAuAAQKfzwABBUACAkeIEsMAL4CABUACAkeIEsMAL4CAAcABgliHOIXAOcBABQAAwnRFY9RAGcAAAAA.',
Ov='Overture:BAABLgAECn8dAAMOAAYJBxGqVAAcAQAOAAYJBxGqVAAcAQAKAAUJjxPtSgCvAAAAAA==.',
Pa='Pakszdude:BAABLgAECn8ZAAMbAAYJMiK5BwA6AgAbAAYJMiK5BwA6AgAkAAMJ/RSrJACuAAAAAA==.Palaslap:BAAALgADCgMJAwAAAA==.Pallyrican:BAAALgAECgEJAQAAAA==.Panacea:BAAALgAECgYJCQABLgAECgcJBwAMAAAAAA==.Parkour:BAABLgAECn8YAAIcAAcJ2RnmWABZAQAcAAcJ2RnmWABZAQAAAA==.Pastorale:BAAALgADCgYJBgABLgAFFAMJAwAMAAAAAA==.Patata:BAAALgADCgMJBQAAAA==.Paully:BAAALgAFFAEJAQAAAA==.Paullyfists:BAAALgAECgYJCAAAAA==.Paullymorph:BAABLgAECn8hAAINAAkJDiE0IQB+AgANAAkJDiE0IQB+AgAAAA==.Pawpawbear:BAAALgADCgEJAQAAAA==.Payal:BAAALgADCgQJBAABLgAFFAYJDgAfAF4LAA==.',
Pe='Pewpewkitti:BAAALgADCgUJBQAAAA==.',
Ph='Phenyl:BAACLgAFFH8GAAIGAAMJ7xFoJQDJAAAGAAMJ7xFoJQDJAAAuAAQKfyIAAgYACQnbD/gfANYBAAYACQnbD/gfANYBAAAA.Pheurton:BAAALgAECgkJBwAAAA==.',
Pi='Pintobeans:BAAALgAECgcJBwAAAA==.Pithers:BAAALgAECgQJBgAAAA==.',
Pl='Plasmor:BAAALgAECggJDAAAAA==.',
Po='Ponchohunter:BAAALgADCgEJAQAAAA==.Pooh:BAAALgADCgEJAQABLgAECgcJHgAGAB8YAA==.Poohpocket:BAAALgADCgQJAwAAAA==.Pooshock:BAAALgAECgYJBgAAAA==.Popkorn:BAACLgAFFH8sAAMcAAgJOSWuAAAKAwAcAAcJOSWuAAAKAwAeAAEJAAAQBABqAAAuAAQKfx8ABBwACAmSJrYQAPgCABwACAlZJLYQAPgCAB0ABQmUIb4qAHABAB4AAQlnJW4iAG8AAAAA.Popkornvoke:BAAALgAFFAIJAgABLgAFFAgJLAAcADklAA==.Poplocks:BAAALgADCgIJAwABLgAECgYJCgAMAAAAAA==.Porrana:BAABLgAECn8qAAMWAAgJ3yHvDAB5AgAWAAgJjSHvDAB5AgAoAAEJIx0BUwBOAAAAAA==.Powaqa:BAABLgAECn8/AAIEAAkJOgSAFADdAAAEAAkJOgSAFADdAAAAAA==.',
Ps='Psy:BAAALgAECggJEwAAAA==.',
Pu='Pumpkinspice:BAAALgAECgUJBQAAAA==.Punchkin:BAABLgAECn8bAAMGAAkJERcYGQAQAgAGAAkJERcYGQAQAgAYAAEJWwJViQAmAAAAAA==.Purify:BAAALgAECgQJBQABLgAFFAUJFAAGAColAA==.Puzzledmonk:BAAALgADCgcJDQAAAA==.',
['Pé']='Pérsés:BAAALgAECgMJAwABLgAECgYJEQAMAAAAAA==.',
Qu='Quasient:BAAALgAECggJDAAAAA==.Quickspell:BAABLgAECn8iAAINAAkJvx5CKABdAgANAAkJvx5CKABdAgAAAA==.Quickstep:BAAALgAECgkJBwAAAA==.',
Ra='Rabidpopcorn:BAAALgADCgcJBwAAAA==.Radaghast:BAABLgAECn8gAAIbAAgJGRY0DwC1AQAbAAgJGRY0DwC1AQAAAA==.Raedyyn:BAABLgAECn8kAAIBAAkJig9zIQCrAQABAAkJig9zIQCrAQAAAA==.Ragarth:BAAALgAECgYJDgAAAA==.Ragendecay:BAABLgAECn8lAAIhAAkJRRZsLAArAgAhAAkJRRZsLAArAgAAAA==.Ragequits:BAACLgAFFH8YAAMWAAgJ7h03AABcAgAWAAYJRCM3AABcAgAoAAMJpBMpHQCyAAAuAAQKfzEAAxYACQnEJpgAAN4DABYACQmtJpgAAN4DACgACQkvIsQBACADAAAA.Ragæ:BAAALgAFFAIJAgAAAA==.Rakshassa:BAABLgAECn8eAAIJAAkJ5BmnEwCLAgAJAAkJ5BmnEwCLAgAAAA==.Ralcar:BAABLgAECn8aAAIcAAYJ1yCEOADDAQAcAAYJ1yCEOADDAQAAAA==.Ratsnart:BAAALgAECgQJBQABLgAFFAMJBAAMAAAAAA==.Razrscale:BAAALgAECgcJCgAAAA==.',
Re='Redhuntsman:BAAALgAECgMJBQAAAA==.Regrow:BAABLgAECn8bAAMOAAYJzBJwRQBXAQAOAAYJzBJwRQBXAQAbAAUJrQg1OQB2AAAAAA==.Renn:BAAALgAECgUJBQABLgAECgUJCQAMAAAAAA==.Renstrider:BAAALgAECgUJBwAAAA==.Retorcido:BAAALgADCgUJBQAAAA==.',
Rh='Rheas:BAAALgAECgIJAQAAAA==.Rhianniean:BAAALgADCgMJAwAAAA==.Rholdentodor:BAAALgADCgUJBQABLgAECgcJCwAMAAAAAA==.',
Ri='Riverkitty:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.',
Ro='Rockabye:BAAALgAECgYJBgABLgAFFAQJEQAhACgWAA==.Rockstar:BAAALgAECgUJBQAAAA==.Rohra:BAABLgAECn8tAAIOAAgJqA5rQQBoAQAOAAgJqA5rQQBoAQAAAA==.Rombaz:BAAALgAFFAIJBAAAAA==.Ronspoomage:BAAALgADCgkJEQAAAA==.Rosemary:BAAALgADCgQJBAAAAA==.Roybi:BAAALgADCgkJCgAAAA==.Roóz:BAAALgAECgQJEQAAAA==.',
Ru='Ruah:BAAALgAECgEJAQAAAA==.Ruenarn:BAAALgAECgEJAQAAAA==.Runecast:BAAALgADCgcJFQAAAA==.',
Ry='Rynk:BAABLgAECn87AAIRAAkJgSZnAAB7AwARAAkJgSZnAAB7AwAAAA==.Rynkidari:BAAALgAECgkJCQABLgAECgkJOwARAIEmAA==.Ryuoxel:BAAALgAFFAIJAwAAAA==.',
['Rá']='Rágnarok:BAAALgADCgMJAwAAAA==.Ráwkfist:BAABLgAFFH8PAAIBAAUJyxuPGgA5AQABAAUJyxuPGgA5AQAAAA==.',
Sa='Sabbybunnee:BAAALgADCgcJDAAAAA==.Sabbybunny:BAAALgAECggJCAAAAA==.Sabertrek:BAAALgADCgMJAwAAAA==.Saelyrinth:BAAALgADCgUJCAAAAA==.Saltybonez:BAAALgADCgUJBQAAAA==.Sambor:BAABLgAECn8bAAIOAAkJ7wl/TAA5AQAOAAkJ7wl/TAA5AQAAAA==.Sarapheena:BAABLgAECn8nAAIDAAkJ2hTXLgDLAQADAAkJ2hTXLgDLAQAAAA==.Saravian:BAAALgADCgUJBQAAAA==.Sardeench:BAAALgAECgEJAQAAAA==.Satanbomb:BAAALgAECgEJAgAAAA==.Satansbride:BAAALgAECgcJCAAAAA==.Saterli:BAACLgAFFH8OAAIUAAQJwA5sEgAGAQAUAAQJwA5sEgAGAQAuAAQKfzgAAxQACQkJHCwHANsCABQACQkJHCwHANsCABUABgmSA8ZNAKcAAAAA.Saturno:BAABLgAECn8UAAIPAAgJPxyQLgAkAgAPAAgJPxyQLgAkAgAAAA==.Saucypirate:BAABLgAECn8jAAINAAgJOxF5WgCxAQANAAgJOxF5WgCxAQAAAA==.Saulgoodman:BAAALgADCgMJAwAAAA==.Sauronknight:BAACLgAFFH8RAAIhAAQJKBbZRgA5AQAhAAQJKBbZRgA5AQAuAAQKfxQAAyEACAmsFamoAPYAACEACAmsFamoAPYAACIAAQk0Cp1RACUAAAAA.',
Sc='Scalvert:BAAALgAECgcJCwAAAA==.Scalypanda:BAABLgAECn8nAAMBAAkJRxNfHADSAQABAAkJRxNfHADSAQAZAAIJ0gzZNABuAAAAAA==.Scamander:BAABLgAECn8YAAIcAAkJnRxmEwCKAgAcAAkJnRxmEwCKAgABLgAECggJJgAfAEgZAA==.Scarléth:BAAALgADCggJCgAAAA==.Scoobs:BAAALgAECgYJEgAAAA==.Scorpinom:BAAALgADCgQJBAAAAA==.Sculi:BAAALgADCgcJBwAAAA==.Scurge:BAAALgAECgIJAgAAAA==.Scuttle:BAAALgADCgIJBgABLgAECgcJHgAGAB8YAA==.',
Se='Sei:BAAALgADCgIJAgAAAA==.Seiishiro:BAABLgAECn8uAAMKAAgJJQp2LwAyAQAKAAgJJQp2LwAyAQAOAAEJTATf4gAiAAAAAA==.Seldon:BAABLgAECn8sAAIPAAgJoR3ZJgBGAgAPAAgJoR3ZJgBGAgAAAA==.Semiosphere:BAAALgAECgkJAgAAAA==.Sennistian:BAAALgADCgMJBAABLgAECggJMAAgALcUAA==.Senyor:BAABLgAECn8yAAILAAgJ9RsCCQATAgALAAgJ9RsCCQATAgAAAA==.Seraphiel:BAABLgAECn8VAAMUAAYJgBzZHAC6AQAUAAYJZRvZHAC6AQAHAAUJChPgMwAZAQAAAA==.Seraphymm:BAAALgAECgcJEQAAAA==.',
Sh='Shacklebolt:BAABLgAECn8mAAMfAAgJSBnzJAB/AgAfAAgJSBnzJAB/AgAEAAQJWg+9MwDoAAAAAA==.Shadowsneak:BAABLgAECn8mAAImAAgJSgz6CQB4AQAmAAgJSgz6CQB4AQAAAA==.Shaelistra:BAABLgAECn8rAAIkAAgJmBe/CgDdAQAkAAgJmBe/CgDdAQAAAA==.Shalai:BAAALgADCggJDgAAAA==.Shalilama:BAACLgAFFH8UAAIDAAQJYR1hDAAUAQADAAQJYR1hDAAUAQAuAAQKf1EAAgMACQnUJeMAAJ4DAAMACQnUJeMAAJ4DAAAA.Shamanana:BAABLgAECn8UAAIXAAkJBg7bCwC/AQAXAAkJBg7bCwC/AQAAAA==.Shamboli:BAAALgADCgUJBQAAAA==.Shanazure:BAABLgAECn8qAAMBAAkJMh1EEQA7AgABAAkJxBpEEQA7AgAZAAcJGBlBEwCvAQAAAA==.Shaï:BAAALgADCgMJAwAAAA==.Sheikai:BAAALgADCgkJHwAAAA==.Shenderp:BAABLgAECn8lAAMUAAgJaREEIwCIAQAUAAgJaREEIwCIAQAVAAIJowJwWwBIAAAAAA==.Shieldhero:BAAALgAECgkJCAAAAA==.Shinerbock:BAABLgAECn8oAAMGAAgJuQ/SPAAkAQAGAAcJdQ3SPAAkAQAYAAEJFQcbjQApAAAAAA==.Shivä:BAAALgADCgcJCgABLgAECggJKQAIACsWAA==.Shriven:BAAALgAECgIJAgAAAA==.Shtark:BAAALgADCgYJCgAAAA==.',
Si='Sianvar:BAAALgAECggJDQAAAA==.Silastraza:BAAALgAFFAEJAQAAAA==.Silvanus:BAAALgAECgMJAwAAAA==.Silverjustis:BAABLgAECn8xAAIPAAgJPgiriAA+AQAPAAgJPgiriAA+AQAAAA==.Siwe:BAABLgAECn8wAAQXAAkJlSE4AgDfAgAXAAkJlSE4AgDfAgADAAcJVB1QIQAaAgAIAAEJpBJkgwA8AAAAAA==.',
Sk='Skadoosh:BAABLgAECn8eAAIYAAgJZCKcCACXAgAYAAgJZCKcCACXAgAAAA==.Skribblez:BAABLgAECn8fAAMPAAgJnx9tQwAaAgAPAAgJnx9tQwAaAgAQAAYJPCF6GQATAgAAAA==.Skrilled:BAABLgAECn8sAAIJAAYJdxNicAAxAQAJAAYJdxNicAAxAQAAAA==.',
Sl='Slackback:BAAALgAECgkJBAABLgAFFAQJEQAIALQaAA==.Sloot:BAAALgAECgYJDgAAAA==.Slughorn:BAAALgAECgcJBQABLgAECggJJgAfAEgZAA==.Slyv:BAAALgADCgcJBwAAAA==.',
Sm='Smellidan:BAAALgADCgEJAwAAAA==.Smïte:BAAALgAECgUJEgAAAA==.Smïtë:BAAALgAECgUJCgAAAA==.',
Sn='Snape:BAAALgAECgYJBgAAAA==.Snowcones:BAAALgAECgcJEwAAAA==.Snowman:BAAALgAECgMJBQAAAA==.Snw:BAAALgAECgcJEwAAAA==.',
So='Solerage:BAAALgAECgcJEAABLgAECgkJKAAZALskAA==.Sophielloyd:BAAALgAECgQJBQAAAA==.Soul:BAACLgAFFH8OAAIkAAQJeB67AgB4AQAkAAQJeB67AgB4AQAuAAQKfxwAAiQACQlwIdAEAMoCACQACQlwIdAEAMoCAAAA.Soulls:BAAALgAECgIJAgAAAA==.Soulsy:BAAALgAECgEJAgAAAA==.Sourgrip:BAABLgAECn8kAAIFAAkJShnUBgDwAQAFAAkJShnUBgDwAQAAAA==.',
Sp='Splendorae:BAABLgAECn8nAAIQAAkJqhShIwAFAgAQAAkJqhShIwAFAgAAAA==.Sprints:BAABLgAECn85AAIDAAkJmRmHEAChAgADAAkJmRmHEAChAgAAAA==.Spritz:BAAALgAECgEJAQAAAA==.Sprylf:BAAALgADCgMJBAAAAA==.Spwany:BAABLgAECn8WAAQWAAgJ3woqQAAbAQAWAAcJfwUqQAAbAQAaAAUJoA0WKgDwAAAoAAEJAABgcAAAAAAAAA==.Spyderelite:BAACLgAFFH8IAAIEAAMJ+AP2CQC7AAAEAAMJ+AP2CQC7AAAuAAQKfywAAgQACQn0FicEABcCAAQACQn0FicEABcCAAAA.',
Sq='Squeekems:BAAALgAECgIJAwAAAA==.Squirrel:BAABLgAECn8lAAIJAAkJ9B3GDgC0AgAJAAkJ9B3GDgC0AgAAAA==.',
St='Stainedhero:BAAALgADCgEJAQAAAA==.Stankstarstu:BAAALgAECgYJBgABLgAECgcJCAAMAAAAAA==.Starspeaker:BAABLgAECn8gAAMOAAcJfQaCZgDgAAAOAAcJfQaCZgDgAAAKAAIJiwPfdwBFAAAAAA==.Starykniight:BAAALgADCgMJAwABLgAECgcJHgAGAB8YAA==.Steveaustin:BAAALgAECgcJEgABLgAECgcJHgAGAB8YAA==.Stinkypeen:BAAALgAECgIJAgAAAA==.Stonecypher:BAABLgAECn8UAAIJAAYJswrBhwD+AAAJAAYJswrBhwD+AAAAAA==.Stoogotz:BAAALgADCgYJCAAAAA==.Stormlesbian:BAAALgADCgUJBQAAAA==.',
Su='Suhe:BAAALgADCggJHQAAAA==.Sundaresh:BAAALgAECgMJBgAAAA==.Sunwing:BAABLgAECn8nAAIUAAkJRhySDwBqAgAUAAkJRhySDwBqAgAAAA==.Sutileza:BAAALgADCgMJAwABLgAECgYJHQAOAAcRAA==.Suvien:BAAALgAECgUJDAAAAA==.',
Sw='Swagette:BAAALgADCgcJBwAAAA==.Swingkitti:BAABLgAECn8XAAIPAAcJqwedqQAHAQAPAAcJqwedqQAHAQAAAA==.',
Sx='Sxtitan:BAAALgAECggJEQAAAA==.',
Sy='Sylvarian:BAABLgAECn8mAAIpAAkJ+RJEAgANAgApAAkJ+RJEAgANAgAAAA==.Synareth:BAAALgAECgIJAwAAAA==.Syrodeus:BAAALgAECgQJBAAAAA==.',
Sz='Szz:BAABLgAECn8oAAIZAAkJuySeAAAuAwAZAAkJuySeAAAuAwAAAA==.',
['Sÿ']='Sÿn:BAAALgADCgcJFwAAAA==.',
Ta='Taelgar:BAAALgAECgcJEgAAAA==.Tanthalos:BAAALgAECgQJCgABLgAECggJGwATAD4PAA==.Targaryenelf:BAAALgADCgMJBAAAAA==.Taterdotz:BAAALgAECggJEwAAAA==.Tatortwats:BAABLgAECn8cAAIjAAcJ6hyzAgD8AQAjAAcJ6hyzAgD8AQAAAA==.Tatyrra:BAAALgADCgUJBQAAAA==.Tayswift:BAAALgADCgQJBAABLgAECgUJGAAMAAAAAA==.',
Te='Tenast:BAAALgADCgIJAgAAAA==.Tepicoyotl:BAABLgAECn8uAAIDAAgJDBYVIQAbAgADAAgJDBYVIQAbAgAAAA==.Tethir:BAAALgAECgkJAQAAAA==.',
Th='Thaymor:BAAALgADCgkJKQAAAA==.Thelonecone:BAACLgAFFH8WAAMFAAQJXB1wBQBWAQAFAAQJHhxwBQBWAQAhAAQJlQ8gJQABAQAuAAQKf1QAAwUACQl/Ix4BABUDAAUACQmDIh4BABUDACEACAkfIooVAPsCAAAA.Theoganth:BAAALgAECgYJBgAAAA==.Theraphee:BAAALgADCgcJEwAAAA==.Therimor:BAABLgAECn8YAAMDAAcJoQgHXQAWAQADAAYJZgkHXQAWAQAIAAEJHwHcnwAVAAAAAA==.Theronshan:BAAALgADCggJIQAAAA==.Thevoid:BAAALgAFFAMJAwAAAA==.Thoghas:BAAALgADCgYJBgAAAA==.Thomwizard:BAAALgAECgMJAwAAAA==.Thongrin:BAAALgADCgcJBwAAAA==.Thormorn:BAAALgADCgEJAgAAAA==.Thornarlenan:BAAALgADCgkJDgAAAA==.Thunnha:BAACLgAFFH8JAAIfAAMJlSEmRQAaAQAfAAMJlSEmRQAaAQAuAAQKfygAAx8ACQk5JDQFACkDAB8ACQk5JDQFACkDAAQAAQkcG1dmAEMAAAAA.Thurlando:BAAALgADCgIJBAAAAA==.',
Ti='Tierali:BAAALgAECgQJCAAAAA==.Tinandra:BAAALgADCgEJAQAAAA==.',
To='Toastedsushi:BAAALgAECgYJEQAAAA==.Toetagg:BAAALgAECgIJAwAAAA==.Toobooku:BAAALgADCgEJAQAAAA==.Toodamsirius:BAAALgAECgIJAgAAAA==.Toofwess:BAAALgADCgkJEAABLgAECgcJHgAGAB8YAA==.Toribia:BAAALgAECgQJBAAAAA==.Torí:BAAALgADCgYJCAAAAA==.Tosala:BAAALgAECgYJEQAAAA==.Totemkiller:BAABLgAECn8lAAIIAAgJYhHiLwBTAQAIAAgJYhHiLwBTAQAAAA==.Totemtwiddlr:BAABLgAECn8UAAIIAAgJuRzIFAB3AgAIAAgJuRzIFAB3AgABLgAFFAMJBAAMAAAAAA==.Totezmcgoats:BAAALgAECgUJBQAAAA==.',
Tr='Traael:BAABLgAECn85AAIJAAkJxBiMHQBLAgAJAAkJxBiMHQBLAgAAAA==.Trashbeard:BAAALgADCgIJAgAAAA==.Treebranch:BAAALgAECgEJAgAAAA==.Treesap:BAABLgAECn8nAAInAAkJrxp6AQDHAgAnAAkJrxp6AQDHAgAAAA==.Trinityeve:BAAALgAECgUJDAAAAA==.Trnz:BAAALgAFFAEJAQABLgAFFAMJBAAMAAAAAA==.Trnzlock:BAAALgAFFAEJAwABLgAFFAMJBAAMAAAAAA==.',
Tu='Tulanii:BAAALgADCgcJCAAAAA==.Tularana:BAABLgAECn82AAINAAkJHxyAHQCRAgANAAkJHxyAHQCRAgAAAA==.Tumble:BAABLgAECn8dAAMVAAgJzgdVMAAzAQAVAAgJzgdVMAAzAQAHAAEJCgG+bwAaAAAAAA==.Tummyissues:BAAALgAECgIJAgAAAA==.Tums:BAAALgAECgQJCQAAAA==.',
Tw='Twignberryz:BAAALgADCgcJCQABLgAECgcJCAAMAAAAAA==.Twinkie:BAABLgAECn8WAAIfAAkJvQhGjgA8AQAfAAkJvQhGjgA8AQAAAA==.Twodogz:BAABLgAECn8rAAIJAAgJUiMPEgCYAgAJAAgJUiMPEgCYAgAAAA==.',
Ty='Tyious:BAABLgAECn8oAAMhAAkJEBwPOQD5AQAhAAkJEBwPOQD5AQAiAAYJCAuRLADaAAAAAA==.Tyndara:BAABLgAECn8rAAIPAAgJOxI3WwCcAQAPAAgJOxI3WwCcAQAAAA==.',
['Tü']='Tüesdaÿ:BAAALgAECgcJCwAAAA==.',
Uc='Uchihazephyr:BAAALgADCgIJAgABLgAFFAQJFAADAGEdAA==.',
Un='Unbeat:BAABLgAECn8WAAMlAAkJVA6xFADVAQAlAAkJVA6xFADVAQAmAAEJGwzRHwA0AAAAAA==.Unbeliever:BAAALgAECgkJEQAAAA==.Unhoe:BAAALgADCggJEgAAAA==.Unholussie:BAACLgAFFH8NAAIhAAQJLgxsWQAcAQAhAAQJLgxsWQAcAQAuAAQKfzAAAiEACQl/HLUlAEoCACEACQl/HLUlAEoCAAAA.Unholybowner:BAAALgADCgcJDAAAAA==.Unstablè:BAAALgAECgYJCgAAAA==.',
Ur='Ursane:BAACLgAFFH8FAAIWAAMJqQocKwDLAAAWAAMJqQocKwDLAAAuAAQKfzIAAhYACQkXID4IAL4CABYACQkXID4IAL4CAAAA.Ursully:BAABLgAECn8rAAIbAAgJNSCWBQB8AgAbAAgJNSCWBQB8AgAAAA==.',
Uz='Uzi:BAABLgAECn8YAAIEAAYJVR1eCACaAQAEAAYJVR1eCACaAQAAAA==.',
Va='Vaardux:BAABLgAECn8iAAMQAAkJIh0CEwBUAgAQAAgJ5hwCEwBUAgAPAAgJmSE3MwASAgAAAA==.Vaelithra:BAAALgADCgEJAQAAAA==.Vaesyth:BAAALgADCgYJBgAAAA==.Valamarl:BAAALgADCgcJCAAAAA==.Valkeria:BAAALgAECgQJBQAAAA==.Valíthria:BAAALgAECgYJDAAAAA==.Vampulla:BAABLgAECn8pAAIcAAkJ6QmhVQBiAQAcAAkJ6QmhVQBiAQAAAA==.Vanncint:BAAALgAECgQJBAAAAA==.Vanndrygos:BAABLgAECn8aAAIBAAgJcgjZNwAmAQABAAgJcgjZNwAmAQAAAA==.Varea:BAAALgAECgIJAgAAAA==.Vashie:BAAALgAECggJEQAAAA==.Vathan:BAAALgAECgEJAgAAAA==.',
Ve='Veigar:BAAALgAECgcJDgABLgAFFAYJHgASAEMmAA==.Velanis:BAAALgADCgUJBwAAAA==.Velmir:BAAALgAECgkJBwAAAA==.Velorius:BAAALgAECgEJAgAAAA==.Venmo:BAAALgAECgEJAQAAAA==.Vexus:BAACLgAFFH8RAAIIAAQJtBotEwBEAQAIAAQJtBotEwBEAQAuAAQKfyYAAggACAmXI8MJAPcCAAgACAmXI8MJAPcCAAAA.Vexuss:BAAALgAECgkJAgABLgAFFAQJEQAIALQaAA==.',
Vi='Vidya:BAAALgADCgMJAwAAAA==.Vivifyght:BAAALgAECgQJAgAAAA==.',
Vl='Vladios:BAAALgAECgYJEAAAAA==.',
Vo='Voidwraith:BAAALgADCgEJAQAAAA==.Vordarian:BAABLgAECn8oAAQGAAkJ9A2tKQCRAQAGAAkJ9A2tKQCRAQARAAMJmgFKZwBdAAAYAAEJ3AnijwAnAAAAAA==.',
Vy='Vynciaagn:BAAALgADCgcJEgAAAA==.',
Wa='Wafflehouse:BAABLgAECn8YAAIhAAgJCh1EOQD4AQAhAAgJCh1EOQD4AQAAAA==.Walolas:BAAALgADCgcJEAAAAA==.Wamiya:BAAALgAECgEJAgAAAA==.Wapa:BAAALgAECgEJAQAAAA==.Warbatt:BAAALgADCggJCAAAAA==.Watchmeburst:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgAECgcJCgAAAA==.',
Wh='Whaler:BAABLgAECn8tAAIWAAgJRSTfBgDVAgAWAAgJRSTfBgDVAgAAAA==.Whìndy:BAAALgAECgQJBgABLgAECgYJGwAOAMwSAA==.',
Wi='Wildspanks:BAAALgADCgYJCQAAAA==.',
Wo='Wowoo:BAAALgAECgcJCAAAAA==.',
Wu='Wuzntmyfault:BAAALgAECgEJAQABLgAECgYJGwAOAMwSAA==.',
Xa='Xanadus:BAAALgAECgQJBAAAAA==.',
Xe='Xenos:BAAALgAECgMJBQAAAA==.Xenyodk:BAABLgAECn8mAAIhAAkJeCGeDQDgAgAhAAkJeCGeDQDgAgAAAA==.Xenyovoker:BAAALgAFFAMJBAAAAA==.',
Xi='Xideris:BAABLgAECn81AAICAAkJlCKLAQBmAwACAAkJlCKLAQBmAwAAAA==.Xiderís:BAAALgAECgYJBgAAAA==.',
Xt='Xtraxtra:BAABLgAECn8pAAMOAAgJZhm/HABWAgAOAAgJZhm/HABWAgAKAAgJ6g5ZKQBXAQAAAA==.',
Ya='Yaku:BAAALgAECgUJCAAAAA==.Yasura:BAAALgADCgcJBwAAAA==.',
Ye='Yetzi:BAAALgADCgIJAgAAAA==.Yetzibel:BAAALgADCgQJBAAAAA==.',
Yo='Yoan:BAAALgAFFAMJBgAAAQ==.Yoga:BAABLgAECn8fAAIGAAcJ9B7XDwBxAgAGAAcJ9B7XDwBxAgAAAA==.Yonicbonnet:BAABLgAECn8kAAIOAAgJGgqOTgAxAQAOAAgJGgqOTgAxAQAAAA==.Yoondo:BAAALgAECgUJCgAAAA==.Yorde:BAAALgADCgcJBwAAAA==.',
Ys='Ysandrell:BAAALgADCgMJAwAAAA==.Yshtola:BAABLgAECn8cAAIDAAkJqRX8GgBGAgADAAkJqRX8GgBGAgAAAA==.',
Yu='Yuffie:BAAALgAECgQJBAAAAA==.Yunara:BAACLgAFFH8LAAIcAAMJpR9XPQAGAQAcAAMJpR9XPQAGAQAuAAQKfzIAAhwACQnVH7gLAM8CABwACQnVH7gLAM8CAAEuAAUUBgkeABIAQyYA.Yunge:BAAALgADCgQJBAAAAA==.',
Za='Zabra:BAAALgAECgcJEwAAAA==.Zachpally:BAAALgADCgUJBQAAAA==.Zahvoker:BAABLgAECn8ZAAIZAAgJoQesDAAnAQAZAAgJoQesDAAnAQAAAA==.Zaldina:BAAALgADCggJDwAAAA==.Zapkitti:BAAALgADCgQJBAAAAA==.Zareline:BAAALgAECgUJCwAAAA==.Zathaeus:BAABLgAECn8rAAIcAAkJpRU/KgABAgAcAAkJpRU/KgABAgAAAA==.Zaylian:BAABLgAECn8oAAIdAAkJUxm5DQAUAgAdAAkJUxm5DQAUAgAAAA==.Zayragossa:BAACLgAFFH8OAAIfAAQJ3hV8NgA3AQAfAAQJ3hV8NgA3AQAuAAQKfxkAAh8ACAn/HnwlAC4CAB8ACAn/HnwlAC4CAAAA.Zayrah:BAAALgAECgUJBQABLgAFFAQJDgAfAN4VAA==.',
Ze='Zeerkk:BAABLgAECn8vAAIfAAkJyRhJJgAqAgAfAAkJyRhJJgAqAgAAAA==.Zelanta:BAAALgADCgQJBAAAAA==.Zenderal:BAAALgADCgcJBwABLgAFFAQJFAADAGEdAA==.Zergmark:BAAALgADCgMJAwAAAA==.Zero:BAAALgADCgIJAgAAAA==.',
Zo='Zoomzoom:BAAALgAECgUJCQABLgAFFAYJFAAVAGEMAA==.Zouris:BAAALgAECgYJCgAAAA==.',
Zt='Ztaziki:BAAALgADCgQJBAAAAA==.',
Zu='Zulkraa:BAAALgAECgYJEQAAAA==.Zulmex:BAAALgAECgYJCwAAAA==.Zunda:BAAALgAECgkJBwAAAA==.Zurtogg:BAABLgAECn8lAAMWAAkJIxhFEQBJAgAWAAkJIxhFEQBJAgAoAAMJVxQGJQDFAAAAAA==.',
Zy='Zynreth:BAAALgADCggJDAAAAA==.',
['Ài']='Àirén:BAAALgAECgEJAgAAAA==.',
['Îc']='Îcey:BAAALgAECgMJAwAAAA==.',
['Ön']='Öndi:BAAALgADCgYJBgAAAA==.',
['ßr']='ßrûh:BAAALgADCgEJAQAAAA==.',
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
