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

local lookup = {'DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Paladin-Holy','Unknown-Unknown','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','Hunter-Survival','Monk-Mistweaver','DemonHunter-Havoc','Warrior-Fury','Evoker-Devastation','Rogue-Outlaw','DeathKnight-Unholy','Monk-Brewmaster','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Monk-Windwalker','Warrior-Protection','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','DeathKnight-Frost','Druid-Guardian','Rogue-Subtlety','Druid-Feral','Rogue-Assassination','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-08-18',data={Ab='Aberration:BAAALgAECgEJAgAAAA==.Abraxidormu:BAAALgAECgYJBgABLgAECgkJMAABAPgQAA==.',
Ad='Adorraa:BAAALgAFFAIJAgAAAA==.Adoryn:BAAALgADCgYJCQAAAA==.Adowyrm:BAACLgAFFH8vAAMCAAkJphfmCQAMAgACAAkJphfmCQAMAgADAAQJpBCmPADVAAAuAAQKfyEAAwIACQm1IUcCAFEDAAIACQm1IUcCAFEDAAMABgnLHfscAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.Adrielle:BAAALgAECgkJEwAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECgkJHQAEAIgcAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAFFAQJBAAAAA==.Agtar:BAAALgAECgMJAwAAAA==.',
Ai='Airali:BAACLgAFFH8KAAIFAAUJ+gXrYADtAAAFAAUJ+gXrYADtAAAuAAQKfxcAAwUACQn+E2tkALgBAAUACQn+E2tkALgBAAYAAwmJCNM3AGIAAAAA.Airedale:BAABLgAECn85AAIHAAkJPhnBCAD7AQAHAAkJPhnBCAD7AQAAAA==.',
Ak='Akairo:BAACLgAFFH8FAAIIAAQJNRuFCgC8AAAIAAQJNRuFCgC8AAAuAAQKfzEAAwgACQkAJIICAEEDAAgACQkAJIICAEEDAAkACAmsEborAHcBAAAA.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgAECgYJBgABLgAFFAUJCgADAMQQAA==.Alderbaran:BAAALgADCgUJBQAAAA==.Alexanderlx:BAABLgAECn8WAAMGAAYJAB1gFwBfAQAGAAYJAB1gFwBfAQAFAAUJWBXRxAACAQAAAA==.Aleybobwa:BAABLgAECn8gAAQKAAkJjhLIKgC5AQAKAAkJjhLIKgC5AQAGAAEJvRiJFQBFAAAFAAEJYwiPUgErAAAAAA==.Alody:BAAALgADCgMJAwABLgAECgYJBgALAAAAAA==.Alucardo:BAAALgAECgQJBQAAAA==.Alyméré:BAAALgAECgYJCAAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAABLgAECn8nAAIKAAkJmxsaDQC/AgAKAAkJmxsaDQC/AgAAAA==.Amord:BAAALgADCgEJAQAAAA==.Amoreena:BAAALgADCgQJAgAAAA==.Amulius:BAACLgAFFH8GAAIFAAMJtSVvOAA8AQAFAAMJtSVvOAA8AQAuAAQKfzYAAgUACQnyJZQEAFUDAAUACQnyJZQEAFUDAAAA.',
An='Anderdingus:BAAALgADCgYJCgAAAA==.Andormath:BAAALgAECgQJBgAAAA==.Andramedae:BAABLgAECn9AAAMMAAkJtBsBEgC/AgAMAAkJtBsBEgC/AgANAAYJQg4wSQDnAAAAAA==.Angerissues:BAAALgADCgkJCQAAAA==.Angyavocado:BAAALgAFFAEJAQAAAA==.Anoki:BAABLgAECn9DAAMOAAkJIxs1FQChAgAOAAkJIxs1FQChAgAPAAEJgQshtQAmAAAAAA==.',
Ao='Aolus:BAACLgAFFH8SAAINAAQJwhgIIgARAQANAAQJwhgIIgARAQAuAAQKfxsAAg0ACQkVHDETAHsCAA0ACQkVHDETAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgAECgEJAQAAAA==.Aprollon:BAAALgAECgEJAgAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJBAALAAAAAA==.Arcaina:BAABLgAECn8kAAIQAAkJLglCegCEAQAQAAkJLglCegCEAQAAAA==.Arconn:BAAALgADCgEJAQAAAA==.Ares:BAAALgADCgkJHAABLgAECgkJPAARAPAXAA==.Arez:BAABLgAECn88AAIRAAkJ8BdVKQA2AgARAAkJ8BdVKQA2AgAAAA==.Arilass:BAAALgADCgIJBAAAAA==.Armis:BAAALgADCgEJAQABLgAECgkJSAASAOMlAA==.Artèmís:BAABLgAECn8nAAITAAkJDSVaAwACAwATAAkJDSVaAwACAwABLgAECgkJPAAUAB0fAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Ashtongue:BAAALgAECgYJDQAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athinea:BAAALgAECgYJCgAAAA==.Athlon:BAAALgAECgIJAgAAAA==.',
Au='Aura:BAAALgAFFAEJAQAAAA==.',
Aw='Awake:BAAALgAECgQJBAAAAA==.',
Ay='Ayahuasca:BAAALgADCgIJAgAAAA==.',
Az='Azaekho:BAABLgAECn8kAAIOAAkJcxQIKgDmAQAOAAkJcxQIKgDmAQAAAA==.Azaelleonoc:BAAALgAECgEJAQAAAA==.Azalet:BAAALgAFFAIJAgAAAA==.',
Ba='Baalzak:BAAALgADCgYJBQAAAA==.Backfliphoe:BAABLgAECn8aAAIVAAkJuRc5GQC4AQAVAAkJuRc5GQC4AQAAAA==.Badoosh:BAABLgAECn8pAAIWAAgJbB6aGACHAgAWAAgJbB6aGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Baisan:BAAALgAFFAEJAQAAAA==.Bajablaster:BAABLgAECn9EAAQXAAkJdCOpAAA7AwAXAAkJdCOpAAA7AwADAAMJ5BD7TACdAAACAAEJMAssPgArAAAAAA==.Baliw:BAAALgAECgUJCgAAAA==.Balltze:BAAALgAFFAEJAQAAAA==.Balto:BAAALgADCgMJAwAAAA==.Barbearic:BAAALgAECgEJAQAAAA==.',
Bb='Bbl:BAECLgAFFH8jAAIPAAgJQxWmCwCJAQAPAAgJQxWmCwCJAQAuAAQKfyUAAg8ACQnWIFgKAPACAA8ACQnWIFgKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8RAAIQAAQJ2xFGKwAIAQAQAAQJ2xFGKwAIAQAuAAQKfyMAAhAACQnDGZo7AIgCABAACQnDGZo7AIgCAAAA.',
Be='Bedrewd:BAAALgAECgEJAQAAAA==.Beertits:BAAALgAECgEJAQAAAA==.Belip:BAACLgAFFH8GAAIFAAIJJQ26kwCMAAAFAAIJJQ26kwCMAAAuAAQKfxgAAgUACQkfEYxXAMUBAAUACQkfEYxXAMUBAAAA.Belphyssa:BAAALgADCggJCAAAAA==.Bertus:BAAALgAFFAIJAwABLgAFFAkJJwAYAG8lAA==.',
Bh='Bhain:BAAALgAECgEJAgABLgAFFAUJGgAFAKwfAA==.',
Bi='Bieorne:BAABLgAECn87AAIZAAkJrSECDwD0AgAZAAkJrSECDwD0AgAAAA==.Bigpan:BAAALgAECgIJAgABLgAECggJJAAaAJsRAA==.Bipölar:BAAALgAECgIJAgAAAA==.',
Bl='Blastbane:BAACLgAFFH8LAAIRAAQJXQsUYwABAQARAAQJXQsUYwABAQAuAAQKfxQAAhEACQnuFBA3AP0BABEACQnuFBA3AP0BAAEuAAUUBwkVABsAjxAA.Bloodwrath:BAAALgAECgcJEwAAAA==.Bluenads:BAAALgAECgUJBwABLgAECgkJJwAKAJsbAA==.Blueveins:BAABLgAECn8VAAIQAAcJ/gWi1gDoAAAQAAcJ/gWi1gDoAAAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAACLgAFFH8FAAIRAAIJ5R7xlACYAAARAAIJ5R7xlACYAAAuAAQKfxgAAxEACQnvHP4PAPoCABEACQnvHP4PAPoCABwAAQkAAExQAAAAAAEuAAUUAwkIAAoAaxsA.Boondemon:BAAALgAECgIJAgAAAA==.Boondocks:BAABLgAECn9BAAMRAAkJ9R9OCQB1AQARAAYJIBtOCQB1AQAdAAUJ8CHQDgBvAQAAAA==.',
Br='Braca:BAAALgAECgYJEAABLgAECgkJNwAOAEcfAA==.Braelek:BAAALgADCgEJAQAAAA==.Brains:BAAALgAECgEJAQAAAA==.Bread:BAAALgAECgYJCwAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAABLgAECn8ZAAIaAAkJLQ/qIwCMAQAaAAkJLQ/qIwCMAQABLgAECgkJLgARAO0gAA==.Brielle:BAABLgAECn8wAAIHAAkJnhgALAAtAgAHAAkJnhgALAAtAgAAAA==.Brokenbranch:BAABLgAECn8aAAIMAAgJywjpawDxAAAMAAgJywjpawDxAAAAAA==.Brudene:BAABLgAECn8UAAIWAAcJFRF2VABZAQAWAAcJFRF2VABZAQAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Bubbletruble:BAAALgAECgYJBgAAAA==.Buddylock:BAABLgAECn8iAAIRAAkJmgm3ewBBAQARAAkJmgm3ewBBAQAAAA==.Bulltaura:BAAALgAECgcJBwAAAA==.Bullymaguire:BAACLgAFFH8RAAIeAAcJRhsUBgC2AQAeAAcJRhsUBgC2AQAuAAQKfx0AAh4ACAk5I0EFADEDAB4ACAk5I0EFADEDAAEuAAUUCAkQAAEA6BgA.Bumblebtuna:BAAALgAECgcJBgAAAA==.Burakkuburu:BAABLgAECn88AAMUAAkJHR8ICQALAwAUAAkJHR8ICQALAwAeAAYJMRlGMQBBAQAAAA==.Buu:BAAALgAECgUJBQAAAA==.',
Ca='Caboozles:BAABLgAECn87AAIHAAkJCRaMOwDxAQAHAAkJCRaMOwDxAQAAAA==.Caliopia:BAABLgAECn8xAAMPAAkJvBQCIADjAQAPAAkJvBQCIADjAQAOAAYJYQqXcQAIAQAAAA==.Caliper:BAAALgAECgEJAQAAAA==.Canrif:BAAALgAECgYJBgAAAA==.Caplyta:BAABLgAECn8UAAISAAkJtR98BgAtAgASAAkJtR98BgAtAgABLgAFFAUJEgAJACscAA==.Captnhuntcat:BAAALgAECggJEwAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.Cathode:BAAALgAFFAEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8vAAIWAAkJNxevEwBUAgAWAAkJNxevEwBUAgAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAABLgAECn8bAAMbAAkJaR2cEAABAgAbAAkJaR2cEAABAgAZAAQJJA/ZyQDxAAAAAA==.Chemistree:BAABLgAECn88AAIMAAkJmxQaJwAXAgAMAAkJmxQaJwAXAgAAAA==.Chewtum:BAAALgAECgIJAgAAAA==.Chillout:BAABLgAECn8nAAIQAAkJvw2LYwC3AQAQAAkJvw2LYwC3AQAAAA==.Chillums:BAABLgAECn8cAAIRAAcJ4iP7GgCzAgARAAcJ4iP7GgCzAgAAAA==.Chipcle:BAAALgAECgQJBwAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Ci='Cillah:BAAALgAECgEJAwABLgAECgkJOQAWAPwfAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgAECgEJAQALAAAAAA==.Clymax:BAAALgAECgIJAgAAAA==.',
Co='Codeblue:BAAALgADCgkJEQAAAA==.Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8dAAIKAAkJYg7CKQDAAQAKAAkJYg7CKQDAAQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Cy='Cy:BAABLgAECn8jAAMUAAkJCBavCQCQAQAUAAkJCBavCQCQAQAeAAIJmhSQEQB5AAAAAA==.Cynistrawna:BAAALgAECgUJBQAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAABLgAECggJFQAZAB4bAA==.Daeleiel:BAAALgAECgEJAQAAAA==.Damrek:BAAALgAECgEJAQAAAA==.Darkenergy:BAABLgAECn9DAAMVAAkJpiToAQBTAwAVAAkJpiToAQBTAwABAAkJuh85EQC4AgAAAA==.Darkyucie:BAAALgAECgEJAQAAAA==.Darà:BAABLgAECn8mAAMIAAgJAA9OBgB8AQAIAAgJAA9OBgB8AQAJAAYJUwioEwCiAAABLgAECgkJRQANANgSAA==.Dashyll:BAAALgAECgkJDQAAAA==.Davyfknjones:BAABLgAECn8aAAIHAAgJTxhFOAD9AQAHAAgJTxhFOAD9AQAAAA==.Daynia:BAAALgAECgYJEQAAAA==.',
De='Deadbolt:BAAALgAECgYJBgAAAA==.Deadlegslul:BAABLgAECn81AAIHAAkJmCGQAgDuAgAHAAkJmCGQAgDuAgAAAA==.Deadlegsmd:BAAALgAECgYJDgAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadtree:BAAALgAECgEJAQAAAA==.Deadzepplin:BAAALgAECgUJDgAAAA==.Deathfish:BAAALgAECgUJBgAAAA==.Deathmono:BAAALgAECgYJDQAAAA==.Deathshark:BAACLgAFFH8dAAIbAAUJrhy/FQA+AQAbAAUJrhy/FQA+AQAuAAQKfzEAAhsACQkLH/oNACoCABsACQkLH/oNACoCAAAA.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAABLgAECn8kAAIQAAcJyAzyoAA5AQAQAAcJyAzyoAA5AQABLgAECggJRwAOAAcVAA==.Demeter:BAABLgAECn9EAAIGAAkJvBT8DQDlAQAGAAkJvBT8DQDlAQAAAA==.Demiurge:BAAALgAECgIJAgAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denalli:BAAALgAECgUJCQAAAA==.Denarien:BAAALgAECgkJDwAAAA==.Derpygos:BAAALgADCgcJBwABLgAECgkJLgARAO0gAA==.Detroitt:BAAALgADCgIJAgAAAA==.Devouress:BAACLgAFFH8QAAIBAAQJqA4yUgD3AAABAAQJqA4yUgD3AAAuAAQKfxoAAgEACAmEGIw7ANkBAAEACAmEGIw7ANkBAAAA.Deynil:BAAALgADCgEJAQAAAA==.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dika:BAAALgAECgEJAQABLgAECgcJCQALAAAAAA==.Dikasmuasha:BAAALgAECgUJBQABLgAECgcJCQALAAAAAA==.Dillkiller:BAABLgAECn8XAAIfAAcJGQn9IQAuAQAfAAcJGQn9IQAuAQAAAA==.Dirgen:BAABLgAECn9hAAMWAAkJth6VAQC+AgAWAAkJth6VAQC+AgAfAAEJzhxXSgBMAAAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dogmaww:BAAALgAECggJDgAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAFFAUJEwAaAPMJAA==.Double:BAAALgAECgQJBAAAAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAABLgAECn8aAAIDAAgJYhpfHADyAQADAAgJYhpfHADyAQAAAA==.Dragginballs:BAAALgAECgIJBAABLgAFFAIJAgALAAAAAA==.Draggnar:BAABLgAECn8YAAIcAAcJeAiCGgDQAAAcAAcJeAiCGgDQAAAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Drained:BAAALgADCgEJAQAAAA==.Drakomoe:BAAALgAFFAEJAwABLgAFFAEJBAALAAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAABLgAECn8mAAMTAAkJgA+nFAD/AQATAAkJeA+nFAD/AQAgAAcJeAZWIACtAAAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJEQAPAFghAA==.',
Du='Dumplingsxo:BAABLgAECn8kAAMNAAkJnBhBGQA9AgANAAgJsBlBGQA9AgAMAAcJ4BiYPQCtAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn9IAAMSAAkJ4yVgAABiAwASAAkJ4yVgAABiAwAVAAYJgx1qGgCsAQAAAA==.',
Eb='Ebojager:BAABLgAECn9AAAIBAAkJVhpqHABqAgABAAkJVhpqHABqAgAAAA==.',
Eh='Ehko:BAAALgAECgYJCwABLgAECgkJPAAUAB0fAA==.',
Ei='Eibon:BAACLgAFFH8lAAIZAAkJpx6hCwCDAgAZAAkJpx6hCwCDAgAuAAQKfx4AAhkACQnNIakUAAADABkACQnNIakUAAADAAAA.Einfreren:BAAALgAECgQJBAAAAA==.Einjeru:BAAALgAECgUJBQAAAA==.',
El='Elliiria:BAAALgAECgQJBgAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgkJEwAAAA==.Elvispriesty:BAABLgAECn8gAAIhAAcJQxXbIADHAQAhAAcJQxXbIADHAQAAAA==.Elwarrioro:BAAALgAFFAMJBAAAAA==.',
Em='Emaleonoc:BAAALgAECgEJAwAAAA==.Emmpunity:BAAALgAECgQJBAAAAA==.Emmune:BAABLgAECn8qAAIiAAkJ9BWqCQAiAgAiAAkJ9BWqCQAiAgAAAA==.',
En='Enobia:BAABLgAECn87AAMcAAkJIh2hAwBXAgAcAAkJIh2hAwBXAgARAAUJFgbDxADQAAAAAA==.Entrapment:BAAALgADCgYJBgABLgAECgEJAQALAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Ep='Epsï:BAAALgAECgEJAQAAAA==.',
Er='Eriaeda:BAAALgAECgUJDQAAAA==.',
Es='Esen:BAAALgAECgQJBQABLgAECgkJPAARAPAXAA==.Eskath:BAABLgAECn8uAAIRAAkJ7SDoDADmAgARAAkJ7SDoDADmAgAAAA==.Essential:BAACLgAFFH8IAAIFAAQJNgvkWgD6AAAFAAQJNgvkWgD6AAAuAAQKfx0AAgUACAnpEnJ7AHgBAAUACAnpEnJ7AHgBAAAA.',
Et='Eternalpain:BAAALgAECgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8hAAIeAAYJfxNUPQALAQAeAAYJfxNUPQALAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgQJCQAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Felpickles:BAAALgAECgMJBAABLgAECgEJAQALAAAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgAECgEJAQABLgAECggJJAAaAJsRAA==.Ferrara:BAACLgAFFH8tAAQTAAkJ7iOoAgAPAgATAAcJUiSoAgAPAgAgAAcJkx71CwBdAQAHAAEJtx+1HwBiAAAuAAQKfyAABCAACQnRIykGADoDACAACQmLIykGADoDAAcAAQn1I6ywAGIAABMAAQk6HgIsAEYAAAAA.',
Fi='Filthi:BAABLgAECn8XAAIPAAYJRiFuIAANAgAPAAYJRiFuIAANAgAAAA==.Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgUJBwAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgkJSQANAGskAA==.Fisted:BAAALgAFFAEJAQABLgAFFAMJCAAKAGsbAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8jAAQIAAkJxSCmAAD9AgAIAAkJsCCmAAD9AgAhAAEJ8R/QKABcAAAJAAEJUg72OgBDAAAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.Fluorita:BAAALgAECgEJAQAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Freebird:BAAALgAECgEJAQAAAA==.Friedá:BAAALgAECgIJAwABLgAECgYJEgALAAAAAA==.Frostednip:BAACLgAFFH8RAAMZAAUJJhoTYAA0AQAZAAUJ3RkTYAA0AQAjAAIJoRIZHwCNAAAuAAQKfyQAAyMACQnaIPwJAOMBABkACQm/IE4+AAkCACMABwmhG/wJAOMBAAAA.Frozar:BAAALgAECgEJAgAAAA==.',
Ga='Gabaghoul:BAAALgAECgQJBAAAAA==.Gabiru:BAACLgAFFH8IAAQDAAMJ9gQVTgCWAAADAAMJ9gQVTgCWAAACAAMJ4w6eIwCEAAAXAAEJlwEsDABCAAAuAAQKfxUAAwIACQlTE2YSABkCAAIACQlTE2YSABkCAAMAAQm0CZphADUAAAAA.Gadreeste:BAAALgAECggJCQAAAA==.Galnarn:BAACLgAFFH8uAAIaAAkJvR9YCAAKAgAaAAkJvR9YCAAKAgAuAAQKfyEAAhoACQlkHfgNALQCABoACQlkHfgNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Gank:BAAALgAFFAEJAQABLgAFFAgJIAABAEUXAA==.Garious:BAAALgAECgcJBwABLgAFFAcJFAAZAI8hAA==.Garjingo:BAAALgAECgUJBgABLgAECgkJRAAXAHQjAA==.Garlicbae:BAABLgAECn8eAAIkAAkJngznBgAzAQAkAAkJngznBgAzAQAAAA==.Garwulf:BAABLgAECn8dAAITAAkJbwYWIwCFAQATAAkJbwYWIwCFAQAAAA==.',
Ge='Gefaustet:BAABLgAECn9EAAQfAAkJHBuXCwA0AgAfAAkJHBuXCwA0AgAEAAEJKwqmHQAsAAAWAAEJ8gbQqwArAAAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gi='Gilberticus:BAAALgAECgcJCgABLgAECgkJZgAeANIiAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECggJCwAAAA==.Glyd:BAAALgAECgYJCQABLgAECggJRwAOAAcVAA==.',
Go='Goatcheesè:BAAALgAECgIJBAAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAFFAEJAQAAAA==.Gorbachev:BAAALgAECgYJCAAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAABLgAECn8cAAMaAAkJ+AqsKABtAQAaAAkJ+AqsKABtAQAeAAMJHgJxqgAoAAAAAA==.Grayes:BAABLgAECn8hAAMkAAYJMQjfRACUAAAkAAYJMQjfRACUAAAMAAIJLwIW9QAdAAABLgAECgkJHAAaAPgKAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grr:BAAALgAECgMJBAAAAA==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Guldaniel:BAAALgAECgEJAQAAAA==.Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hail:BAAALgADCgUJBQABLgAFFAUJCgADAMQQAA==.Hallowshade:BAABLgAECn8XAAIlAAcJFhnlJQDKAQAlAAcJFhnlJQDKAQAAAA==.Hardran:BAACLgAFFH8GAAIFAAIJYgPcpwByAAAFAAIJYgPcpwByAAAuAAQKfycAAgUACAl3Ei0WACwBAAUACAl3Ei0WACwBAAAA.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgAECgYJDwAAAA==.Hatreddyes:BAAALgAECgMJAwABLgAECgkJCwALAAAAAA==.Hatredyes:BAAALgAECgkJCwAAAA==.Hattredyess:BAAALgAECgUJBQABLgAECgkJCwALAAAAAA==.',
He='Headrot:BAAALgAECgEJAgAAAA==.Heatedsoul:BAAALgAECgEJAQAAAA==.Helanne:BAAALgADCgUJBQAAAA==.Helare:BAABLgAECn8XAAINAAkJ2xgNEgBIAgANAAkJ2xgNEgBIAgAAAA==.Helowyn:BAAALgAECgUJBQAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAABLgAECn8nAAImAAkJrQ2uFAB4AQAmAAkJrQ2uFAB4AQAAAA==.',
Hi='Hinatsuru:BAAALgAECgQJBAAAAA==.',
Ho='Holyzap:BAAALgAECgIJAgABLgAECgkJJQAQABEhAA==.Horsegirl:BAAALgAECgEJAgAAAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Huffmetoes:BAEALgADCgcJFAABLgAECgkJQAAIAIMZAA==.Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECggJCQAAAA==.Huulrokk:BAAALgADCgkJDAABLgAECgkJFQAOAHoVAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.Hyperreal:BAAALgAECgEJAQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgkJJwAKAJsbAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwALAAAAAA==.Idlewild:BAEALgAECgYJDQABLgAECggJHgAMAE0LAA==.',
If='Iforgotnaaru:BAABLgAECn8XAAMOAAcJ4QvecgAEAQAOAAcJ4QvecgAEAQAPAAQJtQrcbACiAAAAAA==.',
Ig='Ignazio:BAAALgAECgEJAQAAAA==.',
Ik='Ikedizzy:BAAALgAFFAEJAQABLgAFFAMJBAALAAAAAA==.Ikeslice:BAAALgAFFAMJBAAAAA==.Ikrys:BAAALgAECgYJDAAAAA==.',
Il='Illiae:BAACLgAFFH8WAAIPAAMJeiToEQAZAQAPAAMJeiToEQAZAQAuAAQKfzIAAg8ACQkjJA8KAL4CAA8ACQkjJA8KAL4CAAAA.',
Im='Imgone:BAAALgADCgEJAQAAAA==.Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8rAAIWAAgJxxOfLQCbAQAWAAgJxxOfLQCbAQAAAA==.',
In='Incrdblestan:BAAALgAECgMJCAAAAA==.Innex:BAABLgAECn8nAAIZAAkJGx+gLABNAgAZAAkJGx+gLABNAgAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECgkJJwAZABsfAA==.Innexvoker:BAABLgAECn8YAAIDAAgJag9VMgBsAQADAAgJag9VMgBsAQABLgAECgkJJwAZABsfAA==.Inpesca:BAAALgADCgUJBQABLgAFFAUJCgADAMQQAA==.Insanityx:BAAALgAECggJCAAAAA==.Insecure:BAAALgAECgEJAQAAAA==.',
Io='Ionic:BAAALgAECgYJCwAAAA==.',
Ir='Iridescent:BAAALgAECgMJBAAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAABLgAECn8hAAIgAAgJNQ7DEwAkAQAgAAgJNQ7DEwAkAQAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itook:BAAALgADCgEJAQAAAA==.Itzmuffin:BAABLgAECn8oAAIOAAgJyRItTQB8AQAOAAgJyRItTQB8AQAAAA==.Itzpie:BAABLgAECn81AAIQAAkJNxYoSgD9AQAQAAkJNxYoSgD9AQAAAA==.',
Ja='Jace:BAABLgAECn8WAAIFAAYJDhyCggBqAQAFAAYJDhyCggBqAQAAAA==.Jadandotz:BAAALgADCggJAgAAAA==.Jagtat:BAABLgAECn8hAAMZAAgJkg8ZmQA3AQAZAAgJkg8ZmQA3AQAbAAUJcQcKRQB6AAAAAA==.Jakeakuma:BAABLgAECn8UAAIRAAkJBAwlXwCsAQARAAkJBAwlXwCsAQAAAA==.Jascob:BAABLgAECn8lAAInAAYJcg92AwDcAAAnAAYJcg92AwDcAAAAAA==.Jasonborne:BAAALgAECgQJBAAAAA==.Jaynne:BAAALgADCgcJCAAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAABLgAECn8pAAIEAAcJdAmhCQDLAAAEAAcJdAmhCQDLAAAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn9QAAIaAAkJsB8zBgDZAgAaAAkJsB8zBgDZAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8lAAIeAAgJGiFcCAD0AgAeAAgJGiFcCAD0AgABLgAFFAQJBAALAAAAAA==.Junfan:BAAALgAECgcJCQAAAA==.',
['Jà']='Jàckblack:BAABLgAECn8ZAAIWAAYJzArsEwCuAAAWAAYJzArsEwCuAAAAAA==.',
Ka='Kaashaa:BAACLgAFFH8XAAIHAAUJthvSLQBVAQAHAAUJthvSLQBVAQAuAAQKf0EAAgcACQnLIRIPANgCAAcACQnLIRIPANgCAAAA.Kaelsgf:BAAALgAECgcJDAAAAA==.Kahllan:BAABLgAECn9FAAMNAAkJ2BKQBwBYAQANAAkJ2BKQBwBYAQAMAAcJeBKaCABAAQAAAA==.Kahnigitt:BAABLgAECn8XAAIZAAcJhwo2qQAeAQAZAAcJhwo2qQAeAQAAAA==.Kalsifire:BAAALgAECgYJEQAAAA==.Kataltoholic:BAABLgAECn8kAAIQAAYJsgN8NgB1AAAQAAYJsgN8NgB1AAAAAA==.Katcantdoit:BAAALgAECgUJBQAAAA==.Katrath:BAAALgADCgMJBgAAAA==.Kayhas:BAAALgAECgUJBwAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIBAAYJCxp5UAC1AQABAAYJCxp5UAC1AQAAAA==.Kaýhás:BAAALgADCgYJBgAAAA==.',
Ke='Kelinïsha:BAABLgAECn8pAAIQAAgJJQrrnwA7AQAQAAgJJQrrnwA7AQAAAA==.Kelynna:BAABLgAECn8pAAIIAAgJDhx4EgBKAgAIAAgJDhx4EgBKAgAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJBQAAAA==.',
Kh='Khaodemus:BAAALgAECggJCQAAAA==.Khellder:BAAALgAECggJEgABLgAECgkJEQALAAAAAA==.Khelldyr:BAAALgAECgkJCQABLgAECgkJEQALAAAAAA==.Khellrond:BAAALgAECgkJEQAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiffira:BAAALgAECgkJCwABLgAECgkJKQABAEUWAA==.Kiiras:BAABLgAECn8vAAIQAAgJ9A2UhQBsAQAQAAgJ9A2UhQBsAQAAAA==.Kimbodh:BAACLgAFFH8qAAIBAAYJVCTtEACtAQABAAYJVCTtEACtAQAuAAQKfygAAgEACQkXJKgOAM8CAAEACQkXJKgOAM8CAAEuAAEKAwkBAAsAAAAA.Kimbubbles:BAAALgAECgMJAwABLgAFFAEJAQALAAAAAA==.Kimoora:BAAALgAFFAEJAQAAAA==.Kimshady:BAAALgADCgEJAQABLgAFFAEJAQALAAAAAA==.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8wAAIBAAkJ+BB5SQCqAQABAAkJ+BB5SQCqAQAAAA==.',
Kl='Klefthoof:BAABLgAECn9HAAMOAAgJBxXELgD7AQAOAAgJBxXELgD7AQAPAAIJdAcGnQA/AAAAAA==.',
Ko='Kodey:BAABLgAECn8pAAIcAAkJxxSBBgD4AQAcAAkJxxSBBgD4AQABLgAFFAQJFwAcABQHAA==.Kordy:BAAALgAECgkJAQAAAA==.Korey:BAAALgAECgEJAQAAAA==.',
Kr='Kraniah:BAABLgAECn8VAAMOAAkJehUzHwBVAgAOAAkJehUzHwBVAgAPAAYJgATSdwCGAAAAAA==.Krelon:BAAALgAECgMJBQAAAA==.Krimboz:BAABLgAECn8vAAIRAAkJZxoXIABkAgARAAkJZxoXIABkAgAAAA==.Krimbrouge:BAAALgAECgYJCQAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8wAAITAAkJdBsiCgB9AgATAAkJdBsiCgB9AgAAAA==.Krìsta:BAACLgAFFH8GAAMdAAIJ7QLKEwBuAAAdAAIJ7QLKEwBuAAARAAEJ8QDC1gAvAAAuAAQKfx4AAx0ACAncDFgNAGABAB0ABwleDlgNAGABABEABwknBOPBAMkAAAAA.',
Ku='Kuanshuwo:BAABLgAECn8VAAMJAAgJ7wksOAA0AQAJAAgJ7wksOAA0AQAIAAYJfQZMTgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
Ky='Kyarcy:BAAALgAECgQJAwAAAA==.Kyokan:BAAALgADCgYJBgAAAA==.',
La='Lanwulf:BAABLgAECn8VAAIFAAYJ5AYE8ADKAAAFAAYJ5AYE8ADKAAAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAACLgAFFH8LAAIJAAUJUxXhGQAaAQAJAAUJUxXhGQAaAQAuAAQKfxgAAgkACQlvHb4XACYCAAkACQlvHb4XACYCAAAA.Legaloas:BAABLgAECn8xAAMHAAkJnyDbFgCeAgAHAAkJnyDbFgCeAgAgAAUJGxFEGADwAAAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAABLgAECn8aAAIeAAgJNg0+OgAYAQAeAAgJNg0+OgAYAQAAAA==.Leondero:BAACLgAFFH8PAAMHAAQJKBn7RQAhAQAHAAQJIBn7RQAhAQAgAAMJ2Q/RFQDuAAAuAAQKfyIABCAACQkZGb8gACACACAACAkSF78gACACAAcABQl/GJ1vAGEBABMAAQlWAKwzAA0AAAAA.Levitt:BAABLgAECn8WAAIRAAYJjhHGkwAUAQARAAYJjhHGkwAUAQABLgAECgkJIwAUAAgWAA==.Leyla:BAAALgADCgkJCQAAAA==.',
Li='Lifelessvoid:BAAALgAECgQJCAAAAA==.Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn80AAIeAAkJbhZdFgAEAgAeAAkJbhZdFgAEAgAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liquid:BAAALgAECgEJAQAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgYJEAAAAA==.',
Ll='Llevanya:BAABLgAECn9IAAIFAAkJ2hB7WwC7AQAFAAkJ2hB7WwC7AQAAAA==.Llinae:BAAALgAECgEJAQAAAA==.Llinaigh:BAACLgAFFH8PAAIHAAQJPBR4PwAuAQAHAAQJPBR4PwAuAQAuAAQKfxkAAgcACQmDFaA8AO4BAAcACQmDFaA8AO4BAAAA.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAgABLgAECgkJOQAWAPwfAA==.Lofi:BAAALgAECgEJAQAAAA==.Loisa:BAAALgADCgYJBgAAAA==.Lomu:BAABLgAECn8rAAQkAAkJyxwECgBIAgAkAAkJyxwECgBIAgAMAAEJ7Q5JzwAvAAANAAEJigSvoAAhAAABLgAECgkJLgARAO0gAA==.Loredalso:BAAALgAECgEJAQAAAA==.Lorenia:BAAALgAECgEJAQAAAA==.Lorenitha:BAAALgAECgEJAQABLgAFFAQJDQAFABccAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
['Lê']='Lêdrollan:BAAALgAECgIJAgABLgAFFAUJCwAJAFMVAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAFFAMJCAAKAGsbAA==.Magicdreams:BAABLgAECn80AAINAAkJNAn6MABZAQANAAkJNAn6MABZAQAAAA==.Malificent:BAAALgADCgQJCAAAAA==.Malmorte:BAABLgAECn8WAAIZAAYJMRUHowA6AQAZAAYJMRUHowA6AQAAAA==.Malorane:BAABLgAECn8vAAIbAAkJFhshCwBjAgAbAAkJFhshCwBjAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgAECgEJAQAAAA==.Mardremar:BAAALgAECgEJAQAAAA==.Margauxx:BAAALgAECgQJBQAAAA==.Marihuano:BAABLgAFFH8IAAIlAAIJGQzJIAB8AAAlAAIJGQzJIAB8AAAAAA==.Marisi:BAAALgADCggJCAABLgAECgcJBwALAAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIlAAkJ0R3tEQAYAgAlAAkJ0R3tEQAYAgAAAA==.Materiaga:BAABLgAECn8iAAQDAAgJEhEHMAB4AQADAAgJwBAHMAB4AQACAAYJFQtdKQAoAQAXAAMJjw9uGACVAAAAAA==.Material:BAAALgAECgEJAQAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8xAAIFAAkJKCE2EADkAgAFAAkJKCE2EADkAgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMiAAkJGxU2BgCWAgAiAAkJGxU2BgCWAgAPAAgJyg/bRAAgAQAAAA==.Mcshanks:BAAALgAECgcJCQAAAA==.',
Me='Medalla:BAAALgADCgYJBgAAAA==.Meerchi:BAABLgAECn8wAAMQAAkJCBnyOQAxAgAQAAkJCBnyOQAxAgAoAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Mefysto:BAAALgAECgUJBQAAAA==.Meiriie:BAAALgAECgYJDAAAAA==.Meknin:BAAALgAECgYJCgAAAA==.Meldia:BAAALgAECgEJAgABLgAECgYJBgALAAAAAA==.Meowkai:BAAALgAECgYJBgABLgAECgkJPAAUAB0fAA==.Merix:BAAALgAECgYJBgAAAA==.Mesmal:BAAALgAECgkJAwAAAA==.Mesthos:BAAALgAECgcJDAABLgAECgkJKAASACwmAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8qAAIDAAgJ4BSbBQA/AQADAAgJ4BSbBQA/AQABLgAECggJKwAdAJIZAA==.',
Mi='Miciah:BAAALgAECgQJBAAAAA==.Mickieta:BAABLgAECn8/AAIFAAkJ4SDOFADFAgAFAAkJ4SDOFADFAgAAAA==.Microsurge:BAACLgAFFH8HAAIQAAQJ4AgqcgD8AAAQAAQJ4AgqcgD8AAAuAAQKfx0AAhAACAkiHdslANsCABAACAkiHdslANsCAAAA.Mikalau:BAACLgAFFH8LAAIHAAMJ1wm2PAC7AAAHAAMJ1wm2PAC7AAAuAAQKf0AAAgcACQmvGi4LAMIBAAcACQmvGi4LAMIBAAAA.Mikaluu:BAACLgAFFH8GAAIRAAIJCgQEVQBWAAARAAIJCgQEVQBWAAAuAAQKfzQAAhEABwkpE6wKAFcBABEABwkpE6wKAFcBAAAA.Milktide:BAAALgADCgYJBgABLgAFFAUJEgAJACscAA==.Miqkail:BAAALgAECggJCgABLgAECgkJKAASACwmAA==.Missteek:BAAALgAECgYJEgABLgAECgkJRAAXAHQjAA==.Mistrunner:BAAALgAECgMJAwAAAA==.Mistspell:BAACLgAFFH8QAAMJAAQJpQ/BHgD8AAAJAAQJpQ/BHgD8AAAIAAEJSgkmJAAkAAAuAAQKfyAAAwkACQnXHeQOAJUCAAkACQnXHeQOAJUCAAgAAwklBoFqAIIAAAAA.',
Mo='Mochacho:BAAALgAECgEJAQABLgAECgkJJwAKAJsbAA==.Mochia:BAAALgAECgYJEwABLgAECgkJJwAKAJsbAA==.Mognel:BAABLgAECn82AAIRAAkJxxySKgAwAgARAAkJxxySKgAwAgAAAA==.Mogrungar:BAACLgAFFH8KAAIOAAMJVRb6MACGAAAOAAMJVRb6MACGAAAuAAQKfygAAg4ACQl3FC0nACQCAA4ACQl3FC0nACQCAAAA.Moisten:BAABLgAECn8eAAIPAAkJQyCCCADVAgAPAAkJQyCCCADVAgAAAA==.Moistifer:BAAALgAECgEJAQAAAA==.Mokuo:BAAALgAFFAIJAwAAAA==.Monklee:BAAALgAECgEJAgAAAA==.Moomootus:BAABLgAECn8zAAMFAAkJeRsTOgAbAgAFAAgJFRsTOgAbAgAKAAQJ/B4wPQBRAQAAAA==.Mordakttaa:BAAALgADCgMJBQAAAA==.Mordine:BAAALgADCgEJAQAAAA==.Morgalea:BAAALgAECgcJAQAAAA==.Motoraxe:BAAALgAFFAMJBAAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIeAAgJRyBsDQClAgAeAAgJRyBsDQClAgABLgAFFAQJEAABAKgOAA==.Mystynight:BAABLgAECn8VAAIJAAgJFQ26QwAAAQAJAAgJFQ26QwAAAQAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAABLgAECn8nAAIPAAkJbg41PQBBAQAPAAkJbg41PQBBAQAAAA==.Naggs:BAAALgAECgkJCAAAAA==.Nagini:BAABLgAECn8fAAIRAAgJdwhEiwAjAQARAAgJdwhEiwAjAQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Nevon:BAAALgADCgEJAQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn9AAAMIAAkJgxkoHQDcAQAIAAcJGRkoHQDcAQAJAAkJ5xGgPgAWAQAAAA==.Nietzcha:BAAALgAECgQJBwAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAABLgAECn8lAAMNAAgJkBf6HADhAQANAAgJkBf6HADhAQAmAAUJRw2oNwB8AAAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nilfgard:BAAALgAECgcJEgAAAA==.Nioh:BAABLgAECn8iAAIBAAkJxRasLwAIAgABAAkJxRasLwAIAgAAAA==.Nivix:BAAALgAECgEJAgAAAA==.',
No='Noodles:BAABLgAECn8nAAIBAAgJnwjLlwDxAAABAAgJnwjLlwDxAAAAAA==.Nordrydd:BAAALgAECggJDgABLgAFFAkJGgAUAFUTAA==.Nordrydsh:BAAALgAFFAMJAwABLgAFFAkJGgAUAFUTAA==.',
Nu='Nuggs:BAABLgAECn8YAAImAAkJzBB3EACwAQAmAAkJzBB3EACwAQAAAA==.Nuhpie:BAACLgAFFH8ZAAMEAAkJygw3KADMAAAWAAMJUxGSOADQAAAEAAYJEQo3KADMAAAuAAQKfx4AAwQACQlfHfQfAF4BAAQABQmuGvQfAF4BABYABQlsHJhMABQBAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8lAAIZAAkJax/eGQCrAgAZAAkJax/eGQCrAgAAAA==.',
Od='Odelay:BAAALgADCgEJAQAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAwAAAA==.',
Ol='Olimdar:BAACLgAFFH8xAAIOAAkJDiV8AAA9AwAOAAkJDiV8AAA9AwAuAAQKfycAAw4ACQlvJUsAAM8DAA4ACQlvJUsAAM8DAA8AAQmSHaiCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBwAAAA==.',
Oo='Oopositive:BAAALgAECgUJDQAAAA==.Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Orgarrot:BAAALgADCgYJBgABLgAECgkJCwALAAAAAA==.Oricelle:BAABLgAECn8pAAIBAAkJRRaDKgAfAgABAAkJRRaDKgAfAgAAAA==.Oridis:BAAALgAECgkJBwAAAA==.Orkariq:BAAALgADCgQJBAAAAA==.Oryon:BAEBLgAECn8zAAIdAAkJnRR/CADgAQAdAAkJnRR/CADgAQAAAA==.',
Os='Osquinn:BAAALgAECgEJAQAAAA==.',
Ot='Otos:BAAALgADCgcJBwAAAA==.',
Ov='Ovarb:BAABLgAECn8xAAMbAAkJ9BhFEgDqAQAbAAkJkRhFEgDqAQAZAAkJUg/ggwBcAQAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDgAAAA==.Painstorm:BAAALgADCgYJBgAAAA==.Palasexo:BAAALgAECgUJCQABLgAFFAIJCAAlABkMAA==.Palldude:BAAALgADCgQJBQAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pathofpain:BAAALgAECgYJDgAAAA==.Pavo:BAAALgADCgQJBAAAAA==.Pawpatrol:BAAALgAECgEJAQAAAA==.',
Pe='Peachie:BAAALgADCgEJAQAAAA==.Persicles:BAAALgAECgUJBgAAAA==.Pesti:BAACLgAFFH8iAAIlAAUJCB8qEgB9AQAlAAUJCB8qEgB9AQAuAAQKf1EAAiUACQlnI8YCACgDACUACQlnI8YCACgDAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8+AAIOAAkJQiM7BAB2AwAOAAkJQiM7BAB2AwAAAA==.',
Pi='Pissedwolf:BAAALgAFFAEJAQAAAA==.',
Pl='Plucker:BAAALgAECgEJAQAAAA==.Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAABLgAECn8fAAIaAAkJeBCbIACiAQAaAAkJeBCbIACiAQAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAACLgAFFH8WAAIQAAUJgxjXUgA3AQAQAAUJgxjXUgA3AQAuAAQKf0cABBAACQkJIqkOAAUDABAACQmIIakOAAUDACkABQnyFiQMABABACgAAQmjEFIUADEAAAAA.Proctologist:BAABLgAECn8zAAMaAAkJ9BvFCACmAgAaAAkJ9BvFCACmAgAeAAQJYROoQwDwAAAAAA==.Proserpìne:BAABLgAECn9NAAIBAAkJBA6NVgCDAQABAAkJBA6NVgCDAQAAAA==.',
Ps='Psychojester:BAACLgAFFH8TAAIiAAUJRxp+BwA/AQAiAAUJRxp+BwA/AQAuAAQKf0MAAiIACQk2IWECAPcCACIACQk2IWECAPcCAAAA.Psylir:BAAALgAECgQJDgAAAA==.Psypra:BAAALgAECgYJCQAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAABLgAECn8WAAIQAAUJihtcvQANAQAQAAUJihtcvQANAQAAAA==.',
Py='Pydge:BAAALgAECgEJAQAAAA==.',
Qu='Queeb:BAAALgAECgUJBgAAAA==.Quod:BAAALgAECgQJBAAAAA==.Quoril:BAACLgAFFH8FAAIQAAIJDQ91ogCKAAAQAAIJDQ91ogCKAAAuAAQKfz8AAxAACQkLIYMQAPgCABAACQkLIYMQAPgCACkAAQmXIHkZAEwAAAEuAAUUCAkhAAcAJxQA.',
Ra='Raijyu:BAABLgAECn9HAAMIAAkJzR8/BQAoAwAIAAkJzR8/BQAoAwAJAAcJVRV+IwC8AQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECgkJNgANAM8WAA==.Rainstormin:BAABLgAECn82AAMNAAkJzxZaFgAbAgANAAkJzxZaFgAbAgAkAAYJxgk+QQCiAAAAAA==.Rakarra:BAABLgAECn8fAAMMAAkJGgvJSABsAQAMAAkJGgvJSABsAQANAAcJhwgPTQD2AAAAAA==.Rakogon:BAAALgADCgEJAQAAAA==.Ranalia:BAAALgADCgcJCgAAAA==.Rantah:BAAALgAFFAEJAQAAAA==.Rawrstance:BAABLgAECn9FAAMbAAkJQRwIBgBWAQAZAAcJoRyudAB6AQAbAAkJGhQIBgBWAQABLgAECgEJAQALAAAAAA==.Razgrize:BAACLgAFFH8RAAIQAAQJLxNdQADGAAAQAAQJLxNdQADGAAAuAAQKfzUAAxAACQm/G/MjAI0CABAACQm/G/MjAI0CACgAAQkpFV8GAEEAAAAA.',
Re='Redraggon:BAAALgAECgYJBgAAAA==.Reecalled:BAAALgADCgUJBQABLgAECggJGgADAGIaAA==.Reeshan:BAABLgAECn8fAAMFAAkJ1yPFDgDwAgAFAAkJ1yPFDgDwAgAKAAIJaxSRdABnAAAAAA==.Reilin:BAAALgAFFAEJAQAAAA==.Remsham:BAABLgAECn8nAAIiAAkJxg0YEACwAQAiAAkJxg0YEACwAQAAAA==.Reniel:BAAALgAECgcJCQABLgAECgkJMAABAPgQAA==.Renwyck:BAABLgAECn8oAAISAAkJLCZcAABjAwASAAkJLCZcAABjAwAAAA==.Reubenb:BAAALgAECgEJAQABLgAECgkJMQAHAAEPAA==.Revengemoon:BAACLgAFFH8SAAIFAAQJsxLTTAAUAQAFAAQJsxLTTAAUAQAuAAQKfyMAAgUACQmVGsApAH4CAAUACQmVGsApAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Ricenoodle:BAAALgADCgcJBwABLgAECgEJAQALAAAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgALAAAAAA==.Riftstrider:BAAALgAECgYJBwAAAA==.Rikkren:BAAALgAFFAEJAQAAAA==.Ringberg:BAACLgAFFH8IAAIKAAMJaxsjLQDHAAAKAAMJaxsjLQDHAAAuAAQKfxcAAwoABwlSHzsZAD0CAAoABwlSHzsZAD0CAAUAAwmmFNkLAaoAAAAA.',
Ro='Robane:BAABLgAECn8UAAIFAAUJCA+e5wDUAAAFAAUJCA+e5wDUAAAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Rockette:BAAALgAECgQJCAAAAA==.Ronburgundy:BAAALgAECgMJBQAAAA==.Rouen:BAABLgAECn80AAMOAAkJ2xoIFQCjAgAOAAkJ2xoIFQCjAgAiAAgJiiIZBwBgAgAAAA==.',
Ru='Rubidea:BAAALgAECgEJAQAAAA==.Ruckus:BAEBLgAECn8eAAQMAAgJTQvnXAAgAQAMAAgJTQvnXAAgAQAkAAMJFAcnHABJAAANAAEJtRFsJgAzAAAAAA==.Ruder:BAAALgAECgMJBAABLgAECgkJCwALAAAAAA==.Rutabaga:BAAALgAECgUJCwAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIJAAkJxBtnEQBzAgAJAAkJxBtnEQBzAgAAAA==.',
Sa='Saintanic:BAAALgAECgEJAQAAAA==.Sandkat:BAABLgAECn9BAAIWAAkJZCJrBgD4AgAWAAkJZCJrBgD4AgAAAA==.Sanstian:BAAALgAECgUJDQAAAA==.Santamoe:BAAALgAFFAEJBAAAAA==.Saraelin:BAABLgAFFH8IAAIRAAIJ8ABpvgBLAAARAAIJ8ABpvgBLAAAAAA==.Saray:BAAALgAECgcJEgAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAYJEwAWAO4QAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgYJDgAAAA==.Serahstia:BAABLgAECn8gAAIQAAkJCBX5ZQCyAQAQAAkJCBX5ZQCyAQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shadowmeld:BAAALgAECgEJAQAAAA==.Shadysadie:BAAALgAECgcJEgAAAA==.Shaiy:BAAALgAECgcJEAAAAA==.Shakejunt:BAAALgADCgIJAgAAAA==.Shammymoe:BAAALgAFFAEJAgABLgAFFAEJBAALAAAAAA==.Shelaan:BAAALgAECgYJCAAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwALAAAAAA==.Shinta:BAABLgAECn8WAAQKAAYJtRRbPwBHAQAKAAYJtRRbPwBHAQAGAAUJ2g+3KwC/AAAFAAQJAwixLgGBAAAAAA==.Shirtles:BAABLgAECn8YAAIPAAYJggOsdACOAAAPAAYJggOsdACOAAAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shpik:BAAALgADCgUJCQAAAA==.Shumahiah:BAAALgADCgQJBAAAAA==.Shèp:BAABLgAECn8gAAIKAAgJvxGcCQAmAQAKAAgJvxGcCQAmAQAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIPAAUJ/hmfAwCvAQAPAAUJ/hmfAwCvAQABLgAFFAgJGwATACgUAA==.Siffrin:BAAALgAECgIJAgAAAA==.Siink:BAABLgAFFH8FAAIlAAIJ0wyfIQBzAAAlAAIJ0wyfIQBzAAAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8rAAMdAAgJkhk2AwBiAQAdAAcJQxs2AwBiAQARAAYJbxOGdABRAQAAAA==.Sinkingship:BAAALgAECgYJCgAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAABLgAECn8sAAIbAAkJgSA7BgC/AgAbAAkJgSA7BgC/AgAAAA==.',
Sk='Skaterboi:BAAALgAECgYJBgAAAA==.Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sliy:BAAALgAECgIJAgAAAA==.Sloothe:BAAALgADCgQJBAAAAA==.Sloothi:BAAALgAECgEJAQAAAA==.Slyveria:BAAALgAECgMJBAAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.Snorri:BAABLgAFFH8GAAMZAAMJORUtZgCNAAAZAAMJ8xAtZgCNAAAjAAEJQxe+GwBJAAAAAA==.',
So='Sosorry:BAAALgADCgIJAgAAAA==.Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAABLgAECn8WAAIFAAkJgRpENgAoAgAFAAkJgRpENgAoAgAAAA==.',
Sp='Sprodage:BAABLgAECn9NAAIKAAkJVhjnFQBcAgAKAAkJVhjnFQBcAgAAAA==.',
St='Staggrsaurus:BAAALgAECgIJAwABLgAECgMJBAALAAAAAA==.Stanil:BAABLgAECn8uAAMHAAkJPQrOcABfAQAHAAkJPQrOcABfAQAgAAEJWwAkmwAVAAAAAA==.Stayfrosty:BAAALgAECgcJDQAAAA==.Stellare:BAABLgAECn8wAAIVAAkJHRdjEQAUAgAVAAkJHRdjEQAUAgAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Stinklines:BAAALgAECgEJAgABLgAECgkJRAAXAHQjAA==.Strangetame:BAAALgADCgEJAQAAAA==.Striest:BAAALgAECgMJAwAAAA==.Styló:BAAALgAECggJEwAAAA==.',
Su='Suetonius:BAACLgAFFH8VAAMZAAUJRR9tQwBuAQAZAAQJRR9tQwBuAQAbAAEJAACqMQAAAAAuAAQKfxQAAxkACAlXJH4RAOECABkACAlXJH4RAOECACMAAgk4Ey8vAGMAAAAA.Suguru:BAAALgAECggJCQAAAA==.Sungsuf:BAAALgAECgEJAQAAAA==.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8wAAIQAAkJ3hqIOAA2AgAQAAkJ3hqIOAA2AgAAAA==.Suraschi:BAABLgAECn8iAAMaAAkJ2BiSAgC0AQAaAAkJEhiSAgC0AQAeAAcJjxFILgBRAQABLgAECgkJMAAQAN4aAA==.',
Sv='Svelda:BAABLgAECn8xAAMJAAkJDg7cJwCQAQAJAAkJDg7cJwCQAQAhAAUJmAULUwC1AAAAAA==.',
Sw='Swisscake:BAABLgAECn9JAAINAAkJaySoAgBHAwANAAkJaySoAgBHAwAAAA==.Swtmystic:BAAALgAECgkJDwAAAA==.',
Sy='Sylain:BAAALgAECgYJEgAAAA==.Synwav:BAAALgAECgcJCwAAAA==.',
Ta='Taldrin:BAAALgADCgIJAgAAAA==.Tannatax:BAABLgAECn8vAAIOAAkJZQbUWwBKAQAOAAkJZQbUWwBKAQAAAA==.Tashah:BAAALgAECgQJAwAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAALAAAAAA==.',
Th='Thauyia:BAAALgAECgEJAQAAAA==.Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8jAAMQAAkJnBWLVADfAQAQAAkJnBWLVADfAQAoAAEJGgGRGAAJAAAAAA==.Thewretch:BAABLgAECn85AAIRAAkJhyLYBwAZAwARAAkJhyLYBwAZAwAAAA==.Thibble:BAAALgADCgYJBgAAAA==.Thonorin:BAAALgAECgMJAwABLgAECgkJMAABAPgQAA==.Thumpthump:BAABLgAECn8nAAQTAAkJQBisFAD+AQAgAAYJwx6nIgARAgATAAkJMhCsFAD+AQAHAAEJqQ7sLwE3AAAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEBLgAECn8uAAIPAAkJGhHlCQAwAQAPAAkJGhHlCQAwAQABLgAECggJHgAMAE0LAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Tindoranis:BAAALgAECgUJBQAAAA==.Titiera:BAABLgAECn8jAAIHAAkJ7BaoOwDxAQAHAAkJ7BaoOwDxAQAAAA==.Titos:BAAALgAECgEJAQAAAA==.',
To='Toastnbutta:BAABLgAECn8mAAIMAAkJ9xnRGAB/AgAMAAkJ9xnRGAB/AgAAAA==.Tolten:BAABLgAECn8eAAIFAAgJ3RmUMQBcAgAFAAgJ3RmUMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgYJCAAAAA==.Traumatism:BAAALgAECgkJEwAAAA==.Trevor:BAABLgAECn9BAAInAAkJUhhpBABPAgAnAAkJUhhpBABPAgAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.Truepain:BAAALgADCgYJBgAAAA==.Tryxi:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAACLgAFFH8OAAMmAAUJHBbpBAD4AAAmAAUJHBbpBAD4AAAkAAEJXBmJNgBKAAAuAAQKfyAAAyYACQnLIogBAC4DACYACQnLIogBAC4DACQABgk0HBMZAIYBAAEuAAUUBQkdABsArhwA.Tsura:BAAALgAFFAEJAQAAAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Ty='Tylaesh:BAAALgAECgYJDwAAAA==.Tyro:BAAALgAFFAEJAwAAAA==.',
Tz='Tziyu:BAAALgAECgQJBAAAAA==.',
Un='Unclepeepers:BAACLgAFFH8XAAIUAAQJ4iDmIQBfAQAUAAQJ4iDmIQBfAQAuAAQKfy4AAx4ACQkPIxYQAEsCAB4ACAmOIhYQAEsCABQACQm0G5wjAAMCAAAA.Underpowered:BAAALgAECgYJDgAAAA==.Ungodlypain:BAABLgAECn8bAAIZAAcJug8LIADBAAAZAAcJug8LIADBAAAAAA==.',
Ur='Urtag:BAACLgAFFH8YAAMgAAkJVRQaDgB8AQAgAAcJRA0aDgB8AQAHAAUJnxRhMQBMAQAuAAQKfxUAAyAACAnyFboqANYBACAACAkZFboqANYBAAcAAgm6F3jYAJwAAAAA.',
Ut='Uthgar:BAAALgAECgYJCAAAAA==.',
Va='Vadge:BAAALgAECgEJAgABLgAECgEJAQALAAAAAA==.Vaeryn:BAABLgAECn8vAAIHAAcJCBvaCQDfAQAHAAcJCBvaCQDfAQABLgAFFAMJCwAUAGMOAA==.Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAACLgAFFH8NAAIhAAMJqw4vMwC/AAAhAAMJqw4vMwC/AAAuAAQKf3UAAyEACQlrHd0JANMCACEACQlrHd0JANMCAAkABwneEPgxAFQBAAEuAAUUAwkLABQAYw4A.Valryn:BAABLgAECn8aAAMZAAcJKgsRogApAQAZAAcJKgsRogApAQAbAAEJxgH7TwAVAAABLgAFFAMJCwAUAGMOAA==.Valtar:BAABLgAECn8hAAIOAAkJoBxrGgB3AgAOAAkJoBxrGgB3AgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAACLgAFFH8IAAMZAAUJRRQ6YAA0AQAZAAUJRRQ6YAA0AQAbAAMJyhEkDgCJAAAuAAQKfzAAAxkACQmJI70GAEEDABkACQmJI70GAEEDABsACAntHUsPABcCAAAA.',
Ve='Veliraleonoc:BAAALgAECgEJAgAAAA==.Velra:BAAALgADCgEJAQABLgAFFAMJCwAUAGMOAA==.Velryn:BAACLgAFFH8LAAIUAAMJYw6TKACMAAAUAAMJYw6TKACMAAAuAAQKf0kAAxQACQlMGjkCAKUCABQACQlMGjkCAKUCAB4ABgl3FW4EAIQBAAAA.Veraalyn:BAABLgAECn8dAAMPAAgJHhH9RQAcAQAPAAgJHhH9RQAcAQAOAAMJxwiifgCZAAAAAA==.Verleanna:BAAALgAECgIJAQAAAA==.',
Vi='Vicsen:BAABLgAECn8gAAIRAAkJdQVbgQA2AQARAAkJdQVbgQA2AQAAAA==.Vikaya:BAAALgAECggJCgAAAA==.Vilaris:BAAALgAECggJDgAAAA==.Vilevixon:BAABLgAECn8hAAMJAAkJ4hbdFwAIAgAJAAkJ4hbdFwAIAgAhAAMJxgcbYAB9AAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Vo='Voidasuras:BAAALgAECgEJAQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAALAAAAAA==.Wanlok:BAAALgAECgQJCQAAAA==.Wantoo:BAAALgAECgYJBgAAAA==.Warlokip:BAAALgAECgkJCgAAAA==.Warmis:BAAALgAECgEJAwABLgAECgkJSAASAOMlAA==.Warotar:BAAALgAECgIJAgAAAA==.Warriorlobo:BAABLgAECn85AAQWAAkJ/B/PCADUAgAWAAkJ/B/PCADUAgAEAAYJ7RDVMgD7AAAfAAEJ6A4QWgAjAAAAAA==.Warvision:BAAALgAFFAEJAQAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.Watts:BAACLgAFFH8hAAIHAAgJJxTbGgCbAQAHAAgJJxTbGgCbAQAuAAQKfzYAAgcACQnHIaYKAPECAAcACQnHIaYKAPECAAAA.',
Wi='Wildfang:BAABLgAECn8iAAMHAAkJKAw1VgChAQAHAAkJKAw1VgChAQATAAEJQwNVagAoAAAAAA==.Wildside:BAABLgAECn8lAAMHAAgJ8R8yHQB2AgAHAAgJ8R8yHQB2AgATAAYJCxZ4KABcAQAAAA==.',
Wu='Wujifei:BAAALgAFFAIJAwAAAA==.Wulffgar:BAAALgAECgYJDAAAAA==.',
['Wì']='Wìldthìng:BAAALgAECgUJCgAAAA==.',
Xa='Xael:BAAALgAECgEJAQAAAA==.Xandronys:BAAALgAECgkJDAAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECggJCgAAAA==.Xenie:BAABLgAFFH8IAAMVAAQJ3BzkCwDuAAAVAAQJ3BzkCwDuAAABAAIJMQeQXQAsAAAAAA==.Xennile:BAABLgAFFH8LAAIgAAcJxRJXBAC0AQAgAAcJxRJXBAC0AQAAAA==.',
Xi='Xinema:BAAALgAECgQJBAAAAA==.Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAABLgAECn8UAAIhAAcJAguiQQAEAQAhAAcJAguiQQAEAQAAAA==.',
Yd='Ydeatho:BAAALgAFFAMJAwAAAA==.',
Ye='Yeet:BAABLgAECn8cAAIlAAkJNBj5IgDhAQAlAAkJNBj5IgDhAQAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgMJBgAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgAECgYJCQAAAA==.Zalanna:BAAALgADCgMJAwAAAA==.Zalckar:BAABLgAECn8bAAMKAAkJcBIZRQBjAQAKAAkJcBIZRQBjAQAFAAEJYQ7soAEtAAAAAA==.Zally:BAAALgADCgYJBgAAAA==.Zanos:BAAALgAECgUJBAAAAA==.Zarane:BAABLgAFFH8HAAIZAAMJzR9aLQAdAQAZAAMJzR9aLQAdAQAAAA==.Zarayssa:BAAALgAECgIJAwAAAA==.Zarnok:BAAALgADCgkJCQAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zebracakes:BAAALgAECgEJAQABLgAECgkJSAASAOMlAA==.Zeeva:BAABLgAECn8cAAMcAAYJxiGVCADDAQAcAAYJ7SCVCADDAQAdAAMJ+h1lKAB/AAAAAA==.Zendead:BAABLgAECn8jAAIeAAkJCiP+BwDIAgAeAAkJCiP+BwDIAgAAAA==.Zeppeli:BAAALgAECgMJAwAAAA==.Zerkces:BAAALgADCgIJAgAAAA==.',
Zi='Ziggie:BAAALgAECgEJAQABLgAECgMJBAALAAAAAA==.Zionspartan:BAABLgAECn8xAAIHAAkJAQ/bRADTAQAHAAkJAQ/bRADTAQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugpriest:BAAALgAECgQJBAAAAA==.Zugzugshaman:BAABLgAECn8yAAQOAAkJ6xkPGACJAgAOAAkJ6xkPGACJAgAPAAQJrwOHbgCJAAAiAAEJYQClSAAdAAAAAA==.Zurokhan:BAAALgAFFAEJAQAAAA==.Zuzill:BAAALgAECgUJBQABLgAECgYJHAAcAMYhAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Êï']='Êïñstëïn:BAAALgAECgEJAQAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8kAAIaAAgJmxF1JgB7AQAaAAgJmxF1JgB7AQAAAA==.',
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
