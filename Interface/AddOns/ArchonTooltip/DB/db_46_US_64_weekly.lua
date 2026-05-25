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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','Warrior-Protection','Unknown-Unknown','Warrior-Fury','Druid-Feral','Paladin-Retribution','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Mage-Frost','Monk-Brewmaster','Evoker-Devastation','Druid-Restoration','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Devourer','Warrior-Arms','DeathKnight-Blood','Shaman-Elemental','Druid-Guardian','Priest-Discipline','DeathKnight-Unholy','Rogue-Outlaw','Monk-Mistweaver','Druid-Balance','Paladin-Holy','Rogue-Assassination','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Vengeance','Mage-Arcane','Paladin-Protection','Warlock-Affliction','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aamix:BAACLgAFFH8RAAIBAAUJJBWIPQApAQABAAUJJBWIPQApAQAuAAQKfysAAwEACQn/HvoZALkCAAEACQn/HvoZALkCAAIAAQkAAL1+ABsAAAAA.Aarom:BAACLgAFFH8QAAIDAAYJfx96AgDbAQADAAYJfx96AgDbAQAuAAQKfxUAAgMABwktF18kAGUBAAMABwktF18kAGUBAAAA.',
Ab='Abdltdoc:BAAALgAECgIJAgABLgAECgYJHAAEAGgiAA==.Abdltzach:BAAALgAECgEJAQABLgAECgYJHAAEAGgiAA==.Abhark:BAAALgAECgYJCQAAAA==.',
Ac='Acemonk:BAAALgAECgkJDgAAAA==.Achifee:BAAALgAECgQJBgAAAA==.',
Ad='Aderan:BAAALgAECgQJBAAAAA==.Adragen:BAAALgAECgUJBQABLgAFFAIJAwAFAAAAAA==.',
Ae='Aelyn:BAAALgADCgUJBQAAAA==.Aeni:BAAALgAECgQJBQAAAA==.Aerius:BAAALgAECgUJCAAAAA==.',
Ai='Aingerfal:BAABLgAECn8oAAIGAAgJ6wh5NwBDAQAGAAgJ6wh5NwBDAQAAAA==.',
Ak='Akasori:BAABLgAECn8rAAIHAAgJ5x8SBQB7AgAHAAgJ5x8SBQB7AgAAAA==.Akira:BAABLgAECn8pAAIIAAgJ3x1JIQBiAgAIAAgJ3x1JIQBiAgAAAA==.Akisori:BAAALgAECgUJBgABLgAECggJKwAHAOcfAA==.Akorang:BAAALgADCgkJDAAAAA==.Akosori:BAAALgAECgUJBgABLgAECggJKwAHAOcfAA==.Akunohana:BAAALgADCgcJCAAAAA==.',
Al='Alixx:BAAALgADCgQJBAAAAA==.Alkein:BAAALgAECgMJAwAAAA==.Allnaturale:BAAALgAECgYJDwAAAA==.Alîsonshammy:BAACLgAFFH8NAAIJAAYJdhywBQAYAgAJAAYJdhywBQAYAgAuAAQKfyAAAgkACAnPIXEIAO8CAAkACAnPIXEIAO8CAAAA.',
Am='Ambersulfr:BAABLgAECn8qAAIKAAgJ1xyXBgA9AgAKAAgJ1xyXBgA9AgAAAA==.Ammarianar:BAAALgAECgMJAwABLgAECgkJFwALAFkJAA==.Amrazz:BAABLgAECn87AAMMAAkJyx3kBgDjAgAMAAkJyx3kBgDjAgANAAMJPBH4VACGAAAAAA==.Amzey:BAEBLgAECn8tAAIOAAkJGSNsEgDSAgAOAAkJGSNsEgDSAgAAAA==.',
An='Anahata:BAAALgAECgMJAwAAAA==.Anari:BAABLgAECn8eAAMPAAgJzwg1NQAMAQADAAYJcwmGPwAcAQAPAAgJtAc1NQAMAQAAAA==.Andromeda:BAABLgAECn81AAIGAAkJCxnpFAAlAgAGAAkJCxnpFAAlAgAAAA==.Andrömalius:BAAALgADCgQJBAAAAA==.Anowon:BAAALgADCgQJBAAAAA==.Anridel:BAAALgADCgIJAgAAAA==.Antimortem:BAAALgAECgEJAQAAAA==.Antwerpen:BAAALgAECgEJBAAAAA==.Anyiaa:BAAALgADCgUJBQAAAA==.',
Ar='Arakis:BAAALgADCgcJEgABLgAECgkJPgAQALQhAA==.Arcacia:BAAALgADCgQJBAAAAA==.Aridillo:BAAALgAECgUJBwAAAA==.Arkanum:BAABLgAECn8VAAICAAYJeg9YEQADAQACAAYJeg9YEQADAQAAAA==.Arstarte:BAAALgAECgEJAQAAAA==.Artemai:BAAALgAECgYJCQAAAA==.',
As='Ashaka:BAABLgAECn8gAAMJAAgJlSOqDQDAAgAJAAcJUySqDQDAAgAKAAEJIBt4KQBQAAAAAA==.Ashylarry:BAAALgADCgYJDQAAAA==.Askthedm:BAAALgAECgQJBAAAAA==.Astralus:BAABLgAECn8fAAIOAAgJCxiRXgAfAgAOAAgJCxiRXgAfAgAAAA==.Astramis:BAABLgAECn8nAAIOAAgJswTNoAAgAQAOAAgJswTNoAAgAQAAAA==.',
At='Atomicbarbie:BAAALgAECgMJBAABLgAFFAYJDQAJAHYcAA==.',
Au='Aucee:BAABLgAECn8eAAIIAAgJaxomLgAmAgAIAAgJaxomLgAmAgAAAA==.',
Av='Avioradoramo:BAAALgADCgEJAQAAAA==.',
Az='Azariah:BAAALgADCgYJDQAAAA==.',
Ba='Babybuu:BAABLgAECn8oAAIRAAgJ9hzTEwCKAgARAAgJ9hzTEwCKAgAAAA==.Backlash:BAAALgAFFAEJAQAAAA==.Baluho:BAAALgADCgIJAgAAAA==.Balzhac:BAAALgAECgQJBQAAAA==.Bam:BAAALgADCgcJBwABLgAFFAcJGQASAPkaAA==.Bambamcdn:BAAALgADCgEJAQAAAA==.',
Be='Beleaf:BAAALgAECgQJBAAAAA==.Bellmonte:BAAALgAECgEJAQABLgAECgkJPgAQALQhAA==.Belmonk:BAAALgADCgEJAQAAAA==.Berdron:BAABLgAECn87AAIBAAkJ+AiGXABzAQABAAkJ+AiGXABzAQAAAA==.Bessy:BAAALgAECgYJCwAAAA==.Bexton:BAABLgAECn85AAIEAAkJEBxxBwBpAgAEAAkJEBxxBwBpAgAAAA==.',
Bi='Bicchoi:BAABLgAECn8XAAIDAAcJ2h1yEgBiAgADAAcJ2h1yEgBiAgAAAA==.Bigbare:BAAALgADCgcJBwAAAA==.Bigripper:BAAALgADCgcJBwAAAA==.',
Bl='Blackdot:BAABLgAECn8iAAMMAAkJ4heVEAA9AgAMAAkJ4heVEAA9AgANAAUJiwJ1UgB/AAAAAA==.Blazin:BAABLgAECn8eAAQTAAcJTAumOQANAQATAAYJ+gumOQANAQAUAAQJLwOjMABGAAAQAAIJ3AUrHwA6AAAAAA==.Bleddyn:BAAALgAECgYJBwAAAA==.Bledsmasher:BAABLgAECn8kAAIVAAgJQhNDRgCSAQAVAAgJQhNDRgCSAQAAAA==.Blindmonkey:BAAALgADCgcJDgAAAA==.Blinkss:BAAALgAECgEJAgAAAA==.Bloodied:BAAALgAECgMJAwAAAA==.Blouses:BAACLgAFFH8bAAMGAAcJlyDwAABUAgAGAAcJlyDwAABUAgAWAAIJZBHbHwCbAAAuAAQKfyUAAgYACQmSI/IEAFkDAAYACQmSI/IEAFkDAAAA.',
Bo='Bobowild:BAABLgAECn8fAAIRAAgJUxVBKADuAQARAAgJUxVBKADuAQAAAA==.Boltthrower:BAAALgAECgQJCQAAAA==.Bonbons:BAAALgAECgYJEgAAAA==.Boned:BAABLgAECn8tAAIPAAgJ9R0qDABTAgAPAAgJ9R0qDABTAgAAAA==.Bonemair:BAACLgAFFH8NAAIXAAUJZxsgEAAvAQAXAAUJZxsgEAAvAQAuAAQKfxgAAhcACAnAH3ILACkCABcACAnAH3ILACkCAAEuAAUUBgkaAA8ADh0A.Bonezey:BAEALgAECggJEgABLgAECgkJLQAOABkjAA==.Boomerkin:BAAALgAECgIJAgABLgAFFAQJEQAYAJQRAA==.Boricuazo:BAAALgAECgQJBAAAAA==.Bovityre:BAABLgAECn8WAAIJAAcJMhmLJwDzAQAJAAcJMhmLJwDzAQAAAA==.Bowjangles:BAAALgADCgEJAQAAAA==.Bowser:BAAALgAECgcJCgAAAA==.',
Bu='Bubblebath:BAAALgAECgYJBwABLgAFFAIJAgAFAAAAAA==.Bubblecuddle:BAAALgAECgEJAQAAAA==.Bubblehooker:BAAALgAFFAIJAgAAAA==.Bubbs:BAAALgADCgcJBwAAAA==.Buffnbeers:BAAALgADCgkJEQABLgAFFAYJDgAZABoZAA==.Buffydemon:BAAALgADCgIJAgABLgAECgcJHQAIACkaAA==.Buffypaladin:BAABLgAECn8dAAIIAAcJKRqlXADNAQAIAAcJKRqlXADNAQAAAA==.Buffyrogue:BAAALgAECgYJDAAAAA==.Buffyshaman:BAAALgADCgEJAQABLgAECgcJHQAIACkaAA==.Buhger:BAAALgADCgUJBQAAAA==.Buldy:BAAALgAECgcJCAAAAA==.Bup:BAABLgAECn8lAAQaAAgJ/x66DgBQAgAaAAcJsiC6DgBQAgAMAAQJFxoWWADVAAANAAEJRAbTdwApAAAAAA==.Bups:BAAALgAECgEJAQAAAA==.Burning:BAAALgAECgYJEgAAAA==.Buttjuggles:BAAALgAECgQJBAAAAA==.',
Bw='Bwonurjor:BAAALgADCgUJBQAAAA==.',
Ca='Caldec:BAACLgAFFH8iAAIbAAgJgyQaAQDmAgAbAAgJgyQaAQDmAgAuAAQKfyYAAhsACQmcJnkAAO4DABsACQmcJnkAAO4DAAAA.Caldh:BAABLgAECn8cAAIVAAgJfB68LgDsAQAVAAgJfB68LgDsAQABLgAFFAgJIgAbAIMkAA==.Cardian:BAAALgAECgUJDQAAAA==.Casstiel:BAAALgAECgUJCAAAAA==.Catdog:BAAALgADCgYJDAABLgAFFAMJCAAKAFUTAA==.',
Ce='Cegro:BAAALgAECgkJEQAAAA==.',
Ch='Chainizard:BAACLgAFFH8cAAQUAAUJKRyoDgByAQAUAAUJKRyoDgByAQATAAEJyBbuSwBKAAAQAAEJgwFTDQAqAAAuAAQKfycAAhQACQnRIHEGANwCABQACQnRIHEGANwCAAAA.Chainsmash:BAAALgAECgUJBwABLgAFFAUJHAAUACkcAA==.Chainter:BAAALgAECgEJAQABLgAFFAUJHAAUACkcAA==.Chamonix:BAABLgAECn8eAAIJAAgJ2xdwIQAZAgAJAAgJ2xdwIQAZAgAAAA==.Chaoticlord:BAAALgAECgQJBQABLgAECgYJGwAaABULAA==.Chaoticrandy:BAAALgADCgYJBgAAAA==.Cheeno:BAACLgAFFH8GAAIVAAMJrxjmGAAIAQAVAAMJrxjmGAAIAQAuAAQKfygAAhUACQkyI5gNABMDABUACQkyI5gNABMDAAAA.Chillyblinks:BAACLgAFFH8MAAIOAAUJ6A1TUgAjAQAOAAUJ6A1TUgAjAQAuAAQKfyUAAg4ACAmNIfEkAN8CAA4ACAmNIfEkAN8CAAAA.Chillywings:BAAALgAECgIJAgABLgAFFAUJDAAOAOgNAA==.Chinchillagg:BAAALgAECgUJCAABLgAFFAUJDAAOAOgNAA==.Chojii:BAAALgADCgcJDQAAAA==.Choryrth:BAAALgAECgYJDQAAAA==.Chubbymuffin:BAAALgAECggJCAAAAA==.',
Ci='Circuitry:BAABLgAECn8eAAIJAAgJ9h+CCwDZAgAJAAgJ9h+CCwDZAgAAAA==.',
Co='Congruent:BAACLgAFFH8IAAIJAAMJFhZpOQDHAAAJAAMJFhZpOQDHAAAuAAQKfxQAAwkACAn7GbYzALUBAAkABwljGLYzALUBAAoAAQkYJcslAGoAAAAA.Cootin:BAAALgADCgEJAgAAAA==.Coriolanus:BAAALgADCgUJBAAAAA==.Cornnmuffin:BAAALgAECgUJBgAAAA==.Corvus:BAAALgAECggJCAAAAA==.',
Cr='Crane:BAABLgAECn8ZAAIPAAgJOhjVHgALAgAPAAgJOhjVHgALAgAAAA==.Crelam:BAACLgAFFH8oAAIKAAgJFQ2JAAAWAgAKAAgJFQ2JAAAWAgAuAAQKfyQAAgoACQnEGoIEANICAAoACQnEGoIEANICAAAA.Critz:BAAALgAECgcJEgAAAA==.Cronatherus:BAAALgAECgMJAwAAAA==.Cruentis:BAABLgAECn86AAIcAAkJdx3WAQCcAgAcAAkJdx3WAQCcAgAAAA==.Crymsonroze:BAAALgAECgMJAwAAAA==.Crysus:BAAALgAECgYJEwAAAA==.',
Cu='Curruptor:BAAALgADCgIJAgAAAA==.',
Cy='Cybernome:BAAALgAECgYJCgAAAA==.Cyncyn:BAAALgADCgYJBgAAAA==.',
Da='Dachiang:BAAALgAECgEJAwAAAA==.Damarisalynn:BAAALgAECgUJBQAAAA==.Dangus:BAABLgAECn8qAAQDAAkJNxkMEAAkAgADAAkJnxgMEAAkAgAPAAUJ5wpqUQChAAAdAAEJlwdfbgAnAAAAAA==.Danifarian:BAABLgAECn8eAAMQAAgJChgNDQAJAgAQAAgJ/xQNDQAJAgATAAYJmRP3KAB2AQABLgAFFAkJJgAFAAAAAA==.Dankeydemon:BAAALgADCgMJAwAAAA==.Danthrox:BAAALgADCgEJAQAAAA==.Darthneepis:BAAALgAECgcJDgAAAA==.Darthplot:BAAALgADCgMJAwAAAA==.Darwin:BAABLgAECn8lAAMbAAgJ0hd/RADTAQAbAAgJ0hd/RADTAQALAAEJgQdULgAnAAAAAA==.Dasmoodhayn:BAAALgAECgYJCwAAAA==.Davalanch:BAAALgAECgkJCQAAAA==.Davrock:BAAALgAECgcJBwABLgAECgkJCQAFAAAAAA==.Dawnglaive:BAAALgAFFAEJAQAAAA==.Dayo:BAABLgAECn8fAAIIAAgJZiWvKACCAgAIAAgJZiWvKACCAgAAAA==.',
De='Deathstorm:BAAALgADCgcJBwABLgAECgkJHwAHAJwYAA==.Demondot:BAAALgAECgYJBgAAAA==.Dethkløk:BAAALgAECgcJEAAAAA==.',
Di='Dibstrum:BAAALgAECggJEwAAAA==.Dimaa:BAAALgAECgkJBwAAAA==.Dixqt:BAAALgAFFAEJAQAAAA==.',
Dj='Djinn:BAAALgAECgMJAwAAAA==.',
Do='Dogbear:BAAALgADCgIJAgAAAA==.Dogfight:BAACLgAFFH8YAAIbAAQJ4SH7IwCGAQAbAAQJ4SH7IwCGAQAuAAQKfx4AAhsACQmOIzkZAOUCABsACQmOIzkZAOUCAAAA.Doilookfatou:BAABLgAECn8bAAMZAAYJlBvVEgCHAQAZAAYJlBvVEgCHAQAeAAQJEQ0fXwClAAAAAA==.Doopy:BAAALgADCgMJAwAAAA==.',
Dr='Draedawn:BAAALgADCgQJBAAAAA==.Dragonhide:BAABLgAECn8jAAIIAAgJCw5hcQBrAQAIAAgJCw5hcQBrAQAAAA==.Drailzx:BAAALgAECgYJDAAAAA==.Drakelle:BAAALgADCgIJAgAAAA==.Drakhon:BAAALgAECgYJBgABLgAECggJLgAfANAWAA==.Draxus:BAABLgAECn8WAAIgAAYJyggEEQDzAAAgAAYJyggEEQDzAAAAAA==.Drbigsbie:BAAALgAECgYJCwAAAA==.Dresel:BAACLgAFFH8eAAMhAAgJmx8oAAD4AQAhAAgJmx8oAAD4AQAiAAMJ7g4DIgCFAAAuAAQKfygABCEACQnMJj8AAOgDACEACQnMJj8AAOgDACIABwloHHUxAKsBACMAAgn9BfgpAGEAAAAA.Drewpeebahlz:BAAALgAECgYJDwABLgAECgkJOAAhAN4kAA==.Drezell:BAAALgADCgcJBwABLgAFFAgJHgAhAJsfAA==.Druidickhal:BAACLgAFFH8OAAMRAAQJwx4BJwAAAQARAAMJVx4BJwAAAQAeAAQJbQxXDwDsAAAuAAQKfxkAAxEACAlUHGEqAAgCABEACAlUHGEqAAgCAB4ABQlfIv8uAI4BAAAA.Druindabs:BAAALgADCgUJBQAAAA==.Drybussy:BAAALgAECgMJAwAAAA==.',
Du='Dunarith:BAAALgADCgMJAwAAAA==.Dunkel:BAAALgADCgUJBQAAAA==.',
Dw='Dwarvenlight:BAAALgAECgEJAQAAAA==.',
Dy='Dyami:BAACLgAFFH8KAAMhAAMJohw9OgD+AAAhAAMJohw9OgD+AAAiAAIJbwYeKQBFAAAuAAQKfzsAAyEACQkKJIUEACwDACEACQkKJIUEACwDACIABAlSGdFFAD4BAAAA.Dynas:BAABLgAECn8xAAMMAAgJdRqeDwBIAgAMAAgJdRqeDwBIAgAaAAYJ/REqJgBkAQAAAA==.',
Ea='Earthcake:BAACLgAFFH8RAAMYAAQJlBEUGQAfAQAYAAQJlBEUGQAfAQAJAAMJVw/VPAC8AAAuAAQKfzYAAxgACQn6Ib4GANICABgACQn6Ib4GANICAAkAAgnVDL6qADwAAAAA.',
Ed='Eddiebkshots:BAAALgAFFAEJAgABLgAFFAgJIQAbAHcdAA==.Eddiechi:BAABLgAFFH8KAAMPAAUJyCHmBADxAQAPAAUJyCHmBADxAQADAAEJ3xZQLQBJAAABLgAFFAgJIQAbAHcdAA==.Eddiedecay:BAAALgAECgUJBQABLgAFFAgJIQAbAHcdAA==.Eddielich:BAACLgAFFH8hAAMbAAgJdx1NAgDyAQAXAAcJkh2XAgA3AgAbAAcJYBtNAgDyAQAuAAQKfzcAAxsACQlxJaAHAGMDABsACQlpJaAHAGMDABcACQnCJD8CABgDAAAA.Eddiepope:BAAALgAFFAIJAgABLgAFFAgJIQAbAHcdAA==.Eddiewar:BAAALgAECgYJDwABLgAFFAgJIQAbAHcdAA==.',
Eg='Eggfumonk:BAAALgAECgQJCgABLgAECgYJBwAFAAAAAA==.',
El='Elbodeep:BAAALgAECgQJBAAAAA==.Elfpen:BAABLgAECn8VAAIfAAYJix4PHAD8AQAfAAYJix4PHAD8AQAAAA==.Elgaux:BAAALgADCgQJBAAAAA==.',
En='Enhancesmexy:BAAALgAECgYJBgABLgAECgYJBgAFAAAAAA==.Ents:BAAALgAECgYJDQAAAA==.',
Eq='Eqwene:BAAALgADCgkJCQAAAA==.',
Er='Erragal:BAAALgAECgYJEgAAAA==.Eryunes:BAAALgAECgMJAwAAAA==.',
Es='Escanoor:BAAALgADCgcJBwAAAA==.',
Et='Et:BAAALgAFFAMJAwABLgAFFAgJDAAEALIZAA==.',
Eu='Euthariel:BAABLgAECn8bAAMbAAcJ/BbUgAA8AQAbAAcJ/BbUgAA8AQALAAQJahKnGQC4AAAAAA==.Euthindor:BAAALgAECgYJDgAAAA==.',
Ev='Evilwench:BAABLgAECn8XAAINAAcJTg3OLgBrAQANAAcJTg3OLgBrAQAAAA==.',
Fa='Faelgan:BAAALgADCgIJAQAAAA==.Faexi:BAAALgADCgMJAgAAAA==.Falek:BAAALgADCgUJBQAAAA==.Farrstrider:BAAALgAECgYJBwAAAA==.Favii:BAAALgADCggJHAAAAA==.',
Fe='Feefiefoéfum:BAAALgAECgMJAwAAAA==.Felosophical:BAAALgAECgMJAwAAAA==.Felstórm:BAAALgADCgcJBwAAAA==.Felurián:BAABLgAECn8dAAMVAAcJpRTVVABlAQAVAAcJYhTVVABlAQAkAAIJFxFgIgBcAAAAAA==.Felyzia:BAAALgAECgEJBAABLgAECgkJOgAGAB4cAA==.Fexli:BAABLgAECn8VAAIhAAYJEg+HdAAoAQAhAAYJEg+HdAAoAQAAAA==.',
Fi='Fiber:BAAALgADCgUJBgAAAA==.Fireteeth:BAAALgAECgEJBQAAAA==.Fizc:BAAALgADCgcJBwAAAA==.',
Fl='Flojo:BAAALgAFFAEJAQAAAA==.Flvx:BAAALgAFFAEJAQAAAA==.',
Fo='Folklore:BAABLgAECn8fAAMZAAgJJBUQFwBZAQAZAAgJFxUQFwBZAQAHAAUJzw/0HgDUAAAAAA==.Forbidi:BAAALgAECgMJBgAAAA==.',
Fr='Freaky:BAAALgAFFAEJAQAAAA==.Frostitoot:BAAALgAECgkJCQABLgAECgYJBgAFAAAAAA==.Frostytute:BAAALgAECgUJCgAAAA==.Frozown:BAABLgAECn8oAAIOAAgJ3RsULwA+AgAOAAgJ3RsULwA+AgAAAA==.Fruits:BAABLgAECn8ZAAQYAAgJChn1JgCHAQAYAAcJshn1JgCHAQAJAAQJixAHdQDCAAAKAAIJSBlgJAB3AAAAAA==.',
Fu='Fumanchu:BAAALgADCgMJAwAAAA==.Funfanfare:BAABLgAECn8eAAIlAAgJRxncAgDuAQAlAAgJRxncAgDuAQAAAA==.Furryfister:BAAALgADCgEJAQAAAA==.',
Fy='Fyvern:BAAALgADCgUJBQAAAA==.',
['Fò']='Fòrlorn:BAAALgAECgEJAgAAAA==.',
['Fö']='Fölktergeist:BAABLgAECn8ZAAIJAAcJFBJTRQBlAQAJAAcJFBJTRQBlAQAAAA==.',
Ga='Gaea:BAAALgADCgEJAQAAAA==.Galaeline:BAAALgADCgkJDQAAAA==.Galram:BAABLgAECn83AAIjAAkJjRhxCgBfAgAjAAkJjRhxCgBfAgABLgAFFAgJKAAKABUNAA==.Gargingoyles:BAACLgAFFH8FAAIbAAIJ8ht+jQCyAAAbAAIJ8ht+jQCyAAAuAAQKfzkAAhsABwlRJf0YAOYCABsABwlRJf0YAOYCAAAA.Garlicbred:BAAALgAECgQJCAABLgAFFAYJDQAJAHYcAA==.Gartholo:BAAALgAECgcJDQABLgAECgkJCQAFAAAAAA==.Garunah:BAABLgAECn8UAAMRAAYJ4xQkVQAaAQARAAYJ4xQkVQAaAQAeAAYJXg7NOwDwAAAAAA==.',
Ge='Gemma:BAAALgAECgIJAgAAAA==.',
Gh='Ghoststalker:BAAALgAFFAIJAgABLgAFFAMJBwAGAOcaAA==.',
Gi='Gimpwithmilk:BAABLgAECn8ZAAIRAAkJcwnuWAAMAQARAAkJcwnuWAAMAQAAAA==.Gip:BAAALgAECgMJBQAAAA==.Giselee:BAAALgADCgEJAQAAAA==.Gisellina:BAABLgAECn8jAAIhAAkJyBkIKAAYAgAhAAkJyBkIKAAYAgAAAA==.Gizzbos:BAAALgADCgUJBQAAAA==.',
Gl='Gladiatorz:BAAALgAECgcJEgABLgAECggJIwAIAAsOAA==.Glimmair:BAAALgAECgYJBgABLgAFFAYJGgAPAA4dAA==.Glimmer:BAAALgAFFAEJAQAAAQ==.Glo:BAABLgAECn8UAAIJAAYJkg2DXQAMAQAJAAYJkg2DXQAMAQAAAA==.',
Gn='Gnxrly:BAAALgAFFAMJAwAAAA==.',
Go='Gokuz:BAAALgAECgYJDgAAAA==.Goo:BAAALgAECgQJBAAAAA==.Goopn:BAAALgADCgEJAQAAAA==.Gorbstrasz:BAAALgADCgEJAQAAAA==.',
Gr='Gregorz:BAABLgAECn8VAAIhAAYJixu9SwCRAQAhAAYJixu9SwCRAQAAAA==.Grelda:BAAALgADCgEJAQAAAA==.Greyanna:BAABLgAECn8VAAIhAAgJrgS+dgAjAQAhAAgJrgS+dgAjAQAAAA==.Grilka:BAAALgAECgEJAQABLgAECgEJAQAFAAAAAA==.Grimmnír:BAAALgAECgMJAwABLgAFFAgJKAAUANQcAA==.Grimrath:BAABLgAECn8aAAIBAAgJtAzedwA0AQABAAgJtAzedwA0AQAAAA==.Gromthrall:BAAALgAECgQJBAAAAA==.Grumpydik:BAAALgAECgYJBgAAAA==.Grumpzilla:BAAALgAECgYJEQAAAA==.',
Gu='Gumdrops:BAAALgAECgYJEgAAAA==.Gurglem:BAAALgADCgEJAQAAAA==.Gurthrot:BAACLgAFFH8IAAIbAAIJ1Rh8owCVAAAbAAIJ1Rh8owCVAAAuAAQKfyYAAhsACAkuIMEqADICABsACAkuIMEqADICAAAA.',
Gw='Gworp:BAAALgADCgEJAQAAAA==.Gwynhwyfar:BAABLgAECn8aAAIeAAgJ7wn5MQAjAQAeAAgJ7wn5MQAjAQAAAA==.',
Gy='Gyozom:BAAALgAECgUJBQAAAA==.',
['Gü']='Güanentá:BAAALgAECgMJAwAAAA==.',
Ha='Haseo:BAAALgADCgcJBwAAAA==.',
Hb='Hbhealthen:BAACLgAFFH8oAAMUAAgJ1ByTAwBYAgAUAAcJohuTAwBYAgATAAEJfQbCSgBTAAAuAAQKf0AAAxQACQmkJH8BAG8DABQACQmkJH8BAG8DABMAAgkjCvxoAGgAAAAA.Hbheathend:BAAALgAECgcJDwABLgAFFAgJKAAUANQcAA==.',
He='Heavie:BAAALgADCgYJCAAAAA==.Hellhore:BAAALgAECgYJDQAAAA==.',
Hi='Highego:BAAALgAECgMJAwAAAA==.Hitmen:BAAALgAECgcJAQAAAA==.Hitta:BAAALgAECgMJBAABLgAECgQJBwAFAAAAAA==.',
Hj='Hjüdas:BAAALgAECgkJCAAAAA==.',
Ho='Hobo:BAAALgAECgEJAgAAAA==.Hobodruid:BAAALgAECgEJAQAAAA==.Holdenc:BAAALgAECgcJEAABLgAECggJGwAJADUVAA==.Holyrandy:BAABLgAECn8uAAIIAAkJhhaSNgAGAgAIAAkJhhaSNgAGAgAAAA==.Honourabull:BAAALgADCgEJAQABLgAFFAQJCAAaACYgAA==.Hoodz:BAABLgAFFH8GAAIWAAMJ4hrEFgDjAAAWAAMJ4hrEFgDjAAAAAA==.Horsecack:BAAALgADCgEJAQAAAA==.Hotzalot:BAAALgAECgYJBgAAAA==.Houla:BAAALgAECgYJCQAAAA==.Howard:BAABLgAECn8dAAMYAAgJhwivNgAuAQAYAAgJhwivNgAuAQAJAAYJiQ9yYQAGAQAAAA==.',
Hu='Huatli:BAAALgAECgEJAQAAAA==.Hugerod:BAAALgAECgEJAgAAAA==.Hukhano:BAAALgADCgEJAQAAAA==.Hurcolo:BAAALgAECgEJAgAAAA==.Hurtan:BAAALgAECgUJBQAAAA==.Huulotta:BAAALgADCgIJAgAAAA==.',
Ia='Ianth:BAAALgAECgUJBgAAAA==.',
Ib='Ibearprofen:BAAALgAECgUJDgAAAA==.Iblees:BAAALgAECggJEAAAAA==.',
Ic='Ichthyosis:BAABLgAECn8XAAMLAAkJWQnxEwD4AAAbAAgJqAhSrgAlAQALAAcJvQjxEwD4AAAAAA==.Icë:BAAALgAECgYJCQAAAA==.',
Id='Idtrapdat:BAABLgAFFH8GAAIhAAMJQRlSNwAJAQAhAAMJQRlSNwAJAQABLgAFFAMJBwAVAEUWAA==.',
Il='Illidarya:BAAALgAECgkJEQAAAA==.Illyana:BAABLgAECn8UAAIXAAcJLSEgDgArAgAXAAcJLSEgDgArAgAAAA==.Ilovetofish:BAAALgAECgEJAQAAAA==.Ilse:BAABLgAECn8wAAMfAAgJdR8LDgCNAgAfAAgJdR8LDgCNAgAIAAIJwxXsAQGFAAAAAA==.',
Im='Imagined:BAABLgAECn8lAAIOAAgJHxxWPQAKAgAOAAgJHxxWPQAKAgABLgAECgkJMwAUAHgbAA==.',
In='Indihunter:BAAALgAECgEJAQAAAA==.Infidelity:BAAALgADCgUJBQABLgAECggJHQAYAIcIAA==.',
Is='Iskhan:BAAALgADCgkJCQABLgAECgYJCwAFAAAAAA==.',
It='Itsmxke:BAACLgAFFH8LAAIIAAUJkRdSDwCdAQAIAAUJkRdSDwCdAQAuAAQKfzMAAggACAmGJBgNAOICAAgACAmGJBgNAOICAAAA.',
Iv='Ivank:BAABLgAECn8lAAIBAAgJ2A+/UQCPAQABAAgJ2A+/UQCPAQAAAA==.Ivannalot:BAAALgAECgQJBQAAAA==.',
Ja='Jabunken:BAACLgAFFH8LAAIfAAQJ4BmjDgDsAAAfAAQJ4BmjDgDsAAAuAAQKfx8AAx8ACQkDIvQDADEDAB8ACQkDIvQDADEDAAgABAn+ETjqALsAAAAA.Jackiechaan:BAABLgAECn8VAAMdAAYJeg95PwAXAQAdAAYJeg95PwAXAQADAAQJEggzTwCdAAAAAA==.Jage:BAABLgAECn8WAAImAAkJ5gWcIwDrAAAmAAkJ5gWcIwDrAAAAAA==.Jakkul:BAAALgAECgYJBwAAAA==.Jarsham:BAAALgAECgYJDwAAAA==.Jaràdan:BAABLgAFFH8HAAIBAAMJNQetZwDHAAABAAMJNQetZwDHAAABLgAFFAMJCAAlAMAMAA==.',
Je='Jeff:BAACLgAFFH8GAAMWAAIJRhBlIwCEAAAGAAIJ3gmTNgCFAAAWAAIJwQtlIwCEAAAuAAQKfy4AAwYACQlRHJ4OAGYCAAYACQlRHJ4OAGYCABYACAklDbAhACgBAAAA.Jestian:BAAALgADCgMJAwAAAA==.',
Ji='Jiannaa:BAACLgAFFH8FAAIMAAMJGBkXFAD2AAAMAAMJGBkXFAD2AAAuAAQKfy0AAgwACAk0InALAJkCAAwACAk0InALAJkCAAAA.Jitzul:BAAALgADCgEJAQAAAA==.',
Jl='Jl:BAAALgAFFAcJAQABLgAFFAgJDAAEALIZAA==.',
Jo='Johnnyderp:BAAALgAECgIJAgAAAA==.Jook:BAABLgAFFH8FAAIOAAIJYRYrfgCjAAAOAAIJYRYrfgCjAAAAAA==.Joran:BAABLgAECn8UAAISAAYJigd4MQDDAAASAAYJigd4MQDDAAAAAA==.',
Ju='Jurisdiction:BAAALgAECgEJAgAAAA==.Justmage:BAAALgADCgEJAQABLgAECgMJAwAFAAAAAA==.Justmonk:BAAALgAECgMJAwAAAA==.',
Jw='Jwrs:BAAALgAECgYJBgAAAA==.',
Jy='Jyaki:BAAALgAECgEJAQAAAA==.',
Ka='Kabbala:BAAALgAECgkJCQABLgAECgkJMwAUAHgbAA==.Kaelana:BAABLgAECn8YAAIMAAgJ1hs5CgCpAgAMAAgJ1hs5CgCpAgAAAA==.Kahhlua:BAAALgADCgkJDQAAAA==.Kahlua:BAABLgAECn8+AAIhAAkJMBp0HgBGAgAhAAkJMBp0HgBGAgAAAA==.Kailan:BAABLgAECn8fAAIVAAYJLB7iPwCoAQAVAAYJLB7iPwCoAQABLgAFFAMJBwANALgPAA==.Kailani:BAABLgAECn8wAAMRAAkJJgwiOwCFAQARAAkJJgwiOwCFAQAeAAgJ2QvdOAD+AAAAAA==.Kaiserroll:BAAALgAECgEJAgABLgAECgEJAwAFAAAAAA==.Kaldro:BAAALgAECgUJBQAAAA==.Kaly:BAABLgAECn8yAAIPAAkJlg2IHQCaAQAPAAkJlg2IHQCaAQAAAA==.Karador:BAAALgAECgEJAQAAAA==.Karpriest:BAAALgADCgQJBAAAAA==.Kathry:BAAALgAECgIJAgAAAA==.',
Kc='Kcid:BAAALgAECggJDAAAAA==.',
Ke='Kedibaba:BAAALgAECgYJCwAAAA==.Keepdreaming:BAABLgAECn86AAQRAAkJOxM1LADWAQARAAkJOxM1LADWAQAHAAEJTQiNQAAtAAAeAAEJngPJhgAgAAAAAA==.Kefkka:BAAALgAECgUJBgAAAA==.Kellane:BAAALgAECgMJBQAAAA==.Keybricker:BAABLgAFFH8OAAIZAAYJGhn3AgCpAQAZAAYJGhn3AgCpAQAAAA==.Keymebrah:BAACLgAFFH8KAAIOAAUJwhSqQABDAQAOAAUJwhSqQABDAQAuAAQKfycAAg4ACAnLHPMuALYCAA4ACAnLHPMuALYCAAAA.',
Kh='Khaera:BAAALgADCgQJBAAAAA==.Khansi:BAAALgADCgUJBQAAAA==.',
Ki='Killeh:BAAALgADCggJCwAAAA==.',
Kl='Klassic:BAAALgAECgIJAgAAAA==.Kleiya:BAABLgAECn8zAAQUAAkJeBuEBADBAgAUAAkJeBuEBADBAgATAAYJFgqiSgDXAAAQAAEJKhniHABHAAAAAA==.',
Ko='Korda:BAAALgADCgMJAwAAAA==.Korinä:BAAALgAECgYJEAAAAA==.Korveen:BAABLgAECn8kAAINAAkJfQvKIACYAQANAAkJfQvKIACYAQAAAA==.Kosh:BAABLgAECn8VAAMnAAYJFhfdDQBHAQAnAAYJGBPdDQBHAQABAAYJ/BRTeAAzAQAAAA==.Koyra:BAACLgAFFH8kAAMQAAgJlh8dAAAmAgAQAAcJWiMdAAAmAgATAAUJGBxCCgDqAQAuAAQKfykAAxAACQm8JSEAAOwDABAACQm8JSEAAOwDABMABQnOHGkhALQBAAAA.',
Kr='Krimzin:BAAALgADCgEJAQABLgAFFAUJEQAhAAwdAA==.Krump:BAABLgAECn8pAAIEAAgJaBeiFQBzAQAEAAgJaBeiFQBzAQAAAA==.Krëyâdrón:BAAALgAECgIJAgAAAA==.',
Ku='Kubidari:BAAALgAECgEJAQAAAA==.Kubs:BAAALgADCgMJAwAAAA==.Kubwa:BAAALgAECgMJBAAAAA==.Kungfugimp:BAAALgADCgcJBwAAAA==.Kurral:BAACLgAFFH8UAAMeAAYJrhnoCACtAQAeAAYJrhnoCACtAQARAAEJYgAlZQAnAAAuAAQKfzEAAh4ACQlbIIEGAM8CAB4ACQlbIIEGAM8CAAAA.Kurralagos:BAABLgAECn8qAAQTAAgJhwqNNAA3AQATAAgJDAqNNAA3AQAQAAYJcArJIAAnAQAUAAQJ9gSGPwBuAAABLgAFFAYJFAAeAK4ZAA==.Kurstina:BAAALgAECgEJAQAAAA==.Kurtîmus:BAAALgAECgQJBwAAAA==.Kuznetsov:BAAALgADCgYJBgABLgAFFAQJEQAeAHoNAA==.Kuzushi:BAAALgAECgEJAQAAAA==.',
Ky='Kyramus:BAABLgAECn8pAAIEAAgJLSZhAgALAwAEAAgJLSZhAgALAwAAAA==.',
La='Laconia:BAABLgAECn8+AAMQAAkJtCEIAQDxAgAQAAkJtCEIAQDxAgATAAEJDA7cYwAvAAAAAA==.Landronor:BAAALgADCgQJBAABLgAECgYJDQAFAAAAAA==.Larox:BAAALgADCggJEQAAAA==.Lattsatnar:BAABLgAECn8XAAIGAAgJDBeoIgC4AQAGAAgJDBeoIgC4AQAAAA==.',
Le='Lennel:BAAALgAECgYJEwAAAA==.Lethaldread:BAAALgADCgIJAgABLgAECggJCQAFAAAAAA==.Leøn:BAAALgAECgYJCwAAAA==.',
Li='Lightbrite:BAAALgAECgMJAwAAAA==.Lightstorm:BAAALgAECgYJCwAAAA==.Lilarri:BAAALgAECgEJAQABLgAECgcJGgAdAEkbAA==.Lilsnick:BAAALgAECgIJAwABLgAECgkJJwABAPcHAA==.Lilyillidari:BAABLgAECn8iAAIkAAgJ9xuQBQAiAgAkAAgJ9xuQBQAiAgAAAA==.Litterbawx:BAAALgADCgYJBgAAAA==.Lizardlemons:BAAALgAECgYJEQAAAA==.',
Ll='Llanthyl:BAABLgAECn8hAAIGAAgJ2RtZFQAgAgAGAAgJ2RtZFQAgAgAAAA==.',
Lo='Lockbawx:BAAALgADCgIJAgABLgADCgYJBgAFAAAAAA==.Locosmexy:BAAALgAECgQJBAABLgAECgYJBgAFAAAAAA==.Lou:BAAALgAECgIJBAAAAA==.Lovia:BAAALgAECgIJAgAAAA==.Lowdps:BAAALgAFFAEJAgABLgAFFAcJFgAhABAbAA==.',
Lu='Luithica:BAAALgADCgUJBQAAAA==.Lunafalia:BAACLgAFFH8HAAIOAAMJ0wnZbQDZAAAOAAMJ0wnZbQDZAAAuAAQKfyoAAg4ACQmDFso9AAgCAA4ACQmDFso9AAgCAAAA.Lupon:BAAALgAECgkJAQAAAA==.Lurosa:BAACLgAFFH8aAAIRAAUJQhuODwCvAQARAAUJQhuODwCvAQAuAAQKfzsABBEACQnKIioIAAoDABEACQnKIioIAAoDAB4ACAlAHW0OAEwCABkABAmZH/0tAK4AAAAA.Luxeria:BAABLgAECn8nAAIIAAkJ2xn8KgAzAgAIAAkJ2xn8KgAzAgAAAA==.Luxlacertea:BAAALgAECggJCAAAAA==.',
Lz='Lz:BAABLgAFFH8MAAIEAAgJshlWAQBTAgAEAAgJshlWAQBTAgAAAA==.',
['Lí']='Lízard:BAAALgAECgQJBAAAAA==.',
['Lî']='Lîlydan:BAABLgAECn8UAAISAAYJ+xPgIQAuAQASAAYJ+xPgIQAuAQAAAA==.',
Ma='Maaz:BAAALgAECgUJBgABLgAECggJEAAFAAAAAA==.Macready:BAACLgAFFH8TAAIEAAUJRB4NCwBCAQAEAAUJRB4NCwBCAQAuAAQKfx8AAgQACAnSHykGANECAAQACAnSHykGANECAAAA.Madmimm:BAAALgADCgMJAwAAAA==.Maerith:BAAALgAECgYJEQAAAA==.Magenin:BAAALgAECgcJDwAAAA==.Mageqt:BAAALgAECggJCAABLgAECggJFwAeACAaAA==.Mahmage:BAACLgAFFH8YAAIOAAUJJyPrIgCXAQAOAAUJJyPrIgCXAQAuAAQKfysAAg4ACQm1JFcLAGkDAA4ACQm1JFcLAGkDAAAA.Mairbear:BAABLgAECn8UAAIZAAgJTB65BgBcAgAZAAgJTB65BgBcAgABLgAFFAYJGgAPAA4dAA==.Mairiachi:BAACLgAFFH8aAAIPAAYJDh3zBADvAQAPAAYJDh3zBADvAQAuAAQKfygAAg8ACQmQI88DAFIDAA8ACQmQI88DAFIDAAAA.Maloa:BAAALgAECgQJAgAAAA==.Marllowe:BAAALgAECgIJBAABLgAFFAUJEgAhADEVAA==.Marload:BAACLgAFFH8SAAIhAAUJMRUkJQA6AQAhAAUJMRUkJQA6AQAuAAQKfzcAAiEACQlfHw0MAOECACEACQlfHw0MAOECAAAA.Mathy:BAABLgAECn8yAAMKAAkJhx+9AgDGAgAKAAkJhx+9AgDGAgAJAAgJrBhaIgARAgAAAA==.Mazaker:BAAALgADCgEJAQAAAA==.',
Me='Mearis:BAAALgAECgMJAwABLgAECgkJMwAUAHgbAA==.Melath:BAAALgAECgUJBwAAAA==.Meld:BAAALgADCgEJAQAAAA==.Memesarecool:BAAALgAECgEJAQAAAA==.Meñtat:BAAALgAECgYJDgAAAA==.',
Mf='Mfdoom:BAAALgAECgQJCAAAAA==.',
Mi='Michael:BAAALgAECgQJBAAAAA==.Midletons:BAAALgAECgYJCQAAAA==.Midran:BAABLgAECn8VAAIjAAgJJRaMCQBKAgAjAAgJJRaMCQBKAgAAAA==.Minbari:BAAALgADCgcJFgABLgAECgYJFQAnABYXAA==.Minerva:BAAALgADCgMJAwAAAA==.Minttea:BAEALgAFFAEJAQABLgAFFAUJFgARAPYTAA==.Misfirë:BAABLgAECn8cAAIjAAgJ+hewFQDaAQAjAAgJ+hewFQDaAQAAAA==.',
Mo='Mojó:BAABLgAECn8XAAIeAAgJIBpqHAC3AQAeAAgJIBpqHAC3AQAAAA==.Momenta:BAAALgADCgEJAQAAAA==.Moobubble:BAAALgAECgYJBgABLgAFFAQJEQAYAJQRAA==.Moogul:BAAALgADCgUJBQAAAA==.Moonanoke:BAAALgADCgkJDgAAAA==.Moorawr:BAAALgADCgYJBgAAAA==.Moovoker:BAABLgAECn8xAAMTAAkJWyL+AwAYAwATAAgJGiL+AwAYAwAQAAMJFSGMIgAWAQAAAA==.Mordran:BAAALgADCgMJAwAAAA==.Morseques:BAACLgAFFH8IAAIbAAMJjiL6SwAyAQAbAAMJjiL6SwAyAQAuAAQKfykAAhsACQnEIocZAIsCABsACQnEIocZAIsCAAAA.Mortimirr:BAAALgAFFAIJAwAAAA==.Mortimur:BAAALgAFFAEJAQABLgAFFAIJAwAFAAAAAA==.Mozi:BAAALgAECgUJEwAAAA==.',
Mt='Mtotdps:BAAALgAECgYJEgAAAQ==.',
Mu='Muffins:BAAALgAECgUJCAAAAA==.Muggy:BAACLgAFFH8UAAMbAAYJUSO2EQDZAQAbAAYJUSO2EQDZAQAXAAEJAAD+EgBbAAAuAAQKf0gAAxsACQkZJvkDAFADABsACQkZJvkDAFADABcABAmXGOYjACIBAAAA.Murphy:BAAALgADCgUJBQAAAA==.Mushrodazz:BAABLgAECn8UAAIOAAcJNRAyfABjAQAOAAcJNRAyfABjAQAAAA==.',
Mx='Mxke:BAAALgADCgQJBAABLgAFFAUJCwAIAJEXAA==.',
My='Mysts:BAABLgAECn8YAAIdAAYJ0SabDACcAgAdAAYJ0SabDACcAgABLgAFFAgJKAAUAL4mAA==.',
Na='Narama:BAACLgAFFH8ZAAMBAAcJTQ/5FQCnAQABAAYJTQ/5FQCnAQAnAAEJAABeBwBIAAAuAAQKfyUAAgEACQnZGE8fAJwCAAEACQnZGE8fAJwCAAAA.Nashornn:BAAALgAECgUJCQAAAA==.Naturaljuice:BAAALgADCgcJBwABLgAECgcJGAAVALgJAA==.Nazari:BAAALgAECgYJBwAAAA==.',
Ne='Necrid:BAAALgAECgEJAwAAAA==.Neverlucky:BAAALgAECgEJAwAAAA==.Nezy:BAAALgAECgYJEQAAAA==.',
Ni='Nikalu:BAAALgADCgYJBgAAAA==.Ninæ:BAAALgAECggJDwABLgAFFAUJHAARAJ8eAA==.Nitewïng:BAAALgAFFAEJAQABLgAFFAEJAQAFAAAAAQ==.',
No='Nocturnê:BAAALgADCgQJBAAAAA==.Nootao:BAACLgAFFH8KAAIDAAUJHhjmDAAzAQADAAUJHhjmDAAzAQAuAAQKfyUAAgMACAnUJJ0LAGQCAAMACAnUJJ0LAGQCAAAA.Nootskee:BAAALgADCgEJAQAAAA==.Nootvoker:BAAALgAECgUJCAABLgAFFAUJCgADAB4YAA==.Normac:BAAALgADCgYJCwAAAA==.Notblouses:BAAALgAFFAMJBAABLgAFFAcJGwAGAJcgAA==.Nou:BAAALgAECgQJBwABLgAFFAUJCgADAB4YAA==.',
Ny='Nyoz:BAAALgAECgYJDQAAAA==.Nyxxadra:BAABLgAECn8xAAIBAAkJLhZSJgAqAgABAAkJLhZSJgAqAgAAAA==.',
Ol='Oliaa:BAAALgADCgUJBQAAAA==.',
Om='Omegadeed:BAACLgAFFH8FAAIBAAMJ2wXsawC8AAABAAMJ2wXsawC8AAAuAAQKfykAAgEACQnOEt08AM8BAAEACQnOEt08AM8BAAAA.',
On='Onne:BAAALgAECgYJDQAAAA==.',
Or='Oraculus:BAACLgAFFH8jAAIRAAgJIRDRBQBMAgARAAgJIRDRBQBMAgAuAAQKfyQAAhEACQl1FdYgAD0CABEACQl1FdYgAD0CAAAA.Orchunter:BAAALgADCgcJEgAAAA==.Orcinus:BAABLgAECn8XAAMUAAcJPwPgHgDaAAAUAAcJPwPgHgDaAAAQAAUJ+QJXGABsAAAAAA==.Orcishfist:BAAALgAFFAIJAgAAAA==.Orcward:BAAALgADCgcJDgABLgAECgkJOAAhAN4kAA==.Ordinem:BAABLgAECn8tAAIOAAgJbB3YSADlAQAOAAgJbB3YSADlAQAAAA==.Ore:BAAALgAECgYJCAAAAA==.Originality:BAAALgAECgQJCAAAAA==.Orindron:BAAALgADCgEJAgAAAA==.Orlandodoom:BAAALgADCgMJAwAAAA==.Orvar:BAABLgAECn84AAQhAAkJ3iQvBAAyAwAhAAkJ3iQvBAAyAwAiAAUJDhiPQwBJAQAjAAEJ4wEAMwAkAAAAAA==.',
Pa='Pakaru:BAABLgAECn8kAAIIAAgJeyFpNwBFAgAIAAgJeyFpNwBFAgAAAA==.Palpapeen:BAAALgAECgEJAQAAAA==.Pam:BAACLgAFFH8ZAAMSAAcJ+RohAQATAgASAAcJ+RohAQATAgAVAAIJwQpALACVAAAuAAQKfzgAAxIACAmsJkMCAHEDABIACAmsJkMCAHEDABUABgm/HGZFAN4BAAAA.Panpanpan:BAAALgAECgYJEAAAAA==.',
Pe='Penry:BAAALgAECgEJAQAAAA==.Peorä:BAABLgAECn8YAAINAAgJuQbSNAAcAQANAAgJuQbSNAAcAQAAAA==.Peremo:BAABLgAECn8lAAIbAAkJDyGjBwBjAwAbAAkJDyGjBwBjAwAAAA==.Perfectdark:BAACLgAFFH8cAAIVAAgJnxjmBABeAgAVAAgJnxjmBABeAgAuAAQKfygAAhUACQmSJJAEAH4DABUACQmSJJAEAH4DAAAA.Perse:BAABLgAECn8gAAIEAAgJkxKMFgBoAQAEAAgJkxKMFgBoAQAAAA==.Petdamage:BAAALgAECgEJAQABLgAFFAQJEQAYAJQRAA==.',
Ph='Phutz:BAAALgADCgEJAQAAAA==.',
Pi='Pickles:BAACLgAFFH8GAAIgAAIJBhO2AwC8AAAgAAIJBhO2AwC8AAAuAAQKfx4AAiAACAnTHE0EACoCACAACAnTHE0EACoCAAAA.Pieper:BAABLgAECn8VAAIhAAYJeQ9ddAApAQAhAAYJeQ9ddAApAQAAAA==.Pipa:BAABLgAECn81AAIJAAkJTCI1BQA6AwAJAAkJTCI1BQA6AwAAAA==.',
Pl='Plagueis:BAAALgADCgYJCwABLgAECgkJPgAQALQhAA==.Plaguexrat:BAABLgAECn8UAAINAAYJtAjNPgDrAAANAAYJtAjNPgDrAAAAAA==.Plooptwo:BAABLgAECn8fAAIIAAgJzA5ybQB0AQAIAAgJzA5ybQB0AQAAAA==.Plutó:BAAALgADCgIJAwAAAA==.',
Po='Poacher:BAABLgAECn8ZAAIhAAcJ4Rg1QwCsAQAhAAcJ4Rg1QwCsAQAAAA==.Poadenn:BAAALgAECgEJAQAAAA==.Pongho:BAAALgADCggJCAAAAA==.Poogli:BAABLgAECn8XAAIIAAkJQRYkMwASAgAIAAkJQRYkMwASAgAAAA==.Pooky:BAAALgAECgUJBQAAAA==.Poppapally:BAAALgAECgEJAQAAAA==.Porque:BAABLgAECn8qAAMOAAkJih35HACTAgAOAAkJih35HACTAgAlAAIJyAtoFgBnAAAAAA==.Powar:BAAALgAECggJCwAAAA==.',
Pr='Protolennel:BAAALgADCgkJHQABLgAECgYJEwAFAAAAAA==.Provence:BAAALgAECgYJDQAAAA==.Príxy:BAAALgAECgUJBgAAAA==.',
Py='Pyreynna:BAABLgAECn8jAAMCAAgJah7iBQDaAQABAAgJpBkKNADwAQACAAcJgR3iBQDaAQAAAA==.',
Qs='Qsteve:BAAALgADCgYJAwAAAA==.',
Qu='Quelamonk:BAABLgAECn8WAAIdAAkJEhbLEgBPAgAdAAkJEhbLEgBPAgAAAA==.Queso:BAAALgADCgYJBgABLgAFFAMJBgAVAK8YAA==.Quinmora:BAAALgADCgcJDgAAAA==.',
Ra='Ragarn:BAAALgADCgMJAwAAAA==.Ralnorin:BAABLgAECn8ZAAIJAAcJwQ+0SwBMAQAJAAcJwQ+0SwBMAQAAAA==.Rarren:BAAALgADCgcJEAAAAA==.Raschild:BAAALgAECgUJCgAAAA==.',
Re='Realfrojd:BAABLgAECn8yAAIXAAkJvgx/HwAoAQAXAAkJvgx/HwAoAQAAAA==.Reallybigdk:BAAALgAECgMJBAAAAA==.Regginunchuk:BAABLgAECn80AAIDAAkJRCH5AwAAAwADAAkJRCH5AwAAAwAAAA==.Rejownation:BAAALgAECgcJEAAAAA==.Releronastus:BAAALgAECgYJDQAAAA==.Relief:BAACLgAFFH8HAAIRAAMJjh9IIgAYAQARAAMJjh9IIgAYAQAuAAQKfyMAAxEACQlkI8MHABADABEACQlkI8MHABADAB4ACAlTHuEXAOIBAAAA.Rextallion:BAACLgAFFH8FAAIIAAMJrA/cTQDnAAAIAAMJrA/cTQDnAAAuAAQKfzsAAggACQkOJDgFADcDAAgACQkOJDgFADcDAAAA.Reyson:BAABLgAECn81AAMOAAkJ4Bc+OQAYAgAOAAkJixc+OQAYAgAlAAEJASA2GwA/AAAAAA==.',
Rh='Rhevader:BAAALgAFFAEJAQAAAA==.Rhevan:BAAALgAFFAMJAwAAAA==.Rhinoe:BAAALgAECgcJEQAAAA==.Rholden:BAAALgAECgEJAQAAAA==.Rhun:BAAALgADCgQJBAAAAA==.Rhunon:BAACLgAFFH8GAAIbAAQJvxBnTQAwAQAbAAQJvxBnTQAwAQAuAAQKfzYAAhsACQnwICwNAOQCABsACQnwICwNAOQCAAAA.',
Ri='Ricecakee:BAAALgAECgEJAQABLgAFFAQJEQAYAJQRAA==.Ridor:BAAALgAECgIJAgAAAA==.Rinslaughter:BAABLgAECn8qAAIbAAgJnA+QbABnAQAbAAgJnA+QbABnAQAAAA==.Rinthia:BAACLgAFFH8HAAINAAMJuA8bGwDpAAANAAMJuA8bGwDpAAAuAAQKfzIAAg0ACQntHlcHAL0CAA0ACQntHlcHAL0CAAAA.Ripyeet:BAACLgAFFH8SAAIIAAQJDhotJgBEAQAIAAQJDhotJgBEAQAuAAQKfzAAAggACQnBI8UIAEwDAAgACQnBI8UIAEwDAAAA.Risolta:BAAALgADCgIJAQABLgADCgcJCAAFAAAAAA==.',
Ro='Robinhood:BAAALgAECgcJBwABLgAFFAcJGwAGAJcgAA==.Rol:BAAALgAECgYJBwAAAA==.Rolden:BAABLgAECn8WAAIfAAUJOxgPQQAVAQAfAAUJOxgPQQAVAQAAAA==.Ron:BAAALgADCgUJBQAAAA==.',
Ru='Ruffaf:BAAALgADCgEJAQAAAA==.Rukaji:BAABLgAECn8pAAMWAAgJ2CFiBgB3AgAWAAgJJCFiBgB3AgAEAAYJ9yBiFQB2AQAAAA==.',
Ry='Ryuuter:BAABLgAECn8XAAIVAAgJ9RXeQACkAQAVAAgJ9RXeQACkAQAAAA==.',
['Rå']='Rå:BAAALgADCgUJBQAAAA==.Rågè:BAABLgAECn8YAAIRAAcJ0BBVQQBpAQARAAcJ0BBVQQBpAQAAAA==.',
Sa='Saebelle:BAAALgADCggJEwAAAA==.Saetheline:BAABLgAECn86AAMGAAkJHhy8CwCJAgAGAAkJHhy8CwCJAgAWAAMJmg7kPQCaAAAAAA==.Salogel:BAAALgAECggJDwAAAA==.Sandybeans:BAAALgAECgMJAwAAAA==.Sanko:BAAALgADCgEJAQAAAA==.Sarkang:BAABLgAECn8XAAMXAAgJSRceEwCvAQAXAAcJohkeEwCvAQAbAAIJfQjn+gB3AAAAAA==.Savereia:BAAALgAECgIJAwAAAA==.',
Sc='Schkate:BAABLgAECn8UAAIJAAgJxRxUIwANAgAJAAgJxRxUIwANAgAAAA==.Schutze:BAACLgAFFH8dAAIjAAUJfh/ABgB5AQAjAAUJfh/ABgB5AQAuAAQKfyMAAyMACQlkJCgEANQCACMACQlkJCgEANQCACIABAmyDmZiALcAAAAA.Scorn:BAAALgADCgMJAwAAAA==.Scrammbles:BAAALgAECgYJDwAAAA==.Scråmmbles:BAAALgAECgEJAQAAAA==.',
Sd='Sdadfeg:BAACLgAFFH8IAAIKAAMJ3CN1BQA2AQAKAAMJ3CN1BQA2AQAuAAQKfykAAgoACQmEI1cDAPwCAAoACQmEI1cDAPwCAAAA.',
Se='Selenagomez:BAABLgAFFH8JAAIDAAMJxRh6FgDpAAADAAMJxRh6FgDpAAAAAA==.Selia:BAABLgAECn8aAAIBAAgJqgeGdgA3AQABAAgJqgeGdgA3AQAAAA==.Senlorin:BAAALgAECgMJAwAAAA==.Sephroth:BAABLgAECn8YAAIVAAcJuAnyfAD+AAAVAAcJuAnyfAD+AAAAAA==.',
Sh='Shabobado:BAAALgAECgYJEQAAAA==.Shaboo:BAAALgADCgQJBAAAAA==.Shadowleaf:BAAALgADCgkJEgAAAA==.Shallo:BAAALgADCgUJBQAAAA==.Shatoya:BAAALgADCggJFQAAAA==.Shawoman:BAAALgAECgEJAQAAAA==.Shayluh:BAAALgADCgMJAwAAAA==.Shedoo:BAAALgAECgYJCQAAAA==.Shhum:BAAALgAECgMJAwAAAA==.Shiipo:BAAALgADCgEJAQAAAA==.Shinokage:BAAALgAECgIJAgAAAA==.Shinrei:BAAALgAECgYJDAAAAA==.Shmoople:BAAALgAECgUJCAAAAA==.Shoklancezx:BAAALgAECgEJAQAAAA==.Shumazing:BAAALgADCgYJBgABLgAECgYJBgAFAAAAAA==.Shuten:BAAALgAECgEJAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.Shìlô:BAAALgAECgcJEwAAAA==.',
Si='Sibble:BAAALgADCgkJCQAAAA==.Silbanuz:BAABLgAECn8YAAIKAAgJeBqQCAAHAgAKAAgJeBqQCAAHAgAAAA==.Simplejakk:BAAALgADCgYJCwAAAA==.Sinill:BAAALgAECgIJAgAAAA==.Sinterklaas:BAABLgAECn8fAAMJAAgJSBE3PACLAQAJAAgJSBE3PACLAQAYAAYJ+gbfUwD2AAAAAA==.Siqma:BAAALgAECgUJBgAAAA==.',
Sj='Sj:BAAALgAECgIJAgABLgAFFAgJGAAOAHkjAA==.',
Sk='Skeith:BAAALgAECgEJAQAAAA==.Skydeed:BAAALgAECgQJBgAAAA==.',
Sl='Slapfurr:BAAALgAECgEJAwAAAA==.Slark:BAABLgAECn8nAAMdAAkJHBmwGQALAgAdAAkJHBmwGQALAgADAAEJGgLJmwAXAAAAAA==.Slawth:BAABLgAECn8VAAQXAAYJexdrHwApAQAXAAUJhxtrHwApAQAbAAYJnAd/tADjAAALAAQJFg57HQCTAAAAAA==.Slayermonde:BAAALgAECgYJDwAAAA==.Slimjerry:BAAALgAECgEJAQAAAA==.Sliprain:BAAALgAECgcJCQAAAA==.Slopwizard:BAAALgAECgUJCAAAAA==.',
Sm='Smexydemon:BAAALgAECgMJAwABLgAECgYJBgAFAAAAAA==.Smexydubs:BAAALgAECgYJBgAAAA==.Smexyexpress:BAAALgAECgUJBQABLgAECgYJBgAFAAAAAA==.Smexytimes:BAAALgAECgEJAQABLgAECgYJBgAFAAAAAA==.Smeyplus:BAACLgAFFH8nAAIIAAgJcxzFAQCSAgAIAAgJcxzFAQCSAgAuAAQKfzEAAggACQkpJbkEAD8DAAgACQkpJbkEAD8DAAAA.Smokincrayon:BAAALgAECgcJAwAAAA==.',
Sn='Snickeris:BAABLgAECn8nAAMBAAkJ9wdxWAB+AQABAAkJ9wdxWAB+AQAnAAIJJgWgMgAuAAAAAA==.Snofawl:BAACLgAFFH8GAAITAAMJyAR1OQCqAAATAAMJyAR1OQCqAAAuAAQKfzIAAhMACQmSGuENAGQCABMACQmSGuENAGQCAAAA.Snoranir:BAABLgAECn8qAAURAAgJTRpcIAAhAgARAAgJTRpcIAAhAgAZAAUJ2BS5EwAzAQAeAAYJPRQGPQDqAAAHAAMJLhwQHQDlAAAAAA==.',
So='Solamxke:BAAALgAECgMJBAABLgAFFAUJCwAIAJEXAA==.Sorisa:BAAALgADCggJDwAAAA==.Sovereign:BAABLgAFFH8QAAMQAAcJshUyAQCzAQAQAAUJYBUyAQCzAQATAAUJVxOYEACMAQAAAA==.',
Sp='Spanfrontals:BAABLgAECn8dAAMkAAgJZBnhCgC1AQAVAAcJ+RgYRADjAQAkAAYJtBrhCgC1AQABLgAFFAYJDgAZABoZAA==.Spiko:BAABLgAECn8bAAIJAAgJNRUsKADvAQAJAAgJNRUsKADvAQAAAA==.Spillthetea:BAAALgADCggJEAABLgAFFAEJAQAFAAAAAA==.Spite:BAACLgAFFH8HAAIBAAMJ7w92WgDjAAABAAMJ7w92WgDjAAAuAAQKfywAAgEACQkDHEIaAG0CAAEACQkDHEIaAG0CAAAA.',
Sq='Squidd:BAABLgAECn8aAAIhAAYJNQJ+twCWAAAhAAYJNQJ+twCWAAAAAA==.',
St='Stars:BAABLgAFFH8HAAIVAAMJRRZASADgAAAVAAMJRRZASADgAAAAAA==.Steakshot:BAAALgADCgIJAgAAAA==.Steelcow:BAAALgADCgEJAQAAAA==.Stevengotwow:BAAALgAECgcJBwAAAA==.Stryjix:BAAALgADCgQJBAAAAA==.Stuhmp:BAAALgADCgEJAQAAAA==.',
Su='Sullie:BAAALgAECgIJAgAAAA==.Sunhorn:BAAALgADCggJCAAAAA==.Sunreaver:BAAALgADCgIJAgAAAA==.Sunset:BAAALgAECgQJBAAAAA==.Sureno:BAAALgAFFAEJAQAAAA==.Suslord:BAAALgADCgcJCgAAAA==.',
Sw='Sweetpickles:BAAALgADCgQJBAAAAA==.',
Sx='Sxybznitch:BAAALgAECgYJCgAAAA==.Sxyhealz:BAABLgAECn8oAAIMAAkJSxWKIADeAQAMAAkJSxWKIADeAQAAAA==.Sxyheålz:BAABLgAFFH8HAAIMAAQJJgbVFQDkAAAMAAQJJgbVFQDkAAAAAA==.',
Sy='Syntherien:BAAALgADCgEJAQAAAA==.',
Sz='Szandöra:BAABLgAECn8yAAINAAkJCAaMOQAEAQANAAkJCAaMOQAEAQAAAA==.',
['Sü']='Süture:BAABLgAECn8eAAIoAAkJkgNlSQDeAAAoAAkJkgNlSQDeAAAAAA==.',
Ta='Taggaz:BAAALgAECgYJCAAAAA==.Talkaris:BAAALgAECgcJEQABLgAFFAMJBwANALgPAA==.Tandrelia:BAAALgAECgQJBQAAAA==.Tanndari:BAAALgAECgEJAQAAAA==.Tarragon:BAAALgAECgIJBAAAAA==.Tartare:BAABLgAECn8cAAIIAAgJlwt0dgBhAQAIAAgJlwt0dgBhAQAAAA==.Tashiice:BAAALgADCgYJBgABLgAECgkJIwAhAMgZAA==.Tazriak:BAAALgAFFAgJAQAAAA==.',
Te='Teriheals:BAAALgADCgkJCQAAAA==.Terishon:BAAALgAECgYJEwAAAA==.',
Th='Thatsmxke:BAAALgADCgUJBQABLgAFFAUJCwAIAJEXAA==.Thaurex:BAAALgAECgEJAgAAAA==.Theophania:BAAALgAECgcJDQAAAA==.Theshacker:BAAALgAECgEJAQAAAA==.Thogo:BAACLgAFFH8HAAIGAAMJ5xruIgDzAAAGAAMJ5xruIgDzAAAuAAQKfyMAAgYACQn2HToSAL4CAAYACQn2HToSAL4CAAAA.Thrustzi:BAAALgAECgYJCAAAAA==.',
Ti='Tiger:BAAALgAECgEJAQABLgAECgEJBAAFAAAAAA==.Tikaa:BAAALgADCgIJAgAAAA==.Tinykitsune:BAAALgADCgMJAwAAAA==.Tipnontotems:BAAALgADCgcJDQAAAA==.',
To='Toadeater:BAAALgAECgEJBQAAAA==.Tokiya:BAAALgAFFAEJAQABLgAECgkJGQAPALodAA==.Tomerd:BAAALgAECgIJAwABLgAECgkJKwAfAPcfAA==.Tomerto:BAABLgAECn8rAAMfAAkJ9x8JDQCxAgAfAAkJ9x8JDQCxAgAIAAIJ9AmRYQEyAAAAAA==.Toobeastly:BAAALgAECgUJBwAAAA==.Tooner:BAABLgAECn8eAAIRAAgJcQ6XPwBxAQARAAgJcQ6XPwBxAQAAAA==.Torques:BAAALgADCgYJGgAAAA==.Toymonkey:BAAALgAECgUJCwAAAA==.',
Tr='Trielas:BAAALgADCgMJAwAAAA==.Trolazo:BAAALgADCgQJBAAAAA==.Tryingmybest:BAAALgAECgUJCQABLgAFFAYJDgAZABoZAA==.',
Tu='Tuxedomaask:BAAALgAECgUJBwABLgAECgcJFgAJADIZAA==.',
Tw='Twentyone:BAABLgAECn8rAAIZAAkJGCXKAAByAwAZAAkJGCXKAAByAwAAAA==.Twiggz:BAAALgAECgUJCQABLgAECgkJKgAOAIodAA==.Twozero:BAAALgAECgYJEwAAAA==.',
Ty='Tyestaumin:BAAALgAECgUJBwABLgAECgYJDQAFAAAAAA==.Tyiesticus:BAAALgAECggJEwAAAA==.Tyralen:BAABLgAECn8xAAIhAAkJYBjzGwBfAgAhAAkJYBjzGwBfAgABLgAECgkJMwAZAJkUAA==.Tyrandras:BAABLgAECn8zAAIZAAkJmRQsDQDVAQAZAAkJmRQsDQDVAQAAAA==.Tyrec:BAAALgAECgYJDQABLgAECgcJFgAJADIZAA==.Tyrïon:BAAALgAECgYJDgAAAA==.',
['Tö']='Töxxy:BAAALgAECgIJAgAAAA==.',
Ul='Uldrag:BAAALgAECgcJEAAAAA==.',
Va='Vaero:BAACLgAFFH8HAAIVAAQJOhJUNAAgAQAVAAQJOhJUNAAgAQAuAAQKf0YAAxUACQl4I7oFABgDABUACQl4I7oFABgDACQAAQlhB1AuACcAAAAA.Vandenar:BAABLgAECn8fAAIVAAYJuRf2ZQA1AQAVAAYJuRf2ZQA1AQAAAA==.Varju:BAABLgAECn8WAAMeAAgJZxOZKABcAQAeAAgJZxOZKABcAQARAAIJQATHwgBCAAAAAA==.Vauromoth:BAAALgADCgEJAQAAAA==.',
Vd='Vdarkadin:BAAALgADCgEJAQABLgAECgYJAQAFAAAAAA==.Vdarkdevour:BAAALgAECgYJAQAAAA==.Vdarksmonk:BAAALgAECgEJAQABLgAECgYJAQAFAAAAAA==.',
Ve='Vee:BAAALgADCgcJBwABLgAFFAcJFQATAJIZAA==.Velyssa:BAAALgADCgcJBwABLgAECggJKQAIAN8dAA==.Venandi:BAAALgADCgkJFwABLgAECgkJKAAaAAEaAA==.Venni:BAAALgAECgQJBQAAAA==.Venoshock:BAAALgADCgEJAQAAAA==.',
Vi='Vibez:BAAALgAECgEJAQAAAA==.Vibin:BAABLgAECn8kAAIUAAkJNBogCgAcAgAUAAkJNBogCgAcAgAAAA==.Vineeshewah:BAABLgAECn8pAAInAAgJQSEZAgCWAgAnAAgJQSEZAgCWAgAAAA==.Vision:BAAALgAECgEJAgAAAA==.Vivi:BAABLgAECn8UAAQCAAYJaRhDDwAfAQACAAYJYBRDDwAfAQAnAAUJMhgdEwD9AAABAAUJngtysADKAAAAAA==.Vizu:BAAALgADCgcJBwAAAA==.',
Vo='Voruna:BAAALgAECggJDwAAAA==.',
Vu='Vulsted:BAAALgADCgUJBwAAAA==.',
Wa='Waffleshank:BAAALgADCggJCAAAAA==.Wantedd:BAAALgAECgcJDgABLgAECggJGwAJADUVAA==.',
Wh='Whalend:BAABLgAECn8VAAIOAAgJhAR59AARAQAOAAgJhAR59AARAQAAAA==.',
Wi='Wilbo:BAABLgAFFH8RAAMYAAQJEx1lIQDwAAAYAAMJPh1lIQDwAAAJAAMJbQRBRgCYAAABLgAFFAQJGAAbAOEhAA==.Wilbodragons:BAAALgAECgEJAQABLgAFFAQJGAAbAOEhAA==.Wily:BAABLgAECn8eAAIBAAgJCAm1awBNAQABAAgJCAm1awBNAQAAAA==.Winton:BAAALgADCgUJBQAAAA==.Wisperwing:BAABLgAECn8bAAIhAAYJDAwVjwDuAAAhAAYJDAwVjwDuAAAAAA==.',
Wo='Wolfdrudu:BAAALgAECgYJEQAAAA==.Worldfire:BAABLgAECn8kAAIOAAgJLQmGiABKAQAOAAgJLQmGiABKAQAAAA==.Wormadina:BAAALgAECgUJDwAAAA==.Wormszer:BAAALgAECgcJEgAAAA==.Woth:BAAALgAECgUJBwAAAA==.',
Wr='Wrecka:BAABLgAECn8rAAMBAAkJFCLqDwC1AgABAAkJFCLqDwC1AgAnAAEJAABNNwAlAAAAAA==.',
Ww='Ww:BAAALgAFFAMJBAABLgAFFAgJDAAEALIZAA==.',
Wy='Wylds:BAAALgAECgcJCgABLgAFFAgJKAAUAL4mAA==.Wyldvyrus:BAAALgADCgUJBQAAAA==.Wyndborne:BAAALgAECgYJBgABLgAFFAgJKAAUAL4mAA==.Wynds:BAACLgAFFH8oAAIUAAgJviYKAACfAwAUAAgJviYKAACfAwAuAAQKfzUAAhQACQmTJhYAAPwDABQACQmTJhYAAPwDAAAA.Wyrsa:BAABLgAECn8bAAQXAAgJWxU3GABxAQAXAAgJ/BQ3GABxAQAbAAYJ5RAckwBaAQALAAEJMQVPLwAkAAAAAA==.Wyrsathuzad:BAAALgADCgUJBQAAAA==.',
Xa='Xanny:BAAALgAECgEJAQAAAA==.Xaro:BAAALgADCgMJAwAAAA==.',
Xe='Xelock:BAAALgAECgcJBwAAAA==.Xeres:BAAALgADCgYJBgAAAA==.',
Xi='Xi:BAABLgAECn85AAQUAAkJlwvPFABaAQAUAAgJkQvPFABaAQATAAgJGAPTSwDSAAAQAAEJ+QEmJQAZAAAAAA==.Xiaozhi:BAEBLgAECn8pAAIdAAgJzyI/BwD7AgAdAAgJzyI/BwD7AgAAAA==.',
Xz='Xzariana:BAABLgAECn8dAAIhAAgJGRC6TgCIAQAhAAgJGRC6TgCIAQAAAA==.',
Ya='Yakor:BAABLgAECn8gAAIPAAgJ8QtYKgBEAQAPAAgJ8QtYKgBEAQAAAA==.Yakub:BAACLgAFFH8WAAMhAAcJEBv6DwCFAQAhAAYJ4xj6DwCFAQAiAAUJ/xtyDQA9AQAuAAQKfxsAAyIACQluH4QMAOUCACIACQnYG4QMAOUCACEABgkBJNkbAFQCAAAA.',
Ye='Yenalda:BAAALgAECggJDgAAAA==.Yennefer:BAAALgADCgcJBwAAAA==.Yeobsuirad:BAAALgAECgEJBgAAAA==.',
Yo='Yodda:BAABLgAECn8jAAIgAAgJcxZnBgDgAQAgAAgJcxZnBgDgAQAAAA==.Yoirr:BAAALgAECgMJAwAAAA==.',
['Yë']='Yëëter:BAAALgAECgIJAgAAAA==.',
Za='Zach:BAABLgAECn8cAAMEAAYJaCLFDQAuAgAEAAYJaCLFDQAuAgAGAAIJ/QvAiwAxAAAAAA==.Zached:BAAALgADCgcJDAABLgAECgYJHAAEAGgiAA==.Zaeix:BAAALgADCgcJBwAAAA==.Zaionis:BAAALgAECgUJCAAAAA==.Zalius:BAAALgAECgUJDQAAAA==.Zanori:BAACLgAFFH8FAAMLAAIJgAhGFAB/AAAbAAIJTQdatwCFAAALAAIJMgVGFAB/AAAuAAQKfyEAAxsACAk9E85eANYBABsACAl1Es5eANYBAAsABwmgD6QPADABAAAA.Zansijo:BAAALgAECgYJCAABLgAFFAIJBQALAIAIAA==.Zarienia:BAABLgAECn8UAAMkAAgJsAVMHQCFAAAVAAgJVQPOmQDDAAAkAAQJJAdMHQCFAAAAAA==.',
Ze='Zedmann:BAAALgADCgcJEwABLgAECgYJBwAFAAAAAA==.Zellyne:BAACLgAFFH8cAAIRAAUJnx7YDQDDAQARAAUJnx7YDQDDAQAuAAQKfyYAAhEACQn/I2kFADYDABEACQn/I2kFADYDAAAA.Zensetral:BAAALgAECgUJBAAAAA==.Zenstiller:BAAALgADCgEJAQAAAA==.Zentho:BAAALgADCgYJBwAAAA==.',
Zl='Zl:BAAALgAFFAIJAgABLgAFFAgJDAAEALIZAA==.',
Zo='Zom:BAAALgADCgkJCQAAAA==.Zoogzoog:BAAALgAECgEJAQAAAA==.Zorriya:BAABLgAECn8qAAIhAAgJ0Rr4JwAVAgAhAAgJ0Rr4JwAVAgAAAA==.Zovhia:BAAALgAFFAEJAQAAAA==.',
Zy='Zygo:BAAALgADCgkJFgAAAA==.',
['Zø']='Zød:BAAALgAECgEJAQABLgAECgkJMwAUAHgbAA==.',
['Ár']='Áries:BAAALgAECgEJAQAAAA==.',
['Çò']='Çòñvíçtíòñ:BAAALgAECgYJCQAAAA==.',
['Ìf']='Ìfrìt:BAABLgAECn8ZAAMOAAgJSRPGcgB3AQAOAAgJ6RLGcgB3AQApAAIJeA/uCgB1AAAAAA==.',
['Ðe']='Ðemonicmonk:BAAALgAECggJCwABLgAECgcJHgATAEwLAA==.Ðemonslayer:BAAALgADCgIJAgAAAA==.',
['Ýu']='Ýuno:BAABLgAECn8dAAIoAAkJ6BWPFQDLAQAoAAkJ6BWPFQDLAQAAAA==.',
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
