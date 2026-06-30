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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Rogue-Outlaw','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Paladin-Retribution','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Druid-Guardian','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Mage-Frost','Mage-Fire','Mage-Arcane','Evoker-Preservation','Paladin-Protection','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Evoker-Augmentation','DemonHunter-Devourer','Evoker-Devastation','Shaman-Elemental','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Warlock-Affliction','Hunter-Marksmanship','Druid-Feral','DemonHunter-Vengeance','Warrior-Arms','Warrior-Fury',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAYJEQABAF0iAA==.',
Ab='Abadizzo:BAAALgAECgcJDwAAAA==.Abadizzoo:BAABLgAECn8qAAICAAkJtyEJFgCkAgACAAkJtyEJFgCkAgAAAA==.Abilities:BAAALgAECgYJEgAAAA==.',
Ac='Ace:BAAALgAFFAEJAQAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAABLgAECn8VAAICAAYJIhXEeQBMAQACAAYJIhXEeQBMAQABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8sAAIEAAkJUiTUBABAAwAEAAkJUiTUBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAFFAIJAgAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airleara:BAAALgAECgcJDAAAAA==.Airwrecka:BAACLgAFFH8IAAIBAAMJ3RTDLwDFAAABAAMJ3RTDLwDFAAAuAAQKfzEAAgEACQnEHqUMAI0CAAEACQnEHqUMAI0CAAAA.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.Aite:BAAALgAECgIJAgAAAA==.',
Al='Alexian:BAABLgAECn8bAAIGAAkJsRVzBQAPAgAGAAkJsRVzBQAPAgAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAABLgAECn8bAAICAAgJ5RVtUACxAQACAAgJ5RVtUACxAQAAAA==.',
Am='Amadk:BAAALgAECgkJAQAAAA==.Amebeliever:BAABLgAECn8fAAQHAAgJiB8ZFQBDAgAHAAcJuB4ZFQBDAgAIAAcJAgi/NwAMAQAJAAQJ/gmOZgB9AAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgkJFgAAAA==.',
Ar='Arahgon:BAEBLgAECn8iAAIKAAkJURtuIQCBAgAKAAkJURtuIQCBAgABLgAECgYJCQAFAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asphodelos:BAAALgAECgYJDQABLgAFFAUJEwADADcfAA==.Asukà:BAABLgAECn8/AAMLAAkJjxe/HQBfAgALAAkJjxe/HQBfAgAMAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAgAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJHAANAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgAECgYJBgABLgAECgYJGAAMAAkRAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAACLgAFFH8NAAIOAAQJ6hv2BADsAAAOAAQJ6hv2BADsAAAuAAQKfxYAAg4ABwn8HzANAA8CAA4ABwn8HzANAA8CAAAA.Beerbutt:BAAALgAECgEJBAAAAA==.Bellarg:BAABLgAECn83AAMPAAkJAxosKQA3AgAPAAkJAxosKQA3AgAQAAMJ3wetSACUAAAAAA==.Belobog:BAAALgAECgUJDQABLgAECggJHAADALsPAA==.Belyn:BAABLgAECn8YAAINAAgJARTlNAB+AQANAAgJARTlNAB+AQAAAA==.Benmage:BAAALgAECgUJBQAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bifesor:BAAALgAFFAMJAwAAAA==.Bigfaust:BAABLgAECn8YAAQJAAcJqB+7LABVAQAJAAUJpx+7LABVAQAIAAUJABu/LgBDAQAHAAIJRR8IUwDFAAAAAA==.',
Bl='Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAABLgAECn8UAAIKAAgJCghTrwAgAQAKAAgJCghTrwAgAQAAAA==.Bluespider:BAAALgAECgYJCQAAAA==.',
Bo='Bondrewd:BAAALgAECgEJAgABLgAFFAIJBgARADAgAA==.Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAACLgAFFH8IAAIHAAUJtxOnFwAFAQAHAAUJtxOnFwAFAQAuAAQKfxYAAwgABwmlGuwWAAoCAAgABwmlGuwWAAoCAAcABAkGI5k1ACwBAAEuAAUUCAkaAAQAtBoA.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Brolich:BAAALgAECggJEgABLgAECgQJBwAFAAAAAA==.Broo:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJEgAAAA==.Calculusx:BAABLgAECn8tAAISAAkJUCNCAQAHAwASAAkJUCNCAQAHAwAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8kAAQTAAYJ+RtBBAAtAgATAAYJrhtBBAAtAgAUAAIJfBO3AQCgAAAVAAIJmRt0AwCXAAAuAAQKfzcABBMACQkrJgsFALEDABMACQn7JQsFALEDABQACQnjIeECAAUCABUAAwnIIi0MALwAAAAA.',
Ch='Champu:BAAALgAECgEJAQAAAA==.Chaoticx:BAAALgAECgQJEQAAAA==.Charlotte:BAAALgAECgcJEwAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn88AAQJAAkJ6yALBQDxAgAJAAkJ6yALBQDxAgAHAAMJfhQSagCAAAAIAAIJqwiMrABGAAABLgAFFAQJDQAOAOobAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAFAAAAAA==.',
Ci='Cinderion:BAAALgADCgUJBQABLgAECgkJUwAWAIsgAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAABLgAECn8XAAIXAAgJLhHLAgDvAAAXAAgJLhHLAgDvAAAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgTSQAYAgADAAgJ1BgTSQAYAgABLgAECgkJCQAFAAAAAA==.Combatboots:BAABLgAECn9KAAIYAAkJVBTTFADpAQAYAAkJVBTTFADpAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMJAAYJ2Rs0LwCaAQAJAAUJGhw0LwCaAQAHAAYJsRShNwBAAQAAAA==.Darilol:BAAALgAECgUJCgABLgAECgYJGAAMAAkRAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn84AAIZAAkJtCICBAD5AgAZAAkJtCICBAD5AgAAAA==.Debra:BAACLgAFFH8GAAIYAAMJlAtRHQC4AAAYAAMJlAtRHQC4AAAuAAQKfy0AAhgACQnCGw8QACYCABgACQnCGw8QACYCAAAA.Debz:BAAALgAECgcJCAAAAA==.Deegee:BAABLgAECn8dAAMaAAcJbSIvDQCTAgAaAAcJbSIvDQCTAgARAAYJvBjTJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAgAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJBQAAAA==.Demize:BAAALgAECgkJCAAAAA==.Demonflame:BAABLgAECn8nAAIQAAkJDxbXBgDwAQAQAAkJDxbXBgDwAQAAAA==.Demíze:BAAALgAECgQJBQAAAA==.Deshield:BAAALgAFFAQJBAABLgAFFAUJHwALADomAA==.Deus:BAABLgAECn8bAAITAAkJexA2bgCeAQATAAkJexA2bgCeAQAAAA==.Dewry:BAABLgAECn8eAAMRAAcJ9By8AQCaAQARAAYJHiC8AQCaAQAbAAcJQhC2MQBUAQAAAA==.',
Dh='Dhudamuthi:BAACLgAFFH8GAAIJAAMJmBnWGgCUAAAJAAMJmBnWGgCUAAAuAAQKfzsAAgkACQmfJNECACsDAAkACQmfJNECACsDAAAA.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwoof:BAAALgAECgYJDAAAAA==.Dizzo:BAAALgAECgkJBQAAAA==.',
Do='Donnajuan:BAABLgAECn86AAMNAAkJShwSCwDcAgANAAkJShwSCwDcAgAKAAEJ2QPovwEkAAAAAA==.Dornath:BAABLgAECn9TAAIKAAgJvxLMBgBJAQAKAAgJvxLMBgBJAQAAAA==.',
Dr='Draaxelro:BAABLgAECn8cAAICAAkJ9RDDWQCXAQACAAkJ9RDDWQCXAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAUJHwALADomAA==.Dragontiddys:BAABLgAECn8fAAMWAAgJRx9cBQDBAgAWAAgJRx9cBQDBAgAcAAEJJBaLjABCAAAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAFAAAAAA==.Drim:BAAALgAECgEJAQAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Eldread:BAAALgADCgEJAQAAAA==.Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8xAAIRAAkJxwoDLAB1AQARAAkJxwoDLAB1AQAAAA==.Elinalise:BAAALgAFFAEJAgABLgAFFAcJIwAdAHsNAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAACLgAFFH8TAAICAAQJ+xh4FwDmAAACAAQJ+xh4FwDmAAAuAAQKfzYAAgIACQmxIDwWAKMCAAIACQmxIDwWAKMCAAAA.',
Em='Embertal:BAABLgAECn8XAAMcAAcJyA5XAgA3AQAcAAcJyA5XAgA3AQAeAAEJAAANMAAAAAAAAA==.Emvoi:BAAALgADCgUJBQAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgcJDgAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.Enzo:BAAALgAECgEJAQAAAA==.',
Eq='Eqlipse:BAAALgAECgMJAwAAAA==.',
Ev='Evién:BAABLgAECn8UAAMfAAYJNxZEOQBrAQAfAAYJNxZEOQBrAQALAAUJthG7hADUAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Executè:BAAALgAECgEJAgABLgAFFAMJDAAYAOcbAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.Fatpanda:BAAALgAECgEJAQAAAA==.Faustus:BAAALgADCgMJAwAAAA==.',
Fe='Feleså:BAAALgAECggJDwABLgAFFAUJEwADADcfAA==.Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8pAAIKAAgJ8gcErgAiAQAKAAgJ8gcErgAiAQAAAA==.',
Fi='Fiammetta:BAECLgAFFH8WAAIgAAcJcx+kBgDfAQAgAAcJcx+kBgDfAQAuAAQKfxgAAiAACQlrI3gNABMCACAACQlrI3gNABMCAAEuAAUUBwkXAAkAmyEA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJEgAFAAAAAA==.Finke:BAABLgAECn8dAAITAAcJyx3rZwAHAgATAAcJyx3rZwAHAgAAAA==.Fishmärket:BAABLgAECn8iAAIMAAkJYA8YDwC/AQAMAAkJYA8YDwC/AQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJCAAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Frostie:BAABLgAFFH8GAAMZAAMJgwvrTQAAAAADAAIJgwvj8wB5AAAZAAEJAADrTQAAAAABLgAFFAYJFAAKABcWAA==.Frís:BAAALgAECggJEwABLgAFFAQJFwAZACscAA==.',
Fu='Furryfist:BAAALgAECgEJAQAAAA==.',
Ga='Galarine:BAABLgAECn8sAAIPAAkJiRgwKQA3AgAPAAkJiRgwKQA3AgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gd='Gdizz:BAAALgAECgkJAgAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAFFAQJDQAOAOobAA==.Gilrathor:BAAALgAECggJEAAAAA==.Gizzlit:BAABLgAECn8tAAIMAAkJzxukBQCHAgAMAAkJzxukBQCHAgAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAFFAEJAQAAAA==.Gofetch:BAABLgAECn8hAAICAAkJsBvtLAApAgACAAkJsBvtLAApAgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAFAAAAAA==.',
Gr='Grandgoop:BAAALgAECgMJAwAAAA==.Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8oAAMCAAkJsx54GgCHAgACAAkJsx54GgCHAgAhAAUJ+hL5GAA/AQAAAA==.',
Gs='Gson:BAAALgAECgcJBwAAAA==.',
Gu='Guppy:BAAALgAECgcJDAAAAA==.Gutcassidy:BAAALgAECgYJCwAAAA==.Guttss:BAAALgAECgEJAQAAAA==.',
Ha='Hac:BAAALgAECgcJEQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harps:BAAALgAECgUJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAFAAAAAA==.',
He='Healingkiss:BAABLgAECn8qAAIaAAkJPQKlQQDlAAAaAAkJPQKlQQDlAAAAAA==.Heatup:BAABLgAECn8aAAITAAgJfiMzFQApAwATAAgJfiMzFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Hi='Hikingboots:BAAALgADCggJCAAAAA==.',
Ho='Hollypallz:BAAALgADCgEJAQAAAA==.Holymages:BAABLgAECn8kAAITAAkJxRwVLgBgAgATAAkJxRwVLgBgAgAAAA==.Holymonka:BAAALgAECgEJAQAAAA==.Homtardy:BAABLgAECn8ZAAIiAAcJRh4zEgAVAgAiAAcJRh4zEgAVAgAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.Hunkomonk:BAAALgAECgcJCAABLgAECgkJJwAKABcgAA==.Hunt:BAAALgAFFAEJAQAAAA==.',
Ic='Ickarus:BAAALgAECgQJBQAAAA==.',
Ik='Iknowaguy:BAAALgADCgkJDwABLgAECgkJSgAYAFQUAA==.',
Il='Ilyanna:BAABLgAECn8lAAMjAAkJgh3rBQAkAgAjAAkJgh3rBQAkAgAPAAEJXxDXCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8mAAQhAAkJXxgJAgAuAgAhAAcJfxkJAgAuAgAkAAYJARqKBgC3AQACAAQJYBhbLQBoAAAuAAQKfyUAAiQACAmyJDgGADkDACQACAmyJDgGADkDAAAA.Imabadshot:BAAALgAECgEJAQAAAA==.Imscary:BAAALgAECgQJBQAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgcJDgAFAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgkJSgAYAFQUAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.Jenyaa:BAAALgAECgMJAwAAAA==.',
Jh='Jhalse:BAAALgAECgQJBAAAAA==.Jhoppss:BAABLgAECn8WAAMeAAYJlx1rDwDkAQAeAAYJlx1rDwDkAQAcAAQJjQ8ecgCGAAAAAA==.',
Ji='Jiinxx:BAAALgAECgQJCAAAAA==.Jilliebean:BAAALgAECgEJAQAAAA==.Jillià:BAAALgAFFAIJAwAAAA==.Jimpossible:BAAALgAECgYJCgAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Karls:BAAALgAECgYJDgAAAA==.',
Ke='Keez:BAAALgAECgcJDwAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kej:BAAALgAECgIJAgAAAA==.Kerafyrm:BAABLgAECn9TAAMWAAkJiyCYAwAKAwAWAAkJiyCYAwAKAwAcAAUJSB5zPQA0AQAAAA==.Kerrigan:BAACLgAFFH8jAAIdAAcJew3IJgCRAQAdAAcJew3IJgCRAQAuAAQKfzMAAh0ACQn4HtYWAI4CAB0ACQn4HtYWAI4CAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJHAANAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8iAAMEAAkJaBd5JAAoAgAEAAkJaBd5JAAoAgAlAAEJPRBUMQA+AAAAAA==.Kozand:BAAALgAECgcJDgABLgAECgYJGAAMAAkRAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgAECgEJAQAAAA==.',
Ky='Kyirr:BAABLgAECn8fAAMeAAkJgxlNDAAWAgAeAAcJQRpNDAAWAgAcAAUJFxiFSAAJAQAAAA==.Kyralen:BAABLgAECn8cAAMNAAYJHSPEGABMAgANAAYJHSPEGABMAgAKAAIJVxMPPgFuAAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAIMAAkJiRVRCgAsAgAMAAkJiRVRCgAsAgAAAA==.',
Li='Lilchithead:BAAALgAECgcJDwAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8XAAIJAAcJmyGEBgAqAgAJAAcJmyGEBgAqAgAuAAQKfy0AAgkACQnqJSUBAK0DAAkACQnqJSUBAK0DAAAA.Lividea:BAABLgAECn8pAAIDAAcJygbzwgD6AAADAAcJygbzwgD6AAAAAA==.Livinglover:BAAALgADCgUJAwAAAA==.',
Ll='Llela:BAAALgAECgcJCAAAAA==.Llynryn:BAABLgAECn8YAAIRAAgJhBCEMwBLAQARAAgJhBCEMwBLAQAAAA==.',
Lo='Locktua:BAAALgAECgcJCQAAAA==.',
Ly='Lympha:BAABLgAFFH8JAAMLAAMJ1x3iNgAHAQALAAMJ1x3iNgAHAQAMAAEJowEhHgAvAAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAgJGgAdACEbAA==.Magicmanzz:BAABLgAECn8iAAITAAkJdA6CcwCTAQATAAkJdA6CcwCTAQAAAA==.Magnifuso:BAAALgAECggJEgAAAA==.Maguapa:BAAALgAECgQJBwAAAA==.Malgata:BAAALgADCgkJFgAAAA==.Margarita:BAAALgAECgUJCwAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8IAAINAAMJIRccMQCvAAANAAMJIRccMQCvAAAuAAQKfy4AAw0ACQnbH9wZADcCAA0ABwkNH9wZADcCAAoACAntGVpIAO0BAAAA.',
Mc='Mcplucky:BAABLgAECn8XAAIkAAYJ2AQyIgCgAAAkAAYJ2AQyIgCgAAAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Miguelito:BAAALgAECgEJAQABLgAECgcJFwAeALwcAA==.Mikio:BAABLgAECn8hAAIBAAkJdRDjIQC6AQABAAkJdRDjIQC6AQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8uAAIaAAkJLRyHCwCuAgAaAAkJLRyHCwCuAgAAAA==.Misho:BAAALgAECgMJAwAAAA==.',
Mo='Moardottz:BAABLgAECn8dAAIPAAYJPxW+cgB5AQAPAAYJPxW+cgB5AQABLgAECgUJBQAFAAAAAA==.Moiryn:BAACLgAFFH8QAAMLAAcJew5JHACKAQALAAcJew5JHACKAQAfAAEJfgcOXAAzAAAuAAQKfy0AAwsACAl+HJ4ZAEoCAAsACAl+HJ4ZAEoCAB8AAgkoECWIAF8AAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Nainaii:BAAALgAFFAEJAQAAAA==.Naturals:BAAALgAECgEJAwAAAA==.Navidruid:BAABLgAFFH8IAAIlAAQJLwgMEgCpAAAlAAQJLwgMEgCpAAABLgAFFAgJKAAWADQQAA==.Navillus:BAACLgAFFH8oAAMWAAgJNBBtCAAqAgAWAAgJNBBtCAAqAgAeAAEJ0g8vAwBKAAAuAAQKf0oAAxYACQnvFMEMAGoCABYACQnvFMEMAGoCAB4ACAkTItgDAEsCAAAA.',
No='Norasoul:BAABLgAECn8wAAMdAAkJ5huiGQB7AgAdAAkJ5huiGQB7AgAmAAcJ2BQUDgBxAQAAAA==.Nowyourdead:BAAALgAECgQJBAAAAA==.',
['Nð']='Nðx:BAAALgAECggJDgAAAA==.',
Oa='Oakensoul:BAAALgAECgEJAQABLgAECgkJJwAKABcgAA==.',
Og='Ogron:BAACLgAFFH8fAAMLAAUJOib4FgCuAQALAAUJOib4FgCuAQAfAAIJ2xy3EACcAAAuAAQKfzkAAx8ACQl8JRAEAF4DAB8ACQl8JRAEAF4DAAsAAwknIKyXAKUAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgAECgYJBgAAAA==.',
Op='Ophindis:BAAALgAECgcJDwAAAA==.',
Or='Orthos:BAACLgAFFH8TAAIDAAUJNx8OPQB+AQADAAUJNx8OPQB+AQAuAAQKfzcAAgMACQlXJdgDAGQDAAMACQlXJdgDAGQDAAAA.Orwenya:BAABLgAECn8YAAIMAAYJCRG5HQANAQAMAAYJCRG5HQANAQAAAA==.',
Os='Osten:BAABLgAECn8cAAINAAkJRBDHKADGAQANAAkJRBDHKADGAQAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAFAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Pl='Plâgue:BAAALgAECgIJAgAAAA==.',
Po='Porkit:BAAALgAFFAIJAwAAAA==.',
Pu='Putemuptoo:BAAALgAECgcJBwAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAABLgAFFH8HAAInAAIJeBfCMACcAAAnAAIJeBfCMACcAAAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgcJDgAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Reddacted:BAAALgADCgcJDAAAAA==.Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8mAAIBAAkJpRjAAQAAAgABAAkJpRjAAQAAAgAuAAQKfzsAAgEACQnBJt0AAH8DAAEACQnBJt0AAH8DAAAA.Respect:BAAALgAECgIJAgAAAA==.Rexam:BAAALgAECgIJAgABLgAECgcJGAAdAEUjAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAABLgAECn8sAAIiAAkJrxraCgB2AgAiAAkJrxraCgB2AgAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAABLgAECn8/AAIiAAkJlCGoAwAMAwAiAAkJlCGoAwAMAwAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8bAAMVAAYJ5A8zCQBZAQAVAAYJ5A8zCQBZAQATAAYJowmu1QDpAAAAAA==.',
['Rè']='Rènza:BAABLgAFFH8GAAIYAAMJJxhICAClAAAYAAMJJxhICAClAAAAAA==.',
Sa='Saelybrosa:BAAALgAECggJDgAAAA==.Salphir:BAAALgAECgUJCQABLgAECgYJGAAMAAkRAA==.Samsara:BAAALgAECgQJCgAAAA==.Sanguineous:BAAALgAECgIJAgABLgAFFAUJCgAKAAIKAA==.Saphyr:BAEBLgAFFH8IAAIZAAUJbCCyEQBuAQAZAAUJbCCyEQBuAQABLgAFFAcJFwAJAJshAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Senniel:BAAALgAECgYJEwAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabit:BAAALgADCgUJBgABLgAFFAIJAwAFAAAAAA==.Shadda:BAABLgAECn8bAAIOAAcJfhcJAgBfAQAOAAcJfhcJAgBfAQAAAA==.Shadorae:BAAALgADCgcJBwABLgAECgQJDwAFAAAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8HAAIfAAIJXg0bSABuAAAfAAIJXg0bSABuAAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECggJFwAXAC4RAA==.Sheesh:BAAALgAECgYJCAAAAA==.Shinru:BAABLgAECn8dAAMNAAkJnRdVAgCFAQANAAkJnRdVAgCFAQAKAAYJlh6BmgBAAQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAABLgAFFH8XAAIZAAQJKxx2BQA2AQAZAAQJKxx2BQA2AQAAAA==.',
Si='Sickdayze:BAABLgAECn8cAAINAAkJcR44DQC+AgANAAkJcR44DQC+AgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sikkunt:BAAALgAECgEJAwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.Skyrain:BAAALgAECgQJBQAAAA==.',
Sl='Slootin:BAAALgAECgEJAgAAAA==.Slyxxar:BAACLgAFFH8OAAILAAQJwQruRwDNAAALAAQJwQruRwDNAAAuAAQKfxwABAwACAkaF9sRAJcBAAwACAkaF9sRAJcBAB8ABgnBEexRAP8AAAsAAQl4AVWrAB8AAAAA.',
Sm='Smarc:BAABLgAECn9FAAIhAAkJcR9aBADpAgAhAAkJcR9aBADpAgAAAA==.Smashtokhan:BAAALgAECgUJCgAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8aAAIEAAgJtBrXBADLAgAEAAgJtBrXBADLAgAuAAQKfxgAAwQABwlsIlgnABkCAAQABwlsIlgnABkCAAEAAgmjFq6GADwAAAAA.Sophie:BAACLgAFFH8PAAMKAAQJwCF+JwBsAQAKAAQJwCF+JwBsAQANAAEJ2w3qSgAzAAAuAAQKfxwAAwoACAmwHOs7ADQCAAoACAmwHOs7ADQCAA0ABgkuDlNKAE8BAAEuAAUUCAkaAAQAtBoA.Sophievokie:BAAALgAFFAQJBAABLgAFFAgJGgAEALQaAA==.Sophisticate:BAABLgAFFH8QAAIhAAQJnB5HDgBTAQAhAAQJnB5HDgBTAQABLgAFFAgJGgAEALQaAA==.Sophiz:BAAALgAECgYJDwABLgAFFAgJGgAEALQaAA==.Sophlax:BAACLgAFFH8TAAIaAAUJLySjAQCpAQAaAAUJLySjAQCpAQAuAAQKfxkAAhoACQnLIA8EABQDABoACQnLIA8EABQDAAEuAAUUCAkaAAQAtBoA.Sophs:BAACLgAFFH8IAAILAAQJkBgUMwAWAQALAAQJkBgUMwAWAQAuAAQKfxUAAwsABgnGHK5VAF8BAAsABgnGHK5VAF8BAB8ABQmpEslaANkAAAEuAAUUCAkaAAQAtBoA.Soulslug:BAAALgAECgEJAQAAAA==.Soup:BAAALgAECgEJAgAAAA==.Sox:BAACLgAFFH8IAAIOAAMJWB/ODwAKAQAOAAMJWB/ODwAKAQAuAAQKfzAAAg4ACQkmIeUCAAUDAA4ACQkmIeUCAAUDAAAA.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAMJAwAFAAAAAA==.',
Sp='Spicynoodle:BAABLgAECn8WAAICAAkJShXZLwAdAgACAAkJShXZLwAdAgAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAACLgAFFH8GAAIRAAIJMCCYDgBgAAARAAIJMCCYDgBgAAAuAAQKfx0AAhEABQmLJcIlAJ0BABEABQmLJcIlAJ0BAAAA.',
Sq='Squattinchop:BAABLgAECn8eAAIHAAYJQiH3FQA6AgAHAAYJQiH3FQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJHgAHAEIhAA==.',
St='Stacyguns:BAAALgAECgMJBAABLgAECgcJCgAFAAAAAA==.Stian:BAAALgAECgUJBQAAAA==.Stiffcrit:BAAALgAECgkJBwAAAA==.Stinkydh:BAABLgAECn8SAAIdAAYJMhFNcwBLAQAdAAYJMhFNcwBLAQAAAA==.Stryx:BAAALgADCgcJBwABLgAECgcJEgAFAAAAAA==.',
Su='Suji:BAABLgAECn8iAAIDAAkJXiAIFADQAgADAAkJXiAIFADQAgAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAFAAAAAA==.Supabird:BAAALgAECgQJBAAAAA==.Supergogeta:BAABLgAECn8yAAQEAAkJ3R9yDgDGAgAEAAgJsyByDgDGAgABAAIJkA82bwBpAAAOAAEJiQQ9NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgkJEQAAAA==.Synistër:BAAALgAECgUJBgAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôcôld:BAAALgADCgQJBAAAAA==.',
Ta='Takoda:BAAALgAECggJEAAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAABLgAECn8VAAICAAkJMwj5YgCAAQACAAkJMwj5YgCAAQAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tarkuun:BAAALgAECgkJCAAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBwAAAA==.',
Th='Thorish:BAABLgAECn8kAAIXAAkJ5CGrAwDbAgAXAAkJ5CGrAwDbAgAAAA==.',
Ti='Tiddyweaver:BAABLgAECn8XAAMIAAgJGyP+BwAdAwAIAAgJGyP+BwAdAwAHAAIJjxHCdwBhAAABLgAECgkJHwAWAEcfAA==.Timbit:BAABLgAECn8jAAIHAAgJfQmhMwBTAQAHAAgJfQmhMwBTAQAAAA==.Tinfoiltotem:BAAALgADCgYJCgAAAA==.Tinybubbles:BAABLgAECn8mAAMLAAgJDhYRSACOAQALAAgJDhYRSACOAQAfAAQJKw2XXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJEAAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgcJDwAFAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8dAAMbAAkJGxhXGQAHAgAbAAkJGxhXGQAHAgARAAEJvwejkAAqAAAAAA==.',
Tr='Trav:BAABLgAFFH8FAAIDAAQJLRKIawAkAQADAAQJLRKIawAkAQAAAA==.Trooth:BAAALgADCgYJBgABLgAECgUJDAAFAAAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgYJCgAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgkJCwAAAA==.',
Ty='Tyranis:BAEALgAECgYJCQAAAA==.Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAABLgAECn8XAAMWAAkJFw0DEgCoAQAWAAkJFw0DEgCoAQAcAAYJRAh9XwC8AAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Va='Vael:BAABLgAECn8iAAIdAAgJRxKDVgCDAQAdAAgJRxKDVgCDAQAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8pAAMZAAkJuBSAJwAYAQADAAcJ9RbEngAuAQAZAAgJ+g6AJwAYAQAAAA==.Valériana:BAAALgADCgMJAwAAAA==.',
Ve='Vee:BAABLgAECn8fAAMoAAgJ+yPlEgBbAgAoAAgJ+yPlEgBbAgAnAAEJnBXmOwBBAAAAAA==.Veyla:BAEALgADCgcJDgABLgAECgYJBwAFAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAACLgAFFH8HAAIDAAQJVQk+ggADAQADAAQJVQk+ggADAQAuAAQKfyQAAgMACQlzFoqAAGIBAAMACQlzFoqAAGIBAAAA.',
Wa='Warkdom:BAAALgAECgUJCAAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAACLgAFFH8OAAIgAAMJViR8EAAsAQAgAAMJViR8EAAsAQAuAAQKfyYAAiAACAlpJMcFALYCACAACAlpJMcFALYCAAAA.',
Wh='Wheelchair:BAEALgADCgYJBgABLgAECgYJBwAFAAAAAA==.',
Wi='Wickeddemon:BAABLgAECn8jAAIYAAkJ4hEhGADCAQAYAAkJ4hEhGADCAQAAAA==.Wildcanadian:BAAALgAECgIJAgAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
Wk='Wk:BAAALgAECgEJAQAAAA==.',
Wo='Wokstar:BAAALgAECgEJAgAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAINAAkJxhT0KgC5AQANAAkJxhT0KgC5AQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJIgAEAGgXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAACLgAFFH8PAAIdAAQJqxO/RwAQAQAdAAQJqxO/RwAQAQAuAAQKfyoAAh0ACQkYIDsRALgCAB0ACQkYIDsRALgCAAAA.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8cAAIlAAcJHRtpAAC4AQAlAAcJHRtpAAC4AQAuAAQKfxYAAiUACAnDInIEANUCACUACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.Yrel:BAAALgAECgQJBAABLgAECgYJGAAMAAkRAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zacariana:BAAALgADCgcJBwAAAA==.Zaftenpuff:BAAALgAECgQJBAAAAA==.Zandashami:BAAALgAECggJCAAAAA==.Zarya:BAABLgAECn8aAAQIAAgJ9B+4AQACAgAIAAYJeh64AQACAgAHAAcJQhusHgC4AQAJAAEJWCVqdgBoAAAAAA==.',
Ze='Zelgie:BAABLgAECn8rAAMXAAkJ7BExEwCXAQAXAAkJ7BExEwCXAQANAAUJ6BDnUQDxAAAAAA==.',
Zi='Zimzim:BAABLgAECn8dAAIIAAgJjxhbGwA9AgAIAAgJjxhbGwA9AgAAAA==.',
Zo='Zorsse:BAAALgAECgQJAwABLgAECggJHwAoAN0XAA==.',
Zu='Zulu:BAABLgAECn8VAAIJAAYJkBzxJgB4AQAJAAYJkBzxJgB4AQAAAA==.',
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
