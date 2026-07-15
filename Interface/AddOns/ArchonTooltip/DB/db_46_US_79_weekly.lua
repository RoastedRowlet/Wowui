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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Warlock-Demonology','Warrior-Arms','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','Priest-Discipline','Warlock-Destruction','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','Warlock-Affliction','Druid-Guardian','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aaronius:BAABLgAECn8uAAIBAAgJTwf1OAAXAQABAAgJTwf1OAAXAQAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8rAAMCAAkJyR21JgCAAgACAAkJwB21JgCAAgADAAUJNReKCwAeAQAAAA==.',
Ac='Acceptance:BAAALgAFFAIJBAAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8uAAIEAAkJFyJ1EQDFAgAEAAkJFyJ1EQDFAgAAAA==.Adora:BAABLgAECn8jAAIEAAkJaByrFACtAgAEAAkJaByrFACtAgAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aelise:BAAALgADCgQJBAABLgAECgkJPAAFAIchAA==.',
Ag='Agaliarept:BAACLgAFFH8PAAIGAAQJkgtbIgDdAAAGAAQJkgtbIgDdAAAuAAQKfxYAAwcACAkYC5UaAMgAAAYABwnpBuCLAAsBAAcABwkPC5UaAMgAAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAABLgAECn8ZAAIIAAcJjBLWJADvAAAIAAcJjBLWJADvAAAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn88AAMJAAkJXRRcFQDjAQAJAAkJXRRcFQDjAQAGAAgJ8AfOdAA4AQAAAA==.',
Ak='Akumajoe:BAAALgAECgMJAwAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aliyah:BAAALgAECgEJAQAAAA==.Aloria:BAAALgAFFAIJAgAAAA==.Alrook:BAABLgAECn8VAAMKAAgJ3xVAewB4AQAKAAgJ3xVAewB4AQALAAIJ4BHBdwBeAAAAAA==.Aluni:BAAALgAECgUJBQAAAA==.',
Am='Amethÿst:BAAALgAFFAIJAgAAAA==.Amoral:BAAALgAECgMJAwAAAA==.',
An='Angelneko:BAABLgAECn85AAIMAAkJaQ0OKQCKAQAMAAkJaQ0OKQCKAQAAAA==.Anitabj:BAAALgAFFAEJAQAAAA==.Annihilaiden:BAAALgAECgIJAgABLgAECgkJPAAJAF0UAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwANAAAAAA==.Aralak:BAAALgAECgIJAgABLgAECgkJNgAOAPggAA==.Arcaynemoon:BAABLgAECn8XAAIMAAYJWAM9VgDLAAAMAAYJWAM9VgDLAAAAAA==.Arcon:BAAALgAECgEJAQAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.Artikfox:BAAALgADCgEJAQAAAA==.',
As='Ashléng:BAAALgAECgEJAQAAAA==.Asterior:BAACLgAFFH8RAAMPAAYJvxdiAQBxAQAPAAUJmxtiAQBxAQAMAAEJTghkSQBNAAAuAAQKfywAAg8ACQnzIKcDANQCAA8ACQnzIKcDANQCAAAA.',
At='Atthis:BAAALgADCgQJBAAAAA==.',
Au='Aug:BAAALgAECgIJAgABLgAECgkJHQAKAKYfAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgAECgEJAQAAAA==.Auroraa:BAABLgAECn8yAAIMAAgJRArePgATAQAMAAgJRArePgATAQAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgUJBQANAAAAAA==.',
Av='Avalectra:BAAALgAECgUJCAAAAA==.',
Ay='Aylana:BAAALgAECgYJBgAAAA==.Aysu:BAAALgAECgUJBQAAAA==.',
Az='Azanost:BAAALgADCgQJBAABLgAECgkJJAAQAOAVAA==.Azmodeaz:BAABLgAECn9NAAIDAAkJRh1mAAAEAgADAAkJRh1mAAAEAgAAAA==.Aztrik:BAAALgAECgYJBgABLgAECgkJIwAKAIUjAA==.',
Ba='Bajapanti:BAABLgAECn9CAAIRAAkJ9R58AABqAgARAAkJ9R58AABqAgAAAA==.Ballyhøø:BAABLgAECn8aAAIMAAkJRhSKMQBWAQAMAAkJRhSKMQBWAQAAAA==.Banchory:BAAALgADCgQJBQAAAA==.Bandaron:BAAALgAECgQJCgAAAA==.Baxstab:BAABLgAECn82AAISAAkJ5xsTDQBVAgASAAkJ5xsTDQBVAgAAAA==.',
Bc='Bcam:BAAALgADCgYJBgAAAA==.',
Be='Beahon:BAAALgAECgQJEAAAAA==.Beelzebrad:BAAALgADCgkJCQAAAA==.Betruger:BAAALgAECgUJAQAAAA==.',
Bg='Bgarlath:BAAALgAECgQJBAAAAA==.Bgeefiddy:BAAALgAECgMJAwAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJCgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackjak:BAAALgAECgEJAQAAAA==.Blackpatch:BAABLgAECn9DAAMTAAkJSCN1AAAgAwATAAkJSCN1AAAgAwAUAAgJ4gfgOAAYAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgYJDgAAAA==.Blargg:BAAALgADCgkJCQAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blightmaker:BAAALgAECgEJAQABLgAECgkJIgAOANUXAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAABLgAFFH8KAAIVAAQJOhaEHwAjAQAVAAQJOhaEHwAjAQAAAA==.Blooming:BAAALgAECggJDQABLgAECggJHAAWAA4aAA==.Bloomsbeam:BAABLgAECn8cAAIGAAgJDBaHZgBZAQAGAAgJDBaHZgBZAQAAAA==.Bloomslinger:BAAALgADCgQJBAAAAA==.',
Bo='Bonusdk:BAAALgAECgYJBgABLgAECgkJMwAXAN4hAA==.Booneboy:BAABLgAECn8pAAMKAAkJ4yGgAwBUAgAKAAkJ4yGgAwBUAgAIAAQJ/Bc5BAAXAQAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8lAAMIAAkJXxXUGQBKAQAIAAkJ7BLUGQBKAQAKAAcJ3A0XpgAuAQABLgAFFAcJHAAYAKMTAA==.',
Br='Brennor:BAABLgAECn8zAAIKAAkJ5w4WaQCdAQAKAAkJ5w4WaQCdAQAAAA==.Brewslunt:BAACLgAFFH8SAAIZAAcJmBZtFgDLAQAZAAcJmBZtFgDLAQAuAAQKfywAAxkACAmfIZgTAH8CABkACAmfIZgTAH8CABMAAwnEC1NpAIIAAAEuAAUUCAkiABoA5RwA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Bubblydin:BAAALgAECgYJBgABLgAFFAMJCgAbAP0GAA==.Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAABLgAECn80AAIaAAkJLxV4JAA0AgAaAAkJLxV4JAA0AgAAAA==.Cairyan:BAABLgAECn9AAAIHAAkJ1B2KAACAAgAHAAkJ1B2KAACAAgAAAA==.Caiya:BAAALgADCgcJBwABLgAECgkJOAASAOMkAA==.Capn:BAAALgADCgcJCQAAAA==.Carvil:BAABLgAECn8zAAMcAAkJGxa9BgDyAQAcAAkJGxa9BgDyAQAWAAMJjweP7gCDAAAAAA==.Castalia:BAABLgAECn8dAAIdAAcJMRBKBQBIAQAdAAcJMRBKBQBIAQAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8YAAICAAYJKBcnOACJAQACAAYJKBcnOACJAQAuAAQKfysAAgIACQkXJCocAAYDAAIACQkXJCocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAYJGAACACgXAA==.Celithe:BAABLgAECn8gAAIKAAgJpxSKXwCyAQAKAAgJpxSKXwCyAQAAAA==.Cendrian:BAABLgAECn8WAAIMAAcJYQutQwD+AAAMAAcJYQutQwD+AAAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8tAAICAAkJfhwLLgBhAgACAAkJfhwLLgBhAgAAAA==.Charmshield:BAAALgAECgUJBQAAAA==.Cheezle:BAABLgAECn8ZAAMaAAkJJwjaCwAXAQAaAAkJJwjaCwAXAQAVAAgJEgEaowA2AAAAAA==.Chiafix:BAABLgAECn8cAAIUAAgJDwxSMgA3AQAUAAgJDwxSMgA3AQABLgAECgkJPgAaAKkjAA==.Chipp:BAABLgAECn8UAAIUAAcJ/CbtBwC1AgAUAAcJ/CbtBwC1AgAAAA==.Chleo:BAAALgAECgQJBwAAAA==.Choco:BAACLgAFFH8pAAIeAAkJ2BzOAgDQAgAeAAkJ2BzOAgDQAgAuAAQKfykAAx4ACQnvI+QFAOgCAB4ACQnvI+QFAOgCAB8AAQkVG3ohAEkAAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAkJKQAeANgcAA==.Chudster:BAABLgAECn8gAAMfAAkJ/RVFCACuAQAfAAkJ/RVFCACuAQAgAAUJDQh1YQC2AAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAABLgAECn8oAAMhAAkJ9CAxCAB4AgAhAAkJ9CAxCAB4AgAXAAEJixFKeQAwAAAAAA==.Conqueror:BAAALgAECgYJEAABLgAFFAMJCQAFAE8RAA==.',
Cr='Crawdaddy:BAABLgAECn8WAAIEAAcJJhJkcQBdAQAEAAcJJhJkcQBdAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAABLgAFFH8GAAIiAAMJiQrFFwDBAAAiAAMJiQrFFwDBAAAAAA==.',
Cu='Cupper:BAAALgADCgcJCgABLgAECgkJJAAKAK0SAA==.Curmudge:BAABLgAECn9aAAIFAAkJZBlMAgAhAgAFAAkJZBlMAgAhAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgANAAAAAA==.Cybele:BAABLgAECn8dAAIBAAgJPAsOCQDLAAABAAgJPAsOCQDLAAAAAA==.',
Da='Dakunaito:BAABLgAECn8hAAMjAAkJxiRjFADNAgAjAAkJTCRjFADNAgAQAAEJLiJqLgBnAAAAAA==.Dakunaitø:BAAALgAECgIJAgAAAA==.Danay:BAAALgAECgEJAgAAAA==.Danksquaddon:BAAALgAECgEJAQAAAA==.Darachane:BAABLgAECn84AAMdAAgJIBCuCQDVAAAdAAgJIBCuCQDVAAABAAEJxwK3egAfAAAAAA==.Darovan:BAAALgADCgMJAwABLgAECgkJSQAOAOkjAA==.Darthnater:BAABLgAFFH8KAAIjAAQJ6BWRHABNAQAjAAQJ6BWRHABNAQAAAA==.Dauglow:BAAALgAECgcJCwAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgADCggJDwAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAFFAEJAgAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAABLgAECn8UAAIGAAYJkhkirwDJAAAGAAYJkhkirwDJAAAAAA==.Deltia:BAABLgAECn8xAAIVAAkJtBiMFgAxAgAVAAkJtBiMFgAxAgAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAQJEwAEAKURAA==.Demonagent:BAABLgAECn8XAAQJAAkJNRp3GgCsAQAJAAkJNRp3GgCsAQAGAAQJOwv3wACrAAAHAAIJFBhfLwBFAAAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8WAAMgAAcJHhchIABgAQAgAAcJHhchIABgAQAfAAIJfQ4ZCQBYAAAuAAQKfzAAAx8ACQkOH9YJAEICAB8ACQlbHNYJAEICACAACAlrG8obAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8cAAIWAAgJDhp9OgDwAQAWAAgJDhp9OgDwAQAAAA==.Devonsemus:BAAALgAECgEJAQAAAA==.',
Di='Dimebagg:BAAALgAECgYJCgAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8sAAMBAAgJdx3+EgBEAgABAAgJdx3+EgBEAgAbAAMJDgnvRACRAAAAAA==.Dokspades:BAABLgAECn8UAAIaAAkJ/g8JMwDnAQAaAAkJ/g8JMwDnAQAAAA==.Dornoch:BAABLgAECn8kAAMLAAgJeCMQDQDAAgALAAgJeCMQDQDAAgAKAAEJ8AE1XAEjAAAAAA==.Dotzilla:BAABLgAECn8XAAQWAAcJViU6VQCdAQAWAAUJeyQ6VQCdAQAkAAIJ9iXlHADXAAAcAAIJbSTgLQBhAAAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJCQAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8tAAIKAAkJ2g3tbgCQAQAKAAkJ2g3tbgCQAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgkJFwAJADUaAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAABLgAFFH8HAAIGAAIJ+h2NcwCgAAAGAAIJ+h2NcwCgAAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8PAAIjAAMJwRktlgDhAAAjAAMJwRktlgDhAAAuAAQKfzQAAiMACQknISYXALwCACMACQknISYXALwCAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAgAAAA==.',
Ei='Einherja:BAAALgAECgQJBgAAAA==.Eisenhorn:BAAALgAECgUJBgAAAA==.',
El='Elessaria:BAABLgAECn8pAAIFAAkJ7QanCgC4AAAFAAkJ7QanCgC4AAAAAA==.Elfatheàrt:BAABLgAECn8ZAAIKAAcJCRApsAAfAQAKAAcJCRApsAAfAQAAAA==.Elidrus:BAAALgADCgcJBwABLgAECgkJCQANAAAAAA==.Elira:BAAALgAECgEJBQAAAA==.',
Em='Emelgee:BAABLgAECn8cAAIlAAgJNAwJCADNAAAlAAgJNAwJCADNAAABLgAFFAMJCgAbAP0GAA==.Emofurry:BAAALgAFFAEJAQABLgAFFAkJKQAeANgcAA==.',
En='End:BAAALgADCgEJAQAAAA==.',
Eo='Eon:BAAALgAECgEJAQAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgkJIwAEAGgcAA==.',
Es='Esika:BAAALgAFFAIJAwAAAA==.Estherras:BAABLgAECn8wAAIEAAkJXBqMJABQAgAEAAkJXBqMJABQAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgUJBQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Ez='Ezbeingreen:BAAALgAECgkJCQAAAA==.',
Fa='Fato:BAAALgAECgUJCQAAAA==.',
Fe='Feardotrun:BAABLgAECn8kAAMWAAkJhQ2/VgCYAQAWAAkJ2Qy/VgCYAQAcAAMJWQznJgB+AAAAAA==.Felicious:BAABLgAECn8UAAIGAAcJFBJ+hQAVAQAGAAcJFBJ+hQAVAQAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgAECgMJAgAAAA==.Finahlia:BAABLgAECn8pAAMFAAkJ7CHtBQBZAwAFAAkJ7CHtBQBZAwAlAAYJxSOJAQAGAgAAAA==.Finally:BAABLgAECn8mAAIVAAgJ/QgfUwDsAAAVAAgJ/QgfUwDsAAAAAA==.Firebat:BAAALgADCgcJDQABLgAECgkJKQAKAOMhAA==.Firemage:BAACLgAFFH8GAAIWAAQJEhiVbADqAAAWAAQJEhiVbADqAAAuAAQKfzYAAhYACQkuI8AHABoDABYACQkuI8AHABoDAAAA.Fizzanelf:BAABLgAECn8mAAIFAAgJFSS4DwDVAgAFAAgJFSS4DwDVAgAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAACLgAFFH8OAAIKAAYJLwSrYgDqAAAKAAYJLwSrYgDqAAAuAAQKfzIAAgoACQkKGgBRAO4BAAoACQkKGgBRAO4BAAAA.Friendo:BAABLgAECn9FAAMPAAkJsB2VAACLAgAPAAkJsB2VAACLAgAMAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAFFAEJAwAAAA==.Frynied:BAAALgAECgUJDAABLgAECgkJJAABAPEaAA==.',
Fu='Furnost:BAABLgAECn8kAAIQAAkJ4BV/CQDtAQAQAAkJ4BV/CQDtAQAAAA==.Futnuraz:BAABLgAECn8iAAIXAAgJlAfDOgDaAAAXAAgJlAfDOgDaAAAAAA==.',
Fy='Fyrakkobama:BAAALgAECgkJBQABLgAECgkJGQAmAP0iAA==.Fyranne:BAAALgADCgkJCQAAAA==.Fyriat:BAABLgAECn81AAICAAkJ0wmxdgCMAQACAAkJ0wmxdgCMAQAAAA==.',
['Fì']='Fìjìt:BAAALgADCgIJAgAAAA==.',
Ga='Gabbee:BAAALgADCgkJCQAAAA==.Gazardiel:BAAALgAECgIJAgAAAA==.',
Ge='Getafix:BAAALgAECgcJCwABLgAECgkJPgAaAKkjAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Gimlore:BAAALgADCgEJAQAAAA==.Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8yAAITAAgJsxxaEABHAgATAAgJsxxaEABHAgAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goatmeal:BAAALgAECgkJBgAAAA==.Goldstorm:BAAALgADCgYJBgAAAA==.Goliath:BAABLgAECn8ZAAIaAAcJQR3QAgBEAgAaAAcJQR3QAgBEAgABLgAECgkJGwAKAMcbAA==.Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8lAAIcAAkJIh1kAgCWAgAcAAkJIh1kAgCWAgAAAA==.Greybark:BAAALgADCgcJEQAAAA==.Griffindor:BAABLgAECn8zAAIKAAkJYBjkMgA0AgAKAAkJYBjkMgA0AgAAAA==.Grimfelborn:BAACLgAFFH8iAAMkAAYJgBIlCQDnAAAWAAUJVg7jOgBgAQAkAAQJ4BElCQDnAAAuAAQKfzIAAxYACQn1HLsxAEUCABYACQlMG7sxAEUCACQAAwlQIaghALUAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAABLgAECn8zAAIaAAkJ8B7TAwAGAgAaAAkJ8B7TAwAGAgAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.Gryphindor:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgAECgQJBgAAAA==.',
Ha='Hahwe:BAAALgADCgEJAQAAAA==.Hanicus:BAAALgAECgkJCQAAAA==.Hanoverfiste:BAABLgAECn8kAAIKAAkJrRI6CgBsAQAKAAkJrRI6CgBsAQAAAA==.Hapsburg:BAABLgAECn8tAAIZAAkJJhPoJAD7AQAZAAkJJhPoJAD7AQAAAA==.Haranbae:BAAALgAECgIJAgAAAA==.Havince:BAABLgAECn82AAIOAAkJ+CATBwCrAgAOAAkJ+CATBwCrAgAAAA==.Haylee:BAAALgAECgMJAwAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn84AAIKAAkJsB/lFgC5AgAKAAkJsB/lFgC5AgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Ic='Icyvinz:BAAALgADCgQJBAAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Ig='Ignisdaemoni:BAAALgAECgMJBAABLgAECgkJKQAFAOwhAA==.',
Il='Illidai:BAAALgAECgYJEgAAAA==.Ilyndra:BAABLgAECn8zAAMXAAkJ3iF1BwCAAgAhAAkJeR2/BwCFAgAXAAgJsyF1BwCAAgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn81AAIiAAkJuxYdGwAVAgAiAAkJuxYdGwAVAgAAAA==.',
It='Ithea:BAABLgAECn8xAAICAAkJCCHSEwDjAgACAAkJCCHSEwDjAgAAAA==.',
Iz='Izzy:BAAALgAECgEJAQAAAA==.',
Ja='Jackkychan:BAAALgAECgEJAQAAAA==.Jackyll:BAAALgAECgIJBwAAAA==.Jaeson:BAEBLgAECn8iAAIWAAkJjhZEMQATAgAWAAkJjhZEMQATAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAgJIAALAGscAA==.',
Je='Jeefrenzy:BAABLgAECn8ZAAMmAAkJ/SIMBQDYAgAmAAkJ/SIMBQDYAgAEAAIJkiGUAAFeAAAAAA==.Jeefwrld:BAAALgAECgUJBAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgcJEQAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8uAAQbAAkJ0hoeAwDOAQAbAAgJtRQeAwDOAQABAAgJFBXpHwDEAQAdAAUJDRSMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8lAAInAAkJwxa1AADDAQAnAAkJwxa1AADDAQAAAA==.',
Ju='Jughunter:BAACLgAFFH8KAAMEAAQJnxNaVgD6AAAEAAQJvgVaVgD6AAAmAAMJtRg3HADvAAAuAAQKfxYAAxEACAmkFl0SADcBACYABgkFFSQrAEkBABEACAnMEF0SADcBAAAA.Jugz:BAAALgADCgEJAQABLgAFFAQJCgAEAJ8TAA==.',
Jw='Jwise:BAAALgAECgkJBgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kamus:BAAALgAECgMJAwAAAA==.Kanabat:BAAALgAECgcJDgAAAA==.Karaden:BAAALgAECgUJBQAAAA==.Karawyn:BAABLgAECn8kAAIEAAgJ5Q5BPQC5AQAEAAgJ5Q5BPQC5AQABLgAFFAEJAQANAAAAAA==.Karelix:BAAALgAECgMJBgAAAA==.Katrishy:BAACLgAFFH8iAAMdAAYJrxidDQCKAQAdAAYJrxidDQCKAQABAAIJQAJBNgA6AAAuAAQKfy8AAx0ACQk+IIcWADMCAB0ACQk+IIcWADMCAAEAAQlwBUSIACcAAAAA.Kaylierocks:BAAALgAECgEJAQAAAA==.Kayyfrost:BAAALgADCgIJAgAAAA==.Kazeral:BAAALgADCggJEQAAAA==.',
Ke='Keedrid:BAABLgAECn8WAAIjAAkJbh23NAAsAgAjAAkJbh23NAAsAgAAAA==.Keindis:BAAALgAECgcJEQABLgAECggJOAAdACAQAA==.Kelaeno:BAAALgAECgkJDAAAAA==.Kelemenohpea:BAABLgAECn8dAAIGAAgJDAcYlQD2AAAGAAgJDAcYlQD2AAABLgAECgkJDAANAAAAAA==.Kelox:BAAALgAECgEJAQAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8+AAIaAAkJqSOSAABtAwAaAAkJqSOSAABtAwAAAA==.Kruàlty:BAACLgAFFH8PAAIPAAUJlx6jAQBlAQAPAAUJlx6jAQBlAQAuAAQKfyQAAg8ACAmCHa0HAFwCAA8ACAmCHa0HAFwCAAAA.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwANAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgAECgEJAQABLgAECggJGgADAN0LAA==.Legreecast:BAABLgAECn8aAAIDAAgJ3Qt+CAAUAQADAAgJ3Qt+CAAUAQAAAA==.Levlia:BAAALgADCgYJBgAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Lintball:BAAALgAECgMJAwAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ+GKACCAQABAAkJGQ+GKACCAQAdAAIJ2wepggA4AAAbAAEJrgFIiwAaAAAAAA==.',
Lo='Loamuhwea:BAAALgAECgQJBAAAAA==.Lodur:BAABLgAECn8uAAIaAAkJlRvEGgB0AgAaAAkJlRvEGgB0AgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn80AAIlAAkJJhOLFgCeAQAlAAkJJhOLFgCeAQAAAA==.Losat:BAABLgAECn9GAAIhAAkJYA89AgCXAQAhAAkJYA89AgCXAQAAAA==.',
Lu='Lucitano:BAAALgADCgYJCAAAAA==.Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8bAAIKAAkJxxvEKABfAgAKAAkJxxvEKABfAgAAAA==.Lunathir:BAAALgADCgMJAwABLgAFFAIJBAANAAAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwANAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAACLgAFFH8JAAIbAAMJhg59NgCxAAAbAAMJhg59NgCxAAAuAAQKfxUAAhsACQkjD8QhAMABABsACQkjD8QhAMABAAAA.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Machiato:BAAALgADCgEJAQAAAA==.Mackavelian:BAAALgAECgEJAQABLgAECgkJNwAZAGAWAA==.Mackkie:BAABLgAECn83AAMZAAkJYBbMHwAcAgAZAAgJgRfMHwAcAgATAAgJBg62LQBVAQAAAA==.Madonkadonk:BAABLgAECn82AAMfAAkJwhBTBwDKAQAfAAkJwhBTBwDKAQAgAAMJlAUZiwBGAAAAAA==.Maedai:BAABLgAECn83AAIZAAkJyhZMGQBOAgAZAAkJyhZMGQBOAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAgAAAA==.Magnaball:BAACLgAFFH8IAAILAAQJbBa2IgAKAQALAAQJbBa2IgAKAQAuAAQKfzsAAwsACQk3HiIUAG0CAAsACQk3HiIUAG0CAAoABQm7EKYLAaoAAAEuAAUUBAkNACIAsBIA.Magús:BAAALgAECgEJAgAAAA==.Maldive:BAABLgAECn8vAAIWAAkJxRMuRQDLAQAWAAkJxRMuRQDLAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Maliificent:BAAALgAECgEJAQAAAA==.Mallicia:BAACLgAFFH8SAAIBAAQJkSFhDwBbAQABAAQJkSFhDwBbAQAuAAQKfz4AAwEACQm4I5cDACADAAEACQm4I5cDACADABsACAlbGMAVACwCAAAA.Mallika:BAABLgAECn8mAAMaAAgJvxerKAAbAgAaAAgJvxerKAAbAgAVAAEJ3wkZqgAsAAABLgAFFAQJEgABAJEhAA==.Mallistra:BAAALgAECgEJAQABLgAFFAQJEgABAJEhAA==.Mallistraza:BAAALgAECgIJAwABLgAFFAQJEgABAJEhAA==.Mallwizard:BAACLgAFFH8JAAIWAAMJjAbkhwC2AAAWAAMJjAbkhwC2AAAuAAQKfy0AAhYACQnEFZQ4ACkCABYACQnEFZQ4ACkCAAAA.Mandor:BAAALgADCgYJBgAAAA==.Mangopewpew:BAAALgAECgUJDwAAAA==.Mariothestab:BAAALgAECgUJBgABLgAFFAQJCwACAOAJAA==.Marks:BAAALgAECgEJAQAAAA==.Martris:BAAALgAECgMJBQAAAA==.Maryjane:BAAALgAFFAIJAgAAAA==.Massoflice:BAACLgAFFH8PAAIjAAQJTA08gAAHAQAjAAQJTA08gAAHAQAuAAQKfzEAAiMACQkDGk04AB4CACMACQkDGk04AB4CAAAA.Matai:BAAALgAECgEJAQAAAA==.Maxblaide:BAABLgAECn8UAAISAAgJUwS1CwBxAAASAAgJUwS1CwBxAAAAAA==.Maxilla:BAAALgAECgQJBQABLgAFFAQJDQAiALASAA==.',
Me='Meauxie:BAAALgADCgEJAQAAAA==.Menguli:BAAALgAECgIJAgAAAA==.Meridians:BAABLgAECn8bAAIZAAYJxxbsPAB8AQAZAAYJxxbsPAB8AQAAAA==.',
Mh='Mhataharii:BAAALgAECgEJAgAAAA==.',
Mi='Mindhorn:BAACLgAFFH8MAAMVAAMJkxpnLwDVAAAVAAMJkxpnLwDVAAAaAAIJrRk/WgCYAAAuAAQKfycAAxUACAk0IXcQAG8CABUACAk0IXcQAG8CABoABAnTFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn89AAIIAAkJWBvwAABGAgAIAAkJWBvwAABGAgAAAA==.Moctar:BAAALgADCgQJBAAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIKAAgJJyAcMwBWAgAKAAgJJyAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAFFAIJAgANAAAAAA==.Musashi:BAABLgAFFH8SAAIEAAUJcx9HEQBlAQAEAAUJcx9HEQBlAQAAAA==.Mustardhunt:BAAALgAECgUJBgAAAA==.',
My='Myriad:BAABLgAECn8vAAIhAAkJmh9RBgCnAgAhAAkJmh9RBgCnAgAAAA==.',
Na='Nakze:BAABLgAECn82AAISAAkJAg/eGADTAQASAAkJAg/eGADTAQAAAA==.Namanari:BAAALgAECgEJAwAAAA==.Namfoodle:BAAALgADCgkJCQAAAA==.Nancydru:BAAALgAECgQJBAAAAA==.Nardwuar:BAAALgAECgYJDAABLgAFFAEJAwANAAAAAA==.Naris:BAAALgAECgMJAwAAAA==.Nastyfigs:BAABLgAECn8xAAIEAAkJURwPGwCDAgAEAAkJURwPGwCDAgAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.Neptune:BAACLgAFFH8IAAICAAQJNw0oMADZAAACAAQJNw0oMADZAAAuAAQKfxsAAgIACQlvER1QAOsBAAIACQlvER1QAOsBAAAA.',
Nh='Nhilas:BAAALgAECgQJDQAAAA==.',
Ni='Nightstryke:BAAALgAECgEJAQAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
No='Nokosi:BAAALgAFFAEJAQAAAA==.Nork:BAAALgAECgIJAgAAAA==.',
Ny='Nyxaries:BAABLgAECn8iAAIOAAkJ1RfLEwDWAQAOAAkJ1RfLEwDWAQAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
On='Onenytestand:BAAALgAECgkJCAAAAA==.',
Or='Ordis:BAAALgADCgQJBAAAAA==.Orrana:BAAALgAECgEJAQAAAA==.',
Pa='Pablo:BAABLgAECn8dAAIKAAkJjxpbAwBiAgAKAAkJjxpbAwBiAgAAAA==.Pannacea:BAAALgAECgYJDQABLgAECgkJPgAaAKkjAA==.Panzerblitz:BAABLgAECn8cAAIlAAgJhQmfNgDNAAAlAAgJhQmfNgDNAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIcAAcJNQoFIABSAQAcAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgADCggJDAAAAA==.',
Pe='Pedrote:BAAALgAECgEJAQAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Peppert:BAAALgAECggJCAAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Ph='Phane:BAAALgAECgYJCQAAAA==.Phson:BAAALgADCgkJDgAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIEAAYJOCApKgANAgAEAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pincher:BAAALgADCgQJBAAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piouspint:BAAALgAECgYJBgAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAABLgAECn8hAAIXAAcJUwknMwD6AAAXAAcJUwknMwD6AAAAAA==.Pretzelz:BAAALgAECgMJBQAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puertoricanj:BAAALgAECgMJAgAAAA==.Puffer:BAABLgAECn9EAAICAAkJTxQ0BQD6AQACAAkJTxQ0BQD6AQAAAA==.',
Ra='Rabone:BAAALgAECgUJBQAAAA==.Raelaris:BAAALgAFFAIJAwABLgAFFAUJEwACANgjAA==.Raevyn:BAAALgAECgYJBwAAAA==.Raeyla:BAAALgADCgEJAQAAAA==.Raito:BAABLgAECn8nAAIKAAgJag/wDABAAQAKAAgJag/wDABAAQAAAA==.Rakshasa:BAACLgAFFH8QAAIWAAQJeh0GOgBjAQAWAAQJeh0GOgBjAQAuAAQKfykAAxYACQnJIpAMAOkCABYACQnJIpAMAOkCACQAAQkAALIhAGsAAAAA.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJCgABLgAECgkJIwAEAGgcAA==.Rasetsungo:BAABLgAECn8iAAIBAAkJqhxYDAChAgABAAkJqhxYDAChAgAAAA==.Raura:BAABLgAECn8kAAIOAAgJWxS9IABNAQAOAAgJWxS9IABNAQAAAA==.Rayala:BAAALgAECgkJCQAAAA==.',
Re='Recalcitrent:BAAALgAECgUJBgAAAA==.Redblueblurr:BAABLgAECn8oAAIKAAkJlxDEUgDRAQAKAAkJlxDEUgDRAQAAAA==.Reintje:BAAALgAECgUJBQAAAA==.Remi:BAABLgAECn8kAAMBAAkJ8Rr0EQBQAgABAAkJ8Rr0EQBQAgAdAAEJ3RNsgAA8AAAAAA==.Rev:BAAALgAECgUJBwAAAA==.Reveillark:BAABLgAECn8UAAIeAAYJYhfWEgCbAQAeAAYJYhfWEgCbAQAAAA==.Revelaiden:BAAALgAECgEJAQABLgAECgkJPAAJAF0UAA==.',
Ro='Rolan:BAACLgAFFH8KAAIjAAQJDyXpLwCoAQAjAAQJDyXpLwCoAQAuAAQKfx4AAiMACQnYJPAWAL0CACMACQnYJPAWAL0CAAAA.Roogyrunes:BAAALgAECgcJCQABLgAECgkJIwAKAIUjAA==.Rosalian:BAABLgAECn81AAIFAAkJJhytEADLAgAFAAkJJhytEADLAgAAAA==.Rotiko:BAABLgAECn8kAAIaAAkJRQwlRQCZAQAaAAkJRQwlRQCZAQAAAA==.Roweene:BAABLgAECn84AAIoAAkJugjUCwBYAQAoAAkJugjUCwBYAQAAAA==.',
Ry='Ryez:BAAALgAECgEJAQAAAA==.Ryusei:BAAALgAECgQJBAAAAA==.',
['Rá']='Rágnar:BAABLgAECn8cAAQKAAkJWw9DYwCqAQAKAAkJhA5DYwCqAQAIAAgJZgi6KwC/AAALAAMJSQZEdABoAAAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgAECgUJBgAAAA==.',
Se='Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8nAAMTAAgJdh9kEgAuAgATAAgJdh9kEgAuAgAUAAEJEws+hQA8AAABLgAECgkJDgANAAAAAA==.Serenatee:BAABLgAECn8xAAIdAAkJnhDdIQC4AQAdAAkJnhDdIQC4AQAAAA==.',
Sh='Shadowkrak:BAAALgAECgEJAgAAAA==.Shakked:BAAALgAECgEJAQABLgAECgkJGwAKABYHAA==.Shamikaze:BAAALgAECgQJBAAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgAECgYJBgAAAA==.Shamwow:BAAALgAECgMJBgAAAA==.Shappens:BAAALgADCgkJHQABLgAECgkJJAAKAK0SAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAABLgAECn8WAAMEAAgJaxB9FQDuAAAEAAgJaxB9FQDuAAAmAAQJ/QI5SACaAAAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAACLgAFFH8HAAIGAAMJcA3saQC4AAAGAAMJcA3saQC4AAAuAAQKfx0AAgYACQlzEs89ANEBAAYACQlzEs89ANEBAAAA.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgcJJQAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgAECgEJAgAAAA==.Silentmaster:BAAALgAECgIJAgAAAA==.Simbà:BAAALgAECgYJEAAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8ZAAMGAAcJGSHEIQCGAgAGAAcJGSHEIQCGAgAJAAIJfhmcEgBRAAABLgAECgkJGQAmAP0iAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAACLgAFFH8QAAISAAQJCxN/DAAbAQASAAQJCxN/DAAbAQAuAAQKfxQAAxIABglfHiggAJUBABIABQlfHiggAJUBACcAAwlRGuMkAEEAAAAA.',
So='Soferfax:BAAALgADCgYJEgAAAA==.Sokroar:BAABLgAFFH8FAAIjAAIJaQwz5gCBAAAjAAIJaQwz5gCBAAABLgAFFAUJCAASAD4iAA==.Solphera:BAAALgADCgEJAQAAAA==.Sonknight:BAABLgAECn8sAAMKAAYJDwkUOgFyAAAKAAUJ8QIUOgFyAAALAAYJIwkHDQBwAAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAIVAAgJZB2mGQAUAgAVAAgJZB2mGQAUAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn9IAAImAAkJzQqvAwAhAQAmAAkJzQqvAwAhAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgQJDgAAAA==.Sto:BAABLgAECn8dAAIKAAkJph9+AgCqAgAKAAkJph9+AgCqAgAAAA==.Stratof:BAAALgAECgEJAQAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Subjugaiden:BAAALgAECgEJAQABLgAECgkJPAAJAF0UAA==.Sukerpunch:BAAALgADCgEJAQAAAA==.Supad:BAAALgADCgYJBwAAAA==.Superjpriest:BAAALgAFFAEJAQABLgAFFAMJAwANAAAAAA==.Suria:BAABLgAECn88AAIFAAkJhyGfAABOAwAFAAkJhyGfAABOAwAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAFFAIJAgAAAA==.Syloc:BAAALgAECgIJAgAAAA==.Syphax:BAAALgAECgQJBAAAAA==.',
['Sü']='Süperball:BAACLgAFFH8NAAIiAAQJsBLJEgDhAAAiAAQJsBLJEgDhAAAuAAQKfzkAAyIACQm2H1UBAIMCACIACQm2H1UBAIMCACEABAlACldDAGMAAAAA.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Taekwondovan:BAAALgAECgQJBwABLgAECgkJSQAOAOkjAA==.Tahrovin:BAAALgAECgIJAgAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgAECgEJAQAAAA==.Taternutzz:BAAALgAECgEJAgAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8yAAMBAAkJfSGoCADfAgABAAgJih+oCADfAgAbAAgJLx6KCwC2AgAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn9KAAMLAAkJuAicPQBPAQALAAkJuAicPQBPAQAKAAkJGgwmEwD6AAAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.Teenyshieva:BAAALgADCgEJAQAAAA==.Terrafying:BAAALgADCgMJAwAAAA==.',
Th='Theefjeef:BAAALgAECgkJBgABLgAECgkJGQAmAP0iAA==.Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgAECgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thicclock:BAAALgAECgEJAQAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thillas:BAAALgAECgEJAQAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Threign:BAEALgADCgkJCQABLgAECgkJIgAWAI4WAA==.Thundercups:BAABLgAECn84AAIYAAkJViHJAwDAAgAYAAkJViHJAwDAAgAAAA==.',
Ti='Tigerstarr:BAACLgAFFH8MAAIjAAMJ1BD9oQDSAAAjAAMJ1BD9oQDSAAAuAAQKfx4AAyMACQm7E9E7ABECACMACQm7E9E7ABECABAAAQlRBioZACoAAAAA.Timboslicé:BAAALgAECgcJDQAAAA==.Tinyshieva:BAABLgAECn8bAAMBAAYJTA7bPgD1AAABAAYJTA7bPgD1AAAdAAQJTwPzaAB6AAAAAA==.Tizuki:BAAALgAECgIJAwAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgkJDQAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn87AAIcAAkJSx1aAACQAgAcAAkJSx1aAACQAgAAAA==.Treenn:BAABLgAECn8tAAMaAAgJCxTtBADTAQAaAAgJCxTtBADTAQAVAAMJ/wT5hQBkAAAAAA==.Triplock:BAAALgAECgcJCwAAAA==.Trolcain:BAABLgAECn86AAIjAAkJTiXdAABNAwAjAAkJTiXdAABNAwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgkJOgAjAE4lAA==.',
Ty='Tyrix:BAABLgAECn8jAAIKAAkJhSP7CgAOAwAKAAkJhSP7CgAOAwAAAA==.Tyránt:BAACLgAFFH8TAAIEAAQJpRElSQAbAQAEAAQJpRElSQAbAQAuAAQKfzEAAwQACQlNI98MAOwCAAQACQlNI98MAOwCABEAAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAIUAAYJ2BmCQABCAQAUAAYJ2BmCQABCAQAAAA==.',
Va='Vaermaeth:BAAALgAECgMJAwABLgAECgkJCQANAAAAAA==.Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCwAAAA==.Valerossi:BAABLgAECn84AAImAAkJlx8VBQDXAgAmAAkJlx8VBQDXAgAAAA==.Valha:BAABLgAECn8mAAIJAAkJeRLMFwDFAQAJAAkJeRLMFwDFAQAAAA==.Valira:BAAALgADCggJCQABLgAECgkJIwAEAGgcAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgAECgIJAwAAAA==.Varleyna:BAAALgAECgQJBAABLgAFFAQJEgABAJEhAA==.Varteras:BAABLgAECn8yAAMkAAkJsxtRBgAZAgAkAAgJghtRBgAZAgAWAAgJnxKCVgCZAQAAAA==.',
Ve='Veleiri:BAABLgAECn81AAICAAkJLRJ/SQD/AQACAAkJLRJ/SQD/AQAAAA==.Velenal:BAAALgAECgQJEQAAAA==.Vellron:BAABLgAECn86AAIEAAkJURMZBQADAgAEAAkJURMZBQADAgAAAA==.',
Vo='Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgcJCQAAAA==.',
Wa='Wafflelegend:BAACLgAFFH8WAAMGAAYJMRcAOQBBAQAGAAUJPxkAOQBBAQAJAAIJHA1MIwCEAAAuAAQKfxYAAwkABgm1I48YAL4BAAkABgkKI48YAL4BAAYABAkfH95qAE8BAAAA.Wardkbriggle:BAACLgAFFH8OAAIOAAYJkx4PDQCsAQAOAAYJkx4PDQCsAQAuAAQKfyEAAg4ACQmoI7gDAAADAA4ACQmoI7gDAAADAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8YAAIUAAYJxRzGCwDXAQAUAAYJxRzGCwDXAQAuAAQKfyAAAhQACQkeIFILAH8CABQACQkeIFILAH8CAAAA.',
Wi='Wifi:BAAALgAECgIJBwAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMOAAYJeAWFNwCGAAAOAAQJGQaFNwCGAAAQAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn9AAAICAAkJ2xTaPAAnAgACAAkJ2xTaPAAnAgAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn84AAQSAAkJ4yQTAgBDAwASAAkJsyQTAgBDAwAnAAcJASMUBAB1AgAoAAYJth3ZCQCIAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.Xará:BAAALgAECgUJBQAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJCwABLgAECgkJOAASAOMkAA==.',
Xh='Xhared:BAABLgAECn9JAAIOAAkJ6SOPAgAjAwAOAAkJ6SOPAgAjAwAAAA==.',
Xy='Xylah:BAAALgADCgIJAgAAAA==.',
Ya='Yahtzee:BAAALgAECgMJBgAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIGAAgJBwMfvQCyAAAGAAgJBwMfvQCyAAAAAA==.',
Ye='Yesenia:BAAALgADCgkJCQAAAA==.',
Yk='Ykszord:BAAALgAECgEJAQAAAA==.',
Ze='Zephy:BAABLgAECn8UAAIiAAcJfxILBQBfAQAiAAcJfxILBQBfAQAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Zé']='Zéd:BAAALgAFFAEJAQABLgAFFAQJCgAEAJ8TAA==.',
['Åe']='Åeon:BAABLgAECn8bAAIEAAcJRhBkdgBTAQAEAAcJRhBkdgBTAQAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Ðr']='Ðráco:BAAALgADCgIJAgAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRhoAgAQAQApAAQJuRhoAgAQAQAuAAQKfzQAAykACQlVIMEAAP8CACkACQlVIMEAAP8CAAIABAmyF6r5AAcBAAAA.',
['ßu']='ßullzeye:BAABLgAFFH8HAAIEAAQJ/wfsHgAKAQAEAAQJ/wfsHgAKAQAAAA==.',
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
