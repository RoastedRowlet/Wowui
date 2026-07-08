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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Warrior-Fury','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Evoker-Augmentation','Druid-Feral','Warrior-Protection','Mage-Fire','Evoker-Preservation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aarkein:BAAALgAECgYJBgAAAA==.',
Ab='Abiotic:BAAALgAECgEJAwAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ac='Aceofspaded:BAAALgAECgQJBwAAAA==.Acesup:BAAALgAFFAEJAQAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.Aesir:BAAALgADCgYJCAAAAA==.',
Ai='Aings:BAACLgAFFH8FAAIBAAIJqyRosADCAAABAAIJqyRosADCAAAuAAQKfzQAAgEACQkkI5YSANoCAAEACQkkI5YSANoCAAAA.',
Al='Alarus:BAAALgAECgMJAwAAAA==.Aldtris:BAAALgADCgcJCgAAAA==.Alejandro:BAAALgADCggJCAAAAA==.Aletaa:BAAALgAECgcJAQABLgAFFAUJDQACADAQAA==.Alex:BAABLgAECn83AAIDAAkJJh6BFQCXAgADAAkJJh6BFQCXAgAAAA==.Alivathor:BAAALgAECgcJCwABLgAECgcJGgAEALcKAA==.Allypally:BAABLgAECn8bAAIFAAkJig0pjwBTAQAFAAkJig0pjwBTAQAAAA==.Althir:BAABLgAECn8rAAICAAkJBSDsJQDbAgACAAkJBSDsJQDbAgAAAA==.Althorian:BAAALgAECgQJAgAAAA==.',
Am='Amgrod:BAEBLgAECn8oAAIGAAkJmQlbMgCCAQAGAAkJmQlbMgCCAQAAAA==.Amythest:BAAALgADCgkJDwAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCggJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8eAAIFAAcJ5hhseQB7AQAFAAcJ5hhseQB7AQAAAA==.',
Ar='Arfas:BAAALgAECggJDgABLgAFFAIJBQAHAE0dAA==.Arkhitype:BAABLgAECn9FAAQIAAkJJx5SAgC7AgAIAAkJJx5SAgC7AgAJAAYJuQ+xMACBAQAKAAEJGQbGKQAgAAAAAA==.Armak:BAAALgADCgEJAgAAAA==.Arwenibria:BAAALgAECgEJAQAAAA==.',
As='Ashdritha:BAAALgAECgEJAQAAAA==.Ashya:BAAALgADCgYJBgAAAA==.Asur:BAABLgAECn9BAAMFAAkJ5BO1BgCQAQAFAAkJ5BO1BgCQAQALAAgJxwZ2BgCaAAAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Auracorusca:BAABLgAECn8jAAIMAAkJeiTYAgB4AwAMAAkJeiTYAgB4AwAAAA==.Auris:BAAALgADCgQJBwAAAA==.',
Ay='Aynilith:BAAALgAECgYJCAAAAA==.Aystarael:BAAALgAECgkJBgAAAA==.',
Ba='Bajablast:BAAALgAECgEJAQAAAA==.Bajr:BAABLgAECn8qAAINAAkJjg51UwCpAQANAAkJjg51UwCpAQAAAA==.Bakura:BAABLgAECn8iAAIOAAkJzhxkBAA5AgAOAAkJzhxkBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8iAAIDAAkJORMVUgCPAQADAAkJORMVUgCPAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.Barudd:BAAALgADCgEJAQAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAACLgAFFH8MAAIPAAMJNR7oAAD4AAAPAAMJNR7oAAD4AAAuAAQKf00AAw8ACQk0JGsAAB8DAA8ACQk0JGsAAB8DAAIAAQlcEJRUATYAAAAA.Berserk:BAAALgADCgIJAgAAAA==.Bestchance:BAAALgAECgEJAQAAAA==.Beware:BAAALgADCgIJAgAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJDQABLgAFFAQJEgAQAAUfAA==.Bigbear:BAACLgAFFH8NAAIRAAUJCiAFAwBmAQARAAUJCiAFAwBmAQAuAAQKfxsAAxEACAn3I4YEAM8CABEACAn3I4YEAM8CABIABgnrFs1gABMBAAAA.Bigtamer:BAAALgADCgMJAwAAAA==.Bisan:BAAALgADCgUJBgAAAA==.',
Bj='Bjebo:BAACLgAFFH8OAAITAAQJIAagMADAAAATAAQJIAagMADAAAAuAAQKfz0AAhMACQnyFFYXABICABMACQnyFFYXABICAAAA.',
Bl='Blaank:BAACLgAFFH8MAAIFAAQJ2wWuXgDyAAAFAAQJ2wWuXgDyAAAuAAQKfx4AAgUACAlkFMRWAMcBAAUACAlkFMRWAMcBAAAA.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.Bluffshot:BAAALgAECgEJAgABLgAFFAMJCQABAFcZAA==.',
Bo='Boba:BAACLgAFFH8LAAMUAAMJiSQqLwAlAQAUAAMJiSQqLwAlAQAVAAEJ1wFvYAAtAAAuAAQKfxYAAxQABwlWJK8aAHUCABQABwlWJK8aAHUCABUABgmtH0AlAL8BAAEuAAUUCQkjABIAwR4A.Boku:BAAALgAECgEJAQAAAA==.Borealiswolf:BAABLgAFFH8LAAIWAAQJMBaMCAAwAQAWAAQJMBaMCAAwAQAAAA==.Borg:BAABLgAFFH8NAAMNAAMJZyOvSQAZAQANAAMJkSCvSQAZAQAXAAMJmxk7GwD3AAABLgAFFAQJDQADACwYAA==.',
Br='Bralaria:BAAALgAECgUJBQAAAA==.Bremena:BAAALgADCgMJAwAAAA==.Brewchew:BAACLgAFFH8GAAIHAAMJZghGEACgAAAHAAMJZghGEACgAAAuAAQKfx0AAgcACAkhET4lAIMBAAcACAkhET4lAIMBAAAA.Brutes:BAAALgAECgIJBAABLgAFFAcJIAABADshAA==.Brynjalf:BAAALgAECgUJCAAAAA==.Bràe:BAAALgAECgEJAgAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bë']='Bëärlylëgäl:BAAALgAFFAEJAwAAAA==.',
['Bï']='Bïcho:BAACLgAFFH8SAAMQAAQJBR86GwD4AAAQAAQJBR86GwD4AAAOAAIJ8gxcBgB9AAAuAAQKfzUABBAACQkpJWIFADoDABAACQkpJWIFADoDAA4AAQkAAHsfAHUAABgAAQn5GaxtADkAAAAA.',
Ca='Calambar:BAAALgAECgEJAQAAAA==.Calib:BAACLgAFFH8ZAAMVAAUJKhgVIAAfAQAVAAUJKhgVIAAfAQAUAAEJ4QOVfgA/AAAuAAQKfzEAAhUACQmwIkIMAKACABUACQmwIkIMAKACAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Casdardly:BAAALgAECgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgAECgIJAwAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQAZAKwRAA==.Cheechin:BAACLgAFFH8FAAIaAAQJVw1YHADsAAAaAAQJVw1YHADsAAAuAAQKfxoAAhoACAmfH94MAHYCABoACAmfH94MAHYCAAEuAAUUBQkaAAIAxxQA.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAACLgAFFH8PAAITAAMJ1wu8EgCfAAATAAMJ1wu8EgCfAAAuAAQKfzAAAhMACQnxGCIdAN8BABMACQnxGCIdAN8BAAAA.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn9AAAIVAAkJiCK2BwDhAgAVAAkJiCK2BwDhAgAAAA==.',
Co='Coffeeshot:BAAALgADCgEJAQAAAA==.Comboost:BAAALgAECgYJDgAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8eAAMbAAUJMCKaCQBWAQAbAAQJMCKaCQBWAQABAAEJAAC8LQEAAAAuAAQKfzcAAhsACQlCI0IAAJMDABsACQlCI0IAAJMDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.Critos:BAAALgAECgQJBAAAAA==.',
Cu='Cup:BAABLgAECn8oAAMMAAkJsB3GCwDRAgAMAAkJsB3GCwDRAgAFAAEJQBUTgwE7AAAAAA==.',
Cv='Cvv:BAAALgAECgUJBgAAAA==.',
Cy='Cyndreya:BAACLgAFFH8hAAIcAAUJyR3zFwCvAQAcAAUJyR3zFwCvAQAuAAQKf0EAAhwACQk7JFECAJYDABwACQk7JFECAJYDAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Daelaris:BAABLgAECn8jAAICAAkJwR/6EwDiAgACAAkJwR/6EwDiAgAAAA==.Damthrax:BAAALgAECgQJCAAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darknessia:BAAALgAECgEJAQAAAA==.Darmil:BAAALgADCggJEwAAAA==.Davegrôwl:BAAALgAECgUJBgABLgAECgkJNAAEAKsXAA==.Daylar:BAAALgAECgEJAQABLgAECggJIwANALwVAA==.Dazztoo:BAAALgAFFAEJAQAAAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Deadzeo:BAAALgAECgcJCQAAAA==.Deathbrand:BAAALgAECggJDwAAAA==.Dedbhang:BAABLgAFFH8KAAIBAAQJoQwQeAATAQABAAQJoQwQeAATAQAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Demonblades:BAABLgAECn8jAAIDAAkJExMIQQDFAQADAAkJExMIQQDFAQAAAA==.Demonicpixie:BAAALgAECgIJAwAAAA==.Denarten:BAAALgAECgIJAgABLgAECgcJGQAPAO8eAA==.Destructoe:BAAALgAECgUJCwAAAA==.Devotegoat:BAAALgAECgUJCAAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtyalba:BAAALgAECgYJBgAAAA==.Dirtymorris:BAACLgAFFH8HAAMdAAQJIRHwJgDEAAAdAAMJ9QvwJgDEAAAeAAEJYQeKFwA1AAAuAAQKfy4AAx0ACQkTEZgcAOABAB0ACQkTEZgcAOABAB4ABwk6FoAwAH8BAAAA.',
Do='Docignis:BAABLgAECn8XAAIVAAgJXA/xQgAnAQAVAAgJXA/xQgAnAQAAAA==.Dockevorkian:BAACLgAFFH8nAAIeAAUJMSO8BwDXAQAeAAUJMSO8BwDXAQAuAAQKfzQAAh4ACQlBIjoGAOsCAB4ACQlBIjoGAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECggJFwAVAFwPAA==.Docrhada:BAAALgAECgQJBQABLgAECggJFwAVAFwPAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAABLgAECn8ZAAIDAAgJUhwOLAAYAgADAAgJUhwOLAAYAgABLgAFFAcJIAABADshAA==.',
Dr='Dracoradk:BAAALgAECgYJBwABLgAFFAQJCAAaAEoGAA==.Dracoramonk:BAABLgAFFH8IAAIaAAQJSgZGJQC+AAAaAAQJSgZGJQC+AAAAAA==.Dragonchris:BAAALgAFFAIJAgABLgAFFAQJDQADACwYAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Draxus:BAAALgAECggJCAAAAA==.Drayvn:BAAALgADCgIJAgAAAA==.Drdisco:BAAALgAECgUJBQAAAA==.Dricex:BAAALgAECgYJCwAAAA==.Drinnagon:BAAALgAECgUJDAABLgAECgcJGQAPAO8eAA==.Drinnaqua:BAAALgADCgUJBQABLgAECgcJGQAPAO8eAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAPAO8eAA==.Drinntellect:BAABLgAECn8ZAAMPAAcJ7x6rBQDPAQAPAAYJCh+rBQDPAQACAAcJ1RpqhwDDAQAAAA==.Drraxx:BAAALgAECgUJBQAAAA==.Drunkdino:BAAALgADCgUJBQAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Duningkruger:BAAALgADCgcJBwABLgAFFAMJCwAWAKYIAA==.Dunnstunns:BAAALgAECgIJAgAAAA==.Duskwälker:BAAALgAECgEJAQAAAA==.',
Dx='Dxanatos:BAABLgAECn8pAAIfAAkJiQhQEQBFAQAfAAkJiQhQEQBFAQAAAA==.',
['Dø']='Døuce:BAAALgADCgUJAwAAAA==.',
Ea='Eamass:BAABLgAECn8rAAIHAAkJSSGrBgDPAgAHAAkJSSGrBgDPAgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.Eiré:BAAALgADCgQJBAAAAA==.',
Ej='Ejunk:BAAALgAECgYJCAAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn87AAIEAAkJixCvGgCIAQAEAAkJixCvGgCIAQAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJFwACAG0VAA==.',
En='Enanthate:BAAALgADCgMJBQABLgAECgUJBgAgAAAAAA==.Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8gAAQBAAcJOyFoIQDrAQABAAcJxx5oIQDrAQAbAAQJvB+YBwB0AQAEAAEJAADHUAAAAAAuAAQKfysAAwEACQm6I0cNADADAAEACQmLI0cNADADABsAAQmgJFUvAGIAAAAA.Enthing:BAACLgAFFH8hAAIDAAUJeBWeQAAmAQADAAUJeBWeQAAmAQAuAAQKf0EAAgMACQkVIakNANgCAAMACQkVIakNANgCAAAA.',
Es='Essamond:BAAALgAECgQJBAAAAA==.',
Ev='Evellara:BAAALgAECgUJCAABLgAECgkJNAAEAKsXAA==.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAABLgAECn8cAAIeAAgJPyZlAwBZAwAeAAgJPyZlAwBZAwAAAA==.Famiki:BAAALgAECgUJCAAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatalxclaw:BAAALgADCgIJAgAAAA==.Fatboycurt:BAAALgADCgIJAgAAAA==.Fatheral:BAABLgAECn8bAAIdAAkJpBVgHwDKAQAdAAkJpBVgHwDKAQAAAA==.',
Fe='Felaxare:BAAALgAECgcJDQAAAA==.Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8rAAQDAAkJaB7MMAADAgAhAAgJlhqkFwALAgADAAgJbxvMMAADAgAiAAYJCBiIDQB+AQAAAA==.Fenraged:BAAALgAECgEJAQABLgAECgkJJQAOAP0lAA==.Fentagram:BAABLgAECn8lAAMOAAkJ/SX7AQCyAgAOAAgJdSb7AQCyAgAQAAQJUiIUlgAQAQAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgAECgIJAgAAAA==.',
Fl='Floofwall:BAACLgAFFH8FAAIHAAIJTR10EgCDAAAHAAIJTR10EgCDAAAuAAQKfyQAAwcACAn+HrsNAF0CAAcACAn+HrsNAF0CABoAAQnIEuuWADkAAAAA.Floralcarer:BAAALgAECgYJBgAAAA==.',
Fo='Follet:BAAALgAECgYJBgAAAA==.Fontss:BAAALgAECgQJBAAAAA==.Fonyfish:BAACLgAFFH8LAAIQAAUJLB3JOQBjAQAQAAUJLB3JOQBjAQAuAAQKf0AAAxAACQkUIyAIABUDABAACQkUIyAIABUDABgAAgmwEm5RAHoAAAAA.Fonytime:BAAALgAECgYJBgABLgAFFAUJCwAQACwdAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8sAAQYAAkJiRDaDgBQAQAQAAgJ6AvobwBbAQAYAAgJwRDaDgBQAQAOAAEJAABzSgAAAAAAAA==.Foxydots:BAAALgADCgcJCgAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgAECgMJAwABLgAECgkJNAAEAKsXAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAECLgAFFH8KAAMaAAMJ/BTWCwCjAAAaAAMJ/BTWCwCjAAAZAAIJWQsAJgBfAAAuAAQKfzsABBoACQmZIl8LAI0CABoACQmZIl8LAI0CAAcABwmeEu4yADQBABkAAQkeCgXOACEAAAAA.Fulgurithm:BAAALgAECgIJAwABLgAECgkJJQAOAP0lAA==.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Ga='Galdran:BAAALgAECgEJAQAAAA==.',
Gg='Ggakkaltigad:BAAALgAECggJCgAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8gAAIGAAgJgxpaBgADAgAGAAgJgxpaBgADAgAuAAQKfysAAwYACAnyJHQHADEDAAYACAndJHQHADEDACMAAgnRGUspAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8XAAIVAAYJhBkXVgDiAAAVAAYJhBkXVgDiAAABLgAFFAUJHgAbADAiAA==.Glorm:BAABLgAECn8oAAIUAAkJtw40PQC5AQAUAAkJtw40PQC5AQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAABLgAECn80AAMEAAkJqxfxFwClAQAEAAkJXxfxFwClAQABAAcJPA8OEwDCAAAAAA==.Grantul:BAABLgAECn8pAAIGAAkJXhzPFgCWAgAGAAkJXhzPFgCWAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAABLgAECn8VAAIDAAYJEh5BUACVAQADAAYJEh5BUACVAQABLgAFFAUJDQARAAogAA==.Grimthore:BAAALgAECgQJBgABLgAECggJLwAFALoYAA==.Grolgan:BAABLgAECn8jAAINAAgJvBXxVAClAQANAAgJvBXxVAClAQAAAA==.Growlings:BAABLgAECn8yAAITAAgJ2ByZEQBNAgATAAgJ2ByZEQBNAgAAAA==.',
Gu='Gueva:BAAALgAFFAQJBAAAAA==.Guilarth:BAAALgAECgkJAgAAAA==.Gulbhang:BAAALgAECgUJBQAAAA==.Guncow:BAAALgAECgEJAQAAAA==.',
Gw='Gwaela:BAAALgAECgMJAwAAAA==.',
Ha='Hailmary:BAAALgADCgIJAgAAAA==.Haradave:BAAALgAECgIJAgAAAA==.Hawktuâh:BAAALgADCgEJAQABLgAECgkJNAAEAKsXAA==.',
He='Healiostrasz:BAAALgAECgQJBgAAAA==.Health:BAAALgAECgQJBgAAAA==.Healyeah:BAABLgAFFH8FAAIkAAMJMQr1GQCqAAAkAAMJMQr1GQCqAAABLgAFFAIJBQAHAE0dAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Henrock:BAAALgAECgEJAgAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgYJCwABLgAECgkJKAAFAAwXAA==.Holyczar:BAAALgADCgkJGwAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hr='Hruun:BAAALgADCgIJAgAAAA==.',
Hu='Hubirt:BAABLgAECn8mAAIFAAgJ/hhNYwCpAQAFAAgJ/hhNYwCpAQAAAA==.Huch:BAAALgAECgUJBQAAAA==.Huntsybuntsy:BAACLgAFFH8OAAMWAAUJxBVmCQAlAQAWAAUJxBVmCQAlAQAVAAIJvQILTwBbAAAuAAQKfzgAAxYACQlgIJkCAO8CABYACQlgIJkCAO8CABUACAkzFoQbADYCAAAA.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJFwACAG0VAA==.',
Hy='Hydrafoil:BAAALgAECggJEgAAAA==.',
Ia='Ianthel:BAAALgAECgUJCwAAAA==.',
Ic='Icesloth:BAABLgAECn8jAAIVAAkJHxm7EwBOAgAVAAkJHxm7EwBOAgAAAA==.',
Id='Idamae:BAABLgAECn8mAAICAAkJmAL50ADwAAACAAkJmAL50ADwAAAAAA==.Iduun:BAAALgAECgUJDQAAAA==.',
Il='Iladelle:BAABLgAECn8mAAIDAAkJ+hB3SACtAQADAAkJ+hB3SACtAQAAAA==.Illidabina:BAEALgAFFAIJBAABLgAFFAMJCgAaAPwUAA==.',
In='Inariokami:BAABLgAECn8XAAIHAAkJKAnCKwBbAQAHAAkJKAnCKwBbAQAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.Inposter:BAAALgAECgYJBwAAAA==.',
Io='Iorak:BAAALgADCgYJBgAAAA==.',
Ir='Irinon:BAABLgAECn8UAAIQAAYJtw0WCgD4AAAQAAYJtw0WCgD4AAAAAA==.Irocky:BAAALgADCgkJCQAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgQJCQAAAA==.',
Ja='Jaaygee:BAACLgAFFH8FAAIKAAIJcxTfDACSAAAKAAIJcxTfDACSAAAuAAQKfxoAAgoABwmwH6gEADACAAoABwmwH6gEADACAAEuAAQKCQk3ABAAfCMA.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAACLgAFFH8UAAIQAAUJyiAMCgC9AQAQAAUJyiAMCgC9AQAuAAQKfzkAAxAACQkgIrcLAPACABAACQkgIrcLAPACABgACAlbGf4EAIsCAAAA.Jaggerss:BAAALgAFFAIJAQABLgAFFAcJIAABADshAA==.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8bAAIeAAcJLhPaKwBrAQAeAAcJLhPaKwBrAQAAAA==.',
Jb='Jbsvoid:BAAALgAECgEJAQAAAA==.',
Je='Jelliebean:BAAALgADCgYJBgAAAA==.Jessalba:BAAALgAECgMJBAAAAA==.Jessalbaa:BAAALgAECgQJBAAAAA==.Jestorian:BAAALgAECgcJEwAAAA==.',
Ji='Jimmym:BAAALgAECgIJAwAAAA==.Jirakaidae:BAABLgAECn8hAAITAAkJlQelCQCjAAATAAkJlQelCQCjAAABLgAECgUJCwAgAAAAAA==.',
Jo='Jockinonmytw:BAACLgAFFH8MAAIJAAQJqSGYFwBSAQAJAAQJqSGYFwBSAQAuAAQKf0EAAgkACQlDJY0CADEDAAkACQlDJY0CADEDAAAA.Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCwAAAA==.Juicyfists:BAAALgAECgEJBAAAAA==.Justred:BAABLgAECn8VAAMGAAYJeRTqSQAeAQAGAAYJeRTqSQAeAQAjAAMJaA9STwCVAAAAAA==.',
Jx='Jxson:BAACLgAFFH8GAAMTAAIJIhTiPQB8AAATAAIJIhTiPQB8AAASAAEJ1AZ2dQAwAAAuAAQKfyYABREABgkAIFgTAL8BABEABgm3H1gTAL8BABIABgnFFGRXAEwBABMABgkIEvhDAPwAACUAAwl+Ej4jALwAAAEuAAQKCQk3ABAAfCMA.Jxsong:BAACLgAFFH8HAAIcAAIJIBWLPACJAAAcAAIJIBWLPACJAAAuAAQKfxsAAxwABgmjHuQXABUCABwABgmjHuQXABUCAB0ABAnQE7dVALwAAAEuAAQKCQk3ABAAfCMA.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ka='Kaisel:BAAALgAECgcJCAAAAA==.Kandrys:BAAALgAECgIJAgAAAA==.Kankles:BAABLgAECn8yAAMUAAkJfh7kCwD8AgAUAAkJfh7kCwD8AgAWAAQJZwjtLQCJAAAAAA==.Kanoa:BAAALgADCgYJBgAAAA==.Kantuo:BAAALgAFFAQJBAAAAA==.Kattschitt:BAAALgAECgEJAQAAAA==.',
Ke='Keanx:BAAALgAFFAEJAQAAAA==.Kehila:BAAALgADCgEJAQAAAA==.Kendorwar:BAAALgAECgkJBAAAAA==.',
Kh='Khelad:BAACLgAFFH8jAAIFAAUJCxowFQAOAQAFAAUJCxowFQAOAQAuAAQKfxoAAwUACQkcGqlSANEBAAUACQkcGqlSANEBAAsAAQk+CxBYACAAAAAA.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAABLgAECn8iAAIHAAgJFh0eAQDuAQAHAAgJFh0eAQDuAQAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killau:BAAALgAECgEJAQAAAA==.Killt:BAABLgAECn8gAAIUAAkJxRQvIgASAgAUAAkJxRQvIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAABLgAECn8lAAMmAAkJkA8BBADsAAAmAAgJKBABBADsAAAjAAEJbAvIDwAqAAAAAA==.',
Ku='Kurzulan:BAAALgAECgQJCAABLgAECgYJCQAgAAAAAA==.',
Ky='Kynthe:BAAALgAECggJDgAAAA==.Kyongye:BAAALgAECgkJDQAAAA==.',
La='Lacerater:BAAALgADCgcJCgAAAA==.Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8jAAMNAAUJ5x0HFAA3AQANAAUJ5x0HFAA3AQAfAAIJ7AhvIACTAAAuAAQKf0oAAw0ACQl4JMcFADcDAA0ACQl4JMcFADcDAB8ACAkEG54aAFUCAAAA.',
Le='Leadgut:BAEALgADCgQJBwAAAA==.Lemanjá:BAABLgAECn83AAIfAAkJTxT0AACbAQAfAAkJTxT0AACbAQAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Lilfurrybast:BAAALgADCgEJAQAAAA==.Liliane:BAABLgAECn8dAAMLAAkJkQzNIQAGAQAFAAYJ8QfUvgAKAQALAAgJMAzNIQAGAQAAAA==.Lillatheen:BAAALgAECgYJCAAAAA==.Limbless:BAAALgAECgYJDAABLgAECgYJDQAgAAAAAA==.Littletoast:BAAALgAECgYJBwAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockrocks:BAAALgAECgUJDAABLgAECggJLwAFALoYAA==.Lockstar:BAAALgADCgUJDAABLgAECggJDwAgAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAABLgAECn8eAAITAAYJfQwWCwCIAAATAAYJfQwWCwCIAAAAAA==.Loozer:BAABLgAECn8vAAMFAAgJuhgCUgDTAQAFAAgJuhgCUgDTAQALAAcJVQqgKQDMAAAAAA==.',
Lu='Lulutauren:BAAALgAECgEJAQAAAA==.Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAABLgAECn8gAAIFAAYJYxB5rgAhAQAFAAYJYxB5rgAhAQAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8mAAMBAAkJxxrOKQBZAgABAAkJxxrOKQBZAgAbAAEJywjmGAAsAAAAAA==.',
Ma='Magelyman:BAACLgAFFH8FAAICAAIJWhF0ngCPAAACAAIJWhF0ngCPAAAuAAQKfyEAAgIACQkAG/UrAGoCAAIACQkAG/UrAGoCAAAA.Magetiger:BAABLgAECn8iAAICAAkJ6xWHPgAiAgACAAkJ6xWHPgAiAgAAAA==.Magoshon:BAAALgAECgIJAQABLgAECgQJBAAgAAAAAA==.Magsh:BAAALgADCgQJBAAAAA==.Malitheion:BAABLgAECn8WAAMBAAgJKwo/sAAUAQABAAgJBQo/sAAUAQAEAAMJ4wFkVQBFAAAAAA==.Malyce:BAAALgAFFAIJAgAAAA==.Malzen:BAABLgAECn8VAAMHAAgJARfvIgCSAQAHAAgJARfvIgCSAQAaAAEJ9AtBpQArAAABLgAFFAIJAgAgAAAAAA==.Manaleia:BAAALgAECgQJBwAAAA==.Manasolid:BAABLgAECn9JAAICAAkJzBvDAgBrAgACAAkJzBvDAgBrAgAAAA==.Mangeømbre:BAAALgAECgQJBAAAAA==.Mar:BAAALgAECgMJBwAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgAECgcJDgAAAA==.Masculinedh:BAAALgAECgIJAwABLgAECgUJBgAgAAAAAA==.Masquèrade:BAAALgAECgEJAQAAAA==.',
Me='Meanka:BAAALgAECgEJAQABLgAFFAMJCgAdAOYeAA==.Meatcurtin:BAAALgADCgkJGAAAAA==.Meches:BAAALgAECgQJCAABLgAECgkJSAASAKkVAA==.Mediocre:BAAALgAECgIJAgAAAA==.Mediocritty:BAAALgAECgYJCgABLgAFFAMJCwAWAKYIAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAABLgAECn9IAAICAAkJGBCgCQBRAQACAAkJGBCgCQBRAQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Meraleona:BAAALgAECgUJBQABLgAECgkJLAABAC4dAA==.Methslinger:BAABLgAECn8gAAIVAAgJ/wzWUAD0AAAVAAgJ/wzWUAD0AAAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Mihra:BAAALgAECgEJAQAAAA==.Milkwithpulp:BAABLgAECn8kAAIeAAgJ/xUPHwDMAQAeAAgJ/xUPHwDMAQAAAA==.Miltonroe:BAAALgADCggJBQABLgAFFAMJCwAWAKYIAA==.Mistynollid:BAAALgADCgYJBgABLgAECgkJKwADAGgeAA==.',
Mk='Mkoons:BAAALgAECgEJBAAAAA==.',
Mo='Monkanical:BAAALgADCgkJEwAAAA==.Mook:BAABLgAECn8cAAIDAAgJHAx9bwBEAQADAAgJHAx9bwBEAQAAAA==.Morbious:BAAALgAECgMJBQAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAABLgAECn8WAAIYAAcJBQYNIACsAAAYAAcJBQYNIACsAAAAAA==.Mortmuzi:BAAALgAECgUJDAAAAA==.Mosrael:BAAALgAECgkJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.Mourningveil:BAAALgADCggJCAAAAA==.',
Mu='Mulas:BAABLgAECn8kAAIQAAkJqxYHLAApAgAQAAkJqxYHLAApAgAAAA==.Muldah:BAACLgAFFH8aAAICAAUJxxRqXAAmAQACAAUJxxRqXAAmAQAuAAQKfzEAAgIACQlrIC8eAKgCAAIACQlrIC8eAKgCAAAA.',
My='Mynte:BAABLgAECn8eAAIeAAYJnBL5NQApAQAeAAYJnBL5NQApAQAAAA==.',
['Mâ']='Mâlice:BAAALgAECgIJAgAAAA==.',
['Mä']='Mäsion:BAABLgAFFH8HAAIGAAQJtwPJNwDTAAAGAAQJtwPJNwDTAAAAAA==.',
Na='Natty:BAAALgADCgkJJQAAAA==.Navie:BAABLgAECn8+AAIcAAkJNBXoEQBXAgAcAAkJNBXoEQBXAgAAAA==.Nawperwoman:BAABLgAECn8oAAMaAAgJvhvtEgBcAgAaAAgJvhvtEgBcAgAZAAEJrgGhdgAYAAAAAA==.Nazevroth:BAAALgAECgcJCwAAAA==.Nazgûl:BAABLgAFFH8JAAIBAAUJmxR7NwDFAAABAAUJmxR7NwDFAAAAAA==.',
Ne='Necronomicob:BAABLgAECn81AAQQAAkJsxn9JwA8AgAQAAkJsxn9JwA8AgAYAAQJ7RieGQDWAAAOAAMJ/BK9JwCEAAAAAA==.Neil:BAAALgADCgUJBQABLgAFFAUJGAAUABwMAA==.Nekros:BAABLgAECn86AAQQAAkJ5h4kGQCNAgAQAAgJNx4kGQCNAgAYAAQJaBxUJQAyAQAOAAMJTxsGHADeAAAAAA==.Neø:BAABLgAECn84AAMBAAkJ+RecLABNAgABAAkJ+RecLABNAgAbAAMJoArXMQBVAAAAAA==.',
Ni='Nianna:BAAALgADCgcJCgAAAA==.Nicebud:BAABLgAECn8VAAIDAAkJaxRUOwDaAQADAAkJaxRUOwDaAQAAAA==.Nightsfury:BAABLgAECn8gAAIFAAgJGQ5JhQBlAQAFAAgJGQ5JhQBlAQAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAABLgAECn8aAAIEAAcJtwomNgC+AAAEAAcJtwomNgC+AAAAAA==.Nollid:BAAALgAECgEJAQABLgAECgkJKwADAGgeAA==.Nordburg:BAAALgAECgEJAQAAAA==.Nornyr:BAABLgAECn8tAAIZAAkJmhdPHQAuAgAZAAkJmhdPHQAuAgAAAA==.Notforgiven:BAAALgAECgEJAQAAAA==.Notnonna:BAAALgAECgEJAgAAAA==.Noxiss:BAAALgADCgQJBAABLgAECgkJLAABAC4dAA==.',
Nu='Nunsrsus:BAAALgADCgYJDgABLgAECgYJFQAGAHkUAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn9MAAITAAkJKhNDAgC6AQATAAkJKhNDAgC6AQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oriax:BAABLgAECn8yAAIQAAgJ+RWTCAAYAQAQAAgJ+RWTCAAYAQAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgYJCgAAAA==.',
Pa='Paean:BAABLgAECn8UAAIZAAYJ8BMgEgCjAAAZAAYJ8BMgEgCjAAAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8mAAMSAAgJZgRbhwCpAAASAAgJZgRbhwCpAAATAAQJ+gIjewBQAAAAAA==.',
Pb='Pbj:BAAALgAECgEJAQAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBwAgAAAAAA==.Peata:BAAALgAECgUJDAAAAA==.Persephones:BAABLgAECn8fAAIdAAcJ4A/eJwCaAQAdAAcJ4A/eJwCaAQAAAA==.Perseus:BAAALgADCgkJCQAAAA==.',
Ph='Phenelope:BAABLgAECn8ZAAMCAAgJTgO90QDvAAACAAgJTgO90QDvAAAnAAcJnAHhDgBwAAAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECgkJFwAHACgJAA==.Pillowpuhmpa:BAAALgAECgIJBAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgAECgIJAgAAAA==.',
Pk='Pkalygos:BAABLgAECn8eAAIoAAkJlRPtDwDMAQAoAAkJlRPtDwDMAQAAAA==.',
Po='Polaka:BAAALgAECgkJAQAAAA==.Poosnwoods:BAAALgAECgYJDgAAAA==.Popefuffer:BAAALgAFFAMJAQAAAA==.Powerfist:BAAALgAECgMJAwAAAA==.Powerstrokee:BAABLgAECn8aAAMBAAcJGRS8eAByAQABAAcJGRS8eAByAQAbAAIJEQ8WMQBZAAAAAA==.',
Pr='Preyforme:BAAALgAECgYJEgAAAA==.Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAIMAAgJrRzoEQCDAgAMAAgJrRzoEQCDAgAAAA==.Protadin:BAABLgAECn8YAAILAAYJwBQUFwBjAQALAAYJwBQUFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAABLgAECn8ZAAMMAAcJbgphTgAAAQAMAAYJAAxhTgAAAQAFAAIJBQifhQE5AAAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôcky:BAAALgAECgEJAQABLgAECgkJKwAHAEkhAA==.Pôps:BAAALgAECgYJEwAAAA==.',
Qu='Quickprick:BAAALgAECgcJEwAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAABLgAFFAMJBAAgAAAAAA==.Ranharr:BAAALgADCgQJBAAAAA==.Rasina:BAAALgAECgIJBAAAAA==.Ratkìng:BAAALgAECgMJBAAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Redcrayons:BAAALgADCgkJCQAAAA==.Reknojir:BAAALgAECgQJBgAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8jAAIDAAUJeRr4OQA9AQADAAUJeRr4OQA9AQAuAAQKfz4AAwMACQkzIfAJAPsCAAMACQkzIfAJAPsCACEABgkAEcs6ABUBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Rh='Rhade:BAAALgAECgMJAwAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgkJDgAAAA==.Rizar:BAAALgAECgUJCgAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgYJDQAgAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn9WAAIRAAkJXgOoCQCKAAARAAkJXgOoCQCKAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.Rottenbeef:BAAALgAECgUJAwAAAA==.',
Ru='Rumhanced:BAAALgADCgkJCQAAAA==.Runeclad:BAABLgAECn8cAAIBAAkJnRW2QQD+AQABAAkJnRW2QQD+AQAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámi:BAAALgAECgEJAQAAAA==.',
['Rï']='Rïvkah:BAAALgADCgcJDgAAAA==.',
Sa='Saauurrora:BAAALgAECgcJCwAAAA==.Sabiton:BAAALgADCgYJCgAAAA==.Sadistikult:BAAALgADCgIJAgAAAA==.Saintshift:BAAALgAECgMJAwABLgAECgUJBgAgAAAAAA==.Salitheion:BAABLgAECn8uAAIMAAgJ+hhnGQA7AgAMAAgJ+hhnGQA7AgAAAA==.Saloraith:BAAALgAECgcJEwAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Salôis:BAAALgAECgYJBwAAAA==.Sanaig:BAAALgADCgcJBwAAAA==.Sanatura:BAAALgAECgYJCwAAAA==.Sapper:BAABLgAECn8wAAIZAAkJ4CAfCAAaAwAZAAkJ4CAfCAAaAwAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgQJCwAAAA==.Sarn:BAABLgAECn8bAAIRAAkJpxI3DwCIAQARAAkJpxI3DwCIAQAAAA==.Sathi:BAAALgAECgcJAgAAAA==.Saudhum:BAABLgAECn8WAAMOAAYJwRsfCADLAQAOAAYJwRsfCADLAQAQAAQJ4Q3K4gCWAAAAAA==.Sayuri:BAABLgAECn84AAMZAAkJfyEaBQBaAwAZAAkJfyEaBQBaAwAaAAIJXANfwAAYAAAAAA==.',
Sb='Sboop:BAAALgAECgQJBwAAAA==.',
Sc='Scrím:BAAALgAECgIJBQAAAA==.',
Se='Secondchance:BAAALgAECgIJBQAAAA==.Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shadowmoocow:BAAALgADCgkJEgABLgAECgYJDgAgAAAAAA==.Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn81AAIUAAkJswanWgBOAQAUAAkJswanWgBOAQAAAA==.Sheriam:BAAALgADCgcJBwABLgAECgEJAQAgAAAAAA==.Shikí:BAAALgAECgMJBgAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn9AAAIjAAkJjhVMGACYAQAjAAkJjhVMGACYAQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAACLgAFFH8SAAImAAQJMQ8mFwDiAAAmAAQJMQ8mFwDiAAAuAAQKfyYAAiYACQlaFG8SAMQBACYACQlaFG8SAMQBAAAA.Shotsshots:BAABLgAECn8vAAQNAAkJDB9MHwBrAgANAAkJDB9MHwBrAgAXAAIJGgycUABtAAAfAAEJAAC1kQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgAECgEJAQAAAA==.Sicaria:BAABLgAECn8WAAMjAAUJ6xkJLAAbAQAjAAUJ6xkJLAAbAQAGAAEJ5woMqgAsAAAAAA==.Sindina:BAAALgADCgYJBgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDgAAAA==.Skully:BAACLgAFFH8SAAIHAAQJUSWtEQCXAQAHAAQJUSWtEQCXAQAuAAQKfzUAAwcACQlfJSICAEADAAcACQlfJSICAEADABkAAglLFg0gAEMAAAEuAAUUBQkNABEACiAA.',
Sl='Slamdh:BAAALgAECgkJCgABLgAFFAIJBwAJAAgdAA==.Slicedup:BAAALgAECgMJAwABLgAECggJDwAgAAAAAA==.Sluffshot:BAACLgAFFH8JAAIBAAMJVxlfKwDtAAABAAMJVxlfKwDtAAAuAAQKfy0AAwQACQnoIPcIAIQCAAQACQloIPcIAIQCAAEABAljHTu3ABQBAAAA.',
Sn='Snorina:BAACLgAFFH8KAAIdAAMJ5h4eHwD6AAAdAAMJ5h4eHwD6AAAuAAQKfzgAAh0ACQkQJUEDAC4DAB0ACQkQJUEDAC4DAAAA.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solarex:BAAALgAFFAIJAgAAAA==.Solina:BAAALgAECgcJBwAAAA==.Solsteece:BAAALgADCgYJDwAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAACLgAFFH8FAAIHAAIJ1wksEwB5AAAHAAIJ1wksEwB5AAAuAAQKf0EAAwcACQl6HKUJAJcCAAcACQl6HKUJAJcCABoAAwnGBwxxAG4AAAAA.Sosopie:BAAALgAECgQJBAAAAA==.Sosozen:BAABLgAECn8mAAIaAAkJxQ7VIgCaAQAaAAkJxQ7VIgCaAQAAAA==.Soul:BAAALgAECgcJEAAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgcJEAAgAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Sparkgrace:BAAALgADCgEJAQAAAA==.Spellbinder:BAAALgAECgEJAgABLgAECggJLwAFALoYAA==.Spirittoast:BAAALgAECgYJEwAAAA==.Spluffshot:BAAALgAECgIJAgAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAABLgAECn8bAAICAAkJkg1YZwCuAQACAAkJkg1YZwCuAQAAAA==.',
Sq='Squelch:BAAALgAECgQJEgAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Stratovarius:BAAALgAECgUJBQAAAA==.Strumpet:BAAALgAECgQJBQAAAA==.',
Su='Sulkendov:BAAALgAFFAEJAQAAAA==.Summuner:BAAALgAECgUJBgAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAABLgAECn8YAAINAAkJYxykGACTAgANAAkJYxykGACTAgABLgAECggJLwAFALoYAA==.Swytch:BAABLgAECn8pAAIIAAkJ8xfgBQATAgAIAAkJ8xfgBQATAgAAAA==.',
Sy='Sylrytherin:BAABLgAECn8WAAMTAAcJqRokHQAXAgATAAcJqRokHQAXAgARAAEJAAAWlQAAAAABLgAFFAMJCgAdAOYeAA==.Sylvii:BAABLgAECn9IAAMSAAkJqRV9HQBaAgASAAkJqRV9HQBaAgATAAgJAhU5AwB2AQAAAA==.',
Ta='Tabor:BAABLgAECn8fAAMSAAgJgxtdHwBLAgASAAgJgxtdHwBLAgARAAEJuApngQAgAAAAAA==.Takachance:BAAALgAECgIJBAAAAA==.Talio:BAAALgAECgEJAgAAAA==.Tammyfaye:BAAALgAECgEJAQABLgAECgkJNAAEAKsXAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAABLgAECn8gAAIMAAgJ+heHHAAfAgAMAAgJ+heHHAAfAgAAAA==.Tauryel:BAAALgAECgYJDQAAAA==.',
Te='Tebook:BAABLgAECn8sAAMBAAkJLh3KRgDuAQABAAkJLh3KRgDuAQAbAAEJvwZGQQAlAAAAAA==.Telath:BAACLgAFFH8KAAIDAAQJlQntXQDWAAADAAQJlQntXQDWAAAuAAQKfyUAAgMACQk8Gf48AAACAAMACQk8Gf48AAACAAAA.Teniron:BAAALgADCgEJAgAAAA==.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8bAAIDAAgJfCJiDABcAgADAAgJfCJiDABcAgAuAAQKfyYAAgMACQm0IF4aALYCAAMACQm0IF4aALYCAAAA.Thistlechi:BAABLgAECn8nAAIaAAgJnBozEAB9AgAaAAgJnBozEAB9AgAAAA==.Thyck:BAABLgAECn8hAAINAAgJzRgSTAC+AQANAAgJzRgSTAC+AQAAAA==.Thydis:BAABLgAFFH8IAAIFAAMJhgXzKwCoAAAFAAMJhgXzKwCoAAAAAA==.',
Ti='Tibbs:BAABLgAECn8eAAIkAAkJEg5sLACLAQAkAAkJEg5sLACLAQAAAA==.Ticklepickle:BAAALgADCgkJEgABLgAECgkJJAAaANEIAA==.Timber:BAAALgAECgUJCgAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Toatasi:BAAALgADCgYJBgAAAA==.Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJDAAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAACLgAFFH8KAAIlAAMJexW6DQDdAAAlAAMJexW6DQDdAAAuAAQKfxoAAiUACAmpFl0OANABACUACAmpFl0OANABAAAA.Trumalice:BAAALgAECgIJAgAAAA==.Trysteryn:BAAALgADCgMJAwAAAA==.',
Tu='Tuckr:BAAALgADCgQJBAAAAA==.Tullamore:BAAALgAECgcJCwAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgcJDgAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQZAAcJrBHqLQBJAQAZAAYJHxHqLQBJAQAaAAUJjw3dagB+AAAHAAEJWgD1mAAbAAAAAA==.Tylerblevins:BAAALgADCgMJAwAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAFFAgJFAASAHUYAA==.',
Un='Uncorrupted:BAACLgAFFH8FAAILAAMJ3RuZAgDxAAALAAMJ3RuZAgDxAAAuAAQKf0wAAgsACQmnH8wEAKsCAAsACQmnH8wEAKsCAAAA.Unholymilk:BAAALgAECgEJAgAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAABLgAECn8kAAMaAAkJ0QhgAwA4AQAaAAkJ0QhgAwA4AQAZAAgJZwhMDwDCAAAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAABLgAECn8rAAINAAcJoBogQQDfAQANAAcJoBogQQDfAQAAAA==.Vasdepherens:BAABLgAECn8iAAIEAAkJShMJGACbAQAEAAkJShMJGACbAQAAAA==.',
Ve='Velan:BAAALgAECgEJAQAAAA==.Vermouth:BAABLgAECn8jAAMaAAgJdxGbLwBKAQAaAAgJdxGbLwBKAQAZAAYJ6AJbhwCOAAAAAA==.',
Vi='Vindrelis:BAAALgADCggJEwAAAA==.Violêt:BAABLgAECn8kAAICAAgJxwX4zgDzAAACAAgJxwX4zgDzAAAAAA==.',
Vo='Voidchris:BAABLgAFFH8NAAIDAAQJLBjeFgAWAQADAAQJLBjeFgAWAQAAAA==.Voidfang:BAAALgADCgEJAQAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgAECgUJBQAAAA==.Volkanegos:BAABLgAECn8iAAMGAAYJZwQNbwCqAAAGAAYJZwQNbwCqAAAjAAEJuwCOSwAGAAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
We='Weedmaan:BAAALgAECgUJBQAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwABLgAFFAQJDQADACwYAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wispywillòw:BAAALgAECgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAFFAUJFgAGABoiAA==.Wizerwar:BAACLgAFFH8WAAIGAAUJGiICEACFAQAGAAUJGiICEACFAQAuAAQKf1EAAgYACQnRJFIDADYDAAYACQnRJFIDADYDAAAA.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolfie:BAAALgADCgQJBAAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAACLgAFFH8LAAICAAMJlxFMLADSAAACAAMJlxFMLADSAAAuAAQKfyQAAgIACAnCG40FALkBAAIACAnCG40FALkBAAAA.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgcJBwAAAA==.',
Ya='Yadiyada:BAABLgAECn8WAAIQAAgJ5BZmAwDRAQAQAAgJ5BZmAwDRAQABLgAECggJHAADABwMAA==.',
Ye='Yemudda:BAAALgAECgIJAQAAAA==.',
Yl='Ylzera:BAAALgAECgEJAgABLgAECggJDAAgAAAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIhAAYJywg8PgC9AAAhAAYJywg8PgC9AAAAAA==.Yoshì:BAAALgAECgUJBQAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAABLgAECggJGwACAOgXAA==.Zakuren:BAACLgAFFH8IAAINAAMJUAWrKwC6AAANAAMJUAWrKwC6AAAuAAQKf1sAAg0ACQlhF6MEAOgBAA0ACQlhF6MEAOgBAAAA.',
Zi='Ziggimist:BAAALgAFFAEJAQAAAA==.',
Zo='Zombied:BAAALgAECgEJBwAAAA==.Zort:BAAALgAECgcJAQAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAABLgAECn8qAAICAAYJVBesCwA0AQACAAYJVBesCwA0AQAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8lAAQkAAkJSBFZNABhAQAkAAcJaRRZNABhAQAoAAUJgwnnMwDOAAApAAUJBQs3KwDDAAAAAA==.',
['Òm']='Òmêñ:BAAALgADCgkJDwAAAA==.',
['Ôj']='Ôjarg:BAAALgAECgcJEAAAAA==.',
['Ød']='Ødinson:BAAALgAFFAIJAgAAAA==.',
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
