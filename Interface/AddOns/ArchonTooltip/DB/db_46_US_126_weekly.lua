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
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Aberration:BAAALgAECgEJAgAAAA==.Abraxidormu:BAAALgAECgYJBgABLgAECgkJMAABAPgQAA==.',
Ad='Adorraa:BAAALgAFFAIJAgAAAA==.Adoryn:BAAALgADCgYJCQAAAA==.Adowyrm:BAACLgAFFH8oAAMCAAgJlRfmCQAMAgACAAcJYRfmCQAMAgADAAMJYQ2mPADVAAAuAAQKfyEAAwIACQm1IUcCAFEDAAIACQm1IUcCAFEDAAMABgnLHfscAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.Adrielle:BAAALgAECgQJBgAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECgkJHQAEAIgcAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAFFAQJBAAAAA==.Agtar:BAAALgAECgMJAwAAAA==.',
Ai='Airali:BAACLgAFFH8KAAIFAAUJ+gXrYADtAAAFAAUJ+gXrYADtAAAuAAQKfxcAAwUACQn+E2tkALgBAAUACQn+E2tkALgBAAYAAwmJCNM3AGIAAAAA.Airedale:BAABLgAECn81AAIHAAgJ/hiwBQC/AQAHAAgJ/hiwBQC/AQAAAA==.',
Ak='Akairo:BAACLgAFFH8FAAIIAAQJNRuFCgC8AAAIAAQJNRuFCgC8AAAuAAQKfzEAAwgACQkAJIICAEEDAAgACQkAJIICAEEDAAkACAmsEborAHcBAAAA.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgAECgYJBgABLgAFFAUJCgADAMQQAA==.Alderbaran:BAAALgADCgUJBQAAAA==.Alexanderxl:BAABLgAECn8WAAMGAAYJAB1gFwBfAQAGAAYJAB1gFwBfAQAFAAUJWBXRxAACAQABLgAECggJAwAKAAAAAA==.Aleybobwa:BAABLgAECn8gAAQLAAkJjhLIKgC5AQALAAkJjhLIKgC5AQAGAAEJvRjnCwBEAAAFAAEJYwiPUgErAAAAAA==.Alody:BAAALgADCgMJAwABLgAECgYJBgAKAAAAAA==.Alucardo:BAAALgAECgQJBQAAAA==.Alyméré:BAAALgAECgYJCAAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAABLgAECn8nAAILAAkJmxsaDQC/AgALAAkJmxsaDQC/AgAAAA==.Amulius:BAACLgAFFH8GAAIFAAMJtSVvOAA8AQAFAAMJtSVvOAA8AQAuAAQKfzYAAgUACQnyJZQEAFUDAAUACQnyJZQEAFUDAAAA.',
An='Anderdingus:BAAALgADCgYJCgAAAA==.Andormath:BAAALgAECgQJBgAAAA==.Andramedae:BAABLgAECn9AAAMMAAkJtBsBEgC/AgAMAAkJtBsBEgC/AgANAAYJQg4wSQDnAAAAAA==.Angerissues:BAAALgADCgkJCQAAAA==.Angyavocado:BAAALgAFFAEJAQAAAA==.Anoki:BAABLgAECn9DAAMOAAkJIxs1FQChAgAOAAkJIxs1FQChAgAPAAEJgQshtQAmAAAAAA==.',
Ao='Aolus:BAACLgAFFH8SAAINAAQJwhgIIgARAQANAAQJwhgIIgARAQAuAAQKfxsAAg0ACQkVHDETAHsCAA0ACQkVHDETAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgAECgEJAQAAAA==.Aprollon:BAAALgAECgEJAgAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJBAAKAAAAAA==.Arcaina:BAABLgAECn8kAAIQAAkJLglCegCEAQAQAAkJLglCegCEAQAAAA==.Ares:BAAALgADCgkJFQABLgAECgkJPAARAPAXAA==.Arez:BAABLgAECn88AAIRAAkJ8BdVKQA2AgARAAkJ8BdVKQA2AgAAAA==.Arilass:BAAALgADCgIJBAAAAA==.Armis:BAAALgADCgEJAQABLgAECgkJSAASAOMlAA==.Artèmís:BAABLgAECn8nAAITAAkJDSVaAwACAwATAAkJDSVaAwACAwAAAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Ashtongue:BAAALgAECgYJDQAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athinea:BAAALgAECgYJCgAAAA==.Athlon:BAAALgAECgEJAQAAAA==.',
Au='Aura:BAAALgAFFAEJAQAAAA==.',
Ay='Ayahuasca:BAAALgADCgIJAgAAAA==.',
Az='Azaekho:BAABLgAECn8kAAIOAAkJcxQIKgDmAQAOAAkJcxQIKgDmAQAAAA==.Azaelleonoc:BAAALgAECgEJAQAAAA==.Azalet:BAAALgAFFAIJAgAAAA==.',
Ba='Baalzak:BAAALgADCgYJBQAAAA==.Backfliphoe:BAABLgAECn8aAAIUAAkJuRc5GQC4AQAUAAkJuRc5GQC4AQAAAA==.Badoosh:BAABLgAECn8pAAIVAAgJbB6aGACHAgAVAAgJbB6aGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Bajablaster:BAABLgAECn9EAAQWAAkJdCOpAAA7AwAWAAkJdCOpAAA7AwADAAMJ5BD7TACdAAACAAEJMAssPgArAAAAAA==.Baliw:BAAALgAECgQJBAAAAA==.Balltze:BAAALgAFFAEJAQAAAA==.Balto:BAAALgADCgMJAwAAAA==.Barbearic:BAAALgAECgEJAQAAAA==.',
Bb='Bbl:BAECLgAFFH8fAAIPAAYJ1BgzFQBzAQAPAAYJ1BgzFQBzAQAuAAQKfyUAAg8ACQnWIFgKAPACAA8ACQnWIFgKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8QAAIQAAQJ2xFGKwAIAQAQAAQJ2xFGKwAIAQAuAAQKfyMAAhAACQnDGZo7AIgCABAACQnDGZo7AIgCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAACLgAFFH8GAAIFAAIJJQ26kwCMAAAFAAIJJQ26kwCMAAAuAAQKfxgAAgUACQkfEYxXAMUBAAUACQkfEYxXAMUBAAAA.',
Bh='Bhain:BAAALgADCgcJDQABLgAFFAUJFgAFAKwfAA==.',
Bi='Bieorne:BAABLgAECn87AAIXAAkJrSECDwD0AgAXAAkJrSECDwD0AgAAAA==.Bigpan:BAAALgAECgIJAgABLgAECggJJAAYAJsRAA==.',
Bl='Blastbane:BAACLgAFFH8LAAIRAAQJXQsUYwABAQARAAQJXQsUYwABAQAuAAQKfxQAAhEACQnuFBA3AP0BABEACQnuFBA3AP0BAAEuAAUUBQkOABkAiQkA.Bloodwrath:BAAALgAECgYJDAAAAA==.Blueveins:BAABLgAECn8VAAIQAAcJ/gWi1gDoAAAQAAcJ/gWi1gDoAAAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAACLgAFFH8FAAIRAAIJ5R7xlACYAAARAAIJ5R7xlACYAAAuAAQKfxgAAxEACQnvHP4PAPoCABEACQnvHP4PAPoCABoAAQkAAExQAAAAAAEuAAUUAwkIAAsAaxsA.Boondemon:BAAALgAECgIJAgAAAA==.Boondocks:BAABLgAECn9BAAMRAAkJ9R/6BAB+AQARAAYJIBv6BAB+AQAbAAUJ8CHQDgBvAQAAAA==.',
Br='Braca:BAAALgAECgYJBwABLgAECgkJNAAOACwfAA==.Braelek:BAAALgADCgEJAQAAAA==.Brains:BAAALgAECgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAABLgAECn8ZAAIYAAkJLQ/qIwCMAQAYAAkJLQ/qIwCMAQABLgAECgkJLgARAO0gAA==.Brielle:BAABLgAECn8uAAIHAAkJnhgALAAtAgAHAAkJnhgALAAtAgAAAA==.Brokenbranch:BAABLgAECn8YAAIMAAcJLwnpawDxAAAMAAcJLwnpawDxAAAAAA==.Brudene:BAABLgAECn8UAAIVAAcJFRF2VABZAQAVAAcJFRF2VABZAQAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Bubbletruble:BAAALgAECgYJBgAAAA==.Buddylock:BAABLgAECn8iAAIRAAkJmgm3ewBBAQARAAkJmgm3ewBBAQAAAA==.Bulltaura:BAAALgAECgcJBwAAAA==.Bullymaguire:BAACLgAFFH8RAAIcAAcJRhsUBgC2AQAcAAcJRhsUBgC2AQAuAAQKfx0AAhwACAk5I0EFADEDABwACAk5I0EFADEDAAAA.Burakkuburu:BAABLgAECn88AAMdAAkJHR8ICQALAwAdAAkJHR8ICQALAwAcAAYJMRlGMQBBAQABLgAECgkJJwATAA0lAA==.',
Ca='Caboozles:BAABLgAECn87AAIHAAkJCRaMOwDxAQAHAAkJCRaMOwDxAQAAAA==.Caliopia:BAABLgAECn8xAAMPAAkJvBQCIADjAQAPAAkJvBQCIADjAQAOAAYJYQqXcQAIAQAAAA==.Caliper:BAAALgAECgEJAQAAAA==.Canrif:BAAALgAECgYJBgAAAA==.Caplyta:BAABLgAECn8UAAISAAkJtR98BgAtAgASAAkJtR98BgAtAgABLgAFFAUJEgAJACscAA==.Captnhuntcat:BAAALgAECggJEwAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.Cathode:BAAALgAFFAEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8vAAIVAAkJNxevEwBUAgAVAAkJNxevEwBUAgAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAABLgAECn8bAAMZAAkJaR2cEAABAgAZAAkJaR2cEAABAgAXAAQJJA/ZyQDxAAAAAA==.Chemistree:BAABLgAECn88AAIMAAkJmxQaJwAXAgAMAAkJmxQaJwAXAgAAAA==.Chillout:BAABLgAECn8nAAIQAAkJvw2LYwC3AQAQAAkJvw2LYwC3AQAAAA==.Chillums:BAABLgAECn8cAAIRAAcJ4iP7GgCzAgARAAcJ4iP7GgCzAgAAAA==.Chipcle:BAAALgAECgQJBwAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Ci='Cillah:BAAALgAECgEJAwABLgAECgkJOQAVAPwfAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgAECgEJAQAKAAAAAA==.',
Co='Codeblue:BAAALgADCgkJEQAAAA==.Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8dAAILAAkJYg7CKQDAAQALAAkJYg7CKQDAAQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Cy='Cy:BAABLgAECn8jAAMdAAkJCBaJBQCKAQAdAAkJCBaJBQCKAQAcAAIJmhQyCgB4AAAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAABLgAECggJFQAXAB4bAA==.Daeleiel:BAAALgAECgEJAQAAAA==.Damrek:BAAALgAECgEJAQAAAA==.Darkenergy:BAABLgAECn9DAAMUAAkJpiToAQBTAwAUAAkJpiToAQBTAwABAAkJuh85EQC4AgAAAA==.Darà:BAABLgAECn8aAAMJAAcJBwjRCADFAAAJAAYJUwjRCADFAAAIAAUJrgeuVQCFAAABLgAECgkJRAANANgSAA==.Dashyll:BAAALgAECgYJCgAAAA==.Davyfknjones:BAABLgAECn8aAAIHAAgJTxhFOAD9AQAHAAgJTxhFOAD9AQAAAA==.Daynia:BAAALgAECgYJEQAAAA==.',
De='Deadbolt:BAAALgAECgYJBgAAAA==.Deadlegslul:BAABLgAECn8mAAIHAAgJCiGzIgBZAgAHAAgJCiGzIgBZAgAAAA==.Deadlegsmd:BAAALgAECgUJCQAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadtree:BAAALgAECgEJAQAAAA==.Deadzepplin:BAAALgAECgUJDgAAAA==.Deathfish:BAAALgAECgUJBgAAAA==.Deathmono:BAAALgAECgYJDQAAAA==.Deathshark:BAACLgAFFH8cAAIZAAUJrhy/FQA+AQAZAAUJrhy/FQA+AQAuAAQKfzEAAhkACQkLH/oNACoCABkACQkLH/oNACoCAAAA.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAABLgAECn8kAAIQAAcJyAzyoAA5AQAQAAcJyAzyoAA5AQABLgAECggJRwAOAAcVAA==.Demeter:BAABLgAECn9EAAIGAAkJvBT8DQDlAQAGAAkJvBT8DQDlAQAAAA==.Demiurge:BAAALgAECgIJAgAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denalli:BAAALgAECgUJCQAAAA==.Denarien:BAAALgAECgkJDwAAAA==.Derpygos:BAAALgADCgcJBwABLgAECgkJLgARAO0gAA==.Detroitt:BAAALgADCgIJAgAAAA==.Devouress:BAACLgAFFH8QAAIBAAQJqA4yUgD3AAABAAQJqA4yUgD3AAAuAAQKfxoAAgEACAmEGIw7ANkBAAEACAmEGIw7ANkBAAAA.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dikasmuasha:BAAALgAECgMJAwABLgAECgMJAwAKAAAAAA==.Dillkiller:BAABLgAECn8XAAIeAAcJGQn9IQAuAQAeAAcJGQn9IQAuAQAAAA==.Dirgen:BAABLgAECn9WAAMVAAkJdx7EAADFAgAVAAkJdx7EAADFAgAeAAEJzhxXSgBMAAAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dogmaww:BAAALgADCgEJAQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAFFAUJEwAYAPMJAA==.Double:BAAALgAECgQJBAAAAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAABLgAECn8aAAIDAAgJYhpfHADyAQADAAgJYhpfHADyAQAAAA==.Dragginballs:BAAALgAECgIJBAABLgAFFAIJAgAKAAAAAA==.Draggnar:BAABLgAECn8YAAIaAAcJeAiCGgDQAAAaAAcJeAiCGgDQAAAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Drakomoe:BAAALgAFFAEJAQABLgAFFAEJAQAKAAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAABLgAECn8mAAMTAAkJgA+nFAD/AQATAAkJeA+nFAD/AQAfAAcJeAZWIACtAAAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJEQAPAFghAA==.',
Du='Dumplingsxo:BAABLgAECn8kAAMNAAkJnBhBGQA9AgANAAgJsBlBGQA9AgAMAAcJ4BiYPQCtAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn9IAAMSAAkJ4yVgAABiAwASAAkJ4yVgAABiAwAUAAYJgx1qGgCsAQAAAA==.',
Eb='Ebojager:BAABLgAECn9AAAIBAAkJVhpqHABqAgABAAkJVhpqHABqAgAAAA==.',
Eh='Ehko:BAAALgAECgYJCwABLgAECgkJJwATAA0lAA==.',
Ei='Eibon:BAACLgAFFH8eAAIXAAgJaB2hCwCDAgAXAAgJaB2hCwCDAgAuAAQKfx4AAhcACQnNIakUAAADABcACQnNIakUAAADAAAA.Einfreren:BAAALgAECgQJBAAAAA==.Einjeru:BAAALgAECgUJBQAAAA==.',
El='Elliiria:BAAALgAECgQJBgAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgkJEwAAAA==.Elvispriesty:BAABLgAECn8eAAIgAAcJQxXbIADHAQAgAAcJQxXbIADHAQAAAA==.Elwarrioro:BAAALgAFFAMJBAAAAA==.',
Em='Emaleonoc:BAAALgAECgEJAwAAAA==.Emmpunity:BAAALgAECgQJBAAAAA==.Emmune:BAABLgAECn8qAAIhAAkJ9BWqCQAiAgAhAAkJ9BWqCQAiAgAAAA==.',
En='Enobia:BAABLgAECn8wAAMaAAkJoRqhAwBXAgAaAAkJoRqhAwBXAgARAAUJFgbDxADQAAAAAA==.Entrapment:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Ep='Epsï:BAAALgAECgEJAQAAAA==.',
Er='Eriaeda:BAAALgAECgUJDQAAAA==.',
Es='Esen:BAAALgAECgQJBQABLgAECgkJPAARAPAXAA==.Eskath:BAABLgAECn8uAAIRAAkJ7SDoDADmAgARAAkJ7SDoDADmAgAAAA==.Essential:BAACLgAFFH8IAAIFAAQJNgvkWgD6AAAFAAQJNgvkWgD6AAAuAAQKfx0AAgUACAnpEnJ7AHgBAAUACAnpEnJ7AHgBAAAA.',
Et='Eternalpain:BAAALgAECgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8hAAIcAAYJfxNUPQALAQAcAAYJfxNUPQALAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgQJCQAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Felpickles:BAAALgAECgMJBAABLgAECgEJAQAKAAAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgAECgEJAQABLgAECggJJAAYAJsRAA==.Ferrara:BAACLgAFFH8nAAQTAAgJfCOoAgAPAgATAAYJxiOoAgAPAgAfAAcJkx71CwBdAQAHAAEJtx+1HwBiAAAuAAQKfyAABB8ACQnRIykGADoDAB8ACQmLIykGADoDAAcAAQn1I6ywAGIAABMAAQk6HgIsAEYAAAAA.',
Fi='Filthi:BAABLgAECn8XAAIPAAYJRiFuIAANAgAPAAYJRiFuIAANAgAAAA==.Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgUJBwAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgkJSQANAGskAA==.Fisted:BAAALgAFFAEJAQABLgAFFAMJCAALAGsbAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8cAAMIAAgJWCCmAAD9AgAIAAgJWCCmAAD9AgAJAAEJUg72OgBDAAAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.Fluorita:BAAALgAECgEJAQAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Friedá:BAAALgAECgIJAwABLgAECgYJEgAKAAAAAA==.Frostednip:BAACLgAFFH8RAAMXAAUJJhoTYAA0AQAXAAUJ3RkTYAA0AQAiAAIJoRIZHwCNAAAuAAQKfyQAAyIACQnaIPwJAOMBABcACQm/IE4+AAkCACIABwmhG/wJAOMBAAAA.Frozar:BAAALgAECgEJAgAAAA==.',
Ga='Gabaghoul:BAAALgAECgQJBAAAAA==.Gabiru:BAACLgAFFH8IAAQDAAMJ9gQVTgCWAAADAAMJ9gQVTgCWAAACAAMJ4w6eIwCEAAAWAAEJlwEsDABCAAAuAAQKfxUAAwIACQlTE2YSABkCAAIACQlTE2YSABkCAAMAAQm0CZphADUAAAAA.Gadreeste:BAAALgAECggJCQAAAA==.Galnarn:BAACLgAFFH8oAAIYAAcJyyBYCAAKAgAYAAcJyyBYCAAKAgAuAAQKfyEAAhgACQlkHfgNALQCABgACQlkHfgNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Gank:BAAALgAFFAEJAQABLgAFFAcJHwABALQZAA==.Garious:BAAALgAECgcJBwABLgAFFAUJEgAXAKMiAA==.Garjingo:BAAALgAECgUJBgABLgAECgkJRAAWAHQjAA==.Garlicbae:BAABLgAECn8dAAIjAAgJeQs2BQD9AAAjAAgJeQs2BQD9AAAAAA==.Garwulf:BAABLgAECn8dAAITAAkJbwYWIwCFAQATAAkJbwYWIwCFAQAAAA==.',
Ge='Gefaustet:BAABLgAECn9EAAQeAAkJHBuXCwA0AgAeAAkJHBuXCwA0AgAVAAEJ8gbQqwArAAAEAAEJKwroDwApAAAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gi='Gilberticus:BAAALgAECgMJAwABLgAECgkJUwAcAMUiAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECgcJCQAAAA==.Glyd:BAAALgAECgYJCQABLgAECggJRwAOAAcVAA==.',
Go='Goatcheesè:BAAALgAECgIJBAAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAFFAEJAQAAAA==.Gorbachev:BAAALgAECgYJCAAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAABLgAECn8cAAMYAAkJ+AqsKABtAQAYAAkJ+AqsKABtAQAcAAMJHgJxqgAoAAAAAA==.Grayes:BAABLgAECn8hAAMjAAYJMQjfRACUAAAjAAYJMQjfRACUAAAMAAIJLwIW9QAdAAABLgAECgkJHAAYAPgKAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hail:BAAALgADCgUJBQABLgAFFAUJCgADAMQQAA==.Hallowshade:BAABLgAECn8XAAIkAAcJFhnlJQDKAQAkAAcJFhnlJQDKAQAAAA==.Hardran:BAACLgAFFH8GAAIFAAIJYgPcpwByAAAFAAIJYgPcpwByAAAuAAQKfycAAgUACAl3EqMLADABAAUACAl3EqMLADABAAAA.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgAECgQJDAAAAA==.Hatreddyes:BAAALgAECgMJAwABLgAECgkJCwAKAAAAAA==.Hatredyes:BAAALgAECgkJCwAAAA==.Hattredyess:BAAALgAECgUJBQABLgAECgkJCwAKAAAAAA==.',
He='Headrot:BAAALgAECgEJAgAAAA==.Heatedsoul:BAAALgAECgEJAQAAAA==.Helanne:BAAALgADCgUJBQAAAA==.Helare:BAABLgAECn8XAAINAAkJ2xgNEgBIAgANAAkJ2xgNEgBIAgAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAABLgAECn8nAAIlAAkJrQ2uFAB4AQAlAAkJrQ2uFAB4AQAAAA==.',
Hi='Hinatsuru:BAAALgAECgQJBAAAAA==.',
Ho='Holyzap:BAAALgAECgIJAgABLgAECgkJJQAQABEhAA==.Horsegirl:BAAALgAECgEJAgAAAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Huffmetoes:BAEALgADCgcJFAABLgAECgkJPwAIAIMZAA==.Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECggJCQAAAA==.Huulrokk:BAAALgADCgkJDAABLgAECgkJFQAOAHoVAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.Hyperreal:BAAALgAECgEJAQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgkJJwALAJsbAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwAKAAAAAA==.Idlewild:BAEALgAECgYJCQABLgAECggJJgAPANkPAA==.',
If='Iforgotnaaru:BAABLgAECn8XAAMOAAcJ4QvecgAEAQAOAAcJ4QvecgAEAQAPAAQJtQrcbACiAAAAAA==.',
Ik='Ikedizzy:BAAALgAFFAEJAQABLgAFFAMJBAAKAAAAAA==.Ikeslice:BAAALgAFFAMJBAAAAA==.Ikrys:BAAALgAECgYJDAAAAA==.',
Il='Illiae:BAACLgAFFH8PAAIPAAMJPiNfHQAxAQAPAAMJPiNfHQAxAQAuAAQKfzIAAg8ACQkiJA8KAL4CAA8ACQkiJA8KAL4CAAAA.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8rAAIVAAgJxxOfLQCbAQAVAAgJxxOfLQCbAQAAAA==.',
In='Incrdblestan:BAAALgAECgMJCAAAAA==.Innex:BAABLgAECn8nAAIXAAkJGx+gLABNAgAXAAkJGx+gLABNAgAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECgkJJwAXABsfAA==.Innexvoker:BAABLgAECn8YAAIDAAgJag9VMgBsAQADAAgJag9VMgBsAQABLgAECgkJJwAXABsfAA==.Inpesca:BAAALgADCgUJBQABLgAFFAUJCgADAMQQAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgYJCwAAAA==.',
Ir='Iridescent:BAAALgAECgMJBAAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAABLgAECn8hAAIfAAgJNQ7DEwAkAQAfAAgJNQ7DEwAkAQAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itook:BAAALgADCgEJAQAAAA==.Itzmuffin:BAABLgAECn8oAAIOAAgJyRItTQB8AQAOAAgJyRItTQB8AQAAAA==.Itzpie:BAABLgAECn81AAIQAAkJNxYoSgD9AQAQAAkJNxYoSgD9AQAAAA==.',
Ja='Jace:BAABLgAECn8WAAIFAAYJDhyCggBqAQAFAAYJDhyCggBqAQAAAA==.Jadandotz:BAAALgADCggJAgAAAA==.Jagtat:BAABLgAECn8hAAMXAAgJkg8ZmQA3AQAXAAgJkg8ZmQA3AQAZAAUJcQcKRQB6AAAAAA==.Jakeakuma:BAABLgAECn8UAAIRAAkJBAwlXwCsAQARAAkJBAwlXwCsAQAAAA==.Jascob:BAABLgAECn8lAAImAAYJXA+5AQDmAAAmAAYJXA+5AQDmAAAAAA==.Jasonborne:BAAALgAECgQJBAAAAA==.Jaynne:BAAALgADCgcJCAAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAABLgAECn8YAAIEAAcJXQY4BwCLAAAEAAcJXQY4BwCLAAAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn9QAAIYAAkJsB8zBgDZAgAYAAkJsB8zBgDZAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8lAAIcAAgJGiFcCAD0AgAcAAgJGiFcCAD0AgABLgAFFAQJBAAKAAAAAA==.Junfan:BAAALgAECgcJCQAAAA==.',
['Jà']='Jàckblack:BAAALgAECgYJDAAAAA==.',
Ka='Kaashaa:BAACLgAFFH8XAAIHAAUJthvSLQBVAQAHAAUJthvSLQBVAQAuAAQKf0EAAgcACQnLIRIPANgCAAcACQnLIRIPANgCAAAA.Kaelsgf:BAAALgAECgcJDAAAAA==.Kahllan:BAABLgAECn9EAAMNAAkJ2BJaAwBsAQANAAkJ2BJaAwBsAQAMAAcJeBISBQA0AQAAAA==.Kahnigitt:BAABLgAECn8XAAIXAAcJhwo2qQAeAQAXAAcJhwo2qQAeAQAAAA==.Kalsifire:BAAALgAECgYJEQAAAA==.Kataltoholic:BAABLgAECn8hAAIQAAYJ+QLzHwB5AAAQAAYJ+QLzHwB5AAAAAA==.Katrath:BAAALgADCgMJBgAAAA==.Kayhas:BAAALgAECgUJBwAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIBAAYJCxp5UAC1AQABAAYJCxp5UAC1AQAAAA==.Kaýhás:BAAALgADCgYJBgAAAA==.',
Ke='Kelinïsha:BAABLgAECn8pAAIQAAgJJQrrnwA7AQAQAAgJJQrrnwA7AQAAAA==.Kelynna:BAABLgAECn8pAAIIAAgJDhx4EgBKAgAIAAgJDhx4EgBKAgAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJBQAAAA==.',
Kh='Khaodemus:BAAALgAECggJCQAAAA==.Khellder:BAAALgAECggJEgABLgAECgkJEQAKAAAAAA==.Khelldyr:BAAALgAECgkJCQABLgAECgkJEQAKAAAAAA==.Khellrond:BAAALgAECgkJEQAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiffira:BAAALgAECgkJCwABLgAECgkJKQABAEUWAA==.Kiiras:BAABLgAECn8vAAIQAAgJ9A2UhQBsAQAQAAgJ9A2UhQBsAQAAAA==.Kimbodh:BAACLgAFFH8nAAIBAAYJVCS6DgBtAQABAAYJVCS6DgBtAQAuAAQKfyYAAgEACAkOJKgOAM8CAAEACAkOJKgOAM8CAAEuAAEKAwkBAAoAAAAA.Kimbubbles:BAAALgAECgMJAwABLgAECgYJCQAKAAAAAA==.Kimoora:BAAALgAECgYJCQAAAA==.Kimshady:BAAALgADCgEJAQABLgAECgYJCQAKAAAAAA==.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8wAAIBAAkJ+BB5SQCqAQABAAkJ+BB5SQCqAQAAAA==.',
Kl='Klefthoof:BAABLgAECn9HAAMOAAgJBxXELgD7AQAOAAgJBxXELgD7AQAPAAIJdAcGnQA/AAAAAA==.',
Ko='Kodey:BAABLgAECn8pAAIaAAkJxxSBBgD4AQAaAAkJxxSBBgD4AQABLgAFFAQJFgAaABQHAA==.Kordy:BAAALgAECgkJAQAAAA==.Korey:BAAALgAECgEJAQAAAA==.',
Kr='Kraniah:BAABLgAECn8VAAMOAAkJehUzHwBVAgAOAAkJehUzHwBVAgAPAAYJgATSdwCGAAAAAA==.Krelon:BAAALgAECgMJBQAAAA==.Krimboz:BAABLgAECn8vAAIRAAkJZxoXIABkAgARAAkJZxoXIABkAgAAAA==.Krimbrouge:BAAALgAECgYJCQAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8wAAITAAkJdBsiCgB9AgATAAkJdBsiCgB9AgAAAA==.Krìsta:BAACLgAFFH8GAAMbAAIJ7QLKEwBuAAAbAAIJ7QLKEwBuAAARAAEJ8QDC1gAvAAAuAAQKfx4AAxsACAncDFgNAGABABsABwleDlgNAGABABEABwknBOPBAMkAAAAA.',
Ku='Kuanshuwo:BAABLgAECn8VAAMJAAgJ7wksOAA0AQAJAAgJ7wksOAA0AQAIAAYJfQZMTgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
Ky='Kyarcy:BAAALgAECgQJAwAAAA==.Kyokan:BAAALgADCgYJBgAAAA==.',
La='Lanwulf:BAABLgAECn8VAAIFAAYJ5AYE8ADKAAAFAAYJ5AYE8ADKAAAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAACLgAFFH8LAAIJAAUJUxXhGQAaAQAJAAUJUxXhGQAaAQAuAAQKfxgAAgkACQlvHb4XACYCAAkACQlvHb4XACYCAAAA.Legaloas:BAABLgAECn8xAAMHAAkJnyDbFgCeAgAHAAkJnyDbFgCeAgAfAAUJGxFEGADwAAAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAABLgAECn8YAAIcAAcJ7A0+OgAYAQAcAAcJ7A0+OgAYAQAAAA==.Leonarde:BAACLgAFFH8PAAMHAAQJKBn7RQAhAQAHAAQJIBn7RQAhAQAfAAMJ2Q/RFQDuAAAuAAQKfyIABB8ACQkZGb8gACACAB8ACAkSF78gACACAAcABQl/GJ1vAGEBABMAAQlWAKwzAA0AAAAA.Levitt:BAABLgAECn8WAAIRAAYJjhHGkwAUAQARAAYJjhHGkwAUAQABLgAECgkJIwAdAAgWAA==.Leyla:BAAALgADCgkJCQAAAA==.',
Li='Lifelessvoid:BAAALgAECgQJCAAAAA==.Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn80AAIcAAkJbhZdFgAEAgAcAAkJbhZdFgAEAgAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liquid:BAAALgAECgEJAQAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgYJEAAAAA==.',
Ll='Llevanya:BAABLgAECn9IAAIFAAkJ2hB7WwC7AQAFAAkJ2hB7WwC7AQAAAA==.Llinae:BAAALgAECgEJAQAAAA==.Llinaigh:BAACLgAFFH8PAAIHAAQJPBRqIADuAAAHAAQJPBRqIADuAAAuAAQKfxkAAgcACQmDFaA8AO4BAAcACQmDFaA8AO4BAAAA.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAgABLgAECgkJOQAVAPwfAA==.Lofi:BAAALgAECgEJAQAAAA==.Lomu:BAABLgAECn8rAAQjAAkJyxwECgBIAgAjAAkJyxwECgBIAgAMAAEJ7Q5JzwAvAAANAAEJigSvoAAhAAABLgAECgkJLgARAO0gAA==.Loredalso:BAAALgAECgEJAQAAAA==.Lorenitha:BAAALgAECgEJAQABLgAFFAQJDQAFABccAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
['Lê']='Lêdrollan:BAAALgAECgIJAgABLgAFFAUJCwAJAFMVAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAFFAMJCAALAGsbAA==.Magicdreams:BAABLgAECn80AAINAAkJNAn6MABZAQANAAkJNAn6MABZAQAAAA==.Malificent:BAAALgADCgQJCAAAAA==.Malmorte:BAABLgAECn8WAAIXAAYJMRUHowA6AQAXAAYJMRUHowA6AQAAAA==.Malorane:BAABLgAECn8vAAIZAAkJFhshCwBjAgAZAAkJFhshCwBjAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgAECgEJAQAAAA==.Marihuano:BAABLgAFFH8IAAIkAAIJGQyXFgCLAAAkAAIJGQyXFgCLAAAAAA==.Marisi:BAAALgADCggJCAABLgAECgcJBwAKAAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIkAAkJ0R3tEQAYAgAkAAkJ0R3tEQAYAgAAAA==.Materiaga:BAABLgAECn8iAAQDAAgJEhEHMAB4AQADAAgJwBAHMAB4AQACAAYJFQtdKQAoAQAWAAMJjw9uGACVAAAAAA==.Material:BAAALgAECgEJAQAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8xAAIFAAkJKCE2EADkAgAFAAkJKCE2EADkAgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMhAAkJGxU2BgCWAgAhAAkJGxU2BgCWAgAPAAgJyg/bRAAgAQAAAA==.Mcshanks:BAAALgAECgMJAwAAAA==.',
Me='Medalla:BAAALgADCgYJBgAAAA==.Meerchi:BAABLgAECn8wAAMQAAkJCBnyOQAxAgAQAAkJCBnyOQAxAgAnAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Mefysto:BAAALgAECgUJBQAAAA==.Meiriie:BAAALgAECgYJDAAAAA==.Meldia:BAAALgAECgEJAgABLgAECgYJBgAKAAAAAA==.Meowkai:BAAALgAECgYJBgABLgAECgkJJwATAA0lAA==.Merix:BAAALgAECgYJBgAAAA==.Mesmal:BAAALgAECgkJAwAAAA==.Mesthos:BAAALgAECgcJDAABLgAECgkJKAASACwmAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8lAAIDAAgJlBKOGgD2AQADAAgJlBKOGgD2AQAAAA==.',
Mi='Miciah:BAAALgAECgQJBAAAAA==.Mickieta:BAABLgAECn8/AAIFAAkJ4SDOFADFAgAFAAkJ4SDOFADFAgAAAA==.Microsurge:BAACLgAFFH8HAAIQAAQJ4AgqcgD8AAAQAAQJ4AgqcgD8AAAuAAQKfx0AAhAACAkiHdslANsCABAACAkiHdslANsCAAAA.Mikalau:BAACLgAFFH8LAAIHAAMJ1wmuJgDPAAAHAAMJ1wmuJgDPAAAuAAQKfzkAAgcACQkGF8ImAEYCAAcACQkGF8ImAEYCAAAA.Mikaluu:BAABLgAECn8wAAIRAAcJKROiBQBiAQARAAcJKROiBQBiAQAAAA==.Milktide:BAAALgADCgYJBgABLgAFFAUJEgAJACscAA==.Miqkail:BAAALgAECggJCgABLgAECgkJKAASACwmAA==.Missteek:BAAALgAECgYJEgABLgAECgkJRAAWAHQjAA==.Mistrunner:BAAALgAECgMJAwAAAA==.Mistspell:BAACLgAFFH8QAAMJAAQJpQ/BHgD8AAAJAAQJpQ/BHgD8AAAIAAEJSglRGgApAAAuAAQKfyAAAwkACQnXHeQOAJUCAAkACQnXHeQOAJUCAAgAAwklBoFqAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwABLgAECgkJJwALAJsbAA==.Mognel:BAABLgAECn82AAIRAAkJxxySKgAwAgARAAkJxxySKgAwAgAAAA==.Mogrungar:BAACLgAFFH8JAAIOAAMJwxHqVgCgAAAOAAMJwxHqVgCgAAAuAAQKfygAAg4ACQl3FC0nACQCAA4ACQl3FC0nACQCAAAA.Moistdk:BAAALgAECgEJAQAAAA==.Moisten:BAABLgAECn8eAAIPAAkJQyCCCADVAgAPAAkJQyCCCADVAgAAAA==.Mokuo:BAAALgAFFAIJAwAAAA==.Monklee:BAAALgAECgEJAgAAAA==.Moomootus:BAABLgAECn8zAAMFAAkJeRsTOgAbAgAFAAgJFRsTOgAbAgALAAQJ/B4wPQBRAQAAAA==.Mordakttaa:BAAALgADCgMJBQAAAA==.Morgalea:BAAALgAECgcJAQAAAA==.Motoraxe:BAAALgAFFAIJAwAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIcAAgJRyBsDQClAgAcAAgJRyBsDQClAgABLgAFFAQJEAABAKgOAA==.Mystynight:BAABLgAECn8UAAIJAAcJ9Au6QwAAAQAJAAcJ9Au6QwAAAQAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAABLgAECn8nAAIPAAkJbg41PQBBAQAPAAkJbg41PQBBAQAAAA==.Naggs:BAAALgAECgkJCAAAAA==.Nagini:BAABLgAECn8fAAIRAAgJdwhEiwAjAQARAAgJdwhEiwAjAQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Nevon:BAAALgADCgEJAQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn8/AAMIAAkJgxkoHQDcAQAIAAcJGRkoHQDcAQAJAAkJtBGgPgAWAQAAAA==.Nietzcha:BAAALgAECgQJBwAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAABLgAECn8kAAMNAAgJ7Rb6HADhAQANAAgJ7Rb6HADhAQAlAAUJRw2oNwB8AAAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nilfgard:BAAALgAECgcJEgAAAA==.Nioh:BAABLgAECn8iAAIBAAkJxRasLwAIAgABAAkJxRasLwAIAgAAAA==.Nivix:BAAALgAECgEJAgAAAA==.',
No='Noodles:BAABLgAECn8nAAIBAAgJnwjLlwDxAAABAAgJnwjLlwDxAAAAAA==.Nordrydd:BAAALgAECggJDgABLgAFFAgJGQAdAPUUAA==.Nordrydsh:BAAALgAFFAIJAgABLgAFFAgJGQAdAPUUAA==.',
Nu='Nuggs:BAABLgAECn8YAAIlAAkJzBB3EACwAQAlAAkJzBB3EACwAQAAAA==.Nuhpie:BAACLgAFFH8XAAMEAAcJhw43KADMAAAVAAMJUxGSOADQAAAEAAQJugs3KADMAAAuAAQKfx4AAwQACQlfHfQfAF4BAAQABQmuGvQfAF4BABUABQlsHJhMABQBAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8lAAIXAAkJax/eGQCrAgAXAAkJax/eGQCrAgAAAA==.',
Od='Odelay:BAAALgADCgEJAQAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAwAAAA==.',
Ol='Olimdar:BAACLgAFFH8qAAIOAAgJjCR8AAA9AwAOAAgJjCR8AAA9AwAuAAQKfycAAw4ACQlvJUsAAM8DAA4ACQlvJUsAAM8DAA8AAQmSHaiCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBwAAAA==.',
Oo='Oopositive:BAAALgAECgUJDAAAAA==.Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Orgarrot:BAAALgADCgYJBgABLgAECgkJCwAKAAAAAA==.Oricelle:BAABLgAECn8pAAIBAAkJRRaDKgAfAgABAAkJRRaDKgAfAgAAAA==.Oridis:BAAALgAECgkJBwAAAA==.Oryon:BAEBLgAECn8zAAIbAAkJnRR/CADgAQAbAAkJnRR/CADgAQAAAA==.',
Ot='Otos:BAAALgADCgcJBwAAAA==.',
Ov='Ovarb:BAABLgAECn8xAAMZAAkJ9BhFEgDqAQAZAAkJkRhFEgDqAQAXAAkJUg/ggwBcAQAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDgAAAA==.Palasexo:BAAALgAECgUJCQABLgAFFAIJCAAkABkMAA==.Palldude:BAAALgADCgQJBQAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Peachie:BAAALgADCgEJAQAAAA==.Pesti:BAACLgAFFH8hAAIkAAQJCB8qEgB9AQAkAAQJCB8qEgB9AQAuAAQKf1EAAiQACQlnI8YCACgDACQACQlnI8YCACgDAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8+AAIOAAkJQiM7BAB2AwAOAAkJQiM7BAB2AwAAAA==.',
Pi='Pissedwolf:BAAALgAFFAEJAQAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAABLgAECn8fAAIYAAkJeBCbIACiAQAYAAkJeBCbIACiAQAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAACLgAFFH8WAAIQAAUJgxjXUgA3AQAQAAUJgxjXUgA3AQAuAAQKf0cABBAACQkJIqkOAAUDABAACQmIIakOAAUDACgABQnyFiQMABABACcAAQmjEFIUADEAAAAA.Proctologist:BAABLgAECn8zAAMYAAkJ9BvFCACmAgAYAAkJ9BvFCACmAgAcAAQJYROoQwDwAAAAAA==.Proserpìne:BAABLgAECn9NAAIBAAkJBA6NVgCDAQABAAkJBA6NVgCDAQAAAA==.',
Ps='Psychojester:BAACLgAFFH8TAAIhAAUJRxp+BwA/AQAhAAUJRxp+BwA/AQAuAAQKf0MAAiEACQk2IWECAPcCACEACQk2IWECAPcCAAAA.Psylir:BAAALgAECgQJDgAAAA==.Psypra:BAAALgAECgYJCQAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAABLgAECn8WAAIQAAUJihtcvQANAQAQAAUJihtcvQANAQAAAA==.',
Py='Pydge:BAAALgAECgEJAQAAAA==.',
Qu='Queeb:BAAALgAECgUJBgAAAA==.Quod:BAAALgAECgQJBAAAAA==.Quoril:BAACLgAFFH8FAAIQAAIJDQ91ogCKAAAQAAIJDQ91ogCKAAAuAAQKfz8AAxAACQkLIYMQAPgCABAACQkLIYMQAPgCACgAAQmXIHkZAEwAAAEuAAUUCAkhAAcAJxQA.',
Ra='Raijyu:BAABLgAECn9HAAMIAAkJzR8/BQAoAwAIAAkJzR8/BQAoAwAJAAcJVRV+IwC8AQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECgkJNgANAM8WAA==.Rainstormin:BAABLgAECn82AAMNAAkJzxZaFgAbAgANAAkJzxZaFgAbAgAjAAYJxgk+QQCiAAAAAA==.Rakarra:BAABLgAECn8fAAMMAAkJGgvJSABsAQAMAAkJGgvJSABsAQANAAcJhwgPTQD2AAAAAA==.Ranalia:BAAALgADCgcJCgAAAA==.Rawrstance:BAABLgAECn9FAAMZAAkJQRwSAwBYAQAXAAcJoRyudAB6AQAZAAkJGhQSAwBYAQABLgAECgEJAQAKAAAAAA==.Razgrize:BAACLgAFFH8RAAIQAAQJLxMRLQDOAAAQAAQJLxMRLQDOAAAuAAQKfzQAAhAACQm/G/MjAI0CABAACQm/G/MjAI0CAAAA.',
Re='Redraggon:BAAALgAECgYJBgAAAA==.Reecalled:BAAALgADCgUJBQABLgAECggJGgADAGIaAA==.Reeshan:BAABLgAECn8fAAMFAAkJ1yPFDgDwAgAFAAkJ1yPFDgDwAgALAAIJaxSRdABnAAAAAA==.Reilin:BAAALgAFFAEJAQAAAA==.Remsham:BAABLgAECn8nAAIhAAkJxg0YEACwAQAhAAkJxg0YEACwAQAAAA==.Reniel:BAAALgAECgcJCQABLgAECgkJMAABAPgQAA==.Renwyck:BAABLgAECn8oAAISAAkJLCZcAABjAwASAAkJLCZcAABjAwAAAA==.Reubenb:BAAALgAECgEJAQABLgAECgkJMQAHAAEPAA==.Revengemoon:BAACLgAFFH8SAAIFAAQJsxLTTAAUAQAFAAQJsxLTTAAUAQAuAAQKfyMAAgUACQmVGsApAH4CAAUACQmVGsApAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgAKAAAAAA==.Riftstrider:BAAALgAECgYJBwAAAA==.Rikkren:BAAALgAFFAEJAQAAAA==.Ringberg:BAACLgAFFH8IAAILAAMJaxsjLQDHAAALAAMJaxsjLQDHAAAuAAQKfxcAAwsABwlSHzsZAD0CAAsABwlSHzsZAD0CAAUAAwmmFNkLAaoAAAAA.',
Ro='Robane:BAABLgAECn8UAAIFAAUJCA+e5wDUAAAFAAUJCA+e5wDUAAAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Rockette:BAAALgAECgQJBQAAAA==.Ronburgundy:BAAALgAECgMJBQAAAA==.Rouen:BAABLgAECn80AAMOAAkJ2xoIFQCjAgAOAAkJ2xoIFQCjAgAhAAgJiiIZBwBgAgAAAA==.',
Ru='Rubidea:BAAALgAECgEJAQAAAA==.Ruckus:BAEBLgAECn8dAAQMAAgJTQvnXAAgAQAMAAgJTQvnXAAgAQAjAAMJFAdIEABSAAANAAEJlQ6wFQAtAAABLgAECggJJgAPANkPAA==.Ruder:BAAALgAECgMJBAABLgAECgkJCwAKAAAAAA==.Rutabaga:BAAALgAECgUJCgAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIJAAkJxBtnEQBzAgAJAAkJxBtnEQBzAgAAAA==.',
Sa='Saintanic:BAAALgAECgEJAQAAAA==.Sandkat:BAABLgAECn9BAAIVAAkJZCJrBgD4AgAVAAkJZCJrBgD4AgAAAA==.Sanstian:BAAALgAECgUJDQAAAA==.Santamou:BAAALgAECgYJDQABLgAFFAEJAQAKAAAAAA==.Saraelin:BAABLgAFFH8IAAIRAAIJ8ABpvgBLAAARAAIJ8ABpvgBLAAAAAA==.Saray:BAAALgAECgcJEgAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAYJEwAVAO4QAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgYJDgAAAA==.Serahstia:BAABLgAECn8gAAIQAAkJCBX5ZQCyAQAQAAkJCBX5ZQCyAQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shadowmeld:BAAALgAECgEJAQAAAA==.Shadysadie:BAAALgAECgcJEQAAAA==.Shaiy:BAAALgAECgcJEAAAAA==.Shakejunt:BAAALgADCgIJAgAAAA==.Shammymoe:BAAALgAFFAEJAQAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwAKAAAAAA==.Shiifthappen:BAAALgAECgEJAQAAAA==.Shinta:BAABLgAECn8WAAQLAAYJtRRbPwBHAQALAAYJtRRbPwBHAQAGAAUJ2g+3KwC/AAAFAAQJAwixLgGBAAAAAA==.Shirtles:BAABLgAECn8YAAIPAAYJggOsdACOAAAPAAYJggOsdACOAAAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shpik:BAAALgADCgUJCQAAAA==.Shèp:BAABLgAECn8fAAILAAgJvxEHBgD2AAALAAgJvxEHBgD2AAAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIPAAUJ/hmfAwCvAQAPAAUJ/hmfAwCvAQABLgAFFAcJFAATAPEUAA==.Siffrin:BAAALgAECgIJAgAAAA==.Siink:BAABLgAFFH8FAAIkAAIJ0wwmFwCDAAAkAAIJ0wwmFwCDAAAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8lAAMRAAgJnhWGdABRAQARAAYJ0hKGdABRAQAbAAUJJRaiGgDpAAABLgAECggJJQADAJQSAA==.Sinkingship:BAAALgAECgYJCgAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAABLgAECn8sAAIZAAkJgSA7BgC/AgAZAAkJgSA7BgC/AgAAAA==.',
Sk='Skaterboi:BAAALgAECgYJBgAAAA==.Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sliy:BAAALgAECgIJAgAAAA==.Sloothe:BAAALgADCgQJBAAAAA==.Sloothi:BAAALgAECgEJAQAAAA==.Slyveria:BAAALgAECgMJBAAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.Snorri:BAABLgAFFH8GAAMXAAMJORW+RACfAAAXAAMJ8xC+RACfAAAiAAEJQxdREgBJAAAAAA==.',
So='Sosorry:BAAALgADCgIJAgAAAA==.Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAABLgAECn8WAAIFAAkJgRpENgAoAgAFAAkJgRpENgAoAgAAAA==.',
Sp='Sprodage:BAABLgAECn9NAAILAAkJVhjnFQBcAgALAAkJVhjnFQBcAgAAAA==.',
St='Staggrsaurus:BAAALgAECgIJAwABLgAECgMJBAAKAAAAAA==.Stanil:BAABLgAECn8uAAMHAAkJPQrOcABfAQAHAAkJPQrOcABfAQAfAAEJWwAkmwAVAAAAAA==.Stayfrosty:BAAALgAECgcJDQAAAA==.Stellare:BAABLgAECn8wAAIUAAkJHRdjEQAUAgAUAAkJHRdjEQAUAgAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Stinklines:BAAALgAECgEJAgABLgAECgkJRAAWAHQjAA==.Strangetame:BAAALgADCgEJAQAAAA==.Striest:BAAALgAECgMJAwAAAA==.Styló:BAAALgAECggJEwAAAA==.',
Su='Suetonius:BAACLgAFFH8VAAMXAAUJRR9tQwBuAQAXAAQJRR9tQwBuAQAZAAEJAAAVIgAAAAAuAAQKfxQAAxcACAlXJH4RAOECABcACAlXJH4RAOECACIAAgk4Ey8vAGMAAAAA.Suguru:BAAALgAECggJCQAAAA==.Sungsuf:BAAALgAECgEJAQAAAA==.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8rAAIQAAkJaBqIOAA2AgAQAAkJaBqIOAA2AgAAAA==.Suraschi:BAABLgAECn8iAAMYAAkJ2BhKAQDQAQAYAAkJEhhKAQDQAQAcAAcJjxFILgBRAQABLgAECgkJKwAQAGgaAA==.',
Sv='Svelda:BAABLgAECn8xAAMJAAkJDg7cJwCQAQAJAAkJDg7cJwCQAQAgAAUJmAULUwC1AAAAAA==.',
Sw='Swisscake:BAABLgAECn9JAAINAAkJaySoAgBHAwANAAkJaySoAgBHAwAAAA==.Swtmystic:BAAALgAECgcJBwAAAA==.',
Sy='Sylain:BAAALgAECgYJEgABLgAECgkJFQAkAKEKAA==.Synwav:BAAALgAECgIJAgAAAA==.',
Ta='Tannatax:BAABLgAECn8vAAIOAAkJZQbUWwBKAQAOAAkJZQbUWwBKAQAAAA==.Tashah:BAAALgADCggJCwAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAAKAAAAAA==.',
Th='Thauyia:BAAALgAECgEJAQAAAA==.Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8jAAMQAAkJnBWLVADfAQAQAAkJnBWLVADfAQAnAAEJGgGRGAAJAAAAAA==.Thewretch:BAABLgAECn85AAIRAAkJhyLYBwAZAwARAAkJhyLYBwAZAwAAAA==.Thibble:BAAALgADCgYJBgAAAA==.Thumpthump:BAABLgAECn8nAAQTAAkJQBisFAD+AQAfAAYJwx6nIgARAgATAAkJMhCsFAD+AQAHAAEJqQ7sLwE3AAAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEBLgAECn8mAAIPAAgJ2Q9XNwBbAQAPAAgJ2Q9XNwBbAQAAAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Tindoranis:BAAALgAECgUJBQAAAA==.Titiera:BAABLgAECn8jAAIHAAkJ7BaoOwDxAQAHAAkJ7BaoOwDxAQAAAA==.',
To='Toastnbutta:BAABLgAECn8mAAIMAAkJ9xnRGAB/AgAMAAkJ9xnRGAB/AgAAAA==.Tolten:BAABLgAECn8eAAIFAAgJ3RmUMQBcAgAFAAgJ3RmUMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgYJCAAAAA==.Traumatism:BAAALgAECgkJEwAAAA==.Trevor:BAABLgAECn9BAAImAAkJUhhpBABPAgAmAAkJUhhpBABPAgAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.Tryxi:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAACLgAFFH8KAAMlAAMJARiZCwD5AAAlAAMJARiZCwD5AAAjAAEJXBmJNgBKAAAuAAQKfyAAAyUACQnLIogBAC4DACUACQnLIogBAC4DACMABgk0HBMZAIYBAAEuAAUUBQkcABkArhwA.Tsura:BAAALgAFFAEJAQAAAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Ty='Tylaesh:BAAALgAECgYJDwAAAA==.',
Un='Unclepeepers:BAACLgAFFH8WAAIdAAQJ4iDmIQBfAQAdAAQJ4iDmIQBfAQAuAAQKfy4AAxwACQkPIxYQAEsCABwACAmOIhYQAEsCAB0ACQm0G5wjAAMCAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAABLgAECn8bAAIXAAcJug/2EgDDAAAXAAcJug/2EgDDAAAAAA==.',
Ur='Urtag:BAACLgAFFH8UAAMfAAgJVBMaDgB8AQAfAAcJRA0aDgB8AQAHAAQJ7xJhMQBMAQAuAAQKfxUAAx8ACAnyFboqANYBAB8ACAkZFboqANYBAAcAAgm6F3jYAJwAAAAA.',
Ut='Uthgar:BAAALgAECgYJCAAAAA==.',
Va='Vadge:BAAALgAECgEJAgABLgAECgEJAQAKAAAAAA==.Vaeryn:BAABLgAECn8kAAIHAAcJ3BQIDAA2AQAHAAcJ3BQIDAA2AQABLgAFFAMJDQAgAKsOAA==.Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAACLgAFFH8NAAIgAAMJqw4vMwC/AAAgAAMJqw4vMwC/AAAuAAQKf3QAAyAACAlXH90JANMCACAACAlXH90JANMCAAkABwneEPgxAFQBAAAA.Valryn:BAABLgAECn8aAAMXAAcJKgsRogApAQAXAAcJKgsRogApAQAZAAEJxgH7TwAVAAABLgAFFAMJDQAgAKsOAA==.Valtar:BAABLgAECn8hAAIOAAkJoBxrGgB3AgAOAAkJoBxrGgB3AgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAACLgAFFH8IAAMXAAUJRRQ6YAA0AQAXAAUJRRQ6YAA0AQAZAAMJyhEkDgCJAAAuAAQKfzAAAxcACQmJI70GAEEDABcACQmJI70GAEEDABkACAntHUsPABcCAAAA.',
Ve='Veliraleonoc:BAAALgAECgEJAgAAAA==.Velra:BAAALgADCgEJAQABLgAFFAMJDQAgAKsOAA==.Velryn:BAACLgAFFH8FAAIdAAMJHQo9HwCHAAAdAAMJHQo9HwCHAAAuAAQKfykAAh0ACAlvGcoBAEECAB0ACAlvGcoBAEECAAEuAAUUAwkNACAAqw4A.Veraalyn:BAABLgAECn8dAAMPAAgJHhH9RQAcAQAPAAgJHhH9RQAcAQAOAAMJxwiifgCZAAAAAA==.Verleanna:BAAALgADCgYJBgAAAA==.',
Vi='Vicsen:BAABLgAECn8gAAIRAAkJdQVbgQA2AQARAAkJdQVbgQA2AQAAAA==.Vikaya:BAAALgAECggJCgAAAA==.Vilaris:BAAALgAECggJDgAAAA==.Vilevixon:BAABLgAECn8hAAMJAAkJ4hbdFwAIAgAJAAkJ4hbdFwAIAgAgAAMJxgcbYAB9AAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Vo='Voidasuras:BAAALgAECgEJAQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAAKAAAAAA==.Wanlok:BAAALgAECgQJCQAAAA==.Wantoo:BAAALgAECgYJBgAAAA==.Warlokip:BAAALgAECgkJCgAAAA==.Warmis:BAAALgAECgEJAQABLgAECgkJSAASAOMlAA==.Warotar:BAAALgAECgIJAgAAAA==.Warriorlobo:BAABLgAECn85AAQVAAkJ/B/PCADUAgAVAAkJ/B/PCADUAgAEAAYJ7RDVMgD7AAAeAAEJ6A4QWgAjAAAAAA==.Warvision:BAAALgAFFAEJAQAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAABLgAECn8iAAMHAAkJKAw1VgChAQAHAAkJKQw1VgChAQATAAEJQwNVagAoAAAAAA==.Wildside:BAABLgAECn8lAAMHAAgJ8R8yHQB2AgAHAAgJ8R8yHQB2AgATAAYJCxZ4KABcAQAAAA==.',
Wu='Wujifei:BAAALgAFFAIJAwAAAA==.Wulffgar:BAAALgAECgYJDAAAAA==.',
['Wì']='Wìldthìng:BAAALgAECgUJCgAAAA==.',
Xa='Xandronys:BAAALgAECgkJDAAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECggJCgAAAA==.Xenie:BAAALgAFFAQJBAAAAA==.Xennile:BAABLgAFFH8JAAIfAAUJThSxBAA8AQAfAAUJThSxBAA8AQAAAA==.',
Xi='Xinema:BAAALgAECgQJBAAAAA==.Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgAECgYJEAAAAA==.',
Yd='Ydeatho:BAAALgAFFAMJAwAAAA==.',
Ye='Yeet:BAABLgAECn8cAAIkAAkJNBj5IgDhAQAkAAkJNBj5IgDhAQAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgMJBgAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgAECgMJBgAAAA==.Zalanna:BAAALgADCgMJAwAAAA==.Zalckar:BAABLgAECn8bAAMLAAkJcBIZRQBjAQALAAkJcBIZRQBjAQAFAAEJYQ7soAEtAAAAAA==.Zanos:BAAALgAECgIJAgAAAA==.Zarayssa:BAAALgAECgEJAQAAAA==.Zarnok:BAAALgADCgkJCQAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zebracakes:BAAALgAECgEJAQABLgAECgkJSAASAOMlAA==.Zeeva:BAABLgAECn8cAAMaAAYJxiGVCADDAQAaAAYJ7SCVCADDAQAbAAMJ+h1lKAB/AAAAAA==.Zendead:BAABLgAECn8jAAIcAAkJCiP+BwDIAgAcAAkJCiP+BwDIAgAAAA==.Zeppeli:BAAALgAECgMJAwAAAA==.Zerkces:BAAALgADCgIJAgAAAA==.',
Zi='Zionspartan:BAABLgAECn8xAAIHAAkJAQ/bRADTAQAHAAkJAQ/bRADTAQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugpriest:BAAALgAECgQJBAAAAA==.Zugzugshaman:BAABLgAECn8yAAQOAAkJ6xkPGACJAgAOAAkJ6xkPGACJAgAPAAQJrwOHbgCJAAAhAAEJYQClSAAdAAAAAA==.Zurokhan:BAAALgAFFAEJAQAAAA==.Zuzill:BAAALgAECgUJBQABLgAECgYJHAAaAMYhAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Êï']='Êïñstëïn:BAAALgAECgEJAQAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8kAAIYAAgJmxF1JgB7AQAYAAgJmxF1JgB7AQAAAA==.',
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
