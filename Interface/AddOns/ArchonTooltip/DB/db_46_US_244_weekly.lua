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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Priest-Discipline','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Augmentation','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Warrior-Fury','Shaman-Elemental','Hunter-Survival','Warrior-Arms','Warrior-Protection','Priest-Holy','Mage-Arcane','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Shaman-Enhancement','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-06-21',data={Aa='Aaminae:BAABLgAECn88AAIBAAkJkxgoDQBUAgABAAkJkxgoDQBUAgAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgUJCgAAAA==.Abracastabya:BAAALgAFFAEJAQAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.Absolution:BAAALgAECgQJBQAAAA==.Abÿss:BAAALgAECgYJBgAAAA==.',
Ad='Adachï:BAABLgAECn8WAAIDAAYJiRptNQCfAQADAAYJiRptNQCfAQABLgAECgkJMwAEABMfAA==.Adevil:BAAALgAECgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aegon:BAAALgADCgkJCQAAAA==.Aethlin:BAABLgAECn86AAMFAAkJ6xyiAACNAQAGAAkJjRnLMgA1AgAFAAgJhh2iAACNAQAAAA==.Aetreyu:BAAALgAECgcJEgAAAA==.Aeturnas:BAABLgAECn8yAAIHAAkJ7B+jCAABAwAHAAkJ7B+jCAABAwAAAA==.',
Ag='Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanima:BAABLgAECn8dAAMIAAgJjQztKgB+AQAIAAgJjQztKgB+AQAJAAYJ3AbXUQDKAAAAAA==.Albus:BAAALgAECgEJAQAAAA==.Aldky:BAAALgADCgkJDgAAAA==.Aliana:BAAALgAFFAEJAQAAAA==.Alinthe:BAAALgADCgkJCQAAAA==.Allindis:BAAALgAECgYJCQABLgAECgkJJQAEALEYAA==.Allypally:BAAALgAECgEJAQAAAA==.Alphamage:BAAALgADCggJCAAAAA==.Alphamonk:BAAALgAECgkJEQAAAA==.Alros:BAABLgAECn9QAAIKAAkJkSN2AADvAgAKAAkJkSN2AADvAgAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgAECgQJCAAAAA==.',
Am='Amardyton:BAAALgAECgYJBwAAAA==.',
An='And:BAABLgAECn8sAAMLAAgJThS8AQDpAAALAAgJThS8AQDpAAAMAAEJ6QOYOAEcAAAAAA==.Aneas:BAAALgAECgYJDwAAAA==.Antäres:BAAALgADCgQJBAABLgAECgkJMwAEABMfAA==.',
Ap='Apolex:BAAALgADCgUJBQAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgMJAwACAAAAAA==.Arctica:BAAALgADCgQJBAAAAA==.Arette:BAAALgAECgcJBwAAAA==.Arkades:BAABLgAECn8hAAIGAAkJrxtkIwB4AgAGAAkJrxtkIwB4AgAAAA==.Arkshade:BAABLgAECn83AAINAAcJfhLdfgBmAQANAAcJfhLdfgBmAQAAAA==.Arlia:BAAALgAECgkJEQABLgAFFAIJBgAOAFYCAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECgkJKgAPAI8fAA==.Aryn:BAAALgAECgEJAQAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgYJCwACAAAAAA==.Ashor:BAAALgAECgIJAgAAAA==.Asmo:BAAALgADCggJGAAAAA==.Aspir:BAEALgAECgYJBgABLgAFFAcJGAAQABwWAA==.Astarii:BAAALgAECgEJBQAAAA==.Asterica:BAABLgAECn9RAAIRAAkJWBi5MQARAgARAAkJWBi5MQARAgAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.Atormunster:BAAALgADCgMJAwABLgAECggJJQASAB4QAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAITAAYJ+A16UwA4AQATAAYJ+A16UwA4AQAAAA==.',
Av='Averynicole:BAABLgAECn8ZAAIUAAcJBxYKLABfAQAUAAcJBxYKLABfAQAAAA==.',
Aw='Awasjr:BAABLgAECn8mAAIKAAkJlh/JGACSAgAKAAkJlh/JGACSAgAAAA==.Awassy:BAAALgAECgEJAgAAAA==.',
Ay='Ayano:BAABLgAECn8WAAIVAAgJYh6zSgD7AQAVAAgJYh6zSgD7AQAAAA==.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balanla:BAAALgAECgMJAwABLgAECgkJNAAWABgjAA==.Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDwABLgAECgkJMwAEABMfAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgAECgEJAQAAAA==.Bearhug:BAACLgAFFH8GAAMDAAIJBwuDUgBfAAADAAIJBwuDUgBfAAAUAAEJoAHBSgApAAAuAAQKfy8AAwMACAn1GnY8AH4BAAMABwntGXY8AH4BABQABwleCYFCAA0BAAEuAAUUBAkNABcA/QoA.Bearshock:BAACLgAFFH8NAAMXAAQJ/QpDLQDfAAAXAAQJ/QpDLQDfAAATAAEJTACPjwAdAAAuAAQKfxwAAhcACAl7G5IUAEYCABcACAl7G5IUAEYCAAAA.Beasty:BAABLgAECn8lAAMSAAgJHhCvEQBAAQASAAgJHhCvEQBAAQAYAAYJhwTyPQDUAAAAAA==.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAABLgAECn83AAIFAAkJ5CT2AABUAwAFAAkJ5CT2AABUAwAAAA==.Beeb:BAAALgAECgUJDgABLgAECgkJNwAFAOQkAA==.Beefisting:BAAALgAECgYJDAABLgAECgkJNwAFAOQkAA==.Beethicc:BAAALgAECgEJBAABLgAECgkJNwAFAOQkAA==.Beeuwu:BAAALgAECgIJAwABLgAECgkJNwAFAOQkAA==.Beliara:BAAALgAECgkJDQAAAA==.Belijoe:BAAALgAECgEJAQAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Belshuntress:BAAALgAECgEJAgAAAA==.Beverage:BAAALgAECgEJAQAAAA==.',
Bi='Bicboi:BAAALgAECgEJAQAAAA==.Bigmattyl:BAAALgAECgcJCgAAAA==.Bionarra:BAABLgAECn81AAIVAAkJjR1GAQAMAgAVAAkJjR1GAQAMAgAAAA==.Bishopwr:BAABLgAECn8oAAMZAAkJ8BZRDAAiAgAZAAkJ8BZRDAAiAgAaAAYJCwohMwCvAAAAAA==.Bittertøfu:BAABLgAECn8eAAIXAAcJfQb8WQDWAAAXAAcJfQb8WQDWAAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJCgAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blessu:BAAALgAECgEJAQAAAA==.Blitê:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Bm='Bmpfrostie:BAABLgAECn8UAAIVAAcJdg01yABYAQAVAAcJdg01yABYAQAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECgkJNgAbADsdAA==.Bohica:BAAALgAECggJDgAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAABLgAFFAMJCQANAEMgAA==.',
Br='Brakug:BAABLgAECn8vAAMVAAkJHiMULgC5AgAVAAkJHiMULgC5AgAcAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAIJAwAAAA==.Brem:BAACLgAFFH8IAAIcAAMJiBnrAQD5AAAcAAMJiBnrAQD5AAAuAAQKfxsAAhwACAmCHB4EABICABwACAmCHB4EABICAAAA.Bretagnesse:BAABLgAECn8UAAIdAAgJ2wXGRQD1AAAdAAgJ2wXGRQD1AAAAAA==.Briara:BAAALgAECgYJDwAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgAECgQJBgAAAA==.Broníx:BAAALgAECgEJBQAAAA==.Bropeep:BAACLgAFFH8FAAINAAMJChunjgDtAAANAAMJChunjgDtAAAuAAQKf1EAAw0ACQkbJT0EAF4DAA0ACQkbJT0EAF4DABAABAmdFKMcAOkAAAAA.Brotality:BAAALgADCgMJBAAAAA==.Brynhildr:BAAALgAECgcJDwABLgAFFAQJDAAeAJ4gAA==.',
Bu='Bullshott:BAABLgAECn8jAAIKAAkJrx1tHQB1AgAKAAkJrx1tHQB1AgAAAA==.Bum:BAABLgAECn8mAAMdAAkJsh/4BABRAwAdAAkJsh/4BABRAwAEAAEJ0xCM0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgAECgUJCQAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJEQAAAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBgAAAA==.',
['Bú']='Búll:BAAALgADCgQJBAAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAABLgAECn8cAAMNAAgJYxC9bgCHAQANAAgJ+g69bgCHAQAfAAYJdA1kMgDTAAABLgAECggJOwAeAH0RAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8zAAIGAAkJXQgNjABZAQAGAAkJXQgNjABZAQAAAA==.Carrots:BAABLgAECn8vAAIKAAkJBxWcSADIAQAKAAkJBxWcSADIAQAAAA==.Cartman:BAABLgAFFH8GAAIaAAQJSRfXEwAFAQAaAAQJSRfXEwAFAQAAAA==.Cashmachine:BAABLgAECn8tAAIKAAkJAx8XGwCDAgAKAAkJAx8XGwCDAgAAAA==.Castorice:BAAALgAECgEJAQAAAA==.Catfight:BAABLgAECn88AAIFAAgJrQ/PHQAmAQAFAAgJrQ/PHQAmAQAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMRAAkJdBhqLgBTAgARAAkJdBhqLgBTAgAgAAEJAABoZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8OAAQKAAUJcR8UNQBDAQAKAAUJTR4UNQBDAQASAAEJISI3IwBlAAAYAAEJzA97MgBIAAAuAAQKfxwABBIACAmLIsIYAGYCABIACAkjIcIYAGYCAAoABQlPHXZcAJABABgAAwkrGAhMAIUAAAAA.Cheesecake:BAABLgAECn8yAAMgAAkJbBA+DAB7AQAgAAgJBRI+DAB7AQAhAAMJMgtqAgBxAAAAAA==.Chelsie:BAAALgADCgUJBQABLgAFFAQJDAAeAJ4gAA==.Chihiko:BAAALgAECgMJAwAAAA==.Choks:BAABLgAECn8yAAIWAAgJsQ12AwDAAAAWAAgJsQ12AwDAAAAAAA==.Chromie:BAAALgADCgMJAwAAAA==.Chubbycat:BAABLgAECn8VAAMEAAcJLhmOPQCuAQAEAAcJLhmOPQCuAQAiAAUJYh34FwBTAQAAAA==.Chuggz:BAABLgAECn81AAIeAAkJoBpRDQBjAgAeAAkJoBpRDQBjAgAAAA==.Chéfboyrlee:BAACLgAFFH8ZAAIJAAgJhRe1BQAjAgAJAAgJhRe1BQAjAgAuAAQKfzYAAgkACQn6IroEAAwDAAkACQn6IroEAAwDAAAA.',
Ci='Cizmac:BAAALgAECgYJDAAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgADCggJDAAAAA==.Cownado:BAABLgAECn87AAIeAAgJfRFnAQDbAAAeAAgJfRFnAQDbAAAAAA==.',
Cr='Crematorion:BAAALgAECgMJAwAAAA==.Crippin:BAAALgAECgEJAQAAAA==.Crouton:BAAALgADCgkJCgAAAA==.',
Cu='Cursedspirit:BAAALgAECgQJBwAAAA==.',
Cy='Cybelem:BAABLgAECn8tAAIXAAkJmB5ZEABwAgAXAAkJmB5ZEABwAgAAAA==.Cyfelen:BAABLgAECn8ZAAQgAAkJiB9oAQDWAgAgAAkJiB9oAQDWAgAhAAQJLxmwHQDSAAARAAIJrw+I+AByAAAAAA==.Cynleel:BAAALgAECggJEAABLgAECgkJNAAIAM8RAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQAAAA==.Damonstyle:BAAALgAECgEJAgAAAA==.Dandistyle:BAABLgAECn8fAAMeAAkJdx1jCwB+AgAeAAkJbh1jCwB+AgAUAAEJchK2fAAzAAAAAA==.Darknature:BAAALgAECgkJCQAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathblade:BAAALgAECgEJAQAAAA==.Deathmatrynn:BAAALgAECgYJDgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAACLgAFFH8FAAIXAAIJ2gUkSwBnAAAXAAIJ2gUkSwBnAAAuAAQKfxUAAhcACAnaFl8eAO8BABcACAnaFl8eAO8BAAAA.Deeviant:BAAALgAECggJDgAAAA==.Defend:BAAALgAFFAMJAwABLgAFFAQJBgAaAEkXAA==.Delrager:BAACLgAFFH8HAAIBAAIJch5sLwCtAAABAAIJch5sLwCtAAAuAAQKfygAAgEABwmYI3YNAFACAAEABwmYI3YNAFACAAAA.Delyta:BAAALgAECgkJCQAAAA==.Demidru:BAAALgAECggJCAAAAA==.Demonicdawn:BAAALgADCgEJAQAAAA==.Demónícz:BAAALgAECgMJAwAAAA==.Derat:BAAALgAECgkJEQAAAA==.Destroy:BAABLgAFFH8GAAIRAAMJpQNYDgClAAARAAMJpQNYDgClAAABLgAFFAQJBgAaAEkXAA==.',
Di='Dibbydab:BAABLgAECn8iAAITAAkJcxMTOgDGAQATAAkJcxMTOgDGAQAAAA==.',
Dj='Django:BAABLgAECn82AAMdAAkJsyIeBgD2AgAdAAkJsyIeBgD2AgAEAAIJkAbIxgA+AAAAAA==.Djatalon:BAABLgAECn8WAAMjAAUJuAsVIwDWAAAjAAUJuAsVIwDWAAAkAAMJrAUaHABsAAAAAA==.Djderpyderpy:BAAALgAECgYJDQAAAA==.Djehrtey:BAAALgAECgcJCQAAAA==.Djin:BAAALgAECgMJBAABLgAFFAQJDAAeAJ4gAA==.Djinni:BAACLgAFFH8MAAIeAAQJniDCEwCFAQAeAAQJniDCEwCFAQAuAAQKfzUAAx4ACQk9IXkGANMCAB4ACAlsI3kGANMCABQACQkSG6gOAF4CAAAA.',
Dk='Dkota:BAAALgAECgUJBAAAAA==.',
Do='Dobath:BAAALgADCgQJBAAAAA==.Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8fAAMQAAgJtxtyCAAHAgAQAAgJtxtyCAAHAgANAAMJsA2A/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8YAAQjAAcJNxmBDwDUAQAjAAcJNxmBDwDUAQAOAAQJuwzhYQC1AAAkAAEJAACAPAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Draknem:BAAALgAECgIJAgAAAA==.Dramaticus:BAAALgAECgQJBAAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drenleah:BAABLgAECn8XAAIgAAkJpRZ0BQAZAgAgAAkJpRZ0BQAZAgABLgAECgkJSAAMAAscAA==.Drenlee:BAAALgAECgEJAgABLgAECgkJSAAMAAscAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgAAAA==.Dryya:BAAALgAECgQJCAAAAA==.Drêck:BAAALgAECgEJAQAAAA==.',
Du='Dumblegear:BAABLgAECn8fAAMVAAgJpRVRbACiAQAVAAgJpRVRbACiAQAcAAEJbQY0IAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAECgkJNAAWABgjAA==.',
Dw='Dwagon:BAAALgADCgUJBQAAAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgADCgQJCAAAAA==.Dädärkbeëf:BAAALgADCgcJCQAAAA==.',
Ed='Edinna:BAABLgAECn89AAMVAAkJ7BrRAACHAgAVAAkJ7BrRAACHAgAcAAQJTQoTEADBAAAAAA==.',
Ee='Eevie:BAAALgADCgMJBgAAAA==.',
Ei='Einekliene:BAAALgAECgcJBwAAAA==.',
Ek='Ekatrina:BAAALgAECgEJAQAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Eldernoc:BAAALgAECgUJDwAAAA==.Elessedil:BAAALgAECggJDgAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgYJDAAAAA==.Elyriana:BAABLgAECn8jAAMEAAkJpSAKCQAoAwAEAAkJpSAKCQAoAwAiAAEJqSBpQQBZAAAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEBLgAECn8gAAIKAAYJPyIMAwBtAQAKAAYJPyIMAwBtAQABLgAECggJKQAKANMgAA==.Emixi:BAAALgAECgQJBQAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECggJDwAAAA==.Emritelan:BAAALgADCgkJEAAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8YAAIGAAYJixdxJgBvAQAGAAYJixdxJgBvAQAuAAQKfzEAAgYACQmaHwElAHACAAYACQmaHwElAHACAAAA.',
Ep='Epedemik:BAAALgAECgMJAwAAAA==.',
Er='Erazath:BAAALgAECgUJBgABLgAFFAMJBwAfAI8JAA==.Eredo:BAAALgAECgUJCgABLgAECgkJNAAWABgjAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgAECgIJAgAAAA==.Erush:BAAALgAECgEJAQAAAA==.',
Es='Esha:BAAALgAECgEJAQAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ex='Exhul:BAAALgAECgEJAQAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Faewing:BAABLgAFFH8GAAIOAAIJVgJ8XgBcAAAOAAIJVgJ8XgBcAAAAAA==.Falar:BAAALgAECggJDQAAAA==.Fatelf:BAAALgADCgMJAwAAAA==.Fatowlbert:BAAALgAECgEJAgAAAA==.Faval:BAAALgAECggJDwABLgAECgkJKgAPAI8fAA==.Favel:BAABLgAECn8qAAMPAAkJjx9OAQAcAwAPAAgJ4iFOAQAcAwAMAAkJRwv7XwBpAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn9VAAIKAAkJxhvxAABfAgAKAAkJxhvxAABfAgAAAA==.Febz:BAABLgAECn8eAAIVAAgJbBsqMACyAgAVAAgJbBsqMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAABLgAECn8aAAIMAAgJZh/zIgBFAgAMAAgJZh/zIgBFAgAAAA==.Felfüry:BAACLgAFFH8LAAMLAAMJ8QdABAB1AAALAAMJ8QdABAB1AAAPAAMJxwNXEABOAAAuAAQKf0cABAsACQm/FEUTAPwBAAsACQm/FEUTAPwBAA8ACAmJCb4WAPEAAAwAAglYCZIGAUQAAAAA.Felly:BAAALgAECgYJBgAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Festicules:BAAALgAECgQJBAAAAA==.Festyr:BAAALgAECgQJCAAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECgUJBwACAAAAAA==.Finella:BAABLgAECn8UAAMQAAkJJBipCAABAgAQAAkJjhOpCAABAgAfAAYJaxYKJgAjAQAAAA==.Finneas:BAAALgAECgEJAwABLgAECgkJIQAGAK8bAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJLwAVAB4jAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgkJFAAQACQYAA==.',
Fo='Fogassann:BAABLgAECn8UAAINAAgJXBwWKwBUAgANAAgJXBwWKwBUAgABLgAECgkJNAAWABgjAA==.Fogdemon:BAAALgAECgIJBAABLgAFFAUJFwAhAHMUAA==.Foggpy:BAACLgAFFH8XAAMhAAUJcxR+BQAvAQAhAAUJcxR+BQAvAQARAAQJnwOKcwDaAAAuAAQKfycABCEACAmeInUEADYCACEABwkkJXUEADYCABEABgkNG8FXAMABACAABgljGQ4fAFgBAAAA.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freinkenbaby:BAAALgAECgEJAQAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostlicious:BAAALgADCgEJAQAAAA==.Frostnuts:BAAALgAECgEJAQAAAA==.Frostybear:BAABLgAECn9JAAIVAAkJAhpRLABoAgAVAAkJAhpRLABoAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAABLgAECn9CAAMfAAkJfAvyIQBDAQAfAAkJaQvyIQBDAQAQAAIJQgQoNwBAAAAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Gacy:BAAALgAECgEJAQAAAA==.Galaythien:BAAALgAECgYJCwAAAA==.Gang:BAAALgAECgUJBQABLgAFFAQJEQABADIOAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAMAEQaAA==.',
Ge='Geluria:BAABLgAECn8aAAMfAAkJdB2vBwCeAgAfAAkJdB2vBwCeAgAQAAEJ5Q6KPAAuAAABLgAECgkJOgAeAMskAA==.Geret:BAABLgAECn8iAAIGAAgJdxO2cgCIAQAGAAgJdxO2cgCIAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gh='Ghanaria:BAAALgAECgEJAQAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Gleesh:BAAALgAECgEJAQABLgAECggJFgAVAGIeAA==.Glitchy:BAABLgAECn9IAAMdAAkJ3x8CCADVAgAdAAkJZx8CCADVAgAlAAYJGhYKGgB+AQAAAA==.Glokraz:BAAALgAECgcJBwAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgYJDQAAAA==.',
Go='Goingtogetu:BAABLgAECn9IAAMFAAkJrSP0AQAhAwAFAAkJrSP0AQAhAwAGAAYJBxDXkwBMAQAAAA==.Gold:BAAALgAECgIJAgABLgAECgkJKwAbAD4fAA==.Goldfarmr:BAABLgAECn8rAAIbAAkJPh+9DACbAgAbAAkJPh+9DACbAgAAAA==.Goldrawr:BAAALgAECgYJBwABLgAECgkJKwAbAD4fAA==.Goldshocker:BAAALgAECgQJBgABLgAECgkJKwAbAD4fAA==.Golduwu:BAAALgAECgEJAgABLgAECgkJKwAbAD4fAA==.Googlymoogly:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.Gottahvyhand:BAAALgAECgQJBQAAAA==.',
Gr='Greed:BAAALgAFFAIJAgABLgAFFAYJCwAlAKYYAA==.Greeley:BAABLgAECn86AAISAAkJMCTnAAA9AwASAAkJMCTnAAA9AwAAAA==.Gregdapro:BAABLgAECn9TAAIfAAkJuSX3AABeAwAfAAkJuSX3AABeAwAAAA==.Gregnstone:BAABLgAECn8jAAIHAAkJlRY8KADJAQAHAAkJlRY8KADJAQABLgAECgkJUwAfALklAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAUJGAAOAM0QAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAgJJAAWAEUZAA==.Gunnyal:BAABLgAECn81AAMZAAgJOhc8GgCIAQAZAAgJOhc8GgCIAQAWAAUJhwqbaAC8AAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8wAAIXAAkJUyM8BQAJAwAXAAkJUyM8BQAJAwAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8kAAMWAAgJRRn+AwA9AgAWAAgJRRn+AwA9AgAZAAEJNAEQDgA8AAAuAAQKfzwAAxYACQktJWkCAE0DABYACQktJWkCAE0DABkAAwldHN46ANkAAAAA.Hakyahi:BAAALgADCggJCAAAAA==.Hallokitty:BAAALgAECgEJAQAAAA==.Hank:BAAALgADCgYJBgAAAA==.Happerixie:BAAALgADCgkJCQAAAA==.Harkin:BAABLgAECn85AAIGAAkJDxImXwCzAQAGAAkJDxImXwCzAQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgAECgYJDAAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIXAAcJXQsvTwD6AAAXAAcJXQsvTwD6AAAAAA==.Hevy:BAABLgAECn9IAAIMAAkJCxyRAABJAgAMAAkJCxyRAABJAgAAAA==.',
Hi='Hilarius:BAAALgAECggJEQAAAA==.Hiraeth:BAAALgAECgUJCQAAAA==.Hirukon:BAAALgAECgEJAQAAAA==.',
Ho='Holydadbod:BAAALgAECgQJBwABLgAFFAQJDAAeAJ4gAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn9FAAIGAAkJARlxLQBLAgAGAAkJARlxLQBLAgAAAA==.Hottice:BAAALgAECgEJAQAAAA==.Howlinnbrews:BAABLgAFFH8IAAMUAAQJbxvnGgDzAAAUAAQJDRbnGgDzAAAeAAEJ6CVyTwBkAAAAAA==.Howlinplague:BAAALgAECgYJCQAAAA==.',
Hu='Hulkhogan:BAABLgAECn8fAAIaAAkJAR1vCABzAgAaAAkJAR1vCABzAgAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIMAAMJRBo2YADPAAAMAAMJRBo2YADPAAAuAAQKfycAAgwACAkuIrAVANQCAAwACAkuIrAVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMEAAgJjBi3KAANAgAEAAgJjBi3KAANAgAiAAIJ1hLaSQBGAAAAAA==.Idrizzt:BAAALgAECgYJBgAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8aAAIUAAcJVBbdNgAnAQAUAAcJVBbdNgAnAQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Io:BAABLgAFFH8MAAIeAAQJSyH9EgCLAQAeAAQJSyH9EgCLAQAAAA==.Iobo:BAABLgAECn87AAIYAAgJKBYsAQAUAQAYAAgJKBYsAQAUAQAAAA==.',
Ir='Ironhidez:BAABLgAECn8+AAIGAAkJlg5HZgCjAQAGAAkJlg5HZgCjAQAAAA==.',
Is='Isaarek:BAABLgAECn8gAAIOAAkJ/xVoFQAvAgAOAAkJ/xVoFQAvAgAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDwAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAgJIgANAN0YAA==.Jasmini:BAAALgAECgEJAwAAAA==.Jastia:BAABLgAECn8ZAAIgAAcJpBopCQC2AQAgAAcJpBopCQC2AQAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jeb:BAAALgAECgEJAgABLgAFFAEJAQACAAAAAA==.Jebopally:BAAALgAECgMJBAABLgAFFAEJAQACAAAAAA==.Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8sAAMRAAkJAhzIHgBsAgARAAkJAhzIHgBsAgAgAAEJAAD2bQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8vAAIGAAkJTw55YQCtAQAGAAkJTw55YQCtAQAAAA==.',
Jo='Joecephus:BAABLgAECn8xAAIHAAgJKiKEDwCgAgAHAAgJKiKEDwCgAgAAAA==.Joehex:BAABLgAECn88AAIaAAkJgyFjBADfAgAaAAkJgyFjBADfAgAAAA==.Joeschmonk:BAAALgAECgYJBgAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Jubelius:BAAALgAECgYJCQABLgAECgkJHwAKAMUVAA==.Judgematt:BAABLgAECn8WAAIHAAkJBRSgGgAvAgAHAAkJBRSgGgAvAgAAAA==.Justin:BAABLgAECn8fAAIZAAkJvhUJDgAJAgAZAAkJvhUJDgAJAgAAAA==.',
Ka='Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAISAAgJ1AwBFAAhAQASAAgJ1AwBFAAhAQABLgAFFAIJBQAXANoFAA==.Kaleesh:BAACLgAFFH8TAAImAAcJpSW1AABnAgAmAAcJpSW1AABnAgAuAAQKfyUAAiYACAkJJkcBAGgDACYACAkJJkcBAGgDAAAA.Kallux:BAABLgAECn9PAAIfAAkJWSFSAACAAgAfAAkJWSFSAACAAgAAAA==.Kananga:BAABLgAECn8oAAIbAAgJABrWAQAUAQAbAAgJABrWAQAUAQAAAA==.Kanati:BAAALgAECgEJAQABLgAECgkJDwACAAAAAA==.Karavira:BAAALgAECgEJAQAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Katniss:BAAALgAECgEJAQAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgAECgYJBgAAAA==.',
Ke='Kelindina:BAAALgAECgMJDQAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Keoeu:BAAALgAECggJDgAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgYJCwAAAA==.',
Ki='Kieleron:BAABLgAECn8kAAIIAAgJARPnGgD4AQAIAAgJARPnGgD4AQAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJEAAAAA==.Kiermaxim:BAABLgAECn8mAAIXAAgJNBwcGwA6AgAXAAgJNBwcGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Killon:BAAALgAECgEJAQABLgAECgkJOQAGADIUAA==.Kindred:BAAALgAECggJCQAAAA==.Kiragrande:BAABLgAECn8iAAIDAAkJxBBzLQDIAQADAAkJxBBzLQDIAQAAAA==.Kiraneth:BAABLgAECn8gAAIUAAgJMBA4LQBYAQAUAAgJMBA4LQBYAQAAAA==.Kirbie:BAAALgADCgUJBQAAAA==.Kirial:BAAALgAECggJCAAAAA==.Kiriku:BAAALgAECggJEwAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgYJCgAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgADCgYJBgAAAA==.',
La='Lagartista:BAAALgAFFAIJAwAAAA==.Largcok:BAAALgAECgIJAgAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Le='Lee:BAAALgAFFAYJAQAAAA==.Lefty:BAAALgADCgcJCgABLgAECgkJOwAYAAoUAA==.Leyn:BAAALgAECgUJBQAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lilpwny:BAAALgAECgQJBAABLgAECgkJIQAJADEYAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn88AAIWAAkJ0iQgAwA7AwAWAAkJ0iQgAwA7AwAAAA==.Logres:BAAALgADCgEJAQAAAA==.Lokeira:BAACLgAFFH8OAAITAAQJew0+RADXAAATAAQJew0+RADXAAAuAAQKfykAAhMACAmGG0czAOUBABMACAmGG0czAOUBAAAA.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn85AAIGAAkJMhTtUwDOAQAGAAkJMhTtUwDOAQAAAA==.Loonnah:BAAALgAECgIJAgAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgUJBgABLgAECgcJJAAVAE4TAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Lupusregina:BAAALgAECgQJBAABLgAECgkJEAACAAAAAA==.Luvbug:BAABLgAECn8WAAIKAAcJ3SJ9GAB2AgAKAAcJ3SJ9GAB2AgAAAA==.',
Ly='Lyais:BAAALgAECgMJAwAAAA==.Lyara:BAACLgAFFH8aAAMTAAcJNST0CQArAgATAAcJNST0CQArAgAXAAQJRxhPIgASAQAuAAQKfxwAAxMACQnAIFAJAOICABMACAkVIFAJAOICABcABglnG/w/ADQBAAAA.Lyi:BAAALgAFFAEJAgAAAA==.Lynn:BAAALgADCgEJAQAAAA==.Lythos:BAACLgAFFH8HAAIfAAMJjwneLgCKAAAfAAMJjwneLgCKAAAuAAQKfxkAAh8ACAmPE2obAHMBAB8ACAmPE2obAHMBAAAA.Lyu:BAAALgAFFAEJAQABLgAFFAcJGgATADUkAA==.Lyuu:BAABLgAFFH8GAAIVAAMJdxa2ggDSAAAVAAMJdxa2ggDSAAABLgAFFAcJGgATADUkAA==.',
['Lø']='Lørdøfßud:BAABLgAECn80AAMWAAkJGCMhBwDsAgAWAAkJuCEhBwDsAgAZAAcJEiNzCwAxAgAAAA==.',
Ma='Macguffin:BAAALgAECgEJAQAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJHQAMAIYLAA==.Maeve:BAAALgADCggJCAAAAA==.Makimá:BAAALgADCgYJBgABLgAECgkJHwAKAMUVAA==.Makinnor:BAAALgAECgEJAgAAAA==.Maklovin:BAAALgAECgEJAwAAAA==.Malifae:BAABLgAECn8bAAIdAAcJYSGbEwB3AgAdAAcJYSGbEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwAdAGEhAA==.Mankilla:BAAALgAECgQJBwAAAA==.Mansa:BAACLgAFFH8GAAInAAMJTgffCADDAAAnAAMJTgffCADDAAAuAAQKfzkAAicACQnFGpsDAHMCACcACQnFGpsDAHMCAAAA.Mastamojo:BAABLgAECn89AAIHAAkJUAnlNwBuAQAHAAkJUAnlNwBuAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Mavis:BAAALgAECgIJAgAAAA==.Maîev:BAAALgAECgUJBwAAAA==.',
Mc='Mcmurphy:BAAALgAECggJEAAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Meanieman:BAAALgADCgEJAgAAAA==.Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAACLgAFFH8GAAIhAAIJTggiEQCHAAAhAAIJTggiEQCHAAAuAAQKfysAAyEACQmkFjgHAAACACEACQmVFjgHAAACACAABwmpE04QAD0BAAAA.Melendaren:BAAALgAECgQJBwAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgAECgQJCAAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAFFAEJAQAAAA==.Meowkug:BAAALgAECgEJAgAAAA==.Merscy:BAABLgAECn8bAAIbAAgJngquOQASAQAbAAgJngquOQASAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAABLgAECn8yAAMdAAcJnRd0KACNAQAdAAcJnRd0KACNAQAEAAYJ1gs6awDzAAAAAA==.Metamonster:BAABLgAECn8vAAMNAAkJcg2keQBwAQANAAkJCgikeQBwAQAfAAYJOBBCAgC2AAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikaels:BAAALgAECgcJCAABLgAECgkJPwAMALsbAA==.Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgcJDQAAAA==.Mirko:BAABLgAECn8dAAIMAAcJhgtsjAAHAQAMAAcJhgtsjAAHAQAAAA==.Mistiah:BAABLgAFFH8JAAINAAMJQyASdwAVAQANAAMJQyASdwAVAQAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn9bAAIcAAkJOB0RAABlAgAcAAkJOB0RAABlAgAAAA==.Mokokniki:BAAALgAECgIJAgAAAA==.Moneie:BAAALgAECgUJDAAAAA==.Monger:BAAALgADCgIJAgAAAA==.Mongò:BAAALgAECgQJBQAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAFFAMJCAAXAKwQAA==.Moondo:BAAALgAECgcJDgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Mooseymancer:BAAALgADCgcJDQAAAA==.Mootron:BAAALgADCgYJCgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mortimus:BAAALgAECgMJAwAAAA==.Mourningstar:BAACLgAFFH8aAAMNAAUJxiVoMACmAQANAAQJxiVoMACmAQAfAAEJAACpYAAAAAAuAAQKfyQAAw0ACQkeJPcYALECAA0ACQkeJPcYALECAB8AAgm1EZ5HAG8AAAEuAAUUCAkiAA0A3RgA.Mozaic:BAABLgAECn9aAAIaAAkJuR43AACHAgAaAAkJuR43AACHAgAAAA==.',
Mu='Mugrüíth:BAAALgAECgUJCgAAAA==.Muyoang:BAAALgADCgEJAQABLgAECgkJMwAEABMfAA==.',
My='Myfeethurt:BAAALgAECgQJBQABLgAECgkJNAAWABgjAA==.Mymoon:BAAALgADCgMJAwAAAA==.Myragê:BAAALgADCgkJDQABLgAECgEJAQACAAAAAA==.Myselia:BAABLgAECn8kAAILAAkJBhXCEgACAgALAAkJBhXCEgACAgAAAA==.Mystra:BAAALgAECgYJCwAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgADCgQJBAAAAA==.Naek:BAAALgAECgYJDAAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgYJDAACAAAAAA==.Nalthis:BAAALgAECgYJAwAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAABLgAECn8xAAIVAAgJ6RQEBwDPAAAVAAgJ6RQEBwDPAAAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAABLgAECn8ZAAIMAAgJvQk+hgATAQAMAAgJvQk+hgATAQAAAA==.Niem:BAABLgAECn8dAAIlAAkJhSVFAQBOAwAlAAkJhSVFAQBOAwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.Nitsi:BAAALgAECgEJAQABLgAECgkJNQAeAKAaAA==.',
No='Nocturnum:BAABLgAECn8/AAIMAAkJuxs5GACEAgAMAAkJuxs5GACEAgAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8KAAIhAAUJQRdPAABcAQAhAAUJQRdPAABcAQAuAAQKfxwAAiEACAktHi8BAPECACEACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAABLgAECgMJAgACAAAAAA==.Odin:BAAALgAECgEJAgAAAA==.Odium:BAAALgADCgMJAwABLgAFFAUJDgAKAHEfAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAcJGAASAIwiAA==.',
Ol='Oldage:BAAALgAECgkJEgABLgAECgkJFAAQACQYAA==.Oldmage:BAAALgAECgYJCAAAAA==.Oldmongerpal:BAAALgAECgEJAQAAAA==.',
On='Onetwocowpow:BAABLgAECn9IAAIDAAkJ+hhrFQBuAgADAAkJ+hhrFQBuAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn9RAAMGAAkJViJwDwATAwAGAAkJViJwDwATAwAFAAkJTBelCQA0AgAAAA==.Orionn:BAACLgAFFH8VAAIKAAUJRSC0CQAUAQAKAAUJRSC0CQAUAQAuAAQKf0UAAgoACQm2JckEAEQDAAoACQm2JckEAEQDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAABLgAECn8cAAIKAAkJXQ5pSgDCAQAKAAkJXQ5pSgDCAQAAAA==.',
Ov='Oven:BAABLgAECn8gAAIUAAgJVxYKIgCfAQAUAAgJVxYKIgCfAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.Patelz:BAAALgADCgQJBAAAAA==.',
Pe='Petoria:BAAALgADCgUJBQAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pinksparkle:BAAALgAECgkJCQAAAA==.Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQABLgAECgkJDwACAAAAAA==.Polyeikon:BAAALgAECgUJCgAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgAECgMJBAAAAA==.Prayr:BAAALgADCgMJBAAAAA==.Praystation:BAAALgAECgUJCAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgYJCwAAAA==.',
Ra='Raekeshh:BAABLgAECn8ZAAIRAAkJ3BWbNAAGAgARAAkJ3BWbNAAGAgAAAA==.Raelone:BAABLgAECn8dAAQgAAkJGBGrIwCUAAARAAUJYg3NqgDtAAAgAAYJZBKrIwCUAAAhAAEJ5RNENwBHAAAAAA==.Rageofmommy:BAAALgAECgMJBAAAAA==.Raidoe:BAABLgAECn9LAAMDAAkJKRwjAQDNAQADAAkJKRwjAQDNAQAUAAMJOQsHdQBmAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn81AAIKAAkJgxk/MAAbAgAKAAkJgxk/MAAbAgAAAA==.Rant:BAAALgAECgYJCwAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.Razorbeams:BAAALgAECgQJBQABLgAECgkJWwAcADgdAA==.',
Re='Redishpanda:BAAALgADCgcJFAAAAA==.Redshammy:BAAALgAFFAIJAwAAAA==.Relion:BAAALgAECggJEwABLgAECgkJRAAGAGISAA==.Reo:BAAALgAFFAEJAQABLgAFFAYJIQADACUgAA==.',
Rh='Rheavin:BAAALgADCgUJCgAAAA==.Rhell:BAACLgAFFH8OAAIHAAQJqhPJKADeAAAHAAQJqhPJKADeAAAuAAQKfzkAAwcACQnuIWsIAAUDAAcACQnuIWsIAAUDAAYAAQkUAvHRARYAAAAA.',
Ri='Rinche:BAABLgAECn9FAAMXAAkJNxa/GwADAgAXAAkJNxa/GwADAgATAAkJ3guvUgBoAQAAAA==.Rintche:BAAALgAECgUJBQAAAA==.Rivers:BAAALgAECgMJAwABLgAECgkJFAAQACQYAA==.',
Ro='Rolland:BAABLgAECn8kAAISAAkJeyD9AQDoAgASAAkJeyD9AQDoAgAAAA==.Rollf:BAAALgAECgMJAwAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAABLgAECn8hAAMRAAkJOAvoWgCNAQARAAkJOAvoWgCNAQAgAAQJ1wTUKQBuAAAAAA==.',
Ru='Rudo:BAABLgAECn8fAAMKAAkJxRVZIgA3AgAKAAkJxRVZIgA3AgAYAAEJrgLXagAnAAAAAA==.Rumproblem:BAABLgAECn9AAAMIAAkJTBg7DwB7AgAIAAkJTBg7DwB7AgAJAAkJqw7aAQAOAQAAAA==.Runekaiser:BAAALgAECgIJBAAAAA==.Runnamuuk:BAABLgAECn82AAIMAAkJGBTzNgDqAQAMAAkJGBTzNgDqAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryegar:BAAALgADCgkJCQAAAA==.Ryeger:BAABLgAECn9RAAMiAAkJWyIQAADjAgAiAAkJWyIQAADjAgAdAAMJpgswZgCFAAAAAA==.',
['Rá']='Ráh:BAAALgADCgEJAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn82AAIlAAkJ3BZYEQDXAQAlAAkJ3BZYEQDXAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBQABLgAECgMJDQACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn9EAAMGAAkJYhKMAQDUAQAGAAkJYhKMAQDUAQAHAAkJYwMLRQAsAQAAAA==.Sandbones:BAAALgAECgUJDAABLgAECgkJWwAcADgdAA==.Sandraice:BAABLgAECn8fAAIGAAgJ0QYyhwBsAQAGAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sanielan:BAAALgAECgYJCwAAAA==.Sansami:BAABLgAECn8/AAIeAAkJ0RsGFwDxAQAeAAkJ0RsGFwDxAQAAAA==.Saphron:BAAALgAECgQJBAAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAABLgAECn8gAAMdAAcJFQlaAwCkAAAdAAcJFQlaAwCkAAAEAAUJDQMlqwBfAAAAAA==.',
Sc='Sc:BAAALgAECgcJCQABLgAECgkJKgAVAE4jAA==.Scalebagz:BAABLgAECn8gAAMjAAkJSB4XBgCoAgAjAAkJSB4XBgCoAgAOAAgJvRyZIADVAQAAAA==.Schism:BAAALgAECgEJAQAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgAECgQJBAAAAA==.Senyorseven:BAAALgAECgYJDgAAAA==.Seo:BAAALgAECgQJCAAAAA==.Serabeara:BAAALgAECgEJAQAAAA==.Setresh:BAABLgAECn9RAAIYAAkJwhUeEwAOAgAYAAkJwhUeEwAOAgAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadowcloak:BAAALgAECgUJBAAAAA==.Shadöwsöng:BAABLgAECn8/AAIaAAgJ3guLIQAjAQAaAAgJ3guLIQAjAQAAAA==.Shaedelana:BAABLgAECn8aAAQIAAcJPRudPAAcAQAIAAUJShOdPAAcAQAbAAUJcxzbTwD4AAAJAAUJpA8UTADfAAAAAA==.Shamrox:BAABLgAECn8WAAIXAAgJvQqfAgDUAAAXAAgJvQqfAgDUAAAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJMwAEABMfAA==.Shinnobi:BAAALgAECgcJBwAAAA==.Shinygoat:BAAALgADCgIJAgABLgAECgkJKgAPAI8fAA==.Shivyn:BAACLgAFFH8FAAITAAIJvhMUZQB8AAATAAIJvhMUZQB8AAAuAAQKfz8AAxMACQlMGs0PANMCABMACQlMGs0PANMCABcAAQkXBbmNACoAAAAA.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAcJGAASAIwiAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAACLgAFFH8MAAMNAAMJMRCpFACbAAANAAMJWg6pFACbAAAfAAIJrwtvNABnAAAuAAQKfy4AAw0ACQmlGUxIAOkBAA0ACQmlGUxIAOkBAB8ABQmtD1UuAMwAAAAA.Sickkid:BAABLgAECn9FAAIWAAgJ8CKrCQDIAgAWAAgJ8CKrCQDIAgAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silkiegirl:BAABLgAECn8iAAIWAAkJzhQeGgAdAgAWAAkJzhQeGgAdAgAAAA==.Silvador:BAAALgAECgEJAQABLgAFFAIJBgAOAFYCAA==.Silvershine:BAABLgAECn8VAAMEAAYJ6w4lgADaAAAEAAUJiAslgADaAAAiAAQJuAYsNwB/AAAAAA==.Silverwolf:BAAALgAECgIJAgAAAA==.Sindrya:BAAALgAECgUJBwAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slayne:BAAALgAECgEJAQAAAA==.Slaänesh:BAAALgADCgcJBwABLgAECgkJMwAEABMfAA==.Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJDAACAAAAAA==.Smashßros:BAAALgAECgQJBAABLgAECgkJNAAWABgjAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgkJEAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgABLgAFFAMJCQANAEMgAA==.Snooker:BAAALgADCgEJAQAAAA==.Snuggles:BAABLgAECn8mAAILAAgJjxoEEwD/AQALAAgJjxoEEwD/AQABLgAFFAYJHAAYAHcUAA==.',
So='Solidgen:BAEALgAECgEJAgABLgAFFAYJGAAGACsRAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Sonofalich:BAAALgAECgkJCQAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAABLgAECn8WAAMaAAgJNRa9FwCDAQAaAAgJNRa9FwCDAQAZAAMJUgOpNABeAAAAAA==.Spinach:BAAALgAECgEJAQAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgQJDgAAAA==.',
Ss='Ssraeshza:BAABLgAFFH8LAAIlAAYJphizCABoAQAlAAYJphizCABoAQAAAA==.',
St='Staretra:BAABLgAECn9BAAMJAAkJOBILHQDcAQAJAAkJOBILHQDcAQAbAAQJowbkUwCNAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.',
Su='Sublevels:BAAALgADCgYJBgAAAA==.Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECggJEQAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Symana:BAABLgAECn85AAIbAAkJKB5aCwCxAgAbAAkJKB5aCwCxAgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgAECgEJAQAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgcJEQAAAA==.',
['Sö']='Sörceress:BAAALgAECgYJEwAAAA==.',
Ta='Taadra:BAABLgAECn9fAAITAAkJvCDlCQAWAwATAAkJvCDlCQAWAwAAAA==.Talerah:BAAALgAECgUJCQAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAACLgAFFH8bAAIEAAUJUhvUGACXAQAEAAUJUhvUGACXAQAuAAQKfxgAAwQACQnvF2YeAEwCAAQACQnvF2YeAEwCACUAAgkPE1VOAHMAAAAA.Talona:BAAALgAFFAEJAQABLgAFFAUJCgAhAEEXAA==.Tandaan:BAAALgADCgkJCgABLgAECgkJGQARANwVAA==.Tanjent:BAABLgAECn8fAAIKAAYJDA1lmgAMAQAKAAYJDA1lmgAMAQAAAA==.Tanok:BAAALgADCgYJBgAAAA==.Tapio:BAABLgAECn8vAAIYAAgJwRZwAQDuAAAYAAgJwRZwAQDuAAAAAA==.Tatsuma:BAAALgAECgYJDgABLgAECgkJJQAGAPsbAA==.Tatsumå:BAAALgAECgcJEgABLgAECgkJJQAGAPsbAA==.Tavvi:BAAALgAECgYJBgABLgAECgcJFgAKAN0iAA==.Tazz:BAAALgAECgIJAgAAAA==.',
Te='Terp:BAAALgAECgMJBwAAAA==.',
Th='Thalfinore:BAAALgAECgcJEgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Therogue:BAAALgAECgIJAgAAAA==.Thorincan:BAAALgAECgkJCQAAAA==.Thorrs:BAAALgAECgIJBwAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thorwar:BAAALgADCgEJAQAAAA==.Thuglifé:BAAALgADCgYJDQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECgUJBwACAAAAAA==.Tidemaiden:BAAALgAECgcJEgAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgABLgAFFAMJAwACAAAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tipsymancer:BAABLgAECn9IAAIeAAkJDSLwAwAOAwAeAAkJDSLwAwAOAwAAAA==.Tirael:BAAALgAECgYJBQABLgAFFAYJAQACAAAAAA==.Tishi:BAAALgAECgEJAQAAAA==.',
To='Tomö:BAAALgAECgkJBAAAAA==.Tossme:BAAALgAECgEJAQABLgAFFAQJDAAeAJ4gAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Traeicel:BAAALgAECgcJAQAAAA==.Treesus:BAABLgAECn8fAAIdAAkJLhqWGwAmAgAdAAkJLhqWGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECgkJHwAKAMUVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Ts='Tsu:BAAALgADCgkJCQAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.Tyzi:BAAALgAECgEJAQAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQVAAgJ+iNoNwA7AgAVAAgJXCFoNwA7AgAcAAMJPCQECAAkAQAoAAEJTQ0VDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8lAAIEAAkJsRiWIgA0AgAEAAkJsRiWIgA0AgAAAA==.',
Un='Undeadgnome:BAAALgAECgMJAwAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.Usër:BAAALgAECgQJBwAAAA==.',
Va='Vainin:BAABLgAECn8VAAIVAAYJsgcI5ADVAAAVAAYJsgcI5ADVAAAAAA==.Valle:BAAALgAFFAEJAQAAAA==.Valry:BAAALgAECgYJDgAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAQJBgAaAEkXAA==.Vankro:BAAALgAECgIJAgABLgAFFAQJGQAPACMmAA==.Variable:BAAALgAECgcJBwAAAA==.Vashdin:BAABLgAECn8sAAIGAAgJEBw5QQADAgAGAAgJEBw5QQADAgAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECgkJHwAKAMUVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velashis:BAABLgAECn8+AAMEAAkJRR9/AAA9AgAEAAkJRR9/AAA9AgAdAAIJ5QydeABVAAAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAABLgAFFH8IAAIXAAMJrBDINQC3AAAXAAMJrBDINQC3AAAAAA==.Vett:BAAALgADCgMJAwABLgAECgYJFQAVALIHAA==.',
Vi='Viable:BAAALgAECgUJCgAAAA==.Vibes:BAAALgAECgkJCwAAAA==.Victorvega:BAAALgAECgMJAwABLgAECgkJHwAKAMUVAA==.Vicvega:BAAALgAECgQJBAABLgAECgkJHwAKAMUVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8QAAMDAAMJtRIRPAC1AAADAAMJtRIRPAC1AAAUAAIJlxllLwCIAAAuAAQKfyYAAxQACQndHRcQAH8CABQACAmuHRcQAH8CAAMABQnvH+pUAB0BAAAA.Vivila:BAAALgAECgMJBQABLgAECgkJSAAMAAscAA==.Vivillian:BAABLgAFFH8HAAIIAAMJjg97MwC+AAAIAAMJjg97MwC+AAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Voidrèaper:BAAALgAECgEJAQAAAA==.Vordilina:BAABLgAECn8cAAQoAAkJqhgQAgBYAgAoAAkJqhgQAgBYAgAcAAEJuAV9IAAtAAAVAAEJrQHbiAEcAAAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQjAAgJKhn4EwAGAgAjAAgJKhn4EwAGAgAkAAQJxRh7FQC6AAAOAAEJygMInQAkAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAABLgAECn88AAMTAAgJ2BvHNADeAQATAAcJnhrHNADeAQAXAAgJDBrtAQAEAQAAAA==.Vugowulf:BAAALgAECgEJAQAAAA==.',
Vy='Vynae:BAAALgADCgcJBAAAAA==.',
['Vé']='Véxx:BAABLgAECn8yAAQPAAkJvh7cBABnAgAPAAkJvh7cBABnAgALAAUJYAizQgDtAAAMAAEJdAGj9QAZAAAAAA==.',
['Vì']='Vìx:BAAALgAECgEJAQAAAA==.',
['Ví']='Víx:BAAALgAECggJCAAAAA==.',
['Vî']='Vîper:BAAALgAFFAEJAQAAAA==.',
['Vï']='Vïx:BAAALgADCgUJBQAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Warihor:BAABLgAECn8vAAMZAAgJeQyTMAAGAQAWAAgJIwq0QABCAQAZAAgJhQmTMAAGAQAAAA==.Waycaps:BAABLgAFFH8FAAIlAAQJUBUQEAAIAQAlAAQJUBUQEAAIAQAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAACLgAFFH8PAAIhAAQJbiTjAQCjAQAhAAQJbiTjAQCjAQAuAAQKfy4AAiEACQk/JMAAACEDACEACQk/JMAAACEDAAAA.',
Wh='Whïte:BAAALgAECgEJAgAAAA==.',
Wi='Wiegraf:BAAALgAECgIJAwABLgAECgkJMwAEABMfAA==.Wife:BAAALgAECgMJAwAAAA==.Wildhide:BAAALgAECgcJBwAAAA==.Withers:BAAALgADCgQJBAAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJDQAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECgcJCgAAAA==.',
['Wä']='Wärbëef:BAAALgADCgEJAQAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECgUJBwACAAAAAA==.',
Xo='Xorxel:BAAALgAECgMJBwAAAA==.',
Ya='Yacob:BAABLgAECn82AAMbAAkJOx0kCgDFAgAbAAkJOx0kCgDFAgAJAAEJwxF6CAA3AAAAAA==.Yacobge:BAAALgAECgYJBgAAAA==.',
Ye='Yenneferr:BAAALgAECgkJAQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8zAAIEAAkJEx+HCwAGAwAEAAkJEx+HCwAGAwAAAA==.',
Yh='Yhwach:BAACLgAFFH8MAAIfAAYJZA10JADLAAAfAAYJZA10JADLAAAuAAQKfyEAAh8ACAk4GBcUANIBAB8ACAk4GBcUANIBAAAA.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAABLgAFFH8JAAIGAAQJkRHzSAAaAQAGAAQJkRHzSAAaAQABLgAECgkJFAAQACQYAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECgUJBwAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgcJCwAAAA==.',
Za='Zaeden:BAABLgAECn8dAAIDAAcJDh+fFgANAgADAAcJDh+fFgANAgABLgAECgkJGgANAK0gAA==.Zaft:BAAALgADCgYJBgAAAA==.Zaftdh:BAABLgAECn81AAIMAAkJqhVZNAD1AQAMAAkJqhVZNAD1AQAAAA==.Zaha:BAABLgAECn8eAAIVAAYJ2iKdXAAkAgAVAAYJ2iKdXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zappsz:BAAALgAECgcJDQAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zedfrey:BAABLgAECn9EAAIGAAkJdBniAQCsAQAGAAkJdBniAQCsAQAAAA==.Zedra:BAAALgADCgcJBwAAAA==.Zem:BAABLgAECn8rAAIWAAgJux8uEgBiAgAWAAgJux8uEgBiAgAAAA==.Zemangoose:BAAALgAECgYJBgAAAA==.Zeroultra:BAABLgAECn86AAIWAAkJvx3PEQBmAgAWAAkJvx3PEQBmAgAAAA==.Zeräse:BAABLgAECn8VAAIIAAgJRw/8JACnAQAIAAgJRw/8JACnAQABLgAECgkJMwAEABMfAA==.Zeusdh:BAAALgADCgkJCQAAAA==.Zeusmos:BAABLgAECn9GAAIUAAkJ2yY4AACVAwAUAAkJ2yY4AACVAwAAAA==.',
Zi='Zithenex:BAABLgAECn88AAIkAAgJWxaDAAD6AAAkAAgJWxaDAAD6AAAAAA==.',
Zo='Zoeÿ:BAAALgAECgEJBAAAAA==.',
Zw='Zwar:BAAALgAECgIJAgAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAABLgAECn8mAAIWAAcJuhR6MgCBAQAWAAcJuhR6MgCBAQAAAA==.',
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
