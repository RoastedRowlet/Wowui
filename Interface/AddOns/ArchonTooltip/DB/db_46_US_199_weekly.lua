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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Shaman-Restoration','DemonHunter-Vengeance','Priest-Discipline','Priest-Holy','Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Mage-Frost','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Warrior-Protection','DemonHunter-Devourer','DeathKnight-Blood','Mage-Fire','Shaman-Elemental','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','DemonHunter-Havoc','Druid-Feral','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aabbigale:BAAALgAECgkJBwAAAA==.',
Ab='Abigt:BAAALgAECgYJEQAAAA==.',
Ad='Adalaidê:BAAALgAECgUJBgAAAA==.',
Ae='Aelusion:BAABLgAECn8fAAQBAAgJSB88GgC3AgABAAgJgR48GgC3AgACAAMJWiEVLAAOAQADAAEJQCQiJwBVAAAAAA==.Aeluu:BAAALgAECgcJBwABLgAECggJHwAEALgRAA==.Aerola:BAAALgADCgEJAQAAAA==.Aerynne:BAAALgAECgMJDQAAAA==.',
Ai='Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn8tAAIFAAgJEw5cNQB/AQAFAAgJEw5cNQB/AQAAAA==.Aita:BAACLgAFFH8JAAIGAAMJaQleBgCXAAAGAAMJaQleBgCXAAAuAAQKfxwAAgYACAk4Ge4GAB0CAAYACAk4Ge4GAB0CAAAA.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJBQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Alisaa:BAAALgADCggJDgAAAA==.Allegria:BAAALgAECgEJAgAAAA==.Alondra:BAABLgAECn8fAAICAAkJvB/zAAC9AgACAAkJvB/zAAC9AgAAAA==.Alulà:BAABLgAECn8aAAMHAAcJWh4KDABZAgAHAAcJOR4KDABZAgAIAAMJMx4lTQAEAQAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.Aluuni:BAAALgAECgYJDwAAAA==.',
Am='Amo:BAAALgAECgIJAgABLgAECgUJCgAJAAAAAA==.',
An='Anaeli:BAABLgAECn84AAIFAAkJzBr7DwCBAgAFAAkJzBr7DwCBAgAAAA==.Anariel:BAAALgADCgUJBQABLgADCgcJDQAJAAAAAA==.Androth:BAABLgAECn8eAAMKAAgJMBl3CgDOAQAKAAcJJxx3CgDOAQALAAIJdwdjDwFMAAAAAA==.Angita:BAAALgAECgQJBwAAAA==.Antipæn:BAACLgAFFH8OAAMLAAMJChtRNQAIAQALAAMJChtRNQAIAQAMAAEJKiWjGQBpAAAuAAQKfz0AAwsACQkGJqUBAGgDAAsACQkGJqUBAGgDAAwABwmNIvcpAOIBAAAA.',
Ap='Apologia:BAABLgAECn8pAAILAAgJTCNVFACOAgALAAgJTCNVFACOAgAAAA==.',
Ar='Arcanix:BAAALgAECgcJBwAAAA==.Arceé:BAAALgAECgIJBAAAAA==.Archaic:BAABLgAECn8tAAINAAgJPxI8VwCXAQANAAgJPxI8VwCXAQAAAA==.Ardicelia:BAAALgAECgEJAQAAAA==.Ares:BAACLgAFFH8SAAMOAAUJOiARBwBfAQAOAAUJOiARBwBfAQAPAAIJCB71FgCuAAAuAAQKfyEAAw4ACAlTJOUBABoDAA4ACAnhI+UBABoDAA8ABwlHIjMZAIICAAAA.Ariellä:BAAALgADCgEJAQAAAA==.Arilynx:BAABLgAECn8iAAIQAAkJ4AdiEQBrAQAQAAkJ4AdiEQBrAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn8wAAIRAAkJSCPTAQANAwARAAkJSCPTAQANAwAAAA==.Aroviaa:BAABLgAECn8xAAIIAAgJqyCGBgDLAgAIAAgJqyCGBgDLAgAAAA==.Arpmek:BAABLgAECn8lAAISAAgJmxOZPQCHAQASAAgJmxOZPQCHAQAAAA==.Artemîs:BAAALgAECgQJBAAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Ashal:BAAALgAECgcJEwAAAA==.Astrotoad:BAAALgAECgMJAwAAAA==.Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgQJBQAAAA==.Aurtt:BAABLgAECn83AAITAAgJWhi7EgDgAQATAAgJWhi7EgDgAQAAAA==.',
Av='Avanel:BAAALgAECgEJAQAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Az='Azkadelia:BAAALgAECgEJAQAAAA==.',
Ba='Bageera:BAABLgAECn8hAAIEAAgJVhz7DwCRAgAEAAgJVhz7DwCRAgAAAA==.Bahahaknight:BAABLgAECn8tAAITAAgJQh2fCQDxAQATAAgJQh2fCQDxAQAAAA==.Barcy:BAAALgAECgEJAwAAAA==.Barnette:BAABLgAECn8/AAIUAAkJaxWSAQArAgAUAAkJaxWSAQArAgAAAA==.Barvi:BAAALgAECgEJAQABLgAECggJIgANAKYbAA==.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearmissile:BAAALgAECgQJBAAAAA==.Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn8tAAILAAgJAxvrMgDvAQALAAgJAxvrMgDvAQAAAA==.Berristan:BAABLgAECn8lAAMMAAkJ1BeiDAC1AgAMAAkJ1BeiDAC1AgALAAUJpAhKwAC5AAAAAA==.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigmarv:BAABLgAECn8eAAIVAAcJXRmRKQBOAQAVAAcJXRmRKQBOAQAAAA==.Bigsam:BAAALgAECgEJAQAAAA==.Bittytigs:BAAALgADCgUJBQAAAA==.',
Bl='Blossom:BAACLgAFFH8IAAIQAAUJ2QuyDgBJAQAQAAUJ2QuyDgBJAQAuAAQKfxUAAhAACAmdEY8YAM4BABAACAmdEY8YAM4BAAAA.Bluewitchpa:BAAALgAECgIJAgAAAA==.',
Bo='Boomboomkill:BAAALgADCgEJAQAAAA==.Bosc:BAAALgAECgkJCQABLgAECggJGQAWALMQAA==.Boudiicca:BAABLgAECn8ZAAIIAAQJmRKPNgDcAAAIAAQJmRKPNgDcAAAAAA==.Boxmasterr:BAABLgAECn8qAAMBAAgJqgzFVABhAQABAAgJNQzFVABhAQADAAcJrgfxEgDHAAAAAA==.',
Br='Brasmir:BAAALgAECgcJDwAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.Brianzero:BAAALgADCgEJAQAAAA==.Brinotriage:BAAALgAECgQJBAAAAA==.',
Bu='Bubblement:BAAALgAFFAUJDQAAAQ==.Bushalabong:BAAALgAECgMJBAAAAA==.Butherrface:BAAALgADCgQJBAAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgAAAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAACLgAFFH8KAAMXAAQJURyjBwBkAQAXAAQJBhujBwBkAQAYAAMJ3RyMKAAcAQAuAAQKfzYABBgACQl+I3oXAFACABgACAn9IXoXAFACABcACAm0HtQJAEMCABkABgmIF1YyAKUBAAAA.Cardran:BAAALgADCgEJAQABLgAECggJHgAKADAZAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAIMAAgJ3yHWBwDwAgAMAAgJ3yHWBwDwAgAAAA==.Catamay:BAABLgAECn8bAAISAAgJphvrJgDqAQASAAgJphvrJgDqAQABLgAECgEJAQAJAAAAAA==.Catprincess:BAABLgAECn8fAAIEAAgJuBF+OwC3AQAEAAgJuBF+OwC3AQAAAA==.Caylara:BAAALgAECgYJDAAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAAALgAECgUJCwAAAA==.',
Ch='Chai:BAAALgAECgYJDAAAAA==.Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAABLgAECn8eAAIWAAgJ8hJ2GgCWAQAWAAgJ8hJ2GgCWAQAAAA==.',
Ci='Cindrethal:BAAALgADCggJCAAAAA==.',
Cl='Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgAECgMJAwAAAA==.Clorox:BAAALgADCgEJAQAAAA==.',
Co='Coocoohead:BAAALgAECgMJBQAAAA==.Coralorchid:BAABLgAECn8eAAMKAAYJQRSwGQD5AAALAAYJSw88kAAIAQAKAAYJ9xGwGQD5AAAAAA==.Corrupt:BAAALgAECgEJAQAAAA==.',
Cp='Cptdarkk:BAABLgAECn8WAAILAAYJSgy7kgAEAQALAAYJSgy7kgAEAQAAAA==.',
Cr='Crytal:BAAALgADCgEJAgAAAA==.',
Cu='Cuddlebucket:BAAALgADCgQJBQAAAA==.Curissan:BAABLgAECn8VAAIVAAcJORVcJQBpAQAVAAcJORVcJQBpAQAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAABLgAECn8UAAIEAAgJAiErDgCoAgAEAAgJAiErDgCoAgAAAA==.',
['Cø']='Cøndemn:BAAALgAECgYJCAAAAA==.',
Da='Daemyn:BAAALgADCgcJBwAAAA==.Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAAALgAECgYJDQAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAcJGQAaAGgOAA==.Dalspin:BAACLgAFFH8ZAAIaAAcJaA7ACADUAQAaAAcJaA7ACADUAQAuAAQKfx8ABBoACQm4GtwHANkCABoACQm4GtwHANkCABsABwm8ElYqAIoBABYAAwkEAhxlAE4AAAAA.Dalthepal:BAABLgAECn8UAAIMAAcJXx+pHgAiAgAMAAcJXx+pHgAiAgABLgAFFAcJGQAaAGgOAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAACLgAFFH8NAAILAAMJQh89MAAZAQALAAMJQh89MAAZAQAuAAQKf0EAAgsACQknJVMCAFgDAAsACQknJVMCAFgDAAAA.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deathsaberss:BAABLgAECn8lAAIOAAkJPBRbDADPAQAOAAkJPBRbDADPAQAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgcJEAAAAA==.Debauch:BAABLgAECn8ZAAIBAAgJYA5WTwBwAQABAAgJYA5WTwBwAQAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Denniah:BAAALgAECgMJAwAAAA==.Derke:BAAALgAECgQJBwAAAA==.',
Di='Didudietho:BAAALgADCggJCAABLgAECggJMAALAPoZAA==.Diladrin:BAACLgAFFH8NAAIcAAMJBxJCCwC7AAAcAAMJBxJCCwC7AAAuAAQKf0AAAhwACQl1GgwFAGoCABwACQl1GgwFAGoCAAAA.Diode:BAACLgAFFH8YAAQdAAUJJRmuBQAnAQAdAAQJBBOuBQAnAQAeAAQJ1hSEPADtAAATAAEJAABkNAAAAAAuAAQKfy0AAx4ACAmHITUYAOoCAB4ACAncIDUYAOoCAB0ACAl1HA8FAPgBAAAA.',
Do='Doileag:BAAALgAECgYJEgAAAA==.Domer:BAAALgAECgYJCAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dora:BAAALgAECgMJAwAAAA==.Dottmatrix:BAAALgAECgYJEgAAAA==.',
Dr='Drachnia:BAAALgAECgQJBAAAAA==.Dragønbreath:BAACLgAFFH8IAAMNAAQJVAZpTQARAQANAAQJVAZpTQARAQAUAAEJaANsAwA/AAAuAAQKfx0AAxQACQlxGhcCAEoCABQACAnMFxcCAEoCAA0ACAk3FXOFADIBAAAA.Dreadwing:BAABLgAECn8WAAIeAAMJGgTQ3gByAAAeAAMJGgTQ3gByAAAAAA==.',
Du='Duf:BAACLgAFFH8aAAIWAAUJexJ8GQAYAQAWAAUJexJ8GQAYAQAuAAQKfy0AAhYACAksH1IRAIwCABYACAksH1IRAIwCAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn8xAAIIAAkJdh7UBAD3AgAIAAkJdh7UBAD3AgAAAA==.',
Dw='Dwagon:BAAALgAECggJEAAAAA==.',
['Dæ']='Dæmôn:BAAALgAECgYJCQAAAA==.',
['Dì']='Dìzzy:BAAALgAECgIJAgAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAABLgAECn8qAAMWAAgJARxPDwAKAgAWAAgJARxPDwAKAgAbAAIJpBghYACPAAAAAA==.Dûna:BAABLgAECn8eAAIfAAgJ5x8PCgBnAgAfAAgJ5x8PCgBnAgABLgAECggJKgAWAAEcAA==.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn83AAILAAgJqiMgFACPAgALAAgJqiMgFACPAgAAAA==.Elduar:BAAALgADCgEJAQAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAAALgAECgYJEQAAAA==.Ellaring:BAAALgAECgYJCAAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrric:BAABLgAECn8UAAIeAAcJ4w0jcAA8AQAeAAcJ4w0jcAA8AQAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAABLgAECn8gAAMFAAcJaCL/FwA3AgAFAAYJuiH/FwA3AgAVAAUJ1go/VwCHAAAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Eroviaa:BAAALgAECgQJBAABLgAECggJMQAIAKsgAA==.Erovvia:BAAALgAECgUJBgABLgAECggJMQAIAKsgAA==.',
Et='Etali:BAAALgAECgMJBAABLgAECggJJAAGAPoUAA==.',
Ez='Ezothen:BAABLgAECn8cAAMgAAgJsAP7PwDWAAAgAAgJXAP7PwDWAAAhAAQJawRpLwCdAAAAAA==.',
Fa='Faedoria:BAAALgAECgYJEAAAAA==.Faeryln:BAABLgAECn8iAAIIAAkJUQvWIAB3AQAIAAkJUQvWIAB3AQAAAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falkorr:BAAALgADCgEJAQABLgAECggJKQAiAD0bAA==.Falorie:BAAALgADCgYJEQAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAABLgAECn8lAAMQAAgJ/iDiBACQAgAQAAcJMSHiBACQAgAgAAEJBBuGYwBQAAAAAA==.Faustus:BAAALgADCgQJCgABLgAECggJJQAQAP4gAA==.',
Fe='Feature:BAAALgAECgkJBwAAAA==.Felstormer:BAAALgADCggJEAABLgAECgIJAgAJAAAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgQJBwAAAA==.Fireføx:BAAALgADCgEJAQAAAA==.Fisticuffs:BAAALgAECgIJAgAAAA==.Fizzllebang:BAABLgAECn8jAAICAAkJTRDXCABuAQACAAkJTRDXCABuAQAAAA==.',
Fl='Flamewhisker:BAAALgAECgQJBwAAAQ==.Flogginrenee:BAAALgAECgYJEwAAAA==.Floggsdaddy:BAAALgAECgYJEwAAAA==.Floke:BAAALgAECgMJBAAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fr='Fraublucher:BAABLgAECn8oAAIIAAgJHBUAFQDkAQAIAAgJHBUAFQDkAQAAAA==.Fredrik:BAAALgAFFAEJAgABLgAFFAQJDgANAL4GAA==.Frewyn:BAAALgAECgQJBgAAAA==.Frostimoth:BAABLgAECn8ZAAINAAcJ9BUQXgCGAQANAAcJ9BUQXgCGAQAAAA==.Frozty:BAAALgAECgYJDgAAAA==.',
Ga='Galandel:BAAALgAECgIJAgAAAA==.Galial:BAACLgAFFH8SAAIGAAUJIyEMAQB+AQAGAAUJIyEMAQB+AQAuAAQKfyIAAgYACQlaHzsBACIDAAYACQlaHzsBACIDAAAA.Gantar:BAAALgAFFAEJAgAAAA==.Garlicbread:BAAALgADCgYJBgABLgAFFAUJEgAGACMhAA==.Gaznol:BAABLgAECn8aAAIYAAgJriAJFABpAgAYAAgJriAJFABpAgAAAA==.',
Ge='Gelasera:BAAALgAECgQJBwAAAA==.',
Gh='Ghibli:BAAALgAECgcJEAAAAA==.',
Gl='Glaivethras:BAABLgAECn8iAAIGAAkJ7SEfAgCmAgAGAAkJ7SEfAgCmAgAAAA==.Glyphix:BAABLgAECn8XAAIPAAgJggkMLwBGAQAPAAgJggkMLwBGAQAAAA==.',
Gn='Gnarly:BAAALgAECgEJAQABLgAECgEJAQAJAAAAAA==.',
Go='Goochtrap:BAAALgADCgEJAQAAAA==.Gorgon:BAAALgAECgMJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAABLgAECn8bAAQXAAgJxgzvGQCHAQAXAAgJYAvvGQCHAQAYAAQJeQ4vgQDkAAAZAAQJXwUlaACeAAAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.Groot:BAAALgAECgUJCwABLgAECggJJAALAO4VAA==.Groovinchef:BAAALgAECgEJAQAAAA==.',
Gu='Gundunn:BAAALgADCgEJAQAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECgQJCgAJAAAAAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAEBLgAECn8dAAIfAAgJshALIAByAQAfAAgJshALIAByAQABLgAECgYJBwAJAAAAAA==.Hannebal:BAABLgAECn8aAAIMAAkJExHgGgDiAQAMAAkJExHgGgDiAQAAAA==.Havenfire:BAAALgADCgUJBQABLgADCgcJBgAJAAAAAA==.',
He='Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCggJEgAAAA==.Heydaw:BAAALgAECggJDgABLgAECgkJIAAeAHEgAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgADCgYJBgAAAA==.Holybeatdown:BAAALgADCgQJBQAAAA==.Holyrage:BAAALgADCgQJBAAAAA==.Holyßloodelf:BAAALgAECgQJBAABLgAECggJFwAeAFsUAA==.Honeysbadger:BAAALgAECgMJAwAAAA==.Hornet:BAABLgAECn8VAAMSAAgJZBA9SABgAQASAAgJ7g89SABgAQAjAAQJFwz3SADPAAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.Hotsauce:BAAALgAECgYJBgABLgAFFAYJGAANAJ4dAA==.',
Hu='Huasca:BAAALgAECgMJBQAAAA==.Humungous:BAAALgAECgcJDQAAAA==.Hunnybunz:BAAALgAECgYJDAAAAA==.',
['Hà']='Hàney:BAEALgAECgYJBwAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJEgAAAA==.',
['Hé']='Hélio:BAAALgADCgUJBQAAAA==.',
Ic='Icastfirebal:BAAALgAECgEJAQAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECggJDAAAAA==.',
Ig='Igotahitin:BAAALgADCgMJBgAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAABLgAECn8ZAAIWAAgJsxAeHwBxAQAWAAgJsxAeHwBxAQAAAA==.',
Il='Illida:BAAALgAECgMJAwAAAA==.',
Im='Imamalelol:BAAALgAECgYJDgAAAA==.',
In='Indira:BAAALgADCgcJDQAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAQJBwABLgAFFAUJCAAQANkLAQ==.Inumimi:BAABLgAECn8bAAIkAAgJyQRxGgDTAAAkAAgJyQRxGgDTAAAAAA==.Invincidemon:BAAALgAECgQJBAAAAA==.',
Ir='Irkenfox:BAECLgAFFH8WAAIRAAUJ8CLIBACUAQARAAUJ8CLIBACUAQAuAAQKfyUAAhEACAmhI54DABsDABEACAmhI54DABsDAAAA.',
It='Ithran:BAABLgAECn8iAAINAAkJKQypUACpAQANAAkJKQypUACpAQAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8qAAIUAAgJOB5iAQA+AgAUAAgJOB5iAQA+AgAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.Jama:BAAALgADCgcJCAAAAA==.James:BAACLgAFFH8OAAINAAQJvgYnSAAkAQANAAQJvgYnSAAkAQAuAAQKfzUAAg0ACAmdH3EaAIMCAA0ACAmdH3EaAIMCAAAA.Janderick:BAABLgAECn8aAAIPAAcJ1yDLFwDkAQAPAAcJ1yDLFwDkAQAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jellacee:BAABLgAECn8aAAMjAAUJeREtMgCYAAAjAAUJeREtMgCYAAASAAIJHgML1gAyAAAAAA==.Jesterjoe:BAAALgAECgQJCAAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8YAAICAAUJ7SMuAgBoAQACAAUJ7SMuAgBoAQAuAAQKfy0AAgIACAk2JfQAAC8DAAIACAk2JfQAAC8DAAAA.Jimi:BAAALgADCgUJBQAAAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJBAABLgAFFAEJAgAJAAAAAA==.',
Jo='Joejitsu:BAAALgAECgMJAwAAAA==.Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAABLgAECn8ZAAQCAAcJLRx4DAApAQACAAUJjBp4DAApAQABAAMJMhmBkwDYAAADAAEJXCB1KgBKAAAAAA==.Joltraxi:BAAALgAECgMJBAAAAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJEwABLgAFFAEJAgAJAAAAAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCQAAAA==.Juicethevoid:BAABLgAECn8mAAISAAgJWwerZwAGAQASAAgJWwerZwAGAQAAAA==.Juniornite:BAABLgAECn80AAINAAkJSSDyCwDqAgANAAkJSSDyCwDqAgAAAA==.Justicus:BAAALgAECgUJEAABLgAECgkJJAAYALUbAA==.Justthetouch:BAAALgAECggJCQAAAA==.',
['Jü']='Jüst:BAAALgAECgMJAwAAAA==.',
Ka='Kaeldrin:BAAALgADCgkJFAAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAABLgAECn8kAAMGAAgJ+hTYCQB3AQAGAAcJVhXYCQB3AQASAAgJrw5nSwBWAQAAAA==.Kaiser:BAAALgAECgQJCQAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgQJBwAAAA==.Kalzod:BAACLgAFFH8NAAIBAAMJnB4oQAAKAQABAAMJnB4oQAAKAQAuAAQKfzsAAwEACQlKJugAAHoDAAEACQlKJugAAHoDAAMAAQkAAB0kAGEAAAAA.Kariana:BAAALgAECgYJDgAAAA==.Kataki:BAAALgAECgEJAQABLgAECggJJAAGAPoUAA==.Katett:BAAALgAECgcJDgAAAA==.Kativeria:BAAALgAECgQJBwAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDwABLgAECgYJDgAJAAAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgYJEQAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Kerfufle:BAAALgAECgEJAQAAAA==.Keyn:BAAALgADCgEJAQAAAA==.Keynstolor:BAABLgAECn8aAAIYAAcJuxthWABBAQAYAAcJuxthWABBAQAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.Khálifá:BAAALgAECgUJBgAAAA==.',
Ki='Kicker:BAAALgAECgYJDgAAAA==.Killmora:BAAALgAECgIJAgAAAA==.Kippars:BAABLgAECn8aAAMcAAcJBRTyGgD4AAAcAAYJuhPyGgD4AAAkAAEJfRX2LgBBAAAAAA==.Kiritsugo:BAAALgADCgUJDQAAAA==.Kissame:BAAALgAECgYJBgAAAA==.',
Ko='Kodazoff:BAABLgAECn8jAAMgAAkJxRApGQC/AQAgAAkJxRApGQC/AQAQAAIJIQeKLwAzAAAAAA==.Korevash:BAABLgAECn8dAAIlAAcJVBy4CQC8AQAlAAcJVBy4CQC8AQABLgAFFAMJDQAHAAkUAA==.Korupta:BAABLgAECn8uAAMSAAgJGxB6SQBdAQASAAgJGxB6SQBdAQAjAAUJ3A36PQAFAQABLgAECgkJKAAPABAUAA==.Korzilius:BAAALgAECgcJDAAAAA==.',
Kr='Krissylu:BAAALgAECgYJEwAAAA==.Krockett:BAAALgAECgMJAwAAAA==.Krothix:BAABLgAECn8qAAIVAAkJygpLJgBiAQAVAAkJygpLJgBiAQAAAA==.Kruvix:BAAALgAECgYJCgAAAA==.Kryjag:BAAALgADCggJCAAAAA==.Krynir:BAAALgADCgkJDgAAAA==.Kryshym:BAAALgAECgYJBgAAAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAAALgAECgUJDgAAAA==.',
['Kü']='Kürömë:BAAALgADCgMJAwAAAA==.',
La='Ladara:BAABLgAECn8tAAIDAAkJ8BD2BQC5AQADAAkJ8BD2BQC5AQAAAA==.Laima:BAAALgADCgUJDQAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAQAAAA==.Lavitz:BAAALgAECgMJAwAAAA==.',
Le='Leheo:BAAALgAECgQJBgAAAA==.Lehua:BAAALgADCggJDAAAAA==.Leilanii:BAAALgAECgIJAgAAAA==.Lemook:BAAALgAECgQJBAAAAA==.Leonìdas:BAAALgAECgQJBgAAAA==.',
Lh='Lhei:BAAALgAECgQJBgAAAA==.',
Li='Lightstormer:BAAALgAECgIJAgAAAA==.Lilamae:BAAALgAECgYJBgAAAA==.Lilarielle:BAABLgAECn8mAAIkAAgJUAd7GADoAAAkAAgJUAd7GADoAAAAAA==.Lildash:BAAALgADCgIJAgABLgAECggJHgAKADAZAA==.Lilface:BAAALgAECgYJCgAAAA==.Liliela:BAAALgAECgQJBAABLgAECggJHgAKADAZAA==.Lilsham:BAAALgAECgQJBAABLgAECggJHgAKADAZAA==.Lilyannah:BAAALgAECgkJAQAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgEJAQAJAAAAAA==.Liø:BAAALgAECgEJAQAAAA==.',
Lo='Lokir:BAAALgAECgMJBgAAAA==.Lotheovian:BAEALgAECgIJAgABLgAECggJIQAeAGkYAA==.Lowchin:BAAALgAECgYJCgAAAA==.',
Lu='Lumia:BAABLgAECn8dAAMfAAkJix4wEwBcAgAfAAcJlB8wEwBcAgAIAAYJFBjVSgANAQAAAA==.Lutherion:BAAALgAECgUJBwAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgAECgEJAQAAAA==.Mackshiesty:BAAALgAECgYJEQAAAA==.Macoun:BAABLgAECn8iAAMYAAkJSyQsAwAwAwAYAAkJSyQsAwAwAwAZAAYJEhv0QABVAQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn8yAAINAAgJASasCwDtAgANAAgJASasCwDtAgAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAAALgAECgYJEAAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBgAJAAAAAA==.Martei:BAACLgAFFH8VAAIkAAUJABVoAwBhAQAkAAUJABVoAwBhAQAuAAQKfy0AAiQACAmUI0ICAC8DACQACAmUI0ICAC8DAAAA.Maríneth:BAAALgAECgQJCgAAAA==.Mathías:BAABLgAECn8iAAIYAAkJOxfdJgD1AQAYAAkJOxfdJgD1AQAAAA==.',
Me='Meadowfrey:BAAALgAECgEJAQAAAA==.Meowbae:BAABLgAECn8mAAMkAAgJXxGxDACOAQAkAAgJXxGxDACOAQAiAAEJNAEGewAYAAAAAA==.Mercesdes:BAAALgAECgQJBAAAAA==.Mercina:BAAALgAECgEJAwAAAA==.Mercuros:BAAALgAECggJCQAAAA==.Merknlock:BAAALgAECgEJAQAAAA==.',
Mi='Midnyte:BAABLgAECn81AAMbAAkJtxqkDgASAgAbAAgJchukDgASAgAaAAYJWA4eTQCbAAAAAA==.Milkyweí:BAAALgAECgMJAwAAAA==.Mini:BAAALgADCgUJBQABLgAECggJIgANAKYbAA==.Minizee:BAAALgAECgEJAQAAAA==.Mirabella:BAAALgAECgQJBgABLgAECgkJJwAaAAAiAA==.Mirokushan:BAAALgAECgMJDAABLgAECgQJDwAJAAAAAA==.Mistfit:BAAALgAECgIJAgAAAA==.Misticlady:BAAALgADCgEJAQAAAA==.Mistrariel:BAABLgAECn8bAAIGAAgJihtwBAAmAgAGAAgJihtwBAAmAgAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Moostafa:BAAALgAECgMJAwAAAA==.Mordemour:BAAALgAECgUJBwAAAA==.',
Mu='Mungo:BAABLgAECn8kAAINAAgJpBTHRwDCAQANAAgJpBTHRwDCAQAAAA==.',
My='My:BAAALgAECgYJAwAAAA==.Mynkie:BAACLgAFFH8LAAIaAAMJPA31HwC6AAAaAAMJPA31HwC6AAAuAAQKfysAAhoACQluHjkFAAMDABoACQluHjkFAAMDAAAA.Mythreashis:BAAALgADCgMJAwAAAA==.',
['Mä']='Mägi:BAAALgAECgEJAQAAAA==.',
['Må']='Mååt:BAAALgADCgIJAgAAAA==.',
['Mæ']='Mæstra:BAAALgADCgEJAQAAAA==.',
['Më']='Mëlony:BAAALgADCgIJAgAAAA==.',
Na='Nachtmar:BAAALgAECgQJCQAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8YAAISAAUJaRZQJQA2AQASAAUJaRZQJQA2AQAuAAQKfyoAAhIACAlCHDciAAQCABIACAlCHDciAAQCAAAA.',
Ne='Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nikkitta:BAAALgADCgMJAwAAAA==.Nimravidae:BAABLgAECn8sAAMMAAgJCxeoFgAKAgAMAAgJCxeoFgAKAgALAAYJkg08jQANAQAAAA==.Ninelives:BAABLgAECn8gAAIiAAgJsgIPQgCvAAAiAAgJsgIPQgCvAAAAAA==.Nitecrawler:BAABLgAECn8XAAINAAcJ1A6veABLAQANAAcJ1A6veABLAQAAAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAABLgAECn8ZAAIgAAcJEAvmNAAIAQAgAAcJEAvmNAAIAQAAAA==.Noxium:BAAALgAECgYJDQAAAA==.Noxolon:BAABLgAECn8nAAIPAAgJbhtPFAAFAgAPAAgJbhtPFAAFAgAAAA==.',
Nr='Nreaf:BAABLgAECn8uAAMLAAgJyRy9JACUAgALAAgJyRy9JACUAgAKAAQJxhYfJQDfAAAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgQJBgAAAA==.Nysca:BAAALgADCgcJBwAAAA==.',
Ob='Obijuan:BAAALgAECgMJAwAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAAALgAECgUJCwAAAA==.',
Or='Ornstein:BAAALgAECgYJEQAAAA==.',
Ot='Ottuk:BAACLgAFFH8SAAMeAAUJpxWvMAD8AAAeAAQJpxWvMAD8AAATAAEJAAAAAAAAAAAuAAQKfyEAAx4ACQnVIa8IAFgDAB4ACQnVIa8IAFgDABMAAwlnHX0nAAMBAAAA.',
Pa='Paksenarrion:BAABLgAECn8tAAIKAAgJKRGAEABmAQAKAAgJKRGAEABmAQAAAA==.Pancham:BAAALgADCgUJBQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECggJEAAAAA==.Pandemônium:BAAALgAECggJDgAAAA==.Pandemönium:BAAALgAECgIJAQAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Pandèmonium:BAAALgAECgYJBgAAAA==.Patchington:BAAALgAECgQJCgAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Perck:BAAALgAECgMJAwAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAFFAIJAwAJAAAAAA==.Pezvoker:BAAALgAFFAIJAwAAAA==.',
Pi='Pienarri:BAAALgAECgEJAgAAAA==.Pixelme:BAAALgAECgMJBQAAAA==.',
Pl='Pleggster:BAABLgAECn8YAAMFAAcJrA/TOwBgAQAFAAcJrA/TOwBgAQAVAAEJiAFeigAcAAAAAA==.',
Po='Pochula:BAABLgAECn8kAAIEAAgJahVfIAD/AQAEAAgJahVfIAD/AQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAABLgAECn8jAAIMAAgJQhHeNwCbAQAMAAgJQhHeNwCbAQAAAA==.Protricity:BAABLgAECn84AAMfAAkJcyAGBQDSAgAfAAkJcyAGBQDSAgAIAAEJ2AJchAAtAAAAAA==.',
Pu='Pumpernickel:BAAALgADCgUJBQABLgAFFAUJEgAGACMhAA==.',
Py='Pyrellyn:BAAALgADCggJCgAAAA==.',
['Pä']='Pändamönium:BAAALgAECggJDgAAAA==.',
['Pæ']='Pæn:BAACLgAFFH8GAAIeAAIJNCbPeQB1AAAeAAIJNCbPeQB1AAAuAAQKfyMAAx4ABwkPJJEwAPcBAB4ABgn+JJEwAPcBABMABwmPHw8PAJwBAAEuAAUUAwkOAAsAChsA.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgQJBwABLgAECgYJCwAJAAAAAA==.Quantar:BAAALgAECgYJCwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rancooll:BAAALgAECgIJAgAAAA==.Rasniir:BAABLgAECn8wAAIEAAgJGyDXCQDiAgAEAAgJGyDXCQDiAgAAAA==.Ravenlash:BAAALgAECgEJBAAAAA==.',
Re='Regna:BAACLgAFFH8YAAIPAAUJtSYDAwDAAQAPAAUJtSYDAwDAAQAuAAQKfy4AAg8ACAmGJhgDAH8DAA8ACAmGJhgDAH8DAAAA.Regner:BAAALgAECgEJAQAAAA==.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAABLgAECn8UAAITAAYJnw0vIQDjAAATAAYJnw0vIQDjAAAAAA==.Remaked:BAACLgAFFH8kAAIWAAYJmR18AwCpAQAWAAYJmR18AwCpAQAuAAQKfz4AAhYACQmrI1ICABEDABYACQmrI1ICABEDAAAA.Remilia:BAABLgAECn8lAAIfAAcJch0jEgD1AQAfAAcJch0jEgD1AQAAAA==.Requinix:BAABLgAECn8yAAIYAAkJSRdeHgAjAgAYAAkJSRdeHgAjAgAAAA==.Retro:BAAALgAECgEJAQAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAECggJBwAAAA==.Revwrinkle:BAAALgAECgIJAwAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgUJDgAAAA==.Ricochet:BAABLgAECn8cAAIXAAgJZRG0FQCvAQAXAAgJZRG0FQCvAQAAAA==.Riptidez:BAAALgADCgcJBgAAAA==.Ririko:BAABLgAECn8tAAIIAAgJuw5qIAB6AQAIAAgJuw5qIAB6AQAAAA==.Ritzo:BAABLgAECn8jAAIPAAgJ7xPAHgCrAQAPAAgJ7xPAHgCrAQAAAA==.Rizzla:BAAALgAECgIJAgABLgAECggJKQAiAD0bAA==.',
Ro='Rockllobster:BAAALgAECgYJBAABLgAECgYJCAAJAAAAAA==.Rocksanne:BAAALgADCgcJEAAAAA==.Roguebâit:BAABLgAECn81AAQDAAkJ2RonBAD7AQADAAcJzxonBAD7AQABAAYJMBdpTQB1AQACAAMJJw3SRACiAAAAAA==.Ronen:BAAALgAECgMJAwAAAA==.',
Ru='Rubywolf:BAAALgAECgYJCQABLgAECggJGwAiALAWAA==.Rukkis:BAABLgAECn8eAAMmAAcJahq0EQDIAQAmAAcJahq0EQDIAQAnAAEJjQn9GQAvAAAAAA==.Rumi:BAACLgAFFH8KAAIGAAMJaBliBADWAAAGAAMJaBliBADWAAAuAAQKf0AAAwYACQmfJHkAADsDAAYACQmfJHkAADsDACMAAQlvEYxHADsAAAAA.',
Ry='Ryeekan:BAABLgAECn8cAAIYAAgJ/xIiNwCvAQAYAAgJ/xIiNwCvAQAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAABLgAECn8kAAILAAgJ7hWSWQB4AQALAAgJ7hWSWQB4AQAAAA==.Saelena:BAAALgADCgEJAQAAAA==.Sakheddala:BAAALgAECgMJAwAAAA==.Sancha:BAAALgADCgQJBAAAAA==.Sanosagara:BAABLgAECn8rAAIaAAgJHRfkFgDyAQAaAAgJHRfkFgDyAQAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgAECgIJAwAAAA==.Sarithon:BAAALgADCgMJAwAAAA==.Saru:BAAALgADCgkJDQAAAA==.Saruta:BAACLgAFFH8PAAMPAAQJfxAmGAAbAQAPAAQJfxAmGAAbAQAOAAEJdQNOJgA7AAAuAAQKfx8AAw8ACAmGGvErAAUCAA8ABwm/HPErAAUCAA4ABQmqDwoWAE4BAAAA.Sath:BAAALgADCgQJBAAAAA==.Sathari:BAABLgAECn8nAAISAAgJQRXfPgCCAQASAAgJQRXfPgCCAQAAAA==.Satsuki:BAAALgAECgcJEwABLgAFFAMJDQASAFcdAA==.',
Sc='Scarycat:BAAALgADCgYJBgAAAA==.Schaden:BAAALgAECgEJAQABLgAECggJFAAEAAIhAA==.',
Se='Seijo:BAAALgAECgMJAwAAAA==.Sekk:BAABLgAECn86AAILAAkJMBxCFQCHAgALAAkJMBxCFQCHAgAAAA==.Selexi:BAAALgADCgYJEAAAAA==.Sereya:BAAALgADCgQJBAABLgADCgcJBgAJAAAAAA==.Sesshanmaru:BAAALgADCgEJAQAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAABLgAECn8xAAIjAAcJQB6/DAD5AQAjAAcJQB6/DAD5AQAAAA==.Shadoshiftt:BAABLgAECn8eAAMiAAgJdgkIQQC0AAAiAAYJKQcIQQC0AAAEAAgJGALwlwCeAAAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgAECgIJAgAAAA==.Shamzee:BAACLgAFFH8IAAMFAAMJpA/bLwDFAAAFAAMJpA/bLwDFAAAVAAEJrQKyOAA/AAAuAAQKfyUAAgUACAnYGbAYADICAAUACAnYGbAYADICAAAA.Shandalf:BAAALgAECgQJDwAAAA==.Shintok:BAAALgAECgQJBAAAAA==.Shuddarun:BAACLgAFFH8ZAAIYAAUJiyKiAwBkAQAYAAUJiyKiAwBkAQAuAAQKfyoAAhgACAmXJcUDAFQDABgACAmXJcUDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgADCgcJDQAJAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simn:BAABLgAECn8XAAIYAAcJzR29MwC9AQAYAAcJzR29MwC9AQAAAA==.Sindraesong:BAAALgAECggJEgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgAECgIJBAAAAA==.',
Sk='Skrai:BAAALgAECgYJCgABLgAECggJGAARAGAdAA==.',
Sl='Slayvylora:BAACLgAFFH8WAAILAAUJwRPPDQA8AQALAAUJwRPPDQA8AQAuAAQKfy8AAwsACAmjI0gVAIcCAAsACAmjI0gVAIcCAAwABQmWB29uAMEAAAAA.Sleep:BAAALgAECgQJBAABLgAFFAMJCAAoAMwTAA==.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgAECgIJBAAAAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Sneakymoth:BAAALgAECgYJEwABLgAECgcJGQANAPQVAA==.Sniff:BAABLgAECn8iAAINAAgJphvjNAAFAgANAAgJphvjNAAFAgAAAA==.Snookums:BAABLgAECn80AAISAAcJsRnKNACqAQASAAcJsRnKNACqAQAAAA==.',
So='Soulomon:BAABLgAECn8UAAIBAAgJqhMwgwBUAQABAAgJqhMwgwBUAQAAAA==.Soulsarisen:BAAALgAECgYJDwAAAA==.',
Sp='Spanki:BAAALgADCgkJEAAAAA==.Spellteaser:BAABLgAECn8UAAINAAYJOhkguQBvAQANAAYJOhkguQBvAQAAAA==.Spicymaker:BAABLgAECn8iAAIOAAgJCSCzBQBeAgAOAAgJCSCzBQBeAgAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJCgAAAA==.Steelheart:BAAALgAECgEJBQAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Stolensøul:BAAALgADCgkJDgAAAA==.Strifewood:BAABLgAECn8VAAITAAgJzRjHEwBfAQATAAgJzRjHEwBfAQAAAA==.Stumper:BAABLgAECn8pAAIiAAgJPRsIEAAQAgAiAAgJPRsIEAAQAgAAAA==.',
Su='Sugondese:BAAALgAECgQJBgAAAA==.Suluna:BAAALgAECgUJBQABLgAECgkJOAAFAMwaAA==.Summêr:BAAALgAECgYJEQAAAA==.Suri:BAAALgAECgUJCgAAAA==.Sux:BAABLgAECn8YAAIcAAcJJA6YHwDQAAAcAAcJJA6YHwDQAAAAAA==.',
Sy='Sybrina:BAABLgAECn8VAAIYAAYJhhWhVABMAQAYAAYJhhWhVABMAQAAAA==.Sylvia:BAAALgADCgcJBgAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAABLgAECn8jAAIYAAYJdQgYfwDhAAAYAAYJdQgYfwDhAAAAAA==.Synèsterwolf:BAAALgAECgIJAwABLgAECggJGwAiALAWAA==.',
['Sí']='Síf:BAAALgAECgYJCAAAAA==.',
Ta='Tabernacle:BAAALgAECgUJBQAAAA==.Tamamò:BAABLgAECn8WAAIaAAcJ1BGPKABvAQAaAAcJ1BGPKABvAQAAAA==.Tarrok:BAAALgADCgMJBwAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAAALgAECgIJAgAAAA==.Tepache:BAAALgADCgEJAQAAAA==.Tequitos:BAABLgAECn8WAAMMAAgJSQ0aXwAAAQAMAAcJugkaXwAAAQALAAYJnwtEmAD6AAAAAA==.Teranin:BAABLgAECn8UAAIiAAcJPAh3NwDeAAAiAAcJPAh3NwDeAAAAAA==.',
Tf='Tfortyone:BAAALgAECgQJBwAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgIJAgAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAACLgAFFH8LAAINAAMJYiKbRAAvAQANAAMJYiKbRAAvAQAuAAQKf0AAAg0ACQlBJWsDAFkDAA0ACQlBJWsDAFkDAAAA.',
Ti='Tiren:BAAALgAECgYJDQAAAA==.',
To='Torag:BAAALgAECgQJBAAAAA==.Torment:BAABLgAECn86AAITAAkJkBkGCQD8AQATAAkJkBkGCQD8AQAAAA==.',
Tr='Trepania:BAACLgAFFH8TAAIIAAUJZgqUCgBCAQAIAAUJZgqUCgBCAQAuAAQKfywAAggACAkMGtEWACUCAAgACAkMGtEWACUCAAAA.Tristén:BAAALgAECgQJBgAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Trollycarp:BAABLgAECn8bAAMKAAgJkgrpHwC/AAALAAgJbQOnowDnAAAKAAUJdhDpHwC/AAAAAA==.Truvie:BAAALgADCgkJEQAAAA==.',
Tu='Tumbler:BAABLgAECn8XAAMFAAgJix1IEAB+AgAFAAgJix1IEAB+AgAVAAMJCBH8UgCWAAAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAABLgAECn8lAAMFAAYJdAxFVQD5AAAFAAYJdAxFVQD5AAAVAAEJ+ARihgAiAAAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAABLgAECn8iAAIXAAgJ/hFsFAC8AQAXAAgJ/hFsFAC8AQAAAA==.',
Ul='Ulnuk:BAACLgAFFH8MAAIFAAQJZRVYHQAaAQAFAAQJZRVYHQAaAQAuAAQKfygAAgUACAmhIMUNAJkCAAUACAmhIMUNAJkCAAAA.Ulster:BAAALgAECgEJAQAAAA==.',
Un='Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAAJAAAAAA==.',
Va='Vadka:BAAALgAECgQJCgAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAAALgAECgQJCgAAAA==.Vairian:BAABLgAECn8YAAIjAAYJjxBhIQAHAQAjAAYJjxBhIQAHAQAAAA==.Valkree:BAAALgAECgMJAwAAAA==.Valsavis:BAABLgAECn83AAIGAAgJ0hyxBAAcAgAGAAgJ0hyxBAAcAgAAAA==.Vampirä:BAABLgAECn8gAAQEAAgJEghEiQDCAAAEAAYJUwREiQDCAAAkAAQJlQXfIwCAAAAiAAIJrgNiYgBAAAAAAA==.Varactor:BAAALgAECgMJAwAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAIbAAgJ7iA1CAD3AgAbAAgJ7iA1CAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgQJBwAAAA==.Vernice:BAAALgAECgEJAQABLgAECgUJBwAJAAAAAA==.Verulan:BAAALgAECgYJEgAAAA==.Vexeh:BAAALgAECgMJBAAAAA==.Vexomous:BAAALgAECgUJDwAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vikss:BAABLgAECn8dAAMYAAgJlRCBSwBnAQAYAAgJlRCBSwBnAQAXAAYJXQQsHQAFAQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgAECgMJAwAAAA==.Vivien:BAAALgADCgYJBgABLgADCgcJBgAJAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAIkAAcJ6x9tCABYAgAkAAcJ6x9tCABYAgABLgAECgkJJAAYALUbAA==.',
Vo='Voidmayne:BAABLgAECn81AAILAAgJyQ+LWwBzAQALAAgJyQ+LWwBzAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgUJCAAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.Voxella:BAAALgAECgMJAwAAAA==.',
Vr='Vrel:BAAALgADCggJBwAAAA==.',
Vy='Vyv:BAABLgAECn8UAAIVAAcJswWDPwDeAAAVAAcJswWDPwDeAAAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAISAAYJEhw/TABUAQASAAYJEhw/TABUAQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Wayadra:BAABLgAECn8XAAQgAAkJjyHLBADmAgAgAAkJjyHLBADmAgAhAAcJSQTlJgDrAAAQAAEJlgrESQAvAAAAAA==.',
We='Weiand:BAABLgAECn8iAAMLAAgJzRnXRACxAQALAAcJxRjXRACxAQAMAAEJNwenbwAzAAAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAACLgAFFH8FAAMBAAMJngffgAB3AAABAAIJHAffgAB3AAACAAEJoQiQGwBEAAAuAAQKfx8ABAEACAk8FPBFAPkBAAEACAk8FPBFAPkBAAIAAgnvD39XAGgAAAMAAQkAAA4xADwAAAAA.Wholemilk:BAABLgAECn8eAAISAAgJ3ByTHAAnAgASAAgJ3ByTHAAnAgAAAA==.',
Wi='Wilhellena:BAABLgAECn8zAAIIAAgJLiHtBQDbAgAIAAgJLiHtBQDbAgAAAA==.Wilhellfu:BAAALgAECgIJBAAAAA==.Winariel:BAAALgAECgUJBwABLgAECggJGwAGAIobAA==.Wisteria:BAAALgAECgEJAQABLgABCgEJAQAJAAAAAA==.',
Wr='Wroughtsoul:BAAALgAECgEJAQAAAA==.Wrëckagë:BAAALgAECgcJEwAAAA==.',
Wu='Wumbo:BAAALgAECgYJBwAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAABLgAECn8jAAIBAAgJHxPjQQCZAQABAAgJHxPjQQCZAQABLgAECgkJKAAPABAUAA==.Xandir:BAABLgAECn8rAAIKAAgJHBDrEwA4AQAKAAgJHBDrEwA4AQAAAA==.Xarhunt:BAAALgAECgQJAwAAAA==.Xaric:BAABLgAECn8iAAIEAAkJDxeXKADIAQAEAAkJDxeXKADIAQAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xy='Xyal:BAABLgAECn8YAAIIAAcJ2x9ZDABXAgAIAAcJ2x9ZDABXAgAAAA==.Xyp:BAAALgAECgEJAQABLgAECgYJEgAJAAAAAA==.',
Yg='Ygor:BAAALgAECgEJAgAAAA==.',
Yi='Yiago:BAAALgAECgQJCgAAAA==.',
Yo='Yobabydaddy:BAAALgAECgMJAwAAAA==.Youknow:BAAALgAECgIJAwAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zany:BAAALgADCgIJAgAAAA==.Zaranorinn:BAABLgAECn8YAAILAAcJ4QcGjwAKAQALAAcJ4QcGjwAKAQAAAA==.Zaxhdk:BAEBLgAECn8hAAMeAAgJaRgfMQD1AQAeAAgJaRgfMQD1AQATAAUJTwZXLwCJAAAAAA==.',
Ze='Zedex:BAAALgADCgcJCAABLgADCggJDQAJAAAAAA==.Zedru:BAAALgADCggJDQAAAA==.Zenstormer:BAAALgADCgQJBAABLgAECgIJAgAJAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zephyrion:BAAALgAECgEJAwAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAABLgAECn8VAAIeAAYJfx0/XwBkAQAeAAYJfx0/XwBkAQAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAABLgAECn8cAAIFAAgJZBnkHgABAgAFAAgJZBnkHgABAgAAAA==.Zinrar:BAABLgAECn8dAAIeAAcJtxicUQCJAQAeAAcJtxicUQCJAQAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8mAAINAAcJ0QUfmwALAQANAAcJ0QUfmwALAQAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAABLgAECn8hAAMXAAgJYxRiFwCfAQAXAAgJfhNiFwCfAQAYAAEJKRogygBFAAAAAA==.',
Zu='Zushi:BAAALgAECgEJAQAAAA==.',
['Äl']='Älphawolf:BAABLgAECn8bAAMiAAgJsBZlHQCFAQAiAAgJsBZlHQCFAQAEAAIJdgg+nABGAAAAAA==.',
['Ðê']='Ðêmønicßløøð:BAABLgAECn8XAAIeAAgJWxQwQAC+AQAeAAgJWxQwQAC+AQAAAA==.',
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
