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

local lookup = {'Shaman-Restoration','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Monk-Brewmaster','Paladin-Retribution','Paladin-Protection','DemonHunter-Vengeance','Paladin-Holy','Unknown-Unknown','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Shaman-Elemental','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Druid-Guardian','Rogue-Assassination','Warlock-Demonology','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Warrior-Fury','Warrior-Arms','Evoker-Preservation','Rogue-Subtlety','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aarmorr:BAABLgAECn9MAAIBAAkJmhnBFQCZAgABAAkJmhnBFQCZAgAAAA==.Aatus:BAAALgADCgkJEAAAAA==.',
Ab='Absoul:BAAALgAECgQJBAAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgQJBgAAAA==.',
Ad='Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aechelus:BAAALgADCgEJAQABLgAECggJFQACAAceAA==.Aedelas:BAAALgAECgIJAwAAAA==.Aeloriá:BAABLgAECn9HAAMDAAkJHiBBBwBBAwADAAkJHiBBBwBBAwAEAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECgcJDAAAAA==.',
Ag='Agrosa:BAAALgAECgYJBgAAAA==.',
Ai='Aimeeiove:BAAALgAECgYJCQAAAA==.Airad:BAAALgADCgUJBgAAAA==.Airoldeel:BAAALgADCgUJBQAAAA==.',
Al='Alcarza:BAAALgAECgMJBQAAAA==.Alchon:BAABLgAECn8kAAIFAAkJ6xpmLgAfAgAFAAkJ6xpmLgAfAgAAAA==.Aldera:BAABLgAECn8pAAIBAAkJ/wTYZQAlAQABAAkJ/wTYZQAlAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8jAAMGAAkJwRzjRgDrAQAGAAkJwRzjRgDrAQAHAAEJyhBgFgA3AAAAAA==.Alista:BAAALgAECgYJCwAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn9EAAMDAAcJJhe6MgDRAQADAAcJJhe6MgDRAQAIAAYJRxEpPgASAQAAAA==.Alorris:BAAALgAECgQJBgABLgAECgkJGQAJAFggAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECggJDwAAAA==.Alyra:BAAALgAECgYJBgAAAA==.',
Am='Amata:BAAALgAECgUJCwAAAA==.Amelianne:BAAALgAECgcJEQAAAA==.Amiria:BAAALgAECgYJBgAAAA==.Ammastary:BAAALgAECgQJBgAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgkJLwAKAA8bAA==.Andragos:BAAALgAECgQJBgAAAA==.Andrea:BAABLgAECn9EAAIEAAkJYR3SBACqAgAEAAkJYR3SBACqAgAAAA==.Anthria:BAAALgAECgcJEAAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arcapeligo:BAAALgAECgEJAgAAAA==.Archonsfury:BAAALgAECggJDwAAAA==.Arilyn:BAAALgAECgIJAgAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgAAAA==.Asheye:BAAALgAECgkJCgABLgAECgkJKQAGANUeAA==.Ashuranadi:BAAALgADCgcJBwAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJEQAAAA==.Asura:BAAALgAECgcJCAAAAA==.Asyllaa:BAABLgAECn8eAAMLAAkJFx+tKwBQAgALAAcJOyOtKwBQAgAMAAYJ9hJbHwAWAQAAAA==.',
At='Atnawuerus:BAAALgAECgEJAQAAAA==.Atonement:BAAALgAECgcJDgABLgAECgkJLgANAKAgAA==.',
Au='Aumaril:BAABLgAECn8ZAAMOAAgJsBTRGgAsAgAOAAgJsBTRGgAsAgALAAgJNxQFYgCqAQAAAA==.Auralynn:BAABLgAECn8iAAILAAkJFQk/jwBQAQALAAkJFQk/jwBQAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averus:BAABLgAECn9MAAIIAAkJ3hHiHADeAQAIAAkJ3hHiHADeAQAAAA==.',
Az='Azariel:BAABLgAECn85AAILAAkJixO9UgDOAQALAAkJixO9UgDOAQAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn9GAAMMAAkJ6B3cBQCLAgAMAAkJIB3cBQCLAgALAAEJXyFuSQFgAAAAAA==.',
Ba='Baane:BAAALgAECgQJBwABLgAECgYJEAAPAAAAAA==.Babnik:BAEALgAECgkJEwAAAA==.Bagel:BAACLgAFFH8ZAAIOAAUJHCNzDADjAQAOAAUJHCNzDADjAQAuAAQKfxkAAw4ACAmCH1AmAPYBAA4ACAmCH1AmAPYBAAsAAQnkCvqiASsAAAAA.Baldwin:BAAALgADCgcJBwAAAA==.Ballbreaker:BAAALgAECgQJBAAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgIJAwAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn89AAQJAAkJnhcPEQBfAgAJAAkJ5RYPEQBfAgAQAAMJFBx6VQDgAAARAAEJKwpDjAAsAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgAECgIJAgAAAA==.Belovis:BAACLgAFFH8aAAILAAUJriSHFwCmAQALAAUJriSHFwCmAQAuAAQKfyYAAgsACQk0JOgMACYDAAsACQk0JOgMACYDAAAA.Berathor:BAAALgAECgkJEwAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJOQAOAGYTAA==.',
Bi='Bidoof:BAABLgAECn8hAAISAAkJPwgFJwA9AQASAAkJPwgFJwA9AQAAAA==.Bigblunt:BAAALgADCgcJDwAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Birdi:BAAALgAECgEJAQAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgYJDwAAAA==.',
Bo='Boggrog:BAAALgAECgQJBAABLgAECgUJCwAPAAAAAA==.Bolz:BAAALgAECgMJAwAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAABLgAECn8vAAITAAkJkgr7NQBeAQATAAkJkgr7NQBeAQAAAA==.Bowgobrr:BAABLgAECn8qAAMUAAgJ4xWgDgBvAQAUAAgJ4xWgDgBvAQAFAAYJ2QoX2QCTAAABLgAFFAcJHQAFAKcRAA==.',
Br='Braelyne:BAABLgAECn8WAAILAAYJdR3JXwDEAQALAAYJdR3JXwDEAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJEQAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDgAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Burlycheeks:BAABLgAECn85AAILAAkJPCDoFwCxAgALAAkJPCDoFwCxAgAAAA==.',
Ca='Caliista:BAAALgADCggJCAAAAA==.Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJDAAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAAALgAECgYJEQAAAA==.Catsneverdie:BAAALgAECgMJDAABLgAFFAMJDAAGADkPAA==.Catzinhatz:BAABLgAECn8WAAICAAcJAgrZjAACAQACAAcJAgrZjAACAQABLgAFFAMJDAAGADkPAA==.',
Ce='Cecelya:BAABLgAECn8/AAQQAAkJ5RnqFgAUAgAQAAkJ5RnqFgAUAgARAAcJ8Q+nMwBJAQAJAAMJUw2BWgCQAAAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8ZAAITAAYJNBC2RQAyAQATAAYJNBC2RQAyAQABLgAECgkJHQASAFciAA==.Chillykiller:BAAALgAECgYJBgABLgAECgkJHQASAFciAA==.Chiva:BAAALgAECgQJBAABLgAECggJNAABABMeAA==.Chivactdl:BAAALgAECgMJBAABLgAECggJNAABABMeAA==.Chivalt:BAAALgAECgEJAQABLgAECggJNAABABMeAA==.Chozen:BAAALgAECggJCwAAAA==.Chunknoriss:BAABLgAECn8oAAMVAAYJYiAoHQApAgAVAAYJYiAoHQApAgAWAAIJ6gQZjgBAAAABLgAECggJNAABABMeAA==.',
Cl='Claudiuss:BAAALgAECgYJDAABLgAFFAMJBgABAD4OAA==.Clurefu:BAABLgAECn84AAMVAAkJvCHzBABaAwAVAAkJvCHzBABaAwAWAAMJ5BZVWACuAAABLgAFFAIJBgADAMoYAA==.Clurelock:BAACLgAFFH8GAAIDAAIJyhhrSACSAAADAAIJyhhrSACSAAAuAAQKfy8AAgMACQnKIKYGAEsDAAMACQnKIKYGAEsDAAAA.Cluremage:BAAALgAECgYJCAAAAA==.Clurethyr:BAAALgAECggJDQAAAA==.',
Co='Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAABLgAECn8UAAIVAAgJIBtuGQBHAgAVAAgJIBtuGQBHAgAAAA==.Constella:BAAALgADCgYJCQAAAA==.Coppertan:BAAALgAECgMJBQAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8nAAIXAAkJLx1qBACoAgAXAAkJLx1qBACoAgAAAA==.',
Cr='Crazyshammy:BAAALgAECgkJEgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crows:BAAALgAECgYJDwAAAA==.Crunchynuget:BAABLgAECn8gAAILAAgJ3h5LJQBtAgALAAgJ3h5LJQBtAgABLgAFFAUJFQALABkgAA==.',
Ct='Cthuwu:BAAALgAECgMJAgABLgAFFAUJCQAFAMMHAA==.',
Cu='Cujotaro:BAAALgAECgEJAgAAAA==.Cumberdale:BAAALgAECgUJBQAAAA==.',
Cv='Cvhamster:BAAALgAECgQJCgAAAA==.',
Cy='Cybeast:BAABLgAECn8vAAIEAAkJHh5nBAC3AgAEAAkJHh5nBAC3AgAAAA==.Cynortas:BAAALgAECgIJBgAAAA==.',
Da='Daciana:BAABLgAECn8YAAIFAAYJ6RCSigAlAQAFAAYJ6RCSigAlAQAAAA==.Dados:BAABLgAECn8wAAMQAAkJXh4oDgCBAgAQAAkJXh4oDgCBAgARAAEJsBTifQA9AAAAAA==.Daeghun:BAAALgAECgIJAgAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgAECgQJBwAAAA==.Dambrien:BAAALgAECgUJBQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkfox:BAAALgADCgkJGAAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8wAAILAAkJtR87FwC1AgALAAkJtR87FwC1AgAAAA==.Darloct:BAAALgAECgYJEQAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8kAAMCAAgJ2hbbYQBhAQASAAYJexvxJwCDAQACAAgJQg/bYQBhAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlifts:BAAALgAECgQJCQAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJJAACANoWAA==.Deadslinger:BAAALgADCgYJDAAAAA==.Deathcat:BAACLgAFFH8MAAIGAAMJOQ/unQDVAAAGAAMJOQ/unQDVAAAuAAQKfzoAAgYACQmjFgc3ACACAAYACQmjFgc3ACACAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8RAAQGAAUJZx5gTwBOAQAGAAUJQh5gTwBOAQAHAAIJhB1eGwCdAAAYAAEJIBh+OgBFAAAAAA==.Deathshadowx:BAAALgAECgUJCwAAAA==.Delryth:BAAALgAECgQJBAAAAA==.Demonkoh:BAAALgAECgUJCAAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgAECgQJBAABLgAECggJGQAWAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn8vAAIRAAkJPxSgFwAJAgARAAkJPxSgFwAJAgAAAA==.',
Do='Dolemite:BAABLgAECn84AAMVAAcJHhYALgC+AQAVAAcJHhYALgC+AQAWAAUJQBUKPwD/AAAAAA==.Donalbain:BAACLgAFFH8GAAIBAAMJPg5SUQCqAAABAAMJPg5SUQCqAAAuAAQKfygAAgEACQmrGXkaAHMCAAEACQmrGXkaAHMCAAAA.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgADCgYJBgABLgAECgQJBQAPAAAAAA==.Draganpriest:BAAALgAFFAMJAwAAAA==.Draganussy:BAAALgADCgEJAQAAAA==.Draggo:BAAALgAECgEJAQAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAABLgAECn8VAAMZAAYJAQ0GGQDXAAAZAAYJRAwGGQDXAAAaAAMJ4AmWJACXAAAAAA==.',
Du='Durock:BAAALgAECgMJBAAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Elcachazo:BAAALgAECgIJAgAAAA==.Eldinn:BAAALgADCgcJBgAAAA==.Elenora:BAAALgAECgMJAwAAAA==.Elidor:BAAALgAECgUJCQAAAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn80AAIYAAkJihnjDQAqAgAYAAkJihnjDQAqAgAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAABLgAECn8UAAIGAAYJ8QKMCQGbAAAGAAYJ8QKMCQGbAAAAAA==.Emmils:BAABLgAECn89AAIIAAkJfA2jKQCCAQAIAAkJfA2jKQCCAQAAAA==.Emìly:BAABLgAECn9PAAQWAAkJGiQBAwAzAwAWAAkJGiQBAwAzAwAVAAkJCxbiHgAdAgAKAAUJRRVsRQDiAAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIbAAUJbw8xBQARAQAbAAUJbw8xBQARAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAACLgAFFH8GAAILAAQJmhnBLgBPAQALAAQJmhnBLgBPAQAuAAQKf0EABAsACQk7IQwOAPMCAAsACQk7IQwOAPMCAAwABwkxHygNAO8BAA4ABgm1DJ5aAMgAAAAA.',
Ep='Episkey:BAABLgAECn8eAAMIAAkJbRCHJQCcAQAIAAkJbRCHJQCcAQADAAQJdRdWYAASAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Erissae:BAAALgADCgEJAgAAAA==.Eropor:BAABLgAECn8iAAMVAAYJexM8QABlAQAVAAYJexM8QABlAQAWAAMJYQZRiABHAAABLgAFFAQJEgADAKsQAA==.Eroversion:BAACLgAFFH8SAAIDAAQJqxAdMgDgAAADAAQJqxAdMgDgAAAuAAQKf1YABQMACQlCHjUXAIoCAAMACQlCHjUXAIoCAAgABAkIFj5UANUAAAQAAwm4DQkyAJEAABwAAQkAAM2QAAAAAAAA.',
Es='Esmay:BAABLgAECn8fAAITAAkJHRS0HwDiAQATAAkJHRS0HwDiAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn9LAAIdAAkJ2RgABABeAgAdAAkJ2RgABABeAgAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgAECgEJAwAAAA==.Feliri:BAAALgADCgcJCgAAAA==.',
Fi='Filgulfin:BAABLgAECn9RAAMFAAkJwx0OEADMAgAFAAkJwx0OEADMAgAUAAgJgRCAEwAkAQAAAA==.Finkate:BAABLgAECn8XAAIFAAgJHA4qYQB/AQAFAAgJHA4qYQB/AQAAAA==.Firebad:BAABLgAECn8wAAMZAAkJpxycAgCHAgAZAAkJpxycAgCHAgAeAAYJHwrH4ACYAAAAAA==.Firebringer:BAABLgAECn9RAAICAAkJOQ7NSQClAQACAAkJOQ7NSQClAQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECgkJIwAfANUXAA==.',
Fl='Flaakk:BAAALgADCgcJBwAAAA==.Flamehunter:BAABLgAECn8iAAMCAAkJMRqEHACnAgACAAkJcRmEHACnAgASAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn9UAAMRAAkJhxzwCgCgAgARAAkJhxzwCgCgAgAQAAMJSAfgVgB5AAAAAA==.Floki:BAABLgAECn8UAAIgAAkJqhL+HABLAQAgAAkJqhL+HABLAQAAAA==.Flora:BAAALgAECgQJBAAAAA==.Flowing:BAABLgAECn8gAAIhAAkJSBdaEwBCAgAhAAkJSBdaEwBCAgAAAA==.',
Fo='Foods:BAACLgAFFH8NAAMiAAMJMBGDPQCoAAAiAAMJMBGDPQCoAAAgAAEJLwRLLwAiAAAuAAQKf1YABCIACQkSHKYQAHECACIACQlgG6YQAHECACAACAlkFf4SALkBACMAAwnoDE0wAHUAAAAA.Foofsmash:BAAALgADCgUJBgAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
['Fø']='Føøds:BAAALgADCgMJAwAAAA==.',
Ga='Gaboo:BAAALgAECgkJEwAAAA==.Garfman:BAAALgAFFAEJAQAAAA==.',
Gb='Gb:BAABLgAFFH8GAAIOAAUJGgwHHgAnAQAOAAUJGgwHHgAnAQABLgAFFAQJDQARAPIaAA==.',
Gh='Ghostinhale:BAAALgAECgUJEQAAAA==.',
Gi='Gibbshole:BAAALgADCgcJBwAAAA==.Gilorion:BAABLgAECn8XAAIFAAkJ7Ra4MQARAgAFAAkJ7Ra4MQARAgAAAA==.',
Gl='Glasgoww:BAAALgAECgYJCQABLgAFFAMJBgABAD4OAA==.',
Gn='Gnibat:BAAALgAECgMJBgAAAA==.',
Go='Goburina:BAACLgAFFH8OAAIBAAQJegdoSQDDAAABAAQJegdoSQDDAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grenache:BAAALgAECgEJAQABLgAECgUJDQAPAAAAAA==.Grievo:BAAALgAECgYJCAAAAA==.',
Gy='Gypsiey:BAAALgAECgUJBQAAAA==.',
['Gí']='Gímlí:BAACLgAFFH8FAAIFAAMJBQ9PYADcAAAFAAMJBQ9PYADcAAAuAAQKfzUAAgUACQnxHDccAHcCAAUACQnxHDccAHcCAAAA.',
Ha='Halcyndraag:BAABLgAECn9MAAQhAAkJLhXLIADRAQAhAAcJKhXLIADRAQAbAAMJQBeeGQCBAAAkAAEJPQJcQwAeAAAAAA==.Handbannana:BAAALgADCgcJBwAAAA==.Handsome:BAAALgAECgcJDAABLgAECggJDgAPAAAAAA==.Happydk:BAACLgAFFH8RAAMGAAQJniC0OgB9AQAGAAQJniC0OgB9AQAYAAMJKRFmKwCaAAAuAAQKfygAAwYACQkdI+QWALsCAAYACQlaIeQWALsCABgABwlKGYwmABwBAAAA.Hartu:BAABLgAECn9GAAIgAAkJfxSlDwDqAQAgAAkJfxSlDwDqAQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healsofpain:BAAALgADCgYJBgAAAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAACLgAFFH8LAAIlAAIJViE9LADCAAAlAAIJViE9LADCAAAuAAQKfzAAAyUACQnhIm4JAIwCACUACQlOIm4JAIwCAB0ABAnwGvkPACMBAAAA.Hemmorage:BAAALgAECgYJCgABLgAECgkJKQAGANUeAA==.Herbalmist:BAAALgAECgUJCwAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgMJAwAAAA==.',
Ho='Holysea:BAAALgAECgYJDAABLgAECgkJOQAOAGYTAA==.Horatio:BAAALgAECgEJAQABLgAFFAMJBgABAD4OAA==.',
Hr='Hraken:BAAALgAECgUJBgAAAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAFFAMJBwAFABUYAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Ic='Icyhooves:BAAALgAECgEJAQAAAA==.',
Id='Idiocracy:BAABLgAECn8lAAMgAAkJbhb0DAAXAgAgAAkJrRX0DAAXAgAiAAgJ2w7fLwCOAQAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgMJBgAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgUJCAAAAA==.Irys:BAAALgAECgMJAwAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8PAAIFAAUJYCL+JABpAQAFAAUJYCL+JABpAQAuAAQKfxwAAgUACQmXI+cEAD8DAAUACQmXI+cEAD8DAAAA.Ismokeu:BAACLgAFFH8LAAIQAAMJwhABIAC0AAAQAAMJwhABIAC0AAAuAAQKfzoAAhAACQmrGV0NAI0CABAACQmrGV0NAI0CAAAA.Ismyn:BAAALgAECgEJAQAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneal:BAABLgAECn8gAAILAAkJ+wTwowAvAQALAAkJ+wTwowAvAQAAAA==.Jalidelo:BAABLgAECn9EAAMJAAkJXx1tCADtAgAJAAkJXx1tCADtAgAQAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Je='Jenifurr:BAAALgADCgIJAgAAAA==.',
Ji='Jimbowaboki:BAAALgADCgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIeAAkJMhocKwAsAgAeAAkJMhocKwAsAgAAAA==.Jokers:BAABLgAECn8XAAMgAAYJFxPrIQAdAQAgAAYJFxPrIQAdAQAiAAMJCQnDjQBTAAAAAA==.Jokersfists:BAAALgAECgYJEQAAAA==.Joranbragi:BAABLgAECn8jAAILAAYJnwdb4gDYAAALAAYJnwdb4gDYAAAAAA==.Jordanjr:BAAALgAECgYJCQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8dAAIaAAYJsRCBDgBJAQAaAAYJsRCBDgBJAQAAAA==.Jotoonice:BAABLgAECn8ZAAIfAAgJjBUJYAC9AQAfAAgJjBUJYAC9AQAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8OAAQmAAYJExdOFAAnAQAmAAQJ3xNOFAAnAQAUAAMJsg2/KwBWAAAFAAEJfg6npABCAAAuAAQKfy0ABCYACAn9H/gTAAYCABQACAn9F60gACACACYABgkaJPgTAAYCAAUAAglIIVPLAKsAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.Justbob:BAAALgAECgUJBgAAAA==.',
['Jú']='Júgg:BAAALgAECgQJBgAAAA==.',
Ka='Kaachow:BAABLgAECn8uAAIDAAkJZR9SCQAjAwADAAkJZR9SCQAjAwAAAA==.Kaana:BAABLgAECn9KAAIFAAkJ7xm0HgBqAgAFAAkJ7xm0HgBqAgAAAA==.Kaestey:BAAALgAECggJCAABLgAECgkJIwAfANUXAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAABLgAECn8dAAILAAYJIRXHlQBFAQALAAYJIRXHlQBFAQAAAA==.Karungash:BAACLgAFFH8LAAMeAAQJqgqhYQD/AAAeAAQJqgqhYQD/AAAZAAEJVQE+GwA+AAAuAAQKfx0AAx4ACAm1Id4QAPMCAB4ACAm1Id4QAPMCABkAAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAINAAkJzBp7BgAqAgANAAkJzBp7BgAqAgAAAA==.Karvy:BAABLgAECn8fAAIcAAgJchraDAAPAgAcAAgJchraDAAPAgABLgAECgkJJAANAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAUJEwAEACYlAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8TAAITAAQJXSCNGABOAQATAAQJXSCNGABOAQAuAAQKfyUAAxMACQlhHiMWADICABMACQlhHiMWADICABcAAgn1Gmc3AEoAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAQJEwATAF0gAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Khthonious:BAABLgAECn8VAAICAAcJBx5NOgDaAQACAAcJBx5NOgDaAQAAAA==.',
Ki='Kibblsncrits:BAAALgAECgIJAwABLgAECgkJEgAPAAAAAA==.Kickingdonut:BAACLgAFFH8FAAIWAAMJNx8fGwDuAAAWAAMJNx8fGwDuAAAuAAQKfywAAxYACAk7IxkJAOcCABYACAk7IxkJAOcCAAoABgn1GUI3AG4BAAAA.Killerhottie:BAAALgAECgEJAQAAAA==.Killermoomoo:BAAALgAECgQJCgAAAA==.Kinoh:BAAALgADCgkJEAAAAA==.Kittykarma:BAAALgAECgUJBQAAAA==.',
Kl='Kloverr:BAAALgAECgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgADCgEJAQAAAA==.Kombatkarl:BAAALgADCgMJAwAAAA==.Koramere:BAAALgADCgcJBwAAAA==.',
Kr='Kretaios:BAAALgADCgQJBAAAAA==.Kromir:BAAALgAECgQJBAAAAA==.Kromnar:BAAALgADCgEJAQAAAA==.Kronixrage:BAAALgAECgYJCAAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krooler:BAAALgAECgQJBwAAAA==.Krum:BAACLgAFFH8ZAAILAAUJaR80JgBqAQALAAUJaR80JgBqAQAuAAQKfx4AAgsACAmsHVVQANUBAAsACAmsHVVQANUBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn9UAAILAAkJHRubIQB+AgALAAkJHRubIQB+AgAAAA==.Lardend:BAAALgAECgYJBgAAAA==.Laurian:BAAALgADCgcJDwAAAA==.Laurì:BAAALgAECgMJAwABLgAECgkJTwAWABokAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAACLgAFFH8LAAIcAAIJ0RwUHQCoAAAcAAIJ0RwUHQCoAAAuAAQKf14AAxwACQnPIdMCAAMDABwACQnPIdMCAAMDAAQAAwl9DiIyAJEAAAAA.Leftblank:BAAALgAECgUJCwAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgUJCQABLgAECgUJCQAPAAAAAA==.Liszt:BAAALgAECgYJBgAAAA==.Litallya:BAAALgAECggJDQAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Loriane:BAAALgAECgUJCAABLgAECgkJKAADAAIgAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lotharbacco:BAAALgAECgMJAwAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAgAAAA==.',
Ly='Lychi:BAAALgAECgUJCwAAAA==.Lylora:BAACLgAFFH8UAAIDAAQJiSAyGwB5AQADAAQJiSAyGwB5AQAuAAQKf08AAgMACQm8JMkBALoDAAMACQm8JMkBALoDAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8sAAMQAAkJTQ8HJgCQAQAQAAkJTQ8HJgCQAQARAAUJAgXLaAB0AAAAAA==.',
Ma='Madesh:BAABLgAECn9GAAMNAAkJSBviBQA8AgANAAkJtxjiBQA8AgACAAkJSRqpJwApAgAAAA==.Madman:BAABLgAECn8uAAIVAAgJMBAYOACLAQAVAAgJMBAYOACLAQAAAA==.Maelle:BAABLgAECn9MAAILAAkJ2iLtCwAEAwALAAkJ2iLtCwAEAwAAAA==.Magekaestey:BAABLgAECn8jAAIfAAkJ1RfPOwAoAgAfAAkJ1RfPOwAoAgAAAA==.Majandra:BAAALgAECgUJDAAAAA==.Malyndra:BAABLgAECn8nAAMSAAkJvxq7DgA2AgASAAkJvxq7DgA2AgANAAEJAw/UMQA5AAAAAA==.Malyssa:BAAALgADCgIJAgAAAA==.Marianne:BAAALgADCgEJAQAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAABLgAECn8YAAIeAAgJcA3OawBkAQAeAAgJcA3OawBkAQAAAA==.Masy:BAAALgAECgEJAQAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgAECgEJAQAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Melon:BAAALgADCgEJAQABLgAECgkJDQAPAAAAAA==.Meriam:BAAALgAECgEJAgABLgAECgkJKQAGANUeAA==.Merlot:BAAALgADCgEJAgABLgAECgUJDQAPAAAAAA==.Mesmash:BAABLgAECn8rAAIgAAkJYSEwBADkAgAgAAkJYSEwBADkAgAAAA==.Metadk:BAAALgAECgQJBgABLgAECggJGQAWAGIXAA==.Metahunt:BAAALgAECgIJAgABLgAECggJGQAWAGIXAA==.Metamasters:BAAALgAECgQJBQABLgAECggJGQAWAGIXAA==.Metavoker:BAAALgAECgEJAQABLgAECggJGQAWAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8vAAIKAAkJDxu2CwB3AgAKAAkJDxu2CwB3AgAAAA==.Midgiit:BAAALgAECgUJBQABLgAECgkJKQAGANUeAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBwAAAA==.Miniborg:BAABLgAECn8iAAIFAAkJ+xo6GwB9AgAFAAkJ+xo6GwB9AgABLgAFFAUJFQALABkgAA==.Minidude:BAAALgAECgYJEAAAAA==.Miyuki:BAAALgAECgQJBgAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAABLgAECn8WAAIWAAkJ0yEqDwBUAgAWAAkJ0yEqDwBUAgAAAA==.Monkter:BAABLgAECn8ZAAQWAAgJYhccHADKAQAWAAgJYhccHADKAQAVAAEJ/gbfbgAmAAAKAAEJfghhngAiAAAAAA==.Monsignore:BAAALgADCgQJBAAAAA==.Moofasaha:BAAALgAECgkJEAAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQACAAceAA==.Morog:BAACLgAFFH8UAAMmAAYJSRllBgChAQAmAAYJSRllBgChAQAFAAEJ0w0GpQBCAAAuAAQKfykABBQACQmpGyMsAM0BABQABgmOHSMsAM0BAAUABgkbGq0/ALABACYABgnqE8kpAFIBAAAA.Morragan:BAAALgAECgQJBQAAAA==.Mortegom:BAAALgADCgcJBwAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECggJEQAAAA==.',
My='Myinja:BAAALgAECgQJBAABLgAECggJGQAWAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.',
Na='Naadra:BAAALgAECgEJAQAAAA==.Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECggJDgAAAA==.Nalid:BAACLgAFFH8TAAIEAAUJJiV1AgCsAQAEAAUJJiV1AgCsAQAuAAQKf0QAAwQACQnAJjsAAI0DAAQACQnAJjsAAI0DAAgAAQmuAmujABsAAAAA.Nanarus:BAACLgAFFH8LAAIQAAIJfRkxJQCPAAAQAAIJfRkxJQCPAAAuAAQKf0kAAxAACQmVHu8HAOsCABAACQmVHu8HAOsCABEABgnkAyRVALsAAAAA.Nanosec:BAAALgAECgEJAQAAAA==.Nansea:BAAALgAECgEJAQAAAA==.Nashalie:BAABLgAECn8sAAIeAAkJ+RzFGwB8AgAeAAkJ+RzFGwB8AgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Neezzdutzz:BAAALgAECgMJAwAAAA==.Nefele:BAABLgAECn8fAAIBAAkJ5RVoIgA8AgABAAkJ5RVoIgA8AgAAAA==.Nepheli:BAACLgAFFH8GAAICAAMJUxcLVADsAAACAAMJUxcLVADsAAAuAAQKf0sAAgIACQlrJDEDAFMDAAIACQlrJDEDAFMDAAAA.Newrhu:BAAALgAECgYJBwAAAA==.Nexbasia:BAACLgAFFH8IAAIEAAIJkQ0hFQCAAAAEAAIJkQ0hFQCAAAAuAAQKf08AAwQACQk6GdkHAFICAAQACQk6GdkHAFICAAMAAgn2Atf2ABsAAAAA.',
Ni='Nickyboy:BAABLgAECn8lAAQZAAcJyiGqBQALAgAZAAcJyiGqBQALAgAeAAIJvg6bAQFlAAAaAAEJrBfNOwA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgUJCAAAAA==.Nikash:BAABLgAECn80AAMIAAkJFBOuGwDpAQAIAAkJFBOuGwDpAQADAAYJ+QhCfgC8AAAAAA==.Nisato:BAAALgAECgQJBAAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgcJEwAAAA==.Northic:BAAALgAECgYJBgABLgAECgkJNQAGAPEgAA==.Nortikolait:BAAALgAECgEJAQABLgAECgkJNQAGAPEgAA==.',
Ny='Nyriah:BAAALgAECgUJCwAAAA==.',
Ob='Obm:BAAALgAECgUJCwAAAA==.',
Oc='Octt:BAACLgAFFH8HAAIeAAMJoRk/aADvAAAeAAMJoRk/aADvAAAuAAQKfxsAAh4ACQk7G3syAA0CAB4ACQk7G3syAA0CAAAA.',
Of='Offal:BAABLgAECn8vAAQjAAYJVBQJGAA5AQAjAAYJCAsJGAA5AQAgAAYJVBSzIQAeAQAiAAEJJQWkrwAmAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgQJCQAAAA==.',
Om='Ominis:BAAALgAECgUJBQAAAA==.',
Oo='Oomaw:BAAALgAECgMJBAAAAA==.',
Or='Orcal:BAACLgAFFH8gAAIhAAUJ/xgkKAAlAQAhAAUJ/xgkKAAlAQAuAAQKfx0AAiEACAn7GnQQAHECACEACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAABLgAECn8YAAMMAAUJBBWIJQDlAAAMAAUJBBWIJQDlAAALAAQJEAQgJAGJAAAAAA==.',
Ot='Otherrhu:BAAALgAECgQJBAAAAA==.',
Oz='Ozo:BAABLgAECn8cAAIFAAcJqBLQagBnAQAFAAcJqBLQagBnAQAAAA==.',
Pa='Paiva:BAAALgAECgUJCAAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn9FAAIMAAkJ/iHKAgD4AgAMAAkJ/iHKAgD4AgAAAA==.Pampas:BAABLgAECn8ZAAMBAAgJpgTCcgD/AAABAAgJpgTCcgD/AAATAAEJ5AFsvwAZAAAAAA==.Pandamonic:BAAALgAECgQJBAAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgUJCwAAAA==.Phoebell:BAAALgAECgUJCQAAAA==.',
Pi='Pinkducky:BAABLgAECn8cAAIGAAYJyQVi8gC5AAAGAAYJyQVi8gC5AAAAAA==.',
Pl='Plen:BAABLgAECn8pAAMGAAkJ1R5aNQBhAgAGAAkJkxxaNQBhAgAYAAYJwxtkGgCJAQAAAA==.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgMJAwAAAA==.Poquads:BAAALgAECgQJBwAAAA==.',
Pr='Primaris:BAAALgAECgcJDAAAAA==.Prinnce:BAAALgAECgcJDQABLgAECgkJTwAWABokAA==.Príestatute:BAAALgAECgUJBQABLgAFFAMJBQAFAAUPAA==.',
Pu='Pulmifinger:BAAALgAECgEJAQAAAA==.Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJOQAOAGYTAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Qi='Qilt:BAAALgADCgcJBwAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIfAAkJmBgBQAAaAgAfAAkJmBgBQAAaAgAAAA==.',
Ra='Radra:BAABLgAECn8lAAMSAAkJ+g8uGQC0AQASAAkJ+g8uGQC0AQANAAEJAADnQQAAAAAAAA==.Raeku:BAABLgAECn8tAAImAAkJkCDOBQDHAgAmAAkJkCDOBQDHAgAAAA==.Rainee:BAAALgADCgEJAQAAAA==.Raja:BAAALgAECgUJDwAAAA==.Rathalo:BAAALgAECgQJBgAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8hAAMNAAYJhRWIFwDiAAACAAYJnBPkfAAiAQANAAUJPxWIFwDiAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8iAAMBAAgJJggufgDgAAABAAcJtgQufgDgAAATAAYJUQOjbwCWAAAAAA==.Retribution:BAABLgAECn85AAILAAkJ5hMpRwDuAQALAAkJ5hMpRwDuAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgMJCQABLgAECgkJTwAWABokAA==.',
Ri='Richcraniums:BAAALgADCgcJBwAAAA==.',
Ro='Roachers:BAAALgADCgIJAgAAAA==.Robomurph:BAAALgADCggJDwAAAA==.Rolas:BAAALgAECgYJAgAAAA==.Ronfax:BAACLgAFFH8hAAMBAAcJtyInBQBrAgABAAYJfSQnBQBrAgATAAIJxAWRUABGAAAuAAQKfywAAwEACQm2IwoFAGADAAEACQm2IwoFAGADABMABgmeHCkqAJwBAAAA.Rooss:BAAALgAECgcJEgAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECggJEgAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQAWAGIXAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.Rul:BAAALgAFFAEJAQABLgAFFAQJEQAGAJ4gAA==.',
Ry='Ryllae:BAAALgAECgQJBQABLgAECgkJHQASAFciAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
['Rì']='Rììdìì:BAAALgAECgcJBwABLgAFFAMJBQAFAAUPAA==.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Sackhammer:BAAALgAECgQJBAAAAA==.Saint:BAAALgAECgkJDQAAAA==.Salopard:BAAALgAECgIJAgAAAA==.Samson:BAABLgAECn8VAAQWAAUJfx4qKwBhAQAWAAUJfx4qKwBhAQAKAAQJHA8WTgDFAAAVAAIJ3woApQBJAAABLgAECgUJCwAPAAAAAA==.Sanivan:BAABLgAECn8VAAISAAcJ+hdxGgDvAQASAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgADCgEJAQAAAA==.Saori:BAAALgAECgEJAQAAAA==.Sappy:BAABLgAECn8aAAQdAAcJdR9BCQCuAQAdAAYJsh5BCQCuAQAlAAQJrxwzOwA/AQAnAAQJ8BLcCQDFAAABLgAFFAQJEQAGAJ4gAA==.Sarinae:BAABLgAECn8kAAQhAAkJ6QVbTAD3AAAhAAgJHwVbTAD3AAAkAAEJwAEZQwAfAAAbAAEJwAH0KwAVAAAAAA==.Sarmuc:BAABLgAECn8ZAAMXAAgJmw83FwBNAQAXAAgJmw83FwBNAQATAAEJXwsIrQAoAAAAAA==.Saryda:BAAALgAECgUJDQAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJDQABLgAECgkJKQAGANUeAA==.Scubagal:BAAALgAECgUJCQAAAA==.Scy:BAAALgAECgQJBQAAAA==.Scythraza:BAABLgAECn8rAAMhAAgJ3xjiGAAOAgAhAAgJ3xjiGAAOAgAkAAEJCQSqPQAqAAAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJOQAOAGYTAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Sedge:BAAALgADCgEJAQAAAA==.Seedsprayer:BAAALgAECgYJDAAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAABLgAECn8XAAICAAYJvByeWwBxAQACAAYJvByeWwBxAQAAAA==.Sensu:BAAALgAECgYJEAAAAA==.Sensual:BAAALgAECgYJAwAAAA==.Sernian:BAAALgAECgQJCQABLgAFFAUJHQALAPgjAA==.Seä:BAABLgAECn85AAIOAAkJZhO+GwAkAgAOAAkJZhO+GwAkAgAAAA==.',
Sh='Shadoweave:BAABLgAECn8dAAIRAAkJqwc/MgBQAQARAAkJqwc/MgBQAQAAAA==.Shamtea:BAABLgAECn8tAAITAAgJaA5SOQBNAQATAAgJaA5SOQBNAQAAAA==.Shapzan:BAAALgAECgYJEAAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shiik:BAAALgAECgYJBwABLgAECgcJGQAOABIYAA==.Shivant:BAABLgAECn80AAMBAAgJEx6AHQBdAgABAAgJEx6AHQBdAgATAAIJQwUnmABCAAAAAA==.Shmeegleroop:BAAALgAECgYJDgAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAABLgAECn8uAAINAAkJoCBbAgDZAgANAAkJoCBbAgDZAgAAAA==.',
Si='Silvertime:BAAALgADCgYJBwAAAA==.Sindice:BAAALgAECgYJCwABLgAFFAcJIQABALciAA==.',
Sk='Skaa:BAAALgAECgEJAgAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slanesh:BAAALgAECgIJAgAAAA==.Slimpooshady:BAABLgAECn8yAAMDAAkJFhL7JwAOAgADAAkJFhL7JwAOAgAcAAkJpBPEEADYAQAAAA==.Sloth:BAABLgAECn8aAAIYAAkJrh8oBQDZAgAYAAkJrh8oBQDZAgAAAA==.',
So='Solaspirus:BAABLgAECn8pAAMCAAkJHhmNIwA/AgACAAkJHhmNIwA/AgANAAEJaww5NgAqAAAAAA==.Solinius:BAAALgAECgQJBQAAAA==.Sope:BAAALgAECgYJCQAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.Soulomatic:BAAALgADCgcJBwAAAA==.',
Sp='Spectors:BAABLgAECn83AAMaAAgJ0g4wDwBlAQAaAAcJxBAwDwBlAQAeAAcJ5wP6vgDNAAAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAIOAAgJPxyNEQCGAgAOAAgJPxyNEQCGAgAAAA==.Sprayinnseed:BAAALgAECgMJBAAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwAPAAAAAA==.',
St='Stabon:BAABLgAECn8lAAIlAAkJcwmiHgCdAQAlAAkJcwmiHgCdAQAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgYJDAAAAA==.',
Sw='Sweetstorm:BAABLgAECn9AAAISAAkJLwguJgBCAQASAAkJLwguJgBCAQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn83AAIOAAkJWxczFABqAgAOAAkJWxczFABqAgAAAA==.',
Ta='Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAABLgAECn8aAAILAAgJsxO5XQC0AQALAAgJsxO5XQC0AQAAAA==.Taredelaria:BAAALgADCgUJBgAAAA==.Tarixx:BAABLgAFFH8GAAMLAAMJ/w5hJACjAAALAAIJQg5hJACjAAAMAAEJeRBmGQAqAAAAAA==.Tazanoth:BAACLgAFFH8IAAQFAAMJBBImbQC8AAAFAAMJ0Q8mbQC8AAAmAAIJKQ7tKgCDAAAUAAEJTArEJgBPAAAuAAQKfyEAAyYACQmaGwgPADwCACYACQmQGggPADwCABQABglBGtYwALABAAAA.',
Te='Teasa:BAABLgAECn9CAAIFAAkJ2RmOIABhAgAFAAkJ2RmOIABhAgAAAA==.Tekeelà:BAACLgAFFH8JAAQFAAUJwwdDAgB7AQAFAAUJwwdDAgB7AQAUAAEJVgAiLgA1AAAmAAEJhAEpNwAqAAAuAAQKfzIABAUACQl2IaMVAIoCAAUACQkHH6MVAIoCACYACQm6GCYPADsCABQABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAABLgAECn8aAAMFAAYJdwPXvwDAAAAFAAYJdwPXvwDAAAAmAAUJcgFaVABYAAAAAA==.Theenna:BAAALgADCgUJCAAAAA==.Thetodd:BAAALgAECgIJAgAAAA==.Thianna:BAABLgAECn8iAAMOAAkJDxlXGwAnAgAOAAkJDxlXGwAnAgALAAYJIAsi3QDeAAAAAA==.Thiculuskage:BAABLgAECn8YAAIOAAkJvB7OBwANAwAOAAkJvB7OBwANAwAAAA==.Thinkso:BAAALgADCgcJFQAAAA==.Thobu:BAAALgAECgcJCwAAAA==.Thodos:BAAALgADCgEJAQAAAA==.Thornscale:BAABLgAECn9JAAQhAAkJ3hoMEQBcAgAhAAkJ3hoMEQBcAgAbAAUJvBYkDQA3AQAkAAYJogvrKAAsAQAAAA==.Thorrent:BAAALgADCgcJDQAAAA==.',
Ti='Tigolcrittys:BAAALgAECgcJEgABLgAFFAMJBQAFAAUPAA==.Timeforloads:BAABLgAECn8kAAMDAAgJoR9TMgDUAQADAAYJdB5TMgDUAQAIAAYJdhRXMwBIAQAAAA==.Tirria:BAAALgADCgMJAwAAAA==.',
To='Tolk:BAAALgAECgcJEQAAAA==.Tomzombe:BAAALgAECgQJBgAAAA==.Totem:BAABLgAECn8VAAITAAgJvQtYRAAeAQATAAgJvQtYRAAeAQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Traveler:BAAALgAECgIJAgAAAA==.Trickyflamom:BAAALgAECgcJEgABLgAECgkJBQAPAAAAAA==.Troloq:BAABLgAECn80AAQaAAkJWB1KCADgAQAeAAgJHhvNNgD8AQAaAAgJHRdKCADgAQAZAAUJ8BmZEwAQAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgAECgMJBQAAAA==.Turger:BAAALgAECgUJCAABLgAECgkJEAAPAAAAAA==.Turinnii:BAAALgADCgcJBwAAAA==.',
Ul='Uller:BAABLgAECn8oAAIfAAkJDholMABWAgAfAAkJDholMABWAgAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAABLgAECn8eAAIOAAYJ/g0tRwAgAQAOAAYJ/g0tRwAgAQAAAA==.Vaimei:BAABLgAECn83AAMZAAkJ+CIdAgCkAgAZAAgJPSMdAgCkAgAeAAgJAyCoFQChAgAAAA==.Valashune:BAAALgADCgEJAQAAAA==.Valsilla:BAAALgAECgYJBgABLgAECgkJHQASAFciAA==.Vapor:BAABLgAECn8jAAIdAAgJTxkCCQCxAQAdAAgJTxkCCQCxAQAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebs:BAABLgAECn8VAAMiAAgJCBPVKgCqAQAiAAgJCBPVKgCqAQAgAAEJAAAySAAuAAAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8gAAIfAAgJaQZ/qAAqAQAfAAgJaQZ/qAAqAQAAAA==.Vento:BAABLgAECn8VAAIGAAgJjxVcYACmAQAGAAgJjxVcYACmAQAAAA==.Verité:BAABLgAECn8UAAMbAAgJ8gz0DgAXAQAbAAcJdg70DgAXAQAhAAcJfQlaTQD0AAAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgAECgEJAQABLgAFFAQJBgALAJoZAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn9GAAICAAkJHBWaLQAOAgACAAkJHBWaLQAOAgAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgUJDAAAAA==.Voltimand:BAAALgAECgEJAQABLgAFFAMJBgABAD4OAA==.',
Vv='Vvicked:BAABLgAECn8gAAIGAAgJrCKwFgC8AgAGAAgJrCKwFgC8AgAAAA==.',
Vy='Vynesta:BAABLgAECn8dAAISAAkJVyJ6AwAcAwASAAkJVyJ6AwAcAwAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wamoo:BAAALgAECgEJAQAAAA==.Wanagi:BAAALgADCgMJAwAAAA==.Wankz:BAAALgAECgkJEgAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8fAAIiAAkJtSJkBwDnAgAiAAkJtSJkBwDnAgAAAA==.',
We='Weyna:BAABLgAECn84AAMVAAgJ3hGvMQCrAQAVAAgJ3hGvMQCrAQAKAAYJVAnmTADJAAABLgAFFAUJGgAkACwWAA==.',
Wh='Whisperingei:BAAALgAECgYJCgAAAA==.',
Wi='Widowx:BAACLgAFFH8GAAMTAAIJOxQjQACBAAATAAIJOxQjQACBAAABAAEJEgEciwAgAAAuAAQKfy0AAhMACQm1GggXACoCABMACQm1GggXACoCAAAA.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAABLgAECn8WAAIFAAcJlBr+PADoAQAFAAcJlBr+PADoAQABLgAECgkJLAAQABkhAA==.',
Wr='Wrandohunt:BAAALgAECgEJBAAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wreckitrandy:BAAALgAECgEJAQAAAA==.Wryn:BAAALgAECgkJEQABLgAECgkJKQAGANUeAA==.',
Wu='Wulyn:BAAALgAECgYJCwAAAA==.',
Wy='Wylla:BAAALgAECgUJDQAAAA==.',
Xa='Xalethra:BAABLgAECn80AAICAAkJByQBBQA1AwACAAkJByQBBQA1AwAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xenophobias:BAAALgAECgYJEAAAAA==.',
Xh='Xhosen:BAABLgAFFH8FAAIGAAIJaw25zwCOAAAGAAIJaw25zwCOAAAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn9EAAIDAAkJpxkvHQBZAgADAAkJpxkvHQBZAgAAAA==.',
Ya='Yarloon:BAAALgADCgcJBwAAAA==.',
Yt='Ytsirk:BAAALgADCgYJBgAAAA==.',
Yv='Yve:BAAALgAECgUJDQAAAA==.',
Za='Zaharian:BAAALgAECgEJAQAAAA==.Zalajin:BAAALgAECgQJBAAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zarayndia:BAAALgAECgYJCAAAAA==.',
Ze='Zeddicus:BAABLgAECn8oAAMaAAkJQQhFDgByAQAaAAkJ0AdFDgByAQAeAAUJ0APJ7wB+AAAAAA==.Zendragan:BAACLgAFFH8HAAIVAAMJzxBDPgCfAAAVAAMJzxBDPgCfAAAuAAQKfx4AAhUACQlOGFAXAFgCABUACQlOGFAXAFgCAAAA.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoe:BAAALgAECgQJCAAAAA==.Zoidz:BAAALgAECggJDAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zombruh:BAAALgAECgEJAQAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.Zythopoios:BAAALgAFFAEJAQAAAA==.',
Zz='Zzilladi:BAABLgAFFH8NAAMQAAYJcxV1CAC/AQAQAAYJcxV1CAC/AQARAAEJAACRQgAAAAAAAA==.Zzilladinzz:BAACLgAFFH8UAAILAAUJjSCTLgBPAQALAAUJjSCTLgBPAQAuAAQKfyIAAgsACQkIIwsSAAIDAAsACQkIIwsSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgAECgYJDwABLgAECgkJLgANAKAgAA==.',
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
