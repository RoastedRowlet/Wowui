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

local lookup = {'DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','Hunter-Survival','DemonHunter-Havoc','Warrior-Fury','Evoker-Devastation','DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','DeathKnight-Frost','Druid-Guardian','Rogue-Subtlety','Druid-Feral','Rogue-Assassination','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Aberration:BAAALgAECgEJAgAAAA==.Abraxidormu:BAAALgAECgYJBgABLgAECgkJMAABAPgQAA==.',
Ad='Adorraa:BAAALgAFFAIJAgAAAA==.Adoryn:BAAALgADCgYJCQAAAA==.Adowyrm:BAACLgAFFH8oAAMCAAgJlRfxCQAMAgACAAcJYRfxCQAMAgADAAMJYQ2jPADVAAAuAAQKfyEAAwIACQm1IUcCAFEDAAIACQm1IUcCAFEDAAMABgnLHfscAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.Adrielle:BAAALgAECgQJBAAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECgkJHQAEAIgcAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAFFAQJBAAAAA==.Agtar:BAAALgAECgMJAwAAAA==.',
Ai='Airali:BAACLgAFFH8KAAIFAAUJ+gXzYADtAAAFAAUJ+gXzYADtAAAuAAQKfxcAAwUACQn+E2tkALgBAAUACQn+E2tkALgBAAYAAwmJCNM3AGIAAAAA.Airedale:BAABLgAECn8uAAIHAAgJiBgfPADwAQAHAAgJiBgfPADwAQAAAA==.',
Ak='Akairo:BAABLgAECn8xAAMIAAkJACSCAgBBAwAIAAkJACSCAgBBAwAJAAgJrBG4KwB3AQAAAA==.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgAECgYJBgABLgAFFAUJCQADAMQQAA==.Alderbaran:BAAALgADCgUJBQAAAA==.Alexanderxl:BAABLgAECn8WAAMGAAYJAB1gFwBfAQAGAAYJAB1gFwBfAQAFAAUJWBXOxAACAQABLgAECggJAwAKAAAAAA==.Aleybobwa:BAABLgAECn8gAAQLAAkJjhLGKgC5AQALAAkJjhLGKgC5AQAGAAEJvRieAwBFAAAFAAEJYwiPUgErAAAAAA==.Alody:BAAALgADCgMJAwABLgAECgYJBgAKAAAAAA==.Alyméré:BAAALgAECgYJCAAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAABLgAECn8nAAILAAkJmxsaDQC/AgALAAkJmxsaDQC/AgAAAA==.Amulius:BAACLgAFFH8FAAIFAAMJtSV9OAA8AQAFAAMJtSV9OAA8AQAuAAQKfzYAAgUACQnyJZMEAFUDAAUACQnyJZMEAFUDAAAA.',
An='Anderdingus:BAAALgADCgYJCgAAAA==.Andormath:BAAALgAECgQJBgAAAA==.Andramedae:BAABLgAECn88AAMMAAkJtBsBEgC/AgAMAAkJtBsBEgC/AgANAAYJQg4sSQDnAAAAAA==.Angerissues:BAAALgADCgkJCQAAAA==.Angyavocado:BAAALgAECgUJBQAAAA==.Anoki:BAABLgAECn9DAAMOAAkJJBs1FQChAgAOAAkJJBs1FQChAgAPAAEJgQsdtQAmAAAAAA==.',
Ao='Aolus:BAACLgAFFH8RAAINAAQJuxgPIgARAQANAAQJuxgPIgARAQAuAAQKfxsAAg0ACQkVHDETAHsCAA0ACQkVHDETAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgAECgEJAQAAAA==.Aprollon:BAAALgAECgEJAQAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJBAAKAAAAAA==.Arcaina:BAABLgAECn8kAAIQAAkJLglDegCEAQAQAAkJLglDegCEAQAAAA==.Ares:BAAALgADCgkJEAABLgAECgkJOgARAPAXAA==.Arez:BAABLgAECn86AAIRAAkJ8BdWKQA2AgARAAkJ8BdWKQA2AgAAAA==.Arilass:BAAALgADCgIJBAAAAA==.Armis:BAAALgADCgEJAQABLgAECgkJSAASAOMlAA==.Artèmís:BAABLgAECn8nAAITAAkJDSVbAwACAwATAAkJDSVbAwACAwAAAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Ashtongue:BAAALgAECgQJBAAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athinea:BAAALgAECgYJCgAAAA==.',
Au='Aura:BAAALgAFFAEJAQAAAA==.',
Ay='Ayahuasca:BAAALgADCgIJAgAAAA==.',
Az='Azaekho:BAABLgAECn8kAAIOAAkJcxQIKgDmAQAOAAkJcxQIKgDmAQAAAA==.Azaelleonoc:BAAALgAECgEJAQAAAA==.Azalet:BAAALgAFFAIJAgAAAA==.',
Ba='Baalzak:BAAALgADCgYJBQAAAA==.Backfliphoe:BAABLgAECn8ZAAIUAAgJUhg6GQC4AQAUAAgJUhg6GQC4AQAAAA==.Badoosh:BAABLgAECn8pAAIVAAgJbB6aGACHAgAVAAgJbB6aGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Bajablaster:BAABLgAECn9EAAQWAAkJdCOpAAA7AwAWAAkJdCOpAAA7AwADAAMJ5BD7TACdAAACAAEJMAstPgArAAAAAA==.Baliw:BAAALgADCgkJDQAAAA==.Balto:BAAALgADCgMJAwAAAA==.Barbearic:BAAALgAECgEJAQAAAA==.',
Bb='Bbl:BAECLgAFFH8eAAIPAAYJ1Bg1FQBzAQAPAAYJ1Bg1FQBzAQAuAAQKfyUAAg8ACQnWIFgKAPACAA8ACQnWIFgKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8PAAIQAAQJ2xFGKwAIAQAQAAQJ2xFGKwAIAQAuAAQKfyMAAhAACQnDGZo7AIgCABAACQnDGZo7AIgCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAACLgAFFH8GAAIFAAIJJQ2+kwCMAAAFAAIJJQ2+kwCMAAAuAAQKfxgAAgUACQkfEY1XAMUBAAUACQkfEY1XAMUBAAAA.',
Bh='Bhain:BAAALgADCgcJDQABLgAFFAUJEgAFANIeAA==.',
Bi='Bieorne:BAABLgAECn87AAIXAAkJrSEBDwD0AgAXAAkJrSEBDwD0AgAAAA==.Bigpan:BAAALgAECgIJAgABLgAECggJJAAYAJsRAA==.',
Bl='Blastbane:BAACLgAFFH8LAAIRAAQJXQsrYwABAQARAAQJXQsrYwABAQAuAAQKfxQAAhEACQnuFA43AP0BABEACQnuFA43AP0BAAEuAAUUBQkNABkAiQkA.Bloodwrath:BAAALgAECgUJCAAAAA==.Blueveins:BAABLgAECn8VAAIQAAcJ/gWd1gDoAAAQAAcJ/gWd1gDoAAAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAACLgAFFH8FAAIRAAIJ5R4BlQCYAAARAAIJ5R4BlQCYAAAuAAQKfxgAAxEACQnvHP4PAPoCABEACQnvHP4PAPoCABoAAQkAAE9QAAAAAAEuAAUUAwkIAAsAaxsA.Boondocks:BAABLgAECn8+AAMRAAkJ+h8fAQCOAQARAAYJJxsfAQCOAQAbAAUJ8CHQDgBvAQAAAA==.',
Br='Braca:BAAALgAECgEJAQAAAA==.Braelek:BAAALgADCgEJAQAAAA==.Brains:BAAALgAECgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAABLgAECn8ZAAIYAAkJLQ/nIwCMAQAYAAkJLQ/nIwCMAQABLgAECgkJLQARAO0gAA==.Brielle:BAABLgAECn8tAAIHAAkJuBcBLAAtAgAHAAkJuBcBLAAtAgAAAA==.Brokenbranch:BAABLgAECn8XAAIMAAcJsgjrawDxAAAMAAcJsgjrawDxAAAAAA==.Brudene:BAABLgAECn8UAAIVAAcJFRF2VABZAQAVAAcJFRF2VABZAQAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Bubbletruble:BAAALgAECgYJBgAAAA==.Buddylock:BAABLgAECn8iAAIRAAkJmgm0ewBBAQARAAkJmgm0ewBBAQAAAA==.Bulltaura:BAAALgAECgcJBwAAAA==.Bullymaguire:BAACLgAFFH8RAAIcAAcJRhsVBgC2AQAcAAcJRhsVBgC2AQAuAAQKfx0AAhwACAk5I0EFADEDABwACAk5I0EFADEDAAAA.Burakkuburu:BAABLgAECn88AAMdAAkJHR8KCQALAwAdAAkJHR8KCQALAwAcAAYJMRlFMQBCAQABLgAECgkJJwATAA0lAA==.',
Ca='Caboozles:BAABLgAECn87AAIHAAkJCRaOOwDxAQAHAAkJCRaOOwDxAQAAAA==.Caliopia:BAABLgAECn8xAAMPAAkJvBQEIADjAQAPAAkJvBQEIADjAQAOAAYJYQqNcQAIAQAAAA==.Caliper:BAAALgAECgEJAQAAAA==.Canrif:BAAALgAECgYJBgAAAA==.Caplyta:BAAALgAECggJEgABLgAFFAUJEgAJACscAA==.Captnhuntcat:BAAALgAECggJEwAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.Cathode:BAAALgAFFAEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8vAAIVAAkJNxewEwBUAgAVAAkJNxewEwBUAgAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAABLgAECn8bAAMZAAkJaR2cEAABAgAZAAkJaR2cEAABAgAXAAQJJA/QyQDxAAAAAA==.Chemistree:BAABLgAECn82AAIMAAkJNRQcJwAXAgAMAAkJNRQcJwAXAgAAAA==.Chillout:BAABLgAECn8nAAIQAAkJvw2KYwC3AQAQAAkJvw2KYwC3AQAAAA==.Chillums:BAABLgAECn8cAAIRAAcJ4iP7GgCzAgARAAcJ4iP7GgCzAgAAAA==.Chipcle:BAAALgAECgQJBwAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Ci='Cillah:BAAALgAECgEJAwABLgAECgkJOQAVAB4gAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgAECgEJAQAKAAAAAA==.',
Co='Codeblue:BAAALgADCgkJEQAAAA==.Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8dAAILAAkJYg7AKQDAAQALAAkJYg7AKQDAAQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Cy='Cy:BAABLgAECn8bAAMdAAgJJRMuMgCvAQAdAAgJJRMuMgCvAQAcAAIJfgohBABVAAAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAABLgAECggJFQAXAB4bAA==.Daeleiel:BAAALgAECgEJAQAAAA==.Damrek:BAAALgAECgEJAQAAAA==.Darkenergy:BAABLgAECn8+AAMUAAkJpiTpAQBTAwAUAAkJpiTpAQBTAwABAAkJuh87EQC4AgAAAA==.Darà:BAAALgAECgYJDQABLgAECgkJNgANALoQAA==.Dashyll:BAAALgAECgMJBQAAAA==.Davyfknjones:BAABLgAECn8aAAIHAAgJTxhHOAD9AQAHAAgJTxhHOAD9AQAAAA==.Daynia:BAAALgAECgYJEQAAAA==.',
De='Deadbolt:BAAALgAECgYJBgAAAA==.Deadlegslul:BAABLgAECn8iAAIHAAgJkx+zIgBZAgAHAAgJkx+zIgBZAgAAAA==.Deadlegsmd:BAAALgAECgQJCAAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadtree:BAAALgAECgEJAQAAAA==.Deadzepplin:BAAALgAECgUJCwAAAA==.Deathfish:BAAALgAECgUJBgAAAA==.Deathmono:BAAALgAECgYJDQAAAA==.Deathshark:BAACLgAFFH8YAAIZAAUJrhzHFQA+AQAZAAUJrhzHFQA+AQAuAAQKfzEAAhkACQkLH/sNACoCABkACQkLH/sNACoCAAAA.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAABLgAECn8jAAIQAAcJyAzxoAA5AQAQAAcJyAzxoAA5AQABLgAECggJQAAOAI4UAA==.Demeter:BAABLgAECn9EAAIGAAkJvBT8DQDlAQAGAAkJvBT8DQDlAQAAAA==.Demiurge:BAAALgAECgIJAgAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denalli:BAAALgAECgQJBAAAAA==.Denarien:BAAALgAECgkJDwAAAA==.Derpygos:BAAALgADCgcJBwABLgAECgkJLQARAO0gAA==.Detroitt:BAAALgADCgIJAgAAAA==.Devouress:BAACLgAFFH8PAAIBAAQJqA5AUgD3AAABAAQJqA5AUgD3AAAuAAQKfxoAAgEACAmEGIo7ANkBAAEACAmEGIo7ANkBAAAA.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dillkiller:BAABLgAECn8XAAIeAAcJGQn9IQAuAQAeAAcJGQn9IQAuAQAAAA==.Dirgen:BAABLgAECn9AAAMVAAkJSRyUDgCJAgAVAAkJSRyUDgCJAgAeAAEJzhxTSgBMAAAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dogmaww:BAAALgADCgEJAQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAFFAUJEwAYAPMJAA==.Double:BAAALgAECgQJBAAAAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAABLgAECn8aAAIDAAgJYhpgHADyAQADAAgJYhpgHADyAQAAAA==.Dragginballs:BAAALgAECgIJBAABLgAFFAIJAgAKAAAAAA==.Draggnar:BAABLgAECn8XAAIaAAcJeAiBGgDQAAAaAAcJeAiBGgDQAAAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAABLgAECn8mAAMTAAkJgA+qFAD/AQATAAkJeA+qFAD/AQAfAAcJeAZVIACtAAAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJDwAPAEwhAA==.',
Du='Dumplingsxo:BAABLgAECn8kAAMNAAkJnBhBGQA9AgANAAgJsBlBGQA9AgAMAAcJ4BiYPQCtAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn9IAAMSAAkJ4yVgAABiAwASAAkJ4yVgAABiAwAUAAYJgx1rGgCsAQAAAA==.',
Eb='Ebojager:BAABLgAECn9AAAIBAAkJVhppHABqAgABAAkJVhppHABqAgAAAA==.',
Eh='Ehko:BAAALgAECgYJCwABLgAECgkJJwATAA0lAA==.',
Ei='Eibon:BAACLgAFFH8eAAIXAAgJaB2sCwCDAgAXAAgJaB2sCwCDAgAuAAQKfx4AAhcACQnNIakUAAADABcACQnNIakUAAADAAAA.Einfreren:BAAALgAECgQJBAAAAA==.',
El='Elliiria:BAAALgAECgQJBgAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgkJEwAAAA==.Elvispriesty:BAABLgAECn8eAAIgAAcJQxXXIADHAQAgAAcJQxXXIADHAQAAAA==.Elwarrioro:BAAALgAECgYJDwAAAA==.',
Em='Emaleonoc:BAAALgAECgEJAgAAAA==.Emmpunity:BAAALgAECgQJBAAAAA==.Emmune:BAABLgAECn8oAAIhAAkJzxSqCQAiAgAhAAkJzxSqCQAiAgAAAA==.',
En='Enobia:BAABLgAECn8sAAMaAAkJuBmhAwBXAgAaAAkJuBmhAwBXAgARAAUJFgbDxADQAAAAAA==.Entrapment:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Er='Eriaeda:BAAALgAECgUJDQAAAA==.',
Es='Esen:BAAALgAECgQJBQABLgAECgkJOgARAPAXAA==.Eskath:BAABLgAECn8tAAIRAAkJ7SDoDADmAgARAAkJ7SDoDADmAgAAAA==.Essential:BAACLgAFFH8IAAIFAAQJNgvvWgD6AAAFAAQJNgvvWgD6AAAuAAQKfx0AAgUACAnpEnV7AHgBAAUACAnpEnV7AHgBAAAA.',
Et='Eternalpain:BAAALgAECgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8hAAIcAAYJfxNSPQALAQAcAAYJfxNSPQALAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgQJCQAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Felpickles:BAAALgAECgMJBAABLgAECgEJAQAKAAAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgAECgEJAQABLgAECggJJAAYAJsRAA==.Ferrara:BAACLgAFFH8nAAQTAAgJfCOoAgAPAgATAAYJxiOoAgAPAgAfAAcJkx71CwBdAQAHAAEJtx+1HwBiAAAuAAQKfyAABB8ACQnRIykGADoDAB8ACQmLIykGADoDAAcAAQn1I6ywAGIAABMAAQk6HgIsAEYAAAAA.',
Fi='Filthi:BAABLgAECn8XAAIPAAYJRiFuIAANAgAPAAYJRiFuIAANAgAAAA==.Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgUJBwAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgkJSQANAGskAA==.Fisted:BAAALgAFFAEJAQABLgAFFAMJCAALAGsbAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8cAAMIAAgJWCCmAAD9AgAIAAgJWCCmAAD9AgAJAAEJUg7xOgBDAAAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.Fluorita:BAAALgAECgEJAQAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Friedá:BAAALgAECgIJAwABLgAECgYJEgAKAAAAAA==.Frostednip:BAACLgAFFH8RAAMXAAUJJhobYAA0AQAXAAUJ3RkbYAA0AQAiAAIJoRIcHwCNAAAuAAQKfyQAAyIACQnaIPwJAOMBABcACQm/IEs+AAkCACIABwmhG/wJAOMBAAAA.',
Ga='Gabaghoul:BAAALgAECgQJBAAAAA==.Gabiru:BAACLgAFFH8HAAQDAAMJ9gQOTgCWAAADAAMJ9gQOTgCWAAACAAMJvQegIwCEAAAWAAEJlwEsDABCAAAuAAQKfxUAAwIACQlTE2YSABkCAAIACQlTE2YSABkCAAMAAQm0CZphADUAAAAA.Gadreeste:BAAALgAECggJCQAAAA==.Galnarn:BAACLgAFFH8oAAIYAAcJyyBjCAAKAgAYAAcJyyBjCAAKAgAuAAQKfyEAAhgACQlkHfgNALQCABgACQlkHfgNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Gank:BAAALgAFFAEJAQABLgAFFAcJHwABALQZAA==.Garious:BAAALgAECgcJBwABLgAFFAUJEgAXAKMiAA==.Garjingo:BAAALgAECgUJBgABLgAECgkJRAAWAHQjAA==.Garlicbae:BAABLgAECn8VAAIjAAcJtwnWOwC2AAAjAAcJtwnWOwC2AAAAAA==.Garwulf:BAABLgAECn8bAAITAAkJUQYWIwCFAQATAAkJUQYWIwCFAQAAAA==.',
Ge='Gefaustet:BAABLgAECn8/AAQeAAkJchqXCwA0AgAeAAkJchqXCwA0AgAVAAEJ8gbMqwArAAAEAAEJEAlvgQApAAAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gi='Gilberticus:BAAALgAECgMJAwABLgAECgkJUAAcAMUiAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECgcJCQAAAA==.Glyd:BAAALgAECgYJCAABLgAECggJQAAOAI4UAA==.',
Go='Goatcheesè:BAAALgAECgIJBAAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAFFAEJAQAAAA==.Gorbachev:BAAALgAECgYJCAAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAABLgAECn8cAAMYAAkJ+AqpKABtAQAYAAkJ+AqpKABtAQAcAAMJHgJvqgAoAAAAAA==.Grayes:BAABLgAECn8hAAMjAAYJMQjgRACUAAAjAAYJMQjgRACUAAAMAAIJLwIX9QAdAAABLgAECgkJHAAYAPgKAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hail:BAAALgADCgUJBQABLgAFFAUJCQADAMQQAA==.Hallowshade:BAABLgAECn8XAAIkAAcJFhnlJQDKAQAkAAcJFhnlJQDKAQAAAA==.Hardran:BAACLgAFFH8FAAIFAAIJsALepwByAAAFAAIJsALepwByAAAuAAQKfyQAAgUACAl3EpYCADkBAAUACAl3EpYCADkBAAAA.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgAECgQJDAAAAA==.Hatreddyes:BAAALgAECgMJAwABLgAECggJCQAKAAAAAA==.Hatredyes:BAAALgAECggJCQAAAA==.Hattredyess:BAAALgAECgUJBQABLgAECggJCQAKAAAAAA==.',
He='Headrot:BAAALgAECgEJAgAAAA==.Heatedsoul:BAAALgAECgEJAQAAAA==.Helare:BAABLgAECn8XAAINAAkJ2xgMEgBIAgANAAkJ2xgMEgBIAgAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAABLgAECn8nAAIlAAkJrQ2rFAB4AQAlAAkJrQ2rFAB4AQAAAA==.',
Hi='Hinatsuru:BAAALgAECgQJBAAAAA==.',
Ho='Holyzap:BAAALgAECgIJAgABLgAECgkJJQAQABEhAA==.Horsegirl:BAAALgAECgEJAgAAAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Huffmetoes:BAEALgADCgcJDgABLgAECgkJPwAIAIMZAA==.Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECggJCQAAAA==.Huulrokk:BAAALgADCgkJDAABLgAECgkJFQAOAHoVAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.Hyperreal:BAAALgAECgEJAQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgkJJwALAJsbAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwAKAAAAAA==.Idlewild:BAEALgAECgYJCAABLgAECggJIAAPALwPAA==.',
If='Iforgotnaaru:BAABLgAECn8XAAMOAAcJ4QvVcgAEAQAOAAcJ4QvVcgAEAQAPAAQJtQrabACiAAAAAA==.',
Ik='Ikedizzy:BAAALgAECgEJAQABLgAFFAEJAQAKAAAAAA==.Ikeslice:BAAALgAFFAEJAQAAAA==.Ikrys:BAAALgAECgYJDAAAAA==.',
Il='Illiae:BAACLgAFFH8OAAIPAAMJPiNgHQAxAQAPAAMJPiNgHQAxAQAuAAQKfzAAAg8ACAl8JA8KAL4CAA8ACAl8JA8KAL4CAAAA.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8rAAIVAAgJxxOgLQCbAQAVAAgJxxOgLQCbAQAAAA==.',
In='Incrdblestan:BAAALgAECgMJBgAAAA==.Innex:BAABLgAECn8nAAIXAAkJGx+eLABNAgAXAAkJGx+eLABNAgAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECgkJJwAXABsfAA==.Innexvoker:BAABLgAECn8YAAIDAAgJag9SMgBsAQADAAgJag9SMgBsAQABLgAECgkJJwAXABsfAA==.Inpesca:BAAALgADCgUJBQABLgAFFAUJCQADAMQQAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgYJCwAAAA==.',
Ir='Iridescent:BAAALgAECgIJAgAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAABLgAECn8hAAIfAAgJNQ7DEwAkAQAfAAgJNQ7DEwAkAQAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itzmuffin:BAABLgAECn8oAAIOAAgJyRIoTQB8AQAOAAgJyRIoTQB8AQAAAA==.Itzpie:BAABLgAECn81AAIQAAkJNxYrSgD9AQAQAAkJNxYrSgD9AQAAAA==.',
Ja='Jace:BAABLgAECn8WAAIFAAYJDhyFggBqAQAFAAYJDhyFggBqAQAAAA==.Jadandotz:BAAALgADCggJAgAAAA==.Jagtat:BAABLgAECn8hAAMXAAgJjQ8YmQA3AQAXAAgJjQ8YmQA3AQAZAAUJcQcIRQB6AAAAAA==.Jakeakuma:BAABLgAECn8UAAIRAAkJBAwlXwCsAQARAAkJBAwlXwCsAQAAAA==.Jascob:BAABLgAECn8gAAImAAYJMQkuEwD0AAAmAAYJMQkuEwD0AAAAAA==.Jasonborne:BAAALgAECgQJBAAAAA==.Jaynne:BAAALgADCgcJCAAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAAALgAECgkJEgAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn9QAAIYAAkJsB8zBgDZAgAYAAkJsB8zBgDZAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8lAAIcAAgJGiFcCAD0AgAcAAgJGiFcCAD0AgABLgAFFAQJBAAKAAAAAA==.Junfan:BAAALgAECgcJCQAAAA==.',
['Jà']='Jàckblack:BAAALgAECgYJDAAAAA==.',
Ka='Kaashaa:BAACLgAFFH8VAAIHAAQJthvULQBVAQAHAAQJthvULQBVAQAuAAQKf0AAAgcACQnLIRQPANgCAAcACQnLIRQPANgCAAAA.Kaelsgf:BAAALgAECgcJDAAAAA==.Kahllan:BAABLgAECn82AAMNAAkJuhA+JACpAQANAAkJuhA+JACpAQAMAAEJ+RdMvwBGAAAAAA==.Kahnigitt:BAABLgAECn8XAAIXAAcJhwowqQAeAQAXAAcJhwowqQAeAQAAAA==.Kalsifire:BAAALgAECgYJBQAAAA==.Kataltoholic:BAABLgAECn8eAAIQAAYJpgGPDQBLAAAQAAYJpgGPDQBLAAAAAA==.Katrath:BAAALgADCgMJBgAAAA==.Kayhas:BAAALgAECgQJBQAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIBAAYJCxp5UAC1AQABAAYJCxp5UAC1AQAAAA==.Kaýhás:BAAALgADCgYJBgAAAA==.',
Ke='Kelinïsha:BAABLgAECn8pAAIQAAgJJQrqnwA7AQAQAAgJJQrqnwA7AQAAAA==.Kelynna:BAABLgAECn8pAAIIAAgJDhx4EgBKAgAIAAgJDhx4EgBKAgAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJBQAAAA==.',
Kh='Khaodemus:BAAALgAECggJCQAAAA==.Khellder:BAAALgAECggJEgABLgAECgkJEQAKAAAAAA==.Khelldyr:BAAALgAECggJCAABLgAECgkJEQAKAAAAAA==.Khellrond:BAAALgAECgkJEQAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiffira:BAAALgAECgkJCwABLgAECgkJKQABAEUWAA==.Kiiras:BAABLgAECn8vAAIQAAgJ9A2ThQBsAQAQAAgJ9A2ThQBsAQAAAA==.Kimbodh:BAACLgAFFH8iAAIBAAUJ/ST+IQCsAQABAAUJ/ST+IQCsAQAuAAQKfyYAAgEACAkOJKoOAM8CAAEACAkOJKoOAM8CAAEuAAEKAwkBAAoAAAAA.Kimoora:BAAALgAECgUJBwAAAA==.Kimshady:BAAALgADCgEJAQABLgAECgUJBwAKAAAAAA==.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8wAAIBAAkJ+BB5SQCqAQABAAkJ+BB5SQCqAQAAAA==.',
Kl='Klefthoof:BAABLgAECn9AAAMOAAgJjhTCLgD7AQAOAAgJjhTCLgD7AQAPAAIJcAQGnQA/AAAAAA==.',
Ko='Kodey:BAABLgAECn8pAAIaAAkJxxSBBgD4AQAaAAkJxxSBBgD4AQABLgAFFAQJEwAaAL8GAA==.Kordy:BAAALgAECgkJAQAAAA==.Korey:BAAALgAECgEJAQAAAA==.',
Kr='Kraniah:BAABLgAECn8VAAMOAAkJehUyHwBVAgAOAAkJehUyHwBVAgAPAAYJgATPdwCGAAAAAA==.Krelon:BAAALgAECgIJAgAAAA==.Krimboz:BAABLgAECn8vAAIRAAkJZxoXIABkAgARAAkJZxoXIABkAgAAAA==.Krimbrouge:BAAALgAECgYJCAAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8wAAITAAkJZxsjCgB9AgATAAkJZxsjCgB9AgAAAA==.Krìsta:BAACLgAFFH8GAAMbAAIJ7QLIEwBuAAAbAAIJ7QLIEwBuAAARAAEJ8QDJ1gAvAAAuAAQKfx4AAxsACAncDFgNAGABABsABwleDlgNAGABABEABwknBOTBAMkAAAAA.',
Ku='Kuanshuwo:BAABLgAECn8VAAMJAAgJ7wknOAA0AQAJAAgJ7wknOAA0AQAIAAYJfQZMTgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
Ky='Kyokan:BAAALgADCgYJBgAAAA==.',
La='Lanwulf:BAABLgAECn8UAAIFAAYJVAYB8ADKAAAFAAYJVAYB8ADKAAAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAACLgAFFH8LAAIJAAUJUxXiGQAaAQAJAAUJUxXiGQAaAQAuAAQKfxgAAgkACQlvHb4XACYCAAkACQlvHb4XACYCAAAA.Legaloas:BAABLgAECn8xAAMHAAkJnyDcFgCeAgAHAAkJnyDcFgCeAgAfAAUJGxFDGADwAAAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAABLgAECn8XAAIcAAcJ7A0+OgAYAQAcAAcJ7A0+OgAYAQAAAA==.Leonarde:BAACLgAFFH8PAAMHAAQJKBkARgAhAQAHAAQJIBkARgAhAQAfAAMJ2Q/RFQDuAAAuAAQKfyIABB8ACQkZGb8gACACAB8ACAkSF78gACACAAcABQl/GKFvAGEBABMAAQlWAKwzAA0AAAAA.Levitt:BAABLgAECn8WAAIRAAYJjhHCkwAUAQARAAYJjhHCkwAUAQABLgAECggJGwAdACUTAA==.Leyla:BAAALgADCgkJCQAAAA==.',
Li='Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn80AAIcAAkJbhZdFgAEAgAcAAkJbhZdFgAEAgAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liquid:BAAALgAECgEJAQAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgYJEAAAAA==.',
Ll='Llevanya:BAABLgAECn9CAAIFAAkJxhCsAwAFAQAFAAkJxhCsAwAFAQAAAA==.Llinaigh:BAACLgAFFH8LAAIHAAQJhBN8PwAuAQAHAAQJhBN8PwAuAQAuAAQKfxkAAgcACQmDFaI8AO4BAAcACQmDFaI8AO4BAAAA.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAgABLgAECgkJOQAVAB4gAA==.Lomu:BAABLgAECn8qAAQjAAkJnhsECgBIAgAjAAkJnhsECgBIAgAMAAEJ7Q5JzwAvAAANAAEJigSooAAhAAABLgAECgkJLQARAO0gAA==.Loredalso:BAAALgAECgEJAQAAAA==.Lorenitha:BAAALgAECgEJAQABLgAFFAQJDQAFABccAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
['Lê']='Lêdrollan:BAAALgAECgIJAgABLgAFFAUJCwAJAFMVAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAFFAMJCAALAGsbAA==.Magicdreams:BAABLgAECn80AAINAAkJNAn1MABZAQANAAkJNAn1MABZAQAAAA==.Malificent:BAAALgADCgQJCAAAAA==.Malmorte:BAABLgAECn8WAAIXAAYJMRUHowA6AQAXAAYJMRUHowA6AQAAAA==.Malorane:BAABLgAECn8vAAIZAAkJFhshCwBjAgAZAAkJFhshCwBjAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgAECgEJAQAAAA==.Marihuano:BAABLgAFFH8FAAIkAAIJGQydMgCYAAAkAAIJGQydMgCYAAAAAA==.Marisi:BAAALgADCggJCAABLgAECgcJBwAKAAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIkAAkJ0R3sEQAYAgAkAAkJ0R3sEQAYAgAAAA==.Materiaga:BAABLgAECn8iAAQDAAgJEhEFMAB4AQADAAgJwBAFMAB4AQACAAYJFQtdKQAoAQAWAAMJjw9uGACVAAAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8xAAIFAAkJKCE1EADkAgAFAAkJKCE1EADkAgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMhAAkJGxU2BgCWAgAhAAkJGxU2BgCWAgAPAAgJyg/YRAAgAQAAAA==.',
Me='Medalla:BAAALgADCgYJBgAAAA==.Meerchi:BAABLgAECn8wAAMQAAkJCBn1OQAxAgAQAAkJCBn1OQAxAgAnAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Mefysto:BAAALgAECgUJBQAAAA==.Meiriie:BAAALgAECgYJBwAAAA==.Meldia:BAAALgAECgEJAQABLgAECgYJBgAKAAAAAA==.Meowkai:BAAALgAECgYJBgABLgAECgkJJwATAA0lAA==.Mesmal:BAAALgAECgkJAwABLgAECgkJCQAKAAAAAA==.Mesthos:BAAALgAECgcJDAABLgAECgkJKAASACwmAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8lAAIDAAgJlBKOGgD2AQADAAgJlBKOGgD2AQAAAA==.',
Mi='Miciah:BAAALgAECgQJBAAAAA==.Mickieta:BAABLgAECn8/AAIFAAkJ4SDNFADFAgAFAAkJ4SDNFADFAgAAAA==.Microsurge:BAACLgAFFH8HAAIQAAQJ4AhIcgD8AAAQAAQJ4AhIcgD8AAAuAAQKfx0AAhAACAkiHdslANsCABAACAkiHdslANsCAAAA.Mikalau:BAACLgAFFH8FAAIHAAIJGQpgiQCLAAAHAAIJGQpgiQCLAAAuAAQKfzkAAgcACQkGF00CAG0BAAcACQkGF00CAG0BAAAA.Mikaluu:BAABLgAECn8nAAIRAAYJbxWZAQBGAQARAAYJbxWZAQBGAQAAAA==.Miqkail:BAAALgAECggJCgABLgAECgkJKAASACwmAA==.Missteek:BAAALgAECgYJEgABLgAECgkJRAAWAHQjAA==.Mistrunner:BAAALgAECgMJAwAAAA==.Mistspell:BAACLgAFFH8PAAIJAAQJpQ/BHgD8AAAJAAQJpQ/BHgD8AAAuAAQKfyAAAwkACQnXHeQOAJUCAAkACQnXHeQOAJUCAAgAAwklBoFqAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwABLgAECgkJJwALAJsbAA==.Mognel:BAABLgAECn82AAIRAAkJxxyRKgAwAgARAAkJxxyRKgAwAgAAAA==.Mogrungar:BAACLgAFFH8IAAIOAAMJRRDoVgCgAAAOAAMJRRDoVgCgAAAuAAQKfygAAg4ACQl3FConACQCAA4ACQl3FConACQCAAAA.Moistdk:BAAALgAECgEJAQAAAA==.Moisten:BAABLgAECn8eAAIPAAkJQyCBCADVAgAPAAkJQyCBCADVAgAAAA==.Mokuo:BAAALgAFFAIJAwAAAA==.Monklee:BAAALgAECgEJAgAAAA==.Moomootus:BAABLgAECn8yAAMFAAkJ4xoXOgAbAgAFAAgJaRoXOgAbAgALAAQJ/B4wPQBRAQAAAA==.Mordakttaa:BAAALgADCgMJAwAAAA==.Morgalea:BAAALgAECgcJAQAAAA==.Motoraxe:BAAALgAFFAIJAwAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIcAAgJRyBsDQClAgAcAAgJRyBsDQClAgABLgAFFAQJDwABAKgOAA==.Mystynight:BAAALgAECgYJEwAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAABLgAECn8lAAIPAAgJEA8zPQBBAQAPAAgJEA8zPQBBAQAAAA==.Naggs:BAAALgAECgkJCAAAAA==.Nagini:BAABLgAECn8fAAIRAAgJdwhBiwAjAQARAAgJdwhBiwAjAQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn8/AAMIAAkJgxkmHQDcAQAIAAcJGRkmHQDcAQAJAAkJtBGdPgAWAQAAAA==.Nietzcha:BAAALgAECgQJBwAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAABLgAECn8kAAMNAAgJ7Rb2HADhAQANAAgJ7Rb2HADhAQAlAAUJRw2pNwB8AAAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nilfgard:BAAALgAECgcJEAAAAA==.Nioh:BAABLgAECn8iAAIBAAkJxRavLwAIAgABAAkJxRavLwAIAgAAAA==.Nivix:BAAALgAECgEJAgAAAA==.',
No='Noodles:BAABLgAECn8nAAIBAAgJnwjJlwDxAAABAAgJnwjJlwDxAAAAAA==.Nordrydd:BAAALgAECggJDgABLgAFFAIJAgAKAAAAAA==.Nordrydsh:BAAALgAFFAIJAgAAAA==.',
Nu='Nuggs:BAABLgAECn8YAAIlAAkJzBB1EACwAQAlAAkJzBB1EACwAQAAAA==.Nuhpie:BAACLgAFFH8XAAMEAAcJhw4/KADMAAAVAAMJUxGXOADQAAAEAAQJugs/KADMAAAuAAQKfx4AAwQACQlfHfQfAF4BAAQABQmuGvQfAF4BABUABQlsHJVMABQBAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8lAAIXAAkJax/dGQCrAgAXAAkJax/dGQCrAgAAAA==.',
Od='Odelay:BAAALgADCgEJAQAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAwAAAA==.',
Ol='Olimdar:BAACLgAFFH8qAAIOAAgJjCR8AAA9AwAOAAgJjCR8AAA9AwAuAAQKfycAAw4ACQlvJUsAAM8DAA4ACQlvJUsAAM8DAA8AAQmSHaiCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBwAAAA==.',
Oo='Oopositive:BAAALgAECgUJDAAAAA==.Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Orgarrot:BAAALgADCgYJBgABLgAECggJCQAKAAAAAA==.Oricelle:BAABLgAECn8pAAIBAAkJRRaGKgAfAgABAAkJRRaGKgAfAgAAAA==.Oridis:BAAALgAECgkJBwAAAA==.Oryon:BAEBLgAECn8zAAIbAAkJnRR+CADgAQAbAAkJnRR+CADgAQAAAA==.',
Ov='Ovarb:BAABLgAECn8vAAMZAAkJshhEEgDqAQAZAAkJkRhEEgDqAQAXAAgJxw/dgwBcAQAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDgAAAA==.Palasexo:BAAALgAECgUJCQABLgAFFAIJBQAkABkMAA==.Palldude:BAAALgADCgQJBQAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Peachie:BAAALgADCgEJAQAAAA==.Pesti:BAACLgAFFH8hAAIkAAQJCB8zEgB9AQAkAAQJCB8zEgB9AQAuAAQKf1EAAiQACQlnI8YCACkDACQACQlnI8YCACkDAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8+AAIOAAkJQiM7BAB2AwAOAAkJQiM7BAB2AwAAAA==.',
Pi='Pissedwolf:BAAALgAECgUJCAAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAABLgAECn8fAAIYAAkJeBCZIACiAQAYAAkJeBCZIACiAQAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAACLgAFFH8VAAIQAAQJgxjyUgA3AQAQAAQJgxjyUgA3AQAuAAQKf0cABBAACQkJIq0OAAUDABAACQmIIa0OAAUDACgABQnyFiQMABABACcAAQmjEFIUADEAAAAA.Proctologist:BAABLgAECn8xAAMYAAkJ9BvECACmAgAYAAkJ9BvECACmAgAcAAQJYROmQwDwAAAAAA==.Proserpìne:BAABLgAECn9LAAIBAAkJzw2PVgCDAQABAAkJzw2PVgCDAQAAAA==.',
Ps='Psychojester:BAACLgAFFH8SAAIhAAQJRxqBBwA/AQAhAAQJRxqBBwA/AQAuAAQKf0MAAiEACQk2IWICAPcCACEACQk2IWICAPcCAAAA.Psylir:BAAALgAECgQJDgAAAA==.Psypra:BAAALgAECgYJCQAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAABLgAECn8WAAIQAAUJihtWvQANAQAQAAUJihtWvQANAQAAAA==.',
Py='Pydge:BAAALgAECgEJAQAAAA==.',
Qu='Quod:BAAALgAECgQJBAAAAA==.Quoril:BAACLgAFFH8FAAIQAAIJDQ+EogCKAAAQAAIJDQ+EogCKAAAuAAQKfz8AAxAACQkLIYcQAPgCABAACQkLIYcQAPgCACgAAQmXIHkZAEwAAAEuAAUUBgkfAAcA4BoA.',
Ra='Raijyu:BAABLgAECn9HAAMIAAkJzR9ABQAoAwAIAAkJzR9ABQAoAwAJAAcJVRV+IwC8AQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECgkJNgANAM8WAA==.Rainstormin:BAABLgAECn82AAMNAAkJzxZYFgAbAgANAAkJzxZYFgAbAgAjAAYJxgk+QQCiAAAAAA==.Rakarra:BAABLgAECn8fAAMMAAkJGgvNSABsAQAMAAkJGgvNSABsAQANAAcJhwgPTQD2AAAAAA==.Ranalia:BAAALgADCgcJCgAAAA==.Rawrstance:BAABLgAECn8+AAMZAAkJRRsaFwCuAQAZAAkJDRIaFwCuAQAXAAcJoRysdAB6AQABLgAECgEJAQAKAAAAAA==.Razgrize:BAACLgAFFH8MAAIQAAMJUxd4egDjAAAQAAMJUxd4egDjAAAuAAQKfzAAAhAACQmeG/YjAI0CABAACQmeG/YjAI0CAAAA.',
Re='Redraggon:BAAALgAECgYJBgAAAA==.Reecalled:BAAALgADCgUJBQABLgAECggJGgADAGIaAA==.Reeshan:BAABLgAECn8fAAMFAAkJ1yPCDgDwAgAFAAkJ1yPCDgDwAgALAAIJaxSUdABnAAAAAA==.Reilin:BAAALgAFFAEJAQAAAA==.Remsham:BAABLgAECn8nAAIhAAkJxg0ZEACwAQAhAAkJxg0ZEACwAQAAAA==.Reniel:BAAALgAECgcJCAABLgAECgkJMAABAPgQAA==.Renwyck:BAABLgAECn8oAAISAAkJLCZcAABjAwASAAkJLCZcAABjAwAAAA==.Reubenb:BAAALgAECgEJAQABLgAECgkJMQAHAAEPAA==.Revengemoon:BAACLgAFFH8RAAIFAAQJsxLhTAAUAQAFAAQJsxLhTAAUAQAuAAQKfyMAAgUACQmVGsApAH4CAAUACQmVGsApAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgAKAAAAAA==.Ringberg:BAACLgAFFH8IAAILAAMJaxsjLQDHAAALAAMJaxsjLQDHAAAuAAQKfxcAAwsABwlSHzwZAD0CAAsABwlSHzwZAD0CAAUAAwmmFNQLAaoAAAAA.',
Ro='Robane:BAABLgAECn8UAAIFAAUJCA+a5wDUAAAFAAUJCA+a5wDUAAAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Rockette:BAAALgADCgYJBgAAAA==.Ronburgundy:BAAALgAECgMJBQAAAA==.Rouen:BAABLgAECn80AAMOAAkJ2xoIFQCjAgAOAAkJ2xoIFQCjAgAhAAgJiiIZBwBgAgAAAA==.',
Ru='Rubidea:BAAALgAECgEJAQAAAA==.Ruckus:BAEBLgAECn8YAAQMAAcJjwvtXAAgAQAMAAcJjwvtXAAgAQAjAAMJnAaUXQBTAAANAAEJQQoOmgAnAAABLgAECggJIAAPALwPAA==.Ruder:BAAALgAECgMJBAABLgAECggJCQAKAAAAAA==.Rutabaga:BAAALgAECgUJCAAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIJAAkJxBtnEQBzAgAJAAkJxBtnEQBzAgAAAA==.',
Sa='Saintanic:BAAALgAECgEJAQAAAA==.Salyna:BAAALgAECgEJAwABLgAECgYJBgAKAAAAAA==.Sandkat:BAABLgAECn9BAAIVAAkJZCJpBgD4AgAVAAkJZCJpBgD4AgAAAA==.Sanstian:BAAALgAECgUJDQAAAA==.Santamou:BAAALgAECgIJBgAAAA==.Saraelin:BAABLgAFFH8IAAIRAAIJ8ABzvgBLAAARAAIJ8ABzvgBLAAAAAA==.Saray:BAAALgAECgcJEgAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAYJEwAVAO4QAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgYJDgAAAA==.Serahstia:BAABLgAECn8gAAIQAAkJBxX4ZQCyAQAQAAkJBxX4ZQCyAQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shadowmeld:BAAALgAECgEJAQAAAA==.Shadysadie:BAAALgAECgcJEQAAAA==.Shaiy:BAAALgAECgcJEAAAAA==.Shakejunt:BAAALgADCgIJAgAAAA==.Shammymoe:BAAALgAECgEJBAAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwAKAAAAAA==.Shiifthappen:BAAALgAECgEJAQAAAA==.Shinta:BAABLgAECn8WAAQLAAYJtRRaPwBHAQALAAYJtRRaPwBHAQAGAAUJ2g+4KwC/AAAFAAQJAwiqLgGBAAAAAA==.Shirtles:BAABLgAECn8YAAIPAAYJggOqdACOAAAPAAYJggOqdACOAAAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shpik:BAAALgADCgUJCQAAAA==.Shèp:BAABLgAECn8eAAILAAgJvxGqAQD4AAALAAgJvxGqAQD4AAAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIPAAUJ/hmfAwCvAQAPAAUJ/hmfAwCvAQABLgAFFAYJDgATACUWAA==.Siffrin:BAAALgAECgIJAgAAAA==.Siink:BAAALgAFFAEJAwAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8lAAMRAAgJnhWFdABRAQARAAYJ0hKFdABRAQAbAAUJJRajGgDpAAABLgAECggJJQADAJQSAA==.Sinkingship:BAAALgAECgYJCQAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAABLgAECn8nAAIZAAkJPyA+BgC/AgAZAAkJPyA+BgC/AgAAAA==.',
Sk='Skaterboi:BAAALgAECgYJBgAAAA==.Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sliy:BAAALgAECgIJAgAAAA==.Sloothe:BAAALgADCgQJBAAAAA==.Sloothi:BAAALgAECgEJAQAAAA==.Slyveria:BAAALgAECgMJBAAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.Snorri:BAAALgAFFAIJAwAAAA==.',
So='Sosorry:BAAALgADCgIJAgAAAA==.Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAABLgAECn8WAAIFAAkJgRpHNgAoAgAFAAkJgRpHNgAoAgAAAA==.',
Sp='Sprodage:BAABLgAECn9LAAILAAkJVhjnFQBcAgALAAkJVhjnFQBcAgAAAA==.',
St='Staggrsaurus:BAAALgAECgIJAwABLgAECgMJBAAKAAAAAA==.Stanil:BAABLgAECn8rAAMHAAkJcwnTcABfAQAHAAkJcwnTcABfAQAfAAEJWwAkmwAVAAAAAA==.Stayfrosty:BAAALgAECgcJDAAAAA==.Stellare:BAABLgAECn8wAAIUAAkJHRdlEQAUAgAUAAkJHRdlEQAUAgAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Stinklines:BAAALgAECgEJAgABLgAECgkJRAAWAHQjAA==.Strangetame:BAAALgADCgEJAQAAAA==.Striest:BAAALgAECgMJAwAAAA==.Styló:BAAALgAECggJEwAAAA==.',
Su='Suetonius:BAACLgAFFH8TAAIXAAQJRR92QwBuAQAXAAQJRR92QwBuAQAuAAQKfxQAAxcACAlXJHwRAOECABcACAlXJHwRAOECACIAAgk4EzAvAGMAAAAA.Suguru:BAAALgAECggJCQAAAA==.Sungsuf:BAAALgAECgEJAQAAAA==.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8rAAIQAAkJaBqLOAA2AgAQAAkJaBqLOAA2AgAAAA==.Suraschi:BAABLgAECn8YAAMYAAkJ/xeoFwDrAQAYAAkJOReoFwDrAQAcAAcJjhFGLgBRAQABLgAECgkJKwAQAGgaAA==.',
Sv='Svelda:BAABLgAECn8xAAMJAAkJDg7bJwCQAQAJAAkJDg7bJwCQAQAgAAUJmAUNUwC1AAAAAA==.',
Sw='Swisscake:BAABLgAECn9JAAINAAkJaySoAgBHAwANAAkJaySoAgBHAwAAAA==.',
Sy='Sylain:BAAALgAECgYJEgABLgAECgkJFQAkAKEKAA==.Synwav:BAAALgADCgEJAQAAAA==.',
Ta='Tannatax:BAABLgAECn8vAAIOAAkJZQbOWwBKAQAOAAkJZQbOWwBKAQAAAA==.Tashah:BAAALgADCggJCwAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAAKAAAAAA==.Tekvet:BAAALgAECgkJCQAAAA==.',
Th='Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8jAAMQAAkJnBWMVADfAQAQAAkJnBWMVADfAQAnAAEJGgGPGAAJAAAAAA==.Thewretch:BAABLgAECn85AAIRAAkJhyLYBwAZAwARAAkJhyLYBwAZAwAAAA==.Thibble:BAAALgADCgYJBgAAAA==.Thumpthump:BAABLgAECn8nAAQTAAkJQBivFAD+AQAfAAYJwx6nIgARAgATAAkJMhCvFAD+AQAHAAEJqQ7oLwE3AAAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEBLgAECn8gAAIPAAgJvA9VNwBbAQAPAAgJvA9VNwBbAQAAAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Titiera:BAABLgAECn8hAAIHAAgJKxerOwDxAQAHAAgJKxerOwDxAQAAAA==.',
To='Toastnbutta:BAABLgAECn8mAAIMAAkJ9xnRGAB/AgAMAAkJ9xnRGAB/AgAAAA==.Tolten:BAABLgAECn8eAAIFAAgJ3RmUMQBcAgAFAAgJ3RmUMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgYJCAAAAA==.Traumatism:BAAALgAECgkJEwAAAA==.Trevor:BAABLgAECn9BAAImAAkJUhhpBABPAgAmAAkJUhhpBABPAgAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAACLgAFFH8KAAMlAAMJARiZCwD6AAAlAAMJARiZCwD6AAAjAAEJXBmLNgBKAAAuAAQKfyAAAyUACQnLIogBAC4DACUACQnLIogBAC4DACMABgk0HBMZAIYBAAEuAAUUBQkYABkArhwA.Tsura:BAAALgAFFAEJAQAAAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Ty='Tylaesh:BAAALgAECgYJDwAAAA==.',
Un='Unclepeepers:BAACLgAFFH8VAAIdAAQJ4iDhIQBfAQAdAAQJ4iDhIQBfAQAuAAQKfy4AAxwACQkPIxYQAEsCABwACAmOIhYQAEsCAB0ACQm0G5ojAAMCAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAABLgAECn8YAAIXAAcJ3QvnygDvAAAXAAcJ3QvnygDvAAAAAA==.',
Ur='Urtag:BAACLgAFFH8UAAMfAAgJVBMoDgB8AQAfAAcJRA0oDgB8AQAHAAQJ7xJkMQBMAQAuAAQKfxUAAx8ACAnyFboqANYBAB8ACAkZFboqANYBAAcAAgm6F3PYAJwAAAAA.',
Ut='Uthgar:BAAALgAECgYJCAAAAA==.',
Va='Vadge:BAAALgADCgcJBwABLgAECgEJAQAKAAAAAA==.Vaeryn:BAABLgAECn8gAAIHAAcJlxQrBAD8AAAHAAcJlxQrBAD8AAABLgAFFAMJDQAgAKsOAA==.Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAACLgAFFH8NAAIgAAMJqw6BBgBxAAAgAAMJqw6BBgBxAAAuAAQKf3MAAyAACAlXH90JANMCACAACAlXH90JANMCAAkABwneEPUxAFQBAAAA.Valryn:BAABLgAECn8ZAAMXAAcJKgsNogApAQAXAAcJKgsNogApAQAZAAEJxgH7TwAVAAABLgAFFAMJDQAgAKsOAA==.Valtar:BAABLgAECn8hAAIOAAkJoBxqGgB3AgAOAAkJoBxqGgB3AgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAACLgAFFH8IAAMXAAUJRRQ/YAA0AQAXAAUJRRQ/YAA0AQAZAAMJyhEkDgCJAAAuAAQKfzAAAxcACQmJI7wGAEEDABcACQmJI7wGAEEDABkACAntHUsPABcCAAAA.',
Ve='Veliraleonoc:BAAALgAECgEJAQAAAA==.Velra:BAAALgADCgEJAQABLgAFFAMJDQAgAKsOAA==.Velryn:BAAALgAECgYJEwABLgAFFAMJDQAgAKsOAA==.Veraalyn:BAABLgAECn8dAAMPAAgJHhH7RQAcAQAPAAgJHhH7RQAcAQAOAAMJxwiifgCZAAAAAA==.',
Vi='Vicsen:BAABLgAECn8gAAIRAAkJdQVYgQA2AQARAAkJdQVYgQA2AQAAAA==.Vikaya:BAAALgAECggJCgAAAA==.Vilaris:BAAALgAECggJCwAAAA==.Vilevixon:BAABLgAECn8hAAMJAAkJ4hbeFwAIAgAJAAkJ4hbeFwAIAgAgAAMJxgcZYAB9AAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Vo='Voidasuras:BAAALgAECgEJAQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAAKAAAAAA==.Wanlok:BAAALgAECgQJCQAAAA==.Wantoo:BAAALgAECgYJBgAAAA==.Warlokip:BAAALgAECgkJCgAAAA==.Warotar:BAAALgAECgIJAgAAAA==.Warriorlobo:BAABLgAECn85AAQVAAkJHiDNCADUAgAVAAkJHiDNCADUAgAEAAYJ7RDUMgD7AAAeAAEJ6A4LWgAjAAAAAA==.Warvision:BAAALgAFFAEJAQAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAABLgAECn8iAAMHAAkJKQw3VgChAQAHAAkJKQw3VgChAQATAAEJQwNUagAoAAAAAA==.Wildside:BAABLgAECn8iAAMHAAgJ8R8zHQB2AgAHAAgJ8R8zHQB2AgATAAYJCxZ3KABcAQAAAA==.',
Wu='Wujifei:BAAALgAFFAIJAwAAAA==.Wulffgar:BAAALgAECgYJCAAAAA==.',
['Wì']='Wìldthìng:BAAALgAECgUJCgAAAA==.',
Xa='Xandronys:BAAALgAECgkJDAAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECggJCgAAAA==.Xenie:BAAALgAECggJEgAAAA==.Xennile:BAAALgAECgYJBwAAAA==.',
Xi='Xinema:BAAALgAECgQJBAAAAA==.Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgAECgYJEAAAAA==.',
Yd='Ydeatho:BAAALgAFFAMJAwAAAA==.',
Ye='Yeet:BAABLgAECn8cAAIkAAkJNBj5IgDhAQAkAAkJNBj5IgDhAQAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgMJBgAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgAECgMJBgAAAA==.Zalanna:BAAALgADCgMJAwAAAA==.Zalckar:BAABLgAECn8bAAMLAAkJcBIZRQBjAQALAAkJcBIZRQBjAQAFAAEJYQ7qoAEtAAAAAA==.Zanos:BAAALgAECgIJAgAAAA==.Zarayssa:BAAALgADCgYJDgAAAA==.Zarnok:BAAALgADCgkJCQAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zebracakes:BAAALgAECgEJAQABLgAECgkJSAASAOMlAA==.Zeeva:BAABLgAECn8cAAMaAAYJxiGVCADDAQAaAAYJ7SCVCADDAQAbAAMJ+h1mKAB/AAAAAA==.Zendead:BAABLgAECn8jAAIcAAkJCiP+BwDIAgAcAAkJCiP+BwDIAgAAAA==.Zeppeli:BAAALgAECgMJAwAAAA==.Zerkces:BAAALgADCgIJAgAAAA==.',
Zi='Zionspartan:BAABLgAECn8xAAIHAAkJAQ/bRADTAQAHAAkJAQ/bRADTAQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugpriest:BAAALgAECgQJBAAAAA==.Zugzugshaman:BAABLgAECn8wAAQOAAkJ6xkPGACJAgAOAAkJ6xkPGACJAgAPAAQJrwOHbgCJAAAhAAEJYQCkSAAdAAAAAA==.Zurokhan:BAAALgAECgUJBQAAAA==.Zuzill:BAAALgAECgUJBQABLgAECgYJHAAaAMYhAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Êï']='Êïñstëïn:BAAALgAECgEJAQAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8kAAIYAAgJmxFxJgB7AQAYAAgJmxFxJgB7AQAAAA==.',
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
