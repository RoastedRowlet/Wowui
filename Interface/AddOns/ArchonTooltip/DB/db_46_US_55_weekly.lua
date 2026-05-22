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

local lookup = {'Rogue-Assassination','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Devastation','Priest-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Paladin-Holy','Monk-Windwalker','Warrior-Fury','Paladin-Protection','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Druid-Restoration','Monk-Mistweaver','Druid-Balance','Warlock-Demonology','Shaman-Elemental','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Priest-Discipline','DemonHunter-Vengeance','Shaman-Restoration','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection','Shaman-Enhancement',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abracadava:BAAALgAECgQJBAAAAA==.',
Ac='Acheniris:BAAALgAECgUJCgAAAA==.',
Ad='Adeaino:BAAALgAECgUJCAAAAA==.Adonix:BAAALgAECgEJAQAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgUJBwAAAA==.',
Ag='Agrippa:BAABLgAECn8bAAIBAAcJkQ+OCQCjAQABAAcJkQ+OCQCjAQAAAA==.',
Ah='Ahndhrez:BAAALgAECgQJAwAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECgUJCgAAAA==.Aioli:BAABLgAECn8kAAQCAAkJ1BvrCgAxAgACAAkJuRjrCgAxAgADAAYJ7hdaRwCUAQAEAAUJcRo4SAAzAQAAAA==.Airwavez:BAAALgAECgcJCgAAAA==.',
Al='Alchemorph:BAAALgAECgYJDgAAAA==.Aldormu:BAABLgAECn8VAAIFAAcJkgrkDAD7AAAFAAcJkgrkDAD7AAAAAA==.Aliyah:BAEALgADCgIJAgABLgAECgkJJgAGAMsZAA==.Allura:BAACLgAFFH8KAAIGAAMJ0BUPFQDEAAAGAAMJ0BUPFQDEAAAuAAQKfyMAAgYACQmLGQ4WACwCAAYACQmLGQ4WACwCAAAA.Altra:BAACLgAFFH8KAAIHAAMJKwpsCQDUAAAHAAMJKwpsCQDUAAAuAAQKfygAAwcACAkUH1YCAJ8CAAcACAkUH1YCAJ8CAAgABwl7A1orAOQAAAAA.Alyvia:BAAALgADCgEJAgAAAA==.',
Am='Amoeta:BAABLgAECn8qAAMJAAgJCBZWCQDRAQAJAAgJ7hRWCQDRAQAKAAcJEg8FGgD+AAAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgMJAwAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgADCggJCgAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angryapples:BAAALgAECgQJCQAAAA==.Antinous:BAABLgAECn8mAAIEAAYJeQ9LEwDmAAAEAAYJeQ9LEwDmAAAAAA==.',
Ar='Arcstorm:BAAALgAECgYJCgAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Ashenback:BAAALgAECgYJBgABLgAFFAUJDQALAGEUAA==.Asomyrh:BAABLgAECn8cAAILAAkJphBcOwCMAQALAAkJphBcOwCMAQAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgUJBgAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgADCgEJAQAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAIMAAgJLQptKgCKAQAMAAgJLQptKgCKAQAAAA==.',
Az='Azenith:BAAALgAECgYJEAAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bananer:BAABLgAECn8iAAINAAkJeRTqFAD9AQANAAkJeRTqFAD9AQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Be='Beaugersugar:BAAALgAECgEJAQAAAA==.Beebler:BAAALgAECgcJEwAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgAECgcJCAAAAA==.Bestt:BAAALgAECgQJBwAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigolchungus:BAABLgAECn8dAAMOAAgJhBluCQA7AgAOAAgJeBluCQA7AgAPAAQJRhY6vwC4AAAAAA==.Bigpapadots:BAAALgADCgYJBgAAAA==.Bigshizz:BAAALgAECgQJAwABLgAECgcJDwAQAAAAAA==.Bippysmasher:BAABLgAECn8kAAIRAAkJaxI4MwCuAQARAAkJaxI4MwCuAQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.',
Bl='Blacblood:BAABLgAECn8fAAIHAAkJYRGYBwCeAQAHAAkJYRGYBwCeAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJDgAAAA==.Bliccy:BAAALgAECgYJCwAAAA==.Blindweiss:BAAALgADCgcJBwABLgAFFAUJEQASAFIbAA==.Blinkies:BAABLgAECn8aAAMTAAgJFxyGAQAuAgATAAgJFxyGAQAuAgASAAUJlg/qkwAXAQAAAA==.Blinkster:BAAALgAECgEJBAAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgAECgMJAwAQAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8NAAIDAAUJox6JEQBjAQADAAUJox6JEQBjAQAuAAQKfysAAgMACQmNIx8DADADAAMACQmNIx8DADADAAAA.Borstenne:BAACLgAFFH8JAAIUAAMJqRspVQAFAQAUAAMJqRspVQAFAQAuAAQKfygAAhQACAnnJIMTAAYDABQACAnnJIMTAAYDAAAA.',
Br='Brake:BAACLgAFFH8KAAIUAAMJnxEyYwDuAAAUAAMJnxEyYwDuAAAuAAQKfyQAAhQACAlFHvU1AF8CABQACAlFHvU1AF8CAAAA.Brese:BAAALgAECgIJAgABLgAFFAMJCgARAAcaAQ==.Breseayaya:BAACLgAFFH8KAAIRAAMJBxpwNwD8AAARAAMJBxpwNwD8AAAuAAQKfywAAhEACAmpIdwLACIDABEACAmpIdwLACIDAAAA.Breseshh:BAAALgAECgcJEwABLgAFFAMJCgARAAcaAA==.Brickbeard:BAABLgAECn8nAAMVAAgJKxKbBwCJAQAVAAgJ+xGbBwCJAQAWAAcJog3lGQB9AQAAAA==.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJEgABLgAFFAUJEwAPAKIgAA==.Bricksquad:BAAALgAECgMJAwABLgAFFAMJAwAQAAAAAA==.Brickthrow:BAACLgAFFH8TAAMPAAUJoiCiDwCCAQAPAAUJoiCiDwCCAQALAAEJEgb3GwBNAAAuAAQKfzMAAw8ACQmtJPACAEgDAA8ACQmsJPACAEgDAAsABQlyBJRYAHUAAAAA.',
Bu='Burgerburn:BAAALgADCgYJCwAAAA==.',
By='Bytheway:BAABLgAECn8UAAIXAAcJ4hOZJwA6AQAXAAcJ4hOZJwA6AQAAAA==.',
['Bà']='Bàbÿ:BAAALgAECgUJBQAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAACLgAFFH8KAAIYAAMJCxRxJwDbAAAYAAMJCxRxJwDbAAAuAAQKfykAAxgACAlqJGEKANcCABgACAlqJGEKANcCAAoAAQlKAac3ABkAAAAA.Cadsune:BAAALgAECgEJAQAAAA==.Caelesti:BAAALgAECgUJDwAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAQAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chowderhead:BAABLgAECn8UAAIWAAYJYxzhDgDcAQAWAAYJYxzhDgDcAQAAAA==.',
Ci='Cileb:BAACLgAFFH8FAAISAAUJcxc2OABJAQASAAUJcxc2OABJAQAuAAQKfyIAAhIACQlxIxsOAFUDABIACQlxIxsOAFUDAAAA.Civik:BAABLgAECn84AAIDAAkJiSLHCQDJAgADAAkJiSLHCQDJAgAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAFFAMJAwAQAAAAAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAACLgAFFH8KAAIPAAQJ4wYzMgARAQAPAAQJ4wYzMgARAQAuAAQKfzAAAg8ACQldGukiADMCAA8ACQldGukiADMCAAAA.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAECgYJDAAQAAAAAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJJwAIAAkjAA==.Copperit:BAABLgAECn8nAAIIAAkJCSOQAgBDAwAIAAkJCSOQAgBDAwAAAA==.Cornburglar:BAACLgAFFH8FAAINAAMJuho6GwAEAQANAAMJuho6GwAEAQAuAAQKfzIAAg0ACAkNJUQGAL8CAA0ACAkNJUQGAL8CAAAA.Cowtaclysmic:BAABLgAECn8ZAAIUAAcJmQkhfwAbAQAUAAcJmQkhfwAbAQAAAA==.',
Cr='Crackersz:BAAALgAFFAIJAwAAAA==.Cranjis:BAABLgAECn8oAAIZAAkJGiEMBQAGAwAZAAkJGiEMBQAGAwAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Crunchwrap:BAABLgAECn8iAAIaAAcJhQ5zKAAwAQAaAAcJhQ5zKAAwAQAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgcJBwAAAA==.',
Cu='Cursereflect:BAABLgAECn8ZAAIbAAcJVBF2WQBSAQAbAAcJVBF2WQBSAQAAAA==.Curseus:BAAALgADCgUJBgAAAA==.',
Cy='Cyberwin:BAAALgAECgEJAQAAAA==.',
Da='Damncats:BAABLgAECn8kAAINAAgJ+QthKwBYAQANAAgJ+QthKwBYAQAAAA==.Dandinn:BAAALgAECgMJBAAAAA==.Danielsboone:BAABLgAECn8UAAIDAAYJmA4KaAAXAQADAAYJmA4KaAAXAQAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJCAABLgAECggJHgAcAGYcAA==.Darknemesis:BAAALgADCggJDgAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAECgEJAQABLgAFFAUJJAAWANciAA==.',
De='Deadhippocow:BAAALgAECgUJDQAAAA==.Deathwavez:BAACLgAFFH8JAAIUAAMJkwu/bADbAAAUAAMJkwu/bADbAAAuAAQKfxoAAhQABwkwFwFlAMUBABQABwkwFwFlAMUBAAAA.Decurse:BAABLgAECn8ZAAIbAAcJgRUBVQBeAQAbAAcJgRUBVQBeAQAAAA==.Deldrin:BAABLgAECn8YAAISAAgJYw9wYgB5AQASAAgJYw9wYgB5AQAAAA==.Demayy:BAABLgAECn8dAAIZAAkJSQ+iHAC3AQAZAAkJSQ+iHAC3AQAAAA==.Demona:BAACLgAFFH8HAAMbAAMJiwq7VQDSAAAbAAMJiwq7VQDSAAAVAAEJkgdjFABDAAAuAAQKfyUAAxsACAkxGcRUAF8BABsABwnIFcRUAF8BABYABAngE+4pABoBAAAA.Demonix:BAABLgAECn8VAAIbAAgJhBj4KwDrAQAbAAgJhBj4KwDrAQAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAABLgAECn8oAAISAAcJXw3meABJAQASAAcJXw3meABJAQAAAA==.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAABLgAECn8bAAMPAAYJZxzGTgCSAQAPAAYJZxzGTgCSAQALAAIJsASyZwBGAAAAAA==.Dinobrass:BAABLgAECn8dAAIEAAcJEQ40DwAeAQAEAAcJEQ40DwAeAQAAAA==.Dirtylöbster:BAACLgAFFH8NAAISAAMJTCHYJwAUAQASAAMJTCHYJwAUAQAuAAQKfzUAAhIACQkKJSAEAEsDABIACQkKJSAEAEsDAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgYJDwABLgAECgYJGwAPAGccAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAAALgAECgYJEgAAAA==.Dorose:BAAALgAECgEJAgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Drewmee:BAABLgAECn8WAAIPAAgJUQl5egAuAQAPAAgJUQl5egAuAQAAAA==.Dronar:BAAALgADCgEJAQABLgAECgkJEQAQAAAAAA==.Drublood:BAAALgAECgYJBgABLgAECggJFgAPAFEJAA==.Drunkinmasta:BAAALgAECgEJAQABLgAFFAMJCgAPAPMQAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Dune:BAAALgADCgcJBwAAAA==.Duwork:BAAALgAECgcJDwAAAA==.',
['Dæ']='Dæmona:BAAALgAECggJAQAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
El='Eladus:BAAALgAECgYJCQAAAA==.Elemnt:BAAALgAECgUJCAABLgAFFAMJCgAPAPMQAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJCwAAAA==.',
En='Enhshaman:BAAALgAFFAMJBAAAAA==.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.Evilinne:BAAALgADCgEJAQAAAA==.',
Ez='Ezkal:BAACLgAFFH8QAAIUAAUJQBvqMABRAQAUAAUJQBvqMABRAQAuAAQKfywAAxQACQnsGaEYAOgCABQACQnsGaEYAOgCAAgABgktFSwdABcBAAAA.',
Fa='Faithastray:BAAALgAECgMJAwAAAA==.Faithpasse:BAABLgAECn8bAAMZAAYJQxXAJgBmAQAZAAYJQxXAJgBmAQAMAAEJ9gPfhgApAAAAAA==.Falcorne:BAABLgAECn8hAAIDAAcJZh7XNQCzAQADAAcJZh7XNQCzAQAAAA==.Fatlipz:BAAALgAECgcJBAAAAA==.',
Fe='Felondar:BAABLgAECn8gAAMdAAkJ2QrUFQB0AQAdAAkJ2QrUFQB0AQARAAYJsASzmwDhAAAAAA==.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8ZAAMIAAkJhBsxDABOAgAIAAcJsBsxDABOAgAUAAgJvhiIagC3AQAAAA==.',
Fi='Finnadin:BAABLgAECn8YAAIPAAcJbx4cLQAEAgAPAAcJbx4cLQAEAgAAAA==.Finns:BAAALgAECgcJDQAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAABLgAECn8bAAIDAAgJ0xmbHgAgAgADAAgJ0xmbHgAgAgAAAA==.Fistobeef:BAAALgAECgEJAQAAAA==.',
Fl='Fleable:BAAALgAECgEJAQAAAA==.Flysky:BAACLgAFFH8XAAIeAAUJ+RlwCgCRAQAeAAUJ+RlwCgCRAQAuAAQKfywABB4ACQnFI4kCAEcDAB4ACQnFI4kCAEcDAB8ACAnIJIYEAOsCAAUAAQl3DyBBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECggJDQAAAA==.',
Fr='Freakmeout:BAAALgADCgkJFQAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgAECgEJAQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJDgABLgAFFAUJEAAUAEAbAA==.Futuredragoo:BAAALgAECgQJBgABLgAFFAUJEAAUAEAbAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Ga='Gabriella:BAAALgAECgEJAwAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQAQAAAAAA==.Galnannix:BAAALgAECgcJDAAAAA==.Gardrake:BAABLgAECn8jAAMfAAkJdRckEQARAgAfAAkJdRckEQARAgAeAAcJUQ+rHQCWAQAAAA==.Gastapha:BAABLgAECn8UAAIRAAcJuAZjigC2AAARAAcJuAZjigC2AAAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMNAAgJCxMcMADvAQANAAgJCxMcMADvAQAgAAEJAADsXQAAAAAAAA==.Gehennas:BAAALgAFFAMJAwAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Go='Goofykirby:BAAALgADCgcJFQAAAA==.Googoo:BAAALgAFFAIJAgAAAA==.Googoogagaa:BAACLgAFFH8MAAIXAAQJkhDmDwA6AQAXAAQJkhDmDwA6AQAuAAQKf0YAAxcACQkJHikHAJsCABcACQkJHikHAJsCAAYABwnyEgMqAKIBAAAA.Gotlieb:BAAALgAECgYJBwAAAA==.',
Gr='Grenno:BAAALgAECgYJBgAAAA==.Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQAQAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8XAAMEAAcJCRRYBwCnAQAEAAcJCRRYBwCnAQACAAMJTgzGGwCeAAAuAAQKfxQAAgQABwkJJOIRAKoCAAQABwkJJOIRAKoCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hamatza:BAAALgAECgEJAgAAAA==.Hammerinfred:BAAALgAECgQJBAAAAA==.',
He='Healingisfun:BAAALgAECgMJBAAAAA==.Helhunter:BAABLgAECn8nAAIRAAkJZhFcOwCNAQARAAkJZhFcOwCNAQAAAA==.Hellock:BAAALgAFFAEJAQAAAA==.',
Hi='Hippysmasher:BAAALgAECgIJAgAAAA==.',
Ho='Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgMJBQAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holyhooters:BAABLgAECn8wAAIPAAkJtCBnCAD0AgAPAAkJtCBnCAD0AgAAAA==.Holypablo:BAAALgAECgIJAgABLgAECgkJPAAhAD8fAA==.Homefries:BAAALgADCgYJBgABLgAECgUJDQAQAAAAAA==.Honkytonk:BAABLgAECn8aAAMFAAgJKQtAIgAYAQAFAAYJ7QlAIgAYAQAfAAcJeAmsOAATAQAAAA==.Honour:BAABLgAECn8wAAIPAAkJziDiDwCuAgAPAAkJziDiDwCuAgAAAA==.',
Hr='Hrathdemon:BAACLgAFFH8JAAIRAAMJWxVCPADpAAARAAMJWxVCPADpAAAuAAQKfygAAhEACAmMImIQAH8CABEACAmMImIQAH8CAAAA.Hrathid:BAAALgADCgUJDAABLgAFFAMJCQARAFsVAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8KAAIPAAMJiiBUEgATAQAPAAMJiiBUEgATAQAuAAQKfywAAg8ACQnqI7oFAHIDAA8ACQnqI7oFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAABLgAECn8VAAIPAAgJHxs2LgD/AQAPAAgJHxs2LgD/AQAAAA==.',
Ib='Ibleedorange:BAAALgAECgYJCgAAAA==.',
Ic='Ickeetard:BAABLgAECn8XAAMhAAgJIhG7IABqAQAhAAcJEw+7IABqAQAGAAQJhQ9NRACFAAAAAA==.',
Id='Idiot:BAAALgAECgMJBAAAAA==.Idiotbreath:BAABLgAECn82AAMfAAkJESBoBQDWAgAfAAkJESBoBQDWAgAFAAMJmQmDMACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgAECgEJAgAAAA==.',
Ig='Iglooshocker:BAEBLgAFFH8FAAIcAAMJfAbVEQDXAAAcAAMJfAbVEQDXAAAAAA==.',
Im='Immorlich:BAAALgADCgcJBwAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJCQAAAA==.Inflexi:BAABLgAECn8aAAMEAAgJdyDwGABkAgAEAAgJyhrwGABkAgADAAUJFyJBMADJAQAAAA==.Inky:BAAALgADCggJEgAAAA==.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAABLgAECn8YAAIMAAYJWhngHwBbAQAMAAYJWhngHwBbAQAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn82AAQYAAkJZh3uCgDPAgAYAAkJZh3uCgDPAgAaAAgJoh80FQBnAgAKAAMJ2hblIADDAAAAAA==.',
Iv='Iver:BAAALgAECgEJAQABLgAECgcJEAAQAAAAAA==.',
Ja='Jangle:BAAALgADCgYJBwAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJBgAQAAAAAA==.',
Jj='Jjooaacchhim:BAAALgADCgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8iAAIDAAkJfBuGFwBOAgADAAkJfBuGFwBOAgAAAA==.',
Ka='Kaelira:BAAALgADCgIJAgAAAA==.Kairei:BAAALgAECgYJDQAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAACLgAFFH8HAAIPAAQJXgytKAAwAQAPAAQJXgytKAAwAQAuAAQKfxoAAw8ACQkbIdQKANwCAA8ACQm7INQKANwCAA4AAQlIJYE2AGkAAAAA.Katalina:BAABLgAECn8pAAMiAAgJjQ8FCwBXAQAiAAgJjQ8FCwBXAQAdAAYJpwsROAAlAQAAAA==.Kawer:BAAALgAECgQJCAAAAA==.',
Ke='Kelstormhoof:BAAALgADCgcJFgABLgADCggJDgAQAAAAAA==.Kernel:BAAALgAECgEJAQABLgAFFAMJBQANALoaAA==.',
Kh='Kham:BAACLgAFFH8NAAINAAQJvh0LDABYAQANAAQJvh0LDABYAQAuAAQKfzsAAg0ACQkuJFsCAB8DAA0ACQkuJFsCAB8DAAAA.',
Ki='Killmaim:BAABLgAECn8ZAAINAAgJwRllIABPAgANAAgJwRllIABPAgAAAA==.Kitsuko:BAABLgAECn8sAAMcAAkJxhBKHQChAQAcAAkJxhBKHQChAQAjAAkJKAzjNQB7AQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuraishin:BAAALgADCgcJBwABLgAFFAUJEQASAFIbAA==.',
['Kë']='Këltön:BAAALgAECgIJAgAAAA==.',
La='Lavashiza:BAAALgAECgQJBgAAAA==.Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAAALgAECgYJEgAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAQAAAA==.Leedaddydk:BAAALgAECgMJBgAAAA==.Leroyjenkins:BAABLgAECn8XAAIkAAcJ8BvoAgBVAgAkAAcJ8BvoAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.',
Li='Lightstorm:BAAALgAECgYJCgAAAA==.Linaria:BAAALgAECgQJBwAAAA==.Linø:BAAALgAECgEJAQAAAA==.Lissara:BAABLgAECn8UAAIfAAgJmA87JgBZAQAfAAgJmA87JgBZAQAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAACLgAFFH8KAAIlAAMJdhXFJADiAAAlAAMJdhXFJADiAAAuAAQKfyIAAiUACAm9H+kMACsCACUACAm9H+kMACsCAAAA.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECggJGwADAOgjAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAFFAQJCgAVALUSAA==.Luminouslexi:BAAALgADCgUJBwAAAA==.',
Ma='Macoub:BAAALgAECgYJDAAAAA==.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAABLgAECn8ZAAMWAAgJfAWOEgDXAAAWAAgJUQWOEgDXAAAbAAQJzAOZyABsAAAAAA==.Mageslayer:BAABLgAECn8bAAMmAAgJmxMbEwC3AQAmAAgJGRIbEwC3AQABAAMJPhBTEwCoAAAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgAQAAAAAA==.Makkideez:BAAALgAFFAIJAgAAAA==.Manabuns:BAABLgAECn8oAAISAAgJ2xd1QQDVAQASAAgJ2xd1QQDVAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8hAAIPAAgJ7hVKQgAeAgAPAAgJ7hVKQgAeAgAAAA==.Markruffalo:BAAALgAECgMJAwAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn8rAAINAAkJNhlxDwA3AgANAAkJNhlxDwA3AgAAAA==.',
Mc='Mckay:BAAALgAECggJEwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8mAAIkAAgJOhQAAwDHAQAkAAgJOhQAAwDHAQAAAA==.Megapunk:BAAALgADCgkJIQAAAA==.Mellmaan:BAAALgADCgYJBgAAAA==.Melys:BAAALgAECgYJCwAAAA==.Mercenar:BAAALgADCgEJAQAAAA==.Meteorite:BAAALgAECgYJCAAAAA==.Meudayr:BAAALgAECgkJEQAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.',
Mi='Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAABLgAECn8eAAIcAAgJZhwiEgCSAgAcAAgJZhwiEgCSAgAAAA==.',
Mo='Moistblanket:BAAALgAECgUJBwAAAA==.Mojorisin:BAABLgAECn8aAAICAAkJnxqiBwB6AgACAAkJnxqiBwB6AgAAAA==.Moonchiken:BAAALgAECgEJBQAAAA==.Moozlock:BAABLgAECn8gAAIbAAkJWBF+PACqAQAbAAkJWBF+PACqAQAAAA==.Moscovio:BAAALgAFFAIJBAAAAA==.Mosspaws:BAABLgAECn82AAMYAAkJbiQRBABPAwAYAAkJbiQRBABPAwAaAAQJZB/MJABIAQAAAA==.',
Mt='Mtndewyou:BAAALgAECgQJBAAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.',
Na='Narfiy:BAAALgADCgEJAQAAAA==.Narisanna:BAAALgAFFAEJAgAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBgAAAA==.',
Nm='Nme:BAABLgAECn8lAAMSAAkJoBDjPgDeAQASAAkJoBDjPgDeAQAkAAYJiw9LCQBWAQAAAA==.',
No='Nocturnos:BAABLgAECn8sAAMbAAkJZR2dDwCaAgAbAAkJZR2dDwCaAgAVAAEJUB94LABGAAAAAA==.Noggin:BAABLgAECn8rAAMLAAkJSCH/BAAcAwALAAkJSCH/BAAcAwAPAAgJ/BAWRACxAQAAAA==.Nonform:BAABLgAECn81AAQaAAkJGRmQDgAiAgAaAAkJGRmQDgAiAgAJAAEJwRW1LgBAAAAYAAEJdAED7AAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECgYJDAAQAAAAAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQAQAAAAAA==.Novamancer:BAAALgAECgEJAQAAAA==.Noxta:BAAALgAECggJEgAAAA==.',
Nu='Numonixx:BAACLgAFFH8XAAMFAAUJwA0KBAD/AAAfAAUJwA2BHgAYAQAFAAQJ6gcKBAD/AAAuAAQKfyYAAwUACAn1HKgJAEUCAAUACAl9G6gJAEUCAB8ABwkuG0gZALwBAAAA.Nutlessfred:BAAALgADCgYJBgAAAA==.',
Ny='Nymage:BAABLgAECn9JAAISAAkJDRsyGwB9AgASAAkJDRsyGwB9AgAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogmund:BAAALgAECgQJBAAAAA==.',
Oh='Ohnospiders:BAABLgAECn8iAAIUAAkJVhPGMAD1AQAUAAkJVhPGMAD1AQAAAA==.Ohpig:BAAALgAECgMJAwAAAA==.',
Ok='Okaerisan:BAAALgAECgcJEQAAAA==.',
Om='Omarcuthlink:BAAALgAECgEJAQABLgAECggJJwAVACsSAA==.Omgbbqq:BAAALgAECggJAgABLgAECgkJKwADANkjAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECgQJBQAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Ou='Outlast:BAACLgAFFH8KAAIPAAMJ8xCFPgDwAAAPAAMJ8xCFPgDwAAAuAAQKfysAAg8ACQk8HbQRAAQDAA8ACQk8HbQRAAQDAAAA.',
Pa='Paants:BAABLgAECn8YAAInAAcJeg0xIADiAAAnAAcJeg0xIADiAAAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Pakal:BAAALgADCgQJBAAAAA==.Palebull:BAAALgADCgUJBwAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8TAAIRAAUJqSToDQCxAQARAAUJqSToDQCxAQAuAAQKfzMAAhEACQkDJSwCAEkDABEACQkDJSwCAEkDAAAA.Parmigiano:BAAALgADCgEJAQABLgAFFAMJBgAnACcZAA==.Parmrageiano:BAABLgAFFH8GAAInAAMJJxlSEADiAAAnAAMJJxlSEADiAAAAAA==.Parms:BAABLgAECn8ZAAQCAAgJ+xNkGgCAAQACAAgJ6xFkGgCAAQAEAAYJhQxETQAcAQADAAIJORANowCFAAABLgAFFAMJBgAnACcZAA==.',
Pe='Peanought:BAABLgAECn8iAAMHAAgJsRcBBgDJAQAHAAgJsRcBBgDJAQAUAAYJXAizvQAHAQAAAA==.Peidro:BAABLgAECn8UAAIPAAcJrAswjgAJAQAPAAcJrAswjgAJAQAAAA==.Pentacles:BAABLgAECn8tAAIKAAkJsCD5AwCLAgAKAAkJsCD5AwCLAgAAAA==.',
Pi='Pijak:BAAALgAECgYJEgAAAA==.Pinkpaw:BAABLgAECn8WAAMKAAgJbxxlBgA6AgAKAAgJbxxlBgA6AgAYAAUJthp8OABsAQAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8IAAMlAAMJ3iTvCABGAQAlAAMJ3iTvCABGAQAMAAEJbQsLKQBAAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCAAlAN4kAA==.Postscalone:BAAALgAECgEJAQAAAA==.Potatoes:BAABLgAECn8VAAMWAAgJBgiWHABpAQAWAAgJBgiWHABpAQAbAAIJCQJIFAE6AAAAAA==.',
Pr='Pruflas:BAABLgAECn8ZAAIUAAgJZAtXYgBaAQAUAAgJZAtXYgBaAQAAAA==.',
Ps='Psycodk:BAABLgAECn8VAAIUAAcJyhYIcgA2AQAUAAcJyhYIcgA2AQAAAA==.',
Pu='Pumpin:BAABLgAECn8XAAIMAAUJFCRvHAB6AQAMAAUJFCRvHAB6AQAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
Qk='Qkn:BAAALgAECgUJDgAAAA==.',
Qu='Quickswipe:BAAALgAFFAIJAgABLgAFFAUJJAAWANciAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgYJCwABLgAECgcJAQAQAAAAAA==.Ralee:BAAALgADCgIJAgAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Rastabution:BAAALgAECgEJAQAAAA==.Raynne:BAAALgAECgIJAgAAAA==.',
Re='Reaperjoe:BAAALgAFFAEJAQAAAA==.Rehab:BAAALgAECgkJEwAAAA==.Rehna:BAAALgAECgYJBgABLgAFFAMJCgAGANAVAA==.Rektributio:BAACLgAFFH8cAAIPAAcJMh9qAQBqAgAPAAcJMh9qAQBqAgAuAAQKfzcAAg8ACQkgJYwCAFMDAA8ACQkgJYwCAFMDAAAA.Revalation:BAABLgAECn8dAAIYAAkJKR3fHgBIAgAYAAkJKR3fHgBIAgAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgAQAAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Ribeyejoe:BAAALgADCgEJAQAAAA==.Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAABLgAECn8bAAMnAAcJnxIPFgBEAQAnAAcJmRIPFgBEAQANAAUJuAwaaQAQAQAAAA==.Roadtrip:BAAALgAECgMJBAAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJAwAAAA==.Rottingslow:BAAALgAFFAIJAgABLgAFFAgJFgAIALkeAA==.',
Sa='Saragos:BAAALgADCgcJBgABLgAFFAUJEQASAFIbAA==.Saucerdote:BAABLgAECn8eAAMhAAkJmRVnFADhAQAhAAcJGxdnFADhAQAXAAkJFAlZIABuAQAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAUJEQASAFIbAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAABLgAECn8dAAIRAAkJxxxYFQBXAgARAAkJxxxYFQBXAgAAAA==.Selkie:BAABLgAECn8aAAIoAAgJiwvjDgBPAQAoAAgJiwvjDgBPAQAAAA==.Seragosa:BAAALgAFFAEJAQABLgAFFAUJEQASAFIbAA==.',
Sh='Shakakhan:BAAALgAECgYJBwABLgAECgYJGwAPAGccAA==.Shambeau:BAAALgADCgQJBAAAAA==.Shamrun:BAAALgADCgEJAQAAAA==.Shamshielder:BAEBLgAECn8kAAMIAAcJHSEtDgAqAgAIAAcJHSEtDgAqAgAUAAEJuQnWIgEpAAABLgAFFAMJBQAcAHwGAA==.Sharick:BAAALgAECgQJBQAAAA==.Shawlee:BAABLgAECn8rAAMjAAgJzBAgQQBGAQAjAAgJzBAgQQBGAQAcAAgJCAhlTQCoAAAAAA==.Sheezie:BAABLgAECn8mAAIjAAgJZRquFQBJAgAjAAgJZRquFQBJAgAAAA==.Shellter:BAAALgAECgEJAgABLgAECggJGgATABccAA==.Shellwit:BAAALgAECgMJBgABLgAECggJGgATABccAA==.Sheph:BAAALgAECgcJCQAAAA==.Shetmage:BAACLgAFFH8TAAISAAUJ+QzWIwAoAQASAAUJ+QzWIwAoAQAuAAQKfykAAhIACQnDILwTAKwCABIACQnDILwTAKwCAAAA.Shettrah:BAAALgAECgYJEQABLgAFFAUJEwASAPkMAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAABLgAECn8ZAAIPAAgJ/hDNWwBxAQAPAAgJ/hDNWwBxAQAAAA==.Shuck:BAAALgAECgQJBAABLgAFFAMJBQANALoaAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Siickboy:BAAALgAECgQJCQAAAA==.Sijious:BAAALgAECgEJAQAAAA==.Silveah:BAAALgADCgEJAQAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.',
Sk='Skora:BAAALgADCgIJAgABLgAECggJIQAPAO4VAA==.Skyland:BAAALgADCgcJDQAAAA==.Skyli:BAAALgAECgUJCAABLgAECgkJGAAjAGsdAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAACLgAFFH8KAAILAAMJVBzJHADtAAALAAMJVBzJHADtAAAuAAQKfyYAAgsACAlcILwIAOMCAAsACAlcILwIAOMCAAAA.Sorrie:BAAALgAECgEJAQAAAA==.',
Sp='Spud:BAAALgADCgcJBwABLgAECgUJEAAQAAAAAA==.Spyroh:BAABLgAECn8bAAQFAAYJ6BLuGQBlAQAFAAYJcBDuGQBlAQAfAAUJGBL7MgAPAQAeAAEJ2wA4TwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAMJCgAGANAVAA==.',
St='Stankydk:BAACLgAFFH8OAAMUAAUJDxt2MABSAQAUAAQJDxt2MABSAQAIAAEJAAB3QAAAAAAuAAQKfzIAAhQACQk9JQ4CAGMDABQACQk9JQ4CAGMDAAAA.Stankyeyes:BAAALgAECgYJBgAAAA==.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Steakhead:BAABLgAECn8ZAAIaAAYJCQc4PQDCAAAaAAYJCQc4PQDCAAAAAA==.Stinkbombs:BAABLgAFFH8IAAISAAQJJwNRUQADAQASAAQJJwNRUQADAQAAAA==.Stinkerz:BAAALgAECgIJAgABLgAECggJGgATABccAA==.Stunanddone:BAAALgAECgQJCAAAAA==.',
Su='Subrogue:BAAALgAFFAIJAwABLgAFFAMJBAAQAAAAAA==.Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJEAAAAA==.Supreme:BAACLgAFFH8IAAIRAAMJXho5OAD5AAARAAMJXho5OAD5AAAuAAQKfxkAAhEACAl4I24YAMMCABEACAl4I24YAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAMJAwAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAUJDQALAGEUAA==.Sylphrena:BAACLgAFFH8KAAIGAAMJKRRREwDVAAAGAAMJKRRREwDVAAAuAAQKfycAAgYACAkqIIgIAMMCAAYACAkqIIgIAMMCAAAA.',
['Sí']='Sínful:BAABLgAECn8nAAIEAAkJBh/gAgB2AgAEAAkJBh/gAgB2AgAAAA==.',
Ta='Tahwe:BAAALgADCgcJBwAAAA==.Talethen:BAAALgAECgcJEwAAAA==.Talla:BAABLgAECn8YAAIjAAkJax2mGgBCAgAjAAkJax2mGgBCAgAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgADCgkJIQAAAA==.Tellus:BAAALgADCgcJCgAAAA==.Tewshort:BAAALgAECgQJCAABLgAFFAMJCgAPAPMQAA==.',
Th='Thatbox:BAAALgAECgQJBAAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgQJDAAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAABLgAECn8UAAMMAAgJBAXJPwCyAAAlAAcJQQRZWQDeAAAMAAcJQgTJPwCyAAAAAA==.Thorfyna:BAABLgAECn8YAAIiAAcJGRKZDgARAQAiAAcJGRKZDgARAQAAAA==.Threzk:BAABLgAECn8eAAIWAAkJeg6LCQBcAQAWAAkJeg6LCQBcAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8KAAIRAAQJbRbXJgAwAQARAAQJbRbXJgAwAQAuAAQKfy8AAhEACQl2IuQFAP0CABEACQl2IuQFAP0CAAAA.Tontiamat:BAABLgAECn8xAAMfAAkJRRgAEAAgAgAfAAkJRRgAEAAgAgAFAAYJawo5IAAsAQAAAA==.Tontier:BAAALgAECgUJDAABLgAECgkJMQAfAEUYAA==.Totembeans:BAAALgAECgQJCwAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAACLgAFFH8NAAILAAUJYRQ1CwCcAQALAAUJYRQ1CwCcAQAuAAQKfxoABAsACAnDHnIHANQCAAsACAnDHnIHANQCAA8ABglODTq3ABcBAA4AAQl9Fro/AD8AAAAA.Trashfire:BAACLgAFFH8KAAMGAAQJIA5TDQAcAQAGAAQJIA5TDQAcAQAhAAIJwgF2FgB7AAAuAAQKfx0ABAYACAkXHSYQAGUCAAYACAkXHSYQAGUCABcABQknFXw2ADkBACEAAwluEWhAAK0AAAEuAAUUBQkNAAsAYRQA.Treeple:BAABLgAECn8YAAIYAAcJGRNHPQBVAQAYAAcJGRNHPQBVAQAAAA==.Treily:BAAALgAECgQJCQAAAA==.Tresleches:BAABLgAECn8eAAIPAAcJYg/6fwAjAQAPAAcJYg/6fwAjAQAAAA==.Tricket:BAABLgAECn8zAAMgAAgJIhvtBgBWAgAgAAgJjRrtBgBWAgANAAYJKBnXPgD4AAAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAWAAYIAQ==.Truestorm:BAABLgAECn8lAAIPAAgJwAsSbABLAQAPAAgJwAsSbABLAQAAAA==.Truheals:BAAALgADCgkJEwAAAA==.',
Tu='Tuchi:BAACLgAFFH8VAAISAAUJkBxJLgBZAQASAAUJkBxJLgBZAQAuAAQKfxwAAxIABwliIrkyAKgCABIABwliIrkyAKgCACQAAglBBa8YAFMAAAAA.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAUJEwARAKkkAA==.',
['Tà']='Tàcobelle:BAAALgADCgYJBwABLgAECggJKAASANsXAA==.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgAQAAAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIjAAMJriIOHwAQAQAjAAMJriIOHwAQAQAuAAQKfzEAAyMACQllGz8SAIQCACMACQllGz8SAIQCABwABgkTGtwjAHIBAAAA.Varanis:BAACLgAFFH8IAAIDAAMJnxZuDAD/AAADAAMJnxZuDAD/AAAuAAQKfxcAAgMACAkLImMLAOgCAAMACAkLImMLAOgCAAAA.',
Ve='Vegh:BAABLgAECn8+AAIiAAkJGh6pAgCDAgAiAAkJGh6pAgCDAgAAAA==.Vem:BAABLgAECn8cAAIfAAkJDh0mEAB1AgAfAAkJDh0mEAB1AgAAAA==.Veriale:BAAALgAECgUJCgAAAA==.Verra:BAABLgAECn8qAAIPAAgJKBlJMAD3AQAPAAgJKBlJMAD3AQAAAA==.',
Vi='Vitriol:BAABLgAECn8bAAINAAYJMBzCLQBLAQANAAYJMBzCLQBLAQAAAA==.',
Vo='Voidbeaver:BAAALgAECgYJCQAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAACLgAFFH8KAAMVAAQJtRLbAQBDAQAVAAQJtRLbAQBDAQAWAAEJYQcQHABBAAAuAAQKfx0AAhUACAkPI6sBAMoCABUACAkPI6sBAMoCAAAA.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgYJCQAQAAAAAA==.Vyrros:BAAALgADCgUJBQAAAA==.',
Wa='Walji:BAABLgAECn8eAAMjAAgJyhtyFwBaAgAjAAgJyhtyFwBaAgAcAAEJWwukfAAqAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgAECgIJAgAAAA==.Wandy:BAABLgAECn8lAAIbAAgJ0BE4WgBRAQAbAAgJ0BE4WgBRAQAAAA==.Wangstah:BAABLgAECn8bAAIDAAgJ6COCDgCWAgADAAgJ6COCDgCWAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAINAAYJNhQUSgB8AQANAAYJNhQUSgB8AQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJDgAAAA==.Wawatesi:BAAALgAECgMJAwAAAA==.Waytogoteam:BAABLgAECn8rAAIDAAkJ2SPRBAAQAwADAAkJ2SPRBAAQAwAAAA==.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8RAAMSAAUJUhtvKgBhAQASAAUJUhtvKgBhAQATAAIJBw76AQCgAAAuAAQKfzMABBIACQnDJGQGACkDABIACQk3JGQGACkDABMABgm+I3wDANkBACQAAQmPIMgWAGQAAAAA.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgEJAQAAAA==.',
Wo='Woodyy:BAABLgAECn8UAAIUAAgJ7AWSegAlAQAUAAgJ7AWSegAlAQAAAA==.Woog:BAAALgAECgQJBAAAAA==.Wox:BAAALgAECgYJCQAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wu='Wulfgar:BAAALgAECgYJBgAAAA==.',
Wy='Wyldspirit:BAABLgAECn8UAAIDAAYJ6wnycgD8AAADAAYJ6wnycgD8AAAAAA==.Wyreless:BAAALgADCgYJBgABLgAECggJKgAJAAgWAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgADCgEJAQAAAA==.',
Ya='Yaass:BAAALgAECgMJAwAAAA==.',
Ye='Yem:BAACLgAFFH8kAAQWAAUJ1yICAgBvAQAWAAUJWh0CAgBvAQAbAAQJ/h8pIQBYAQAVAAIJYSJeCgBdAAAuAAQKfzYAAxYACQmiIzkGAGwCABYABgncIzkGAGwCABsABgliI1VJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAIKAAcJvxm2CAAfAgAKAAcJvxm2CAAfAgABLgAFFAQJBwAPAF4MAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAAQAAAAAA==.Zanzabar:BAAALgAECggJDgAAAA==.Zaraelitha:BAAALgAECgEJAQAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgIJAwAAAA==.Zeodrik:BAABLgAECn8cAAINAAcJYRmUJwBvAQANAAcJYRmUJwBvAQAAAA==.',
Zh='Zhenya:BAACLgAFFH8KAAISAAMJgRTOVQD5AAASAAMJgRTOVQD5AAAuAAQKfyYAAxIACAnXGthDAM4BABIACAnXGthDAM4BACQABAkvD+gOANUAAAAA.',
Zi='Zidguard:BAAALgAECgYJBwAAAA==.Zigzauer:BAAALgAECgQJBAAAAA==.Ziroken:BAAALgADCgUJBQAAAA==.',
Zo='Zombeaver:BAAALgADCgcJCgAAAA==.',
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
