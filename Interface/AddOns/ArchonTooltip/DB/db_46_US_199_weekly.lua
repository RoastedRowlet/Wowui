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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Unknown-Unknown','Shaman-Elemental','Paladin-Protection','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Mage-Frost','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Warrior-Protection','Priest-Shadow','DemonHunter-Devourer','DeathKnight-Blood','Mage-Fire','Shaman-Enhancement','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Druid-Feral','Mage-Arcane','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aabbigale:BAAALgAECgkJBwAAAA==.',
Ab='Abigt:BAABLgAECn8YAAMBAAcJDiB6BgD0AQABAAcJDiB6BgD0AQACAAQJexGexQDOAAAAAA==.',
Ad='Adalaidê:BAAALgAECgYJDgAAAA==.',
Ae='Aelusion:BAACLgAFFH8GAAICAAMJ3xZqXQDxAAACAAMJ3xZqXQDxAAAuAAQKfx8ABAIACAlIHzwaALcCAAIACAmBHjwaALcCAAMAAwlaIRUsAA4BAAEAAQlAJCInAFUAAAAA.Aeluu:BAAALgAECgcJBwABLgAECggJHwAEALgRAA==.Aerola:BAAALgADCgIJAgAAAA==.Aerynne:BAAALgAECgMJDQAAAA==.',
Ai='Aidén:BAAALgAECgEJAQAAAA==.Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn8zAAIFAAgJPg8sQgCIAQAFAAgJPg8sQgCIAQAAAA==.Aita:BAACLgAFFH8SAAIGAAUJfhP4BAD4AAAGAAUJfhP4BAD4AAAuAAQKfyMAAwYACQnXGO4GAB0CAAYACQnXGO4GAB0CAAcABQmWCZY7AKYAAAAA.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJCQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Alisaa:BAAALgAECgEJAgAAAA==.Alistanë:BAAALgAECgUJCQAAAA==.Allegria:BAAALgAECgEJAgAAAA==.Alluna:BAAALgAECgIJAwAAAA==.Alondra:BAABLgAECn8gAAIDAAkJvB+9AQCpAgADAAkJvB+9AQCpAgAAAA==.Alulà:BAABLgAECn8gAAMIAAcJbh5FEABNAgAIAAcJTB5FEABNAgAJAAMJMx4lTQAEAQAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.Aluuni:BAAALgAECggJEwAAAA==.',
Am='Amo:BAAALgAECgIJAgABLgAECggJDgAKAAAAAA==.',
An='Anaeli:BAABLgAECn9AAAMFAAkJlBvBFgB7AgAFAAkJlBvBFgB7AgALAAUJ9wiAYgChAAAAAA==.Anariel:BAAALgADCgUJBQABLgADCgcJDQAKAAAAAA==.Ancalagonn:BAAALgAECgYJCAABLgAECgkJHwAFALEOAA==.Androth:BAABLgAECn8kAAMMAAgJwhwaCQAmAgAMAAgJwhwaCQAmAgANAAIJeAeRPAFUAAAAAA==.Angelius:BAAALgAECgEJAgAAAA==.Angita:BAAALgAECgQJBwAAAA==.Antipæn:BAACLgAFFH8WAAMOAAQJgSPoEgB7AQAOAAQJgSPoEgB7AQANAAMJChu4UQDpAAAuAAQKf0gAAw0ACQmfJrgAAIkDAA0ACQmfJrgAAIkDAA4ABwmNIvcpAOIBAAEuAAUUBQkMAA8A6iUA.',
Ap='Apologia:BAABLgAECn8uAAINAAgJjSNVFwChAgANAAgJjSNVFwChAgAAAA==.',
Ar='Arcanix:BAABLgAECn8UAAIQAAcJxgkkFgD5AAAQAAcJxgkkFgD5AAAAAA==.Arceé:BAAALgAECgMJBwAAAA==.Archaic:BAABLgAECn85AAIRAAkJvxGMSwDhAQARAAkJvxGMSwDhAQAAAA==.Ardicelia:BAAALgAECgEJAQAAAA==.Ares:BAACLgAFFH8WAAMSAAYJ7x6nBQDBAQASAAYJ7x6nBQDBAQATAAIJCB71FgCuAAAuAAQKfyEAAxIACAlRJOUBABoDABIACAnfI+UBABoDABMABwlHIjMZAIICAAAA.Argomir:BAAALgAECgEJAQAAAA==.Ariellä:BAAALgADCgEJAQAAAA==.Arifault:BAAALgAECgIJAgABLgAECgkJQAAFAJQbAA==.Arilynx:BAABLgAECn8iAAIUAAkJ4AeoFQBgAQAUAAkJ4AeoFQBgAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn84AAIVAAkJlCMUAgAhAwAVAAkJlCMUAgAhAwAAAA==.Aroviaa:BAABLgAECn88AAQJAAkJSx7xBgDwAgAJAAkJSx7xBgDwAgAWAAEJHhEccgA5AAAIAAEJ9gOzdAAmAAAAAA==.Arpmek:BAABLgAECn8zAAIXAAgJ0hM4RgCdAQAXAAgJ0hM4RgCdAQAAAA==.Artemîs:BAAALgAECgQJBAAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Ashal:BAABLgAECn8gAAMVAAcJQw1AIgAFAQATAAcJ+gh8RAAcAQAVAAcJQw1AIgAFAQAAAA==.Ashlynne:BAAALgAECggJDgAAAA==.Astrotoad:BAAALgAECgUJCgAAAA==.Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgQJBQAAAA==.Aurtt:BAABLgAECn9BAAIYAAkJuRYHEgDSAQAYAAkJuRYHEgDSAQAAAA==.',
Av='Avanel:BAAALgAECgEJAQAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Az='Azkadelia:BAAALgAECgEJAQAAAA==.',
Ba='Bageera:BAABLgAECn8uAAIEAAkJ8R1TCQAVAwAEAAkJ8R1TCQAVAwAAAA==.Bahahaknight:BAABLgAECn8zAAIYAAgJbx5ACwBDAgAYAAgJbx5ACwBDAgAAAA==.Barccky:BAAALgAECgIJAgAAAA==.Barcy:BAAALgAECgEJAwABLgAECgIJAgAKAAAAAA==.Barnette:BAACLgAFFH8FAAIZAAMJXgagAgCuAAAZAAMJXgagAgCuAAAuAAQKf0oAAhkACQlCGYEBAHQCABkACQlCGYEBAHQCAAAA.Barvi:BAAALgAECgQJBAABLgAECggJKwARAOweAA==.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearmissile:BAAALgAECgUJBgABLgAECggJIAAaALwfAA==.Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn82AAINAAkJ/xwWGgCPAgANAAkJ/xwWGgCPAgAAAA==.Berristan:BAACLgAFFH8FAAIOAAMJSQm4LQCrAAAOAAMJSQm4LQCrAAAuAAQKfy4AAw4ACQkZGKIMALUCAA4ACQkZGKIMALUCAA0ABgk7B4jkALkAAAAA.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigmarv:BAABLgAECn8fAAILAAgJ6heFLQB0AQALAAgJ6heFLQB0AQAAAA==.Bigsam:BAAALgAECgEJAQAAAA==.Bittytigs:BAAALgADCgUJBQAAAA==.',
Bl='Blossom:BAACLgAFFH8MAAIUAAUJww2IEwA6AQAUAAUJww2IEwA6AQAuAAQKfxUAAhQACAmdEY8YAM4BABQACAmdEY8YAM4BAAAA.Bluespruce:BAAALgAECgcJBwAAAA==.Bluewitchpa:BAAALgAECgMJBQAAAA==.',
Bo='Boomboomkill:BAAALgADCgEJAQAAAA==.Bosc:BAABLgAECn8bAAIYAAkJGxf2DQAQAgAYAAkJGxf2DQAQAgABLgAECggJGwAbADgRAA==.Boudiicca:BAABLgAECn8ZAAIJAAQJmRITQQDSAAAJAAQJmRITQQDSAAAAAA==.Boxmasterr:BAABLgAECn8yAAMCAAkJ+wvFUQCaAQACAAkJugvFUQCaAQABAAcJrgeLGwDAAAAAAA==.',
Br='Brasmir:BAABLgAECn8ZAAIcAAgJXQzxHwCPAQAcAAgJXQzxHwCPAQAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.Brianzero:BAAALgAECgEJAQAAAA==.Brinotriage:BAAALgAECgUJBwAAAA==.',
Bu='Bubblement:BAAALgAFFAUJEgAAAQ==.Bulge:BAAALgAFFAEJAQABLgAFFAUJFwAPAG4bAA==.Bulgogi:BAACLgAFFH8XAAIPAAUJbhutSgA9AQAPAAUJbhutSgA9AQAuAAQKfzoAAg8ACQnqIbQKAAkDAA8ACQnqIbQKAAkDAAAA.Bushalabong:BAAALgAECgMJBAAAAA==.Butherrface:BAAALgAECgEJAQAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgAAAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAACLgAFFH8QAAMdAAQJ3yIQHgBiAQAdAAQJ/h0QHgBiAQAcAAQJ7B/VCwBYAQAuAAQKfzgABBwACQmHI8ELAFkCABwACAnqH8ELAFkCAB0ACAn9IV8jAD4CAB4ABgmIF1YyAKUBAAAA.Cardran:BAAALgADCgEJAQABLgAECggJJAAMAMIcAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAIOAAgJ3yHWBwDwAgAOAAgJ3yHWBwDwAgAAAA==.Catamay:BAABLgAECn8dAAIXAAgJqRtqMwDiAQAXAAgJqRtqMwDiAQABLgAECgEJAQAKAAAAAA==.Catprincess:BAABLgAECn8fAAIEAAgJuBF+OwC3AQAEAAgJuBF+OwC3AQAAAA==.Caylara:BAAALgAECggJEgAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAAALgAECgUJDwAAAA==.',
Ch='Chai:BAAALgAECgYJDAAAAA==.Chaintrain:BAAALgADCggJBwABLgAECggJHQADAC8eAA==.Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAABLgAECn8kAAIbAAgJfhXqGwC0AQAbAAgJfhXqGwC0AQAAAA==.',
Ci='Cindrethal:BAAALgADCggJCAAAAA==.',
Cl='Claes:BAAALgAECgEJAgABLgAECggJGwAbADgRAA==.Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgAECgMJAwAAAA==.Clorox:BAAALgADCgEJAQAAAA==.',
Co='Coocoohead:BAAALgAECgMJBQAAAA==.Coralorchid:BAABLgAECn8wAAMMAAcJOxTnGwAeAQANAAcJyA+CkQA0AQAMAAYJcBTnGwAeAQAAAA==.Corrupt:BAAALgAECgEJAQABLgAECgMJCAAKAAAAAA==.',
Cp='Cptdarkk:BAABLgAECn8ZAAINAAcJUwuLqAAPAQANAAcJUwuLqAAPAQAAAA==.',
Cr='Crytal:BAAALgAECgEJAgAAAA==.',
Cu='Cuddlebucket:BAAALgADCgQJBQAAAA==.Curissan:BAABLgAECn8iAAILAAkJrxkdEQBSAgALAAkJrxkdEQBSAgAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAABLgAECn8UAAIEAAgJAiHkEgCjAgAEAAgJAiHkEgCjAgAAAA==.',
['Cø']='Cøndemn:BAAALgAECgYJCAAAAA==.',
Da='Daemyn:BAAALgADCgcJBwAAAA==.Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAABLgAECn8YAAIPAAcJ6huNQQDrAQAPAAcJ6huNQQDrAQAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAgJIAAfAB0RAA==.Dalspin:BAACLgAFFH8gAAIfAAgJHRHNCAAsAgAfAAgJHRHNCAAsAgAuAAQKfyEABB8ACQkpG9wHANkCAB8ACQkpG9wHANkCACAABwm8ElYqAIoBABsAAwkEAid1AE0AAAAA.Dalthepal:BAABLgAECn8UAAIOAAcJXx+pHgAiAgAOAAcJXx+pHgAiAgABLgAFFAgJIAAfAB0RAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAACLgAFFH8VAAINAAQJax/oHQBqAQANAAQJax/oHQBqAQAuAAQKf0wAAg0ACQmMJt8AAIUDAA0ACQmMJt8AAIUDAAAA.Davidshaman:BAAALgAECgcJBwAAAA==.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deadish:BAAALgAECgYJCwAAAA==.Deathsaberss:BAABLgAECn8qAAISAAkJABiLDAAIAgASAAkJABiLDAAIAgAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgcJEQAAAA==.Debauch:BAABLgAECn8bAAICAAgJcg9KXAB+AQACAAgJcg9KXAB+AQAAAA==.Deight:BAAALgADCgkJCQAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Denniah:BAAALgAECgQJBAAAAA==.Derke:BAAALgAECgQJBwAAAA==.Destinee:BAAALgAECgEJAQAAAA==.',
Di='Didudietho:BAAALgADCggJCAABLgAECgkJOwANAAUbAA==.Diladrin:BAACLgAFFH8VAAIhAAQJbg+HDwDeAAAhAAQJbg+HDwDeAAAuAAQKf0sAAiEACQnDHH0FAJQCACEACQnDHH0FAJQCAAAA.Diode:BAACLgAFFH8eAAQPAAYJ7xRSOABiAQAPAAUJfBFSOABiAQAQAAQJBBMyCwAcAQAYAAEJAACORwAAAAAuAAQKfzEAAw8ACQlyIDUYAOoCAA8ACAn8IDUYAOoCABAACQnmG6QFAC4CAAAA.Diyla:BAAALgAECgEJAQAAAA==.',
Do='Doileag:BAABLgAECn8aAAINAAYJrwZa2wDFAAANAAYJrwZa2wDFAAAAAA==.Domer:BAAALgAECgYJCAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dora:BAAALgAECgMJAwAAAA==.Dottmatrix:BAABLgAECn8WAAIDAAYJ2wtbFwDTAAADAAYJ2wtbFwDTAAAAAA==.',
Dr='Drachnia:BAAALgAECgQJBAAAAA==.Dragønbreath:BAACLgAFFH8MAAMRAAUJHAkLXwASAQARAAUJHAkLXwASAQAZAAEJaAOABQAzAAAuAAQKfx0AAxkACQlxGhcCAEoCABkACAnMFxcCAEoCABEACAk3FeyhAB0BAAAA.Dreadwing:BAABLgAECn8bAAIPAAUJ5wSl8QCgAAAPAAUJ5wSl8QCgAAAAAA==.',
Du='Duf:BAACLgAFFH8hAAIbAAYJHx3DCgCwAQAbAAYJHx3DCgCwAQAuAAQKfy8AAhsACQmEH0gNAE4CABsACQmEH0gNAE4CAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn87AAIJAAkJPSA2BQAWAwAJAAkJPSA2BQAWAwAAAA==.',
Dw='Dwagon:BAAALgAECggJEQAAAA==.',
['Dæ']='Dæmôn:BAAALgAECgYJCQAAAA==.',
['Dì']='Dìzzy:BAAALgAECgIJAgAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAACLgAFFH8JAAIgAAMJ5xcYGgDlAAAgAAMJ5xcYGgDlAAAuAAQKfy8AAxsACQnyGmQOAEECABsACQnyGmQOAEECACAAAgmkGCFgAI8AAAAA.Dûna:BAACLgAFFH8GAAIWAAIJVR3FJACgAAAWAAIJVR3FJACgAAAuAAQKfyIAAhYACAkAID4OAFcCABYACAkAID4OAFcCAAEuAAUUAwkJACAA5xcA.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn9DAAINAAkJQSQJBgAwAwANAAkJQSQJBgAwAwAAAA==.Elduar:BAAALgADCgEJAQAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAABLgAECn8YAAILAAcJfBAMOQA3AQALAAcJfBAMOQA3AQAAAA==.Elketha:BAAALgAECgUJBQABLgAFFAQJFQAXACEcAA==.Ellaring:BAAALgAECgYJCAABLgAECgYJDAAKAAAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrric:BAABLgAECn8VAAIPAAgJQQzKeQBaAQAPAAgJQQzKeQBaAQAAAA==.Elryck:BAAALgADCgEJAQAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAABLgAECn8uAAMFAAgJnyBQGABuAgAFAAcJyB9QGABuAgALAAgJJRPELAB4AQAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Eroviaa:BAAALgAECgUJBgABLgAECgkJPAAJAEseAA==.Erovvia:BAAALgAECgUJBgABLgAECgkJPAAJAEseAA==.',
Es='Essaelsia:BAAALgAECgYJBgAAAA==.',
Et='Etali:BAAALgAECgMJBAABLgAECgkJMwAHAKoYAA==.',
Ez='Ezothen:BAABLgAECn8iAAMiAAgJ/gVjSQDiAAAiAAgJqgVjSQDiAAAjAAQJawRpLwCdAAAAAA==.',
Fa='Faedoria:BAABLgAECn8bAAINAAcJAgR15gC3AAANAAcJAgR15gC3AAAAAA==.Faeryln:BAABLgAECn8nAAIJAAkJ+wtvJwB0AQAJAAkJ+wtvJwB0AQAAAA==.Faerynn:BAAALgADCgkJCQABLgAECgkJLgAEAPEdAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falenrush:BAAALgADCgEJAQAAAA==.Falkorr:BAAALgAECgEJAQABLgAECgkJOAAkANQeAA==.Falorie:BAAALgADCgYJEQAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAABLgAECn8zAAMUAAkJTSGwAwD1AgAUAAgJhCGwAwD1AgAiAAEJByGBbwBhAAAAAA==.Faustus:BAAALgADCgQJCgABLgAECgkJMwAUAE0hAA==.',
Fe='Feature:BAAALgAECgkJBwAAAA==.Felstormer:BAAALgADCggJEAABLgAECgMJBQAKAAAAAA==.Felyna:BAAALgAECgMJAwAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgUJCAAAAA==.Firefoxx:BAAALgAECgEJAQABLgAECgkJLgAEAPEdAA==.Fireføx:BAAALgADCgEJAQAAAA==.Fisticuffs:BAAALgAECgMJBQAAAA==.Fizzllebang:BAABLgAECn8oAAIDAAkJxxVNBwDDAQADAAkJxxVNBwDDAQAAAA==.',
Fl='Flamewhisker:BAAALgAECgUJCAAAAQ==.Flogginrenee:BAAALgAECgYJEwAAAA==.Floggsdaddy:BAAALgAECgYJEwAAAA==.Floke:BAAALgAECgMJBAAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fr='Fraublucher:BAABLgAECn8zAAIJAAkJbBTgFQANAgAJAAkJbBTgFQANAgAAAA==.Fredrik:BAABLgAFFH8MAAMbAAQJsRGtIAAVAQAbAAQJsRGtIAAVAQAfAAIJywHdVQAlAAABLgAFFAQJGAARAJsWAA==.Frewyn:BAAALgAECgQJCAAAAA==.Frikk:BAAALgAECgEJAQAAAA==.Frostimoth:BAABLgAECn8kAAIRAAgJlRXdUwDJAQARAAgJlRXdUwDJAQAAAA==.Frozty:BAABLgAECn8VAAIUAAYJ1hW6EwB6AQAUAAYJ1hW6EwB6AQAAAA==.',
Fu='Fujïn:BAAALgADCgEJAQAAAA==.',
Ga='Galandel:BAAALgAECgMJBQAAAA==.Galial:BAACLgAFFH8TAAIGAAUJIyEpAgBsAQAGAAUJIyEpAgBsAQAuAAQKfyIAAgYACQlaHzsBACIDAAYACQlaHzsBACIDAAAA.Gantar:BAABLgAECn8YAAIhAAgJeSOuAgD6AgAhAAgJeSOuAgD6AgAAAA==.Garlicbread:BAAALgADCgYJBgABLgAFFAUJEwAGACMhAA==.Gaznol:BAABLgAECn8hAAIdAAgJtiEJGAB/AgAdAAgJtiEJGAB/AgAAAA==.',
Ge='Gelasera:BAAALgAECgUJCAAAAA==.',
Gh='Ghibli:BAABLgAECn8XAAMSAAkJuA++FwCFAQASAAkJuA++FwCFAQATAAIJ7AWjmgBWAAAAAA==.',
Gi='Gisa:BAAALgAECgEJAQABLgAECgkJMwAHAKoYAA==.',
Gl='Glaivethras:BAABLgAECn8nAAIGAAkJNiNGAgDNAgAGAAkJNiNGAgDNAgAAAA==.Glyphix:BAABLgAECn8nAAITAAkJPwtgKwCTAQATAAkJPwtgKwCTAQAAAA==.Glyphx:BAAALgAECgEJAQAAAA==.',
Gn='Gnarly:BAAALgAECgMJCAAAAA==.',
Go='Goochtrap:BAAALgAECgQJBAAAAA==.Gorgon:BAAALgAECgMJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAABLgAECn8hAAQcAAgJxgzIIACIAQAcAAgJuAvIIACIAQAdAAQJeQ4vgQDkAAAeAAQJXwUlaACeAAAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.Groot:BAABLgAECn8WAAMEAAUJtRL1VQAmAQAEAAUJtRL1VQAmAQAkAAQJxAvIUACuAAABLgAECgkJJgANAO4WAA==.Groovinchef:BAAALgAECgEJAQAAAA==.Grump:BAAALgAECgEJAQABLgAECggJIAAaALwfAA==.',
Gu='Gundunn:BAAALgADCgEJAQAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECgQJDgAKAAAAAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAEBLgAECn8dAAIWAAgJsRDFKABqAQAWAAgJsRDFKABqAQABLgAECgYJBwAKAAAAAA==.Hannebal:BAABLgAECn8aAAIOAAkJEhE7IwDWAQAOAAkJEhE7IwDWAQAAAA==.Havenfire:BAAALgADCgUJBQABLgAECgEJAQAKAAAAAA==.',
He='Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCggJEgAAAA==.Heydaw:BAAALgAECggJDgABLgAECgkJIAAPAHIgAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgAECgEJAQAAAA==.Holybeatdown:BAAALgAECgMJBAAAAA==.Holyrage:BAAALgADCgQJBAAAAA==.Holyßloodelf:BAAALgAECggJCwABLgAECggJFwAPAFsUAA==.Honeysbadger:BAAALgAECgMJAwAAAA==.Hoosier:BAAALgAECgQJBQAAAA==.Hornet:BAABLgAECn8VAAMXAAgJZBByWQBiAQAXAAgJ7w9yWQBiAQAHAAQJFwz3SADPAAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.Hotsauce:BAAALgAECgYJCAABLgAFFAcJGgARAOIaAA==.',
Hu='Huasca:BAAALgAECgMJBQAAAA==.Humungous:BAAALgAECgcJDQAAAA==.Hunnybunz:BAAALgAECgYJDAAAAA==.',
['Hà']='Hàney:BAEALgAECgYJBwAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJEgAAAA==.',
['Hé']='Hélio:BAAALgAECgQJBAAAAA==.',
Ia='Ia:BAABLgAFFH8HAAIQAAQJEQxMCwAaAQAQAAQJEQxMCwAaAQAAAA==.',
Ic='Icastfirebal:BAAALgAECgEJAQAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECggJDAAAAA==.',
Ig='Igotahitin:BAAALgADCgMJCAAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAABLgAECn8bAAIbAAgJOBHTJABzAQAbAAgJOBHTJABzAQAAAA==.',
Il='Illida:BAAALgAECgMJAwAAAA==.',
Im='Imamalelol:BAABLgAECn8dAAQTAAYJjgtKTAD+AAATAAYJjgtKTAD+AAASAAQJVAMFcQApAAAVAAEJqgAUWQATAAAAAA==.',
In='Indira:BAAALgADCgcJDQAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAUJCQABLgAFFAUJDAAUAMMNAQ==.Inumimi:BAABLgAECn8dAAIlAAgJ5AT3IwDDAAAlAAgJ5AT3IwDDAAAAAA==.Invincidemon:BAAALgAECgQJBAAAAA==.',
Ir='Irkenfox:BAECLgAFFH8cAAIVAAYJgyFfBQDFAQAVAAYJgyFfBQDFAQAuAAQKfyUAAhUACAmhI54DABsDABUACAmhI54DABsDAAAA.',
It='Ithran:BAABLgAECn8nAAIRAAkJKQwRaQCRAQARAAkJKQwRaQCRAQAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8wAAIZAAkJ5x0FAQC0AgAZAAkJ5x0FAQC0AgAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.Jama:BAAALgADCgcJCAAAAA==.James:BAACLgAFFH8YAAIRAAQJmxanQABMAQARAAQJmxanQABMAQAuAAQKf0MAAhEACQnUIK8PAOoCABEACQnUIK8PAOoCAAAA.Janderick:BAABLgAECn8gAAITAAgJQiDTFAA2AgATAAgJQiDTFAA2AgAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jellacee:BAABLgAECn8aAAMHAAUJeRFZPwCUAAAHAAUJeRFZPwCUAAAXAAIJHgNMAQEtAAAAAA==.Jesterjoe:BAAALgAECgQJCAAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8eAAIDAAYJhCKqAQDMAQADAAYJhCKqAQDMAQAuAAQKfy8AAgMACQmfIfQAAC8DAAMACQmfIfQAAC8DAAAA.Jimi:BAAALgADCgUJBQAAAA==.Jimreaper:BAAALgAECgkJCQAAAA==.Jinkx:BAAALgADCgkJCQABLgAECgkJOAAkANQeAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJBAABLgAECggJGAAhAHkjAA==.',
Jo='Joejitsu:BAAALgAECgMJAwAAAA==.Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAABLgAECn8dAAQDAAgJLx7xCACeAQADAAYJrx3xCACeAQACAAMJ0ButqQDkAAABAAEJXCB1KgBKAAAAAA==.Joltraxi:BAAALgAECgMJBQAAAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJEwABLgAECggJGAAhAHkjAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Js='Jstnbieber:BAAALgAECgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCgAAAA==.Juicethevoid:BAABLgAECn8pAAIXAAkJnwe9ZwA8AQAXAAkJnwe9ZwA8AQAAAA==.Juniornite:BAABLgAECn82AAIRAAkJmCBhEwDRAgARAAkJmCBhEwDRAgAAAA==.Justicus:BAAALgAECgYJEQABLgAECggJIQAHAO4iAA==.Justthetouch:BAAALgAECggJCQAAAA==.',
Jy='Jygglypuff:BAAALgAECgYJBQAAAA==.',
['Jü']='Jüst:BAAALgAECgMJAwAAAA==.',
Ka='Kaeldrin:BAAALgADCgkJFAAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAABLgAECn8zAAQHAAkJqhghEQD4AQAHAAgJ7RchEQD4AQAGAAcJVhX5DABsAQAXAAgJsA5NXQBYAQAAAA==.Kahgar:BAAALgAECgYJBgABLgAECggJLQAOABgRAA==.Kaiser:BAAALgAECgQJCQAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgQJCwAAAA==.Kalzod:BAACLgAFFH8RAAICAAQJoRuEOABFAQACAAQJoRuEOABFAQAuAAQKfz4AAwIACQlLJtYBAHMDAAIACQlLJtYBAHMDAAEAAQkAAB0kAGEAAAAA.Kariana:BAAALgAECgYJDgAAAA==.Kataki:BAAALgAECgMJBAABLgAECgkJMwAHAKoYAA==.Katett:BAAALgAECgcJDgAAAA==.Kativeria:BAAALgAECgUJCAAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDwABLgAECgYJDgAKAAAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgYJEgAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Kerfufle:BAAALgAECgMJAwAAAA==.Keyn:BAAALgADCgEJAQAAAA==.Keynstolor:BAABLgAECn8hAAIdAAgJRBrLPADVAQAdAAgJRBrLPADVAQAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.Khálifá:BAAALgAECgUJBgAAAA==.',
Ki='Kicker:BAABLgAECn8UAAITAAYJcgaQXQDDAAATAAYJcgaQXQDDAAAAAA==.Killmora:BAAALgAECgMJBQAAAA==.Kippars:BAABLgAECn8aAAMhAAcJBRRIKADuAAAhAAYJuhNIKADuAAAlAAEJfRWGPwBAAAAAAA==.Kiritsugo:BAAALgADCggJFQAAAA==.Kissame:BAAALgAECgYJCAAAAA==.',
Kn='Knaifu:BAAALgADCgkJDQAAAA==.',
Ko='Kodazoff:BAABLgAECn8wAAMiAAkJUhLNGgDnAQAiAAkJUhLNGgDnAQAUAAIJIAdMNwAzAAAAAA==.Korevash:BAABLgAECn8mAAMaAAcJjBw3DQDCAQAaAAcJjBw3DQDCAQAFAAIJ4wn5qABVAAABLgAFFAQJFQAIAKYTAA==.Korupta:BAABLgAECn8uAAMXAAgJHBCWWgBfAQAXAAgJHBCWWgBfAQAHAAUJ3A36PQAFAQABLgAECgkJJAACADgSAA==.Korzilius:BAAALgAECggJEAAAAA==.',
Kr='Krissylu:BAABLgAECn8dAAIBAAYJ4AwiFAAJAQABAAYJ4AwiFAAJAQAAAA==.Krockett:BAAALgAECgQJBAAAAA==.Krothix:BAABLgAECn88AAILAAkJPQyPLgBuAQALAAkJPQyPLgBuAQAAAA==.Kruvix:BAAALgAECgYJCgAAAA==.Kryjag:BAAALgAECgMJBgAAAA==.Krynir:BAAALgADCgkJDgAAAA==.Kryshym:BAAALgAECggJCQAAAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAAALgAECgUJDgAAAA==.',
['Kü']='Kürömë:BAAALgADCgMJAwAAAA==.',
La='Ladara:BAABLgAECn8tAAIBAAkJ8BAkCADLAQABAAkJ8BAkCADLAQAAAA==.Laima:BAAALgADCgYJDQAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAgAAAA==.Lavitz:BAAALgAECgMJAwAAAA==.',
Le='Leheo:BAAALgAECgQJCgAAAA==.Lehua:BAAALgADCggJDAAAAA==.Leilanii:BAAALgAECgMJBQAAAA==.Lemook:BAAALgAECgcJCwAAAA==.Leonìdas:BAAALgAECgQJBgAAAA==.',
Lh='Lhei:BAAALgAECgQJBgAAAA==.',
Li='Lightstormer:BAAALgAECgMJBQAAAA==.Lilamae:BAAALgAECgcJCwAAAA==.Lilarielle:BAABLgAECn80AAIlAAgJcQgEHgDyAAAlAAgJcQgEHgDyAAAAAA==.Lildash:BAAALgADCgIJAgABLgAECggJJAAMAMIcAA==.Lilface:BAAALgAECgYJCgAAAA==.Liliela:BAAALgAECgQJBAABLgAECggJJAAMAMIcAA==.Lilsham:BAAALgAECgQJBAABLgAECggJJAAMAMIcAA==.Lilyannah:BAAALgAECgkJAQAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgIJAgAKAAAAAA==.Liopain:BAAALgAECgIJAgAAAA==.Liø:BAAALgAECgEJAQABLgAECgIJAgAKAAAAAA==.',
Lo='Lokir:BAAALgAECgMJBgAAAA==.Lotheovian:BAEALgAECgIJAgABLgAECgkJLgAPAJsaAA==.Lowchin:BAAALgAECgYJEwAAAA==.',
Lu='Lumia:BAABLgAECn8dAAMWAAkJix4wEwBcAgAWAAcJlB8wEwBcAgAJAAYJFBjVSgANAQAAAA==.Lutherion:BAAALgAECggJEAAAAA==.',
Ly='Lycemmas:BAAALgAECgQJBAAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgAECgEJAQAAAA==.Mackshiesty:BAABLgAECn8ZAAIXAAYJ3xr4TQCEAQAXAAYJ3xr4TQCEAQAAAA==.Macoun:BAABLgAECn8rAAMdAAkJpiS9BQAnAwAdAAkJpiS9BQAnAwAeAAYJEhv0QABVAQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn9AAAIRAAkJCCZiBABVAwARAAkJCCZiBABVAwAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAABLgAECn8bAAIWAAcJGAwlNgAbAQAWAAcJGAwlNgAbAQAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBgAKAAAAAA==.Martei:BAACLgAFFH8aAAIlAAUJbBhBBQA+AQAlAAUJbBhBBQA+AQAuAAQKfy8AAiUACQm/IkICAC8DACUACQm/IkICAC8DAAAA.Maríneth:BAAALgAECgQJDgAAAA==.Mathías:BAABLgAECn8nAAIdAAkJgBlPIwA/AgAdAAkJgBlPIwA/AgAAAA==.Mavze:BAAALgADCgIJAgAAAA==.',
Me='Meadowfrey:BAAALgAECgEJAQAAAA==.Meowbae:BAABLgAECn8uAAMlAAkJGhVMCgD6AQAlAAkJGhVMCgD6AQAkAAEJNAENmAAVAAAAAA==.Mercesdes:BAAALgAECgUJBgAAAA==.Mercina:BAAALgAECgEJBAAAAA==.Mercuros:BAABLgAECn8UAAMJAAkJawMfOAAFAQAJAAkJawMfOAAFAQAWAAIJrgMVbQBFAAAAAA==.Merknlock:BAAALgAECgEJAQAAAA==.',
Mi='Midnyte:BAABLgAECn9EAAMgAAkJwRr6DABgAgAgAAkJwRr6DABgAgAfAAkJshP/HAAKAgAAAA==.Milkyweí:BAAALgAECgMJAwAAAA==.Mini:BAAALgADCgUJBQABLgAECggJKwARAOweAA==.Minizee:BAAALgAECgYJCAAAAA==.Mirabella:BAAALgAECgQJBgABLgAFFAQJCAAfABsXAA==.Mirokushan:BAAALgAECgQJEAAAAA==.Mistfit:BAAALgAECgMJAgAAAA==.Misticlady:BAAALgADCgEJAQAAAA==.Mistingmoo:BAAALgAECgQJBAABLgAECgcJFwASAMIKAA==.Mistrariel:BAABLgAECn8oAAIGAAkJuh7DAgCyAgAGAAkJuh7DAgCyAgAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Moostafa:BAAALgAECgQJBAAAAA==.Moradin:BAAALgADCgIJAgAAAA==.Mordemour:BAAALgAECgYJEAAAAA==.',
Mu='Mungo:BAABLgAECn8qAAIRAAgJTBgnSADrAQARAAgJTBgnSADrAQAAAA==.',
My='My:BAAALgAECgkJDgAAAA==.Mynkie:BAACLgAFFH8TAAIfAAQJkBRhIwD+AAAfAAQJkBRhIwD+AAAuAAQKfzYAAh8ACQlfIm4DAG4DAB8ACQlfIm4DAG4DAAAA.Myrell:BAAALgAECgkJBgAAAA==.Mythreashis:BAAALgADCgMJAwAAAA==.',
['Mä']='Mägi:BAAALgAECgEJAQAAAA==.',
['Må']='Mååt:BAAALgADCgIJAgAAAA==.',
['Mæ']='Mæstra:BAAALgADCgQJBAAAAA==.',
['Më']='Mëlony:BAAALgADCgIJAgAAAA==.',
Na='Nachtmar:BAAALgAECgQJDQAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8fAAIXAAYJKxR+IgB2AQAXAAYJKxR+IgB2AQAuAAQKfyoAAhcACAlDHPItAPkBABcACAlDHPItAPkBAAAA.Nalik:BAAALgAECgUJBAAAAA==.',
Ne='Necia:BAAALgADCgEJAQABLgAECgkJJwAJAPsLAA==.Neltu:BAAALgAECgEJAQAAAA==.Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nikkitta:BAAALgADCgMJAwAAAA==.Nimravidae:BAABLgAECn8yAAMOAAgJCxfrHQD9AQAOAAgJCxfrHQD9AQANAAcJkg8SjAA+AQAAAA==.Ninelives:BAABLgAECn8iAAIkAAkJSwO0RQDYAAAkAAkJSwO0RQDYAAAAAA==.Nitecrawler:BAABLgAECn8hAAMRAAgJ2Q5XcwB4AQARAAgJ2Q5XcwB4AQAmAAEJhQM+FgAbAAAAAA==.Niteryu:BAAALgAECgkJEQABLgAECgkJNgARAJggAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAABLgAECn8hAAIiAAgJ+wsBNQA8AQAiAAgJ+wsBNQA8AQAAAA==.Noxium:BAAALgAECgYJDQAAAA==.Noxolon:BAABLgAECn8yAAITAAgJZxxdFwAfAgATAAgJZxxdFwAfAgAAAA==.',
Nr='Nreaf:BAABLgAECn8yAAMNAAkJKRy9JACUAgANAAkJKRy9JACUAgAMAAQJChcfJQDfAAAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgQJCAAAAA==.Nydhogg:BAAALgADCgkJCQABLgAECgkJKAAGALoeAA==.Nysca:BAAALgADCgcJBwAAAA==.',
Ob='Obijuan:BAAALgAECgMJAwAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAAALgAECgYJDAAAAA==.',
Or='Ornstein:BAABLgAECn8eAAMMAAYJmiE4DQDWAQAMAAYJmiE4DQDWAQANAAYJGBAirwAEAQAAAA==.',
Ot='Ottuk:BAACLgAFFH8TAAMPAAUJpxU+VgArAQAPAAQJpxU+VgArAQAYAAEJAAAYUgAAAAAuAAQKfyIAAw8ACQnVIa8IAFgDAA8ACQnVIa8IAFgDABgAAwlnHX0nAAMBAAAA.',
Pa='Padinbar:BAAALgAECgQJBAABLgAECgYJCQAKAAAAAA==.Paksenarrion:BAABLgAECn8zAAIMAAgJdBEXFABxAQAMAAgJdBEXFABxAQAAAA==.Pancham:BAAALgADCgUJBQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECgkJEQAAAA==.Pandemônium:BAAALgAECggJEAAAAA==.Pandemönium:BAAALgAECgIJAQAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Pandèmonium:BAAALgAECgYJBgAAAA==.Patchington:BAAALgAECgQJDgAAAA==.Pañdemönium:BAAALgAECgUJBQAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Perck:BAAALgAECgQJBAAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAFFAIJBgAiAIgTAA==.Pezvoker:BAABLgAFFH8GAAIiAAIJiBNdRQCGAAAiAAIJiBNdRQCGAAAAAA==.',
Pi='Pienarri:BAAALgAECgEJAgAAAA==.Pixelme:BAAALgAECgMJBQAAAA==.',
Pl='Pleggster:BAABLgAECn8ZAAMFAAgJJA53RgB4AQAFAAgJJA53RgB4AQALAAEJiAFAqwAbAAAAAA==.',
Po='Pochula:BAABLgAECn8kAAIEAAgJaxXRJwD/AQAEAAgJaxXRJwD/AQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAABLgAECn8tAAMOAAgJGBHeNwCbAQAOAAgJGBHeNwCbAQANAAIJSgT3TwFFAAAAAA==.Protricity:BAABLgAECn88AAMWAAkJdCBCCACxAgAWAAkJdCBCCACxAgAJAAEJ2AJchAAtAAAAAA==.',
Pu='Pumpernickel:BAAALgADCgUJBQABLgAFFAUJEwAGACMhAA==.Puppytoes:BAAALgAECgYJDgAAAA==.',
Py='Pyrellyn:BAAALgADCggJCgAAAA==.',
['Pä']='Pändamönium:BAAALgAECgkJEQAAAA==.Pändemönium:BAAALgAECgMJAwAAAA==.',
['Pæ']='Pæn:BAACLgAFFH8MAAIPAAUJ6iUZHgCzAQAPAAUJ6iUZHgCzAQAuAAQKfy0AAw8ABwnHJWodAIQCAA8ABwnHJWodAIQCABgABwmPH6oRANgBAAAA.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgUJCAABLgAECgYJCwAKAAAAAA==.Quantar:BAAALgAECgYJCwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rakta:BAAALgAECgYJCgAAAA==.Rancooll:BAAALgAECgMJBQAAAA==.Rasniir:BAABLgAECn9DAAIEAAkJyyClBQBRAwAEAAkJyyClBQBRAwAAAA==.Ravenlash:BAAALgAECgEJBAAAAA==.',
Re='Regna:BAACLgAFFH8eAAITAAYJ0SZeAgAsAgATAAYJ0SZeAgAsAgAuAAQKfzAAAhMACQmaJhgDAH8DABMACQmaJhgDAH8DAAAA.Regner:BAAALgAECgEJAQAAAA==.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAABLgAECn8VAAIYAAcJlQyyKAD3AAAYAAcJlQyyKAD3AAAAAA==.Remaked:BAACLgAFFH8rAAIbAAcJgR02BgD3AQAbAAcJgR02BgD3AQAuAAQKf0AAAhsACQmsI1kDAA8DABsACQmsI1kDAA8DAAAA.Remilia:BAABLgAECn8tAAIWAAgJnR1LDgBXAgAWAAgJnR1LDgBXAgAAAA==.Requinix:BAABLgAECn9FAAIdAAkJIxgzJAA7AgAdAAkJIxgzJAA7AgAAAA==.Retro:BAAALgAECgEJAQAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAECggJBwAAAA==.Revwrinkle:BAAALgAECgIJAwAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgUJEAAAAA==.Ricochet:BAABLgAECn8eAAIcAAgJphHcGwCvAQAcAAgJphHcGwCvAQAAAA==.Riptidez:BAAALgADCgcJBgAAAA==.Ririko:BAABLgAECn8uAAIJAAgJEw+1JwByAQAJAAgJEw+1JwByAQAAAA==.Ritzo:BAABLgAECn8oAAITAAgJnBQgJgCyAQATAAgJnBQgJgCyAQAAAA==.Rizzla:BAAALgAECgIJAgABLgAECgkJOAAkANQeAA==.',
Ro='Rockllobster:BAAALgAECgYJDAAAAA==.Rocksanne:BAAALgADCgcJEAAAAA==.Roguebâit:BAABLgAECn9IAAQBAAkJ9BzxAgB6AgABAAgJFRzxAgB6AgACAAcJjBQGUACfAQADAAMJJw3SRACiAAAAAA==.Ronarvinge:BAAALgAECgYJCQAAAA==.Ronen:BAAALgAECgQJBAAAAA==.',
Ru='Rubywolf:BAAALgAECgYJDgABLgAECgkJKAAkAEQXAA==.Rukkis:BAABLgAECn8lAAMnAAkJ7xrRCACCAgAnAAkJ7xrRCACCAgAoAAEJjQnYIAAvAAAAAA==.Rumi:BAACLgAFFH8SAAIGAAQJRB3HAgBMAQAGAAQJRB3HAgBMAQAuAAQKf0sAAwYACQnrJLwAAD8DAAYACQnrJLwAAD8DAAcAAQlvEWBfADIAAAAA.',
Ry='Ryeekan:BAABLgAECn8mAAIdAAgJEhToRgC1AQAdAAgJEhToRgC1AQAAAA==.',
['Ró']='Róronoà:BAAALgAECgQJBgAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAABLgAECn8mAAINAAkJ7hZcUQC8AQANAAkJ7hZcUQC8AQAAAA==.Saelena:BAAALgADCgEJAQAAAA==.Sakheddala:BAAALgAECgQJBAAAAA==.Sancha:BAAALgAECgUJBQAAAA==.Sanosagara:BAABLgAECn84AAIfAAgJFBmiFgBBAgAfAAgJFBmiFgBBAgAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgAECgIJAwAAAA==.Sarithon:BAAALgAECgYJBgAAAA==.Saru:BAAALgADCgkJDQAAAA==.Saruta:BAACLgAFFH8VAAMTAAQJ5BjQFABKAQATAAQJ5BjQFABKAQASAAEJdQOaOAA4AAAuAAQKfy8AAxMACAmAIJMQAGACABMACAmAIJMQAGACABIABQmqDwoWAE4BAAAA.Sath:BAAALgAECgQJBAAAAA==.Sathari:BAABLgAECn8oAAIXAAgJfBWBTgCDAQAXAAgJfBWBTgCDAQAAAA==.Satsuki:BAABLgAECn8bAAMIAAcJORy0EwAiAgAIAAcJORy0EwAiAgAWAAUJfxUmLwBCAQABLgAFFAQJFQAXACEcAA==.',
Sc='Scarycat:BAAALgADCgYJBgAAAA==.Schaden:BAAALgAECgEJAQABLgAECggJFAAEAAIhAA==.',
Se='Seijo:BAAALgAECgMJAwAAAA==.Sekk:BAABLgAECn9MAAINAAkJ4B+cEADNAgANAAkJ4B+cEADNAgAAAA==.Selexi:BAAALgADCgYJEAAAAA==.Sereya:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.Sesshanmaru:BAAALgADCgcJBwAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAABLgAECn8/AAIHAAgJBR85CQB7AgAHAAgJBR85CQB7AgAAAA==.Shadoshiftt:BAABLgAECn8kAAMkAAgJ2AYVPgD6AAAkAAgJ2AYVPgD6AAAEAAgJGALwlwCeAAAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgAECgMJBQAAAA==.Shamzee:BAACLgAFFH8PAAMFAAQJZxxgHgBQAQAFAAQJZxxgHgBQAQALAAEJrQLvTAA1AAAuAAQKfygAAwUACAkZHboZAGMCAAUACAkZHboZAGMCAAsAAQlWDa+TADEAAAAA.Shandalf:BAAALgAECgQJDwABLgAECgQJEAAKAAAAAA==.Shansebaim:BAAALgAECgYJBgAAAA==.Shintok:BAAALgAECggJCQAAAA==.Shuddarun:BAACLgAFFH8gAAIdAAYJoSBhCgDHAQAdAAYJoSBhCgDHAQAuAAQKfywAAh0ACQlPIsUDAFQDAB0ACQlPIsUDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgADCgcJDQAKAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simn:BAABLgAECn8bAAIdAAgJQhwwKAAnAgAdAAgJQhwwKAAnAgAAAA==.Sindraesong:BAAALgAECggJEgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgAECgIJBAAAAA==.',
Sk='Skithiryx:BAAALgADCgkJCQABLgAECgkJMwAHAKoYAA==.Skrai:BAAALgAECgYJCgABLgAECggJIAAVANshAA==.',
Sl='Slayvylora:BAACLgAFFH8dAAMNAAYJyBjPDQA8AQANAAUJ+RXPDQA8AQAOAAEJ+QLxPQBHAAAuAAQKfzMABA0ACQnKIW4SAMECAA0ACQnKIW4SAMECAA4ABQmWB29uAMEAAAwAAgn2FpsyAH8AAAAA.Sleep:BAAALgAECgQJBAABLgAFFAQJBwAQABEMAA==.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgAECgIJBQAAAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Sneakymoth:BAAALgAECgYJEwABLgAECggJJAARAJUVAA==.Sniff:BAABLgAECn8rAAIRAAgJ7B5wKQBeAgARAAgJ7B5wKQBeAgAAAA==.Snookums:BAABLgAECn84AAIXAAcJLRzMOADNAQAXAAcJLRzMOADNAQAAAA==.',
So='Soulomon:BAABLgAECn8ZAAICAAkJsRMwgwBUAQACAAkJsRMwgwBUAQAAAA==.Soulsarisen:BAAALgAECgYJDwAAAA==.',
Sp='Spanki:BAAALgADCgkJEAAAAA==.Spellteaser:BAABLgAECn8UAAIRAAYJOhkguQBvAQARAAYJOhkguQBvAQAAAA==.Spicymaker:BAABLgAECn8mAAISAAgJ5yDSBwBiAgASAAgJ5yDSBwBiAgAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJCgAAAA==.Steelheart:BAAALgAECgEJBwAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Stolensøul:BAAALgADCgkJDgAAAA==.Strifewood:BAABLgAECn8bAAIYAAgJzBiXFwCNAQAYAAgJzBiXFwCNAQAAAA==.Stumper:BAABLgAECn84AAIkAAkJ1B7aBwDEAgAkAAkJ1B7aBwDEAgAAAA==.',
Su='Sugondese:BAAALgAECgQJBgAAAA==.Suluna:BAAALgAECgUJBQABLgAECgkJQAAFAJQbAA==.Summêr:BAABLgAECn8XAAIfAAYJdAeoYQC5AAAfAAYJdAeoYQC5AAAAAA==.Suri:BAAALgAECgUJCgABLgAECggJDgAKAAAAAA==.Sux:BAABLgAECn8ZAAIhAAgJqg4NJgD8AAAhAAgJqg4NJgD8AAAAAA==.',
Sy='Sybrina:BAABLgAECn8bAAIdAAkJLhSdLQAPAgAdAAkJLhSdLQAPAgAAAA==.Sylvia:BAAALgADCgcJBgABLgAECgEJAQAKAAAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAABLgAECn81AAIdAAYJ4QsIiwAPAQAdAAYJ4QsIiwAPAQAAAA==.Synèsterwolf:BAAALgAECgIJAwABLgAECgkJKAAkAEQXAA==.',
['Sí']='Síf:BAAALgAECgcJDQAAAA==.',
Ta='Tabernacle:BAAALgAECgUJBQAAAA==.Tadeusz:BAAALgAECgYJCwAAAA==.Tamamò:BAABLgAECn8WAAIfAAcJ1BGPKABvAQAfAAcJ1BGPKABvAQAAAA==.Tarrok:BAAALgADCgMJBwAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAAALgAECgMJBQAAAA==.Tepache:BAAALgADCgEJAQAAAA==.Tequitos:BAABLgAECn8dAAMOAAgJNAyRPQA4AQAOAAgJNAyRPQA4AQANAAYJnwvsyADeAAAAAA==.Teranin:BAABLgAECn8UAAIkAAcJPwh5QwDiAAAkAAcJPwh5QwDiAAAAAA==.',
Tf='Tfortyone:BAAALgAECgUJCAAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgIJAgAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAACLgAFFH8TAAIRAAQJxR5nMQB5AQARAAQJxR5nMQB5AQAuAAQKf0sAAhEACQnNJdkCAGoDABEACQnNJdkCAGoDAAAA.',
Ti='Tiren:BAAALgAECgYJDQAAAA==.',
To='Torag:BAAALgAECgQJBAAAAA==.Torment:BAABLgAECn9NAAIYAAkJoB0+BwCUAgAYAAkJoB0+BwCUAgAAAA==.Tosti:BAAALgAECgkJAQAAAA==.',
Tr='Trepania:BAACLgAFFH8ZAAIJAAYJRwt4CgB5AQAJAAYJRwt4CgB5AQAuAAQKfy4AAgkACQm9GNEWACUCAAkACQm9GNEWACUCAAAA.Tristén:BAAALgAECgcJEAAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Trollycarp:BAABLgAECn8fAAMMAAgJvApgKAC5AAANAAgJlwNNygDcAAAMAAUJdhBgKAC5AAAAAA==.Truvie:BAAALgAECgYJCgAAAA==.',
Tu='Tumbler:BAABLgAECn8XAAMFAAgJix0PGABwAgAFAAgJix0PGABwAgALAAMJCBH+ZgCTAAAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAABLgAECn83AAMFAAYJdAyTbAD2AAAFAAYJdAyTbAD2AAALAAYJkQxhTQDjAAAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAABLgAECn8jAAIcAAkJRxFiEwD/AQAcAAkJRxFiEwD/AQAAAA==.',
Ul='Ulnuk:BAACLgAFFH8RAAIFAAQJRxerKwARAQAFAAQJRxerKwARAQAuAAQKfzkAAgUACQnvINsGAC8DAAUACQnvINsGAC8DAAAA.Ulster:BAAALgAECgIJAgAAAA==.',
Un='Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAAKAAAAAA==.',
Va='Vadka:BAAALgAECggJEQAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAAALgAECgQJDgAAAA==.Vairian:BAABLgAECn8ZAAIHAAcJqQ+GJQAoAQAHAAcJqQ+GJQAoAQAAAA==.Valkree:BAAALgAECgYJDAAAAA==.Vallae:BAAALgADCgkJEQABLgAECgkJQAAFAJQbAA==.Valsavis:BAABLgAECn9DAAIGAAkJtxzYAwB6AgAGAAkJtxzYAwB6AgAAAA==.Valtier:BAAALgAECgcJCwAAAA==.Vampirä:BAABLgAECn8iAAQEAAkJQQXEfQCuAAAEAAgJAgTEfQCuAAAlAAQJngXmLwB5AAAkAAIJrgOweQA8AAAAAA==.Varactor:BAAALgAECgMJAwAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAIgAAgJ7iA1CAD3AgAgAAgJ7iA1CAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgUJCAAAAA==.Vernice:BAAALgAECgEJAQABLgAECgYJEAAKAAAAAA==.Verulan:BAABLgAECn8dAAQkAAcJjgoCPQD/AAAkAAcJiQkCPQD/AAAEAAQJjAruiQCQAAAlAAEJKA4QRQAyAAAAAA==.Vexeh:BAAALgAECgMJBAAAAA==.Vexomous:BAAALgAECgUJDwAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vierina:BAAALgAECgEJAQAAAA==.Vikss:BAABLgAECn8vAAMdAAkJExKkPADWAQAdAAkJExKkPADWAQAcAAYJXQQsHQAFAQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgAECgMJAwAAAA==.Vivien:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAIlAAcJ6x9tCABYAgAlAAcJ6x9tCABYAgABLgAECggJIQAHAO4iAA==.',
Vo='Voidmayne:BAABLgAECn8/AAINAAkJjBEqTADKAQANAAkJjBEqTADKAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgUJEQAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.Voxella:BAAALgAECgQJBAAAAA==.',
Vr='Vrel:BAAALgADCgkJDgAAAA==.',
Vy='Vyv:BAABLgAECn8UAAILAAcJtAXLTwDbAAALAAcJtAXLTwDbAAAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAIXAAYJEhyzTQC+AQAXAAYJEhyzTQC+AQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Wayadra:BAABLgAECn8XAAQiAAkJkSGxBgDYAgAiAAkJkSGxBgDYAgAjAAcJSQTlJgDrAAAUAAEJlgrESQAvAAAAAA==.',
We='Weiand:BAABLgAECn8vAAMNAAkJUhtdLwAqAgANAAgJpxpdLwAqAgAOAAEJOwdzgQAzAAAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAACLgAFFH8FAAMCAAMJngcenwBzAAACAAIJHAcenwBzAAADAAEJoQhvIwBDAAAuAAQKfx8ABAIACAlBFPBFAPkBAAIACAlBFPBFAPkBAAMAAgnvD39XAGgAAAEAAQkAAA4xADwAAAAA.Wholemilk:BAABLgAECn8nAAIXAAgJYSC0FgB6AgAXAAgJYSC0FgB6AgAAAA==.',
Wi='Wiggz:BAAALgAECgYJBgAAAA==.Wilhellena:BAABLgAECn8/AAIJAAkJwx7MBQAKAwAJAAkJwx7MBQAKAwAAAA==.Wilhellfu:BAAALgAECgIJBAAAAA==.Winariel:BAAALgAECgUJBwABLgAECgkJKAAGALoeAA==.Wisteria:BAAALgAECgEJAQABLgABCgEJAQAKAAAAAA==.',
Wr='Wroughtsoul:BAAALgAECgEJAgAAAA==.Wrëckagë:BAAALgAECgcJEwAAAA==.',
Wu='Wumbo:BAAALgAECgYJBwAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAABLgAECn8kAAICAAkJOBIzPgDWAQACAAkJOBIzPgDWAQAAAA==.Xandir:BAABLgAECn84AAIMAAkJPhJREAClAQAMAAkJPhJREAClAQAAAA==.Xarhunt:BAAALgAECgYJBgAAAA==.Xaric:BAABLgAECn8nAAIEAAkJXhnhIwAZAgAEAAkJXhnhIwAZAgAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xy='Xyal:BAABLgAECn8sAAIJAAgJpiEfCADWAgAJAAgJpiEfCADWAgAAAA==.Xyp:BAAALgAECgEJAQABLgAECgcJHQAkAI4KAA==.',
Yg='Ygor:BAAALgAECgUJDwAAAA==.',
Yi='Yiago:BAAALgAECgQJDgAAAA==.',
Yo='Yobabydaddy:BAAALgAECgMJAwAAAA==.Youknow:BAAALgAECgUJCAAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.Yungslug:BAAALgAECgIJAgAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zany:BAAALgADCgIJAgAAAA==.Zaranorinn:BAABLgAECn8dAAINAAkJ0AeSiABEAQANAAkJ0AeSiABEAQAAAA==.Zaxhdk:BAEBLgAECn8uAAMPAAkJmxrtIQBsAgAPAAkJmxrtIQBsAgAYAAUJTwZPPQCCAAAAAA==.Zaxhmonk:BAEALgADCgkJCQABLgAECgkJLgAPAJsaAA==.',
Ze='Zedex:BAAALgADCgcJCAABLgADCggJDQAKAAAAAA==.Zedru:BAAALgADCggJDQAAAA==.Zenstormer:BAAALgADCgQJBAABLgAECgMJBQAKAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zephyrion:BAAALgAECgQJCAAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAABLgAECn8VAAIPAAYJfx1RfQBTAQAPAAYJfx1RfQBTAQAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAABLgAECn8eAAIFAAgJZBlUKgD4AQAFAAgJZBlUKgD4AQAAAA==.Zinrar:BAABLgAECn8hAAIPAAgJeBnLPwDxAQAPAAgJeBnLPwDxAQAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8vAAIRAAcJlwgVqgAPAQARAAcJlwgVqgAPAQAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAABLgAECn8rAAMcAAgJrBVNGwC0AQAcAAgJyBRNGwC0AQAdAAEJKRpC+wBBAAAAAA==.',
Zu='Zushi:BAAALgAECgUJBQAAAA==.',
['Äl']='Älphawolf:BAABLgAECn8oAAQkAAkJRBcxGQDqAQAkAAkJERYxGQDqAQAhAAQJ+hT9JQD9AAAEAAIJdgg/tABGAAAAAA==.',
['Ðê']='Ðêmønicßløøð:BAABLgAECn8XAAIPAAgJWxSdUgC4AQAPAAgJWxSdUgC4AQAAAA==.',
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
