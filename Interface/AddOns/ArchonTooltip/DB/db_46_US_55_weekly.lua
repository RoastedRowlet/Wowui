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
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abracadava:BAAALgAECgQJBQAAAA==.',
Ac='Acheniris:BAAALgAECgUJDQAAAA==.',
Ad='Adeaino:BAAALgAECgUJCAAAAA==.Adonix:BAAALgAECgEJAQAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgUJBwAAAA==.',
Ag='Agrippa:BAACLgAFFH8HAAIBAAQJyQE8CgCaAAABAAQJyQE8CgCaAAAuAAQKfxwAAgEACAmgDo4JAKMBAAEACAmgDo4JAKMBAAAA.',
Ah='Ahndhrez:BAAALgAECgcJBgAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECggJEwAAAA==.Aioli:BAABLgAECn8kAAQCAAkJ1BvXEgARAgACAAkJuRjXEgARAgADAAYJ7hdaRwCUAQAEAAUJcRo4SAAzAQAAAA==.Airwavez:BAAALgAECgcJDQAAAA==.',
Al='Alchemorph:BAABLgAECn8XAAIFAAgJSwnNPQAYAQAFAAgJSwnNPQAYAQAAAA==.Aldormu:BAABLgAECn8mAAIGAAkJuAx8CgB3AQAGAAkJuAx8CgB3AQAAAA==.Aliyah:BAEALgADCgIJAgABLgAECgkJJgAHAMoZAA==.Allura:BAACLgAFFH8SAAIHAAQJzRGaHADTAAAHAAQJzRGaHADTAAAuAAQKfyQAAgcACQmLGQ4WACwCAAcACQmLGQ4WACwCAAAA.Altra:BAACLgAFFH8TAAMIAAUJDguIEQAHAQAIAAQJDguIEQAHAQAJAAEJAACpCwAAAAAuAAQKfykAAwgACQl5HFYCAJ8CAAgACQl5HFYCAJ8CAAkABwl7A1orAOQAAAAA.Alyvia:BAAALgADCgEJAgAAAA==.',
Am='Amoeta:BAABLgAECn81AAQKAAkJFRZiDwC/AQAKAAgJ0hViDwC/AQALAAkJAg6rIABJAQAMAAcJyQhAaQD4AAAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgQJBAAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgAECgIJAwAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angelkinq:BAAALgAECgEJAgAAAA==.Angryapples:BAAALgAECgQJCQAAAA==.Annihilation:BAAALgAECgUJCQAAAA==.Antinous:BAABLgAECn8qAAIEAAgJ3gw6EwArAQAEAAgJ3gw6EwArAQAAAA==.',
Ap='Apathia:BAAALgAECgEJAQABLgAECgYJCAANAAAAAA==.Aphrodité:BAAALgAECgIJAgAAAA==.',
Ar='Arcstorm:BAAALgAECgYJDAAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Ashenback:BAACLgAFFH8GAAMOAAMJXAqFYgCEAAAOAAMJXAqFYgCEAAAPAAEJkQkKHAA+AAAuAAQKfxkABA8ACAl8GlEKABUCAA8ACAkxGlEKABUCABAAAwn1HoFJAA4BAA4AAgkaGuecAJcAAAEuAAUUBgkOABEA7xEA.Asomyrh:BAABLgAECn8lAAMRAAkJmxUGGgA1AgARAAkJmxUGGgA1AgASAAEJPQHV0wESAAAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgYJCAAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgAECgQJBAAAAA==.',
Av='Averyl:BAAALgAECgUJBQAAAA==.Aviendha:BAAALgAECgYJCgAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAITAAgJLQptKgCKAQATAAgJLQptKgCKAQAAAA==.',
Az='Azenith:BAABLgAECn8cAAMSAAYJgRx/agCaAQASAAYJgRx/agCaAQAUAAEJrQjGVAAnAAAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bamboozle:BAAALgADCgcJBwAAAA==.Bananer:BAABLgAECn8iAAIVAAkJeBRRIwDZAQAVAAkJeBRRIwDZAQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Bb='Bbqlol:BAAALgAECgYJBwABLgAECgYJHgASAGccAA==.',
Be='Beaugersugar:BAAALgAECgQJBQAAAA==.Beebler:BAABLgAECn8YAAIPAAgJnhfoDgDCAQAPAAgJnhfoDgDCAQAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgAECgcJCAAAAA==.Beowulf:BAAALgAECgEJAwAAAA==.Bestt:BAAALgAECgQJCQAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Bigbluenfab:BAAALgAECgIJAgAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigholylady:BAAALgADCgkJCQAAAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigocagler:BAAALgAECgcJAQAAAA==.Bigolchungus:BAABLgAECn8eAAMUAAkJwRpuCQA7AgAUAAgJeBluCQA7AgASAAUJ6BjGuwAOAQAAAA==.Bigpapadots:BAAALgAECgMJBAAAAA==.Bigpéet:BAAALgAECgIJAgAAAA==.Bigshizz:BAAALgAECgQJBgABLgAECgcJFQAFAAEhAA==.Bippysmasher:BAABLgAECn8kAAIWAAkJaxIzSACuAQAWAAkJaxIzSACuAQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.',
Bl='Blacblood:BAABLgAECn8fAAIIAAkJYRHNBQDSAQAIAAkJYRHNBQDSAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJEQAAAA==.Blindweiss:BAAALgAFFAEJAQABLgAFFAcJFgAXABwUAA==.Blinkies:BAABLgAECn8iAAMYAAkJbSD5AADWAgAYAAkJbSD5AADWAgAXAAUJlg8pvgAMAQAAAA==.Blinkster:BAAALgAECgEJBAAAAA==.Bloodfushion:BAAALgADCgYJBgAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgAECgMJAwANAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8QAAIDAAcJGRncEADeAQADAAcJGRncEADeAQAuAAQKfysAAgMACQmNIyoKAAYDAAMACQmNIyoKAAYDAAAA.Boolala:BAAALgAECgYJCQABLgAECgkJMAASAIYRAA==.Borstenne:BAACLgAFFH8SAAIZAAUJGR3YUQBOAQAZAAUJGR3YUQBOAQAuAAQKfykAAhkACQm7JEkTANQCABkACQm7JEkTANQCAAAA.',
Br='Brake:BAACLgAFFH8KAAIZAAMJnxFZqwDIAAAZAAMJnxFZqwDIAAAuAAQKfyYAAhkACAlXHvU1AF8CABkACAlXHvU1AF8CAAAA.Brese:BAAALgAECgIJAgABLgAFFAUJEwAWAHIZAQ==.Breseayaya:BAACLgAFFH8TAAIWAAUJchlVPwAqAQAWAAUJchlVPwAqAQAuAAQKfy0AAhYACQkrIXoNANkCABYACQkrIXoNANkCAAAA.Breseshh:BAAALgAECgcJEwABLgAFFAUJEwAWAHIZAA==.Brickbeard:BAACLgAFFH8LAAIaAAQJeREOBQA4AQAaAAQJeREOBQA4AQAuAAQKfy0AAxoACQl0FawGAA8CABoACQl0FawGAA8CABsABwnDDeUZAH0BAAAA.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJEgABLgAFFAgJGQASAJ0cAA==.Bricksquad:BAAALgAECgMJAwABLgAFFAMJBQAWAHodAA==.Brickthrow:BAACLgAFFH8ZAAMSAAgJnRy1HQCSAQASAAYJ1hq1HQCSAQARAAMJOQjULADIAAAuAAQKfzMAAxIACQmsJBcIACsDABIACQmsJBcIACsDABEABQlyBERyAG4AAAAA.Bronkle:BAAALgAECgUJBQABLgAFFAQJCwAaAHkRAA==.',
Bu='Buhleed:BAAALgAECgIJAgAAAA==.Burgerburn:BAAALgAECgUJBgAAAA==.',
By='Bytheway:BAABLgAECn8WAAIcAAgJ4RN5LgBnAQAcAAgJ4RN5LgBnAQAAAA==.',
['Bà']='Bàbÿ:BAAALgAECgcJDgAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAACLgAFFH8TAAIMAAUJPxBoMADvAAAMAAUJPxBoMADvAAAuAAQKfzEABAwACQm4I8cIACsDAAwACQm4I8cIACsDAAUAAglbGzp8AE4AAAsAAQlKAac3ABkAAAAA.Cadsune:BAAALgAECgYJDAAAAA==.Caelesti:BAABLgAECn8oAAMHAAgJVxMcIADCAQAHAAgJVxMcIADCAQAcAAgJxhabJgCYAQAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAgAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQABLgAFFAgJHAAdAG8YAA==.Chelbur:BAAALgADCgEJAQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chosmuke:BAAALgAECgEJAwAAAA==.Chowderhead:BAABLgAECn8UAAIbAAYJYxzhDgDcAQAbAAYJYxzhDgDcAQAAAA==.',
Ci='Cileb:BAACLgAFFH8GAAIXAAUJSBjEYAAgAQAXAAUJSBjEYAAgAQAuAAQKfzUAAhcACQmkJAUMABkDABcACQmkJAUMABkDAAAA.Civik:BAABLgAECn9KAAIDAAkJciOLCQAMAwADAAkJciOLCQAMAwAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAFFAMJBQAWAHodAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAACLgAFFH8SAAISAAQJ0xXpPgAtAQASAAQJ0xXpPgAtAQAuAAQKfzAAAhIACQldGmE9AA8CABIACQldGmE9AA8CAAAA.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAFFAQJBQAWAAkFAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJJwAJAAkjAA==.Copperit:BAABLgAECn8nAAIJAAkJCSOQAgBDAwAJAAkJCSOQAgBDAwAAAA==.Cornburglar:BAACLgAFFH8NAAIVAAQJwB9wEQB7AQAVAAQJwB9wEQB7AQAuAAQKfzoAAhUACAlcJW4IANkCABUACAlcJW4IANkCAAAA.Cowtaclysmic:BAACLgAFFH8FAAIZAAIJOgfP3wCFAAAZAAIJOgfP3wCFAAAuAAQKfyMAAxkACAkGE6GAAGIBABkACAmaDKGAAGIBAAkABQlKFmUqAAUBAAAA.',
Cr='Crackersz:BAABLgAECn8WAAMOAAcJHQgGigDHAAAOAAcJHQgGigDHAAAQAAMJGATOhwBgAAAAAA==.Cranjis:BAABLgAECn9NAAIeAAkJ9iFpBwAoAwAeAAkJ9iFpBwAoAwAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Crunchwrap:BAABLgAECn8qAAIFAAkJDA8JJwCWAQAFAAkJDA8JJwCWAQAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgcJBwAAAA==.',
Cu='Curadora:BAAALgADCgQJBAAAAA==.Cursereflect:BAABLgAECn8iAAMfAAkJyQ7eUwCgAQAfAAkJyQ7eUwCgAQAbAAEJAADQVgAAAAAAAA==.Curseus:BAAALgAECgIJBQAAAA==.',
Cy='Cyberwin:BAAALgAECgEJAQAAAA==.',
Da='Damncats:BAABLgAECn9CAAIVAAkJQxIaIwDaAQAVAAkJQxIaIwDaAQAAAA==.Dandinn:BAAALgAECgYJCQAAAA==.Danielsboone:BAABLgAECn8jAAIDAAgJhg+wBADnAAADAAgJhg+wBADnAAAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJCAABLgAFFAUJDQAQAMMMAA==.Darknemesis:BAAALgAECgUJCAAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAFFAIJAwABLgAFFAYJOAAbAPsiAA==.',
De='Deadhippocow:BAABLgAECn8aAAIMAAYJfR3lLAD0AQAMAAYJfR3lLAD0AQAAAA==.Deathwavez:BAACLgAFFH8VAAIZAAQJqhPvCADoAAAZAAQJqhPvCADoAAAuAAQKfxoAAhkABwkwFwFlAMUBABkABwkwFwFlAMUBAAAA.Declän:BAAALgAECgMJBAABLgAECgYJGgAMAH0dAA==.Decurse:BAABLgAECn8kAAIfAAkJ+hTNPADoAQAfAAkJ+hTNPADoAQAAAA==.Deldrin:BAABLgAECn8jAAIXAAkJAhOLUADqAQAXAAkJAhOLUADqAQAAAA==.Demayy:BAABLgAECn8uAAIeAAkJKxNWIwAFAgAeAAkJKxNWIwAFAgAAAA==.Demona:BAACLgAFFH8MAAMfAAUJAwwaYQAGAQAfAAQJAwwaYQAGAQAaAAIJkgdVLAA9AAAuAAQKfyUAAxsACAkxGe4pABoBAB8ABwnIFQd4AEkBABsABAngE+4pABoBAAAA.Demonix:BAABLgAECn8YAAIfAAgJlRocNgABAgAfAAgJlRocNgABAgAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAACLgAFFH8KAAIXAAQJdwdDcQD/AAAXAAQJdwdDcQD/AAAuAAQKfzoAAhcACQm/D2BXANcBABcACQm/D2BXANcBAAAA.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAABLgAECn8eAAMSAAYJZxxzeQB7AQASAAYJZxxzeQB7AQARAAIJsAQHhABDAAAAAA==.Dinobrass:BAABLgAECn8jAAIEAAgJtA1yEQBEAQAEAAgJtA1yEQBEAQAAAA==.Dirktheshiny:BAAALgAECgkJDwABLgAECgkJPQAFAIEbAA==.Dirtylöbster:BAACLgAFFH8OAAIXAAMJTCHYJwAUAQAXAAMJTCHYJwAUAQAuAAQKfzUAAhcACQkKJcAJACwDABcACQkKJcAJACwDAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgYJEQABLgAECgYJHgASAGccAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAABLgAECn8UAAIFAAgJpxfYLgBlAQAFAAgJpxfYLgBlAQAAAA==.Dorfydorf:BAAALgAECgEJAgAAAA==.Dorose:BAAALgAECgEJAgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Dranight:BAAALgAECgcJBwABLgAECgkJSgADAHIjAA==.Dreats:BAAALgAECgYJCgAAAA==.Drewmee:BAABLgAECn8YAAISAAkJHgkPkQBQAQASAAkJHgkPkQBQAQAAAA==.Dronar:BAABLgAFFH8FAAIOAAUJCglNLwAlAQAOAAUJCglNLwAlAQABLgAECgkJIwALAAEgAA==.Drublood:BAAALgAECgcJCwABLgAECgkJGAASAB4JAA==.Drunkinmasta:BAAALgAECgEJAQABLgAFFAQJEAASAB4WAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Duckbeak:BAAALgADCgUJCAAAAA==.Dune:BAAALgADCgcJBwAAAA==.Duwork:BAABLgAECn8VAAIFAAcJASHiHADhAQAFAAcJASHiHADhAQAAAA==.',
['Dæ']='Dæmona:BAABLgAECn8VAAIgAAkJmxLUFQDeAQAgAAkJmxLUFQDeAQAAAA==.',
Eb='Ebk:BAAALgAECgcJDAAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
Ei='Eight:BAAALgADCggJGAAAAA==.',
El='Eladus:BAAALgAECgcJEAAAAA==.Elemnt:BAAALgAECgYJDQABLgAFFAQJEAASAB4WAA==.Elesus:BAAALgAECggJDQABLgAECgkJQwAhAJUhAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJDgAAAA==.Emrys:BAAALgAECgMJAgAAAA==.',
En='Enhshaman:BAACLgAFFH8FAAIeAAMJGQagRQCNAAAeAAMJGQagRQCNAAAuAAQKfxYAAh4ACQn+FDYkAP8BAB4ACQn+FDYkAP8BAAAA.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.Evilinne:BAAALgADCgIJAgAAAA==.Evânescence:BAAALgAECgEJAQAAAA==.',
Ex='Excaliburn:BAAALgAECgEJBAAAAA==.',
Ez='Ezekial:BAAALgAECgQJBAAAAA==.Ezkal:BAACLgAFFH8RAAIZAAUJQBvKaAAoAQAZAAUJQBvKaAAoAQAuAAQKfywAAxkACQnsGaEYAOgCABkACQnsGaEYAOgCAAkABgktFWkrAP4AAAAA.',
Fa='Faithastray:BAAALgAECgMJAwAAAA==.Faithpasse:BAABLgAECn84AAMeAAgJ4xydEgCJAgAeAAgJ4xydEgCJAgATAAEJ9gPfhgApAAAAAA==.Falcorne:BAABLgAECn80AAIDAAkJqiITCAAbAwADAAkJqiITCAAbAwAAAA==.Fatlipz:BAABLgAECn8iAAIhAAcJdQ8WAQBEAQAhAAcJdQ8WAQBEAQAAAA==.Fay:BAAALgADCgEJAQABLgAECgYJCAANAAAAAA==.',
Fe='Felondar:BAABLgAECn8iAAMgAAkJVgtYIgBlAQAgAAkJVgtYIgBlAQAWAAYJsASzmwDhAAAAAA==.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8ZAAMJAAkJhBsxDABOAgAJAAcJsBsxDABOAgAZAAgJvhiIagC3AQAAAA==.',
Fi='Finnadin:BAABLgAECn8mAAISAAkJ4R5cGQCrAgASAAkJ4R5cGQCrAgAAAA==.Finns:BAAALgAECgcJDwAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAABLgAECn8dAAIDAAgJ0xn0OQD3AQADAAgJ0xn0OQD3AQAAAA==.Fistobeef:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.',
Fl='Fleable:BAAALgAECgQJAgAAAA==.Flysky:BAACLgAFFH8cAAIdAAgJbxiPBQB0AgAdAAgJbxiPBQB0AgAuAAQKfywABB0ACQnFI4kCAEcDAB0ACQnFI4kCAEcDACIACAnIJF8HAOICAAYAAQl3DyBBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECggJDQAAAA==.',
Fr='Freakmeout:BAAALgAECgQJBAAAAA==.Freshpot:BAAALgAECgMJAwAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgAECgEJAQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJDgABLgAFFAUJEQAZAEAbAA==.Futuredragoo:BAAALgAECgcJDAABLgAFFAUJEQAZAEAbAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Fy='Fyska:BAAALgADCgEJAQAAAA==.',
Ga='Gabriella:BAAALgAECgYJDAAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQANAAAAAA==.Galnannix:BAAALgAECggJDQAAAA==.Gardrake:BAABLgAECn8zAAMiAAkJrBn7EABeAgAiAAkJrBn7EABeAgAdAAcJqhCrHQCWAQAAAA==.Gastapha:BAABLgAECn8ZAAIWAAkJ0wZmigAMAQAWAAkJ0wZmigAMAQAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMVAAgJCxMcMADvAQAVAAgJCxMcMADvAQAjAAEJAAD5jwAAAAAAAA==.Gehennas:BAABLgAFFH8FAAIWAAMJeh3PUwDzAAAWAAMJeh3PUwDzAAAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Go='Goku:BAAALgAFFAIJAgAAAA==.Goofykirby:BAAALgADCgcJFQAAAA==.Googoo:BAABLgAECn8UAAIZAAkJrhM/OgAXAgAZAAkJrhM/OgAXAgAAAA==.Googoogagaa:BAACLgAFFH8MAAIcAAQJkhAXHQAHAQAcAAQJkhAXHQAHAQAuAAQKf0YAAxwACQkKHnMNAH0CABwACQkKHnMNAH0CAAcABwnyEgMqAKIBAAAA.Gotlieb:BAAALgAECggJCgAAAA==.',
Gr='Grenno:BAAALgAECgcJBwABLgAFFAgJIAAZANsaAA==.Greystorm:BAAALgAECgIJAgAAAA==.Greythorn:BAAALgADCgkJCQABLgAECgkJSgADAHIjAA==.Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQANAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8hAAMEAAgJNRJYBwCnAQAEAAcJXRRYBwCnAQACAAUJnwxcFwAXAQAuAAQKfxQAAgQABwkJJOIRAKoCAAQABwkJJOIRAKoCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hakarren:BAAALgAECgYJCAAAAA==.Hamatza:BAAALgAECgEJAgAAAA==.Hammerinfred:BAAALgAECgQJBwAAAA==.Hawkmoon:BAAALgAECgEJBAAAAA==.',
He='Healingisfun:BAAALgAECgMJBAAAAA==.Helhunter:BAABLgAECn8yAAIWAAkJbRL9RwCuAQAWAAkJbRL9RwCuAQAAAA==.Hellock:BAAALgAFFAEJAQAAAA==.',
Hi='Hippysmasher:BAAALgAECgIJAgAAAA==.',
Ho='Hodgepodge:BAAALgAECgEJAgAAAA==.Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgMJBQAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holybob:BAAALgAECgQJCAAAAA==.Holyhooters:BAABLgAECn87AAISAAkJ2yFfDwDrAgASAAkJ2yFfDwDrAgAAAA==.Holypablo:BAAALgAECgQJBgABLgAECgkJUQAhAMEfAA==.Homefries:BAAALgADCgYJBgABLgAECgYJGgAMAH0dAA==.Honkytonk:BAABLgAECn8aAAMGAAgJKQtAIgAYAQAGAAYJ7QlAIgAYAQAiAAcJeAmsOAATAQAAAA==.Honor:BAAALgAECgcJBwABLgAECgkJOwASAI8jAA==.Honour:BAABLgAECn87AAISAAkJjyMeDgD0AgASAAkJjyMeDgD0AgAAAA==.',
Hr='Hrathdemon:BAACLgAFFH8SAAIWAAUJlxfgQAAlAQAWAAUJlxfgQAAlAQAuAAQKfysAAhYACQntIPUQALoCABYACQntIPUQALoCAAAA.Hrathid:BAAALgADCgUJDAABLgAFFAUJEgAWAJcXAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8KAAISAAMJiiBUEgATAQASAAMJiiBUEgATAQAuAAQKfywAAhIACQnqI7oFAHIDABIACQnqI7oFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAABLgAECn8YAAMSAAkJwRuJLwBDAgASAAkJwRuJLwBDAgARAAIJWwcfhgA/AAAAAA==.',
Ib='Ibleedorange:BAAALgAECggJDQAAAA==.',
Ic='Icehawk:BAAALgAECgMJBAAAAA==.Ickeetard:BAABLgAECn8eAAMhAAkJXRJ4MQBWAQAhAAcJFA94MQBWAQAHAAYJwxF8AwBuAAAAAA==.',
Id='Idiot:BAAALgAECgMJBAAAAA==.Idiotbreath:BAABLgAECn82AAMiAAkJFSCyCADLAgAiAAkJFSCyCADLAgAGAAMJmQmDMACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgAECgEJAgAAAA==.',
Im='Immorlich:BAAALgAECgEJAQAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJCQAAAA==.Inflexi:BAACLgAFFH8KAAIDAAQJyRQ2BwDaAAADAAQJyRQ2BwDaAAAuAAQKfy0AAwMACQlqIFkNAOcCAAMACQmYH1kNAOcCAAQACAnKGvAYAGQCAAAA.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAABLgAECn8YAAITAAYJWhmkLwBKAQATAAYJWhmkLwBKAQAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn8/AAQMAAkJIB5zDgDkAgAMAAkJIB5zDgDkAgAFAAgJFyDoFAAqAgALAAMJ2hZVOQDAAAAAAA==.',
Iv='Iver:BAAALgAECgUJBgABLgAECgcJEQANAAAAAA==.',
Ja='Jangle:BAAALgADCgYJBwAAAA==.',
Je='Jeffblades:BAAALgAECgYJDgAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJBgANAAAAAA==.',
Jj='Jjooaacchhim:BAAALgAECgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8jAAIDAAkJfBt4LQAnAgADAAkJfBt4LQAnAgAAAA==.',
Ka='Kadillac:BAAALgAECgcJEwAAAA==.Kaelira:BAAALgADCgIJAgAAAA==.Kairei:BAAALgAECggJDwAAAA==.Kakashi:BAAALgADCgEJAQAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAACLgAFFH8VAAISAAYJ9BpWKQBnAQASAAYJ9BpWKQBnAQAuAAQKfx0AAxIACQl1ItsRANkCABIACQkUItsRANkCABQAAQlIJYE2AGkAAAAA.Katalina:BAABLgAECn8wAAMkAAgJmBHLDQB2AQAkAAgJmBHLDQB2AQAgAAYJpwsROAAlAQAAAA==.Kawer:BAAALgAECgQJCQAAAA==.Kawnzerker:BAAALgADCgkJCQAAAA==.',
Ke='Kelstormhoof:BAAALgADCgcJFgABLgAECgUJCAANAAAAAA==.Kernel:BAAALgAECgEJAQABLgAFFAQJDQAVAMAfAA==.',
Kh='Kham:BAACLgAFFH8UAAIVAAUJMhsvGQBOAQAVAAUJMhsvGQBOAQAuAAQKf0QAAhUACQlgJMYDACsDABUACQlgJMYDACsDAAAA.',
Ki='Kialla:BAAALgAECgIJAgABLgAECgkJKAAOACsgAA==.Killmaim:BAABLgAECn8ZAAIVAAgJwRllIABPAgAVAAgJwRllIABPAgAAAA==.Kitsuko:BAABLgAECn80AAMOAAkJFg+0PgCzAQAOAAkJFg+0PgCzAQAQAAkJxRDLLACRAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ko='Kokeovrdose:BAAALgAECgQJBAABLgAECgYJFAAXAAYWAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuli:BAAALgAECgEJAgAAAA==.Kuraishin:BAAALgAFFAEJAQABLgAFFAcJFgAXABwUAA==.Kuvare:BAAALgAECgMJAwAAAA==.',
['Kè']='Kèlton:BAAALgAECgUJCgAAAA==.',
La='Lanas:BAEALgAECgkJAwABLgAFFAUJFAASAMMQAA==.Laocoon:BAAALgAECggJCAABLgAECgkJOwASANshAA==.Lavashiza:BAAALgAECgYJEwAAAA==.Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAABLgAECn8UAAIDAAgJThKyfABGAQADAAgJThKyfABGAQAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAgAAAA==.Leedaddydk:BAAALgAECgQJCgAAAA==.Leroyjenkins:BAABLgAECn8XAAIlAAcJ8BvoAgBVAgAlAAcJ8BvoAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.Letsbeef:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.',
Li='Lightstorm:BAAALgAECgYJEAAAAA==.Linaria:BAAALgAECgUJCAAAAA==.Linø:BAAALgAECgEJAQAAAA==.Lissara:BAABLgAECn8ZAAIiAAgJExBLNABiAQAiAAgJExBLNABiAQAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAACLgAFFH8TAAImAAUJqRyuGgBQAQAmAAUJqRyuGgBQAQAuAAQKfyMAAiYACQnCHEEOAFUCACYACQnCHEEOAFUCAAAA.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockmogged:BAAALgAFFAIJAgAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECgkJHAADADIkAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAFFAQJDgAaAKATAA==.Luminouslexi:BAAALgAECgMJAwAAAA==.',
Ma='Macoub:BAACLgAFFH8FAAIWAAQJCQUfYADPAAAWAAQJCQUfYADPAAAuAAQKfxcABCAACAnFFZcnAD4BACAABgl2FZcnAD4BABYABAmMGrWbAOoAACQAAwluB5QxAD0AAAAA.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAABLgAECn8ZAAMbAAgJfQU8GwDLAAAbAAgJUQU8GwDLAAAfAAQJzAOW/gBqAAAAAA==.Mageslayer:BAABLgAECn8bAAMnAAgJmxPiHgCfAQAnAAgJGBLiHgCfAQABAAMJPRCMGACtAAAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magicstorm:BAAALgAECgYJBgAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgANAAAAAA==.Mahalleinr:BAAALgADCgEJAQAAAA==.Maiggee:BAAALgAECgEJAgAAAA==.Makkideez:BAABLgAECn8UAAInAAkJNxhXEAApAgAnAAkJNxhXEAApAgAAAA==.Makkii:BAAALgADCgEJAQABLgAECgkJFAAnADcYAA==.Malanara:BAAALgADCgEJAQABLgAECgkJIwAXAAITAA==.Malxt:BAAALgADCgYJBwAAAA==.Manabuns:BAABLgAECn8pAAIXAAgJ2xc8XgDEAQAXAAgJ2xc8XgDEAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8lAAISAAkJ/RRKQgAeAgASAAkJ/RRKQgAeAgAAAA==.Markruffalo:BAAALgAECgYJDAAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn86AAIVAAkJaBu+FABKAgAVAAkJaBu+FABKAgAAAA==.',
Mc='Mckay:BAAALgAECggJEwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8mAAIlAAgJRBSzBACjAQAlAAgJRBSzBACjAQAAAA==.Megapunk:BAAALgAECgcJDwAAAA==.Mellmaan:BAAALgAFFAIJAgAAAA==.Melys:BAAALgAECgcJEgAAAA==.Meteorite:BAAALgAECgYJCQAAAA==.Meudayr:BAABLgAECn8jAAILAAkJASBxBADRAgALAAkJASBxBADRAgAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.Mezagog:BAAALgAECgYJDwAAAA==.',
Mi='Mikehammer:BAAALgADCgcJDgAAAA==.Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAACLgAFFH8NAAIQAAUJwww4KwDoAAAQAAUJwww4KwDoAAAuAAQKfx4AAhAACAltHCISAJICABAACAltHCISAJICAAAA.Mittenss:BAAALgADCgIJAgAAAA==.',
Mo='Moistblanket:BAAALgAECgUJBwAAAA==.Mojorisin:BAABLgAECn8jAAICAAkJ6xoWDgBHAgACAAkJ6xoWDgBHAgAAAA==.Moobear:BAAALgAECggJDQAAAA==.Moonchiken:BAAALgAECgEJCgAAAA==.Moozlock:BAABLgAECn8rAAIfAAkJEhKNTQCyAQAfAAkJEhKNTQCyAQAAAA==.Moscovio:BAAALgAFFAIJBAABLgAFFAMJBQASAFITAA==.Mosspaws:BAABLgAECn82AAMMAAkJbiTQBgBLAwAMAAkJbiTQBgBLAwAFAAQJZB8ONgA+AQAAAA==.',
Mt='Mtndewyou:BAAALgAECgYJEAAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.Mutterutters:BAAALgAECgEJAgAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.Myrollin:BAAALgAECgIJAgAAAA==.',
Na='Naetara:BAAALgADCgEJAQAAAA==.Narfiy:BAAALgADCgEJAQAAAA==.Narisanna:BAAALgAFFAEJAgAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBgAAAA==.',
Nm='Nme:BAABLgAECn8lAAMXAAkJoBAPXADKAQAXAAkJoBAPXADKAQAlAAYJiw9LCQBWAQAAAA==.',
No='Nocturnos:BAACLgAFFH8HAAIfAAMJ/RNycwDaAAAfAAMJ/RNycwDaAAAuAAQKfzIAAx8ACQlNIEQbAIACAB8ACQlNIEQbAIACABoAAgn3IOguAGIAAAAA.Noctyr:BAAALgAECgEJAQAAAA==.Noggin:BAABLgAECn8rAAMRAAkJRyH/BAAcAwARAAkJRyH/BAAcAwASAAgJ/BCIagCaAQAAAA==.Nonform:BAABLgAECn89AAQFAAkJgRvQDACKAgAFAAkJgRvQDACKAgAKAAEJwRXvTAA/AAAMAAEJdAED7AAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECggJIQAWAH0WAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQANAAAAAA==.Novamancer:BAAALgAECgEJAQAAAA==.Noxta:BAAALgAECggJEgAAAA==.',
Nu='Numonixx:BAACLgAFFH8hAAMGAAYJ7A6bBgDqAAAiAAYJCA2gKQAiAQAGAAQJKwubBgDqAAAuAAQKfzoAAwYACQkFH4oCAJMCAAYACAmsIIoCAJMCACIACAnGG0MUADsCAAAA.Nutlessfred:BAAALgAECgEJAQAAAA==.',
Ny='Nymage:BAABLgAECn9ZAAIXAAkJHBulKgBvAgAXAAkJHBulKgBvAgAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogmund:BAAALgAECgYJEQAAAA==.',
Oh='Ohnospiders:BAABLgAECn8yAAMZAAkJpBfMNAAsAgAZAAkJpBfMNAAsAgAIAAQJ4RRYIQDDAAAAAA==.Ohpig:BAAALgAECgMJAwAAAA==.',
Ok='Okaerisan:BAABLgAECn8VAAIUAAkJZxRmFQB8AQAUAAkJZxRmFQB8AQAAAA==.',
Ol='Olord:BAAALgAECgYJBgAAAA==.',
Om='Omarcuthlink:BAAALgAECgEJAQABLgAFFAQJCwAaAHkRAA==.Omgbbqq:BAAALgAECggJCAABLgAFFAMJCQADAKwbAA==.',
On='Onilecram:BAAALgAECgIJAgAAAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECggJEQAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Ou='Outlast:BAACLgAFFH8QAAISAAQJHhYoOwA1AQASAAQJHhYoOwA1AQAuAAQKfy8AAhIACQm1HbQRAAQDABIACQm1HbQRAAQDAAAA.',
Pa='Paants:BAABLgAECn8kAAIoAAkJugwEHwA7AQAoAAkJugwEHwA7AQAAAA==.Pacid:BAAALgAECgYJDAAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Pakal:BAAALgAECgMJAwAAAA==.Palebull:BAAALgADCgYJCAAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8YAAIWAAgJfxxRCgB1AgAWAAgJfxxRCgB1AgAuAAQKfzMAAhYACQkEJZUEAD0DABYACQkEJZUEAD0DAAAA.Parmageddon:BAAALgAFFAEJAQABLgAFFAQJDgAoAPggAA==.Parmigiano:BAAALgADCgEJAQABLgAFFAQJDgAoAPggAA==.Parmrageiano:BAABLgAFFH8OAAIoAAQJ+CAIDQBdAQAoAAQJ+CAIDQBdAQAAAA==.Parms:BAABLgAECn8ZAAQCAAgJ+xNAJgBrAQACAAgJ6xFAJgBrAQAEAAYJhQxETQAcAQADAAIJORANowCFAAABLgAFFAQJDgAoAPggAA==.Parmy:BAAALgAECgEJAQAAAA==.',
Pe='Peanought:BAABLgAECn8qAAMIAAkJjxYBBgDJAQAIAAgJsRcBBgDJAQAZAAkJ5A4SYQCnAQAAAA==.Peidro:BAABLgAECn8bAAISAAcJAA9HqAArAQASAAcJAA9HqAArAQAAAA==.Pentacles:BAABLgAECn8tAAILAAkJsCA5BwCDAgALAAkJsCA5BwCDAgAAAA==.',
Pi='Pijak:BAABLgAECn8UAAIUAAgJuRTaGwA4AQAUAAgJuRTaGwA4AQAAAA==.Pinkpaw:BAABLgAECn8iAAQLAAkJFh/EBADJAgALAAkJFh/EBADJAgAMAAUJthqnSABsAQAKAAEJuBKESgBEAAAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8JAAMmAAMJ3iTvCABGAQAmAAMJ3iTvCABGAQATAAEJlCPqOABjAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCQAmAN4kAA==.Postscalone:BAAALgAECgYJBwAAAA==.Potatoes:BAABLgAECn8VAAMbAAgJBgiWHABpAQAbAAgJBgiWHABpAQAfAAIJCQJIFAE6AAAAAA==.',
Pr='Pruflas:BAABLgAECn8aAAIZAAgJZAtAjgBJAQAZAAgJZAtAjgBJAQAAAA==.',
Ps='Psycodk:BAACLgAFFH8JAAIZAAUJxxzxSwBaAQAZAAUJxxzxSwBaAQAuAAQKfxYAAhkACAmYGD5sAI0BABkACAmYGD5sAI0BAAAA.',
Pu='Puffdaddie:BAAALgAECgUJBwABLgAECggJJwASAMwfAA==.Pumpin:BAABLgAECn8XAAITAAUJFCTGKgBnAQATAAUJFCTGKgBnAQAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
['Pä']='Päcid:BAAALgADCgEJAQAAAA==.',
Qk='Qkn:BAAALgAECgUJEgAAAA==.',
Qu='Quickswipe:BAABLgAFFH8GAAInAAMJxSAkIgAUAQAnAAMJxSAkIgAUAQABLgAFFAYJOAAbAPsiAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgYJCwABLgAECgcJCQANAAAAAA==.Ralee:BAAALgADCgcJCQAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Rastabution:BAAALgAECgkJAQAAAA==.Ratoncita:BAAALgAECgEJAgAAAA==.Raynne:BAAALgAECgIJAgAAAA==.Rayzee:BAAALgADCgUJBQAAAA==.',
Re='Reaperjoe:BAAALgAFFAEJAgAAAA==.Rehab:BAACLgAFFH8FAAISAAMJ1RMTawDZAAASAAMJ1RMTawDZAAAuAAQKfxUAAhIACQlbHK4vAGQCABIACQlbHK4vAGQCAAAA.Rehna:BAAALgAECgYJBgABLgAFFAQJEgAHAM0RAA==.Rek:BAAALgAECgEJAQABLgAECgkJIwALAAEgAA==.Rektributio:BAACLgAFFH8eAAISAAgJCyDIBACYAgASAAgJCyDIBACYAgAuAAQKfzcAAhIACQkgJeYGADgDABIACQkgJeYGADgDAAAA.Resurection:BAAALgAECgYJCAAAAA==.Revalation:BAACLgAFFH8GAAIMAAMJERXEAwC6AAAMAAMJERXEAwC6AAAuAAQKfycAAgwACQlSH9wVAJoCAAwACQlSH9wVAJoCAAAA.Revenancer:BAAALgAECgEJAgAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgANAAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Riachu:BAAALgADCgUJBQAAAA==.Ribeyejoe:BAAALgADCgEJAQAAAA==.Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAACLgAFFH8GAAMVAAMJHxevBwBaAAAoAAIJlxhgIQCNAAAVAAIJwxOvBwBaAAAuAAQKfzEAAxUACQmCHx8WAD4CABUACAl0IB8WAD4CACgACAkJF+ISAL4BAAAA.Roadtrip:BAAALgAECgMJBAAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJBAAAAA==.Rottingslow:BAABLgAFFH8IAAIHAAMJ9wDYKwBpAAAHAAMJ9wDYKwBpAAABLgAFFAgJIQAJAHcgAA==.',
Sa='Sanford:BAAALgAECgUJBQAAAA==.Saragos:BAAALgADCgcJBgABLgAFFAcJFgAXABwUAA==.Saucerdote:BAABLgAECn8eAAMhAAkJmBWvHwDQAQAhAAcJGxevHwDQAQAcAAkJFAldMQBWAQAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAcJFgAXABwUAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAACLgAFFH8JAAIWAAUJ9RJ6TAAFAQAWAAUJ9RJ6TAAFAQAuAAQKfysAAhYACQl7H6sPAMYCABYACQl7H6sPAMYCAAAA.Selkie:BAABLgAECn8mAAIPAAkJvg86DgDMAQAPAAkJvg86DgDMAQAAAA==.Seragosa:BAAALgAFFAEJAQABLgAFFAcJFgAXABwUAA==.',
Sh='Shakakhan:BAAALgAECgYJDQABLgAECgYJHgASAGccAA==.Shambeau:BAAALgADCgQJBAAAAA==.Shamrun:BAAALgADCgQJBQAAAA==.Shamshielder:BAECLgAFFH8QAAQIAAUJiBJOEQAKAQAIAAQJZwpOEQAKAQAJAAMJihizOQBPAAAZAAIJMgcWHQBIAAAuAAQKfy0ABAkACQmZI5oFAM0CAAkACQmZI5oFAM0CAAgABgmlGxsOAJQBABkAAQm5CXGNASkAAAAA.Shapper:BAAALgAECgQJBQAAAA==.Sharick:BAAALgAECgQJBQAAAA==.Shawlee:BAACLgAFFH8FAAMQAAMJGgL3BgBnAAAQAAIJ9QL3BgBnAAAOAAEJjQLWjAAmAAAuAAQKfy0AAw4ACAnMEB1cAEkBAA4ACAnMEB1cAEkBABAACAk7CnJWAOEAAAAA.Sheezie:BAACLgAFFH8IAAIOAAMJExrbPADwAAAOAAMJExrbPADwAAAuAAQKf0kAAw4ACQmkIVsFAF0DAA4ACQmkIVsFAF0DAA8ACQnfGDULAAQCAAAA.Shellcow:BAAALgAECgYJBgABLgAECgkJIgAYAG0gAA==.Shellter:BAAALgAECgEJAgABLgAECgkJIgAYAG0gAA==.Shellwit:BAAALgAECgMJBgABLgAECgkJIgAYAG0gAA==.Sheph:BAAALgAFFAEJAQAAAA==.Shetmage:BAACLgAFFH8XAAIXAAcJdwv2NQCSAQAXAAcJdwv2NQCSAQAuAAQKfykAAhcACQnDIAUkAI0CABcACQnDIAUkAI0CAAAA.Shettdh:BAAALgAECgMJBQAAAA==.Shettrah:BAABLgAECn8UAAIFAAYJ+hobKwB8AQAFAAYJ+hobKwB8AQABLgAFFAcJFwAXAHcLAA==.Shienro:BAAALgAECgQJBAABLgAECgQJCQANAAAAAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAABLgAECn8lAAISAAkJ5BFMYACwAQASAAkJ5BFMYACwAQAAAA==.Shuck:BAAALgAECgQJBAABLgAFFAQJDQAVAMAfAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Sibyx:BAAALgAECgYJEgABLgAECgYJHgASAGccAA==.Siickboy:BAAALgAECgQJCQAAAA==.Sijious:BAAALgAECgYJDAAAAA==.Silveah:BAAALgADCgEJAQAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.',
Sk='Skinable:BAAALgAFFAEJAQAAAA==.Skora:BAAALgADCgIJAgABLgAECgkJJQASAP0UAA==.Skyland:BAAALgADCgcJDQABLgAFFAgJHAAdAG8YAA==.Skyli:BAAALgAECgUJCAABLgAECgkJKAAOACsgAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Sneez:BAAALgAFFAEJAQAAAA==.Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAACLgAFFH8TAAIRAAUJZxqXIgALAQARAAUJZxqXIgALAQAuAAQKfycAAhEACQmfH7wIAOMCABEACQmfH7wIAOMCAAAA.Sorrie:BAAALgAECgEJAQAAAA==.Sortiarius:BAAALgADCgkJCQAAAA==.',
Sp='Spud:BAAALgADCgcJBwABLgAECgYJFgADAI8fAA==.Spyroh:BAABLgAECn8bAAQGAAYJ6BLuGQBlAQAGAAYJcBDuGQBlAQAiAAUJGBJKSAAKAQAdAAEJ2wA4TwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAQJEgAHAM0RAA==.',
St='Stankydk:BAACLgAFFH8RAAMZAAcJRBTyKQDBAQAZAAYJRBTyKQDBAQAJAAEJAACKagAAAAAuAAQKfzIAAhkACQk+JdAFAEsDABkACQk+JdAFAEsDAAAA.Stankyeyes:BAAALgAECgYJBgAAAA==.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Staticdh:BAABLgAFFH8FAAIWAAUJfRGZBwDaAAAWAAUJfRGZBwDaAAABLgAFFAcJIgAXAAYiAA==.Steakhead:BAABLgAECn8pAAIFAAYJxAsRTQDYAAAFAAYJxAsRTQDYAAAAAA==.Stinkbombs:BAACLgAFFH8RAAIXAAYJhgdHBwANAQAXAAYJhgdHBwANAQAuAAQKfxYAAhcACQl6FNN4AIcBABcACQl6FNN4AIcBAAAA.Stinkerz:BAAALgAECgIJAgABLgAECgkJIgAYAG0gAA==.Stonegut:BAAALgAECggJDwAAAA==.Stunanddone:BAAALgAECgUJEAAAAA==.',
Su='Subrogue:BAABLgAFFH8FAAIjAAIJlhnnMQCWAAAjAAIJlhnnMQCWAAABLgAFFAMJBQAeABkGAA==.Suffragan:BAAALgAECgIJAgAAAA==.Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJEAAAAA==.Supreme:BAACLgAFFH8IAAIWAAMJXhrQXwDQAAAWAAMJXhrQXwDQAAAuAAQKfxkAAhYACAl4I24YAMMCABYACAl4I24YAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAMJAwABLgAFFAQJFQAnAIUeAA==.Swayaim:BAABLgAFFH8LAAIDAAQJEgaDVAD/AAADAAQJEgaDVAD/AAAAAA==.Sweatypits:BAAALgAECgYJBgABLgAFFAMJCAAOABMaAA==.Swordsaint:BAAALgAECgEJAQAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAYJDgARAO8RAA==.Sylphrena:BAACLgAFFH8TAAIHAAUJHxawGAD3AAAHAAUJHxawGAD3AAAuAAQKfygAAgcACQlQHogIAMMCAAcACQlQHogIAMMCAAAA.',
['Sí']='Sínful:BAABLgAECn8qAAIEAAkJxB+BBABqAgAEAAkJxB+BBABqAgAAAA==.',
Ta='Tacow:BAAALgAECggJEQAAAA==.Tahwe:BAAALgAECgIJAgAAAA==.Talethen:BAABLgAECn8gAAMiAAkJdRmNMgBqAQAiAAkJ8xeNMgBqAQAGAAUJMxgpIAAtAQAAAA==.Talgrin:BAAALgAECgYJBgAAAA==.Talla:BAABLgAECn8oAAIOAAkJKyCvCAAmAwAOAAkJKyCvCAAmAwAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgAECgEJAQABLgAECgUJCAANAAAAAA==.Tellus:BAAALgADCgcJCwAAAA==.Tempesttempi:BAAALgADCgcJBwAAAA==.Tewshort:BAAALgAECgQJCAABLgAFFAQJEAASAB4WAA==.',
Th='Thatbox:BAAALgAECgQJBAAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgUJEQAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAABLgAECn8UAAMTAAgJBAUGXgCfAAAmAAcJQQRZWQDeAAATAAcJQgQGXgCfAAAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thorfyna:BAABLgAECn8kAAIkAAkJRxRRCQDXAQAkAAkJRxRRCQDXAQAAAA==.Threzk:BAABLgAECn8eAAIbAAkJew7+DgBPAQAbAAkJew7+DgBPAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.Thunderstorm:BAAALgAECgcJDAAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8MAAIWAAUJZBMbNABUAQAWAAUJZBMbNABUAQAuAAQKfy8AAhYACQmGIoULAOsCABYACQmGIoULAOsCAAAA.Tontiamat:BAABLgAECn89AAMiAAkJXRijFwAaAgAiAAkJXRijFwAaAgAGAAYJawo5IAAsAQAAAA==.Tontier:BAABLgAECn8hAAQMAAgJYg7ZSABsAQAMAAgJYg7ZSABsAQAKAAYJWwo2MAChAAALAAQJSg5fSwB9AAABLgAECgkJPQAiAF0YAA==.Totembeans:BAAALgAECgQJCwAAAA==.Totemshocker:BAECLgAFFH8FAAIQAAMJfAbVEQDXAAAQAAMJfAbVEQDXAAAuAAQKfxYAAxAACAkqGQUXAGACABAACAkqGQUXAGACAA4AAQkBDHLeACoAAAEuAAUUBQkQAAgAiBIA.Toxicshadow:BAAALgADCgQJBgAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAACLgAFFH8OAAIRAAYJ7xGxEQCoAQARAAYJ7xGxEQCoAQAuAAQKfxwABBEACQlOH5QMAMUCABEACAnDHpQMAMUCABIABwksDjq3ABcBABQAAgmgE6FNADgAAAAA.Trashfire:BAACLgAFFH8KAAMHAAQJIA5zGQDvAAAHAAQJIA5zGQDvAAAhAAIJwgF2FgB7AAAuAAQKfx0ABAcACAkXHSYQAGUCAAcACAkXHSYQAGUCABwABQknFXw2ADkBACEAAwluEWhAAK0AAAEuAAUUBgkOABEA7xEA.Treeple:BAABLgAECn8iAAMMAAkJ5xZ0SwBhAQAMAAcJUBN0SwBhAQAFAAUJbA5uQQAIAQAAAA==.Treily:BAAALgAECgYJDwAAAA==.Tresleches:BAABLgAECn8rAAISAAkJBhJDXgC1AQASAAkJBhJDXgC1AQAAAA==.Tricket:BAABLgAECn9TAAMjAAkJeCDLAwDsAgAjAAkJeCDLAwDsAgAVAAYJKBlvVAD6AAAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAbAAYIAQ==.Truestorm:BAACLgAFFH8FAAISAAIJ2wSxCwBwAAASAAIJ2wSxCwBwAAAuAAQKfykAAhIACQnOC017AHgBABIACQnOC017AHgBAAAA.Truheals:BAAALgAECgYJCgAAAA==.',
Tu='Tuchi:BAACLgAFFH8ZAAMlAAUJCx+9AQAIAQAXAAUJkByVHgBQAQAlAAMJaxy9AQAIAQAuAAQKfyYAAyUABwm9IzsDAPgBABcABwliIrkyAKgCACUABgnQIjsDAPgBAAAA.Tumblestone:BAAALgAECgEJAQAAAA==.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAgJGAAWAH8cAA==.',
['Tà']='Tàcobelle:BAACLgAFFH8FAAIEAAIJoxPuIwCPAAAEAAIJoxPuIwCPAAAuAAQKfxYAAgQACQnrHm8EAGwCAAQACQnrHm8EAGwCAAEuAAQKCAkpABcA2xcA.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Vaelen:BAAALgAECgEJAQABLgAECgkJGAAfAJUaAA==.Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgANAAAAAA==.Valhalla:BAAALgAECgYJBgAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIOAAMJriKeOgD4AAAOAAMJriKeOgD4AAAuAAQKfzEAAw4ACQllGz8SAIQCAA4ACQllGz8SAIQCABAABgkTGo82AF8BAAAA.Varanis:BAACLgAFFH8JAAIDAAMJnxZuDAD/AAADAAMJnxZuDAD/AAAuAAQKfxkAAgMACQlkIWMLAOgCAAMACQlkIWMLAOgCAAAA.',
Ve='Vegh:BAACLgAFFH8HAAIkAAMJYBgkCQDBAAAkAAMJYBgkCQDBAAAuAAQKf04AAiQACQnzH1wDAKoCACQACQnzH1wDAKoCAAAA.Vem:BAABLgAECn8uAAIiAAkJsR1KEABlAgAiAAkJsR1KEABlAgAAAA==.Veriale:BAAALgAECgcJDAAAAA==.Verra:BAABLgAECn85AAISAAkJWhs3JgBrAgASAAkJWhs3JgBrAgAAAA==.',
Vi='Vitriol:BAABLgAECn8hAAIVAAcJZxgvMQCIAQAVAAcJZxgvMQCIAQAAAA==.',
Vo='Voidbeaver:BAAALgAECgcJCwAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAACLgAFFH8OAAMaAAQJoBMWBgAhAQAaAAQJoBMWBgAhAQAbAAEJYQcEKwA8AAAuAAQKfx8AAhoACQl2IqsBAMoCABoACQl2IqsBAMoCAAAA.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgcJEAANAAAAAA==.Vyrros:BAAALgAECgEJAQAAAA==.',
Wa='Walji:BAABLgAECn8eAAMOAAgJyhtyFwBaAgAOAAgJyhtyFwBaAgAQAAEJWwuirwApAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgAECgIJBAAAAA==.Wandy:BAABLgAECn86AAIfAAkJtxrGAADnAQAfAAkJtxrGAADnAQAAAA==.Wangstah:BAABLgAECn8cAAIDAAkJMiRgDwDVAgADAAkJMiRgDwDVAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAIVAAYJNhQUSgB8AQAVAAYJNhQUSgB8AQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJDgAAAA==.Wawatesi:BAAALgAECgMJAwAAAA==.Waytogoteam:BAACLgAFFH8JAAIDAAMJrBv/UwAAAQADAAMJrBv/UwAAAQAuAAQKfzgAAgMACQkpJJkLAPcCAAMACQkpJJkLAPcCAAAA.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8WAAMXAAcJHBTPKgDJAQAXAAcJHBTPKgDJAQAYAAIJBw4+BQCCAAAuAAQKfzMABBcACQnEJIMNAA0DABcACQk3JIMNAA0DABgABgm+I3wDANkBACUAAQmPIMgWAGQAAAAA.Wenya:BAAALgADCgcJBwAAAA==.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgQJBAAAAA==.',
Wo='Woodyy:BAABLgAECn8jAAIZAAgJYg+BewBsAQAZAAgJYg+BewBsAQAAAA==.Woog:BAAALgAECgYJEQAAAA==.Wox:BAAALgAECgkJEAAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wu='Wujustyle:BAAALgAECgcJBwAAAA==.Wulfgar:BAAALgAFFAEJAQAAAA==.',
Wy='Wyldspirit:BAABLgAECn8jAAIDAAgJQg/+BADcAAADAAgJQg/+BADcAAAAAA==.Wyreless:BAAALgADCgYJBgABLgAECgkJNQAKABUWAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgAECgEJAQAAAA==.',
Xe='Xe:BAAALgAECgYJBgABLgAECgkJUwAjAHggAA==.',
Xr='Xrind:BAAALgADCgEJAQAAAA==.',
Ya='Yaass:BAAALgAECgMJAwAAAA==.',
Ye='Yem:BAACLgAFFH84AAQbAAYJ+yJoAgDMAQAbAAYJEiBoAgDMAQAfAAUJeiAgPABcAQAaAAIJYSIrHgBTAAAuAAQKfzYAAxsACQmiIzkGAGwCABsABgncIzkGAGwCAB8ABgliI1VJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAILAAcJvxm2CAAfAgALAAcJvxm2CAAfAgABLgAFFAYJFQASAPQaAA==.Yoverre:BAAALgAECgMJAwAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAANAAAAAA==.Zanzabar:BAABLgAECn8XAAISAAkJvBlHQAAGAgASAAkJvBlHQAAGAgAAAA==.Zaraelitha:BAAALgAECgYJCwAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgYJCQABLgAECgkJPwAHAJoeAA==.Zeodrik:BAABLgAECn8cAAIVAAcJYRmxNQDSAQAVAAcJYRmxNQDSAQAAAA==.',
Zh='Zhenya:BAACLgAFFH8TAAIXAAUJ+hLNYgAdAQAXAAUJ+hLNYgAdAQAuAAQKfycAAxcACQltGJ1LAPgBABcACQltGJ1LAPgBACUABAkvD+gOANUAAAAA.',
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
