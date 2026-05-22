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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','Druid-Balance','Unknown-Unknown','Druid-Feral','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Monk-Mistweaver','Warlock-Destruction','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Priest-Discipline','DeathKnight-Frost','Warlock-Affliction','Warrior-Arms','Warrior-Fury','Paladin-Holy','Hunter-Survival','Priest-Shadow','Rogue-Assassination','Druid-Guardian','Warrior-Protection','Shaman-Elemental','Rogue-Outlaw','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaronius:BAABLgAECn8aAAIBAAcJOARSNwDVAAABAAcJOARSNwDVAAAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8mAAMCAAgJRhtGLgAeAgACAAgJRhtGLgAeAgADAAQJ2BeKCwAeAQAAAA==.',
Ac='Acceptance:BAAALgAECgMJAwAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8iAAIEAAgJuCDgFABiAgAEAAgJuCDgFABiAgAAAA==.Adora:BAABLgAECn8UAAIEAAcJnBcbRQB6AQAEAAcJnBcbRQB6AQAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aeðn:BAABLgAECn8XAAIEAAcJwA9uTgBcAQAEAAcJwA9uTgBcAQAAAA==.',
Ag='Agaliarept:BAACLgAFFH8FAAIFAAMJQgN6TACtAAAFAAMJQgN6TACtAAAuAAQKfxYAAwYACAkZCw8SANgAAAUABwnpBuCLAAsBAAYABwkPCw8SANgAAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAAALgAECgQJDQAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn8oAAMHAAgJexNmEwCUAQAHAAgJexNmEwCUAQAFAAEJxgMG6QAhAAAAAA==.',
Ak='Akumajoe:BAAALgADCgYJBgAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAECgEJBAAAAA==.Alrook:BAAALgAECggJEwAAAA==.',
Am='Amoral:BAAALgAECgMJAwAAAA==.',
An='Angelneko:BAABLgAECn8bAAIIAAcJtw0ILAAaAQAIAAcJtw0ILAAaAQAAAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwAJAAAAAA==.Arcaynemoon:BAABLgAECn8XAAIIAAYJWAM9VgDLAAAIAAYJWAM9VgDLAAAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.',
As='Asterior:BAACLgAFFH8PAAIKAAUJeRpiAQBxAQAKAAUJeRpiAQBxAQAuAAQKfyUAAgoACAnCILQDAIMCAAoACAnCILQDAIMCAAAA.',
Au='Aug:BAAALgAECgIJAgABLgAECggJDQAJAAAAAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgADCgEJAQAAAA==.Auroraa:BAABLgAECn8fAAIIAAYJJQVJQgCsAAAIAAYJJQVJQgCsAAAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgIJAgAJAAAAAA==.',
Av='Avalectra:BAAALgAECgMJAwAAAA==.',
Az='Azmodeaz:BAABLgAECn8iAAIDAAgJoBMtAwC6AQADAAgJoBMtAwC6AQAAAA==.',
Ba='Bajapanti:BAABLgAECn8wAAILAAgJzxuaBAAjAgALAAgJzxuaBAAjAgAAAA==.Ballyhøø:BAABLgAECn8VAAIIAAkJSxH0NgDfAAAIAAkJSxH0NgDfAAAAAA==.Banchory:BAAALgADCgIJAgAAAA==.Baxstab:BAABLgAECn8zAAIMAAkJ5xsrBwBwAgAMAAkJ5xsrBwBwAgAAAA==.',
Be='Beahon:BAAALgAECgQJCQAAAA==.Betruger:BAAALgAECgEJAQAAAA==.',
Bg='Bgeefiddy:BAAALgAECgIJAgAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJBgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackpatch:BAABLgAECn8uAAMNAAgJdiG/BwCGAgANAAgJdiG/BwCGAgAOAAgJ4ge9KwAfAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgMJAwAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAAALgAECgcJBwAAAA==.Blooming:BAAALgAECgYJBgABLgAECggJGwAPAAwaAA==.Bloomsbeam:BAABLgAECn8cAAIFAAgJ+xX1SQBZAQAFAAgJ+xX1SQBZAQAAAA==.',
Bo='Booneboy:BAABLgAECn8UAAMQAAYJGiDBQgC1AQAQAAYJGiDBQgC1AQARAAQJVhAmHwDEAAAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8ZAAMQAAcJ1wtQpAA4AQAQAAcJjApQpAA4AQARAAYJqgp7JQDdAAAAAA==.',
Br='Brennor:BAABLgAECn8wAAIQAAkJ5w6BQgC2AQAQAAkJ5w6BQgC2AQAAAA==.Brewslunt:BAACLgAFFH8PAAISAAUJQRhYEABbAQASAAUJQRhYEABbAQAuAAQKfyoAAxIACAmgIQMLAIUCABIACAmgIQMLAIUCAA0AAwnEC6RIAJEAAAAA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAAALgAECgYJEQAAAA==.Cairyan:BAABLgAECn8fAAIGAAgJixr/BAAMAgAGAAgJixr/BAAMAgAAAA==.Caiya:BAAALgADCgcJBwABLgAECggJLgAMACslAA==.Capn:BAAALgADCgcJCAAAAA==.Carvil:BAABLgAECn8wAAMTAAkJGRVZBADtAQATAAkJGRVZBADtAQAPAAMJiweSvQCCAAAAAA==.Castalia:BAAALgAECgQJCAAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8NAAICAAUJ/RIROwBEAQACAAUJ/RIROwBEAQAuAAQKfykAAgIACAnjIyocAAYDAAIACAnjIyocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAUJDQACAP0SAA==.Celithe:BAABLgAECn8WAAIQAAcJ8g6jUQCKAQAQAAcJ8g6jUQCKAQAAAA==.Cendrian:BAAALgAECgYJDwAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8qAAICAAkJfRwuHAB3AgACAAkJfRwuHAB3AgAAAA==.Charmshield:BAAALgAECgMJAwAAAA==.Chiafix:BAABLgAECn8bAAIOAAgJ3graJwA0AQAOAAgJ3graJwA0AQABLgAECggJKAAUAC0hAA==.Chipp:BAAALgAFFAEJBAAAAA==.Chleo:BAAALgAECgMJBgAAAA==.Choco:BAACLgAFFH8cAAIVAAYJih8hBAAaAgAVAAYJih8hBAAaAgAuAAQKfycAAxUACQmFIeQFAOgCABUACQmFIeQFAOgCABYAAQkVG6wYAE4AAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAYJHAAVAIofAA==.Chudster:BAABLgAECn8gAAMWAAkJ/RUEBQDSAQAWAAkJ/RUEBQDSAQAXAAUJDQgfQwDIAAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAAALgAECgUJEQAAAA==.Conqueror:BAAALgAECgYJEAABLgAECgkJMgAYAKQZAA==.',
Cr='Crawdaddy:BAABLgAECn8UAAIEAAYJBRFIZAAgAQAEAAYJBRFIZAAgAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAAALgAECgQJCAAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECgYJFAAQAN8JAA==.Curmudge:BAABLgAECn87AAIYAAkJ1xRDGQAzAgAYAAkJ1xRDGQAzAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgAJAAAAAA==.Cybele:BAABLgAECn8UAAIBAAYJqwxSLQAYAQABAAYJqwxSLQAYAQAAAA==.',
Da='Dakunaito:BAABLgAECn8aAAIZAAcJGCViKwALAgAZAAcJGCViKwALAgAAAA==.Darachane:BAAALgAECgUJEgAAAA==.Darovan:BAAALgADCgMJAwABLgAECggJJQAaAMMgAA==.Dauglow:BAAALgAECgMJAwAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgADCgEJAQAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAECgQJBAAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAAALgAECgUJEAAAAA==.Deltia:BAAALgAECgcJEwAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAMJBgAEAI8QAA==.Demonagent:BAAALgAECgYJDgAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8SAAMXAAUJjBpKFQBEAQAXAAUJjBpKFQBEAQAWAAEJ2BYZCQBYAAAuAAQKfyoAAxYACQkvHtYJAEICABYACQkEHNYJAEICABcACAmaFsobAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8bAAIPAAgJDBrYJQAJAgAPAAgJDBrYJQAJAgAAAA==.',
Di='Dimebagg:BAAALgAECgEJAgAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8hAAMBAAgJLxv9EgD5AQABAAgJLxv9EgD5AQAbAAMJDgnvRACRAAAAAA==.Dokspades:BAAALgADCgUJBQAAAA==.Dornoch:BAAALgAECgQJCwAAAA==.Dotzilla:BAAALgAECgQJCwAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJBgAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8iAAIQAAgJagxZaQBRAQAQAAgJagxZaQBRAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgYJDgAJAAAAAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAAALgAFFAIJBAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8IAAIZAAMJHxBqYQDxAAAZAAMJHxBqYQDxAAAuAAQKfy4AAhkACAn5IQsiADkCABkACAn5IQsiADkCAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAQAAAA==.',
Ei='Eisenhorn:BAAALgAECgEJAQAAAA==.',
El='Elessaria:BAABLgAECn8UAAIYAAYJ5QbrYwDEAAAYAAYJ5QbrYwDEAAAAAA==.Elfatheàrt:BAAALgAECgQJDQAAAA==.Elira:BAAALgAECgEJAQAAAA==.',
Em='Emofurry:BAAALgADCgIJAwAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgcJFAAEAJwXAA==.',
Es='Esika:BAAALgAFFAEJAgAAAA==.Estherras:BAABLgAECn8mAAIEAAgJsBW4LgDQAQAEAAgJsBW4LgDQAQAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgEJAQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fe='Feardotrun:BAABLgAECn8XAAMTAAcJIwxqHQB8AAAPAAYJAwzYgQD4AAATAAMJVwxqHQB8AAAAAA==.Felicious:BAAALgAECgQJDQAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgAJAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgADCgUJBQAAAA==.Finahlia:BAABLgAECn8WAAIYAAgJJyBrCwDJAgAYAAgJJyBrCwDJAgAAAA==.Finally:BAAALgAECgQJDQAAAA==.Firemage:BAABLgAECn8hAAIPAAkJ6CAdFQBuAgAPAAkJ6CAdFQBuAgAAAA==.Fizzanelf:BAAALgAECgQJDQAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAABLgAECn8qAAIQAAkJ/RYAUQDuAQAQAAkJ/RYAUQDuAQAAAA==.Friendo:BAABLgAECn8vAAMKAAgJlBUYCQDYAQAKAAgJlBUYCQDYAQAIAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAECgkJAwAAAA==.',
Fu='Furnost:BAABLgAECn8jAAIcAAgJAhcpBgDIAQAcAAgJAhcpBgDIAQAAAA==.Futnuraz:BAAALgAECgQJCQAAAA==.',
Fy='Fyriat:BAABLgAECn8oAAICAAgJZQnVdABQAQACAAgJZQnVdABQAQAAAA==.',
Ga='Gazardiel:BAAALgAECgIJAgAAAA==.',
Ge='Getafix:BAAALgAECgEJAgABLgAECggJKAAUAC0hAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8gAAINAAcJxhRmHwBfAQANAAcJxhRmHwBfAQAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8cAAITAAgJOhiVCABxAQATAAgJOhiVCABxAQAAAA==.Greybark:BAAALgADCgcJCwAAAA==.Griffindor:BAABLgAECn8pAAIQAAgJFBh+OQDUAQAQAAgJFBh+OQDUAQAAAA==.Grimfelborn:BAACLgAFFH8PAAMPAAUJkw1KPQARAQAPAAQJkw1KPQARAQAdAAEJAAAwFwAAAAAuAAQKfy4AAw8ACAlMG7sxAEUCAA8ACAkWG7sxAEUCAB0AAgmcHx8aAKcAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAAALgAECgYJEAAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgADCgkJDQAAAA==.',
Ha='Hanicus:BAAALgADCggJDgAAAA==.Hanoverfiste:BAABLgAECn8UAAIQAAYJ3wmemQD2AAAQAAYJ3wmemQD2AAAAAA==.Hapsburg:BAABLgAECn8oAAISAAkJYBGPGADdAQASAAkJYBGPGADdAQAAAA==.Havince:BAABLgAECn8zAAIaAAkJ9yBDAwDXAgAaAAkJ9yBDAwDXAgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn8uAAIQAAgJth8cGQBtAgAQAAgJth8cGQBtAgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Il='Illidai:BAAALgAECgYJDgAAAA==.Ilyndra:BAABLgAECn8bAAIeAAcJ3CH6BwAiAgAeAAcJ3CH6BwAiAgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn8oAAIfAAgJpxXNHAC5AQAfAAgJpxXNHAC5AQAAAA==.',
It='Ithea:BAABLgAECn8fAAICAAcJFCArOwDrAQACAAcJFCArOwDrAQAAAA==.',
Ja='Jaeson:BAABLgAECn8fAAIPAAkJ4BT3JAANAgAPAAkJ4BT3JAANAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAYJGAAgAMAXAA==.',
Je='Jeef:BAAALgADCgEJAQABLgAECggJFAAhADcjAA==.Jeefrenzy:BAABLgAECn8UAAIhAAgJNyMtBQCfAgAhAAgJNyMtBQCfAgAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgYJDgAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8iAAQBAAgJAhkCFQDiAQABAAgJsxICFQDiAQAbAAYJ8RSgIwB2AQAiAAQJ+BOMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8UAAIjAAYJCQwzDQATAQAjAAYJCQwzDQATAQAAAA==.',
Jw='Jwise:BAAALgADCgcJCgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kanabat:BAAALgAECgUJBwAAAA==.Karawyn:BAABLgAECn8eAAIEAAgJyw6lQwB+AQAEAAgJyw6lQwB+AQABLgAECgcJCAAJAAAAAA==.Karelix:BAAALgADCgcJBwAAAA==.Katrishy:BAACLgAFFH8PAAIiAAUJdxLkDgBCAQAiAAUJdxLkDgBCAQAuAAQKfysAAyIACAlcHYcWADMCACIACAlcHYcWADMCAAEAAQlwBUSIACcAAAAA.Kayyfrost:BAAALgADCgEJAQAAAA==.Kazeral:BAAALgADCggJDwAAAA==.',
Ke='Keedrid:BAAALgAECggJEQAAAA==.Keindis:BAAALgADCgYJBgABLgAECgUJEgAJAAAAAA==.Kelaeno:BAAALgADCgEJAQABLgAECggJHQAFAAsHAA==.Kelemenohpea:BAABLgAECn8dAAIFAAgJCweObgDzAAAFAAgJCweObgDzAAAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8oAAIUAAgJLSG0CwCzAgAUAAgJLSG0CwCzAgAAAA==.Kruàlty:BAAALgAECgQJCwAAAA==.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwAJAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgADCgIJAgABLgAECgQJBQAJAAAAAA==.Legreecast:BAAALgAECgQJBQAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ/zGgCmAQABAAkJGQ/zGgCmAQAiAAIJ2wfYWgBBAAAbAAEJrgEhYQAbAAAAAA==.',
Lo='Lodur:BAABLgAECn8nAAIUAAgJjRzjFQBHAgAUAAgJjRzjFQBHAgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn8nAAIkAAgJARTKDwB5AQAkAAgJARTKDwB5AQAAAA==.Losat:BAABLgAECn8wAAIlAAgJSQ1MFwA2AQAlAAgJSQ1MFwA2AQAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8VAAIQAAgJuBkoNQDkAQAQAAgJuBkoNQDkAQAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwAJAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAAALgAECgMJBQAAAA==.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Mackavelian:BAAALgAECgEJAQABLgAECgcJFwASACATAA==.Mackkie:BAABLgAECn8XAAMSAAcJIBOmIgCFAQASAAcJIBOmIgCFAQANAAMJKA0JVwBgAAAAAA==.Madonkadonk:BAABLgAECn8zAAMWAAkJoxCNBADoAQAWAAkJoxCNBADoAQAXAAMJlAW4ZQBJAAAAAA==.Maedai:BAABLgAECn8yAAISAAkJyhbmDgBMAgASAAkJyhbmDgBMAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAABLgAECn8zAAMgAAkJxRy5EQA8AgAgAAkJxRy5EQA8AgAQAAMJ1wn3SgEvAAAAAA==.Magús:BAAALgAECgEJAQAAAA==.Maldive:BAABLgAECn8mAAIPAAgJ4BHERgCIAQAPAAgJ4BHERgCIAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Mallicia:BAACLgAFFH8HAAIBAAMJtyFZDQAcAQABAAMJtyFZDQAcAQAuAAQKfysAAwEACAlkJJcDACADAAEACAlkJJcDACADABsABwlEGWQQABMCAAAA.Mallika:BAABLgAECn8YAAIUAAgJMhQdJwDLAQAUAAgJMhQdJwDLAQABLgAFFAMJBwABALchAA==.Mallwizard:BAABLgAECn8qAAIPAAkJyxSUOAApAgAPAAkJyxSUOAApAgAAAA==.Mangopewpew:BAAALgAECgUJDgAAAA==.Martris:BAAALgADCgcJCwAAAA==.Massoflice:BAABLgAECn8kAAIZAAgJQxdmOgDRAQAZAAgJQxdmOgDRAQAAAA==.Maxblaide:BAAALgAECgUJBQAAAA==.Maxilla:BAAALgADCgcJDQABLgAECgkJMwAgAMUcAA==.',
Me='Meridians:BAABLgAECn8YAAISAAYJohUnKABcAQASAAYJohUnKABcAQAAAA==.',
Mh='Mhataharii:BAAALgADCgIJAgAAAA==.',
Mi='Mindhorn:BAACLgAFFH8IAAMmAAMJkxqVGQAHAQAmAAMJkxqVGQAHAQAUAAEJLAneTwBBAAAuAAQKfyYAAyYACAkzIWcJAIICACYACAkzIWcJAIICABQABAkFFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn8oAAIRAAgJGhmECgDMAQARAAgJGhmECgDMAQAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIQAAgJJiAcMwBWAgAQAAgJJiAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAECgkJIgAXAHYUAA==.Musashi:BAAALgAECgMJAwAAAA==.Mustardhunt:BAAALgADCgQJBQAAAA==.',
My='Myriad:BAABLgAECn8oAAIlAAgJfx/CBgBXAgAlAAgJfx/CBgBXAgAAAA==.',
Na='Nakze:BAABLgAECn8oAAIMAAgJsAs9GwBhAQAMAAgJsAs9GwBhAQAAAA==.Namanari:BAAALgADCgkJCgAAAA==.Naris:BAAALgADCgYJBgAAAA==.Nastyfigs:BAABLgAECn8hAAIEAAgJAxzIIQAOAgAEAAgJAxzIIQAOAgAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.',
Nh='Nhilas:BAAALgAECgEJAwAAAA==.',
Ni='Nightstryke:BAAALgADCgYJBgAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
Ny='Nyxaries:BAAALgAECgUJDwAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
Pa='Pablo:BAAALgAECgQJBwAAAA==.Paladus:BAAALgAECgYJDwAAAA==.Pannacea:BAAALgAECgYJBgABLgAECggJKAAUAC0hAA==.Panzerblitz:BAABLgAECn8bAAIkAAgJwAgwHwDQAAAkAAgJwAgwHwDQAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAITAAcJNQoFIABSAQATAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgADCggJDAAAAA==.',
Pe='Pedrote:BAAALgADCgUJBgAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIEAAYJOCApKgANAgAEAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAAALgAECgYJEQAAAA==.Pretzelz:BAAALgADCgYJCgAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puffer:BAABLgAECn8vAAICAAgJixEOWgCOAQACAAgJixEOWgCOAQAAAA==.',
Ra='Rabone:BAAALgADCgIJAgAAAA==.Raelaris:BAAALgAECgMJAwABLgAFFAUJCwACAHscAA==.Raito:BAABLgAECn8YAAIQAAcJ6AlQpQA2AQAQAAcJ6AlQpQA2AQAAAA==.Rakshasa:BAABLgAECn8lAAMPAAgJdCNBDwCdAgAPAAgJdCNBDwCdAgAdAAEJAACyIQBrAAAAAA==.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJBgABLgAECgcJFAAEAJwXAA==.Rasetsungo:BAABLgAECn8WAAIBAAgJkhj8FwDEAQABAAgJkhj8FwDEAQAAAA==.Raura:BAAALgAECgQJCwAAAA==.',
Re='Recalcitrent:BAAALgADCgYJCAAAAA==.Redblueblurr:BAAALgAECgcJEgAAAA==.Remi:BAAALgAECgkJDwAAAA==.Reveillark:BAAALgAECgYJDgAAAA==.',
Ro='Rolan:BAABLgAECn8eAAIZAAkJ2CTcCwDVAgAZAAkJ2CTcCwDVAgAAAA==.Rosalian:BAABLgAECn8oAAIYAAgJFxw6EgB4AgAYAAgJFxw6EgB4AgAAAA==.Rotiko:BAABLgAECn8YAAIUAAcJLAypRAA3AQAUAAcJLAypRAA3AQAAAA==.Roweene:BAABLgAECn8aAAInAAcJ8QXsDADgAAAnAAcJ8QXsDADgAAAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgADCggJGQAAAA==.',
Se='Seiko:BAAALgADCgEJAQAAAA==.Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8lAAMNAAcJzR+CEQDoAQANAAcJzR+CEQDoAQAOAAEJEws+hQA8AAAAAA==.Serenatee:BAABLgAECn8uAAIiAAkJ7Q9SFgDGAQAiAAkJ7Q9SFgDGAQAAAA==.',
Sh='Shadowkrak:BAAALgADCgMJAwAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgADCgcJBwAAAA==.Shamwow:BAAALgADCggJDgAAAA==.Shappens:BAAALgADCgUJBQABLgAECgYJFAAQAN8JAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAAALgAECgYJDwAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAABLgAECn8YAAIFAAkJFRGkLwC+AQAFAAkJFRGkLwC+AQAAAA==.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgMJBgAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgADCgMJAwAAAA==.Simbà:BAAALgAECgYJDgAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8XAAMFAAcJGSHEIQCGAgAFAAcJGSHEIQCGAgAHAAEJ9hZVawA7AAABLgAECggJFAAhADcjAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAAALgAFFAIJAgAAAA==.',
So='Soferfax:BAAALgADCgUJBQAAAA==.Sokroar:BAAALgAECgQJBAABLgAFFAIJAwAJAAAAAA==.Sonknight:BAABLgAECn8VAAIgAAYJDAT+RwDGAAAgAAYJDAT+RwDGAAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAImAAgJYx32DgAwAgAmAAgJYx32DgAwAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn8qAAIhAAkJCQrkFgChAQAhAAkJCQrkFgChAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgIJBAAAAA==.Sto:BAAALgAECggJDQAAAA==.Stratof:BAAALgADCgIJAgAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Supad:BAAALgADCgYJBwAAAA==.Superball:BAAALgAECgkJEwABLgAECgkJMwAgAMUcAA==.Superjpriest:BAAALgAECgQJBgABLgAECgcJEwAJAAAAAA==.Suria:BAABLgAECn8vAAIYAAgJAyD7CQDdAgAYAAgJAyD7CQDdAgAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgEJAQAAAA==.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Tahrovin:BAAALgADCggJEwAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgADCgcJEwAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8UAAIbAAcJ+BkxEgD8AQAbAAcJ+BkxEgD8AQAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn80AAMgAAgJjQTyOQAQAQAgAAgJjQTyOQAQAQAQAAgJ3QmhmAD3AAAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.',
Th='Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgADCgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Thundercups:BAABLgAECn8zAAIoAAkJPiGNAQDnAgAoAAkJPiGNAQDnAgAAAA==.',
Ti='Tigerstarr:BAABLgAECn8UAAMZAAkJYg03fwAbAQAZAAkJYg03fwAbAQAcAAEJUQYqGQAqAAAAAA==.Timboslicé:BAAALgAECgcJCwAAAA==.Tinyshieva:BAABLgAECn8VAAMBAAYJ5Av0SAAVAQABAAYJ5Av0SAAVAQAiAAIJ2wOMWgBCAAAAAA==.Tizuki:BAAALgAECgIJAgAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgkJBwAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn8oAAITAAgJWBsgAwAjAgATAAgJWBsgAwAjAgAAAA==.Treenn:BAAALgAECgMJAwAAAA==.Triplock:BAAALgADCgMJBQAAAA==.Trolcain:BAABLgAECn8kAAIZAAgJKiRIDADSAgAZAAgJKiRIDADSAgAAAA==.Trolmed:BAAALgAECgYJDAABLgAECggJJAAZACokAA==.',
Ty='Tyrix:BAABLgAECn8XAAIQAAcJqSQyGwBgAgAQAAcJqSQyGwBgAgAAAA==.Tyránt:BAACLgAFFH8GAAIEAAMJjxCSOQDhAAAEAAMJjxCSOQDhAAAuAAQKfywAAwQACQkTI8QGAPACAAQACQkTI8QGAPACAAsAAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAIOAAYJ2BmCQABCAQAOAAYJ2BmCQABCAQAAAA==.',
Va='Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCAAAAA==.Valerossi:BAABLgAECn8uAAIhAAgJxR1LCQBMAgAhAAgJxR1LCQBMAgAAAA==.Valha:BAABLgAECn8mAAIHAAkJeRKeDgDXAQAHAAkJeRKeDgDXAQAAAA==.Valira:BAAALgADCgUJBQABLgAECgcJFAAEAJwXAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgADCgYJBgAAAA==.Varleyna:BAAALgAECgMJAwABLgAFFAMJBwABALchAA==.Varteras:BAABLgAECn8vAAMdAAkJrxtABAD1AQAdAAcJeRxABAD1AQAPAAgJnBIbOgCyAQAAAA==.',
Ve='Veleiri:BAABLgAECn8bAAICAAcJ5hE1bQBhAQACAAcJ5hE1bQBhAQAAAA==.Velenal:BAAALgAECgEJAwAAAA==.Vellron:BAABLgAECn8lAAIEAAgJ4Q6gPgCRAQAEAAgJ4Q6gPgCRAQAAAA==.',
Vo='Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAABLgAECn8WAAMHAAYJtSOLDgDYAQAHAAYJCiOLDgDYAQAFAAQJHx86SwBVAQAAAA==.Wardkbriggle:BAACLgAFFH8JAAIaAAMJDBamGwCbAAAaAAMJDBamGwCbAAAuAAQKfyEAAhoACQmoI38BACoDABoACQmoI38BACoDAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8UAAIOAAUJihuTCABKAQAOAAUJihuTCABKAQAuAAQKfyAAAg4ACQkdINcGAJUCAA4ACQkdINcGAJUCAAAA.',
Wi='Wifi:BAAALgAECgIJBAAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMaAAYJeAWFNwCGAAAaAAQJGQaFNwCGAAAcAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn8iAAICAAgJBxJaUwCgAQACAAgJBxJaUwCgAQAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn8uAAQMAAgJKyW6AgDsAgAMAAgJzCS6AgDsAgAjAAcJViIUBAB1AgAnAAYJth23BgCRAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJBwABLgAECggJLgAMACslAA==.',
Xh='Xhared:BAABLgAECn8lAAIaAAgJwyDwBgBpAgAaAAgJwyDwBgBpAgAAAA==.',
Ya='Yahtzee:BAAALgADCgcJCAAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIFAAgJBgOgjQCwAAAFAAgJBgOgjQCwAAAAAA==.',
Ze='Zephy:BAAALgAECgQJBwAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRilAABgAQApAAQJuRilAABgAQAuAAQKfzQAAykACQlVIIIAANUCACkACQlVIIIAANUCAAIABAmyF6r5AAcBAAAA.',
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
