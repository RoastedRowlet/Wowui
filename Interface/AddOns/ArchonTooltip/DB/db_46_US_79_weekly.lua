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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Warrior-Arms','Shaman-Enhancement','Monk-Mistweaver','Priest-Discipline','Shaman-Restoration','Warlock-Destruction','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Unholy','Warlock-Affliction','Druid-Guardian','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaronius:BAABLgAECn8uAAIBAAgJTwfwOAAXAQABAAgJTwfwOAAXAQAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8rAAMCAAkJyR24JgCAAgACAAkJwB24JgCAAgADAAUJNReKCwAeAQAAAA==.',
Ac='Acceptance:BAAALgAFFAEJAQAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8uAAIEAAkJFyJ4EQDFAgAEAAkJFyJ4EQDFAgAAAA==.Adora:BAABLgAECn8jAAIEAAkJaBysFACtAgAEAAkJaBysFACtAgAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aelise:BAAALgADCgQJBAABLgAECgkJMwAFAFEfAA==.',
Ag='Agaliarept:BAACLgAFFH8LAAIGAAQJkgszVQDvAAAGAAQJkgszVQDvAAAuAAQKfxYAAwcACAkYC5UaAMgAAAYABwnpBuCLAAsBAAcABwkPC5UaAMgAAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAABLgAECn8YAAIIAAYJaBLXJADvAAAIAAYJaBLXJADvAAAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn88AAMJAAkJXRRcFQDjAQAJAAkJXRRcFQDjAQAGAAgJ8AfPdAA4AQAAAA==.',
Ak='Akumajoe:BAAALgAECgMJAwAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAFFAIJAgAAAA==.Alrook:BAABLgAECn8VAAMKAAgJ3xVEewB4AQAKAAgJ3xVEewB4AQALAAIJ4BHDdwBeAAAAAA==.Aluni:BAAALgAECgUJBQAAAA==.',
Am='Amethÿst:BAAALgAFFAIJAgAAAA==.Amoral:BAAALgAECgMJAwAAAA==.',
An='Angelneko:BAABLgAECn85AAIMAAkJaQ0LKQCKAQAMAAkJaQ0LKQCKAQAAAA==.Anitabj:BAAALgAFFAEJAQAAAA==.Annihilaiden:BAAALgAECgIJAgABLgAECgkJPAAJAF0UAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwANAAAAAA==.Aralak:BAAALgADCgYJBgABLgAECgkJNgAOAPggAA==.Arcaynemoon:BAABLgAECn8XAAIMAAYJWAM9VgDLAAAMAAYJWAM9VgDLAAAAAA==.Arcon:BAAALgAECgEJAQAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.',
As='Asterior:BAACLgAFFH8RAAMPAAYJvxdiAQBxAQAPAAUJmxtiAQBxAQAMAAEJTghoSQBNAAAuAAQKfywAAg8ACQnzIKcDANQCAA8ACQnzIKcDANQCAAAA.',
Au='Aug:BAAALgAECgIJAgABLgAECggJFAAKAO4aAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgAECgEJAQAAAA==.Auroraa:BAABLgAECn8wAAIMAAgJiwkPAwCEAAAMAAgJiwkPAwCEAAAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgMJBAANAAAAAA==.',
Av='Avalectra:BAAALgAECgUJCAAAAA==.',
Ay='Aylana:BAAALgAECgYJBgAAAA==.',
Az='Azanost:BAAALgADCgQJBAABLgAECgkJJAAQAOAVAA==.Azmodeaz:BAABLgAECn9BAAIDAAkJxhtzAQCPAgADAAkJxhtzAQCPAgAAAA==.Aztrik:BAAALgAECgYJBgABLgAECgkJIwAKAIUjAA==.',
Ba='Bajapanti:BAABLgAECn86AAIRAAkJvxveAwCFAgARAAkJvxveAwCFAgAAAA==.Ballyhøø:BAABLgAECn8aAAIMAAkJRhSFMQBWAQAMAAkJRhSFMQBWAQAAAA==.Banchory:BAAALgADCgQJBQAAAA==.Bandaron:BAAALgAECgQJCgAAAA==.Baxstab:BAABLgAECn82AAISAAkJ5xsRDQBVAgASAAkJ5xsRDQBVAgAAAA==.',
Bc='Bcam:BAAALgADCgYJBgAAAA==.',
Be='Beahon:BAAALgAECgQJDgAAAA==.Beelzebrad:BAAALgADCgkJCQAAAA==.Betruger:BAAALgAECgEJAQAAAA==.',
Bg='Bgeefiddy:BAAALgAECgMJAwAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJCgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackjak:BAAALgAECgEJAQAAAA==.Blackpatch:BAABLgAECn87AAMTAAkJZCLLBAAKAwATAAkJZCLLBAAKAwAUAAgJ4gfeOAAYAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgYJDAAAAA==.Blargg:BAAALgADCgkJCQAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAABLgAFFH8JAAIVAAQJOhaFHwAjAQAVAAQJOhaFHwAjAQAAAA==.Blooming:BAAALgAECggJDQABLgAECggJHAAWAA4aAA==.Bloomsbeam:BAABLgAECn8cAAIGAAgJDBaGZgBZAQAGAAgJDBaGZgBZAQAAAA==.Bloomslinger:BAAALgADCgQJBAAAAA==.',
Bo='Bonerflex:BAACLgAFFH8JAAIXAAQJ+woTKwAIAQAXAAQJ+woTKwAIAQAuAAQKfysAAxcACQnlG68KALoCABcACQnlG68KALoCABgABAlAClZDAGMAAAAA.Bonusdk:BAAALgAECgYJBgABLgAECgkJMwAZAN4hAA==.Booneboy:BAABLgAECn8gAAMKAAgJTyFUJQBvAgAKAAgJTyFUJQBvAgAIAAQJ/BfjAAAXAQAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8lAAMIAAkJXxXTGQBKAQAIAAkJ7BLTGQBKAQAKAAcJ3A0YpgAuAQABLgAFFAYJGwAaAPsUAA==.',
Br='Brennor:BAABLgAECn8zAAIKAAkJ5w4XaQCdAQAKAAkJ5w4XaQCdAQAAAA==.Brewslunt:BAACLgAFFH8SAAIbAAcJmBZuFgDLAQAbAAcJmBZuFgDLAQAuAAQKfywAAxsACAmfIZkTAH8CABsACAmfIZkTAH8CABMAAwnEC1VpAIIAAAAA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Bubblydin:BAAALgAECgYJBgABLgAFFAMJCQAcAP0GAA==.Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAABLgAECn8uAAIdAAkJDRR2JAA0AgAdAAkJDRR2JAA0AgAAAA==.Cairyan:BAABLgAECn85AAIHAAkJJx3TAwCVAgAHAAkJJx3TAwCVAgAAAA==.Caiya:BAAALgADCgcJBwABLgAECgkJOAASAOMkAA==.Capn:BAAALgADCgcJCQAAAA==.Carvil:BAABLgAECn8zAAMeAAkJGxa9BgDyAQAeAAkJGxa9BgDyAQAWAAMJjweN7gCDAAAAAA==.Castalia:BAABLgAECn8UAAIfAAYJ7Qs+AgDEAAAfAAYJ7Qs+AgDEAAAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8YAAICAAYJKBdMOACJAQACAAYJKBdMOACJAQAuAAQKfysAAgIACQkXJCocAAYDAAIACQkXJCocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAYJGAACACgXAA==.Celithe:BAABLgAECn8gAAIKAAgJpxSNXwCyAQAKAAgJpxSNXwCyAQAAAA==.Cendrian:BAABLgAECn8WAAIMAAcJYQuoQwD+AAAMAAcJYQuoQwD+AAAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8tAAICAAkJfhwOLgBhAgACAAkJfhwOLgBhAgAAAA==.Charmshield:BAAALgAECgMJAwAAAA==.Cheezle:BAAALgAECgkJCAAAAA==.Chiafix:BAABLgAECn8cAAIUAAgJDwxPMgA3AQAUAAgJDwxPMgA3AQABLgAECgkJNQAdANYhAA==.Chipp:BAABLgAECn8UAAIUAAcJ/CbtBwC1AgAUAAcJ/CbtBwC1AgAAAA==.Chleo:BAAALgAECgMJBwAAAA==.Choco:BAACLgAFFH8kAAIgAAgJox3QAgDQAgAgAAgJox3QAgDQAgAuAAQKfykAAyAACQnvI+QFAOgCACAACQnvI+QFAOgCACEAAQkVG3ohAEkAAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAgJJAAgAKMdAA==.Chudster:BAABLgAECn8gAAMhAAkJ/RVFCACuAQAhAAkJ/RVFCACuAQAiAAUJDQh0YQC2AAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAABLgAECn8mAAMYAAgJcCAyCAB4AgAYAAgJcCAyCAB4AgAZAAEJixFMeQAwAAAAAA==.Conqueror:BAAALgAECgYJEAABLgAFFAMJCQAFAE8RAA==.',
Cr='Crawdaddy:BAABLgAECn8WAAIEAAcJJhJocQBdAQAEAAcJJhJocQBdAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAAALgAECgcJDwAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECggJHAAKAFcMAA==.Curmudge:BAABLgAECn9RAAIFAAkJrBdxGwBqAgAFAAkJrBdxGwBqAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgANAAAAAA==.Cybele:BAABLgAECn8bAAIBAAcJCgycAgCjAAABAAcJCgycAgCjAAAAAA==.',
Da='Dakunaito:BAABLgAECn8hAAMjAAkJxiRiFADNAgAjAAkJTCRiFADNAgAQAAEJLiJrLgBnAAAAAA==.Danay:BAAALgAECgEJAQAAAA==.Danksquaddon:BAAALgADCgQJBAAAAA==.Darachane:BAABLgAECn82AAMfAAcJ6A//NABEAQAfAAcJ6A//NABEAQABAAEJxwKwegAfAAAAAA==.Darovan:BAAALgADCgMJAwABLgAECgkJQQAOAOkjAA==.Darthnater:BAAALgAECgIJAgAAAA==.Dauglow:BAAALgAECgYJCQAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgADCggJDwAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAFFAEJAgAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAAALgAECgUJEwAAAA==.Deltia:BAABLgAECn8xAAIVAAkJtBiMFgAxAgAVAAkJtBiMFgAxAgAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAQJEAAEAKURAA==.Demonagent:BAABLgAECn8UAAQJAAgJfhl4GgCsAQAJAAgJfhl4GgCsAQAGAAQJOwv1wACrAAAHAAIJFBhaLwBFAAAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8VAAMiAAYJ+hYpIABgAQAiAAYJ+hYpIABgAQAhAAIJfQ4ZCQBYAAAuAAQKfzAAAyEACQkOH9YJAEICACEACQlbHNYJAEICACIACAlrG8obAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8cAAIWAAgJDhp6OgDwAQAWAAgJDhp6OgDwAQAAAA==.',
Di='Dimebagg:BAAALgAECgYJCgAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8sAAMBAAgJdx3+EgBEAgABAAgJdx3+EgBEAgAcAAMJDgnvRACRAAAAAA==.Dokspades:BAABLgAECn8UAAIdAAkJ/g8HMwDnAQAdAAkJ/g8HMwDnAQAAAA==.Dornoch:BAABLgAECn8jAAMLAAcJSCMQDQDAAgALAAcJSCMQDQDAAgAKAAEJ8AE1XAEjAAAAAA==.Dotzilla:BAABLgAECn8WAAQWAAYJiyU6VQCcAQAWAAQJiCQ6VQCcAQAkAAIJ9iXmHADXAAAeAAIJbSTgLQBhAAAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJCQAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8tAAIKAAkJ2g3xbgCQAQAKAAkJ2g3xbgCQAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECggJFAAJAH4ZAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAABLgAFFH8HAAIGAAIJ+h2bcwCfAAAGAAIJ+h2bcwCfAAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8PAAIjAAMJwRkvlgDhAAAjAAMJwRkvlgDhAAAuAAQKfzQAAiMACQknISYXALwCACMACQknISYXALwCAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAgAAAA==.',
Ei='Einherja:BAAALgAECgQJBgAAAA==.Eisenhorn:BAAALgAECgUJBgAAAA==.',
El='Elessaria:BAABLgAECn8gAAIFAAgJFwaQAwBtAAAFAAgJFwaQAwBtAAAAAA==.Elfatheàrt:BAABLgAECn8YAAIKAAYJwxEosAAfAQAKAAYJwxEosAAfAQAAAA==.Elidrus:BAAALgADCgcJBwABLgAECgkJCQANAAAAAA==.Elira:BAAALgAECgEJAQAAAA==.',
Em='Emelgee:BAABLgAECn8aAAIlAAcJRA0aAgCtAAAlAAcJRA0aAgCtAAABLgAFFAMJCQAcAP0GAA==.Emofurry:BAAALgAECgUJBQAAAA==.',
En='End:BAAALgADCgEJAQAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgkJIwAEAGgcAA==.',
Es='Esika:BAAALgAFFAIJAwAAAA==.Estherras:BAABLgAECn8wAAIEAAkJXBqOJABQAgAEAAkJXBqOJABQAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgEJAQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fa='Fato:BAAALgAECgUJBgAAAA==.',
Fe='Feardotrun:BAABLgAECn8kAAMWAAkJhQ3AVgCYAQAWAAkJ2QzAVgCYAQAeAAMJWQzlJgB+AAAAAA==.Felicious:BAAALgAECgYJEwAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgAECgMJAgAAAA==.Finahlia:BAABLgAECn8gAAIFAAkJ7CHtBQBZAwAFAAkJ7CHtBQBZAwAAAA==.Finally:BAABLgAECn8lAAIVAAcJOgkcUwDsAAAVAAcJOgkcUwDsAAAAAA==.Firebat:BAAALgADCgcJBwABLgAECggJIAAKAE8hAA==.Firemage:BAABLgAECn81AAIWAAkJLiPABwAaAwAWAAkJLiPABwAaAwAAAA==.Fizzanelf:BAABLgAECn8lAAIFAAcJHiS4DwDVAgAFAAcJHiS4DwDVAgAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAACLgAFFH8NAAIKAAYJLwS1YgDqAAAKAAYJLwS1YgDqAAAuAAQKfzIAAgoACQkKGgBRAO4BAAoACQkKGgBRAO4BAAAA.Friendo:BAABLgAECn88AAMPAAkJSRkCCABTAgAPAAkJSRkCCABTAgAMAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAFFAEJAwAAAA==.Frynied:BAAALgAECgUJCAABLgAECgkJIgABAKwaAA==.',
Fu='Furnost:BAABLgAECn8kAAIQAAkJ4BV/CQDtAQAQAAkJ4BV/CQDtAQAAAA==.Futnuraz:BAABLgAECn8hAAIZAAcJOgfCOgDaAAAZAAcJOgfCOgDaAAAAAA==.',
Fy='Fyrakkobama:BAAALgAECgkJBQABLgAECgkJGQAmAP0iAA==.Fyranne:BAAALgADCgkJCQAAAA==.Fyriat:BAABLgAECn81AAICAAkJ0wmwdgCMAQACAAkJ0wmwdgCMAQAAAA==.',
Ga='Gabbee:BAAALgADCgkJCQAAAA==.Gazardiel:BAAALgAECgIJAgAAAA==.',
Ge='Getafix:BAAALgAECgcJCwABLgAECgkJNQAdANYhAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8yAAITAAgJsxxbEABHAgATAAgJsxxbEABHAgAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goldstorm:BAAALgADCgYJBgAAAA==.Goliath:BAAALgAECgYJDAABLgAECgkJGwAKAMcbAA==.Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8lAAIeAAkJIh1kAgCWAgAeAAkJIh1kAgCWAgAAAA==.Greybark:BAAALgADCgcJEQAAAA==.Griffindor:BAABLgAECn8zAAIKAAkJYBjmMgA0AgAKAAkJYBjmMgA0AgAAAA==.Grimfelborn:BAACLgAFFH8hAAMkAAYJgBIlCQDnAAAWAAUJVg4COwBgAQAkAAQJ4BElCQDnAAAuAAQKfzIAAxYACQn1HLsxAEUCABYACQlMG7sxAEUCACQAAwlQIaohALUAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAABLgAECn8rAAIdAAgJNh1jGgB4AgAdAAgJNh1jGgB4AgAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgAECgEJAgAAAA==.',
Ha='Hanicus:BAAALgAECgkJCQAAAA==.Hanoverfiste:BAABLgAECn8cAAIKAAgJVwyVlABKAQAKAAgJVwyVlABKAQAAAA==.Hapsburg:BAABLgAECn8rAAIbAAkJdxLoJAD7AQAbAAkJdxLoJAD7AQAAAA==.Haranbae:BAAALgADCgkJCQAAAA==.Havince:BAABLgAECn82AAIOAAkJ+CAWBwCrAgAOAAkJ+CAWBwCrAgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn84AAIKAAkJsB/kFgC5AgAKAAkJsB/kFgC5AgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Ig='Ignisdaemoni:BAAALgAECgMJBAABLgAECgkJIAAFAOwhAA==.',
Il='Illidai:BAAALgAECgYJEgAAAA==.Ilyndra:BAABLgAECn8zAAMZAAkJ3iF1BwCAAgAYAAkJeR3ABwCFAgAZAAgJsyF1BwCAAgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn81AAIXAAkJuxYdGwAVAgAXAAkJuxYdGwAVAgAAAA==.',
It='Ithea:BAABLgAECn8xAAICAAkJCCHWEwDjAgACAAkJCCHWEwDjAgAAAA==.',
Ja='Jackyll:BAAALgAECgIJBwAAAA==.Jaeson:BAEBLgAECn8iAAIWAAkJjhZDMQATAgAWAAkJjhZDMQATAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAgJHwALAGscAA==.',
Je='Jeef:BAAALgADCgEJAQABLgAECgkJGQAmAP0iAA==.Jeefrenzy:BAABLgAECn8ZAAMmAAkJ/SINBQDYAgAmAAkJ/SINBQDYAgAEAAIJkiGPAAFeAAAAAA==.Jeefwrld:BAAALgAECgQJBAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgcJEQAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8lAAQBAAkJeBnmHwDEAQABAAgJsRLmHwDEAQAcAAYJ8RSgIwB2AQAfAAUJDRSMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8cAAInAAgJsg8YCgCYAQAnAAgJsg8YCgCYAQAAAA==.',
Ju='Jughunter:BAACLgAFFH8KAAMEAAQJnxNaVgD6AAAEAAQJvgVaVgD6AAAmAAMJtRg3HADvAAAuAAQKfxYAAxEACAmkFl0SADcBACYABgkFFSArAEkBABEACAnMEF0SADcBAAAA.Jugz:BAAALgADCgEJAQABLgAFFAQJCgAEAJ8TAA==.',
Jw='Jwise:BAAALgAECgkJBgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kamus:BAAALgAECgMJAwAAAA==.Kanabat:BAAALgAECgcJDgAAAA==.Karaden:BAAALgAECgUJBQAAAA==.Karawyn:BAABLgAECn8kAAIEAAgJ5Q5BPQC5AQAEAAgJ5Q5BPQC5AQABLgAECgcJCQANAAAAAA==.Karelix:BAAALgAECgIJAwAAAA==.Katrishy:BAACLgAFFH8hAAMfAAYJrxiaDQCKAQAfAAYJrxiaDQCKAQABAAIJQAJANgA6AAAuAAQKfy8AAx8ACQk+IIcWADMCAB8ACQk+IIcWADMCAAEAAQlwBUSIACcAAAAA.Kaylierocks:BAAALgAECgEJAQAAAA==.Kayyfrost:BAAALgADCgIJAgAAAA==.Kazeral:BAAALgADCggJEQAAAA==.',
Ke='Keedrid:BAABLgAECn8WAAIjAAkJbh22NAAsAgAjAAkJbh22NAAsAgAAAA==.Keindis:BAAALgAECgcJDwABLgAECgcJNgAfAOgPAA==.Kelaeno:BAAALgAECgMJAwABLgAECggJHQAGAAwHAA==.Kelemenohpea:BAABLgAECn8dAAIGAAgJDAcVlQD2AAAGAAgJDAcVlQD2AAAAAA==.Kelox:BAAALgAECgEJAQAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn81AAIdAAkJ1iHeBgBCAwAdAAkJ1iHeBgBCAwAAAA==.Kruàlty:BAACLgAFFH8HAAIPAAUJ5RKuCAAgAQAPAAUJ5RKuCAAgAQAuAAQKfyQAAg8ACAmCHa0HAFwCAA8ACAmCHa0HAFwCAAAA.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwANAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgAECgEJAQABLgAECgcJGQADAJoKAA==.Legreecast:BAABLgAECn8ZAAIDAAcJmgp+CAAUAQADAAcJmgp+CAAUAQAAAA==.Levlia:BAAALgADCgYJBgAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ+BKACCAQABAAkJGQ+BKACCAQAfAAIJ2wehggA4AAAcAAEJrgFIiwAaAAAAAA==.',
Lo='Loamuhwea:BAAALgAECgQJBAAAAA==.Lodur:BAABLgAECn8uAAIdAAkJlRvCGgB0AgAdAAkJlRvCGgB0AgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn80AAIlAAkJJhOKFgCeAQAlAAkJJhOKFgCeAQAAAA==.Losat:BAABLgAECn89AAIYAAkJzg1rGAB7AQAYAAkJzg1rGAB7AQAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8bAAIKAAkJxxvFKABfAgAKAAkJxxvFKABfAgAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwANAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAABLgAFFH8GAAIcAAMJQwuENgCxAAAcAAMJQwuENgCxAAAAAA==.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Mackavelian:BAAALgAECgEJAQABLgAECgkJNwAbAGAWAA==.Mackkie:BAABLgAECn83AAMbAAkJYBbMHwAcAgAbAAgJgRfMHwAcAgATAAgJBg6zLQBVAQAAAA==.Madonkadonk:BAABLgAECn82AAMhAAkJwhBTBwDKAQAhAAkJwhBTBwDKAQAiAAMJlAUWiwBGAAAAAA==.Maedai:BAABLgAECn81AAIbAAkJyhZNGQBOAgAbAAkJyhZNGQBOAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAACLgAFFH8IAAILAAQJbBa7IgAKAQALAAQJbBa7IgAKAQAuAAQKfzsAAwsACQk3HiMUAG0CAAsACQk3HiMUAG0CAAoABQm7EJ8LAaoAAAEuAAUUBAkJABcA+woA.Magús:BAAALgAECgEJAgAAAA==.Maldive:BAABLgAECn8uAAIWAAkJZREtRQDLAQAWAAkJZREtRQDLAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Maliificent:BAAALgAECgEJAQAAAA==.Mallicia:BAACLgAFFH8SAAIBAAQJkSFjDwBbAQABAAQJkSFjDwBbAQAuAAQKfzcAAwEACQm4I5cDACADAAEACQm4I5cDACADABwACAmiF74VACwCAAAA.Mallika:BAABLgAECn8mAAMdAAgJvxepKAAbAgAdAAgJvxepKAAbAgAVAAEJ3wkUqgAsAAABLgAFFAQJEgABAJEhAA==.Mallistraza:BAAALgAECgIJAwABLgAFFAQJEgABAJEhAA==.Mallwizard:BAACLgAFFH8JAAIWAAMJjAbzhwC2AAAWAAMJjAbzhwC2AAAuAAQKfy0AAhYACQnEFZQ4ACkCABYACQnEFZQ4ACkCAAAA.Mandor:BAAALgADCgYJBgAAAA==.Mangopewpew:BAAALgAECgUJDwAAAA==.Marks:BAAALgAECgEJAQAAAA==.Martris:BAAALgAECgIJBAAAAA==.Massoflice:BAACLgAFFH8MAAIjAAQJSglDgAAHAQAjAAQJSglDgAAHAQAuAAQKfyoAAiMACQn2F0w4AB4CACMACQn2F0w4AB4CAAAA.Maxblaide:BAAALgAECgcJEwAAAA==.Maxilla:BAAALgADCgcJDQABLgAFFAQJCQAXAPsKAA==.',
Me='Menguli:BAAALgAECgIJAgAAAA==.Meridians:BAABLgAECn8bAAIbAAYJxxbpPAB8AQAbAAYJxxbpPAB8AQAAAA==.',
Mh='Mhataharii:BAAALgAECgEJAQAAAA==.',
Mi='Mindhorn:BAACLgAFFH8MAAMVAAMJkxpoLwDVAAAVAAMJkxpoLwDVAAAdAAIJrRk7WgCYAAAuAAQKfycAAxUACAk0IXgQAG8CABUACAk0IXgQAG8CAB0ABAnTFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn80AAIIAAkJOhnnCgAbAgAIAAkJOhnnCgAbAgAAAA==.Moctar:BAAALgADCgQJBAAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIKAAgJJyAcMwBWAgAKAAgJJyAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAECgkJIgAiAHYUAA==.Musashi:BAABLgAFFH8HAAIEAAUJ8RKrCQCtAAAEAAUJ8RKrCQCtAAAAAA==.Mustardhunt:BAAALgADCgcJDAAAAA==.',
My='Myriad:BAABLgAECn8vAAIYAAkJmh9TBgCnAgAYAAkJmh9TBgCnAgAAAA==.',
Na='Nakze:BAABLgAECn82AAISAAkJAg/dGADTAQASAAkJAg/dGADTAQAAAA==.Namanari:BAAALgAECgEJAQAAAA==.Namfoodle:BAAALgADCgkJCQAAAA==.Nancydru:BAAALgAECgQJBAAAAA==.Nardwuar:BAAALgAECgYJDAABLgAFFAEJAwANAAAAAA==.Naris:BAAALgADCgYJBgAAAA==.Nastyfigs:BAABLgAECn8xAAIEAAkJURwQGwCDAgAEAAkJURwQGwCDAgAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.Neptune:BAABLgAECn8XAAICAAkJuRAdUADrAQACAAkJuRAdUADrAQAAAA==.',
Nh='Nhilas:BAAALgAECgQJDAAAAA==.',
Ni='Nightstryke:BAAALgAECgEJAQAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
No='Nork:BAAALgAECgIJAgAAAA==.',
Ny='Nyxaries:BAABLgAECn8gAAIOAAgJqhjKEwDWAQAOAAgJqhjKEwDWAQAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
On='Onenytestand:BAAALgAECgkJCAAAAA==.',
Or='Ordis:BAAALgADCgQJBAAAAA==.Orrana:BAAALgAECgEJAQAAAA==.',
Pa='Pablo:BAABLgAECn8VAAIKAAgJKxa6AgAtAQAKAAgJKxa6AgAtAQAAAA==.Pannacea:BAAALgAECgYJDQABLgAECgkJNQAdANYhAA==.Panzerblitz:BAABLgAECn8cAAIlAAgJhQmdNgDNAAAlAAgJhQmdNgDNAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIeAAcJNQoFIABSAQAeAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgADCggJDAAAAA==.',
Pe='Pedrote:BAAALgAECgEJAQAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Peppert:BAAALgAECggJCAAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Ph='Phane:BAAALgAECgUJCQAAAA==.Phson:BAAALgADCgkJDgAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIEAAYJOCApKgANAgAEAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pincher:BAAALgADCgQJBAAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piouspint:BAAALgAECgYJBgAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAABLgAECn8hAAIZAAcJUwknMwD6AAAZAAcJUwknMwD6AAAAAA==.Pretzelz:BAAALgAECgMJAwAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puertoricanj:BAAALgAECgMJAgAAAA==.Puffer:BAABLgAECn87AAICAAkJSxG9WgDNAQACAAkJSxG9WgDNAQAAAA==.',
Ra='Rabone:BAAALgAECgUJBQAAAA==.Raelaris:BAAALgAFFAIJAwABLgAFFAUJEwACANgjAA==.Raevyn:BAAALgAECgYJBgAAAA==.Raito:BAABLgAECn8gAAIKAAgJcgtingA6AQAKAAgJcgtingA6AQAAAA==.Rakshasa:BAACLgAFFH8NAAIWAAQJeh0pOgBjAQAWAAQJeh0pOgBjAQAuAAQKfykAAxYACQnJIpAMAOkCABYACQnJIpAMAOkCACQAAQkAALIhAGsAAAAA.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJCQABLgAECgkJIwAEAGgcAA==.Rasetsungo:BAABLgAECn8iAAIBAAkJqhxYDAChAgABAAkJqhxYDAChAgAAAA==.Raura:BAABLgAECn8jAAIOAAcJuRK+IABNAQAOAAcJuRK+IABNAQAAAA==.Rayala:BAAALgAECgkJCQAAAA==.',
Re='Recalcitrent:BAAALgADCgYJCAAAAA==.Redblueblurr:BAABLgAECn8oAAIKAAkJlxDHUgDRAQAKAAkJlxDHUgDRAQAAAA==.Remi:BAABLgAECn8iAAMBAAgJrBr0EQBQAgABAAgJrBr0EQBQAgAfAAEJ3RNkgAA8AAAAAA==.Reveillark:BAABLgAECn8UAAIgAAYJYhfVEgCbAQAgAAYJYhfVEgCbAQAAAA==.Revelaiden:BAAALgAECgEJAQABLgAECgkJPAAJAF0UAA==.',
Ro='Rolan:BAACLgAFFH8KAAIjAAQJDyX6LwCoAQAjAAQJDyX6LwCoAQAuAAQKfx4AAiMACQnYJPAWAL0CACMACQnYJPAWAL0CAAAA.Roogyrunes:BAAALgAECgcJCQABLgAECgkJIwAKAIUjAA==.Rosalian:BAABLgAECn81AAIFAAkJJhysEADLAgAFAAkJJhysEADLAgAAAA==.Rotiko:BAABLgAECn8kAAIdAAkJRQwhRQCZAQAdAAkJRQwhRQCZAQAAAA==.Roweene:BAABLgAECn84AAIoAAkJugjUCwBYAQAoAAkJugjUCwBYAQAAAA==.',
Ry='Ryez:BAAALgAECgEJAQAAAA==.Ryusei:BAAALgAECgQJBAAAAA==.',
['Rá']='Rágnar:BAABLgAECn8YAAQKAAkJ/Q5GYwCqAQAKAAkJJg5GYwCqAQAIAAgJZgi8KwC/AAALAAMJSQZHdABoAAAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgAECgUJBgAAAA==.',
Se='Seiko:BAAALgADCgEJAQAAAA==.Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8nAAMTAAgJdh9kEgAuAgATAAgJdh9kEgAuAgAUAAEJEws+hQA8AAABLgAECgkJDgANAAAAAA==.Serenatee:BAABLgAECn8xAAIfAAkJnhDcIQC4AQAfAAkJnhDcIQC4AQAAAA==.',
Sh='Shadowkrak:BAAALgAECgEJAgAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgADCgcJBwAAAA==.Shamwow:BAAALgADCgkJGAAAAA==.Shappens:BAAALgADCgcJEwABLgAECggJHAAKAFcMAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAAALgAECgYJEgAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAACLgAFFH8HAAIGAAMJcA33aQC4AAAGAAMJcA33aQC4AAAuAAQKfx0AAgYACQlzEsw9ANEBAAYACQlzEsw9ANEBAAAA.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgcJJQAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgAECgEJAQAAAA==.Silentmaster:BAAALgADCgkJCQAAAA==.Simbà:BAAALgAECgYJEAAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8YAAMGAAcJGSHEIQCGAgAGAAcJGSHEIQCGAgAJAAEJ9hZVawA7AAABLgAECgkJGQAmAP0iAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAACLgAFFH8MAAISAAMJ7Be2BQCTAAASAAMJ7Be2BQCTAAAuAAQKfxQAAxIABglfHicgAJUBABIABQlfHicgAJUBACcAAwlRGuIkAEEAAAAA.',
So='Soferfax:BAAALgADCgYJEgAAAA==.Sokroar:BAABLgAFFH8FAAIjAAIJaQw25gCBAAAjAAIJaQw25gCBAAAAAA==.Sonknight:BAABLgAECn8pAAMLAAYJswcmVQDjAAALAAYJswcmVQDjAAAKAAUJ8QIKOgFyAAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAIVAAgJZB2nGQAUAgAVAAgJZB2nGQAUAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn9GAAImAAkJzQrLAAAzAQAmAAkJzQrLAAAzAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgQJCwAAAA==.Sto:BAABLgAECn8UAAIKAAgJ7hr9NgAlAgAKAAgJ7hr9NgAlAgAAAA==.Stratof:BAAALgADCgIJAgAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Subjugaiden:BAAALgAECgEJAQABLgAECgkJPAAJAF0UAA==.Sukerpunch:BAAALgADCgEJAQAAAA==.Supad:BAAALgADCgYJBwAAAA==.Superjpriest:BAAALgAFFAEJAQABLgAFFAMJAwANAAAAAA==.Suria:BAABLgAECn8zAAIFAAkJUR8zCQAmAwAFAAkJUR8zCQAmAwAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgIJAgAAAA==.Syphax:BAAALgAECgMJAwAAAA==.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Taekwondovan:BAAALgAECgMJAwABLgAECgkJQQAOAOkjAA==.Tahrovin:BAAALgAECgIJAgAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgAECgEJAQAAAA==.Taternutzz:BAAALgAECgEJAQAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8yAAMBAAkJfSGoCADfAgABAAgJih+oCADfAgAcAAgJLx6LCwC2AgAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn9BAAMLAAkJzwWaPQBPAQALAAkJzwWaPQBPAQAKAAgJxgssCQBwAAAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.Teenyshieva:BAAALgADCgEJAQAAAA==.',
Th='Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgAECgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thillas:BAAALgAECgEJAQAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thorek:BAAALgAECgEJAQAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Threign:BAEALgADCgkJCQABLgAECgkJIgAWAI4WAA==.Thundercups:BAABLgAECn82AAIaAAkJPiHKAwDAAgAaAAkJPiHKAwDAAgAAAA==.',
Ti='Tigerstarr:BAACLgAFFH8MAAIjAAMJ1BABogDSAAAjAAMJ1BABogDSAAAuAAQKfx4AAyMACQm7E887ABECACMACQm7E887ABECABAAAQlRBioZACoAAAAA.Timboslicé:BAAALgAECgcJDAAAAA==.Tinyshieva:BAABLgAECn8bAAMBAAYJTA7WPgD1AAABAAYJTA7WPgD1AAAfAAQJTwPnaAB6AAAAAA==.Tizuki:BAAALgAECgIJAwAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgkJDQAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn8yAAIeAAgJqhwDBQAmAgAeAAgJqhwDBQAmAgAAAA==.Treenn:BAABLgAECn8fAAMdAAYJ9BQoAgAeAQAdAAYJ9BQoAgAeAQAVAAMJ/wT7hQBkAAAAAA==.Triplock:BAAALgAECgcJCgAAAA==.Trolcain:BAABLgAECn8xAAIjAAkJOyTPCAArAwAjAAkJOyTPCAArAwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgkJMQAjADskAA==.',
Ty='Tyrix:BAABLgAECn8jAAIKAAkJhSP5CgAOAwAKAAkJhSP5CgAOAwAAAA==.Tyránt:BAACLgAFFH8QAAIEAAQJpREnSQAbAQAEAAQJpREnSQAbAQAuAAQKfzEAAwQACQlNI+MMAOwCAAQACQlNI+MMAOwCABEAAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAIUAAYJ2BmCQABCAQAUAAYJ2BmCQABCAQAAAA==.',
Va='Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCwAAAA==.Valerossi:BAABLgAECn84AAImAAkJlx8WBQDXAgAmAAkJlx8WBQDXAgAAAA==.Valha:BAABLgAECn8mAAIJAAkJeRLMFwDFAQAJAAkJeRLMFwDFAQAAAA==.Valira:BAAALgADCggJCQABLgAECgkJIwAEAGgcAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgAECgIJAwAAAA==.Varleyna:BAAALgAECgQJBAABLgAFFAQJEgABAJEhAA==.Varteras:BAABLgAECn8yAAMkAAkJsxtRBgAZAgAkAAgJghtRBgAZAgAWAAgJnxKDVgCZAQAAAA==.',
Ve='Veleiri:BAABLgAECn81AAICAAkJLRKCSQD/AQACAAkJLRKCSQD/AQAAAA==.Velenal:BAAALgAECgQJDAAAAA==.Vellron:BAABLgAECn8xAAIEAAkJhw6NRgDOAQAEAAkJhw6NRgDOAQAAAA==.',
Vo='Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAACLgAFFH8VAAMGAAYJMRcKOQBBAQAGAAUJPxkKOQBBAQAJAAIJHA1IIwCEAAAuAAQKfxYAAwkABgm1I48YAL4BAAkABgkKI48YAL4BAAYABAkfH95qAE8BAAAA.Wardkbriggle:BAACLgAFFH8OAAIOAAYJkx4aDQCsAQAOAAYJkx4aDQCsAQAuAAQKfyEAAg4ACQmoI7oDAAADAA4ACQmoI7oDAAADAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8YAAIUAAYJxRzXCwDXAQAUAAYJxRzXCwDXAQAuAAQKfyAAAhQACQkeIFELAH8CABQACQkeIFELAH8CAAAA.',
Wi='Wifi:BAAALgAECgIJBwAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMOAAYJeAWFNwCGAAAOAAQJGQaFNwCGAAAQAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn9AAAICAAkJ2xTdPAAnAgACAAkJ2xTdPAAnAgAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn84AAQSAAkJ4yQTAgBDAwASAAkJsyQTAgBDAwAnAAcJASMUBAB1AgAoAAYJth3ZCQCIAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJCwABLgAECgkJOAASAOMkAA==.',
Xh='Xhared:BAABLgAECn9BAAIOAAkJ6SOQAgAjAwAOAAkJ6SOQAgAjAwAAAA==.',
Ya='Yahtzee:BAAALgAECgMJBgAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIGAAgJBwMhvQCyAAAGAAgJBwMhvQCyAAAAAA==.',
Ye='Yesenia:BAAALgADCgkJCQAAAA==.',
Yk='Ykszord:BAAALgAECgEJAQAAAA==.',
Ze='Zephy:BAAALgAECgYJDgAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Zé']='Zéd:BAAALgAFFAEJAQABLgAFFAQJCgAEAJ8TAA==.',
['Åe']='Åeon:BAABLgAECn8aAAIEAAcJGRBpdgBTAQAEAAcJGRBpdgBTAQAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRhoAgAQAQApAAQJuRhoAgAQAQAuAAQKfzQAAykACQlVIMEAAP8CACkACQlVIMEAAP8CAAIABAmyF6r5AAcBAAAA.',
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
