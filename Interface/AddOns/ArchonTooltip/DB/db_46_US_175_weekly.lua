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

local lookup = {'DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','Monk-Brewmaster','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Warlock-Destruction','Monk-Mistweaver','DeathKnight-Frost','Priest-Discipline','Shaman-Enhancement','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','DeathKnight-Blood','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Warrior-Arms','Druid-Restoration','Druid-Guardian','Druid-Feral','Warrior-Protection','Hunter-Survival','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abiotic:BAAALgAECgEJAgAAAA==.Abonin:BAAALgAECgEJAQAAAA==.',
Ad='Adomah:BAAALgADCgUJBQAAAA==.',
Ae='Aenard:BAAALgAECgMJAwAAAA==.',
Ai='Aings:BAABLgAECn8mAAIBAAkJdyKxEACqAgABAAkJdyKxEACqAgAAAA==.',
Al='Alarus:BAAALgADCgEJAQAAAA==.Aletaa:BAAALgAECgcJAQABLgAFFAMJCwACANMXAA==.Alex:BAABLgAECn83AAIDAAkJJh6PDACnAgADAAkJJh6PDACnAgAAAA==.Alivathor:BAAALgAECgMJBAABLgAECgUJCgAEAAAAAA==.Allypally:BAABLgAECn8bAAIFAAkJig1JXwBqAQAFAAkJig1JXwBqAQAAAA==.Althir:BAABLgAECn8rAAICAAkJAiDsJQDbAgACAAkJAiDsJQDbAgAAAA==.Althorian:BAAALgAECgMJAgAAAA==.',
Am='Amgrod:BAEBLgAECn8WAAIGAAgJmQQcQAD0AAAGAAgJmQQcQAD0AAAAAA==.',
An='Anayanci:BAAALgADCgIJAgAAAA==.Anduriell:BAAALgADCgIJAgAAAA==.Angelkitty:BAAALgADCggJCQAAAA==.Anndan:BAAALgADCgEJAQAAAA==.Antemurale:BAABLgAECn8eAAIFAAcJ5hhgUgCKAQAFAAcJ5hhgUgCKAQAAAA==.',
Ar='Arfas:BAAALgAECgcJCwAAAA==.Arkhitype:BAABLgAECn8tAAQHAAgJ/xmjAwAlAgAHAAgJ/xmjAwAlAgAIAAYJuQ+xMACBAQAJAAEJGQZXGwAnAAAAAA==.Armak:BAAALgADCgEJAgAAAA==.Arwenibria:BAAALgAECgEJAQAAAA==.',
As='Ashdritha:BAAALgADCgQJBAAAAA==.Ashya:BAAALgADCgYJBgAAAA==.Asur:BAABLgAECn8eAAMFAAYJtQyxkwACAQAFAAYJtQyxkwACAQAKAAUJYQGRNABIAAAAAA==.',
Au='Aul:BAAALgADCgIJAgAAAA==.Aunica:BAAALgADCgQJBAAAAA==.Auracorusca:BAABLgAECn8WAAILAAgJ+CRJBQABAwALAAgJ+CRJBQABAwAAAA==.Auris:BAAALgADCgQJBwAAAA==.',
Ay='Aynilith:BAAALgAECgUJBgAAAA==.',
Ba='Bajr:BAABLgAECn8oAAIMAAkJig6ENAC6AQAMAAkJig6ENAC6AQAAAA==.Bakura:BAABLgAECn8iAAINAAkJzhxkBAA5AgANAAkJzhxkBAA5AgAAAA==.Balphorsus:BAAALgADCgcJBwAAAA==.Banker:BAABLgAECn8hAAIDAAkJKxPVPACKAQADAAkJKxPVPACKAQAAAA==.Baroo:BAAALgADCgcJCwAAAA==.',
Be='Belenor:BAAALgAECgUJCgAAAA==.Berko:BAABLgAECn9JAAIOAAkJMCQdAABLAwAOAAkJMCQdAABLAwAAAA==.Berserk:BAAALgADCgIJAgAAAA==.Beware:BAAALgADCgIJAgAAAA==.Beärlylegäl:BAAALgAECgEJAgAAAA==.',
Bh='Bhaang:BAAALgAECgQJBAAAAA==.',
Bi='Bicho:BAAALgAECgkJCgABLgAECgkJKAAPAFcgAA==.Bigbear:BAAALgAECggJEwABLgAFFAQJEgAQAFElAA==.Bigtamer:BAAALgADCgMJAwAAAA==.Bisan:BAAALgADCgUJBgAAAA==.',
Bj='Bjebo:BAABLgAECn8pAAIRAAkJ+w++GACvAQARAAkJ+w++GACvAQAAAA==.',
Bl='Blaank:BAABLgAECn8VAAIFAAgJlg5aVQCDAQAFAAgJlg5aVQCDAQAAAA==.Bleucheez:BAAALgADCgMJBAAAAA==.Blistex:BAAALgADCggJGAAAAA==.Bluboo:BAAALgAECgQJBAAAAA==.Bluefang:BAAALgADCgEJAQAAAA==.',
Bo='Boba:BAACLgAFFH8LAAMSAAMJiSRpFwA8AQASAAMJiSRpFwA8AQATAAEJ1wF4OgA5AAAuAAQKfxYAAxIABwlVJCwQAH8CABIABwlVJCwQAH8CABMABgmtH28YAM4BAAEuAAUUBgkXABQAIhoA.Boku:BAAALgAECgEJAQAAAA==.Borg:BAAALgAFFAEJAQAAAA==.',
Br='Bremena:BAAALgADCgMJAwAAAA==.Brewchew:BAAALgAECgYJDgAAAA==.',
Bu='Bunktrayer:BAAALgAECgMJAwAAAA==.Bunny:BAAALgADCgYJBgAAAA==.',
['Bï']='Bïcho:BAABLgAECn8oAAQPAAkJVyAODQARAwAPAAkJVyAODQARAwANAAEJAAB7HwB1AAAVAAEJ+RmsbQA5AAAAAA==.',
Ca='Calambar:BAAALgAECgEJAQAAAA==.Calib:BAACLgAFFH8PAAITAAQJxhWHEgAwAQATAAQJxhWHEgAwAQAuAAQKfy0AAhMACAnUIicNAEoCABMACAnUIicNAEoCAAAA.Calkurn:BAAALgADCgEJAQAAAA==.Calvianna:BAAALgAECgMJAwAAAA==.Casally:BAAALgADCgEJAQAAAA==.Cassiopea:BAAALgADCgcJDgAAAA==.',
Ce='Celebi:BAAALgAECgIJAwAAAA==.Celryth:BAAALgAECgkJBgAAAA==.',
Ch='Checktoi:BAAALgAECgEJAQABLgAECgcJFQAWAKwRAA==.Cheechin:BAAALgAECggJEwABLgAFFAQJEgACAI0QAA==.Cherish:BAAALgAECgUJCgAAAA==.Chewwy:BAABLgAECn8lAAIRAAgJ+hU0FwC+AQARAAgJ+hU0FwC+AQAAAA==.Chokengag:BAAALgADCgQJBQAAAA==.',
Cm='Cml:BAABLgAECn8kAAITAAgJhyIYCgB4AgATAAgJhyIYCgB4AgAAAA==.',
Co='Coffeeshot:BAAALgADCgEJAQAAAA==.Comboost:BAAALgADCggJCAABLgADCgkJCQAEAAAAAA==.',
Cr='Crabman:BAAALgAECgYJDwAAAA==.Crashcake:BAACLgAFFH8VAAIXAAQJMCLJAgBjAQAXAAQJMCLJAgBjAQAuAAQKfzMAAhcACQnYIkIAAJMDABcACQnYIkIAAJMDAAAA.Creamcheez:BAAALgADCgYJBgAAAA==.Crimsonghost:BAAALgADCgIJAQAAAA==.',
Cu='Cup:BAABLgAECn8nAAILAAkJsB3yBQDxAgALAAkJsB3yBQDxAgAAAA==.',
Cv='Cvv:BAAALgAECgUJBQABLgAECgYJEAAEAAAAAA==.',
Cy='Cyndreya:BAACLgAFFH8PAAIYAAQJFBroEwBJAQAYAAQJFBroEwBJAQAuAAQKfzIAAhgACQmfI58BAIMDABgACQmfI58BAIMDAAAA.Cywen:BAAALgADCgYJCQAAAA==.',
Da='Daelaris:BAABLgAECn8YAAICAAgJcxvQLwAYAgACAAgJcxvQLwAYAgAAAA==.Danagor:BAAALgADCgYJCQAAAA==.Danielan:BAAALgADCgEJAgAAAA==.Darmil:BAAALgADCggJEwAAAA==.',
De='Deadlyalba:BAAALgADCgMJAwAAAA==.Deathbrand:BAAALgAECgUJBgAAAA==.Defonde:BAAALgAECgMJAwAAAA==.Dejavu:BAABLgAECn8WAAMSAAYJ4h2bIQDvAQASAAYJ4h2bIQDvAQAZAAMJZwg5HQCKAAAAAA==.Demonblades:BAABLgAECn8iAAIDAAkJExMRLgDHAQADAAkJExMRLgDHAQAAAA==.Demonicpixie:BAAALgADCgkJDwAAAA==.Denarten:BAAALgADCgQJBAABLgAECgcJGQAOAO4eAA==.Devotegoat:BAAALgAECgUJCAAAAA==.',
Di='Dinonuggy:BAAALgADCgQJBAAAAA==.Dirtymorris:BAABLgAECn8mAAMaAAkJKQ3vGACtAQAaAAkJKQ3vGACtAQAbAAYJ0xSAMAB/AQAAAA==.',
Do='Docignis:BAABLgAECn8XAAITAAgJXA9GLQA3AQATAAgJXA9GLQA3AQAAAA==.Dockevorkian:BAACLgAFFH8MAAIbAAQJwB7nCABcAQAbAAQJwB7nCABcAQAuAAQKfywAAhsACQklIToGAOsCABsACQklIToGAOsCAAAA.Docmelo:BAAALgADCgYJBgABLgAECggJFwATAFwPAA==.Docrhada:BAAALgAECgQJBQABLgAECggJFwATAFwPAA==.Dojo:BAAALgADCggJEQAAAA==.Doublebonus:BAABLgAECn8YAAIDAAgJURxSHQAhAgADAAgJURxSHQAhAgABLgAFFAYJFAABAI0gAA==.',
Dr='Dracoradk:BAAALgAECgIJAgABLgAECggJDQAEAAAAAA==.Dracoramonk:BAAALgAECggJDQAAAA==.Drainedsaint:BAAALgADCgMJAwAAAA==.Dricex:BAAALgAECgEJAQAAAA==.Drinnagon:BAAALgAECgIJBQABLgAECgcJGQAOAO4eAA==.Drinnokan:BAAALgADCgUJBQABLgAECgcJGQAOAO4eAA==.Drinntellect:BAABLgAECn8ZAAMOAAcJ7h6rBQDPAQAOAAYJCh+rBQDPAQACAAcJ0xoQawBnAQAAAA==.Drraxx:BAAALgAECgUJBQAAAA==.Dryx:BAAALgADCgcJBwAAAA==.',
Du='Dumdög:BAAALgAECgEJAgAAAA==.Dunnstunns:BAAALgADCgcJBwAAAA==.Duskwälker:BAAALgADCgcJBwAAAA==.',
Dx='Dxanatos:BAABLgAECn8pAAIcAAkJiAgpCwAzAQAcAAkJiAgpCwAzAQAAAA==.',
['Dø']='Døuce:BAAALgADCgUJAwAAAA==.',
Ea='Eamass:BAABLgAECn8qAAIQAAkJQCGvAwDjAgAQAAkJQCGvAwDjAgAAAA==.',
Eh='Ehyopeta:BAAALgADCgQJBAAAAA==.',
Ei='Einmyria:BAAALgAECgUJCwAAAA==.',
El='Elenara:BAAALgADCgUJBQAAAA==.Elilla:BAABLgAECn8iAAIdAAgJ6Q8kHAANAQAdAAgJ6Q8kHAANAQAAAA==.Elorela:BAAALgADCgUJBgABLgAECgYJFwACAG0VAA==.',
En='Enanthate:BAAALgADCgMJBQABLgAECgYJEAAEAAAAAA==.Endvoid:BAAALgADCgQJBAAAAA==.Enjoy:BAACLgAFFH8UAAQBAAYJjSDTDgBnAQABAAUJSR/TDgBnAQAXAAQJ9xUXBQAxAQAdAAEJAAA9MAAAAAAuAAQKfysAAwEACQm4I0cNADADAAEACQmJI0cNADADABcAAQmgJO0aAGYAAAAA.Enthing:BAACLgAFFH8PAAIDAAQJlQ2QMAAVAQADAAQJlQ2QMAAVAQAuAAQKfzIAAgMACQm1HH8VAFcCAAMACQm1HH8VAFcCAAAA.',
Ex='Excaliber:BAAALgAECgQJBwAAAA==.Excalimental:BAAALgADCgUJBQAAAA==.',
Fa='Faing:BAAALgADCgIJAgAAAA==.Faithfulness:BAABLgAECn8cAAIbAAgJPyaXAQByAwAbAAgJPyaXAQByAwAAAA==.Famiki:BAAALgADCgQJBQAAAA==.Farlack:BAAALgADCgEJAQAAAA==.Fatheral:BAABLgAECn8WAAIaAAgJyBNBMQBbAQAaAAgJyBNBMQBbAQAAAA==.',
Fe='Felaxare:BAAALgAECgcJDAAAAA==.Felintu:BAAALgAECgIJAgAAAA==.Felnollid:BAABLgAECn8eAAQeAAgJvh2kFwALAgAeAAgJlBqkFwALAgAfAAYJCBiIDQB+AQADAAQJlB30TwBIAQAAAA==.Fentagram:BAABLgAECn8hAAMNAAgJcSb7AQCyAgANAAgJcSb7AQCyAgAPAAMJMSLSoAC+AAAAAA==.Fentangled:BAAALgADCgUJBQAAAA==.',
Fi='Fionni:BAAALgADCgEJAQAAAA==.',
Fl='Floofwall:BAABLgAECn8XAAIQAAgJXhl8EAD8AQAQAAgJXhl8EAD8AQAAAA==.',
Fo='Fonyfish:BAABLgAECn8yAAMPAAkJCSP4BgD4AgAPAAkJCSP4BgD4AgAVAAIJsBJuUQB6AAAAAA==.Fonytime:BAAALgAECgYJBgABLgAECgkJMgAPAAkjAA==.Foxpalm:BAAALgAECgYJCQAAAA==.Foxramas:BAABLgAECn8sAAQVAAkJiRDDCQBZAQAPAAgJ5wvHTwBvAQAVAAgJwBDDCQBZAQANAAEJAACnLQAAAAAAAA==.Foxydots:BAAALgADCgcJCgAAAA==.',
Fr='Friendless:BAAALgADCgEJAgAAAA==.Fromage:BAAALgAECgMJAwABLgAECgYJGAAdAHURAA==.Frostdflake:BAAALgADCgEJAQAAAA==.Frànk:BAAALgADCgMJAwAAAA==.',
Fu='Fubina:BAABLgAECn8rAAMgAAgJ+SGNCAB2AgAgAAgJ+SGNCAB2AgAQAAcJYAsYLwAOAQAAAA==.Funkymou:BAAALgAECgMJAwAAAA==.',
Fy='Fyjalla:BAAALgADCgkJCwAAAA==.',
Gg='Ggakkaltigad:BAAALgAECggJCgAAAA==.',
Gi='Gilgämesh:BAACLgAFFH8VAAIGAAUJPx2xDgBIAQAGAAUJPx2xDgBIAQAuAAQKfyUAAwYACAmmJHQHADEDAAYACAmCJHQHADEDACEAAgnRGUspAKYAAAAA.',
Gl='Gladator:BAAALgAECgUJBQAAAA==.Glorb:BAABLgAECn8WAAITAAYJhBmCPADrAAATAAYJhBmCPADrAAABLgAFFAQJFQAXADAiAA==.Glorm:BAABLgAECn8nAAISAAkJtw52KQDAAQASAAkJtw52KQDAAQAAAA==.',
Go='Gordo:BAAALgADCgMJAwAAAA==.Gorghr:BAAALgAECgUJBwAAAA==.',
Gr='Graatch:BAAALgADCgYJBgAAAA==.Grabbyhands:BAABLgAECn8YAAMdAAYJdRFZIQDiAAABAAYJJwrWkgD5AAAdAAYJahBZIQDiAAAAAA==.Grantul:BAABLgAECn8pAAIGAAkJXhzPFgCWAgAGAAkJXhzPFgCWAgAAAA==.Grax:BAAALgAECgMJBAAAAA==.Greasmon:BAAALgAECgYJEgABLgAFFAQJEgAQAFElAA==.Grolgan:BAAALgAECgYJDgAAAA==.Growlings:BAAALgAECgYJDQAAAA==.',
Gu='Guilarth:BAAALgADCgYJCQAAAA==.Guncow:BAAALgAECgEJAQAAAA==.',
Ha='Hailmary:BAAALgADCgIJAgAAAA==.Hawktuâh:BAAALgADCgEJAQAAAA==.',
He='Healiostrasz:BAAALgAECgMJBQAAAA==.Healyeah:BAAALgAECgMJBAAAAA==.Heftyheifer:BAAALgAECgUJCgAAAA==.Hermos:BAAALgADCgYJCAAAAA==.',
Ho='Holdi:BAAALgAECgQJBQABLgAECgYJGwAFAA0YAA==.Holyczar:BAAALgADCgcJCQAAAA==.Holyoke:BAAALgADCgYJBwAAAA==.',
Hr='Hruun:BAAALgADCgIJAgAAAA==.',
Hu='Hubirt:BAABLgAECn8mAAIFAAgJ/RitPwDBAQAFAAgJ/RitPwDBAQAAAA==.Huntsybuntsy:BAABLgAECn8qAAMTAAgJ3BiEGwA2AgATAAgJMxaEGwA2AgAZAAgJmhQeCwCcAQAAAA==.Hurbiehusker:BAAALgAECgEJAQAAAA==.Huriso:BAAALgADCgYJCAAAAA==.Hushpupi:BAAALgADCgUJCAABLgAECgYJFwACAG0VAA==.',
Hy='Hydrafoil:BAAALgAECgQJBgAAAA==.',
Ia='Ianthel:BAAALgAECgUJCwAAAA==.',
Ic='Icesloth:BAABLgAECn8WAAITAAgJgQ8YKQBRAQATAAgJgQ8YKQBRAQAAAA==.',
Id='Idamae:BAAALgAECgcJEQAAAA==.Iduun:BAAALgAECgUJDQAAAA==.',
Il='Iladelle:BAABLgAECn8mAAIDAAkJ+hCqMwCuAQADAAkJ+hCqMwCuAQAAAA==.Illidabina:BAAALgAECgMJCAABLgAECggJKwAgAPkhAA==.',
In='Inariokami:BAAALgAECggJEgAAAA==.Incoherent:BAAALgAECgYJDAAAAA==.',
Io='Iorak:BAAALgADCgQJBAAAAA==.',
Is='Istollan:BAAALgAECgIJAgAAAA==.',
It='Itsmooncake:BAAALgAECgcJBgAAAA==.',
Ix='Ixiya:BAAALgADCgMJBgAAAA==.',
Ja='Jaaygee:BAAALgAECgYJCwABLgAECgYJIgAPAB8kAA==.Jackofblades:BAAALgAECgIJAgAAAA==.Jafud:BAABLgAECn81AAMVAAgJQSD+BACLAgAVAAgJWxn+BACLAgAPAAgJQSBJFAB1AgAAAA==.Jamarcus:BAAALgADCgEJAgAAAA==.Jaste:BAABLgAECn8UAAIbAAYJJg7HRAAmAQAbAAYJJg7HRAAmAQAAAA==.',
Je='Jelliebean:BAAALgADCgYJBgAAAA==.Jessalba:BAAALgAECgMJBAAAAA==.Jestorian:BAAALgAECgUJCQAAAA==.',
Ji='Jirakaidae:BAAALgAECgUJDgAAAA==.',
Jo='Jockinonmytw:BAACLgAFFH8IAAIIAAQJqSFeBwCKAQAIAAQJqSFeBwCKAQAuAAQKfzgAAggACQkPJTcBAD0DAAgACQkPJTcBAD0DAAAA.Joemomi:BAAALgAECgYJDAAAAA==.',
Jr='Jrsy:BAAALgAECgEJAQAAAA==.',
Ju='Judé:BAAALgAECgYJCwAAAA==.Juicyfists:BAAALgADCgcJCgAAAA==.Justice:BAAALgADCgEJAQAAAA==.Justred:BAABLgAECn8VAAMGAAYJeRQDMwAxAQAGAAYJeRQDMwAxAQAhAAMJaA/+MQCeAAAAAA==.',
Jx='Jxson:BAABLgAECn8gAAUiAAYJxRRkVwBMAQAiAAYJxRRkVwBMAQAjAAUJfxj1FwAXAQARAAYJCBLLLwAHAQAkAAMJfhI+IwC8AAABLgAECgYJIgAPAB8kAA==.',
['Jí']='Jínx:BAAALgADCgUJBwAAAA==.',
Ka='Kantuo:BAAALgAECgYJDAAAAA==.',
Ke='Keanx:BAAALgAECgEJAQAAAA==.Kehila:BAAALgADCgEJAQAAAA==.',
Kh='Khelad:BAACLgAFFH8SAAIFAAQJ+A/4JQA4AQAFAAQJ+A/4JQA4AQAuAAQKfxUAAgUACAkUGZhVAOEBAAUACAkUGZhVAOEBAAAA.Khârmá:BAAALgAECgQJBgAAAA==.Khârmâ:BAAALgAECgQJBQAAAA==.',
Ki='Kibear:BAAALgADCgUJBQAAAA==.Killt:BAABLgAECn8gAAISAAkJxRQvIgASAgASAAkJxRQvIgASAgAAAA==.',
Ko='Koltovincent:BAAALgAECgQJBQAAAA==.Koojoé:BAABLgAECn8UAAIlAAcJXQ8eHAAGAQAlAAcJXQ8eHAAGAQAAAA==.',
Ky='Kynthe:BAAALgAECggJDgAAAA==.Kyongye:BAAALgAECggJDAAAAA==.',
La='Laftel:BAAALgADCgQJBgAAAA==.Laghles:BAACLgAFFH8SAAMMAAQJ5x2LDwBsAQAMAAQJ5x2LDwBsAQAcAAIJ7AhvIACTAAAuAAQKf0EAAwwACQkxJJICAEADAAwACQkxJJICAEADABwACAkEG54aAFUCAAAA.',
Le='Leadgut:BAAALgADCgQJBwAAAA==.Lemanjá:BAABLgAECn8hAAIcAAgJmwuFDgD8AAAcAAgJmwuFDgD8AAAAAA==.Lexis:BAAALgADCgkJFQAAAA==.',
Li='Liliane:BAABLgAECn8XAAMKAAkJVAlLHgDNAAAKAAcJZgpLHgDNAAAFAAQJ9Qb8xQCwAAAAAA==.Limbless:BAAALgAECgYJDAAAAA==.',
Lo='Lobot:BAAALgAECgIJAgAAAA==.Lockstar:BAAALgADCgUJCwABLgAECgUJBgAEAAAAAA==.Lohkhan:BAAALgADCggJCwAAAA==.Lontra:BAABLgAECn8UAAIRAAYJPQnuOgDOAAARAAYJPQnuOgDOAAAAAA==.Loozer:BAABLgAECn8ZAAMFAAgJvRZ7SQCjAQAFAAgJvRZ7SQCjAQAKAAMJbAs2OgBWAAAAAA==.',
Lu='Lumil:BAAALgADCgUJBQAAAA==.Luthais:BAAALgAECgYJEQAAAA==.Luzifer:BAAALgADCgEJAQAAAA==.',
Ly='Lymp:BAABLgAECn8eAAMBAAgJuBirMgDvAQABAAgJuBirMgDvAQAXAAEJywjmGAAsAAAAAA==.',
Ma='Magelyman:BAABLgAECn8XAAICAAkJShjAHwBlAgACAAkJShjAHwBlAgAAAA==.Magetiger:BAABLgAECn8UAAICAAgJ+hGdVwCWAQACAAgJ+hGdVwCWAQAAAA==.Malitheion:BAAALgAECgQJCwAAAA==.Malzen:BAABLgAECn8UAAMQAAgJARdvGQCeAQAQAAgJARdvGQCeAQAgAAEJ9AsHdgAuAAAAAA==.Manaleia:BAAALgADCgcJBwAAAA==.Manasolid:BAABLgAECn8sAAICAAgJORWwQADaAQACAAgJORWwQADaAQAAAA==.Mangeømbre:BAAALgAECgQJBAAAAA==.Maruug:BAAALgADCggJDwAAAA==.Marvinah:BAAALgAECgIJAgAAAA==.Masculinedh:BAAALgAECgIJAwABLgAECgYJEAAEAAAAAA==.',
Me='Meches:BAAALgAECgQJCAABLgAECgYJKgAiAK8WAA==.Mediocre:BAAALgAECgEJAQAAAA==.Mediocritty:BAAALgAECgYJCgAAAA==.Medunda:BAAALgAECgMJAwAAAA==.Meeshka:BAABLgAECn8bAAICAAcJRQfUlgATAQACAAcJRQfUlgATAQAAAA==.Melisandre:BAAALgADCgYJBwAAAA==.Meraleona:BAAALgAECgUJBQABLgAECgkJLAABACwdAA==.Methslinger:BAAALgAECggJCwAAAA==.',
Mi='Micaela:BAAALgADCgcJBwAAAA==.Milkwithpulp:BAABLgAECn8dAAIbAAgJ/RUfFQDiAQAbAAgJ/RUfFQDiAQAAAA==.',
Mk='Mkoons:BAAALgAECgEJAgAAAA==.',
Mo='Mook:BAAALgADCgkJCQAAAA==.Mordred:BAAALgAECgcJCQAAAA==.Moris:BAAALgAECgYJEAAAAA==.Mortmuzi:BAAALgADCgYJBgAAAA==.Mosrael:BAAALgAECgkJBgAAAA==.Mothèr:BAAALgADCgEJAwAAAA==.',
Mu='Mulas:BAABLgAECn8eAAIPAAcJmBdePQCpAQAPAAcJmBdePQCpAQAAAA==.Muldah:BAACLgAFFH8SAAICAAQJjRA6PABBAQACAAQJjRA6PABBAQAuAAQKfzAAAgIACQlXIHgRAL4CAAIACQlXIHgRAL4CAAAA.',
My='Mynte:BAABLgAECn8eAAIbAAYJnBLbJwBAAQAbAAYJnBLbJwBAAQAAAA==.',
Na='Natty:BAAALgADCgkJIAAAAA==.Navie:BAABLgAECn8aAAIYAAkJ4AlCGQCwAQAYAAkJ4AlCGQCwAQAAAA==.Nawperwoman:BAABLgAECn8oAAMgAAgJvhuaEQDpAQAgAAgJvhuaEQDpAQAWAAEJrgGhdgAYAAAAAA==.Nazevroth:BAAALgAECgQJBAAAAA==.',
Ne='Necronomicob:BAABLgAECn8dAAIPAAgJkRezMwDMAQAPAAgJkRezMwDMAQAAAA==.Neil:BAAALgADCgUJBQAAAA==.Nekros:BAABLgAECn8tAAQPAAgJ0yDTFgBkAgAPAAcJCyDTFgBkAgAVAAQJaBxUJQAyAQANAAIJqB2vFQCmAAAAAA==.Neø:BAABLgAECn8gAAMBAAgJiBVyRQCtAQABAAgJiBVyRQCtAQAXAAMJoAoIHABdAAAAAA==.',
Ni='Nianna:BAAALgADCgMJAwAAAA==.Nicebud:BAAALgAECgMJAwAAAA==.Nightsfury:BAAALgAECgYJCgAAAA==.Nisa:BAAALgAECgYJBwAAAA==.',
Nm='Nmls:BAAALgADCgQJBAAAAA==.',
No='Nocrackhere:BAAALgADCgYJBgAAAA==.Nokastakaj:BAAALgAECgUJCgAAAA==.Nornyr:BAABLgAECn8gAAIWAAgJARefFgD0AQAWAAgJARefFgD0AQAAAA==.Noxiss:BAAALgADCgQJBAABLgAECgkJLAABACwdAA==.',
Ny='Nymerias:BAAALgAECgYJDwAAAA==.',
Ok='Oku:BAAALgAECgYJEAAAAA==.',
Om='Omaticaya:BAABLgAECn8sAAIRAAgJQQuhJwA4AQARAAgJQQuhJwA4AQAAAA==.',
On='Oni:BAAALgADCgcJFAAAAA==.',
Or='Oriax:BAABLgAECn8WAAIPAAcJaBAzXwBGAQAPAAcJaBAzXwBGAQAAAA==.Ornakaye:BAAALgADCgcJCwAAAA==.',
Os='Oshot:BAAALgAECgMJAwAAAA==.',
Pa='Paean:BAAALgAECgUJCQAAAA==.Pajamas:BAAALgAECgEJAQAAAA==.Pandycake:BAAALgADCgcJDAAAAA==.Pandzzy:BAAALgAECgUJBQAAAA==.Papilaflame:BAABLgAECn8kAAMiAAgJgAbafwDbAAAiAAcJVATafwDbAAARAAQJ+gKXWwBRAAAAAA==.',
Pc='Pc:BAAALgAECgEJAQAAAA==.',
Pe='Peak:BAAALgADCgEJAQABLgAECgEJBgAEAAAAAA==.Peata:BAAALgAECgEJAQAAAA==.Persephones:BAABLgAECn8fAAIaAAcJ4g/eJwCaAQAaAAcJ4g/eJwCaAQAAAA==.',
Ph='Phenelope:BAAALgAECgcJCgAAAA==.Phillycheez:BAAALgADCgYJBgAAAA==.',
Pi='Piika:BAAALgAECgUJBQABLgAECggJEgAEAAAAAA==.Pillowpuhmpa:BAAALgAECgIJBAAAAA==.Pinga:BAAALgADCgcJCgAAAA==.Pinkstarfish:BAAALgAECgIJAgAAAA==.',
Pk='Pkalygos:BAABLgAECn8eAAIUAAkJmBNdCwDaAQAUAAkJmBNdCwDaAQAAAA==.',
Po='Poosnwoods:BAAALgAECgYJDQAAAA==.Popefuffer:BAAALgAFFAIJAQAAAA==.Powerstrokee:BAABLgAECn8XAAMBAAcJxREZYQBfAQABAAcJuBEZYQBfAQAXAAIJEQ/GGwBfAAAAAA==.',
Pr='Primal:BAAALgADCgIJAgAAAA==.Principle:BAABLgAECn8hAAILAAgJrRzoEQCDAgALAAgJrRzoEQCDAgAAAA==.Protadin:BAABLgAECn8YAAIKAAYJwBQUFwBjAQAKAAYJwBQUFwBjAQAAAA==.Práystation:BAAALgADCgEJAQAAAA==.',
Ps='Psychelone:BAABLgAECn8XAAMLAAcJbgqSOwAJAQALAAYJAAySOwAJAQAFAAIJBQi9HgE+AAAAAA==.',
Pu='Punchygood:BAAALgAECgEJAQAAAA==.Purification:BAAALgADCgQJBAAAAA==.',
['Pô']='Pôps:BAAALgAECgYJEwAAAA==.',
Qu='Quickprick:BAAALgAECgcJDgAAAA==.',
Ra='Radrela:BAAALgADCgYJBgAAAA==.Rakhaith:BAAALgAECgQJBAAAAA==.Rasina:BAAALgAECgIJBAAAAA==.Ratkìng:BAAALgAECgMJBAAAAA==.Raynt:BAAALgAECgMJAwAAAA==.Raziêl:BAAALgAECgIJBAAAAA==.',
Re='Reaperix:BAAALgADCgYJBgAAAA==.Reknojir:BAAALgAECgIJAgAAAA==.Reneeww:BAAALgAECgYJDAAAAA==.Rexhavoc:BAACLgAFFH8SAAIDAAQJlxRCIwA9AQADAAQJlxRCIwA9AQAuAAQKfzYAAwMACQluIIwHAOUCAAMACQluIIwHAOUCAB4ABgkAEcs6ABUBAAAA.Rexion:BAAALgAECgQJCgAAAA==.',
Ri='Rigor:BAAALgAECgUJCQAAAA==.Ringing:BAAALgAECgYJCQAAAA==.Ripre:BAAALgADCgQJCAAAAA==.Rizar:BAAALgAECgUJBQAAAA==.',
Ro='Roamina:BAAALgAECgEJAQABLgAECgYJDAAEAAAAAA==.Rockbottom:BAAALgAECgEJAQAAAA==.Ronxjubio:BAAALgADCgQJBAAAAA==.Rosary:BAABLgAECn8kAAIjAAgJTAJLKwCAAAAjAAgJTAJLKwCAAAAAAA==.Rosewoodren:BAAALgADCgkJDQAAAA==.',
Ru='Runeclad:BAABLgAECn8cAAIBAAkJnRV7KgARAgABAAkJnRV7KgARAgAAAA==.',
Ry='Rysandra:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámi:BAAALgADCgEJAgAAAA==.',
Sa='Saauurrora:BAAALgADCggJCAAAAA==.Sabiton:BAAALgADCgYJCgAAAA==.Saintshift:BAAALgADCgYJDAABLgAECgYJEAAEAAAAAA==.Salitheion:BAAALgAECggJDQAAAA==.Saloraith:BAAALgAECgcJDQAAAA==.Salpper:BAAALgADCgYJBgAAAA==.Sanatura:BAAALgAECgYJCwAAAA==.Sapper:BAABLgAECn8rAAIWAAkJOCDOBQD1AgAWAAkJOCDOBQD1AgAAAA==.Sarabia:BAAALgADCgUJBQAAAA==.Sarasvatia:BAAALgAECgQJCAAAAA==.Sarn:BAABLgAECn8bAAIjAAkJpxI3DwCIAQAjAAkJpxI3DwCIAQAAAA==.Sathi:BAAALgAECgIJAgAAAA==.Saudhum:BAABLgAECn8WAAMNAAYJwRsfCADLAQANAAYJwRsfCADLAQAPAAQJ4Q2dsACgAAAAAA==.Sayuri:BAABLgAECn8aAAIWAAgJ+h+7BwDGAgAWAAgJ+h+7BwDGAgAAAA==.',
Sb='Sboop:BAAALgAECgQJBwAAAA==.',
Se='Sengoku:BAAALgADCgEJAQAAAA==.Sennest:BAAALgADCgMJAwAAAA==.Seppuku:BAAALgAECgMJBQAAAA==.Sev:BAAALgAECgQJBgAAAA==.',
Sh='Shadowmoocow:BAAALgADCgkJCQAAAA==.Shakti:BAAALgAECgcJBgAAAA==.Shalltear:BAAALgADCgIJAgAAAA==.Shampoo:BAABLgAECn8rAAISAAkJMgRrRgAyAQASAAkJMgRrRgAyAQAAAA==.Shikí:BAAALgADCggJGAAAAA==.Shivs:BAAALgADCgcJBwAAAA==.Shladoran:BAABLgAECn8lAAIhAAcJHxXCFQBWAQAhAAcJHxXCFQBWAQAAAA==.Shmistan:BAAALgADCgYJBgAAAA==.Shockles:BAAALgAECgcJDwAAAA==.Shos:BAACLgAFFH8FAAIlAAIJGAhcGQBxAAAlAAIJGAhcGQBxAAAuAAQKfx4AAiUACAljETgUAF4BACUACAljETgUAF4BAAAA.Shotsshots:BAABLgAECn8tAAQMAAkJGx9/EACGAgAMAAkJGx9/EACGAgAmAAIJGgz1OwB5AAAcAAEJAAC1kQApAAAAAA==.Shuttsylock:BAAALgAECgUJCgAAAA==.',
Si='Siberianwolf:BAAALgAECgEJAQAAAA==.Sicaria:BAAALgAECgUJEwAAAA==.Sindina:BAAALgADCgYJBgAAAA==.Sinnisterx:BAAALgADCgQJBAAAAA==.',
Sk='Skally:BAAALgAECgYJDgAAAA==.Skully:BAACLgAFFH8SAAIQAAQJUSXqBQC2AQAQAAQJUSXqBQC2AQAuAAQKfzMAAhAACQleJQkBAE8DABAACQleJQkBAE8DAAAA.',
Sl='Slicedup:BAAALgAECgMJAwABLgAECgUJBgAEAAAAAA==.Sluffshot:BAABLgAECn8tAAMdAAkJ6CBqBABiAgAdAAkJZyBqBABiAgABAAQJYx07twAUAQAAAA==.',
Sn='Snorina:BAACLgAFFH8HAAIaAAMJ0B0dFAAJAQAaAAMJ0B0dFAAJAQAuAAQKfzcAAhoACQkOJYYBAEgDABoACQkOJYYBAEgDAAAA.',
So='Soggydave:BAAALgADCgIJAgAAAA==.Solina:BAAALgADCgUJBQAAAA==.Solsteece:BAAALgADCgYJDwAAAA==.Solàrflàré:BAAALgADCgIJAgAAAA==.Sorrows:BAAALgAECgIJBgAAAA==.Sosgoraan:BAABLgAECn8bAAMQAAgJ8RdZFgC7AQAQAAgJ8RdZFgC7AQAgAAEJWglLewArAAAAAA==.Sosozen:BAABLgAECn8WAAIgAAgJgQtdKwATAQAgAAgJgQtdKwATAQAAAA==.Soul:BAAALgAECgYJDQAAAA==.Soulzi:BAAALgADCgYJCAABLgAECgYJDQAEAAAAAA==.',
Sp='Sparepärts:BAAALgADCgMJAwAAAA==.Sparkgrace:BAAALgADCgEJAQAAAA==.Spirittoast:BAAALgAECgUJCQAAAA==.Splunk:BAAALgADCggJDAAAAA==.Sprakgul:BAABLgAECn8YAAICAAgJUw0VZwBwAQACAAgJUw0VZwBwAQAAAA==.',
Sq='Squelch:BAAALgAECgMJBAAAAA==.',
St='Starpe:BAAALgAECgYJDQAAAA==.Steezy:BAAALgADCgcJBwAAAA==.Stinkykoala:BAAALgADCggJCAAAAA==.Stratovarius:BAAALgAECgUJBQAAAA==.Strumpet:BAAALgAECgQJBQAAAA==.',
Sw='Sweepthelego:BAAALgADCgEJAQAAAA==.Sweetspot:BAAALgAECgQJBwABLgAECggJGQAFAL0WAA==.Swytch:BAABLgAECn8pAAIHAAkJ8Rd+AwAwAgAHAAkJ8Rd+AwAwAgAAAA==.',
Sy='Sylrytherin:BAABLgAECn8UAAIRAAcJkBokHQAXAgARAAcJkBokHQAXAgABLgAFFAMJBwAaANAdAA==.Sylvii:BAABLgAECn8qAAMiAAYJrxbKNQB8AQAiAAYJrxbKNQB8AQARAAYJhAzwNQDmAAAAAA==.',
Ta='Tabor:BAAALgAECgUJDwAAAA==.Tammyfaye:BAAALgADCgEJAQABLgAECgYJGAAdAHURAA==.Tankdozer:BAAALgADCgcJCgAAAA==.Tarahly:BAABLgAECn8ZAAILAAgJYBVaGAD5AQALAAgJYBVaGAD5AQAAAA==.Tauryel:BAAALgAECgYJDAABLgAECgYJDAAEAAAAAA==.',
Te='Tebook:BAABLgAECn8sAAMBAAkJLB3GLgD/AQABAAkJLB3GLgD/AQAXAAEJvwYfJAAsAAAAAA==.Telath:BAACLgAFFH8GAAIDAAMJggvCRADPAAADAAMJggvCRADPAAAuAAQKfyMAAgMACQk7Gf48AAACAAMACQk7Gf48AAACAAAA.Tevinter:BAAALgAECgIJAgAAAA==.',
Th='Themoosifer:BAACLgAFFH8VAAIDAAYJ7RrMDwCjAQADAAYJ7RrMDwCjAQAuAAQKfyEAAgMACAkAIF4aALYCAAMACAkAIF4aALYCAAAA.Thistlechi:BAABLgAECn8jAAIgAAgJIxkzEAB9AgAgAAgJIxkzEAB9AgAAAA==.Thyck:BAABLgAECn8hAAIMAAgJzBiVLADbAQAMAAgJzBiVLADbAQAAAA==.Thydis:BAAALgAECggJEgAAAA==.',
Ti='Tibbs:BAABLgAECn8cAAInAAkJEQ4jIACIAQAnAAkJEQ4jIACIAQAAAA==.Timber:BAAALgAECgMJBgAAAA==.Timthahunter:BAAALgADCgUJCQAAAA==.',
To='Tonar:BAAALgAECgQJCAAAAA==.Torluis:BAAALgAECgYJDAAAAA==.',
Tr='Treeheals:BAAALgADCgUJBQAAAA==.Treeleaf:BAABLgAECn8XAAIkAAcJdBRlEABMAQAkAAcJdBRlEABMAQAAAA==.',
Tu='Tullamore:BAAALgAECgIJAgAAAA==.Turgle:BAAALgAECgMJAgAAAA==.',
Tw='Twôtrucks:BAAALgADCgYJBwAAAA==.',
Ty='Tyinthiostus:BAABLgAECn8VAAQWAAcJrBHqLQBJAQAWAAYJHxHqLQBJAQAgAAUJjw1TTwDVAAAQAAEJWgD1mAAbAAAAAA==.Tylerblevins:BAAALgADCgMJAwAAAA==.Typeshyt:BAAALgADCgEJAQAAAA==.',
Uk='Ukkied:BAAALgAECgIJAgABLgAFFAYJEQAiAOoYAA==.',
Un='Uncorrupted:BAABLgAECn8ZAAIKAAgJ4RvgCQDaAQAKAAgJ4RvgCQDaAQAAAA==.Unholymilk:BAAALgAECgEJAQAAAA==.Unrealtotem:BAAALgADCgEJAQAAAA==.',
Up='Updog:BAAALgAECgYJEwAAAA==.',
Va='Vaelis:BAAALgAECgIJAgAAAA==.Valauthiel:BAABLgAECn8ZAAIMAAYJpBb8WAA/AQAMAAYJpBb8WAA/AQAAAA==.Vasdepherens:BAABLgAECn8iAAIdAAkJShMJGACbAQAdAAkJShMJGACbAQAAAA==.',
Ve='Velan:BAAALgADCgcJEQAAAA==.Vermouth:BAABLgAECn8fAAMgAAcJcRO5JQA0AQAgAAcJcRO5JQA0AQAWAAYJ6AJcTgCWAAAAAA==.',
Vi='Vindrelis:BAAALgADCggJEAAAAA==.Violêt:BAAALgAECgYJDgAAAA==.',
Vo='Voidchris:BAAALgAECgcJDgAAAA==.Voidlord:BAAALgADCgcJBwAAAA==.Voidormu:BAAALgADCgEJAQAAAA==.Volkanegos:BAABLgAECn8VAAMGAAYJ0wI/WQCRAAAGAAYJ0wI/WQCRAAAhAAEJuwCOSwAGAAAAAA==.Voren:BAAALgAECgYJDAAAAA==.Vortex:BAAALgADCgIJAgAAAA==.',
Vy='Vyk:BAAALgAECgYJBwAAAA==.',
Wa='Warelf:BAAALgADCgYJCQAAAA==.',
Wh='Whambulance:BAAALgAECgMJAwAAAA==.Whipcracker:BAAALgAECgYJBgAAAA==.Whodouthink:BAAALgADCgEJAQAAAA==.',
Wi='Wildcherry:BAAALgADCgQJBwAAAA==.Wishmaster:BAAALgADCgEJAQAAAA==.Wizermagus:BAAALgADCgkJFwABLgAFFAQJCAAGAE8dAA==.Wizerwar:BAACLgAFFH8IAAIGAAQJTx3cCQBpAQAGAAQJTx3cCQBpAQAuAAQKf0QAAgYACQnRJFYBAEkDAAYACQnRJFYBAEkDAAAA.',
Wo='Woggo:BAAALgADCgQJBQAAAA==.Wolina:BAAALgADCgMJAwAAAA==.Wovvo:BAAALgADCgYJBgAAAA==.',
Wy='Wylia:BAABLgAECn8WAAICAAgJFhZTRQDLAQACAAgJFhZTRQDLAQAAAA==.',
Xa='Xander:BAAALgADCgYJBgAAAA==.',
Xc='Xcw:BAAALgAECgYJBgAAAA==.',
Ya='Yadiyada:BAAALgADCgcJBwAAAA==.',
Yl='Ylzera:BAAALgAECgEJAgABLgAECgQJBgAEAAAAAA==.',
Yo='Yoruchi:BAABLgAECn8VAAIeAAYJywiPKADSAAAeAAYJywiPKADSAAAAAA==.Yoshì:BAAALgAECgUJBQAAAA==.Yoshí:BAAALgAECgYJBwAAAA==.',
Za='Zaddyboom:BAAALgAECgQJBAABLgAECggJGwACAOgXAA==.Zakuren:BAABLgAECn8xAAIMAAkJpA4TMADMAQAMAAkJpA4TMADMAQAAAA==.',
Zo='Zombied:BAAALgAECgEJBgAAAA==.Zort:BAAALgAECgcJAQAAAA==.',
Zs='Zsasz:BAAALgAECgEJAQAAAA==.',
Zu='Zubzero:BAABLgAECn8cAAICAAYJLRCNjgAiAQACAAYJLRCNjgAiAQAAAA==.',
['Ån']='Ånubis:BAAALgADCgcJDgAAAA==.',
['Æn']='Æntítÿ:BAAALgAECgIJAgAAAA==.',
['Ñî']='Ñîx:BAABLgAECn8jAAQnAAgJRxJvJQBhAQAnAAcJaRRvJQBhAQAUAAUJSwTnMwDOAAAoAAQJNAs3KwDDAAAAAA==.',
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
