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
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abracadava:BAAALgAECgQJBQAAAA==.',
Ac='Acheniris:BAAALgAECgUJDQAAAA==.',
Ad='Adeaino:BAAALgAECgUJCAAAAA==.Adonix:BAAALgAECgEJAQAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgUJBwAAAA==.',
Ag='Agrippa:BAACLgAFFH8GAAIBAAMJyQEJCgCdAAABAAMJyQEJCgCdAAAuAAQKfxwAAgEACAmgDo4JAKMBAAEACAmgDo4JAKMBAAAA.',
Ah='Ahndhrez:BAAALgAECgcJBgAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECggJEwAAAA==.Aioli:BAABLgAECn8kAAQCAAkJ1BtMEgAXAgACAAkJuRhMEgAXAgADAAYJ7hdaRwCUAQAEAAUJcRo4SAAzAQAAAA==.Airwavez:BAAALgAECgcJDQAAAA==.',
Al='Alchemorph:BAABLgAECn8XAAIFAAgJSwnfPAAYAQAFAAgJSwnfPAAYAQAAAA==.Aldormu:BAABLgAECn8mAAIGAAkJuAxbCgB3AQAGAAkJuAxbCgB3AQAAAA==.Aliyah:BAEALgADCgIJAgABLgAECgkJJgAHAMoZAA==.Allura:BAACLgAFFH8SAAIHAAQJzRHGGwDUAAAHAAQJzRHGGwDUAAAuAAQKfyQAAgcACQmLGQ4WACwCAAcACQmLGQ4WACwCAAAA.Altra:BAACLgAFFH8SAAIIAAQJDguzEAAHAQAIAAQJDguzEAAHAQAuAAQKfykAAwgACQl5HFYCAJ8CAAgACQl5HFYCAJ8CAAkABwl7A1orAOQAAAAA.Alyvia:BAAALgADCgEJAgAAAA==.',
Am='Amoeta:BAABLgAECn81AAQKAAkJFRYUDwC+AQAKAAgJ0hUUDwC+AQALAAkJAg4BIABJAQAMAAcJyQgGaAD5AAAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgQJBAAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgAECgEJAQAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angelkinq:BAAALgAECgEJAgAAAA==.Angryapples:BAAALgAECgQJCQAAAA==.Annihilation:BAAALgAECgUJCQAAAA==.Antinous:BAABLgAECn8qAAIEAAgJ3gzoEgArAQAEAAgJ3gzoEgArAQAAAA==.',
Ap='Apathia:BAAALgAECgEJAQABLgAECgYJCAANAAAAAA==.Aphrodité:BAAALgAECgIJAgAAAA==.',
Ar='Arcstorm:BAAALgAECgYJDAAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Ashenback:BAACLgAFFH8FAAMOAAMJhwSfXwCEAAAOAAMJhwSfXwCEAAAPAAEJkQnGGgA+AAAuAAQKfxkABA8ACAl8GhIKABUCAA8ACAkxGhIKABUCABAAAwn4HkBIAA8BAA4AAgkaGi+aAJcAAAEuAAUUBgkOABEA7xEA.Asomyrh:BAABLgAECn8lAAMRAAkJmxV4GQA4AgARAAkJmxV4GQA4AgASAAEJPQFwywESAAAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgYJCAAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgAECgQJBAAAAA==.',
Av='Averyl:BAAALgAECgUJBQAAAA==.Aviendha:BAAALgAECgYJCQAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAITAAgJLQptKgCKAQATAAgJLQptKgCKAQAAAA==.',
Az='Azenith:BAABLgAECn8cAAMSAAYJgRzTaACbAQASAAYJgRzTaACbAQAUAAEJrQh4UwAnAAAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bamboozle:BAAALgADCgcJBwAAAA==.Bananer:BAABLgAECn8iAAIVAAkJeBSpIgDcAQAVAAkJeBSpIgDcAQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Bb='Bbqlol:BAAALgAECgYJBwABLgAECgYJHgASAGccAA==.',
Be='Beaugersugar:BAAALgAECgQJBQAAAA==.Beebler:BAABLgAECn8YAAIPAAgJnhedDgDCAQAPAAgJnhedDgDCAQAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgAECgcJCAAAAA==.Beowulf:BAAALgAECgEJAwAAAA==.Bestt:BAAALgAECgQJCQAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Bigbluenfab:BAAALgADCggJBQAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigholylady:BAAALgADCgkJCQAAAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigocagler:BAAALgAECgcJAQAAAA==.Bigolchungus:BAABLgAECn8eAAMUAAkJwRpuCQA7AgAUAAgJeBluCQA7AgASAAUJ6Bi4uQAOAQAAAA==.Bigpapadots:BAAALgAECgMJAwAAAA==.Bigshizz:BAAALgAECgQJBgABLgAECgcJFQAFAAEhAA==.Bippysmasher:BAABLgAECn8kAAIWAAkJaxI0RwCtAQAWAAkJaxI0RwCtAQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.',
Bl='Blacblood:BAABLgAECn8fAAIIAAkJYRGRDgCIAQAIAAkJYRGRDgCIAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJEQAAAA==.Blindweiss:BAAALgAFFAEJAQABLgAFFAcJFQAXABwUAA==.Blinkies:BAABLgAECn8iAAMYAAkJbSDrAADYAgAYAAkJbSDrAADYAgAXAAUJlg9wuwANAQAAAA==.Blinkster:BAAALgAECgEJBAAAAA==.Bloodfushion:BAAALgADCgYJBgAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgAECgMJAwANAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8PAAIDAAcJGRktDwDeAQADAAcJGRktDwDeAQAuAAQKfysAAgMACQmNI7kJAAcDAAMACQmNI7kJAAcDAAAA.Boolala:BAAALgADCgEJAQAAAA==.Borstenne:BAACLgAFFH8RAAIZAAQJGR12TgBQAQAZAAQJGR12TgBQAQAuAAQKfykAAhkACQm7JMMSANYCABkACQm7JMMSANYCAAAA.',
Br='Brake:BAACLgAFFH8KAAIZAAMJnxEapgDMAAAZAAMJnxEapgDMAAAuAAQKfyYAAhkACAlXHvU1AF8CABkACAlXHvU1AF8CAAAA.Brese:BAAALgAECgIJAgABLgAFFAQJEgAWAHIZAQ==.Breseayaya:BAACLgAFFH8SAAIWAAQJchn6PAArAQAWAAQJchn6PAArAQAuAAQKfy0AAhYACQkrIS8NANoCABYACQkrIS8NANoCAAAA.Breseshh:BAAALgAECgcJEwABLgAFFAQJEgAWAHIZAA==.Brickbeard:BAACLgAFFH8LAAIaAAQJeRHUBAA5AQAaAAQJeRHUBAA5AQAuAAQKfy0AAxoACQl0FYkGABACABoACQl0FYkGABACABsABwnDDeUZAH0BAAAA.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJEgABLgAFFAgJGAASAJ0cAA==.Bricksquad:BAAALgAECgMJAwABLgAFFAMJBQAWAHodAA==.Brickthrow:BAACLgAFFH8YAAMSAAgJnRx0GwCTAQASAAYJ1hp0GwCTAQARAAMJOQjSKwDIAAAuAAQKfzMAAxIACQmsJMAHACwDABIACQmsJMAHACwDABEABQlyBB1xAG4AAAAA.Bronkle:BAAALgAECgUJBQABLgAFFAQJCwAaAHkRAA==.',
Bu='Buhleed:BAAALgAECgIJAgAAAA==.Burgerburn:BAAALgAECgUJBQAAAA==.',
By='Bytheway:BAABLgAECn8WAAIcAAgJ4RPxLQBpAQAcAAgJ4RPxLQBpAQAAAA==.',
['Bà']='Bàbÿ:BAAALgAECgcJDgAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAACLgAFFH8SAAIMAAQJdhL1LgDwAAAMAAQJdhL1LgDwAAAuAAQKfzEABAwACQm4I5sIACwDAAwACQm4I5sIACwDAAUAAglbGyl6AE4AAAsAAQlKAac3ABkAAAAA.Cadsune:BAAALgAECgYJDAAAAA==.Caelesti:BAABLgAECn8mAAMHAAgJVxOCHwDDAQAHAAgJVxOCHwDDAQAcAAcJ6RYEJgCaAQAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAgAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQABLgAFFAgJGwAdAMIXAA==.Chelbur:BAAALgADCgEJAQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chosmuke:BAAALgAECgEJAwAAAA==.Chowderhead:BAABLgAECn8UAAIbAAYJYxzhDgDcAQAbAAYJYxzhDgDcAQAAAA==.',
Ci='Cileb:BAACLgAFFH8GAAIXAAUJSBjuXQAvAQAXAAUJSBjuXQAvAQAuAAQKfzUAAhcACQmkJJcLABoDABcACQmkJJcLABoDAAAA.Civik:BAABLgAECn9KAAIDAAkJciMVCQAOAwADAAkJciMVCQAOAwAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAFFAMJBQAWAHodAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAACLgAFFH8SAAISAAQJ0xUNPAAuAQASAAQJ0xUNPAAuAQAuAAQKfzAAAhIACQldGmE8ABACABIACQldGmE8ABACAAAA.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAFFAQJBQAWAAkFAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJJwAJAAkjAA==.Copperit:BAABLgAECn8nAAIJAAkJCSOQAgBDAwAJAAkJCSOQAgBDAwAAAA==.Cornburglar:BAACLgAFFH8LAAIVAAQJwB9VEAB9AQAVAAQJwB9VEAB9AQAuAAQKfzcAAhUACAlcJS8IANsCABUACAlcJS8IANsCAAAA.Cowtaclysmic:BAABLgAECn8jAAMZAAgJBhPNfQBlAQAZAAgJmgzNfQBlAQAJAAUJShbTKQAGAQAAAA==.',
Cr='Crackersz:BAABLgAECn8WAAMOAAcJHQi0hwDHAAAOAAcJHQi0hwDHAAAQAAMJGAQihQBhAAAAAA==.Cranjis:BAABLgAECn9NAAIeAAkJ9iE+BwAoAwAeAAkJ9iE+BwAoAwAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Crunchwrap:BAABLgAECn8pAAIFAAkJFw4VJgCZAQAFAAkJFw4VJgCZAQAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgcJBwAAAA==.',
Cu='Curadora:BAAALgADCgQJBAAAAA==.Cursereflect:BAABLgAECn8iAAMfAAkJyQ4PUgClAQAfAAkJyQ4PUgClAQAbAAEJAABbVQAAAAAAAA==.Curseus:BAAALgAECgIJBAAAAA==.',
Cy='Cyberwin:BAAALgAECgEJAQAAAA==.',
Da='Damncats:BAABLgAECn8+AAIVAAkJJRJeIgDeAQAVAAkJJRJeIgDeAQAAAA==.Dandinn:BAAALgAECgYJCQAAAA==.Danielsboone:BAABLgAECn8fAAIDAAgJfA5UYACCAQADAAgJfA5UYACCAQAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJCAABLgAFFAQJDAAQAMMMAA==.Darknemesis:BAAALgAECgEJAQAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAFFAIJAwABLgAFFAYJOAAbAPsiAA==.',
De='Deadhippocow:BAABLgAECn8aAAIMAAYJfR2GLAD0AQAMAAYJfR2GLAD0AQAAAA==.Deathwavez:BAACLgAFFH8SAAIZAAQJqhMLZwApAQAZAAQJqhMLZwApAQAuAAQKfxoAAhkABwkwFwFlAMUBABkABwkwFwFlAMUBAAAA.Declän:BAAALgAECgMJBAABLgAECgYJGgAMAH0dAA==.Decurse:BAABLgAECn8iAAIfAAgJThU1VQCcAQAfAAgJThU1VQCcAQAAAA==.Deldrin:BAABLgAECn8hAAIXAAkJAhMdTwDrAQAXAAkJAhMdTwDrAQAAAA==.Demayy:BAABLgAECn8uAAIeAAkJKxOJIgAEAgAeAAkJKxOJIgAEAgAAAA==.Demona:BAACLgAFFH8LAAMfAAQJAwyyXgAGAQAfAAQJAwyyXgAGAQAaAAEJkgcjKwA9AAAuAAQKfyUAAxsACAkxGe4pABoBAB8ABwnIFbh1AE0BABsABAngE+4pABoBAAAA.Demonix:BAABLgAECn8YAAIfAAgJlRp1NQACAgAfAAgJlRp1NQACAgAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAACLgAFFH8KAAIXAAQJdwdmbgAMAQAXAAQJdwdmbgAMAQAuAAQKfzgAAhcACQlODydXANQBABcACQlODydXANQBAAAA.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAABLgAECn8eAAMSAAYJZxypdwB8AQASAAYJZxypdwB8AQARAAIJsASOgQBFAAAAAA==.Dinobrass:BAABLgAECn8jAAIEAAgJtA0oEQBEAQAEAAgJtA0oEQBEAQAAAA==.Dirktheshiny:BAAALgAECgkJDwABLgAECgkJPQAFAIEbAA==.Dirtylöbster:BAACLgAFFH8OAAIXAAMJTCHYJwAUAQAXAAMJTCHYJwAUAQAuAAQKfzUAAhcACQkKJV4JAC4DABcACQkKJV4JAC4DAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgYJEQABLgAECgYJHgASAGccAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAAALgAECgcJEwAAAA==.Dorfydorf:BAAALgAECgEJAgAAAA==.Dorose:BAAALgAECgEJAgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Dranight:BAAALgAECgcJBwABLgAECgkJSgADAHIjAA==.Dreats:BAAALgAECgYJCQAAAA==.Drewmee:BAABLgAECn8YAAISAAkJHgntjQBTAQASAAkJHgntjQBTAQAAAA==.Dronar:BAABLgAFFH8FAAIOAAUJCgluLQAlAQAOAAUJCgluLQAlAQABLgAECgkJIwALAAEgAA==.Drublood:BAAALgAECgcJCwABLgAECgkJGAASAB4JAA==.Drunkinmasta:BAAALgAECgEJAQABLgAFFAQJEAASAB4WAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Duckbeak:BAAALgADCgQJAwAAAA==.Dune:BAAALgADCgcJBwAAAA==.Duwork:BAABLgAECn8VAAIFAAcJASF1HADhAQAFAAcJASF1HADhAQAAAA==.',
['Dæ']='Dæmona:BAABLgAECn8VAAIgAAkJmxJwFQDeAQAgAAkJmxJwFQDeAQAAAA==.',
Eb='Ebk:BAAALgAECgcJDAAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
Ei='Eight:BAAALgADCggJGAAAAA==.',
El='Eladus:BAAALgAECgcJEAAAAA==.Elemnt:BAAALgAECgYJDQABLgAFFAQJEAASAB4WAA==.Elesus:BAAALgAECggJDQABLgAECgkJQwAhAJUhAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJDgAAAA==.Emrys:BAAALgAECgMJAgAAAA==.',
En='Enhshaman:BAACLgAFFH8FAAIeAAMJGQZVQgCOAAAeAAMJGQZVQgCOAAAuAAQKfxYAAh4ACQn+FJQjAP0BAB4ACQn+FJQjAP0BAAAA.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.Evilinne:BAAALgADCgIJAgAAAA==.Evânescence:BAAALgAECgEJAQAAAA==.',
Ex='Excaliburn:BAAALgAECgEJAwAAAA==.',
Ez='Ezekial:BAAALgAECgQJBAAAAA==.Ezkal:BAACLgAFFH8RAAIZAAUJQBu6ZAAsAQAZAAUJQBu6ZAAsAQAuAAQKfywAAxkACQnsGaEYAOgCABkACQnsGaEYAOgCAAkABgktFcIqAAABAAAA.',
Fa='Faithastray:BAAALgAECgMJAwAAAA==.Faithpasse:BAABLgAECn82AAMeAAgJWBwbEgCJAgAeAAgJWBwbEgCJAgATAAEJ9gPfhgApAAAAAA==.Falcorne:BAABLgAECn80AAIDAAkJqiKmBwAcAwADAAkJqiKmBwAcAwAAAA==.Fatlipz:BAABLgAECn8cAAIhAAcJdgqdMgBNAQAhAAcJdgqdMgBNAQAAAA==.Fay:BAAALgADCgEJAQABLgAECgYJCAANAAAAAA==.',
Fe='Felondar:BAABLgAECn8iAAMgAAkJVgtQIQBpAQAgAAkJVgtQIQBpAQAWAAYJsASzmwDhAAAAAA==.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8ZAAMJAAkJhBsxDABOAgAJAAcJsBsxDABOAgAZAAgJvhiIagC3AQAAAA==.',
Fi='Finnadin:BAABLgAECn8kAAISAAkJ4R7FGACsAgASAAkJ4R7FGACsAgAAAA==.Finns:BAAALgAECgcJDgAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAABLgAECn8dAAIDAAgJ0xmDOAD3AQADAAgJ0xmDOAD3AQAAAA==.Fistobeef:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.',
Fl='Fleable:BAAALgAECgQJAQAAAA==.Flysky:BAACLgAFFH8bAAIdAAgJwhejBQBjAgAdAAgJwhejBQBjAgAuAAQKfywABB0ACQnFI4kCAEcDAB0ACQnFI4kCAEcDACIACAnIJDQHAOMCAAYAAQl3DyBBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECggJDQAAAA==.',
Fr='Freakmeout:BAAALgAECgQJBAAAAA==.Freshpot:BAAALgAECgMJAwAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgAECgEJAQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJDgABLgAFFAUJEQAZAEAbAA==.Futuredragoo:BAAALgAECgcJDAABLgAFFAUJEQAZAEAbAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Fy='Fyska:BAAALgADCgEJAQAAAA==.',
Ga='Gabriella:BAAALgAECgYJDAAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQANAAAAAA==.Galnannix:BAAALgAECggJDQAAAA==.Gardrake:BAABLgAECn8zAAMiAAkJrBnMEABeAgAiAAkJrBnMEABeAgAdAAcJqhCrHQCWAQAAAA==.Gastapha:BAABLgAECn8XAAIWAAgJYgZnoADeAAAWAAgJYgZnoADeAAAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMVAAgJCxMcMADvAQAVAAgJCxMcMADvAQAjAAEJAACvjAAAAAAAAA==.Gehennas:BAABLgAFFH8FAAIWAAMJeh3tUAD0AAAWAAMJeh3tUAD0AAAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Go='Goku:BAAALgAFFAIJAgAAAA==.Goofykirby:BAAALgADCgcJFQAAAA==.Googoo:BAABLgAECn8UAAIZAAkJrhMaOQAZAgAZAAkJrhMaOQAZAgAAAA==.Googoogagaa:BAACLgAFFH8MAAIcAAQJkhAyHAAHAQAcAAQJkhAyHAAHAQAuAAQKf0YAAxwACQkKHkINAH8CABwACQkKHkINAH8CAAcABwnyEgMqAKIBAAAA.Gotlieb:BAAALgAECggJCQAAAA==.',
Gr='Grenno:BAAALgAECgcJBwABLgAFFAgJIAAZANsaAA==.Greystorm:BAAALgAECgIJAgAAAA==.Greythorn:BAAALgADCgkJCQABLgAECgkJSgADAHIjAA==.Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQANAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8hAAMEAAgJNRJYBwCnAQAEAAcJXRRYBwCnAQACAAUJnwzJFgAXAQAuAAQKfxQAAgQABwkJJOIRAKoCAAQABwkJJOIRAKoCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hakarren:BAAALgAECgYJBgAAAA==.Hamatza:BAAALgAECgEJAgAAAA==.Hammerinfred:BAAALgAECgQJBwAAAA==.Hawkmoon:BAAALgAECgEJAwAAAA==.',
He='Healingisfun:BAAALgAECgMJBAAAAA==.Helhunter:BAABLgAECn8yAAIWAAkJbRIGRwCuAQAWAAkJbRIGRwCuAQAAAA==.Hellock:BAAALgAFFAEJAQAAAA==.',
Hi='Hippysmasher:BAAALgAECgIJAgAAAA==.',
Ho='Hodgepodge:BAAALgAECgEJAgAAAA==.Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgMJBQAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holybob:BAAALgAECgQJCAAAAA==.Holyhooters:BAABLgAECn87AAISAAkJ2yHhDgDsAgASAAkJ2yHhDgDsAgAAAA==.Holypablo:BAAALgAECgQJBgABLgAECgkJTgAhAJAfAA==.Homefries:BAAALgADCgYJBgABLgAECgYJGgAMAH0dAA==.Honkytonk:BAABLgAECn8aAAMGAAgJKQtAIgAYAQAGAAYJ7QlAIgAYAQAiAAcJeAmsOAATAQAAAA==.Honor:BAAALgAECgcJBwABLgAECgkJOwASAI8jAA==.Honour:BAABLgAECn87AAISAAkJjyOmDQD2AgASAAkJjyOmDQD2AgAAAA==.',
Hr='Hrathdemon:BAACLgAFFH8RAAIWAAQJlxdWPgAnAQAWAAQJlxdWPgAnAQAuAAQKfysAAhYACQntILAQALoCABYACQntILAQALoCAAAA.Hrathid:BAAALgADCgUJDAABLgAFFAQJEQAWAJcXAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8KAAISAAMJiiBUEgATAQASAAMJiiBUEgATAQAuAAQKfywAAhIACQnqI7oFAHIDABIACQnqI7oFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAABLgAECn8YAAMSAAkJwRuzLgBEAgASAAkJwRuzLgBEAgARAAIJWwfAgwBAAAAAAA==.',
Ib='Ibleedorange:BAAALgAECgcJDAAAAA==.',
Ic='Icehawk:BAAALgAECgMJAwAAAA==.Ickeetard:BAABLgAECn8cAAMhAAkJlhFUMABaAQAhAAcJFA9UMABaAQAHAAYJmBC0PwDrAAAAAA==.',
Id='Idiot:BAAALgAECgMJBAAAAA==.Idiotbreath:BAABLgAECn82AAMiAAkJFSCOCADMAgAiAAkJFSCOCADMAgAGAAMJmQmDMACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgAECgEJAgAAAA==.',
Im='Immorlich:BAAALgAECgEJAQAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJCQAAAA==.Inflexi:BAACLgAFFH8HAAIDAAQJyRT9NwA3AQADAAQJyRT9NwA3AQAuAAQKfy0AAwMACQlqINMMAOkCAAMACQmYH9MMAOkCAAQACAnKGvAYAGQCAAAA.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAABLgAECn8YAAITAAYJWhnfLgBKAQATAAYJWhnfLgBKAQAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn8/AAQMAAkJIB5ADgDkAgAMAAkJIB5ADgDkAgAFAAgJFyCuFAAqAgALAAMJ2hYFOADAAAAAAA==.',
Iv='Iver:BAAALgAECgUJBgABLgAECgcJEQANAAAAAA==.',
Ja='Jangle:BAAALgADCgYJBwAAAA==.',
Je='Jeffblades:BAAALgAECgYJDQAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJBgANAAAAAA==.',
Jj='Jjooaacchhim:BAAALgAECgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8jAAIDAAkJfBtaLAAnAgADAAkJfBtaLAAnAgAAAA==.',
Ka='Kadillac:BAAALgAECgcJEwAAAA==.Kaelira:BAAALgADCgIJAgAAAA==.Kairei:BAAALgAECgcJDgAAAA==.Kakashi:BAAALgADCgEJAQAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAACLgAFFH8UAAISAAUJVB+jJgBoAQASAAUJVB+jJgBoAQAuAAQKfx0AAxIACQl1IkkRANoCABIACQkUIkkRANoCABQAAQlIJYE2AGkAAAAA.Katalina:BAABLgAECn8wAAMkAAgJmBGMDQB2AQAkAAgJmBGMDQB2AQAgAAYJpwsROAAlAQAAAA==.Kawer:BAAALgAECgQJCQAAAA==.Kawnzerker:BAAALgADCgkJCQAAAA==.',
Ke='Kelstormhoof:BAAALgADCgcJFgABLgAECgEJAQANAAAAAA==.Kernel:BAAALgAECgEJAQABLgAFFAQJCwAVAMAfAA==.',
Kh='Kham:BAACLgAFFH8TAAIVAAQJ4B7VFwBPAQAVAAQJ4B7VFwBPAQAuAAQKf0QAAhUACQlgJKEDAC4DABUACQlgJKEDAC4DAAAA.',
Ki='Killmaim:BAABLgAECn8ZAAIVAAgJwRllIABPAgAVAAgJwRllIABPAgAAAA==.Kitsuko:BAABLgAECn80AAMOAAkJFg/CPQCzAQAOAAkJFg/CPQCzAQAQAAkJxRAXLACRAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ko='Kokeovrdose:BAAALgAECgQJBAABLgAECgYJFAAXAAYWAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuli:BAAALgAECgEJAgAAAA==.Kuraishin:BAAALgAFFAEJAQABLgAFFAcJFQAXABwUAA==.Kuvare:BAAALgAECgMJAwAAAA==.',
['Kè']='Kèlton:BAAALgAECgUJCgAAAA==.',
La='Lanas:BAEALgAECgkJAwABLgAFFAQJEwASAMMQAA==.Laocoon:BAAALgAECggJCAABLgAECgkJOwASANshAA==.Lavashiza:BAAALgAECgYJEwAAAA==.Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAAALgAECgcJEwAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAgAAAA==.Leedaddydk:BAAALgAECgQJCgAAAA==.Leroyjenkins:BAABLgAECn8XAAIlAAcJ8BvoAgBVAgAlAAcJ8BvoAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.',
Li='Lightstorm:BAAALgAECgYJEAAAAA==.Linaria:BAAALgAECgUJCAAAAA==.Linø:BAAALgAECgEJAQAAAA==.Lissara:BAABLgAECn8ZAAIiAAgJExA3MwBkAQAiAAgJExA3MwBkAQAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAACLgAFFH8SAAImAAQJqRx9GQBSAQAmAAQJqRx9GQBSAQAuAAQKfyMAAiYACQnCHAwOAFUCACYACQnCHAwOAFUCAAAA.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockmogged:BAAALgAFFAIJAgAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECgkJHAADADIkAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAFFAQJDgAaAKATAA==.Luminouslexi:BAAALgAECgMJAwAAAA==.',
Ma='Macoub:BAACLgAFFH8FAAIWAAQJCQWIXQDPAAAWAAQJCQWIXQDPAAAuAAQKfxcABCAACAnFFX8mAEEBACAABgl2FX8mAEEBABYABAmMGoeZAOkAACQAAwluB7UwAD0AAAAA.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAABLgAECn8ZAAMbAAgJfQWmGgDMAAAbAAgJUQWmGgDMAAAfAAQJzAOt/ABqAAAAAA==.Mageslayer:BAABLgAECn8bAAMnAAgJmxNpHgCfAQAnAAgJGBJpHgCfAQABAAMJPRA+GACtAAAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magicstorm:BAAALgAECgYJBgAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgANAAAAAA==.Mahalleinr:BAAALgADCgEJAQAAAA==.Maiggee:BAAALgADCgMJAwAAAA==.Makkideez:BAABLgAECn8UAAInAAkJNxj1DwAqAgAnAAkJNxj1DwAqAgAAAA==.Makkii:BAAALgADCgEJAQABLgAECgkJFAAnADcYAA==.Malanara:BAAALgADCgEJAQABLgAECgkJIQAXAAITAA==.Malxt:BAAALgADCgYJBwAAAA==.Manabuns:BAABLgAECn8pAAIXAAgJ2xe+XADFAQAXAAgJ2xe+XADFAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8lAAISAAkJ/RRKQgAeAgASAAkJ/RRKQgAeAgAAAA==.Markruffalo:BAAALgAECgYJDAAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn86AAIVAAkJaBuAFABLAgAVAAkJaBuAFABLAgAAAA==.',
Mc='Mckay:BAAALgAECggJEwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8mAAIlAAgJRBSgBACiAQAlAAgJRBSgBACiAQAAAA==.Megapunk:BAAALgAECgcJDwAAAA==.Mellmaan:BAAALgAFFAIJAgAAAA==.Melys:BAAALgAECgcJEgAAAA==.Meteorite:BAAALgAECgYJCQAAAA==.Meudayr:BAABLgAECn8jAAILAAkJASBKBADSAgALAAkJASBKBADSAgAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.Mezagog:BAAALgAECgYJDwAAAA==.',
Mi='Mikehammer:BAAALgADCgcJDgAAAA==.Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAACLgAFFH8MAAIQAAQJwwy5KQDpAAAQAAQJwwy5KQDpAAAuAAQKfx4AAhAACAltHCISAJICABAACAltHCISAJICAAAA.Mittenss:BAAALgADCgIJAgAAAA==.',
Mo='Moistblanket:BAAALgAECgUJBwAAAA==.Mojorisin:BAABLgAECn8jAAICAAkJ6xqjDQBNAgACAAkJ6xqjDQBNAgAAAA==.Moobear:BAAALgAECgcJDAAAAA==.Moonchiken:BAAALgAECgEJCgAAAA==.Moozlock:BAABLgAECn8rAAIfAAkJEhLfSwC2AQAfAAkJEhLfSwC2AQAAAA==.Moscovio:BAAALgAFFAIJBAABLgAFFAMJBQASAFITAA==.Mosspaws:BAABLgAECn82AAMMAAkJbiSdBgBLAwAMAAkJbiSdBgBLAwAFAAQJZB9LNQA+AQAAAA==.',
Mt='Mtndewyou:BAAALgAECgYJEAAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.Mutterutters:BAAALgAECgEJAgAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.Myrollin:BAAALgAECgIJAgAAAA==.',
Na='Naetara:BAAALgADCgEJAQAAAA==.Narfiy:BAAALgADCgEJAQAAAA==.Narisanna:BAAALgAFFAEJAgAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBgAAAA==.',
Nm='Nme:BAABLgAECn8lAAMXAAkJoBCcWgDKAQAXAAkJoBCcWgDKAQAlAAYJiw9LCQBWAQAAAA==.',
No='Nocturnos:BAABLgAECn8uAAMfAAkJZR29GgCCAgAfAAkJZR29GgCCAgAaAAIJ9yC5LQBiAAAAAA==.Noggin:BAABLgAECn8rAAMRAAkJRyH/BAAcAwARAAkJRyH/BAAcAwASAAgJ/BBPaQCaAQAAAA==.Nonform:BAABLgAECn89AAQFAAkJgRtwDACOAgAFAAkJgRtwDACOAgAKAAEJwRW3SgA/AAAMAAEJdAED7AAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECgcJDQANAAAAAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQANAAAAAA==.Novamancer:BAAALgAECgEJAQAAAA==.Noxta:BAAALgAECggJEgAAAA==.',
Nu='Numonixx:BAACLgAFFH8gAAMGAAYJfg5tBgDqAAAiAAYJCA2jJwAoAQAGAAQJowptBgDqAAAuAAQKfzoAAwYACQkFH3gCAJMCAAYACAmsIHgCAJMCACIACAnGGwgUADsCAAAA.Nutlessfred:BAAALgAECgEJAQAAAA==.',
Ny='Nymage:BAABLgAECn9ZAAIXAAkJHBvzKQBwAgAXAAkJHBvzKQBwAgAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogmund:BAAALgAECgYJEQAAAA==.',
Oh='Ohnospiders:BAABLgAECn8yAAMZAAkJpBdcMwAvAgAZAAkJpBdcMwAvAgAIAAQJ4RTEIADDAAAAAA==.Ohpig:BAAALgAECgMJAwAAAA==.',
Ok='Okaerisan:BAABLgAECn8VAAIUAAkJZxQfFQB9AQAUAAkJZxQfFQB9AQAAAA==.',
Ol='Olord:BAAALgADCgYJCQAAAA==.',
Om='Omarcuthlink:BAAALgAECgEJAQABLgAFFAQJCwAaAHkRAA==.Omgbbqq:BAAALgAECggJCAABLgAFFAMJCQADAKwbAA==.',
On='Onilecram:BAAALgAECgIJAgAAAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECggJEQAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Ou='Outlast:BAACLgAFFH8QAAISAAQJHhZAOAA2AQASAAQJHhZAOAA2AQAuAAQKfy8AAhIACQm1HbQRAAQDABIACQm1HbQRAAQDAAAA.',
Pa='Paants:BAABLgAECn8iAAIoAAkJiAz3HgA3AQAoAAkJiAz3HgA3AQAAAA==.Pacid:BAAALgAECgYJCAAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Pakal:BAAALgAECgMJAwAAAA==.Palebull:BAAALgADCgYJCAAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8XAAIWAAgJfxzsCAB7AgAWAAgJfxzsCAB7AgAuAAQKfzMAAhYACQkEJWEEAD4DABYACQkEJWEEAD4DAAAA.Parmageddon:BAAALgAECgEJAQABLgAFFAQJDgAoAPggAA==.Parmigiano:BAAALgADCgEJAQABLgAFFAQJDgAoAPggAA==.Parmrageiano:BAABLgAFFH8OAAIoAAQJ+CAkDABhAQAoAAQJ+CAkDABhAQAAAA==.Parms:BAABLgAECn8ZAAQCAAgJ+xOaJQBwAQACAAgJ6xGaJQBwAQAEAAYJhQxETQAcAQADAAIJORANowCFAAABLgAFFAQJDgAoAPggAA==.Parmy:BAAALgAECgEJAQAAAA==.',
Pe='Peanought:BAABLgAECn8qAAMIAAkJjxYBBgDJAQAIAAgJsRcBBgDJAQAZAAkJ5A7+XwCnAQAAAA==.Peidro:BAABLgAECn8aAAISAAcJtA2BpAAuAQASAAcJtA2BpAAuAQAAAA==.Pentacles:BAABLgAECn8tAAILAAkJsCAMBwCDAgALAAkJsCAMBwCDAgAAAA==.',
Pi='Pijak:BAAALgAECgcJEwAAAA==.Pinkpaw:BAABLgAECn8iAAQLAAkJFh+eBADJAgALAAkJFh+eBADJAgAMAAUJthoRSABsAQAKAAEJuBJLSABEAAAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8JAAMmAAMJ3iTvCABGAQAmAAMJ3iTvCABGAQATAAEJlCP0NgBkAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCQAmAN4kAA==.Postscalone:BAAALgAECgYJBwAAAA==.Potatoes:BAABLgAECn8VAAMbAAgJBgiWHABpAQAbAAgJBgiWHABpAQAfAAIJCQJIFAE6AAAAAA==.',
Pr='Pruflas:BAABLgAECn8aAAIZAAgJZAs4iwBLAQAZAAgJZAs4iwBLAQAAAA==.',
Ps='Psycodk:BAACLgAFFH8IAAIZAAQJxxyDSABdAQAZAAQJxxyDSABdAQAuAAQKfxYAAhkACAmYGO1qAI0BABkACAmYGO1qAI0BAAAA.',
Pu='Puffdaddie:BAAALgAECgIJAgABLgAECgcJIQASADwhAA==.Pumpin:BAABLgAECn8XAAITAAUJFCQIKgBoAQATAAUJFCQIKgBoAQAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
['Pä']='Päcid:BAAALgADCgEJAQAAAA==.',
Qk='Qkn:BAAALgAECgUJEQAAAA==.',
Qu='Quickswipe:BAABLgAFFH8GAAInAAMJxSDYIAAWAQAnAAMJxSDYIAAWAQABLgAFFAYJOAAbAPsiAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgYJCwABLgAECgcJCQANAAAAAA==.Ralee:BAAALgADCgcJCQAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Rastabution:BAAALgAECgkJAQAAAA==.Ratoncita:BAAALgAECgEJAgAAAA==.Raynne:BAAALgAECgIJAgAAAA==.Rayzee:BAAALgADCgUJBQAAAA==.',
Re='Reaperjoe:BAAALgAFFAEJAgAAAA==.Rehab:BAACLgAFFH8FAAISAAMJ1RNyZwDZAAASAAMJ1RNyZwDZAAAuAAQKfxUAAhIACQlbHK4vAGQCABIACQlbHK4vAGQCAAAA.Rehna:BAAALgAECgYJBgABLgAFFAQJEgAHAM0RAA==.Rek:BAAALgAECgEJAQABLgAECgkJIwALAAEgAA==.Rektributio:BAACLgAFFH8eAAISAAgJCyAjBACbAgASAAgJCyAjBACbAgAuAAQKfzcAAhIACQkgJZgGADoDABIACQkgJZgGADoDAAAA.Resurection:BAAALgAECgIJAwAAAA==.Revalation:BAABLgAECn8nAAIMAAkJUh+EFQCaAgAMAAkJUh+EFQCaAgAAAA==.Revenancer:BAAALgAECgEJAgAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgANAAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Ribeyejoe:BAAALgADCgEJAQAAAA==.Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAABLgAECn8wAAMVAAgJeh/IFQBAAgAVAAcJkyDIFQBAAgAoAAgJCRd+EgC/AQAAAA==.Roadtrip:BAAALgAECgMJBAAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJBAAAAA==.Rottingslow:BAABLgAFFH8IAAIHAAMJ9wDCKgBpAAAHAAMJ9wDCKgBpAAABLgAFFAgJIQAJAHcgAA==.',
Sa='Sanford:BAAALgAECgUJBQAAAA==.Saragos:BAAALgADCgcJBgABLgAFFAcJFQAXABwUAA==.Saucerdote:BAABLgAECn8eAAMhAAkJmBX1HgDTAQAhAAcJGxf1HgDTAQAcAAkJFAm7LwBeAQAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAcJFQAXABwUAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAACLgAFFH8IAAIWAAQJ9RKxSQAGAQAWAAQJ9RKxSQAGAQAuAAQKfysAAhYACQl7H2APAMUCABYACQl7H2APAMUCAAAA.Selkie:BAABLgAECn8mAAIPAAkJvg/jDQDOAQAPAAkJvg/jDQDOAQAAAA==.Seragosa:BAAALgAFFAEJAQABLgAFFAcJFQAXABwUAA==.',
Sh='Shakakhan:BAAALgAECgYJDAABLgAECgYJHgASAGccAA==.Shambeau:BAAALgADCgQJBAAAAA==.Shamrun:BAAALgADCgQJBQAAAA==.Shamshielder:BAECLgAFFH8MAAQIAAUJwxBzEAAKAQAIAAQJZwpzEAAKAQAJAAIJhiMdOABRAAAZAAEJ6QPqDAE/AAAuAAQKfy0ABAkACQmZI3MFANACAAkACQmZI3MFANACAAgABgmlG+QNAJUBABkAAQm5CcCFASkAAAAA.Shapper:BAAALgAECgQJBQAAAA==.Sharick:BAAALgAECgQJBQAAAA==.Shawlee:BAABLgAECn8tAAMOAAgJzBCYWgBIAQAOAAgJzBCYWgBIAQAQAAgJOwriVADiAAAAAA==.Sheezie:BAACLgAFFH8HAAIOAAMJExq7OgDwAAAOAAMJExq7OgDwAAAuAAQKf0MAAw4ACQmkISYFAF4DAA4ACQmkISYFAF4DAA8ABgkUGC0UAHMBAAAA.Shellcow:BAAALgAECgYJBgABLgAECgkJIgAYAG0gAA==.Shellter:BAAALgAECgEJAgABLgAECgkJIgAYAG0gAA==.Shellwit:BAAALgAECgMJBgABLgAECgkJIgAYAG0gAA==.Sheph:BAAALgAFFAEJAQAAAA==.Shetmage:BAACLgAFFH8WAAIXAAcJdwtPMgChAQAXAAcJdwtPMgChAQAuAAQKfykAAhcACQnDIF4jAI0CABcACQnDIF4jAI0CAAAA.Shettdh:BAAALgAECgEJAwAAAA==.Shettrah:BAABLgAECn8UAAIFAAYJ+hqLKgB8AQAFAAYJ+hqLKgB8AQABLgAFFAcJFgAXAHcLAA==.Shienro:BAAALgAECgQJBAABLgAECgQJCQANAAAAAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAABLgAECn8jAAISAAkJNhEOXwCxAQASAAkJNhEOXwCxAQAAAA==.Shuck:BAAALgAECgQJBAABLgAFFAQJCwAVAMAfAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Sibyx:BAAALgAECgYJDwABLgAECgYJHgASAGccAA==.Siickboy:BAAALgAECgQJCQAAAA==.Sijious:BAAALgAECgQJBwAAAA==.Silveah:BAAALgADCgEJAQAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.',
Sk='Skinable:BAAALgAFFAEJAQAAAA==.Skora:BAAALgADCgIJAgABLgAECgkJJQASAP0UAA==.Skyland:BAAALgADCgcJDQABLgAFFAgJGwAdAMIXAA==.Skyli:BAAALgAECgUJCAABLgAECgkJKAAOACsgAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Sneez:BAAALgAFFAEJAQABLgAFFAQJEwAVAEgVAA==.Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAACLgAFFH8SAAIRAAQJNhqdIQAMAQARAAQJNhqdIQAMAQAuAAQKfycAAhEACQmfH7wIAOMCABEACQmfH7wIAOMCAAAA.Sorrie:BAAALgAECgEJAQAAAA==.Sortiarius:BAAALgADCgkJCQAAAA==.',
Sp='Spud:BAAALgADCgcJBwABLgAECgYJFgADAI8fAA==.Spyroh:BAABLgAECn8bAAQGAAYJ6BLuGQBlAQAGAAYJcBDuGQBlAQAiAAUJGBJuRwAJAQAdAAEJ2wA4TwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAQJEgAHAM0RAA==.',
St='Stankydk:BAACLgAFFH8RAAMZAAcJRBRHJgDFAQAZAAYJRBRHJgDFAQAJAAEJAAAEZwAAAAAuAAQKfzIAAhkACQk+JYsFAE0DABkACQk+JYsFAE0DAAAA.Stankyeyes:BAAALgAECgYJBgAAAA==.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Staticdh:BAAALgAECggJCAABLgAFFAcJIgAXAAYiAA==.Steakhead:BAABLgAECn8oAAIFAAYJagvtSwDXAAAFAAYJagvtSwDXAAAAAA==.Stinkbombs:BAACLgAFFH8NAAIXAAYJbgPNYQAoAQAXAAYJbgPNYQAoAQAuAAQKfxUAAhcACQl6FNt2AIgBABcACQl6FNt2AIgBAAAA.Stinkerz:BAAALgAECgIJAgABLgAECgkJIgAYAG0gAA==.Stonegut:BAAALgAECggJDQAAAA==.Stunanddone:BAAALgAECgUJDgAAAA==.',
Su='Subrogue:BAABLgAFFH8FAAIjAAIJlhn+LwCXAAAjAAIJlhn+LwCXAAABLgAFFAMJBQAeABkGAA==.Suffragan:BAAALgAECgIJAgAAAA==.Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJEAAAAA==.Supreme:BAACLgAFFH8IAAIWAAMJXhrgXADRAAAWAAMJXhrgXADRAAAuAAQKfxkAAhYACAl4I24YAMMCABYACAl4I24YAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAMJAwABLgAFFAQJEgAnAIUeAA==.Swayaim:BAABLgAFFH8KAAIDAAQJ2QUaUQD/AAADAAQJ2QUaUQD/AAAAAA==.Sweatypits:BAAALgAECgYJBgABLgAFFAMJBwAOABMaAA==.Swordsaint:BAAALgAECgEJAQAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAYJDgARAO8RAA==.Sylphrena:BAACLgAFFH8SAAIHAAQJ9hTXFwD5AAAHAAQJ9hTXFwD5AAAuAAQKfygAAgcACQlQHogIAMMCAAcACQlQHogIAMMCAAAA.',
['Sí']='Sínful:BAABLgAECn8qAAIEAAkJxB9jBABqAgAEAAkJxB9jBABqAgAAAA==.',
Ta='Tacow:BAAALgAECggJEQAAAA==.Tahwe:BAAALgAECgIJAgAAAA==.Talethen:BAABLgAECn8fAAMiAAkJdRnyMQBrAQAiAAkJ8xfyMQBrAQAGAAUJMxgpIAAtAQAAAA==.Talgrin:BAAALgAECgYJBgAAAA==.Talla:BAABLgAECn8oAAIOAAkJKyBsCAAnAwAOAAkJKyBsCAAnAwAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgADCgkJIQABLgAECgEJAQANAAAAAA==.Tellus:BAAALgADCgcJCwAAAA==.Tempesttempi:BAAALgADCgcJBwAAAA==.Tewshort:BAAALgAECgQJCAABLgAFFAQJEAASAB4WAA==.',
Th='Thatbox:BAAALgAECgQJBAAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgUJEQAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAABLgAECn8UAAMTAAgJBAUEXAChAAAmAAcJQQRZWQDeAAATAAcJQgQEXAChAAAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thorfyna:BAABLgAECn8iAAIkAAkJRxQsCQDXAQAkAAkJRxQsCQDXAQAAAA==.Threzk:BAABLgAECn8eAAIbAAkJew6sDgBPAQAbAAkJew6sDgBPAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.Thunderstorm:BAAALgAECgcJBwAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8MAAIWAAUJZBMIMgBUAQAWAAUJZBMIMgBUAQAuAAQKfy8AAhYACQmGIkMLAOsCABYACQmGIkMLAOsCAAAA.Tontiamat:BAABLgAECn89AAMiAAkJXRgwFwAdAgAiAAkJXRgwFwAdAgAGAAYJawo5IAAsAQAAAA==.Tontier:BAABLgAECn8fAAQMAAgJWA0ESABsAQAMAAgJWA0ESABsAQAKAAUJNggKLwChAAALAAQJSg5TSQB9AAABLgAECgkJPQAiAF0YAA==.Totembeans:BAAALgAECgQJCwAAAA==.Totemshocker:BAACLgAFFH8FAAIQAAMJfAbVEQDXAAAQAAMJfAbVEQDXAAAuAAQKfxYAAxAACAkqGQUXAGACABAACAkqGQUXAGACAA4AAQkBDFDaACoAAAAA.Toxicshadow:BAAALgADCgQJBgAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAACLgAFFH8OAAIRAAYJ7xHeEACpAQARAAYJ7xHeEACpAQAuAAQKfxwABBEACQlOH2EMAMYCABEACAnDHmEMAMYCABIABwksDjq3ABcBABQAAgmgE3NMADgAAAAA.Trashfire:BAACLgAFFH8KAAMHAAQJIA6dGADwAAAHAAQJIA6dGADwAAAhAAIJwgF2FgB7AAAuAAQKfx0ABAcACAkXHSYQAGUCAAcACAkXHSYQAGUCABwABQknFXw2ADkBACEAAwluEWhAAK0AAAEuAAUUBgkOABEA7xEA.Treeple:BAABLgAECn8iAAMMAAkJ5xanSgBhAQAMAAcJUBOnSgBhAQAFAAUJbA6/PwALAQAAAA==.Treily:BAAALgAECgYJDwAAAA==.Tresleches:BAABLgAECn8rAAISAAkJBhLfWwC4AQASAAkJBhLfWwC4AQAAAA==.Tricket:BAABLgAECn9TAAMjAAkJeCCtAwDtAgAjAAkJeCCtAwDtAgAVAAYJKBmmUwD8AAAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAbAAYIAQ==.Truestorm:BAABLgAECn8pAAISAAkJzgvGeAB6AQASAAkJzgvGeAB6AQAAAA==.Truheals:BAAALgAECgYJCgAAAA==.',
Tu='Tuchi:BAACLgAFFH8ZAAMlAAUJCx+wAQAIAQAXAAUJkByVHgBQAQAlAAMJaxywAQAIAQAuAAQKfyYAAyUABwm9IysDAPkBABcABwliIrkyAKgCACUABgnQIisDAPkBAAAA.Tumblestone:BAAALgAECgEJAQAAAA==.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAgJFwAWAH8cAA==.',
['Tà']='Tàcobelle:BAABLgAECn8VAAIEAAgJWB5SBABtAgAEAAgJWB5SBABtAgABLgAECggJKQAXANsXAA==.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Vaelen:BAAALgAECgEJAQABLgAECggJGAAfAJUaAA==.Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgANAAAAAA==.Valhalla:BAAALgAECgYJBgAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIOAAMJriJyOAD5AAAOAAMJriJyOAD5AAAuAAQKfzEAAw4ACQllGz8SAIQCAA4ACQllGz8SAIQCABAABgkTGrc1AGABAAAA.Varanis:BAACLgAFFH8JAAIDAAMJnxZuDAD/AAADAAMJnxZuDAD/AAAuAAQKfxkAAgMACQlkIWMLAOgCAAMACQlkIWMLAOgCAAAA.',
Ve='Vegh:BAACLgAFFH8HAAIkAAMJYBjBCADBAAAkAAMJYBjBCADBAAAuAAQKf04AAiQACQnzH0sDAKoCACQACQnzH0sDAKoCAAAA.Vem:BAABLgAECn8uAAIiAAkJsR0MEABnAgAiAAkJsR0MEABnAgAAAA==.Veriale:BAAALgAECgYJCwAAAA==.Verra:BAABLgAECn84AAISAAkJWhuBJQBsAgASAAkJWhuBJQBsAgAAAA==.',
Vi='Vitriol:BAABLgAECn8gAAIVAAcJZxipMACKAQAVAAcJZxipMACKAQAAAA==.',
Vo='Voidbeaver:BAAALgAECgcJCwAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAACLgAFFH8OAAMaAAQJoBPHBQAjAQAaAAQJoBPHBQAjAQAbAAEJYQf0KQA9AAAuAAQKfx8AAhoACQl2IqsBAMoCABoACQl2IqsBAMoCAAAA.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgcJEAANAAAAAA==.Vyrros:BAAALgADCgUJBQAAAA==.',
Wa='Walji:BAABLgAECn8eAAMOAAgJyhtyFwBaAgAOAAgJyhtyFwBaAgAQAAEJWwsTrAApAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgAECgIJBAAAAA==.Wandy:BAABLgAECn80AAIfAAkJLhi0JQBFAgAfAAkJLhi0JQBFAgAAAA==.Wangstah:BAABLgAECn8cAAIDAAkJMiTBDgDXAgADAAkJMiTBDgDXAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAIVAAYJNhQUSgB8AQAVAAYJNhQUSgB8AQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJDgAAAA==.Wawatesi:BAAALgAECgMJAwAAAA==.Waytogoteam:BAACLgAFFH8JAAIDAAMJrBuzTwADAQADAAMJrBuzTwADAQAuAAQKfzgAAgMACQkpJBoLAPkCAAMACQkpJBoLAPkCAAAA.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8VAAMXAAcJHBRzJwDYAQAXAAcJHBRzJwDYAQAYAAIJBw7iBACCAAAuAAQKfzMABBcACQnEJAkNAA8DABcACQk3JAkNAA8DABgABgm+I3wDANkBACUAAQmPIMgWAGQAAAAA.Wenya:BAAALgADCgcJBwAAAA==.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgQJBAAAAA==.',
Wo='Woodyy:BAABLgAECn8iAAIZAAgJAQ0oeQBuAQAZAAgJAQ0oeQBuAQAAAA==.Woog:BAAALgAECgYJEQAAAA==.Wox:BAAALgAECggJDwAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wu='Wujustyle:BAAALgAECgcJBwAAAA==.Wulfgar:BAAALgAFFAEJAQAAAA==.',
Wy='Wyldspirit:BAABLgAECn8fAAIDAAgJUg5wXACMAQADAAgJUg5wXACMAQAAAA==.Wyreless:BAAALgADCgYJBgABLgAECgkJNQAKABUWAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgAECgEJAQAAAA==.',
Xe='Xe:BAAALgAECgYJBgABLgAECgkJUwAjAHggAA==.',
Xr='Xrind:BAAALgADCgEJAQAAAA==.',
Ya='Yaass:BAAALgAECgMJAwAAAA==.',
Ye='Yem:BAACLgAFFH84AAQbAAYJ+yI3AgDRAQAbAAYJEiA3AgDRAQAfAAUJeiCAOQBdAQAaAAIJYSIRHQBTAAAuAAQKfzYAAxsACQmiIzkGAGwCABsABgncIzkGAGwCAB8ABgliI1VJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAILAAcJvxm2CAAfAgALAAcJvxm2CAAfAgABLgAFFAUJFAASAFQfAA==.Yoverre:BAAALgAECgMJAwAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAANAAAAAA==.Zanzabar:BAABLgAECn8XAAISAAkJvBlMPwAGAgASAAkJvBlMPwAGAgAAAA==.Zaraelitha:BAAALgAECgYJBwAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgYJCQAAAA==.Zeodrik:BAABLgAECn8cAAIVAAcJYRmxNQDSAQAVAAcJYRmxNQDSAQAAAA==.',
Zh='Zhenya:BAACLgAFFH8SAAIXAAQJ+hISYAArAQAXAAQJ+hISYAArAQAuAAQKfycAAxcACQltGFlKAPkBABcACQltGFlKAPkBACUABAkvD+gOANUAAAAA.',
Zi='Zidguard:BAAALgAECgYJBwAAAA==.Zigzauer:BAAALgAECgQJBAAAAA==.Ziroken:BAAALgADCgUJBQAAAA==.',
Zo='Zombeaver:BAAALgAECgIJAgAAAA==.',
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
