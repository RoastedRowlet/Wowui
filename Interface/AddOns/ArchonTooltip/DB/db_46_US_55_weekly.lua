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

local lookup = {'Rogue-Assassination','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Evoker-Devastation','Priest-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Feral','Druid-Restoration','Druid-Guardian','Paladin-Holy','Paladin-Retribution','Monk-Windwalker','Paladin-Protection','Warrior-Fury','Shaman-Enhancement','Unknown-Unknown','DemonHunter-Devourer','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Demonology','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','DemonHunter-Vengeance','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abracadava:BAAALgAECgQJBAAAAA==.',
Ac='Acheniris:BAAALgAECgUJDQAAAA==.',
Ad='Adeaino:BAAALgAECgUJCAAAAA==.Adonix:BAAALgAECgEJAQAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgUJBwAAAA==.',
Ag='Agrippa:BAACLgAFFH8GAAIBAAMJyQGeCACiAAABAAMJyQGeCACiAAAuAAQKfxsAAgEABwmRD44JAKMBAAEABwmRD44JAKMBAAAA.',
Ah='Ahndhrez:BAAALgAECgYJBQAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECggJEgAAAA==.Aioli:BAABLgAECn8kAAQCAAkJ1BsAEAAjAgACAAkJuRgAEAAjAgADAAYJ7hdaRwCUAQAEAAUJcRo4SAAzAQAAAA==.Airwavez:BAAALgAECgcJDQAAAA==.',
Al='Alchemorph:BAABLgAECn8XAAIFAAgJSwmDNwAbAQAFAAgJSwmDNwAbAQAAAA==.Aldormu:BAABLgAECn8gAAIGAAkJTwy6CQB2AQAGAAkJTwy6CQB2AQAAAA==.Aliyah:BAEALgADCgIJAgABLgAECgkJJgAHAMoZAA==.Allura:BAACLgAFFH8SAAIHAAQJzRHRFgDmAAAHAAQJzRHRFgDmAAAuAAQKfyQAAgcACQmLGQ4WACwCAAcACQmLGQ4WACwCAAAA.Altra:BAACLgAFFH8SAAIIAAQJDgsSDAARAQAIAAQJDgsSDAARAQAuAAQKfygAAwgACAkUH1YCAJ8CAAgACAkUH1YCAJ8CAAkABwl7A1orAOQAAAAA.Alyvia:BAAALgADCgEJAgAAAA==.',
Am='Amoeta:BAABLgAECn8zAAQKAAgJ6hbjDADFAQAKAAgJ0hXjDADFAQALAAcJyQivYQD+AAAMAAcJEQ/bJgD4AAAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgQJBAAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgADCggJDAAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angryapples:BAAALgAECgQJCQAAAA==.Antinous:BAABLgAECn8qAAIEAAgJ3gyrEAA4AQAEAAgJ3gyrEAA4AQAAAA==.',
Ar='Arcstorm:BAAALgAECgYJDAAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Ashenback:BAAALgAFFAEJAQABLgAFFAYJDgANAO8RAA==.Asomyrh:BAABLgAECn8lAAMNAAkJmxXBFgA+AgANAAkJmxXBFgA+AgAOAAEJPQG/pAETAAAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgYJCAAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgAECgEJAQAAAA==.',
Av='Averyl:BAAALgAECgUJBQAAAA==.Aviendha:BAAALgAECgYJBwAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAIPAAgJLQptKgCKAQAPAAgJLQptKgCKAQAAAA==.',
Az='Azenith:BAABLgAECn8WAAMOAAYJ8xbBkAA1AQAOAAYJ8xbBkAA1AQAQAAEJrQhgTAAnAAAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bamboozle:BAAALgADCgcJBwAAAA==.Bananer:BAABLgAECn8iAAIRAAkJeBTyHgDjAQARAAkJeBTyHgDjAQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Be='Beaugersugar:BAAALgAECgQJBQAAAA==.Beebler:BAABLgAECn8YAAISAAgJnhedDADLAQASAAgJnhedDADLAQAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgAECgcJCAAAAA==.Beowulf:BAAALgAECgEJAQAAAA==.Bestt:BAAALgAECgQJCAAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigholylady:BAAALgADCgkJCQAAAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigocagler:BAAALgAECgcJAQAAAA==.Bigolchungus:BAABLgAECn8eAAMQAAkJwRpuCQA7AgAQAAgJeBluCQA7AgAOAAUJ6BiAqwAKAQAAAA==.Bigpapadots:BAAALgAECgEJAQAAAA==.Bigshizz:BAAALgAECgQJBQABLgAECgcJEQATAAAAAA==.Bippysmasher:BAABLgAECn8kAAIUAAkJaxLGQACvAQAUAAkJaxLGQACvAQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.',
Bl='Blacblood:BAABLgAECn8fAAIIAAkJYRHNBQDSAQAIAAkJYRHNBQDSAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJEQAAAA==.Blindweiss:BAAALgAFFAEJAQABLgAFFAYJFAAVAMkWAA==.Blinkies:BAABLgAECn8iAAMWAAkJbSClAADsAgAWAAkJbSClAADsAgAVAAUJlg+MrgAIAQAAAA==.Blinkster:BAAALgAECgEJBAAAAA==.Bloodfushion:BAAALgADCgYJBgAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgAECgMJAwATAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8OAAIDAAYJOh29DwChAQADAAYJOh29DwChAQAuAAQKfysAAgMACQmNI0UHABMDAAMACQmNI0UHABMDAAAA.Borstenne:BAACLgAFFH8RAAIXAAQJGR1UOgBdAQAXAAQJGR1UOgBdAQAuAAQKfygAAhcACAnnJIMTAAYDABcACAnnJIMTAAYDAAAA.',
Br='Brake:BAACLgAFFH8KAAIXAAMJnxFKiwDSAAAXAAMJnxFKiwDSAAAuAAQKfyYAAhcACAlXHvU1AF8CABcACAlXHvU1AF8CAAAA.Brese:BAAALgAECgIJAgABLgAFFAQJEgAUAHIZAQ==.Breseayaya:BAACLgAFFH8SAAIUAAQJchmKLwA8AQAUAAQJchmKLwA8AQAuAAQKfywAAhQACAmpIdwLACIDABQACAmpIdwLACIDAAAA.Breseshh:BAAALgAECgcJEwABLgAFFAQJEgAUAHIZAA==.Brickbeard:BAABLgAECn8tAAMYAAkJdBVEBQAXAgAYAAkJdBVEBQAXAgAZAAcJww3lGQB9AQAAAA==.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJEgABLgAFFAcJFwAOAMYgAA==.Bricksquad:BAAALgAECgMJAwABLgAFFAMJBAATAAAAAA==.Brickthrow:BAACLgAFFH8XAAMOAAcJxiBMIABiAQAOAAUJoiBMIABiAQANAAMJOQjvJgDUAAAuAAQKfzMAAw4ACQmsJPIFADEDAA4ACQmsJPIFADEDAA0ABQlyBM5pAG8AAAAA.',
Bu='Buhleed:BAAALgAECgIJAgAAAA==.Burgerburn:BAAALgAECgUJBQAAAA==.',
By='Bytheway:BAABLgAECn8WAAIaAAgJ4ROXKQBlAQAaAAgJ4ROXKQBlAQAAAA==.',
['Bà']='Bàbÿ:BAAALgAECgcJDgAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAACLgAFFH8SAAILAAQJdhLzJgAPAQALAAQJdhLzJgAPAQAuAAQKfzAABAsACAlqJEgOANUCAAsACAlqJEgOANUCAAUAAglbG1JwAE8AAAwAAQlKAac3ABkAAAAA.Cadsune:BAAALgAECgYJDAAAAA==.Caelesti:BAABLgAECn8gAAMaAAgJSRMQJQCCAQAaAAcJVBUQJQCCAQAHAAYJthJYLgBDAQAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAgAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQAAAA==.Chelbur:BAAALgADCgEJAQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chowderhead:BAABLgAECn8UAAIZAAYJYxzhDgDcAQAZAAYJYxzhDgDcAQAAAA==.',
Ci='Cileb:BAACLgAFFH8GAAIVAAUJSBibTQA1AQAVAAUJSBibTQA1AQAuAAQKfzUAAhUACQmkJGcJABwDABUACQmkJGcJABwDAAAA.Civik:BAABLgAECn9DAAIDAAkJZSNsDQDTAgADAAkJZSNsDQDTAgAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAFFAMJBAATAAAAAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAACLgAFFH8OAAIOAAQJUQyAQAATAQAOAAQJUQyAQAATAQAuAAQKfzAAAg4ACQldGi03AAwCAA4ACQldGi03AAwCAAAA.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAECggJFAAbAHoVAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJJwAJAAkjAA==.Copperit:BAABLgAECn8nAAIJAAkJCSOQAgBDAwAJAAkJCSOQAgBDAwAAAA==.Cornburglar:BAACLgAFFH8HAAIRAAMJMRs6JgD7AAARAAMJMRs6JgD7AAAuAAQKfzcAAhEACAlcJa8GAOMCABEACAlcJa8GAOMCAAAA.Cowtaclysmic:BAABLgAECn8cAAIXAAgJJQrsfwBOAQAXAAgJJQrsfwBOAQAAAA==.',
Cr='Crackersz:BAABLgAECn8WAAMcAAcJHQhrfADIAAAcAAcJHQhrfADIAAAdAAMJGAQVeQBhAAAAAA==.Cranjis:BAABLgAECn87AAIeAAkJliHCBgAZAwAeAAkJliHCBgAZAwAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Crunchwrap:BAABLgAECn8mAAIFAAgJAA8lKgBnAQAFAAgJAA8lKgBnAQAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgcJBwAAAA==.',
Cu='Curadora:BAAALgADCgQJBAAAAA==.Cursereflect:BAABLgAECn8iAAMfAAkJyQ77SQCxAQAfAAkJyQ77SQCxAQAZAAEJAADKTgAAAAAAAA==.Curseus:BAAALgAECgIJBAAAAA==.',
Cy='Cyberwin:BAAALgAECgEJAQAAAA==.',
Da='Damncats:BAABLgAECn81AAIRAAgJYxAZLACPAQARAAgJYxAZLACPAQAAAA==.Dandinn:BAAALgAECgYJCQAAAA==.Danielsboone:BAABLgAECn8ZAAIDAAcJcQ8KaQBYAQADAAcJcQ8KaQBYAQAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJCAABLgAFFAQJDAAdAMMMAA==.Darknemesis:BAAALgADCggJDgABLgADCgkJIQATAAAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAFFAEJAgABLgAFFAYJMgAZAPsiAA==.',
De='Deaaron:BAAALgADCgEJAQAAAA==.Deadhippocow:BAABLgAECn8YAAILAAYJjRsYLwDVAQALAAYJjRsYLwDVAQAAAA==.Deathwavez:BAACLgAFFH8OAAIXAAQJvBLoVAAtAQAXAAQJvBLoVAAtAQAuAAQKfxoAAhcABwkwFwFlAMUBABcABwkwFwFlAMUBAAAA.Decurse:BAABLgAECn8gAAIfAAgJThWFTgCkAQAfAAgJThWFTgCkAQAAAA==.Deldrin:BAABLgAECn8eAAIVAAgJTRK7bgCDAQAVAAgJTRK7bgCDAQAAAA==.Demayy:BAABLgAECn8nAAIeAAkJphGuIgDfAQAeAAkJphGuIgDfAQAAAA==.Demona:BAACLgAFFH8LAAMfAAQJAwxQUAATAQAfAAQJAwxQUAATAQAYAAEJkgcQIwBBAAAuAAQKfyUAAxkACAkxGe4pABoBAB8ABwnIFbxtAFUBABkABAngE+4pABoBAAAA.Demonix:BAABLgAECn8XAAIfAAgJLhqbNAD6AQAfAAgJLhqbNAD6AQAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAABLgAECn83AAIVAAkJBg/eUADRAQAVAAkJBg/eUADRAQAAAA==.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAABLgAECn8eAAMOAAYJZxzQagB/AQAOAAYJZxzQagB/AQANAAIJsAQfeQBGAAAAAA==.Dinobrass:BAABLgAECn8jAAIEAAgJtA0bDwBQAQAEAAgJtA0bDwBQAQAAAA==.Dirktheshiny:BAAALgAECgYJBgABLgAECgkJPQAFAIEbAA==.Dirtylöbster:BAACLgAFFH8OAAIVAAMJTCHYJwAUAQAVAAMJTCHYJwAUAQAuAAQKfzUAAhUACQkKJYQHADADABUACQkKJYQHADADAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgYJEQABLgAECgYJHgAOAGccAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAAALgAECgYJEgAAAA==.Dorfydorf:BAAALgAECgEJAgAAAA==.Dorose:BAAALgAECgEJAgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Dranight:BAAALgAECgcJBwABLgAECgkJQwADAGUjAA==.Dreats:BAAALgAECgUJBgAAAA==.Drewmee:BAABLgAECn8YAAIOAAkJHgltgwBNAQAOAAkJHgltgwBNAQAAAA==.Dronar:BAABLgAFFH8FAAIcAAUJCgkUJAAzAQAcAAUJCgkUJAAzAQABLgAECgkJIwAMAAEgAA==.Drublood:BAAALgAECgcJCwABLgAECgkJGAAOAB4JAA==.Drunkinmasta:BAAALgAECgEJAQABLgAFFAQJEAAOAB4WAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Dune:BAAALgADCgcJBwAAAA==.Duwork:BAAALgAECgcJEQAAAA==.',
['Dæ']='Dæmona:BAAALgAECggJBwAAAA==.',
Eb='Ebk:BAAALgAECgcJDAAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
Ei='Eight:BAAALgADCggJDQAAAA==.',
El='Eladus:BAAALgAECgYJDwAAAA==.Elemnt:BAAALgAECgYJDQABLgAFFAQJEAAOAB4WAA==.Elesus:BAAALgAECggJDQABLgAECgkJQwAgAJUhAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJDgAAAA==.Emrys:BAAALgAECgEJAQAAAA==.',
En='Enhshaman:BAACLgAFFH8FAAIeAAMJGQaNMwCZAAAeAAMJGQaNMwCZAAAuAAQKfxYAAh4ACQn+FEkfAPgBAB4ACQn+FEkfAPgBAAAA.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.Evilinne:BAAALgADCgIJAgAAAA==.Evânescence:BAAALgAECgEJAQAAAA==.',
Ex='Excaliburn:BAAALgAECgEJAQAAAA==.',
Ez='Ezkal:BAACLgAFFH8RAAIXAAUJQBunUAAzAQAXAAUJQBunUAAzAQAuAAQKfywAAxcACQnsGaEYAOgCABcACQnsGaEYAOgCAAkABgktFagmAAYBAAAA.',
Fa='Faithastray:BAAALgAECgMJAwAAAA==.Faithpasse:BAABLgAECn8nAAMeAAgJ6BWPHwD2AQAeAAgJ6BWPHwD2AQAPAAEJ9gPfhgApAAAAAA==.Falcorne:BAABLgAECn8pAAIDAAgJ2CC5GAB7AgADAAgJ2CC5GAB7AgAAAA==.Fatlipz:BAAALgAECgcJEAAAAA==.Fay:BAAALgADCgEJAQABLgAECgYJCAATAAAAAA==.',
Fe='Felondar:BAABLgAECn8iAAMbAAkJVgtkHQBsAQAbAAkJVgtkHQBsAQAUAAYJsASzmwDhAAAAAA==.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8ZAAMJAAkJhBsxDABOAgAJAAcJsBsxDABOAgAXAAgJvhiIagC3AQAAAA==.',
Fi='Finnadin:BAABLgAECn8ZAAIOAAcJbx70QgDlAQAOAAcJbx70QgDlAQAAAA==.Finns:BAAALgAECgcJDQAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAABLgAECn8cAAIDAAgJ0xn2MAABAgADAAgJ0xn2MAABAgAAAA==.Fistobeef:BAAALgAECgEJAQAAAA==.',
Fl='Fleable:BAAALgAECgEJAQAAAA==.Flysky:BAACLgAFFH8aAAIhAAcJKBlPBgAoAgAhAAcJKBlPBgAoAgAuAAQKfywABCEACQnFI4kCAEcDACEACQnFI4kCAEcDACIACAnIJGsGAN0CAAYAAQl3DyBBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECggJDQAAAA==.',
Fr='Freakmeout:BAAALgAECgQJBAAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgAECgEJAQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJDgABLgAFFAUJEQAXAEAbAA==.Futuredragoo:BAAALgAECgcJDAABLgAFFAUJEQAXAEAbAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Fy='Fyska:BAAALgADCgEJAQAAAA==.',
Ga='Gabriella:BAAALgAECgQJBwAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQATAAAAAA==.Galnannix:BAAALgAECggJDQAAAA==.Gardrake:BAABLgAECn8sAAMiAAkJrBk3DwBZAgAiAAkJrBk3DwBZAgAhAAcJUQ+rHQCWAQAAAA==.Gastapha:BAABLgAECn8XAAIUAAgJYgZNlADZAAAUAAgJYgZNlADZAAAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMRAAgJCxMcMADvAQARAAgJCxMcMADvAQAjAAEJAAAifAAAAAAAAA==.Gehennas:BAAALgAFFAMJBAAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Go='Goku:BAAALgAECgkJCQAAAA==.Goofykirby:BAAALgADCgcJFQAAAA==.Googoo:BAABLgAECn8UAAIXAAkJrhPsMgAfAgAXAAkJrhPsMgAfAgAAAA==.Googoogagaa:BAACLgAFFH8MAAIaAAQJkhBGFwAZAQAaAAQJkhBGFwAZAQAuAAQKf0YAAxoACQkKHo0LAH0CABoACQkKHo0LAH0CAAcABwnyEgMqAKIBAAAA.Gotlieb:BAAALgAECgYJBwAAAA==.',
Gr='Grenno:BAAALgAECgcJBwABLgAFFAcJGgAXAAYfAA==.Greystorm:BAAALgAECgIJAgAAAA==.Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQATAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8dAAMEAAgJNRJYBwCnAQAEAAcJXRRYBwCnAQACAAUJnwywEQAzAQAuAAQKfxQAAgQABwkJJOIRAKoCAAQABwkJJOIRAKoCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hamatza:BAAALgAECgEJAgAAAA==.Hammerinfred:BAAALgAECgQJBAAAAA==.Hawkmoon:BAAALgAECgEJAQAAAA==.',
He='Healingisfun:BAAALgAECgMJBAAAAA==.Helhunter:BAABLgAECn8xAAIUAAkJbRI/PwC0AQAUAAkJbRI/PwC0AQAAAA==.Hellock:BAAALgAFFAEJAQAAAA==.',
Hi='Hippysmasher:BAAALgAECgIJAgAAAA==.',
Ho='Hodgepodge:BAAALgAECgEJAgAAAA==.Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgMJBQAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holybob:BAAALgAECgQJCAAAAA==.Holyhooters:BAABLgAECn85AAIOAAkJ2yFQDADuAgAOAAkJ2yFQDADuAgAAAA==.Holypablo:BAAALgAECgQJBgABLgAECgkJSgAgAD8fAA==.Homefries:BAAALgADCgYJBgABLgAECgYJGAALAI0bAA==.Honkytonk:BAABLgAECn8aAAMGAAgJKQtAIgAYAQAGAAYJ7QlAIgAYAQAiAAcJeAmsOAATAQAAAA==.Honor:BAAALgAECgcJBwABLgAECgkJOwAOAI8jAA==.Honour:BAABLgAECn87AAIOAAkJjyOlCgD9AgAOAAkJjyOlCgD9AgAAAA==.',
Hr='Hrathdemon:BAACLgAFFH8RAAIUAAQJlxfbMAA4AQAUAAQJlxfbMAA4AQAuAAQKfyoAAhQACAmMImsXAHUCABQACAmMImsXAHUCAAAA.Hrathid:BAAALgADCgUJDAABLgAFFAQJEQAUAJcXAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8KAAIOAAMJiiBUEgATAQAOAAMJiiBUEgATAQAuAAQKfywAAg4ACQnqI7oFAHIDAA4ACQnqI7oFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAABLgAECn8WAAIOAAkJwRtmKABIAgAOAAkJwRtmKABIAgAAAA==.',
Ib='Ibleedorange:BAAALgAECgcJDAAAAA==.',
Ic='Ickeetard:BAABLgAECn8aAAMgAAgJIxHtKgBaAQAgAAcJFA/tKgBaAQAHAAUJrg/4RwCuAAAAAA==.',
Id='Idiot:BAAALgAECgMJBAAAAA==.Idiotbreath:BAABLgAECn82AAMiAAkJFSCsBwDGAgAiAAkJFSCsBwDGAgAGAAMJmQmDMACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgAECgEJAgAAAA==.',
Ig='Iglooshocker:BAECLgAFFH8FAAIdAAMJfAbVEQDXAAAdAAMJfAbVEQDXAAAuAAQKfxYAAx0ACAkqGQUXAGACAB0ACAkqGQUXAGACABwAAQkBDAfGACoAAAEuAAUUBAkFAAgAzg4A.',
Im='Immorlich:BAAALgAECgEJAQAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJCQAAAA==.Inflexi:BAABLgAECn8tAAMDAAkJaiAZCgDzAgADAAkJmB8ZCgDzAgAEAAgJyhrwGABkAgAAAA==.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAABLgAECn8YAAIPAAYJWhmCKgBOAQAPAAYJWhmCKgBOAQAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn8/AAQLAAkJIB7hDADkAgALAAkJIB7hDADkAgAFAAgJFyCSEgAtAgAMAAMJ2hazMADBAAAAAA==.',
Iv='Iver:BAAALgAECgUJBQABLgAECgcJEQATAAAAAA==.',
Ja='Jangle:BAAALgADCgYJBwAAAA==.',
Je='Jeffblades:BAAALgAECgYJCgAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJBgATAAAAAA==.',
Jj='Jjooaacchhim:BAAALgAECgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8iAAIDAAkJfBuTJgAvAgADAAkJfBuTJgAvAgAAAA==.',
Ka='Kadillac:BAAALgAECgcJDQAAAA==.Kaelira:BAAALgADCgIJAgAAAA==.Kairei:BAAALgAECgYJDQAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAACLgAFFH8PAAIOAAUJUR2QIgBaAQAOAAUJUR2QIgBaAQAuAAQKfx0AAw4ACQl1IrkNAOICAA4ACQkUIrkNAOICABAAAQlIJYE2AGkAAAAA.Katalina:BAABLgAECn8rAAMkAAgJkhCiDQBeAQAkAAgJkhCiDQBeAQAbAAYJpwsROAAlAQAAAA==.Kawer:BAAALgAECgQJCQAAAA==.Kawnzerker:BAAALgADCgkJCQAAAA==.',
Ke='Kelstormhoof:BAAALgADCgcJFgABLgADCgkJIQATAAAAAA==.Kernel:BAAALgAECgEJAQABLgAFFAMJBwARADEbAA==.',
Kh='Kham:BAACLgAFFH8PAAIRAAQJ4B44EQBdAQARAAQJ4B44EQBdAQAuAAQKfzsAAhEACQkuJA0FAAADABEACQkuJA0FAAADAAAA.',
Ki='Killmaim:BAABLgAECn8ZAAIRAAgJwRllIABPAgARAAgJwRllIABPAgAAAA==.Kitsuko:BAABLgAECn80AAMcAAkJFg/FNwC1AQAcAAkJFg/FNwC1AQAdAAkJxRBcJwCYAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ko='Kokeovrdose:BAAALgAECgQJBAABLgAECgYJFAAVAAYWAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuli:BAAALgAECgEJAgAAAA==.Kuraishin:BAAALgAFFAEJAQABLgAFFAYJFAAVAMkWAA==.Kuvare:BAAALgADCgMJAwAAAA==.',
['Kè']='Kèlton:BAAALgAECgUJCgAAAA==.',
La='Lanas:BAEALgAECgkJAwABLgAFFAQJCwAOAO8PAA==.Laocoon:BAAALgAECggJCAABLgAECgkJOQAOANshAA==.Lavashiza:BAAALgAECgYJEQAAAA==.Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAAALgAECgYJEgAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAgAAAA==.Leedaddydk:BAAALgAECgQJCgAAAA==.Leroyjenkins:BAABLgAECn8XAAIlAAcJ8BvoAgBVAgAlAAcJ8BvoAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.',
Li='Lightstorm:BAAALgAECgYJEAAAAA==.Linaria:BAAALgAECgUJCAAAAA==.Linø:BAAALgAECgEJAQAAAA==.Lissara:BAABLgAECn8ZAAIiAAgJExAXLwBeAQAiAAgJExAXLwBeAQAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAACLgAFFH8SAAImAAQJqRzbEwBeAQAmAAQJqRzbEwBeAQAuAAQKfyIAAiYACAm9H2MOAK8CACYACAm9H2MOAK8CAAAA.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockmogged:BAAALgAFFAIJAgAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECgkJHAADADIkAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAFFAQJDgAYAKATAA==.Luminouslexi:BAAALgAECgMJAwAAAA==.',
Ma='Macoub:BAABLgAECn8UAAQbAAgJehXrIQBEAQAbAAYJdhXrIQBEAQAUAAIJBhncuQCTAAAkAAMJbgdFKwBAAAAAAA==.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAABLgAECn8ZAAMZAAgJfQW/FwDQAAAZAAgJUQW/FwDQAAAfAAQJzAMZ7gBsAAAAAA==.Mageslayer:BAABLgAECn8bAAMnAAgJmxMjGwCmAQAnAAgJGBIjGwCmAQABAAMJPRB2FgCvAAAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgATAAAAAA==.Makkideez:BAABLgAECn8UAAInAAkJNxjkDQAyAgAnAAkJNxjkDQAyAgAAAA==.Makkii:BAAALgADCgEJAQABLgAECgkJFAAnADcYAA==.Malanara:BAAALgADCgEJAQABLgAECggJHgAVAE0SAA==.Manabuns:BAABLgAECn8pAAIVAAgJ2xdnVQDEAQAVAAgJ2xdnVQDEAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8kAAIOAAgJ7xVKQgAeAgAOAAgJ7xVKQgAeAgAAAA==.Markruffalo:BAAALgAECgYJCwAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn83AAIRAAkJKRtnEgBNAgARAAkJKRtnEgBNAgAAAA==.',
Mc='Mckay:BAAALgAECggJEwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8mAAIlAAgJRBQNBACtAQAlAAgJRBQNBACtAQAAAA==.Megapunk:BAAALgAECgYJCgAAAA==.Mellmaan:BAAALgAFFAIJAgAAAA==.Melys:BAAALgAECgcJEgAAAA==.Mercenar:BAAALgADCgEJAQAAAA==.Meteorite:BAAALgAECgYJCQAAAA==.Meudayr:BAABLgAECn8jAAIMAAkJASB6AwDZAgAMAAkJASB6AwDZAgAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.Mezagog:BAAALgAECgYJBgAAAA==.',
Mi='Mikehammer:BAAALgADCgcJBwAAAA==.Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAACLgAFFH8MAAIdAAQJwwx3IQD9AAAdAAQJwwx3IQD9AAAuAAQKfx4AAh0ACAltHCISAJICAB0ACAltHCISAJICAAAA.',
Mo='Moistblanket:BAAALgAECgUJBwAAAA==.Mojorisin:BAABLgAECn8jAAICAAkJ6xq5CwBaAgACAAkJ6xq5CwBaAgAAAA==.Moobear:BAAALgAECgYJBgAAAA==.Moonchiken:BAAALgAECgEJCgAAAA==.Moozlock:BAABLgAECn8pAAIfAAkJwBHiRADBAQAfAAkJwBHiRADBAQAAAA==.Moscovio:BAAALgAFFAIJBAABLgAFFAMJBQAOAFITAA==.Mosspaws:BAABLgAECn82AAMLAAkJbiTNBQBOAwALAAkJbiTNBQBOAwAFAAQJZB/GMAA/AQAAAA==.',
Mt='Mtndewyou:BAAALgAECgYJDwAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.Mutterutters:BAAALgADCgMJAwAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.',
Na='Naetara:BAAALgADCgEJAQAAAA==.Narfiy:BAAALgADCgEJAQAAAA==.Narisanna:BAAALgAFFAEJAgAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBgAAAA==.',
Nm='Nme:BAABLgAECn8lAAMVAAkJoBACUQDRAQAVAAkJoBACUQDRAQAlAAYJiw9LCQBWAQAAAA==.',
No='Nocturnos:BAABLgAECn8uAAMfAAkJZR3AFwCJAgAfAAkJZR3AFwCJAgAYAAIJ9yDCJwBkAAAAAA==.Noggin:BAABLgAECn8rAAMNAAkJRyH/BAAcAwANAAkJRyH/BAAcAwAOAAgJ/BCwXQCdAQAAAA==.Nonform:BAABLgAECn89AAQFAAkJgRuvCgCUAgAFAAkJgRuvCgCUAgAKAAEJwRWsPwA/AAALAAEJdAED7AAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECgcJDQATAAAAAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQATAAAAAA==.Novamancer:BAAALgAECgEJAQAAAA==.Noxta:BAAALgAECggJEgAAAA==.',
Nu='Numonixx:BAACLgAFFH8eAAMiAAYJCA0uHgA4AQAiAAYJCA0uHgA4AQAGAAQJ6gejBQD1AAAuAAQKfyoAAwYACQm3GqgJAEUCAAYACAl9G6gJAEUCACIACAlTGfAXAP8BAAAA.Nutlessfred:BAAALgAECgEJAQAAAA==.',
Ny='Nymage:BAABLgAECn9ZAAIVAAkJHBsYJQBxAgAVAAkJHBsYJQBxAgAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogmund:BAAALgAECgYJDwAAAA==.',
Oh='Ohnospiders:BAABLgAECn8vAAMXAAkJgRZaNQAWAgAXAAkJgRZaNQAWAgAIAAQJ4RRXGwDBAAAAAA==.Ohpig:BAAALgAECgMJAwAAAA==.',
Ok='Okaerisan:BAABLgAECn8VAAIQAAgJQRY1FgBWAQAQAAgJQRY1FgBWAQAAAA==.',
Om='Omarcuthlink:BAAALgAECgEJAQABLgAECgkJLQAYAHQVAA==.Omgbbqq:BAAALgAECggJCAABLgAFFAMJBgADAOsWAA==.',
On='Onilecram:BAAALgAECgIJAgAAAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECggJDQAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Ou='Outlast:BAACLgAFFH8QAAIOAAQJHhYuKQBFAQAOAAQJHhYuKQBFAQAuAAQKfy8AAg4ACQm1HbQRAAQDAA4ACQm1HbQRAAQDAAAA.',
Pa='Paants:BAABLgAECn8fAAIoAAgJ2w2/IAASAQAoAAgJ2w2/IAASAQAAAA==.Pacid:BAAALgAECgEJAgAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Pakal:BAAALgADCgYJFAAAAA==.Palebull:BAAALgADCgYJCAAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8WAAIUAAcJ9R8ECABNAgAUAAcJ9R8ECABNAgAuAAQKfzMAAhQACQkEJYQDAD8DABQACQkEJYQDAD8DAAAA.Parmageddon:BAAALgAECgEJAQABLgAFFAQJDgAoAPggAA==.Parmigiano:BAAALgADCgEJAQABLgAFFAQJDgAoAPggAA==.Parmrageiano:BAABLgAFFH8OAAIoAAQJ+CBsCACBAQAoAAQJ+CBsCACBAQAAAA==.Parms:BAABLgAECn8ZAAQCAAgJ+xOkIgB4AQACAAgJ6xGkIgB4AQAEAAYJhQxETQAcAQADAAIJORANowCFAAABLgAFFAQJDgAoAPggAA==.Parmy:BAAALgAECgEJAQAAAA==.',
Pe='Peanought:BAABLgAECn8qAAMIAAkJjxYBBgDJAQAIAAgJsRcBBgDJAQAXAAkJ5A7sVwCqAQAAAA==.Peidro:BAABLgAECn8aAAIOAAcJtA20lAAvAQAOAAcJtA20lAAvAQAAAA==.Pentacles:BAABLgAECn8tAAIMAAkJsCDfBQCIAgAMAAkJsCDfBQCIAgAAAA==.',
Pi='Pijak:BAAALgAECgYJEgAAAA==.Pinkpaw:BAABLgAECn8hAAMMAAkJFh/lAwDMAgAMAAkJFh/lAwDMAgALAAUJthorRABsAQAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8JAAMmAAMJ3iTvCABGAQAmAAMJ3iTvCABGAQAPAAEJlCM5LwBoAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCQAmAN4kAA==.Postscalone:BAAALgAECgYJBwAAAA==.Potatoes:BAABLgAECn8VAAMZAAgJBgiWHABpAQAZAAgJBgiWHABpAQAfAAIJCQJIFAE6AAAAAA==.',
Pr='Pruflas:BAABLgAECn8aAAIXAAgJZAuifQBTAQAXAAgJZAuifQBTAQAAAA==.',
Ps='Psycodk:BAACLgAFFH8HAAIXAAQJLhslNgBnAQAXAAQJLhslNgBnAQAuAAQKfxYAAhcACAmYGJ1hAJIBABcACAmYGJ1hAJIBAAAA.',
Pu='Pumpin:BAABLgAECn8XAAIPAAUJFCQnJgBsAQAPAAUJFCQnJgBsAQAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
Qk='Qkn:BAAALgAECgUJEQAAAA==.',
Qu='Quickswipe:BAAALgAFFAIJBAABLgAFFAYJMgAZAPsiAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgYJCwABLgAECgcJCAATAAAAAA==.Ralee:BAAALgADCgcJCQAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Rastabution:BAAALgAECgkJAQAAAA==.Raynne:BAAALgAECgIJAgAAAA==.Rayzee:BAAALgADCgUJBQAAAA==.',
Re='Reaperjoe:BAAALgAFFAEJAgAAAA==.Rehab:BAABLgAECn8VAAIOAAkJWxyuLwBkAgAOAAkJWxyuLwBkAgAAAA==.Rehna:BAAALgAECgYJBgABLgAFFAQJEgAHAM0RAA==.Rek:BAAALgAECgEJAQABLgAECgkJIwAMAAEgAA==.Rektributio:BAACLgAFFH8eAAIOAAgJCyC3AQC4AgAOAAgJCyC3AQC4AgAuAAQKfzcAAg4ACQkgJQoFAD4DAA4ACQkgJQoFAD4DAAAA.Revalation:BAABLgAECn8nAAILAAkJUh+4EwCbAgALAAkJUh+4EwCbAgAAAA==.Revenancer:BAAALgAECgEJAQAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgATAAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Ribeyejoe:BAAALgADCgEJAQAAAA==.Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAABLgAECn8kAAMoAAgJoBg4EADMAQAoAAgJCRc4EADMAQARAAUJshEaaQAQAQAAAA==.Roadtrip:BAAALgAECgMJBAAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJBAAAAA==.Rottingslow:BAABLgAFFH8IAAIHAAMJ9wB4JAB0AAAHAAMJ9wB4JAB0AAABLgAFFAgJHAAJAEkgAA==.',
Sa='Sanford:BAAALgAECgUJBQAAAA==.Saragos:BAAALgADCgcJBgABLgAFFAYJFAAVAMkWAA==.Saucerdote:BAABLgAECn8eAAMgAAkJmBUrHADLAQAgAAcJGxcrHADLAQAaAAkJFAm2KwBXAQAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAYJFAAVAMkWAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAABLgAECn8qAAIUAAkJAR+EDgC8AgAUAAkJAR+EDgC8AgAAAA==.Selkie:BAABLgAECn8lAAISAAkJvg8QDADVAQASAAkJvg8QDADVAQAAAA==.Seragosa:BAAALgAFFAEJAQABLgAFFAYJFAAVAMkWAA==.',
Sh='Shakakhan:BAAALgAECgYJCgABLgAECgYJHgAOAGccAA==.Shambeau:BAAALgADCgQJBAAAAA==.Shamrun:BAAALgADCgQJBQAAAA==.Shamshielder:BAECLgAFFH8FAAMIAAQJzg5yDAAMAQAIAAQJcghyDAAMAQAJAAEJhiNQLgBWAAAuAAQKfy0ABAkACQmZI4UEANoCAAkACQmZI4UEANoCAAgABgmlG3QLAJUBABcAAQm5Ca1iASkAAAAA.Sharick:BAAALgAECgQJBQAAAA==.Shawlee:BAABLgAECn8tAAMcAAgJzBCSUgBKAQAcAAgJzBCSUgBKAQAdAAgJOwqoSwDqAAAAAA==.Sheezie:BAACLgAFFH8FAAIcAAMJExqNLgAFAQAcAAMJExqNLgAFAQAuAAQKfzYAAhwACQlgHoEHACQDABwACQlgHoEHACQDAAAA.Shellter:BAAALgAECgEJAgABLgAECgkJIgAWAG0gAA==.Shellwit:BAAALgAECgMJBgABLgAECgkJIgAWAG0gAA==.Sheph:BAAALgAECgcJCgAAAA==.Shetmage:BAACLgAFFH8VAAIVAAYJag2RNgBnAQAVAAYJag2RNgBnAQAuAAQKfykAAhUACQnDIBMeAJMCABUACQnDIBMeAJMCAAAA.Shettdh:BAAALgAECgEJAQAAAA==.Shettrah:BAABLgAECn8UAAIFAAYJ+hrAJgB+AQAFAAYJ+hrAJgB+AQABLgAFFAYJFQAVAGoNAA==.Shienro:BAAALgAECgQJBAABLgAECgQJCQATAAAAAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAABLgAECn8cAAIOAAgJwRHMdgBmAQAOAAgJwRHMdgBmAQAAAA==.Shuck:BAAALgAECgQJBAABLgAFFAMJBwARADEbAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Sibyx:BAAALgAECgUJCgABLgAECgYJHgAOAGccAA==.Siickboy:BAAALgAECgQJCQAAAA==.Sijious:BAAALgAECgEJAgAAAA==.Silveah:BAAALgADCgEJAQAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.',
Sk='Skora:BAAALgADCgIJAgABLgAECggJJAAOAO8VAA==.Skyland:BAAALgADCgcJDQAAAA==.Skyli:BAAALgAECgUJCAABLgAECgkJIQAcAPIeAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAACLgAFFH8SAAINAAQJNhoTHQAeAQANAAQJNhoTHQAeAQAuAAQKfyYAAg0ACAlcILwIAOMCAA0ACAlcILwIAOMCAAAA.Sorrie:BAAALgAECgEJAQAAAA==.Sortiarius:BAAALgADCgkJCQAAAA==.',
Sp='Spud:BAAALgADCgcJBwABLgAECgUJEQATAAAAAA==.Spyroh:BAABLgAECn8bAAQGAAYJ6BLuGQBlAQAGAAYJcBDuGQBlAQAiAAUJGBJOQgD/AAAhAAEJ2wA4TwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAQJEgAHAM0RAA==.',
St='Stankydk:BAACLgAFFH8QAAMXAAYJ8hYMLQB/AQAXAAUJ8hYMLQB/AQAJAAEJAACQVwAAAAAuAAQKfzIAAhcACQk+JTkEAFQDABcACQk+JTkEAFQDAAAA.Stankyeyes:BAAALgAECgYJBgAAAA==.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Steakhead:BAABLgAECn8jAAIFAAYJlwm7SADMAAAFAAYJlwm7SADMAAAAAA==.Stinkbombs:BAABLgAFFH8KAAIVAAUJ4AOeaADyAAAVAAUJ4AOeaADyAAAAAA==.Stinkerz:BAAALgAECgIJAgABLgAECgkJIgAWAG0gAA==.Stonegut:BAAALgAECgUJBQAAAA==.Stunanddone:BAAALgAECgQJCAAAAA==.',
Su='Subrogue:BAABLgAFFH8FAAIjAAIJlhmNJQCfAAAjAAIJlhmNJQCfAAABLgAFFAMJBQAeABkGAA==.Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJEAAAAA==.Supreme:BAACLgAFFH8IAAIUAAMJXhq0TQDiAAAUAAMJXhq0TQDiAAAuAAQKfxkAAhQACAl4I24YAMMCABQACAl4I24YAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAMJAwABLgAFFAQJDgAnAKIcAA==.Swayaim:BAAALgAFFAQJBAAAAA==.Sweatypits:BAAALgADCggJCAABLgAFFAMJBQAcABMaAA==.Swordsaint:BAAALgAECgEJAQAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAYJDgANAO8RAA==.Sylphrena:BAACLgAFFH8SAAIHAAQJ9hQQEwAMAQAHAAQJ9hQQEwAMAQAuAAQKfycAAgcACAkqIIgIAMMCAAcACAkqIIgIAMMCAAAA.',
['Sí']='Sínful:BAABLgAECn8qAAIEAAkJxB/QAwBzAgAEAAkJxB/QAwBzAgAAAA==.',
Ta='Tacow:BAAALgAECgcJCQAAAA==.Tahwe:BAAALgADCgcJBwAAAA==.Talethen:BAABLgAECn8aAAMiAAgJjxnAKAB3AQAiAAgJ1RfAKAB3AQAGAAUJMxgpIAAtAQAAAA==.Talgrin:BAAALgAECgYJBgAAAA==.Talla:BAABLgAECn8hAAIcAAkJ8h6bCwDpAgAcAAkJ8h6bCwDpAgAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgADCgkJIQAAAA==.Tellus:BAAALgADCgcJCwAAAA==.Tempesttempi:BAAALgADCgcJBwAAAA==.Tewshort:BAAALgAECgQJCAABLgAFFAQJEAAOAB4WAA==.',
Th='Thatbox:BAAALgAECgQJBAAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgQJDAAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAABLgAECn8UAAMPAAgJBAW8UgCnAAAmAAcJQQRZWQDeAAAPAAcJQgS8UgCnAAAAAA==.Thorfyna:BAABLgAECn8fAAIkAAgJLhTMCgCXAQAkAAgJLhTMCgCXAQAAAA==.Threzk:BAABLgAECn8eAAIZAAkJew6vDABWAQAZAAkJew6vDABWAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8MAAIUAAUJZBMNJQBpAQAUAAUJZBMNJQBpAQAuAAQKfy8AAhQACQmGIkYJAPACABQACQmGIkYJAPACAAAA.Tontiamat:BAABLgAECn86AAMiAAkJXRgiFQAZAgAiAAkJXRgiFQAZAgAGAAYJawo5IAAsAQAAAA==.Tontier:BAABLgAECn8YAAQLAAYJlw8haQDnAAALAAUJFg4haQDnAAAKAAUJNggkKQCiAAAMAAQJSg5CPwB+AAABLgAECgkJOgAiAF0YAA==.Totembeans:BAAALgAECgQJCwAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAACLgAFFH8OAAINAAYJ7xFUDADMAQANAAYJ7xFUDADMAQAuAAQKfxwABA0ACQlOH98KAMkCAA0ACAnDHt8KAMkCAA4ABwksDjq3ABcBABAAAgmgE1FFADoAAAAA.Trashfire:BAACLgAFFH8KAAMHAAQJIA6pEwAEAQAHAAQJIA6pEwAEAQAgAAIJwgF2FgB7AAAuAAQKfx0ABAcACAkXHSYQAGUCAAcACAkXHSYQAGUCABoABQknFXw2ADkBACAAAwluEWhAAK0AAAEuAAUUBgkOAA0A7xEA.Treeple:BAABLgAECn8fAAMLAAgJshQDSQBYAQALAAcJGRMDSQBYAQAFAAQJHRBiRQDZAAAAAA==.Treily:BAAALgAECgYJDwAAAA==.Tresleches:BAABLgAECn8qAAIOAAgJ1BEHcQByAQAOAAgJ1BEHcQByAQAAAA==.Tricket:BAABLgAECn9MAAMjAAkJgR/cAwDSAgAjAAkJQR/cAwDSAgARAAYJKBluTAD+AAAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAZAAYIAQ==.Truestorm:BAABLgAECn8oAAIOAAkJzgtvcABzAQAOAAkJzgtvcABzAQAAAA==.Truheals:BAAALgAECgYJCgAAAA==.',
Tu='Tuchi:BAACLgAFFH8VAAIVAAUJkByVHgBQAQAVAAUJkByVHgBQAQAuAAQKfyYAAyUABwm9I9QCAP8BABUABwliIrkyAKgCACUABgnQItQCAP8BAAAA.Tumblestone:BAAALgAECgEJAQAAAA==.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAcJFgAUAPUfAA==.',
['Tà']='Tàcobelle:BAAALgAFFAIJAgABLgAECggJKQAVANsXAA==.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgATAAAAAA==.Valhalla:BAAALgAECgYJBgAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIcAAMJriK0LgAEAQAcAAMJriK0LgAEAQAuAAQKfzEAAxwACQllGz8SAIQCABwACQllGz8SAIQCAB0ABgkTGrMwAGIBAAAA.Varanis:BAACLgAFFH8JAAIDAAMJnxZuDAD/AAADAAMJnxZuDAD/AAAuAAQKfxkAAgMACQlkIWMLAOgCAAMACQlkIWMLAOgCAAAA.',
Ve='Vegh:BAACLgAFFH8HAAIkAAMJYBiyBgDKAAAkAAMJYBiyBgDKAAAuAAQKf04AAiQACQnzH8ICALICACQACQnzH8ICALICAAAA.Vem:BAABLgAECn8uAAIiAAkJsR1RDgBkAgAiAAkJsR1RDgBkAgAAAA==.Veriale:BAAALgAECgUJCgAAAA==.Verra:BAABLgAECn81AAIOAAgJzRseMgAfAgAOAAgJzRseMgAfAgAAAA==.',
Vi='Vitriol:BAABLgAECn8gAAIRAAcJZxhALACOAQARAAcJZxhALACOAQAAAA==.',
Vo='Voidbeaver:BAAALgAECgcJCwAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAACLgAFFH8OAAMYAAQJoBP4AwA1AQAYAAQJoBP4AwA1AQAZAAEJYQc2JABAAAAuAAQKfx8AAhgACQl2IqsBAMoCABgACQl2IqsBAMoCAAAA.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgYJDwATAAAAAA==.Vyrros:BAAALgADCgUJBQAAAA==.',
Wa='Walji:BAABLgAECn8eAAMcAAgJyhtyFwBaAgAcAAgJyhtyFwBaAgAdAAEJWwvgmgAqAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgAECgIJAwAAAA==.Wandy:BAABLgAECn8rAAIfAAgJHxWaSAC1AQAfAAgJHxWaSAC1AQAAAA==.Wangstah:BAABLgAECn8cAAIDAAkJMiSRCwDkAgADAAkJMiSRCwDkAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAIRAAYJNhQUSgB8AQARAAYJNhQUSgB8AQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJDgAAAA==.Wawatesi:BAAALgAECgMJAwAAAA==.Waytogoteam:BAACLgAFFH8GAAIDAAMJ6xYPSADzAAADAAMJ6xYPSADzAAAuAAQKfy8AAgMACQnaI+MJAPQCAAMACQnaI+MJAPQCAAAA.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8UAAMVAAYJyRbRKQCTAQAVAAYJyRbRKQCTAQAWAAIJBw4tAwCJAAAuAAQKfzMABBUACQnEJMIKAA8DABUACQk3JMIKAA8DABYABgm+I3wDANkBACUAAQmPIMgWAGQAAAAA.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgQJBAAAAA==.',
Wo='Woodyy:BAABLgAECn8ZAAIXAAgJSAbqkwAqAQAXAAgJSAbqkwAqAQAAAA==.Woog:BAAALgAECgYJDwAAAA==.Wox:BAAALgAECggJDQAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wu='Wujustyle:BAAALgAECgcJBwAAAA==.Wulfgar:BAAALgAECgcJCQAAAA==.',
Wy='Wyldspirit:BAABLgAECn8ZAAIDAAcJegylbABQAQADAAcJegylbABQAQAAAA==.Wyreless:BAAALgADCgYJBgABLgAECggJMwAKAOoWAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xr='Xrind:BAAALgADCgEJAQAAAA==.',
Ya='Yaass:BAAALgAECgMJAwAAAA==.',
Ye='Yem:BAACLgAFFH8yAAQZAAYJ+yK7AQDFAQAZAAYJlh67AQDFAQAfAAUJeiDPKwBrAQAYAAIJYSIxFgBXAAAuAAQKfzYAAxkACQmiIzkGAGwCABkABgncIzkGAGwCAB8ABgliI1VJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAIMAAcJvxm2CAAfAgAMAAcJvxm2CAAfAgABLgAFFAUJDwAOAFEdAA==.Yoverre:BAAALgAECgMJAwAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAATAAAAAA==.Zanzabar:BAABLgAECn8XAAIOAAkJvBnlOQADAgAOAAkJvBnlOQADAgAAAA==.Zaraelitha:BAAALgAECgYJBwAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgYJCQAAAA==.Zeodrik:BAABLgAECn8cAAIRAAcJYRmxNQDSAQARAAcJYRmxNQDSAQAAAA==.',
Zh='Zhenya:BAACLgAFFH8SAAIVAAQJ+hLIUAAwAQAVAAQJ+hLIUAAwAQAuAAQKfyYAAxUACAnXGndeAB8CABUACAnXGndeAB8CACUABAkvD+gOANUAAAAA.',
Zi='Zidguard:BAAALgAECgYJBwAAAA==.Zigzauer:BAAALgAECgQJBAAAAA==.Ziroken:BAAALgADCgUJBQAAAA==.',
Zo='Zombeaver:BAAALgAECgIJAgAAAA==.',
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
