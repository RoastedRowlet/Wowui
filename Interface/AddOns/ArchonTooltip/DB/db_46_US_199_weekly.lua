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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Druid-Restoration','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Shaman-Enhancement','Hunter-BeastMastery','Unknown-Unknown','Shaman-Elemental','Paladin-Protection','Paladin-Retribution','Paladin-Holy','DeathKnight-Frost','Mage-Frost','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Warrior-Protection','Priest-Shadow','DemonHunter-Devourer','DeathKnight-Blood','Mage-Fire','Monk-Brewmaster','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Druid-Feral','Mage-Arcane','Rogue-Outlaw',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aabbigale:BAAALgAECgkJBwAAAA==.',
Ab='Abigt:BAABLgAECn8YAAMBAAcJDiAtBwDwAQABAAcJDiAtBwDwAQACAAQJexGexQDOAAAAAA==.',
Ad='Adalaidê:BAAALgAECgYJDwAAAA==.',
Ae='Aelusion:BAACLgAFFH8GAAICAAMJ3xbjZgDlAAACAAMJ3xbjZgDlAAAuAAQKfx8ABAIACAlIHzwaALcCAAIACAmBHjwaALcCAAMAAwlaIRUsAA4BAAEAAQlAJCInAFUAAAEuAAUUBQkKAAQAeRAA.Aeluu:BAAALgAECgcJBwABLgAECggJHwAFALgRAA==.Aerola:BAAALgADCgIJAgAAAA==.Aerynne:BAAALgAECgMJDQAAAA==.',
Ai='Aidén:BAAALgAECgEJAQAAAA==.Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn86AAIGAAgJmBKjMwDWAQAGAAgJmBKjMwDWAQAAAA==.Aita:BAACLgAFFH8SAAIHAAUJfhPsBQDxAAAHAAUJfhPsBQDxAAAuAAQKfyMAAwcACQnXGO4GAB0CAAcACQnXGO4GAB0CAAgABQmWCVQ/AKYAAAAA.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJCQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Alisaa:BAAALgAECgQJBgAAAA==.Alistanë:BAAALgAECgUJCQAAAA==.Allegria:BAAALgAECgEJAgAAAA==.Alluna:BAAALgAECgIJBAAAAA==.Alondra:BAABLgAECn8gAAIDAAkJvB/4AQCmAgADAAkJvB/4AQCmAgAAAA==.Alulà:BAABLgAECn8gAAMJAAcJbh5eEQBRAgAJAAcJTB5eEQBRAgAKAAMJMx4lTQAEAQAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.Aluuni:BAABLgAECn8cAAILAAkJEBZuCAAvAgALAAkJEBZuCAAvAgAAAA==.',
Am='Amednato:BAAALgAECgcJBwABLgAECggJIQAMALYhAA==.Amo:BAAALgAECgIJAgABLgAECggJEQANAAAAAA==.',
An='Anaeli:BAABLgAECn9CAAMGAAkJKxzyFQCOAgAGAAkJKxzyFQCOAgAOAAUJ9whCaACeAAAAAA==.Anariel:BAAALgADCgUJBQABLgADCgcJDQANAAAAAA==.Ancalagonn:BAAALgAECgYJDgABLgAECgkJIQAGAE8PAA==.Androth:BAABLgAECn8mAAMPAAkJShvwCQAiAgAPAAgJwhzwCQAiAgAQAAMJpQqIDgGYAAAAAA==.Angelius:BAAALgAECgEJAwAAAA==.Angita:BAAALgAECgUJCAAAAA==.Antipæn:BAACLgAFFH8bAAMRAAUJEyBVDgDDAQARAAUJEyBVDgDDAQAQAAMJChv6XADgAAAuAAQKf0oAAxAACQmfJvoAAIoDABAACQmfJvoAAIoDABEABwmNIvcpAOIBAAAA.',
Ap='Apologia:BAABLgAECn82AAIQAAgJNSSTFgCyAgAQAAgJNSSTFgCyAgAAAA==.',
Ar='Arcanix:BAABLgAECn8UAAISAAcJxgnOFgASAQASAAcJxgnOFgASAQAAAA==.Arceé:BAAALgAECgMJBwAAAA==.Archaic:BAABLgAECn85AAITAAkJvxHXTwDmAQATAAkJvxHXTwDmAQAAAA==.Ardicelia:BAAALgAECgEJAQAAAA==.Ares:BAACLgAFFH8aAAMUAAcJyB/mAgBPAgAUAAcJyB/mAgBPAgAVAAIJCB71FgCuAAAuAAQKfyEAAxQACAlRJOUBABoDABQACAnfI+UBABoDABUABwlHIjMZAIICAAAA.Argomir:BAAALgAECgEJAQAAAA==.Ariellä:BAAALgADCgEJAQAAAA==.Arifault:BAAALgAECgIJAgABLgAECgkJQgAGACscAA==.Arilynx:BAABLgAECn8iAAIWAAkJ4Ad6FgBfAQAWAAkJ4Ad6FgBfAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn9BAAIXAAkJDSSxAQA3AwAXAAkJDSSxAQA3AwAAAA==.Aroviaa:BAABLgAECn9BAAQKAAkJVh57BwDsAgAKAAkJVh57BwDsAgAYAAEJHhHOegA4AAAJAAEJ9gOTfAAmAAAAAA==.Arpmek:BAABLgAECn8zAAIZAAgJ0hPOSQCcAQAZAAgJ0hPOSQCcAQAAAA==.Artemîs:BAAALgAECgQJBAAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Ashal:BAABLgAECn8gAAMXAAcJQw2BJAD/AAAVAAcJ+ggbSAAcAQAXAAcJQw2BJAD/AAAAAA==.Ashlynne:BAAALgAECggJEQAAAA==.Astrotoad:BAAALgAECgUJCgAAAA==.Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgYJBwAAAA==.Aurtt:BAABLgAECn9GAAIaAAkJHRc1EQDtAQAaAAkJHRc1EQDtAQAAAA==.',
Av='Avanel:BAAALgAECgEJAQAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Az='Azkadelia:BAAALgAECgEJAQAAAA==.',
Ba='Bageera:BAABLgAECn8uAAIFAAkJ8R3yCQATAwAFAAkJ8R3yCQATAwAAAA==.Bahahaknight:BAABLgAECn87AAIaAAgJvx8oCgBlAgAaAAgJvx8oCgBlAgAAAA==.Barccky:BAAALgAECgIJAgAAAA==.Barcy:BAAALgAECgEJAwABLgAECgIJAgANAAAAAA==.Barnette:BAACLgAFFH8JAAIbAAQJGgaMAgDcAAAbAAQJGgaMAgDcAAAuAAQKf0oAAhsACQlCGdkBAFwCABsACQlCGdkBAFwCAAAA.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearmissile:BAAALgAECgUJBwABLgAECggJIQALALwfAA==.Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn87AAIQAAkJ4x3UFwCrAgAQAAkJ4x3UFwCrAgAAAA==.Berristan:BAACLgAFFH8JAAIRAAMJkg6HLQC2AAARAAMJkg6HLQC2AAAuAAQKfzAAAxEACQkZGKIMALUCABEACQkZGKIMALUCABAABwnnCOXMAOoAAAAA.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigmarv:BAABLgAECn8gAAIOAAgJ6hfBMABtAQAOAAgJ6hfBMABtAQAAAA==.Bigsam:BAAALgAECgEJAQAAAA==.Bittytigs:BAAALgADCgUJBQAAAA==.',
Bl='Blossom:BAACLgAFFH8MAAIWAAUJww2NFQAlAQAWAAUJww2NFQAlAQAuAAQKfxUAAhYACAmdEY8YAM4BABYACAmdEY8YAM4BAAAA.Bluespruce:BAAALgAECgcJBwAAAA==.Bluewitchpa:BAAALgAECgQJCQAAAA==.',
Bo='Boomboomkill:BAAALgADCgEJAQAAAA==.Bosc:BAABLgAECn8kAAIaAAkJtBrrCQBqAgAaAAkJtBrrCQBqAgABLgAECggJHAAcAP0SAA==.Boudiicca:BAABLgAECn8ZAAIKAAQJmRKHQwDNAAAKAAQJmRKHQwDNAAAAAA==.Boxmasterr:BAABLgAECn83AAMCAAkJhQ6IVACaAQACAAkJFwyIVACaAQABAAcJ0wtyEwAkAQAAAA==.',
Br='Brasmir:BAABLgAECn8bAAIdAAgJXQxeIQCNAQAdAAgJXQxeIQCNAQAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.Brianzero:BAAALgAECgEJAQAAAA==.Brinotriage:BAAALgAECgUJBwAAAA==.',
Bu='Bubblement:BAAALgAFFAUJEgAAAQ==.Bubblemoth:BAAALgAECggJCgABLgAECgkJJgATACEWAA==.Bulge:BAAALgAFFAEJAQABLgAFFAYJGQAEAKIXAA==.Bulgogi:BAACLgAFFH8ZAAIEAAYJohcCMACMAQAEAAYJohcCMACMAQAuAAQKfzoAAgQACQnqISAMAAUDAAQACQnqISAMAAUDAAAA.Bushalabong:BAAALgAECgMJBAAAAA==.Butherrface:BAAALgAECgEJAQAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgAAAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAACLgAFFH8SAAQdAAUJ3yLjDABPAQAMAAQJ/h1MKABVAQAdAAQJ7B/jDABPAQAeAAEJAABeOAAAAAAuAAQKfzgABAwACQmHI4YmADsCAB0ACAnqH68MAFUCAAwACAn9IYYmADsCAB4ABgmIF1YyAKUBAAAA.Cardran:BAAALgADCgEJAQABLgAECgkJJgAPAEobAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAIRAAgJ3yHWBwDwAgARAAgJ3yHWBwDwAgAAAA==.Catamay:BAABLgAECn8gAAIZAAkJxRlxKAAeAgAZAAkJxRlxKAAeAgABLgAECgEJAQANAAAAAA==.Catprincess:BAABLgAECn8fAAIFAAgJuBF+OwC3AQAFAAgJuBF+OwC3AQAAAA==.Caylara:BAABLgAECn8YAAIfAAgJtQ8rHACnAQAfAAgJtQ8rHACnAQAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAABLgAECn8VAAIZAAYJcw0+kwDsAAAZAAYJcw0+kwDsAAAAAA==.',
Ch='Chai:BAAALgAECgcJEwAAAA==.Chaintrain:BAAALgADCggJBwABLgAECggJHwADAC8eAA==.Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAABLgAECn8mAAIcAAkJSBRSFgDwAQAcAAkJSBRSFgDwAQAAAA==.Chioma:BAAALgADCgIJAgAAAA==.',
Ci='Cindrethal:BAAALgADCggJCAAAAA==.',
Cl='Claes:BAAALgAECgEJAwABLgAECggJHAAcAP0SAA==.Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgAECgMJBAAAAA==.Clorox:BAAALgADCgEJAQAAAA==.',
Co='Coocoohead:BAAALgAECgMJBQAAAA==.Coralorchid:BAABLgAECn8yAAMPAAgJvxPkFQBpAQAPAAcJJRXkFQBpAQAQAAcJyA9olQA9AQAAAA==.Corrupt:BAAALgAECgEJAQABLgAECgMJCAANAAAAAA==.',
Cp='Cptdarkk:BAABLgAECn8ZAAIQAAcJUwtSrgAWAQAQAAcJUwtSrgAWAQAAAA==.',
Cr='Crytal:BAAALgAECgMJBAAAAA==.',
Cu='Cuddlebucket:BAAALgADCgQJBQAAAA==.Curissan:BAABLgAECn8iAAIOAAkJrxl1EgBPAgAOAAkJrxl1EgBPAgAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAABLgAECn8UAAIFAAgJAiEgFAChAgAFAAgJAiEgFAChAgAAAA==.',
['Cø']='Cøndemn:BAAALgAECgYJCAAAAA==.',
Da='Daemyn:BAAALgADCgcJBwAAAA==.Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAABLgAECn8bAAIEAAgJvhoNMQAzAgAEAAgJvhoNMQAzAgAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAgJIAAgAB0RAA==.Dalspin:BAACLgAFFH8gAAIgAAgJHRHuCwAbAgAgAAgJHRHuCwAbAgAuAAQKfyEABCAACQkpG9wHANkCACAACQkpG9wHANkCACEABwm8ElYqAIoBABwAAwkEAoF5AE0AAAAA.Dalthepal:BAABLgAECn8UAAIRAAcJXx+pHgAiAgARAAcJXx+pHgAiAgABLgAFFAgJIAAgAB0RAA==.Darassa:BAAALgAECgEJAQAAAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAACLgAFFH8aAAIQAAUJyx8QIQBuAQAQAAUJyx8QIQBuAQAuAAQKf0wAAhAACQmMJicBAIUDABAACQmMJicBAIUDAAAA.Davidshaman:BAAALgAECgcJBwAAAA==.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deadish:BAAALgAECgYJCwAAAA==.Deathsaberss:BAABLgAECn8qAAIUAAkJABiqDQAEAgAUAAkJABiqDQAEAgAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgcJEQAAAA==.Debauch:BAABLgAECn8cAAICAAkJPw89SQC6AQACAAkJPw89SQC6AQAAAA==.Deight:BAAALgAECgEJAQAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Denniah:BAAALgAECgQJBAAAAA==.Derke:BAAALgAECgQJBwAAAA==.Destinee:BAAALgAECgEJAQAAAA==.',
Di='Didudietho:BAAALgADCggJCAABLgAECgkJQQAQAAUbAA==.Diladrin:BAACLgAFFH8aAAIiAAUJ8w93EgDXAAAiAAUJ8w93EgDXAAAuAAQKf0sAAiIACQnDHCEGAJECACIACQnDHCEGAJECAAAA.Diode:BAACLgAFFH8fAAQEAAYJ7xTiQABhAQAEAAUJfBHiQABhAQASAAQJBBOkDQASAQAaAAEJAADITgAAAAAuAAQKfzEAAwQACQlyIDUYAOoCAAQACAn8IDUYAOoCABIACQnmGzgGADYCAAAA.Diyla:BAAALgAECgEJAQAAAA==.',
Do='Doileag:BAABLgAECn8gAAIQAAYJ+gfc2ADaAAAQAAYJ+gfc2ADaAAAAAA==.Domer:BAAALgAECgYJCAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dora:BAAALgAECgMJAwAAAA==.Dottmatrix:BAABLgAECn8aAAIDAAYJKA0tFwDeAAADAAYJKA0tFwDeAAAAAA==.',
Dr='Drachnia:BAAALgAECgQJBAAAAA==.Dragønbreath:BAACLgAFFH8MAAMTAAUJHAk0ZwAPAQATAAUJHAk0ZwAPAQAbAAEJaAOyBgAzAAAuAAQKfx0AAxsACQlxGhcCAEoCABsACAnMFxcCAEoCABMACAk3FfiqACQBAAAA.Dreadwing:BAABLgAECn8bAAIEAAUJ5wTC/QCgAAAEAAUJ5wTC/QCgAAAAAA==.',
Du='Duf:BAACLgAFFH8iAAIcAAYJHx2cDQClAQAcAAYJHx2cDQClAQAuAAQKfy8AAhwACQmEHzAOAEwCABwACQmEHzAOAEwCAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn87AAIKAAkJPSDgBQAOAwAKAAkJPSDgBQAOAwAAAA==.',
Dw='Dwagon:BAAALgAFFAEJAQAAAA==.',
['Dæ']='Dæmôn:BAAALgAECgYJCQAAAA==.',
['Dì']='Dìzzy:BAAALgAECgIJAgAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAACLgAFFH8LAAIhAAMJARsHGQD5AAAhAAMJARsHGQD5AAAuAAQKfzEAAxwACQkpG0UOAEoCABwACQkpG0UOAEoCACEAAgmkGCFgAI8AAAAA.Dûna:BAACLgAFFH8HAAIYAAIJVR26KACYAAAYAAIJVR26KACYAAAuAAQKfyUAAhgACAkBIecMAH4CABgACAkBIecMAH4CAAEuAAUUAwkLACEAARsA.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn9HAAIQAAkJQSRgBgA3AwAQAAkJQSRgBgA3AwAAAA==.Elduar:BAAALgADCgEJAQAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAABLgAECn8YAAIOAAcJfBBVPQAvAQAOAAcJfBBVPQAvAQAAAA==.Elketha:BAAALgAECgUJBQABLgAFFAUJGgAZAMkcAA==.Ellaring:BAAALgAECgYJCAABLgAECgcJDwANAAAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrric:BAABLgAECn8VAAIEAAgJQQz4fwBaAQAEAAgJQQz4fwBaAQAAAA==.Elryck:BAAALgADCgEJAQAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAABLgAECn8zAAMGAAgJ3h9GDwDNAgAGAAgJ3h9GDwDNAgAOAAgJJRNVLwB1AQAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Eroviaa:BAAALgAECgYJBwABLgAECgkJQQAKAFYeAA==.Erovvia:BAAALgAECgUJBgABLgAECgkJQQAKAFYeAA==.',
Es='Essaelsia:BAAALgAECgYJBgAAAA==.',
Et='Etali:BAAALgAECgMJBAABLgAECgkJMwAIAKoYAA==.',
Ez='Ezothen:BAABLgAECn8iAAMjAAgJ/gWTSgD2AAAjAAgJqgWTSgD2AAAkAAQJawRpLwCdAAAAAA==.',
Fa='Faedoria:BAABLgAECn8hAAIQAAgJKwRR1ADgAAAQAAgJKwRR1ADgAAAAAA==.Faeryln:BAABLgAECn8nAAIKAAkJ+ws8KgBpAQAKAAkJ+ws8KgBpAQAAAA==.Faerynn:BAAALgADCgkJCQABLgAECgkJLgAFAPEdAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falenrush:BAAALgADCgEJAQAAAA==.Falkorr:BAAALgAECgEJAgABLgAECgkJOAAlANQeAA==.Falorie:BAAALgADCgYJEQAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAABLgAECn8zAAMWAAkJTSHqAwD0AgAWAAgJhCHqAwD0AgAjAAEJByF3eABhAAAAAA==.Faustus:BAAALgADCgQJCgABLgAECgkJMwAWAE0hAA==.',
Fe='Feature:BAAALgAECgkJBwAAAA==.Felstormer:BAAALgADCggJEAABLgAECgQJCQANAAAAAA==.Felyna:BAAALgAECgMJAwAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgYJCQAAAA==.Firefoxx:BAAALgAECgEJAQABLgAECgkJLgAFAPEdAA==.Fireføx:BAAALgADCgEJAQAAAA==.Fisticuffs:BAAALgAECgQJCQAAAA==.Fizzllebang:BAABLgAECn8oAAIDAAkJxxUYCAC+AQADAAkJxxUYCAC+AQAAAA==.',
Fl='Flamewhisker:BAAALgAECgYJCQAAAQ==.Flogginrenee:BAAALgAECgYJEwAAAA==.Floggsdaddy:BAAALgAECgYJEwAAAA==.Floke:BAAALgAECgMJBAAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fr='Fraublucher:BAABLgAECn81AAIKAAkJbBSKFwAEAgAKAAkJbBSKFwAEAgAAAA==.Fredrik:BAABLgAFFH8NAAMcAAQJsRESJAAPAQAcAAQJsRESJAAPAQAgAAIJywHGYQAjAAABLgAFFAQJGAATAJsWAA==.Frewyn:BAAALgAECgQJCQAAAA==.Frikk:BAAALgAECgQJBAAAAA==.Frostimoth:BAABLgAECn8mAAITAAkJIRaGPAAiAgATAAkJIRaGPAAiAgAAAA==.Frozty:BAABLgAECn8dAAIWAAkJuxPjCgAnAgAWAAkJuxPjCgAnAgAAAA==.',
Fu='Fujïn:BAAALgADCgEJAQAAAA==.',
Ga='Galandel:BAAALgAECgQJCQAAAA==.Galial:BAACLgAFFH8VAAIHAAYJkh9XAQC2AQAHAAYJkh9XAQC2AQAuAAQKfyIAAgcACQlaHzsBACIDAAcACQlaHzsBACIDAAAA.Gantar:BAABLgAECn8YAAIiAAgJeSOuAgD6AgAiAAgJeSOuAgD6AgAAAA==.Garlicbread:BAAALgADCgYJBgABLgAFFAYJFQAHAJIfAA==.Garrunter:BAAALgAECgkJAQAAAA==.Gaznol:BAABLgAECn8hAAIMAAgJtiHGGgB4AgAMAAgJtiHGGgB4AgAAAA==.',
Ge='Gelasera:BAAALgAECgYJCQAAAA==.Gerbert:BAAALgAECgUJBQAAAA==.',
Gh='Ghibli:BAABLgAECn8XAAMUAAkJuA+DGQCEAQAUAAkJuA+DGQCEAQAVAAIJ7AWjmgBWAAAAAA==.',
Gi='Gisa:BAAALgAECgEJAQABLgAECgkJMwAIAKoYAA==.',
Gl='Glaivethras:BAABLgAECn8nAAIHAAkJNiOLAgDGAgAHAAkJNiOLAgDGAgAAAA==.Glyphix:BAABLgAECn8nAAIVAAkJPwuwLQCTAQAVAAkJPwuwLQCTAQAAAA==.Glyphx:BAAALgAECgEJAgAAAA==.',
Gn='Gnarly:BAAALgAECgMJCAAAAA==.',
Go='Goochtrap:BAAALgAECgQJBAAAAA==.Gorgon:BAAALgAECgMJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAABLgAECn8hAAQdAAgJxgw9IgCHAQAdAAgJuAs9IgCHAQAMAAQJeQ4vgQDkAAAeAAQJXwUlaACeAAAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.Groot:BAABLgAECn8cAAMFAAcJ9RCKWAAlAQAFAAUJtRKKWAAlAQAlAAcJKQ0sOgAbAQABLgAFFAIJBQAQAOMLAA==.Groovinchef:BAAALgAECgEJAQAAAA==.Grump:BAAALgAECgEJAQABLgAECggJIQALALwfAA==.',
Gu='Gundunn:BAAALgADCgEJAQAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECgYJFAAGAKYHAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAABLgAECn8dAAIYAAgJsRD2KwBuAQAYAAgJsRD2KwBuAQABLgAECgYJBwANAAAAAA==.Hannebal:BAABLgAECn8aAAIRAAkJEhFMJQDTAQARAAkJEhFMJQDTAQAAAA==.Havenfire:BAAALgADCgUJBQABLgAECgEJAQANAAAAAA==.',
He='Healsonyou:BAAALgAECgUJBQABLgAECggJFwAEAFsUAA==.Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCggJEgAAAA==.Heydaw:BAAALgAECggJDgABLgAECgkJIAAEAHIgAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgAECgEJAQAAAA==.Holybeatdown:BAAALgAECgMJBAAAAA==.Holyrage:BAAALgADCgYJBQAAAA==.Holyßloodelf:BAAALgAECggJCwABLgAECggJFwAEAFsUAA==.Honeysbadger:BAAALgAECgMJAwAAAA==.Hoosier:BAAALgAECgQJBQAAAA==.Hornet:BAABLgAECn8VAAMZAAgJZBBjXwBfAQAZAAgJ7w9jXwBfAQAIAAQJFwz3SADPAAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.Hotsauce:BAAALgAECgYJCAABLgAFFAcJGgATAOIaAA==.',
Hu='Huasca:BAAALgAECgMJBQAAAA==.Humungous:BAAALgAECgcJDQAAAA==.Hunnybunz:BAAALgAECgYJDAAAAA==.',
['Hà']='Hàney:BAAALgAECgYJBwAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJEgAAAA==.',
['Hé']='Hélio:BAAALgAECgQJBAAAAA==.',
Ia='Ia:BAABLgAFFH8HAAISAAQJEQzNDQAQAQASAAQJEQzNDQAQAQAAAA==.',
Ic='Icastfirebal:BAAALgAECgEJAQAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECggJDAAAAA==.',
Ig='Igotahitin:BAAALgADCgMJCAAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAABLgAECn8cAAIcAAgJ/RJoIQCUAQAcAAgJ/RJoIQCUAQAAAA==.',
Il='Illida:BAAALgAECgMJAwAAAA==.',
Im='Imamalelol:BAABLgAECn8gAAQVAAYJ1w00UAD+AAAVAAYJjgs0UAD+AAAUAAUJrQoxQgCyAAAXAAEJqgB1XQATAAAAAA==.',
In='Indira:BAAALgADCgcJDQAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAUJCQABLgAFFAUJDAAWAMMNAQ==.Inumimi:BAABLgAECn8fAAImAAkJzAXfIQDmAAAmAAkJzAXfIQDmAAAAAA==.Invincidemon:BAAALgAECgQJBAAAAA==.',
Ir='Irkenfox:BAECLgAFFH8dAAIXAAYJgyEiBwCtAQAXAAYJgyEiBwCtAQAuAAQKfyUAAhcACAmhI54DABsDABcACAmhI54DABsDAAAA.',
It='Ithran:BAABLgAECn8pAAITAAkJKQy9aQCiAQATAAkJKQy9aQCiAQAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8wAAIbAAkJ5x1HAQCcAgAbAAkJ5x1HAQCcAgAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.Jama:BAAALgAECgMJAwAAAA==.James:BAACLgAFFH8YAAITAAQJmxakSgBEAQATAAQJmxakSgBEAQAuAAQKf0cAAhMACQmgIZoNAAgDABMACQmgIZoNAAgDAAAA.Janderick:BAABLgAECn8iAAIVAAkJyiAACwCvAgAVAAkJyiAACwCvAgAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jeannedarc:BAAALgADCgIJAgAAAA==.Jellacee:BAABLgAECn8aAAMIAAUJeRFiRACQAAAIAAUJeRFiRACQAAAZAAIJHgPLBAE2AAAAAA==.Jesterjoe:BAAALgAECgQJDAAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8fAAIDAAYJhCLxAQDLAQADAAYJhCLxAQDLAQAuAAQKfy8AAgMACQmfIfQAAC8DAAMACQmfIfQAAC8DAAAA.Jimi:BAAALgADCgUJBQAAAA==.Jimreaper:BAAALgAECgkJCQAAAA==.Jinkx:BAAALgAECgEJAQABLgAECgkJOAAlANQeAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJBAABLgAECggJGAAiAHkjAA==.',
Jo='Joejitsu:BAAALgAECgMJAwAAAA==.Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAABLgAECn8fAAQDAAgJLx6kCQCdAQADAAYJrx2kCQCdAQACAAMJ0Bs8rgDiAAABAAEJXCB1KgBKAAAAAA==.Joltraxi:BAAALgAECgMJBQAAAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJEwABLgAECggJGAAiAHkjAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Js='Jstnbieber:BAAALgAECgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCgAAAA==.Juicethevoid:BAABLgAECn8pAAIZAAkJnwfQawBAAQAZAAkJnwfQawBAAQAAAA==.Juniornite:BAABLgAECn82AAITAAkJmCAdFQDVAgATAAkJmCAdFQDVAgAAAA==.Justicus:BAAALgAECgYJEQABLgAECgkJJwAMALUbAA==.Justthetouch:BAAALgAECggJCQAAAA==.',
Jy='Jygglypuff:BAAALgAECgcJCAAAAA==.',
['Jü']='Jüst:BAAALgAECgMJAwAAAA==.',
Ka='Kaeldrin:BAAALgADCgkJFAAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAABLgAECn8zAAQIAAkJqhipEgD0AQAIAAgJ7RepEgD0AQAHAAcJVhWlDQBpAQAZAAgJsA7BYQBZAQAAAA==.Kahgar:BAAALgAECgYJBgABLgAECgkJNAARAGkUAA==.Kaiser:BAAALgAECgQJCQAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgQJDQAAAA==.Kalzod:BAACLgAFFH8RAAICAAQJoRtaQQA4AQACAAQJoRtaQQA4AQAuAAQKfz4AAwIACQlLJisCAG4DAAIACQlLJisCAG4DAAEAAQkAAB0kAGEAAAAA.Kariana:BAAALgAECgYJDgAAAA==.Kataki:BAAALgAECgMJBAABLgAECgkJMwAIAKoYAA==.Katett:BAAALgAECgcJDgAAAA==.Katia:BAAALgADCgUJBQAAAA==.Kativeria:BAAALgAECgYJCQAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDwABLgAECgYJDgANAAAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgYJEgAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Keidric:BAAALgAECgIJAgAAAA==.Kerfufle:BAAALgAECgUJBQAAAA==.Keyn:BAAALgAECgIJAQAAAA==.Keynstolor:BAABLgAECn8hAAIMAAgJRBrjQQDRAQAMAAgJRBrjQQDRAQAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.Khálifá:BAAALgAECgUJBgAAAA==.',
Ki='Kicker:BAABLgAECn8UAAIVAAYJcgZNYgDDAAAVAAYJcgZNYgDDAAAAAA==.Killmora:BAAALgAECgQJCQAAAA==.Kippars:BAABLgAECn8hAAMiAAgJvRVCGwBhAQAiAAcJxxVCGwBhAQAmAAEJfRWJRQA/AAAAAA==.Kiritsugo:BAAALgADCggJGgAAAA==.Kissame:BAAALgAECgYJCAAAAA==.',
Kn='Knaifu:BAAALgADCgkJDQAAAA==.',
Ko='Kodazoff:BAABLgAECn85AAQjAAkJixKaHADqAQAjAAkJUhKaHADqAQAkAAgJsQ3uCQB4AQAWAAIJIAdzOQAzAAAAAA==.Korevash:BAABLgAECn8mAAMLAAcJjBxaDgC+AQALAAcJjBxaDgC+AQAGAAIJ4wktsgBVAAABLgAFFAUJFgAJAOgRAA==.Korupta:BAABLgAECn8uAAMZAAgJHBCaXQBkAQAZAAgJHBCaXQBkAQAIAAUJ3A36PQAFAQABLgAECgkJJAACADgSAA==.Korzilius:BAAALgAECggJEAAAAA==.',
Kr='Krissylu:BAABLgAECn8gAAIBAAcJFQ0IEQBBAQABAAcJFQ0IEQBBAQAAAA==.Krockett:BAAALgAECgQJBAAAAA==.Krothix:BAABLgAECn9FAAIOAAkJrA3rLwByAQAOAAkJrA3rLwByAQAAAA==.Kruvix:BAAALgAECgYJCgAAAA==.Krygask:BAAALgAECgQJBAAAAA==.Kryjag:BAAALgAECgMJBgAAAA==.Krynir:BAAALgADCgkJDgAAAA==.Kryshym:BAAALgAECggJCQAAAA==.Krythrall:BAAALgAECgMJAwABLgAECggJCQANAAAAAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAAALgAECgYJDwAAAA==.',
['Kü']='Kürömë:BAAALgADCgMJAwAAAA==.',
La='Ladara:BAABLgAECn8tAAIBAAkJ8BAkCADLAQABAAkJ8BAkCADLAQAAAA==.Laima:BAAALgADCgYJDQAAAA==.Lalthras:BAAALgAECgcJBwAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAgAAAA==.Lavitz:BAAALgAECgMJBgAAAA==.',
Le='Leheo:BAAALgAECgQJDAAAAA==.Lehua:BAAALgADCggJDAAAAA==.Leilanii:BAAALgAECgQJCQAAAA==.Lemook:BAAALgAECgcJDQAAAA==.Leonìdas:BAAALgAECgQJBgAAAA==.',
Lh='Lhei:BAAALgAECgYJDAAAAA==.',
Li='Lightstormer:BAAALgAECgQJCQAAAA==.Lilamae:BAAALgAECggJDgAAAA==.Lilarielle:BAABLgAECn86AAImAAgJKwmRHwD4AAAmAAgJKwmRHwD4AAAAAA==.Lildash:BAAALgADCgIJAgABLgAECgkJJgAPAEobAA==.Lilface:BAAALgAECgYJCgAAAA==.Liliela:BAAALgAECgQJBAABLgAECgkJJgAPAEobAA==.Lilsham:BAAALgAECgQJBAABLgAECgkJJgAPAEobAA==.Lilyannah:BAAALgAECgkJAQAAAA==.Linadra:BAAALgAECgcJBwAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgIJAgANAAAAAA==.Liopain:BAAALgAECgIJAgAAAA==.Liø:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.',
Lo='Lokir:BAAALgAECgMJBgAAAA==.Lotheovian:BAEALgAECgIJAgABLgAECgkJLgAEAJsaAA==.Lowchin:BAABLgAECn8VAAIFAAcJOwqQZAD9AAAFAAcJOwqQZAD9AAAAAA==.',
Lu='Lumia:BAABLgAECn8dAAMYAAkJix4wEwBcAgAYAAcJlB8wEwBcAgAKAAYJFBjVSgANAQAAAA==.Lutherion:BAABLgAECn8WAAQXAAgJqB+1BwB5AgAXAAgJqB+1BwB5AgAUAAEJCQdCSAAlAAAVAAEJUAL+rwASAAAAAA==.',
Lv='Lvispriestly:BAAALgADCgQJBAABLgAECgkJIgAlAEsDAA==.',
Ly='Lycemmas:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìllìth:BAAALgADCgYJBgAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgAECgEJAQAAAA==.Mackshiesty:BAABLgAECn8gAAIZAAcJzx1qLQAGAgAZAAcJzx1qLQAGAgAAAA==.Macoun:BAABLgAECn80AAMMAAkJrSThAwBMAwAMAAkJrSThAwBMAwAeAAYJEhv0QABVAQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn9BAAITAAkJLiYgBABlAwATAAkJLiYgBABlAwAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAABLgAECn8dAAIYAAgJzApGMgBJAQAYAAgJzApGMgBJAQAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBgANAAAAAA==.Martei:BAACLgAFFH8bAAImAAUJXhpSBQBOAQAmAAUJXhpSBQBOAQAuAAQKfy8AAiYACQm/IkICAC8DACYACQm/IkICAC8DAAAA.Maríneth:BAABLgAECn8UAAIFAAYJVwiCdwDGAAAFAAYJVwiCdwDGAAAAAA==.Mathías:BAABLgAECn8nAAIMAAkJgBn6JgA4AgAMAAkJgBn6JgA4AgAAAA==.Mavze:BAAALgADCgIJAgAAAA==.',
Me='Meadowfrey:BAAALgAECgEJAQAAAA==.Mentuko:BAAALgADCgEJAQAAAA==.Meowbae:BAABLgAECn8zAAMmAAkJ8BcrCAA9AgAmAAkJ8BcrCAA9AgAlAAEJNAEfoAAVAAAAAA==.Merce:BAAALgAECgcJBwABLgAECgkJJgAPAEobAA==.Mercesdes:BAAALgAECgUJBgAAAA==.Mercina:BAAALgAECgEJBAAAAA==.Mercuros:BAABLgAECn8UAAMKAAkJawNVOwD5AAAKAAkJawNVOwD5AAAYAAIJrgOYdQBEAAAAAA==.Merknlock:BAAALgAECgEJAQAAAA==.',
Mi='Micãh:BAAALgAECgIJAgAAAA==.Midnyte:BAABLgAECn9EAAMhAAkJwRoADgBcAgAhAAkJwRoADgBcAgAgAAkJshNOHwAMAgAAAA==.Milkyweí:BAAALgAECgMJAwAAAA==.Mini:BAAALgADCgUJBQABLgAECggJKwATAOweAA==.Minizee:BAAALgAECgYJCAAAAA==.Mirabella:BAAALgAECgQJBgABLgAFFAQJDAAgAIkYAA==.Mirokushan:BAAALgAECgQJEAABLgAECgUJEAANAAAAAA==.Mistfit:BAAALgAECgQJAwAAAA==.Misticlady:BAAALgADCgEJAQAAAA==.Mistingmoo:BAAALgAECgUJBgABLgAECgcJFwAUAMIKAA==.Mistrariel:BAABLgAECn8oAAIHAAkJuh4LAwCrAgAHAAkJuh4LAwCrAgAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Moostafa:BAAALgAECgQJBAAAAA==.Moradin:BAAALgADCgIJAgAAAA==.Mordemour:BAAALgAECgYJEAAAAA==.',
Mu='Mungo:BAABLgAECn8qAAITAAgJTBjmSwDxAQATAAgJTBjmSwDxAQAAAA==.Musketoon:BAAALgAECgYJBgAAAA==.',
My='My:BAAALgAECgkJDgAAAA==.Mynkie:BAACLgAFFH8UAAIgAAUJlhT1HwBBAQAgAAUJlhT1HwBBAQAuAAQKfzYAAiAACQlfIusDAGwDACAACQlfIusDAGwDAAAA.Myrell:BAAALgAECgkJBgAAAA==.Mythreashis:BAAALgADCgMJAwAAAA==.',
['Mä']='Mägi:BAAALgAECgEJAQAAAA==.',
['Må']='Mååt:BAAALgADCgIJAgAAAA==.',
['Mæ']='Mæstra:BAAALgADCgQJBAAAAA==.',
['Më']='Mëlony:BAAALgADCgIJAgAAAA==.',
Na='Nachtmar:BAAALgAECgYJEwAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8gAAIZAAYJKxSfKABsAQAZAAYJKxSfKABsAQAuAAQKfyoAAhkACAlDHF4wAPkBABkACAlDHF4wAPkBAAAA.Nalik:BAAALgAECgYJBwAAAA==.Nanou:BAAALgADCgUJBQAAAA==.Nardiaun:BAAALgADCgkJCQAAAA==.',
Ne='Necia:BAAALgADCgEJAQABLgAECgkJJwAKAPsLAA==.Neltu:BAAALgAECgEJAQAAAA==.Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nikkitta:BAAALgADCgMJAwAAAA==.Nimravidae:BAABLgAECn86AAMRAAgJ5ReIHgADAgARAAgJ5ReIHgADAgAQAAcJKRIhgwBdAQAAAA==.Ninelives:BAABLgAECn8iAAIlAAkJSwPtSQDVAAAlAAkJSwPtSQDVAAAAAA==.Nitecrawler:BAABLgAECn8iAAMTAAgJ2Q63eACAAQATAAgJ2Q63eACAAQAnAAEJhQNXGAAZAAAAAA==.Niteryu:BAAALgAECgkJEQABLgAECgkJNgATAJggAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAABLgAECn8nAAIjAAgJCQwTOABBAQAjAAgJCQwTOABBAQAAAA==.Noxium:BAAALgAECgYJDQAAAA==.Noxolon:BAABLgAECn86AAIVAAkJ8RuYDQCNAgAVAAkJ8RuYDQCNAgAAAA==.',
Nr='Nreaf:BAABLgAECn8yAAMQAAkJKRy9JACUAgAQAAkJKRy9JACUAgAPAAQJChcfJQDfAAAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgQJCAAAAA==.Nydhogg:BAAALgAECgEJAQABLgAECgkJKAAHALoeAA==.Nysca:BAAALgADCgcJBwAAAA==.',
Ob='Obijuan:BAAALgAECgMJAwAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAAALgAECgYJDAAAAA==.',
Ol='Olarrick:BAAALgAFFAMJBAABLgAFFAQJGAATAJsWAA==.',
Or='Ornstein:BAABLgAECn8kAAMPAAYJkSL0DADpAQAPAAYJkSL0DADpAQAQAAYJGBDmtQAKAQAAAA==.',
Ot='Ottuk:BAACLgAFFH8VAAMEAAYJ9RO4MwCBAQAEAAUJ9RO4MwCBAQAaAAEJAAAyWgAAAAAuAAQKfyIAAwQACQnVIa8IAFgDAAQACQnVIa8IAFgDABoAAwlnHX0nAAMBAAAA.',
Pa='Padinbar:BAAALgAECgQJBAABLgAECgcJDwANAAAAAA==.Pakraxes:BAAALgAECgUJBQAAAA==.Paksenarrion:BAABLgAECn87AAIPAAgJAhIRFQBzAQAPAAgJAhIRFQBzAQAAAA==.Pancham:BAAALgADCgUJBQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECgkJEQAAAA==.Pandemônium:BAAALgAECggJEAAAAA==.Pandemönium:BAAALgAECgIJAQAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Pandèmonium:BAAALgAECgYJBgAAAA==.Patchington:BAABLgAECn8UAAIPAAYJohSBGwAuAQAPAAYJohSBGwAuAQAAAA==.Pañdemönium:BAAALgAECgUJBQAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Perck:BAAALgAECgQJBAAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAFFAIJBgAjAIgTAA==.Pezvoker:BAACLgAFFH8GAAIjAAIJiBMeTACCAAAjAAIJiBMeTACCAAAuAAQKfxQAAiMABgmtHsIkAK8BACMABgmtHsIkAK8BAAAA.',
Pi='Pienarri:BAAALgAECgEJAgAAAA==.Pixelme:BAAALgAECgMJBQAAAA==.',
Pl='Pleggster:BAABLgAECn8ZAAMGAAgJJA7ASgB3AQAGAAgJJA7ASgB3AQAOAAEJiAG3tQAbAAAAAA==.',
Po='Pochula:BAABLgAECn8kAAIFAAgJaxV0KQD/AQAFAAgJaxV0KQD/AQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAABLgAECn80AAMRAAkJaRQyFwBFAgARAAkJaRQyFwBFAgAQAAIJSgSmYQFEAAAAAA==.Protricity:BAABLgAECn88AAMYAAkJdCALCQC4AgAYAAkJdCALCQC4AgAKAAEJ2AJchAAtAAAAAA==.',
Pu='Pumpernickel:BAAALgADCgUJBQABLgAFFAYJFQAHAJIfAA==.Puppytoes:BAAALgAECgYJDgAAAA==.',
Py='Pyrellyn:BAAALgADCggJCgAAAA==.',
['Pä']='Pändamönium:BAAALgAECgkJEQAAAA==.Pändemönium:BAAALgAFFAEJAQAAAA==.',
['Pæ']='Pæn:BAACLgAFFH8PAAIEAAUJOybDIgC+AQAEAAUJOybDIgC+AQAuAAQKfy0AAwQABwnHJc0fAIICAAQABwnHJc0fAIICABoABwmPHxUTANMBAAEuAAUUBQkbABEAEyAA.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgYJCQABLgAECgYJCwANAAAAAA==.Quantar:BAAALgAECgYJCwAAAA==.Quickstab:BAAALgAECgcJBwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rakta:BAAALgAECgYJDwAAAA==.Rancooll:BAAALgAECgQJCQAAAA==.Rasniir:BAACLgAFFH8FAAIFAAIJRAYnWQBjAAAFAAIJRAYnWQBjAAAuAAQKf0sAAgUACQlZIQ4FAGADAAUACQlZIQ4FAGADAAAA.Ravenlash:BAAALgAECgEJBAAAAA==.',
Re='Regna:BAACLgAFFH8eAAIVAAYJ0SZ9AwAjAgAVAAYJ0SZ9AwAjAgAuAAQKfzAAAhUACQmaJhgDAH8DABUACQmaJhgDAH8DAAAA.Regner:BAAALgAECgEJAQAAAA==.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAABLgAECn8VAAIaAAcJlQwKKwD2AAAaAAcJlQwKKwD2AAAAAA==.Remaked:BAACLgAFFH8rAAIcAAcJgR18AwCpAQAcAAcJgR18AwCpAQAuAAQKf0AAAhwACQmsI7YDAAwDABwACQmsI7YDAAwDAAAA.Remilia:BAABLgAECn83AAIYAAgJQiKUCADBAgAYAAgJQiKUCADBAgAAAA==.Requinix:BAABLgAECn9FAAIMAAkJIxiLJwA2AgAMAAkJIxiLJwA2AgAAAA==.Retro:BAAALgAECgEJAQAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAFFAEJAQAAAA==.Revwrinkle:BAAALgAECgIJAwAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgUJEAAAAA==.Ricochet:BAABLgAECn8hAAIdAAkJ0RD3FAD5AQAdAAkJ0RD3FAD5AQAAAA==.Riptidez:BAAALgADCgcJBgAAAA==.Ririko:BAABLgAECn82AAIKAAgJMhCKJACSAQAKAAgJMhCKJACSAQAAAA==.Ritzo:BAABLgAECn8pAAIVAAgJnBR8KACxAQAVAAgJnBR8KACxAQAAAA==.Rizzla:BAAALgAECgIJAgABLgAECgkJOAAlANQeAA==.',
Ro='Rockllobster:BAAALgAECgcJDwAAAA==.Rocksanne:BAAALgADCgcJEAAAAA==.Roguebâit:BAABLgAECn9IAAQBAAkJ9Bx8AwBvAgABAAgJFRx8AwBvAgACAAcJjBRmVACaAQADAAMJJw3SRACiAAAAAA==.Ronarvinge:BAAALgAECgcJDwAAAA==.Ronen:BAAALgAECgQJBAAAAA==.',
Ru='Rubywolf:BAAALgAECgYJDgABLgAFFAQJBwAlAEkHAA==.Rukkis:BAABLgAECn8pAAMfAAkJ7xpsCQCCAgAfAAkJ7xpsCQCCAgAoAAEJjQkmIwAuAAAAAA==.Rukâ:BAAALgADCgIJAgAAAA==.Rumi:BAACLgAFFH8XAAIHAAUJZx0dAwBSAQAHAAUJZx0dAwBSAQAuAAQKf0sAAwcACQnrJOwAADgDAAcACQnrJOwAADgDAAgAAQlvEellADIAAAAA.',
Ry='Ryeekan:BAABLgAECn8oAAIMAAkJdhN5NwD1AQAMAAkJdhN5NwD1AQAAAA==.',
['Ró']='Róronoà:BAAALgAECgYJCgAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAACLgAFFH8FAAIQAAIJ4ws4hgCMAAAQAAIJ4ws4hgCMAAAuAAQKfykAAhAACQlbFzBNANUBABAACQlbFzBNANUBAAAA.Saelena:BAAALgADCgEJAQAAAA==.Sakheddala:BAAALgAECgQJBAAAAA==.Sancha:BAAALgAECgYJBgAAAA==.Sanosagara:BAABLgAECn9AAAIgAAgJSxo5FgBVAgAgAAgJSxo5FgBVAgAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgAECgIJAwAAAA==.Sarithon:BAAALgAECgYJBgAAAA==.Saru:BAAALgADCgkJDQAAAA==.Saruta:BAACLgAFFH8VAAMVAAQJ5BjfGABAAQAVAAQJ5BjfGABAAQAUAAEJdQPQPgA4AAAuAAQKfzEAAxUACQnxIBkJAMgCABUACQnxIBkJAMgCABQABQmqDwoWAE4BAAAA.Sath:BAAALgAECgQJBAAAAA==.Sathari:BAABLgAECn8wAAIZAAgJ/RY/QQC5AQAZAAgJ/RY/QQC5AQAAAA==.Satille:BAAALgADCgUJBQAAAA==.Satsuki:BAABLgAECn8bAAMJAAcJORwnFQAlAgAJAAcJORwnFQAlAgAYAAUJfxVKMgBJAQABLgAFFAUJGgAZAMkcAA==.',
Sc='Scarycat:BAAALgADCgYJBgAAAA==.Schaden:BAAALgAECgEJAQABLgAECggJFAAFAAIhAA==.',
Se='Seijo:BAAALgAECgMJAwAAAA==.Sekk:BAABLgAECn9MAAIQAAkJ4B+0EgDKAgAQAAkJ4B+0EgDKAgAAAA==.Selexi:BAAALgADCgYJEAAAAA==.Sereya:BAAALgADCgQJBAABLgAECgEJAQANAAAAAA==.Sesshanmaru:BAAALgAECgUJBQAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAABLgAECn9RAAIIAAkJbySEAQBZAwAIAAkJbySEAQBZAwAAAA==.Shadoshiftt:BAABLgAECn8mAAMlAAkJrQaTPAAPAQAlAAkJrQaTPAAPAQAFAAgJGALwlwCeAAAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgAECgQJCQAAAA==.Shamzee:BAACLgAFFH8TAAMGAAQJZxy5IgBHAQAGAAQJZxy5IgBHAQAOAAEJrQKVVQAxAAAuAAQKfygAAwYACAkZHdobAGACAAYACAkZHdobAGACAA4AAQlWDXWfACwAAAAA.Shandalf:BAAALgAECgUJEAAAAA==.Shansebaim:BAAALgAECgYJBgAAAA==.Shintok:BAAALgAECggJDAAAAA==.Shuddarun:BAACLgAFFH8hAAIMAAYJoSCiAwBkAQAMAAYJoSCiAwBkAQAuAAQKfywAAgwACQlPIsUDAFQDAAwACQlPIsUDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgADCgcJDQANAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simn:BAABLgAECn8eAAIMAAkJCxqnHgBjAgAMAAkJCxqnHgBjAgAAAA==.Sindraesong:BAAALgAECggJEgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgAECgIJBAAAAA==.',
Sk='Skithiryx:BAAALgAECgEJAQABLgAECgkJMwAIAKoYAA==.Skrai:BAAALgAECgYJCgABLgAECggJIAAXANshAA==.',
Sl='Slayvylora:BAACLgAFFH8eAAMQAAYJyBjPDQA8AQAQAAUJ+RXPDQA8AQARAAEJ+QLmQQBHAAAuAAQKfzMABBAACQnKIZwUAL8CABAACQnKIZwUAL8CABEABQmWB29uAMEAAA8AAgn2FkY1AH4AAAAA.Sleep:BAAALgAECgQJBAABLgAFFAQJBwASABEMAA==.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgAECgIJBQAAAA==.Smarte:BAAALgAECgQJBAABLgAECggJKwATAOweAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Sneakymoth:BAAALgAECgYJEwABLgAECgkJJgATACEWAA==.Sniff:BAABLgAECn8rAAITAAgJ7B5ALABiAgATAAgJ7B5ALABiAgAAAA==.Snookums:BAABLgAECn86AAIZAAgJbBr7LgD/AQAZAAgJbBr7LgD/AQAAAA==.',
So='Soulomon:BAABLgAECn8ZAAICAAkJsRMwgwBUAQACAAkJsRMwgwBUAQAAAA==.Soulsarisen:BAAALgAECgYJDwAAAA==.',
Sp='Spanki:BAAALgADCgkJEAAAAA==.Spellteaser:BAABLgAECn8VAAITAAYJOhkguQBvAQATAAYJOhkguQBvAQAAAA==.Spicymaker:BAABLgAECn8mAAIUAAgJ5yCfCABdAgAUAAgJ5yCfCABdAgAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJCgAAAA==.Steelheart:BAAALgAECgEJCAAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Stolensøul:BAAALgADCgkJDgAAAA==.Strifewood:BAABLgAECn8cAAIaAAkJWhiTEwDMAQAaAAkJWhiTEwDMAQAAAA==.Stumper:BAABLgAECn84AAIlAAkJ1B6cCADBAgAlAAkJ1B6cCADBAgAAAA==.',
Su='Sugondese:BAAALgAECgQJBgAAAA==.Suluna:BAAALgAECgUJBQABLgAECgkJQgAGACscAA==.Summêr:BAABLgAECn8YAAIgAAYJ2wgQYwDPAAAgAAYJ2wgQYwDPAAAAAA==.Suri:BAAALgAECgUJCgABLgAECggJEQANAAAAAA==.Sux:BAABLgAECn8ZAAIiAAgJqg7sKQD4AAAiAAgJqg7sKQD4AAAAAA==.',
Sy='Sybrina:BAABLgAECn8cAAIMAAkJLhQGMgAJAgAMAAkJLhQGMgAJAgAAAA==.Sylvia:BAAALgADCgcJBgABLgAECgEJAQANAAAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAABLgAECn81AAIMAAYJ4QuIkwALAQAMAAYJ4QuIkwALAQAAAA==.Synèsterwolf:BAAALgAECgIJAwABLgAFFAQJBwAlAEkHAA==.',
['Sí']='Síf:BAAALgAECgcJDQAAAA==.',
Ta='Tabernacle:BAAALgAECgUJBQAAAA==.Tadeusz:BAAALgAECggJEwAAAA==.Tamamò:BAABLgAECn8bAAIgAAcJOxKPKABvAQAgAAcJOxKPKABvAQAAAA==.Tarrok:BAAALgADCgMJBwAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAAALgAECgQJCQAAAA==.Tepache:BAAALgADCgEJAQAAAA==.Tequitos:BAABLgAECn8mAAMRAAkJTBO4GAA2AgARAAkJTBO4GAA2AgAQAAYJ7guXzgDoAAAAAA==.Teranin:BAABLgAECn8UAAIlAAcJPwghRwDhAAAlAAcJPwghRwDhAAAAAA==.',
Tf='Tfortyone:BAAALgAECgYJCQAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgIJAgAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAACLgAFFH8TAAITAAQJxR5mOwBuAQATAAQJxR5mOwBuAQAuAAQKf0sAAhMACQnNJXADAG4DABMACQnNJXADAG4DAAAA.Thunderwalkr:BAAALgAECgEJAQAAAA==.',
Ti='Tiren:BAAALgAECgYJDQAAAA==.',
To='Torag:BAAALgAECgQJBAAAAA==.Torment:BAABLgAECn9NAAIaAAkJoB35BwCPAgAaAAkJoB35BwCPAgAAAA==.Tosti:BAAALgAECgkJAQAAAA==.',
Tr='Trepania:BAACLgAFFH8aAAIKAAYJRwvRDABmAQAKAAYJRwvRDABmAQAuAAQKfy4AAgoACQm9GNEWACUCAAoACQm9GNEWACUCAAAA.Tristén:BAABLgAECn8UAAIMAAgJWRVHOADyAQAMAAgJWRVHOADyAQAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Trollycarp:BAABLgAECn8gAAMQAAkJQwq8tAAMAQAQAAkJAgS8tAAMAQAPAAUJdhCuKgC4AAAAAA==.Truvie:BAAALgAECgYJDwAAAA==.',
Tu='Tumbler:BAABLgAECn8XAAMGAAgJix0YGgBtAgAGAAgJix0YGgBtAgAOAAMJCBE1bACTAAAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAABLgAECn85AAMOAAgJCgwNPQAxAQAOAAgJCgwNPQAxAQAGAAYJdAwvcgD2AAAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAABLgAECn8jAAIdAAkJRxGnFAD8AQAdAAkJRxGnFAD8AQAAAA==.',
Ul='Ulnuk:BAACLgAFFH8UAAIGAAQJlRjUKwAcAQAGAAQJlRjUKwAcAQAuAAQKfzsAAgYACQnvILAHACsDAAYACQnvILAHACsDAAAA.Ulster:BAAALgAECgIJAgAAAA==.',
Un='Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAANAAAAAA==.',
Va='Vadka:BAAALgAECggJEgAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAABLgAECn8UAAMGAAYJpgd+hwC8AAAGAAUJ3gh+hwC8AAAOAAUJlwT1ZQCkAAAAAA==.Vairian:BAABLgAECn8ZAAIIAAcJqQ/ZKAAiAQAIAAcJqQ/ZKAAiAQAAAA==.Valkree:BAAALgAECgYJDAAAAA==.Vallae:BAAALgADCgkJEQABLgAECgkJQgAGACscAA==.Valsavis:BAABLgAECn9IAAIHAAkJtxxfBABuAgAHAAkJtxxfBABuAgAAAA==.Valtier:BAAALgAECgcJDAAAAA==.Vampirä:BAABLgAECn8iAAQFAAkJQQUeggCrAAAFAAgJAgQeggCrAAAmAAQJngXWMwB4AAAlAAIJrgPZfwA8AAAAAA==.Varactor:BAAALgAECgMJAwAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAIhAAgJ7iA1CAD3AgAhAAgJ7iA1CAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgYJCQAAAA==.Vernice:BAAALgAECgEJAQABLgAECgYJEAANAAAAAA==.Verulan:BAABLgAECn8gAAQlAAgJtQpmNgAuAQAlAAgJ1AlmNgAuAQAFAAQJjArgjgCNAAAmAAEJKA65SwAyAAAAAA==.Vexeh:BAAALgAECgQJBQAAAA==.Vexomous:BAAALgAECgUJDwAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vierina:BAAALgAECgEJAQAAAA==.Vikss:BAABLgAECn8zAAMMAAkJ0xJ4PwDZAQAMAAkJ0xJ4PwDZAQAdAAYJXQQsHQAFAQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgAECgMJAwAAAA==.Vivien:BAAALgADCgYJBgABLgAECgEJAQANAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAImAAcJ6x9tCABYAgAmAAcJ6x9tCABYAgABLgAECgkJJwAMALUbAA==.',
Vo='Voidmayne:BAABLgAECn8/AAIQAAkJjBG8UADMAQAQAAkJjBG8UADMAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgYJEwAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.Voxella:BAAALgAECgQJBAAAAA==.',
Vr='Vrel:BAAALgADCgkJDgAAAA==.',
Vy='Vynnara:BAAALgAECgcJBwABLgAECgcJIAAJAG4eAA==.Vyv:BAABLgAECn8UAAIOAAcJtAV5VQDUAAAOAAcJtAV5VQDUAAAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAIZAAYJEhyzTQC+AQAZAAYJEhyzTQC+AQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Wayadra:BAABLgAECn8XAAQjAAkJkSE2BwDfAgAjAAkJkSE2BwDfAgAkAAcJSQTlJgDrAAAWAAEJlgrESQAvAAAAAA==.',
We='Weiand:BAABLgAECn8vAAMQAAkJUhtpMwAoAgAQAAgJpxppMwAoAgARAAEJOwckhgAzAAAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAACLgAFFH8IAAQCAAQJFgg6fQC6AAACAAMJ6Ac6fQC6AAABAAEJHgj9JABGAAADAAEJoQjvJgBAAAAuAAQKfyUABAIACQntFmc9AOABAAIACQntFmc9AOABAAMAAgnvD39XAGgAAAEAAQkAAA4xADwAAAAA.Wholemilk:BAABLgAECn8pAAIZAAkJXyCDDADaAgAZAAkJXyCDDADaAgAAAA==.',
Wi='Wiggz:BAAALgAECgcJCgAAAA==.Wilhellena:BAABLgAECn9BAAIKAAkJEB+0BQARAwAKAAkJEB+0BQARAwAAAA==.Wilhellfu:BAAALgAECgMJBwAAAA==.Winariel:BAAALgAECgUJBwABLgAECgkJKAAHALoeAA==.Wisteria:BAAALgAECgEJAQABLgABCgEJAQANAAAAAA==.',
Wr='Writhesoul:BAAALgAECgEJAQAAAA==.Wroughtsoul:BAAALgAECgQJAgAAAA==.Wrëckagë:BAAALgAECgcJEwAAAA==.',
Wu='Wumbo:BAAALgAECgYJBwAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAABLgAECn8kAAICAAkJOBLtQQDRAQACAAkJOBLtQQDRAQAAAA==.Xandir:BAABLgAECn8+AAIPAAkJPhJREQCiAQAPAAkJPhJREQCiAQAAAA==.Xarhunt:BAAALgAECgYJBwAAAA==.Xaric:BAABLgAECn8nAAIFAAkJXhnqJQAVAgAFAAkJXhnqJQAVAgAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xy='Xyal:BAABLgAECn8zAAIKAAgJICMHBwD1AgAKAAgJICMHBwD1AgAAAA==.Xyp:BAAALgAECgEJAQABLgAECggJIAAlALUKAA==.',
Yg='Ygor:BAAALgAECgUJDwAAAA==.',
Yi='Yiago:BAABLgAECn8UAAIVAAYJGgU7aQCtAAAVAAYJGgU7aQCtAAAAAA==.',
Yo='Yobabydaddy:BAAALgAECgMJAwAAAA==.Youknow:BAAALgAECgUJCAAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.Yungslug:BAAALgAECgcJCQAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zany:BAAALgADCgIJAgAAAA==.Zaranorinn:BAABLgAECn8dAAIQAAkJ0AdDjwBIAQAQAAkJ0AdDjwBIAQAAAA==.Zaxhdk:BAEBLgAECn8uAAMEAAkJmxrAJABpAgAEAAkJmxrAJABpAgAaAAUJTwa3QACBAAAAAA==.Zaxhmonk:BAEALgADCgkJCQABLgAECgkJLgAEAJsaAA==.',
Ze='Zedex:BAAALgADCgcJCAABLgADCggJDQANAAAAAA==.Zedru:BAAALgADCggJDQAAAA==.Zenstormer:BAAALgADCgQJBAABLgAECgQJCQANAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zephyrion:BAAALgAECgQJCQAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAABLgAECn8VAAIEAAYJfx0ahABTAQAEAAYJfx0ahABTAQAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAABLgAECn8hAAIGAAkJ+hfXIwAqAgAGAAkJ+hfXIwAqAgAAAA==.Zinrar:BAABLgAECn8qAAIEAAkJ/Rk6JQBnAgAEAAkJ/Rk6JQBnAgAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8wAAITAAcJqAhLswAYAQATAAcJqAhLswAYAQAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAABLgAECn8tAAMdAAkJgxU4EwAKAgAdAAkJuxQ4EwAKAgAMAAEJKRqbCQFBAAAAAA==.',
Zu='Zushi:BAAALgAECgUJBQAAAA==.',
['Äl']='Älphawolf:BAACLgAFFH8HAAIlAAQJSQevKgDLAAAlAAQJSQevKgDLAAAuAAQKfykABCUACQnNGBAbAOQBACUACQkRFhAbAOQBACIABQn2FHAgADcBAAUAAgl2CHy5AEYAAAAA.',
['Ðê']='Ðêmønicßløøð:BAABLgAECn8XAAIEAAgJWxRCVwC4AQAEAAgJWxRCVwC4AQAAAA==.',
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
