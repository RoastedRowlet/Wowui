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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Rogue-Outlaw','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Paladin-Retribution','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Druid-Guardian','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Mage-Frost','Mage-Fire','Mage-Arcane','Warlock-Affliction','Evoker-Preservation','Paladin-Protection','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Evoker-Augmentation','DemonHunter-Devourer','Evoker-Devastation','Shaman-Elemental','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Hunter-Marksmanship','Druid-Feral','DemonHunter-Vengeance','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAcJEgABADIhAA==.',
Ab='Abadizzo:BAAALgAECgcJDwAAAA==.Abadizzoo:BAABLgAECn8qAAICAAkJtyEJFgCkAgACAAkJtyEJFgCkAgAAAA==.Abilities:BAAALgAECgYJEgAAAA==.',
Ac='Ace:BAAALgAFFAEJAQAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAABLgAECn8VAAICAAYJIhXEeQBMAQACAAYJIhXEeQBMAQABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8sAAIEAAkJUiTUBABAAwAEAAkJUiTUBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAFFAMJAwAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airleara:BAAALgAECgcJDAAAAA==.Airwrecka:BAACLgAFFH8IAAIBAAMJ3RTDLwDFAAABAAMJ3RTDLwDFAAAuAAQKfzEAAgEACQnEHqUMAI0CAAEACQnEHqUMAI0CAAAA.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.Aite:BAAALgAECgIJAgAAAA==.',
Al='Alexian:BAABLgAECn8bAAIGAAkJsRVzBQAPAgAGAAkJsRVzBQAPAgAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAABLgAECn8dAAICAAgJ5RVBDgAZAQACAAgJ5RVBDgAZAQAAAA==.',
Am='Amadk:BAAALgAECgkJAQAAAA==.Amebeliever:BAABLgAECn8fAAQHAAgJiB8ZFQBDAgAHAAcJuB4ZFQBDAgAIAAcJAgi/NwAMAQAJAAQJ/gmOZgB9AAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgkJFgAAAA==.',
Ar='Arahgon:BAEBLgAECn8lAAIKAAkJnxtuIQCBAgAKAAkJnxtuIQCBAgABLgAECggJDgAFAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asphodelos:BAAALgAECgYJDQABLgAFFAYJFAADAIcgAA==.Asukà:BAABLgAECn9CAAMLAAkJWRi/HQBfAgALAAkJWRi/HQBfAgAMAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAgAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJHAANAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgAECgYJBgABLgAECgYJGAAMAAkRAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAACLgAFFH8OAAIOAAUJ6hsICwBCAQAOAAUJ6hsICwBCAQAuAAQKfxYAAg4ABwn8HzANAA8CAA4ABwn8HzANAA8CAAAA.Beerbutt:BAAALgAECgEJBAAAAA==.Bellarg:BAABLgAECn83AAMPAAkJAxosKQA3AgAPAAkJAxosKQA3AgAQAAMJ3wetSACUAAAAAA==.Belobog:BAAALgAECgUJDQABLgAECggJHAADALsPAA==.Belyn:BAABLgAECn8dAAINAAkJVxf9AgCNAQANAAkJVxf9AgCNAQAAAA==.Benmage:BAAALgAECgUJBQAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bifesor:BAAALgAFFAMJAwAAAA==.Bigfaust:BAABLgAECn8YAAQJAAcJqB+7LABVAQAJAAUJpx+7LABVAQAIAAUJABu/LgBDAQAHAAIJRR8IUwDFAAAAAA==.',
Bl='Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAABLgAECn8UAAIKAAgJCghTrwAgAQAKAAgJCghTrwAgAQAAAA==.Bluespider:BAAALgAECgYJCQAAAA==.',
Bo='Bondrewd:BAAALgAECgEJAgABLgAFFAIJBgARADAgAA==.Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAACLgAFFH8IAAIHAAUJtxOnFwAFAQAHAAUJtxOnFwAFAQAuAAQKfxYAAwgABwmlGuwWAAoCAAgABwmlGuwWAAoCAAcABAkGI5k1ACwBAAEuAAUUCAkaAAQAtBoA.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Brolich:BAAALgAECggJEgABLgAECgQJBwAFAAAAAA==.Broo:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJEgAAAA==.Calculusx:BAABLgAECn8tAAISAAkJUCNCAQAHAwASAAkJUCNCAQAHAwAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8mAAQTAAgJAxlBBAAtAgATAAgJzRhBBAAtAgAUAAIJfBN8AgCfAAAVAAIJmRt0AwCXAAAuAAQKfzcABBMACQkrJgsFALEDABMACQn7JQsFALEDABQACQnjIeECAAUCABUAAwnIIi0MALwAAAAA.',
Ch='Champu:BAAALgAECgEJAQAAAA==.Chaoticx:BAABLgAECn8UAAIWAAQJXgPsBQCAAAAWAAQJXgPsBQCAAAAAAA==.Charlotte:BAAALgAECgcJEwAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn88AAQJAAkJ6yALBQDxAgAJAAkJ6yALBQDxAgAHAAMJfhQSagCAAAAIAAIJqwiMrABGAAABLgAFFAUJDgAOAOobAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAFAAAAAA==.',
Ci='Cinderion:BAAALgADCgUJBQABLgAECgkJVQAXAIsgAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAABLgAECn8ZAAIYAAgJ9hA5AwAgAQAYAAgJ9hA5AwAgAQAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgTSQAYAgADAAgJ1BgTSQAYAgABLgAECgkJCQAFAAAAAA==.Combatboots:BAABLgAECn9KAAIZAAkJVBTTFADpAQAZAAkJVBTTFADpAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMJAAYJ2Rs0LwCaAQAJAAUJGhw0LwCaAQAHAAYJsRShNwBAAQAAAA==.Darilol:BAAALgAECgUJDQABLgAECgYJGAAMAAkRAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn84AAIaAAkJtCICBAD5AgAaAAkJtCICBAD5AgAAAA==.Debra:BAACLgAFFH8GAAIZAAMJlAtRHQC4AAAZAAMJlAtRHQC4AAAuAAQKfy0AAhkACQnCGw8QACYCABkACQnCGw8QACYCAAAA.Debz:BAAALgAECgcJCAAAAA==.Deegee:BAABLgAECn8dAAMbAAcJbSIvDQCTAgAbAAcJbSIvDQCTAgARAAYJvBjTJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAgAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJBQAAAA==.Demize:BAAALgAECgkJCAAAAA==.Demonflame:BAABLgAECn8nAAIQAAkJDxbXBgDwAQAQAAkJDxbXBgDwAQAAAA==.Demíze:BAAALgAECgQJBQAAAA==.Deshield:BAAALgAFFAQJBAABLgAFFAUJHwALADomAA==.Deus:BAABLgAECn8eAAITAAkJGRE2bgCeAQATAAkJGRE2bgCeAQAAAA==.Dewry:BAABLgAECn8eAAMRAAcJ0RywAgCYAQARAAYJHiCwAgCYAQAcAAcJSxC2MQBUAQAAAA==.',
Dh='Dhudamuthi:BAACLgAFFH8GAAIJAAMJmBnWGgCUAAAJAAMJmBnWGgCUAAAuAAQKfzsAAgkACQmfJNECACsDAAkACQmfJNECACsDAAAA.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwøøf:BAAALgAECgYJDAAAAA==.Dizzo:BAAALgAECgkJBgAAAA==.',
Do='Donnajuan:BAABLgAECn86AAMNAAkJShwSCwDcAgANAAkJShwSCwDcAgAKAAEJ2QPovwEkAAAAAA==.Dornath:BAABLgAECn9bAAIKAAgJvxKGCgBAAQAKAAgJvxKGCgBAAQAAAA==.',
Dr='Draaxelro:BAABLgAECn8cAAICAAkJ9RDDWQCXAQACAAkJ9RDDWQCXAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAUJHwALADomAA==.Dragontiddys:BAABLgAECn8gAAMXAAgJRx9cBQDBAgAXAAgJRx9cBQDBAgAdAAEJJBaLjABCAAAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAFAAAAAA==.Drim:BAAALgAECgEJAQAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Eldread:BAAALgADCgEJAQAAAA==.Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8xAAIRAAkJxwoDLAB1AQARAAkJxwoDLAB1AQAAAA==.Elinalise:BAAALgAFFAEJAgABLgAFFAcJIwAeAHsNAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAACLgAFFH8XAAICAAUJ+xhKPAA0AQACAAUJ+xhKPAA0AQAuAAQKfzYAAgIACQmxIDwWAKMCAAIACQmxIDwWAKMCAAAA.',
Em='Embertal:BAABLgAECn8XAAMdAAcJ2g7dAwAmAQAdAAcJ2g7dAwAmAQAfAAEJAAANMAAAAAAAAA==.Emvoi:BAAALgADCgUJBQAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgcJDgAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.Enzo:BAAALgAECgEJAQAAAA==.',
Eq='Eqlipse:BAAALgAECgMJAwAAAA==.',
Ev='Evién:BAABLgAECn8UAAMgAAYJNxZEOQBrAQAgAAYJNxZEOQBrAQALAAUJthG7hADUAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Executè:BAAALgAECgEJAgABLgAFFAMJDAAZAOcbAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.Fatpanda:BAAALgAECgEJAQAAAA==.Faustus:BAAALgADCgMJAwAAAA==.',
Fe='Feleså:BAAALgAECggJDwABLgAFFAYJFAADAIcgAA==.Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8pAAIKAAgJ8gcErgAiAQAKAAgJ8gcErgAiAQAAAA==.',
Fi='Fiammetta:BAECLgAFFH8WAAIhAAcJWx+kBgDfAQAhAAcJWx+kBgDfAQAuAAQKfxgAAiEACQlrI3gNABMCACEACQlrI3gNABMCAAEuAAUUCQkeAAkAPSIA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJEgAFAAAAAA==.Finke:BAABLgAECn8dAAITAAcJax3rZwAHAgATAAcJax3rZwAHAgAAAA==.Fishmärket:BAABLgAECn8iAAIMAAkJYA8YDwC/AQAMAAkJYA8YDwC/AQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJCgAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Free:BAABLgAECn9VAAMXAAkJiyCYAwAKAwAXAAkJiyCYAwAKAwAdAAUJSB5zPQA0AQAAAA==.Frostie:BAABLgAFFH8OAAMDAAgJQRTgBQBPAgADAAgJQRTgBQBPAgAaAAEJAADrTQAAAAAAAA==.Frís:BAAALgAECggJEwABLgAFFAQJFwAaACscAA==.',
Fu='Furryfist:BAAALgAECgEJAgAAAA==.',
Ga='Galarine:BAABLgAECn8sAAIPAAkJiRgwKQA3AgAPAAkJiRgwKQA3AgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gd='Gdizz:BAAALgAECgkJAgAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAFFAUJDgAOAOobAA==.Gilrathor:BAAALgAECgkJEQAAAA==.Gizzlit:BAABLgAECn8tAAIMAAkJzxukBQCHAgAMAAkJzxukBQCHAgAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAFFAEJAgAAAA==.Gofetch:BAABLgAECn8hAAICAAkJsBvtLAApAgACAAkJsBvtLAApAgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAFAAAAAA==.',
Gr='Grandgoop:BAAALgAECgMJAwAAAA==.Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8oAAMCAAkJsx54GgCHAgACAAkJsx54GgCHAgAiAAUJ+hL5GAA/AQAAAA==.',
Gs='Gson:BAAALgAECgcJBwAAAA==.',
Gu='Guppy:BAAALgAECgcJDAAAAA==.Gutcassidy:BAAALgAECgYJCwAAAA==.Guttss:BAAALgAECgEJAQAAAA==.',
Ha='Hac:BAAALgAECgcJEQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harps:BAAALgAECgUJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAFAAAAAA==.',
He='Healingkiss:BAABLgAECn8qAAIbAAkJPQKlQQDlAAAbAAkJPQKlQQDlAAAAAA==.Heatup:BAABLgAECn8aAAITAAgJfiMzFQApAwATAAgJfiMzFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Hi='Hikingboots:BAAALgAECgYJBgAAAA==.',
Ho='Hollypallz:BAAALgADCgEJAQAAAA==.Holymages:BAABLgAECn8kAAITAAkJxRwVLgBgAgATAAkJxRwVLgBgAgAAAA==.Holymonka:BAAALgAECgEJAQAAAA==.Homtardy:BAABLgAECn8ZAAIjAAcJRh4zEgAVAgAjAAcJRh4zEgAVAgAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.Hunkomonk:BAAALgAECgcJCAABLgAECgkJJwAKABcgAA==.Hunt:BAAALgAFFAIJAgAAAA==.',
Ic='Ickarus:BAAALgAECgQJBQAAAA==.',
Ik='Iknowaguy:BAAALgADCgkJDwABLgAECgkJSgAZAFQUAA==.',
Il='Ilyanna:BAABLgAECn8lAAMWAAkJgh3rBQAkAgAWAAkJgh3rBQAkAgAPAAEJXxDXCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8pAAQiAAkJ4BkJAgAuAgAiAAcJYBsJAgAuAgAkAAYJARqKBgC3AQACAAQJpBhFQABlAAAuAAQKfyUAAiQACAmyJDgGADkDACQACAmyJDgGADkDAAAA.Imabadshot:BAAALgAECgEJAQAAAA==.Imscary:BAAALgAECgQJBQAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgcJDgAFAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgkJSgAZAFQUAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.Jenyaa:BAAALgAECgMJAwAAAA==.',
Jh='Jhalse:BAAALgAECgQJBAAAAA==.Jhoppss:BAABLgAECn8WAAMfAAYJlx1rDwDkAQAfAAYJlx1rDwDkAQAdAAQJjQ8ecgCGAAAAAA==.',
Ji='Jiinxx:BAAALgAECgQJCAAAAA==.Jilliebean:BAAALgAECgIJAwAAAA==.Jillià:BAAALgAFFAIJAwAAAA==.Jimpossible:BAAALgAECgYJCgAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Kallisto:BAAALgAFFAMJAwABLgAFFAYJBwADALkTAA==.Karls:BAAALgAECgYJDgAAAA==.',
Ke='Keez:BAAALgAECgcJDwAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kej:BAAALgAECgIJAgAAAA==.Kerrigan:BAACLgAFFH8jAAIeAAcJew3IJgCRAQAeAAcJew3IJgCRAQAuAAQKfzMAAh4ACQn4HtYWAI4CAB4ACQn4HtYWAI4CAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJHAANAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8lAAMEAAkJaBd5JAAoAgAEAAkJaBd5JAAoAgAlAAMJgCGXAgAmAQAAAA==.Kozand:BAAALgAECgcJEAABLgAECgYJGAAMAAkRAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgAECgMJAwAAAA==.',
Ky='Kyirr:BAABLgAECn8fAAMfAAkJgxlNDAAWAgAfAAcJQRpNDAAWAgAdAAUJFxiFSAAJAQAAAA==.Kyralen:BAABLgAECn8cAAMNAAYJHSPEGABMAgANAAYJHSPEGABMAgAKAAIJVxMPPgFuAAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAIMAAkJiRVRCgAsAgAMAAkJiRVRCgAsAgAAAA==.',
Li='Lilchithead:BAAALgAECgcJDwAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8eAAIJAAkJPSKIAQBUAgAJAAkJPSKIAQBUAgAuAAQKfy0AAgkACQnqJSUBAK0DAAkACQnqJSUBAK0DAAAA.Lividea:BAABLgAECn8pAAIDAAcJygbzwgD6AAADAAcJygbzwgD6AAAAAA==.Livinglover:BAAALgADCgUJAwAAAA==.',
Ll='Llela:BAAALgAECgcJCAAAAA==.Llynryn:BAABLgAECn8YAAIRAAgJhBCEMwBLAQARAAgJhBCEMwBLAQAAAA==.',
Lo='Locktua:BAAALgAECgcJCQAAAA==.',
Ly='Lympha:BAABLgAFFH8JAAMLAAMJ1x3iNgAHAQALAAMJ1x3iNgAHAQAMAAEJowEhHgAvAAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAgJHAAeAA0eAA==.Magicmanzz:BAABLgAECn8pAAITAAkJFRDsCABhAQATAAkJFRDsCABhAQAAAA==.Magnifuso:BAAALgAECggJEgAAAA==.Maguapa:BAAALgAECgQJBwAAAA==.Malgata:BAAALgADCgkJFgAAAA==.Margarita:BAAALgAECgUJCwAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8IAAINAAMJIRccMQCvAAANAAMJIRccMQCvAAAuAAQKfy4AAw0ACQnbH9wZADcCAA0ABwkNH9wZADcCAAoACAntGVpIAO0BAAAA.',
Mc='Mcplucky:BAABLgAECn8eAAIkAAYJnwcjAwCtAAAkAAYJnwcjAwCtAAAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Miguelito:BAAALgAECgEJAQABLgAECgcJFwAfALwcAA==.Mikio:BAABLgAECn8hAAIBAAkJdRDjIQC6AQABAAkJdRDjIQC6AQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8uAAIbAAkJLRyHCwCuAgAbAAkJLRyHCwCuAgAAAA==.Misho:BAAALgAECgMJAwAAAA==.',
Mo='Moardottz:BAABLgAECn8dAAIPAAYJPxW+cgB5AQAPAAYJPxW+cgB5AQABLgAECgUJBQAFAAAAAA==.Moiryn:BAACLgAFFH8TAAMLAAcJ6hFJHACKAQALAAcJ6hFJHACKAQAgAAIJnwUOXAAzAAAuAAQKfy0AAwsACAl+HJ4ZAEoCAAsACAl+HJ4ZAEoCACAAAgkoECWIAF8AAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Nainaii:BAAALgAFFAEJAQAAAA==.Nalthexon:BAAALgAECgEJAQAAAA==.Naturals:BAAALgAECgEJAwAAAA==.Navidruid:BAABLgAFFH8IAAIlAAQJLwgMEgCpAAAlAAQJLwgMEgCpAAABLgAFFAgJKQAXADQQAA==.Navillus:BAACLgAFFH8pAAMXAAgJNBBtCAAqAgAXAAgJNBBtCAAqAgAfAAEJDxR2BABMAAAuAAQKf0oAAxcACQnvFMEMAGoCABcACQnvFMEMAGoCAB8ACAkTItgDAEsCAAAA.',
No='Norasoul:BAABLgAECn8wAAMeAAkJ5huiGQB7AgAeAAkJ5huiGQB7AgAmAAcJ2BQUDgBxAQAAAA==.Nowyourdead:BAAALgAECgQJBQAAAA==.',
['Nð']='Nðx:BAAALgAECggJDgAAAA==.',
Oa='Oakensoul:BAAALgAECgcJCAABLgAECgkJJwAKABcgAA==.',
Og='Ogron:BAACLgAFFH8fAAMLAAUJOib4FgCuAQALAAUJOib4FgCuAQAgAAIJ2xzkFwCWAAAuAAQKfzkAAyAACQl8JRAEAF4DACAACQl8JRAEAF4DAAsAAwknIKyXAKUAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgAECgYJBgAAAA==.',
Op='Ophindis:BAAALgAECgcJDwAAAA==.',
Or='Orthos:BAACLgAFFH8UAAIDAAYJhyCjFABsAQADAAYJhyCjFABsAQAuAAQKfzcAAgMACQlXJdgDAGQDAAMACQlXJdgDAGQDAAAA.Orwenya:BAABLgAECn8YAAIMAAYJCRG5HQANAQAMAAYJCRG5HQANAQAAAA==.',
Os='Osten:BAABLgAECn8cAAINAAkJRBDHKADGAQANAAkJRBDHKADGAQAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAFAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Pl='Plâgue:BAAALgAECgIJAgAAAA==.',
Po='Porkit:BAAALgAFFAIJAwAAAA==.',
Pu='Putemuptoo:BAAALgAECgcJBwAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAABLgAFFH8KAAMnAAMJ3RNSEADgAAAnAAMJ3RNSEADgAAAoAAIJeBfCMACcAAAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgcJDgAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Reddacted:BAAALgADCgcJDAAAAA==.Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8oAAIBAAkJQxvAAQAAAgABAAkJQxvAAQAAAgAuAAQKfzsAAgEACQnBJt0AAH8DAAEACQnBJt0AAH8DAAAA.Respect:BAAALgAECgIJAgAAAA==.Rexam:BAAALgAECgIJAgABLgAECgcJGAAeAEUjAA==.Rexsouls:BAAALgAECgEJAQAAAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAABLgAECn8sAAIjAAkJrxraCgB2AgAjAAkJrxraCgB2AgAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAABLgAECn9DAAIjAAkJlCGoAwAMAwAjAAkJlCGoAwAMAwAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8bAAMVAAYJ5A8zCQBZAQAVAAYJ5A8zCQBZAQATAAYJowmu1QDpAAAAAA==.',
['Rè']='Rènza:BAABLgAFFH8IAAIZAAMJJxgWDACjAAAZAAMJJxgWDACjAAAAAA==.',
Sa='Saelybrosa:BAAALgAECggJDgAAAA==.Salphir:BAAALgAECgUJCQABLgAECgYJGAAMAAkRAA==.Samsara:BAAALgAECgQJCgAAAA==.Sanguineous:BAAALgAECgIJAgABLgAFFAUJCgAKAAIKAA==.Saphyr:BAEBLgAFFH8IAAIaAAUJbCCyEQBuAQAaAAUJbCCyEQBuAQABLgAFFAkJHgAJAD0iAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Senniel:BAAALgAECgYJEwAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabalaba:BAAALgAECgEJAQAAAA==.Shabit:BAAALgADCgUJBgABLgAFFAIJAwAFAAAAAA==.Shadda:BAABLgAECn8bAAIOAAcJXhclAwBaAQAOAAcJXhclAwBaAQAAAA==.Shadorae:BAAALgADCgcJBwABLgAECgYJEQAFAAAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8HAAIgAAIJXg0bSABuAAAgAAIJXg0bSABuAAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECggJGQAYAPYQAA==.Sheesh:BAAALgAECgYJCgAAAA==.Shinru:BAABLgAECn8dAAMNAAkJnhebAwBlAQANAAkJnhebAwBlAQAKAAYJlh6BmgBAAQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAABLgAFFH8XAAIaAAQJKxwICAAqAQAaAAQJKxwICAAqAQAAAA==.',
Si='Sickdayze:BAABLgAECn8fAAINAAkJwCA4DQC+AgANAAkJwCA4DQC+AgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sikkunt:BAAALgAECgEJAwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.Skyrain:BAAALgAECgQJBQAAAA==.',
Sl='Slootin:BAAALgAECgEJAgAAAA==.Slyxxar:BAACLgAFFH8OAAILAAQJwQruRwDNAAALAAQJwQruRwDNAAAuAAQKfxwABAwACAkaF9sRAJcBAAwACAkaF9sRAJcBACAABgnBEexRAP8AAAsAAQl4AVWrAB8AAAAA.',
Sm='Smarc:BAABLgAECn9FAAIiAAkJcR9aBADpAgAiAAkJcR9aBADpAgAAAA==.Smashtokhan:BAAALgAECgUJCgAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8aAAIEAAgJtBrXBADLAgAEAAgJtBrXBADLAgAuAAQKfxgAAwQABwlsIlgnABkCAAQABwlsIlgnABkCAAEAAgmjFq6GADwAAAAA.Sophie:BAACLgAFFH8PAAMKAAQJwCF+JwBsAQAKAAQJwCF+JwBsAQANAAEJ2w3qSgAzAAAuAAQKfxwAAwoACAmwHOs7ADQCAAoACAmwHOs7ADQCAA0ABgkuDlNKAE8BAAEuAAUUCAkaAAQAtBoA.Sophievokie:BAAALgAFFAQJBAABLgAFFAgJGgAEALQaAA==.Sophisticate:BAABLgAFFH8QAAIiAAQJnB5HDgBTAQAiAAQJnB5HDgBTAQABLgAFFAgJGgAEALQaAA==.Sophiz:BAAALgAECgYJDwABLgAFFAgJGgAEALQaAA==.Sophlax:BAACLgAFFH8TAAIbAAUJLySjAQCpAQAbAAUJLySjAQCpAQAuAAQKfxkAAhsACQnLIA8EABQDABsACQnLIA8EABQDAAEuAAUUCAkaAAQAtBoA.Sophs:BAACLgAFFH8IAAILAAQJkBgUMwAWAQALAAQJkBgUMwAWAQAuAAQKfxUAAwsABgnGHK5VAF8BAAsABgnGHK5VAF8BACAABQmpEslaANkAAAEuAAUUCAkaAAQAtBoA.Soulslug:BAAALgAECgEJAQAAAA==.Soup:BAAALgAECgEJAgAAAA==.Sox:BAACLgAFFH8IAAIOAAMJWB/ODwAKAQAOAAMJWB/ODwAKAQAuAAQKfzAAAg4ACQkmIeUCAAUDAA4ACQkmIeUCAAUDAAAA.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAMJAwAFAAAAAA==.',
Sp='Spankgg:BAAALgAECgQJBAAAAA==.Spicynoodle:BAABLgAECn8WAAICAAkJShXZLwAdAgACAAkJShXZLwAdAgAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAACLgAFFH8GAAIRAAIJMCCjFABcAAARAAIJMCCjFABcAAAuAAQKfx0AAhEABQmLJcIlAJ0BABEABQmLJcIlAJ0BAAAA.',
Sq='Squattinchop:BAABLgAECn8eAAIHAAYJQiH3FQA6AgAHAAYJQiH3FQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJHgAHAEIhAA==.',
St='Stacyguns:BAAALgAECgMJBAABLgAECgcJCgAFAAAAAA==.Stian:BAAALgAECgUJBQAAAA==.Stiffcrit:BAAALgAECgkJBwAAAA==.Stinkydh:BAABLgAECn8SAAIeAAYJMhFNcwBLAQAeAAYJMhFNcwBLAQAAAA==.Stryx:BAAALgADCgcJBwABLgAECgcJEgAFAAAAAA==.',
Su='Suji:BAABLgAECn8iAAIDAAkJXiAIFADQAgADAAkJXiAIFADQAgAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAFAAAAAA==.Supabird:BAAALgAECgQJBAAAAA==.Supergogeta:BAABLgAECn8yAAQEAAkJ3R9yDgDGAgAEAAgJsyByDgDGAgABAAIJkA82bwBpAAAOAAEJiQQ9NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgkJEQAAAA==.Synistër:BAAALgAECgUJBgAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôcôld:BAAALgADCgQJBAAAAA==.',
Ta='Takoda:BAAALgAECggJEAAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAABLgAECn8VAAICAAkJMwj5YgCAAQACAAkJMwj5YgCAAQAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tarkuun:BAAALgAECgkJCAAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBwAAAA==.',
Th='Thorish:BAABLgAECn8kAAIYAAkJ5CGrAwDbAgAYAAkJ5CGrAwDbAgAAAA==.',
Ti='Tiddyweaver:BAABLgAECn8XAAMIAAgJGyP+BwAdAwAIAAgJGyP+BwAdAwAHAAIJjxHCdwBhAAABLgAECgkJIAAXAEcfAA==.Timbit:BAABLgAECn8jAAIHAAgJfQmhMwBTAQAHAAgJfQmhMwBTAQAAAA==.Tinfoiltotem:BAAALgADCgYJCgAAAA==.Tinybubbles:BAABLgAECn8oAAMLAAkJbRQRSACOAQALAAkJbRQRSACOAQAgAAQJKw2XXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJEAAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgcJDwAFAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8gAAMcAAkJGRlXGQAHAgAcAAkJGRlXGQAHAgARAAEJvwejkAAqAAAAAA==.',
Tr='Trav:BAABLgAFFH8FAAIDAAQJLRKIawAkAQADAAQJLRKIawAkAQAAAA==.Trooth:BAAALgADCgYJBgABLgAECgUJDAAFAAAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgYJCgAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgkJCwAAAA==.',
Ty='Tyranis:BAEALgAECggJDgAAAA==.Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAABLgAECn8XAAMXAAkJFw0DEgCoAQAXAAkJFw0DEgCoAQAdAAYJRAh9XwC8AAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Uw='Uwusev:BAAALgAECgIJAgAAAA==.',
Va='Vael:BAABLgAECn8iAAIeAAgJRxKDVgCDAQAeAAgJRxKDVgCDAQAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8pAAMaAAkJuBSAJwAYAQADAAcJ9RbEngAuAQAaAAgJ+g6AJwAYAQAAAA==.Valériana:BAAALgADCgMJAwAAAA==.',
Ve='Vee:BAABLgAECn8fAAMnAAgJ+yPlEgBbAgAnAAgJ+yPlEgBbAgAoAAEJnBXmOwBBAAAAAA==.Veyla:BAEALgADCgcJDgABLgAECgYJBwAFAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAACLgAFFH8HAAIDAAQJVQk+ggADAQADAAQJVQk+ggADAQAuAAQKfyQAAgMACQlzFoqAAGIBAAMACQlzFoqAAGIBAAAA.',
Wa='Warkdom:BAAALgAECgUJCAAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAACLgAFFH8PAAIhAAMJViR8EAAsAQAhAAMJViR8EAAsAQAuAAQKfyYAAiEACAlpJMcFALYCACEACAlpJMcFALYCAAAA.',
Wh='Wheelchair:BAEALgADCgYJBgABLgAECgYJBwAFAAAAAA==.',
Wi='Wickeddemon:BAABLgAECn8lAAIZAAkJzBIhGADCAQAZAAkJzBIhGADCAQAAAA==.Wildcanadian:BAAALgAECgIJAgAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
Wk='Wk:BAAALgAECgEJAQAAAA==.',
Wo='Wokstar:BAAALgAECgEJAgAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAINAAkJxhT0KgC5AQANAAkJxhT0KgC5AQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJJQAEAGgXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAACLgAFFH8PAAIeAAQJqxO/RwAQAQAeAAQJqxO/RwAQAQAuAAQKfyoAAh4ACQkYIDsRALgCAB4ACQkYIDsRALgCAAAA.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8cAAIlAAcJFRvbAACgAQAlAAcJFRvbAACgAQAuAAQKfxYAAiUACAnDInIEANUCACUACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.Yrel:BAAALgAECgQJBAABLgAECgYJGAAMAAkRAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zacariana:BAAALgADCgcJBwAAAA==.Zaftenpuff:BAAALgAECgQJBAAAAA==.Zandashami:BAAALgAECggJCAAAAA==.Zarya:BAABLgAECn8bAAQIAAgJFyCbAgAEAgAIAAYJqR6bAgAEAgAHAAcJQhusHgC4AQAJAAEJWCVqdgBoAAAAAA==.',
Ze='Zelgie:BAABLgAECn8rAAMYAAkJ7BExEwCXAQAYAAkJ7BExEwCXAQANAAUJ6BDnUQDxAAAAAA==.',
Zi='Zimzim:BAABLgAECn8dAAIIAAgJjxhbGwA9AgAIAAgJjxhbGwA9AgAAAA==.',
Zo='Zorsse:BAAALgAECgQJAwABLgAECggJHwAnAN0XAA==.',
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
