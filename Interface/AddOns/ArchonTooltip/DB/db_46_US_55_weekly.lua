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

local lookup = {'Rogue-Assassination','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Evoker-Devastation','Priest-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Feral','Druid-Restoration','Druid-Guardian','Paladin-Holy','Paladin-Retribution','Monk-Windwalker','Warrior-Fury','Shaman-Enhancement','Paladin-Protection','Unknown-Unknown','DemonHunter-Devourer','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Demonology','Priest-Discipline','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','DemonHunter-Vengeance','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abracadava:BAAALgAECgQJBAAAAA==.',
Ac='Acheniris:BAAALgAECgUJCgAAAA==.',
Ad='Adeaino:BAAALgAECgUJCAAAAA==.Adonix:BAAALgAECgEJAQAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgUJBwAAAA==.',
Ag='Agrippa:BAACLgAFFH8GAAIBAAMJyQF0BwCxAAABAAMJyQF0BwCxAAAuAAQKfxsAAgEABwmRD44JAKMBAAEABwmRD44JAKMBAAAA.',
Ah='Ahndhrez:BAAALgAECgQJAwAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECgUJCgAAAA==.Aioli:BAABLgAECn8kAAQCAAkJ1BtRDgApAgACAAkJuRhRDgApAgADAAYJ7hdaRwCUAQAEAAUJcRo4SAAzAQAAAA==.Airwavez:BAAALgAECgcJDQAAAA==.',
Al='Alchemorph:BAABLgAECn8VAAIFAAcJIgjzPgDhAAAFAAcJIgjzPgDhAAAAAA==.Aldormu:BAABLgAECn8aAAIGAAgJtgxECwBCAQAGAAgJtgxECwBCAQAAAA==.Aliyah:BAEALgADCgIJAgABLgAECgkJJgAHAMoZAA==.Allura:BAACLgAFFH8OAAIHAAQJzREXEwAAAQAHAAQJzREXEwAAAQAuAAQKfyQAAgcACQmLGQ4WACwCAAcACQmLGQ4WACwCAAAA.Altra:BAACLgAFFH8OAAIIAAQJDguFCQAZAQAIAAQJDguFCQAZAQAuAAQKfygAAwgACAkUH1YCAJ8CAAgACAkUH1YCAJ8CAAkABwl7A1orAOQAAAAA.Alyvia:BAAALgADCgEJAgAAAA==.',
Am='Amoeta:BAABLgAECn8zAAQKAAgJ6hYpCwDVAQAKAAgJ0hUpCwDVAQALAAcJyQiAXQD9AAAMAAcJEQ/8IQD6AAAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgMJAwAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgADCggJDAAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angryapples:BAAALgAECgQJCQAAAA==.Antinous:BAABLgAECn8mAAIEAAYJeQ8UFgDjAAAEAAYJeQ8UFgDjAAAAAA==.',
Ar='Arcstorm:BAAALgAECgYJDAAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Ashenback:BAAALgAECgYJCQABLgAFFAUJDQANAGEUAA==.Asomyrh:BAABLgAECn8lAAMNAAkJmxW5FABCAgANAAkJmxW5FABCAgAOAAEJPQEehwEUAAAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgYJBwAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgADCgYJCAAAAA==.',
Av='Aviendha:BAAALgAECgEJAQAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAIPAAgJLQptKgCKAQAPAAgJLQptKgCKAQAAAA==.',
Az='Azenith:BAAALgAECgYJEQAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bamboozle:BAAALgADCgEJAQAAAA==.Bananer:BAABLgAECn8iAAIQAAkJeBRoGwDuAQAQAAkJeBRoGwDuAQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Be='Beaugersugar:BAAALgAECgQJBQAAAA==.Beebler:BAABLgAECn8UAAIRAAgJ3RVjDAC1AQARAAgJ3RVjDAC1AQAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgAECgcJCAAAAA==.Bestt:BAAALgAECgQJBwAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigholylady:BAAALgADCgkJCQAAAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigolchungus:BAABLgAECn8eAAMSAAkJwRpuCQA7AgASAAgJeBluCQA7AgAOAAUJ6BgvmgAgAQAAAA==.Bigpapadots:BAAALgAECgEJAQAAAA==.Bigshizz:BAAALgAECgQJBAABLgAECgcJDwATAAAAAA==.Bippysmasher:BAABLgAECn8kAAIUAAkJaxIoOgC9AQAUAAkJaxIoOgC9AQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.',
Bl='Blacblood:BAABLgAECn8fAAIIAAkJYRGtCgCMAQAIAAkJYRGtCgCMAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJDwAAAA==.Blindweiss:BAAALgAFFAEJAQABLgAFFAUJEgAVAO8bAA==.Blinkies:BAABLgAECn8hAAMWAAgJxh8gAQCMAgAWAAgJxh8gAQCMAgAVAAUJlg9logAdAQAAAA==.Blinkster:BAAALgAECgEJBAAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgAECgMJAwATAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8OAAIDAAYJOh2uCQCrAQADAAYJOh2uCQCrAQAuAAQKfysAAgMACQmNI5oFABoDAAMACQmNI5oFABoDAAAA.Borstenne:BAACLgAFFH8NAAIXAAQJtxytMgBeAQAXAAQJtxytMgBeAQAuAAQKfygAAhcACAnnJIMTAAYDABcACAnnJIMTAAYDAAAA.',
Br='Brake:BAACLgAFFH8KAAIXAAMJnxGoeQDeAAAXAAMJnxGoeQDeAAAuAAQKfyYAAhcACAlXHvU1AF8CABcACAlXHvU1AF8CAAAA.Brese:BAAALgAECgIJAgABLgAFFAQJDgAUAIUYAQ==.Breseayaya:BAACLgAFFH8OAAIUAAQJhRjtKABDAQAUAAQJhRjtKABDAQAuAAQKfywAAhQACAmpIdwLACIDABQACAmpIdwLACIDAAAA.Breseshh:BAAALgAECgcJEwABLgAFFAQJDgAUAIUYAA==.Brickbeard:BAABLgAECn8sAAMYAAgJ8RN6BwDDAQAYAAgJ8RN6BwDDAQAZAAcJww3lGQB9AQAAAA==.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJEgABLgAFFAYJFQAOAAkhAA==.Bricksquad:BAAALgAECgMJAwABLgAFFAMJAwATAAAAAA==.Brickthrow:BAACLgAFFH8VAAMOAAYJCSFbGABxAQAOAAUJoiBbGABxAQANAAIJ7gdiLwCDAAAuAAQKfzMAAw4ACQmsJL8EAD8DAA4ACQmsJL8EAD8DAA0ABQlyBGhkAG8AAAAA.',
Bu='Burgerburn:BAAALgAECgUJBQAAAA==.',
By='Bytheway:BAABLgAECn8UAAIaAAcJ4RPPLgA8AQAaAAcJ4RPPLgA8AQAAAA==.',
['Bà']='Bàbÿ:BAAALgAECgcJDQAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAACLgAFFH8OAAILAAQJGBK+IQAbAQALAAQJGBK+IQAbAQAuAAQKfy4ABAsACAlqJBANANUCAAsACAlqJBANANUCAAUAAQlbG3toAE8AAAwAAQlKAac3ABkAAAAA.Cadsune:BAAALgAECgYJBwAAAA==.Caelesti:BAABLgAECn8cAAMHAAgJQRCMKwBIAQAHAAYJthKMKwBIAQAaAAYJkRG4MwAiAQAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAQAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQAAAA==.Chelbur:BAAALgADCgEJAQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chowderhead:BAABLgAECn8UAAIZAAYJYxzhDgDcAQAZAAYJYxzhDgDcAQAAAA==.',
Ci='Cileb:BAACLgAFFH8GAAIVAAUJSBhAQwA/AQAVAAUJSBhAQwA/AQAuAAQKfywAAhUACQmYJBsOAFUDABUACQmYJBsOAFUDAAAA.Civik:BAABLgAECn9BAAIDAAkJPiM1CwDYAgADAAkJPiM1CwDYAgAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAFFAMJAwATAAAAAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAACLgAFFH8LAAIOAAQJ6wcDQAAGAQAOAAQJ6wcDQAAGAQAuAAQKfzAAAg4ACQldGvItACcCAA4ACQldGvItACcCAAAA.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAECgcJEQATAAAAAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJJwAJAAkjAA==.Copperit:BAABLgAECn8nAAIJAAkJCSOQAgBDAwAJAAkJCSOQAgBDAwAAAA==.Cornburglar:BAACLgAFFH8GAAIQAAMJMRs7IQD+AAAQAAMJMRs7IQD+AAAuAAQKfzUAAhAACAlcJbwHAMYCABAACAlcJbwHAMYCAAAA.Cowtaclysmic:BAABLgAECn8aAAIXAAgJPAnueQBJAQAXAAgJPAnueQBJAQAAAA==.',
Cr='Crackersz:BAABLgAECn8WAAMbAAcJHQj6cgDJAAAbAAcJHQj6cgDJAAAcAAMJGAQZcABhAAAAAA==.Cranjis:BAABLgAECn8yAAIdAAkJgCFCBgASAwAdAAkJgCFCBgASAwAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Crunchwrap:BAABLgAECn8kAAIFAAgJtA14KABcAQAFAAgJtA14KABcAQAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgcJBwAAAA==.',
Cu='Cursereflect:BAABLgAECn8eAAIeAAkJyQ6pQwC5AQAeAAkJyQ6pQwC5AQAAAA==.Curseus:BAAALgADCgUJBgAAAA==.',
Cy='Cyberwin:BAAALgAECgEJAQAAAA==.',
Da='Damncats:BAABLgAECn8sAAIQAAgJVQ6RLgBvAQAQAAgJVQ6RLgBvAQAAAA==.Dandinn:BAAALgAECgMJBAAAAA==.Danielsboone:BAABLgAECn8UAAIDAAYJmA6lfQAVAQADAAYJmA6lfQAVAQAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJCAABLgAFFAQJCAAcAJYKAA==.Darknemesis:BAAALgADCggJDgAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAECgEJAQABLgAFFAUJKgAZANciAA==.',
De='Deadhippocow:BAAALgAECgYJEgAAAA==.Deathwavez:BAACLgAFFH8OAAIXAAQJvBLGRAA9AQAXAAQJvBLGRAA9AQAuAAQKfxoAAhcABwkwFwFlAMUBABcABwkwFwFlAMUBAAAA.Decurse:BAABLgAECn8eAAIeAAgJThVESACrAQAeAAgJThVESACrAQAAAA==.Deldrin:BAABLgAECn8aAAIVAAgJYw+mbgCAAQAVAAgJYw+mbgCAAQAAAA==.Demayy:BAABLgAECn8eAAIdAAkJSQ9jJAC1AQAdAAkJSQ9jJAC1AQAAAA==.Demona:BAACLgAFFH8HAAMeAAMJiwoHZQDNAAAeAAMJiwoHZQDNAAAYAAEJkgcZHQBBAAAuAAQKfyUAAx4ACAkxGU1mAFoBAB4ABwnIFU1mAFoBABkABAngE+4pABoBAAAA.Demonix:BAABLgAECn8WAAIeAAgJLhoWMAAAAgAeAAgJLhoWMAAAAgAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAABLgAECn8uAAIVAAgJUg/UYQCeAQAVAAgJUg/UYQCeAQAAAA==.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAABLgAECn8cAAMOAAYJZxyKZgCCAQAOAAYJZxyKZgCCAQANAAIJsAT3cgBGAAAAAA==.Dinobrass:BAABLgAECn8jAAIEAAgJtA0PDgBTAQAEAAgJtA0PDgBTAQAAAA==.Dirtylöbster:BAACLgAFFH8OAAIVAAMJTCHYJwAUAQAVAAMJTCHYJwAUAQAuAAQKfzUAAhUACQkKJTAGAD8DABUACQkKJTAGAD8DAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgYJDwABLgAECgYJHAAOAGccAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAAALgAECgYJEgAAAA==.Dorose:BAAALgAECgEJAgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Dreats:BAAALgAECgUJBgAAAA==.Drewmee:BAABLgAECn8XAAIOAAkJEQltdABlAQAOAAkJEQltdABlAQAAAA==.Dronar:BAABLgAFFH8FAAIbAAUJCgk8HQA+AQAbAAUJCgk8HQA+AQABLgAECgkJGgAMAMcdAA==.Drublood:BAAALgAECgYJBgABLgAECgkJFwAOABEJAA==.Drunkinmasta:BAAALgAECgEJAQABLgAFFAQJDgAOAFoQAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Dune:BAAALgADCgcJBwAAAA==.Duwork:BAAALgAECgcJDwAAAA==.',
['Dæ']='Dæmona:BAAALgAECggJAQAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
Ei='Eight:BAAALgADCggJDQAAAA==.',
El='Eladus:BAAALgAECgYJDwAAAA==.Elemnt:BAAALgAECgYJDQABLgAFFAQJDgAOAFoQAA==.Elesus:BAAALgAECggJCAABLgAECgkJQwAfAJUhAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJDgAAAA==.Emrys:BAAALgAECgEJAQAAAA==.',
En='Enhshaman:BAABLgAECn8WAAIdAAkJ/hQ9HAD2AQAdAAkJ/hQ9HAD2AQAAAA==.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.Evilinne:BAAALgADCgEJAQAAAA==.Evânescence:BAAALgAECgEJAQAAAA==.',
Ez='Ezkal:BAACLgAFFH8RAAIXAAUJQBv9QgA/AQAXAAUJQBv9QgA/AQAuAAQKfywAAxcACQnsGaEYAOgCABcACQnsGaEYAOgCAAkABgktFVEjAAkBAAAA.',
Fa='Faithastray:BAAALgAECgMJAwAAAA==.Faithpasse:BAABLgAECn8iAAMdAAgJMBR7HwDbAQAdAAgJMBR7HwDbAQAPAAEJ9gPfhgApAAAAAA==.Falcorne:BAABLgAECn8nAAIDAAcJeyEjIwAsAgADAAcJeyEjIwAsAgAAAA==.Fatlipz:BAAALgAECgcJCgAAAA==.Fay:BAAALgADCgEJAQABLgAECgYJBwATAAAAAA==.',
Fe='Felondar:BAABLgAECn8hAAMgAAkJ2gojGwBqAQAgAAkJ2gojGwBqAQAUAAYJsASzmwDhAAAAAA==.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8ZAAMJAAkJhBsxDABOAgAJAAcJsBsxDABOAgAXAAgJvhiIagC3AQAAAA==.',
Fi='Finnadin:BAABLgAECn8YAAIOAAcJbx6YPADyAQAOAAcJbx6YPADyAQAAAA==.Finns:BAAALgAECgcJDQAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAABLgAECn8bAAIDAAgJ0xkYKgALAgADAAgJ0xkYKgALAgAAAA==.Fistobeef:BAAALgAECgEJAQAAAA==.',
Fl='Fleable:BAAALgAECgEJAQAAAA==.Flysky:BAACLgAFFH8YAAIhAAYJHRsACADuAQAhAAYJHRsACADuAQAuAAQKfywABCEACQnFI4kCAEcDACEACQnFI4kCAEcDACIACAnIJLMFAOwCAAYAAQl3DyBBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECggJDQAAAA==.',
Fr='Freakmeout:BAAALgADCgkJFQAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgAECgEJAQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJDgABLgAFFAUJEQAXAEAbAA==.Futuredragoo:BAAALgAECgcJDAABLgAFFAUJEQAXAEAbAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Ga='Gabriella:BAAALgAECgIJBAAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQATAAAAAA==.Galnannix:BAAALgAECgcJDAAAAA==.Gardrake:BAABLgAECn8jAAMiAAkJgxdeFQAPAgAiAAkJgxdeFQAPAgAhAAcJUQ+rHQCWAQAAAA==.Gastapha:BAABLgAECn8WAAIUAAgJWwY9hwDoAAAUAAgJWwY9hwDoAAAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMQAAgJCxMcMADvAQAQAAgJCxMcMADvAQAjAAEJAAAQcAAAAAAAAA==.Gehennas:BAAALgAFFAMJAwAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Go='Goofykirby:BAAALgADCgcJFQAAAA==.Googoo:BAABLgAECn8UAAIXAAkJrhMfLgAjAgAXAAkJrhMfLgAjAgAAAA==.Googoogagaa:BAACLgAFFH8MAAIaAAQJkhAMFAArAQAaAAQJkhAMFAArAQAuAAQKf0YAAxoACQkKHiIKAIsCABoACQkKHiIKAIsCAAcABwnyEgMqAKIBAAAA.Gotlieb:BAAALgAECgYJBwAAAA==.',
Gr='Grenno:BAAALgAECgYJBgABLgAFFAYJGAAXAIYkAA==.Greystorm:BAAALgAECgIJAgAAAA==.Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQATAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8bAAMEAAgJNRL1BgC0AQAEAAcJXRT1BgC0AQACAAUJnwwRDwA5AQAuAAQKfxQAAgQABwkJJOIRAKoCAAQABwkJJOIRAKoCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hamatza:BAAALgAECgEJAgAAAA==.Hammerinfred:BAAALgAECgQJBAAAAA==.',
He='Healingisfun:BAAALgAECgMJBAAAAA==.Helhunter:BAABLgAECn8oAAIUAAkJ4hFAQACnAQAUAAkJ4hFAQACnAQAAAA==.Hellock:BAAALgAFFAEJAQAAAA==.',
Hi='Hippysmasher:BAAALgAECgIJAgAAAA==.',
Ho='Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgMJBQAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holybob:BAAALgAECgQJBAAAAA==.Holyhooters:BAABLgAECn85AAIOAAkJ2yEUCgD9AgAOAAkJ2yEUCgD9AgAAAA==.Holypablo:BAAALgAECgQJBgABLgAECgkJRQAfAD8fAA==.Homefries:BAAALgADCgYJBgABLgAECgYJEgATAAAAAA==.Honkytonk:BAABLgAECn8aAAMGAAgJKQtAIgAYAQAGAAYJ7QlAIgAYAQAiAAcJeAmsOAATAQAAAA==.Honour:BAABLgAECn85AAIOAAkJNSLwDADjAgAOAAkJNSLwDADjAgAAAA==.',
Hr='Hrathdemon:BAACLgAFFH8NAAIUAAQJtBQyMAAqAQAUAAQJtBQyMAAqAQAuAAQKfyoAAhQACAmMIv8UAH4CABQACAmMIv8UAH4CAAAA.Hrathid:BAAALgADCgUJDAABLgAFFAQJDQAUALQUAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8KAAIOAAMJiiBUEgATAQAOAAMJiiBUEgATAQAuAAQKfywAAg4ACQnqI7oFAHIDAA4ACQnqI7oFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAABLgAECn8WAAIOAAkJwRufIwBWAgAOAAkJwRufIwBWAgAAAA==.',
Ib='Ibleedorange:BAAALgAECgcJDAAAAA==.',
Ic='Ickeetard:BAABLgAECn8ZAAMfAAgJIxF7JwBlAQAfAAcJFA97JwBlAQAHAAUJrg/TQwCyAAAAAA==.',
Id='Idiot:BAAALgAECgMJBAAAAA==.Idiotbreath:BAABLgAECn82AAMiAAkJFSAPBwDSAgAiAAkJFSAPBwDSAgAGAAMJmQmDMACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgAECgEJAgAAAA==.',
Ig='Iglooshocker:BAECLgAFFH8FAAIcAAMJfAbVEQDXAAAcAAMJfAbVEQDXAAAuAAQKfxYAAxwACAkqGQUXAGACABwACAkqGQUXAGACABsAAQkBDCm2ACoAAAAA.',
Im='Immorlich:BAAALgADCgcJBwAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJCQAAAA==.Inflexi:BAABLgAECn8pAAMDAAkJaiBdCAD2AgADAAkJmB9dCAD2AgAEAAgJyhrwGABkAgAAAA==.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAABLgAECn8YAAIPAAYJWhk0JwBQAQAPAAYJWhk0JwBQAQAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn84AAQLAAkJIB7GCwDlAgALAAkJIB7GCwDlAgAFAAgJox80FQBnAgAMAAMJ2haTKgDCAAAAAA==.',
Iv='Iver:BAAALgAECgEJAQABLgAECgcJEQATAAAAAA==.',
Ja='Jangle:BAAALgADCgYJBwAAAA==.',
Je='Jeffblades:BAAALgAECgQJBAAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJBgATAAAAAA==.',
Jj='Jjooaacchhim:BAAALgAECgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8iAAIDAAkJfBszIQA3AgADAAkJfBszIQA3AgAAAA==.',
Ka='Kadillac:BAAALgAECgUJBQAAAA==.Kaelira:BAAALgADCgIJAgAAAA==.Kairei:BAAALgAECgYJDQAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAACLgAFFH8KAAIOAAQJaxc0IgBPAQAOAAQJaxc0IgBPAQAuAAQKfxwAAw4ACQl1IkILAPECAA4ACQkUIkILAPECABIAAQlIJYE2AGkAAAAA.Katalina:BAABLgAECn8rAAMkAAgJkhCNDABhAQAkAAgJkhCNDABhAQAgAAYJpwsROAAlAQAAAA==.Kawer:BAAALgAECgQJCQAAAA==.Kawnzerker:BAAALgADCgkJCQAAAA==.',
Ke='Kelstormhoof:BAAALgADCgcJFgABLgADCggJDgATAAAAAA==.Kernel:BAAALgAECgEJAQABLgAFFAMJBgAQADEbAA==.',
Kh='Kham:BAACLgAFFH8OAAIQAAQJ4B5UDQBlAQAQAAQJ4B5UDQBlAQAuAAQKfzsAAhAACQkuJCQEAAoDABAACQkuJCQEAAoDAAAA.',
Ki='Killmaim:BAABLgAECn8ZAAIQAAgJwRllIABPAgAQAAgJwRllIABPAgAAAA==.Kitsuko:BAABLgAECn80AAMbAAkJFg8KMwC3AQAbAAkJFg8KMwC3AQAcAAkJxRAcJACZAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ko='Kokeovrdose:BAAALgAECgQJBAABLgAECgYJFAAVAAYWAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuraishin:BAAALgAFFAEJAQABLgAFFAUJEgAVAO8bAA==.',
['Kè']='Kèlton:BAAALgAECgUJCgAAAA==.',
La='Lanas:BAEALgAECgkJAwABLgAFFAMJBwAOALsQAA==.Laocoon:BAAALgAECggJCAABLgAECgkJOQAOANshAA==.Lavashiza:BAAALgAECgYJCwAAAA==.Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAAALgAECgYJEgAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAgAAAA==.Leedaddydk:BAAALgAECgQJCgAAAA==.Leroyjenkins:BAABLgAECn8XAAIlAAcJ8BvoAgBVAgAlAAcJ8BvoAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.',
Li='Lightstorm:BAAALgAECgYJEAAAAA==.Linaria:BAAALgAECgUJCAAAAA==.Linø:BAAALgAECgEJAQAAAA==.Lissara:BAABLgAECn8WAAIiAAgJCRDHKwBpAQAiAAgJCRDHKwBpAQAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAACLgAFFH8OAAImAAQJ8BkoEgBXAQAmAAQJ8BkoEgBXAQAuAAQKfyIAAiYACAm9H2MOAK8CACYACAm9H2MOAK8CAAAA.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockmogged:BAAALgAFFAEJAQAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECgkJHAADADIkAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAFFAQJDgAYAKATAA==.Luminouslexi:BAAALgAECgMJAwAAAA==.',
Ma='Macoub:BAAALgAECgcJEQAAAA==.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAABLgAECn8ZAAMZAAgJfQWIFQDWAAAZAAgJUQWIFQDWAAAeAAQJzAOp4gBsAAAAAA==.Mageslayer:BAABLgAECn8bAAMnAAgJmxMrGACxAQAnAAgJGBIrGACxAQABAAMJPRD1FACzAAAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgATAAAAAA==.Makkideez:BAABLgAECn8UAAInAAkJNxgYDAA+AgAnAAkJNxgYDAA+AgAAAA==.Makkii:BAAALgADCgEJAQABLgAECgkJFAAnADcYAA==.Malanara:BAAALgADCgEJAQABLgAECggJGgAVAGMPAA==.Manabuns:BAABLgAECn8pAAIVAAgJ2xf/TQDVAQAVAAgJ2xf/TQDVAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8kAAIOAAgJ7xVKQgAeAgAOAAgJ7xVKQgAeAgAAAA==.Markruffalo:BAAALgAECgUJCAAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn80AAIQAAkJeBqXEgA8AgAQAAkJeBqXEgA8AgAAAA==.',
Mc='Mckay:BAAALgAECggJEwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8mAAIlAAgJRBSvAwC3AQAlAAgJRBSvAwC3AQAAAA==.Megapunk:BAAALgAECgYJBwAAAA==.Mellmaan:BAAALgAFFAEJAQAAAA==.Melys:BAAALgAECgYJCwAAAA==.Mercenar:BAAALgADCgEJAQAAAA==.Meteorite:BAAALgAECgYJCQAAAA==.Meudayr:BAABLgAECn8aAAIMAAkJxx3CBgBYAgAMAAkJxx3CBgBYAgAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.Mezagog:BAAALgADCgQJBwAAAA==.',
Mi='Mikehammer:BAAALgADCgcJBwAAAA==.Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAACLgAFFH8IAAIcAAQJlgoQHgAGAQAcAAQJlgoQHgAGAQAuAAQKfx4AAhwACAltHCISAJICABwACAltHCISAJICAAAA.',
Mo='Moistblanket:BAAALgAECgUJBwAAAA==.Mojorisin:BAABLgAECn8aAAICAAkJnxqiBwB6AgACAAkJnxqiBwB6AgAAAA==.Moonchiken:BAAALgAECgEJBgAAAA==.Moozlock:BAABLgAECn8pAAIeAAkJwBGxPgDJAQAeAAkJwBGxPgDJAQAAAA==.Moscovio:BAAALgAFFAIJBAAAAA==.Mosspaws:BAABLgAECn82AAMLAAkJbiQcBQBPAwALAAkJbiQcBQBPAwAFAAQJZB/8LABAAQAAAA==.',
Mt='Mtndewyou:BAAALgAECgYJCQAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.Mutterutters:BAAALgADCgMJAwAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.',
Na='Narfiy:BAAALgADCgEJAQAAAA==.Narisanna:BAAALgAFFAEJAgAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBgAAAA==.',
Nm='Nme:BAABLgAECn8lAAMVAAkJoBC9SgDfAQAVAAkJoBC9SgDfAQAlAAYJiw9LCQBWAQAAAA==.',
No='Nocturnos:BAABLgAECn8tAAMeAAkJZR0hFQCPAgAeAAkJZR0hFQCPAgAYAAIJ9yBWIwBlAAAAAA==.Noggin:BAABLgAECn8rAAMNAAkJRyH/BAAcAwANAAkJRyH/BAAcAwAOAAgJ/BBaUgCzAQAAAA==.Nonform:BAABLgAECn89AAQFAAkJgRt4CQCYAgAFAAkJgRt4CQCYAgAKAAEJwRWkOABAAAALAAEJdAED7AAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECgcJHQAUAL4WAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQATAAAAAA==.Novamancer:BAAALgAECgEJAQAAAA==.Noxta:BAAALgAECggJEgAAAA==.',
Nu='Numonixx:BAACLgAFFH8cAAMGAAUJVg8ABQD3AAAiAAUJVg+WJAALAQAGAAQJ6gcABQD3AAAuAAQKfyoAAwYACQm3GqgJAEUCAAYACAl9G6gJAEUCACIACAlTGd4VAAoCAAAA.Nutlessfred:BAAALgADCgYJBgAAAA==.',
Ny='Nymage:BAABLgAECn9RAAIVAAkJDBuEIwBzAgAVAAkJDBuEIwBzAgAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogmund:BAAALgAECgYJCQAAAA==.',
Oh='Ohnospiders:BAABLgAECn8nAAIXAAkJbxV8NAAJAgAXAAkJbxV8NAAJAgAAAA==.Ohpig:BAAALgAECgMJAwAAAA==.',
Ok='Okaerisan:BAAALgAECggJEwAAAA==.',
Om='Omarcuthlink:BAAALgAECgEJAQABLgAECggJLAAYAPETAA==.Omgbbqq:BAAALgAECggJAgABLgAECgkJLgADANojAA==.',
On='Onilecram:BAAALgAECgIJAgAAAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECgcJCwAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Ou='Outlast:BAACLgAFFH8OAAIOAAQJWhDoMQArAQAOAAQJWhDoMQArAQAuAAQKfy4AAg4ACQm1HbQRAAQDAA4ACQm1HbQRAAQDAAAA.',
Pa='Paants:BAABLgAECn8dAAIoAAgJaw2HHgAWAQAoAAgJaw2HHgAWAQAAAA==.Pacid:BAAALgAECgEJAQAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Pakal:BAAALgADCgYJCgAAAA==.Palebull:BAAALgADCgYJCAAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8UAAIUAAYJHCQVCgAMAgAUAAYJHCQVCgAMAgAuAAQKfzMAAhQACQkEJQMDAEgDABQACQkEJQMDAEgDAAAA.Parmageddon:BAAALgAECgEJAQABLgAFFAQJCgAoABscAA==.Parmigiano:BAAALgADCgEJAQABLgAFFAQJCgAoABscAA==.Parmrageiano:BAABLgAFFH8KAAIoAAQJGxzBCQBUAQAoAAQJGxzBCQBUAQAAAA==.Parms:BAABLgAECn8ZAAQCAAgJ+xP1HwB8AQACAAgJ6xH1HwB8AQAEAAYJhQxETQAcAQADAAIJORANowCFAAABLgAFFAQJCgAoABscAA==.',
Pe='Peanought:BAABLgAECn8oAAMIAAgJfRgBBgDJAQAIAAgJsRcBBgDJAQAXAAgJuA8jbABoAQAAAA==.Peidro:BAABLgAECn8aAAIOAAcJtA3MiAA+AQAOAAcJtA3MiAA+AQAAAA==.Pentacles:BAABLgAECn8tAAIMAAkJsCAZBQCKAgAMAAkJsCAZBQCKAgAAAA==.',
Pi='Pijak:BAAALgAECgYJEgAAAA==.Pinkpaw:BAABLgAECn8fAAMMAAkJ8x5vAwDKAgAMAAkJ8x5vAwDKAgALAAUJthqqQABsAQAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8IAAMmAAMJ3iTvCABGAQAmAAMJ3iTvCABGAQAPAAEJbQtJMQBAAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCAAmAN4kAA==.Postscalone:BAAALgAECgEJAQAAAA==.Potatoes:BAABLgAECn8VAAMZAAgJBgiWHABpAQAZAAgJBgiWHABpAQAeAAIJCQJIFAE6AAAAAA==.',
Pr='Pruflas:BAABLgAECn8aAAIXAAgJZAsVdABWAQAXAAgJZAsVdABWAQAAAA==.',
Ps='Psycodk:BAABLgAECn8VAAIXAAcJyhaXigAqAQAXAAcJyhaXigAqAQAAAA==.',
Pu='Pumpin:BAABLgAECn8XAAIPAAUJFCQUIwBuAQAPAAUJFCQUIwBuAQAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
Qk='Qkn:BAAALgAECgUJEQAAAA==.',
Qu='Quickswipe:BAAALgAFFAIJAgABLgAFFAUJKgAZANciAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgYJCwABLgAECgcJCAATAAAAAA==.Ralee:BAAALgADCgIJAgAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Rastabution:BAAALgAECgkJAQAAAA==.Raynne:BAAALgAECgIJAgAAAA==.Rayzee:BAAALgADCgUJBQAAAA==.',
Re='Reaperjoe:BAAALgAFFAEJAgAAAA==.Rehab:BAABLgAECn8VAAIOAAkJWxyuLwBkAgAOAAkJWxyuLwBkAgAAAA==.Rehna:BAAALgAECgYJBgABLgAFFAQJDgAHAM0RAA==.Rektributio:BAACLgAFFH8eAAIOAAgJCyDnAADMAgAOAAgJCyDnAADMAgAuAAQKfzcAAg4ACQkgJfsDAEwDAA4ACQkgJfsDAEwDAAAA.Revalation:BAABLgAECn8jAAILAAkJxR3XFgBuAgALAAkJxR3XFgBuAgAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgATAAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Ribeyejoe:BAAALgADCgEJAQAAAA==.Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAABLgAECn8dAAMoAAgJJxM5FQB4AQAoAAgJIhM5FQB4AQAQAAUJuAwaaQAQAQAAAA==.Roadtrip:BAAALgAECgMJBAAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJBAAAAA==.Rottingslow:BAABLgAFFH8FAAIHAAMJlgBPIQB9AAAHAAMJlgBPIQB9AAAAAA==.',
Sa='Sanford:BAAALgAECgEJAQAAAA==.Saragos:BAAALgADCgcJBgABLgAFFAUJEgAVAO8bAA==.Saucerdote:BAABLgAECn8eAAMfAAkJmBVeGQDZAQAfAAcJGxdeGQDZAQAaAAkJFAlrJgBwAQAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAUJEgAVAO8bAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAABLgAECn8pAAIUAAkJeh6ZDwCrAgAUAAkJeh6ZDwCrAgAAAA==.Selkie:BAABLgAECn8dAAIRAAkJDAvVDgCJAQARAAkJDAvVDgCJAQAAAA==.Seragosa:BAAALgAFFAEJAQABLgAFFAUJEgAVAO8bAA==.',
Sh='Shakakhan:BAAALgAECgYJCgABLgAECgYJHAAOAGccAA==.Shambeau:BAAALgADCgQJBAAAAA==.Shamrun:BAAALgADCgEJAQAAAA==.Shamshielder:BAEBLgAECn8tAAQJAAkJmSPCAwDhAgAJAAkJmSPCAwDhAgAIAAYJpRsxCgCXAQAXAAEJuQlDSQEpAAABLgAFFAMJBQAcAHwGAA==.Sharick:BAAALgAECgQJBQAAAA==.Shawlee:BAABLgAECn8rAAMbAAgJzBATTgBDAQAbAAgJzBATTgBDAQAcAAgJCAj2WACpAAAAAA==.Sheezie:BAABLgAECn8uAAIbAAkJcxn1EACdAgAbAAkJcxn1EACdAgAAAA==.Shellter:BAAALgAECgEJAgABLgAECggJIQAWAMYfAA==.Shellwit:BAAALgAECgMJBgABLgAECggJIQAWAMYfAA==.Sheph:BAAALgAECgcJCQAAAA==.Shetmage:BAACLgAFFH8VAAIVAAYJag1rLAByAQAVAAYJag1rLAByAQAuAAQKfykAAhUACQnDIOsaAJ4CABUACQnDIOsaAJ4CAAAA.Shettrah:BAAALgAECgYJEQABLgAFFAYJFQAVAGoNAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAABLgAECn8bAAIOAAgJihGOaQB8AQAOAAgJihGOaQB8AQAAAA==.Shuck:BAAALgAECgQJBAABLgAFFAMJBgAQADEbAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Sibyx:BAAALgAECgUJBgABLgAECgYJHAAOAGccAA==.Siickboy:BAAALgAECgQJCQAAAA==.Sijious:BAAALgAECgEJAQAAAA==.Silveah:BAAALgADCgEJAQAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.',
Sk='Skora:BAAALgADCgIJAgABLgAECggJJAAOAO8VAA==.Skyland:BAAALgADCgcJDQAAAA==.Skyli:BAAALgAECgUJCAABLgAECgkJGAAbAGsdAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAACLgAFFH8OAAINAAQJ8xn8GAAnAQANAAQJ8xn8GAAnAQAuAAQKfyYAAg0ACAlcILwIAOMCAA0ACAlcILwIAOMCAAAA.Sorrie:BAAALgAECgEJAQAAAA==.Sortiarius:BAAALgADCgkJCQAAAA==.',
Sp='Spud:BAAALgADCgcJBwABLgAECgUJEAATAAAAAA==.Spyroh:BAABLgAECn8bAAQGAAYJ6BLuGQBlAQAGAAYJcBDuGQBlAQAiAAUJGBIlPgAKAQAhAAEJ2wA4TwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAQJDgAHAM0RAA==.',
St='Stankydk:BAACLgAFFH8OAAMXAAUJDxtxGgA8AQAXAAQJDxtxGgA8AQAJAAEJAABjTQAAAAAuAAQKfzIAAhcACQk+JVkDAFkDABcACQk+JVkDAFkDAAAA.Stankyeyes:BAAALgAECgYJBgAAAA==.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Steakhead:BAABLgAECn8dAAIFAAYJCgnlRADHAAAFAAYJCgnlRADHAAAAAA==.Stinkbombs:BAABLgAFFH8JAAIVAAQJ4AMoXgD8AAAVAAQJ4AMoXgD8AAAAAA==.Stinkerz:BAAALgAECgIJAgABLgAECggJIQAWAMYfAA==.Stunanddone:BAAALgAECgQJCAAAAA==.',
Su='Subrogue:BAAALgAFFAIJBAABLgAECgkJFgAdAP4UAA==.Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJEAAAAA==.Supreme:BAACLgAFFH8IAAIUAAMJXhrEQwDvAAAUAAMJXhrEQwDvAAAuAAQKfxkAAhQACAl4I24YAMMCABQACAl4I24YAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAMJAwABLgAFFAQJCgAnAG0cAA==.Swayaim:BAAALgAECgkJAgAAAA==.Sweatypits:BAAALgADCggJCAAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAUJDQANAGEUAA==.Sylphrena:BAACLgAFFH8OAAIHAAQJDBQbEAAeAQAHAAQJDBQbEAAeAQAuAAQKfycAAgcACAkqIIgIAMMCAAcACAkqIIgIAMMCAAAA.',
['Sí']='Sínful:BAABLgAECn8qAAIEAAkJxB9DAwB6AgAEAAkJxB9DAwB6AgAAAA==.',
Ta='Tacow:BAAALgAECgcJBwAAAA==.Tahwe:BAAALgADCgcJBwAAAA==.Talethen:BAABLgAECn8YAAMiAAgJhRjAKAB3AQAiAAgJyxbAKAB3AQAGAAUJMxgpIAAtAQAAAA==.Talla:BAABLgAECn8YAAIbAAkJax2mGgBCAgAbAAkJax2mGgBCAgAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgADCgkJIQAAAA==.Tellus:BAAALgADCgcJCwAAAA==.Tempesttempi:BAAALgADCgcJBwAAAA==.Tewshort:BAAALgAECgQJCAABLgAFFAQJDgAOAFoQAA==.',
Th='Thatbox:BAAALgAECgQJBAAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgQJDAAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAABLgAECn8UAAMPAAgJBAX1SwCpAAAmAAcJQQRZWQDeAAAPAAcJQgT1SwCpAAAAAA==.Thorfyna:BAABLgAECn8dAAIkAAgJ9hHHCwByAQAkAAgJ9hHHCwByAQAAAA==.Threzk:BAABLgAECn8eAAIZAAkJew5ACwBeAQAZAAkJew5ACwBeAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8MAAIUAAUJZBOEHQB2AQAUAAUJZBOEHQB2AQAuAAQKfy8AAhQACQmGIhMIAPkCABQACQmGIhMIAPkCAAAA.Tontiamat:BAABLgAECn8xAAMiAAkJSBgeFAAbAgAiAAkJSBgeFAAbAgAGAAYJawo5IAAsAQAAAA==.Tontier:BAABLgAECn8UAAQLAAUJFg6PZADmAAALAAUJFg6PZADmAAAKAAUJNgimJACrAAAMAAMJEQn/SwBCAAABLgAECgkJMQAiAEgYAA==.Totembeans:BAAALgAECgQJCwAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAACLgAFFH8NAAINAAUJYRRJDwCHAQANAAUJYRRJDwCHAQAuAAQKfxwABA0ACQlOH6IJAMwCAA0ACAnDHqIJAMwCAA4ABwksDjq3ABcBABIAAgmgEzVAADoAAAAA.Trashfire:BAACLgAFFH8KAAMHAAQJIA6nEAAYAQAHAAQJIA6nEAAYAQAfAAIJwgF2FgB7AAAuAAQKfx0ABAcACAkXHSYQAGUCAAcACAkXHSYQAGUCABoABQknFXw2ADkBAB8AAwluEWhAAK0AAAEuAAUUBQkNAA0AYRQA.Treeple:BAABLgAECn8dAAMLAAgJLBNoRQBXAQALAAcJGRNoRQBXAQAFAAQJtQvtSAC2AAAAAA==.Treily:BAAALgAECgYJDwAAAA==.Tresleches:BAABLgAECn8gAAIOAAgJuw+JdABlAQAOAAgJuw+JdABlAQAAAA==.Tricket:BAABLgAECn9DAAMjAAkJqB1qBACsAgAjAAkJYx1qBACsAgAQAAYJKBnpRgAAAQAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAZAAYIAQ==.Truestorm:BAABLgAECn8oAAIOAAkJzgtGXwCTAQAOAAkJzgtGXwCTAQAAAA==.Truheals:BAAALgADCgkJEwAAAA==.',
Tu='Tuchi:BAACLgAFFH8VAAIVAAUJkByVHgBQAQAVAAUJkByVHgBQAQAuAAQKfyYAAyUABwm9I5QCAAYCABUABwliIrkyAKgCACUABgnQIpQCAAYCAAAA.Tumblestone:BAAALgAECgEJAQAAAA==.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAYJFAAUABwkAA==.',
['Tà']='Tàcobelle:BAAALgADCgYJBwABLgAECggJKQAVANsXAA==.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgATAAAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIbAAMJriLeJwAKAQAbAAMJriLeJwAKAQAuAAQKfzEAAxsACQllGz8SAIQCABsACQllGz8SAIQCABwABgkTGrEsAGUBAAAA.Varanis:BAACLgAFFH8IAAIDAAMJnxZuDAD/AAADAAMJnxZuDAD/AAAuAAQKfxcAAgMACAkLImMLAOgCAAMACAkLImMLAOgCAAAA.',
Ve='Vegh:BAABLgAECn9HAAIkAAkJ8x9lAgC2AgAkAAkJ8x9lAgC2AgAAAA==.Vem:BAABLgAECn8lAAIiAAkJnB0mEAB1AgAiAAkJnB0mEAB1AgAAAA==.Veriale:BAAALgAECgUJCgAAAA==.Verra:BAABLgAECn8zAAIOAAgJzRvILAAsAgAOAAgJzRvILAAsAgAAAA==.',
Vi='Vitriol:BAABLgAECn8gAAIQAAcJZxh1KACTAQAQAAcJZxh1KACTAQAAAA==.',
Vo='Voidbeaver:BAAALgAECgcJCwAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAACLgAFFH8OAAMYAAQJoBPYAgA/AQAYAAQJoBPYAgA/AQAZAAEJYQeLIABBAAAuAAQKfx8AAhgACQl1IqsBAMoCABgACQl1IqsBAMoCAAAA.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgYJDwATAAAAAA==.Vyrros:BAAALgADCgUJBQAAAA==.',
Wa='Walji:BAABLgAECn8eAAMbAAgJyhtyFwBaAgAbAAgJyhtyFwBaAgAcAAEJWwtijgAqAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgAECgIJAgAAAA==.Wandy:BAABLgAECn8rAAIeAAgJHxWsQgC8AQAeAAgJHxWsQgC8AQAAAA==.Wangstah:BAABLgAECn8cAAIDAAkJMiQVCQDvAgADAAkJMiQVCQDvAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAIQAAYJNhQUSgB8AQAQAAYJNhQUSgB8AQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJDgAAAA==.Wawatesi:BAAALgAECgMJAwAAAA==.Waytogoteam:BAABLgAECn8uAAIDAAkJ2iMkCAD5AgADAAkJ2iMkCAD5AgAAAA==.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8SAAMVAAUJ7xt4NQBYAQAVAAUJ7xt4NQBYAQAWAAIJBw6OAgCRAAAuAAQKfzMABBUACQnEJBkJAB4DABUACQk3JBkJAB4DABYABgm+I3wDANkBACUAAQmPIMgWAGQAAAAA.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgEJAQAAAA==.',
Wo='Woodyy:BAABLgAECn8XAAIXAAgJNgbfiQArAQAXAAgJNgbfiQArAQAAAA==.Woog:BAAALgAECgYJCQAAAA==.Wox:BAAALgAECgcJCwAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wu='Wujustyle:BAAALgAECgcJBwAAAA==.Wulfgar:BAAALgAECgcJCAAAAA==.',
Wy='Wyldspirit:BAABLgAECn8UAAIDAAYJ6wlHiQD7AAADAAYJ6wlHiQD7AAAAAA==.Wyreless:BAAALgADCgYJBgABLgAECggJMwAKAOoWAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgADCgEJAQAAAA==.',
Xr='Xrind:BAAALgADCgEJAQAAAA==.',
Ya='Yaass:BAAALgAECgMJAwAAAA==.',
Ye='Yem:BAACLgAFFH8qAAQZAAUJ1yLDAgBkAQAZAAUJWh3DAgBkAQAeAAQJ/h/PLQBPAQAYAAIJYSL1EABXAAAuAAQKfzYAAxkACQmiIzkGAGwCABkABgncIzkGAGwCAB4ABgliI1VJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAIMAAcJvxm2CAAfAgAMAAcJvxm2CAAfAgABLgAFFAQJCgAOAGsXAA==.Yoverre:BAAALgAECgMJAwAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAATAAAAAA==.Zanzabar:BAABLgAECn8XAAIOAAkJvBm7LwAgAgAOAAkJvBm7LwAgAgAAAA==.Zaraelitha:BAAALgAECgYJBwAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgIJAwAAAA==.Zeodrik:BAABLgAECn8cAAIQAAcJYRmxNQDSAQAQAAcJYRmxNQDSAQAAAA==.',
Zh='Zhenya:BAACLgAFFH8OAAIVAAQJ+hILRgA7AQAVAAQJ+hILRgA7AQAuAAQKfyYAAxUACAnXGllQAM4BABUACAnXGllQAM4BACUABAkvD+gOANUAAAAA.',
Zi='Zidguard:BAAALgAECgYJBwAAAA==.Zigzauer:BAAALgAECgQJBAAAAA==.Ziroken:BAAALgADCgUJBQAAAA==.',
Zo='Zombeaver:BAAALgADCgcJCgAAAA==.',
Zu='Zuga:BAAALgAECggJCAAAAA==.',
['Ña']='Ñajana:BAAALgADCgcJCAAAAA==.',
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
