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

local lookup = {'Shaman-Restoration','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Monk-Brewmaster','Paladin-Retribution','Paladin-Protection','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Holy','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Hunter-Marksmanship','DemonHunter-Devourer','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Blood','Evoker-Devastation','Druid-Guardian','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Mage-Frost','Warrior-Protection','Warrior-Fury','Warrior-Arms','Evoker-Augmentation','Evoker-Preservation','Rogue-Subtlety','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aarmorr:BAABLgAECn8+AAIBAAkJhxakHwA4AgABAAkJhxakHwA4AgAAAA==.Aatus:BAAALgADCgUJBgAAAA==.',
Ab='Absoul:BAAALgAECgQJBAAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgQJBgAAAA==.',
Ad='Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aedelas:BAAALgAECgIJAwAAAA==.Aeloriá:BAABLgAECn87AAMCAAkJ0x2tCQAPAwACAAkJ0x2tCQAPAwADAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECgcJDAAAAA==.',
Ag='Agrosa:BAAALgAECgYJBgAAAA==.',
Ai='Aimeeiove:BAAALgAECgMJAwAAAA==.Airad:BAAALgADCgUJBgAAAA==.',
Al='Alchon:BAABLgAECn8kAAIEAAkJ6xoXJwAtAgAEAAkJ6xoXJwAtAgAAAA==.Aldera:BAABLgAECn8mAAIBAAkJ6gSvXAAoAQABAAkJ6gSvXAAoAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8jAAMFAAkJwRxQQADvAQAFAAkJwRxQQADvAQAGAAEJyhBgFgA3AAAAAA==.Alista:BAAALgAECgIJAgAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn8+AAMCAAcJJheoLwDRAQACAAcJJheoLwDRAQAHAAIJmQqzbQBUAAAAAA==.Alorris:BAAALgAECgQJBgABLgAECgkJGQAIAFggAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECggJDgAAAA==.Alyra:BAAALgAECgYJBgAAAA==.',
Am='Amata:BAAALgAECgUJCAAAAA==.Amelianne:BAAALgADCgMJAwAAAA==.Amiria:BAAALgAECgYJBgAAAA==.Ammastary:BAAALgAECgQJBgAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgkJLwAJAA8bAA==.Andragos:BAAALgAECgQJBgAAAA==.Andrea:BAABLgAECn89AAIDAAkJfRqxBQB2AgADAAkJfRqxBQB2AgAAAA==.Anthria:BAAALgAECgcJEAAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arcapeligo:BAAALgAECgEJAgAAAA==.Archonsfury:BAAALgAECggJDwAAAA==.Arilyn:BAAALgAECgIJAgAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgAAAA==.Asheye:BAAALgAECgcJBwABLgAECgkJKQAFANUeAA==.Ashuranadi:BAAALgADCgcJBwAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJEQAAAA==.Asura:BAAALgAECgEJAQAAAA==.Asyllaa:BAABLgAECn8eAAMKAAkJFx/0JQBTAgAKAAcJOyP0JQBTAgALAAYJ9hKvHAAXAQAAAA==.',
At='Atnawuerus:BAAALgAECgEJAQAAAA==.Atonement:BAAALgAECgIJBAABLgAECgkJKwAMAD0gAA==.',
Au='Aumaril:BAAALgAECggJEwAAAA==.Auralynn:BAABLgAECn8dAAIKAAkJpAi9hgBHAQAKAAkJpAi9hgBHAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averus:BAABLgAECn8+AAIHAAkJzQ/fHQC/AQAHAAkJzQ/fHQC/AQAAAA==.',
Az='Azariel:BAABLgAECn81AAIKAAkJixPvRQASAgAKAAkJixPvRQASAgAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn84AAMLAAkJPR0KBQCOAgALAAkJ+xwKBQCOAgAKAAEJKx1HPAFUAAAAAA==.',
Ba='Baane:BAAALgAECgQJBAABLgAECgUJCwANAAAAAA==.Babnik:BAEALgAECgcJEwAAAA==.Bagel:BAACLgAFFH8VAAIOAAQJxiO8EACSAQAOAAQJxiO8EACSAQAuAAQKfxkAAw4ACAmCH1AmAPYBAA4ACAmCH1AmAPYBAAoAAQnkCrh8AS4AAAAA.Baldwin:BAAALgADCgcJBwAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgIJAwAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn82AAMIAAkJnhcIDwBfAgAIAAkJ5RYIDwBfAgAPAAMJFBx6VQDgAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgADCgcJCwAAAA==.Belovis:BAACLgAFFH8TAAIKAAUJEiABHABxAQAKAAUJEiABHABxAQAuAAQKfyYAAgoACQk0JOgMACYDAAoACQk0JOgMACYDAAAA.Berathor:BAAALgAECgkJEwAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJMgAOAHsQAA==.',
Bi='Bidoof:BAABLgAECn8ZAAIQAAcJNAUjNADKAAAQAAcJNAUjNADKAAAAAA==.Bigblunt:BAAALgADCgQJBgAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Birdi:BAAALgAECgEJAQAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgUJDwAAAA==.',
Bo='Boggrog:BAAALgAECgMJAwABLgAECgUJCAANAAAAAA==.Bolz:BAAALgAECgMJAwAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAABLgAECn8oAAIRAAkJAwhGOAA6AQARAAkJAwhGOAA6AQAAAA==.Bowgobrr:BAABLgAECn8qAAMSAAgJ4xXtDAB8AQASAAgJ4xXtDAB8AQAEAAYJ2QqDxQCWAAABLgAFFAcJHQAEAKcRAA==.',
Br='Braelyne:BAABLgAECn8WAAIKAAYJdR3JXwDEAQAKAAYJdR3JXwDEAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJEQAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDgAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Burlycheeks:BAABLgAECn85AAIKAAkJPCDBEwC4AgAKAAkJPCDBEwC4AgAAAA==.',
Ca='Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJDAAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAAALgAECgUJDAAAAA==.Catsneverdie:BAAALgAECgMJDAABLgAFFAMJBgAFAGQFAA==.Catzinhatz:BAABLgAECn8UAAITAAcJ8wnygQD/AAATAAcJ8wnygQD/AAABLgAFFAMJBgAFAGQFAA==.',
Ce='Cecelya:BAABLgAECn80AAQPAAkJ5RnoEwAhAgAPAAkJ5RnoEwAhAgAIAAMJUw0VTwCVAAAUAAIJIQ/gXQBwAAAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8ZAAIRAAYJNBC2RQAyAQARAAYJNBC2RQAyAQABLgAECgkJFgAQANgbAA==.Chillykiller:BAAALgAECgYJBgABLgAECgkJFgAQANgbAA==.Chiva:BAAALgAECgQJBAABLgAECggJKQABABMeAA==.Chivactdl:BAAALgAECgMJBAABLgAECggJKQABABMeAA==.Chivalt:BAAALgAECgEJAQABLgAECggJKQABABMeAA==.Chozen:BAAALgAECggJCwAAAA==.Chunknoriss:BAABLgAECn8gAAMVAAYJwR2qHwD1AQAVAAYJwR2qHwD1AQAWAAIJ6gQpgABBAAABLgAECggJKQABABMeAA==.',
Cl='Claudiuss:BAAALgAECgYJDAABLgAECgkJKAABAKsZAA==.Clurefu:BAABLgAECn8xAAMVAAkJxR+/BgAZAwAVAAkJxR+/BgAZAwAWAAMJ5BZVWACuAAAAAA==.Clurelock:BAABLgAECn8oAAICAAkJyiDJBQBOAwACAAkJyiDJBQBOAwABLgAECgkJMQAVAMUfAA==.Cluremage:BAAALgAECgYJCAAAAA==.',
Co='Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAAALgAECggJEwAAAA==.Constella:BAAALgADCgUJBQAAAA==.Coppertan:BAAALgAECgIJAgAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8dAAIXAAkJyReBCQAMAgAXAAkJyReBCQAMAgAAAA==.',
Cr='Crazyshammy:BAAALgAECgkJEgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crows:BAAALgAECgQJBAAAAA==.Crunchynuget:BAABLgAECn8YAAIKAAgJAx6WIwBfAgAKAAgJAx6WIwBfAgABLgAFFAUJEQAKAKAfAA==.',
Ct='Cthuwu:BAAALgADCgcJDgABLgAFFAUJCQAEAMMHAA==.',
Cu='Cujotaro:BAAALgAECgEJAgAAAA==.Cumberdale:BAAALgADCgcJBwAAAA==.',
Cv='Cvhamster:BAAALgAECgQJBAAAAA==.',
Cy='Cybeast:BAABLgAECn8vAAIDAAkJHh6TAwC9AgADAAkJHh6TAwC9AgAAAA==.Cynortas:BAAALgAECgIJBgAAAA==.',
Da='Daciana:BAAALgAECgYJEwAAAA==.Dados:BAABLgAECn8wAAMPAAkJXh4wDACMAgAPAAkJXh4wDACMAgAUAAEJsBTHbwA+AAAAAA==.Daeghun:BAAALgAECgIJAgAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgAECgMJAwAAAA==.Dambrien:BAAALgAECgUJBQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkfox:BAAALgADCgYJCAAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8wAAIKAAkJtR9EEwC7AgAKAAkJtR9EEwC7AgAAAA==.Darloct:BAAALgAECgQJCgAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8kAAMTAAgJ2halWABkAQAQAAYJexvxJwCDAQATAAgJQg+lWABkAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlifts:BAAALgAECgQJCQAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJJAATANoWAA==.Deadslinger:BAAALgADCgYJDAAAAA==.Deathcat:BAACLgAFFH8GAAIFAAMJZAXSSwBvAAAFAAMJZAXSSwBvAAAuAAQKfzoAAgUACQmjFkcxACYCAAUACQmjFkcxACYCAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8QAAMFAAUJZx6hPQBWAQAFAAUJQh6hPQBWAQAGAAIJhB03FACkAAAAAA==.Deathshadowx:BAAALgAECgUJCAAAAA==.Delryth:BAAALgADCgkJCQAAAA==.Demonkoh:BAAALgAECgUJCAAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgAECgQJBAABLgAECggJGQAWAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn8oAAIUAAkJDQ6YIQCaAQAUAAkJDQ6YIQCaAQAAAA==.',
Do='Dolemite:BAABLgAECn8wAAMVAAcJaBDwNgBmAQAVAAcJaBDwNgBmAQAWAAUJDRSVPAD1AAAAAA==.Donalbain:BAABLgAECn8oAAIBAAkJqxldFwB2AgABAAkJqxldFwB2AgAAAA==.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgADCgYJBgABLgAECgQJBQANAAAAAA==.Draganpriest:BAAALgAECgEJAQAAAA==.Draganussy:BAAALgADCgEJAQAAAA==.Draggo:BAAALgAECgEJAQAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAAALgAECgYJDwAAAA==.',
Du='Durock:BAAALgAECgMJBAAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Elcachazo:BAAALgAECgEJAQAAAA==.Eldinn:BAAALgADCgcJBgAAAA==.Elenora:BAAALgADCgEJAQAAAA==.Elidor:BAAALgAECgQJBwAAAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn8xAAIYAAkJ/xeZDAAoAgAYAAkJ/xeZDAAoAgAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAAALgAECgYJEAAAAA==.Emmils:BAABLgAECn82AAIHAAkJdguAKwBeAQAHAAkJdguAKwBeAQAAAA==.Emìly:BAABLgAECn9BAAQWAAgJcCRXBgDVAgAWAAgJcCRXBgDVAgAVAAgJThXyJQDIAQAJAAUJRRViQQDkAAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIZAAUJbw8oBAAsAQAZAAUJbw8oBAAsAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAABLgAECn9BAAQKAAkJOyFJCwD3AgAKAAkJOyFJCwD3AgALAAcJMR+GCwD2AQAOAAYJtQwfVQDJAAAAAA==.',
Ep='Episkey:BAABLgAECn8bAAMHAAkJyw4oJQCJAQAHAAkJyw4oJQCJAQACAAQJdRcuWwATAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Erissae:BAAALgADCgEJAgAAAA==.Eropor:BAABLgAECn8YAAMVAAYJAQwOUQDzAAAVAAYJAQwOUQDzAAAWAAMJYQbhegBIAAABLgAECgkJVgACAEIeAA==.Eroversion:BAABLgAECn9WAAUCAAkJQh4ZFQCNAgACAAkJQh4ZFQCNAgAHAAQJCBY+VADVAAADAAMJuA29KwCTAAAaAAEJAACLegAAAAAAAA==.',
Es='Esmay:BAABLgAECn8YAAIRAAcJoA8iOgBmAQARAAcJoA8iOgBmAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn89AAIbAAkJTBViBAA5AgAbAAkJTBViBAA5AgAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgAECgEJAwAAAA==.',
Fi='Filgulfin:BAABLgAECn9FAAMEAAkJIx2hDgDIAgAEAAkJIx2hDgDIAgASAAgJgRBaEQAvAQAAAA==.Finkate:BAAALgAECggJEAAAAA==.Firebad:BAABLgAECn8wAAMcAAkJpxwpAgCOAgAcAAkJpxwpAgCOAgAdAAYJHwo61ACbAAAAAA==.Firebringer:BAABLgAECn9GAAITAAkJTAtKVABxAQATAAkJTAtKVABxAQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECgkJIwAeANUXAA==.',
Fl='Flaakk:BAAALgADCgcJBwAAAA==.Flamehunter:BAABLgAECn8iAAMTAAkJMRqEHACnAgATAAkJcRmEHACnAgAQAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn9IAAMUAAkJqBpvDABwAgAUAAkJqBpvDABwAgAPAAMJSAdeUACAAAAAAA==.Floki:BAABLgAECn8UAAIfAAkJqhKtGQBWAQAfAAkJqhKtGQBWAQAAAA==.Flowing:BAAALgAECgkJDgAAAA==.',
Fo='Foods:BAACLgAFFH8JAAMgAAMJIgkSHQCKAAAgAAMJIgkSHQCKAAAfAAEJLwREKgAoAAAuAAQKf0UABCAACQnDF8EYABMCACAACQmRF8EYABMCAB8ABwl6EmIdAC8BACEAAwnoDAdPAHAAAAAA.Foofsmash:BAAALgADCgUJBgAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
['Fø']='Føøds:BAAALgADCgMJAwAAAA==.',
Ga='Gaboo:BAAALgAECgkJEwAAAA==.Garfman:BAAALgAFFAEJAQAAAA==.',
Gb='Gb:BAAALgAFFAQJBAABLgAFFAQJDQAUAPIaAA==.',
Gh='Ghostinhale:BAAALgAECgUJDAAAAA==.',
Gi='Gibbshole:BAAALgADCgcJBwAAAA==.Gilorion:BAABLgAECn8UAAIEAAgJnxbIPwDLAQAEAAgJnxbIPwDLAQAAAA==.',
Gl='Glasgoww:BAAALgAECgMJAwABLgAECgkJKAABAKsZAA==.',
Gn='Gnibat:BAAALgAECgMJAwAAAA==.',
Go='Goburina:BAACLgAFFH8LAAIBAAQJege0OgDcAAABAAQJege0OgDcAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grievo:BAAALgAECgYJCAAAAA==.',
Gy='Gypsiey:BAAALgAECgUJBQAAAA==.',
['Gí']='Gímlí:BAABLgAECn8uAAIEAAkJrRqqIABNAgAEAAkJrRqqIABNAgAAAA==.',
Ha='Halcyndraag:BAABLgAECn8+AAQiAAkJMxTEHgDIAQAiAAcJaxTEHgDIAQAZAAMJ7xWRKADcAAAjAAEJPQJwPgAfAAAAAA==.Handbannana:BAAALgADCgcJBwAAAA==.Handsome:BAAALgAECgcJDAABLgAECggJDgANAAAAAA==.Happydk:BAACLgAFFH8QAAMFAAQJniAgKACNAQAFAAQJniAgKACNAQAYAAMJKRFYIwCmAAAuAAQKfygAAwUACQkdI3ETAMECAAUACQlaIXETAMECABgABwlKGa8iACMBAAAA.Hartu:BAABLgAECn9AAAIfAAkJyw+nFACOAQAfAAkJyw+nFACOAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healsofpain:BAAALgADCgYJBgAAAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAACLgAFFH8HAAIkAAIJuhxsJgDCAAAkAAIJuhxsJgDCAAAuAAQKfy0AAyQACQk4IoEJAHYCACQACQmlIYEJAHYCABsABAnwGtkOACUBAAAA.Hemmorage:BAAALgAECgYJCgABLgAECgkJKQAFANUeAA==.Herbalmist:BAAALgAECgUJCAAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgMJAwAAAA==.',
Ho='Holysea:BAAALgAECgYJDAABLgAECgkJMgAOAHsQAA==.Horatio:BAAALgAECgEJAQABLgAECgkJKAABAKsZAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAECgkJKQAEALUfAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Ic='Icyhooves:BAAALgAECgEJAQAAAA==.',
Id='Idiocracy:BAABLgAECn8VAAMgAAgJHxITKwCVAQAgAAgJ2w4TKwCVAQAfAAYJqRNjHwAdAQAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgMJBgAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgUJCAAAAA==.Irys:BAAALgADCgcJDwAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8PAAIEAAUJYCKQGAB2AQAEAAUJYCKQGAB2AQAuAAQKfxwAAgQACQmXI+cEAD8DAAQACQmXI+cEAD8DAAAA.Ismokeu:BAACLgAFFH8FAAIPAAMJWwa5IACUAAAPAAMJWwa5IACUAAAuAAQKfywAAg8ACAm9GecUABcCAA8ACAm9GecUABcCAAAA.Ismyn:BAAALgADCgEJAgAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneal:BAABLgAECn8YAAIKAAgJWQTTuwDxAAAKAAgJWQTTuwDxAAAAAA==.Jalidelo:BAABLgAECn9AAAMIAAkJWxzYCADLAgAIAAkJWxzYCADLAgAPAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Je='Jenifurr:BAAALgADCgIJAgAAAA==.',
Ji='Jimbowaboki:BAAALgADCgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIdAAkJMhoHJwAzAgAdAAkJMhoHJwAzAgAAAA==.Jokers:BAAALgAECgYJEQAAAA==.Jokersfists:BAAALgAECgYJCgAAAA==.Joranbragi:BAABLgAECn8XAAIKAAYJpgYo2wDFAAAKAAYJpgYo2wDFAAAAAA==.Jordanjr:BAAALgAECgYJCQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8dAAIlAAYJsRCBDgBJAQAlAAYJsRCBDgBJAQAAAA==.Jotoonice:BAABLgAECn8ZAAIeAAgJihXoqAARAQAeAAgJihXoqAARAQAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8NAAQmAAUJahYbEAA9AQAmAAQJ3xMbEAA9AQAEAAEJfg6QiwBCAAASAAIJrQF1LQA8AAAuAAQKfyoABBIACAkPH60gACACABIACAn9F60gACACACYABgmXIiwVAO4BAAQAAglIIY64ALAAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.Justbob:BAAALgAECgUJBgAAAA==.',
['Jú']='Júgg:BAAALgAECgQJBgAAAA==.',
Ka='Kaachow:BAABLgAECn8uAAICAAkJZR9ACAAmAwACAAkJZR9ACAAmAwAAAA==.Kaana:BAABLgAECn89AAIEAAkJLxZvJgAwAgAEAAkJLxZvJgAwAgAAAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAABLgAECn8ZAAIKAAYJKBUZhgBIAQAKAAYJKBUZhgBIAQAAAA==.Karungash:BAACLgAFFH8LAAMdAAQJqgqWUwALAQAdAAQJqgqWUwALAQAcAAEJVQE+GwA+AAAuAAQKfx0AAx0ACAm1Id4QAPMCAB0ACAm1Id4QAPMCABwAAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAIMAAkJzBpwBQA3AgAMAAkJzBpwBQA3AgAAAA==.Karvy:BAABLgAECn8XAAIaAAgJ1hntCwACAgAaAAgJ1hntCwACAgABLgAECgkJJAAMAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAQJEQADAMEkAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8SAAIRAAQJXSCfEQBkAQARAAQJXSCfEQBkAQAuAAQKfyUAAxEACQlhHn4TADcCABEACQlhHn4TADcCABcAAgn1GqMvAEsAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAQJEgARAF0gAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Khthonious:BAABLgAECn8VAAITAAcJBx62NQDZAQATAAcJBx62NQDZAQAAAA==.',
Ki='Kibblsncrits:BAAALgAECgIJAwABLgAECgkJEgANAAAAAA==.Kickingdonut:BAACLgAFFH8FAAIWAAMJNx85FwD4AAAWAAMJNx85FwD4AAAuAAQKfywAAxYACAk7IxkJAOcCABYACAk7IxkJAOcCAAkABgn1GUI3AG4BAAAA.Killerhottie:BAAALgADCgEJAQAAAA==.Killermoomoo:BAAALgAECgQJBwAAAA==.Kittykarma:BAAALgAECgUJBQAAAA==.',
Kl='Kloverr:BAAALgAECgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgADCgEJAQAAAA==.Kombatkarl:BAAALgADCgMJAwAAAA==.Koramere:BAAALgADCgcJBwAAAA==.',
Kr='Kromir:BAAALgADCgkJHQAAAA==.Kromnar:BAAALgADCgEJAQAAAA==.Kronixrage:BAAALgAECgQJBgAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krooler:BAAALgAECgQJBwAAAA==.Krum:BAACLgAFFH8VAAIKAAQJNhyIIABhAQAKAAQJNhyIIABhAQAuAAQKfx4AAgoACAmsHfFGANkBAAoACAmsHfFGANkBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn9IAAIKAAkJqxryIABsAgAKAAkJqxryIABsAgAAAA==.Laurian:BAAALgADCgcJDwAAAA==.Laurì:BAAALgAECgEJAQABLgAECggJQQAWAHAkAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAACLgAFFH8HAAIaAAIJnxpZGACgAAAaAAIJnxpZGACgAAAuAAQKf0wAAxoACQmZIWECAAIDABoACQmZIWECAAIDAAMAAwl9DtMrAJIAAAAA.Leftblank:BAAALgAECgUJCAAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgQJBwABLgAECgQJBwANAAAAAA==.Liszt:BAAALgAECgYJBgAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAgAAAA==.',
Ly='Lychi:BAAALgAECgUJCAAAAA==.Lylora:BAACLgAFFH8NAAICAAMJjh/LJQAWAQACAAMJjh/LJQAWAQAuAAQKf0cAAgIACQlcJOABALADAAIACQlcJOABALADAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8pAAMPAAkJTQ8MIgCdAQAPAAkJTQ8MIgCdAQAUAAUJAgXrWwB4AAAAAA==.',
Ma='Madesh:BAABLgAECn89AAMMAAkJ4Br1BQAkAgATAAkJSRo2JAApAgAMAAkJGBf1BQAkAgAAAA==.Madman:BAABLgAECn8oAAIVAAgJCg94NABzAQAVAAgJCg94NABzAQAAAA==.Maelle:BAABLgAECn8+AAIKAAkJuyKbCgD+AgAKAAkJuyKbCgD+AgAAAA==.Magekaestey:BAABLgAECn8jAAIeAAkJ1ReENAAvAgAeAAkJ1ReENAAvAgAAAA==.Majandra:BAAALgAECgQJBwAAAA==.Malyndra:BAABLgAECn8iAAIQAAkJ1xeEEAAAAgAQAAkJ1xeEEAAAAgAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAAALgAECggJEAAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgADCgMJAwAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Melon:BAAALgADCgEJAQABLgAECgkJDQANAAAAAA==.Meriam:BAAALgAECgEJAgABLgAECgkJKQAFANUeAA==.Merlot:BAAALgADCgEJAgABLgAECgUJCgANAAAAAA==.Mesmash:BAABLgAECn8kAAIfAAkJPx56BgCQAgAfAAkJPx56BgCQAgAAAA==.Metadk:BAAALgAECgQJBAABLgAECggJGQAWAGIXAA==.Metahunt:BAAALgAECgEJAQABLgAECggJGQAWAGIXAA==.Metamasters:BAAALgAECgQJBQABLgAECggJGQAWAGIXAA==.Metavoker:BAAALgAECgEJAQABLgAECggJGQAWAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8vAAIJAAkJDxtlCgB7AgAJAAkJDxtlCgB7AgAAAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBwAAAA==.Miniborg:BAABLgAECn8iAAIEAAkJ+xpnFgCKAgAEAAkJ+xpnFgCKAgABLgAFFAUJEQAKAKAfAA==.Minidude:BAAALgAECgYJEAAAAA==.Miyuki:BAAALgAECgQJBgAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAABLgAECn8WAAIWAAkJ0yFSDQBcAgAWAAkJ0yFSDQBcAgAAAA==.Monkter:BAABLgAECn8ZAAQWAAgJYhfQGADVAQAWAAgJYhfQGADVAQAVAAEJ/gbfbgAmAAAJAAEJfggClQAiAAAAAA==.Monsignore:BAAALgADCgQJBAAAAA==.Moofasaha:BAAALgAECgkJEAAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQATAAceAA==.Morog:BAACLgAFFH8MAAMmAAQJZx6kCABzAQAmAAQJZx6kCABzAQAEAAEJ0w3piwBCAAAuAAQKfykABBIACQmpGyMsAM0BABIABgmOHSMsAM0BAAQABgkbGq0/ALABACYABgnqE8wmAFgBAAAA.Morragan:BAAALgAECgIJAgAAAA==.Mortegom:BAAALgADCgcJBwAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECggJEQAAAA==.',
My='Myinja:BAAALgAECgQJBAABLgAECggJGQAWAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.',
Na='Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECggJDgAAAA==.Nalid:BAACLgAFFH8RAAIDAAQJwSSLAQCzAQADAAQJwSSLAQCzAQAuAAQKf0MAAwMACQnAJicAAJIDAAMACQnAJicAAJIDAAcAAQmuAjmVABsAAAAA.Nanarus:BAACLgAFFH8HAAIPAAIJfRmxIACUAAAPAAIJfRmxIACUAAAuAAQKfz4AAw8ACQmVHqoGAPcCAA8ACQmVHqoGAPcCABQABgmcApdVAJEAAAAA.Nanosec:BAAALgAECgEJAQAAAA==.Nansea:BAAALgAECgEJAQAAAA==.Nashalie:BAABLgAECn8oAAIdAAkJhhtIHABsAgAdAAkJhhtIHABsAgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Neezzdutzz:BAAALgADCgYJBgAAAA==.Nefele:BAABLgAECn8aAAIBAAgJ7xXtLADqAQABAAgJ7xXtLADqAQAAAA==.Nepheli:BAABLgAECn8/AAITAAkJ6yHkBgANAwATAAkJ6yHkBgANAwAAAA==.Newrhu:BAAALgAECgEJAQAAAA==.Nexbasia:BAABLgAECn8+AAMDAAkJFxiXBwA8AgADAAkJFxiXBwA8AgACAAIJ9gL15wAcAAAAAA==.',
Ni='Nickyboy:BAABLgAECn8lAAQcAAcJyiHXBAAPAgAcAAcJyiHXBAAPAgAdAAIJvg5Z7wBqAAAlAAEJrBc/NQA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgUJBQAAAA==.Nikash:BAABLgAECn8mAAMHAAgJkgsHMwAzAQAHAAgJkgsHMwAzAQACAAYJ+Qj6dgDAAAAAAA==.Nisato:BAAALgAECgQJBAAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgcJEwAAAA==.Northic:BAAALgAECgYJBgABLgAECggJNAAFANcgAA==.',
Ny='Nyriah:BAAALgAECgUJCgAAAA==.',
Ob='Obm:BAAALgAECgUJCAAAAA==.',
Oc='Octt:BAABLgAECn8bAAIdAAkJOxskLQAYAgAdAAkJOxskLQAYAgAAAA==.',
Of='Offal:BAABLgAECn8oAAQhAAYJZxAJGAA5AQAhAAYJCAsJGAA5AQAfAAYJZxC1JQDqAAAgAAEJJQVHoAAmAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgQJCAAAAA==.',
Om='Ominis:BAAALgAECgMJAwAAAA==.',
Oo='Oomaw:BAAALgAECgMJBAAAAA==.',
Or='Orcal:BAACLgAFFH8bAAIiAAUJXBTUJAATAQAiAAUJXBTUJAATAQAuAAQKfx0AAiIACAn7GnQQAHECACIACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAAALgAECgUJEwAAAA==.',
Ot='Otherrhu:BAAALgAECgIJAgAAAA==.',
Oz='Ozo:BAABLgAECn8cAAIEAAcJqBJRXgByAQAEAAcJqBJRXgByAQAAAA==.',
Pa='Paiva:BAAALgAECgUJCAAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn89AAILAAkJ/iFEAgD+AgALAAkJ/iFEAgD+AgAAAA==.Pampas:BAABLgAECn8XAAMBAAcJxgTRcgDjAAABAAcJxgTRcgDjAAARAAEJRAEbrAAaAAAAAA==.Pandamonic:BAAALgAECgQJBAAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgUJCAAAAA==.Phoebell:BAAALgAECgQJBwAAAA==.',
Pi='Pinkducky:BAABLgAECn8cAAIFAAYJyQUP3gC8AAAFAAYJyQUP3gC8AAAAAA==.',
Pl='Plen:BAABLgAECn8pAAMFAAkJ1R5aNQBhAgAFAAkJkxxaNQBhAgAYAAYJwxuBFwCOAQAAAA==.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgIJAgAAAA==.Poquads:BAAALgAECgMJAwAAAA==.',
Pr='Primaris:BAAALgAECgYJCwAAAA==.Príestatute:BAAALgAECgUJBQABLgAECgkJLgAEAK0aAA==.',
Pu='Pulmifinger:BAAALgAECgEJAQAAAA==.Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJMgAOAHsQAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Qi='Qilt:BAAALgADCgcJBwAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIeAAkJmBhSOQAdAgAeAAkJmBhSOQAdAgAAAA==.',
Ra='Radra:BAABLgAECn8UAAMQAAcJhAzZJwAXAQAQAAcJhAzZJwAXAQAMAAEJAABSOwAAAAAAAA==.Raeku:BAABLgAECn8tAAImAAkJkCDLBADTAgAmAAkJkCDLBADTAgAAAA==.Rainee:BAAALgADCgEJAQAAAA==.Raja:BAAALgAECgUJDwAAAA==.Ralluur:BAAALgAECgYJAgAAAA==.Rathalo:BAAALgAECgEJAwAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8hAAMMAAYJhRVkFQDjAAATAAYJnBPacwAfAQAMAAUJPxVkFQDjAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8iAAMBAAgJJgjYcgDjAAABAAcJtgTYcgDjAAARAAYJUQMwZQCZAAAAAA==.Retribution:BAABLgAECn82AAIKAAkJXxKURQDdAQAKAAkJXxKURQDdAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgMJBQABLgAECggJQQAWAHAkAA==.',
Ri='Richcraniums:BAAALgADCgcJBwAAAA==.',
Ro='Roachers:BAAALgADCgIJAgAAAA==.Robomurph:BAAALgADCggJDwAAAA==.Ronfax:BAACLgAFFH8bAAMBAAcJyCBaAwBnAgABAAYJPCJaAwBnAgARAAIJxAXpQgBNAAAuAAQKfyMAAwEACQmcIwIHACwDAAEACQmcIwIHACwDABEABgmeHPclAKEBAAAA.Rooss:BAAALgAECgYJEQAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECggJEgAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQAWAGIXAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.Rul:BAAALgAECgQJCgABLgAFFAQJEAAFAJ4gAA==.',
Ry='Ryllae:BAAALgAECgQJBQABLgAECgkJFgAQANgbAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Saint:BAAALgAECggJCQAAAA==.Samson:BAAALgAECgUJEAABLgAECgUJCAANAAAAAA==.Sanivan:BAABLgAECn8VAAIQAAcJ+hdxGgDvAQAQAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgADCgEJAQAAAA==.Sappy:BAABLgAECn8aAAQbAAcJdR9BCQCuAQAbAAYJsh5BCQCuAQAkAAQJrxwzOwA/AQAnAAQJ8BLcCQDFAAABLgAFFAQJEAAFAJ4gAA==.Sarinae:BAABLgAECn8gAAQiAAgJSQVkWACrAAAiAAcJQwRkWACrAAAjAAEJwAF2PgAfAAAZAAEJwAE4KAAXAAAAAA==.Sarmuc:BAABLgAECn8YAAMXAAgJlw/wFABLAQAXAAgJlw/wFABLAQARAAEJXwvGmwApAAAAAA==.Saryda:BAAALgAECgUJCgAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJDAABLgAECgkJKQAFANUeAA==.Scubagal:BAAALgAECgQJBwAAAA==.Scy:BAAALgAECgQJBQAAAA==.Scythraza:BAABLgAECn8dAAMiAAgJIRfBGQDuAQAiAAgJIRfBGQDuAQAjAAEJCQRkOQArAAAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJMgAOAHsQAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Sedge:BAAALgADCgEJAQAAAA==.Seedsprayer:BAAALgAECgYJDAAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAABLgAECn8XAAITAAYJvBwkVQBuAQATAAYJvBwkVQBuAQAAAA==.Sensu:BAAALgAECgUJCwAAAA==.Sensual:BAAALgAECgMJAwAAAA==.Sernian:BAAALgAECgQJCAABLgAFFAQJEwAKACYjAA==.Seä:BAABLgAECn8yAAIOAAkJexADIQDlAQAOAAkJexADIQDlAQAAAA==.',
Sh='Shadoweave:BAABLgAECn8dAAIUAAkJqwdeLQBMAQAUAAkJqwdeLQBMAQAAAA==.Shamtea:BAABLgAECn8qAAIRAAgJ2w0QNQBLAQARAAgJ2w0QNQBLAQAAAA==.Shapzan:BAAALgAECgQJCwAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shiik:BAAALgAECgEJAQABLgAECgYJEQANAAAAAA==.Shivant:BAABLgAECn8pAAMBAAgJEx7ZGQBhAgABAAgJEx7ZGQBhAgARAAEJ9gIeqwAcAAAAAA==.Shmeegleroop:BAAALgAECgQJBAAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAABLgAECn8rAAIMAAkJPSA2AgDRAgAMAAkJPSA2AgDRAgAAAA==.',
Si='Sindice:BAAALgAECgYJCwABLgAFFAcJGwABAMggAA==.',
Sk='Skaa:BAAALgAECgEJAgAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slanesh:BAAALgAECgIJAgAAAA==.Slimpooshady:BAABLgAECn8hAAMCAAkJFhIUJQARAgACAAkJFhIUJQARAgAaAAYJrBIpGQBhAQAAAA==.Sloth:BAAALgAECgkJCQAAAA==.',
So='Solaspirus:BAABLgAECn8iAAMTAAkJYBa6KgAIAgATAAkJYBa6KgAIAgAMAAEJawyLMAArAAAAAA==.Solinius:BAAALgAECgIJAgAAAA==.Sope:BAAALgAECgYJCQAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.Soulomatic:BAAALgADCgcJBwAAAA==.',
Sp='Spectors:BAABLgAECn8kAAMlAAcJbQfCFQD1AAAlAAYJSAjCFQD1AAAdAAcJ5wN+sQDWAAAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAIOAAgJPxyMDwCKAgAOAAgJPxyMDwCKAgAAAA==.Sprayinnseed:BAAALgAECgMJBAAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwANAAAAAA==.',
St='Stabon:BAABLgAECn8lAAIkAAkJcwmRGwCiAQAkAAkJcwmRGwCiAQAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgQJCgAAAA==.',
Sw='Sweetstorm:BAABLgAECn8xAAIQAAgJZwcLKQAPAQAQAAgJZwcLKQAPAQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn80AAIOAAkJWxfnEQBvAgAOAAkJWxfnEQBvAgAAAA==.',
Ta='Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAAALgAECgcJEQAAAA==.Tarixx:BAABLgAFFH8GAAMKAAMJ/w5hJACjAAAKAAIJQg5hJACjAAALAAEJeRDuFAA0AAAAAA==.Tazanoth:BAACLgAFFH8IAAQEAAMJBBJaWQDDAAAEAAMJ0Q9aWQDDAAAmAAIJKQ6+JACTAAASAAEJTArEJgBPAAAuAAQKfyEAAyYACQmaG+wMAEoCACYACQmQGuwMAEoCABIABglBGtYwALABAAAA.',
Te='Teasa:BAABLgAECn80AAIEAAgJpBc1NAD1AQAEAAgJpBc1NAD1AQAAAA==.Tekeelà:BAACLgAFFH8JAAQEAAUJwwdDAgB7AQAEAAUJwwdDAgB7AQAmAAEJhAFRMAA1AAASAAEJVgAiLgA1AAAuAAQKfzIABAQACQl2IaMVAIoCAAQACQkHH6MVAIoCACYACQm6GEUNAEUCABIABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAABLgAECn8VAAMEAAYJQwOLsQC+AAAEAAYJQwOLsQC+AAAmAAUJcgGJTgBZAAAAAA==.Theenna:BAAALgADCgUJBQAAAA==.Thetodd:BAAALgAECgIJAgAAAA==.Thianna:BAABLgAECn8dAAMOAAkJlBZ2HAAJAgAOAAkJlBZ2HAAJAgAKAAYJ8Qo0ywDbAAAAAA==.Thiculuskage:BAABLgAECn8WAAIOAAgJLB4VDQCqAgAOAAgJLB4VDQCqAgAAAA==.Thinkso:BAAALgADCgcJFQAAAA==.Thobu:BAAALgAECgcJCwAAAA==.Thodos:BAAALgADCgEJAQAAAA==.Thornscale:BAABLgAECn9BAAQiAAkJ3hpNDwBYAgAiAAkJ3hpNDwBYAgAZAAUJvBYUDAA/AQAjAAYJogvrKAAsAQAAAA==.Thorrent:BAAALgADCgcJCAAAAA==.',
Ti='Tigolcrittys:BAAALgAECgUJBwABLgAECgkJLgAEAK0aAA==.Timeforloads:BAABLgAECn8bAAMCAAgJTB/aOQCbAQACAAYJAh7aOQCbAQAHAAUJ9hHrQQDpAAAAAA==.',
To='Tolk:BAAALgAECgcJEAAAAA==.Tomzombe:BAAALgAECgQJBgAAAA==.Totem:BAAALgAECggJEwAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Trickyflamom:BAAALgAECgUJBQABLgAFFAQJEwAeACgZAA==.Troloq:BAABLgAECn80AAQlAAkJWB37BgDlAQAdAAgJHhtMMgACAgAlAAgJHRf7BgDlAQAcAAUJ8BmXEQATAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgAECgIJAgAAAA==.Turger:BAAALgAECgUJCAABLgAECgkJEAANAAAAAA==.Turinnii:BAAALgADCgcJBwAAAA==.',
Ul='Uller:BAABLgAECn8oAAIeAAkJDhoIKwBXAgAeAAkJDhoIKwBXAgAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAAALgAECgUJEAAAAA==.Vaimei:BAABLgAECn83AAMcAAkJ+CK4AQCrAgAcAAgJPSO4AQCrAgAdAAgJAyC+EgCqAgAAAA==.Valashune:BAAALgADCgEJAQAAAA==.Valsilla:BAAALgAECgYJBgABLgAECgkJFgAQANgbAA==.Vapor:BAABLgAECn8hAAIbAAgJOBjbBQACAgAbAAgJOBjbBQACAgAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebs:BAABLgAECn8VAAMgAAgJCBN2JgCxAQAgAAgJCBN2JgCxAQAfAAEJAAAySAAuAAAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8fAAIeAAgJaQZDogAdAQAeAAgJaQZDogAdAQAAAA==.Vento:BAABLgAECn8VAAIFAAgJjxViVgCuAQAFAAgJjxViVgCuAQAAAA==.Verité:BAAALgAECgYJCwAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgAECgEJAQABLgAECgkJQQAKADshAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn86AAITAAkJmBR/LAAAAgATAAkJmBR/LAAAAgAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgUJDAAAAA==.Voltimand:BAAALgAECgEJAQABLgAECgkJKAABAKsZAA==.',
Vv='Vvicked:BAABLgAECn8gAAIFAAgJrCIoEwDDAgAFAAgJrCIoEwDDAgAAAA==.',
Vy='Vynesta:BAABLgAECn8WAAIQAAkJ2BurCgBgAgAQAAkJ2BurCgBgAgAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wanagi:BAAALgADCgMJAwAAAA==.Wankz:BAAALgAECgkJEgAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8dAAIgAAgJSiJrDgB3AgAgAAgJSiJrDgB3AgAAAA==.',
We='Weyna:BAABLgAECn84AAMVAAgJ3hHOKgCqAQAVAAgJ3hHOKgCqAQAJAAYJVAkISADMAAAAAA==.',
Wh='Whisperingei:BAAALgAECgYJCgAAAA==.',
Wi='Widowx:BAABLgAECn8tAAIRAAkJtRoQFAAyAgARAAkJtRoQFAAyAgAAAA==.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAABLgAECn8VAAIEAAcJbRqgNgDrAQAEAAcJbRqgNgDrAQABLgAECggJKwAPABMiAA==.',
Wr='Wrandohunt:BAAALgAECgEJAwAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wreckitrandy:BAAALgADCgQJBAAAAA==.Wryn:BAAALgAECgcJDwABLgAECgkJKQAFANUeAA==.',
Wu='Wulyn:BAAALgAECgUJCwAAAA==.',
Wy='Wylla:BAAALgAECgUJCgAAAA==.',
Xa='Xalethra:BAABLgAECn80AAITAAkJByQoBAA2AwATAAkJByQoBAA2AwAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xenophobias:BAAALgAECgYJEAAAAA==.',
Xh='Xhosen:BAAALgAFFAIJBAAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn82AAICAAkJRBf0IwAYAgACAAkJRBf0IwAYAgAAAA==.',
Ya='Yarloon:BAAALgADCgcJBwAAAA==.',
Yv='Yve:BAAALgAECgUJDQAAAA==.',
Za='Zalajin:BAAALgAECgQJBAAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zarayndia:BAAALgAECgQJCAAAAA==.',
Ze='Zeddicus:BAABLgAECn8hAAMlAAkJ9gXsDwA/AQAlAAkJhQXsDwA/AQAdAAUJ0AOo3wCGAAAAAA==.Zendragan:BAABLgAECn8eAAIVAAkJThgrFABYAgAVAAkJThgrFABYAgAAAA==.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoe:BAAALgADCgcJAwAAAA==.Zoidz:BAAALgAECggJDAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zombruh:BAAALgAECgEJAQAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.Zythopoios:BAAALgAECgIJAwAAAA==.',
Zz='Zzilladi:BAABLgAFFH8HAAMPAAQJIBbUFAD4AAAPAAMJ2hzUFAD4AAAUAAEJAADLOAAAAAAAAA==.Zzilladinzz:BAACLgAFFH8TAAIKAAQJjSAFIQBfAQAKAAQJjSAFIQBfAQAuAAQKfyIAAgoACQkIIwsSAAIDAAoACQkIIwsSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgAECgYJDwABLgAECgkJKwAMAD0gAA==.',
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
