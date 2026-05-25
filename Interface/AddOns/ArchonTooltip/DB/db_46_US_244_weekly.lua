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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Hunter-Survival','Warrior-Arms','Warrior-Protection','Priest-Holy','Mage-Arcane','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','Warlock-Destruction','Warrior-Fury','Druid-Feral','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Affliction','Shaman-Enhancement','Priest-Discipline','Rogue-Assassination','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-05-24',data={Aa='Aaminae:BAABLgAECn8oAAIBAAgJkxddFADbAQABAAgJkxddFADbAQAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgQJBQAAAA==.Abracastabya:BAAALgAECggJEAAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.',
Ad='Adachï:BAABLgAECn8WAAIDAAYJiRpPKACgAQADAAYJiRpPKACgAQABLgAECgkJMgAEABMfAA==.Adevil:BAAALgAECgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aethlin:BAABLgAECn8tAAMFAAkJ4BvNJwBEAgAFAAkJjRnNJwBEAgAGAAcJghu9DQC8AQAAAA==.Aeturnas:BAABLgAECn8tAAIHAAgJViGeCQDNAgAHAAgJViGeCQDNAgAAAA==.',
Ag='Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanima:BAAALgAECgcJEAAAAA==.Aldky:BAAALgADCgkJDgAAAA==.Aliana:BAAALgAECgIJBAAAAA==.Allindis:BAAALgAECgYJCQABLgAECgkJJQAEALEYAA==.Allypally:BAAALgADCgMJAwAAAA==.Alphamage:BAAALgADCgMJAwAAAA==.Alphamonk:BAAALgAECggJDwAAAA==.Alros:BAABLgAECn81AAIIAAkJYyDXDQC+AgAIAAkJYyDXDQC+AgAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgAECgQJCAAAAA==.',
Am='Amardyton:BAAALgAECgYJBwAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgIJAgACAAAAAA==.Arctica:BAAALgADCgQJBAAAAA==.Arette:BAAALgAECgIJAgAAAA==.Arkades:BAABLgAECn8dAAIFAAgJ1hw9JwBHAgAFAAgJ1hw9JwBHAgAAAA==.Arkshade:BAABLgAECn8oAAIJAAcJoA8XfgBEAQAJAAcJoA8XfgBEAQAAAA==.Arlia:BAAALgAECgkJEQAAAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECgkJKgAKAI8fAA==.Aryn:BAAALgAECgEJAQAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgQJBQACAAAAAA==.Ashor:BAAALgAECgEJAQAAAA==.Asmo:BAAALgADCggJGAAAAA==.Astarii:BAAALgAECgEJBQAAAA==.Asterica:BAABLgAECn8/AAILAAkJWBhJLAASAgALAAkJWBhJLAASAgAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAIMAAYJ+A16UwA4AQAMAAYJ+A16UwA4AQAAAA==.',
Av='Averynicole:BAABLgAECn8ZAAINAAcJBxbwJABkAQANAAcJBxbwJABkAQAAAA==.',
Aw='Awasjr:BAABLgAECn8iAAIIAAgJ9x2XJwAWAgAIAAgJ9x2XJwAWAgAAAA==.',
Ay='Ayano:BAABLgAECn8VAAIOAAgJ/Bz1RwDqAQAOAAgJ/Bz1RwDqAQAAAA==.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balanla:BAAALgADCgIJAgAAAA==.Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDQABLgAECgkJMgAEABMfAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgADCgkJDgAAAA==.Bearhug:BAABLgAECn8mAAMDAAgJrhZkIACwAQADAAcJrRhkIACwAQANAAYJhAiBQgANAQABLgAFFAQJCQAPAJMFAA==.Bearshock:BAABLgAFFH8JAAMPAAQJkwVdJADfAAAPAAQJkwVdJADfAAAMAAEJTADpawAdAAAAAA==.Beasty:BAABLgAECn8lAAMQAAgJHhB5DgBNAQAQAAgJHhB5DgBNAQARAAYJhwQcNgDcAAAAAA==.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAABLgAECn8yAAIGAAkJzCTFAABLAwAGAAkJzCTFAABLAwAAAA==.Beeb:BAAALgAECgUJDgABLgAECgkJMgAGAMwkAA==.Beefisting:BAAALgAECgYJDAABLgAECgkJMgAGAMwkAA==.Beethicc:BAAALgAECgEJAwABLgAECgkJMgAGAMwkAA==.Beeuwu:BAAALgAECgIJAwABLgAECgkJMgAGAMwkAA==.Beliara:BAAALgAECgYJCwAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Belshuntress:BAAALgAECgEJAgAAAA==.Beverage:BAAALgAECgEJAQAAAA==.',
Bi='Bigmattyl:BAAALgAECgcJCgAAAA==.Bionarra:BAABLgAECn8uAAIOAAkJtBp3KQBZAgAOAAkJtBp3KQBZAgAAAA==.Bishopwr:BAABLgAECn8hAAMSAAgJkBbKDgDXAQASAAgJkBbKDgDXAQATAAYJPwhoLQCrAAAAAA==.Bittertøfu:BAABLgAECn8eAAIPAAcJfQbhSQDfAAAPAAcJfQbhSQDfAAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJCAAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blitê:BAAALgADCgUJBQABLgADCgkJDQACAAAAAA==.',
Bm='Bmpfrostie:BAAALgAECgcJEwAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECgkJLQAUANwcAA==.Bohica:BAAALgAECggJDQAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAABLgAFFAMJBQAJAEMgAA==.',
Br='Brakug:BAABLgAECn8vAAMOAAkJHiMULgC5AgAOAAkJHiMULgC5AgAVAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAIJAwAAAA==.Brem:BAABLgAECn8bAAIVAAgJghweBAASAgAVAAgJghweBAASAgAAAA==.Bretagnesse:BAABLgAECn8UAAIWAAgJ2wXyOgD3AAAWAAgJ2wXyOgD3AAAAAA==.Briara:BAAALgAECgYJCQAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgADCgEJAQAAAA==.Broníx:BAAALgAECgEJBQAAAA==.Bropeep:BAABLgAECn8vAAMJAAgJ9yCCHgBxAgAJAAgJ9yCCHgBxAgAXAAQJnRRBFQDvAAAAAA==.Brotality:BAAALgADCgMJBAAAAA==.Brynhildr:BAAALgAECgYJBgABLgAECgkJKwANANQdAA==.',
Bu='Bullshott:BAABLgAECn8dAAIIAAkJCBwqGABtAgAIAAkJCBwqGABtAgAAAA==.Bum:BAABLgAECn8mAAMWAAkJsh/4BABRAwAWAAkJsh/4BABRAwAEAAEJ0xCM0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgAECgUJCQAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJEAAAAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBgAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAABLgAECn8VAAMJAAgJQA1XjwAlAQAJAAcJsQpXjwAlAQAYAAYJdA0UKgDbAAAAAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8tAAIFAAkJ6wcgcQBuAQAFAAkJ6wcgcQBuAQAAAA==.Carrots:BAABLgAECn8hAAIIAAcJKhVFUACFAQAIAAcJKhVFUACFAQAAAA==.Cartman:BAAALgAFFAEJAQABLgAFFAQJFgAZAHIYAA==.Cashmachine:BAABLgAECn8qAAIIAAkJ3B1jFgB5AgAIAAkJ3B1jFgB5AgAAAA==.Castorice:BAAALgAECgEJAQAAAA==.Catfight:BAABLgAECn8jAAIGAAcJ4A5JHgD3AAAGAAcJ4A5JHgD3AAAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMLAAkJdBhqLgBTAgALAAkJdBhqLgBTAgAaAAEJAABoZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8MAAQIAAQJ3B58GgBbAQAIAAQJuB18GgBbAQAQAAEJISI3IwBlAAARAAEJzA8rKABNAAAuAAQKfxoABBAACAkNIcIYAGYCABAACAmlH8IYAGYCAAgABQlPHaJJAJkBABEAAwkrGA9DAIcAAAAA.Cheesecake:BAABLgAECn8jAAIaAAcJDBPKDABGAQAaAAcJDBPKDABGAQAAAA==.Chihiko:BAAALgAECgMJAwAAAA==.Choks:BAABLgAECn8bAAIbAAcJMwnMPwAhAQAbAAcJMwnMPwAhAQAAAA==.Chromie:BAAALgADCgMJAwAAAA==.Chubbycat:BAABLgAECn8VAAMEAAcJLhmOPQCuAQAEAAcJLhmOPQCuAQAcAAUJYh3eEgBZAQAAAA==.Chuggz:BAABLgAECn8wAAIZAAkJHRiyDQA/AgAZAAkJHRiyDQA/AgAAAA==.Chéfboyrlee:BAACLgAFFH8XAAIdAAcJBxgVBAD6AQAdAAcJBxgVBAD6AQAuAAQKfzYAAh0ACQn6IiMDAB8DAB0ACQn6IiMDAB8DAAAA.',
Ci='Cizmac:BAAALgAECgMJBQAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgADCgYJCgAAAA==.Cownado:BAABLgAECn8pAAIZAAcJTRG8KQBKAQAZAAcJTRG8KQBKAQABLgAECggJFQAJAEANAA==.',
Cr='Crouton:BAAALgADCgkJCgAAAA==.',
Cu='Cursedspirit:BAAALgAECgQJBwAAAA==.',
Cy='Cybelem:BAABLgAECn8tAAIPAAkJmB6gDAB6AgAPAAkJmB6gDAB6AgAAAA==.Cyfelen:BAAALgAECggJDgAAAA==.Cynleel:BAAALgAECggJDwAAAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQAAAA==.Damonstyle:BAAALgAECgEJAgAAAA==.Dandistyle:BAABLgAECn8fAAMZAAkJdx39CACIAgAZAAkJbh39CACIAgANAAEJchK2fAAzAAAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathblade:BAAALgAECgEJAQAAAA==.Deathmatrynn:BAAALgAECgIJAgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAAALgAFFAEJAQAAAA==.Deeviant:BAAALgAECggJDgAAAA==.Defend:BAAALgAECgYJBgABLgAFFAQJFgAZAHIYAA==.Delrager:BAACLgAFFH8FAAIBAAIJwxsHJACwAAABAAIJwxsHJACwAAAuAAQKfyEAAgEABwlnI3ULAEoCAAEABwlnI3ULAEoCAAAA.Demonicdawn:BAAALgADCgEJAQAAAA==.Derat:BAAALgAECgkJEQAAAA==.',
Di='Dibbydab:BAABLgAECn8gAAIMAAkJShIqMADIAQAMAAkJShIqMADIAQAAAA==.',
Dj='Django:BAABLgAECn82AAMWAAkJsyJqBAD/AgAWAAkJsyJqBAD/AgAEAAIJkAaksABCAAAAAA==.Djatalon:BAAALgAECgUJEgAAAA==.Djderpyderpy:BAAALgAECgYJDQAAAA==.Djehrtey:BAAALgADCgYJCgAAAA==.Djin:BAAALgAECgMJBAABLgAECgkJKwANANQdAA==.Djinni:BAABLgAECn8rAAMNAAkJ1B08CwBtAgANAAkJEhs8CwBtAgAZAAgJHx6wEQAMAgAAAA==.',
Do='Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8WAAMXAAYJfBjBBQDVAQAXAAYJfBjBBQDVAQAJAAMJsA2A/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8YAAQeAAcJNxm2DQDTAQAeAAcJNxm2DQDTAQAfAAQJuwzAUgC8AAAgAAEJAACAPAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Dramaticus:BAAALgADCgEJAQAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drenleah:BAAALgAECgUJBwABLgAECgkJNAAhAKIWAA==.Drenlee:BAAALgAECgEJAQABLgAECgkJNAAhAKIWAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgAAAA==.Dryya:BAAALgAECgQJCAAAAA==.Drêck:BAAALgAECgEJAQAAAA==.',
Du='Dumblegear:BAABLgAECn8dAAMOAAcJuBSnfABkAQAOAAcJuBSnfABkAQAVAAEJbQY0IAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAECggJMQAbAO8iAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgADCgQJCAAAAA==.Dädärkbeëf:BAAALgADCgcJCQAAAA==.',
Ed='Edinna:BAABLgAECn8rAAMOAAkJ1BFLQAACAgAOAAkJ1BFLQAACAgAVAAQJTQoTEADBAAAAAA==.',
Ei='Einekliene:BAAALgAECgcJBwAAAA==.',
Ek='Ekatrina:BAAALgADCgkJDgAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Eldernoc:BAAALgADCgkJDQAAAA==.Elessedil:BAAALgAECgcJDQAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgMJBQAAAA==.Elyriana:BAABLgAECn8jAAMEAAkJpSARBwAtAwAEAAkJpSARBwAtAwAcAAEJqSB8MQBdAAAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEBLgAECn8WAAIIAAYJuh7xRQClAQAIAAYJuh7xRQClAQABLgAECgcJGAAIAMgcAA==.Emixi:BAAALgAECgQJBQAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECgcJDQAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8UAAIFAAUJjBvdJwBCAQAFAAUJjBvdJwBCAQAuAAQKfzEAAgUACQmaH0cbAIQCAAUACQmaH0cbAIQCAAAA.',
Ep='Epedemik:BAAALgAECgIJAgAAAA==.',
Er='Erazath:BAAALgAECgUJBgABLgAECggJGQAYAI8TAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgAECgIJAgAAAA==.',
Es='Esha:BAAALgADCgkJDgAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Faewing:BAAALgAFFAIJAgAAAA==.Falar:BAAALgAECggJDQAAAA==.Fatelf:BAAALgADCgMJAwAAAA==.Faval:BAAALgAECggJDwABLgAECgkJKgAKAI8fAA==.Favel:BAABLgAECn8qAAMKAAkJjx9OAQAcAwAKAAgJ4iFOAQAcAwAhAAkJRwu3UABzAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn8xAAIIAAkJpRS3LwD0AQAIAAkJpRS3LwD0AQAAAA==.Febz:BAABLgAECn8eAAIOAAgJbBsqMACyAgAOAAgJbBsqMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAABLgAECn8ZAAIhAAgJEh1gJQAcAgAhAAgJEh1gJQAcAgAAAA==.Felfüry:BAABLgAECn84AAQiAAkJrRL/EADoAQAiAAkJrRL/EADoAQAKAAgJkQXeFADcAAAhAAEJJAPQEQEWAAAAAA==.Felly:BAAALgAECgYJBgAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Festyr:BAAALgAECgQJCAAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECgQJBgACAAAAAA==.Finella:BAAALgAECgMJBAAAAA==.Finneas:BAAALgADCgUJBQABLgAECggJHQAFANYcAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJLwAOAB4jAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgMJBAACAAAAAA==.',
Fj='Fjeighty:BAABLgAECn8gAAMiAAcJKg8jIgAvAQAiAAcJKg8jIgAvAQAhAAEJ6QPEDAEcAAAAAA==.',
Fo='Fogassann:BAAALgAECgQJBAAAAA==.Foggpy:BAACLgAFFH8RAAMjAAUJixAWAwA4AQAjAAUJQxAWAwA4AQALAAQJnwNEWgDmAAAuAAQKfycABCMACAmeInUEADYCACMABwkkJXUEADYCAAsABgkNG8FXAMABABoABgljGQ4fAFgBAAAA.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freinkenbaby:BAAALgAECgEJAQAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostlicious:BAAALgADCgEJAQAAAA==.Frostybear:BAABLgAECn8/AAIOAAkJLRifKwBQAgAOAAkJLRifKwBQAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAABLgAECn8xAAMYAAkJPAm/HgAyAQAYAAkJPAm/HgAyAQAXAAEJ8QHLMgAaAAAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Galaythien:BAAALgAECgIJAwAAAA==.Gang:BAAALgAECgUJBQABLgAFFAMJCwABAMUOAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAhAEQaAA==.',
Ge='Geluria:BAAALgAECgkJEAABLgAECgkJNAAZADckAA==.Geret:BAABLgAECn8iAAIFAAgJdxMuWwCfAQAFAAgJdxMuWwCfAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Glitchy:BAABLgAECn89AAIWAAkJIR69BwC7AgAWAAkJIR69BwC7AgAAAA==.Glokraz:BAAALgAECgcJBwAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgYJDQAAAA==.',
Go='Goingtogetu:BAABLgAECn89AAIGAAkJCSOIAQAWAwAGAAkJCSOIAQAWAwAAAA==.Gold:BAAALgAECgIJAgABLgAECgkJKwAUAD4fAA==.Goldfarmr:BAABLgAECn8rAAIUAAkJPh9uCQCvAgAUAAkJPh9uCQCvAgAAAA==.Goldrawr:BAAALgAECgYJBwABLgAECgkJKwAUAD4fAA==.Goldshocker:BAAALgAECgQJBgABLgAECgkJKwAUAD4fAA==.Golduwu:BAAALgAECgEJAgABLgAECgkJKwAUAD4fAA==.Googlymoogly:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.',
Gr='Greed:BAAALgAFFAIJAgABLgAFFAYJFgAGAOYhAA==.Greeley:BAABLgAECn8vAAIQAAkJBiTmAAAoAwAQAAkJBiTmAAAoAwAAAA==.Gregdapro:BAABLgAECn9EAAIYAAkJhCWUAABjAwAYAAkJhCWUAABjAwAAAA==.Gregnstone:BAABLgAECn8jAAIHAAkJlRbNIQDSAQAHAAkJlRbNIQDSAQABLgAECgkJRAAYAIQlAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAUJCgAfAGUMAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAYJIQAbAKwgAA==.Gunnyal:BAABLgAECn8hAAMSAAcJQxHeHABMAQASAAcJRRDeHABMAQAbAAQJsAl2XgCvAAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8wAAIPAAkJUyO3AwATAwAPAAkJUyO3AwATAwAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8hAAMbAAYJrCDeAwDUAQAbAAYJrCDeAwDUAQASAAEJNAEQDgA8AAAuAAQKfzwAAxsACQktJU4BAF4DABsACQktJU4BAF4DABIAAwldHJkuAOIAAAAA.Hakyahi:BAAALgADCggJCAAAAA==.Hank:BAAALgADCgYJBgAAAA==.Harkin:BAABLgAECn8tAAIFAAkJPBA9UwCzAQAFAAkJPBA9UwCzAQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgAECgMJBQAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIPAAcJXQt1QAAFAQAPAAcJXQt1QAAFAQAAAA==.Hermioné:BAAALgADCgUJBQAAAA==.Hevy:BAABLgAECn80AAIhAAkJohaKJAAgAgAhAAkJohaKJAAgAgAAAA==.',
Hi='Hilarius:BAAALgAECggJEQAAAA==.Hiraeth:BAAALgAECgUJCQAAAA==.Hirukon:BAAALgADCgIJAgAAAA==.',
Ho='Holydadbod:BAAALgAECgQJBwABLgAECgkJKwANANQdAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn86AAIFAAkJHRj9JABRAgAFAAkJHRj9JABRAgAAAA==.Howlinnbrews:BAABLgAFFH8GAAMNAAIJNCKOIQCcAAANAAIJcBeOIQCcAAAZAAEJ6CXuQwBrAAAAAA==.Howlinplague:BAAALgAECgYJCQAAAA==.',
Hu='Hulkhogan:BAABLgAECn8ZAAITAAgJRB3WDQDkAQATAAgJRB3WDQDkAQAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIhAAMJRBoSRwDmAAAhAAMJRBoSRwDmAAAuAAQKfycAAiEACAkuIrAVANQCACEACAkuIrAVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMEAAgJjBjDIwAMAgAEAAgJjBjDIwAMAgAcAAIJ1hI+NwBJAAAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8aAAINAAcJVBa2LQAtAQANAAcJVBa2LQAtAQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Io:BAAALgAFFAMJAwAAAA==.Iobo:BAABLgAECn8iAAIRAAcJpRKFHQCTAQARAAcJpRKFHQCTAQAAAA==.',
Ir='Ironhidez:BAABLgAECn8mAAIFAAgJiQt3fQBVAQAFAAgJiQt3fQBVAQAAAA==.',
Is='Isaarek:BAABLgAECn8aAAIfAAkJURW1EQA4AgAfAAkJURW1EQA4AgAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDgAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAYJGgAJAIkcAA==.Jastia:BAAALgAECgYJEgAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jeb:BAAALgAECgEJAQABLgAECggJEAACAAAAAA==.Jebopally:BAAALgAECgMJBAABLgAECggJEAACAAAAAA==.Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8sAAMLAAkJAhy+FwCAAgALAAkJAhy+FwCAAgAaAAEJAAD2bQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8pAAIFAAkJMAsBYwCNAQAFAAkJMAsBYwCNAQAAAA==.',
Jo='Joecephus:BAABLgAECn8cAAIHAAcJtCEuDgCOAgAHAAcJtCEuDgCOAgAAAA==.Joehex:BAABLgAECn82AAITAAkJbCCMAwDeAgATAAkJbCCMAwDeAgAAAA==.Joeschmonk:BAAALgAECgQJBAAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Jubelius:BAAALgAECgYJBgABLgAECgkJHwAIAMUVAA==.Judgematt:BAAALgAECgkJEwAAAA==.Justin:BAABLgAECn8fAAISAAkJvhVlCgAdAgASAAkJvhVlCgAdAgAAAA==.',
Ka='Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAIQAAgJ1AymEAAsAQAQAAgJ1AymEAAsAQAAAA==.Kaleesh:BAACLgAFFH8OAAIkAAUJESX2AQCWAQAkAAUJESX2AQCWAQAuAAQKfyMAAiQACAmrJEcBAGgDACQACAmrJEcBAGgDAAAA.Kallux:BAABLgAECn80AAIYAAkJUB2oBwB8AgAYAAkJUB2oBwB8AgAAAA==.Kananga:BAABLgAECn8bAAIUAAcJlxhxHQC3AQAUAAcJlxhxHQC3AQAAAA==.Karavira:BAAALgAECgEJAQAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgAECgYJBQAAAA==.',
Ke='Kelindina:BAAALgAECgMJDQAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Keoeu:BAAALgAECgMJAwAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgIJBAAAAA==.',
Ki='Kieleron:BAABLgAECn8ZAAIlAAcJgBHsHwCjAQAlAAcJgBHsHwCjAQAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJDgAAAA==.Kiermaxim:BAABLgAECn8mAAIPAAgJNBwcGwA6AgAPAAgJNBwcGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Killon:BAAALgAECgEJAQABLgAECgkJMwAFAKsQAA==.Kiragrande:BAABLgAECn8iAAIDAAkJxBD6IgDFAQADAAkJxBD6IgDFAQAAAA==.Kiraneth:BAABLgAECn8gAAINAAgJMBCjJABnAQANAAgJMBCjJABnAQAAAA==.Kirbie:BAAALgADCgUJBQAAAA==.Kirial:BAAALgADCgcJBwAAAA==.Kiriku:BAAALgAECggJEwAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgQJBAAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgADCgYJBgAAAA==.',
La='Lagartista:BAAALgAECgcJCQAAAA==.Largcok:BAAALgAECgEJAQAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Le='Lee:BAAALgAFFAUJAQAAAA==.Lefty:BAAALgADCgcJBwABLgAECgkJOwARAAoUAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lilpwny:BAAALgADCgMJAwABLgAECgkJIQAdADEYAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn82AAIbAAkJfiMrAwAhAwAbAAkJfiMrAwAhAwAAAA==.Logres:BAAALgADCgEJAQAAAA==.Lokeira:BAACLgAFFH8HAAIMAAMJ1wejQgCuAAAMAAMJ1wejQgCuAAAuAAQKfygAAgwACAkeGxstANgBAAwACAkeGxstANgBAAAA.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn8zAAIFAAkJqxDyUAC5AQAFAAkJqxDyUAC5AQAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgEJAgABLgAECgcJIwAOAE4TAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Luvbug:BAABLgAECn8WAAIIAAcJ3SJ9GAB2AgAIAAcJ3SJ9GAB2AgAAAA==.',
Ly='Lyara:BAACLgAFFH8ZAAMMAAYJ5yNhAwBNAgAMAAYJ5yNhAwBNAgAPAAQJRxj8FAA7AQAuAAQKfxwAAwwACQnAIFAJAOICAAwACAkVIFAJAOICAA8ABglnGxQ1ADoBAAAA.Lyi:BAAALgAFFAEJAQAAAA==.Lythos:BAABLgAECn8ZAAIYAAgJjxNqGwBzAQAYAAgJjxNqGwBzAQAAAA==.Lyu:BAAALgAFFAEJAQABLgAFFAYJGQAMAOcjAA==.Lyuu:BAABLgAFFH8GAAIOAAMJdxZLZgDsAAAOAAMJdxZLZgDsAAABLgAFFAYJGQAMAOcjAA==.',
['Lø']='Lørdøfßud:BAABLgAECn8xAAMbAAgJ7yIbCwCTAgAbAAgJXCEbCwCTAgASAAcJEiPiCAA7AgAAAA==.',
Ma='Macguffin:BAAALgADCgkJDgAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJHQAhAIYLAA==.Makimá:BAAALgADCgYJBgABLgAECgkJHwAIAMUVAA==.Makinnor:BAAALgADCgEJAQAAAA==.Malifae:BAABLgAECn8bAAIWAAcJYSGbEwB3AgAWAAcJYSGbEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwAWAGEhAA==.Mankilla:BAAALgAECgQJBwAAAA==.Mansa:BAABLgAECn8zAAImAAkJJhYxBAAyAgAmAAkJJhYxBAAyAgAAAA==.Mastamojo:BAABLgAECn8yAAIHAAkJOQjPMgBkAQAHAAkJOQjPMgBkAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Maîev:BAAALgAECgUJBwAAAA==.',
Mc='Mcmurphy:BAAALgAECgUJDAAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAABLgAECn8WAAIaAAcJqRPBDABGAQAaAAcJqRPBDABGAQAAAA==.Melendaren:BAAALgAECgMJBQAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgAECgQJCAAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAECgIJAgAAAA==.Meowkug:BAAALgAECgEJAgAAAA==.Merscy:BAABLgAECn8bAAIUAAgJngqnMAAoAQAUAAgJngqnMAAoAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAABLgAECn8eAAMWAAcJbg9MOgD6AAAWAAcJbg9MOgD6AAAEAAYJ1gsYYgDxAAAAAA==.Metamonster:BAABLgAECn8eAAMJAAgJRQ1crwDwAAAJAAgJAAVcrwDwAAAYAAYJ4w9ULwC5AAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgQJBgAAAA==.Mirko:BAABLgAECn8dAAIhAAcJhgs5eAAMAQAhAAcJhgs5eAAMAQAAAA==.Mistiah:BAABLgAFFH8FAAIJAAMJQyAfVAAoAQAJAAMJQyAfVAAoAQAAAA==.Mistyjoe:BAAALgADCgMJAwAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn83AAIVAAkJTRYVAgAsAgAVAAkJTRYVAgAsAgAAAA==.Mokokniki:BAAALgADCggJCQAAAA==.Moneie:BAAALgAECgQJBgAAAA==.Monger:BAAALgADCgIJAgAAAA==.Mongò:BAAALgADCgIJAgAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAFFAMJBAACAAAAAA==.Moondo:BAAALgAECgcJDgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Mooseymancer:BAAALgADCgYJBgAAAA==.Mootron:BAAALgADCgUJBQAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mourningstar:BAACLgAFFH8SAAMJAAUJeSXVIwCKAQAJAAQJeSXVIwCKAQAYAAEJAAAeRwAAAAAuAAQKfyMAAwkACQkeJPASALoCAAkACQkeJPASALoCABgAAgm1EfY7AHUAAAEuAAUUBgkaAAkAiRwA.Mozaic:BAABLgAECn82AAITAAkJZRaoCwAQAgATAAkJZRaoCwAQAgAAAA==.',
Mu='Mugrüíth:BAAALgAECgIJBAAAAA==.',
My='Myfeethurt:BAAALgADCgYJBgABLgAECggJMQAbAO8iAA==.Myragê:BAAALgADCgkJDQAAAA==.Myselia:BAABLgAECn8gAAIiAAgJhRbYEQDZAQAiAAgJhRbYEQDZAQAAAA==.Mystra:BAAALgAECgQJBQAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgADCgQJBAAAAA==.Naek:BAAALgAECgMJBQAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgMJBQACAAAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAABLgAECn8eAAIOAAcJHRJBegBpAQAOAAcJHRJBegBpAQAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAABLgAECn8ZAAIhAAgJvQkMcAAeAQAhAAgJvQkMcAAeAQAAAA==.Niem:BAABLgAECn8dAAInAAkJhSXMAABWAwAnAAkJhSXMAABWAwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.',
No='Nocturnum:BAABLgAECn8zAAIhAAgJ6BktLQD2AQAhAAgJ6BktLQD2AQAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8JAAIjAAQJQRdPAABcAQAjAAQJQRdPAABcAQAuAAQKfxwAAiMACAktHi8BAPECACMACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAAAAA==.Odin:BAAALgADCgYJBgAAAA==.Odium:BAAALgADCgMJAwABLgAFFAQJDAAIANweAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAcJGAAQAIwiAA==.',
Ol='Oldmage:BAAALgADCgUJBQAAAA==.Oldmongerpal:BAAALgAECgEJAQAAAA==.',
On='Onetwocowpow:BAABLgAECn89AAIDAAkJ4RcnEgBZAgADAAkJ4RcnEgBZAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn8/AAMFAAkJViJwDwATAwAFAAkJViJwDwATAwAGAAEJsQzgQgA0AAAAAA==.Orionn:BAACLgAFFH8TAAIIAAQJRSCTFwBlAQAIAAQJRSCTFwBlAQAuAAQKf0MAAggACQm2JaECAFIDAAgACQm2JaECAFIDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAABLgAECn8ZAAIIAAgJiwxBVAB6AQAIAAgJiwxBVAB6AQAAAA==.',
Ov='Oven:BAABLgAECn8gAAINAAgJVxZFGwCtAQANAAgJVxZFGwCtAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.Patelz:BAAALgADCgQJBAAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQABLgAECgkJDwACAAAAAA==.Polyeikon:BAAALgAECgUJCgAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgADCgcJBwAAAA==.Prayr:BAAALgADCgEJAQAAAA==.Praystation:BAAALgAECgUJCAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgUJBQAAAA==.',
Ra='Raekeshh:BAABLgAECn8ZAAILAAkJ3BX3KwATAgALAAkJ3BX3KwATAgAAAA==.Raelone:BAABLgAECn8bAAMaAAgJshCTHQCbAAALAAUJYg2XlQD+AAAaAAYJZBKTHQCbAAAAAA==.Rageofmommy:BAAALgAECgMJAwAAAA==.Raidoe:BAABLgAECn88AAMDAAkJmBvvDQCNAgADAAkJmBvvDQCNAgANAAMJOQtGYQBoAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn8zAAIIAAkJoxhRIwAsAgAIAAkJoxhRIwAsAgAAAA==.Rant:BAAALgAECgUJCgAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.Razorbeams:BAAALgAECgMJAwABLgAECgkJNwAVAE0WAA==.',
Re='Redishpanda:BAAALgADCgcJDQAAAA==.Redshammy:BAAALgAECgcJEQAAAA==.Redward:BAABLgAECn8sAAIFAAgJ/hH0XACbAQAFAAgJ/hH0XACbAQAAAA==.Relion:BAAALgAECgQJBAABLgAECgkJMQAFABsMAA==.',
Rh='Rhell:BAACLgAFFH8OAAIHAAQJqhMcHwD9AAAHAAQJqhMcHwD9AAAuAAQKfzEAAgcACQnCH5EHAPACAAcACQnCH5EHAPACAAAA.',
Ri='Rinche:BAABLgAECn88AAMPAAkJAhOxHwC7AQAPAAkJAhOxHwC7AQAMAAgJ0gqDXQARAQAAAA==.Rintche:BAAALgAECgMJAwAAAA==.',
Ro='Rolland:BAABLgAECn8bAAIQAAcJmx/BBwDmAQAQAAcJmx/BBwDmAQAAAA==.Rollf:BAAALgAECgMJAwAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAABLgAECn8WAAMLAAkJlAitVwCCAQALAAkJlAitVwCCAQAaAAQJ1wRhIgB0AAAAAA==.',
Ru='Rudo:BAABLgAECn8fAAMIAAkJxRVZIgA3AgAIAAkJxRVZIgA3AgARAAEJrgI1XAAoAAAAAA==.Rumproblem:BAABLgAECn8cAAMlAAkJXw9HFgD7AQAlAAkJXw9HFgD7AQAdAAYJAwndQwDXAAAAAA==.Runnamuuk:BAABLgAECn82AAIhAAkJGBQGLgDyAQAhAAkJGBQGLgDyAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryeger:BAABLgAECn8tAAMcAAkJsRSkCAATAgAcAAkJsRSkCAATAgAWAAMJpgtoVwCFAAAAAA==.',
['Rá']='Ráh:BAAALgADCgEJAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn8lAAInAAkJ2xHlGABMAQAnAAkJ2xHlGABMAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBQABLgAECgMJDQACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn8xAAMFAAkJGwxFXwCVAQAFAAkJGwxFXwCVAQAHAAkJYwNXPAAxAQAAAA==.Sandbones:BAAALgAECgUJDAABLgAECgkJNwAVAE0WAA==.Sandraice:BAABLgAECn8fAAIFAAgJ0QYyhwBsAQAFAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sanielan:BAAALgADCgMJBAAAAA==.Sansami:BAABLgAECn8wAAIZAAcJPR1ZGwCtAQAZAAcJPR1ZGwCtAQAAAA==.Saphron:BAAALgAECgQJBAAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAAALgAECgcJEAAAAA==.',
Sc='Scalebagz:BAABLgAECn8XAAMfAAkJ6B1RHADWAQAfAAgJvRxRHADWAQAeAAcJphfUGQC+AQAAAA==.Schism:BAAALgADCgkJDgAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgADCgcJDAAAAA==.Senyorseven:BAAALgAECgYJDgAAAA==.Seo:BAAALgAECgQJCAAAAA==.Serabeara:BAAALgAECgEJAQAAAA==.Setresh:BAABLgAECn8/AAIRAAkJmxWmDwAbAgARAAkJmxWmDwAbAgAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadöwsöng:BAABLgAECn8vAAITAAgJbwpjHQAjAQATAAgJbwpjHQAjAQAAAA==.Shaedelana:BAAALgAECgYJEwAAAA==.Shamrox:BAAALgAECgYJBwAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJMgAEABMfAA==.Shinygoat:BAAALgADCgIJAgABLgAECgkJKgAKAI8fAA==.Shivyn:BAABLgAECn81AAMMAAkJ/BE9LwDNAQAMAAkJ/BE9LwDNAQAPAAEJFwW5jQAqAAAAAA==.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAcJGAAQAIwiAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAABLgAECn8uAAMJAAkJpRmtOgD1AQAJAAkJpRmtOgD1AQAYAAUJrQ9VLgDMAAAAAA==.Sickkid:BAABLgAECn8yAAIbAAcJcyKMDwBdAgAbAAcJcyKMDwBdAgAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silkiegirl:BAABLgAECn8aAAIbAAkJihN4GAAIAgAbAAkJihN4GAAIAgAAAA==.Silvershine:BAABLgAECn8UAAMEAAYJyw4lgADaAAAEAAUJYgslgADaAAAcAAQJuAbnKQCLAAAAAA==.Silverwolf:BAAALgAECgIJAgAAAA==.Sindrya:BAAALgAECgQJBgAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slayne:BAAALgAECgEJAQAAAA==.Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJDAACAAAAAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgkJEAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgABLgAFFAMJBQAJAEMgAA==.Snuggles:BAABLgAECn8gAAIiAAYJmxyfGACJAQAiAAYJmxyfGACJAQABLgAFFAUJFAARADAZAA==.',
So='Solidgen:BAAALgAECgEJAgAAAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAABLgAECn8WAAMTAAgJNRa1EgCaAQATAAgJNRa1EgCaAQASAAMJUgOpNABeAAAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgQJDgAAAA==.',
Ss='Ssraeshza:BAABLgAFFH8KAAInAAUJ9BnSBgA9AQAnAAUJ9BnSBgA9AQABLgAFFAYJFgAGAOYhAA==.',
St='Staretra:BAABLgAECn82AAMdAAkJeBDXGQDUAQAdAAkJeBDXGQDUAQAUAAMJjgM3UwBjAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.',
Su='Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECgcJEAAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Symana:BAABLgAECn8xAAIUAAkJER7eCgCUAgAUAAkJER7eCgCUAgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgADCgcJGAAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgcJEQAAAA==.',
['Sö']='Sörceress:BAAALgAECgMJAwAAAA==.',
Ta='Taadra:BAABLgAECn87AAIMAAkJXR6RCwDaAgAMAAkJXR6RCwDaAgAAAA==.Talerah:BAAALgAECgMJBQAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAACLgAFFH8OAAIEAAQJBhGEIwAUAQAEAAQJBhGEIwAUAQAuAAQKfxUAAgQACAkXGWYeAEwCAAQACAkXGWYeAEwCAAAA.Talona:BAAALgAECgQJBAABLgAFFAQJCQAjAEEXAA==.Tandaan:BAAALgADCgkJCQABLgAECgkJGQALANwVAA==.Tanjent:BAABLgAECn8UAAIIAAYJxwp0jwDxAAAIAAYJxwp0jwDxAAAAAA==.Tapio:BAABLgAECn8jAAIRAAcJWhaGHACcAQARAAcJWhaGHACcAQAAAA==.Tatsuma:BAAALgAECgYJDgABLgAECgcJEQACAAAAAA==.Tatsumå:BAAALgAECgcJEQAAAA==.Tavvi:BAAALgAECgYJBgABLgAECgcJFgAIAN0iAA==.',
Te='Terp:BAAALgAECgMJBgAAAA==.',
Th='Thalfinore:BAAALgAECgcJEgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Therogue:BAAALgAECgIJAgAAAA==.Thorincan:BAAALgAECgkJBwAAAA==.Thorrs:BAAALgAECgIJBQAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thuglifé:BAAALgADCgYJDQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECgQJBgACAAAAAA==.Tidemaiden:BAAALgAECgYJEAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgABLgAFFAMJBQAMANEWAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tipsymancer:BAABLgAECn89AAIZAAkJ/yC9AwD5AgAZAAkJ/yC9AwD5AgAAAA==.Tirael:BAAALgAECgYJBQABLgAFFAUJAQACAAAAAA==.',
To='Tomö:BAAALgAECgcJAgAAAA==.Tossme:BAAALgAECgEJAQABLgAECgkJKwANANQdAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Treesus:BAABLgAECn8fAAIWAAkJLhqWGwAmAgAWAAkJLhqWGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECgkJHwAIAMUVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQOAAgJ+iN5LQBHAgAOAAgJXCF5LQBHAgAVAAMJPCRqBgAvAQAoAAEJTQ0VDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8lAAIEAAkJsRgGHgA0AgAEAAkJsRgGHgA0AgAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.',
Va='Vainin:BAAALgAECgQJCgAAAA==.Valle:BAAALgAECgYJCwAAAA==.Valry:BAAALgAECgYJDgAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAQJFgAZAHIYAA==.Variable:BAAALgADCgEJAQAAAA==.Vashdin:BAABLgAECn8WAAIFAAcJExnCaQB+AQAFAAcJExnCaQB+AQAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECgkJHwAIAMUVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velashis:BAABLgAECn8oAAIEAAkJDBpPEwCRAgAEAAkJDBpPEwCRAgAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAAALgAFFAMJBAAAAA==.Vett:BAAALgADCgMJAwABLgAECgQJCgACAAAAAA==.',
Vi='Viable:BAAALgAECgQJCQAAAA==.Vibes:BAAALgAECgQJBAAAAA==.Victorvega:BAAALgAECgMJAwABLgAECgkJHwAIAMUVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8NAAMDAAMJvQ5OKgCvAAADAAMJvQ5OKgCvAAANAAIJlxm2IQCbAAAuAAQKfxkAAw0ACQmQHRcQAH8CAA0ACAlXHRcQAH8CAAMABQnvH+dEAAUBAAAA.Vivila:BAAALgAECgEJAQABLgAECgkJNAAhAKIWAA==.Vivillian:BAABLgAFFH8HAAIlAAMJjg/CJADbAAAlAAMJjg/CJADbAAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Vordilina:BAABLgAECn8cAAQoAAkJqhg8AQCCAgAoAAkJqhg8AQCCAgAVAAEJuAV9IAAtAAAOAAEJrQHbiAEcAAAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQeAAgJKhn4EwAGAgAeAAgJKhn4EwAGAgAgAAQJxRi2EgC+AAAfAAEJygPwhwAkAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAABLgAECn8jAAMMAAcJLhdjOQCcAQAMAAcJLhdjOQCcAQAPAAcJ5w8AOwAdAQAAAA==.',
['Vé']='Véxx:BAABLgAECn8jAAQKAAcJ4RwnCADPAQAKAAcJ4RwnCADPAQAiAAUJYAizQgDtAAAhAAEJdAGj9QAZAAAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Warihor:BAABLgAECn8vAAMSAAgJeQxKJQAWAQAbAAgJIwqnNQBPAQASAAgJhQlKJQAWAQAAAA==.Waycaps:BAAALgAECgcJCQAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAABLgAECn8sAAIjAAkJPyR6AAArAwAjAAkJPyR6AAArAwAAAA==.',
Wi='Wiegraf:BAAALgADCgYJBgABLgAECgkJMgAEABMfAA==.Wife:BAAALgAECgIJAgAAAA==.Withers:BAAALgADCgEJAQAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJBgAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECgYJCQAAAA==.',
['Wä']='Wärbëef:BAAALgADCgEJAQAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECgQJBgACAAAAAA==.',
Xo='Xorxel:BAAALgAECgMJBAAAAA==.',
Ya='Yacob:BAABLgAECn8tAAIUAAkJ3BwuCADHAgAUAAkJ3BwuCADHAgAAAA==.',
Ye='Yenneferr:BAAALgADCgUJBQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8yAAIEAAkJEx9hCQAIAwAEAAkJEx9hCQAIAwAAAA==.',
Yh='Yhwach:BAACLgAFFH8LAAIYAAUJtAw6GQDkAAAYAAUJtAw6GQDkAAAuAAQKfyEAAhgACAk4GJMPAOQBABgACAk4GJMPAOQBAAAA.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAAALgAECgcJDQABLgAECgMJBAACAAAAAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECgQJBgAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgYJCgAAAA==.',
Za='Zaeden:BAABLgAECn8cAAIDAAcJmx6fFgANAgADAAcJmx6fFgANAgABLgAECggJDwACAAAAAA==.Zaft:BAAALgADCgYJBgAAAA==.Zaftdh:BAABLgAECn8rAAIhAAkJVxVZMQDjAQAhAAkJVxVZMQDjAQAAAA==.Zaha:BAABLgAECn8eAAIOAAYJ2iKdXAAkAgAOAAYJ2iKdXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zem:BAABLgAECn8mAAIbAAgJmR+3EwAxAgAbAAgJmR+3EwAxAgAAAA==.Zeroultra:BAABLgAECn8sAAIbAAcJFiA2FQAjAgAbAAcJFiA2FQAjAgAAAA==.Zeräse:BAAALgAECgYJCgABLgAECgkJMgAEABMfAA==.Zeusmos:BAABLgAECn8jAAINAAgJmSUMBgDNAgANAAgJmSUMBgDNAgAAAA==.',
Zi='Zithenex:BAABLgAECn8jAAIgAAcJURE5CgBcAQAgAAcJURE5CgBcAQAAAA==.',
Zo='Zoeÿ:BAAALgAECgEJAwAAAA==.',
Zw='Zwar:BAAALgAECgIJAgAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAAALgAECgYJEQAAAA==.',
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
