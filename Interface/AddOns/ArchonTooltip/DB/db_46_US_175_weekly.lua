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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Druid-Guardian','Druid-Restoration','Monk-Brewmaster','Shaman-Restoration','Shaman-Enhancement','Druid-Balance','Shaman-Elemental','Evoker-Preservation','Hunter-Survival','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','DeathKnight-Blood','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Druid-Feral','Warrior-Protection','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abiotic:BAAALgAECgEJAwAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ac='Acesup:BAAALgAECgIJAwAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.Aesir:BAAALgADCgYJBQAAAA==.',
Ai='Aings:BAACLgAFFH8FAAIBAAIJqyQ0jQDPAAABAAIJqyQ0jQDPAAAuAAQKfy0AAgEACQnLIucOAOMCAAEACQnLIucOAOMCAAAA.',
Al='Alarus:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCggJCAAAAA==.Aletaa:BAAALgAECgcJAQABLgAFFAQJDAACAMcTAA==.Alex:BAABLgAECn83AAIDAAkJJh53EgCbAgADAAkJJh53EgCbAgAAAA==.Alivathor:BAAALgAECgYJCQABLgAECgYJEAAEAAAAAA==.Allypally:BAABLgAECn8bAAIFAAkJig0ngABUAQAFAAkJig0ngABUAQAAAA==.Althir:BAABLgAECn8rAAICAAkJBSDsJQDbAgACAAkJBSDsJQDbAgAAAA==.Althorian:BAAALgAECgQJAgAAAA==.',
Am='Amgrod:BAEBLgAECn8cAAIGAAkJyAXBPgA0AQAGAAkJyAXBPgA0AQAAAA==.Amythest:BAAALgADCgYJBgAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCggJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8eAAIFAAcJ5hiSawB+AQAFAAcJ5hiSawB+AQAAAA==.',
Ar='Arfas:BAAALgAECgcJCwAAAA==.Arkhitype:BAABLgAECn86AAQHAAkJ9huVAgCVAgAHAAkJ9huVAgCVAgAIAAYJuQ+xMACBAQAJAAEJGQYrJAAgAAAAAA==.Armak:BAAALgADCgEJAgAAAA==.Arwenibria:BAAALgAECgEJAQAAAA==.',
As='Ashdritha:BAAALgAECgEJAQAAAA==.Ashya:BAAALgADCgYJBgAAAA==.Asur:BAABLgAECn8oAAMFAAgJahGMZACNAQAFAAgJahGMZACNAQAKAAUJYgG7QABIAAAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Aunica:BAAALgADCgQJBAAAAA==.Auracorusca:BAABLgAECn8bAAILAAkJeiTDAwBSAwALAAkJeiTDAwBSAwAAAA==.Auris:BAAALgADCgQJBwAAAA==.',
Ay='Aynilith:BAAALgAECgYJCAAAAA==.Aystarael:BAAALgAECgkJBgAAAA==.',
Ba='Bajr:BAABLgAECn8qAAIMAAkJjg4qRwC0AQAMAAkJjg4qRwC0AQAAAA==.Bakura:BAABLgAECn8iAAINAAkJzhxkBAA5AgANAAkJzhxkBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8hAAIDAAkJORNATACJAQADAAkJORNATACJAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.Barudd:BAAALgADCgEJAQAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAACLgAFFH8GAAIOAAMJNR5MAQAAAQAOAAMJNR5MAQAAAQAuAAQKf0wAAw4ACQk0JEkAAC4DAA4ACQk0JEkAAC4DAAIAAQlcEMpOAS4AAAAA.Berserk:BAAALgADCgIJAgAAAA==.Bestchance:BAAALgAECgEJAQAAAA==.Beware:BAAALgADCgIJAgAAAA==.Beärlylegäl:BAAALgAECgEJAgAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJDQABLgAFFAMJBwAPAPcbAA==.Bigbear:BAACLgAFFH8IAAIQAAQJth+OBQB3AQAQAAQJth+OBQB3AQAuAAQKfxsAAxAACAn3I6sDANMCABAACAn3I6sDANMCABEABgnrFtZYAEgBAAEuAAUUBAkSABIAUSUA.Bigdave:BAABLgAECn8jAAMTAAgJ3B7AEACyAgATAAgJ3B7AEACyAgAUAAQJZwgnJwCKAAAAAA==.Bigtamer:BAAALgADCgMJAwAAAA==.Bisan:BAAALgADCgUJBgAAAA==.',
Bj='Bjebo:BAACLgAFFH8LAAIVAAQJQwXaKAC+AAAVAAQJQwXaKAC+AAAuAAQKfzcAAhUACQkvE5oYAPABABUACQkvE5oYAPABAAAA.',
Bl='Blaank:BAACLgAFFH8GAAIFAAMJWAOZbACqAAAFAAMJWAOZbACqAAAuAAQKfx4AAgUACAlkFDBLAM0BAAUACAlkFDBLAM0BAAAA.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.',
Bo='Boba:BAACLgAFFH8LAAMTAAMJiSQQJAAzAQATAAMJiSQQJAAzAQAWAAEJ1wHJTAA1AAAuAAQKfxYAAxMABwlWJPMWAHkCABMABwlWJPMWAHkCABYABgmtH+EgAMQBAAEuAAUUBgkXABcAIhoA.Boku:BAAALgAECgEJAQAAAA==.Borealiswolf:BAAALgAFFAMJAwAAAA==.Borg:BAABLgAFFH8FAAMYAAMJsByeFQAPAQAYAAMJmxmeFQAPAQAMAAEJsCD8egBiAAAAAA==.',
Br='Bremena:BAAALgADCgMJAwAAAA==.Brewchew:BAABLgAECn8cAAISAAgJ0w6XKABcAQASAAgJ0w6XKABcAQAAAA==.Brynjalf:BAAALgAECgUJCAAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bï']='Bïcho:BAACLgAFFH8HAAMPAAMJ9xsZZQDgAAAPAAIJcSUZZQDgAAANAAEJAwlWIQBGAAAuAAQKfzUABA8ACQkpJSgEAEUDAA8ACQkpJSgEAEUDAA0AAQkAAHsfAHUAABkAAQn5GaxtADkAAAAA.',
Ca='Calambar:BAAALgAECgEJAQAAAA==.Calib:BAACLgAFFH8UAAIWAAUJxhWQHQAQAQAWAAUJxhWQHQAQAQAuAAQKfy8AAhYACQkSICcOAHQCABYACQkSICcOAHQCAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgAECgIJAwAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQAaAKwRAA==.Cheechin:BAABLgAECn8aAAIbAAgJnx8OCwB+AgAbAAgJnx8OCwB+AgABLgAFFAQJFgACAMcUAA==.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAACLgAFFH8FAAIVAAIJ6wgGNwBvAAAVAAIJ6wgGNwBvAAAuAAQKfyYAAhUACAn6FZ0dAMIBABUACAn6FZ0dAMIBAAAA.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn80AAIWAAgJ8yKSCwCVAgAWAAgJ8yKSCwCVAgAAAA==.',
Co='Coffeeshot:BAAALgADCgEJAQAAAA==.Comboost:BAAALgADCggJCAABLgADCgkJEgAEAAAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8eAAMcAAUJMCKLBQBoAQAcAAQJMCKLBQBoAQABAAEJAAAx/AAAAAAuAAQKfzcAAhwACQlCI0IAAJMDABwACQlCI0IAAJMDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.',
Cu='Cup:BAABLgAECn8oAAMLAAkJsB3cCQDZAgALAAkJsB3cCQDZAgAFAAEJQBXRWgE9AAAAAA==.',
Cv='Cvv:BAAALgAECgUJBgABLgAECgYJEAAEAAAAAA==.',
Cy='Cyndreya:BAACLgAFFH8YAAIdAAUJjhmtFQCJAQAdAAUJjhmtFQCJAQAuAAQKfz0AAh0ACQkUJOwBAJIDAB0ACQkUJOwBAJIDAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Daelaris:BAABLgAECn8gAAICAAkJSB2hFwC2AgACAAkJSB2hFwC2AgAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darmil:BAAALgADCggJEwAAAA==.Davegrôwl:BAAALgAECgUJBAABLgAECggJJQAeAGYVAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Deathbrand:BAAALgAECggJDwAAAA==.Dedbhang:BAAALgAFFAMJAwAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Demonblades:BAABLgAECn8iAAIDAAkJExMXOgDHAQADAAkJExMXOgDHAQAAAA==.Demonicpixie:BAAALgADCgkJDwAAAA==.Denarten:BAAALgADCgQJBAABLgAECgcJGQAOAO8eAA==.Devotegoat:BAAALgAECgUJCAAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtymorris:BAACLgAFFH8FAAIfAAMJ9QsUIADNAAAfAAMJ9QsUIADNAAAuAAQKfy4AAx8ACQkTEXEYAOcBAB8ACQkTEXEYAOcBACAABwk6FtknAHEBAAAA.',
Do='Docignis:BAABLgAECn8XAAIWAAgJXA9LOgAxAQAWAAgJXA9LOgAxAQAAAA==.Dockevorkian:BAACLgAFFH8VAAIgAAUJbSD+BQDJAQAgAAUJbSD+BQDJAQAuAAQKfzAAAiAACQklIToGAOsCACAACQklIToGAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECggJFwAWAFwPAA==.Docrhada:BAAALgAECgQJBQABLgAECggJFwAWAFwPAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAABLgAECn8YAAIDAAgJUhzsJwAWAgADAAgJUhzsJwAWAgABLgAFFAYJFAABAI0gAA==.',
Dr='Dracoradk:BAAALgAECgYJBwABLgAFFAQJBAAEAAAAAA==.Dracoramonk:BAAALgAFFAQJBAAAAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Dricex:BAAALgAECgYJCQAAAA==.Drinnagon:BAAALgAECgMJBwABLgAECgcJGQAOAO8eAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAOAO8eAA==.Drinntellect:BAABLgAECn8ZAAMOAAcJ7x6rBQDPAQAOAAYJCh+rBQDPAQACAAcJ1RpqhwDDAQAAAA==.Drraxx:BAAALgAECgUJBQAAAA==.Drunkdino:BAAALgADCgUJBQAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Dunnstunns:BAAALgAECgIJAgAAAA==.Duskwälker:BAAALgADCgcJBwAAAA==.',
Dx='Dxanatos:BAABLgAECn8pAAIhAAkJiQjYDgBVAQAhAAkJiQjYDgBVAQAAAA==.',
['Dø']='Døuce:BAAALgADCgUJAwAAAA==.',
Ea='Eamass:BAABLgAECn8rAAISAAkJSSGhBQDWAgASAAkJSSGhBQDWAgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.Eiré:BAAALgADCgQJBAAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn8vAAIeAAkJixD1FgCUAQAeAAkJixD1FgCUAQAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJFwACAG0VAA==.',
En='Enanthate:BAAALgADCgMJBQABLgAECgYJEAAEAAAAAA==.Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8UAAQBAAYJjSANJwCRAQABAAUJSR8NJwCRAQAcAAQJ9xUwCwAcAQAeAAEJAAC8QQAAAAAuAAQKfysAAwEACQm6I0cNADADAAEACQmLI0cNADADABwAAQmgJG8mAGMAAAAA.Enthing:BAACLgAFFH8YAAIDAAUJCRGxPgARAQADAAUJCRGxPgARAQAuAAQKfz0AAgMACQmtH3INAMYCAAMACQmtH3INAMYCAAAA.',
Es='Essamond:BAAALgAECgQJBAAAAA==.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAABLgAECn8cAAIgAAgJPya8AgBjAwAgAAgJPya8AgBjAwAAAA==.Famiki:BAAALgADCggJDwAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatheral:BAABLgAECn8bAAIfAAkJpBWIGwDMAQAfAAkJpBWIGwDMAQAAAA==.',
Fe='Felaxare:BAAALgAECgcJDQAAAA==.Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8kAAQDAAkJ+xzAKwAEAgAiAAgJlhqkFwALAgADAAgJFBnAKwAEAgAjAAYJCBiIDQB+AQAAAA==.Fentagram:BAABLgAECn8jAAMNAAkJnCX7AQCyAgANAAgJdSb7AQCyAgAPAAQJkSF1jQAWAQAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgADCgUJBgAAAA==.',
Fl='Floofwall:BAABLgAECn8hAAISAAgJMx4tDQBRAgASAAgJMx4tDQBRAgAAAA==.',
Fo='Follet:BAAALgADCgQJBwAAAA==.Fonyfish:BAACLgAFFH8GAAIPAAQJ4RiYOQBCAQAPAAQJ4RiYOQBCAQAuAAQKf0AAAw8ACQkUIz4GACEDAA8ACQkUIz4GACEDABkAAgmwEm5RAHoAAAAA.Fonytime:BAAALgAECgYJBgABLgAFFAQJBgAPAOEYAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8sAAQZAAkJiRC2DABWAQAPAAgJ6Au9YwBsAQAZAAgJwRC2DABWAQANAAEJAAC0PwAAAAAAAA==.Foxydots:BAAALgADCgcJCgAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgAECgMJAwABLgAECggJJQAeAGYVAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAABLgAECn8sAAQbAAgJ+SGSDABnAgAbAAgJ+SGSDABnAgASAAcJYAt7OQAFAQAaAAEJHgoMqwAgAAABLgAFFAIJAgAEAAAAAA==.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Gg='Ggakkaltigad:BAAALgAECggJCgAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8XAAIGAAYJmxu8CQCWAQAGAAYJmxu8CQCWAQAuAAQKfyUAAwYACAmmJHQHADEDAAYACAmCJHQHADEDACQAAgnRGUspAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8XAAIWAAYJhBnWTADlAAAWAAYJhBnWTADlAAABLgAFFAUJHgAcADAiAA==.Glorm:BAABLgAECn8nAAITAAkJtw5eNgC8AQATAAkJtw5eNgC8AQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAABLgAECn8lAAMeAAgJZhVrFwCPAQAeAAgJZhVrFwCPAQABAAYJfQqOtAD3AAAAAA==.Grantul:BAABLgAECn8pAAIGAAkJXhzPFgCWAgAGAAkJXhzPFgCWAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAABLgAECn8VAAIDAAYJEh53SQCSAQADAAYJEh53SQCSAQABLgAFFAQJEgASAFElAA==.Grolgan:BAABLgAECn8VAAIMAAYJDA6/hAAcAQAMAAYJDA6/hAAcAQAAAA==.Growlings:BAABLgAECn8cAAIVAAgJYxnyFAATAgAVAAgJYxnyFAATAgAAAA==.',
Gu='Guncow:BAAALgAECgEJAQAAAA==.',
Ha='Hailmary:BAAALgADCgIJAgAAAA==.Hawktuâh:BAAALgADCgEJAQABLgAECggJJQAeAGYVAA==.',
He='Healiostrasz:BAAALgAECgQJBgAAAA==.Healyeah:BAAALgAECgMJBAAAAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgYJCwABLgAECggJHgAFANgWAA==.Holyczar:BAAALgADCgkJGwAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hr='Hruun:BAAALgADCgIJAgAAAA==.',
Hu='Hubirt:BAABLgAECn8mAAIFAAgJ/hjVVQCwAQAFAAgJ/hjVVQCwAQAAAA==.Huntsybuntsy:BAACLgAFFH8OAAMUAAUJxBUsBgA+AQAUAAUJxBUsBgA+AQAWAAIJvQIgPwBqAAAuAAQKfzgAAxQACQlgIP0BAPkCABQACQlgIP0BAPkCABYACAkzFoQbADYCAAAA.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJFwACAG0VAA==.',
Hy='Hydrafoil:BAAALgAECgYJDQAAAA==.',
Ia='Ianthel:BAAALgAECgUJCwAAAA==.',
Ic='Icesloth:BAABLgAECn8bAAIWAAkJKxKGIQC/AQAWAAkJKxKGIQC/AQAAAA==.',
Id='Idamae:BAABLgAECn8XAAICAAkJ1AEq3wC6AAACAAkJ1AEq3wC6AAAAAA==.Iduun:BAAALgAECgUJDQAAAA==.',
Il='Iladelle:BAABLgAECn8mAAIDAAkJ+hDLQACvAQADAAkJ+hDLQACvAQAAAA==.Illidabina:BAAALgAFFAIJAgAAAA==.',
In='Inariokami:BAABLgAECn8XAAISAAkJKAlbKABdAQASAAkJKAlbKABdAQAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.',
Io='Iorak:BAAALgADCgQJBAAAAA==.',
Ir='Irinon:BAAALgAECgEJAQAAAA==.Irocky:BAAALgADCgkJCQAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgMJBgAAAA==.',
Ja='Jaaygee:BAABLgAECn8YAAIJAAcJHx90BAAlAgAJAAcJHx90BAAlAgABLgAECgcJJwAPAJgkAA==.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAACLgAFFH8HAAIPAAMJSxpeWQD8AAAPAAMJSxpeWQD8AAAuAAQKfzkAAw8ACQkgIj8JAP0CAA8ACQkgIj8JAP0CABkACAlbGf4EAIsCAAAA.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8bAAIgAAcJLhOpJwBzAQAgAAcJLhOpJwBzAQAAAA==.',
Je='Jelliebean:BAAALgADCgYJBgAAAA==.Jessalba:BAAALgAECgMJBAAAAA==.Jestorian:BAAALgAECgYJEgAAAA==.',
Ji='Jirakaidae:BAABLgAECn8WAAIVAAcJjQSlSwDAAAAVAAcJjQSlSwDAAAAAAA==.',
Jo='Jockinonmytw:BAACLgAFFH8MAAIIAAQJqSFLEQBdAQAIAAQJqSFLEQBdAQAuAAQKf0EAAggACQlDJeMBADwDAAgACQlDJeMBADwDAAAA.Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCwAAAA==.Juicyfists:BAAALgAECgEJAQAAAA==.Justice:BAAALgADCgEJAQAAAA==.Justred:BAABLgAECn8VAAMGAAYJeRQvQgAkAQAGAAYJeRQvQgAkAQAkAAMJaA83RACbAAAAAA==.',
Jx='Jxson:BAABLgAECn8mAAUQAAYJACA6EADDAQAQAAYJtx86EADDAQARAAYJxRRkVwBMAQAVAAYJCBJmPQD9AAAlAAMJfhI+IwC8AAABLgAECgcJJwAPAJgkAA==.Jxsong:BAAALgAFFAEJAgABLgAECgcJJwAPAJgkAA==.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ka='Kaisel:BAAALgADCgYJCwAAAA==.Kandrys:BAAALgAECgIJAgAAAA==.Kanoa:BAAALgADCgYJBgAAAA==.Kantuo:BAAALgAFFAQJBAAAAA==.',
Ke='Keanx:BAAALgAECgEJAwAAAA==.Kehila:BAAALgADCgEJAQAAAA==.Kendorwar:BAAALgAECgkJAwAAAA==.',
Kh='Khelad:BAACLgAFFH8aAAIFAAQJBhOcNQAoAQAFAAQJBhOcNQAoAQAuAAQKfxoAAwUACQkcGnJIANUBAAUACQkcGnJIANUBAAoAAQk+CxxPACAAAAAA.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAAALgAECgUJDwAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killt:BAABLgAECn8gAAITAAkJxRQvIgASAgATAAkJxRQvIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAABLgAECn8bAAImAAcJQxGvHgAjAQAmAAcJQxGvHgAjAQAAAA==.',
Ku='Kurzulan:BAAALgAECgQJBAABLgAECgYJCQAEAAAAAA==.',
Ky='Kynthe:BAAALgAECggJDgAAAA==.Kyongye:BAAALgAECgkJDQAAAA==.',
La='Lacerater:BAAALgADCgcJCgAAAA==.Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8aAAMMAAQJ5x0pJgBLAQAMAAQJ5x0pJgBLAQAhAAIJ7AhvIACTAAAuAAQKf0oAAwwACQl4JA4EAEIDAAwACQl4JA4EAEIDACEACAkEG54aAFUCAAAA.',
Le='Leadgut:BAAALgADCgQJBwAAAA==.Lemanjá:BAABLgAECn8qAAIhAAkJtg6XCgCsAQAhAAkJtg6XCgCsAQAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Liliane:BAABLgAECn8cAAMKAAkJkQxZHgAIAQAFAAYJ8QcpqAAPAQAKAAgJMAxZHgAIAQAAAA==.Limbless:BAAALgAECgYJDAABLgAECgYJDQAEAAAAAA==.Littletoast:BAAALgAECgUJBgAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockrocks:BAAALgAECgQJCAABLgAECggJHgAFAL0WAA==.Lockstar:BAAALgADCgUJDAABLgAECggJDwAEAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAABLgAECn8ZAAIVAAYJ9gpgRgDVAAAVAAYJ9gpgRgDVAAAAAA==.Loozer:BAABLgAECn8eAAMFAAgJvRaPYgCRAQAFAAgJvRaPYgCRAQAKAAUJxgg2OgBWAAAAAA==.',
Lu='Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAABLgAECn8UAAIFAAYJzQl3yADeAAAFAAYJzQl3yADeAAAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8jAAMBAAkJMBoNKABOAgABAAkJMBoNKABOAgAcAAEJywjmGAAsAAAAAA==.',
Ma='Magelyman:BAABLgAECn8cAAICAAkJJRmiJQBvAgACAAkJJRmiJQBvAgAAAA==.Magetiger:BAABLgAECn8aAAICAAkJPhRzQAAEAgACAAkJPhRzQAAEAgAAAA==.Magsh:BAAALgADCgQJBAAAAA==.Malitheion:BAAALgAECgYJEgAAAA==.Malyce:BAAALgAECgIJAgABLgAECggJFQASAAEXAA==.Malzen:BAABLgAECn8VAAMSAAgJARfZHwCWAQASAAgJARfZHwCWAQAbAAEJ9AtxkgAtAAAAAA==.Manaleia:BAAALgADCgcJDAAAAA==.Manasolid:BAABLgAECn88AAICAAkJZxWuNgAmAgACAAkJZxWuNgAmAgAAAA==.Mangeømbre:BAAALgAECgQJBAAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgAECgYJCQAAAA==.Masculinedh:BAAALgAECgIJAwABLgAECgYJEAAEAAAAAA==.',
Me='Meanka:BAAALgAECgEJAQABLgAFFAMJCgAfAOYeAA==.Meatcurtin:BAAALgADCgkJEQAAAA==.Meches:BAAALgAECgQJCAABLgAECggJPAARANQXAA==.Mediocre:BAAALgAECgIJAgAAAA==.Mediocritty:BAAALgAECgYJCgABLgAECggJIgAUAOkOAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAABLgAECn8kAAICAAgJyAgOjgBAAQACAAgJyAgOjgBAAQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Meraleona:BAAALgAECgUJBQABLgAECgkJLAABAC4dAA==.Methslinger:BAABLgAECn8VAAIWAAYJoA3xSAD0AAAWAAYJoA3xSAD0AAAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Milkwithpulp:BAABLgAECn8kAAIgAAgJ/xVWGwDWAQAgAAgJ/xVWGwDWAQAAAA==.',
Mk='Mkoons:BAAALgAECgEJBAAAAA==.',
Mo='Monkanical:BAAALgADCgYJBgAAAA==.Mook:BAAALgAECgYJDAABLgAECggJDgAEAAAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAABLgAECn8WAAIZAAcJBQbsGwCzAAAZAAcJBQbsGwCzAAAAAA==.Mortmuzi:BAAALgAECgUJCwAAAA==.Mosrael:BAAALgAECgkJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.',
Mu='Mulas:BAABLgAECn8kAAIPAAkJqxbRJgA0AgAPAAkJqxbRJgA0AgAAAA==.Muldah:BAACLgAFFH8WAAICAAQJxxT1SQA6AQACAAQJxxT1SQA6AQAuAAQKfzEAAgIACQlrIKsZAKoCAAIACQlrIKsZAKoCAAAA.',
My='Mynte:BAABLgAECn8eAAIgAAYJnBKaMAA0AQAgAAYJnBKaMAA0AQAAAA==.',
['Mä']='Mäsion:BAABLgAFFH8HAAIGAAQJtwOHLQDZAAAGAAQJtwOHLQDZAAAAAA==.',
Na='Natty:BAAALgADCgkJIAAAAA==.Navie:BAABLgAECn8sAAIdAAkJrA0AGgDfAQAdAAkJrA0AGgDfAQAAAA==.Nawperwoman:BAABLgAECn8oAAMbAAgJvhvtEgBcAgAbAAgJvhvtEgBcAgAaAAEJrgGhdgAYAAAAAA==.Nazevroth:BAAALgAECgUJBQAAAA==.Nazgûl:BAABLgAFFH8FAAIBAAMJMxo2cgD6AAABAAMJMxo2cgD6AAAAAA==.',
Ne='Necronomicob:BAABLgAECn8sAAMPAAkJsxkzIwBHAgAPAAkJsxkzIwBHAgAZAAMJ7RiEFgDZAAAAAA==.Neil:BAAALgADCgUJBQABLgAFFAUJEAATAPwHAA==.Nekros:BAABLgAECn8tAAQPAAgJ1yCOIABVAgAPAAcJDyCOIABVAgAZAAQJaBxUJQAyAQANAAIJqB24HwCbAAAAAA==.Neø:BAABLgAECn8vAAMBAAgJbBmnOAAJAgABAAgJbBmnOAAJAgAcAAMJoAqBKQBRAAAAAA==.',
Ni='Nianna:BAAALgADCgcJCgAAAA==.Nicebud:BAAALgAECgUJCQAAAA==.Nightsfury:BAAALgAECgcJEQAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAAALgAECgYJEAAAAA==.Nordburg:BAAALgAECgEJAQAAAA==.Nornyr:BAABLgAECn8oAAIaAAgJAhdQHwD4AQAaAAgJAhdQHwD4AQAAAA==.Noxiss:BAAALgADCgQJBAABLgAECgkJLAABAC4dAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn88AAIVAAkJLg53IQCiAQAVAAkJLg53IQCiAQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oriax:BAABLgAECn8lAAIPAAcJmxIuaQBfAQAPAAcJmxIuaQBfAQAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgYJCgAAAA==.',
Pa='Paean:BAAALgAECgUJDQAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8mAAMRAAgJZgSAfgCtAAARAAgJZgSAfgCtAAAVAAQJ+gJIbwBRAAAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBgAEAAAAAA==.Peata:BAAALgAECgEJAgAAAA==.Persephones:BAABLgAECn8fAAIfAAcJ4A/eJwCaAQAfAAcJ4A/eJwCaAQAAAA==.',
Ph='Phenelope:BAABLgAECn8ZAAMCAAgJTgMCxwDgAAACAAgJTgMCxwDgAAAnAAcJnAE+DAB1AAAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECgkJFwASACgJAA==.Pillowpuhmpa:BAAALgAECgIJBAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgAECgIJAgAAAA==.',
Pk='Pkalygos:BAABLgAECn8eAAIXAAkJlROlDgDQAQAXAAkJlROlDgDQAQAAAA==.',
Po='Poosnwoods:BAAALgAECgYJDgAAAA==.Popefuffer:BAAALgAFFAIJAQAAAA==.Powerstrokee:BAABLgAECn8aAAMBAAcJGRSGawB6AQABAAcJGRSGawB6AQAcAAIJEQ+mKgBLAAAAAA==.',
Pr='Preyforme:BAAALgAECgQJBAAAAA==.Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAILAAgJrRzoEQCDAgALAAgJrRzoEQCDAgAAAA==.Protadin:BAABLgAECn8YAAIKAAYJwBQUFwBjAQAKAAYJwBQUFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAABLgAECn8YAAMLAAcJbgo3SAAFAQALAAYJAAw3SAAFAQAFAAIJBQhuXwE5AAAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôcky:BAAALgAECgEJAQABLgAECgkJKwASAEkhAA==.Pôps:BAAALgAECgYJEwAAAA==.',
Qu='Quickprick:BAAALgAECgcJEwAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAABLgAECggJDgAEAAAAAA==.Ranharr:BAAALgADCgQJBAAAAA==.Rasina:BAAALgAECgIJBAAAAA==.Ratkìng:BAAALgAECgMJBAAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Redcrayons:BAAALgADCgkJCQAAAA==.Reknojir:BAAALgAECgQJBQAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8aAAIDAAQJ3BZLMgAzAQADAAQJ3BZLMgAzAQAuAAQKfz4AAwMACQkzIQ8IAP8CAAMACQkzIQ8IAP8CACIABgkAEcs6ABUBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgYJDgAAAA==.Rizar:BAAALgAECgUJCgAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgYJDQAEAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn81AAIQAAkJ1gIPNQCsAAAQAAkJ1gIPNQCsAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.',
Ru='Rumhanced:BAAALgADCgkJCQAAAA==.Runeclad:BAABLgAECn8cAAIBAAkJnRWrOAAJAgABAAkJnRWrOAAJAgAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámi:BAAALgADCgEJAgAAAA==.',
['Rï']='Rïvkah:BAAALgADCgYJBgAAAA==.',
Sa='Saauurrora:BAAALgAECgcJBwAAAA==.Sabiton:BAAALgADCgYJCgAAAA==.Saintshift:BAAALgADCgYJDAABLgAECgYJEAAEAAAAAA==.Salitheion:BAABLgAECn8bAAILAAgJ/hMHIgDeAQALAAgJ/hMHIgDeAQAAAA==.Saloraith:BAAALgAECgcJDQAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Sanaig:BAAALgADCgcJBwAAAA==.Sanatura:BAAALgAECgYJCwAAAA==.Sapper:BAABLgAECn8wAAIaAAkJ4CCwBgAaAwAaAAkJ4CCwBgAaAwAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgQJCwAAAA==.Sarn:BAABLgAECn8bAAIQAAkJpxI3DwCIAQAQAAkJpxI3DwCIAQAAAA==.Sathi:BAAALgAECgcJAgAAAA==.Saudhum:BAABLgAECn8WAAMNAAYJwRsfCADLAQANAAYJwRsfCADLAQAPAAQJ4Q2F0gCeAAAAAA==.Sayuri:BAABLgAECn8tAAIaAAgJjiIhBwARAwAaAAgJjiIhBwARAwAAAA==.',
Sb='Sboop:BAAALgAECgQJBwAAAA==.',
Sc='Scrím:BAAALgAECgEJAgAAAA==.',
Se='Secondchance:BAAALgAECgIJAgAAAA==.Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shadowmoocow:BAAALgADCgkJEgAAAA==.Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn80AAITAAkJjAayUABRAQATAAkJjAayUABRAQAAAA==.Sheriam:BAAALgADCgcJBwAAAA==.Shikí:BAAALgAECgIJAwAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn8qAAIkAAgJyRQBFwCLAQAkAAgJyRQBFwCLAQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAACLgAFFH8MAAImAAQJCwtdFQDaAAAmAAQJCwtdFQDaAAAuAAQKfyQAAiYACAmqEm8XAG4BACYACAmqEm8XAG4BAAAA.Shotsshots:BAABLgAECn8vAAQMAAkJDB/RGAB7AgAMAAkJDB/RGAB7AgAYAAIJGgynSQB0AAAhAAEJAAC1kQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgAECgEJAQAAAA==.Sicaria:BAABLgAECn8WAAMkAAUJ6xlLJgAgAQAkAAUJ6xlLJgAgAQAGAAEJ5wqUlwAwAAAAAA==.Sindina:BAAALgADCgYJBgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDgAAAA==.Skully:BAACLgAFFH8SAAISAAQJUSXSCwClAQASAAQJUSXSCwClAQAuAAQKfzQAAxIACQlfJbIBAEUDABIACQlfJbIBAEUDABoAAQkBFT2TAD4AAAAA.',
Sl='Slicedup:BAAALgAECgMJAwABLgAECggJDwAEAAAAAA==.Sluffshot:BAABLgAECn8tAAMeAAkJ6CBOBwCTAgAeAAkJaCBOBwCTAgABAAQJYx07twAUAQAAAA==.',
Sn='Snorina:BAACLgAFFH8KAAIfAAMJ5h5qGQAJAQAfAAMJ5h5qGQAJAQAuAAQKfzcAAh8ACQkQJX4CADADAB8ACQkQJX4CADADAAAA.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solina:BAAALgAECgcJBwAAAA==.Solsteece:BAAALgADCgYJDwAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAABLgAECn8qAAMSAAgJgxz4DgA5AgASAAgJgxz4DgA5AgAbAAIJEQkhcwBVAAAAAA==.Sosozen:BAABLgAECn8aAAIbAAgJ2ws7NQAXAQAbAAgJ2ws7NQAXAQAAAA==.Soul:BAAALgAECgcJDwAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgcJDwAEAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Sparkgrace:BAAALgADCgEJAQAAAA==.Spirittoast:BAAALgAECgUJDQAAAA==.Spluffshot:BAAALgAECgIJAgAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAABLgAECn8bAAICAAkJkg2VXQCuAQACAAkJkg2VXQCuAQAAAA==.',
Sq='Squelch:BAAALgAECgQJCwAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Stratovarius:BAAALgAECgUJBQAAAA==.Strumpet:BAAALgAECgQJBQAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAAALgAECggJEAABLgAECggJHgAFAL0WAA==.Swytch:BAABLgAECn8pAAIHAAkJ8xdIBQAVAgAHAAkJ8xdIBQAVAgAAAA==.',
Sy='Sylrytherin:BAABLgAECn8VAAMVAAcJkBokHQAXAgAVAAcJkBokHQAXAgAQAAEJAABJegAAAAABLgAFFAMJCgAfAOYeAA==.Sylvii:BAABLgAECn88AAMRAAgJ1BcyHwA5AgARAAgJ1BcyHwA5AgAVAAYJRxG1NwAaAQAAAA==.',
Ta='Tabor:BAABLgAECn8VAAIRAAYJPR8KJQARAgARAAYJPR8KJQARAgAAAA==.Takachance:BAAALgAECgIJAgAAAA==.Talio:BAAALgADCgMJBQAAAA==.Tammyfaye:BAAALgADCgEJAQABLgAECggJJQAeAGYVAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAABLgAECn8ZAAILAAgJXxU/IADqAQALAAgJXxU/IADqAQAAAA==.Tauryel:BAAALgAECgYJDQAAAA==.',
Te='Tebook:BAABLgAECn8sAAMBAAkJLh2VPgD1AQABAAkJLh2VPgD1AQAcAAEJvwbhMwApAAAAAA==.Telath:BAACLgAFFH8KAAIDAAQJlQkBTQDkAAADAAQJlQkBTQDkAAAuAAQKfyUAAgMACQk8Gf48AAACAAMACQk8Gf48AAACAAAA.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8WAAIDAAYJayEQGACxAQADAAYJayEQGACxAQAuAAQKfyYAAgMACQm0IF4aALYCAAMACQm0IF4aALYCAAAA.Thistlechi:BAABLgAECn8lAAIbAAgJkxozEAB9AgAbAAgJkxozEAB9AgAAAA==.Thyck:BAABLgAECn8hAAIMAAgJzRjsPwDLAQAMAAgJzRjsPwDLAQAAAA==.Thydis:BAAALgAECggJEwAAAA==.',
Ti='Tibbs:BAABLgAECn8eAAIoAAkJEg4tKACHAQAoAAkJEg4tKACHAQAAAA==.Timber:BAAALgAECgQJBwAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJDAAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAABLgAECn8aAAIlAAgJqRYcDADVAQAlAAgJqRYcDADVAQAAAA==.',
Tu='Tuckr:BAAALgADCgQJBAAAAA==.Tullamore:BAAALgAECgIJAwAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgcJDgAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQaAAcJrBHqLQBJAQAaAAYJHxHqLQBJAQAbAAUJjw3VXgCDAAASAAEJWgD1mAAbAAAAAA==.Tylerblevins:BAAALgADCgMJAwAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAFFAYJEQARAOoYAA==.',
Un='Uncorrupted:BAABLgAECn8qAAIKAAgJtRwUCgARAgAKAAgJtRwUCgARAgAAAA==.Unholymilk:BAAALgAECgEJAQAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAAALgAECgYJEwAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAABLgAECn8oAAIMAAcJRRrZOADkAQAMAAcJRRrZOADkAQAAAA==.Vasdepherens:BAABLgAECn8iAAIeAAkJShMJGACbAQAeAAkJShMJGACbAQAAAA==.',
Ve='Velan:BAAALgADCgcJEQAAAA==.Vermouth:BAABLgAECn8jAAMbAAgJdxFjKQBWAQAbAAgJdxFjKQBWAQAaAAYJ6ALhbwCOAAAAAA==.',
Vi='Vindrelis:BAAALgADCggJEwAAAA==.Violêt:BAABLgAECn8VAAICAAYJUAWk3wC5AAACAAYJUAWk3wC5AAAAAA==.',
Vo='Voidchris:BAAALgAFFAEJAQAAAA==.Voidfang:BAAALgADCgEJAQAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgADCgcJCAAAAA==.Volkanegos:BAABLgAECn8cAAMGAAYJ2QPMZQCnAAAGAAYJ2QPMZQCnAAAkAAEJuwCOSwAGAAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
We='Weedmaan:BAAALgAECgUJBQAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwAAAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAFFAUJEQAGAM8eAA==.Wizerwar:BAACLgAFFH8RAAIGAAUJzx42EABkAQAGAAUJzx42EABkAQAuAAQKf1EAAgYACQnRJFECAEMDAAYACQnRJFECAEMDAAAA.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAABLgAECn8cAAICAAgJYRq/PAAQAgACAAgJYRq/PAAQAgAAAA==.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgcJBwAAAA==.',
Ya='Yadiyada:BAAALgAECggJDgAAAA==.',
Yl='Ylzera:BAAALgAECgEJAgABLgAECgUJBwAEAAAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIiAAYJywh4NQDDAAAiAAYJywh4NQDDAAAAAA==.Yoshì:BAAALgAECgUJBQAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAABLgAECggJGwACAOgXAA==.Zakuren:BAABLgAECn86AAIMAAkJDRQyKAAnAgAMAAkJDRQyKAAnAgAAAA==.',
Zi='Ziggibrew:BAAALgAECgMJAwABLgAECgYJEAAEAAAAAA==.',
Zo='Zombied:BAAALgAECgEJBgAAAA==.Zort:BAAALgAECgcJAQAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAABLgAECn8iAAICAAYJ9BAtpQAYAQACAAYJ9BAtpQAYAQAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8lAAQoAAkJSBHYLgBgAQAoAAcJaRTYLgBgAQAXAAUJgwnnMwDOAAApAAUJBQs3KwDDAAAAAA==.',
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
