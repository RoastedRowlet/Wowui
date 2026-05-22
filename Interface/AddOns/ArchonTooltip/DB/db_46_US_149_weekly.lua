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

local lookup = {'Druid-Balance','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Restoration','Unknown-Unknown','Rogue-Outlaw','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Paladin-Retribution','Shaman-Restoration','Shaman-Enhancement','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Hunter-Survival','Rogue-Assassination','Mage-Frost','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Evoker-Preservation','DemonHunter-Devourer','Shaman-Elemental','Warrior-Protection','Warlock-Affliction','Hunter-Marksmanship','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Rogue-Subtlety','Druid-Guardian','Paladin-Protection','Priest-Discipline','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaurum:BAEALgAECgYJBgABLgAFFAYJEQABAF0iAA==.',
Ab='Abadizzo:BAAALgAECgcJBwAAAA==.Abadizzoo:BAABLgAECn8qAAICAAkJuCFBCADcAgACAAkJuCFBCADcAgAAAA==.Abilities:BAAALgAECgUJBgAAAA==.',
Ac='Ace:BAAALgAECgQJBgAAAA==.',
Ae='Aeon:BAAALgAECgYJEgAAAA==.',
Ag='Agathe:BAAALgAECgYJEQABLgAECggJHAADALsPAA==.Agilio:BAABLgAECn8pAAIEAAkJDSTUBABAAwAEAAkJDSTUBABAAwAAAA==.',
Ah='Ahkimbo:BAAALgAECgIJAgAAAA==.',
Ai='Airhorns:BAAALgAECgQJAQAAAA==.Airwrecka:BAACLgAFFH8FAAIBAAMJFRTpHADjAAABAAMJFRTpHADjAAAuAAQKfzEAAgEACQnEHuQGAKMCAAEACQnEHuQGAKMCAAAA.Airyxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
Al='Alexian:BAABLgAECn8ZAAIGAAgJEhIjBgClAQAGAAgJEhIjBgClAQAAAA==.Alorin:BAAALgADCgcJCAAAAA==.Altlas:BAAALgAECgYJEAAAAA==.',
Am='Amebeliever:BAABLgAECn8fAAQHAAgJiB8ZFQBDAgAHAAcJuB4ZFQBDAgAIAAcJAgi/NwAMAQAJAAQJ/gltUQCCAAAAAA==.',
An='Andari:BAAALgAECgYJDAAAAA==.Anywhere:BAAALgADCgQJBAAAAA==.',
Ar='Arahgon:BAABLgAECn8UAAIKAAcJLRSZdQA3AQAKAAcJLRSZdQA3AQABLgAECgUJAwAFAAAAAA==.Arixana:BAAALgAECgUJBQAAAA==.Aryxana:BAAALgADCgEJAQABLgAECgUJBQAFAAAAAA==.',
As='Asher:BAAALgAECgQJBAAAAA==.Asphodelos:BAAALgAECgYJBgABLgAECggJIAADAJUhAA==.Asukà:BAABLgAECn8kAAMLAAgJxhR0HgACAgALAAgJxhR0HgACAgAMAAYJ7AoeFwBPAQAAAA==.',
At='Attero:BAAALgAECgEJAgAAAA==.',
Au='Auchenile:BAAALgADCgYJBgABLgAECgYJFgANAB0jAA==.',
Av='Aveliese:BAAALgAECgYJDgAAAA==.',
Aw='Awilix:BAAALgAECgcJCgAAAA==.',
['Aé']='Aéd:BAAALgADCgEJAQABLgAECgUJDwAFAAAAAA==.',
Be='Beans:BAAALgAECgEJAQAAAA==.Bearhugzz:BAAALgAECgcJEwABLgAFFAIJAgAFAAAAAA==.Bellarg:BAABLgAECn80AAMOAAgJpxhxLQDkAQAOAAgJpxhxLQDkAQAPAAMJ3wetSACUAAAAAA==.Belobog:BAAALgAECgUJCAABLgAECggJHAADALsPAA==.Belyn:BAAALgAECgUJCwAAAA==.Benmage:BAAALgAECgIJAgAAAA==.Benzo:BAAALgAECgUJDAAAAA==.Beoworgen:BAAALgADCgIJAgAAAA==.',
Bi='Bifesor:BAAALgAECggJCwAAAA==.Bigfaust:BAABLgAECn8YAAQJAAcJph88IQBgAQAJAAUJpx88IQBgAQAIAAUJARu/LgBDAQAHAAIJRR8IUwDFAAAAAA==.',
Bl='Blackbudro:BAABLgAECn8pAAIQAAkJYReFCQBHAgAQAAkJYReFCQBHAgAAAA==.Blocka:BAAALgADCgIJAgAAAA==.Bloodadinz:BAAALgAECgcJEgAAAA==.Bluespider:BAAALgAECgIJBAAAAA==.',
Bo='Bonedaddy:BAAALgADCgMJAwAAAA==.',
Br='Bratlax:BAAALgAECgcJEgABLgAFFAYJDQAEADIWAA==.Brawnie:BAAALgAECgYJBgAAAA==.Bro:BAAALgAECgQJBwAAAA==.Brokai:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.Brolich:BAAALgAECgcJDgABLgAECgQJBwAFAAAAAA==.',
Bu='Bumpus:BAAALgAECgIJAgAAAA==.',
Ca='Caarcus:BAAALgAECgcJEQAAAA==.Calculusx:BAABLgAECn8tAAIRAAkJUiORAAAoAwARAAkJUiORAAAoAwAAAA==.Cass:BAAALgAECgMJAwAAAA==.',
Ce='Cellice:BAACLgAFFH8gAAMSAAYJ+RtBBAAtAgASAAYJrhtBBAAtAgATAAIJmRtoAQC0AAAuAAQKfzYABBIACQkrJgsFALEDABIACQn7JQsFALEDABQACAkSIuECAAUCABMAAwm/Iq4IAMMAAAAA.',
Ch='Champu:BAAALgADCgEJAQAAAA==.Charlotte:BAAALgAECgcJDgAAAA==.Cheatus:BAAALgADCgMJAwAAAA==.Checkursix:BAAALgAECgcJBgAAAA==.Chipcoffey:BAAALgADCgEJAQAAAA==.Chris:BAAALgAECgQJBAAAAA==.Chuckborris:BAABLgAECn8kAAIJAAgJPB6gCgBQAgAJAAgJPB6gCgBQAgABLgAFFAIJAgAFAAAAAA==.Chuttbeeks:BAAALgAECgIJBAABLgAECgYJCwAFAAAAAA==.',
Cl='Claytnbigsby:BAAALgADCgMJAwAAAA==.Cloúd:BAAALgAECgUJDAAAAA==.',
Co='Coleco:BAABLgAECn8XAAIDAAgJ1BgTSQAYAgADAAgJ1BgTSQAYAgABLgAECgkJCQAFAAAAAA==.Combatboots:BAABLgAECn8mAAIVAAgJywvpGQBJAQAVAAgJywvpGQBJAQAAAA==.',
Cr='Crosshairs:BAAALgAECgEJAQAAAA==.',
Da='Daddydimes:BAABLgAECn8aAAMJAAYJ2Rs0LwCaAQAJAAUJGhw0LwCaAQAHAAYJsRShNwBAAQAAAA==.',
De='Deamonprince:BAAALgADCgkJFQAAAA==.Deathless:BAABLgAECn8jAAIWAAcJECOACABCAgAWAAcJECOACABCAgAAAA==.Debra:BAACLgAFFH8FAAIVAAMJlAueDgDZAAAVAAMJlAueDgDZAAAuAAQKfy0AAhUACQnCGw4JAD8CABUACQnCGw4JAD8CAAAA.Debz:BAAALgAECgcJCAAAAA==.Deegee:BAABLgAECn8WAAMXAAYJgSEpEQARAgAXAAYJgSEpEQARAgAYAAYJvBjTJgChAQAAAA==.Deliveryboy:BAAALgAECgEJAQAAAA==.Delphist:BAAALgAECgEJAQAAAA==.Demiize:BAAALgAECgEJAQAAAA==.Demize:BAAALgAECgQJBAAAAA==.Demonflame:BAABLgAECn8hAAIPAAkJuBXqAwD+AQAPAAkJuBXqAwD+AQAAAA==.Deshield:BAAALgADCgQJBAABLgAFFAQJEgALAGslAA==.Deus:BAABLgAECn8ZAAISAAgJKRKFZAB0AQASAAgJKRKFZAB0AQAAAA==.Dewry:BAAALgAECgYJDQAAAA==.',
Dh='Dhudamuthi:BAABLgAECn8qAAIJAAkJciQyAgAWAwAJAAkJciQyAgAWAwAAAA==.',
Di='Dimes:BAAALgAECgIJAgAAAA==.Direwoof:BAAALgAECgYJDAAAAA==.Dizzo:BAAALgAECgkJAQAAAA==.',
Do='Donnajuan:BAABLgAECn8xAAMNAAkJrRrdCAC4AgANAAkJrRrdCAC4AgAKAAEJ2QOsTQEnAAAAAA==.Dornath:BAABLgAECn8lAAIKAAcJyA3IdgA1AQAKAAcJyA3IdgA1AQAAAA==.',
Dr='Draaxelro:BAABLgAECn8ZAAICAAgJVhJ1SwBlAQACAAgJVhJ1SwBlAQAAAA==.Dragonboufas:BAAALgADCgYJBgABLgAFFAQJEgALAGslAA==.Dragontiddys:BAABLgAECn8ZAAIZAAgJgh1zBACgAgAZAAgJgh1zBACgAgAAAA==.Drew:BAEALgADCgUJBQABLgAECgYJCgAFAAAAAA==.',
Du='Durge:BAAALgAECgEJAQAAAA==.',
El='Eldread:BAAALgADCgEJAQAAAA==.Elias:BAAALgADCgQJBAAAAA==.Elimere:BAABLgAECn8mAAIYAAkJzQlfIwBXAQAYAAkJzQlfIwBXAQAAAA==.Elinalise:BAAALgAFFAEJAgABLgAFFAYJGAAaAIwNAA==.Elminstér:BAAALgAECgQJCQAAAA==.Elvarg:BAAALgADCgEJAQAAAA==.Elywen:BAACLgAFFH8FAAICAAIJkRNYIQBeAAACAAIJkRNYIQBeAAAuAAQKfy4AAgIACAkkIMQOAMUCAAIACAkkIMQOAMUCAAAA.',
Em='Embertal:BAAALgAECgYJCgAAAA==.Emvoi:BAAALgADCgUJBQAAAA==.',
En='Ena:BAAALgADCgYJBgAAAA==.Enfuegó:BAAALgAECggJDgAAAA==.Enry:BAAALgAECgYJDgAAAA==.Enshaendor:BAAALgAECgYJCQAAAA==.Enzo:BAAALgAECgEJAQAAAA==.',
Ev='Evién:BAABLgAECn8UAAMbAAYJNxZEOQBrAQAbAAYJNxZEOQBrAQALAAUJthE8XQDaAAAAAA==.Evve:BAAALgADCgIJAgAAAA==.',
Ex='Executè:BAAALgAECgEJAQABLgAECggJGAAVAD8jAA==.',
Fa='Fanforlife:BAAALgADCgcJDQAAAA==.',
Fe='Felgus:BAAALgADCgYJBgAAAA==.Feyre:BAABLgAECn8oAAIKAAgJtQdcegAuAQAKAAgJtQdcegAuAQAAAA==.',
Fi='Fiammetta:BAECLgAFFH8HAAIcAAQJpR3bBgD4AAAcAAQJpR3bBgD4AAAuAAQKfxgAAhwACQlnI94HADoCABwACQlnI94HADoCAAEuAAUUBgkUAAkASSEA.Fiddlesticks:BAAALgAECgYJDgABLgAECgcJEQAFAAAAAA==.Finke:BAABLgAECn8bAAISAAcJZhzrZwAHAgASAAcJZhzrZwAHAgAAAA==.Fishmärket:BAABLgAECn8eAAIMAAkJeQszCwCYAQAMAAkJeQszCwCYAQAAAA==.',
Fl='Flickerbeat:BAAALgAECgUJBAAAAA==.',
Fo='Forestclaw:BAAALgADCgMJBAAAAA==.',
Fr='Freakbeast:BAAALgAECgEJAgAAAA==.Frostie:BAAALgAFFAIJAwABLgAFFAUJCwANALkMAA==.Frís:BAAALgAECggJEwABLgAFFAMJAwAFAAAAAA==.',
Fu='Furryfist:BAAALgADCgcJBwAAAA==.',
Ga='Galarine:BAABLgAECn8lAAIOAAkJcBe+IQAfAgAOAAkJcBe+IQAfAgAAAA==.Galas:BAAALgADCgEJAQAAAA==.',
Gi='Gigazapper:BAAALgADCgcJCAABLgAFFAIJAgAFAAAAAA==.Gilrathor:BAAALgAECggJCgAAAA==.Gizzlit:BAABLgAECn8eAAIMAAgJ2hpFBwD7AQAMAAgJ2hpFBwD7AQAAAA==.',
Gl='Glovez:BAAALgAECgMJAwAAAA==.',
Go='Gobiasinds:BAAALgAECgEJAQAAAA==.Gofetch:BAABLgAECn8hAAICAAkJrxvkFgBTAgACAAkJrxvkFgBTAgAAAA==.Golffwangg:BAAALgADCgUJBQAAAA==.Goomei:BAAALgADCgcJDwAAAA==.Goopzy:BAAALgAECgIJAgABLgAECgUJDAAFAAAAAA==.',
Gr='Grandwiz:BAAALgAECgMJBQAAAA==.Grissum:BAABLgAECn8lAAMCAAgJOR2nGwAxAgACAAgJOR2nGwAxAgAQAAUJ+hL5GAA/AQAAAA==.',
Gu='Gutcassidy:BAAALgADCgkJCQAAAA==.',
Ha='Hac:BAAALgAECgcJDQAAAA==.Hackacracka:BAAALgAECgYJDgABLgAECgcJDQAFAAAAAA==.Halotwo:BAAALgAECgYJCQAAAA==.Harold:BAAALgAECgYJCQAAAA==.Harper:BAAALgAECgYJBgAAAA==.Harpull:BAAALgADCgYJEAABLgAECgYJBgAFAAAAAA==.Harpö:BAAALgAECgEJAQABLgAECgYJBgAFAAAAAA==.',
He='Healingkiss:BAABLgAECn8XAAIXAAYJ8AG8PgCmAAAXAAYJ8AG8PgCmAAAAAA==.Heatup:BAABLgAECn8aAAISAAgJfiMzFQApAwASAAgJfiMzFQApAwAAAA==.Helper:BAAALgAECgcJEgAAAA==.',
Ho='Holymages:BAABLgAECn8hAAISAAgJpxuqNwD4AQASAAgJpxuqNwD4AQAAAA==.Homtardy:BAAALgAECgYJBwAAAA==.',
Hu='Huhknee:BAAALgADCgEJAQAAAA==.',
Il='Ilyanna:BAABLgAECn8bAAMdAAkJoRzmAwAEAgAdAAkJoRzmAwAEAgAOAAEJXxDXCwFFAAAAAA==.',
Im='Im:BAACLgAFFH8YAAQQAAcJvRaSAwCUAQAeAAYJARqKBgC3AQAQAAYJng6SAwCUAQACAAEJPRPaIgBaAAAuAAQKfyUAAh4ACAmyJDgGADkDAB4ACAmyJDgGADkDAAAA.Imabadshot:BAAALgADCgUJBQAAAA==.Imscary:BAAALgADCgMJAwAAAA==.',
In='Incandescent:BAAALgADCgcJCwABLgAECgYJBwAFAAAAAA==.Incarnate:BAAALgADCgYJBgABLgAECggJJgAVAMsLAA==.',
Ja='Ja:BAAALgADCgYJCQAAAA==.',
Je='Jenn:BAAALgAECgcJDAAAAA==.',
Jh='Jhalse:BAAALgAECgMJAQAAAA==.Jhoppss:BAABLgAECn8WAAMfAAYJlx1rDwDkAQAfAAYJlx1rDwDkAQAgAAQJjQ9AUQCQAAAAAA==.',
Ji='Jiinxx:BAAALgAECgIJAwAAAA==.Jillià:BAAALgAFFAEJAgAAAA==.Jirachi:BAAALgADCgYJBgAAAA==.',
Jo='Jokervenom:BAAALgADCgYJBAAAAA==.',
Ka='Kaidia:BAAALgAECgQJBAAAAA==.Kaiyann:BAAALgADCgcJBwAAAA==.Karls:BAAALgAECgYJDQAAAA==.',
Ke='Keez:BAAALgAECgcJDgAAAA==.Keezey:BAAALgAECggJEQAAAA==.Kej:BAAALgAECgIJAgAAAA==.Kerafyrm:BAABLgAECn8rAAMZAAgJwx9/AwDMAgAZAAgJwx9/AwDMAgAgAAIJch/LZgBFAAAAAA==.Kerrigan:BAACLgAFFH8YAAIaAAYJjA0RGABvAQAaAAYJjA0RGABvAQAuAAQKfzMAAhoACQn4HuoNAJcCABoACQn4HuoNAJcCAAAA.',
Ki='Kiezn:BAAALgADCgEJAQABLgAECgYJFgANAB0jAA==.Kirithan:BAAALgAECgEJAQAAAA==.',
Ko='Kookler:BAABLgAECn8iAAMEAAkJaBd5JAAoAgAEAAkJaBd5JAAoAgAhAAEJPRBUMQA+AAAAAA==.Kozand:BAAALgADCgIJAgABLgAECgUJDwAFAAAAAA==.Kozari:BAAALgAECgYJEQAAAA==.',
Ku='Kushmon:BAAALgADCggJEgAAAA==.',
Ky='Kyirr:BAABLgAECn8fAAMfAAkJgxlNDAAWAgAfAAcJQRpNDAAWAgAgAAUJFxiwMgARAQAAAA==.Kyralen:BAABLgAECn8WAAMNAAYJHSPEGABMAgANAAYJHSPEGABMAgAKAAIJVxOk5wB3AAAAAA==.',
La='Labamba:BAAALgADCgYJCwAAAA==.Lazerbeampew:BAABLgAECn8XAAIMAAkJiRVRCgAsAgAMAAkJiRVRCgAsAgAAAA==.',
Li='Lilchithead:BAAALgAECgYJCgAAAA==.Lilium:BAAALgADCgEJAQAAAA==.Lilli:BAECLgAFFH8UAAIJAAYJSSFgAwDqAQAJAAYJSSFgAwDqAQAuAAQKfy0AAgkACQnqJSUBAK0DAAkACQnqJSUBAK0DAAAA.Lividea:BAAALgADCgUJBwAAAA==.Livinglover:BAAALgADCgUJAwAAAA==.',
Ll='Llela:BAAALgAECgYJBgAAAA==.Llynryn:BAABLgAECn8UAAIYAAcJOA+EMwBLAQAYAAcJOA+EMwBLAQAAAA==.',
Lo='Locktua:BAAALgAECgcJCAAAAA==.',
Ly='Lympha:BAABLgAFFH8IAAMLAAMJch2WHQAYAQALAAMJch2WHQAYAQAMAAEJowElDQA3AAAAAA==.Lyn:BAAALgAECgUJCAAAAA==.',
Ma='Magicae:BAAALgADCgUJBQABLgAFFAcJFAAaAHUbAA==.Magicmanzz:BAAALgAECgcJDwAAAA==.Magnifuso:BAAALgAECgYJEAAAAA==.Maguapa:BAAALgAECgQJBwAAAA==.Malgata:BAAALgADCgkJFgAAAA==.Margarita:BAAALgAECgQJCQAAAA==.Martineh:BAAALgADCgcJDAAAAA==.Martoc:BAAALgADCgQJBAAAAA==.Martoche:BAAALgADCgEJAQAAAA==.Mastab:BAACLgAFFH8GAAINAAMJIRcQHgDgAAANAAMJIRcQHgDgAAAuAAQKfy4AAw0ACQnbH8UQAEcCAA0ABwkNH8UQAEcCAAoACAntGVooABgCAAAA.',
Mc='Mcplucky:BAAALgAECgQJBAAAAA==.Mcziggles:BAAALgAECgcJCwAAAA==.',
Me='Meg:BAAALgAECgIJAgAAAA==.',
Mi='Mikio:BAABLgAECn8bAAIBAAgJYg5HIwBTAQABAAgJYg5HIwBTAQAAAA==.Miliani:BAAALgAECgIJAgAAAA==.Milinka:BAABLgAECn8nAAIXAAkJcxfEEQAJAgAXAAkJcxfEEQAJAgAAAA==.',
Mo='Moardottz:BAABLgAECn8XAAIOAAYJPxW+cgB5AQAOAAYJPxW+cgB5AQABLgAECgUJBQAFAAAAAA==.Moiryn:BAACLgAFFH8LAAILAAQJoRBYHQAZAQALAAQJoRBYHQAZAQAuAAQKfykAAwsACAn9G54ZAEoCAAsACAn9G54ZAEoCABsAAQlxD2B2ADEAAAAA.Monkmonk:BAAALgAECgEJAQAAAA==.Mortine:BAAALgADCgYJDwAAAA==.',
My='Mythesesgrey:BAAALgADCgUJCQAAAA==.',
Na='Naturals:BAAALgAECgEJAwAAAA==.Navillus:BAACLgAFFH8aAAIZAAYJxBAfCQCsAQAZAAYJxBAfCQCsAQAuAAQKf0EAAxkACQnvFMEMAGoCABkACQnvFMEMAGoCAB8ABwmbIdwIAFUCAAAA.',
No='Norasoul:BAABLgAECn8lAAIaAAkJVRsnEQB4AgAaAAkJVRsnEQB4AgAAAA==.',
Og='Ogron:BAACLgAFFH8SAAMLAAQJayVWCQC2AQALAAQJayVWCQC2AQAbAAEJcx/FGwBTAAAuAAQKfzgAAxsACQl8JRAEAF4DABsACQl8JRAEAF4DAAsAAwkoIJ9qAKwAAAAA.',
Oh='Ohmna:BAAALgAECgQJCAAAAA==.Ohshyt:BAAALgAECgYJBgAAAA==.Ohsowitchy:BAAALgADCgQJBAAAAA==.',
Op='Ophindis:BAAALgAECgYJDgAAAA==.',
Or='Orwenya:BAAALgAECgUJDwAAAA==.',
Os='Osten:BAAALgAECgYJDQAAAA==.',
Ou='Ourkelly:BAAALgAECgYJDQAAAA==.',
Pa='Pagoda:BAAALgAECgkJCQAAAA==.',
Pe='Pewpop:BAAALgAECgYJCgABLgAECgcJEwAFAAAAAA==.',
Ph='Philzeey:BAAALgADCgYJCAAAAA==.Phrall:BAAALgAECgEJAQAAAA==.',
Py='Pylon:BAAALgAECggJCAAAAA==.',
Qp='Qpti:BAAALgAECgQJDQAAAA==.',
Ra='Raphael:BAAALgADCgcJCwAAAA==.Ravness:BAAALgAECgEJAQAAAA==.Razorclaw:BAAALgAECgYJBwAAAA==.',
Rc='Rckola:BAAALgADCgcJBwAAAA==.',
Re='Reddacted:BAAALgADCgcJDAAAAA==.Redgrave:BAAALgADCggJCwAAAA==.Rejectlol:BAAALgAECgcJCgAAAA==.Remake:BAAALgAECgMJAQAAAA==.Rennx:BAACLgAFFH8eAAIBAAgJ1hjAAQAAAgABAAgJ1hjAAQAAAgAuAAQKfzkAAgEACQmrJmoAAIIDAAEACQmrJmoAAIIDAAAA.Rexam:BAAALgAECgIJAgABLgAECgcJEgAaAAkgAA==.Reznik:BAAALgAECgUJBwAAAA==.',
Ri='Ringmasta:BAABLgAECn8ZAAIiAAcJnxqpFACmAQAiAAcJnxqpFACmAQAAAA==.',
Ro='Roger:BAAALgADCgUJBQAAAA==.Rowen:BAABLgAECn8ZAAIiAAcJjB3sEADSAQAiAAcJjB3sEADSAQAAAA==.',
Ru='Rucket:BAAALgAFFAEJAQAAAA==.Rutroraggy:BAABLgAECn8VAAMTAAYJ5A8zCQBZAQATAAYJ5A8zCQBZAQASAAYJ/QgdpgD2AAAAAA==.',
['Rè']='Rènza:BAAALgAFFAIJAwAAAA==.',
Sa='Saelybrosa:BAAALgAECgYJCQAAAA==.',
Se='Selmama:BAAALgAECgMJAgAAAA==.Senniel:BAAALgADCgMJAwAAAA==.Serenìty:BAAALgAECgUJBQAAAA==.',
Sh='Shabit:BAAALgADCgUJBgABLgAFFAEJAgAFAAAAAA==.Shadda:BAAALgAECgYJDgAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shamoon:BAABLgAFFH8GAAIbAAIJOQwwKgCPAAAbAAIJOQwwKgCPAAAAAA==.Sharkattack:BAAALgADCgEJAQABLgAECgUJDAAFAAAAAA==.Shinru:BAABLgAECn8WAAMNAAkJbhiqHgDBAQANAAgJCxeqHgDBAQAKAAYJlR6BaABTAQAAAA==.Shioraven:BAAALgADCgMJAwAAAA==.Shrikedk:BAAALgAFFAMJAwAAAA==.',
Si='Sickdayze:BAABLgAECn8bAAINAAgJ9SCtCgCZAgANAAgJ9SCtCgCZAgAAAA==.Sickkungfu:BAAALgADCgcJDAAAAA==.Sickshifts:BAAALgADCgYJBgAAAA==.Sicktides:BAAALgADCgcJCwAAAA==.Sine:BAAALgAECgIJAgAAAA==.',
Sk='Skydaddy:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.Skyrain:BAAALgADCgcJEgAAAA==.',
Sl='Slootin:BAAALgAECgEJAQAAAA==.Slyxxar:BAACLgAFFH8HAAILAAMJTg2uMQC9AAALAAMJTg2uMQC9AAAuAAQKfxsABAwABwk5GMINAGMBAAwABwk5GMINAGMBABsABgnBEexRAP8AAAsAAQl4AVWrAB8AAAAA.',
Sm='Smashtokhan:BAAALgAECgUJCAAAAA==.',
So='Socks:BAAALgAECgQJAQAAAA==.Soow:BAAALgAECgEJAQAAAA==.Soowwrr:BAAALgAECgQJCQAAAA==.Soph:BAACLgAFFH8NAAIEAAYJMhasCADhAQAEAAYJMhasCADhAQAuAAQKfxgAAwQABwlrIlgnABkCAAQABwlrIlgnABkCAAEAAgmjFqpiAD4AAAAA.Sophie:BAACLgAFFH8KAAMKAAQJ9RvBGwBRAQAKAAQJ9RvBGwBRAQANAAEJ2w1eNwA5AAAuAAQKfxsAAwoACAmrHAI1AOUBAAoACAmrHAI1AOUBAA0ABgkuDlNKAE8BAAEuAAUUBgkNAAQAMhYA.Sophievokie:BAAALgAECgQJCwABLgAFFAYJDQAEADIWAA==.Sophisticate:BAABLgAFFH8IAAIQAAQJSRdRCQBWAQAQAAQJSRdRCQBWAQABLgAFFAYJDQAEADIWAA==.Sophiz:BAAALgAECgYJDwABLgAFFAYJDQAEADIWAA==.Sophlax:BAACLgAFFH8TAAIXAAUJLyS6AgDkAQAXAAUJLyS6AgDkAQAuAAQKfxkAAhcACQnLIA8EABQDABcACQnLIA8EABQDAAEuAAUUBgkNAAQAMhYA.Sophs:BAAALgAFFAIJAgABLgAFFAYJDQAEADIWAA==.Soulslug:BAAALgAECgEJAQAAAA==.Sox:BAACLgAFFH8FAAIjAAMJmBpwBwD1AAAjAAMJmBpwBwD1AAAuAAQKfzAAAiMACQknIWgBAAsDACMACQknIWgBAAsDAAAA.Soyeon:BAAALgAFFAEJAQAAAA==.Soyganchgar:BAAALgADCgUJCgAAAA==.Soyonagasaki:BAAALgAECgEJAgABLgAFFAMJAwAFAAAAAA==.',
Sp='Spicynoodle:BAAALgAECgkJCwAAAA==.Spiderknight:BAAALgADCgYJCwAAAA==.Spookyougi:BAABLgAECn8ZAAIYAAUJUSUoGgCgAQAYAAUJUSUoGgCgAQAAAA==.',
Sq='Squattinchop:BAABLgAECn8XAAIHAAYJaiD3FQA6AgAHAAYJaiD3FQA6AgAAAA==.Squattinzaps:BAAALgADCgUJBQABLgAECgYJFwAHAGogAA==.',
St='Stiffcrit:BAAALgAECgkJBwAAAA==.Stinkydh:BAABLgAECn8SAAIaAAYJMhFNcwBLAQAaAAYJMhFNcwBLAQAAAA==.Stryx:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.',
Su='Suji:BAABLgAECn8hAAIDAAgJgyDzFACJAgADAAgJgyDzFACJAgAAAA==.Sumiko:BAAALgADCgQJBAABLgADCgYJBgAFAAAAAA==.Supergogeta:BAABLgAECn8vAAQEAAgJUiFyDgDGAgAEAAcJfCJyDgDGAgABAAIJ+A5YUwBnAAAjAAEJiQQ9NwAaAAAAAA==.',
Sy='Sylvie:BAAALgAECgcJDwAAAA==.Synistër:BAAALgADCgMJAwAAAA==.Synthesis:BAAALgADCgMJAwAAAA==.',
Ta='Takoda:BAAALgADCgYJBgAAAA==.Taks:BAAALgADCgIJAgAAAA==.Talauyia:BAAALgAECgYJEAAAAA==.Tankyou:BAAALgAECgEJAQAAAA==.Tater:BAAALgADCgEJAQAAAA==.Tavik:BAAALgAECgMJAwAAAA==.',
Te='Teestri:BAAALgADCgcJBwAAAA==.Temporë:BAAALgAECgIJBQAAAA==.',
Th='Thorish:BAABLgAECn8kAAIkAAkJ5CGrAwDbAgAkAAkJ5CGrAwDbAgAAAA==.',
Ti='Tiddyweaver:BAAALgAECgUJDgABLgAECgkJGQAZAIIdAA==.Timbit:BAABLgAECn8jAAIHAAgJfQnbLwD4AAAHAAgJfQnbLwD4AAAAAA==.Tinfoiltotem:BAAALgADCgYJAQAAAA==.Tinybubbles:BAABLgAECn8fAAMLAAgJDhb6MwC0AQALAAgJDhb6MwC0AQAbAAQJKw2XXwDFAAAAAA==.Tinyfeet:BAAALgAECgUJCgAAAA==.Tiriandrel:BAAALgADCgYJBgABLgAECgYJDgAFAAAAAA==.',
To='Token:BAAALgADCgIJAwAAAA==.Torio:BAABLgAECn8bAAMlAAgJRBl/FADgAQAlAAgJRBl/FADgAQAYAAEJvwcSZwAsAAAAAA==.',
Tr='Trooth:BAAALgADCgYJBgABLgAECgUJDAAFAAAAAA==.Tròybòy:BAABLgAECn8gAAIDAAgJlSEDHgBQAgADAAgJlSEDHgBQAgAAAA==.Trölololollo:BAAALgADCgUJCAAAAA==.',
Tu='Turboidiot:BAAALgAECgYJCQAAAA==.',
Tw='Twofow:BAAALgADCgkJCgAAAA==.Twylla:BAAALgAECgEJAQABLgAECgkJPgAfAIQlAA==.',
Ty='Tyrrlol:BAAALgAECgUJCAAAAA==.Tyê:BAABLgAECn8VAAMZAAgJ+A16DwCKAQAZAAgJ+A16DwCKAQAgAAYJRAjBQgDJAAAAAA==.',
['Té']='Témalabécane:BAAALgADCgEJAQAAAA==.',
Va='Vael:BAABLgAECn8ZAAIaAAcJFxNmYAAWAQAaAAcJFxNmYAAWAQAAAA==.Vaelric:BAAALgADCgEJAQAAAA==.Vale:BAABLgAECn8nAAMWAAgJphP6GQA2AQADAAYJ5xXfjwBgAQAWAAgJ+g76GQA2AQAAAA==.Valériana:BAAALgADCgEJAQAAAA==.',
Ve='Vee:BAABLgAECn8fAAMmAAgJ+CN6CQCHAgAmAAgJ+CN6CQCHAgAnAAEJnBXmOwBBAAAAAA==.Veyla:BAEALgADCgcJDgABLgAECgYJBwAFAAAAAA==.',
Vo='Voiddemon:BAAALgAECgIJAgAAAA==.Voltage:BAAALgAECgcJEwAAAA==.Vore:BAAALgADCgEJAQAAAA==.',
Vu='Vult:BAABLgAECn8jAAIDAAkJwxV7ZQBSAQADAAkJwxV7ZQBSAQAAAA==.',
Wa='Warkdom:BAAALgAECgUJCAAAAA==.',
We='Wehttam:BAAALgAECgIJAgAAAA==.Welgo:BAABLgAECn8jAAIcAAcJhiNFBwBKAgAcAAcJhiNFBwBKAgAAAA==.',
Wh='Wheelchair:BAEALgADCgYJBgABLgAECgYJBwAFAAAAAA==.',
Wi='Wickeddemon:BAABLgAECn8YAAIVAAcJkxHvGgA+AQAVAAcJkxHvGgA+AQAAAA==.Wiseoaktree:BAAALgADCgcJCAAAAA==.Wizzie:BAAALgAECgMJAwAAAA==.',
['Wì']='Wìzzqt:BAABLgAECn8iAAINAAkJxhSHHQDKAQANAAkJxhSHHQDKAQAAAA==.',
Xa='Xanthel:BAAALgADCgcJCwABLgAECgkJIgAEAGgXAA==.',
Xe='Xenk:BAAALgADCgEJAQAAAA==.Xerra:BAABLgAECn8mAAIaAAkJPB9DDACpAgAaAAkJPB9DDACpAgAAAA==.',
Ye='Yeast:BAAALgADCgEJAQAAAA==.',
Yi='Yia:BAACLgAFFH8WAAIhAAUJGiC4AACxAQAhAAUJGiC4AACxAQAuAAQKfxYAAiEACAnDInIEANUCACEACAnDInIEANUCAAAA.',
Yr='Yralka:BAAALgAECgMJAwAAAA==.',
Yu='Yuqi:BAAALgADCgcJBwAAAA==.',
Za='Zaftenpuff:BAAALgAECgQJBAAAAA==.Zandashami:BAAALgAECggJCAAAAA==.Zarya:BAAALgAECgUJDwAAAA==.',
Ze='Zelgie:BAABLgAECn8pAAMkAAgJXxG9EABfAQAkAAgJXxG9EABfAQANAAUJ6BAfPgD6AAAAAA==.',
Zo='Zorsse:BAAALgAECgQJAwABLgAECggJHwAmAN0XAA==.',
Zu='Zulu:BAABLgAECn8VAAIJAAYJkBzJHACCAQAJAAYJkBzJHACCAQAAAA==.',
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
