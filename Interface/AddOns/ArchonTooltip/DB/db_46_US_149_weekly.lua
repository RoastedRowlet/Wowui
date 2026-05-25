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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Rogue-Outlaw','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Paladin-Retribution','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Hunter-Survival','Rogue-Assassination','Mage-Frost','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','Shaman-Elemental','Warlock-Affliction','Hunter-Marksmanship','Evoker-Devastation','Druid-Feral','DemonHunter-Vengeance','Rogue-Subtlety','Druid-Guardian','Paladin-Protection','Priest-Discipline','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAYJEQABAF0iAA==.',
Ab='Abadizzo:BAAALgAECgcJBwAAAA==.Abadizzoo:BAABLgAECn8qAAICAAkJtyHQDQC9AgACAAkJtyHQDQC9AgAAAA==.Abilities:BAAALgAECgYJDAAAAA==.',
Ac='Ace:BAAALgAFFAEJAQAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAAALgAECgYJEgABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8sAAIEAAkJUiTUBABAAwAEAAkJUiTUBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAECgIJAgAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airwrecka:BAACLgAFFH8IAAIBAAMJ3RT8IgDdAAABAAMJ3RT8IgDdAAAuAAQKfzEAAgEACQnEHlMJAJoCAAEACQnEHlMJAJoCAAAA.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
Al='Aleara:BAAALgAECgQJBAAAAA==.Alexian:BAABLgAECn8ZAAIGAAgJERK0BwCZAQAGAAgJERK0BwCZAQAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAAALgAECgcJEgAAAA==.',
Am='Amebeliever:BAABLgAECn8fAAQHAAgJiB8ZFQBDAgAHAAcJuB4ZFQBDAgAIAAcJAgi/NwAMAQAJAAQJ/gmMWgCCAAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgkJFgAAAA==.',
Ar='Arahgon:BAABLgAECn8UAAIKAAcJLRQZigA7AQAKAAcJLRQZigA7AQABLgAECgUJBgAFAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asphodelos:BAAALgAECgYJDQABLgAFFAQJBQADAAEcAA==.Asukà:BAABLgAECn8yAAMLAAgJnBa2IQAXAgALAAgJnBa2IQAXAgAMAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAgAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJHAANAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgADCgEJAQABLgAECgYJFQAMANIPAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAAALgAECgcJEwABLgAFFAMJBQAOAJkRAA==.Bellarg:BAABLgAECn81AAMPAAgJphgFNwDkAQAPAAgJphgFNwDkAQAQAAMJ3wetSACUAAAAAA==.Belobog:BAAALgAECgUJDQABLgAECggJHAADALsPAA==.Belyn:BAAALgAECgcJDgAAAA==.Benmage:BAAALgAECgUJBQAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bifesor:BAAALgAFFAIJAgAAAA==.Bigfaust:BAABLgAECn8YAAQJAAcJqB+rJgBbAQAJAAUJpx+rJgBbAQAIAAUJABu/LgBDAQAHAAIJRR8IUwDFAAAAAA==.',
Bl='Blackbudro:BAABLgAECn8yAAIRAAkJ3hk0CQBxAgARAAkJ3hk0CQBxAgAAAA==.Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAAALgAECgcJEwAAAA==.Bluespider:BAAALgAECgYJCQAAAA==.',
Bo='Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAABLgAECn8WAAMIAAcJpRrsFgAKAgAIAAcJpRrsFgAKAgAHAAQJBiM+LAAxAQABLgAFFAcJDgAEALMUAA==.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Brolich:BAAALgAECggJEgABLgAECgQJBwAFAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJEQAAAA==.Calculusx:BAABLgAECn8tAAISAAkJUCPBAAAZAwASAAkJUCPBAAAZAwAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8gAAMTAAYJ+RtBBAAtAgATAAYJrhtBBAAtAgAUAAIJmRvzAQCiAAAuAAQKfzcABBMACQkrJgsFALEDABMACQn7JQsFALEDABUACQnjIeECAAUCABQAAwnIIqMJAMAAAAAA.',
Ch='Champu:BAAALgADCgEJAQAAAA==.Chaoticx:BAAALgADCgQJBAAAAA==.Charlotte:BAAALgAECgcJDgAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn8vAAIJAAkJ6yCPAwD9AgAJAAkJ6yCPAwD9AgABLgAFFAMJBQAOAJkRAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAFAAAAAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAAALgAECgcJDgAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgTSQAYAgADAAgJ1BgTSQAYAgABLgAECgkJCQAFAAAAAA==.Combatboots:BAABLgAECn8xAAIWAAkJnxBvEwDBAQAWAAkJnxBvEwDBAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMJAAYJ2Rs0LwCaAQAJAAUJGhw0LwCaAQAHAAYJsRShNwBAAQAAAA==.Darilol:BAAALgADCgYJBgABLgAECgYJFQAMANIPAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn8qAAIXAAcJECPTCgA1AgAXAAcJECPTCgA1AgAAAA==.Debra:BAACLgAFFH8GAAIWAAMJlAuVEgDOAAAWAAMJlAuVEgDOAAAuAAQKfy0AAhYACQnCG5QLADcCABYACQnCG5QLADcCAAAA.Debz:BAAALgAECgcJCAAAAA==.Deegee:BAABLgAECn8cAAMYAAYJ3yKiDwBIAgAYAAYJ3yKiDwBIAgAZAAYJvBjTJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAgAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJAgAAAA==.Demize:BAAALgAECgYJBwAAAA==.Demonflame:BAABLgAECn8nAAIQAAkJDxa/BAAAAgAQAAkJDxa/BAAAAgAAAA==.Demíze:BAAALgADCgEJAQAAAA==.Deshield:BAAALgAECgcJBwABLgAFFAQJFgALAAQmAA==.Deus:BAABLgAECn8bAAITAAkJexDUWQCzAQATAAkJexDUWQCzAQAAAA==.Dewry:BAAALgAECgYJEwAAAA==.',
Dh='Dhudamuthi:BAABLgAECn8zAAIJAAkJeiQpAgArAwAJAAkJeiQpAgArAwAAAA==.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwoof:BAAALgAECgYJDAAAAA==.Dizzo:BAAALgAECgkJAQAAAA==.',
Do='Donnajuan:BAABLgAECn8xAAMNAAkJrRoyDACnAgANAAkJrRoyDACnAgAKAAEJ2QOleAEnAAAAAA==.Dornath:BAABLgAECn8tAAIKAAgJwQ+bZwCAAQAKAAgJwQ+bZwCAAQAAAA==.',
Dr='Draaxelro:BAABLgAECn8bAAICAAkJ9RD5RQCjAQACAAkJ9RD5RQCjAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAQJFgALAAQmAA==.Dragontiddys:BAABLgAECn8fAAMaAAgJRx9gBADGAgAaAAgJRx9gBADGAgAbAAEJJBZIdgBCAAAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAFAAAAAA==.Drim:BAAALgADCgMJAwAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Eldread:BAAALgADCgEJAQAAAA==.Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8xAAIZAAkJxwrXIQCQAQAZAAkJxwrXIQCQAQAAAA==.Elinalise:BAAALgAFFAEJAgABLgAFFAYJHQAcAGgOAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAACLgAFFH8FAAICAAIJkRNYIQBeAAACAAIJkRNYIQBeAAAuAAQKfy4AAgIACAkkIMQOAMUCAAIACAkkIMQOAMUCAAAA.',
Em='Embertal:BAAALgAECgYJEAAAAA==.Emvoi:BAAALgADCgUJBQAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgcJDgAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.Enzo:BAAALgAECgEJAQAAAA==.',
Ev='Evién:BAABLgAECn8UAAMdAAYJNxZEOQBrAQAdAAYJNxZEOQBrAQALAAUJthFMbgDXAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Executè:BAAALgAECgEJAgABLgAECggJGAAWAEAjAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.Faustus:BAAALgADCgMJAwAAAA==.',
Fe='Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8oAAIKAAgJtQcgjQA2AQAKAAgJtQcgjQA2AQAAAA==.',
Fi='Fiammetta:BAECLgAFFH8MAAIOAAQJgiJdCQBaAQAOAAQJgiJdCQBaAQAuAAQKfxgAAg4ACQlrIwQKAC0CAA4ACQlrIwQKAC0CAAEuAAUUBwkWAAkAmyEA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Finke:BAABLgAECn8bAAITAAcJZhzrZwAHAgATAAcJZhzrZwAHAgAAAA==.Fishmärket:BAABLgAECn8iAAIMAAkJYA88CwDLAQAMAAkJYA88CwDLAQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJBAAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Frostie:BAABLgAFFH8FAAMXAAMJgwvZNwAAAAADAAIJgwvrswCJAAAXAAEJAADZNwAAAAABLgAFFAUJDgAKANcRAA==.Frís:BAAALgAECggJEwABLgAFFAMJBgAXAB0WAA==.',
Fu='Furryfist:BAAALgADCgcJCAAAAA==.',
Ga='Galarine:BAABLgAECn8sAAIPAAkJiRjVIABHAgAPAAkJiRjVIABHAgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAFFAMJBQAOAJkRAA==.Gilrathor:BAAALgAECggJDAAAAA==.Gizzlit:BAABLgAECn8jAAIMAAgJ6BpWCAAMAgAMAAgJ6BpWCAAMAgAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAECgUJBgAAAA==.Gofetch:BAABLgAECn8hAAICAAkJsBugHwA/AgACAAkJsBugHwA/AgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAFAAAAAA==.',
Gr='Grandgoop:BAAALgADCgMJAwAAAA==.Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8mAAMCAAgJOR0wJwAYAgACAAgJOR0wJwAYAgARAAUJ+hL5GAA/AQAAAA==.',
Gu='Guppy:BAAALgAECgQJBAAAAA==.Gutcassidy:BAAALgAECgMJAwAAAA==.',
Ha='Hac:BAAALgAECgcJEQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAFAAAAAA==.Harpö:BAAALgAECgEJAQABLgAECgYJBgAFAAAAAA==.',
He='Healingkiss:BAABLgAECn8fAAIYAAgJGwJjPQDXAAAYAAgJGwJjPQDXAAAAAA==.Heatup:BAABLgAECn8aAAITAAgJfiMzFQApAwATAAgJfiMzFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Ho='Hollypallz:BAAALgADCgEJAQAAAA==.Holymages:BAABLgAECn8hAAITAAgJphvwRQDuAQATAAgJphvwRQDuAQAAAA==.Homtardy:BAAALgAECgYJDAAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.Hunkomonk:BAAALgADCgkJCQABLgAECgkJJwAKABcgAA==.',
Il='Ilyanna:BAABLgAECn8lAAMeAAkJgh3XAwA3AgAeAAkJgh3XAwA3AgAPAAEJXxDXCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8cAAQRAAgJtxUsAQAVAgARAAcJPBQsAQAVAgAfAAYJARqKBgC3AQACAAEJPRPaIgBaAAAuAAQKfyUAAh8ACAmyJDgGADkDAB8ACAmyJDgGADkDAAAA.Imabadshot:BAAALgADCgUJBQAAAA==.Imscary:BAAALgADCgMJAwAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgcJDgAFAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECgkJMQAWAJ8QAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.',
Jh='Jhalse:BAAALgAECgQJBAAAAA==.Jhoppss:BAABLgAECn8WAAMgAAYJlx1rDwDkAQAgAAYJlx1rDwDkAQAbAAQJjQ9vXgCQAAAAAA==.',
Ji='Jiinxx:BAAALgAECgIJAwAAAA==.Jillià:BAAALgAFFAIJAwAAAA==.Jimpossible:BAAALgAECgQJBAAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Karls:BAAALgAECgYJDgAAAA==.',
Ke='Keez:BAAALgAECgcJDwAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kej:BAAALgAECgIJAgAAAA==.Kerafyrm:BAABLgAECn8zAAMaAAgJwx9mBADFAgAaAAgJwx9mBADFAgAbAAMJQRxdYQCFAAAAAA==.Kerrigan:BAACLgAFFH8dAAIcAAYJaA7HHwBqAQAcAAYJaA7HHwBqAQAuAAQKfzMAAhwACQn4HlURAJsCABwACQn4HlURAJsCAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJHAANAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8iAAMEAAkJaBd5JAAoAgAEAAkJaBd5JAAoAgAhAAEJPRBUMQA+AAAAAA==.Kozand:BAAALgAECgQJBAABLgAECgYJFQAMANIPAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgADCggJFwAAAA==.',
Ky='Kyirr:BAABLgAECn8fAAMgAAkJgxlNDAAWAgAgAAcJQRpNDAAWAgAbAAUJFxgZPQAOAQAAAA==.Kyralen:BAABLgAECn8cAAMNAAYJHSPEGABMAgANAAYJHSPEGABMAgAKAAIJVxMCCwF3AAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAIMAAkJiRVRCgAsAgAMAAkJiRVRCgAsAgAAAA==.',
Li='Lilchithead:BAAALgAECgYJCgAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8WAAIJAAcJmyEeAgBIAgAJAAcJmyEeAgBIAgAuAAQKfy0AAgkACQnqJSUBAK0DAAkACQnqJSUBAK0DAAAA.Lividea:BAAALgADCgcJDQAAAA==.Livinglover:BAAALgADCgUJAwAAAA==.',
Ll='Llela:BAAALgAECgcJCAAAAA==.Llynryn:BAABLgAECn8WAAIZAAgJ8A6EMwBLAQAZAAgJ8A6EMwBLAQAAAA==.',
Lo='Locktua:BAAALgAECgcJCAAAAA==.',
Ly='Lympha:BAABLgAFFH8JAAMLAAMJ1x09JAAaAQALAAMJ1x09JAAaAQAMAAEJowFxEQA2AAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAcJFAAcAHUbAA==.Magicmanzz:BAAALgAECggJEgAAAA==.Magnifuso:BAAALgAECgYJEAAAAA==.Maguapa:BAAALgAECgQJBwAAAA==.Malgata:BAAALgADCgkJFgAAAA==.Margarita:BAAALgAECgUJCwAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8IAAINAAMJIRd6JADOAAANAAMJIRd6JADOAAAuAAQKfy4AAw0ACQnbHwUVAD8CAA0ABwkNHwUVAD8CAAoACAntGdo3AAICAAAA.',
Mc='Mcplucky:BAAALgAECgQJBQAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Mikio:BAABLgAECn8cAAIBAAgJYw7zKABZAQABAAgJYw7zKABZAQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8uAAIYAAkJLRxTCADCAgAYAAkJLRxTCADCAgAAAA==.',
Mo='Moardottz:BAABLgAECn8dAAIPAAYJPxW+cgB5AQAPAAYJPxW+cgB5AQABLgAECgUJBQAFAAAAAA==.Moiryn:BAACLgAFFH8NAAILAAUJKRLdFgBnAQALAAUJKRLdFgBnAQAuAAQKfykAAwsACAn9G54ZAEoCAAsACAn9G54ZAEoCAB0AAQlxD6SHADEAAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Naturals:BAAALgAECgEJAwAAAA==.Navillus:BAACLgAFFH8cAAIaAAcJ6g+XBwD2AQAaAAcJ6g+XBwD2AQAuAAQKf0cAAxoACQnvFMEMAGoCABoACQnvFMEMAGoCACAABwkHItwIAFUCAAAA.',
No='Norasoul:BAABLgAECn8wAAMcAAkJ5hssEwCMAgAcAAkJ5hssEwCMAgAiAAcJ2BR6CwB4AQAAAA==.',
Og='Ogron:BAACLgAFFH8WAAMLAAQJBCaqDAC7AQALAAQJBCaqDAC7AQAdAAEJcx/FGwBTAAAuAAQKfzkAAx0ACQl8JRAEAF4DAB0ACQl8JRAEAF4DAAsAAwknIKB9AKgAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgADCgQJBAAAAA==.',
Op='Ophindis:BAAALgAECgcJDwAAAA==.',
Or='Orthos:BAACLgAFFH8FAAIDAAQJARzUKwBwAQADAAQJARzUKwBwAQAuAAQKfyUAAgMACQlDIzEMAOwCAAMACQlDIzEMAOwCAAAA.Orwenya:BAABLgAECn8VAAIMAAYJ0g9vFwAJAQAMAAYJ0g9vFwAJAQAAAA==.',
Os='Osten:BAAALgAECgcJEQAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAFAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Po='Porkit:BAAALgAFFAIJAgAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAAALgAFFAIJBAAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgcJDgAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Reddacted:BAAALgADCgcJDAAAAA==.Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8eAAIBAAgJ1hjAAQAAAgABAAgJ1hjAAQAAAgAuAAQKfzsAAgEACQnBJoEAAIYDAAEACQnBJoEAAIYDAAAA.Respect:BAAALgAECgIJAgAAAA==.Rexam:BAAALgAECgIJAgABLgAECgcJFAAcAB8jAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAABLgAECn8hAAIjAAgJiRo6DgAgAgAjAAgJiRo6DgAgAgAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAABLgAECn8hAAIjAAgJLhzQDAAzAgAjAAgJLhzQDAAzAgAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8bAAMUAAYJ5A8zCQBZAQAUAAYJ5A8zCQBZAQATAAYJowl0uAD4AAAAAA==.',
['Rè']='Rènza:BAAALgAFFAIJAwAAAA==.',
Sa='Saelybrosa:BAAALgAECgcJCgAAAA==.Samsara:BAAALgAECgQJBAAAAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Senniel:BAAALgAECgQJBQAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabit:BAAALgADCgUJBgABLgAFFAIJAwAFAAAAAA==.Shadda:BAABLgAECn8UAAIkAAYJ/BX+HQAaAQAkAAYJ/BX+HQAaAQAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8HAAIdAAIJXg30MQCKAAAdAAIJXg30MQCKAAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECgcJDgAFAAAAAA==.Shinru:BAABLgAECn8WAAMNAAkJbhj6JQCyAQANAAgJCxf6JQCyAQAKAAYJlh79gABMAQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAABLgAFFH8GAAIXAAMJHRadGwDMAAAXAAMJHRadGwDMAAAAAA==.',
Si='Sickdayze:BAABLgAECn8cAAINAAkJcR7nCQDIAgANAAkJcR7nCQDIAgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.Skyrain:BAAALgADCgcJEgAAAA==.',
Sl='Slootin:BAAALgAECgEJAQAAAA==.Slyxxar:BAACLgAFFH8JAAILAAMJTg2PPQC6AAALAAMJTg2PPQC6AAAuAAQKfxwABAwACAkaF48NAKABAAwACAkaF48NAKABAB0ABgnBEexRAP8AAAsAAQl4AVWrAB8AAAAA.',
Sm='Smashtokhan:BAAALgAECgUJCAAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8OAAIEAAcJsxQsBwAvAgAEAAcJsxQsBwAvAgAuAAQKfxgAAwQABwlsIlgnABkCAAQABwlsIlgnABkCAAEAAgmjFr5wAD0AAAAA.Sophie:BAACLgAFFH8KAAMKAAQJ9RvWJwBAAQAKAAQJ9RvWJwBAAQANAAEJ2w2BPgA4AAAuAAQKfxsAAwoACAmqHOs7ADQCAAoACAmqHOs7ADQCAA0ABgkuDlNKAE8BAAEuAAUUBwkOAAQAsxQA.Sophievokie:BAAALgAECgQJCwABLgAFFAcJDgAEALMUAA==.Sophisticate:BAABLgAFFH8MAAIRAAQJvRiKCwBQAQARAAQJvRiKCwBQAQABLgAFFAcJDgAEALMUAA==.Sophiz:BAAALgAECgYJDwABLgAFFAcJDgAEALMUAA==.Sophlax:BAACLgAFFH8TAAIYAAUJLySjAQCpAQAYAAUJLySjAQCpAQAuAAQKfxkAAhgACQnLIA8EABQDABgACQnLIA8EABQDAAEuAAUUBwkOAAQAsxQA.Sophs:BAAALgAFFAMJAwABLgAFFAcJDgAEALMUAA==.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAACLgAFFH8IAAIkAAMJWB+HCAAZAQAkAAMJWB+HCAAZAQAuAAQKfzAAAiQACQkmIesBAAwDACQACQkmIesBAAwDAAAA.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAMJAwAFAAAAAA==.',
Sp='Spicynoodle:BAABLgAECn8WAAICAAkJShWQIgAvAgACAAkJShWQIgAvAgAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAABLgAECn8dAAIZAAUJiyUDHwCmAQAZAAUJiyUDHwCmAQAAAA==.',
Sq='Squattinchop:BAABLgAECn8eAAIHAAYJQiH3FQA6AgAHAAYJQiH3FQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJHgAHAEIhAA==.',
St='Stiffcrit:BAAALgAECgkJBwAAAA==.Stinkydh:BAABLgAECn8SAAIcAAYJMhFNcwBLAQAcAAYJMhFNcwBLAQAAAA==.Stryx:BAAALgADCgcJBwABLgAECgcJEQAFAAAAAA==.',
Su='Suji:BAABLgAECn8iAAIDAAkJXiBrDQDhAgADAAkJXiBrDQDhAgAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAFAAAAAA==.Supabird:BAAALgAECgQJBAAAAA==.Supergogeta:BAABLgAECn8wAAQEAAgJUiFyDgDGAgAEAAcJfCJyDgDGAgABAAIJ+A5OYABjAAAkAAEJiQQ9NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgkJEQAAAA==.Synistër:BAAALgADCgMJAwAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
Ta='Takoda:BAAALgAECggJCgAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAAALgAECggJEgAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tarkuun:BAAALgAECgkJCAAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBwAAAA==.',
Th='Thorish:BAABLgAECn8kAAIlAAkJ5CGrAwDbAgAlAAkJ5CGrAwDbAgAAAA==.Thrayne:BAAALgADCgIJAgAAAA==.',
Ti='Tiddyweaver:BAAALgAECgUJDgABLgAECgkJHwAaAEcfAA==.Timbit:BAABLgAECn8jAAIHAAgJfQmhMwBTAQAHAAgJfQmhMwBTAQAAAA==.Tinfoiltotem:BAAALgADCgYJAQAAAA==.Tinybubbles:BAABLgAECn8gAAMLAAgJDhb6MwC0AQALAAgJDhb6MwC0AQAdAAQJKw2XXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJDwAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgcJDwAFAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8dAAMmAAkJGxgnEwAcAgAmAAkJGxgnEwAcAgAZAAEJvweedQAsAAAAAA==.',
Tr='Trooth:BAAALgADCgYJBgABLgAECgUJDAAFAAAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgYJCgAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgkJCgAAAA==.',
Ty='Tyranis:BAAALgAECgUJBgAAAA==.Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAABLgAECn8VAAMaAAgJ+A0oEgCDAQAaAAgJ+A0oEgCDAQAbAAYJRAhbTgDJAAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Va='Vael:BAABLgAECn8fAAIcAAgJRxLQSQCGAQAcAAgJRxLQSQCGAQAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8nAAMXAAgJphPSHwAlAQADAAYJ5xXfjwBgAQAXAAgJ+g7SHwAlAQAAAA==.Valériana:BAAALgADCgEJAQAAAA==.',
Ve='Vee:BAABLgAECn8fAAMnAAgJ+yPTDQBvAgAnAAgJ+yPTDQBvAgAoAAEJnBXmOwBBAAAAAA==.Veyla:BAEALgADCgcJDgABLgAECgYJBwAFAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAACLgAFFH8GAAIDAAMJBwuffQDYAAADAAMJBwuffQDYAAAuAAQKfyQAAgMACQlzFpFrAGkBAAMACQlzFpFrAGkBAAAA.',
Wa='Warkdom:BAAALgAECgUJCAAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAACLgAFFH8FAAIOAAMJhCArDwAOAQAOAAMJhCArDwAOAQAuAAQKfyMAAg4ABwmGI1EJAD0CAA4ABwmGI1EJAD0CAAAA.',
Wh='Wheelchair:BAEALgADCgYJBgABLgAECgYJBwAFAAAAAA==.',
Wi='Wickeddemon:BAABLgAECn8gAAIWAAgJPhJ2FwCTAQAWAAgJPhJ2FwCTAQAAAA==.Wildcanadian:BAAALgAECgIJAgAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
Wk='Wk:BAAALgAECgEJAQAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAINAAkJxhSdIwDCAQANAAkJxhSdIwDCAQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJIgAEAGgXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAABLgAECn8pAAIcAAkJGCAWDQDCAgAcAAkJGCAWDQDCAgAAAA==.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8WAAIhAAUJGiC4AACxAQAhAAUJGiC4AACxAQAuAAQKfxYAAiEACAnDInIEANUCACEACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zaftenpuff:BAAALgAECgQJBAAAAA==.Zandashami:BAAALgAECggJCAAAAA==.Zarya:BAAALgAECgcJEQAAAA==.',
Ze='Zelgie:BAABLgAECn8pAAMlAAgJXxH+EwBeAQAlAAgJXxH+EwBeAQANAAUJ6BBKRwD2AAAAAA==.',
Zi='Zimzim:BAAALgAECggJDwAAAA==.',
Zo='Zorsse:BAAALgAECgQJAwABLgAECggJHwAnAN0XAA==.',
Zu='Zulu:BAABLgAECn8VAAIJAAYJkByTIQB9AQAJAAYJkByTIQB9AQAAAA==.',
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
