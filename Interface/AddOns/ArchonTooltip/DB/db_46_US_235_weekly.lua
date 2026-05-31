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

local lookup = {'Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Warlock-Demonology','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Priest-Holy','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Mage-Frost','DemonHunter-Devourer','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','DeathKnight-Frost','Monk-Mistweaver','DemonHunter-Vengeance','Warrior-Arms','Shaman-Elemental','Priest-Discipline','Mage-Fire','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Monk-Windwalker','Rogue-Outlaw','Paladin-Protection','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-05-31',data={Ad='Addisyn:BAAALgAECgEJBAAAAA==.',
Ae='Aekal:BAAALgADCggJEAAAAA==.Aemetris:BAABLgAECn8UAAIBAAYJ4Rm7NgC8AQABAAYJ4Rm7NgC8AQAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgUJBgAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ai='Aidendawn:BAAALgAECgQJCQAAAA==.',
Aj='Ajheria:BAAALgADCgcJCAAAAA==.',
Al='Alukart:BAAALgAECgEJAgAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.',
An='Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgAECgIJAwAAAA==.Andari:BAAALgADCgEJAQAAAA==.Andramaedra:BAAALgAECgkJAgAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAACLgAFFH8KAAICAAQJPiPCCQCaAQACAAQJPiPCCQCaAQAuAAQKfzwAAwIACQkLJYUCALYCAAIACAnnJIUCALYCAAMAAQkGJljhAGYAAAAA.',
Ap='Aponi:BAAALgAECgQJBwAAAA==.',
Ar='Ardour:BAAALgAECgMJBgABLgAECgYJDgAEAAAAAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8fAAIFAAkJlxQALADoAQAFAAkJlxQALADoAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.',
As='Ashenaya:BAABLgAECn8YAAMGAAgJLxl1CwASAgAGAAgJLxl1CwASAgAHAAEJMQpQQgArAAAAAA==.Asparagus:BAABLgAECn8ZAAIIAAgJpQ5ScwBuAQAIAAgJpQ5ScwBuAQAAAA==.',
At='Atlass:BAACLgAFFH8GAAIJAAIJLhWWtACRAAAJAAIJLhWWtACRAAAuAAQKfxgAAgkABwnxGYtjAMkBAAkABwnxGYtjAMkBAAAA.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBQABLgAFFAcJGgAKAGAaAA==.Aust:BAABLgAECn8UAAIIAAgJ6hNIYQCVAQAIAAgJ6hNIYQCVAQAAAA==.',
Av='Averlis:BAABLgAECn8bAAILAAgJ5RS6HgC6AQALAAgJ5RS6HgC6AQAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgADCggJCAAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgYJDQAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8lAAIIAAkJzApoewBdAQAIAAkJzApoewBdAQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAEBLgAECn8wAAIMAAgJox9tFQDVAgAMAAgJox9tFQDVAgAAAA==.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECggJDgAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECggJEAAAAA==.Beeble:BAAALgAECgYJDwAAAA==.Belii:BAAALgAECgYJDAAAAA==.Bended:BAAALgADCgEJAQAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJDQAAAA==.',
Bi='Bigbooty:BAABLgAECn8aAAMNAAYJxwcaPwCEAAANAAYJawYaPwCEAAAOAAQJwAalNwBaAAAAAA==.Bigbootyjudi:BAAALgADCgIJAgAAAA==.',
Bl='Blikey:BAABLgAFFH8GAAIJAAIJfiZTmwC6AAAJAAIJfiZTmwC6AAAAAA==.Bloodyrott:BAAALgAECgQJCQAAAA==.Bluedrake:BAACLgAFFH8JAAMHAAQJRhqOAgBWAQAHAAQJRhqOAgBWAQAPAAEJPRMiWABAAAAuAAQKfyMAAwcACAlfHr4EALoCAAcACAmGHb4EALoCAA8ACAk9FlIZAAMCAAEuAAUUBAkPAAsAqBwA.Blueparrot:BAABLgAECn8yAAIQAAgJpBScGADzAQAQAAgJpBScGADzAQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8ZAAIRAAgJphxHIADcAQARAAgJphxHIADcAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8UAAMJAAYJdiOzGgDJAQAJAAUJdiOzGgDJAQASAAEJAABiRgAAAAAuAAQKfyAAAwkACQmrIaMXAO4CAAkACQmrIaMXAO4CABIABAmuE584AJsAAAAA.Bowkatan:BAAALgAECgEJAgAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAITAAYJUx4zJQD8AQATAAYJUx4zJQD8AQAAAA==.Bringinlight:BAAALgAECgYJCQAAAA==.',
Bu='Bubbleicious:BAAALgAECgYJDAAAAA==.Bubbletea:BAAALgAECgcJEQABLgAECgkJKQADAIgiAA==.Bulletz:BAABLgAECn8eAAICAAgJ7x1CBABkAgACAAgJ7x1CBABkAgAAAA==.Bumpersnouts:BAAALgADCgEJAQAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgIJBQABLgAECgcJFQAKAEoPAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8sAAMFAAgJBxAgUAA9AQAFAAcJqw4gUAA9AQALAAgJ2Ax5NQAoAQAAAA==.Cassiradra:BAAALgADCgEJAQAAAA==.',
Ce='Cearas:BAAALgADCgkJDQAAAA==.Cedrick:BAAALgAECgUJBQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgYJDAAAAA==.Celticsinsix:BAAALgAECgMJBQAAAA==.Cervixticklr:BAAALgAECgEJAQAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAABLgAECn8xAAIUAAcJ4Q65jgBBAQAUAAcJ4Q65jgBBAQAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAABLgAECn8UAAIFAAYJuQ27WwAUAQAFAAYJuQ27WwAUAQAAAA==.Choglana:BAAALgAECgcJCQAAAA==.Chogli:BAAALgAECgEJAQABLgAECgcJCQAEAAAAAA==.Chogric:BAABLgAECn83AAMTAAkJhh+NBQATAwATAAkJhh+NBQATAwAIAAQJZw39DwGEAAABLgAECgcJCQAEAAAAAA==.',
Ci='Civetta:BAABLgAECn8WAAIDAAkJhwybRgC4AQADAAkJhwybRgC4AQAAAA==.',
Cl='Clannininick:BAAALgADCgUJBgAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Comespankit:BAAALgAECgUJBQAAAA==.Convalesor:BAABLgAECn8UAAIKAAYJQQggSgDCAAAKAAYJQQggSgDCAAAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8JAAIJAAMJYRmEkQDMAAAJAAMJYRmEkQDMAAAAAA==.Crona:BAABLgAECn8aAAITAAkJtg4LPACJAQATAAkJtg4LPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8PAAIUAAYJthDpNQBrAQAUAAYJthDpNQBrAQAuAAQKfxcAAhQACAnmH2k5AJACABQACAnmH2k5AJACAAAA.Crzzy:BAAALgAFFAEJAQAAAA==.',
Cu='Cuddlez:BAABLgAECn8eAAIQAAgJGwxSLQBNAQAQAAgJGwxSLQBNAQAAAA==.Cultera:BAACLgAFFH8HAAIVAAQJJg8FPwARAQAVAAQJJg8FPwARAQAuAAQKfxQAAhUACAl6GzA/ALYBABUACAl6GzA/ALYBAAAA.',
Cy='Cyhyraethia:BAABLgAECn8fAAIWAAgJDB+sBQANAgAWAAgJDB+sBQANAgABLgAECgkJOAAVAEEaAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Dammnation:BAAALgAECgEJAQABLgAECgcJFQAKAEoPAA==.Danda:BAAALgAECgYJCgAAAA==.Daricepicker:BAABLgAECn8pAAIDAAkJiCJPBQA3AwADAAkJiCJPBQA3AwAAAA==.Darkyn:BAABLgAECn8ZAAIMAAkJPRC0PwDSAQAMAAkJPRC0PwDSAQAAAA==.Davedadude:BAABLgAECn8nAAIIAAkJ2iF+CwD2AgAIAAkJ2iF+CwD2AgAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAABLgAFFH8KAAMCAAQJPA4zEwAGAQADAAQJsgs4OQAgAQACAAQJ2gwzEwAGAQAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIJAAgJ8wvpbACwAQAJAAgJ8wvpbACwAQAAAA==.Deadscar:BAECLgAFFH8IAAIXAAQJ+SMOAgCrAQAXAAQJ+SMOAgCrAQAuAAQKfzQAAhcACQlSJnYAAGUDABcACQlSJnYAAGUDAAAA.Deathmasterj:BAAALgADCggJCQAAAA==.Deaths:BAABLgAECn8eAAMYAAgJTRKHGACgAQAYAAgJTRKHGACgAQAVAAEJJQRWGwEdAAAAAA==.Dedfrosty:BAABLgAECn8XAAMSAAgJegw/JAAYAQASAAgJMQs/JAAYAQAZAAYJqQcGGgDQAAAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwAEAAAAAA==.Demonio:BAAALgADCgQJBgAAAA==.Demonpimp:BAAALgAECgYJEAAAAA==.Dermon:BAAALgAECgYJBwABLgAECgkJJAAaAPoiAA==.Deviously:BAAALgADCgQJBAABLgAECggJHgACAO8dAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Di='Dimpiana:BAAALgAECgQJBAAAAA==.Disciplea:BAAALgADCgYJBgAAAA==.Dithariaa:BAABLgAECn8WAAIbAAYJUwUNHQCcAAAbAAYJUwUNHQCcAAAAAA==.',
Do='Docryktor:BAABLgAECn85AAIXAAgJ3xqeCAAhAgAXAAgJ3xqeCAAhAgAAAA==.Doomgears:BAAALgAECgYJEAAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Draculä:BAAALgAECgQJBAAAAA==.Dragonair:BAABLgAECn8ZAAMGAAcJSAUjJQCwAAAGAAYJiQMjJQCwAAAHAAcJ7AKnFQCjAAAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAABLgAECn8UAAIcAAYJSR4NFgCWAQAcAAYJSR4NFgCWAQAAAA==.Dro:BAAALgAECgQJCQAAAA==.Drogas:BAAALgAECgIJBAAAAA==.Drtybear:BAABLgAECn8YAAMNAAgJnw3cMADDAAANAAYJtg3cMADDAAAOAAQJpQ1oLACSAAAAAA==.Drulissa:BAACLgAFFH8IAAITAAMJnyAYHwAQAQATAAMJnyAYHwAQAQAuAAQKfxkAAhMACQl1GZktAM0BABMACQl1GZktAM0BAAAA.Druu:BAAALgADCgMJAwABLgAFFAUJEAAUAKUaAA==.',
Du='Duh:BAAALgADCgEJAQAAAA==.Duogear:BAAALgADCgEJAQAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
Eb='Ebonwings:BAAALgAECgYJCgABLgAECgcJAwAEAAAAAA==.',
Ed='Ediana:BAABLgAECn8nAAIUAAkJ6gmbcgB7AQAUAAkJ6gmbcgB7AQAAAA==.',
El='Eld:BAAALgAECgEJAQAAAA==.Elmô:BAABLgAECn83AAITAAgJHiEoCQDmAgATAAgJHiEoCQDmAgAAAA==.Elody:BAAALgADCgYJBgAAAA==.Elvara:BAAALgAECgUJDQAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8qAAINAAgJyhbHFACPAQANAAgJyhbHFACPAQAAAA==.',
Ex='Exash:BAACLgAFFH8LAAIdAAQJwRpIFQBIAQAdAAQJwRpIFQBIAQAuAAQKfycAAh0ACQk7ITUJAP8CAB0ACQk7ITUJAP8CAAAA.Excizion:BAABLgAECn8eAAIJAAkJxQlAZACNAQAJAAkJxQlAZACNAQAAAA==.',
Fa='Faelynne:BAAALgADCgUJBQAAAA==.Fari:BAAALgAECgcJDAAAAA==.Fathertim:BAABLgAECn8WAAIeAAYJrRekIQCfAQAeAAYJrRekIQCfAQAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frostii:BAABLgAECn8XAAIUAAgJxRnIXACxAQAUAAgJxRnIXACxAQAAAA==.',
Fu='Fudestamp:BAAALgADCgQJBQAAAA==.Fufight:BAAALgAECgIJBAABLgAECgkJJAAaAPoiAA==.Fugryktor:BAABLgAECn8eAAIWAAYJGBW3EAA3AQAWAAYJGBW3EAA3AQAAAA==.',
Fy='Fyrebug:BAABLgAECn8WAAIBAAYJkwuqZwAHAQABAAYJkwuqZwAHAQAAAA==.',
Ga='Galandor:BAAALgAECgYJEwAAAA==.Gandaalf:BAABLgAECn8WAAMfAAcJCR7XAQBrAgAfAAcJCR7XAQBrAgAUAAIJ4Q9RRgFzAAAAAA==.Garrinda:BAAALgAECgkJDgAAAA==.Gaya:BAAALgAECgYJBgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8gAAIgAAkJlA90CQCWAQAgAAkJlA90CQCWAQAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAhAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIFAAgJRiBKEADAAgAFAAgJRiBKEADAAgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityadruid:BAAALgADCgMJAwABLgAECgYJCQAEAAAAAA==.Gityahunter:BAAALgAECgEJAQABLgAECgYJCQAEAAAAAA==.',
Gl='Glavenus:BAAALgADCgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn87AAIIAAkJXCCzDwDTAgAIAAkJXCCzDwDTAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAgJGQAiAMsjAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAAALgAECgYJEQAAAA==.Graysurv:BAACLgAFFH8ZAAIiAAgJyyMEAACBAgAiAAgJyyMEAACBAgAuAAQKfykAAiIACQn6JgUAABQEACIACQn6JgUAABQEAAAA.Gregmiller:BAAALgADCgYJBgAAAA==.Gromlin:BAAALgAECgQJBAAAAA==.',
['Gä']='Gäreth:BAAALgADCgYJCwAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hamremmi:BAAALgAECgEJAQABLgAFFAcJGgAKAGAaAA==.Haruharu:BAAALgAECgQJBQABLgAECgkJJQAFANkfAA==.Hasalia:BAAALgAECggJCAABLgAFFAMJCAATAJ8gAA==.',
He='Healsforu:BAAALgAECgUJDQABLgAECgYJCgAEAAAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMNAAgJORj4HwArAQANAAUJ8Rr4HwArAQALAAYJAhH+TAC+AAAAAA==.Heunno:BAAALgADCgYJBgABLgADCgcJBwAEAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAABLgAECn8gAAIFAAkJgyO0BQAxAwAFAAkJgyO0BQAxAwAAAA==.Highbrittz:BAAALgAECgYJDgAAAA==.',
Ho='Hoakaren:BAABLgAECn8YAAIVAAgJfhcVOgDJAQAVAAgJfhcVOgDJAQAAAA==.Hobiscuits:BAEALgADCgQJBAABLgAECgYJEwAMAE8gAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgUJDQAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAABLgAECn8VAAIDAAcJHhtwMADvAQADAAcJHhtwMADvAQAAAA==.',
Hy='Hydrobubble:BAAALgAECgEJAQAAAA==.',
['Há']='Hátfield:BAAALgADCgEJAQAAAA==.',
Ih='Ihyo:BAAALgADCgIJAgABLgAECgcJBwAEAAAAAA==.',
Il='Illyy:BAABLgAECn8mAAIQAAgJMgswMQAyAQAQAAgJMgswMQAyAQAAAA==.',
In='Indawhole:BAACLgAFFH8dAAIVAAgJABhbDQAOAgAVAAgJABhbDQAOAgAuAAQKfxoAAhUACAl8JcIgAD4CABUACAl8JcIgAD4CAAAA.',
Ir='Iridori:BAABLgAECn8wAAIQAAgJuCCmCQC6AgAQAAgJuCCmCQC6AgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAALgAECgYJEgAAAA==.',
Ja='Jabberthehut:BAAALgAECgYJBgAAAA==.Jamerius:BAAALgAECgIJAgAAAA==.Jasmean:BAAALgADCgcJBQAAAA==.Javaluminous:BAABLgAECn8oAAIIAAgJQCDZJQBVAgAIAAgJQCDZJQBVAgAAAA==.Jay:BAAALgADCgcJDQABLgAFFAUJEwAjAEQbAA==.Jaytsukitori:BAACLgAFFH8VAAMFAAQJ0yS1EgCwAQAFAAQJ0yS1EgCwAQALAAEJgwgnQwA4AAAuAAQKfx0AAwUACAmKIbkMANcCAAUACAmKIbkMANcCAAsAAQlmEEuAADMAAAAA.',
Jh='Jhaeriao:BAAALgAECgYJDAAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8WAAIJAAYJVxcaIQCpAQAJAAYJVxcaIQCpAQAAAA==.Joham:BAAALgAECgEJAQAAAA==.Jonah:BAAALgAFFAEJAQABLgAFFAIJBQAJAB4YAA==.',
Ju='Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAIUAAYJUQ5x0ABMAQAUAAYJUQ5x0ABMAQAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Kh='Khrønos:BAAALgAECggJCgAAAA==.',
Ki='Killzom:BAAALgADCgEJAQABLgAFFAIJBgANAKoQAA==.Kilrah:BAABLgAECn82AAIYAAkJahYmEAAIAgAYAAkJahYmEAAIAgAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAABLgAECn8WAAIUAAYJ9AnuyQDdAAAUAAYJ9AnuyQDdAAAAAA==.Kissmycrits:BAABLgAECn8ZAAIDAAQJsB1pcwBDAQADAAQJsB1pcwBDAQAAAA==.Kissmywrath:BAAALgADCgEJAQAAAA==.Kiyana:BAABLgAECn8rAAIYAAcJUA2nKgAIAQAYAAcJUA2nKgAIAQAAAA==.Kiyoine:BAABLgAECn8iAAIOAAgJKRlhCgD7AQAOAAgJKRlhCgD7AQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8SAAIIAAYJLRrWFgCJAQAIAAYJLRrWFgCJAQAuAAQKfxsAAggABwl+IIskAJUCAAgABwl+IIskAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAAEAAAAAA==.Knoxreaps:BAAALgAECgIJBAABLgAECgMJBAAEAAAAAA==.Knoxstaggers:BAABLgAECn8lAAIkAAgJ3iCFEQAbAgAkAAgJ3iCFEQAbAgABLgAECgMJBAAEAAAAAA==.',
Kr='Krzzy:BAAALgAFFAEJAQABLgAFFAEJAQAEAAAAAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kynbrookera:BAABLgAECn8dAAIFAAgJ0Ay7SgBTAQAFAAgJ0Ay7SgBTAQAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgYJEAAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgQJCAAAAA==.Lethiferous:BAAALgAECgEJAQAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8jAAIUAAkJaBRlQgD/AQAUAAkJaBRlQgD/AQAAAA==.',
Li='Licht:BAAALgAECgYJCwAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilpyro:BAAALgAECgQJBAAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8hAAMlAAkJvAzmDQA3AQAjAAcJZA4QIQB0AQAlAAgJEQjmDQA3AQAAAA==.Lit:BAAALgAECgEJAwAAAA==.Littledog:BAACLgAFFH8GAAIKAAMJyhAPHwDXAAAKAAMJyhAPHwDXAAAuAAQKfy0AAwoACQnXFdsYAOYBAAoACQnXFdsYAOYBAB4AAwkdFK09AL8AAAAA.',
Lo='Lockdout:BAAALgADCgEJAQABLgAECggJGQAUANkWAA==.Loky:BAACLgAFFH8FAAIMAAIJvxlVgQCfAAAMAAIJvxlVgQCfAAAuAAQKfyQABAwACQkCH/c2APIBAAwACQncHvc2APIBACAABAl+GMskADUBABYAAQl6IZApAF8AAAAA.Longshanks:BAAALgADCgUJDAAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgUJCAAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lunitari:BAAALgAECgUJBgAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECggJGAAOAD8PAA==.',
Ly='Lynnali:BAAALgADCggJEQAAAA==.Lyrrin:BAAALgADCgYJBgAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8ZAAIUAAgJ2RbnVgDBAQAUAAgJ2RbnVgDBAQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magicmann:BAAALgADCgcJAgAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Majhduul:BAAALgADCgMJAwAAAA==.Malafang:BAAALgAECgYJEgAAAA==.Malanah:BAAALgAECgYJDgAAAA==.Marandra:BAAALgAECgMJAwAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAAALgAECgQJCwAAAA==.Maverick:BAACLgAFFH8TAAIjAAUJRBunCABiAQAjAAUJRBunCABiAQAuAAQKfxsAAyMABwlUIsIVAGECACMABwlNIsIVAGECACUABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCAAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAABLgAECn8XAAIDAAcJQw8IawBWAQADAAcJQw8IawBWAQAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEALgAECgYJDQABLgAECggJPQAmAGsjAA==.',
Mo='Mogar:BAABLgAECn8WAAIcAAYJkxyRFAClAQAcAAYJkxyRFAClAQAAAA==.Mogina:BAAALgADCggJCAAAAA==.Monkish:BAAALgADCgMJAwAAAA==.Monster:BAAALgAECgUJBQAAAA==.Moonzhine:BAABLgAECn8jAAISAAkJXhWyEgDLAQASAAkJXhWyEgDLAQAAAA==.Moosejaw:BAAALgAECgQJBwAAAA==.Mordread:BAAALgAECggJDgAAAA==.Morgalruk:BAAALgAECgYJDgAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8cAAQDAAgJTRsDAgCBAQADAAYJJh0DAgCBAQAiAAQJCQwTEgAyAQACAAIJRRT8IgBeAAAuAAQKfysABAMACAlXI3wIAAoDAAMACAlXI3wIAAoDACIABgn7GO0oAEsBAAIABQkFEe5MAB0BAAAA.',
Na='Nalanelin:BAABLgAECn8WAAIJAAcJKQ34igA8AQAJAAcJKQ34igA8AQAAAA==.Narukin:BAABLgAECn8cAAIVAAcJVBp2QgCrAQAVAAcJVBp2QgCrAQAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAcJGgAKAGAaAA==.',
Ni='Nivmizzet:BAABLgAECn8wAAMMAAgJ+BkBSgCyAQAMAAcJfBoBSgCyAQAgAAYJ8BUqLQAJAQAAAA==.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAACLgAFFH8KAAIBAAQJ1yXEDwC5AQABAAQJ1yXEDwC5AQAuAAQKf00AAwEACQlhI+IDAGkDAAEACQlhI+IDAGkDAB0ABwkeHkkpAI4BAAAA.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAgAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMhAAgJzxxbCwBYAgAhAAcJgB1bCwBYAgARAAgJhRoVIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAABLgAFFH8NAAISAAYJmR2FCgCYAQASAAYJmR2FCgCYAQAAAA==.',
Ov='Ova:BAAALgAECgEJAQAAAA==.',
Ox='Oxxo:BAABLgAECn8WAAInAAYJHwsnEADxAAAnAAYJHwsnEADxAAAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAABLgAECn8dAAIDAAYJDRn7YgBpAQADAAYJDRn7YgBpAQAAAA==.',
Pe='Penelöpe:BAAALgAECgMJAwAAAA==.Penoosê:BAAALgADCgEJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Phoinyx:BAAALgAECgkJDwAAAA==.Phuriosa:BAAALgAECgcJCgABLgAFFAMJBQAFAGoUAA==.Phury:BAACLgAFFH8FAAIFAAMJahTcMwDRAAAFAAMJahTcMwDRAAAuAAQKfyQAAwUACQlSGs4kABQCAAUACAkbGc4kABQCAAsAAgkmF/JWAJsAAAAA.Physinyx:BAAALgAECgkJCgAAAA==.Physta:BAAALgADCggJCwAAAA==.',
Pi='Pizza:BAAALgAECgYJEwAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAFFAEJBAAAAA==.Porkmancer:BAAALgAECgYJCgABLgAECggJJgAJAEwfAA==.Porkslope:BAABLgAECn8mAAIJAAgJTB+yIQBvAgAJAAgJTB+yIQBvAgAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAAALgAECgYJCwAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn85AAMMAAgJ3x7RGgB3AgAMAAgJ3x7RGgB3AgAWAAMJag4jJgBsAAAAAA==.Raiflock:BAAALgAECgcJDAAAAA==.Ranalastus:BAAALgAECgUJDAAAAA==.Raveneyes:BAEBLgAECn8jAAIMAAkJjhF1PADdAQAMAAkJjhF1PADdAQAAAA==.',
Re='Reiena:BAAALgAECgcJEAAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8oAAIaAAkJqBV5FwA8AgAaAAkJqBV5FwA8AgAAAA==.Reynarena:BAAALgAECgYJCgAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8jAAMVAAkJMBVUNQDcAQAVAAkJMBVUNQDcAQAbAAEJ9QwaMwAlAAAAAA==.',
Ri='Richardhurtz:BAAALgAECgEJAQAAAA==.Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAACLgAFFH8JAAIgAAUJERGJBgAPAQAgAAUJERGJBgAPAQAuAAQKfykAAyAACQkgItABAKYCACAACAlaI9ABAKYCAAwAAQmHGQMLAUsAAAAA.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMVAAkJgCAPFQDZAgAVAAkJgCAPFQDZAgAYAAEJ+RRiaQBAAAAAAA==.Rocksann:BAAALgAECgEJAgAAAA==.Rodel:BAAALgAECgEJAQAAAA==.Roquan:BAABLgAECn8wAAIZAAgJ7RtWBwD7AQAZAAgJ7RtWBwD7AQAAAA==.Roulette:BAAALgAECgUJDAAAAA==.',
Ru='Rubmyrott:BAAALgAECgcJDAAAAA==.Runalot:BAAALgAECgYJBgAAAA==.',
['Rê']='Rêdd:BAABLgAECn8VAAIKAAcJSg8xMAA9AQAKAAcJSg8xMAA9AQAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Sadiebuding:BAAALgAECgEJAQAAAA==.Salswarriah:BAAALgAECgYJEgAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scottlee:BAAALgADCgIJBAABLgAECggJIwAdAKcUAA==.Scrumbles:BAAALgAECgcJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwAEAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtbonesnap:BAAALgAECgYJCgAAAA==.Sgtpunchy:BAAALgADCgMJBQABLgAECgYJCgAEAAAAAA==.',
Sh='Shakuro:BAAALgAECgEJAgAAAA==.Shallash:BAAALgADCgUJBgAAAA==.Shamageddon:BAAALgAECgIJBAAAAA==.Shamanizim:BAACLgAFFH8IAAMdAAQJRBHJHwAHAQAdAAQJRBHJHwAHAQAXAAEJfgSHFQA+AAAuAAQKfyoABB0ACAmUHNcZAP0BAB0ACAkpHNcZAP0BABcABwnlFY8UAFMBAAEAAgknBlm6AD0AAAAA.Shausin:BAAALgAECggJCAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAFFAMJCAATAJ8gAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shinoikari:BAACLgAFFH8GAAIZAAIJjQapGACEAAAZAAIJjQapGACEAAAuAAQKfycAAxkACQkNEaQIANUBABkACQkNEaQIANUBABIABQnJCA89AIYAAAAA.Shinotenshi:BAAALgAECgYJDQABLgAFFAIJBgAZAI0GAA==.Shirase:BAABLgAECn8eAAMMAAkJdw4pYwBvAQAMAAkJHgwpYwBvAQAWAAYJRQ5+FAAHAQABLgAFFAQJCgABANclAA==.Shugarae:BAABLgAECn8cAAMLAAgJPQg5OAAZAQALAAgJPQg5OAAZAQAFAAUJcASplgBzAAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skreezy:BAAALgAECgcJDAAAAA==.Skuls:BAAALgAECgIJAgAAAA==.',
Sl='Slashemup:BAABLgAECn8jAAIYAAkJ+RZgDwATAgAYAAkJ+RZgDwATAgAAAA==.Slayter:BAABLgAECn8lAAIFAAkJ2R/mGgBdAgAFAAkJ2R/mGgBdAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.',
Sn='Snakelazers:BAABLgAECn8kAAIaAAkJ+iJDBABYAwAaAAkJ+iJDBABYAwAAAA==.Snufulafagus:BAAALgAECgYJEgAAAA==.',
So='Soju:BAABLgAECn8gAAMBAAkJchSPJAAbAgABAAkJchSPJAAbAgAdAAMJZA6zaACRAAABLgAECgkJKQADAIgiAA==.Songwind:BAABLgAECn8oAAImAAcJqg6ILQA/AQAmAAcJqg6ILQA/AQAAAA==.Soonie:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgADCggJCAAAAA==.',
Sq='Squishypal:BAABLgAECn8WAAMIAAgJSBsENgARAgAIAAgJSBsENgARAgAoAAEJ6xYjPwBBAAAAAA==.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Steelcure:BAAALgAECggJCQAAAA==.Strabo:BAAALgADCggJCQAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAABLgAECn8VAAIKAAYJwwZuSwC9AAAKAAYJwwZuSwC9AAAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgAECgQJBAABLgAECggJHQAFANAMAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8kAAMDAAgJlyHSFwCDAgADAAgJlyHSFwCDAgACAAQJ2BP2VgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAAALgAECgQJCwAAAA==.Teneturadvós:BAAALgAECgcJAwAAAA==.Tentreeadvos:BAAALgAECgEJAQABLgAECgcJAwAEAAAAAA==.Tetris:BAACLgAFFH8LAAIUAAQJrRlXPwBPAQAUAAQJrRlXPwBPAQAuAAQKfzgAAhQACQmgIvwSANUCABQACQmgIvwSANUCAAAA.',
Th='Thellaria:BAAALgADCgIJAgAAAA==.Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgkJDwAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJEQAAAA==.Tiroelin:BAAALgAECgIJAgAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgAECgYJBgABLgAFFAQJFQAFANMkAA==.',
Tr='Tragedeigh:BAAALgAECgUJBQABLgAECgcJHAAGAHAbAA==.Trane:BAAALgAECgIJAgAAAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAABLgAECn8YAAMoAAkJgxEqDgDJAQAoAAkJgxEqDgDJAQATAAEJTQgejgAoAAAAAA==.Truthfully:BAAALgAECgYJDwAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAECgUJDQAAAA==.',
Tu='Tubs:BAAALgAECgEJAQAAAA==.Tuckncloak:BAAALgAECgIJAgAAAA==.',
['Tî']='Tîmon:BAAALgAECgQJBAAAAA==.',
Ug='Ugrup:BAAALgAECgYJDgAAAA==.',
Uj='Ujabula:BAAALgAECgYJEgAAAA==.',
Ul='Ulurak:BAABLgAECn8YAAMOAAgJPw8aGwAaAQAOAAYJkwkaGwAaAQAFAAQJ9QqCngBkAAAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIcAAcJ0wd0FgBJAQAcAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAABLgAECn8WAAIoAAkJdBjcCAAtAgAoAAkJdBjcCAAtAgAAAA==.Unstobubble:BAAALgAECgYJCQAAAA==.',
Va='Valeriya:BAAALgADCgMJAwABLgAECgEJAQAEAAAAAA==.Valisanna:BAAALgADCggJDQAAAA==.Vallorien:BAABLgAECn8WAAIoAAYJOyEZDgDKAQAoAAYJOyEZDgDKAQAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJOAAVAEEaAA==.',
Ve='Vegtam:BAAALgAECgEJAQAAAA==.Velaryn:BAAALgAFFAIJAgAAAA==.Velnia:BAAALgAECgYJCwAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgAECgMJBwAAAA==.',
Wa='Wanks:BAAALgAECgQJCgAAAA==.Warmoon:BAAALgAECgMJAwAAAA==.Warskul:BAAALgADCgEJAQAAAA==.Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Wholy:BAAALgAECgMJBgAAAA==.',
Wi='Wickedromeo:BAAALgAECgMJAwAAAA==.',
Wo='Wolfmother:BAABLgAECn8jAAIdAAgJpxTcJQCkAQAdAAgJpxTcJQCkAQAAAA==.',
Xa='Xaanii:BAABLgAECn8WAAITAAYJcBttJADPAQATAAYJcBttJADPAQAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAABLgAECn8WAAIUAAYJ+wFABQF/AAAUAAYJ+wFABQF/AAAAAA==.',
Xe='Xeeria:BAACLgAFFH8ZAAIBAAUJShPtIQA/AQABAAUJShPtIQA/AQAuAAQKfy4AAwEACQmiHwoNALUCAAEACQmiHwoNALUCAB0AAQlXG3ODAE8AAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIFAAgJ3xYQLgD1AQAFAAgJ3xYQLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgYJDAAAAA==.',
Za='Zamzak:BAAALgADCgQJBAABLgAECgEJAQAEAAAAAA==.Zanthor:BAABLgAECn8VAAIJAAUJbgiP4QC6AAAJAAUJbgiP4QC6AAAAAA==.Zaralina:BAABLgAECn8tAAIKAAkJ0RZjEQAwAgAKAAkJ0RZjEQAwAgAAAA==.Zartox:BAABLgAECn8bAAIpAAgJVBdXAwDcAQApAAgJVBdXAwDcAQAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zarynth:BAAALgAECgEJAQAAAA==.Zaryssa:BAABLgAECn8dAAIdAAgJjwVDSQD1AAAdAAgJjwVDSQD1AAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDwAAAA==.Zephystra:BAAALgADCgQJBAABLgAFFAQJCgABANclAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgAECgUJBgAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAABLgAECn8hAAIDAAgJXx4OHwBYAgADAAgJXx4OHwBYAgAAAA==.',
Zu='Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAAALgAECgEJAgAAAA==.',
['Èd']='Èddy:BAABLgAECn8bAAIFAAkJNBY/GgBiAgAFAAkJNBY/GgBiAgAAAA==.',
['Ût']='Ûthèr:BAAALgADCgEJAQAAAA==.',
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
