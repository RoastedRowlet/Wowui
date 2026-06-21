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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Warrior-Fury','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Frost','Unknown-Unknown','Priest-Discipline','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Druid-Feral','Warrior-Protection','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aarkein:BAAALgAECgYJBgAAAA==.',
Ab='Abiotic:BAAALgAECgEJAwAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ac='Aceofspaded:BAAALgAECgIJAgAAAA==.Acesup:BAAALgAFFAEJAQAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.Aesir:BAAALgADCgYJCAAAAA==.',
Ai='Aings:BAACLgAFFH8FAAIBAAIJqyRysADCAAABAAIJqyRysADCAAAuAAQKfy0AAgEACQnLIpQSANoCAAEACQnLIpQSANoCAAAA.',
Al='Alarus:BAAALgAECgMJAwAAAA==.Alejandro:BAAALgADCggJCAAAAA==.Aletaa:BAAALgAECgcJAQABLgAFFAUJDQACADAQAA==.Alex:BAABLgAECn83AAIDAAkJJh6EFQCXAgADAAkJJh6EFQCXAgAAAA==.Alivathor:BAAALgAECgYJCgABLgAECgYJFwAEAMgKAA==.Allypally:BAABLgAECn8bAAIFAAkJig0pjwBTAQAFAAkJig0pjwBTAQAAAA==.Althir:BAABLgAECn8rAAICAAkJBSDsJQDbAgACAAkJBSDsJQDbAgAAAA==.Althorian:BAAALgAECgQJAgAAAA==.',
Am='Amgrod:BAEBLgAECn8oAAIGAAkJmQlaMgCCAQAGAAkJmQlaMgCCAQAAAA==.Amythest:BAAALgADCgkJDwAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCggJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8eAAIFAAcJ5hhveQB7AQAFAAcJ5hhveQB7AQAAAA==.',
Ar='Arfas:BAAALgAECggJDgABLgAECggJIwAHAP4eAA==.Arkhitype:BAABLgAECn9BAAQIAAkJJx5RAgC7AgAIAAkJJx5RAgC7AgAJAAYJuQ+xMACBAQAKAAEJGQbFKQAgAAAAAA==.Armak:BAAALgADCgEJAgAAAA==.Arwenibria:BAAALgAECgEJAQAAAA==.',
As='Ashdritha:BAAALgAECgEJAQAAAA==.Ashya:BAAALgADCgYJBgAAAA==.Asur:BAABLgAECn83AAMFAAgJ6BJTagCaAQAFAAgJ6BJTagCaAQALAAUJkgNMPwBgAAAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Auracorusca:BAABLgAECn8jAAIMAAkJeiTZAgB4AwAMAAkJeiTZAgB4AwAAAA==.Auris:BAAALgADCgQJBwAAAA==.',
Ay='Aynilith:BAAALgAECgYJCAAAAA==.Aystarael:BAAALgAECgkJBgAAAA==.',
Ba='Bajr:BAABLgAECn8qAAINAAkJjg52UwCpAQANAAkJjg52UwCpAQAAAA==.Bakura:BAABLgAECn8iAAIOAAkJzhxkBAA5AgAOAAkJzhxkBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8hAAIDAAkJORMWUgCPAQADAAkJORMWUgCPAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.Barudd:BAAALgADCgEJAQAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAACLgAFFH8IAAIPAAMJNR7/AQD0AAAPAAMJNR7/AQD0AAAuAAQKf0wAAw8ACQk0JGsAAB8DAA8ACQk0JGsAAB8DAAIAAQlcEJBUATYAAAAA.Berserk:BAAALgADCgIJAgAAAA==.Bestchance:BAAALgAECgEJAQAAAA==.Beware:BAAALgADCgIJAgAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJDQABLgAFFAMJDgAQAPghAA==.Bigbear:BAACLgAFFH8MAAIRAAQJCiCdAABnAQARAAQJCiCdAABnAQAuAAQKfxsAAxEACAn3I4YEAM8CABEACAn3I4YEAM8CABIABgnrFs9gABMBAAEuAAUUBAkSAAcAUSUA.Bigtamer:BAAALgADCgMJAwAAAA==.Bisan:BAAALgADCgUJBgAAAA==.',
Bj='Bjebo:BAACLgAFFH8OAAITAAQJIAajMADAAAATAAQJIAajMADAAAAuAAQKfz0AAhMACQnyFFMXABICABMACQnyFFMXABICAAAA.',
Bl='Blaank:BAACLgAFFH8MAAIFAAQJ2wW5XgDyAAAFAAQJ2wW5XgDyAAAuAAQKfx4AAgUACAlkFMZWAMcBAAUACAlkFMZWAMcBAAAA.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.Bluffshot:BAAALgAECgEJAgABLgAECgkJLQAEAOggAA==.',
Bo='Boba:BAACLgAFFH8LAAMUAAMJiSQnLwAlAQAUAAMJiSQnLwAlAQAVAAEJ1wFwYAAtAAAuAAQKfxYAAxQABwlWJK0aAHUCABQABwlWJK0aAHUCABUABgmtH0IlAL8BAAEuAAUUBgkXABYAIhoA.Boku:BAAALgAECgEJAQAAAA==.Borealiswolf:BAABLgAFFH8LAAIXAAQJMBaOCAAwAQAXAAQJMBaOCAAwAQAAAA==.Borg:BAABLgAFFH8LAAMNAAMJZyOuSQAZAQANAAMJkSCuSQAZAQAYAAMJmxk7GwD3AAAAAA==.',
Br='Bralaria:BAAALgAECgUJBQAAAA==.Bremena:BAAALgADCgMJAwAAAA==.Brewchew:BAACLgAFFH8GAAIHAAMJZgh9AwCzAAAHAAMJZgh9AwCzAAAuAAQKfx0AAgcACAkhETslAIMBAAcACAkhETslAIMBAAAA.Brutes:BAAALgAECgIJBAABLgAFFAcJHgABALcgAA==.Brynjalf:BAAALgAECgUJCAAAAA==.Bràe:BAAALgAECgEJAQAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bë']='Bëärlylëgäl:BAAALgAFFAEJAgAAAA==.',
['Bï']='Bïcho:BAACLgAFFH8OAAMQAAMJ+CFgUAAlAQAQAAMJ+CFgUAAlAQAOAAEJdBIRAwBVAAAuAAQKfzUABBAACQkpJWIFADoDABAACQkpJWIFADoDAA4AAQkAAHsfAHUAABkAAQn5GaxtADkAAAAA.',
Ca='Calambar:BAAALgAECgEJAQAAAA==.Calib:BAACLgAFFH8ZAAMVAAUJKhgXIAAfAQAVAAUJKhgXIAAfAQAUAAEJ4QO0fgA/AAAuAAQKfzEAAhUACQmwIkIMAKACABUACQmwIkIMAKACAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Casdardly:BAAALgAECgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgAECgIJAwAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQAaAKwRAA==.Cheechin:BAACLgAFFH8FAAIbAAQJVw1YHADsAAAbAAQJVw1YHADsAAAuAAQKfxoAAhsACAmfH94MAHYCABsACAmfH94MAHYCAAEuAAUUBAkZAAIAxxQA.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAACLgAFFH8KAAITAAMJ1wu0NACtAAATAAMJ1wu0NACtAAAuAAQKfywAAhMACAm+FiAdAN8BABMACAm+FiAdAN8BAAAA.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn89AAIVAAkJiCK2BwDhAgAVAAkJiCK2BwDhAgAAAA==.',
Co='Coffeeshot:BAAALgADCgEJAQAAAA==.Comboost:BAAALgAECgQJBAAAAA==.Copay:BAABLgAECn8uAAMUAAkJkh3lCwD8AgAUAAkJkh3lCwD8AgAXAAQJZwjtLQCJAAAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8eAAMcAAUJMCKeCQBWAQAcAAQJMCKeCQBWAQABAAEJAADFLQEAAAAuAAQKfzcAAhwACQlCI0IAAJMDABwACQlCI0IAAJMDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.Critos:BAAALgAECgQJBAAAAA==.',
Cu='Cup:BAABLgAECn8oAAMMAAkJsB3GCwDRAgAMAAkJsB3GCwDRAgAFAAEJQBURgwE7AAAAAA==.',
Cv='Cvv:BAAALgAECgUJBgABLgAFFAEJAQAdAAAAAA==.',
Cy='Cyndreya:BAACLgAFFH8hAAIeAAUJyR0FGACvAQAeAAUJyR0FGACvAQAuAAQKf0EAAh4ACQk7JFICAJYDAB4ACQk7JFICAJYDAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Daelaris:BAABLgAECn8jAAICAAkJwR/+EwDiAgACAAkJwR/+EwDiAgAAAA==.Damthrax:BAAALgAECgQJCAAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darmil:BAAALgADCggJEwAAAA==.Davegrôwl:BAAALgAECgUJBgABLgAECggJLgAEANYWAA==.Daylar:BAAALgAECgEJAQABLgAECggJIgANAMEUAA==.Daztoo:BAAALgAECgQJBQAAAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Deadzeo:BAAALgAECgEJAQAAAA==.Deathbrand:BAAALgAECggJDwAAAA==.Dedbhang:BAABLgAFFH8KAAIBAAQJoQwUeAATAQABAAQJoQwUeAATAQAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Demonblades:BAABLgAECn8jAAIDAAkJExMGQQDFAQADAAkJExMGQQDFAQAAAA==.Demonicpixie:BAAALgAECgIJAwAAAA==.Denarten:BAAALgADCgQJBAABLgAECgcJGQAPAO8eAA==.Destructoe:BAAALgAECgUJBwAAAA==.Devotegoat:BAAALgAECgUJCAAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtyalba:BAAALgAECgUJBQAAAA==.Dirtymorris:BAACLgAFFH8FAAIfAAMJ9QvvJgDEAAAfAAMJ9QvvJgDEAAAuAAQKfy4AAx8ACQkTEZgcAOABAB8ACQkTEZgcAOABACAABwk6FoAwAH8BAAAA.',
Do='Docignis:BAABLgAECn8XAAIVAAgJXA/vQgAnAQAVAAgJXA/vQgAnAQAAAA==.Dockevorkian:BAACLgAFFH8gAAIgAAUJMSO9BwDXAQAgAAUJMSO9BwDXAQAuAAQKfzIAAiAACQlBIjoGAOsCACAACQlBIjoGAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECggJFwAVAFwPAA==.Docrhada:BAAALgAECgQJBQABLgAECggJFwAVAFwPAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAABLgAECn8ZAAIDAAgJUhwQLAAYAgADAAgJUhwQLAAYAgABLgAFFAcJHgABALcgAA==.',
Dr='Dracoradk:BAAALgAECgYJBwABLgAFFAQJCAAbAEoGAA==.Dracoramonk:BAABLgAFFH8IAAIbAAQJSgZFJQC+AAAbAAQJSgZFJQC+AAAAAA==.Dragonchris:BAAALgAECgUJDQAAAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Draxus:BAAALgAECggJCAAAAA==.Drdisco:BAAALgAECgUJBQAAAA==.Dricex:BAAALgAECgYJCgAAAA==.Drinnagon:BAAALgAECgMJBwABLgAECgcJGQAPAO8eAA==.Drinnaqua:BAAALgADCgUJBQABLgAECgcJGQAPAO8eAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAPAO8eAA==.Drinntellect:BAABLgAECn8ZAAMPAAcJ7x6rBQDPAQAPAAYJCh+rBQDPAQACAAcJ1RpqhwDDAQAAAA==.Drraxx:BAAALgAECgUJBQAAAA==.Drunkdino:BAAALgADCgUJBQAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Duningkruger:BAAALgADCgcJBwABLgAFFAMJCQAXAMQGAA==.Dunnstunns:BAAALgAECgIJAgAAAA==.Duskwälker:BAAALgAECgEJAQAAAA==.',
Dx='Dxanatos:BAABLgAECn8pAAIhAAkJiQhPEQBFAQAhAAkJiQhPEQBFAQAAAA==.',
['Dø']='Døuce:BAAALgADCgUJAwAAAA==.',
Ea='Eamass:BAABLgAECn8rAAIHAAkJSSGrBgDPAgAHAAkJSSGrBgDPAgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.Eiré:BAAALgADCgQJBAAAAA==.',
Ej='Ejunk:BAAALgAECgMJBAAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn83AAIEAAkJixCuGgCIAQAEAAkJixCuGgCIAQAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJFwACAG0VAA==.',
En='Enanthate:BAAALgADCgMJBQABLgAFFAEJAQAdAAAAAA==.Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8eAAQBAAcJtyB/IQDrAQABAAcJxx5/IQDrAQAcAAQJ9x6cBwB0AQAEAAEJAADJUAAAAAAuAAQKfysAAwEACQm6I0cNADADAAEACQmLI0cNADADABwAAQmgJFYvAGIAAAAA.Enthing:BAACLgAFFH8hAAIDAAUJeBWoQAAmAQADAAUJeBWoQAAmAQAuAAQKf0EAAgMACQkVIaoNANgCAAMACQkVIaoNANgCAAAA.',
Es='Essamond:BAAALgAECgQJBAAAAA==.',
Ev='Evellara:BAAALgAECgQJBAABLgAECggJLgAEANYWAA==.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAABLgAECn8cAAIgAAgJPyZmAwBZAwAgAAgJPyZmAwBZAwAAAA==.Famiki:BAAALgAECgUJCAAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatalxclaw:BAAALgADCgIJAgAAAA==.Fatheral:BAABLgAECn8bAAIfAAkJpBVhHwDKAQAfAAkJpBVhHwDKAQAAAA==.',
Fe='Felaxare:BAAALgAECgcJDQAAAA==.Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8lAAQDAAkJ+xzPMAADAgAiAAgJlhqkFwALAgADAAgJFBnPMAADAgAjAAYJCBiIDQB+AQAAAA==.Fentagram:BAABLgAECn8jAAMOAAkJnCX7AQCyAgAOAAgJdSb7AQCyAgAQAAQJkSERlgAQAQAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgADCgUJBgAAAA==.',
Fl='Floofwall:BAABLgAECn8jAAMHAAgJ/h66DQBdAgAHAAgJ/h66DQBdAgAbAAEJyBLrlgA5AAAAAA==.Floralcarer:BAAALgAECgYJBgAAAA==.',
Fo='Follet:BAAALgADCgQJBwAAAA==.Fonyfish:BAACLgAFFH8LAAIQAAUJLB3wOQBjAQAQAAUJLB3wOQBjAQAuAAQKf0AAAxAACQkUIyAIABUDABAACQkUIyAIABUDABkAAgmwEm5RAHoAAAAA.Fonytime:BAAALgAECgYJBgABLgAFFAUJCwAQACwdAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8sAAQZAAkJiRDaDgBQAQAQAAgJ6AvnbwBbAQAZAAgJwRDaDgBQAQAOAAEJAAB2SgAAAAAAAA==.Foxydots:BAAALgADCgcJCgAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgAECgMJAwABLgAECggJLgAEANYWAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAACLgAFFH8GAAIbAAMJyhPNJADAAAAbAAMJyhPNJADAAAAuAAQKfzYABBsACAmOI18LAI0CABsACAmOI18LAI0CAAcABwkmD+4yADQBABoAAQkeCgTOACEAAAAA.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Ga='Galdran:BAAALgAECgEJAQAAAA==.',
Gg='Ggakkaltigad:BAAALgAECggJCgAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8dAAIGAAcJGh1iBgADAgAGAAcJGh1iBgADAgAuAAQKfyUAAwYACAmmJHQHADEDAAYACAmCJHQHADEDACQAAgnRGUspAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8XAAIVAAYJhBkUVgDiAAAVAAYJhBkUVgDiAAABLgAFFAUJHgAcADAiAA==.Glorm:BAABLgAECn8nAAIUAAkJtw4yPQC5AQAUAAkJtw4yPQC5AQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAABLgAECn8uAAMEAAgJ1hbwFwClAQAEAAgJ1hbwFwClAQABAAYJdQ1XvAADAQAAAA==.Grantul:BAABLgAECn8pAAIGAAkJXhzPFgCWAgAGAAkJXhzPFgCWAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAABLgAECn8VAAIDAAYJEh5GUACVAQADAAYJEh5GUACVAQABLgAFFAQJEgAHAFElAA==.Grimthore:BAAALgAECgQJBQABLgAECggJKgAFAHkYAA==.Grolgan:BAABLgAECn8iAAINAAgJwRTzVAClAQANAAgJwRTzVAClAQAAAA==.Growlings:BAABLgAECn8xAAITAAgJ2BzVAABtAQATAAgJ2BzVAABtAQAAAA==.',
Gu='Gueva:BAAALgAFFAQJBAAAAA==.Guilarth:BAAALgAECgkJAQAAAA==.Guncow:BAAALgAECgEJAQAAAA==.',
Ha='Hailmary:BAAALgADCgIJAgAAAA==.Haradave:BAAALgAECgIJAgAAAA==.Hawktuâh:BAAALgADCgEJAQABLgAECggJLgAEANYWAA==.',
He='Healiostrasz:BAAALgAECgQJBgAAAA==.Health:BAAALgAECgQJBgAAAA==.Healyeah:BAAALgAFFAIJAgABLgAECggJIwAHAP4eAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgYJCwABLgAECggJJQAFAEoXAA==.Holyczar:BAAALgADCgkJGwAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hr='Hruun:BAAALgADCgIJAgAAAA==.',
Hu='Hubirt:BAABLgAECn8mAAIFAAgJ/hhPYwCpAQAFAAgJ/hhPYwCpAQAAAA==.Huntsybuntsy:BAACLgAFFH8OAAMXAAUJxBVpCQAlAQAXAAUJxBVpCQAlAQAVAAIJvQINTwBbAAAuAAQKfzgAAxcACQlgIJoCAO8CABcACQlgIJoCAO8CABUACAkzFoQbADYCAAAA.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJFwACAG0VAA==.',
Hy='Hydrafoil:BAAALgAECgcJEQAAAA==.',
Ia='Ianthel:BAAALgAECgUJCwAAAA==.',
Ic='Icesloth:BAABLgAECn8jAAIVAAkJHxm8EwBOAgAVAAkJHxm8EwBOAgAAAA==.',
Id='Idamae:BAABLgAECn8iAAICAAkJbALz0ADwAAACAAkJbALz0ADwAAAAAA==.Iduun:BAAALgAECgUJDQAAAA==.',
Il='Iladelle:BAABLgAECn8mAAIDAAkJ+hB3SACtAQADAAkJ+hB3SACtAQAAAA==.Illidabina:BAAALgAFFAIJBAABLgAFFAMJBgAbAMoTAA==.',
In='Inariokami:BAABLgAECn8XAAIHAAkJKAnAKwBbAQAHAAkJKAnAKwBbAQAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.Inposter:BAAALgAECgIJAgAAAA==.',
Io='Iorak:BAAALgADCgQJBAAAAA==.',
Ir='Irinon:BAAALgAECgQJDAAAAA==.Irocky:BAAALgADCgkJCQAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgQJCQAAAA==.',
Ja='Jaaygee:BAACLgAFFH8FAAIKAAIJcxTgDACSAAAKAAIJcxTgDACSAAAuAAQKfxoAAgoABwmwH6cEADACAAoABwmwH6cEADACAAEuAAQKCAk1ABAA4yIA.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAACLgAFFH8OAAIQAAMJXx+cXAAPAQAQAAMJXx+cXAAPAQAuAAQKfzkAAxAACQkgIrcLAPACABAACQkgIrcLAPACABkACAlbGf4EAIsCAAAA.Jaggerss:BAAALgAECgEJAgABLgAFFAcJHgABALcgAA==.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8bAAIgAAcJLhPWKwBrAQAgAAcJLhPWKwBrAQAAAA==.',
Jb='Jbsvoid:BAAALgAECgEJAQAAAA==.',
Je='Jelliebean:BAAALgADCgYJBgAAAA==.Jessalba:BAAALgAECgMJBAAAAA==.Jessalbaa:BAAALgAECgMJAwAAAA==.Jestorian:BAAALgAECgcJEwAAAA==.',
Ji='Jimmym:BAAALgAECgEJAQAAAA==.Jirakaidae:BAABLgAECn8dAAITAAgJkwVqSQDmAAATAAgJkwVqSQDmAAAAAA==.',
Jo='Jockinonmytw:BAACLgAFFH8MAAIJAAQJqSGfFwBSAQAJAAQJqSGfFwBSAQAuAAQKf0EAAgkACQlDJY0CADEDAAkACQlDJY0CADEDAAAA.Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCwAAAA==.Juicyfists:BAAALgAECgEJBAAAAA==.Justice:BAAALgADCgEJAQAAAA==.Justred:BAABLgAECn8VAAMGAAYJeRTnSQAeAQAGAAYJeRTnSQAeAQAkAAMJaA9QTwCVAAAAAA==.',
Jx='Jxson:BAACLgAFFH8GAAMTAAIJIhToPQB8AAATAAIJIhToPQB8AAASAAEJ1AZ4dQAwAAAuAAQKfyYABREABgkAIFcTAL8BABEABgm3H1cTAL8BABIABgnFFGRXAEwBABMABgkIEvNDAPwAACUAAwl+Ej4jALwAAAEuAAQKCAk1ABAA4yIA.Jxsong:BAACLgAFFH8FAAIeAAIJIBWQPACJAAAeAAIJIBWQPACJAAAuAAQKfxsAAx4ABgmjHuIXABUCAB4ABgmjHuIXABUCAB8ABAnQE7RVALwAAAEuAAQKCAk1ABAA4yIA.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ka='Kaisel:BAAALgAECgcJCAAAAA==.Kandrys:BAAALgAECgIJAgAAAA==.Kanoa:BAAALgADCgYJBgAAAA==.Kantuo:BAAALgAFFAQJBAAAAA==.Kattschitt:BAAALgAECgEJAQAAAA==.',
Ke='Keanx:BAAALgAFFAEJAQAAAA==.Kehila:BAAALgADCgEJAQAAAA==.Kendorwar:BAAALgAECgkJAwAAAA==.',
Kh='Khelad:BAACLgAFFH8iAAIFAAQJCxpUAwAsAQAFAAQJCxpUAwAsAQAuAAQKfxoAAwUACQkcGqtSANEBAAUACQkcGqtSANEBAAsAAQk+CxBYACAAAAAA.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAABLgAECn8eAAIHAAYJoB6UAABhAQAHAAYJoB6UAABhAQAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killau:BAAALgADCgEJAgAAAA==.Killt:BAABLgAECn8gAAIUAAkJxRQvIgASAgAUAAkJxRQvIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAABLgAECn8cAAImAAcJQxG8IgAaAQAmAAcJQxG8IgAaAQAAAA==.',
Ku='Kurzulan:BAAALgAECgQJCAABLgAECgYJCQAdAAAAAA==.',
Ky='Kynthe:BAAALgAECggJDgAAAA==.Kyongye:BAAALgAECgkJDQAAAA==.',
La='Lacerater:BAAALgADCgcJCgAAAA==.Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8iAAMNAAQJ5x1jAwBNAQANAAQJ5x1jAwBNAQAhAAIJ7AhvIACTAAAuAAQKf0oAAw0ACQl4JMkFADcDAA0ACQl4JMkFADcDACEACAkEG54aAFUCAAAA.',
Le='Leadgut:BAAALgADCgQJBwAAAA==.Lemanjá:BAABLgAECn8yAAIhAAkJhxEbCwC4AQAhAAkJhxEbCwC4AQAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Lilfurrybast:BAAALgADCgEJAQAAAA==.Liliane:BAABLgAECn8dAAMLAAkJkQzMIQAGAQAFAAYJ8QfSvgAKAQALAAgJMAzMIQAGAQAAAA==.Lillatheen:BAAALgAECgMJAwAAAA==.Limbless:BAAALgAECgYJDAABLgAECgYJDQAdAAAAAA==.Littletoast:BAAALgAECgYJBwAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockrocks:BAAALgAECgQJCwABLgAECggJKgAFAHkYAA==.Lockstar:BAAALgADCgUJDAABLgAECggJDwAdAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAABLgAECn8bAAITAAYJ9gr6TQDUAAATAAYJ9gr6TQDUAAAAAA==.Loozer:BAABLgAECn8qAAMFAAgJeRgFUgDTAQAFAAgJmBcFUgDTAQALAAYJ+guhKQDMAAAAAA==.',
Lu='Lulutauren:BAAALgAECgEJAQAAAA==.Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAABLgAECn8gAAIFAAYJYxB6rgAhAQAFAAYJYxB6rgAhAQAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8mAAMBAAkJxxrPKQBZAgABAAkJxxrPKQBZAgAcAAEJywjmGAAsAAAAAA==.',
Ma='Magelyman:BAACLgAFFH8FAAICAAIJWhGDngCPAAACAAIJWhGDngCPAAAuAAQKfxwAAgIACQklGfcrAGoCAAIACQklGfcrAGoCAAAA.Magetiger:BAABLgAECn8iAAICAAkJ6xWJPgAiAgACAAkJ6xWJPgAiAgAAAA==.Magoshon:BAAALgAECgIJAQABLgAECgQJBAAdAAAAAA==.Magsh:BAAALgADCgQJBAAAAA==.Malitheion:BAABLgAECn8VAAMBAAcJPgo5sAAUAQABAAcJEgo5sAAUAQAEAAMJ4wFmVQBFAAAAAA==.Malyce:BAAALgAFFAIJAgAAAA==.Malzen:BAABLgAECn8VAAMHAAgJARftIgCSAQAHAAgJARftIgCSAQAbAAEJ9AtApQArAAABLgAFFAIJAgAdAAAAAA==.Manaleia:BAAALgAECgQJBwAAAA==.Manasolid:BAABLgAECn9GAAICAAkJ1hcLAQDrAQACAAkJ1hcLAQDrAQAAAA==.Mangeømbre:BAAALgAECgQJBAAAAA==.Mar:BAAALgAECgMJBgAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgAECgcJDQAAAA==.Masculinedh:BAAALgAECgIJAwABLgAFFAEJAQAdAAAAAA==.',
Me='Meanka:BAAALgAECgEJAQABLgAFFAMJCgAfAOYeAA==.Meatcurtin:BAAALgADCgkJEQAAAA==.Meches:BAAALgAECgQJCAABLgAECgkJRQASAKkVAA==.Mediocre:BAAALgAECgIJAgAAAA==.Mediocritty:BAAALgAECgYJCgABLgAFFAMJCQAXAMQGAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAABLgAECn86AAICAAkJxgyuYwC3AQACAAkJxgyuYwC3AQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Meraleona:BAAALgAECgUJBQABLgAECgkJLAABAC4dAA==.Methslinger:BAABLgAECn8dAAIVAAYJGQ7TUAD0AAAVAAYJGQ7TUAD0AAAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Milkwithpulp:BAABLgAECn8kAAIgAAgJ/xUNHwDMAQAgAAgJ/xUNHwDMAQAAAA==.Miltonroe:BAAALgADCggJBQABLgAFFAMJCQAXAMQGAA==.Mistynollid:BAAALgADCgYJBgABLgAECgkJJQADAPscAA==.',
Mk='Mkoons:BAAALgAECgEJBAAAAA==.',
Mo='Monkanical:BAAALgADCgkJEwAAAA==.Mook:BAABLgAECn8cAAIDAAgJHAx+bwBEAQADAAgJHAx+bwBEAQAAAA==.Morbious:BAAALgAECgMJBQAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAABLgAECn8WAAIZAAcJBQYLIACsAAAZAAcJBQYLIACsAAAAAA==.Mortmuzi:BAAALgAECgUJDAAAAA==.Mosrael:BAAALgAECgkJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.Mourningveil:BAAALgADCggJCAAAAA==.',
Mu='Mulas:BAABLgAECn8kAAIQAAkJqxYHLAApAgAQAAkJqxYHLAApAgAAAA==.Muldah:BAACLgAFFH8ZAAICAAQJxxTGCgDHAAACAAQJxxTGCgDHAAAuAAQKfzEAAgIACQlrIDEeAKgCAAIACQlrIDEeAKgCAAAA.',
My='Mynte:BAABLgAECn8eAAIgAAYJnBL0NQApAQAgAAYJnBL0NQApAQAAAA==.',
['Mâ']='Mâlice:BAAALgAECgIJAgAAAA==.',
['Mä']='Mäsion:BAABLgAFFH8HAAIGAAQJtwPONwDTAAAGAAQJtwPONwDTAAAAAA==.',
Na='Natty:BAAALgADCgkJIAAAAA==.Navie:BAABLgAECn8+AAIeAAkJNBXoEQBXAgAeAAkJNBXoEQBXAgAAAA==.Nawperwoman:BAABLgAECn8oAAMbAAgJvhvtEgBcAgAbAAgJvhvtEgBcAgAaAAEJrgGhdgAYAAAAAA==.Nazevroth:BAAALgAECgUJBQAAAA==.Nazgûl:BAABLgAFFH8FAAIBAAMJMxqUjQDvAAABAAMJMxqUjQDvAAAAAA==.',
Ne='Necronomicob:BAABLgAECn8zAAQQAAkJsxn9JwA8AgAQAAkJsxn9JwA8AgAZAAQJ7RicGQDWAAAOAAMJ/BK+JwCEAAAAAA==.Neil:BAAALgADCgUJBQABLgAFFAUJFQAUAAAKAA==.Nekros:BAABLgAECn82AAQQAAkJ5h4kGQCNAgAQAAgJNx4kGQCNAgAZAAQJaBxUJQAyAQAOAAMJTxsGHADeAAAAAA==.Neø:BAABLgAECn84AAMBAAkJ+ReaLABNAgABAAkJ+ReaLABNAgAcAAMJoArXMQBVAAAAAA==.',
Ni='Nianna:BAAALgADCgcJCgAAAA==.Nicebud:BAABLgAECn8VAAIDAAkJaxRSOwDaAQADAAkJaxRSOwDaAQAAAA==.Nightsfury:BAABLgAECn8gAAIFAAgJGQ5JhQBlAQAFAAgJGQ5JhQBlAQAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAABLgAECn8XAAIEAAYJyAokNgC+AAAEAAYJyAokNgC+AAAAAA==.Nordburg:BAAALgAECgEJAQAAAA==.Nornyr:BAABLgAECn8pAAIaAAkJIBZPHQAuAgAaAAkJIBZPHQAuAgAAAA==.Notnonna:BAAALgAECgEJAgAAAA==.Noxiss:BAAALgADCgQJBAABLgAECgkJLAABAC4dAA==.',
Nu='Nunsrsus:BAAALgADCgYJCQABLgAECgYJFQAGAHkUAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn9GAAITAAkJfxH3AABUAQATAAkJfxH3AABUAQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oriax:BAABLgAECn8tAAIQAAgJjROITAC1AQAQAAgJjROITAC1AQAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgYJCgAAAA==.',
Pa='Paean:BAAALgAECgUJEgAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8mAAMSAAgJZgRahwCpAAASAAgJZgRahwCpAAATAAQJ+gIhewBQAAAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBwAdAAAAAA==.Peata:BAAALgAECgEJAgAAAA==.Persephones:BAABLgAECn8fAAIfAAcJ4A/eJwCaAQAfAAcJ4A/eJwCaAQAAAA==.Perseus:BAAALgADCgkJCQAAAA==.',
Ph='Phenelope:BAABLgAECn8ZAAMCAAgJTgO30QDvAAACAAgJTgO30QDvAAAnAAcJnAHfDgBwAAAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECgkJFwAHACgJAA==.Pillowpuhmpa:BAAALgAECgIJBAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgAECgIJAgAAAA==.',
Pk='Pkalygos:BAABLgAECn8eAAIWAAkJlRPuDwDMAQAWAAkJlRPuDwDMAQAAAA==.',
Po='Polaka:BAAALgAECgkJAQAAAA==.Poosnwoods:BAAALgAECgYJDgAAAA==.Popefuffer:BAAALgAFFAMJAQAAAA==.Powerstrokee:BAABLgAECn8aAAMBAAcJGRS4eAByAQABAAcJGRS4eAByAQAcAAIJEQ8XMQBZAAAAAA==.',
Pr='Preyforme:BAAALgAECgYJEgAAAA==.Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAIMAAgJrRzoEQCDAgAMAAgJrRzoEQCDAgAAAA==.Protadin:BAABLgAECn8YAAILAAYJwBQUFwBjAQALAAYJwBQUFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAABLgAECn8YAAMMAAcJbgpgTgAAAQAMAAYJAAxgTgAAAQAFAAIJBQibhQE5AAAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôcky:BAAALgAECgEJAQABLgAECgkJKwAHAEkhAA==.Pôps:BAAALgAECgYJEwAAAA==.',
Qu='Quickprick:BAAALgAECgcJEwAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAABLgAFFAMJBAAdAAAAAA==.Ranharr:BAAALgADCgQJBAAAAA==.Rasina:BAAALgAECgIJBAAAAA==.Ratkìng:BAAALgAECgMJBAAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Redcrayons:BAAALgADCgkJCQAAAA==.Reknojir:BAAALgAECgQJBgAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8iAAIDAAQJeRo4BgD5AAADAAQJeRo4BgD5AAAuAAQKfz4AAwMACQkzIfMJAPsCAAMACQkzIfMJAPsCACIABgkAEcs6ABUBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Rh='Rhade:BAAALgAECgMJAwAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgcJDgAAAA==.Rizar:BAAALgAECgUJCgAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgYJDQAdAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn9OAAIRAAkJPQOsPACzAAARAAkJPQOsPACzAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.',
Ru='Rumhanced:BAAALgADCgkJCQAAAA==.Runeclad:BAABLgAECn8cAAIBAAkJnRWzQQD+AQABAAkJnRWzQQD+AQAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámi:BAAALgADCgEJAgAAAA==.',
['Rï']='Rïvkah:BAAALgADCgcJDgAAAA==.',
Sa='Saauurrora:BAAALgAECgcJCwAAAA==.Sabiton:BAAALgADCgYJCgAAAA==.Sadistikult:BAAALgADCgIJAgAAAA==.Saintshift:BAAALgAECgMJAwABLgAFFAEJAQAdAAAAAA==.Salitheion:BAABLgAECn8uAAIMAAgJ+hhqGQA7AgAMAAgJ+hhqGQA7AgAAAA==.Saloraith:BAAALgAECgcJEwAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Salôis:BAAALgAECgYJBgAAAA==.Sanaig:BAAALgADCgcJBwAAAA==.Sanatura:BAAALgAECgYJCwAAAA==.Sapper:BAABLgAECn8wAAIaAAkJ4CAgCAAaAwAaAAkJ4CAgCAAaAwAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgQJCwAAAA==.Sarn:BAABLgAECn8bAAIRAAkJpxI3DwCIAQARAAkJpxI3DwCIAQAAAA==.Sathi:BAAALgAECgcJAgAAAA==.Saudhum:BAABLgAECn8WAAMOAAYJwRsfCADLAQAOAAYJwRsfCADLAQAQAAQJ4Q3L4gCWAAAAAA==.Sayuri:BAABLgAECn84AAMaAAkJfyEbBQBaAwAaAAkJfyEbBQBaAwAbAAIJXANewAAYAAAAAA==.',
Sb='Sboop:BAAALgAECgQJBwAAAA==.',
Sc='Scrím:BAAALgAECgIJBQAAAA==.',
Se='Secondchance:BAAALgAECgIJBQAAAA==.Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shadowmoocow:BAAALgADCgkJEgABLgAECgQJBAAdAAAAAA==.Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn81AAIUAAkJswaiWgBOAQAUAAkJswaiWgBOAQAAAA==.Sheriam:BAAALgADCgcJBwAAAA==.Shikí:BAAALgAECgMJBgAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn88AAIkAAkJLhRLGACYAQAkAAkJLhRLGACYAQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAACLgAFFH8SAAImAAQJMQ8iFwDiAAAmAAQJMQ8iFwDiAAAuAAQKfyYAAiYACQlaFHASAMQBACYACQlaFHASAMQBAAAA.Shotsshots:BAABLgAECn8vAAQNAAkJDB9OHwBrAgANAAkJDB9OHwBrAgAYAAIJGgyZUABtAAAhAAEJAAC1kQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgAECgEJAQAAAA==.Sicaria:BAABLgAECn8WAAMkAAUJ6xkKLAAbAQAkAAUJ6xkKLAAbAQAGAAEJ5woIqgAsAAAAAA==.Sindina:BAAALgADCgYJBgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDgAAAA==.Skully:BAACLgAFFH8SAAIHAAQJUSW8EQCXAQAHAAQJUSW8EQCXAQAuAAQKfzUAAwcACQlfJSICAEADAAcACQlfJSICAEADABoAAglLFsYJAEUAAAAA.',
Sl='Slamdh:BAAALgAECgkJCgABLgAFFAIJBwAJAAgdAA==.Slicedup:BAAALgAECgMJAwABLgAECggJDwAdAAAAAA==.Sluffshot:BAABLgAECn8tAAMEAAkJ6CD6CACEAgAEAAkJaCD6CACEAgABAAQJYx07twAUAQAAAA==.',
Sn='Snorina:BAACLgAFFH8KAAIfAAMJ5h4hHwD6AAAfAAMJ5h4hHwD6AAAuAAQKfzcAAh8ACQkQJUIDAC4DAB8ACQkQJUIDAC4DAAAA.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solarex:BAAALgAECgYJBgAAAA==.Solina:BAAALgAECgcJBwAAAA==.Solsteece:BAAALgADCgYJDwAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAABLgAECn87AAMHAAkJehylCQCXAgAHAAkJehylCQCXAgAbAAMJxgcOcQBuAAAAAA==.Sosozen:BAABLgAECn8mAAIbAAkJxQ7UIgCaAQAbAAkJxQ7UIgCaAQAAAA==.Soul:BAAALgAECgcJEAAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgcJEAAdAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Sparkgrace:BAAALgADCgEJAQAAAA==.Spirittoast:BAAALgAECgUJEQAAAA==.Spluffshot:BAAALgAECgIJAgAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAABLgAECn8bAAICAAkJkg1XZwCuAQACAAkJkg1XZwCuAQAAAA==.',
Sq='Squelch:BAAALgAECgQJEAAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Stratovarius:BAAALgAECgUJBQAAAA==.Strumpet:BAAALgAECgQJBQAAAA==.',
Su='Summuner:BAAALgAECgQJBQAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAABLgAECn8YAAINAAkJYxymGACTAgANAAkJYxymGACTAgABLgAECggJKgAFAHkYAA==.Swytch:BAABLgAECn8pAAIIAAkJ8xfgBQATAgAIAAkJ8xfgBQATAgAAAA==.',
Sy='Sylrytherin:BAABLgAECn8VAAMTAAcJkBokHQAXAgATAAcJkBokHQAXAgARAAEJAAAWlQAAAAABLgAFFAMJCgAfAOYeAA==.Sylvii:BAABLgAECn9FAAMSAAkJqRV/HQBaAgASAAkJqRV/HQBaAgATAAYJRhO4AQDmAAAAAA==.',
Ta='Tabor:BAABLgAECn8eAAMSAAcJhR1fHwBLAgASAAcJhR1fHwBLAgARAAEJuApkgQAgAAAAAA==.Takachance:BAAALgAECgIJBAAAAA==.Talio:BAAALgAECgEJAgAAAA==.Tammyfaye:BAAALgAECgEJAQABLgAECggJLgAEANYWAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAABLgAECn8eAAIMAAgJoheJHAAfAgAMAAgJoheJHAAfAgAAAA==.Tauryel:BAAALgAECgYJDQAAAA==.',
Te='Tebook:BAABLgAECn8sAAMBAAkJLh3GRgDuAQABAAkJLh3GRgDuAQAcAAEJvwZGQQAlAAAAAA==.Telath:BAACLgAFFH8KAAIDAAQJlQn5XQDWAAADAAQJlQn5XQDWAAAuAAQKfyUAAgMACQk8Gf48AAACAAMACQk8Gf48AAACAAAA.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8bAAIDAAgJfCJqDABcAgADAAgJfCJqDABcAgAuAAQKfyYAAgMACQm0IF4aALYCAAMACQm0IF4aALYCAAAA.Thistlechi:BAABLgAECn8nAAIbAAgJnBozEAB9AgAbAAgJnBozEAB9AgAAAA==.Thyck:BAABLgAECn8hAAINAAgJzRgRTAC+AQANAAgJzRgRTAC+AQAAAA==.Thydis:BAAALgAFFAEJAQAAAA==.',
Ti='Tibbs:BAABLgAECn8eAAIoAAkJEg5rLACLAQAoAAkJEg5rLACLAQAAAA==.Ticklepickle:BAAALgADCgkJCQABLgAECgYJEwAdAAAAAA==.Timber:BAAALgAECgQJCAAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Toatasi:BAAALgADCgYJBgAAAA==.Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJDAAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAACLgAFFH8KAAIlAAMJexW4DQDdAAAlAAMJexW4DQDdAAAuAAQKfxoAAiUACAmpFlsOANABACUACAmpFlsOANABAAAA.',
Tu='Tuckr:BAAALgADCgQJBAAAAA==.Tullamore:BAAALgAECgcJCwAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgcJDgAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQaAAcJrBHqLQBJAQAaAAYJHxHqLQBJAQAbAAUJjw3eagB+AAAHAAEJWgD1mAAbAAAAAA==.Tylerblevins:BAAALgADCgMJAwAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAFFAcJEwASAIgYAA==.',
Un='Uncorrupted:BAABLgAECn9BAAILAAkJ9B3MBACrAgALAAkJ9B3MBACrAgAAAA==.Unholymilk:BAAALgAECgEJAgAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAAALgAECgYJEwAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAABLgAECn8rAAINAAcJoBoiQQDfAQANAAcJoBoiQQDfAQAAAA==.Vasdepherens:BAABLgAECn8iAAIEAAkJShMJGACbAQAEAAkJShMJGACbAQAAAA==.',
Ve='Velan:BAAALgADCgcJEQAAAA==.Vermouth:BAABLgAECn8jAAMbAAgJdxGZLwBKAQAbAAgJdxGZLwBKAQAaAAYJ6AJYhwCOAAAAAA==.',
Vi='Vindrelis:BAAALgADCggJEwAAAA==.Violêt:BAABLgAECn8jAAICAAgJwgXyzgDzAAACAAgJwgXyzgDzAAAAAA==.',
Vo='Voidchris:BAABLgAFFH8GAAIDAAQJjhVKQAAnAQADAAQJjhVKQAAnAQAAAA==.Voidfang:BAAALgADCgEJAQAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgAECgUJBQAAAA==.Volkanegos:BAABLgAECn8iAAMGAAYJZwQKbwCqAAAGAAYJZwQKbwCqAAAkAAEJuwCOSwAGAAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
We='Weedmaan:BAAALgAECgUJBQAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwAAAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAFFAUJFgAGABoiAA==.Wizerwar:BAACLgAFFH8WAAIGAAUJGiITEACFAQAGAAUJGiITEACFAQAuAAQKf1EAAgYACQnRJFIDADYDAAYACQnRJFIDADYDAAAA.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolfie:BAAALgADCgQJBAAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAACLgAFFH8GAAICAAIJBxZTmQCYAAACAAIJBxZTmQCYAAAuAAQKfx4AAgIACAmCGkRDABICAAIACAmCGkRDABICAAAA.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgcJBwAAAA==.',
Ya='Yadiyada:BAABLgAECn8WAAIQAAgJ8hbHAADnAQAQAAgJ8hbHAADnAQABLgAECggJHAADABwMAA==.',
Yl='Ylzera:BAAALgAECgEJAgABLgAECgcJCwAdAAAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIiAAYJywg5PgC9AAAiAAYJywg5PgC9AAAAAA==.Yoshì:BAAALgAECgUJBQAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAABLgAECggJGwACAOgXAA==.Zakuren:BAABLgAECn9LAAINAAkJRBecJgBGAgANAAkJRBecJgBGAgAAAA==.',
Zi='Ziggimist:BAAALgAFFAEJAQAAAA==.',
Zo='Zombied:BAAALgAECgEJBwAAAA==.Zort:BAAALgAECgcJAQAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAABLgAECn8lAAICAAYJ9BAitAAbAQACAAYJ9BAitAAbAQAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8lAAQoAAkJSBFXNABhAQAoAAcJaRRXNABhAQAWAAUJgwnnMwDOAAApAAUJBQs3KwDDAAAAAA==.',
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
