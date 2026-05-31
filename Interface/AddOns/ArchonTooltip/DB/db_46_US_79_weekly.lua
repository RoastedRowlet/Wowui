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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver','Priest-Discipline','Shaman-Restoration','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Arms','DeathKnight-Unholy','Priest-Shadow','DeathKnight-Blood','Hunter-Survival','Warlock-Affliction','Rogue-Assassination','Druid-Guardian','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaronius:BAABLgAECn8nAAIBAAgJwgQyOAAFAQABAAgJwgQyOAAFAQAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8pAAMCAAkJwB3RIQCBAgACAAkJwB3RIQCBAgADAAQJ2BeKCwAeAQAAAA==.',
Ac='Acceptance:BAAALgAECgMJBAAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8sAAIEAAkJ3yH1DQDPAgAEAAkJ3yH1DQDPAgAAAA==.Adora:BAABLgAECn8bAAIEAAcJIx3jMAABAgAEAAcJIx3jMAABAgAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aelise:BAAALgADCgQJBAABLgAECgkJMAAFAFEfAA==.Aeðn:BAABLgAECn8ZAAIEAAcJGRAyZgBfAQAEAAcJGRAyZgBfAQAAAA==.',
Ag='Agaliarept:BAACLgAFFH8JAAIGAAMJPArEWQDAAAAGAAMJPArEWQDAAAAuAAQKfxYAAwcACAkYC1IXAM0AAAYABwnpBuCLAAsBAAcABwkPC1IXAM0AAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAAALgAECgUJEgAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn8zAAMIAAkJXRQlEgDqAQAIAAkJXRQlEgDqAQAGAAQJPwe0tgCZAAAAAA==.',
Ak='Akumajoe:BAAALgADCgcJBwAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAECgEJBAAAAA==.Alrook:BAABLgAECn8UAAMJAAgJ3xV+bAB8AQAJAAgJ3xV+bAB8AQAKAAIJ4BEobwBfAAAAAA==.Aluni:BAAALgAECgUJBQAAAA==.',
Am='Amoral:BAAALgAECgMJAwAAAA==.',
An='Angelneko:BAABLgAECn8wAAILAAgJGA5kLABZAQALAAgJGA5kLABZAQAAAA==.Anitabj:BAAALgAECgMJAwAAAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwAMAAAAAA==.Arcaynemoon:BAABLgAECn8XAAILAAYJWAM9VgDLAAALAAYJWAM9VgDLAAAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.',
As='Asterior:BAACLgAFFH8RAAMNAAYJvxdiAQBxAQANAAUJmxtiAQBxAQALAAEJTghiPQBNAAAuAAQKfywAAg0ACQnzIOMCANoCAA0ACQnzIOMCANoCAAAA.',
Au='Aug:BAAALgAECgIJAgABLgAECggJDQAMAAAAAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgAECgEJAQAAAA==.Auroraa:BAABLgAECn8mAAILAAcJyAZPRADeAAALAAcJyAZPRADeAAAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgIJAgAMAAAAAA==.',
Av='Avalectra:BAAALgAECgUJCAAAAA==.',
Ay='Aylana:BAAALgAECgYJBgAAAA==.',
Az='Azanost:BAAALgADCgQJBAABLgAECgkJJAAOAOAVAA==.Azmodeaz:BAABLgAECn8zAAIDAAgJExpyAgAcAgADAAgJExpyAgAcAgAAAA==.',
Ba='Bajapanti:BAABLgAECn86AAIPAAkJvxsaAwCUAgAPAAkJvxsaAwCUAgAAAA==.Ballyhøø:BAABLgAECn8VAAILAAkJSxHrQgDkAAALAAkJSxHrQgDkAAAAAA==.Banchory:BAAALgADCgQJBQAAAA==.Bandaron:BAAALgAECgQJBQAAAA==.Baxstab:BAABLgAECn82AAIQAAkJ5xv3CgBeAgAQAAkJ5xv3CgBeAgAAAA==.',
Bc='Bcam:BAAALgADCgYJBgAAAA==.',
Be='Beahon:BAAALgAECgQJCgAAAA==.Betruger:BAAALgAECgEJAQAAAA==.',
Bg='Bgeefiddy:BAAALgAECgMJAwAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJCgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackjak:BAAALgAECgEJAQAAAA==.Blackpatch:BAABLgAECn84AAMRAAkJZCLBAwATAwARAAkJZCLBAwATAwASAAgJ4gegNAAbAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgUJCQAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAABLgAFFH8FAAITAAMJ+hSxJgDgAAATAAMJ+hSxJgDgAAAAAA==.Blooming:BAAALgAECgYJCwABLgAECggJHAAUAA4aAA==.Bloomsbeam:BAABLgAECn8cAAIGAAgJDBbdXgBUAQAGAAgJDBbdXgBUAQAAAA==.Bloomslinger:BAAALgADCgQJBAAAAA==.',
Bo='Bonerflex:BAABLgAECn8iAAMVAAkJGxqTCwCaAgAVAAkJGxqTCwCaAgAWAAQJQApUPABoAAAAAA==.Booneboy:BAABLgAECn8WAAMJAAcJ7yChNwAKAgAJAAcJ7yChNwAKAgAXAAQJVhCfJwC+AAAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8lAAMXAAkJXxWlFgBRAQAXAAkJ7BKlFgBRAQAJAAcJ3A3wlgArAQABLgAFFAUJFAAYANEWAA==.',
Br='Brennor:BAABLgAECn8zAAIJAAkJ5w6OXgCbAQAJAAkJ5w6OXgCbAQAAAA==.Brewslunt:BAACLgAFFH8QAAIZAAYJQRa1FACIAQAZAAYJQRa1FACIAQAuAAQKfysAAxkACAmfIWkQAIACABkACAmfIWkQAIACABEAAwnEC51dAIYAAAAA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Bubblydin:BAAALgAECgYJBgABLgAFFAIJBQAaAJ8JAA==.Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAABLgAECn8eAAIbAAgJORQWLQDpAQAbAAgJORQWLQDpAQAAAA==.Cairyan:BAABLgAECn8sAAIHAAkJWBsuBABsAgAHAAkJWBsuBABsAgAAAA==.Caiya:BAAALgADCgcJBwABLgAECgkJOAAQAOMkAA==.Capn:BAAALgADCgcJCQAAAA==.Carvil:BAABLgAECn8zAAMcAAkJGxaWBQD5AQAcAAkJGxaWBQD5AQAUAAMJjwfa3QCJAAAAAA==.Castalia:BAAALgAECgUJCgAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8RAAICAAUJGxSUTgAzAQACAAUJGxSUTgAzAQAuAAQKfykAAgIACAnmIyocAAYDAAIACAnmIyocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAUJEQACABsUAA==.Celithe:BAABLgAECn8dAAIJAAgJpxQlVAC1AQAJAAgJpxQlVAC1AQAAAA==.Cendrian:BAABLgAECn8WAAILAAcJYQvzPAD/AAALAAcJYQvzPAD/AAAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8tAAICAAkJfhzbJwBlAgACAAkJfhzbJwBlAgAAAA==.Charmshield:BAAALgAECgMJAwAAAA==.Chiafix:BAABLgAECn8cAAISAAgJDwxULgA6AQASAAgJDwxULgA6AQABLgAECgkJMgAbANYhAA==.Chipp:BAABLgAECn8UAAISAAcJ/CaHDgA/AgASAAcJ/CaHDgA/AgAAAA==.Chleo:BAAALgAECgMJBgAAAA==.Choco:BAACLgAFFH8kAAIdAAgJox1lAQDiAgAdAAgJox1lAQDiAgAuAAQKfykAAx0ACQnvI+QFAOgCAB0ACQnvI+QFAOgCAB4AAQkVG5EeAEkAAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAgJJAAdAKMdAA==.Chudster:BAABLgAECn8gAAMeAAkJ/RX+BgC/AQAeAAkJ/RX+BgC/AQAfAAUJDQgRWQCoAAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAABLgAECn8dAAMWAAYJax25EwCbAQAWAAYJax25EwCbAQAgAAEJixE3aAAyAAAAAA==.Conqueror:BAAALgAECgYJEAABLgAECgkJOgAFACUaAA==.',
Cr='Crawdaddy:BAABLgAECn8WAAIEAAcJJhItYgBpAQAEAAcJJhItYgBpAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAAALgAECgcJDwAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECgcJFgAJAGMLAA==.Curmudge:BAABLgAECn9HAAIFAAkJFhfOGwBTAgAFAAkJFhfOGwBTAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgAMAAAAAA==.Cybele:BAABLgAECn8VAAIBAAYJqwwKNwAMAQABAAYJqwwKNwAMAQAAAA==.',
Da='Dakunaito:BAABLgAECn8cAAIhAAgJFSXeIgBnAgAhAAgJFSXeIgBnAgAAAA==.Darachane:BAABLgAECn8qAAMiAAcJig5kPAD9AAAiAAcJig5kPAD9AAABAAEJxwIAcQAgAAAAAA==.Darovan:BAAALgADCgMJAwABLgAECggJNwAjAGMiAA==.Dauglow:BAAALgAECgMJAwAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgADCggJCQAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAFFAEJAQAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAAALgAECgUJEwAAAA==.Deltia:BAABLgAECn8oAAITAAgJYBfBHwDLAQATAAgJYBfBHwDLAQAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAQJDQAEAKURAA==.Demonagent:BAAALgAECgYJDgAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8VAAMfAAYJ+hZ5FgByAQAfAAYJ+hZ5FgByAQAeAAIJfQ4ZCQBYAAAuAAQKfysAAx4ACQmFHtYJAEICAB4ACQlbHNYJAEICAB8ACAmaFsobAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8cAAIUAAgJDhr2NAD4AQAUAAgJDhr2NAD4AQAAAA==.',
Di='Dimebagg:BAAALgAECgQJBQAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8sAAMBAAgJdx1EEABPAgABAAgJdx1EEABPAgAaAAMJDgnvRACRAAAAAA==.Dokspades:BAAALgAECggJEgAAAA==.Dornoch:BAABLgAECn8dAAMKAAcJFiJzFQBKAgAKAAcJFiJzFQBKAgAJAAEJ8AE1XAEjAAAAAA==.Dotzilla:BAAALgAECgUJEAAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJCQAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8tAAIJAAkJ2g3zYACVAQAJAAkJ2g3zYACVAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgYJDgAMAAAAAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAABLgAFFH8HAAIGAAIJ+h3zYACpAAAGAAIJ+h3zYACpAAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8OAAIhAAMJwRkLeADuAAAhAAMJwRkLeADuAAAuAAQKfzAAAiEACQkJIX0XAKYCACEACQkJIX0XAKYCAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAgAAAA==.',
Ei='Eisenhorn:BAAALgAECgUJBgAAAA==.',
El='Elessaria:BAABLgAECn8WAAIFAAcJQQaebADdAAAFAAcJQQaebADdAAAAAA==.Elfatheàrt:BAAALgAECgUJEgAAAA==.Elidrus:BAAALgADCgcJBwABLgAECgcJCQAMAAAAAA==.Elira:BAAALgAECgEJAQAAAA==.',
Em='Emelgee:BAAALgAECgUJCAABLgAFFAIJBQAaAJ8JAA==.Emofurry:BAAALgADCgIJAwAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgcJGwAEACMdAA==.',
Es='Esika:BAAALgAFFAIJAwAAAA==.Estherras:BAABLgAECn8uAAIEAAkJpBlZHwBVAgAEAAkJpBlZHwBVAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgEJAQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fa='Fato:BAAALgAECgIJAgAAAA==.',
Fe='Feardotrun:BAABLgAECn8iAAMUAAgJnAzcaABgAQAUAAgJ1gvcaABgAQAcAAMJWQwKIgCFAAAAAA==.Felicious:BAAALgAECgQJDQAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgAMAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgADCgUJBQAAAA==.Finahlia:BAABLgAECn8gAAIFAAkJ7CEDBQBcAwAFAAkJ7CEDBQBcAwAAAA==.Finally:BAABLgAECn8fAAITAAcJMQgHVQDKAAATAAcJMQgHVQDKAAAAAA==.Firebat:BAAALgADCgcJBwABLgAECgcJFgAJAO8gAA==.Firemage:BAABLgAECn8jAAIUAAkJ6iDpHwBYAgAUAAkJ6iDpHwBYAgAAAA==.Fizzanelf:BAABLgAECn8fAAIFAAcJOCPwGABsAgAFAAcJOCPwGABsAgAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAACLgAFFH8HAAIJAAQJpQRlTQD0AAAJAAQJpQRlTQD0AAAuAAQKfzIAAgkACQkKGgBRAO4BAAkACQkKGgBRAO4BAAAA.Friendo:BAABLgAECn85AAMNAAkJARnKBgBUAgANAAkJARnKBgBUAgALAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAECgkJBAAAAA==.',
Fu='Furnost:BAABLgAECn8kAAIOAAkJ4BViBwD1AQAOAAkJ4BViBwD1AQAAAA==.Futnuraz:BAABLgAECn8bAAIgAAcJ+wbdOQDDAAAgAAcJ+wbdOQDDAAAAAA==.',
Fy='Fyrakkobama:BAAALgAECggJAgABLgAECgkJGQAkAP0iAA==.Fyriat:BAABLgAECn8zAAICAAkJnwn7cAB+AQACAAkJnwn7cAB+AQAAAA==.',
Ga='Gazardiel:BAAALgAECgIJAgAAAA==.',
Ge='Getafix:BAAALgAECgYJCQABLgAECgkJMgAbANYhAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8mAAIRAAgJJRhmFgDsAQARAAgJJRhmFgDsAQAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goliath:BAAALgAECgUJCAABLgAECgkJGwAJAMcbAA==.Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8lAAIcAAkJIh3hAQCgAgAcAAkJIh3hAQCgAgAAAA==.Greybark:BAAALgADCgcJEQAAAA==.Griffindor:BAABLgAECn8zAAIJAAkJYBh/KwA6AgAJAAkJYBh/KwA6AgAAAA==.Grimfelborn:BAACLgAFFH8ZAAMlAAUJqRUZCgCtAAAUAAQJRRCOSgAfAQAlAAMJERcZCgCtAAAuAAQKfzAAAxQACQmGHLsxAEUCABQACQkaGbsxAEUCACUAAwlQIZgcALcAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAABLgAECn8ZAAIbAAYJuyCpIwAeAgAbAAYJuyCpIwAeAgAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgADCgkJEwAAAA==.',
Ha='Hanicus:BAAALgAECgcJCQAAAA==.Hanoverfiste:BAABLgAECn8WAAIJAAcJYwvKpAAVAQAJAAcJYwvKpAAVAQAAAA==.Hapsburg:BAABLgAECn8rAAIZAAkJdxKNHwD2AQAZAAkJdxKNHwD2AQAAAA==.Havince:BAABLgAECn82AAIjAAkJ+CCzBQC6AgAjAAkJ+CCzBQC6AgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn84AAIJAAkJsB+MEgDAAgAJAAkJsB+MEgDAAgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Ig='Ignisdaemoni:BAAALgADCgcJBwABLgAECgkJIAAFAOwhAA==.',
Il='Illidai:BAAALgAECgYJEgAAAA==.Ilyndra:BAABLgAECn8wAAMgAAgJXCGvBgB9AgAgAAgJXCGvBgB9AgAWAAgJrRzNCgAtAgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn8zAAIVAAkJYBaNFwAeAgAVAAkJYBaNFwAeAgAAAA==.',
It='Ithea:BAABLgAECn8uAAICAAgJpCDQIwB3AgACAAgJpCDQIwB3AgAAAA==.',
Ja='Jackyll:BAAALgAECgIJAgAAAA==.Jaeson:BAEBLgAECn8iAAIUAAkJjhaBKgAiAgAUAAkJjhaBKgAiAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAgJHwAKAGscAA==.',
Je='Jeef:BAAALgADCgEJAQABLgAECgkJGQAkAP0iAA==.Jeefrenzy:BAABLgAECn8ZAAMkAAkJ/SILBADmAgAkAAkJ/SILBADmAgAEAAIJkiFG4wBgAAAAAA==.Jeefwrld:BAAALgAECgQJBAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgYJDwAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8lAAQBAAkJeBnlGwDQAQABAAgJsRLlGwDQAQAaAAYJ8RSgIwB2AQAiAAUJDRSMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8WAAImAAcJKQ+YCwBjAQAmAAcJKQ+YCwBjAQAAAA==.',
Jw='Jwise:BAAALgADCgcJCgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kamus:BAAALgAECgMJAwAAAA==.Kanabat:BAAALgAECgcJDgAAAA==.Karaden:BAAALgAECgUJBQAAAA==.Karawyn:BAABLgAECn8eAAIEAAgJyw5BPQC5AQAEAAgJyw5BPQC5AQABLgAECgcJCQAMAAAAAA==.Karelix:BAAALgAECgIJAgAAAA==.Katrishy:BAACLgAFFH8ZAAIiAAUJ9xSgEwAxAQAiAAUJ9xSgEwAxAQAuAAQKfy0AAyIACQkmHocWADMCACIACQkmHocWADMCAAEAAQlwBUSIACcAAAAA.Kaylierocks:BAAALgAECgEJAQAAAA==.Kayyfrost:BAAALgADCgIJAgAAAA==.Kazeral:BAAALgADCggJEQAAAA==.',
Ke='Keedrid:BAABLgAECn8UAAIhAAkJJx2JMAApAgAhAAkJJx2JMAApAgAAAA==.Keindis:BAAALgAECgQJBgABLgAECgcJKgAiAIoOAA==.Kelaeno:BAAALgADCgkJCQABLgAECggJHQAGAAwHAA==.Kelemenohpea:BAABLgAECn8dAAIGAAgJDAeHiQDvAAAGAAgJDAeHiQDvAAAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8yAAIbAAkJ1iFmBQBIAwAbAAkJ1iFmBQBIAwAAAA==.Kruàlty:BAABLgAECn8dAAINAAgJwhouCAAsAgANAAgJwhouCAAsAgAAAA==.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwAMAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgAECgEJAQABLgAECgcJFwADAFkKAA==.Legreecast:BAABLgAECn8XAAIDAAcJWQr/CADmAAADAAcJWQr/CADmAAAAAA==.Levlia:BAAALgADCgYJBgAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ83IwCTAQABAAkJGQ83IwCTAQAiAAIJ2welcAA8AAAaAAEJrgFbegALAAAAAA==.',
Lo='Loamuhwea:BAAALgAECgEJAQAAAA==.Lodur:BAABLgAECn8tAAIbAAkJlRtQFwB3AgAbAAkJlRtQFwB3AgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn8yAAInAAkJRBJ9EwCbAQAnAAkJRBJ9EwCbAQAAAA==.Losat:BAABLgAECn86AAIWAAkJzg1ZFQCHAQAWAAkJzg1ZFQCHAQAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8bAAIJAAkJxxs+IgBmAgAJAAkJxxs+IgBmAgAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwAMAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAAALgAECgkJEwAAAA==.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Mackavelian:BAAALgAECgEJAQABLgAECggJLQAZAIEXAA==.Mackkie:BAABLgAECn8tAAMZAAgJgRcBGwAZAgAZAAgJgRcBGwAZAgARAAYJ3wrIQQDfAAAAAA==.Madonkadonk:BAABLgAECn82AAMeAAkJwhBQBgDYAQAeAAkJwhBQBgDYAQAfAAMJlAUCegBIAAAAAA==.Maedai:BAABLgAECn81AAIZAAkJyhajFQBLAgAZAAkJyhajFQBLAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAACLgAFFH8HAAIKAAMJyBmgJQDeAAAKAAMJyBmgJQDeAAAuAAQKfzsAAwoACQk3HpkRAHMCAAoACQk3HpkRAHMCAAkABQm7EIruAK0AAAAA.Magús:BAAALgAECgEJAgAAAA==.Maldive:BAABLgAECn8uAAIUAAkJZRHfPADbAQAUAAkJZRHfPADbAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Mallicia:BAACLgAFFH8SAAIBAAQJkSFRCwBtAQABAAQJkSFRCwBtAQAuAAQKfzYAAwEACQm4I5cDACADAAEACQm4I5cDACADABoABwlEGWAWAAQCAAAA.Mallika:BAABLgAECn8ZAAIbAAgJMhSPNADDAQAbAAgJMhSPNADDAQABLgAFFAQJEgABAJEhAA==.Mallistraza:BAAALgAECgIJAgABLgAFFAQJEgABAJEhAA==.Mallwizard:BAACLgAFFH8JAAIUAAMJjAbWdgC7AAAUAAMJjAbWdgC7AAAuAAQKfy0AAhQACQnEFZQ4ACkCABQACQnEFZQ4ACkCAAAA.Mandor:BAAALgADCgYJBgAAAA==.Mangopewpew:BAAALgAECgUJDwAAAA==.Martris:BAAALgADCgcJCwAAAA==.Massoflice:BAACLgAFFH8JAAIhAAMJhQlskQDJAAAhAAMJhQlskQDJAAAuAAQKfyYAAiEACQmEFks2ABICACEACQmEFks2ABICAAAA.Maxblaide:BAAALgAECgUJEAAAAA==.Maxilla:BAAALgADCgcJDQABLgAECgkJIgAVABsaAA==.',
Me='Menguli:BAAALgAECgIJAgAAAA==.Meridians:BAABLgAECn8bAAIZAAYJxxZyMwB5AQAZAAYJxxZyMwB5AQAAAA==.',
Mh='Mhataharii:BAAALgADCggJCAAAAA==.',
Mi='Mindhorn:BAACLgAFFH8MAAMTAAMJkxqVJQDnAAATAAMJkxqVJQDnAAAbAAIJrRk4TACjAAAuAAQKfycAAxMACAk0IQoOAHUCABMACAk0IQoOAHUCABsABAnTFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn8yAAIXAAkJAhk+CQAiAgAXAAkJAhk+CQAiAgAAAA==.Moctar:BAAALgADCgQJBAAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIJAAgJJyAcMwBWAgAJAAgJJyAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAECgkJIgAfAHYUAA==.Musashi:BAAALgAFFAIJAgAAAA==.Mustardhunt:BAAALgADCgYJCwAAAA==.',
My='Myriad:BAABLgAECn8tAAIWAAkJmh8KBQC6AgAWAAkJmh8KBQC6AgAAAA==.',
Na='Nakze:BAABLgAECn80AAIQAAkJAg+ZFQDaAQAQAAkJAg+ZFQDaAQAAAA==.Namanari:BAAALgADCgkJCgAAAA==.Nancydru:BAAALgAECgQJBAAAAA==.Nardwuar:BAAALgAECgQJCAABLgAECgkJBAAMAAAAAA==.Naris:BAAALgADCgYJBgAAAA==.Nastyfigs:BAABLgAECn8qAAIEAAkJzRuDNgDsAQAEAAkJzRuDNgDsAQAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAECgkJDgAAAA==.',
Nh='Nhilas:BAAALgAECgQJDAAAAA==.',
Ni='Nightstryke:BAAALgAECgEJAQAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
No='Nork:BAAALgAECgIJAgAAAA==.',
Ny='Nyxaries:BAABLgAECn8UAAIjAAUJHRcXKQD0AAAjAAUJHRcXKQD0AAAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
On='Onenytestand:BAAALgAECgkJCAAAAA==.',
Or='Ordis:BAAALgADCgQJBAAAAA==.Orrana:BAAALgAECgEJAQAAAA==.',
Pa='Pablo:BAAALgAECgYJDQAAAA==.Pannacea:BAAALgAECgYJCQABLgAECgkJMgAbANYhAA==.Panzerblitz:BAABLgAECn8cAAInAAgJhQm+LQDQAAAnAAgJhQm+LQDQAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIcAAcJNQoFIABSAQAcAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgADCggJDAAAAA==.',
Pe='Pedrote:BAAALgADCgcJCgAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Peppert:BAAALgAECggJCAAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Ph='Phane:BAAALgAECgUJBQAAAA==.Phson:BAAALgADCgIJAgAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIEAAYJOCApKgANAgAEAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pincher:BAAALgADCgQJBAAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAABLgAECn8cAAIgAAYJxQcfNwDOAAAgAAYJxQcfNwDOAAAAAA==.Pretzelz:BAAALgADCgYJCgAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puertoricanj:BAAALgAECgMJAgAAAA==.Puffer:BAABLgAECn84AAICAAkJdhAMUQDRAQACAAkJdhAMUQDRAQAAAA==.',
Ra='Rabone:BAAALgAECgUJBQAAAA==.Raelaris:BAAALgAFFAIJAwABLgAFFAUJEQACANgjAA==.Raito:BAABLgAECn8gAAIJAAgJcgtekAA2AQAJAAgJcgtekAA2AQAAAA==.Rakshasa:BAACLgAFFH8JAAIUAAMJ/B3UTQAZAQAUAAMJ/B3UTQAZAQAuAAQKfykAAxQACQnJIhcKAPQCABQACQnJIhcKAPQCACUAAQkAALIhAGsAAAAA.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJBwABLgAECgcJGwAEACMdAA==.Rasetsungo:BAABLgAECn8fAAIBAAkJnxxHCgCtAgABAAkJnxxHCgCtAgAAAA==.Raura:BAABLgAECn8dAAIjAAcJiBHzJQALAQAjAAcJiBHzJQALAQAAAA==.Rayala:BAAALgAECgkJCQAAAA==.',
Re='Recalcitrent:BAAALgADCgYJCAAAAA==.Redblueblurr:BAABLgAECn8mAAIJAAgJMhCrZACNAQAJAAgJMhCrZACNAQAAAA==.Remi:BAABLgAECn8cAAMBAAgJIhq9EABJAgABAAgJIhq9EABJAgAiAAEJ3RNJcAA9AAAAAA==.Reveillark:BAABLgAECn8UAAIdAAYJYhe4EQCaAQAdAAYJYhe4EQCaAQAAAA==.',
Ro='Rolan:BAACLgAFFH8IAAIhAAQJDyU6HQC4AQAhAAQJDyU6HQC4AQAuAAQKfx4AAiEACQnYJOcSAMUCACEACQnYJOcSAMUCAAAA.Roogyrunes:BAAALgAECgcJCQABLgAECggJIAAJAHEjAA==.Rosalian:BAABLgAECn8zAAIFAAkJJhz2DgDMAgAFAAkJJhz2DgDMAgAAAA==.Rotiko:BAABLgAECn8fAAIbAAgJEQx6SwBlAQAbAAgJEQx6SwBlAQAAAA==.Roweene:BAABLgAECn8vAAIoAAgJRAfEDQAZAQAoAAgJRAfEDQAZAQAAAA==.',
['Rá']='Rágnar:BAABLgAECn8VAAQJAAcJ7w1GlQAuAQAJAAcJ0AxGlQAuAQAXAAcJkgdSJwDAAAAKAAMJSQYPawBrAAAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgAECgUJBQAAAA==.',
Se='Seiko:BAAALgADCgEJAQAAAA==.Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8lAAMRAAcJzR/DGADVAQARAAcJzR/DGADVAQASAAEJEws+hQA8AAABLgAECgkJDgAMAAAAAA==.Serenatee:BAABLgAECn8xAAIiAAkJnhDiHADAAQAiAAkJnhDiHADAAQAAAA==.',
Sh='Shadowkrak:BAAALgAECgEJAQAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgADCgcJBwAAAA==.Shamwow:BAAALgADCggJDgAAAA==.Shappens:BAAALgADCgcJDAABLgAECgcJFgAJAGMLAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAAALgAECgYJEQAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAACLgAFFH8HAAIGAAMJcA06WADFAAAGAAMJcA06WADFAAAuAAQKfx0AAgYACQlzEnE2ANYBAAYACQlzEnE2ANYBAAAA.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgcJDQAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgADCgQJBAAAAA==.Simbà:BAAALgAECgYJDgAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8YAAMGAAcJGSHEIQCGAgAGAAcJGSHEIQCGAgAIAAEJ9hZVawA7AAABLgAECgkJGQAkAP0iAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAACLgAFFH8FAAIQAAMJEBe8HgABAQAQAAMJEBe8HgABAQAuAAQKfxQAAxAABglfHlocAJsBABAABQlfHlocAJsBACYAAwlRGmohAEEAAAAA.',
So='Soferfax:BAAALgADCgYJDQAAAA==.Sokroar:BAAALgAECgQJBAABLgAFFAIJBAAMAAAAAA==.Sonknight:BAABLgAECn8gAAMKAAYJCweoUADdAAAKAAYJCweoUADdAAAJAAQJ9QL2OwFVAAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAITAAgJZB3sFQAeAgATAAgJZB3sFQAeAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn85AAIkAAkJzQq/GwCxAQAkAAkJzQq/GwCxAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgQJCAAAAA==.Sto:BAAALgAECggJDQAAAA==.Stratof:BAAALgADCgIJAgAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Sukerpunch:BAAALgADCgEJAQAAAA==.Supad:BAAALgADCgYJBwAAAA==.Superjpriest:BAAALgAECgQJCwABLgAFFAIJAgAMAAAAAA==.Suria:BAABLgAECn8wAAIFAAkJUR8MCAApAwAFAAkJUR8MCAApAwAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgIJAgAAAA==.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Tahrovin:BAAALgAECgIJAgAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgADCgcJEwAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8pAAIaAAgJLx71CQC1AgAaAAgJLx71CQC1AgAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn8+AAMKAAkJzwVROABUAQAKAAkJzwVROABUAQAJAAgJ3gm9twD3AAAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.',
Th='Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgAECgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Thundercups:BAABLgAECn82AAIYAAkJPiELAwDJAgAYAAkJPiELAwDJAgAAAA==.',
Ti='Tigerstarr:BAACLgAFFH8HAAIhAAMJXwlzkwDGAAAhAAMJXwlzkwDGAAAuAAQKfx4AAyEACQm7E340ABkCACEACQm7E340ABkCAA4AAQlRBioZACoAAAAA.Timboslicé:BAAALgAECgcJCwAAAA==.Tinyshieva:BAABLgAECn8aAAMBAAYJTA4qOQD+AAABAAYJTA4qOQD+AAAiAAQJTwPNXwBqAAAAAA==.Tizuki:BAAALgAECgIJAwAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgkJBwAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn8wAAIcAAgJCxwQBAAtAgAcAAgJCxwQBAAtAgAAAA==.Treenn:BAAALgAECgUJEQAAAA==.Triplock:BAAALgADCgMJBQAAAA==.Trolcain:BAABLgAECn8uAAIhAAkJLiR/BgA2AwAhAAkJLiR/BgA2AwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgkJLgAhAC4kAA==.',
Ty='Tyrix:BAABLgAECn8gAAIJAAgJcSO1FgCkAgAJAAgJcSO1FgCkAgAAAA==.Tyránt:BAACLgAFFH8NAAIEAAQJpRHSNQApAQAEAAQJpRHSNQApAQAuAAQKfzAAAwQACQlLI4QMANsCAAQACQlLI4QMANsCAA8AAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAISAAYJ2BmCQABCAQASAAYJ2BmCQABCAQAAAA==.',
Va='Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCwAAAA==.Valerossi:BAABLgAECn84AAIkAAkJlx/+AwDnAgAkAAkJlx/+AwDnAgAAAA==.Valha:BAABLgAECn8mAAIIAAkJeRJGFADNAQAIAAkJeRJGFADNAQAAAA==.Valira:BAAALgADCggJCQABLgAECgcJGwAEACMdAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgADCgYJBgAAAA==.Varleyna:BAAALgAECgMJAwABLgAFFAQJEgABAJEhAA==.Varteras:BAABLgAECn8yAAMlAAkJsxvXBAAlAgAlAAgJghvXBAAlAgAUAAgJnxLHTQCmAQAAAA==.',
Ve='Veleiri:BAABLgAECn8sAAICAAgJ/hGdYQCjAQACAAgJ/hGdYQCjAQAAAA==.Velenal:BAAALgAECgQJDAAAAA==.Vellron:BAABLgAECn8uAAIEAAkJhw54OwDaAQAEAAkJhw54OwDaAQAAAA==.',
Vo='Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAACLgAFFH8OAAMGAAUJbRjQRAAAAQAGAAQJlRvQRAAAAQAIAAIJHA1xGgCKAAAuAAQKfxYAAwgABgm1I+0UAMUBAAgABgkKI+0UAMUBAAYABAkfH7xhAEwBAAAA.Wardkbriggle:BAACLgAFFH8OAAIjAAYJkx4FCADBAQAjAAYJkx4FCADBAQAuAAQKfyEAAiMACQmoI9QCAA4DACMACQmoI9QCAA4DAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8XAAISAAYJxRwpBwDkAQASAAYJxRwpBwDkAQAuAAQKfyAAAhIACQkeIMgJAIUCABIACQkeIMgJAIUCAAAA.',
Wi='Wifi:BAAALgAECgIJBQAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMjAAYJeAWFNwCGAAAjAAQJGQaFNwCGAAAOAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn83AAICAAgJzxICYgCiAQACAAgJzxICYgCiAQAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn84AAQQAAkJ4ySFAQBNAwAQAAkJsySFAQBNAwAmAAcJASMUBAB1AgAoAAYJth0eCQCGAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJCwABLgAECgkJOAAQAOMkAA==.',
Xh='Xhared:BAABLgAECn83AAIjAAgJYyIBBwCZAgAjAAgJYyIBBwCZAgAAAA==.',
Ya='Yahtzee:BAAALgAECgMJBgAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIGAAgJBwNnqwCuAAAGAAgJBwNnqwCuAAAAAA==.',
Yk='Ykszord:BAAALgAECgEJAQAAAA==.',
Ze='Zephy:BAAALgAECgUJCAAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRhJAQApAQApAAQJuRhJAQApAQAuAAQKfzQAAykACQlVIMEAAP8CACkACQlVIMEAAP8CAAIABAmyF6r5AAcBAAAA.',
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
