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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Unknown-Unknown','Shaman-Elemental','Paladin-Protection','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','Mage-Frost','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Warrior-Protection','DemonHunter-Devourer','DeathKnight-Blood','Mage-Fire','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','DeathKnight-Frost','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Druid-Feral','Shaman-Enhancement','Mage-Arcane','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aabbigale:BAAALgAECgkJBwAAAA==.',
Ab='Abigt:BAABLgAECn8XAAMBAAcJrR9/BgDzAQABAAcJrR9/BgDzAQACAAQJexGexQDOAAAAAA==.',
Ad='Adalaidê:BAAALgAECgUJCgAAAA==.',
Ae='Aelusion:BAACLgAFFH8GAAICAAMJ3xaaUgD3AAACAAMJ3xaaUgD3AAAuAAQKfx8ABAIACAlIHzwaALcCAAIACAmBHjwaALcCAAMAAwlaIRUsAA4BAAEAAQlAJCInAFUAAAAA.Aeluu:BAAALgAECgcJBwABLgAECggJHwAEALgRAA==.Aerola:BAAALgADCgIJAgAAAA==.Aerynne:BAAALgAECgMJDQAAAA==.',
Ai='Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn8yAAIFAAgJPg9sPACKAQAFAAgJPg9sPACKAQAAAA==.Aita:BAACLgAFFH8NAAIGAAQJIBDvBADgAAAGAAQJIBDvBADgAAAuAAQKfyMAAwYACQnXGO4GAB0CAAYACQnXGO4GAB0CAAcABQmWCTg2AKsAAAAA.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJCQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Alisaa:BAAALgAECgEJAQAAAA==.Allegria:BAAALgAECgEJAgAAAA==.Alluna:BAAALgAECgIJAgAAAA==.Alondra:BAABLgAECn8gAAIDAAkJvB9jAQCxAgADAAkJvB9jAQCxAgAAAA==.Alulà:BAABLgAECn8gAAMIAAcJbh6UDgBYAgAIAAcJTB6UDgBYAgAJAAMJMx4lTQAEAQAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.Aluuni:BAAALgAECggJEwAAAA==.',
Am='Amo:BAAALgAECgIJAgABLgAECggJCAAKAAAAAA==.',
An='Anaeli:BAABLgAECn8+AAMFAAkJyxqoFAB5AgAFAAkJyxqoFAB5AgALAAUJ9wiNWwChAAAAAA==.Anariel:BAAALgADCgUJBQABLgADCgcJDQAKAAAAAA==.Ancalagonn:BAAALgAECgYJBgABLgAECgkJHwAFALEOAA==.Androth:BAABLgAECn8kAAMMAAgJwhz1BwAsAgAMAAgJwhz1BwAsAgANAAIJeAdqJQFaAAAAAA==.Angelius:BAAALgAECgEJAgAAAA==.Angita:BAAALgAECgQJBwAAAA==.Antipæn:BAACLgAFFH8SAAMOAAQJgSOQDwCDAQAOAAQJgSOQDwCDAQANAAMJChuSRAD6AAAuAAQKf0YAAw0ACQmfJnoAAJQDAA0ACQmfJnoAAJQDAA4ABwmNIvcpAOIBAAEuAAUUBQkKAA8A6iUA.',
Ap='Apologia:BAABLgAECn8uAAINAAgJjSM3FACuAgANAAgJjSM3FACuAgAAAA==.',
Ar='Arcanix:BAAALgAECgcJDQAAAA==.Arceé:BAAALgAECgMJBwAAAA==.Archaic:BAABLgAECn83AAIQAAkJtxE7RwDqAQAQAAkJtxE7RwDqAQAAAA==.Ardicelia:BAAALgAECgEJAQAAAA==.Ares:BAACLgAFFH8UAAMRAAYJuh5UBAC6AQARAAYJuh5UBAC6AQASAAIJCB71FgCuAAAuAAQKfyEAAxEACAlRJOUBABoDABEACAnfI+UBABoDABIABwlHIjMZAIICAAAA.Ariellä:BAAALgADCgEJAQAAAA==.Arilynx:BAABLgAECn8iAAITAAkJ4AcZFABlAQATAAkJ4AcZFABlAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn84AAIUAAkJlCOgAQAsAwAUAAkJlCOgAQAsAwAAAA==.Aroviaa:BAABLgAECn87AAMJAAkJSx7xBQD5AgAJAAkJSx7xBQD5AgAIAAEJ9gMDawAoAAAAAA==.Arpmek:BAABLgAECn8tAAIVAAgJ0hOxQAClAQAVAAgJ0hOxQAClAQAAAA==.Artemîs:BAAALgAECgQJBAAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Ashal:BAABLgAECn8ZAAISAAcJ+ghdPwAfAQASAAcJ+ghdPwAfAQAAAA==.Ashlynne:BAAALgAECggJCAAAAA==.Astrotoad:BAAALgAECgUJCAAAAA==.Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgQJBQAAAA==.Aurtt:BAABLgAECn9BAAIWAAkJuRYWEADZAQAWAAkJuRYWEADZAQAAAA==.',
Av='Avanel:BAAALgAECgEJAQAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Az='Azkadelia:BAAALgAECgEJAQAAAA==.',
Ba='Bageera:BAABLgAECn8tAAIEAAgJuB65DQDOAgAEAAgJuB65DQDOAgAAAA==.Bahahaknight:BAABLgAECn8yAAIWAAgJKB4zCgBBAgAWAAgJKB4zCgBBAgAAAA==.Barccky:BAAALgAECgIJAgAAAA==.Barcy:BAAALgAECgEJAwABLgAECgIJAgAKAAAAAA==.Barnette:BAABLgAECn9IAAIXAAkJLhhlAQBoAgAXAAkJLhhlAQBoAgAAAA==.Barvi:BAAALgAECgMJAwABLgAECggJKQAQAFgcAA==.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearmissile:BAAALgAECgQJBAAAAA==.Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn82AAINAAkJ/xx+FgCeAgANAAkJ/xx+FgCeAgAAAA==.Berristan:BAACLgAFFH8FAAIOAAMJSQkhKQCyAAAOAAMJSQkhKQCyAAAuAAQKfycAAw4ACQnfF6IMALUCAA4ACQnfF6IMALUCAA0ABQmkCD/hALUAAAAA.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigmarv:BAABLgAECn8fAAILAAgJ6hfoKQB1AQALAAgJ6hfoKQB1AQAAAA==.Bigsam:BAAALgAECgEJAQAAAA==.Bittytigs:BAAALgADCgUJBQAAAA==.',
Bl='Blossom:BAACLgAFFH8MAAITAAUJww20EABPAQATAAUJww20EABPAQAuAAQKfxUAAhMACAmdEY8YAM4BABMACAmdEY8YAM4BAAAA.Bluewitchpa:BAAALgAECgIJAgAAAA==.',
Bo='Boomboomkill:BAAALgADCgEJAQAAAA==.Bosc:BAAALgAECgkJEgABLgAECggJGwAYADgRAA==.Boudiicca:BAABLgAECn8ZAAIJAAQJmRIyPQDYAAAJAAQJmRIyPQDYAAAAAA==.Boxmasterr:BAABLgAECn8yAAMCAAkJ+wtISwCiAQACAAkJugtISwCiAQABAAcJrgdHGADEAAAAAA==.',
Br='Brasmir:BAABLgAECn8UAAIZAAgJ9gu4HgCIAQAZAAgJ9gu4HgCIAQAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.Brianzero:BAAALgAECgEJAQAAAA==.Brinotriage:BAAALgAECgUJBwAAAA==.',
Bu='Bubblement:BAAALgAFFAUJEgAAAQ==.Bushalabong:BAAALgAECgMJBAAAAA==.Butherrface:BAAALgADCgcJBwAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgAAAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAACLgAFFH8MAAMaAAQJ3yJBFABwAQAaAAQJ/h1BFABwAQAZAAQJBhuFCwBQAQAuAAQKfzYABBoACQl+I0ceAEcCABoACAn9IUceAEcCABkACAm0Hi0NADgCABsABgmIF1YyAKUBAAAA.Cardran:BAAALgADCgEJAQABLgAECggJJAAMAMIcAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAIOAAgJ3yHWBwDwAgAOAAgJ3yHWBwDwAgAAAA==.Catamay:BAABLgAECn8dAAIVAAgJqRuYLwDoAQAVAAgJqRuYLwDoAQABLgAECgEJAQAKAAAAAA==.Catprincess:BAABLgAECn8fAAIEAAgJuBF+OwC3AQAEAAgJuBF+OwC3AQAAAA==.Caylara:BAAALgAECgYJDAAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAAALgAECgUJCwAAAA==.',
Ch='Chai:BAAALgAECgYJDAAAAA==.Chaintrain:BAAALgADCggJBwABLgAECggJHAADAC8eAA==.Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAABLgAECn8kAAIYAAgJfhXAGQC5AQAYAAgJfhXAGQC5AQAAAA==.',
Ci='Cindrethal:BAAALgADCggJCAAAAA==.',
Cl='Claes:BAAALgAECgEJAgABLgAECggJGwAYADgRAA==.Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgAECgMJAwAAAA==.Clorox:BAAALgADCgEJAQAAAA==.',
Co='Coocoohead:BAAALgAECgMJBQAAAA==.Coralorchid:BAABLgAECn8qAAMNAAcJ9RMMhQBEAQANAAcJyA8MhQBEAQAMAAYJHRS+GwAMAQAAAA==.Corrupt:BAAALgAECgEJAQABLgAECgIJBAAKAAAAAA==.',
Cp='Cptdarkk:BAABLgAECn8ZAAINAAcJUwt7lgAmAQANAAcJUwt7lgAmAQAAAA==.',
Cr='Crytal:BAAALgAECgEJAgAAAA==.',
Cu='Cuddlebucket:BAAALgADCgQJBQAAAA==.Curissan:BAABLgAECn8fAAILAAgJehnWFgADAgALAAgJehnWFgADAgAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAABLgAECn8UAAIEAAgJAiFNEQClAgAEAAgJAiFNEQClAgAAAA==.',
['Cø']='Cøndemn:BAAALgAECgYJCAAAAA==.',
Da='Daemyn:BAAALgADCgcJBwAAAA==.Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAABLgAECn8UAAIPAAcJFBtNRQDQAQAPAAcJFBtNRQDQAQAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAgJIAAcAB0RAA==.Dalspin:BAACLgAFFH8gAAIcAAgJHRFhBgA2AgAcAAgJHRFhBgA2AgAuAAQKfyEABBwACQkpG9wHANkCABwACQkpG9wHANkCAB0ABwm8ElYqAIoBABgAAwkEAv5uAE4AAAAA.Dalthepal:BAABLgAECn8UAAIOAAcJXx+pHgAiAgAOAAcJXx+pHgAiAgABLgAFFAgJIAAcAB0RAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAACLgAFFH8RAAINAAQJXRzGHQBdAQANAAQJXRzGHQBdAQAuAAQKf0oAAg0ACQmMJpQAAJADAA0ACQmMJpQAAJADAAAA.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deathsaberss:BAABLgAECn8lAAIRAAkJPBTcDgDTAQARAAkJPBTcDgDTAQAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgcJEQAAAA==.Debauch:BAABLgAECn8ZAAICAAgJYA6KWwB2AQACAAgJYA6KWwB2AQAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Denniah:BAAALgAECgQJBAAAAA==.Derke:BAAALgAECgQJBwAAAA==.Destinee:BAAALgAECgEJAQAAAA==.',
Di='Didudietho:BAAALgADCggJCAABLgAECggJNgANAFkdAA==.Diladrin:BAACLgAFFH8RAAIeAAQJAg4CDQDYAAAeAAQJAg4CDQDYAAAuAAQKf0kAAh4ACQn0G14FAIMCAB4ACQn0G14FAIMCAAAA.Diode:BAACLgAFFH8dAAQPAAYJ7xQHLQBtAQAPAAUJfBEHLQBtAQAfAAQJBBMsCQAfAQAWAAEJAAD1PgAAAAAuAAQKfy8AAw8ACAmnITUYAOoCAA8ACAn8IDUYAOoCAB8ACAl1HHoHANwBAAAA.',
Do='Doileag:BAAALgAECgYJEwAAAA==.Domer:BAAALgAECgYJCAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dora:BAAALgAECgMJAwAAAA==.Dottmatrix:BAAALgAECgYJEwAAAA==.',
Dr='Drachnia:BAAALgAECgQJBAAAAA==.Dragønbreath:BAACLgAFFH8MAAMQAAUJHAnFVAAcAQAQAAUJHAnFVAAcAQAXAAEJaAM/BAA3AAAuAAQKfx0AAxcACQlxGhcCAEoCABcACAnMFxcCAEoCABAACAk3FaCZACsBAAAA.Dreadwing:BAABLgAECn8WAAIPAAMJGgQmAgFrAAAPAAMJGgQmAgFrAAAAAA==.',
Du='Duf:BAACLgAFFH8gAAIYAAYJHx3XBwC6AQAYAAYJHx3XBwC6AQAuAAQKfy0AAhgACAkwH1IRAIwCABgACAkwH1IRAIwCAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn87AAIJAAkJPSBeBAAgAwAJAAkJPSBeBAAgAwAAAA==.',
Dw='Dwagon:BAAALgAECggJEAAAAA==.',
['Dæ']='Dæmôn:BAAALgAECgYJCQAAAA==.',
['Dì']='Dìzzy:BAAALgAECgIJAgAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAACLgAFFH8GAAIdAAMJqgvOGwDGAAAdAAMJqgvOGwDGAAAuAAQKfy8AAxgACQnyGggNAEcCABgACQnyGggNAEcCAB0AAgmkGCFgAI8AAAAA.Dûna:BAACLgAFFH8FAAIgAAIJVR0TIACzAAAgAAIJVR0TIACzAAAuAAQKfyIAAiAACAkAIJwMAGYCACAACAkAIJwMAGYCAAEuAAUUAwkGAB0AqgsA.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn9BAAINAAkJ4CNCBgAoAwANAAkJ4CNCBgAoAwAAAA==.Elduar:BAAALgADCgEJAQAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAABLgAECn8YAAILAAcJfBCQNAA5AQALAAcJfBCQNAA5AQAAAA==.Elketha:BAAALgAECgUJBQABLgAFFAQJEQAVAC0YAA==.Ellaring:BAAALgAECgYJCAABLgAECgYJDAAKAAAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrric:BAABLgAECn8VAAIPAAgJQQwicQBcAQAPAAgJQQwicQBcAQAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAABLgAECn8qAAMFAAgJnyCRFQBxAgAFAAcJyB+RFQBxAgALAAcJWQ4FPgAMAQAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Eroviaa:BAAALgAECgQJBQABLgAECgkJOwAJAEseAA==.Erovvia:BAAALgAECgUJBgABLgAECgkJOwAJAEseAA==.',
Es='Essaelsia:BAAALgAECgUJBQAAAA==.',
Et='Etali:BAAALgAECgMJBAABLgAECggJMQAHANMYAA==.',
Ez='Ezothen:BAABLgAECn8gAAMhAAgJ0wQEQwD2AAAhAAgJfwQEQwD2AAAiAAQJawRpLwCdAAAAAA==.',
Fa='Faedoria:BAABLgAECn8aAAINAAYJdAS04gCzAAANAAYJdAS04gCzAAAAAA==.Faeryln:BAABLgAECn8iAAIJAAkJUQtOJgBvAQAJAAkJUQtOJgBvAQAAAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falenrush:BAAALgADCgEJAQAAAA==.Falkorr:BAAALgAECgEJAQABLgAECggJNQAjAH4dAA==.Falorie:BAAALgADCgYJEQAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAABLgAECn8yAAMTAAgJRSG4BQCTAgATAAcJgiG4BQCTAgAhAAEJByGxagBiAAAAAA==.Faustus:BAAALgADCgQJCgABLgAECggJMgATAEUhAA==.',
Fe='Feature:BAAALgAECgkJBwAAAA==.Felstormer:BAAALgADCggJEAABLgAECgIJAgAKAAAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgUJCAAAAA==.Fireføx:BAAALgADCgEJAQAAAA==.Fisticuffs:BAAALgAECgIJAgAAAA==.Fizzllebang:BAABLgAECn8jAAIDAAkJTRBFCgBxAQADAAkJTRBFCgBxAQAAAA==.',
Fl='Flamewhisker:BAAALgAECgUJCAAAAQ==.Flogginrenee:BAAALgAECgYJEwAAAA==.Floggsdaddy:BAAALgAECgYJEwAAAA==.Floke:BAAALgAECgMJBAAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fr='Fraublucher:BAABLgAECn8yAAIJAAgJgBVHGADkAQAJAAgJgBVHGADkAQAAAA==.Fredrik:BAAALgAFFAIJBAABLgAFFAQJFAAQAJENAA==.Frewyn:BAAALgAECgQJCAAAAA==.Frikk:BAAALgAECgEJAQAAAA==.Frostimoth:BAABLgAECn8jAAIQAAgJlRWWTADZAQAQAAgJlRWWTADZAQAAAA==.Frozty:BAABLgAECn8UAAITAAYJfhUvEwBzAQATAAYJfhUvEwBzAQAAAA==.',
Ga='Galandel:BAAALgAECgIJAgAAAA==.Galial:BAACLgAFFH8TAAIGAAUJIyGXAQByAQAGAAUJIyGXAQByAQAuAAQKfyIAAgYACQlaHzsBACIDAAYACQlaHzsBACIDAAAA.Gantar:BAABLgAECn8VAAIeAAgJ1SKuAgD6AgAeAAgJ1SKuAgD6AgAAAA==.Garlicbread:BAAALgADCgYJBgABLgAFFAUJEwAGACMhAA==.Gaznol:BAABLgAECn8hAAIaAAgJuCHsEwCJAgAaAAgJuCHsEwCJAgAAAA==.',
Ge='Gelasera:BAAALgAECgUJCAAAAA==.',
Gh='Ghibli:BAABLgAECn8WAAMRAAgJ7BDUGABqAQARAAgJ7BDUGABqAQASAAIJ7AWjmgBWAAAAAA==.',
Gl='Glaivethras:BAABLgAECn8iAAIGAAkJ7yHuAgCYAgAGAAkJ7yHuAgCYAgAAAA==.Glyphix:BAABLgAECn8fAAISAAkJZQlCLAB8AQASAAkJZQlCLAB8AQAAAA==.',
Gn='Gnarly:BAAALgAECgIJBAAAAA==.',
Go='Goochtrap:BAAALgAECgQJBAAAAA==.Gorgon:BAAALgAECgMJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAABLgAECn8gAAQZAAgJxgxHHgCLAQAZAAgJuAtHHgCLAQAaAAQJeQ4vgQDkAAAbAAQJXwUlaACeAAAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.Groot:BAABLgAECn8VAAMEAAUJtRLkUQAlAQAEAAUJtRLkUQAlAQAjAAQJhgpsTACpAAABLgAECgkJJgANAO4WAA==.Groovinchef:BAAALgAECgEJAQAAAA==.Grump:BAAALgAECgEJAQAAAA==.',
Gu='Gundunn:BAAALgADCgEJAQAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECgQJCgAKAAAAAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAEBLgAECn8dAAIgAAgJsRCSJQB2AQAgAAgJsRCSJQB2AQABLgAECgYJBwAKAAAAAA==.Hannebal:BAABLgAECn8aAAIOAAkJEhGQIADZAQAOAAkJEhGQIADZAQAAAA==.Havenfire:BAAALgADCgUJBQABLgAECgEJAQAKAAAAAA==.',
He='Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCggJEgAAAA==.Heydaw:BAAALgAECggJDgABLgAECgkJIAAPAHIgAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgAECgEJAQAAAA==.Holybeatdown:BAAALgAECgMJBAAAAA==.Holyrage:BAAALgADCgQJBAAAAA==.Holyßloodelf:BAAALgAECggJCwABLgAECggJFwAPAFsUAA==.Honeysbadger:BAAALgAECgMJAwAAAA==.Hoosier:BAAALgAECgQJBQAAAA==.Hornet:BAABLgAECn8VAAMVAAgJZBDbUgBqAQAVAAgJ7w/bUgBqAQAHAAQJFwz3SADPAAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.Hotsauce:BAAALgAECgYJCAABLgAFFAcJGgAQAOIaAA==.',
Hu='Huasca:BAAALgAECgMJBQAAAA==.Humungous:BAAALgAECgcJDQAAAA==.Hunnybunz:BAAALgAECgYJDAAAAA==.',
['Hà']='Hàney:BAEALgAECgYJBwAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJEgAAAA==.',
['Hé']='Hélio:BAAALgADCgUJBQAAAA==.',
Ia='Ia:BAAALgAFFAMJAwAAAA==.',
Ic='Icastfirebal:BAAALgAECgEJAQAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECggJDAAAAA==.',
Ig='Igotahitin:BAAALgADCgMJCAAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAABLgAECn8bAAIYAAgJOBFgIgB4AQAYAAgJOBFgIgB4AQAAAA==.',
Il='Illida:BAAALgAECgMJAwAAAA==.',
Im='Imamalelol:BAABLgAECn8YAAQSAAYJlAj+TADpAAASAAYJlAj+TADpAAARAAQJVANhZgApAAAUAAEJqgA0UwAUAAAAAA==.',
In='Indira:BAAALgADCgcJDQAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAUJCAABLgAFFAUJDAATAMMNAQ==.Inumimi:BAABLgAECn8dAAIkAAgJ5ASYHwDOAAAkAAgJ5ASYHwDOAAAAAA==.Invincidemon:BAAALgAECgQJBAAAAA==.',
Ir='Irkenfox:BAECLgAFFH8cAAIUAAYJgyGuAwDdAQAUAAYJgyGuAwDdAQAuAAQKfyUAAhQACAmhI54DABsDABQACAmhI54DABsDAAAA.',
It='Ithran:BAABLgAECn8iAAIQAAkJKQzZXACrAQAQAAkJKQzZXACrAQAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8uAAIXAAkJrx3hAACzAgAXAAkJrx3hAACzAgAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.Jama:BAAALgADCgcJCAAAAA==.James:BAACLgAFFH8UAAIQAAQJkQ1pTAAwAQAQAAQJkQ1pTAAwAQAuAAQKf0EAAhAACAn5H0khAH0CABAACAn5H0khAH0CAAAA.Janderick:BAABLgAECn8gAAISAAgJQiByEgA9AgASAAgJQiByEgA9AgAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jellacee:BAABLgAECn8aAAMHAAUJeRHfOQCXAAAHAAUJeRHfOQCXAAAVAAIJHgPw6QA3AAAAAA==.Jesterjoe:BAAALgAECgQJCAAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8dAAIDAAYJhCIyAQDdAQADAAYJhCIyAQDdAQAuAAQKfy0AAgMACAk2JfQAAC8DAAMACAk2JfQAAC8DAAAA.Jimi:BAAALgADCgUJBQAAAA==.Jimreaper:BAAALgAECgkJCQAAAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJBAABLgAECggJFQAeANUiAA==.',
Jo='Joejitsu:BAAALgAECgMJAwAAAA==.Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAABLgAECn8cAAQDAAgJLx7/BwCiAQADAAYJrx3/BwCiAQACAAMJMhmuqwDTAAABAAEJXCB1KgBKAAAAAA==.Joltraxi:BAAALgAECgMJBQAAAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJEwABLgAECggJFQAeANUiAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Js='Jstnbieber:BAAALgAECgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCgAAAA==.Juicethevoid:BAABLgAECn8pAAIVAAkJnwe+XABOAQAVAAkJnwe+XABOAQAAAA==.Juniornite:BAABLgAECn82AAIQAAkJmCCuEADfAgAQAAkJmCCuEADfAgAAAA==.Justicus:BAAALgAECgYJEQABLgAECgkJJgAaALUbAA==.Justthetouch:BAAALgAECggJCQAAAA==.',
['Jü']='Jüst:BAAALgAECgMJAwAAAA==.',
Ka='Kaeldrin:BAAALgADCgkJFAAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAABLgAECn8xAAQHAAgJ0xgpFQCsAQAHAAcJ/RcpFQCsAQAGAAcJVhXhCwBwAQAVAAgJsA6+VABlAQAAAA==.Kahgar:BAAALgAECgEJAQAAAA==.Kaiser:BAAALgAECgQJCQAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgQJBwAAAA==.Kalzod:BAACLgAFFH8RAAICAAQJoRv4LgBLAQACAAQJoRv4LgBLAQAuAAQKfz4AAwIACQlLJnMBAHgDAAIACQlLJnMBAHgDAAEAAQkAAB0kAGEAAAAA.Kariana:BAAALgAECgYJDgAAAA==.Kataki:BAAALgAECgMJBAABLgAECggJMQAHANMYAA==.Katett:BAAALgAECgcJDgAAAA==.Kativeria:BAAALgAECgUJCAAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDwABLgAECgYJDgAKAAAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgYJEgAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Kerfufle:BAAALgAECgEJAQAAAA==.Keyn:BAAALgADCgEJAQAAAA==.Keynstolor:BAABLgAECn8hAAIaAAgJRBp1NgDZAQAaAAgJRBp1NgDZAQAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.Khálifá:BAAALgAECgUJBgAAAA==.',
Ki='Kicker:BAABLgAECn8UAAISAAYJcgYqVwDFAAASAAYJcgYqVwDFAAAAAA==.Killmora:BAAALgAECgIJAgAAAA==.Kippars:BAABLgAECn8aAAMeAAcJBRQkIwDyAAAeAAYJuhMkIwDyAAAkAAEJfRV4OABBAAAAAA==.Kiritsugo:BAAALgADCggJEAAAAA==.Kissame:BAAALgAECgYJCAAAAA==.',
Kn='Knaifu:BAAALgADCgQJBAAAAA==.',
Ko='Kodazoff:BAABLgAECn8tAAMhAAkJNhLqGADuAQAhAAkJNhLqGADuAQATAAIJIAdiNAAzAAAAAA==.Korevash:BAABLgAECn8jAAMlAAcJjBwtDAC5AQAlAAcJjBwtDAC5AQAFAAIJ4wkRnABVAAABLgAFFAQJEQAIAMoRAA==.Korupta:BAABLgAECn8uAAMVAAgJHBCNUQBuAQAVAAgJHBCNUQBuAQAHAAUJ3A36PQAFAQABLgAECgkJJAACADgSAA==.Korzilius:BAAALgAECggJEAAAAA==.',
Kr='Krissylu:BAABLgAECn8ZAAIBAAYJhAupEgADAQABAAYJhAupEgADAQAAAA==.Krockett:BAAALgAECgQJBAAAAA==.Krothix:BAABLgAECn80AAILAAkJPQy+KgBwAQALAAkJPQy+KgBwAQAAAA==.Kruvix:BAAALgAECgYJCgAAAA==.Kryjag:BAAALgADCggJFwAAAA==.Krynir:BAAALgADCgkJDgAAAA==.Kryshym:BAAALgAECgYJBgAAAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAAALgAECgUJDgAAAA==.',
['Kü']='Kürömë:BAAALgADCgMJAwAAAA==.',
La='Ladara:BAABLgAECn8tAAIBAAkJ8BAuCACxAQABAAkJ8BAuCACxAQAAAA==.Laima:BAAALgADCgUJDQAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAQAAAA==.Lavitz:BAAALgAECgMJAwAAAA==.',
Le='Leheo:BAAALgAECgQJBgAAAA==.Lehua:BAAALgADCggJDAAAAA==.Leilanii:BAAALgAECgIJAgAAAA==.Lemook:BAAALgAECgYJBwAAAA==.Leonìdas:BAAALgAECgQJBgAAAA==.',
Lh='Lhei:BAAALgAECgQJBgAAAA==.',
Li='Lightstormer:BAAALgAECgIJAgAAAA==.Lilamae:BAAALgAECgcJCAAAAA==.Lilarielle:BAABLgAECn8uAAIkAAgJXwdmHQDiAAAkAAgJXwdmHQDiAAAAAA==.Lildash:BAAALgADCgIJAgABLgAECggJJAAMAMIcAA==.Lilface:BAAALgAECgYJCgAAAA==.Liliela:BAAALgAECgQJBAABLgAECggJJAAMAMIcAA==.Lilsham:BAAALgAECgQJBAABLgAECggJJAAMAMIcAA==.Lilyannah:BAAALgAECgkJAQAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgIJAgAKAAAAAA==.Liopain:BAAALgAECgIJAgAAAA==.Liø:BAAALgAECgEJAQABLgAECgIJAgAKAAAAAA==.',
Lo='Lokir:BAAALgAECgMJBgAAAA==.Lotheovian:BAEALgAECgIJAgABLgAECggJLQAPAD0bAA==.Lowchin:BAAALgAECgYJEAAAAA==.',
Lu='Lumia:BAABLgAECn8dAAMgAAkJix4wEwBcAgAgAAcJlB8wEwBcAgAJAAYJFBjVSgANAQAAAA==.Lutherion:BAAALgAECgUJCAAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgAECgEJAQAAAA==.Mackshiesty:BAABLgAECn8WAAIVAAYJwhgQVgBhAQAVAAYJwhgQVgBhAQAAAA==.Macoun:BAABLgAECn8oAAMaAAkJpiRRBAAvAwAaAAkJpiRRBAAvAwAbAAYJEhv0QABVAQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn88AAIQAAkJBiaHAwBjAwAQAAkJBiaHAwBjAwAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAABLgAECn8XAAIgAAcJewvfMAAwAQAgAAcJewvfMAAwAQAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBgAKAAAAAA==.Martei:BAACLgAFFH8ZAAIkAAUJUBf/AwBWAQAkAAUJUBf/AwBWAQAuAAQKfy0AAiQACAmUI0ICAC8DACQACAmUI0ICAC8DAAAA.Maríneth:BAAALgAECgQJCgAAAA==.Mathías:BAABLgAECn8iAAIaAAkJPBefMQDsAQAaAAkJPBefMQDsAQAAAA==.Mavze:BAAALgADCgIJAgAAAA==.',
Me='Meadowfrey:BAAALgAECgEJAQAAAA==.Meowbae:BAABLgAECn8sAAMkAAkJGhUDCQAFAgAkAAkJGhUDCQAFAgAjAAEJNAGMjAAVAAAAAA==.Mercesdes:BAAALgAECgUJBgAAAA==.Mercina:BAAALgAECgEJAwAAAA==.Mercuros:BAAALgAECggJEwAAAA==.Merknlock:BAAALgAECgEJAQAAAA==.',
Mi='Midnyte:BAABLgAECn8/AAMdAAkJThoODQBNAgAdAAkJThoODQBNAgAcAAkJshNNGgAGAgAAAA==.Milkyweí:BAAALgAECgMJAwAAAA==.Mini:BAAALgADCgUJBQABLgAECggJKQAQAFgcAA==.Minizee:BAAALgAECgQJBAAAAA==.Mirabella:BAAALgAECgQJBgABLgAECgkJJwAcAAAiAA==.Mirokushan:BAAALgAECgMJDAABLgAECgQJDwAKAAAAAA==.Mistfit:BAAALgAECgMJAgAAAA==.Misticlady:BAAALgADCgEJAQAAAA==.Mistingmoo:BAAALgAECgQJBAABLgAECgcJFwARAMIKAA==.Mistrariel:BAABLgAECn8nAAIGAAgJuR4vBABcAgAGAAgJuR4vBABcAgAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Moostafa:BAAALgAECgQJBAAAAA==.Moradin:BAAALgADCgEJAQAAAA==.Mordemour:BAAALgAECgUJCwAAAA==.',
Mu='Mungo:BAABLgAECn8pAAIQAAgJTBiGQQD8AQAQAAgJTBiGQQD8AQAAAA==.',
My='My:BAAALgAECgYJCQAAAA==.Mynkie:BAACLgAFFH8PAAIcAAQJExTmHAANAQAcAAQJExTmHAANAQAuAAQKfzQAAhwACQlfIvECAHADABwACQlfIvECAHADAAAA.Myrell:BAAALgAECgkJBgAAAA==.Mythreashis:BAAALgADCgMJAwAAAA==.',
['Mä']='Mägi:BAAALgAECgEJAQAAAA==.',
['Må']='Mååt:BAAALgADCgIJAgAAAA==.',
['Mæ']='Mæstra:BAAALgADCgEJAQAAAA==.',
['Më']='Mëlony:BAAALgADCgIJAgAAAA==.',
Na='Nachtmar:BAAALgAECgQJCQAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8eAAIVAAYJKxTEGwB/AQAVAAYJKxTEGwB/AQAuAAQKfyoAAhUACAlDHF8qAAECABUACAlDHF8qAAECAAAA.',
Ne='Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nikkitta:BAAALgADCgMJAwAAAA==.Nimravidae:BAABLgAECn8xAAMOAAgJCxd6GwABAgAOAAgJCxd6GwABAgANAAcJeQ7ogwBGAQAAAA==.Ninelives:BAABLgAECn8gAAIjAAgJsgKzSQCzAAAjAAgJsgKzSQCzAAAAAA==.Nitecrawler:BAABLgAECn8hAAMQAAgJ2Q5KagCKAQAQAAgJ2Q5KagCKAQAmAAEJhQNGFAAbAAAAAA==.Niteryu:BAAALgAECggJCAABLgAECgkJNgAQAJggAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAABLgAECn8hAAIhAAgJ+wt5MQBGAQAhAAgJ+wt5MQBGAQAAAA==.Noxium:BAAALgAECgYJDQAAAA==.Noxolon:BAABLgAECn8sAAISAAgJ4xuuFwANAgASAAgJ4xuuFwANAgAAAA==.',
Nr='Nreaf:BAABLgAECn8wAAMNAAgJyhy9JACUAgANAAgJyhy9JACUAgAMAAQJChcfJQDfAAAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgQJCAAAAA==.Nysca:BAAALgADCgcJBwAAAA==.',
Ob='Obijuan:BAAALgAECgMJAwAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAAALgAECgUJCwAAAA==.',
Or='Ornstein:BAABLgAECn8dAAMMAAYJmiH1CwDZAQAMAAYJmiH1CwDZAQANAAYJGBCsnAAbAQAAAA==.',
Ot='Ottuk:BAACLgAFFH8TAAMPAAUJpxVwRQA8AQAPAAQJpxVwRQA8AQAWAAEJAABeSAAAAAAuAAQKfyIAAw8ACQnVIa8IAFgDAA8ACQnVIa8IAFgDABYAAwlnHX0nAAMBAAAA.',
Pa='Padinbar:BAAALgAECgQJBAAAAA==.Paksenarrion:BAABLgAECn8yAAIMAAgJdBFYEgB0AQAMAAgJdBFYEgB0AQAAAA==.Pancham:BAAALgADCgUJBQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECgkJEQAAAA==.Pandemônium:BAAALgAECggJEAAAAA==.Pandemönium:BAAALgAECgIJAQAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Pandèmonium:BAAALgAECgYJBgAAAA==.Patchington:BAAALgAECgQJCgAAAA==.Pañdemönium:BAAALgAECgQJBAAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Perck:BAAALgAECgQJBAAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAFFAIJBQAhAIgTAA==.Pezvoker:BAABLgAFFH8FAAIhAAIJiBOZPQCOAAAhAAIJiBOZPQCOAAAAAA==.',
Pi='Pienarri:BAAALgAECgEJAgAAAA==.Pixelme:BAAALgAECgMJBQAAAA==.',
Pl='Pleggster:BAABLgAECn8ZAAMFAAgJJA6TQAB5AQAFAAgJJA6TQAB5AQALAAEJiAGDnQAcAAAAAA==.',
Po='Pochula:BAABLgAECn8kAAIEAAgJaxV+JQD/AQAEAAgJaxV+JQD/AQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAABLgAECn8rAAIOAAgJGBHeNwCbAQAOAAgJGBHeNwCbAQAAAA==.Protricity:BAABLgAECn88AAMgAAkJdCAXBwDBAgAgAAkJdCAXBwDBAgAJAAEJ2AJchAAtAAAAAA==.',
Pu='Pumpernickel:BAAALgADCgUJBQABLgAFFAUJEwAGACMhAA==.Puppytoes:BAAALgAECgEJAgAAAA==.',
Py='Pyrellyn:BAAALgADCggJCgAAAA==.',
['Pä']='Pändamönium:BAAALgAECgkJEQAAAA==.',
['Pæ']='Pæn:BAACLgAFFH8KAAIPAAUJ6iUMFgC7AQAPAAUJ6iUMFgC7AQAuAAQKfykAAw8ABwkXJLk1AAUCAA8ABgkIJbk1AAUCABYABwmPH60PAN8BAAAA.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgUJCAABLgAECgYJCwAKAAAAAA==.Quantar:BAAALgAECgYJCwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rakta:BAAALgAECgYJBgAAAA==.Rancooll:BAAALgAECgIJAgAAAA==.Rasniir:BAABLgAECn86AAIEAAkJSx8JBwAsAwAEAAkJSx8JBwAsAwAAAA==.Ravenlash:BAAALgAECgEJBAAAAA==.',
Re='Regna:BAACLgAFFH8dAAISAAYJ0SZjAQA1AgASAAYJ0SZjAQA1AgAuAAQKfy4AAhIACAmLJhgDAH8DABIACAmLJhgDAH8DAAAA.Regner:BAAALgAECgEJAQAAAA==.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAABLgAECn8VAAIWAAcJlQxYJQD6AAAWAAcJlQxYJQD6AAAAAA==.Remaked:BAACLgAFFH8rAAIYAAcJgR1TBAABAgAYAAcJgR1TBAABAgAuAAQKf0AAAhgACQmsI90CABMDABgACQmsI90CABMDAAAA.Remilia:BAABLgAECn8tAAIgAAgJnR2lDABlAgAgAAgJnR2lDABlAgAAAA==.Requinix:BAABLgAECn88AAIaAAkJIxiLHgBFAgAaAAkJIxiLHgBFAgAAAA==.Retro:BAAALgAECgEJAQAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAECggJBwAAAA==.Revwrinkle:BAAALgAECgIJAwAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgUJEAAAAA==.Ricochet:BAABLgAECn8eAAIZAAgJphGpGQCzAQAZAAgJphGpGQCzAQAAAA==.Riptidez:BAAALgADCgcJBgAAAA==.Ririko:BAABLgAECn8tAAIJAAgJvA72JQByAQAJAAgJvA72JQByAQAAAA==.Ritzo:BAABLgAECn8oAAISAAgJnBT4IgC2AQASAAgJnBT4IgC2AQAAAA==.Rizzla:BAAALgAECgIJAgABLgAECggJNQAjAH4dAA==.',
Ro='Rockllobster:BAAALgAECgYJDAAAAA==.Rocksanne:BAAALgADCgcJEAAAAA==.Roguebâit:BAABLgAECn8/AAQBAAkJixuxBAAZAgABAAcJlBuxBAAZAgACAAcJjBTMSQCmAQADAAMJJw3SRACiAAAAAA==.Ronarvinge:BAAALgAECgMJAwABLgAECgQJBAAKAAAAAA==.Ronen:BAAALgAECgQJBAAAAA==.',
Ru='Rubywolf:BAAALgAECgYJDQABLgAECggJHgAjANkWAA==.Rukkis:BAABLgAECn8fAAMnAAgJhBoUDwAVAgAnAAgJhBoUDwAVAgAoAAEJjQn7HQAvAAAAAA==.Rumi:BAACLgAFFH8OAAIGAAQJlBuCAgA7AQAGAAQJlBuCAgA7AQAuAAQKf0kAAwYACQnSJKMAAEEDAAYACQnSJKMAAEEDAAcAAQlvEZlVADQAAAAA.',
Ry='Ryeekan:BAABLgAECn8mAAIaAAgJGxRPPwC5AQAaAAgJGxRPPwC5AQAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAABLgAECn8mAAINAAkJ7hbGRADZAQANAAkJ7hbGRADZAQAAAA==.Saelena:BAAALgADCgEJAQAAAA==.Sakheddala:BAAALgAECgQJBAAAAA==.Sancha:BAAALgADCgQJBAAAAA==.Sanosagara:BAABLgAECn83AAIcAAgJFhkXFABBAgAcAAgJFhkXFABBAgAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgAECgIJAwAAAA==.Sarithon:BAAALgAECgYJBgAAAA==.Saru:BAAALgADCgkJDQAAAA==.Saruta:BAACLgAFFH8RAAMSAAQJXhAeGgAmAQASAAQJXhAeGgAmAQARAAEJdQOIMAA4AAAuAAQKfygAAxIACAlKHrkXAAwCABIABwkkIbkXAAwCABEABQmqDwoWAE4BAAAA.Sath:BAAALgADCgQJBQAAAA==.Sathari:BAABLgAECn8nAAIVAAgJQhVrSwCBAQAVAAgJQhVrSwCBAQAAAA==.Satsuki:BAABLgAECn8UAAIIAAcJBBx2EgAjAgAIAAcJBBx2EgAjAgABLgAFFAQJEQAVAC0YAA==.',
Sc='Scarycat:BAAALgADCgYJBgAAAA==.Schaden:BAAALgAECgEJAQABLgAECggJFAAEAAIhAA==.',
Se='Seijo:BAAALgAECgMJAwAAAA==.Sekk:BAABLgAECn9DAAINAAkJ3B9MDgDZAgANAAkJ3B9MDgDZAgAAAA==.Selexi:BAAALgADCgYJEAAAAA==.Sereya:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.Sesshanmaru:BAAALgADCgEJAQAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAABLgAECn86AAIHAAgJjR1sCgBQAgAHAAgJjR1sCgBQAgAAAA==.Shadoshiftt:BAABLgAECn8kAAMjAAgJ2AZzOQD7AAAjAAgJ2AZzOQD7AAAEAAgJGALwlwCeAAAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgAECgIJAgAAAA==.Shamzee:BAACLgAFFH8LAAMFAAMJMR9fJQAVAQAFAAMJMR9fJQAVAQALAAEJrQKzQwA6AAAuAAQKfycAAwUACAkDG0kdADUCAAUACAkDG0kdADUCAAsAAQlWDTGIADEAAAAA.Shandalf:BAAALgAECgQJDwAAAA==.Shansebaim:BAAALgAECgYJBgAAAA==.Shintok:BAAALgAECgUJBQAAAA==.Shuddarun:BAACLgAFFH8fAAIaAAYJoSAdBgDWAQAaAAYJoSAdBgDWAQAuAAQKfyoAAhoACAmXJcUDAFQDABoACAmXJcUDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgADCgcJDQAKAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simn:BAABLgAECn8bAAIaAAgJSBzzIgAtAgAaAAgJSBzzIgAtAgAAAA==.Sindraesong:BAAALgAECggJEgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgAECgIJBAAAAA==.',
Sk='Skrai:BAAALgAECgYJCgABLgAECggJGAAUAGAdAA==.',
Sl='Slayvylora:BAACLgAFFH8cAAMNAAYJAhfPDQA8AQANAAUJwRPPDQA8AQAOAAEJ+QLDOABHAAAuAAQKfzEABA0ACAmjI0UXAN0CAA0ACAmjI0UXAN0CAA4ABQmWB29uAMEAAAwAAgn2FtAuAIAAAAAA.Sleep:BAAALgAECgQJBAABLgAFFAMJAwAKAAAAAA==.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgAECgIJBQAAAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Sneakymoth:BAAALgAECgYJEwABLgAECggJIwAQAJUVAA==.Sniff:BAABLgAECn8pAAIQAAgJWBxvMQA1AgAQAAgJWBxvMQA1AgAAAA==.Snookums:BAABLgAECn84AAIVAAcJLRyCNADUAQAVAAcJLRyCNADUAQAAAA==.',
So='Soulomon:BAABLgAECn8WAAICAAgJrBMwgwBUAQACAAgJrBMwgwBUAQAAAA==.Soulsarisen:BAAALgAECgYJDwAAAA==.',
Sp='Spanki:BAAALgADCgkJEAAAAA==.Spellteaser:BAABLgAECn8UAAIQAAYJOhkguQBvAQAQAAYJOhkguQBvAQAAAA==.Spicymaker:BAABLgAECn8jAAIRAAgJCSDcBwBQAgARAAgJCSDcBwBQAgAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJCgAAAA==.Steelheart:BAAALgAECgEJBgAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Stolensøul:BAAALgADCgkJDgAAAA==.Strifewood:BAABLgAECn8bAAIWAAgJzBg4FQCUAQAWAAgJzBg4FQCUAQAAAA==.Stumper:BAABLgAECn81AAIjAAgJfh1iDgBNAgAjAAgJfh1iDgBNAgAAAA==.',
Su='Sugondese:BAAALgAECgQJBgAAAA==.Suluna:BAAALgAECgUJBQABLgAECgkJPgAFAMsaAA==.Summêr:BAABLgAECn8XAAIcAAYJdAfeVAC+AAAcAAYJdAfeVAC+AAAAAA==.Suri:BAAALgAECgUJCgABLgAECggJCAAKAAAAAA==.Sux:BAABLgAECn8ZAAIeAAgJqg4yIQAAAQAeAAgJqg4yIQAAAQAAAA==.',
Sy='Sybrina:BAABLgAECn8WAAIaAAYJhhXYaABDAQAaAAYJhhXYaABDAQAAAA==.Sylvia:BAAALgADCgcJBgABLgAECgEJAQAKAAAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAABLgAECn8pAAIaAAYJqwrQhAAFAQAaAAYJqwrQhAAFAQAAAA==.Synèsterwolf:BAAALgAECgIJAwABLgAECggJHgAjANkWAA==.',
['Sí']='Síf:BAAALgAECgcJCQAAAA==.',
Ta='Tabernacle:BAAALgAECgUJBQAAAA==.Tadeusz:BAAALgAECgUJBQAAAA==.Tamamò:BAABLgAECn8WAAIcAAcJ1BGPKABvAQAcAAcJ1BGPKABvAQAAAA==.Tarrok:BAAALgADCgMJBwAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAAALgAECgIJAgAAAA==.Tepache:BAAALgADCgEJAQAAAA==.Tequitos:BAABLgAECn8dAAMOAAgJNAzuOQA5AQAOAAgJNAzuOQA5AQANAAYJnwuOtQD0AAAAAA==.Teranin:BAABLgAECn8UAAIjAAcJPwiGPgDjAAAjAAcJPwiGPgDjAAAAAA==.',
Tf='Tfortyone:BAAALgAECgUJCAAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgIJAgAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAACLgAFFH8PAAIQAAQJxR5aJwCGAQAQAAQJxR5aJwCGAQAuAAQKf0kAAhAACQmBJdICAGwDABAACQmBJdICAGwDAAAA.',
Ti='Tiren:BAAALgAECgYJDQAAAA==.',
To='Torag:BAAALgAECgQJBAAAAA==.Torment:BAABLgAECn9EAAIWAAkJIh0KBwCIAgAWAAkJIh0KBwCIAgAAAA==.Tosti:BAAALgAECgkJAQAAAA==.',
Tr='Trepania:BAACLgAFFH8YAAIJAAYJ1wowCACNAQAJAAYJ1wowCACNAQAuAAQKfywAAgkACAkMGtEWACUCAAkACAkMGtEWACUCAAAA.Tristén:BAAALgAECgcJDgAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Trollycarp:BAABLgAECn8fAAMMAAgJvApGJQC7AAANAAgJlwOPuADwAAAMAAUJdhBGJQC7AAAAAA==.Truvie:BAAALgAECgQJBAAAAA==.',
Tu='Tumbler:BAABLgAECn8XAAMFAAgJix0sFQB1AgAFAAgJix0sFQB1AgALAAMJCBG2XwCTAAAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAABLgAECn8rAAMFAAYJdAxJZAD2AAAFAAYJdAxJZAD2AAALAAQJYAmgWgCkAAAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAABLgAECn8jAAIZAAkJRxG5EQADAgAZAAkJRxG5EQADAgAAAA==.',
Ul='Ulnuk:BAACLgAFFH8NAAIFAAQJ/hYhJQAWAQAFAAQJ/hYhJQAWAQAuAAQKfzEAAgUACQnvIKYGACADAAUACQnvIKYGACADAAAA.Ulster:BAAALgAECgEJAQAAAA==.',
Un='Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAAKAAAAAA==.',
Va='Vadka:BAAALgAECgcJDwAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAAALgAECgQJCgAAAA==.Vairian:BAABLgAECn8YAAIHAAYJjxBuKAD9AAAHAAYJjxBuKAD9AAAAAA==.Valkree:BAAALgAECgUJBwAAAA==.Vallae:BAAALgADCgkJEQABLgAECgkJPgAFAMsaAA==.Valsavis:BAABLgAECn9BAAIGAAkJoRxrAwB+AgAGAAkJoRxrAwB+AgAAAA==.Valtier:BAAALgAECgQJBQAAAA==.Vampirä:BAABLgAECn8gAAQEAAgJFQhEiQDCAAAEAAYJUwREiQDCAAAkAAQJngWOKgCAAAAjAAIJrgMRcQA8AAAAAA==.Varactor:BAAALgAECgMJAwAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAIdAAgJ7iA1CAD3AgAdAAgJ7iA1CAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgUJCAAAAA==.Vernice:BAAALgAECgEJAQABLgAECgUJCwAKAAAAAA==.Verulan:BAABLgAECn8ZAAMjAAcJhwmSOAD/AAAjAAcJhwmSOAD/AAAEAAQJjAregwCQAAAAAA==.Vexeh:BAAALgAECgMJBAAAAA==.Vexomous:BAAALgAECgUJDwAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vierina:BAAALgAECgEJAQAAAA==.Vikss:BAABLgAECn8oAAMaAAgJUxOfSgCVAQAaAAgJUxOfSgCVAQAZAAYJXQQsHQAFAQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgAECgMJAwAAAA==.Vivien:BAAALgADCgYJBgABLgAECgEJAQAKAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAIkAAcJ6x9tCABYAgAkAAcJ6x9tCABYAgABLgAECgkJJgAaALUbAA==.',
Vo='Voidmayne:BAABLgAECn8/AAINAAkJjBGCQADmAQANAAkJjBGCQADmAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgUJDQAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.Voxella:BAAALgAECgQJBAAAAA==.',
Vr='Vrel:BAAALgADCgkJDgAAAA==.',
Vy='Vyv:BAABLgAECn8UAAILAAcJtAWxSQDcAAALAAcJtAWxSQDcAAAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAIVAAYJEhyzTQC+AQAVAAYJEhyzTQC+AQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Wayadra:BAABLgAECn8XAAQhAAkJkSEfBgDjAgAhAAkJkSEfBgDjAgAiAAcJSQTlJgDrAAATAAEJlgrESQAvAAAAAA==.',
We='Weiand:BAABLgAECn8uAAMNAAgJihzqOwD0AQANAAcJ9RvqOwD0AQAOAAEJOwfsegAzAAAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAACLgAFFH8FAAMCAAMJngdKkgBzAAACAAIJHAdKkgBzAAADAAEJoQi4HwBEAAAuAAQKfx8ABAIACAlBFPBFAPkBAAIACAlBFPBFAPkBAAMAAgnvD39XAGgAAAEAAQkAAA4xADwAAAAA.Wholemilk:BAABLgAECn8mAAIVAAgJ3x/lFQB3AgAVAAgJ3x/lFQB3AgAAAA==.',
Wi='Wilhellena:BAABLgAECn89AAIJAAkJYx6hBQABAwAJAAkJYx6hBQABAwAAAA==.Wilhellfu:BAAALgAECgIJBAAAAA==.Winariel:BAAALgAECgUJBwABLgAECggJJwAGALkeAA==.Wisteria:BAAALgAECgEJAQABLgABCgEJAQAKAAAAAA==.',
Wr='Wroughtsoul:BAAALgAECgEJAQAAAA==.Wrëckagë:BAAALgAECgcJEwAAAA==.',
Wu='Wumbo:BAAALgAECgYJBwAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAABLgAECn8kAAICAAkJOBKOOADfAQACAAkJOBKOOADfAQAAAA==.Xandir:BAABLgAECn83AAIMAAgJIRN1EgBzAQAMAAgJIRN1EgBzAQAAAA==.Xarhunt:BAAALgAECgUJAwAAAA==.Xaric:BAABLgAECn8iAAIEAAkJDxdJLgDJAQAEAAkJDxdJLgDJAQAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xy='Xyal:BAABLgAECn8lAAIJAAgJdSF6BwDTAgAJAAgJdSF6BwDTAgAAAA==.Xyp:BAAALgAECgEJAQABLgAECgcJGQAjAIcJAA==.',
Yg='Ygor:BAAALgAECgUJDwAAAA==.',
Yi='Yiago:BAAALgAECgQJCgAAAA==.',
Yo='Yobabydaddy:BAAALgAECgMJAwAAAA==.Youknow:BAAALgAECgQJBQAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.Yungslug:BAAALgAECgIJAgAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zany:BAAALgADCgIJAgAAAA==.Zaranorinn:BAABLgAECn8cAAINAAgJVgj1hwA/AQANAAgJVgj1hwA/AQAAAA==.Zaxhdk:BAEBLgAECn8tAAMPAAgJPRv3LgAgAgAPAAgJPRv3LgAgAgAWAAUJTwazOACDAAAAAA==.',
Ze='Zedex:BAAALgADCgcJCAABLgADCggJDQAKAAAAAA==.Zedru:BAAALgADCggJDQAAAA==.Zenstormer:BAAALgADCgQJBAABLgAECgIJAgAKAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zephyrion:BAAALgAECgQJBwAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAABLgAECn8VAAIPAAYJfx27dABUAQAPAAYJfx27dABUAQAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAABLgAECn8eAAIFAAgJZBk0JgD7AQAFAAgJZBk0JgD7AQAAAA==.Zinrar:BAABLgAECn8hAAIPAAgJeBnlOQD2AQAPAAgJeBnlOQD2AQAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8uAAIQAAcJlwhdoAAgAQAQAAcJlwhdoAAgAQAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAABLgAECn8rAAMZAAgJrBUeGQC4AQAZAAgJyBQeGQC4AQAaAAEJKRrK6ABBAAAAAA==.',
Zu='Zushi:BAAALgAECgUJBQAAAA==.',
['Äl']='Älphawolf:BAABLgAECn8eAAMjAAgJ2RbXIACUAQAjAAgJ2RbXIACUAQAEAAIJdggHrABGAAAAAA==.',
['Ðê']='Ðêmønicßløøð:BAABLgAECn8XAAIPAAgJWxSxSwC9AQAPAAgJWxSxSwC9AQAAAA==.',
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
