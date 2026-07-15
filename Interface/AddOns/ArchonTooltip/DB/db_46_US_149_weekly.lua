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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Paladin-Retribution','Unknown-Unknown','Rogue-Outlaw','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Druid-Guardian','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Mage-Frost','Mage-Fire','Mage-Arcane','Warlock-Affliction','Evoker-Preservation','Paladin-Protection','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Evoker-Augmentation','DemonHunter-Devourer','Evoker-Devastation','Shaman-Elemental','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Hunter-Marksmanship','Druid-Feral','DemonHunter-Vengeance','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAcJEgABADIhAA==.',
Ab='Abadizzo:BAAALgAECgcJDwAAAA==.Abadizzoo:BAABLgAECn8qAAICAAkJtyEJFgCkAgACAAkJtyEJFgCkAgAAAA==.Abilities:BAAALgAECgYJEgAAAA==.',
Ac='Ace:BAAALgAFFAEJAQAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAABLgAECn8VAAICAAYJIhXEeQBMAQACAAYJIhXEeQBMAQABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8sAAIEAAkJUiTUBABAAwAEAAkJUiTUBABAAwAAAA==.',
Ah='Ahkimbo:BAABLgAFFH8GAAIFAAMJAQtxLAC/AAAFAAMJAQtxLAC/AAAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airleara:BAAALgAECgcJDAAAAA==.Airwrecka:BAACLgAFFH8IAAIBAAMJ3RTDLwDFAAABAAMJ3RTDLwDFAAAuAAQKfzEAAgEACQnEHqUMAI0CAAEACQnEHqUMAI0CAAAA.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAGAAAAAA==.Aite:BAAALgAECgIJAgAAAA==.',
Al='Alexian:BAABLgAECn8bAAIHAAkJsRVzBQAPAgAHAAkJsRVzBQAPAgAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAABLgAECn8fAAICAAkJlxSLDABRAQACAAkJlxSLDABRAQAAAA==.',
Am='Amadk:BAAALgAECgkJAQAAAA==.Amebeliever:BAABLgAECn8fAAQIAAgJiB8ZFQBDAgAIAAcJuB4ZFQBDAgAJAAcJAgi/NwAMAQAKAAQJ/gmOZgB9AAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgkJFgAAAA==.',
Ar='Arahgon:BAEBLgAECn8lAAIFAAkJnxtuIQCBAgAFAAkJnxtuIQCBAgABLgAECggJDgAGAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAGAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asphodelos:BAAALgAECgYJDQABLgAFFAYJFAADAIcgAA==.Asukà:BAABLgAECn9DAAMLAAkJWRi/HQBfAgALAAkJWRi/HQBfAgAMAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAgAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJHAANAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgAECgYJBgABLgAECgcJGgAMABQQAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAACLgAFFH8OAAIOAAUJ6hsICwBCAQAOAAUJ6hsICwBCAQAuAAQKfxYAAg4ABwn8HzANAA8CAA4ABwn8HzANAA8CAAAA.Beerbutt:BAAALgAECgEJBAAAAA==.Bellarg:BAABLgAECn83AAMPAAkJAxosKQA3AgAPAAkJAxosKQA3AgAQAAMJ3wetSACUAAAAAA==.Belobog:BAAALgAECgUJDQABLgAECggJHAADALsPAA==.Belyn:BAABLgAECn8dAAINAAkJVxelAwCOAQANAAkJVxelAwCOAQAAAA==.Benmage:BAAALgAECgUJBQAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bifesor:BAAALgAFFAMJAwAAAA==.Bigfaust:BAABLgAECn8YAAQKAAcJqB+7LABVAQAKAAUJpx+7LABVAQAJAAUJABu/LgBDAQAIAAIJRR8IUwDFAAAAAA==.',
Bl='Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAABLgAECn8UAAIFAAgJCghTrwAgAQAFAAgJCghTrwAgAQAAAA==.Bluespider:BAAALgAECgYJCQAAAA==.',
Bo='Bondrewd:BAAALgAECgEJAgABLgAFFAIJBgARADAgAA==.Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAACLgAFFH8IAAIIAAUJtxOnFwAFAQAIAAUJtxOnFwAFAQAuAAQKfxYAAwkABwmlGuwWAAoCAAkABwmlGuwWAAoCAAgABAkGI5k1ACwBAAEuAAUUCAkaAAQAtBoA.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.Brolich:BAAALgAECggJEgABLgAECgQJBwAGAAAAAA==.Broo:BAAALgAECgEJAQABLgAECgQJBwAGAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJEgAAAA==.Calculusx:BAABLgAECn8tAAISAAkJUCNCAQAHAwASAAkJUCNCAQAHAwAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8qAAQTAAgJfxpBBAAtAgATAAgJSRpBBAAtAgAUAAMJ8BUDAgDwAAAVAAIJmRt0AwCXAAAuAAQKfzcABBMACQkrJgsFALEDABMACQn7JQsFALEDABQACQnjIeECAAUCABUAAwnIIi0MALwAAAAA.',
Ch='Champu:BAAALgAECgEJAQAAAA==.Chaoticx:BAABLgAECn8UAAIWAAQJXgM/BwB+AAAWAAQJXgM/BwB+AAAAAA==.Charlotte:BAAALgAECgcJEwAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn88AAQKAAkJ6yALBQDxAgAKAAkJ6yALBQDxAgAIAAMJfhQSagCAAAAJAAIJqwiMrABGAAABLgAFFAUJDgAOAOobAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAGAAAAAA==.',
Ci='Cinderion:BAAALgADCgUJBQABLgAECgkJVQAXAIsgAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAABLgAECn8bAAIYAAkJohASAwBVAQAYAAkJohASAwBVAQAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgTSQAYAgADAAgJ1BgTSQAYAgABLgAECgkJCQAGAAAAAA==.Combatboots:BAABLgAECn9KAAIZAAkJVBTTFADpAQAZAAkJVBTTFADpAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMKAAYJ2Rs0LwCaAQAKAAUJGhw0LwCaAQAIAAYJsRShNwBAAQAAAA==.Darilol:BAAALgAECgUJDQABLgAECgcJGgAMABQQAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn84AAIaAAkJtCICBAD5AgAaAAkJtCICBAD5AgAAAA==.Debra:BAACLgAFFH8GAAIZAAMJlAtRHQC4AAAZAAMJlAtRHQC4AAAuAAQKfy0AAhkACQnCGw8QACYCABkACQnCGw8QACYCAAAA.Debz:BAAALgAECgcJCAAAAA==.Deegee:BAABLgAECn8dAAMbAAcJbSIvDQCTAgAbAAcJbSIvDQCTAgARAAYJvBjTJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAwAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJBQAAAA==.Demize:BAAALgAECgkJCAAAAA==.Demonflame:BAABLgAECn8nAAIQAAkJDxbXBgDwAQAQAAkJDxbXBgDwAQAAAA==.Demíze:BAAALgAECgQJBQAAAA==.Deshield:BAAALgAFFAQJBAABLgAFFAUJHwALADomAA==.Deus:BAABLgAECn8eAAITAAkJGRE2bgCeAQATAAkJGRE2bgCeAQAAAA==.Dewry:BAABLgAECn8eAAMRAAcJ0Rx6AwCVAQARAAYJHiB6AwCVAQAcAAcJSxC2MQBUAQAAAA==.',
Dh='Dhudamuthi:BAACLgAFFH8HAAMKAAMJmBnWGgCUAAAKAAMJmBnWGgCUAAAIAAEJqRelFgBJAAAuAAQKfzsAAgoACQmfJNECACsDAAoACQmfJNECACsDAAAA.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Din:BAAALgAECgEJAgAAAA==.Direwøøf:BAAALgAECgYJDAAAAA==.Dizzo:BAAALgAECgkJBwAAAA==.',
Do='Donnajuan:BAABLgAECn86AAMNAAkJShwSCwDcAgANAAkJShwSCwDcAgAFAAEJ2QPovwEkAAAAAA==.Dornath:BAABLgAECn9bAAIFAAgJvxIwDQA8AQAFAAgJvxIwDQA8AQAAAA==.',
Dr='Draaxelro:BAABLgAECn8dAAICAAkJ9RDDWQCXAQACAAkJ9RDDWQCXAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAUJHwALADomAA==.Dragontiddys:BAABLgAECn8gAAMXAAgJRx9cBQDBAgAXAAgJRx9cBQDBAgAdAAEJJBaLjABCAAAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAGAAAAAA==.Drim:BAAALgAECgEJAQAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Eldread:BAAALgADCgEJAQAAAA==.Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8xAAIRAAkJxwoDLAB1AQARAAkJxwoDLAB1AQAAAA==.Elinalise:BAAALgAFFAEJAgABLgAFFAcJIwAeAHsNAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAACLgAFFH8YAAICAAUJ+xhKPAA0AQACAAUJ+xhKPAA0AQAuAAQKfzYAAgIACQmxIDwWAKMCAAIACQmxIDwWAKMCAAAA.',
Em='Embertal:BAABLgAECn8XAAMdAAcJ2g7QBAAgAQAdAAcJ2g7QBAAgAQAfAAEJAAANMAAAAAAAAA==.Emvoi:BAAALgADCgUJBQAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgcJDgAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.Enzo:BAAALgAECgEJAQAAAA==.',
Eq='Eqlipse:BAAALgAECgMJAwAAAA==.',
Ev='Evién:BAABLgAECn8UAAMgAAYJNxZEOQBrAQAgAAYJNxZEOQBrAQALAAUJthG7hADUAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Executè:BAAALgAECgEJAgABLgAFFAQJDQAZAKQYAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.Fatpanda:BAAALgAECgEJAQAAAA==.Faustus:BAAALgADCgMJAwAAAA==.',
Fe='Feleså:BAAALgAECggJDwABLgAFFAYJFAADAIcgAA==.Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8pAAIFAAgJ8gcErgAiAQAFAAgJ8gcErgAiAQAAAA==.',
Fi='Fiammetta:BAECLgAFFH8WAAIhAAcJWx+kBgDfAQAhAAcJWx+kBgDfAQAuAAQKfxgAAiEACQlrI3gNABMCACEACQlrI3gNABMCAAEuAAUUCQkfAAoAPSIA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJEgAGAAAAAA==.Finke:BAABLgAECn8fAAITAAgJ4BvrZwAHAgATAAgJ4BvrZwAHAgAAAA==.Fishmärket:BAABLgAECn8iAAIMAAkJYA8YDwC/AQAMAAkJYA8YDwC/AQAAAA==.',
Fl='Flickerbeat:BAAALgAECgYJDQAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Free:BAABLgAECn9VAAMXAAkJiyCYAwAKAwAXAAkJiyCYAwAKAwAdAAUJSB5zPQA0AQAAAA==.Frostie:BAABLgAFFH8PAAMDAAgJ/BQXCAA3AgADAAgJ/BQXCAA3AgAaAAEJAADrTQAAAAAAAA==.Frís:BAAALgAECggJEwABLgAFFAQJFwAaACscAA==.',
Fu='Furryfist:BAAALgAECgEJAgAAAA==.',
Ga='Galarine:BAABLgAECn8sAAIPAAkJiRgwKQA3AgAPAAkJiRgwKQA3AgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gd='Gdizz:BAAALgAECgkJAgAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAFFAUJDgAOAOobAA==.Gilrathor:BAAALgAECgkJEQAAAA==.Gizzlit:BAABLgAECn8tAAIMAAkJzxukBQCHAgAMAAkJzxukBQCHAgAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAFFAEJAgAAAA==.Gofetch:BAABLgAECn8hAAICAAkJsBvtLAApAgACAAkJsBvtLAApAgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAGAAAAAA==.',
Gr='Grandgoop:BAAALgAECgMJAwAAAA==.Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8oAAMCAAkJsx54GgCHAgACAAkJsx54GgCHAgAiAAUJ+hL5GAA/AQAAAA==.',
Gs='Gson:BAAALgAECgcJBwAAAA==.',
Gu='Guppy:BAAALgAECgcJDAAAAA==.Gutcassidy:BAAALgAECgYJCwAAAA==.Guttss:BAAALgAECgEJAQAAAA==.',
Ha='Hac:BAAALgAECgcJEQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJEQAGAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harps:BAAALgAECgUJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAGAAAAAA==.',
He='Healingkiss:BAABLgAECn8qAAIbAAkJPQKlQQDlAAAbAAkJPQKlQQDlAAAAAA==.Heatup:BAABLgAECn8aAAITAAgJfiMzFQApAwATAAgJfiMzFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Hi='Hikingboots:BAAALgAECgYJDAAAAA==.',
Ho='Hollypallz:BAAALgADCgEJAQAAAA==.Holymages:BAABLgAECn8kAAITAAkJxRwVLgBgAgATAAkJxRwVLgBgAgAAAA==.Holymonka:BAAALgAECgEJAQAAAA==.Homtardy:BAABLgAECn8ZAAIjAAcJRh4zEgAVAgAjAAcJRh4zEgAVAgAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.Hunkomonk:BAAALgAECgcJCAABLgAECgkJJwAFABcgAA==.Hunt:BAAALgAFFAIJBAAAAA==.',
Ic='Ickarus:BAAALgAECgQJBQAAAA==.',
Ik='Iknowaguy:BAAALgADCgkJEwABLgAECgkJSgAZAFQUAA==.',
Il='Ilyanna:BAABLgAECn8lAAMWAAkJgh3rBQAkAgAWAAkJgh3rBQAkAgAPAAEJXxDXCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8qAAQiAAkJ5RoJAgAuAgAiAAcJYBsJAgAuAgAkAAYJARqKBgC3AQACAAQJXBvARgBqAAAuAAQKfyUAAiQACAmyJDgGADkDACQACAmyJDgGADkDAAAA.Imabadshot:BAAALgAECgEJAgAAAA==.Imscary:BAAALgAECgQJBQAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgcJDgAGAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgkJSgAZAFQUAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.Jenyaa:BAAALgAECgMJAwAAAA==.',
Jh='Jhalse:BAAALgAECgQJBAAAAA==.Jhoppss:BAABLgAECn8WAAMfAAYJlx1rDwDkAQAfAAYJlx1rDwDkAQAdAAQJjQ8ecgCGAAAAAA==.',
Ji='Jiinxx:BAAALgAECgQJCAAAAA==.Jilliebean:BAAALgAECgIJBAAAAA==.Jillià:BAAALgAFFAIJAwAAAA==.Jimpossible:BAAALgAECgYJCgAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Kallisto:BAAALgAFFAMJAwABLgAFFAYJBwADALkTAA==.Karls:BAAALgAECgYJDgAAAA==.',
Ke='Keez:BAAALgAECgcJDwAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kej:BAAALgAECgIJAgAAAA==.Kerrigan:BAACLgAFFH8jAAIeAAcJew3IJgCRAQAeAAcJew3IJgCRAQAuAAQKfzMAAh4ACQn4HtYWAI4CAB4ACQn4HtYWAI4CAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJHAANAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8lAAMEAAkJaBd5JAAoAgAEAAkJaBd5JAAoAgAlAAMJgCFZAwAfAQAAAA==.Kozand:BAAALgAECgcJEAABLgAECgcJGgAMABQQAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgAECgMJBQAAAA==.',
Ky='Kyirr:BAABLgAECn8fAAMfAAkJgxlNDAAWAgAfAAcJQRpNDAAWAgAdAAUJFxiFSAAJAQAAAA==.Kyralen:BAABLgAECn8cAAMNAAYJHSPEGABMAgANAAYJHSPEGABMAgAFAAIJVxMPPgFuAAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAIMAAkJiRVRCgAsAgAMAAkJiRVRCgAsAgAAAA==.',
Le='Lexxi:BAAALgAFFAEJAQAAAA==.',
Li='Lilchithead:BAAALgAECgcJDwAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8fAAIKAAkJPSL2AQBEAgAKAAkJPSL2AQBEAgAuAAQKfy0AAgoACQnqJSUBAK0DAAoACQnqJSUBAK0DAAAA.Lividea:BAABLgAECn8pAAIDAAcJygbzwgD6AAADAAcJygbzwgD6AAAAAA==.Livinglover:BAAALgADCgUJAwAAAA==.',
Ll='Llela:BAAALgAECgcJCAAAAA==.Llynryn:BAABLgAECn8ZAAIRAAgJhBCEMwBLAQARAAgJhBCEMwBLAQAAAA==.',
Lo='Locktua:BAAALgAECgcJCQAAAA==.',
Ly='Lympha:BAABLgAFFH8JAAMLAAMJ1x3iNgAHAQALAAMJ1x3iNgAHAQAMAAEJowEhHgAvAAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAgJHgAeAPQeAA==.Magicmanzz:BAABLgAECn8xAAITAAkJsBFWBgDFAQATAAkJsBFWBgDFAQAAAA==.Magnifuso:BAAALgAECggJEgAAAA==.Maguapa:BAAALgAECgQJBwAAAA==.Malgata:BAAALgADCgkJFgAAAA==.Margarita:BAAALgAECgUJCwAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8IAAINAAMJIRccMQCvAAANAAMJIRccMQCvAAAuAAQKfy4AAw0ACQnbH9wZADcCAA0ABwkNH9wZADcCAAUACAntGVpIAO0BAAAA.',
Mc='Mcplucky:BAABLgAECn8eAAIkAAYJnwf9AwCoAAAkAAYJnwf9AwCoAAAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Miguelito:BAAALgAECgEJAQABLgAECgcJFwAfALwcAA==.Mikio:BAABLgAECn8hAAIBAAkJdRDjIQC6AQABAAkJdRDjIQC6AQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8uAAIbAAkJLRyHCwCuAgAbAAkJLRyHCwCuAgAAAA==.Misho:BAAALgAECgMJAwAAAA==.',
Mo='Moardottz:BAABLgAECn8dAAIPAAYJPxW+cgB5AQAPAAYJPxW+cgB5AQABLgAECgUJBQAGAAAAAA==.Moiryn:BAACLgAFFH8UAAMLAAgJlhFJHACKAQALAAgJlhFJHACKAQAgAAIJnwUOXAAzAAAuAAQKfy8AAwsACQmJHZ4ZAEoCAAsACAl+HJ4ZAEoCACAAAwlhGKoMAKsAAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Nainaii:BAAALgAFFAEJAQAAAA==.Nalthexon:BAAALgAECgEJAQAAAA==.Naturals:BAAALgAECgEJAwAAAA==.Navidruid:BAABLgAFFH8IAAIlAAQJLwgMEgCpAAAlAAQJLwgMEgCpAAABLgAFFAgJKgAXADQQAA==.Navillus:BAACLgAFFH8qAAMXAAgJNBBtCAAqAgAXAAgJNBBtCAAqAgAfAAEJwRcmBQBMAAAuAAQKf0oAAxcACQnvFMEMAGoCABcACQnvFMEMAGoCAB8ACAkTItgDAEsCAAAA.',
No='Norasoul:BAABLgAECn8wAAMeAAkJ5huiGQB7AgAeAAkJ5huiGQB7AgAmAAcJ2BQUDgBxAQAAAA==.Nowyourdead:BAAALgAECgQJBQAAAA==.',
['Nð']='Nðx:BAAALgAECggJDgAAAA==.',
Oa='Oakensoul:BAAALgAECgcJCAABLgAECgkJJwAFABcgAA==.',
Og='Ogron:BAACLgAFFH8fAAMLAAUJOib4FgCuAQALAAUJOib4FgCuAQAgAAIJ2xwRHACUAAAuAAQKfzkAAyAACQl8JRAEAF4DACAACQl8JRAEAF4DAAsAAwknIKyXAKUAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgAECgYJBgAAAA==.',
Op='Ophindis:BAAALgAECgcJDwAAAA==.',
Or='Orthos:BAACLgAFFH8UAAIDAAYJhyBsGQBjAQADAAYJhyBsGQBjAQAuAAQKfzcAAgMACQlXJdgDAGQDAAMACQlXJdgDAGQDAAAA.Orwenya:BAABLgAECn8aAAIMAAcJFBC5HQANAQAMAAcJFBC5HQANAQAAAA==.',
Os='Osten:BAABLgAECn8cAAINAAkJRBDHKADGAQANAAkJRBDHKADGAQAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAGAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phobos:BAAALgADCgIJAgAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Pl='Plâgue:BAAALgAECgQJBAAAAA==.',
Po='Porkit:BAAALgAFFAIJAwAAAA==.',
Pu='Putemuptoo:BAAALgAECgcJBwAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAABLgAFFH8KAAMnAAMJ3RO1EwDaAAAnAAMJ3RO1EwDaAAAoAAIJeBfCMACcAAAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgcJDgAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Reddacted:BAAALgADCgcJDAAAAA==.Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8oAAIBAAkJQxvAAQAAAgABAAkJQxvAAQAAAgAuAAQKfzsAAgEACQnBJt0AAH8DAAEACQnBJt0AAH8DAAAA.Respect:BAAALgAECgIJAgAAAA==.Rexam:BAAALgAECgIJAgABLgAECgcJGAAeAEUjAA==.Rexsouls:BAAALgAFFAEJAQAAAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAABLgAECn8sAAIjAAkJrxraCgB2AgAjAAkJrxraCgB2AgAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAABLgAECn9FAAIjAAkJnCGoAwAMAwAjAAkJnCGoAwAMAwAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8bAAMVAAYJ5A8zCQBZAQAVAAYJ5A8zCQBZAQATAAYJowmu1QDpAAAAAA==.',
['Rè']='Rènza:BAABLgAFFH8IAAIZAAMJJxiKDgCfAAAZAAMJJxiKDgCfAAAAAA==.',
Sa='Saelybrosa:BAAALgAECggJDgAAAA==.Salphir:BAAALgAECgUJCQABLgAECgcJGgAMABQQAA==.Samsara:BAAALgAECgQJCgAAAA==.Sanguineous:BAAALgAECgIJAgABLgAFFAUJCgAFAAIKAA==.Saphyr:BAEBLgAFFH8IAAIaAAUJbCCyEQBuAQAaAAUJbCCyEQBuAQABLgAFFAkJHwAKAD0iAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Senniel:BAAALgAECgYJEwAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabalaba:BAAALgAECgEJAQAAAA==.Shabit:BAAALgADCgUJBgABLgAFFAIJAwAGAAAAAA==.Shadda:BAABLgAECn8bAAIOAAcJXhfjAwBaAQAOAAcJXhfjAwBaAQAAAA==.Shadorae:BAAALgADCgcJBwABLgAECgYJEQAGAAAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8HAAIgAAIJXg0bSABuAAAgAAIJXg0bSABuAAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECgkJGwAYAKIQAA==.Sheesh:BAAALgAECgYJCgAAAA==.Shinru:BAABLgAECn8dAAMNAAkJnhdLBABpAQANAAkJnhdLBABpAQAFAAYJlh6BmgBAAQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAABLgAFFH8XAAIaAAQJKxyQCQAnAQAaAAQJKxyQCQAnAQAAAA==.',
Si='Sickdayze:BAABLgAECn8fAAINAAkJwCA4DQC+AgANAAkJwCA4DQC+AgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sikkunt:BAAALgAECgEJAwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAGAAAAAA==.Skyrain:BAAALgAECgUJBgAAAA==.',
Sl='Slootin:BAAALgAECgEJAgAAAA==.Slyxxar:BAACLgAFFH8OAAILAAQJwQruRwDNAAALAAQJwQruRwDNAAAuAAQKfxwABAwACAkaF9sRAJcBAAwACAkaF9sRAJcBACAABgnBEexRAP8AAAsAAQl4AVWrAB8AAAAA.',
Sm='Smarc:BAABLgAECn9FAAIiAAkJcR9aBADpAgAiAAkJcR9aBADpAgAAAA==.Smashtokhan:BAAALgAECgUJCgAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8aAAIEAAgJtBrXBADLAgAEAAgJtBrXBADLAgAuAAQKfxgAAwQABwlsIlgnABkCAAQABwlsIlgnABkCAAEAAgmjFq6GADwAAAAA.Sophie:BAACLgAFFH8PAAMFAAQJwCF+JwBsAQAFAAQJwCF+JwBsAQANAAEJ2w3qSgAzAAAuAAQKfxwAAwUACAmwHOs7ADQCAAUACAmwHOs7ADQCAA0ABgkuDlNKAE8BAAEuAAUUCAkaAAQAtBoA.Sophievokie:BAAALgAFFAQJBAABLgAFFAgJGgAEALQaAA==.Sophisticate:BAABLgAFFH8QAAIiAAQJnB5HDgBTAQAiAAQJnB5HDgBTAQABLgAFFAgJGgAEALQaAA==.Sophiz:BAAALgAECgYJDwABLgAFFAgJGgAEALQaAA==.Sophlax:BAACLgAFFH8TAAIbAAUJLySjAQCpAQAbAAUJLySjAQCpAQAuAAQKfxkAAhsACQnLIA8EABQDABsACQnLIA8EABQDAAEuAAUUCAkaAAQAtBoA.Sophs:BAACLgAFFH8IAAILAAQJkBgUMwAWAQALAAQJkBgUMwAWAQAuAAQKfxUAAwsABgnGHK5VAF8BAAsABgnGHK5VAF8BACAABQmpEslaANkAAAEuAAUUCAkaAAQAtBoA.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAACLgAFFH8IAAIOAAMJWB/ODwAKAQAOAAMJWB/ODwAKAQAuAAQKfzAAAg4ACQkmIeUCAAUDAA4ACQkmIeUCAAUDAAAA.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAMJAwAGAAAAAA==.',
Sp='Spankgg:BAAALgAECgQJBAAAAA==.Spicynoodle:BAABLgAECn8WAAICAAkJShXZLwAdAgACAAkJShXZLwAdAgAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAACLgAFFH8GAAIRAAIJMCBHGABaAAARAAIJMCBHGABaAAAuAAQKfx0AAhEABQmLJcIlAJ0BABEABQmLJcIlAJ0BAAAA.',
Sq='Squattinchop:BAABLgAECn8eAAIIAAYJQiH3FQA6AgAIAAYJQiH3FQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJHgAIAEIhAA==.',
St='Stacyguns:BAAALgAECgMJBAABLgAECgcJCgAGAAAAAA==.Stian:BAAALgAECgUJBQAAAA==.Stiffcrit:BAAALgAECgkJBwAAAA==.Stinkydh:BAABLgAECn8SAAIeAAYJMhFNcwBLAQAeAAYJMhFNcwBLAQAAAA==.Stryx:BAAALgADCgcJBwABLgAECgcJEgAGAAAAAA==.',
Su='Suji:BAABLgAECn8iAAIDAAkJXiAIFADQAgADAAkJXiAIFADQAgAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAGAAAAAA==.Supabird:BAAALgAECgQJBAAAAA==.Supergogeta:BAABLgAECn8yAAQEAAkJ3R9yDgDGAgAEAAgJsyByDgDGAgABAAIJkA82bwBpAAAOAAEJiQQ9NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgkJEQAAAA==.Synistër:BAAALgAECgUJBgAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôcôld:BAAALgADCgQJBAAAAA==.',
Ta='Takoda:BAAALgAECggJEAAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAABLgAECn8VAAICAAkJMwj5YgCAAQACAAkJMwj5YgCAAQAAAA==.Tandaris:BAAALgADCgYJBgAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tarkuun:BAAALgAECgkJCAAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBwAAAA==.',
Th='Thorish:BAABLgAECn8kAAIYAAkJ5CGrAwDbAgAYAAkJ5CGrAwDbAgAAAA==.',
Ti='Tiddyweaver:BAABLgAECn8XAAMJAAgJGyP+BwAdAwAJAAgJGyP+BwAdAwAIAAIJjxHCdwBhAAABLgAECgkJIAAXAEcfAA==.Timbit:BAABLgAECn8jAAIIAAgJfQmhMwBTAQAIAAgJfQmhMwBTAQAAAA==.Tinfoiltotem:BAAALgADCgYJCgAAAA==.Tinybubbles:BAABLgAECn8oAAMLAAkJbRQRSACOAQALAAkJbRQRSACOAQAgAAQJKw2XXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJEwAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgcJDwAGAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8gAAMcAAkJGRlXGQAHAgAcAAkJGRlXGQAHAgARAAEJvwejkAAqAAAAAA==.',
Tr='Trav:BAABLgAFFH8FAAIDAAQJLRKIawAkAQADAAQJLRKIawAkAQAAAA==.Trooth:BAAALgADCgYJBgABLgAECgUJDAAGAAAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgYJCgAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgkJCwAAAA==.',
Ty='Tyranis:BAEALgAECggJDgAAAA==.Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAABLgAECn8XAAMXAAkJFw0DEgCoAQAXAAkJFw0DEgCoAQAdAAYJRAh9XwC8AAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Uw='Uwusev:BAAALgAECgIJAgAAAA==.',
Va='Vael:BAABLgAECn8iAAIeAAgJRxKDVgCDAQAeAAgJRxKDVgCDAQAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8pAAMaAAkJuBSAJwAYAQADAAcJ9RbEngAuAQAaAAgJ+g6AJwAYAQAAAA==.Valexisea:BAAALgAECgEJAQABLgAFFAYJFAADAIcgAA==.Valériana:BAAALgADCgMJAwAAAA==.',
Ve='Vee:BAABLgAECn8fAAMnAAgJ+yPlEgBbAgAnAAgJ+yPlEgBbAgAoAAEJnBXmOwBBAAAAAA==.Veyla:BAEALgADCgcJDgABLgAECgYJBwAGAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAACLgAFFH8HAAIDAAQJVQk+ggADAQADAAQJVQk+ggADAQAuAAQKfyQAAgMACQlzFoqAAGIBAAMACQlzFoqAAGIBAAAA.',
Wa='Warkdom:BAAALgAECgUJCAAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAACLgAFFH8PAAIhAAMJViR8EAAsAQAhAAMJViR8EAAsAQAuAAQKfyYAAiEACAlpJMcFALYCACEACAlpJMcFALYCAAAA.',
Wh='Wheelchair:BAEALgADCgYJBgABLgAECgYJBwAGAAAAAA==.',
Wi='Wickeddemon:BAABLgAECn8lAAIZAAkJzBIhGADCAQAZAAkJzBIhGADCAQAAAA==.Wildcanadian:BAAALgAECgIJAgAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
Wk='Wk:BAAALgAECgEJAQAAAA==.',
Wo='Wokstar:BAAALgAECgEJAgAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAINAAkJxhT0KgC5AQANAAkJxhT0KgC5AQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJJQAEAGgXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAACLgAFFH8PAAIeAAQJqxO/RwAQAQAeAAQJqxO/RwAQAQAuAAQKfyoAAh4ACQkYIDsRALgCAB4ACQkYIDsRALgCAAAA.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8dAAIlAAcJwRsSAQCnAQAlAAcJwRsSAQCnAQAuAAQKfxYAAiUACAnDInIEANUCACUACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.Yrel:BAAALgAECgQJBAABLgAECgcJGgAMABQQAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zacariana:BAAALgADCgcJBwAAAA==.Zaftenpuff:BAAALgAECgQJBAAAAA==.Zandashami:BAAALgAECggJCAAAAA==.Zarya:BAABLgAECn8cAAQJAAkJWB8OAgBRAgAJAAcJ5x0OAgBRAgAIAAcJQhusHgC4AQAKAAEJWCVqdgBoAAAAAA==.',
Ze='Zelgie:BAABLgAECn8rAAMYAAkJ7BExEwCXAQAYAAkJ7BExEwCXAQANAAUJ6BDnUQDxAAAAAA==.',
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
