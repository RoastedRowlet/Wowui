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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Paladin-Retribution','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','DemonHunter-Havoc','Paladin-Holy','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Warlock-Demonology','Warrior-Arms','Monk-Mistweaver','Shaman-Restoration','Priest-Discipline','Warlock-Destruction','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','Warlock-Affliction','Druid-Guardian','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-08-18',data={Aa='Aaronius:BAABLgAECn8uAAIBAAgJTwf1OAAXAQABAAgJTwf1OAAXAQAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8rAAMCAAkJyR21JgCAAgACAAkJwB21JgCAAgADAAUJNReKCwAeAQAAAA==.',
Ac='Acceptance:BAABLgAFFH8KAAIEAAYJUyDlCQDeAQAEAAYJUyDlCQDeAQAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8uAAIFAAkJFyJ1EQDFAgAFAAkJFyJ1EQDFAgAAAA==.Adora:BAABLgAECn8jAAIFAAkJaByrFACtAgAFAAkJaByrFACtAgAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aelise:BAAALgADCgQJBAABLgAECgkJPAAGAMMgAA==.',
Ag='Agaliarept:BAACLgAFFH8PAAIHAAQJkgv2KwDMAAAHAAQJkgv2KwDMAAAuAAQKfxYAAwgACAkYC5UaAMgAAAcABwnpBuCLAAsBAAgABwkPC5UaAMgAAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAABLgAECn8gAAIJAAkJORVXBgAfAQAJAAkJORVXBgAfAQAAAA==.Agathosia:BAAALgAECgMJAwAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn88AAMKAAkJXRRcFQDjAQAKAAkJXRRcFQDjAQAHAAgJ8AfOdAA4AQAAAA==.',
Ak='Akumajoe:BAAALgAECgMJAwAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aliyah:BAAALgAECgEJAQAAAA==.Aloria:BAAALgAFFAIJAgAAAA==.Alrook:BAABLgAECn8VAAMEAAgJ3xVAewB4AQAEAAgJ3xVAewB4AQALAAIJ4BHBdwBeAAAAAA==.Aluni:BAAALgAECgUJBQAAAA==.',
Am='Amethÿst:BAAALgAFFAIJAgAAAA==.Amoral:BAAALgAECgMJAwAAAA==.',
An='Andretta:BAAALgAECgEJAQAAAA==.Angelneko:BAABLgAECn85AAIMAAkJaQ0OKQCKAQAMAAkJaQ0OKQCKAQAAAA==.Angst:BAAALgAECgEJAQAAAA==.Anitabj:BAAALgAFFAEJAQAAAA==.Annihilaiden:BAAALgAFFAEJAQABLgAECgkJPAAKAF0UAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwANAAAAAA==.Aralak:BAAALgAECgIJAgABLgAECgkJNgAOAPggAA==.Arcaynemoon:BAABLgAECn8XAAIMAAYJWAM9VgDLAAAMAAYJWAM9VgDLAAAAAA==.Arcon:BAAALgAECgEJAQAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.Artikfox:BAAALgADCgEJAQAAAA==.',
As='Ashléng:BAAALgAECgEJAQAAAA==.Asmodeas:BAAALgADCgkJCQAAAA==.Asterior:BAACLgAFFH8RAAMPAAYJvxdiAQBxAQAPAAUJmxtiAQBxAQAMAAEJTghkSQBNAAAuAAQKfywAAg8ACQnzIKcDANQCAA8ACQnzIKcDANQCAAAA.',
At='Atthis:BAAALgAECgMJAwAAAA==.',
Au='Aug:BAAALgAECgIJAgABLgAECgkJHQAEANsdAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgAECgEJAQAAAA==.Auroraa:BAABLgAECn80AAIMAAkJlwviDwDFAAAMAAkJlwviDwDFAAAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgUJBQANAAAAAA==.',
Av='Avalectra:BAAALgAECgYJDwAAAA==.',
Ay='Aylana:BAAALgAECgYJBgAAAA==.Aysu:BAAALgAECgUJBQAAAA==.',
Az='Azanost:BAAALgADCgQJBAABLgAECgkJJAAQAOAVAA==.Azmodeaz:BAABLgAECn9TAAIDAAkJQR3dAAANAgADAAkJQR3dAAANAgAAAA==.Aztrik:BAAALgAECgYJBgABLgAECgkJIwAEAIUjAA==.',
Ba='Bajapanti:BAABLgAECn9CAAIRAAkJGh7eAwCFAgARAAkJGh7eAwCFAgAAAA==.Ballyhøø:BAACLgAFFH8HAAIMAAUJFgtYFQDbAAAMAAUJFgtYFQDbAAAuAAQKfxoAAgwACQlGFIoxAFYBAAwACQlGFIoxAFYBAAAA.Banchory:BAAALgADCgQJBQAAAA==.Bandaron:BAAALgAECgQJCgAAAA==.Baxstab:BAABLgAECn82AAISAAkJ5xsTDQBVAgASAAkJ5xsTDQBVAgAAAA==.',
Bc='Bcam:BAAALgADCgYJBgAAAA==.',
Be='Beahon:BAAALgAECgUJEgAAAA==.Bearovan:BAAALgADCgkJCQAAAA==.Beelzebrad:BAAALgADCgkJCQAAAA==.Bellawitch:BAAALgAECgUJBQAAAA==.Betruger:BAAALgAECgUJAQAAAA==.',
Bg='Bgarlath:BAAALgAECgQJBAAAAA==.Bgeefiddy:BAAALgAECgMJAwAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJCgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackjak:BAAALgAECgEJAQAAAA==.Blackpatch:BAABLgAECn9DAAMTAAkJ6SLhAADyAgATAAkJ6SLhAADyAgAUAAgJ4gfgOAAYAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgYJDgAAAA==.Blargg:BAAALgADCgkJCQAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blightmaker:BAAALgAECgEJAQABLgAECgkJJAAOANUXAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAACLgAFFH8KAAIVAAQJOhaEHwAjAQAVAAQJOhaEHwAjAQAuAAQKfxUAAhUACQliG7MTAE4CABUACQliG7MTAE4CAAAA.Blooming:BAAALgAECggJDQABLgAECggJHAAWAA4aAA==.Bloomsbeam:BAABLgAECn8cAAIHAAgJDBaHZgBZAQAHAAgJDBaHZgBZAQAAAA==.Bloomslinger:BAAALgAECggJDwAAAA==.',
Bo='Bonusdk:BAAALgAECgYJBgABLgAECgkJMwAXAN4hAA==.Booneboy:BAABLgAECn8pAAMEAAkJ4yEfBgBDAgAEAAkJ4yEfBgBDAgAJAAQJ/BfKBgATAQAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8lAAMJAAkJXxXUGQBKAQAJAAkJ7BLUGQBKAQAEAAcJ3A0XpgAuAQAAAA==.',
Br='Brennor:BAABLgAECn8zAAIEAAkJ5w4WaQCdAQAEAAkJ5w4WaQCdAQAAAA==.Brewslunt:BAACLgAFFH8SAAIYAAcJmBZtFgDLAQAYAAcJmBZtFgDLAQAuAAQKfywAAxgACAmfIZgTAH8CABgACAmfIZgTAH8CABMAAwnEC1NpAIIAAAEuAAUUCAkiABkA5RwA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Bubblegonk:BAAALgAECggJEgAAAA==.Bubblydin:BAAALgAECgYJBgABLgAFFAMJCgAaAP0GAA==.Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAABLgAECn80AAIZAAkJLxV4JAA0AgAZAAkJLxV4JAA0AgAAAA==.Cairyan:BAABLgAECn9AAAIIAAkJ1B3SAAB8AgAIAAkJ1B3SAAB8AgAAAA==.Caiya:BAAALgADCgcJBwABLgAECgkJOAASAOMkAA==.Capn:BAAALgADCgcJCQAAAA==.Carvil:BAABLgAECn8zAAMbAAkJGxa9BgDyAQAbAAkJGxa9BgDyAQAWAAMJjweP7gCDAAAAAA==.Castalia:BAABLgAECn8dAAIcAAcJMRAFCQA6AQAcAAcJMRAFCQA6AQAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8YAAICAAYJKBcnOACJAQACAAYJKBcnOACJAQAuAAQKfysAAgIACQkXJCocAAYDAAIACQkXJCocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAYJGAACACgXAA==.Celithe:BAABLgAECn8mAAIEAAkJVRa9EgBNAQAEAAkJVRa9EgBNAQAAAA==.Cendrian:BAABLgAECn8WAAIMAAcJYQutQwD+AAAMAAcJYQutQwD+AAAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8tAAICAAkJfhwLLgBhAgACAAkJfhwLLgBhAgAAAA==.Charmshield:BAAALgAECgUJBQAAAA==.Cheezle:BAABLgAECn8ZAAMZAAkJJwheEgATAQAZAAkJJwheEgATAQAVAAgJEgEaowA2AAAAAA==.Chiafix:BAABLgAECn8cAAIUAAgJDwxSMgA3AQAUAAgJDwxSMgA3AQABLgAECgkJPgAZAF8jAA==.Chipp:BAABLgAECn8XAAMUAAcJ/CbtBwC1AgAUAAcJ/CbtBwC1AgAYAAMJryCgEQAUAQAAAA==.Chleo:BAAALgAECgQJBwAAAA==.Choco:BAACLgAFFH80AAIdAAkJTCHOAgDQAgAdAAkJTCHOAgDQAgAuAAQKfyoAAx0ACQnvI+QFAOgCAB0ACQnvI+QFAOgCAB4AAgmVG3gHAFEAAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAkJNAAdAEwhAA==.Chocolight:BAAALgAFFAEJAQABLgAFFAkJNAAdAEwhAA==.Chudster:BAABLgAECn8gAAMeAAkJ/RVFCACuAQAeAAkJ/RVFCACuAQAfAAUJDQh1YQC2AAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAABLgAECn8oAAMgAAkJ9CAxCAB4AgAgAAkJ9CAxCAB4AgAXAAEJixFKeQAwAAAAAA==.Conqueror:BAAALgAECgYJEAABLgAFFAMJCQAGAE8RAA==.Cordeliagray:BAAALgAECgIJAgAAAA==.',
Cr='Crawdaddy:BAABLgAECn8WAAIFAAcJJhJkcQBdAQAFAAcJJhJkcQBdAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAABLgAFFH8IAAIhAAMJuw7EGwDJAAAhAAMJuw7EGwDJAAAAAA==.',
Cu='Cupper:BAAALgADCgcJCgABLgAECgkJJAAEAK0SAA==.Curmudge:BAABLgAECn9iAAIGAAkJ0xmVAgBlAgAGAAkJ0xmVAgBlAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgANAAAAAA==.Cybele:BAABLgAECn8dAAIBAAgJPAvPDQDAAAABAAgJPAvPDQDAAAAAAA==.',
Da='Dakunaito:BAABLgAECn8jAAMiAAkJxiRjFADNAgAiAAkJTCRjFADNAgAQAAIJqR5CCgCmAAAAAA==.Dakunaitø:BAAALgAECgIJAgAAAA==.Danay:BAAALgAECgEJAgAAAA==.Danksquaddon:BAAALgAECgEJAQAAAA==.Darachane:BAABLgAECn87AAMcAAgJIBDhCwABAQAcAAgJIBDhCwABAQABAAEJxwK3egAfAAAAAA==.Darovan:BAAALgAECgMJBQABLgAECgkJSQAOAOkjAA==.Darthnater:BAABLgAFFH8PAAIiAAQJ1RfmJQBAAQAiAAQJ1RfmJQBAAQAAAA==.Dauglow:BAAALgAECgcJCwAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathball:BAAALgAECgEJAwAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgAECgEJAQAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAFFAEJAgAAAA==.Definitely:BAAALgAECgMJAwAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAABLgAECn8VAAIHAAcJBhoHHgCfAAAHAAcJBhoHHgCfAAAAAA==.Deltia:BAABLgAECn8xAAIVAAkJtBiMFgAxAgAVAAkJtBiMFgAxAgAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAQJEwAFAKURAA==.Demonagent:BAABLgAECn8ZAAQKAAkJWRp3GgCsAQAKAAkJNRp3GgCsAQAHAAQJOwv3wACrAAAIAAMJqRxuBgCrAAAAAA==.Denominator:BAAALgAECgEJAQABLgAECgMJAwANAAAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8WAAMfAAcJHhchIABgAQAfAAcJHhchIABgAQAeAAIJfQ4ZCQBYAAAuAAQKfzAAAx4ACQkOH9YJAEICAB4ACQlbHNYJAEICAB8ACAlrG8obAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8cAAIWAAgJDhp9OgDwAQAWAAgJDhp9OgDwAQAAAA==.Devonsemus:BAAALgAECgEJAQAAAA==.',
Di='Dimebagg:BAAALgAECgYJCgAAAA==.Dionis:BAAALgAECgEJAQAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Dm='Dmnslyer:BAAALgAECgYJCwAAAA==.',
Do='Docspades:BAABLgAECn8sAAMBAAgJdx3+EgBEAgABAAgJdx3+EgBEAgAaAAMJDgnvRACRAAAAAA==.Dokspades:BAABLgAECn8UAAIZAAkJ/g8JMwDnAQAZAAkJ/g8JMwDnAQAAAA==.Dornoch:BAABLgAECn8uAAMLAAkJKiMQDQDAAgALAAkJKiMQDQDAAgAEAAMJFxLbLACkAAAAAA==.Dotzilla:BAABLgAECn8eAAQWAAkJ7STPBwCcAQAWAAYJBSTPBwCcAQAjAAIJ9iXlHADXAAAbAAMJDiX2CwBxAAAAAA==.',
Dr='Dragnlvr:BAAALgADCgYJBgAAAA==.Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJCQAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8tAAIEAAkJ2g3tbgCQAQAEAAkJ2g3tbgCQAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgkJGQAKAFkaAA==.Drspades:BAAALgAECgEJAQAAAA==.',
Dx='Dx:BAABLgAFFH8HAAIHAAIJ+h2NcwCgAAAHAAIJ+h2NcwCgAAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8PAAIiAAMJwRktlgDhAAAiAAMJwRktlgDhAAAuAAQKfzQAAiIACQknISYXALwCACIACQknISYXALwCAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAgAAAA==.',
Ei='Einherja:BAAALgAECgQJBgAAAA==.Eisenhorn:BAAALgAECgUJBgAAAA==.',
El='Elessaria:BAABLgAECn8pAAIGAAkJ7QZ5DwC2AAAGAAkJ7QZ5DwC2AAAAAA==.Elfatheàrt:BAABLgAECn8gAAIEAAkJEhQLFgAtAQAEAAkJEhQLFgAtAQAAAA==.Elfleena:BAAALgAECgMJAwAAAA==.Elidrus:BAAALgADCgcJBwABLgAECgkJCQANAAAAAA==.Elira:BAAALgAECgEJBQAAAA==.',
Em='Emelgee:BAABLgAECn8cAAIkAAgJNAzvCwDCAAAkAAgJNAzvCwDCAAABLgAFFAMJCgAaAP0GAA==.Emofurry:BAAALgAFFAEJAQABLgAFFAkJNAAdAEwhAA==.',
En='End:BAAALgADCgEJAQAAAA==.',
Eo='Eon:BAAALgAECgEJAQAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgkJIwAFAGgcAA==.',
Es='Esika:BAAALgAFFAIJAwAAAA==.Estherras:BAABLgAECn8wAAIFAAkJXBqMJABQAgAFAAkJXBqMJABQAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgUJBQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fa='Fato:BAAALgAECgUJCQAAAA==.',
Fe='Feardotrun:BAABLgAECn8kAAMWAAkJhQ2/VgCYAQAWAAkJ2Qy/VgCYAQAbAAMJWQznJgB+AAAAAA==.Felicious:BAABLgAECn8YAAIHAAkJChT3DgAbAQAHAAkJChT3DgAbAQAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgAECgMJAgAAAA==.Finahlia:BAABLgAECn8pAAMGAAkJ7CHtBQBZAwAGAAkJ7CHtBQBZAwAkAAYJxSOAAgD6AQABLgAECgcJCAANAAAAAA==.Finally:BAABLgAECn8tAAIVAAkJ4gvDDwDQAAAVAAkJ4gvDDwDQAAAAAA==.Firana:BAAALgADCgEJAQAAAA==.Firebat:BAAALgADCgcJDQABLgAECgkJKQAEAOMhAA==.Firemage:BAACLgAFFH8HAAIWAAUJEhiVbADqAAAWAAUJEhiVbADqAAAuAAQKfz4AAhYACQmwI8AHABoDABYACQmwI8AHABoDAAAA.Fizzanelf:BAABLgAECn8wAAMGAAkJqiO4DwDVAgAGAAkJqiO4DwDVAgAkAAMJjhJdDgCfAAAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAACLgAFFH8PAAIEAAcJvQSrYgDqAAAEAAcJvQSrYgDqAAAuAAQKfzIAAgQACQkKGgBRAO4BAAQACQkKGgBRAO4BAAAA.Friendo:BAABLgAECn9PAAMPAAkJNBwiAQBfAgAPAAkJNBwiAQBfAgAMAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJCAAAAA==.Frylock:BAAALgAFFAEJAwAAAA==.Frynied:BAAALgAECgUJDAABLgAECgkJJAABAPEaAA==.',
Fu='Furnost:BAABLgAECn8kAAIQAAkJ4BV/CQDtAQAQAAkJ4BV/CQDtAQAAAA==.Futnuraz:BAABLgAECn8sAAIXAAkJAA17BABKAQAXAAkJAA17BABKAQAAAA==.',
Fy='Fyrakkobama:BAAALgAECgkJBQABLgAECgkJGQAlAP0iAA==.Fyranne:BAAALgADCgkJCQAAAA==.Fyriat:BAABLgAECn81AAICAAkJ0wmxdgCMAQACAAkJ0wmxdgCMAQAAAA==.',
['Fì']='Fìjìt:BAAALgADCgIJAgAAAA==.',
Ga='Gabbee:BAAALgADCgkJCQAAAA==.Gazardiel:BAAALgAECgMJAwAAAA==.',
Ge='Getafix:BAAALgAECgcJCwABLgAECgkJPgAZAF8jAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Gimlore:BAAALgADCgEJAQAAAA==.Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8yAAITAAgJsxxaEABHAgATAAgJsxxaEABHAgAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goatmeal:BAAALgAECgkJBgAAAA==.Goldstorm:BAAALgADCgYJBgAAAA==.Goliath:BAABLgAECn8fAAIZAAcJqh45BABVAgAZAAcJqh45BABVAgABLgAECgkJGwAEAMcbAA==.Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8lAAIbAAkJIh1kAgCWAgAbAAkJIh1kAgCWAgAAAA==.Greybark:BAAALgADCgcJEQAAAA==.Griffindor:BAABLgAECn8zAAIEAAkJYBjkMgA0AgAEAAkJYBjkMgA0AgAAAA==.Grimfelborn:BAACLgAFFH8iAAMjAAYJgBIlCQDnAAAWAAUJVg7jOgBgAQAjAAQJ4BElCQDnAAAuAAQKfzIAAxYACQn1HLsxAEUCABYACQlMG7sxAEUCACMAAwlQIaghALUAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grokta:BAAALgADCgMJAwAAAA==.Grondosh:BAABLgAECn8zAAIZAAkJ8B44BgADAgAZAAkJ8B44BgADAgAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.Gryphindor:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgAECgUJCAAAAA==.',
Ha='Hahwe:BAAALgADCgEJAQABLgAECgkJCQANAAAAAA==.Hanicus:BAAALgAECgkJCQAAAA==.Hanoverfiste:BAABLgAECn8kAAIEAAkJrRIuEQBgAQAEAAkJrRIuEQBgAQAAAA==.Hapsburg:BAABLgAECn8tAAIYAAkJJhPoJAD7AQAYAAkJJhPoJAD7AQAAAA==.Haranbae:BAAALgAECgIJAgAAAA==.Havince:BAABLgAECn82AAIOAAkJ+CATBwCrAgAOAAkJ+CATBwCrAgAAAA==.Haylee:BAAALgAECgMJBAAAAA==.',
He='Healtome:BAAALgAECgIJAgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn84AAIEAAkJsB/lFgC5AgAEAAkJsB/lFgC5AgAAAA==.Holytalon:BAAALgADCgMJAwAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huuken:BAAALgADCgMJAwAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Ic='Icyvinz:BAAALgADCgQJBAAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Ig='Ignisdaemoni:BAAALgAECgMJBAABLgAECgcJCAANAAAAAA==.',
Il='Illidai:BAAALgAECgYJEgAAAA==.Ilyndra:BAABLgAECn8zAAMXAAkJ3iF1BwCAAgAgAAkJeR2/BwCFAgAXAAgJsyF1BwCAAgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn81AAIhAAkJuxYdGwAVAgAhAAkJuxYdGwAVAgAAAA==.',
It='Ithea:BAABLgAECn8xAAICAAkJCCHSEwDjAgACAAkJCCHSEwDjAgAAAA==.',
Iz='Izzy:BAAALgAECgEJAQAAAA==.',
Ja='Jackkychan:BAAALgAECgEJAQAAAA==.Jackyll:BAAALgAECgIJBwAAAA==.Jaeson:BAEBLgAECn8iAAIWAAkJjhZEMQATAgAWAAkJjhZEMQATAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAgJIAALAGscAA==.',
Je='Jeef:BAAALgAECgQJAQABLgAECgkJGQAlAP0iAA==.Jeefrenzy:BAABLgAECn8ZAAMlAAkJ/SIMBQDYAgAlAAkJ/SIMBQDYAgAFAAIJkiGUAAFeAAAAAA==.Jeefwrld:BAAALgAECgUJBAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Jh='Jhoíra:BAAALgAECgcJBwAAAA==.',
Ji='Jimothy:BAAALgAECgcJEQAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8uAAQaAAkJsRlPBQDMAQAaAAgJtRRPBQDMAQABAAgJzxPpHwDEAQAcAAUJDRSMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8lAAImAAkJwxYrAQC+AQAmAAkJwxYrAQC+AQAAAA==.',
Ju='Jughunter:BAACLgAFFH8KAAMFAAQJnxNaVgD6AAAFAAQJvgVaVgD6AAAlAAMJtRg3HADvAAAuAAQKfxYAAxEACAmkFl0SADcBACUABgkFFSQrAEkBABEACAnMEF0SADcBAAAA.Jugz:BAAALgADCgEJAQABLgAFFAQJCgAFAJ8TAA==.',
Jw='Jwise:BAAALgAECgkJBgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kamus:BAAALgAECgMJAwAAAA==.Kanabat:BAAALgAECgcJDgAAAA==.Karaden:BAAALgAECgUJBQAAAA==.Karawyn:BAABLgAECn8kAAIFAAgJ5Q5BPQC5AQAFAAgJ5Q5BPQC5AQABLgAFFAEJAQANAAAAAA==.Karelix:BAAALgAECgMJBgAAAA==.Katrishy:BAACLgAFFH8iAAMcAAYJrxidDQCKAQAcAAYJrxidDQCKAQABAAIJQAJBNgA6AAAuAAQKfy8AAxwACQk+IIcWADMCABwACQk+IIcWADMCAAEAAQlwBUSIACcAAAAA.Kaylierocks:BAAALgAECgEJAQAAAA==.Kayyfrost:BAAALgADCgIJAgAAAA==.Kazeral:BAAALgADCggJEQAAAA==.',
Ke='Keedrid:BAABLgAECn8WAAIiAAkJbh23NAAsAgAiAAkJbh23NAAsAgAAAA==.Keindis:BAAALgAECgcJEQABLgAECggJOwAcACAQAA==.Kelaeno:BAAALgAECgkJDAAAAA==.Kelemenohpea:BAABLgAECn8dAAIHAAgJDAcYlQD2AAAHAAgJDAcYlQD2AAABLgAECgkJDAANAAAAAA==.Kelox:BAAALgAECgEJAQAAAA==.',
Ki='Kirmit:BAAALgAECgkJCQAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8+AAIZAAkJXyNAAQBFAwAZAAkJXyNAAQBFAwAAAA==.Kruàlty:BAACLgAFFH8SAAIPAAUJlx75AgBIAQAPAAUJlx75AgBIAQAuAAQKfyQAAg8ACAmCHa0HAFwCAA8ACAmCHa0HAFwCAAAA.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwANAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgAECgUJBgABLgAECgkJHwADAPYPAA==.Legreecast:BAABLgAECn8fAAIDAAkJ9g/6AwAWAQADAAkJ9g/6AwAWAQAAAA==.Levlia:BAAALgADCgYJBgAAAA==.',
Li='Liare:BAAALgAECgEJAQABLgAFFAYJHgAcAJ0gAA==.Liasong:BAAALgAECgUJBwAAAA==.Lintball:BAAALgAECgMJBAAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ+GKACCAQABAAkJGQ+GKACCAQAcAAIJ2wepggA4AAAaAAEJrgFIiwAaAAAAAA==.',
Lo='Loamuhwea:BAAALgAECgQJBAAAAA==.Lodur:BAABLgAECn8uAAIZAAkJlRvEGgB0AgAZAAkJlRvEGgB0AgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAABLgAECn80AAIkAAkJJhOLFgCeAQAkAAkJJhOLFgCeAQAAAA==.Losat:BAABLgAECn9GAAIgAAkJ7A12BABmAQAgAAkJ7A12BABmAQAAAA==.',
Lu='Lucitano:BAAALgADCgYJCAAAAA==.Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8bAAIEAAkJxxvEKABfAgAEAAkJxxvEKABfAgAAAA==.Lunathir:BAAALgADCgMJAwABLgAFFAIJBAANAAAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwANAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAACLgAFFH8LAAIaAAMJhg59NgCxAAAaAAMJhg59NgCxAAAuAAQKfxUAAhoACQkjD8QhAMABABoACQkjD8QhAMABAAAA.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Machiato:BAAALgADCgEJAQAAAA==.Mackavelian:BAAALgAECgEJAQABLgAECgkJNwAYAGAWAA==.Mackkie:BAABLgAECn83AAMYAAkJYBbMHwAcAgAYAAgJgRfMHwAcAgATAAgJBg62LQBVAQAAAA==.Madonkadonk:BAABLgAECn82AAMeAAkJwhBTBwDKAQAeAAkJwhBTBwDKAQAfAAMJlAUZiwBGAAAAAA==.Maedai:BAABLgAECn83AAIYAAkJyhZMGQBOAgAYAAkJyhZMGQBOAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAgAAAA==.Magnaball:BAACLgAFFH8IAAILAAQJbBa2IgAKAQALAAQJbBa2IgAKAQAuAAQKfzsAAwsACQk3HiIUAG0CAAsACQk3HiIUAG0CAAQABQm7EKYLAaoAAAEuAAUUBAkPACEA+BYA.Magús:BAAALgAECgEJAgAAAA==.Maldive:BAABLgAECn8vAAIWAAkJxRMuRQDLAQAWAAkJxRMuRQDLAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Maliificent:BAAALgAECgEJAQAAAA==.Mallicia:BAACLgAFFH8VAAIBAAQJuCX8BwBCAQABAAQJuCX8BwBCAQAuAAQKf0gAAwEACQnHJZAAAGMDAAEACQnHJZAAAGMDABoACAlbGMAVACwCAAAA.Mallika:BAABLgAECn8mAAMZAAgJvxerKAAbAgAZAAgJvxerKAAbAgAVAAEJ3wkZqgAsAAABLgAFFAQJFQABALglAA==.Mallistra:BAAALgAECgIJAgABLgAFFAQJFQABALglAA==.Mallistraza:BAAALgAECgIJAwABLgAFFAQJFQABALglAA==.Mallwizard:BAACLgAFFH8JAAIWAAMJjAbkhwC2AAAWAAMJjAbkhwC2AAAuAAQKfy0AAhYACQnEFZQ4ACkCABYACQnEFZQ4ACkCAAAA.Mandible:BAAALgAECgEJAgAAAA==.Mandor:BAAALgADCgYJBgAAAA==.Mangopewpew:BAAALgAECgUJDwAAAA==.Mariothestab:BAAALgAECgUJBgABLgAFFAQJCwACAOAJAA==.Marks:BAAALgAECgEJAQAAAA==.Martris:BAAALgAECgMJBQAAAA==.Maryjane:BAAALgAFFAIJAgAAAA==.Massoflice:BAACLgAFFH8PAAIiAAQJTA08gAAHAQAiAAQJTA08gAAHAQAuAAQKfz8AAiIACQlFHeEEAFYCACIACQlFHeEEAFYCAAAA.Matai:BAAALgAECgEJAQAAAA==.Maxblaide:BAABLgAECn8WAAISAAkJwwSbDgCKAAASAAkJwwSbDgCKAAAAAA==.Maxilla:BAAALgAECgQJBQABLgAFFAQJDwAhAPgWAA==.',
Me='Meauxie:BAAALgADCgEJAQAAAA==.Menguli:BAAALgAECgIJAgAAAA==.Mercredi:BAAALgAECgUJBQAAAA==.Meridians:BAABLgAECn8bAAIYAAYJxxbsPAB8AQAYAAYJxxbsPAB8AQAAAA==.',
Mh='Mhataharii:BAAALgAECgEJAwAAAA==.',
Mi='Mindhorn:BAACLgAFFH8MAAMVAAMJkxpnLwDVAAAVAAMJkxpnLwDVAAAZAAIJrRk/WgCYAAAuAAQKfycAAxUACAk0IXcQAG8CABUACAk0IXcQAG8CABkABAnTFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn89AAIJAAkJuBkEAgATAgAJAAkJuBkEAgATAgAAAA==.Moctar:BAAALgADCgQJBAAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIEAAgJJyAcMwBWAgAEAAgJJyAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAFFAIJAgANAAAAAA==.Musashi:BAABLgAFFH8XAAIFAAYJ4yHUCwDvAQAFAAYJ4yHUCwDvAQABLgAFFAkJQgAFAGMmAA==.Mustardhunt:BAAALgAECgYJCwAAAA==.',
My='Mybaby:BAAALgADCgEJAQAAAA==.Myriad:BAABLgAECn8vAAIgAAkJmh9RBgCnAgAgAAkJmh9RBgCnAgAAAA==.',
Na='Nakze:BAABLgAECn82AAISAAkJAg/eGADTAQASAAkJAg/eGADTAQAAAA==.Namanari:BAAALgAECgEJBAAAAA==.Namfoodle:BAAALgADCgkJCQAAAA==.Nancydru:BAAALgAECgQJBAAAAA==.Nardwuar:BAAALgAECgYJDAABLgAFFAEJAwANAAAAAA==.Naris:BAAALgAECgMJAwABLgAECgkJCQANAAAAAA==.Nastyfigs:BAABLgAECn8xAAIFAAkJURwPGwCDAgAFAAkJURwPGwCDAgAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.Neptune:BAACLgAFFH8KAAICAAQJNw15PgDNAAACAAQJNw15PgDNAAAuAAQKfxsAAgIACQlvER1QAOsBAAIACQlvER1QAOsBAAAA.',
Nh='Nhilas:BAAALgAECgQJDQAAAA==.',
Ni='Nightstryke:BAAALgAECgEJAQAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
No='Nokosi:BAAALgAFFAEJAQAAAA==.Nork:BAAALgAECgIJAgAAAA==.',
Ny='Nyxaries:BAABLgAECn8kAAIOAAkJ1RfLEwDWAQAOAAkJ1RfLEwDWAQAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
On='Onenytestand:BAAALgAECgkJCAAAAA==.',
Op='Opalynn:BAAALgAECgQJBwAAAA==.',
Or='Ordis:BAAALgADCgQJBAAAAA==.Orrana:BAAALgAECgEJAQAAAA==.',
Pa='Pablo:BAABLgAECn8gAAIEAAkJABsbBQBvAgAEAAkJABsbBQBvAgAAAA==.Pannacea:BAAALgAECgYJDQABLgAECgkJPgAZAF8jAA==.Panzerblitz:BAABLgAECn8cAAIkAAgJhQmfNgDNAAAkAAgJhQmfNgDNAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIbAAcJNQoFIABSAQAbAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgAECgEJAgAAAA==.',
Pe='Pedrote:BAAALgAECgEJAQAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Peppert:BAAALgAECggJCAAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Ph='Phane:BAAALgAECgYJCQAAAA==.Phson:BAAALgADCgkJDgAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIFAAYJOCApKgANAgAFAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pincher:BAAALgADCgQJBAAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piouspint:BAAALgAECgYJBgAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Pl='Plammett:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAABLgAECn8hAAIXAAcJUwknMwD6AAAXAAcJUwknMwD6AAAAAA==.Pretzelz:BAAALgAECgMJBQAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puertoricanj:BAAALgAECgMJAgAAAA==.Puffer:BAABLgAECn9EAAICAAkJ7RLXCQDNAQACAAkJ7RLXCQDNAQAAAA==.',
Ra='Rabone:BAAALgAECgUJBgAAAA==.Raelaris:BAAALgAFFAIJAwABLgAFFAUJEwACANgjAA==.Raevyn:BAAALgAECgcJCQAAAA==.Raeyla:BAAALgADCgEJAQAAAA==.Raito:BAABLgAECn8nAAIEAAgJCw1pGQATAQAEAAgJCw1pGQATAQAAAA==.Rakshasa:BAACLgAFFH8QAAIWAAQJeh0GOgBjAQAWAAQJeh0GOgBjAQAuAAQKfzwABBsACQm5JFYAANUCABYACQkoJJAMAOkCABsABwklI1YAANUCACMAAwl5HbAIAKwAAAAA.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJCgABLgAECgkJIwAFAGgcAA==.Rasetsungo:BAABLgAECn8iAAIBAAkJqhxYDAChAgABAAkJqhxYDAChAgAAAA==.Raura:BAABLgAECn8rAAIOAAkJBRTYBgAxAQAOAAkJBRTYBgAxAQAAAA==.Rayala:BAAALgAECgkJCQAAAA==.',
Re='Recalcitrent:BAAALgAECggJDwAAAA==.Redblueblurr:BAABLgAECn8oAAIEAAkJlxDEUgDRAQAEAAkJlxDEUgDRAQAAAA==.Reintje:BAAALgAECgUJBQAAAA==.Remi:BAABLgAECn8kAAMBAAkJ8Rr0EQBQAgABAAkJ8Rr0EQBQAgAcAAEJ3RNsgAA8AAAAAA==.Rev:BAAALgAECgUJBwAAAA==.Reveillark:BAABLgAECn8UAAIdAAYJYhfWEgCbAQAdAAYJYhfWEgCbAQAAAA==.Revelaiden:BAAALgAFFAEJAQABLgAECgkJPAAKAF0UAA==.',
Ro='Rolan:BAACLgAFFH8KAAIiAAQJDyXpLwCoAQAiAAQJDyXpLwCoAQAuAAQKfx4AAiIACQnYJPAWAL0CACIACQnYJPAWAL0CAAAA.Roogyrunes:BAAALgAECgcJCQABLgAECgkJIwAEAIUjAA==.Rosalian:BAABLgAECn81AAIGAAkJJhytEADLAgAGAAkJJhytEADLAgAAAA==.Rotiko:BAABLgAECn8kAAIZAAkJRQwlRQCZAQAZAAkJRQwlRQCZAQAAAA==.Roweene:BAABLgAECn84AAInAAkJugjUCwBYAQAnAAkJugjUCwBYAQAAAA==.',
Ry='Ryez:BAAALgAECgEJAQAAAA==.Ryusei:BAAALgAECgQJBAAAAA==.',
['Rá']='Rágnar:BAABLgAECn8cAAQEAAkJWw9DYwCqAQAEAAkJhA5DYwCqAQAJAAgJZgi6KwC/AAALAAMJSQZEdABoAAAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Sakuta:BAAALgAECgQJBQABLgAFFAMJDgAZAMslAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgAECgUJBgAAAA==.',
Se='Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8nAAMTAAgJdh9kEgAuAgATAAgJdh9kEgAuAgAUAAEJEws+hQA8AAABLgAECgkJDgANAAAAAA==.Serenatee:BAABLgAECn8xAAIcAAkJnhDdIQC4AQAcAAkJnhDdIQC4AQAAAA==.',
Sh='Shadowkrak:BAAALgAECgEJAgAAAA==.Shakked:BAAALgAECgQJBQABLgAECgkJGwAEABYHAA==.Shamikaze:BAAALgAECgQJBAAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgAECgYJBgAAAA==.Shamwow:BAABLgAECn8cAAIZAAUJrRO+EAAnAQAZAAUJrRO+EAAnAQAAAA==.Shappens:BAAALgADCgkJHQABLgAECgkJJAAEAK0SAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAABLgAECn8WAAMFAAgJaxDlHgDsAAAFAAgJaxDlHgDsAAAlAAQJ/QI5SACaAAAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAACLgAFFH8HAAIHAAMJcA3saQC4AAAHAAMJcA3saQC4AAAuAAQKfx0AAgcACQlzEs89ANEBAAcACQlzEs89ANEBAAAA.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgcJJQAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgAECgEJAwAAAA==.Silentmaster:BAAALgAECgIJAgAAAA==.Simbà:BAAALgAECgYJEAAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8ZAAMHAAcJGSHEIQCGAgAHAAcJGSHEIQCGAgAKAAIJfhlUGwBQAAABLgAECgkJGQAlAP0iAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAACLgAFFH8QAAISAAQJCxOSEQD7AAASAAQJCxOSEQD7AAAuAAQKfxQAAxIABglfHiggAJUBABIABQlfHiggAJUBACYAAwlRGuMkAEEAAAAA.',
So='Soferfax:BAAALgADCgYJEgAAAA==.Sokroar:BAABLgAFFH8FAAIiAAIJaQwz5gCBAAAiAAIJaQwz5gCBAAABLgAFFAYJCAASAD4iAA==.Solphera:BAAALgADCgYJBwAAAA==.Sonknight:BAABLgAECn8xAAMLAAYJIwkfEgCRAAALAAYJIwkfEgCRAAAEAAUJzQMUOgFyAAAAAA==.Sonrogue:BAAALgAECgYJCAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAIVAAgJZB2mGQAUAgAVAAgJZB2mGQAUAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn9IAAIlAAkJzQoyBgD2AAAlAAkJzQoyBgD2AAAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgQJDgAAAA==.Sto:BAABLgAECn8dAAIEAAkJ2x3dBAB5AgAEAAkJ2x3dBAB5AgAAAA==.Stratof:BAAALgAECgQJBQAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Subjugaiden:BAAALgAECgEJAQABLgAECgkJPAAKAF0UAA==.Sukerpunch:BAAALgADCgEJAQAAAA==.Supad:BAAALgADCgYJBwAAAA==.Superjpriest:BAAALgAFFAEJAQABLgAFFAMJAwANAAAAAA==.Suria:BAABLgAECn88AAIGAAkJwyABAQA5AwAGAAkJwyABAQA5AwAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swytchblade:BAAALgAECgUJCAAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAFFAIJAgAAAA==.Syloc:BAAALgAECgIJAgAAAA==.Syphax:BAAALgAECgQJBAAAAA==.',
['Sü']='Süperball:BAACLgAFFH8PAAIhAAQJ+BbjEwD/AAAhAAQJ+BbjEwD/AAAuAAQKfzkAAyEACQm2HzkCAHYCACEACQm2HzkCAHYCACAABAlACldDAGMAAAAA.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Taekwondovan:BAAALgAECgQJCAABLgAECgkJSQAOAOkjAA==.Tahrovin:BAAALgAECgIJAgAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Talayska:BAAALgAECgMJAwABLgAECgkJKwAOAAUUAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgAECgEJAQAAAA==.Taternutzz:BAAALgAECgEJAgAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8yAAMBAAkJfSGoCADfAgABAAgJih+oCADfAgAaAAgJLx6KCwC2AgAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn9KAAMLAAkJzwWcPQBPAQALAAkJzwWcPQBPAQAEAAkJGgxGHgDvAAAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.Teenyshieva:BAAALgADCgEJAQAAAA==.Terrafying:BAAALgADCgMJAwAAAA==.',
Th='Theefjeef:BAAALgAECgkJBgABLgAECgkJGQAlAP0iAA==.Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgAECgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thicclock:BAAALgAECgEJAQAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thickyboi:BAAALgAECgEJAQAAAA==.Thillas:BAAALgAECgEJAQAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Threign:BAEALgADCgkJCQABLgAECgkJIgAWAI4WAA==.Thundercups:BAABLgAECn84AAIoAAkJViHJAwDAAgAoAAkJViHJAwDAAgAAAA==.',
Ti='Tigerstarr:BAACLgAFFH8MAAIiAAMJ1BD9oQDSAAAiAAMJ1BD9oQDSAAAuAAQKfx4AAyIACQm7E9E7ABECACIACQm7E9E7ABECABAAAQlRBioZACoAAAAA.Timboslicé:BAAALgAECgcJDQAAAA==.Tinyshieva:BAABLgAECn8cAAMBAAYJ3Q/bPgD1AAABAAYJ3Q/bPgD1AAAcAAQJTwPzaAB6AAAAAA==.Tizuki:BAAALgAECgIJAwAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Tonystandard:BAAALgAECgcJDgAAAA==.Toriael:BAAALgAECgkJDQAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn87AAIbAAkJABy7AAB4AgAbAAkJABy7AAB4AgAAAA==.Treenn:BAABLgAECn8xAAMZAAkJoBTABQAUAgAZAAkJoBTABQAUAgAVAAMJ/wT5hQBkAAAAAA==.Triplock:BAAALgAECgcJCwAAAA==.Trolcain:BAABLgAECn86AAIiAAkJGyXqAQAiAwAiAAkJGyXqAQAiAwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgkJOgAiABslAA==.',
Tw='Twistedlight:BAAALgAECgUJCgAAAA==.',
Ty='Tyrendra:BAAALgAECgEJAQAAAA==.Tyrix:BAABLgAECn8jAAIEAAkJhSP7CgAOAwAEAAkJhSP7CgAOAwAAAA==.Tyránt:BAACLgAFFH8TAAIFAAQJpRElSQAbAQAFAAQJpRElSQAbAQAuAAQKfzEAAwUACQlNI98MAOwCAAUACQlNI98MAOwCABEAAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAIUAAYJ2BmCQABCAQAUAAYJ2BmCQABCAQAAAA==.',
Va='Vaermaeth:BAAALgAECgMJBAABLgAECgkJCQANAAAAAA==.Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCwAAAA==.Valastia:BAAALgAECgEJAQABLgAECgkJCQANAAAAAA==.Valerossi:BAABLgAECn84AAIlAAkJlx8VBQDXAgAlAAkJlx8VBQDXAgAAAA==.Valha:BAABLgAECn8mAAIKAAkJeRLMFwDFAQAKAAkJeRLMFwDFAQAAAA==.Valira:BAAALgADCggJCQABLgAECgkJIwAFAGgcAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgAECgIJAwAAAA==.Varleyna:BAAALgAECgQJBAABLgAFFAQJFQABALglAA==.Varteras:BAABLgAECn8yAAMjAAkJsxtRBgAZAgAjAAgJghtRBgAZAgAWAAgJnxKCVgCZAQAAAA==.',
Ve='Veleiri:BAABLgAECn81AAICAAkJLRJ/SQD/AQACAAkJLRJ/SQD/AQAAAA==.Velenal:BAAALgAECgQJEQAAAA==.Vellron:BAABLgAECn86AAIFAAkJGhGOCwC6AQAFAAkJGhGOCwC6AQAAAA==.',
Vi='Vitani:BAAALgAECgEJAQABLgAECgkJJAAOANUXAA==.',
Vo='Voidedgooch:BAAALgAECgEJAQAAAA==.Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgcJCQAAAA==.',
Wa='Wafflelegend:BAACLgAFFH8WAAMHAAYJMRcAOQBBAQAHAAUJPxkAOQBBAQAKAAIJHA1MIwCEAAAuAAQKfxYAAwoABgm1I48YAL4BAAoABgkKI48YAL4BAAcABAkfH95qAE8BAAAA.Wardkbriggle:BAACLgAFFH8QAAIOAAcJxx4PDQCsAQAOAAcJxx4PDQCsAQAuAAQKfyEAAg4ACQmoI7gDAAADAA4ACQmoI7gDAAADAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8ZAAIUAAYJxRzGCwDXAQAUAAYJxRzGCwDXAQAuAAQKfyAAAhQACQkeIFILAH8CABQACQkeIFILAH8CAAAA.',
Wi='Wifi:BAAALgAECgIJBwAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMOAAYJeAWFNwCGAAAOAAQJGQaFNwCGAAAQAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn9AAAICAAkJ2xTaPAAnAgACAAkJ2xTaPAAnAgAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn84AAQSAAkJ4yQTAgBDAwASAAkJsyQTAgBDAwAmAAcJASMUBAB1AgAnAAYJth3ZCQCIAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.Xaoc:BAAALgAECgcJCAAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJCwABLgAECgkJOAASAOMkAA==.',
Xh='Xhared:BAABLgAECn9JAAIOAAkJ6SOPAgAjAwAOAAkJ6SOPAgAjAwAAAA==.',
Xy='Xylah:BAAALgADCgIJAgAAAA==.',
Ya='Yahtzee:BAAALgAECgMJBgAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIHAAgJBwMfvQCyAAAHAAgJBwMfvQCyAAAAAA==.',
Ye='Yesenia:BAAALgAECgMJAwAAAA==.',
Yk='Ykszord:BAAALgAECgEJAQAAAA==.',
Za='Zarzak:BAAALgAECgQJAQAAAA==.',
Ze='Zephy:BAABLgAECn8UAAIhAAcJfxIfCABYAQAhAAcJfxIfCABYAQAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Zé']='Zéd:BAAALgAFFAEJAQABLgAFFAQJCgAFAJ8TAA==.',
['Åe']='Åeon:BAABLgAECn8bAAIFAAcJRhBkdgBTAQAFAAcJRhBkdgBTAQAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Ðr']='Ðráco:BAAALgADCgIJAgAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRhoAgAQAQApAAQJuRhoAgAQAQAuAAQKfzQAAykACQlVIMEAAP8CACkACQlVIMEAAP8CAAIABAmyF6r5AAcBAAAA.',
['ßu']='ßullzeye:BAABLgAFFH8IAAIFAAQJWw3WJQAPAQAFAAQJWw3WJQAPAQAAAA==.',
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
