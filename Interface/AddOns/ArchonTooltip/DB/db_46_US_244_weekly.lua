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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Restoration','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Warrior-Arms','Warrior-Protection','Priest-Holy','Mage-Arcane','Druid-Balance','DeathKnight-Frost','Warlock-Destruction','Hunter-Survival','Warrior-Fury','Druid-Feral','Monk-Brewmaster','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','DeathKnight-Blood','DemonHunter-Havoc','Warlock-Affliction','Shaman-Enhancement','Rogue-Assassination','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-05-17',data={Aa='Aaminae:BAABLgAECn8hAAIBAAgJfxdGEwDBAQABAAgJfxdGEwDBAQAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgQJBAAAAA==.Abracastabya:BAAALgAECggJDwAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.',
Ad='Adachï:BAABLgAECn8WAAIDAAYJiRqiIQCfAQADAAYJiRqiIQCfAQABLgAECgkJLwAEAGoeAA==.Adevil:BAAALgAECgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aethlin:BAABLgAECn8mAAMFAAkJEBuTCwDBAQAFAAcJghuTCwDBAQAGAAkJhxR+WgCBAQAAAA==.Aeturnas:BAABLgAECn8pAAIHAAgJhSDICQCxAgAHAAgJhSDICQCxAgAAAA==.',
Ag='Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanima:BAAALgAECgcJDQAAAA==.Aldky:BAAALgADCgkJDgAAAA==.Aliana:BAAALgAECgIJAwAAAA==.Allindis:BAAALgAECgYJCQABLgAECgkJJQAEALEYAA==.Allypally:BAAALgADCgMJAwAAAA==.Alphamage:BAAALgADCgMJAwAAAA==.Alphamonk:BAAALgAECggJDgAAAA==.Alros:BAABLgAECn8uAAIIAAkJLiALCwDCAgAIAAkJLiALCwDCAgAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgAECgMJBAAAAA==.',
Am='Amardyton:BAAALgAECgYJBwAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgIJAgACAAAAAA==.Arctica:BAAALgADCgQJBAAAAA==.Arette:BAAALgAECgIJAgAAAA==.Arkades:BAABLgAECn8WAAIGAAgJUhsTJQAyAgAGAAgJUhsTJQAyAgAAAA==.Arkshade:BAABLgAECn8hAAIJAAcJWA3pdwA6AQAJAAcJWA3pdwA6AQAAAA==.Arlia:BAAALgAECgkJEAAAAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECgkJKgAKAI8fAA==.Aryn:BAAALgAECgEJAQAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgQJBQACAAAAAA==.Ashor:BAAALgAECgEJAQAAAA==.Asmo:BAAALgADCggJGAAAAA==.Astarii:BAAALgAECgEJBAAAAA==.Asterica:BAABLgAECn82AAILAAkJOBaMOgAiAgALAAkJOBaMOgAiAgAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAIMAAYJ+A16UwA4AQAMAAYJ+A16UwA4AQAAAA==.',
Av='Averynicole:BAABLgAECn8ZAAINAAcJBRbEHwBrAQANAAcJBRbEHwBrAQAAAA==.',
Aw='Awasjr:BAABLgAECn8iAAIIAAgJ9x0oHwAnAgAIAAgJ9x0oHwAnAgAAAA==.',
Ay='Ayano:BAABLgAECn8UAAIOAAcJhB2hVQCjAQAOAAcJhB2hVQCjAQAAAA==.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDQABLgAECgkJLwAEAGoeAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgADCgkJDgAAAA==.Bearhug:BAABLgAECn8mAAMDAAgJrhZkIACwAQADAAcJrRhkIACwAQANAAYJhAiBQgANAQABLgAFFAQJBwAPAF4MAA==.Bearshock:BAABLgAFFH8HAAMPAAQJXgw1JwCpAAAPAAMJPgU1JwCpAAAMAAEJTACvWwAfAAAAAA==.Beasty:BAABLgAECn8eAAIQAAcJVhAWEAAZAQAQAAcJVhAWEAAZAQAAAA==.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAABLgAECn8uAAIFAAkJoiRYAQAJAwAFAAkJoiRYAQAJAwAAAA==.Beeb:BAAALgAECgUJDgABLgAECgkJLgAFAKIkAA==.Beefisting:BAAALgAECgYJDAABLgAECgkJLgAFAKIkAA==.Beethicc:BAAALgAECgEJAgABLgAECgkJLgAFAKIkAA==.Beeuwu:BAAALgAECgEJAgABLgAECgkJLgAFAKIkAA==.Belardor:BAAALgAECgkJBwAAAA==.Beliara:BAAALgAECgYJCgAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Belshuntress:BAAALgAECgEJAgAAAA==.Beverage:BAAALgAECgEJAQAAAA==.',
Bi='Bigmattyl:BAAALgAECgcJBQAAAA==.Bionarra:BAABLgAECn8qAAIOAAgJIxrvNQAIAgAOAAgJIxrvNQAIAgABLgAECgkJGwAGAOwVAA==.Bishopwr:BAABLgAECn8bAAMRAAgJaxQvDwCwAQARAAgJaxQvDwCwAQASAAYJPwgqKAC1AAAAAA==.Bittertøfu:BAABLgAECn8eAAIPAAcJfQbFQQDiAAAPAAcJfQbFQQDiAAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJBwAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blitê:BAAALgADCgUJBQABLgADCgkJDQACAAAAAA==.',
Bm='Bmpfrostie:BAAALgAECgcJDwAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECgkJLQATANwcAA==.Bohica:BAAALgAECggJDQAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAABLgAFFAIJAgACAAAAAA==.',
Br='Brakug:BAABLgAECn8sAAMOAAkJbSIULgC5AgAOAAkJbSIULgC5AgAUAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAIJAwAAAA==.Brem:BAABLgAECn8bAAIUAAgJgBweBAASAgAUAAgJgBweBAASAgAAAA==.Bretagnesse:BAABLgAECn8UAAIVAAgJ2wVINQD2AAAVAAgJ2wVINQD2AAAAAA==.Briara:BAAALgAECgMJAwAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgADCgEJAQAAAA==.Broníx:BAAALgAECgEJBQAAAA==.Bropeep:BAABLgAECn8rAAMJAAgJ0SBoGgBvAgAJAAgJ0SBoGgBvAgAWAAQJnRRVEQD1AAAAAA==.',
Bu='Bullshott:BAABLgAECn8XAAIIAAgJmxvaLQDhAQAIAAgJmxvaLQDhAQAAAA==.Bum:BAABLgAECn8mAAMVAAkJsh/4BABRAwAVAAkJsh/4BABRAwAEAAEJ0xCM0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgAECgQJBAAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJDwAAAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBgAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAAALgAECggJDwAAAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8qAAIGAAgJpwcNhgAnAQAGAAgJpwcNhgAnAQAAAA==.Carrots:BAABLgAECn8aAAIIAAcJNBQiTAB0AQAIAAcJNBQiTAB0AQAAAA==.Cashmachine:BAABLgAECn8nAAIIAAkJdx0dEQCIAgAIAAkJdx0dEQCIAgAAAA==.Catfight:BAABLgAECn8cAAIFAAcJnw5THADqAAAFAAcJnw5THADqAAAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMLAAkJchgeLAD2AQALAAkJchgeLAD2AQAXAAEJAABoZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8LAAQIAAQJ3B7hDwBwAQAIAAQJuB3hDwBwAQAQAAEJISI3IwBlAAAYAAEJzA80IgBRAAAuAAQKfxgABBAACAlEIMIYAGYCABAACAmlH8IYAGYCAAgAAwl9GRaLANYAABgAAwkkGKU8AIcAAAAA.Cheesecake:BAABLgAECn8cAAIXAAYJvxAWEAD9AAAXAAYJvxAWEAD9AAAAAA==.Chihiko:BAAALgAECgMJAwAAAA==.Choks:BAABLgAECn8VAAIZAAcJZgfNQQD7AAAZAAcJZgfNQQD7AAAAAA==.Chromie:BAAALgADCgMJAwAAAA==.Chubbycat:BAABLgAECn8VAAMEAAcJLhmOPQCuAQAEAAcJLhmOPQCuAQAaAAUJYh1JEABcAQAAAA==.Chuggz:BAABLgAECn8nAAIbAAgJ5hj1EQDyAQAbAAgJ5hj1EQDyAQAAAA==.Chéfboyrlee:BAACLgAFFH8WAAIcAAYJ7huqBADBAQAcAAYJ7huqBADBAQAuAAQKfzYAAhwACQn7IlICACoDABwACQn7IlICACoDAAAA.',
Ci='Cizmac:BAAALgAECgIJBAAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgADCgYJCgAAAA==.Cownado:BAABLgAECn8iAAIbAAcJOQ9TKQA2AQAbAAcJOQ9TKQA2AQABLgAECggJDwACAAAAAA==.',
Cr='Crouton:BAAALgADCgkJCgAAAA==.',
Cu='Cursedspirit:BAAALgAECgMJAwAAAA==.',
Cy='Cybelem:BAABLgAECn8sAAIPAAkJ7R1rCgB8AgAPAAkJ7R1rCgB8AgAAAA==.Cyfelen:BAAALgAECgYJBgAAAA==.Cynleel:BAAALgAECggJDgAAAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQAAAA==.Damonstyle:BAAALgAECgEJAgAAAA==.Dandistyle:BAABLgAECn8fAAMbAAkJdx1/BwCPAgAbAAkJbh1/BwCPAgANAAEJchK2fAAzAAAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Darrot:BAAALgAECgMJBAAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAAALgAECgMJAwAAAA==.Deeviant:BAAALgAECggJDQAAAA==.Defend:BAAALgAECgYJBgABLgAFFAQJEwAbAEoPAA==.Delrager:BAABLgAECn8bAAIBAAcJSiNwCwAqAgABAAcJSiNwCwAqAgAAAA==.Demonicdawn:BAAALgADCgEJAQAAAA==.Derat:BAAALgAECgkJEQAAAA==.',
Di='Dibbydab:BAABLgAECn8cAAIMAAgJ9xBYNwCDAQAMAAgJ9xBYNwCDAQAAAA==.',
Dj='Django:BAABLgAECn82AAMVAAkJsyJbAwAFAwAVAAkJsyJbAwAFAwAEAAIJkAboowBCAAAAAA==.Djatalon:BAAALgAECgUJDQAAAA==.Djderpyderpy:BAAALgAECgUJBwAAAA==.Djehrtey:BAAALgADCgYJCgAAAA==.Djin:BAAALgAECgMJBAABLgAECgkJKAANAMMbAA==.Djinni:BAABLgAECn8oAAMNAAkJwxsUCQB1AgANAAkJEhsUCQB1AgAbAAYJ0x3xIwBYAQAAAA==.',
Do='Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8WAAMWAAYJfBjBBQDVAQAWAAYJfBjBBQDVAQAJAAMJsA2A/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8XAAQdAAcJNxklDADVAQAdAAcJNxklDADVAQAeAAQJuwzaSQC9AAAfAAEJAACAPAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Dramaticus:BAAALgADCgEJAQAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drenleah:BAAALgAECgUJBgABLgAECggJLAAgAFkYAA==.Drenlee:BAAALgADCgYJBgABLgAECggJLAAgAFkYAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgAAAA==.Dryya:BAAALgAECgMJBAAAAA==.Drêck:BAAALgAECgEJAQAAAA==.',
Du='Dumblegear:BAABLgAECn8dAAMOAAcJuhRjcwBcAQAOAAcJuhRjcwBcAQAUAAEJbQY0IAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAECggJKQARAPcgAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgADCgQJBwAAAA==.Dädärkbeëf:BAAALgADCgcJBwAAAA==.',
Ed='Edinna:BAABLgAECn8iAAMOAAkJAw8oRQDTAQAOAAkJAw8oRQDTAQAUAAQJTQoTEADBAAAAAA==.',
Ei='Einekliene:BAAALgAECgcJBwAAAA==.',
Ek='Ekatrina:BAAALgADCgkJDgAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Eldernoc:BAAALgADCgQJBAAAAA==.Elessedil:BAAALgAECgcJDAAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgIJBAAAAA==.Elyriana:BAABLgAECn8iAAMEAAkJpSDEBQAxAwAEAAkJpSDEBQAxAwAaAAEJqSCgKgBfAAAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEBLgAECn8WAAIIAAYJuh7fOQCyAQAIAAYJuh7fOQCyAQAAAA==.Emixi:BAAALgAECgEJAQAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECgcJDAAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8QAAIGAAUJjBv8HABPAQAGAAUJjBv8HABPAQAuAAQKfzEAAgYACQmaHx4VAJACAAYACQmaHx4VAJACAAAA.',
Er='Erazath:BAAALgAECgUJBgABLgAECggJGQAhAI4TAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgAECgIJAgAAAA==.',
Es='Esha:BAAALgADCgkJDgAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Falar:BAAALgAECggJDQAAAA==.Fatelf:BAAALgADCgMJAwAAAA==.Faval:BAAALgAECggJDwABLgAECgkJKgAKAI8fAA==.Favel:BAABLgAECn8qAAMKAAkJjx9OAQAcAwAKAAgJ4iFOAQAcAwAgAAkJRguyRwBuAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn8oAAIIAAgJkRYFOAC4AQAIAAgJkRYFOAC4AQAAAA==.Febz:BAABLgAECn8eAAIOAAgJbBsqMACyAgAOAAgJbBsqMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAAALgAECgcJEwAAAA==.Felfüry:BAABLgAECn8vAAQiAAkJeg1lFwBxAQAiAAkJHw1lFwBxAQAKAAgJkQVyEgDdAAAgAAEJGgM2/QARAAAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECgQJBQACAAAAAA==.Finella:BAAALgAECgMJBAAAAA==.Finneas:BAAALgADCgUJBQABLgAECggJFgAGAFIbAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJLAAOAG0iAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgMJBAACAAAAAA==.',
Fj='Fjeighty:BAABLgAECn8aAAIiAAcJbw4sHgAvAQAiAAcJbw4sHgAvAQAAAA==.',
Fo='Foggpy:BAACLgAFFH8MAAMjAAUJixD9AQBDAQAjAAUJQxD9AQBDAQALAAQJnwP7TADqAAAuAAQKfyUABCMACAmWInUEADYCACMABwkcJXUEADYCAAsABgkNG8FXAMABABcABgliGQ4fAFgBAAAA.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freinkenbaby:BAAALgAECgEJAQAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostlicious:BAAALgADCgEJAQAAAA==.Frostybear:BAABLgAECn82AAIOAAkJ/hWfKwAxAgAOAAkJ/hWfKwAxAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAABLgAECn8rAAMhAAgJiQiqIwDqAAAhAAgJiQiqIwDqAAAWAAEJ8QHyKQAaAAAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Galaythien:BAAALgAECgIJAwAAAA==.Gang:BAAALgAECgUJBQABLgAFFAIJCAABAJcQAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAgAEQaAA==.',
Ge='Geluria:BAAALgAECgcJBwABLgAECgkJNAAbADYkAA==.Geret:BAABLgAECn8iAAIGAAgJdxM7UACbAQAGAAgJdxM7UACbAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Glitchy:BAABLgAECn80AAIVAAkJSB1ICQCAAgAVAAkJSB1ICQCAAgAAAA==.Glokraz:BAAALgAECgcJBwAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgUJCwAAAA==.',
Go='Goingtogetu:BAABLgAECn80AAIFAAkJdSEmAgDVAgAFAAkJdSEmAgDVAgAAAA==.Gold:BAAALgAECgIJAgAAAA==.Goldfarmr:BAABLgAECn8rAAITAAkJPh+KBwC7AgATAAkJPh+KBwC7AgAAAA==.Goldrawr:BAAALgAECgYJBgAAAA==.Goldshocker:BAAALgAECgQJBgAAAA==.Golduwu:BAAALgAECgEJAgAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.',
Gr='Greeley:BAABLgAECn8nAAIQAAkJ2iP/AAAPAwAQAAkJ2iP/AAAPAwAAAA==.Gregdapro:BAABLgAECn87AAIhAAkJqiOuAQAlAwAhAAkJqiOuAQAlAwAAAA==.Gregnstone:BAABLgAECn8aAAIHAAgJsBgUJgCYAQAHAAgJsBgUJgCYAQABLgAECgkJOwAhAKojAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAMJBQAeAH4GAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAUJGgAZAAofAA==.Gunnyal:BAABLgAECn8aAAMRAAcJ7g4WHQAoAQARAAcJhw4WHQAoAQAZAAQJzQjHVQCuAAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8sAAIPAAkJSiONAwAFAwAPAAkJSiONAwAFAwAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8aAAMZAAUJCh/UCAB1AQAZAAUJCh/UCAB1AQARAAEJNAEQDgA8AAAuAAQKfzwAAxkACQktJdIAAGcDABkACQktJdIAAGcDABEAAwldHF0nAOQAAAAA.Hakyahi:BAAALgADCggJCAAAAA==.Hank:BAAALgADCgYJBgAAAA==.Harkin:BAABLgAECn8mAAIGAAkJ4Q4aUACbAQAGAAkJ4Q4aUACbAQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgAECgIJBAAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIPAAcJXQsNOQAIAQAPAAcJXQsNOQAIAQAAAA==.Hermioné:BAAALgADCgUJBQAAAA==.Hevy:BAABLgAECn8sAAIgAAgJWRhFKgDkAQAgAAgJWRhFKgDkAQAAAA==.',
Hi='Hilarius:BAAALgAECggJEQAAAA==.Hiraeth:BAAALgAECgUJCQAAAA==.',
Ho='Holydadbod:BAAALgAECgQJBwABLgAECgkJKAANAMMbAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn8xAAIGAAkJ4xNSOADkAQAGAAkJ4xNSOADkAQAAAA==.Howlinnbrews:BAABLgAFFH8GAAMNAAIJNCIEHACfAAANAAIJcBcEHACfAAAbAAEJ6CW7PQBtAAAAAA==.Howlinplague:BAAALgAECgYJCQAAAA==.',
Hu='Hulkhogan:BAABLgAECn8UAAISAAcJGh8eEgDmAQASAAcJGh8eEgDmAQAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIgAAMJRBp5PADwAAAgAAMJRBp5PADwAAAuAAQKfyEAAiAACAnuIbAVANQCACAACAnuIbAVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMEAAgJihjKHwAMAgAEAAgJihjKHwAMAgAaAAIJ1hJPLwBKAAAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8aAAINAAcJVBbEJgA5AQANAAcJVBbEJgA5AQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Iobo:BAABLgAECn8bAAIYAAcJjA8bHwBoAQAYAAcJjA8bHwBoAQAAAA==.',
Ir='Ironhidez:BAABLgAECn8fAAIGAAgJvQi+gwArAQAGAAgJvQi+gwArAQAAAA==.',
Is='Isaarek:BAAALgAECgkJEQAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDgAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAYJGgAJAIkcAA==.Jastia:BAAALgAECgYJEQAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jebopally:BAAALgAECgMJBAABLgAECggJDwACAAAAAA==.Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8oAAMLAAkJHBsbFgBvAgALAAkJHBsbFgBvAgAXAAEJAAD2bQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8iAAIGAAgJvAvPcABPAQAGAAgJvAvPcABPAQAAAA==.',
Jo='Joecephus:BAABLgAECn8VAAIHAAcJtCFzCwCXAgAHAAcJtCFzCwCXAgAAAA==.Joehex:BAABLgAECn8tAAISAAgJVCCWBgBnAgASAAgJVCCWBgBnAgAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Jubelius:BAAALgAECgUJBQABLgAECgkJHwAIAMIVAA==.Judgematt:BAAALgAECgcJDQAAAA==.Justin:BAABLgAECn8XAAIRAAcJWBa9EQCRAQARAAcJWBa9EQCRAQAAAA==.',
Ka='Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAIQAAgJ0AwmDwApAQAQAAgJ0AwmDwApAQAAAA==.Kaleesh:BAACLgAFFH8NAAIkAAUJESUeAQCmAQAkAAUJESUeAQCmAQAuAAQKfyMAAiQACAmqJEcBAGgDACQACAmqJEcBAGgDAAAA.Kallux:BAABLgAECn8rAAIhAAkJtRt7CABLAgAhAAkJtRt7CABLAgAAAA==.Kananga:BAABLgAECn8aAAITAAcJERf1GgCzAQATAAcJERf1GgCzAQAAAA==.Karavira:BAAALgAECgEJAQAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgADCgkJEQAAAA==.',
Ke='Kelindina:BAAALgAECgMJDAAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Keoeu:BAAALgAECgMJAwAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgIJBAAAAA==.',
Ki='Kieleron:BAAALgAECgYJEgAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJDgAAAA==.Kiermaxim:BAABLgAECn8mAAIPAAgJNBwcGwA6AgAPAAgJNBwcGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Kiragrande:BAABLgAECn8hAAIDAAkJwxAlHQDEAQADAAkJwxAlHQDEAQAAAA==.Kiraneth:BAABLgAECn8gAAINAAgJMBDtIABiAQANAAgJMBDtIABiAQAAAA==.Kirbie:BAAALgADCgEJAQAAAA==.Kirial:BAAALgADCgcJBwAAAA==.Kiriku:BAAALgAECggJEwAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgQJBAAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgADCgYJBgAAAA==.',
La='Lagartista:BAAALgAECgcJCAAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Le='Lee:BAAALgAFFAUJAQAAAA==.Lefty:BAAALgADCgcJBwABLgAECgkJOwAYAAoUAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lilpwny:BAAALgADCgMJAwABLgAECggJIAAcAEkZAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn8tAAIZAAgJoyPnCACZAgAZAAgJoyPnCACZAgAAAA==.Logres:BAAALgADCgEJAQAAAA==.Lokeira:BAABLgAECn8oAAIMAAgJHhtAJgDdAQAMAAgJHhtAJgDdAQAAAA==.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn8qAAIGAAgJ7xGMZgBlAQAGAAgJ7xGMZgBlAQAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgEJAgABLgAECgcJHAAOADsTAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Luvbug:BAABLgAECn8WAAIIAAcJ3SJ9GAB2AgAIAAcJ3SJ9GAB2AgAAAA==.',
Ly='Lyara:BAACLgAFFH8TAAMMAAUJ4iO3BgDoAQAMAAUJ4iO3BgDoAQAPAAIJ1w9mGQCLAAAuAAQKfxkAAwwACAkVIFAJAOICAAwACAkVIFAJAOICAA8ABAkfFhFbANgAAAAA.Lyi:BAAALgAECgUJBwAAAA==.Lythos:BAABLgAECn8ZAAIhAAgJjhNqGwBzAQAhAAgJjhNqGwBzAQAAAA==.Lyu:BAAALgAFFAEJAQABLgAFFAUJEwAMAOIjAA==.Lyuu:BAABLgAFFH8GAAIOAAMJdxbYVwD5AAAOAAMJdxbYVwD5AAABLgAFFAUJEwAMAOIjAA==.',
['Lø']='Lørdøfßud:BAABLgAECn8pAAMRAAgJ9yAxBwBAAgARAAcJEyMxBwBAAgAZAAgJ4RyjFwDwAQAAAA==.',
Ma='Macguffin:BAAALgADCgkJDgAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJHQAgAIULAA==.Makimá:BAAALgADCgYJBgABLgAECgkJHwAIAMIVAA==.Malifae:BAABLgAECn8bAAIVAAcJYSGbEwB3AgAVAAcJYSGbEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwAVAGEhAA==.Mankilla:BAAALgAECgMJAwAAAA==.Mansa:BAABLgAECn8qAAIlAAgJ3ReGBQDhAQAlAAgJ3ReGBQDhAQAAAA==.Mastamojo:BAABLgAECn8pAAIHAAkJ/QdKLgBiAQAHAAkJ/QdKLgBiAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Maîev:BAAALgAECgUJBwAAAA==.',
Mc='Mcmurphy:BAAALgAECgUJDAAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAABLgAECn8VAAIXAAYJ/hMxDgAXAQAXAAYJ/hMxDgAXAQAAAA==.Melendaren:BAAALgAECgIJBAAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgAECgMJBAAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAECgIJAgAAAA==.Meowkug:BAAALgAECgEJAQAAAA==.Merscy:BAABLgAECn8bAAITAAgJngpxKwAxAQATAAgJngpxKwAxAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAABLgAECn8XAAMVAAcJDQ+rMwD+AAAVAAcJDQ+rMwD+AAAEAAEJVgpFvQAmAAAAAA==.Metamonster:BAABLgAECn8cAAMhAAcJLw4KKgC7AAAJAAcJiQQPuwDDAAAhAAYJ4w8KKgC7AAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgMJBQAAAA==.Mirko:BAABLgAECn8dAAIgAAcJhQtfcAD9AAAgAAcJhQtfcAD9AAAAAA==.Mistiah:BAAALgAFFAIJAgAAAA==.Mistyjoe:BAAALgADCgMJAwAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn8uAAIUAAkJcxRCAgAOAgAUAAkJcxRCAgAOAgAAAA==.Mokokniki:BAAALgADCggJCQAAAA==.Moneie:BAAALgAECgMJBQAAAA==.Monger:BAAALgADCgIJAgAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAFFAEJAQACAAAAAA==.Moondo:BAAALgAECgcJDgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mourningstar:BAACLgAFFH8OAAMJAAUJHiNaIQB6AQAJAAQJHiNaIQB6AQAhAAEJAAA9PAAAAAAuAAQKfx8AAwkACQl5IEAUAAIDAAkACAkzI0AUAAIDACEAAgm1EUk1AHkAAAEuAAUUBgkaAAkAiRwA.Mozaic:BAABLgAECn8tAAISAAgJzhYqDwCyAQASAAgJzhYqDwCyAQAAAA==.',
Mu='Mugrüíth:BAAALgAECgIJBAAAAA==.',
My='Myfeethurt:BAAALgADCgYJBgABLgAECggJKQARAPcgAA==.Myragê:BAAALgADCgkJDQAAAA==.Myselia:BAABLgAECn8YAAIiAAgJMhYAGgBUAQAiAAgJMhYAGgBUAQAAAA==.Mystra:BAAALgAECgQJBQAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgADCgQJBAAAAA==.Naek:BAAALgAECgIJBAAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgIJBAACAAAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAABLgAECn8XAAIOAAcJMBHcdABZAQAOAAcJMBHcdABZAQAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAABLgAECn8XAAIgAAgJugkxaAARAQAgAAgJugkxaAARAQAAAA==.Niem:BAABLgAECn8dAAImAAkJhSWcAABYAwAmAAkJhSWcAABYAwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.',
No='Nocturnum:BAABLgAECn8sAAIgAAgJ5hhGLQDWAQAgAAgJ5hhGLQDWAQAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8HAAIjAAQJRQ9PAABcAQAjAAQJRQ9PAABcAQAuAAQKfxwAAiMACAktHi8BAPECACMACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAAAAA==.Odin:BAAALgADCgYJBgAAAA==.Odium:BAAALgADCgMJAwABLgAFFAQJCwAIANweAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAYJFwAQACciAA==.',
Ol='Oldmage:BAAALgADCgUJBQAAAA==.Oldmongerpal:BAAALgAECgEJAQAAAA==.',
On='Onetwocowpow:BAABLgAECn80AAIDAAkJyBaiEQA3AgADAAkJyBaiEQA3AgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn82AAMGAAkJeSFwDwATAwAGAAkJeSFwDwATAwAFAAEJqwS/QQAjAAAAAA==.Orionn:BAACLgAFFH8SAAIIAAQJRSBlDQB8AQAIAAQJRSBlDQB8AQAuAAQKfz0AAggACQm2JTgCAFEDAAgACQm2JTgCAFEDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAABLgAECn8ZAAIIAAgJkwz6dgAFAQAIAAgJkwz6dgAFAQAAAA==.',
Ov='Oven:BAABLgAECn8gAAINAAgJVxZsGACqAQANAAgJVxZsGACqAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.Patelz:BAAALgADCgQJBAAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQABLgAECgcJCwACAAAAAA==.Polyeikon:BAAALgAECgUJBwAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgADCgcJBwAAAA==.Praystation:BAAALgAECgUJCAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgUJBQAAAA==.',
Ra='Raekeshh:BAAALgAECgkJEAAAAA==.Raelone:BAABLgAECn8ZAAMXAAgJshBlGgCgAAALAAUJYQ1TiwD1AAAXAAYJZBJlGgCgAAAAAA==.Rageofmommy:BAAALgADCgMJAwAAAA==.Raidoe:BAABLgAECn8zAAMDAAkJPh0OEQA/AgADAAgJgBwOEQA/AgANAAMJOQviVQBtAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn8qAAIIAAgJbBiJNADFAQAIAAgJbBiJNADFAQAAAA==.Rant:BAAALgAECgQJCQAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.',
Re='Redishpanda:BAAALgADCgcJBwAAAA==.Redshammy:BAAALgAECgcJEQAAAA==.Redward:BAABLgAECn8nAAIGAAgJDBF3WgCBAQAGAAgJDBF3WgCBAQAAAA==.Relion:BAAALgAECgQJBAABLgAECgkJKAAGABsMAA==.',
Rh='Rhell:BAACLgAFFH8OAAIHAAQJqhO6GQASAQAHAAQJqhO6GQASAQAuAAQKfzEAAgcACQnDH8IFAP0CAAcACQnDH8IFAP0CAAAA.',
Ri='Rinche:BAABLgAECn8zAAMPAAkJTBJcHAC2AQAPAAkJTBJcHAC2AQAMAAgJ0grOUgARAQAAAA==.Rintche:BAAALgAECgMJAwAAAA==.',
Ro='Rolland:BAABLgAECn8bAAIQAAcJnh9aBgDxAQAQAAcJnh9aBgDxAQAAAA==.Rollf:BAAALgAECgMJAwAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAABLgAECn8WAAMLAAkJlAi7TgB9AQALAAkJlAi7TgB9AQAXAAQJ1wTaHgB6AAAAAA==.',
Ru='Rudo:BAABLgAECn8fAAMIAAkJwhVOJgADAgAIAAkJwhVOJgADAgAYAAEJrgKAUgAsAAAAAA==.Rumproblem:BAAALgAECgkJEwAAAA==.Runnamuuk:BAABLgAECn8sAAIgAAgJmw9dTQBcAQAgAAgJmw9dTQBcAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryeger:BAABLgAECn8kAAMaAAgJpBWBCQDaAQAaAAgJpBWBCQDaAQAVAAMJyATaVwBkAAAAAA==.',
['Rá']='Ráh:BAAALgADCgEJAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn8hAAImAAgJkhLuGAAfAQAmAAgJkhLuGAAfAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBAABLgAECgMJDAACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn8oAAMGAAkJGwzTVACPAQAGAAkJGwzTVACPAQAHAAEJigUxdAAxAAAAAA==.Sandbones:BAAALgAECgQJBwABLgAECgkJLgAUAHMUAA==.Sandraice:BAABLgAECn8fAAIGAAgJ0QYyhwBsAQAGAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sanielan:BAAALgADCgMJAwAAAA==.Sansami:BAABLgAECn8pAAIbAAcJPR3iGwCUAQAbAAcJPR3iGwCUAQAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAAALgAECgYJCQAAAA==.',
Sc='Scalebagz:BAABLgAECn8XAAMeAAkJ5x3iFwDXAQAeAAgJuxziFwDXAQAdAAcJqRfUGQC+AQAAAA==.Schism:BAAALgADCgkJDgAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgADCgcJDAAAAA==.Senyorseven:BAAALgAECgYJDgAAAA==.Seo:BAAALgAECgMJBAAAAA==.Setresh:BAABLgAECn82AAIYAAkJgxU5DQAeAgAYAAkJgxU5DQAeAgAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadöwsöng:BAABLgAECn8rAAISAAgJ6wnXGgAfAQASAAgJ6wnXGgAfAQAAAA==.Shaedelana:BAAALgAECgYJDwAAAA==.Shamrox:BAAALgAECgYJBwAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJLwAEAGoeAA==.Shinygoat:BAAALgADCgIJAgABLgAECgkJKgAKAI8fAA==.Shivyn:BAABLgAECn8zAAMMAAkJxQ0TOACAAQAMAAkJxQ0TOACAAQAPAAEJFwW5jQAqAAAAAA==.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAYJFwAQACciAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAABLgAECn8uAAMJAAkJpRmkMQD+AQAJAAkJpRmkMQD+AQAhAAUJrQ9VLgDMAAAAAA==.Sickkid:BAABLgAECn8oAAIZAAcJMBsyGgDbAQAZAAcJMBsyGgDbAQAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silkiegirl:BAAALgAECgIJAgAAAA==.Silvershine:BAABLgAECn8UAAMEAAYJyw4lgADaAAAEAAUJYgslgADaAAAaAAQJuAZAJACOAAAAAA==.Silverwolf:BAAALgAECgIJAgAAAA==.Sindrya:BAAALgAECgQJBgAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slayne:BAAALgAECgEJAQAAAA==.Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJDAACAAAAAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgkJDAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgABLgAFFAIJAgACAAAAAA==.Snuggles:BAABLgAECn8aAAIiAAYJlxroFwBrAQAiAAYJlxroFwBrAQABLgAFFAUJEAAYADAZAA==.',
So='Solidgen:BAAALgAECgEJAQAAAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAABLgAECn8WAAMSAAgJMxagFABlAQASAAgJMxagFABlAQARAAMJUgOpNABeAAAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgQJCwAAAA==.',
Ss='Ssraeshza:BAABLgAFFH8FAAImAAUJ9BnLBAA/AQAmAAUJ9BnLBAA/AQAAAA==.',
St='Staretra:BAABLgAECn8tAAMcAAkJ3A2yGwChAQAcAAkJ3A2yGwChAQATAAMJjQO9TABmAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.',
Su='Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECgcJEAAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Symana:BAABLgAECn8xAAITAAkJER63CACgAgATAAkJER63CACgAgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgADCgcJGAAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgYJDQAAAA==.',
['Sö']='Sörceress:BAAALgAECgMJAwAAAA==.',
Ta='Taadra:BAABLgAECn8yAAIMAAkJIhwCDAC7AgAMAAkJIhwCDAC7AgAAAA==.Talerah:BAAALgAECgIJAgAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAACLgAFFH8KAAIEAAQJBhETHgAZAQAEAAQJBhETHgAZAQAuAAQKfxUAAgQACAkXGWYeAEwCAAQACAkXGWYeAEwCAAAA.Talona:BAAALgAECgQJBAABLgAFFAQJBwAjAEUPAA==.Tandaan:BAAALgADCgkJCQABLgAECgkJEAACAAAAAA==.Tanjent:BAAALgAECgYJDwAAAA==.Tapio:BAABLgAECn8cAAIYAAcJ8xWjGgCRAQAYAAcJ8xWjGgCRAQAAAA==.Tatsuma:BAAALgAECgQJCAABLgAECgcJHwAGACMdAA==.Tatsumå:BAAALgAECgYJEAABLgAECgcJHwAGACMdAA==.Tavvi:BAAALgAECgYJBgABLgAECgcJFgAIAN0iAA==.',
Te='Terp:BAAALgAECgMJBgAAAA==.',
Th='Thalfinore:BAAALgAECgcJEgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Therogue:BAAALgAECgIJAgAAAA==.Thorincan:BAAALgAECgkJBwAAAA==.Thorrs:BAAALgAECgIJAgAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thuglifé:BAAALgADCgYJDQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECgQJBQACAAAAAA==.Tidemaiden:BAAALgAECgYJEAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tipsymancer:BAABLgAECn80AAIbAAkJbh5oBQC7AgAbAAkJbh5oBQC7AgAAAA==.Tirael:BAAALgAECgYJBQABLgAFFAUJAQACAAAAAA==.',
To='Tomö:BAAALgAECgIJAgAAAA==.Tossme:BAAALgAECgEJAQABLgAECgkJKAANAMMbAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Treesus:BAABLgAECn8fAAIVAAkJLRqWGwAmAgAVAAkJLRqWGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECgkJHwAIAMIVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQOAAgJ4iMfJQBQAgAOAAgJWyEfJQBQAgAUAAMJBCTiBQAzAQAnAAEJTQ0VDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8lAAIEAAkJsRgvGgA3AgAEAAkJsRgvGgA3AgAAAA==.',
Ur='Uruloki:BAABLgAFFH8FAAIeAAMJfgY0MADAAAAeAAMJfgY0MADAAAAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.',
Va='Vainin:BAAALgAECgQJCgAAAA==.Valle:BAAALgAECgYJCwAAAA==.Valry:BAAALgAECgUJCAAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAQJEwAbAEoPAA==.Variable:BAAALgADCgEJAQAAAA==.Vashdin:BAABLgAECn8WAAIGAAcJExlqVwCJAQAGAAcJExlqVwCJAQAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECgkJHwAIAMIVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velashis:BAABLgAECn8fAAIEAAkJMBd7JQDmAQAEAAkJMBd7JQDmAQAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAAALgAFFAEJAQAAAA==.Vett:BAAALgADCgMJAwABLgAECgQJCgACAAAAAA==.',
Vi='Viable:BAAALgAECgQJBgAAAA==.Vibes:BAAALgADCgkJEQAAAA==.Victorvega:BAAALgAECgMJAwABLgAECgkJHwAIAMIVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8NAAMDAAMJvQ5qIQC6AAADAAMJvQ5qIQC6AAANAAIJlxk6HACdAAAuAAQKfxkAAw0ACQmQHRcQAH8CAA0ACAlXHRcQAH8CAAMABQnvH5o5AAUBAAAA.Vivillian:BAAALgAFFAIJBAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Vordilina:BAAALgAECggJEwAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQdAAgJKhn4EwAGAgAdAAgJKhn4EwAGAgAfAAQJxRivEADEAAAeAAEJygPEegAkAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAABLgAECn8cAAMMAAcJ1Rc9QQBWAQAMAAYJ2BY9QQBWAQAPAAYJCBGsOwD9AAAAAA==.',
['Vé']='Véxx:BAABLgAECn8cAAQKAAYJmB5wCQCLAQAKAAYJmB5wCQCLAQAiAAUJYAizQgDtAAAgAAEJdAGj9QAZAAAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Warihor:BAABLgAECn8sAAMZAAgJUgyiMABKAQAZAAgJuAmiMABKAQARAAgJXwldIQALAQAAAA==.Waycaps:BAAALgAECgIJAgAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAABLgAECn8qAAIjAAkJxSNyAAASAwAjAAkJxSNyAAASAwAAAA==.',
Wi='Wife:BAAALgAECgIJAgAAAA==.Withers:BAAALgADCgEJAQAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJBgAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECgYJCQAAAA==.',
['Wä']='Wärbëef:BAAALgADCgEJAQAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECgQJBQACAAAAAA==.',
Xo='Xorxel:BAAALgAECgMJBAAAAA==.',
Ya='Yacob:BAABLgAECn8tAAITAAkJ3Bx6BgDUAgATAAkJ3Bx6BgDUAgAAAA==.',
Ye='Yenneferr:BAAALgADCgUJBQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8vAAIEAAkJah4ECQD1AgAEAAkJah4ECQD1AgAAAA==.',
Yh='Yhwach:BAACLgAFFH8JAAIhAAQJAwxfFQDmAAAhAAQJAwxfFQDmAAAuAAQKfx8AAiEACAm5F2ENAOkBACEACAm5F2ENAOkBAAAA.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAAALgAECgcJDQABLgAECgMJBAACAAAAAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECgQJBQAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgQJBAAAAA==.',
Za='Zaeden:BAABLgAECn8cAAIDAAcJmx6fFgANAgADAAcJmx6fFgANAgAAAA==.Zaftdh:BAABLgAECn8iAAIgAAkJKRTCMADGAQAgAAkJKRTCMADGAQAAAA==.Zaha:BAABLgAECn8eAAIOAAYJ2iKdXAAkAgAOAAYJ2iKdXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zem:BAABLgAECn8mAAIZAAgJmh+QDwBBAgAZAAgJmh+QDwBBAgAAAA==.Zeroultra:BAABLgAECn8lAAIZAAcJ1R7xFAAKAgAZAAcJ1R7xFAAKAgAAAA==.Zeräse:BAAALgADCgcJBwABLgAECgkJLwAEAGoeAA==.Zeusmos:BAABLgAECn8jAAINAAgJmCXSBADTAgANAAgJmCXSBADTAgAAAA==.',
Zi='Zithenex:BAABLgAECn8cAAIfAAcJ7A8JCgBDAQAfAAcJ7A8JCgBDAQAAAA==.',
Zo='Zoeÿ:BAAALgAECgEJAgAAAA==.',
Zw='Zwar:BAAALgAECgIJAgAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAAALgAECgMJBwAAAA==.',
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
