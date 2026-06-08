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

local lookup = {'Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','Hunter-Survival','Warrior-Fury','Evoker-Devastation','DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Protection','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','DeathKnight-Frost','Rogue-Subtlety','Druid-Feral','Rogue-Assassination','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Aberration:BAAALgAECgEJAgAAAA==.',
Ad='Adorraa:BAAALgAFFAEJAQAAAA==.Adoryn:BAAALgADCgYJCQAAAA==.Adowyrm:BAACLgAFFH8nAAMBAAgJFRcZCQD/AQABAAcJzhYZCQD/AQACAAMJYQ1INgDfAAAuAAQKfyEAAwEACQm1IUcCAFEDAAEACQm1IUcCAFEDAAIABgnLHfscAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.Adrielle:BAAALgADCgkJDAAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECgkJHQADAIgcAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAFFAQJBAAAAA==.',
Ai='Airali:BAACLgAFFH8JAAIEAAQJ+gUAVgDwAAAEAAQJ+gUAVgDwAAAuAAQKfxcAAwQACQn+E2tkALgBAAQACQn+E2tkALgBAAUAAwmJCNM3AGIAAAAA.Airedale:BAABLgAECn8qAAIGAAgJDxf/OADvAQAGAAgJDxf/OADvAQAAAA==.',
Ak='Akairo:BAABLgAECn8xAAMHAAkJACSCAgBBAwAHAAkJACSCAgBBAwAIAAgJrBHwJwCGAQAAAA==.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgAECgYJBgAAAA==.Alderbaran:BAAALgADCgUJBQAAAA==.Alexanderxl:BAABLgAECn8WAAMFAAYJAB1gFwBfAQAFAAYJAB1gFwBfAQAEAAUJWBU9uwACAQABLgAECggJAwAJAAAAAA==.Aleybobwa:BAABLgAECn8fAAMKAAkJjhKwKAC8AQAKAAkJjhKwKAC8AQAEAAEJYwiPUgErAAAAAA==.Alody:BAAALgADCgMJAwAAAA==.Alyméré:BAAALgAECgYJBwAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAABLgAECn8nAAIKAAkJmxspDADCAgAKAAkJmxspDADCAgAAAA==.Amulius:BAABLgAECn81AAIEAAkJyyWtBABMAwAEAAkJyyWtBABMAwAAAA==.',
An='Anderdingus:BAAALgADCgYJCgAAAA==.Andormath:BAAALgAECgQJBgAAAA==.Andramedae:BAABLgAECn8yAAMLAAkJaxUuHwBDAgALAAkJaxUuHwBDAgAMAAYJCw1ZRQDoAAAAAA==.Angerissues:BAAALgADCgkJCQAAAA==.Angyavocado:BAAALgADCgkJCQAAAA==.Anoki:BAABLgAECn9DAAMNAAkJJBu6EwCiAgANAAkJJBu6EwCiAgAOAAEJgQvCpwAnAAAAAA==.',
Ao='Aolus:BAACLgAFFH8RAAIMAAQJuxgIHgAXAQAMAAQJuxgIHgAXAQAuAAQKfxsAAgwACQkVHDETAHsCAAwACQkVHDETAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgAECgEJAQAAAA==.Aprollon:BAAALgAECgEJAQAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJBAAJAAAAAA==.Arcaina:BAABLgAECn8fAAIPAAgJHAlbkgBNAQAPAAgJHAlbkgBNAQAAAA==.Ares:BAAALgADCgkJEAABLgAECgkJMwAQAGwXAA==.Arez:BAABLgAECn8zAAIQAAkJbBeFKQAvAgAQAAkJbBeFKQAvAgAAAA==.Arilass:BAAALgADCgIJBAAAAA==.Armis:BAAALgADCgEJAQABLgAECgkJQwARAOMlAA==.Artèmís:BAABLgAECn8nAAISAAkJDSX1AgAKAwASAAkJDSX1AgAKAwAAAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Ashtongue:BAAALgADCgkJHAAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athinea:BAAALgAECgIJAgAAAA==.',
Au='Aura:BAAALgAFFAEJAQAAAA==.',
Ay='Ayahuasca:BAAALgADCgIJAgAAAA==.',
Az='Azaekho:BAABLgAECn8kAAINAAkJcxQIKgDmAQANAAkJcxQIKgDmAQAAAA==.Azalet:BAAALgAFFAIJAgAAAA==.',
Ba='Baalzak:BAAALgADCgYJBQAAAA==.Backfliphoe:BAAALgAECgcJEAAAAA==.Badoosh:BAABLgAECn8oAAITAAgJcB2aGACHAgATAAgJcB2aGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Bajablaster:BAABLgAECn82AAQUAAkJVCLAAAAnAwAUAAkJVCLAAAAnAwACAAMJ5BD7TACdAAABAAEJMAuWOwArAAAAAA==.Baliw:BAAALgADCgUJBAAAAA==.Balto:BAAALgADCgMJAwAAAA==.',
Bb='Bbl:BAECLgAFFH8ZAAIOAAUJYxgBGwAuAQAOAAUJYxgBGwAuAQAuAAQKfyUAAg4ACQnWIFgKAPACAA4ACQnWIFgKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8PAAIPAAQJ2xFGKwAIAQAPAAQJ2xFGKwAIAQAuAAQKfyMAAg8ACQnDGZo7AIgCAA8ACQnDGZo7AIgCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAACLgAFFH8GAAIEAAIJJQ3nhQCMAAAEAAIJJQ3nhQCMAAAuAAQKfxgAAgQACQkfER1SAMgBAAQACQkfER1SAMgBAAAA.',
Bh='Bhain:BAAALgADCgcJDQABLgAFFAQJDwAEAHweAA==.',
Bi='Bieorne:BAABLgAECn87AAIVAAkJrSFbDQD6AgAVAAkJrSFbDQD6AgAAAA==.Bigpan:BAAALgAECgEJAQABLgAECggJHQAWAJoOAA==.',
Bl='Blastbane:BAACLgAFFH8LAAIQAAQJXQuTWgAEAQAQAAQJXQuTWgAEAQAuAAQKfxQAAhAACQnuFBozAAcCABAACQnuFBozAAcCAAEuAAUUBQkMABcAiQkA.Bloodwrath:BAAALgAECgIJBAAAAA==.Blueveins:BAAALgAECgcJDwAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAACLgAFFH8FAAIQAAIJ5R7IiQCcAAAQAAIJ5R7IiQCcAAAuAAQKfxgAAxAACQnvHP4PAPoCABAACQnvHP4PAPoCABgAAQkAAN1LAAAAAAEuAAUUAwkIAAoAaxsA.Boondocks:BAABLgAECn81AAMZAAkJqB5kDQByAQAQAAUJZBocXACFAQAZAAUJ8CFkDQByAQAAAA==.',
Br='Braca:BAAALgADCgEJAgAAAA==.Braelek:BAAALgADCgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAABLgAECn8ZAAIWAAkJLQ+LIgCNAQAWAAkJLQ+LIgCNAQABLgAECgkJKgAaAJ4bAA==.Brielle:BAABLgAECn8tAAIGAAkJuBfcJwA0AgAGAAkJuBfcJwA0AgAAAA==.Brokenbranch:BAABLgAECn8UAAILAAcJUQioaQDuAAALAAcJUQioaQDuAAAAAA==.Brudene:BAABLgAECn8UAAITAAcJFRF2VABZAQATAAcJFRF2VABZAQAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Bubbletruble:BAAALgAECgYJBgAAAA==.Buddylock:BAABLgAECn8iAAIQAAkJmgnOdABLAQAQAAkJmgnOdABLAQAAAA==.Bulltaura:BAAALgAECgcJBwAAAA==.Bullymaguire:BAACLgAFFH8RAAIbAAcJRhugBADEAQAbAAcJRhugBADEAQAuAAQKfx0AAhsACAk5I0EFADEDABsACAk5I0EFADEDAAAA.Burakkuburu:BAABLgAECn88AAMcAAkJHR84CAAKAwAcAAkJHR84CAAKAwAbAAYJMRmwLgBCAQABLgAECgkJJwASAA0lAA==.',
Ca='Caboozles:BAABLgAECn87AAIGAAkJCRatNgD3AQAGAAkJCRatNgD3AQAAAA==.Caliopia:BAABLgAECn8xAAMOAAkJvBTxHQDlAQAOAAkJvBTxHQDlAQANAAYJYQrWawAIAQAAAA==.Caliper:BAAALgAECgEJAQAAAA==.Caplyta:BAAALgAECgUJCQABLgAFFAUJEgAIACscAA==.Captnhuntcat:BAAALgAECggJEwAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8vAAITAAkJNxcmEgBcAgATAAkJNxcmEgBcAgAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAABLgAECn8bAAMXAAkJaR2cEAABAgAXAAkJaR2cEAABAgAVAAQJJA+ZvgD2AAAAAA==.Chemistree:BAABLgAECn8vAAILAAkJNRR3JQAYAgALAAkJNRR3JQAYAgAAAA==.Chillout:BAABLgAECn8nAAIPAAkJvw0IXQDBAQAPAAkJvw0IXQDBAQAAAA==.Chillums:BAABLgAECn8cAAIQAAcJ4iP7GgCzAgAQAAcJ4iP7GgCzAgAAAA==.Chipcle:BAAALgAECgQJBwAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Ci='Cillah:BAAALgAECgEJAQABLgAECgkJNAATAPwfAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgADCgkJFAAJAAAAAA==.',
Co='Codeblue:BAAALgADCgYJBwAAAA==.Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8dAAIKAAkJYg6gJwDDAQAKAAkJYg6gJwDDAQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Cy='Cy:BAAALgAECgcJEAAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAABLgAECggJFQAVAB4bAA==.Daeleiel:BAAALgAECgEJAQAAAA==.Damrek:BAAALgAECgEJAQAAAA==.Darkenergy:BAABLgAECn80AAMdAAkJmySRAQBXAwAdAAkJmySRAQBXAwAeAAkJuh8gEAC4AgAAAA==.Darà:BAAALgAECgMJAwABLgAECgkJMQAMAOUPAA==.Dashyll:BAAALgAECgMJBAAAAA==.Davyfknjones:BAABLgAECn8aAAIGAAgJTxjWMgAGAgAGAAgJTxjWMgAGAgAAAA==.Daynia:BAAALgAECgYJEAAAAA==.',
De='Deadbolt:BAAALgAECgYJBgAAAA==.Deadlegslul:BAABLgAECn8fAAIGAAgJOR20JgA6AgAGAAgJOR20JgA6AgAAAA==.Deadlegsmd:BAAALgAECgQJCAAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadtree:BAAALgAECgEJAQAAAA==.Deadzepplin:BAAALgAECgUJBwAAAA==.Deathmono:BAAALgAECgYJDQAAAA==.Deathshark:BAACLgAFFH8VAAIXAAUJAhycEwA7AQAXAAUJAhycEwA7AQAuAAQKfy8AAhcACQn6HuoMADECABcACQn6HuoMADECAAAA.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAABLgAECn8iAAIPAAcJyAyumABDAQAPAAcJyAyumABDAQABLgAECggJNwANAFcUAA==.Demeter:BAABLgAECn9EAAIFAAkJvBTyDADpAQAFAAkJvBTyDADpAQAAAA==.Demiurge:BAAALgAECgIJAgAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denalli:BAAALgADCgIJAgAAAA==.Denarien:BAAALgAECgkJDQAAAA==.Derpygos:BAAALgADCgcJBwABLgAECgkJKgAaAJ4bAA==.Devouress:BAACLgAFFH8HAAIeAAQJXwyiTwDtAAAeAAQJXwyiTwDtAAAuAAQKfxkAAh4ACAkOGM04ANcBAB4ACAkOGM04ANcBAAAA.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dillkiller:BAABLgAECn8XAAIfAAcJGQn9IQAuAQAfAAcJGQn9IQAuAQAAAA==.Dirgen:BAABLgAECn8wAAMTAAkJLhnMEABpAgATAAkJLhnMEABpAgAfAAEJzhxRRgBNAAAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAFFAQJEgAWAPMJAA==.Double:BAAALgAECgQJBAAAAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAABLgAECn8aAAICAAgJYhpkGwDzAQACAAgJYhpkGwDzAQAAAA==.Dragginballs:BAAALgAECgIJBAABLgAFFAIJAgAJAAAAAA==.Draggnar:BAABLgAECn8UAAIYAAcJWQe1GQDMAAAYAAcJWQe1GQDMAAAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAABLgAECn8mAAMSAAkJgA9KEwAJAgASAAkJeA9KEwAJAgAgAAcJeAaFHgCvAAAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJDwAOAEwhAA==.',
Du='Dumplingsxo:BAABLgAECn8kAAMMAAkJnBhBGQA9AgAMAAgJsBlBGQA9AgALAAcJ4BiYPQCtAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn9DAAMRAAkJ4yVNAABkAwARAAkJ4yVNAABkAwAdAAYJgx1xGACvAQAAAA==.',
Eb='Ebojager:BAABLgAECn9AAAIeAAkJVhr2GgBoAgAeAAkJVhr2GgBoAgAAAA==.',
Eh='Ehko:BAAALgAECgYJCwABLgAECgkJJwASAA0lAA==.',
Ei='Eibon:BAACLgAFFH8dAAIVAAgJaB2XBgCXAgAVAAgJaB2XBgCXAgAuAAQKfx4AAhUACQnNIakUAAADABUACQnNIakUAAADAAAA.Einfreren:BAAALgAECgQJBAAAAA==.',
El='Elliiria:BAAALgAECgQJBgAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgkJEwAAAA==.Elvispriesty:BAABLgAECn8dAAIhAAcJ5RPqIgCoAQAhAAcJ5RPqIgCoAQAAAA==.Elwarrioro:BAAALgAECgYJDwAAAA==.',
Em='Emmpunity:BAAALgAECgQJBAAAAA==.Emmune:BAABLgAECn8oAAIiAAkJzxToCAAlAgAiAAkJzxToCAAlAgAAAA==.',
En='Enobia:BAABLgAECn8lAAMYAAgJSBMfCgCTAQAYAAgJSBMfCgCTAQAQAAUJFgbDxADQAAAAAA==.Entrapment:BAAALgADCgYJBgABLgADCgkJFAAJAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Er='Eriaeda:BAAALgAECgUJDQAAAA==.',
Es='Esen:BAAALgAECgQJBQABLgAECgkJMwAQAGwXAA==.Eskath:BAABLgAECn8hAAIQAAgJXh+aIwBMAgAQAAgJXh+aIwBMAgABLgAECgkJKgAaAJ4bAA==.Essential:BAACLgAFFH8IAAIEAAQJNgs1UAD+AAAEAAQJNgs1UAD+AAAuAAQKfx0AAgQACAnpErNyAH4BAAQACAnpErNyAH4BAAAA.',
Et='Eternalpain:BAAALgAECgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8hAAIbAAYJfxMlOgALAQAbAAYJfxMlOgALAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgQJCQAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgAECgEJAQABLgAECggJHQAWAJoOAA==.Ferrara:BAACLgAFFH8nAAQSAAgJfCPjAQAYAgASAAYJxiPjAQAYAgAgAAcJkx71CwBdAQAGAAEJtx+1HwBiAAAuAAQKfyAABCAACQnRIykGADoDACAACQmLIykGADoDAAYAAQn1I6ywAGIAABIAAQk6HgIsAEYAAAAA.',
Fi='Filthi:BAABLgAECn8XAAIOAAYJRiFuIAANAgAOAAYJRiFuIAANAgAAAA==.Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgUJBwAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgkJRAAMAGskAA==.Fisted:BAAALgAFFAEJAQABLgAFFAMJCAAKAGsbAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8bAAIHAAgJWCBbAAAIAwAHAAgJWCBbAAAIAwAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.Fluorita:BAAALgAECgEJAQAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Friedá:BAAALgAECgIJAwABLgAECgYJEgAJAAAAAA==.Frostednip:BAACLgAFFH8QAAMVAAQJJhpyUABBAQAVAAQJ3RlyUABBAQAjAAIJoRLmGQCNAAAuAAQKfyQAAyMACQnaIPoIAOgBABUACQm/IDo7AAwCACMABwmhG/oIAOgBAAAA.',
Ga='Gabaghoul:BAAALgAECgQJBAAAAA==.Gabiru:BAACLgAFFH8HAAQCAAMJ9gSERgCgAAACAAMJ9gSERgCgAAABAAMJvQcEIQCLAAAUAAEJlwEsDABCAAAuAAQKfxUAAwEACQlTE2YSABkCAAEACQlTE2YSABkCAAIAAQm0CZphADUAAAAA.Gadreeste:BAAALgAECgYJBwAAAA==.Galnarn:BAACLgAFFH8oAAIWAAcJyyD3BQAVAgAWAAcJyyD3BQAVAgAuAAQKfyEAAhYACQlkHfgNALQCABYACQlkHfgNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Garious:BAAALgAECgcJBwABLgAFFAUJEAAVAKMiAA==.Garjingo:BAAALgAECgUJBgABLgAECgkJNgAUAFQiAA==.Garlicbae:BAABLgAECn8UAAIaAAcJgAmaNwCzAAAaAAcJgAmaNwCzAAAAAA==.Garwulf:BAABLgAECn8UAAISAAkJ2wUUIgCIAQASAAkJ2wUUIgCIAQAAAA==.',
Ge='Gefaustet:BAABLgAECn81AAMfAAkJEBpHCwAvAgAfAAkJEBpHCwAvAgADAAEJEAlZeAApAAAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECgcJCQAAAA==.',
Go='Goatcheesè:BAAALgAECgIJBAAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAFFAEJAQAAAA==.Gorbachev:BAAALgAECgYJCAAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAABLgAECn8aAAMWAAkJAAnIKQBeAQAWAAkJAAnIKQBeAQAbAAMJHgKxnwAoAAAAAA==.Grayes:BAABLgAECn8fAAIaAAYJMQgVPwCVAAAaAAYJMQgVPwCVAAABLgAECgkJGgAWAAAJAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hail:BAAALgADCgUJBQABLgAECgYJBgAJAAAAAA==.Hallowshade:BAABLgAECn8XAAIkAAcJFhnlJQDKAQAkAAcJFhnlJQDKAQAAAA==.Hardran:BAABLgAECn8eAAIEAAgJ8Ax8fgBmAQAEAAgJ8Ax8fgBmAQAAAA==.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgAECgQJCQAAAA==.Hatreddyes:BAAALgAECgMJAwABLgAECggJCQAJAAAAAA==.Hatredyes:BAAALgAECggJCQAAAA==.Hattredyess:BAAALgAECgUJBQABLgAECggJCQAJAAAAAA==.',
He='Heatedsoul:BAAALgAECgEJAQAAAA==.Helare:BAABLgAECn8XAAIMAAkJ2xjkEABJAgAMAAkJ2xjkEABJAgAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAABLgAECn8nAAIlAAkJrQ2/EgB+AQAlAAkJrQ2/EgB+AQAAAA==.',
Hi='Hinatsuru:BAAALgAECgQJBAAAAA==.',
Ho='Holyzap:BAAALgAECgIJAgABLgAECgkJJQAPABEhAA==.Horsegirl:BAAALgAECgEJAgAAAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Huffmetoes:BAEALgADCgUJBQABLgAECgkJPwAHAIMZAA==.Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECggJCQAAAA==.Huulrokk:BAAALgADCgkJDAABLgAECgcJDgAJAAAAAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.Hyperreal:BAAALgAECgEJAQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgkJJwAKAJsbAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwAJAAAAAA==.Idlewild:BAEALgAECgEJAQABLgAECgcJFwALAI8LAA==.',
If='Iforgotnaaru:BAABLgAECn8XAAMNAAcJ4QuPbAAGAQANAAcJ4QuPbAAGAQAOAAQJtQodZgCkAAAAAA==.',
Ik='Ikedizzy:BAAALgAECgEJAQABLgAECgMJBAAJAAAAAA==.Ikeslice:BAAALgAECgMJBAAAAA==.Ikrys:BAAALgAECgYJDAAAAA==.',
Il='Illiae:BAACLgAFFH8JAAIOAAMJ/CJvHAAlAQAOAAMJ/CJvHAAlAQAuAAQKfy4AAg4ACAl8JDEJAMACAA4ACAl8JDEJAMACAAAA.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8rAAITAAgJxxP3KgCiAQATAAgJxxP3KgCiAQAAAA==.',
In='Incrdblestan:BAAALgAECgEJAQAAAA==.Innex:BAABLgAECn8nAAIVAAkJGx/pKQBRAgAVAAkJGx/pKQBRAgAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECgkJJwAVABsfAA==.Innexvoker:BAABLgAECn8YAAICAAgJag9jMABrAQACAAgJag9jMABrAQABLgAECgkJJwAVABsfAA==.Inpesca:BAAALgADCgUJBQABLgAECgYJBgAJAAAAAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgYJCwAAAA==.',
Ir='Iridescent:BAAALgAECgIJAgAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAABLgAECn8eAAIgAAcJuQ6nEgAnAQAgAAcJuQ6nEgAnAQAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itzmuffin:BAABLgAECn8oAAINAAgJyRL+SAB9AQANAAgJyRL+SAB9AQAAAA==.Itzpie:BAABLgAECn81AAIPAAkJNxY6RQAFAgAPAAkJNxY6RQAFAgAAAA==.',
Ja='Jadandotz:BAAALgADCggJAgAAAA==.Jagtat:BAABLgAECn8gAAMVAAcJPBAbjwA/AQAVAAcJPBAbjwA/AQAXAAUJcQf/QACAAAAAAA==.Jakeakuma:BAABLgAECn8UAAIQAAkJBAwlXwCsAQAQAAkJBAwlXwCsAQAAAA==.Jascob:BAABLgAECn8bAAImAAUJoQdUFgC8AAAmAAUJoQdUFgC8AAAAAA==.Jasonborne:BAAALgAECgQJBAAAAA==.Jaynne:BAAALgADCgcJCAAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAAALgAECgcJCQAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn9QAAIWAAkJsB+1BQDcAgAWAAkJsB+1BQDcAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8lAAIbAAgJGiFcCAD0AgAbAAgJGiFcCAD0AgABLgAFFAQJBAAJAAAAAA==.Junfan:BAAALgAECgcJCQAAAA==.',
['Jà']='Jàckblack:BAAALgAECgYJDAAAAA==.',
Ka='Kaashaa:BAACLgAFFH8QAAIGAAQJFxnOJgBYAQAGAAQJFxnOJgBYAQAuAAQKf0AAAgYACQnLIScNAN8CAAYACQnLIScNAN8CAAAA.Kaelsgf:BAAALgAECgcJDAAAAA==.Kahllan:BAABLgAECn8xAAMMAAkJ5Q/yIQCsAQAMAAkJ5Q/yIQCsAQALAAEJLhSMwgA8AAAAAA==.Kahnigitt:BAABLgAECn8XAAIVAAcJhwqYnQAnAQAVAAcJhwqYnQAnAQAAAA==.Kalsifire:BAAALgADCgcJCgAAAA==.Kataltoholic:BAABLgAECn8aAAIPAAYJOAG5HgFqAAAPAAYJOAG5HgFqAAAAAA==.Katrath:BAAALgADCgMJBgAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIeAAYJCxp5UAC1AQAeAAYJCxp5UAC1AQAAAA==.Kaýhás:BAAALgADCgYJBgAAAA==.',
Ke='Kelinïsha:BAABLgAECn8pAAIPAAgJJQrMlwBEAQAPAAgJJQrMlwBEAQAAAA==.Kelynna:BAABLgAECn8pAAIHAAgJDhwqEQBNAgAHAAgJDhwqEQBNAgAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJBQAAAA==.',
Kh='Khaodemus:BAAALgAECggJCQAAAA==.Khellder:BAAALgAECgUJCQABLgAECgkJEQAJAAAAAA==.Khelldyr:BAAALgAECggJCAABLgAECgkJEQAJAAAAAA==.Khellrond:BAAALgAECgkJEQAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiffira:BAAALgAECgYJBgABLgAECgkJKQAeAEUWAA==.Kiiras:BAABLgAECn8vAAIPAAgJ9A1QfQB3AQAPAAgJ9A1QfQB3AQAAAA==.Kimbodh:BAACLgAFFH8dAAIeAAUJOSSHHwCcAQAeAAUJOSSHHwCcAQAuAAQKfyYAAh4ACAkOJIsNANACAB4ACAkOJIsNANACAAEuAAEKAwkBAAkAAAAA.Kimoora:BAAALgAECgQJBAAAAA==.Kimshady:BAAALgADCgEJAQABLgAECgQJBAAJAAAAAA==.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8wAAIeAAkJ+BAGRgCpAQAeAAkJ+BAGRgCpAQAAAA==.',
Kl='Klefthoof:BAABLgAECn83AAMNAAgJVxRpLAD5AQANAAgJVxRpLAD5AQAOAAIJcASzkgA/AAAAAA==.',
Ko='Kodey:BAABLgAECn8hAAIYAAkJ3RKtBwDKAQAYAAkJ3RKtBwDKAQABLgAFFAQJDwAYAJMGAA==.Kordy:BAAALgAECgkJAQAAAA==.Korey:BAAALgAECgEJAQAAAA==.',
Kr='Kraniah:BAAALgAECgcJDgAAAA==.Krelon:BAAALgAECgEJAQAAAA==.Krimboz:BAABLgAECn8uAAIQAAkJ+hkoHwBjAgAQAAkJ+hkoHwBjAgAAAA==.Krimbrouge:BAAALgAECgYJCAAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8sAAISAAgJXho2EAApAgASAAgJXho2EAApAgAAAA==.Krìsta:BAACLgAFFH8GAAMZAAIJ7QIAEAB1AAAZAAIJ7QIAEAB1AAAQAAEJ8QAEyAAxAAAuAAQKfx4AAxkACAncDFgNAGABABkABwleDlgNAGABABAABwknBK66AM4AAAAA.',
Ku='Kuanshuwo:BAABLgAECn8VAAMIAAgJ7wmfMwBCAQAIAAgJ7wmfMwBCAQAHAAYJfQZMTgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
La='Lanwulf:BAAALgAECgYJEQAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAACLgAFFH8KAAIIAAQJUxXiFgAdAQAIAAQJUxXiFgAdAQAuAAQKfxgAAggACQlvHb4XACYCAAgACQlvHb4XACYCAAAA.Legaloas:BAABLgAECn8tAAMGAAgJ6R+zJQA/AgAGAAgJ6R+zJQA/AgAgAAUJGxHDFgD0AAAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAABLgAECn8UAAIbAAcJZgxvOgAKAQAbAAcJZgxvOgAKAQAAAA==.Leonarde:BAACLgAFFH8PAAMGAAQJKBlJOwAsAQAGAAQJIBlJOwAsAQAgAAMJ2Q/RFQDuAAAuAAQKfyIABCAACQkZGb8gACACACAACAkSF78gACACAAYABQl/GBhoAGYBABIAAQlWAKwzAA0AAAAA.Levitt:BAABLgAECn8WAAIQAAYJjhHbjgAYAQAQAAYJjhHbjgAYAQABLgAECgcJEAAJAAAAAA==.Leyla:BAAALgADCgkJCQAAAA==.',
Li='Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn80AAIbAAkJbhYMFQAGAgAbAAkJbhYMFQAGAgAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liquid:BAAALgAECgEJAQAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgYJDwAAAA==.',
Ll='Llevanya:BAABLgAECn88AAIEAAkJUxDmVQC+AQAEAAkJUxDmVQC+AQAAAA==.Llinaigh:BAACLgAFFH8HAAIGAAMJzhcLTwD2AAAGAAMJzhcLTwD2AAAuAAQKfxkAAgYACQmDFVw3APUBAAYACQmDFVw3APUBAAAA.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAgABLgAECgkJNAATAPwfAA==.Lomu:BAABLgAECn8qAAQaAAkJnhskCQBIAgAaAAkJnhskCQBIAgALAAEJ7Q5JzwAvAAAMAAEJigQomAAhAAAAAA==.Loredalso:BAAALgAECgEJAQAAAA==.Lorenitha:BAAALgAECgEJAQABLgAFFAQJDQAEABccAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
['Lê']='Lêdrollan:BAAALgAECgIJAgABLgAFFAQJCgAIAFMVAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAFFAMJCAAKAGsbAA==.Magicdreams:BAABLgAECn80AAIMAAkJNAmuLQBdAQAMAAkJNAmuLQBdAQAAAA==.Malificent:BAAALgADCgQJCAAAAA==.Malmorte:BAABLgAECn8WAAIVAAYJMRUHowA6AQAVAAYJMRUHowA6AQAAAA==.Malorane:BAABLgAECn8vAAIXAAkJFhshCwBjAgAXAAkJFhshCwBjAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgAECgEJAQAAAA==.Marihuano:BAAALgAFFAIJAgAAAA==.Marisi:BAAALgADCggJCAABLgAECgcJBwAJAAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIkAAkJ0R2YEAAbAgAkAAkJ0R2YEAAbAgAAAA==.Materiaga:BAABLgAECn8iAAQCAAgJEhFiLQB8AQACAAgJwBBiLQB8AQABAAYJFQtdKQAoAQAUAAMJjw8IFwCaAAAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8xAAIEAAkJKCFnDgDpAgAEAAkJKCFnDgDpAgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMiAAkJGxU2BgCWAgAiAAkJGxU2BgCWAgAOAAgJyg/QQAAgAQAAAA==.',
Me='Medalla:BAAALgADCgYJBgAAAA==.Meerchi:BAABLgAECn8wAAMPAAkJCBmYNgA3AgAPAAkJCBmYNgA3AgAnAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Meiriie:BAAALgAECgEJAQAAAA==.Meowkai:BAAALgAECgYJBgABLgAECgkJJwASAA0lAA==.Mesthos:BAAALgAECgcJDAABLgAECgkJKAARACwmAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8lAAICAAgJlBKOGgD2AQACAAgJlBKOGgD2AQAAAA==.',
Mi='Miciah:BAAALgAECgQJBAAAAA==.Mickieta:BAABLgAECn81AAIEAAkJwh+HGACmAgAEAAkJwh+HGACmAgAAAA==.Microsurge:BAACLgAFFH8HAAIPAAQJ4Aj1aAAKAQAPAAQJ4Aj1aAAKAQAuAAQKfx0AAg8ACAkiHdslANsCAA8ACAkiHdslANsCAAAA.Mikalau:BAABLgAECn8vAAIGAAkJ1hZZIwBLAgAGAAkJ1hZZIwBLAgAAAA==.Mikaluu:BAABLgAECn8dAAIQAAYJEgiQsQDdAAAQAAYJEgiQsQDdAAAAAA==.Miqkail:BAAALgAECggJCgABLgAECgkJKAARACwmAA==.Missteek:BAAALgAECgYJDwABLgAECgkJNgAUAFQiAA==.Mistrunner:BAAALgAECgMJAwAAAA==.Mistspell:BAACLgAFFH8PAAIIAAQJpQ+lGwD+AAAIAAQJpQ+lGwD+AAAuAAQKfyAAAwgACQnXHeQOAJUCAAgACQnXHeQOAJUCAAcAAwklBoFqAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwABLgAECgkJJwAKAJsbAA==.Mognel:BAABLgAECn82AAIQAAkJxxzfJwA3AgAQAAkJxxzfJwA3AgAAAA==.Mogrungar:BAACLgAFFH8FAAINAAMJAQwjUgCaAAANAAMJAQwjUgCaAAAuAAQKfygAAg0ACQl3FJQkACUCAA0ACQl3FJQkACUCAAAA.Moistdk:BAAALgAECgEJAQAAAA==.Moisten:BAABLgAECn8eAAIOAAkJQyCfBwDYAgAOAAkJQyCfBwDYAgAAAA==.Mokuo:BAAALgAFFAIJAgAAAA==.Monklee:BAAALgAECgEJAgAAAA==.Moomootus:BAABLgAECn8qAAMEAAkJTxj1RADsAQAEAAgJdxf1RADsAQAKAAQJ/B7GOgBSAQAAAA==.Mordakttaa:BAAALgADCgMJAwAAAA==.Morgalea:BAAALgAECgcJAQAAAA==.Motoraxe:BAAALgAFFAIJAgAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIbAAgJRyBsDQClAgAbAAgJRyBsDQClAgABLgAFFAQJBwAeAF8MAA==.Mystynight:BAAALgAECgYJDAAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAABLgAECn8lAAIOAAgJEA9yOQBCAQAOAAgJEA9yOQBCAQAAAA==.Naggs:BAAALgAECgkJCAAAAA==.Nagini:BAABLgAECn8fAAIQAAgJdwgGgwAuAQAQAAgJdwgGgwAuAQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn8/AAMHAAkJgxlRGwDfAQAHAAcJGRlRGwDfAQAIAAkJtBH1OgAeAQAAAA==.Nietzcha:BAAALgAECgMJBAAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAABLgAECn8kAAMMAAgJ7RZzGwDhAQAMAAgJ7RZzGwDhAQAlAAUJRw3kMgB+AAAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nilfgard:BAAALgAECgcJEAAAAA==.Nioh:BAABLgAECn8iAAIeAAkJxRZOLQAHAgAeAAkJxRZOLQAHAgAAAA==.Nivix:BAAALgAECgEJAQAAAA==.',
No='Noodles:BAABLgAECn8nAAIeAAgJnwiRkADxAAAeAAgJnwiRkADxAAAAAA==.Nordrydd:BAAALgAECggJDgABLgAFFAYJFgAcACQZAA==.Nordrydsh:BAAALgAECgQJBQABLgAFFAYJFgAcACQZAA==.',
Nu='Nuggs:BAABLgAECn8YAAIlAAkJzBAcDwCyAQAlAAkJzBAcDwCyAQAAAA==.Nuhpie:BAACLgAFFH8XAAMDAAcJhw4FIgDTAAADAAQJugsFIgDTAAATAAMJUxHyMgDRAAAuAAQKfx4AAwMACQlfHT8eAGABAAMABQmuGj8eAGABABMABQlsHE9JABcBAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8lAAIVAAkJax/gFwCvAgAVAAkJax/gFwCvAgAAAA==.',
Od='Odelay:BAAALgADCgEJAQAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAwAAAA==.',
Ol='Olimdar:BAACLgAFFH8pAAINAAgJgSRKAAA7AwANAAgJgSRKAAA7AwAuAAQKfycAAw0ACQlvJUsAAM8DAA0ACQlvJUsAAM8DAA4AAQmSHaiCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBwAAAA==.',
Oo='Oopositive:BAAALgADCgYJBgAAAA==.Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Orgarrot:BAAALgADCgYJBgABLgAECggJCQAJAAAAAA==.Oricelle:BAABLgAECn8pAAIeAAkJRRZTKAAeAgAeAAkJRRZTKAAeAgAAAA==.Oridis:BAAALgAECgkJBwAAAA==.Oryon:BAEBLgAECn8zAAIZAAkJnRSnBwDjAQAZAAkJnRSnBwDjAQAAAA==.',
Ov='Ovarb:BAABLgAECn8qAAMXAAkJkRjVEADyAQAXAAkJkRjVEADyAQAVAAUJrQ4r0QDdAAAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDQAAAA==.Palasexo:BAAALgAECgUJBQABLgAFFAIJAgAJAAAAAA==.Palldude:BAAALgADCgQJBQAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Peachie:BAAALgADCgEJAQAAAA==.Pesti:BAACLgAFFH8ZAAIkAAQJsRbCFQBPAQAkAAQJsRbCFQBPAQAuAAQKf00AAiQACQlnI3MCACwDACQACQlnI3MCACwDAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8+AAINAAkJQiOuAwB4AwANAAkJQiOuAwB4AwAAAA==.',
Pi='Pissedwolf:BAAALgAECgUJBgAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAABLgAECn8eAAIWAAgJCRAdKQBiAQAWAAgJCRAdKQBiAQAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAACLgAFFH8QAAIPAAQJxBZbTABBAQAPAAQJxBZbTABBAQAuAAQKf0cABA8ACQkJIgQNAAwDAA8ACQmIIQQNAAwDACgABQnyFiQMABABACcAAQmjEFUSADEAAAAA.Proctologist:BAABLgAECn8sAAMWAAkJDRkZEQAoAgAWAAkJ6RcZEQAoAgAbAAQJYRMBQADxAAAAAA==.Proserpìne:BAABLgAECn86AAIeAAkJMgzKVQB5AQAeAAkJMgzKVQB5AQAAAA==.',
Ps='Psychojester:BAACLgAFFH8QAAIiAAQJ8xhvBgBDAQAiAAQJ8xhvBgBDAQAuAAQKf0MAAiIACQk2IRYCAPwCACIACQk2IRYCAPwCAAAA.Psylir:BAAALgAECgQJDgAAAA==.Psypra:BAAALgAECgUJBgAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAABLgAECn8WAAIPAAUJihsItgATAQAPAAUJihsItgATAQAAAA==.',
Py='Pydge:BAAALgAECgEJAQAAAA==.',
Qu='Quod:BAAALgAECgQJBAAAAA==.Quoril:BAACLgAFFH8FAAIPAAIJDQ9CmACRAAAPAAIJDQ9CmACRAAAuAAQKfz8AAw8ACQkLIegOAP4CAA8ACQkLIegOAP4CACgAAQmXIHkZAEwAAAEuAAUUBgkfAAYA4BoA.',
Ra='Raijyu:BAABLgAECn9CAAMHAAkJzR/ABAArAwAHAAkJzR/ABAArAwAIAAcJVRV+IwC8AQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECgkJNgAMAM8WAA==.Rainstormin:BAABLgAECn82AAMMAAkJzxa9FAAgAgAMAAkJzxa9FAAgAgAaAAYJxgm4OwCiAAAAAA==.Rakarra:BAABLgAECn8bAAMLAAgJ2wvnTgBJAQALAAgJ2wvnTgBJAQAMAAcJYQcPTQD2AAAAAA==.Ranalia:BAAALgADCgcJCgAAAA==.Rawrstance:BAABLgAECn84AAMXAAkJABrLGACPAQAXAAkJ/w/LGACPAQAVAAcJoRy2bACDAQABLgADCgkJFAAJAAAAAA==.Razgrize:BAACLgAFFH8KAAIPAAMJUxeXcADxAAAPAAMJUxeXcADxAAAuAAQKfzAAAg8ACQmeG20hAJICAA8ACQmeG20hAJICAAAA.',
Re='Redraggon:BAAALgAECgYJBgAAAA==.Reecalled:BAAALgADCgUJBQABLgAECggJGgACAGIaAA==.Reeshan:BAABLgAECn8fAAMEAAkJ1yP0DAD1AgAEAAkJ1yP0DAD1AgAKAAIJaxRLcABnAAAAAA==.Reilin:BAAALgAECgcJCwAAAA==.Remsham:BAABLgAECn8nAAIiAAkJxg27DgC4AQAiAAkJxg27DgC4AQAAAA==.Reniel:BAAALgAECgYJBgABLgAECgkJMAAeAPgQAA==.Renwyck:BAABLgAECn8oAAIRAAkJLCZJAABlAwARAAkJLCZJAABlAwAAAA==.Revengemoon:BAACLgAFFH8RAAIEAAQJsxIWQwAYAQAEAAQJsxIWQwAYAQAuAAQKfyMAAgQACQmVGsApAH4CAAQACQmVGsApAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgAJAAAAAA==.Ringberg:BAACLgAFFH8IAAIKAAMJaxvKKQDPAAAKAAMJaxvKKQDPAAAuAAQKfxcAAwoABwlSH9EXAD8CAAoABwlSH9EXAD8CAAQAAwmmFD//AKoAAAAA.',
Ro='Robane:BAABLgAECn8UAAIEAAUJCA/03ADVAAAEAAUJCA/03ADVAAAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Rockette:BAAALgADCgYJBgAAAA==.Ronburgundy:BAAALgAECgMJBQAAAA==.Rouen:BAABLgAECn80AAMNAAkJ2xqTEwCjAgANAAkJ2xqTEwCjAgAiAAgJiiJrBgBmAgAAAA==.',
Ru='Rubidea:BAAALgADCgQJBgAAAA==.Ruckus:BAEBLgAECn8XAAQLAAcJjwsIWgAgAQALAAcJjwsIWgAgAQAaAAMJnAYWVQBTAAAMAAEJhQUKmQAgAAAAAA==.Ruder:BAAALgAECgMJBAABLgAECggJCQAJAAAAAA==.Rutabaga:BAAALgAECgUJCAAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIIAAkJxBtnEQBzAgAIAAkJxBtnEQBzAgAAAA==.',
Sa='Saintanic:BAAALgADCgkJFAAAAA==.Sandkat:BAABLgAECn9BAAITAAkJZCKXBQD/AgATAAkJZCKXBQD/AgAAAA==.Sanstian:BAAALgAECgUJDQAAAA==.Santamou:BAAALgAECgIJBAAAAA==.Saraelin:BAABLgAFFH8IAAIQAAIJ8ACosQBNAAAQAAIJ8ACosQBNAAAAAA==.Saray:BAAALgAECgcJEgAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAYJEwATAO4QAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgYJDgAAAA==.Serahstia:BAABLgAECn8fAAIPAAgJ9xUPYAC5AQAPAAgJ9xUPYAC5AQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shadowmeld:BAAALgAECgEJAQAAAA==.Shadysadie:BAAALgAECgcJDwAAAA==.Shaiy:BAAALgAECgcJEAAAAA==.Shammymoe:BAAALgAECgEJAQAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwAJAAAAAA==.Shiifthappen:BAAALgAECgEJAQAAAA==.Shinta:BAAALgAECgYJEQAAAA==.Shirtles:BAABLgAECn8YAAIOAAYJggOabQCPAAAOAAYJggOabQCPAAAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shpik:BAAALgADCgUJCQAAAA==.Shèp:BAABLgAECn8ZAAIKAAgJFhESLQCgAQAKAAgJFhESLQCgAQAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIOAAUJ/hmfAwCvAQAOAAUJ/hmfAwCvAQABLgAFFAYJDgASACUWAA==.Siffrin:BAAALgAECgIJAgAAAA==.Siink:BAAALgAFFAEJAQAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8lAAMQAAgJnhWXbwBWAQAQAAYJ0hKXbwBWAQAZAAUJJRZ3GADqAAABLgAECggJJQACAJQSAA==.Sinkingship:BAAALgAECgUJBQAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAABLgAECn8gAAIXAAkJFyCVBQDIAgAXAAkJFyCVBQDIAgAAAA==.',
Sk='Skaterboi:BAAALgAECgYJBgAAAA==.Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sliy:BAAALgAECgIJAgAAAA==.Sloothe:BAAALgADCgQJBAAAAA==.Sloothi:BAAALgAECgEJAQAAAA==.Slyveria:BAAALgAECgMJBAAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.',
So='Sosorry:BAAALgADCgIJAgAAAA==.Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAABLgAECn8WAAIEAAkJgRpOMgAsAgAEAAkJgRpOMgAsAgAAAA==.',
Sp='Sprodage:BAABLgAECn86AAIKAAkJpBdXFgBNAgAKAAkJpBdXFgBNAgAAAA==.',
St='Staggrsaurus:BAAALgAECgIJAwABLgAECgMJBAAJAAAAAA==.Stanil:BAABLgAECn8nAAMGAAgJ0QhOagBhAQAGAAgJ0QhOagBhAQAgAAEJWwAkmwAVAAAAAA==.Stayfrosty:BAAALgAECgcJDAAAAA==.Stellare:BAABLgAECn8wAAIdAAkJHRcbEAAWAgAdAAkJHRcbEAAWAgAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Stinklines:BAAALgAECgEJAgABLgAECgkJNgAUAFQiAA==.Strangetame:BAAALgADCgEJAQAAAA==.Striest:BAAALgAECgMJAwAAAA==.Styló:BAAALgAECggJEwAAAA==.',
Su='Suetonius:BAACLgAFFH8NAAIVAAQJRR8SNwB5AQAVAAQJRR8SNwB5AQAuAAQKfxQAAxUACAlXJMoPAOYCABUACAlXJMoPAOYCACMAAgk4E8MqAGYAAAAA.Suguru:BAAALgAECggJCQAAAA==.Sungsuf:BAAALgAECgEJAQAAAA==.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8rAAIPAAkJaBpUNABAAgAPAAkJaBpUNABAAgAAAA==.Suraschi:BAAALgAECgYJCwABLgAECgkJKwAPAGgaAA==.',
Sv='Svelda:BAABLgAECn8gAAMIAAYJrQv1QgD7AAAIAAYJrQv1QgD7AAAhAAUJmAUITQC8AAAAAA==.',
Sw='Swisscake:BAABLgAECn9EAAIMAAkJayRiAgBJAwAMAAkJayRiAgBJAwAAAA==.',
Sy='Sylain:BAAALgAECgYJEgABLgAECgkJFQAkAKEKAA==.Synwav:BAAALgADCgEJAQAAAA==.',
Ta='Tannatax:BAABLgAECn8vAAINAAkJZQZoVgBMAQANAAkJZQZoVgBMAQAAAA==.Tashah:BAAALgADCgUJBQAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAAJAAAAAA==.Tekvet:BAAALgAECgkJCQAAAA==.',
Th='Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8jAAMPAAkJnBVlTgDqAQAPAAkJnBVlTgDqAQAnAAEJGgEOFgAKAAAAAA==.Thewretch:BAABLgAECn85AAIQAAkJhyLGBgAgAwAQAAkJhyLGBgAgAwAAAA==.Thibble:BAAALgADCgYJBgAAAA==.Thumpthump:BAABLgAECn8nAAQSAAkJQBgbEwALAgAgAAYJwx6nIgARAgASAAkJMhAbEwALAgAGAAEJqQ7dGgE5AAAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEBLgAECn8WAAIOAAcJYQ0GQgAbAQAOAAcJYQ0GQgAbAQABLgAECgcJFwALAI8LAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Titiera:BAABLgAECn8gAAIGAAgJCRfjOgDoAQAGAAgJCRfjOgDoAQAAAA==.',
To='Toastnbutta:BAABLgAECn8mAAILAAkJ9xmRFwCBAgALAAkJ9xmRFwCBAgAAAA==.Tolten:BAABLgAECn8eAAIEAAgJ3RmUMQBcAgAEAAgJ3RmUMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgYJCAAAAA==.Traumatism:BAAALgAECgcJDAAAAA==.Trevor:BAABLgAECn9BAAImAAkJUhglBABQAgAmAAkJUhglBABQAgAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAACLgAFFH8IAAMlAAMJjBIqDgDDAAAlAAMJ9wwqDgDDAAAaAAEJXBmmLgBMAAAuAAQKfx4AAyUACAmAIAIFAJoCACUACAmAIAIFAJoCABoABgk0HPYWAIcBAAEuAAUUBQkVABcAAhwA.Tsura:BAAALgAFFAEJAQAAAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Ty='Tylaesh:BAAALgAECgYJDwAAAA==.',
Un='Unclepeepers:BAACLgAFFH8VAAIcAAQJ4iDZGwBlAQAcAAQJ4iDZGwBlAQAuAAQKfy4AAxsACQkPIwAPAE4CABsACAmOIgAPAE4CABwACQm0G8cgAAICAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAABLgAECn8XAAIVAAcJ3QuMwADzAAAVAAcJ3QuMwADzAAAAAA==.',
Ur='Urtag:BAACLgAFFH8UAAMgAAgJVBOGCwCSAQAgAAcJRA2GCwCSAQAGAAQJ7xLdJwBWAQAuAAQKfxUAAyAACAnyFboqANYBACAACAkZFboqANYBAAYAAgm6F23LAJ4AAAAA.',
Ut='Uthgar:BAAALgAECgMJAwAAAA==.',
Va='Vadge:BAAALgADCgcJBwABLgADCgkJFAAJAAAAAA==.Vaeryn:BAABLgAECn8WAAIGAAcJ/xPVWQCLAQAGAAcJ/xPVWQCLAQABLgAFFAMJBwAhANIKAA==.Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAACLgAFFH8HAAIhAAMJ0grjLwC4AAAhAAMJ0grjLwC4AAAuAAQKf2wAAyEACAlXHyIJANYCACEACAlXHyIJANYCAAgABwnEDwcxAFABAAAA.Valryn:BAABLgAECn8WAAMVAAcJKAs5wgDxAAAVAAcJKAs5wgDxAAAXAAEJxgH7TwAVAAABLgAFFAMJBwAhANIKAA==.Valtar:BAABLgAECn8gAAINAAkJoBy+GAB4AgANAAkJoBy+GAB4AgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAACLgAFFH8HAAMVAAUJRRSUUwA8AQAVAAUJRRSUUwA8AQAXAAIJxRAkDgCJAAAuAAQKfzAAAxUACQmJI8YFAEcDABUACQmJI8YFAEcDABcACAntHUsPABcCAAAA.',
Ve='Velra:BAAALgADCgEJAQABLgAFFAMJBwAhANIKAA==.Veraalyn:BAABLgAECn8dAAMOAAgJHhFvQQAeAQAOAAgJHhFvQQAeAQANAAMJxwiifgCZAAAAAA==.',
Vi='Vicsen:BAABLgAECn8gAAIQAAkJdQX+eQBAAQAQAAkJdQX+eQBAAQAAAA==.Vikaya:BAAALgAECgYJCAAAAA==.Vilevixon:BAABLgAECn8hAAMIAAkJ4hYcFgASAgAIAAkJ4hYcFgASAgAhAAMJxgetWQCBAAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Vo='Voidasuras:BAAALgAECgEJAQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAAJAAAAAA==.Wanlok:BAAALgAECgQJCQAAAA==.Wantoo:BAAALgAECgYJBgAAAA==.Warlokip:BAAALgAECgkJCgAAAA==.Warotar:BAAALgAECgIJAgAAAA==.Warriorlobo:BAABLgAECn80AAQTAAkJ/B+yBwDcAgATAAkJ/B+yBwDcAgADAAYJ7RBfLwAAAQAfAAEJ6A5iVQAjAAAAAA==.Warvision:BAAALgAFFAEJAQAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAABLgAECn8gAAIGAAgJeAzDRgCWAQAGAAgJeAzDRgCWAQAAAA==.Wildside:BAABLgAECn8XAAMGAAYJJh58VgCTAQAGAAYJJh58VgCTAQASAAYJCxalJgBlAQAAAA==.',
Wu='Wujifei:BAAALgAFFAIJAwAAAA==.Wulffgar:BAAALgAECgQJBAAAAA==.',
['Wì']='Wìldthìng:BAAALgAECgUJCgAAAA==.',
Xa='Xandronys:BAAALgAECgkJDAAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECggJCgAAAA==.Xenie:BAAALgAECggJEgAAAA==.',
Xi='Xinema:BAAALgAECgQJBAAAAA==.Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgAECgUJCQAAAA==.',
Yd='Ydeatho:BAAALgAFFAMJAwAAAA==.',
Ye='Yeet:BAABLgAECn8bAAIkAAkJNBj5IgDhAQAkAAkJNBj5IgDhAQAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgMJBgAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgAECgMJBAAAAA==.Zalanna:BAAALgADCgMJAwAAAA==.Zalckar:BAABLgAECn8bAAMKAAkJcBIZRQBjAQAKAAkJcBIZRQBjAQAEAAEJYQ7KgwEvAAAAAA==.Zanos:BAAALgADCgUJBQAAAA==.Zarayssa:BAAALgADCgQJBAAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zebracakes:BAAALgAECgEJAQABLgAECgkJQwARAOMlAA==.Zeeva:BAABLgAECn8UAAMYAAYJ9x/eCgCEAQAYAAYJiR3eCgCEAQAZAAMJ+h04JQB/AAAAAA==.Zendead:BAABLgAECn8jAAIbAAkJCiNNBwDLAgAbAAkJCiNNBwDLAgAAAA==.Zeppeli:BAAALgAECgMJAwAAAA==.Zerkces:BAAALgADCgIJAgAAAA==.',
Zi='Zionspartan:BAABLgAECn8xAAIGAAkJAQ/dPgDbAQAGAAkJAQ/dPgDbAQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugpriest:BAAALgAECgQJBAAAAA==.Zugzugshaman:BAABLgAECn8nAAQNAAkJLxfTHABZAgANAAkJLxfTHABZAgAOAAQJrwOHbgCJAAAiAAEJYQD/QQAdAAAAAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Êï']='Êïñstëïn:BAAALgAECgEJAQAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8dAAIWAAgJmg7QLgBCAQAWAAgJmg7QLgBCAQAAAA==.',
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
