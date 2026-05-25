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

local lookup = {'Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Druid-Restoration','Paladin-Retribution','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Warlock-Demonology','Druid-Guardian','Druid-Feral','Evoker-Devastation','Evoker-Augmentation','Priest-Holy','Warrior-Fury','DeathKnight-Blood','Paladin-Holy','Mage-Frost','DemonHunter-Devourer','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','Monk-Mistweaver','Evoker-Preservation','Warrior-Arms','Shaman-Elemental','Mage-Fire','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Rogue-Subtlety','Monk-Brewmaster','Rogue-Assassination','Priest-Discipline','Monk-Windwalker','DemonHunter-Vengeance','DeathKnight-Frost','Paladin-Protection','Mage-Arcane',}
local provider = {region='US',realm='Velen',name='US',type='weekly',zone=46,date='2026-05-24',data={Ad='Addisyn:BAAALgAECgEJBAAAAA==.',
Ae='Aekal:BAAALgADCggJCQAAAA==.Aemetris:BAABLgAECn8UAAIBAAYJ4RkeMgC/AQABAAYJ4RkeMgC/AQAAAA==.Aenicus:BAAALgADCgcJBwAAAA==.Aerina:BAAALgAECgQJCwAAAA==.Aethra:BAAALgADCgYJBgAAAA==.',
Ag='Agamotto:BAAALgAECgYJCgAAAA==.Agromagnetic:BAAALgAECgUJBgAAAA==.Agytha:BAAALgAECgMJAwAAAA==.Agøny:BAAALgADCgMJAwAAAA==.',
Ai='Aidendawn:BAAALgAECgQJBwAAAA==.',
Aj='Ajheria:BAAALgADCgcJCAAAAA==.',
Am='Ameildoran:BAAALgADCgkJCQAAAA==.',
An='Anaru:BAAALgAECgMJBgAAAA==.Anatyriel:BAAALgADCgEJAQAAAA==.Anayanci:BAAALgADCgUJBgAAAA==.Andalaine:BAAALgAECgEJAgAAAA==.Andari:BAAALgADCgEJAQAAAA==.Andramaedra:BAAALgAECgkJAgAAAA==.Anoobornot:BAAALgADCgMJAwAAAA==.Anraleth:BAACLgAFFH8GAAICAAMJPSFZDwAkAQACAAMJPSFZDwAkAQAuAAQKfzwAAwIACQkLJTwCALsCAAIACAnnJDwCALsCAAMAAQkGJirQAGgAAAAA.',
Ap='Aponi:BAAALgAECgQJBQAAAA==.',
Ar='Ardour:BAAALgAECgMJBgABLgAECgYJDgAEAAAAAA==.Arduous:BAAALgAECgMJAwAAAA==.Arihu:BAABLgAECn8fAAIFAAkJlxSNKQDoAQAFAAkJlxSNKQDoAQAAAA==.Arkhana:BAAALgADCgEJAQAAAA==.',
As='Ashenaya:BAAALgAECgcJEQAAAA==.Asparagus:BAABLgAECn8VAAIGAAcJJwvMlwAmAQAGAAcJJwvMlwAmAQAAAA==.',
At='Atlass:BAABLgAECn8YAAIHAAcJ8RmLYwDJAQAHAAcJ8RmLYwDJAQAAAA==.Atrest:BAAALgAECgYJBwAAAA==.',
Au='Augmenter:BAAALgAECgQJBQABLgAFFAcJGgAIAGAaAA==.Aust:BAABLgAECn8UAAIGAAgJ6hNmVACwAQAGAAgJ6hNmVACwAQAAAA==.',
Av='Averlis:BAABLgAECn8UAAIJAAgJpRJ3JgBuAQAJAAgJpRJ3JgBuAQAAAA==.Avoiddance:BAAALgADCgEJAQAAAA==.',
Ax='Axee:BAAALgADCgYJBgAAAA==.',
Az='Azima:BAAALgADCggJCAAAAA==.Azura:BAAALgADCgIJAgAAAA==.Azurargentyr:BAAALgAECgYJDQAAAA==.',
Ba='Babeolicious:BAAALgADCgEJAQAAAA==.Bacon:BAABLgAECn8iAAIGAAgJTQv9ggBKAQAGAAgJTQv9ggBKAQAAAA==.Bambøøze:BAAALgADCgEJAQAAAA==.Bandadi:BAEBLgAECn8wAAIKAAgJox9tFQDVAgAKAAgJox9tFQDVAgAAAA==.Barbelo:BAAALgAECgcJCgAAAA==.Barely:BAAALgAECggJDgAAAA==.Barkweldort:BAAALgAECgYJEQAAAA==.Barreled:BAAALgADCgMJAwAAAA==.Batistabomba:BAAALgAECgYJBgAAAA==.',
Be='Beargruk:BAAALgAECgUJBwAAAA==.Beastly:BAAALgAECgcJBwAAAA==.Beeble:BAAALgAECgMJAwAAAA==.Belii:BAAALgAECgUJBgAAAA==.Bepisthepall:BAAALgAECgEJAgAAAA==.Betterkevin:BAAALgAECgQJDQAAAA==.',
Bi='Bigbooty:BAABLgAECn8WAAMLAAYJeQfbOAB9AAALAAYJHgbbOAB9AAAMAAQJwAZRMABiAAAAAA==.Bigbootyjudi:BAAALgADCgEJAQAAAA==.',
Bl='Blikey:BAABLgAFFH8GAAIHAAIJfiYjigDCAAAHAAIJfiYjigDCAAAAAA==.Bloodyrott:BAAALgAECgQJCQAAAA==.Bluedrake:BAACLgAFFH8JAAMNAAQJRhooAgBZAQANAAQJRhooAgBZAQAOAAEJPRN4TwBEAAAuAAQKfyMAAw0ACAlfHr4EALoCAA0ACAmGHb4EALoCAA4ACAk9FlIZAAMCAAEuAAUUBAkPAAkAqBwA.Blueparrot:BAABLgAECn8uAAIPAAgJpBRUFgD6AQAPAAgJpBRUFgD6AQAAAA==.Bluy:BAAALgADCgMJAwAAAA==.Blädèstorm:BAABLgAECn8ZAAIQAAgJphxQHQDhAQAQAAgJphxQHQDhAQAAAA==.',
Bo='Bonesnap:BAACLgAFFH8UAAMHAAYJdiNgEgDbAQAHAAUJdiNgEgDbAQARAAEJAABIPgAAAAAuAAQKfyAAAwcACQmrIaMXAO4CAAcACQmrIaMXAO4CABEABAmuE4w0AJwAAAAA.Bowkatan:BAAALgAECgEJAgAAAA==.',
Br='Brianisita:BAAALgAECgUJBgAAAA==.Brightmane:BAABLgAECn8WAAISAAYJUx4zJQD8AQASAAYJUx4zJQD8AQAAAA==.Bringinlight:BAAALgAECgUJCAAAAA==.',
Bu='Bubbleicious:BAAALgAECgYJCgAAAA==.Bubbletea:BAAALgAECgcJEQABLgAECgkJKQADAIgiAA==.Bulletz:BAABLgAECn8XAAICAAgJihtbBwDvAQACAAgJihtbBwDvAQAAAA==.Bumpersnouts:BAAALgADCgEJAQAAAA==.Buttfur:BAAALgADCgYJBgAAAA==.',
['Bê']='Bêarwithme:BAAALgAECgIJBAABLgAECgcJEwAEAAAAAA==.',
Ca='Caenzo:BAAALgADCgkJCgAAAA==.Casanna:BAAALgADCgYJBgAAAA==.Cassandria:BAABLgAECn8lAAMFAAgJkA59TAA8AQAFAAcJqw59TAA8AQAJAAgJ2QkqOQD/AAAAAA==.Cassiradra:BAAALgADCgEJAQAAAA==.',
Ce='Cearas:BAAALgADCgkJCwAAAA==.Cedrick:BAAALgADCgcJCQAAAA==.Celiona:BAAALgAECgkJBwAAAA==.Celody:BAAALgAECgYJDAAAAA==.Celticsinsix:BAAALgAECgEJAQAAAA==.Cervixticklr:BAAALgADCgQJAwAAAA==.',
Ch='Chaoten:BAAALgADCgEJAQAAAA==.Chathlia:BAAALgAECgQJBAAAAA==.Chavdar:BAAALgADCgEJAQAAAA==.Chewster:BAABLgAECn8rAAITAAcJvw23jABEAQATAAcJvw23jABEAQAAAA==.Chixie:BAAALgADCgEJAQAAAA==.Choal:BAAALgAECgYJEQAAAA==.Choglana:BAAALgAECgcJCQAAAA==.Chogric:BAABLgAECn83AAMSAAkJhh+NBQATAwASAAkJhh+NBQATAwAGAAQJZw1h+QCXAAABLgAECgcJCQAEAAAAAA==.',
Ci='Civetta:BAAALgAECggJEwAAAA==.',
Cl='Clannininick:BAAALgADCgUJBgAAAA==.Clark:BAAALgADCgEJAQAAAA==.',
Co='Cogswell:BAAALgADCgIJAgAAAA==.Comespankit:BAAALgAECgUJBQAAAA==.Convalesor:BAABLgAECn8UAAIIAAYJQQjrQQDfAAAIAAYJQQjrQQDfAAAAAA==.',
Cr='Crazzywazzy:BAABLgAFFH8IAAIHAAIJJR9AOwCmAAAHAAIJJR9AOwCmAAAAAA==.Crona:BAABLgAECn8aAAISAAkJtg4LPACJAQASAAkJtg4LPACJAQAAAA==.Crsteel:BAAALgAECgEJAQAAAA==.Crzyblnkrton:BAACLgAFFH8PAAITAAYJthCBKwB5AQATAAYJthCBKwB5AQAuAAQKfxcAAhMACAnmH2k5AJACABMACAnmH2k5AJACAAAA.Crzzy:BAAALgAECgQJBwABLgAFFAEJAQAEAAAAAA==.',
Cu='Cuddlez:BAABLgAECn8cAAIPAAgJGwwMKgBVAQAPAAgJGwwMKgBVAQAAAA==.Cultera:BAABLgAECn8UAAIUAAgJehueOgC+AQAUAAgJehueOgC+AQAAAA==.',
Cy='Cyhyraethia:BAABLgAECn8fAAIVAAgJDB+sBQANAgAVAAgJDB+sBQANAgABLgAECgkJOAAUAEEaAA==.Cyndera:BAAALgADCgEJAQAAAA==.',
Da='Dagden:BAAALgADCgYJCAAAAA==.Dalaa:BAAALgAECgIJAgAAAA==.Danda:BAAALgAECgYJCgAAAA==.Daricepicker:BAABLgAECn8pAAIDAAkJiCJPBQA3AwADAAkJiCJPBQA3AwAAAA==.Darkyn:BAABLgAECn8XAAIKAAgJBQ8UWACBAQAKAAgJBQ8UWACBAQAAAA==.Davedadude:BAABLgAECn8dAAIGAAgJQCHKGwCCAgAGAAgJQCHKGwCCAgAAAA==.',
Dd='Ddeonu:BAAALgAECgEJAQAAAA==.Ddeonuu:BAABLgAFFH8JAAMCAAQJPA5jEAAWAQACAAQJ2gxjEAAWAQADAAMJEA0qRgDhAAAAAA==.',
De='Deadlysins:BAABLgAECn8WAAIHAAgJ8wvpbACwAQAHAAgJ8wvpbACwAQAAAA==.Deadscar:BAABLgAECn80AAIWAAkJUiZfAABoAwAWAAkJUiZfAABoAwAAAA==.Deathmasterj:BAAALgADCggJCQAAAA==.Deaths:BAABLgAECn8eAAMXAAgJTRItFgCkAQAXAAgJTRItFgCkAQAUAAEJJQSBDAEdAAAAAA==.Dedfrosty:BAAALgAECgcJDgAAAA==.Demomcgee:BAAALgADCgEJAgABLgAECgYJDwAEAAAAAA==.Demonio:BAAALgADCgQJBgAAAA==.Demonpimp:BAAALgAECgYJDgAAAA==.Dermon:BAAALgAECgYJBgABLgAECgkJJAAYAPoiAA==.Deviously:BAAALgADCgQJBAABLgAECggJFwACAIobAA==.Dewyhuey:BAAALgADCgIJAgAAAA==.',
Di='Dimpiana:BAAALgAECgQJAwAAAA==.Dithariaa:BAAALgAECgYJEwAAAA==.',
Do='Docryktor:BAABLgAECn8xAAIWAAgJShogCAAWAgAWAAgJShogCAAWAgAAAA==.Doomgears:BAAALgAECgYJDQAAAA==.Dotsdead:BAAALgADCgYJDgAAAA==.Dotöri:BAAALgAECggJDwAAAA==.',
Dr='Dragonair:BAABLgAECn8ZAAMZAAcJSAVTIwCwAAAZAAYJiQNTIwCwAAANAAcJ7AJHFACnAAAAAA==.Drashta:BAAALgAECgEJAQAAAA==.Drhoe:BAAALgAECgEJAQAAAA==.Drhurtouch:BAABLgAECn8UAAIaAAYJSR4TFACaAQAaAAYJSR4TFACaAQAAAA==.Dro:BAAALgAECgQJCAAAAA==.Drtybear:BAABLgAECn8VAAMLAAcJ5QzmKgDFAAALAAYJtg3mKgDFAAAMAAMJsQhZMgBaAAAAAA==.Drulissa:BAACLgAFFH8FAAISAAIJeCX/JADPAAASAAIJeCX/JADPAAAuAAQKfxkAAhIACQl1GZktAM0BABIACQl1GZktAM0BAAAA.Druu:BAAALgADCgMJAwABLgAFFAQJCwATAB8TAA==.',
Du='Duogear:BAAALgADCgEJAQAAAA==.Dusters:BAAALgADCgcJCwAAAA==.',
Eb='Ebonwings:BAAALgAECgYJCgABLgAECgcJAwAEAAAAAA==.',
Ed='Ediana:BAABLgAECn8lAAITAAkJzgiVaACRAQATAAkJzgiVaACRAQAAAA==.',
El='Eld:BAAALgAECgEJAQAAAA==.Elmô:BAABLgAECn81AAISAAgJoyDrCADYAgASAAgJoyDrCADYAgAAAA==.Elody:BAAALgADCgYJBgAAAA==.Elvara:BAAALgAECgUJDQAAAA==.',
Eq='Equipwooman:BAAALgADCgIJAgAAAA==.',
Es='Estameling:BAABLgAECn8jAAILAAgJ/hSkCwDUAQALAAgJ/hSkCwDUAQAAAA==.',
Ex='Exash:BAACLgAFFH8HAAIbAAMJNBaSJADeAAAbAAMJNBaSJADeAAAuAAQKfycAAhsACQk7ITUJAP8CABsACQk7ITUJAP8CAAAA.Excizion:BAABLgAECn8XAAIHAAgJ1AmydABYAQAHAAgJ1AmydABYAQAAAA==.',
Fa='Faelynne:BAAALgADCgUJBQAAAA==.Fari:BAAALgAECgcJDAAAAA==.Fathertim:BAAALgAECgYJEwAAAA==.',
Fe='Feannara:BAAALgAECgYJCQAAAA==.Felar:BAAALgADCgEJAQAAAA==.Feldrena:BAAALgADCgcJDAAAAA==.',
Fl='Flangus:BAAALgADCgMJBAAAAA==.Flappydragon:BAAALgADCgIJAgAAAA==.Floraria:BAAALgADCgYJBgAAAA==.',
Fr='Frostii:BAABLgAECn8XAAITAAgJxRkLVgDAAQATAAgJxRkLVgDAAQAAAA==.',
Fu='Fudestamp:BAAALgADCgQJBQAAAA==.Fufight:BAAALgAECgIJAwABLgAECgkJJAAYAPoiAA==.Fugryktor:BAABLgAECn8YAAIVAAYJGBWQDwAzAQAVAAYJGBWQDwAzAQAAAA==.',
Fy='Fyrebug:BAABLgAECn8WAAIBAAYJkwsuYAAIAQABAAYJkwsuYAAIAQAAAA==.',
Ga='Galandor:BAAALgAECgYJEwAAAA==.Gandaalf:BAABLgAECn8WAAMcAAcJCR7XAQBrAgAcAAcJCR7XAQBrAgATAAIJ4Q9RRgFzAAAAAA==.Garrinda:BAAALgAECgkJDgAAAA==.',
Ge='Geeked:BAAALgADCgUJBQAAAA==.Gemhide:BAABLgAECn8aAAIdAAgJkQosEgD7AAAdAAgJkQosEgD7AAAAAA==.Georgharison:BAAALgAECgEJAQAAAA==.',
Gg='Ggwp:BAAALgAECgEJAQAAAA==.',
Gh='Ghae:BAAALgAECgUJBAAAAA==.Ghostsaber:BAAALgADCgEJAQABLgAECggJGQAeAM8cAA==.',
Gi='Gigglyguff:BAABLgAECn8YAAIFAAgJRiACDwDAAgAFAAgJRiACDwDAAgAAAA==.Gimly:BAAALgAECgEJAQAAAA==.Gityadruid:BAAALgADCgMJAwABLgAECgUJCAAEAAAAAA==.Gityahunter:BAAALgADCgcJEQABLgAECgUJCAAEAAAAAA==.',
Gl='Glavenus:BAAALgADCgEJAQAAAA==.',
Go='Gobank:BAAALgADCgIJAgAAAA==.Gobanks:BAABLgAECn85AAIGAAkJXCBEDQDhAgAGAAkJXCBEDQDhAgAAAA==.',
Gr='Graycat:BAAALgADCgIJAgABLgAFFAgJFwAfAMsjAA==.Grayele:BAAALgAECgIJAgAAAA==.Grayson:BAAALgAECgYJEQAAAA==.Graysurv:BAACLgAFFH8XAAIfAAgJyyMEAACBAgAfAAgJyyMEAACBAgAuAAQKfykAAh8ACQn6JgUAABQEAB8ACQn6JgUAABQEAAAA.Gregmiller:BAAALgADCgYJBgAAAA==.Gromlin:BAAALgAECgQJBAAAAA==.',
['Gä']='Gäreth:BAAALgADCgYJCwAAAA==.',
Ha='Habachi:BAAALgADCgEJAQAAAA==.Halcrenian:BAAALgAECgIJAgAAAA==.Hamelot:BAAALgADCgMJBAAAAA==.Hamremmi:BAAALgAECgEJAQABLgAFFAcJGgAIAGAaAA==.Haruharu:BAAALgAECgMJAwABLgAECgkJJAAFANkfAA==.Hasalia:BAAALgAECggJCAABLgAFFAIJBQASAHglAA==.',
He='Healsforu:BAAALgAECgUJDQAAAA==.Helly:BAAALgAECgEJAQAAAA==.Hemidall:BAAALgADCgMJAwAAAA==.Herbievore:BAABLgAECn8UAAMLAAgJORgxHAAtAQALAAUJ8RoxHAAtAQAJAAYJAhGdRwC/AAAAAA==.Heunno:BAAALgADCgYJBgABLgADCgcJBwAEAAAAAA==.',
Hi='Hiemy:BAAALgAECgYJBgAAAA==.Hif:BAABLgAECn8gAAIFAAkJgyO0BQAxAwAFAAkJgyO0BQAxAwAAAA==.Highbrittz:BAAALgAECgYJDQAAAA==.',
Ho='Hoakaren:BAABLgAECn8WAAIUAAcJ8BUXTgB7AQAUAAcJ8BUXTgB7AQAAAA==.Hobiscuits:BAEALgADCgQJBAABLgAECgUJDgAEAAAAAA==.Hocus:BAAALgADCgYJBgAAAA==.Holde:BAAALgAECgUJCgAAAA==.',
Hu='Hunterzamb:BAAALgAECgEJAQAAAA==.Huntinator:BAABLgAECn8VAAIDAAcJHhtwMADvAQADAAcJHhtwMADvAQAAAA==.',
['Há']='Hátfield:BAAALgADCgEJAQAAAA==.',
Ih='Ihyo:BAAALgADCgIJAgABLgAECgcJBwAEAAAAAA==.',
Il='Illyy:BAABLgAECn8kAAIPAAgJMgsVLgA5AQAPAAgJMgsVLgA5AQAAAA==.',
In='Indawhole:BAACLgAFFH8cAAIUAAcJSxqnEADLAQAUAAcJSxqnEADLAQAuAAQKfxcAAhQACAn4I9MfAJICABQACAn4I9MfAJICAAAA.',
Ir='Iridori:BAABLgAECn8pAAIPAAgJmiALCQC3AgAPAAgJmiALCQC3AgAAAA==.Irönfist:BAAALgADCgkJEgAAAA==.',
It='Itzzender:BAAALgADCgIJAgAAAA==.',
Iz='Izumiwitabow:BAAALgAECgYJEgAAAA==.',
Ja='Jamerius:BAAALgAECgIJAgAAAA==.Jasmean:BAAALgADCgcJBQAAAA==.Javaluminous:BAABLgAECn8hAAIGAAgJJh6iLgAmAgAGAAgJJh6iLgAmAgAAAA==.Jay:BAAALgADCgcJDQABLgAFFAUJEwAgAEQbAA==.Jaytsukitori:BAACLgAFFH8RAAMFAAQJ3iJgEgCZAQAFAAQJ3iJgEgCZAQAJAAEJgwiKPQA+AAAuAAQKfx0AAwUACAmKIbkMANcCAAUACAmKIbkMANcCAAkAAQlmELd3ADMAAAAA.',
Jh='Jhaeriao:BAAALgAECgYJDAAAAA==.Jhantherox:BAAALgAECgYJBgAAAA==.',
Jo='Joesepi:BAABLgAFFH8SAAIHAAYJtRQ4KQB6AQAHAAYJtRQ4KQB6AQAAAA==.Joham:BAAALgAECgEJAQAAAA==.Jonah:BAAALgAFFAEJAQABLgAFFAIJBQAHAB4YAA==.',
Ju='Juliofoolioo:BAAALgAECgEJAgAAAA==.',
Ka='Kayahli:BAAALgAECgQJBAAAAA==.Kazghul:BAAALgADCgEJAQAAAA==.',
Ke='Kelaeus:BAABLgAECn8VAAITAAYJUQ5x0ABMAQATAAYJUQ5x0ABMAQAAAA==.Keyonslayz:BAAALgADCggJCAAAAA==.',
Kh='Khrønos:BAAALgAECggJCQAAAA==.',
Ki='Killzom:BAAALgADCgEJAQABLgAECgcJFwALAAMiAA==.Kilrah:BAABLgAECn8vAAIXAAkJ1xXEEQDbAQAXAAkJ1xXEEQDbAQAAAA==.Kirian:BAAALgADCgEJAQAAAA==.Kissmyash:BAABLgAECn8WAAITAAYJ9AkJuQD6AAATAAYJ9AkJuQD6AAAAAA==.Kissmycrits:BAABLgAECn8ZAAIDAAQJsB0paABHAQADAAQJsB0paABHAQAAAA==.Kiyana:BAABLgAECn8rAAIXAAcJUA3OJgALAQAXAAcJUA3OJgALAQAAAA==.Kiyoine:BAABLgAECn8bAAIMAAgJuxHxDwCFAQAMAAgJuxHxDwCFAQAAAA==.',
Kn='Knocksteady:BAACLgAFFH8QAAIGAAUJWBihCgBXAQAGAAUJWBihCgBXAQAuAAQKfxsAAgYABwl+IIskAJUCAAYABwl+IIskAJUCAAAA.Knoxform:BAAALgAECgMJBAAAAA==.Knoxhops:BAAALgAECgMJAwABLgAECgMJBAAEAAAAAA==.Knoxreaps:BAAALgAECgIJAgABLgAECgMJBAAEAAAAAA==.Knoxstaggers:BAABLgAECn8gAAIhAAgJJCD2EgB6AgAhAAgJJCD2EgB6AgABLgAECgMJBAAEAAAAAA==.',
Kr='Krzzy:BAAALgAFFAEJAQAAAA==.',
Ku='Kuray:BAAALgAECgEJAgAAAA==.',
Ky='Kynbrookera:BAABLgAECn8ZAAIFAAgJvwuySQBIAQAFAAgJvwuySQBIAQAAAA==.Kyujin:BAAALgADCgEJAQAAAA==.',
['Kì']='Kìnky:BAAALgAECgUJCwAAAA==.',
La='Laetha:BAAALgADCgUJBQAAAA==.',
Le='Lemicall:BAAALgADCgQJCAAAAA==.Lethiferous:BAAALgAECgEJAQAAAA==.Letmespankit:BAAALgADCgYJDAAAAA==.Lezigo:BAABLgAECn8gAAITAAgJMxMQYAClAQATAAgJMxMQYAClAQAAAA==.',
Li='Licht:BAAALgAECgYJCwAAAA==.Lik:BAAALgAECgQJBwAAAA==.Lilhorror:BAAALgADCgMJAwAAAA==.Lilyheart:BAAALgADCgYJBgAAAA==.Linai:BAABLgAECn8aAAMiAAgJUQjeDAA+AQAiAAgJEQjeDAA+AQAgAAEJmA1YTwA2AAAAAA==.Lit:BAAALgAECgEJAgAAAA==.Littledog:BAACLgAFFH8FAAIIAAMJyhB0GwDqAAAIAAMJyhB0GwDqAAAuAAQKfywAAwgACAltF94dALEBAAgACAltF94dALEBACMAAwkdFK09AL8AAAAA.',
Lo='Lockdout:BAAALgADCgEJAQABLgAECggJGQATANkWAA==.Loky:BAABLgAECn8kAAQKAAkJAh91MgD4AQAKAAkJ3B51MgD4AQAdAAQJfhjLJAA1AQAVAAEJeiERJQBhAAAAAA==.Longshanks:BAAALgADCgUJDAAAAA==.Lorna:BAAALgADCgEJAQAAAA==.Lotten:BAAALgAECgQJBgAAAA==.',
Lu='Luckevin:BAAALgAECgYJDgAAAA==.Lunitari:BAAALgAECgQJBAAAAA==.Luthiean:BAAALgADCgQJBAAAAA==.Luthran:BAAALgAECgUJCwABLgAECggJGAAMAD8PAA==.',
Ly='Lynnali:BAAALgADCggJEQAAAA==.Lyrrin:BAAALgADCgYJBgAAAA==.',
Ma='Magedon:BAAALgAECgEJAQAAAA==.Mageyoulaugh:BAABLgAECn8ZAAITAAgJ2RbzUADPAQATAAgJ2RbzUADPAQAAAA==.Magezamb:BAAALgAECgUJDQAAAA==.Magicmann:BAAALgADCgcJAgAAAA==.Magmash:BAAALgADCggJDwAAAA==.Mahito:BAAALgADCgEJAQAAAA==.Mahru:BAAALgADCgYJCAAAAA==.Majhduul:BAAALgADCgMJAwAAAA==.Malafang:BAAALgAECgYJDgAAAA==.Malanah:BAAALgAECgUJDgAAAA==.Marandra:BAAALgADCgcJDAAAAA==.Mathalios:BAAALgAECgIJAgAAAA==.Mattu:BAAALgAECgQJBwAAAA==.Maverick:BAACLgAFFH8TAAIgAAUJRBunCABiAQAgAAUJRBunCABiAQAuAAQKfxsAAyAABwlUIsIVAGECACAABwlNIsIVAGECACIABAmBIpcMAFgBAAAA.Maxbaba:BAAALgAECgEJAQAAAA==.',
Mc='Mcskittelz:BAAALgADCgQJBAAAAA==.',
Me='Meleshanorak:BAAALgADCgUJCgAAAA==.',
Mi='Michaella:BAAALgAECgUJCAAAAA==.Michartson:BAAALgADCgYJBAAAAA==.Mingres:BAABLgAECn8VAAIDAAYJqRAvfQAZAQADAAYJqRAvfQAZAQAAAA==.Miramanie:BAAALgADCgYJBgAAAA==.Misdiagnosed:BAAALgADCgIJAgAAAA==.Mistbrewer:BAAALgADCgIJAgAAAA==.',
Mk='Mk:BAEALgAECgQJBgABLgAECggJOwAkAGsjAA==.',
Mo='Mogar:BAAALgAECgYJEAAAAA==.Mogina:BAAALgADCggJCAAAAA==.Monster:BAAALgAECgUJBQAAAA==.Moonzhine:BAABLgAECn8gAAIRAAgJYxQGGQBrAQARAAgJYxQGGQBrAQAAAA==.Moosejaw:BAAALgAECgQJBwAAAA==.Mordread:BAAALgAECgMJBgAAAA==.Morgalruk:BAAALgAECgYJDgAAAA==.',
My='Myriosheal:BAAALgADCgQJBAAAAA==.Mythx:BAACLgAFFH8ZAAQDAAYJKR8DAgCBAQADAAUJeR0DAgCBAQAfAAMJkA2IGQDgAAACAAIJRRTgHgBjAAAuAAQKfysABAMACAlXI3wIAAoDAAMACAlXI3wIAAoDAB8ABgn7GAomAE4BAAIABQkFEe5MAB0BAAAA.',
Na='Nalanelin:BAABLgAECn8WAAIHAAcJKQ0bggA9AQAHAAcJKQ0bggA9AQAAAA==.Narukin:BAABLgAECn8cAAIUAAcJVBpHPgCwAQAUAAcJVBpHPgCwAQAAAA==.Naturboy:BAAALgADCgYJBgAAAA==.',
Ne='Nessirebette:BAAALgADCgUJCAAAAA==.Netherwalker:BAAALgAECgIJAgABLgAFFAcJGgAIAGAaAA==.',
Ni='Nivmizzet:BAABLgAECn8pAAMKAAgJAhl6TQCeAQAKAAcJ3hl6TQCeAQAdAAUJyRUqLQAJAQAAAA==.',
No='Nolakai:BAAALgAECgEJAQAAAA==.Nomiro:BAAALgAECgYJDAAAAA==.Noradori:BAAALgAECgEJAQAAAA==.Notdip:BAAALgADCgIJAgAAAA==.Novalea:BAACLgAFFH8GAAIBAAMJ9x0iJgAWAQABAAMJ9x0iJgAWAQAuAAQKf00AAwEACQlhIxoDAG0DAAEACQlhIxoDAG0DABsABwkeHuElAJEBAAAA.',
Nu='Nuru:BAAALgAECgcJEAAAAA==.',
['Nø']='Nøstalgic:BAAALgAECgEJAgAAAA==.',
Ob='Obala:BAAALgADCgIJAgAAAA==.',
Od='Odogaren:BAABLgAECn8ZAAMeAAgJzxxbCwBYAgAeAAcJgB1bCwBYAgAQAAgJhRoVIQBLAgAAAA==.',
Om='Omnithorn:BAAALgAECggJDQAAAA==.',
On='Onei:BAAALgADCgEJAQAAAA==.',
Or='Oramos:BAAALgAECgQJBgAAAA==.Orgóndó:BAABLgAFFH8KAAIRAAUJ2B06DgBIAQARAAUJ2B06DgBIAQAAAA==.',
Ox='Oxxo:BAAALgAECgYJEwAAAA==.',
Pa='Palzamb:BAAALgADCgYJCwAAAA==.Pandacillin:BAAALgAECgQJBAAAAA==.Paraggonn:BAABLgAECn8XAAIDAAYJGhfXaQBDAQADAAYJGhfXaQBDAQAAAA==.',
Pe='Penelöpe:BAAALgAECgMJAwAAAA==.Penoosê:BAAALgADCgEJAgAAAA==.Perlonis:BAAALgAECgYJEwAAAA==.',
Ph='Phatocaster:BAAALgADCgIJBAAAAA==.Phoinyx:BAAALgAECgkJDwAAAA==.Phuriosa:BAAALgAECgcJCgABLgAECgkJIwAFAKYZAA==.Phury:BAABLgAECn8jAAMFAAkJphmIIgAUAgAFAAgJGxmIIgAUAgAJAAIJJhfjTwChAAAAAA==.Physinyx:BAAALgAECgkJCgAAAA==.Physta:BAAALgADCggJCwAAAA==.',
Pi='Pizza:BAAALgAECgYJEAAAAA==.',
Pl='Plagafel:BAAALgADCgYJBgAAAA==.',
Po='Pomomies:BAAALgAECgMJBAAAAA==.Pooseunpoose:BAAALgAFFAEJBAAAAA==.Porkmancer:BAAALgAECgYJCgABLgAECggJHwAHALUeAA==.Porkslope:BAABLgAECn8fAAIHAAgJtR4lNwACAgAHAAgJtR4lNwACAgAAAA==.',
Pr='Praahv:BAAALgADCgYJBgAAAA==.Profryktor:BAAALgAECgYJCwAAAA==.',
Pu='Purebloods:BAAALgADCgEJAQAAAA==.',
Qu='Quickben:BAAALgAECgIJAgAAAA==.',
Ra='Raenyx:BAABLgAECn8xAAMKAAgJiRx2IwA7AgAKAAgJiRx2IwA7AgAVAAMJag7bIQBuAAAAAA==.Raiflock:BAAALgAECgYJCQAAAA==.Ranalastus:BAAALgAECgQJBwAAAA==.Ravenblack:BAAALgAECgEJAQAAAA==.Raveneyes:BAEBLgAECn8gAAIKAAgJDA/zXQByAQAKAAgJDA/zXQByAQAAAA==.',
Re='Reiena:BAAALgAECgcJEAAAAA==.Relas:BAAALgADCgUJBQAAAA==.Reylilyn:BAABLgAECn8mAAIYAAkJqBUEFQA7AgAYAAkJqBUEFQA7AgAAAA==.Reynarena:BAAALgAECgYJBgAAAA==.',
Rh='Rhaenfyre:BAABLgAECn8jAAMUAAkJMBWeMQDiAQAUAAkJMBWeMQDiAQAlAAEJ9Qx6LwAlAAAAAA==.',
Ri='Richardhurtz:BAAALgADCgEJAQAAAA==.Ricola:BAAALgAFFAIJBAAAAA==.Rivenel:BAABLgAECn8pAAMdAAkJICJ8AQCrAgAdAAgJWiN8AQCrAgAKAAEJhxkB/QBMAAAAAA==.Rivèn:BAAALgADCgEJAQAAAA==.',
Ro='Robinvoid:BAABLgAECn8dAAMUAAkJgCAPFQDZAgAUAAkJgCAPFQDZAgAXAAEJ+RRiaQBAAAAAAA==.Rocksann:BAAALgAECgEJAQAAAA==.Rodel:BAAALgAECgEJAQAAAA==.Roquan:BAABLgAECn8pAAImAAgJ4xu6BwDZAQAmAAgJ4xu6BwDZAQAAAA==.Roulette:BAAALgAECgUJCAAAAA==.',
Ru='Rubmyrott:BAAALgAECgQJCAAAAA==.Runalot:BAAALgAECgYJBgAAAA==.',
['Rê']='Rêdd:BAAALgAECgcJEwAAAA==.',
Sa='Sabeion:BAAALgAECgYJDAAAAA==.Salswarriah:BAAALgAECgYJEgAAAA==.Sanaku:BAAALgAECgYJCAAAAA==.Sanangra:BAAALgADCgEJAQAAAA==.Santo:BAAALgADCgMJAwAAAA==.Sarlyan:BAAALgADCgkJFwAAAA==.Sassafrazz:BAAALgAECgQJBAAAAA==.',
Sc='Scottee:BAAALgAECgIJBAABLgAECgYJGwAbAFESAA==.Scottlee:BAAALgADCgIJBAABLgAECgYJGwAbAFESAA==.Scrumbles:BAAALgAECgcJDwAAAA==.',
Se='Secksytoes:BAAALgAECgMJAwABLgADCgYJCwAEAAAAAA==.Seraphim:BAAALgADCgEJAQAAAA==.Serion:BAAALgADCgMJAwAAAA==.Sewerrat:BAAALgADCggJCAAAAA==.',
Sg='Sgtbonesnap:BAAALgAECgQJBAABLgAECgUJDQAEAAAAAA==.Sgtpunchy:BAAALgADCgMJBQABLgAECgUJDQAEAAAAAA==.',
Sh='Shakuro:BAAALgAECgEJAgAAAA==.Shallash:BAAALgADCgUJBgAAAA==.Shamageddon:BAAALgAECgIJBAAAAA==.Shamanizim:BAABLgAECn8qAAQbAAgJlBx1FwABAgAbAAgJKRx1FwABAgAWAAcJ5RVkEgBUAQABAAIJJwb0qwA+AAAAAA==.Sheeanna:BAAALgAFFAEJAQABLgAFFAIJBQASAHglAA==.Shiftmyself:BAAALgADCgkJDgAAAA==.Shinoikari:BAABLgAECn8nAAMmAAkJDRFuBwDiAQAmAAkJDRFuBwDiAQARAAUJyQi9OACHAAAAAA==.Shinotenshi:BAAALgAECgYJDQABLgAECgkJJwAmAA0RAA==.Shirase:BAABLgAECn8eAAMKAAkJdw5xXAB2AQAKAAkJHgxxXAB2AQAVAAYJRQ5XEgAMAQABLgAFFAMJBgABAPcdAA==.Shugarae:BAABLgAECn8VAAMJAAcJdQSzWADBAAAJAAcJdQSzWADBAAAFAAUJcARqkAByAAAAAA==.',
Si='Sionnocht:BAAALgADCgEJAQAAAA==.Sirlemage:BAAALgADCgMJAwAAAA==.',
Sk='Skina:BAAALgAECgEJAQAAAA==.Skreezy:BAAALgAECgcJDAAAAA==.Skuls:BAAALgADCggJCwAAAA==.',
Sl='Slashemup:BAABLgAECn8gAAIXAAgJuBQ1FgCkAQAXAAgJuBQ1FgCkAQAAAA==.Slayter:BAABLgAECn8kAAIFAAkJ2R9gGQBZAgAFAAkJ2R9gGQBZAgAAAA==.',
Sm='Smaugin:BAAALgAECgIJAgAAAA==.',
Sn='Snakelazers:BAABLgAECn8kAAIYAAkJ+iKuAwBaAwAYAAkJ+iKuAwBaAwAAAA==.Snufulafagus:BAAALgAECgUJEQAAAA==.',
So='Soju:BAABLgAECn8cAAMBAAkJHxItOgCYAQABAAkJHxItOgCYAQAbAAMJZA5iYQCSAAABLgAECgkJKQADAIgiAA==.Songwind:BAABLgAECn8hAAIkAAYJxA1lNQAGAQAkAAYJxA1lNQAGAQAAAA==.Soonie:BAAALgADCgEJAQAAAA==.Soulreever:BAAALgADCggJCAAAAA==.',
Sq='Squishypal:BAAALgAECgYJEwAAAA==.',
St='Starfirelmao:BAAALgAECgYJDwAAAA==.Steelcure:BAAALgAECggJCAAAAA==.Strabo:BAAALgADCggJCQAAAA==.Strawdicks:BAAALgAECgcJAQAAAA==.',
Su='Sugma:BAAALgAECgEJAQAAAA==.Suzsette:BAABLgAECn8VAAIIAAYJwwZ4QwDZAAAIAAYJwwZ4QwDZAAAAAA==.',
Sy='Sylris:BAAALgADCgkJFgAAAA==.Sylvanthis:BAAALgADCgcJBwAAAA==.',
['Sç']='Sçoxx:BAAALgADCgEJAQAAAA==.',
Ta='Taazdingo:BAAALgADCgEJAQAAAA==.Talnora:BAAALgAECgYJDwAAAA==.Tardovski:BAABLgAECn8iAAMDAAcJRx7yKwAEAgADAAcJRx7yKwAEAgACAAQJ2BP2VgDsAAAAAA==.Taurentino:BAAALgAECgkJBQAAAA==.',
Te='Telaris:BAAALgADCgIJAgAAAA==.Telda:BAAALgAECgQJBwAAAA==.Teneturadvós:BAAALgAECgcJAwAAAA==.Tentreeadvos:BAAALgAECgEJAQABLgAECgcJAwAEAAAAAA==.Tetris:BAACLgAFFH8HAAITAAMJDRr8XAAEAQATAAMJDRr8XAAEAQAuAAQKfzgAAhMACQmgIjcQAOQCABMACQmgIjcQAOQCAAAA.',
Th='Thellaria:BAAALgADCgIJAgAAAA==.Thraggoar:BAAALgADCgEJAQAAAA==.Thunsar:BAAALgAECgkJDwAAAA==.Thuzzad:BAAALgADCgUJBQAAAA==.',
Ti='Tickler:BAAALgAECgUJEQAAAA==.Tiroelin:BAAALgADCgUJBwAAAA==.',
To='Toetem:BAAALgADCgQJBgAAAA==.Tox:BAAALgADCgUJBQAAAA==.Toyotama:BAAALgAECgYJBgABLgAFFAQJEQAFAN4iAA==.',
Tr='Tragedeigh:BAAALgAECgUJBQAAAA==.Trane:BAAALgAECgIJAgAAAA==.Tritoch:BAAALgAECgYJEAAAAA==.Troche:BAABLgAECn8YAAMnAAkJgxHYDADNAQAnAAkJgxHYDADNAQASAAEJTQhWhwAoAAAAAA==.Truthfully:BAAALgAECgYJDwAAAA==.Trávpac:BAAALgADCgEJAQAAAA==.',
Tt='Ttjpll:BAAALgAECgUJDQAAAA==.',
Tu='Tubs:BAAALgAECgEJAQAAAA==.Tuckncloak:BAAALgAECgIJAgAAAA==.',
Ug='Ugrup:BAAALgAECgUJCAAAAA==.',
Uj='Ujabula:BAAALgAECgYJEgAAAA==.',
Ul='Ulurak:BAABLgAECn8YAAMMAAgJPw8aGwAaAQAMAAYJkwkaGwAaAQAFAAQJ9QrKlwBkAAAAAA==.',
Un='Uncleskip:BAABLgAECn8bAAIaAAcJ0wd0FgBJAQAaAAcJ0wd0FgBJAQAAAA==.Unhappytoast:BAAALgAECggJEwAAAA==.Unstobubble:BAAALgAECgYJCQAAAA==.',
Va='Valeriya:BAAALgADCgMJAwABLgAECgEJAQAEAAAAAA==.Valisanna:BAAALgADCggJDQAAAA==.Vallorien:BAABLgAECn8WAAInAAYJOyHUDADNAQAnAAYJOyHUDADNAQAAAA==.Valsharess:BAAALgADCgcJBwABLgAECgkJOAAUAEEaAA==.',
Ve='Vegtam:BAAALgAECgEJAQAAAA==.Velnia:BAAALgAECgYJCwAAAA==.Verencia:BAAALgAECgEJAQAAAA==.',
Vi='Vildaren:BAAALgAECgUJCQAAAA==.Vivachel:BAAALgADCgcJCAAAAA==.',
Vo='Vorsan:BAAALgADCgcJBwAAAA==.Vorsane:BAAALgADCgQJBAAAAA==.',
['Và']='Vàli:BAAALgAECgMJBgAAAA==.',
Wa='Wanks:BAAALgAECgQJBwAAAA==.Wasenshi:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgUJCwAAAA==.Weeny:BAAALgAECgcJCwAAAA==.',
Wh='Wholy:BAAALgAECgMJBgAAAA==.',
Wi='Wickedromeo:BAAALgAECgMJAwAAAA==.',
Wo='Wolfmother:BAABLgAECn8bAAIbAAYJURL7PwAHAQAbAAYJURL7PwAHAQAAAA==.',
Xa='Xaanii:BAABLgAECn8WAAISAAYJcBvEIQDSAQASAAYJcBvEIQDSAQAAAA==.Xandius:BAAALgADCgcJDAAAAA==.Xarferrin:BAAALgAECgYJEwAAAA==.',
Xe='Xeeria:BAACLgAFFH8UAAIBAAQJrRPlKwD/AAABAAQJrRPlKwD/AAAuAAQKfywAAgEACAnAIgoNALUCAAEACAnAIgoNALUCAAAA.Xenzull:BAAALgAECgIJAgAAAA==.',
Xk='Xkaliber:BAAALgADCgEJAQAAAA==.',
Xu='Xuecat:BAABLgAECn8kAAIFAAgJ3xYQLgD1AQAFAAgJ3xYQLgD1AQAAAA==.',
Yn='Yn:BAAALgAECgYJDAAAAA==.',
Za='Zamzak:BAAALgADCgQJBAABLgAECgEJAQAEAAAAAA==.Zanthor:BAABLgAECn8VAAIHAAUJbgjy0gC6AAAHAAUJbgjy0gC6AAAAAA==.Zaralina:BAABLgAECn8tAAIIAAkJ0RbFDwA8AgAIAAkJ0RbFDwA8AgAAAA==.Zartox:BAABLgAECn8ZAAIoAAYJBxkuBQBkAQAoAAYJBxkuBQBkAQAAAA==.Zaryn:BAAALgADCgIJAgAAAA==.Zaryssa:BAABLgAECn8ZAAIbAAgJjwUBRAD3AAAbAAgJjwUBRAD3AAAAAA==.Zavinus:BAAALgADCgYJCAAAAA==.',
Ze='Zenzug:BAAALgAECgUJDwAAAA==.Zephystra:BAAALgADCgQJBAABLgAFFAMJBgABAPcdAA==.Zeusqt:BAAALgADCgYJBgAAAA==.',
Zh='Zharfrost:BAAALgAECgUJBQAAAA==.',
Zi='Zicroniah:BAAALgADCgYJCgAAAA==.Ziyuu:BAAALgADCgUJBQAAAA==.',
Zo='Zombiehunter:BAABLgAECn8bAAIDAAgJCR7SHABPAgADAAgJCR7SHABPAgAAAA==.',
Zu='Zuzu:BAAALgADCgMJAwAAAA==.',
['Âr']='Ârc:BAAALgAECgEJAgAAAA==.',
['Èd']='Èddy:BAAALgAECggJEwAAAA==.',
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
