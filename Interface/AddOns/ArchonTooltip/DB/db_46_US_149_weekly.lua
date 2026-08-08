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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Paladin-Retribution','Unknown-Unknown','Rogue-Outlaw','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Paladin-Protection','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Druid-Guardian','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Mage-Frost','Mage-Fire','Mage-Arcane','Warlock-Affliction','Rogue-Subtlety','Evoker-Preservation','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Evoker-Augmentation','DemonHunter-Devourer','Evoker-Devastation','Shaman-Elemental','Warrior-Protection','Hunter-Survival','Hunter-Marksmanship','Druid-Feral','DemonHunter-Vengeance','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAcJEgABADIhAA==.',
Ab='Abadizzo:BAAALgAECgcJDwAAAA==.Abadizzoo:BAABLgAECn8qAAICAAkJtyEJFgCkAgACAAkJtyEJFgCkAgAAAA==.Abilities:BAAALgAECgYJEgAAAA==.',
Ac='Ace:BAAALgAFFAEJAQAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAABLgAECn8VAAICAAYJIhXEeQBMAQACAAYJIhXEeQBMAQABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8sAAIEAAkJUiTUBABAAwAEAAkJUiTUBABAAwAAAA==.',
Ah='Ahkimbo:BAABLgAFFH8HAAIFAAMJwxBGLADaAAAFAAMJwxBGLADaAAAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airleara:BAAALgAECgcJDAAAAA==.Airwrecka:BAACLgAFFH8IAAIBAAMJ3RTDLwDFAAABAAMJ3RTDLwDFAAAuAAQKfzEAAgEACQnEHqUMAI0CAAEACQnEHqUMAI0CAAAA.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAGAAAAAA==.Aite:BAAALgAECgIJAgAAAA==.',
Al='Alexian:BAABLgAECn8bAAIHAAkJsRVzBQAPAgAHAAkJsRVzBQAPAgAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAABLgAECn8mAAICAAkJ8BUIDgCDAQACAAkJ8BUIDgCDAQAAAA==.',
Am='Amadk:BAAALgAECgkJAQAAAA==.Amebeliever:BAABLgAECn8fAAQIAAgJiB8ZFQBDAgAIAAcJuB4ZFQBDAgAJAAcJAgi/NwAMAQAKAAQJ/gmOZgB9AAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgkJFgAAAA==.',
Ap='Applemilk:BAAALgAECgEJAQAAAA==.',
Ar='Arahgon:BAEBLgAECn8nAAMFAAkJnxtuIQCBAgAFAAkJnxtuIQCBAgALAAEJJRmqEwBIAAABLgAECggJDgAGAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAGAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asphodelos:BAAALgAECgYJDQABLgAFFAcJFQADAKseAA==.Asukà:BAABLgAECn9DAAMMAAkJWRi/HQBfAgAMAAkJWRi/HQBfAgANAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAgAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJHAAOAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgAECgYJCQABLgAECgcJGgANABQQAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAACLgAFFH8PAAIPAAYJXBgICwBCAQAPAAYJXBgICwBCAQAuAAQKfxYAAg8ABwn8HzANAA8CAA8ABwn8HzANAA8CAAAA.Beerbutt:BAAALgAECgEJBAAAAA==.Bellarg:BAABLgAECn83AAMQAAkJAxosKQA3AgAQAAkJAxosKQA3AgARAAMJ3wetSACUAAAAAA==.Belobog:BAAALgAECgUJDQABLgAECggJHAADALsPAA==.Belyn:BAABLgAECn8dAAIOAAkJVxeHBQCRAQAOAAkJVxeHBQCRAQAAAA==.Benmage:BAAALgAECgUJBQAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bifesor:BAAALgAFFAMJAwAAAA==.Bigfaust:BAABLgAECn8YAAQKAAcJqB+7LABVAQAKAAUJpx+7LABVAQAJAAUJABu/LgBDAQAIAAIJRR8IUwDFAAAAAA==.',
Bl='Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAABLgAECn8UAAIFAAgJCghTrwAgAQAFAAgJCghTrwAgAQAAAA==.Bluespider:BAAALgAECgYJCQAAAA==.',
Bo='Bondrewd:BAAALgAECgEJAgABLgAFFAIJBgASADAgAA==.Bonedaddy:BAAALgADCgMJAwAAAA==.Booner:BAAALgADCgkJCQAAAA==.',
Br='Bratlax:BAACLgAFFH8IAAIIAAUJtxOnFwAFAQAIAAUJtxOnFwAFAQAuAAQKfxYAAwkABwmlGuwWAAoCAAkABwmlGuwWAAoCAAgABAkGI5k1ACwBAAEuAAUUCAkaAAQAtBoA.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.Brolich:BAAALgAECggJEgABLgAECgQJBwAGAAAAAA==.Broo:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJEgAAAA==.Calculusx:BAABLgAECn8tAAITAAkJUCNCAQAHAwATAAkJUCNCAQAHAwAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8uAAQUAAkJjRlBBAAtAgAUAAkJXhlBBAAtAgAVAAMJ8BXhAgDQAAAWAAIJmRt0AwCXAAAuAAQKfzcABBQACQkrJgsFALEDABQACQn7JQsFALEDABUACQnjIeECAAUCABYAAwnIIi0MALwAAAAA.',
Ch='Champu:BAAALgAECgEJAQAAAA==.Chaoticx:BAABLgAECn8fAAIXAAYJtQeLBwC6AAAXAAYJtQeLBwC6AAAAAA==.Charlotte:BAABLgAECn8VAAMHAAgJBRpECgB/AQAHAAcJPBtECgB/AQAYAAcJxQ7ONQD+AAAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn88AAQKAAkJ6yALBQDxAgAKAAkJ6yALBQDxAgAIAAMJfhQSagCAAAAJAAIJqwiMrABGAAABLgAFFAYJDwAPAFwYAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAGAAAAAA==.',
Ci='Cinderion:BAAALgADCgUJBQABLgAECgkJVQAZAIsgAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAABLgAECn8iAAILAAkJohD7AwB1AQALAAkJohD7AwB1AQAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgTSQAYAgADAAgJ1BgTSQAYAgABLgAECgkJCQAGAAAAAA==.Combatboots:BAABLgAECn9KAAIaAAkJVBTTFADpAQAaAAkJVBTTFADpAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMKAAYJ2Rs0LwCaAQAKAAUJGhw0LwCaAQAIAAYJsRShNwBAAQAAAA==.Darilol:BAAALgAECgUJDQABLgAECgcJGgANABQQAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn8+AAIbAAkJWCMCBAD5AgAbAAkJWCMCBAD5AgAAAA==.Debra:BAACLgAFFH8GAAIaAAMJlAtRHQC4AAAaAAMJlAtRHQC4AAAuAAQKfy0AAhoACQnCGw8QACYCABoACQnCGw8QACYCAAAA.Debz:BAAALgAECgcJCAAAAA==.Deegee:BAABLgAECn8dAAMcAAcJbSIvDQCTAgAcAAcJbSIvDQCTAgASAAYJvBjTJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAwAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJBQAAAA==.Demize:BAAALgAECgkJCAAAAA==.Demonflame:BAABLgAECn8nAAIRAAkJDxbXBgDwAQARAAkJDxbXBgDwAQAAAA==.Demíze:BAAALgAECgQJBQAAAA==.Deshield:BAAALgAFFAQJBAABLgAFFAUJHwAMADomAA==.Deus:BAABLgAECn8eAAIUAAkJGRE2bgCeAQAUAAkJGRE2bgCeAQAAAA==.Dewry:BAABLgAECn8eAAMSAAcJ0RyABQCKAQASAAYJHiCABQCKAQAdAAcJSxC2MQBUAQAAAA==.',
Dh='Dhudamuthi:BAACLgAFFH8HAAMKAAMJmBnWGgCUAAAKAAMJmBnWGgCUAAAIAAEJqRdUHQBDAAAuAAQKfzsAAgoACQmfJNECACsDAAoACQmfJNECACsDAAAA.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Din:BAAALgAECgIJAwAAAA==.Direwøøf:BAAALgAECgYJDAAAAA==.Dizzo:BAAALgAECgkJBwAAAA==.',
Do='Donnajuan:BAABLgAECn86AAMOAAkJShwSCwDcAgAOAAkJShwSCwDcAgAFAAEJ2QPovwEkAAAAAA==.Dornath:BAABLgAECn9bAAIFAAgJvxINFAAxAQAFAAgJvxINFAAxAQAAAA==.',
Dr='Draaxelro:BAABLgAECn8dAAICAAkJ9RDDWQCXAQACAAkJ9RDDWQCXAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAUJHwAMADomAA==.Dragontiddys:BAABLgAECn8gAAMZAAgJRx9cBQDBAgAZAAgJRx9cBQDBAgAeAAEJJBaLjABCAAAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAGAAAAAA==.Drim:BAAALgAECgEJAQAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Eldread:BAAALgADCgEJAQAAAA==.Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8xAAISAAkJxwoDLAB1AQASAAkJxwoDLAB1AQAAAA==.Elinalise:BAAALgAFFAEJAgABLgAFFAcJIwAfAHsNAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAACLgAFFH8ZAAICAAYJ0xdWHwAqAQACAAYJ0xdWHwAqAQAuAAQKfzYAAgIACQmxIDwWAKMCAAIACQmxIDwWAKMCAAAA.',
Em='Embertal:BAABLgAECn8XAAMeAAcJ2g6ZBgAcAQAeAAcJ2g6ZBgAcAQAgAAEJAAANMAAAAAAAAA==.Emvoi:BAAALgADCgUJBQAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgcJDgAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.Enzo:BAAALgAECgEJAQAAAA==.',
Eq='Eqlipse:BAAALgAECgMJAwAAAA==.',
Ev='Evién:BAABLgAECn8UAAMhAAYJNxZEOQBrAQAhAAYJNxZEOQBrAQAMAAUJthG7hADUAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Exasperate:BAAALgADCgIJAgAAAA==.Executè:BAAALgAECgEJAgABLgAFFAQJDQAaAKQYAA==.',
Ey='Eyecontact:BAAALgAECgQJBAAAAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.Fatpanda:BAAALgAECgEJAQAAAA==.Faustus:BAAALgADCgMJAwAAAA==.',
Fe='Feleså:BAAALgAECggJDwABLgAFFAcJFQADAKseAA==.Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8pAAIFAAgJ8gcErgAiAQAFAAgJ8gcErgAiAQAAAA==.',
Fi='Fiammetta:BAECLgAFFH8YAAIiAAgJ3x+kBgDfAQAiAAgJ3x+kBgDfAQAuAAQKfxgAAiIACQlrI3gNABMCACIACQlrI3gNABMCAAEuAAUUCQkmAAoAcyIA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJEgAGAAAAAA==.Finke:BAABLgAECn8gAAIUAAgJ4BvmGAAKAQAUAAgJ4BvmGAAKAQAAAA==.Firemge:BAEALgAECgkJCQABLgAFFAkJHQAbAMQbAA==.Fishmärket:BAABLgAECn8iAAINAAkJYA8YDwC/AQANAAkJYA8YDwC/AQAAAA==.Fistzz:BAAALgADCgUJBgAAAA==.',
Fl='Flickerbeat:BAAALgAECgYJEwAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Free:BAABLgAECn9VAAMZAAkJiyCYAwAKAwAZAAkJiyCYAwAKAwAeAAUJSB5zPQA0AQAAAA==.Frostie:BAABLgAFFH8QAAMDAAgJChUgDQAaAgADAAgJChUgDQAaAgAbAAEJAADrTQAAAAABLgAFFAkJGwAFAGcTAA==.Frís:BAAALgAECggJEwABLgAFFAQJFwAbACscAA==.',
Fu='Furryfist:BAAALgAECgEJAgAAAA==.',
Ga='Galarine:BAABLgAECn8sAAIQAAkJiRgwKQA3AgAQAAkJiRgwKQA3AgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gd='Gdizz:BAAALgAECgkJAgAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAFFAYJDwAPAFwYAA==.Gilrathor:BAAALgAECgkJEQAAAA==.Gizzlit:BAABLgAECn8tAAINAAkJzxukBQCHAgANAAkJzxukBQCHAgAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAFFAEJAgAAAA==.Gofetch:BAABLgAECn8hAAICAAkJsBvtLAApAgACAAkJsBvtLAApAgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAGAAAAAA==.Gordon:BAAALgAECgEJAQABLgAECggJIgAfAEcSAA==.',
Gr='Grandgoop:BAAALgAECgMJAwAAAA==.Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8oAAMCAAkJsx54GgCHAgACAAkJsx54GgCHAgAjAAUJ+hL5GAA/AQAAAA==.',
Gs='Gson:BAAALgAECgcJBwAAAA==.',
Gu='Guppy:BAAALgAECgcJDAAAAA==.Gutcassidy:BAAALgAECgYJCwAAAA==.Guttss:BAAALgAECgEJAQAAAA==.',
Ha='Hac:BAAALgAECgcJEQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJEQAGAAAAAA==.Hakka:BAAALgAECgEJAQABLgAECgcJEQAGAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harps:BAAALgAECgUJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAGAAAAAA==.',
He='Healingkiss:BAABLgAECn8qAAIcAAkJPQKlQQDlAAAcAAkJPQKlQQDlAAAAAA==.Heatup:BAABLgAECn8aAAIUAAgJfiMzFQApAwAUAAgJfiMzFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Hi='Hikingboots:BAAALgAECgcJEwAAAA==.',
Ho='Hollypallz:BAAALgADCgEJAQAAAA==.Holymages:BAABLgAECn8kAAIUAAkJxRwVLgBgAgAUAAkJxRwVLgBgAgAAAA==.Holymonka:BAAALgAECgEJAQAAAA==.Homtardy:BAABLgAECn8ZAAIYAAcJRh4zEgAVAgAYAAcJRh4zEgAVAgAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.Hunkomonk:BAAALgAECgcJCAABLgAECgkJJwAFABcgAA==.Hunt:BAAALgAFFAIJBAAAAA==.',
Ic='Ickarus:BAAALgAECgQJBQAAAA==.',
Ik='Iknowaguy:BAAALgADCgkJEwABLgAECgkJSgAaAFQUAA==.',
Il='Ilyanna:BAABLgAECn8lAAMXAAkJgh3rBQAkAgAXAAkJgh3rBQAkAgAQAAEJXxDXCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8yAAQjAAkJDhsJAgAuAgAjAAcJwBsJAgAuAgAkAAYJARqKBgC3AQACAAQJXBvJVwBlAAAuAAQKfyUAAiQACAmyJDgGADkDACQACAmyJDgGADkDAAAA.Imabadshot:BAAALgAECgEJAgAAAA==.Imscary:BAAALgAECgQJBgAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgcJDgAGAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgkJSgAaAFQUAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.Jenyaa:BAAALgAECgMJAwAAAA==.',
Jh='Jhalse:BAAALgAECgQJBAAAAA==.Jhoppss:BAABLgAECn8WAAMgAAYJlx1rDwDkAQAgAAYJlx1rDwDkAQAeAAQJjQ8ecgCGAAAAAA==.',
Ji='Jiinxx:BAAALgAECgQJCAAAAA==.Jilliebean:BAAALgAECgIJBQAAAA==.Jillià:BAAALgAFFAIJAwAAAA==.Jimpossible:BAAALgAECgYJCgAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Kallisto:BAAALgAFFAMJAwABLgAFFAYJBwADALkTAA==.Karls:BAAALgAECgYJDgAAAA==.',
Ke='Keez:BAAALgAECgcJDwAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kej:BAAALgAECgIJAgAAAA==.Kerrigan:BAACLgAFFH8jAAIfAAcJew3IJgCRAQAfAAcJew3IJgCRAQAuAAQKfzMAAh8ACQn4HtYWAI4CAB8ACQn4HtYWAI4CAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJHAAOAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8lAAMEAAkJaBd5JAAoAgAEAAkJaBd5JAAoAgAlAAMJgCH+BAAXAQAAAA==.Kozand:BAAALgAECgcJEAABLgAECgcJGgANABQQAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgAECgQJCAAAAA==.',
Ky='Kyirr:BAABLgAECn8fAAMgAAkJgxlNDAAWAgAgAAcJQRpNDAAWAgAeAAUJFxiFSAAJAQAAAA==.Kyralen:BAABLgAECn8cAAMOAAYJHSPEGABMAgAOAAYJHSPEGABMAgAFAAIJVxMPPgFuAAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAINAAkJiRVRCgAsAgANAAkJiRVRCgAsAgAAAA==.',
Le='Lexxi:BAAALgAFFAEJAQAAAA==.',
Li='Lilchithead:BAAALgAECgcJDwAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8mAAIKAAkJcyKEBgAqAgAKAAkJcyKEBgAqAgAuAAQKfy0AAgoACQnqJSUBAK0DAAoACQnqJSUBAK0DAAAA.Lividea:BAABLgAECn8pAAIDAAcJygbzwgD6AAADAAcJygbzwgD6AAAAAA==.Livinglover:BAAALgADCgUJAwAAAA==.',
Ll='Llela:BAAALgAECgcJCAAAAA==.Llynryn:BAABLgAECn8ZAAISAAgJhBCEMwBLAQASAAgJhBCEMwBLAQAAAA==.',
Lo='Locktua:BAAALgAECgcJCQAAAA==.',
Lu='Luhen:BAAALgAECgMJAwAAAA==.',
Ly='Lympha:BAABLgAFFH8JAAMMAAMJ1x3iNgAHAQAMAAMJ1x3iNgAHAQANAAEJowEhHgAvAAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAkJKQAfAC0hAA==.Magicmanzz:BAABLgAECn8xAAIUAAkJsBGlCQDBAQAUAAkJsBGlCQDBAQAAAA==.Magnifuso:BAAALgAECggJEwAAAA==.Maguapa:BAAALgAECgQJBwAAAA==.Malgata:BAAALgADCgkJHwAAAA==.Margarita:BAAALgAECgUJCwAAAA==.Marker:BAAALgADCgQJBAAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8IAAIOAAMJIRccMQCvAAAOAAMJIRccMQCvAAAuAAQKfy4AAw4ACQnbH9wZADcCAA4ABwkNH9wZADcCAAUACAntGVpIAO0BAAAA.',
Mc='Mcplucky:BAABLgAECn8hAAIkAAYJ4AjDBQCsAAAkAAYJ4AjDBQCsAAAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Miguelito:BAAALgAECgEJAQABLgAECgcJFwAgALwcAA==.Mikio:BAABLgAECn8hAAIBAAkJdRDjIQC6AQABAAkJdRDjIQC6AQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8uAAIcAAkJLRyHCwCuAgAcAAkJLRyHCwCuAgAAAA==.Misho:BAAALgAECgMJAwAAAA==.',
Mo='Moardottz:BAABLgAECn8dAAIQAAYJPxW+cgB5AQAQAAYJPxW+cgB5AQABLgAECgUJBQAGAAAAAA==.Moiryn:BAACLgAFFH8YAAMMAAgJlhFJHACKAQAMAAgJlhFJHACKAQAhAAQJ7wlXHwCkAAAuAAQKfy8AAwwACQmJHZ4ZAEoCAAwACAl+HJ4ZAEoCACEAAwlhGMUSAKUAAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Nainaii:BAAALgAFFAEJAQAAAA==.Nalthexon:BAAALgAECgEJAQAAAA==.Naturals:BAAALgAECgEJAwAAAA==.Navidruid:BAABLgAFFH8IAAIlAAQJLwgMEgCpAAAlAAQJLwgMEgCpAAABLgAFFAgJKwAZADQQAA==.Navillus:BAACLgAFFH8rAAMZAAgJNBBtCAAqAgAZAAgJNBBtCAAqAgAgAAEJwRccBwBJAAAuAAQKf0oAAxkACQnvFMEMAGoCABkACQnvFMEMAGoCACAACAkTItgDAEsCAAAA.',
Nn='Nnyryl:BAAALgAECgEJAQAAAA==.',
No='Norasoul:BAABLgAECn8wAAMfAAkJ5huiGQB7AgAfAAkJ5huiGQB7AgAmAAcJ2BQUDgBxAQAAAA==.Nowyourdead:BAAALgAECgQJBQAAAA==.',
['Nð']='Nðx:BAAALgAECggJDgAAAA==.',
Oa='Oakensoul:BAAALgAECgcJCAABLgAECgkJJwAFABcgAA==.',
Og='Ogron:BAACLgAFFH8fAAMMAAUJOib4FgCuAQAMAAUJOib4FgCuAQAhAAIJ2xzkIwCJAAAuAAQKfzkAAyEACQl8JRAEAF4DACEACQl8JRAEAF4DAAwAAwknIKyXAKUAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgAECgYJBgAAAA==.',
Op='Ophindis:BAAALgAECgcJDwAAAA==.',
Or='Orthos:BAACLgAFFH8VAAIDAAcJqx4jGACdAQADAAcJqx4jGACdAQAuAAQKfz4AAgMACQl5JdgDAGQDAAMACQl5JdgDAGQDAAAA.Orwenya:BAABLgAECn8aAAINAAcJFBC5HQANAQANAAcJFBC5HQANAQAAAA==.',
Os='Osten:BAABLgAECn8cAAIOAAkJRBDHKADGAQAOAAkJRBDHKADGAQAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAGAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phobos:BAAALgAECgUJBwAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Pl='Plâgue:BAAALgAECgQJBgAAAA==.',
Po='Porkit:BAAALgAFFAIJAwAAAA==.',
Pu='Putemuptoo:BAAALgAECgcJBwAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAABLgAFFH8KAAMnAAMJ3RPlGQDRAAAnAAMJ3RPlGQDRAAAoAAIJeBfCMACcAAAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgcJDgAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Reddacted:BAAALgADCgcJDAAAAA==.Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8rAAIBAAkJQxvAAQAAAgABAAkJQxvAAQAAAgAuAAQKfzsAAgEACQnBJt0AAH8DAAEACQnBJt0AAH8DAAAA.Respect:BAAALgAECgIJAgAAAA==.Rexam:BAAALgAECgIJAgABLgAECgcJGAAfAEUjAA==.Rexsouls:BAAALgAFFAEJAQAAAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAABLgAECn8sAAIYAAkJrxraCgB2AgAYAAkJrxraCgB2AgAAAA==.Rivet:BAAALgADCgQJBAAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAABLgAECn9HAAIYAAkJnCGoAwAMAwAYAAkJnCGoAwAMAwAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8bAAMWAAYJ5A8zCQBZAQAWAAYJ5A8zCQBZAQAUAAYJowmu1QDpAAAAAA==.',
['Rè']='Rènza:BAABLgAFFH8KAAIaAAMJJxjbEgCUAAAaAAMJJxjbEgCUAAAAAA==.',
Sa='Saelybrosa:BAAALgAECggJDgAAAA==.Salphir:BAAALgAECgUJCQABLgAECgcJGgANABQQAA==.Samsara:BAAALgAECgQJCgAAAA==.Sanguineous:BAAALgAFFAEJAQABLgAFFAUJCgAFAAIKAA==.Saphia:BAEALgAFFAEJAQABLgAFFAkJJgAKAHMiAA==.Saphyr:BAEBLgAFFH8IAAIbAAUJbCCyEQBuAQAbAAUJbCCyEQBuAQABLgAFFAkJJgAKAHMiAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Senniel:BAAALgAECgYJEwAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabalaba:BAAALgAECgEJAQAAAA==.Shabit:BAAALgADCgUJBgABLgAFFAIJAwAGAAAAAA==.Shadda:BAABLgAECn8bAAIPAAcJXhelBQBQAQAPAAcJXhelBQBQAQAAAA==.Shadorae:BAAALgADCgcJBwABLgAECgYJEQAGAAAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8HAAIhAAIJXg0bSABuAAAhAAIJXg0bSABuAAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECgkJIgALAKIQAA==.Sheesh:BAAALgAECgYJCgAAAA==.Shinru:BAACLgAFFH8HAAIOAAMJ2xoiDwABAQAOAAMJ2xoiDwABAQAuAAQKfx8AAw4ACQmeF0oGAHUBAA4ACQmeF0oGAHUBAAUABgmWHoglALgAAAAA.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAABLgAFFH8XAAIbAAQJKxy2FgA0AQAbAAQJKxy2FgA0AQAAAA==.',
Si='Sickdayze:BAABLgAECn8fAAIOAAkJwCA4DQC+AgAOAAkJwCA4DQC+AgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sikkunt:BAAALgAECgEJAwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAGAAAAAA==.Skyrain:BAAALgAECgUJBgAAAA==.',
Sl='Slootin:BAAALgAECgEJAgAAAA==.Slyxxar:BAACLgAFFH8OAAIMAAQJwQruRwDNAAAMAAQJwQruRwDNAAAuAAQKfxwABA0ACAkaF9sRAJcBAA0ACAkaF9sRAJcBACEABgnBEexRAP8AAAwAAQl4AVWrAB8AAAAA.',
Sm='Smarc:BAABLgAECn9FAAIjAAkJcR9aBADpAgAjAAkJcR9aBADpAgAAAA==.Smashtokhan:BAAALgAECgUJCgAAAA==.',
Sn='Snak:BAAALgAFFAIJAgAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8aAAIEAAgJtBrXBADLAgAEAAgJtBrXBADLAgAuAAQKfxgAAwQABwlsIlgnABkCAAQABwlsIlgnABkCAAEAAgmjFq6GADwAAAAA.Sophie:BAACLgAFFH8PAAMFAAQJwCF+JwBsAQAFAAQJwCF+JwBsAQAOAAEJ2w3qSgAzAAAuAAQKfxwAAwUACAmwHOs7ADQCAAUACAmwHOs7ADQCAA4ABgkuDlNKAE8BAAEuAAUUCAkaAAQAtBoA.Sophievokie:BAAALgAFFAQJBAABLgAFFAgJGgAEALQaAA==.Sophisticate:BAABLgAFFH8QAAIjAAQJnB5HDgBTAQAjAAQJnB5HDgBTAQABLgAFFAgJGgAEALQaAA==.Sophiz:BAAALgAECgYJDwABLgAFFAgJGgAEALQaAA==.Sophlax:BAACLgAFFH8TAAIcAAUJLySjAQCpAQAcAAUJLySjAQCpAQAuAAQKfxkAAhwACQnLIA8EABQDABwACQnLIA8EABQDAAEuAAUUCAkaAAQAtBoA.Sophs:BAACLgAFFH8IAAIMAAQJkBgUMwAWAQAMAAQJkBgUMwAWAQAuAAQKfxUAAwwABgnGHK5VAF8BAAwABgnGHK5VAF8BACEABQmpEslaANkAAAEuAAUUCAkaAAQAtBoA.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAACLgAFFH8IAAIPAAMJWB/ODwAKAQAPAAMJWB/ODwAKAQAuAAQKfzAAAg8ACQkmIeUCAAUDAA8ACQkmIeUCAAUDAAAA.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAMJAwAGAAAAAA==.',
Sp='Spankgg:BAAALgAECgcJCgAAAA==.Spicynoodle:BAABLgAECn8WAAICAAkJShXZLwAdAgACAAkJShXZLwAdAgAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAACLgAFFH8GAAISAAIJMCB0IABRAAASAAIJMCB0IABRAAAuAAQKfx0AAhIABQmLJcIlAJ0BABIABQmLJcIlAJ0BAAAA.',
Sq='Squattinchop:BAABLgAECn8eAAIIAAYJQiH3FQA6AgAIAAYJQiH3FQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJHgAIAEIhAA==.',
St='Stacyguns:BAAALgAECgMJBAABLgAECgcJCgAGAAAAAA==.Stian:BAAALgAECgUJBQAAAA==.Stiffcrit:BAAALgAECgkJBwAAAA==.Stinkydh:BAABLgAECn8SAAIfAAYJMhFNcwBLAQAfAAYJMhFNcwBLAQAAAA==.Stryx:BAAALgADCgcJBwABLgAECgcJEgAGAAAAAA==.',
Su='Suji:BAABLgAECn8iAAIDAAkJXiAIFADQAgADAAkJXiAIFADQAgAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAGAAAAAA==.Supabird:BAAALgAECgQJBAAAAA==.Supergogeta:BAABLgAECn8yAAQEAAkJ3R9yDgDGAgAEAAgJsyByDgDGAgABAAIJkA82bwBpAAAPAAEJiQQ9NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgkJEQAAAA==.Synistër:BAAALgAECgYJBwAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôcôld:BAAALgADCgQJBAAAAA==.',
Ta='Takoda:BAAALgAECggJEAAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAABLgAECn8VAAICAAkJMwj5YgCAAQACAAkJMwj5YgCAAQAAAA==.Tandaris:BAAALgADCgYJBgAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tarkuun:BAAALgAECgkJCAAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBwAAAA==.',
Th='Thndrsquirel:BAAALgAECgkJDwABLgAECgkJSgAaAFQUAA==.Thorish:BAABLgAECn8kAAILAAkJ5CGrAwDbAgALAAkJ5CGrAwDbAgAAAA==.Thrayne:BAAALgAECgMJAwAAAA==.',
Ti='Tiddyweaver:BAABLgAECn8XAAMJAAgJGyP+BwAdAwAJAAgJGyP+BwAdAwAIAAIJjxHCdwBhAAABLgAECgkJIAAZAEcfAA==.Timbit:BAABLgAECn8jAAIIAAgJfQmhMwBTAQAIAAgJfQmhMwBTAQAAAA==.Tinfoiltotem:BAAALgAECgUJBQAAAA==.Tinybubbles:BAABLgAECn8oAAMMAAkJbRQRSACOAQAMAAkJbRQRSACOAQAhAAQJKw2XXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJEwAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgcJDwAGAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8gAAMdAAkJGRlXGQAHAgAdAAkJGRlXGQAHAgASAAEJvwejkAAqAAAAAA==.',
Tr='Trav:BAABLgAFFH8FAAIDAAQJLRKIawAkAQADAAQJLRKIawAkAQAAAA==.Trooth:BAAALgADCgYJBgABLgAECgUJDAAGAAAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgYJCgAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgkJCwAAAA==.',
Ty='Tyranis:BAEALgAECggJDgAAAA==.Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAABLgAECn8XAAMZAAkJFw0DEgCoAQAZAAkJFw0DEgCoAQAeAAYJRAh9XwC8AAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Uw='Uwusev:BAAALgAECgIJAgAAAA==.',
Va='Vael:BAABLgAECn8iAAIfAAgJRxKDVgCDAQAfAAgJRxKDVgCDAQAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8pAAMbAAkJuBSAJwAYAQADAAcJ9RbEngAuAQAbAAgJ+g6AJwAYAQAAAA==.Valexisea:BAAALgAECgEJAQABLgAFFAcJFQADAKseAA==.Valériana:BAAALgADCgMJAwAAAA==.',
Ve='Vee:BAABLgAECn8fAAMnAAgJ+yPlEgBbAgAnAAgJ+yPlEgBbAgAoAAEJnBXmOwBBAAAAAA==.Veyla:BAAALgADCgcJDgABLgAECgYJBwAGAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAACLgAFFH8HAAIDAAQJVQk+ggADAQADAAQJVQk+ggADAQAuAAQKfyQAAgMACQlzFoqAAGIBAAMACQlzFoqAAGIBAAAA.',
Wa='Warkdom:BAAALgAECgUJCAAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAACLgAFFH8PAAIiAAMJViR8EAAsAQAiAAMJViR8EAAsAQAuAAQKfyYAAiIACAlpJMcFALYCACIACAlpJMcFALYCAAAA.',
Wh='Wheelchair:BAAALgADCgYJBgABLgAECgYJBwAGAAAAAA==.',
Wi='Wickeddemon:BAABLgAECn8lAAIaAAkJzBIhGADCAQAaAAkJzBIhGADCAQAAAA==.Wildcanadian:BAAALgAECgIJAgAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
Wk='Wk:BAAALgAECgEJAQAAAA==.',
Wo='Wokstar:BAAALgAECgEJAgAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAIOAAkJxhT0KgC5AQAOAAkJxhT0KgC5AQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJJQAEAGgXAA==.',
Xc='Xcessiv:BAAALgADCgUJBgAAAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAACLgAFFH8PAAIfAAQJqxO/RwAQAQAfAAQJqxO/RwAQAQAuAAQKfzYAAh8ACQmeIyQCAIoCAB8ACQmeIyQCAIoCAAAA.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8eAAIlAAgJWxsjAQDnAQAlAAgJWxsjAQDnAQAuAAQKfxYAAiUACAnDInIEANUCACUACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.Yrel:BAAALgAECgQJBAABLgAECgcJGgANABQQAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zacariana:BAAALgADCgcJBwAAAA==.Zaftenpuff:BAAALgAECgQJBAAAAA==.Zandashami:BAAALgAECggJCAAAAA==.Zaria:BAAALgAECgUJBQAAAA==.Zarya:BAABLgAECn8iAAQJAAkJXhyjAQDeAgAJAAkJXhyjAQDeAgAIAAcJQhusHgC4AQAKAAEJWCVqdgBoAAAAAA==.',
Ze='Zelgie:BAABLgAECn8rAAMLAAkJ7BExEwCXAQALAAkJ7BExEwCXAQAOAAUJ6BDnUQDxAAAAAA==.',
Zi='Zimzim:BAABLgAECn8dAAIJAAgJjxhbGwA9AgAJAAgJjxhbGwA9AgAAAA==.',
Zo='Zorsse:BAAALgAECgQJAwABLgAECggJHwAnAN0XAA==.',
Zu='Zulu:BAABLgAECn8VAAIKAAYJkBzxJgB4AQAKAAYJkBzxJgB4AQAAAA==.',
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
