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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Druid-Restoration','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Protection','Shaman-Elemental','Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Paladin-Holy','DeathKnight-Frost','Mage-Frost','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Priest-Shadow','DemonHunter-Devourer','DeathKnight-Blood','Mage-Fire','Monk-Brewmaster','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Mistweaver','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Druid-Feral','Mage-Arcane','Rogue-Outlaw',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aabbigale:BAAALgAECgkJBwAAAA==.',
Ab='Abigt:BAABLgAECn8YAAMBAAcJDiDIBwDtAQABAAcJDiDIBwDtAQACAAQJexGexQDOAAAAAA==.',
Ad='Adalaidê:BAAALgAECgYJEAAAAA==.',
Ae='Aelusion:BAACLgAFFH8GAAICAAMJ3xZDbQDjAAACAAMJ3xZDbQDjAAAuAAQKfx8ABAIACAlIHzwaALcCAAIACAmBHjwaALcCAAMAAwlaIRUsAA4BAAEAAQlAJCInAFUAAAEuAAUUBQkLAAQAwhUA.Aeluu:BAAALgAECgcJBwABLgAECggJHwAFALgRAA==.Aerola:BAAALgADCgIJAgAAAA==.Aerynne:BAAALgAECgQJEQAAAA==.',
Ai='Aidén:BAAALgAECgEJAQAAAA==.Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn88AAIGAAgJABQaLwD1AQAGAAgJABQaLwD1AQAAAA==.Aita:BAACLgAFFH8WAAIHAAUJAhcjBQATAQAHAAUJAhcjBQATAQAuAAQKfyMAAwcACQnXGO4GAB0CAAcACQnXGO4GAB0CAAgABQmWCcVCAKYAAAAA.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJCQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Alisaa:BAAALgAECgUJCAAAAA==.Alistanë:BAAALgAECgUJCQAAAA==.Allegria:BAAALgAECgEJAgAAAA==.Alluna:BAAALgAECgYJCgAAAA==.Alondra:BAABLgAECn8gAAIDAAkJvB8jAgCiAgADAAkJvB8jAgCiAgAAAA==.Alulà:BAABLgAECn8gAAMJAAcJbh4wEgBRAgAJAAcJTB4wEgBRAgAKAAMJMx4lTQAEAQAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.Aluuni:BAABLgAECn8jAAILAAkJOxcKCABDAgALAAkJOxcKCABDAgAAAA==.',
Am='Amednato:BAAALgAECgcJDgABLgAECggJIQAMALYhAA==.Amo:BAAALgAECgIJAgABLgAECggJFgANANwWAA==.',
An='Anaeli:BAABLgAECn9GAAMGAAkJ4BwsFQCeAgAGAAkJ4BwsFQCeAgAOAAUJ9wi7bACeAAAAAA==.Anariel:BAAALgADCgUJBQABLgADCgcJDQAPAAAAAA==.Ancalagonn:BAAALgAECgYJDgABLgAECgkJIwAGAMEPAA==.Androth:BAABLgAECn8mAAMQAAkJSht5CgAgAgAQAAgJwhx5CgAgAgARAAMJpQqUGQGWAAAAAA==.Angelius:BAAALgAECgEJBQAAAA==.Angita:BAAALgAECgUJCAAAAA==.Antipæn:BAACLgAFFH8bAAMSAAUJEyDbDwC2AQASAAUJEyDbDwC2AQARAAMJChsXZQDeAAAuAAQKf0oAAxEACQmfJhwBAIgDABEACQmfJhwBAIgDABIABwmNIvcpAOIBAAAA.',
Ap='Apologia:BAABLgAECn85AAIRAAgJNSRCGACvAgARAAgJNSRCGACvAgAAAA==.',
Ar='Arcanix:BAABLgAECn8UAAITAAcJxglQGAAPAQATAAcJxglQGAAPAQAAAA==.Arceé:BAAALgAECgMJBwAAAA==.Archaic:BAABLgAECn85AAIUAAkJvxE7VADdAQAUAAkJvxE7VADdAQAAAA==.Ardicelia:BAAALgAECgMJBAAAAA==.Ares:BAACLgAFFH8aAAMVAAcJyB/2AwBDAgAVAAcJyB/2AwBDAgAWAAIJCB71FgCuAAAuAAQKfyEAAxUACAlRJOUBABoDABUACAnfI+UBABoDABYABwlHIjMZAIICAAAA.Argomir:BAAALgAECgEJAQAAAA==.Ariellä:BAAALgADCgEJAQAAAA==.Arifault:BAAALgAECgMJAwABLgAECgkJRgAGAOAcAA==.Arilynx:BAABLgAECn8iAAIXAAkJ4AdpFwBWAQAXAAkJ4AdpFwBWAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn9KAAINAAkJFyTOAQA4AwANAAkJFyTOAQA4AwAAAA==.Aroviaa:BAABLgAECn9BAAQKAAkJVh4TCADoAgAKAAkJVh4TCADoAgAYAAEJHhEggAA4AAAJAAEJ9gPsgwAlAAAAAA==.Arpmek:BAABLgAECn80AAIZAAkJfhOOOQDdAQAZAAkJfhOOOQDdAQAAAA==.Artemîs:BAAALgAECgQJBAAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Ashal:BAABLgAECn8gAAMNAAcJQw0mJgD9AAAWAAcJ+ghtSwAXAQANAAcJQw0mJgD9AAAAAA==.Ashlynne:BAABLgAECn8WAAMNAAgJ3BbEFgCKAQANAAYJrBvEFgCKAQAWAAgJMAusOgBaAQAAAA==.Astrotoad:BAAALgAECgUJCgAAAA==.Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgYJBwAAAA==.Aurtt:BAABLgAECn9GAAIaAAkJHRdaEgDmAQAaAAkJHRdaEgDmAQAAAA==.',
Av='Avanel:BAAALgAECgEJAQAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Az='Azkadelia:BAAALgAECgEJAQAAAA==.',
Ba='Bageera:BAABLgAECn8uAAIFAAkJ8R1/CgASAwAFAAkJ8R1/CgASAwAAAA==.Bahahaknight:BAABLgAECn8+AAIaAAgJBiFvCQB7AgAaAAgJBiFvCQB7AgAAAA==.Barccky:BAAALgAECgIJAgAAAA==.Barcy:BAAALgAECgEJAwABLgAECgIJAgAPAAAAAA==.Barnette:BAACLgAFFH8NAAIbAAQJCAjpAgDlAAAbAAQJCAjpAgDlAAAuAAQKf0oAAhsACQlCGQcCAFcCABsACQlCGQcCAFcCAAAA.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearmissile:BAAALgAECgUJBwABLgAECggJJgALALwfAA==.Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn87AAIRAAkJ4x29GQCnAgARAAkJ4x29GQCnAgAAAA==.Berristan:BAACLgAFFH8LAAISAAMJkg5GMQCoAAASAAMJkg5GMQCoAAAuAAQKfzAAAxIACQkZGKIMALUCABIACQkZGKIMALUCABEABwnnCIjUAOoAAAAA.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigmarv:BAABLgAECn8gAAIOAAgJ6hfiMgBtAQAOAAgJ6hfiMgBtAQAAAA==.Bigsam:BAAALgAECgEJAQAAAA==.Bittytigs:BAAALgADCgUJBQAAAA==.',
Bl='Blossom:BAACLgAFFH8MAAIXAAUJww3hFgAfAQAXAAUJww3hFgAfAQAuAAQKfxUAAhcACAmdEY8YAM4BABcACAmdEY8YAM4BAAAA.Bluespruce:BAAALgAECgcJBwAAAA==.Bluewitchpa:BAAALgAECgUJDQAAAA==.',
Bo='Boomboomkill:BAAALgADCgEJAQAAAA==.Bosc:BAABLgAECn8sAAIaAAkJnR0cBwCpAgAaAAkJnR0cBwCpAgABLgAECggJHQAcAP0SAA==.Boudiicca:BAABLgAECn8dAAIKAAUJdRAyPwDtAAAKAAUJdRAyPwDtAAAAAA==.Boxmasterr:BAABLgAECn83AAMCAAkJhQ4eWQCRAQACAAkJFwweWQCRAQABAAcJ0wvLFAAiAQAAAA==.',
Br='Brasmir:BAABLgAECn8dAAIdAAkJ1guqGgDJAQAdAAkJ1guqGgDJAQAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.Brianzero:BAAALgAECgEJAQAAAA==.Brinotriage:BAAALgAECgUJBwAAAA==.',
Bu='Bubblement:BAAALgAFFAUJEgAAAQ==.Bubblemoth:BAAALgAECggJEQABLgAECgkJLQAUAM0WAA==.Bulge:BAAALgAFFAIJAgABLgAFFAYJGgAEAKIXAA==.Bulgogi:BAACLgAFFH8aAAIEAAYJohebNwCGAQAEAAYJohebNwCGAQAuAAQKfzoAAgQACQnqIUYNAAEDAAQACQnqIUYNAAEDAAAA.Bushalabong:BAAALgAECgMJBAAAAA==.Butherrface:BAAALgAECgIJAgAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgABLgAECgEJAQAPAAAAAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAACLgAFFH8SAAQdAAUJ3yKbDgBLAQAdAAQJ7B+bDgBLAQAMAAQJ/h3TLwBJAQAeAAEJAACqPAAAAAAuAAQKfzwABAwACQmHIzsoADoCAB0ACAnqH3gNAE8CAAwACAn9ITsoADoCAB4ABgmIF1YyAKUBAAAA.Cardran:BAAALgADCgEJAQABLgAECgkJJgAQAEobAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAISAAgJ3yHWBwDwAgASAAgJ3yHWBwDwAgAAAA==.Catamay:BAABLgAECn8gAAIZAAkJxRkEKgAeAgAZAAkJxRkEKgAeAgABLgAECgEJAQAPAAAAAA==.Catprincess:BAABLgAECn8fAAIFAAgJuBF+OwC3AQAFAAgJuBF+OwC3AQAAAA==.Cayda:BAAALgADCgYJBgAAAA==.Caylara:BAABLgAECn8fAAIfAAgJXBE9GwC5AQAfAAgJXBE9GwC5AQAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAABLgAECn8ZAAIZAAYJcw36lwDsAAAZAAYJcw36lwDsAAAAAA==.',
Ch='Chai:BAABLgAECn8VAAIgAAgJ2BGtJACKAQAgAAgJ2BGtJACKAQAAAA==.Chaintrain:BAAALgADCggJBwABLgAECgkJJQADAJMeAA==.Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAABLgAECn8mAAIcAAkJSBQjFwDuAQAcAAkJSBQjFwDuAQAAAA==.Chioma:BAAALgAECgQJBAAAAA==.',
Ci='Cindrethal:BAAALgADCggJCAAAAA==.',
Cl='Claes:BAAALgAECgEJBQABLgAECggJHQAcAP0SAA==.Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgAECgMJBAAAAA==.Clonetrooper:BAAALgAFFAIJAwAAAA==.Clorox:BAAALgADCgEJAQAAAA==.',
Co='Coocoohead:BAAALgAECgMJBQAAAA==.Coofus:BAAALgAFFAIJBAAAAA==.Coralorchid:BAABLgAECn8yAAMQAAgJvxPVFgBoAQAQAAcJJRXVFgBoAQARAAcJyA8MmwA9AQAAAA==.Corrupt:BAAALgAECgEJAQABLgAECgMJCAAPAAAAAA==.',
Cp='Cptdarkk:BAABLgAECn8ZAAIRAAcJUwuftAAWAQARAAcJUwuftAAWAQAAAA==.',
Cr='Crytal:BAAALgAECgMJBAAAAA==.',
Cu='Cuddlebucket:BAAALgADCgQJBQAAAA==.Curissan:BAABLgAECn8jAAIOAAkJrxmOEwBNAgAOAAkJrxmOEwBNAgAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAABLgAECn8UAAIFAAgJAiHeFACgAgAFAAgJAiHeFACgAgAAAA==.',
['Cø']='Cøndemn:BAAALgAECgYJCAAAAA==.',
Da='Daemyn:BAAALgADCgcJBwAAAA==.Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAABLgAECn8bAAIEAAgJvhqnMwAuAgAEAAgJvhqnMwAuAgAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAgJIAAhAB0RAA==.Dalspin:BAACLgAFFH8gAAIhAAgJHRFxDgAXAgAhAAgJHRFxDgAXAgAuAAQKfycABCEACQkpG9wHANkCACEACQkpG9wHANkCACAABwm8ElYqAIoBABwABgnGBMpWAKoAAAAA.Dalthepal:BAABLgAECn8UAAISAAcJXx+pHgAiAgASAAcJXx+pHgAiAgABLgAFFAgJIAAhAB0RAA==.Darassa:BAAALgAECgEJAQAAAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAACLgAFFH8eAAIRAAUJiCGHHQCKAQARAAUJiCGHHQCKAQAuAAQKf0wAAhEACQmMJlkBAIMDABEACQmMJlkBAIMDAAAA.Davidshaman:BAAALgAECgcJBwAAAA==.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deadish:BAAALgAECgYJCwAAAA==.Deathsaberss:BAABLgAECn8qAAIVAAkJABi7DgD+AQAVAAkJABi7DgD+AQAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgcJEQAAAA==.Debauch:BAABLgAECn8cAAICAAkJPw+bTAC0AQACAAkJPw+bTAC0AQAAAA==.Deight:BAAALgAECgEJAQAAAA==.Dejamoo:BAAALgADCgcJBgAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Denniah:BAAALgAECgQJBAAAAA==.Derke:BAAALgAECgQJBwAAAA==.Destinee:BAAALgAECgEJAQAAAA==.',
Di='Didudietho:BAAALgADCggJCAABLgAECgkJQwARADobAA==.Diladrin:BAACLgAFFH8eAAIiAAUJ8w9UFQDSAAAiAAUJ8w9UFQDSAAAuAAQKf0sAAiIACQnDHH8GAJECACIACQnDHH8GAJECAAAA.Diode:BAACLgAFFH8fAAQEAAYJ7xS9SABcAQAEAAUJfBG9SABcAQATAAQJBBPHDwASAQAaAAEJAADPVAAAAAAuAAQKfzEAAwQACQlyIDUYAOoCAAQACAn8IDUYAOoCABMACQnmG84GADECAAAA.Diyla:BAAALgAECgEJAQAAAA==.',
Do='Doileag:BAABLgAECn8nAAIRAAcJ6Aj7uAAPAQARAAcJ6Aj7uAAPAQAAAA==.Domer:BAAALgAECgYJCAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dora:BAAALgAECgMJAwAAAA==.Dottmatrix:BAABLgAECn8dAAIDAAcJhQ06FAAIAQADAAcJhQ06FAAIAQAAAA==.',
Dr='Drachnia:BAAALgAECgQJBAAAAA==.Dragønbreath:BAACLgAFFH8MAAMUAAUJHAmDbQAOAQAUAAUJHAmDbQAOAQAbAAEJaAPDBwAzAAAuAAQKfx0AAxsACQlxGhcCAEoCABsACAnMFxcCAEoCABQACAk3FUSzABkBAAAA.Dreadwing:BAABLgAECn8fAAIEAAYJGwkgzQDpAAAEAAYJGwkgzQDpAAAAAA==.',
Du='Duf:BAACLgAFFH8iAAIcAAYJHx3QDwCfAQAcAAYJHx3QDwCfAQAuAAQKfy8AAhwACQmEH+UOAEkCABwACQmEH+UOAEkCAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn9GAAIKAAkJPSBqBgAKAwAKAAkJPSBqBgAKAwAAAA==.',
Dw='Dwagon:BAAALgAFFAEJAQAAAA==.',
['Dæ']='Dæmôn:BAAALgAECgYJCQAAAA==.',
['Dì']='Dìzzy:BAAALgAECgIJAgAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAACLgAFFH8LAAIgAAMJARuLGgDwAAAgAAMJARuLGgDwAAAuAAQKfzEAAxwACQkpG/QOAEgCABwACQkpG/QOAEgCACAAAgmkGCFgAI8AAAAA.Dûna:BAACLgAFFH8HAAIYAAIJVR2xKwCWAAAYAAIJVR2xKwCWAAAuAAQKfyUAAhgACAkBIZoNAHoCABgACAkBIZoNAHoCAAEuAAUUAwkLACAAARsA.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn9HAAIRAAkJQSQfBwA0AwARAAkJQSQfBwA0AwAAAA==.Elduar:BAAALgADCgEJAQAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAABLgAECn8gAAIOAAgJYxJsMAB6AQAOAAgJYxJsMAB6AQAAAA==.Elketha:BAAALgAECgUJBQABLgAFFAUJHgAZAMkcAA==.Ellaring:BAAALgAECgYJCAABLgAECgcJDwAPAAAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrric:BAABLgAECn8VAAIEAAgJQQxXhgBUAQAEAAgJQQxXhgBUAQAAAA==.Elryck:BAAALgADCgEJAQAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAABLgAECn8zAAMGAAgJ3h83EADLAgAGAAgJ3h83EADLAgAOAAgJJROCMQB0AQAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Erouvi:BAAALgAECgEJAQABLgAECgkJQQAKAFYeAA==.Eroviaa:BAAALgAECgYJBwABLgAECgkJQQAKAFYeAA==.Erovvia:BAAALgAECgUJBgABLgAECgkJQQAKAFYeAA==.',
Es='Essaelsia:BAAALgAECgcJBwAAAA==.',
Et='Etali:BAAALgAECgMJBAABLgAFFAEJAQAPAAAAAA==.',
Ez='Ezothen:BAABLgAECn8oAAMjAAgJNg2INQBYAQAjAAgJNg2INQBYAQAkAAQJawRpLwCdAAAAAA==.',
Fa='Faedoria:BAABLgAECn8iAAIRAAgJVwRI2QDkAAARAAgJVwRI2QDkAAAAAA==.Faeryln:BAABLgAECn8nAAIKAAkJ+wvVKwBnAQAKAAkJ+wvVKwBnAQAAAA==.Faerynn:BAAALgADCgkJCQABLgAECgkJLgAFAPEdAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falenrush:BAAALgADCgEJAQAAAA==.Falkorr:BAAALgAECgQJBQABLgAECgkJOQAlANQeAA==.Falorie:BAAALgADCgYJEQAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAABLgAECn8zAAMXAAkJTSEVBADzAgAXAAgJhCEVBADzAgAjAAEJByEJfQBgAAAAAA==.Faustus:BAAALgADCgQJCgABLgAECgkJMwAXAE0hAA==.',
Fe='Feature:BAAALgAECgkJBwAAAA==.Felstormer:BAAALgADCggJEAABLgAECgQJCQAPAAAAAA==.Felyna:BAAALgAECgMJAwAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgYJCQAAAA==.Firefoxx:BAAALgAECgEJAQABLgAECgkJLgAFAPEdAA==.Fireføx:BAAALgADCgEJAQAAAA==.Fisticuffs:BAAALgAECgUJDQAAAA==.Fizzllebang:BAABLgAECn8oAAIDAAkJxxXACAC6AQADAAkJxxXACAC6AQAAAA==.',
Fl='Flamewhisker:BAAALgAECgYJCQAAAQ==.Flogginrenee:BAAALgAECgYJEwAAAA==.Floggsdaddy:BAAALgAECgYJEwAAAA==.Floke:BAAALgAECgMJBAAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fr='Fraublucher:BAABLgAECn87AAIKAAkJnRV/EwA6AgAKAAkJnRV/EwA6AgAAAA==.Fredrik:BAABLgAFFH8RAAMcAAUJsRGCJgALAQAcAAUJsRGCJgALAQAhAAIJywFIawAjAAAAAA==.Frewyn:BAAALgAECgQJCQAAAA==.Frikk:BAAALgAECgQJBAAAAA==.Frostimoth:BAABLgAECn8tAAIUAAkJzRY1OgAtAgAUAAkJzRY1OgAtAgAAAA==.Frozty:BAABLgAECn8dAAIXAAkJuxNpCwAgAgAXAAkJuxNpCwAgAgAAAA==.',
Fu='Fujïn:BAAALgADCgEJAQAAAA==.',
Ga='Galandel:BAAALgAECgUJDQAAAA==.Galial:BAACLgAFFH8WAAIHAAYJkh+VAQC0AQAHAAYJkh+VAQC0AQAuAAQKfyIAAgcACQlaHzsBACIDAAcACQlaHzsBACIDAAAA.Gantar:BAABLgAECn8YAAIiAAgJeSOuAgD6AgAiAAgJeSOuAgD6AgABLgAFFAQJBAAPAAAAAA==.Garlicbread:BAAALgADCgYJBgABLgAFFAYJFgAHAJIfAA==.Garralock:BAAALgAECgcJAQAAAA==.Garrunter:BAAALgAECgkJBAAAAA==.Gaznol:BAABLgAECn8hAAIMAAgJtiEIHQBzAgAMAAgJtiEIHQBzAgAAAA==.',
Ge='Gelasera:BAAALgAECgYJCQAAAA==.Gerbert:BAAALgAECgUJCQAAAA==.',
Gh='Ghibli:BAABLgAECn8XAAMVAAkJuA8VGwB+AQAVAAkJuA8VGwB+AQAWAAIJ7AWjmgBWAAAAAA==.',
Gi='Gisa:BAAALgAECgEJAQABLgAFFAEJAQAPAAAAAA==.',
Gl='Glaivethras:BAABLgAECn8nAAIHAAkJNiPHAgDEAgAHAAkJNiPHAgDEAgAAAA==.Glyph:BAAALgAECgEJAQAAAA==.Glyphix:BAABLgAECn8nAAIWAAkJPwsYMACMAQAWAAkJPwsYMACMAQAAAA==.Glyphx:BAAALgAECgEJAgAAAA==.',
Gn='Gnarly:BAAALgAECgMJCAAAAA==.',
Go='Goochtrap:BAAALgAECgQJBAAAAA==.Gorgon:BAAALgAECgMJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAABLgAECn8hAAQdAAgJxgy1IwCAAQAdAAgJuAu1IwCAAQAMAAQJeQ4vgQDkAAAeAAQJXwUlaACeAAAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.Grimclaw:BAAALgAECgIJAgABLgAFFAkJFwAEAEgXAA==.Groot:BAABLgAECn8hAAMFAAcJchV5PACfAQAFAAYJ3xZ5PACfAQAlAAcJKQ1oPAAbAQABLgAFFAIJBgARAOMLAA==.Groovinchef:BAAALgAECgEJAQAAAA==.Grump:BAAALgAECgEJAQABLgAECggJJgALALwfAA==.',
Gu='Gundunn:BAAALgADCgEJAQAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECgYJGgAGAKYHAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAEBLgAECn8dAAIYAAgJsRDULQBqAQAYAAgJsRDULQBqAQABLgAECgYJBwAPAAAAAA==.Hannebal:BAABLgAECn8aAAISAAkJEhGiJgDSAQASAAkJEhGiJgDSAQAAAA==.Havenfire:BAAALgADCgUJBQABLgAECgEJAQAPAAAAAA==.',
He='Healsonyou:BAAALgAECgUJBQABLgAECggJFwAEAFsUAA==.Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCggJEgAAAA==.Heydaw:BAAALgAECggJDgABLgAECgkJIAAEAHIgAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgAECgEJAQAAAA==.Holybeatdown:BAAALgAECgMJBAAAAA==.Holyrage:BAAALgADCgYJBgAAAA==.Holyßloodelf:BAAALgAECggJCwABLgAECggJFwAEAFsUAA==.Honeysbadger:BAAALgAECgMJAwAAAA==.Hoosier:BAAALgAECgQJBQAAAA==.Hornet:BAABLgAECn8VAAMZAAgJZBCMYgBfAQAZAAgJ7w+MYgBfAQAIAAQJFwz3SADPAAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.Hotsauce:BAAALgAECgYJCAABLgAFFAcJGgAUAOIaAA==.',
Hu='Huasca:BAAALgAECgMJBQAAAA==.Humungous:BAAALgAECgcJDQAAAA==.Hunnybunz:BAAALgAECgYJDAAAAA==.',
['Hà']='Hàney:BAEALgAECgYJBwAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJEgAAAA==.',
['Hé']='Hélio:BAAALgAECgUJCAAAAA==.',
Ia='Ia:BAABLgAFFH8LAAITAAQJKAziDwARAQATAAQJKAziDwARAQAAAA==.',
Ic='Icastfirebal:BAAALgAECgEJAQAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECggJDAAAAA==.',
Ig='Igotahitin:BAAALgADCgMJCAAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAABLgAECn8dAAIcAAgJ/RKkIgCRAQAcAAgJ/RKkIgCRAQAAAA==.',
Il='Illida:BAAALgAECgUJCAAAAA==.',
Im='Imamalelol:BAABLgAECn8iAAQWAAcJsQ0ZSAAkAQAWAAcJygsZSAAkAQAVAAUJrQotRgCsAAANAAEJqgDtYAATAAAAAA==.',
In='Indira:BAAALgADCgcJDQAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAUJCQABLgAFFAUJDAAXAMMNAQ==.Inumimi:BAABLgAECn8fAAImAAkJzAXPIwDkAAAmAAkJzAXPIwDkAAAAAA==.Invincidemon:BAAALgAECgQJBAAAAA==.',
Ir='Irkenfox:BAECLgAFFH8dAAINAAYJgyHZCACcAQANAAYJgyHZCACcAQAuAAQKfyUAAg0ACAmhI54DABsDAA0ACAmhI54DABsDAAAA.',
Is='Isogni:BAAALgAECgQJBAABLgAECgcJIAAJAG4eAA==.',
It='Ithran:BAABLgAECn8pAAIUAAkJKQzEbwCXAQAUAAkJKQzEbwCXAQAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8wAAIbAAkJ5x1tAQCXAgAbAAkJ5x1tAQCXAgAAAA==.',
Iz='Izanamí:BAAALgADCgMJAwAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.Jama:BAAALgAECgUJBwAAAA==.James:BAACLgAFFH8bAAIUAAQJTBxcQgBpAQAUAAQJTBxcQgBpAQAuAAQKf0gAAhQACQmgIa8OAAMDABQACQmgIa8OAAMDAAEuAAUUBQkRABwAsREA.Janderick:BAABLgAECn8iAAIWAAkJyiDhCwCpAgAWAAkJyiDhCwCpAgAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jeannedarc:BAAALgAECgQJBAAAAA==.Jellacee:BAABLgAECn8aAAMIAAUJeRE3SACQAAAIAAUJeRE3SACQAAAZAAIJHgP8DgE2AAAAAA==.Jesterjoe:BAAALgAECgQJDAAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8fAAIDAAYJhCKDAgDAAQADAAYJhCKDAgDAAQAuAAQKfy8AAgMACQmfIfQAAC8DAAMACQmfIfQAAC8DAAAA.Jimi:BAAALgADCgUJBQAAAA==.Jimreaper:BAAALgAECgkJCQAAAA==.Jinkx:BAAALgAECgEJAQABLgAECgkJOQAlANQeAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJBAABLgAFFAQJBAAPAAAAAA==.',
Jo='Joejitsu:BAAALgAECgMJAwAAAA==.Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAABLgAECn8lAAQDAAkJkx78CQCiAQADAAYJAx78CQCiAQACAAQJFx27dABPAQABAAEJXCB1KgBKAAAAAA==.Joltraxi:BAAALgAECgMJBQAAAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJEwABLgAFFAQJBAAPAAAAAA==.Joshy:BAAALgAFFAQJBAAAAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Js='Jstnbieber:BAAALgAECgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCgAAAA==.Juicethevoid:BAABLgAECn8pAAIZAAkJnwd2bwBAAQAZAAkJnwd2bwBAAQAAAA==.Juniornite:BAABLgAECn82AAIUAAkJmCCiFgDPAgAUAAkJmCCiFgDPAgAAAA==.Justicus:BAAALgAECgYJEQABLgAECgkJJwAMALUbAA==.Justthetouch:BAAALgAECggJCQAAAA==.',
Jy='Jygglypuff:BAAALgAECgcJCAAAAA==.',
['Jü']='Jüst:BAAALgAECgMJAwAAAA==.',
Ka='Kadaan:BAAALgAECgcJCAAAAA==.Kaeldrin:BAAALgADCgkJFAAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAABLgAECn82AAQIAAkJCBo6EAAgAgAIAAgJFRo6EAAgAgAHAAcJVhVHDgBpAQAZAAgJsA7KZABaAQABLgAFFAEJAQAPAAAAAA==.Kahgar:BAAALgAECgQJBAABLgAECgkJNwASABsWAA==.Kaiser:BAAALgAECgQJCQAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgUJDwAAAA==.Kalzod:BAACLgAFFH8VAAMCAAQJoRveRAA6AQACAAQJoRveRAA6AQABAAEJWRZeHQBSAAAuAAQKfz4AAwIACQlLJnQCAGoDAAIACQlLJnQCAGoDAAEAAQkAAB0kAGEAAAAA.Kariana:BAAALgAECgYJDgAAAA==.Kataki:BAAALgAFFAEJAQAAAA==.Katett:BAAALgAECgcJDgAAAA==.Katia:BAAALgADCgUJBQAAAA==.Kativeria:BAAALgAECgYJCQAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDwABLgAECgYJDgAPAAAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgYJEgAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Keidric:BAAALgAECgIJAgAAAA==.Kerfufle:BAAALgAECgUJBQAAAA==.Keyn:BAAALgAECgIJAQAAAA==.Keynstolor:BAABLgAECn8hAAIMAAgJRBotRgDKAQAMAAgJRBotRgDKAQAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.Khálifá:BAAALgAECgUJBgAAAA==.',
Ki='Kicker:BAABLgAECn8UAAIWAAYJcgYaZgDCAAAWAAYJcgYaZgDCAAAAAA==.Killmora:BAAALgAECgUJDQAAAA==.Kippars:BAABLgAECn8hAAMiAAgJvRXSHABhAQAiAAcJxxXSHABhAQAmAAEJfRX6SgA+AAAAAA==.Kiritsugo:BAAALgAECgQJBAAAAA==.Kissame:BAAALgAECgYJCAAAAA==.',
Kn='Knaifu:BAAALgADCgkJDQAAAA==.',
Ko='Kodazoff:BAABLgAECn85AAQjAAkJixL9HQDmAQAjAAkJUhL9HQDmAQAkAAgJsQ1SCgB4AQAXAAIJIAd/OwAyAAAAAA==.Korevash:BAABLgAECn8nAAMLAAgJ+xvfCgAFAgALAAgJ+xvfCgAFAgAGAAIJ4wmZuQBVAAABLgAFFAUJGgAJAAIUAA==.Korupta:BAABLgAECn8uAAMZAAgJHBC9YABkAQAZAAgJHBC9YABkAQAIAAUJ3A36PQAFAQABLgAECgkJJAACADgSAA==.Korzilius:BAAALgAECggJEAAAAA==.',
Kr='Krissylu:BAABLgAECn8gAAIBAAcJFQ1JEgA/AQABAAcJFQ1JEgA/AQAAAA==.Krockett:BAAALgAECgQJBAAAAA==.Krothix:BAABLgAECn9FAAIOAAkJrA3/MQByAQAOAAkJrA3/MQByAQAAAA==.Kruvix:BAAALgAECgYJCgAAAA==.Krygask:BAAALgAECgQJBAAAAA==.Kryjag:BAAALgAECgQJCgAAAA==.Krynir:BAAALgADCgkJDgAAAA==.Kryshym:BAAALgAECggJDQAAAA==.Krythrall:BAAALgAECgMJAwABLgAECggJDQAPAAAAAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAAALgAECgYJDwAAAA==.',
La='Ladara:BAABLgAECn8tAAIBAAkJ8BAkCADLAQABAAkJ8BAkCADLAQAAAA==.Laima:BAAALgADCgcJEwAAAA==.Lalthras:BAAALgAECgcJBwAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAgAAAA==.Lavitz:BAAALgAECgMJBgAAAA==.',
Le='Leheo:BAAALgAECgQJDAAAAA==.Lehua:BAAALgAECgQJBAAAAA==.Leilanii:BAAALgAECgQJCQAAAA==.Lemook:BAAALgAECgcJEAAAAA==.Leonìdas:BAAALgAECgQJBgAAAA==.',
Lh='Lhei:BAAALgAECgYJEgAAAA==.',
Li='Lightstormer:BAAALgAECgQJCQAAAA==.Lilamae:BAAALgAECggJDgAAAA==.Lilarielle:BAABLgAECn9CAAImAAgJfQo9IAAAAQAmAAgJfQo9IAAAAQAAAA==.Lildash:BAAALgADCgIJAgABLgAECgkJJgAQAEobAA==.Lilface:BAAALgAECgYJCgAAAA==.Liliela:BAAALgAECgQJBAABLgAECgkJJgAQAEobAA==.Lilsham:BAAALgAECgQJBAABLgAECgkJJgAQAEobAA==.Lilyannah:BAAALgAECgkJAQAAAA==.Linadra:BAAALgAECgcJBwAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgIJAgAPAAAAAA==.Liopain:BAAALgAECgIJAgAAAA==.Liø:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.',
Lo='Lokir:BAAALgAECgMJBgAAAA==.Losoli:BAAALgAECggJCAABLgAECgkJTQAgAOkbAA==.Lotheovian:BAEALgAECgIJAgABLgAECgkJLgAEAJsaAA==.Lowchin:BAABLgAECn8VAAIFAAcJOwrKZgD9AAAFAAcJOwrKZgD9AAAAAA==.',
Lu='Lumia:BAABLgAECn8dAAMYAAkJix4wEwBcAgAYAAcJlB8wEwBcAgAKAAYJFBjVSgANAQAAAA==.Lutherion:BAABLgAECn8WAAQNAAgJqB9GCAB0AgANAAgJqB9GCAB0AgAVAAEJCQdCSAAlAAAWAAEJUAJNtwASAAAAAA==.',
Lv='Lvispriestly:BAAALgADCgQJBAABLgAECgkJIgAlAEsDAA==.',
Ly='Lycemmas:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìllìth:BAAALgADCgYJBgAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgAECgEJAQAAAA==.Mackshiesty:BAABLgAECn8mAAIZAAcJsB7nKwAVAgAZAAcJsB7nKwAVAgAAAA==.Macoun:BAABLgAECn81AAMMAAkJrSRZBABJAwAMAAkJrSRZBABJAwAeAAYJEhv0QABVAQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn9BAAIUAAkJLiaSBABgAwAUAAkJLiaSBABgAwAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAABLgAECn8dAAIYAAgJzAo1NQBAAQAYAAgJzAo1NQBAAQAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBgAPAAAAAA==.Martei:BAACLgAFFH8bAAImAAUJXhoSBgBIAQAmAAUJXhoSBgBIAQAuAAQKfy8AAiYACQm/IkICAC8DACYACQm/IkICAC8DAAAA.Maruki:BAAALgADCgEJAQAAAA==.Maríneth:BAABLgAECn8aAAIFAAYJyQzFZgD9AAAFAAYJyQzFZgD9AAAAAA==.Mathías:BAABLgAECn8nAAIMAAkJgBn5KQAyAgAMAAkJgBn5KQAyAgAAAA==.Mavze:BAAALgADCgIJAgAAAA==.',
Me='Meadowfrey:BAAALgAECgEJAQAAAA==.Mentuko:BAAALgAECgQJBgAAAA==.Meowbae:BAABLgAECn8zAAMmAAkJ8BeqCAA7AgAmAAkJ8BeqCAA7AgAlAAEJNAGEpgAVAAAAAA==.Merce:BAAALgAECgcJDgABLgAECgkJJgAQAEobAA==.Mercesdes:BAAALgAECgUJBwAAAA==.Mercina:BAAALgAECgEJBAAAAA==.Mercuros:BAABLgAECn8UAAMKAAkJawM9PQD5AAAKAAkJawM9PQD5AAAYAAIJrgPZewBBAAAAAA==.Merknlock:BAAALgAECgEJAQAAAA==.',
Mi='Micãh:BAAALgAECgIJAgAAAA==.Midnyte:BAABLgAECn9NAAMgAAkJ6Rt/DAB5AgAgAAkJ6Rt/DAB5AgAhAAkJLBXFGwA0AgAAAA==.Milkyweí:BAAALgAECgMJAwAAAA==.Mindgames:BAAALgAECgEJAQAAAA==.Mini:BAAALgADCgUJBQABLgAECggJKwAUAOweAA==.Minizee:BAAALgAECgYJCAAAAA==.Mirabella:BAAALgAECgQJBgABLgAFFAQJDAAhAIkYAA==.Mirokushan:BAABLgAECn8UAAMhAAQJKxE0agDPAAAhAAQJKxE0agDPAAAcAAQJwQMQZwB4AAABLgAECgUJEAAPAAAAAA==.Mistfit:BAAALgAECgQJAwAAAA==.Misticlady:BAAALgADCgEJAQAAAA==.Mistingmoo:BAAALgAECgkJDQAAAA==.Mistrariel:BAABLgAECn8oAAIHAAkJuh5MAwCqAgAHAAkJuh5MAwCqAgABLgAFFAEJAgAPAAAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Moostafa:BAAALgAECgQJBAAAAA==.Moradin:BAAALgADCgIJAgAAAA==.Mordemour:BAABLgAECn8WAAIBAAYJPhS0EgA6AQABAAYJPhS0EgA6AQAAAA==.Morlune:BAAALgAECgEJAQAAAA==.',
Mu='Mungo:BAABLgAECn8qAAIUAAgJTBhxUADnAQAUAAgJTBhxUADnAQAAAA==.Musketoon:BAAALgAECgYJBgAAAA==.',
My='My:BAAALgAECgkJDgAAAA==.Mynkie:BAACLgAFFH8YAAIhAAUJGRWkIgBKAQAhAAUJGRWkIgBKAQAuAAQKfzYAAiEACQlfIkcEAGwDACEACQlfIkcEAGwDAAAA.Myrell:BAAALgAECgkJBgAAAA==.Mythreashis:BAAALgADCgMJAwAAAA==.',
['Mä']='Mägi:BAAALgAECgEJAQAAAA==.',
['Må']='Mååt:BAAALgADCgIJAgAAAA==.',
['Mæ']='Mæstra:BAAALgADCgQJBAAAAA==.',
['Më']='Mëlony:BAAALgADCgIJAgAAAA==.',
Na='Nachtmar:BAABLgAECn8ZAAIiAAYJohVKIwAwAQAiAAYJohVKIwAwAQAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8gAAIZAAYJKxSCLgBjAQAZAAYJKxSCLgBjAQAuAAQKfyoAAhkACAlDHDkyAPoBABkACAlDHDkyAPoBAAAA.Nalik:BAAALgAECgYJBwAAAA==.Nanou:BAAALgADCgUJBwAAAA==.Nardiaun:BAAALgADCgkJEgAAAA==.',
Ne='Necia:BAAALgADCgMJAwABLgAECgkJJwAKAPsLAA==.Neltu:BAAALgAECgQJBQAAAA==.Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nikkitta:BAAALgADCgMJAwAAAA==.Nimravidae:BAABLgAECn89AAMSAAgJ5Rd3HwAFAgASAAgJ5Rd3HwAFAgARAAcJoBP9fwBsAQAAAA==.Ninelives:BAABLgAECn8iAAIlAAkJSwO5TADUAAAlAAkJSwO5TADUAAAAAA==.Nitecrawler:BAABLgAECn8jAAMUAAkJnw/4XADEAQAUAAkJnw/4XADEAQAnAAEJhQM5GgAZAAAAAA==.Nitelyt:BAAALgAECgEJAQABLgAECgkJNgAUAJggAA==.Niteryu:BAABLgAECn8YAAIkAAkJsRHZBgDYAQAkAAkJsRHZBgDYAQABLgAECgkJNgAUAJggAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAABLgAECn8nAAIjAAgJCQycOgA+AQAjAAgJCQycOgA+AQAAAA==.Noxium:BAAALgAECgYJDQAAAA==.Noxolon:BAABLgAECn9CAAIWAAkJlB0lCgDAAgAWAAkJlB0lCgDAAgAAAA==.',
Nr='Nreaf:BAABLgAECn84AAMRAAkJfBy9JACUAgARAAkJKRy9JACUAgAQAAYJPxwNEwCVAQAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgQJCAAAAA==.Nydhogg:BAAALgAECgEJAQABLgAFFAEJAgAPAAAAAA==.Nysca:BAAALgADCgcJBwAAAA==.',
Ob='Obijuan:BAAALgAECgMJAwAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAAALgAECgYJEgAAAA==.',
Ol='Olarrick:BAABLgAFFH8HAAIaAAMJ/wTNLgCEAAAaAAMJ/wTNLgCEAAABLgAFFAUJEQAcALERAA==.',
Or='Ornstein:BAABLgAECn8nAAMQAAYJkSKXDQDoAQAQAAYJkSKXDQDoAQARAAYJGBCrvAAKAQAAAA==.',
Ot='Ottuk:BAACLgAFFH8WAAMEAAYJ9RNnOwB8AQAEAAUJ9RNnOwB8AQAaAAEJAADGYAAAAAAuAAQKfyIAAwQACQnVIa8IAFgDAAQACQnVIa8IAFgDABoAAwlnHX0nAAMBAAAA.',
Pa='Padinbar:BAAALgAECgQJBAABLgAECgcJFQAUAAkSAA==.Pakraxes:BAAALgAECgUJBQAAAA==.Paksenarrion:BAABLgAECn8+AAIQAAgJrhJfFQB6AQAQAAgJrhJfFQB6AQAAAA==.Pancham:BAAALgADCgUJBQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECgkJEQAAAA==.Pandemônium:BAAALgAECggJEAAAAA==.Pandemönium:BAAALgAECgIJAQAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Pandèmonium:BAAALgAECgYJBgAAAA==.Parts:BAAALgAECgEJAQAAAA==.Patchington:BAABLgAECn8aAAIQAAYJKBUSHAAyAQAQAAYJKBUSHAAyAQAAAA==.Pañdemönium:BAAALgAECgUJBQAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Perck:BAAALgAECgQJBAAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAFFAIJBgAjAIgTAA==.Pezvoker:BAACLgAFFH8GAAIjAAIJiBMNUQB/AAAjAAIJiBMNUQB/AAAuAAQKfxUAAiMABgkgIIsiAMQBACMABgkgIIsiAMQBAAAA.',
Ph='Phaedrä:BAAALgAECgEJAQAAAA==.',
Pi='Pienarri:BAAALgAECgEJAgAAAA==.Pixelme:BAAALgAECgMJBQAAAA==.',
Pl='Pleggster:BAABLgAECn8ZAAMGAAgJJA56TQB3AQAGAAgJJA56TQB3AQAOAAEJiAGBvgAbAAAAAA==.',
Po='Pochula:BAABLgAECn8kAAIFAAgJaxXbKgD+AQAFAAgJaxXbKgD+AQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAABLgAECn83AAMSAAkJGxYyFgBYAgASAAkJGxYyFgBYAgARAAIJSgS+bgFEAAAAAA==.Protricity:BAABLgAECn88AAMYAAkJdCCJCQC1AgAYAAkJdCCJCQC1AgAKAAEJ2AJchAAtAAAAAA==.',
Pu='Pumpernickel:BAAALgADCgUJBQABLgAFFAYJFgAHAJIfAA==.Puppytoes:BAAALgAECgYJDwAAAA==.',
Py='Pyrellyn:BAAALgADCggJCgAAAA==.',
['Pä']='Pändamönium:BAAALgAECgkJEQAAAA==.Pändemönium:BAAALgAFFAEJAQAAAA==.',
['Pæ']='Pæn:BAACLgAFFH8RAAIEAAUJOyYdKQC5AQAEAAUJOyYdKQC5AQAuAAQKfy0AAwQABwnHJYghAH8CAAQABwnHJYghAH8CABoABwmPHygUAM8BAAEuAAUUBQkbABIAEyAA.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgYJCQABLgAECgYJCwAPAAAAAA==.Quantar:BAAALgAECgYJCwAAAA==.Quickstab:BAAALgAECgcJBwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rakta:BAAALgAECgcJEAAAAA==.Rancooll:BAAALgAECgUJDQAAAA==.Rasniir:BAACLgAFFH8FAAIFAAIJRAaEXQBcAAAFAAIJRAaEXQBcAAAuAAQKf0sAAgUACQlZIWoFAF8DAAUACQlZIWoFAF8DAAAA.Ravenlash:BAAALgAECgEJBAAAAA==.',
Re='Regna:BAACLgAFFH8eAAIWAAYJ0Sa1BAAcAgAWAAYJ0Sa1BAAcAgAuAAQKfzAAAhYACQmaJhgDAH8DABYACQmaJhgDAH8DAAAA.Regner:BAAALgAECgEJAQAAAA==.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAABLgAECn8VAAIaAAcJlQzMLADyAAAaAAcJlQzMLADyAAAAAA==.Remaked:BAACLgAFFH8sAAIcAAcJgR18AwCpAQAcAAcJgR18AwCpAQAuAAQKf0AAAhwACQmsI/IDAAkDABwACQmsI/IDAAkDAAAA.Remilia:BAABLgAECn85AAIYAAkJriIVCQC8AgAYAAkJriIVCQC8AgAAAA==.Requinix:BAABLgAECn9WAAIMAAkJpRkAHwBpAgAMAAkJpRkAHwBpAgAAAA==.Retro:BAAALgAECgEJAQAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAFFAEJAQAAAA==.Revwrinkle:BAAALgAECgIJAwAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgUJEAAAAA==.Ricochet:BAABLgAECn8hAAIdAAkJ0RAdFgDyAQAdAAkJ0RAdFgDyAQAAAA==.Riptidez:BAAALgADCgcJBgAAAA==.Ririko:BAABLgAECn85AAMKAAgJVxFbJACdAQAKAAgJVxFbJACdAQAYAAEJ9QJkmAAZAAAAAA==.Ritzo:BAABLgAECn8qAAIWAAgJoRXmKAC1AQAWAAgJoRXmKAC1AQAAAA==.Rizzla:BAAALgAECgIJAgABLgAECgkJOQAlANQeAA==.',
Ro='Rockllobster:BAAALgAECgcJDwAAAA==.Rocksanne:BAAALgADCgcJEAAAAA==.Roguebâit:BAABLgAECn9YAAQBAAkJqCDnAQDFAgABAAkJ1R/nAQDFAgACAAcJjBT2VwCUAQADAAMJJw3SRACiAAAAAA==.Ronarvinge:BAABLgAECn8VAAIUAAcJCRILgAB0AQAUAAcJCRILgAB0AQAAAA==.Ronen:BAAALgAECgQJBAAAAA==.',
Ru='Rubywolf:BAAALgAECgYJDgABLgAFFAQJCAAlALsIAA==.Rukkis:BAABLgAECn8pAAMfAAkJ7xofCgB/AgAfAAkJ7xofCgB/AgAoAAEJjQkKJQAuAAAAAA==.Rukâ:BAAALgAECgQJBAAAAA==.Rumi:BAACLgAFFH8bAAIHAAUJZx2YAwBNAQAHAAUJZx2YAwBNAQAuAAQKf0sAAwcACQnrJAoBADYDAAcACQnrJAoBADYDAAgAAQlvEb9rADIAAAAA.',
Ry='Ryeekan:BAABLgAECn8vAAIMAAkJjxSYNAAGAgAMAAkJjxSYNAAGAgAAAA==.',
['Ró']='Róronoà:BAAALgAECgYJCgAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAACLgAFFH8GAAIRAAIJ4wtojwCMAAARAAIJ4wtojwCMAAAuAAQKfykAAhEACQlbF/NQANMBABEACQlbF/NQANMBAAAA.Sacia:BAAALgADCgkJCQABLgAECgYJFgABAD4UAA==.Saelena:BAAALgADCgEJAQAAAA==.Sakheddala:BAAALgAECgQJBAAAAA==.Sancha:BAAALgAECgYJBgAAAA==.Sanosagara:BAABLgAECn9BAAIhAAgJSxqaFwBWAgAhAAgJSxqaFwBWAgAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgAECgIJAwAAAA==.Sarithon:BAAALgAECgYJBgAAAA==.Saru:BAAALgADCgkJDQAAAA==.Saruta:BAACLgAFFH8VAAMWAAQJ5BgsGwBAAQAWAAQJ5BgsGwBAAQAVAAEJdQO2RAA3AAAuAAQKfzEAAxYACQnxIPEJAMMCABYACQnxIPEJAMMCABUABQmqDwoWAE4BAAAA.Sath:BAAALgAECgQJBAAAAA==.Sathari:BAABLgAECn8zAAIZAAgJZRjYOwDUAQAZAAgJZRjYOwDUAQAAAA==.Satille:BAAALgADCgUJBQAAAA==.Satsuki:BAABLgAECn8bAAMJAAcJORwTFgAlAgAJAAcJORwTFgAlAgAYAAUJfxVWNABFAQABLgAFFAUJHgAZAMkcAA==.',
Sc='Scarycat:BAAALgADCgYJBgAAAA==.Schaden:BAAALgAECgEJAQABLgAECggJFAAFAAIhAA==.',
Se='Seijo:BAAALgAECgMJAwAAAA==.Sekk:BAABLgAECn9dAAMRAAkJZSDiEADdAgARAAkJZSDiEADdAgAQAAYJvRbpFwBcAQAAAA==.Selexi:BAAALgADCgYJEAAAAA==.Sereya:BAAALgADCgQJBAABLgAECgEJAQAPAAAAAA==.Sesshanmaru:BAAALgAECgUJCAAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAACLgAFFH8FAAIIAAMJgRqrFQDxAAAIAAMJgRqrFQDxAAAuAAQKf2YAAggACQllJQEBAHIDAAgACQllJQEBAHIDAAAA.Shadoshiftt:BAABLgAECn8mAAMlAAkJrQYOPwAOAQAlAAkJrQYOPwAOAQAFAAgJGALwlwCeAAAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgAECgUJDQAAAA==.Shamzee:BAACLgAFFH8YAAMGAAUJ2R7JEwC7AQAGAAUJ2R7JEwC7AQAOAAEJrQL0WwAuAAAuAAQKfygAAwYACAkZHUsdAF4CAAYACAkZHUsdAF4CAA4AAQlWDTunACwAAAAA.Shandalf:BAAALgAECgUJEAAAAA==.Shansebaim:BAAALgAECgYJBgAAAA==.Shintok:BAAALgAECggJDAAAAA==.Shuddarun:BAACLgAFFH8hAAIMAAYJoSCiAwBkAQAMAAYJoSCiAwBkAQAuAAQKfywAAgwACQlPIsUDAFQDAAwACQlPIsUDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgADCgcJDQAPAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simn:BAABLgAECn8fAAIMAAkJCxpJIQBcAgAMAAkJCxpJIQBcAgAAAA==.Sindraesong:BAAALgAECggJEgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgAECgIJBAAAAA==.',
Sk='Skithiryx:BAAALgAECgQJBAABLgAFFAEJAQAPAAAAAA==.Skrai:BAAALgAECgYJCgABLgAECggJIAANANshAA==.',
Sl='Slayvylora:BAACLgAFFH8eAAMRAAYJyBjPDQA8AQARAAUJ+RXPDQA8AQASAAEJ+QI7RQBFAAAuAAQKfzkABBEACQnKIUwWALsCABEACQnKIUwWALsCABIABwnCD5Q7AFcBABAAAgn2Fm03AH4AAAAA.Sleep:BAAALgAECgQJBAABLgAFFAQJCwATACgMAA==.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgAECgIJBQAAAA==.Smarte:BAAALgAECgQJBQABLgAECggJKwAUAOweAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Sneakymoth:BAABLgAECn8VAAIfAAYJXxP/LQAoAQAfAAYJXxP/LQAoAQABLgAECgkJLQAUAM0WAA==.Sniff:BAABLgAECn8rAAIUAAgJ7B4bLgBeAgAUAAgJ7B4bLgBeAgAAAA==.Snookums:BAABLgAECn86AAIZAAgJbBrsMAD/AQAZAAgJbBrsMAD/AQAAAA==.',
So='Soulomon:BAABLgAECn8ZAAICAAkJsRMwgwBUAQACAAkJsRMwgwBUAQAAAA==.Soulsarisen:BAAALgAECgYJDwAAAA==.',
Sp='Spanki:BAAALgADCgkJEAAAAA==.Spellteaser:BAABLgAECn8VAAIUAAYJOhkguQBvAQAUAAYJOhkguQBvAQAAAA==.Spicymaker:BAABLgAECn8mAAIVAAgJ5yAsCQBaAgAVAAgJ5yAsCQBaAgAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJCgAAAA==.Steelheart:BAAALgAECgEJCAAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Stolensøul:BAAALgADCgkJDgAAAA==.Strifewood:BAABLgAECn8cAAIaAAkJWhjgFADFAQAaAAkJWhjgFADFAQAAAA==.Stumper:BAABLgAECn85AAIlAAkJ1B4gCQC/AgAlAAkJ1B4gCQC/AgAAAA==.',
Su='Sugondese:BAAALgAECgQJBgAAAA==.Suluna:BAAALgAECgUJCgABLgAECgkJRgAGAOAcAA==.Summêr:BAABLgAECn8YAAIhAAYJ2wj7aQDPAAAhAAYJ2wj7aQDPAAAAAA==.Suri:BAAALgAECgUJCgABLgAECggJFgANANwWAA==.Sux:BAABLgAECn8ZAAIiAAgJqg5pLAD4AAAiAAgJqg5pLAD4AAAAAA==.',
Sy='Sybrina:BAABLgAECn8cAAIMAAkJLhTBNQACAgAMAAkJLhTBNQACAgAAAA==.Sylvia:BAAALgADCgcJBgABLgAECgEJAQAPAAAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAABLgAECn81AAIMAAYJ4QvLmgAGAQAMAAYJ4QvLmgAGAQAAAA==.Synèsterwolf:BAAALgAECgIJAwABLgAFFAQJCAAlALsIAA==.',
['Sí']='Síf:BAAALgAECgcJDQAAAA==.',
Ta='Tabernacle:BAAALgAECgUJBQAAAA==.Tadeusz:BAABLgAECn8YAAIfAAkJfhczDABfAgAfAAkJfhczDABfAgAAAA==.Tamamò:BAABLgAECn8bAAIhAAcJOxKPKABvAQAhAAcJOxKPKABvAQAAAA==.Tarrok:BAAALgADCgMJBwAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAAALgAECgUJDQAAAA==.Tepache:BAAALgADCgEJAQAAAA==.Tequitos:BAABLgAECn8mAAMSAAkJTBPWGQA0AgASAAkJTBPWGQA0AgARAAYJ7gsi1gDoAAAAAA==.Teranin:BAABLgAECn8UAAIlAAcJPwjTSQDgAAAlAAcJPwjTSQDgAAAAAA==.',
Tf='Tfortyone:BAAALgAECgYJCQAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgIJAwAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAACLgAFFH8TAAIUAAQJxR6qQwBlAQAUAAQJxR6qQwBlAQAuAAQKf0sAAhQACQnNJd0DAGkDABQACQnNJd0DAGkDAAAA.Thunderwalkr:BAAALgAECgEJAQAAAA==.',
Ti='Tiren:BAAALgAECgYJDQAAAA==.',
To='Torag:BAAALgAECgQJBAAAAA==.Torment:BAABLgAECn9eAAIaAAkJ5iCfBADmAgAaAAkJ5iCfBADmAgAAAA==.Tosti:BAAALgAECgkJAQAAAA==.',
Tr='Trepania:BAACLgAFFH8aAAIKAAYJRwu9DgBdAQAKAAYJRwu9DgBdAQAuAAQKfy8AAgoACQngGdEWACUCAAoACQngGdEWACUCAAAA.Tristén:BAABLgAECn8VAAIMAAgJWRWYOwDtAQAMAAgJWRWYOwDtAQAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Trollycarp:BAABLgAECn8gAAMRAAkJQwo5vAALAQARAAkJAgQ5vAALAQAQAAUJdhBGLAC4AAAAAA==.Truvie:BAAALgAECgYJEwAAAA==.',
Tu='Tumbler:BAABLgAECn8XAAMGAAgJix2HGwBsAgAGAAgJix2HGwBsAgAOAAMJCBHNcACTAAAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAABLgAECn86AAMOAAgJCgzTPwAxAQAOAAgJCgzTPwAxAQAGAAYJdAxJdgD1AAAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAABLgAECn8jAAIdAAkJRxHEFQD1AQAdAAkJRxHEFQD1AQAAAA==.',
Ul='Ulnuk:BAACLgAFFH8XAAIGAAQJSh3DIwBVAQAGAAQJSh3DIwBVAQAuAAQKfzwAAgYACQnvIDgIACoDAAYACQnvIDgIACoDAAAA.Ulster:BAAALgAECgIJAgAAAA==.',
Un='Unholyshan:BAAALgADCgEJAQABLgAECgUJEAAPAAAAAA==.Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAAPAAAAAA==.',
Ur='Urwelcome:BAAALgAECgcJBwAAAA==.',
Va='Vadka:BAABLgAECn8XAAISAAgJ9RVaGwAnAgASAAgJ9RVaGwAnAgAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAABLgAECn8aAAMGAAYJpgdMjQC5AAAGAAUJ3ghMjQC5AAAOAAYJyQUfZgCvAAAAAA==.Vairian:BAABLgAECn8ZAAIIAAcJqQ/0KgAiAQAIAAcJqQ/0KgAiAQAAAA==.Valkree:BAAALgAECgYJEgAAAA==.Vallae:BAAALgADCgkJEQABLgAECgkJRgAGAOAcAA==.Valsavis:BAABLgAECn9IAAIHAAkJtxyiBABtAgAHAAkJtxyiBABtAgAAAA==.Valtier:BAABLgAECn8WAAMlAAgJ8BfdIAC9AQAlAAcJNRndIAC9AQAFAAQJyBfNXgAXAQAAAA==.Vampirä:BAABLgAECn8iAAQFAAkJQQU0hQCrAAAFAAgJAgQ0hQCrAAAmAAQJngWSNwB1AAAlAAIJrgPOhAA8AAAAAA==.Varactor:BAAALgAECgMJAwAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAIgAAgJ7iA1CAD3AgAgAAgJ7iA1CAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgYJCQAAAA==.Vernice:BAAALgAECgEJAQABLgAECgYJFgABAD4UAA==.Verulan:BAABLgAECn8gAAQlAAgJtQqiOAAtAQAlAAgJ1AmiOAAtAQAFAAQJjArnkQCNAAAmAAEJKA7MUQAwAAAAAA==.Vexeh:BAAALgAECgUJCQAAAA==.Vexomous:BAAALgAECgUJDwAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vierina:BAAALgAECgEJAQAAAA==.Vikss:BAABLgAECn8zAAMMAAkJ0xKZQwDSAQAMAAkJ0xKZQwDSAQAdAAYJXQQsHQAFAQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgAECgUJCAAAAA==.Vivien:BAAALgADCgYJBgABLgAECgEJAQAPAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAImAAcJ6x9tCABYAgAmAAcJ6x9tCABYAgABLgAECgkJJwAMALUbAA==.',
Vo='Voidmayne:BAABLgAECn8/AAIRAAkJjBF7VADKAQARAAkJjBF7VADKAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgYJEwAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.Voxella:BAAALgAECgQJBAAAAA==.',
Vr='Vrel:BAAALgADCgkJDgAAAA==.',
Vy='Vynnara:BAAALgAECgcJDgABLgAECgcJIAAJAG4eAA==.Vyv:BAABLgAECn8UAAIOAAcJtAVMWQDUAAAOAAcJtAVMWQDUAAAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAIZAAYJEhyzTQC+AQAZAAYJEhyzTQC+AQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Wayadra:BAABLgAECn8XAAQjAAkJkSF7BwDeAgAjAAkJkSF7BwDeAgAkAAcJSQTlJgDrAAAXAAEJlgrESQAvAAAAAA==.',
We='Weiand:BAABLgAECn8vAAMRAAkJUhtGNgAlAgARAAgJpxpGNgAlAgASAAEJOwf0iQAzAAAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAACLgAFFH8LAAQDAAQJNw/LEwCZAAACAAQJTwkQYQAAAQADAAIJGRLLEwCZAAABAAEJHgjhJwBFAAAuAAQKfycABAIACQlDGOs0AAQCAAIACQlDGOs0AAQCAAMAAgnvD39XAGgAAAEAAQkAAA4xADwAAAAA.Wholemilk:BAABLgAECn8qAAIZAAkJXyAuDQDaAgAZAAkJXyAuDQDaAgAAAA==.',
Wi='Wiggz:BAAALgAECgcJCgAAAA==.Wilhellena:BAABLgAECn9BAAIKAAkJEB8sBgAOAwAKAAkJEB8sBgAOAwAAAA==.Wilhellfu:BAAALgAECgMJBwAAAA==.Winariel:BAAALgAFFAEJAgAAAA==.Wisteria:BAAALgAECgEJAQABLgABCgEJAQAPAAAAAA==.',
Wr='Wrecksoul:BAAALgAECgEJAQABLgAECgEJAgAPAAAAAA==.Writhesoul:BAAALgAECgEJAgAAAA==.Wroughtsoul:BAAALgAECgQJAgAAAA==.Wrëckagë:BAAALgAECgcJEwAAAA==.',
Wu='Wumbo:BAAALgAECgYJBwAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAABLgAECn8kAAICAAkJOBIORQDKAQACAAkJOBIORQDKAQAAAA==.Xandir:BAABLgAECn9BAAIQAAkJPhItEgCgAQAQAAkJPhItEgCgAQAAAA==.Xarhunt:BAAALgAECgYJDAAAAA==.Xaric:BAABLgAECn8nAAIFAAkJXhn0JgAVAgAFAAkJXhn0JgAVAgAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xy='Xyal:BAABLgAECn84AAMKAAgJICOgBwDyAgAKAAgJICOgBwDyAgAYAAEJ8wgXjgAqAAAAAA==.Xyp:BAAALgAECgEJAQABLgAECggJIAAlALUKAA==.',
Yg='Ygor:BAAALgAECgUJDwAAAA==.',
Yi='Yiago:BAABLgAECn8aAAIWAAYJQQb1aAC6AAAWAAYJQQb1aAC6AAAAAA==.',
Yo='Yobabydaddy:BAAALgAECgMJAwAAAA==.Youknow:BAAALgAECgUJCAAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.Yungslug:BAAALgAECgcJCQAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zany:BAAALgADCgIJAgAAAA==.Zaranorinn:BAABLgAECn8dAAIRAAkJ0AdjlQBGAQARAAkJ0AdjlQBGAQAAAA==.Zaxhdk:BAEBLgAECn8uAAMEAAkJmxqgJgBmAgAEAAkJmxqgJgBmAgAaAAUJTwZcQwB+AAAAAA==.Zaxhmonk:BAEALgADCgkJCQABLgAECgkJLgAEAJsaAA==.',
Ze='Zedex:BAAALgADCgcJCAABLgADCggJDQAPAAAAAA==.Zedru:BAAALgADCggJDQAAAA==.Zenstormer:BAAALgADCgQJBAABLgAECgQJCQAPAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zephyrion:BAAALgAECgQJCQAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAABLgAECn8VAAIEAAYJfx3KiQBOAQAEAAYJfx3KiQBOAQAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAABLgAECn8hAAIGAAkJ+heEJQApAgAGAAkJ+heEJQApAgAAAA==.Zinrar:BAABLgAECn8qAAIEAAkJ/RnlJwBgAgAEAAkJ/RnlJwBgAgAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8wAAIUAAcJqAhjugAPAQAUAAcJqAhjugAPAQAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAABLgAECn80AAMdAAkJGBa+EQAdAgAdAAkJURW+EQAdAgAMAAEJKRoRFQFBAAAAAA==.',
Zu='Zushi:BAAALgAFFAIJAgAAAA==.',
['Äl']='Älphawolf:BAACLgAFFH8IAAIlAAQJuwhvLADSAAAlAAQJuwhvLADSAAAuAAQKfykABCUACQnNGEgcAOMBACUACQkRFkgcAOMBACIABQn2FGMiADcBAAUAAgl2COC9AEYAAAAA.',
['Ðê']='Ðêmønicßløøð:BAABLgAECn8XAAIEAAgJWxRFWwCyAQAEAAgJWxRFWwCyAQAAAA==.',
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
