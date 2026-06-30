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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Warlock-Demonology','Warrior-Arms','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','Priest-Discipline','Warlock-Destruction','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','DeathKnight-Unholy','Warlock-Affliction','Druid-Guardian','Hunter-Survival','Warrior-Fury','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aaronius:BAABLgAECn8uAAIBAAgJTwf1OAAXAQABAAgJTwf1OAAXAQAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8rAAMCAAkJyR21JgCAAgACAAkJwB21JgCAAgADAAUJNReKCwAeAQAAAA==.',
Ac='Acceptance:BAAALgAFFAIJAgAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8uAAIEAAkJFyJ1EQDFAgAEAAkJFyJ1EQDFAgAAAA==.Adora:BAABLgAECn8jAAIEAAkJaByrFACtAgAEAAkJaByrFACtAgAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aelise:BAAALgADCgQJBAABLgAECgkJPAAFAMkgAA==.',
Ag='Agaliarept:BAACLgAFFH8PAAIGAAQJkgu4FADuAAAGAAQJkgu4FADuAAAuAAQKfxYAAwcACAkYC5UaAMgAAAYABwnpBuCLAAsBAAcABwkPC5UaAMgAAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAABLgAECn8ZAAIIAAcJjBLWJADvAAAIAAcJjBLWJADvAAAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn88AAMJAAkJXRRcFQDjAQAJAAkJXRRcFQDjAQAGAAgJ8AfOdAA4AQAAAA==.',
Ak='Akumajoe:BAAALgAECgMJAwAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAFFAIJAgAAAA==.Alrook:BAABLgAECn8VAAMKAAgJ3xVAewB4AQAKAAgJ3xVAewB4AQALAAIJ4BHBdwBeAAAAAA==.Aluni:BAAALgAECgUJBQAAAA==.',
Am='Amethÿst:BAAALgAFFAIJAgAAAA==.Amoral:BAAALgAECgMJAwAAAA==.',
An='Angelneko:BAABLgAECn85AAIMAAkJaQ0OKQCKAQAMAAkJaQ0OKQCKAQAAAA==.Anitabj:BAAALgAFFAEJAQAAAA==.Annihilaiden:BAAALgAECgIJAgABLgAECgkJPAAJAF0UAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwANAAAAAA==.Aralak:BAAALgAECgIJAgABLgAECgkJNgAOAPggAA==.Arcaynemoon:BAABLgAECn8XAAIMAAYJWAM9VgDLAAAMAAYJWAM9VgDLAAAAAA==.Arcon:BAAALgAECgEJAQAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.Artikfox:BAAALgADCgEJAQAAAA==.',
As='Asterior:BAACLgAFFH8RAAMPAAYJvxdiAQBxAQAPAAUJmxtiAQBxAQAMAAEJTghkSQBNAAAuAAQKfywAAg8ACQnzIKcDANQCAA8ACQnzIKcDANQCAAAA.',
Au='Aug:BAAALgAECgIJAgABLgAECgkJHQAKAB0eAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgAECgEJAQAAAA==.Auroraa:BAABLgAECn8wAAIMAAgJiwnePgATAQAMAAgJiwnePgATAQAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgMJBAANAAAAAA==.',
Av='Avalectra:BAAALgAECgUJCAAAAA==.',
Ay='Aylana:BAAALgAECgYJBgAAAA==.',
Az='Azanost:BAAALgADCgQJBAABLgAECgkJJAAQAOAVAA==.Azmodeaz:BAABLgAECn9EAAIDAAkJxhtzAQCPAgADAAkJxhtzAQCPAgAAAA==.Aztrik:BAAALgAECgYJBgABLgAECgkJIwAKAIUjAA==.',
Ba='Bajapanti:BAABLgAECn9CAAIRAAkJKx5NAABPAgARAAkJKx5NAABPAgAAAA==.Ballyhøø:BAABLgAECn8aAAIMAAkJRhSKMQBWAQAMAAkJRhSKMQBWAQAAAA==.Banchory:BAAALgADCgQJBQAAAA==.Bandaron:BAAALgAECgQJCgAAAA==.Baxstab:BAABLgAECn82AAISAAkJ5xsTDQBVAgASAAkJ5xsTDQBVAgAAAA==.',
Bc='Bcam:BAAALgADCgYJBgAAAA==.',
Be='Beahon:BAAALgAECgQJEAAAAA==.Beelzebrad:BAAALgADCgkJCQAAAA==.Betruger:BAAALgAECgEJAQAAAA==.',
Bg='Bgeefiddy:BAAALgAECgMJAwAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJCgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackjak:BAAALgAECgEJAQAAAA==.Blackpatch:BAABLgAECn9DAAMTAAkJ6yJMAAANAwATAAkJ6yJMAAANAwAUAAgJ4gfgOAAYAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgYJDgAAAA==.Blargg:BAAALgADCgkJCQAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAABLgAFFH8KAAIVAAQJOhaEHwAjAQAVAAQJOhaEHwAjAQAAAA==.Blooming:BAAALgAECggJDQABLgAECggJHAAWAA4aAA==.Bloomsbeam:BAABLgAECn8cAAIGAAgJDBaHZgBZAQAGAAgJDBaHZgBZAQAAAA==.Bloomslinger:BAAALgADCgQJBAAAAA==.',
Bo='Bonusdk:BAAALgAECgYJBgABLgAECgkJMwAXAN4hAA==.Booneboy:BAABLgAECn8iAAMKAAgJTyFUJQBvAgAKAAgJTyFUJQBvAgAIAAQJ/Bc0AgAdAQAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8lAAMIAAkJXxXUGQBKAQAIAAkJ7BLUGQBKAQAKAAcJ3A0XpgAuAQABLgAFFAYJGwAYAPsUAA==.',
Br='Brennor:BAABLgAECn8zAAIKAAkJ5w4WaQCdAQAKAAkJ5w4WaQCdAQAAAA==.Brewslunt:BAACLgAFFH8SAAIZAAcJmBZtFgDLAQAZAAcJmBZtFgDLAQAuAAQKfywAAxkACAmfIZgTAH8CABkACAmfIZgTAH8CABMAAwnEC1NpAIIAAAEuAAUUCAkiABoA5RwA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Bubblydin:BAAALgAECgYJBgABLgAFFAMJCgAbAP0GAA==.Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAABLgAECn8uAAIaAAkJDRR4JAA0AgAaAAkJDRR4JAA0AgAAAA==.Cairyan:BAABLgAECn9AAAIHAAkJ1B1KAACAAgAHAAkJ1B1KAACAAgAAAA==.Caiya:BAAALgADCgcJBwABLgAECgkJOAASAOMkAA==.Capn:BAAALgADCgcJCQAAAA==.Carvil:BAABLgAECn8zAAMcAAkJGxa9BgDyAQAcAAkJGxa9BgDyAQAWAAMJjweP7gCDAAAAAA==.Castalia:BAABLgAECn8WAAIdAAYJ7QuTBADuAAAdAAYJ7QuTBADuAAAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8YAAICAAYJKBcnOACJAQACAAYJKBcnOACJAQAuAAQKfysAAgIACQkXJCocAAYDAAIACQkXJCocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAYJGAACACgXAA==.Celithe:BAABLgAECn8gAAIKAAgJpxSKXwCyAQAKAAgJpxSKXwCyAQAAAA==.Cendrian:BAABLgAECn8WAAIMAAcJYQutQwD+AAAMAAcJYQutQwD+AAAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8tAAICAAkJfhwLLgBhAgACAAkJfhwLLgBhAgAAAA==.Charmshield:BAAALgAECgUJBQAAAA==.Cheezle:BAAALgAECgkJCAAAAA==.Chiafix:BAABLgAECn8cAAIUAAgJDwxSMgA3AQAUAAgJDwxSMgA3AQABLgAECgkJPgAaAGMjAA==.Chipp:BAABLgAECn8UAAIUAAcJ/CbtBwC1AgAUAAcJ/CbtBwC1AgAAAA==.Chleo:BAAALgAECgMJBwAAAA==.Choco:BAACLgAFFH8kAAIeAAgJox3OAgDQAgAeAAgJox3OAgDQAgAuAAQKfykAAx4ACQnvI+QFAOgCAB4ACQnvI+QFAOgCAB8AAQkVG3ohAEkAAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAgJJAAeAKMdAA==.Chudster:BAABLgAECn8gAAMfAAkJ/RVFCACuAQAfAAkJ/RVFCACuAQAgAAUJDQh1YQC2AAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAABLgAECn8mAAMhAAgJcCAxCAB4AgAhAAgJcCAxCAB4AgAXAAEJixFKeQAwAAAAAA==.Conqueror:BAAALgAECgYJEAABLgAFFAMJCQAFAE8RAA==.',
Cr='Crawdaddy:BAABLgAECn8WAAIEAAcJJhJkcQBdAQAEAAcJJhJkcQBdAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAAALgAECgcJDwAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECggJHQAKAHcMAA==.Curmudge:BAABLgAECn9ZAAIFAAkJZxkqAQAqAgAFAAkJZxkqAQAqAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgANAAAAAA==.Cybele:BAABLgAECn8cAAIBAAcJCgziBQC0AAABAAcJCgziBQC0AAAAAA==.',
Da='Dakunaito:BAABLgAECn8hAAMiAAkJxiRjFADNAgAiAAkJTCRjFADNAgAQAAEJLiJqLgBnAAAAAA==.Dakunaitø:BAAALgAECgIJAgAAAA==.Danay:BAAALgAECgEJAgAAAA==.Danksquaddon:BAAALgADCgQJBAAAAA==.Darachane:BAABLgAECn84AAMdAAgJixDpBADiAAAdAAgJixDpBADiAAABAAEJxwK3egAfAAAAAA==.Darovan:BAAALgADCgMJAwABLgAECgkJRAAOAOkjAA==.Darthnater:BAAALgAECgcJCQAAAA==.Dauglow:BAAALgAECgcJCwAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgADCggJDwAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAFFAEJAgAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAABLgAECn8UAAIGAAYJkhkirwDJAAAGAAYJkhkirwDJAAAAAA==.Deltia:BAABLgAECn8xAAIVAAkJtBiMFgAxAgAVAAkJtBiMFgAxAgAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAQJEAAEAKURAA==.Demonagent:BAABLgAECn8UAAQJAAgJfhl3GgCsAQAJAAgJfhl3GgCsAQAGAAQJOwv3wACrAAAHAAIJFBhfLwBFAAAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8VAAMgAAYJ+hYhIABgAQAgAAYJ+hYhIABgAQAfAAIJfQ4ZCQBYAAAuAAQKfzAAAx8ACQkOH9YJAEICAB8ACQlbHNYJAEICACAACAlrG8obAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8cAAIWAAgJDhp9OgDwAQAWAAgJDhp9OgDwAQAAAA==.',
Di='Dimebagg:BAAALgAECgYJCgAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8sAAMBAAgJdx3+EgBEAgABAAgJdx3+EgBEAgAbAAMJDgnvRACRAAAAAA==.Dokspades:BAABLgAECn8UAAIaAAkJ/g8JMwDnAQAaAAkJ/g8JMwDnAQAAAA==.Dornoch:BAABLgAECn8kAAMLAAgJeCMQDQDAAgALAAgJeCMQDQDAAgAKAAEJ8AE1XAEjAAAAAA==.Dotzilla:BAABLgAECn8XAAQWAAcJViU6VQCdAQAWAAUJeyQ6VQCdAQAjAAIJ9iXlHADXAAAcAAIJbSTgLQBhAAAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJCQAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8tAAIKAAkJ2g3tbgCQAQAKAAkJ2g3tbgCQAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECggJFAAJAH4ZAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAABLgAFFH8HAAIGAAIJ+h2NcwCgAAAGAAIJ+h2NcwCgAAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8PAAIiAAMJwRktlgDhAAAiAAMJwRktlgDhAAAuAAQKfzQAAiIACQknISYXALwCACIACQknISYXALwCAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAgAAAA==.',
Ei='Einherja:BAAALgAECgQJBgAAAA==.Eisenhorn:BAAALgAECgUJBgAAAA==.',
El='Elessaria:BAABLgAECn8iAAIFAAgJFwZDCACAAAAFAAgJFwZDCACAAAAAAA==.Elfatheàrt:BAABLgAECn8ZAAIKAAcJCRApsAAfAQAKAAcJCRApsAAfAQAAAA==.Elidrus:BAAALgADCgcJBwABLgAECgkJCQANAAAAAA==.Elira:BAAALgAECgEJAgAAAA==.',
Em='Emelgee:BAABLgAECn8cAAIkAAgJNAyNBADOAAAkAAgJNAyNBADOAAABLgAFFAMJCgAbAP0GAA==.Emofurry:BAAALgAECgUJBQAAAA==.',
En='End:BAAALgADCgEJAQAAAA==.',
Eo='Eon:BAAALgAECgEJAQAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgkJIwAEAGgcAA==.',
Es='Esika:BAAALgAFFAIJAwAAAA==.Estherras:BAABLgAECn8wAAIEAAkJXBqMJABQAgAEAAkJXBqMJABQAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgUJBQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Ez='Ezbeingreen:BAAALgAECgkJCQAAAA==.',
Fa='Fato:BAAALgAECgUJBgAAAA==.',
Fe='Feardotrun:BAABLgAECn8kAAMWAAkJhQ2/VgCYAQAWAAkJ2Qy/VgCYAQAcAAMJWQznJgB+AAAAAA==.Felicious:BAABLgAECn8UAAIGAAcJFBJ+hQAVAQAGAAcJFBJ+hQAVAQAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgAECgMJAgAAAA==.Finahlia:BAABLgAECn8kAAMFAAkJ7CHtBQBZAwAFAAkJ7CHtBQBZAwAkAAQJzyN0AQCcAQAAAA==.Finally:BAABLgAECn8mAAIVAAgJ/QgfUwDsAAAVAAgJ/QgfUwDsAAAAAA==.Firebat:BAAALgADCgcJBwABLgAECggJIgAKAE8hAA==.Firemage:BAABLgAECn82AAIWAAkJLiPABwAaAwAWAAkJLiPABwAaAwAAAA==.Fizzanelf:BAABLgAECn8mAAIFAAgJFSS4DwDVAgAFAAgJFSS4DwDVAgAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAACLgAFFH8NAAIKAAYJLwSrYgDqAAAKAAYJLwSrYgDqAAAuAAQKfzIAAgoACQkKGgBRAO4BAAoACQkKGgBRAO4BAAAA.Friendo:BAABLgAECn9FAAMPAAkJLRxGAACTAgAPAAkJLRxGAACTAgAMAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAFFAEJAwAAAA==.Frynied:BAAALgAECgUJCAABLgAECgkJIgABAKwaAA==.',
Fu='Furnost:BAABLgAECn8kAAIQAAkJ4BV/CQDtAQAQAAkJ4BV/CQDtAQAAAA==.Futnuraz:BAABLgAECn8iAAIXAAgJlAfDOgDaAAAXAAgJlAfDOgDaAAAAAA==.',
Fy='Fyrakkobama:BAAALgAECgkJBQABLgAECgkJGQAlAP0iAA==.Fyranne:BAAALgADCgkJCQAAAA==.Fyriat:BAABLgAECn81AAICAAkJ0wmxdgCMAQACAAkJ0wmxdgCMAQAAAA==.',
['Fì']='Fìjìt:BAAALgADCgIJAgAAAA==.',
Ga='Gabbee:BAAALgADCgkJCQAAAA==.Gazardiel:BAAALgAECgIJAgAAAA==.',
Ge='Getafix:BAAALgAECgcJCwABLgAECgkJPgAaAGMjAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Gimlore:BAAALgADCgEJAQAAAA==.Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8yAAITAAgJsxxaEABHAgATAAgJsxxaEABHAgAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goatmeal:BAAALgAECgkJBgAAAA==.Goldstorm:BAAALgADCgYJBgAAAA==.Goliath:BAAALgAECgYJEAABLgAECgkJGwAKAMcbAA==.Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8lAAIcAAkJIh1kAgCWAgAcAAkJIh1kAgCWAgAAAA==.Greybark:BAAALgADCgcJEQAAAA==.Griffindor:BAABLgAECn8zAAIKAAkJYBjkMgA0AgAKAAkJYBjkMgA0AgAAAA==.Grimfelborn:BAACLgAFFH8iAAMjAAYJgBIlCQDnAAAWAAUJVg7jOgBgAQAjAAQJ4BElCQDnAAAuAAQKfzIAAxYACQn1HLsxAEUCABYACQlMG7sxAEUCACMAAwlQIaghALUAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAABLgAECn8vAAIaAAgJLh9kGgB4AgAaAAgJLh9kGgB4AgAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgAECgEJAgAAAA==.',
Ha='Hahwe:BAAALgADCgEJAQAAAA==.Hanicus:BAAALgAECgkJCQAAAA==.Hanoverfiste:BAABLgAECn8dAAIKAAgJdwyUlABKAQAKAAgJdwyUlABKAQAAAA==.Hapsburg:BAABLgAECn8tAAIZAAkJKBPoJAD7AQAZAAkJKBPoJAD7AQAAAA==.Haranbae:BAAALgAECgIJAgAAAA==.Havince:BAABLgAECn82AAIOAAkJ+CATBwCrAgAOAAkJ+CATBwCrAgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn84AAIKAAkJsB/lFgC5AgAKAAkJsB/lFgC5AgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Ic='Icyvinz:BAAALgADCgQJBAAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Ig='Ignisdaemoni:BAAALgAECgMJBAABLgAECgkJJAAFAOwhAA==.',
Il='Illidai:BAAALgAECgYJEgAAAA==.Ilyndra:BAABLgAECn8zAAMXAAkJ3iF1BwCAAgAhAAkJeR2/BwCFAgAXAAgJsyF1BwCAAgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn81AAImAAkJuxYdGwAVAgAmAAkJuxYdGwAVAgAAAA==.',
It='Ithea:BAABLgAECn8xAAICAAkJCCHSEwDjAgACAAkJCCHSEwDjAgAAAA==.',
Ja='Jackyll:BAAALgAECgIJBwAAAA==.Jaeson:BAEBLgAECn8iAAIWAAkJjhZEMQATAgAWAAkJjhZEMQATAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAgJIAALAGscAA==.',
Je='Jeefrenzy:BAABLgAECn8ZAAMlAAkJ/SIMBQDYAgAlAAkJ/SIMBQDYAgAEAAIJkiGUAAFeAAAAAA==.Jeefwrld:BAAALgAECgQJBAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgcJEQAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8uAAQbAAkJvRmmAQDHAQAbAAgJrhSmAQDHAQABAAgJ5BPpHwDEAQAdAAUJDRSMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8dAAInAAgJ6g8YCgCYAQAnAAgJ6g8YCgCYAQAAAA==.',
Ju='Jughunter:BAACLgAFFH8KAAMEAAQJnxNaVgD6AAAEAAQJvgVaVgD6AAAlAAMJtRg3HADvAAAuAAQKfxYAAxEACAmkFl0SADcBACUABgkFFSQrAEkBABEACAnMEF0SADcBAAAA.Jugz:BAAALgADCgEJAQABLgAFFAQJCgAEAJ8TAA==.',
Jw='Jwise:BAAALgAECgkJBgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kamus:BAAALgAECgMJAwAAAA==.Kanabat:BAAALgAECgcJDgAAAA==.Karaden:BAAALgAECgUJBQAAAA==.Karawyn:BAABLgAECn8kAAIEAAgJ5Q5BPQC5AQAEAAgJ5Q5BPQC5AQABLgAECgcJCgANAAAAAA==.Karelix:BAAALgAECgMJBgAAAA==.Katrishy:BAACLgAFFH8iAAMdAAYJrxidDQCKAQAdAAYJrxidDQCKAQABAAIJQAJBNgA6AAAuAAQKfy8AAx0ACQk+IIcWADMCAB0ACQk+IIcWADMCAAEAAQlwBUSIACcAAAAA.Kaylierocks:BAAALgAECgEJAQAAAA==.Kayyfrost:BAAALgADCgIJAgAAAA==.Kazeral:BAAALgADCggJEQAAAA==.',
Ke='Keedrid:BAABLgAECn8WAAIiAAkJbh23NAAsAgAiAAkJbh23NAAsAgAAAA==.Keindis:BAAALgAECgcJEQABLgAECggJOAAdAIsQAA==.Kelaeno:BAAALgAECgkJDAAAAA==.Kelemenohpea:BAABLgAECn8dAAIGAAgJDAcYlQD2AAAGAAgJDAcYlQD2AAABLgAECgkJDAANAAAAAA==.Kelox:BAAALgAECgEJAQAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8+AAIaAAkJYyNVAABeAwAaAAkJYyNVAABeAwAAAA==.Kruàlty:BAACLgAFFH8HAAIPAAUJ5RKtCAAgAQAPAAUJ5RKtCAAgAQAuAAQKfyQAAg8ACAmCHa0HAFwCAA8ACAmCHa0HAFwCAAAA.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwANAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgAECgEJAQABLgAECggJGgADAN0LAA==.Legreecast:BAABLgAECn8aAAIDAAgJ3Qt+CAAUAQADAAgJ3Qt+CAAUAQAAAA==.Levlia:BAAALgADCgYJBgAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Lintball:BAAALgAECgMJAwAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ+GKACCAQABAAkJGQ+GKACCAQAdAAIJ2wepggA4AAAbAAEJrgFIiwAaAAAAAA==.',
Lo='Loamuhwea:BAAALgAECgQJBAAAAA==.Lodur:BAABLgAECn8uAAIaAAkJlRvEGgB0AgAaAAkJlRvEGgB0AgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn80AAIkAAkJJhOLFgCeAQAkAAkJJhOLFgCeAQAAAA==.Losat:BAABLgAECn9GAAIhAAkJ7g1tAQB5AQAhAAkJ7g1tAQB5AQAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8bAAIKAAkJxxvEKABfAgAKAAkJxxvEKABfAgAAAA==.Lunathir:BAAALgADCgMJAwABLgAFFAIJBAANAAAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwANAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAACLgAFFH8GAAIbAAMJQwt9NgCxAAAbAAMJQwt9NgCxAAAuAAQKfxQAAhsACQk4DcQhAMABABsACQk4DcQhAMABAAAA.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Machiato:BAAALgADCgEJAQAAAA==.Mackavelian:BAAALgAECgEJAQABLgAECgkJNwAZAGAWAA==.Mackkie:BAABLgAECn83AAMZAAkJYBbMHwAcAgAZAAgJgRfMHwAcAgATAAgJBg62LQBVAQAAAA==.Madonkadonk:BAABLgAECn82AAMfAAkJwhBTBwDKAQAfAAkJwhBTBwDKAQAgAAMJlAUZiwBGAAAAAA==.Maedai:BAABLgAECn83AAIZAAkJyhZMGQBOAgAZAAkJyhZMGQBOAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAACLgAFFH8IAAILAAQJbBa2IgAKAQALAAQJbBa2IgAKAQAuAAQKfzsAAwsACQk3HiIUAG0CAAsACQk3HiIUAG0CAAoABQm7EKYLAaoAAAEuAAUUBAkMACYAsBIA.Magús:BAAALgAECgEJAgAAAA==.Maldive:BAABLgAECn8vAAIWAAkJxRMuRQDLAQAWAAkJxRMuRQDLAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Maliificent:BAAALgAECgEJAQAAAA==.Mallicia:BAACLgAFFH8SAAIBAAQJkSFhDwBbAQABAAQJkSFhDwBbAQAuAAQKfz4AAwEACQm4I5cDACADAAEACQm4I5cDACADABsACAlbGMAVACwCAAAA.Mallika:BAABLgAECn8mAAMaAAgJvxerKAAbAgAaAAgJvxerKAAbAgAVAAEJ3wkZqgAsAAABLgAFFAQJEgABAJEhAA==.Mallistraza:BAAALgAECgIJAwABLgAFFAQJEgABAJEhAA==.Mallwizard:BAACLgAFFH8JAAIWAAMJjAbkhwC2AAAWAAMJjAbkhwC2AAAuAAQKfy0AAhYACQnEFZQ4ACkCABYACQnEFZQ4ACkCAAAA.Mandor:BAAALgADCgYJBgAAAA==.Mangopewpew:BAAALgAECgUJDwAAAA==.Marks:BAAALgAECgEJAQAAAA==.Martris:BAAALgAECgIJBAAAAA==.Massoflice:BAACLgAFFH8NAAIiAAQJAgs8gAAHAQAiAAQJAgs8gAAHAQAuAAQKfzEAAiIACQkDGtAFAEgBACIACQkDGtAFAEgBAAAA.Maxblaide:BAAALgAECgcJEwAAAA==.Maxilla:BAAALgADCgcJDQABLgAFFAQJDAAmALASAA==.',
Me='Menguli:BAAALgAECgIJAgAAAA==.Meridians:BAABLgAECn8bAAIZAAYJxxbsPAB8AQAZAAYJxxbsPAB8AQAAAA==.',
Mh='Mhataharii:BAAALgAECgEJAgAAAA==.',
Mi='Mindhorn:BAACLgAFFH8MAAMVAAMJkxpnLwDVAAAVAAMJkxpnLwDVAAAaAAIJrRk/WgCYAAAuAAQKfycAAxUACAk0IXcQAG8CABUACAk0IXcQAG8CABoABAnTFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn89AAIIAAkJ8RmGAAAwAgAIAAkJ8RmGAAAwAgAAAA==.Moctar:BAAALgADCgQJBAAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIKAAgJJyAcMwBWAgAKAAgJJyAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAECgkJIgAgAHYUAA==.Musashi:BAABLgAFFH8LAAIEAAUJVxvyCABoAQAEAAUJVxvyCABoAQAAAA==.Mustardhunt:BAAALgADCgcJDAAAAA==.',
My='Myriad:BAABLgAECn8vAAIhAAkJmh9RBgCnAgAhAAkJmh9RBgCnAgAAAA==.',
Na='Nakze:BAABLgAECn82AAISAAkJAg/eGADTAQASAAkJAg/eGADTAQAAAA==.Namanari:BAAALgAECgEJAQAAAA==.Namfoodle:BAAALgADCgkJCQAAAA==.Nancydru:BAAALgAECgQJBAAAAA==.Nardwuar:BAAALgAECgYJDAABLgAFFAEJAwANAAAAAA==.Naris:BAAALgAECgMJAwAAAA==.Nastyfigs:BAABLgAECn8xAAIEAAkJURwPGwCDAgAEAAkJURwPGwCDAgAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.Neptune:BAABLgAECn8bAAICAAkJbxGbCAApAQACAAkJbxGbCAApAQAAAA==.',
Nh='Nhilas:BAAALgAECgQJDAAAAA==.',
Ni='Nightstryke:BAAALgAECgEJAQAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
No='Nork:BAAALgAECgIJAgAAAA==.',
Ny='Nyxaries:BAABLgAECn8gAAIOAAgJqhjLEwDWAQAOAAgJqhjLEwDWAQAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
On='Onenytestand:BAAALgAECgkJCAAAAA==.',
Or='Ordis:BAAALgADCgQJBAAAAA==.Orrana:BAAALgAECgEJAQAAAA==.',
Pa='Pablo:BAABLgAECn8WAAIKAAkJuBY5BQB1AQAKAAkJuBY5BQB1AQAAAA==.Pannacea:BAAALgAECgYJDQABLgAECgkJPgAaAGMjAA==.Panzerblitz:BAABLgAECn8cAAIkAAgJhQmfNgDNAAAkAAgJhQmfNgDNAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIcAAcJNQoFIABSAQAcAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgADCggJDAAAAA==.',
Pe='Pedrote:BAAALgAECgEJAQAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Peppert:BAAALgAECggJCAAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Ph='Phane:BAAALgAECgUJCQAAAA==.Phson:BAAALgADCgkJDgAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIEAAYJOCApKgANAgAEAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pincher:BAAALgADCgQJBAAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piouspint:BAAALgAECgYJBgAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAABLgAECn8hAAIXAAcJUwknMwD6AAAXAAcJUwknMwD6AAAAAA==.Pretzelz:BAAALgAECgMJBQAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puertoricanj:BAAALgAECgMJAgAAAA==.Puffer:BAABLgAECn9EAAICAAkJ7BInAwDrAQACAAkJ7BInAwDrAQAAAA==.',
Ra='Rabone:BAAALgAECgUJBQAAAA==.Raelaris:BAAALgAFFAIJAwABLgAFFAUJEwACANgjAA==.Raevyn:BAAALgAECgYJBwAAAA==.Raeyla:BAAALgADCgEJAQAAAA==.Raito:BAABLgAECn8nAAIKAAgJPw1VCAAnAQAKAAgJPw1VCAAnAQAAAA==.Rakshasa:BAACLgAFFH8OAAIWAAQJeh0GOgBjAQAWAAQJeh0GOgBjAQAuAAQKfykAAxYACQnJIpAMAOkCABYACQnJIpAMAOkCACMAAQkAALIhAGsAAAAA.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJCgABLgAECgkJIwAEAGgcAA==.Rasetsungo:BAABLgAECn8iAAIBAAkJqhxYDAChAgABAAkJqhxYDAChAgAAAA==.Raura:BAABLgAECn8kAAIOAAgJWxS9IABNAQAOAAgJWxS9IABNAQAAAA==.Rayala:BAAALgAECgkJCQAAAA==.',
Re='Recalcitrent:BAAALgAECgEJAQAAAA==.Redblueblurr:BAABLgAECn8oAAIKAAkJlxDEUgDRAQAKAAkJlxDEUgDRAQAAAA==.Remi:BAABLgAECn8iAAMBAAgJrBr0EQBQAgABAAgJrBr0EQBQAgAdAAEJ3RNsgAA8AAAAAA==.Reveillark:BAABLgAECn8UAAIeAAYJYhfWEgCbAQAeAAYJYhfWEgCbAQAAAA==.Revelaiden:BAAALgAECgEJAQABLgAECgkJPAAJAF0UAA==.',
Ro='Rolan:BAACLgAFFH8KAAIiAAQJDyXpLwCoAQAiAAQJDyXpLwCoAQAuAAQKfx4AAiIACQnYJPAWAL0CACIACQnYJPAWAL0CAAAA.Roogyrunes:BAAALgAECgcJCQABLgAECgkJIwAKAIUjAA==.Rosalian:BAABLgAECn81AAIFAAkJJhytEADLAgAFAAkJJhytEADLAgAAAA==.Rotiko:BAABLgAECn8kAAIaAAkJRQwlRQCZAQAaAAkJRQwlRQCZAQAAAA==.Roweene:BAABLgAECn84AAIoAAkJugjUCwBYAQAoAAkJugjUCwBYAQAAAA==.',
Ry='Ryez:BAAALgAECgEJAQAAAA==.Ryusei:BAAALgAECgQJBAAAAA==.',
['Rá']='Rágnar:BAABLgAECn8ZAAQKAAkJWw9DYwCqAQAKAAkJhA5DYwCqAQAIAAgJZgi6KwC/AAALAAMJSQZEdABoAAAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgAECgUJBgAAAA==.',
Se='Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8nAAMTAAgJdh9kEgAuAgATAAgJdh9kEgAuAgAUAAEJEws+hQA8AAABLgAECgkJDgANAAAAAA==.Serenatee:BAABLgAECn8xAAIdAAkJnhDdIQC4AQAdAAkJnhDdIQC4AQAAAA==.',
Sh='Shadowkrak:BAAALgAECgEJAgAAAA==.Shamikaze:BAAALgADCgcJBwAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgAECgYJBgAAAA==.Shamwow:BAAALgAECgMJAwAAAA==.Shappens:BAAALgADCgcJEwABLgAECggJHQAKAHcMAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAABLgAECn8VAAMEAAgJehD7DgDPAAAEAAgJehD7DgDPAAAlAAQJ/QI5SACaAAAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAACLgAFFH8HAAIGAAMJcA3saQC4AAAGAAMJcA3saQC4AAAuAAQKfx0AAgYACQlzEs89ANEBAAYACQlzEs89ANEBAAAA.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgcJJQAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgAECgEJAgAAAA==.Silentmaster:BAAALgAECgIJAgAAAA==.Simbà:BAAALgAECgYJEAAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8YAAMGAAcJGSHEIQCGAgAGAAcJGSHEIQCGAgAJAAEJ9hZVawA7AAABLgAECgkJGQAlAP0iAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAACLgAFFH8NAAISAAMJ7Bd3CwDYAAASAAMJ7Bd3CwDYAAAuAAQKfxQAAxIABglfHiggAJUBABIABQlfHiggAJUBACcAAwlRGuMkAEEAAAAA.',
So='Soferfax:BAAALgADCgYJEgAAAA==.Sokroar:BAABLgAFFH8FAAIiAAIJaQwz5gCBAAAiAAIJaQwz5gCBAAAAAA==.Solphera:BAAALgADCgEJAQAAAA==.Sonknight:BAABLgAECn8pAAMLAAYJswcnVQDjAAALAAYJswcnVQDjAAAKAAUJ8QIUOgFyAAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAIVAAgJZB2mGQAUAgAVAAgJZB2mGQAUAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn9GAAIlAAkJzQoZAgAsAQAlAAkJzQoZAgAsAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgQJDgAAAA==.Sto:BAABLgAECn8dAAIKAAkJHR6AAQCWAgAKAAkJHR6AAQCWAgAAAA==.Stratof:BAAALgADCgIJAwAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Subjugaiden:BAAALgAECgEJAQABLgAECgkJPAAJAF0UAA==.Sukerpunch:BAAALgADCgEJAQAAAA==.Supad:BAAALgADCgYJBwAAAA==.Superjpriest:BAAALgAFFAEJAQABLgAFFAMJAwANAAAAAA==.Suria:BAABLgAECn88AAIFAAkJySBWAABHAwAFAAkJySBWAABHAwAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgIJAgAAAA==.Syphax:BAAALgAECgQJBAAAAA==.',
['Sü']='Süperball:BAACLgAFFH8MAAImAAQJsBJBCgDvAAAmAAQJsBJBCgDvAAAuAAQKfy8AAyYACQmlHq8KALoCACYACQmlHq8KALoCACEABAlACldDAGMAAAAA.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Taekwondovan:BAAALgAECgMJAwABLgAECgkJRAAOAOkjAA==.Tahrovin:BAAALgAECgIJAgAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgAECgEJAQAAAA==.Taternutzz:BAAALgAECgEJAQAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8yAAMBAAkJfSGoCADfAgABAAgJih+oCADfAgAbAAgJLx6KCwC2AgAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn9KAAMLAAkJzwWcPQBPAQALAAkJzwWcPQBPAQAKAAkJGgwvCgAEAQAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.Teenyshieva:BAAALgADCgEJAQAAAA==.Terrafying:BAAALgADCgMJAwAAAA==.',
Th='Theefjeef:BAAALgAECgkJBgABLgAECgkJGQAlAP0iAA==.Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgAECgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thicclock:BAAALgAECgEJAQAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thillas:BAAALgAECgEJAQAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thorek:BAAALgAECgEJAQAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Threign:BAEALgADCgkJCQABLgAECgkJIgAWAI4WAA==.Thundercups:BAABLgAECn84AAIYAAkJViHJAwDAAgAYAAkJViHJAwDAAgAAAA==.',
Ti='Tigerstarr:BAACLgAFFH8MAAIiAAMJ1BD9oQDSAAAiAAMJ1BD9oQDSAAAuAAQKfx4AAyIACQm7E9E7ABECACIACQm7E9E7ABECABAAAQlRBioZACoAAAAA.Timboslicé:BAAALgAECgcJDQAAAA==.Tinyshieva:BAABLgAECn8bAAMBAAYJTA7bPgD1AAABAAYJTA7bPgD1AAAdAAQJTwPzaAB6AAAAAA==.Tizuki:BAAALgAECgIJAwAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgkJDQAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn87AAIcAAkJBBw5AAB7AgAcAAkJBBw5AAB7AgAAAA==.Treenn:BAABLgAECn8fAAMaAAYJ9BQ2BgAhAQAaAAYJ9BQ2BgAhAQAVAAMJ/wT5hQBkAAAAAA==.Triplock:BAAALgAECgcJCgAAAA==.Trolcain:BAABLgAECn86AAIiAAkJGyWKAABQAwAiAAkJGyWKAABQAwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgkJOgAiABslAA==.',
Ty='Tyrix:BAABLgAECn8jAAIKAAkJhSP7CgAOAwAKAAkJhSP7CgAOAwAAAA==.Tyránt:BAACLgAFFH8QAAIEAAQJpRElSQAbAQAEAAQJpRElSQAbAQAuAAQKfzEAAwQACQlNI98MAOwCAAQACQlNI98MAOwCABEAAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAIUAAYJ2BmCQABCAQAUAAYJ2BmCQABCAQAAAA==.',
Va='Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCwAAAA==.Valerossi:BAABLgAECn84AAIlAAkJlx8VBQDXAgAlAAkJlx8VBQDXAgAAAA==.Valha:BAABLgAECn8mAAIJAAkJeRLMFwDFAQAJAAkJeRLMFwDFAQAAAA==.Valira:BAAALgADCggJCQABLgAECgkJIwAEAGgcAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgAECgIJAwAAAA==.Varleyna:BAAALgAECgQJBAABLgAFFAQJEgABAJEhAA==.Varteras:BAABLgAECn8yAAMjAAkJsxtRBgAZAgAjAAgJghtRBgAZAgAWAAgJnxKCVgCZAQAAAA==.',
Ve='Veleiri:BAABLgAECn81AAICAAkJLRJ/SQD/AQACAAkJLRJ/SQD/AQAAAA==.Velenal:BAAALgAECgQJDgAAAA==.Vellron:BAABLgAECn86AAIEAAkJWhEVAwD2AQAEAAkJWhEVAwD2AQAAAA==.',
Vo='Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAACLgAFFH8WAAMGAAYJMRcAOQBBAQAGAAUJPxkAOQBBAQAJAAIJHA1MIwCEAAAuAAQKfxYAAwkABgm1I48YAL4BAAkABgkKI48YAL4BAAYABAkfH95qAE8BAAAA.Wardkbriggle:BAACLgAFFH8OAAIOAAYJkx4PDQCsAQAOAAYJkx4PDQCsAQAuAAQKfyEAAg4ACQmoI7gDAAADAA4ACQmoI7gDAAADAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8YAAIUAAYJxRzGCwDXAQAUAAYJxRzGCwDXAQAuAAQKfyAAAhQACQkeIFILAH8CABQACQkeIFILAH8CAAAA.',
Wi='Wifi:BAAALgAECgIJBwAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMOAAYJeAWFNwCGAAAOAAQJGQaFNwCGAAAQAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn9AAAICAAkJ2xTaPAAnAgACAAkJ2xTaPAAnAgAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn84AAQSAAkJ4yQTAgBDAwASAAkJsyQTAgBDAwAnAAcJASMUBAB1AgAoAAYJth3ZCQCIAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJCwABLgAECgkJOAASAOMkAA==.',
Xh='Xhared:BAABLgAECn9EAAIOAAkJ6SOPAgAjAwAOAAkJ6SOPAgAjAwAAAA==.',
Xy='Xylah:BAAALgADCgIJAgAAAA==.',
Ya='Yahtzee:BAAALgAECgMJBgAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIGAAgJBwMfvQCyAAAGAAgJBwMfvQCyAAAAAA==.',
Ye='Yesenia:BAAALgADCgkJCQAAAA==.',
Yk='Ykszord:BAAALgAECgEJAQAAAA==.',
Ze='Zephy:BAAALgAECgYJDgAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Zé']='Zéd:BAAALgAFFAEJAQABLgAFFAQJCgAEAJ8TAA==.',
['Åe']='Åeon:BAABLgAECn8bAAIEAAcJRhBkdgBTAQAEAAcJRhBkdgBTAQAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Ðr']='Ðráco:BAAALgADCgIJAgAAAA==.',
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
