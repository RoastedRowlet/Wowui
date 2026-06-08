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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Retribution','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Druid-Guardian','Druid-Restoration','Monk-Brewmaster','Shaman-Restoration','Shaman-Enhancement','Druid-Balance','Shaman-Elemental','Evoker-Preservation','Hunter-Survival','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','DeathKnight-Frost','Priest-Discipline','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Druid-Feral','Warrior-Protection','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aarkein:BAAALgAECgYJBgAAAA==.',
Ab='Abiotic:BAAALgAECgEJAwAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ac='Acesup:BAAALgAFFAEJAQAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.Aesir:BAAALgADCgYJBgAAAA==.',
Ai='Aings:BAACLgAFFH8FAAIBAAIJqyRgngDKAAABAAIJqyRgngDKAAAuAAQKfy0AAgEACQnLIqwQAOACAAEACQnLIqwQAOACAAAA.',
Al='Alarus:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCggJCAAAAA==.Aletaa:BAAALgAECgcJAQABLgAFFAUJDQACADAQAA==.Alex:BAABLgAECn83AAIDAAkJJh4rFACXAgADAAkJJh4rFACXAgAAAA==.Alivathor:BAAALgAECgYJCgABLgAECgYJFgAEAMgKAA==.Allypally:BAABLgAECn8bAAIFAAkJig3HhQBZAQAFAAkJig3HhQBZAQAAAA==.Althir:BAABLgAECn8rAAICAAkJBSDsJQDbAgACAAkJBSDsJQDbAgAAAA==.Althorian:BAAALgAECgQJAgAAAA==.',
Am='Amgrod:BAEBLgAECn8lAAIGAAkJrweqNQBpAQAGAAkJrweqNQBpAQAAAA==.Amythest:BAAALgADCgYJBgAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCggJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8eAAIFAAcJ5hjlcgB9AQAFAAcJ5hjlcgB9AQAAAA==.',
Ar='Arfas:BAAALgAECggJDgAAAA==.Arkhitype:BAABLgAECn86AAQHAAkJ9hvfAgCQAgAHAAkJ9hvfAgCQAgAIAAYJuQ+xMACBAQAJAAEJGQarJgAgAAAAAA==.Armak:BAAALgADCgEJAgAAAA==.Arwenibria:BAAALgAECgEJAQAAAA==.',
As='Ashdritha:BAAALgAECgEJAQAAAA==.Ashya:BAAALgADCgYJBgAAAA==.Asur:BAABLgAECn8vAAMFAAgJbBJ4aACTAQAFAAgJbBJ4aACTAQAKAAUJkgMYPABgAAAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Auracorusca:BAABLgAECn8hAAILAAkJeiR5AgB7AwALAAkJeiR5AgB7AwAAAA==.Auris:BAAALgADCgQJBwAAAA==.',
Ay='Aynilith:BAAALgAECgYJCAAAAA==.Aystarael:BAAALgAECgkJBgAAAA==.',
Ba='Bajr:BAABLgAECn8qAAIMAAkJjg6jTACwAQAMAAkJjg6jTACwAQAAAA==.Bakura:BAABLgAECn8iAAINAAkJzhxkBAA5AgANAAkJzhxkBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8hAAIDAAkJORM7TgCPAQADAAkJORM7TgCPAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.Barudd:BAAALgADCgEJAQAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAACLgAFFH8IAAIOAAMJNR6qAQD3AAAOAAMJNR6qAQD3AAAuAAQKf0wAAw4ACQk0JFgAACUDAA4ACQk0JFgAACUDAAIAAQlcEJdEATkAAAAA.Berserk:BAAALgADCgIJAgAAAA==.Bestchance:BAAALgAECgEJAQAAAA==.Beware:BAAALgADCgIJAgAAAA==.Beärlylegäl:BAAALgAECgEJAwAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJDQABLgAFFAMJCgAPAPghAA==.Bigbear:BAACLgAFFH8IAAIQAAQJth/0BgBvAQAQAAQJth/0BgBvAQAuAAQKfxsAAxAACAn3Iw0EANACABAACAn3Iw0EANACABEABgnrFtZYAEgBAAEuAAUUBAkSABIAUSUA.Bigdave:BAABLgAECn8qAAMTAAkJkR3ECgD+AgATAAkJkR3ECgD+AgAUAAQJZwhNKgCKAAAAAA==.Bigtamer:BAAALgADCgMJAwAAAA==.Bisan:BAAALgADCgUJBgAAAA==.',
Bj='Bjebo:BAACLgAFFH8OAAIVAAQJIAYnLADBAAAVAAQJIAYnLADBAAAuAAQKfzcAAhUACQkvE3waAOoBABUACQkvE3waAOoBAAAA.',
Bl='Blaank:BAACLgAFFH8IAAIFAAMJLQUacwC2AAAFAAMJLQUacwC2AAAuAAQKfx4AAgUACAlkFIxQAMwBAAUACAlkFIxQAMwBAAAA.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.Bluffshot:BAAALgAECgEJAQABLgAECgkJLQAEAOggAA==.',
Bo='Boba:BAACLgAFFH8LAAMTAAMJiSRrKAArAQATAAMJiSRrKAArAQAWAAEJ1wFCVAA0AAAuAAQKfxYAAxMABwlWJMYYAHcCABMABwlWJMYYAHcCABYABgmtH9siAMEBAAEuAAUUBgkXABcAIhoA.Boku:BAAALgAECgEJAQAAAA==.Borealiswolf:BAABLgAFFH8LAAIUAAQJMBbWBgA8AQAUAAQJMBbWBgA8AQAAAA==.Borg:BAABLgAFFH8JAAMMAAMJZyNAPgAlAQAMAAMJpCBAPgAlAQAYAAMJmxmMGAD6AAAAAA==.',
Br='Bremena:BAAALgADCgMJAwAAAA==.Brewchew:BAABLgAECn8cAAISAAgJ0w5gKgBbAQASAAgJ0w5gKgBbAQAAAA==.Brynjalf:BAAALgAECgUJCAAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bï']='Bïcho:BAACLgAFFH8KAAMPAAMJ+CGMRgAsAQAPAAMJ+CGMRgAsAQANAAEJAwkyJgBEAAAuAAQKfzUABA8ACQkpJbEEAEADAA8ACQkpJbEEAEADAA0AAQkAAHsfAHUAABkAAQn5GaxtADkAAAAA.',
Ca='Calambar:BAAALgAECgEJAQAAAA==.Calib:BAACLgAFFH8YAAIWAAUJKhizGwApAQAWAAUJKhizGwApAQAuAAQKfzEAAhYACQmwIjsLAKMCABYACQmwIjsLAKMCAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgAECgIJAwAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQAaAKwRAA==.Cheechin:BAABLgAECn8aAAIbAAgJnx/9CwB5AgAbAAgJnx/9CwB5AgABLgAFFAQJFgACAMcUAA==.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAACLgAFFH8HAAIVAAIJmQrsOgBzAAAVAAIJmQrsOgBzAAAuAAQKfyYAAhUACAn6FWEfAL8BABUACAn6FWEfAL8BAAAA.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn86AAIWAAkJGiLgBgDkAgAWAAkJGiLgBgDkAgAAAA==.',
Co='Coffeeshot:BAAALgADCgEJAQAAAA==.Comboost:BAAALgADCggJCgABLgADCgkJEgAcAAAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8eAAMdAAUJMCIXBwBeAQAdAAQJMCIXBwBeAQABAAEJAAB3EQEAAAAuAAQKfzcAAh0ACQlCI0IAAJMDAB0ACQlCI0IAAJMDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.',
Cu='Cup:BAABLgAECn8oAAMLAAkJsB3SCgDUAgALAAkJsB3SCgDUAgAFAAEJQBUbbgE8AAAAAA==.',
Cv='Cvv:BAAALgAECgUJBgABLgAECgYJEAAcAAAAAA==.',
Cy='Cyndreya:BAACLgAFFH8cAAIeAAUJ1BsHFQCuAQAeAAUJ1BsHFQCuAQAuAAQKfz8AAh4ACQk7JBQCAJoDAB4ACQk7JBQCAJoDAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Daelaris:BAABLgAECn8jAAICAAkJwR8mEgDpAgACAAkJwR8mEgDpAgAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darmil:BAAALgADCggJEwAAAA==.Davegrôwl:BAAALgAECgUJBAABLgAECggJJwAEANYWAA==.Daylar:BAAALgAECgEJAQABLgAECgYJGgAMAH4QAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Deathbrand:BAAALgAECggJDwAAAA==.Dedbhang:BAABLgAFFH8GAAIBAAMJHQxemgDPAAABAAMJHQxemgDPAAAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Demonblades:BAABLgAECn8iAAIDAAkJExPzPQDFAQADAAkJExPzPQDFAQAAAA==.Demonicpixie:BAAALgAECgIJAwAAAA==.Denarten:BAAALgADCgQJBAABLgAECgcJGQAOAO8eAA==.Destructoe:BAAALgAECgQJBAAAAA==.Devotegoat:BAAALgAECgUJCAAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtymorris:BAACLgAFFH8FAAIfAAMJ9Qs3IwDGAAAfAAMJ9Qs3IwDGAAAuAAQKfy4AAx8ACQkTEdgZAO8BAB8ACQkTEdgZAO8BACAABwk6FoAwAH8BAAAA.',
Do='Docignis:BAABLgAECn8XAAIWAAgJXA+0PgApAQAWAAgJXA+0PgApAQAAAA==.Dockevorkian:BAACLgAFFH8ZAAIgAAUJCiJdBgDVAQAgAAUJCiJdBgDVAQAuAAQKfzIAAiAACQlBIjoGAOsCACAACQlBIjoGAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECggJFwAWAFwPAA==.Docrhada:BAAALgAECgQJBQABLgAECggJFwAWAFwPAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAABLgAECn8ZAAIDAAgJUhzWKQAXAgADAAgJUhzWKQAXAgABLgAFFAcJGAABAB0gAA==.',
Dr='Dracoradk:BAAALgAECgYJBwABLgAFFAQJCAAbAEoGAA==.Dracoramonk:BAABLgAFFH8IAAIbAAQJSgbPIADMAAAbAAQJSgbPIADMAAAAAA==.Dragonchris:BAAALgAECgUJBQAAAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Draxus:BAAALgAECggJCAAAAA==.Dricex:BAAALgAECgYJCQAAAA==.Drinnagon:BAAALgAECgMJBwABLgAECgcJGQAOAO8eAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAOAO8eAA==.Drinntellect:BAABLgAECn8ZAAMOAAcJ7x6rBQDPAQAOAAYJCh+rBQDPAQACAAcJ1RpqhwDDAQAAAA==.Drraxx:BAAALgAECgUJBQAAAA==.Drunkdino:BAAALgADCgUJBQAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Dunnstunns:BAAALgAECgIJAgAAAA==.Duskwälker:BAAALgADCgcJBwAAAA==.',
Dx='Dxanatos:BAABLgAECn8pAAIhAAkJiQgTEABLAQAhAAkJiQgTEABLAQAAAA==.',
['Dø']='Døuce:BAAALgADCgUJAwAAAA==.',
Ea='Eamass:BAABLgAECn8rAAISAAkJSSEgBgDTAgASAAkJSSEgBgDTAgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.Eiré:BAAALgADCgQJBAAAAA==.',
Ej='Ejunk:BAAALgAECgEJAQAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn8wAAIEAAkJixCYGACRAQAEAAkJixCYGACRAQAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJFwACAG0VAA==.',
En='Enanthate:BAAALgADCgMJBQABLgAECgYJEAAcAAAAAA==.Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8YAAQBAAcJHSAwGgDvAQABAAYJxx4wGgDvAQAdAAQJYRyPBwBYAQAEAAEJAABnSAAAAAAuAAQKfysAAwEACQm6I0cNADADAAEACQmLI0cNADADAB0AAQmgJDQrAGMAAAAA.Enthing:BAACLgAFFH8cAAIDAAUJYhWuOwAjAQADAAUJYhWuOwAjAQAuAAQKfz8AAgMACQm/H8kOAMQCAAMACQm/H8kOAMQCAAAA.',
Es='Essamond:BAAALgAECgQJBAAAAA==.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAABLgAECn8cAAIgAAgJPyYXAwBcAwAgAAgJPyYXAwBcAwAAAA==.Famiki:BAAALgAECgMJAQAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatheral:BAABLgAECn8bAAIfAAkJpBVyHQDSAQAfAAkJpBVyHQDSAQAAAA==.',
Fe='Felaxare:BAAALgAECgcJDQAAAA==.Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8kAAQDAAkJ+xwvLgADAgAiAAgJlhqkFwALAgADAAgJFBkvLgADAgAjAAYJCBiIDQB+AQAAAA==.Fentagram:BAABLgAECn8jAAMNAAkJnCX7AQCyAgANAAgJdSb7AQCyAgAPAAQJkSHkkQATAQAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgADCgUJBgAAAA==.',
Fl='Floofwall:BAABLgAECn8jAAMSAAgJ/h7mDABgAgASAAgJ/h7mDABgAgAbAAEJyBIHjQA5AAAAAA==.Floralcarer:BAAALgAECgYJBgAAAA==.',
Fo='Follet:BAAALgADCgQJBwAAAA==.Fonyfish:BAACLgAFFH8LAAIPAAUJLB1lMABrAQAPAAUJLB1lMABrAQAuAAQKf0AAAw8ACQkUIxsHABwDAA8ACQkUIxsHABwDABkAAgmwEm5RAHoAAAAA.Fonytime:BAAALgAECgYJBgABLgAFFAUJCwAPACwdAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8sAAQZAAkJiRCHDQBVAQAPAAgJ6AvuaABmAQAZAAgJwRCHDQBVAQANAAEJAACPRAAAAAAAAA==.Foxydots:BAAALgADCgcJCgAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgAECgMJAwABLgAECggJJwAEANYWAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAABLgAECn8sAAQbAAgJ+SGWDQBiAgAbAAgJ+SGWDQBiAgASAAcJYAvEOwAFAQAaAAEJHgrhugAgAAABLgAFFAIJBAAcAAAAAA==.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Ga='Galdran:BAAALgAECgEJAQAAAA==.',
Gg='Ggakkaltigad:BAAALgAECggJCgAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8YAAIGAAcJGh0iBQD6AQAGAAcJGh0iBQD6AQAuAAQKfyUAAwYACAmmJHQHADEDAAYACAmCJHQHADEDACQAAgnRGUspAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8XAAIWAAYJhBnbUADjAAAWAAYJhBnbUADjAAABLgAFFAUJHgAdADAiAA==.Glorm:BAABLgAECn8nAAITAAkJtw7cOQC6AQATAAkJtw7cOQC6AQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAABLgAECn8nAAMEAAgJ1hYgFgCtAQAEAAgJ1hYgFgCtAQABAAYJfQrkvQD3AAAAAA==.Grantul:BAABLgAECn8pAAIGAAkJXhzPFgCWAgAGAAkJXhzPFgCWAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAABLgAECn8VAAIDAAYJEh4+TACUAQADAAYJEh4+TACUAQABLgAFFAQJEgASAFElAA==.Grimthore:BAAALgAECgIJAgABLgAECggJHgAFAL0WAA==.Grolgan:BAABLgAECn8aAAIMAAYJfhAEgQAwAQAMAAYJfhAEgQAwAQAAAA==.Growlings:BAABLgAECn8kAAIVAAgJFRuNEwAtAgAVAAgJFRuNEwAtAgAAAA==.',
Gu='Guncow:BAAALgAECgEJAQAAAA==.',
Ha='Hailmary:BAAALgADCgIJAgAAAA==.Haradave:BAAALgAECgEJAQAAAA==.Hawktuâh:BAAALgADCgEJAQABLgAECggJJwAEANYWAA==.',
He='Healiostrasz:BAAALgAECgQJBgAAAA==.Healyeah:BAAALgAECgMJBAAAAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgYJCwABLgAECggJHgAFANgWAA==.Holyczar:BAAALgADCgkJGwAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hr='Hruun:BAAALgADCgIJAgAAAA==.',
Hu='Hubirt:BAABLgAECn8mAAIFAAgJ/hiZXACuAQAFAAgJ/hiZXACuAQAAAA==.Huntsybuntsy:BAACLgAFFH8OAAMUAAUJxBWeBwAyAQAUAAUJxBWeBwAyAQAWAAIJvQL5RQBlAAAuAAQKfzgAAxQACQlgIEACAPUCABQACQlgIEACAPUCABYACAkzFoQbADYCAAAA.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJFwACAG0VAA==.',
Hy='Hydrafoil:BAAALgAECgYJEAAAAA==.',
Ia='Ianthel:BAAALgAECgUJCwAAAA==.',
Ic='Icesloth:BAABLgAECn8hAAIWAAkJHxlBEgBRAgAWAAkJHxlBEgBRAgAAAA==.',
Id='Idamae:BAABLgAECn8gAAICAAkJLwJo0wDnAAACAAkJLwJo0wDnAAAAAA==.Iduun:BAAALgAECgUJDQAAAA==.',
Il='Iladelle:BAABLgAECn8mAAIDAAkJ+hAWRQCsAQADAAkJ+hAWRQCsAQAAAA==.Illidabina:BAAALgAFFAIJBAAAAA==.',
In='Inariokami:BAABLgAECn8XAAISAAkJKAkBKgBdAQASAAkJKAkBKgBdAQAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.',
Io='Iorak:BAAALgADCgQJBAAAAA==.',
Ir='Irinon:BAAALgAECgQJCAAAAA==.Irocky:BAAALgADCgkJCQAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgMJBgAAAA==.',
Ja='Jaaygee:BAABLgAECn8ZAAIJAAcJsB93BAAvAgAJAAcJsB93BAAvAgABLgAECgcJMwAPALUkAA==.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAACLgAFFH8KAAIPAAMJ3xrYXQD8AAAPAAMJ3xrYXQD8AAAuAAQKfzkAAw8ACQkgInAKAPcCAA8ACQkgInAKAPcCABkACAlbGf4EAIsCAAAA.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8bAAIgAAcJLhO5KQBsAQAgAAcJLhO5KQBsAQAAAA==.',
Je='Jelliebean:BAAALgADCgYJBgAAAA==.Jessalba:BAAALgAECgMJBAAAAA==.Jestorian:BAAALgAECgYJEgAAAA==.',
Ji='Jirakaidae:BAABLgAECn8YAAIVAAcJjQRnTwDAAAAVAAcJjQRnTwDAAAAAAA==.',
Jo='Jockinonmytw:BAACLgAFFH8MAAIIAAQJqSElFABZAQAIAAQJqSElFABZAQAuAAQKf0EAAggACQlDJTACADYDAAgACQlDJTACADYDAAAA.Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCwAAAA==.Juicyfists:BAAALgAECgEJAwAAAA==.Justice:BAAALgADCgEJAQAAAA==.Justred:BAABLgAECn8VAAMGAAYJeRTFRQAkAQAGAAYJeRTFRQAkAQAkAAMJaA/1SACbAAAAAA==.',
Jx='Jxson:BAACLgAFFH8GAAMVAAIJIhRXOAB8AAAVAAIJIhRXOAB8AAARAAEJ1AYMbgAzAAAuAAQKfyYABRAABgkAIKgRAMABABAABgm3H6gRAMABABEABgnFFGRXAEwBABUABgkIEl5AAP0AACUAAwl+Ej4jALwAAAEuAAQKBwkzAA8AtSQA.Jxsong:BAACLgAFFH8FAAIeAAIJIBVsNgCLAAAeAAIJIBVsNgCLAAAuAAQKfxkAAx4ABgmiHncWABYCAB4ABgmiHncWABYCAB8ABAnQE2lSALwAAAEuAAQKBwkzAA8AtSQA.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ka='Kaisel:BAAALgAECgcJBwAAAA==.Kandrys:BAAALgAECgIJAgAAAA==.Kanoa:BAAALgADCgYJBgAAAA==.Kantuo:BAAALgAFFAQJBAAAAA==.Kattschitt:BAAALgAECgEJAQAAAA==.',
Ke='Keanx:BAAALgAFFAEJAQAAAA==.Kehila:BAAALgADCgEJAQAAAA==.Kendorwar:BAAALgAECgkJAwAAAA==.',
Kh='Khelad:BAACLgAFFH8eAAIFAAQJKRlZNQAyAQAFAAQJKRlZNQAyAQAuAAQKfxoAAwUACQkcGmRNANQBAAUACQkcGmRNANQBAAoAAQk+C3JTAB8AAAAA.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAABLgAECn8VAAISAAYJoB7wGwC+AQASAAYJoB7wGwC+AQAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killau:BAAALgADCgEJAgAAAA==.Killt:BAABLgAECn8gAAITAAkJxRQvIgASAgATAAkJxRQvIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAABLgAECn8bAAImAAcJQxG+IAAdAQAmAAcJQxG+IAAdAQAAAA==.',
Ku='Kurzulan:BAAALgAECgQJCAABLgAECgYJCQAcAAAAAA==.',
Ky='Kynthe:BAAALgAECggJDgAAAA==.Kyongye:BAAALgAECgkJDQAAAA==.',
La='Lacerater:BAAALgADCgcJCgAAAA==.Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8eAAMMAAQJ5x2FJgBZAQAMAAQJ5x2FJgBZAQAhAAIJ7AhvIACTAAAuAAQKf0oAAwwACQl4JM0EAD0DAAwACQl4JM0EAD0DACEACAkEG54aAFUCAAAA.',
Le='Leadgut:BAAALgADCgQJBwAAAA==.Lemanjá:BAABLgAECn8tAAIhAAkJoA9SCgC9AQAhAAkJoA9SCgC9AQAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Liliane:BAABLgAECn8dAAMKAAkJkQwcIAAGAQAFAAYJ8QdPtAANAQAKAAgJMAwcIAAGAQAAAA==.Limbless:BAAALgAECgYJDAABLgAECgYJDQAcAAAAAA==.Littletoast:BAAALgAECgYJBwAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockrocks:BAAALgAECgQJCwABLgAECggJHgAFAL0WAA==.Lockstar:BAAALgADCgUJDAABLgAECggJDwAcAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAABLgAECn8aAAIVAAYJ9gr6SQDVAAAVAAYJ9gr6SQDVAAAAAA==.Loozer:BAABLgAECn8eAAMFAAgJvRbdaQCQAQAFAAgJvRbdaQCQAQAKAAUJxgg2OgBWAAAAAA==.',
Lu='Lulutauren:BAAALgAECgEJAQAAAA==.Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAABLgAECn8aAAIFAAYJnwzMwAD7AAAFAAYJnwzMwAD7AAAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8mAAMBAAkJxxqnJQBkAgABAAkJxxqnJQBkAgAdAAEJywjmGAAsAAAAAA==.',
Ma='Magelyman:BAABLgAECn8cAAICAAkJJRl2KAByAgACAAkJJRl2KAByAgAAAA==.Magetiger:BAABLgAECn8gAAICAAkJAhXWOwAkAgACAAkJAhXWOwAkAgAAAA==.Magsh:BAAALgADCgQJBAAAAA==.Malitheion:BAAALgAECgYJEwAAAA==.Malyce:BAAALgAFFAIJAgAAAA==.Malzen:BAABLgAECn8VAAMSAAgJARdrIQCUAQASAAgJARdrIQCUAQAbAAEJ9AvDmgArAAABLgAFFAIJAgAcAAAAAA==.Manaleia:BAAALgAECgMJBgAAAA==.Manasolid:BAABLgAECn8/AAICAAkJIhaCNQA7AgACAAkJIhaCNQA7AgAAAA==.Mangeømbre:BAAALgAECgQJBAAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgAECgcJCwAAAA==.Masculinedh:BAAALgAECgIJAwABLgAECgYJEAAcAAAAAA==.',
Me='Meanka:BAAALgAECgEJAQABLgAFFAMJCgAfAOYeAA==.Meatcurtin:BAAALgADCgkJEQAAAA==.Meches:BAAALgAECgQJCAABLgAECggJPAARANQXAA==.Mediocre:BAAALgAECgIJAgAAAA==.Mediocritty:BAAALgAECgYJCgABLgAECggJIgAUAOkOAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAABLgAECn8rAAICAAgJ/gvafgBzAQACAAgJ/gvafgBzAQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Meraleona:BAAALgAECgUJBQABLgAECgkJLAABAC4dAA==.Methslinger:BAABLgAECn8ZAAIWAAYJGQ6/SwD2AAAWAAYJGQ6/SwD2AAAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Milkwithpulp:BAABLgAECn8kAAIgAAgJ/xU0HQDOAQAgAAgJ/xU0HQDOAQAAAA==.Miltonroe:BAAALgADCggJBQABLgAECggJIgAUAOkOAA==.Mistynollid:BAAALgADCgYJBgABLgAECgkJJAADAPscAA==.',
Mk='Mkoons:BAAALgAECgEJBAAAAA==.',
Mo='Monkanical:BAAALgADCgYJCgAAAA==.Mook:BAABLgAECn8UAAIDAAgJWAqocwAtAQADAAgJWAqocwAtAQAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAABLgAECn8WAAIZAAcJBQa4HQCxAAAZAAcJBQa4HQCxAAAAAA==.Mortmuzi:BAAALgAECgUJDAAAAA==.Mosrael:BAAALgAECgkJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.',
Mu='Mulas:BAABLgAECn8kAAIPAAkJqxYJKQAxAgAPAAkJqxYJKQAxAgAAAA==.Muldah:BAACLgAFFH8WAAICAAQJxxTXUgA3AQACAAQJxxTXUgA3AQAuAAQKfzEAAgIACQlrINkbAK0CAAIACQlrINkbAK0CAAAA.',
My='Mynte:BAABLgAECn8eAAIgAAYJnBI/MwArAQAgAAYJnBI/MwArAQAAAA==.',
['Mâ']='Mâlice:BAAALgAECgIJAgAAAA==.',
['Mä']='Mäsion:BAABLgAFFH8HAAIGAAQJtwM2MgDUAAAGAAQJtwM2MgDUAAAAAA==.',
Na='Natty:BAAALgADCgkJIAAAAA==.Navie:BAABLgAECn81AAIeAAkJrw/KGQD0AQAeAAkJrw/KGQD0AQAAAA==.Nawperwoman:BAABLgAECn8oAAMbAAgJvhvtEgBcAgAbAAgJvhvtEgBcAgAaAAEJrgGhdgAYAAAAAA==.Nazevroth:BAAALgAECgUJBQAAAA==.Nazgûl:BAABLgAFFH8FAAIBAAMJMxq8fgD3AAABAAMJMxq8fgD3AAAAAA==.',
Ne='Necronomicob:BAABLgAECn8wAAQPAAkJsxk4JQBEAgAPAAkJsxk4JQBEAgAZAAQJ7Rj7FwDYAAANAAEJNw/VNgA8AAAAAA==.Neil:BAAALgADCgUJBQABLgAFFAUJEAATAPwHAA==.Nekros:BAABLgAECn8vAAQPAAgJ1yACIwBPAgAPAAcJDyACIwBPAgAZAAQJaBxUJQAyAQANAAIJqB03IgCaAAAAAA==.Neø:BAABLgAECn84AAMBAAkJ+RcNKgBQAgABAAkJ+RcNKgBQAgAdAAMJoApHLQBXAAAAAA==.',
Ni='Nianna:BAAALgADCgcJCgAAAA==.Nicebud:BAAALgAECggJDgAAAA==.Nightsfury:BAABLgAECn8fAAIFAAgJGQ4GfgBnAQAFAAgJGQ4GfgBnAQAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAABLgAECn8WAAIEAAYJyArsMgDEAAAEAAYJyArsMgDEAAAAAA==.Nordburg:BAAALgAECgEJAQAAAA==.Nornyr:BAABLgAECn8pAAIaAAkJIBYoGwArAgAaAAkJIBYoGwArAgAAAA==.Noxiss:BAAALgADCgQJBAABLgAECgkJLAABAC4dAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn8/AAIVAAkJug47IgCqAQAVAAkJug47IgCqAQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oriax:BAABLgAECn8rAAIPAAcJvROJZwBpAQAPAAcJvROJZwBpAQAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgYJCgAAAA==.',
Pa='Paean:BAAALgAECgUJDgAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8mAAMRAAgJZgTVggCqAAARAAgJZgTVggCqAAAVAAQJ+gLzdABQAAAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBwAcAAAAAA==.Peata:BAAALgAECgEJAgAAAA==.Persephones:BAABLgAECn8fAAIfAAcJ4A/eJwCaAQAfAAcJ4A/eJwCaAQAAAA==.Perseus:BAAALgADCgkJCQAAAA==.',
Ph='Phenelope:BAABLgAECn8ZAAMCAAgJTgM9yQD2AAACAAgJTgM9yQD2AAAnAAcJnAGEDQBwAAAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECgkJFwASACgJAA==.Pillowpuhmpa:BAAALgAECgIJBAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgAECgIJAgAAAA==.',
Pk='Pkalygos:BAABLgAECn8eAAIXAAkJlRNDDwDPAQAXAAkJlRNDDwDPAQAAAA==.',
Po='Poosnwoods:BAAALgAECgYJDgAAAA==.Popefuffer:BAAALgAFFAIJAQAAAA==.Powerstrokee:BAABLgAECn8aAAMBAAcJGRRHcQB5AQABAAcJGRRHcQB5AQAdAAIJEQ9aLABcAAAAAA==.',
Pr='Preyforme:BAAALgAECgQJDAAAAA==.Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAILAAgJrRzoEQCDAgALAAgJrRzoEQCDAgAAAA==.Protadin:BAABLgAECn8YAAIKAAYJwBQUFwBjAQAKAAYJwBQUFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAABLgAECn8YAAMLAAcJbgomSwADAQALAAYJAAwmSwADAQAFAAIJBQgKcQE5AAAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôcky:BAAALgAECgEJAQABLgAECgkJKwASAEkhAA==.Pôps:BAAALgAECgYJEwAAAA==.',
Qu='Quickprick:BAAALgAECgcJEwAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAABLgAECgkJDwAcAAAAAA==.Ranharr:BAAALgADCgQJBAAAAA==.Rasina:BAAALgAECgIJBAAAAA==.Ratkìng:BAAALgAECgMJBAAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Redcrayons:BAAALgADCgkJCQAAAA==.Reknojir:BAAALgAECgQJBgAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8eAAIDAAQJeRp0MABLAQADAAQJeRp0MABLAQAuAAQKfz4AAwMACQkzISYJAPwCAAMACQkzISYJAPwCACIABgkAEcs6ABUBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgcJDgAAAA==.Rizar:BAAALgAECgUJCgAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgYJDQAcAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn8+AAIQAAkJKAPuNwCyAAAQAAkJKAPuNwCyAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.',
Ru='Rumhanced:BAAALgADCgkJCQAAAA==.Runeclad:BAABLgAECn8cAAIBAAkJnRULPAAJAgABAAkJnRULPAAJAgAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámi:BAAALgADCgEJAgAAAA==.',
['Rï']='Rïvkah:BAAALgADCgYJDAAAAA==.',
Sa='Saauurrora:BAAALgAECgcJBwAAAA==.Sabiton:BAAALgADCgYJCgAAAA==.Saintshift:BAAALgADCgYJDQABLgAECgYJEAAcAAAAAA==.Salitheion:BAABLgAECn8lAAILAAgJ1RYIHAAYAgALAAgJ1RYIHAAYAgAAAA==.Saloraith:BAAALgAECgcJEwAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Sanaig:BAAALgADCgcJBwAAAA==.Sanatura:BAAALgAECgYJCwAAAA==.Sapper:BAABLgAECn8wAAIaAAkJ4CBmBwAaAwAaAAkJ4CBmBwAaAwAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgQJCwAAAA==.Sarn:BAABLgAECn8bAAIQAAkJpxI3DwCIAQAQAAkJpxI3DwCIAQAAAA==.Sathi:BAAALgAECgcJAgAAAA==.Saudhum:BAABLgAECn8WAAMNAAYJwRsfCADLAQANAAYJwRsfCADLAQAPAAQJ4Q352gCaAAAAAA==.Sayuri:BAABLgAECn8zAAIaAAgJjiLiBwAQAwAaAAgJjiLiBwAQAwAAAA==.',
Sb='Sboop:BAAALgAECgQJBwAAAA==.',
Sc='Scrím:BAAALgAECgIJBAAAAA==.',
Se='Secondchance:BAAALgAECgIJAwAAAA==.Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shadowmoocow:BAAALgADCgkJEgAAAA==.Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn80AAITAAkJjAZjVQBQAQATAAkJjAZjVQBQAQAAAA==.Sheriam:BAAALgADCgcJBwAAAA==.Shikí:BAAALgAECgMJBQAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn8yAAIkAAgJyRSnGACLAQAkAAgJyRSnGACLAQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAACLgAFFH8QAAImAAQJMQ/7EwDxAAAmAAQJMQ/7EwDxAAAuAAQKfyQAAiYACAmqEvkYAGgBACYACAmqEvkYAGgBAAAA.Shotsshots:BAABLgAECn8vAAQMAAkJDB/yGwByAgAMAAkJDB/yGwByAgAYAAIJGgzHTABzAAAhAAEJAAC1kQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgAECgEJAQAAAA==.Sicaria:BAABLgAECn8WAAMkAAUJ6xknKQAeAQAkAAUJ6xknKQAeAQAGAAEJ5wqynwAwAAAAAA==.Sindina:BAAALgADCgYJBgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDgAAAA==.Skully:BAACLgAFFH8SAAISAAQJUSVPDgCeAQASAAQJUSVPDgCeAQAuAAQKfzQAAxIACQlfJekBAEMDABIACQlfJekBAEMDABoAAQkBFUqhAD4AAAAA.',
Sl='Slamdh:BAAALgAECgkJAQAAAA==.Slicedup:BAAALgAECgMJAwABLgAECggJDwAcAAAAAA==.Sluffshot:BAABLgAECn8tAAMEAAkJ6CAhCACNAgAEAAkJaCAhCACNAgABAAQJYx07twAUAQAAAA==.',
Sn='Snorina:BAACLgAFFH8KAAIfAAMJ5h5hGwAAAQAfAAMJ5h5hGwAAAQAuAAQKfzcAAh8ACQkQJd4CADYDAB8ACQkQJd4CADYDAAAA.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solina:BAAALgAECgcJBwAAAA==.Solsteece:BAAALgADCgYJDwAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAABLgAECn8xAAMSAAgJgxzRDwA3AgASAAgJgxzRDwA3AgAbAAMJxgc7aQByAAAAAA==.Sosozen:BAABLgAECn8jAAIbAAgJsw4IKgBeAQAbAAgJsw4IKgBeAQAAAA==.Soul:BAAALgAECgcJEAAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgcJEAAcAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Sparkgrace:BAAALgADCgEJAQAAAA==.Spirittoast:BAAALgAECgUJDQAAAA==.Spluffshot:BAAALgAECgIJAgAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAABLgAECn8bAAICAAkJkg0YYAC5AQACAAkJkg0YYAC5AQAAAA==.',
Sq='Squelch:BAAALgAECgQJDAAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Stratovarius:BAAALgAECgUJBQAAAA==.Strumpet:BAAALgAECgQJBQAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAABLgAECn8XAAIMAAkJYxzhFQCaAgAMAAkJYxzhFQCaAgABLgAECggJHgAFAL0WAA==.Swytch:BAABLgAECn8pAAIHAAkJ8xeeBQASAgAHAAkJ8xeeBQASAgAAAA==.',
Sy='Sylrytherin:BAABLgAECn8VAAMVAAcJkBokHQAXAgAVAAcJkBokHQAXAgAQAAEJAABjhgAAAAABLgAFFAMJCgAfAOYeAA==.Sylvii:BAABLgAECn88AAMRAAgJ1Be5IAA4AgARAAgJ1Be5IAA4AgAVAAYJRxGJOgAZAQAAAA==.',
Ta='Tabor:BAABLgAECn8cAAIRAAYJcB8YJgAUAgARAAYJcB8YJgAUAgAAAA==.Takachance:BAAALgAECgIJAgAAAA==.Talio:BAAALgAECgEJAQAAAA==.Tammyfaye:BAAALgAECgEJAQABLgAECggJJwAEANYWAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAABLgAECn8dAAILAAgJ1xb6GgAhAgALAAgJ1xb6GgAhAgAAAA==.Tauryel:BAAALgAECgYJDQAAAA==.',
Te='Tebook:BAABLgAECn8sAAMBAAkJLh2AQgD0AQABAAkJLh2AQgD0AQAdAAEJvwZaOgAoAAAAAA==.Telath:BAACLgAFFH8KAAIDAAQJlQnwVADcAAADAAQJlQnwVADcAAAuAAQKfyUAAgMACQk8Gf48AAACAAMACQk8Gf48AAACAAAA.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8XAAIDAAcJFSFhEQAFAgADAAcJFSFhEQAFAgAuAAQKfyYAAgMACQm0IF4aALYCAAMACQm0IF4aALYCAAAA.Thistlechi:BAABLgAECn8mAAIbAAgJnBozEAB9AgAbAAgJnBozEAB9AgAAAA==.Thyck:BAABLgAECn8hAAIMAAgJzRhHRQDFAQAMAAgJzRhHRQDFAQAAAA==.Thydis:BAAALgAECggJEwAAAA==.',
Ti='Tibbs:BAABLgAECn8eAAIoAAkJEg42KQCUAQAoAAkJEg42KQCUAQAAAA==.Timber:BAAALgAECgQJBwAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Toatasi:BAAALgADCgYJBgAAAA==.Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJDAAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAACLgAFFH8IAAIlAAMJCBOKDADZAAAlAAMJCBOKDADZAAAuAAQKfxoAAiUACAmpFikNANMBACUACAmpFikNANMBAAAA.',
Tu='Tuckr:BAAALgADCgQJBAAAAA==.Tullamore:BAAALgAECgcJCgAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgcJDgAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQaAAcJrBHqLQBJAQAaAAYJHxHqLQBJAQAbAAUJjw04ZACAAAASAAEJWgD1mAAbAAAAAA==.Tylerblevins:BAAALgADCgMJAwAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAFFAcJEwARAIgYAA==.',
Un='Uncorrupted:BAABLgAECn83AAIKAAgJtx2ACABCAgAKAAgJtx2ACABCAgAAAA==.Unholymilk:BAAALgAECgEJAQAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAAALgAECgYJEwAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAABLgAECn8rAAIMAAcJoBrQOwDlAQAMAAcJoBrQOwDlAQAAAA==.Vasdepherens:BAABLgAECn8iAAIEAAkJShMJGACbAQAEAAkJShMJGACbAQAAAA==.',
Ve='Velan:BAAALgADCgcJEQAAAA==.Vermouth:BAABLgAECn8jAAMbAAgJdxGcLABNAQAbAAgJdxGcLABNAQAaAAYJ6AKGegCOAAAAAA==.',
Vi='Vindrelis:BAAALgADCggJEwAAAA==.Violêt:BAABLgAECn8bAAICAAYJwQVY4QDSAAACAAYJwQVY4QDSAAAAAA==.',
Vo='Voidchris:BAABLgAFFH8GAAIDAAQJjhVrOAAuAQADAAQJjhVrOAAuAQAAAA==.Voidfang:BAAALgADCgEJAQAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgADCgcJCAAAAA==.Volkanegos:BAABLgAECn8cAAMGAAYJ2QMXawCnAAAGAAYJ2QMXawCnAAAkAAEJuwCOSwAGAAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
We='Weedmaan:BAAALgAECgUJBQAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwAAAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAFFAUJFgAGABoiAA==.Wizerwar:BAACLgAFFH8WAAIGAAUJGiJQDACQAQAGAAUJGiJQDACQAQAuAAQKf1EAAgYACQnRJMoCAD4DAAYACQnRJMoCAD4DAAAA.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAABLgAECn8dAAICAAgJYRpnQAAVAgACAAgJYRpnQAAVAgAAAA==.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgcJBwAAAA==.',
Ya='Yadiyada:BAAALgAECggJDgABLgAECggJFAADAFgKAA==.',
Yl='Ylzera:BAAALgAECgEJAgABLgAECgYJCQAcAAAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIiAAYJywiIOQDAAAAiAAYJywiIOQDAAAAAAA==.Yoshì:BAAALgAECgUJBQAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAABLgAECggJGwACAOgXAA==.Zakuren:BAABLgAECn9FAAIMAAkJZxZrJABFAgAMAAkJZxZrJABFAgAAAA==.',
Zi='Ziggibrew:BAAALgAECgQJBAABLgAECgYJEAAcAAAAAA==.',
Zo='Zombied:BAAALgAECgEJBwAAAA==.Zort:BAAALgAECgcJAQAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAABLgAECn8iAAICAAYJ9BC3qwAjAQACAAYJ9BC3qwAjAQAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8lAAQoAAkJSBGCMQBlAQAoAAcJaRSCMQBlAQAXAAUJgwnnMwDOAAApAAUJBQs3KwDDAAAAAA==.',
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
