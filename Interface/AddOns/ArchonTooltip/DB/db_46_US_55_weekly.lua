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

local lookup = {'Rogue-Assassination','Paladin-Retribution','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Evoker-Devastation','Priest-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Druid-Restoration','DeathKnight-Unholy','Unknown-Unknown','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Paladin-Holy','Monk-Windwalker','Paladin-Protection','Warrior-Fury','DemonHunter-Devourer','Mage-Frost','Mage-Fire','Evoker-Preservation','Evoker-Augmentation','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Monk-Brewmaster','Monk-Mistweaver','Warlock-Demonology','DemonHunter-Havoc','Priest-Discipline','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Mage-Arcane','Rogue-Subtlety',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-08-18',data={Ab='Abc:BAAALgAECgUJCAAAAA==.Abracadava:BAAALgAECgQJBQAAAA==.',
Ac='Acheniris:BAAALgAECgYJEQAAAA==.',
Ad='Adeaino:BAAALgAECgUJCAAAAA==.Adonix:BAAALgAECgEJAQAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgUJBwAAAA==.',
Ag='Agrippa:BAACLgAFFH8HAAIBAAQJyQE8CgCaAAABAAQJyQE8CgCaAAAuAAQKfxwAAgEACAmgDo4JAKMBAAEACAmgDo4JAKMBAAAA.',
Ah='Ahndhrez:BAAALgAECgcJBgAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAABLgAECn8UAAICAAgJkA6WlwBFAQACAAgJkA6WlwBFAQAAAA==.Aioli:BAABLgAECn8kAAQDAAkJ1BvVEgARAgADAAkJuRjVEgARAgAEAAYJ7hdaRwCUAQAFAAUJcRo4SAAzAQAAAA==.Airwavez:BAAALgAFFAMJAwAAAA==.',
Al='Alchemorph:BAABLgAECn8XAAIGAAgJSwnQPQAYAQAGAAgJSwnQPQAYAQAAAA==.Aldormu:BAABLgAECn8mAAIHAAkJuAx8CgB3AQAHAAkJuAx8CgB3AQAAAA==.Aliyah:BAEALgADCgIJAgABLgAECgkJJgAIAMoZAA==.Allura:BAACLgAFFH8SAAIIAAQJzRGZHADTAAAIAAQJzRGZHADTAAAuAAQKfyQAAggACQmLGQ4WACwCAAgACQmLGQ4WACwCAAAA.Altra:BAACLgAFFH8TAAMJAAUJDguJEQAHAQAJAAQJDguJEQAHAQAKAAEJAAAQPAAAAAAuAAQKfykAAwkACQl5HFYCAJ8CAAkACQl5HFYCAJ8CAAoABwl7A1orAOQAAAAA.Alyvia:BAAALgADCgEJAgAAAA==.',
Am='Amoeta:BAABLgAECn81AAQLAAkJFRZjDwC/AQALAAgJ0hVjDwC/AQAMAAkJAg6qIABJAQANAAcJyQg9aQD4AAAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgQJBAAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgAECgUJBwAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angelkinq:BAAALgAECgEJAwABLgAFFAUJCQAOAMccAA==.Angryapples:BAAALgAECgQJCQAAAA==.Anilbeedz:BAAALgAECgEJAQAAAA==.Annihilation:BAAALgAECgUJCQAAAA==.Antinous:BAABLgAECn8qAAIFAAgJ3gw6EwArAQAFAAgJ3gw6EwArAQAAAA==.',
Ap='Apathia:BAAALgAECgEJAQABLgAECgYJCAAPAAAAAA==.Aphrodité:BAAALgAECgIJAgAAAA==.Approved:BAAALgADCgEJAQAAAA==.',
Ar='Arcstorm:BAAALgAECgYJDwAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Ashenback:BAACLgAFFH8GAAMQAAMJXAqHYgCEAAAQAAMJXAqHYgCEAAARAAEJkQkKHAA+AAAuAAQKfxkABBEACAl8GlEKABUCABEACAkxGlEKABUCABIAAwn1HoNJAA4BABAAAgkaGuucAJcAAAEuAAUUBgkOABMA7xEA.Ashguard:BAAALgAECgQJBAAAAA==.Asililisa:BAAALgAECgEJAQAAAA==.Asomyrh:BAABLgAECn8lAAMTAAkJmxUEGgA1AgATAAkJmxUEGgA1AgACAAEJPQHY0wESAAAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgYJCAAAAA==.Atticus:BAAALgADCgkJCQAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgAECgYJDwAAAA==.',
Av='Averyl:BAAALgAECgUJBQAAAA==.Aviendha:BAAALgAECgYJCgAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAIUAAgJLQptKgCKAQAUAAgJLQptKgCKAQAAAA==.',
Az='Azenith:BAABLgAECn8cAAMCAAYJgRx9agCaAQACAAYJgRx9agCaAQAVAAEJrQjGVAAnAAAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bababing:BAAALgADCgEJAQABLgAFFAIJBgACAFsYAA==.Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bamboozle:BAAALgAECgEJAQAAAA==.Bananer:BAABLgAECn8iAAIWAAkJeBRSIwDZAQAWAAkJeBRSIwDZAQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Bb='Bbqlol:BAAALgAECgYJBwABLgAECgYJHgACAGccAA==.',
Be='Beaugersugar:BAAALgAECgQJBQAAAA==.Beebler:BAABLgAECn8YAAIRAAgJnhfnDgDCAQARAAgJnhfnDgDCAQAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgAECgcJCAAAAA==.Bennington:BAAALgADCgYJBgAAAA==.Beowulf:BAAALgAECgEJBAAAAA==.Bestt:BAAALgAECgQJCQAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Bigbluenfab:BAAALgAECgIJAgAAAA==.Bigdaddyd:BAAALgAECgIJAgAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigholylady:BAAALgADCgkJCQABLgAFFAUJCQAOAMccAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigocagler:BAAALgAECgcJAQAAAA==.Bigolchungus:BAABLgAECn8eAAMVAAkJwRpuCQA7AgAVAAgJeBluCQA7AgACAAUJ6BjFuwAOAQAAAA==.Bigpapadots:BAAALgAECgMJBAAAAA==.Bigpéet:BAAALgAECgMJBwAAAA==.Bigshizz:BAAALgAECgQJBgABLgAECgcJFwAGAAEhAA==.Bippysmasher:BAABLgAECn8kAAIXAAkJaxI1SACuAQAXAAkJaxI1SACuAQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.Bishmanistic:BAAALgAECgIJAgAAAA==.',
Bl='Blacblood:BAABLgAECn8fAAIJAAkJYRHNBQDSAQAJAAkJYRHNBQDSAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJEQAAAA==.Blindweiss:BAAALgAFFAEJAQABLgAFFAgJGQAYADESAA==.Blinkies:BAABLgAECn8iAAMZAAkJbSD5AADWAgAZAAkJbSD5AADWAgAYAAUJlg8wvgAMAQAAAA==.Blinkster:BAAALgAECgEJBgAAAA==.Bloodfushion:BAAALgADCgYJBgAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgAECgMJAwAPAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8aAAIEAAkJDxpOBwBGAgAEAAkJDxpOBwBGAgAuAAQKfysAAgQACQmNIycKAAYDAAQACQmNIycKAAYDAAAA.Boolala:BAABLgAECn8UAAQaAAYJ9QkeBgDRAAAaAAYJ9QkeBgDRAAAbAAQJBwFJogAbAAAHAAIJQgFhLAAZAAABLgAECgkJMgACAIYRAA==.Borstenne:BAACLgAFFH8SAAIOAAUJGR3PUQBOAQAOAAUJGR3PUQBOAQAuAAQKfykAAg4ACQm7JEoTANQCAA4ACQm7JEoTANQCAAAA.Boö:BAAALgAECgQJBAABLgAECgkJMgACAIYRAA==.',
Br='Brake:BAACLgAFFH8KAAIOAAMJnxFTqwDIAAAOAAMJnxFTqwDIAAAuAAQKfyYAAg4ACAlXHvU1AF8CAA4ACAlXHvU1AF8CAAAA.Brese:BAAALgAECgIJAgABLgAFFAUJEwAXAHIZAQ==.Breseayaya:BAACLgAFFH8TAAIXAAUJchlIPwAqAQAXAAUJchlIPwAqAQAuAAQKfy0AAhcACQkrIXcNANkCABcACQkrIXcNANkCAAAA.Breseshh:BAAALgAECgcJEwABLgAFFAUJEwAXAHIZAA==.Brickbeard:BAACLgAFFH8NAAIcAAQJeREOBQA4AQAcAAQJeREOBQA4AQAuAAQKfy0AAxwACQl0Fa0GAA8CABwACQl0Fa0GAA8CAB0ABwnDDeUZAH0BAAAA.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJEgABLgAFFAkJIAACAC8dAA==.Bricksquad:BAAALgAECgMJAwABLgAFFAMJBQAXAHodAA==.Brickthrow:BAACLgAFFH8gAAMCAAkJLx2hHQCSAQACAAYJ1hqhHQCSAQATAAYJ3grMDAA6AQAuAAQKfzMAAwIACQmsJBgIACsDAAIACQmsJBgIACsDABMABQlyBENyAG4AAAAA.Bronkle:BAAALgAECgUJBQABLgAFFAQJDQAcAHkRAA==.',
Bu='Buhleed:BAAALgAECgIJAgAAAA==.Burgerburn:BAAALgAECgUJCwAAAA==.',
By='Bytheway:BAABLgAECn8aAAIeAAkJ+xN8DQDkAAAeAAkJ+xN8DQDkAAAAAA==.',
['Bà']='Bàbÿ:BAAALgAECgcJDgAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
['Bé']='Béstt:BAAALgAECgMJAwAAAA==.',
Ca='Cadilak:BAACLgAFFH8TAAINAAUJPxBgMADvAAANAAUJPxBgMADvAAAuAAQKfzEABA0ACQm4I8cIACsDAA0ACQm4I8cIACsDAAYAAglbGzx8AE4AAAwAAQlKAac3ABkAAAAA.Cadsune:BAAALgAECgYJDAAAAA==.Caelesti:BAABLgAECn8pAAMIAAkJXRMfIADCAQAIAAgJVxMfIADCAQAeAAkJSBacJgCYAQAAAA==.Calisse:BAABLgAFFH8KAAIfAAQJnxvvCABeAQAfAAQJnxvvCABeAQABLgAFFAQJEQAUAIoiAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAgAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQABLgAFFAkJJQAaAFsbAA==.Cheapshotjoe:BAAALgAECgEJAQAAAA==.Chelbur:BAAALgADCgEJAQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chosmuke:BAAALgAECgEJAwAAAA==.Chowderhead:BAABLgAECn8UAAIdAAYJYxzhDgDcAQAdAAYJYxzhDgDcAQAAAA==.',
Ci='Cileb:BAACLgAFFH8GAAIYAAUJSBipYAAgAQAYAAUJSBipYAAgAQAuAAQKfzUAAhgACQmkJAIMABkDABgACQmkJAIMABkDAAAA.Civik:BAABLgAECn9KAAIEAAkJciOICQAMAwAEAAkJciOICQAMAwAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAFFAMJBQAXAHodAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAACLgAFFH8dAAICAAYJKReqFABUAQACAAYJKReqFABUAQAuAAQKfzAAAgIACQldGl89AA8CAAIACQldGl89AA8CAAAA.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAFFAQJBQAXAAkFAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJJwAKAAkjAA==.Copperit:BAABLgAECn8nAAIKAAkJCSOQAgBDAwAKAAkJCSOQAgBDAwAAAA==.Coreroot:BAAALgAECgEJAQAAAA==.Cornburglar:BAACLgAFFH8WAAIWAAQJkSJgEQB7AQAWAAQJkSJgEQB7AQAuAAQKfzsAAhYACAlcJXAIANkCABYACAlcJXAIANkCAAAA.Cowtaclysmic:BAACLgAFFH8FAAIOAAIJOgfN3wCFAAAOAAIJOgfN3wCFAAAuAAQKfyMAAw4ACAkGE6SAAGIBAA4ACAmaDKSAAGIBAAoABQlKFmoqAAUBAAAA.',
Cr='Crackersz:BAABLgAECn8WAAMQAAcJHQgMigDHAAAQAAcJHQgMigDHAAASAAMJGATNhwBgAAAAAA==.Cranjis:BAABLgAECn9kAAIgAAkJeCJnBwAoAwAgAAkJeCJnBwAoAwAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Criss:BAAALgAFFAIJBAABLgAFFAQJEQAUAIoiAA==.Crunchwrap:BAABLgAECn8qAAIGAAkJDA8LJwCWAQAGAAkJDA8LJwCWAQAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgcJBwAAAA==.',
Cu='Curadora:BAAALgADCgQJBAAAAA==.Cursereflect:BAABLgAECn8iAAMhAAkJyQ7fUwCgAQAhAAkJyQ7fUwCgAQAdAAEJAADNVgAAAAAAAA==.Curseus:BAAALgAECgIJBQAAAA==.',
Cy='Cyberwin:BAAALgAECgEJAQAAAA==.',
['Câ']='Câlisse:BAABLgAFFH8RAAIUAAQJiiLyAwCZAQAUAAQJiiLyAwCZAQAAAA==.',
['Cä']='Cäpsløck:BAAALgAECgEJAQAAAA==.',
Da='Daiyan:BAAALgADCgEJAQAAAA==.Damncats:BAACLgAFFH8GAAIWAAMJVwt6KQB7AAAWAAMJVwt6KQB7AAAuAAQKf1QAAhYACQm9FgUFALcBABYACQm9FgUFALcBAAAA.Dandinn:BAAALgAECgYJCQAAAA==.Danielsboone:BAABLgAECn8sAAIEAAkJDxXDDQCWAQAEAAkJDxXDDQCWAQAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJCAABLgAFFAUJDQASAMMMAA==.Darknemesis:BAABLgAECn8UAAIYAAYJPRh9EABjAQAYAAYJPRh9EABjAQAAAA==.Davidbowey:BAAALgAECgIJBQAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAFFAIJAwABLgAFFAgJPAAdAHgfAA==.',
De='Deadhippocow:BAABLgAECn8cAAINAAgJkR3jLAD0AQANAAgJkR3jLAD0AQAAAA==.Deathwavez:BAACLgAFFH8bAAIOAAYJPBNnIwBPAQAOAAYJPBNnIwBPAQAuAAQKfxsAAg4ACAnoFgFlAMUBAA4ACAnoFgFlAMUBAAAA.Declän:BAAALgAECgQJBQABLgAECggJHAANAJEdAA==.Decurse:BAABLgAECn8kAAIhAAkJ+hTPPADoAQAhAAkJ+hTPPADoAQAAAA==.Degrono:BAAALgAECgQJBAAAAA==.Deldrin:BAABLgAECn8mAAIYAAkJERSJUADqAQAYAAkJERSJUADqAQAAAA==.Demayy:BAABLgAECn8uAAIgAAkJKxNWIwAFAgAgAAkJKxNWIwAFAgAAAA==.Demona:BAACLgAFFH8MAAMhAAUJAwwHYQAGAQAhAAQJAwwHYQAGAQAcAAIJkgdYLAA9AAAuAAQKfyUAAx0ACAkxGe4pABoBACEABwnIFQl4AEkBAB0ABAngE+4pABoBAAAA.Demonix:BAABLgAECn8YAAIhAAgJlRoeNgABAgAhAAgJlRoeNgABAgAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAACLgAFFH8NAAIYAAQJggckcQD/AAAYAAQJggckcQD/AAAuAAQKfzoAAhgACQm/D19XANcBABgACQm/D19XANcBAAAA.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedqt:BAAALgAECgYJCQABLgAECgYJHgACAGccAA==.Dilutedret:BAABLgAECn8eAAMCAAYJZxxweQB7AQACAAYJZxxweQB7AQATAAIJsAQDhABDAAAAAA==.Dilutedx:BAAALgAECgUJCAABLgAECgYJHgACAGccAA==.Dinobrass:BAACLgAFFH8FAAMFAAMJHgLlJwBuAAAFAAMJHgLlJwBuAAAEAAEJ5QNWgQA2AAAuAAQKfzoAAwQACAl8GvEHAA0CAAQABwkoHfEHAA0CAAUACAm0DXMRAEQBAAAA.Dirktheshiny:BAAALgAECgkJDwABLgAECgkJPQAGAIEbAA==.Dirtylöbster:BAACLgAFFH8OAAIYAAMJTCHYJwAUAQAYAAMJTCHYJwAUAQAuAAQKfzUAAhgACQkKJb0JACwDABgACQkKJb0JACwDAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgYJEQABLgAECgYJHgACAGccAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doobysnacks:BAAALgAECgQJBQAAAA==.Doolittle:BAABLgAECn8XAAIGAAkJHxqOCwAFAQAGAAkJHxqOCwAFAQAAAA==.Dorfydorf:BAAALgAECgEJAgAAAA==.Dorose:BAAALgAECgEJAgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Dranight:BAAALgAECgcJBwABLgAECgkJSgAEAHIjAA==.Dreats:BAAALgAECgYJEQAAAA==.Drewmee:BAABLgAECn8YAAICAAkJHgkPkQBQAQACAAkJHgkPkQBQAQAAAA==.Dronar:BAABLgAFFH8FAAIQAAUJCgk3LwAlAQAQAAUJCgk3LwAlAQABLgAECgkJIwAMAAEgAA==.Drublood:BAAALgAECgcJDAABLgAECgkJGAACAB4JAA==.Drunkinmasta:BAAALgAECgEJAQABLgAFFAQJEAACAB4WAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Duckbeak:BAAALgAECgUJCwAAAA==.Dune:BAAALgADCgcJBwAAAA==.Duwork:BAABLgAECn8XAAIGAAcJASHkHADhAQAGAAcJASHkHADhAQAAAA==.',
['Dæ']='Dæmona:BAABLgAECn8VAAIiAAkJmxLTFQDeAQAiAAkJmxLTFQDeAQAAAA==.',
Eb='Ebk:BAAALgAECgcJDAAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
Ei='Eight:BAAALgADCggJGAAAAA==.',
El='Eladus:BAAALgAECgcJEAAAAA==.Elemnt:BAABLgAECn8UAAMSAAcJXRDTCQAyAQASAAcJXRDTCQAyAQAQAAYJWg/eZQAqAQABLgAFFAQJEAACAB4WAA==.Elesus:BAAALgAECggJDQABLgAECgkJQwAjAJUhAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJDwAAAA==.Emrys:BAAALgAECgMJAgAAAA==.',
En='Enhshaman:BAACLgAFFH8FAAIgAAMJGQajRQCNAAAgAAMJGQajRQCNAAAuAAQKfxYAAiAACQn+FDYkAP8BACAACQn+FDYkAP8BAAAA.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.Evilinne:BAAALgADCgIJAgAAAA==.Evânescence:BAAALgAECgEJAQAAAA==.',
Ex='Excaliburn:BAAALgAECgEJBQAAAA==.',
Ez='Ezekial:BAAALgAECgQJBAAAAA==.Ezkal:BAACLgAFFH8UAAIOAAUJGxzFaAAoAQAOAAUJGxzFaAAoAQAuAAQKfywAAw4ACQnsGaEYAOgCAA4ACQnsGaEYAOgCAAoABgktFW0rAP4AAAAA.',
Fa='Faithastray:BAAALgAECgMJAwAAAA==.Faithpasse:BAABLgAECn9HAAMgAAkJjSC0AgB8AgAgAAkJjSC0AgB8AgAUAAEJ9gPfhgApAAAAAA==.Falcorne:BAABLgAECn80AAIEAAkJqiIRCAAbAwAEAAkJqiIRCAAbAwAAAA==.Fatlipz:BAABLgAECn8iAAIjAAcJdQ++CQBHAQAjAAcJdQ++CQBHAQAAAA==.Fay:BAAALgADCgEJAQABLgAECgYJCAAPAAAAAA==.',
Fe='Felondar:BAACLgAFFH8FAAIiAAIJ/QWCGABhAAAiAAIJ/QWCGABhAAAuAAQKfygAAyIACQkUEVsiAGUBACIACQkUEVsiAGUBABcABgmwBLObAOEAAAAA.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8ZAAMKAAkJhBsxDABOAgAKAAcJsBsxDABOAgAOAAgJvhiIagC3AQAAAA==.',
Fi='Finnadin:BAABLgAECn8sAAICAAkJzx9dGQCrAgACAAkJzx9dGQCrAgAAAA==.Finns:BAAALgAECgkJEwAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAABLgAECn8dAAIEAAgJ0xnyOQD3AQAEAAgJ0xnyOQD3AQAAAA==.Fistinfred:BAAALgADCgMJAwAAAA==.Fistobeef:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.',
Fl='Fleable:BAAALgAECgQJAwAAAA==.Flysky:BAACLgAFFH8lAAIaAAkJWxsfAgB+AgAaAAkJWxsfAgB+AgAuAAQKfywABBoACQnFI4kCAEcDABoACQnFI4kCAEcDABsACAnIJF4HAOICAAcAAQl3DyBBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECggJDQAAAA==.',
Fr='Freakmeout:BAAALgAECgQJBAAAAA==.Freshpot:BAAALgAECgMJAwAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgAECgEJAQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Furysbane:BAAALgAECgYJCgAAAA==.Future:BAAALgAECgUJDgABLgAFFAUJFAAOABscAA==.Futuredragoo:BAAALgAECgcJDAABLgAFFAUJFAAOABscAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Fy='Fyska:BAAALgADCgEJAQAAAA==.',
Ga='Gabriella:BAAALgAECgYJDAAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQAPAAAAAA==.Galnannix:BAAALgAECgkJEAAAAA==.Gardrake:BAABLgAECn8zAAMbAAkJrBn5EABeAgAbAAkJrBn5EABeAgAaAAcJqhCrHQCWAQAAAA==.Gastapha:BAABLgAECn8ZAAIXAAkJ0wZoigAMAQAXAAkJ0wZoigAMAQAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMWAAgJCxMcMADvAQAWAAgJCxMcMADvAQAkAAEJAAD2jwAAAAAAAA==.Gehennas:BAABLgAFFH8FAAIXAAMJeh2+UwDzAAAXAAMJeh2+UwDzAAAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Gi='Girnahuma:BAAALgAECgEJAQAAAA==.',
Go='Goku:BAAALgAFFAIJAgAAAA==.Goofykirby:BAAALgADCgcJFQAAAA==.Googoo:BAABLgAECn8UAAIOAAkJrhNCOgAXAgAOAAkJrhNCOgAXAgAAAA==.Googoogagaa:BAACLgAFFH8MAAIeAAQJkhAXHQAHAQAeAAQJkhAXHQAHAQAuAAQKf0YAAx4ACQkKHnMNAH0CAB4ACQkKHnMNAH0CAAgABwnyEgMqAKIBAAAA.Gotlieb:BAAALgAECggJCgAAAA==.',
Gr='Grenno:BAAALgAECgcJBwABLgAFFAkJIgAOAFYcAA==.Greystorm:BAAALgAECgIJAgAAAA==.Greythorn:BAAALgADCgkJCQABLgAECgkJSgAEAHIjAA==.Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQAPAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8pAAMFAAkJaxNEBQCRAQAFAAkJaxNEBQCRAQADAAUJVA1bFwAXAQAuAAQKfxQAAgUABwkJJOIRAKoCAAUABwkJJOIRAKoCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gw='Gwilly:BAAALgAECgMJBQAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hakarren:BAAALgAECgcJEwAAAA==.Hakosuka:BAAALgAECgIJAgAAAA==.Hamatza:BAAALgAECgEJAgAAAA==.Hammerinfred:BAAALgAECgUJCwAAAA==.Hawkmoon:BAAALgAECgEJBAAAAA==.',
He='Healingisfun:BAAALgAECgMJBAAAAA==.Heavyguard:BAAALgAECgEJAQAAAA==.Helhunter:BAABLgAECn8yAAIXAAkJbRL9RwCuAQAXAAkJbRL9RwCuAQAAAA==.Hellock:BAAALgAFFAEJAQAAAA==.',
Hi='Hippayman:BAABLgAECn8ZAAMTAAYJdBy6AwD4AQATAAYJdBy6AwD4AQACAAEJPRE2YwA0AAAAAA==.Hippysmasher:BAAALgAECgIJAgABLgAECgkJJAAXAGsSAA==.',
Ho='Hodgepodge:BAAALgAECgEJAgAAAA==.Hohennheim:BAAALgAECgUJBQAAAA==.Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgMJBQAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holybob:BAAALgAECgQJCAAAAA==.Holyhooters:BAABLgAECn87AAICAAkJ2yFiDwDrAgACAAkJ2yFiDwDrAgAAAA==.Holypablo:BAAALgAECgQJBgABLgAECgkJUQAjAMEfAA==.Homefries:BAAALgADCgYJBgABLgAECggJHAANAJEdAA==.Honkytonk:BAABLgAECn8aAAMHAAgJKQtAIgAYAQAHAAYJ7QlAIgAYAQAbAAcJeAmsOAATAQAAAA==.Honor:BAAALgAECgcJDQABLgAECgkJOwACAI8jAA==.Honour:BAABLgAECn87AAICAAkJjyMgDgD0AgACAAkJjyMgDgD0AgAAAA==.',
Hr='Hrathdemon:BAACLgAFFH8SAAIXAAUJlxfSQAAlAQAXAAUJlxfSQAAlAQAuAAQKfysAAhcACQntIPMQALoCABcACQntIPMQALoCAAAA.Hrathid:BAAALgADCgUJDAABLgAFFAUJEgAXAJcXAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8KAAICAAMJiiBUEgATAQACAAMJiiBUEgATAQAuAAQKfywAAgIACQnqI7oFAHIDAAIACQnqI7oFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAABLgAECn8aAAMCAAkJNxyILwBDAgACAAkJNxyILwBDAgATAAIJWwcbhgA/AAAAAA==.',
Ib='Ibleedorange:BAAALgAECggJDQAAAA==.',
Ic='Icehawk:BAAALgAECgMJBgABLgAFFAEJAQAPAAAAAA==.Ickeetard:BAABLgAECn8eAAMjAAkJUhJ5MQBWAQAjAAcJFA95MQBWAQAIAAYJsxGzQADqAAAAAA==.',
Id='Idiot:BAAALgAECgMJBAAAAA==.Idiotbreath:BAABLgAECn82AAMbAAkJFSCxCADLAgAbAAkJFSCxCADLAgAHAAMJmQmDMACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgAECgEJAgAAAA==.Ieyasu:BAACLgAFFH8JAAIGAAYJRgkAEQAQAQAGAAYJRgkAEQAQAQAuAAQKfxgAAgwABwm/GbYIAB8CAAwABwm/GbYIAB8CAAEuAAUUBgkVAAIA9BoA.',
Ig='Igloocrusade:BAEALgAECgEJAQABLgAFFAYJEwAJAAYSAA==.Ignitus:BAAALgAECgUJBgAAAA==.',
Im='Immorlich:BAAALgAECgEJAQAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJCQAAAA==.Infiniti:BAAALgADCgIJAgAAAA==.Inflexi:BAACLgAFFH8MAAIEAAQJ8Bf3OgA3AQAEAAQJ8Bf3OgA3AQAuAAQKfy0AAwQACQlqIFYNAOgCAAQACQmYH1YNAOgCAAUACAnKGvAYAGQCAAAA.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAABLgAECn8YAAIUAAYJWhmmLwBKAQAUAAYJWhmmLwBKAQAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn8/AAQNAAkJIB5zDgDjAgANAAkJIB5zDgDjAgAGAAgJFyDpFAAqAgAMAAMJ2hZXOQDAAAAAAA==.',
Iv='Iver:BAAALgAECgUJBgABLgAECgcJEQAPAAAAAA==.',
Ja='Jaliano:BAAALgADCgYJBgABLgAECgkJLgAQAJkXAA==.Jangle:BAAALgADCgYJBwAAAA==.',
Je='Jeffblades:BAAALgAECgcJEAAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgUJCwAPAAAAAA==.',
Jj='Jjooaacchhim:BAAALgAECgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8jAAIEAAkJfBt2LQAnAgAEAAkJfBt2LQAnAgAAAA==.',
Ka='Kadillac:BAABLgAECn8WAAIlAAcJUQgjLgDMAAAlAAcJUQgjLgDMAAAAAA==.Kaelira:BAAALgADCgIJAgAAAA==.Kairei:BAABLgAECn8XAAMTAAkJmw2hPQBPAQATAAkJmw2hPQBPAQACAAUJnwjdNQCAAAAAAA==.Kakashi:BAAALgADCgEJAQAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBgAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAACLgAFFH8VAAICAAYJ9BpDKQBnAQACAAYJ9BpDKQBnAQAuAAQKfyEAAwIACQl1ItwRANkCAAIACQkUItwRANkCABUABQnrH2QHAP8AAAAA.Katalina:BAABLgAECn8wAAMmAAgJmBHLDQB2AQAmAAgJmBHLDQB2AQAiAAYJpwsROAAlAQAAAA==.Kawer:BAAALgAECgQJCQAAAA==.Kawnzerker:BAAALgADCgkJCQAAAA==.',
Ke='Keilanis:BAAALgAECgIJAgAAAA==.Kelstormhoof:BAAALgAECgEJAQABLgAECgYJFAAYAD0YAA==.Kernel:BAAALgAECgEJAQABLgAFFAQJFgAWAJEiAA==.',
Kh='Kham:BAACLgAFFH8ZAAIWAAYJLhsaDgA2AQAWAAYJLhsaDgA2AQAuAAQKf0QAAhYACQlgJMYDACsDABYACQlgJMYDACsDAAAA.Khäléési:BAAALgAECgEJAQAAAA==.',
Ki='Kialla:BAAALgAECgIJAgABLgAECgkJKAAQACsgAA==.Killmaim:BAABLgAECn8ZAAIWAAgJwRllIABPAgAWAAgJwRllIABPAgAAAA==.Kitsuko:BAABLgAECn80AAMQAAkJFg+2PgCzAQAQAAkJFg+2PgCzAQASAAkJxRDNLACRAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ko='Kokeovrdose:BAAALgAECgQJBAABLgAECgYJFAAYAAYWAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuli:BAAALgAECgEJAgAAAA==.Kuraishin:BAAALgAFFAEJAQABLgAFFAgJGQAYADESAA==.Kuvare:BAAALgAECgMJAwAAAA==.',
['Kå']='Kårmå:BAAALgADCgUJBQAAAA==.',
['Kè']='Kèlton:BAAALgAECgUJCgABLgAECgQJCgAPAAAAAA==.',
La='Lanas:BAEALgAECgkJAwABLgAFFAcJFwACAA0PAA==.Laocoon:BAAALgAECggJCAABLgAECgkJOwACANshAA==.Lavashiza:BAAALgAECgYJEwAAAA==.Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAABLgAECn8dAAIEAAkJRRatCwC4AQAEAAkJRRatCwC4AQAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAgAAAA==.Leedaddydk:BAAALgAECgQJCgAAAA==.Leeoflight:BAAALgADCgEJAQAAAA==.Leroyjenkins:BAABLgAECn8XAAInAAcJ8BvoAgBVAgAnAAcJ8BvoAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.Letsbeef:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.',
Li='Lightstorm:BAAALgAECgYJEAAAAA==.Linaria:BAAALgAECgYJCgAAAA==.Linø:BAAALgAECgIJAgAAAA==.Lissara:BAABLgAECn8ZAAIbAAgJExBPNABiAQAbAAgJExBPNABiAQAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAACLgAFFH8TAAIfAAUJqRyjGgBQAQAfAAUJqRyjGgBQAQAuAAQKfyMAAh8ACQnCHEIOAFUCAB8ACQnCHEIOAFUCAAAA.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockdownlol:BAAALgAECgEJAQABLgAECgYJHgACAGccAA==.Lockednabyss:BAAALgAECgQJBAABLgAECgkJOgAoAD0kAA==.Lockmogged:BAAALgAFFAIJAgAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECgkJHAAEADIkAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAFFAQJDgAcAKATAA==.Luminouslexi:BAAALgAECgMJAwAAAA==.',
Ma='Macoub:BAACLgAFFH8FAAIXAAQJCQUSYADPAAAXAAQJCQUSYADPAAAuAAQKfxcABCIACAnFFZonAD4BACIABgl2FZonAD4BABcABAmMGrebAOoAACYAAwluB5YxAD0AAAAA.Macuahuitl:BAAALgAECgQJBAAAAA==.Maddog:BAABLgAECn8ZAAMdAAgJfQU9GwDLAAAdAAgJUQU9GwDLAAAhAAQJzAOX/gBqAAAAAA==.Maebell:BAAALgAECgYJDAABLgAECgYJHgACAGccAA==.Mageslayer:BAABLgAECn8bAAMoAAgJmxPjHgCfAQAoAAgJGBLjHgCfAQABAAMJPRCNGACtAAAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magicstorm:BAAALgAECgcJBwAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgAPAAAAAA==.Magrun:BAABLgAECn8VAAQnAAYJzRxhAgBlAQAnAAUJHR5hAgBlAQAZAAEJMRjsBQBJAAAYAAIJjxcaSgBFAAAAAA==.Mahalleinr:BAAALgAECgEJAgAAAA==.Maiggee:BAAALgAECgEJAgAAAA==.Makkideez:BAABLgAECn8UAAIoAAkJOBhVEAApAgAoAAkJOBhVEAApAgAAAA==.Makkii:BAAALgADCgEJAQABLgAECgkJFAAoADgYAA==.Malanara:BAAALgADCgEJAQABLgAECgkJJgAYABEUAA==.Malxt:BAAALgADCgYJBwAAAA==.Manabuns:BAABLgAECn8sAAIYAAgJNRg7XgDEAQAYAAgJNRg7XgDEAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8lAAICAAkJ/RRKQgAeAgACAAkJ/RRKQgAeAgAAAA==.Markruffalo:BAAALgAECgYJDAAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn86AAIWAAkJaBu9FABKAgAWAAkJaBu9FABKAgAAAA==.',
Mc='Mckay:BAAALgAECggJEwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8mAAInAAgJRBSzBACjAQAnAAgJRBSzBACjAQAAAA==.Megapunk:BAAALgAECgcJEwAAAA==.Mellmaan:BAAALgAFFAIJAgAAAA==.Melys:BAAALgAECgcJEgAAAA==.Meteorite:BAAALgAECgYJCQAAAA==.Meudayr:BAABLgAECn8jAAIMAAkJASBxBADRAgAMAAkJASBxBADRAgAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.Mezagog:BAAALgAECgYJEgAAAA==.',
Mi='Mikehammer:BAAALgADCgcJFQAAAA==.Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAACLgAFFH8NAAISAAUJwww5KwDoAAASAAUJwww5KwDoAAAuAAQKfx4AAhIACAltHCISAJICABIACAltHCISAJICAAAA.Mittenss:BAAALgADCgIJAgAAAA==.',
Mo='Moistblanket:BAAALgAECgUJBwAAAA==.Mojorisin:BAABLgAECn8jAAIDAAkJ6xoUDgBHAgADAAkJ6xoUDgBHAgAAAA==.Moobear:BAABLgAECn8aAAIMAAgJLRsEAgAmAgAMAAgJLRsEAgAmAgAAAA==.Moogie:BAAALgAFFAEJAQABLgAFFAUJFAAOABscAA==.Moonchiken:BAAALgAECgEJCgAAAA==.Moozlock:BAABLgAECn8rAAIhAAkJEhKNTQCyAQAhAAkJEhKNTQCyAQAAAA==.Moscovio:BAAALgAFFAIJBAABLgAFFAMJBQACAFITAA==.Mosspaws:BAABLgAECn82AAMNAAkJbiTQBgBLAwANAAkJbiTQBgBLAwAGAAQJZB8ONgA+AQAAAA==.',
Mt='Mtndewyou:BAAALgAECgcJEQAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.Mutterutters:BAAALgAECgEJAgAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.Myrollin:BAAALgAECgIJAgAAAA==.Myrothan:BAAALgAECgUJBgAAAA==.',
Na='Naetara:BAAALgADCgEJAQAAAA==.Narfiy:BAAALgADCgEJAQAAAA==.Narisanna:BAAALgAFFAEJAgAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBgAAAA==.Ninkarrak:BAAALgAECgcJCAAAAA==.',
Nm='Nme:BAABLgAECn8lAAMYAAkJoBAOXADKAQAYAAkJoBAOXADKAQAnAAYJiw9LCQBWAQAAAA==.',
No='Nocturnos:BAACLgAFFH8HAAIhAAMJ/RNbcwDaAAAhAAMJ/RNbcwDaAAAuAAQKfzIAAyEACQlLIEQbAIACACEACQlLIEQbAIACABwAAgn3IOguAGIAAAAA.Noctyr:BAAALgAECgcJCAAAAA==.Noggin:BAABLgAECn8rAAMTAAkJRyH/BAAcAwATAAkJRyH/BAAcAwACAAgJ/BCGagCaAQAAAA==.Nonform:BAABLgAECn89AAQGAAkJgRvRDACKAgAGAAkJgRvRDACKAgALAAEJwRXwTAA/AAANAAEJdAED7AAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECggJIgAXAH0WAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQAPAAAAAA==.Novamancer:BAAALgAECgIJAgAAAA==.Noxta:BAAALgAECggJEgAAAA==.',
Nu='Numonixx:BAACLgAFFH8hAAMHAAYJ7A6ZBgDqAAAbAAYJCA2iKQAiAQAHAAQJKwuZBgDqAAAuAAQKfzoAAwcACQkFH4oCAJMCAAcACAmsIIoCAJMCABsACAnGG0IUADsCAAAA.Nutlessfred:BAAALgAECgEJAQAAAA==.',
Ny='Nymage:BAABLgAECn9tAAIYAAkJSx7iAwCyAgAYAAkJSx7iAwCyAgAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogkushe:BAAALgAECgQJCgAAAA==.Ogmund:BAAALgAECgcJEgAAAA==.',
Oh='Ohnospiders:BAABLgAECn8yAAMOAAkJpBfNNAAsAgAOAAkJpBfNNAAsAgAJAAQJ4RRYIQDDAAAAAA==.Ohpig:BAAALgAECgMJAwAAAA==.',
Ok='Okaerisan:BAABLgAECn8XAAIVAAkJoRZmFQB8AQAVAAkJoRZmFQB8AQAAAA==.',
Ol='Olord:BAABLgAFFH8GAAICAAIJWxiDQgCZAAACAAIJWxiDQgCZAAAAAA==.',
Om='Omarcuthlink:BAAALgAECgEJAQABLgAFFAQJDQAcAHkRAA==.Omgbbqq:BAAALgAECggJCAABLgAFFAMJDgAEADMcAA==.',
On='Onilecram:BAAALgAECgIJAwAAAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.Oomkin:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECggJEQAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Os='Ostie:BAABLgAFFH8IAAIhAAMJUBKwMQDAAAAhAAMJUBKwMQDAAAABLgAFFAQJEQAUAIoiAA==.',
Ou='Outlast:BAACLgAFFH8QAAICAAQJHhYZOwA1AQACAAQJHhYZOwA1AQAuAAQKfy8AAgIACQm1HbQRAAQDAAIACQm1HbQRAAQDAAAA.',
Pa='Paants:BAABLgAECn8kAAIlAAkJugwEHwA7AQAlAAkJugwEHwA7AQAAAA==.Pacid:BAAALgAECgYJDAAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Pakal:BAAALgAECgUJEgAAAA==.Palebull:BAAALgADCgYJCAAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8fAAIXAAkJ8h5MCgB1AgAXAAkJ8h5MCgB1AgAuAAQKfzMAAhcACQkEJZQEAD0DABcACQkEJZQEAD0DAAAA.Paracotos:BAAALgADCgUJBQAAAA==.Parmageddon:BAAALgAFFAEJAQABLgAFFAQJDgAlAPggAA==.Parmigiano:BAAALgADCgEJAQABLgAFFAQJDgAlAPggAA==.Parmrageiano:BAABLgAFFH8OAAIlAAQJ+CAHDQBdAQAlAAQJ+CAHDQBdAQAAAA==.Parms:BAABLgAECn8ZAAQDAAgJ+xNBJgBrAQADAAgJ6xFBJgBrAQAFAAYJhQxETQAcAQAEAAIJORANowCFAAABLgAFFAQJDgAlAPggAA==.Parmy:BAAALgAECgEJAQAAAA==.Pastry:BAABLgAFFH8IAAIOAAMJUBqsOgDuAAAOAAMJUBqsOgDuAAABLgAFFAgJDQASAFISAA==.',
Pe='Peanought:BAABLgAECn8sAAMJAAkJXBoBBgDJAQAJAAgJsRcBBgDJAQAOAAkJhxMUYQCnAQAAAA==.Peidro:BAABLgAECn8bAAICAAcJAA9GqAArAQACAAcJAA9GqAArAQAAAA==.Pentacles:BAABLgAECn8tAAIMAAkJsCA5BwCDAgAMAAkJsCA5BwCDAgAAAA==.',
Pi='Pijak:BAABLgAECn8dAAIVAAkJAxeTAgDjAQAVAAkJAxeTAgDjAQAAAA==.Pinkpaw:BAABLgAECn8iAAQMAAkJFh/EBADJAgAMAAkJFh/EBADJAgANAAUJthqjSABsAQALAAEJuBKESgBEAAAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8JAAMfAAMJ3iTvCABGAQAfAAMJ3iTvCABGAQAUAAEJlCPlOABjAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCQAfAN4kAA==.Postscalone:BAAALgAECgYJBwAAAA==.Potatoes:BAABLgAECn8VAAMdAAgJBgiWHABpAQAdAAgJBgiWHABpAQAhAAIJCQJIFAE6AAAAAA==.',
Pr='Primalcat:BAAALgADCgkJCQAAAA==.Pruflas:BAABLgAECn8aAAIOAAgJZAtAjgBJAQAOAAgJZAtAjgBJAQAAAA==.',
Ps='Psycodk:BAACLgAFFH8JAAIOAAUJxxztSwBaAQAOAAUJxxztSwBaAQAuAAQKfxYAAg4ACAmYGD9sAI0BAA4ACAmYGD9sAI0BAAAA.',
Pu='Puffdaddie:BAAALgAECgUJBwABLgAECggJJwACAMkfAA==.Pumpin:BAABLgAECn8XAAIUAAUJFCTFKgBnAQAUAAUJFCTFKgBnAQAAAA==.Punkthor:BAAALgAECgIJAgAAAA==.Purgemepappy:BAAALgADCgEJAQAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
['Pä']='Päcid:BAAALgAECgYJCQAAAA==.',
Qk='Qkn:BAABLgAECn8VAAIQAAYJnwxeigDGAAAQAAYJnwxeigDGAAAAAA==.',
Qu='Quickswipe:BAABLgAFFH8GAAIoAAMJxSAgIgAVAQAoAAMJxSAgIgAVAQABLgAFFAgJPAAdAHgfAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgYJCwABLgAECgcJCQAPAAAAAA==.Ralee:BAAALgAECgEJAQAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Rastabution:BAAALgAECgkJAQAAAA==.Ratoncita:BAAALgAECgEJAwAAAA==.Raynne:BAAALgAECgIJAgAAAA==.Rayzee:BAAALgADCgUJBQAAAA==.Rayzi:BAAALgAECgEJAQAAAA==.Razerblade:BAAALgAFFAEJAQAAAA==.',
Re='Reaperjoe:BAAALgAFFAEJAgAAAA==.Rehab:BAACLgAFFH8JAAICAAMJRRvULADYAAACAAMJRRvULADYAAAuAAQKfxUAAgIACQlbHK4vAGQCAAIACQlbHK4vAGQCAAEuAAUUBwkIAB4AvBMA.Rehna:BAAALgAECgYJBgABLgAFFAQJEgAIAM0RAA==.Rek:BAAALgAECgEJAQABLgAECgkJIwAMAAEgAA==.Rektributio:BAACLgAFFH8kAAICAAkJoyDCBACYAgACAAkJoyDCBACYAgAuAAQKfzcAAgIACQkgJecGADgDAAIACQkgJecGADgDAAAA.Restø:BAAALgAECgEJAQAAAA==.Resurection:BAAALgAECgYJEgAAAA==.Revalation:BAACLgAFFH8GAAINAAMJERVVGQCpAAANAAMJERVVGQCpAAAuAAQKfycAAg0ACQlSH9wVAJoCAA0ACQlSH9wVAJoCAAAA.Revenancer:BAAALgAECgEJAwAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgAPAAAAAA==.Rhydon:BAAALgADCgQJBAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Riachu:BAAALgAECgcJDAAAAA==.Ribeyejoe:BAAALgADCgEJAQAAAA==.Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAACLgAFFH8JAAMWAAMJ5xmBIACuAAAWAAMJNRmBIACuAAAlAAIJlxhkIQCNAAAuAAQKfzgAAxYACQmEHx8WAD4CABYACAl2IB8WAD4CACUACAkPGswDAI0BAAAA.Roadtrip:BAAALgAECgMJBAAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJBAAAAA==.Rockiden:BAAALgADCgEJAQAAAA==.Roflmäo:BAAALgAECgMJAwAAAA==.Rosco:BAAALgAECgEJAQABLgAFFAMJAwAPAAAAAA==.Rottingslow:BAABLgAFFH8IAAIIAAMJ9wDZKwBpAAAIAAMJ9wDZKwBpAAABLgAFFAkJJwAKAIEgAA==.Rowzdower:BAAALgAECgMJAwAAAA==.',
['Râ']='Râke:BAAALgADCgkJCQABLgAECggJHwAEADYLAA==.',
Sa='Sanford:BAAALgAECgUJBQAAAA==.Saragos:BAAALgADCgcJBgABLgAFFAgJGQAYADESAA==.Satine:BAAALgAECgMJAwAAAA==.Saucerdote:BAABLgAECn8eAAMjAAkJmBWxHwDQAQAjAAcJGxexHwDQAQAeAAkJFAlhMQBWAQAAAA==.Saucy:BAAALgAECgEJAQAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAgJGQAYADESAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAACLgAFFH8KAAIXAAUJ9RJpTAAFAQAXAAUJ9RJpTAAFAQAuAAQKfysAAhcACQl7H6kPAMYCABcACQl7H6kPAMYCAAAA.Selkie:BAABLgAECn8sAAIRAAkJEBA5DgDMAQARAAkJEBA5DgDMAQAAAA==.Seragosa:BAAALgAFFAEJAQABLgAFFAgJGQAYADESAA==.',
Sh='Shadowmaven:BAAALgAECgcJBwAAAA==.Shakakhan:BAAALgAECgYJDQABLgAECgYJHgACAGccAA==.Shambeau:BAAALgADCgQJBAAAAA==.Shamrun:BAAALgADCgQJBQAAAA==.Shamshielder:BAECLgAFFH8TAAQJAAYJBhJPEQAKAQAJAAQJZwpPEQAKAQAKAAQJsBUAHQB2AAAOAAIJMgdBmABCAAAuAAQKfy0ABAoACQmZI5cFAM0CAAoACQmZI5cFAM0CAAkABgmlGxwOAJQBAA4AAQm5CXeNASkAAAAA.Shapper:BAAALgAECgYJDQAAAA==.Sharick:BAAALgAFFAEJAgAAAA==.Shawdrake:BAAALgAFFAMJAwABLgAFFAMJBwASABoCAA==.Shawlee:BAACLgAFFH8HAAMSAAMJGgIqLwBVAAASAAIJ9QIqLwBVAAAQAAMJJQLqUAA3AAAuAAQKfy0AAxAACAnMECRcAEkBABAACAnMECRcAEkBABIACAk7CnVWAOEAAAAA.Sheezie:BAACLgAFFH8MAAMQAAMJExrdPADwAAAQAAMJExrdPADwAAARAAIJWxF/DQCCAAAuAAQKf0kAAxAACQmkIVoFAF0DABAACQmkIVoFAF0DABEACQnfGDULAAQCAAAA.Shellcow:BAAALgAECgYJBgABLgAECgkJIgAZAG0gAA==.Shellter:BAAALgAECgEJAgABLgAECgkJIgAZAG0gAA==.Shellwit:BAAALgAECgMJBgABLgAECgkJIgAZAG0gAA==.Sheph:BAAALgAFFAEJAQAAAA==.Shetmage:BAACLgAFFH8fAAIYAAkJugrUNQCSAQAYAAkJugrUNQCSAQAuAAQKfykAAhgACQnDIAEkAI0CABgACQnDIAEkAI0CAAAA.Shettdh:BAAALgAECgUJCQAAAA==.Shettrah:BAABLgAECn8UAAIGAAYJ+hoeKwB8AQAGAAYJ+hoeKwB8AQABLgAFFAkJHwAYALoKAA==.Shienro:BAAALgAECgQJBAABLgAECgQJCQAPAAAAAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAABLgAECn8oAAICAAkJOhRKYACwAQACAAkJOhRKYACwAQAAAA==.Shuck:BAAALgAECgQJBAABLgAFFAQJFgAWAJEiAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Sibyx:BAAALgAECgYJEgABLgAECgYJHgACAGccAA==.Siickboy:BAAALgAECgQJCQAAAA==.Sijious:BAAALgAECgYJDAAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.Singularity:BAAALgAECgQJBAABLgAECgYJHgACAGccAA==.',
Sk='Skinable:BAAALgAFFAEJAQAAAA==.Skora:BAAALgADCgIJAgABLgAECgkJJQACAP0UAA==.Skyland:BAAALgADCgcJDQABLgAFFAkJJQAaAFsbAA==.Skyli:BAAALgAECgUJCAABLgAECgkJKAAQACsgAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Sneez:BAAALgAFFAEJAQABLgAFFAQJEwAWAEgVAA==.Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAACLgAFFH8TAAITAAUJZxqSIgALAQATAAUJZxqSIgALAQAuAAQKfycAAhMACQmfH7wIAOMCABMACQmfH7wIAOMCAAAA.Sorrie:BAAALgAECgEJAQAAAA==.Sortiarius:BAAALgADCgkJCQAAAA==.',
Sp='Spud:BAAALgADCgcJBwABLgAECgYJFgAEAI8fAA==.Spyroh:BAABLgAECn8bAAQHAAYJ6BLuGQBlAQAHAAYJcBDuGQBlAQAbAAUJGBJMSAAKAQAaAAEJ2wA4TwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAQJEgAIAM0RAA==.',
St='Stankydk:BAACLgAFFH8RAAMOAAcJRBTiKQDBAQAOAAYJRBTiKQDBAQAKAAEJAACCagAAAAAuAAQKfzIAAg4ACQk+JdAFAEsDAA4ACQk+JdAFAEsDAAAA.Stankyeyes:BAAALgAECgYJBgAAAA==.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Staticdh:BAABLgAFFH8fAAIXAAYJ6yLhCwABAgAXAAYJ6yLhCwABAgABLgAFFAkJOwAYAMMgAA==.Steakhead:BAABLgAECn8pAAIGAAYJxAsXTQDYAAAGAAYJxAsXTQDYAAAAAA==.Stinkbombs:BAACLgAFFH8TAAIYAAYJeQhCNwDoAAAYAAYJeQhCNwDoAAAuAAQKfxcAAhgACQnEFNN4AIcBABgACQnEFNN4AIcBAAAA.Stinkerz:BAAALgAECgIJAgABLgAECgkJIgAZAG0gAA==.Stonegut:BAAALgAECggJDwAAAA==.Stunanddone:BAABLgAECn8eAAIoAAcJMA4ABgA3AQAoAAcJMA4ABgA3AQAAAA==.Stupidkitty:BAAALgAECgMJAgAAAA==.',
Su='Subrogue:BAABLgAFFH8FAAIkAAIJlhnjMQCWAAAkAAIJlhnjMQCWAAABLgAFFAMJBQAgABkGAA==.Suffragan:BAAALgAECgIJAgAAAA==.Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJEAAAAA==.Supreme:BAACLgAFFH8IAAIXAAMJXhrBXwDQAAAXAAMJXhrBXwDQAAAuAAQKfxkAAhcACAl4I24YAMMCABcACAl4I24YAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAMJAwABLgAFFAUJFgAoAIUeAA==.Swayaim:BAABLgAFFH8LAAIEAAQJEgaDVAD/AAAEAAQJEgaDVAD/AAAAAA==.Sweatypits:BAAALgAECgYJBgABLgAFFAMJDAAQABMaAA==.Swordsaint:BAAALgAECgEJAQAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAYJDgATAO8RAA==.Sylphrena:BAACLgAFFH8TAAIIAAUJHxaxGAD3AAAIAAUJHxaxGAD3AAAuAAQKfygAAggACQlQHogIAMMCAAgACQlQHogIAMMCAAAA.',
['Sí']='Sínful:BAABLgAECn8qAAIFAAkJxB+BBABqAgAFAAkJxB+BBABqAgAAAA==.',
Ta='Tacow:BAAALgAECggJEQAAAA==.Tahwe:BAAALgAECgIJAgAAAA==.Talethen:BAABLgAECn8gAAMbAAkJdRmPMgBqAQAbAAkJ8xePMgBqAQAHAAUJMxgpIAAtAQAAAA==.Talgrin:BAAALgAECgYJBgAAAA==.Talla:BAABLgAECn8oAAIQAAkJKyCtCAAmAwAQAAkJKyCtCAAmAwAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgAECgEJAgABLgAECgYJFAAYAD0YAA==.Tellus:BAAALgADCgcJCwAAAA==.Tempesttempi:BAAALgADCgcJBwAAAA==.Tewshort:BAAALgAECgQJCAABLgAFFAQJEAACAB4WAA==.',
Th='Thatbox:BAAALgAECgQJBQAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAABLgAECn8lAAINAAkJVyH2AABDAwANAAkJVyH2AABDAwAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAABLgAECn8UAAMUAAgJBAUFXgCfAAAfAAcJQQRZWQDeAAAUAAcJQgQFXgCfAAAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thordak:BAAALgAFFAIJAwABLgAFFAMJCQAWAOcZAA==.Thorfyna:BAABLgAECn8kAAImAAkJRxRRCQDXAQAmAAkJRxRRCQDXAQAAAA==.Threzk:BAABLgAECn8eAAIdAAkJew7/DgBPAQAdAAkJew7/DgBPAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.Thunderstorm:BAAALgAECgcJDAAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8UAAIXAAgJOxJMEQCnAQAXAAgJOxJMEQCnAQAuAAQKfy8AAhcACQmGIoMLAOsCABcACQmGIoMLAOsCAAAA.Tontiamat:BAABLgAECn9AAAMbAAkJihqiFwAaAgAbAAkJihqiFwAaAgAHAAYJawo5IAAsAQAAAA==.Tontier:BAABLgAECn8iAAQNAAkJAQ/VSABsAQANAAgJYg7VSABsAQAMAAQJSg5hSwB9AAALAAcJjwzaCwB1AAABLgAECgkJQAAbAIoaAA==.Totembeans:BAAALgAECgQJCwAAAA==.Totemshocker:BAECLgAFFH8HAAMSAAQJJAvVEQDXAAASAAMJfAbVEQDXAAAQAAIJrgTWRABMAAAuAAQKfxYAAxIACAkqGQUXAGACABIACAkqGQUXAGACABAAAQkBDHPeACoAAAEuAAUUBgkTAAkABhIA.Toxicshadow:BAAALgADCgQJBgAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAACLgAFFH8OAAITAAYJ7xGlEQCoAQATAAYJ7xGlEQCoAQAuAAQKfxwABBMACQlOH5QMAMUCABMACAnDHpQMAMUCAAIABwksDjq3ABcBABUAAgmgE6FNADgAAAAA.Trashfire:BAACLgAFFH8KAAMIAAQJIA50GQDvAAAIAAQJIA50GQDvAAAjAAIJwgF2FgB7AAAuAAQKfx0ABAgACAkXHSYQAGUCAAgACAkXHSYQAGUCAB4ABQknFXw2ADkBACMAAwluEWhAAK0AAAEuAAUUBgkOABMA7xEA.Treeple:BAABLgAECn8iAAMNAAkJ5xZvSwBhAQANAAcJUBNvSwBhAQAGAAUJbA5zQQAIAQAAAA==.Treily:BAABLgAECn8fAAIEAAgJNgs4GAAhAQAEAAgJNgs4GAAhAQAAAA==.Tresleches:BAABLgAECn8tAAICAAkJLRJBXgC1AQACAAkJLRJBXgC1AQAAAA==.Tricket:BAABLgAECn9TAAMkAAkJeCDLAwDtAgAkAAkJeCDLAwDtAgAWAAYJKBl1VAD6AAAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAdAAYIAQ==.Trueshotjoe:BAAALgAECgEJAgAAAA==.Truestorm:BAACLgAFFH8TAAICAAMJDAjFPgCkAAACAAMJDAjFPgCkAAAuAAQKfyoAAgIACQkNDUt7AHgBAAIACQkNDUt7AHgBAAAA.Truheals:BAAALgAECgYJCgAAAA==.',
Tu='Tuchi:BAACLgAFFH8ZAAMnAAUJCx+8AQAIAQAYAAUJkByVHgBQAQAnAAMJaxy8AQAIAQAuAAQKfyYAAycABwm9IzoDAPgBABgABwliIrkyAKgCACcABgnQIjoDAPgBAAAA.Tumblestone:BAAALgAECgEJAQAAAA==.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAkJHwAXAPIeAA==.',
['Tà']='Tàcobelle:BAACLgAFFH8JAAIFAAIJoxN5EACLAAAFAAIJoxN5EACLAAAuAAQKfx0AAgUACQnXIAABAC0CAAUACQnXIAABAC0CAAEuAAQKCAksABgANRgA.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Vaelen:BAAALgAECgEJAQABLgAECgkJGAAhAJUaAA==.Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgAPAAAAAA==.Valhalla:BAAALgAECgYJBgAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIQAAMJriKiOgD4AAAQAAMJriKiOgD4AAAuAAQKfzEAAxAACQllGz8SAIQCABAACQllGz8SAIQCABIABgkTGpE2AF8BAAAA.Varanis:BAACLgAFFH8JAAIEAAMJnxZuDAD/AAAEAAMJnxZuDAD/AAAuAAQKfxkAAgQACQlkIWMLAOgCAAQACQlkIWMLAOgCAAAA.',
Ve='Vegh:BAACLgAFFH8HAAImAAMJYBglCQDAAAAmAAMJYBglCQDAAAAuAAQKf04AAiYACQnzH1wDAKoCACYACQnzH1wDAKoCAAAA.Vem:BAABLgAECn8uAAIbAAkJsR1IEABlAgAbAAkJsR1IEABlAgAAAA==.Veriale:BAAALgAECggJEwAAAA==.Verra:BAABLgAECn85AAICAAkJWhs3JgBrAgACAAkJWhs3JgBrAgAAAA==.',
Vi='Vitriol:BAACLgAFFH8FAAIWAAMJfA+ZJQCQAAAWAAMJfA+ZJQCQAAAuAAQKfyEAAhYABwlnGDAxAIgBABYABwlnGDAxAIgBAAAA.Vivid:BAAALgADCgUJBQAAAA==.',
Vo='Voidbeaver:BAAALgAECgcJCwAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAACLgAFFH8OAAMcAAQJoBMWBgAhAQAcAAQJoBMWBgAhAQAdAAEJYQcDKwA8AAAuAAQKfx8AAhwACQl2IqsBAMoCABwACQl2IqsBAMoCAAAA.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgcJEAAPAAAAAA==.Vyrros:BAAALgAECgkJEAAAAA==.',
Wa='Walji:BAABLgAECn8eAAMQAAgJyhtyFwBaAgAQAAgJyhtyFwBaAgASAAEJWwumrwApAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgAECgIJBAAAAA==.Wandy:BAABLgAECn86AAIhAAkJnxqPBgDGAQAhAAkJnxqPBgDGAQAAAA==.Wangstah:BAABLgAECn8cAAIEAAkJMiReDwDVAgAEAAkJMiReDwDVAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAIWAAYJNhQUSgB8AQAWAAYJNhQUSgB8AQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJDgAAAA==.Wawatesi:BAAALgAECgMJAwAAAA==.Waytogoteam:BAACLgAFFH8OAAIEAAMJMxzFMgDbAAAEAAMJMxzFMgDbAAAuAAQKfzgAAgQACQkpJJYLAPcCAAQACQkpJJYLAPcCAAAA.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8ZAAMYAAgJMRK0KgDJAQAYAAcJHBS0KgDJAQAZAAMJlQs+BQCCAAAuAAQKfzMABBgACQnEJH8NAA4DABgACQk3JH8NAA4DABkABgm+I3wDANkBACcAAQmPIMgWAGQAAAAA.Wenya:BAAALgADCgcJDgAAAA==.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgQJBAAAAA==.',
Wo='Woodyy:BAABLgAECn8oAAIOAAgJcBCuFAARAQAOAAgJcBCuFAARAQAAAA==.Woog:BAAALgAECgcJEgAAAA==.Wox:BAAALgAECgkJEAAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wu='Wujustyle:BAAALgAECgcJBwABLgAFFAUJCQAOAMccAA==.Wulfgar:BAAALgAFFAEJAQAAAA==.',
Wy='Wyldspirit:BAABLgAECn8sAAIEAAkJzBLNEABrAQAEAAkJzBLNEABrAQAAAA==.Wyreless:BAAALgADCgYJBgABLgAECgkJNQALABUWAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgAECgEJAQAAAA==.',
Xe='Xe:BAAALgAECgYJBgABLgAECgkJUwAkAHggAA==.',
Xr='Xrind:BAAALgADCgEJAQAAAA==.',
Xu='Xub:BAAALgAECgEJAQAAAA==.',
Ya='Yaass:BAAALgAECgMJAwAAAA==.Yama:BAAALgAECgQJBAAAAA==.',
Ye='Yem:BAACLgAFFH88AAQdAAgJeB9mAgDMAQAdAAcJwB5mAgDMAQAhAAYJOx4EPABcAQAcAAIJYSIrHgBTAAAuAAQKfzYAAx0ACQmiIzkGAGwCAB0ABgncIzkGAGwCACEABgliI1VJAO4BAAAA.',
Yo='Yoverre:BAAALgAECgMJAwAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAAPAAAAAA==.Zanzabar:BAABLgAECn8XAAICAAkJvBlHQAAGAgACAAkJvBlHQAAGAgAAAA==.Zaraelitha:BAAALgAECggJDgAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgYJCQABLgAECgkJRwAIADIgAA==.Zeodrik:BAABLgAECn8cAAIWAAcJYRmxNQDSAQAWAAcJYRmxNQDSAQAAAA==.',
Zh='Zhenya:BAACLgAFFH8TAAIYAAUJ+hKwYgAdAQAYAAUJ+hKwYgAdAQAuAAQKfycAAxgACQltGJtLAPgBABgACQltGJtLAPgBACcABAkvD+gOANUAAAAA.',
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
