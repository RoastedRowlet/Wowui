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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Monk-Mistweaver','Priest-Discipline','Shaman-Restoration','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Arms','DeathKnight-Unholy','Priest-Shadow','DeathKnight-Blood','Warlock-Affliction','Hunter-Survival','Rogue-Assassination','Druid-Guardian','Rogue-Outlaw','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaronius:BAABLgAECn8oAAIBAAgJLQXYOgD9AAABAAgJLQXYOgD9AAAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8pAAMCAAkJwB1DJACFAgACAAkJwB1DJACFAgADAAQJ2BeKCwAeAQAAAA==.',
Ac='Acceptance:BAAALgAECgMJBAAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8sAAIEAAkJ3yH6DwDHAgAEAAkJ3yH6DwDHAgAAAA==.Adora:BAABLgAECn8iAAIEAAgJHh6/GgB5AgAEAAgJHh6/GgB5AgAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aelise:BAAALgADCgQJBAABLgAECgkJMAAFAFEfAA==.',
Ag='Agaliarept:BAACLgAFFH8KAAIGAAQJAgqlTAD2AAAGAAQJAgqlTAD2AAAuAAQKfxYAAwcACAkYC/sYAMgAAAYABwnpBuCLAAsBAAcABwkPC/sYAMgAAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAABLgAECn8WAAIIAAUJyhVMLQCpAAAIAAUJyhVMLQCpAAAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn86AAMJAAkJXRTREwDmAQAJAAkJXRTREwDmAQAGAAcJEAdqiwD7AAAAAA==.',
Ak='Akumajoe:BAAALgADCgcJBwAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAECgEJBAAAAA==.Alrook:BAABLgAECn8VAAMKAAgJ3xVsdAB6AQAKAAgJ3xVsdAB6AQALAAIJ4BFLcwBeAAAAAA==.Aluni:BAAALgAECgUJBQAAAA==.',
Am='Amethÿst:BAAALgAFFAIJAgAAAA==.Amoral:BAAALgAECgMJAwAAAA==.',
An='Angelneko:BAABLgAECn8xAAIMAAgJGA7ALgBXAQAMAAgJGA7ALgBXAQAAAA==.Anitabj:BAAALgAECgMJAwAAAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwANAAAAAA==.Arcaynemoon:BAABLgAECn8XAAIMAAYJWAM9VgDLAAAMAAYJWAM9VgDLAAAAAA==.Arcon:BAAALgAECgEJAQAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.',
As='Asterior:BAACLgAFFH8RAAMOAAYJvxdiAQBxAQAOAAUJmxtiAQBxAQAMAAEJTgjsQgBNAAAuAAQKfywAAg4ACQnzIFsDANYCAA4ACQnzIFsDANYCAAAA.',
Au='Aug:BAAALgAECgIJAgABLgAECggJFAAKAO4aAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgAECgEJAQAAAA==.Auroraa:BAABLgAECn8mAAIMAAcJyAb+RwDdAAAMAAcJyAb+RwDdAAAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgIJAgANAAAAAA==.',
Av='Avalectra:BAAALgAECgUJCAAAAA==.',
Ay='Aylana:BAAALgAECgYJBgAAAA==.',
Az='Azanost:BAAALgADCgQJBAABLgAECgkJJAAPAOAVAA==.Azmodeaz:BAABLgAECn81AAIDAAkJDBqzAQBuAgADAAkJDBqzAQBuAgAAAA==.',
Ba='Bajapanti:BAABLgAECn86AAIQAAkJvxtrAwCNAgAQAAkJvxtrAwCNAgAAAA==.Ballyhøø:BAABLgAECn8VAAIMAAkJSxF+RwDfAAAMAAkJSxF+RwDfAAAAAA==.Banchory:BAAALgADCgQJBQAAAA==.Bandaron:BAAALgAECgQJBwAAAA==.Baxstab:BAABLgAECn82AAIRAAkJ5xv3CwBZAgARAAkJ5xv3CwBZAgAAAA==.',
Bc='Bcam:BAAALgADCgYJBgAAAA==.',
Be='Beahon:BAAALgAECgQJCwAAAA==.Betruger:BAAALgAECgEJAQAAAA==.',
Bg='Bgeefiddy:BAAALgAECgMJAwAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJCgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackjak:BAAALgAECgEJAQAAAA==.Blackpatch:BAABLgAECn84AAMSAAkJZCJDBAANAwASAAkJZCJDBAANAwATAAgJ4ge0NgAbAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgUJCgAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAABLgAFFH8IAAIUAAQJoBUwHAAmAQAUAAQJoBUwHAAmAQAAAA==.Blooming:BAAALgAECgYJCwABLgAECggJHAAVAA4aAA==.Bloomsbeam:BAABLgAECn8cAAIGAAgJDBbeYQBYAQAGAAgJDBbeYQBYAQAAAA==.Bloomslinger:BAAALgADCgQJBAAAAA==.',
Bo='Bonerflex:BAACLgAFFH8HAAIWAAQJ+wq6JgAIAQAWAAQJ+wq6JgAIAQAuAAQKfyIAAxYACQkbGtIMAJcCABYACQkbGtIMAJcCABcABAlACtg/AGMAAAAA.Booneboy:BAABLgAECn8aAAMKAAgJTyHzIgBwAgAKAAgJTyHzIgBwAgAIAAQJVhDOKQC9AAAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8lAAMIAAkJXxUeGABOAQAIAAkJ7BIeGABOAQAKAAcJ3A21nAAxAQAAAA==.',
Br='Brennor:BAABLgAECn8zAAIKAAkJ5w79YQCiAQAKAAkJ5w79YQCiAQAAAA==.Brewslunt:BAACLgAFFH8QAAIYAAYJQRYsGQCAAQAYAAYJQRYsGQCAAQAuAAQKfywAAxgACAmfId8RAH8CABgACAmfId8RAH8CABIAAwnEC69iAIQAAAAA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Bubblydin:BAAALgAECgYJBgABLgAFFAMJBwAZAP0GAA==.Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAABLgAECn8jAAIaAAgJcxUbKgAGAgAaAAgJcxUbKgAGAgAAAA==.Cairyan:BAABLgAECn8yAAIHAAkJ5RsrBAB2AgAHAAkJ5RsrBAB2AgAAAA==.Caiya:BAAALgADCgcJBwABLgAECgkJOAARAOMkAA==.Capn:BAAALgADCgcJCQAAAA==.Carvil:BAABLgAECn8zAAMbAAkJGxYSBgD3AQAbAAkJGxYSBgD3AQAVAAMJjwdE5gCGAAAAAA==.Castalia:BAAALgAECgYJDgAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8TAAICAAYJ1hWfMACSAQACAAYJ1hWfMACSAQAuAAQKfykAAgIACAnmIyocAAYDAAIACAnmIyocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAYJEwACANYVAA==.Celithe:BAABLgAECn8dAAIKAAgJpxRqWQC2AQAKAAgJpxRqWQC2AQAAAA==.Cendrian:BAABLgAECn8WAAIMAAcJYQsiQAD+AAAMAAcJYQsiQAD+AAAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8tAAICAAkJfhyEKgBpAgACAAkJfhyEKgBpAgAAAA==.Charmshield:BAAALgAECgMJAwAAAA==.Cheezle:BAAALgAECgkJCAAAAA==.Chiafix:BAABLgAECn8cAAITAAgJDww1MAA6AQATAAgJDww1MAA6AQABLgAECgkJMgAaANYhAA==.Chipp:BAABLgAECn8UAAITAAcJ/CZpBwC3AgATAAcJ/CZpBwC3AgAAAA==.Chleo:BAAALgAECgMJBgAAAA==.Choco:BAACLgAFFH8kAAIcAAgJox3lAQDXAgAcAAgJox3lAQDXAgAuAAQKfykAAxwACQnvI+QFAOgCABwACQnvI+QFAOgCAB0AAQkVG9EfAEkAAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAgJJAAcAKMdAA==.Chudster:BAABLgAECn8gAAMdAAkJ/RWnBwCzAQAdAAkJ/RWnBwCzAQAeAAUJDQgyWwC8AAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAABLgAECn8fAAMXAAYJuR9QEgC5AQAXAAYJuR9QEgC5AQAfAAEJixHzcAAwAAAAAA==.Conqueror:BAAALgAECgYJEAABLgAFFAMJBgAMANQMAA==.',
Cr='Crawdaddy:BAABLgAECn8WAAIEAAcJJhJQaQBkAQAEAAcJJhJQaQBkAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAAALgAECgcJDwAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECggJGgAKAFcMAA==.Curmudge:BAABLgAECn9OAAIFAAkJrBfkGwBdAgAFAAkJrBfkGwBdAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgANAAAAAA==.Cybele:BAABLgAECn8XAAIBAAcJKgvnNQAaAQABAAcJKgvnNQAaAQAAAA==.',
Da='Dakunaito:BAABLgAECn8fAAIgAAkJTCSFEgDSAgAgAAkJTCSFEgDSAgAAAA==.Darachane:BAABLgAECn8uAAMhAAcJ1A5ZNAA+AQAhAAcJ1A5ZNAA+AQABAAEJxwIQdAAgAAAAAA==.Darovan:BAAALgADCgMJAwABLgAECgkJOAAiAK4iAA==.Dauglow:BAAALgAECgYJCQAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgADCggJDwAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAFFAEJAgAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAAALgAECgUJEwAAAA==.Deltia:BAABLgAECn8pAAIUAAgJYBfRIQDIAQAUAAgJYBfRIQDIAQAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAQJDwAEAKURAA==.Demonagent:BAAALgAECgYJDwAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8VAAMeAAYJ+hYRGwBqAQAeAAYJ+hYRGwBqAQAdAAIJfQ4ZCQBYAAAuAAQKfysAAx0ACQmFHtYJAEICAB0ACQlbHNYJAEICAB4ACAmaFsobAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8cAAIVAAgJDho4OADzAQAVAAgJDho4OADzAQAAAA==.',
Di='Dimebagg:BAAALgAECgYJCgAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8sAAMBAAgJdx2hEQBHAgABAAgJdx2hEQBHAgAZAAMJDgnvRACRAAAAAA==.Dokspades:BAAALgAECggJEgAAAA==.Dornoch:BAABLgAECn8hAAMLAAcJFiLjDQCqAgALAAcJFiLjDQCqAgAKAAEJ8AE1XAEjAAAAAA==.Dotzilla:BAABLgAECn8UAAQVAAUJ7iVlgAAzAQAVAAMJtSRlgAAzAQAjAAIJ9iVJHQDCAAAbAAIJbSQUKwBjAAAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJCQAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8tAAIKAAkJ2g1kZwCVAQAKAAkJ2g1kZwCVAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgYJDwANAAAAAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAABLgAFFH8HAAIGAAIJ+h0iaQCkAAAGAAIJ+h0iaQCkAAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8OAAIgAAMJwRn1hQDpAAAgAAMJwRn1hQDpAAAuAAQKfzQAAiAACQknId4UAMICACAACQknId4UAMICAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAgAAAA==.',
Ei='Einherja:BAAALgAECgIJAwAAAA==.Eisenhorn:BAAALgAECgUJBgAAAA==.',
El='Elessaria:BAABLgAECn8aAAIFAAgJCgb2ZwDzAAAFAAgJCgb2ZwDzAAAAAA==.Elfatheàrt:BAABLgAECn8WAAIKAAUJ8Q+R5gDJAAAKAAUJ8Q+R5gDJAAAAAA==.Elidrus:BAAALgADCgcJBwABLgAECgkJCQANAAAAAA==.Elira:BAAALgAECgEJAQAAAA==.',
Em='Emelgee:BAAALgAECgYJDgABLgAFFAMJBwAZAP0GAA==.Emofurry:BAAALgADCgIJAwAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECggJIgAEAB4eAA==.',
Es='Esika:BAAALgAFFAIJAwAAAA==.Estherras:BAABLgAECn8uAAIEAAkJpBlcIgBQAgAEAAkJpBlcIgBQAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgEJAQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fa='Fato:BAAALgAECgMJAwAAAA==.',
Fe='Feardotrun:BAABLgAECn8iAAMVAAgJnAxjbgBZAQAVAAgJ1gtjbgBZAQAbAAMJWQwhJACDAAAAAA==.Felicious:BAAALgAECgUJEQAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgADCgUJBQAAAA==.Finahlia:BAABLgAECn8gAAIFAAkJ7CFkBQBaAwAFAAkJ7CFkBQBaAwAAAA==.Finally:BAABLgAECn8jAAIUAAcJvQjDTwDnAAAUAAcJvQjDTwDnAAAAAA==.Firebat:BAAALgADCgcJBwABLgAECggJGgAKAE8hAA==.Firemage:BAABLgAECn8sAAIVAAkJLiPSBgAgAwAVAAkJLiPSBgAgAwAAAA==.Fizzanelf:BAABLgAECn8jAAIFAAcJOCOkEADEAgAFAAcJOCOkEADEAgAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAACLgAFFH8LAAIKAAQJpQR2VwDtAAAKAAQJpQR2VwDtAAAuAAQKfzIAAgoACQkKGgBRAO4BAAoACQkKGgBRAO4BAAAA.Friendo:BAABLgAECn85AAMOAAkJARlkBwBTAgAOAAkJARlkBwBTAgAMAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAFFAEJAQAAAA==.Frynied:BAAALgAECgMJAwABLgAECgkJIgABAKwaAA==.',
Fu='Furnost:BAABLgAECn8kAAIPAAkJ4BVVCAD4AQAPAAkJ4BVVCAD4AQAAAA==.Futnuraz:BAABLgAECn8fAAIfAAcJNAcDNwDdAAAfAAcJNAcDNwDdAAAAAA==.',
Fy='Fyrakkobama:BAAALgAECgkJBQABLgAECgkJGQAkAP0iAA==.Fyriat:BAABLgAECn8zAAICAAkJnwl3bwCVAQACAAkJnwl3bwCVAQAAAA==.',
Ga='Gazardiel:BAAALgAECgIJAgAAAA==.',
Ge='Getafix:BAAALgAECgYJCQABLgAECgkJMgAaANYhAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8sAAISAAgJZBzDDwBDAgASAAgJZBzDDwBDAgAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goldstorm:BAAALgADCgYJBgAAAA==.Goliath:BAAALgAECgUJCgABLgAECgkJGwAKAMcbAA==.Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8lAAIbAAkJIh0kAgCcAgAbAAkJIh0kAgCcAgAAAA==.Greybark:BAAALgADCgcJEQAAAA==.Griffindor:BAABLgAECn8zAAIKAAkJYBgaLwA5AgAKAAkJYBgaLwA5AgAAAA==.Grimfelborn:BAACLgAFFH8bAAMjAAYJgBL4BwDvAAAVAAUJMQ5aMwBiAQAjAAQJ4BH4BwDvAAAuAAQKfzAAAxUACQmGHLsxAEUCABUACQkaGbsxAEUCACMAAwlQIfAeALUAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAABLgAECn8gAAIaAAcJmR6wHABaAgAaAAcJmR6wHABaAgAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgAECgEJAQAAAA==.',
Ha='Hanicus:BAAALgAECgkJCQAAAA==.Hanoverfiste:BAABLgAECn8aAAIKAAgJVwwdiwBPAQAKAAgJVwwdiwBPAQAAAA==.Hapsburg:BAABLgAECn8rAAIYAAkJdxJAIgD4AQAYAAkJdxJAIgD4AQAAAA==.Havince:BAABLgAECn82AAIiAAkJ+CBcBgC0AgAiAAkJ+CBcBgC0AgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn84AAIKAAkJsB+oFAC+AgAKAAkJsB+oFAC+AgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Ig='Ignisdaemoni:BAAALgAECgIJAgABLgAECgkJIAAFAOwhAA==.',
Il='Illidai:BAAALgAECgYJEgAAAA==.Ilyndra:BAABLgAECn8xAAMfAAgJXCFJBwB5AgAfAAgJXCFJBwB5AgAXAAgJrRy6CwAkAgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn8zAAIWAAkJYBZeGQAcAgAWAAkJYBZeGQAcAgAAAA==.',
It='Ithea:BAABLgAECn8vAAICAAgJpCCYJgB6AgACAAgJpCCYJgB6AgAAAA==.',
Ja='Jackyll:BAAALgAECgIJAwAAAA==.Jaeson:BAEBLgAECn8iAAIVAAkJjhZvLQAdAgAVAAkJjhZvLQAdAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAgJHwALAGscAA==.',
Je='Jeef:BAAALgADCgEJAQABLgAECgkJGQAkAP0iAA==.Jeefrenzy:BAABLgAECn8ZAAMkAAkJ/SKMBADgAgAkAAkJ/SKMBADgAgAEAAIJkiG/8ABfAAAAAA==.Jeefwrld:BAAALgAECgQJBAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgYJDwAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8lAAQBAAkJeBnwHQDHAQABAAgJsRLwHQDHAQAZAAYJ8RSgIwB2AQAhAAUJDRSMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8aAAIlAAgJsg+kCQCaAQAlAAgJsg+kCQCaAQAAAA==.',
Jw='Jwise:BAAALgAECgkJBgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kamus:BAAALgAECgMJAwAAAA==.Kanabat:BAAALgAECgcJDgAAAA==.Karaden:BAAALgAECgUJBQAAAA==.Karawyn:BAABLgAECn8kAAIEAAgJ5Q5BPQC5AQAEAAgJ5Q5BPQC5AQABLgAECgcJCQANAAAAAA==.Karelix:BAAALgAECgIJAwAAAA==.Katrishy:BAACLgAFFH8bAAIhAAYJ8RZHDACCAQAhAAYJ8RZHDACCAQAuAAQKfy0AAyEACQkmHocWADMCACEACQkmHocWADMCAAEAAQlwBUSIACcAAAAA.Kaylierocks:BAAALgAECgEJAQAAAA==.Kayyfrost:BAAALgADCgIJAgAAAA==.Kazeral:BAAALgADCggJEQAAAA==.',
Ke='Keedrid:BAABLgAECn8WAAIgAAkJbh3QMQAvAgAgAAkJbh3QMQAvAgAAAA==.Keindis:BAAALgAECgcJDAABLgAECgcJLgAhANQOAA==.Kelaeno:BAAALgADCgkJCQABLgAECggJHQAGAAwHAA==.Kelemenohpea:BAABLgAECn8dAAIGAAgJDAf/jQD2AAAGAAgJDAf/jQD2AAAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8yAAIaAAkJ1iEcBgBFAwAaAAkJ1iEcBgBFAwAAAA==.Kruàlty:BAACLgAFFH8FAAIOAAUJkQ/4CQAAAQAOAAUJkQ/4CQAAAQAuAAQKfyQAAg4ACAmCHQgHAF4CAA4ACAmCHQgHAF4CAAAA.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwANAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgAECgEJAQABLgAECgcJFwADAFIKAA==.Legreecast:BAABLgAECn8XAAIDAAcJUgrcBwAYAQADAAcJUgrcBwAYAQAAAA==.Levlia:BAAALgADCgYJBgAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ+DJgCDAQABAAkJGQ+DJgCDAQAhAAIJ2wfaeAA8AAAZAAEJrgEYgQAbAAAAAA==.',
Lo='Loamuhwea:BAAALgAECgEJAQAAAA==.Lodur:BAABLgAECn8tAAIaAAkJlRskGQB1AgAaAAkJlRskGQB1AgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn8yAAImAAkJRBKgFQCUAQAmAAkJRBKgFQCUAQAAAA==.Losat:BAABLgAECn86AAIXAAkJzg0CFwB+AQAXAAkJzg0CFwB+AQAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8bAAIKAAkJxxuQJQBjAgAKAAkJxxuQJQBjAgAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwANAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAAALgAFFAMJBAAAAA==.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Mackavelian:BAAALgAECgEJAQABLgAECggJLgAYAIEXAA==.Mackkie:BAABLgAECn8uAAMYAAgJgRdmHQAaAgAYAAgJgRdmHQAaAgASAAYJ3wryRQDaAAAAAA==.Madonkadonk:BAABLgAECn82AAMdAAkJwhDVBgDNAQAdAAkJwhDVBgDNAQAeAAMJlAU+ggBIAAAAAA==.Maedai:BAABLgAECn81AAIYAAkJyhZkFwBLAgAYAAkJyhZkFwBLAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAACLgAFFH8HAAILAAMJyBnMKADVAAALAAMJyBnMKADVAAAuAAQKfzsAAwsACQk3HuoSAHACAAsACQk3HuoSAHACAAoABQm7EJv9AKwAAAAA.Magús:BAAALgAECgEJAgAAAA==.Maldive:BAABLgAECn8uAAIVAAkJZRG1QADVAQAVAAkJZRG1QADVAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Mallicia:BAACLgAFFH8SAAIBAAQJkSH8DABjAQABAAQJkSH8DABjAQAuAAQKfzYAAwEACQm4I5cDACADAAEACQm4I5cDACADABkABwlEGVIYAAICAAAA.Mallika:BAABLgAECn8mAAMaAAgJvxcJJgAdAgAaAAgJvxcJJgAdAgAUAAEJ3wnzngAsAAABLgAFFAQJEgABAJEhAA==.Mallistraza:BAAALgAECgIJAgABLgAFFAQJEgABAJEhAA==.Mallwizard:BAACLgAFFH8JAAIVAAMJjAYEfgC5AAAVAAMJjAYEfgC5AAAuAAQKfy0AAhUACQnEFZQ4ACkCABUACQnEFZQ4ACkCAAAA.Mandor:BAAALgADCgYJBgAAAA==.Mangopewpew:BAAALgAECgUJDwAAAA==.Martris:BAAALgADCgcJCwAAAA==.Massoflice:BAACLgAFFH8MAAIgAAQJSgkkcgAPAQAgAAQJSgkkcgAPAQAuAAQKfyYAAiAACQmEFuA5ABECACAACQmEFuA5ABECAAAA.Maxblaide:BAAALgAECgUJEQAAAA==.Maxilla:BAAALgADCgcJDQABLgAFFAQJBwAWAPsKAA==.',
Me='Menguli:BAAALgAECgIJAgAAAA==.Meridians:BAABLgAECn8bAAIYAAYJxxYKOAB6AQAYAAYJxxYKOAB6AQAAAA==.',
Mh='Mhataharii:BAAALgADCggJCAAAAA==.',
Mi='Mindhorn:BAACLgAFFH8MAAMUAAMJkxpwKgDfAAAUAAMJkxpwKgDfAAAaAAIJrRlvUgCaAAAuAAQKfycAAxQACAk0IT4PAHECABQACAk0IT4PAHECABoABAnTFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn8yAAIIAAkJAhkRCgAfAgAIAAkJAhkRCgAfAgAAAA==.Moctar:BAAALgADCgQJBAAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIKAAgJJyAcMwBWAgAKAAgJJyAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAECgkJIgAeAHYUAA==.Musashi:BAAALgAFFAIJAgAAAA==.Mustardhunt:BAAALgADCgcJDAAAAA==.',
My='Myriad:BAABLgAECn8tAAIXAAkJmh+mBQCwAgAXAAkJmh+mBQCwAgAAAA==.',
Na='Nakze:BAABLgAECn80AAIRAAkJAg9GFwDVAQARAAkJAg9GFwDVAQAAAA==.Namanari:BAAALgADCgkJCgAAAA==.Nancydru:BAAALgAECgQJBAAAAA==.Nardwuar:BAAALgAECgYJDAABLgAFFAEJAQANAAAAAA==.Naris:BAAALgADCgYJBgAAAA==.Nastyfigs:BAABLgAECn8xAAIEAAkJURwEGACKAgAEAAkJURwEGACKAgAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAECgkJDwAAAA==.',
Nh='Nhilas:BAAALgAECgQJDAAAAA==.',
Ni='Nightstryke:BAAALgAECgEJAQAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
No='Nork:BAAALgAECgIJAgAAAA==.',
Ny='Nyxaries:BAABLgAECn8WAAIiAAUJBRkzKAAKAQAiAAUJBRkzKAAKAQAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
On='Onenytestand:BAAALgAECgkJCAAAAA==.',
Or='Ordis:BAAALgADCgQJBAAAAA==.Orrana:BAAALgAECgEJAQAAAA==.',
Pa='Pablo:BAAALgAECgcJDgAAAA==.Pannacea:BAAALgAECgYJDQABLgAECgkJMgAaANYhAA==.Panzerblitz:BAABLgAECn8cAAImAAgJhQnpMQDOAAAmAAgJhQnpMQDOAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIbAAcJNQoFIABSAQAbAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgADCggJDAAAAA==.',
Pe='Pedrote:BAAALgADCgcJCgAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Peppert:BAAALgAECggJCAAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Ph='Phane:BAAALgAECgUJCQAAAA==.Phson:BAAALgADCgYJCAAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIEAAYJOCApKgANAgAEAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pincher:BAAALgADCgQJBAAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAABLgAECn8eAAIfAAYJQwgmOgDRAAAfAAYJQwgmOgDRAAAAAA==.Pretzelz:BAAALgAECgMJAwAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puertoricanj:BAAALgAECgMJAgAAAA==.Puffer:BAABLgAECn84AAICAAkJdhAAVgDUAQACAAkJdhAAVgDUAQAAAA==.',
Ra='Rabone:BAAALgAECgUJBQAAAA==.Raelaris:BAAALgAFFAIJAwABLgAFFAUJEQACANgjAA==.Raevyn:BAAALgAECgUJBQAAAA==.Raito:BAABLgAECn8gAAIKAAgJcgtLlQA9AQAKAAgJcgtLlQA9AQAAAA==.Rakshasa:BAACLgAFFH8MAAIVAAQJeh3hMABqAQAVAAQJeh3hMABqAQAuAAQKfykAAxUACQnJIkYLAPACABUACQnJIkYLAPACACMAAQkAALIhAGsAAAAA.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJCAABLgAECggJIgAEAB4eAA==.Rasetsungo:BAABLgAECn8fAAIBAAkJnxxRCwClAgABAAkJnxxRCwClAgAAAA==.Raura:BAABLgAECn8hAAIiAAcJuRKvIQA7AQAiAAcJuRKvIQA7AQAAAA==.Rayala:BAAALgAECgkJCQAAAA==.',
Re='Recalcitrent:BAAALgADCgYJCAAAAA==.Redblueblurr:BAABLgAECn8mAAIKAAgJLhDtagCOAQAKAAgJLhDtagCOAQAAAA==.Remi:BAABLgAECn8iAAMBAAgJrBqYEABUAgABAAgJrBqYEABUAgAhAAEJ3RO7eAA8AAAAAA==.Reveillark:BAABLgAECn8UAAIcAAYJYhdaEgCaAQAcAAYJYhdaEgCaAQAAAA==.',
Ro='Rolan:BAACLgAFFH8IAAIgAAQJDyVVJQCyAQAgAAQJDyVVJQCyAQAuAAQKfx4AAiAACQnYJNEUAMICACAACQnYJNEUAMICAAAA.Roogyrunes:BAAALgAECgcJCQABLgAECggJIQAKAHEjAA==.Rosalian:BAABLgAECn8zAAIFAAkJJhzWDwDLAgAFAAkJJhzWDwDLAgAAAA==.Rotiko:BAABLgAECn8iAAIaAAkJoQuXQwCRAQAaAAkJoQuXQwCRAQAAAA==.Roweene:BAABLgAECn8wAAInAAgJVAeJDgAXAQAnAAgJVAeJDgAXAQAAAA==.',
Ry='Ryez:BAAALgAECgEJAQAAAA==.',
['Rá']='Rágnar:BAABLgAECn8WAAQKAAgJUQ4UfwBlAQAKAAgJXA0UfwBlAQAIAAcJkgeOKQC/AAALAAMJSQYqbwBqAAAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgAECgUJBQAAAA==.',
Se='Seiko:BAAALgADCgEJAQAAAA==.Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8lAAMSAAcJzR9tGgDQAQASAAcJzR9tGgDQAQATAAEJEws+hQA8AAABLgAECgkJDgANAAAAAA==.Serenatee:BAABLgAECn8xAAIhAAkJnhAeHgDMAQAhAAkJnhAeHgDMAQAAAA==.',
Sh='Shadowkrak:BAAALgAECgEJAgAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgADCgcJBwAAAA==.Shamwow:BAAALgADCggJDwAAAA==.Shappens:BAAALgADCgcJEwABLgAECggJGgAKAFcMAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAAALgAECgYJEQAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAACLgAFFH8HAAIGAAMJcA1jYAC9AAAGAAMJcA1jYAC9AAAuAAQKfx0AAgYACQlzEu06ANABAAYACQlzEu06ANABAAAA.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgcJGQAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgADCgQJBAAAAA==.Simbà:BAAALgAECgYJDgAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8YAAMGAAcJGSHEIQCGAgAGAAcJGSHEIQCGAgAJAAEJ9hZVawA7AAABLgAECgkJGQAkAP0iAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAACLgAFFH8IAAIRAAMJ7BePIAAIAQARAAMJ7BePIAAIAQAuAAQKfxQAAxEABglfHjYeAJYBABEABQlfHjYeAJYBACUAAwlRGgUjAEEAAAAA.',
So='Soferfax:BAAALgADCgYJDQAAAA==.Sokroar:BAAALgAFFAIJBAAAAA==.Sonknight:BAABLgAECn8lAAMLAAYJswepUQDmAAALAAYJswepUQDmAAAKAAQJ9QJfTAFVAAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAIUAAgJZB3KFwAXAgAUAAgJZB3KFwAXAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn8/AAIkAAkJzQo6HQCuAQAkAAkJzQo6HQCuAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgQJCAAAAA==.Sto:BAABLgAECn8UAAIKAAgJ7hr1MgAqAgAKAAgJ7hr1MgAqAgAAAA==.Stratof:BAAALgADCgIJAgAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Sukerpunch:BAAALgADCgEJAQAAAA==.Supad:BAAALgADCgYJBwAAAA==.Superjpriest:BAAALgAECgUJDQABLgAFFAMJAwANAAAAAA==.Suria:BAABLgAECn8wAAIFAAkJUR+OCAAnAwAFAAkJUR+OCAAnAwAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgIJAgAAAA==.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Tahrovin:BAAALgAECgIJAgAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgADCgcJEwAAAA==.Taternutzz:BAAALgAECgEJAQAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8qAAIZAAgJLx69CgC4AgAZAAgJLx69CgC4AgAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn8+AAMLAAkJzwXcOgBSAQALAAkJzwXcOgBSAQAKAAgJ3gkvxAD2AAAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.',
Th='Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgAECgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Thundercups:BAABLgAECn82AAIoAAkJPiFdAwDFAgAoAAkJPiFdAwDFAgAAAA==.',
Ti='Tigerstarr:BAACLgAFFH8KAAIgAAMJ1BDzkADbAAAgAAMJ1BDzkADbAAAuAAQKfx4AAyAACQm7E9Q3ABgCACAACQm7E9Q3ABgCAA8AAQlRBioZACoAAAAA.Timboslicé:BAAALgAECgcJCwAAAA==.Tinyshieva:BAABLgAECn8aAAMBAAYJTA4HPAD1AAABAAYJTA4HPAD1AAAhAAQJTwMXYgCAAAAAAA==.Tizuki:BAAALgAECgIJAwAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgkJBwAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn8wAAIbAAgJCxx+BAArAgAbAAgJCxx+BAArAgAAAA==.Treenn:BAABLgAECn8YAAMaAAYJ6hSiSgB3AQAaAAYJ6hSiSgB3AQAUAAMJ/wSufQBlAAAAAA==.Triplock:BAAALgAECgUJBgAAAA==.Trolcain:BAABLgAECn8uAAIgAAkJLiR/BwAyAwAgAAkJLiR/BwAyAwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgkJLgAgAC4kAA==.',
Ty='Tyrix:BAABLgAECn8hAAIKAAgJcSMrGQCiAgAKAAgJcSMrGQCiAgAAAA==.Tyránt:BAACLgAFFH8PAAIEAAQJpRFCPgAlAQAEAAQJpRFCPgAlAQAuAAQKfzEAAwQACQlNIwsLAPMCAAQACQlNIwsLAPMCABAAAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAITAAYJ2BmCQABCAQATAAYJ2BmCQABCAQAAAA==.',
Va='Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCwAAAA==.Valerossi:BAABLgAECn84AAIkAAkJlx93BADiAgAkAAkJlx93BADiAgAAAA==.Valha:BAABLgAECn8mAAIJAAkJeRLwFQDJAQAJAAkJeRLwFQDJAQAAAA==.Valira:BAAALgADCggJCQABLgAECggJIgAEAB4eAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgADCgYJBgAAAA==.Varleyna:BAAALgAECgMJAwABLgAFFAQJEgABAJEhAA==.Varteras:BAABLgAECn8yAAMjAAkJsxuSBQAdAgAjAAgJghuSBQAdAgAVAAgJnxLOUQChAQAAAA==.',
Ve='Veleiri:BAABLgAECn8tAAICAAgJ/hGEZwCnAQACAAgJ/hGEZwCnAQAAAA==.Velenal:BAAALgAECgQJDAAAAA==.Vellron:BAABLgAECn8uAAIEAAkJhw5sQADVAQAEAAkJhw5sQADVAQAAAA==.',
Vo='Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAACLgAFFH8SAAMGAAUJbRipTQDzAAAGAAQJlRupTQDzAAAJAAIJHA2yHQCJAAAuAAQKfxYAAwkABgm1I68WAMEBAAkABgkKI68WAMEBAAYABAkfH9tlAE4BAAAA.Wardkbriggle:BAACLgAFFH8OAAIiAAYJkx5PCgC4AQAiAAYJkx5PCgC4AQAuAAQKfyEAAiIACQmoI0IDAAkDACIACQmoI0IDAAkDAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8YAAITAAYJxRwCCQDdAQATAAYJxRwCCQDdAQAuAAQKfyAAAhMACQkeIJEKAIMCABMACQkeIJEKAIMCAAAA.',
Wi='Wifi:BAAALgAECgIJBwAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMiAAYJeAWFNwCGAAAiAAQJGQaFNwCGAAAPAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn84AAICAAgJExPvZgCoAQACAAgJExPvZgCoAQAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn84AAQRAAkJ4yTDAQBHAwARAAkJsyTDAQBHAwAlAAcJASMUBAB1AgAnAAYJth2LCQCHAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJCwABLgAECgkJOAARAOMkAA==.',
Xh='Xhared:BAABLgAECn84AAIiAAkJriKPAwABAwAiAAkJriKPAwABAwAAAA==.',
Ya='Yahtzee:BAAALgAECgMJBgAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIGAAgJBwMjtACyAAAGAAgJBwMjtACyAAAAAA==.',
Ye='Yesenia:BAAALgADCgYJBgAAAA==.',
Yk='Ykszord:BAAALgAECgEJAQAAAA==.',
Ze='Zephy:BAAALgAECgYJCgAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Åe']='Åeon:BAABLgAECn8aAAIEAAcJGRBbbQBaAQAEAAcJGRBbbQBaAQAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRjEAQAZAQApAAQJuRjEAQAZAQAuAAQKfzQAAykACQlVIMEAAP8CACkACQlVIMEAAP8CAAIABAmyF6r5AAcBAAAA.',
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
