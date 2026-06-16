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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Priest-Discipline','Priest-Shadow','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Vengeance','Warlock-Demonology','Hunter-Marksmanship','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Warrior-Fury','Shaman-Elemental','Hunter-Survival','Warrior-Arms','Warrior-Protection','Priest-Holy','Mage-Arcane','Druid-Balance','DeathKnight-Frost','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Guardian','Shaman-Enhancement','Rogue-Assassination','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-06-14',data={Aa='Aaminae:BAABLgAECn86AAIBAAkJkxjlDABWAgABAAkJkxjlDABWAgAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgUJCgAAAA==.Abracastabya:BAAALgAFFAEJAQAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.Absolution:BAAALgAECgQJBQAAAA==.Abÿss:BAAALgAECgYJBgAAAA==.',
Ad='Adachï:BAABLgAECn8WAAIDAAYJiRp6NACfAQADAAYJiRp6NACfAQABLgAECgkJMwAEABMfAA==.Adevil:BAAALgAECgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aegon:BAAALgADCgkJCQAAAA==.Aethlin:BAABLgAECn81AAMFAAkJ4BtEMgA2AgAFAAkJjRlEMgA2AgAGAAgJdhsrCwATAgAAAA==.Aetreyu:BAAALgAECgcJEgAAAA==.Aeturnas:BAABLgAECn8xAAIHAAkJ7B9+CAACAwAHAAkJ7B9+CAACAwAAAA==.',
Ag='Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanima:BAABLgAECn8dAAMIAAgJjQwHKgCEAQAIAAgJjQwHKgCEAQAJAAYJ3AbBUADNAAAAAA==.Aldky:BAAALgADCgkJDgAAAA==.Aliana:BAAALgAFFAEJAQAAAA==.Alinthe:BAAALgADCgkJCQAAAA==.Allindis:BAAALgAECgYJCQABLgAECgkJJQAEALEYAA==.Allypally:BAAALgAECgEJAQAAAA==.Alphamage:BAAALgADCggJCAAAAA==.Alphamonk:BAAALgAECgkJEQAAAA==.Alros:BAABLgAECn9HAAIKAAkJfiMfBgAwAwAKAAkJfiMfBgAwAwAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgAECgQJCAAAAA==.',
Am='Amardyton:BAAALgAECgYJBwAAAA==.',
An='Aneas:BAAALgAECgYJDwAAAA==.Antäres:BAAALgADCgQJBAABLgAECgkJMwAEABMfAA==.',
Ap='Apolex:BAAALgADCgUJBQAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgMJAwACAAAAAA==.Arctica:BAAALgADCgQJBAAAAA==.Arette:BAAALgAECgcJBwAAAA==.Arkades:BAABLgAECn8hAAIFAAkJrxtnIgB7AgAFAAkJrxtnIgB7AgAAAA==.Arkshade:BAABLgAECn83AAILAAcJfhLTfQBmAQALAAcJfhLTfQBmAQAAAA==.Arlia:BAAALgAECgkJEQABLgAFFAIJBAACAAAAAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECgkJKgAMAI8fAA==.Aryn:BAAALgAECgEJAQAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgYJCwACAAAAAA==.Ashor:BAAALgAECgIJAgAAAA==.Asmo:BAAALgADCggJGAAAAA==.Astarii:BAAALgAECgEJBQAAAA==.Asterica:BAABLgAECn9QAAINAAkJWBheMQASAgANAAkJWBheMQASAgAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.Atormunster:BAAALgADCgMJAwABLgAECggJJQAOAB4QAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAIPAAYJ+A16UwA4AQAPAAYJ+A16UwA4AQAAAA==.',
Av='Averynicole:BAABLgAECn8ZAAIQAAcJBxaiKwBgAQAQAAcJBxaiKwBgAQAAAA==.',
Aw='Awasjr:BAABLgAECn8mAAIKAAkJlh82GACTAgAKAAkJlh82GACTAgAAAA==.Awassy:BAAALgAECgEJAgAAAA==.',
Ay='Ayano:BAABLgAECn8WAAIRAAgJYh7oSQD7AQARAAgJYh7oSQD7AQAAAA==.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balanla:BAAALgAECgMJAwABLgAECgkJNAASABgjAA==.Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDwABLgAECgkJMwAEABMfAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgAECgEJAQAAAA==.Bearhug:BAABLgAECn8uAAMDAAgJxxdkIACwAQADAAcJ7RlkIACwAQAQAAcJ2geBQgANAQABLgAFFAQJDAATAJ8KAA==.Bearshock:BAACLgAFFH8MAAMTAAQJnwoKLADfAAATAAQJnwoKLADfAAAPAAEJTACojAAdAAAuAAQKfxwAAhMACAl7G0wUAEcCABMACAl7G0wUAEcCAAAA.Beasty:BAABLgAECn8lAAMOAAgJHhB0EQBAAQAOAAgJHhB0EQBAAQAUAAYJhwSRPQDWAAAAAA==.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAABLgAECn83AAIGAAkJ5CTtAABUAwAGAAkJ5CTtAABUAwAAAA==.Beeb:BAAALgAECgUJDgABLgAECgkJNwAGAOQkAA==.Beefisting:BAAALgAECgYJDAABLgAECgkJNwAGAOQkAA==.Beethicc:BAAALgAECgEJBAABLgAECgkJNwAGAOQkAA==.Beeuwu:BAAALgAECgIJAwABLgAECgkJNwAGAOQkAA==.Beliara:BAAALgAECgkJDQAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Belshuntress:BAAALgAECgEJAgAAAA==.Beverage:BAAALgAECgEJAQAAAA==.',
Bi='Bicboi:BAAALgAECgEJAQAAAA==.Bigmattyl:BAAALgAECgcJCgAAAA==.Bionarra:BAABLgAECn8uAAIRAAkJtBrXMgBLAgARAAkJtBrXMgBLAgAAAA==.Bishopwr:BAABLgAECn8oAAMVAAkJ8BYpDAAiAgAVAAkJ8BYpDAAiAgAWAAYJCwqkMgCvAAAAAA==.Bittertøfu:BAABLgAECn8eAAITAAcJfQaRWADXAAATAAcJfQaRWADXAAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJCgAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blessu:BAAALgAECgEJAQAAAA==.Blitê:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Bm='Bmpfrostie:BAABLgAECn8UAAIRAAcJdg01yABYAQARAAcJdg01yABYAQAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECgkJNQAXADsdAA==.Bohica:BAAALgAECggJDgAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAABLgAFFAMJCQALAEMgAA==.',
Br='Brakug:BAABLgAECn8vAAMRAAkJHiMULgC5AgARAAkJHiMULgC5AgAYAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAIJAwAAAA==.Brem:BAACLgAFFH8IAAIYAAMJiBnhAQD6AAAYAAMJiBnhAQD6AAAuAAQKfxsAAhgACAmCHB4EABICABgACAmCHB4EABICAAAA.Bretagnesse:BAABLgAECn8UAAIZAAgJ2wUCRQD1AAAZAAgJ2wUCRQD1AAAAAA==.Briara:BAAALgAECgYJDwAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgAECgQJBQAAAA==.Broníx:BAAALgAECgEJBQAAAA==.Bropeep:BAACLgAFFH8FAAILAAMJChtOiwDuAAALAAMJChtOiwDuAAAuAAQKf0QAAwsACQkDJEUGAEUDAAsACQkDJEUGAEUDABoABAmdFBIcAOwAAAAA.Brotality:BAAALgADCgMJBAAAAA==.Brynhildr:BAAALgAECgcJDwABLgAFFAQJDAAbAJ4gAA==.',
Bu='Bullshott:BAABLgAECn8jAAIKAAkJrx24HAB2AgAKAAkJrx24HAB2AgAAAA==.Bum:BAABLgAECn8mAAMZAAkJsh/4BABRAwAZAAkJsh/4BABRAwAEAAEJ0xCM0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgAECgUJCQAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJEAAAAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBgAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAABLgAECn8cAAMLAAgJYxDCbQCIAQALAAgJ+g7CbQCIAQAcAAYJdA32MQDTAAAAAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8zAAIFAAkJXQjYiQBbAQAFAAkJXQjYiQBbAQAAAA==.Carrots:BAABLgAECn8tAAIKAAgJXRR1RwDIAQAKAAgJXRR1RwDIAQAAAA==.Cartman:BAABLgAFFH8GAAIWAAQJSRcvEwAGAQAWAAQJSRcvEwAGAQAAAA==.Cashmachine:BAABLgAECn8tAAIKAAkJAx9tGgCEAgAKAAkJAx9tGgCEAgAAAA==.Castorice:BAAALgAECgEJAQAAAA==.Catfight:BAABLgAECn83AAIGAAcJxhGIHQAmAQAGAAcJxhGIHQAmAQAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMNAAkJdBhqLgBTAgANAAkJdBhqLgBTAgAdAAEJAABoZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8OAAQKAAUJcR/QMgBDAQAKAAUJTR7QMgBDAQAOAAEJISI3IwBlAAAUAAEJzA+bMQBIAAAuAAQKfxwABA4ACAmLIsIYAGYCAA4ACAkjIcIYAGYCAAoABQlPHSJbAJABABQAAwkrGKhLAIUAAAAA.Cheesecake:BAABLgAECn8wAAMdAAgJBRILDAB8AQAdAAgJBRILDAB8AQAeAAIJLQ6/KwBqAAAAAA==.Chihiko:BAAALgAECgMJAwAAAA==.Choks:BAABLgAECn8tAAISAAcJTw39QABBAQASAAcJTw39QABBAQAAAA==.Chromie:BAAALgADCgMJAwAAAA==.Chubbycat:BAABLgAECn8VAAMEAAcJLhmOPQCuAQAEAAcJLhmOPQCuAQAfAAUJYh2WFwBTAQAAAA==.Chuggz:BAABLgAECn81AAIbAAkJoBowDQBjAgAbAAkJoBowDQBjAgAAAA==.Chéfboyrlee:BAACLgAFFH8ZAAIJAAgJhRc8BQAmAgAJAAgJhRc8BQAmAgAuAAQKfzYAAgkACQn6InUEABMDAAkACQn6InUEABMDAAAA.',
Ci='Cizmac:BAAALgAECgYJDAAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgADCggJDAAAAA==.Cownado:BAABLgAECn82AAIbAAcJnBLGKgBfAQAbAAcJnBLGKgBfAQABLgAECggJHAALAGMQAA==.',
Cr='Crematorion:BAAALgAECgMJAwAAAA==.Crouton:BAAALgADCgkJCgAAAA==.',
Cu='Cursedspirit:BAAALgAECgQJBwAAAA==.',
Cy='Cybelem:BAABLgAECn8tAAITAAkJmB4kEABxAgATAAkJmB4kEABxAgAAAA==.Cyfelen:BAABLgAECn8ZAAQdAAkJiB9fAQDYAgAdAAkJiB9fAQDYAgAeAAQJLxkMHQDUAAANAAIJrw+n9wByAAAAAA==.Cynleel:BAAALgAECggJEAABLgAECgkJMgAIAGsQAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQAAAA==.Damonstyle:BAAALgAECgEJAgAAAA==.Dandistyle:BAABLgAECn8fAAMbAAkJdx1DCwB/AgAbAAkJbh1DCwB/AgAQAAEJchK2fAAzAAAAAA==.Darknature:BAAALgAECgkJCQAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathblade:BAAALgAECgEJAQAAAA==.Deathmatrynn:BAAALgAECgYJDgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAACLgAFFH8FAAITAAIJ2gUNSQBnAAATAAIJ2gUNSQBnAAAuAAQKfxUAAhMACAnaFhAeAO8BABMACAnaFhAeAO8BAAAA.Deeviant:BAAALgAECggJDgAAAA==.Defend:BAAALgAECgYJBgABLgAFFAQJBgAWAEkXAA==.Delrager:BAACLgAFFH8HAAIBAAIJch5dLgCuAAABAAIJch5dLgCuAAAuAAQKfygAAgEABwmYIz0NAFACAAEABwmYIz0NAFACAAAA.Delyta:BAAALgAECgkJCQAAAA==.Demonicdawn:BAAALgADCgEJAQAAAA==.Demónícz:BAAALgAECgMJAwAAAA==.Derat:BAAALgAECgkJEQAAAA==.Destroy:BAAALgAECgMJAwABLgAFFAQJBgAWAEkXAA==.',
Di='Dibbydab:BAABLgAECn8gAAIPAAkJShJ6OQDGAQAPAAkJShJ6OQDGAQAAAA==.',
Dj='Django:BAABLgAECn82AAMZAAkJsyIABgD2AgAZAAkJsyIABgD2AgAEAAIJkAZcxQA+AAAAAA==.Djatalon:BAABLgAECn8WAAMgAAUJuAvCIgDWAAAgAAUJuAvCIgDWAAAhAAMJrAXIGwBsAAAAAA==.Djderpyderpy:BAAALgAECgYJDQAAAA==.Djehrtey:BAAALgAECgcJCAAAAA==.Djin:BAAALgAECgMJBAABLgAFFAQJDAAbAJ4gAA==.Djinni:BAACLgAFFH8MAAIbAAQJniD2EgCGAQAbAAQJniD2EgCGAQAuAAQKfzUAAxsACQk9IV4GANMCABsACAlsI14GANMCABAACQkSG3YOAF8CAAAA.',
Do='Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8fAAMaAAgJtxtUCAAIAgAaAAgJtxtUCAAIAgALAAMJsA2A/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8YAAQgAAcJNxlcDwDUAQAgAAcJNxlcDwDUAQAiAAQJuwzSYAC0AAAhAAEJAACAPAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Draknem:BAAALgAECgEJAQAAAA==.Dramaticus:BAAALgAECgQJBAAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drenleah:BAABLgAECn8XAAIdAAkJpRZTBQAZAgAdAAkJpRZTBQAZAgABLgAECgkJPwAjAKwZAA==.Drenlee:BAAALgAECgEJAgABLgAECgkJPwAjAKwZAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgAAAA==.Dryya:BAAALgAECgQJCAAAAA==.Drêck:BAAALgAECgEJAQAAAA==.',
Du='Dumblegear:BAABLgAECn8fAAMRAAgJpRU8awCjAQARAAgJpRU8awCjAQAYAAEJbQY0IAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAECgkJNAASABgjAA==.',
Dw='Dwagon:BAAALgADCgUJBQAAAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgADCgQJCAAAAA==.Dädärkbeëf:BAAALgADCgcJCQAAAA==.',
Ed='Edinna:BAABLgAECn80AAMRAAkJnhPaQgARAgARAAkJnhPaQgARAgAYAAQJTQoTEADBAAAAAA==.',
Ee='Eevie:BAAALgADCgMJAwAAAA==.',
Ei='Einekliene:BAAALgAECgcJBwAAAA==.',
Ek='Ekatrina:BAAALgAECgEJAQAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Eldernoc:BAAALgAECgUJCwAAAA==.Elessedil:BAAALgAECggJDgAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgYJDAAAAA==.Elyriana:BAABLgAECn8jAAMEAAkJpSDmCAAoAwAEAAkJpSDmCAAoAwAfAAEJqSAkQABZAAAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEBLgAECn8bAAIKAAYJqyFlPADsAQAKAAYJqyFlPADsAQABLgAECggJKAAKANMgAA==.Emixi:BAAALgAECgQJBQAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECggJDwAAAA==.Emritelan:BAAALgADCgkJDgAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8YAAIFAAYJixfUJABwAQAFAAYJixfUJABwAQAuAAQKfzEAAgUACQmaH5AkAHICAAUACQmaH5AkAHICAAAA.',
Ep='Epedemik:BAAALgAECgMJAwAAAA==.',
Er='Erazath:BAAALgAECgUJBgABLgAFFAMJBwAcAI8JAA==.Eredo:BAAALgAECgUJCAABLgAECgkJNAASABgjAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgAECgIJAgAAAA==.Erush:BAAALgAECgEJAQAAAA==.',
Es='Esha:BAAALgAECgEJAQAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ex='Exhul:BAAALgAECgEJAQAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Faewing:BAAALgAFFAIJBAAAAA==.Falar:BAAALgAECggJDQAAAA==.Fatelf:BAAALgADCgMJAwAAAA==.Fatowlbert:BAAALgAECgEJAgAAAA==.Faval:BAAALgAECggJDwABLgAECgkJKgAMAI8fAA==.Favel:BAABLgAECn8qAAMMAAkJjx9OAQAcAwAMAAgJ4iFOAQAcAwAjAAkJRwvyXgBpAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn9MAAIKAAkJcxmbIABiAgAKAAkJcxmbIABiAgAAAA==.Febz:BAABLgAECn8eAAIRAAgJbBsqMACyAgARAAgJbBsqMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAABLgAECn8aAAIjAAgJZh+HIgBFAgAjAAgJZh+HIgBFAgAAAA==.Felfüry:BAACLgAFFH8IAAMMAAMJwQfoDwBOAAAkAAIJegh+JAB5AAAMAAIJ7gToDwBOAAAuAAQKf0UABCQACQm/FPcSAP0BACQACQm/FPcSAP0BAAwACAlACH4WAPEAACMAAglYCaUDAUQAAAAA.Felly:BAAALgAECgYJBgAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Festicules:BAAALgAECgQJBAAAAA==.Festyr:BAAALgAECgQJCAAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECgQJBgACAAAAAA==.Finella:BAAALgAECgkJEgAAAA==.Finneas:BAAALgAECgEJAwABLgAECgkJIQAFAK8bAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJLwARAB4jAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgkJEgACAAAAAA==.',
Fj='Fjeighty:BAABLgAECn8nAAMkAAcJ9xGxJABPAQAkAAcJ9xGxJABPAQAjAAEJ6QPUNAEcAAAAAA==.',
Fo='Fogassann:BAABLgAECn8UAAILAAgJXByQKgBUAgALAAgJXByQKgBUAgABLgAECgkJNAASABgjAA==.Fogdemon:BAAALgAECgIJBAABLgAFFAUJFgAeAHMUAA==.Foggpy:BAACLgAFFH8WAAMeAAUJcxRFBQAxAQAeAAUJcxRFBQAxAQANAAQJnwPDcQDaAAAuAAQKfycABB4ACAmeInUEADYCAB4ABwkkJXUEADYCAA0ABgkNG8FXAMABAB0ABgljGQ4fAFgBAAAA.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freinkenbaby:BAAALgAECgEJAQAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostlicious:BAAALgADCgEJAQAAAA==.Frostnuts:BAAALgAECgEJAQAAAA==.Frostybear:BAABLgAECn9IAAIRAAkJARnNKwBoAgARAAkJARnNKwBoAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAABLgAECn9BAAMcAAkJXAs+IQBGAQAcAAkJSAs+IQBGAQAaAAIJQgTzNQBBAAAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Gacy:BAAALgAECgEJAQAAAA==.Galaythien:BAAALgAECgYJCwAAAA==.Gang:BAAALgAECgUJBQABLgAFFAQJEQABADIOAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAjAEQaAA==.',
Ge='Geluria:BAABLgAECn8aAAMcAAkJdB2PBwCgAgAcAAkJdB2PBwCgAgAaAAEJ5Q5QOwAuAAABLgAECgkJNAAbADckAA==.Geret:BAABLgAECn8iAAIFAAgJdxOycQCJAQAFAAgJdxOycQCJAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gh='Ghanaria:BAAALgAECgEJAQAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Gleesh:BAAALgAECgEJAQABLgAECggJFgARAGIeAA==.Glitchy:BAABLgAECn9IAAMZAAkJ3x/eBwDVAgAZAAkJZx/eBwDVAgAlAAYJGhaeGQB+AQAAAA==.Glokraz:BAAALgAECgcJBwAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgYJDQAAAA==.',
Go='Goingtogetu:BAABLgAECn9IAAMGAAkJrSPlAQAiAwAGAAkJrSPlAQAiAwAFAAYJBxAJkQBPAQAAAA==.Gold:BAAALgAECgIJAgABLgAECgkJKwAXAD4fAA==.Goldfarmr:BAABLgAECn8rAAIXAAkJPh+RDACbAgAXAAkJPh+RDACbAgAAAA==.Goldrawr:BAAALgAECgYJBwABLgAECgkJKwAXAD4fAA==.Goldshocker:BAAALgAECgQJBgABLgAECgkJKwAXAD4fAA==.Golduwu:BAAALgAECgEJAgABLgAECgkJKwAXAD4fAA==.Googlymoogly:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.Gottahvyhand:BAAALgAECgEJAQAAAA==.',
Gr='Greed:BAAALgAFFAIJAgABLgAFFAYJCwAlAKYYAA==.Greeley:BAABLgAECn86AAIOAAkJMCTeAAA+AwAOAAkJMCTeAAA+AwAAAA==.Gregdapro:BAABLgAECn9NAAIcAAkJuSXuAABgAwAcAAkJuSXuAABgAwAAAA==.Gregnstone:BAABLgAECn8jAAIHAAkJlRaqJwDMAQAHAAkJlRaqJwDMAQABLgAECgkJTQAcALklAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAUJEwAiAGAQAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAgJJAASAEUZAA==.Gunnyal:BAABLgAECn8yAAMVAAcJhRbZGQCIAQAVAAcJhRbZGQCIAQASAAUJhwrdZgDBAAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8wAAITAAkJUyMgBQAKAwATAAkJUyMgBQAKAwAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8kAAMSAAgJRRmrAwA+AgASAAgJRRmrAwA+AgAVAAEJNAEQDgA8AAAuAAQKfzwAAxIACQktJVwCAFADABIACQktJVwCAFADABUAAwldHOo5ANkAAAAA.Hakyahi:BAAALgADCggJCAAAAA==.Hallokitty:BAAALgAECgEJAQAAAA==.Hank:BAAALgADCgYJBgAAAA==.Happerixie:BAAALgADCgkJCQAAAA==.Harkin:BAABLgAECn82AAIFAAkJDxI2XQC2AQAFAAkJDxI2XQC2AQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgAECgYJDAAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAITAAcJXQvUTQD7AAATAAcJXQvUTQD7AAAAAA==.Hevy:BAABLgAECn8/AAIjAAkJrBnqIABNAgAjAAkJrBnqIABNAgAAAA==.',
Hi='Hilarius:BAAALgAECggJEQAAAA==.Hiraeth:BAAALgAECgUJCQAAAA==.Hirukon:BAAALgAECgEJAQAAAA==.',
Ho='Holydadbod:BAAALgAECgQJBwABLgAFFAQJDAAbAJ4gAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn9FAAIFAAkJARnuLABMAgAFAAkJARnuLABMAgAAAA==.Hottice:BAAALgAECgEJAQAAAA==.Howlinnbrews:BAABLgAFFH8HAAMQAAMJBiMoGgD0AAAQAAMJ2BsoGgD0AAAbAAEJ6CVlTgBlAAAAAA==.Howlinplague:BAAALgAECgYJCQAAAA==.',
Hu='Hulkhogan:BAABLgAECn8fAAIWAAkJAR1MCAB0AgAWAAkJAR1MCAB0AgAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIjAAMJRBo1XgDQAAAjAAMJRBo1XgDQAAAuAAQKfycAAiMACAkuIrAVANQCACMACAkuIrAVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMEAAgJjBhqKAAMAgAEAAgJjBhqKAAMAgAfAAIJ1hJaSABGAAAAAA==.Idrizzt:BAAALgAECgYJBgAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8aAAIQAAcJVBYkNgAoAQAQAAcJVBYkNgAoAQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Io:BAABLgAFFH8LAAIbAAQJoh+7FAB3AQAbAAQJoh+7FAB3AQAAAA==.Iobo:BAABLgAECn82AAIUAAcJFxZ5HAC6AQAUAAcJFxZ5HAC6AQAAAA==.',
Ir='Ironhidez:BAABLgAECn89AAIFAAkJPg4TZACmAQAFAAkJPg4TZACmAQAAAA==.',
Is='Isaarek:BAABLgAECn8fAAIiAAkJkxX7FAAyAgAiAAkJkxX7FAAyAgAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDgAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAgJIgALAN0YAA==.Jasmini:BAAALgAECgEJAwAAAA==.Jastia:BAABLgAECn8ZAAIdAAcJpBr7CAC3AQAdAAcJpBr7CAC3AQAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jeb:BAAALgAECgEJAgABLgAFFAEJAQACAAAAAA==.Jebopally:BAAALgAECgMJBAABLgAFFAEJAQACAAAAAA==.Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8sAAMNAAkJAhxkHgBtAgANAAkJAhxkHgBtAgAdAAEJAAD2bQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8vAAIFAAkJTw59XwCxAQAFAAkJTw59XwCxAQAAAA==.',
Jo='Joecephus:BAABLgAECn8uAAIHAAcJZyJTDwChAgAHAAcJZyJTDwChAgAAAA==.Joehex:BAABLgAECn88AAIWAAkJgyFQBADgAgAWAAkJgyFQBADgAgAAAA==.Joeschmonk:BAAALgAECgQJBAAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Jubelius:BAAALgAECgYJCQABLgAECgkJHwAKAMUVAA==.Judgematt:BAABLgAECn8WAAIHAAkJBRQsGgAyAgAHAAkJBRQsGgAyAgAAAA==.Justin:BAABLgAECn8fAAIVAAkJvhXWDQAJAgAVAAkJvhXWDQAJAgAAAA==.',
Ka='Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAIOAAgJ1AzIEwAhAQAOAAgJ1AzIEwAhAQABLgAFFAIJBQATANoFAA==.Kaleesh:BAACLgAFFH8RAAImAAYJpCWjAQD4AQAmAAYJpCWjAQD4AQAuAAQKfyUAAiYACAkJJkcBAGgDACYACAkJJkcBAGgDAAAA.Kallux:BAABLgAECn9GAAIcAAkJoCBHBQDVAgAcAAkJoCBHBQDVAgAAAA==.Kananga:BAABLgAECn8jAAIXAAcJYhmCIAC8AQAXAAcJYhmCIAC8AQAAAA==.Karavira:BAAALgAECgEJAQAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgAECgYJBgAAAA==.',
Ke='Kelindina:BAAALgAECgMJDQAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Keoeu:BAAALgAECggJDAAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgYJCwAAAA==.',
Ki='Kieleron:BAABLgAECn8kAAIIAAgJAROGGgD6AQAIAAgJAROGGgD6AQAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJEAAAAA==.Kiermaxim:BAABLgAECn8mAAITAAgJNBwcGwA6AgATAAgJNBwcGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Killon:BAAALgAECgEJAQABLgAECgkJOQAFADIUAA==.Kindred:BAAALgAECggJCAAAAA==.Kiragrande:BAABLgAECn8iAAIDAAkJxBDGLADHAQADAAkJxBDGLADHAQAAAA==.Kiraneth:BAABLgAECn8gAAIQAAgJMBDBLABYAQAQAAgJMBDBLABYAQAAAA==.Kirbie:BAAALgADCgUJBQAAAA==.Kirial:BAAALgAECgEJAQAAAA==.Kiriku:BAAALgAECggJEwAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgYJCgAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgADCgYJBgAAAA==.',
La='Lagartista:BAAALgAFFAEJAQAAAA==.Largcok:BAAALgAECgIJAgAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Le='Lee:BAAALgAFFAYJAQAAAA==.Lefty:BAAALgADCgcJCgABLgAECgkJOwAUAAoUAA==.Leyn:BAAALgAECgUJBQAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lilpwny:BAAALgAECgQJBAABLgAECgkJIQAJADEYAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn88AAISAAkJ0iQIAwA9AwASAAkJ0iQIAwA9AwAAAA==.Logres:BAAALgADCgEJAQAAAA==.Lokeira:BAACLgAFFH8OAAIPAAQJew3IQgDXAAAPAAQJew3IQgDXAAAuAAQKfykAAg8ACAmGG7AyAOUBAA8ACAmGG7AyAOUBAAAA.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn85AAIFAAkJMhQxUwDOAQAFAAkJMhQxUwDOAQAAAA==.Loonnah:BAAALgAECgIJAgAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgUJBgABLgAECgcJJAARAE4TAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Lupusregina:BAAALgAECgQJBAABLgAECgkJEAACAAAAAA==.Luvbug:BAABLgAECn8WAAIKAAcJ3SJ9GAB2AgAKAAcJ3SJ9GAB2AgAAAA==.',
Ly='Lyais:BAAALgAECgMJAwAAAA==.Lyara:BAACLgAFFH8ZAAMPAAYJ5yMYCQAsAgAPAAYJ5yMYCQAsAgATAAQJRxgWIQAUAQAuAAQKfxwAAw8ACQnAIFAJAOICAA8ACAkVIFAJAOICABMABglnGzE/ADUBAAAA.Lyi:BAAALgAFFAEJAgAAAA==.Lynn:BAAALgADCgEJAQAAAA==.Lythos:BAACLgAFFH8HAAIcAAMJjwllLQCPAAAcAAMJjwllLQCPAAAuAAQKfxkAAhwACAmPE2obAHMBABwACAmPE2obAHMBAAAA.Lyu:BAAALgAFFAEJAQABLgAFFAYJGQAPAOcjAA==.Lyuu:BAABLgAFFH8GAAIRAAMJdxaagADaAAARAAMJdxaagADaAAABLgAFFAYJGQAPAOcjAA==.',
['Lø']='Lørdøfßud:BAABLgAECn80AAMSAAkJGCP/BgDuAgASAAkJuCH/BgDuAgAVAAcJEiNLCwAxAgAAAA==.',
Ma='Macguffin:BAAALgAECgEJAQAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJHQAjAIYLAA==.Maeve:BAAALgADCggJCAAAAA==.Makimá:BAAALgADCgYJBgABLgAECgkJHwAKAMUVAA==.Makinnor:BAAALgAECgEJAgAAAA==.Maklovin:BAAALgAECgEJAwAAAA==.Malifae:BAABLgAECn8bAAIZAAcJYSGbEwB3AgAZAAcJYSGbEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwAZAGEhAA==.Mankilla:BAAALgAECgQJBwAAAA==.Mansa:BAACLgAFFH8GAAInAAMJTgfBCADDAAAnAAMJTgfBCADDAAAuAAQKfzkAAicACQnFGpMDAHMCACcACQnFGpMDAHMCAAAA.Mastamojo:BAABLgAECn89AAIHAAkJUAkQNwBxAQAHAAkJUAkQNwBxAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Mavis:BAAALgAECgIJAgAAAA==.Maîev:BAAALgAECgUJBwAAAA==.',
Mc='Mcmurphy:BAAALgAECggJEAAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Meanieman:BAAALgADCgEJAgAAAA==.Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAACLgAFFH8FAAIeAAIJTgigEACJAAAeAAIJTgigEACJAAAuAAQKfykAAx4ACAnRFyEHAAECAB4ACAnAFyEHAAECAB0ABwmpExgQAD0BAAAA.Melendaren:BAAALgAECgQJBwAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgAECgQJCAAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAFFAEJAQAAAA==.Meowkug:BAAALgAECgEJAgAAAA==.Merscy:BAABLgAECn8bAAIXAAgJngocOQASAQAXAAgJngocOQASAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAABLgAECn8wAAMZAAcJlBUCKACNAQAZAAcJlBUCKACNAQAEAAYJ1gumagDyAAAAAA==.Metamonster:BAABLgAECn8qAAMLAAkJcg33dwByAQALAAkJCgj3dwByAQAcAAYJOBA2LgDrAAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikaels:BAAALgAECgcJBwABLgAECgkJPgAjALsbAA==.Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgcJDQAAAA==.Mirko:BAABLgAECn8dAAIjAAcJhgvyigAHAQAjAAcJhgvyigAHAQAAAA==.Mistiah:BAABLgAFFH8JAAILAAMJQyC6cwAWAQALAAMJQyC6cwAWAQAAAA==.Mistyjoe:BAAALgADCgMJAwAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn9SAAIYAAkJOB0kAQC0AgAYAAkJOB0kAQC0AgAAAA==.Mokokniki:BAAALgADCgkJEgAAAA==.Moneie:BAAALgAECgUJDAAAAA==.Monger:BAAALgADCgIJAgAAAA==.Mongò:BAAALgAECgEJAQAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAFFAMJCAATAKwQAA==.Moondo:BAAALgAECgcJDgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Mooseymancer:BAAALgADCgcJDQAAAA==.Mootron:BAAALgADCgYJCgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mortimus:BAAALgAECgMJAwAAAA==.Mourningstar:BAACLgAFFH8aAAMLAAUJxiVLLQCoAQALAAQJxiVLLQCoAQAcAAEJAABIXgAAAAAuAAQKfyQAAwsACQkeJH8YALICAAsACQkeJH8YALICABwAAgm1EcpGAHAAAAEuAAUUCAkiAAsA3RgA.Mozaic:BAABLgAECn9RAAIWAAkJJxyoBwCFAgAWAAkJJxyoBwCFAgAAAA==.',
Mu='Mugrüíth:BAAALgAECgUJCgAAAA==.Muyoang:BAAALgADCgEJAQABLgAECgkJMwAEABMfAA==.',
My='Myfeethurt:BAAALgAECgQJBAABLgAECgkJNAASABgjAA==.Mymoon:BAAALgADCgMJAwAAAA==.Myragê:BAAALgADCgkJDQABLgAECgEJAQACAAAAAA==.Myselia:BAABLgAECn8iAAIkAAkJBhVuEgAEAgAkAAkJBhVuEgAEAgAAAA==.Mystra:BAAALgAECgYJCwAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgADCgQJBAAAAA==.Naek:BAAALgAECgYJDAAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgYJDAACAAAAAA==.Nalthis:BAAALgAECgYJAwAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAABLgAECn8sAAIRAAcJKxa/bACfAQARAAcJKxa/bACfAQAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAABLgAECn8ZAAIjAAgJvQnWhAATAQAjAAgJvQnWhAATAQAAAA==.Niem:BAABLgAECn8dAAIlAAkJhSU6AQBOAwAlAAkJhSU6AQBOAwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.Nitsi:BAAALgAECgEJAQABLgAECgkJNQAbAKAaAA==.',
No='Nocturnum:BAABLgAECn8+AAIjAAkJuxv5FwCEAgAjAAkJuxv5FwCEAgAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8KAAIeAAUJQRdPAABcAQAeAAUJQRdPAABcAQAuAAQKfxwAAh4ACAktHi8BAPECAB4ACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAAAAA==.Odin:BAAALgAECgEJAgAAAA==.Odium:BAAALgADCgMJAwABLgAFFAUJDgAKAHEfAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAcJGAAOAIwiAA==.',
Ol='Oldage:BAAALgAECgkJCQABLgAECgkJEgACAAAAAA==.Oldmage:BAAALgAECgEJAwAAAA==.Oldmongerpal:BAAALgAECgEJAQAAAA==.',
On='Onetwocowpow:BAABLgAECn9IAAIDAAkJ+hgcFQBtAgADAAkJ+hgcFQBtAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn9QAAMFAAkJViJwDwATAwAFAAkJViJwDwATAwAGAAkJTBeDCQA1AgAAAA==.Orionn:BAACLgAFFH8VAAIKAAUJRSC0CQAUAQAKAAUJRSC0CQAUAQAuAAQKf0QAAgoACQm2JawEAEUDAAoACQm2JawEAEUDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAABLgAECn8bAAIKAAkJnQ1KSQDCAQAKAAkJnQ1KSQDCAQAAAA==.',
Ov='Oven:BAABLgAECn8gAAIQAAgJVxaqIQCgAQAQAAgJVxaqIQCgAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.Patelz:BAAALgADCgQJBAAAAA==.',
Pe='Petoria:BAAALgADCgUJBQAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pinksparkle:BAAALgAECgkJCQAAAA==.Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQABLgAECgkJDwACAAAAAA==.Polyeikon:BAAALgAECgUJCgAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgAECgMJBAAAAA==.Prayr:BAAALgADCgMJBAAAAA==.Praystation:BAAALgAECgUJCAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgYJCwAAAA==.',
Ra='Raekeshh:BAABLgAECn8ZAAINAAkJ3BUyNAAHAgANAAkJ3BUyNAAHAgAAAA==.Raelone:BAABLgAECn8dAAQdAAkJGBEwIwCUAAANAAUJYg3XqADxAAAdAAYJZBIwIwCUAAAeAAEJ5RMNNgBIAAAAAA==.Rageofmommy:BAAALgAECgMJBAAAAA==.Raidoe:BAABLgAECn9FAAMDAAkJmhvEDwCkAgADAAkJmhvEDwCkAgAQAAMJOQvWcwBmAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn8zAAIKAAkJoxh2LwAbAgAKAAkJoxh2LwAbAgAAAA==.Rant:BAAALgAECgYJCwAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.Razorbeams:BAAALgAECgQJBQABLgAECgkJUgAYADgdAA==.',
Re='Redishpanda:BAAALgADCgcJFAAAAA==.Redshammy:BAAALgAFFAIJAwAAAA==.Relion:BAAALgAECggJEwABLgAECgkJOwAFAHsQAA==.',
Rh='Rheavin:BAAALgADCgUJCgAAAA==.Rhell:BAACLgAFFH8OAAIHAAQJqhMMKADeAAAHAAQJqhMMKADeAAAuAAQKfzcAAwcACQlXIEUIAAYDAAcACQlXIEUIAAYDAAUAAQkUAgHMARYAAAAA.',
Ri='Rinche:BAABLgAECn9FAAMTAAkJNxZxGwAEAgATAAkJNxZxGwAEAgAPAAkJ3gu+UQBoAQAAAA==.Rintche:BAAALgAECgUJBQAAAA==.',
Ro='Rolland:BAABLgAECn8hAAIOAAkJbyAXAgDdAgAOAAkJbyAXAgDdAgAAAA==.Rollf:BAAALgAECgMJAwAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAABLgAECn8hAAMNAAkJOAstWQCSAQANAAkJOAstWQCSAQAdAAQJ1wRKKQBuAAAAAA==.',
Ru='Rudo:BAABLgAECn8fAAMKAAkJxRVZIgA3AgAKAAkJxRVZIgA3AgAUAAEJrgKsaQAnAAAAAA==.Rumproblem:BAABLgAECn83AAMIAAkJcxf6DgB+AgAIAAkJcxf6DgB+AgAJAAcJsA7KMQBUAQAAAA==.Runekaiser:BAAALgAECgIJAgAAAA==.Runnamuuk:BAABLgAECn82AAIjAAkJGBRyNgDqAQAjAAkJGBRyNgDqAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryegar:BAAALgADCgkJCQAAAA==.Ryeger:BAABLgAECn9IAAMfAAkJRiFMAgAGAwAfAAkJRiFMAgAGAwAZAAMJpgsBZQCFAAAAAA==.',
['Rá']='Ráh:BAAALgADCgEJAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn82AAIlAAkJ3BYNEQDXAQAlAAkJ3BYNEQDXAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBQABLgAECgMJDQACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn87AAMFAAkJexABVgDHAQAFAAkJexABVgDHAQAHAAkJYwN1RAAuAQAAAA==.Sandbones:BAAALgAECgUJDAABLgAECgkJUgAYADgdAA==.Sandraice:BAABLgAECn8fAAIFAAgJ0QYyhwBsAQAFAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sanielan:BAAALgAECgUJCQAAAA==.Sansami:BAABLgAECn89AAIbAAgJpRvSFgDyAQAbAAgJpRvSFgDyAQAAAA==.Saphron:BAAALgAECgQJBAAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAABLgAECn8cAAMZAAcJnwe0SADmAAAZAAcJnwe0SADmAAAEAAUJDQMLqgBfAAAAAA==.',
Sc='Sc:BAAALgAECgcJCQABLgAECgkJKgARAE4jAA==.Scalebagz:BAABLgAECn8gAAMgAAkJSB4JBgCoAgAgAAkJSB4JBgCoAgAiAAgJvRxvIADVAQAAAA==.Schism:BAAALgAECgEJAQAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgAECgQJBAAAAA==.Senyorseven:BAAALgAECgYJDgAAAA==.Seo:BAAALgAECgQJCAAAAA==.Serabeara:BAAALgAECgEJAQAAAA==.Setresh:BAABLgAECn9QAAIUAAkJwhW+EgATAgAUAAkJwhW+EgATAgAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadöwsöng:BAABLgAECn88AAIWAAgJ3gtVIQAiAQAWAAgJ3gtVIQAiAQAAAA==.Shaedelana:BAABLgAECn8aAAQIAAcJPRt5PAAdAQAIAAUJShN5PAAdAQAXAAUJcxzbTwD4AAAJAAUJpA9ISwDhAAAAAA==.Shamrox:BAAALgAECggJEQAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJMwAEABMfAA==.Shinnobi:BAAALgAECgcJBwAAAA==.Shinygoat:BAAALgADCgIJAgABLgAECgkJKgAMAI8fAA==.Shivyn:BAABLgAECn8/AAMPAAkJTBqCDwDTAgAPAAkJTBqCDwDTAgATAAEJFwW5jQAqAAAAAA==.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAcJGAAOAIwiAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAACLgAFFH8KAAMcAAMJng/aMgBrAAALAAIJBA8g3QCDAAAcAAIJrwvaMgBrAAAuAAQKfy4AAwsACQmlGRJHAOsBAAsACQmlGRJHAOsBABwABQmtD1UuAMwAAAAA.Sickkid:BAABLgAECn9FAAISAAgJ8CJ7CQDKAgASAAgJ8CJ7CQDKAgAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silkiegirl:BAABLgAECn8iAAISAAkJzhTdGQAeAgASAAkJzhTdGQAeAgAAAA==.Silvershine:BAABLgAECn8VAAMEAAYJ6w4lgADaAAAEAAUJiAslgADaAAAfAAQJuAYtNgB/AAAAAA==.Silverwolf:BAAALgAECgIJAgAAAA==.Sindrya:BAAALgAECgUJBwAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slayne:BAAALgAECgEJAQAAAA==.Slaänesh:BAAALgADCgcJBwABLgAECgkJMwAEABMfAA==.Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJDAACAAAAAA==.Smashßros:BAAALgAECgEJAQABLgAECgkJNAASABgjAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgkJEAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgABLgAFFAMJCQALAEMgAA==.Snuggles:BAABLgAECn8mAAIkAAgJjxquEgABAgAkAAgJjxquEgABAgABLgAFFAYJGwAUAHcUAA==.',
So='Solidgen:BAEALgAECgEJAgABLgAFFAYJGAAFACsRAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Sonofalich:BAAALgAECgkJCQAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAABLgAECn8WAAMWAAgJNRZ5FwCDAQAWAAgJNRZ5FwCDAQAVAAMJUgOpNABeAAAAAA==.Spinach:BAAALgAECgEJAQAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgQJDgAAAA==.',
Ss='Ssraeshza:BAABLgAFFH8LAAIlAAYJphhJCABpAQAlAAYJphhJCABpAQAAAA==.',
St='Staretra:BAABLgAECn9BAAMJAAkJOBIwHADjAQAJAAkJOBIwHADjAQAXAAQJowYTUwCNAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.',
Su='Sublevels:BAAALgADCgYJBgAAAA==.Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECggJEQAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Symana:BAABLgAECn85AAIXAAkJKB4zCwCxAgAXAAkJKB4zCwCxAgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgAECgEJAQAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgcJEQAAAA==.',
['Sö']='Sörceress:BAAALgAECgYJEwAAAA==.',
Ta='Taadra:BAABLgAECn9WAAIPAAkJAiCoCQAXAwAPAAkJAiCoCQAXAwAAAA==.Talerah:BAAALgAECgUJCQAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAACLgAFFH8bAAIEAAUJUhsqGACYAQAEAAUJUhsqGACYAQAuAAQKfxgAAwQACQnvF2YeAEwCAAQACQnvF2YeAEwCACUAAgkPE/pMAHMAAAAA.Talona:BAAALgAFFAEJAQABLgAFFAUJCgAeAEEXAA==.Tandaan:BAAALgADCgkJCgABLgAECgkJGQANANwVAA==.Tanjent:BAABLgAECn8eAAIKAAYJDA1/mAAMAQAKAAYJDA1/mAAMAQAAAA==.Tanok:BAAALgADCgYJBgAAAA==.Tapio:BAABLgAECn8qAAIUAAcJWhaBIQCSAQAUAAcJWhaBIQCSAQAAAA==.Tatsuma:BAAALgAECgYJDgABLgAECggJJAAFADAdAA==.Tatsumå:BAAALgAECgcJEgABLgAECggJJAAFADAdAA==.Tavvi:BAAALgAECgYJBgABLgAECgcJFgAKAN0iAA==.Tazz:BAAALgAECgIJAgAAAA==.',
Te='Terp:BAAALgAECgMJBgAAAA==.',
Th='Thalfinore:BAAALgAECgcJEgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Therogue:BAAALgAECgIJAgAAAA==.Thorincan:BAAALgAECgkJBwAAAA==.Thorrs:BAAALgAECgIJBwAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thorwar:BAAALgADCgEJAQAAAA==.Thuglifé:BAAALgADCgYJDQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECgQJBgACAAAAAA==.Tidemaiden:BAAALgAECgYJEAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgABLgAFFAMJAwACAAAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tipsymancer:BAABLgAECn9IAAIbAAkJDSLcAwAOAwAbAAkJDSLcAwAOAwAAAA==.Tirael:BAAALgAECgYJBQABLgAFFAYJAQACAAAAAA==.Tishi:BAAALgAECgEJAQAAAA==.',
To='Tomö:BAAALgAECgkJBAAAAA==.Tossme:BAAALgAECgEJAQABLgAFFAQJDAAbAJ4gAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Treesus:BAABLgAECn8fAAIZAAkJLhqWGwAmAgAZAAkJLhqWGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECgkJHwAKAMUVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Ts='Tsu:BAAALgADCgkJCQAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.Tyzi:BAAALgAECgEJAQAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQRAAgJ+iPMNgA7AgARAAgJXCHMNgA7AgAYAAMJPCToBwAkAQAoAAEJTQ0VDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8lAAIEAAkJsRhLIgA0AgAEAAkJsRhLIgA0AgAAAA==.',
Un='Undeadgnome:BAAALgAECgMJAwAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.Usër:BAAALgAECgEJAgAAAA==.',
Va='Vainin:BAABLgAECn8UAAIRAAYJfAcl4gDVAAARAAYJfAcl4gDVAAAAAA==.Valle:BAAALgAFFAEJAQAAAA==.Valry:BAAALgAECgYJDgAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAQJBgAWAEkXAA==.Variable:BAAALgAECgcJBwAAAA==.Vashdin:BAABLgAECn8pAAIFAAcJVx5vQAAEAgAFAAcJVx5vQAAEAgAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECgkJHwAKAMUVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velashis:BAABLgAECn83AAMEAAkJUhzZDQDpAgAEAAkJUhzZDQDpAgAZAAIJ5QxVdwBVAAAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAABLgAFFH8IAAITAAMJrBBmNAC3AAATAAMJrBBmNAC3AAAAAA==.Vett:BAAALgADCgMJAwABLgAECgYJFAARAHwHAA==.',
Vi='Viable:BAAALgAECgUJCgAAAA==.Vibes:BAAALgAECgkJCwAAAA==.Victorvega:BAAALgAECgMJAwABLgAECgkJHwAKAMUVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8QAAMDAAMJtRI3OgC1AAADAAMJtRI3OgC1AAAQAAIJlxk9LgCJAAAuAAQKfyYAAxAACQndHRcQAH8CABAACAmuHRcQAH8CAAMABQnvHzhTABwBAAAA.Vivila:BAAALgAECgMJBQABLgAECgkJPwAjAKwZAA==.Vivillian:BAABLgAFFH8HAAIIAAMJjg9UMgC+AAAIAAMJjg9UMgC+AAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Voidrèaper:BAAALgAECgEJAQAAAA==.Vordilina:BAABLgAECn8cAAQoAAkJqhgIAgBYAgAoAAkJqhgIAgBYAgAYAAEJuAV9IAAtAAARAAEJrQHbiAEcAAAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQgAAgJKhn4EwAGAgAgAAgJKhn4EwAGAgAhAAQJxRgtFQC6AAAiAAEJygP3mgAkAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAABLgAECn83AAMPAAcJnhomNADeAQAPAAcJnhomNADeAQATAAcJZRhvJgC1AQAAAA==.',
Vy='Vynae:BAAALgADCgcJBAAAAA==.',
['Vé']='Véxx:BAABLgAECn8wAAQMAAgJpB7LBABnAgAMAAgJpB7LBABnAgAkAAUJYAizQgDtAAAjAAEJdAGj9QAZAAAAAA==.',
['Vì']='Vìx:BAAALgAECgEJAQAAAA==.',
['Ví']='Víx:BAAALgAECggJCAAAAA==.',
['Vî']='Vîper:BAAALgAFFAEJAQAAAA==.',
['Vï']='Vïx:BAAALgADCgUJBQAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Warihor:BAABLgAECn8vAAMSAAgJeQxwPwBHAQASAAgJIwpwPwBHAQAVAAgJhQnQLwAGAQAAAA==.Waycaps:BAABLgAFFH8FAAIlAAQJUBUIDwANAQAlAAQJUBUIDwANAQAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAACLgAFFH8PAAIeAAQJbiS8AQClAQAeAAQJbiS8AQClAQAuAAQKfy4AAh4ACQk/JL8AACMDAB4ACQk/JL8AACMDAAAA.',
Wh='Whïte:BAAALgAECgEJAgAAAA==.',
Wi='Wiegraf:BAAALgAECgIJAwABLgAECgkJMwAEABMfAA==.Wife:BAAALgAECgMJAwAAAA==.Wildhide:BAAALgAECgcJBwAAAA==.Withers:BAAALgADCgQJBAAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJDQAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECgcJCgAAAA==.',
['Wä']='Wärbëef:BAAALgADCgEJAQAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECgQJBgACAAAAAA==.',
Xo='Xorxel:BAAALgAECgMJBwAAAA==.',
Ya='Yacob:BAABLgAECn81AAIXAAkJOx3/CQDFAgAXAAkJOx3/CQDFAgAAAA==.',
Ye='Yenneferr:BAAALgAECgkJAQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8zAAIEAAkJEx9hCwAGAwAEAAkJEx9hCwAGAwAAAA==.',
Yh='Yhwach:BAACLgAFFH8LAAIcAAUJtAxyIwDPAAAcAAUJtAxyIwDPAAAuAAQKfyEAAhwACAk4GNMTANQBABwACAk4GNMTANQBAAAA.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAABLgAFFH8HAAIFAAQJGhB0RgAbAQAFAAQJGhB0RgAbAQABLgAECgkJEgACAAAAAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECgQJBgAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgcJCwAAAA==.',
Za='Zaeden:BAABLgAECn8cAAIDAAcJmx6fFgANAgADAAcJmx6fFgANAgABLgAECgkJGgALAK0gAA==.Zaft:BAAALgADCgYJBgAAAA==.Zaftdh:BAABLgAECn81AAIjAAkJqhXtMwD0AQAjAAkJqhXtMwD0AQAAAA==.Zaha:BAABLgAECn8eAAIRAAYJ2iKdXAAkAgARAAYJ2iKdXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zappsz:BAAALgAECgcJCQAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zedfrey:BAABLgAECn89AAIFAAkJ/hajMAA8AgAFAAkJ/hajMAA8AgAAAA==.Zem:BAABLgAECn8rAAISAAgJux/4EQBjAgASAAgJux/4EQBjAgAAAA==.Zemangoose:BAAALgAECgYJBgAAAA==.Zeroultra:BAABLgAECn85AAISAAgJsR2TEQBoAgASAAgJsR2TEQBoAgAAAA==.Zeräse:BAABLgAECn8VAAIIAAgJRw/1IwCuAQAIAAgJRw/1IwCuAQABLgAECgkJMwAEABMfAA==.Zeusdh:BAAALgADCgkJCQAAAA==.Zeusmos:BAABLgAECn89AAIQAAkJxiY3AACWAwAQAAkJxiY3AACWAwAAAA==.',
Zi='Zithenex:BAABLgAECn83AAIhAAcJdhVlCQCRAQAhAAcJdhVlCQCRAQAAAA==.',
Zo='Zoeÿ:BAAALgAECgEJBAAAAA==.',
Zw='Zwar:BAAALgAECgIJAgAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAABLgAECn8hAAISAAcJ0hONMQCHAQASAAcJ0hONMQCHAQAAAA==.',
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
