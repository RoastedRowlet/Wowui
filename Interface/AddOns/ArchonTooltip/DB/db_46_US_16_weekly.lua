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

local lookup = {'Priest-Holy','Priest-Shadow','Druid-Restoration','Mage-Frost','Unknown-Unknown','Druid-Balance','Druid-Feral','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Priest-Discipline','Hunter-BeastMastery','Paladin-Protection','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Blood','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Warrior-Protection','Warlock-Affliction','Druid-Guardian','Hunter-Survival','Warlock-Destruction','Rogue-Outlaw','Shaman-Enhancement','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Absoul:BAACLgAFFH8IAAIBAAMJhB4ODwAJAQABAAMJhB4ODwAJAQAuAAQKfyYAAwEACAnGIW8FAOUCAAEACAnGIW8FAOUCAAIAAQlxA/doACYAAAAA.',
Ac='Acedia:BAABLgAECn8xAAIBAAkJKhUKEAAfAgABAAkJKhUKEAAfAgAAAA==.',
Ad='Adellas:BAABLgAECn8mAAIDAAgJ1B+BDAC6AgADAAgJ1B+BDAC6AgAAAA==.Adern:BAABLgAECn8kAAICAAcJ2B6LEgBkAgACAAcJ2B6LEgBkAgAAAA==.Adon:BAABLgAECn8jAAIEAAgJYx15NQABAgAEAAgJYx15NQABAgAAAA==.Adondruel:BAAALgAECgEJAQAAAA==.',
Ae='Aelali:BAAALgAECgQJBgAAAA==.Aelith:BAAALgAECgcJEwAAAA==.',
Af='Afador:BAAALgAECgEJAwABLgAECgYJFgAEANgVAA==.',
Ag='Ageling:BAAALgADCgQJAgAAAA==.',
Ak='Akeno:BAAALgAECgMJAwABLgAECgIJAwAFAAAAAA==.Akrom:BAAALgADCgEJAgAAAA==.',
Al='Aladestar:BAACLgAFFH8KAAMDAAUJnwteIAAFAQADAAUJnwteIAAFAQAGAAMJrApxIADJAAAuAAQKfygAAwMACAnIGqwbAF4CAAMACAnIGqwbAF4CAAYACAkcIRciAOwBAAAA.Albinodargon:BAAALgAECgQJCwAAAA==.Alderleise:BAABLgAECn8ZAAQDAAgJYAr+SQAfAQADAAgJYAr+SQAfAQAGAAIJchXVYgA+AAAHAAEJlgjvNAAuAAAAAA==.Alecc:BAAALgAECgYJCwAAAA==.Alecw:BAAALgAECgQJBQAAAA==.Alexein:BAACLgAFFH8IAAIIAAQJ8wOXBwD4AAAIAAQJ8wOXBwD4AAAuAAQKfygAAggACAmzFg8FAPYBAAgACAmzFg8FAPYBAAAA.Alienspace:BAAALgADCgEJAQAAAA==.',
Am='Amets:BAABLgAECn8sAAMJAAgJtCVBAgBcAwAJAAgJtCVBAgBcAwAKAAUJXxkRfgAnAQAAAA==.Amydh:BAAALgAECgIJCQAAAA==.',
An='Anabel:BAAALgADCgkJFAAAAA==.Anamii:BAAALgADCgEJAQAAAA==.Andorsi:BAAALgAECgYJCAAAAA==.Anglechow:BAAALgADCgUJBQAAAA==.',
Ar='Arachne:BAABLgAECn8eAAICAAcJRQqvNQA+AQACAAcJRQqvNQA+AQAAAA==.Aranax:BAAALgADCgEJAgAAAA==.Arce:BAAALgAECgQJCgAAAA==.Architeleaf:BAAALgADCgMJAwABLgAECgMJAwAFAAAAAA==.Areafiftymoo:BAABLgAECn8yAAMLAAgJpAxHLABTAQALAAgJuwtHLABTAQAMAAEJ2wkrVQApAAAAAA==.Arthurleywin:BAAALgADCgIJAgAAAA==.Arysia:BAABLgAECn8VAAMEAAcJFhLPgQA4AQAEAAcJFhLPgQA4AQANAAMJsw4BEgCkAAAAAA==.Aryya:BAABLgAECn8+AAMHAAgJ2iNBAgDJAgAHAAgJ2iNBAgDJAgAGAAMJHAfBZwCCAAAAAA==.',
As='Astralbreak:BAAALgADCgQJBQABLgAECgUJBwAFAAAAAA==.',
At='Athelia:BAAALgADCgEJAQAAAA==.',
Au='Aulaes:BAAALgADCgIJAgAAAA==.',
Av='Avalan:BAABLgAECn81AAILAAgJnCGMCgB2AgALAAgJnCGMCgB2AgAAAA==.Avanolatwo:BAAALgAECgMJAwABLgAECgkJIwAOAO0dAA==.Avashammy:BAABLgAECn8jAAMOAAgJ7R3CHQAHAgAOAAgJ7R3CHQAHAgAPAAEJcQjTfgApAAAAAA==.Avesia:BAABLgAECn8aAAIQAAYJUhaeIgB/AQAQAAYJUhaeIgB/AQAAAA==.Aviendah:BAABLgAECn8eAAIRAAgJkRMYOgChAQARAAgJkRMYOgChAQAAAA==.',
Aw='Awsomeonet:BAABLgAECn8bAAMSAAgJMRiCEABkAQASAAgJMRiCEABkAQAKAAIJPwQZKAFQAAAAAA==.',
Ay='Ayot:BAAALgAECgcJEwAAAA==.',
Az='Azdfghop:BAACLgAFFH8bAAMRAAYJFSSeCACTAQARAAUJCiSeCACTAQATAAUJPBsNDwD3AAAuAAQKfyAAAxMACQm4IjIPAMcCABMACAnIHjIPAMcCABEACAmbIZM/ALEBAAAA.Azzinotica:BAAALgAECgEJAQAAAA==.',
Ba='Babeshot:BAABLgAECn8kAAIRAAgJWRZfMADJAQARAAgJWRZfMADJAQAAAA==.Babezila:BAAALgAECgYJDwAAAA==.Badshahprime:BAABLgAECn8eAAIKAAgJPhpjKgB7AgAKAAgJPhpjKgB7AgAAAA==.Barbiegrill:BAABLgAECn8dAAMUAAgJ7x7+DwCmAgAUAAgJEB7+DwCmAgAVAAUJVRxACQCuAQABLgAFFAMJCAAWABEZAA==.Battlemaker:BAAALgADCgcJBwABLgAECggJLgAOAMIXAA==.Baykin:BAABLgAECn8nAAIXAAgJNh8nCgBYAgAXAAgJNh8nCgBYAgAAAA==.',
Bb='Bbeastt:BAAALgADCgEJAgAAAA==.',
Be='Beefyfivelyr:BAAALgADCgcJBwAAAA==.Beldinnara:BAAALgAECgEJAQAAAA==.Berandas:BAABLgAECn8UAAMYAAcJ/hEGJgCDAQAYAAcJ/hEGJgCDAQAZAAUJjg3WOADOAAAAAA==.Bereessielin:BAAALgAECgQJBgAAAA==.Bergur:BAAALgAECgQJBAAAAA==.Berkowitz:BAABLgAECn8UAAIUAAUJ9Bm+JQAJAQAUAAUJ9Bm+JQAJAQAAAA==.',
Bi='Bigbear:BAAALgADCgEJAQABLgADCgMJAwAFAAAAAA==.',
Bl='Blaaze:BAAALgAECgQJBgAAAA==.Blaiddyd:BAABLgAECn8mAAIRAAgJUyCLGABHAgARAAgJUyCLGABHAgAAAA==.Blead:BAACLgAFFH8IAAMWAAMJERl9EgD4AAAWAAMJERl9EgD4AAAaAAEJtgVFuABHAAAuAAQKfxYABBYACAkIHn4JACwCABYACAkIHn4JACwCAAgAAgnbFTgZAHYAABoAAgl9FecJAToAAAAA.Blinkerr:BAAALgADCgkJDAAAAA==.Bluefarm:BAAALgADCgQJBAAAAA==.',
Br='Brahot:BAAALgAECgEJAQAAAA==.Brain:BAAALgAECgQJAwAAAA==.Brandawn:BAAALgADCgYJBgAAAA==.Branwarden:BAAALgAECgYJEgAAAA==.Brewsle:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebot:BAAALgAECgMJAwABLgAECggJKgAbACshAA==.Bullchitz:BAABLgAECn8WAAIRAAYJ+hibQwChAQARAAYJ+hibQwChAQAAAA==.Bullchitza:BAAALgADCgcJBwABLgAECgYJFgARAPoYAA==.Burningooch:BAAALgADCgEJAQAAAA==.',
['Bã']='Bãyy:BAAALgAECgYJEAAAAA==.',
['Bæ']='Bæyy:BAAALgADCgUJCgABLgAECgYJEAAFAAAAAA==.',
Ca='Calador:BAAALgAECggJEgAAAA==.Capybara:BAAALgAECgcJDAAAAA==.Caster:BAAALgADCgQJBAAAAA==.Cathbad:BAAALgADCgEJAQAAAA==.Caylynn:BAAALgAECgUJBQAAAA==.',
Ce='Celyne:BAABLgAECn8qAAMbAAgJKyHvFgBMAgAbAAgJKyHvFgBMAgAcAAcJThdTCQCCAQAAAA==.Cereza:BAAALgAECgEJAQAAAA==.',
Ch='Chaoslock:BAAALgADCgMJAwAAAA==.Chicknfajita:BAAALgAECgYJCAABLgAECgcJEQAFAAAAAA==.Chrissi:BAABLgAECn8cAAIDAAkJDwy+MwCFAQADAAkJDwy+MwCFAQAAAA==.',
Ci='Cinco:BAAALgADCgUJBQAAAA==.',
Cl='Clearly:BAAALgADCgQJAwAAAA==.Clessidra:BAAALgAECgIJAgAAAA==.',
Co='Cocytus:BAAALgAECgIJAwAAAA==.Colbith:BAAALgADCgkJDQAAAA==.Conquest:BAABLgAECn8WAAIKAAYJwRJhfAAqAQAKAAYJwRJhfAAqAQAAAA==.Cordaddy:BAABLgAECn8gAAIDAAgJmyUuCwDoAgADAAgJmyUuCwDoAgAAAA==.Cordragu:BAAALgAECggJEAABLgAECggJIAADAJslAA==.Corinthe:BAABLgAECn8VAAMJAAgJESYQAgBiAwAJAAgJESYQAgBiAwAKAAEJYQ8LLAE3AAABLgAECggJIAADAJslAA==.Corinthin:BAABLgAECn8uAAIOAAgJwhepIgDmAQAOAAgJwhepIgDmAQAAAA==.',
Cr='Crinn:BAABLgAECn8WAAQIAAkJDw81CQB1AQAIAAgJrAw1CQB1AQAWAAYJYwvYJwAAAQAaAAEJoQ71CQE6AAAAAA==.Crizmon:BAABLgAECn85AAIIAAgJYCM/AQD5AgAIAAgJYCM/AQD5AgAAAA==.Cryomancer:BAAALgADCgQJBAAAAA==.Crõwley:BAAALgADCgYJBgABLgAECggJHQAdAK0XAA==.',
Da='Damage:BAAALgAECgEJAQAAAA==.Damorax:BAAALgAECggJDwAAAA==.Darazarke:BAACLgAFFH8dAAIdAAYJrRJPCAC9AQAdAAYJrRJPCAC9AQAuAAQKfyMABB4ACAltHhAEANICAB4ACAltHhAEANICAB0ABwmTHK0OAE4CAB8AAQlwGIVdAEQAAAAA.Darkcursed:BAABLgAECn8mAAIgAAgJ5AvRUwBiAQAgAAgJ5AvRUwBiAQAAAA==.Darksudge:BAAALgAECgEJAQAAAA==.Darps:BAABLgAECn8WAAIRAAgJQhlIIwAGAgARAAgJQhlIIwAGAgABLgAECgkJIgAhAAEkAA==.Daybreak:BAAALgAECgcJEQAAAA==.Dayquil:BAECLgAFFH8GAAIKAAIJGwsGXgCWAAAKAAIJGwsGXgCWAAAuAAQKfykAAwoACAkXIIMaAGQCAAoACAkXIIMaAGQCAAkAAQnLGaxpAEEAAAAA.',
De='Deadaddie:BAABLgAECn8gAAMaAAgJgh8IIABFAgAaAAgJgh8IIABFAgAIAAYJZRfQDAAoAQAAAA==.Deamoneyes:BAAALgAFFAMJBAAAAA==.Deathbakerey:BAAALgADCgUJBQAAAA==.Decastamon:BAABLgAECn8VAAIEAAgJnAShkwAXAQAEAAgJnAShkwAXAQAAAA==.Delin:BAAALgAECgcJBwABLgAFFAYJHQAdAK0SAA==.Deluxdh:BAAALgAECgMJAwAAAA==.Demonslinger:BAAALgADCgUJBQAAAA==.Dendrel:BAAALgAECgMJAwAAAA==.Derpspally:BAAALgAECgEJAQAAAA==.Derpspunch:BAABLgAECn8hAAIYAAgJnBvsDABnAgAYAAgJnBvsDABnAgABLgAECgkJIgAhAAEkAA==.Destrox:BAAALgADCgYJBgAAAA==.Dezatra:BAAALgAECgQJBwAAAA==.Deíty:BAAALgADCgUJBgAAAA==.',
Di='Diane:BAEALgAECgYJBgAAAA==.Dieselcon:BAABLgAECn9AAAMSAAgJNhbFDQDpAQASAAgJNhbFDQDpAQAKAAEJswyfRAEyAAAAAA==.Dieseletta:BAAALgAECgMJAwAAAA==.Dinodruid:BAAALgAECgcJAwAAAA==.',
Do='Domdog:BAABLgAECn80AAIEAAkJcRZoKwAqAgAEAAkJcRZoKwAqAgAAAA==.Domína:BAAALgAECgEJAQAAAA==.Dontforget:BAABLgAECn8cAAMJAAcJuRS8LQBXAQAJAAYJKhS8LQBXAQAKAAcJoAN8wwCyAAAAAA==.Dookiesmash:BAABLgAECn8iAAIhAAkJASSzAQATAwAhAAkJASSzAQATAwAAAA==.Doomblast:BAAALgADCgIJAgAAAA==.Doomdealer:BAAALgAFFAEJAQAAAA==.Doomed:BAAALgADCgQJBAABLgAECggJGAAXADQdAA==.Doomrage:BAAALgADCgcJFAAAAA==.Doomsdead:BAAALgADCgcJBwAAAA==.Doomshock:BAAALgADCgYJBQAAAA==.',
Dr='Draftymonk:BAABLgAECn8kAAMXAAgJxSC7DAAtAgAXAAcJcCG7DAAtAgAZAAUJVRqNJgAtAQAAAA==.Drax:BAABLgAECn8hAAMiAAgJsAu8DgBFAQAgAAgJbwqUWQBSAQAiAAYJygq8DgBFAQAAAA==.Dreadgar:BAAALgAECgQJBAABLgAECggJFgAPADgbAA==.Dritzzfive:BAABLgAECn8XAAIaAAcJ4Aj3ggAUAQAaAAcJ4Aj3ggAUAQAAAA==.Dritzzwar:BAAALgAECgYJDAAAAA==.',
Ei='Eilica:BAAALgAECgUJBQAAAA==.',
Ek='Ekaine:BAAALgADCgQJBAABLgAECgYJGAAEAFgQAA==.',
El='Elandrus:BAAALgAECgUJCQABLgAECggJHQAdAK0XAA==.Elishiveth:BAAALgAECgYJDAAAAA==.Elleynre:BAAALgADCgQJBAAAAA==.Elliewilliam:BAAALgADCgQJBAAAAA==.Elrëim:BAAALgAECggJDgAAAA==.Elwendigo:BAAALgADCgMJAwAAAA==.Elwyna:BAAALgADCgIJAgAAAA==.',
Em='Emmara:BAABLgAECn8eAAITAAgJxQRaEwDlAAATAAgJxQRaEwDlAAAAAA==.',
En='Enhancement:BAAALgADCgcJDQABLgAFFAUJFQAPAAIlAA==.Enitar:BAAALgAECgUJCQABLgAECggJKgAbACshAA==.',
Er='Erata:BAAALgAECgYJEgAAAA==.Erlangshen:BAAALgADCgUJBQAAAA==.Erravis:BAAALgADCgcJDwAAAA==.',
Ev='Evarion:BAAALgADCgEJAQAAAA==.Eviaei:BAAALgAECgMJAwAAAA==.Evulise:BAAALgAECgEJAQAAAA==.Evullight:BAAALgAECgEJAQAAAA==.',
Ez='Ezalan:BAAALgADCgcJBwAAAA==.Ezlok:BAABLgAECn8WAAIPAAgJOBsFHwCVAQAPAAgJOBsFHwCVAQAAAA==.Ezorreodd:BAAALgADCgQJBAAAAA==.Ezzorreodd:BAAALgAECgUJDgAAAA==.',
Fa='Fae:BAABLgAECn8aAAMOAAgJ2BX9SgBWAQAOAAYJihH9SgBWAQAPAAYJ/BKCMwATAQABLgAECgYJGgAKAGQWAA==.Falcyon:BAAALgAECgMJAwAAAA==.Falerin:BAABLgAECn8YAAIDAAgJThFEQQBDAQADAAgJThFEQQBDAQAAAA==.Farenheit:BAABLgAECn8yAAQGAAkJChuiCQBwAgAGAAkJChuiCQBwAgADAAQJlQ0dowCDAAAjAAMJsBClMgBbAAAAAA==.Fatel:BAAALgAFFAEJAgABLgAFFAMJCAAWABEZAA==.Faydwer:BAAALgADCgMJBAAAAA==.Fayfox:BAAALgADCgkJFwAAAA==.',
Fe='Feenex:BAAALgAECgYJDgAAAA==.',
Fi='Fillorey:BAAALgADCgEJAQAAAA==.Finick:BAAALgAECgcJEQAAAA==.Firedealer:BAABLgAECn8fAAITAAgJgBVCCACvAQATAAgJgBVCCACvAQAAAA==.Firnen:BAABLgAECn8dAAIdAAgJrRcaGgC7AQAdAAgJrRcaGgC7AQAAAA==.',
Fl='Flahash:BAAALgAECgMJAwAAAA==.Flappy:BAAALgAECgcJDwABLgAECgkJKwAOALcgAA==.Flapster:BAAALgADCgkJFQABLgAECgkJKwAOALcgAA==.Flashmaster:BAAALgAECgYJCgAAAA==.Flawlessheal:BAAALgAECgEJCQAAAA==.Flora:BAAALgAECgYJCgABLgAECgYJGgAKAGQWAA==.Fluffybutt:BAAALgADCgkJFgAAAA==.',
Fo='Fossora:BAAALgAECgQJBwAAAA==.',
Fr='Frostmagi:BAAALgAECgYJDwABLgAFFAUJFQAPAAIlAA==.Frostybunny:BAAALgAECgMJBQAAAA==.Frozenharded:BAAALgAECgQJAwABLgAECgcJFQAOAAsZAA==.',
Fu='Furrbidden:BAAALgADCgQJBAAAAA==.Fusionve:BAAALgAECgUJBgAAAA==.',
Ga='Gaffershot:BAAALgADCgMJAwAAAA==.Gafferthicc:BAABLgAECn8cAAIbAAgJOBuwMQC1AQAbAAgJOBuwMQC1AQAAAA==.Gaffharir:BAAALgADCgUJBQAAAA==.Galvin:BAAALgADCgYJBgAAAA==.Garfeeld:BAAALgADCgcJCwABLgAECggJLgAOAMIXAA==.Garlicroast:BAAALgAECgMJBgAAAA==.Gayden:BAAALgAECgUJBgAAAA==.',
Ge='Gelatin:BAAALgADCgQJBQAAAA==.Gerry:BAABLgAECn8tAAIkAAkJvx6YBwBsAgAkAAkJvx6YBwBsAgAAAA==.Geyora:BAABLgAECn8cAAIkAAgJAB+SAwDvAgAkAAgJAB+SAwDvAgAAAA==.',
Gg='Ggkando:BAAALgAECgYJCgAAAA==.',
Gi='Gigguschadus:BAAALgADCgIJAgAAAA==.Gingerail:BAABLgAECn8VAAIOAAcJCxkTIwDkAQAOAAcJCxkTIwDkAQAAAA==.',
Gl='Glory:BAABLgAECn8aAAIWAAkJKRpGCgAZAgAWAAkJKRpGCgAZAgAAAA==.',
Gn='Gnotorious:BAAALgAECgMJAwAAAA==.',
Go='Goldi:BAAALgAECgEJAQAAAA==.Goochsquirts:BAABLgAECn8sAAMOAAkJ+xiHKADuAQAOAAkJ+xiHKADuAQAPAAEJ2ATDhQAiAAAAAA==.Gorrick:BAAALgAECgYJBgAAAA==.Gorriff:BAAALgAECgMJBAAAAA==.',
Gr='Graestrae:BAABLgAECn8fAAIaAAcJewV2kQD5AAAaAAcJewV2kQD5AAAAAA==.Gravedygger:BAABLgAECn80AAIRAAgJjBpFKADuAQARAAgJjBpFKADuAQAAAA==.Greenonions:BAAALgADCgIJAgAAAA==.Grenswood:BAACLgAFFH8VAAIlAAUJTCTMAQB9AQAlAAUJTCTMAQB9AQAuAAQKfzMAAiUACQlOJTQAAFQDACUACQlOJTQAAFQDAAAA.Grimmarius:BAAALgAFFAIJAgAAAA==.Grimmkin:BAAALgAECgUJCAAAAA==.Grimmyr:BAAALgADCgYJBgAAAA==.Grumbo:BAAALgAECgQJBwAAAA==.Gryff:BAAALgADCgcJBwAAAA==.',
Gu='Gunnerr:BAAALgAECgMJBAAAAA==.Guuldurak:BAAALgAECgQJBwAAAA==.',
Ha='Hanadan:BAAALgADCgcJBwAAAA==.Harrod:BAABLgAECn8cAAIEAAgJxAcUeQBIAQAEAAgJxAcUeQBIAQAAAA==.Hasew:BAABLgAECn8eAAIRAAcJnRv3MgC+AQARAAcJnRv3MgC+AQAAAA==.Haste:BAAALgAECgMJAwABLgAFFAMJCAAWABEZAA==.Hauken:BAAALgAECgMJAwABLgAFFAcJEgARALgbAA==.',
He='He:BAAALgAECgEJAQAAAA==.Heimlich:BAAALgAECgIJAwABLgAECggJHgAKAD4aAA==.Hellodoodle:BAAALgAECgMJAwAAAA==.Helpimßlind:BAABLgAECn8kAAIbAAcJMRgnSwDIAQAbAAcJMRgnSwDIAQAAAA==.Hera:BAACLgAFFH8PAAIRAAUJWCIkCwCDAQARAAUJWCIkCwCDAQAuAAQKfzEAAhEACAn0JUUCAHYDABEACAn0JUUCAHYDAAAA.Herry:BAABLgAECn8VAAIkAAcJLxuyDgD9AQAkAAcJLxuyDgD9AQABLgAECgkJLQAkAL8eAA==.Heyner:BAABLgAECn8xAAImAAgJ3heYBADjAQAmAAgJ3heYBADjAQAAAA==.',
Hi='Hille:BAAALgADCgEJAQAAAA==.Hinral:BAACLgAFFH8LAAIYAAUJ9x/wCADPAQAYAAUJ9x/wCADPAQAuAAQKfykAAhgACAnJJSkDAEsDABgACAnJJSkDAEsDAAAA.',
Ho='Hojira:BAAALgAECgUJBQAAAA==.Holyangus:BAAALgAECgUJDgAAAA==.Holybabe:BAAALgADCgEJAQAAAA==.Holysmacker:BAAALgAECgMJAwABLgAECgcJHQAEAAIaAA==.',
Hu='Hukkaru:BAAALgADCgYJDgAAAA==.',
['Hë']='Hëll:BAABLgAECn8hAAIgAAgJWhIJRwCHAQAgAAgJWhIJRwCHAQAAAA==.',
Ic='Iceblind:BAABLgAECn8UAAIbAAYJZAoZgQDJAAAbAAYJZAoZgQDJAAAAAA==.',
Il='Ilcanna:BAAALgADCgEJAQAAAA==.Illaynne:BAABLgAECn8uAAIBAAgJCx7nCwBcAgABAAgJCx7nCwBcAgAAAA==.Ilvasir:BAAALgADCgEJAQAAAA==.',
Im='Imani:BAACLgAFFH8JAAInAAQJAQdUBQAVAQAnAAQJAQdUBQAVAQAuAAQKfy4AAicACAk6FiQNAO4BACcACAk6FiQNAO4BAAAA.Immensepain:BAABLgAECn8mAAIEAAgJqRD/fADXAQAEAAgJqRD/fADXAQAAAA==.Imnotbalding:BAAALgAECgQJBwAAAA==.Imtrynacrack:BAAALgADCgQJBAAAAA==.Imurhucklbry:BAAALgADCgMJAwAAAA==.',
In='Inalee:BAAALgAECgcJEgAAAA==.Inoshikacho:BAABLgAECn8rAAIHAAgJPQtKEABMAQAHAAgJPQtKEABMAQAAAA==.Involio:BAAALgADCggJDQAAAA==.Invý:BAABLgAECn8nAAIKAAgJgRlENgDgAQAKAAgJgRlENgDgAQAAAA==.',
Ir='Irishdots:BAAALgADCgMJAwAAAA==.Irishkicks:BAAALgAECgEJAgAAAA==.Irishlife:BAAALgAECgQJBAAAAA==.Irishmecha:BAACLgAFFH8OAAIVAAUJjgTxAwAgAQAVAAUJjgTxAwAgAQAuAAQKfywAAhUACAlxGR4FAEQCABUACAlxGR4FAEQCAAAA.Irishtotems:BAAALgADCgQJBAAAAA==.Irishtraps:BAAALgADCgEJAQAAAA==.',
Is='Isandra:BAAALgADCgEJAQAAAA==.',
It='Itharillys:BAABLgAECn8nAAIRAAkJWQ7DLwDLAQARAAkJWQ7DLwDLAQAAAA==.',
Ja='Jaadu:BAAALgAECgIJAwAAAA==.',
Je='Jeennkiins:BAAALgADCggJFwABLgAECggJGQAEADYNAA==.Jessibella:BAABLgAECn8UAAMQAAcJsw6AJABMAQAQAAcJpwqAJABMAQABAAIJwRjuRgB2AAAAAA==.Jezzako:BAABLgAECn8YAAMRAAYJjgtlaAAvAQARAAUJtQ1laAAvAQAkAAYJGwSgGwAaAQAAAA==.',
Ji='Jinx:BAAALgAECgMJBAABLgAECgYJGgAKAGQWAA==.',
Jo='Johali:BAABLgAECn8fAAIMAAcJJwjQJwDQAAAMAAcJJwjQJwDQAAAAAA==.',
Ju='Justise:BAABLgAECn8WAAQhAAYJwRkDFADMAQAhAAYJ5xgDFADMAQALAAUJFBjPOgAKAQAMAAEJjQ4LRgAsAAAAAA==.Jutojerry:BAABLgAECn8YAAMXAAgJNB2gDQAfAgAXAAgJNB2gDQAfAgAYAAIJzhwVTQChAAAAAA==.',
['Jî']='Jîru:BAAALgADCgQJBAAAAA==.',
['Jö']='Jöhnblaze:BAABLgAECn8gAAQhAAgJ+hJdGgAWAQALAAcJiRIENQAlAQAhAAcJfA9dGgAWAQAMAAEJQwsaUgAuAAAAAA==.Jöker:BAAALgAECgUJBgAAAA==.',
Ka='Kaalya:BAAALgAECgQJBAAAAA==.Kaelus:BAAALgADCgEJAQAAAA==.Kahoona:BAAALgAECgUJDAAAAA==.Kailys:BAACLgAFFH8FAAISAAIJ9QQ6DQBQAAASAAIJ9QQ6DQBQAAAuAAQKfyUAAhIACAk4EdQQAF4BABIACAk4EdQQAF4BAAAA.Kaishias:BAABLgAECn8eAAIKAAgJfRiuPwAnAgAKAAgJfRiuPwAnAgAAAA==.Kamyra:BAABLgAECn8WAAIKAAcJVwu+mgD0AAAKAAcJVwu+mgD0AAAAAA==.Kandoh:BAAALgADCgUJBQABLgAECgYJCgAFAAAAAA==.Kanimeh:BAAALgADCgQJBAAAAA==.Kankuró:BAACLgAFFH8HAAIRAAMJ1w4lOADlAAARAAMJ1w4lOADlAAAuAAQKfzUAAxEACQl8IToKAMQCABEACQl8IToKAMQCABMAAQnIB2qOAC0AAAAA.',
Ke='Kedzen:BAAALgADCgcJGgABLgAECggJLgAOAMIXAA==.Kerfur:BAAALgAECgMJAwAAAA==.',
Ki='Killudead:BAAALgAECggJDwAAAA==.',
Ko='Kodetra:BAAALgAECgQJBAAAAA==.Kolgrim:BAABLgAECn8hAAMIAAgJehohDAA1AQAWAAcJYRrHHQBbAQAIAAYJBRMhDAA1AQAAAA==.Korimya:BAAALgAECgEJAgAAAA==.Korva:BAAALgAECgYJEwABLgAECgYJGAAEAFgQAA==.',
Kr='Krianthess:BAAALgAFFAEJAQAAAA==.Krissypoo:BAAALgAECgMJAwAAAA==.Kristie:BAABLgAECn8YAAIEAAYJWBCNugBsAQAEAAYJWBCNugBsAQAAAA==.Krom:BAABLgAECn8iAAIOAAgJ5A5EPwBOAQAOAAgJ5A5EPwBOAQAAAA==.',
Ku='Kuadonaran:BAAALgADCgEJAQABLgAECggJKAAiAPYhAA==.Kulitcomandr:BAAALgADCgUJBQAAAA==.Kupquake:BAACLgAFFH8NAAIZAAUJ6goyEAD/AAAZAAUJ6goyEAD/AAAuAAQKfy8AAhkACAmvH7cQAHYCABkACAmvH7cQAHYCAAAA.',
Ky='Kynris:BAAALgADCgMJAwABLgAECggJHQAdAK0XAA==.',
La='Laancelot:BAAALgADCgkJDgAAAA==.Lacy:BAAALgADCgEJAQAAAA==.Laetus:BAAALgAECgUJDQAAAA==.Lamort:BAABLgAECn8oAAQiAAgJ9iHlAwAFAgAgAAcJVx35PAAZAgAiAAcJ8yLlAwAFAgAlAAYJcxqZCwA3AQAAAA==.Lanaal:BAAALgADCgIJAgAAAA==.Lancewh:BAAALgADCgkJFwAAAA==.Launzi:BAAALgADCgkJDgAAAA==.Lavirna:BAAALgAECgEJAQABLgAECgYJGAAEAFgQAA==.Lazulli:BAAALgADCgMJAwAAAA==.',
Le='Leaila:BAAALgAECgYJEAAAAA==.Legg:BAAALgADCgEJAQAAAA==.Leonora:BAABLgAECn8hAAITAAkJhQ+ACQCQAQATAAkJhQ+ACQCQAQAAAA==.',
Li='Lightbreakk:BAAALgADCgkJDwABLgAECgUJBwAFAAAAAA==.Lindesong:BAAALgAECgEJAQABLgAFFAcJEgARALgbAA==.Lisondrel:BAAALgAECgUJBwAAAA==.',
Lo='Lockbone:BAAALgAECgMJAwAAAA==.Loops:BAABLgAECn8dAAIkAAgJlB8dCgA8AgAkAAgJlB8dCgA8AgAAAA==.Lorette:BAABLgAECn8eAAMBAAgJARjmLQCNAQABAAgJARjmLQCNAQACAAYJ+BxrHQCEAQAAAA==.Lovelychow:BAAALgADCgYJCQAAAA==.',
Lu='Luckynyx:BAAALgAECgUJBgAAAA==.Luuma:BAAALgAECgYJBgABLgAECgYJGgAKAGQWAA==.',
Lw='Lwinterheart:BAAALgADCgYJBgAAAA==.',
Ly='Ly:BAAALgADCgUJBQAAAA==.Lymriina:BAACLgAFFH8GAAIUAAMJaROkDQARAQAUAAMJaROkDQARAQAuAAQKfxwAAhQACAlsI5wHABYDABQACAlsI5wHABYDAAEuAAUUBwkSABEAuBsA.Lyr:BAAALgADCgcJBwAAAA==.',
Ma='Machotedan:BAABLgAECn8pAAIKAAgJGyDTHgBLAgAKAAgJGyDTHgBLAgAAAA==.Macmittens:BAAALgAECggJDwAAAA==.Magedude:BAAALgAECgIJAgAAAA==.Maliken:BAABLgAECn8fAAIaAAgJ7B34JQCkAgAaAAgJ7B34JQCkAgAAAA==.Mamadrag:BAABLgAECn8fAAQdAAgJQxlZDgCbAQAdAAcJkhhZDgCbAQAfAAMJXgblWABbAAAeAAIJ8AaOFwBYAAAAAA==.Mambø:BAAALgADCgYJBgAAAA==.Managua:BAAALgAECgIJBAAAAA==.Mandwa:BAAALgAECgYJBgABLgAECggJKgAbACshAA==.Mario:BAABLgAECn8dAAIEAAcJAhpuTQCwAQAEAAcJAhpuTQCwAQAAAA==.Masivewin:BAAALgAECgEJAQAAAA==.Mastashifta:BAAALgAECgMJCwAAAA==.Matryoshka:BAAALgAECgUJCgAAAA==.Mattsadler:BAAALgAECgEJAwAAAA==.Maverex:BAAALgAFFAEJAQAAAA==.Mavok:BAAALgAECgEJAQAAAA==.Maxxim:BAAALgAECgMJAwAAAA==.Mayihmpurleg:BAAALgAECgMJAwABLgAECgkJHwATAIAVAA==.',
Mc='Mcnugs:BAAALgAECgMJBQAAAA==.',
Me='Mechamonk:BAAALgADCgIJAgAAAA==.Merczdk:BAAALgADCgYJDAAAAA==.Merczpal:BAAALgAECgYJBgAAAA==.Meta:BAAALgAECgYJEQAAAA==.',
Mi='Mindfreeze:BAAALgADCgUJBQAAAA==.Minthara:BAAALgADCgYJDgAAAA==.Missdemon:BAAALgADCgUJBgAAAA==.Missikrissi:BAAALgADCgYJBwAAAA==.Missmorrigan:BAAALgAECgQJDAAAAA==.Missî:BAAALgAECgcJDAAAAA==.Mists:BAACLgAFFH8KAAIgAAUJ2hzuDgBnAQAgAAUJ2hzuDgBnAQAuAAQKfyQAAyAACAmIJOwLABsDACAACAmIJOwLABsDACUAAgmaHfZHAJcAAAAA.Miththrawndo:BAABLgAECn8jAAMWAAgJjxhHEgDnAQAWAAgJjxhHEgDnAQAIAAEJAAAyGwAIAAAAAA==.',
Ml='Ml:BAABLgAECn8UAAMlAAYJVh4HCwAPAgAlAAYJVh4HCwAPAgAgAAQJJg9tjgDfAAAAAA==.',
Mo='Moldevort:BAAALgAECgMJCgAAAA==.Momjeans:BAABLgAECn8mAAMNAAgJQx+cAQCzAgANAAcJjSGcAQCzAgAEAAYJQxYZfQBAAQAAAA==.Monfanth:BAAALgAECgEJAQABLgAECgYJGAAEAFgQAA==.Morningumbra:BAAALgADCgIJAgAAAA==.',
Ms='Mstryoda:BAAALgADCgUJCAAAAA==.',
Mu='Muramasa:BAAALgAECgIJAwABLgAECgcJJQAZAM0fAA==.',
My='Myfriendtold:BAAALgADCgEJAgAAAA==.Mythunsarian:BAABLgAECn8wAAIoAAkJXBLQDQDkAQAoAAkJXBLQDQDkAQAAAA==.',
['Mä']='Mäylä:BAABLgAECn8mAAIDAAkJUw+JKgC6AQADAAkJUw+JKgC6AQAAAA==.',
['Mí']='Míst:BAABLgAECn8yAAIKAAgJ3RgWNADoAQAKAAgJ3RgWNADoAQAAAA==.',
Na='Nazaline:BAAALgADCgIJAgAAAA==.',
Ne='Necrohealiac:BAAALgAECgQJCQAAAA==.Necromerc:BAAALgAECgQJBAAAAA==.Necrotizer:BAAALgADCgMJAwAAAA==.Nephie:BAABLgAECn8hAAIoAAgJzxx1EgBGAgAoAAgJzxx1EgBGAgAAAA==.Netazia:BAAALgADCgcJGQAAAA==.Nethralfus:BAAALgAECgEJAQAAAA==.Nezqk:BAACLgAFFH8LAAQaAAUJZQQkWAD/AAAaAAQJZQQkWAD/AAAIAAQJkgF/CQDSAAAWAAEJAAAFPQAAAAAuAAQKfyUAAxoACAmnFhhdANsBABoACAnXFRhdANsBAAgAAgl/HG4dAE8AAAAA.',
Ni='Niano:BAAALgAECgEJAQAAAA==.',
Nm='Nmnenthe:BAAALgAECgcJDQAAAA==.',
No='Noelytv:BAAALgADCgcJBwAAAA==.Norman:BAAALgADCgEJAgAAAA==.November:BAAALgADCgEJAQAAAA==.Noxren:BAAALgAFFAEJAgAAAA==.',
['Nî']='Nîstø:BAABLgAECn8hAAQSAAgJFRdtDgDeAQASAAcJzBhtDgDeAQAJAAYJIxwgIAC3AQAKAAQJBQrqCQFQAAAAAA==.',
Ob='Obin:BAABLgAECn8iAAILAAkJ0hWTHQCzAQALAAkJ0hWTHQCzAQAAAA==.',
Oh='Oharachloe:BAAALgADCgYJBgAAAA==.',
Ol='Ollenbock:BAAALgADCgQJBAABLgAFFAcJEgARALgbAA==.',
Or='Orhanu:BAAALgAECgcJCAAAAA==.',
Ou='Outbbreakk:BAAALgAECgUJBwAAAA==.',
Ow='Owendriel:BAABLgAECn8XAAIbAAgJURhsOwAGAgAbAAgJURhsOwAGAgAAAA==.',
Pa='Padocus:BAAALgADCgUJBwAAAA==.Pajamas:BAABLgAECn8zAAIRAAkJrR3rCgDuAgARAAkJrR3rCgDuAgAAAA==.Palyamorous:BAAALgADCgUJBQAAAA==.Pandress:BAABLgAECn8eAAIRAAcJDheZQACKAQARAAcJDheZQACKAQAAAA==.Pankake:BAAALgAECgEJAQABLgAECggJJwAXADYfAA==.Paralysis:BAAALgAECgYJDQABLgAFFAUJDQAZAOoKAA==.',
Pe='Peryite:BAABLgAECn8nAAMQAAgJGhaJDwAgAgAQAAgJGhaJDwAgAgABAAYJrwolRwAdAQAAAA==.',
Ph='Phelris:BAAALgAECgYJDQAAAA==.',
Pi='Pillpusher:BAAALgAECgMJBAAAAA==.Pisscat:BAAALgAECgUJCgAAAA==.',
Po='Polymerase:BAAALgAECgEJAQABLgAECggJKgAaAOAgAA==.',
Pr='Prideindeath:BAAALgAECgUJBQAAAA==.Promiscuity:BAAALgAECggJEwAAAA==.Protròast:BAAALgAECgQJBQAAAA==.Prængle:BAABLgAECn8UAAIYAAYJ6RYSJAB6AQAYAAYJ6RYSJAB6AQAAAA==.',
Ps='Psoas:BAAALgAECgYJBgABLgAECggJLgAeAMoeAA==.Psypriest:BAABLgAFFH8JAAIBAAQJKxlLDAApAQABAAQJKxlLDAApAQABLgAFFAYJJQABAJYdAA==.',
Pu='Pulverine:BAAALgADCgcJDgAAAA==.',
Qu='Quarantinia:BAAALgADCgEJAQAAAA==.',
Ra='Rabbi:BAABLgAECn8ZAAMCAAcJPBdwGwCVAQACAAcJPBdwGwCVAQABAAUJaA7TTgD9AAAAAA==.Ragerunnerx:BAAALgAECggJDwAAAA==.Rahfna:BAAALgAECgEJAQAAAA==.Rakan:BAAALgADCgIJAgAAAA==.Raynare:BAAALgAECgIJAwAAAA==.',
Re='Redall:BAABLgAECn8eAAITAAcJVQxuDwAbAQATAAcJVQxuDwAbAQAAAA==.Reesespbc:BAABLgAECn8wAAIEAAkJtw95PwDcAQAEAAkJtw95PwDcAQAAAA==.Reina:BAABLgAECn8aAAIKAAYJZBbEdAA4AQAKAAYJZBbEdAA4AQAAAA==.Reinir:BAABLgAECn8oAAIhAAgJayNhBACeAgAhAAgJayNhBACeAgAAAA==.Reinz:BAAALgAECggJDQAAAA==.Rektagar:BAABLgAECn8oAAMPAAkJZSMaCQCHAgAPAAgJHyMaCQCHAgAOAAQJSh3HPwBMAQABLgAFFAcJEgARALgbAA==.Ressandra:BAAALgADCgcJBwAAAA==.Reyvanna:BAAALgADCgEJAQAAAA==.',
Ro='Roar:BAAALgAECgUJBQABLgAECgYJFgAEANgVAA==.Robert:BAAALgADCgEJAQAAAA==.Rosavyra:BAAALgAECggJCQAAAA==.Roshara:BAAALgAECgQJCgAAAA==.',
Ry='Ryanbutscaly:BAAALgADCgMJAwABLgAECgcJFQAEABYSAA==.Ryce:BAAALgAECgQJBAABLgAECggJJwAXADYfAA==.Ryoka:BAAALgAECgIJAgAAAA==.',
['Rö']='Rös:BAACLgAFFH8NAAIEAAUJThzRKABlAQAEAAUJThzRKABlAQAuAAQKfzMAAwQACAljHxwdAHICAAQACAljHxwdAHICACkAAQlfINwMAF0AAAAA.',
['Rü']='Rübblë:BAAALgAECgQJBAAAAA==.',
Sa='Saberie:BAAALgAECgQJBwAAAA==.Salamun:BAAALgAECgQJBQAAAA==.Salaria:BAABLgAECn8iAAIbAAgJrgmNXgAbAQAbAAgJrgmNXgAbAQAAAA==.Salen:BAABLgAECn8xAAMnAAgJ2hiuBwDuAQAnAAgJ2hiuBwDuAQAOAAQJoQV6dQCFAAAAAA==.Salina:BAEBLgAECn8oAAIcAAkJFRZOBwC5AQAcAAkJFRZOBwC5AQAAAA==.Sandraia:BAABLgAECn8kAAIaAAgJtxtyOwDNAQAaAAgJtxtyOwDNAQAAAA==.Sandstique:BAABLgAECn8WAAIOAAkJpyFqCADvAgAOAAkJpyFqCADvAgAAAA==.Sandtwig:BAAALgADCgEJAQAAAA==.Sandweaver:BAAALgADCgEJAQAAAA==.Sanjira:BAABLgAECn8bAAImAAgJ8gdqCQA6AQAmAAgJ8gdqCQA6AQAAAA==.Sarusuby:BAABLgAECn8kAAIjAAcJYRdzDQCvAQAjAAcJYRdzDQCvAQAAAA==.',
Sc='Schuffles:BAAALgAECgEJAQAAAA==.Scottyfist:BAABLgAECn8YAAIXAAgJfB96FgBVAgAXAAgJfB96FgBVAgAAAA==.Scottymac:BAAALgADCgYJBgABLgAECgkJGAAXAHwfAA==.',
Se='Sealion:BAACLgAFFH8JAAMJAAMJVyCeEQDDAAAJAAIJQB2eEQDDAAAKAAIJlAulXACZAAAuAAQKfxoAAwkACQmUF2AWAF4CAAkACQmUF2AWAF4CAAoAAwltI3K4AMMAAAAA.Seetah:BAABLgAECn8hAAIBAAgJZiJtBQDlAgABAAgJZiJtBQDlAgAAAA==.Seetur:BAAALgAECgQJBAAAAA==.Serratus:BAABLgAECn8uAAQeAAgJyh7AAwAPAgAeAAgJqBvAAwAPAgAfAAgJixr7EgD7AQAdAAEJTgThMAAsAAAAAA==.Setcher:BAAALgADCgEJAQAAAA==.',
Sh='Shadaddy:BAAALgAFFAIJAgABLgAECggJIAAaAIIfAA==.Shadoweyes:BAAALgAECgcJCgAAAA==.Shadowsyther:BAAALgAECgYJBgAAAA==.Shamax:BAAALgADCgEJAgABLgADCgUJBQAFAAAAAA==.Shamommy:BAAALgAECgQJBwAAAA==.Shayes:BAABLgAECn8jAAIjAAgJbx7NBQBOAgAjAAgJbx7NBQBOAgAAAA==.Shifue:BAAALgAECgMJBAAAAA==.Shimmerstar:BAABLgAECn8eAAIKAAkJmRqnFgB9AgAKAAkJmRqnFgB9AgAAAA==.',
Si='Sigg:BAAALgAECgUJBQAAAA==.Silexe:BAAALgAECgUJBwABLgAECggJKAAiAPYhAA==.Sitar:BAAALgAECgEJAQABLgAECggJKgAbACshAA==.',
Sk='Skathae:BAAALgAECgEJAQABLgAECggJHQAdAK0XAA==.Skåld:BAABLgAECn8fAAIaAAgJThhmQAC8AQAaAAgJThhmQAC8AQAAAA==.',
Sl='Slipperyboi:BAAALgAECgYJBgAAAA==.',
Sn='Snuffles:BAABLgAECn8cAAIkAAgJ2Bo9EwDGAQAkAAgJ2Bo9EwDGAQAAAA==.Snugs:BAAALgADCgEJAQAAAA==.',
So='Soldraca:BAAALgAECgMJCQAAAA==.Soulence:BAAALgAECgMJBAAAAA==.Soymaster:BAAALgADCgYJBgABLgAECggJFgAPADgbAA==.',
St='Stinkbug:BAAALgADCgUJBgAAAA==.Stutters:BAABLgAECn8qAAMaAAgJ4CDoGABuAgAaAAgJ4CDoGABuAgAWAAUJIBgpIABDAQAAAA==.',
Su='Sudachi:BAACLgAFFH8GAAIMAAMJUhHJEQDdAAAMAAMJUhHJEQDdAAAuAAQKfxUAAwwACQmPGo0EAKMCAAwACQmPGo0EAKMCAAsAAgkDDViUAG4AAAEuAAUUBQkJABkAqxwA.Sunnyräy:BAAALgADCgcJDQAAAA==.',
Sw='Swineflu:BAAALgAECgMJAwAAAA==.Swizzjenks:BAAALgADCgMJAwAAAA==.',
Sy='Synonym:BAAALgADCgcJBwAAAA==.Syrprize:BAAALgADCgEJAQABLgAECggJGAAXADQdAA==.',
['Sý']='Sýndrá:BAABLgAECn8hAAIlAAgJPiFrAQCQAgAlAAgJPiFrAQCQAgAAAA==.',
Ta='Tacobob:BAACLgAFFH8LAAIDAAQJBgb6JQDkAAADAAQJBgb6JQDkAAAuAAQKfy4AAgMACAlwFm83AMkBAAMACAlwFm83AMkBAAAA.Taethron:BAAALgADCgUJBQAAAA==.Taffeta:BAAALgADCgEJAQAAAA==.Taffyboy:BAAALgADCggJCgAAAA==.Talysiah:BAAALgAECgcJEwAAAA==.Tannir:BAAALgAECgEJAQAAAA==.Tarogen:BAAALgADCgQJBgABLgAFFAUJCwAYAPcfAA==.Tavok:BAABLgAECn8rAAMLAAgJbiNdCACYAgALAAgJbiNdCACYAgAhAAEJ+BUGRAA9AAAAAA==.',
Te='Tenacious:BAAALgADCgcJDAAAAA==.Tene:BAAALgADCgMJAwAAAA==.Teratots:BAAALgADCgYJBgAAAA==.Testament:BAAALgADCgcJCAAAAA==.',
Th='Thenna:BAAALgAECgMJAwAAAA==.Theosclaws:BAAALgADCgcJDgAAAA==.Theramier:BAAALgADCgIJAgAAAA==.Thiux:BAABLgAECn8VAAMgAAgJWxzgJQAJAgAgAAcJWxzgJQAJAgAlAAEJAAByXQBWAAAAAA==.Thotsnprayrs:BAAALgADCgUJCAABLgAECggJGAAXADQdAA==.Thourin:BAAALgADCgEJAQAAAA==.Thrappy:BAABLgAECn8rAAIOAAkJtyB7BQATAwAOAAkJtyB7BQATAwAAAA==.Thráwñ:BAAALgAECgIJAwABLgAECgYJCgAFAAAAAA==.',
Ti='Tiddyhammer:BAABLgAECn8gAAMKAAgJnRu9KQASAgAKAAcJnRu9KQASAgAJAAcJNBRlRQBiAQAAAA==.Tintaglia:BAAALgAECgYJBwABLgAECgcJHQAEAAIaAA==.Tirtun:BAABLgAECn8mAAIEAAgJDh9PKQAzAgAEAAgJDh9PKQAzAgAAAA==.',
To='Tomek:BAABLgAECn8qAAMkAAkJGRxICABfAgAkAAkJ8BhICABfAgATAAcJyh8mCQCYAQAAAA==.Totemetot:BAAALgAECgQJDAAAAA==.',
Tr='Treemourne:BAAALgADCgEJAQAAAA==.Triggeer:BAABLgAECn8zAAIhAAkJxBYCDQDMAQAhAAkJxBYCDQDMAQAAAA==.',
Tu='Tully:BAAALgADCgEJAQAAAA==.Turalus:BAAALgADCgYJBgAAAA==.Turina:BAABLgAECn8UAAIgAAYJxwJIsQCcAAAgAAYJxwJIsQCcAAAAAA==.',
Tw='Twelvekill:BAACLgAFFH8NAAIRAAUJTwq2JgAiAQARAAUJTwq2JgAiAQAuAAQKfy4AAhEACAmEGiYaAGsCABEACAmEGiYaAGsCAAAA.',
Ty='Tyliaa:BAAALgAECggJEgABLgAECggJHwAdAEMZAA==.Tylidus:BAAALgAECgUJCQAAAA==.Tyranny:BAAALgAECgYJEgAAAA==.',
Ub='Ubisami:BAABLgAECn8YAAIIAAgJmAkUCwASAQAIAAgJmAkUCwASAQAAAA==.',
Ud='Udderfailure:BAAALgADCgIJAgAAAA==.',
Ul='Ullur:BAAALgADCgEJAgAAAA==.Ultramon:BAABLgAECn8iAAIKAAgJow40XQBtAQAKAAgJow40XQBtAQAAAA==.Uly:BAAALgAECgYJDQAAAA==.',
Un='Unwell:BAAALgAECgUJCgABLgAECgcJDgAFAAAAAA==.',
Ur='Urgoochness:BAABLgAECn8hAAIDAAgJshahJgDTAQADAAgJshahJgDTAQAAAA==.Urikhai:BAAALgAECgQJBQAAAA==.',
Va='Vaellvoid:BAAALgAECgMJAwAAAA==.Vainglorious:BAAALgAECgQJDgABLgAECgkJGgAWACkaAA==.Valanora:BAABLgAECn8iAAIiAAgJdRqjAwBbAgAiAAgJdRqjAwBbAgAAAA==.Valdis:BAAALgADCgcJDgABLgAECgYJGAAEAFgQAA==.Valinaxius:BAAALgAECgQJEgAAAA==.Valphalk:BAAALgADCggJCQAAAA==.Vanastasia:BAAALgAECgQJBgAAAA==.Vanyr:BAAALgADCgkJCQAAAA==.Vapturov:BAAALgAECgQJCwAAAA==.',
Ve='Veeks:BAAALgAECgcJDwAAAA==.Velikirn:BAABLgAECn8zAAMZAAgJGiKbCAB0AgAZAAgJ/CGbCAB0AgAXAAcJZhi5GgCTAQAAAA==.Vellwinnalas:BAAALgADCgUJCAAAAA==.Verah:BAAALgADCgYJBgAAAA==.Versø:BAABLgAECn8mAAQVAAcJOBvvBgD9AQAVAAYJSBvvBgD9AQAmAAcJmxZDBwB/AQAUAAQJ1hmHPgAoAQAAAA==.',
Vi='Villageinn:BAAALgAECgMJAwAAAA==.Vine:BAAALgAECgYJEAAAAA==.Vixxon:BAABLgAECn8lAAIRAAgJSRm+KADrAQARAAgJSRm+KADrAQAAAA==.',
Vl='Vly:BAABLgAECn8VAAMVAAgJtgjcDgD0AAAVAAYJmwncDgD0AAAUAAgJugZ3KwDgAAAAAA==.Vlyrae:BAAALgAECgEJAgABLgAECggJFQAVALYIAA==.Vlysham:BAAALgAECgEJAQABLgAECggJFQAVALYIAA==.Vlyzen:BAAALgAECgQJBQABLgAECggJFQAVALYIAA==.',
Vo='Voidhearted:BAABLgAECn8yAAICAAgJ2h5NCwBPAgACAAgJ2h5NCwBPAgAAAA==.',
Vu='Vulpy:BAAALgAECgEJAQABLgAECgcJEQAFAAAAAA==.',
['Vì']='Vìolet:BAAALgAECgYJEgABLgAECggJKAAGADwiAA==.',
['Ví']='Víolet:BAAALgADCgEJAQAAAA==.',
Wa='Waggleton:BAAALgAECgEJAgAAAA==.Warp:BAAALgADCgEJAQAAAA==.Washyourasz:BAAALgAECgQJBAAAAA==.Wasted:BAAALgADCgEJAQABLgAECgkJKwAOALcgAA==.Wayshua:BAAALgAECgUJBwAAAA==.',
We='Wearyouout:BAAALgADCgUJBQAAAA==.Wemon:BAAALgAECgUJBQAAAA==.Werkajerk:BAABLgAECn8hAAMXAAgJPyEOEQD0AQAXAAgJPyEOEQD0AQAZAAEJwBdFdABEAAABLgAFFAUJFQAPAAIlAA==.Werkjathal:BAACLgAFFH8VAAQPAAUJAiVlAwC1AQAPAAQJAiVlAwC1AQAnAAUJeSNqAQCXAQAOAAIJhweqGwCKAAAuAAQKfzMABCcACQnGJVkAAFMDACcACQkOJFkAAFMDAA8ACAkhIxkOAMICAA4ABwnDI4oNAK8CAAAA.Wetribs:BAAALgADCgkJCQAAAA==.',
Wh='Whereareyou:BAAALgADCgkJCQABLgAECgYJFgARAPoYAA==.Whitedog:BAAALgAECgEJAQAAAA==.Whitetank:BAABLgAECn8gAAISAAgJBRlNDACqAQASAAgJBRlNDACqAQAAAA==.',
Wi='Willowbeard:BAAALgAECgQJBwAAAA==.Winnelepooh:BAAALgADCgQJBAAAAA==.Winnithebrew:BAAALgAECgEJAQAAAA==.',
Wo='Wobys:BAABLgAECn8dAAIYAAgJWRTKIwB8AQAYAAgJWRTKIwB8AQAAAA==.Wolfblitzer:BAABLgAECn8kAAIKAAgJKRmyTAD8AQAKAAgJKRmyTAD8AQAAAA==.Wolfmanbro:BAAALgADCggJCAAAAA==.Worldbane:BAABLgAECn8lAAIlAAgJlhM6BwCTAQAlAAgJlhM6BwCTAQAAAA==.',
['Wä']='Wärchild:BAAALgAECgQJBAAAAA==.',
Xa='Xalaa:BAAALgAECgYJCgAAAA==.Xalataxfraud:BAAALgAECgQJBAAAAA==.Xanthos:BAAALgAECgMJBwAAAA==.',
Xe='Xenthriel:BAAALgADCgcJDQAAAA==.',
Xi='Xianyu:BAAALgAECgYJEgAAAA==.Ximmer:BAAALgAECgEJAQAAAA==.',
Xr='Xrispy:BAAALgAECgQJBwABLgAECgkJKwAOALcgAA==.',
Ya='Yarian:BAAALgAECgMJAwAAAA==.',
Yo='Yormin:BAAALgAECgUJEQAAAA==.Yorra:BAAALgAECgIJAgAAAA==.',
Yu='Yuzuu:BAABLgAECn8fAAIOAAcJsA2bTgAQAQAOAAcJsA2bTgAQAQAAAA==.',
Za='Zachhunter:BAABLgAFFH8SAAMRAAcJuBuCBQCvAQARAAUJahyCBQCvAQATAAYJJBF5CQBPAQAAAA==.Zan:BAACLgAFFH8OAAMPAAUJ2wuqGgD+AAAPAAUJ2wuqGgD+AAAOAAIJ4hAuGQCXAAAuAAQKfy4AAw8ACAmZH6wTAIICAA8ACAmZH6wTAIICAA4AAgmgC8OJAG0AAAAA.',
Zo='Zohaan:BAAALgADCgEJAwAAAA==.Zoma:BAAALgADCggJDgAAAA==.',
Zu='Zuhura:BAAALgAECgUJCwAAAA==.Zultrix:BAAALgAECgMJCAAAAA==.',
Zy='Zylaeri:BAAALgAECgkJDwAAAA==.',
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
