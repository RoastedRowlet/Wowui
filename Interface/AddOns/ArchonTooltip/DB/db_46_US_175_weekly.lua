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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Warrior-Fury','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Druid-Guardian','Druid-Restoration','Shaman-Restoration','Shaman-Enhancement','Druid-Balance','Shaman-Elemental','Evoker-Preservation','Hunter-Survival','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Frost','Unknown-Unknown','Priest-Discipline','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Druid-Feral','Warrior-Protection','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aarkein:BAAALgAECgYJBgAAAA==.',
Ab='Abiotic:BAAALgAECgEJAwAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ac='Acesup:BAAALgAFFAEJAQAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.Aesir:BAAALgADCgYJCAAAAA==.',
Ai='Aings:BAACLgAFFH8FAAIBAAIJqyTRqwDFAAABAAIJqyTRqwDFAAAuAAQKfy0AAgEACQnLIiwSANsCAAEACQnLIiwSANsCAAAA.',
Al='Alarus:BAAALgAECgMJAwAAAA==.Alejandro:BAAALgADCggJCAAAAA==.Aletaa:BAAALgAECgcJAQABLgAFFAUJDQACADAQAA==.Alex:BAABLgAECn83AAIDAAkJJh4nFQCXAgADAAkJJh4nFQCXAgAAAA==.Alivathor:BAAALgAECgYJCgABLgAECgYJFgAEAMgKAA==.Allypally:BAABLgAECn8bAAIFAAkJig3QiwBXAQAFAAkJig3QiwBXAQAAAA==.Althir:BAABLgAECn8rAAICAAkJBSDsJQDbAgACAAkJBSDsJQDbAgAAAA==.Althorian:BAAALgAECgQJAgAAAA==.',
Am='Amgrod:BAEBLgAECn8oAAIGAAkJmQn7MACIAQAGAAkJmQn7MACIAQAAAA==.Amythest:BAAALgADCgkJDwAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCggJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8eAAIFAAcJ5hjDdwB8AQAFAAcJ5hjDdwB8AQAAAA==.',
Ar='Arfas:BAAALgAECggJDgABLgAECggJIwAHAP4eAA==.Arkhitype:BAABLgAECn9BAAQIAAkJJx5KAgC7AgAIAAkJJx5KAgC7AgAJAAYJuQ+xMACBAQAKAAEJGQbPKAAgAAAAAA==.Armak:BAAALgADCgEJAgAAAA==.Arwenibria:BAAALgAECgEJAQAAAA==.',
As='Ashdritha:BAAALgAECgEJAQAAAA==.Ashya:BAAALgADCgYJBgAAAA==.Asur:BAABLgAECn80AAMFAAgJ6RLQaACbAQAFAAgJ6RLQaACbAQALAAUJkgN5PgBgAAAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Auracorusca:BAABLgAECn8jAAIMAAkJeiS+AgB5AwAMAAkJeiS+AgB5AwAAAA==.Auris:BAAALgADCgQJBwAAAA==.',
Ay='Aynilith:BAAALgAECgYJCAAAAA==.Aystarael:BAAALgAECgkJBgAAAA==.',
Ba='Bajr:BAABLgAECn8qAAINAAkJjg7ZUQCpAQANAAkJjg7ZUQCpAQAAAA==.Bakura:BAABLgAECn8iAAIOAAkJzhxkBAA5AgAOAAkJzhxkBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8hAAIDAAkJORP5UACPAQADAAkJORP5UACPAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.Barudd:BAAALgADCgEJAQAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAACLgAFFH8IAAIPAAMJNR7tAQD1AAAPAAMJNR7tAQD1AAAuAAQKf0wAAw8ACQk0JGMAACEDAA8ACQk0JGMAACEDAAIAAQlcEPRPATYAAAAA.Berserk:BAAALgADCgIJAgAAAA==.Bestchance:BAAALgAECgEJAQAAAA==.Beware:BAAALgADCgIJAgAAAA==.Beärlylegäl:BAAALgAECgEJBQAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJDQABLgAFFAMJCwAQAPghAA==.Bigbear:BAACLgAFFH8IAAIRAAQJth8VCABrAQARAAQJth8VCABrAQAuAAQKfxsAAxEACAn3I2AEAM8CABEACAn3I2AEAM8CABIABgnrFtZYAEgBAAEuAAUUBAkSAAcAUSUA.Bigdave:BAABLgAECn8uAAMTAAkJkh2HCwD9AgATAAkJkh2HCwD9AgAUAAQJZwiqLACJAAAAAA==.Bigtamer:BAAALgADCgMJAwAAAA==.Bisan:BAAALgADCgUJBgAAAA==.',
Bj='Bjebo:BAACLgAFFH8OAAIVAAQJIAY+LwDAAAAVAAQJIAY+LwDAAAAuAAQKfz0AAhUACQnyFLUWABYCABUACQnyFLUWABYCAAAA.',
Bl='Blaank:BAACLgAFFH8MAAIFAAQJ2wVgWwDzAAAFAAQJ2wVgWwDzAAAuAAQKfx4AAgUACAlkFKJUAMoBAAUACAlkFKJUAMoBAAAA.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.Bluffshot:BAAALgAECgEJAgABLgAECgkJLQAEAOggAA==.',
Bo='Boba:BAACLgAFFH8LAAMTAAMJiSQALQAnAQATAAMJiSQALQAnAQAWAAEJ1wHkXAAtAAAuAAQKfxYAAxMABwlWJCIaAHYCABMABwlWJCIaAHYCABYABgmtH5gkAL8BAAEuAAUUBgkXABcAIhoA.Boku:BAAALgAECgEJAQAAAA==.Borealiswolf:BAABLgAFFH8LAAIUAAQJMBb/BwA2AQAUAAQJMBb/BwA2AQAAAA==.Borg:BAABLgAFFH8LAAMNAAMJZyMgRQAcAQANAAMJkSAgRQAcAQAYAAMJmxl6GgD4AAAAAA==.',
Br='Bralaria:BAAALgAECgUJBQAAAA==.Bremena:BAAALgADCgMJAwAAAA==.Brewchew:BAABLgAECn8cAAIHAAgJ0w6GKwBZAQAHAAgJ0w6GKwBZAQAAAA==.Brynjalf:BAAALgAECgUJCAAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bï']='Bïcho:BAACLgAFFH8LAAMQAAMJ+CEoTQAnAQAQAAMJ+CEoTQAnAQAOAAEJAwksKQBDAAAuAAQKfzUABBAACQkpJSsFADwDABAACQkpJSsFADwDAA4AAQkAAHsfAHUAABkAAQn5GaxtADkAAAAA.',
Ca='Calambar:BAAALgAECgEJAQAAAA==.Calib:BAACLgAFFH8ZAAMWAAUJKhi0HgAhAQAWAAUJKhi0HgAhAQATAAEJ4QMRewA/AAAuAAQKfzEAAhYACQmwIv8LAKECABYACQmwIv8LAKECAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Casdardly:BAAALgAECgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgAECgIJAwAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQAaAKwRAA==.Cheechin:BAABLgAECn8aAAIbAAgJnx+cDAB3AgAbAAgJnx+cDAB3AgABLgAFFAQJFgACAMcUAA==.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAACLgAFFH8KAAIVAAMJ1wsvMwCtAAAVAAMJ1wsvMwCtAAAuAAQKfyYAAhUACAn6FdEgAL4BABUACAn6FdEgAL4BAAAA.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn86AAIWAAkJGiJ3BwDiAgAWAAkJGiJ3BwDiAgAAAA==.',
Co='Coffeeshot:BAAALgADCgEJAQAAAA==.Comboost:BAAALgAECgQJBAAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8eAAMcAAUJMCLHCABYAQAcAAQJMCLHCABYAQABAAEJAABYJAEAAAAuAAQKfzcAAhwACQlCI0IAAJMDABwACQlCI0IAAJMDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.',
Cu='Cup:BAABLgAECn8oAAMMAAkJsB2RCwDSAgAMAAkJsB2RCwDSAgAFAAEJQBVLfAE7AAAAAA==.',
Cv='Cvv:BAAALgAECgUJBgABLgAFFAEJAQAdAAAAAA==.',
Cy='Cyndreya:BAACLgAFFH8hAAIeAAUJyR31FgCyAQAeAAUJyR31FgCyAQAuAAQKf0EAAh4ACQk7JDwCAJkDAB4ACQk7JDwCAJkDAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Daelaris:BAABLgAECn8jAAICAAkJwR9QEwDkAgACAAkJwR9QEwDkAgAAAA==.Damthrax:BAAALgAECgEJAQAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darmil:BAAALgADCggJEwAAAA==.Davegrôwl:BAAALgAECgUJBAABLgAECggJLQAEANYWAA==.Daylar:BAAALgAECgEJAQABLgAECgcJHgANAAERAA==.Daztoo:BAAALgAECgQJBQAAAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Deathbrand:BAAALgAECggJDwAAAA==.Dedbhang:BAABLgAFFH8KAAIBAAQJoQzqcwAXAQABAAQJoQzqcwAXAQAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Demonblades:BAABLgAECn8jAAIDAAkJExMnQADFAQADAAkJExMnQADFAQAAAA==.Demonicpixie:BAAALgAECgIJAwAAAA==.Denarten:BAAALgADCgQJBAABLgAECgcJGQAPAO8eAA==.Destructoe:BAAALgAECgUJBQAAAA==.Devotegoat:BAAALgAECgUJCAAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtyalba:BAAALgAECgUJBQAAAA==.Dirtymorris:BAACLgAFFH8FAAIfAAMJ9QvZJQDEAAAfAAMJ9QvZJQDEAAAuAAQKfy4AAx8ACQkTEbobAOYBAB8ACQkTEbobAOYBACAABwk6FoAwAH8BAAAA.',
Do='Docignis:BAABLgAECn8XAAIWAAgJXA+FQQApAQAWAAgJXA+FQQApAQAAAA==.Dockevorkian:BAACLgAFFH8dAAIgAAUJhiIrBwDZAQAgAAUJhiIrBwDZAQAuAAQKfzIAAiAACQlBIjoGAOsCACAACQlBIjoGAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECggJFwAWAFwPAA==.Docrhada:BAAALgAECgQJBQABLgAECggJFwAWAFwPAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAABLgAECn8ZAAIDAAgJUhx4KwAXAgADAAgJUhx4KwAXAgABLgAFFAcJHgABALcgAA==.',
Dr='Dracoradk:BAAALgAECgYJBwABLgAFFAQJCAAbAEoGAA==.Dracoramonk:BAABLgAFFH8IAAIbAAQJSgYJJAC+AAAbAAQJSgYJJAC+AAAAAA==.Dragonchris:BAAALgAECgUJCgAAAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Draxus:BAAALgAECggJCAAAAA==.Drdisco:BAAALgAECgUJBQAAAA==.Dricex:BAAALgAECgYJCQAAAA==.Drinnagon:BAAALgAECgMJBwABLgAECgcJGQAPAO8eAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAPAO8eAA==.Drinntellect:BAABLgAECn8ZAAMPAAcJ7x6rBQDPAQAPAAYJCh+rBQDPAQACAAcJ1RpqhwDDAQAAAA==.Drraxx:BAAALgAECgUJBQAAAA==.Drunkdino:BAAALgADCgUJBQAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Dunnstunns:BAAALgAECgIJAgAAAA==.Duskwälker:BAAALgADCgcJBwAAAA==.',
Dx='Dxanatos:BAABLgAECn8pAAIhAAkJiQgIEQBFAQAhAAkJiQgIEQBFAQAAAA==.',
['Dø']='Døuce:BAAALgADCgUJAwAAAA==.',
Ea='Eamass:BAABLgAECn8rAAIHAAkJSSF7BgDQAgAHAAkJSSF7BgDQAgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.Eiré:BAAALgADCgQJBAAAAA==.',
Ej='Ejunk:BAAALgAECgMJAwAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn83AAIEAAkJixAoGgCLAQAEAAkJixAoGgCLAQAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJFwACAG0VAA==.',
En='Enanthate:BAAALgADCgMJBQABLgAFFAEJAQAdAAAAAA==.Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8eAAQBAAcJtyCxHgDtAQABAAcJxx6xHgDtAQAcAAQJ9x7WBgB3AQAEAAEJAADzTQAAAAAuAAQKfysAAwEACQm6I0cNADADAAEACQmLI0cNADADABwAAQmgJCYuAGIAAAAA.Enthing:BAACLgAFFH8hAAIDAAUJeBX5PQAoAQADAAUJeBX5PQAoAQAuAAQKf0EAAgMACQkVIWkNANgCAAMACQkVIWkNANgCAAAA.',
Es='Essamond:BAAALgAECgQJBAAAAA==.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAABLgAECn8cAAIgAAgJPyZUAwBaAwAgAAgJPyZUAwBaAwAAAA==.Famiki:BAAALgAECgUJCAAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatalxclaw:BAAALgADCgIJAgAAAA==.Fatheral:BAABLgAECn8bAAIfAAkJpBW1HgDOAQAfAAkJpBW1HgDOAQAAAA==.',
Fe='Felaxare:BAAALgAECgcJDQAAAA==.Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8lAAQDAAkJ+xwbMAADAgAiAAgJlhqkFwALAgADAAgJFBkbMAADAgAjAAYJCBiIDQB+AQAAAA==.Fentagram:BAABLgAECn8jAAMOAAkJnCX7AQCyAgAOAAgJdSb7AQCyAgAQAAQJkSGolQARAQAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgADCgUJBgAAAA==.',
Fl='Floofwall:BAABLgAECn8jAAMHAAgJ/h6GDQBdAgAHAAgJ/h6GDQBdAgAbAAEJyBL+kwA5AAAAAA==.Floralcarer:BAAALgAECgYJBgAAAA==.',
Fo='Follet:BAAALgADCgQJBwAAAA==.Fonyfish:BAACLgAFFH8LAAIQAAUJLB0KNwBlAQAQAAUJLB0KNwBlAQAuAAQKf0AAAxAACQkUI8wHABcDABAACQkUI8wHABcDABkAAgmwEm5RAHoAAAAA.Fonytime:BAAALgAECgYJBgABLgAFFAUJCwAQACwdAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8sAAQZAAkJiRB/DgBRAQAQAAgJ6AvnbQBfAQAZAAgJwRB/DgBRAQAOAAEJAACVSAAAAAAAAA==.Foxydots:BAAALgADCgcJCgAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgAECgMJAwABLgAECggJLQAEANYWAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAACLgAFFH8GAAIbAAMJyhOIIwDAAAAbAAMJyhOIIwDAAAAuAAQKfzEABBsACAn5IfwNAGQCABsACAn5IfwNAGQCAAcABwkmD2gyADUBABoAAQkeCr7HACEAAAAA.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Ga='Galdran:BAAALgAECgEJAQAAAA==.',
Gg='Ggakkaltigad:BAAALgAECggJCgAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8YAAIGAAcJGh2BBgD3AQAGAAcJGh2BBgD3AQAuAAQKfyUAAwYACAmmJHQHADEDAAYACAmCJHQHADEDACQAAgnRGUspAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8XAAIWAAYJhBmeVADjAAAWAAYJhBmeVADjAAABLgAFFAUJHgAcADAiAA==.Glorm:BAABLgAECn8nAAITAAkJtw49PAC5AQATAAkJtw49PAC5AQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAABLgAECn8tAAMEAAgJ1haFFwCnAQAEAAgJ1haFFwCnAQABAAYJdQ2auAAFAQAAAA==.Grantul:BAABLgAECn8pAAIGAAkJXhzPFgCWAgAGAAkJXhzPFgCWAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAABLgAECn8VAAIDAAYJEh4rTwCUAQADAAYJEh4rTwCUAQABLgAFFAQJEgAHAFElAA==.Grimthore:BAAALgAECgMJAwABLgAECggJJwAFAHkYAA==.Grolgan:BAABLgAECn8eAAINAAcJAREraQBrAQANAAcJAREraQBrAQAAAA==.Growlings:BAABLgAECn8sAAIVAAgJzBxcEQBNAgAVAAgJzBxcEQBNAgAAAA==.',
Gu='Guncow:BAAALgAECgEJAQAAAA==.',
Ha='Hailmary:BAAALgADCgIJAgAAAA==.Haradave:BAAALgAECgIJAgAAAA==.Hawktuâh:BAAALgADCgEJAQABLgAECggJLQAEANYWAA==.',
He='Healiostrasz:BAAALgAECgQJBgAAAA==.Health:BAAALgAECgIJAgAAAA==.Healyeah:BAAALgAECgMJBAABLgAECggJIwAHAP4eAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgYJCwABLgAECggJIAAFANgWAA==.Holyczar:BAAALgADCgkJGwAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hr='Hruun:BAAALgADCgIJAgAAAA==.',
Hu='Hubirt:BAABLgAECn8mAAIFAAgJ/hgCYQCsAQAFAAgJ/hgCYQCsAQAAAA==.Huntsybuntsy:BAACLgAFFH8OAAMUAAUJxBXTCAArAQAUAAUJxBXTCAArAQAWAAIJvQJZTABbAAAuAAQKfzgAAxQACQlgIIECAPACABQACQlgIIECAPACABYACAkzFoQbADYCAAAA.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJFwACAG0VAA==.',
Hy='Hydrafoil:BAAALgAECgcJEQAAAA==.',
Ia='Ianthel:BAAALgAECgUJCwAAAA==.',
Ic='Icesloth:BAABLgAECn8jAAIWAAkJHxlhEwBPAgAWAAkJHxlhEwBPAgAAAA==.',
Id='Idamae:BAABLgAECn8iAAICAAkJbAItzgDxAAACAAkJbAItzgDxAAAAAA==.Iduun:BAAALgAECgUJDQAAAA==.',
Il='Iladelle:BAABLgAECn8mAAIDAAkJ+hB6RwCsAQADAAkJ+hB6RwCsAQAAAA==.Illidabina:BAAALgAFFAIJBAABLgAFFAMJBgAbAMoTAA==.',
In='Inariokami:BAABLgAECn8XAAIHAAkJKAlLKwBbAQAHAAkJKAlLKwBbAQAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.',
Io='Iorak:BAAALgADCgQJBAAAAA==.',
Ir='Irinon:BAAALgAECgQJCgAAAA==.Irocky:BAAALgADCgkJCQAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgQJCQAAAA==.',
Ja='Jaaygee:BAACLgAFFH8FAAIKAAIJcxRlDACSAAAKAAIJcxRlDACSAAAuAAQKfxkAAgoABwmwH5oEADECAAoABwmwH5oEADECAAEuAAQKCAk1ABAA4yIA.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAACLgAFFH8MAAIQAAMJAh/RWAARAQAQAAMJAh/RWAARAQAuAAQKfzkAAxAACQkgIlgLAPMCABAACQkgIlgLAPMCABkACAlbGf4EAIsCAAAA.Jaggerss:BAAALgAECgEJAQABLgAFFAcJHgABALcgAA==.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8bAAIgAAcJLhMqKwBrAQAgAAcJLhMqKwBrAQAAAA==.',
Jb='Jbsvoid:BAAALgAECgEJAQAAAA==.',
Je='Jelliebean:BAAALgADCgYJBgAAAA==.Jessalba:BAAALgAECgMJBAAAAA==.Jessalbaa:BAAALgAECgMJAwAAAA==.Jestorian:BAAALgAECgYJEgAAAA==.',
Ji='Jimmym:BAAALgAECgEJAQAAAA==.Jirakaidae:BAABLgAECn8bAAIVAAgJEgVHSADmAAAVAAgJEgVHSADmAAAAAA==.',
Jo='Jockinonmytw:BAACLgAFFH8MAAIJAAQJqSGdFgBTAQAJAAQJqSGdFgBTAQAuAAQKf0EAAgkACQlDJXQCADIDAAkACQlDJXQCADIDAAAA.Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCwAAAA==.Juicyfists:BAAALgAECgEJBAAAAA==.Justice:BAAALgADCgEJAQAAAA==.Justred:BAABLgAECn8VAAMGAAYJeRQOSAAkAQAGAAYJeRQOSAAkAQAkAAMJaA+ETQCVAAAAAA==.',
Jx='Jxson:BAACLgAFFH8GAAMVAAIJIhQRPAB8AAAVAAIJIhQRPAB8AAASAAEJ1Ab4cgAwAAAuAAQKfyYABREABgkAINkSAL8BABEABgm3H9kSAL8BABIABgnFFGRXAEwBABUABgkIEgtDAPwAACUAAwl+Ej4jALwAAAEuAAQKCAk1ABAA4yIA.Jxsong:BAACLgAFFH8FAAIeAAIJIBWuOgCKAAAeAAIJIBWuOgCKAAAuAAQKfxkAAx4ABgmiHnwXABYCAB4ABgmiHnwXABYCAB8ABAnQE8JUALwAAAEuAAQKCAk1ABAA4yIA.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ka='Kaisel:BAAALgAECgcJBwAAAA==.Kandrys:BAAALgAECgIJAgAAAA==.Kanoa:BAAALgADCgYJBgAAAA==.Kantuo:BAAALgAFFAQJBAAAAA==.Kattschitt:BAAALgAECgEJAQAAAA==.',
Ke='Keanx:BAAALgAFFAEJAQAAAA==.Kehila:BAAALgADCgEJAQAAAA==.Kendorwar:BAAALgAECgkJAwAAAA==.',
Kh='Khelad:BAACLgAFFH8eAAIFAAQJKRmbPAAsAQAFAAQJKRmbPAAsAQAuAAQKfxoAAwUACQkcGsRRANEBAAUACQkcGsRRANEBAAsAAQk+C7JWACAAAAAA.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAABLgAECn8ZAAIHAAYJoB7xHAC7AQAHAAYJoB7xHAC7AQAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killau:BAAALgADCgEJAgAAAA==.Killt:BAABLgAECn8gAAITAAkJxRQvIgASAgATAAkJxRQvIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAABLgAECn8cAAImAAcJQxE4IgAaAQAmAAcJQxE4IgAaAQAAAA==.',
Ku='Kurzulan:BAAALgAECgQJCAABLgAECgYJCQAdAAAAAA==.',
Ky='Kynthe:BAAALgAECggJDgAAAA==.Kyongye:BAAALgAECgkJDQAAAA==.',
La='Lacerater:BAAALgADCgcJCgAAAA==.Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8eAAMNAAQJ5x0gLQBQAQANAAQJ5x0gLQBQAQAhAAIJ7AhvIACTAAAuAAQKf0oAAw0ACQl4JIAFADgDAA0ACQl4JIAFADgDACEACAkEG54aAFUCAAAA.',
Le='Leadgut:BAAALgADCgQJBwAAAA==.Lemanjá:BAABLgAECn8tAAIhAAkJoA/gCgC4AQAhAAkJoA/gCgC4AQAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Liliane:BAABLgAECn8dAAMLAAkJkQxbIQAGAQAFAAYJ8QcJuwANAQALAAgJMAxbIQAGAQAAAA==.Limbless:BAAALgAECgYJDAABLgAECgYJDQAdAAAAAA==.Littletoast:BAAALgAECgYJBwAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockrocks:BAAALgAECgQJCwABLgAECggJJwAFAHkYAA==.Lockstar:BAAALgADCgUJDAABLgAECggJDwAdAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAABLgAECn8aAAIVAAYJ9grOTADUAAAVAAYJ9grOTADUAAAAAA==.Loozer:BAABLgAECn8nAAMFAAgJeRjVUADUAQAFAAgJmBfVUADUAQALAAYJ+gsKKQDMAAAAAA==.',
Lu='Lulutauren:BAAALgAECgEJAQAAAA==.Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAABLgAECn8fAAIFAAYJYxCvqgAkAQAFAAYJYxCvqgAkAQAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8mAAMBAAkJxxqUKABdAgABAAkJxxqUKABdAgAcAAEJywjmGAAsAAAAAA==.',
Ma='Magelyman:BAABLgAECn8cAAICAAkJJRkdKwBrAgACAAkJJRkdKwBrAgAAAA==.Magetiger:BAABLgAECn8iAAICAAkJ6xVxPQAjAgACAAkJ6xVxPQAjAgAAAA==.Magsh:BAAALgADCgQJBAAAAA==.Malitheion:BAABLgAECn8UAAMBAAcJtwmRrgATAQABAAcJigmRrgATAQAEAAMJ4wEoVABFAAAAAA==.Malyce:BAAALgAFFAIJAgAAAA==.Malzen:BAABLgAECn8VAAMHAAgJARd+IgCSAQAHAAgJARd+IgCSAQAbAAEJ9AsaogArAAABLgAFFAIJAgAdAAAAAA==.Manaleia:BAAALgAECgQJBwAAAA==.Manasolid:BAABLgAECn8/AAICAAkJIhZ9NwA4AgACAAkJIhZ9NwA4AgAAAA==.Mangeømbre:BAAALgAECgQJBAAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgAECgcJDAAAAA==.Masculinedh:BAAALgAECgIJAwABLgAFFAEJAQAdAAAAAA==.',
Me='Meanka:BAAALgAECgEJAQABLgAFFAMJCgAfAOYeAA==.Meatcurtin:BAAALgADCgkJEQAAAA==.Meches:BAAALgAECgQJCAABLgAECgkJPwASAKkVAA==.Mediocre:BAAALgAECgIJAgAAAA==.Mediocritty:BAAALgAECgYJCgABLgAFFAMJBgAUAG0EAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAABLgAECn8yAAICAAgJCw3BgABzAQACAAgJCw3BgABzAQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Meraleona:BAAALgAECgUJBQABLgAECgkJLAABAC4dAA==.Methslinger:BAABLgAECn8dAAIWAAYJGQ48TwD1AAAWAAYJGQ48TwD1AAAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Milkwithpulp:BAABLgAECn8kAAIgAAgJ/xV7HgDMAQAgAAgJ/xV7HgDMAQAAAA==.Miltonroe:BAAALgADCggJBQABLgAFFAMJBgAUAG0EAA==.Mistynollid:BAAALgADCgYJBgABLgAECgkJJQADAPscAA==.',
Mk='Mkoons:BAAALgAECgEJBAAAAA==.',
Mo='Monkanical:BAAALgADCgYJCgAAAA==.Mook:BAABLgAECn8cAAIDAAgJHAzlbQBEAQADAAgJHAzlbQBEAQAAAA==.Morbious:BAAALgAECgMJBAAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAABLgAECn8WAAIZAAcJBQZlHwCtAAAZAAcJBQZlHwCtAAAAAA==.Mortmuzi:BAAALgAECgUJDAAAAA==.Mosrael:BAAALgAECgkJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.',
Mu='Mulas:BAABLgAECn8kAAIQAAkJqxZeKwAqAgAQAAkJqxZeKwAqAgAAAA==.Muldah:BAACLgAFFH8WAAICAAQJxxRfWQA2AQACAAQJxxRfWQA2AQAuAAQKfzEAAgIACQlrII4dAKgCAAIACQlrII4dAKgCAAAA.',
My='Mynte:BAABLgAECn8eAAIgAAYJnBIYNQApAQAgAAYJnBIYNQApAQAAAA==.',
['Mâ']='Mâlice:BAAALgAECgIJAgAAAA==.',
['Mä']='Mäsion:BAABLgAFFH8HAAIGAAQJtwMYNgDTAAAGAAQJtwMYNgDTAAAAAA==.',
Na='Natty:BAAALgADCgkJIAAAAA==.Navie:BAABLgAECn8+AAIeAAkJNBU1EQBeAgAeAAkJNBU1EQBeAgAAAA==.Nawperwoman:BAABLgAECn8oAAMbAAgJvhvtEgBcAgAbAAgJvhvtEgBcAgAaAAEJrgGhdgAYAAAAAA==.Nazevroth:BAAALgAECgUJBQAAAA==.Nazgûl:BAABLgAFFH8FAAIBAAMJMxqoiAD0AAABAAMJMxqoiAD0AAAAAA==.',
Ne='Necronomicob:BAABLgAECn8zAAQQAAkJsxlrJwA9AgAQAAkJsxlrJwA9AgAZAAQJ7RgnGQDXAAAOAAMJ/BK5JgCFAAAAAA==.Neil:BAAALgADCgUJBQABLgAFFAUJFQATAAAKAA==.Nekros:BAABLgAECn82AAQQAAkJ5h6hGACPAgAQAAgJNx6hGACPAgAZAAQJaBxUJQAyAQAOAAMJTxtcGwDeAAAAAA==.Neø:BAABLgAECn84AAMBAAkJ+RcELABOAgABAAkJ+RcELABOAgAcAAMJoApuMABWAAAAAA==.',
Ni='Nianna:BAAALgADCgcJCgAAAA==.Nicebud:BAAALgAECgkJEwAAAA==.Nightsfury:BAABLgAECn8gAAIFAAgJGQ5egwBmAQAFAAgJGQ5egwBmAQAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAABLgAECn8WAAIEAAYJyApwNQC+AAAEAAYJyApwNQC+AAAAAA==.Nordburg:BAAALgAECgEJAQAAAA==.Nornyr:BAABLgAECn8pAAIaAAkJIBa8HAAtAgAaAAkJIBa8HAAtAgAAAA==.Notnonna:BAAALgAECgEJAQAAAA==.Noxiss:BAAALgADCgQJBAABLgAECgkJLAABAC4dAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn8/AAIVAAkJug6xIwCpAQAVAAkJug6xIwCpAQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oriax:BAABLgAECn8rAAIQAAcJvRO8awBkAQAQAAcJvRO8awBkAQAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgYJCgAAAA==.',
Pa='Paean:BAAALgAECgUJEgAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8mAAMSAAgJZgQohgCpAAASAAgJZgQohgCpAAAVAAQJ+gISeQBQAAAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBwAdAAAAAA==.Peata:BAAALgAECgEJAgAAAA==.Persephones:BAABLgAECn8fAAIfAAcJ4A/eJwCaAQAfAAcJ4A/eJwCaAQAAAA==.Perseus:BAAALgADCgkJCQAAAA==.',
Ph='Phenelope:BAABLgAECn8ZAAMCAAgJTgPyzgDwAAACAAgJTgPyzgDwAAAnAAcJnAF8DgBwAAAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECgkJFwAHACgJAA==.Pillowpuhmpa:BAAALgAECgIJBAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgAECgIJAgAAAA==.',
Pk='Pkalygos:BAABLgAECn8eAAIXAAkJlRO8DwDLAQAXAAkJlRO8DwDLAQAAAA==.',
Po='Polaka:BAAALgAECgkJAQAAAA==.Poosnwoods:BAAALgAECgYJDgAAAA==.Popefuffer:BAAALgAFFAMJAQAAAA==.Powerstrokee:BAABLgAECn8aAAMBAAcJGRRbdgB0AQABAAcJGRRbdgB0AQAcAAIJEQ+uLwBaAAAAAA==.',
Pr='Preyforme:BAAALgAECgYJEgAAAA==.Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAIMAAgJrRzoEQCDAgAMAAgJrRzoEQCDAgAAAA==.Protadin:BAABLgAECn8YAAILAAYJwBQUFwBjAQALAAYJwBQUFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAABLgAECn8YAAMMAAcJbgpMTQADAQAMAAYJAAxMTQADAQAFAAIJBQjffgE5AAAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôcky:BAAALgAECgEJAQABLgAECgkJKwAHAEkhAA==.Pôps:BAAALgAECgYJEwAAAA==.',
Qu='Quickprick:BAAALgAECgcJEwAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAABLgAFFAEJAQAdAAAAAA==.Ranharr:BAAALgADCgQJBAAAAA==.Rasina:BAAALgAECgIJBAAAAA==.Ratkìng:BAAALgAECgMJBAAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Redcrayons:BAAALgADCgkJCQAAAA==.Reknojir:BAAALgAECgQJBgAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8eAAIDAAQJeRqBNwA/AQADAAQJeRqBNwA/AQAuAAQKfz4AAwMACQkzIb4JAPsCAAMACQkzIb4JAPsCACIABgkAEcs6ABUBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Rh='Rhade:BAAALgAECgMJAwAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgcJDgAAAA==.Rizar:BAAALgAECgUJCgAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgYJDQAdAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn9GAAIRAAkJPQMbOwCzAAARAAkJPQMbOwCzAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.',
Ru='Rumhanced:BAAALgADCgkJCQAAAA==.Runeclad:BAABLgAECn8cAAIBAAkJnRX4PwABAgABAAkJnRX4PwABAgAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámi:BAAALgADCgEJAgAAAA==.',
['Rï']='Rïvkah:BAAALgADCgYJDAAAAA==.',
Sa='Saauurrora:BAAALgAECgcJCwAAAA==.Sabiton:BAAALgADCgYJCgAAAA==.Sadistikult:BAAALgADCgIJAgAAAA==.Saintshift:BAAALgAECgMJAwABLgAFFAEJAQAdAAAAAA==.Salitheion:BAABLgAECn8tAAIMAAgJnhgHGQA8AgAMAAgJnhgHGQA8AgAAAA==.Saloraith:BAAALgAECgcJEwAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Salôis:BAAALgAECgYJBgAAAA==.Sanaig:BAAALgADCgcJBwAAAA==.Sanatura:BAAALgAECgYJCwAAAA==.Sapper:BAABLgAECn8wAAIaAAkJ4CDxBwAaAwAaAAkJ4CDxBwAaAwAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgQJCwAAAA==.Sarn:BAABLgAECn8bAAIRAAkJpxI3DwCIAQARAAkJpxI3DwCIAQAAAA==.Sathi:BAAALgAECgcJAgAAAA==.Saudhum:BAABLgAECn8WAAMOAAYJwRsfCADLAQAOAAYJwRsfCADLAQAQAAQJ4Q2Y4QCWAAAAAA==.Sayuri:BAABLgAECn81AAMaAAgJjiKOCAAQAwAaAAgJjiKOCAAQAwAbAAIJXAOlvAAYAAAAAA==.',
Sb='Sboop:BAAALgAECgQJBwAAAA==.',
Sc='Scrím:BAAALgAECgIJBQAAAA==.',
Se='Secondchance:BAAALgAECgIJAwAAAA==.Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shadowmoocow:BAAALgADCgkJEgABLgAECgQJBAAdAAAAAA==.Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn80AAITAAkJjAYiWQBOAQATAAkJjAYiWQBOAQAAAA==.Sheriam:BAAALgADCgcJBwAAAA==.Shikí:BAAALgAECgMJBgAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn86AAIkAAgJxRXDFwCZAQAkAAgJxRXDFwCZAQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAACLgAFFH8RAAImAAQJMQ9QFgDjAAAmAAQJMQ9QFgDjAAAuAAQKfyYAAiYACQlaFCASAMUBACYACQlaFCASAMUBAAAA.Shotsshots:BAABLgAECn8vAAQNAAkJDB9rHgBsAgANAAkJDB9rHgBsAgAYAAIJGgz6TgBxAAAhAAEJAAC1kQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgAECgEJAQAAAA==.Sicaria:BAABLgAECn8WAAMkAAUJ6xkfKwAbAQAkAAUJ6xkfKwAbAQAGAAEJ5woQpgAwAAAAAA==.Sindina:BAAALgADCgYJBgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDgAAAA==.Skully:BAACLgAFFH8SAAIHAAQJUSWHEACZAQAHAAQJUSWHEACZAQAuAAQKfzQAAwcACQlfJRICAEEDAAcACQlfJRICAEEDABoAAQkBFdisAD4AAAAA.',
Sl='Slamdh:BAAALgAECgkJCQAAAA==.Slicedup:BAAALgAECgMJAwABLgAECggJDwAdAAAAAA==.Sluffshot:BAABLgAECn8tAAMEAAkJ6CC9CACHAgAEAAkJaCC9CACHAgABAAQJYx07twAUAQAAAA==.',
Sn='Snorina:BAACLgAFFH8KAAIfAAMJ5h76HQD7AAAfAAMJ5h76HQD7AAAuAAQKfzcAAh8ACQkQJSIDADEDAB8ACQkQJSIDADEDAAAA.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solarex:BAAALgAECgUJBQAAAA==.Solina:BAAALgAECgcJBwAAAA==.Solsteece:BAAALgADCgYJDwAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAABLgAECn84AAMHAAkJtBvSCgCFAgAHAAkJtBvSCgCFAgAbAAMJxgdCbwBuAAAAAA==.Sosozen:BAABLgAECn8mAAIbAAkJxQ5QIgCaAQAbAAkJxQ5QIgCaAQAAAA==.Soul:BAAALgAECgcJEAAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgcJEAAdAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Sparkgrace:BAAALgADCgEJAQAAAA==.Spirittoast:BAAALgAECgUJEQAAAA==.Spluffshot:BAAALgAECgIJAgAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAABLgAECn8bAAICAAkJkg3DZQCvAQACAAkJkg3DZQCvAQAAAA==.',
Sq='Squelch:BAAALgAECgQJEAAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Stratovarius:BAAALgAECgUJBQAAAA==.Strumpet:BAAALgAECgQJBQAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAABLgAECn8YAAINAAkJYxzEFwCUAgANAAkJYxzEFwCUAgABLgAECggJJwAFAHkYAA==.Swytch:BAABLgAECn8pAAIIAAkJ8xfNBQASAgAIAAkJ8xfNBQASAgAAAA==.',
Sy='Sylrytherin:BAABLgAECn8VAAMVAAcJkBokHQAXAgAVAAcJkBokHQAXAgARAAEJAACNkAAAAAABLgAFFAMJCgAfAOYeAA==.Sylvii:BAABLgAECn8/AAMSAAkJqRUFHQBbAgASAAkJqRUFHQBbAgAVAAYJRxHcPAAYAQAAAA==.',
Ta='Tabor:BAABLgAECn8dAAMSAAcJBh0hJwAUAgASAAYJcB8hJwAUAgARAAEJuApZfQAgAAAAAA==.Takachance:BAAALgAECgIJAwAAAA==.Talio:BAAALgAECgEJAQAAAA==.Tammyfaye:BAAALgAECgEJAQABLgAECggJLQAEANYWAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAABLgAECn8dAAIMAAgJ1xYlHAAgAgAMAAgJ1xYlHAAgAgAAAA==.Tauryel:BAAALgAECgYJDQAAAA==.',
Te='Tebook:BAABLgAECn8sAAMBAAkJLh3IRQDvAQABAAkJLh3IRQDvAQAcAAEJvwaUPgAnAAAAAA==.Telath:BAACLgAFFH8KAAIDAAQJlQlnWwDWAAADAAQJlQlnWwDWAAAuAAQKfyUAAgMACQk8Gf48AAACAAMACQk8Gf48AAACAAAA.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8YAAIDAAcJNiL5EQAVAgADAAcJNiL5EQAVAgAuAAQKfyYAAgMACQm0IF4aALYCAAMACQm0IF4aALYCAAAA.Thistlechi:BAABLgAECn8nAAIbAAgJnBozEAB9AgAbAAgJnBozEAB9AgAAAA==.Thyck:BAABLgAECn8hAAINAAgJzRhGSgC+AQANAAgJzRhGSgC+AQAAAA==.Thydis:BAAALgAFFAEJAQAAAA==.',
Ti='Tibbs:BAABLgAECn8eAAIoAAkJEg5NKwCPAQAoAAkJEg5NKwCPAQAAAA==.Timber:BAAALgAECgQJCAAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Toatasi:BAAALgADCgYJBgAAAA==.Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJDAAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAACLgAFFH8KAAIlAAMJexUoDQDdAAAlAAMJexUoDQDdAAAuAAQKfxoAAiUACAmpFh4OAM4BACUACAmpFh4OAM4BAAAA.',
Tu='Tuckr:BAAALgADCgQJBAAAAA==.Tullamore:BAAALgAECgcJCgAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgcJDgAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQaAAcJrBHqLQBJAQAaAAYJHxHqLQBJAQAbAAUJjw2BaACAAAAHAAEJWgD1mAAbAAAAAA==.Tylerblevins:BAAALgADCgMJAwAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAFFAcJEwASAIgYAA==.',
Un='Uncorrupted:BAABLgAECn8+AAILAAkJ9B0CBQChAgALAAkJ9B0CBQChAgAAAA==.Unholymilk:BAAALgAECgEJAQAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAAALgAECgYJEwAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAABLgAECn8rAAINAAcJoBpvPwDgAQANAAcJoBpvPwDgAQAAAA==.Vasdepherens:BAABLgAECn8iAAIEAAkJShMJGACbAQAEAAkJShMJGACbAQAAAA==.',
Ve='Velan:BAAALgADCgcJEQAAAA==.Vermouth:BAABLgAECn8jAAMbAAgJdxHrLgBKAQAbAAgJdxHrLgBKAQAaAAYJ6AIZgwCOAAAAAA==.',
Vi='Vindrelis:BAAALgADCggJEwAAAA==.Violêt:BAABLgAECn8fAAICAAcJjAUhzAD0AAACAAcJjAUhzAD0AAAAAA==.',
Vo='Voidchris:BAABLgAFFH8GAAIDAAQJjhXlPQAoAQADAAQJjhXlPQAoAQAAAA==.Voidfang:BAAALgADCgEJAQAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgADCgcJCAAAAA==.Volkanegos:BAABLgAECn8iAAMGAAYJZwThbACuAAAGAAYJZwThbACuAAAkAAEJuwCOSwAGAAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
We='Weedmaan:BAAALgAECgUJBQAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwAAAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAFFAUJFgAGABoiAA==.Wizerwar:BAACLgAFFH8WAAIGAAUJGiLtDgCIAQAGAAUJGiLtDgCIAQAuAAQKf1EAAgYACQnRJDADADkDAAYACQnRJDADADkDAAAA.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAACLgAFFH8GAAICAAIJBxZ7lACmAAACAAIJBxZ7lACmAAAuAAQKfx0AAgIACAlhGlRCABICAAIACAlhGlRCABICAAAA.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgcJBwAAAA==.',
Ya='Yadiyada:BAAALgAECggJDgABLgAECggJHAADABwMAA==.',
Yl='Ylzera:BAAALgAECgEJAgABLgAECgcJCgAdAAAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIiAAYJywiuPAC/AAAiAAYJywiuPAC/AAAAAA==.Yoshì:BAAALgAECgUJBQAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAABLgAECggJGwACAOgXAA==.Zakuren:BAABLgAECn9LAAINAAkJRBebJQBHAgANAAkJRBebJQBHAgAAAA==.',
Zi='Ziggimist:BAAALgAFFAEJAQAAAA==.',
Zo='Zombied:BAAALgAECgEJBwAAAA==.Zort:BAAALgAECgcJAQAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAABLgAECn8kAAICAAYJ9BD/sQAbAQACAAYJ9BD/sQAbAQAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8lAAQoAAkJSBFTMwBkAQAoAAcJaRRTMwBkAQAXAAUJgwnnMwDOAAApAAUJBQs3KwDDAAAAAA==.',
['Òm']='Òmêñ:BAAALgADCgkJDwAAAA==.',
['Ôj']='Ôjarg:BAAALgAECgcJEAAAAA==.',
['Ül']='Ülf:BAAALgADCgQJBAAAAA==.',
['ßæ']='ßær:BAAALgAECgQJCQAAAA==.',
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
