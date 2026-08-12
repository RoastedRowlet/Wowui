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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Priest-Discipline','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Fury','Evoker-Augmentation','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Hunter-Survival','Hunter-Marksmanship','Warrior-Arms','Warrior-Protection','Priest-Holy','Monk-Brewmaster','Mage-Arcane','Druid-Balance','DeathKnight-Blood','Druid-Guardian','Warlock-Affliction','Druid-Feral','Evoker-Preservation','Evoker-Devastation','Shaman-Enhancement','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aaminae:BAABLgAECn8+AAIBAAkJkxgpDQBUAgABAAkJkxgpDQBUAgAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgUJCwAAAA==.Abracastabya:BAAALgAFFAEJAQAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.Abÿss:BAAALgAECgYJBgAAAA==.',
Ad='Adachï:BAABLgAECn8WAAIDAAYJiRpuNQCfAQADAAYJiRpuNQCfAQABLgAECgkJMwAEABMfAA==.Adevil:BAAALgAECgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aegon:BAABLgAECn8ZAAMFAAkJ1BkrAgDbAQAFAAkJHRIrAgDbAQAGAAUJzRsCCgChAQAAAA==.Aethlin:BAABLgAECn86AAMHAAkJ6xzKMgA1AgAHAAkJjRnKMgA1AgAIAAgJhh1UCwASAgAAAA==.Aetreyu:BAAALgAECgcJEgAAAA==.Aeturnas:BAABLgAECn81AAIJAAkJ7B+jCAABAwAJAAkJ7B+jCAABAwAAAA==.',
Ag='Aggros:BAAALgAECgYJBgAAAA==.Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanash:BAAALgAECgEJAQAAAA==.Alanima:BAABLgAECn8dAAMKAAgJjQzuKgB+AQAKAAgJjQzuKgB+AQALAAYJ3AbYUQDKAAAAAA==.Alauradona:BAAALgADCgQJBAAAAA==.Albus:BAAALgAECgEJAgAAAA==.Aldky:BAAALgAECgEJAQAAAA==.Aliana:BAAALgAFFAEJAQAAAA==.Alinthe:BAAALgADCgkJCQAAAA==.Allesta:BAAALgADCgEJAQAAAA==.Allindis:BAAALgAECgYJCQABLgAECgkJJQAEALEYAA==.Allypally:BAAALgAECgEJAwAAAA==.Alphamage:BAAALgADCggJCAAAAA==.Alphamonk:BAAALgAECgkJEgAAAA==.Alros:BAABLgAECn9XAAIMAAkJzyPyAQAQAwAMAAkJzyPyAQAQAwAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgAECgQJCAAAAA==.',
Am='Amardyton:BAAALgAECgYJBwAAAA==.',
An='And:BAABLgAECn8sAAMNAAgJYhSTCgD4AAANAAgJYhSTCgD4AAAOAAEJ6QOdOAEcAAAAAA==.Aneas:BAAALgAECgcJEQAAAA==.Antäres:BAAALgADCgQJBAABLgAECgkJMwAEABMfAA==.',
Ap='Apolex:BAAALgADCgUJBQAAAA==.Appela:BAAALgAECgEJAgAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgMJAwACAAAAAA==.Arcie:BAAALgADCgEJAQABLgAFFAQJDAAPADcaAA==.Arcstream:BAAALgAECgkJEwAAAA==.Arette:BAAALgAECgcJCwAAAA==.Arkades:BAACLgAFFH8FAAIHAAIJyRZeRACTAAAHAAIJyRZeRACTAAAuAAQKfyUAAgcACQmnHWQjAHgCAAcACQmnHWQjAHgCAAAA.Arkshade:BAABLgAECn87AAIGAAkJBxDefgBmAQAGAAkJBxDefgBmAQAAAA==.Arlia:BAAALgAECgkJEQABLgAFFAIJBgAQAFYCAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECgkJKgARAI8fAA==.Aryn:BAAALgAECgEJAQAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgcJEAACAAAAAA==.Ashor:BAAALgAECgIJAgAAAA==.Ashrodite:BAAALgADCgYJAgABLgAECgcJEAACAAAAAA==.Asmo:BAAALgADCggJGAAAAA==.Aspir:BAEALgAECgYJBgABLgAFFAgJGQAFAIATAA==.Astarii:BAAALgAECgQJCwAAAA==.Asterica:BAABLgAECn9ZAAMSAAkJ+xjDAQDcAQATAAkJWBi6MQARAgASAAgJnRbDAQDcAQAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.Atormunster:BAAALgADCgMJAwABLgAFFAIJBQAMAJwGAA==.Atsumisa:BAAALgAECgkJCQAAAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAIUAAYJ+A16UwA4AQAUAAYJ+A16UwA4AQAAAA==.',
Av='Averynicole:BAABLgAECn8ZAAIVAAcJBxYLLABfAQAVAAcJBxYLLABfAQAAAA==.',
Aw='Awasjr:BAABLgAECn8mAAIMAAkJlh/GGACSAgAMAAkJlh/GGACSAgAAAA==.Awassy:BAAALgAECgEJAgAAAA==.',
Ay='Ayano:BAACLgAFFH8HAAIWAAEJBR+MbwA9AAAWAAEJBR+MbwA9AAAuAAQKfxYAAhYACAliHrFKAPsBABYACAliHrFKAPsBAAAA.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balanla:BAAALgAECgcJCAABLgAFFAQJDAAPADcaAA==.Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDwABLgAECgkJMwAEABMfAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgAECgEJAQAAAA==.Bearhug:BAACLgAFFH8HAAMDAAMJAAiGUgBfAAADAAMJAAiGUgBfAAAVAAEJoAHDSgApAAAuAAQKfy8AAwMACAn1Gnc8AH4BAAMABwntGXc8AH4BABUABwleCYFCAA0BAAEuAAUUBAkOABcA6gwA.Bearshock:BAACLgAFFH8OAAMXAAQJ6gxGLQDfAAAXAAQJ6gxGLQDfAAAUAAEJTACOjwAdAAAuAAQKfx4AAhcACAneHZEUAEYCABcACAneHZEUAEYCAAAA.Beasty:BAACLgAFFH8FAAMMAAIJnAZcUQB8AAAMAAIJnAZcUQB8AAAYAAIJUAGJLgBnAAAuAAQKfyUAAxkACAkeEK8RAEABABkACAkeEK8RAEABABgABgmHBPI9ANQAAAAA.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAACLgAFFH8FAAIHAAEJoSUIVABrAAAHAAEJoSUIVABrAAAuAAQKfzcAAggACQnkJPYAAFQDAAgACQnkJPYAAFQDAAAA.Beeb:BAAALgAECgUJDgABLgAFFAEJBQAHAKElAA==.Beefisting:BAAALgAECgYJDAABLgAFFAEJBQAHAKElAA==.Beethicc:BAAALgAECgEJBAABLgAFFAEJBQAHAKElAA==.Beeuwu:BAAALgAECgIJAwABLgAFFAEJBQAHAKElAA==.Beliara:BAAALgAECgkJDgAAAA==.Belijoe:BAAALgAECgEJAQAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Belshuntress:BAAALgAECgEJAgAAAA==.Beverage:BAAALgAECgQJBQAAAA==.',
Bi='Bicboi:BAAALgAECgEJAQAAAA==.Biglewt:BAAALgAECgIJAgAAAA==.Bigmattyl:BAAALgAECgcJCgAAAA==.Bionarra:BAABLgAECn8/AAIWAAkJ0B3VBQBNAgAWAAkJ0B3VBQBNAgAAAA==.Bishopwr:BAABLgAECn8pAAMaAAkJvBdQDAAiAgAaAAkJvBdQDAAiAgAbAAYJCwohMwCvAAAAAA==.Bittertøfu:BAABLgAECn8eAAIXAAcJfQb/WQDWAAAXAAcJfQb/WQDWAAAAAA==.',
Bl='Blackmagick:BAAALgAECgQJBAAAAA==.Blackwidöw:BAAALgAECgIJCgAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blessu:BAAALgAECgEJAwAAAA==.Blitê:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Bm='Bmpfrostie:BAABLgAECn8WAAIWAAcJcQ41yABYAQAWAAcJcQ41yABYAQAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECgkJPAAcADsdAA==.Bohica:BAAALgAECggJDgAAAA==.Bonetotem:BAAALgAECgEJAQABLgAECgkJRAAdALQUAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAABLgAFFAMJCQAGAEMgAA==.',
Br='Brakug:BAABLgAECn8vAAMWAAkJHiMULgC5AgAWAAkJHiMULgC5AgAeAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAIJAwAAAA==.Brem:BAACLgAFFH8IAAIeAAMJiBnrAQD5AAAeAAMJiBnrAQD5AAAuAAQKfxsAAh4ACAmCHB4EABICAB4ACAmCHB4EABICAAAA.Bretagnesse:BAABLgAECn8UAAIfAAgJ2wXJRQD1AAAfAAgJ2wXJRQD1AAAAAA==.Brewc:BAAALgADCgUJCAABLgAECgkJPgAcAF0UAA==.Briara:BAAALgAECgYJDwAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgAECgQJCgAAAA==.Broníx:BAAALgAECgEJBQAAAA==.Bropeep:BAACLgAFFH8HAAIGAAMJDhutjgDtAAAGAAMJDhutjgDtAAAuAAQKf1MAAwYACQnZJT0EAF4DAAYACQnZJT0EAF4DAAUABAmdFKIcAOkAAAAA.Brotality:BAAALgADCgMJBAAAAA==.Brynhildr:BAAALgAECgcJDwABLgAFFAYJFwAdAFIfAA==.',
Bu='Bulder:BAAALgAECgQJBAAAAA==.Bullshott:BAABLgAECn8jAAIMAAkJrx1qHQB1AgAMAAkJrx1qHQB1AgAAAA==.Bum:BAABLgAECn8mAAMfAAkJsh/4BABRAwAfAAkJsh/4BABRAwAEAAEJ0xCM0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgAECgUJCQAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJEQAAAA==.Bynx:BAAALgAECgEJAQABLgAECgkJHwAMAMUVAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBgAAAA==.',
['Bú']='Búll:BAAALgAECgEJAQAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAABLgAECn8eAAMGAAkJaxO9bgCHAQAGAAkJLxK9bgCHAQAgAAYJdA1nMgDTAAABLgAECgkJRAAdALQUAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn80AAIHAAkJ2AgNjABZAQAHAAkJ2AgNjABZAQAAAA==.Carrots:BAABLgAECn8vAAIMAAkJCBWgSADIAQAMAAkJCBWgSADIAQAAAA==.Cartman:BAABLgAFFH8HAAIbAAQJSRfcEwAEAQAbAAQJSRfcEwAEAQABLgAFFAQJEAAhAEIcAA==.Cashmachine:BAABLgAECn8tAAIMAAkJAx8VGwCDAgAMAAkJAx8VGwCDAgAAAA==.Cashmoolah:BAAALgAECgUJBQAAAA==.Castorice:BAAALgAECgEJAQAAAA==.Catfight:BAABLgAECn9GAAIIAAkJ/xBKCADlAAAIAAkJ/xBKCADlAAAAAA==.',
Ch='Chadilton:BAAALgAECgYJCAAAAA==.Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMTAAkJdBhqLgBTAgATAAkJdBhqLgBTAgASAAEJAABoZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8SAAQMAAUJVyESNQBDAQAMAAUJMyASNQBDAQAZAAEJISI3IwBlAAAYAAEJzA98MgBIAAAuAAQKfxwABBkACAmLIsIYAGYCABkACAkjIcIYAGYCAAwABQlPHXFcAJABABgAAwkrGAlMAIUAAAAA.Cheesecake:BAABLgAECn82AAMSAAkJvBBADAB7AQASAAgJBRJADAB7AQAiAAUJhgt4CACwAAAAAA==.Chelsie:BAAALgAECgcJDAABLgAFFAYJFwAdAFIfAA==.Chihiko:BAAALgAECgMJAwAAAA==.Choks:BAABLgAECn87AAIPAAkJBQ7NDAD/AAAPAAkJBQ7NDAD/AAAAAA==.Chubbycat:BAABLgAECn8VAAMEAAcJLhmOPQCuAQAEAAcJLhmOPQCuAQAjAAUJYh35FwBTAQAAAA==.Chuggz:BAABLgAECn81AAIdAAkJoBpSDQBjAgAdAAkJoBpSDQBjAgAAAA==.Chéfboyrlee:BAACLgAFFH8jAAILAAkJ3Ba0BQAjAgALAAkJ3Ba0BQAjAgAuAAQKfzYAAgsACQn6IrkEAAwDAAsACQn6IrkEAAwDAAAA.',
Ci='Cizmac:BAAALgAECgYJDgAAAA==.',
Cm='Cmdrshepard:BAAALgADCgMJAwABLgAFFAIJBwAiAE4IAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAABLgAECn8ZAAMFAAYJLQt3CQCzAAAFAAYJLQt3CQCzAAAGAAEJpA2SUwAwAAAAAA==.Cownado:BAABLgAECn9EAAIdAAkJtBSyBAAlAQAdAAkJtBSyBAAlAQAAAA==.',
Cr='Crematorion:BAAALgAECgMJAwAAAA==.Crippin:BAAALgAECgEJAQAAAA==.Crouton:BAAALgADCgkJCgAAAA==.',
Ct='Ctrlaltchill:BAAALgADCgEJAQAAAA==.',
Cu='Cursedspirit:BAAALgAECgQJBwAAAA==.',
Cy='Cybelem:BAABLgAECn8tAAIXAAkJmB5ZEABwAgAXAAkJmB5ZEABwAgAAAA==.Cyfelen:BAABLgAECn8ZAAQSAAkJiB9oAQDWAgASAAkJiB9oAQDWAgAiAAQJLxmtHQDSAAATAAIJrw+H+AByAAAAAA==.Cynleel:BAAALgAECggJEQABLgAECgkJSQAKAJsWAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.Damonsouls:BAAALgAECgEJAwAAAA==.Dandistyle:BAABLgAECn8fAAMdAAkJdx1kCwB+AgAdAAkJbh1kCwB+AgAVAAEJchK2fAAzAAAAAA==.Darknature:BAAALgAECgkJCQAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Darthmall:BAAALgADCgMJAwABLgAFFAYJFwAdAFIfAA==.Dawgg:BAAALgAECgIJAgAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathblade:BAAALgAECgEJAQAAAA==.Deathmatrynn:BAAALgAECgYJDgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAACLgAFFH8FAAIXAAIJ2gUkSwBnAAAXAAIJ2gUkSwBnAAAuAAQKfxUAAhcACAnaFl8eAO8BABcACAnaFl8eAO8BAAAA.Deeviant:BAAALgAECggJDgAAAA==.Defend:BAABLgAFFH8QAAIhAAQJQhynBgA1AQAhAAQJQhynBgA1AQAAAA==.Delrager:BAACLgAFFH8HAAIBAAIJch5vLwCtAAABAAIJch5vLwCtAAAuAAQKfygAAgEABwmYI3cNAFACAAEABwmYI3cNAFACAAAA.Delyta:BAAALgAECgkJCQAAAA==.Demidru:BAABLgAECn8cAAMhAAgJtROXBQBbAQAhAAcJjBSXBQBbAQAjAAgJDAaACAC8AAAAAA==.Demonicdawn:BAAALgADCgEJAQAAAA==.Demónícz:BAAALgAECgMJAwAAAA==.Derat:BAAALgAECgkJEQAAAA==.Destroy:BAABLgAFFH8GAAITAAMJpQMORgCAAAATAAMJpQMORgCAAAABLgAFFAQJEAAhAEIcAA==.Deverux:BAAALgAECgEJAQAAAA==.',
Di='Dibbydab:BAABLgAECn8qAAIUAAkJBxbTCAC2AQAUAAkJBxbTCAC2AQAAAA==.Dixencider:BAAALgAECgIJAgAAAA==.',
Dj='Django:BAABLgAECn82AAMfAAkJsyIdBgD2AgAfAAkJsyIdBgD2AgAEAAIJkAbHxgA+AAAAAA==.Djatalon:BAABLgAECn8WAAMkAAUJuAsWIwDWAAAkAAUJuAsWIwDWAAAlAAMJrAUaHABsAAAAAA==.Djderpyderpy:BAAALgAECgYJDQAAAA==.Djehrtey:BAAALgAECgkJEQAAAA==.Djin:BAAALgAECgMJBAABLgAFFAYJFwAdAFIfAA==.Djinni:BAACLgAFFH8XAAIdAAYJUh/AEwCFAQAdAAYJUh/AEwCFAQAuAAQKfzUAAx0ACQk9IXkGANMCAB0ACAlsI3kGANMCABUACQkSG6gOAF4CAAAA.',
Dk='Dkota:BAAALgAECgUJBgAAAA==.',
Do='Dobath:BAAALgADCgQJBAAAAA==.Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8fAAMFAAgJtxtyCAAHAgAFAAgJtxtyCAAHAgAGAAMJsA2A/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8YAAQkAAcJNxmADwDUAQAkAAcJNxmADwDUAQAQAAQJuwziYQC1AAAlAAEJAACAPAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Dragodeeps:BAAALgAECgQJBAABLgAFFAIJBQAXANoFAA==.Draknem:BAAALgAECgYJBwAAAA==.Dramaticus:BAAALgAECgQJBAAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drenleah:BAABLgAECn8XAAISAAkJpRZ0BQAZAgASAAkJpRZ0BQAZAgABLgAECgkJSAAOAPwbAA==.Drenlee:BAAALgAECgEJAgABLgAECgkJSAAOAPwbAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgABLgAECgEJAQACAAAAAA==.Dryya:BAAALgAECgQJCAAAAA==.Drêck:BAAALgAECgEJAQAAAA==.',
Du='Dumblegear:BAABLgAECn8fAAMWAAgJpRVRbACiAQAWAAgJpRVRbACiAQAeAAEJbQY0IAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAFFAQJDAAPADcaAA==.Durian:BAAALgAECgIJAgABLgAFFAEJAQACAAAAAA==.',
Dw='Dwagon:BAAALgADCgUJBQAAAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dysdayne:BAAALgAECgYJCAABLgAFFAMJBgALAMUHAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgAECgEJAQAAAA==.Dädärkbeëf:BAAALgADCgcJCQAAAA==.',
Ed='Edinna:BAABLgAECn9OAAMWAAkJNRyrBACDAgAWAAkJNRyrBACDAgAeAAQJTQoTEADBAAAAAA==.',
Ee='Eevie:BAAALgADCgUJCAAAAA==.',
Ei='Einekliene:BAAALgAECgcJBwAAAA==.',
Ek='Ekatrina:BAAALgAECgEJAQAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Eldernoc:BAABLgAECn8jAAIhAAkJzRHYAwCkAQAhAAkJzRHYAwCkAQAAAA==.Elessedil:BAAALgAECggJDwAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgYJEgAAAA==.Elucidäte:BAAALgAECgEJAQAAAA==.Elyriana:BAABLgAECn8jAAMEAAkJpSAKCQAoAwAEAAkJpSAKCQAoAwAjAAEJqSBoQQBZAAAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEBLgAECn8kAAIMAAYJPyKCEQBgAQAMAAYJPyKCEQBgAQABLgAECgkJLAAMANQgAA==.Emirozu:BAAALgAECgUJAgAAAA==.Emixi:BAAALgAECgQJBQAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECggJEAAAAA==.Emritelan:BAAALgAECgUJCAAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8YAAIHAAYJixdsJgBvAQAHAAYJixdsJgBvAQAuAAQKfzEAAgcACQmaHwIlAHACAAcACQmaHwIlAHACAAAA.',
Ep='Epedemik:BAAALgAECgcJCQAAAA==.',
Er='Erazath:BAAALgAECgUJBgABLgAFFAMJBwAgAI8JAA==.Eredo:BAAALgAECgUJCwABLgAFFAQJDAAPADcaAA==.Erieladra:BAAALgAECgEJAQAAAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgAECgIJAgAAAA==.Erush:BAAALgAECgEJAQAAAA==.',
Es='Esha:BAAALgAECgEJAQAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ex='Exhul:BAAALgAECgEJAQAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Faewing:BAABLgAFFH8GAAIQAAIJVgKBXgBcAAAQAAIJVgKBXgBcAAAAAA==.Falar:BAAALgAECggJDQAAAA==.Fatelf:BAAALgADCgMJAwAAAA==.Fatowlbert:BAAALgAECgEJAgAAAA==.Faval:BAAALgAECggJDwABLgAECgkJKgARAI8fAA==.Favel:BAABLgAECn8qAAMRAAkJjx9OAQAcAwARAAgJ4iFOAQAcAwAOAAkJRwv4XwBpAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn9iAAIMAAkJBR32BABwAgAMAAkJBR32BABwAgAAAA==.Febz:BAABLgAECn8eAAIWAAgJbBsqMACyAgAWAAgJbBsqMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAABLgAECn8aAAIOAAgJZh/xIgBFAgAOAAgJZh/xIgBFAgAAAA==.Felfüry:BAACLgAFFH8LAAMNAAMJ8Qc4GABiAAANAAMJ8Qc4GABiAAARAAMJxwNYEABOAAAuAAQKf0cABA0ACQm/FEMTAPwBAA0ACQm/FEMTAPwBABEACAmGCb4WAPEAAA4AAglYCZYGAUQAAAAA.Felly:BAAALgAECgYJBgAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Festicules:BAAALgAECgQJBAAAAA==.Festyr:BAAALgAECgQJCAAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAABLgAECn8WAAMDAAgJOhNyBwC9AQADAAgJOhNyBwC9AQAVAAMJLgOtZQB2AAAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECggJDAACAAAAAA==.Finella:BAACLgAFFH8GAAIFAAMJEg7ODQDEAAAFAAMJEg7ODQDEAAAuAAQKfx4AAwUACQlcHtwBAAgCAAUACQmvHNwBAAgCACAABglrFgsmACMBAAAA.Finigin:BAAALgAECgEJAQABLgAFFAIJBQAHAMkWAA==.Finneas:BAAALgAECgEJBgABLgAFFAIJBQAHAMkWAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJLwAWAB4jAA==.Fistsofurry:BAAALgAECgQJBAABLgAFFAMJBgAFABIOAA==.',
Fo='Fogassann:BAACLgAFFH8KAAIGAAQJvxm7PwDgAAAGAAQJvxm7PwDgAAAuAAQKfxkAAgYACQmvHBUrAFQCAAYACQmvHBUrAFQCAAEuAAUUBAkMAA8ANxoA.Fogdemon:BAAALgAECgIJBAABLgAFFAUJGAAiAHMUAA==.Foggpy:BAACLgAFFH8YAAMiAAUJcxR+BQAvAQAiAAUJcxR+BQAvAQATAAQJnwOOcwDaAAAuAAQKfy4ABCIACQnxJLYAAHYCACIACQnxJLYAAHYCABMABgkNG8FXAMABABIABgljGQ4fAFgBAAAA.Foxyhuntress:BAAALgAECgEJAQAAAA==.Foxyshammy:BAAALgAECgEJAQAAAA==.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freinkenbaby:BAAALgAECgEJAQAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostnuts:BAAALgAECgEJAQAAAA==.Frostybear:BAABLgAECn9JAAIWAAkJAhpNLABoAgAWAAkJAhpNLABoAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAACLgAFFH8HAAIgAAMJhAjILgCKAAAgAAMJhAjILgCKAAAuAAQKf0IAAyAACQl8C/MhAEMBACAACQlpC/MhAEMBAAUAAglCBCg3AEAAAAAA.',
Fu='Fuzzyguy:BAAALgAECgEJAQAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Gacy:BAAALgAECgEJAQAAAA==.Galaythien:BAAALgAECgYJEgAAAA==.Gang:BAAALgAECgUJBQABLgAFFAQJEQABADIOAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAOAEQaAA==.',
Ge='Geluria:BAABLgAECn8aAAMgAAkJdB2tBwCeAgAgAAkJdB2tBwCeAgAFAAEJ5Q6JPAAuAAABLgAECgkJOgAdAN0kAA==.Geret:BAABLgAECn8iAAIHAAgJdxO1cgCIAQAHAAgJdxO1cgCIAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gh='Ghanaria:BAAALgAECgEJAQAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Glador:BAAALgAECgcJBwAAAA==.Gleesh:BAAALgAECgEJAQABLgAFFAEJBwAWAAUfAA==.Glitchy:BAABLgAECn9IAAMfAAkJ3x8CCADVAgAfAAkJZx8CCADVAgAhAAYJGhYLGgB+AQAAAA==.Glokraz:BAAALgAECgcJBwAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgYJDQAAAA==.',
Gn='Gnineteen:BAAALgADCgQJBAAAAA==.',
Go='Goingtogetu:BAABLgAECn9IAAMIAAkJrSP0AQAhAwAIAAkJrSP0AQAhAwAHAAYJBxDWkwBMAQAAAA==.Gold:BAAALgAECgIJAgABLgAECgkJKwAcAD4fAA==.Goldfarmr:BAABLgAECn8rAAIcAAkJPh+9DACbAgAcAAkJPh+9DACbAgAAAA==.Goldrawr:BAAALgAECgYJBwABLgAECgkJKwAcAD4fAA==.Goldshocker:BAAALgAECgQJBgABLgAECgkJKwAcAD4fAA==.Golduwu:BAAALgAECgEJAgABLgAECgkJKwAcAD4fAA==.Googlymoogly:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.Gottahvyhand:BAAALgAECgQJBQAAAA==.',
Gr='Greed:BAAALgAFFAIJAgABLgAFFAcJDQAhAG0YAA==.Greeley:BAABLgAECn86AAIZAAkJMCTnAAA9AwAZAAkJMCTnAAA9AwAAAA==.Gregdapro:BAABLgAECn9TAAIgAAkJuSX3AABeAwAgAAkJuSX3AABeAwAAAA==.Gregnstone:BAABLgAECn8jAAIJAAkJlRY+KADJAQAJAAkJlRY+KADJAQABLgAECgkJUwAgALklAA==.Greyback:BAAALgADCgIJAgAAAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAUJHAAQABoTAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAgJJAAPAEUZAA==.Gunnyal:BAABLgAECn88AAMaAAkJeRdIBABRAQAaAAkJeRdIBABRAQAPAAUJhwqeaAC8AAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8wAAIXAAkJUyM8BQAJAwAXAAkJUyM8BQAJAwAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8kAAMPAAgJRRn+AwA9AgAPAAgJRRn+AwA9AgAaAAEJNAEQDgA8AAAuAAQKfzwAAw8ACQktJWkCAE0DAA8ACQktJWkCAE0DABoAAwldHN86ANkAAAAA.Hakyahi:BAAALgAECgEJAQAAAA==.Hallokitty:BAAALgAECgEJAgAAAA==.Hank:BAAALgADCgYJBgAAAA==.Happerixie:BAAALgAECgYJDAAAAA==.Harkin:BAABLgAECn8/AAMHAAkJdRMmXwCzAQAHAAkJdRMmXwCzAQAJAAIJiQMdHgA5AAAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Harrynear:BAAALgAECgMJBAAAAA==.Hatchett:BAAALgAECgYJDgAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIXAAcJXQsvTwD6AAAXAAcJXQsvTwD6AAAAAA==.Hevy:BAABLgAECn9IAAIOAAkJ/BuiAwAmAgAOAAkJ/BuiAwAmAgAAAA==.',
Hi='Hilarius:BAAALgAECggJEQAAAA==.Hiraeth:BAAALgAECgUJCQAAAA==.Hirukon:BAAALgAECgEJAQAAAA==.',
Ho='Holydadbod:BAAALgAECgQJBwABLgAFFAYJFwAdAFIfAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn9FAAIHAAkJARlxLQBLAgAHAAkJARlxLQBLAgAAAA==.Hottice:BAAALgAECgEJAwAAAA==.Howlinnbrews:BAABLgAFFH8IAAMVAAQJbxvoGgDzAAAVAAQJDRboGgDzAAAdAAEJ6CVsTwBkAAAAAA==.Howlinplague:BAAALgAFFAIJBAAAAA==.',
Hu='Hulkhogan:BAABLgAECn8fAAIbAAkJAR1uCABzAgAbAAkJAR1uCABzAgAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIOAAMJRBo1YADPAAAOAAMJRBo1YADPAAAuAAQKfycAAg4ACAkuIrAVANQCAA4ACAkuIrAVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMEAAgJjBi1KAANAgAEAAgJjBi1KAANAgAjAAIJ1hLbSQBGAAAAAA==.Idrizzt:BAAALgAECgYJBgAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8aAAIVAAcJVBbeNgAnAQAVAAcJVBbeNgAnAQAAAA==.',
Il='Illidanielle:BAAALgAECgEJAgAAAA==.Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgAECgEJAQAAAA==.Invariable:BAAALgAECgEJAQAAAA==.',
Io='Io:BAABLgAFFH8NAAIdAAUJSyH8EgCLAQAdAAUJSyH8EgCLAQAAAA==.Iobo:BAABLgAECn9EAAIYAAkJwRdSBABIAQAYAAkJwRdSBABIAQAAAA==.',
Ir='Ironhidez:BAABLgAECn8+AAIHAAkJlg5IZgCjAQAHAAkJlg5IZgCjAQAAAA==.',
Is='Isaarek:BAABLgAECn8oAAIQAAkJAxZpFQAvAgAQAAkJAxZpFQAvAgAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDwAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAkJJwAGAIAYAA==.Jasmini:BAAALgAECgEJAwAAAA==.Jastia:BAABLgAECn8fAAISAAgJlx0pCQC2AQASAAgJlx0pCQC2AQAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jeb:BAAALgAECgEJAgABLgAFFAEJAQACAAAAAA==.Jebopally:BAAALgAECgMJBAABLgAFFAEJAQACAAAAAA==.Jekelez:BAAALgADCgYJCQAAAA==.Jessejames:BAAALgAECgEJAQAAAA==.Jetblack:BAABLgAECn8sAAMTAAkJAhzIHgBsAgATAAkJAhzIHgBsAgASAAEJAAD2bQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8vAAIHAAkJTw55YQCtAQAHAAkJTw55YQCtAQAAAA==.',
Jo='Joecephus:BAABLgAECn81AAIJAAkJhCGDDwCgAgAJAAkJhCGDDwCgAgAAAA==.Joehex:BAABLgAECn88AAIbAAkJgyFiBADfAgAbAAkJgyFiBADfAgAAAA==.Joeschmonk:BAAALgAECgYJBwAAAA==.Joulez:BAAALgAECgEJAQAAAA==.',
Ju='Jubelius:BAAALgAECgYJCQABLgAECgkJHwAMAMUVAA==.Judgematt:BAABLgAECn8iAAIJAAkJdBeeGgAvAgAJAAkJdBeeGgAvAgAAAA==.Justin:BAABLgAECn8fAAIaAAkJvhUIDgAJAgAaAAkJvhUIDgAJAgAAAA==.',
Ka='Kaella:BAAALgAECgQJBAAAAA==.Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAIZAAgJ1AwBFAAhAQAZAAgJ1AwBFAAhAQABLgAFFAIJBQAXANoFAA==.Kaleesh:BAACLgAFFH8UAAImAAgJQiS1AABnAgAmAAgJQiS1AABnAgAuAAQKfycAAiYACQlHJkcBAGgDACYACQlHJkcBAGgDAAAA.Kallux:BAABLgAECn9WAAIgAAkJQCFdBQDUAgAgAAkJQCFdBQDUAgAAAA==.Kananga:BAABLgAECn8xAAIcAAkJYhgrCQAlAQAcAAkJYhgrCQAlAQAAAA==.Kanati:BAAALgAECgEJAQABLgAECgkJDwACAAAAAA==.Karavira:BAAALgAECgEJAQAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Katniss:BAAALgAECgEJBAAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgAECgYJBgAAAA==.Kazarka:BAAALgAECgEJAQAAAA==.',
Ke='Kelindina:BAAALgAECgMJDQAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Keoeu:BAAALgAECggJEgAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgYJEgAAAA==.',
Ki='Kieleron:BAABLgAECn8kAAIKAAgJARPoGgD4AQAKAAgJARPoGgD4AQAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJEAAAAA==.Kiermaxim:BAABLgAECn8mAAIXAAgJNBwcGwA6AgAXAAgJNBwcGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Killon:BAAALgAECgEJAQABLgAECgkJOQAHADIUAA==.Kimijo:BAAALgAECgEJBAAAAA==.Kindred:BAAALgAECggJCQAAAA==.Kiragrande:BAABLgAECn8iAAIDAAkJxBByLQDIAQADAAkJxBByLQDIAQAAAA==.Kiraneth:BAABLgAECn8gAAIVAAgJMBA7LQBYAQAVAAgJMBA7LQBYAQAAAA==.Kirbie:BAAALgADCgUJBQAAAA==.Kirial:BAAALgAECgkJDAAAAA==.Kiriku:BAABLgAECn8YAAIfAAkJeQ9yDgDVAAAfAAkJeQ9yDgDVAAAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.Klorto:BAAALgAECgEJAQAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgYJCgAAAA==.',
Ku='Kumaz:BAAALgAECgMJAwAAAA==.Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgAECgEJAgAAAA==.',
La='Lagartista:BAABLgAFFH8FAAIQAAIJHRfsKAB/AAAQAAIJHRfsKAB/AAAAAA==.Largcok:BAAALgAECgYJDwAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Le='Lee:BAAALgAFFAYJAQAAAA==.Lefty:BAAALgADCgcJCgABLgAECgkJPgAYAAoUAA==.Leyn:BAAALgAECgUJBQAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lilpwny:BAAALgAECgQJBAABLgAECgkJIQALADEYAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn88AAIPAAkJ0iQgAwA7AwAPAAkJ0iQgAwA7AwAAAA==.Logres:BAAALgADCgEJAQAAAA==.Lokeira:BAACLgAFFH8TAAIUAAQJcRYaHwDZAAAUAAQJcRYaHwDZAAAuAAQKfy4AAhQACQn8Gk0LAIABABQACQn8Gk0LAIABAAAA.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn85AAIHAAkJMhTtUwDOAQAHAAkJMhTtUwDOAQAAAA==.Loonnah:BAAALgAECgIJAgAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgUJBgABLgAECgcJJAAWAE4TAA==.Lukian:BAABLgAFFH8IAAIgAAQJiQTZGwB+AAAgAAQJiQTZGwB+AAABLgAFFAQJEAAhAEIcAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Lupusregina:BAAALgAECgQJBAABLgAECgkJFQAmAOMdAA==.Luuniren:BAAALgADCgQJBAABLgAFFAMJBgALAMUHAA==.Luvbug:BAABLgAECn8YAAIMAAkJ7x59GAB2AgAMAAkJ7x59GAB2AgAAAA==.',
Ly='Lyais:BAAALgAECgMJAwAAAA==.Lyara:BAACLgAFFH8eAAMUAAgJTyT0CQArAgAUAAgJTyT0CQArAgAXAAQJRxhPIgASAQAuAAQKfyAAAxQACQnjI1AJAOICABQACAmEI1AJAOICABcABglgHP8/ADQBAAAA.Lyi:BAAALgAFFAEJAgAAAA==.Lynn:BAAALgADCgEJAQAAAA==.Lythos:BAACLgAFFH8HAAIgAAMJjwngLgCKAAAgAAMJjwngLgCKAAAuAAQKfxkAAiAACAmPE2obAHMBACAACAmPE2obAHMBAAAA.Lyu:BAAALgAFFAEJAQABLgAFFAgJHgAUAE8kAA==.Lyuu:BAABLgAFFH8GAAIWAAMJdxa2ggDSAAAWAAMJdxa2ggDSAAABLgAFFAgJHgAUAE8kAA==.',
['Lø']='Lørdøfßud:BAACLgAFFH8MAAMPAAQJNxqGDABMAQAPAAQJxBeGDABMAQAaAAIJIhi4FQCgAAAuAAQKfzQAAw8ACQkYIyIHAOwCAA8ACQm4ISIHAOwCABoABwkSI3ILADECAAAA.',
Ma='Macguffin:BAAALgAECgEJAQAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJHQAOAIYLAA==.Maeve:BAAALgADCggJCAAAAA==.Makimá:BAAALgAECgEJAQABLgAECgkJHwAMAMUVAA==.Makinnor:BAAALgAECgEJAgAAAA==.Maklovin:BAAALgAECgEJAwAAAA==.Malifae:BAABLgAECn8bAAIfAAcJYSGbEwB3AgAfAAcJYSGbEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwAfAGEhAA==.Malzeno:BAAALgAECgQJBQAAAA==.Mankilla:BAAALgAECgQJBwAAAA==.Mansa:BAACLgAFFH8HAAInAAMJTgffCADDAAAnAAMJTgffCADDAAAuAAQKfzkAAicACQnFGpsDAHMCACcACQnFGpsDAHMCAAAA.Mastamojo:BAABLgAECn89AAIJAAkJUAnlNwBuAQAJAAkJUAnlNwBuAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Mavis:BAAALgAECgIJAgAAAA==.Maîev:BAAALgAECgUJBwAAAA==.',
Mc='Mcmurphy:BAAALgAECggJEQAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Meanieman:BAAALgADCgEJAgAAAA==.Mechadragon:BAAALgADCgYJDwAAAA==.Medivac:BAAALgAECgEJAQAAAA==.Medved:BAAALgAECgEJAgABLgAFFAEJAQACAAAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAACLgAFFH8HAAIiAAIJTggjEQCHAAAiAAIJTggjEQCHAAAuAAQKfy8AAyIACQmbFzoHAAACACIACQmMFzoHAAACABIABwmpE04QAD0BAAAA.Melendaren:BAAALgAECgYJDAAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgAECgQJCAAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAFFAEJAQAAAA==.Meowkug:BAAALgAECgEJAgAAAA==.Merscy:BAABLgAECn8bAAIcAAgJngqyOQASAQAcAAgJngqyOQASAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAABLgAECn81AAMfAAkJUhlQBwBdAQAfAAkJUhlQBwBdAQAEAAYJ1gs3awDzAAABLgAECgkJNgAcAE4XAA==.Metamonster:BAABLgAECn8yAAMgAAkJ4A8+BgBLAQAGAAkJCgikeQBwAQAgAAgJJRE+BgBLAQAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikaels:BAAALgAECgcJCQABLgAECgkJQQAOAHMcAA==.Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgcJEwAAAA==.Mirko:BAABLgAECn8dAAIOAAcJhgtsjAAHAQAOAAcJhgtsjAAHAQAAAA==.Mistiah:BAABLgAFFH8JAAIGAAMJQyATdwAVAQAGAAMJQyATdwAVAQAAAA==.Mistyjoe:BAAALgAECgEJAQAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn9yAAIeAAkJkx5fAACuAgAeAAkJkx5fAACuAgAAAA==.Mokokniki:BAAALgAECgcJCQAAAA==.Moneie:BAAALgAECgUJDAAAAA==.Monger:BAAALgAECgEJAQAAAA==.Mongò:BAAALgAECgQJBwAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAFFAMJCAAXAKwQAA==.Moondo:BAAALgAECgcJDgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Mooseymancer:BAAALgADCgcJDQAAAA==.Mootron:BAAALgADCgYJCgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mortimus:BAAALgAECgMJAwAAAA==.Mourningstar:BAACLgAFFH8bAAMGAAUJxiVkMACmAQAGAAQJxiVkMACmAQAgAAIJhwiXLQAfAAAuAAQKfygAAwYACQknJPcYALECAAYACQknJPcYALECACAAAwmqFicTAF0AAAEuAAUUCQknAAYAgBgA.Mozaic:BAABLgAECn9sAAIbAAkJWB81AQCkAgAbAAkJWB81AQCkAgAAAA==.',
Mu='Mugrüíth:BAAALgAECgYJEAAAAA==.Munich:BAAALgADCgUJBQAAAA==.Muyoang:BAAALgADCgEJAQABLgAECgkJMwAEABMfAA==.',
My='Myfeethurt:BAAALgAECgQJBQABLgAFFAQJDAAPADcaAA==.Mymoon:BAAALgADCgMJAwAAAA==.Myragê:BAAALgADCgkJDQABLgAECgEJAQACAAAAAA==.Myselia:BAABLgAECn8kAAINAAkJBhXAEgACAgANAAkJBhXAEgACAgAAAA==.Mystra:BAAALgAECgcJEAAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgAECgEJAQAAAA==.Naek:BAAALgAECgYJEwAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgYJEwACAAAAAA==.Nalthis:BAAALgAECgYJAwAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nathar:BAAALgADCgMJAwABLgAFFAQJDAAPADcaAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAABLgAECn86AAIWAAkJlRczEQBYAQAWAAkJlRczEQBYAQAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nicehair:BAAALgAECgcJCAABLgAECgYJCgACAAAAAA==.Nichtaire:BAABLgAECn8ZAAIOAAgJvQk+hgATAQAOAAgJvQk+hgATAQAAAA==.Niem:BAABLgAECn8dAAIhAAkJhSVFAQBOAwAhAAkJhSVFAQBOAwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.Nimh:BAAALgAECgQJBAAAAA==.Nirvanna:BAAALgADCgQJBAAAAA==.Nitsi:BAAALgAECgEJAQABLgAECgkJNQAdAKAaAA==.',
No='Nocturnum:BAABLgAECn9BAAIOAAkJcxw3GACEAgAOAAkJcxw3GACEAgAAAA==.Nostalgic:BAAALgADCgcJBwAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8KAAIiAAUJQRdPAABcAQAiAAUJQRdPAABcAQAuAAQKfxwAAiIACAktHi8BAPECACIACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Oc='Occultist:BAAALgADCgMJAwAAAA==.',
Od='Odahviing:BAAALgADCgQJBAABLgAFFAMJAwACAAAAAA==.Odin:BAAALgAECgEJAgAAAA==.Odium:BAAALgADCgMJAwABLgAFFAUJEgAMAFchAA==.',
Oh='Oha:BAAALgAECgcJCgAAAA==.Ohuln:BAAALgADCgcJCAABLgAFFAkJHAAZAJoeAA==.',
Ol='Oldage:BAABLgAECn8WAAMEAAkJkhMJBAD8AQAEAAkJkhMJBAD8AQAfAAQJbAMJIwA/AAABLgAFFAMJBgAFABIOAA==.Oldmage:BAAALgAECgYJCAAAAA==.Oldmongerpal:BAAALgAECgEJAgAAAA==.Oltiyet:BAAALgAECgMJBQABLgAFFAMJBgALAMUHAA==.',
On='Onepuffman:BAAALgAECgEJAgABLgAFFAkJIwALANwWAA==.Onetwocowpow:BAABLgAECn9IAAIDAAkJ+hhqFQBuAgADAAkJ+hhqFQBuAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn9ZAAMHAAkJViJwDwATAwAHAAkJViJwDwATAwAIAAkJTBelCQA0AgAAAA==.Orionn:BAACLgAFFH8YAAIMAAUJRSC0CQAUAQAMAAUJRSC0CQAUAQAuAAQKf0oAAgwACQm2JcgEAEQDAAwACQm2JcgEAEQDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAABLgAECn8dAAIMAAkJWw5oSgDCAQAMAAkJWw5oSgDCAQAAAA==.',
Ov='Oven:BAABLgAECn8gAAIVAAgJVxYLIgCfAQAVAAgJVxYLIgCfAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.Patelz:BAAALgADCgQJBAAAAA==.',
Pe='Petoria:BAAALgADCgUJBQAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pinksparkle:BAAALgAECgkJCQAAAA==.Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQABLgAECgkJDwACAAAAAA==.Polyeikon:BAAALgAECgYJCwAAAA==.Polytotems:BAAALgAECgIJAgAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgAECgQJBwAAAA==.Prayr:BAAALgAECgYJDQAAAA==.Praystation:BAAALgAECgUJCwAAAA==.Problem:BAAALgAECgQJBAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgYJCwAAAA==.Quick:BAAALgAFFAEJAQAAAA==.',
Ra='Raekeshh:BAABLgAECn8ZAAITAAkJ3BWcNAAGAgATAAkJ3BWcNAAGAgAAAA==.Raelone:BAABLgAECn8dAAQSAAkJGBGtIwCUAAATAAUJYg3LqgDtAAASAAYJZBKtIwCUAAAiAAEJ5RNGNwBHAAAAAA==.Rageofmommy:BAAALgAECgMJBAAAAA==.Raidoe:BAABLgAECn9LAAMDAAkJKRz/DwClAgADAAkJKRz/DwClAgAVAAMJOQsIdQBmAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn86AAIMAAkJfRswDQCeAQAMAAkJfRswDQCeAQAAAA==.Rant:BAAALgAECgYJCwAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.Razorbeams:BAAALgAECgQJBQABLgAECgkJcgAeAJMeAA==.',
Re='Redishpanda:BAAALgADCgcJFAAAAA==.Redshammy:BAAALgAFFAIJAwAAAA==.Relion:BAABLgAECn8fAAIWAAkJqQkIFgAqAQAWAAkJqQkIFgAqAQABLgAECgkJTQAHANkSAA==.Reo:BAAALgAFFAEJAQABLgAFFAYJIQADACUgAA==.Reverse:BAAALgAECgEJAQAAAA==.',
Rh='Rheaven:BAAALgADCgEJAQAAAA==.Rheavin:BAAALgAECgcJAQAAAA==.Rhell:BAACLgAFFH8OAAIJAAQJqhPIKADeAAAJAAQJqhPIKADeAAAuAAQKfz0AAwkACQk2ImsIAAUDAAkACQk2ImsIAAUDAAcAAQkUAvXRARYAAAAA.',
Ri='Rinche:BAABLgAECn9FAAMXAAkJNxa/GwADAgAXAAkJNxa/GwADAgAUAAkJ3guyUgBoAQAAAA==.Rintche:BAAALgAECgUJBQAAAA==.Rivers:BAAALgAFFAMJAwABLgAFFAMJBgAFABIOAA==.',
Ro='Rolland:BAABLgAECn8lAAIZAAkJeyD9AQDoAgAZAAkJeyD9AQDoAgAAAA==.Rollf:BAAALgAECgMJAwAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAABLgAECn8hAAMTAAkJOAvmWgCNAQATAAkJOAvmWgCNAQASAAQJ1wTVKQBuAAAAAA==.',
Ru='Rubèus:BAAALgAECgEJAQAAAA==.Rudo:BAABLgAECn8fAAMMAAkJxRVZIgA3AgAMAAkJxRVZIgA3AgAYAAEJrgLYagAnAAAAAA==.Rumproblem:BAABLgAECn9SAAMKAAkJQxk6DwB7AgAKAAkJQxk6DwB7AgALAAkJoBhyAgBFAgAAAA==.Runekaiser:BAAALgAECgMJDgAAAA==.Runnamuuk:BAABLgAECn82AAIOAAkJGBTzNgDqAQAOAAkJGBTzNgDqAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryegar:BAAALgAECggJDgAAAA==.Ryeger:BAABLgAECn9iAAMjAAkJDSNZAgAGAwAjAAkJDSNZAgAGAwAfAAMJpgs0ZgCFAAAAAA==.',
['Rá']='Ráh:BAAALgADCgEJAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn84AAIhAAkJ8hdXEQDXAQAhAAkJ8hdXEQDXAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBQABLgAECgMJDQACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samonkvarius:BAAALgAECgMJAwABLgAECgkJTQAHANkSAA==.Samovar:BAABLgAECn9NAAMHAAkJ2RIHCwC5AQAHAAkJ2RIHCwC5AQAJAAkJRQUMRQAsAQAAAA==.Samovaro:BAAALgAECgEJAQAAAA==.Sandbones:BAAALgAECgcJEwABLgAECgkJcgAeAJMeAA==.Sandraice:BAABLgAECn8fAAIHAAgJ0QYyhwBsAQAHAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sanielan:BAAALgAECgYJCwAAAA==.Sansami:BAABLgAECn9DAAIdAAkJsxwIFwDxAQAdAAkJsxwIFwDxAQAAAA==.Saphron:BAAALgAECgQJBAAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAABLgAECn8uAAMfAAcJRQpmFACSAAAfAAcJRQpmFACSAAAEAAUJDQMlqwBfAAAAAA==.',
Sc='Sc:BAAALgAECgcJCgABLgAECgkJKgAWAE4jAA==.Scalebagz:BAABLgAECn8gAAMkAAkJSB4WBgCoAgAkAAkJSB4WBgCoAgAQAAgJvRyYIADUAQAAAA==.Schism:BAAALgAECgEJAQAAAA==.Schitzøø:BAAALgAECgEJAgAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgAECgQJBAAAAA==.Senyorseven:BAAALgAECgYJDgAAAA==.Seo:BAAALgAECgQJCQAAAA==.Serabeara:BAAALgAECgIJAgAAAA==.Setresh:BAABLgAECn9ZAAIYAAkJwhUcEwAOAgAYAAkJwhUcEwAOAgAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadowcloak:BAAALgAECgUJBQAAAA==.Shadöwsöng:BAACLgAFFH8JAAIbAAMJKAVxFwBnAAAbAAMJKAVxFwBnAAAuAAQKf0AAAhsACAneC4whACMBABsACAneC4whACMBAAAA.Shaedelana:BAABLgAECn8gAAQcAAkJmBqNDADWAAAKAAUJShOcPAAcAQAcAAcJRhuNDADWAAALAAYJKBRxEADBAAAAAA==.Shamaned:BAAALgAECgEJAQAAAA==.Shamrox:BAABLgAECn8WAAIXAAgJvQraEADEAAAXAAgJvQraEADEAAAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJMwAEABMfAA==.Sharatira:BAAALgAECgUJBQAAAA==.Shinnobi:BAAALgAECgcJBwAAAA==.Shinygoat:BAAALgADCgIJAgABLgAECgkJKgARAI8fAA==.Shivver:BAAALgAECgIJAgAAAA==.Shivyn:BAACLgAFFH8PAAIUAAQJUxVcGgD6AAAUAAQJUxVcGgD6AAAuAAQKfz8AAxQACQlMGs4PANMCABQACQlMGs4PANMCABcAAQkXBbmNACoAAAAA.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAkJHAAZAJoeAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAACLgAFFH8UAAMGAAMJ+Re1QADdAAAGAAMJ+Re1QADdAAAgAAIJrwtwNABnAAAuAAQKfy4AAwYACQmlGVFIAOkBAAYACQmlGVFIAOkBACAABQmtD1UuAMwAAAAA.Sickkid:BAACLgAFFH8GAAIPAAIJLSIyHQDBAAAPAAIJLSIyHQDBAAAuAAQKf0wAAg8ACQmhIqwJAMgCAA8ACQmhIqwJAMgCAAAA.Siegekaiser:BAAALgADCgcJEwAAAA==.Silkiegirl:BAABLgAECn8iAAIPAAkJzhQeGgAdAgAPAAkJzhQeGgAdAgAAAA==.Silvador:BAAALgAFFAEJAQABLgAFFAIJBgAQAFYCAA==.Silvershine:BAABLgAECn8VAAMEAAYJ6w4lgADaAAAEAAUJiAslgADaAAAjAAQJuAYsNwB/AAAAAA==.Silverwolf:BAAALgAECgIJAgAAAA==.Sindrya:BAAALgAECgUJBwAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slayne:BAAALgAECgEJAQAAAA==.Slaänesh:BAAALgADCgcJBwABLgAECgkJMwAEABMfAA==.Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJDAACAAAAAA==.Smashßros:BAAALgAECgQJBAABLgAFFAQJDAAPADcaAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAABLgAECn8VAAImAAcJ4x3HAwBoAQAmAAcJ4x3HAwBoAQAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgABLgAFFAMJCQAGAEMgAA==.Snooker:BAAALgAECgIJAgAAAA==.Snuggles:BAABLgAECn8mAAINAAgJjxoCEwD/AQANAAgJjxoCEwD/AQABLgAFFAYJHQAYAHcUAA==.',
So='Solaire:BAAALgAECgEJAgABLgAECgkJDwACAAAAAA==.Solidgen:BAEALgAECgEJAgABLgAFFAgJHgAHACYPAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Solárz:BAAALgAECgYJBgAAAA==.Sonofalich:BAAALgAECgkJCQAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAABLgAECn8WAAMbAAgJNRa8FwCDAQAbAAgJNRa8FwCDAQAaAAMJUgOpNABeAAAAAA==.Spinach:BAAALgAECgEJAQAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgQJDgAAAA==.',
Ss='Ssraeshza:BAABLgAFFH8NAAIhAAcJbRi0CABoAQAhAAcJbRi0CABoAQAAAA==.',
St='Staretra:BAABLgAECn9BAAMLAAkJOBILHQDcAQALAAkJOBILHQDcAQAcAAQJowboUwCNAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.Stockade:BAAALgAECgEJAQAAAA==.Strikerblack:BAAALgAECgQJDQAAAA==.Stusey:BAAALgADCgIJAgAAAA==.',
Su='Sublevels:BAAALgADCgYJBgAAAA==.Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECggJEQAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Superdestror:BAAALgAECgMJAwAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Sylph:BAAALgAECgUJBgAAAA==.Symana:BAABLgAECn85AAIcAAkJKB5bCwCxAgAcAAkJKB5bCwCxAgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgAECgEJAQAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgcJEQAAAA==.',
['Sö']='Sörceress:BAAALgAECgYJEwAAAA==.',
Ta='Taadra:BAABLgAECn9uAAIUAAkJtSElAgDgAgAUAAkJtSElAgDgAgAAAA==.Talerah:BAAALgAECgUJCQAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAACLgAFFH8mAAMEAAcJqhntCADDAQAEAAcJqhntCADDAQAfAAEJfAPCNAAnAAAuAAQKfxgAAwQACQnvF2YeAEwCAAQACQnvF2YeAEwCACEAAgkPE1ZOAHMAAAAA.Talona:BAAALgAFFAEJAQABLgAFFAUJCgAiAEEXAA==.Tandaan:BAAALgADCgkJCgABLgAECgkJGQATANwVAA==.Tanjent:BAABLgAECn8kAAIMAAcJfwxcKAC3AAAMAAcJfwxcKAC3AAAAAA==.Tanok:BAAALgADCgYJBgAAAA==.Tapio:BAABLgAECn84AAIYAAkJ5RkwAwCNAQAYAAkJ5RkwAwCNAQAAAA==.Tatsuma:BAAALgAECgYJDgABLgAECgkJJQAHAPobAA==.Tatsumå:BAAALgAECgcJEgABLgAECgkJJQAHAPobAA==.Tavv:BAAALgADCgMJAwAAAA==.Tavvi:BAAALgAECgYJBgABLgAECgkJGAAMAO8eAA==.Tazz:BAAALgAECgIJAgAAAA==.',
Te='Terp:BAAALgAECgMJBwAAAA==.',
Th='Thalfinore:BAAALgAECgcJEgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Therogue:BAAALgAECgIJAgAAAA==.Thoghar:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.Thorincan:BAAALgAECgkJCQAAAA==.Thorrs:BAAALgAECgIJBwAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thorwar:BAAALgADCgMJBAAAAA==.Thuglifé:BAAALgAECgEJAQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECggJDAACAAAAAA==.Tidemaiden:BAABLgAECn8jAAMUAAgJ7BH1DQBOAQAUAAcJGw/1DQBOAQAmAAMJNAdkDgBoAAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgABLgAFFAMJAwACAAAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tinypickles:BAAALgAECgQJBAAAAA==.Tipsymancer:BAABLgAECn9IAAIdAAkJDSLwAwAOAwAdAAkJDSLwAwAOAwAAAA==.Tirael:BAAALgAECgYJBQABLgAFFAYJAQACAAAAAA==.Tishi:BAAALgAECgIJAwAAAA==.',
To='Tolduso:BAAALgAECgIJAgAAAA==.Tomö:BAAALgAECgkJBAAAAA==.Tossme:BAAALgAECgEJAQABLgAFFAYJFwAdAFIfAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Traeicel:BAAALgAECggJCQAAAA==.Treesus:BAABLgAECn8fAAIfAAkJLhqWGwAmAgAfAAkJLhqWGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECgkJHwAMAMUVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Ts='Tsu:BAAALgADCgkJCQAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.Tyzi:BAAALgAECgEJAQAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQWAAgJ+iNmNwA7AgAWAAgJXCFmNwA7AgAeAAMJPCQECAAkAQAoAAEJTQ0VDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8lAAIEAAkJsRiVIgA0AgAEAAkJsRiVIgA0AgAAAA==.',
Un='Undeadgnome:BAAALgAECgMJAwAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.Usër:BAAALgAECgQJBwAAAA==.',
Va='Vainin:BAABLgAECn8VAAIWAAYJsgcL5ADVAAAWAAYJsgcL5ADVAAAAAA==.Valle:BAAALgAFFAEJAQAAAA==.Valry:BAAALgAECgYJDgAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAQJEAAhAEIcAA==.Vankro:BAAALgAFFAEJAgABLgAFFAUJHgAKAKQfAA==.Variable:BAAALgAECgcJBwAAAA==.Varser:BAAALgAECgYJCwAAAA==.Vashdin:BAABLgAECn81AAIHAAkJLx7ODACaAQAHAAkJLx7ODACaAQAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECgkJHwAMAMUVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velaronia:BAAALgAECgYJCwAAAA==.Velashis:BAABLgAECn9LAAMEAAkJnCB1AQDlAgAEAAkJnCB1AQDlAgAfAAQJLw6feABVAAAAAA==.Velathadora:BAAALgAECgEJAQAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAABLgAFFH8IAAIXAAMJrBDJNQC3AAAXAAMJrBDJNQC3AAAAAA==.Vett:BAAALgADCgMJAwABLgAECgYJFQAWALIHAA==.Vexable:BAAALgAECgQJBAAAAA==.',
Vi='Viable:BAAALgAECgUJCgAAAA==.Vibes:BAAALgAECgkJCwAAAA==.Victoriá:BAAALgAECgEJAQAAAA==.Victorvega:BAAALgAECgMJAwABLgAECgkJHwAMAMUVAA==.Vicvega:BAAALgAECgQJBQABLgAECgkJHwAMAMUVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8RAAMDAAMJtRIWPAC1AAADAAMJtRIWPAC1AAAVAAIJ0h3FFwBrAAAuAAQKfyYAAxUACQndHRcQAH8CABUACAmuHRcQAH8CAAMABQnvH+lUAB0BAAAA.Vivila:BAABLgAECn8cAAIPAAkJHh2pAQCtAgAPAAkJHh2pAQCtAgABLgAECgkJSAAOAPwbAA==.Vivillian:BAABLgAFFH8HAAIKAAMJjg98MwC+AAAKAAMJjg98MwC+AAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Voidrèaper:BAAALgAECgEJAQAAAA==.Volstak:BAAALgADCgQJBAAAAA==.Vordilina:BAABLgAECn8cAAQoAAkJqhgPAgBYAgAoAAkJqhgPAgBYAgAeAAEJuAV9IAAtAAAWAAEJrQHbiAEcAAAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQkAAgJKhn4EwAGAgAkAAgJKhn4EwAGAgAlAAQJxRh7FQC6AAAQAAEJygMInQAkAAAAAA==.',
Vu='Vugilist:BAAALgAECgEJAQAAAA==.Vuginhood:BAAALgADCgEJAgAAAA==.Vugnacious:BAAALgAECgcJBwAAAA==.Vugnus:BAABLgAECn9FAAMUAAkJEhvKNADeAQAUAAgJlhnKNADeAQAXAAkJIBlrCQA6AQAAAA==.Vugowulf:BAAALgAECgEJAwAAAA==.',
Vy='Vynae:BAAALgADCgcJBAAAAA==.',
['Vé']='Véxx:BAABLgAECn82AAQRAAkJ5R7cBABnAgARAAkJ5R7cBABnAgANAAUJYAizQgDtAAAOAAEJdAGj9QAZAAAAAA==.',
['Vì']='Vìx:BAAALgAECgEJAQAAAA==.',
['Ví']='Víx:BAAALgAECggJCAAAAA==.',
['Vî']='Vîper:BAAALgAFFAEJAQAAAA==.',
['Vï']='Vïx:BAAALgADCgUJBQAAAA==.',
Wa='Wadewilson:BAABLgAECn8UAAIMAAgJERJWDQCbAQAMAAgJERJWDQCbAQAAAA==.Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAwACAAAAAA==.Warihor:BAABLgAECn8vAAMaAAgJeQyTMAAGAQAPAAgJIwq1QABCAQAaAAgJhQmTMAAGAQAAAA==.Waycaps:BAABLgAFFH8FAAIhAAQJUBUQEAAIAQAhAAQJUBUQEAAIAQAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAACLgAFFH8UAAIiAAUJbiTjAQCjAQAiAAUJbiTjAQCjAQAuAAQKfzEAAiIACQltJMAAACEDACIACQltJMAAACEDAAAA.',
Wh='Whïte:BAAALgAECgEJAgAAAA==.',
Wi='Wiegraf:BAAALgAECgIJAwABLgAECgkJMwAEABMfAA==.Wife:BAAALgAECgMJAwAAAA==.Wildhide:BAAALgAECgcJCAAAAA==.Withers:BAAALgADCgQJBAAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJDQAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECggJDAAAAA==.',
['Wä']='Wärbëef:BAAALgADCgEJAQAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECggJDAACAAAAAA==.',
Xo='Xorxel:BAAALgAECgQJCAAAAA==.',
Ya='Yacob:BAABLgAECn88AAMcAAkJOx0jCgDFAgAcAAkJOx0jCgDFAgALAAYJFRypBQCUAQAAAA==.Yacobge:BAAALgAECgYJBgAAAA==.',
Ye='Yenneferr:BAAALgAECgkJAQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8zAAIEAAkJEx+HCwAGAwAEAAkJEx+HCwAGAwAAAA==.',
Yh='Yhwach:BAACLgAFFH8MAAIgAAYJZA13JADLAAAgAAYJZA13JADLAAAuAAQKfy4AAiAACAmfGjkEAK8BACAACAmfGjkEAK8BAAAA.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAABLgAFFH8MAAIHAAQJGBNWLQDWAAAHAAQJGBNWLQDWAAABLgAFFAMJBgAFABIOAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECggJDAAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgcJCwAAAA==.',
Za='Zabrajin:BAAALgAECgEJAQAAAA==.Zaeden:BAABLgAECn8dAAIDAAcJDh+fFgANAgADAAcJDh+fFgANAgAAAA==.Zaft:BAAALgADCgYJBgAAAA==.Zaftdh:BAABLgAECn81AAIOAAkJqhVXNAD1AQAOAAkJqhVXNAD1AQAAAA==.Zaha:BAABLgAECn8eAAIWAAYJ2iKdXAAkAgAWAAYJ2iKdXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zappsz:BAAALgAECggJDwAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zedfrey:BAABLgAECn9HAAIHAAkJ3hlBMQA7AgAHAAkJ3hlBMQA7AgAAAA==.Zedra:BAAALgAECgMJAwAAAA==.Zem:BAABLgAECn8rAAIPAAgJux8tEgBiAgAPAAgJux8tEgBiAgAAAA==.Zemagoose:BAAALgAECgEJAgAAAA==.Zemangoose:BAAALgAECgYJBgAAAA==.Zeroultra:BAABLgAECn8+AAIPAAkJth7PEQBmAgAPAAkJth7PEQBmAgAAAA==.Zeräse:BAABLgAECn8VAAIKAAgJRw//JACnAQAKAAgJRw//JACnAQABLgAECgkJMwAEABMfAA==.Zeusdh:BAAALgAECgIJAgAAAA==.Zeusmos:BAABLgAECn9GAAIVAAkJ3iY4AACVAwAVAAkJ3iY4AACVAwAAAA==.',
Zi='Zithenex:BAABLgAECn9GAAIlAAkJ3RfrAQBTAQAlAAkJ3RfrAQBTAQAAAA==.',
Zo='Zoeÿ:BAAALgAECgEJBAAAAA==.',
Zu='Zugnugs:BAAALgAECgMJAQAAAA==.',
Zw='Zwar:BAAALgAECgIJAgAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAABLgAECn9EAAIPAAkJPBaPAwACAgAPAAkJPBaPAwACAgAAAA==.',
['Ér']='Éragon:BAAALgAECgYJEwAAAA==.',
['ßo']='ßoru:BAAALgAECgEJAQABLgAECgIJAgACAAAAAA==.',
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
