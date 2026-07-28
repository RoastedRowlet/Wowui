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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Paladin-Retribution','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','DemonHunter-Havoc','Paladin-Holy','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Warlock-Demonology','Warrior-Arms','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','Priest-Discipline','Warlock-Destruction','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','Warlock-Affliction','Druid-Guardian','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aaronius:BAABLgAECn8uAAIBAAgJTwf1OAAXAQABAAgJTwf1OAAXAQAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8rAAMCAAkJyR21JgCAAgACAAkJwB21JgCAAgADAAUJNReKCwAeAQAAAA==.',
Ac='Acceptance:BAABLgAFFH8FAAIEAAIJwRhMOgCrAAAEAAIJwRhMOgCrAAAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8uAAIFAAkJFyJ1EQDFAgAFAAkJFyJ1EQDFAgAAAA==.Adora:BAABLgAECn8jAAIFAAkJaByrFACtAgAFAAkJaByrFACtAgAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aelise:BAAALgADCgQJBAABLgAECgkJPAAGAMMgAA==.',
Ag='Agaliarept:BAACLgAFFH8PAAIHAAQJkgu+KADWAAAHAAQJkgu+KADWAAAuAAQKfxYAAwgACAkYC5UaAMgAAAcABwnpBuCLAAsBAAgABwkPC5UaAMgAAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAABLgAECn8dAAIJAAkJChNdBwDgAAAJAAkJChNdBwDgAAAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn88AAMKAAkJXRRcFQDjAQAKAAkJXRRcFQDjAQAHAAgJ8AfOdAA4AQAAAA==.',
Ak='Akumajoe:BAAALgAECgMJAwAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aliyah:BAAALgAECgEJAQAAAA==.Aloria:BAAALgAFFAIJAgAAAA==.Alrook:BAABLgAECn8VAAMEAAgJ3xVAewB4AQAEAAgJ3xVAewB4AQALAAIJ4BHBdwBeAAAAAA==.Aluni:BAAALgAECgUJBQAAAA==.',
Am='Amethÿst:BAAALgAFFAIJAgAAAA==.Amoral:BAAALgAECgMJAwAAAA==.',
An='Angelneko:BAABLgAECn85AAIMAAkJaQ0OKQCKAQAMAAkJaQ0OKQCKAQAAAA==.Angst:BAAALgAECgEJAQAAAA==.Anitabj:BAAALgAFFAEJAQAAAA==.Annihilaiden:BAAALgAFFAEJAQABLgAECgkJPAAKAF0UAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwANAAAAAA==.Aralak:BAAALgAECgIJAgABLgAECgkJNgAOAPggAA==.Arcaynemoon:BAABLgAECn8XAAIMAAYJWAM9VgDLAAAMAAYJWAM9VgDLAAAAAA==.Arcon:BAAALgAECgEJAQAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.Artikfox:BAAALgADCgEJAQAAAA==.',
As='Ashléng:BAAALgAECgEJAQAAAA==.Asterior:BAACLgAFFH8RAAMPAAYJvxdiAQBxAQAPAAUJmxtiAQBxAQAMAAEJTghkSQBNAAAuAAQKfywAAg8ACQnzIKcDANQCAA8ACQnzIKcDANQCAAAA.',
At='Atthis:BAAALgAECgMJAwAAAA==.',
Au='Aug:BAAALgAECgIJAgABLgAECgkJHQAEANsdAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgAECgEJAQAAAA==.Auroraa:BAABLgAECn8zAAIMAAgJVwvePgATAQAMAAgJVwvePgATAQAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgUJBQANAAAAAA==.',
Av='Avalectra:BAAALgAECgYJCQAAAA==.',
Ay='Aylana:BAAALgAECgYJBgAAAA==.Aysu:BAAALgAECgUJBQAAAA==.',
Az='Azanost:BAAALgADCgQJBAABLgAECgkJJAAQAOAVAA==.Azmodeaz:BAABLgAECn9TAAIDAAkJQR2hAAAIAgADAAkJQR2hAAAIAgAAAA==.Aztrik:BAAALgAECgYJBgABLgAECgkJIwAEAIUjAA==.',
Ba='Bajapanti:BAABLgAECn9CAAIRAAkJGh7eAwCFAgARAAkJGh7eAwCFAgAAAA==.Ballyhøø:BAACLgAFFH8FAAIMAAUJYQiFFADLAAAMAAUJYQiFFADLAAAuAAQKfxoAAgwACQlGFIoxAFYBAAwACQlGFIoxAFYBAAAA.Banchory:BAAALgADCgQJBQAAAA==.Bandaron:BAAALgAECgQJCgAAAA==.Baxstab:BAABLgAECn82AAISAAkJ5xsTDQBVAgASAAkJ5xsTDQBVAgAAAA==.',
Bc='Bcam:BAAALgADCgYJBgAAAA==.',
Be='Beahon:BAAALgAECgUJEgAAAA==.Beelzebrad:BAAALgADCgkJCQAAAA==.Bellawitch:BAAALgAECgUJBQAAAA==.Betruger:BAAALgAECgUJAQAAAA==.',
Bg='Bgarlath:BAAALgAECgQJBAAAAA==.Bgeefiddy:BAAALgAECgMJAwAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJCgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackjak:BAAALgAECgEJAQAAAA==.Blackpatch:BAABLgAECn9DAAMTAAkJ6SK4AAD+AgATAAkJ6SK4AAD+AgAUAAgJ4gfgOAAYAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgYJDgAAAA==.Blargg:BAAALgADCgkJCQAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blightmaker:BAAALgAECgEJAQABLgAECgkJJAAOANUXAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAABLgAFFH8KAAIVAAQJOhaEHwAjAQAVAAQJOhaEHwAjAQAAAA==.Blooming:BAAALgAECggJDQABLgAECggJHAAWAA4aAA==.Bloomsbeam:BAABLgAECn8cAAIHAAgJDBaHZgBZAQAHAAgJDBaHZgBZAQAAAA==.Bloomslinger:BAAALgAECggJCAAAAA==.',
Bo='Bonusdk:BAAALgAECgYJBgABLgAECgkJMwAXAN4hAA==.Booneboy:BAABLgAECn8pAAMEAAkJ4yEPBQBIAgAEAAkJ4yEPBQBIAgAJAAQJ/Be3BQAWAQAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8lAAMJAAkJXxXUGQBKAQAJAAkJ7BLUGQBKAQAEAAcJ3A0XpgAuAQABLgAFFAgJHQAYAOoSAA==.',
Br='Brennor:BAABLgAECn8zAAIEAAkJ5w4WaQCdAQAEAAkJ5w4WaQCdAQAAAA==.Brewslunt:BAACLgAFFH8SAAIZAAcJmBZtFgDLAQAZAAcJmBZtFgDLAQAuAAQKfywAAxkACAmfIZgTAH8CABkACAmfIZgTAH8CABMAAwnEC1NpAIIAAAEuAAUUCAkiABoA5RwA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Bubblegonk:BAAALgAECggJCAAAAA==.Bubblydin:BAAALgAECgYJBgABLgAFFAMJCgAbAP0GAA==.Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAABLgAECn80AAIaAAkJLxV4JAA0AgAaAAkJLxV4JAA0AgAAAA==.Cairyan:BAABLgAECn9AAAIIAAkJ1B22AACBAgAIAAkJ1B22AACBAgAAAA==.Caiya:BAAALgADCgcJBwABLgAECgkJOAASAOMkAA==.Capn:BAAALgADCgcJCQAAAA==.Carvil:BAABLgAECn8zAAMcAAkJGxa9BgDyAQAcAAkJGxa9BgDyAQAWAAMJjweP7gCDAAAAAA==.Castalia:BAABLgAECn8dAAIdAAcJMRBaBwBFAQAdAAcJMRBaBwBFAQAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8YAAICAAYJKBcnOACJAQACAAYJKBcnOACJAQAuAAQKfysAAgIACQkXJCocAAYDAAIACQkXJCocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAYJGAACACgXAA==.Celithe:BAABLgAECn8gAAIEAAgJpxSKXwCyAQAEAAgJpxSKXwCyAQAAAA==.Cendrian:BAABLgAECn8WAAIMAAcJYQutQwD+AAAMAAcJYQutQwD+AAAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8tAAICAAkJfhwLLgBhAgACAAkJfhwLLgBhAgAAAA==.Charmshield:BAAALgAECgUJBQAAAA==.Cheezle:BAABLgAECn8ZAAMaAAkJJwjLDwATAQAaAAkJJwjLDwATAQAVAAgJEgEaowA2AAAAAA==.Chiafix:BAABLgAECn8cAAIUAAgJDwxSMgA3AQAUAAgJDwxSMgA3AQABLgAECgkJPgAaAF8jAA==.Chipp:BAABLgAECn8UAAIUAAcJ/CbtBwC1AgAUAAcJ/CbtBwC1AgAAAA==.Chleo:BAAALgAECgQJBwAAAA==.Choco:BAACLgAFFH8wAAIeAAkJTCHOAgDQAgAeAAkJTCHOAgDQAgAuAAQKfykAAx4ACQnvI+QFAOgCAB4ACQnvI+QFAOgCAB8AAQkVG3ohAEkAAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAkJMAAeAEwhAA==.Chocolight:BAAALgAFFAEJAQABLgAFFAkJMAAeAEwhAA==.Chudster:BAABLgAECn8gAAMfAAkJ/RVFCACuAQAfAAkJ/RVFCACuAQAgAAUJDQh1YQC2AAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAABLgAECn8oAAMhAAkJ9CAxCAB4AgAhAAkJ9CAxCAB4AgAXAAEJixFKeQAwAAAAAA==.Conqueror:BAAALgAECgYJEAABLgAFFAMJCQAGAE8RAA==.Cordeliagray:BAAALgAECgIJAgAAAA==.',
Cr='Crawdaddy:BAABLgAECn8WAAIFAAcJJhJkcQBdAQAFAAcJJhJkcQBdAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAABLgAFFH8HAAIiAAMJuw4FGgDKAAAiAAMJuw4FGgDKAAAAAA==.',
Cu='Cupper:BAAALgADCgcJCgABLgAECgkJJAAEAK0SAA==.Curmudge:BAABLgAECn9aAAIGAAkJZBn8AgAoAgAGAAkJZBn8AgAoAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgANAAAAAA==.Cybele:BAABLgAECn8dAAIBAAgJPAvZCwDGAAABAAgJPAvZCwDGAAAAAA==.',
Da='Dakunaito:BAABLgAECn8hAAMjAAkJxiRjFADNAgAjAAkJTCRjFADNAgAQAAEJLiJqLgBnAAAAAA==.Dakunaitø:BAAALgAECgIJAgAAAA==.Danay:BAAALgAECgEJAgAAAA==.Danksquaddon:BAAALgAECgEJAQAAAA==.Darachane:BAABLgAECn84AAMdAAgJIBDFDADTAAAdAAgJIBDFDADTAAABAAEJxwK3egAfAAAAAA==.Darovan:BAAALgAECgMJBQABLgAECgkJSQAOAOkjAA==.Darthnater:BAABLgAFFH8OAAIjAAQJYBZQJAA9AQAjAAQJYBZQJAA9AQAAAA==.Dauglow:BAAALgAECgcJCwAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathball:BAAALgAECgEJAQAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgAECgEJAQAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAFFAEJAgAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAABLgAECn8UAAIHAAYJkhkirwDJAAAHAAYJkhkirwDJAAAAAA==.Deltia:BAABLgAECn8xAAIVAAkJtBiMFgAxAgAVAAkJtBiMFgAxAgAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAQJEwAFAKURAA==.Demonagent:BAABLgAECn8ZAAQKAAkJWRp3GgCsAQAKAAkJNRp3GgCsAQAHAAQJOwv3wACrAAAIAAMJqRyjBQCrAAAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8WAAMgAAcJHhchIABgAQAgAAcJHhchIABgAQAfAAIJfQ4ZCQBYAAAuAAQKfzAAAx8ACQkOH9YJAEICAB8ACQlbHNYJAEICACAACAlrG8obAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8cAAIWAAgJDhp9OgDwAQAWAAgJDhp9OgDwAQAAAA==.Devonsemus:BAAALgAECgEJAQAAAA==.',
Di='Dimebagg:BAAALgAECgYJCgAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8sAAMBAAgJdx3+EgBEAgABAAgJdx3+EgBEAgAbAAMJDgnvRACRAAAAAA==.Dokspades:BAABLgAECn8UAAIaAAkJ/g8JMwDnAQAaAAkJ/g8JMwDnAQAAAA==.Dornoch:BAABLgAECn8oAAMLAAkJKiMQDQDAAgALAAkJKiMQDQDAAgAEAAEJ8AE1XAEjAAAAAA==.Dotzilla:BAABLgAECn8bAAQWAAkJnyQSCwA3AQAWAAYJBSQSCwA3AQAkAAIJ9iXlHADXAAAcAAMJ1yPSCgBqAAAAAA==.',
Dr='Dragnlvr:BAAALgADCgYJBgAAAA==.Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJCQAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8tAAIEAAkJ2g3tbgCQAQAEAAkJ2g3tbgCQAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgkJGQAKAFkaAA==.Drspades:BAAALgAECgEJAQAAAA==.',
Dx='Dx:BAABLgAFFH8HAAIHAAIJ+h2NcwCgAAAHAAIJ+h2NcwCgAAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8PAAIjAAMJwRktlgDhAAAjAAMJwRktlgDhAAAuAAQKfzQAAiMACQknISYXALwCACMACQknISYXALwCAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAgAAAA==.',
Ei='Einherja:BAAALgAECgQJBgAAAA==.Eisenhorn:BAAALgAECgUJBgAAAA==.',
El='Elessaria:BAABLgAECn8pAAIGAAkJ7QaeDQC4AAAGAAkJ7QaeDQC4AAAAAA==.Elfatheàrt:BAABLgAECn8dAAIEAAkJMBNHGwDlAAAEAAkJMBNHGwDlAAAAAA==.Elidrus:BAAALgADCgcJBwABLgAECgkJCQANAAAAAA==.Elira:BAAALgAECgEJBQAAAA==.',
Em='Emelgee:BAABLgAECn8cAAIlAAgJNAx6CgDGAAAlAAgJNAx6CgDGAAABLgAFFAMJCgAbAP0GAA==.Emofurry:BAAALgAFFAEJAQABLgAFFAkJMAAeAEwhAA==.',
En='End:BAAALgADCgEJAQAAAA==.',
Eo='Eon:BAAALgAECgEJAQAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgkJIwAFAGgcAA==.',
Es='Esika:BAAALgAFFAIJAwAAAA==.Estherras:BAABLgAECn8wAAIFAAkJXBqMJABQAgAFAAkJXBqMJABQAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgUJBQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Ez='Ezbeingreen:BAAALgAECgkJCQAAAA==.',
Fa='Fato:BAAALgAECgUJCQAAAA==.',
Fe='Feardotrun:BAABLgAECn8kAAMWAAkJhQ2/VgCYAQAWAAkJ2Qy/VgCYAQAcAAMJWQznJgB+AAAAAA==.Felicious:BAABLgAECn8WAAIHAAgJgxP4GACuAAAHAAgJgxP4GACuAAAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgAECgMJAgAAAA==.Finahlia:BAABLgAECn8pAAMGAAkJ7CHtBQBZAwAGAAkJ7CHtBQBZAwAlAAYJxSMfAgD9AQABLgABCgEJAQANAAAAAA==.Finally:BAABLgAECn8qAAIVAAkJsQsqEQCmAAAVAAkJsQsqEQCmAAAAAA==.Firebat:BAAALgADCgcJDQABLgAECgkJKQAEAOMhAA==.Firemage:BAACLgAFFH8HAAIWAAUJEhiVbADqAAAWAAUJEhiVbADqAAAuAAQKfzYAAhYACQkuI8AHABoDABYACQkuI8AHABoDAAAA.Fizzanelf:BAABLgAECn8qAAIGAAkJoyO4DwDVAgAGAAkJoyO4DwDVAgAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAACLgAFFH8PAAIEAAcJvQSpPgCdAAAEAAcJvQSpPgCdAAAuAAQKfzIAAgQACQkKGgBRAO4BAAQACQkKGgBRAO4BAAAA.Friendo:BAABLgAECn9JAAMPAAkJEBz+AABaAgAPAAkJEBz+AABaAgAMAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAFFAEJAwAAAA==.Frynied:BAAALgAECgUJDAABLgAECgkJJAABAPEaAA==.',
Fu='Furnost:BAABLgAECn8kAAIQAAkJ4BV/CQDtAQAQAAkJ4BV/CQDtAQAAAA==.Futnuraz:BAABLgAECn8mAAIXAAkJogmiCgCYAAAXAAkJogmiCgCYAAAAAA==.',
Fy='Fyrakkobama:BAAALgAECgkJBQABLgAECgkJGQAmAP0iAA==.Fyranne:BAAALgADCgkJCQAAAA==.Fyriat:BAABLgAECn81AAICAAkJ0wmxdgCMAQACAAkJ0wmxdgCMAQAAAA==.',
['Fì']='Fìjìt:BAAALgADCgIJAgAAAA==.',
Ga='Gabbee:BAAALgADCgkJCQAAAA==.Gazardiel:BAAALgAECgIJAgAAAA==.',
Ge='Getafix:BAAALgAECgcJCwABLgAECgkJPgAaAF8jAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Gimlore:BAAALgADCgEJAQAAAA==.Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8yAAITAAgJsxxaEABHAgATAAgJsxxaEABHAgAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goatmeal:BAAALgAECgkJBgAAAA==.Goldstorm:BAAALgADCgYJBgAAAA==.Goliath:BAABLgAECn8ZAAIaAAcJQR3xAwBCAgAaAAcJQR3xAwBCAgABLgAECgkJGwAEAMcbAA==.Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8lAAIcAAkJIh1kAgCWAgAcAAkJIh1kAgCWAgAAAA==.Greybark:BAAALgADCgcJEQAAAA==.Griffindor:BAABLgAECn8zAAIEAAkJYBjkMgA0AgAEAAkJYBjkMgA0AgAAAA==.Grimfelborn:BAACLgAFFH8iAAMkAAYJgBIlCQDnAAAWAAUJVg7jOgBgAQAkAAQJ4BElCQDnAAAuAAQKfzIAAxYACQn1HLsxAEUCABYACQlMG7sxAEUCACQAAwlQIaghALUAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAABLgAECn8zAAIaAAkJ8B5QBQADAgAaAAkJ8B5QBQADAgAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.Gryphindor:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgAECgQJBwAAAA==.',
Ha='Hahwe:BAAALgADCgEJAQABLgAECgkJCQANAAAAAA==.Hanicus:BAAALgAECgkJCQAAAA==.Hanoverfiste:BAABLgAECn8kAAIEAAkJrRJQDgBjAQAEAAkJrRJQDgBjAQAAAA==.Hapsburg:BAABLgAECn8tAAIZAAkJJhPoJAD7AQAZAAkJJhPoJAD7AQAAAA==.Haranbae:BAAALgAECgIJAgAAAA==.Havince:BAABLgAECn82AAIOAAkJ+CATBwCrAgAOAAkJ+CATBwCrAgAAAA==.Haylee:BAAALgAECgMJBAAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn84AAIEAAkJsB/lFgC5AgAEAAkJsB/lFgC5AgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huuken:BAAALgADCgMJAwAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Ic='Icyvinz:BAAALgADCgQJBAAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Ig='Ignisdaemoni:BAAALgAECgMJBAABLgABCgEJAQANAAAAAA==.',
Il='Illidai:BAAALgAECgYJEgAAAA==.Ilyndra:BAABLgAECn8zAAMXAAkJ3iF1BwCAAgAhAAkJeR2/BwCFAgAXAAgJsyF1BwCAAgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn81AAIiAAkJuxYdGwAVAgAiAAkJuxYdGwAVAgAAAA==.',
It='Ithea:BAABLgAECn8xAAICAAkJCCHSEwDjAgACAAkJCCHSEwDjAgAAAA==.',
Iz='Izzy:BAAALgAECgEJAQAAAA==.',
Ja='Jackkychan:BAAALgAECgEJAQAAAA==.Jackyll:BAAALgAECgIJBwAAAA==.Jaeson:BAEBLgAECn8iAAIWAAkJjhZEMQATAgAWAAkJjhZEMQATAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAgJIAALAGscAA==.',
Je='Jeef:BAAALgAECgQJAQABLgAECgkJGQAmAP0iAA==.Jeefrenzy:BAABLgAECn8ZAAMmAAkJ/SIMBQDYAgAmAAkJ/SIMBQDYAgAFAAIJkiGUAAFeAAAAAA==.Jeefwrld:BAAALgAECgUJBAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgcJEQAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8uAAQbAAkJsRlsBADNAQAbAAgJtRRsBADNAQABAAgJzxPpHwDEAQAdAAUJDRSMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8lAAInAAkJwxb6AADBAQAnAAkJwxb6AADBAQAAAA==.',
Ju='Jughunter:BAACLgAFFH8KAAMFAAQJnxNaVgD6AAAFAAQJvgVaVgD6AAAmAAMJtRg3HADvAAAuAAQKfxYAAxEACAmkFl0SADcBACYABgkFFSQrAEkBABEACAnMEF0SADcBAAAA.Jugz:BAAALgADCgEJAQABLgAFFAQJCgAFAJ8TAA==.',
Jw='Jwise:BAAALgAECgkJBgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kamus:BAAALgAECgMJAwAAAA==.Kanabat:BAAALgAECgcJDgAAAA==.Karaden:BAAALgAECgUJBQAAAA==.Karawyn:BAABLgAECn8kAAIFAAgJ5Q5BPQC5AQAFAAgJ5Q5BPQC5AQABLgAFFAEJAQANAAAAAA==.Karelix:BAAALgAECgMJBgAAAA==.Katrishy:BAACLgAFFH8iAAMdAAYJrxidDQCKAQAdAAYJrxidDQCKAQABAAIJQAJBNgA6AAAuAAQKfy8AAx0ACQk+IIcWADMCAB0ACQk+IIcWADMCAAEAAQlwBUSIACcAAAAA.Kaylierocks:BAAALgAECgEJAQAAAA==.Kayyfrost:BAAALgADCgIJAgAAAA==.Kazeral:BAAALgADCggJEQAAAA==.',
Ke='Keedrid:BAABLgAECn8WAAIjAAkJbh23NAAsAgAjAAkJbh23NAAsAgAAAA==.Keindis:BAAALgAECgcJEQABLgAECggJOAAdACAQAA==.Kelaeno:BAAALgAECgkJDAAAAA==.Kelemenohpea:BAABLgAECn8dAAIHAAgJDAcYlQD2AAAHAAgJDAcYlQD2AAABLgAECgkJDAANAAAAAA==.Kelox:BAAALgAECgEJAQAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8+AAIaAAkJXyMLAQBGAwAaAAkJXyMLAQBGAwAAAA==.Kruàlty:BAACLgAFFH8SAAIPAAUJlx6IAgBPAQAPAAUJlx6IAgBPAQAuAAQKfyQAAg8ACAmCHa0HAFwCAA8ACAmCHa0HAFwCAAAA.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwANAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgAECgIJAwABLgAECgkJHAADAKsNAA==.Legreecast:BAABLgAECn8cAAIDAAkJqw1+CAAUAQADAAkJqw1+CAAUAQAAAA==.Levlia:BAAALgADCgYJBgAAAA==.',
Li='Liasong:BAAALgAECgQJAwAAAA==.Lintball:BAAALgAECgMJAwAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ+GKACCAQABAAkJGQ+GKACCAQAdAAIJ2wepggA4AAAbAAEJrgFIiwAaAAAAAA==.',
Lo='Loamuhwea:BAAALgAECgQJBAAAAA==.Lodur:BAABLgAECn8uAAIaAAkJlRvEGgB0AgAaAAkJlRvEGgB0AgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAABLgAECn80AAIlAAkJJhOLFgCeAQAlAAkJJhOLFgCeAQAAAA==.Losat:BAABLgAECn9GAAIhAAkJ7A3AAwBlAQAhAAkJ7A3AAwBlAQAAAA==.',
Lu='Lucitano:BAAALgADCgYJCAAAAA==.Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8bAAIEAAkJxxvEKABfAgAEAAkJxxvEKABfAgAAAA==.Lunathir:BAAALgADCgMJAwABLgAFFAIJBAANAAAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwANAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAACLgAFFH8LAAIbAAMJhg59NgCxAAAbAAMJhg59NgCxAAAuAAQKfxUAAhsACQkjD8QhAMABABsACQkjD8QhAMABAAAA.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Machiato:BAAALgADCgEJAQAAAA==.Mackavelian:BAAALgAECgEJAQABLgAECgkJNwAZAGAWAA==.Mackkie:BAABLgAECn83AAMZAAkJYBbMHwAcAgAZAAgJgRfMHwAcAgATAAgJBg62LQBVAQAAAA==.Madonkadonk:BAABLgAECn82AAMfAAkJwhBTBwDKAQAfAAkJwhBTBwDKAQAgAAMJlAUZiwBGAAAAAA==.Maedai:BAABLgAECn83AAIZAAkJyhZMGQBOAgAZAAkJyhZMGQBOAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAgAAAA==.Magnaball:BAACLgAFFH8IAAILAAQJbBa2IgAKAQALAAQJbBa2IgAKAQAuAAQKfzsAAwsACQk3HiIUAG0CAAsACQk3HiIUAG0CAAQABQm7EKYLAaoAAAEuAAUUBAkNACIAsBIA.Magús:BAAALgAECgEJAgAAAA==.Maldive:BAABLgAECn8vAAIWAAkJxRMuRQDLAQAWAAkJxRMuRQDLAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Maliificent:BAAALgAECgEJAQAAAA==.Mallicia:BAACLgAFFH8VAAIBAAQJuCVrBwBIAQABAAQJuCVrBwBIAQAuAAQKf0MAAwEACQnBI5cDACADAAEACQnBI5cDACADABsACAlbGMAVACwCAAAA.Mallika:BAABLgAECn8mAAMaAAgJvxerKAAbAgAaAAgJvxerKAAbAgAVAAEJ3wkZqgAsAAABLgAFFAQJFQABALglAA==.Mallistra:BAAALgAECgIJAgABLgAFFAQJFQABALglAA==.Mallistraza:BAAALgAECgIJAwABLgAFFAQJFQABALglAA==.Mallwizard:BAACLgAFFH8JAAIWAAMJjAbkhwC2AAAWAAMJjAbkhwC2AAAuAAQKfy0AAhYACQnEFZQ4ACkCABYACQnEFZQ4ACkCAAAA.Mandible:BAAALgAECgEJAQAAAA==.Mandor:BAAALgADCgYJBgAAAA==.Mangopewpew:BAAALgAECgUJDwAAAA==.Mariothestab:BAAALgAECgUJBgABLgAFFAQJCwACAOAJAA==.Marks:BAAALgAECgEJAQAAAA==.Martris:BAAALgAECgMJBQAAAA==.Maryjane:BAAALgAFFAIJAgAAAA==.Massoflice:BAACLgAFFH8PAAIjAAQJTA08gAAHAQAjAAQJTA08gAAHAQAuAAQKfzgAAiMACQmOGwIFACMCACMACQmOGwIFACMCAAAA.Matai:BAAALgAECgEJAQAAAA==.Maxblaide:BAABLgAECn8WAAISAAkJwwTGDACLAAASAAkJwwTGDACLAAAAAA==.Maxilla:BAAALgAECgQJBQABLgAFFAQJDQAiALASAA==.',
Me='Meauxie:BAAALgADCgEJAQAAAA==.Menguli:BAAALgAECgIJAgAAAA==.Mercredi:BAAALgAECgUJBQAAAA==.Meridians:BAABLgAECn8bAAIZAAYJxxbsPAB8AQAZAAYJxxbsPAB8AQAAAA==.',
Mh='Mhataharii:BAAALgAECgEJAgAAAA==.',
Mi='Mindhorn:BAACLgAFFH8MAAMVAAMJkxpnLwDVAAAVAAMJkxpnLwDVAAAaAAIJrRk/WgCYAAAuAAQKfycAAxUACAk0IXcQAG8CABUACAk0IXcQAG8CABoABAnTFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn89AAIJAAkJuBmmAQAYAgAJAAkJuBmmAQAYAgAAAA==.Moctar:BAAALgADCgQJBAAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIEAAgJJyAcMwBWAgAEAAgJJyAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAFFAIJAgANAAAAAA==.Musashi:BAABLgAFFH8WAAIFAAUJvyCPEgCAAQAFAAUJvyCPEgCAAQAAAA==.Mustardhunt:BAAALgAECgYJCwAAAA==.',
My='Mybaby:BAAALgADCgEJAQAAAA==.Myriad:BAABLgAECn8vAAIhAAkJmh9RBgCnAgAhAAkJmh9RBgCnAgAAAA==.',
Na='Nakze:BAABLgAECn82AAISAAkJAg/eGADTAQASAAkJAg/eGADTAQAAAA==.Namanari:BAAALgAECgEJBAAAAA==.Namfoodle:BAAALgADCgkJCQAAAA==.Nancydru:BAAALgAECgQJBAAAAA==.Nardwuar:BAAALgAECgYJDAABLgAFFAEJAwANAAAAAA==.Naris:BAAALgAECgMJAwABLgAECgkJCQANAAAAAA==.Nastyfigs:BAABLgAECn8xAAIFAAkJURwPGwCDAgAFAAkJURwPGwCDAgAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.Neptune:BAACLgAFFH8JAAICAAQJNw3KOQDUAAACAAQJNw3KOQDUAAAuAAQKfxsAAgIACQlvER1QAOsBAAIACQlvER1QAOsBAAAA.',
Nh='Nhilas:BAAALgAECgQJDQAAAA==.',
Ni='Nightstryke:BAAALgAECgEJAQAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
No='Nokosi:BAAALgAFFAEJAQAAAA==.Nork:BAAALgAECgIJAgAAAA==.',
Ny='Nyxaries:BAABLgAECn8kAAIOAAkJ1RfLEwDWAQAOAAkJ1RfLEwDWAQAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
On='Onenytestand:BAAALgAECgkJCAAAAA==.',
Op='Opalynn:BAAALgAECgQJBQAAAA==.',
Or='Ordis:BAAALgADCgQJBAAAAA==.Orrana:BAAALgAECgEJAQAAAA==.',
Pa='Pablo:BAABLgAECn8gAAIEAAkJABs7BAByAgAEAAkJABs7BAByAgAAAA==.Pannacea:BAAALgAECgYJDQABLgAECgkJPgAaAF8jAA==.Panzerblitz:BAABLgAECn8cAAIlAAgJhQmfNgDNAAAlAAgJhQmfNgDNAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIcAAcJNQoFIABSAQAcAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgAECgEJAQAAAA==.',
Pe='Pedrote:BAAALgAECgEJAQAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Peppert:BAAALgAECggJCAAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Ph='Phane:BAAALgAECgYJCQAAAA==.Phson:BAAALgADCgkJDgAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIFAAYJOCApKgANAgAFAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pincher:BAAALgADCgQJBAAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piouspint:BAAALgAECgYJBgAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Pl='Plammett:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAABLgAECn8hAAIXAAcJUwknMwD6AAAXAAcJUwknMwD6AAAAAA==.Pretzelz:BAAALgAECgMJBQAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puertoricanj:BAAALgAECgMJAgAAAA==.Puffer:BAABLgAECn9EAAICAAkJ7RI4CADSAQACAAkJ7RI4CADSAQAAAA==.',
Ra='Rabone:BAAALgAECgUJBQAAAA==.Raelaris:BAAALgAFFAIJAwABLgAFFAUJEwACANgjAA==.Raevyn:BAAALgAECgcJCQAAAA==.Raeyla:BAAALgADCgEJAQAAAA==.Raito:BAABLgAECn8nAAIEAAgJCw3mFQARAQAEAAgJCw3mFQARAQAAAA==.Rakshasa:BAACLgAFFH8QAAIWAAQJeh0GOgBjAQAWAAQJeh0GOgBjAQAuAAQKfzMAAxYACQkoJJAMAOkCABYACQkoJJAMAOkCACQAAwl5HW8HAKwAAAAA.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJCgABLgAECgkJIwAFAGgcAA==.Rasetsungo:BAABLgAECn8iAAIBAAkJqhxYDAChAgABAAkJqhxYDAChAgAAAA==.Raura:BAABLgAECn8oAAIOAAkJBRTwBwDjAAAOAAkJBRTwBwDjAAAAAA==.Rayala:BAAALgAECgkJCQAAAA==.',
Re='Recalcitrent:BAAALgAECggJDwAAAA==.Redblueblurr:BAABLgAECn8oAAIEAAkJlxDEUgDRAQAEAAkJlxDEUgDRAQAAAA==.Reintje:BAAALgAECgUJBQAAAA==.Remi:BAABLgAECn8kAAMBAAkJ8Rr0EQBQAgABAAkJ8Rr0EQBQAgAdAAEJ3RNsgAA8AAAAAA==.Rev:BAAALgAECgUJBwAAAA==.Reveillark:BAABLgAECn8UAAIeAAYJYhfWEgCbAQAeAAYJYhfWEgCbAQAAAA==.Revelaiden:BAAALgAECgEJAQABLgAECgkJPAAKAF0UAA==.',
Ro='Rolan:BAACLgAFFH8KAAIjAAQJDyXpLwCoAQAjAAQJDyXpLwCoAQAuAAQKfx4AAiMACQnYJPAWAL0CACMACQnYJPAWAL0CAAAA.Roogyrunes:BAAALgAECgcJCQABLgAECgkJIwAEAIUjAA==.Rosalian:BAABLgAECn81AAIGAAkJJhytEADLAgAGAAkJJhytEADLAgAAAA==.Rotiko:BAABLgAECn8kAAIaAAkJRQwlRQCZAQAaAAkJRQwlRQCZAQAAAA==.Roweene:BAABLgAECn84AAIoAAkJugjUCwBYAQAoAAkJugjUCwBYAQAAAA==.',
Ry='Ryez:BAAALgAECgEJAQAAAA==.Ryusei:BAAALgAECgQJBAAAAA==.',
['Rá']='Rágnar:BAABLgAECn8cAAQEAAkJWw9DYwCqAQAEAAkJhA5DYwCqAQAJAAgJZgi6KwC/AAALAAMJSQZEdABoAAAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Sakuta:BAAALgAECgEJAQABLgAFFAMJDgAaAMslAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgAECgUJBgAAAA==.',
Se='Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8nAAMTAAgJdh9kEgAuAgATAAgJdh9kEgAuAgAUAAEJEws+hQA8AAABLgAECgkJDgANAAAAAA==.Serenatee:BAABLgAECn8xAAIdAAkJnhDdIQC4AQAdAAkJnhDdIQC4AQAAAA==.',
Sh='Shadowkrak:BAAALgAECgEJAgAAAA==.Shakked:BAAALgAECgEJAQABLgAECgkJGwAEABYHAA==.Shamikaze:BAAALgAECgQJBAAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgAECgYJBgAAAA==.Shamwow:BAABLgAECn8WAAIaAAUJQBLFDwAUAQAaAAUJQBLFDwAUAQAAAA==.Shappens:BAAALgADCgkJHQABLgAECgkJJAAEAK0SAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAABLgAECn8WAAMFAAgJaxDMGgDuAAAFAAgJaxDMGgDuAAAmAAQJ/QI5SACaAAAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAACLgAFFH8HAAIHAAMJcA3saQC4AAAHAAMJcA3saQC4AAAuAAQKfx0AAgcACQlzEs89ANEBAAcACQlzEs89ANEBAAAA.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgcJJQAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgAECgEJAwAAAA==.Silentmaster:BAAALgAECgIJAgAAAA==.Simbà:BAAALgAECgYJEAAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8ZAAMHAAcJGSHEIQCGAgAHAAcJGSHEIQCGAgAKAAIJfhmVFwBRAAABLgAECgkJGQAmAP0iAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAACLgAFFH8QAAISAAQJCxP+DwACAQASAAQJCxP+DwACAQAuAAQKfxQAAxIABglfHiggAJUBABIABQlfHiggAJUBACcAAwlRGuMkAEEAAAAA.',
So='Soferfax:BAAALgADCgYJEgAAAA==.Sokroar:BAABLgAFFH8FAAIjAAIJaQwz5gCBAAAjAAIJaQwz5gCBAAAAAA==.Solphera:BAAALgADCgYJBgAAAA==.Sonknight:BAABLgAECn8wAAMLAAYJIwmtDgCVAAALAAYJIwmtDgCVAAAEAAUJzQMUOgFyAAAAAA==.Sonrogue:BAAALgAECgIJAgAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAIVAAgJZB2mGQAUAgAVAAgJZB2mGQAUAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn9IAAImAAkJzQoyBQACAQAmAAkJzQoyBQACAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgQJDgAAAA==.Sto:BAABLgAECn8dAAIEAAkJ2x0GBAB9AgAEAAkJ2x0GBAB9AgAAAA==.Stratof:BAAALgAECgQJBQAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Subjugaiden:BAAALgAECgEJAQABLgAECgkJPAAKAF0UAA==.Sukerpunch:BAAALgADCgEJAQAAAA==.Supad:BAAALgADCgYJBwAAAA==.Superjpriest:BAAALgAFFAEJAQABLgAFFAMJAwANAAAAAA==.Suria:BAABLgAECn88AAIGAAkJwyDdAAA9AwAGAAkJwyDdAAA9AwAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swytchblade:BAAALgAECgMJBQAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAFFAIJAgAAAA==.Syloc:BAAALgAECgIJAgAAAA==.Syphax:BAAALgAECgQJBAAAAA==.',
['Sü']='Süperball:BAACLgAFFH8NAAIiAAQJsBLWFwDWAAAiAAQJsBLWFwDWAAAuAAQKfzkAAyIACQm2H+EBAHoCACIACQm2H+EBAHoCACEABAlACldDAGMAAAAA.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Taekwondovan:BAAALgAECgQJCAABLgAECgkJSQAOAOkjAA==.Tahrovin:BAAALgAECgIJAgAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgAECgEJAQAAAA==.Taternutzz:BAAALgAECgEJAgAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8yAAMBAAkJfSGoCADfAgABAAgJih+oCADfAgAbAAgJLx6KCwC2AgAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn9KAAMLAAkJzwWcPQBPAQALAAkJzwWcPQBPAQAEAAkJGgzEGQDwAAAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.Teenyshieva:BAAALgADCgEJAQAAAA==.Terrafying:BAAALgADCgMJAwAAAA==.',
Th='Theefjeef:BAAALgAECgkJBgABLgAECgkJGQAmAP0iAA==.Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgAECgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thicclock:BAAALgAECgEJAQAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thillas:BAAALgAECgEJAQAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Threign:BAEALgADCgkJCQABLgAECgkJIgAWAI4WAA==.Thundercups:BAABLgAECn84AAIYAAkJViHJAwDAAgAYAAkJViHJAwDAAgAAAA==.',
Ti='Tigerstarr:BAACLgAFFH8MAAIjAAMJ1BD9oQDSAAAjAAMJ1BD9oQDSAAAuAAQKfx4AAyMACQm7E9E7ABECACMACQm7E9E7ABECABAAAQlRBioZACoAAAAA.Timboslicé:BAAALgAECgcJDQAAAA==.Tinyshieva:BAABLgAECn8bAAMBAAYJTA7bPgD1AAABAAYJTA7bPgD1AAAdAAQJTwPzaAB6AAAAAA==.Tizuki:BAAALgAECgIJAwAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Tonystandard:BAAALgAECgcJBwAAAA==.Toriael:BAAALgAECgkJDQAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn87AAIcAAkJAByXAAB7AgAcAAkJAByXAAB7AgAAAA==.Treenn:BAABLgAECn8xAAMaAAkJoBTnBAATAgAaAAkJoBTnBAATAgAVAAMJ/wT5hQBkAAAAAA==.Triplock:BAAALgAECgcJCwAAAA==.Trolcain:BAABLgAECn86AAIjAAkJGyWUAQApAwAjAAkJGyWUAQApAwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgkJOgAjABslAA==.',
Ty='Tyrendra:BAAALgAECgEJAQAAAA==.Tyrix:BAABLgAECn8jAAIEAAkJhSP7CgAOAwAEAAkJhSP7CgAOAwAAAA==.Tyránt:BAACLgAFFH8TAAIFAAQJpRElSQAbAQAFAAQJpRElSQAbAQAuAAQKfzEAAwUACQlNI98MAOwCAAUACQlNI98MAOwCABEAAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAIUAAYJ2BmCQABCAQAUAAYJ2BmCQABCAQAAAA==.',
Va='Vaermaeth:BAAALgAECgMJBAABLgAECgkJCQANAAAAAA==.Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCwAAAA==.Valastia:BAAALgAECgEJAQABLgAECgkJCQANAAAAAA==.Valerossi:BAABLgAECn84AAImAAkJlx8VBQDXAgAmAAkJlx8VBQDXAgAAAA==.Valha:BAABLgAECn8mAAIKAAkJeRLMFwDFAQAKAAkJeRLMFwDFAQAAAA==.Valira:BAAALgADCggJCQABLgAECgkJIwAFAGgcAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgAECgIJAwAAAA==.Varleyna:BAAALgAECgQJBAABLgAFFAQJFQABALglAA==.Varteras:BAABLgAECn8yAAMkAAkJsxtRBgAZAgAkAAgJghtRBgAZAgAWAAgJnxKCVgCZAQAAAA==.',
Ve='Veleiri:BAABLgAECn81AAICAAkJLRJ/SQD/AQACAAkJLRJ/SQD/AQAAAA==.Velenal:BAAALgAECgQJEQAAAA==.Vellron:BAABLgAECn86AAIFAAkJGhG2CQC6AQAFAAkJGhG2CQC6AQAAAA==.',
Vi='Vitani:BAAALgAECgEJAQABLgAECgkJJAAOANUXAA==.',
Vo='Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgcJCQAAAA==.',
Wa='Wafflelegend:BAACLgAFFH8WAAMHAAYJMRcAOQBBAQAHAAUJPxkAOQBBAQAKAAIJHA1MIwCEAAAuAAQKfxYAAwoABgm1I48YAL4BAAoABgkKI48YAL4BAAcABAkfH95qAE8BAAAA.Wardkbriggle:BAACLgAFFH8QAAIOAAcJxx4PDQCsAQAOAAcJxx4PDQCsAQAuAAQKfyEAAg4ACQmoI7gDAAADAA4ACQmoI7gDAAADAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8YAAIUAAYJxRzGCwDXAQAUAAYJxRzGCwDXAQAuAAQKfyAAAhQACQkeIFILAH8CABQACQkeIFILAH8CAAAA.',
Wi='Wifi:BAAALgAECgIJBwAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMOAAYJeAWFNwCGAAAOAAQJGQaFNwCGAAAQAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn9AAAICAAkJ2xTaPAAnAgACAAkJ2xTaPAAnAgAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn84AAQSAAkJ4yQTAgBDAwASAAkJsyQTAgBDAwAnAAcJASMUBAB1AgAoAAYJth3ZCQCIAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJCwABLgAECgkJOAASAOMkAA==.',
Xh='Xhared:BAABLgAECn9JAAIOAAkJ6SOPAgAjAwAOAAkJ6SOPAgAjAwAAAA==.',
Xy='Xylah:BAAALgADCgIJAgAAAA==.',
Ya='Yahtzee:BAAALgAECgMJBgAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIHAAgJBwMfvQCyAAAHAAgJBwMfvQCyAAAAAA==.',
Ye='Yesenia:BAAALgAECgIJAgAAAA==.',
Yk='Ykszord:BAAALgAECgEJAQAAAA==.',
Za='Zarzak:BAAALgADCgYJBgAAAA==.',
Ze='Zephy:BAABLgAECn8UAAIiAAcJfxLaBgBcAQAiAAcJfxLaBgBcAQAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Zé']='Zéd:BAAALgAFFAEJAQABLgAFFAQJCgAFAJ8TAA==.',
['Åe']='Åeon:BAABLgAECn8bAAIFAAcJRhBkdgBTAQAFAAcJRhBkdgBTAQAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Ðr']='Ðráco:BAAALgADCgIJAgAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRhoAgAQAQApAAQJuRhoAgAQAQAuAAQKfzQAAykACQlVIMEAAP8CACkACQlVIMEAAP8CAAIABAmyF6r5AAcBAAAA.',
['ßu']='ßullzeye:BAABLgAFFH8IAAIFAAQJWw2wIgATAQAFAAQJWw2wIgATAQAAAA==.',
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
