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

local lookup = {'DeathKnight-Blood','Druid-Restoration','Warrior-Arms','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Affliction','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Paladin-Protection','Priest-Holy','Mage-Frost','Monk-Brewmaster','Monk-Windwalker','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Balance','Paladin-Holy','Warlock-Demonology','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Shadow','Unknown-Unknown','Evoker-Augmentation','Evoker-Preservation','Rogue-Outlaw','Warrior-Protection','Monk-Mistweaver','Rogue-Assassination','Warrior-Fury','DemonHunter-Devourer',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=53,date='2026-11-10',data={Ai='Aitnd:BAAANQAECgMIAwAAAA==.Aitns:BAAANQADCgUIBgAAAA==.',
Al='Alaszun:BAAANQADCggICQAAAA==.Alorothius:BAAANQAECgYIDgABNQAECgoKKAABAAIIAA==.Alpacalypse:BAAANQADCggICAAAAA==.Altha:BAABNQAECn9BAAICAAoKiBTRFwA9AgACAAoKiBTRFwA9AgAAAA==.',
Am='Amilde:BAAANQADCggICQABNQAECgoKKwADACIbAA==.',
An='Anarisa:BAABNQAECn9EAAIEAAoKDxjnQAA9AgAEAAoKDxjnQAA9AgAAAA==.',
Ap='Appocolypto:BAAANQAECgUIBQAAAA==.',
Ar='Areese:BAAANQADCgUIAgAAAA==.Arës:BAAANQAECgEIAQAAAA==.',
At='Atra:BAAANQAECgUIBQAAAA==.',
Av='Averse:BAACNQAFFH8HAAIFAAUKFAurDAB5AAAFAAUKFAurDAB5AAA1AAQKf0gAAwUACgpRJF4JAHQDAAUACgpRJF4JAHQDAAYAAgpxINOcAE8AAAAA.',
Ba='Balnor:BAABNQAECn8jAAIDAAkKhgkgwQB6AQADAAkKhgkgwQB6AQAAAA==.',
Bi='Bigbeef:BAAANQADCgEIAQAAAA==.',
Bo='Borgus:BAAANQAECgUJEgAAAA==.',
Br='Brimstone:BAAANQADCggIEAAAAA==.Brokemav:BAACNQAFFH8FAAIHAAQKIwuDAQA6AQAHAAQKIwuDAQA6AQA1AAQKfzUAAgcACgpNHrQBADIDAAcACgpNHrQBADIDAAAA.Brooklin:BAABNQAECn87AAIEAAoKyBcegQB8AgAEAAoKyBcegQB8AgAAAA==.',
Bu='Busky:BAABNQAECn8bAAQIAAkKMBNMGQDRAQAIAAgKXxFMGQDRAQAJAAUKYAu8ywD7AAAKAAMKCxGgAwFhAAAAAA==.',
Ca='Cao:BAABNQAECn8vAAMLAAoKqBZzVgAaAgALAAoKqBZzVgAaAgAMAAEKAABSgAAcAAAAAA==.Cassiopea:BAABNQAECn8zAAINAAoKohtEOACHAgANAAoKohtEOACHAgAAAA==.',
Ce='Cellcept:BAAANQAECgEIAQAAAA==.',
Ch='Chinchillada:BAABNQAECn8dAAIOAAcKOhUSEACmAQAOAAcKOhUSEACmAQAAAA==.Chows:BAAANQADCgYIBgABNQAECgoKKwADACIbAA==.',
Cl='Clafoutis:BAAANQAECggIDgAAAA==.Clanker:BAACNQAFFH8WAAIPAAcKiRdDAwCVAQAPAAcKiRdDAwCVAQA1AAQKfzsAAw8ACgoVIz0CAO8CAA8ACgoVIz0CAO8CABAAAQrAE4JUAEAAAAAA.',
['Cà']='Càss:BAAANQABCgEIAQABNQAECgoKMwANAKIbAA==.',
Da='Dabajabaza:BAABNQAECn8oAAIBAAoKAgi8YwBjAQABAAoKAgi8YwBjAQAAAA==.Dabergerak:BAACNQAFFH8IAAIDAAMKjRvzIQDtAAADAAMKjRvzIQDtAAA1AAQKfxoAAgMACQpUG/ZSAJECAAMACQpUG/ZSAJECAAAA.Dakrus:BAABNQAECn8jAAMRAAoKMRdvEAAoAgARAAkKMRdvEAAoAgASAAEKAABUPwFkAAAAAA==.',
De='Deathntaxes:BAABNQAECn8mAAMBAAoKBh9ECwDWAgABAAoK7B5ECwDWAgAFAAkKvBdcUgDJAQAAAA==.Dejanira:BAABNQAECn8vAAMCAAoK1RDLJACvAQACAAoK1RDLJACvAQATAAEK6AejuAAoAAAAAA==.Deyedrel:BAABNQAECn8oAAMUAAkK6B4RJACSAgAUAAkK6B4RJACSAgALAAYKFAzP+gDcAAAAAA==.',
Di='Diddily:BAAANQAECgYICwAAAA==.',
Dr='Dridarok:BAAANQAECggIEAAAAA==.Drixfu:BAAANQADCgcIBwAAAA==.',
['Dé']='Déathkeng:BAAANQAECggICAAAAA==.',
El='Elise:BAAANQADCgUIBQABNQAECggIJwASAAkaAA==.Elstrid:BAABNQAECn8jAAIVAAcKIhQ5pgCIAQAVAAcKIhQ5pgCIAQAAAA==.Elyange:BAAANQAECgQIBAAAAA==.',
Er='Eremisa:BAAANQADCggIDgABNQAECgoKRAAEAA8YAA==.Erros:BAAANQADCgQIBwAAAA==.',
Ev='Eve:BAACNQAFFH8VAAIWAAcKgw+MAQB6AQAWAAcKgw+MAQB6AQA1AAQKfygAAhYACgpjHnAGALMCABYACgpjHnAGALMCAAAA.Evochre:BAAANQADCgcIDQAAAA==.',
Fa='Fantasy:BAABNQAECn81AAIJAAoK/CWSBwA5AwAJAAoK/CWSBwA5AwAAAA==.',
Fe='Felbourn:BAABNQAECn86AAIXAAoKzx52EQCNAgAXAAoKzx52EQCNAgAAAA==.Fendraim:BAAANQADCgMIBgAAAA==.',
Fi='Figurefour:BAAANQAECgIIAgAAAA==.',
Fl='Flaccidmass:BAAANQAECggIEwAAAA==.',
Fo='Foedris:BAAANQAECgIIAgAAAA==.Foxfire:BAAANQABCgQIBgAAAA==.',
Fr='Frailboosy:BAACNQAFFH8OAAILAAYKTRWPDAASAQALAAYKTRWPDAASAQA1AAQKfzIAAgsACgp0IENJALkCAAsACgp0IENJALkCAAAA.',
Fu='Fuzzidan:BAAANQAECgIIAgAAAA==.',
Ga='Gaara:BAABNQAECn8nAAIJAAoKwhrrHQBxAgAJAAoKwhrrHQBxAgAAAA==.',
Ge='Gemini:BAABNQAECn8WAAILAAgKlBUNiwAQAgALAAgKlBUNiwAQAgAAAA==.',
Gl='Glitz:BAAANQAECgUIDAABNQAFFAcIFQAWAIMPAA==.',
Gr='Graamps:BAAANQAECgQIBgAAAA==.Gravedigger:BAABNQAECn9HAAIBAAoKqSAGFgD9AgABAAoKqSAGFgD9AgAAAA==.',
['Gü']='Güts:BAABNQAECn8yAAIDAAkKKhaZbwBEAgADAAkKKhaZbwBEAgAAAA==.',
Ho='Holywagyu:BAAANQADCgcIBwAAAA==.Howlimer:BAAANQADCgEIAQAAAA==.',
Hu='Huf:BAAANQAECgUIBgABNQAFFAcIFgAYAMANAA==.Husshh:BAAANQABCgMIAwAAAA==.',
Il='Illidanzs:BAAANQADCgcIBwABNQAECgQIBQAZAAAAAA==.',
Ir='Ironnmonk:BAAANQADCgYIBQABNQAECgUIBQAZAAAAAA==.',
Ja='Jarlaxxle:BAAANQAECgEIAQAAAA==.Java:BAAANQADCgQIBgABNQAECgkJGwAIADATAA==.Jawshoeuh:BAAANQAECgEIAQAAAA==.',
Ju='Jujujab:BAAANQAECgQIDQAAAA==.Jujukni:BAAANQAECgQIBAABNQAECgQIDQAZAAAAAA==.Jujumon:BAAANQADCgYIBgABNQAECgQIDQAZAAAAAA==.Jujuzor:BAAANQAECgUIDgAAAA==.Jujuzul:BAAANQAECgQICQABNQAECgQIDQAZAAAAAA==.Justimp:BAABNQAECn8uAAIVAAoKaxhSNAC4AgAVAAoKaxhSNAC4AgAAAA==.',
Ka='Karlek:BAACNQAFFH8FAAIMAAIKzAURDABdAAAMAAIKzAURDABdAAA1AAQKfy4ABAsACgqtEOeoAM4BAAsACArxEeeoAM4BAAwABAqVCyM6ALIAABQAAQrpC30eATgAAAAA.Kassamella:BAAANQADCggICAABNQAECgcIHQAOADoVAA==.Kassanndra:BAEANQAECggICAABNQAFFAMIBgALACUKAA==.Kazeshiní:BAAANQADCgQIBAAAAA==.',
La='Lalana:BAAANQAECgYIEQAAAA==.Lan:BAAANQAECgUIDgAAAA==.',
Li='Lilshorty:BAAANQAECgEIAQABNQAECgQIBQAZAAAAAA==.',
Lo='Lofwyr:BAACNQAFFH8IAAMaAAMK3gGVCgCFAAAaAAMK3gGVCgCFAAAbAAEK9AGEGAAsAAA1AAQKfy8AAxsACgqGC+omAIIBABsACQq5CeomAIIBABoACQqZC8ALACkBAAAA.',
Lu='Lumaie:BAABNQAECn8zAAMCAAoKfyG3CAA5AwACAAoKfyG3CAA5AwATAAEKAABpmgAAAAAAAA==.Lumie:BAAANQAECgUIBQABNQAECgoKMwACAH8hAA==.Lumistress:BAECNQAFFH8GAAILAAMKJQrzGAC5AAALAAMKJQrzGAC5AAA1AAQKfy0AAgsACgqjGWVpAGACAAsACgqjGWVpAGACAAAA.',
Ly='Lynni:BAAANQADCgUIBQAAAA==.',
Ma='Maelstrom:BAAANQADCgYIBgAAAA==.Malcharion:BAAANQAECgQIBAAAAA==.Mamarue:BAAANQADCgYIBgAAAA==.',
Mc='Mcshâms:BAABNQAECn8vAAQJAAoKSBuWMwCrAgAJAAkKbRuWMwCrAgAIAAoKOxTxDQAhAgAKAAQKwRaIiAAGAQAAAA==.',
Me='Medril:BAAANQAECgEIAQAAAA==.',
Mu='Munir:BAAANQADCggIIQAAAA==.',
Na='Naeltian:BAABNQAECn8yAAIcAAoK/xvYAgAdAwAcAAoK/xvYAgAdAwAAAA==.',
Ne='Necromachine:BAACNQAFFH8IAAIFAAQKYh9bBQADAQAFAAQKYh9bBQADAQA1AAQKf0wAAgUACgoHJIcGAAYDAAUACgoHJIcGAAYDAAAA.Neon:BAAANQAECgUIBgABNQAECgoKNQAJAPwlAA==.Nevermore:BAABNQAECn8xAAIXAAoKoxzjFgDlAgAXAAoKoxzjFgDlAgAAAA==.',
No='Noctislucis:BAAANQABCgIIAgAAAA==.Noobdk:BAACNQAFFH8QAAIBAAcKHhvyDACEAQABAAcKHhvyDACEAQA1AAQKfxYAAgEABwqlI+wTAGQCAAEABwqlI+wTAGQCAAAA.Noobmonkey:BAAANQADCgYIBgABNQAFFAcIEAABAB4bAA==.Noobwarr:BAABNQAECn8kAAMdAAkK8iT3AgB6AwAdAAkK8iT3AgB6AwADAAgKEBczmADgAQABNQAFFAcIEAABAB4bAA==.Novax:BAAANQAECgUIBwAAAA==.',
Ny='Nyquil:BAEANQAECggICAABNQAFFAMIBgALACUKAA==.',
Ol='Oldreligion:BAAANQADCggICAAAAA==.',
Pe='Perugius:BAAANQADCgYICgABNQAECgcIIwAVACIUAA==.',
Ph='Phrenulhum:BAAANQADCgcIBwAAAA==.',
Pr='Predmost:BAAANQABCgQIBAAAAA==.Prettypoison:BAABNQAECn87AAISAAoKyhTnPwBDAgASAAoKyhTnPwBDAgAAAA==.',
Pu='Pussehfart:BAAANQADCggJDAAAAA==.Putz:BAABNQAECn9BAAIWAAoKERt7BgCxAgAWAAoKERt7BgCxAgAAAA==.Putzadin:BAAANQAECgIIAgAAAA==.',
Pw='Pwincess:BAAANQAECgEIAQAAAA==.',
Ra='Rainbow:BAABNQAECn8mAAIeAAoKVBbxFQAdAgAeAAoKVBbxFQAdAgABNQAECgoKNQAJAPwlAA==.',
Re='Reialaleigh:BAABNQAECn8hAAIfAAgKSgtJQwC8AQAfAAgKSgtJQwC8AQAAAA==.',
Ry='Ryuk:BAAANQADCgMIAwAAAA==.',
Sa='Saberdiva:BAABNQAECn8cAAILAAYKfwyR+QDeAAALAAYKfwyR+QDeAAAAAA==.Sabersidious:BAAANQADCgUIBQAAAA==.Sabpar:BAACNQAFFH8TAAMKAAcKNQhUCwCYAQAKAAYKUQlUCwCYAQAJAAYKSxKTDgCHAQA1AAQKfyQAAwkACgrXH2koAOACAAkACgrXH2koAOACAAoAAQqSHGndAE8AAAAA.Sabs:BAABNQAECn8fAAIFAAkKNyF3CQDUAgAFAAkKNyF3CQDUAgABNQAFFAcIEwAKADUIAA==.Saladin:BAABNQAECn8sAAIDAAoKlBTrggAUAgADAAoKlBTrggAUAgAAAA==.Sanakht:BAABNQAECn8aAAIfAAkKiRbOIwBqAgAfAAkKiRbOIwBqAgAAAA==.',
Sc='Schweitzer:BAAANQAECgUIBAAAAA==.Scotticus:BAAANQAECgIIAgAAAA==.Scribblezz:BAAANQABCgMIBQAAAA==.',
Se='Seditionist:BAAANQADCgYIGAAAAA==.Serafina:BAAANQAECggIDAABNQAFFAcIFQAWAIMPAA==.',
Sh='Shakira:BAAANQADCgYICwABNQAECggIIQAfAEoLAA==.Sheepd:BAAANQAECgcIDgABNQAFFAcIEAABAB4bAA==.',
Si='Sidewind:BAAANQAECgMIAwAAAA==.Sidthekid:BAAANQADCggIGAAAAA==.Sinayion:BAABNQAECn8YAAIMAAgKJAWbOwCrAAAMAAgKJAWbOwCrAAAAAA==.',
Sm='Smokestackz:BAAANQAECgEIAQAAAA==.',
Sn='Snepaí:BAABNQAECn8rAAIDAAoKIhv0NADuAgADAAoKIhv0NADuAgAAAA==.',
So='Sonamis:BAAANQAECgIIAQAAAA==.',
Sp='Sparkleshout:BAAANQABCgMIAwABNQAFFAcIFQAWAIMPAA==.',
St='Stepdemonh:BAAANQADCgYIBgAAAA==.Stinkoman:BAAANQABCgIIAgABNQABCgQIBgAZAAAAAA==.',
Su='Sunofthewar:BAAANQADCgQIBAAAAA==.',
Ta='Tankobell:BAABNQAECn8bAAILAAgK+QyFugCoAQALAAgK+QyFugCoAQAAAA==.',
Te='Terrible:BAEANQAECgEIAQABNQAFFAYICQAgABAOAA==.',
Th='Thañatos:BAABNQAECn8kAAMWAAkKuRueBgAeAgAWAAkKuRueBgAeAgAhAAYKiwTuOADCAAABNQAECgoKRwABAKkgAA==.',
Tr='Truart:BAABNQAECn8oAAILAAoKpROggwAgAgALAAoKpROggwAgAgAAAA==.',
Tu='Tuerjoie:BAAANQAECgIIAwAAAA==.',
Va='Valesko:BAAANQADCgUIBQAAAA==.Varfus:BAAANQADCgYIDAABNQAECgoKJgABAAYfAA==.',
Ve='Vector:BAAANQADCgQIBAAAAA==.Veinglory:BAABNQAECn8oAAIBAAoKHh06KwBtAgABAAoKHh06KwBtAgAAAA==.Velentre:BAAANQAECgcIDgAAAA==.',
Vi='Vindictress:BAEANQAECggIBQABNQAFFAMIBgALACUKAA==.',
Vo='Vonka:BAAANQADCgYIDwAAAA==.',
Wa='Walnut:BAAANQAECggIEgAAAA==.',
Wi='Wigskid:BAAANQAECgQIBQAAAA==.Winney:BAAANQAECggIDQAAAA==.',
Wo='Wonkz:BAAANQABCgQIBwAAAA==.',
Wr='Wrequiem:BAAANQADCgUIBgAAAA==.',
Xh='Xhiaky:BAAANQADCgQIBAAAAA==.',
Xy='Xyran:BAAANQADCgYICgAAAA==.',
Yo='Yoyomba:BAAANQAECgcICwABNQAECgkJMgADACoWAA==.',
Ze='Zenderal:BAAANQADCgEIAQAAAA==.Zendetra:BAAANQAECgEIAQABNQAECggIFwAfAOsMAA==.Zeposo:BAABNQAECn8hAAINAAkKTBwLGgD2AgANAAkKTBwLGgD2AgABNQAECgoKLQAKAD4eAA==.Zeptide:BAABNQAECn8tAAMKAAoKPh4ARgBJAgAKAAoKPh4ARgBJAgAJAAcKChToZQA9AQAAAA==.',
['Zë']='Zëp:BAABNQAECn8oAAMUAAkK8B+WEQAiAwAUAAkK8B+WEQAiAwALAAEKAAAQnwE4AAABNQAECgoKLQAKAD4eAA==.',
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
