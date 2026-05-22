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

local lookup = {'Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Monk-Windwalker','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','Hunter-Survival','Monk-Mistweaver','Warrior-Fury','Evoker-Devastation','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Druid-Guardian','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Subtlety','Druid-Feral','Rogue-Assassination','Mage-Fire','Mage-Arcane','Priest-Discipline',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adorraa:BAAALgAECgQJBAAAAA==.Adoryn:BAAALgADCgYJCQAAAA==.Adowyrm:BAACLgAFFH8ZAAMBAAcJshfFBQDzAQABAAYJkhnFBQDzAQACAAEJkQwOQABTAAAuAAQKfyEAAwEACQm1IUcCAFEDAAEACQm1IUcCAFEDAAIABgnLHfscAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.Adrielle:BAAALgADCgkJDAAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECgkJHQADAIgcAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAECgUJDgABLgAECggJJQAEABghAA==.',
Ai='Airali:BAABLgAECn8XAAMFAAkJ/hNrZAC4AQAFAAkJ/hNrZAC4AQAGAAMJiQjTNwBiAAAAAA==.Airedale:BAABLgAECn8fAAIHAAcJdxC4SQBrAQAHAAcJdxC4SQBrAQAAAA==.',
Ak='Akairo:BAABLgAECn8xAAMIAAkJACSCAgBBAwAIAAkJACSCAgBBAwAJAAgJrREqHQCGAQAAAA==.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgAECgUJBQABLgAECgkJJQACAMcfAA==.Alderbaran:BAAALgADCgUJBQAAAA==.Alexanderxl:BAAALgAECgYJDgABLgAECggJAwAKAAAAAA==.Aleybobwa:BAABLgAECn8fAAMLAAkJjRJyHQDLAQALAAkJjRJyHQDLAQAFAAEJYwiPUgErAAAAAA==.Alody:BAAALgADCgMJAwAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAABLgAECn8eAAILAAkJMRoBCgClAgALAAkJMRoBCgClAgAAAA==.Amulius:BAABLgAECn80AAIFAAkJAiXxAgBIAwAFAAkJAiXxAgBIAwAAAA==.',
An='Anderdingus:BAAALgADCgUJBQAAAA==.Andormath:BAAALgAECgQJBQAAAA==.Andramedae:BAABLgAECn8hAAIMAAgJRxZCIAD+AQAMAAgJRxZCIAD+AQAAAA==.Angerissues:BAAALgADCgkJCQAAAA==.Angyavocado:BAAALgADCgkJCQAAAA==.Anoki:BAABLgAECn8wAAMNAAkJ1xkKDwCKAgANAAkJ1xkKDwCKAgAOAAEJgQuoegAsAAAAAA==.',
Ao='Aolus:BAACLgAFFH8PAAIPAAQJzxZ8EgAzAQAPAAQJzxZ8EgAzAQAuAAQKfxsAAg8ACQkVHDETAHsCAA8ACQkVHDETAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgAECgEJAQAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJAwAKAAAAAA==.Arcaina:BAABLgAECn8WAAIQAAcJhwm0hQAwAQAQAAcJhwm0hQAwAQAAAA==.Ares:BAAALgADCgcJBwABLgAECggJJwARABkWAA==.Arez:BAABLgAECn8nAAIRAAgJGRbzNgC9AQARAAgJGRbzNgC9AQAAAA==.Arilass:BAAALgADCgIJBAAAAA==.Armis:BAAALgADCgEJAQABLgAECgkJMQASAGMlAA==.Artèmís:BAABLgAECn8nAAITAAkJDCUvAQAuAwATAAkJDCUvAQAuAwABLgAECgkJNgAUAB0fAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Ashtongue:BAAALgADCggJCAAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athenä:BAAALgAECgIJAgAAAA==.',
Au='Aura:BAAALgAECgQJBAAAAA==.',
Az='Azaekho:BAABLgAECn8kAAINAAkJcxQIKgDmAQANAAkJcxQIKgDmAQAAAA==.',
Ba='Baalzak:BAAALgADCgYJCgAAAA==.Backfliphoe:BAAALgAECgcJBwAAAA==.Badoosh:BAABLgAECn8kAAIVAAgJCB2aGACHAgAVAAgJCB2aGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Bajablaster:BAABLgAECn8kAAQWAAgJXSC1AQCSAgAWAAgJXSC1AQCSAgACAAMJ5BD7TACdAAABAAEJMAu6MAAtAAAAAA==.Baliw:BAAALgADCgUJBAAAAA==.Balto:BAAALgADCgMJAwAAAA==.',
Bb='Bbl:BAECLgAFFH8QAAIOAAQJ7BD6FQAdAQAOAAQJ7BD6FQAdAQAuAAQKfyUAAg4ACQnWIFgKAPACAA4ACQnWIFgKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8PAAIQAAQJ2xH4PgA8AQAQAAQJ2xH4PgA8AQAuAAQKfyMAAhAACQnDGZo7AIgCABAACQnDGZo7AIgCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAAALgAFFAEJAgAAAA==.',
Bh='Bhain:BAAALgADCgcJDQABLgAFFAMJBgAFAIMQAA==.',
Bi='Bieorne:BAABLgAECn8tAAIXAAgJmyDcGgBiAgAXAAgJmyDcGgBiAgAAAA==.',
Bl='Blastbane:BAACLgAFFH8LAAIRAAQJXQvqOwAVAQARAAQJXQvqOwAVAQAuAAQKfxQAAhEACQnsFEYjABYCABEACQnsFEYjABYCAAAA.Bloodwrath:BAAALgAECgEJAQAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAACLgAFFH8FAAIRAAIJ5R7/YQCwAAARAAIJ5R7/YQCwAAAuAAQKfxgAAxEACQnvHP4PAPoCABEACQnvHP4PAPoCABgAAQkAAAw8AAAAAAEuAAUUAwkHAAsAaxsA.Boondocks:BAABLgAECn8kAAMRAAgJcxoNXQBJAQARAAUJNRYNXQBJAQAZAAQJMSCqEADgAAAAAA==.',
Br='Braca:BAAALgADCgEJAgAAAA==.Braelek:BAAALgADCgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAABLgAECn8XAAIaAAgJBhDRIQBbAQAaAAgJBhDRIQBbAQABLgAECgkJJQAbANUZAA==.Brielle:BAABLgAECn8kAAIHAAgJ/BamLwDzAQAHAAgJ/BamLwDzAQAAAA==.Brokenbranch:BAAALgAECgUJDQAAAA==.Brudene:BAABLgAECn8UAAIVAAcJFREPQADyAAAVAAcJFREPQADyAAAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Buddylock:BAABLgAECn8iAAIRAAkJmgmRWgBQAQARAAkJmgmRWgBQAQAAAA==.Bulltaura:BAAALgAECgcJBwAAAA==.Bullymaguire:BAACLgAFFH8OAAIEAAYJQBkoBwBYAQAEAAYJQBkoBwBYAQAuAAQKfx0AAgQACAk5I0EFADEDAAQACAk5I0EFADEDAAAA.Burakkuburu:BAABLgAECn82AAMUAAkJHR/IBAAPAwAUAAkJHR/IBAAPAwAEAAYJ4RXjJwCbAQAAAA==.',
Ca='Caboozles:BAABLgAECn8xAAIHAAgJbBafLAABAgAHAAgJbBafLAABAgAAAA==.Caliopia:BAABLgAECn8xAAMOAAkJvBS+EwD6AQAOAAkJvBS+EwD6AQANAAYJYAriTwALAQAAAA==.Captnhuntcat:BAAALgAECgcJDwAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8oAAIVAAkJEBTJEwAJAgAVAAkJEBTJEwAJAgAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAABLgAECn8XAAMcAAkJaR2cEAABAgAcAAkJaR2cEAABAgAXAAEJfRApCAE8AAAAAA==.Chemistree:BAABLgAECn8lAAIMAAgJyRHtKwCxAQAMAAgJyRHtKwCxAQAAAA==.Chillout:BAABLgAECn8iAAIQAAgJYg75XACHAQAQAAgJYg75XACHAQAAAA==.Chillums:BAABLgAECn8dAAIRAAcJ4iP7GgCzAgARAAcJ4iP7GgCzAgAAAA==.Chipcle:BAAALgAECgIJAgAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgADCgQJBAAKAAAAAA==.',
Co='Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8bAAILAAgJ2A3JJQCNAQALAAgJ2A3JJQCNAQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAABLgAECggJDwAKAAAAAA==.Daeleiel:BAAALgAECgEJAQAAAA==.Darkenergy:BAABLgAECn8jAAMdAAgJfyMjEgBxAgAdAAgJIyAjEgBxAgAeAAYJxSQcEwA+AgAAAA==.Darà:BAAALgADCgcJDgABLgAECggJIQAPAKEOAA==.Dashyll:BAAALgAECgMJAwAAAA==.Davyfknjones:BAAALgAECggJEAAAAA==.Daynia:BAAALgAECgEJAgAAAA==.',
De='Deadlegslul:BAABLgAECn8ZAAIHAAcJNx1YQQCHAQAHAAcJNx1YQQCHAQAAAA==.Deadlegsmd:BAAALgAECgEJAQAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadtree:BAAALgAECgEJAQAAAA==.Deadzepplin:BAAALgAECgUJBwAAAA==.Deathmono:BAAALgAECgYJCQAAAA==.Deathshark:BAACLgAFFH8IAAIcAAMJoR3iFgDOAAAcAAMJoR3iFgDOAAAuAAQKfysAAhwACAlqHb0KAGwCABwACAlqHb0KAGwCAAAA.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAABLgAECn8UAAIQAAYJrQX2swDeAAAQAAYJrQX2swDeAAABLgAECgcJKwANAG4QAA==.Demeter:BAABLgAECn8xAAIGAAkJJxLmDACeAQAGAAkJJxLmDACeAQAAAA==.Demiurge:BAAALgAECgIJAgAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denarien:BAAALgAECgkJDAAAAA==.Derpygos:BAAALgADCgcJBwABLgAECgkJJQAbANUZAA==.Devouress:BAABLgAECn8PAAIdAAgJFRRBOgCRAQAdAAgJFRRBOgCRAQABLgAECggJGAAEAEcgAA==.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dillkiller:BAABLgAECn8XAAIfAAcJGQn9IQAuAQAfAAcJGQn9IQAuAQAAAA==.Dirgen:BAABLgAECn8hAAIVAAgJMBTMMAA6AQAVAAgJMBTMMAA6AQAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAFFAMJBwAaAFIFAA==.Double:BAAALgAECgQJBAAAAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAABLgAECn8aAAICAAgJYhr8EgD7AQACAAgJYhr8EgD7AQAAAA==.Dragginballs:BAAALgAECgIJBAABLgAFFAIJAgAKAAAAAA==.Draggnar:BAAALgAECgUJDQAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAAALgAECgkJEwAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJDgAOAEwhAA==.',
Du='Dumplingsxo:BAABLgAECn8kAAMPAAkJnBhBGQA9AgAPAAgJsBlBGQA9AgAMAAcJ4BjBNACAAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn8xAAISAAkJYyUvAABlAwASAAkJYyUvAABlAwAAAA==.',
Eb='Ebojager:BAABLgAECn8wAAIdAAgJDBebLwC+AQAdAAgJDBebLwC+AQAAAA==.',
Eh='Ehko:BAAALgAECgYJCwABLgAECgkJNgAUAB0fAA==.',
Ei='Eibon:BAACLgAFFH8SAAIXAAUJcxhxFwCWAQAXAAUJcxhxFwCWAQAuAAQKfx4AAhcACQnNIakUAAADABcACQnNIakUAAADAAAA.',
El='Elliiria:BAAALgADCggJDgAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgkJEwAAAA==.Elvispriesty:BAAALgAECgUJEQAAAA==.Elwarrioro:BAAALgAECgYJDQAAAA==.',
Em='Emmpunity:BAAALgAECgQJBAAAAA==.Emmune:BAABLgAECn8cAAIgAAgJQg6SDQBmAQAgAAgJQg6SDQBmAQAAAA==.',
En='Enobia:BAABLgAECn8aAAMYAAYJtxXCCwA1AQAYAAYJtxXCCwA1AQARAAUJFgbDxADQAAAAAA==.Entrapment:BAAALgADCgYJBgABLgADCgQJBAAKAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Er='Eriaeda:BAAALgAECgUJDQAAAA==.',
Es='Esen:BAAALgAECgEJAQABLgAECggJJwARABkWAA==.Eskath:BAABLgAECn8bAAIRAAgJWR6oGwBCAgARAAgJWR6oGwBCAgABLgAECgkJJQAbANUZAA==.Essential:BAABLgAECn8dAAIFAAgJ6BLPTQCUAQAFAAgJ6BLPTQCUAQAAAA==.',
Et='Eternalpain:BAAALgADCgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8dAAIEAAYJcRNLKgAXAQAEAAYJcRNLKgAXAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgQJCAAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgAECgEJAQABLgAECgYJGQAaAB0OAA==.Ferrara:BAACLgAFFH8YAAQhAAcJqyGKBwB4AQAhAAcJhR6KBwB4AQATAAEJ9iWjHgBvAAAHAAEJtx+1HwBiAAAuAAQKfyAABCEACQnRIykGADoDACEACQmLIykGADoDAAcAAQn1I6ywAGIAABMAAQk6HgIsAEYAAAAA.',
Fi='Filthi:BAAALgAECgYJEwAAAA==.Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgUJBwAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgkJMQAPAGgiAA==.Fisted:BAAALgAFFAEJAQABLgAFFAMJBwALAGsbAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8PAAIIAAcJfRN3AQAhAgAIAAcJfRN3AQAhAgAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.Fluorita:BAAALgADCgEJAQAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Friedá:BAAALgAECgIJAwABLgAECgYJEgAKAAAAAA==.Frostednip:BAACLgAFFH8HAAIXAAMJOhg4VAAIAQAXAAMJOhg4VAAIAQAuAAQKfx0AAhcACQm/IBYmACQCABcACQm/IBYmACQCAAAA.',
Ga='Gabaghoul:BAAALgAECgQJBAAAAA==.Gabiru:BAACLgAFFH8HAAQCAAMJ9gQjLwC8AAACAAMJ9gQjLwC8AAABAAMJvQd7GACsAAAWAAEJlwEsDABCAAAuAAQKfxUAAwEACQlTE2YSABkCAAEACQlTE2YSABkCAAIAAQm0CZphADUAAAAA.Gadreeste:BAAALgAECgUJBQAAAA==.Galnarn:BAACLgAFFH8cAAIaAAcJ8h6RAQAzAgAaAAcJ8h6RAQAzAgAuAAQKfyEAAhoACQlkHfgNALQCABoACQlkHfgNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Garious:BAAALgAECgcJBwABLgAFFAQJCgAXAIsgAA==.Garjingo:BAAALgAECgQJBQABLgAECggJJAAWAF0gAA==.Garlicbae:BAAALgAECgQJBwAAAA==.Garwulf:BAAALgAECgYJDQAAAA==.',
Ge='Gefaustet:BAABLgAECn8kAAIfAAgJBhp+DADWAQAfAAgJBhp+DADWAQAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECgEJAQAAAA==.',
Go='Goatcheesè:BAAALgAECgIJAwAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAECgcJEAAAAA==.Gorbachev:BAAALgAECgYJCAAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAAALgAECggJDgAAAA==.Grayes:BAABLgAECn8aAAIbAAYJEQaJLAB2AAAbAAYJEQaJLAB2AAAAAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hallowshade:BAABLgAECn8XAAIiAAcJEhlDHABYAQAiAAcJEhlDHABYAQAAAA==.Hardran:BAABLgAECn8XAAIFAAYJUAsklQD+AAAFAAYJUAsklQD+AAAAAA==.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgAECgIJAgAAAA==.Hatreddyes:BAAALgADCgUJBQABLgAECggJCQAKAAAAAA==.Hatredyes:BAAALgAECggJCQAAAA==.Hattredyess:BAAALgAECgUJBQABLgAECggJCQAKAAAAAA==.',
He='Heatedsoul:BAAALgAECgEJAQAAAA==.Helare:BAAALgAECgYJDgAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAABLgAECn8dAAIjAAcJWQxMEwAjAQAjAAcJWQxMEwAjAQAAAA==.',
Hi='Hinatsuru:BAAALgAECgQJBAAAAA==.',
Ho='Holyzap:BAAALgAECgEJAQABLgAECgkJJQAQAA0hAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECgEJAQAAAA==.Huulrokk:BAAALgADCgkJCwABLgAECgIJBQAKAAAAAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.Hyperreal:BAAALgAECgEJAQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgkJHgALADEaAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwAKAAAAAA==.',
If='Iforgotnaaru:BAAALgAECgcJEAAAAA==.',
Ik='Ikeslice:BAAALgAECgMJAwAAAA==.Ikrys:BAAALgAECgYJDAAAAA==.',
Il='Illiae:BAABLgAECn8lAAIOAAgJ5SN7BgC5AgAOAAgJ5SN7BgC5AgAAAA==.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8rAAIVAAgJxxO+HQCyAQAVAAgJxxO+HQCyAQAAAA==.',
In='Innex:BAABLgAECn8iAAIXAAgJwR7aLgB9AgAXAAgJwR7aLgB9AgAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECggJIgAXAMEeAA==.Innexvoker:BAAALgAECgYJEAABLgAECggJIgAXAMEeAA==.Inpesca:BAAALgADCgUJBQABLgAECgkJJQACAMcfAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgQJBQAAAA==.',
Ir='Iridescent:BAAALgAECgIJAgAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAABLgAECn8UAAIhAAYJeg5mEgDxAAAhAAYJeg5mEgDxAAAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itzmuffin:BAABLgAECn8hAAINAAgJ7xHrNgCnAQANAAgJ7xHrNgCnAQAAAA==.Itzpie:BAABLgAECn81AAIQAAkJNxb2LgAbAgAQAAkJNxb2LgAbAgAAAA==.',
Ja='Jadandotz:BAAALgADCggJAgAAAA==.Jagtat:BAABLgAECn8VAAMXAAYJjQ/EjAACAQAXAAYJjQ/EjAACAQAcAAUJcQc8MQCHAAAAAA==.Jakeakuma:BAABLgAECn8UAAIRAAkJBAwlXwCsAQARAAkJBAwlXwCsAQAAAA==.Jascob:BAABLgAECn8XAAIkAAUJJgfYEQDoAAAkAAUJJgfYEQDoAAAAAA==.Jaynne:BAAALgADCgEJAQAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn8sAAIaAAkJ4h0tBgCjAgAaAAkJ4h0tBgCjAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8lAAIEAAgJGCFcCAD0AgAEAAgJGCFcCAD0AgAAAA==.Junfan:BAAALgAECgcJAwAAAA==.',
['Jà']='Jàckblack:BAAALgAECgEJAQAAAA==.',
Ka='Kaashaa:BAABLgAECn83AAIHAAkJcSHeBgDvAgAHAAkJcSHeBgDvAgAAAA==.Kaelsgf:BAAALgADCgcJBwAAAA==.Kahllan:BAABLgAECn8hAAMPAAgJoQ4BKwAhAQAPAAgJoQ4BKwAhAQAMAAEJLhQVpAA7AAAAAA==.Kahnigitt:BAAALgAECgYJDQAAAA==.Kataltoholic:BAABLgAECn8aAAIQAAYJOAE+6wBwAAAQAAYJOAE+6wBwAAAAAA==.Katrath:BAAALgADCgMJBgAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIdAAYJCxp5UAC1AQAdAAYJCxp5UAC1AQAAAA==.',
Ke='Kelinïsha:BAABLgAECn8jAAIQAAgJJAopegBGAQAQAAgJJAopegBGAQAAAA==.Kelynna:BAABLgAECn8kAAIIAAgJDhw/DgA5AgAIAAgJDhw/DgA5AgAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJAwAAAA==.',
Kh='Khelldyr:BAAALgAECggJCAAAAA==.Khellrond:BAAALgAECgkJCgAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiiras:BAABLgAECn8vAAIQAAgJ8w0qXwCBAQAQAAgJ8w0qXwCBAQAAAA==.Kimbodh:BAACLgAFFH8OAAIdAAQJWiMhEACfAQAdAAQJWiMhEACfAQAuAAQKfyYAAh0ACAkNJIYIANYCAB0ACAkNJIYIANYCAAEuAAEKAwkBAAoAAAAA.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8oAAIdAAgJLBHuQwBtAQAdAAgJLBHuQwBtAQAAAA==.',
Kl='Klefthoof:BAABLgAECn8rAAMNAAcJbhDlOwBdAQANAAcJbhDlOwBdAQAOAAEJUQQ4hwAgAAAAAA==.',
Ko='Kodey:BAABLgAECn8YAAIYAAgJrxGwCABvAQAYAAgJrxGwCABvAQABLgAFFAIJBQAYAOwGAA==.Kordy:BAAALgAECgkJAQAAAA==.',
Kr='Kraniah:BAAALgAECgIJBQAAAA==.Krimboz:BAABLgAECn8iAAIRAAcJPBhfRACPAQARAAcJPBhfRACPAQAAAA==.Krimbrouge:BAAALgAECgEJAQAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8iAAITAAcJwBWEFgCkAQATAAcJwBWEFgCkAQAAAA==.Krìsta:BAABLgAECn8cAAMZAAgJ3AxYDQBgAQAZAAcJXg5YDQBgAQARAAcJJgQAlwDPAAAAAA==.',
Ku='Kuanshuwo:BAABLgAECn8VAAMJAAgJ8AlBJgBDAQAJAAgJ8AlBJgBDAQAIAAYJfQZMTgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
La='Lanwulf:BAAALgAECgQJBAAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAACLgAFFH8GAAIJAAMJrxV4FQD7AAAJAAMJrxV4FQD7AAAuAAQKfxgAAgkACQlvHb4XACYCAAkACQlvHb4XACYCAAAA.Legaloas:BAABLgAECn8kAAMHAAgJmhpaMgDAAQAHAAgJrxlaMgDAAQAhAAUJGxGoEAAIAQAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAAALgAECgUJDQAAAA==.Leonarde:BAACLgAFFH8PAAMHAAQJKBlpHABBAQAHAAQJIBlpHABBAQAhAAMJ2Q/RFQDuAAAuAAQKfyIABCEACQkZGb8gACACACEACAkSF78gACACAAcABQl/GFNCAIMBABMAAQlWAKwzAA0AAAAA.Levitt:BAABLgAECn8WAAIRAAYJjhGTbQAjAQARAAYJjhGTbQAjAQAAAA==.',
Li='Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn8rAAIEAAgJuRbYFgCtAQAEAAgJuRbYFgCtAQAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liquid:BAAALgAECgEJAQAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgQJBAAAAA==.',
Ll='Llevanya:BAABLgAECn8rAAIFAAgJ7AxxYABlAQAFAAgJ7AxxYABlAQAAAA==.Llinaigh:BAAALgAECgkJEwAAAA==.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAQABLgAECggJIwAVAGcfAA==.Lomu:BAABLgAECn8lAAQbAAkJ1Rm7BgAuAgAbAAkJ1Rm7BgAuAgAMAAEJ7Q5JzwAvAAAPAAEJigSQdQAhAAAAAA==.Loredalso:BAAALgADCggJFgAAAA==.Lorenitha:BAAALgAECgEJAQABLgAFFAQJDQAFABccAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAFFAMJBwALAGsbAA==.Magicdreams:BAABLgAECn8wAAIPAAgJJQnqKgAhAQAPAAgJJQnqKgAhAQAAAA==.Malificent:BAAALgADCgQJCAAAAA==.Malmorte:BAABLgAECn8WAAIXAAYJMRUHowA6AQAXAAYJMRUHowA6AQAAAA==.Malorane:BAABLgAECn8vAAIcAAkJFhteCgAXAgAcAAkJFhteCgAXAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgAECgEJAQAAAA==.Marihuano:BAAALgADCgYJCwABLgADCgcJCwAKAAAAAA==.Marisi:BAAALgADCggJCAABLgAECgcJBwAKAAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIiAAkJwx2LCgAwAgAiAAkJwx2LCgAwAgAAAA==.Materiaga:BAABLgAECn8iAAQCAAgJEBE1IgB3AQACAAgJvxA1IgB3AQABAAYJFQtdKQAoAQAWAAMJjw+cEQCoAAAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8oAAIFAAkJ/x+UCgDeAgAFAAkJ/x+UCgDeAgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMgAAkJGxU2BgCWAgAgAAkJGxU2BgCWAgAOAAgJyg8jLwAqAQAAAA==.',
Me='Mebetankmon:BAEALgADCgUJBQABLgAECgkJOAAIAI8ZAA==.Meerchi:BAABLgAECn8uAAMQAAkJCBkRJABNAgAQAAkJCBkRJABNAgAlAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Meowkai:BAAALgAECgYJBgABLgAECgkJNgAUAB0fAA==.Mesthos:BAAALgAECgcJDAABLgAECggJGwASAHIlAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8lAAICAAgJlBKOGgD2AQACAAgJlBKOGgD2AQAAAA==.',
Mi='Mickieta:BAABLgAECn8kAAIFAAgJviAIGgBnAgAFAAgJviAIGgBnAgAAAA==.Microsurge:BAABLgAECn8cAAIQAAgJIh3bJQDbAgAQAAgJIh3bJQDbAgAAAA==.Mikalau:BAABLgAECn8aAAIHAAcJIA+TUwBNAQAHAAcJIA+TUwBNAQAAAA==.Mikaluu:BAAALgAECgYJDgAAAA==.Miqkail:BAAALgAECggJCgABLgAECggJGwASAHIlAA==.Missteek:BAAALgAECgEJAwABLgAECggJJAAWAF0gAA==.Mistrunner:BAAALgAECgMJAwAAAA==.Mistspell:BAACLgAFFH8PAAIJAAQJpQ87EQAtAQAJAAQJpQ87EQAtAQAuAAQKfyAAAwkACQnXHeQOAJUCAAkACQnXHeQOAJUCAAgAAwklBoFqAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwABLgAECgkJHgALADEaAA==.Mognel:BAABLgAECn82AAIRAAkJxRyAGQBQAgARAAkJxRyAGQBQAgAAAA==.Mogrungar:BAABLgAECn8jAAINAAkJEQ4vKADFAQANAAkJEQ4vKADFAQAAAA==.Moisten:BAABLgAECn8VAAIOAAkJURxWCwBkAgAOAAkJURxWCwBkAgAAAA==.Monklee:BAAALgAECgEJAQAAAA==.Moomootus:BAABLgAECn8cAAMFAAgJHhTIRgCpAQAFAAgJHhTIRgCpAQALAAMJvRxIQADuAAAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIEAAgJRyBsDQClAgAEAAgJRyBsDQClAgAAAA==.Mystynight:BAAALgAECgYJBwAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAABLgAECn8eAAIOAAgJng6IKgBFAQAOAAgJng6IKgBFAQAAAA==.Nagini:BAABLgAECn8fAAIRAAgJdwjYZQA0AQARAAgJdwjYZQA0AQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn84AAMIAAkJjxmHFgDSAQAIAAcJKRmHFgDSAQAJAAkJahA8LwAOAQAAAA==.Nietzcha:BAAALgADCgYJDgAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAAALgAECgYJEgAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nilfgard:BAAALgAECgUJBwABLgAECgYJFgAdAFQSAA==.Nioh:BAABLgAECn8eAAIdAAkJwxbdHwAQAgAdAAkJwxbdHwAQAgAAAA==.',
No='Noodles:BAABLgAECn8nAAIdAAgJngi6cADtAAAdAAgJngi6cADtAAAAAA==.Nordrydsh:BAAALgADCgkJCQABLgAFFAUJEAAUANAYAA==.',
Nu='Nuggs:BAABLgAECn8XAAIjAAgJjhFZDACTAQAjAAgJjhFZDACTAQAAAA==.Nuhpie:BAACLgAFFH8TAAMDAAcJdA5XEQDhAAADAAQJlQtXEQDhAAAVAAMJUxHRIQDdAAAuAAQKfx4AAwMACQlfHdUTAGoBAAMABQmuGtUTAGoBABUABQlsHOo0ACUBAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8lAAIXAAkJah+0DQDEAgAXAAkJah+0DQDEAgAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAwAAAA==.',
Ol='Olimdar:BAACLgAFFH8bAAINAAcJmCGdAACeAgANAAcJmCGdAACeAgAuAAQKfyEAAw0ACQlsJUsAAM8DAA0ACQlsJUsAAM8DAA4AAQmSHaiCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBwAAAA==.',
Oo='Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Oricelle:BAABLgAECn8fAAIdAAkJdhEQPQCHAQAdAAkJdhEQPQCHAQAAAA==.Oryon:BAEBLgAECn8rAAIZAAgJyRSCBgCpAQAZAAgJyRSCBgCpAQAAAA==.',
Ov='Ovarb:BAABLgAECn8hAAIcAAkJkRhXCgAYAgAcAAkJkRhXCgAYAgAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDQAAAA==.Palasexo:BAAALgADCgcJCwAAAA==.Palldude:BAAALgADCgIJAgAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Pesti:BAACLgAFFH8OAAIiAAMJXhGZDgAGAQAiAAMJXhGZDgAGAQAuAAQKfzQAAiIACQkKHzIGAIcCACIACQkKHzIGAIcCAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn84AAINAAkJQiOsAQCDAwANAAkJQiOsAQCDAwAAAA==.',
Pi='Pissedwolf:BAAALgAECgEJAgAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAABLgAECn8ZAAIaAAgJJQ8uJwA4AQAaAAgJJQ8uJwA4AQAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAABLgAECn81AAMQAAkJ3B79EgCxAgAQAAkJWR79EgCxAgAmAAUJrRIkDAAQAQAAAA==.Proctologist:BAABLgAECn8fAAIaAAgJlRd3FQDCAQAaAAgJlRd3FQDCAQAAAA==.Proserpìne:BAABLgAECn8lAAIdAAgJlAj5YQASAQAdAAgJlAj5YQASAQAAAA==.',
Ps='Psychojester:BAABLgAECn86AAIgAAkJKiAzAgC+AgAgAAkJKiAzAgC+AgAAAA==.Psylir:BAAALgAECgQJDgAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAABLgAECn8WAAIQAAUJihsojgAhAQAQAAUJihsojgAhAQAAAA==.',
Py='Pydge:BAAALgAECgEJAQAAAA==.',
Qu='Quod:BAAALgAECgQJBAAAAA==.Quoril:BAABLgAECn8yAAMQAAgJYh3XKAA1AgAQAAgJYh3XKAA1AgAmAAEJlyB5GQBMAAABLgAFFAUJEgAHADobAA==.',
Ra='Raijyu:BAABLgAECn8vAAMIAAkJJh2FBAD9AgAIAAkJJh2FBAD9AgAJAAcJVRV+IwC8AQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECgkJMAAPAM8WAA==.Rainstormin:BAABLgAECn8wAAIPAAkJzxZRDgAlAgAPAAkJzxZRDgAlAgAAAA==.Rakarra:BAABLgAECn8WAAMMAAcJogpDUAAHAQAMAAcJogpDUAAHAQAPAAYJDgcPTQD2AAAAAA==.Rawrstance:BAABLgAECn8oAAMXAAgJbRumTgCPAQAXAAcJoRymTgCPAQAcAAgJKQ93FwBRAQABLgADCgQJBAAKAAAAAA==.Razgrize:BAABLgAECn8ZAAIQAAgJjxIgTgCuAQAQAAgJjxIgTgCuAQAAAA==.',
Re='Redraggon:BAAALgAECgYJBgAAAA==.Reecalled:BAAALgADCgUJBQABLgAECggJGgACAGIaAA==.Reeshan:BAABLgAECn8fAAMFAAkJ1iPzBQAUAwAFAAkJ1iPzBQAUAwALAAIJaxRNWwBqAAAAAA==.Reilin:BAAALgAECgQJBQAAAA==.Remsham:BAABLgAECn8dAAIgAAcJxA6REAAyAQAgAAcJxA6REAAyAQAAAA==.Reniel:BAAALgADCgQJBAABLgAECggJKAAdACwRAA==.Renwyck:BAABLgAECn8bAAISAAgJciXYAQD2AgASAAgJciXYAQD2AgAAAA==.Revengemoon:BAACLgAFFH8PAAIFAAQJJBJsJgA2AQAFAAQJJBJsJgA2AQAuAAQKfyMAAgUACQmVGsApAH4CAAUACQmVGsApAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgAKAAAAAA==.Ringberg:BAACLgAFFH8HAAILAAMJaxs8HQDoAAALAAMJaxs8HQDoAAAuAAQKfxcAAwsABwlTH2MQAEwCAAsABwlTH2MQAEwCAAUAAwmmFI3AALYAAAAA.',
Ro='Robane:BAAALgAECgUJDwAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Ronburgundy:BAAALgAECgMJBQAAAA==.Rouen:BAABLgAECn8kAAMgAAgJLyLWBQAoAgAgAAgJLyLWBQAoAgANAAYJmx9CHQAKAgAAAA==.',
Ru='Ruckus:BAEALgAECgQJCAAAAA==.Ruder:BAAALgAECgIJAwABLgAECggJCQAKAAAAAA==.Rutabaga:BAAALgAECgUJCAAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIJAAkJxBtnEQBzAgAJAAkJxBtnEQBzAgAAAA==.',
Sa='Saintanic:BAAALgADCgQJBAAAAA==.Sandkat:BAABLgAECn8xAAIVAAgJISInCACcAgAVAAgJISInCACcAgAAAA==.Sanstian:BAAALgAECgUJDQAAAA==.Santamou:BAAALgADCgIJAgAAAA==.Saraelin:BAAALgAFFAEJAgAAAA==.Saray:BAAALgAECgcJDQAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAYJEQAVAN4KAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgYJDQAAAA==.Serahstia:BAABLgAECn8aAAIQAAYJ8BjFbwBbAQAQAAYJ8BjFbwBbAQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shaiy:BAAALgAECgMJBQAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwAKAAAAAA==.Shiifthappen:BAAALgAECgEJAQAAAA==.Shinta:BAAALgAECgUJBQAAAA==.Shirtles:BAAALgAECgYJDwAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shpik:BAAALgADCgQJBAAAAA==.Shèp:BAABLgAECn8ZAAILAAgJFhEuIgCoAQALAAgJFhEuIgCoAQAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIOAAUJ/hmfAwCvAQAOAAUJ/hmfAwCvAQABLgAFFAYJDgATACUWAA==.Siffrin:BAAALgAECgIJAgAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8lAAMRAAgJnxV3UgBlAQARAAYJ0hJ3UgBlAQAZAAUJJhbSDgD8AAABLgAECggJJQACAJQSAA==.Sinkingship:BAAALgADCgcJDwAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAABLgAECn8VAAIcAAgJKx3BCAA9AgAcAAgJKx3BCAA9AgAAAA==.',
Sk='Skaterboi:BAAALgAECgYJBgAAAA==.Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sloothe:BAAALgADCgUJBQAAAA==.Sloothi:BAAALgAECgEJAQAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.',
So='Sosorry:BAAALgADCgIJAgAAAA==.Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAABLgAECn8UAAIFAAgJIBw3LgD/AQAFAAgJIBw3LgD/AQAAAA==.',
Sp='Sprodage:BAABLgAECn8lAAILAAgJ0xN8HwC7AQALAAgJ0xN8HwC7AQAAAA==.',
St='Staggrsaurus:BAAALgAECgIJAwABLgAECgMJBAAKAAAAAA==.Stanil:BAABLgAECn8bAAMHAAgJ7AYAWgA6AQAHAAgJ7AYAWgA6AQAhAAEJWwAkmwAVAAAAAA==.Stayfrosty:BAAALgAECgcJDAAAAA==.Stellare:BAABLgAECn8pAAIeAAgJHRTvEQCnAQAeAAgJHRTvEQCnAQAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Striest:BAAALgAECgMJAwAAAA==.Styló:BAAALgAECggJEgAAAA==.',
Su='Suetonius:BAAALgAECgYJCQAAAA==.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8rAAIQAAkJdRqhIgBVAgAQAAkJdRqhIgBVAgAAAA==.Suraschi:BAAALgAECgYJBgABLgAECgkJKwAQAHUaAA==.',
Sv='Svelda:BAAALgAECgUJEgAAAA==.',
Sw='Swisscake:BAABLgAECn8xAAIPAAkJaCI9AwABAwAPAAkJaCI9AwABAwAAAA==.',
Sy='Sylain:BAAALgAECgYJEQABLgAECgkJEgAKAAAAAA==.',
Ta='Tannatax:BAABLgAECn8nAAINAAgJoAYPRwAuAQANAAgJoAYPRwAuAQAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAAKAAAAAA==.Tekvet:BAAALgAECgkJCQAAAA==.',
Th='Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8jAAMQAAkJmRXMNgD8AQAQAAkJmRXMNgD8AQAlAAEJGgEmDwALAAAAAA==.Thewretch:BAABLgAECn8rAAIRAAgJ8iBPFABzAgARAAgJ8iBPFABzAgAAAA==.Thumpthump:BAABLgAECn8eAAQhAAkJKxinIgARAgAhAAYJwx6nIgARAgATAAgJ3AxOFQCwAQAHAAEJpw4D4AA1AAAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEALgAECgMJBAABLgAECgQJCAAKAAAAAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Titiera:BAAALgAECgYJEwAAAA==.',
To='Toastnbutta:BAABLgAECn8jAAIMAAgJ4xlyGQAyAgAMAAgJ4xlyGQAyAgAAAA==.Tolten:BAABLgAECn8eAAIFAAgJ3RmUMQBcAgAFAAgJ3RmUMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgQJBAAAAA==.Traumatism:BAAALgAECgIJAwAAAA==.Trevor:BAABLgAECn8xAAIkAAgJUxT7BQDEAQAkAAgJUxT7BQDEAQAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAABLgAECn8UAAMbAAcJXxxaDgCPAQAbAAYJNBxaDgCPAQAjAAUJhhs0EQA/AQABLgAFFAMJCAAcAKEdAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Ty='Tylaesh:BAAALgAECgYJDwAAAA==.',
Un='Unclepeepers:BAACLgAFFH8PAAIUAAQJ4xyvEQBKAQAUAAQJ4xyvEQBKAQAuAAQKfykAAwQACQkPI98JAF0CAAQACAmNIt8JAF0CABQACQkDGp8VABgCAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAABLgAECn8XAAIXAAcJ3QtFjwD9AAAXAAcJ3QtFjwD9AAAAAA==.',
Ur='Urtag:BAABLgAFFH8IAAIhAAYJRw1PCQBTAQAhAAYJRw1PCQBTAQAAAA==.',
Va='Vadge:BAAALgADCgcJBwABLgADCgQJBAAKAAAAAA==.Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAABLgAECn8/AAMnAAgJNxvsCgBtAgAnAAgJNxvsCgBtAgAJAAUJoQarRgCWAAAAAA==.Valryn:BAAALgAECgMJBAABLgAECggJPwAnADcbAA==.Valtar:BAABLgAECn8gAAINAAkJoByoDwCDAgANAAkJoByoDwCDAgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAABLgAECn8eAAIcAAgJ7R1LDwAXAgAcAAgJ7R1LDwAXAgAAAA==.',
Ve='Veraalyn:BAABLgAECn8dAAMOAAgJHhE8LwAqAQAOAAgJHhE8LwAqAQANAAMJxwiifgCZAAAAAA==.',
Vi='Vicsen:BAABLgAECn8gAAIRAAkJdAUuXgBGAQARAAkJdAUuXgBGAQAAAA==.Vikaya:BAAALgAECgUJBQAAAA==.Vilevixon:BAABLgAECn8cAAMJAAgJiRj2EwDfAQAJAAgJiRj2EwDfAQAnAAEJDwSzXgAlAAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Vo='Voidasuras:BAAALgAECgEJAQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAAKAAAAAA==.Wanlok:BAAALgAECgQJBAAAAA==.Wantoo:BAAALgAECgYJBgAAAA==.Warlokip:BAAALgAECgkJCgAAAA==.Warotar:BAAALgAECgIJAgAAAA==.Warriorlobo:BAABLgAECn8jAAQVAAgJZx9cCwBqAgAVAAgJZx9cCwBqAgADAAYJ7RC3HgAKAQAfAAEJ6A7OQgAoAAAAAA==.Warvision:BAAALgAFFAEJAQAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAABLgAECn8cAAIHAAcJuQzDRgCWAQAHAAcJuQzDRgCWAQAAAA==.Wildside:BAAALgAECgcJCwAAAA==.',
Wu='Wulffgar:BAAALgADCgcJCQAAAA==.',
['Wì']='Wìldthìng:BAAALgAECgUJBQAAAA==.',
Xa='Xandronys:BAAALgAECgYJCQAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECgcJCQAAAA==.Xenie:BAAALgAECgUJCgAAAA==.',
Xi='Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgADCgcJCAAAAA==.',
Ye='Yeet:BAABLgAECn8XAAIiAAkJMhb5IgDhAQAiAAkJMhb5IgDhAQAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgEJBAAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgAECgIJAgAAAA==.Zalanna:BAAALgADCgMJAwAAAA==.Zalckar:BAABLgAECn8XAAMLAAkJIRIZRQBjAQALAAkJIRIZRQBjAQAFAAEJjAwUNQE0AAAAAA==.Zarayssa:BAAALgADCgQJBAAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zeeva:BAAALgAECgYJEwAAAA==.Zendead:BAABLgAECn8fAAIEAAkJhyL8BADIAgAEAAkJhyL8BADIAgAAAA==.Zeppeli:BAAALgAECgMJAwAAAA==.',
Zi='Zionspartan:BAABLgAECn8mAAIHAAgJpw1nRAB8AQAHAAgJpw1nRAB8AQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugshaman:BAABLgAECn8iAAQNAAkJhRb0FgA9AgANAAkJhRb0FgA9AgAOAAQJrwOHbgCJAAAgAAEJYQCPKwAdAAAAAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Êï']='Êïñstëïn:BAAALgAECgEJAQAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8ZAAIaAAYJHQ77NwDhAAAaAAYJHQ77NwDhAAAAAA==.',
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
