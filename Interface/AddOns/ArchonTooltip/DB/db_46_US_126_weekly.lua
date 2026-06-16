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

local lookup = {'DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','Hunter-Survival','DemonHunter-Havoc','Warrior-Fury','Evoker-Devastation','DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','DeathKnight-Frost','Rogue-Subtlety','Druid-Feral','Rogue-Assassination','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Aberration:BAAALgAECgEJAgAAAA==.Abraxidormu:BAAALgAECgYJBgABLgAECgkJMAABAPgQAA==.',
Ad='Adorraa:BAAALgAFFAIJAgAAAA==.Adoryn:BAAALgADCgYJCQAAAA==.Adowyrm:BAACLgAFFH8oAAMCAAgJlRdqCQANAgACAAcJYRdqCQANAgADAAMJYQ3VOgDZAAAuAAQKfyEAAwIACQm1IUcCAFEDAAIACQm1IUcCAFEDAAMABgnLHfscAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.Adrielle:BAAALgADCgkJDAAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECgkJHQAEAIgcAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAFFAQJBAAAAA==.',
Ai='Airali:BAACLgAFFH8KAAIFAAUJ+gWrXQDtAAAFAAUJ+gWrXQDtAAAuAAQKfxcAAwUACQn+E2tkALgBAAUACQn+E2tkALgBAAYAAwmJCNM3AGIAAAAA.Airedale:BAABLgAECn8tAAIHAAgJThekOgDwAQAHAAgJThekOgDwAQAAAA==.',
Ak='Akairo:BAABLgAECn8xAAMIAAkJACSCAgBBAwAIAAkJACSCAgBBAwAJAAgJrBG2KgB7AQAAAA==.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgAECgYJBgABLgAFFAUJCQADAMQQAA==.Alderbaran:BAAALgADCgUJBQAAAA==.Alexanderxl:BAABLgAECn8WAAMGAAYJAB1gFwBfAQAGAAYJAB1gFwBfAQAFAAUJWBW9wgACAQABLgAECggJAwAKAAAAAA==.Aleybobwa:BAABLgAECn8fAAMLAAkJjhIIKgC8AQALAAkJjhIIKgC8AQAFAAEJYwiPUgErAAAAAA==.Alody:BAAALgADCgMJAwABLgAECgEJAgAKAAAAAA==.Alyméré:BAAALgAECgYJBwAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAABLgAECn8nAAILAAkJmxvmDADAAgALAAkJmxvmDADAAgAAAA==.Amulius:BAACLgAFFH8FAAIFAAMJtSUsNQA+AQAFAAMJtSUsNQA+AQAuAAQKfzYAAgUACQnyJVYEAFYDAAUACQnyJVYEAFYDAAAA.',
An='Anderdingus:BAAALgADCgYJCgAAAA==.Andormath:BAAALgAECgQJBgAAAA==.Andramedae:BAABLgAECn83AAMMAAkJKBu/EQC/AgAMAAkJKBu/EQC/AgANAAYJCw0OSADnAAAAAA==.Angerissues:BAAALgADCgkJCQAAAA==.Angyavocado:BAAALgAECgUJBQAAAA==.Anoki:BAABLgAECn9DAAMOAAkJJBvHFAChAgAOAAkJJBvHFAChAgAPAAEJgQvqrwAnAAAAAA==.',
Ao='Aolus:BAACLgAFFH8RAAINAAQJuxj0IAASAQANAAQJuxj0IAASAQAuAAQKfxsAAg0ACQkVHDETAHsCAA0ACQkVHDETAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgAECgEJAQAAAA==.Aprollon:BAAALgAECgEJAQAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJBAAKAAAAAA==.Arcaina:BAABLgAECn8jAAIQAAkJLglieACFAQAQAAkJLglieACFAQAAAA==.Ares:BAAALgADCgkJEAABLgAECgkJOQARAPAXAA==.Arez:BAABLgAECn85AAIRAAkJ8BeuKAA3AgARAAkJ8BeuKAA3AgAAAA==.Arilass:BAAALgADCgIJBAAAAA==.Armis:BAAALgADCgEJAQABLgAECgkJQwASAOMlAA==.Artèmís:BAABLgAECn8nAAITAAkJDSU+AwAFAwATAAkJDSU+AwAFAwAAAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Ashtongue:BAAALgAECgQJBAAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athinea:BAAALgAECgYJCgAAAA==.',
Au='Aura:BAAALgAFFAEJAQAAAA==.',
Ay='Ayahuasca:BAAALgADCgIJAgAAAA==.',
Az='Azaekho:BAABLgAECn8kAAIOAAkJcxQIKgDmAQAOAAkJcxQIKgDmAQAAAA==.Azalet:BAAALgAFFAIJAgAAAA==.',
Ba='Baalzak:BAAALgADCgYJBQAAAA==.Backfliphoe:BAABLgAECn8VAAIUAAcJRhIdIQBqAQAUAAcJRhIdIQBqAQAAAA==.Badoosh:BAABLgAECn8oAAIVAAgJcB2aGACHAgAVAAgJcB2aGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Bajablaster:BAABLgAECn9BAAQWAAkJIyOmAAA7AwAWAAkJIyOmAAA7AwADAAMJ5BD7TACdAAACAAEJMAtePQArAAAAAA==.Baliw:BAAALgADCgkJDQAAAA==.Balto:BAAALgADCgMJAwAAAA==.Barbearic:BAAALgAECgEJAQAAAA==.',
Bb='Bbl:BAECLgAFFH8aAAIPAAYJ1BjqEwB1AQAPAAYJ1BjqEwB1AQAuAAQKfyUAAg8ACQnWIFgKAPACAA8ACQnWIFgKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8PAAIQAAQJ2xFGKwAIAQAQAAQJ2xFGKwAIAQAuAAQKfyMAAhAACQnDGZo7AIgCABAACQnDGZo7AIgCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAACLgAFFH8GAAIFAAIJJQ0ZjwCMAAAFAAIJJQ0ZjwCMAAAuAAQKfxgAAgUACQkfEWNWAMUBAAUACQkfEWNWAMUBAAAA.',
Bh='Bhain:BAAALgADCgcJDQABLgAFFAUJEAAFAHweAA==.',
Bi='Bieorne:BAABLgAECn87AAIXAAkJrSGeDgD1AgAXAAkJrSGeDgD1AgAAAA==.Bigpan:BAAALgAECgEJAQABLgAECggJJAAYAJsRAA==.',
Bl='Blastbane:BAACLgAFFH8LAAIRAAQJXQupYAABAQARAAQJXQupYAABAQAuAAQKfxQAAhEACQnuFJQ1AAICABEACQnuFJQ1AAICAAEuAAUUBQkNABkAiQkA.Bloodwrath:BAAALgAECgIJBAAAAA==.Blueveins:BAABLgAECn8VAAIQAAcJ/gX80wDoAAAQAAcJ/gX80wDoAAAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAACLgAFFH8FAAIRAAIJ5R7MkQCYAAARAAIJ5R7MkQCYAAAuAAQKfxgAAxEACQnvHP4PAPoCABEACQnvHP4PAPoCABoAAQkAANpOAAAAAAEuAAUUAwkIAAsAaxsA.Boondocks:BAABLgAECn85AAMbAAkJqB5oDgBwAQARAAUJZBrgXwCAAQAbAAUJ8CFoDgBwAQAAAA==.',
Br='Braca:BAAALgAECgEJAQAAAA==.Braelek:BAAALgADCgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAABLgAECn8ZAAIYAAkJLQ+IIwCMAQAYAAkJLQ+IIwCMAQABLgAECgkJKgAcAJ4bAA==.Brielle:BAABLgAECn8tAAIHAAkJuBfZKgAuAgAHAAkJuBfZKgAuAgAAAA==.Brokenbranch:BAABLgAECn8XAAIMAAcJsggnawDwAAAMAAcJsggnawDwAAAAAA==.Brudene:BAABLgAECn8UAAIVAAcJFRF2VABZAQAVAAcJFRF2VABZAQAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Bubbletruble:BAAALgAECgYJBgAAAA==.Buddylock:BAABLgAECn8iAAIRAAkJmgljeQBGAQARAAkJmgljeQBGAQAAAA==.Bulltaura:BAAALgAECgcJBwAAAA==.Bullymaguire:BAACLgAFFH8RAAIdAAcJRhuuBQC4AQAdAAcJRhuuBQC4AQAuAAQKfx0AAh0ACAk5I0EFADEDAB0ACAk5I0EFADEDAAAA.Burakkuburu:BAABLgAECn88AAMeAAkJHR/TCAAKAwAeAAkJHR/TCAAKAwAdAAYJMRmBMABCAQABLgAECgkJJwATAA0lAA==.',
Ca='Caboozles:BAABLgAECn87AAIHAAkJCRZaOgDxAQAHAAkJCRZaOgDxAQAAAA==.Caliopia:BAABLgAECn8xAAMPAAkJvBRtHwDkAQAPAAkJvBRtHwDkAQAOAAYJYQrAbwAHAQAAAA==.Caliper:BAAALgAECgEJAQAAAA==.Canrif:BAAALgAECgYJBgAAAA==.Caplyta:BAAALgAECgUJDgABLgAFFAUJEgAJACscAA==.Captnhuntcat:BAAALgAECggJEwAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.Cathode:BAAALgAFFAEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8vAAIVAAkJNxdaEwBWAgAVAAkJNxdaEwBWAgAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAABLgAECn8bAAMZAAkJaR2cEAABAgAZAAkJaR2cEAABAgAXAAQJJA+XxgDyAAAAAA==.Chemistree:BAABLgAECn81AAIMAAkJNRSSJgAYAgAMAAkJNRSSJgAYAgAAAA==.Chillout:BAABLgAECn8nAAIQAAkJvw0BYgC4AQAQAAkJvw0BYgC4AQAAAA==.Chillums:BAABLgAECn8cAAIRAAcJ4iP7GgCzAgARAAcJ4iP7GgCzAgAAAA==.Chipcle:BAAALgAECgQJBwAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Ci='Cillah:BAAALgAECgEJAgABLgAECgkJNAAVAPwfAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgADCgkJFAAKAAAAAA==.',
Co='Codeblue:BAAALgADCgkJEQAAAA==.Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8dAAILAAkJYg7yKADCAQALAAkJYg7yKADCAQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Cy='Cy:BAABLgAECn8WAAIeAAgJ1REdMQCuAQAeAAgJ1REdMQCuAQAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAABLgAECggJFQAXAB4bAA==.Daeleiel:BAAALgAECgEJAQAAAA==.Damrek:BAAALgAECgEJAQAAAA==.Darkenergy:BAABLgAECn85AAMUAAkJpiTMAQBWAwAUAAkJpiTMAQBWAwABAAkJuh/tEAC4AgAAAA==.Darà:BAAALgAECgQJBwABLgAECgkJNAANAOUPAA==.Dashyll:BAAALgAECgMJBAAAAA==.Davyfknjones:BAABLgAECn8aAAIHAAgJTxjfNgD+AQAHAAgJTxjfNgD+AQAAAA==.Daynia:BAAALgAECgYJEQAAAA==.',
De='Deadbolt:BAAALgAECgYJBgAAAA==.Deadlegslul:BAABLgAECn8hAAIHAAgJRx+2IQBaAgAHAAgJRx+2IQBaAgAAAA==.Deadlegsmd:BAAALgAECgQJCAAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadtree:BAAALgAECgEJAQAAAA==.Deadzepplin:BAAALgAECgUJBwAAAA==.Deathfish:BAAALgAECgEJAQAAAA==.Deathmono:BAAALgAECgYJDQAAAA==.Deathshark:BAACLgAFFH8YAAIZAAUJrhzJFABBAQAZAAUJrhzJFABBAQAuAAQKfzEAAhkACQkLH7oNAC0CABkACQkLH7oNAC0CAAAA.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAABLgAECn8iAAIQAAcJyAwmnwA5AQAQAAcJyAwmnwA5AQABLgAECggJPwAOAI4UAA==.Demeter:BAABLgAECn9EAAIGAAkJvBS4DQDlAQAGAAkJvBS4DQDlAQAAAA==.Demiurge:BAAALgAECgIJAgAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denalli:BAAALgAECgQJBAAAAA==.Denarien:BAAALgAECgkJDQAAAA==.Derpygos:BAAALgADCgcJBwABLgAECgkJKgAcAJ4bAA==.Detroitt:BAAALgADCgIJAgAAAA==.Devouress:BAACLgAFFH8OAAIBAAQJqA61TwD4AAABAAQJqA61TwD4AAAuAAQKfxkAAgEACAkOGNc6ANgBAAEACAkOGNc6ANgBAAAA.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dillkiller:BAABLgAECn8XAAIfAAcJGQn9IQAuAQAfAAcJGQn9IQAuAQAAAA==.Dirgen:BAABLgAECn80AAMVAAkJLRo1DwCAAgAVAAkJLRo1DwCAAgAfAAEJzhwLSQBMAAAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dogmaww:BAAALgADCgEJAQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAFFAUJEwAYAPMJAA==.Double:BAAALgAECgQJBAAAAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAABLgAECn8aAAIDAAgJYhovHADzAQADAAgJYhovHADzAQAAAA==.Dragginballs:BAAALgAECgIJBAABLgAFFAIJAgAKAAAAAA==.Draggnar:BAABLgAECn8XAAIaAAcJeAjyGQDRAAAaAAcJeAjyGQDRAAAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAABLgAECn8mAAMTAAkJgA8sFAAEAgATAAkJeA8sFAAEAgAgAAcJeAbWHwCtAAAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJDwAPAEwhAA==.',
Du='Dumplingsxo:BAABLgAECn8kAAMNAAkJnBhBGQA9AgANAAgJsBlBGQA9AgAMAAcJ4BiYPQCtAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn9DAAMSAAkJ4yVhAABiAwASAAkJ4yVhAABiAwAUAAYJgx3SGQCtAQAAAA==.',
Eb='Ebojager:BAABLgAECn9AAAIBAAkJVhoEHABpAgABAAkJVhoEHABpAgAAAA==.',
Eh='Ehko:BAAALgAECgYJCwABLgAECgkJJwATAA0lAA==.',
Ei='Eibon:BAACLgAFFH8eAAIXAAgJaB3MCQCHAgAXAAgJaB3MCQCHAgAuAAQKfx4AAhcACQnNIakUAAADABcACQnNIakUAAADAAAA.Einfreren:BAAALgAECgQJBAAAAA==.',
El='Elliiria:BAAALgAECgQJBgAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgkJEwAAAA==.Elvispriesty:BAABLgAECn8eAAIhAAcJQxVSIADJAQAhAAcJQxVSIADJAQAAAA==.Elwarrioro:BAAALgAECgYJDwAAAA==.',
Em='Emmpunity:BAAALgAECgQJBAAAAA==.Emmune:BAABLgAECn8oAAIiAAkJzxR2CQAiAgAiAAkJzxR2CQAiAgAAAA==.',
En='Enobia:BAABLgAECn8rAAMaAAkJ7hjwAwBGAgAaAAkJ7hjwAwBGAgARAAUJFgbDxADQAAAAAA==.Entrapment:BAAALgADCgYJBgABLgADCgkJFAAKAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Er='Eriaeda:BAAALgAECgUJDQAAAA==.',
Es='Esen:BAAALgAECgQJBQABLgAECgkJOQARAPAXAA==.Eskath:BAABLgAECn8oAAIRAAkJUiB7DwDPAgARAAkJUiB7DwDPAgABLgAECgkJKgAcAJ4bAA==.Essential:BAACLgAFFH8IAAIFAAQJNgvGVwD6AAAFAAQJNgvGVwD6AAAuAAQKfx0AAgUACAnpEnF4AHsBAAUACAnpEnF4AHsBAAAA.',
Et='Eternalpain:BAAALgAECgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8hAAIdAAYJfxNJPAALAQAdAAYJfxNJPAALAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgQJCQAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Felpickles:BAAALgAECgMJAwABLgADCgkJFAAKAAAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgAECgEJAQABLgAECggJJAAYAJsRAA==.Ferrara:BAACLgAFFH8nAAQTAAgJfCNkAgARAgATAAYJxiNkAgARAgAgAAcJkx71CwBdAQAHAAEJtx+1HwBiAAAuAAQKfyAABCAACQnRIykGADoDACAACQmLIykGADoDAAcAAQn1I6ywAGIAABMAAQk6HgIsAEYAAAAA.',
Fi='Filthi:BAABLgAECn8XAAIPAAYJRiFuIAANAgAPAAYJRiFuIAANAgAAAA==.Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgUJBwAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgkJRAANAGskAA==.Fisted:BAAALgAFFAEJAQABLgAFFAMJCAALAGsbAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8cAAMIAAgJWCCRAAABAwAIAAgJWCCRAAABAwAJAAEJUg4ZOQBDAAAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.Fluorita:BAAALgAECgEJAQAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Friedá:BAAALgAECgIJAwABLgAECgYJEgAKAAAAAA==.Frostednip:BAACLgAFFH8RAAMXAAUJJhqcWwA5AQAXAAUJ3RmcWwA5AQAjAAIJoRKLHQCNAAAuAAQKfyQAAyMACQnaIL4JAOUBABcACQm/IH09AAkCACMABwmhG74JAOUBAAAA.',
Ga='Gabaghoul:BAAALgAECgQJBAAAAA==.Gabiru:BAACLgAFFH8HAAQDAAMJ9gSvSwCaAAADAAMJ9gSvSwCaAAACAAMJvQfJIgCEAAAWAAEJlwEsDABCAAAuAAQKfxUAAwIACQlTE2YSABkCAAIACQlTE2YSABkCAAMAAQm0CZphADUAAAAA.Gadreeste:BAAALgAECggJCQAAAA==.Galnarn:BAACLgAFFH8oAAIYAAcJyyCLBwANAgAYAAcJyyCLBwANAgAuAAQKfyEAAhgACQlkHfgNALQCABgACQlkHfgNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Gank:BAAALgAFFAEJAQABLgAFFAcJHgABALQZAA==.Garious:BAAALgAECgcJBwABLgAFFAUJEgAXAKMiAA==.Garjingo:BAAALgAECgUJBgABLgAECgkJQQAWACMjAA==.Garlicbae:BAABLgAECn8UAAIcAAcJgAk5OwCzAAAcAAcJgAk5OwCzAAAAAA==.Garwulf:BAABLgAECn8ZAAITAAkJUQaUIgCJAQATAAkJUQaUIgCJAQAAAA==.',
Ge='Gefaustet:BAABLgAECn86AAQfAAkJchpSCwA1AgAfAAkJchpSCwA1AgAVAAEJ8gZ6qgAsAAAEAAEJEAmHfgApAAAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECgcJCQAAAA==.Glyd:BAAALgAECgUJBQABLgAECggJPwAOAI4UAA==.',
Go='Goatcheesè:BAAALgAECgIJBAAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAFFAEJAQAAAA==.Gorbachev:BAAALgAECgYJCAAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAABLgAECn8cAAMYAAkJ+ApBKABtAQAYAAkJ+ApBKABtAQAdAAMJHgJfpwAoAAAAAA==.Grayes:BAABLgAECn8hAAMcAAYJMQggQwCUAAAcAAYJMQggQwCUAAAMAAIJLwKK8gAdAAABLgAECgkJHAAYAPgKAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hail:BAAALgADCgUJBQABLgAFFAUJCQADAMQQAA==.Hallowshade:BAABLgAECn8XAAIkAAcJFhnlJQDKAQAkAAcJFhnlJQDKAQAAAA==.Hardran:BAABLgAECn8eAAIFAAgJ8AyvgwBlAQAFAAgJ8AyvgwBlAQAAAA==.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgAECgQJDAAAAA==.Hatreddyes:BAAALgAECgMJAwABLgAECggJCQAKAAAAAA==.Hatredyes:BAAALgAECggJCQAAAA==.Hattredyess:BAAALgAECgUJBQABLgAECggJCQAKAAAAAA==.',
He='Heatedsoul:BAAALgAECgEJAQAAAA==.Helare:BAABLgAECn8XAAINAAkJ2xjJEQBIAgANAAkJ2xjJEQBIAgAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAABLgAECn8nAAIlAAkJrQ1IFAB3AQAlAAkJrQ1IFAB3AQAAAA==.',
Hi='Hinatsuru:BAAALgAECgQJBAAAAA==.',
Ho='Holyzap:BAAALgAECgIJAgABLgAECgkJJQAQABEhAA==.Horsegirl:BAAALgAECgEJAgAAAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Huffmetoes:BAEALgADCgcJDQABLgAECgkJPwAIAIMZAA==.Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECggJCQAAAA==.Huulrokk:BAAALgADCgkJDAABLgAECgkJFQAOAHoVAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.Hyperreal:BAAALgAECgEJAQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgkJJwALAJsbAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwAKAAAAAA==.Idlewild:BAEALgAECgEJAgABLgAECggJIAAPALwPAA==.',
If='Iforgotnaaru:BAABLgAECn8XAAMOAAcJ4Qv3cAAEAQAOAAcJ4Qv3cAAEAQAPAAQJtQqGagCkAAAAAA==.',
Ik='Ikedizzy:BAAALgAECgEJAQABLgAFFAEJAQAKAAAAAA==.Ikeslice:BAAALgAFFAEJAQAAAA==.Ikrys:BAAALgAECgYJDAAAAA==.',
Il='Illiae:BAACLgAFFH8LAAIPAAMJ/CKYHwAbAQAPAAMJ/CKYHwAbAQAuAAQKfzAAAg8ACAl8JNMJAL8CAA8ACAl8JNMJAL8CAAAA.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8rAAIVAAgJxxNkLACgAQAVAAgJxxNkLACgAQAAAA==.',
In='Incrdblestan:BAAALgAECgMJBAAAAA==.Innex:BAABLgAECn8nAAIXAAkJGx8KLABOAgAXAAkJGx8KLABOAgAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECgkJJwAXABsfAA==.Innexvoker:BAABLgAECn8YAAIDAAgJag/FMQBsAQADAAgJag/FMQBsAQABLgAECgkJJwAXABsfAA==.Inpesca:BAAALgADCgUJBQABLgAFFAUJCQADAMQQAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgYJCwAAAA==.',
Ir='Iridescent:BAAALgAECgIJAgAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAABLgAECn8eAAIgAAcJuQ52EwAkAQAgAAcJuQ52EwAkAQAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itzmuffin:BAABLgAECn8oAAIOAAgJyRLwSwB8AQAOAAgJyRLwSwB8AQAAAA==.Itzpie:BAABLgAECn81AAIQAAkJNxYiSQD9AQAQAAkJNxYiSQD9AQAAAA==.',
Ja='Jadandotz:BAAALgADCggJAgAAAA==.Jagtat:BAABLgAECn8gAAMXAAcJPBCSlQA6AQAXAAcJPBCSlQA6AQAZAAUJcQfTQwB8AAAAAA==.Jakeakuma:BAABLgAECn8UAAIRAAkJBAwlXwCsAQARAAkJBAwlXwCsAQAAAA==.Jascob:BAABLgAECn8gAAImAAYJMQn8EgD0AAAmAAYJMQn8EgD0AAAAAA==.Jasonborne:BAAALgAECgQJBAAAAA==.Jaynne:BAAALgADCgcJCAAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAAALgAECgkJEAAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn9QAAIYAAkJsB8HBgDaAgAYAAkJsB8HBgDaAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8lAAIdAAgJGiFcCAD0AgAdAAgJGiFcCAD0AgABLgAFFAQJBAAKAAAAAA==.Junfan:BAAALgAECgcJCQAAAA==.',
['Jà']='Jàckblack:BAAALgAECgYJDAAAAA==.',
Ka='Kaashaa:BAACLgAFFH8UAAIHAAQJthtUKgBXAQAHAAQJthtUKgBXAQAuAAQKf0AAAgcACQnLIX8OANkCAAcACQnLIX8OANkCAAAA.Kaelsgf:BAAALgAECgcJDAAAAA==.Kahllan:BAABLgAECn80AAMNAAkJ5Q9fIwCrAQANAAkJ5Q9fIwCrAQAMAAEJ+RdmvQBGAAAAAA==.Kahnigitt:BAABLgAECn8XAAIXAAcJhwrWpQAgAQAXAAcJhwrWpQAgAQAAAA==.Kalsifire:BAAALgADCgkJEAAAAA==.Kataltoholic:BAABLgAECn8aAAIQAAYJOAHUJwFmAAAQAAYJOAHUJwFmAAAAAA==.Katrath:BAAALgADCgMJBgAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIBAAYJCxp5UAC1AQABAAYJCxp5UAC1AQAAAA==.Kaýhás:BAAALgADCgYJBgAAAA==.',
Ke='Kelinïsha:BAABLgAECn8pAAIQAAgJJQqrnQA8AQAQAAgJJQqrnQA8AQAAAA==.Kelynna:BAABLgAECn8pAAIIAAgJDhwsEgBLAgAIAAgJDhwsEgBLAgAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJBQAAAA==.',
Kh='Khaodemus:BAAALgAECggJCQAAAA==.Khellder:BAAALgAECgUJDgABLgAECgkJEQAKAAAAAA==.Khelldyr:BAAALgAECggJCAABLgAECgkJEQAKAAAAAA==.Khellrond:BAAALgAECgkJEQAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiffira:BAAALgAECgYJBgABLgAECgkJKQABAEUWAA==.Kiiras:BAABLgAECn8vAAIQAAgJ9A2bgwBtAQAQAAgJ9A2bgwBtAQAAAA==.Kimbodh:BAACLgAFFH8iAAIBAAUJ/SSwHwCuAQABAAUJ/SSwHwCuAQAuAAQKfyYAAgEACAkOJFUOAM8CAAEACAkOJFUOAM8CAAEuAAEKAwkBAAoAAAAA.Kimoora:BAAALgAECgQJBAAAAA==.Kimshady:BAAALgADCgEJAQABLgAECgQJBAAKAAAAAA==.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8wAAIBAAkJ+BB/SACpAQABAAkJ+BB/SACpAQAAAA==.',
Kl='Klefthoof:BAABLgAECn8/AAMOAAgJjhTfLQD7AQAOAAgJjhTfLQD7AQAPAAIJcASrmQA/AAAAAA==.',
Ko='Kodey:BAABLgAECn8oAAIaAAkJxxRVBgD5AQAaAAkJxxRVBgD5AQABLgAFFAQJEwAaAL8GAA==.Kordy:BAAALgAECgkJAQAAAA==.Korey:BAAALgAECgEJAQAAAA==.',
Kr='Kraniah:BAABLgAECn8VAAMOAAkJehWaHgBVAgAOAAkJehWaHgBVAgAPAAYJgATJdQCGAAAAAA==.Krelon:BAAALgAECgEJAQAAAA==.Krimboz:BAABLgAECn8vAAIRAAkJZxqCHwBlAgARAAkJZxqCHwBlAgAAAA==.Krimbrouge:BAAALgAECgYJCAAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8uAAITAAkJQxqxCQCCAgATAAkJQxqxCQCCAgAAAA==.Krìsta:BAACLgAFFH8GAAMbAAIJ7QIWEwBuAAAbAAIJ7QIWEwBuAAARAAEJ8QAY0gAvAAAuAAQKfx4AAxsACAncDFgNAGABABsABwleDlgNAGABABEABwknBE6/AMwAAAAA.',
Ku='Kuanshuwo:BAABLgAECn8VAAMJAAgJ7wnMNgA4AQAJAAgJ7wnMNgA4AQAIAAYJfQZMTgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
La='Lanwulf:BAAALgAECgYJEQAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAACLgAFFH8LAAIJAAUJUxXpGAAbAQAJAAUJUxXpGAAbAQAuAAQKfxgAAgkACQlvHb4XACYCAAkACQlvHb4XACYCAAAA.Legaloas:BAABLgAECn8vAAMHAAkJGyARFgCgAgAHAAkJGyARFgCgAgAgAAUJGxHfFwDwAAAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAABLgAECn8XAAIdAAcJ7A3cOAAbAQAdAAcJ7A3cOAAbAQAAAA==.Leonarde:BAACLgAFFH8PAAMHAAQJKBnhQgAhAQAHAAQJIBnhQgAhAQAgAAMJ2Q/RFQDuAAAuAAQKfyIABCAACQkZGb8gACACACAACAkSF78gACACAAcABQl/GDptAGIBABMAAQlWAKwzAA0AAAAA.Levitt:BAABLgAECn8WAAIRAAYJjhFikQAYAQARAAYJjhFikQAYAQABLgAECggJFgAeANURAA==.Leyla:BAAALgADCgkJCQAAAA==.',
Li='Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn80AAIdAAkJbhYFFgAFAgAdAAkJbhYFFgAFAgAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liquid:BAAALgAECgEJAQAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgYJDwAAAA==.',
Ll='Llevanya:BAABLgAECn88AAIFAAkJUxA3WgC8AQAFAAkJUxA3WgC8AQAAAA==.Llinaigh:BAACLgAFFH8KAAIHAAQJhBNlPAAuAQAHAAQJhBNlPAAuAQAuAAQKfxkAAgcACQmDFVU7AO4BAAcACQmDFVU7AO4BAAAA.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAgABLgAECgkJNAAVAPwfAA==.Lomu:BAABLgAECn8qAAQcAAkJnhvSCQBHAgAcAAkJnhvSCQBHAgAMAAEJ7Q5JzwAvAAANAAEJigTXnQAhAAAAAA==.Loredalso:BAAALgAECgEJAQAAAA==.Lorenitha:BAAALgAECgEJAQABLgAFFAQJDQAFABccAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
['Lê']='Lêdrollan:BAAALgAECgIJAgABLgAFFAUJCwAJAFMVAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAFFAMJCAALAGsbAA==.Magicdreams:BAABLgAECn80AAINAAkJNAmaLwBcAQANAAkJNAmaLwBcAQAAAA==.Malificent:BAAALgADCgQJCAAAAA==.Malmorte:BAABLgAECn8WAAIXAAYJMRUHowA6AQAXAAYJMRUHowA6AQAAAA==.Malorane:BAABLgAECn8vAAIZAAkJFhshCwBjAgAZAAkJFhshCwBjAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgAECgEJAQAAAA==.Marihuano:BAAALgAFFAIJBAAAAA==.Marisi:BAAALgADCggJCAABLgAECgcJBwAKAAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIkAAkJ0R12EQAaAgAkAAkJ0R12EQAaAgAAAA==.Materiaga:BAABLgAECn8iAAQDAAgJEhEFLwB7AQADAAgJwBAFLwB7AQACAAYJFQtdKQAoAQAWAAMJjw8HGACVAAAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8xAAIFAAkJKCGwDwDmAgAFAAkJKCGwDwDmAgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMiAAkJGxU2BgCWAgAiAAkJGxU2BgCWAgAPAAgJyg/SQwAgAQAAAA==.',
Me='Medalla:BAAALgADCgYJBgAAAA==.Meerchi:BAABLgAECn8wAAMQAAkJCBkdOQAxAgAQAAkJCBkdOQAxAgAnAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Meiriie:BAAALgAECgYJBgAAAA==.Meowkai:BAAALgAECgYJBgABLgAECgkJJwATAA0lAA==.Mesmal:BAAALgAECgkJAwABLgAECgkJCQAKAAAAAA==.Mesthos:BAAALgAECgcJDAABLgAECgkJKAASACwmAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8lAAIDAAgJlBKOGgD2AQADAAgJlBKOGgD2AQAAAA==.',
Mi='Miciah:BAAALgAECgQJBAAAAA==.Mickieta:BAABLgAECn86AAIFAAkJ0iA5FADHAgAFAAkJ0iA5FADHAgAAAA==.Microsurge:BAACLgAFFH8HAAIQAAQJ4AhCbwAJAQAQAAQJ4AhCbwAJAQAuAAQKfx0AAhAACAkiHdslANsCABAACAkiHdslANsCAAAA.Mikalau:BAABLgAECn8zAAIHAAkJ4xa0JQBHAgAHAAkJ4xa0JQBHAgAAAA==.Mikaluu:BAABLgAECn8hAAIRAAYJJg7EnAAEAQARAAYJJg7EnAAEAQAAAA==.Miqkail:BAAALgAECggJCgABLgAECgkJKAASACwmAA==.Missteek:BAAALgAECgYJEgABLgAECgkJQQAWACMjAA==.Mistrunner:BAAALgAECgMJAwAAAA==.Mistspell:BAACLgAFFH8PAAIJAAQJpQ/PHQD8AAAJAAQJpQ/PHQD8AAAuAAQKfyAAAwkACQnXHeQOAJUCAAkACQnXHeQOAJUCAAgAAwklBoFqAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwABLgAECgkJJwALAJsbAA==.Mognel:BAABLgAECn82AAIRAAkJxxxUKQA0AgARAAkJxxxUKQA0AgAAAA==.Mogrungar:BAACLgAFFH8IAAIOAAMJRRCBVACgAAAOAAMJRRCBVACgAAAuAAQKfygAAg4ACQl3FGUmACQCAA4ACQl3FGUmACQCAAAA.Moistdk:BAAALgAECgEJAQAAAA==.Moisten:BAABLgAECn8eAAIPAAkJQyBBCADWAgAPAAkJQyBBCADWAgAAAA==.Mokuo:BAAALgAFFAIJAgAAAA==.Monklee:BAAALgAECgEJAgAAAA==.Moomootus:BAABLgAECn8yAAMFAAkJ4xoZOQAcAgAFAAgJaRoZOQAcAgALAAQJ/B6UPABRAQAAAA==.Mordakttaa:BAAALgADCgMJAwAAAA==.Morgalea:BAAALgAECgcJAQAAAA==.Motoraxe:BAAALgAFFAIJAwAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIdAAgJRyBsDQClAgAdAAgJRyBsDQClAgABLgAFFAQJDgABAKgOAA==.Mystynight:BAAALgAECgYJEQAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAABLgAECn8lAAIPAAgJEA8APABCAQAPAAgJEA8APABCAQAAAA==.Naggs:BAAALgAECgkJCAAAAA==.Nagini:BAABLgAECn8fAAIRAAgJdwgFiQAnAQARAAgJdwgFiQAnAQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn8/AAMIAAkJgxmfHADcAQAIAAcJGRmfHADcAQAJAAkJtBGGPAAdAQAAAA==.Nietzcha:BAAALgAECgMJBAAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAABLgAECn8kAAMNAAgJ7RagHADgAQANAAgJ7RagHADgAQAlAAUJRw03NgB8AAAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nilfgard:BAAALgAECgcJEAAAAA==.Nioh:BAABLgAECn8iAAIBAAkJxRYVLwAHAgABAAkJxRYVLwAHAgAAAA==.Nivix:BAAALgAECgEJAgAAAA==.',
No='Noodles:BAABLgAECn8nAAIBAAgJnwiGlQDxAAABAAgJnwiGlQDxAAAAAA==.Nordrydd:BAAALgAECggJDgABLgAFFAcJGAAeAIIXAA==.Nordrydsh:BAAALgAFFAIJAgABLgAFFAcJGAAeAIIXAA==.',
Nu='Nuggs:BAABLgAECn8YAAIlAAkJzBAuEACuAQAlAAkJzBAuEACuAQAAAA==.Nuhpie:BAACLgAFFH8XAAMEAAcJhw6FJgDOAAAVAAMJUxHiNgDQAAAEAAQJuguFJgDOAAAuAAQKfx4AAwQACQlfHVAfAF8BAAQABQmuGlAfAF8BABUABQlsHOFLABYBAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8lAAIXAAkJax9hGQCsAgAXAAkJax9hGQCsAgAAAA==.',
Od='Odelay:BAAALgADCgEJAQAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAwAAAA==.',
Ol='Olimdar:BAACLgAFFH8qAAIOAAgJjCRhAABBAwAOAAgJjCRhAABBAwAuAAQKfycAAw4ACQlvJUsAAM8DAA4ACQlvJUsAAM8DAA8AAQmSHaiCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBwAAAA==.',
Oo='Oopositive:BAAALgAECgUJBQAAAA==.Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Orgarrot:BAAALgADCgYJBgABLgAECggJCQAKAAAAAA==.Oricelle:BAABLgAECn8pAAIBAAkJRRb1KQAeAgABAAkJRRb1KQAeAgAAAA==.Oridis:BAAALgAECgkJBwAAAA==.Oryon:BAEBLgAECn8zAAIbAAkJnRQ2CADjAQAbAAkJnRQ2CADjAQAAAA==.',
Ov='Ovarb:BAABLgAECn8rAAMZAAkJkRjgEQDsAQAZAAkJkRjgEQDsAQAXAAUJrQ522QDZAAAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDgAAAA==.Palasexo:BAAALgAECgUJCQABLgAFFAIJBAAKAAAAAA==.Palldude:BAAALgADCgQJBQAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Peachie:BAAALgADCgEJAQAAAA==.Pesti:BAACLgAFFH8gAAIkAAQJfBnyEwBkAQAkAAQJfBnyEwBkAQAuAAQKf1EAAiQACQlnI6wCACoDACQACQlnI6wCACoDAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8+AAIOAAkJQiMSBAB2AwAOAAkJQiMSBAB2AwAAAA==.',
Pi='Pissedwolf:BAAALgAECgUJCAAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAABLgAECn8fAAIYAAkJeBA7IACjAQAYAAkJeBA7IACjAQAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAACLgAFFH8UAAIQAAQJgxiSTwBGAQAQAAQJgxiSTwBGAQAuAAQKf0cABBAACQkJIjoOAAYDABAACQmIIToOAAYDACgABQnyFiQMABABACcAAQmjEKkTADEAAAAA.Proctologist:BAABLgAECn8xAAMYAAkJ9BubCACnAgAYAAkJ9BubCACnAgAdAAQJYROqQgDxAAAAAA==.Proserpìne:BAABLgAECn9IAAIBAAkJBw1kVQCDAQABAAkJBw1kVQCDAQAAAA==.',
Ps='Psychojester:BAACLgAFFH8RAAIiAAQJRxozBwBCAQAiAAQJRxozBwBCAQAuAAQKf0MAAiIACQk2IUsCAPgCACIACQk2IUsCAPgCAAAA.Psylir:BAAALgAECgQJDgAAAA==.Psypra:BAAALgAECgYJCQAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAABLgAECn8WAAIQAAUJihsPuwANAQAQAAUJihsPuwANAQAAAA==.',
Py='Pydge:BAAALgAECgEJAQAAAA==.',
Qu='Quod:BAAALgAECgQJBAAAAA==.Quoril:BAACLgAFFH8FAAIQAAIJDQ/4nwCRAAAQAAIJDQ/4nwCRAAAuAAQKfz8AAxAACQkLIQkQAPkCABAACQkLIQkQAPkCACgAAQmXIHkZAEwAAAEuAAUUBgkfAAcA4BoA.',
Ra='Raijyu:BAABLgAECn9CAAMIAAkJzR8hBQApAwAIAAkJzR8hBQApAwAJAAcJVRV+IwC8AQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECgkJNgANAM8WAA==.Rainstormin:BAABLgAECn82AAMNAAkJzxbDFQAeAgANAAkJzxbDFQAeAgAcAAYJxgmPPwCiAAAAAA==.Rakarra:BAABLgAECn8fAAMMAAkJGgv1RwBtAQAMAAkJGgv1RwBtAQANAAcJhwgPTQD2AAAAAA==.Ranalia:BAAALgADCgcJCgAAAA==.Rawrstance:BAABLgAECn89AAMZAAkJRRuiFgCxAQAZAAkJDRKiFgCxAQAXAAcJoRy7cQB+AQABLgADCgkJFAAKAAAAAA==.Razgrize:BAACLgAFFH8MAAIQAAMJUxdFdwDwAAAQAAMJUxdFdwDwAAAuAAQKfzAAAhAACQmeG1cjAI0CABAACQmeG1cjAI0CAAAA.',
Re='Redraggon:BAAALgAECgYJBgAAAA==.Reecalled:BAAALgADCgUJBQABLgAECggJGgADAGIaAA==.Reeshan:BAABLgAECn8fAAMFAAkJ1yNEDgDxAgAFAAkJ1yNEDgDxAgALAAIJaxRecwBnAAAAAA==.Reilin:BAAALgAFFAEJAQAAAA==.Remsham:BAABLgAECn8nAAIiAAkJxg24DwCyAQAiAAkJxg24DwCyAQAAAA==.Reniel:BAAALgAECgcJCAABLgAECgkJMAABAPgQAA==.Renwyck:BAABLgAECn8oAAISAAkJLCZdAABjAwASAAkJLCZdAABjAwAAAA==.Revengemoon:BAACLgAFFH8RAAIFAAQJsxLjSQAUAQAFAAQJsxLjSQAUAQAuAAQKfyMAAgUACQmVGsApAH4CAAUACQmVGsApAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgAKAAAAAA==.Ringberg:BAACLgAFFH8IAAILAAMJaxsBLADHAAALAAMJaxsBLADHAAAuAAQKfxcAAwsABwlSH+cYAD0CAAsABwlSH+cYAD0CAAUAAwmmFEoIAaoAAAAA.',
Ro='Robane:BAABLgAECn8UAAIFAAUJCA8V5QDUAAAFAAUJCA8V5QDUAAAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Rockette:BAAALgADCgYJBgAAAA==.Ronburgundy:BAAALgAECgMJBQAAAA==.Rouen:BAABLgAECn80AAMOAAkJ2xqbFACjAgAOAAkJ2xqbFACjAgAiAAgJiiLfBgBiAgAAAA==.',
Ru='Rubidea:BAAALgAECgEJAQAAAA==.Ruckus:BAEBLgAECn8XAAQMAAcJjwsuXAAgAQAMAAcJjwsuXAAgAQAcAAMJnAblWgBTAAANAAEJhQXHngAgAAABLgAECggJIAAPALwPAA==.Ruder:BAAALgAECgMJBAABLgAECggJCQAKAAAAAA==.Rutabaga:BAAALgAECgUJCAAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIJAAkJxBtnEQBzAgAJAAkJxBtnEQBzAgAAAA==.',
Sa='Saintanic:BAAALgADCgkJFAAAAA==.Salyna:BAAALgAECgEJAgAAAA==.Sandkat:BAABLgAECn9BAAIVAAkJZCI8BgD6AgAVAAkJZCI8BgD6AgAAAA==.Sanstian:BAAALgAECgUJDQAAAA==.Santamou:BAAALgAECgIJBQAAAA==.Saraelin:BAABLgAFFH8IAAIRAAIJ8ABbugBLAAARAAIJ8ABbugBLAAAAAA==.Saray:BAAALgAECgcJEgAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAYJEwAVAO4QAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgYJDgAAAA==.Serahstia:BAABLgAECn8fAAIQAAgJ9xVPZACyAQAQAAgJ9xVPZACyAQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shadowmeld:BAAALgAECgEJAQAAAA==.Shadysadie:BAAALgAECgcJDwAAAA==.Shaiy:BAAALgAECgcJEAAAAA==.Shakejunt:BAAALgADCgEJAQAAAA==.Shammymoe:BAAALgAECgEJAwAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwAKAAAAAA==.Shiifthappen:BAAALgAECgEJAQAAAA==.Shinta:BAABLgAECn8UAAQLAAYJLRSdPgBHAQALAAUJBRadPgBHAQAGAAUJ2g8aKwC/AAAFAAQJAwjYKAGDAAAAAA==.Shirtles:BAABLgAECn8YAAIPAAYJggNgcgCPAAAPAAYJggNgcgCPAAAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shpik:BAAALgADCgUJCQAAAA==.Shèp:BAABLgAECn8ZAAILAAgJFhGdLgCfAQALAAgJFhGdLgCfAQAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIPAAUJ/hmfAwCvAQAPAAUJ/hmfAwCvAQABLgAFFAYJDgATACUWAA==.Siffrin:BAAALgAECgIJAgAAAA==.Siink:BAAALgAFFAEJAgAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8lAAMRAAgJnhWtcwBSAQARAAYJ0hKtcwBSAQAbAAUJJRYKGgDqAAABLgAECggJJQADAJQSAA==.Sinkingship:BAAALgAECgYJCQAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAABLgAECn8iAAIZAAkJFyANBgDCAgAZAAkJFyANBgDCAgAAAA==.',
Sk='Skaterboi:BAAALgAECgYJBgAAAA==.Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sliy:BAAALgAECgIJAgAAAA==.Sloothe:BAAALgADCgQJBAAAAA==.Sloothi:BAAALgAECgEJAQAAAA==.Slyveria:BAAALgAECgMJBAAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.Snorri:BAAALgAECgUJBQAAAA==.',
So='Sosorry:BAAALgADCgIJAgAAAA==.Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAABLgAECn8WAAIFAAkJgRpDNQApAgAFAAkJgRpDNQApAgAAAA==.',
Sp='Sprodage:BAABLgAECn9IAAILAAkJVhiHFQBdAgALAAkJVhiHFQBdAgAAAA==.',
St='Staggrsaurus:BAAALgAECgIJAwABLgAECgMJBAAKAAAAAA==.Stanil:BAABLgAECn8oAAMHAAgJFgm0bgBfAQAHAAgJFgm0bgBfAQAgAAEJWwAkmwAVAAAAAA==.Stayfrosty:BAAALgAECgcJDAAAAA==.Stellare:BAABLgAECn8wAAIUAAkJHRchEQAUAgAUAAkJHRchEQAUAgAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Stinklines:BAAALgAECgEJAgABLgAECgkJQQAWACMjAA==.Strangetame:BAAALgADCgEJAQAAAA==.Striest:BAAALgAECgMJAwAAAA==.Styló:BAAALgAECggJEwAAAA==.',
Su='Suetonius:BAACLgAFFH8RAAIXAAQJRR+ePwBxAQAXAAQJRR+ePwBxAQAuAAQKfxQAAxcACAlXJBwRAOICABcACAlXJBwRAOICACMAAgk4E+EtAGQAAAAA.Suguru:BAAALgAECggJCQAAAA==.Sungsuf:BAAALgAECgEJAQAAAA==.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8rAAIQAAkJaBq8NwA3AgAQAAkJaBq8NwA3AgAAAA==.Suraschi:BAABLgAECn8UAAMYAAkJ4hdeFwDsAQAYAAgJ1BdeFwDsAQAdAAcJjhGILQBSAQABLgAECgkJKwAQAGgaAA==.',
Sv='Svelda:BAABLgAECn8uAAMJAAcJow/wNwAzAQAJAAcJow/wNwAzAQAhAAUJmAXOUAC7AAAAAA==.',
Sw='Swisscake:BAABLgAECn9EAAINAAkJaySUAgBIAwANAAkJaySUAgBIAwAAAA==.',
Sy='Sylain:BAAALgAECgYJEgABLgAECgkJFQAkAKEKAA==.Synwav:BAAALgADCgEJAQAAAA==.',
Ta='Tannatax:BAABLgAECn8vAAIOAAkJZQZDWgBKAQAOAAkJZQZDWgBKAQAAAA==.Tashah:BAAALgADCgUJBQAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAAKAAAAAA==.Tekvet:BAAALgAECgkJCQAAAA==.',
Th='Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8jAAMQAAkJnBUsUwDgAQAQAAkJnBUsUwDgAQAnAAEJGgHCFwAJAAAAAA==.Thewretch:BAABLgAECn85AAIRAAkJhyKEBwAbAwARAAkJhyKEBwAbAwAAAA==.Thibble:BAAALgADCgYJBgAAAA==.Thumpthump:BAABLgAECn8nAAQTAAkJQBg2FAADAgAgAAYJwx6nIgARAgATAAkJMhA2FAADAgAHAAEJqQ4/KQE3AAAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEBLgAECn8gAAIPAAgJvA9NNgBdAQAPAAgJvA9NNgBdAQAAAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Titiera:BAABLgAECn8gAAIHAAgJBRcvOgDyAQAHAAgJBRcvOgDyAQAAAA==.',
To='Toastnbutta:BAABLgAECn8mAAIMAAkJ9xluGACAAgAMAAkJ9xluGACAAgAAAA==.Tolten:BAABLgAECn8eAAIFAAgJ3RmUMQBcAgAFAAgJ3RmUMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgYJCAAAAA==.Traumatism:BAAALgAECgkJEwAAAA==.Trevor:BAABLgAECn9BAAImAAkJUhheBABOAgAmAAkJUhheBABOAgAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAACLgAFFH8IAAMlAAMJjBLkDwC8AAAlAAMJ9wzkDwC8AAAcAAEJXBmENABLAAAuAAQKfyAAAyUACQnLInoBAC4DACUACQnLInoBAC4DABwABgk0HGUYAIYBAAEuAAUUBQkYABkArhwA.Tsura:BAAALgAFFAEJAQAAAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Ty='Tylaesh:BAAALgAECgYJDwAAAA==.',
Un='Unclepeepers:BAACLgAFFH8VAAIeAAQJ4iD2HwBgAQAeAAQJ4iD2HwBgAQAuAAQKfy4AAx0ACQkPI8oPAEwCAB0ACAmOIsoPAEwCAB4ACQm0G7kiAAMCAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAABLgAECn8YAAIXAAcJ3QuaxwDxAAAXAAcJ3QuaxwDxAAAAAA==.',
Ur='Urtag:BAACLgAFFH8UAAMgAAgJVBNFDQCGAQAgAAcJRA1FDQCGAQAHAAQJ7xJxLgBMAQAuAAQKfxUAAyAACAnyFboqANYBACAACAkZFboqANYBAAcAAgm6F1zUAJwAAAAA.',
Ut='Uthgar:BAAALgAECgYJCAAAAA==.',
Va='Vadge:BAAALgADCgcJBwABLgADCgkJFAAKAAAAAA==.Vaeryn:BAABLgAECn8bAAIHAAcJlxQFXQCKAQAHAAcJlxQFXQCKAQABLgAFFAMJCgAhAKsOAA==.Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAACLgAFFH8KAAIhAAMJqw6JMQDBAAAhAAMJqw6JMQDBAAAuAAQKf3IAAyEACAlXH6QJANYCACEACAlXH6QJANYCAAkABwneEJUxAFQBAAAA.Valryn:BAABLgAECn8XAAMXAAcJKgvVngArAQAXAAcJKgvVngArAQAZAAEJxgH7TwAVAAABLgAFFAMJCgAhAKsOAA==.Valtar:BAABLgAECn8gAAIOAAkJoBzyGQB3AgAOAAkJoBzyGQB3AgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAACLgAFFH8HAAMXAAUJRRTDWwA5AQAXAAUJRRTDWwA5AQAZAAIJxRAkDgCJAAAuAAQKfzAAAxcACQmJI20GAEMDABcACQmJI20GAEMDABkACAntHUsPABcCAAAA.',
Ve='Velra:BAAALgADCgEJAQABLgAFFAMJCgAhAKsOAA==.Velryn:BAAALgAECgUJCwABLgAFFAMJCgAhAKsOAA==.Veraalyn:BAABLgAECn8dAAMPAAgJHhGHRAAdAQAPAAgJHhGHRAAdAQAOAAMJxwiifgCZAAAAAA==.',
Vi='Vicsen:BAABLgAECn8gAAIRAAkJdQWIfwA5AQARAAkJdQWIfwA5AQAAAA==.Vikaya:BAAALgAECggJCgAAAA==.Vilaris:BAAALgAECggJCwAAAA==.Vilevixon:BAABLgAECn8hAAMJAAkJ4hZRFwANAgAJAAkJ4hZRFwANAgAhAAMJxgc/XgB/AAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Vo='Voidasuras:BAAALgAECgEJAQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAAKAAAAAA==.Wanlok:BAAALgAECgQJCQAAAA==.Wantoo:BAAALgAECgYJBgAAAA==.Warlokip:BAAALgAECgkJCgAAAA==.Warotar:BAAALgAECgIJAgAAAA==.Warriorlobo:BAABLgAECn80AAQVAAkJ/B+VCADWAgAVAAkJ/B+VCADWAgAEAAYJ7RCVMQD9AAAfAAEJ6A6RWAAjAAAAAA==.Warvision:BAAALgAFFAEJAQAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAABLgAECn8iAAMHAAkJKQx8VAChAQAHAAkJKQx8VAChAQATAAEJQwO5aAAoAAAAAA==.Wildside:BAABLgAECn8cAAMHAAYJGSBmSQDBAQAHAAYJGSBmSQDBAQATAAYJCxYSKABfAQAAAA==.',
Wu='Wujifei:BAAALgAFFAIJAwAAAA==.Wulffgar:BAAALgAECgQJBAAAAA==.',
['Wì']='Wìldthìng:BAAALgAECgUJCgAAAA==.',
Xa='Xandronys:BAAALgAECgkJDAAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECggJCgAAAA==.Xenie:BAAALgAECggJEgAAAA==.',
Xi='Xinema:BAAALgAECgQJBAAAAA==.Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgAECgYJDgAAAA==.',
Yd='Ydeatho:BAAALgAFFAMJAwAAAA==.',
Ye='Yeet:BAABLgAECn8bAAIkAAkJNBj5IgDhAQAkAAkJNBj5IgDhAQAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgMJBgAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgAECgMJBgAAAA==.Zalanna:BAAALgADCgMJAwAAAA==.Zalckar:BAABLgAECn8bAAMLAAkJcBIZRQBjAQALAAkJcBIZRQBjAQAFAAEJYQ5HmgEtAAAAAA==.Zanos:BAAALgAECgIJAgAAAA==.Zarayssa:BAAALgADCgYJCAAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zebracakes:BAAALgAECgEJAQABLgAECgkJQwASAOMlAA==.Zeeva:BAABLgAECn8bAAMaAAYJOyFQCADEAQAaAAYJYyBQCADEAQAbAAMJ+h1hJwB/AAAAAA==.Zendead:BAABLgAECn8jAAIdAAkJCiPUBwDIAgAdAAkJCiPUBwDIAgAAAA==.Zeppeli:BAAALgAECgMJAwAAAA==.Zerkces:BAAALgADCgIJAgAAAA==.',
Zi='Zionspartan:BAABLgAECn8xAAIHAAkJAQ9NQwDTAQAHAAkJAQ9NQwDTAQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugpriest:BAAALgAECgQJBAAAAA==.Zugzugshaman:BAABLgAECn8sAAQOAAkJARiBGwBsAgAOAAkJARiBGwBsAgAPAAQJrwOHbgCJAAAiAAEJYQB8RgAdAAAAAA==.Zurokhan:BAAALgAECgUJBQAAAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Êï']='Êïñstëïn:BAAALgAECgEJAQAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8kAAIYAAgJmxELJgB7AQAYAAgJmxELJgB7AQAAAA==.',
['Ñå']='Ñårçîssîstîç:BAAALgAECgYJBgAAAA==.',
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
