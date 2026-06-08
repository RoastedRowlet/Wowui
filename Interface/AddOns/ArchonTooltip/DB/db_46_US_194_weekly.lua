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

local lookup = {'Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Havoc','Mage-Frost','Priest-Shadow','Shaman-Enhancement','Evoker-Augmentation','Evoker-Preservation','Warlock-Destruction','Mage-Arcane','Druid-Guardian','Monk-Windwalker','Warrior-Fury','Monk-Mistweaver','Priest-Discipline','Priest-Holy','Druid-Feral','Rogue-Subtlety','Mage-Fire','DeathKnight-Frost','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abelothh:BAABLgAECn8bAAMBAAkJOQz1WgCIAQABAAkJxwr1WgCIAQACAAQJOw34EwDwAAAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIDAAcJyBqmMgAvAgADAAcJyBqmMgAvAgAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAABLgAECn8oAAMEAAkJ3RpGDQB6AgAEAAkJ3RpGDQB6AgAFAAUJ+RKdZAD9AAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aidanpryde:BAAALgAECgMJBgAAAA==.Aimster:BAAALgAECgkJBwAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAACLgAFFH8IAAIGAAMJFRxsIgAAAQAGAAMJFRxsIgAAAQAuAAQKfx4AAwYACQnUHC4OAKYCAAYACQnUHC4OAKYCAAcABgl4DJ7EAPUAAAAA.Akoni:BAAALgAECgYJDwABLgAECggJHAAIANAiAA==.',
Al='Allaris:BAABLgAECn8mAAIBAAkJ7AaZbgBZAQABAAkJ7AaZbgBZAQAAAA==.Allíesin:BAAALgAECgUJCAAAAA==.Altryn:BAAALgAECgMJBgAAAA==.Alundrablaze:BAABLgAECn8rAAIJAAkJ5heJGQByAgAJAAkJ5heJGQByAgABLgAECgkJNgACAP0YAA==.',
Am='Amarixa:BAAALgAECgMJAgABLgAECgYJCQAKAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8OAAILAAQJyxm3HwAjAQALAAQJyxm3HwAjAQAuAAQKfzgAAgsACQlrIa4GAMcCAAsACQlrIa4GAMcCAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.Antsy:BAAALgAECgEJAgAAAA==.',
Ap='Apollis:BAAALgAECgMJBgAAAA==.',
Ar='Aram:BAAALgAECggJCgAAAA==.Aranthino:BAAALgAECgkJDwAAAA==.Armson:BAAALgAECgQJBAAAAA==.Aryabhatta:BAABLgAECn8sAAMMAAkJPx5dGACIAgAMAAkJPx5dGACIAgANAAYJ/BTEHQCpAQAAAA==.',
As='Ashrom:BAAALgAECgUJCgAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECggJCQAAAA==.',
At='Athellios:BAAALgAECgEJAQAAAA==.Athenarelia:BAABLgAECn8dAAIJAAgJjBC4QwCQAQAJAAgJjBC4QwCQAQAAAA==.',
Ba='Backbush:BAAALgAECgQJBwAAAA==.Baelskrim:BAABLgAECn8WAAIOAAcJUR26IgDBAQAOAAcJUR26IgDBAQAAAA==.Ballofsoy:BAAALgAECgEJAQAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAABLgAECn9HAAMPAAkJfSCrHACSAgAPAAkJ3B+rHACSAgAQAAMJng7CSABfAAAAAA==.Baoshengdadi:BAAALgAECgEJAQAAAA==.',
Be='Beansination:BAACLgAFFH8FAAIJAAIJrB1bUACfAAAJAAIJrB1bUACfAAAuAAQKfxYAAw4ACQmtF/4fANUBAA4ACQmtF/4fANUBAAkABQnIFPlRAD0BAAAA.Beefsupriem:BAABLgAECn8VAAIRAAkJ+RTrFADVAQARAAkJ+RTrFADVAQAAAA==.Bellatrïx:BAAALgAECgEJAgABLgAECgUJCAAKAAAAAA==.Belliaz:BAAALgAECgYJCQAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgAECgEJAQAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAFFAMJBgAGADkTAA==.',
Bl='Bloodlyfrost:BAABLgAECn8sAAISAAkJCAYYgQBvAQASAAkJCAYYgQBvAQAAAA==.Bloodmaji:BAAALgAECgUJBgAAAA==.Bloodwell:BAAALgAECgUJBQAAAA==.Bloodyguthix:BAAALgAECggJEgAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.Boyo:BAAALgADCgUJBQAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgYJDgABLgAFFAMJEwATAFgaAA==.Breaknasweat:BAAALgAECgIJAgAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bruzera:BAAALgADCgYJDAAAAA==.Bréwtality:BAAALgAECgEJAQABLgAFFAUJDgAPAOocAA==.',
['Bò']='Bòóberry:BAAALgAECgMJAwAAAA==.',
Ca='Calientay:BAAALgAECgYJBgABLgAFFAQJDgAMAP4aAA==.Candyquartz:BAAALgADCgcJFwAAAA==.Caylda:BAAALgAECgUJBQAAAA==.',
Ce='Celladorne:BAAALgAECgcJCwAAAA==.',
Ch='Chibi:BAACLgAFFH8QAAIUAAQJ5gKaDADcAAAUAAQJ5gKaDADcAAAuAAQKfyoAAhQACQnVEskPALwBABQACQnVEskPALwBAAAA.Chronokite:BAABLgAECn8bAAMVAAgJ8gi6PwAfAQAVAAgJ8gi6PwAfAQAWAAcJAgetHQAEAQAAAA==.',
Co='Colair:BAAALgAECgQJBQAAAA==.Corpsegrin:BAAALgAECgIJAgAAAA==.',
Cp='Cpr:BAAALgAECgQJDgAAAA==.',
Cr='Crushed:BAABLgAECn8bAAMXAAgJqRk1DABsAQAXAAgJqRk1DABsAQABAAIJUw009ABtAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMJAAcJvBJkRgBoAQAJAAcJvBJkRgBoAQAOAAUJxwesZwCkAAABLgAECggJGwAVAPIIAA==.',
Da='Da:BAAALgADCgUJBQAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8/AAIGAAkJhhrfDgCeAgAGAAkJhhrfDgCeAgAAAA==.Darkfuse:BAAALgAECgMJBAAAAA==.Darkliter:BAAALgADCgcJBwAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgAECgYJBAABLgAECgcJAQAKAAAAAA==.Dayman:BAABLgAECn8YAAIHAAYJKRxiaQCRAQAHAAYJKRxiaQCRAQAAAA==.',
Db='Dbk:BAAALgAECgYJEgAAAA==.',
De='Deader:BAAALgAECggJEgAAAA==.Deadlyydot:BAABLgAECn8gAAITAAcJpwg5PgAQAQATAAcJpwg5PgAQAQAAAA==.Deadlyykiss:BAABLgAECn8lAAIYAAYJYApQCQDrAAAYAAYJYApQCQDrAAAAAA==.Deathhowl:BAAALgAECgkJDQAAAA==.Demonsaber:BAABLgAECn8bAAIDAAcJSASytACxAAADAAcJSASytACxAAAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAABLgAECn8fAAMRAAgJHg4zIgBTAQARAAgJHg4zIgBTAQADAAQJ2wTV1QB0AAAAAA==.Dengfeijien:BAAALgAECgQJBAABLgAECgkJCAAKAAAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgQJCAAAAA==.Dirtydotz:BAAALgADCgUJBgAAAA==.Disengage:BAACLgAFFH8FAAIMAAMJmQTYYwDBAAAMAAMJmQTYYwDBAAAuAAQKfzAAAgwACAmHETRXAJIBAAwACAmHETRXAJIBAAAA.Displace:BAABLgAECn8bAAIPAAkJcQ9lSgDcAQAPAAkJcQ9lSgDcAQAAAA==.Divinewords:BAAALgAECggJCAAAAA==.Divish:BAABLgAECn8qAAMWAAkJMRymBgCPAgAWAAkJMRymBgCPAgAVAAEJAABwoAAAAAAAAA==.',
Do='Dogan:BAAALgAECgQJBAAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgAECgEJAQAAAA==.Dotaldtrump:BAAALgAECgIJAgAAAA==.',
Dr='Dragkin:BAAALgADCgYJBgAAAA==.Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Dreyvia:BAAALgADCgUJBQAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgYJDQAAAA==.Dropdeath:BAAALgAECgUJBQAAAA==.Druecc:BAABLgAECn8rAAISAAkJPRdwMQBMAgASAAkJPRdwMQBMAgAAAA==.Druidlord:BAABLgAECn8pAAIZAAkJRwNUNwC1AAAZAAkJRwNUNwC1AAAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECggJCQAAAA==.Duckyfur:BAAALgAECgIJAwAAAA==.Dumplíng:BAAALgAECgQJBAABLgAECgkJKAAEAN0aAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgQJCAAKAAAAAA==.',
Dz='Dzhunter:BAAALgAECgkJAgAAAA==.',
Ed='Edgerallen:BAABLgAECn8dAAMLAAkJ+g9YIQCVAQALAAkJ+g9YIQCVAQAaAAYJrgL/YQCHAAAAAA==.',
Ei='Eitherwind:BAAALgAECgEJAQAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECggJGwAVAPIIAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECgkJEwAAAA==.Elianaa:BAAALgADCgMJBgAAAA==.Ellennia:BAAALgAECgUJDAAAAA==.',
Er='Era:BAABLgAECn8nAAIbAAgJnBziGAAgAgAbAAgJnBziGAAgAgAAAA==.',
Ex='Executions:BAAALgAECgUJDgAAAA==.',
Fa='Fanara:BAAALgAECgYJEgAAAA==.Fangtazia:BAAALgADCgQJBAAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAABLgAECn8aAAQJAAgJCB7rFgCGAgAJAAgJCB7rFgCGAgAOAAEJggrupwAnAAAUAAEJHQAyQwAEAAAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgQJBgABLgAECgEJAQAKAAAAAA==.Felbládes:BAAALgAECgMJBQAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8kAAIaAAgJzRfSGwDDAQAaAAgJzRfSGwDDAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Finluzzertok:BAAALgADCgQJBAABLgAECgkJKAASAKgDAA==.Fitua:BAABLgAECn8gAAIPAAkJjwu3fgCGAQAPAAkJjwu3fgCGAQAAAA==.Fizzbann:BAAALgAECgcJEQABLgAECggJHAAIANAiAA==.',
Fk='Fkingbeast:BAAALgAFFAgJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAABLgAECn8YAAIQAAkJwgotHwBQAQAQAAkJwgotHwBQAQAAAA==.Foutre:BAABLgAECn8qAAIEAAkJzw3sJACWAQAEAAkJzw3sJACWAQAAAA==.',
Fr='Froghugger:BAAALgAECgUJBQAAAA==.Fruntstabba:BAAALgAECgEJAQAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fuzzy:BAAALgAECgUJBAABLgAFFAQJDAAcALEgAA==.Fuzzytotems:BAAALgAECgYJDQAAAA==.',
['Få']='Fång:BAAALgAECggJEAAAAA==.',
Ga='Galadenn:BAAALgADCgEJAQAAAA==.Garo:BAABLgAECn88AAIUAAkJ8x8rAwDQAgAUAAkJ8x8rAwDQAgAAAA==.',
Ge='Getlnmyvan:BAABLgAECn8qAAIHAAkJuCA1EQDUAgAHAAkJuCA1EQDUAgAAAA==.',
Gh='Ghanima:BAAALgAECgEJAQABLgAFFAIJAgAKAAAAAA==.Ghoulgranny:BAAALgADCgMJAwAAAA==.Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgAECgEJAQAAAA==.Gile:BAAALgAECgIJAQABLgAECgkJIAAPAI8LAA==.',
Gl='Glert:BAABLgAECn8YAAISAAgJzA8cngCaAQASAAgJzA8cngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQTAAkJcAa5NQA3AQATAAkJcAa5NQA3AQAdAAYJAwS8NQD3AAAeAAYJUAIxVQDiAAAAAA==.Goinsolo:BAABLgAECn8fAAMMAAkJgRFfOQDuAQAMAAkJgRFfOQDuAQANAAYJ4wIOQAC9AAAAAA==.Goldentusk:BAAALgAECgYJCwAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMFAAgJzBnyHwBCAgAFAAgJzBnyHwBCAgAEAAUJeQ6eTQDzAAAAAA==.Gorecrush:BAAALgADCgEJAQABLgAFFAMJEwATAFgaAA==.Gorvax:BAABLgAECn81AAMQAAkJJhvrCgBWAgAQAAkJJhvrCgBWAgAPAAMJ4xCCHAF1AAAAAA==.',
Gr='Grimnyx:BAAALgADCgYJCwAAAA==.Grimstout:BAAALgAECgEJAQAAAA==.Gripe:BAAALgAECgEJAgAAAA==.Groguk:BAAALgAECgIJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgABLgAFFAUJHQAMAMMgAA==.',
Gw='Gwenledyr:BAABLgAECn9HAAQCAAkJux5PBABMAgACAAgJmB1PBABMAgABAAkJzxUBOQDwAQAXAAcJtRs6BwDUAQAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAFFAIJAgAKAAAAAA==.Heimthrall:BAABLgAECn80AAIHAAkJpw3/ZgCWAQAHAAkJpw3/ZgCWAQAAAA==.Hekatee:BAAALgAECgcJEwAAAA==.Hekkruk:BAAALgAECgMJAwABLgAFFAUJEQAfAJchAA==.Hekus:BAEALgAECgUJBQABLgAECgcJEQAKAAAAAA==.Hemesia:BAAALgAECgEJAgAAAA==.Henshin:BAABLgAECn81AAMFAAkJCyTFCgAHAwAFAAgJ7yPFCgAHAwAEAAgJ8BOeHwC9AQAAAA==.Herak:BAABLgAECn8hAAINAAcJxwvAKQBOAQANAAcJxwvAKQBOAQAAAA==.Hermiecrabbs:BAAALgAECgMJAwAAAA==.',
Hi='Highchairjr:BAABLgAECn8nAAMXAAgJZhqbEgAUAQABAAUJfBlmhgAoAQAXAAcJABebEgAUAQAAAA==.Hildaelf:BAAALgAECgYJDwABLgAECggJHAAIANAiAA==.',
Ho='Hojdeeznuts:BAABLgAECn8vAAMGAAgJSx4bFABkAgAGAAgJSx4bFABkAgAHAAYJ6gbm3gDSAAAAAA==.Holyfudge:BAAALgAECgMJAwAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgAECgMJBgAAAA==.Horazi:BAAALgAECgEJAQABLgAFFAMJCAAGABUcAA==.Horohöro:BAAALgAFFAQJBAABLgAFFAQJDgALAMsZAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ib='Ibuprofen:BAAALgAECgEJAQAAAA==.',
Ii='Iil:BAABLgAECn8rAAMSAAgJjRfETwDmAQASAAgJjRfETwDmAQAYAAEJFRSWGwA9AAAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECggJKwASAI0XAA==.',
Is='Istor:BAAALgAECgUJCwAAAA==.',
Ja='Jaxxia:BAABLgAECn8rAAIGAAcJPBBRMwB8AQAGAAcJPBBRMwB8AQABLgAECggJKAAHAMULAA==.',
Jb='Jblaze:BAAALgAECgYJDQAAAA==.',
Je='Jellzilla:BAAALgAECgEJAQAAAA==.Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAABLgAECn8XAAIaAAgJDBX5IACaAQAaAAgJDBX5IACaAQAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgAECgIJAgAAAA==.',
Jo='Joesphkony:BAAALgAECgIJAwAAAA==.Jorick:BAABLgAECn8VAAIHAAYJPQeq5QDKAAAHAAYJPQeq5QDKAAAAAA==.',
Ju='Ju:BAABLgAECn8bAAIcAAYJbRo6KwC+AQAcAAYJbRo6KwC+AQAAAA==.Juzodots:BAAALgAECgEJAgAAAA==.Juzomido:BAACLgAFFH8bAAINAAYJOhqsBQCdAQANAAYJOhqsBQCdAQAuAAQKfygAAg0ACQmQHHkEANMCAA0ACQmQHHkEANMCAAAA.',
Ka='Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn86AAIaAAkJAxpEDgBYAgAaAAkJAxpEDgBYAgAAAA==.Kaline:BAACLgAFFH8FAAIZAAQJfxTFEADnAAAZAAQJfxTFEADnAAAuAAQKfxcAAhkACAnjGqgGAFsCABkACAnjGqgGAFsCAAAA.Karupted:BAABLgAECn8dAAIMAAcJvgosfgA1AQAMAAcJvgosfgA1AQAAAA==.Katianna:BAABLgAECn81AAIJAAkJvB1PDQDhAgAJAAkJvB1PDQDhAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAABLgAECn8iAAIHAAgJkhCKdgB2AQAHAAgJkhCKdgB2AQAAAA==.Keola:BAAALgAECgUJBQABLgAECgkJBgAKAAAAAA==.Kerra:BAAALgADCgMJAwAAAA==.',
Kh='Khalli:BAABLgAECn8zAAMeAAkJOxntEwAsAgAeAAgJ5hjtEwAsAgATAAEJVwduhwArAAAAAA==.Khalwena:BAAALgAECgQJBQAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Kinddurid:BAAALgADCgEJAQAAAA==.Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAABLgAECn8ZAAMHAAcJVRLdhQBZAQAHAAcJVRLdhQBZAQAIAAIJ0wB9VAAdAAAAAA==.Kissesnhugs:BAAALgAECgEJAQAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.Kiwirage:BAAALgAECgUJBgABLgAECggJJAAOAGEbAA==.Kizent:BAAALgAECgYJDgAAAA==.',
Ko='Koraena:BAAALgAECgYJEAAAAA==.Koronuss:BAABLgAFFH8GAAIPAAMJuw8HlADXAAAPAAMJuw8HlADXAAAAAA==.',
Kr='Krivgar:BAAALgAECgcJDwAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgQJBQAAAA==.',
Ku='Kulrig:BAACLgAFFH8TAAQTAAMJWBooHAD7AAATAAMJWBooHAD7AAAeAAMJ/gVzJACHAAAdAAIJ3QIgQABYAAAuAAQKf0cABBMACAl6HFMSADoCABMACAl6HFMSADoCAB4ABwlxF14fAOYBAB0AAQkNBnx9ACQAAAAA.Kurwa:BAAALgADCggJDQAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgAECgUJBQAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECgcJGQAMADcPAA==.Lanlong:BAAALgADCgcJCgABLgAFFAIJAgAKAAAAAA==.Lastmark:BAAALgADCgcJDgAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFgAAAA==.Liliac:BAAALgADCgEJAQAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loryian:BAAALgADCgYJBgAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgAECgYJDAABLgAECggJHAAIANAiAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunalei:BAAALgAECgIJAgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAABLgAECn8cAAIgAAkJmB3IFwBKAgAgAAkJmB3IFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malganon:BAABLgAECn8zAAIHAAkJ2Bz9GgCYAgAHAAkJ2Bz9GgCYAgAAAA==.Marcille:BAAALgAECgEJAQAAAA==.Margarrann:BAAALgAECgMJAwABLgAFFAMJEwATAFgaAA==.Markymark:BAAALgADCgYJBgAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Marzanna:BAAALgAECgYJCgAAAA==.Mashpewtater:BAAALgAECgcJEgAAAA==.Mashpwntato:BAAALgAECgYJCwAAAA==.Mathelmana:BAABLgAECn82AAMCAAkJ/RhVBABLAgACAAkJYhdVBABLAgABAAcJThE5bQBcAQAAAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Me='Mellwin:BAAALgAECgQJBAAAAA==.Mezthyr:BAAALgADCggJCAAAAA==.',
Mi='Miliandra:BAAALgADCgkJEAAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8tAAITAAkJYRIzGwDkAQATAAkJYRIzGwDkAQAAAA==.Miseral:BAABLgAECn9FAAIRAAkJ/SCkBADzAgARAAkJ/SCkBADzAgAAAA==.Missfrost:BAAALgAECgIJCAAAAA==.Mitzy:BAAALgAECgUJCAAAAA==.',
Mo='Moganchee:BAABLgAECn8dAAMSAAkJtgTYkABQAQASAAkJtgTYkABQAQAhAAcJCgJmCADiAAAAAA==.Mooeck:BAAALgAECgUJBwAAAA==.Moostafer:BAAALgAECgMJAwABLgAECgkJLAAPACYhAA==.Mordakka:BAAALgAFFAEJAQABLgAFFAMJEwATAFgaAA==.Morghella:BAABLgAECn9EAAIMAAkJWB93DwDMAgAMAAkJWB93DwDMAgAAAA==.Morney:BAAALgAECgMJAwAAAA==.Morticiaa:BAAALgAECgEJAQAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Mourningwood:BAAALgADCggJCAAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgAECgEJAQAAAA==.Mysticjaina:BAAALgAECggJDgABLgAFFAMJBgAEAHMFAA==.Mythros:BAAALgAECgcJBwAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Na='Nasman:BAAALgADCggJCwAAAA==.',
Ne='Needswowaa:BAAALgAECgcJEgAAAA==.Nesmae:BAAALgAECggJEQABLgAFFAQJDgAMAP4aAA==.',
Ni='Nightwitch:BAAALgAECgYJDAAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAACLgAFFH8OAAIMAAQJ/ho+LwBEAQAMAAQJ/ho+LwBEAQAuAAQKfzAAAgwACQkcI3wMANwCAAwACQkcI3wMANwCAAAA.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Nosferatuu:BAAALgADCgYJBgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECgkJDwAAAA==.Nyxari:BAAALgADCgQJBAAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAECgYJCgAAAA==.',
Ol='Oleyinka:BAAALgAECgcJDgAAAA==.',
Om='Omnissiah:BAABLgAECn8sAAIeAAgJhRWMHADUAQAeAAgJhRWMHADUAQAAAA==.',
On='Once:BAABLgAECn8gAAMHAAcJdRtFZgCYAQAHAAYJyhtFZgCYAQAGAAUJEhHuXwD9AAAAAA==.Oneyedemon:BAAALgADCggJCQAAAA==.Oneyeshoter:BAAALgADCgEJAQABLgAECgcJHQAMAL4KAA==.',
Op='Opaths:BAABLgAECn8sAAMPAAgJJiFpHgCJAgAPAAgJJiFpHgCJAgAiAAIJzRCrKABzAAAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAABLgAECn81AAIIAAkJTSQiAQBAAwAIAAkJTSQiAQBAAwAAAA==.',
Pe='Peng:BAABLgAECn8VAAQjAAkJTw8tIAAiAQAjAAgJ3g8tIAAiAQAkAAEJYwvddQArAAAbAAEJhQLcqwAhAAAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAFFAMJBgAGADkTAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Priedorei:BAAALgAECgUJBQAAAA==.Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgcJBwAAAA==.',
Ps='Psyberollin:BAAALgAECgcJBwABLgAECgkJBgAKAAAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Pv='Pvp:BAABLgAECn8gAAMGAAkJehPLGwAbAgAGAAkJehPLGwAbAgAHAAEJywxCgwEwAAAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJCQAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAABLgAECn8aAAMcAAgJoiPUBgAmAwAcAAgJoiPUBgAmAwAaAAIJ0wUliAA/AAAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAABLgAECn8sAAIGAAkJPhkAFwBGAgAGAAkJPhkAFwBGAgAAAA==.Raydoink:BAAALgAECgYJBgAAAA==.',
Re='Reighan:BAAALgADCgUJBwAAAA==.Remiel:BAAALgAECgEJAQAAAA==.Renka:BAAALgAECgQJCAAAAA==.Revolting:BAABLgAFFH8YAAIDAAYJCRWAJwBxAQADAAYJCRWAJwBxAQAAAA==.Reze:BAAALgAECgEJAQABLgAFFAMJCAACAEUfAA==.Rezme:BAAALgADCgkJFAAAAA==.',
Rh='Rhaeny:BAAALgADCgEJAQAAAA==.',
Ri='Rianne:BAAALgAECgUJDwAAAA==.Rizeen:BAAALgAECgYJEwAAAA==.',
Ro='Rowanbow:BAAALgAECgQJDAAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn87AAMFAAkJ8RqnEQC4AgAFAAkJ8RqnEQC4AgAEAAUJsAeZYACGAAAAAA==.',
Sa='Saberhawk:BAABLgAECn8bAAIMAAcJtA8yawBfAQAMAAcJtA8yawBfAQAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sailarmoon:BAAALgAECgYJBgABLgAECgkJOAABANQXAA==.Sakee:BAAALgAECgEJAQABLgAECgQJCAAKAAAAAA==.Sakurazuka:BAABLgAECn84AAIBAAkJ1BetIQBWAgABAAkJ1BetIQBWAgAAAA==.Salaminizer:BAAALgAECgEJBAAAAA==.Samidudu:BAABLgAECn8YAAIZAAcJSRX3HgBDAQAZAAcJSRX3HgBDAQAAAA==.Sanath:BAABLgAECn8kAAIVAAkJwQ6PKQCSAQAVAAkJwQ6PKQCSAQAAAA==.Sanctusdeus:BAAALgAFFAEJAQAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECgkJOAANAO0YAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8dAAIEAAcJdiRQHwAFAgAEAAcJdiRQHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAABLgAECn8uAAIUAAkJAiNVAQAjAwAUAAkJAiNVAQAjAwAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAFFAMJEwATAFgaAA==.Sevotharte:BAAALgAECgYJBwAAAA==.',
Sg='Sgtmoose:BAAALgADCgYJBgAAAA==.',
Sh='Shadobread:BAAALgAECgcJEwAAAA==.Shadowglider:BAAALgAECgUJBwAAAA==.Shammhammer:BAAALgADCgEJAQAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8WAAIJAAQJOyO/GQB+AQAJAAQJOyO/GQB+AQAuAAQKfysAAgkACQmkJR0BAMEDAAkACQmkJR0BAMEDAAAA.Shioban:BAAALgAECgIJAgAAAA==.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8eAAIfAAkJHRnNCAAsAgAfAAkJHRnNCAAsAgAAAA==.',
Si='Sib:BAAALgAECgMJBAAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Sissyo:BAAALgADCgYJDQAAAA==.',
Sk='Skeets:BAAALgADCgcJDwAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sleasem:BAAALgADCgIJAgAAAA==.Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAABLgAECn8kAAIHAAgJ2RnMOQARAgAHAAgJ2RnMOQARAgAAAA==.Snke:BAAALgADCgcJBwABLgAECggJJAAHANkZAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8tAAIPAAkJvR+tHgDJAgAPAAkJvR+tHgDJAgAAAA==.Somah:BAAALgADCgEJAQAAAA==.Sonofgods:BAABLgAECn8aAAIMAAcJXRWzXQCAAQAMAAcJXRWzXQCAAQAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.Soulsnack:BAAALgAECgQJBgABLgAECggJKgADAOwRAA==.',
Sp='Spectrahl:BAABLgAECn8sAAIOAAgJQRK5LwBzAQAOAAgJQRK5LwBzAQABLgAFFAQJDgAMAP4aAA==.Spedspidspud:BAABLgAECn8aAAIDAAcJ0SCTJwAiAgADAAcJ0SCTJwAiAgAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECgkJLgATAJEQAA==.',
St='Stall:BAAALgAECgIJAQABLgAECgUJBQAKAAAAAA==.Starrbuck:BAABLgAECn81AAMFAAkJsgrYWwAaAQAFAAgJRgjYWwAaAQAEAAEJrwJQngAZAAAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8aAAINAAkJYRIBFQD5AQANAAkJYRIBFQD5AQAAAA==.Stryke:BAABLgAECn8iAAIeAAgJmxqFEQBJAgAeAAgJmxqFEQBJAgAAAA==.',
Su='Sunfury:BAAALgAECgQJBQAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgAECgMJBQAAAA==.Suterareta:BAABLgAECn8tAAMlAAkJdRQ/CgCvAQAlAAkJoxE/CgCvAQARAAYJbxWPPwD9AAAAAA==.',
Sy='Sylareith:BAAALgAECgYJEAAAAA==.Syntara:BAABLgAECn81AAIUAAkJPCCtAwC7AgAUAAkJPCCtAwC7AgAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taggalongg:BAAALgADCgYJBgAAAA==.Taksun:BAABLgAECn8+AAIZAAkJpBohCABeAgAZAAkJpBohCABeAgAAAA==.Tandas:BAAALgAECgQJBAAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn84AAIQAAkJzg33HQBcAQAQAAkJzg33HQBcAQAAAA==.Tav:BAABLgAFFH8QAAMkAAUJRhoHEQA+AQAkAAUJsRcHEQA+AQAjAAIJnxpGIACDAAAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAABLgAECn8cAAMIAAgJ0CJCBQCSAgAIAAgJ0CJCBQCSAgAHAAUJPBFt0gDjAAAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.Theoryhazit:BAAALgAECgEJAQAAAA==.Thewarwithin:BAAALgADCggJCAAAAA==.',
Ti='Tianara:BAACLgAFFH8GAAMGAAMJOROvKwDCAAAGAAMJOROvKwDCAAAHAAIJtRmQfgCYAAAuAAQKfxcAAwYACAmNIfIEAB0DAAYACAmNIfIEAB0DAAgABAk+FWwqALgAAAAA.Titania:BAAALgADCgQJBAAAAA==.',
Tj='Tjismyname:BAAALgAECgYJDwAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgQJBQAAAA==.Tokens:BAAALgAECgcJCgAAAA==.Tolerabull:BAABLgAECn8uAAQGAAkJ2x6rDgCgAgAGAAgJHh6rDgCgAgAIAAYJjwg2JwDPAAAHAAEJexTtawE9AAAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trixxe:BAACLgAFFH8FAAIDAAMJow58XQDEAAADAAMJow58XQDEAAAuAAQKfzIAAgMACQlYGjUiAD4CAAMACQlYGjUiAD4CAAAA.Trojaan:BAABLgAECn8VAAIbAAkJMgVOWgDcAAAbAAkJMgVOWgDcAAAAAA==.Trostani:BAAALgAECgQJBAAAAA==.Trulisha:BAAALgAFFAIJAgAAAA==.Trurala:BAAALgAECgMJBQABLgAECgYJBgAKAAAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgMJAwAAAA==.',
Ue='Uelfaen:BAAALgADCgYJBwAAAA==.',
Un='Undolf:BAAALgAECgQJBwAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8kAAIQAAkJkQaUKAAHAQAQAAkJkQaUKAAHAQAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAABLgAECn8eAAITAAcJcwcQQQADAQATAAcJcwcQQQADAQAAAA==.',
Va='Vacum:BAAALgADCgEJAQAAAA==.Vaderon:BAAALgAECgYJCwAAAA==.Vaelanar:BAAALgAECgYJCAAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vayine:BAACLgAFFH8QAAIIAAQJfweaCwCvAAAIAAQJfweaCwCvAAAuAAQKfysAAggACQkxFKIVAHYBAAgACQkxFKIVAHYBAAAA.Vaynitee:BAAALgADCgcJDQAAAA==.',
Ve='Venmo:BAAALgAECgYJCAABLgAECgkJNQAQACYbAA==.Veridesh:BAAALgAECgcJCwABLgAFFAMJEwATAFgaAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAAALgAECggJEQAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAECgYJBgABLgAFFAMJBQAJAJ0kAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8iAAIQAAkJQhN5FgCpAQAQAAkJQhN5FgCpAQAAAA==.',
Vy='Vynlash:BAAALgADCgYJAQAAAA==.',
['Vì']='Vìcious:BAABLgAECn8tAAMMAAgJNxVDRgDDAQAMAAgJNxVDRgDDAQANAAYJRQ9mLAA8AQAAAA==.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgcJGgADANEgAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wicks:BAAALgAECgYJBgAAAA==.Wigglyears:BAABLgAECn8uAAMTAAkJkRBZIAC7AQATAAkJkRBZIAC7AQAdAAcJwQ8iKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgQJBwAAAA==.',
Ws='Wselfwulf:BAAALgAECgUJEQABLgAECggJHAAIANAiAA==.',
Xa='Xanadaria:BAAALgAECgYJCwABLgAECgkJCAAKAAAAAA==.Xanalluna:BAAALgAECgQJAwABLgAECgkJCAAKAAAAAA==.Xandrelyra:BAAALgADCgMJBQABLgAECgkJCAAKAAAAAA==.Xanvarani:BAAALgAECgkJCAAAAA==.',
Xe='Xenwilder:BAAALgADCgEJAQAAAA==.Xeriirado:BAAALgAECgcJBwAAAA==.Xeril:BAAALgAECgQJBQAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgAECgUJBQAAAA==.Yakushimaru:BAABLgAECn82AAIEAAkJFSELBgDvAgAEAAkJFSELBgDvAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgMJBQAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgIJAwAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAABLgAFFH8MAAIHAAQJKBgJOgAoAQAHAAQJKBgJOgAoAQAAAA==.Zeith:BAABLgAECn8mAAIjAAkJXRb+DgDrAQAjAAkJXRb+DgDrAQAAAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgYJBgAAAA==.',
Zi='Zildon:BAAALgAECgYJCwAAAA==.',
Zu='Zurik:BAACLgAFFH8RAAIfAAUJlyFZAwCDAQAfAAUJlyFZAwCDAQAuAAQKfy0AAh8ACQm6IFoCAPsCAB8ACQm6IFoCAPsCAAAA.',
Zy='Zyphoros:BAAALgADCgkJCwAAAA==.',
['Äz']='Äzúlà:BAAALgAECgcJEAAAAA==.',
['År']='Årrowz:BAAALgAECgIJAgAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAABLgAECn8UAAIHAAcJ9wdIxQD0AAAHAAcJ9wdIxQD0AAAAAA==.',
['Ìt']='Ìta:BAAALgAECgEJAQAAAA==.',
['Ðe']='Ðeadlymyth:BAAALgAECgQJBAAAAA==.',
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
