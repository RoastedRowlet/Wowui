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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Rogue-Outlaw','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Paladin-Retribution','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Druid-Guardian','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Mage-Frost','Mage-Arcane','Mage-Fire','Evoker-Preservation','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Evoker-Augmentation','DemonHunter-Devourer','Shaman-Elemental','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Warlock-Affliction','Hunter-Marksmanship','Evoker-Devastation','Druid-Feral','DemonHunter-Vengeance','Warrior-Arms','Paladin-Protection','Warrior-Fury',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAYJEQABAF0iAA==.',
Ab='Abadizzo:BAAALgAECgcJDAAAAA==.Abadizzoo:BAABLgAECn8qAAICAAkJtyE9FQClAgACAAkJtyE9FQClAgAAAA==.Abilities:BAAALgAECgYJEgAAAA==.',
Ac='Ace:BAAALgAFFAEJAQAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAABLgAECn8VAAICAAYJIhU2dwBMAQACAAYJIhU2dwBMAQABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8sAAIEAAkJUiTUBABAAwAEAAkJUiTUBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAECgIJAwAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airleara:BAAALgAECgcJDAAAAA==.Airwrecka:BAACLgAFFH8IAAIBAAMJ3RRQLgDGAAABAAMJ3RRQLgDGAAAuAAQKfzEAAgEACQnEHjQMAJACAAEACQnEHjQMAJACAAAA.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.Aite:BAAALgAECgIJAgAAAA==.',
Al='Alexian:BAABLgAECn8bAAIGAAkJsRVPBQATAgAGAAkJsRVPBQATAgAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAABLgAECn8VAAICAAgJ/BKjTgCyAQACAAgJ/BKjTgCyAQAAAA==.',
Am='Amebeliever:BAABLgAECn8fAAQHAAgJiB8ZFQBDAgAHAAcJuB4ZFQBDAgAIAAcJAgi/NwAMAQAJAAQJ/gmEZQB9AAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgkJFgAAAA==.',
Ar='Arahgon:BAEBLgAECn8eAAIKAAkJ7xrKIACCAgAKAAkJ7xrKIACCAgABLgAECgYJCQAFAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asphodelos:BAAALgAECgYJDQABLgAFFAQJDwADACIfAA==.Asukà:BAABLgAECn85AAMLAAkJ/xYzHQBfAgALAAkJ/xYzHQBfAgAMAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAgAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJHAANAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgAECgYJBgABLgAECgYJGAAMAAkRAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAACLgAFFH8IAAIOAAQJtBtQCgBFAQAOAAQJtBtQCgBFAQAuAAQKfxYAAg4ABwn8H9wMAA8CAA4ABwn8H9wMAA8CAAAA.Beerbutt:BAAALgAECgEJAQAAAA==.Bellarg:BAABLgAECn83AAMPAAkJAxq4JwA8AgAPAAkJAxq4JwA8AgAQAAMJ3wetSACUAAAAAA==.Belobog:BAAALgAECgUJDQABLgAECggJHAADALsPAA==.Belyn:BAABLgAECn8XAAINAAcJRhM9NAB/AQANAAcJRhM9NAB/AQAAAA==.Benmage:BAAALgAECgUJBQAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bifesor:BAAALgAFFAMJAwAAAA==.Bigfaust:BAABLgAECn8YAAQJAAcJqB8sLABWAQAJAAUJpx8sLABWAQAIAAUJABu/LgBDAQAHAAIJRR8IUwDFAAAAAA==.',
Bl='Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAABLgAECn8UAAIKAAgJCgjtqwAiAQAKAAgJCgjtqwAiAQAAAA==.Bluespider:BAAALgAECgYJCQAAAA==.',
Bo='Bondrewd:BAAALgAECgEJAgABLgAECgUJHQARAIslAA==.Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAABLgAECn8WAAMIAAcJpRrsFgAKAgAIAAcJpRrsFgAKAgAHAAQJBiOLNAAtAQABLgAFFAgJGgAEALQaAA==.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Brolich:BAAALgAECggJEgABLgAECgQJBwAFAAAAAA==.Broo:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJEQAAAA==.Calculusx:BAABLgAECn8tAAISAAkJUCM6AQAHAwASAAkJUCM6AQAHAwAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8gAAMTAAYJ+RtBBAAtAgATAAYJrhtBBAAtAgAUAAIJmRtHAwCXAAAuAAQKfzcABBMACQkrJgsFALEDABMACQn7JQsFALEDABUACQnjIeECAAUCABQAAwnIItkLALwAAAAA.',
Ch='Champu:BAAALgAECgEJAQAAAA==.Chaoticx:BAAALgAECgMJAwAAAA==.Charlotte:BAAALgAECgcJEwAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn88AAQJAAkJ6yDfBADyAgAJAAkJ6yDfBADyAgAHAAMJfhSYaACAAAAIAAIJqwjspgBGAAABLgAFFAQJCAAOALQbAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAFAAAAAA==.',
Ci='Cinderion:BAAALgADCgUJBQABLgAECgkJSgAWAPceAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAAALgAECggJEAAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgTSQAYAgADAAgJ1BgTSQAYAgABLgAECgkJCQAFAAAAAA==.Combatboots:BAABLgAECn9GAAIXAAkJVBRWFADsAQAXAAkJVBRWFADsAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMJAAYJ2Rs0LwCaAQAJAAUJGhw0LwCaAQAHAAYJsRShNwBAAQAAAA==.Darilol:BAAALgAECgUJBQABLgAECgYJGAAMAAkRAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn80AAIYAAkJtCLoAwD8AgAYAAkJtCLoAwD8AgAAAA==.Debra:BAACLgAFFH8GAAIXAAMJlAsuHAC4AAAXAAMJlAsuHAC4AAAuAAQKfy0AAhcACQnCG7EPACgCABcACQnCG7EPACgCAAAA.Debz:BAAALgAECgcJCAAAAA==.Deegee:BAABLgAECn8dAAMZAAcJbSLzDACUAgAZAAcJbSLzDACUAgARAAYJvBjTJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAgAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJBQAAAA==.Demize:BAAALgAECgkJBwAAAA==.Demonflame:BAABLgAECn8nAAIQAAkJDxaqBgDwAQAQAAkJDxaqBgDwAQAAAA==.Demíze:BAAALgAECgEJAgAAAA==.Deshield:BAAALgAFFAQJBAABLgAFFAQJGgALACYmAA==.Deus:BAABLgAECn8bAAITAAkJexB6bACfAQATAAkJexB6bACfAQAAAA==.Dewry:BAABLgAECn8XAAMRAAYJWh87LAByAQARAAYJWh87LAByAQAaAAYJcBELMQBWAQAAAA==.',
Dh='Dhudamuthi:BAACLgAFFH8FAAIJAAMJmBnWGgCUAAAJAAMJmBnWGgCUAAAuAAQKfzsAAgkACQmfJLcCACwDAAkACQmfJLcCACwDAAAA.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwoof:BAAALgAECgYJDAAAAA==.Dizzo:BAAALgAECgkJBQAAAA==.',
Do='Donnajuan:BAABLgAECn86AAMNAAkJShzgCgDdAgANAAkJShzgCgDdAgAKAAEJ2QN3uAEkAAAAAA==.Dornath:BAABLgAECn9FAAIKAAgJvxIdawCVAQAKAAgJvxIdawCVAQAAAA==.',
Dr='Draaxelro:BAABLgAECn8bAAICAAkJ9RARWACXAQACAAkJ9RARWACXAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAQJGgALACYmAA==.Dragontiddys:BAABLgAECn8fAAMWAAgJRx9HBQDBAgAWAAgJRx9HBQDBAgAbAAEJJBYQigBCAAAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAFAAAAAA==.Drim:BAAALgADCgkJDAAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Eldread:BAAALgADCgEJAQAAAA==.Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8xAAIRAAkJxwqNKgB8AQARAAkJxwqNKgB8AQAAAA==.Elinalise:BAAALgAFFAEJAgABLgAFFAcJIwAcAHsNAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAACLgAFFH8MAAICAAQJzBflOAA1AQACAAQJzBflOAA1AQAuAAQKfzQAAgIACQkLIDEWAJ8CAAIACQkLIDEWAJ8CAAAA.',
Em='Embertal:BAAALgAECgYJEAAAAA==.Emvoi:BAAALgADCgUJBQAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgcJDgAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.Enzo:BAAALgAECgEJAQAAAA==.',
Ev='Evién:BAABLgAECn8UAAMdAAYJNxZEOQBrAQAdAAYJNxZEOQBrAQALAAUJthGPggDUAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Executè:BAAALgAECgEJAgABLgAFFAMJCQAXAMUaAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.Faustus:BAAALgADCgMJAwAAAA==.',
Fe='Feleså:BAAALgAECgcJBwABLgAFFAQJDwADACIfAA==.Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8pAAIKAAgJ8gecqgAkAQAKAAgJ8gecqgAkAQAAAA==.',
Fi='Fiammetta:BAECLgAFFH8PAAIeAAYJyyH/BgDKAQAeAAYJyyH/BgDKAQAuAAQKfxgAAh4ACQlrIyQNABUCAB4ACQlrIyQNABUCAAEuAAUUBwkWAAkAmyEA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Finke:BAABLgAECn8cAAITAAcJmRzrZwAHAgATAAcJmRzrZwAHAgAAAA==.Fishmärket:BAABLgAECn8iAAIMAAkJYA/UDgDAAQAMAAkJYA/UDgDAAQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJCAAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Frostie:BAABLgAFFH8GAAMYAAMJgwsoSwAAAAADAAIJgwtI7AB8AAAYAAEJAAAoSwAAAAABLgAFFAYJFAAKABcWAA==.Frís:BAAALgAECggJEwABLgAFFAQJEAAYAEgbAA==.',
Fu='Furryfist:BAAALgADCgcJCAAAAA==.',
Ga='Galarine:BAABLgAECn8sAAIPAAkJiRiYKAA4AgAPAAkJiRiYKAA4AgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAFFAQJCAAOALQbAA==.Gilrathor:BAAALgAECggJDgAAAA==.Gizzlit:BAABLgAECn8tAAIMAAkJzxt7BQCHAgAMAAkJzxt7BQCHAgAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAECgUJBgAAAA==.Gofetch:BAABLgAECn8hAAICAAkJsBvaKwAqAgACAAkJsBvaKwAqAgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAFAAAAAA==.',
Gr='Grandgoop:BAAALgAECgMJAwAAAA==.Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8oAAMCAAkJsx6AGQCIAgACAAkJsx6AGQCIAgAfAAUJ+hL5GAA/AQAAAA==.',
Gu='Guppy:BAAALgAECgcJDAAAAA==.Gutcassidy:BAAALgAECgYJCwAAAA==.',
Ha='Hac:BAAALgAECgcJEQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harps:BAAALgAECgUJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAFAAAAAA==.',
He='Healingkiss:BAABLgAECn8qAAIZAAkJPQKuQADlAAAZAAkJPQKuQADlAAAAAA==.Heatup:BAABLgAECn8aAAITAAgJfiMzFQApAwATAAgJfiMzFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Ho='Hollypallz:BAAALgADCgEJAQAAAA==.Holymages:BAABLgAECn8kAAITAAkJxRxFLQBiAgATAAkJxRxFLQBiAgAAAA==.Holymonka:BAAALgAECgEJAQAAAA==.Homtardy:BAABLgAECn8ZAAIgAAcJRh7FEQAWAgAgAAcJRh7FEQAWAgAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.Hunkomonk:BAAALgAECgcJCAABLgAECgkJJwAKABcgAA==.Hunt:BAAALgADCgIJAgAAAA==.',
Ic='Ickarus:BAAALgAECgQJBAAAAA==.',
Ik='Iknowaguy:BAAALgADCgkJCgABLgAECgkJRgAXAFQUAA==.',
Il='Ilyanna:BAABLgAECn8lAAMhAAkJgh3CBQAlAgAhAAkJgh3CBQAlAgAPAAEJXxDXCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8lAAQfAAgJjxjcAQAwAgAfAAcJfxncAQAwAgAiAAYJARqKBgC3AQACAAMJCxnaIgBaAAAuAAQKfyUAAiIACAmyJDgGADkDACIACAmyJDgGADkDAAAA.Imabadshot:BAAALgADCgUJBQAAAA==.Imscary:BAAALgADCgQJBAAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgcJDgAFAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgkJRgAXAFQUAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.Jenyaa:BAAALgAECgMJAwAAAA==.',
Jh='Jhalse:BAAALgAECgQJBAAAAA==.Jhoppss:BAABLgAECn8WAAMjAAYJlx1rDwDkAQAjAAYJlx1rDwDkAQAbAAQJjQ9IcACGAAAAAA==.',
Ji='Jiinxx:BAAALgAECgQJCAAAAA==.Jillià:BAAALgAFFAIJAwAAAA==.Jimpossible:BAAALgAECgYJCgAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Karls:BAAALgAECgYJDgAAAA==.',
Ke='Keez:BAAALgAECgcJDwAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kej:BAAALgAECgIJAgAAAA==.Kerafyrm:BAABLgAECn9KAAMWAAkJ9x6IAwAKAwAWAAkJ9x6IAwAKAwAbAAUJ7RuqPAA1AQAAAA==.Kerrigan:BAACLgAFFH8jAAIcAAcJew3KJACRAQAcAAcJew3KJACRAQAuAAQKfzMAAhwACQn4HnoWAI4CABwACQn4HnoWAI4CAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJHAANAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8iAAMEAAkJaBd5JAAoAgAEAAkJaBd5JAAoAgAkAAEJPRBUMQA+AAAAAA==.Kozand:BAAALgAECgcJDgABLgAECgYJGAAMAAkRAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgAECgEJAQAAAA==.',
Ky='Kyirr:BAABLgAECn8fAAMjAAkJgxlNDAAWAgAjAAcJQRpNDAAWAgAbAAUJFxhrRwAJAQAAAA==.Kyralen:BAABLgAECn8cAAMNAAYJHSPEGABMAgANAAYJHSPEGABMAgAKAAIJVxMvOQFuAAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAIMAAkJiRVRCgAsAgAMAAkJiRVRCgAsAgAAAA==.',
Li='Lilchithead:BAAALgAECgcJDwAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8WAAIJAAcJmyHRBQAtAgAJAAcJmyHRBQAtAgAuAAQKfy0AAgkACQnqJSUBAK0DAAkACQnqJSUBAK0DAAAA.Lividea:BAABLgAECn8pAAIDAAcJygb9vgD8AAADAAcJygb9vgD8AAAAAA==.Livinglover:BAAALgADCgUJAwAAAA==.',
Ll='Llela:BAAALgAECgcJCAAAAA==.Llynryn:BAABLgAECn8WAAIRAAgJ8A6EMwBLAQARAAgJ8A6EMwBLAQAAAA==.',
Lo='Locktua:BAAALgAECgcJCQAAAA==.',
Ly='Lympha:BAABLgAFFH8JAAMLAAMJ1x2jNAAIAQALAAMJ1x2jNAAIAQAMAAEJowGFHAAyAAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAcJFAAcAHUbAA==.Magicmanzz:BAABLgAECn8fAAITAAgJlw+qcQCTAQATAAgJlw+qcQCTAQAAAA==.Magnifuso:BAAALgAECggJEgAAAA==.Maguapa:BAAALgAECgQJBwAAAA==.Malgata:BAAALgADCgkJFgAAAA==.Margarita:BAAALgAECgUJCwAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8IAAINAAMJIRfxLwCwAAANAAMJIRfxLwCwAAAuAAQKfy4AAw0ACQnbH3wZADgCAA0ABwkNH3wZADgCAAoACAntGTBHAO4BAAAA.',
Mc='Mcplucky:BAAALgAECgYJEQAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Miguelito:BAAALgAECgEJAQABLgAECgcJFwAjALwcAA==.Mikio:BAABLgAECn8hAAIBAAkJdRDwIAC9AQABAAkJdRDwIAC9AQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8uAAIZAAkJLRxLCwCvAgAZAAkJLRxLCwCvAgAAAA==.Misho:BAAALgADCgEJAQAAAA==.',
Mo='Moardottz:BAABLgAECn8dAAIPAAYJPxW+cgB5AQAPAAYJPxW+cgB5AQABLgAECgUJBQAFAAAAAA==.Moiryn:BAACLgAFFH8PAAMLAAYJiBC7GgCKAQALAAYJiBC7GgCKAQAdAAEJfgerWAAzAAAuAAQKfy0AAwsACAl+HJ4ZAEoCAAsACAl+HJ4ZAEoCAB0AAgkoEMKFAF8AAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Nainaii:BAAALgAECgIJAwAAAA==.Naturals:BAAALgAECgEJAwAAAA==.Navidruid:BAAALgAFFAQJBAABLgAFFAgJJwAWADQQAA==.Navillus:BAACLgAFFH8nAAIWAAgJNBDqBwAqAgAWAAgJNBDqBwAqAgAuAAQKf0oAAxYACQnvFMEMAGoCABYACQnvFMEMAGoCACMACAkTIsQDAEwCAAAA.',
No='Norasoul:BAABLgAECn8wAAMcAAkJ5hs7GQB7AgAcAAkJ5hs7GQB7AgAlAAcJ2BTWDQBxAQAAAA==.',
['Nð']='Nðx:BAAALgAECgcJBwAAAA==.',
Og='Ogron:BAACLgAFFH8aAAMLAAQJJiZQFQCvAQALAAQJJiZQFQCvAQAdAAEJcx/FGwBTAAAuAAQKfzkAAx0ACQl8JRAEAF4DAB0ACQl8JRAEAF4DAAsAAwknIAyVAKUAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgAECgYJBgAAAA==.',
Op='Ophindis:BAAALgAECgcJDwAAAA==.',
Or='Orthos:BAACLgAFFH8PAAIDAAQJIh9ZOQCBAQADAAQJIh9ZOQCBAQAuAAQKfzYAAgMACQlXJZ0DAGUDAAMACQlXJZ0DAGUDAAAA.Orwenya:BAABLgAECn8YAAIMAAYJCREEHQAPAQAMAAYJCREEHQAPAQAAAA==.',
Os='Osten:BAABLgAECn8cAAINAAkJRBAgKADIAQANAAkJRBAgKADIAQAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAFAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Po='Porkit:BAAALgAFFAIJAwAAAA==.',
Pu='Putemuptoo:BAAALgAECgcJBAAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAABLgAFFH8HAAImAAIJeBfyLgCcAAAmAAIJeBfyLgCcAAAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgcJDgAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Reddacted:BAAALgADCgcJDAAAAA==.Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8eAAIBAAgJ1hjAAQAAAgABAAgJ1hjAAQAAAgAuAAQKfzsAAgEACQnBJtkAAIADAAEACQnBJtkAAIADAAAA.Respect:BAAALgAECgIJAgAAAA==.Rexam:BAAALgAECgIJAgABLgAECgcJGAAcAEUjAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAABLgAECn8sAAIgAAkJrxqDCgB5AgAgAAkJrxqDCgB5AgAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAABLgAECn86AAIgAAkJlCGLAwAOAwAgAAkJlCGLAwAOAwAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8bAAMUAAYJ5A8zCQBZAQAUAAYJ5A8zCQBZAQATAAYJown/0gDpAAAAAA==.',
['Rè']='Rènza:BAAALgAFFAMJBAAAAA==.',
Sa='Saelybrosa:BAAALgAECgcJDAAAAA==.Salphir:BAAALgAECgUJCQABLgAECgYJGAAMAAkRAA==.Samsara:BAAALgAECgQJCgAAAA==.Saphyr:BAEBLgAFFH8IAAIYAAUJbCC5EABxAQAYAAUJbCC5EABxAQABLgAFFAcJFgAJAJshAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Senniel:BAAALgAECgUJDwAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabit:BAAALgADCgUJBgABLgAFFAIJAwAFAAAAAA==.Shadda:BAABLgAECn8UAAIOAAYJ/BX3JwATAQAOAAYJ/BX3JwATAQAAAA==.Shadorae:BAAALgADCgcJBwABLgAECgQJDwAFAAAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8HAAIdAAIJXg28RQBuAAAdAAIJXg28RQBuAAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECggJEAAFAAAAAA==.Sheesh:BAAALgAECgIJAgAAAA==.Shinru:BAABLgAECn8WAAMNAAkJbhiuLACrAQANAAgJCxeuLACrAQAKAAYJlh4zmABBAQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAABLgAFFH8QAAIYAAQJSBuoFQA4AQAYAAQJSBuoFQA4AQAAAA==.',
Si='Sickdayze:BAABLgAECn8cAAINAAkJcR79DAC/AgANAAkJcR79DAC/AgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sikkunt:BAAALgAECgEJAwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.Skyrain:BAAALgAECgQJBQAAAA==.',
Sl='Slootin:BAAALgAECgEJAgAAAA==.Slyxxar:BAACLgAFFH8OAAILAAQJwQq5RQDNAAALAAQJwQq5RQDNAAAuAAQKfxwABAwACAkaF3IRAJgBAAwACAkaF3IRAJgBAB0ABgnBEexRAP8AAAsAAQl4AVWrAB8AAAAA.',
Sm='Smarc:BAABLgAECn9CAAIfAAkJcR87BADsAgAfAAkJcR87BADsAgAAAA==.Smashtokhan:BAAALgAECgUJCgAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8aAAIEAAgJtBpXBADOAgAEAAgJtBpXBADOAgAuAAQKfxgAAwQABwlsIlgnABkCAAQABwlsIlgnABkCAAEAAgmjFmSEADwAAAAA.Sophie:BAACLgAFFH8PAAMKAAQJwCHJJABuAQAKAAQJwCHJJABuAQANAAEJ2w1VSQAzAAAuAAQKfxwAAwoACAmwHOs7ADQCAAoACAmwHOs7ADQCAA0ABgkuDlNKAE8BAAEuAAUUCAkaAAQAtBoA.Sophievokie:BAAALgAFFAQJBAABLgAFFAgJGgAEALQaAA==.Sophisticate:BAABLgAFFH8QAAIfAAQJnB6UDQBUAQAfAAQJnB6UDQBUAQABLgAFFAgJGgAEALQaAA==.Sophiz:BAAALgAECgYJDwABLgAFFAgJGgAEALQaAA==.Sophlax:BAACLgAFFH8TAAIZAAUJLySjAQCpAQAZAAUJLySjAQCpAQAuAAQKfxkAAhkACQnLIA8EABQDABkACQnLIA8EABQDAAEuAAUUCAkaAAQAtBoA.Sophs:BAACLgAFFH8IAAILAAQJkBgAMQAWAQALAAQJkBgAMQAWAQAuAAQKfxUAAwsABgnGHDtUAF8BAAsABgnGHDtUAF8BAB0ABQmpEslaANkAAAEuAAUUCAkaAAQAtBoA.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAACLgAFFH8IAAIOAAMJWB/aDgANAQAOAAMJWB/aDgANAQAuAAQKfzAAAg4ACQkmIckCAAUDAA4ACQkmIckCAAUDAAAA.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAMJAwAFAAAAAA==.',
Sp='Spicynoodle:BAABLgAECn8WAAICAAkJShW4LgAdAgACAAkJShW4LgAdAgAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAABLgAECn8dAAIRAAUJiyVOJQCfAQARAAUJiyVOJQCfAQAAAA==.',
Sq='Squattinchop:BAABLgAECn8eAAIHAAYJQiH3FQA6AgAHAAYJQiH3FQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJHgAHAEIhAA==.',
St='Stacyguns:BAAALgAECgMJBAABLgAECgcJCgAFAAAAAA==.Stiffcrit:BAAALgAECgkJBwAAAA==.Stinkydh:BAABLgAECn8SAAIcAAYJMhFNcwBLAQAcAAYJMhFNcwBLAQAAAA==.Stryx:BAAALgADCgcJBwABLgAECgcJEgAFAAAAAA==.',
Su='Suji:BAABLgAECn8iAAIDAAkJXiBpEwDSAgADAAkJXiBpEwDSAgAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAFAAAAAA==.Supabird:BAAALgAECgQJBAAAAA==.Supergogeta:BAABLgAECn8yAAQEAAkJ3R9yDgDGAgAEAAgJsyByDgDGAgABAAIJkA96bQBpAAAOAAEJiQQ9NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgkJEQAAAA==.Synistër:BAAALgAECgUJBgAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôcôld:BAAALgADCgQJBAAAAA==.',
Ta='Takoda:BAAALgAECggJEAAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAABLgAECn8VAAICAAkJMwgcYQCAAQACAAkJMwgcYQCAAQAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tarkuun:BAAALgAECgkJCAAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBwAAAA==.',
Th='Thorish:BAABLgAECn8kAAInAAkJ5CGrAwDbAgAnAAkJ5CGrAwDbAgAAAA==.Thrayne:BAAALgADCgUJBgAAAA==.',
Ti='Tiddyweaver:BAABLgAECn8WAAMIAAgJeyKLCQD9AgAIAAgJeyKLCQD9AgAHAAIJjxGDdQBiAAABLgAECgkJHwAWAEcfAA==.Timbit:BAABLgAECn8jAAIHAAgJfQmhMwBTAQAHAAgJfQmhMwBTAQAAAA==.Tinfoiltotem:BAAALgADCgYJCgAAAA==.Tinybubbles:BAABLgAECn8lAAMLAAgJDhbxRgCOAQALAAgJDhbxRgCOAQAdAAQJKw2XXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJEAAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgcJDwAFAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8dAAMaAAkJGxivGAAKAgAaAAkJGxivGAAKAgARAAEJvwf9jQAqAAAAAA==.',
Tr='Trav:BAABLgAFFH8FAAIDAAQJLRJKaQAmAQADAAQJLRJKaQAmAQAAAA==.Trooth:BAAALgADCgYJBgABLgAECgUJDAAFAAAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgYJCgAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgkJCwAAAA==.',
Ty='Tyranis:BAEALgAECgYJCQAAAA==.Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAABLgAECn8XAAMWAAkJFw3MEQCoAQAWAAkJFw3MEQCoAQAbAAYJRAgAXgC8AAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Va='Vael:BAABLgAECn8iAAIcAAgJRxJ1VQCDAQAcAAgJRxJ1VQCDAQAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8pAAMYAAkJuBSSJgAcAQADAAcJ9RbRmwAwAQAYAAgJ+g6SJgAcAQAAAA==.Valériana:BAAALgADCgEJAQAAAA==.',
Ve='Vee:BAABLgAECn8fAAMoAAgJ+yOKEgBdAgAoAAgJ+yOKEgBdAgAmAAEJnBXmOwBBAAAAAA==.Veyla:BAEALgADCgcJDgABLgAECgYJBwAFAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAACLgAFFH8HAAIDAAQJVQkffgAHAQADAAQJVQkffgAHAQAuAAQKfyQAAgMACQlzFqN+AGMBAAMACQlzFqN+AGMBAAAA.',
Wa='Warkdom:BAAALgAECgUJCAAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAACLgAFFH8NAAIeAAMJViS3DwAuAQAeAAMJViS3DwAuAQAuAAQKfyYAAh4ACAlpJKUFALcCAB4ACAlpJKUFALcCAAAA.',
Wh='Wheelchair:BAEALgADCgYJBgABLgAECgYJBwAFAAAAAA==.',
Wi='Wickeddemon:BAABLgAECn8jAAIXAAkJ4hGaFwDEAQAXAAkJ4hGaFwDEAQAAAA==.Wildcanadian:BAAALgAECgIJAgAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
Wk='Wk:BAAALgAECgEJAQAAAA==.',
Wo='Wokstar:BAAALgAECgEJAgAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAINAAkJxhT8KQC8AQANAAkJxhT8KQC8AQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJIgAEAGgXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAACLgAFFH8OAAIcAAQJqxORRQARAQAcAAQJqxORRQARAQAuAAQKfyoAAhwACQkYIO8QALgCABwACQkYIO8QALgCAAAA.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8WAAIkAAUJGiC4AACxAQAkAAUJGiC4AACxAQAuAAQKfxYAAiQACAnDInIEANUCACQACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zacariana:BAAALgADCgcJBwAAAA==.Zaftenpuff:BAAALgAECgQJBAAAAA==.Zandashami:BAAALgAECggJCAAAAA==.Zarya:BAABLgAECn8UAAQHAAgJHB4fHgC4AQAHAAcJQhsfHgC4AQAIAAIJZhLajgBxAAAJAAEJWCVqdgBoAAAAAA==.',
Ze='Zelgie:BAABLgAECn8rAAMnAAkJ7BH0EgCXAQAnAAkJ7BH0EgCXAQANAAUJ6BCxUADzAAAAAA==.',
Zi='Zimzim:BAABLgAECn8dAAIIAAgJjxiyGgA9AgAIAAgJjxiyGgA9AgAAAA==.',
Zo='Zorsse:BAAALgAECgQJAwABLgAECggJHwAoAN0XAA==.',
Zu='Zulu:BAABLgAECn8VAAIJAAYJkBx7JgB4AQAJAAYJkBx7JgB4AQAAAA==.',
['Zâ']='Zâkârum:BAAALgADCgcJBwAAAA==.',
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
