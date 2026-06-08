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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Rogue-Outlaw','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Paladin-Retribution','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Druid-Guardian','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Mage-Frost','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','Shaman-Elemental','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Warlock-Affliction','Hunter-Marksmanship','Evoker-Devastation','Druid-Feral','DemonHunter-Vengeance','Warrior-Arms','Paladin-Protection','Warrior-Fury',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAYJEQABAF0iAA==.',
Ab='Abadizzo:BAAALgAECgcJDAAAAA==.Abadizzoo:BAABLgAECn8qAAICAAkJtyF1EwCrAgACAAkJtyF1EwCrAgAAAA==.Abilities:BAAALgAECgYJEgAAAA==.',
Ac='Ace:BAAALgAFFAEJAQAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAAALgAECgYJEwABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8sAAIEAAkJUiTUBABAAwAEAAkJUiTUBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAECgIJAwAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airleara:BAAALgAECgcJDAAAAA==.Airwrecka:BAACLgAFFH8IAAIBAAMJ3RQHKwDJAAABAAMJ3RQHKwDJAAAuAAQKfzEAAgEACQnEHocLAJICAAEACQnEHocLAJICAAAA.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.Aite:BAAALgAECgIJAgAAAA==.',
Al='Alexian:BAABLgAECn8bAAIGAAkJsRUqBQARAgAGAAkJsRUqBQARAgAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAAALgAECgcJEwAAAA==.',
Am='Amebeliever:BAABLgAECn8fAAQHAAgJiB8ZFQBDAgAHAAcJuB4ZFQBDAgAIAAcJAgi/NwAMAQAJAAQJ/gnGYgCAAAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgkJFgAAAA==.',
Ar='Arahgon:BAEBLgAECn8ZAAIKAAcJtBp+TgDRAQAKAAcJtBp+TgDRAQABLgAECgYJCQAFAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asphodelos:BAAALgAECgYJDQABLgAFFAQJDQADAJseAA==.Asukà:BAABLgAECn85AAMLAAkJ/xbfGwBgAgALAAkJ/xbfGwBgAgAMAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAgAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJHAANAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgAECgYJBgABLgAECgYJFQAMANIPAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAABLgAECn8WAAIOAAcJ/B8HDAAQAgAOAAcJ/B8HDAAQAgAAAA==.Bellarg:BAABLgAECn83AAMPAAkJAxqeJQBCAgAPAAkJAxqeJQBCAgAQAAMJ3wetSACUAAAAAA==.Belobog:BAAALgAECgUJDQABLgAECggJHAADALsPAA==.Belyn:BAABLgAECn8WAAINAAcJRhPCMgB/AQANAAcJRhPCMgB/AQAAAA==.Benmage:BAAALgAECgUJBQAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bifesor:BAAALgAFFAMJAwAAAA==.Bigfaust:BAABLgAECn8YAAQJAAcJqB/2KgBXAQAJAAUJpx/2KgBXAQAIAAUJABu/LgBDAQAHAAIJRR8IUwDFAAAAAA==.',
Bl='Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAABLgAECn8UAAIKAAgJCgg5pQAjAQAKAAgJCgg5pQAjAQAAAA==.Bluespider:BAAALgAECgYJCQAAAA==.',
Bo='Bondrewd:BAAALgAECgEJAgABLgAECgUJHQARAIslAA==.Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAABLgAECn8WAAMIAAcJpRrsFgAKAgAIAAcJpRrsFgAKAgAHAAQJBiOOMgAuAQABLgAFFAcJFgAEAJMaAA==.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Brolich:BAAALgAECggJEgABLgAECgQJBwAFAAAAAA==.Broo:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJEQAAAA==.Calculusx:BAABLgAECn8tAAISAAkJUCMdAQAKAwASAAkJUCMdAQAKAwAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8gAAMTAAYJ+RtBBAAtAgATAAYJrhtBBAAtAgAUAAIJmRvwAgCXAAAuAAQKfzcABBMACQkrJgsFALEDABMACQn7JQsFALEDABUACQnjIeECAAUCABQAAwnIIjULALwAAAAA.',
Ch='Champu:BAAALgADCgEJAQAAAA==.Chaoticx:BAAALgADCgQJBQAAAA==.Charlotte:BAAALgAECgcJEwAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn84AAMJAAkJ6yCaBAD0AgAJAAkJ6yCaBAD0AgAIAAEJHwlRtwAiAAABLgAECgcJFgAOAPwfAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAFAAAAAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAAALgAECgcJDgAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgTSQAYAgADAAgJ1BgTSQAYAgABLgAECgkJCQAFAAAAAA==.Combatboots:BAABLgAECn8+AAIWAAkJJxRUEwDsAQAWAAkJJxRUEwDsAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMJAAYJ2Rs0LwCaAQAJAAUJGhw0LwCaAQAHAAYJsRShNwBAAQAAAA==.Darilol:BAAALgAECgUJBQABLgAECgYJFQAMANIPAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn8wAAIXAAkJtCKHAwACAwAXAAkJtCKHAwACAwAAAA==.Debra:BAACLgAFFH8GAAIWAAMJlAt+GQC4AAAWAAMJlAt+GQC4AAAuAAQKfy0AAhYACQnCG5wOACsCABYACQnCG5wOACsCAAAA.Debz:BAAALgAECgcJCAAAAA==.Deegee:BAABLgAECn8dAAMYAAcJbSIfDACXAgAYAAcJbSIfDACXAgARAAYJvBjTJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAgAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJBQAAAA==.Demize:BAAALgAECgYJBwAAAA==.Demonflame:BAABLgAECn8nAAIQAAkJDxYuBgD0AQAQAAkJDxYuBgD0AQAAAA==.Demíze:BAAALgAECgEJAgAAAA==.Deshield:BAAALgAFFAQJBAABLgAFFAQJGgALACYmAA==.Deus:BAABLgAECn8bAAITAAkJexCKZgCpAQATAAkJexCKZgCpAQAAAA==.Dewry:BAABLgAECn8XAAMRAAYJWh/RKgB1AQARAAYJWh/RKgB1AQAZAAYJcBHmLgBXAQAAAA==.',
Dh='Dhudamuthi:BAACLgAFFH8FAAIJAAMJmBlFOwCtAAAJAAMJmBlFOwCtAAAuAAQKfzsAAgkACQmfJIUCAC4DAAkACQmfJIUCAC4DAAAA.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwoof:BAAALgAECgYJDAAAAA==.Dizzo:BAAALgAECgkJBQAAAA==.',
Do='Donnajuan:BAABLgAECn86AAMNAAkJShw3CgDfAgANAAkJShw3CgDfAgAKAAEJ2QPzqAEkAAAAAA==.Dornath:BAABLgAECn89AAIKAAgJUxHTbwCDAQAKAAgJUxHTbwCDAQAAAA==.',
Dr='Draaxelro:BAABLgAECn8bAAICAAkJ9RDSUgCeAQACAAkJ9RDSUgCeAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAQJGgALACYmAA==.Dragontiddys:BAABLgAECn8fAAMaAAgJRx8VBQDDAgAaAAgJRx8VBQDDAgAbAAEJJBbNhABCAAAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAFAAAAAA==.Drim:BAAALgADCgkJDAAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Eldread:BAAALgADCgEJAQAAAA==.Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8xAAIRAAkJxwrKJwCHAQARAAkJxwrKJwCHAQAAAA==.Elinalise:BAAALgAFFAEJAgABLgAFFAcJIwAcAHsNAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAACLgAFFH8MAAICAAQJzBdqMQA/AQACAAQJzBdqMQA/AQAuAAQKfzQAAgIACQkLIJYUAKMCAAIACQkLIJYUAKMCAAAA.',
Em='Embertal:BAAALgAECgYJEAAAAA==.Emvoi:BAAALgADCgUJBQAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgcJDgAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.Enzo:BAAALgAECgEJAQAAAA==.',
Ev='Evién:BAABLgAECn8UAAMdAAYJNxZEOQBrAQAdAAYJNxZEOQBrAQALAAUJthH0fQDVAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Executè:BAAALgAECgEJAgABLgAFFAMJBgAWAMUaAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.Faustus:BAAALgADCgMJAwAAAA==.',
Fe='Feleså:BAAALgADCgcJBwABLgAFFAQJDQADAJseAA==.Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8pAAIKAAgJ8geoowAmAQAKAAgJ8geoowAmAQAAAA==.',
Fi='Fiammetta:BAECLgAFFH8PAAIeAAYJyyGcBQDVAQAeAAYJyyGcBQDVAQAuAAQKfxgAAh4ACQlrI1UMABoCAB4ACQlrI1UMABoCAAEuAAUUBwkWAAkAmyEA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Finke:BAABLgAECn8cAAITAAcJmRzrZwAHAgATAAcJmRzrZwAHAgAAAA==.Fishmärket:BAABLgAECn8iAAIMAAkJYA/TDQDGAQAMAAkJYA/TDQDGAQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJBAAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Frostie:BAABLgAFFH8GAAMXAAMJgwvaRQAAAAADAAIJgwuD3ACAAAAXAAEJAADaRQAAAAAAAA==.Frís:BAAALgAECggJEwABLgAFFAMJDAAXANMaAA==.',
Fu='Furryfist:BAAALgADCgcJCAAAAA==.',
Ga='Galarine:BAABLgAECn8sAAIPAAkJiRibJgA9AgAPAAkJiRibJgA9AgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAECgcJFgAOAPwfAA==.Gilrathor:BAAALgAECggJDgAAAA==.Gizzlit:BAABLgAECn8pAAIMAAgJDhs6CgAKAgAMAAgJDhs6CgAKAgAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAECgUJBgAAAA==.Gofetch:BAABLgAECn8hAAICAAkJsBvDKAAwAgACAAkJsBvDKAAwAgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAFAAAAAA==.',
Gr='Grandgoop:BAAALgAECgMJAwAAAA==.Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8oAAMCAAkJsx4dFwCRAgACAAkJsx4dFwCRAgAfAAUJ+hL5GAA/AQAAAA==.',
Gu='Guppy:BAAALgAECgcJDAAAAA==.Gutcassidy:BAAALgAECgYJCwAAAA==.',
Ha='Hac:BAAALgAECgcJEQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harps:BAAALgAECgUJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAFAAAAAA==.',
He='Healingkiss:BAABLgAECn8pAAIYAAgJRAIyRADKAAAYAAgJRAIyRADKAAAAAA==.Heatup:BAABLgAECn8aAAITAAgJfiMzFQApAwATAAgJfiMzFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Ho='Hollypallz:BAAALgADCgEJAQAAAA==.Holymages:BAABLgAECn8kAAITAAkJxRyAKgBpAgATAAkJxRyAKgBpAgAAAA==.Holymonka:BAAALgAECgEJAQAAAA==.Homtardy:BAABLgAECn8YAAIgAAYJpx2yGgCzAQAgAAYJpx2yGgCzAQAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.Hunkomonk:BAAALgAECgcJBwABLgAECgkJJwAKABcgAA==.',
Ic='Ickarus:BAAALgAECgQJBAAAAA==.',
Ik='Iknowaguy:BAAALgADCgEJAQABLgAECgkJPgAWACcUAA==.',
Il='Ilyanna:BAABLgAECn8lAAMhAAkJgh1HBQAnAgAhAAkJgh1HBQAnAgAPAAEJXxDXCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8gAAQfAAgJ+BcvAgAIAgAfAAcJIhUvAgAIAgAiAAYJARqKBgC3AQACAAMJCxnaIgBaAAAuAAQKfyUAAiIACAmyJDgGADkDACIACAmyJDgGADkDAAAA.Imabadshot:BAAALgADCgUJBQAAAA==.Imscary:BAAALgADCgQJBAAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgcJDgAFAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgkJPgAWACcUAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.',
Jh='Jhalse:BAAALgAECgQJBAAAAA==.Jhoppss:BAABLgAECn8WAAMjAAYJlx1rDwDkAQAjAAYJlx1rDwDkAQAbAAQJjQ/RawCJAAAAAA==.',
Ji='Jiinxx:BAAALgAECgQJBgAAAA==.Jillià:BAAALgAFFAIJAwAAAA==.Jimpossible:BAAALgAECgYJCgAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Karls:BAAALgAECgYJDgAAAA==.',
Ke='Keez:BAAALgAECgcJDwAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kej:BAAALgAECgIJAgAAAA==.Kerafyrm:BAABLgAECn9CAAMaAAgJwx8cBQDDAgAaAAgJwx8cBQDDAgAbAAUJ7RvKOgA1AQAAAA==.Kerrigan:BAACLgAFFH8jAAIcAAcJew0hHwCeAQAcAAcJew0hHwCeAQAuAAQKfzMAAhwACQn4HngVAI4CABwACQn4HngVAI4CAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJHAANAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8iAAMEAAkJaBd5JAAoAgAEAAkJaBd5JAAoAgAkAAEJPRBUMQA+AAAAAA==.Kozand:BAAALgAECgQJBAABLgAECgYJFQAMANIPAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgADCggJFwAAAA==.',
Ky='Kyirr:BAABLgAECn8fAAMjAAkJgxlNDAAWAgAjAAcJQRpNDAAWAgAbAAUJFxicRAAMAQAAAA==.Kyralen:BAABLgAECn8cAAMNAAYJHSPEGABMAgANAAYJHSPEGABMAgAKAAIJVxORLgFuAAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAIMAAkJiRVRCgAsAgAMAAkJiRVRCgAsAgAAAA==.',
Li='Lilchithead:BAAALgAECgcJDwAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8WAAIJAAcJmyGTBAAzAgAJAAcJmyGTBAAzAgAuAAQKfy0AAgkACQnqJSUBAK0DAAkACQnqJSUBAK0DAAAA.Lividea:BAABLgAECn8mAAIDAAcJtQUBwgDxAAADAAcJtQUBwgDxAAAAAA==.Livinglover:BAAALgADCgUJAwAAAA==.',
Ll='Llela:BAAALgAECgcJCAAAAA==.Llynryn:BAABLgAECn8WAAIRAAgJ8A6EMwBLAQARAAgJ8A6EMwBLAQAAAA==.',
Lo='Locktua:BAAALgAECgcJCQAAAA==.',
Ly='Lympha:BAABLgAFFH8JAAMLAAMJ1x0AMAALAQALAAMJ1x0AMAALAQAMAAEJowFNGQAzAAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAcJFAAcAHUbAA==.Magicmanzz:BAABLgAECn8dAAITAAgJcw5+cACTAQATAAgJcw5+cACTAQAAAA==.Magnifuso:BAAALgAECggJEgAAAA==.Maguapa:BAAALgAECgQJBwAAAA==.Malgata:BAAALgADCgkJFgAAAA==.Margarita:BAAALgAECgUJCwAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8IAAINAAMJIRc5LAC/AAANAAMJIRc5LAC/AAAuAAQKfy4AAw0ACQnbH1oYADkCAA0ABwkNH1oYADkCAAoACAntGZNDAPEBAAAA.',
Mc='Mcplucky:BAAALgAECgYJDwAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Miguelito:BAAALgAECgEJAQABLgAECgcJFwAjALwcAA==.Mikio:BAABLgAECn8fAAIBAAkJcQ9CIwChAQABAAkJcQ9CIwChAQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8uAAIYAAkJLRx+CgCyAgAYAAkJLRx+CgCyAgAAAA==.Misho:BAAALgADCgEJAQAAAA==.',
Mo='Moardottz:BAABLgAECn8dAAIPAAYJPxW+cgB5AQAPAAYJPxW+cgB5AQABLgAECgUJBQAFAAAAAA==.Moiryn:BAACLgAFFH8PAAMLAAYJiBCeFwCNAQALAAYJiBCeFwCNAQAdAAEJfge2UgA3AAAuAAQKfywAAwsACAl+HJ4ZAEoCAAsACAl+HJ4ZAEoCAB0AAQlxD9ieAC0AAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Nainaii:BAAALgAECgEJAQAAAA==.Naturals:BAAALgAECgEJAwAAAA==.Navillus:BAACLgAFFH8jAAIaAAcJ5BE0CgDpAQAaAAcJ5BE0CgDpAQAuAAQKf0kAAxoACQnvFMEMAGoCABoACQnvFMEMAGoCACMACAkTIosDAE0CAAAA.',
No='Norasoul:BAABLgAECn8wAAMcAAkJ5hsiGAB7AgAcAAkJ5hsiGAB7AgAlAAcJ2BQ1DQBxAQAAAA==.',
Og='Ogron:BAACLgAFFH8aAAMLAAQJJiZsEgCzAQALAAQJJiZsEgCzAQAdAAEJcx/FGwBTAAAuAAQKfzkAAx0ACQl8JRAEAF4DAB0ACQl8JRAEAF4DAAsAAwknIKqPAKYAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgADCgQJBAAAAA==.',
Op='Ophindis:BAAALgAECgcJDwAAAA==.',
Or='Orthos:BAACLgAFFH8NAAIDAAQJmx6lNAB/AQADAAQJmx6lNAB/AQAuAAQKfzUAAgMACQlXJT0DAGkDAAMACQlXJT0DAGkDAAAA.Orwenya:BAABLgAECn8VAAIMAAYJ0g9tHAAIAQAMAAYJ0g9tHAAIAQAAAA==.',
Os='Osten:BAABLgAECn8ZAAINAAgJOw8+MgCCAQANAAgJOw8+MgCCAQAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAFAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Po='Porkit:BAAALgAFFAIJAwAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAABLgAFFH8FAAImAAIJfAy/LgCHAAAmAAIJfAy/LgCHAAAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgcJDgAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Reddacted:BAAALgADCgcJDAAAAA==.Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8eAAIBAAgJ1hjAAQAAAgABAAgJ1hjAAQAAAgAuAAQKfzsAAgEACQnBJsoAAIEDAAEACQnBJsoAAIEDAAAA.Respect:BAAALgAECgIJAgAAAA==.Rexam:BAAALgAECgIJAgABLgAECgcJGAAcAEUjAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAABLgAECn8rAAIgAAgJVBzKDgAxAgAgAAgJVBzKDgAxAgAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAABLgAECn8xAAIgAAgJuCEjBwCsAgAgAAgJuCEjBwCsAgAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8bAAMUAAYJ5A8zCQBZAQAUAAYJ5A8zCQBZAQATAAYJownpywDyAAAAAA==.',
['Rè']='Rènza:BAAALgAFFAMJBAAAAA==.',
Sa='Saelybrosa:BAAALgAECgcJDAAAAA==.Salphir:BAAALgAECgUJBQABLgAECgYJFQAMANIPAA==.Samsara:BAAALgAECgQJBwAAAA==.Saphyr:BAEBLgAFFH8IAAIXAAUJeyASDwBxAQAXAAUJeyASDwBxAQABLgAFFAcJFgAJAJshAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Senniel:BAAALgAECgUJCwAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabit:BAAALgADCgUJBgABLgAFFAIJAwAFAAAAAA==.Shadda:BAABLgAECn8UAAIOAAYJ/BWyJQATAQAOAAYJ/BWyJQATAQAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8HAAIdAAIJXg2FPwB6AAAdAAIJXg2FPwB6AAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECgcJDgAFAAAAAA==.Shinru:BAABLgAECn8WAAMNAAkJbhhKKwCrAQANAAgJCxdKKwCrAQAKAAYJlh4TkgBDAQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAABLgAFFH8MAAIXAAMJ0xqqHgDhAAAXAAMJ0xqqHgDhAAAAAA==.',
Si='Sickdayze:BAABLgAECn8cAAINAAkJcR5NDADAAgANAAkJcR5NDADAAgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sikkunt:BAAALgAECgEJAwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.Skyrain:BAAALgAECgQJBQAAAA==.',
Sl='Slootin:BAAALgAECgEJAgAAAA==.Slyxxar:BAACLgAFFH8OAAILAAQJwQr7PwDSAAALAAQJwQr7PwDSAAAuAAQKfxwABAwACAkaF6kQAJoBAAwACAkaF6kQAJoBAB0ABgnBEexRAP8AAAsAAQl4AVWrAB8AAAAA.',
Sm='Smarc:BAABLgAECn9CAAIfAAkJcR/wAwDwAgAfAAkJcR/wAwDwAgAAAA==.Smashtokhan:BAAALgAECgUJCQAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8WAAIEAAcJkxo6BgCEAgAEAAcJkxo6BgCEAgAuAAQKfxgAAwQABwlsIlgnABkCAAQABwlsIlgnABkCAAEAAgmjFqx/AD0AAAAA.Sophie:BAACLgAFFH8PAAMKAAQJwCH9HgB1AQAKAAQJwCH9HgB1AQANAAEJ2w3USAAzAAAuAAQKfxwAAwoACAmwHOhKANsBAAoACAmwHOhKANsBAA0ABgkuDlNKAE8BAAEuAAUUBwkWAAQAkxoA.Sophievokie:BAAALgAECgQJCwABLgAFFAcJFgAEAJMaAA==.Sophisticate:BAABLgAFFH8QAAIfAAQJnB6gCwBaAQAfAAQJnB6gCwBaAQABLgAFFAcJFgAEAJMaAA==.Sophiz:BAAALgAECgYJDwABLgAFFAcJFgAEAJMaAA==.Sophlax:BAACLgAFFH8TAAIYAAUJLySjAQCpAQAYAAUJLySjAQCpAQAuAAQKfxkAAhgACQnLIA8EABQDABgACQnLIA8EABQDAAEuAAUUBwkWAAQAkxoA.Sophs:BAACLgAFFH8IAAILAAQJkBg5KwAeAQALAAQJkBg5KwAeAQAuAAQKfxQAAwsABgnGHHNQAGIBAAsABgnGHHNQAGIBAB0ABAl2EclaANkAAAEuAAUUBwkWAAQAkxoA.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAACLgAFFH8IAAIOAAMJWB/uDAAQAQAOAAMJWB/uDAAQAQAuAAQKfzAAAg4ACQkmIYwCAAcDAA4ACQkmIYwCAAcDAAAA.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAMJAwAFAAAAAA==.',
Sp='Spicynoodle:BAABLgAECn8WAAICAAkJShVPKwAlAgACAAkJShVPKwAlAgAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAABLgAECn8dAAIRAAUJiyXvIwChAQARAAUJiyXvIwChAQAAAA==.',
Sq='Squattinchop:BAABLgAECn8eAAIHAAYJQiH3FQA6AgAHAAYJQiH3FQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJHgAHAEIhAA==.',
St='Stiffcrit:BAAALgAECgkJBwAAAA==.Stinkydh:BAABLgAECn8SAAIcAAYJMhFNcwBLAQAcAAYJMhFNcwBLAQAAAA==.Stryx:BAAALgADCgcJBwABLgAECgcJEgAFAAAAAA==.',
Su='Suji:BAABLgAECn8iAAIDAAkJXiDLEQDXAgADAAkJXiDLEQDXAgAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAFAAAAAA==.Supabird:BAAALgAECgQJBAAAAA==.Supergogeta:BAABLgAECn8yAAQEAAkJ3R9yDgDGAgAEAAgJsyByDgDGAgABAAIJkA+waQBqAAAOAAEJiQQ9NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgkJEQAAAA==.Synistër:BAAALgAECgEJAQAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôcôld:BAAALgADCgQJBAAAAA==.',
Ta='Takoda:BAAALgAECggJEAAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAABLgAECn8VAAICAAkJMwiRWwCGAQACAAkJMwiRWwCGAQAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tarkuun:BAAALgAECgkJCAAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBwAAAA==.',
Th='Thorish:BAABLgAECn8kAAInAAkJ5CGrAwDbAgAnAAkJ5CGrAwDbAgAAAA==.Thrayne:BAAALgADCgUJBgAAAA==.',
Ti='Tiddyweaver:BAAALgAECgYJEQABLgAECgkJHwAaAEcfAA==.Timbit:BAABLgAECn8jAAIHAAgJfQmhMwBTAQAHAAgJfQmhMwBTAQAAAA==.Tinfoiltotem:BAAALgADCgYJBwAAAA==.Tinybubbles:BAABLgAECn8lAAMLAAgJDhZBRACOAQALAAgJDhZBRACOAQAdAAQJKw2XXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJEAAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgcJDwAFAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8dAAMZAAkJGxhtFwAMAgAZAAkJGxhtFwAMAgARAAEJvwc4iAAqAAAAAA==.',
Tr='Travvy:BAAALgAECgQJBAABLgAFFAgJMAAgAIMiAA==.Trooth:BAAALgADCgYJBgABLgAECgUJDAAFAAAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgYJCgAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgkJCwAAAA==.',
Ty='Tyranis:BAEALgAECgYJCQAAAA==.Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAABLgAECn8XAAMaAAkJFw03EQCuAQAaAAkJFw03EQCuAQAbAAYJRAhpWgC+AAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Va='Vael:BAABLgAECn8iAAIcAAgJRxKOUgCCAQAcAAgJRxKOUgCCAQAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8pAAMXAAkJuBTYJAAhAQADAAcJ9RY4lQA0AQAXAAgJ+g7YJAAhAQAAAA==.Valériana:BAAALgADCgEJAQAAAA==.',
Ve='Vee:BAABLgAECn8fAAMoAAgJ+yOzEQBhAgAoAAgJ+yOzEQBhAgAmAAEJnBXmOwBBAAAAAA==.Veyla:BAEALgADCgcJDgABLgAECgYJBwAFAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAACLgAFFH8GAAIDAAMJBws/nQDMAAADAAMJBws/nQDMAAAuAAQKfyQAAgMACQlzFpB6AGUBAAMACQlzFpB6AGUBAAAA.',
Wa='Warkdom:BAAALgAECgUJCAAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAACLgAFFH8KAAIeAAMJayNyDwAlAQAeAAMJayNyDwAlAQAuAAQKfyYAAh4ACAlpJDAFALwCAB4ACAlpJDAFALwCAAAA.',
Wh='Wheelchair:BAEALgADCgYJBgABLgAECgYJBwAFAAAAAA==.',
Wi='Wickeddemon:BAABLgAECn8iAAIWAAgJDRODGwCRAQAWAAgJDRODGwCRAQAAAA==.Wildcanadian:BAAALgAECgIJAgAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
Wk='Wk:BAAALgAECgEJAQAAAA==.',
Wo='Wokstar:BAAALgAECgEJAgAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAINAAkJxhSPKAC9AQANAAkJxhSPKAC9AQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJIgAEAGgXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAACLgAFFH8LAAIcAAQJSRMFQAAXAQAcAAQJSRMFQAAXAQAuAAQKfyoAAhwACQkYICIQALgCABwACQkYICIQALgCAAAA.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8WAAIkAAUJGiC4AACxAQAkAAUJGiC4AACxAQAuAAQKfxYAAiQACAnDInIEANUCACQACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zacariana:BAAALgADCgcJBwAAAA==.Zaftenpuff:BAAALgAECgQJBAAAAA==.Zandashami:BAAALgAECggJCAAAAA==.Zarya:BAAALgAECgcJEgAAAA==.',
Ze='Zelgie:BAABLgAECn8rAAMnAAkJ7BErEgCYAQAnAAkJ7BErEgCYAQANAAUJ6BCOTgD0AAAAAA==.',
Zi='Zimzim:BAABLgAECn8WAAIIAAgJVBGzMACgAQAIAAgJVBGzMACgAQAAAA==.',
Zo='Zorsse:BAAALgAECgQJAwABLgAECggJHwAoAN0XAA==.',
Zu='Zulu:BAABLgAECn8VAAIJAAYJkBxUJQB6AQAJAAYJkBxUJQB6AQAAAA==.',
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
