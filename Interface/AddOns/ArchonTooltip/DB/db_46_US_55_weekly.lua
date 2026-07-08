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

local lookup = {'Rogue-Assassination','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Evoker-Devastation','Priest-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Druid-Restoration','DeathKnight-Unholy','Unknown-Unknown','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Paladin-Holy','Paladin-Retribution','Monk-Windwalker','Paladin-Protection','Warrior-Fury','DemonHunter-Devourer','Mage-Frost','Mage-Fire','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Evoker-Preservation','Monk-Mistweaver','Warlock-Demonology','DemonHunter-Havoc','Priest-Discipline','Evoker-Augmentation','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abracadava:BAAALgAECgQJBQAAAA==.',
Ac='Acheniris:BAAALgAECgUJDQAAAA==.',
Ad='Adeaino:BAAALgAECgUJCAAAAA==.Adonix:BAAALgAECgEJAQAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgUJBwAAAA==.',
Ag='Agrippa:BAACLgAFFH8HAAIBAAQJyQE8CgCaAAABAAQJyQE8CgCaAAAuAAQKfxwAAgEACAmgDo4JAKMBAAEACAmgDo4JAKMBAAAA.',
Ah='Ahndhrez:BAAALgAECgcJBgAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECggJEwAAAA==.Aioli:BAABLgAECn8kAAQCAAkJ1BvVEgARAgACAAkJuRjVEgARAgADAAYJ7hdaRwCUAQAEAAUJcRo4SAAzAQAAAA==.Airwavez:BAAALgAFFAMJAwAAAA==.',
Al='Alchemorph:BAABLgAECn8XAAIFAAgJSwnQPQAYAQAFAAgJSwnQPQAYAQAAAA==.Aldormu:BAABLgAECn8mAAIGAAkJuAx8CgB3AQAGAAkJuAx8CgB3AQAAAA==.Aliyah:BAEALgADCgIJAgABLgAECgkJJgAHAMoZAA==.Allura:BAACLgAFFH8SAAIHAAQJzRGZHADTAAAHAAQJzRGZHADTAAAuAAQKfyQAAgcACQmLGQ4WACwCAAcACQmLGQ4WACwCAAAA.Altra:BAACLgAFFH8TAAMIAAUJDguJEQAHAQAIAAQJDguJEQAHAQAJAAEJAAAdKgAAAAAuAAQKfykAAwgACQl5HFYCAJ8CAAgACQl5HFYCAJ8CAAkABwl7A1orAOQAAAAA.Alyvia:BAAALgADCgEJAgAAAA==.',
Am='Amoeta:BAABLgAECn81AAQKAAkJFRZjDwC/AQAKAAgJ0hVjDwC/AQALAAkJAg6qIABJAQAMAAcJyQg9aQD4AAAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgQJBAAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgAECgIJAwAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angelkinq:BAAALgAECgEJAwABLgAFFAUJCQANAMccAA==.Angryapples:BAAALgAECgQJCQAAAA==.Anilbeedz:BAAALgAECgEJAQAAAA==.Annihilation:BAAALgAECgUJCQAAAA==.Antinous:BAABLgAECn8qAAIEAAgJ3gw6EwArAQAEAAgJ3gw6EwArAQAAAA==.',
Ap='Apathia:BAAALgAECgEJAQABLgAECgYJCAAOAAAAAA==.Aphrodité:BAAALgAECgIJAgAAAA==.',
Ar='Arcstorm:BAAALgAECgYJDwAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Ashenback:BAACLgAFFH8GAAMPAAMJXAqHYgCEAAAPAAMJXAqHYgCEAAAQAAEJkQkKHAA+AAAuAAQKfxkABBAACAl8GlEKABUCABAACAkxGlEKABUCABEAAwn1HoNJAA4BAA8AAgkaGuucAJcAAAEuAAUUBgkOABIA7xEA.Asomyrh:BAABLgAECn8lAAMSAAkJmxUEGgA1AgASAAkJmxUEGgA1AgATAAEJPQHY0wESAAAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgYJCAAAAA==.Atticus:BAAALgADCgkJCQAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgAECgQJCgAAAA==.',
Av='Averyl:BAAALgAECgUJBQAAAA==.Aviendha:BAAALgAECgYJCgAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAIUAAgJLQptKgCKAQAUAAgJLQptKgCKAQAAAA==.',
Az='Azenith:BAABLgAECn8cAAMTAAYJgRx9agCaAQATAAYJgRx9agCaAQAVAAEJrQjGVAAnAAAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bababing:BAAALgADCgEJAQABLgAFFAIJAgAOAAAAAA==.Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bamboozle:BAAALgADCgcJBwAAAA==.Bananer:BAABLgAECn8iAAIWAAkJeBRSIwDZAQAWAAkJeBRSIwDZAQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Bb='Bbqlol:BAAALgAECgYJBwABLgAECgYJHgATAGccAA==.',
Be='Beaugersugar:BAAALgAECgQJBQAAAA==.Beebler:BAABLgAECn8YAAIQAAgJnhfnDgDCAQAQAAgJnhfnDgDCAQAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgAECgcJCAAAAA==.Bennington:BAAALgADCgYJBgAAAA==.Beowulf:BAAALgAECgEJBAAAAA==.Bestt:BAAALgAECgQJCQAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Bigbluenfab:BAAALgAECgIJAgAAAA==.Bigdaddyd:BAAALgAECgIJAgAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigholylady:BAAALgADCgkJCQABLgAFFAUJCQANAMccAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigocagler:BAAALgAECgcJAQAAAA==.Bigolchungus:BAABLgAECn8eAAMVAAkJwRpuCQA7AgAVAAgJeBluCQA7AgATAAUJ6BjFuwAOAQAAAA==.Bigpapadots:BAAALgAECgMJBAAAAA==.Bigpéet:BAAALgAECgMJBwAAAA==.Bigshizz:BAAALgAECgQJBgABLgAECgcJFwAFAAEhAA==.Bippysmasher:BAABLgAECn8kAAIXAAkJaxI1SACuAQAXAAkJaxI1SACuAQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.',
Bl='Blacblood:BAABLgAECn8fAAIIAAkJYRHNBQDSAQAIAAkJYRHNBQDSAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJEQAAAA==.Blindweiss:BAAALgAFFAEJAQABLgAFFAcJFgAYABwUAA==.Blinkies:BAABLgAECn8iAAMZAAkJbSD5AADWAgAZAAkJbSD5AADWAgAYAAUJlg8wvgAMAQAAAA==.Blinkster:BAAALgAECgEJBgAAAA==.Bloodfushion:BAAALgADCgYJBgAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgAECgMJAwAOAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8RAAIDAAcJGRnZEADeAQADAAcJGRnZEADeAQAuAAQKfysAAgMACQmNIycKAAYDAAMACQmNIycKAAYDAAAA.Boolala:BAAALgAECgYJDwABLgAECgkJMgATAIYRAA==.Borstenne:BAACLgAFFH8SAAINAAUJGR3PUQBOAQANAAUJGR3PUQBOAQAuAAQKfykAAg0ACQm7JEoTANQCAA0ACQm7JEoTANQCAAAA.',
Br='Brake:BAACLgAFFH8KAAINAAMJnxFTqwDIAAANAAMJnxFTqwDIAAAuAAQKfyYAAg0ACAlXHvU1AF8CAA0ACAlXHvU1AF8CAAAA.Brese:BAAALgAECgIJAgABLgAFFAUJEwAXAHIZAQ==.Breseayaya:BAACLgAFFH8TAAIXAAUJchlIPwAqAQAXAAUJchlIPwAqAQAuAAQKfy0AAhcACQkrIXcNANkCABcACQkrIXcNANkCAAAA.Breseshh:BAAALgAECgcJEwABLgAFFAUJEwAXAHIZAA==.Brickbeard:BAACLgAFFH8NAAIaAAQJeREOBQA4AQAaAAQJeREOBQA4AQAuAAQKfy0AAxoACQl0Fa0GAA8CABoACQl0Fa0GAA8CABsABwnDDeUZAH0BAAAA.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJEgABLgAFFAgJGQATAJ0cAA==.Bricksquad:BAAALgAECgMJAwABLgAFFAMJBQAXAHodAA==.Brickthrow:BAACLgAFFH8ZAAMTAAgJnRyhHQCSAQATAAYJ1hqhHQCSAQASAAMJOQjULADIAAAuAAQKfzMAAxMACQmsJBgIACsDABMACQmsJBgIACsDABIABQlyBENyAG4AAAAA.Bronkle:BAAALgAECgUJBQABLgAFFAQJDQAaAHkRAA==.',
Bu='Buhleed:BAAALgAECgIJAgAAAA==.Burgerburn:BAAALgAECgUJBgAAAA==.',
By='Bytheway:BAABLgAECn8WAAIcAAgJ4RN8LgBnAQAcAAgJ4RN8LgBnAQAAAA==.',
['Bà']='Bàbÿ:BAAALgAECgcJDgAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAACLgAFFH8TAAIMAAUJPxBgMADvAAAMAAUJPxBgMADvAAAuAAQKfzEABAwACQm4I8cIACsDAAwACQm4I8cIACsDAAUAAglbGzx8AE4AAAsAAQlKAac3ABkAAAAA.Cadsune:BAAALgAECgYJDAAAAA==.Caelesti:BAABLgAECn8pAAMHAAkJXRMfIADCAQAHAAgJVxMfIADCAQAcAAkJSBacJgCYAQAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAgAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQABLgAFFAgJHAAdAG8YAA==.Cheapshotjoe:BAAALgAECgEJAQAAAA==.Chelbur:BAAALgADCgEJAQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chosmuke:BAAALgAECgEJAwAAAA==.Chowderhead:BAABLgAECn8UAAIbAAYJYxzhDgDcAQAbAAYJYxzhDgDcAQAAAA==.',
Ci='Cileb:BAACLgAFFH8GAAIYAAUJSBipYAAgAQAYAAUJSBipYAAgAQAuAAQKfzUAAhgACQmkJAIMABkDABgACQmkJAIMABkDAAAA.Civik:BAABLgAECn9KAAIDAAkJciOICQAMAwADAAkJciOICQAMAwAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAFFAMJBQAXAHodAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAACLgAFFH8XAAITAAUJYhpZEwAaAQATAAUJYhpZEwAaAQAuAAQKfzAAAhMACQldGl89AA8CABMACQldGl89AA8CAAAA.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAFFAQJBQAXAAkFAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJJwAJAAkjAA==.Copperit:BAABLgAECn8nAAIJAAkJCSOQAgBDAwAJAAkJCSOQAgBDAwAAAA==.Coreroot:BAAALgAECgEJAQAAAA==.Cornburglar:BAACLgAFFH8VAAIWAAQJkSJOBgBoAQAWAAQJkSJOBgBoAQAuAAQKfzoAAhYACAlcJXAIANkCABYACAlcJXAIANkCAAAA.Cowtaclysmic:BAACLgAFFH8FAAINAAIJOgfN3wCFAAANAAIJOgfN3wCFAAAuAAQKfyMAAw0ACAkGE6SAAGIBAA0ACAmaDKSAAGIBAAkABQlKFmoqAAUBAAAA.',
Cr='Crackersz:BAABLgAECn8WAAMPAAcJHQgMigDHAAAPAAcJHQgMigDHAAARAAMJGATNhwBgAAAAAA==.Cranjis:BAABLgAECn9WAAIeAAkJASJnBwAoAwAeAAkJASJnBwAoAwAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Crunchwrap:BAABLgAECn8qAAIFAAkJDA8LJwCWAQAFAAkJDA8LJwCWAQAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgcJBwAAAA==.',
Cu='Curadora:BAAALgADCgQJBAAAAA==.Cursereflect:BAABLgAECn8iAAMfAAkJyQ7fUwCgAQAfAAkJyQ7fUwCgAQAbAAEJAADNVgAAAAAAAA==.Curseus:BAAALgAECgIJBQAAAA==.',
Cy='Cyberwin:BAAALgAECgEJAQAAAA==.',
['Câ']='Câlisse:BAAALgAFFAEJAQAAAA==.',
Da='Damncats:BAACLgAFFH8GAAIWAAMJVwsFHACBAAAWAAMJVwsFHACBAAAuAAQKf0cAAhYACQkTE78DAHMBABYACQkTE78DAHMBAAAA.Dandinn:BAAALgAECgYJCQAAAA==.Danielsboone:BAABLgAECn8mAAIDAAkJtA+3CgBJAQADAAkJtA+3CgBJAQAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJCAABLgAFFAUJDQARAMMMAA==.Darknemesis:BAAALgAECgYJDQAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAFFAIJAwABLgAFFAcJOgAbALAgAA==.',
De='Deadhippocow:BAABLgAECn8cAAIMAAgJkR3jLAD0AQAMAAgJkR3jLAD0AQAAAA==.Deathwavez:BAACLgAFFH8ZAAINAAUJqhNpLQDmAAANAAUJqhNpLQDmAAAuAAQKfxoAAg0ABwkwFwFlAMUBAA0ABwkwFwFlAMUBAAAA.Declän:BAAALgAECgQJBgABLgAECggJHAAMAJEdAA==.Decurse:BAABLgAECn8kAAIfAAkJ+hTPPADoAQAfAAkJ+hTPPADoAQAAAA==.Degrono:BAAALgAECgQJBAAAAA==.Deldrin:BAABLgAECn8mAAIYAAkJERSJUADqAQAYAAkJERSJUADqAQAAAA==.Demayy:BAABLgAECn8uAAIeAAkJKxNWIwAFAgAeAAkJKxNWIwAFAgAAAA==.Demona:BAACLgAFFH8MAAMfAAUJAwwHYQAGAQAfAAQJAwwHYQAGAQAaAAIJkgdYLAA9AAAuAAQKfyUAAxsACAkxGe4pABoBAB8ABwnIFQl4AEkBABsABAngE+4pABoBAAAA.Demonix:BAABLgAECn8YAAIfAAgJlRoeNgABAgAfAAgJlRoeNgABAgAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAACLgAFFH8LAAIYAAQJdwckcQD/AAAYAAQJdwckcQD/AAAuAAQKfzoAAhgACQm/D19XANcBABgACQm/D19XANcBAAAA.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAABLgAECn8eAAMTAAYJZxxweQB7AQATAAYJZxxweQB7AQASAAIJsAQDhABDAAAAAA==.Dinobrass:BAACLgAFFH8FAAMEAAMJHgLlJwBuAAAEAAMJHgLlJwBuAAADAAEJ5QM1YAA9AAAuAAQKfyMAAgQACAm0DXMRAEQBAAQACAm0DXMRAEQBAAAA.Dirktheshiny:BAAALgAECgkJDwABLgAECgkJPQAFAIEbAA==.Dirtylöbster:BAACLgAFFH8OAAIYAAMJTCHYJwAUAQAYAAMJTCHYJwAUAQAuAAQKfzUAAhgACQkKJb0JACwDABgACQkKJb0JACwDAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgYJEQABLgAECgYJHgATAGccAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAABLgAECn8UAAIFAAgJpxfbLgBlAQAFAAgJpxfbLgBlAQAAAA==.Dorfydorf:BAAALgAECgEJAgAAAA==.Dorose:BAAALgAECgEJAgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Dranight:BAAALgAECgcJBwABLgAECgkJSgADAHIjAA==.Dreats:BAAALgAECgYJCwAAAA==.Drewmee:BAABLgAECn8YAAITAAkJHgkPkQBQAQATAAkJHgkPkQBQAQAAAA==.Dronar:BAABLgAFFH8FAAIPAAUJCgk3LwAlAQAPAAUJCgk3LwAlAQABLgAECgkJIwALAAEgAA==.Drublood:BAAALgAECgcJCwABLgAECgkJGAATAB4JAA==.Drunkinmasta:BAAALgAECgEJAQABLgAFFAQJEAATAB4WAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Duckbeak:BAAALgADCgUJCwAAAA==.Dune:BAAALgADCgcJBwAAAA==.Duwork:BAABLgAECn8XAAIFAAcJASHkHADhAQAFAAcJASHkHADhAQAAAA==.',
['Dæ']='Dæmona:BAABLgAECn8VAAIgAAkJmxLTFQDeAQAgAAkJmxLTFQDeAQAAAA==.',
Eb='Ebk:BAAALgAECgcJDAAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
Ei='Eight:BAAALgADCggJGAAAAA==.',
El='Eladus:BAAALgAECgcJEAAAAA==.Elemnt:BAABLgAECn8UAAMRAAcJXRC2BAA8AQARAAcJXRC2BAA8AQAPAAYJWg/eZQAqAQABLgAFFAQJEAATAB4WAA==.Elesus:BAAALgAECggJDQABLgAECgkJQwAhAJUhAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJDgAAAA==.Emrys:BAAALgAECgMJAgAAAA==.',
En='Enhshaman:BAACLgAFFH8FAAIeAAMJGQajRQCNAAAeAAMJGQajRQCNAAAuAAQKfxYAAh4ACQn+FDYkAP8BAB4ACQn+FDYkAP8BAAAA.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.Evilinne:BAAALgADCgIJAgAAAA==.Evânescence:BAAALgAECgEJAQAAAA==.',
Ex='Excaliburn:BAAALgAECgEJBQAAAA==.',
Ez='Ezekial:BAAALgAECgQJBAAAAA==.Ezkal:BAACLgAFFH8UAAINAAUJGxzFaAAoAQANAAUJGxzFaAAoAQAuAAQKfywAAw0ACQnsGaEYAOgCAA0ACQnsGaEYAOgCAAkABgktFW0rAP4AAAAA.',
Fa='Faithastray:BAAALgAECgMJAwAAAA==.Faithpasse:BAABLgAECn8/AAMeAAkJlR69AgD6AQAeAAkJlR69AgD6AQAUAAEJ9gPfhgApAAAAAA==.Falcorne:BAABLgAECn80AAIDAAkJqiIRCAAbAwADAAkJqiIRCAAbAwAAAA==.Fatlipz:BAABLgAECn8iAAIhAAcJdQ/IBABKAQAhAAcJdQ/IBABKAQAAAA==.Fay:BAAALgADCgEJAQABLgAECgYJCAAOAAAAAA==.',
Fe='Felondar:BAACLgAFFH8FAAIgAAIJ/QUuDwBxAAAgAAIJ/QUuDwBxAAAuAAQKfygAAyAACQkUEfQFAOYAACAACQkUEfQFAOYAABcABgmwBLObAOEAAAAA.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8ZAAMJAAkJhBsxDABOAgAJAAcJsBsxDABOAgANAAgJvhiIagC3AQAAAA==.',
Fi='Finnadin:BAABLgAECn8qAAITAAkJzx9dGQCrAgATAAkJzx9dGQCrAgAAAA==.Finns:BAAALgAECgcJEQAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAABLgAECn8dAAIDAAgJ0xnyOQD3AQADAAgJ0xnyOQD3AQAAAA==.Fistinfred:BAAALgADCgMJAwAAAA==.Fistobeef:BAAALgAECgEJAQABLgAECgIJAgAOAAAAAA==.',
Fl='Fleable:BAAALgAECgQJAwAAAA==.Flysky:BAACLgAFFH8cAAIdAAgJbxiMBQB0AgAdAAgJbxiMBQB0AgAuAAQKfywABB0ACQnFI4kCAEcDAB0ACQnFI4kCAEcDACIACAnIJF4HAOICAAYAAQl3DyBBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECggJDQAAAA==.',
Fr='Freakmeout:BAAALgAECgQJBAAAAA==.Freshpot:BAAALgAECgMJAwAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgAECgEJAQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJDgABLgAFFAUJFAANABscAA==.Futuredragoo:BAAALgAECgcJDAABLgAFFAUJFAANABscAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Fy='Fyska:BAAALgADCgEJAQAAAA==.',
Ga='Gabriella:BAAALgAECgYJDAAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQAOAAAAAA==.Galnannix:BAAALgAECgkJEAAAAA==.Gardrake:BAABLgAECn8zAAMiAAkJrBn5EABeAgAiAAkJrBn5EABeAgAdAAcJqhCrHQCWAQAAAA==.Gastapha:BAABLgAECn8ZAAIXAAkJ0wZoigAMAQAXAAkJ0wZoigAMAQAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMWAAgJCxMcMADvAQAWAAgJCxMcMADvAQAjAAEJAAD2jwAAAAAAAA==.Gehennas:BAABLgAFFH8FAAIXAAMJeh2+UwDzAAAXAAMJeh2+UwDzAAAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Gi='Girnahuma:BAAALgAECgEJAQAAAA==.',
Go='Goku:BAAALgAFFAIJAgAAAA==.Goofykirby:BAAALgADCgcJFQAAAA==.Googoo:BAABLgAECn8UAAINAAkJrhNCOgAXAgANAAkJrhNCOgAXAgAAAA==.Googoogagaa:BAACLgAFFH8MAAIcAAQJkhAXHQAHAQAcAAQJkhAXHQAHAQAuAAQKf0YAAxwACQkKHnMNAH0CABwACQkKHnMNAH0CAAcABwnyEgMqAKIBAAAA.Gotlieb:BAAALgAECggJCgAAAA==.',
Gr='Grenno:BAAALgAECgcJBwABLgAFFAgJIAANANsaAA==.Greystorm:BAAALgAECgIJAgAAAA==.Greythorn:BAAALgADCgkJCQABLgAECgkJSgADAHIjAA==.Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQAOAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8lAAMEAAkJmBJYBwCnAQAEAAkJmBJYBwCnAQACAAUJVA1bFwAXAQAuAAQKfxQAAgQABwkJJOIRAKoCAAQABwkJJOIRAKoCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hakarren:BAAALgAECgYJDAAAAA==.Hakosuka:BAAALgADCgEJAQAAAA==.Hamatza:BAAALgAECgEJAgAAAA==.Hammerinfred:BAAALgAECgUJCwAAAA==.Hawkmoon:BAAALgAECgEJBAAAAA==.',
He='Healingisfun:BAAALgAECgMJBAAAAA==.Helhunter:BAABLgAECn8yAAIXAAkJbRL9RwCuAQAXAAkJbRL9RwCuAQAAAA==.Hellock:BAAALgAFFAEJAQAAAA==.',
Hi='Hippayman:BAAALgAECgQJBAAAAA==.Hippysmasher:BAAALgAECgIJAgABLgAECgkJJAAXAGsSAA==.',
Ho='Hodgepodge:BAAALgAECgEJAgAAAA==.Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgMJBQAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holybob:BAAALgAECgQJCAAAAA==.Holyhooters:BAABLgAECn87AAITAAkJ2yFiDwDrAgATAAkJ2yFiDwDrAgAAAA==.Holypablo:BAAALgAECgQJBgABLgAECgkJUQAhAMEfAA==.Homefries:BAAALgADCgYJBgABLgAECggJHAAMAJEdAA==.Honkytonk:BAABLgAECn8aAAMGAAgJKQtAIgAYAQAGAAYJ7QlAIgAYAQAiAAcJeAmsOAATAQAAAA==.Honor:BAAALgAECgcJDAABLgAECgkJOwATAI8jAA==.Honour:BAABLgAECn87AAITAAkJjyMgDgD0AgATAAkJjyMgDgD0AgAAAA==.',
Hr='Hrathdemon:BAACLgAFFH8SAAIXAAUJlxfSQAAlAQAXAAUJlxfSQAAlAQAuAAQKfysAAhcACQntIPMQALoCABcACQntIPMQALoCAAAA.Hrathid:BAAALgADCgUJDAABLgAFFAUJEgAXAJcXAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8KAAITAAMJiiBUEgATAQATAAMJiiBUEgATAQAuAAQKfywAAhMACQnqI7oFAHIDABMACQnqI7oFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAABLgAECn8aAAMTAAkJNxyILwBDAgATAAkJNxyILwBDAgASAAIJWwcbhgA/AAAAAA==.',
Ib='Ibleedorange:BAAALgAECggJDQAAAA==.',
Ic='Icehawk:BAAALgAECgMJBgAAAA==.Ickeetard:BAABLgAECn8eAAMhAAkJUhJ5MQBWAQAhAAcJFA95MQBWAQAHAAYJsxGzQADqAAAAAA==.',
Id='Idiot:BAAALgAECgMJBAAAAA==.Idiotbreath:BAABLgAECn82AAMiAAkJFSCxCADLAgAiAAkJFSCxCADLAgAGAAMJmQmDMACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgAECgEJAgAAAA==.',
Ig='Ignitus:BAAALgAECgQJBAAAAA==.',
Im='Immorlich:BAAALgAECgEJAQAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJCQAAAA==.Inflexi:BAACLgAFFH8LAAIDAAQJyRT3OgA3AQADAAQJyRT3OgA3AQAuAAQKfy0AAwMACQlqIFYNAOgCAAMACQmYH1YNAOgCAAQACAnKGvAYAGQCAAAA.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAABLgAECn8YAAIUAAYJWhmmLwBKAQAUAAYJWhmmLwBKAQAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn8/AAQMAAkJIB5zDgDjAgAMAAkJIB5zDgDjAgAFAAgJFyDpFAAqAgALAAMJ2hZXOQDAAAAAAA==.',
Iv='Iver:BAAALgAECgUJBgABLgAECgcJEQAOAAAAAA==.',
Ja='Jaliano:BAAALgADCgYJBgABLgAECgkJLgAPAJkXAA==.Jangle:BAAALgADCgYJBwAAAA==.',
Je='Jeffblades:BAAALgAECgcJEAAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJBgAOAAAAAA==.',
Jj='Jjooaacchhim:BAAALgAECgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8jAAIDAAkJfBt2LQAnAgADAAkJfBt2LQAnAgAAAA==.',
Ka='Kadillac:BAABLgAECn8WAAIkAAcJUQgjLgDMAAAkAAcJUQgjLgDMAAAAAA==.Kaelira:BAAALgADCgIJAgAAAA==.Kairei:BAAALgAECggJDwAAAA==.Kakashi:BAAALgADCgEJAQAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAACLgAFFH8VAAITAAYJ9BpDKQBnAQATAAYJ9BpDKQBnAQAuAAQKfyEAAxMACQl1ItwRANkCABMACQkUItwRANkCABUABQnrH7IDAAUBAAAA.Katalina:BAABLgAECn8wAAMlAAgJmBHLDQB2AQAlAAgJmBHLDQB2AQAgAAYJpwsROAAlAQAAAA==.Kawer:BAAALgAECgQJCQAAAA==.Kawnzerker:BAAALgADCgkJCQAAAA==.',
Ke='Keilanis:BAAALgAECgIJAgAAAA==.Kelstormhoof:BAAALgADCgcJFgABLgAECgYJDQAOAAAAAA==.Kernel:BAAALgAECgEJAQABLgAFFAQJFQAWAJEiAA==.',
Kh='Kham:BAACLgAFFH8VAAIWAAUJLhsiGQBOAQAWAAUJLhsiGQBOAQAuAAQKf0QAAhYACQlgJMYDACsDABYACQlgJMYDACsDAAAA.Khäléési:BAAALgAECgEJAQAAAA==.',
Ki='Kialla:BAAALgAECgIJAgABLgAECgkJKAAPACsgAA==.Killmaim:BAABLgAECn8ZAAIWAAgJwRllIABPAgAWAAgJwRllIABPAgAAAA==.Kitsuko:BAABLgAECn80AAMPAAkJFg+2PgCzAQAPAAkJFg+2PgCzAQARAAkJxRDNLACRAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ko='Kokeovrdose:BAAALgAECgQJBAABLgAECgYJFAAYAAYWAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuli:BAAALgAECgEJAgAAAA==.Kuraishin:BAAALgAFFAEJAQABLgAFFAcJFgAYABwUAA==.Kuvare:BAAALgAECgMJAwAAAA==.',
['Kå']='Kårmå:BAAALgADCgUJBQAAAA==.',
['Kè']='Kèlton:BAAALgAECgUJCgAAAA==.',
La='Lanas:BAEALgAECgkJAwABLgAFFAUJFQATACMRAA==.Laocoon:BAAALgAECggJCAABLgAECgkJOwATANshAA==.Lavashiza:BAAALgAECgYJEwAAAA==.Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAABLgAECn8UAAIDAAgJThKxfABGAQADAAgJThKxfABGAQAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAgAAAA==.Leedaddydk:BAAALgAECgQJCgAAAA==.Leeoflight:BAAALgADCgEJAQAAAA==.Leroyjenkins:BAABLgAECn8XAAImAAcJ8BvoAgBVAgAmAAcJ8BvoAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.Letsbeef:BAAALgAECgEJAQABLgAECgIJAgAOAAAAAA==.',
Li='Lightstorm:BAAALgAECgYJEAAAAA==.Linaria:BAAALgAECgYJCgAAAA==.Linø:BAAALgAECgIJAgAAAA==.Lissara:BAABLgAECn8ZAAIiAAgJExBPNABiAQAiAAgJExBPNABiAQAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAACLgAFFH8TAAInAAUJqRyjGgBQAQAnAAUJqRyjGgBQAQAuAAQKfyMAAicACQnCHEIOAFUCACcACQnCHEIOAFUCAAAA.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockednabyss:BAAALgAECgQJBAABLgAECgkJOQAoAD0kAA==.Lockmogged:BAAALgAFFAIJAgAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECgkJHAADADIkAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAFFAQJDgAaAKATAA==.Luminouslexi:BAAALgAECgMJAwAAAA==.',
Ma='Macoub:BAACLgAFFH8FAAIXAAQJCQUSYADPAAAXAAQJCQUSYADPAAAuAAQKfxcABCAACAnFFZonAD4BACAABgl2FZonAD4BABcABAmMGrebAOoAACUAAwluB5YxAD0AAAAA.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAABLgAECn8ZAAMbAAgJfQU9GwDLAAAbAAgJUQU9GwDLAAAfAAQJzAOX/gBqAAAAAA==.Maebell:BAAALgAECgYJDAABLgAECgYJHgATAGccAA==.Mageslayer:BAABLgAECn8bAAMoAAgJmxPjHgCfAQAoAAgJGBLjHgCfAQABAAMJPRCNGACtAAAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magicstorm:BAAALgAECgcJBwAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgAOAAAAAA==.Magrun:BAAALgAECgUJBgAAAA==.Mahalleinr:BAAALgAECgEJAQAAAA==.Maiggee:BAAALgAECgEJAgAAAA==.Makkideez:BAABLgAECn8UAAIoAAkJOBhVEAApAgAoAAkJOBhVEAApAgAAAA==.Makkii:BAAALgADCgEJAQABLgAECgkJFAAoADgYAA==.Malanara:BAAALgADCgEJAQABLgAECgkJJgAYABEUAA==.Malxt:BAAALgADCgYJBwAAAA==.Manabuns:BAABLgAECn8sAAIYAAgJNRg7XgDEAQAYAAgJNRg7XgDEAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8lAAITAAkJ/RRKQgAeAgATAAkJ/RRKQgAeAgAAAA==.Markruffalo:BAAALgAECgYJDAAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn86AAIWAAkJaBu9FABKAgAWAAkJaBu9FABKAgAAAA==.',
Mc='Mckay:BAAALgAECggJEwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8mAAImAAgJRBSzBACjAQAmAAgJRBSzBACjAQAAAA==.Megapunk:BAAALgAECgcJEwAAAA==.Mellmaan:BAAALgAFFAIJAgAAAA==.Melys:BAAALgAECgcJEgAAAA==.Meteorite:BAAALgAECgYJCQAAAA==.Meudayr:BAABLgAECn8jAAILAAkJASBxBADRAgALAAkJASBxBADRAgAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.Mezagog:BAAALgAECgYJDwAAAA==.',
Mi='Mikehammer:BAAALgADCgcJFQAAAA==.Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAACLgAFFH8NAAIRAAUJwww5KwDoAAARAAUJwww5KwDoAAAuAAQKfx4AAhEACAltHCISAJICABEACAltHCISAJICAAAA.Mittenss:BAAALgADCgIJAgAAAA==.',
Mo='Moistblanket:BAAALgAECgUJBwAAAA==.Mojorisin:BAABLgAECn8jAAICAAkJ6xoUDgBHAgACAAkJ6xoUDgBHAgAAAA==.Moobear:BAAALgAFFAIJAgAAAA==.Moonchiken:BAAALgAECgEJCgAAAA==.Moozlock:BAABLgAECn8rAAIfAAkJEhKNTQCyAQAfAAkJEhKNTQCyAQAAAA==.Moscovio:BAAALgAFFAIJBAABLgAFFAMJBQATAC4MAA==.Mosspaws:BAABLgAECn82AAMMAAkJbiTQBgBLAwAMAAkJbiTQBgBLAwAFAAQJZB8ONgA+AQAAAA==.',
Mt='Mtndewyou:BAAALgAECgcJEQAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.Mutterutters:BAAALgAECgEJAgAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.Myrollin:BAAALgAECgIJAgAAAA==.Myrothan:BAAALgAECgQJBAAAAA==.',
Na='Naetara:BAAALgADCgEJAQAAAA==.Narfiy:BAAALgADCgEJAQAAAA==.Narisanna:BAAALgAFFAEJAgAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBgAAAA==.',
Nm='Nme:BAABLgAECn8lAAMYAAkJoBAOXADKAQAYAAkJoBAOXADKAQAmAAYJiw9LCQBWAQAAAA==.',
No='Nocturnos:BAACLgAFFH8HAAIfAAMJ/RNbcwDaAAAfAAMJ/RNbcwDaAAAuAAQKfzIAAx8ACQlLIEQbAIACAB8ACQlLIEQbAIACABoAAgn3IOguAGIAAAAA.Noctyr:BAAALgAECgcJCAAAAA==.Noggin:BAABLgAECn8rAAMSAAkJRyH/BAAcAwASAAkJRyH/BAAcAwATAAgJ/BCGagCaAQAAAA==.Nonform:BAABLgAECn89AAQFAAkJgRvRDACKAgAFAAkJgRvRDACKAgAKAAEJwRXwTAA/AAAMAAEJdAED7AAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECggJIgAXAH0WAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQAOAAAAAA==.Novamancer:BAAALgAECgIJAgAAAA==.Noxta:BAAALgAECggJEgAAAA==.',
Nu='Numonixx:BAACLgAFFH8hAAMGAAYJ7A6ZBgDqAAAiAAYJCA2iKQAiAQAGAAQJKwuZBgDqAAAuAAQKfzoAAwYACQkFH4oCAJMCAAYACAmsIIoCAJMCACIACAnGG0IUADsCAAAA.Nutlessfred:BAAALgAECgEJAQAAAA==.',
Ny='Nymage:BAABLgAECn9dAAIYAAkJORuiKgBvAgAYAAkJORuiKgBvAgAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogkushe:BAAALgAECgMJAwAAAA==.Ogmund:BAAALgAECgcJEgAAAA==.',
Oh='Ohnospiders:BAABLgAECn8yAAMNAAkJpBfNNAAsAgANAAkJpBfNNAAsAgAIAAQJ4RRYIQDDAAAAAA==.Ohpig:BAAALgAECgMJAwAAAA==.',
Ok='Okaerisan:BAABLgAECn8XAAIVAAkJoRZmFQB8AQAVAAkJoRZmFQB8AQAAAA==.',
Ol='Olord:BAAALgAFFAIJAgAAAA==.',
Om='Omarcuthlink:BAAALgAECgEJAQABLgAFFAQJDQAaAHkRAA==.Omgbbqq:BAAALgAECggJCAABLgAFFAMJDgADADMcAA==.',
On='Onilecram:BAAALgAECgIJAwAAAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.Oomkin:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECggJEQAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Os='Ostie:BAAALgAFFAEJAQAAAA==.',
Ou='Outlast:BAACLgAFFH8QAAITAAQJHhYZOwA1AQATAAQJHhYZOwA1AQAuAAQKfy8AAhMACQm1HbQRAAQDABMACQm1HbQRAAQDAAAA.',
Pa='Paants:BAABLgAECn8kAAIkAAkJugwEHwA7AQAkAAkJugwEHwA7AQAAAA==.Pacid:BAAALgAECgYJDAAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Pakal:BAAALgAECgQJCAAAAA==.Palebull:BAAALgADCgYJCAAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8YAAIXAAgJfxxMCgB1AgAXAAgJfxxMCgB1AgAuAAQKfzMAAhcACQkEJZQEAD0DABcACQkEJZQEAD0DAAAA.Paracotos:BAAALgADCgUJBQAAAA==.Parmageddon:BAAALgAFFAEJAQABLgAFFAQJDgAkAPggAA==.Parmigiano:BAAALgADCgEJAQABLgAFFAQJDgAkAPggAA==.Parmrageiano:BAABLgAFFH8OAAIkAAQJ+CAHDQBdAQAkAAQJ+CAHDQBdAQAAAA==.Parms:BAABLgAECn8ZAAQCAAgJ+xNBJgBrAQACAAgJ6xFBJgBrAQAEAAYJhQxETQAcAQADAAIJORANowCFAAABLgAFFAQJDgAkAPggAA==.Parmy:BAAALgAECgEJAQAAAA==.Pastry:BAABLgAFFH8FAAINAAMJBxTTLQDkAAANAAMJBxTTLQDkAAABLgAFFAcJDAARAMISAA==.',
Pe='Peanought:BAABLgAECn8qAAMIAAkJjxYBBgDJAQAIAAgJsRcBBgDJAQANAAkJ5A4UYQCnAQAAAA==.Peidro:BAABLgAECn8bAAITAAcJAA9GqAArAQATAAcJAA9GqAArAQAAAA==.Pentacles:BAABLgAECn8tAAILAAkJsCA5BwCDAgALAAkJsCA5BwCDAgAAAA==.',
Pi='Pijak:BAABLgAECn8UAAIVAAgJuRTaGwA4AQAVAAgJuRTaGwA4AQAAAA==.Pinkpaw:BAABLgAECn8iAAQLAAkJFh/EBADJAgALAAkJFh/EBADJAgAMAAUJthqjSABsAQAKAAEJuBKESgBEAAAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8JAAMnAAMJ3iTvCABGAQAnAAMJ3iTvCABGAQAUAAEJlCPlOABjAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCQAnAN4kAA==.Postscalone:BAAALgAECgYJBwAAAA==.Potatoes:BAABLgAECn8VAAMbAAgJBgiWHABpAQAbAAgJBgiWHABpAQAfAAIJCQJIFAE6AAAAAA==.',
Pr='Pruflas:BAABLgAECn8aAAINAAgJZAtAjgBJAQANAAgJZAtAjgBJAQAAAA==.',
Ps='Psycodk:BAACLgAFFH8JAAINAAUJxxztSwBaAQANAAUJxxztSwBaAQAuAAQKfxYAAg0ACAmYGD9sAI0BAA0ACAmYGD9sAI0BAAAA.',
Pu='Puffdaddie:BAAALgAECgUJBwABLgAECggJJwATAMkfAA==.Pumpin:BAABLgAECn8XAAIUAAUJFCTFKgBnAQAUAAUJFCTFKgBnAQAAAA==.Punkthor:BAAALgAECgIJAgAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
['Pä']='Päcid:BAAALgAECgYJCQAAAA==.',
Qk='Qkn:BAAALgAECgUJEwAAAA==.',
Qu='Quickswipe:BAABLgAFFH8GAAIoAAMJxSAgIgAVAQAoAAMJxSAgIgAVAQABLgAFFAcJOgAbALAgAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgYJCwABLgAECgcJCQAOAAAAAA==.Ralee:BAAALgAECgEJAQAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Rastabution:BAAALgAECgkJAQAAAA==.Ratoncita:BAAALgAECgEJAwAAAA==.Raynne:BAAALgAECgIJAgAAAA==.Rayzee:BAAALgADCgUJBQAAAA==.',
Re='Reaperjoe:BAAALgAFFAEJAgAAAA==.Rehab:BAACLgAFFH8JAAITAAMJRRvBGgDvAAATAAMJRRvBGgDvAAAuAAQKfxUAAhMACQlbHK4vAGQCABMACQlbHK4vAGQCAAAA.Rehna:BAAALgAECgYJBgABLgAFFAQJEgAHAM0RAA==.Rek:BAAALgAECgEJAQABLgAECgkJIwALAAEgAA==.Rektributio:BAACLgAFFH8eAAITAAgJCyDCBACYAgATAAgJCyDCBACYAgAuAAQKfzcAAhMACQkgJecGADgDABMACQkgJecGADgDAAAA.Restø:BAAALgAECgEJAQAAAA==.Resurection:BAAALgAECgYJDQAAAA==.Revalation:BAACLgAFFH8GAAIMAAMJERUaEQCxAAAMAAMJERUaEQCxAAAuAAQKfycAAgwACQlSH9wVAJoCAAwACQlSH9wVAJoCAAAA.Revenancer:BAAALgAECgEJAwAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgAOAAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Riachu:BAAALgAECgIJAQAAAA==.Ribeyejoe:BAAALgADCgEJAQAAAA==.Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAACLgAFFH8IAAMWAAMJ5xllFQC4AAAWAAMJNRllFQC4AAAkAAIJlxhkIQCNAAAuAAQKfzEAAxYACQmEHx8WAD4CABYACAl2IB8WAD4CACQACAkJF+ESAL4BAAAA.Roadtrip:BAAALgAECgMJBAAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJBAAAAA==.Rockiden:BAAALgADCgEJAQAAAA==.Rottingslow:BAABLgAFFH8IAAIHAAMJ9wDZKwBpAAAHAAMJ9wDZKwBpAAABLgAFFAkJIgAJAAUgAA==.',
Sa='Sanford:BAAALgAECgUJBQAAAA==.Saragos:BAAALgADCgcJBgABLgAFFAcJFgAYABwUAA==.Satine:BAAALgAECgMJAwAAAA==.Saucerdote:BAABLgAECn8eAAMhAAkJmBWxHwDQAQAhAAcJGxexHwDQAQAcAAkJFAlhMQBWAQAAAA==.Saucy:BAAALgAECgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAcJFgAYABwUAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAACLgAFFH8KAAIXAAUJ9RJpTAAFAQAXAAUJ9RJpTAAFAQAuAAQKfysAAhcACQl7H6kPAMYCABcACQl7H6kPAMYCAAAA.Selkie:BAABLgAECn8rAAIQAAkJEBA5DgDMAQAQAAkJEBA5DgDMAQAAAA==.Seragosa:BAAALgAFFAEJAQABLgAFFAcJFgAYABwUAA==.',
Sh='Shakakhan:BAAALgAECgYJDQABLgAECgYJHgATAGccAA==.Shambeau:BAAALgADCgQJBAAAAA==.Shamrun:BAAALgADCgQJBQAAAA==.Shamshielder:BAECLgAFFH8SAAQIAAUJiBJPEQAKAQAIAAQJZwpPEQAKAQAJAAMJihivOQBPAAANAAIJMgcycgBIAAAuAAQKfy0ABAkACQmZI5cFAM0CAAkACQmZI5cFAM0CAAgABgmlGxwOAJQBAA0AAQm5CXeNASkAAAAA.Shapper:BAAALgAECgQJBgAAAA==.Sharick:BAAALgAECgQJBQAAAA==.Shawdrake:BAAALgAECgEJAQABLgAFFAMJBwARABoCAA==.Shawlee:BAACLgAFFH8HAAMRAAMJGgJjHgBfAAARAAIJ9QJjHgBfAAAPAAMJJQL3NgBIAAAuAAQKfy0AAw8ACAnMECRcAEkBAA8ACAnMECRcAEkBABEACAk7CnVWAOEAAAAA.Sheezie:BAACLgAFFH8KAAIPAAMJExrdPADwAAAPAAMJExrdPADwAAAuAAQKf0kAAw8ACQmkIVoFAF0DAA8ACQmkIVoFAF0DABAACQnfGDULAAQCAAAA.Shellcow:BAAALgAECgYJBgABLgAECgkJIgAZAG0gAA==.Shellter:BAAALgAECgEJAgABLgAECgkJIgAZAG0gAA==.Shellwit:BAAALgAECgMJBgABLgAECgkJIgAZAG0gAA==.Sheph:BAAALgAFFAEJAQAAAA==.Shetmage:BAACLgAFFH8XAAIYAAcJdwvUNQCSAQAYAAcJdwvUNQCSAQAuAAQKfykAAhgACQnDIAEkAI0CABgACQnDIAEkAI0CAAAA.Shettdh:BAAALgAECgUJCQAAAA==.Shettrah:BAABLgAECn8UAAIFAAYJ+hoeKwB8AQAFAAYJ+hoeKwB8AQABLgAFFAcJFwAYAHcLAA==.Shienro:BAAALgAECgQJBAABLgAECgQJCQAOAAAAAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAABLgAECn8oAAITAAkJOhRKYACwAQATAAkJOhRKYACwAQAAAA==.Shuck:BAAALgAECgQJBAABLgAFFAQJFQAWAJEiAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Sibyx:BAAALgAECgYJEgABLgAECgYJHgATAGccAA==.Siickboy:BAAALgAECgQJCQAAAA==.Sijious:BAAALgAECgYJDAAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.Singularity:BAAALgAECgQJAwABLgAECgYJHgATAGccAA==.',
Sk='Skinable:BAAALgAFFAEJAQAAAA==.Skora:BAAALgADCgIJAgABLgAECgkJJQATAP0UAA==.Skyland:BAAALgADCgcJDQABLgAFFAgJHAAdAG8YAA==.Skyli:BAAALgAECgUJCAABLgAECgkJKAAPACsgAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Sneez:BAAALgAFFAEJAQABLgAFFAQJEwAWAEgVAA==.Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAACLgAFFH8TAAISAAUJZxqSIgALAQASAAUJZxqSIgALAQAuAAQKfycAAhIACQmfH7wIAOMCABIACQmfH7wIAOMCAAAA.Sorrie:BAAALgAECgEJAQAAAA==.Sortiarius:BAAALgADCgkJCQAAAA==.',
Sp='Spud:BAAALgADCgcJBwABLgAECgYJFgADAI8fAA==.Spyroh:BAABLgAECn8bAAQGAAYJ6BLuGQBlAQAGAAYJcBDuGQBlAQAiAAUJGBJMSAAKAQAdAAEJ2wA4TwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAQJEgAHAM0RAA==.',
St='Stankydk:BAACLgAFFH8RAAMNAAcJRBTiKQDBAQANAAYJRBTiKQDBAQAJAAEJAACCagAAAAAuAAQKfzIAAg0ACQk+JdAFAEsDAA0ACQk+JdAFAEsDAAAA.Stankyeyes:BAAALgAECgYJBgAAAA==.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Staticdh:BAABLgAFFH8LAAIXAAUJBBgCFAAwAQAXAAUJBBgCFAAwAQABLgAFFAgJJwAYAGsgAA==.Steakhead:BAABLgAECn8pAAIFAAYJxAsXTQDYAAAFAAYJxAsXTQDYAAAAAA==.Stinkbombs:BAACLgAFFH8SAAIYAAYJeQioJAD4AAAYAAYJeQioJAD4AAAuAAQKfxYAAhgACQl6FNN4AIcBABgACQl6FNN4AIcBAAAA.Stinkerz:BAAALgAECgIJAgABLgAECgkJIgAZAG0gAA==.Stonegut:BAAALgAECggJDwAAAA==.Stunanddone:BAABLgAECn8VAAIoAAUJGwurBwCkAAAoAAUJGwurBwCkAAAAAA==.Stupidkitty:BAAALgAECgMJAgAAAA==.',
Su='Subrogue:BAABLgAFFH8FAAIjAAIJlhnjMQCWAAAjAAIJlhnjMQCWAAABLgAFFAMJBQAeABkGAA==.Suffragan:BAAALgAECgIJAgAAAA==.Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJEAAAAA==.Supreme:BAACLgAFFH8IAAIXAAMJXhrBXwDQAAAXAAMJXhrBXwDQAAAuAAQKfxkAAhcACAl4I24YAMMCABcACAl4I24YAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAMJAwABLgAFFAUJFgAoAIUeAA==.Swayaim:BAABLgAFFH8LAAIDAAQJEgaDVAD/AAADAAQJEgaDVAD/AAAAAA==.Sweatypits:BAAALgAECgYJBgABLgAFFAMJCgAPABMaAA==.Swordsaint:BAAALgAECgEJAQAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAYJDgASAO8RAA==.Sylphrena:BAACLgAFFH8TAAIHAAUJHxaxGAD3AAAHAAUJHxaxGAD3AAAuAAQKfygAAgcACQlQHogIAMMCAAcACQlQHogIAMMCAAAA.',
['Sí']='Sínful:BAABLgAECn8qAAIEAAkJxB+BBABqAgAEAAkJxB+BBABqAgAAAA==.',
Ta='Tacow:BAAALgAECggJEQAAAA==.Tahwe:BAAALgAECgIJAgAAAA==.Talethen:BAABLgAECn8gAAMiAAkJdRmPMgBqAQAiAAkJ8xePMgBqAQAGAAUJMxgpIAAtAQAAAA==.Talgrin:BAAALgAECgYJBgAAAA==.Talla:BAABLgAECn8oAAIPAAkJKyCtCAAmAwAPAAkJKyCtCAAmAwAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgAECgEJAQABLgAECgYJDQAOAAAAAA==.Tellus:BAAALgADCgcJCwAAAA==.Tempesttempi:BAAALgADCgcJBwAAAA==.Tewshort:BAAALgAECgQJCAABLgAFFAQJEAATAB4WAA==.',
Th='Thatbox:BAAALgAECgQJBQAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgUJEQAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAABLgAECn8UAAMUAAgJBAUFXgCfAAAnAAcJQQRZWQDeAAAUAAcJQgQFXgCfAAAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thordak:BAAALgAECgUJBQAAAA==.Thorfyna:BAABLgAECn8kAAIlAAkJRxRRCQDXAQAlAAkJRxRRCQDXAQAAAA==.Threzk:BAABLgAECn8eAAIbAAkJew7/DgBPAQAbAAkJew7/DgBPAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.Thunderstorm:BAAALgAECgcJDAAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8MAAIXAAUJZBMQNABUAQAXAAUJZBMQNABUAQAuAAQKfy8AAhcACQmGIoMLAOsCABcACQmGIoMLAOsCAAAA.Tontiamat:BAABLgAECn89AAMiAAkJXRiiFwAaAgAiAAkJXRiiFwAaAgAGAAYJawo5IAAsAQAAAA==.Tontier:BAABLgAECn8iAAQMAAkJAQ/VSABsAQAMAAgJYg7VSABsAQAKAAcJjwxSBgCBAAALAAQJSg5hSwB9AAABLgAECgkJPQAiAF0YAA==.Totembeans:BAAALgAECgQJCwAAAA==.Totemshocker:BAECLgAFFH8HAAMRAAQJJAvVEQDXAAARAAMJfAbVEQDXAAAPAAIJrgReMQBXAAAuAAQKfxYAAxEACAkqGQUXAGACABEACAkqGQUXAGACAA8AAQkBDHPeACoAAAEuAAUUBQkSAAgAiBIA.Toxicshadow:BAAALgADCgQJBgAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAACLgAFFH8OAAISAAYJ7xGlEQCoAQASAAYJ7xGlEQCoAQAuAAQKfxwABBIACQlOH5QMAMUCABIACAnDHpQMAMUCABMABwksDjq3ABcBABUAAgmgE6FNADgAAAAA.Trashfire:BAACLgAFFH8KAAMHAAQJIA50GQDvAAAHAAQJIA50GQDvAAAhAAIJwgF2FgB7AAAuAAQKfx0ABAcACAkXHSYQAGUCAAcACAkXHSYQAGUCABwABQknFXw2ADkBACEAAwluEWhAAK0AAAEuAAUUBgkOABIA7xEA.Treeple:BAABLgAECn8iAAMMAAkJ5xZvSwBhAQAMAAcJUBNvSwBhAQAFAAUJbA5zQQAIAQAAAA==.Treily:BAAALgAECggJEgAAAA==.Tresleches:BAABLgAECn8tAAITAAkJLRJBXgC1AQATAAkJLRJBXgC1AQAAAA==.Tricket:BAABLgAECn9TAAMjAAkJeCDLAwDtAgAjAAkJeCDLAwDtAgAWAAYJKBl1VAD6AAAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAbAAYIAQ==.Truestorm:BAACLgAFFH8JAAITAAIJdAWTOAB1AAATAAIJdAWTOAB1AAAuAAQKfykAAhMACQnOC0t7AHgBABMACQnOC0t7AHgBAAAA.Truheals:BAAALgAECgYJCgAAAA==.',
Tu='Tuchi:BAACLgAFFH8ZAAMmAAUJCx+8AQAIAQAYAAUJkByVHgBQAQAmAAMJaxy8AQAIAQAuAAQKfyYAAyYABwm9IzoDAPgBABgABwliIrkyAKgCACYABgnQIjoDAPgBAAAA.Tumblestone:BAAALgAECgEJAQAAAA==.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAgJGAAXAH8cAA==.',
['Tà']='Tàcobelle:BAACLgAFFH8HAAIEAAIJoxMhCgCfAAAEAAIJoxMhCgCfAAAuAAQKfxYAAgQACQnrHm8EAGwCAAQACQnrHm8EAGwCAAEuAAQKCAksABgANRgA.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Vaelen:BAAALgAECgEJAQABLgAECgkJGAAfAJUaAA==.Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgAOAAAAAA==.Valhalla:BAAALgAECgYJBgAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIPAAMJriKiOgD4AAAPAAMJriKiOgD4AAAuAAQKfzEAAw8ACQllGz8SAIQCAA8ACQllGz8SAIQCABEABgkTGpE2AF8BAAAA.Varanis:BAACLgAFFH8JAAIDAAMJnxZuDAD/AAADAAMJnxZuDAD/AAAuAAQKfxkAAgMACQlkIWMLAOgCAAMACQlkIWMLAOgCAAAA.',
Ve='Vegh:BAACLgAFFH8HAAIlAAMJYBglCQDAAAAlAAMJYBglCQDAAAAuAAQKf04AAiUACQnzH1wDAKoCACUACQnzH1wDAKoCAAAA.Vem:BAABLgAECn8uAAIiAAkJsR1IEABlAgAiAAkJsR1IEABlAgAAAA==.Veriale:BAAALgAECgcJDAAAAA==.Verra:BAABLgAECn85AAITAAkJWhs3JgBrAgATAAkJWhs3JgBrAgAAAA==.',
Vi='Vitriol:BAABLgAECn8hAAIWAAcJZxgwMQCIAQAWAAcJZxgwMQCIAQAAAA==.',
Vo='Voidbeaver:BAAALgAECgcJCwAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAACLgAFFH8OAAMaAAQJoBMWBgAhAQAaAAQJoBMWBgAhAQAbAAEJYQcDKwA8AAAuAAQKfx8AAhoACQl2IqsBAMoCABoACQl2IqsBAMoCAAAA.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgcJEAAOAAAAAA==.Vyrros:BAAALgAECgYJCAAAAA==.',
Wa='Walji:BAABLgAECn8eAAMPAAgJyhtyFwBaAgAPAAgJyhtyFwBaAgARAAEJWwumrwApAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgAECgIJBAAAAA==.Wandy:BAABLgAECn86AAIfAAkJnxpRAwDXAQAfAAkJnxpRAwDXAQAAAA==.Wangstah:BAABLgAECn8cAAIDAAkJMiReDwDVAgADAAkJMiReDwDVAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAIWAAYJNhQUSgB8AQAWAAYJNhQUSgB8AQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJDgAAAA==.Wawatesi:BAAALgAECgMJAwAAAA==.Waytogoteam:BAACLgAFFH8OAAIDAAMJMxxxHwDzAAADAAMJMxxxHwDzAAAuAAQKfzgAAgMACQkpJJYLAPcCAAMACQkpJJYLAPcCAAAA.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8WAAMYAAcJHBS0KgDJAQAYAAcJHBS0KgDJAQAZAAIJBw4+BQCCAAAuAAQKfzMABBgACQnEJH8NAA4DABgACQk3JH8NAA4DABkABgm+I3wDANkBACYAAQmPIMgWAGQAAAAA.Wenya:BAAALgADCgcJDgAAAA==.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgQJBAAAAA==.',
Wo='Woodyy:BAABLgAECn8oAAINAAgJcBCACgAjAQANAAgJcBCACgAjAQAAAA==.Woog:BAAALgAECgcJEgAAAA==.Wox:BAAALgAECgkJEAAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wu='Wujustyle:BAAALgAECgcJBwABLgAFFAUJCQANAMccAA==.Wulfgar:BAAALgAFFAEJAQAAAA==.',
Wy='Wyldspirit:BAABLgAECn8mAAIDAAkJTw4PDAA1AQADAAkJTw4PDAA1AQAAAA==.Wyreless:BAAALgADCgYJBgABLgAECgkJNQAKABUWAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgAECgEJAQAAAA==.',
Xe='Xe:BAAALgAECgYJBgABLgAECgkJUwAjAHggAA==.',
Xr='Xrind:BAAALgADCgEJAQAAAA==.',
Ya='Yaass:BAAALgAECgMJAwAAAA==.',
Ye='Yem:BAACLgAFFH86AAQbAAcJsCBmAgDMAQAbAAYJEiBmAgDMAQAfAAYJOx4EPABcAQAaAAIJYSIrHgBTAAAuAAQKfzYAAxsACQmiIzkGAGwCABsABgncIzkGAGwCAB8ABgliI1VJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAILAAcJvxm2CAAfAgALAAcJvxm2CAAfAgABLgAFFAYJFQATAPQaAA==.Yoverre:BAAALgAECgMJAwAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAAOAAAAAA==.Zanzabar:BAABLgAECn8XAAITAAkJvBlHQAAGAgATAAkJvBlHQAAGAgAAAA==.Zaraelitha:BAAALgAECggJDgAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgYJCQABLgAECgkJRAAHADIgAA==.Zeodrik:BAABLgAECn8cAAIWAAcJYRmxNQDSAQAWAAcJYRmxNQDSAQAAAA==.',
Zh='Zhenya:BAACLgAFFH8TAAIYAAUJ+hKwYgAdAQAYAAUJ+hKwYgAdAQAuAAQKfycAAxgACQltGJtLAPgBABgACQltGJtLAPgBACYABAkvD+gOANUAAAAA.',
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
