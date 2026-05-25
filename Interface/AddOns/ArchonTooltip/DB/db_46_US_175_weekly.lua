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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Druid-Guardian','Druid-Restoration','Monk-Brewmaster','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','DeathKnight-Blood','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Druid-Feral','Warrior-Protection','Hunter-Survival','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abiotic:BAAALgAECgEJAgAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ac='Acesup:BAAALgAECgIJAgAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.',
Ai='Aings:BAACLgAFFH8FAAIBAAIJqySOfgDWAAABAAIJqySOfgDWAAAuAAQKfy0AAgEACQnLIoYMAOkCAAEACQnLIoYMAOkCAAAA.',
Al='Alarus:BAAALgADCgEJAQAAAA==.Aletaa:BAAALgAECgcJAQABLgAFFAQJDAACAMcTAA==.Alex:BAABLgAECn83AAIDAAkJJh52EACjAgADAAkJJh52EACjAgAAAA==.Alivathor:BAAALgAECgYJCQABLgAECgYJDwAEAAAAAA==.Allypally:BAABLgAECn8bAAIFAAkJig2dbwBvAQAFAAkJig2dbwBvAQAAAA==.Althir:BAABLgAECn8rAAICAAkJBSDsJQDbAgACAAkJBSDsJQDbAgAAAA==.Althorian:BAAALgAECgQJAgAAAA==.',
Am='Amgrod:BAEBLgAECn8aAAIGAAgJyQTfSAD5AAAGAAgJyQTfSAD5AAAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCggJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8eAAIFAAcJ5hh2YwCKAQAFAAcJ5hh2YwCKAQAAAA==.',
Ar='Arfas:BAAALgAECgcJCwAAAA==.Arkhitype:BAABLgAECn8xAAQHAAgJKhspBAAxAgAHAAgJKhspBAAxAgAIAAYJuQ+xMACBAQAJAAEJGQb+IAAgAAAAAA==.Armak:BAAALgADCgEJAgAAAA==.Arwenibria:BAAALgAECgEJAQAAAA==.',
As='Ashdritha:BAAALgAECgEJAQAAAA==.Ashya:BAAALgADCgYJBgAAAA==.Asur:BAABLgAECn8mAAMFAAgJxw+KYQCOAQAFAAgJxw+KYQCOAQAKAAUJYgHcOwBIAAAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Aunica:BAAALgADCgQJBAAAAA==.Auracorusca:BAABLgAECn8ZAAILAAgJ+CQsBwD2AgALAAgJ+CQsBwD2AgAAAA==.Auris:BAAALgADCgQJBwAAAA==.',
Ay='Aynilith:BAAALgAECgUJBwAAAA==.',
Ba='Bajr:BAABLgAECn8qAAIMAAkJjg6zQAC0AQAMAAkJjg6zQAC0AQAAAA==.Bakura:BAABLgAECn8iAAINAAkJzhxkBAA5AgANAAkJzhxkBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8hAAIDAAkJOROMQwCbAQADAAkJOROMQwCbAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.Barudd:BAAALgADCgEJAQAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAACLgAFFH8FAAIOAAMJNR7uAAANAQAOAAMJNR7uAAANAQAuAAQKf0oAAg4ACQk0JDYAAD0DAA4ACQk0JDYAAD0DAAAA.Berserk:BAAALgADCgIJAgAAAA==.Bestchance:BAAALgAECgEJAQAAAA==.Beware:BAAALgADCgIJAgAAAA==.Beärlylegäl:BAAALgAECgEJAgAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJDQABLgAECgkJNAAPAJAkAA==.Bigbear:BAABLgAECn8bAAMQAAgJ9yMsAwDUAgAQAAgJ9yMsAwDUAgARAAYJ6xbWWABIAQABLgAFFAQJEgASAFElAA==.Bigtamer:BAAALgADCgMJAwAAAA==.Bisan:BAAALgADCgUJBgAAAA==.',
Bj='Bjebo:BAACLgAFFH8HAAITAAMJMAXHKQCsAAATAAMJMAXHKQCsAAAuAAQKfzAAAhMACQmWEGsbAMABABMACQmWEGsbAMABAAAA.',
Bl='Blaank:BAABLgAECn8aAAIFAAgJVxA0YACRAQAFAAgJVxA0YACRAQAAAA==.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.',
Bo='Boba:BAACLgAFFH8LAAMUAAMJiSR2HgA4AQAUAAMJiSR2HgA4AQAVAAEJ1wFsRAA4AAAuAAQKfxYAAxQABwlWJGYUAHsCABQABwlWJGYUAHsCABUABgmtH/cdAMUBAAEuAAUUBgkXABYAIhoA.Boku:BAAALgAECgEJAQAAAA==.Borealiswolf:BAAALgAFFAMJAwAAAA==.Borg:BAAALgAFFAEJAQAAAA==.',
Br='Bremena:BAAALgADCgMJAwAAAA==.Brewchew:BAAALgAECgYJDgAAAA==.Brynjalf:BAAALgAECgUJCAAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bï']='Bïcho:BAABLgAECn80AAQPAAkJkCQvBAA8AwAPAAkJkCQvBAA8AwANAAEJAAB7HwB1AAAXAAEJ+RmsbQA5AAAAAA==.',
Ca='Calambar:BAAALgAECgEJAQAAAA==.Calib:BAACLgAFFH8PAAIVAAQJxhV6GAAjAQAVAAQJxhV6GAAjAQAuAAQKfy0AAhUACAnVIiERAD8CABUACAnVIiERAD8CAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgAECgIJAwAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQAYAKwRAA==.Cheechin:BAABLgAECn8aAAIZAAgJnx/SCQCCAgAZAAgJnx/SCQCCAgABLgAFFAQJFgACAMcUAA==.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAABLgAECn8lAAITAAgJ+hUDGwDEAQATAAgJ+hUDGwDEAQAAAA==.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn8yAAIVAAgJ8yIdCgCZAgAVAAgJ8yIdCgCZAgAAAA==.',
Co='Coffeeshot:BAAALgADCgEJAQAAAA==.Comboost:BAAALgADCggJCAABLgADCgkJCQAEAAAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8aAAMaAAUJMCIzBQBZAQAaAAQJMCIzBQBZAQABAAEJAADN4QAAAAAuAAQKfzcAAhoACQlCI0IAAJMDABoACQlCI0IAAJMDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.',
Cu='Cup:BAABLgAECn8oAAMLAAkJsB15CADeAgALAAkJsB15CADeAgAFAAEJQBVlQwE+AAAAAA==.',
Cv='Cvv:BAAALgAECgUJBgABLgAECgYJEAAEAAAAAA==.',
Cy='Cyndreya:BAACLgAFFH8TAAIbAAQJFBoJGQBCAQAbAAQJFBoJGQBCAQAuAAQKfzsAAhsACQmmI9UBAJMDABsACQmmI9UBAJMDAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Daelaris:BAABLgAECn8gAAICAAkJSB2vFADDAgACAAkJSB2vFADDAgAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darmil:BAAALgADCggJEwAAAA==.Davegrôwl:BAAALgAECgUJBAABLgAECgcJGwAcAOUTAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Deathbrand:BAAALgAECggJDQAAAA==.Dedbhang:BAAALgAECgcJBwAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Demonblades:BAABLgAECn8iAAIDAAkJExNzNQDQAQADAAkJExNzNQDQAQAAAA==.Demonicpixie:BAAALgADCgkJDwAAAA==.Denarten:BAAALgADCgQJBAABLgAECgcJGQAOAO8eAA==.Devotegoat:BAAALgAECgUJCAAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtymorris:BAABLgAECn8sAAMdAAkJExHZFQD4AQAdAAkJExHZFQD4AQAeAAYJ0xSAMAB/AQAAAA==.',
Do='Docignis:BAABLgAECn8XAAIVAAgJXA+8NQAzAQAVAAgJXA+8NQAzAQAAAA==.Dockevorkian:BAACLgAFFH8QAAIeAAQJlyBJCgBrAQAeAAQJlyBJCgBrAQAuAAQKfy4AAh4ACQklIToGAOsCAB4ACQklIToGAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECggJFwAVAFwPAA==.Docrhada:BAAALgAECgQJBQABLgAECggJFwAVAFwPAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAABLgAECn8YAAIDAAgJUhymJAAeAgADAAgJUhymJAAeAgABLgAFFAYJFAABAI0gAA==.',
Dr='Dracoradk:BAAALgAECgYJBwABLgAECggJDQAEAAAAAA==.Dracoramonk:BAAALgAECggJDQAAAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Dricex:BAAALgAECgYJBgAAAA==.Drinnagon:BAAALgAECgMJBwABLgAECgcJGQAOAO8eAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAOAO8eAA==.Drinntellect:BAABLgAECn8ZAAMOAAcJ7x6rBQDPAQAOAAYJCh+rBQDPAQACAAcJ1RpqhwDDAQAAAA==.Drraxx:BAAALgAECgUJBQAAAA==.Drunkdino:BAAALgADCgUJBQAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Dunnstunns:BAAALgADCgcJBwAAAA==.Duskwälker:BAAALgADCgcJBwAAAA==.',
Dx='Dxanatos:BAABLgAECn8pAAIfAAkJiQivDQBbAQAfAAkJiQivDQBbAQAAAA==.',
['Dø']='Døuce:BAAALgADCgUJAwAAAA==.',
Ea='Eamass:BAABLgAECn8rAAISAAkJSSHhBADbAgASAAkJSSHhBADbAgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn8mAAIcAAgJ6Q95HQA6AQAcAAgJ6Q95HQA6AQAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJFwACAG0VAA==.',
En='Enanthate:BAAALgADCgMJBQABLgAECgYJEAAEAAAAAA==.Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8UAAQBAAYJjSCJHACeAQABAAUJSR+JHACeAQAaAAQJ9xWzCAAmAQAcAAEJAADJOQAAAAAuAAQKfysAAwEACQm6I0cNADADAAEACQmLI0cNADADABoAAQmgJDQiAGQAAAAA.Enthing:BAACLgAFFH8TAAIDAAQJCREgNQAeAQADAAQJCREgNQAeAQAuAAQKfzsAAgMACQlqHloOALYCAAMACQlqHloOALYCAAAA.',
Es='Essamond:BAAALgAECgQJBAAAAA==.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAABLgAECn8cAAIeAAgJPyY6AgBqAwAeAAgJPyY6AgBqAwAAAA==.Famiki:BAAALgADCgYJCAAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatheral:BAABLgAECn8bAAIdAAkJpBUyGQDXAQAdAAkJpBUyGQDXAQAAAA==.',
Fe='Felaxare:BAAALgAECgcJDQAAAA==.Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8kAAQDAAkJ+xxRKAALAgADAAgJFBlRKAALAgAgAAgJlhqkFwALAgAhAAYJCBiIDQB+AQAAAA==.Fentagram:BAABLgAECn8jAAMNAAkJnCX7AQCyAgANAAgJdSb7AQCyAgAPAAQJkSF6hQAZAQAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgADCgEJAQAAAA==.',
Fl='Floofwall:BAABLgAECn8dAAISAAgJ2h3HDABKAgASAAgJ2h3HDABKAgAAAA==.',
Fo='Follet:BAAALgADCgQJAwAAAA==.Fonyfish:BAACLgAFFH8GAAIPAAQJ4RikLgBMAQAPAAQJ4RikLgBMAQAuAAQKf0AAAw8ACQkUI0sFACcDAA8ACQkUI0sFACcDABcAAgmwEm5RAHoAAAAA.Fonytime:BAAALgAECgYJBgABLgAFFAQJBgAPAOEYAA==.Foxinshocks:BAABLgAECn8dAAMUAAgJQRwkFQB1AgAUAAgJQRwkFQB1AgAiAAQJZwj/IgCKAAAAAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8sAAQXAAkJiRBeCwBcAQAPAAgJ6AuAXABzAQAXAAgJwRBeCwBcAQANAAEJAADLOAAAAAAAAA==.Foxydots:BAAALgADCgcJCgAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgAECgMJAwABLgAECgcJGwAcAOUTAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAABLgAECn8rAAMZAAgJ+SErCwBsAgAZAAgJ+SErCwBsAgASAAcJYAv4NQAJAQAAAA==.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Gg='Ggakkaltigad:BAAALgAECggJCgAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8VAAIGAAUJPx31CQBYAQAGAAUJPx31CQBYAQAuAAQKfyUAAwYACAmmJHQHADEDAAYACAmCJHQHADEDACMAAgnRGUspAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8XAAIVAAYJhBkwRwDmAAAVAAYJhBkwRwDmAAABLgAFFAUJGgAaADAiAA==.Glorm:BAABLgAECn8nAAIUAAkJtw7OMQC9AQAUAAkJtw7OMQC9AQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAABLgAECn8bAAMcAAcJ5RMDHgA1AQAcAAcJBxMDHgA1AQABAAYJJwqTrQDuAAAAAA==.Grantul:BAABLgAECn8pAAIGAAkJXhzPFgCWAgAGAAkJXhzPFgCWAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAABLgAECn8VAAIDAAYJEh6ZRACXAQADAAYJEh6ZRACXAQABLgAFFAQJEgASAFElAA==.Grolgan:BAABLgAECn8UAAIMAAYJRg3/fAAWAQAMAAYJRg3/fAAWAQAAAA==.Growlings:BAABLgAECn8UAAITAAcJtBZ4IgCIAQATAAcJtBZ4IgCIAQAAAA==.',
Gu='Guilarth:BAAALgADCgYJCQAAAA==.Guncow:BAAALgAECgEJAQAAAA==.',
Ha='Hailmary:BAAALgADCgIJAgAAAA==.Hawktuâh:BAAALgADCgEJAQAAAA==.',
He='Healiostrasz:BAAALgAECgQJBgAAAA==.Healyeah:BAAALgAECgMJBAAAAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgYJCwAAAA==.Holyczar:BAAALgADCgkJFQAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hr='Hruun:BAAALgADCgIJAgAAAA==.',
Hu='Hubirt:BAABLgAECn8mAAIFAAgJ/hhWTgC+AQAFAAgJ/hhWTgC+AQAAAA==.Huntsybuntsy:BAACLgAFFH8JAAMiAAQJPxNVBgAkAQAiAAQJPxNVBgAkAQAVAAIJvQKxNwBzAAAuAAQKfzgAAyIACQlgIKABAP8CACIACQlgIKABAP8CABUACAkzFoQbADYCAAAA.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJFwACAG0VAA==.',
Hy='Hydrafoil:BAAALgAECgYJCQAAAA==.',
Ia='Ianthel:BAAALgAECgUJCwAAAA==.',
Ic='Icesloth:BAABLgAECn8ZAAIVAAgJvRBYLABnAQAVAAgJvRBYLABnAQAAAA==.',
Id='Idamae:BAABLgAECn8VAAICAAgJpAFq5QCtAAACAAgJpAFq5QCtAAAAAA==.Iduun:BAAALgAECgUJDQAAAA==.',
Il='Iladelle:BAABLgAECn8mAAIDAAkJ+hC3OwC3AQADAAkJ+hC3OwC3AQAAAA==.Illidabina:BAAALgAECgYJDgABLgAECggJKwAZAPkhAA==.',
In='Inariokami:BAAALgAECggJEwAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.',
Io='Iorak:BAAALgADCgQJBAAAAA==.',
Ir='Irocky:BAAALgADCgkJCQAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgMJBgAAAA==.',
Ja='Jaaygee:BAAALgAECgYJEQABLgAECgcJJQAPAEokAA==.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAACLgAFFH8GAAIPAAMJpBVKVwDqAAAPAAMJpBVKVwDqAAAuAAQKfzUAAxcACAlGIP4EAIsCABcACAlbGf4EAIsCAA8ACAlGIK0aAGoCAAAA.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8bAAIeAAcJLhNKJQB3AQAeAAcJLhNKJQB3AQAAAA==.',
Je='Jelliebean:BAAALgADCgYJBgAAAA==.Jessalba:BAAALgAECgMJBAAAAA==.Jestorian:BAAALgAECgYJDwAAAA==.',
Ji='Jirakaidae:BAAALgAECgcJEgAAAA==.',
Jo='Jockinonmytw:BAACLgAFFH8MAAIIAAQJqSFsDQBrAQAIAAQJqSFsDQBrAQAuAAQKf0EAAggACQlDJYEBAEYDAAgACQlDJYEBAEYDAAAA.Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCwAAAA==.Juicyfists:BAAALgAECgEJAQAAAA==.Justice:BAAALgADCgEJAQAAAA==.Justred:BAABLgAECn8VAAMGAAYJeRQ1PQAoAQAGAAYJeRQ1PQAoAQAjAAMJaA9vPQCcAAAAAA==.',
Jx='Jxson:BAABLgAECn8mAAUQAAYJACAmDgDFAQAQAAYJtx8mDgDFAQARAAYJxRRkVwBMAQATAAYJCBLHOAD+AAAkAAMJfhI+IwC8AAABLgAECgcJJQAPAEokAA==.Jxsong:BAAALgAFFAEJAQABLgAECgcJJQAPAEokAA==.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ka='Kaisel:BAAALgADCgYJBwAAAA==.Kanoa:BAAALgADCgYJBgAAAA==.Kantuo:BAAALgAECgYJDAAAAA==.Kattschitt:BAAALgAECgEJAQAAAA==.',
Ke='Keanx:BAAALgAECgEJAwAAAA==.Kehila:BAAALgADCgEJAQAAAA==.Kendorwar:BAAALgAECgkJAwAAAA==.',
Kh='Khelad:BAACLgAFFH8WAAIFAAQJBhPzLQAzAQAFAAQJBhPzLQAzAQAuAAQKfxoAAwUACQkcGtU/AOgBAAUACQkcGtU/AOgBAAoAAQk+Cw9JACAAAAAA.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAAALgAECgQJCQAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killt:BAABLgAECn8gAAIUAAkJxRQvIgASAgAUAAkJxRQvIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAABLgAECn8YAAIlAAcJFhBgHwANAQAlAAcJFhBgHwANAQAAAA==.',
Ky='Kynthe:BAAALgAECggJDgAAAA==.Kyongye:BAAALgAECgkJDQAAAA==.',
La='Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8WAAMMAAQJ5x1kGwBUAQAMAAQJ5x1kGwBUAQAfAAIJ7AhvIACTAAAuAAQKf0oAAwwACQl4JAkDAEgDAAwACQl4JAkDAEgDAB8ACAkEG54aAFUCAAAA.',
Le='Leadgut:BAAALgADCgQJBwAAAA==.Lemanjá:BAABLgAECn8mAAIfAAgJswvlDwA1AQAfAAgJswvlDwA1AQAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Liliane:BAABLgAECn8cAAMKAAkJkQzuGwAKAQAFAAYJ8QdVnQAaAQAKAAgJMAzuGwAKAQAAAA==.Limbless:BAAALgAECgYJDAABLgAECgYJDQAEAAAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockrocks:BAAALgAECgQJBAABLgAECggJHAAFAL0WAA==.Lockstar:BAAALgADCgUJDAABLgAECggJDQAEAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAABLgAECn8YAAITAAYJ9gpnQQDVAAATAAYJ9gpnQQDVAAAAAA==.Loozer:BAABLgAECn8cAAMFAAgJvRb6WgCdAQAFAAgJvRb6WgCdAQAKAAUJxgg2OgBWAAAAAA==.',
Lu='Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAAALgAECgYJEQAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8gAAMBAAgJXhmJOwDwAQABAAgJXhmJOwDwAQAaAAEJywjmGAAsAAAAAA==.',
Ma='Magelyman:BAABLgAECn8bAAICAAkJaRi6JQBoAgACAAkJaRi6JQBoAgAAAA==.Magetiger:BAABLgAECn8YAAICAAgJExXIUwDEAQACAAgJExXIUwDEAQAAAA==.Magsh:BAAALgADCgQJBAAAAA==.Malitheion:BAAALgAECgYJDgAAAA==.Malyce:BAAALgAECgEJAQABLgAECggJFQASAAEXAA==.Malzen:BAABLgAECn8VAAMSAAgJARegHQCZAQASAAgJARegHQCZAQAZAAEJ9AtBhAAuAAAAAA==.Manaleia:BAAALgADCgcJBwAAAA==.Manasolid:BAABLgAECn80AAICAAgJ9xcUPQALAgACAAgJ9xcUPQALAgAAAA==.Mangeømbre:BAAALgAECgQJBAAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgAECgUJBgAAAA==.Masculinedh:BAAALgAECgIJAwABLgAECgYJEAAEAAAAAA==.',
Me='Meanka:BAAALgAECgEJAQABLgAFFAMJCgAdAOYeAA==.Meatcurtin:BAAALgADCggJCgAAAA==.Meches:BAAALgAECgQJCAABLgAECgYJNgARAGoXAA==.Mediocre:BAAALgAECgEJAQAAAA==.Mediocritty:BAAALgAECgYJCgABLgAECggJIgAiAOkOAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAABLgAECn8gAAICAAgJCAjVhQBPAQACAAgJCAjVhQBPAQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Meraleona:BAAALgAECgUJBQABLgAECgkJLAABAC4dAA==.Methslinger:BAAALgAECggJDwAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Milkwithpulp:BAABLgAECn8kAAIeAAgJ/xX6GADdAQAeAAgJ/xX6GADdAQAAAA==.',
Mk='Mkoons:BAAALgAECgEJBAAAAA==.',
Mo='Mook:BAAALgAECgYJBgABLgAECggJDgAEAAAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAABLgAECn8WAAIXAAcJBQZvGQC4AAAXAAcJBQZvGQC4AAAAAA==.Mortmuzi:BAAALgAECgIJAgAAAA==.Mosrael:BAAALgAECgkJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.',
Mu='Mulas:BAABLgAECn8kAAIPAAkJqxa6IgA9AgAPAAkJqxa6IgA9AgAAAA==.Muldah:BAACLgAFFH8WAAICAAQJxxQvPwBFAQACAAQJxxQvPwBFAQAuAAQKfzEAAgIACQlrIL0WALYCAAIACQlrIL0WALYCAAAA.',
My='Mynte:BAABLgAECn8eAAIeAAYJnBKCLQA7AQAeAAYJnBKCLQA7AQAAAA==.',
['Mä']='Mäsion:BAAALgAFFAQJBAAAAA==.',
Na='Natty:BAAALgADCgkJIAAAAA==.Navie:BAABLgAECn8jAAIbAAkJnArCHAC5AQAbAAkJnArCHAC5AQAAAA==.Nawperwoman:BAABLgAECn8oAAMZAAgJvhvtEgBcAgAZAAgJvhvtEgBcAgAYAAEJrgGhdgAYAAAAAA==.Nazevroth:BAAALgAECgQJBAAAAA==.Nazgûl:BAABLgAFFH8FAAIBAAMJMxrpZAABAQABAAMJMxrpZAABAQAAAA==.',
Ne='Necronomicob:BAABLgAECn8jAAIPAAkJmRgtIwA6AgAPAAkJmRgtIwA6AgAAAA==.Neil:BAAALgADCgUJBQABLgAFFAUJDAAUALUHAA==.Nekros:BAABLgAECn8tAAQPAAgJ1yB1HQBaAgAPAAcJDyB1HQBaAgAXAAQJaBxUJQAyAQANAAIJqB0uHACeAAAAAA==.Neø:BAABLgAECn8mAAMBAAgJjBV3UQCsAQABAAgJjBV3UQCsAQAaAAMJoAr0JABRAAAAAA==.',
Ni='Nianna:BAAALgADCgMJAwAAAA==.Nicebud:BAAALgAECgMJBAAAAA==.Nightsfury:BAAALgAECgcJCwAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAAALgAECgYJDwAAAA==.Nornyr:BAABLgAECn8kAAIYAAgJAhcVHAD3AQAYAAgJAhcVHAD3AQAAAA==.Noxiss:BAAALgADCgQJBAABLgAECgkJLAABAC4dAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn80AAITAAgJ+g10KABcAQATAAgJ+g10KABcAQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oriax:BAABLgAECn8eAAIPAAcJmxLzYQBlAQAPAAcJmxLzYQBlAQAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgMJAwAAAA==.',
Pa='Paean:BAAALgAECgUJDQAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8kAAMRAAgJgAbafwDbAAARAAcJVATafwDbAAATAAQJ+gKjZwBRAAAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBgAEAAAAAA==.Peata:BAAALgAECgEJAQAAAA==.Persephones:BAABLgAECn8fAAIdAAcJ4A/eJwCaAQAdAAcJ4A/eJwCaAQAAAA==.',
Ph='Phenelope:BAAALgAECggJEQAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECggJEwAEAAAAAA==.Pillowpuhmpa:BAAALgAECgIJBAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgAECgIJAgAAAA==.',
Pk='Pkalygos:BAABLgAECn8eAAIWAAkJlRNUDQDWAQAWAAkJlRNUDQDWAQAAAA==.',
Po='Poosnwoods:BAAALgAECgYJDQAAAA==.Popefuffer:BAAALgAFFAIJAQAAAA==.Powerstrokee:BAABLgAECn8aAAMBAAcJGRSxYwB9AQABAAcJGRSxYwB9AQAaAAIJEQ8yIwBcAAAAAA==.',
Pr='Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAILAAgJrRzoEQCDAgALAAgJrRzoEQCDAgAAAA==.Protadin:BAABLgAECn8YAAIKAAYJwBQUFwBjAQAKAAYJwBQUFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAABLgAECn8YAAMLAAcJbgrrQwAGAQALAAYJAAzrQwAGAQAFAAIJBQj4RAE9AAAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôcky:BAAALgAECgEJAQABLgAECgkJKwASAEkhAA==.Pôps:BAAALgAECgYJEwAAAA==.',
Qu='Quickprick:BAAALgAECgcJEgAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAABLgAECggJDgAEAAAAAA==.Rasina:BAAALgAECgIJBAAAAA==.Ratkìng:BAAALgAECgMJBAAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Redcrayons:BAAALgADCgkJCQAAAA==.Reknojir:BAAALgAECgQJBAAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8WAAIDAAQJ3BYUKwA7AQADAAQJ3BYUKwA7AQAuAAQKfz4AAwMACQkzIfsGAAgDAAMACQkzIfsGAAgDACAABgkAEcs6ABUBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgYJDgAAAA==.Rizar:BAAALgAECgUJBQAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgYJDQAEAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn8vAAIQAAkJvAJaLwCnAAAQAAkJvAJaLwCnAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.',
Ru='Runeclad:BAABLgAECn8cAAIBAAkJnRWQMwANAgABAAkJnRWQMwANAgAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámi:BAAALgADCgEJAgAAAA==.',
Sa='Saauurrora:BAAALgAECgcJBwAAAA==.Sabiton:BAAALgADCgYJCgAAAA==.Saintshift:BAAALgADCgYJDAABLgAECgYJEAAEAAAAAA==.Salitheion:BAABLgAECn8aAAILAAgJIROWIgDJAQALAAgJIROWIgDJAQAAAA==.Saloraith:BAAALgAECgcJDQAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Sanaig:BAAALgADCgcJBwAAAA==.Sanatura:BAAALgAECgYJCwAAAA==.Sapper:BAABLgAECn8vAAIYAAkJ4CDbBQAbAwAYAAkJ4CDbBQAbAwAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgQJCwAAAA==.Sarn:BAABLgAECn8bAAIQAAkJpxI3DwCIAQAQAAkJpxI3DwCIAQAAAA==.Sathi:BAAALgAECgcJAgAAAA==.Saudhum:BAABLgAECn8WAAMNAAYJwRsfCADLAQANAAYJwRsfCADLAQAPAAQJ4Q0pyACfAAAAAA==.Sayuri:BAABLgAECn8lAAIYAAgJSiLBBgAHAwAYAAgJSiLBBgAHAwAAAA==.',
Sb='Sboop:BAAALgAECgQJBwAAAA==.',
Sc='Scrím:BAAALgAECgEJAQAAAA==.',
Se='Secondchance:BAAALgAECgIJAgAAAA==.Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shadowmoocow:BAAALgADCgkJCQAAAA==.Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn8rAAIUAAkJMgROUwAwAQAUAAkJMgROUwAwAQAAAA==.Shikí:BAAALgAECgEJAQAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn8pAAIjAAgJyRTXEwCYAQAjAAgJyRTXEwCYAQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAACLgAFFH8JAAIlAAMJUwzLFwCxAAAlAAMJUwzLFwCxAAAuAAQKfyQAAiUACAmqEi4VAHkBACUACAmqEi4VAHkBAAAA.Shotsshots:BAABLgAECn8vAAQMAAkJDB/EFACDAgAMAAkJDB/EFACDAgAmAAIJGgxDRQB0AAAfAAEJAAC1kQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgAECgEJAQAAAA==.Sicaria:BAABLgAECn8WAAMjAAUJ6xl5IgAjAQAjAAUJ6xl5IgAjAQAGAAEJ5wrcjAAwAAAAAA==.Sindina:BAAALgADCgYJBgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDgAAAA==.Skully:BAACLgAFFH8SAAISAAQJUSXjCACtAQASAAQJUSXjCACtAQAuAAQKfzMAAhIACQlfJWYBAEkDABIACQlfJWYBAEkDAAAA.',
Sl='Slicedup:BAAALgAECgMJAwABLgAECggJDQAEAAAAAA==.Sluffshot:BAABLgAECn8tAAMcAAkJ6CAxBgCdAgAcAAkJaCAxBgCdAgABAAQJYx07twAUAQAAAA==.',
Sn='Snorina:BAACLgAFFH8KAAIdAAMJ5h7UFgATAQAdAAMJ5h7UFgATAQAuAAQKfzcAAh0ACQkQJSICAD8DAB0ACQkQJSICAD8DAAAA.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solina:BAAALgAECgcJBwAAAA==.Solsteece:BAAALgADCgYJDwAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAABLgAECn8kAAMSAAgJgxy/DQA9AgASAAgJgxy/DQA9AgAZAAEJWgmQjQApAAAAAA==.Sosozen:BAABLgAECn8aAAIZAAgJ2wvDMAAaAQAZAAgJ2wvDMAAaAQAAAA==.Soul:BAAALgAECgcJDwAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgcJDwAEAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Sparkgrace:BAAALgADCgEJAQAAAA==.Spirittoast:BAAALgAECgUJDQAAAA==.Spluffshot:BAAALgAECgIJAgAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAABLgAECn8aAAICAAgJwQ5SawCIAQACAAgJwQ5SawCIAQAAAA==.',
Sq='Squelch:BAAALgAECgQJBwAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Stratovarius:BAAALgAECgUJBQAAAA==.Strumpet:BAAALgAECgQJBQAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAAALgAECggJDwABLgAECggJHAAFAL0WAA==.Swytch:BAABLgAECn8pAAIHAAkJ8xelBAAdAgAHAAkJ8xelBAAdAgAAAA==.',
Sy='Sylrytherin:BAABLgAECn8UAAITAAcJkBokHQAXAgATAAcJkBokHQAXAgABLgAFFAMJCgAdAOYeAA==.Sylvii:BAABLgAECn82AAMRAAYJahf0OACQAQARAAYJahf0OACQAQATAAYJRxF/MwAaAQAAAA==.',
Ta='Tabor:BAAALgAECgYJEgAAAA==.Takachance:BAAALgAECgIJAgAAAA==.Tammyfaye:BAAALgADCgEJAQABLgAECgcJGwAcAOUTAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAABLgAECn8ZAAILAAgJXxWbHQDvAQALAAgJXxWbHQDvAQAAAA==.Tauryel:BAAALgAECgYJDQAAAA==.',
Te='Tebook:BAABLgAECn8sAAMBAAkJLh3UOAD6AQABAAkJLh3UOAD6AQAaAAEJvwZyLQAqAAAAAA==.Telath:BAACLgAFFH8KAAIDAAQJlQkrRADuAAADAAQJlQkrRADuAAAuAAQKfyUAAgMACQk8Gf48AAACAAMACQk8Gf48AAACAAAA.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8VAAIDAAYJ7RrbFwCVAQADAAYJ7RrbFwCVAQAuAAQKfyEAAgMACAkAIF4aALYCAAMACAkAIF4aALYCAAAA.Thistlechi:BAABLgAECn8jAAIZAAgJIxkzEAB9AgAZAAgJIxkzEAB9AgAAAA==.Thyck:BAABLgAECn8hAAIMAAgJzRj5OQDMAQAMAAgJzRj5OQDMAQAAAA==.Thydis:BAAALgAECggJEgAAAA==.',
Ti='Tibbs:BAABLgAECn8eAAInAAkJEg41JACZAQAnAAkJEg41JACZAQAAAA==.Timber:BAAALgAECgQJBwAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJDAAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAABLgAECn8aAAIkAAgJqRaFCgDjAQAkAAgJqRaFCgDjAQAAAA==.',
Tu='Tullamore:BAAALgAECgIJAwAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgcJDgAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQYAAcJrBHqLQBJAQAYAAYJHxHqLQBJAQAZAAUJjw0TVwCEAAASAAEJWgD1mAAbAAAAAA==.Tylerblevins:BAAALgADCgMJAwAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAFFAYJEQARAOoYAA==.',
Un='Uncorrupted:BAABLgAECn8iAAIKAAgJpxwZCQASAgAKAAgJpxwZCQASAgAAAA==.Unholymilk:BAAALgAECgEJAQAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAAALgAECgYJEwAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAABLgAECn8lAAIMAAYJGhlgUQCAAQAMAAYJGhlgUQCAAQAAAA==.Vasdepherens:BAABLgAECn8iAAIcAAkJShMJGACbAQAcAAkJShMJGACbAQAAAA==.',
Ve='Velan:BAAALgADCgcJEQAAAA==.Vermouth:BAABLgAECn8jAAMZAAgJdxEIJgBYAQAZAAgJdxEIJgBYAQAYAAYJ6AIYYQCUAAAAAA==.',
Vi='Vindrelis:BAAALgADCggJEwAAAA==.Violêt:BAABLgAECn8UAAICAAYJwgQ71QDJAAACAAYJwgQ71QDJAAAAAA==.',
Vo='Voidchris:BAAALgAECgcJDgAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgADCgcJCAAAAA==.Volkanegos:BAABLgAECn8bAAMGAAYJ2QMCXwCpAAAGAAYJ2QMCXwCpAAAjAAEJuwCOSwAGAAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
We='Weedmaan:BAAALgADCgYJBgAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwAAAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAFFAQJDAAGAE8dAA==.Wizerwar:BAACLgAFFH8MAAIGAAQJTx11DwBXAQAGAAQJTx11DwBXAQAuAAQKf1EAAgYACQnRJMIBAEsDAAYACQnRJMIBAEsDAAAA.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAABLgAECn8YAAICAAgJThkJRgDuAQACAAgJThkJRgDuAQAAAA==.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgYJBgAAAA==.',
Ya='Yadiyada:BAAALgAECggJDgAAAA==.',
Yl='Ylzera:BAAALgAECgEJAgABLgAECgQJBgAEAAAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIgAAYJywizMADHAAAgAAYJywizMADHAAAAAA==.Yoshì:BAAALgAECgUJBQAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAABLgAECggJGwACAOgXAA==.Zakuren:BAABLgAECn86AAIMAAkJDRQMIwAtAgAMAAkJDRQMIwAtAgAAAA==.',
Zi='Ziggibrew:BAAALgAECgMJAwABLgAECgYJEAAEAAAAAA==.',
Zo='Zombied:BAAALgAECgEJBgAAAA==.Zort:BAAALgAECgcJAQAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAABLgAECn8gAAICAAYJ9BDpmQArAQACAAYJ9BDpmQArAQAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8kAAQnAAgJSBILLABnAQAnAAcJaRQLLABnAQAWAAUJgwnnMwDOAAAoAAQJNAs3KwDDAAAAAA==.',
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
