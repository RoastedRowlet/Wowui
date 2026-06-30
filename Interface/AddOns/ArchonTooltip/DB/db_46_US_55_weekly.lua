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

local lookup = {'Rogue-Assassination','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Evoker-Devastation','Priest-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Druid-Restoration','Unknown-Unknown','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Paladin-Holy','Paladin-Retribution','Monk-Windwalker','Paladin-Protection','Warrior-Fury','DemonHunter-Devourer','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Evoker-Preservation','Monk-Mistweaver','Warlock-Demonology','DemonHunter-Havoc','Priest-Discipline','Evoker-Augmentation','Warrior-Arms','DemonHunter-Vengeance','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abracadava:BAAALgAECgQJBQAAAA==.',
Ac='Acheniris:BAAALgAECgUJDQAAAA==.',
Ad='Adeaino:BAAALgAECgUJCAAAAA==.Adonix:BAAALgAECgEJAQAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgUJBwAAAA==.',
Ag='Agrippa:BAACLgAFFH8HAAIBAAQJyQE8CgCaAAABAAQJyQE8CgCaAAAuAAQKfxwAAgEACAmgDo4JAKMBAAEACAmgDo4JAKMBAAAA.',
Ah='Ahndhrez:BAAALgAECgcJBgAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECggJEwAAAA==.Aioli:BAABLgAECn8kAAQCAAkJ1BvVEgARAgACAAkJuRjVEgARAgADAAYJ7hdaRwCUAQAEAAUJcRo4SAAzAQAAAA==.Airwavez:BAAALgAECgcJDQAAAA==.',
Al='Alchemorph:BAABLgAECn8XAAIFAAgJSwnQPQAYAQAFAAgJSwnQPQAYAQAAAA==.Aldormu:BAABLgAECn8mAAIGAAkJuAx8CgB3AQAGAAkJuAx8CgB3AQAAAA==.Aliyah:BAEALgADCgIJAgABLgAECgkJJgAHAMoZAA==.Allura:BAACLgAFFH8SAAIHAAQJzRGZHADTAAAHAAQJzRGZHADTAAAuAAQKfyQAAgcACQmLGQ4WACwCAAcACQmLGQ4WACwCAAAA.Altra:BAACLgAFFH8TAAMIAAUJDguJEQAHAQAIAAQJDguJEQAHAQAJAAEJAAD+HwAAAAAuAAQKfykAAwgACQl5HFYCAJ8CAAgACQl5HFYCAJ8CAAkABwl7A1orAOQAAAAA.Alyvia:BAAALgADCgEJAgAAAA==.',
Am='Amoeta:BAABLgAECn81AAQKAAkJFRZjDwC/AQAKAAgJ0hVjDwC/AQALAAkJAg6qIABJAQAMAAcJyQg9aQD4AAAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgQJBAAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgAECgIJAwAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angelkinq:BAAALgAECgEJAwAAAA==.Angryapples:BAAALgAECgQJCQAAAA==.Anilbeedz:BAAALgAECgEJAQAAAA==.Annihilation:BAAALgAECgUJCQAAAA==.Antinous:BAABLgAECn8qAAIEAAgJ3gw6EwArAQAEAAgJ3gw6EwArAQAAAA==.',
Ap='Apathia:BAAALgAECgEJAQABLgAECgYJCAANAAAAAA==.Aphrodité:BAAALgAECgIJAgAAAA==.',
Ar='Arcstorm:BAAALgAECgYJDwAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Ashenback:BAACLgAFFH8GAAMOAAMJXAqHYgCEAAAOAAMJXAqHYgCEAAAPAAEJkQkKHAA+AAAuAAQKfxkABA8ACAl8GlEKABUCAA8ACAkxGlEKABUCABAAAwn1HoNJAA4BAA4AAgkaGuucAJcAAAEuAAUUBgkOABEA7xEA.Asomyrh:BAABLgAECn8lAAMRAAkJmxUEGgA1AgARAAkJmxUEGgA1AgASAAEJPQHY0wESAAAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgYJCAAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgAECgQJCAAAAA==.',
Av='Averyl:BAAALgAECgUJBQAAAA==.Aviendha:BAAALgAECgYJCgAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAITAAgJLQptKgCKAQATAAgJLQptKgCKAQAAAA==.',
Az='Azenith:BAABLgAECn8cAAMSAAYJgRx9agCaAQASAAYJgRx9agCaAQAUAAEJrQjGVAAnAAAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bamboozle:BAAALgADCgcJBwAAAA==.Bananer:BAABLgAECn8iAAIVAAkJeBRSIwDZAQAVAAkJeBRSIwDZAQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Bb='Bbqlol:BAAALgAECgYJBwABLgAECgYJHgASAGccAA==.',
Be='Beaugersugar:BAAALgAECgQJBQAAAA==.Beebler:BAABLgAECn8YAAIPAAgJnhfnDgDCAQAPAAgJnhfnDgDCAQAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgAECgcJCAAAAA==.Bennington:BAAALgADCgYJBgAAAA==.Beowulf:BAAALgAECgEJBAAAAA==.Bestt:BAAALgAECgQJCQAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Bigbluenfab:BAAALgAECgIJAgAAAA==.Bigdaddyd:BAAALgAECgIJAgAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigholylady:BAAALgADCgkJCQAAAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigocagler:BAAALgAECgcJAQAAAA==.Bigolchungus:BAABLgAECn8eAAMUAAkJwRpuCQA7AgAUAAgJeBluCQA7AgASAAUJ6BjFuwAOAQAAAA==.Bigpapadots:BAAALgAECgMJBAAAAA==.Bigpéet:BAAALgAECgMJBwAAAA==.Bigshizz:BAAALgAECgQJBgABLgAECgcJFwAFAAEhAA==.Bippysmasher:BAABLgAECn8kAAIWAAkJaxI1SACuAQAWAAkJaxI1SACuAQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.',
Bl='Blacblood:BAABLgAECn8fAAIIAAkJYRHNBQDSAQAIAAkJYRHNBQDSAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJEQAAAA==.Blindweiss:BAAALgAFFAEJAQABLgAFFAcJFgAXABwUAA==.Blinkies:BAABLgAECn8iAAMYAAkJbSD5AADWAgAYAAkJbSD5AADWAgAXAAUJlg8wvgAMAQAAAA==.Blinkster:BAAALgAECgEJBAAAAA==.Bloodfushion:BAAALgADCgYJBgAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgAECgMJAwANAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8QAAIDAAcJGRnZEADeAQADAAcJGRnZEADeAQAuAAQKfysAAgMACQmNIycKAAYDAAMACQmNIycKAAYDAAAA.Boolala:BAAALgAECgYJDgABLgAECggJCQANAAAAAA==.Borstenne:BAACLgAFFH8SAAIZAAUJGR3PUQBOAQAZAAUJGR3PUQBOAQAuAAQKfykAAhkACQm7JEoTANQCABkACQm7JEoTANQCAAAA.',
Br='Brake:BAACLgAFFH8KAAIZAAMJnxFTqwDIAAAZAAMJnxFTqwDIAAAuAAQKfyYAAhkACAlXHvU1AF8CABkACAlXHvU1AF8CAAAA.Brese:BAAALgAECgIJAgABLgAFFAUJEwAWAHIZAQ==.Breseayaya:BAACLgAFFH8TAAIWAAUJchlIPwAqAQAWAAUJchlIPwAqAQAuAAQKfy0AAhYACQkrIXcNANkCABYACQkrIXcNANkCAAAA.Breseshh:BAAALgAECgcJEwABLgAFFAUJEwAWAHIZAA==.Brickbeard:BAACLgAFFH8NAAIaAAQJeREOBQA4AQAaAAQJeREOBQA4AQAuAAQKfy0AAxoACQl0Fa0GAA8CABoACQl0Fa0GAA8CABsABwnDDeUZAH0BAAAA.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJEgABLgAFFAgJGQASAJ0cAA==.Bricksquad:BAAALgAECgMJAwABLgAFFAMJBQAWAHodAA==.Brickthrow:BAACLgAFFH8ZAAMSAAgJnRyhHQCSAQASAAYJ1hqhHQCSAQARAAMJOQjULADIAAAuAAQKfzMAAxIACQmsJBgIACsDABIACQmsJBgIACsDABEABQlyBENyAG4AAAAA.Bronkle:BAAALgAECgUJBQABLgAFFAQJDQAaAHkRAA==.',
Bu='Buhleed:BAAALgAECgIJAgAAAA==.Burgerburn:BAAALgAECgUJBgAAAA==.',
By='Bytheway:BAABLgAECn8WAAIcAAgJ4RN8LgBnAQAcAAgJ4RN8LgBnAQAAAA==.',
['Bà']='Bàbÿ:BAAALgAECgcJDgAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAACLgAFFH8TAAIMAAUJPxBgMADvAAAMAAUJPxBgMADvAAAuAAQKfzEABAwACQm4I8cIACsDAAwACQm4I8cIACsDAAUAAglbGzx8AE4AAAsAAQlKAac3ABkAAAAA.Cadsune:BAAALgAECgYJDAAAAA==.Caelesti:BAABLgAECn8oAAMHAAgJVxMfIADCAQAHAAgJVxMfIADCAQAcAAgJxhacJgCYAQAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAgAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQABLgAFFAgJHAAdAG8YAA==.Chelbur:BAAALgADCgEJAQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chosmuke:BAAALgAECgEJAwAAAA==.Chowderhead:BAABLgAECn8UAAIbAAYJYxzhDgDcAQAbAAYJYxzhDgDcAQAAAA==.',
Ci='Cileb:BAACLgAFFH8GAAIXAAUJSBipYAAgAQAXAAUJSBipYAAgAQAuAAQKfzUAAhcACQmkJAIMABkDABcACQmkJAIMABkDAAAA.Civik:BAABLgAECn9KAAIDAAkJciOICQAMAwADAAkJciOICQAMAwAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAFFAMJBQAWAHodAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAACLgAFFH8SAAISAAQJ0xXePgAtAQASAAQJ0xXePgAtAQAuAAQKfzAAAhIACQldGl89AA8CABIACQldGl89AA8CAAAA.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAFFAQJBQAWAAkFAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJJwAJAAkjAA==.Copperit:BAABLgAECn8nAAIJAAkJCSOQAgBDAwAJAAkJCSOQAgBDAwAAAA==.Cornburglar:BAACLgAFFH8SAAIVAAQJkSJgEQB7AQAVAAQJkSJgEQB7AQAuAAQKfzoAAhUACAlcJXAIANkCABUACAlcJXAIANkCAAAA.Cowtaclysmic:BAACLgAFFH8FAAIZAAIJOgfN3wCFAAAZAAIJOgfN3wCFAAAuAAQKfyMAAxkACAkGE6SAAGIBABkACAmaDKSAAGIBAAkABQlKFmoqAAUBAAAA.',
Cr='Crackersz:BAABLgAECn8WAAMOAAcJHQgMigDHAAAOAAcJHQgMigDHAAAQAAMJGATNhwBgAAAAAA==.Cranjis:BAABLgAECn9RAAIeAAkJ9iFnBwAoAwAeAAkJ9iFnBwAoAwAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Crunchwrap:BAABLgAECn8qAAIFAAkJDA8LJwCWAQAFAAkJDA8LJwCWAQAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgcJBwAAAA==.',
Cu='Curadora:BAAALgADCgQJBAAAAA==.Cursereflect:BAABLgAECn8iAAMfAAkJyQ7fUwCgAQAfAAkJyQ7fUwCgAQAbAAEJAADNVgAAAAAAAA==.Curseus:BAAALgAECgIJBQAAAA==.',
Cy='Cyberwin:BAAALgAECgEJAQAAAA==.',
Da='Damncats:BAABLgAECn9FAAIVAAkJExN5AgB3AQAVAAkJExN5AgB3AQAAAA==.Dandinn:BAAALgAECgYJCQAAAA==.Danielsboone:BAABLgAECn8lAAIDAAgJrxDACQAgAQADAAgJrxDACQAgAQAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJCAABLgAFFAUJDQAQAMMMAA==.Darknemesis:BAAALgAECgYJDAAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAFFAIJAwABLgAFFAcJOgAbALAgAA==.',
De='Deadhippocow:BAABLgAECn8bAAIMAAcJ8x3jLAD0AQAMAAcJ8x3jLAD0AQAAAA==.Deathwavez:BAACLgAFFH8ZAAIZAAUJqhORHwDnAAAZAAUJqhORHwDnAAAuAAQKfxoAAhkABwkwFwFlAMUBABkABwkwFwFlAMUBAAAA.Declän:BAAALgAECgQJBgABLgAECgcJGwAMAPMdAA==.Decurse:BAABLgAECn8kAAIfAAkJ+hTPPADoAQAfAAkJ+hTPPADoAQAAAA==.Degrono:BAAALgAECgQJBAAAAA==.Deldrin:BAABLgAECn8mAAIXAAkJERSJUADqAQAXAAkJERSJUADqAQAAAA==.Demayy:BAABLgAECn8uAAIeAAkJKxNWIwAFAgAeAAkJKxNWIwAFAgAAAA==.Demona:BAACLgAFFH8MAAMfAAUJAwwHYQAGAQAfAAQJAwwHYQAGAQAaAAIJkgdYLAA9AAAuAAQKfyUAAxsACAkxGe4pABoBAB8ABwnIFQl4AEkBABsABAngE+4pABoBAAAA.Demonix:BAABLgAECn8YAAIfAAgJlRoeNgABAgAfAAgJlRoeNgABAgAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAACLgAFFH8KAAIXAAQJdwckcQD/AAAXAAQJdwckcQD/AAAuAAQKfzoAAhcACQm/D19XANcBABcACQm/D19XANcBAAAA.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAABLgAECn8eAAMSAAYJZxxweQB7AQASAAYJZxxweQB7AQARAAIJsAQDhABDAAAAAA==.Dinobrass:BAACLgAFFH8FAAMEAAMJHgLlJwBuAAAEAAMJHgLlJwBuAAADAAEJ5QNZSQA9AAAuAAQKfyMAAgQACAm0DXMRAEQBAAQACAm0DXMRAEQBAAAA.Dirktheshiny:BAAALgAECgkJDwABLgAECgkJPQAFAIEbAA==.Dirtylöbster:BAACLgAFFH8OAAIXAAMJTCHYJwAUAQAXAAMJTCHYJwAUAQAuAAQKfzUAAhcACQkKJb0JACwDABcACQkKJb0JACwDAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgYJEQABLgAECgYJHgASAGccAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAABLgAECn8UAAIFAAgJpxfbLgBlAQAFAAgJpxfbLgBlAQAAAA==.Dorfydorf:BAAALgAECgEJAgAAAA==.Dorose:BAAALgAECgEJAgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Dranight:BAAALgAECgcJBwABLgAECgkJSgADAHIjAA==.Dreats:BAAALgAECgYJCgAAAA==.Drewmee:BAABLgAECn8YAAISAAkJHgkPkQBQAQASAAkJHgkPkQBQAQAAAA==.Dronar:BAABLgAFFH8FAAIOAAUJCgk3LwAlAQAOAAUJCgk3LwAlAQABLgAECgkJIwALAAEgAA==.Drublood:BAAALgAECgcJCwABLgAECgkJGAASAB4JAA==.Drunkinmasta:BAAALgAECgEJAQABLgAFFAQJEAASAB4WAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Duckbeak:BAAALgADCgUJCwAAAA==.Dune:BAAALgADCgcJBwAAAA==.Duwork:BAABLgAECn8XAAIFAAcJASHkHADhAQAFAAcJASHkHADhAQAAAA==.',
['Dæ']='Dæmona:BAABLgAECn8VAAIgAAkJmxLTFQDeAQAgAAkJmxLTFQDeAQAAAA==.',
Eb='Ebk:BAAALgAECgcJDAAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
Ei='Eight:BAAALgADCggJGAAAAA==.',
El='Eladus:BAAALgAECgcJEAAAAA==.Elemnt:BAAALgAECgYJDQABLgAFFAQJEAASAB4WAA==.Elesus:BAAALgAECggJDQABLgAECgkJQwAhAJUhAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJDgAAAA==.Emrys:BAAALgAECgMJAgAAAA==.',
En='Enhshaman:BAACLgAFFH8FAAIeAAMJGQajRQCNAAAeAAMJGQajRQCNAAAuAAQKfxYAAh4ACQn+FDYkAP8BAB4ACQn+FDYkAP8BAAAA.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.Evilinne:BAAALgADCgIJAgAAAA==.Evânescence:BAAALgAECgEJAQAAAA==.',
Ex='Excaliburn:BAAALgAECgEJBQAAAA==.',
Ez='Ezekial:BAAALgAECgQJBAAAAA==.Ezkal:BAACLgAFFH8UAAIZAAUJGxzFaAAoAQAZAAUJGxzFaAAoAQAuAAQKfywAAxkACQnsGaEYAOgCABkACQnsGaEYAOgCAAkABgktFW0rAP4AAAAA.',
Fa='Faithastray:BAAALgAECgMJAwAAAA==.Faithpasse:BAABLgAECn89AAMeAAkJ/x0AAgDrAQAeAAkJ/x0AAgDrAQATAAEJ9gPfhgApAAAAAA==.Falcorne:BAABLgAECn80AAIDAAkJqiIRCAAbAwADAAkJqiIRCAAbAwAAAA==.Fatlipz:BAABLgAECn8iAAIhAAcJdQ8gAwBHAQAhAAcJdQ8gAwBHAQAAAA==.Fay:BAAALgADCgEJAQABLgAECgYJCAANAAAAAA==.',
Fe='Felondar:BAABLgAECn8kAAMgAAkJuw1bIgBlAQAgAAkJuw1bIgBlAQAWAAYJsASzmwDhAAAAAA==.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8ZAAMJAAkJhBsxDABOAgAJAAcJsBsxDABOAgAZAAgJvhiIagC3AQAAAA==.',
Fi='Finnadin:BAABLgAECn8pAAISAAkJzx9dGQCrAgASAAkJzx9dGQCrAgAAAA==.Finns:BAAALgAECgcJEQAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAABLgAECn8dAAIDAAgJ0xnyOQD3AQADAAgJ0xnyOQD3AQAAAA==.Fistinfred:BAAALgADCgMJAwAAAA==.Fistobeef:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.',
Fl='Fleable:BAAALgAECgQJAwAAAA==.Flysky:BAACLgAFFH8cAAIdAAgJbxiMBQB0AgAdAAgJbxiMBQB0AgAuAAQKfywABB0ACQnFI4kCAEcDAB0ACQnFI4kCAEcDACIACAnIJF4HAOICAAYAAQl3DyBBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECggJDQAAAA==.',
Fr='Freakmeout:BAAALgAECgQJBAAAAA==.Freshpot:BAAALgAECgMJAwAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgAECgEJAQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJDgABLgAFFAUJFAAZABscAA==.Futuredragoo:BAAALgAECgcJDAABLgAFFAUJFAAZABscAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Fy='Fyska:BAAALgADCgEJAQAAAA==.',
Ga='Gabriella:BAAALgAECgYJDAAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQANAAAAAA==.Galnannix:BAAALgAECgkJEAAAAA==.Gardrake:BAABLgAECn8zAAMiAAkJrBn5EABeAgAiAAkJrBn5EABeAgAdAAcJqhCrHQCWAQAAAA==.Gastapha:BAABLgAECn8ZAAIWAAkJ0wZoigAMAQAWAAkJ0wZoigAMAQAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMVAAgJCxMcMADvAQAVAAgJCxMcMADvAQAjAAEJAAD2jwAAAAAAAA==.Gehennas:BAABLgAFFH8FAAIWAAMJeh2+UwDzAAAWAAMJeh2+UwDzAAAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Gi='Girnahuma:BAAALgAECgEJAQAAAA==.',
Go='Goku:BAAALgAFFAIJAgAAAA==.Goofykirby:BAAALgADCgcJFQAAAA==.Googoo:BAABLgAECn8UAAIZAAkJrhNCOgAXAgAZAAkJrhNCOgAXAgAAAA==.Googoogagaa:BAACLgAFFH8MAAIcAAQJkhAXHQAHAQAcAAQJkhAXHQAHAQAuAAQKf0YAAxwACQkKHnMNAH0CABwACQkKHnMNAH0CAAcABwnyEgMqAKIBAAAA.Gotlieb:BAAALgAECggJCgAAAA==.',
Gr='Grenno:BAAALgAECgcJBwABLgAFFAgJIAAZANsaAA==.Greystorm:BAAALgAECgIJAgAAAA==.Greythorn:BAAALgADCgkJCQABLgAECgkJSgADAHIjAA==.Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQANAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8iAAMEAAkJvRFYBwCnAQAEAAgJhRNYBwCnAQACAAUJnwxbFwAXAQAuAAQKfxQAAgQABwkJJOIRAKoCAAQABwkJJOIRAKoCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hakarren:BAAALgAECgYJCAAAAA==.Hakosuka:BAAALgADCgEJAQAAAA==.Hamatza:BAAALgAECgEJAgAAAA==.Hammerinfred:BAAALgAECgQJBwAAAA==.Hawkmoon:BAAALgAECgEJBAAAAA==.',
He='Healingisfun:BAAALgAECgMJBAAAAA==.Helhunter:BAABLgAECn8yAAIWAAkJbRL9RwCuAQAWAAkJbRL9RwCuAQAAAA==.Hellock:BAAALgAFFAEJAQAAAA==.',
Hi='Hippysmasher:BAAALgAECgIJAgABLgAECgkJJAAWAGsSAA==.',
Ho='Hodgepodge:BAAALgAECgEJAgAAAA==.Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgMJBQAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holybob:BAAALgAECgQJCAAAAA==.Holyhooters:BAABLgAECn87AAISAAkJ2yFiDwDrAgASAAkJ2yFiDwDrAgAAAA==.Holypablo:BAAALgAECgQJBgABLgAECgkJUQAhAMEfAA==.Homefries:BAAALgADCgYJBgABLgAECgcJGwAMAPMdAA==.Honkytonk:BAABLgAECn8aAAMGAAgJKQtAIgAYAQAGAAYJ7QlAIgAYAQAiAAcJeAmsOAATAQAAAA==.Honor:BAAALgAECgcJBwABLgAECgkJOwASAI8jAA==.Honour:BAABLgAECn87AAISAAkJjyMgDgD0AgASAAkJjyMgDgD0AgAAAA==.',
Hr='Hrathdemon:BAACLgAFFH8SAAIWAAUJlxfSQAAlAQAWAAUJlxfSQAAlAQAuAAQKfysAAhYACQntIPMQALoCABYACQntIPMQALoCAAAA.Hrathid:BAAALgADCgUJDAABLgAFFAUJEgAWAJcXAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8KAAISAAMJiiBUEgATAQASAAMJiiBUEgATAQAuAAQKfywAAhIACQnqI7oFAHIDABIACQnqI7oFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAABLgAECn8YAAMSAAkJwRuILwBDAgASAAkJwRuILwBDAgARAAIJWwcbhgA/AAAAAA==.',
Ib='Ibleedorange:BAAALgAECggJDQAAAA==.',
Ic='Icehawk:BAAALgAECgMJBQAAAA==.Ickeetard:BAABLgAECn8eAAMhAAkJXRJ5MQBWAQAhAAcJFA95MQBWAQAHAAYJwxGzQADqAAAAAA==.',
Id='Idiot:BAAALgAECgMJBAAAAA==.Idiotbreath:BAABLgAECn82AAMiAAkJFSCxCADLAgAiAAkJFSCxCADLAgAGAAMJmQmDMACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgAECgEJAgAAAA==.',
Ig='Ignitus:BAAALgAECgMJAwAAAA==.',
Im='Immorlich:BAAALgAECgEJAQAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJCQAAAA==.Inflexi:BAACLgAFFH8KAAIDAAQJyRT3OgA3AQADAAQJyRT3OgA3AQAuAAQKfy0AAwMACQlqIFYNAOgCAAMACQmYH1YNAOgCAAQACAnKGvAYAGQCAAAA.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAABLgAECn8YAAITAAYJWhmmLwBKAQATAAYJWhmmLwBKAQAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn8/AAQMAAkJIB5zDgDjAgAMAAkJIB5zDgDjAgAFAAgJFyDpFAAqAgALAAMJ2hZXOQDAAAAAAA==.',
Iv='Iver:BAAALgAECgUJBgABLgAECgcJEQANAAAAAA==.',
Ja='Jaliano:BAAALgADCgYJBgABLgAECgkJLgAOAJkXAA==.Jangle:BAAALgADCgYJBwAAAA==.',
Je='Jeffblades:BAAALgAECgcJEAAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJBgANAAAAAA==.',
Jj='Jjooaacchhim:BAAALgAECgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8jAAIDAAkJfBt2LQAnAgADAAkJfBt2LQAnAgAAAA==.',
Ka='Kadillac:BAAALgAECgcJEwAAAA==.Kaelira:BAAALgADCgIJAgAAAA==.Kairei:BAAALgAECggJDwAAAA==.Kakashi:BAAALgADCgEJAQAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAACLgAFFH8VAAISAAYJ9BpDKQBnAQASAAYJ9BpDKQBnAQAuAAQKfx0AAxIACQl1ItwRANkCABIACQkUItwRANkCABQAAQlIJYE2AGkAAAAA.Katalina:BAABLgAECn8wAAMkAAgJmBHLDQB2AQAkAAgJmBHLDQB2AQAgAAYJpwsROAAlAQAAAA==.Kawer:BAAALgAECgQJCQAAAA==.Kawnzerker:BAAALgADCgkJCQAAAA==.',
Ke='Keilanis:BAAALgAECgIJAgAAAA==.Kelstormhoof:BAAALgADCgcJFgABLgAECgYJDAANAAAAAA==.Kernel:BAAALgAECgEJAQABLgAFFAQJEgAVAJEiAA==.',
Kh='Kham:BAACLgAFFH8UAAIVAAUJMhsiGQBOAQAVAAUJMhsiGQBOAQAuAAQKf0QAAhUACQlgJMYDACsDABUACQlgJMYDACsDAAAA.Khäléési:BAAALgAECgEJAQAAAA==.',
Ki='Kialla:BAAALgAECgIJAgABLgAECgkJKAAOACsgAA==.Killmaim:BAABLgAECn8ZAAIVAAgJwRllIABPAgAVAAgJwRllIABPAgAAAA==.Kitsuko:BAABLgAECn80AAMOAAkJFg+2PgCzAQAOAAkJFg+2PgCzAQAQAAkJxRDNLACRAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ko='Kokeovrdose:BAAALgAECgQJBAABLgAECgYJFAAXAAYWAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuli:BAAALgAECgEJAgAAAA==.Kuraishin:BAAALgAFFAEJAQABLgAFFAcJFgAXABwUAA==.Kuvare:BAAALgAECgMJAwAAAA==.',
['Kè']='Kèlton:BAAALgAECgUJCgAAAA==.',
La='Lanas:BAEALgAECgkJAwABLgAFFAUJFQASACMRAA==.Laocoon:BAAALgAECggJCAABLgAECgkJOwASANshAA==.Lavashiza:BAAALgAECgYJEwAAAA==.Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAABLgAECn8UAAIDAAgJThKxfABGAQADAAgJThKxfABGAQAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAgAAAA==.Leedaddydk:BAAALgAECgQJCgAAAA==.Leroyjenkins:BAABLgAECn8XAAIlAAcJ8BvoAgBVAgAlAAcJ8BvoAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.Letsbeef:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.',
Li='Lightstorm:BAAALgAECgYJEAAAAA==.Linaria:BAAALgAECgUJCAAAAA==.Linø:BAAALgAECgIJAgAAAA==.Lissara:BAABLgAECn8ZAAIiAAgJExBPNABiAQAiAAgJExBPNABiAQAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAACLgAFFH8TAAImAAUJqRyjGgBQAQAmAAUJqRyjGgBQAQAuAAQKfyMAAiYACQnCHEIOAFUCACYACQnCHEIOAFUCAAAA.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockednabyss:BAAALgAECgQJBAABLgAECgkJOQAnAD0kAA==.Lockmogged:BAAALgAFFAIJAgAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECgkJHAADADIkAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAFFAQJDgAaAKATAA==.Luminouslexi:BAAALgAECgMJAwAAAA==.',
Ma='Macoub:BAACLgAFFH8FAAIWAAQJCQUSYADPAAAWAAQJCQUSYADPAAAuAAQKfxcABCAACAnFFZonAD4BACAABgl2FZonAD4BABYABAmMGrebAOoAACQAAwluB5YxAD0AAAAA.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAABLgAECn8ZAAMbAAgJfQU9GwDLAAAbAAgJUQU9GwDLAAAfAAQJzAOX/gBqAAAAAA==.Maebell:BAAALgAECgYJCwABLgAECgYJHgASAGccAA==.Mageslayer:BAABLgAECn8bAAMnAAgJmxPjHgCfAQAnAAgJGBLjHgCfAQABAAMJPRCNGACtAAAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magicstorm:BAAALgAECgcJBwAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgANAAAAAA==.Magrun:BAAALgADCgYJBgAAAA==.Mahalleinr:BAAALgADCgEJAQAAAA==.Maiggee:BAAALgAECgEJAgAAAA==.Makkideez:BAABLgAECn8UAAInAAkJNxhVEAApAgAnAAkJNxhVEAApAgAAAA==.Makkii:BAAALgADCgEJAQABLgAECgkJFAAnADcYAA==.Malanara:BAAALgADCgEJAQABLgAECgkJJgAXABEUAA==.Malxt:BAAALgADCgYJBwAAAA==.Manabuns:BAABLgAECn8pAAIXAAgJ2xc7XgDEAQAXAAgJ2xc7XgDEAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8lAAISAAkJ/RRKQgAeAgASAAkJ/RRKQgAeAgAAAA==.Markruffalo:BAAALgAECgYJDAAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn86AAIVAAkJaBu9FABKAgAVAAkJaBu9FABKAgAAAA==.',
Mc='Mckay:BAAALgAECggJEwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8mAAIlAAgJRBSzBACjAQAlAAgJRBSzBACjAQAAAA==.Megapunk:BAAALgAECgcJEwAAAA==.Mellmaan:BAAALgAFFAIJAgAAAA==.Melys:BAAALgAECgcJEgAAAA==.Meteorite:BAAALgAECgYJCQAAAA==.Meudayr:BAABLgAECn8jAAILAAkJASBxBADRAgALAAkJASBxBADRAgAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.Mezagog:BAAALgAECgYJDwAAAA==.',
Mi='Mikehammer:BAAALgADCgcJDgAAAA==.Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAACLgAFFH8NAAIQAAUJwww5KwDoAAAQAAUJwww5KwDoAAAuAAQKfx4AAhAACAltHCISAJICABAACAltHCISAJICAAAA.Mittenss:BAAALgADCgIJAgAAAA==.',
Mo='Moistblanket:BAAALgAECgUJBwAAAA==.Mojorisin:BAABLgAECn8jAAICAAkJ6xoUDgBHAgACAAkJ6xoUDgBHAgAAAA==.Moobear:BAAALgAFFAIJAgAAAA==.Moonchiken:BAAALgAECgEJCgAAAA==.Moozlock:BAABLgAECn8rAAIfAAkJEhKNTQCyAQAfAAkJEhKNTQCyAQAAAA==.Moscovio:BAAALgAFFAIJBAABLgAFFAMJBQASAFITAA==.Mosspaws:BAABLgAECn82AAMMAAkJbiTQBgBLAwAMAAkJbiTQBgBLAwAFAAQJZB8ONgA+AQAAAA==.',
Mt='Mtndewyou:BAAALgAECgcJEQAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.Mutterutters:BAAALgAECgEJAgAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.Myrollin:BAAALgAECgIJAgAAAA==.Myrothan:BAAALgAECgMJAwAAAA==.',
Na='Naetara:BAAALgADCgEJAQAAAA==.Narfiy:BAAALgADCgEJAQAAAA==.Narisanna:BAAALgAFFAEJAgAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBgAAAA==.',
Nm='Nme:BAABLgAECn8lAAMXAAkJoBAOXADKAQAXAAkJoBAOXADKAQAlAAYJiw9LCQBWAQAAAA==.',
No='Nocturnos:BAACLgAFFH8HAAIfAAMJ/RNbcwDaAAAfAAMJ/RNbcwDaAAAuAAQKfzIAAx8ACQlNIEQbAIACAB8ACQlNIEQbAIACABoAAgn3IOguAGIAAAAA.Noctyr:BAAALgAECgcJCAAAAA==.Noggin:BAABLgAECn8rAAMRAAkJRyH/BAAcAwARAAkJRyH/BAAcAwASAAgJ/BCGagCaAQAAAA==.Nonform:BAABLgAECn89AAQFAAkJgRvRDACKAgAFAAkJgRvRDACKAgAKAAEJwRXwTAA/AAAMAAEJdAED7AAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECggJIgAWAH0WAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQANAAAAAA==.Novamancer:BAAALgAECgIJAgAAAA==.Noxta:BAAALgAECggJEgAAAA==.',
Nu='Numonixx:BAACLgAFFH8hAAMGAAYJ7A6ZBgDqAAAiAAYJCA2iKQAiAQAGAAQJKwuZBgDqAAAuAAQKfzoAAwYACQkFH4oCAJMCAAYACAmsIIoCAJMCACIACAnGG0IUADsCAAAA.Nutlessfred:BAAALgAECgEJAQAAAA==.',
Ny='Nymage:BAABLgAECn9aAAIXAAkJHBuiKgBvAgAXAAkJHBuiKgBvAgAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogmund:BAAALgAECgcJEgAAAA==.',
Oh='Ohnospiders:BAABLgAECn8yAAMZAAkJpBfNNAAsAgAZAAkJpBfNNAAsAgAIAAQJ4RRYIQDDAAAAAA==.Ohpig:BAAALgAECgMJAwAAAA==.',
Ok='Okaerisan:BAABLgAECn8WAAIUAAkJkxRmFQB8AQAUAAkJkxRmFQB8AQAAAA==.',
Ol='Olord:BAAALgAECgYJBwAAAA==.',
Om='Omarcuthlink:BAAALgAECgEJAQABLgAFFAQJDQAaAHkRAA==.Omgbbqq:BAAALgAECggJCAABLgAFFAMJDAADADMcAA==.',
On='Onilecram:BAAALgAECgIJAwAAAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.Oomkin:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECggJEQAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Ou='Outlast:BAACLgAFFH8QAAISAAQJHhYZOwA1AQASAAQJHhYZOwA1AQAuAAQKfy8AAhIACQm1HbQRAAQDABIACQm1HbQRAAQDAAAA.',
Pa='Paants:BAABLgAECn8kAAIoAAkJugwEHwA7AQAoAAkJugwEHwA7AQAAAA==.Pacid:BAAALgAECgYJDAAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Pakal:BAAALgAECgQJBQAAAA==.Palebull:BAAALgADCgYJCAAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8YAAIWAAgJfxxMCgB1AgAWAAgJfxxMCgB1AgAuAAQKfzMAAhYACQkEJZQEAD0DABYACQkEJZQEAD0DAAAA.Parmageddon:BAAALgAFFAEJAQABLgAFFAQJDgAoAPggAA==.Parmigiano:BAAALgADCgEJAQABLgAFFAQJDgAoAPggAA==.Parmrageiano:BAABLgAFFH8OAAIoAAQJ+CAHDQBdAQAoAAQJ+CAHDQBdAQAAAA==.Parms:BAABLgAECn8ZAAQCAAgJ+xNBJgBrAQACAAgJ6xFBJgBrAQAEAAYJhQxETQAcAQADAAIJORANowCFAAABLgAFFAQJDgAoAPggAA==.Parmy:BAAALgAECgEJAQAAAA==.Pastry:BAAALgAFFAIJAgABLgAFFAYJCwAQACwUAA==.',
Pe='Peanought:BAABLgAECn8qAAMIAAkJjxYBBgDJAQAIAAgJsRcBBgDJAQAZAAkJ5A4UYQCnAQAAAA==.Peidro:BAABLgAECn8bAAISAAcJAA9GqAArAQASAAcJAA9GqAArAQAAAA==.Pentacles:BAABLgAECn8tAAILAAkJsCA5BwCDAgALAAkJsCA5BwCDAgAAAA==.',
Pi='Pijak:BAABLgAECn8UAAIUAAgJuRTaGwA4AQAUAAgJuRTaGwA4AQAAAA==.Pinkpaw:BAABLgAECn8iAAQLAAkJFh/EBADJAgALAAkJFh/EBADJAgAMAAUJthqjSABsAQAKAAEJuBKESgBEAAAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8JAAMmAAMJ3iTvCABGAQAmAAMJ3iTvCABGAQATAAEJlCPlOABjAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCQAmAN4kAA==.Postscalone:BAAALgAECgYJBwAAAA==.Potatoes:BAABLgAECn8VAAMbAAgJBgiWHABpAQAbAAgJBgiWHABpAQAfAAIJCQJIFAE6AAAAAA==.',
Pr='Pruflas:BAABLgAECn8aAAIZAAgJZAtAjgBJAQAZAAgJZAtAjgBJAQAAAA==.',
Ps='Psycodk:BAACLgAFFH8JAAIZAAUJxxztSwBaAQAZAAUJxxztSwBaAQAuAAQKfxYAAhkACAmYGD9sAI0BABkACAmYGD9sAI0BAAAA.',
Pu='Puffdaddie:BAAALgAECgUJBwABLgAECggJJwASAMwfAA==.Pumpin:BAABLgAECn8XAAITAAUJFCTFKgBnAQATAAUJFCTFKgBnAQAAAA==.Punkthor:BAAALgAECgIJAgAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
['Pä']='Päcid:BAAALgAECgUJCAAAAA==.',
Qk='Qkn:BAAALgAECgUJEgAAAA==.',
Qu='Quickswipe:BAABLgAFFH8GAAInAAMJxSAgIgAVAQAnAAMJxSAgIgAVAQABLgAFFAcJOgAbALAgAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgYJCwABLgAECgcJCQANAAAAAA==.Ralee:BAAALgADCgcJCQAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Rastabution:BAAALgAECgkJAQAAAA==.Ratoncita:BAAALgAECgEJAgAAAA==.Raynne:BAAALgAECgIJAgAAAA==.Rayzee:BAAALgADCgUJBQAAAA==.',
Re='Reaperjoe:BAAALgAFFAEJAgAAAA==.Rehab:BAACLgAFFH8IAAISAAMJ4xpyEgDyAAASAAMJ4xpyEgDyAAAuAAQKfxUAAhIACQlbHK4vAGQCABIACQlbHK4vAGQCAAAA.Rehna:BAAALgAECgYJBgABLgAFFAQJEgAHAM0RAA==.Rek:BAAALgAECgEJAQABLgAECgkJIwALAAEgAA==.Rektributio:BAACLgAFFH8eAAISAAgJCyDCBACYAgASAAgJCyDCBACYAgAuAAQKfzcAAhIACQkgJecGADgDABIACQkgJecGADgDAAAA.Resurection:BAAALgAECgYJDQAAAA==.Revalation:BAACLgAFFH8GAAIMAAMJERVpDAC2AAAMAAMJERVpDAC2AAAuAAQKfycAAgwACQlSH9wVAJoCAAwACQlSH9wVAJoCAAAA.Revenancer:BAAALgAECgEJAwAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgANAAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Riachu:BAAALgADCgUJBQAAAA==.Ribeyejoe:BAAALgADCgEJAQAAAA==.Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAACLgAFFH8IAAMVAAMJ5xmZDgC8AAAVAAMJNRmZDgC8AAAoAAIJlxhkIQCNAAAuAAQKfzEAAxUACQmCHx8WAD4CABUACAl0IB8WAD4CACgACAkJF+ESAL4BAAAA.Roadtrip:BAAALgAECgMJBAAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJBAAAAA==.Rockiden:BAAALgADCgEJAQAAAA==.Rottingslow:BAABLgAFFH8IAAIHAAMJ9wDZKwBpAAAHAAMJ9wDZKwBpAAABLgAFFAgJIQAJAHcgAA==.',
Sa='Sanford:BAAALgAECgUJBQAAAA==.Saragos:BAAALgADCgcJBgABLgAFFAcJFgAXABwUAA==.Satine:BAAALgAECgMJAwAAAA==.Saucerdote:BAABLgAECn8eAAMhAAkJmBWxHwDQAQAhAAcJGxexHwDQAQAcAAkJFAlhMQBWAQAAAA==.Saucy:BAAALgAECgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAcJFgAXABwUAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAACLgAFFH8KAAIWAAUJ9RJpTAAFAQAWAAUJ9RJpTAAFAQAuAAQKfysAAhYACQl7H6kPAMYCABYACQl7H6kPAMYCAAAA.Selkie:BAABLgAECn8mAAIPAAkJvw85DgDMAQAPAAkJvw85DgDMAQAAAA==.Seragosa:BAAALgAFFAEJAQABLgAFFAcJFgAXABwUAA==.',
Sh='Shakakhan:BAAALgAECgYJDQABLgAECgYJHgASAGccAA==.Shambeau:BAAALgADCgQJBAAAAA==.Shamrun:BAAALgADCgQJBQAAAA==.Shamshielder:BAECLgAFFH8SAAQIAAUJiBJPEQAKAQAIAAQJZwpPEQAKAQAJAAMJihivOQBPAAAZAAIJMgdGVwBIAAAuAAQKfy0ABAkACQmZI5cFAM0CAAkACQmZI5cFAM0CAAgABgmlGxwOAJQBABkAAQm5CXeNASkAAAAA.Shapper:BAAALgAECgQJBgAAAA==.Sharick:BAAALgAECgQJBQAAAA==.Shawlee:BAACLgAFFH8FAAMQAAMJGgKEFQBjAAAQAAIJ9QKEFQBjAAAOAAEJjQLXjAAmAAAuAAQKfy0AAw4ACAnMECRcAEkBAA4ACAnMECRcAEkBABAACAk7CnVWAOEAAAAA.Sheezie:BAACLgAFFH8KAAIOAAMJExrdPADwAAAOAAMJExrdPADwAAAuAAQKf0kAAw4ACQmkIVoFAF0DAA4ACQmkIVoFAF0DAA8ACQnfGDULAAQCAAAA.Shellcow:BAAALgAECgYJBgABLgAECgkJIgAYAG0gAA==.Shellter:BAAALgAECgEJAgABLgAECgkJIgAYAG0gAA==.Shellwit:BAAALgAECgMJBgABLgAECgkJIgAYAG0gAA==.Sheph:BAAALgAFFAEJAQAAAA==.Shetmage:BAACLgAFFH8XAAIXAAcJdwvUNQCSAQAXAAcJdwvUNQCSAQAuAAQKfykAAhcACQnDIAEkAI0CABcACQnDIAEkAI0CAAAA.Shettdh:BAAALgAECgUJCQAAAA==.Shettrah:BAABLgAECn8UAAIFAAYJ+hoeKwB8AQAFAAYJ+hoeKwB8AQABLgAFFAcJFwAXAHcLAA==.Shienro:BAAALgAECgQJBAABLgAECgQJCQANAAAAAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAABLgAECn8oAAISAAkJOhRKYACwAQASAAkJOhRKYACwAQAAAA==.Shuck:BAAALgAECgQJBAABLgAFFAQJEgAVAJEiAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Sibyx:BAAALgAECgYJEgABLgAECgYJHgASAGccAA==.Siickboy:BAAALgAECgQJCQAAAA==.Sijious:BAAALgAECgYJDAAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.',
Sk='Skinable:BAAALgAFFAEJAQAAAA==.Skora:BAAALgADCgIJAgABLgAECgkJJQASAP0UAA==.Skyland:BAAALgADCgcJDQABLgAFFAgJHAAdAG8YAA==.Skyli:BAAALgAECgUJCAABLgAECgkJKAAOACsgAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Sneez:BAAALgAFFAEJAQAAAA==.Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAACLgAFFH8TAAIRAAUJZxqSIgALAQARAAUJZxqSIgALAQAuAAQKfycAAhEACQmfH7wIAOMCABEACQmfH7wIAOMCAAAA.Sorrie:BAAALgAECgEJAQAAAA==.Sortiarius:BAAALgADCgkJCQAAAA==.',
Sp='Spud:BAAALgADCgcJBwABLgAECgYJFgADAI8fAA==.Spyroh:BAABLgAECn8bAAQGAAYJ6BLuGQBlAQAGAAYJcBDuGQBlAQAiAAUJGBJMSAAKAQAdAAEJ2wA4TwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAQJEgAHAM0RAA==.',
St='Stankydk:BAACLgAFFH8RAAMZAAcJRBTiKQDBAQAZAAYJRBTiKQDBAQAJAAEJAACCagAAAAAuAAQKfzIAAhkACQk+JdAFAEsDABkACQk+JdAFAEsDAAAA.Stankyeyes:BAAALgAECgYJBgAAAA==.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Staticdh:BAABLgAFFH8FAAIWAAUJfREzGQDKAAAWAAUJfREzGQDKAAABLgAFFAgJJwAXAGsgAA==.Steakhead:BAABLgAECn8pAAIFAAYJxAsXTQDYAAAFAAYJxAsXTQDYAAAAAA==.Stinkbombs:BAACLgAFFH8RAAIXAAYJhgdGGgD8AAAXAAYJhgdGGgD8AAAuAAQKfxYAAhcACQl6FNN4AIcBABcACQl6FNN4AIcBAAAA.Stinkerz:BAAALgAECgIJAgABLgAECgkJIgAYAG0gAA==.Stonegut:BAAALgAECggJDwAAAA==.Stunanddone:BAAALgAECgUJEAAAAA==.Stupidkitty:BAAALgAECgMJAgAAAA==.',
Su='Subrogue:BAABLgAFFH8FAAIjAAIJlhnjMQCWAAAjAAIJlhnjMQCWAAABLgAFFAMJBQAeABkGAA==.Suffragan:BAAALgAECgIJAgAAAA==.Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJEAAAAA==.Supreme:BAACLgAFFH8IAAIWAAMJXhrBXwDQAAAWAAMJXhrBXwDQAAAuAAQKfxkAAhYACAl4I24YAMMCABYACAl4I24YAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAMJAwAAAA==.Swayaim:BAABLgAFFH8LAAIDAAQJEgaDVAD/AAADAAQJEgaDVAD/AAAAAA==.Sweatypits:BAAALgAECgYJBgABLgAFFAMJCgAOABMaAA==.Swordsaint:BAAALgAECgEJAQAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAYJDgARAO8RAA==.Sylphrena:BAACLgAFFH8TAAIHAAUJHxaxGAD3AAAHAAUJHxaxGAD3AAAuAAQKfygAAgcACQlQHogIAMMCAAcACQlQHogIAMMCAAAA.',
['Sí']='Sínful:BAABLgAECn8qAAIEAAkJxB+BBABqAgAEAAkJxB+BBABqAgAAAA==.',
Ta='Tacow:BAAALgAECggJEQAAAA==.Tahwe:BAAALgAECgIJAgAAAA==.Talethen:BAABLgAECn8gAAMiAAkJdRmPMgBqAQAiAAkJ8xePMgBqAQAGAAUJMxgpIAAtAQAAAA==.Talgrin:BAAALgAECgYJBgAAAA==.Talla:BAABLgAECn8oAAIOAAkJKyCtCAAmAwAOAAkJKyCtCAAmAwAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgAECgEJAQABLgAECgYJDAANAAAAAA==.Tellus:BAAALgADCgcJCwAAAA==.Tempesttempi:BAAALgADCgcJBwAAAA==.Tewshort:BAAALgAECgQJCAABLgAFFAQJEAASAB4WAA==.',
Th='Thatbox:BAAALgAECgQJBQAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgUJEQAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAABLgAECn8UAAMTAAgJBAUFXgCfAAAmAAcJQQRZWQDeAAATAAcJQgQFXgCfAAAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thorfyna:BAABLgAECn8kAAIkAAkJRxRRCQDXAQAkAAkJRxRRCQDXAQAAAA==.Threzk:BAABLgAECn8eAAIbAAkJew7/DgBPAQAbAAkJew7/DgBPAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.Thunderstorm:BAAALgAECgcJDAAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8MAAIWAAUJZBMQNABUAQAWAAUJZBMQNABUAQAuAAQKfy8AAhYACQmGIoMLAOsCABYACQmGIoMLAOsCAAAA.Tontiamat:BAABLgAECn89AAMiAAkJXRiiFwAaAgAiAAkJXRiiFwAaAgAGAAYJawo5IAAsAQAAAA==.Tontier:BAABLgAECn8hAAQMAAgJYg7VSABsAQAMAAgJYg7VSABsAQAKAAYJWwo2MAChAAALAAQJSg5hSwB9AAABLgAECgkJPQAiAF0YAA==.Totembeans:BAAALgAECgQJCwAAAA==.Totemshocker:BAECLgAFFH8HAAMQAAQJJAvVEQDXAAAQAAMJfAbVEQDXAAAOAAIJrgQrJABXAAAuAAQKfxYAAxAACAkqGQUXAGACABAACAkqGQUXAGACAA4AAQkBDHPeACoAAAEuAAUUBQkSAAgAiBIA.Toxicshadow:BAAALgADCgQJBgAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAACLgAFFH8OAAIRAAYJ7xGlEQCoAQARAAYJ7xGlEQCoAQAuAAQKfxwABBEACQlOH5QMAMUCABEACAnDHpQMAMUCABIABwksDjq3ABcBABQAAgmgE6FNADgAAAAA.Trashfire:BAACLgAFFH8KAAMHAAQJIA50GQDvAAAHAAQJIA50GQDvAAAhAAIJwgF2FgB7AAAuAAQKfx0ABAcACAkXHSYQAGUCAAcACAkXHSYQAGUCABwABQknFXw2ADkBACEAAwluEWhAAK0AAAEuAAUUBgkOABEA7xEA.Treeple:BAABLgAECn8iAAMMAAkJ5xZvSwBhAQAMAAcJUBNvSwBhAQAFAAUJbA5zQQAIAQAAAA==.Treily:BAAALgAECggJEgAAAA==.Tresleches:BAABLgAECn8rAAISAAkJBhJBXgC1AQASAAkJBhJBXgC1AQAAAA==.Tricket:BAABLgAECn9TAAMjAAkJeCDLAwDtAgAjAAkJeCDLAwDtAgAVAAYJKBl1VAD6AAAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAbAAYIAQ==.Truestorm:BAACLgAFFH8HAAISAAIJGgUrKQBvAAASAAIJGgUrKQBvAAAuAAQKfykAAhIACQnOC0t7AHgBABIACQnOC0t7AHgBAAAA.Truheals:BAAALgAECgYJCgAAAA==.',
Tu='Tuchi:BAACLgAFFH8ZAAMlAAUJCx+8AQAIAQAXAAUJkByVHgBQAQAlAAMJaxy8AQAIAQAuAAQKfyYAAyUABwm9IzoDAPgBABcABwliIrkyAKgCACUABgnQIjoDAPgBAAAA.Tumblestone:BAAALgAECgEJAQAAAA==.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAgJGAAWAH8cAA==.',
['Tà']='Tàcobelle:BAACLgAFFH8HAAIEAAIJoxMeBwChAAAEAAIJoxMeBwChAAAuAAQKfxYAAgQACQnrHm8EAGwCAAQACQnrHm8EAGwCAAEuAAQKCAkpABcA2xcA.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Vaelen:BAAALgAECgEJAQABLgAECgkJGAAfAJUaAA==.Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgANAAAAAA==.Valhalla:BAAALgAECgYJBgAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIOAAMJriKiOgD4AAAOAAMJriKiOgD4AAAuAAQKfzEAAw4ACQllGz8SAIQCAA4ACQllGz8SAIQCABAABgkTGpE2AF8BAAAA.Varanis:BAACLgAFFH8JAAIDAAMJnxZuDAD/AAADAAMJnxZuDAD/AAAuAAQKfxkAAgMACQlkIWMLAOgCAAMACQlkIWMLAOgCAAAA.',
Ve='Vegh:BAACLgAFFH8HAAIkAAMJYBglCQDAAAAkAAMJYBglCQDAAAAuAAQKf04AAiQACQnzH1wDAKoCACQACQnzH1wDAKoCAAAA.Vem:BAABLgAECn8uAAIiAAkJsR1IEABlAgAiAAkJsR1IEABlAgAAAA==.Veriale:BAAALgAECgcJDAAAAA==.Verra:BAABLgAECn85AAISAAkJWhs3JgBrAgASAAkJWhs3JgBrAgAAAA==.',
Vi='Vitriol:BAABLgAECn8hAAIVAAcJZxgwMQCIAQAVAAcJZxgwMQCIAQAAAA==.',
Vo='Voidbeaver:BAAALgAECgcJCwAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAACLgAFFH8OAAMaAAQJoBMWBgAhAQAaAAQJoBMWBgAhAQAbAAEJYQcDKwA8AAAuAAQKfx8AAhoACQl2IqsBAMoCABoACQl2IqsBAMoCAAAA.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgcJEAANAAAAAA==.Vyrros:BAAALgAECgEJAQAAAA==.',
Wa='Walji:BAABLgAECn8eAAMOAAgJyhtyFwBaAgAOAAgJyhtyFwBaAgAQAAEJWwumrwApAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgAECgIJBAAAAA==.Wandy:BAABLgAECn86AAIfAAkJtxo5AgDbAQAfAAkJtxo5AgDbAQAAAA==.Wangstah:BAABLgAECn8cAAIDAAkJMiReDwDVAgADAAkJMiReDwDVAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAIVAAYJNhQUSgB8AQAVAAYJNhQUSgB8AQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJDgAAAA==.Wawatesi:BAAALgAECgMJAwAAAA==.Waytogoteam:BAACLgAFFH8MAAIDAAMJMxzJIACtAAADAAMJMxzJIACtAAAuAAQKfzgAAgMACQkpJJYLAPcCAAMACQkpJJYLAPcCAAAA.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8WAAMXAAcJHBS0KgDJAQAXAAcJHBS0KgDJAQAYAAIJBw4+BQCCAAAuAAQKfzMABBcACQnEJH8NAA4DABcACQk3JH8NAA4DABgABgm+I3wDANkBACUAAQmPIMgWAGQAAAAA.Wenya:BAAALgADCgcJBwAAAA==.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgQJBAAAAA==.',
Wo='Woodyy:BAABLgAECn8oAAIZAAgJcBADBwAoAQAZAAgJcBADBwAoAQAAAA==.Woog:BAAALgAECgcJEgAAAA==.Wox:BAAALgAECgkJEAAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wu='Wujustyle:BAAALgAECgcJBwAAAA==.Wulfgar:BAAALgAFFAEJAQAAAA==.',
Wy='Wyldspirit:BAABLgAECn8lAAIDAAgJQg+QCgARAQADAAgJQg+QCgARAQAAAA==.Wyreless:BAAALgADCgYJBgABLgAECgkJNQAKABUWAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgAECgEJAQAAAA==.',
Xe='Xe:BAAALgAECgYJBgABLgAECgkJUwAjAHggAA==.',
Xr='Xrind:BAAALgADCgEJAQAAAA==.',
Ya='Yaass:BAAALgAECgMJAwAAAA==.',
Ye='Yem:BAACLgAFFH86AAQbAAcJsCBmAgDMAQAbAAYJEiBmAgDMAQAfAAYJOx4EPABcAQAaAAIJYSIrHgBTAAAuAAQKfzYAAxsACQmiIzkGAGwCABsABgncIzkGAGwCAB8ABgliI1VJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAILAAcJvxm2CAAfAgALAAcJvxm2CAAfAgABLgAFFAYJFQASAPQaAA==.Yoverre:BAAALgAECgMJAwAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAANAAAAAA==.Zanzabar:BAABLgAECn8XAAISAAkJvBlHQAAGAgASAAkJvBlHQAAGAgAAAA==.Zaraelitha:BAAALgAECggJDgAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgYJCQAAAA==.Zeodrik:BAABLgAECn8cAAIVAAcJYRmxNQDSAQAVAAcJYRmxNQDSAQAAAA==.',
Zh='Zhenya:BAACLgAFFH8TAAIXAAUJ+hKwYgAdAQAXAAUJ+hKwYgAdAQAuAAQKfycAAxcACQltGJtLAPgBABcACQltGJtLAPgBACUABAkvD+gOANUAAAAA.',
Zi='Zidguard:BAAALgAECgYJBwAAAA==.Zigzauer:BAAALgAECgQJBAAAAA==.Ziroken:BAAALgADCgUJBQAAAA==.',
Zo='Zombeaver:BAAALgAECgMJAwAAAA==.',
Zu='Zuga:BAAALgAECggJCAAAAA==.',
['Ña']='Ñajana:BAAALgADCgcJCAAAAA==.',
['Ôb']='Ôbelix:BAAALgAFFAIJAgAAAA==.',
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
