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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Priest-Discipline','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Warrior-Fury','Shaman-Elemental','Hunter-Survival','Hunter-Marksmanship','Warrior-Arms','Warrior-Protection','Priest-Holy','Monk-Brewmaster','Mage-Arcane','Druid-Balance','DeathKnight-Blood','Druid-Guardian','Warlock-Affliction','Druid-Feral','Evoker-Preservation','Evoker-Devastation','Shaman-Enhancement','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aaminae:BAABLgAECn8+AAIBAAkJkxgpDQBUAgABAAkJkxgpDQBUAgAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgUJCwAAAA==.Abracastabya:BAAALgAFFAEJAQAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.Absolution:BAAALgAECgQJBQAAAA==.Abÿss:BAAALgAECgYJBgAAAA==.',
Ad='Adachï:BAABLgAECn8WAAIDAAYJiRpuNQCfAQADAAYJiRpuNQCfAQABLgAECgkJMwAEABMfAA==.Adevil:BAAALgAECgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aegon:BAAALgAECgUJBQAAAA==.Aethlin:BAABLgAECn86AAMFAAkJ6xzKMgA1AgAFAAkJjRnKMgA1AgAGAAgJhh1UCwASAgAAAA==.Aetreyu:BAAALgAECgcJEgAAAA==.Aeturnas:BAABLgAECn81AAIHAAkJ7B+jCAABAwAHAAkJ7B+jCAABAwAAAA==.',
Ag='Aggros:BAAALgAECgYJBgAAAA==.Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanima:BAABLgAECn8dAAMIAAgJjQzuKgB+AQAIAAgJjQzuKgB+AQAJAAYJ3AbYUQDKAAAAAA==.Albus:BAAALgAECgEJAgAAAA==.Aldky:BAAALgAECgEJAQAAAA==.Aliana:BAAALgAFFAEJAQAAAA==.Alinthe:BAAALgADCgkJCQAAAA==.Allindis:BAAALgAECgYJCQABLgAECgkJJQAEALEYAA==.Allypally:BAAALgAECgEJAwAAAA==.Alphamage:BAAALgADCggJCAAAAA==.Alphamonk:BAAALgAECgkJEQAAAA==.Alros:BAABLgAECn9XAAIKAAkJzyP3AAAiAwAKAAkJzyP3AAAiAwAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgAECgQJCAAAAA==.',
Am='Amardyton:BAAALgAECgYJBwAAAA==.',
An='And:BAABLgAECn8sAAMLAAgJYhT3BgDyAAALAAgJYhT3BgDyAAAMAAEJ6QOdOAEcAAAAAA==.Aneas:BAAALgAECgcJEQAAAA==.Antäres:BAAALgADCgQJBAABLgAECgkJMwAEABMfAA==.',
Ap='Apolex:BAAALgADCgUJBQAAAA==.Appela:BAAALgAECgEJAgAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgMJAwACAAAAAA==.Arette:BAAALgAECgcJCwAAAA==.Arkades:BAABLgAECn8iAAIFAAkJpx1kIwB4AgAFAAkJpx1kIwB4AgAAAA==.Arkshade:BAABLgAECn87AAINAAkJBxDefgBmAQANAAkJBxDefgBmAQAAAA==.Arlia:BAAALgAECgkJEQABLgAFFAIJBgAOAFYCAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECgkJKgAPAI8fAA==.Aryn:BAAALgAECgEJAQAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgcJEAACAAAAAA==.Ashor:BAAALgAECgIJAgAAAA==.Ashrodite:BAAALgADCgYJAgABLgAECgcJEAACAAAAAA==.Asmo:BAAALgADCggJGAAAAA==.Aspir:BAEALgAECgYJBgABLgAFFAgJGQAQAIATAA==.Astarii:BAAALgAECgEJBQAAAA==.Asterica:BAABLgAECn9ZAAMRAAkJ+xgSAQDQAQASAAkJWBi6MQARAgARAAgJnRYSAQDQAQAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.Atormunster:BAAALgADCgMJAwABLgAFFAIJBQAKAJwGAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAITAAYJ+A16UwA4AQATAAYJ+A16UwA4AQAAAA==.',
Av='Averynicole:BAABLgAECn8ZAAIUAAcJBxYLLABfAQAUAAcJBxYLLABfAQAAAA==.',
Aw='Awasjr:BAABLgAECn8mAAIKAAkJlh/GGACSAgAKAAkJlh/GGACSAgAAAA==.Awassy:BAAALgAECgEJAgAAAA==.',
Ay='Ayano:BAACLgAFFH8HAAIVAAEJBR/UWwBFAAAVAAEJBR/UWwBFAAAuAAQKfxYAAhUACAliHrFKAPsBABUACAliHrFKAPsBAAAA.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balanla:BAAALgAECgcJCAABLgAFFAMJBgAWAGgRAA==.Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDwABLgAECgkJMwAEABMfAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgAECgEJAQAAAA==.Bearhug:BAACLgAFFH8HAAMDAAMJAAiGUgBfAAADAAMJAAiGUgBfAAAUAAEJoAHDSgApAAAuAAQKfy8AAwMACAn1Gnc8AH4BAAMABwntGXc8AH4BABQABwleCYFCAA0BAAEuAAUUBAkOABcA6gwA.Bearshock:BAACLgAFFH8OAAMXAAQJ6gxGLQDfAAAXAAQJ6gxGLQDfAAATAAEJTACOjwAdAAAuAAQKfx4AAhcACAneHZEUAEYCABcACAneHZEUAEYCAAAA.Beasty:BAACLgAFFH8FAAMKAAIJnAbBQACDAAAKAAIJnAbBQACDAAAYAAIJUAGJLgBnAAAuAAQKfyUAAxkACAkeEK8RAEABABkACAkeEK8RAEABABgABgmHBPI9ANQAAAAA.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAACLgAFFH8FAAIFAAEJoSVbQwBwAAAFAAEJoSVbQwBwAAAuAAQKfzcAAgYACQnkJPYAAFQDAAYACQnkJPYAAFQDAAAA.Beeb:BAAALgAECgUJDgABLgAFFAEJBQAFAKElAA==.Beefisting:BAAALgAECgYJDAABLgAFFAEJBQAFAKElAA==.Beethicc:BAAALgAECgEJBAABLgAFFAEJBQAFAKElAA==.Beeuwu:BAAALgAECgIJAwABLgAFFAEJBQAFAKElAA==.Beliara:BAAALgAECgkJDQAAAA==.Belijoe:BAAALgAECgEJAQAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Belshuntress:BAAALgAECgEJAgAAAA==.Beverage:BAAALgAECgQJBQAAAA==.',
Bi='Bicboi:BAAALgAECgEJAQAAAA==.Bigmattyl:BAAALgAECgcJCgAAAA==.Bionarra:BAABLgAECn88AAIVAAkJrR2MAwBbAgAVAAkJrR2MAwBbAgAAAA==.Bishopwr:BAABLgAECn8pAAMaAAkJvBdQDAAiAgAaAAkJvBdQDAAiAgAbAAYJCwohMwCvAAAAAA==.Bittertøfu:BAABLgAECn8eAAIXAAcJfQb/WQDWAAAXAAcJfQb/WQDWAAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJCgAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blessu:BAAALgAECgEJAgAAAA==.Blitê:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Bm='Bmpfrostie:BAABLgAECn8WAAIVAAcJcQ41yABYAQAVAAcJcQ41yABYAQAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECgkJNwAcADsdAA==.Bohica:BAAALgAECggJDgAAAA==.Bonetotem:BAAALgAECgEJAQABLgAECgkJRAAdALQUAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAABLgAFFAMJCQANAEMgAA==.',
Br='Brakug:BAABLgAECn8vAAMVAAkJHiMULgC5AgAVAAkJHiMULgC5AgAeAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAIJAwAAAA==.Brem:BAACLgAFFH8IAAIeAAMJiBnrAQD5AAAeAAMJiBnrAQD5AAAuAAQKfxsAAh4ACAmCHB4EABICAB4ACAmCHB4EABICAAAA.Bretagnesse:BAABLgAECn8UAAIfAAgJ2wXJRQD1AAAfAAgJ2wXJRQD1AAAAAA==.Briara:BAAALgAECgYJDwAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgAECgQJBgAAAA==.Broníx:BAAALgAECgEJBQAAAA==.Bropeep:BAACLgAFFH8HAAINAAMJDhutjgDtAAANAAMJDhutjgDtAAAuAAQKf1MAAw0ACQnZJT0EAF4DAA0ACQnZJT0EAF4DABAABAmdFKIcAOkAAAAA.Brotality:BAAALgADCgMJBAAAAA==.Brynhildr:BAAALgAECgcJDwABLgAFFAQJEQAdAJ4gAA==.',
Bu='Bullshott:BAABLgAECn8jAAIKAAkJrx1qHQB1AgAKAAkJrx1qHQB1AgAAAA==.Bum:BAABLgAECn8mAAMfAAkJsh/4BABRAwAfAAkJsh/4BABRAwAEAAEJ0xCM0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgAECgUJCQAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJEQAAAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBgAAAA==.',
['Bú']='Búll:BAAALgAECgEJAQAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAABLgAECn8cAAMNAAgJYxC9bgCHAQANAAgJ+g69bgCHAQAgAAYJdA1nMgDTAAABLgAECgkJRAAdALQUAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn80AAIFAAkJ2AgNjABZAQAFAAkJ2AgNjABZAQAAAA==.Carrots:BAABLgAECn8vAAIKAAkJCBWgSADIAQAKAAkJCBWgSADIAQAAAA==.Cartman:BAABLgAFFH8HAAIbAAQJSRfcEwAEAQAbAAQJSRfcEwAEAQABLgAFFAQJCgAhAAIcAA==.Cashmachine:BAABLgAECn8tAAIKAAkJAx8VGwCDAgAKAAkJAx8VGwCDAgAAAA==.Cashmoolah:BAAALgAECgUJBQAAAA==.Castorice:BAAALgAECgEJAQAAAA==.Catfight:BAABLgAECn9GAAIGAAkJ/xAGBQDxAAAGAAkJ/xAGBQDxAAAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMSAAkJdBhqLgBTAgASAAkJdBhqLgBTAgARAAEJAABoZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8SAAQKAAUJVyESNQBDAQAKAAUJMyASNQBDAQAZAAEJISI3IwBlAAAYAAEJzA98MgBIAAAuAAQKfxwABBkACAmLIsIYAGYCABkACAkjIcIYAGYCAAoABQlPHXFcAJABABgAAwkrGAlMAIUAAAAA.Cheesecake:BAABLgAECn82AAMRAAkJvBBADAB7AQARAAgJBRJADAB7AQAiAAUJhgu7BQC1AAAAAA==.Chelsie:BAAALgAECgYJCgABLgAFFAQJEQAdAJ4gAA==.Chihiko:BAAALgAECgMJAwAAAA==.Choks:BAABLgAECn87AAIWAAkJBQ59CAAEAQAWAAkJBQ59CAAEAQAAAA==.Chubbycat:BAABLgAECn8VAAMEAAcJLhmOPQCuAQAEAAcJLhmOPQCuAQAjAAUJYh35FwBTAQAAAA==.Chuggz:BAABLgAECn81AAIdAAkJoBpSDQBjAgAdAAkJoBpSDQBjAgAAAA==.Chéfboyrlee:BAACLgAFFH8iAAIJAAkJwRW0BQAjAgAJAAkJwRW0BQAjAgAuAAQKfzYAAgkACQn6IrkEAAwDAAkACQn6IrkEAAwDAAAA.',
Ci='Cizmac:BAAALgAECgYJDgAAAA==.',
Cm='Cmdrshepard:BAAALgADCgMJAwABLgAFFAIJBwAiAE4IAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgAECgQJBwAAAA==.Cownado:BAABLgAECn9EAAIdAAkJtBQnAwAyAQAdAAkJtBQnAwAyAQAAAA==.',
Cr='Crematorion:BAAALgAECgMJAwAAAA==.Crippin:BAAALgAECgEJAQAAAA==.Crouton:BAAALgADCgkJCgAAAA==.',
Ct='Ctrlaltchill:BAAALgADCgEJAQAAAA==.',
Cu='Cursedspirit:BAAALgAECgQJBwAAAA==.',
Cy='Cybelem:BAABLgAECn8tAAIXAAkJmB5ZEABwAgAXAAkJmB5ZEABwAgAAAA==.Cyfelen:BAABLgAECn8ZAAQRAAkJiB9oAQDWAgARAAkJiB9oAQDWAgAiAAQJLxmtHQDSAAASAAIJrw+H+AByAAAAAA==.Cynleel:BAAALgAECggJEAABLgAECgkJPwAIAD0UAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQAAAA==.Damonstyle:BAAALgAECgEJAgAAAA==.Dandistyle:BAABLgAECn8fAAMdAAkJdx1kCwB+AgAdAAkJbh1kCwB+AgAUAAEJchK2fAAzAAAAAA==.Darknature:BAAALgAECgkJCQAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Darthmall:BAAALgADCgMJAwABLgAFFAQJEQAdAJ4gAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathblade:BAAALgAECgEJAQAAAA==.Deathmatrynn:BAAALgAECgYJDgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAACLgAFFH8FAAIXAAIJ2gUkSwBnAAAXAAIJ2gUkSwBnAAAuAAQKfxUAAhcACAnaFl8eAO8BABcACAnaFl8eAO8BAAAA.Deeviant:BAAALgAECggJDgAAAA==.Defend:BAABLgAFFH8KAAIhAAQJAhyTBABCAQAhAAQJAhyTBABCAQAAAA==.Delrager:BAACLgAFFH8HAAIBAAIJch5vLwCtAAABAAIJch5vLwCtAAAuAAQKfygAAgEABwmYI3cNAFACAAEABwmYI3cNAFACAAAA.Delyta:BAAALgAECgkJCQAAAA==.Demidru:BAABLgAECn8YAAMhAAgJUBJEBABHAQAhAAcJ6xJEBABHAQAjAAgJDAZSBQDIAAAAAA==.Demonicdawn:BAAALgADCgEJAQAAAA==.Demónícz:BAAALgAECgMJAwAAAA==.Derat:BAAALgAECgkJEQAAAA==.Destroy:BAABLgAFFH8GAAISAAMJpQMGkwCcAAASAAMJpQMGkwCcAAABLgAFFAQJCgAhAAIcAA==.Deverux:BAAALgAECgEJAQAAAA==.',
Di='Dibbydab:BAABLgAECn8nAAITAAkJbRQWOgDGAQATAAkJbRQWOgDGAQAAAA==.',
Dj='Django:BAABLgAECn82AAMfAAkJsyIdBgD2AgAfAAkJsyIdBgD2AgAEAAIJkAbHxgA+AAAAAA==.Djatalon:BAABLgAECn8WAAMkAAUJuAsWIwDWAAAkAAUJuAsWIwDWAAAlAAMJrAUaHABsAAAAAA==.Djderpyderpy:BAAALgAECgYJDQAAAA==.Djehrtey:BAAALgAECggJEAAAAA==.Djin:BAAALgAECgMJBAABLgAFFAQJEQAdAJ4gAA==.Djinni:BAACLgAFFH8RAAIdAAQJniDAEwCFAQAdAAQJniDAEwCFAQAuAAQKfzUAAx0ACQk9IXkGANMCAB0ACAlsI3kGANMCABQACQkSG6gOAF4CAAAA.',
Dk='Dkota:BAAALgAECgUJBgAAAA==.',
Do='Dobath:BAAALgADCgQJBAAAAA==.Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8fAAMQAAgJtxtyCAAHAgAQAAgJtxtyCAAHAgANAAMJsA2A/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8YAAQkAAcJNxmADwDUAQAkAAcJNxmADwDUAQAOAAQJuwziYQC1AAAlAAEJAACAPAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Dragodeeps:BAAALgAECgQJBAABLgAFFAIJBQAXANoFAA==.Draknem:BAAALgAECgUJBwAAAA==.Dramaticus:BAAALgAECgQJBAAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drenleah:BAABLgAECn8XAAIRAAkJpRZ0BQAZAgARAAkJpRZ0BQAZAgABLgAECgkJSAAMAPwbAA==.Drenlee:BAAALgAECgEJAgABLgAECgkJSAAMAPwbAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgABLgAECgEJAQACAAAAAA==.Dryya:BAAALgAECgQJCAAAAA==.Drêck:BAAALgAECgEJAQAAAA==.',
Du='Dumblegear:BAABLgAECn8fAAMVAAgJpRVRbACiAQAVAAgJpRVRbACiAQAeAAEJbQY0IAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAFFAMJBgAWAGgRAA==.Durian:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.',
Dw='Dwagon:BAAALgADCgUJBQAAAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgAECgEJAQAAAA==.Dädärkbeëf:BAAALgADCgcJCQAAAA==.',
Ed='Edinna:BAABLgAECn9EAAMVAAkJMxwGAwCGAgAVAAkJMxwGAwCGAgAeAAQJTQoTEADBAAAAAA==.',
Ee='Eevie:BAAALgADCgMJBgAAAA==.',
Ei='Einekliene:BAAALgAECgcJBwAAAA==.',
Ek='Ekatrina:BAAALgAECgEJAQAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Eldernoc:BAABLgAECn8WAAIhAAgJzw8/BABIAQAhAAgJzw8/BABIAQAAAA==.Elessedil:BAAALgAECggJDgAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgYJDQAAAA==.Elucidäte:BAAALgAECgEJAQAAAA==.Elyriana:BAABLgAECn8jAAMEAAkJpSAKCQAoAwAEAAkJpSAKCQAoAwAjAAEJqSBoQQBZAAAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEBLgAECn8kAAIKAAYJPyIcCwBrAQAKAAYJPyIcCwBrAQABLgAECgkJLAAKANQgAA==.Emirozu:BAAALgADCgEJAQAAAA==.Emixi:BAAALgAECgQJBQAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECggJDwAAAA==.Emritelan:BAAALgAECgUJCAAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8YAAIFAAYJixdsJgBvAQAFAAYJixdsJgBvAQAuAAQKfzEAAgUACQmaHwIlAHACAAUACQmaHwIlAHACAAAA.',
Ep='Epedemik:BAAALgAECgcJCQAAAA==.',
Er='Erazath:BAAALgAECgUJBgABLgAFFAMJBwAgAI8JAA==.Eredo:BAAALgAECgUJCwABLgAFFAMJBgAWAGgRAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgAECgIJAgAAAA==.Erush:BAAALgAECgEJAQAAAA==.',
Es='Esha:BAAALgAECgEJAQAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ex='Exhul:BAAALgAECgEJAQAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Faewing:BAABLgAFFH8GAAIOAAIJVgKBXgBcAAAOAAIJVgKBXgBcAAAAAA==.Falar:BAAALgAECggJDQAAAA==.Fatelf:BAAALgADCgMJAwAAAA==.Fatowlbert:BAAALgAECgEJAgAAAA==.Faval:BAAALgAECggJDwABLgAECgkJKgAPAI8fAA==.Favel:BAABLgAECn8qAAMPAAkJjx9OAQAcAwAPAAgJ4iFOAQAcAwAMAAkJRwv4XwBpAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn9cAAIKAAkJBR3TAgCBAgAKAAkJBR3TAgCBAgAAAA==.Febz:BAABLgAECn8eAAIVAAgJbBsqMACyAgAVAAgJbBsqMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAABLgAECn8aAAIMAAgJZh/xIgBFAgAMAAgJZh/xIgBFAgAAAA==.Felfüry:BAACLgAFFH8LAAMLAAMJ8Qc6EgBtAAALAAMJ8Qc6EgBtAAAPAAMJxwNYEABOAAAuAAQKf0cABAsACQm/FEMTAPwBAAsACQm/FEMTAPwBAA8ACAmGCb4WAPEAAAwAAglYCZYGAUQAAAAA.Felly:BAAALgAECgYJBgAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Festicules:BAAALgAECgQJBAAAAA==.Festyr:BAAALgAECgQJCAAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECggJDAACAAAAAA==.Finella:BAABLgAECn8UAAMQAAkJJBipCAABAgAQAAkJjhOpCAABAgAgAAYJaxYLJgAjAQAAAA==.Finneas:BAAALgAECgEJBAABLgAECgkJIgAFAKcdAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJLwAVAB4jAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgkJFAAQACQYAA==.',
Fo='Fogassann:BAACLgAFFH8GAAINAAMJuxlOMADyAAANAAMJuxlOMADyAAAuAAQKfxkAAg0ACQmvHBUrAFQCAA0ACQmvHBUrAFQCAAEuAAUUAwkGABYAaBEA.Fogdemon:BAAALgAECgIJBAABLgAFFAUJGAAiAHMUAA==.Foggpy:BAACLgAFFH8YAAMiAAUJcxR+BQAvAQAiAAUJcxR+BQAvAQASAAQJnwOOcwDaAAAuAAQKfy4ABCIACQnxJGIAAHwCACIACQnxJGIAAHwCABIABgkNG8FXAMABABEABgljGQ4fAFgBAAAA.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freinkenbaby:BAAALgAECgEJAQAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostnuts:BAAALgAECgEJAQAAAA==.Frostybear:BAABLgAECn9JAAIVAAkJAhpNLABoAgAVAAkJAhpNLABoAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAACLgAFFH8HAAIgAAMJhAjILgCKAAAgAAMJhAjILgCKAAAuAAQKf0IAAyAACQl8C/MhAEMBACAACQlpC/MhAEMBABAAAglCBCg3AEAAAAAA.',
Fu='Fuzzyguy:BAAALgAECgEJAQAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Gacy:BAAALgAECgEJAQAAAA==.Galaythien:BAAALgAECgYJDQAAAA==.Gang:BAAALgAECgUJBQABLgAFFAQJEQABADIOAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAMAEQaAA==.',
Ge='Geluria:BAABLgAECn8aAAMgAAkJdB2tBwCeAgAgAAkJdB2tBwCeAgAQAAEJ5Q6JPAAuAAABLgAECgkJOgAdAN0kAA==.Geret:BAABLgAECn8iAAIFAAgJdxO1cgCIAQAFAAgJdxO1cgCIAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gh='Ghanaria:BAAALgAECgEJAQAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Gleesh:BAAALgAECgEJAQABLgAFFAEJBwAVAAUfAA==.Glitchy:BAABLgAECn9IAAMfAAkJ3x8CCADVAgAfAAkJZx8CCADVAgAhAAYJGhYLGgB+AQAAAA==.Glokraz:BAAALgAECgcJBwAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgYJDQAAAA==.',
Go='Goingtogetu:BAABLgAECn9IAAMGAAkJrSP0AQAhAwAGAAkJrSP0AQAhAwAFAAYJBxDWkwBMAQAAAA==.Gold:BAAALgAECgIJAgABLgAECgkJKwAcAD4fAA==.Goldfarmr:BAABLgAECn8rAAIcAAkJPh+9DACbAgAcAAkJPh+9DACbAgAAAA==.Goldrawr:BAAALgAECgYJBwABLgAECgkJKwAcAD4fAA==.Goldshocker:BAAALgAECgQJBgABLgAECgkJKwAcAD4fAA==.Golduwu:BAAALgAECgEJAgABLgAECgkJKwAcAD4fAA==.Googlymoogly:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.Gottahvyhand:BAAALgAECgQJBQAAAA==.',
Gr='Greed:BAAALgAFFAIJAgABLgAFFAYJCwAhAKYYAA==.Greeley:BAABLgAECn86AAIZAAkJMCTnAAA9AwAZAAkJMCTnAAA9AwAAAA==.Gregdapro:BAABLgAECn9TAAIgAAkJuSX3AABeAwAgAAkJuSX3AABeAwAAAA==.Gregnstone:BAABLgAECn8jAAIHAAkJlRY+KADJAQAHAAkJlRY+KADJAQABLgAECgkJUwAgALklAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAUJHAAOABoTAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAgJJAAWAEUZAA==.Gunnyal:BAABLgAECn88AAMaAAkJeReuAgBFAQAaAAkJeReuAgBFAQAWAAUJhwqeaAC8AAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8wAAIXAAkJUyM8BQAJAwAXAAkJUyM8BQAJAwAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8kAAMWAAgJRRn+AwA9AgAWAAgJRRn+AwA9AgAaAAEJNAEQDgA8AAAuAAQKfzwAAxYACQktJWkCAE0DABYACQktJWkCAE0DABoAAwldHN86ANkAAAAA.Hakyahi:BAAALgAECgEJAQAAAA==.Hallokitty:BAAALgAECgEJAgAAAA==.Hank:BAAALgADCgYJBgAAAA==.Happerixie:BAAALgADCgkJCQAAAA==.Harkin:BAABLgAECn85AAIFAAkJDxImXwCzAQAFAAkJDxImXwCzAQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgAECgYJDgAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIXAAcJXQsvTwD6AAAXAAcJXQsvTwD6AAAAAA==.Hevy:BAABLgAECn9IAAIMAAkJ/BsiAgA2AgAMAAkJ/BsiAgA2AgAAAA==.',
Hi='Hilarius:BAAALgAECggJEQAAAA==.Hiraeth:BAAALgAECgUJCQAAAA==.Hirukon:BAAALgAECgEJAQAAAA==.',
Ho='Holydadbod:BAAALgAECgQJBwABLgAFFAQJEQAdAJ4gAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn9FAAIFAAkJARlxLQBLAgAFAAkJARlxLQBLAgAAAA==.Hottice:BAAALgAECgEJAwAAAA==.Howlinnbrews:BAABLgAFFH8IAAMUAAQJbxvoGgDzAAAUAAQJDRboGgDzAAAdAAEJ6CVsTwBkAAAAAA==.Howlinplague:BAAALgAFFAIJAwAAAA==.',
Hu='Hulkhogan:BAABLgAECn8fAAIbAAkJAR1uCABzAgAbAAkJAR1uCABzAgAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIMAAMJRBo1YADPAAAMAAMJRBo1YADPAAAuAAQKfycAAgwACAkuIrAVANQCAAwACAkuIrAVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMEAAgJjBi1KAANAgAEAAgJjBi1KAANAgAjAAIJ1hLbSQBGAAAAAA==.Idrizzt:BAAALgAECgYJBgAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8aAAIUAAcJVBbeNgAnAQAUAAcJVBbeNgAnAQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.Invariable:BAAALgAECgEJAQAAAA==.',
Io='Io:BAABLgAFFH8NAAIdAAUJSyH8EgCLAQAdAAUJSyH8EgCLAQAAAA==.Iobo:BAABLgAECn9EAAIYAAkJwRfCAgBeAQAYAAkJwRfCAgBeAQAAAA==.',
Ir='Ironhidez:BAABLgAECn8+AAIFAAkJlg5IZgCjAQAFAAkJlg5IZgCjAQAAAA==.',
Is='Isaarek:BAABLgAECn8oAAIOAAkJAxZpFQAvAgAOAAkJAxZpFQAvAgAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDwAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAgJJgANAN0YAA==.Jasmini:BAAALgAECgEJAwAAAA==.Jastia:BAABLgAECn8eAAIRAAcJjxwpCQC2AQARAAcJjxwpCQC2AQAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jeb:BAAALgAECgEJAgABLgAFFAEJAQACAAAAAA==.Jebopally:BAAALgAECgMJBAABLgAFFAEJAQACAAAAAA==.Jekelez:BAAALgADCgYJCQAAAA==.Jessejames:BAAALgAECgEJAQAAAA==.Jetblack:BAABLgAECn8sAAMSAAkJAhzIHgBsAgASAAkJAhzIHgBsAgARAAEJAAD2bQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8vAAIFAAkJTw55YQCtAQAFAAkJTw55YQCtAQAAAA==.',
Jo='Joecephus:BAABLgAECn81AAIHAAkJhCGDDwCgAgAHAAkJhCGDDwCgAgAAAA==.Joehex:BAABLgAECn88AAIbAAkJgyFiBADfAgAbAAkJgyFiBADfAgAAAA==.Joeschmonk:BAAALgAECgYJBwAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Jubelius:BAAALgAECgYJCQABLgAECgkJHwAKAMUVAA==.Judgematt:BAABLgAECn8XAAIHAAkJBRSeGgAvAgAHAAkJBRSeGgAvAgAAAA==.Justin:BAABLgAECn8fAAIaAAkJvhUIDgAJAgAaAAkJvhUIDgAJAgAAAA==.',
Ka='Kaella:BAAALgAECgQJBAAAAA==.Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAIZAAgJ1AwBFAAhAQAZAAgJ1AwBFAAhAQABLgAFFAIJBQAXANoFAA==.Kaleesh:BAACLgAFFH8TAAImAAcJpSW1AABnAgAmAAcJpSW1AABnAgAuAAQKfyUAAiYACAkJJkcBAGgDACYACAkJJkcBAGgDAAAA.Kallux:BAABLgAECn9WAAIgAAkJQCEDAQCcAgAgAAkJQCEDAQCcAgAAAA==.Kananga:BAABLgAECn8xAAIcAAkJYhjrBQAtAQAcAAkJYhjrBQAtAQAAAA==.Kanati:BAAALgAECgEJAQABLgAECgkJDwACAAAAAA==.Karavira:BAAALgAECgEJAQAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Katniss:BAAALgAECgEJAQAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgAECgYJBgAAAA==.Kazarka:BAAALgAECgEJAQAAAA==.',
Ke='Kelindina:BAAALgAECgMJDQAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Keoeu:BAAALgAECggJEgAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgYJDQAAAA==.',
Ki='Kieleron:BAABLgAECn8kAAIIAAgJARPoGgD4AQAIAAgJARPoGgD4AQAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJEAAAAA==.Kiermaxim:BAABLgAECn8mAAIXAAgJNBwcGwA6AgAXAAgJNBwcGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Killon:BAAALgAECgEJAQABLgAECgkJOQAFADIUAA==.Kimijo:BAAALgAECgEJAgAAAA==.Kindred:BAAALgAECggJCQAAAA==.Kiragrande:BAABLgAECn8iAAIDAAkJxBByLQDIAQADAAkJxBByLQDIAQAAAA==.Kiraneth:BAABLgAECn8gAAIUAAgJMBA7LQBYAQAUAAgJMBA7LQBYAQAAAA==.Kirbie:BAAALgADCgUJBQAAAA==.Kirial:BAAALgAECgkJDAAAAA==.Kiriku:BAABLgAECn8UAAIfAAgJDwujRwDtAAAfAAgJDwujRwDtAAAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.Klorto:BAAALgAECgEJAQAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgYJCgAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgAECgEJAgAAAA==.',
La='Lagartista:BAAALgAFFAIJBAAAAA==.Largcok:BAAALgAECgYJDgAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Le='Lee:BAAALgAFFAYJAQAAAA==.Lefty:BAAALgADCgcJCgABLgAECgkJPgAYAAoUAA==.Leyn:BAAALgAECgUJBQAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lilpwny:BAAALgAECgQJBAABLgAECgkJIQAJADEYAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn88AAIWAAkJ0iQgAwA7AwAWAAkJ0iQgAwA7AwAAAA==.Logres:BAAALgADCgEJAQAAAA==.Lokeira:BAACLgAFFH8PAAITAAQJFBI/RADXAAATAAQJFBI/RADXAAAuAAQKfy0AAhMACAmGG4MJAEMBABMACAmGG4MJAEMBAAAA.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn85AAIFAAkJMhTtUwDOAQAFAAkJMhTtUwDOAQAAAA==.Loonnah:BAAALgAECgIJAgAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgUJBgABLgAECgcJJAAVAE4TAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Lupusregina:BAAALgAECgQJBAABLgAECgkJEAACAAAAAA==.Luvbug:BAABLgAECn8WAAIKAAcJ3SJ9GAB2AgAKAAcJ3SJ9GAB2AgAAAA==.',
Ly='Lyais:BAAALgAECgMJAwAAAA==.Lyara:BAACLgAFFH8dAAMTAAcJMiT0CQArAgATAAcJMiT0CQArAgAXAAQJRxhPIgASAQAuAAQKfx0AAxMACQnAIFAJAOICABMACAkVIFAJAOICABcABglgHP8/ADQBAAAA.Lyi:BAAALgAFFAEJAgAAAA==.Lynn:BAAALgADCgEJAQAAAA==.Lythos:BAACLgAFFH8HAAIgAAMJjwngLgCKAAAgAAMJjwngLgCKAAAuAAQKfxkAAiAACAmPE2obAHMBACAACAmPE2obAHMBAAAA.Lyu:BAAALgAFFAEJAQABLgAFFAcJHQATADIkAA==.Lyuu:BAABLgAFFH8GAAIVAAMJdxa2ggDSAAAVAAMJdxa2ggDSAAABLgAFFAcJHQATADIkAA==.',
['Lø']='Lørdøfßud:BAACLgAFFH8GAAIWAAMJaBEPFADYAAAWAAMJaBEPFADYAAAuAAQKfzQAAxYACQkYIyIHAOwCABYACQm4ISIHAOwCABoABwkSI3ILADECAAAA.',
Ma='Macguffin:BAAALgAECgEJAQAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJHQAMAIYLAA==.Maeve:BAAALgADCggJCAAAAA==.Makimá:BAAALgAECgEJAQABLgAECgkJHwAKAMUVAA==.Makinnor:BAAALgAECgEJAgAAAA==.Maklovin:BAAALgAECgEJAwAAAA==.Malifae:BAABLgAECn8bAAIfAAcJYSGbEwB3AgAfAAcJYSGbEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwAfAGEhAA==.Mankilla:BAAALgAECgQJBwAAAA==.Mansa:BAACLgAFFH8HAAInAAMJTgffCADDAAAnAAMJTgffCADDAAAuAAQKfzkAAicACQnFGpsDAHMCACcACQnFGpsDAHMCAAAA.Mastamojo:BAABLgAECn89AAIHAAkJUAnlNwBuAQAHAAkJUAnlNwBuAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Mavis:BAAALgAECgIJAgAAAA==.Maîev:BAAALgAECgUJBwAAAA==.',
Mc='Mcmurphy:BAAALgAECggJEQAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Meanieman:BAAALgADCgEJAgAAAA==.Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAACLgAFFH8HAAIiAAIJTggjEQCHAAAiAAIJTggjEQCHAAAuAAQKfy8AAyIACQmbFzoHAAACACIACQmMFzoHAAACABEABwmpE04QAD0BAAAA.Melendaren:BAAALgAECgQJBwAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgAECgQJCAAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAFFAEJAQAAAA==.Meowkug:BAAALgAECgEJAgAAAA==.Merscy:BAABLgAECn8bAAIcAAgJngqyOQASAQAcAAgJngqyOQASAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAABLgAECn81AAMfAAkJUhknBABpAQAfAAkJUhknBABpAQAEAAYJ1gs3awDzAAABLgAECgkJNgAcAE4XAA==.Metamonster:BAABLgAECn8vAAMNAAkJcg2keQBwAQANAAkJCgikeQBwAQAgAAYJOBDCBwCzAAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikaels:BAAALgAECgcJCQABLgAECgkJQAAMAHMcAA==.Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgcJDgAAAA==.Mirko:BAABLgAECn8dAAIMAAcJhgtsjAAHAQAMAAcJhgtsjAAHAQAAAA==.Mistiah:BAABLgAFFH8JAAINAAMJQyATdwAVAQANAAMJQyATdwAVAQAAAA==.Mistyjoe:BAAALgAECgEJAQAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn9iAAIeAAkJVR5AAAByAgAeAAkJVR5AAAByAgAAAA==.Mokokniki:BAAALgAECgUJBwAAAA==.Moneie:BAAALgAECgUJDAAAAA==.Monger:BAAALgADCgIJAgAAAA==.Mongò:BAAALgAECgQJBwAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAFFAMJCAAXAKwQAA==.Moondo:BAAALgAECgcJDgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Mooseymancer:BAAALgADCgcJDQAAAA==.Mootron:BAAALgADCgYJCgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mortimus:BAAALgAECgMJAwAAAA==.Mourningstar:BAACLgAFFH8bAAMNAAUJxiVkMACmAQANAAQJxiVkMACmAQAgAAIJhwj4IwAiAAAuAAQKfygAAw0ACQknJPcYALECAA0ACQknJPcYALECACAAAwmqFqQMAF8AAAEuAAUUCAkmAA0A3RgA.Mozaic:BAABLgAECn9hAAIbAAkJWB+uAAC1AgAbAAkJWB+uAAC1AgAAAA==.',
Mu='Mugrüíth:BAAALgAECgUJCwAAAA==.Muyoang:BAAALgADCgEJAQABLgAECgkJMwAEABMfAA==.',
My='Myfeethurt:BAAALgAECgQJBQABLgAFFAMJBgAWAGgRAA==.Mymoon:BAAALgADCgMJAwAAAA==.Myragê:BAAALgADCgkJDQABLgAECgEJAQACAAAAAA==.Myselia:BAABLgAECn8kAAILAAkJBhXAEgACAgALAAkJBhXAEgACAgAAAA==.Mystra:BAAALgAECgcJEAAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgAECgEJAQAAAA==.Naek:BAAALgAECgYJDgAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgYJDgACAAAAAA==.Nalthis:BAAALgAECgYJAwAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAABLgAECn86AAIVAAkJlRfsCgBgAQAVAAkJlRfsCgBgAQAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nicehair:BAAALgADCgYJBgABLgAECgYJCgACAAAAAA==.Nichtaire:BAABLgAECn8ZAAIMAAgJvQk+hgATAQAMAAgJvQk+hgATAQAAAA==.Niem:BAABLgAECn8dAAIhAAkJhSVFAQBOAwAhAAkJhSVFAQBOAwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.Nitsi:BAAALgAECgEJAQABLgAECgkJNQAdAKAaAA==.',
No='Nocturnum:BAABLgAECn9AAAIMAAkJcxw3GACEAgAMAAkJcxw3GACEAgAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8KAAIiAAUJQRdPAABcAQAiAAUJQRdPAABcAQAuAAQKfxwAAiIACAktHi8BAPECACIACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAABLgAFFAMJAwACAAAAAA==.Odin:BAAALgAECgEJAgAAAA==.Odium:BAAALgADCgMJAwABLgAFFAUJEgAKAFchAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAkJHAAKAJoeAA==.',
Ol='Oldage:BAABLgAECn8WAAMEAAkJkhPUAgD1AQAEAAkJkhPUAgD1AQAfAAQJbAOZFQBDAAABLgAECgkJFAAQACQYAA==.Oldmage:BAAALgAECgYJCAAAAA==.Oldmongerpal:BAAALgAECgEJAgAAAA==.',
On='Onetwocowpow:BAABLgAECn9IAAIDAAkJ+hhqFQBuAgADAAkJ+hhqFQBuAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn9ZAAMFAAkJViJwDwATAwAFAAkJViJwDwATAwAGAAkJTBelCQA0AgAAAA==.Orionn:BAACLgAFFH8YAAIKAAUJRSC0CQAUAQAKAAUJRSC0CQAUAQAuAAQKf0oAAgoACQm2JcgEAEQDAAoACQm2JcgEAEQDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAABLgAECn8cAAIKAAkJWw5oSgDCAQAKAAkJWw5oSgDCAQAAAA==.',
Ov='Oven:BAABLgAECn8gAAIUAAgJVxYLIgCfAQAUAAgJVxYLIgCfAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.Patelz:BAAALgADCgQJBAAAAA==.',
Pe='Petoria:BAAALgADCgUJBQAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pinksparkle:BAAALgAECgkJCQAAAA==.Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQABLgAECgkJDwACAAAAAA==.Polyeikon:BAAALgAECgYJCwAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgAECgMJBAAAAA==.Prayr:BAAALgAECgIJAgAAAA==.Praystation:BAAALgAECgUJCwAAAA==.Problem:BAAALgAECgQJBAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgYJCwAAAA==.',
Ra='Raekeshh:BAABLgAECn8ZAAISAAkJ3BWcNAAGAgASAAkJ3BWcNAAGAgAAAA==.Raelone:BAABLgAECn8dAAQRAAkJGBGtIwCUAAASAAUJYg3LqgDtAAARAAYJZBKtIwCUAAAiAAEJ5RNGNwBHAAAAAA==.Rageofmommy:BAAALgAECgMJBAAAAA==.Raidoe:BAABLgAECn9LAAMDAAkJKRz/DwClAgADAAkJKRz/DwClAgAUAAMJOQsIdQBmAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn86AAIKAAkJfRvZBwCqAQAKAAkJfRvZBwCqAQAAAA==.Rant:BAAALgAECgYJCwAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.Razorbeams:BAAALgAECgQJBQABLgAECgkJYgAeAFUeAA==.',
Re='Redishpanda:BAAALgADCgcJFAAAAA==.Redshammy:BAAALgAFFAIJAwAAAA==.Relion:BAABLgAECn8aAAIVAAkJqQnqDQA2AQAVAAkJqQnqDQA2AQABLgAECgkJRAAFAJASAA==.Reo:BAAALgAFFAEJAQABLgAFFAYJIQADACUgAA==.Reverse:BAAALgAECgEJAQAAAA==.',
Rh='Rhell:BAACLgAFFH8OAAIHAAQJqhPIKADeAAAHAAQJqhPIKADeAAAuAAQKfz0AAwcACQk2ImsIAAUDAAcACQk2ImsIAAUDAAUAAQkUAvXRARYAAAAA.',
Ri='Rinche:BAABLgAECn9FAAMXAAkJNxa/GwADAgAXAAkJNxa/GwADAgATAAkJ3guyUgBoAQAAAA==.Rintche:BAAALgAECgUJBQAAAA==.Rivers:BAAALgAFFAMJAwABLgAECgkJFAAQACQYAA==.',
Ro='Rolland:BAABLgAECn8lAAIZAAkJeyD9AQDoAgAZAAkJeyD9AQDoAgAAAA==.Rollf:BAAALgAECgMJAwAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAABLgAECn8hAAMSAAkJOAvmWgCNAQASAAkJOAvmWgCNAQARAAQJ1wTVKQBuAAAAAA==.',
Ru='Rubèus:BAAALgAECgEJAQAAAA==.Rudo:BAABLgAECn8fAAMKAAkJxRVZIgA3AgAKAAkJxRVZIgA3AgAYAAEJrgLYagAnAAAAAA==.Rumproblem:BAABLgAECn9JAAMIAAkJTBg6DwB7AgAIAAkJTBg6DwB7AgAJAAkJoBhuAQBTAgAAAA==.Runekaiser:BAAALgAECgMJCwAAAA==.Runnamuuk:BAABLgAECn82AAIMAAkJGBTzNgDqAQAMAAkJGBTzNgDqAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryegar:BAAALgADCgkJCQAAAA==.Ryeger:BAABLgAECn9YAAMjAAkJDSNiAADUAgAjAAkJDSNiAADUAgAfAAMJpgs0ZgCFAAAAAA==.',
['Rá']='Ráh:BAAALgADCgEJAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn83AAIhAAkJ3BZXEQDXAQAhAAkJ3BZXEQDXAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBQABLgAECgMJDQACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn9EAAMFAAkJkBKsBgDBAQAFAAkJkBKsBgDBAQAHAAkJYwMMRQAsAQAAAA==.Sandbones:BAAALgAECgUJDAABLgAECgkJYgAeAFUeAA==.Sandraice:BAABLgAECn8fAAIFAAgJ0QYyhwBsAQAFAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sanielan:BAAALgAECgYJCwAAAA==.Sansami:BAABLgAECn9DAAIdAAkJsxwIFwDxAQAdAAkJsxwIFwDxAQAAAA==.Saphron:BAAALgAECgQJBAAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAABLgAECn8uAAMfAAcJRQpyCwCnAAAfAAcJRQpyCwCnAAAEAAUJDQMlqwBfAAAAAA==.',
Sc='Sc:BAAALgAECgcJCgABLgAECgkJKgAVAE4jAA==.Scalebagz:BAABLgAECn8gAAMkAAkJSB4WBgCoAgAkAAkJSB4WBgCoAgAOAAgJvRyYIADUAQAAAA==.Schism:BAAALgAECgEJAQAAAA==.Schitzøø:BAAALgAECgEJAgAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgAECgQJBAAAAA==.Senyorseven:BAAALgAECgYJDgAAAA==.Seo:BAAALgAECgQJCQAAAA==.Serabeara:BAAALgAECgIJAgAAAA==.Setresh:BAABLgAECn9ZAAIYAAkJwhXQAgBZAQAYAAkJwhXQAgBZAQAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadowcloak:BAAALgAECgUJBQAAAA==.Shadöwsöng:BAACLgAFFH8JAAIbAAMJKAWAEQB6AAAbAAMJKAWAEQB6AAAuAAQKf0AAAhsACAneC4whACMBABsACAneC4whACMBAAAA.Shaedelana:BAABLgAECn8fAAQIAAgJJhucPAAcAQAIAAUJShOcPAAcAQAJAAYJKBSOCgDIAAAcAAYJIByCCwCVAAAAAA==.Shamrox:BAABLgAECn8WAAIXAAgJvQrPCgDFAAAXAAgJvQrPCgDFAAAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJMwAEABMfAA==.Shinnobi:BAAALgAECgcJBwAAAA==.Shinygoat:BAAALgADCgIJAgABLgAECgkJKgAPAI8fAA==.Shivver:BAAALgAECgEJAQAAAA==.Shivyn:BAACLgAFFH8KAAITAAMJAhaVHQC+AAATAAMJAhaVHQC+AAAuAAQKfz8AAxMACQlMGs4PANMCABMACQlMGs4PANMCABcAAQkXBbmNACoAAAAA.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAkJHAAKAJoeAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAACLgAFFH8UAAMNAAMJ+RfMMQDtAAANAAMJ+RfMMQDtAAAgAAIJrwtwNABnAAAuAAQKfy4AAw0ACQmlGVFIAOkBAA0ACQmlGVFIAOkBACAABQmtD1UuAMwAAAAA.Sickkid:BAABLgAECn9HAAIWAAgJ9SKsCQDIAgAWAAgJ9SKsCQDIAgAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silkiegirl:BAABLgAECn8iAAIWAAkJzhQeGgAdAgAWAAkJzhQeGgAdAgAAAA==.Silvador:BAAALgAFFAEJAQABLgAFFAIJBgAOAFYCAA==.Silvershine:BAABLgAECn8VAAMEAAYJ6w4lgADaAAAEAAUJiAslgADaAAAjAAQJuAYsNwB/AAAAAA==.Silverwolf:BAAALgAECgIJAgAAAA==.Sindrya:BAAALgAECgUJBwAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slayne:BAAALgAECgEJAQAAAA==.Slaänesh:BAAALgADCgcJBwABLgAECgkJMwAEABMfAA==.Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJDAACAAAAAA==.Smashßros:BAAALgAECgQJBAABLgAFFAMJBgAWAGgRAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgkJEAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgABLgAFFAMJCQANAEMgAA==.Snooker:BAAALgADCgEJAQAAAA==.Snuggles:BAABLgAECn8mAAILAAgJjxoCEwD/AQALAAgJjxoCEwD/AQABLgAFFAYJHQAYAHcUAA==.',
So='Solaire:BAAALgAECgEJAQABLgAECgkJDwACAAAAAA==.Solidgen:BAEALgAECgEJAgABLgAFFAgJHQAFACYPAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Solárz:BAAALgAECgYJBgAAAA==.Sonofalich:BAAALgAECgkJCQAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAABLgAECn8WAAMbAAgJNRa8FwCDAQAbAAgJNRa8FwCDAQAaAAMJUgOpNABeAAAAAA==.Spinach:BAAALgAECgEJAQAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgQJDgAAAA==.',
Ss='Ssraeshza:BAABLgAFFH8LAAIhAAYJphi0CABoAQAhAAYJphi0CABoAQAAAA==.',
St='Staretra:BAABLgAECn9BAAMJAAkJOBILHQDcAQAJAAkJOBILHQDcAQAcAAQJowboUwCNAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.Stockade:BAAALgAECgEJAQAAAA==.Stusey:BAAALgADCgIJAgAAAA==.',
Su='Sublevels:BAAALgADCgYJBgAAAA==.Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECggJEQAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Sylph:BAAALgAECgUJBQAAAA==.Symana:BAABLgAECn85AAIcAAkJKB5bCwCxAgAcAAkJKB5bCwCxAgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgAECgEJAQAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgcJEQAAAA==.',
['Sö']='Sörceress:BAAALgAECgYJEwAAAA==.',
Ta='Taadra:BAABLgAECn9mAAITAAkJtSFYAQDhAgATAAkJtSFYAQDhAgAAAA==.Talerah:BAAALgAECgUJCQAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAACLgAFFH8lAAMEAAYJqhp/CACJAQAEAAYJqhp/CACJAQAfAAEJfANEKAAnAAAuAAQKfxgAAwQACQnvF2YeAEwCAAQACQnvF2YeAEwCACEAAgkPE1ZOAHMAAAAA.Talona:BAAALgAFFAEJAQABLgAFFAUJCgAiAEEXAA==.Tandaan:BAAALgADCgkJCgABLgAECgkJGQASANwVAA==.Tanjent:BAABLgAECn8jAAIKAAYJDA0BIwCNAAAKAAYJDA0BIwCNAAAAAA==.Tanok:BAAALgADCgYJBgAAAA==.Tapio:BAABLgAECn84AAIYAAkJ5RkPAgCZAQAYAAkJ5RkPAgCZAQAAAA==.Tatsuma:BAAALgAECgYJDgABLgAECgkJJQAFAPobAA==.Tatsumå:BAAALgAECgcJEgABLgAECgkJJQAFAPobAA==.Tavvi:BAAALgAECgYJBgABLgAECgcJFgAKAN0iAA==.Tazz:BAAALgAECgIJAgAAAA==.',
Te='Terp:BAAALgAECgMJBwAAAA==.',
Th='Thalfinore:BAAALgAECgcJEgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Therogue:BAAALgAECgIJAgAAAA==.Thoghar:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.Thorincan:BAAALgAECgkJCQAAAA==.Thorrs:BAAALgAECgIJBwAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thorwar:BAAALgADCgMJBAAAAA==.Thuglifé:BAAALgAECgEJAQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECggJDAACAAAAAA==.Tidemaiden:BAABLgAECn8ZAAMmAAgJmg9DCQBvAAAmAAMJNAdDCQBvAAATAAcJPgm5GQBrAAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgABLgAFFAMJAwACAAAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tinypickles:BAAALgAECgMJAwAAAA==.Tipsymancer:BAABLgAECn9IAAIdAAkJDSLwAwAOAwAdAAkJDSLwAwAOAwAAAA==.Tirael:BAAALgAECgYJBQABLgAFFAYJAQACAAAAAA==.Tishi:BAAALgAECgIJAwAAAA==.',
To='Tomö:BAAALgAECgkJBAAAAA==.Tossme:BAAALgAECgEJAQABLgAFFAQJEQAdAJ4gAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Traeicel:BAAALgAECggJBQAAAA==.Treesus:BAABLgAECn8fAAIfAAkJLhqWGwAmAgAfAAkJLhqWGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECgkJHwAKAMUVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Ts='Tsu:BAAALgADCgkJCQAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.Tyzi:BAAALgAECgEJAQAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQVAAgJ+iNmNwA7AgAVAAgJXCFmNwA7AgAeAAMJPCQECAAkAQAoAAEJTQ0VDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8lAAIEAAkJsRiVIgA0AgAEAAkJsRiVIgA0AgAAAA==.',
Un='Undeadgnome:BAAALgAECgMJAwAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.Usër:BAAALgAECgQJBwAAAA==.',
Va='Vainin:BAABLgAECn8VAAIVAAYJsgcL5ADVAAAVAAYJsgcL5ADVAAAAAA==.Valle:BAAALgAFFAEJAQAAAA==.Valry:BAAALgAECgYJDgAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAQJCgAhAAIcAA==.Vankro:BAAALgAFFAEJAgABLgAFFAQJGQAPACMmAA==.Variable:BAAALgAECgcJBwAAAA==.Vashdin:BAABLgAECn81AAIFAAkJLx7eBwCfAQAFAAkJLx7eBwCfAQAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECgkJHwAKAMUVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velaronia:BAAALgAECgQJBwAAAA==.Velashis:BAABLgAECn9JAAMEAAkJnCD0AADhAgAEAAkJnCD0AADhAgAfAAQJLw6feABVAAAAAA==.Velathadora:BAAALgAECgEJAQAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAABLgAFFH8IAAIXAAMJrBDJNQC3AAAXAAMJrBDJNQC3AAAAAA==.Vett:BAAALgADCgMJAwABLgAECgYJFQAVALIHAA==.Vexable:BAAALgAECgQJBAAAAA==.',
Vi='Viable:BAAALgAECgUJCgAAAA==.Vibes:BAAALgAECgkJCwAAAA==.Victorvega:BAAALgAECgMJAwABLgAECgkJHwAKAMUVAA==.Vicvega:BAAALgAECgQJBQABLgAECgkJHwAKAMUVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8QAAMDAAMJtRIWPAC1AAADAAMJtRIWPAC1AAAUAAIJlxlmLwCIAAAuAAQKfyYAAxQACQndHRcQAH8CABQACAmuHRcQAH8CAAMABQnvH+lUAB0BAAAA.Vivila:BAAALgAECgMJBwABLgAECgkJSAAMAPwbAA==.Vivillian:BAABLgAFFH8HAAIIAAMJjg98MwC+AAAIAAMJjg98MwC+AAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Voidrèaper:BAAALgAECgEJAQAAAA==.Vordilina:BAABLgAECn8cAAQoAAkJqhgPAgBYAgAoAAkJqhgPAgBYAgAeAAEJuAV9IAAtAAAVAAEJrQHbiAEcAAAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQkAAgJKhn4EwAGAgAkAAgJKhn4EwAGAgAlAAQJxRh7FQC6AAAOAAEJygMInQAkAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAABLgAECn9FAAMTAAkJEhvKNADeAQATAAgJlhnKNADeAQAXAAkJIBmoBQBAAQAAAA==.Vugowulf:BAAALgAECgEJAwAAAA==.',
Vy='Vynae:BAAALgADCgcJBAAAAA==.',
['Vé']='Véxx:BAABLgAECn82AAQPAAkJ5R7cBABnAgAPAAkJ5R7cBABnAgALAAUJYAizQgDtAAAMAAEJdAGj9QAZAAAAAA==.',
['Vì']='Vìx:BAAALgAECgEJAQAAAA==.',
['Ví']='Víx:BAAALgAECggJCAAAAA==.',
['Vî']='Vîper:BAAALgAFFAEJAQAAAA==.',
['Vï']='Vïx:BAAALgADCgUJBQAAAA==.',
Wa='Wadewilson:BAAALgAECgYJBgAAAA==.Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Warihor:BAABLgAECn8vAAMaAAgJeQyTMAAGAQAWAAgJIwq1QABCAQAaAAgJhQmTMAAGAQAAAA==.Waycaps:BAABLgAFFH8FAAIhAAQJUBUQEAAIAQAhAAQJUBUQEAAIAQAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAACLgAFFH8UAAIiAAUJbiTjAQCjAQAiAAUJbiTjAQCjAQAuAAQKfy4AAiIACQk/JMAAACEDACIACQk/JMAAACEDAAAA.',
Wh='Whïte:BAAALgAECgEJAgAAAA==.',
Wi='Wiegraf:BAAALgAECgIJAwABLgAECgkJMwAEABMfAA==.Wife:BAAALgAECgMJAwAAAA==.Wildhide:BAAALgAECgcJCAAAAA==.Withers:BAAALgADCgQJBAAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJDQAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECggJDAAAAA==.',
['Wä']='Wärbëef:BAAALgADCgEJAQAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECggJDAACAAAAAA==.',
Xo='Xorxel:BAAALgAECgQJCAAAAA==.',
Ya='Yacob:BAABLgAECn83AAMcAAkJOx0jCgDFAgAcAAkJOx0jCgDFAgAJAAIJ6hNqEAByAAAAAA==.Yacobge:BAAALgAECgYJBgAAAA==.',
Ye='Yenneferr:BAAALgAECgkJAQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8zAAIEAAkJEx+HCwAGAwAEAAkJEx+HCwAGAwAAAA==.',
Yh='Yhwach:BAACLgAFFH8MAAIgAAYJZA13JADLAAAgAAYJZA13JADLAAAuAAQKfyUAAiAACAk+GbcDAFwBACAACAk+GbcDAFwBAAAA.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAABLgAFFH8MAAIFAAQJGBP7IgDgAAAFAAQJGBP7IgDgAAABLgAECgkJFAAQACQYAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECggJDAAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgcJCwAAAA==.',
Za='Zaeden:BAABLgAECn8dAAIDAAcJDh+fFgANAgADAAcJDh+fFgANAgABLgAECgkJGgANAK0gAA==.Zaft:BAAALgADCgYJBgAAAA==.Zaftdh:BAABLgAECn81AAIMAAkJqhVXNAD1AQAMAAkJqhVXNAD1AQAAAA==.Zaha:BAABLgAECn8eAAIVAAYJ2iKdXAAkAgAVAAYJ2iKdXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zappsz:BAAALgAECggJDwAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zedfrey:BAABLgAECn9HAAIFAAkJ3hmvBwCjAQAFAAkJ3hmvBwCjAQAAAA==.Zedra:BAAALgAECgMJAwAAAA==.Zem:BAABLgAECn8rAAIWAAgJux8tEgBiAgAWAAgJux8tEgBiAgAAAA==.Zemangoose:BAAALgAECgYJBgAAAA==.Zeroultra:BAABLgAECn8+AAIWAAkJth7PEQBmAgAWAAkJth7PEQBmAgAAAA==.Zeräse:BAABLgAECn8VAAIIAAgJRw//JACnAQAIAAgJRw//JACnAQABLgAECgkJMwAEABMfAA==.Zeusdh:BAAALgADCgkJCQAAAA==.Zeusmos:BAABLgAECn9GAAIUAAkJ3iY4AACVAwAUAAkJ3iY4AACVAwAAAA==.',
Zi='Zithenex:BAABLgAECn9GAAIlAAkJ3RcfAQBgAQAlAAkJ3RcfAQBgAQAAAA==.',
Zo='Zoeÿ:BAAALgAECgEJBAAAAA==.',
Zu='Zugnugs:BAAALgAECgMJAQAAAA==.',
Zw='Zwar:BAAALgAECgIJAgAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAABLgAECn8yAAIWAAcJkxXqBwAPAQAWAAcJkxXqBwAPAQAAAA==.',
['Ér']='Éragon:BAAALgAECgYJEwAAAA==.',
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
