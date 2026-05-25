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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Warlock-Demonology','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Priest-Shadow','DeathKnight-Blood','Shaman-Elemental','Priest-Discipline','Warlock-Affliction','Warrior-Fury','Hunter-Survival','Rogue-Assassination','Druid-Guardian','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaronius:BAABLgAECn8iAAIBAAgJEASpNgD/AAABAAgJEASpNgD/AAAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8mAAMCAAgJRhusOwAPAgACAAgJRhusOwAPAgADAAQJ2BeKCwAeAQAAAA==.',
Ac='Acceptance:BAAALgAECgMJBAAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8nAAIEAAgJzSDHGgBcAgAEAAgJzSDHGgBcAgAAAA==.Adora:BAABLgAECn8VAAIEAAcJnBeBVQB1AQAEAAcJnBeBVQB1AQAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aelise:BAAALgADCgQJBAABLgAECgkJMAAFAFEfAA==.Aeðn:BAABLgAECn8ZAAIEAAcJGRA6XwBbAQAEAAcJGRA6XwBbAQAAAA==.',
Ag='Agaliarept:BAACLgAFFH8GAAIGAAMJQgNjWQCoAAAGAAMJQgNjWQCoAAAuAAQKfxYAAwcACAkYC1AVANQAAAYABwnpBuCLAAsBAAcABwkPC1AVANQAAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAAALgAECgUJEgAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn8uAAMIAAgJzBOdFQCmAQAIAAgJzBOdFQCmAQAGAAEJxgOWAwEhAAAAAA==.',
Ak='Akumajoe:BAAALgADCgcJBwAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAECgEJBAAAAA==.Alrook:BAABLgAECn8UAAMJAAgJ3xUAYwCLAQAJAAgJ3xUAYwCLAQAKAAIJ4BFfaQBfAAAAAA==.Aluni:BAAALgAECgUJBQAAAA==.',
Am='Amoral:BAAALgAECgMJAwAAAA==.',
An='Angelneko:BAABLgAECn8rAAILAAgJ3A3oKQBTAQALAAgJ3A3oKQBTAQAAAA==.Anitabj:BAAALgADCgYJBgAAAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwAMAAAAAA==.Arcaynemoon:BAABLgAECn8XAAILAAYJWAM9VgDLAAALAAYJWAM9VgDLAAAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.',
As='Asterior:BAACLgAFFH8QAAINAAUJmxtiAQBxAQANAAUJmxtiAQBxAQAuAAQKfyUAAg0ACAnDIAkFAHwCAA0ACAnDIAkFAHwCAAAA.',
Au='Aug:BAAALgAECgIJAgABLgAECggJDQAMAAAAAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgADCgIJAgAAAA==.Auroraa:BAABLgAECn8lAAILAAYJ9QZnSAC4AAALAAYJ9QZnSAC4AAAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgIJAgAMAAAAAA==.',
Av='Avalectra:BAAALgAECgMJBgAAAA==.',
Ay='Aylana:BAAALgAECgYJBgAAAA==.',
Az='Azanost:BAAALgADCgQJBAABLgAECgkJJAAOAOAVAA==.Azmodeaz:BAABLgAECn8qAAIDAAgJ1RbrAgDpAQADAAgJ1RbrAgDpAQAAAA==.',
Ba='Bajapanti:BAABLgAECn86AAIPAAkJvxuzAgCdAgAPAAkJvxuzAgCdAgAAAA==.Ballyhøø:BAABLgAECn8VAAILAAkJSxG/PQDmAAALAAkJSxG/PQDmAAAAAA==.Banchory:BAAALgADCgQJBQAAAA==.Bandaron:BAAALgAECgQJBAAAAA==.Baxstab:BAABLgAECn82AAIQAAkJ5xuECQBqAgAQAAkJ5xuECQBqAgAAAA==.',
Be='Beahon:BAAALgAECgQJCQAAAA==.Betruger:BAAALgAECgEJAQAAAA==.',
Bg='Bgeefiddy:BAAALgAECgIJAgAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJCgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackjak:BAAALgAECgEJAQAAAA==.Blackpatch:BAABLgAECn84AAMRAAkJZCIlAwAZAwARAAkJZCIlAwAZAwASAAgJ4gd4MQAeAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgQJBwAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAAALgAFFAIJAgAAAA==.Blooming:BAAALgAECgYJCQABLgAECggJGwATAA4aAA==.Bloomsbeam:BAABLgAECn8cAAIGAAgJDBZ8VABmAQAGAAgJDBZ8VABmAQAAAA==.Bloomslinger:BAAALgADCgQJBAAAAA==.',
Bo='Booneboy:BAABLgAECn8UAAMJAAYJGiDgVgCnAQAJAAYJGiDgVgCnAQAUAAQJVhCjJAC/AAAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8iAAMUAAkJcBOxFwAyAQAJAAcJ3A1DhwBAAQAUAAkJ/RCxFwAyAQABLgAFFAQJDwAVAPIRAA==.',
Br='Brennor:BAABLgAECn8zAAIJAAkJ5w7xTwC5AQAJAAkJ5w7xTwC5AQAAAA==.Brewslunt:BAACLgAFFH8PAAIWAAUJQRjRBwBAAQAWAAUJQRjRBwBAAQAuAAQKfysAAxYACAmfIYAOAIICABYACAmfIYAOAIICABEAAwnEC0VWAIYAAAAA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAABLgAECn8XAAIXAAYJcRI6SQBWAQAXAAYJcRI6SQBWAQAAAA==.Cairyan:BAABLgAECn8mAAIHAAgJvBoRBgAPAgAHAAgJvBoRBgAPAgAAAA==.Caiya:BAAALgADCgcJBwABLgAECgkJOAAQAOMkAA==.Capn:BAAALgADCgcJCAAAAA==.Carvil:BAABLgAECn8zAAMYAAkJGxbEBAAAAgAYAAkJGxbEBAAAAgATAAMJjwfS0gCKAAAAAA==.Castalia:BAAALgAECgQJCAAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8NAAICAAUJ/RJASgA0AQACAAUJ/RJASgA0AQAuAAQKfykAAgIACAnmIyocAAYDAAIACAnmIyocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAUJDQACAP0SAA==.Celithe:BAABLgAECn8dAAIJAAgJpxQPSgDJAQAJAAgJpxQPSgDJAQAAAA==.Cendrian:BAABLgAECn8WAAILAAcJYQtoOAAAAQALAAcJYQtoOAAAAQAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8tAAICAAkJfhyaIwBzAgACAAkJfhyaIwBzAgAAAA==.Charmshield:BAAALgAECgMJAwAAAA==.Chiafix:BAABLgAECn8bAAISAAgJ3gpPLQAzAQASAAgJ3gpPLQAzAQABLgAECgkJMgAXANYhAA==.Chipp:BAAALgAFFAEJBAAAAA==.Chleo:BAAALgAECgMJBgAAAA==.Choco:BAACLgAFFH8eAAIZAAcJ3B05AwBmAgAZAAcJ3B05AwBmAgAuAAQKfykAAxkACQnvI+QFAOgCABkACQnvI+QFAOgCABoAAQkVG34cAEoAAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAcJHgAZANwdAA==.Chudster:BAABLgAECn8gAAMaAAkJ/RUgBgDKAQAaAAkJ/RUgBgDKAQAbAAUJDQjhTgDHAAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAABLgAECn8ZAAMcAAYJ2BmxFgBmAQAcAAYJ2BmxFgBmAQAdAAEJixFdXgAzAAAAAA==.Conqueror:BAAALgAECgYJEAABLgAECgkJMgAFAKQZAA==.',
Cr='Crawdaddy:BAABLgAECn8UAAIEAAYJBREQeQAeAQAEAAYJBREQeQAeAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAAALgAECgcJDwAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECgYJFAAJAN8JAA==.Curmudge:BAABLgAECn9EAAIFAAkJdRYwGgBQAgAFAAkJdRYwGgBQAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgAMAAAAAA==.Cybele:BAABLgAECn8UAAIBAAYJqwxeMwAUAQABAAYJqwxeMwAUAQAAAA==.',
Da='Dakunaito:BAABLgAECn8aAAIeAAcJGSXzNwD9AQAeAAcJGSXzNwD9AQAAAA==.Darachane:BAABLgAECn8dAAMfAAYJZg4ONwARAQAfAAYJZg4ONwARAQABAAEJxwJFagAhAAAAAA==.Darovan:BAAALgADCgMJAwABLgAECggJLQAgALshAA==.Dauglow:BAAALgAECgMJAwAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgADCgEJAQAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAECgcJCwAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAAALgAECgUJEwAAAA==.Deltia:BAABLgAECn8jAAIhAAgJmhYzHwC8AQAhAAgJmhYzHwC8AQAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAQJCwAEAKURAA==.Demonagent:BAAALgAECgYJDgAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8SAAMbAAUJjBp2GwAzAQAbAAUJjBp2GwAzAQAaAAEJ2BYZCQBYAAAuAAQKfyoAAxoACQkvHtYJAEICABoACQkEHNYJAEICABsACAmaFsobAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8bAAITAAgJDhpfMAD/AQATAAgJDhpfMAD/AQAAAA==.',
Di='Dimebagg:BAAALgAECgQJBQAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8sAAMBAAgJdx2XDgBWAgABAAgJdx2XDgBWAgAiAAMJDgnvRACRAAAAAA==.Dokspades:BAAALgAECggJDQAAAA==.Dornoch:BAAALgAECgUJEwAAAA==.Dotzilla:BAAALgAECgUJEAAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJBgAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8oAAIJAAgJRQ0mdwBgAQAJAAgJRQ0mdwBgAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgYJDgAMAAAAAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAABLgAFFH8GAAIGAAIJ+h2FVgCzAAAGAAIJ+h2FVgCzAAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8LAAIeAAMJghMCcgDoAAAeAAMJghMCcgDoAAAuAAQKfzAAAh4ACQkJIa4UAKsCAB4ACQkJIa4UAKsCAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAgAAAA==.',
Ei='Eisenhorn:BAAALgAECgUJBgAAAA==.',
El='Elessaria:BAABLgAECn8UAAIFAAYJ5Qa4bwDEAAAFAAYJ5Qa4bwDEAAAAAA==.Elfatheàrt:BAAALgAECgUJEgAAAA==.Elira:BAAALgAECgEJAQAAAA==.',
Em='Emelgee:BAAALgAECgQJBAABLgAECgkJGwAiABsOAA==.Emofurry:BAAALgADCgIJAwAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgcJFQAEAJwXAA==.',
Es='Esika:BAAALgAFFAIJAwAAAA==.Estherras:BAABLgAECn8pAAIEAAgJsBVVKgAMAgAEAAgJsBVVKgAMAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgEJAQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fe='Feardotrun:BAABLgAECn8dAAMTAAcJ7gzweAAyAQATAAcJygvweAAyAQAYAAMJWQz0HwCGAAAAAA==.Felicious:BAAALgAECgQJDQAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgAMAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgADCgUJBQAAAA==.Finahlia:BAABLgAECn8fAAIFAAkJ7CFfBABdAwAFAAkJ7CFfBABdAwAAAA==.Finally:BAABLgAECn8VAAIhAAUJKQi2XgCXAAAhAAUJKQi2XgCXAAAAAA==.Firebat:BAAALgADCgcJBwABLgAECgYJFAAJABogAA==.Firemage:BAABLgAECn8iAAITAAkJ6iDMHABeAgATAAkJ6iDMHABeAgAAAA==.Fizzanelf:BAABLgAECn8VAAIFAAUJQiXYIQAWAgAFAAUJQiXYIQAWAgAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAABLgAECn8tAAIJAAkJ/RYAUQDuAQAJAAkJ/RYAUQDuAQAAAA==.Friendo:BAABLgAECn85AAMNAAkJARnoBQBeAgANAAkJARnoBQBeAgALAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAECgkJBAAAAA==.',
Fu='Furnost:BAABLgAECn8kAAIOAAkJ4BVrBgD9AQAOAAkJ4BVrBgD9AQAAAA==.Futnuraz:BAAALgAECgUJEQAAAA==.',
Fy='Fyriat:BAABLgAECn8uAAICAAgJZgkvgwBUAQACAAgJZgkvgwBUAQAAAA==.',
Ga='Gazardiel:BAAALgAECgIJAgAAAA==.',
Ge='Getafix:BAAALgAECgYJCAABLgAECgkJMgAXANYhAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8mAAIRAAgJJRhEFADxAQARAAgJJRhEFADxAQAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goliath:BAAALgAECgQJBAABLgAECgkJGgAJAKMbAA==.Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8lAAIYAAkJIh1/AQCoAgAYAAkJIh1/AQCoAgAAAA==.Greybark:BAAALgADCgcJCwAAAA==.Griffindor:BAABLgAECn8zAAIJAAkJYBieJQBNAgAJAAkJYBieJQBNAgAAAA==.Grimfelborn:BAACLgAFFH8UAAMTAAUJyg6lRQAZAQATAAQJyg6lRQAZAQAjAAEJAABeIAAAAAAuAAQKfy4AAxMACAlNG7sxAEUCABMACAkYG7sxAEUCACMAAgmcHx8aAKcAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAABLgAECn8YAAIXAAYJuyAfIAAiAgAXAAYJuyAfIAAiAgAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgADCgkJDQAAAA==.',
Ha='Hanicus:BAAALgAECgcJCAAAAA==.Hanoverfiste:BAABLgAECn8UAAIJAAYJ3wkRuQDvAAAJAAYJ3wkRuQDvAAAAAA==.Hapsburg:BAABLgAECn8rAAIWAAkJdxJ5HAD0AQAWAAkJdxJ5HAD0AQAAAA==.Havince:BAABLgAECn82AAIgAAkJ+CDBBADCAgAgAAkJ+CDBBADCAgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn84AAIJAAkJsB+eDwDPAgAJAAkJsB+eDwDPAgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Il='Illidai:BAAALgAECgYJEgAAAA==.Ilyndra:BAABLgAECn8rAAMdAAgJXCF4BgB0AgAdAAgJXCF4BgB0AgAcAAgJrRx7CQA5AgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn8uAAIkAAgJphXVIgC3AQAkAAgJphXVIgC3AQAAAA==.',
It='Ithea:BAABLgAECn8uAAICAAgJpiDwHwCEAgACAAgJpiDwHwCEAgAAAA==.',
Ja='Jaeson:BAEBLgAECn8iAAITAAkJjhZVJgAqAgATAAkJjhZVJgAqAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAcJGQAKALkXAA==.',
Je='Jeef:BAAALgADCgEJAQABLgAECgkJGQAlAP0iAA==.Jeefrenzy:BAABLgAECn8ZAAMlAAkJ/SJGAwDvAgAlAAkJ/SJGAwDvAgAEAAIJkiHG0ABjAAAAAA==.Jeefwrld:BAAALgAECgQJBAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgYJDwAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8lAAQBAAkJeBk2GQDaAQABAAgJsRI2GQDaAQAiAAYJ8RSgIwB2AQAfAAUJDRSMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8UAAImAAYJCQyQDwAMAQAmAAYJCQyQDwAMAQAAAA==.',
Jw='Jwise:BAAALgADCgcJCgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kanabat:BAAALgAECgcJDgAAAA==.Karaden:BAAALgAECgMJAwAAAA==.Karawyn:BAABLgAECn8eAAIEAAgJyw5BPQC5AQAEAAgJyw5BPQC5AQABLgAECgcJCAAMAAAAAA==.Karelix:BAAALgADCgcJCwAAAA==.Katrishy:BAACLgAFFH8UAAIfAAUJoRRIEQA/AQAfAAUJoRRIEQA/AQAuAAQKfysAAx8ACAlhHYcWADMCAB8ACAlhHYcWADMCAAEAAQlwBUSIACcAAAAA.Kayyfrost:BAAALgADCgIJAgAAAA==.Kazeral:BAAALgADCggJDwAAAA==.',
Ke='Keedrid:BAABLgAECn8UAAIeAAkJJx1CKwAwAgAeAAkJJx1CKwAwAgAAAA==.Keindis:BAAALgAECgMJAwABLgAECgYJHQAfAGYOAA==.Kelaeno:BAAALgADCgEJAQABLgAECggJHQAGAAwHAA==.Kelemenohpea:BAABLgAECn8dAAIGAAgJDAd+fAD/AAAGAAgJDAd+fAD/AAAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8yAAIXAAkJ1iFaBABMAwAXAAkJ1iFaBABMAwAAAA==.Kruàlty:BAABLgAECn8WAAINAAcJLhq3EQBmAQANAAcJLhq3EQBmAQAAAA==.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwAMAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgAECgEJAQABLgAECgUJDQAMAAAAAA==.Legreecast:BAAALgAECgUJDQAAAA==.Levlia:BAAALgADCgYJBgAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ9KIACdAQABAAkJGQ9KIACdAQAfAAIJ2wclaQA8AAAiAAEJrgGvbwAbAAAAAA==.',
Lo='Lodur:BAABLgAECn8oAAIXAAgJjRwAHAA+AgAXAAgJjRwAHAA+AgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn8tAAInAAgJAhS6FAByAQAnAAgJAhS6FAByAQAAAA==.Losat:BAABLgAECn86AAIcAAkJzg0XEwCSAQAcAAkJzg0XEwCSAQAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8aAAIJAAkJoxtWHwBsAgAJAAkJoxtWHwBsAgAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwAMAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAAALgAECgkJEwAAAA==.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Mackavelian:BAAALgAECgEJAQABLgAECggJJwAWADcVAA==.Mackkie:BAABLgAECn8nAAMWAAgJNxUFHQDvAQAWAAgJNxUFHQDvAQARAAYJ3wpcPADhAAAAAA==.Madonkadonk:BAABLgAECn82AAMaAAkJwhCCBQDlAQAaAAkJwhCCBQDlAQAbAAMJlAX6cwBIAAAAAA==.Maedai:BAABLgAECn81AAIWAAkJyhZXEwBKAgAWAAkJyhZXEwBKAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAACLgAFFH8HAAIKAAMJyBn5IQDiAAAKAAMJyBn5IQDiAAAuAAQKfzsAAwoACQk3HqgPAHkCAAoACQk3HqgPAHkCAAkABQm7EPvfALYAAAAA.Magús:BAAALgAECgEJAQAAAA==.Maldive:BAABLgAECn8uAAITAAkJZRFbNwDjAQATAAkJZRFbNwDjAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Mallicia:BAACLgAFFH8OAAIBAAQJkSFfCQB5AQABAAQJkSFfCQB5AQAuAAQKfzIAAwEACQmtIZcDACADAAEACQmtIZcDACADACIABwlEGUwUAA0CAAAA.Mallika:BAABLgAECn8ZAAIXAAgJMhTqLwDGAQAXAAgJMhTqLwDGAQABLgAFFAQJDgABAJEhAA==.Mallwizard:BAACLgAFFH8GAAITAAIJbAa0jwB8AAATAAIJbAa0jwB8AAAuAAQKfy0AAhMACQnEFZQ4ACkCABMACQnEFZQ4ACkCAAAA.Mandor:BAAALgADCgYJBgAAAA==.Mangopewpew:BAAALgAECgUJDwAAAA==.Martris:BAAALgADCgcJCwAAAA==.Massoflice:BAACLgAFFH8GAAIeAAMJgwnMfwDUAAAeAAMJgwnMfwDUAAAuAAQKfyUAAh4ACQmEFsoxABQCAB4ACQmEFsoxABQCAAAA.Maxblaide:BAAALgAECgUJDQAAAA==.Maxilla:BAAALgADCgcJDQABLgAFFAMJBwAKAMgZAA==.',
Me='Menguli:BAAALgAECgIJAgAAAA==.Meridians:BAABLgAECn8bAAIWAAYJxxZNLQB5AQAWAAYJxxZNLQB5AQAAAA==.',
Mh='Mhataharii:BAAALgADCggJCAAAAA==.',
Mi='Mindhorn:BAACLgAFFH8KAAMhAAMJkxqFIAD2AAAhAAMJkxqFIAD2AAAXAAIJwQp5UAB2AAAuAAQKfycAAyEACAk0IZIMAHgCACEACAk0IZIMAHgCABcABAnTFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn8yAAIUAAkJAhklCAAmAgAUAAkJAhklCAAmAgAAAA==.Moctar:BAAALgADCgQJBAAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIJAAgJJyAcMwBWAgAJAAgJJyAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAECgkJIgAbAHYUAA==.Musashi:BAAALgAECgUJCAAAAA==.Mustardhunt:BAAALgADCgQJBQAAAA==.',
My='Myriad:BAABLgAECn8oAAIcAAgJgR/cCABHAgAcAAgJgR/cCABHAgAAAA==.',
Na='Nakze:BAABLgAECn8vAAIQAAgJeQyJHQB/AQAQAAgJeQyJHQB/AQAAAA==.Namanari:BAAALgADCgkJCgAAAA==.Naris:BAAALgADCgYJBgAAAA==.Nastyfigs:BAABLgAECn8qAAIEAAkJzRu0EgCSAgAEAAkJzRu0EgCSAgAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAECggJDAAAAA==.',
Nh='Nhilas:BAAALgAECgQJCAAAAA==.',
Ni='Nightstryke:BAAALgAECgEJAQAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
Ny='Nyxaries:BAABLgAECn8UAAIgAAUJHRd6JQD4AAAgAAUJHRd6JQD4AAAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
On='Onenytestand:BAAALgAECgkJAgAAAA==.',
Or='Ordis:BAAALgADCgQJBAAAAA==.',
Pa='Pablo:BAAALgAECgQJCAAAAA==.Paladus:BAAALgAECgcJEgAAAA==.Pannacea:BAAALgAECgYJCAABLgAECgkJMgAXANYhAA==.Panzerblitz:BAABLgAECn8bAAInAAgJwAj3KADLAAAnAAgJwAj3KADLAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIYAAcJNQoFIABSAQAYAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgADCggJDAAAAA==.',
Pe='Pedrote:BAAALgADCgUJBgAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Peppert:BAAALgAECggJCAAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Ph='Phane:BAAALgAECgUJBQAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIEAAYJOCApKgANAgAEAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pincher:BAAALgADCgQJBAAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAABLgAECn8YAAIdAAYJcAdjOgCoAAAdAAYJcAdjOgCoAAAAAA==.Pretzelz:BAAALgADCgYJCgAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puertoricanj:BAAALgAECgMJAgAAAA==.Puffer:BAABLgAECn84AAICAAkJdhC8SgDfAQACAAkJdhC8SgDfAQAAAA==.',
Ra='Rabone:BAAALgAECgEJAQAAAA==.Raelaris:BAAALgAFFAIJAwABLgAFFAUJCwACAHscAA==.Raito:BAABLgAECn8gAAIJAAgJcgv1fwBOAQAJAAgJcgv1fwBOAQAAAA==.Rakshasa:BAACLgAFFH8GAAITAAMJ0g9FXADfAAATAAMJ0g9FXADfAAAuAAQKfykAAxMACQnJIrMIAPsCABMACQnJIrMIAPsCACMAAQkAALIhAGsAAAAA.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJBwABLgAECgcJFQAEAJwXAA==.Rasetsungo:BAABLgAECn8fAAIBAAkJnxzuCAC2AgABAAkJnxzuCAC2AgAAAA==.Raura:BAAALgAECgUJEwAAAA==.',
Re='Recalcitrent:BAAALgADCgYJCAAAAA==.Redblueblurr:BAABLgAECn8hAAIJAAgJFw+OXQCXAQAJAAgJFw+OXQCXAQAAAA==.Remi:BAABLgAECn8XAAIBAAgJIhr0DgBRAgABAAgJIhr0DgBRAgAAAA==.Reveillark:BAABLgAECn8UAAIZAAYJYhe/EACZAQAZAAYJYhe/EACZAQAAAA==.',
Ro='Rolan:BAACLgAFFH8FAAIeAAIJ2SZmdQDjAAAeAAIJ2SZmdQDjAAAuAAQKfx4AAh4ACQnYJDgQAMsCAB4ACQnYJDgQAMsCAAAA.Roogyrunes:BAAALgAECgQJBAABLgAECggJIAAJAHEjAA==.Rosalian:BAABLgAECn8uAAIFAAgJ6hzqEwCJAgAFAAgJ6hzqEwCJAgAAAA==.Rotiko:BAABLgAECn8dAAIXAAgJ8Qt7RQBlAQAXAAgJ8Qt7RQBlAQAAAA==.Roweene:BAABLgAECn8qAAIoAAgJmQZPDQAMAQAoAAgJmQZPDQAMAQAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgAECgEJAQAAAA==.',
Se='Seiko:BAAALgADCgEJAQAAAA==.Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8lAAMRAAcJzR+iFgDYAQARAAcJzR+iFgDYAQASAAEJEws+hQA8AAAAAA==.Serenatee:BAABLgAECn8xAAIfAAkJnhChGQDTAQAfAAkJnhChGQDTAQAAAA==.',
Sh='Shadowkrak:BAAALgADCgMJAwAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgADCgcJBwAAAA==.Shamwow:BAAALgADCggJDgAAAA==.Shappens:BAAALgADCgcJDAABLgAECgYJFAAJAN8JAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAAALgAECgYJEAAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAACLgAFFH8HAAIGAAMJcA21TgDNAAAGAAMJcA21TgDNAAAuAAQKfx0AAgYACQlzEnkxAOABAAYACQlzEnkxAOABAAAA.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgcJDQAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgADCgQJBAAAAA==.Simbà:BAAALgAECgYJDgAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8XAAMGAAcJGSHEIQCGAgAGAAcJGSHEIQCGAgAIAAEJ9hZVawA7AAABLgAECgkJGQAlAP0iAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAAALgAFFAIJAgAAAA==.',
So='Soferfax:BAAALgADCgYJCAAAAA==.Sokroar:BAAALgAECgQJBAABLgAFFAIJAwAMAAAAAA==.Sonknight:BAABLgAECn8cAAMKAAYJzgR2UADLAAAKAAYJzgR2UADLAAAJAAQJ9QJsKAFXAAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAIhAAgJZB2cEwAjAgAhAAgJZB2cEwAjAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn8yAAIlAAkJzQqqGQCzAQAlAAkJzQqqGQCzAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgIJBAAAAA==.Sto:BAAALgAECggJDQAAAA==.Stratof:BAAALgADCgIJAgAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Sukerpunch:BAAALgADCgEJAQAAAA==.Supad:BAAALgADCgYJBwAAAA==.Superball:BAABLgAECn8YAAMkAAkJ4BS9FgAUAgAkAAkJ4BS9FgAUAgAcAAQJQArvNwBrAAABLgAFFAMJBwAKAMgZAA==.Superjpriest:BAAALgAECgQJCgABLgAFFAEJAQAMAAAAAA==.Suria:BAABLgAECn8wAAIFAAkJUR8yBwApAwAFAAkJUR8yBwApAwAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgIJAgAAAA==.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Tahrovin:BAAALgAECgEJAQAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgADCgcJEwAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8kAAIiAAgJwRuvCwCIAgAiAAgJwRuvCwCIAgAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn8+AAMKAAkJzwXXNABUAQAKAAkJzwXXNABUAQAJAAgJ3glfrAACAQAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.',
Th='Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgADCgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Thundercups:BAABLgAECn82AAIVAAkJPiGHAgDPAgAVAAkJPiGHAgDPAgAAAA==.',
Ti='Tigerstarr:BAACLgAFFH8GAAIeAAMJXwl0gQDRAAAeAAMJXwl0gQDRAAAuAAQKfxkAAx4ACQnMDdpcAI0BAB4ACQnMDdpcAI0BAA4AAQlRBioZACoAAAAA.Timboslicé:BAAALgAECgcJCwAAAA==.Tinyshieva:BAABLgAECn8XAAMBAAYJTA6uNQAFAQABAAYJTA6uNQAFAQAfAAIJ2wNKZwBBAAAAAA==.Tizuki:BAAALgAECgIJAwAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgkJBwAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn8wAAIYAAgJCxyEAwAzAgAYAAgJCxyEAwAzAgAAAA==.Treenn:BAAALgAECgMJCAAAAA==.Triplock:BAAALgADCgMJBQAAAA==.Trolcain:BAABLgAECn8uAAIeAAkJLiQ2BQA8AwAeAAkJLiQ2BQA8AwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgkJLgAeAC4kAA==.',
Ty='Tyrix:BAABLgAECn8gAAIJAAgJcSOfEwCyAgAJAAgJcSOfEwCyAgAAAA==.Tyránt:BAACLgAFFH8LAAIEAAQJpRHOKwArAQAEAAQJpRHOKwArAQAuAAQKfy4AAwQACQk4I7wKAN0CAAQACQk4I7wKAN0CAA8AAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAISAAYJ2BmCQABCAQASAAYJ2BmCQABCAQAAAA==.',
Va='Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCAAAAA==.Valerossi:BAABLgAECn84AAIlAAkJlx9uAwDrAgAlAAkJlx9uAwDrAgAAAA==.Valha:BAABLgAECn8mAAIIAAkJeRLyEQDVAQAIAAkJeRLyEQDVAQAAAA==.Valira:BAAALgADCgUJBgABLgAECgcJFQAEAJwXAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgADCgYJBgAAAA==.Varleyna:BAAALgAECgMJAwABLgAFFAQJDgABAJEhAA==.Varteras:BAABLgAECn8yAAMjAAkJsxsKBAAwAgAjAAgJghsKBAAwAgATAAgJnxKBRwCtAQAAAA==.',
Ve='Veleiri:BAABLgAECn8rAAICAAgJ4BFKXACtAQACAAgJ4BFKXACtAQAAAA==.Velenal:BAAALgAECgQJCAAAAA==.Vellron:BAABLgAECn8uAAIEAAkJhw4VNgDaAQAEAAkJhw4VNgDaAQAAAA==.',
Vo='Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAACLgAFFH8JAAMGAAQJWhZgQgD1AAAGAAMJ0BhgQgD1AAAIAAIJHA0PFgCXAAAuAAQKfxYAAwgABgm1I68SAMsBAAgABgkKI68SAMsBAAYABAkfH/dbAFEBAAEuAAUUBQkKAAkAPxUA.Wardkbriggle:BAACLgAFFH8OAAIgAAYJkx64BQDQAQAgAAYJkx64BQDQAQAuAAQKfyEAAiAACQmoI0wCABUDACAACQmoI0wCABUDAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8VAAISAAUJihuTCABKAQASAAUJihuTCABKAQAuAAQKfyAAAhIACQkeIMUIAIoCABIACQkeIMUIAIoCAAAA.',
Wi='Wifi:BAAALgAECgIJBQAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMgAAYJeAWFNwCGAAAgAAQJGQaFNwCGAAAOAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn8yAAICAAgJsBIDXACtAQACAAgJsBIDXACtAQAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn84AAQQAAkJ4yQzAQBWAwAQAAkJsyQzAQBWAwAmAAcJASMUBAB1AgAoAAYJth1aCACIAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJCwABLgAECgkJOAAQAOMkAA==.',
Xh='Xhared:BAABLgAECn8tAAIgAAgJuyElBwCGAgAgAAgJuyElBwCGAgAAAA==.',
Ya='Yahtzee:BAAALgAECgMJAwAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIGAAgJBwPsngC5AAAGAAgJBwPsngC5AAAAAA==.',
Yk='Ykszord:BAAALgAECgEJAQAAAA==.',
Ze='Zephy:BAAALgAECgQJBwAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRjfAABOAQApAAQJuRjfAABOAQAuAAQKfzQAAykACQlVILEAANICACkACQlVILEAANICAAIABAmyF6r5AAcBAAAA.',
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
