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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Warrior-Fury','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Druid-Feral','Warrior-Protection','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aarkein:BAAALgAECgYJBgAAAA==.',
Ab='Abiotic:BAAALgAECgEJAwAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ac='Aceofspaded:BAAALgAECgQJBQAAAA==.Acesup:BAAALgAFFAEJAQAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.Aesir:BAAALgADCgYJCAAAAA==.',
Ai='Aings:BAACLgAFFH8FAAIBAAIJqyRosADCAAABAAIJqyRosADCAAAuAAQKfzQAAgEACQkkI5YSANoCAAEACQkkI5YSANoCAAAA.',
Al='Alarus:BAAALgAECgMJAwAAAA==.Aldtris:BAAALgADCgcJCgAAAA==.Alejandro:BAAALgADCggJCAAAAA==.Aletaa:BAAALgAECgcJAQABLgAFFAUJDQACADAQAA==.Alex:BAABLgAECn83AAIDAAkJJh6BFQCXAgADAAkJJh6BFQCXAgAAAA==.Alivathor:BAAALgAECgYJCgABLgAECgcJGQAEALcKAA==.Allypally:BAABLgAECn8bAAIFAAkJig0pjwBTAQAFAAkJig0pjwBTAQAAAA==.Althir:BAABLgAECn8rAAICAAkJBSDsJQDbAgACAAkJBSDsJQDbAgAAAA==.Althorian:BAAALgAECgQJAgAAAA==.',
Am='Amgrod:BAEBLgAECn8oAAIGAAkJmQlbMgCCAQAGAAkJmQlbMgCCAQAAAA==.Amythest:BAAALgADCgkJDwAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCggJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8eAAIFAAcJ5hhseQB7AQAFAAcJ5hhseQB7AQAAAA==.',
Ar='Arfas:BAAALgAECggJDgABLgAECggJJAAHAP4eAA==.Arkhitype:BAABLgAECn9FAAQIAAkJJx5SAgC7AgAIAAkJJx5SAgC7AgAJAAYJuQ+xMACBAQAKAAEJGQbGKQAgAAAAAA==.Armak:BAAALgADCgEJAgAAAA==.Arwenibria:BAAALgAECgEJAQAAAA==.',
As='Ashdritha:BAAALgAECgEJAQAAAA==.Ashya:BAAALgADCgYJBgAAAA==.Asur:BAABLgAECn88AAMFAAkJdxNpBACWAQAFAAkJdxNpBACWAQALAAUJkgNMPwBgAAAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Auracorusca:BAABLgAECn8jAAIMAAkJeiTYAgB4AwAMAAkJeiTYAgB4AwAAAA==.Auris:BAAALgADCgQJBwAAAA==.',
Ay='Aynilith:BAAALgAECgYJCAAAAA==.Aystarael:BAAALgAECgkJBgAAAA==.',
Ba='Bajablast:BAAALgAECgEJAQAAAA==.Bajr:BAABLgAECn8qAAINAAkJjg51UwCpAQANAAkJjg51UwCpAQAAAA==.Bakura:BAABLgAECn8iAAIOAAkJzhxkBAA5AgAOAAkJzhxkBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8iAAIDAAkJORMVUgCPAQADAAkJORMVUgCPAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.Barudd:BAAALgADCgEJAQAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAACLgAFFH8IAAIPAAMJNR7/AQD0AAAPAAMJNR7/AQD0AAAuAAQKf00AAw8ACQk0JGsAAB8DAA8ACQk0JGsAAB8DAAIAAQlcEJRUATYAAAAA.Berserk:BAAALgADCgIJAgAAAA==.Bestchance:BAAALgAECgEJAQAAAA==.Beware:BAAALgADCgIJAgAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJDQABLgAFFAQJEgAQAAUfAA==.Bigbear:BAACLgAFFH8NAAIRAAUJCiD1AQBvAQARAAUJCiD1AQBvAQAuAAQKfxsAAxEACAn3I4YEAM8CABEACAn3I4YEAM8CABIABgnrFs1gABMBAAAA.Bigtamer:BAAALgADCgMJAwAAAA==.Bisan:BAAALgADCgUJBgAAAA==.',
Bj='Bjebo:BAACLgAFFH8OAAITAAQJIAagMADAAAATAAQJIAagMADAAAAuAAQKfz0AAhMACQnyFFYXABICABMACQnyFFYXABICAAAA.',
Bl='Blaank:BAACLgAFFH8MAAIFAAQJ2wWuXgDyAAAFAAQJ2wWuXgDyAAAuAAQKfx4AAgUACAlkFMRWAMcBAAUACAlkFMRWAMcBAAAA.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.Bluffshot:BAAALgAECgEJAgABLgAFFAMJBgABAFcZAA==.',
Bo='Boba:BAACLgAFFH8LAAMUAAMJiSQqLwAlAQAUAAMJiSQqLwAlAQAVAAEJ1wFvYAAtAAAuAAQKfxYAAxQABwlWJK8aAHUCABQABwlWJK8aAHUCABUABgmtH0AlAL8BAAEuAAUUBgkXABYAIhoA.Boku:BAAALgAECgEJAQAAAA==.Borealiswolf:BAABLgAFFH8LAAIXAAQJMBaMCAAwAQAXAAQJMBaMCAAwAQAAAA==.Borg:BAABLgAFFH8NAAMNAAMJZyOvSQAZAQANAAMJkSCvSQAZAQAYAAMJmxlZCAChAAABLgAFFAQJCQADAFYWAA==.',
Br='Bralaria:BAAALgAECgUJBQAAAA==.Bremena:BAAALgADCgMJAwAAAA==.Brewchew:BAACLgAFFH8GAAIHAAMJZggVDAClAAAHAAMJZggVDAClAAAuAAQKfx0AAgcACAkhET4lAIMBAAcACAkhET4lAIMBAAAA.Brutes:BAAALgAECgIJBAABLgAFFAcJIAABADshAA==.Brynjalf:BAAALgAECgUJCAAAAA==.Bràe:BAAALgAECgEJAgAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bë']='Bëärlylëgäl:BAAALgAFFAEJAwAAAA==.',
['Bï']='Bïcho:BAACLgAFFH8SAAMQAAQJBR9REQAEAQAQAAQJBR9REQAEAQAOAAIJ8gw4BAB9AAAuAAQKfzUABBAACQkpJWIFADoDABAACQkpJWIFADoDAA4AAQkAAHsfAHUAABkAAQn5GaxtADkAAAAA.',
Ca='Calambar:BAAALgAECgEJAQAAAA==.Calib:BAACLgAFFH8ZAAMVAAUJKhgVIAAfAQAVAAUJKhgVIAAfAQAUAAEJ4QOVfgA/AAAuAAQKfzEAAhUACQmwIkIMAKACABUACQmwIkIMAKACAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Casdardly:BAAALgAECgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgAECgIJAwAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQAaAKwRAA==.Cheechin:BAACLgAFFH8FAAIbAAQJVw1YHADsAAAbAAQJVw1YHADsAAAuAAQKfxoAAhsACAmfH94MAHYCABsACAmfH94MAHYCAAEuAAUUBQkaAAIAxxQA.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAACLgAFFH8NAAITAAMJ1wuHDQCmAAATAAMJ1wuHDQCmAAAuAAQKfy0AAhMACAlgFyIdAN8BABMACAlgFyIdAN8BAAAA.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn9AAAIVAAkJiCK2BwDhAgAVAAkJiCK2BwDhAgAAAA==.',
Co='Coffeeshot:BAAALgADCgEJAQAAAA==.Comboost:BAAALgAECgYJCgAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8eAAMcAAUJMCKaCQBWAQAcAAQJMCKaCQBWAQABAAEJAAC8LQEAAAAuAAQKfzcAAhwACQlCI0IAAJMDABwACQlCI0IAAJMDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.Critos:BAAALgAECgQJBAAAAA==.',
Cu='Cup:BAABLgAECn8oAAMMAAkJsB3GCwDRAgAMAAkJsB3GCwDRAgAFAAEJQBUTgwE7AAAAAA==.',
Cv='Cvv:BAAALgAECgUJBgAAAA==.',
Cy='Cyndreya:BAACLgAFFH8hAAIdAAUJyR3zFwCvAQAdAAUJyR3zFwCvAQAuAAQKf0EAAh0ACQk7JFECAJYDAB0ACQk7JFECAJYDAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Dadgumit:BAABLgAECn8wAAMUAAkJfh7kCwD8AgAUAAkJfh7kCwD8AgAXAAQJZwjtLQCJAAAAAA==.Daelaris:BAABLgAECn8jAAICAAkJwR/6EwDiAgACAAkJwR/6EwDiAgAAAA==.Damthrax:BAAALgAECgQJCAAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darmil:BAAALgADCggJEwAAAA==.Davegrôwl:BAAALgAECgUJBgABLgAECgkJMwAEAKcXAA==.Daylar:BAAALgAECgEJAQABLgAECggJIwANALwVAA==.Dazztoo:BAAALgAECgQJBQAAAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Deadzeo:BAAALgAECgYJBwAAAA==.Deathbrand:BAAALgAECggJDwAAAA==.Dedbhang:BAABLgAFFH8KAAIBAAQJoQwQeAATAQABAAQJoQwQeAATAQAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Demonblades:BAABLgAECn8jAAIDAAkJExMIQQDFAQADAAkJExMIQQDFAQAAAA==.Demonicpixie:BAAALgAECgIJAwAAAA==.Denarten:BAAALgADCgQJBAABLgAECgcJGQAPAO8eAA==.Destructoe:BAAALgAECgUJCwAAAA==.Devotegoat:BAAALgAECgUJCAAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtyalba:BAAALgAECgUJBQAAAA==.Dirtymorris:BAACLgAFFH8GAAIeAAMJ9QvwJgDEAAAeAAMJ9QvwJgDEAAAuAAQKfy4AAx4ACQkTEZgcAOABAB4ACQkTEZgcAOABAB8ABwk6FoAwAH8BAAAA.',
Do='Docignis:BAABLgAECn8XAAIVAAgJXA/xQgAnAQAVAAgJXA/xQgAnAQAAAA==.Dockevorkian:BAACLgAFFH8jAAIfAAUJMSO8BwDXAQAfAAUJMSO8BwDXAQAuAAQKfzQAAh8ACQlBIjoGAOsCAB8ACQlBIjoGAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECggJFwAVAFwPAA==.Docrhada:BAAALgAECgQJBQABLgAECggJFwAVAFwPAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAABLgAECn8ZAAIDAAgJUhwOLAAYAgADAAgJUhwOLAAYAgABLgAFFAcJIAABADshAA==.',
Dr='Dracoradk:BAAALgAECgYJBwABLgAFFAQJCAAbAEoGAA==.Dracoramonk:BAABLgAFFH8IAAIbAAQJSgZGJQC+AAAbAAQJSgZGJQC+AAAAAA==.Dragonchris:BAAALgAFFAIJAgABLgAFFAQJCQADAFYWAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Draxus:BAAALgAECggJCAAAAA==.Drayvn:BAAALgADCgIJAgAAAA==.Drdisco:BAAALgAECgUJBQAAAA==.Dricex:BAAALgAECgYJCgAAAA==.Drinnagon:BAAALgAECgUJCgABLgAECgcJGQAPAO8eAA==.Drinnaqua:BAAALgADCgUJBQABLgAECgcJGQAPAO8eAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAPAO8eAA==.Drinntellect:BAABLgAECn8ZAAMPAAcJ7x6rBQDPAQAPAAYJCh+rBQDPAQACAAcJ1RpqhwDDAQAAAA==.Drraxx:BAAALgAECgUJBQAAAA==.Drunkdino:BAAALgADCgUJBQAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Duningkruger:BAAALgADCgcJBwABLgAFFAMJCQAXAMQGAA==.Dunnstunns:BAAALgAECgIJAgAAAA==.Duskwälker:BAAALgAECgEJAQAAAA==.',
Dx='Dxanatos:BAABLgAECn8pAAIgAAkJiQhQEQBFAQAgAAkJiQhQEQBFAQAAAA==.',
['Dø']='Døuce:BAAALgADCgUJAwAAAA==.',
Ea='Eamass:BAABLgAECn8rAAIHAAkJSSGrBgDPAgAHAAkJSSGrBgDPAgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.Eiré:BAAALgADCgQJBAAAAA==.',
Ej='Ejunk:BAAALgAECgYJBwAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn87AAIEAAkJixCvGgCIAQAEAAkJixCvGgCIAQAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJFwACAG0VAA==.',
En='Enanthate:BAAALgADCgMJBQABLgAECgUJBgAhAAAAAA==.Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8gAAQBAAcJOyFoIQDrAQABAAcJxx5oIQDrAQAcAAQJvB+YBwB0AQAEAAEJAADHUAAAAAAuAAQKfysAAwEACQm6I0cNADADAAEACQmLI0cNADADABwAAQmgJFUvAGIAAAAA.Enthing:BAACLgAFFH8hAAIDAAUJeBWeQAAmAQADAAUJeBWeQAAmAQAuAAQKf0EAAgMACQkVIakNANgCAAMACQkVIakNANgCAAAA.',
Es='Essamond:BAAALgAECgQJBAAAAA==.',
Ev='Evellara:BAAALgAECgUJCAABLgAECgkJMwAEAKcXAA==.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAABLgAECn8cAAIfAAgJPyZlAwBZAwAfAAgJPyZlAwBZAwAAAA==.Famiki:BAAALgAECgUJCAAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatalxclaw:BAAALgADCgIJAgAAAA==.Fatboycurt:BAAALgADCgIJAgAAAA==.Fatheral:BAABLgAECn8bAAIeAAkJpBVgHwDKAQAeAAkJpBVgHwDKAQAAAA==.',
Fe='Felaxare:BAAALgAECgcJDQAAAA==.Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8oAAQDAAkJIR3MMAADAgAiAAgJlhqkFwALAgADAAgJ+hnMMAADAgAjAAYJCBiIDQB+AQAAAA==.Fentagram:BAABLgAECn8jAAMOAAkJnCX7AQCyAgAOAAgJdSb7AQCyAgAQAAQJkSEUlgAQAQAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgAECgIJAgAAAA==.',
Fl='Floofwall:BAABLgAECn8kAAMHAAgJ/h67DQBdAgAHAAgJ/h67DQBdAgAbAAEJyBLrlgA5AAAAAA==.Floralcarer:BAAALgAECgYJBgAAAA==.',
Fo='Follet:BAAALgAECgYJBgAAAA==.Fonyfish:BAACLgAFFH8LAAIQAAUJLB3JOQBjAQAQAAUJLB3JOQBjAQAuAAQKf0AAAxAACQkUIyAIABUDABAACQkUIyAIABUDABkAAgmwEm5RAHoAAAAA.Fonytime:BAAALgAECgYJBgABLgAFFAUJCwAQACwdAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8sAAQZAAkJiRDaDgBQAQAQAAgJ6AvobwBbAQAZAAgJwRDaDgBQAQAOAAEJAABzSgAAAAAAAA==.Foxydots:BAAALgADCgcJCgAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgAECgMJAwABLgAECgkJMwAEAKcXAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAECLgAFFH8IAAMbAAMJyhPOJADAAAAbAAMJyhPOJADAAAAaAAIJWQvbGwBjAAAuAAQKfzcABBsACAmOI18LAI0CABsACAmOI18LAI0CAAcABwkmD+4yADQBABoAAQkeCgXOACEAAAAA.Fulgurithm:BAAALgAECgEJAgABLgAECgkJIwAOAJwlAA==.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Ga='Galdran:BAAALgAECgEJAQAAAA==.',
Gg='Ggakkaltigad:BAAALgAECggJCgAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8gAAIGAAgJgxpaBgADAgAGAAgJgxpaBgADAgAuAAQKfyUAAwYACAmmJHQHADEDAAYACAmCJHQHADEDACQAAgnRGUspAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8XAAIVAAYJhBkXVgDiAAAVAAYJhBkXVgDiAAABLgAFFAUJHgAcADAiAA==.Glorm:BAABLgAECn8oAAIUAAkJtw40PQC5AQAUAAkJtw40PQC5AQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAABLgAECn8zAAMEAAkJpxfxFwClAQAEAAkJWxfxFwClAQABAAYJZg8cEQCcAAAAAA==.Grantul:BAABLgAECn8pAAIGAAkJXhzPFgCWAgAGAAkJXhzPFgCWAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAABLgAECn8VAAIDAAYJEh5BUACVAQADAAYJEh5BUACVAQABLgAFFAUJDQARAAogAA==.Grimthore:BAAALgAECgQJBgABLgAECggJLAAFAHkYAA==.Grolgan:BAABLgAECn8jAAINAAgJvBXxVAClAQANAAgJvBXxVAClAQAAAA==.Growlings:BAABLgAECn8xAAITAAgJ2ByZEQBNAgATAAgJ2ByZEQBNAgAAAA==.',
Gu='Gueva:BAAALgAFFAQJBAAAAA==.Guilarth:BAAALgAECgkJAgAAAA==.Guncow:BAAALgAECgEJAQAAAA==.',
Gw='Gwaela:BAAALgAECgMJAwAAAA==.',
Ha='Hailmary:BAAALgADCgIJAgAAAA==.Haradave:BAAALgAECgIJAgAAAA==.Hawktuâh:BAAALgADCgEJAQABLgAECgkJMwAEAKcXAA==.',
He='Healiostrasz:BAAALgAECgQJBgAAAA==.Health:BAAALgAECgQJBgAAAA==.Healyeah:BAAALgAFFAMJBAABLgAECggJJAAHAP4eAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Henrock:BAAALgAECgEJAQAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgYJCwABLgAECggJJQAFAEoXAA==.Holyczar:BAAALgADCgkJGwAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hr='Hruun:BAAALgADCgIJAgAAAA==.',
Hu='Hubirt:BAABLgAECn8mAAIFAAgJ/hhNYwCpAQAFAAgJ/hhNYwCpAQAAAA==.Huntsybuntsy:BAACLgAFFH8OAAMXAAUJxBVmCQAlAQAXAAUJxBVmCQAlAQAVAAIJvQILTwBbAAAuAAQKfzgAAxcACQlgIJkCAO8CABcACQlgIJkCAO8CABUACAkzFoQbADYCAAAA.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJFwACAG0VAA==.',
Hy='Hydrafoil:BAAALgAECgcJEQAAAA==.',
Ia='Ianthel:BAAALgAECgUJCwAAAA==.',
Ic='Icesloth:BAABLgAECn8jAAIVAAkJHxm7EwBOAgAVAAkJHxm7EwBOAgAAAA==.',
Id='Idamae:BAABLgAECn8iAAICAAkJbAL50ADwAAACAAkJbAL50ADwAAAAAA==.Iduun:BAAALgAECgUJDQAAAA==.',
Il='Iladelle:BAABLgAECn8mAAIDAAkJ+hB3SACtAQADAAkJ+hB3SACtAQAAAA==.Illidabina:BAEALgAFFAIJBAABLgAFFAMJCAAbAMoTAA==.',
In='Inariokami:BAABLgAECn8XAAIHAAkJKAnCKwBbAQAHAAkJKAnCKwBbAQAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.Inposter:BAAALgAECgYJBwAAAA==.',
Io='Iorak:BAAALgADCgYJBgAAAA==.',
Ir='Irinon:BAAALgAECgQJDwAAAA==.Irocky:BAAALgADCgkJCQAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgQJCQAAAA==.',
Ja='Jaaygee:BAACLgAFFH8FAAIKAAIJcxTfDACSAAAKAAIJcxTfDACSAAAuAAQKfxoAAgoABwmwH6gEADACAAoABwmwH6gEADACAAEuAAQKCAk1ABAA4yIA.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAACLgAFFH8SAAIQAAQJ3xspCwBPAQAQAAQJ3xspCwBPAQAuAAQKfzkAAxAACQkgIrcLAPACABAACQkgIrcLAPACABkACAlbGf4EAIsCAAAA.Jaggerss:BAAALgAECgEJAgABLgAFFAcJIAABADshAA==.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8bAAIfAAcJLhPaKwBrAQAfAAcJLhPaKwBrAQAAAA==.',
Jb='Jbsvoid:BAAALgAECgEJAQAAAA==.',
Je='Jelliebean:BAAALgADCgYJBgAAAA==.Jessalba:BAAALgAECgMJBAAAAA==.Jessalbaa:BAAALgAECgMJAwAAAA==.Jestorian:BAAALgAECgcJEwAAAA==.',
Ji='Jimmym:BAAALgAECgIJAwAAAA==.Jirakaidae:BAABLgAECn8gAAITAAgJiQZuSQDmAAATAAgJiQZuSQDmAAABLgAECgUJCwAhAAAAAA==.',
Jo='Jockinonmytw:BAACLgAFFH8MAAIJAAQJqSGYFwBSAQAJAAQJqSGYFwBSAQAuAAQKf0EAAgkACQlDJY0CADEDAAkACQlDJY0CADEDAAAA.Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCwAAAA==.Juicyfists:BAAALgAECgEJBAAAAA==.Justred:BAABLgAECn8VAAMGAAYJeRTqSQAeAQAGAAYJeRTqSQAeAQAkAAMJaA9STwCVAAAAAA==.',
Jx='Jxson:BAACLgAFFH8GAAMTAAIJIhTiPQB8AAATAAIJIhTiPQB8AAASAAEJ1AZ2dQAwAAAuAAQKfyYABREABgkAIFgTAL8BABEABgm3H1gTAL8BABIABgnFFGRXAEwBABMABgkIEvhDAPwAACUAAwl+Ej4jALwAAAEuAAQKCAk1ABAA4yIA.Jxsong:BAACLgAFFH8HAAIdAAIJIBWLPACJAAAdAAIJIBWLPACJAAAuAAQKfxsAAx0ABgmjHuQXABUCAB0ABgmjHuQXABUCAB4ABAnQE7dVALwAAAEuAAQKCAk1ABAA4yIA.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ka='Kaisel:BAAALgAECgcJCAAAAA==.Kandrys:BAAALgAECgIJAgAAAA==.Kanoa:BAAALgADCgYJBgAAAA==.Kantuo:BAAALgAFFAQJBAAAAA==.Kattschitt:BAAALgAECgEJAQAAAA==.',
Ke='Keanx:BAAALgAFFAEJAQAAAA==.Kehila:BAAALgADCgEJAQAAAA==.Kendorwar:BAAALgAECgkJAwAAAA==.',
Kh='Khelad:BAACLgAFFH8jAAIFAAUJCxofDQAdAQAFAAUJCxofDQAdAQAuAAQKfxoAAwUACQkcGqlSANEBAAUACQkcGqlSANEBAAsAAQk+CxBYACAAAAAA.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAABLgAECn8gAAIHAAcJIx4CAQC1AQAHAAcJIx4CAQC1AQAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killau:BAAALgAECgEJAQAAAA==.Killt:BAABLgAECn8gAAIUAAkJxRQvIgASAgAUAAkJxRQvIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAABLgAECn8kAAImAAgJaRCMAgD+AAAmAAgJaRCMAgD+AAAAAA==.',
Ku='Kurzulan:BAAALgAECgQJCAABLgAECgYJCQAhAAAAAA==.',
Ky='Kynthe:BAAALgAECggJDgAAAA==.Kyongye:BAAALgAECgkJDQAAAA==.',
La='Lacerater:BAAALgADCgcJCgAAAA==.Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8jAAMNAAUJ5x23DAA8AQANAAUJ5x23DAA8AQAgAAIJ7AhvIACTAAAuAAQKf0oAAw0ACQl4JMcFADcDAA0ACQl4JMcFADcDACAACAkEG54aAFUCAAAA.',
Le='Leadgut:BAAALgADCgQJBwAAAA==.Lemanjá:BAABLgAECn80AAIgAAkJfhPSAABeAQAgAAkJfhPSAABeAQAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Lilfurrybast:BAAALgADCgEJAQAAAA==.Liliane:BAABLgAECn8dAAMLAAkJkQzNIQAGAQAFAAYJ8QfUvgAKAQALAAgJMAzNIQAGAQAAAA==.Lillatheen:BAAALgAECgYJCAAAAA==.Limbless:BAAALgAECgYJDAABLgAECgYJDQAhAAAAAA==.Littletoast:BAAALgAECgYJBwAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockrocks:BAAALgAECgUJDAABLgAECggJLAAFAHkYAA==.Lockstar:BAAALgADCgUJDAABLgAECggJDwAhAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAABLgAECn8bAAITAAYJ9goATgDUAAATAAYJ9goATgDUAAAAAA==.Loozer:BAABLgAECn8sAAMFAAgJeRgCUgDTAQAFAAgJmBcCUgDTAQALAAYJ+gugKQDMAAAAAA==.',
Lu='Lulutauren:BAAALgAECgEJAQAAAA==.Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAABLgAECn8gAAIFAAYJYxB5rgAhAQAFAAYJYxB5rgAhAQAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8mAAMBAAkJxxrOKQBZAgABAAkJxxrOKQBZAgAcAAEJywjmGAAsAAAAAA==.',
Ma='Magelyman:BAACLgAFFH8FAAICAAIJWhF0ngCPAAACAAIJWhF0ngCPAAAuAAQKfxwAAgIACQklGfUrAGoCAAIACQklGfUrAGoCAAAA.Magetiger:BAABLgAECn8iAAICAAkJ6xWHPgAiAgACAAkJ6xWHPgAiAgAAAA==.Magoshon:BAAALgAECgIJAQABLgAECgQJBAAhAAAAAA==.Magsh:BAAALgADCgQJBAAAAA==.Malitheion:BAABLgAECn8VAAMBAAcJPgo/sAAUAQABAAcJEgo/sAAUAQAEAAMJ4wFkVQBFAAAAAA==.Malyce:BAAALgAFFAIJAgAAAA==.Malzen:BAABLgAECn8VAAMHAAgJARfvIgCSAQAHAAgJARfvIgCSAQAbAAEJ9AtBpQArAAABLgAFFAIJAgAhAAAAAA==.Manaleia:BAAALgAECgQJBwAAAA==.Manasolid:BAABLgAECn9JAAICAAkJzBviAQB0AgACAAkJzBviAQB0AgAAAA==.Mangeømbre:BAAALgAECgQJBAAAAA==.Mar:BAAALgAECgMJBwAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgAECgcJDQAAAA==.Masculinedh:BAAALgAECgIJAwABLgAECgUJBgAhAAAAAA==.',
Me='Meanka:BAAALgAECgEJAQABLgAFFAMJCgAeAOYeAA==.Meatcurtin:BAAALgADCgkJGAAAAA==.Meches:BAAALgAECgQJCAABLgAECgkJRQASAKkVAA==.Mediocre:BAAALgAECgIJAgAAAA==.Mediocritty:BAAALgAECgYJCgABLgAFFAMJCQAXAMQGAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAABLgAECn9BAAICAAkJzw7cBgBMAQACAAkJzw7cBgBMAQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Meraleona:BAAALgAECgUJBQABLgAECgkJLAABAC4dAA==.Methslinger:BAABLgAECn8dAAIVAAYJGQ7WUAD0AAAVAAYJGQ7WUAD0AAAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Milkwithpulp:BAABLgAECn8kAAIfAAgJ/xUPHwDMAQAfAAgJ/xUPHwDMAQAAAA==.Miltonroe:BAAALgADCggJBQABLgAFFAMJCQAXAMQGAA==.Mistynollid:BAAALgADCgYJBgABLgAECgkJKAADACEdAA==.',
Mk='Mkoons:BAAALgAECgEJBAAAAA==.',
Mo='Monkanical:BAAALgADCgkJEwAAAA==.Mook:BAABLgAECn8cAAIDAAgJHAx9bwBEAQADAAgJHAx9bwBEAQAAAA==.Morbious:BAAALgAECgMJBQAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAABLgAECn8WAAIZAAcJBQYNIACsAAAZAAcJBQYNIACsAAAAAA==.Mortmuzi:BAAALgAECgUJDAAAAA==.Mosrael:BAAALgAECgkJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.Mourningveil:BAAALgADCggJCAAAAA==.',
Mu='Mulas:BAABLgAECn8kAAIQAAkJqxYHLAApAgAQAAkJqxYHLAApAgAAAA==.Muldah:BAACLgAFFH8aAAICAAUJxxRqXAAmAQACAAUJxxRqXAAmAQAuAAQKfzEAAgIACQlrIC8eAKgCAAIACQlrIC8eAKgCAAAA.',
My='Mynte:BAABLgAECn8eAAIfAAYJnBL5NQApAQAfAAYJnBL5NQApAQAAAA==.',
['Mâ']='Mâlice:BAAALgAECgIJAgAAAA==.',
['Mä']='Mäsion:BAABLgAFFH8HAAIGAAQJtwPJNwDTAAAGAAQJtwPJNwDTAAAAAA==.',
Na='Natty:BAAALgADCgkJJQAAAA==.Navie:BAABLgAECn8+AAIdAAkJNBXoEQBXAgAdAAkJNBXoEQBXAgAAAA==.Nawperwoman:BAABLgAECn8oAAMbAAgJvhvtEgBcAgAbAAgJvhvtEgBcAgAaAAEJrgGhdgAYAAAAAA==.Nazevroth:BAAALgAECgcJCwAAAA==.Nazgûl:BAABLgAFFH8JAAIBAAUJmxRMJwDHAAABAAUJmxRMJwDHAAAAAA==.',
Ne='Necronomicob:BAABLgAECn80AAQQAAkJsxn9JwA8AgAQAAkJsxn9JwA8AgAZAAQJ7RieGQDWAAAOAAMJ/BK9JwCEAAAAAA==.Neil:BAAALgADCgUJBQABLgAFFAUJGAAUABwMAA==.Nekros:BAABLgAECn86AAQQAAkJ5h4kGQCNAgAQAAgJNx4kGQCNAgAZAAQJaBxUJQAyAQAOAAMJTxsGHADeAAAAAA==.Neø:BAABLgAECn84AAMBAAkJ+RecLABNAgABAAkJ+RecLABNAgAcAAMJoArXMQBVAAAAAA==.',
Ni='Nianna:BAAALgADCgcJCgAAAA==.Nicebud:BAABLgAECn8VAAIDAAkJaxRUOwDaAQADAAkJaxRUOwDaAQAAAA==.Nightsfury:BAABLgAECn8gAAIFAAgJGQ5JhQBlAQAFAAgJGQ5JhQBlAQAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAABLgAECn8ZAAIEAAcJtwomNgC+AAAEAAcJtwomNgC+AAAAAA==.Nordburg:BAAALgAECgEJAQAAAA==.Nornyr:BAABLgAECn8qAAIaAAkJaRZPHQAuAgAaAAkJaRZPHQAuAgAAAA==.Notforgiven:BAAALgAECgEJAQAAAA==.Notnonna:BAAALgAECgEJAgAAAA==.Noxiss:BAAALgADCgQJBAABLgAECgkJLAABAC4dAA==.',
Nu='Nunsrsus:BAAALgADCgYJCQABLgAECgYJFQAGAHkUAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn9JAAITAAkJcBKDAQC/AQATAAkJcBKDAQC/AQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oriax:BAABLgAECn8yAAIQAAgJ+RW5BQAcAQAQAAgJ+RW5BQAcAQAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgYJCgAAAA==.',
Pa='Paean:BAABLgAECn8UAAIaAAYJ8BOKDACjAAAaAAYJ8BOKDACjAAAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8mAAMSAAgJZgRbhwCpAAASAAgJZgRbhwCpAAATAAQJ+gIjewBQAAAAAA==.',
Pb='Pbj:BAAALgAECgEJAQAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBwAhAAAAAA==.Peata:BAAALgAECgUJBwAAAA==.Persephones:BAABLgAECn8fAAIeAAcJ4A/eJwCaAQAeAAcJ4A/eJwCaAQAAAA==.Perseus:BAAALgADCgkJCQAAAA==.',
Ph='Phenelope:BAABLgAECn8ZAAMCAAgJTgO90QDvAAACAAgJTgO90QDvAAAnAAcJnAHhDgBwAAAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECgkJFwAHACgJAA==.Pillowpuhmpa:BAAALgAECgIJBAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgAECgIJAgAAAA==.',
Pk='Pkalygos:BAABLgAECn8eAAIWAAkJlRPtDwDMAQAWAAkJlRPtDwDMAQAAAA==.',
Po='Polaka:BAAALgAECgkJAQAAAA==.Poosnwoods:BAAALgAECgYJDgAAAA==.Popefuffer:BAAALgAFFAMJAQAAAA==.Powerstrokee:BAABLgAECn8aAAMBAAcJGRS8eAByAQABAAcJGRS8eAByAQAcAAIJEQ8WMQBZAAAAAA==.',
Pr='Preyforme:BAAALgAECgYJEgAAAA==.Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAIMAAgJrRzoEQCDAgAMAAgJrRzoEQCDAgAAAA==.Protadin:BAABLgAECn8YAAILAAYJwBQUFwBjAQALAAYJwBQUFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAABLgAECn8YAAMMAAcJbgphTgAAAQAMAAYJAAxhTgAAAQAFAAIJBQifhQE5AAAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôcky:BAAALgAECgEJAQABLgAECgkJKwAHAEkhAA==.Pôps:BAAALgAECgYJEwAAAA==.',
Qu='Quickprick:BAAALgAECgcJEwAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAABLgAFFAMJBAAhAAAAAA==.Ranharr:BAAALgADCgQJBAAAAA==.Rasina:BAAALgAECgIJBAAAAA==.Ratkìng:BAAALgAECgMJBAAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Redcrayons:BAAALgADCgkJCQAAAA==.Reknojir:BAAALgAECgQJBgAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8jAAIDAAUJeRr4OQA9AQADAAUJeRr4OQA9AQAuAAQKfz4AAwMACQkzIfAJAPsCAAMACQkzIfAJAPsCACIABgkAEcs6ABUBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Rh='Rhade:BAAALgAECgMJAwAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgkJDgAAAA==.Rizar:BAAALgAECgUJCgAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgYJDQAhAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn9QAAIRAAkJPQOrPACzAAARAAkJPQOrPACzAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.',
Ru='Rumhanced:BAAALgADCgkJCQAAAA==.Runeclad:BAABLgAECn8cAAIBAAkJnRW2QQD+AQABAAkJnRW2QQD+AQAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámi:BAAALgAECgEJAQAAAA==.',
['Rï']='Rïvkah:BAAALgADCgcJDgAAAA==.',
Sa='Saauurrora:BAAALgAECgcJCwAAAA==.Sabiton:BAAALgADCgYJCgAAAA==.Sadistikult:BAAALgADCgIJAgAAAA==.Saintshift:BAAALgAECgMJAwABLgAECgUJBgAhAAAAAA==.Salitheion:BAABLgAECn8uAAIMAAgJ+hhnGQA7AgAMAAgJ+hhnGQA7AgAAAA==.Saloraith:BAAALgAECgcJEwAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Salôis:BAAALgAECgYJBwAAAA==.Sanaig:BAAALgADCgcJBwAAAA==.Sanatura:BAAALgAECgYJCwAAAA==.Sapper:BAABLgAECn8wAAIaAAkJ4CAfCAAaAwAaAAkJ4CAfCAAaAwAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgQJCwAAAA==.Sarn:BAABLgAECn8bAAIRAAkJpxI3DwCIAQARAAkJpxI3DwCIAQAAAA==.Sathi:BAAALgAECgcJAgAAAA==.Saudhum:BAABLgAECn8WAAMOAAYJwRsfCADLAQAOAAYJwRsfCADLAQAQAAQJ4Q3K4gCWAAAAAA==.Sayuri:BAABLgAECn84AAMaAAkJfyEaBQBaAwAaAAkJfyEaBQBaAwAbAAIJXANfwAAYAAAAAA==.',
Sb='Sboop:BAAALgAECgQJBwAAAA==.',
Sc='Scrím:BAAALgAECgIJBQAAAA==.',
Se='Secondchance:BAAALgAECgIJBQAAAA==.Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shadowmoocow:BAAALgADCgkJEgABLgAECgYJCgAhAAAAAA==.Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn81AAIUAAkJswanWgBOAQAUAAkJswanWgBOAQAAAA==.Sheriam:BAAALgADCgcJBwAAAA==.Shikí:BAAALgAECgMJBgAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn9AAAIkAAkJhxVMGACYAQAkAAkJhxVMGACYAQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAACLgAFFH8SAAImAAQJMQ8mFwDiAAAmAAQJMQ8mFwDiAAAuAAQKfyYAAiYACQlaFG8SAMQBACYACQlaFG8SAMQBAAAA.Shotsshots:BAABLgAECn8vAAQNAAkJDB9MHwBrAgANAAkJDB9MHwBrAgAYAAIJGgycUABtAAAgAAEJAAC1kQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgAECgEJAQAAAA==.Sicaria:BAABLgAECn8WAAMkAAUJ6xkJLAAbAQAkAAUJ6xkJLAAbAQAGAAEJ5woMqgAsAAAAAA==.Sindina:BAAALgADCgYJBgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDgAAAA==.Skully:BAACLgAFFH8SAAIHAAQJUSWtEQCXAQAHAAQJUSWtEQCXAQAuAAQKfzUAAwcACQlfJSICAEADAAcACQlfJSICAEADABoAAglLFl0XAEMAAAEuAAUUBQkNABEACiAA.',
Sl='Slamdh:BAAALgAECgkJCgABLgAFFAIJBwAJAAgdAA==.Slicedup:BAAALgAECgMJAwABLgAECggJDwAhAAAAAA==.Sluffshot:BAACLgAFFH8GAAIBAAMJVxmNHQDxAAABAAMJVxmNHQDxAAAuAAQKfy0AAwQACQnoIPcIAIQCAAQACQloIPcIAIQCAAEABAljHTu3ABQBAAAA.',
Sn='Snorina:BAACLgAFFH8KAAIeAAMJ5h4eHwD6AAAeAAMJ5h4eHwD6AAAuAAQKfzcAAh4ACQkQJUEDAC4DAB4ACQkQJUEDAC4DAAAA.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solarex:BAAALgAECgYJBgAAAA==.Solina:BAAALgAECgcJBwAAAA==.Solsteece:BAAALgADCgYJDwAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAABLgAECn9BAAMHAAkJehylCQCXAgAHAAkJehylCQCXAgAbAAMJxgcMcQBuAAAAAA==.Sosozen:BAABLgAECn8mAAIbAAkJxQ7VIgCaAQAbAAkJxQ7VIgCaAQAAAA==.Soul:BAAALgAECgcJEAAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgcJEAAhAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Sparkgrace:BAAALgADCgEJAQAAAA==.Spellbinder:BAAALgAECgEJAQABLgAECggJLAAFAHkYAA==.Spirittoast:BAAALgAECgYJEwAAAA==.Spluffshot:BAAALgAECgIJAgAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAABLgAECn8bAAICAAkJkg1YZwCuAQACAAkJkg1YZwCuAQAAAA==.',
Sq='Squelch:BAAALgAECgQJEgAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Stratovarius:BAAALgAECgUJBQAAAA==.Strumpet:BAAALgAECgQJBQAAAA==.',
Su='Summuner:BAAALgAECgQJBQAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAABLgAECn8YAAINAAkJYxykGACTAgANAAkJYxykGACTAgABLgAECggJLAAFAHkYAA==.Swytch:BAABLgAECn8pAAIIAAkJ8xfgBQATAgAIAAkJ8xfgBQATAgAAAA==.',
Sy='Sylrytherin:BAABLgAECn8WAAMTAAcJqRokHQAXAgATAAcJqRokHQAXAgARAAEJAAAWlQAAAAABLgAFFAMJCgAeAOYeAA==.Sylvii:BAABLgAECn9FAAMSAAkJqRV9HQBaAgASAAkJqRV9HQBaAgATAAYJRhPSBADiAAAAAA==.',
Ta='Tabor:BAABLgAECn8eAAMSAAcJhR1dHwBLAgASAAcJhR1dHwBLAgARAAEJuApngQAgAAAAAA==.Takachance:BAAALgAECgIJBAAAAA==.Talio:BAAALgAECgEJAgAAAA==.Tammyfaye:BAAALgAECgEJAQABLgAECgkJMwAEAKcXAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAABLgAECn8fAAIMAAgJyxeHHAAfAgAMAAgJyxeHHAAfAgAAAA==.Tauryel:BAAALgAECgYJDQAAAA==.',
Te='Tebook:BAABLgAECn8sAAMBAAkJLh3KRgDuAQABAAkJLh3KRgDuAQAcAAEJvwZGQQAlAAAAAA==.Telath:BAACLgAFFH8KAAIDAAQJlQntXQDWAAADAAQJlQntXQDWAAAuAAQKfyUAAgMACQk8Gf48AAACAAMACQk8Gf48AAACAAAA.Teniron:BAAALgADCgEJAgAAAA==.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8bAAIDAAgJfCJiDABcAgADAAgJfCJiDABcAgAuAAQKfyYAAgMACQm0IF4aALYCAAMACQm0IF4aALYCAAAA.Thistlechi:BAABLgAECn8nAAIbAAgJnBozEAB9AgAbAAgJnBozEAB9AgAAAA==.Thyck:BAABLgAECn8hAAINAAgJzRgSTAC+AQANAAgJzRgSTAC+AQAAAA==.Thydis:BAABLgAFFH8GAAIFAAMJhgUYHgCvAAAFAAMJhgUYHgCvAAAAAA==.',
Ti='Tibbs:BAABLgAECn8eAAIoAAkJEg5sLACLAQAoAAkJEg5sLACLAQAAAA==.Ticklepickle:BAAALgADCgkJEgABLgAECggJGwAaAGcIAA==.Timber:BAAALgAECgQJCQAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Toatasi:BAAALgADCgYJBgAAAA==.Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJDAAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAACLgAFFH8KAAIlAAMJexW6DQDdAAAlAAMJexW6DQDdAAAuAAQKfxoAAiUACAmpFl0OANABACUACAmpFl0OANABAAAA.Trumalice:BAAALgAECgIJAgAAAA==.Trysteryn:BAAALgADCgMJAwAAAA==.',
Tu='Tuckr:BAAALgADCgQJBAAAAA==.Tullamore:BAAALgAECgcJCwAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgcJDgAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQaAAcJrBHqLQBJAQAaAAYJHxHqLQBJAQAbAAUJjw3dagB+AAAHAAEJWgD1mAAbAAAAAA==.Tylerblevins:BAAALgADCgMJAwAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAFFAgJFAASAHUYAA==.',
Un='Uncorrupted:BAABLgAECn9HAAILAAkJ6h7MBACrAgALAAkJ6h7MBACrAgAAAA==.Unholymilk:BAAALgAECgEJAgAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAABLgAECn8bAAIaAAgJZwhoCgDEAAAaAAgJZwhoCgDEAAAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAABLgAECn8rAAINAAcJoBogQQDfAQANAAcJoBogQQDfAQAAAA==.Vasdepherens:BAABLgAECn8iAAIEAAkJShMJGACbAQAEAAkJShMJGACbAQAAAA==.',
Ve='Velan:BAAALgAECgEJAQAAAA==.Vermouth:BAABLgAECn8jAAMbAAgJdxGbLwBKAQAbAAgJdxGbLwBKAQAaAAYJ6AJbhwCOAAAAAA==.',
Vi='Vindrelis:BAAALgADCggJEwAAAA==.Violêt:BAABLgAECn8kAAICAAgJxwX4zgDzAAACAAgJxwX4zgDzAAAAAA==.',
Vo='Voidchris:BAABLgAFFH8JAAIDAAQJVhY8QAAnAQADAAQJVhY8QAAnAQAAAA==.Voidfang:BAAALgADCgEJAQAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgAECgUJBQAAAA==.Volkanegos:BAABLgAECn8iAAMGAAYJZwQNbwCqAAAGAAYJZwQNbwCqAAAkAAEJuwCOSwAGAAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
We='Weedmaan:BAAALgAECgUJBQAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwABLgAFFAQJCQADAFYWAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAFFAUJFgAGABoiAA==.Wizerwar:BAACLgAFFH8WAAIGAAUJGiICEACFAQAGAAUJGiICEACFAQAuAAQKf1EAAgYACQnRJFIDADYDAAYACQnRJFIDADYDAAAA.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolfie:BAAALgADCgQJBAAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAACLgAFFH8IAAICAAIJBxa9LACTAAACAAIJBxa9LACTAAAuAAQKfyQAAgIACAnCG9cDALwBAAIACAnCG9cDALwBAAAA.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgcJBwAAAA==.',
Ya='Yadiyada:BAABLgAECn8WAAIQAAgJ8hZCAgDXAQAQAAgJ8hZCAgDXAQABLgAECggJHAADABwMAA==.',
Ye='Yemudda:BAAALgAECgIJAQAAAA==.',
Yl='Ylzera:BAAALgAECgEJAgABLgAECgcJCwAhAAAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIiAAYJywg8PgC9AAAiAAYJywg8PgC9AAAAAA==.Yoshì:BAAALgAECgUJBQAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAABLgAECggJGwACAOgXAA==.Zakuren:BAACLgAFFH8HAAINAAMJPwXTHwCzAAANAAMJPwXTHwCzAAAuAAQKf1MAAg0ACQlcF8gEAJsBAA0ACQlcF8gEAJsBAAAA.',
Zi='Ziggimist:BAAALgAFFAEJAQAAAA==.',
Zo='Zombied:BAAALgAECgEJBwAAAA==.Zort:BAAALgAECgcJAQAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAABLgAECn8qAAICAAYJVBf3BwA4AQACAAYJVBf3BwA4AQAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8lAAQoAAkJSBFZNABhAQAoAAcJaRRZNABhAQAWAAUJgwnnMwDOAAApAAUJBQs3KwDDAAAAAA==.',
['Òm']='Òmêñ:BAAALgADCgkJDwAAAA==.',
['Ôj']='Ôjarg:BAAALgAECgcJEAAAAA==.',
['Ød']='Ødinson:BAAALgAECgYJCgAAAA==.',
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
