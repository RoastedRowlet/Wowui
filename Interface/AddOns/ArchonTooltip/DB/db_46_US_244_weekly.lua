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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Priest-Discipline','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Warrior-Arms','Warrior-Protection','Priest-Holy','Mage-Arcane','Druid-Balance','DeathKnight-Frost','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Warrior-Fury','Druid-Feral','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Guardian','Shaman-Enhancement','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-06-07',data={Aa='Aaminae:BAABLgAECn8xAAIBAAkJIxdSDgA6AgABAAkJIxdSDgA6AgAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgUJCgAAAA==.Abracastabya:BAAALgAFFAEJAQAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.Absolution:BAAALgAECgQJBAAAAA==.Abÿss:BAAALgAECgYJBgAAAA==.',
Ad='Adachï:BAABLgAECn8WAAIDAAYJiRpjMQCfAQADAAYJiRpjMQCfAQABLgAECgkJMwAEABMfAA==.Adevil:BAAALgAECgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aegon:BAAALgADCgkJCQAAAA==.Aethlin:BAABLgAECn81AAMFAAkJ4BvJLwA3AgAFAAkJjRnJLwA3AgAGAAgJdhuVCgAVAgAAAA==.Aetreyu:BAAALgAECgYJCwAAAA==.Aeturnas:BAABLgAECn8wAAIHAAkJrB6PCAD4AgAHAAkJrB6PCAD4AgAAAA==.',
Ag='Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanima:BAABLgAECn8ZAAMIAAgJMQo8KwBwAQAIAAgJMQo8KwBwAQAJAAYJ3AY4TQDSAAAAAA==.Aldky:BAAALgADCgkJDgAAAA==.Aliana:BAAALgAFFAEJAQAAAA==.Alinthe:BAAALgADCgkJCQAAAA==.Allindis:BAAALgAECgYJCQABLgAECgkJJQAEALEYAA==.Allypally:BAAALgADCgMJAwAAAA==.Alphamage:BAAALgADCgMJAwAAAA==.Alphamonk:BAAALgAECggJEAAAAA==.Alros:BAABLgAECn8+AAIKAAkJGSKpBwAaAwAKAAkJGSKpBwAaAwAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgAECgQJCAAAAA==.',
Am='Amardyton:BAAALgAECgYJBwAAAA==.',
An='Aneas:BAAALgAECgUJCQAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgMJAwACAAAAAA==.Arctica:BAAALgADCgQJBAAAAA==.Arette:BAAALgAECgIJAgAAAA==.Arkades:BAABLgAECn8fAAIFAAgJ1hzmLwA3AgAFAAgJ1hzmLwA3AgAAAA==.Arkshade:BAABLgAECn81AAILAAcJfhIoeQBqAQALAAcJfhIoeQBqAQAAAA==.Arlia:BAAALgAECgkJEQABLgAFFAIJAwACAAAAAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECgkJKgAMAI8fAA==.Aryn:BAAALgAECgEJAQAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgYJCwACAAAAAA==.Ashor:BAAALgAECgIJAgAAAA==.Asmo:BAAALgADCggJGAAAAA==.Astarii:BAAALgAECgEJBQAAAA==.Asterica:BAABLgAECn9QAAINAAkJWBiULwAUAgANAAkJWBiULwAUAgAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAIOAAYJ+A16UwA4AQAOAAYJ+A16UwA4AQAAAA==.',
Av='Averynicole:BAABLgAECn8ZAAIPAAcJBxb+KQBgAQAPAAcJBxb+KQBgAQAAAA==.',
Aw='Awasjr:BAABLgAECn8mAAIKAAkJlh9CFgCZAgAKAAkJlh9CFgCZAgAAAA==.Awassy:BAAALgAECgEJAgAAAA==.',
Ay='Ayano:BAABLgAECn8WAAIQAAgJYh6oRwD/AQAQAAgJYh6oRwD/AQAAAA==.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balanla:BAAALgADCgIJAgAAAA==.Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDwABLgAECgkJMwAEABMfAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgAECgEJAQAAAA==.Bearhug:BAABLgAECn8uAAMDAAgJxxdkIACwAQADAAcJ7RlkIACwAQAPAAcJ2geBQgANAQABLgAFFAQJCwARAPcIAA==.Bearshock:BAACLgAFFH8LAAMRAAQJ9wimKQDmAAARAAQJ9wimKQDmAAAOAAEJTADKgwAdAAAuAAQKfxwAAhEACAl7GzITAEkCABEACAl7GzITAEkCAAAA.Beasty:BAABLgAECn8lAAMSAAgJHhC/EABAAQASAAgJHhC/EABAAQATAAYJhwS/OwDZAAAAAA==.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAABLgAECn8yAAIGAAkJzCQQAQBGAwAGAAkJzCQQAQBGAwAAAA==.Beeb:BAAALgAECgUJDgABLgAECgkJMgAGAMwkAA==.Beefisting:BAAALgAECgYJDAABLgAECgkJMgAGAMwkAA==.Beethicc:BAAALgAECgEJBAABLgAECgkJMgAGAMwkAA==.Beeuwu:BAAALgAECgIJAwABLgAECgkJMgAGAMwkAA==.Beliara:BAAALgAECggJDAAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Belshuntress:BAAALgAECgEJAgAAAA==.Beverage:BAAALgAECgEJAQAAAA==.',
Bi='Bicboi:BAAALgAECgEJAQAAAA==.Bigmattyl:BAAALgAECgcJCgAAAA==.Bionarra:BAABLgAECn8uAAIQAAkJtBoIMQBPAgAQAAkJtBoIMQBPAgAAAA==.Bishopwr:BAABLgAECn8nAAMUAAkJ8BZ/CwAmAgAUAAkJ8BZ/CwAmAgAVAAYJCwq3MACxAAAAAA==.Bittertøfu:BAABLgAECn8eAAIRAAcJfQYEVQDXAAARAAcJfQYEVQDXAAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJCQAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blessu:BAAALgAECgEJAQAAAA==.Blitê:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Bm='Bmpfrostie:BAABLgAECn8UAAIQAAcJdg01yABYAQAQAAcJdg01yABYAQAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECgkJNQAWADsdAA==.Bohica:BAAALgAECggJDgAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAABLgAFFAMJCAALAEMgAA==.',
Br='Brakug:BAABLgAECn8vAAMQAAkJHiMULgC5AgAQAAkJHiMULgC5AgAXAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAIJAwAAAA==.Brem:BAACLgAFFH8IAAIXAAMJiBmiAQD8AAAXAAMJiBmiAQD8AAAuAAQKfxsAAhcACAmCHB4EABICABcACAmCHB4EABICAAAA.Bretagnesse:BAABLgAECn8UAAIYAAgJ2wWfQgD2AAAYAAgJ2wWfQgD2AAAAAA==.Briara:BAAALgAECgYJDwAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgAECgQJBQAAAA==.Broníx:BAAALgAECgEJBQAAAA==.Bropeep:BAACLgAFFH8FAAILAAMJChuFgQD0AAALAAMJChuFgQD0AAAuAAQKfzsAAwsACQmYI70JABwDAAsACQmYI70JABwDABkABAmdFHEaAO4AAAAA.Brotality:BAAALgADCgMJBAAAAA==.Brynhildr:BAAALgAECgcJDwABLgAFFAMJBwAaAG0gAA==.',
Bu='Bullshott:BAABLgAECn8jAAIKAAkJrx1qGgB8AgAKAAkJrx1qGgB8AgAAAA==.Bum:BAABLgAECn8mAAMYAAkJsh/4BABRAwAYAAkJsh/4BABRAwAEAAEJ0xCM0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgAECgUJCQAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJEAAAAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBgAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAABLgAECn8VAAMLAAgJQA2mnwAlAQALAAcJsQqmnwAlAQAbAAYJdA0cMADVAAAAAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8zAAIFAAkJXQjnhABbAQAFAAkJXQjnhABbAQAAAA==.Carrots:BAABLgAECn8rAAIKAAgJXRQwQwDOAQAKAAgJXRQwQwDOAQAAAA==.Cartman:BAABLgAFFH8GAAIVAAQJSRd0EQARAQAVAAQJSRd0EQARAQAAAA==.Cashmachine:BAABLgAECn8tAAIKAAkJAx8+GACKAgAKAAkJAx8+GACKAgAAAA==.Castorice:BAAALgAECgEJAQAAAA==.Catfight:BAABLgAECn8wAAIGAAcJxhFvHAAnAQAGAAcJxhFvHAAnAQAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMNAAkJdBhqLgBTAgANAAkJdBhqLgBTAgAcAAEJAABoZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8MAAQKAAQJ3B4oLgBFAQAKAAQJuB0oLgBFAQASAAEJISI3IwBlAAATAAEJzA/iLgBJAAAuAAQKfxoABBIACAkNIcIYAGYCABIACAmlH8IYAGYCAAoABQlPHSVXAJQBABMAAwkrGJ5JAIYAAAAA.Cheesecake:BAABLgAECn8uAAIcAAgJBRI2CwB/AQAcAAgJBRI2CwB/AQAAAA==.Chihiko:BAAALgAECgMJAwAAAA==.Choks:BAABLgAECn8nAAIdAAcJEg0+PwBBAQAdAAcJEg0+PwBBAQAAAA==.Chromie:BAAALgADCgMJAwAAAA==.Chubbycat:BAABLgAECn8VAAMEAAcJLhmOPQCuAQAEAAcJLhmOPQCuAQAeAAUJYh1aFgBTAQAAAA==.Chuggz:BAABLgAECn81AAIaAAkJoBqZDABlAgAaAAkJoBqZDABlAgAAAA==.Chéfboyrlee:BAACLgAFFH8ZAAIJAAgJhRcoBAAvAgAJAAgJhRcoBAAvAgAuAAQKfzYAAgkACQn6IhUEABYDAAkACQn6IhUEABYDAAAA.',
Ci='Cizmac:BAAALgAECgUJCwAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgADCgYJCgAAAA==.Cownado:BAABLgAECn82AAIaAAcJnBKvKQBgAQAaAAcJnBKvKQBgAQABLgAECggJFQALAEANAA==.',
Cr='Crouton:BAAALgADCgkJCgAAAA==.',
Cu='Cursedspirit:BAAALgAECgQJBwAAAA==.',
Cy='Cybelem:BAABLgAECn8tAAIRAAkJmB5IDwByAgARAAkJmB5IDwByAgAAAA==.Cyfelen:BAABLgAECn8ZAAQcAAkJiB8+AQDbAgAcAAkJiB8+AQDbAgAfAAQJLxksGwDVAAANAAIJrw9y7wB2AAAAAA==.Cynleel:BAAALgAECggJEAAAAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQAAAA==.Damonstyle:BAAALgAECgEJAgAAAA==.Dandistyle:BAABLgAECn8fAAMaAAkJdx21CgCBAgAaAAkJbh21CgCBAgAPAAEJchK2fAAzAAAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathblade:BAAALgAECgEJAQAAAA==.Deathmatrynn:BAAALgAECgYJCAAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAABLgAECn8VAAIRAAgJ2haxHADxAQARAAgJ2haxHADxAQAAAA==.Deeviant:BAAALgAECggJDgAAAA==.Defend:BAAALgAECgYJBgABLgAFFAQJBgAVAEkXAA==.Delrager:BAACLgAFFH8HAAIBAAIJch4qKwCzAAABAAIJch4qKwCzAAAuAAQKfygAAgEABwmYI3sMAFMCAAEABwmYI3sMAFMCAAAA.Delyta:BAAALgAECgkJCQAAAA==.Demonicdawn:BAAALgADCgEJAQAAAA==.Demónícz:BAAALgAECgMJAwAAAA==.Derat:BAAALgAECgkJEQAAAA==.',
Di='Dibbydab:BAABLgAECn8gAAIOAAkJShJNNwDGAQAOAAkJShJNNwDGAQAAAA==.',
Dj='Django:BAABLgAECn82AAMYAAkJsyKhBQD4AgAYAAkJsyKhBQD4AgAEAAIJkAZovgBBAAAAAA==.Djatalon:BAABLgAECn8WAAMgAAUJuAsBIgDYAAAgAAUJuAsBIgDYAAAhAAMJrAUFGwBsAAAAAA==.Djderpyderpy:BAAALgAECgYJDQAAAA==.Djehrtey:BAAALgAECgYJBgAAAA==.Djin:BAAALgAECgMJBAABLgAFFAMJBwAaAG0gAA==.Djinni:BAACLgAFFH8HAAIaAAMJbSAxIQAeAQAaAAMJbSAxIQAeAQAuAAQKfy4AAw8ACQllHs8NAGECAA8ACQkSG88NAGECABoACAmPH8cPADkCAAAA.',
Do='Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8XAAMZAAYJfBjBBQDVAQAZAAYJfBjBBQDVAQALAAMJsA2A/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8YAAQgAAcJNxkJDwDUAQAgAAcJNxkJDwDUAQAiAAQJuwyRXQC0AAAhAAEJAACAPAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Dramaticus:BAAALgAECgQJBAAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drenleah:BAAALgAECgkJEQABLgAECgkJPAAjALgYAA==.Drenlee:BAAALgAECgEJAgABLgAECgkJPAAjALgYAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgAAAA==.Dryya:BAAALgAECgQJCAAAAA==.Drêck:BAAALgAECgEJAQAAAA==.',
Du='Dumblegear:BAABLgAECn8fAAMQAAgJpRUXZQCuAQAQAAgJpRUXZQCuAQAXAAEJbQY0IAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAECgkJNAAdABgjAA==.',
Dw='Dwagon:BAAALgADCgUJBQAAAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgADCgQJCAAAAA==.Dädärkbeëf:BAAALgADCgcJCQAAAA==.',
Ed='Edinna:BAABLgAECn80AAMQAAkJnhO3QAAUAgAQAAkJnhO3QAAUAgAXAAQJTQoTEADBAAAAAA==.',
Ei='Einekliene:BAAALgAECgcJBwAAAA==.',
Ek='Ekatrina:BAAALgAECgEJAQAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Eldernoc:BAAALgAECgQJBgAAAA==.Elessedil:BAAALgAECgcJDQAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgUJCwAAAA==.Elyriana:BAABLgAECn8jAAMEAAkJpSB1CAAqAwAEAAkJpSB1CAAqAwAeAAEJqSDAOwBbAAAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEBLgAECn8bAAIKAAYJqyFKOQDwAQAKAAYJqyFKOQDwAQABLgAECggJKAAKANMgAA==.Emixi:BAAALgAECgQJBQAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECgcJDgAAAA==.Emritelan:BAAALgADCgkJDgAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8XAAIFAAYJixe4HwB0AQAFAAYJixe4HwB0AQAuAAQKfzEAAgUACQmaH0wiAHQCAAUACQmaH0wiAHQCAAAA.',
Ep='Epedemik:BAAALgAECgIJAgAAAA==.',
Er='Erazath:BAAALgAECgUJBgABLgAFFAMJBwAbAI8JAA==.Eredo:BAAALgAECgIJAgAAAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgAECgIJAgAAAA==.',
Es='Esha:BAAALgAECgEJAQAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Faewing:BAAALgAFFAIJAwAAAA==.Falar:BAAALgAECggJDQAAAA==.Fatelf:BAAALgADCgMJAwAAAA==.Fatowlbert:BAAALgAECgEJAgAAAA==.Faval:BAAALgAECggJDwABLgAECgkJKgAMAI8fAA==.Favel:BAABLgAECn8qAAMMAAkJjx9OAQAcAwAMAAgJ4iFOAQAcAwAjAAkJRwvxWwBpAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn9DAAIKAAkJVBhcIQBWAgAKAAkJVBhcIQBWAgAAAA==.Febz:BAABLgAECn8eAAIQAAgJbBsqMACyAgAQAAgJbBsqMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAABLgAECn8aAAIjAAgJZh8LIQBFAgAjAAgJZh8LIQBFAgAAAA==.Felfüry:BAACLgAFFH8FAAMMAAIJ+QagDgBOAAAMAAIJ7gSgDgBOAAAkAAEJoQdbKgA4AAAuAAQKf0AABCQACQm/FN8RAAACACQACQm/FN8RAAACAAwACAm2BhwXAN0AACMAAglYCYv6AEMAAAAA.Felly:BAAALgAECgYJBgAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Festicules:BAAALgAECgQJBAAAAA==.Festyr:BAAALgAECgQJCAAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECgQJBgACAAAAAA==.Finella:BAAALgAECgkJDQAAAA==.Finneas:BAAALgAECgEJAQABLgAECggJHwAFANYcAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJLwAQAB4jAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgkJDQACAAAAAA==.',
Fj='Fjeighty:BAABLgAECn8hAAMkAAcJeA9QKAAoAQAkAAcJeA9QKAAoAQAjAAEJ6QOoKQEcAAAAAA==.',
Fo='Fogassann:BAAALgAECgcJCgAAAA==.Fogdemon:BAAALgAECgIJBAABLgAFFAUJFgAfAHMUAA==.Foggpy:BAACLgAFFH8WAAMfAAUJcxR0BAA/AQAfAAUJcxR0BAA/AQANAAQJnwOMawDdAAAuAAQKfycABB8ACAmeInUEADYCAB8ABwkkJXUEADYCAA0ABgkNG8FXAMABABwABgljGQ4fAFgBAAAA.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freinkenbaby:BAAALgAECgEJAQAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostlicious:BAAALgADCgEJAQAAAA==.Frostybear:BAABLgAECn9IAAIQAAkJARkaKgBrAgAQAAkJARkaKgBrAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAABLgAECn88AAMbAAkJXAtxIABGAQAbAAkJSAtxIABGAQAZAAIJQgScMgBBAAAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Gacy:BAAALgADCgEJAQAAAA==.Galaythien:BAAALgAECgUJCQAAAA==.Gang:BAAALgAECgUJBQABLgAFFAQJEQABADIOAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAjAEQaAA==.',
Ge='Geluria:BAABLgAECn8aAAMbAAkJdB39BgClAgAbAAkJdB39BgClAgAZAAEJ5Q77NwAuAAABLgAECgkJNAAaADckAA==.Geret:BAABLgAECn8iAAIFAAgJdxPubACKAQAFAAgJdxPubACKAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gh='Ghanaria:BAAALgAECgEJAQAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Gleesh:BAAALgAECgEJAQABLgAECggJFgAQAGIeAA==.Glitchy:BAABLgAECn9IAAMYAAkJ3x9mBwDXAgAYAAkJZx9mBwDXAgAlAAYJGhYeGAB/AQAAAA==.Glokraz:BAAALgAECgcJBwAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgYJDQAAAA==.',
Go='Goingtogetu:BAABLgAECn9IAAMGAAkJrSO3AQAkAwAGAAkJrSO3AQAkAwAFAAYJBxC8iwBPAQAAAA==.Gold:BAAALgAECgIJAgABLgAECgkJKwAWAD4fAA==.Goldfarmr:BAABLgAECn8rAAIWAAkJPh/LCwCeAgAWAAkJPh/LCwCeAgAAAA==.Goldrawr:BAAALgAECgYJBwABLgAECgkJKwAWAD4fAA==.Goldshocker:BAAALgAECgQJBgABLgAECgkJKwAWAD4fAA==.Golduwu:BAAALgAECgEJAgABLgAECgkJKwAWAD4fAA==.Googlymoogly:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.',
Gr='Greed:BAAALgAFFAIJAgABLgAFFAYJHAAGAPwhAA==.Greeley:BAABLgAECn86AAISAAkJMCTMAABBAwASAAkJMCTMAABBAwAAAA==.Gregdapro:BAABLgAECn9NAAIbAAkJuSXUAABjAwAbAAkJuSXUAABjAwAAAA==.Gregnstone:BAABLgAECn8jAAIHAAkJlRZkJgDNAQAHAAkJlRZkJgDNAQABLgAECgkJTQAbALklAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAUJDwAiAGAQAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAcJIwAdACsdAA==.Gunnyal:BAABLgAECn8sAAMUAAcJhRSNHABuAQAUAAcJKBSNHABuAQAdAAQJsAnVaQCtAAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8wAAIRAAkJUyO2BAAMAwARAAkJUyO2BAAMAwAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8jAAMdAAcJKx2TBAAJAgAdAAcJKx2TBAAJAgAUAAEJNAEQDgA8AAAuAAQKfzwAAx0ACQktJRQCAFQDAB0ACQktJRQCAFQDABQAAwldHC04ANoAAAAA.Hakyahi:BAAALgADCggJCAAAAA==.Hallokitty:BAAALgAECgEJAQAAAA==.Hank:BAAALgADCgYJBgAAAA==.Happerixie:BAAALgADCgkJCQAAAA==.Harkin:BAABLgAECn82AAIFAAkJDxJdWQC3AQAFAAkJDxJdWQC3AQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgAECgUJCwAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIRAAcJXQu2SgD7AAARAAcJXQu2SgD7AAAAAA==.Hermioné:BAAALgADCgUJBQAAAA==.Hevy:BAABLgAECn88AAIjAAkJuBhHJAA0AgAjAAkJuBhHJAA0AgAAAA==.',
Hi='Hilarius:BAAALgAECggJEQAAAA==.Hiraeth:BAAALgAECgUJCQAAAA==.Hirukon:BAAALgAECgEJAQAAAA==.',
Ho='Holydadbod:BAAALgAECgQJBwABLgAFFAMJBwAaAG0gAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn9FAAIFAAkJARmNKgBNAgAFAAkJARmNKgBNAgAAAA==.Hottice:BAAALgAECgEJAQAAAA==.Howlinnbrews:BAABLgAFFH8HAAMPAAMJBiPiGAD8AAAPAAMJ2BviGAD8AAAaAAEJ6CWgSwBmAAAAAA==.Howlinplague:BAAALgAECgYJCQAAAA==.',
Hu='Hulkhogan:BAABLgAECn8fAAIVAAkJAR3BBwB5AgAVAAkJAR3BBwB5AgAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIjAAMJRBrsWADSAAAjAAMJRBrsWADSAAAuAAQKfycAAiMACAkuIrAVANQCACMACAkuIrAVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMEAAgJjBh2JwAMAgAEAAgJjBh2JwAMAgAeAAIJ1hIlQwBHAAAAAA==.Idrizzt:BAAALgAECgYJBgAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8aAAIPAAcJVBY4NAAoAQAPAAcJVBY4NAAoAQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Io:BAABLgAFFH8HAAIaAAQJJh1DFgBfAQAaAAQJJh1DFgBfAQAAAA==.Iobo:BAABLgAECn8vAAITAAcJZBQSHgCoAQATAAcJZBQSHgCoAQAAAA==.',
Ir='Ironhidez:BAABLgAECn84AAIFAAkJYA2yZQCaAQAFAAkJYA2yZQCaAQAAAA==.',
Is='Isaarek:BAABLgAECn8fAAIiAAkJkxVAFAAzAgAiAAkJkxVAFAAzAgAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDgAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAcJIAALAIUbAA==.Jasmini:BAAALgAECgEJAQAAAA==.Jastia:BAABLgAECn8XAAIcAAYJpxuqCwB4AQAcAAYJpxuqCwB4AQAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jeb:BAAALgAECgEJAgABLgAFFAEJAQACAAAAAA==.Jebopally:BAAALgAECgMJBAABLgAFFAEJAQACAAAAAA==.Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8sAAMNAAkJAhweHQBvAgANAAkJAhweHQBvAgAcAAEJAAD2bQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8vAAIFAAkJTw59WwCxAQAFAAkJTw59WwCxAQAAAA==.',
Jo='Joecephus:BAABLgAECn8nAAIHAAcJZyKWDgCjAgAHAAcJZyKWDgCjAgAAAA==.Joehex:BAABLgAECn88AAIVAAkJgyHvAwDmAgAVAAkJgyHvAwDmAgAAAA==.Joeschmonk:BAAALgAECgQJBAAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Jubelius:BAAALgAECgYJCQABLgAECgkJHwAKAMUVAA==.Judgematt:BAABLgAECn8WAAIHAAkJBRQWGQAzAgAHAAkJBRQWGQAzAgAAAA==.Justin:BAABLgAECn8fAAIUAAkJvhUdDQANAgAUAAkJvhUdDQANAgAAAA==.',
Ka='Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAISAAgJ1AwHEwAhAQASAAgJ1AwHEwAhAQABLgAECggJFQARANoWAA==.Kaleesh:BAACLgAFFH8RAAImAAYJpCVHAQD+AQAmAAYJpCVHAQD+AQAuAAQKfyUAAiYACAkJJkcBAGgDACYACAkJJkcBAGgDAAAA.Kallux:BAABLgAECn89AAIbAAkJRx5/BwCaAgAbAAkJRx5/BwCaAgAAAA==.Kananga:BAABLgAECn8cAAIWAAcJlxijIQCqAQAWAAcJlxijIQCqAQAAAA==.Karavira:BAAALgAECgEJAQAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgAECgYJBgAAAA==.',
Ke='Kelindina:BAAALgAECgMJDQAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Keoeu:BAAALgAECggJCwAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgUJCgAAAA==.',
Ki='Kieleron:BAABLgAECn8jAAIIAAgJARM5GQD8AQAIAAgJARM5GQD8AQAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJEAAAAA==.Kiermaxim:BAABLgAECn8mAAIRAAgJNBwcGwA6AgARAAgJNBwcGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Killon:BAAALgAECgEJAQABLgAECgkJOQAFADIUAA==.Kindred:BAAALgAECggJCAAAAA==.Kiragrande:BAABLgAECn8iAAIDAAkJxBBkKgDFAQADAAkJxBBkKgDFAQAAAA==.Kiraneth:BAABLgAECn8gAAIPAAgJMBB8KgBdAQAPAAgJMBB8KgBdAQAAAA==.Kirbie:BAAALgADCgUJBQAAAA==.Kirial:BAAALgADCgcJBwAAAA==.Kiriku:BAAALgAECggJEwAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgYJCgAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgADCgYJBgAAAA==.',
La='Lagartista:BAAALgAECgcJCgAAAA==.Largcok:BAAALgAECgIJAgAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Le='Lee:BAAALgAFFAUJAQAAAA==.Lefty:BAAALgADCgcJCgABLgAECgkJOwATAAoUAA==.Leyn:BAAALgAECgUJBQAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lilpwny:BAAALgAECgQJBAABLgAECgkJIQAJADEYAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn88AAIdAAkJ0iSuAgBCAwAdAAkJ0iSuAgBCAwAAAA==.Logres:BAAALgADCgEJAQAAAA==.Lokeira:BAACLgAFFH8OAAIOAAQJew1RPQDcAAAOAAQJew1RPQDcAAAuAAQKfykAAg4ACAmGG3UwAOcBAA4ACAmGG3UwAOcBAAAA.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn85AAIFAAkJMhRqTwDPAQAFAAkJMhRqTwDPAQAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgUJBgABLgAECgcJJAAQAE4TAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Luvbug:BAABLgAECn8WAAIKAAcJ3SJ9GAB2AgAKAAcJ3SJ9GAB2AgAAAA==.',
Ly='Lyais:BAAALgAECgMJAwAAAA==.Lyara:BAACLgAFFH8ZAAMOAAYJ5yMLBwAzAgAOAAYJ5yMLBwAzAgARAAQJRxiNHQAhAQAuAAQKfxwAAw4ACQnAIFAJAOICAA4ACAkVIFAJAOICABEABglnG2Y8ADYBAAAA.Lyi:BAAALgAFFAEJAgAAAA==.Lythos:BAACLgAFFH8HAAIbAAMJjwnYKQCVAAAbAAMJjwnYKQCVAAAuAAQKfxkAAhsACAmPE2obAHMBABsACAmPE2obAHMBAAAA.Lyu:BAAALgAFFAEJAQABLgAFFAYJGQAOAOcjAA==.Lyuu:BAABLgAFFH8GAAIQAAMJdxb2eQDfAAAQAAMJdxb2eQDfAAABLgAFFAYJGQAOAOcjAA==.',
['Lø']='Lørdøfßud:BAABLgAECn80AAMdAAkJGCNpBgDzAgAdAAkJuCFpBgDzAgAUAAcJEiO3CgA0AgAAAA==.',
Ma='Macguffin:BAAALgAECgEJAQAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJHQAjAIYLAA==.Maeve:BAAALgADCggJCAAAAA==.Makimá:BAAALgADCgYJBgABLgAECgkJHwAKAMUVAA==.Makinnor:BAAALgADCgEJAQAAAA==.Maklovin:BAAALgAECgEJAQAAAA==.Malifae:BAABLgAECn8bAAIYAAcJYSGbEwB3AgAYAAcJYSGbEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwAYAGEhAA==.Mankilla:BAAALgAECgQJBwAAAA==.Mansa:BAABLgAECn85AAInAAkJxRphAwB0AgAnAAkJxRphAwB0AgAAAA==.Mastamojo:BAABLgAECn89AAIHAAkJUAlqNQBxAQAHAAkJUAlqNQBxAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Maîev:BAAALgAECgUJBwAAAA==.',
Mc='Mcmurphy:BAAALgAECgcJDwAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Meanieman:BAAALgADCgEJAgAAAA==.Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAABLgAECn8hAAMfAAgJLBfQBwDhAQAfAAgJfxXQBwDhAQAcAAcJqRMfDwBAAQAAAA==.Melendaren:BAAALgAECgMJBgAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgAECgQJCAAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAECgMJAwAAAA==.Meowkug:BAAALgAECgEJAgAAAA==.Merscy:BAABLgAECn8bAAIWAAgJngp5NwASAQAWAAgJngp5NwASAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAABLgAECn8oAAMYAAcJTBT6KQB3AQAYAAcJTBT6KQB3AQAEAAYJ1gvHaADyAAABLgAECggJMAAWAFYTAA==.Metamonster:BAABLgAECn8pAAMLAAgJSw5VkAA+AQALAAgJHQhVkAA+AQAbAAYJOBA9LADvAAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgYJDAAAAA==.Mirko:BAABLgAECn8dAAIjAAcJhgtxhgAHAQAjAAcJhgtxhgAHAQAAAA==.Mistiah:BAABLgAFFH8IAAILAAMJQyCEbAAbAQALAAMJQyCEbAAbAQAAAA==.Mistyjoe:BAAALgADCgMJAwAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn9JAAIXAAkJvhs/AQCdAgAXAAkJvhs/AQCdAgAAAA==.Mokokniki:BAAALgADCgkJEgAAAA==.Moneie:BAAALgAECgUJDAAAAA==.Monger:BAAALgADCgIJAgAAAA==.Mongò:BAAALgAECgEJAQAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAFFAMJCAARAKwQAA==.Moondo:BAAALgAECgcJDgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Mooseymancer:BAAALgADCgcJDQAAAA==.Mootron:BAAALgADCgYJCgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mortimus:BAAALgAECgMJAwAAAA==.Mourningstar:BAACLgAFFH8aAAMLAAUJxiXFJgCwAQALAAQJxiXFJgCwAQAbAAEJAADiVwAAAAAuAAQKfyQAAwsACQkeJPMWALYCAAsACQkeJPMWALYCABsAAgm1ERtEAHIAAAEuAAUUBwkgAAsAhRsA.Mozaic:BAABLgAECn9IAAIVAAkJDRxJBwCFAgAVAAkJDRxJBwCFAgAAAA==.',
Mu='Mugrüíth:BAAALgAECgQJCQAAAA==.Muyoang:BAAALgADCgEJAQABLgAECgkJMwAEABMfAA==.',
My='Myfeethurt:BAAALgAECgMJAwABLgAECgkJNAAdABgjAA==.Myragê:BAAALgADCgkJDQABLgAECgEJAQACAAAAAA==.Myselia:BAABLgAECn8gAAIkAAgJhRagFQDOAQAkAAgJhRagFQDOAQAAAA==.Mystra:BAAALgAECgYJCwAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgADCgQJBAAAAA==.Naek:BAAALgAECgUJCwAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgUJCwACAAAAAA==.Nalthis:BAAALgAECgYJAwAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAABLgAECn8lAAIQAAcJHRIYiABiAQAQAAcJHRIYiABiAQAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAABLgAECn8ZAAIjAAgJvQmBgAATAQAjAAgJvQmBgAATAQAAAA==.Niem:BAABLgAECn8dAAIlAAkJhSUZAQBQAwAlAAkJhSUZAQBQAwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.Nitsi:BAAALgAECgEJAQABLgAECgkJNQAaAKAaAA==.',
No='Nocturnum:BAABLgAECn88AAIjAAkJRxlLHABhAgAjAAkJRxlLHABhAgAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8KAAIfAAUJQRdPAABcAQAfAAUJQRdPAABcAQAuAAQKfxwAAh8ACAktHi8BAPECAB8ACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAAAAA==.Odin:BAAALgAECgEJAgAAAA==.Odium:BAAALgADCgMJAwABLgAFFAQJDAAKANweAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAcJGAASAIwiAA==.',
Ol='Oldage:BAAALgAECgkJCQABLgAECgkJDQACAAAAAA==.Oldmage:BAAALgAECgEJAQAAAA==.Oldmongerpal:BAAALgAECgEJAQAAAA==.',
On='Onetwocowpow:BAABLgAECn9IAAIDAAkJ+hjhEwBtAgADAAkJ+hjhEwBtAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn9QAAMFAAkJViJwDwATAwAFAAkJViJwDwATAwAGAAkJTBf9CAA4AgAAAA==.Orionn:BAACLgAFFH8VAAIKAAUJRSC0CQAUAQAKAAUJRSC0CQAUAQAuAAQKf0QAAgoACQm2JREEAEoDAAoACQm2JREEAEoDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAABLgAECn8bAAIKAAkJng0VYQB5AQAKAAkJng0VYQB5AQAAAA==.',
Ov='Oven:BAABLgAECn8gAAIPAAgJVxbZHwCkAQAPAAgJVxbZHwCkAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.Patelz:BAAALgADCgQJBAAAAA==.',
Pe='Petoria:BAAALgADCgUJBQAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQABLgAECgkJDwACAAAAAA==.Polyeikon:BAAALgAECgUJCgAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgAECgMJBAAAAA==.Prayr:BAAALgADCgMJBAAAAA==.Praystation:BAAALgAECgUJCAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgYJCwAAAA==.',
Ra='Raekeshh:BAABLgAECn8ZAAINAAkJ3BVSMgAJAgANAAkJ3BVSMgAJAgAAAA==.Raelone:BAABLgAECn8dAAQcAAkJGBG7IQCVAAANAAUJYg0fpAD0AAAcAAYJZBK7IQCVAAAfAAEJ5RMiMwBIAAAAAA==.Rageofmommy:BAAALgAECgMJBAAAAA==.Raidoe:BAABLgAECn9FAAMDAAkJmhvZDgCjAgADAAkJmhvZDgCjAgAPAAMJOQsAbwBmAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn8zAAIKAAkJoxhrLAAiAgAKAAkJoxhrLAAiAgAAAA==.Rant:BAAALgAECgYJCwAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.Razorbeams:BAAALgAECgQJBAABLgAECgkJSQAXAL4bAA==.',
Re='Redishpanda:BAAALgADCgcJFAAAAA==.Redshammy:BAAALgAFFAIJAwAAAA==.Relion:BAAALgAECgcJCwABLgAECgkJOwAFAHsQAA==.',
Rh='Rheavin:BAAALgADCgUJBQAAAA==.Rhell:BAACLgAFFH8OAAIHAAQJqhMqJgDoAAAHAAQJqhMqJgDoAAAuAAQKfzUAAgcACQnCHz0JAO4CAAcACQnCHz0JAO4CAAAA.',
Ri='Rinche:BAABLgAECn9FAAMRAAkJNxYeGgAFAgARAAkJNxYeGgAFAgAOAAkJ3gtbTgBrAQAAAA==.Rintche:BAAALgAECgUJBQAAAA==.',
Ro='Rolland:BAABLgAECn8cAAISAAgJTB/kBQAyAgASAAgJTB/kBQAyAgAAAA==.Rollf:BAAALgAECgMJAwAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAABLgAECn8bAAMNAAkJ9AjDYAB6AQANAAkJ9AjDYAB6AQAcAAQJ1wRFJwBwAAAAAA==.',
Ru='Rudo:BAABLgAECn8fAAMKAAkJxRVZIgA3AgAKAAkJxRVZIgA3AgATAAEJrgKPZgAnAAAAAA==.Rumproblem:BAABLgAECn8uAAMIAAkJDRIzFgAbAgAIAAkJDRIzFgAbAgAJAAcJuAs7NgA1AQAAAA==.Runnamuuk:BAABLgAECn82AAIjAAkJGBR2NADqAQAjAAkJGBR2NADqAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryegar:BAAALgADCgkJCQAAAA==.Ryeger:BAABLgAECn8/AAMeAAkJ/B/UAgDqAgAeAAkJ/B/UAgDqAgAYAAMJpgt8YQCFAAAAAA==.',
['Rá']='Ráh:BAAALgADCgEJAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn8vAAIlAAkJ5BSMFgCNAQAlAAkJ5BSMFgCNAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBQABLgAECgMJDQACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn87AAMFAAkJexBwUgDIAQAFAAkJexBwUgDIAQAHAAkJYwObQgAuAQAAAA==.Sandbones:BAAALgAECgUJDAABLgAECgkJSQAXAL4bAA==.Sandraice:BAABLgAECn8fAAIFAAgJ0QYyhwBsAQAFAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sanielan:BAAALgADCgMJBAAAAA==.Sansami:BAABLgAECn87AAIaAAgJpRsQFgDzAQAaAAgJpRsQFgDzAQAAAA==.Saphron:BAAALgAECgQJBAAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAABLgAECn8cAAMYAAcJnwc0RgDmAAAYAAcJnwc0RgDmAAAEAAUJDQObpgBfAAAAAA==.',
Sc='Sc:BAAALgAECgcJBwABLgAECgkJKgAQAE4jAA==.Scalebagz:BAABLgAECn8gAAMgAAkJSB7cBQCqAgAgAAkJSB7cBQCqAgAiAAgJvRx2HwDVAQAAAA==.Schism:BAAALgAECgEJAQAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgAECgQJBAAAAA==.Senyorseven:BAAALgAECgYJDgAAAA==.Seo:BAAALgAECgQJCAAAAA==.Serabeara:BAAALgAECgEJAQAAAA==.Setresh:BAABLgAECn9QAAITAAkJwhWjEQAbAgATAAkJwhWjEQAbAgAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadöwsöng:BAABLgAECn85AAIVAAgJ3QsdIAAlAQAVAAgJ3QsdIAAlAQAAAA==.Shaedelana:BAABLgAECn8ZAAQIAAYJrBqyOQAeAQAIAAUJShOyOQAeAQAWAAQJ5xvbTwD4AAAJAAUJpA8SSQDiAAAAAA==.Shamrox:BAAALgAECggJDwAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJMwAEABMfAA==.Shinygoat:BAAALgADCgIJAgABLgAECgkJKgAMAI8fAA==.Shivyn:BAABLgAECn8/AAMOAAkJTRppIABBAgAOAAkJTRppIABBAgARAAEJFwW5jQAqAAAAAA==.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAcJGAASAIwiAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAACLgAFFH8KAAMbAAMJng+xLgBwAAALAAIJBA87zQCLAAAbAAIJrwuxLgBwAAAuAAQKfy4AAwsACQmlGW1DAPIBAAsACQmlGW1DAPIBABsABQmtD1UuAMwAAAAA.Sickkid:BAABLgAECn8+AAIdAAgJzCJsCQDFAgAdAAgJzCJsCQDFAgAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silkiegirl:BAABLgAECn8gAAIdAAkJahQUGgAXAgAdAAkJahQUGgAXAgAAAA==.Silvershine:BAABLgAECn8VAAMEAAYJ6w4lgADaAAAEAAUJiAslgADaAAAeAAQJuAYHMwCAAAAAAA==.Silverwolf:BAAALgAECgIJAgAAAA==.Sindrya:BAAALgAECgUJBwAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slayne:BAAALgAECgEJAQAAAA==.Slaänesh:BAAALgADCgcJBwABLgAECgkJMwAEABMfAA==.Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJDAACAAAAAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgkJEAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgABLgAFFAMJCAALAEMgAA==.Snuggles:BAABLgAECn8lAAIkAAgJjxqLEQAEAgAkAAgJjxqLEQAEAgABLgAFFAYJGwATAHcUAA==.',
So='Solidgen:BAEALgAECgEJAgABLgAFFAYJGAAFACsRAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Sonofalich:BAAALgAECgkJCQAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAABLgAECn8WAAMVAAgJNRZxFgCGAQAVAAgJNRZxFgCGAQAUAAMJUgOpNABeAAAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgQJDgAAAA==.',
Ss='Ssraeshza:BAABLgAFFH8KAAIlAAUJ9BmqCgAwAQAlAAUJ9BmqCgAwAQABLgAFFAYJHAAGAPwhAA==.',
St='Staretra:BAABLgAECn9BAAMJAAkJOBImGwDlAQAJAAkJOBImGwDlAQAWAAQJowaxUACNAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.',
Su='Sublevels:BAAALgADCgYJBgAAAA==.Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECggJEQAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Symana:BAABLgAECn8xAAIWAAkJER52DQCDAgAWAAkJER52DQCDAgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgAECgEJAQAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgcJEQAAAA==.',
['Sö']='Sörceress:BAAALgAECgYJDgAAAA==.',
Ta='Taadra:BAABLgAECn9NAAIOAAkJUx9dCgAGAwAOAAkJUx9dCgAGAwAAAA==.Talerah:BAAALgAECgMJBQAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAACLgAFFH8WAAIEAAUJIRnCFgCcAQAEAAUJIRnCFgCcAQAuAAQKfxgAAwQACQnvF2YeAEwCAAQACQnvF2YeAEwCACUAAgkPE5tIAHIAAAAA.Talona:BAAALgAFFAEJAQABLgAFFAUJCgAfAEEXAA==.Tandaan:BAAALgADCgkJCgABLgAECgkJGQANANwVAA==.Tanjent:BAABLgAECn8eAAIKAAYJDA1/kQARAQAKAAYJDA1/kQARAQAAAA==.Tanok:BAAALgADCgYJBgAAAA==.Tapio:BAABLgAECn8qAAITAAcJWhY9IACYAQATAAcJWhY9IACYAQAAAA==.Tatsuma:BAAALgAECgYJDgABLgAECggJJAAFADAdAA==.Tatsumå:BAAALgAECgcJEgABLgAECggJJAAFADAdAA==.Tavvi:BAAALgAECgYJBgABLgAECgcJFgAKAN0iAA==.',
Te='Terp:BAAALgAECgMJBgAAAA==.',
Th='Thalfinore:BAAALgAECgcJEgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Therogue:BAAALgAECgIJAgAAAA==.Thorincan:BAAALgAECgkJBwAAAA==.Thorrs:BAAALgAECgIJBwAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thorwar:BAAALgADCgEJAQAAAA==.Thuglifé:BAAALgADCgYJDQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECgQJBgACAAAAAA==.Tidemaiden:BAAALgAECgYJEAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgABLgAFFAMJAwACAAAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tipsymancer:BAABLgAECn9IAAIaAAkJDSKhAwARAwAaAAkJDSKhAwARAwAAAA==.Tirael:BAAALgAECgYJBQABLgAFFAUJAQACAAAAAA==.Tishi:BAAALgADCggJCAAAAA==.',
To='Tomö:BAAALgAECgkJBAAAAA==.Tossme:BAAALgAECgEJAQABLgAFFAMJBwAaAG0gAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Treesus:BAABLgAECn8fAAIYAAkJLhqWGwAmAgAYAAkJLhqWGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECgkJHwAKAMUVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Ts='Tsu:BAAALgADCgkJCQAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQQAAgJ+iPQNAA/AgAQAAgJXCHQNAA/AgAXAAMJPCR6BwAlAQAoAAEJTQ0VDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8lAAIEAAkJsRh1IQA0AgAEAAkJsRh1IQA0AgAAAA==.',
Un='Undeadgnome:BAAALgAECgMJAwAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.',
Va='Vainin:BAAALgAECgQJDgAAAA==.Valle:BAAALgAFFAEJAQAAAA==.Valry:BAAALgAECgYJDgAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAQJBgAVAEkXAA==.Variable:BAAALgAECgcJBwAAAA==.Vashdin:BAABLgAECn8iAAIFAAcJNxu/VQC/AQAFAAcJNxu/VQC/AQAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECgkJHwAKAMUVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velashis:BAABLgAECn8uAAIEAAkJKhytDQDlAgAEAAkJKhytDQDlAgAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAABLgAFFH8IAAIRAAMJrBCNMADBAAARAAMJrBCNMADBAAAAAA==.Vett:BAAALgADCgMJAwABLgAECgQJDgACAAAAAA==.',
Vi='Viable:BAAALgAECgUJCgAAAA==.Vibes:BAAALgAECgQJBAAAAA==.Victorvega:BAAALgAECgMJAwABLgAECgkJHwAKAMUVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8QAAMDAAMJtRJyNAC6AAADAAMJtRJyNAC6AAAPAAIJlxm9KgCSAAAuAAQKfyQAAw8ACQndHRcQAH8CAA8ACAmuHRcQAH8CAAMABQnvH0pOABwBAAAA.Vivila:BAAALgAECgMJBAABLgAECgkJPAAjALgYAA==.Vivillian:BAABLgAFFH8HAAIIAAMJjg+yLgDAAAAIAAMJjg+yLgDAAAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Vordilina:BAABLgAECn8cAAQoAAkJqhjfAQBcAgAoAAkJqhjfAQBcAgAXAAEJuAV9IAAtAAAQAAEJrQHbiAEcAAAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQgAAgJKhn4EwAGAgAgAAgJKhn4EwAGAgAhAAQJxRirFAC7AAAiAAEJygMMlQAkAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAABLgAECn8wAAMOAAcJnhreMQDgAQAOAAcJnhreMQDgAQARAAcJMhNLMwBiAQAAAA==.',
Vy='Vynae:BAAALgADCgcJBAAAAA==.',
['Vé']='Véxx:BAABLgAECn8uAAQMAAgJpB6LBABoAgAMAAgJpB6LBABoAgAkAAUJYAizQgDtAAAjAAEJdAGj9QAZAAAAAA==.',
['Ví']='Víx:BAAALgAECgYJBgAAAA==.',
['Vî']='Vîper:BAAALgAECgYJCwAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Warihor:BAABLgAECn8vAAMUAAgJeQwlLQANAQAdAAgJIwq9PABMAQAUAAgJhQklLQANAQAAAA==.Waycaps:BAABLgAFFH8FAAIlAAQJUBU4DQAQAQAlAAQJUBU4DQAQAQAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAACLgAFFH8LAAIfAAQJQyRuAQCqAQAfAAQJQyRuAQCqAQAuAAQKfy4AAh8ACQk/JKoAACYDAB8ACQk/JKoAACYDAAAA.',
Wh='Whïte:BAAALgAECgEJAgAAAA==.',
Wi='Wiegraf:BAAALgAECgIJAwABLgAECgkJMwAEABMfAA==.Wife:BAAALgAECgMJAwAAAA==.Withers:BAAALgADCgQJBAAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJDQAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECgYJCQAAAA==.',
['Wä']='Wärbëef:BAAALgADCgEJAQAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECgQJBgACAAAAAA==.',
Xo='Xorxel:BAAALgAECgMJBwAAAA==.',
Ya='Yacob:BAABLgAECn81AAIWAAkJOx1OCQDJAgAWAAkJOx1OCQDJAgAAAA==.',
Ye='Yenneferr:BAAALgADCgUJBQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8zAAIEAAkJEx/fCgAHAwAEAAkJEx/fCgAHAwAAAA==.',
Yh='Yhwach:BAACLgAFFH8LAAIbAAUJtAywIADVAAAbAAUJtAywIADVAAAuAAQKfyEAAhsACAk4GNcSANgBABsACAk4GNcSANgBAAAA.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAABLgAFFH8HAAIFAAQJGhD3PgAgAQAFAAQJGhD3PgAgAQABLgAECgkJDQACAAAAAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECgQJBgAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgcJCwAAAA==.',
Za='Zaeden:BAABLgAECn8cAAIDAAcJmx6fFgANAgADAAcJmx6fFgANAgABLgAECgkJGAALADUgAA==.Zaft:BAAALgADCgYJBgAAAA==.Zaftdh:BAABLgAECn81AAIjAAkJqhUrMgDzAQAjAAkJqhUrMgDzAQAAAA==.Zaha:BAABLgAECn8eAAIQAAYJ2iKdXAAkAgAQAAYJ2iKdXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zappsz:BAAALgAECgYJBgAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zedfrey:BAABLgAECn82AAIFAAkJ8xPnOwAKAgAFAAkJ8xPnOwAKAgAAAA==.Zem:BAABLgAECn8rAAIdAAgJux/lEABpAgAdAAgJux/lEABpAgAAAA==.Zeroultra:BAABLgAECn83AAIdAAgJsR3HEABrAgAdAAgJsR3HEABrAgAAAA==.Zeräse:BAABLgAECn8VAAIIAAgJRw80IgCvAQAIAAgJRw80IgCvAQABLgAECgkJMwAEABMfAA==.Zeusdh:BAAALgADCgkJCQAAAA==.Zeusmos:BAABLgAECn81AAIPAAkJkCZPAACPAwAPAAkJkCZPAACPAwAAAA==.',
Zi='Zithenex:BAABLgAECn8wAAIhAAcJqhGMCwBSAQAhAAcJqhGMCwBSAQAAAA==.',
Zo='Zoeÿ:BAAALgAECgEJBAAAAA==.',
Zw='Zwar:BAAALgAECgIJAgAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAABLgAECn8aAAIdAAYJGxUkQAA9AQAdAAYJGxUkQAA9AQAAAA==.',
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
