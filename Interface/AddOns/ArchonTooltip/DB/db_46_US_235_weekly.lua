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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Druid-Restoration','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Warlock-Demonology','Druid-Guardian','Druid-Feral','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Priest-Holy','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Mage-Frost','Warlock-Affliction','DemonHunter-Devourer','Shaman-Enhancement','DemonHunter-Havoc','Shaman-Elemental','Monk-Mistweaver','Mage-Fire','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Priest-Discipline','Monk-Windwalker','Shaman-Restoration','DeathKnight-Frost','Paladin-Protection','Warrior-Arms','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-05-17',data={Ad='Addisyn:BAAALgAECgEJAgAAAA==.',
Ae='Aemetris:BAAALgAECgUJDwAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgUJBgAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ai='Aidendawn:BAAALgAECgQJBwAAAA==.',
Aj='Ajheria:BAAALgADCgcJCAAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.',
An='Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgAECgEJAQAAAA==.Andari:BAAALgADCgEJAQAAAA==.Andramaedra:BAAALgADCgkJCQAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAABLgAECn84AAMBAAkJwCQOAgCxAgABAAgJkiQOAgCxAgACAAEJBiacuQBrAAAAAA==.',
Ap='Aponi:BAAALgAECgMJAwAAAA==.',
Ar='Ardour:BAAALgAECgMJBgABLgAECgYJDQADAAAAAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8fAAIEAAkJlxQdJQDpAQAEAAkJlxQdJQDpAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.',
As='Ashenaya:BAAALgAECgcJEQAAAA==.Asparagus:BAABLgAECn8VAAIFAAcJJwsTggAuAQAFAAcJJwsTggAuAQAAAA==.',
At='Atlass:BAABLgAECn8YAAIGAAcJ8RmLYwDJAQAGAAcJ8RmLYwDJAQAAAA==.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBAABLgAFFAcJFgAHADsWAA==.Aust:BAABLgAECn8UAAIFAAgJ6RPrSgCqAQAFAAgJ6RPrSgCqAQAAAA==.',
Av='Averlis:BAAALgAECgcJEAAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgADCggJCAAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgYJDQAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8fAAIFAAgJtgoyfAA5AQAFAAgJtgoyfAA5AQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAEBLgAECn8wAAIIAAgJox9tFQDVAgAIAAgJox9tFQDVAgAAAA==.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECgUJBwAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECgcJBwAAAA==.Beeble:BAAALgAECgMJAwAAAA==.Belii:BAAALgAECgUJBgAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJDAAAAA==.',
Bi='Bigbooty:BAABLgAECn8VAAMJAAYJeQenLgCAAAAJAAYJHganLgCAAAAKAAQJwAYEKgBiAAAAAA==.Bigbootyjudi:BAAALgADCgEJAQAAAA==.',
Bl='Blikey:BAABLgAFFH8GAAIGAAIJfibqdQDNAAAGAAIJfibqdQDNAAAAAA==.Bloodyrott:BAAALgAECgQJCQAAAA==.Bluedrake:BAACLgAFFH8FAAMLAAMJBxW1BADpAAALAAMJRBC1BADpAAAMAAEJPROSRQBJAAAuAAQKfyMAAwsACAlfHr4EALoCAAsACAmGHb4EALoCAAwACAk9FlIZAAMCAAEuAAUUBAkPAA0AqBwA.Blueparrot:BAABLgAECn8oAAIOAAgJmRQfEwAEAgAOAAgJmRQfEwAEAgAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8ZAAIPAAgJphxJGADrAQAPAAgJphxJGADrAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8TAAMGAAUJnyNUHACLAQAGAAQJnyNUHACLAQAQAAEJAACkNAAAAAAuAAQKfyAAAwYACQmqIaMXAO4CAAYACQmqIaMXAO4CABAABAmuE9YuAJ4AAAAA.Bowkatan:BAAALgAECgEJAgAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAIRAAYJUx4zJQD8AQARAAYJUx4zJQD8AQAAAA==.Bringinlight:BAAALgADCgkJHwAAAA==.',
Bu='Bubbleicious:BAAALgAECgQJBQAAAA==.Bubbletea:BAAALgAECgUJCwABLgAECgkJKQACAIgiAA==.Bulletz:BAABLgAECn8VAAIBAAcJmRpyDQBFAQABAAcJmRpyDQBFAQAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgIJBAABLgAECgcJDwADAAAAAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8lAAMEAAgJkA4gRgA7AQAEAAcJqw4gRgA7AQANAAgJ2AlPNAD7AAAAAA==.Cassiradra:BAAALgADCgEJAQAAAA==.',
Ce='Cearas:BAAALgADCgkJCQAAAA==.Cedrick:BAAALgADCgcJCQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgYJDAAAAA==.Celticsinsix:BAAALgAECgEJAQAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAABLgAECn8hAAISAAcJWQzTiAAzAQASAAcJWQzTiAAzAQAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAAALgAECgYJDQAAAA==.Choglana:BAAALgAECgMJAwAAAA==.Chogric:BAABLgAECn82AAMRAAkJhh+NBQATAwARAAkJhh+NBQATAwAFAAQJZw0t3QCbAAABLgAECgMJAwADAAAAAA==.',
Ci='Civetta:BAAALgAECgYJDwAAAA==.',
Cl='Clannininick:BAAALgADCgUJBgAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Comespankit:BAAALgAECgMJAwAAAA==.Convalesor:BAAALgAECgYJEwAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8HAAIGAAIJJR9AOwCmAAAGAAIJJR9AOwCmAAAAAA==.Crona:BAABLgAECn8aAAIRAAkJtw4LPACJAQARAAkJtw4LPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8PAAISAAYJthB2HwCJAQASAAYJthB2HwCJAQAuAAQKfxcAAhIACAnmH2k5AJACABIACAnmH2k5AJACAAAA.Crzzy:BAAALgAECgQJBwAAAA==.',
Cu='Cuddlez:BAABLgAECn8bAAIOAAgJGwwNJQBfAQAOAAgJGwwNJQBfAQAAAA==.Cultera:BAAALgAECggJEwAAAA==.',
Cy='Cyhyraethia:BAABLgAECn8fAAITAAgJDB+sBQANAgATAAgJDB+sBQANAgABLgAECgkJOAAUAEAaAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Danda:BAAALgAECgYJCgAAAA==.Daricepicker:BAABLgAECn8pAAICAAkJiCJPBQA3AwACAAkJiCJPBQA3AwAAAA==.Darkyn:BAABLgAECn8WAAIIAAgJBA9HUAB5AQAIAAgJBA9HUAB5AQAAAA==.Davedadude:BAABLgAECn8WAAIFAAgJPx6yHwBPAgAFAAgJPx6yHwBPAgAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAABLgAFFH8FAAIBAAMJgQ5vEQDcAAABAAMJgQ5vEQDcAAAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIGAAgJ8wvpbACwAQAGAAgJ8wvpbACwAQAAAA==.Deadscar:BAABLgAECn80AAIVAAkJUiY+AABwAwAVAAkJUiY+AABwAwAAAA==.Deathmasterj:BAAALgADCggJCAAAAA==.Deaths:BAABLgAECn8ZAAMWAAgJXA5JGABnAQAWAAgJXA5JGABnAQAUAAEJJQSB9AAeAAAAAA==.Dedfrosty:BAAALgAECgQJBgAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwADAAAAAA==.Demonio:BAAALgADCgQJBgAAAA==.Demonpimp:BAAALgAECgYJCQAAAA==.Deviously:BAAALgADCgQJBAABLgAECgcJFQABAJkaAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Di='Dimpiana:BAAALgAECgQJAwAAAA==.Dithariaa:BAAALgAECgYJDgAAAA==.',
Do='Docryktor:BAABLgAECn8pAAIVAAgJ3RejCQDMAQAVAAgJ3RejCQDMAQAAAA==.Doomgears:BAAALgAECgYJDQAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Dragonair:BAAALgAECgYJEgAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAAALgAECgUJDwAAAA==.Dro:BAAALgAECgQJCAAAAA==.Drtybear:BAAALgAECgYJEAAAAA==.Drulissa:BAABLgAECn8ZAAIRAAkJdRmZLQDNAQARAAkJdRmZLQDNAQAAAA==.Druu:BAAALgADCgMJAwABLgAFFAQJBwASALcSAA==.',
Du='Duogear:BAAALgADCgIJAgAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
Eb='Ebonwings:BAAALgAECgYJCgABLgAECgcJAwADAAAAAA==.',
Ed='Ediana:BAABLgAECn8jAAISAAcJMgkKmQAXAQASAAcJMgkKmQAXAQAAAA==.',
El='Elmô:BAABLgAECn8vAAIRAAgJpCA5BwDgAgARAAgJpCA5BwDgAgAAAA==.Elody:BAAALgADCgYJBgAAAA==.Elvara:BAAALgAECgUJDAAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8jAAIJAAgJ/hSkCwDUAQAJAAgJ/hSkCwDUAQAAAA==.',
Ex='Exash:BAABLgAECn8kAAIXAAkJOyE1CQD/AgAXAAkJOyE1CQD/AgAAAA==.Excizion:BAAALgAECgcJDAAAAA==.',
Fa='Faelynne:BAAALgADCgUJBQAAAA==.Fari:BAAALgAECgUJBgAAAA==.Fathertim:BAAALgAECgYJDgAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frostii:BAABLgAECn8XAAISAAgJxRkTSQDGAQASAAgJxRkTSQDGAQAAAA==.',
Fu='Fudestamp:BAAALgADCgQJBQAAAA==.Fufight:BAAALgAECgIJAwABLgAECgkJIwAYAO4iAA==.Fugryktor:BAAALgAECgYJEgAAAA==.',
Fy='Fyrebug:BAAALgAECgUJEQAAAA==.',
Ga='Galandor:BAAALgAECgUJDwAAAA==.Gandaalf:BAABLgAECn8VAAMZAAcJth3XAQBrAgAZAAcJth3XAQBrAgASAAIJ4Q9RRgFzAAAAAA==.Garrinda:BAAALgAECgkJDgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8aAAIaAAgJkApHEAD6AAAaAAgJkApHEAD6AAAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAbAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIEAAgJRSDFDADCAgAEAAgJRSDFDADCAgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityahunter:BAAALgADCgcJDgABLgADCgkJHwADAAAAAA==.',
Gl='Glavenus:BAAALgADCgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn85AAIFAAkJWyCzCQDrAgAFAAkJWyCzCQDrAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAcJEQAcAL0jAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAAALgAECgUJDAAAAA==.Graysurv:BAACLgAFFH8RAAIcAAcJvSMEAACBAgAcAAcJvSMEAACBAgAuAAQKfykAAhwACQn6JgUAABQEABwACQn6JgUAABQEAAAA.Gromlin:BAAALgAECgMJAwAAAA==.',
['Gä']='Gäreth:BAAALgADCgYJCwAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hamremmi:BAAALgAECgEJAQABLgAFFAcJFgAHADsWAA==.Hasalia:BAAALgAECggJCAABLgAECgkJGQARAHUZAA==.',
He='Healsforu:BAAALgAECgUJDQAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMJAAgJORhaFwAuAQAJAAUJ8RpaFwAuAQANAAYJAhFiQgC5AAAAAA==.Heunno:BAAALgADCgYJBgABLgADCgcJBwADAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAABLgAECn8fAAIEAAkJgSO0BQAxAwAEAAkJgSO0BQAxAwAAAA==.Highbrittz:BAAALgAECgYJDQAAAA==.',
Ho='Hoakaren:BAABLgAECn8WAAIUAAcJ8BUjQwB+AQAUAAcJ8BUjQwB+AQAAAA==.Hobiscuits:BAEALgADCgQJBAABLgAECgUJCQADAAAAAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgQJBgAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAAALgAECgYJEwAAAA==.',
['Há']='Hátfield:BAAALgADCgEJAQAAAA==.',
Ih='Ihyo:BAAALgADCgIJAgABLgAECgcJBwADAAAAAA==.',
Il='Illyy:BAABLgAECn8kAAIOAAgJMgsYKQBCAQAOAAgJMgsYKQBCAQAAAA==.',
In='Indawhole:BAACLgAFFH8VAAIUAAYJ9BcSCQCYAQAUAAYJ9BcSCQCYAQAuAAQKfxcAAhQACAn4I98gABYCABQACAn4I98gABYCAAAA.',
Ir='Iridori:BAABLgAECn8pAAIOAAgJmSAiBwDDAgAOAAgJmSAiBwDDAgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAALgAECgUJDQAAAA==.',
Ja='Jamerius:BAAALgAECgIJAgAAAA==.Jasmean:BAAALgADCgMJAwAAAA==.Javaluminous:BAABLgAECn8hAAIFAAgJJh4OJgAuAgAFAAgJJh4OJgAuAgAAAA==.Jay:BAAALgADCgcJDQABLgAFFAUJEwAdAEQbAA==.Jaytsukitori:BAACLgAFFH8OAAMEAAQJxx7VEQB4AQAEAAQJxx7VEQB4AQANAAEJgwhGNQA+AAAuAAQKfx0AAwQACAmKIbkMANcCAAQACAmKIbkMANcCAA0AAQlmEBxsADMAAAAA.',
Jh='Jhaeriao:BAAALgAECgQJCgAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8SAAIGAAYJtRTLGgCQAQAGAAYJtRTLGgCQAQAAAA==.Joham:BAAALgAECgEJAQAAAA==.Jonah:BAAALgAECgUJDAABLgAECggJGAAGAGUjAA==.',
Ju='Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAISAAYJUQ5x0ABMAQASAAYJUQ5x0ABMAQAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Ki='Killzom:BAAALgADCgEJAQABLgAECgYJFgAJANAjAA==.Kilrah:BAABLgAECn8vAAIWAAkJ1xW6DgDjAQAWAAkJ1xW6DgDjAQAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAAALgAECgQJEAAAAA==.Kissmycrits:BAABLgAECn8YAAICAAQJsB3VWQBNAQACAAQJsB3VWQBNAQAAAA==.Kiyana:BAABLgAECn8lAAIWAAcJ+wtIJAD/AAAWAAcJ+wtIJAD/AAAAAA==.Kiyoine:BAABLgAECn8bAAIKAAgJuRGnDQCJAQAKAAgJuRGnDQCJAQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8PAAIFAAUJWBihCgBXAQAFAAUJWBihCgBXAQAuAAQKfxsAAgUABwl+IIskAJUCAAUABwl+IIskAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAADAAAAAA==.Knoxreaps:BAAALgAECgIJAgABLgAECgMJBAADAAAAAA==.Knoxstaggers:BAABLgAECn8gAAIeAAgJJCD2EgB6AgAeAAgJJCD2EgB6AgABLgAECgMJBAADAAAAAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kynbrookera:BAABLgAECn8XAAIEAAgJvwtrQwBHAQAEAAgJvwtrQwBHAQAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgUJCwAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgQJCAAAAA==.Lethiferous:BAAALgAECgEJAQAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8eAAISAAgJMxMbVgCiAQASAAgJMxMbVgCiAQAAAA==.',
Li='Licht:BAAALgAECgYJCwAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8aAAMfAAgJUQigCwA7AQAfAAgJEQigCwA7AQAdAAEJmA3ORwA2AAAAAA==.Lit:BAAALgAECgEJAgAAAA==.Littledog:BAABLgAECn8sAAMHAAgJbhdMGgCsAQAHAAgJbhdMGgCsAQAgAAMJHRStPQC/AAAAAA==.',
Lo='Loky:BAABLgAECn8iAAQIAAkJAh8MKgAAAgAIAAkJ3B4MKgAAAgAaAAQJfhjLJAA1AQATAAEJeiFjHgBjAAAAAA==.Longshanks:BAAALgADCgUJDAAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgQJBgAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lunitari:BAAALgAECgQJBAAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECggJGAAKAD8PAA==.',
Ly='Lynnali:BAAALgADCggJEQAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8WAAISAAgJsRYvTAC9AQASAAgJsRYvTAC9AQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Majhduul:BAAALgADCgMJAwAAAA==.Malafang:BAAALgAECgUJCgAAAA==.Malanah:BAAALgAECgUJCwAAAA==.Marandra:BAAALgADCgcJDAAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAAALgAECgMJAwAAAA==.Maverick:BAACLgAFFH8TAAIdAAUJRBunCABiAQAdAAUJRBunCABiAQAuAAQKfxsAAx0ABwlUIsIVAGECAB0ABwlNIsIVAGECAB8ABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCAAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAAALgAECgYJEQAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEALgAECgMJAwABLgAECggJNwAhAGsjAA==.',
Mo='Mogar:BAAALgAECgUJDAAAAA==.Mogina:BAAALgADCggJCAAAAA==.Monster:BAAALgAECgUJBQAAAA==.Moonzhine:BAABLgAECn8eAAIQAAgJYxTzFAB8AQAQAAgJYxTzFAB8AQAAAA==.Moosejaw:BAAALgAECgQJBAAAAA==.Mordread:BAAALgAECgMJAwAAAA==.Morgalruk:BAAALgAECgYJDQAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8ZAAQCAAYJKR8DAgCBAQACAAUJeR0DAgCBAQAcAAMJkA2UFQDoAAABAAIJRRRFGgBqAAAuAAQKfysABAIACAlWI3wIAAoDAAIACAlWI3wIAAoDABwABgn7GKAgAFoBAAEABQkFEe5MAB0BAAAA.',
Na='Nalanelin:BAAALgAECggJEQAAAA==.Narukin:BAABLgAECn8cAAIUAAcJUxrBNQCxAQAUAAcJUxrBNQCxAQAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAcJFgAHADsWAA==.',
Ni='Nivmizzet:BAABLgAECn8pAAMIAAgJARlqQQCmAQAIAAcJ3hlqQQCmAQAaAAUJyBUqLQAJAQAAAA==.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAABLgAECn9IAAMiAAkJRCNgAgBuAwAiAAkJRCNgAgBuAwAXAAcJwxvEJgBtAQAAAA==.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAgAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMbAAgJzxxbCwBYAgAbAAcJgB1bCwBYAgAPAAgJhRoVIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAABLgAFFH8IAAIQAAQJ+httEwD3AAAQAAQJ+httEwD3AAAAAA==.',
Ox='Oxxo:BAAALgAECgYJDgAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAAALgAECgYJEgAAAA==.',
Pe='Penoosê:BAAALgADCgEJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Phoinyx:BAAALgAECgkJDwAAAA==.Phuriosa:BAAALgAECgQJBAABLgAECggJIQAEABsZAA==.Phury:BAABLgAECn8hAAIEAAgJGxmRHgAUAgAEAAgJGxmRHgAUAgAAAA==.Physinyx:BAAALgAECgkJCgAAAA==.Physta:BAAALgADCggJCQAAAA==.',
Pi='Pizza:BAAALgAECgYJDgAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAFFAEJBAAAAA==.Porkmancer:BAAALgAECgYJCgABLgAECggJHwAGALUeAA==.Porkslope:BAABLgAECn8fAAIGAAgJtR54LAATAgAGAAgJtR54LAATAgAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAAALgAECgUJCQAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn8pAAMIAAgJ+BpsJAAbAgAIAAgJ+BpsJAAbAgATAAEJAABRLABGAAAAAA==.Raiflock:BAAALgAECgMJAwAAAA==.Ranalastus:BAAALgAECgQJBwAAAA==.Ravenblack:BAAALgAECgEJAQAAAA==.Raveneyes:BAEBLgAECn8eAAIIAAgJDA/pVABtAQAIAAgJDA/pVABtAQAAAA==.',
Re='Reiena:BAAALgAECgYJDgAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8mAAIYAAkJqBVJEQA8AgAYAAkJqBVJEQA8AgAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8fAAIUAAgJzxRDPACXAQAUAAgJzxRDPACXAQAAAA==.',
Ri='Richardhurtz:BAAALgADCgEJAQAAAA==.Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAABLgAECn8oAAMaAAkJ/CEuAQCqAgAaAAgJMSMuAQCqAgAIAAEJhxl85wBOAAAAAA==.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMUAAkJgCAPFQDZAgAUAAkJgCAPFQDZAgAWAAEJ+RRiaQBAAAAAAA==.Rocksann:BAAALgAECgEJAQAAAA==.Rodel:BAAALgAECgEJAQAAAA==.Roquan:BAABLgAECn8pAAIjAAgJ5RvSBQDqAQAjAAgJ5RvSBQDqAQAAAA==.Roulette:BAAALgAECgUJCAAAAA==.',
Ru='Rubmyrott:BAAALgAECgQJBwAAAA==.Runalot:BAAALgAECgYJBgAAAA==.',
['Rê']='Rêdd:BAAALgAECgcJDwAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Salswarriah:BAAALgAECgUJDQAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scottee:BAAALgAECgEJAQABLgAECgYJGwAXAFESAA==.Scottlee:BAAALgADCgIJBAABLgAECgYJGwAXAFESAA==.Scrumbles:BAAALgAECgcJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwADAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtpunchy:BAAALgADCgMJBQABLgAECgUJDQADAAAAAA==.',
Sh='Shakuro:BAAALgAECgEJAgAAAA==.Shallash:BAAALgADCgUJBgAAAA==.Shamageddon:BAAALgAECgIJAwAAAA==.Shamanizim:BAABLgAECn8qAAQXAAgJlBxcEwAKAgAXAAgJKRxcEwAKAgAVAAcJ5RUqDwBdAQAiAAIJJwaRmQA+AAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAECgkJGQARAHUZAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shinoikari:BAABLgAECn8eAAMjAAkJEw6/CACUAQAjAAkJ+Q2/CACUAQAQAAUJyQjZMgCHAAAAAA==.Shinotenshi:BAAALgAECgYJDQABLgAECgkJHgAjABMOAA==.Shirase:BAAALgAECgkJEgABLgAECgkJSAAiAEQjAA==.Shugarae:BAABLgAECn8VAAMNAAcJdQSzWADBAAANAAcJdQSzWADBAAAEAAUJcASnhQByAAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skreezy:BAAALgAECgcJDAAAAA==.Skuls:BAAALgADCggJCwAAAA==.',
Sl='Slashemup:BAABLgAECn8eAAIWAAgJcxTGEwCfAQAWAAgJcxTGEwCfAQAAAA==.Slayter:BAABLgAECn8kAAIEAAkJ2B8KFgBcAgAEAAkJ2B8KFgBcAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.',
Sn='Snakelazers:BAABLgAECn8jAAIYAAkJ7iIMBgD5AgAYAAkJ7iIMBgD5AgAAAA==.Snufulafagus:BAAALgAECgUJDgAAAA==.',
So='Soju:BAABLgAECn8bAAMiAAkJHhK3MgCZAQAiAAkJHhK3MgCZAQAXAAIJ6xEbYwBqAAABLgAECgkJKQACAIgiAA==.Songwind:BAABLgAECn8bAAIhAAYJEwpVOADeAAAhAAYJEwpVOADeAAAAAA==.Soonie:BAAALgADCgEJAQAAAA==.',
Sq='Squishypal:BAAALgAECgYJEwAAAA==.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Steelcure:BAAALgAECgYJBgAAAA==.Strabo:BAAALgADCgcJBwAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAAALgAECgUJEAAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgADCgcJBwAAAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8gAAMCAAcJRx4VJQAJAgACAAcJRx4VJQAJAgABAAQJ2BP2VgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAAALgAECgMJAwAAAA==.Teneturadvós:BAAALgAECgcJAwAAAA==.Tentreeadvos:BAAALgAECgEJAQABLgAECgcJAwADAAAAAA==.Tetris:BAACLgAFFH8FAAISAAMJ1BYUUAAOAQASAAMJ1BYUUAAOAQAuAAQKfzgAAhIACQmgIgYMAO4CABIACQmgIgYMAO4CAAAA.',
Th='Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgkJDwAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJEQAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgAECgYJBgABLgAFFAQJDgAEAMceAA==.',
Tr='Trane:BAAALgAECgIJAgAAAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAABLgAECn8XAAMkAAkJixEMGABWAQAkAAkJixEMGABWAQARAAEJTQjyfAApAAAAAA==.Truthfully:BAAALgAECgYJDwAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAECgUJCgAAAA==.',
Tu='Tuckncloak:BAAALgAECgIJAgAAAA==.',
Ug='Ugrup:BAAALgAECgUJBwAAAA==.',
Uj='Ujabula:BAAALgAECgUJEAAAAA==.',
Ul='Ulurak:BAABLgAECn8YAAMKAAgJPw8aGwAaAQAKAAYJkwkaGwAaAQAEAAQJ9Qo4jABlAAAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIlAAcJ0wd0FgBJAQAlAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAAALgAECgYJDwAAAA==.Unstobubble:BAAALgAECgYJCQAAAA==.',
Va='Valeriya:BAAALgADCgMJAwABLgAECgEJAQADAAAAAA==.Valisanna:BAAALgADCggJCwAAAA==.Vallorien:BAAALgAECgUJEQAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJOAAUAEAaAA==.',
Ve='Vegtam:BAAALgAECgEJAQAAAA==.Velnia:BAAALgAECgYJCgAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgAECgEJAQAAAA==.',
Wa='Wanks:BAAALgAECgQJBgAAAA==.Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Wholy:BAAALgAECgIJAwAAAA==.',
Wi='Wickedromeo:BAAALgAECgMJAwAAAA==.',
Wo='Wolfmother:BAABLgAECn8bAAIXAAYJURKmOAAKAQAXAAYJURKmOAAKAQAAAA==.',
Xa='Xaanii:BAAALgAECgUJEQAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAAALgAECgYJDgAAAA==.',
Xe='Xeeria:BAACLgAFFH8QAAIiAAQJrRO/IgAHAQAiAAQJrRO/IgAHAQAuAAQKfywAAiIACAnAIgoNALUCACIACAnAIgoNALUCAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIEAAgJ3xYQLgD1AQAEAAgJ3xYQLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgYJDAAAAA==.',
Za='Zamzak:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.Zanthor:BAABLgAECn8VAAIGAAUJbggtugDEAAAGAAUJbggtugDEAAAAAA==.Zaralina:BAABLgAECn8sAAIHAAkJOhbeEgD3AQAHAAkJOhbeEgD3AQAAAA==.Zartox:BAABLgAECn8ZAAImAAYJBxmcBABuAQAmAAYJBxmcBABuAQAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zaryssa:BAABLgAECn8UAAIXAAgJlwSvRgDPAAAXAAgJlwSvRgDPAAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDQAAAA==.Zephystra:BAAALgADCgQJBAABLgAECgkJSAAiAEQjAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgADCgkJCwAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAAALgAECggJEwAAAA==.',
Zu='Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAAALgAECgEJAgAAAA==.',
['Èd']='Èddy:BAAALgAECgYJDwAAAA==.',
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
