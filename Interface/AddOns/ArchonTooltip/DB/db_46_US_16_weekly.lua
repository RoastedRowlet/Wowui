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

local lookup = {'Priest-Holy','Priest-Shadow','Druid-Restoration','Mage-Frost','DemonHunter-Devourer','DeathKnight-Unholy','Unknown-Unknown','Druid-Balance','Druid-Guardian','Druid-Feral','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Priest-Discipline','Hunter-BeastMastery','Paladin-Protection','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Blood','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Warlock-Affliction','Hunter-Survival','Warlock-Destruction','Rogue-Outlaw','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Arathor',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aange:BAAALgADCgYJBgAAAA==.',
Ab='Absoul:BAACLgAFFH8OAAIBAAMJhB7rEgABAQABAAMJhB7rEgABAQAuAAQKfy4AAwEACQkSIggDAEsDAAEACQkSIggDAEsDAAIAAQlxA/doACYAAAAA.',
Ac='Acedia:BAABLgAECn80AAIBAAkJkhY0EQA0AgABAAkJkhY0EQA0AgAAAA==.',
Ad='Adellas:BAACLgAFFH8GAAIDAAMJ+xJkLgDYAAADAAMJ+xJkLgDYAAAuAAQKfygAAgMACAmOIY0LAOgCAAMACAmOIY0LAOgCAAAA.Adern:BAACLgAFFH8GAAICAAMJ2RyQFwAKAQACAAMJ2RyQFwAKAQAuAAQKfyYAAgIACQktHPQQACsCAAIACQktHPQQACsCAAAA.Adon:BAACLgAFFH8GAAIEAAMJAA+PZgDoAAAEAAMJAA+PZgDoAAAuAAQKfycAAgQACQn9GmUtAEYCAAQACQn9GmUtAEYCAAAA.Adondruel:BAAALgAECgEJAQAAAA==.',
Ae='Aelali:BAAALgAECgQJBwAAAA==.Aelith:BAABLgAECn8UAAIFAAcJ0RkAYQBCAQAFAAcJ0RkAYQBCAQAAAA==.',
Af='Afador:BAAALgAECgUJCAABLgAECgkJKwAGAMgUAA==.',
Ag='Ageling:BAAALgADCgYJCgAAAA==.',
Ai='Aidara:BAAALgADCgcJBwABLgAECgYJCgAHAAAAAA==.',
Ak='Akeno:BAAALgAECgMJAwABLgAECgIJAwAHAAAAAA==.Akrom:BAAALgADCgEJAgAAAA==.',
Al='Aladestar:BAACLgAFFH8PAAMDAAUJrg41GwBIAQADAAUJrg41GwBIAQAIAAMJrArqJgDEAAAuAAQKfygAAwMACAnKGqwbAF4CAAMACAnKGqwbAF4CAAgACAkcIRciAOwBAAAA.Albinodargon:BAAALgAECggJEwAAAA==.Alderleise:BAABLgAECn8cAAUDAAgJYAp4UwAfAQADAAgJYAp4UwAfAQAJAAMJMgkMPwBgAAAIAAIJchUYcQA8AAAKAAEJlghZPwAuAAAAAA==.Alecc:BAAALgAECgcJEQAAAA==.Alecw:BAAALgAECgQJCAAAAA==.Alexein:BAACLgAFFH8NAAILAAUJnARKCwD5AAALAAUJnARKCwD5AAAuAAQKfygAAgsACAmxFg8FAPYBAAsACAmxFg8FAPYBAAAA.Alienspace:BAAALgADCgEJAQAAAA==.Allila:BAAALgAECgEJAQAAAA==.',
Am='Amets:BAABLgAECn8zAAMMAAkJlCMzAQCdAwAMAAkJlCMzAQCdAwANAAUJXxk2mgAgAQAAAA==.Amydh:BAAALgAECgMJCwAAAA==.',
An='Anabel:BAAALgADCgkJFAAAAA==.Anamii:BAAALgADCgEJAQAAAA==.Andorsi:BAAALgAECgYJCAAAAA==.Anglechow:BAAALgADCgUJBQAAAA==.',
Ar='Arachne:BAABLgAECn8eAAICAAcJRAqvNQA+AQACAAcJRAqvNQA+AQAAAA==.Aranax:BAAALgADCgEJAgAAAA==.Arce:BAAALgAECgUJEAAAAA==.Architeleaf:BAAALgADCgMJAwABLgAECgMJAwAHAAAAAA==.Areafiftymoo:BAABLgAECn87AAMOAAkJiRAuJwCbAQAOAAkJJQwuJwCbAQAPAAYJRxFMIgAkAQAAAA==.Arthurleywin:BAAALgADCgIJAgAAAA==.Arysia:BAABLgAECn8YAAMEAAkJ3g8ZSwDeAQAEAAkJ3g8ZSwDeAQAQAAMJsw4BEgCkAAAAAA==.Aryya:BAABLgAECn9FAAMKAAgJ2yM2AwDBAgAKAAgJ2yM2AwDBAgAIAAMJHAfBZwCCAAAAAA==.',
As='Astralbreak:BAAALgADCgQJBQABLgAECgUJBwAHAAAAAA==.',
At='Athelia:BAAALgADCgEJAQAAAA==.',
Au='Aulaes:BAAALgADCgIJAgAAAA==.',
Av='Avalan:BAABLgAECn87AAIOAAkJ9SH1BgDTAgAOAAkJ9SH1BgDTAgAAAA==.Avanolatwo:BAAALgAECgMJAwABLgAFFAMJBgARAKoSAA==.Avashammy:BAACLgAFFH8GAAIRAAMJqhL0NgDQAAARAAMJqhL0NgDQAAAuAAQKfycAAxEACQmKHdkZAE8CABEACQmKHdkZAE8CABIAAQlxCK+WACQAAAAA.Avesia:BAABLgAECn8aAAITAAYJUhaeIgB/AQATAAYJUhaeIgB/AQAAAA==.Avhunt:BAAALgAECgMJAwABLgAECgkJOwAOAPUhAA==.Aviendah:BAABLgAECn8nAAIUAAkJ6BImMgDqAQAUAAkJ6BImMgDqAQAAAA==.',
Aw='Awsomeonet:BAABLgAECn8bAAMVAAgJMRgHFABdAQAVAAgJMRgHFABdAQANAAIJPwQZKAFQAAAAAA==.',
Ay='Ayot:BAAALgAECgcJEwAAAA==.',
Az='Azdfghop:BAACLgAFFH8dAAMUAAcJ8B+/EgB2AQAUAAUJCiS/EgB2AQAWAAYJCBj+DABEAQAuAAQKfyAAAxYACQm4IjIPAMcCABYACAnIHjIPAMcCABQACAmbIZM/ALEBAAAA.Azzinotica:BAAALgAECgEJAQAAAA==.',
Ba='Babeshot:BAABLgAECn8pAAIUAAgJpxYrOwDIAQAUAAgJpxYrOwDIAQAAAA==.Babezila:BAAALgAECgYJEgAAAA==.Badshahprime:BAABLgAECn8eAAINAAgJPhpjKgB7AgANAAgJPhpjKgB7AgAAAA==.Barbiegrill:BAABLgAECn8dAAMXAAgJ7x7+DwCmAgAXAAgJEB7+DwCmAgAYAAUJVRxACQCuAQABLgAFFAMJCgAZACgdAA==.Barleb:BAAALgAECgEJAQAAAA==.Battlemaker:BAAALgADCgcJBwABLgAECggJNwARAK4YAA==.Baykin:BAABLgAECn8pAAIaAAkJtSBJBQDRAgAaAAkJtSBJBQDRAgAAAA==.',
Bb='Bbeastt:BAAALgADCgEJAgAAAA==.',
Be='Beefyfivelyr:BAAALgADCgcJBwAAAA==.Beldinnara:BAAALgAECgEJAQAAAA==.Berandas:BAABLgAECn8UAAMbAAcJ/hEGJgCDAQAbAAcJ/hEGJgCDAQAcAAUJjg0SRQDAAAAAAA==.Bereessielin:BAAALgAECgQJBgAAAA==.Bergur:BAAALgAECgQJBAAAAA==.Berkowitz:BAABLgAECn8ZAAIXAAgJXxs2DwAUAgAXAAgJXxs2DwAUAgAAAA==.Beyy:BAAALgADCgcJBwABLgAECgYJEAAHAAAAAA==.',
Bi='Bigbear:BAAALgADCgEJAQABLgADCgMJAwAHAAAAAA==.',
Bl='Blaaze:BAAALgAECgQJBgAAAA==.Blackfrost:BAABLgAECn8VAAIEAAcJhBN9eABqAQAEAAcJhBN9eABqAQAAAA==.Blaiddyd:BAABLgAECn8uAAIUAAgJVCBEHgBHAgAUAAgJVCBEHgBHAgAAAA==.Blead:BAACLgAFFH8KAAMZAAMJKB2BFgD1AAAZAAMJKB2BFgD1AAAGAAEJtgXE1gBCAAAuAAQKfxYABBkACAkIHpAMABQCABkACAkIHpAMABQCAAsAAgnbFZ4gAHEAAAYAAgl9FfwtATkAAAAA.Blinkerr:BAAALgADCgkJDAAAAA==.Bluefarm:BAAALgADCgQJBAAAAA==.',
Br='Brahot:BAAALgAECgEJAQAAAA==.Brain:BAAALgAECgQJAwAAAA==.Brandawn:BAAALgADCgYJBgAAAA==.Branwarden:BAABLgAECn8bAAMOAAYJFQzrTgDiAAAOAAYJTgnrTgDiAAAdAAIJUQ6jPABXAAAAAA==.Brewsle:BAAALgAECgEJAQAAAA==.Brigantia:BAAALgADCgYJCgAAAA==.',
Bu='Bubblebot:BAAALgAECgMJAwABLgAECgkJMwAFABkgAA==.Bullchitz:BAABLgAECn8WAAIUAAYJ+hibQwChAQAUAAYJ+hibQwChAQAAAA==.Bullchitza:BAAALgADCgcJBwABLgAECgYJFgAUAPoYAA==.Burningooch:BAAALgADCgEJAQAAAA==.',
['Bã']='Bãyy:BAAALgAECgYJEAAAAA==.',
['Bæ']='Bæyy:BAAALgADCgUJCgABLgAECgYJEAAHAAAAAA==.',
Ca='Calador:BAAALgAECggJEgAAAA==.Capybara:BAAALgAECgcJDAAAAA==.Caster:BAAALgADCgQJBAAAAA==.Cathbad:BAAALgADCgEJAQAAAA==.Caylynn:BAAALgAECgUJBQAAAA==.',
Ce='Celyne:BAABLgAECn8zAAQFAAkJGSB/EgCRAgAFAAkJGSB/EgCRAgAeAAcJURdhCwB6AQAfAAMJ/wy5OgCTAAAAAA==.Cereza:BAAALgAECgEJAQAAAA==.',
Ch='Chaoslock:BAAALgADCgMJAwAAAA==.Chicknfajita:BAAALgAECgYJDQABLgAECgcJEQAHAAAAAA==.Chrissi:BAABLgAECn8fAAIDAAkJEAwNOwCGAQADAAkJEAwNOwCGAQAAAA==.',
Ci='Cinco:BAAALgADCgUJBQAAAA==.',
Cl='Clearly:BAAALgADCgQJAwAAAA==.Clessidra:BAAALgAECgIJAgAAAA==.',
Co='Cocytus:BAAALgAECgIJAwAAAA==.Colbith:BAAALgADCgkJDQAAAA==.Conquest:BAABLgAECn8WAAINAAYJwRKemwAdAQANAAYJwRKemwAdAQAAAA==.Cordaddy:BAABLgAECn8jAAIDAAkJQSWiBQBFAwADAAkJQSWiBQBFAwAAAA==.Cordragu:BAABLgAECn8WAAIRAAgJaySfBABGAwARAAgJaySfBABGAwABLgAECgkJIwADAEElAA==.Corinthe:BAABLgAECn8aAAMMAAgJESYFAwBbAwAMAAgJESYFAwBbAwANAAEJYQ+1VwE1AAABLgAECgkJIwADAEElAA==.Corinthin:BAABLgAECn83AAIRAAgJrhhbHgAuAgARAAgJrhhbHgAuAgAAAA==.',
Cr='Crinn:BAABLgAECn8WAAQLAAkJDw+PDABlAQALAAgJqwyPDABlAQAZAAYJYwvYJwAAAQAGAAEJuA32LwE4AAAAAA==.Crizmon:BAABLgAECn85AAILAAgJvyI/AQD5AgALAAgJvyI/AQD5AgAAAA==.Cryomancer:BAAALgADCgQJBAAAAA==.Crõwley:BAAALgADCgYJBgABLgAECggJHQAgAK0XAA==.',
Da='Damage:BAAALgAECgEJAQAAAA==.Damorax:BAAALgAECggJEQAAAA==.Darazarke:BAACLgAFFH8fAAIgAAcJeBHaBgAFAgAgAAcJeBHaBgAFAgAuAAQKfyoABCEACAkfHxAEANICACEACAkfHxAEANICACAABwm4HK0OAE4CACIAAQlwGIVdAEQAAAAA.Darkcursed:BAABLgAECn8vAAIjAAkJkgxsRQCzAQAjAAkJkgxsRQCzAQAAAA==.Darkndeadly:BAAALgAFFAIJAgAAAA==.Darksudge:BAAALgAECgEJAQAAAA==.Darps:BAACLgAFFH8FAAIUAAMJVh5dMgAZAQAUAAMJVh5dMgAZAQAuAAQKfyAAAhQACAnhH9MVAHwCABQACAnhH9MVAHwCAAAA.Daybreak:BAAALgAECggJEgAAAA==.Dayquil:BAECLgAFFH8HAAINAAMJuxCoTgDlAAANAAMJuxCoTgDlAAAuAAQKfykAAw0ACAkRIJMjAFcCAA0ACAkRIJMjAFcCAAwAAQnLGbN1AEAAAAAA.',
De='Deadaddie:BAACLgAFFH8GAAIGAAQJUQ7FUQApAQAGAAQJUQ7FUQApAQAuAAQKfyIAAwYACQkAIPkTALACAAYACQkAIPkTALACAAsABgllF5wRABYBAAAA.Deamoneyes:BAABLgAFFH8FAAINAAMJZRd6SADxAAANAAMJZRd6SADxAAAAAA==.Deathbakerey:BAAALgADCgUJBQAAAA==.Decastamon:BAABLgAECn8YAAIEAAgJQgW5mwAoAQAEAAgJQgW5mwAoAQAAAA==.Delin:BAAALgAECgcJBwABLgAFFAcJHwAgAHgRAA==.Deluxdh:BAAALgAECgMJAwAAAA==.Demonslinger:BAAALgADCgUJBQAAAA==.Dendrel:BAAALgAECgMJAwAAAA==.Derpspally:BAAALgAECgEJAQAAAA==.Derpspunch:BAABLgAECn8pAAIbAAkJjhv9CgC2AgAbAAkJjhv9CgC2AgABLgAFFAMJBQAUAFYeAA==.Destrox:BAAALgADCgYJBgAAAA==.Dezatra:BAAALgAECgQJBwAAAA==.Deíty:BAAALgADCgUJBgAAAA==.',
Di='Diane:BAEALgAECgkJCQAAAA==.Dieselcon:BAABLgAECn9JAAMVAAkJ8Bp0BgBVAgAVAAkJ8Bp0BgBVAgANAAEJswyfRAEyAAAAAA==.Dieseletta:BAAALgAECgMJAwAAAA==.Dinodruid:BAAALgAECgcJAwAAAA==.',
Do='Domdog:BAABLgAECn80AAIEAAkJTBZkNQAmAgAEAAkJTBZkNQAmAgAAAA==.Domína:BAAALgAECgEJAQAAAA==.Dontforget:BAABLgAECn8cAAMMAAcJuRR4NQBRAQAMAAYJKhR4NQBRAQANAAcJngPZ5QCuAAAAAA==.Dookiesmash:BAABLgAECn8nAAIdAAkJMiQaAgAYAwAdAAkJMiQaAgAYAwABLgAFFAMJBQAUAFYeAA==.Doomblast:BAAALgADCgIJAgAAAA==.Doomdealer:BAAALgAFFAEJAQAAAA==.Doomed:BAAALgADCgQJBAABLgAECggJGAAaADQdAA==.Doomrage:BAAALgADCgcJFAAAAA==.Doomsdead:BAAALgADCgcJBwAAAA==.Doomshock:BAAALgADCgYJBQAAAA==.',
Dr='Draftymonk:BAABLgAECn80AAMaAAgJMSTkBADbAgAaAAgJMSTkBADbAgAcAAUJVRpULwAhAQAAAA==.Drax:BAABLgAECn8jAAMkAAgJOAy8DgBFAQAjAAgJ5Qp4ZABfAQAkAAYJggu8DgBFAQAAAA==.Dreadgar:BAAALgAECgQJBAABLgAECggJHAASADgbAA==.Dritzzfive:BAACLgAFFH8FAAIGAAIJtgFDwQBwAAAGAAIJtgFDwQBwAAAuAAQKfx4AAgYACAlUCYp3AE4BAAYACAlUCYp3AE4BAAAA.Dritzzwar:BAAALgAECgYJDAAAAA==.',
Ed='Ediann:BAAALgADCgYJBgAAAA==.',
Ei='Eilica:BAAALgAECgUJBQAAAA==.',
Ek='Ekaine:BAAALgADCgQJBAABLgAECgYJGAAEAFgQAA==.',
El='Elandrus:BAAALgAECggJEQABLgAECggJHQAgAK0XAA==.Elishiveth:BAAALgAECgYJEgAAAA==.Elleynre:BAAALgADCgQJBAAAAA==.Elliewilliam:BAAALgADCgQJBAAAAA==.Elreim:BAAALgAECggJDgAAAA==.Elwendigo:BAAALgADCgMJAwAAAA==.Elwyna:BAAALgADCgIJAgAAAA==.',
Em='Emmara:BAABLgAECn8lAAIWAAgJrQVlFAD1AAAWAAgJrQVlFAD1AAAAAA==.',
En='Enhancement:BAAALgADCgcJDQABLgAFFAUJFgASAAIlAA==.Enitar:BAAALgAECgUJCQABLgAECgkJMwAFABkgAA==.',
Er='Erata:BAABLgAECn8YAAIkAAYJmw2VEgAEAQAkAAYJmw2VEgAEAQAAAA==.Erlangshen:BAAALgADCgUJBQAAAA==.Erravis:BAAALgADCgcJDwAAAA==.',
Ev='Evarion:BAAALgADCgEJAQAAAA==.Eviaei:BAAALgAECgMJAwAAAA==.Evulise:BAAALgAECgEJAQAAAA==.Evullight:BAAALgAECgEJAQAAAA==.',
Ez='Ezalan:BAAALgADCgcJBwAAAA==.Ezlok:BAABLgAECn8cAAISAAgJOBsGGQDuAQASAAgJOBsGGQDuAQAAAA==.Ezorreodd:BAAALgADCgQJBAAAAA==.Ezzorreodd:BAAALgAECgUJDgAAAA==.',
Fa='Fae:BAABLgAECn8fAAMSAAkJexOSKwBrAQASAAcJmBSSKwBrAQARAAYJihH9SgBWAQABLgAECgYJGgANAGQWAA==.Falcyon:BAAALgAECgMJBgAAAA==.Falerin:BAABLgAECn8jAAIDAAkJQBHTLQDMAQADAAkJQBHTLQDMAQAAAA==.Farenheit:BAABLgAECn81AAQIAAkJuhtUCwB6AgAIAAkJuhtUCwB6AgADAAQJlQ0dowCDAAAJAAMJsBDmQQBZAAAAAA==.Fatel:BAAALgAFFAEJAgABLgAFFAMJCgAZACgdAA==.Faydwer:BAAALgADCgMJBAAAAA==.Fayfox:BAAALgADCgkJFwAAAA==.',
Fe='Feenex:BAAALgAECggJEQAAAA==.',
Fi='Fillorey:BAAALgADCgEJAQAAAA==.Finick:BAAALgAECgcJEQAAAA==.Firedealer:BAABLgAECn8fAAIWAAgJgRWBCgCfAQAWAAgJgRWBCgCfAQAAAA==.Firnen:BAABLgAECn8dAAIgAAgJrRcaGgC7AQAgAAgJrRcaGgC7AQAAAA==.',
Fl='Flahash:BAAALgAECgMJAwAAAA==.Flapjack:BAAALgAECgIJAgABLgAECgUJDQAHAAAAAA==.Flappy:BAAALgAECgcJDwABLgAECgkJLgARALYgAA==.Flapster:BAAALgADCgkJFQABLgAECgkJLgARALYgAA==.Flashmaster:BAAALgAECgcJEQAAAA==.Flawlessheal:BAAALgAECgEJCgAAAA==.Flora:BAAALgAECgYJDgABLgAECgYJGgANAGQWAA==.Fluffybutt:BAAALgADCgkJHgAAAA==.',
Fo='Fossora:BAAALgAECgQJBwAAAA==.',
Fr='Frostmagi:BAAALgAECgYJDwABLgAFFAUJFgASAAIlAA==.Frostybunny:BAAALgAECgUJCQAAAA==.Frozenharded:BAAALgAECgQJAwABLgAECgcJFwARAAsZAA==.',
Fu='Furrbidden:BAAALgADCgQJBAAAAA==.Fusionve:BAAALgAECgUJBgAAAA==.',
Ga='Gaffershot:BAAALgADCgMJAwAAAA==.Gafferthicc:BAABLgAECn8cAAIFAAgJOBs/OgC9AQAFAAgJOBs/OgC9AQAAAA==.Gaffharir:BAAALgADCgUJBQAAAA==.Galvin:BAAALgADCgYJBgAAAA==.Garfeeld:BAAALgADCgcJCwABLgAECggJNwARAK4YAA==.Garlicroast:BAAALgAECgMJBgAAAA==.Gayden:BAAALgAECgUJBgAAAA==.',
Ge='Gelatin:BAAALgADCgQJBQAAAA==.Gerry:BAABLgAECn8wAAIlAAkJvx4bCgBkAgAlAAkJvx4bCgBkAgAAAA==.Geyora:BAABLgAECn8cAAIlAAgJAR+SAwDvAgAlAAgJAR+SAwDvAgAAAA==.',
Gg='Ggkando:BAAALgAECgYJCgAAAA==.',
Gi='Gigguschadus:BAAALgADCgIJAgAAAA==.Gingerail:BAABLgAECn8XAAIRAAcJCxlyKwDdAQARAAcJCxlyKwDdAQAAAA==.',
Gl='Glory:BAABLgAECn8jAAIZAAkJVhtMCABsAgAZAAkJVhtMCABsAgAAAA==.',
Gn='Gnotorious:BAAALgAECgMJAwAAAA==.',
Go='Goldi:BAAALgAECgEJAQAAAA==.Goochsquirts:BAABLgAECn8sAAMRAAkJ+xiHKADuAQARAAkJ+xiHKADuAQASAAEJ2ATMmAAiAAAAAA==.Gorrick:BAAALgAFFAEJAQAAAA==.Gorriff:BAAALgAECgMJBAAAAA==.',
Gr='Graestrae:BAABLgAECn8vAAIGAAgJ9wtfZwBzAQAGAAgJ9wtfZwBzAQAAAA==.Gravedygger:BAABLgAECn85AAIUAAgJDRs/LwD2AQAUAAgJDRs/LwD2AQAAAA==.Greenonions:BAAALgADCgIJAgAAAA==.Grenswood:BAACLgAFFH8VAAImAAUJTCSpAgBpAQAmAAUJTCSpAgBpAQAuAAQKfzkAAiYACQkKJigAAHIDACYACQkKJigAAHIDAAAA.Grimmarius:BAAALgAFFAIJAgAAAA==.Grimmkin:BAAALgAECgUJCQAAAA==.Grimmyr:BAAALgADCgYJBgAAAA==.Growl:BAAALgADCgEJAQAAAA==.Grumbo:BAAALgAECgQJBwAAAA==.Gryff:BAAALgADCgcJBwAAAA==.Gryffindor:BAAALgADCgQJBAAAAA==.',
Gu='Gunnerr:BAAALgAECgMJBQAAAA==.Guuldurak:BAAALgAECgQJBwAAAA==.',
Ha='Hanadan:BAAALgADCgcJBwAAAA==.Harrod:BAABLgAECn8lAAIEAAkJTwhVZgCUAQAEAAkJTwhVZgCUAQAAAA==.Hasew:BAABLgAECn8eAAIUAAcJnRvAMgDkAQAUAAcJnRvAMgDkAQAAAA==.Haste:BAAALgAECgMJAwABLgAFFAMJCgAZACgdAA==.Hauken:BAAALgAECgkJEAABLgAFFAcJEwAUALkbAA==.',
He='He:BAAALgAECgEJAQAAAA==.Heimlich:BAAALgAECgIJAwABLgAECggJHgANAD4aAA==.Hellodoodle:BAAALgAECgYJCgAAAA==.Helpimßlind:BAABLgAECn8qAAIFAAgJ1RUPSgCGAQAFAAgJ1RUPSgCGAQAAAA==.Hera:BAACLgAFFH8UAAIUAAUJNCQrEACEAQAUAAUJNCQrEACEAQAuAAQKfzEAAhQACAn1JUUCAHYDABQACAn1JUUCAHYDAAAA.Herry:BAABLgAECn8ZAAIlAAcJLxslEgD+AQAlAAcJLxslEgD+AQABLgAECgkJMAAlAL8eAA==.Heyner:BAABLgAECn85AAInAAgJyxjlBAD+AQAnAAgJyxjlBAD+AQAAAA==.',
Hi='Hille:BAAALgADCgEJAQAAAA==.Hinral:BAACLgAFFH8QAAIbAAUJfyKxCQD0AQAbAAUJfyKxCQD0AQAuAAQKfykAAhsACAnIJSkDAEsDABsACAnIJSkDAEsDAAAA.',
Ho='Hojira:BAAALgAECgYJBgAAAA==.Holyangus:BAAALgAECgUJDgAAAA==.Holybabe:BAAALgADCgEJAQAAAA==.Holysmacker:BAAALgAECgMJAwABLgAFFAMJBgAEAJMJAA==.',
Hu='Hukkaru:BAAALgADCgYJDgAAAA==.',
['Hë']='Hëll:BAABLgAECn8qAAIjAAgJpBUROQDdAQAjAAgJpBUROQDdAQAAAA==.',
Ic='Iceblind:BAABLgAECn8UAAIFAAYJZAo8lADNAAAFAAYJZAo8lADNAAAAAA==.',
Il='Ilcanna:BAAALgADCgEJAQAAAA==.Illaynne:BAABLgAECn8uAAIBAAgJCx4rDwBOAgABAAgJCx4rDwBOAgAAAA==.Ilvasir:BAAALgAECgIJAgAAAA==.',
Im='Imani:BAACLgAFFH8OAAIoAAUJFQdSBwAKAQAoAAUJFQdSBwAKAQAuAAQKfy4AAigACAk+FiQNAO4BACgACAk+FiQNAO4BAAAA.Immensepain:BAABLgAECn8mAAIEAAgJqhD/fADXAQAEAAgJqhD/fADXAQAAAA==.Imnotbalding:BAAALgAECgQJBwAAAA==.Imtrynacrack:BAAALgADCgQJBAAAAA==.Imurhucklbry:BAAALgADCgUJBQAAAA==.',
In='Inalee:BAAALgAECgcJEgAAAA==.Inoshikacho:BAABLgAECn80AAIKAAkJFQ5YDgCaAQAKAAkJFQ5YDgCaAQAAAA==.Involio:BAAALgADCggJEAAAAA==.Invý:BAABLgAECn8wAAINAAgJGhsuMwASAgANAAgJGhsuMwASAgAAAA==.',
Ir='Irelià:BAAALgAECgQJBAAAAA==.Irenna:BAAALgADCgUJBQAAAA==.Irishdots:BAAALgAECgQJBAAAAA==.Irishkicks:BAAALgAECgEJAgAAAA==.Irishlife:BAAALgAECgQJBAAAAA==.Irishmecha:BAACLgAFFH8OAAIYAAUJjgS8BAAfAQAYAAUJjgS8BAAfAQAuAAQKfywAAhgACAluGR4FAEQCABgACAluGR4FAEQCAAAA.Irishtotems:BAAALgADCgQJBAAAAA==.Irishtraps:BAAALgADCgEJAQAAAA==.',
Is='Isandra:BAAALgADCgEJAQAAAA==.',
It='Itharillys:BAABLgAECn8vAAIUAAkJlhImKQAPAgAUAAkJlhImKQAPAgAAAA==.',
Ja='Jaadu:BAAALgAECgIJAwAAAA==.',
Je='Jeennkiins:BAAALgADCggJFwABLgAECgkJMAABAMQcAA==.Jessibella:BAABLgAECn8aAAMTAAgJKhIrGwDIAQATAAgJUw8rGwDIAQABAAIJwRgoTwByAAAAAA==.Jezzako:BAABLgAECn8YAAMUAAYJjgtlaAAvAQAUAAUJtQ1laAAvAQAlAAYJGwSgGwAaAQAAAA==.',
Ji='Jinx:BAAALgAECgMJBQABLgAECgYJGgANAGQWAA==.',
Jo='Johali:BAABLgAECn8gAAIPAAcJKAiPMQDQAAAPAAcJKAiPMQDQAAAAAA==.',
Ju='Jupp:BAAALgAECgYJBQAAAA==.Justise:BAABLgAECn8dAAQdAAgJ7BcDFADMAQAdAAgJUBcDFADMAQAOAAUJFBgHRwAAAQAPAAEJjQ4LRgAsAAAAAA==.Jutojerry:BAABLgAECn8YAAMaAAgJNB3lEAAUAgAaAAgJNB3lEAAUAgAbAAIJzhwVTQChAAAAAA==.',
['Jî']='Jîru:BAAALgADCgQJBAAAAA==.',
['Jö']='Jöhnblaze:BAACLgAFFH8GAAIOAAMJqgnBKgDNAAAOAAMJqgnBKgDNAAAuAAQKfyUABA4ACQlQFNQmAJ4BAA4ACAlsFNQmAJ4BAB0ACAkTD4kZAEcBAA8AAQlDC7diAC4AAAAA.Jöker:BAAALgAECgUJBgAAAA==.',
Ka='Kaalya:BAAALgAECgQJBwAAAA==.Kaelus:BAAALgADCgEJAQAAAA==.Kahoona:BAAALgAECgYJEgAAAA==.Kailys:BAACLgAFFH8FAAIVAAIJ9QTdDwBPAAAVAAIJ9QTdDwBPAAAuAAQKfzUAAhUACAk4FZoOAKwBABUACAk4FZoOAKwBAAAA.Kaishias:BAABLgAECn8tAAINAAkJ7h2tEQDAAgANAAkJ7h2tEQDAAgAAAA==.Kamyra:BAABLgAECn8WAAINAAcJVwu3sQD6AAANAAcJVwu3sQD6AAAAAA==.Kandoh:BAAALgAECgEJAQABLgAECgYJCgAHAAAAAA==.Kanimeh:BAAALgADCgQJBAAAAA==.Kankuró:BAACLgAFFH8IAAIUAAMJ1w5NRwDZAAAUAAMJ1w5NRwDZAAAuAAQKfz4AAxQACQntIfANALwCABQACQntIfANALwCABYAAQnIB2qOAC0AAAAA.Karmella:BAAALgAECgQJBAAAAA==.Kartoshka:BAAALgAECgEJAQAAAA==.',
Ke='Kedzen:BAAALgADCgkJJAABLgAECggJNwARAK4YAA==.Kerfur:BAAALgAECgMJAwAAAA==.',
Ki='Killudead:BAAALgAECggJDwAAAA==.',
Ko='Kodetra:BAAALgAECgUJCAAAAA==.Kolgrim:BAABLgAECn8hAAMLAAgJfRoFEAAsAQAZAAcJZRrHHQBbAQALAAYJBRMFEAAsAQAAAA==.Korimya:BAAALgAECgEJAgAAAA==.Korva:BAAALgAECgYJEwABLgAECgYJGAAEAFgQAA==.',
Kr='Krianthess:BAAALgAFFAEJAQAAAA==.Krissypoo:BAAALgAECgMJAwAAAA==.Kristie:BAABLgAECn8YAAIEAAYJWBCNugBsAQAEAAYJWBCNugBsAQAAAA==.Krom:BAABLgAECn8qAAIRAAgJPhAHRQBmAQARAAgJPhAHRQBmAQAAAA==.',
Ku='Kuadonaran:BAAALgADCgEJAQABLgAECggJLgAkAPYhAA==.Kulitcomandr:BAAALgADCgUJBQAAAA==.Kupquake:BAACLgAFFH8NAAIcAAUJ6gp1FAD4AAAcAAUJ6gp1FAD4AAAuAAQKfy8AAhwACAmwH7cQAHYCABwACAmwH7cQAHYCAAAA.',
Ky='Kynris:BAAALgADCgMJAwABLgAECggJHQAgAK0XAA==.',
La='Laancelot:BAAALgADCgkJDgAAAA==.Lacy:BAAALgADCgEJAQAAAA==.Laetus:BAAALgAECgUJDQAAAA==.Lamort:BAABLgAECn8uAAQkAAgJ9iHIBAAVAgAjAAcJWB35PAAZAgAkAAcJ8yLIBAAVAgAmAAYJcxryDQAyAQAAAA==.Lanaal:BAAALgADCgIJAgAAAA==.Lancewh:BAAALgADCgkJFwAAAA==.Launzi:BAAALgADCgkJDgAAAA==.Lavirna:BAAALgAECgEJAQABLgAECgYJGAAEAFgQAA==.Lazulli:BAAALgADCgMJAwAAAA==.',
Le='Leaila:BAAALgAECgYJEAAAAA==.Ledollabean:BAAALgADCgYJBgAAAA==.Legg:BAAALgADCgEJAQAAAA==.Leonora:BAABLgAECn8oAAIWAAkJvA+NCgCeAQAWAAkJvA+NCgCeAQAAAA==.Levdk:BAAALgAECgEJAQAAAA==.',
Li='Lightbreakk:BAAALgADCgkJDwABLgAECgUJBwAHAAAAAA==.Lindesong:BAAALgAECgEJAQABLgAFFAcJEwAUALkbAA==.Lisondrel:BAAALgAECgUJBwAAAA==.',
Lo='Lockbone:BAAALgAECgMJAwAAAA==.Loops:BAACLgAFFH8GAAIlAAMJDxrhEwAIAQAlAAMJDxrhEwAIAQAuAAQKfyEAAiUACQnpHlAPAB4CACUACQnpHlAPAB4CAAAA.Lorette:BAACLgAFFH8GAAMBAAMJQBEKGQDCAAABAAMJQBEKGQDCAAACAAEJEhSQKgBTAAAuAAQKfyIAAwIACQkjHpMQADACAAIACAmKHZMQADACAAEACQmnGLAjAIMBAAAA.Lovelychow:BAAALgADCgYJCQAAAA==.',
Lu='Luckynyx:BAAALgAECgYJCgAAAA==.Lunate:BAAALgAECgIJAgABLgAECggJLgAhAM0eAA==.Luuma:BAAALgAECggJDgABLgAECgYJGgANAGQWAA==.',
Lw='Lwinterheart:BAAALgADCgYJBgAAAA==.',
Ly='Ly:BAAALgADCgUJBQAAAA==.Lymriina:BAACLgAFFH8GAAIXAAMJaROkDQARAQAXAAMJaROkDQARAQAuAAQKfxwAAhcACAlsI5wHABYDABcACAlsI5wHABYDAAEuAAUUBwkTABQAuRsA.Lyr:BAAALgADCgcJBwAAAA==.',
Ma='Machotedan:BAABLgAECn8sAAINAAkJlSDGFACqAgANAAkJlSDGFACqAgAAAA==.Macmittens:BAAALgAECggJEAAAAA==.Magedude:BAAALgAECgIJAgAAAA==.Maliken:BAABLgAECn8fAAIGAAgJ7B34JQCkAgAGAAgJ7B34JQCkAgAAAA==.Mamadrag:BAABLgAECn8fAAQgAAgJQxn8EACVAQAgAAcJkhj8EACVAQAiAAMJXgblWABbAAAhAAIJ8AZtGwBTAAAAAA==.Mambø:BAAALgADCgYJBgAAAA==.Managua:BAAALgAECgIJBQAAAA==.Mandwa:BAAALgAECgcJBwABLgAECgkJMwAFABkgAA==.Mario:BAACLgAFFH8GAAIEAAMJkwnSbADcAAAEAAMJkwnSbADcAAAuAAQKfyEAAgQACQkAGPAuAD8CAAQACQkAGPAuAD8CAAAA.Masivewin:BAAALgAECgEJAQAAAA==.Mastashifta:BAABLgAECn8WAAQKAAYJ2xOeFgAoAQAKAAYJ2xOeFgAoAQAIAAQJ7QxWVgCFAAADAAIJCA37qABKAAAAAA==.Matryoshka:BAAALgAECgYJDwAAAA==.Mattsadler:BAAALgAECgEJAwAAAA==.Maverex:BAAALgAFFAEJAQAAAA==.Mavok:BAAALgAECgEJAQAAAA==.Maxxim:BAAALgAECgMJAwAAAA==.Mayihmpurleg:BAAALgAECgMJAwABLgAECgkJHwAWAIEVAA==.',
Mc='Mcnugs:BAAALgAECgUJCQAAAA==.',
Me='Mechamonk:BAAALgADCgIJAgAAAA==.Merczdk:BAAALgADCgYJDAAAAA==.Merczlock:BAAALgAECgQJBAAAAA==.Meta:BAABLgAECn8VAAIFAAYJWhftUgCsAQAFAAYJWhftUgCsAQAAAA==.',
Mi='Mindfreeze:BAAALgADCgUJBQAAAA==.Minidudde:BAAALgAECgMJAwAAAA==.Minthara:BAAALgADCgYJDgAAAA==.Missdemon:BAAALgADCgUJBgAAAA==.Missikrissi:BAAALgADCgYJBwAAAA==.Missmorrigan:BAAALgAECgQJDAAAAA==.Missî:BAAALgAECgcJEAAAAA==.Mists:BAACLgAFFH8KAAIjAAUJ2hzuDgBnAQAjAAUJ2hzuDgBnAQAuAAQKfyQAAyMACAmLJOwLABsDACMACAmLJOwLABsDACYAAgmaHfZHAJcAAAAA.Miththrawndo:BAABLgAECn8oAAMZAAgJ0hpHEgDnAQAZAAgJ0hpHEgDnAQALAAEJAAAyGwAIAAAAAA==.',
Ml='Ml:BAABLgAECn8UAAMmAAYJVh4HCwAPAgAmAAYJVh4HCwAPAgAjAAQJJg9QpQDfAAAAAA==.',
Mo='Moldevort:BAAALgAECgUJDQAAAA==.Momjeans:BAABLgAECn8vAAMQAAkJtB6cAQCzAgAQAAcJkyGcAQCzAgAEAAkJ6xkMJABwAgAAAA==.Monfanth:BAAALgAECgEJAQABLgAECgYJGAAEAFgQAA==.Morningumbra:BAAALgADCgIJAgAAAA==.',
Ms='Mstryoda:BAAALgADCgUJCAAAAA==.',
Mu='Muramasa:BAAALgAECgcJCQAAAA==.',
My='Myfriendtold:BAAALgADCgEJAgAAAA==.Mythunsarian:BAABLgAECn8xAAIfAAkJXRL+EQDUAQAfAAkJXRL+EQDUAQAAAA==.',
['Mâ']='Mâximus:BAAALgADCgYJBwAAAA==.',
['Mä']='Mäylä:BAABLgAECn8nAAIDAAkJUg99MAC8AQADAAkJUg99MAC8AQAAAA==.',
['Mí']='Míst:BAABLgAECn85AAINAAkJjxduKwAxAgANAAkJjxduKwAxAgAAAA==.',
Na='Nazaline:BAAALgADCgIJAgAAAA==.',
Ne='Necrohealiac:BAAALgAECgQJCQAAAA==.Necrotizer:BAAALgADCgMJAwAAAA==.Nephie:BAABLgAECn8lAAIfAAkJgh76CQBaAgAfAAkJgh76CQBaAgAAAA==.Netazia:BAAALgADCgcJGQAAAA==.Nethralfus:BAAALgAECgEJAQAAAA==.Nezqk:BAACLgAFFH8QAAQGAAUJbwXvaAD4AAAGAAQJbwXvaAD4AAALAAQJ4AFgDQDbAAAZAAEJAAAUSQAAAAAuAAQKfyUAAwYACAmlFhhdANsBAAYACAnZFRhdANsBAAsAAglyHMklAEwAAAAA.',
Ni='Niano:BAAALgAECgEJAQAAAA==.',
Nm='Nmnenthe:BAAALgAECgcJDQAAAA==.',
No='Noelytv:BAAALgADCgcJBwAAAA==.Norman:BAAALgADCgEJAgAAAA==.November:BAAALgADCgEJAQAAAA==.Noxren:BAAALgAFFAEJAgAAAA==.',
['Nî']='Nîstø:BAABLgAECn8hAAQVAAgJFRdtDgDeAQAVAAcJzBhtDgDeAQAMAAYJIxzvJgCsAQANAAQJBQrNJAFbAAAAAA==.',
Ob='Obin:BAABLgAECn8oAAIOAAkJcxaeHgDWAQAOAAkJcxaeHgDWAQAAAA==.',
Oh='Oharachloe:BAAALgADCgYJBgAAAA==.',
Ol='Ollenbock:BAAALgADCgQJBAABLgAFFAcJEwAUALkbAA==.',
Or='Orhanu:BAAALgAECgcJCAAAAA==.',
Ou='Outbbreakk:BAAALgAECgUJBwAAAA==.',
Ow='Owendriel:BAABLgAECn8XAAIFAAgJURhsOwAGAgAFAAgJURhsOwAGAgAAAA==.',
Pa='Padocus:BAAALgADCgUJBwAAAA==.Pajamas:BAABLgAECn8zAAIUAAkJrR3rCgDuAgAUAAkJrR3rCgDuAgAAAA==.Palyamorous:BAAALgADCgUJBQAAAA==.Pandress:BAABLgAECn8hAAIUAAgJ2RagPADCAQAUAAgJ2RagPADCAQAAAA==.Pankake:BAAALgAECgMJAwABLgAECgkJKQAaALUgAA==.Paralysis:BAABLgAFFH8FAAIFAAUJHAyzOgAOAQAFAAUJHAyzOgAOAQABLgAFFAUJDQAcAOoKAA==.',
Pe='Peetza:BAAALgAECgIJAgABLgAECgkJKQAaALUgAA==.Peryite:BAABLgAECn8qAAMTAAkJhhSCEwAWAgATAAgJGRaCEwAWAgABAAcJSgolRwAdAQAAAA==.',
Ph='Phaedrana:BAAALgADCgIJAgAAAA==.Phelris:BAABLgAECn8YAAIFAAcJQg9tYwA7AQAFAAcJQg9tYwA7AQAAAA==.',
Pi='Pillpusher:BAAALgAECgMJBAAAAA==.Pisscat:BAAALgAECgYJEAAAAA==.',
Po='Polymerase:BAAALgAECgQJBAABLgAECgkJMAAGAMcfAA==.',
Pr='Prideindeath:BAAALgAECgUJBQAAAA==.Promiscuity:BAAALgAECggJEwAAAA==.Protròast:BAAALgAECgQJBQAAAA==.Prængle:BAABLgAECn8UAAIbAAYJ6RaWLAB9AQAbAAYJ6RaWLAB9AQAAAA==.',
Ps='Psoas:BAAALgAECgYJCAABLgAECggJLgAhAM0eAA==.Psypriest:BAABLgAFFH8OAAIBAAQJBh7CCQB0AQABAAQJBh7CCQB0AQABLgAFFAcJJgABAOwZAA==.',
Pu='Pulverine:BAAALgADCgcJDgAAAA==.',
Qu='Quarantinia:BAAALgADCgEJAQAAAA==.',
Ra='Rabbi:BAABLgAECn8kAAMCAAcJExrKGgDJAQACAAcJExrKGgDJAQABAAUJaA7TTgD9AAAAAA==.Ragerunnerx:BAAALgAECggJDwAAAA==.Rahfna:BAAALgAECgEJAQAAAA==.Rakan:BAAALgADCgIJAgAAAA==.Raynare:BAAALgAECgIJAwAAAA==.',
Re='Redall:BAABLgAECn8fAAIWAAgJMwtIDwA/AQAWAAgJMwtIDwA/AQAAAA==.Reesespbc:BAABLgAECn83AAIEAAkJ5A94SQDjAQAEAAkJ5A94SQDjAQAAAA==.Reina:BAABLgAECn8aAAINAAYJZBYbjwAzAQANAAYJZBYbjwAzAQAAAA==.Reinir:BAABLgAECn8qAAIdAAkJdSPTAgD3AgAdAAkJdSPTAgD3AgAAAA==.Reinz:BAABLgAECn8UAAIaAAgJ5RXzFwDJAQAaAAgJ5RXzFwDJAQAAAA==.Rektagar:BAABLgAECn8oAAMSAAkJZiOPDAB4AgASAAgJHyOPDAB4AgARAAQJSR2PTABJAQABLgAFFAcJEwAUALkbAA==.Resident:BAAALgAECgIJAgABLgAECggJLgAhAM0eAA==.Ressandra:BAAALgAECgYJBgAAAA==.Reyvanna:BAAALgADCgEJAQAAAA==.',
Ro='Roar:BAAALgAECgUJBQABLgAECgkJKwAGAMgUAA==.Robert:BAAALgADCgEJAQAAAA==.Rosavyra:BAAALgAECggJCQAAAA==.Roshara:BAAALgAECgQJDgAAAA==.',
Ry='Ryanbutscaly:BAAALgAECgIJAgABLgAECgkJGAAEAN4PAA==.Ryce:BAAALgAECgQJBAABLgAECgkJKQAaALUgAA==.Ryoka:BAAALgAECgIJAgAAAA==.',
['Rö']='Rös:BAACLgAFFH8SAAIEAAUJThzBNwBTAQAEAAUJThzBNwBTAQAuAAQKfzMAAwQACAljH5AmAGUCAAQACAljH5AmAGUCACkAAQlfINwMAF0AAAAA.',
['Rü']='Rübblë:BAAALgAECgQJBwAAAA==.',
Sa='Saberie:BAAALgAECgQJBwAAAA==.Sacredice:BAAALgAECgQJBQABLgAECgcJFwARAAsZAA==.Salamun:BAAALgAECgQJBQAAAA==.Salaria:BAABLgAECn8iAAIFAAgJrwnUaAAtAQAFAAgJrwnUaAAtAQAAAA==.Salen:BAABLgAECn86AAMoAAkJ4RlbBgBFAgAoAAkJ4RlbBgBFAgARAAQJoQWAiQCDAAAAAA==.Salina:BAEBLgAECn8oAAIeAAkJFhYRCQCxAQAeAAkJFhYRCQCxAQAAAA==.Sandraia:BAACLgAFFH8GAAIGAAMJ5xQbeADgAAAGAAMJ5xQbeADgAAAuAAQKfygAAgYACQkNHMIuACECAAYACQkNHMIuACECAAAA.Sandstique:BAABLgAECn8XAAIRAAkJpyFqCADvAgARAAkJpyFqCADvAgAAAA==.Sandtwig:BAAALgADCgEJAQAAAA==.Sandweaver:BAAALgADCgEJAQAAAA==.Sanjira:BAABLgAECn8cAAInAAkJBAhwCQBmAQAnAAkJBAhwCQBmAQAAAA==.Sarlak:BAAALgAECggJCAAAAA==.Sarusuby:BAACLgAFFH8GAAIJAAMJqAQWGgBuAAAJAAMJqAQWGgBuAAAuAAQKfyYAAgkACQkmFHMNAK8BAAkACQkmFHMNAK8BAAAA.Satae:BAAALgAECgMJAwABLgAECgkJKQAaALUgAA==.',
Sc='Schuffles:BAAALgAECgEJAQAAAA==.Scottyfist:BAACLgAFFH8GAAIaAAMJJR3lIQAIAQAaAAMJJR3lIQAIAQAuAAQKfxwAAhoACQnEH3oWAFUCABoACQnEH3oWAFUCAAAA.Scottymac:BAAALgADCgYJBgABLgAFFAMJBgAaACUdAA==.',
Se='Sealion:BAACLgAFFH8JAAMMAAMJVyCeEQDDAAAMAAIJQB2eEQDDAAANAAIJlAsBcQCRAAAuAAQKfxoAAwwACQmUF2AWAF4CAAwACQmUF2AWAF4CAA0AAwltI8baAL4AAAAA.Seetah:BAABLgAECn8jAAIBAAgJjyJQBgDuAgABAAgJjyJQBgDuAgAAAA==.Seetur:BAAALgAECgQJBAAAAA==.Serratus:BAABLgAECn8uAAQhAAgJzR6/BAAAAgAhAAgJqhu/BAAAAgAiAAgJjhoFGAD2AQAgAAEJTgQZNgAsAAAAAA==.Setcher:BAAALgADCgEJAQAAAA==.',
Sh='Shadaddy:BAACLgAFFH8FAAIEAAIJPwg6iACUAAAEAAIJPwg6iACUAAAuAAQKfxkAAgQACAlMFcJMANkBAAQACAlMFcJMANkBAAEuAAUUBAkGAAYAUQ4A.Shadoweyes:BAAALgAECgcJCgAAAA==.Shadowsyther:BAAALgAECgYJBgAAAA==.Shamax:BAAALgADCgEJAgABLgADCgUJBQAHAAAAAA==.Shamommy:BAAALgAECgQJBwAAAA==.Shayes:BAABLgAECn8pAAIJAAkJfR5BBACpAgAJAAkJfR5BBACpAgAAAA==.Shifue:BAAALgAECgMJBAAAAA==.Shimmerstar:BAABLgAECn8nAAINAAkJDxweGACUAgANAAkJDxweGACUAgAAAA==.',
Si='Sigg:BAAALgAECgUJBQAAAA==.Silexe:BAAALgAECgUJBwABLgAECggJLgAkAPYhAA==.Sitar:BAAALgAECgEJAQABLgAECgkJMwAFABkgAA==.',
Sk='Skathae:BAAALgAECgEJAQABLgAECggJHQAgAK0XAA==.Skåld:BAABLgAECn8oAAMGAAgJuxlcNAAKAgAGAAgJuxlcNAAKAgAZAAEJAADMXAAAAAAAAA==.',
Sl='Slinga:BAAALgAECgUJBQAAAA==.Slipperyboi:BAAALgAECgYJBgAAAA==.',
Sn='Snuffles:BAABLgAECn8cAAIlAAgJ2BoWGADBAQAlAAgJ2BoWGADBAQAAAA==.Snugs:BAAALgADCgEJAQAAAA==.',
So='Sofiya:BAAALgADCgEJAQAAAA==.Soldraca:BAAALgAECgYJEgAAAA==.Soulence:BAAALgAECgMJBAAAAA==.Soymaster:BAAALgADCgYJBgABLgAECggJHAASADgbAA==.',
St='Stinkbug:BAAALgADCgcJDQAAAA==.Stutters:BAABLgAECn8wAAMGAAkJxx84FACuAgAGAAkJxx84FACuAgAZAAUJIBgpIABDAQAAAA==.',
Su='Sudachi:BAACLgAFFH8GAAIPAAMJUhFWGADXAAAPAAMJUhFWGADXAAAuAAQKfxcAAw8ACQlAG40EAKMCAA8ACQlAG40EAKMCAA4AAgkDDViUAG4AAAEuAAUUBQkJABwAqxwA.Sunnyräy:BAAALgADCgcJDQAAAA==.Suthrheimr:BAAALgADCgMJAwABLgAECgkJMAAlAL8eAA==.',
Sw='Swineflu:BAAALgAECgMJAwAAAA==.Swizzjenks:BAAALgADCgMJAwAAAA==.',
Sy='Synonym:BAAALgADCgcJBwAAAA==.Syrabane:BAAALgAECgYJBgAAAA==.Syrprize:BAAALgADCgEJAQABLgAECggJGAAaADQdAA==.',
['Sý']='Sýndrá:BAABLgAECn8mAAImAAkJOSHWAADqAgAmAAkJOSHWAADqAgAAAA==.',
Ta='Tachyon:BAAALgADCgEJAQAAAA==.Tacobob:BAACLgAFFH8LAAIDAAQJBgbILADhAAADAAQJBgbILADhAAAuAAQKfy4AAgMACAlxFm83AMkBAAMACAlxFm83AMkBAAAA.Taethron:BAAALgADCgUJBQAAAA==.Taffeta:BAAALgADCgEJAQAAAA==.Taffyboy:BAAALgADCggJCgAAAA==.Talysiah:BAABLgAECn8ZAAIjAAcJNgtBeQAxAQAjAAcJNgtBeQAxAQAAAA==.Tannir:BAAALgAECgEJAQAAAA==.Tarogen:BAAALgADCgQJBgABLgAFFAUJEAAbAH8iAA==.Tavhunts:BAAALgADCgkJCQAAAA==.Tavok:BAABLgAECn8zAAMOAAgJkCMVCADAAgAOAAgJkCMVCADAAgAdAAEJ+BUGRAA9AAAAAA==.',
Te='Tenacious:BAAALgADCgcJDAAAAA==.Tene:BAAALgADCgMJAwAAAA==.Teratots:BAAALgADCgYJBgAAAA==.Testament:BAAALgADCgcJCAAAAA==.',
Th='Thenna:BAAALgAECgMJAwAAAA==.Theosclaws:BAAALgADCgcJDgAAAA==.Theramier:BAAALgAECgcJEAAAAA==.Thiux:BAABLgAECn8bAAMjAAgJaB7VGgBpAgAjAAgJaB7VGgBpAgAmAAEJAAByXQBWAAAAAA==.Thotsnprayrs:BAAALgADCgUJCAABLgAECggJGAAaADQdAA==.Thourin:BAAALgADCgEJAQAAAA==.Thrappy:BAABLgAECn8uAAIRAAkJtiD/BwAJAwARAAkJtiD/BwAJAwAAAA==.Thráwñ:BAAALgAECgIJAwABLgAECgYJCgAHAAAAAA==.',
Ti='Tiddyhammer:BAABLgAECn8iAAMNAAgJVR3aLAArAgANAAcJVR3aLAArAgAMAAcJNBRlRQBiAQAAAA==.Tintaglia:BAAALgAECgYJCQABLgAFFAMJBgAEAJMJAA==.Tirtun:BAACLgAFFH8GAAIEAAMJZBLSYgDwAAAEAAMJZBLSYgDwAAAuAAQKfygAAgQACAkQH4cyADECAAQACAkQH4cyADECAAAA.',
To='Tomek:BAABLgAECn8tAAMlAAkJGBxGCwBUAgAlAAkJ8hhGCwBUAgAWAAcJyB9vCwCLAQAAAA==.Torukmakto:BAAALgADCggJCAAAAA==.Totemetot:BAAALgAECgYJDgAAAA==.',
Tr='Treemourne:BAAALgADCgEJAQAAAA==.Triggeer:BAABLgAECn8zAAIdAAkJxRYVEAC/AQAdAAkJxRYVEAC/AQAAAA==.',
Tu='Tully:BAAALgADCgEJAQAAAA==.Turalus:BAAALgADCgYJBgAAAA==.Turina:BAABLgAECn8UAAIjAAYJxwI2ygCcAAAjAAYJxwI2ygCcAAAAAA==.',
Tw='Twelvekill:BAACLgAFFH8SAAIUAAUJVQ5QLgAlAQAUAAUJVQ5QLgAlAQAuAAQKfy4AAhQACAmFGiYaAGsCABQACAmFGiYaAGsCAAAA.',
Ty='Tyliaa:BAABLgAECn8aAAMRAAgJ8xy8EQCVAgARAAgJ8xy8EQCVAgASAAEJhQhGkwAnAAABLgAECggJHwAgAEMZAA==.Tylidus:BAAALgAECgcJCwAAAA==.Tyranny:BAAALgAECgYJEgAAAA==.',
Ub='Ubisami:BAABLgAECn8YAAILAAgJmAkUCwASAQALAAgJmAkUCwASAQAAAA==.',
Ud='Udderfailure:BAAALgADCgIJAgAAAA==.',
Uk='Ukstryker:BAAALgAECgMJBQABLgAFFAMJCgAZACgdAA==.',
Ul='Ullur:BAAALgADCgEJAgAAAA==.Ultramon:BAABLgAECn8rAAINAAgJ8A6nbAB1AQANAAgJ8A6nbAB1AQAAAA==.Uly:BAAALgAECgYJDQAAAA==.',
Un='Unwell:BAAALgAECgUJCgABLgAFFAMJBwAXAEIeAA==.',
Up='Uplok:BAAALgADCgEJAQAAAA==.',
Ur='Urgoochness:BAABLgAECn8hAAIDAAgJshagLADTAQADAAgJshagLADTAQAAAA==.Urikhai:BAAALgAECgQJBQAAAA==.',
Uw='Uwuwu:BAAALgAECgEJAQAAAA==.',
Va='Vaellvoid:BAAALgAECgMJAwAAAA==.Vainglorious:BAAALgAECgQJDwABLgAECgkJIwAZAFYbAA==.Valanora:BAABLgAECn8qAAIkAAkJ0BqjAwBbAgAkAAkJ0BqjAwBbAgAAAA==.Valdis:BAAALgADCgcJDgABLgAECgYJGAAEAFgQAA==.Valinaxius:BAABLgAECn8bAAMZAAYJMB5AFQCTAQAZAAYJMB5AFQCTAQAGAAQJ7AhZ1wCvAAAAAA==.Valphalk:BAAALgADCggJCQAAAA==.Vanastasia:BAAALgAECgQJBgAAAA==.Vanyr:BAAALgADCgkJEAAAAA==.Vapturov:BAABLgAECn8UAAIGAAYJRQrCqwDyAAAGAAYJRQrCqwDyAAAAAA==.',
Ve='Veeks:BAAALgAECgcJDwAAAA==.Velikirn:BAABLgAECn83AAMcAAkJASPQBADnAgAcAAkJ5yLQBADnAgAaAAgJnRhGFgDZAQAAAA==.Vellwinnalas:BAAALgADCgUJCAAAAA==.Verah:BAAALgADCgYJBgAAAA==.Versø:BAABLgAECn8mAAQYAAcJOBvvBgD9AQAYAAYJSBvvBgD9AQAnAAcJmxbKCAB6AQAXAAQJ1hmHPgAoAQAAAA==.',
Vi='Villageinn:BAAALgAECgMJAwAAAA==.Vine:BAAALgAECgYJEAAAAA==.Vixxon:BAABLgAECn8tAAIUAAgJTBnDMwDkAQAUAAgJTBnDMwDkAQAAAA==.',
Vl='Vlai:BAAALgAECgIJAgABLgAECgYJCQAHAAAAAA==.Vly:BAABLgAECn8aAAMXAAkJDw5eHwBvAQAXAAkJqQxeHwBvAQAYAAYJmwnCEAD3AAABLgAECgYJCQAHAAAAAA==.Vlyrae:BAAALgAECgIJAwABLgAECgYJCQAHAAAAAA==.Vlysham:BAAALgAECgMJAwABLgAECgYJCQAHAAAAAA==.Vlythyr:BAAALgAECgYJCQAAAA==.Vlyzen:BAAALgAECgQJBQABLgAECgYJCQAHAAAAAA==.',
Vo='Voidhearted:BAABLgAECn85AAICAAgJ2x4KDwBDAgACAAgJ2x4KDwBDAgAAAA==.',
Vu='Vulpy:BAAALgAECgEJAQABLgAECggJEgAHAAAAAA==.',
['Vì']='Vìolet:BAAALgAECgYJEwABLgAECggJLwAIADsiAA==.',
['Ví']='Víolet:BAAALgAECgYJBgAAAA==.',
Wa='Waggleton:BAAALgAECgEJAgAAAA==.Warp:BAAALgADCgEJAQAAAA==.Washyourasz:BAAALgAECgYJCgAAAA==.Wasted:BAAALgADCgEJAQABLgAECgkJLgARALYgAA==.Wayshua:BAAALgAECgUJBwAAAA==.',
We='Wearyouout:BAAALgADCgUJBQAAAA==.Wemon:BAAALgAECgUJBQAAAA==.Werkajerk:BAABLgAECn8wAAQaAAkJaCMBBQDYAgAaAAgJICQBBQDYAgAbAAEJ6yPobQBpAAAcAAEJwBdFdABEAAABLgAFFAUJFgASAAIlAA==.Werkjathal:BAACLgAFFH8WAAQSAAUJAiVlAwC1AQASAAQJAiVlAwC1AQAoAAUJeSN5AgCBAQARAAMJoAyqGwCKAAAuAAQKfzQABCgACQnFJZwAAEoDACgACQkOJJwAAEoDABIACAknIxkOAMICABEABwnDI4oNAK8CAAAA.Wetribs:BAAALgADCgkJCQAAAA==.',
Wh='Whereareyou:BAAALgADCgkJCQABLgAECgYJFgAUAPoYAA==.Whitedog:BAAALgAECgEJAQAAAA==.Whitetank:BAABLgAECn8gAAIVAAgJBhlhDwCgAQAVAAgJBhlhDwCgAQAAAA==.',
Wi='Willowbeard:BAAALgAECggJDwAAAA==.Winnelepooh:BAAALgADCgQJBAAAAA==.Winnithebrew:BAAALgAECgEJAQAAAA==.',
Wo='Wobys:BAABLgAECn8dAAIbAAgJWRT3KwCCAQAbAAgJWRT3KwCCAQAAAA==.Wolfblitzer:BAABLgAECn8zAAINAAkJchqnHAB7AgANAAkJchqnHAB7AgAAAA==.Wolfmanbro:BAAALgADCggJCAAAAA==.Worldbane:BAABLgAECn8yAAImAAgJXBRuBwCuAQAmAAgJXBRuBwCuAQAAAA==.',
['Wä']='Wärchild:BAAALgAECgQJBAAAAA==.',
Xa='Xalaa:BAAALgAECgYJCgAAAA==.Xalataxfraud:BAAALgAECgQJBAAAAA==.Xanin:BAAALgAECgIJAgABLgAECgMJAwAHAAAAAA==.Xanthos:BAAALgAECgUJDAAAAA==.',
Xe='Xenthriel:BAAALgADCgcJDQAAAA==.',
Xi='Xianyu:BAABLgAECn8YAAIaAAYJaQqqQgDTAAAaAAYJaQqqQgDTAAAAAA==.Ximmer:BAAALgAECgEJAQAAAA==.',
Xr='Xrispy:BAAALgAECgQJBwABLgAECgkJLgARALYgAA==.',
Ya='Yarian:BAAALgAECgMJAwAAAA==.',
Yo='Yormin:BAAALgAECgUJEQAAAA==.Yorra:BAAALgAECgIJAgAAAA==.',
Yu='Yuzuu:BAABLgAECn8vAAIRAAgJag1XSQBVAQARAAgJag1XSQBVAQAAAA==.',
Za='Zachhunter:BAABLgAFFH8TAAMUAAcJuRvBDACWAQAUAAUJaxzBDACWAQAWAAYJJBGUDABKAQAAAA==.Zan:BAACLgAFFH8TAAMSAAUJsxGdGgAYAQASAAUJsxGdGgAYAQARAAIJ4hAuGQCXAAAuAAQKfy4AAxIACAmZH6wTAIICABIACAmZH6wTAIICABEAAgmgC8OJAG0AAAAA.',
Zo='Zohaan:BAAALgADCgEJAwAAAA==.Zoma:BAAALgADCggJDgAAAA==.',
Zu='Zuhura:BAAALgAECgUJCwAAAA==.Zultrix:BAAALgAECgYJEAAAAA==.',
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
