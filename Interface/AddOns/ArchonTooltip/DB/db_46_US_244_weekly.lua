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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Priest-Discipline','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Warrior-Fury','Shaman-Elemental','Hunter-Survival','Hunter-Marksmanship','Warrior-Arms','Warrior-Protection','Priest-Holy','Mage-Arcane','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','Warlock-Affliction','Druid-Feral','Druid-Guardian','Evoker-Preservation','Evoker-Devastation','Shaman-Enhancement','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aaminae:BAABLgAECn89AAIBAAkJkxgpDQBUAgABAAkJkxgpDQBUAgAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgUJCwAAAA==.Abracastabya:BAAALgAFFAEJAQAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.Absolution:BAAALgAECgQJBQAAAA==.Abÿss:BAAALgAECgYJBgAAAA==.',
Ad='Adachï:BAABLgAECn8WAAIDAAYJiRpuNQCfAQADAAYJiRpuNQCfAQABLgAECgkJMwAEABMfAA==.Adevil:BAAALgAECgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aegon:BAAALgAECgUJBQAAAA==.Aethlin:BAABLgAECn86AAMFAAkJ6xzKMgA1AgAFAAkJjRnKMgA1AgAGAAgJhh38AQB/AQAAAA==.Aetreyu:BAAALgAECgcJEgAAAA==.Aeturnas:BAABLgAECn81AAIHAAkJ7B+jCAABAwAHAAkJ7B+jCAABAwAAAA==.',
Ag='Aggros:BAAALgAECgYJBgAAAA==.Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanima:BAABLgAECn8dAAMIAAgJjQzuKgB+AQAIAAgJjQzuKgB+AQAJAAYJ3AbYUQDKAAAAAA==.Albus:BAAALgAECgEJAgAAAA==.Aldky:BAAALgAECgEJAQAAAA==.Aliana:BAAALgAFFAEJAQAAAA==.Alinthe:BAAALgADCgkJCQAAAA==.Allindis:BAAALgAECgYJCQABLgAECgkJJQAEALEYAA==.Allypally:BAAALgAECgEJAwAAAA==.Alphamage:BAAALgADCggJCAAAAA==.Alphamonk:BAAALgAECgkJEQAAAA==.Alros:BAABLgAECn9QAAIKAAkJkSNIBgAvAwAKAAkJkSNIBgAvAwAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgAECgQJCAAAAA==.',
Am='Amardyton:BAAALgAECgYJBwAAAA==.',
An='And:BAABLgAECn8sAAMLAAgJYhTBBQDuAAALAAgJYhTBBQDuAAAMAAEJ6QOdOAEcAAAAAA==.Aneas:BAAALgAECgcJEQAAAA==.Antäres:BAAALgADCgQJBAABLgAECgkJMwAEABMfAA==.',
Ap='Apolex:BAAALgADCgUJBQAAAA==.Appela:BAAALgAECgEJAQABLgAECgEJAQACAAAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgMJAwACAAAAAA==.Arette:BAAALgAECgcJCwAAAA==.Arkades:BAABLgAECn8iAAIFAAkJpx1kIwB4AgAFAAkJpx1kIwB4AgAAAA==.Arkshade:BAABLgAECn83AAINAAcJfhLefgBmAQANAAcJfhLefgBmAQAAAA==.Arlia:BAAALgAECgkJEQABLgAFFAIJBgAOAFYCAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECgkJKgAPAI8fAA==.Aryn:BAAALgAECgEJAQAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgcJEAACAAAAAA==.Ashor:BAAALgAECgIJAgAAAA==.Ashrodite:BAAALgADCgYJAgABLgAECgcJEAACAAAAAA==.Asmo:BAAALgADCggJGAAAAA==.Aspir:BAEALgAECgYJBgABLgAFFAgJGQAQAIATAA==.Astarii:BAAALgAECgEJBQAAAA==.Asterica:BAABLgAECn9ZAAMRAAkJ+xjgAADOAQASAAkJWBi6MQARAgARAAgJnRbgAADOAQAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.Atormunster:BAAALgADCgMJAwABLgAFFAIJBQAKAJwGAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAITAAYJ+A16UwA4AQATAAYJ+A16UwA4AQAAAA==.',
Av='Averynicole:BAABLgAECn8ZAAIUAAcJBxYLLABfAQAUAAcJBxYLLABfAQAAAA==.',
Aw='Awasjr:BAABLgAECn8mAAIKAAkJlh/GGACSAgAKAAkJlh/GGACSAgAAAA==.Awassy:BAAALgAECgEJAgAAAA==.',
Ay='Ayano:BAACLgAFFH8HAAIVAAEJBR91UwBFAAAVAAEJBR91UwBFAAAuAAQKfxYAAhUACAliHrFKAPsBABUACAliHrFKAPsBAAAA.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balanla:BAAALgAECgcJCAABLgAFFAMJBgAWAGgRAA==.Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDwABLgAECgkJMwAEABMfAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgAECgEJAQAAAA==.Bearhug:BAACLgAFFH8HAAMDAAMJAAiGUgBfAAADAAMJAAiGUgBfAAAUAAEJoAHDSgApAAAuAAQKfy8AAwMACAn1Gnc8AH4BAAMABwntGXc8AH4BABQABwleCYFCAA0BAAEuAAUUBAkNABcA/QoA.Bearshock:BAACLgAFFH8NAAMXAAQJ/QpGLQDfAAAXAAQJ/QpGLQDfAAATAAEJTACOjwAdAAAuAAQKfx4AAhcACAneHZEUAEYCABcACAneHZEUAEYCAAAA.Beasty:BAACLgAFFH8FAAMKAAIJnAZ/NwCKAAAKAAIJnAZ/NwCKAAAYAAIJUAGJLgBnAAAuAAQKfyUAAxkACAkeEK8RAEABABkACAkeEK8RAEABABgABgmHBPI9ANQAAAAA.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAABLgAECn83AAIGAAkJ5CT2AABUAwAGAAkJ5CT2AABUAwAAAA==.Beeb:BAAALgAECgUJDgABLgAECgkJNwAGAOQkAA==.Beefisting:BAAALgAECgYJDAABLgAECgkJNwAGAOQkAA==.Beethicc:BAAALgAECgEJBAABLgAECgkJNwAGAOQkAA==.Beeuwu:BAAALgAECgIJAwABLgAECgkJNwAGAOQkAA==.Beliara:BAAALgAECgkJDQAAAA==.Belijoe:BAAALgAECgEJAQAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Belshuntress:BAAALgAECgEJAgAAAA==.Beverage:BAAALgAECgIJAgAAAA==.',
Bi='Bicboi:BAAALgAECgEJAQAAAA==.Bigmattyl:BAAALgAECgcJCgAAAA==.Bionarra:BAABLgAECn81AAIVAAkJjR04BAD6AQAVAAkJjR04BAD6AQAAAA==.Bishopwr:BAABLgAECn8pAAMaAAkJvBdQDAAiAgAaAAkJvBdQDAAiAgAbAAYJCwohMwCvAAAAAA==.Bittertøfu:BAABLgAECn8eAAIXAAcJfQb/WQDWAAAXAAcJfQb/WQDWAAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJCgAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blessu:BAAALgAECgEJAgAAAA==.Blitê:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Bm='Bmpfrostie:BAABLgAECn8WAAIVAAcJcQ41yABYAQAVAAcJcQ41yABYAQAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECgkJNwAcADsdAA==.Bohica:BAAALgAECggJDgAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAABLgAFFAMJCQANAEMgAA==.',
Br='Brakug:BAABLgAECn8vAAMVAAkJHiMULgC5AgAVAAkJHiMULgC5AgAdAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAIJAwAAAA==.Brem:BAACLgAFFH8IAAIdAAMJiBnrAQD5AAAdAAMJiBnrAQD5AAAuAAQKfxsAAh0ACAmCHB4EABICAB0ACAmCHB4EABICAAAA.Bretagnesse:BAABLgAECn8UAAIeAAgJ2wXJRQD1AAAeAAgJ2wXJRQD1AAAAAA==.Briara:BAAALgAECgYJDwAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgAECgQJBgAAAA==.Broníx:BAAALgAECgEJBQAAAA==.Bropeep:BAACLgAFFH8HAAINAAMJDhutjgDtAAANAAMJDhutjgDtAAAuAAQKf1MAAw0ACQnZJT0EAF4DAA0ACQnZJT0EAF4DABAABAmdFKIcAOkAAAAA.Brotality:BAAALgADCgMJBAAAAA==.Brynhildr:BAAALgAECgcJDwABLgAFFAQJEQAfAJ4gAA==.',
Bu='Bullshott:BAABLgAECn8jAAIKAAkJrx1qHQB1AgAKAAkJrx1qHQB1AgAAAA==.Bum:BAABLgAECn8mAAMeAAkJsh/4BABRAwAeAAkJsh/4BABRAwAEAAEJ0xCM0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgAECgUJCQAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJEQAAAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBgAAAA==.',
['Bú']='Búll:BAAALgAECgEJAQAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAABLgAECn8cAAMNAAgJYxC9bgCHAQANAAgJ+g69bgCHAQAgAAYJdA1nMgDTAAABLgAECggJQAAfAPASAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8zAAIFAAkJXQgNjABZAQAFAAkJXQgNjABZAQAAAA==.Carrots:BAABLgAECn8vAAIKAAkJCBWgSADIAQAKAAkJCBWgSADIAQAAAA==.Cartman:BAABLgAFFH8HAAIbAAQJSRfcEwAEAQAbAAQJSRfcEwAEAQAAAA==.Cashmachine:BAABLgAECn8tAAIKAAkJAx8VGwCDAgAKAAkJAx8VGwCDAgAAAA==.Castorice:BAAALgAECgEJAQAAAA==.Catfight:BAABLgAECn9BAAIGAAgJDhLPHQAmAQAGAAgJDhLPHQAmAQAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMSAAkJdBhqLgBTAgASAAkJdBhqLgBTAgARAAEJAABoZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8RAAQKAAUJVyHdGgAJAQAKAAUJMyDdGgAJAQAZAAEJISI3IwBlAAAYAAEJzA98MgBIAAAuAAQKfxwABBkACAmLIsIYAGYCABkACAkjIcIYAGYCAAoABQlPHXFcAJABABgAAwkrGAlMAIUAAAAA.Cheesecake:BAABLgAECn8yAAMRAAkJbhBADAB7AQARAAgJBRJADAB7AQAhAAMJNws1BwBmAAAAAA==.Chelsie:BAAALgAECgYJCgABLgAFFAQJEQAfAJ4gAA==.Chihiko:BAAALgAECgMJAwAAAA==.Choks:BAABLgAECn83AAIWAAgJxg2vCQDJAAAWAAgJxg2vCQDJAAAAAA==.Chubbycat:BAABLgAECn8VAAMEAAcJLhmOPQCuAQAEAAcJLhmOPQCuAQAiAAUJYh35FwBTAQAAAA==.Chuggz:BAABLgAECn81AAIfAAkJoBpSDQBjAgAfAAkJoBpSDQBjAgAAAA==.Chéfboyrlee:BAACLgAFFH8hAAIJAAgJJBi0BQAjAgAJAAgJJBi0BQAjAgAuAAQKfzYAAgkACQn6IrkEAAwDAAkACQn6IrkEAAwDAAAA.',
Ci='Cizmac:BAAALgAECgYJDgAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgAECgQJBAAAAA==.Cownado:BAABLgAECn9AAAIfAAgJ8BIyBADWAAAfAAgJ8BIyBADWAAAAAA==.',
Cr='Crematorion:BAAALgAECgMJAwAAAA==.Crippin:BAAALgAECgEJAQAAAA==.Crouton:BAAALgADCgkJCgAAAA==.',
Ct='Ctrlaltchill:BAAALgADCgEJAQAAAA==.',
Cu='Cursedspirit:BAAALgAECgQJBwAAAA==.',
Cy='Cybelem:BAABLgAECn8tAAIXAAkJmB5ZEABwAgAXAAkJmB5ZEABwAgAAAA==.Cyfelen:BAABLgAECn8ZAAQRAAkJiB9oAQDWAgARAAkJiB9oAQDWAgAhAAQJLxmtHQDSAAASAAIJrw+H+AByAAAAAA==.Cynleel:BAAALgAECggJEAABLgAECgkJPwAIAD0UAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQAAAA==.Damonstyle:BAAALgAECgEJAgAAAA==.Dandistyle:BAABLgAECn8fAAMfAAkJdx1kCwB+AgAfAAkJbh1kCwB+AgAUAAEJchK2fAAzAAAAAA==.Darknature:BAAALgAECgkJCQAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathblade:BAAALgAECgEJAQAAAA==.Deathmatrynn:BAAALgAECgYJDgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAACLgAFFH8FAAIXAAIJ2gUkSwBnAAAXAAIJ2gUkSwBnAAAuAAQKfxUAAhcACAnaFl8eAO8BABcACAnaFl8eAO8BAAAA.Deeviant:BAAALgAECggJDgAAAA==.Defend:BAABLgAFFH8HAAIjAAQJ2BluBAAvAQAjAAQJ2BluBAAvAQABLgAFFAQJBwAbAEkXAA==.Delrager:BAACLgAFFH8HAAIBAAIJch5vLwCtAAABAAIJch5vLwCtAAAuAAQKfygAAgEABwmYI3cNAFACAAEABwmYI3cNAFACAAAA.Delyta:BAAALgAECgkJCQAAAA==.Demidru:BAABLgAECn8VAAMjAAgJSRJxAwBIAQAjAAcJ6xJxAwBIAQAiAAgJ7ASNBADAAAAAAA==.Demonicdawn:BAAALgADCgEJAQAAAA==.Demónícz:BAAALgAECgMJAwAAAA==.Derat:BAAALgAECgkJEQAAAA==.Destroy:BAABLgAFFH8GAAISAAMJpQMGkwCcAAASAAMJpQMGkwCcAAABLgAFFAQJBwAbAEkXAA==.Deverux:BAAALgAECgEJAQAAAA==.',
Di='Dibbydab:BAABLgAECn8iAAITAAkJexMWOgDGAQATAAkJexMWOgDGAQAAAA==.',
Dj='Django:BAABLgAECn82AAMeAAkJsyIdBgD2AgAeAAkJsyIdBgD2AgAEAAIJkAbHxgA+AAAAAA==.Djatalon:BAABLgAECn8WAAMkAAUJuAsWIwDWAAAkAAUJuAsWIwDWAAAlAAMJrAUaHABsAAAAAA==.Djderpyderpy:BAAALgAECgYJDQAAAA==.Djehrtey:BAAALgAECggJEAAAAA==.Djin:BAAALgAECgMJBAABLgAFFAQJEQAfAJ4gAA==.Djinni:BAACLgAFFH8RAAIfAAQJniDAEwCFAQAfAAQJniDAEwCFAQAuAAQKfzUAAx8ACQk9IXkGANMCAB8ACAlsI3kGANMCABQACQkSG6gOAF4CAAAA.',
Dk='Dkota:BAAALgAECgUJBgAAAA==.',
Do='Dobath:BAAALgADCgQJBAAAAA==.Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8fAAMQAAgJtxtyCAAHAgAQAAgJtxtyCAAHAgANAAMJsA2A/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8YAAQkAAcJNxmADwDUAQAkAAcJNxmADwDUAQAOAAQJuwziYQC1AAAlAAEJAACAPAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Draknem:BAAALgAECgUJBwAAAA==.Dramaticus:BAAALgAECgQJBAAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drenleah:BAABLgAECn8XAAIRAAkJpRZ0BQAZAgARAAkJpRZ0BQAZAgABLgAECgkJSAAMAPwbAA==.Drenlee:BAAALgAECgEJAgABLgAECgkJSAAMAPwbAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgABLgAECgEJAQACAAAAAA==.Dryya:BAAALgAECgQJCAAAAA==.Drêck:BAAALgAECgEJAQAAAA==.',
Du='Dumblegear:BAABLgAECn8fAAMVAAgJpRVRbACiAQAVAAgJpRVRbACiAQAdAAEJbQY0IAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAFFAMJBgAWAGgRAA==.',
Dw='Dwagon:BAAALgADCgUJBQAAAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgAECgEJAQAAAA==.Dädärkbeëf:BAAALgADCgcJCQAAAA==.',
Ed='Edinna:BAABLgAECn89AAMVAAkJKhu6AgBwAgAVAAkJKhu6AgBwAgAdAAQJTQoTEADBAAAAAA==.',
Ee='Eevie:BAAALgADCgMJBgAAAA==.',
Ei='Einekliene:BAAALgAECgcJBwAAAA==.',
Ek='Ekatrina:BAAALgAECgEJAQAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Eldernoc:BAABLgAECn8UAAIjAAgJAw/EAwA5AQAjAAgJAw/EAwA5AQAAAA==.Elessedil:BAAALgAECggJDgAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgYJDQAAAA==.Elucidäte:BAAALgAECgEJAQAAAA==.Elyriana:BAABLgAECn8jAAMEAAkJpSAKCQAoAwAEAAkJpSAKCQAoAwAiAAEJqSBoQQBZAAAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEBLgAECn8kAAIKAAYJPyLRCABuAQAKAAYJPyLRCABuAQABLgAECgkJLAAKANQgAA==.Emirozu:BAAALgADCgEJAQAAAA==.Emixi:BAAALgAECgQJBQAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECggJDwAAAA==.Emritelan:BAAALgAECgQJBAAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8YAAIFAAYJixdsJgBvAQAFAAYJixdsJgBvAQAuAAQKfzEAAgUACQmaHwIlAHACAAUACQmaHwIlAHACAAAA.',
Ep='Epedemik:BAAALgAECgcJCQAAAA==.',
Er='Erazath:BAAALgAECgUJBgABLgAFFAMJBwAgAI8JAA==.Eredo:BAAALgAECgUJCwABLgAFFAMJBgAWAGgRAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgAECgIJAgAAAA==.Erush:BAAALgAECgEJAQAAAA==.',
Es='Esha:BAAALgAECgEJAQAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ex='Exhul:BAAALgAECgEJAQAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Faewing:BAABLgAFFH8GAAIOAAIJVgKBXgBcAAAOAAIJVgKBXgBcAAAAAA==.Falar:BAAALgAECggJDQAAAA==.Fatelf:BAAALgADCgMJAwAAAA==.Fatowlbert:BAAALgAECgEJAgAAAA==.Faval:BAAALgAECggJDwABLgAECgkJKgAPAI8fAA==.Favel:BAABLgAECn8qAAMPAAkJjx9OAQAcAwAPAAgJ4iFOAQAcAwAMAAkJRwv4XwBpAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn9VAAIKAAkJyBvwAgBLAgAKAAkJyBvwAgBLAgAAAA==.Febz:BAABLgAECn8eAAIVAAgJbBsqMACyAgAVAAgJbBsqMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAABLgAECn8aAAIMAAgJZh/xIgBFAgAMAAgJZh/xIgBFAgAAAA==.Felfüry:BAACLgAFFH8LAAMLAAMJ8QdMDwBwAAALAAMJ8QdMDwBwAAAPAAMJxwNYEABOAAAuAAQKf0cABAsACQm/FEMTAPwBAAsACQm/FEMTAPwBAA8ACAmGCb4WAPEAAAwAAglYCZYGAUQAAAAA.Felly:BAAALgAECgYJBgAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Festicules:BAAALgAECgQJBAAAAA==.Festyr:BAAALgAECgQJCAAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECggJDAACAAAAAA==.Finella:BAABLgAECn8UAAMQAAkJJBipCAABAgAQAAkJjhOpCAABAgAgAAYJaxYLJgAjAQAAAA==.Finneas:BAAALgAECgEJBAABLgAECgkJIgAFAKcdAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJLwAVAB4jAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgkJFAAQACQYAA==.',
Fo='Fogassann:BAABLgAECn8ZAAINAAkJrxwVKwBUAgANAAkJrxwVKwBUAgABLgAFFAMJBgAWAGgRAA==.Fogdemon:BAAALgAECgIJBAABLgAFFAUJGAAhAHMUAA==.Foggpy:BAACLgAFFH8YAAMhAAUJcxR+BQAvAQAhAAUJcxR+BQAvAQASAAQJnwOOcwDaAAAuAAQKfygABCEACAmeInUEADYCACEABwkkJXUEADYCABIABgkNG8FXAMABABEABgljGQ4fAFgBAAAA.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freinkenbaby:BAAALgAECgEJAQAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostnuts:BAAALgAECgEJAQAAAA==.Frostybear:BAABLgAECn9JAAIVAAkJAhpNLABoAgAVAAkJAhpNLABoAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAACLgAFFH8HAAIgAAMJhAjILgCKAAAgAAMJhAjILgCKAAAuAAQKf0IAAyAACQl8C/MhAEMBACAACQlpC/MhAEMBABAAAglCBCg3AEAAAAAA.',
Fu='Fuzzyguy:BAAALgAECgEJAQAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Gacy:BAAALgAECgEJAQAAAA==.Galaythien:BAAALgAECgYJDQAAAA==.Gang:BAAALgAECgUJBQABLgAFFAQJEQABADIOAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAMAEQaAA==.',
Ge='Geluria:BAABLgAECn8aAAMgAAkJdB2tBwCeAgAgAAkJdB2tBwCeAgAQAAEJ5Q6JPAAuAAABLgAECgkJOgAfAN0kAA==.Geret:BAABLgAECn8iAAIFAAgJdxO1cgCIAQAFAAgJdxO1cgCIAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gh='Ghanaria:BAAALgAECgEJAQAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Gleesh:BAAALgAECgEJAQABLgAFFAEJBwAVAAUfAA==.Glitchy:BAABLgAECn9IAAMeAAkJ3x8CCADVAgAeAAkJZx8CCADVAgAjAAYJGhYLGgB+AQAAAA==.Glokraz:BAAALgAECgcJBwAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgYJDQAAAA==.',
Go='Goingtogetu:BAABLgAECn9IAAMGAAkJrSP0AQAhAwAGAAkJrSP0AQAhAwAFAAYJBxDWkwBMAQAAAA==.Gold:BAAALgAECgIJAgABLgAECgkJKwAcAD4fAA==.Goldfarmr:BAABLgAECn8rAAIcAAkJPh+9DACbAgAcAAkJPh+9DACbAgAAAA==.Goldrawr:BAAALgAECgYJBwABLgAECgkJKwAcAD4fAA==.Goldshocker:BAAALgAECgQJBgABLgAECgkJKwAcAD4fAA==.Golduwu:BAAALgAECgEJAgABLgAECgkJKwAcAD4fAA==.Googlymoogly:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.Gottahvyhand:BAAALgAECgQJBQAAAA==.',
Gr='Greed:BAAALgAFFAIJAgABLgAFFAYJCwAjAKYYAA==.Greeley:BAABLgAECn86AAIZAAkJMCTnAAA9AwAZAAkJMCTnAAA9AwAAAA==.Gregdapro:BAABLgAECn9TAAIgAAkJuSX3AABeAwAgAAkJuSX3AABeAwAAAA==.Gregnstone:BAABLgAECn8jAAIHAAkJlRY+KADJAQAHAAkJlRY+KADJAQABLgAECgkJUwAgALklAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAUJHAAOABoTAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAgJJAAWAEUZAA==.Gunnyal:BAABLgAECn85AAMaAAgJKxg9GgCIAQAaAAgJKxg9GgCIAQAWAAUJhwqeaAC8AAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8wAAIXAAkJUyM8BQAJAwAXAAkJUyM8BQAJAwAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8kAAMWAAgJRRn+AwA9AgAWAAgJRRn+AwA9AgAaAAEJNAEQDgA8AAAuAAQKfzwAAxYACQktJWkCAE0DABYACQktJWkCAE0DABoAAwldHN86ANkAAAAA.Hakyahi:BAAALgADCggJCAAAAA==.Hallokitty:BAAALgAECgEJAgAAAA==.Hank:BAAALgADCgYJBgAAAA==.Happerixie:BAAALgADCgkJCQAAAA==.Harkin:BAABLgAECn85AAIFAAkJDxImXwCzAQAFAAkJDxImXwCzAQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgAECgYJDgAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIXAAcJXQsvTwD6AAAXAAcJXQsvTwD6AAAAAA==.Hevy:BAABLgAECn9IAAIMAAkJ/ButAQA7AgAMAAkJ/ButAQA7AgAAAA==.',
Hi='Hilarius:BAAALgAECggJEQAAAA==.Hiraeth:BAAALgAECgUJCQAAAA==.Hirukon:BAAALgAECgEJAQAAAA==.',
Ho='Holydadbod:BAAALgAECgQJBwABLgAFFAQJEQAfAJ4gAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn9FAAIFAAkJARlxLQBLAgAFAAkJARlxLQBLAgAAAA==.Hottice:BAAALgAECgEJAwAAAA==.Howlinnbrews:BAABLgAFFH8IAAMUAAQJbxvoGgDzAAAUAAQJDRboGgDzAAAfAAEJ6CVsTwBkAAAAAA==.Howlinplague:BAAALgAFFAIJAwAAAA==.',
Hu='Hulkhogan:BAABLgAECn8fAAIbAAkJAR1uCABzAgAbAAkJAR1uCABzAgAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIMAAMJRBo1YADPAAAMAAMJRBo1YADPAAAuAAQKfycAAgwACAkuIrAVANQCAAwACAkuIrAVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMEAAgJjBi1KAANAgAEAAgJjBi1KAANAgAiAAIJ1hLbSQBGAAAAAA==.Idrizzt:BAAALgAECgYJBgAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8aAAIUAAcJVBbeNgAnAQAUAAcJVBbeNgAnAQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Io:BAABLgAFFH8NAAIfAAUJSyH8EgCLAQAfAAUJSyH8EgCLAQAAAA==.Iobo:BAABLgAECn9AAAIYAAgJ4xZnAwAOAQAYAAgJ4xZnAwAOAQAAAA==.',
Ir='Ironhidez:BAABLgAECn8+AAIFAAkJlg5IZgCjAQAFAAkJlg5IZgCjAQAAAA==.',
Is='Isaarek:BAABLgAECn8oAAIOAAkJAxZpFQAvAgAOAAkJAxZpFQAvAgAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDwAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAgJJgANAN0YAA==.Jasmini:BAAALgAECgEJAwAAAA==.Jastia:BAABLgAECn8eAAIRAAcJjxwpCQC2AQARAAcJjxwpCQC2AQAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jeb:BAAALgAECgEJAgABLgAFFAEJAQACAAAAAA==.Jebopally:BAAALgAECgMJBAABLgAFFAEJAQACAAAAAA==.Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8sAAMSAAkJAhzIHgBsAgASAAkJAhzIHgBsAgARAAEJAAD2bQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8vAAIFAAkJTw55YQCtAQAFAAkJTw55YQCtAQAAAA==.',
Jo='Joecephus:BAABLgAECn8xAAIHAAgJMiKDDwCgAgAHAAgJMiKDDwCgAgAAAA==.Joehex:BAABLgAECn88AAIbAAkJgyFiBADfAgAbAAkJgyFiBADfAgAAAA==.Joeschmonk:BAAALgAECgYJBgAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Jubelius:BAAALgAECgYJCQABLgAECgkJHwAKAMUVAA==.Judgematt:BAABLgAECn8XAAIHAAkJBRSeGgAvAgAHAAkJBRSeGgAvAgAAAA==.Justin:BAABLgAECn8fAAIaAAkJvhUIDgAJAgAaAAkJvhUIDgAJAgAAAA==.',
Ka='Kaella:BAAALgAECgQJBAAAAA==.Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAIZAAgJ1AwBFAAhAQAZAAgJ1AwBFAAhAQABLgAFFAIJBQAXANoFAA==.Kaleesh:BAACLgAFFH8TAAImAAcJpSW1AABnAgAmAAcJpSW1AABnAgAuAAQKfyUAAiYACAkJJkcBAGgDACYACAkJJkcBAGgDAAAA.Kallux:BAABLgAECn9PAAIgAAkJQCFdBQDUAgAgAAkJQCFdBQDUAgAAAA==.Kananga:BAABLgAECn8tAAIcAAgJ+BncIAC8AQAcAAgJ+BncIAC8AQAAAA==.Kanati:BAAALgAECgEJAQABLgAECgkJDwACAAAAAA==.Karavira:BAAALgAECgEJAQAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Katniss:BAAALgAECgEJAQAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgAECgYJBgAAAA==.Kazarka:BAAALgADCgEJAQAAAA==.',
Ke='Kelindina:BAAALgAECgMJDQAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Keoeu:BAAALgAECggJEgAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgYJDQAAAA==.',
Ki='Kieleron:BAABLgAECn8kAAIIAAgJARPoGgD4AQAIAAgJARPoGgD4AQAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJEAAAAA==.Kiermaxim:BAABLgAECn8mAAIXAAgJNBwcGwA6AgAXAAgJNBwcGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Killon:BAAALgAECgEJAQABLgAECgkJOQAFADIUAA==.Kindred:BAAALgAECggJCQAAAA==.Kiragrande:BAABLgAECn8iAAIDAAkJxBByLQDIAQADAAkJxBByLQDIAQAAAA==.Kiraneth:BAABLgAECn8gAAIUAAgJMBA7LQBYAQAUAAgJMBA7LQBYAQAAAA==.Kirbie:BAAALgADCgUJBQAAAA==.Kirial:BAAALgAECggJCAAAAA==.Kiriku:BAABLgAECn8UAAIeAAgJDwujRwDtAAAeAAgJDwujRwDtAAAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.Klorto:BAAALgAECgEJAQAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgYJCgAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgAECgEJAgAAAA==.',
La='Lagartista:BAAALgAFFAIJBAAAAA==.Largcok:BAAALgAECgYJDAAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Le='Lee:BAAALgAFFAYJAQAAAA==.Lefty:BAAALgADCgcJCgABLgAECgkJPAAYAAoUAA==.Leyn:BAAALgAECgUJBQAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lilpwny:BAAALgAECgQJBAABLgAECgkJIQAJADEYAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn88AAIWAAkJ0iQgAwA7AwAWAAkJ0iQgAwA7AwAAAA==.Logres:BAAALgADCgEJAQAAAA==.Lokeira:BAACLgAFFH8PAAITAAQJFBI/RADXAAATAAQJFBI/RADXAAAuAAQKfykAAhMACAmGG0ozAOUBABMACAmGG0ozAOUBAAAA.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn85AAIFAAkJMhTtUwDOAQAFAAkJMhTtUwDOAQAAAA==.Loonnah:BAAALgAECgIJAgAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgUJBgABLgAECgcJJAAVAE4TAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Lupusregina:BAAALgAECgQJBAABLgAECgkJEAACAAAAAA==.Luvbug:BAABLgAECn8WAAIKAAcJ3SJ9GAB2AgAKAAcJ3SJ9GAB2AgAAAA==.',
Ly='Lyais:BAAALgAECgMJAwAAAA==.Lyara:BAACLgAFFH8dAAMTAAcJMiT0CQArAgATAAcJMiT0CQArAgAXAAQJRxhPIgASAQAuAAQKfxwAAxMACQnAIFAJAOICABMACAkVIFAJAOICABcABglnG/8/ADQBAAAA.Lyi:BAAALgAFFAEJAgAAAA==.Lynn:BAAALgADCgEJAQAAAA==.Lythos:BAACLgAFFH8HAAIgAAMJjwngLgCKAAAgAAMJjwngLgCKAAAuAAQKfxkAAiAACAmPE2obAHMBACAACAmPE2obAHMBAAAA.Lyu:BAAALgAFFAEJAQABLgAFFAcJHQATADIkAA==.Lyuu:BAABLgAFFH8GAAIVAAMJdxa2ggDSAAAVAAMJdxa2ggDSAAABLgAFFAcJHQATADIkAA==.',
['Lø']='Lørdøfßud:BAACLgAFFH8GAAIWAAMJaBGVEADeAAAWAAMJaBGVEADeAAAuAAQKfzQAAxYACQkYIyIHAOwCABYACQm4ISIHAOwCABoABwkSI3ILADECAAAA.',
Ma='Macguffin:BAAALgAECgEJAQAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJHQAMAIYLAA==.Maeve:BAAALgADCggJCAAAAA==.Makimá:BAAALgAECgEJAQABLgAECgkJHwAKAMUVAA==.Makinnor:BAAALgAECgEJAgAAAA==.Maklovin:BAAALgAECgEJAwAAAA==.Malifae:BAABLgAECn8bAAIeAAcJYSGbEwB3AgAeAAcJYSGbEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwAeAGEhAA==.Mankilla:BAAALgAECgQJBwAAAA==.Mansa:BAACLgAFFH8HAAInAAMJTgffCADDAAAnAAMJTgffCADDAAAuAAQKfzkAAicACQnFGpsDAHMCACcACQnFGpsDAHMCAAAA.Mastamojo:BAABLgAECn89AAIHAAkJUAnlNwBuAQAHAAkJUAnlNwBuAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Mavis:BAAALgAECgIJAgAAAA==.Maîev:BAAALgAECgUJBwAAAA==.',
Mc='Mcmurphy:BAAALgAECggJEQAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Meanieman:BAAALgADCgEJAgAAAA==.Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAACLgAFFH8HAAIhAAIJTggjEQCHAAAhAAIJTggjEQCHAAAuAAQKfysAAyEACQmmFjoHAAACACEACQmXFjoHAAACABEABwmpE04QAD0BAAAA.Melendaren:BAAALgAECgQJBwAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgAECgQJCAAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAFFAEJAQAAAA==.Meowkug:BAAALgAECgEJAgAAAA==.Merscy:BAABLgAECn8bAAIcAAgJngqyOQASAQAcAAgJngqyOQASAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAABLgAECn8zAAMeAAcJtRl3KACNAQAeAAcJtRl3KACNAQAEAAYJ1gs3awDzAAAAAA==.Metamonster:BAABLgAECn8vAAMNAAkJcg2keQBwAQANAAkJCgikeQBwAQAgAAYJOBBqBgCzAAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikaels:BAAALgAECgcJCAABLgAECgkJQAAMAHMcAA==.Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgcJDgAAAA==.Mirko:BAABLgAECn8dAAIMAAcJhgtsjAAHAQAMAAcJhgtsjAAHAQAAAA==.Mistiah:BAABLgAFFH8JAAINAAMJQyATdwAVAQANAAMJQyATdwAVAQAAAA==.Mistyjoe:BAAALgAECgEJAQAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn9bAAIdAAkJOB0+AABCAgAdAAkJOB0+AABCAgAAAA==.Mokokniki:BAAALgAECgIJAgAAAA==.Moneie:BAAALgAECgUJDAAAAA==.Monger:BAAALgADCgIJAgAAAA==.Mongò:BAAALgAECgQJBwAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAFFAMJCAAXAKwQAA==.Moondo:BAAALgAECgcJDgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Mooseymancer:BAAALgADCgcJDQAAAA==.Mootron:BAAALgADCgYJCgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mortimus:BAAALgAECgMJAwAAAA==.Mourningstar:BAACLgAFFH8bAAMNAAUJxiVkMACmAQANAAQJxiVkMACmAQAgAAIJhwicHwAiAAAuAAQKfyUAAw0ACQkeJPcYALECAA0ACQkeJPcYALECACAAAwmqFnwKAF8AAAEuAAUUCAkmAA0A3RgA.Mozaic:BAABLgAECn9aAAIbAAkJuR68AABmAgAbAAkJuR68AABmAgAAAA==.',
Mu='Mugrüíth:BAAALgAECgUJCwAAAA==.Muyoang:BAAALgADCgEJAQABLgAECgkJMwAEABMfAA==.',
My='Myfeethurt:BAAALgAECgQJBQABLgAFFAMJBgAWAGgRAA==.Mymoon:BAAALgADCgMJAwAAAA==.Myragê:BAAALgADCgkJDQABLgAECgEJAQACAAAAAA==.Myselia:BAABLgAECn8kAAILAAkJBhXAEgACAgALAAkJBhXAEgACAgAAAA==.Mystra:BAAALgAECgcJEAAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Naek:BAAALgAECgYJDgAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgYJDgACAAAAAA==.Nalthis:BAAALgAECgYJAwAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAABLgAECn82AAIVAAgJKBeyDwAAAQAVAAgJKBeyDwAAAQAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAABLgAECn8ZAAIMAAgJvQk+hgATAQAMAAgJvQk+hgATAQAAAA==.Niem:BAABLgAECn8dAAIjAAkJhSVFAQBOAwAjAAkJhSVFAQBOAwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.Nitsi:BAAALgAECgEJAQABLgAECgkJNQAfAKAaAA==.',
No='Nocturnum:BAABLgAECn9AAAIMAAkJcxw3GACEAgAMAAkJcxw3GACEAgAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8KAAIhAAUJQRdPAABcAQAhAAUJQRdPAABcAQAuAAQKfxwAAiEACAktHi8BAPECACEACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAABLgAFFAMJAwACAAAAAA==.Odin:BAAALgAECgEJAgAAAA==.Odium:BAAALgADCgMJAwABLgAFFAUJEQAKAFchAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAgJGQAZAKYfAA==.',
Ol='Oldage:BAAALgAECgkJEgABLgAECgkJFAAQACQYAA==.Oldmage:BAAALgAECgYJCAAAAA==.Oldmongerpal:BAAALgAECgEJAgAAAA==.',
On='Onetwocowpow:BAABLgAECn9IAAIDAAkJ+hhqFQBuAgADAAkJ+hhqFQBuAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn9ZAAMFAAkJViJwDwATAwAFAAkJViJwDwATAwAGAAkJTBelCQA0AgAAAA==.Orionn:BAACLgAFFH8YAAIKAAUJRSC0CQAUAQAKAAUJRSC0CQAUAQAuAAQKf0gAAgoACQm2JcgEAEQDAAoACQm2JcgEAEQDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAABLgAECn8cAAIKAAkJWw5oSgDCAQAKAAkJWw5oSgDCAQAAAA==.',
Ov='Oven:BAABLgAECn8gAAIUAAgJVxYLIgCfAQAUAAgJVxYLIgCfAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.Patelz:BAAALgADCgQJBAAAAA==.',
Pe='Petoria:BAAALgADCgUJBQAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pinksparkle:BAAALgAECgkJCQAAAA==.Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQABLgAECgkJDwACAAAAAA==.Polyeikon:BAAALgAECgYJCwAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgAECgMJBAAAAA==.Prayr:BAAALgAECgIJAgAAAA==.Praystation:BAAALgAECgUJCwAAAA==.Problem:BAAALgAECgEJAQAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgYJCwAAAA==.',
Ra='Raekeshh:BAABLgAECn8ZAAISAAkJ3BWcNAAGAgASAAkJ3BWcNAAGAgAAAA==.Raelone:BAABLgAECn8dAAQRAAkJGBGtIwCUAAASAAUJYg3LqgDtAAARAAYJZBKtIwCUAAAhAAEJ5RNGNwBHAAAAAA==.Rageofmommy:BAAALgAECgMJBAAAAA==.Raidoe:BAABLgAECn9LAAMDAAkJKRz/DwClAgADAAkJKRz/DwClAgAUAAMJOQsIdQBmAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn81AAIKAAkJfRk+MAAbAgAKAAkJfRk+MAAbAgAAAA==.Rant:BAAALgAECgYJCwAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.Razorbeams:BAAALgAECgQJBQABLgAECgkJWwAdADgdAA==.',
Re='Redishpanda:BAAALgADCgcJFAAAAA==.Redshammy:BAAALgAFFAIJAwAAAA==.Relion:BAAALgAECggJEwABLgAECgkJRAAFAJASAA==.Reo:BAAALgAFFAEJAQABLgAFFAYJIQADACUgAA==.',
Rh='Rheavin:BAAALgADCgUJCgAAAA==.Rhell:BAACLgAFFH8OAAIHAAQJqhPIKADeAAAHAAQJqhPIKADeAAAuAAQKfzkAAwcACQnkIWsIAAUDAAcACQnkIWsIAAUDAAUAAQkUAvXRARYAAAAA.',
Ri='Rinche:BAABLgAECn9FAAMXAAkJNxa/GwADAgAXAAkJNxa/GwADAgATAAkJ3guyUgBoAQAAAA==.Rintche:BAAALgAECgUJBQAAAA==.Rivers:BAAALgAECgQJBQABLgAECgkJFAAQACQYAA==.',
Ro='Rolland:BAABLgAECn8lAAIZAAkJeyD9AQDoAgAZAAkJeyD9AQDoAgAAAA==.Rollf:BAAALgAECgMJAwAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAABLgAECn8hAAMSAAkJOAvmWgCNAQASAAkJOAvmWgCNAQARAAQJ1wTVKQBuAAAAAA==.',
Ru='Rubèus:BAAALgAECgEJAQAAAA==.Rudo:BAABLgAECn8fAAMKAAkJxRVZIgA3AgAKAAkJxRVZIgA3AgAYAAEJrgLYagAnAAAAAA==.Rumproblem:BAABLgAECn9AAAMIAAkJTBg6DwB7AgAIAAkJTBg6DwB7AgAJAAkJ1w5GBgD+AAAAAA==.Runekaiser:BAAALgAECgMJCQAAAA==.Runnamuuk:BAABLgAECn82AAIMAAkJGBTzNgDqAQAMAAkJGBTzNgDqAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryegar:BAAALgADCgkJCQAAAA==.Ryeger:BAABLgAECn9RAAMiAAkJWyJQAADHAgAiAAkJWyJQAADHAgAeAAMJpgs0ZgCFAAAAAA==.',
['Rá']='Ráh:BAAALgADCgEJAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn83AAIjAAkJ3BZXEQDXAQAjAAkJ3BZXEQDXAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBQABLgAECgMJDQACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn9EAAMFAAkJkBJIBQDCAQAFAAkJkBJIBQDCAQAHAAkJYwMMRQAsAQAAAA==.Sandbones:BAAALgAECgUJDAABLgAECgkJWwAdADgdAA==.Sandraice:BAABLgAECn8fAAIFAAgJ0QYyhwBsAQAFAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sanielan:BAAALgAECgYJCwAAAA==.Sansami:BAABLgAECn8/AAIfAAkJ1xsIFwDxAQAfAAkJ1xsIFwDxAQAAAA==.Saphron:BAAALgAECgQJBAAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAABLgAECn8tAAMeAAcJJQphCQCpAAAeAAcJJQphCQCpAAAEAAUJDQMlqwBfAAAAAA==.',
Sc='Sc:BAAALgAECgcJCgABLgAECgkJKgAVAE4jAA==.Scalebagz:BAABLgAECn8gAAMkAAkJSB4WBgCoAgAkAAkJSB4WBgCoAgAOAAgJvRyYIADUAQAAAA==.Schism:BAAALgAECgEJAQAAAA==.Schitzøø:BAAALgAECgEJAQAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgAECgQJBAAAAA==.Senyorseven:BAAALgAECgYJDgAAAA==.Seo:BAAALgAECgQJCQAAAA==.Serabeara:BAAALgAECgIJAgAAAA==.Setresh:BAABLgAECn9ZAAIYAAkJwhU6AgBjAQAYAAkJwhU6AgBjAQAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadowcloak:BAAALgAECgUJBQAAAA==.Shadöwsöng:BAACLgAFFH8JAAIbAAMJKAUkDwB6AAAbAAMJKAUkDwB6AAAuAAQKf0AAAhsACAneC4whACMBABsACAneC4whACMBAAAA.Shaedelana:BAABLgAECn8fAAQIAAgJJhucPAAcAQAIAAUJShOcPAAcAQAJAAYJKBR8CADKAAAcAAYJIByfCQCXAAAAAA==.Shamrox:BAABLgAECn8WAAIXAAgJvQrLCADHAAAXAAgJvQrLCADHAAAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJMwAEABMfAA==.Shinnobi:BAAALgAECgcJBwAAAA==.Shinygoat:BAAALgADCgIJAgABLgAECgkJKgAPAI8fAA==.Shivyn:BAACLgAFFH8IAAITAAMJBRWhGgC5AAATAAMJBRWhGgC5AAAuAAQKfz8AAxMACQlMGs4PANMCABMACQlMGs4PANMCABcAAQkXBbmNACoAAAAA.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAgJGQAZAKYfAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAACLgAFFH8SAAMNAAMJzhKlMADbAAANAAMJ9hClMADbAAAgAAIJrwtwNABnAAAuAAQKfy4AAw0ACQmlGVFIAOkBAA0ACQmlGVFIAOkBACAABQmtD1UuAMwAAAAA.Sickkid:BAABLgAECn9HAAIWAAgJ9SKsCQDIAgAWAAgJ9SKsCQDIAgAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silkiegirl:BAABLgAECn8iAAIWAAkJzhQeGgAdAgAWAAkJzhQeGgAdAgAAAA==.Silvador:BAAALgAECgIJAwABLgAFFAIJBgAOAFYCAA==.Silvershine:BAABLgAECn8VAAMEAAYJ6w4lgADaAAAEAAUJiAslgADaAAAiAAQJuAYsNwB/AAAAAA==.Silverwolf:BAAALgAECgIJAgAAAA==.Sindrya:BAAALgAECgUJBwAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slayne:BAAALgAECgEJAQAAAA==.Slaänesh:BAAALgADCgcJBwABLgAECgkJMwAEABMfAA==.Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJDAACAAAAAA==.Smashßros:BAAALgAECgQJBAABLgAFFAMJBgAWAGgRAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgkJEAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgABLgAFFAMJCQANAEMgAA==.Snooker:BAAALgADCgEJAQAAAA==.Snuggles:BAABLgAECn8mAAILAAgJjxoCEwD/AQALAAgJjxoCEwD/AQABLgAFFAYJHQAYAHcUAA==.',
So='Solidgen:BAEALgAECgEJAgABLgAFFAcJGgAFAGAQAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Sonofalich:BAAALgAECgkJCQAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAABLgAECn8WAAMbAAgJNRa8FwCDAQAbAAgJNRa8FwCDAQAaAAMJUgOpNABeAAAAAA==.Spinach:BAAALgAECgEJAQAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgQJDgAAAA==.',
Ss='Ssraeshza:BAABLgAFFH8LAAIjAAYJphi0CABoAQAjAAYJphi0CABoAQAAAA==.',
St='Staretra:BAABLgAECn9BAAMJAAkJOBILHQDcAQAJAAkJOBILHQDcAQAcAAQJowboUwCNAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.Stusey:BAAALgADCgIJAgAAAA==.',
Su='Sublevels:BAAALgADCgYJBgAAAA==.Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECggJEQAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Sylph:BAAALgAECgUJBQAAAA==.Symana:BAABLgAECn85AAIcAAkJKB5bCwCxAgAcAAkJKB5bCwCxAgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgAECgEJAQAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgcJEQAAAA==.',
['Sö']='Sörceress:BAAALgAECgYJEwAAAA==.',
Ta='Taadra:BAABLgAECn9fAAITAAkJvCDjCQAWAwATAAkJvCDjCQAWAwAAAA==.Talerah:BAAALgAECgUJCQAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAACLgAFFH8iAAMEAAUJcRzTGACXAQAEAAUJcRzTGACXAQAeAAEJfANpIwArAAAuAAQKfxgAAwQACQnvF2YeAEwCAAQACQnvF2YeAEwCACMAAgkPE1ZOAHMAAAAA.Talona:BAAALgAFFAEJAQABLgAFFAUJCgAhAEEXAA==.Tandaan:BAAALgADCgkJCgABLgAECgkJGQASANwVAA==.Tanjent:BAABLgAECn8jAAIKAAYJDA3NHACSAAAKAAYJDA3NHACSAAAAAA==.Tanok:BAAALgADCgYJBgAAAA==.Tapio:BAABLgAECn80AAIYAAgJzxiwAgA7AQAYAAgJzxiwAgA7AQAAAA==.Tatsuma:BAAALgAECgYJDgABLgAECgkJJQAFAPobAA==.Tatsumå:BAAALgAECgcJEgABLgAECgkJJQAFAPobAA==.Tavvi:BAAALgAECgYJBgABLgAECgcJFgAKAN0iAA==.Tazz:BAAALgAECgIJAgAAAA==.',
Te='Terp:BAAALgAECgMJBwAAAA==.',
Th='Thalfinore:BAAALgAECgcJEgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Therogue:BAAALgAECgIJAgAAAA==.Thoghar:BAAALgAECgEJAQAAAA==.Thorincan:BAAALgAECgkJCQAAAA==.Thorrs:BAAALgAECgIJBwAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thorwar:BAAALgADCgMJBAAAAA==.Thuglifé:BAAALgAECgEJAQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECggJDAACAAAAAA==.Tidemaiden:BAABLgAECn8WAAMTAAgJywwiFQBrAAATAAcJPgkiFQBrAAAmAAEJRQfjDgAqAAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgABLgAFFAMJAwACAAAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tinypickles:BAAALgAECgMJAwAAAA==.Tipsymancer:BAABLgAECn9IAAIfAAkJDSLwAwAOAwAfAAkJDSLwAwAOAwAAAA==.Tirael:BAAALgAECgYJBQABLgAFFAYJAQACAAAAAA==.Tishi:BAAALgAECgEJAQAAAA==.',
To='Tomö:BAAALgAECgkJBAAAAA==.Tossme:BAAALgAECgEJAQABLgAFFAQJEQAfAJ4gAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Traeicel:BAAALgAECggJBAAAAA==.Treesus:BAABLgAECn8fAAIeAAkJLhqWGwAmAgAeAAkJLhqWGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECgkJHwAKAMUVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Ts='Tsu:BAAALgADCgkJCQAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.Tyzi:BAAALgAECgEJAQAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQVAAgJ+iNmNwA7AgAVAAgJXCFmNwA7AgAdAAMJPCQECAAkAQAoAAEJTQ0VDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8lAAIEAAkJsRiVIgA0AgAEAAkJsRiVIgA0AgAAAA==.',
Un='Undeadgnome:BAAALgAECgMJAwAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.Usër:BAAALgAECgQJBwAAAA==.',
Va='Vainin:BAABLgAECn8VAAIVAAYJsgcL5ADVAAAVAAYJsgcL5ADVAAAAAA==.Valle:BAAALgAFFAEJAQAAAA==.Valry:BAAALgAECgYJDgAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAQJBwAbAEkXAA==.Vankro:BAAALgAFFAEJAgABLgAFFAQJGQAPACMmAA==.Variable:BAAALgAECgcJBwAAAA==.Vashdin:BAABLgAECn8xAAIFAAgJjR64CQBOAQAFAAgJjR64CQBOAQAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECgkJHwAKAMUVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velaronia:BAAALgAECgQJBAAAAA==.Velashis:BAABLgAECn9HAAMEAAkJnCDKAADkAgAEAAkJnCDKAADkAgAeAAIJ5QyfeABVAAAAAA==.Velathadora:BAAALgAECgEJAQAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAABLgAFFH8IAAIXAAMJrBDJNQC3AAAXAAMJrBDJNQC3AAAAAA==.Vett:BAAALgADCgMJAwABLgAECgYJFQAVALIHAA==.Vexable:BAAALgAECgQJBAAAAA==.',
Vi='Viable:BAAALgAECgUJCgAAAA==.Vibes:BAAALgAECgkJCwAAAA==.Victorvega:BAAALgAECgMJAwABLgAECgkJHwAKAMUVAA==.Vicvega:BAAALgAECgQJBQABLgAECgkJHwAKAMUVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8QAAMDAAMJtRIWPAC1AAADAAMJtRIWPAC1AAAUAAIJlxlmLwCIAAAuAAQKfyYAAxQACQndHRcQAH8CABQACAmuHRcQAH8CAAMABQnvH+lUAB0BAAAA.Vivila:BAAALgAECgMJBQABLgAECgkJSAAMAPwbAA==.Vivillian:BAABLgAFFH8HAAIIAAMJjg98MwC+AAAIAAMJjg98MwC+AAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Voidrèaper:BAAALgAECgEJAQAAAA==.Vordilina:BAABLgAECn8cAAQoAAkJqhgPAgBYAgAoAAkJqhgPAgBYAgAdAAEJuAV9IAAtAAAVAAEJrQHbiAEcAAAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQkAAgJKhn4EwAGAgAkAAgJKhn4EwAGAgAlAAQJxRh7FQC6AAAOAAEJygMInQAkAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAABLgAECn9BAAMTAAgJlhnKNADeAQATAAgJlhnKNADeAQAXAAgJOxrmJgC0AQAAAA==.Vugowulf:BAAALgAECgEJAgAAAA==.',
Vy='Vynae:BAAALgADCgcJBAAAAA==.',
['Vé']='Véxx:BAABLgAECn8yAAQPAAkJuh7cBABnAgAPAAkJuh7cBABnAgALAAUJYAizQgDtAAAMAAEJdAGj9QAZAAAAAA==.',
['Vì']='Vìx:BAAALgAECgEJAQAAAA==.',
['Ví']='Víx:BAAALgAECggJCAAAAA==.',
['Vî']='Vîper:BAAALgAFFAEJAQAAAA==.',
['Vï']='Vïx:BAAALgADCgUJBQAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Warihor:BAABLgAECn8vAAMaAAgJeQyTMAAGAQAWAAgJIwq1QABCAQAaAAgJhQmTMAAGAQAAAA==.Waycaps:BAABLgAFFH8FAAIjAAQJUBUQEAAIAQAjAAQJUBUQEAAIAQAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAACLgAFFH8UAAIhAAUJbiTjAQCjAQAhAAUJbiTjAQCjAQAuAAQKfy4AAiEACQk/JMAAACEDACEACQk/JMAAACEDAAAA.',
Wh='Whïte:BAAALgAECgEJAgAAAA==.',
Wi='Wiegraf:BAAALgAECgIJAwABLgAECgkJMwAEABMfAA==.Wife:BAAALgAECgMJAwAAAA==.Wildhide:BAAALgAECgcJBwAAAA==.Withers:BAAALgADCgQJBAAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJDQAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECggJDAAAAA==.',
['Wä']='Wärbëef:BAAALgADCgEJAQAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECggJDAACAAAAAA==.',
Xo='Xorxel:BAAALgAECgQJCAAAAA==.',
Ya='Yacob:BAABLgAECn83AAMcAAkJOx0jCgDFAgAcAAkJOx0jCgDFAgAJAAIJ6hOtDQByAAAAAA==.Yacobge:BAAALgAECgYJBgAAAA==.',
Ye='Yenneferr:BAAALgAECgkJAQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8zAAIEAAkJEx+HCwAGAwAEAAkJEx+HCwAGAwAAAA==.',
Yh='Yhwach:BAACLgAFFH8MAAIgAAYJZA13JADLAAAgAAYJZA13JADLAAAuAAQKfyUAAiAACAk+GfkCAF4BACAACAk+GfkCAF4BAAAA.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAABLgAFFH8MAAIFAAQJGBM6HQDiAAAFAAQJGBM6HQDiAAABLgAECgkJFAAQACQYAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECggJDAAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgcJCwAAAA==.',
Za='Zaeden:BAABLgAECn8dAAIDAAcJDh+fFgANAgADAAcJDh+fFgANAgABLgAECgkJGgANAK0gAA==.Zaft:BAAALgADCgYJBgAAAA==.Zaftdh:BAABLgAECn81AAIMAAkJqhVXNAD1AQAMAAkJqhVXNAD1AQAAAA==.Zaha:BAABLgAECn8eAAIVAAYJ2iKdXAAkAgAVAAYJ2iKdXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zappsz:BAAALgAECggJDwAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zedfrey:BAABLgAECn9HAAIFAAkJ3hn4BQCpAQAFAAkJ3hn4BQCpAQAAAA==.Zedra:BAAALgAECgMJAwAAAA==.Zem:BAABLgAECn8rAAIWAAgJux8tEgBiAgAWAAgJux8tEgBiAgAAAA==.Zemangoose:BAAALgAECgYJBgAAAA==.Zeroultra:BAABLgAECn86AAIWAAkJxB3PEQBmAgAWAAkJxB3PEQBmAgAAAA==.Zeräse:BAABLgAECn8VAAIIAAgJRw//JACnAQAIAAgJRw//JACnAQABLgAECgkJMwAEABMfAA==.Zeusdh:BAAALgADCgkJCQAAAA==.Zeusmos:BAABLgAECn9GAAIUAAkJ3iY4AACVAwAUAAkJ3iY4AACVAwAAAA==.',
Zi='Zithenex:BAABLgAECn9BAAIlAAgJNRd9CQCRAQAlAAgJNRd9CQCRAQAAAA==.',
Zo='Zoeÿ:BAAALgAECgEJBAAAAA==.',
Zu='Zugnugs:BAAALgAECgMJAQAAAA==.',
Zw='Zwar:BAAALgAECgIJAgAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAABLgAECn8vAAIWAAcJjxV7BwD4AAAWAAcJjxV7BwD4AAAAAA==.',
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
