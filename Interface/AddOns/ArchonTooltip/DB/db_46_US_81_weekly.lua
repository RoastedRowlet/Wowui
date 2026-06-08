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

local lookup = {'Shaman-Restoration','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Monk-Brewmaster','Paladin-Retribution','Paladin-Protection','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Holy','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Hunter-Marksmanship','DemonHunter-Devourer','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Blood','Evoker-Devastation','Druid-Guardian','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Warrior-Fury','Warrior-Arms','Evoker-Preservation','Rogue-Subtlety','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aarmorr:BAABLgAECn9FAAIBAAkJmhmmFACaAgABAAkJmhmmFACaAgAAAA==.Aatus:BAAALgADCgUJBwAAAA==.',
Ab='Absoul:BAAALgAECgQJBAAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgQJBgAAAA==.',
Ad='Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aedelas:BAAALgAECgIJAwAAAA==.Aeloriá:BAABLgAECn8+AAMCAAkJ+B4RCQAhAwACAAkJ+B4RCQAhAwADAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECgcJDAAAAA==.',
Ag='Agrosa:BAAALgAECgYJBgAAAA==.',
Ai='Aimeeiove:BAAALgAECgYJCQAAAA==.Airad:BAAALgADCgUJBgAAAA==.',
Al='Alcarza:BAAALgAECgMJBQAAAA==.Alchon:BAABLgAECn8kAAIEAAkJ6xo7KwAmAgAEAAkJ6xo7KwAmAgAAAA==.Aldera:BAABLgAECn8nAAIBAAkJ6gSTYQAnAQABAAkJ6gSTYQAnAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8jAAMFAAkJwRwrRADuAQAFAAkJwRwrRADuAQAGAAEJyhBgFgA3AAAAAA==.Alista:BAAALgAECgYJCwAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn9EAAMCAAcJJhd4MQDRAQACAAcJJhd4MQDRAQAHAAYJRxHBOwATAQAAAA==.Alorris:BAAALgAECgQJBgABLgAECgkJGQAIAFggAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECggJDwAAAA==.Alyra:BAAALgAECgYJBgAAAA==.',
Am='Amata:BAAALgAECgUJCwAAAA==.Amelianne:BAAALgAECgcJDQAAAA==.Amiria:BAAALgAECgYJBgAAAA==.Ammastary:BAAALgAECgQJBgAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECgkJLwAJAA8bAA==.Andragos:BAAALgAECgQJBgAAAA==.Andrea:BAABLgAECn9EAAIDAAkJYR1xBACtAgADAAkJYR1xBACtAgAAAA==.Anthria:BAAALgAECgcJEAAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Arcapeligo:BAAALgAECgEJAgAAAA==.Archonsfury:BAAALgAECggJDwAAAA==.Arilyn:BAAALgAECgIJAgAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgAAAA==.Asheye:BAAALgAECgcJBwABLgAECgkJKQAFANUeAA==.Ashuranadi:BAAALgADCgcJBwAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJEQAAAA==.Asura:BAAALgAECgYJBwAAAA==.Asyllaa:BAABLgAECn8eAAMKAAkJFx82KQBTAgAKAAcJOyM2KQBTAgALAAYJ9hIyHgAWAQAAAA==.',
At='Atnawuerus:BAAALgAECgEJAQAAAA==.Atonement:BAAALgAECgYJCgABLgAECgkJLgAMAKAgAA==.',
Au='Aumaril:BAAALgAECggJEwAAAA==.Auralynn:BAABLgAECn8dAAIKAAkJpAj6igBPAQAKAAkJpAj6igBPAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averus:BAABLgAECn9FAAIHAAkJgRDiHgDDAQAHAAkJgRDiHgDDAQAAAA==.',
Az='Azariel:BAABLgAECn81AAIKAAkJixPvRQASAgAKAAkJixPvRQASAgAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn8/AAMLAAkJ6B1sBQCOAgALAAkJIB1sBQCOAgAKAAEJXyGePAFhAAAAAA==.',
Ba='Baane:BAAALgAECgQJBwABLgAECgYJCwANAAAAAA==.Babnik:BAEALgAECggJEwAAAA==.Bagel:BAACLgAFFH8ZAAIOAAUJHCNXCwDsAQAOAAUJHCNXCwDsAQAuAAQKfxkAAw4ACAmCH1AmAPYBAA4ACAmCH1AmAPYBAAoAAQnkCoOUASsAAAAA.Baldwin:BAAALgADCgcJBwAAAA==.Ballbreaker:BAAALgAECgQJBAAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgIJAwAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn82AAMIAAkJnhdLEABgAgAIAAkJ5RZLEABgAgAPAAMJFBx6VQDgAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgAECgEJAQAAAA==.Belovis:BAACLgAFFH8WAAIKAAUJRSKBGACQAQAKAAUJRSKBGACQAQAuAAQKfyYAAgoACQk0JOgMACYDAAoACQk0JOgMACYDAAAA.Berathor:BAAALgAECgkJEwAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJMgAOAHsQAA==.',
Bi='Bidoof:BAABLgAECn8gAAIQAAgJtQctLQAFAQAQAAgJtQctLQAFAQAAAA==.Bigblunt:BAAALgADCgQJCQAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Birdi:BAAALgAECgEJAQAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgYJDwAAAA==.',
Bo='Boggrog:BAAALgAECgMJAwABLgAECgUJCwANAAAAAA==.Bolz:BAAALgAECgMJAwAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAABLgAECn8vAAIRAAkJkgquMwBeAQARAAkJkgquMwBeAQAAAA==.Bowgobrr:BAABLgAECn8qAAMSAAgJ4xX5DQByAQASAAgJ4xX5DQByAQAEAAYJ2QrfzwCWAAABLgAFFAcJHQAEAKcRAA==.',
Br='Braelyne:BAABLgAECn8WAAIKAAYJdR3JXwDEAQAKAAYJdR3JXwDEAQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJEQAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDgAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Burlycheeks:BAABLgAECn85AAIKAAkJPCAPFgC1AgAKAAkJPCAPFgC1AgAAAA==.',
Ca='Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJDAAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAAALgAECgYJDAAAAA==.Catsneverdie:BAAALgAECgMJDAABLgAFFAMJCQAFAPgHAA==.Catzinhatz:BAABLgAECn8WAAITAAcJAgpfiAACAQATAAcJAgpfiAACAQABLgAFFAMJCQAFAPgHAA==.',
Ce='Cecelya:BAABLgAECn84AAQPAAkJ5Rm/FQAXAgAPAAkJ5Rm/FQAXAgAUAAQJpQ2NTADUAAAIAAMJUw3TVQCTAAAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8ZAAIRAAYJNBC2RQAyAQARAAYJNBC2RQAyAQABLgAECgkJFgAQANgbAA==.Chillykiller:BAAALgAECgYJBgABLgAECgkJFgAQANgbAA==.Chiva:BAAALgAECgQJBAABLgAECggJLAABABMeAA==.Chivactdl:BAAALgAECgMJBAABLgAECggJLAABABMeAA==.Chivalt:BAAALgAECgEJAQABLgAECggJLAABABMeAA==.Chozen:BAAALgAECggJCwAAAA==.Chunknoriss:BAABLgAECn8nAAMVAAYJYiBKGwApAgAVAAYJYiBKGwApAgAWAAIJ6gTLhwBAAAABLgAECggJLAABABMeAA==.',
Cl='Claudiuss:BAAALgAECgYJDAABLgAFFAMJBgABAD4OAA==.Clurefu:BAABLgAECn84AAMVAAkJvCGWBABbAwAVAAkJvCGWBABbAwAWAAMJ5BZVWACuAAABLgAECgkJLwACAMogAA==.Clurelock:BAABLgAECn8vAAICAAkJyiA9BgBMAwACAAkJyiA9BgBMAwAAAA==.Cluremage:BAAALgAECgYJCAAAAA==.',
Co='Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAABLgAECn8UAAIVAAgJIBsDGABGAgAVAAgJIBsDGABGAgAAAA==.Constella:BAAALgADCgYJCQAAAA==.Coppertan:BAAALgAECgMJBQAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8iAAIXAAkJSBorBwBQAgAXAAkJSBorBwBQAgAAAA==.',
Cr='Crazyshammy:BAAALgAECgkJEgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crows:BAAALgAECgYJDAAAAA==.Crunchynuget:BAABLgAECn8fAAIKAAgJ3h7EIgBxAgAKAAgJ3h7EIgBxAgABLgAFFAUJEQAKAKAfAA==.',
Ct='Cthuwu:BAAALgAECgMJAgABLgAFFAUJCQAEAMMHAA==.',
Cu='Cujotaro:BAAALgAECgEJAgAAAA==.Cumberdale:BAAALgAECgUJBQAAAA==.',
Cv='Cvhamster:BAAALgAECgQJCgAAAA==.',
Cy='Cybeast:BAABLgAECn8vAAIDAAkJHh4SBAC6AgADAAkJHh4SBAC6AgAAAA==.Cynortas:BAAALgAECgIJBgAAAA==.',
Da='Daciana:BAABLgAECn8UAAIEAAYJBhBBiAAhAQAEAAYJBhBBiAAhAQAAAA==.Dados:BAABLgAECn8wAAMPAAkJXh5FDQCEAgAPAAkJXh5FDQCEAgAUAAEJsBQbeAA+AAAAAA==.Daeghun:BAAALgAECgIJAgAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgAECgQJBwAAAA==.Dambrien:BAAALgAECgUJBQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkfox:BAAALgADCgcJDwAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8wAAIKAAkJtR93FQC5AgAKAAkJtR93FQC5AgAAAA==.Darloct:BAAALgAECgYJEAAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8kAAMTAAgJ2hayXgBhAQAQAAYJexvxJwCDAQATAAgJQg+yXgBhAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlifts:BAAALgAECgQJCQAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJJAATANoWAA==.Deadslinger:BAAALgADCgYJDAAAAA==.Deathcat:BAACLgAFFH8JAAIFAAMJ+AdNqwCyAAAFAAMJ+AdNqwCyAAAuAAQKfzoAAgUACQmjFq00ACQCAAUACQmjFq00ACQCAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8QAAMFAAUJZx53RwBTAQAFAAUJQh53RwBTAQAGAAIJhB36FwCdAAAAAA==.Deathshadowx:BAAALgAECgUJCwAAAA==.Delryth:BAAALgADCgkJCQAAAA==.Demonkoh:BAAALgAECgUJCAAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgAECgQJBAABLgAECggJGQAWAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn8vAAIUAAkJPxSpFgAMAgAUAAkJPxSpFgAMAgAAAA==.',
Do='Dolemite:BAABLgAECn8zAAMVAAcJaBALPABmAQAVAAcJaBALPABmAQAWAAUJtxRKPgD4AAAAAA==.Donalbain:BAACLgAFFH8GAAIBAAMJPg6kSgCwAAABAAMJPg6kSgCwAAAuAAQKfygAAgEACQmrGTUZAHQCAAEACQmrGTUZAHQCAAAA.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgADCgYJBgABLgAECgQJBQANAAAAAA==.Draganpriest:BAAALgAECgkJCwAAAA==.Draganussy:BAAALgADCgEJAQAAAA==.Draggo:BAAALgAECgEJAQAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAAALgAECgYJEQAAAA==.',
Du='Durock:BAAALgAECgMJBAAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Elcachazo:BAAALgAECgIJAgAAAA==.Eldinn:BAAALgADCgcJBgAAAA==.Elenora:BAAALgAECgMJAwAAAA==.Elidor:BAAALgAECgUJCAAAAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn80AAIYAAkJihnrDAAwAgAYAAkJihnrDAAwAgAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAAALgAECgYJEAAAAA==.Emmils:BAABLgAECn82AAIHAAkJdgsYLgBbAQAHAAkJdgsYLgBbAQAAAA==.Emìly:BAABLgAECn9IAAQWAAkJsST8BgDSAgAWAAgJgyT8BgDSAgAVAAkJCxZDHQAbAgAJAAUJRRXhQwDjAAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIZAAUJbw+wBAAbAQAZAAUJbw+wBAAbAQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAACLgAFFH8GAAIKAAQJmhn5JwBWAQAKAAQJmhn5JwBWAQAuAAQKf0EABAoACQk7IdcMAPYCAAoACQk7IdcMAPYCAAsABwkxH5QMAPABAA4ABgm1DF5YAMkAAAAA.',
Ep='Episkey:BAABLgAECn8bAAMHAAkJyw6/JwCEAQAHAAkJyw6/JwCEAQACAAQJdRcKXgATAQAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Erissae:BAAALgADCgEJAgAAAA==.Eropor:BAABLgAECn8iAAMVAAYJexNaPABlAQAVAAYJexNaPABlAQAWAAMJYQZIggBHAAABLgAFFAMJCgACAI4NAA==.Eroversion:BAACLgAFFH8KAAICAAMJjg2iPwCsAAACAAMJjg2iPwCsAAAuAAQKf1YABQIACQlCHkgWAIwCAAIACQlCHkgWAIwCAAcABAkIFj5UANUAAAMAAwm4DRgvAJMAABoAAQkAAKOGAAAAAAAA.',
Es='Esmay:BAABLgAECn8fAAIRAAkJHRRCHgDiAQARAAkJHRRCHgDiAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn9EAAIbAAkJwxjXAwBdAgAbAAkJwxjXAwBdAgAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgAECgEJAwAAAA==.',
Fi='Filgulfin:BAABLgAECn9IAAMEAAkJIx2XEADCAgAEAAkJIx2XEADCAgASAAgJgRCZEgAnAQAAAA==.Finkate:BAAALgAECggJEAAAAA==.Firebad:BAABLgAECn8wAAMcAAkJpxxuAgCKAgAcAAkJpxxuAgCKAgAdAAYJHwoO3ACYAAAAAA==.Firebringer:BAABLgAECn9IAAITAAkJTAuNWAByAQATAAkJTAuNWAByAQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECgkJIwAeANUXAA==.',
Fl='Flaakk:BAAALgADCgcJBwAAAA==.Flamehunter:BAABLgAECn8iAAMTAAkJMRqEHACnAgATAAkJcRmEHACnAgAQAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn9LAAMUAAkJQxt7DACEAgAUAAkJQxt7DACEAgAPAAMJSAcvVAB5AAAAAA==.Floki:BAABLgAECn8UAAIfAAkJqhLPGwBMAQAfAAkJqhLPGwBMAQAAAA==.Flowing:BAABLgAECn8XAAIgAAkJHRRQGQAEAgAgAAkJHRRQGQAEAgAAAA==.',
Fo='Foods:BAACLgAFFH8LAAMhAAMJuBBDOgCjAAAhAAMJuBBDOgCjAAAfAAEJLwQfLAAnAAAuAAQKf04ABCEACQlwGXITAFACACEACQlKGXITAFACAB8ABwl6EhwfACwBACIAAwnoDK1UAHAAAAAA.Foofsmash:BAAALgADCgUJBgAAAA==.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
['Fø']='Føøds:BAAALgADCgMJAwAAAA==.',
Ga='Gaboo:BAAALgAECgkJEwAAAA==.Garfman:BAAALgAFFAEJAQAAAA==.',
Gb='Gb:BAABLgAFFH8FAAIOAAQJWQrOJQDpAAAOAAQJWQrOJQDpAAABLgAFFAQJDQAUAPIaAA==.',
Gh='Ghostinhale:BAAALgAECgUJDAAAAA==.',
Gi='Gibbshole:BAAALgADCgcJBwAAAA==.Gilorion:BAABLgAECn8WAAIEAAkJ7RaALgAXAgAEAAkJ7RaALgAXAgAAAA==.',
Gl='Glasgoww:BAAALgAECgYJCQABLgAFFAMJBgABAD4OAA==.',
Gn='Gnibat:BAAALgAECgMJBgAAAA==.',
Go='Goburina:BAACLgAFFH8LAAIBAAQJegdrQwDIAAABAAQJegdrQwDIAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grievo:BAAALgAECgYJCAAAAA==.',
Gy='Gypsiey:BAAALgAECgUJBQAAAA==.',
['Gí']='Gímlí:BAABLgAECn8uAAIEAAkJrRpKJABGAgAEAAkJrRpKJABGAgAAAA==.',
Ha='Halcyndraag:BAABLgAECn9FAAQgAAkJ2hRIHwDWAQAgAAcJKhVIHwDWAQAZAAMJ7xWRKADcAAAjAAEJPQLRQAAfAAAAAA==.Handbannana:BAAALgADCgcJBwAAAA==.Handsome:BAAALgAECgcJDAABLgAECggJDgANAAAAAA==.Happydk:BAACLgAFFH8RAAMFAAQJniANMgCGAQAFAAQJniANMgCGAQAYAAMJKRGyJwCiAAAuAAQKfygAAwUACQkdI28VAL4CAAUACQlaIW8VAL4CABgABwlKGQklAB8BAAAA.Hartu:BAABLgAECn9DAAIfAAkJzBKoEgC1AQAfAAkJzBKoEgC1AQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healsofpain:BAAALgADCgYJBgAAAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAACLgAFFH8JAAIkAAIJViFaKQDGAAAkAAIJViFaKQDGAAAuAAQKfy4AAyQACQk4IocKAHACACQACQmlIYcKAHACABsABAnwGnoPACMBAAAA.Hemmorage:BAAALgAECgYJCgABLgAECgkJKQAFANUeAA==.Herbalmist:BAAALgAECgUJCwAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgMJAwAAAA==.',
Ho='Holysea:BAAALgAECgYJDAABLgAECgkJMgAOAHsQAA==.Horatio:BAAALgAECgEJAQABLgAFFAMJBgABAD4OAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAECgkJKwAEACAgAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Ic='Icyhooves:BAAALgAECgEJAQAAAA==.',
Id='Idiocracy:BAABLgAECn8eAAMfAAkJbhanDgDyAQAfAAgJaRinDgDyAQAhAAgJ2w5gLQCVAQAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgMJBgAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgUJCAAAAA==.Irys:BAAALgAECgMJAwAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8PAAIEAAUJYCKXHwBwAQAEAAUJYCKXHwBwAQAuAAQKfxwAAgQACQmXI+cEAD8DAAQACQmXI+cEAD8DAAAA.Ismokeu:BAACLgAFFH8JAAIPAAMJ/QpxIgCUAAAPAAMJ/QpxIgCUAAAuAAQKfzcAAg8ACAmwG1IQAFcCAA8ACAmwG1IQAFcCAAAA.Ismyn:BAAALgADCgEJAgAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneal:BAABLgAECn8gAAIKAAkJ+wQ/nQAwAQAKAAkJ+wQ/nQAwAQAAAA==.Jalidelo:BAABLgAECn9AAAMIAAkJWxy8CQDLAgAIAAkJWxy8CQDLAgAPAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Je='Jenifurr:BAAALgADCgIJAgAAAA==.',
Ji='Jimbowaboki:BAAALgADCgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIdAAkJMhp2KQAvAgAdAAkJMhp2KQAvAgAAAA==.Jokers:BAABLgAECn8XAAMfAAYJFxOGIAAfAQAfAAYJFxOGIAAfAQAhAAMJCQkSiABTAAAAAA==.Jokersfists:BAAALgAECgYJCgAAAA==.Joranbragi:BAABLgAECn8dAAIKAAYJnweP2gDYAAAKAAYJnweP2gDYAAAAAA==.Jordanjr:BAAALgAECgYJCQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8dAAIlAAYJsRCBDgBJAQAlAAYJsRCBDgBJAQAAAA==.Jotoonice:BAABLgAECn8ZAAIeAAgJjBUlXQDBAQAeAAgJjBUlXQDBAQAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8OAAQmAAYJExdIEgAqAQAmAAQJ3xNIEgAqAQASAAMJsg0OKABWAAAEAAEJfg6PmQBCAAAuAAQKfyoABBIACAkPH60gACACABIACAn9F60gACACACYABgmXIowWAOsBAAQAAglIISLDAK4AAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.Justbob:BAAALgAECgUJBgAAAA==.',
['Jú']='Júgg:BAAALgAECgQJBgAAAA==.',
Ka='Kaachow:BAABLgAECn8uAAICAAkJZR/ZCAAkAwACAAkJZR/ZCAAkAwAAAA==.Kaana:BAABLgAECn9DAAIEAAkJzxf+JABDAgAEAAkJzxf+JABDAgAAAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAABLgAECn8cAAIKAAYJIRUVkABGAQAKAAYJIRUVkABGAQAAAA==.Karungash:BAACLgAFFH8LAAMdAAQJqgqKWwACAQAdAAQJqgqKWwACAQAcAAEJVQE+GwA+AAAuAAQKfx0AAx0ACAm1Id4QAPMCAB0ACAm1Id4QAPMCABwAAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAIMAAkJzBoVBgArAgAMAAkJzBoVBgArAgAAAA==.Karvy:BAABLgAECn8XAAIaAAgJ1hkNDQAAAgAaAAgJ1hkNDQAAAgABLgAECgkJJAAMAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAUJEwADACYlAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8TAAIRAAQJXSCHFQBYAQARAAQJXSCHFQBYAQAuAAQKfyUAAxEACQlhHv8UADMCABEACQlhHv8UADMCABcAAgn1Ggk0AEsAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAQJEwARAF0gAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Khthonious:BAABLgAECn8VAAITAAcJBx4UOADaAQATAAcJBx4UOADaAQAAAA==.',
Ki='Kibblsncrits:BAAALgAECgIJAwABLgAECgkJEgANAAAAAA==.Kickingdonut:BAACLgAFFH8FAAIWAAMJNx/CGQD1AAAWAAMJNx/CGQD1AAAuAAQKfywAAxYACAk7IxkJAOcCABYACAk7IxkJAOcCAAkABgn1GUI3AG4BAAAA.Killerhottie:BAAALgAECgEJAQAAAA==.Killermoomoo:BAAALgAECgQJCgAAAA==.Kinoh:BAAALgADCgcJBwAAAA==.Kittykarma:BAAALgAECgUJBQAAAA==.',
Kl='Kloverr:BAAALgAECgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgADCgEJAQAAAA==.Kombatkarl:BAAALgADCgMJAwAAAA==.Koramere:BAAALgADCgcJBwAAAA==.',
Kr='Kromir:BAAALgAECgQJBAAAAA==.Kromnar:BAAALgADCgEJAQAAAA==.Kronixrage:BAAALgAECgQJBgAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krooler:BAAALgAECgQJBwAAAA==.Krum:BAACLgAFFH8ZAAIKAAUJaR84IABxAQAKAAUJaR84IABxAQAuAAQKfx4AAgoACAmsHWZMANcBAAoACAmsHWZMANcBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn9LAAIKAAkJqxrSIwBsAgAKAAkJqxrSIwBsAgAAAA==.Laurian:BAAALgADCgcJDwAAAA==.Laurì:BAAALgAECgEJAQABLgAECgkJSAAWALEkAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAACLgAFFH8JAAIaAAIJ0Ry3GQCpAAAaAAIJ0Ry3GQCpAAAuAAQKf1UAAxoACQmbIbQCAP4CABoACQmbIbQCAP4CAAMAAwl9DjQvAJIAAAAA.Leftblank:BAAALgAECgUJCwAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgUJCAABLgAECgUJCAANAAAAAA==.Liszt:BAAALgAECgYJBgAAAA==.Litallya:BAAALgAECggJCAAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAgAAAA==.',
Ly='Lychi:BAAALgAECgUJCwAAAA==.Lylora:BAACLgAFFH8RAAICAAQJLyAQGgB7AQACAAQJLyAQGgB7AQAuAAQKf08AAgIACQm8JKUBALwDAAIACQm8JKUBALwDAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8sAAMPAAkJTQ9xJACSAQAPAAkJTQ9xJACSAQAUAAUJAgVUZAB3AAAAAA==.',
Ma='Madesh:BAABLgAECn89AAMMAAkJ4BqRBgAZAgATAAkJSRogJgApAgAMAAkJGBeRBgAZAgAAAA==.Madman:BAABLgAECn8tAAIVAAgJ6g/9NQCEAQAVAAgJ6g/9NQCEAQAAAA==.Maelle:BAABLgAECn9FAAIKAAkJ2iK/CgAIAwAKAAkJ2iK/CgAIAwAAAA==.Magekaestey:BAABLgAECn8jAAIeAAkJ1RcMOAAyAgAeAAkJ1RcMOAAyAgAAAA==.Majandra:BAAALgAECgUJDAAAAA==.Malyndra:BAABLgAECn8iAAIQAAkJ1xfyEQD8AQAQAAkJ1xfyEQD8AQAAAA==.Malyssa:BAAALgADCgIJAgAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAAALgAECggJEAAAAA==.Masy:BAAALgAECgEJAQAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgAECgEJAQAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Melon:BAAALgADCgEJAQABLgAECgkJDQANAAAAAA==.Meriam:BAAALgAECgEJAgABLgAECgkJKQAFANUeAA==.Merlot:BAAALgADCgEJAgABLgAECgUJDQANAAAAAA==.Mesmash:BAABLgAECn8rAAIfAAkJYSHSAwDpAgAfAAkJYSHSAwDpAgAAAA==.Metadk:BAAALgAECgQJBgABLgAECggJGQAWAGIXAA==.Metahunt:BAAALgAECgIJAgABLgAECggJGQAWAGIXAA==.Metamasters:BAAALgAECgQJBQABLgAECggJGQAWAGIXAA==.Metavoker:BAAALgAECgEJAQABLgAECggJGQAWAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8vAAIJAAkJDxsnCwB5AgAJAAkJDxsnCwB5AgAAAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBwAAAA==.Miniborg:BAABLgAECn8iAAIEAAkJ+xoiGQCDAgAEAAkJ+xoiGQCDAgABLgAFFAUJEQAKAKAfAA==.Minidude:BAAALgAECgYJEAAAAA==.Miyuki:BAAALgAECgQJBgAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAABLgAECn8WAAIWAAkJ0yFTDgBXAgAWAAkJ0yFTDgBXAgAAAA==.Monkter:BAABLgAECn8ZAAQWAAgJYheRGgDPAQAWAAgJYheRGgDPAQAVAAEJ/gbfbgAmAAAJAAEJfgh7mgAiAAAAAA==.Monsignore:BAAALgADCgQJBAAAAA==.Moofasaha:BAAALgAECgkJEAAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQATAAceAA==.Morog:BAACLgAFFH8PAAMmAAUJZx6WCwBaAQAmAAUJZx6WCwBaAQAEAAEJ0w3mmQBCAAAuAAQKfykABBIACQmpGyMsAM0BABIABgmOHSMsAM0BAAQABgkbGq0/ALABACYABgnqE7MoAFUBAAAA.Morragan:BAAALgAECgQJBQAAAA==.Mortegom:BAAALgADCgcJBwAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECggJEQAAAA==.',
My='Myinja:BAAALgAECgQJBAABLgAECggJGQAWAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.',
Na='Naadra:BAAALgAECgEJAQAAAA==.Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECggJDgAAAA==.Nalid:BAACLgAFFH8TAAIDAAUJJiUDAgCzAQADAAUJJiUDAgCzAQAuAAQKf0QAAwMACQnAJjEAAJEDAAMACQnAJjEAAJEDAAcAAQmuAhydABsAAAAA.Nanarus:BAACLgAFFH8JAAIPAAIJfRm2IgCSAAAPAAIJfRm2IgCSAAAuAAQKf0cAAw8ACQmVHlQHAO4CAA8ACQmVHlQHAO4CABQABgnkAzVRAMEAAAAA.Nanosec:BAAALgAECgEJAQAAAA==.Nansea:BAAALgAECgEJAQAAAA==.Nashalie:BAABLgAECn8oAAIdAAkJhhtFHgBoAgAdAAkJhhtFHgBoAgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Neezzdutzz:BAAALgADCgcJBgAAAA==.Nefele:BAABLgAECn8aAAIBAAgJ7xXiLwDoAQABAAgJ7xXiLwDoAQAAAA==.Nepheli:BAACLgAFFH8FAAITAAMJUxdeTwDuAAATAAMJUxdeTwDuAAAuAAQKf0IAAhMACQknIuEGABYDABMACQknIuEGABYDAAAA.Newrhu:BAAALgAECgUJBgAAAA==.Nexbasia:BAACLgAFFH8GAAIDAAIJYwrHEwCAAAADAAIJYwrHEwCAAAAuAAQKf0cAAwMACQluGPwHAEECAAMACQluGPwHAEECAAIAAgn2AtLvABsAAAAA.',
Ni='Nickyboy:BAABLgAECn8lAAQcAAcJyiFQBQAOAgAcAAcJyiFQBQAOAgAdAAIJvg7P+ABoAAAlAAEJrBd1OAA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgUJCAAAAA==.Nikash:BAABLgAECn8vAAMHAAkJExHeHgDDAQAHAAkJExHeHgDDAQACAAYJ+QiBewC8AAAAAA==.Nisato:BAAALgAECgQJBAAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgcJEwAAAA==.Northic:BAAALgAECgYJBgABLgAECggJNAAFANcgAA==.',
Ny='Nyriah:BAAALgAECgUJCwAAAA==.',
Ob='Obm:BAAALgAECgUJCwAAAA==.',
Oc='Octt:BAABLgAECn8bAAIdAAkJOxvVLwAUAgAdAAkJOxvVLwAUAgAAAA==.',
Of='Offal:BAABLgAECn8pAAQiAAYJcBAJGAA5AQAiAAYJCAsJGAA5AQAfAAYJcBCGJwDoAAAhAAEJJQW/qAAmAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgQJCAAAAA==.',
Om='Ominis:BAAALgAECgUJBQAAAA==.',
Oo='Oomaw:BAAALgAECgMJBAAAAA==.',
Or='Orcal:BAACLgAFFH8bAAIgAAUJXBRWKgALAQAgAAUJXBRWKgALAQAuAAQKfx0AAiAACAn7GnQQAHECACAACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAAALgAECgYJEwAAAA==.',
Ot='Otherrhu:BAAALgAECgQJBAAAAA==.',
Oz='Ozo:BAABLgAECn8cAAIEAAcJqBJdZQBtAQAEAAcJqBJdZQBtAQAAAA==.',
Pa='Paiva:BAAALgAECgUJCAAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn89AAILAAkJ/iGSAgD6AgALAAkJ/iGSAgD6AgAAAA==.Pampas:BAABLgAECn8YAAMBAAcJxgQmeQDiAAABAAcJxgQmeQDiAAARAAEJ5AGYtgAZAAAAAA==.Pandamonic:BAAALgAECgQJBAAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgUJCwAAAA==.Phoebell:BAAALgAECgUJCAAAAA==.',
Pi='Pinkducky:BAABLgAECn8cAAIFAAYJyQUc6QC8AAAFAAYJyQUc6QC8AAAAAA==.',
Pl='Plen:BAABLgAECn8pAAMFAAkJ1R5aNQBhAgAFAAkJkxxaNQBhAgAYAAYJwxsuGQCLAQAAAA==.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgIJAgAAAA==.Poquads:BAAALgAECgQJBwAAAA==.',
Pr='Primaris:BAAALgAECgYJCwAAAA==.Prinnce:BAAALgAECgEJAQABLgAECgkJSAAWALEkAA==.Príestatute:BAAALgAECgUJBQABLgAECgkJLgAEAK0aAA==.',
Pu='Pulmifinger:BAAALgAECgEJAQAAAA==.Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJMgAOAHsQAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Qi='Qilt:BAAALgADCgcJBwAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIeAAkJmBg9PQAfAgAeAAkJmBg9PQAfAgAAAA==.',
Ra='Radra:BAABLgAECn8cAAMQAAkJlg7lGgCWAQAQAAkJlg7lGgCWAQAMAAEJAADhPgAAAAAAAA==.Raeku:BAABLgAECn8tAAImAAkJkCBaBQDNAgAmAAkJkCBaBQDNAgAAAA==.Rainee:BAAALgADCgEJAQAAAA==.Raja:BAAALgAECgUJDwAAAA==.Rathalo:BAAALgAECgQJBgAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8hAAMMAAYJhRV9FgDiAAATAAYJnBMUeQAiAQAMAAUJPxV9FgDiAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8iAAMBAAgJJggaeQDiAAABAAcJtgQaeQDiAAARAAYJUQMKawCWAAAAAA==.Retribution:BAABLgAECn85AAIKAAkJ5hO1QwDwAQAKAAkJ5hO1QwDwAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgMJBwABLgAECgkJSAAWALEkAA==.',
Ri='Richcraniums:BAAALgADCgcJBwAAAA==.',
Ro='Roachers:BAAALgADCgIJAgAAAA==.Robomurph:BAAALgADCggJDwAAAA==.Rolas:BAAALgAECgYJAgAAAA==.Ronfax:BAACLgAFFH8bAAMBAAcJyCDOBABcAgABAAYJPCLOBABcAgARAAIJxAWJSgBIAAAuAAQKfysAAwEACQm2I28HAC8DAAEACQm2I28HAC8DABEABgmeHC8oAJ0BAAAA.Rooss:BAAALgAECgcJEgAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECggJEgAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQAWAGIXAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.Rul:BAAALgAFFAEJAQABLgAFFAQJEQAFAJ4gAA==.',
Ry='Ryllae:BAAALgAECgQJBQABLgAECgkJFgAQANgbAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Sackhammer:BAAALgAECgQJBAAAAA==.Saint:BAAALgAECgkJDQAAAA==.Samson:BAAALgAECgYJEAABLgAECgUJCwANAAAAAA==.Sanivan:BAABLgAECn8VAAIQAAcJ+hdxGgDvAQAQAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgADCgEJAQAAAA==.Sappy:BAABLgAECn8aAAQbAAcJdR9BCQCuAQAbAAYJsh5BCQCuAQAkAAQJrxwzOwA/AQAnAAQJ8BLcCQDFAAABLgAFFAQJEQAFAJ4gAA==.Sarinae:BAABLgAECn8iAAQgAAgJbgXNWQDAAAAgAAcJbQTNWQDAAAAjAAEJwAHbQAAfAAAZAAEJwAEwKgAXAAAAAA==.Sarmuc:BAABLgAECn8ZAAMXAAgJmw8bFgBOAQAXAAgJmw8bFgBOAQARAAEJXwsDpQAoAAAAAA==.Saryda:BAAALgAECgUJDQAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJDAABLgAECgkJKQAFANUeAA==.Scubagal:BAAALgAECgUJCAAAAA==.Scy:BAAALgAECgQJBQAAAA==.Scythraza:BAABLgAECn8lAAMgAAgJcxcoGwD0AQAgAAgJcxcoGwD0AQAjAAEJCQSoOwArAAAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJMgAOAHsQAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Sedge:BAAALgADCgEJAQAAAA==.Seedsprayer:BAAALgAECgYJDAAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAABLgAECn8XAAITAAYJvBy2WABxAQATAAYJvBy2WABxAQAAAA==.Sensu:BAAALgAECgYJCwAAAA==.Sensual:BAAALgAECgMJAwAAAA==.Sernian:BAAALgAECgQJCQABLgAFFAUJGAAKAHIjAA==.Seä:BAABLgAECn8yAAIOAAkJexD4IgDiAQAOAAkJexD4IgDiAQAAAA==.',
Sh='Shadoweave:BAABLgAECn8dAAIUAAkJqwc3LwBbAQAUAAkJqwc3LwBbAQAAAA==.Shamtea:BAABLgAECn8tAAIRAAgJaA7mNgBNAQARAAgJaA7mNgBNAQAAAA==.Shapzan:BAAALgAECgYJCwAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shiik:BAAALgAECgYJBwAAAA==.Shivant:BAABLgAECn8sAAMBAAgJEx4NHABeAgABAAgJEx4NHABeAgARAAEJ9gIXtQAcAAAAAA==.Shmeegleroop:BAAALgAECgYJDgAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAABLgAECn8uAAIMAAkJoCAwAgDbAgAMAAkJoCAwAgDbAgAAAA==.',
Si='Silvertime:BAAALgADCgYJBwAAAA==.Sindice:BAAALgAECgYJCwABLgAFFAcJGwABAMggAA==.',
Sk='Skaa:BAAALgAECgEJAgAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slanesh:BAAALgAECgIJAgAAAA==.Slimpooshady:BAABLgAECn8rAAMCAAkJFhK1JgAQAgACAAkJFhK1JgAQAgAaAAkJaBMiEADVAQAAAA==.Sloth:BAAALgAECgkJEgAAAA==.',
So='Solaspirus:BAABLgAECn8pAAMTAAkJHhkrIgA+AgATAAkJHhkrIgA+AgAMAAEJawzNMwAqAAAAAA==.Solinius:BAAALgAECgQJBQAAAA==.Sope:BAAALgAECgYJCQAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.Soulomatic:BAAALgADCgcJBwAAAA==.',
Sp='Spectors:BAABLgAECn8wAAMlAAgJxAkqEgAzAQAlAAcJ3goqEgAzAQAdAAcJ5wMPuADSAAAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAIOAAgJPxyvEACIAgAOAAgJPxyvEACIAgAAAA==.Sprayinnseed:BAAALgAECgMJBAAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwANAAAAAA==.',
St='Stabon:BAABLgAECn8lAAIkAAkJcwlkHQCdAQAkAAkJcwlkHQCdAQAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgYJDAAAAA==.',
Sw='Sweetstorm:BAABLgAECn86AAIQAAkJxwcFJQA+AQAQAAkJxwcFJQA+AQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn83AAIOAAkJWxdIEwBsAgAOAAkJWxdIEwBsAgAAAA==.',
Ta='Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAABLgAECn8VAAIKAAgJwA0SgwBdAQAKAAgJwA0SgwBdAQAAAA==.Tarixx:BAABLgAFFH8GAAMKAAMJ/w5hJACjAAAKAAIJQg5hJACjAAALAAEJeRDuFgA0AAAAAA==.Tazanoth:BAACLgAFFH8IAAQEAAMJBBIcZADAAAAEAAMJ0Q8cZADAAAAmAAIJKQ6OKACEAAASAAEJTArEJgBPAAAuAAQKfyEAAyYACQmaG/gNAEUCACYACQmQGvgNAEUCABIABglBGtYwALABAAAA.',
Te='Teasa:BAABLgAECn86AAIEAAkJ5xeZJQA/AgAEAAkJ5xeZJQA/AgAAAA==.Tekeelà:BAACLgAFFH8JAAQEAAUJwwdDAgB7AQAEAAUJwwdDAgB7AQASAAEJVgAiLgA1AAAmAAEJhAFCNAAqAAAuAAQKfzIABAQACQl2IaMVAIoCAAQACQkHH6MVAIoCACYACQm6GFwOAEACABIABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAABLgAECn8aAAMEAAYJdwN0twDEAAAEAAYJdwN0twDEAAAmAAUJcgHmUQBYAAAAAA==.Theenna:BAAALgADCgUJBQAAAA==.Thetodd:BAAALgAECgIJAgAAAA==.Thianna:BAABLgAECn8dAAMOAAkJlBZTHgAFAgAOAAkJlBZTHgAFAgAKAAYJ8Qp81wDcAAAAAA==.Thiculuskage:BAABLgAECn8WAAIOAAgJLB4bDgCnAgAOAAgJLB4bDgCnAgAAAA==.Thinkso:BAAALgADCgcJFQAAAA==.Thobu:BAAALgAECgcJCwAAAA==.Thodos:BAAALgADCgEJAQAAAA==.Thornscale:BAABLgAECn9BAAQgAAkJ3hpSEABeAgAgAAkJ3hpSEABeAgAZAAUJvBa6DAA4AQAjAAYJogvrKAAsAQAAAA==.Thorrent:BAAALgADCgcJCAAAAA==.',
Ti='Tigolcrittys:BAAALgAECgUJBwABLgAECgkJLgAEAK0aAA==.Timeforloads:BAABLgAECn8hAAMCAAgJoR8xOgCjAQACAAYJdB4xOgCjAQAHAAUJVRPyQAD7AAAAAA==.',
To='Tolk:BAAALgAECgcJEQAAAA==.Tomzombe:BAAALgAECgQJBgAAAA==.Totem:BAABLgAECn8UAAIRAAgJvQtQQQAeAQARAAgJvQtQQQAeAQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Traveler:BAAALgAECgIJAgAAAA==.Trickyflamom:BAAALgAECgYJCwABLgAFFAQJFwAeACgZAA==.Troloq:BAABLgAECn80AAQlAAkJWB21BwDiAQAdAAgJHhsqNQD/AQAlAAgJHRe1BwDiAQAcAAUJ8BnAEgASAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgAECgMJBQAAAA==.Turger:BAAALgAECgUJCAABLgAECgkJEAANAAAAAA==.Turinnii:BAAALgADCgcJBwAAAA==.',
Ul='Uller:BAABLgAECn8oAAIeAAkJDhoNLgBbAgAeAAkJDhoNLgBbAgAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAABLgAECn8YAAIOAAYJKgq8SwABAQAOAAYJKgq8SwABAQAAAA==.Vaimei:BAABLgAECn83AAMcAAkJ+CL0AQCoAgAcAAgJPSP0AQCoAgAdAAgJAyB8FAClAgAAAA==.Valashune:BAAALgADCgEJAQAAAA==.Valsilla:BAAALgAECgYJBgABLgAECgkJFgAQANgbAA==.Vapor:BAABLgAECn8hAAIbAAgJOBguBgAAAgAbAAgJOBguBgAAAgAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebs:BAABLgAECn8VAAMhAAgJCBPcKACvAQAhAAgJCBPcKACvAQAfAAEJAAAySAAuAAAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8gAAIeAAgJaQZKogAyAQAeAAgJaQZKogAyAQAAAA==.Vento:BAABLgAECn8VAAIFAAgJjxX+WgCuAQAFAAgJjxX+WgCuAQAAAA==.Verité:BAAALgAECgcJEgAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgAECgEJAQABLgAFFAQJBgAKAJoZAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn89AAITAAkJmBQCMAD7AQATAAkJmBQCMAD7AQAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgUJDAAAAA==.Voltimand:BAAALgAECgEJAQABLgAFFAMJBgABAD4OAA==.',
Vv='Vvicked:BAABLgAECn8gAAIFAAgJrCIdFQDAAgAFAAgJrCIdFQDAAgAAAA==.',
Vy='Vynesta:BAABLgAECn8WAAIQAAkJ2BvUCwBaAgAQAAkJ2BvUCwBaAgAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wanagi:BAAALgADCgMJAwAAAA==.Wankz:BAAALgAECgkJEgAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8dAAIhAAgJSiLjDwBzAgAhAAgJSiLjDwBzAgAAAA==.',
We='Weyna:BAABLgAECn84AAMVAAgJ3hHNLgCqAQAVAAgJ3hHNLgCqAQAJAAYJVAmeSgDLAAABLgAFFAUJGgAjACwWAA==.',
Wh='Whisperingei:BAAALgAECgYJCgAAAA==.',
Wi='Widowx:BAABLgAECn8tAAIRAAkJtRrUFQAsAgARAAkJtRrUFQAsAgAAAA==.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAABLgAECn8VAAIEAAcJbRpyOwDmAQAEAAcJbRpyOwDmAQABLgAECggJKwAPABMiAA==.',
Wr='Wrandohunt:BAAALgAECgEJAwAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wreckitrandy:BAAALgAECgEJAQAAAA==.Wryn:BAAALgAECgkJEQABLgAECgkJKQAFANUeAA==.',
Wu='Wulyn:BAAALgAECgYJCwAAAA==.',
Wy='Wylla:BAAALgAECgUJDQAAAA==.',
Xa='Xalethra:BAABLgAECn80AAITAAkJBySgBAA2AwATAAkJBySgBAA2AwAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xenophobias:BAAALgAECgYJEAAAAA==.',
Xh='Xhosen:BAAALgAFFAIJBAAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn89AAICAAkJwxgyIAA8AgACAAkJwxgyIAA8AgAAAA==.',
Ya='Yarloon:BAAALgADCgcJBwAAAA==.',
Yt='Ytsirk:BAAALgADCgYJBgAAAA==.',
Yv='Yve:BAAALgAECgUJDQAAAA==.',
Za='Zaharian:BAAALgAECgEJAQAAAA==.Zalajin:BAAALgAECgQJBAAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zarayndia:BAAALgAECgYJCAAAAA==.',
Ze='Zeddicus:BAABLgAECn8oAAMlAAkJQQhSDQBzAQAlAAkJ0AdSDQBzAQAdAAUJ0AO+5wCDAAAAAA==.Zendragan:BAACLgAFFH8GAAIVAAMJzRBlNwCnAAAVAAMJzRBlNwCnAAAuAAQKfx4AAhUACQlOGPYVAFcCABUACQlOGPYVAFcCAAAA.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoe:BAAALgAECgQJBAAAAA==.Zoidz:BAAALgAECggJDAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zombruh:BAAALgAECgEJAQAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.Zythopoios:BAAALgAECgYJDgAAAA==.',
Zz='Zzilladi:BAABLgAFFH8LAAMPAAUJnxJ4EQArAQAPAAQJyhZ4EQArAQAUAAEJAAASPgAAAAAAAA==.Zzilladinzz:BAACLgAFFH8TAAIKAAQJjSCKKABUAQAKAAQJjSCKKABUAQAuAAQKfyIAAgoACQkIIwsSAAIDAAoACQkIIwsSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgAECgYJDwABLgAECgkJLgAMAKAgAA==.',
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
