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

local lookup = {'Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Havoc','Mage-Frost','Priest-Shadow','Shaman-Enhancement','Evoker-Augmentation','Evoker-Preservation','Warlock-Destruction','Priest-Holy','Mage-Arcane','Druid-Guardian','Monk-Windwalker','Warrior-Fury','Monk-Mistweaver','Priest-Discipline','Druid-Feral','Rogue-Subtlety','Mage-Fire','DeathKnight-Frost','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abelothh:BAABLgAECn8bAAMBAAkJOQyWXwCAAQABAAkJxwqWXwCAAQACAAQJOw34EwDwAAAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIDAAcJyBqmMgAvAgADAAcJyBqmMgAvAgAAAA==.Aelita:BAAALgAECgUJBQAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAABLgAECn8oAAMEAAkJ3BoBDgB4AgAEAAkJ3BoBDgB4AgAFAAUJ+RJMZwD8AAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aidanpryde:BAAALgAECgMJBgAAAA==.Aimster:BAAALgAECgkJBwAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAACLgAFFH8MAAIGAAQJAyKoEwCHAQAGAAQJAyKoEwCHAQAuAAQKfx4AAwYACQnUHPsOAKUCAAYACQnUHPsOAKUCAAcABgl4DPLLAPUAAAAA.Akoni:BAAALgAECgYJDwABLgAECggJIAAIANAiAA==.',
Al='Allaris:BAABLgAECn8mAAIBAAkJ7AZIcwBSAQABAAkJ7AZIcwBSAQAAAA==.Allíesin:BAAALgAECgUJCAAAAA==.Altryn:BAAALgAECgMJBgAAAA==.Alundrablaze:BAABLgAECn8rAAIJAAkJ5hfXGgBxAgAJAAkJ5hfXGgBxAgABLgAECgkJNgACAP0YAA==.',
Am='Amarixa:BAAALgAECgMJAgABLgAECgYJCQAKAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8OAAILAAQJyxllIgAeAQALAAQJyxllIgAeAQAuAAQKfzgAAgsACQlrIRMHAMQCAAsACQlrIRMHAMQCAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.Antsy:BAAALgAECgEJAgAAAA==.',
Ap='Apollis:BAAALgAECgMJBgAAAA==.',
Ar='Aram:BAAALgAECggJCgAAAA==.Aranthino:BAAALgAECgkJEAAAAA==.Arell:BAAALgAECgEJAQAAAA==.Armson:BAAALgAECgQJBAAAAA==.Aryabhatta:BAABLgAECn8sAAMMAAkJPx52GgCCAgAMAAkJPx52GgCCAgANAAYJ/BQDHwCkAQAAAA==.',
As='Ashrom:BAAALgAECgYJDAAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECggJCQAAAA==.',
At='Athellios:BAAALgAECgEJAgAAAA==.Athenarelia:BAABLgAECn8dAAIJAAgJjBBeRgCQAQAJAAgJjBBeRgCQAQAAAA==.',
Ba='Backbush:BAAALgAECgQJBwAAAA==.Baelskrim:BAABLgAECn8WAAIOAAcJUR2FJADAAQAOAAcJUR2FJADAAQAAAA==.Ballofsoy:BAAALgAECgEJAQAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAABLgAECn9HAAMPAAkJfSBsHgCPAgAPAAkJ3B9sHgCPAgAQAAMJng6USwBeAAAAAA==.Baoshengdadi:BAAALgAECgEJAQAAAA==.',
Be='Beansfu:BAAALgAECgIJAgABLgAFFAIJBgAJAKwdAA==.Beansination:BAACLgAFFH8GAAMJAAIJrB1iVgCcAAAJAAIJrB1iVgCcAAAOAAEJ5g6zVAA5AAAuAAQKfxYAAw4ACQmtF3khANUBAA4ACQmtF3khANUBAAkABQnIFPlRAD0BAAAA.Beefsupriem:BAABLgAECn8VAAIRAAkJ+RQjFgDUAQARAAkJ+RQjFgDUAQAAAA==.Bellatrïx:BAAALgAECgEJAgABLgAECgUJCAAKAAAAAA==.Belliaz:BAAALgAECgYJCQAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgAECgEJAQAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAFFAMJBgAGADkTAA==.',
Bl='Bloodlyfrost:BAABLgAECn8sAAISAAkJCAYBhwBmAQASAAkJCAYBhwBmAQAAAA==.Bloodmaji:BAAALgAECgUJBgAAAA==.Bloodwell:BAAALgAECgUJBQAAAA==.Bloodyguthix:BAAALgAECggJEgAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.Boyo:BAAALgADCgUJBQAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgYJDgABLgAFFAQJFwATAAYXAA==.Breaknasweat:BAAALgAECgIJAgAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bruzera:BAAALgAECgEJAQAAAA==.Bréwtality:BAAALgAECgEJAQABLgAFFAUJDgAPAOocAA==.',
['Bò']='Bòóberry:BAAALgAECgMJAwAAAA==.',
Ca='Calientay:BAAALgAECgYJBgABLgAFFAUJEgAMAGwbAA==.Candyquartz:BAAALgADCgcJFwAAAA==.Captaïn:BAAALgADCgUJBQAAAA==.Caylda:BAAALgAECgUJBQAAAA==.',
Ce='Celladorne:BAAALgAECgcJCwAAAA==.Centermass:BAAALgAECgMJAwAAAA==.',
Ch='Chibi:BAACLgAFFH8QAAIUAAQJ5gJKDgDXAAAUAAQJ5gJKDgDXAAAuAAQKfyoAAhQACQnVEskPALwBABQACQnVEskPALwBAAAA.Chronokite:BAABLgAECn8bAAMVAAgJ8gjOQgAbAQAVAAgJ8gjOQgAbAQAWAAcJAgetHgD+AAAAAA==.',
Co='Colair:BAAALgAECgQJBQAAAA==.Corpsegrin:BAAALgAECgIJAgAAAA==.',
Cp='Cpr:BAAALgAECgQJDgAAAA==.',
Cr='Crushed:BAABLgAECn8bAAMXAAgJqRlgEwCwAQAXAAgJqRlgEwCwAQABAAIJUw0b+gBtAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMJAAcJvBJkRgBoAQAJAAcJvBJkRgBoAQAOAAUJxwesZwCkAAABLgAECggJGwAVAPIIAA==.',
Da='Da:BAAALgADCgUJBQAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8/AAIGAAkJhhqwDwCcAgAGAAkJhhqwDwCcAgAAAA==.Darkfuse:BAAALgAECgMJBAAAAA==.Darkliter:BAAALgADCgcJBwAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgAECgYJBAABLgAFFAQJBQANAHsZAA==.Dayman:BAABLgAECn8YAAIHAAYJKRySbgCPAQAHAAYJKRySbgCPAQAAAA==.',
Db='Dbk:BAAALgAECgYJEgAAAA==.',
De='Deader:BAABLgAECn8aAAMYAAgJ5x2JDgB8AgAYAAgJ5x2JDgB8AgATAAIJsxF1aAB1AAAAAA==.Deadlyydot:BAABLgAECn8gAAITAAcJqQgMQgAFAQATAAcJqQgMQgAFAQAAAA==.Deadlyykiss:BAABLgAECn8pAAIZAAYJxQu4CQDvAAAZAAYJxQu4CQDvAAAAAA==.Deathhowl:BAAALgAECgkJEgAAAA==.Demonsaber:BAABLgAECn8kAAIDAAcJkAQuuQC0AAADAAcJkAQuuQC0AAAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAABLgAECn8iAAMRAAgJHg4XJABSAQARAAgJHg4XJABSAQADAAQJ2wTE3QB0AAAAAA==.Dengfeijien:BAAALgAECgUJBwABLgAECgkJCAAKAAAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.Desended:BAAALgAECgEJAQAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgYJDQAAAA==.Dirtydotz:BAAALgADCgUJBgAAAA==.Disengage:BAACLgAFFH8HAAIMAAMJhQU1awDBAAAMAAMJhQU1awDBAAAuAAQKfzMAAgwACAmCElxXAJkBAAwACAmCElxXAJkBAAAA.Displace:BAABLgAECn8bAAIPAAkJcQ++TgDUAQAPAAkJcQ++TgDUAQAAAA==.Divinewords:BAAALgAECggJCgABLgAECgkJFgAUAHcXAA==.Divish:BAABLgAECn8qAAMWAAkJMRzWBgCOAgAWAAkJMRzWBgCOAgAVAAEJAAAqpwAAAAAAAA==.',
Do='Dogan:BAAALgAECgQJBwAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgAECgEJAQAAAA==.Dotaldtrump:BAAALgAECgIJAgAAAA==.',
Dr='Dragkin:BAAALgADCgYJBgAAAA==.Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Dreyvia:BAAALgADCgUJBQAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgYJDQAAAA==.Dropdeath:BAAALgAECgUJBQAAAA==.Druecc:BAABLgAECn8rAAISAAkJPRe4NABDAgASAAkJPRe4NABDAgAAAA==.Druidlord:BAABLgAECn8vAAIaAAkJawNUOgC2AAAaAAkJawNUOgC2AAAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECggJCQAAAA==.Duckyfur:BAAALgAECgIJAwAAAA==.Dumplíng:BAAALgAECgQJBAABLgAECgkJKAAEANwaAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.',
Dz='Dzhunter:BAAALgAECgkJAgAAAA==.',
Ed='Edgerallen:BAACLgAFFH8FAAILAAMJPAnkOwCzAAALAAMJPAnkOwCzAAAuAAQKfx0AAwsACQn6D48iAJIBAAsACQn6D48iAJIBABsABgmuAv9hAIcAAAAA.',
Ei='Eitherwind:BAAALgAECgYJDAAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECggJGwAVAPIIAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECgkJEwAAAA==.Elianaa:BAAALgADCgMJBgAAAA==.Ellennia:BAAALgAECgUJEAAAAA==.',
Er='Era:BAABLgAECn8tAAIcAAgJAx2sFwAvAgAcAAgJAx2sFwAvAgAAAA==.',
Ex='Executions:BAAALgAECgUJEQAAAA==.',
Fa='Fanara:BAABLgAECn8dAAIEAAYJ0w5ZQwD7AAAEAAYJ0w5ZQwD7AAAAAA==.Fangtazia:BAAALgADCgQJBAAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAABLgAECn8aAAQJAAgJCB40GACEAgAJAAgJCB40GACEAgAOAAEJggoZsAAnAAAUAAEJHQA3SAAEAAAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgQJBgABLgAECgEJAQAKAAAAAA==.Felbládes:BAAALgAECgMJBQAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8kAAIbAAgJzRfzHADCAQAbAAgJzRfzHADCAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Finluzzertok:BAAALgADCgQJBAABLgAECgkJKAASAKgDAA==.Fitua:BAABLgAECn8gAAIPAAkJjwu3fgCGAQAPAAkJjwu3fgCGAQAAAA==.Fizzbann:BAAALgAECgcJEQABLgAECggJIAAIANAiAA==.',
Fk='Fkingbeast:BAAALgAFFAgJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAABLgAECn8dAAIQAAkJzArEIABJAQAQAAkJzArEIABJAQAAAA==.Fortytwö:BAAALgAECgMJAwAAAA==.Foutre:BAABLgAECn8qAAIEAAkJzw2CJgCWAQAEAAkJzw2CJgCWAQAAAA==.',
Fr='Froghugger:BAAALgAECgUJBQAAAA==.Fruntstabba:BAAALgAECgEJAQAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fuzzy:BAAALgAECgUJBAABLgAFFAQJDAAdALEgAA==.Fuzzytotems:BAAALgAECgYJDQAAAA==.',
['Få']='Fång:BAAALgAECggJEAAAAA==.',
Ga='Galadenn:BAAALgADCgEJAQAAAA==.Garo:BAABLgAECn88AAIUAAkJ8x90AwDMAgAUAAkJ8x90AwDMAgAAAA==.',
Ge='Getlnmyvan:BAACLgAFFH8IAAIHAAQJNhybKQBfAQAHAAQJNhybKQBfAQAuAAQKfyoAAgcACQm4ILoSANACAAcACQm4ILoSANACAAAA.',
Gh='Ghanima:BAAALgAECgEJAQABLgAECggJFwAOADMbAA==.Ghoulgranny:BAAALgADCgMJAwAAAA==.Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgAECgEJAQAAAA==.Gile:BAAALgAECgIJAgABLgAECgkJIAAPAI8LAA==.Gisul:BAAALgAECgMJAwAAAA==.',
Gl='Glert:BAABLgAECn8YAAISAAgJzA8cngCaAQASAAgJzA8cngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQTAAkJcAavOAAvAQATAAkJcAavOAAvAQAeAAYJAwS8NQD3AAAYAAYJUAIxVQDiAAAAAA==.Goinsolo:BAABLgAECn8fAAMMAAkJgRErPQDnAQAMAAkJgRErPQDnAQANAAYJ4wIkQgC5AAAAAA==.Goldentusk:BAAALgAECgYJEAAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMFAAgJzBnyHwBCAgAFAAgJzBnyHwBCAgAEAAUJeQ6eTQDzAAAAAA==.Gorecrush:BAAALgADCgEJAQABLgAFFAQJFwATAAYXAA==.Gorvax:BAABLgAECn81AAMQAAkJJhu1CwBQAgAQAAkJJhu1CwBQAgAPAAMJ4xAyJgF1AAAAAA==.',
Gr='Grimnyx:BAAALgADCgYJCwAAAA==.Grimstout:BAAALgAECgEJAQAAAA==.Gripe:BAAALgAECgQJBgAAAA==.Groguk:BAAALgAECgIJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgABLgAFFAUJHQAMAMMgAA==.',
Gw='Gwenledyr:BAABLgAECn9HAAQCAAkJux60BABJAgACAAgJmB20BABJAgABAAkJzxXrOwDqAQAXAAcJtRvCBwDRAQAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAECggJFwAOADMbAA==.Heimthrall:BAABLgAECn80AAIHAAkJpw3nawCUAQAHAAkJpw3nawCUAQAAAA==.Hekatee:BAABLgAECn8aAAIBAAcJaQn6lgAOAQABAAcJaQn6lgAOAQAAAA==.Hekkruk:BAAALgAECgMJAwABLgAFFAUJEgAfAJchAA==.Hekus:BAEALgAECgYJCAABLgAECgcJEQAKAAAAAA==.Hemesia:BAAALgAECgEJAgAAAA==.Henshin:BAABLgAECn81AAMFAAkJCyRcCwAGAwAFAAgJ7yNcCwAGAwAEAAgJ8BMSIQC8AQAAAA==.Herak:BAABLgAECn8hAAINAAcJxwskKwBJAQANAAcJxwskKwBJAQAAAA==.Hermiecrabbs:BAAALgAECgMJAwAAAA==.',
Hi='Highchairjr:BAABLgAECn8nAAMXAAgJZhp1EwASAQABAAUJfBkUiQAnAQAXAAcJABd1EwASAQAAAA==.Hildaelf:BAAALgAECgYJDwABLgAECggJIAAIANAiAA==.',
Ho='Hojdeeznuts:BAABLgAECn8vAAMGAAgJSx4jFQBiAgAGAAgJSx4jFQBiAgAHAAYJ6gYk6ADRAAAAAA==.Holyfudge:BAAALgAECgMJAwAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgAECgMJBgAAAA==.Horazi:BAAALgAECgEJAQABLgAFFAQJDAAGAAMiAA==.Horohöro:BAAALgAFFAQJBAABLgAFFAQJDgALAMsZAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ib='Ibuprofen:BAAALgAECgEJAgAAAA==.',
Ii='Iil:BAABLgAECn8tAAMSAAgJHxi4TgDsAQASAAgJHxi4TgDsAQAZAAEJFRSWGwA9AAAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECggJLQASAB8YAA==.',
Is='Istor:BAAALgAECgUJCwAAAA==.',
Ja='Jalir:BAAALgADCgEJAQAAAA==.Jaxxia:BAABLgAECn8rAAIGAAcJPBDUNAB7AQAGAAcJPBDUNAB7AQABLgAECgkJKwAHAHQLAA==.',
Jb='Jblaze:BAAALgAECgYJEAAAAA==.',
Je='Jellzilla:BAAALgAECgEJAQAAAA==.Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAABLgAECn8XAAIbAAgJDBVeIgCaAQAbAAgJDBVeIgCaAQAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgAECgIJAgAAAA==.',
Jo='Joesphkony:BAAALgAECgIJAwAAAA==.Jorick:BAABLgAECn8VAAIHAAYJPQfO7QDKAAAHAAYJPQfO7QDKAAAAAA==.',
Ju='Ju:BAABLgAECn8bAAIdAAYJbRoJLgC+AQAdAAYJbRoJLgC+AQAAAA==.Juzodots:BAAALgAECgEJAgAAAA==.Juzomido:BAACLgAFFH8bAAINAAYJOhq+BgCcAQANAAYJOhq+BgCcAQAuAAQKfygAAg0ACQmQHHkEANMCAA0ACQmQHHkEANMCAAAA.',
Ka='Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn88AAIbAAkJLRq/DgBaAgAbAAkJLRq/DgBaAgAAAA==.Kaline:BAACLgAFFH8FAAIaAAQJfxR5EwDhAAAaAAQJfxR5EwDhAAAuAAQKfxcAAhoACAnjGqgGAFsCABoACAnjGqgGAFsCAAAA.Karupted:BAABLgAECn8dAAIMAAcJvgozhQAvAQAMAAcJvgozhQAvAQAAAA==.Katianna:BAABLgAECn81AAIJAAkJvB0uDgDgAgAJAAkJvB0uDgDgAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAABLgAECn8jAAIHAAgJZhO3ZQCiAQAHAAgJZhO3ZQCiAQAAAA==.Keola:BAAALgAECgUJBQABLgAECgkJBgAKAAAAAA==.Kerra:BAAALgADCgMJAwAAAA==.',
Kh='Khalli:BAABLgAECn8zAAMYAAkJOxkGFQAqAgAYAAgJ5hgGFQAqAgATAAEJVwdUkAAoAAAAAA==.Khalwena:BAAALgAECgQJBQAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Killossus:BAAALgAECgQJBAAAAA==.Kinddurid:BAAALgADCgEJAQAAAA==.Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAABLgAECn8ZAAMHAAcJVRKqiwBXAQAHAAcJVRKqiwBXAQAIAAIJ0wDOVwAdAAAAAA==.Kissesnhugs:BAAALgAECgEJAQAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.Kiwirage:BAAALgAECgUJBgABLgAECgkJJwAOAOwbAA==.Kizent:BAAALgAECgYJDgAAAA==.Kizlock:BAAALgAECgEJAQAAAA==.',
Kl='Klaya:BAAALgAECgQJBAABLgAECgYJBgAKAAAAAA==.',
Ko='Koraena:BAABLgAECn8UAAIMAAYJJBFHgQA3AQAMAAYJJBFHgQA3AQAAAA==.Koronuss:BAABLgAFFH8GAAIPAAMJuw8HoADTAAAPAAMJuw8HoADTAAAAAA==.',
Kr='Krivgar:BAAALgAECgcJDwAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgQJBQAAAA==.',
Ku='Kulrig:BAACLgAFFH8XAAQTAAQJBhcLFQA2AQATAAQJBhcLFQA2AQAeAAMJawThOACYAAAYAAMJ/gUpJwCDAAAuAAQKf0cABBMACAl6HIsTADQCABMACAl6HIsTADQCABgABwlxF14fAOYBAB4AAQkNBiGEACQAAAAA.Kurri:BAAALgAECgUJBQAAAA==.Kurwa:BAAALgADCggJDQAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgAECgUJBQAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECgcJHwAMANQPAA==.Lanlong:BAAALgADCgcJCgABLgAECggJFwAOADMbAA==.Lastmark:BAAALgADCgcJDgAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFgAAAA==.Liliac:BAAALgADCgEJAQAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loryian:BAAALgADCgYJBgAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgAECgYJDgABLgAECggJIAAIANAiAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunalei:BAAALgAECgIJAgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAABLgAECn8cAAIgAAkJmB3IFwBKAgAgAAkJmB3IFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malganon:BAABLgAECn83AAIHAAkJnB1/GwCdAgAHAAkJnB1/GwCdAgAAAA==.Marcille:BAAALgAECgEJAQAAAA==.Margarrann:BAAALgAFFAIJAgABLgAFFAQJFwATAAYXAA==.Markymark:BAAALgADCgYJBgAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Marzanna:BAAALgAECgYJCgAAAA==.Mashpewtater:BAAALgAECgcJEgAAAA==.Mashpwntato:BAAALgAECgYJDQAAAA==.Mathelmana:BAABLgAECn82AAMCAAkJ/Ri8BABHAgACAAkJYhe8BABHAgABAAcJThExbwBbAQAAAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Me='Mellwin:BAAALgAECgQJBAAAAA==.Mezthyr:BAAALgADCggJCAAAAA==.',
Mi='Miliandra:BAAALgADCgkJEAAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Miniarrow:BAAALgADCggJCAAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8uAAITAAkJYRJIHQDaAQATAAkJYRJIHQDaAQAAAA==.Miseral:BAACLgAFFH8GAAIRAAMJOhn9FQDuAAARAAMJOhn9FQDuAAAuAAQKf0UAAhEACQn9IBsFAPACABEACQn9IBsFAPACAAAA.Missfrost:BAAALgAECgQJDQAAAA==.Mitzy:BAAALgAECgYJCQAAAA==.',
Mo='Moganchee:BAABLgAECn8dAAMSAAkJtgTDlgBIAQASAAkJtgTDlgBIAQAhAAcJCgJmCADiAAAAAA==.Mooeck:BAAALgAECgUJBwAAAA==.Moostafer:BAAALgAECgMJAwABLgAECgkJLAAPACYhAA==.Mordakka:BAAALgAFFAEJAQABLgAFFAQJFwATAAYXAA==.Morghella:BAABLgAECn9EAAIMAAkJWB8QEQDFAgAMAAkJWB8QEQDFAgAAAA==.Morney:BAAALgAECgMJAwAAAA==.Morticiaa:BAAALgAECgEJAQAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Mourningwood:BAAALgADCggJCAAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgAECgIJAgAAAA==.Mysticjaina:BAAALgAECgkJEAABLgAFFAMJBgAEAHMFAA==.Mythros:BAAALgAECgcJBwAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Na='Nasman:BAAALgADCggJCwAAAA==.',
Ne='Needswowaa:BAAALgAECgcJEgAAAA==.Nesmae:BAAALgAECggJEQABLgAFFAUJEgAMAGwbAA==.',
Ni='Nightwitch:BAABLgAECn8VAAINAAYJqgXGOQDtAAANAAYJqgXGOQDtAAAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAACLgAFFH8SAAIMAAUJbBvYKgBWAQAMAAUJbBvYKgBWAQAuAAQKfzAAAgwACQkcI3wMANwCAAwACQkcI3wMANwCAAAA.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Nosferatuu:BAAALgADCgYJBgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECgkJDwAAAA==.Nyxari:BAAALgADCgQJBAAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAECgYJCgAAAA==.',
Ol='Oleyinka:BAAALgAECgcJDgAAAA==.',
Om='Omnissiah:BAABLgAECn81AAMYAAkJ9hRMGAAHAgAYAAkJ9hRMGAAHAgAeAAIJHQYdbABPAAAAAA==.',
On='Once:BAABLgAECn8hAAMHAAcJUxupTADeAQAHAAcJUxupTADeAQAGAAUJEhHuXwD9AAAAAA==.Oneyedemon:BAAALgADCggJCQAAAA==.Oneyeshoter:BAAALgADCgEJAQABLgAECgcJHQAMAL4KAA==.',
Op='Opaths:BAABLgAECn8sAAMPAAgJJiE9IACGAgAPAAgJJiE9IACGAgAiAAIJzRB6KwByAAAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAABLgAECn81AAIIAAkJTSRPAQA+AwAIAAkJTSRPAQA+AwAAAA==.',
Pe='Peng:BAABLgAECn8VAAQjAAkJTw9dIQAhAQAjAAgJ3g9dIQAhAQAkAAEJYwvnewArAAAcAAEJhQIqtAAeAAAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAFFAMJBgAGADkTAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Preysight:BAAALgADCgYJBgABLgAECgkJFgAUAHcXAA==.Priedorei:BAAALgAECgUJBQAAAA==.Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgcJBwAAAA==.',
Ps='Psyberollin:BAAALgAECgcJBwABLgAECgkJBgAKAAAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Pv='Pvp:BAABLgAECn8iAAMGAAkJ9hN7HAAdAgAGAAkJ9hN7HAAdAgAHAAEJywx/kQEwAAAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJCQAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAABLgAECn8aAAMdAAgJoiNZBwAmAwAdAAgJoiNZBwAmAwAbAAIJ0wVzjgA/AAAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAABLgAECn8sAAIGAAkJPhkTGABFAgAGAAkJPhkTGABFAgAAAA==.Raydoink:BAAALgAECgYJBgAAAA==.',
Re='Reighan:BAAALgADCgUJBwAAAA==.Remiel:BAAALgAECgEJAQAAAA==.Renka:BAAALgAECgQJCAAAAA==.Revolting:BAABLgAFFH8YAAIDAAYJCRU3LQBoAQADAAYJCRU3LQBoAQAAAA==.Reze:BAAALgAECgIJAwABLgAFFAMJCQACAEUfAA==.Rezme:BAAALgADCgkJFAAAAA==.',
Rh='Rhaeny:BAAALgADCgEJAgAAAA==.',
Ri='Rianne:BAAALgAECgUJDwAAAA==.Rizeen:BAAALgAECgYJEwAAAA==.',
Ro='Rowanbow:BAAALgAECgQJDAAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn88AAMFAAkJ8RpaEgC4AgAFAAkJ8RpaEgC4AgAEAAUJsAcMZACGAAAAAA==.',
Sa='Saberhawk:BAABLgAECn8bAAIMAAcJtA8YcQBZAQAMAAcJtA8YcQBZAQAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sailarmoon:BAAALgAECgYJBgABLgAECgkJOAABANQXAA==.Sakee:BAAALgAECgEJAQABLgAECgYJDQAKAAAAAA==.Sakurazuka:BAABLgAECn84AAIBAAkJ1BcRIwBSAgABAAkJ1BcRIwBSAgAAAA==.Salaminizer:BAAALgAECgEJBAAAAA==.Samidudu:BAABLgAECn8YAAIaAAcJSRXEIABDAQAaAAcJSRXEIABDAQAAAA==.Sanath:BAABLgAECn8kAAIVAAkJwQ68KwCNAQAVAAkJwQ68KwCNAQAAAA==.Sanctusdeus:BAAALgAFFAEJAQAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECgkJOAANAO0YAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8dAAIEAAcJdiRQHwAFAgAEAAcJdiRQHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAABLgAECn8uAAIUAAkJAiOEAQAeAwAUAAkJAiOEAQAeAwAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAFFAQJFwATAAYXAA==.Sevotharte:BAAALgAECgYJBwAAAA==.',
Sg='Sgtmoose:BAAALgADCgcJDAAAAA==.',
Sh='Shadobread:BAAALgAECgcJEwAAAA==.Shadowglider:BAAALgAECgUJCAAAAA==.Shadowofhate:BAAALgAECgQJBAAAAA==.Shammhammer:BAAALgADCgEJAQAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8WAAIJAAQJOyNxHQB5AQAJAAQJOyNxHQB5AQAuAAQKfzEAAgkACQkGJvAAAM0DAAkACQkGJvAAAM0DAAAA.Shioban:BAAALgAECgIJAgAAAA==.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8eAAIfAAkJHRl9CQAmAgAfAAkJHRl9CQAmAgAAAA==.Shootermacge:BAAALgAECgEJAQABLgAECgcJGAAHAIYSAA==.',
Si='Sib:BAAALgAECgMJBAAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Sissyo:BAAALgADCgYJDQAAAA==.',
Sk='Skeets:BAAALgADCgcJDwAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sleasem:BAAALgADCgIJAgAAAA==.Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAABLgAECn8kAAIHAAgJ2RlqPQANAgAHAAgJ2RlqPQANAgAAAA==.Snke:BAAALgADCgcJBwABLgAECggJJAAHANkZAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8tAAIPAAkJvR+tHgDJAgAPAAkJvR+tHgDJAgAAAA==.Somah:BAAALgADCgEJAQAAAA==.Sonofgods:BAABLgAECn8bAAIMAAgJxBXzSADCAQAMAAgJxBXzSADCAQAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.Soulsnack:BAAALgAECgUJCQABLgAECggJKwADAOwRAA==.',
Sp='Spectrahl:BAABLgAECn8sAAIOAAgJQRLiMQByAQAOAAgJQRLiMQByAQABLgAFFAUJEgAMAGwbAA==.Spedspidspud:BAABLgAECn8cAAIDAAcJ0SBbKQAhAgADAAcJ0SBbKQAhAgAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECgkJLgATAJEQAA==.',
St='Stall:BAAALgAECgIJAQABLgAECgUJBQAKAAAAAA==.Starrbuck:BAABLgAECn81AAMFAAkJsgoOXgAZAQAFAAgJRggOXgAZAQAEAAEJrwJmpAAZAAAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8aAAINAAkJYRLlFQD0AQANAAkJYRLlFQD0AQAAAA==.Stryke:BAABLgAECn8oAAIYAAgJoxpuEgBIAgAYAAgJoxpuEgBIAgAAAA==.',
Su='Sunfury:BAAALgAECgQJBQAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgAECgMJBQAAAA==.Suterareta:BAABLgAECn8zAAMlAAkJdRQ5CgC9AQAlAAkJBxI5CgC9AQARAAYJbxWPPwD9AAAAAA==.',
Sy='Sylareith:BAABLgAECn8YAAQdAAYJVRfwNACaAQAdAAYJVRfwNACaAQAbAAUJMhSHSADbAAALAAQJkBImVwCpAAAAAA==.Syntara:BAABLgAECn81AAIUAAkJPCD9AwC3AgAUAAkJPCD9AwC3AgAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taggalongg:BAAALgADCgYJBgAAAA==.Taksun:BAABLgAECn9CAAIaAAkJpBqwCABeAgAaAAkJpBqwCABeAgAAAA==.Tandas:BAAALgAECgUJBQAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn84AAIQAAkJzg1/HwBWAQAQAAkJzg1/HwBWAQAAAA==.Tav:BAABLgAFFH8UAAMkAAUJOB3gDwBaAQAkAAUJOB3gDwBaAQAjAAIJnxpUIgB/AAAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAABLgAECn8gAAMIAAgJ0CLUBACmAgAIAAgJ0CLUBACmAgAHAAUJPBFl2gDiAAAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.Theoryhazit:BAAALgAECgEJAQAAAA==.Thewarwithin:BAAALgADCggJCAAAAA==.',
Ti='Tianara:BAACLgAFFH8GAAMGAAMJOROHLgC5AAAGAAMJOROHLgC5AAAHAAIJtRmWiQCVAAAuAAQKfxcAAwYACAmNIfIEAB0DAAYACAmNIfIEAB0DAAgABAk+FWwqALgAAAAA.Titania:BAAALgADCgQJBAAAAA==.',
Tj='Tjismyname:BAAALgAECgYJDwAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgQJBQAAAA==.Tokens:BAAALgAECgcJCgAAAA==.Tolerabull:BAABLgAECn8uAAQGAAkJ2x54DwCeAgAGAAgJHh54DwCeAgAIAAYJjwiaKADPAAAHAAEJexTiegE8AAAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trixxe:BAACLgAFFH8JAAIDAAQJ0RCQSQAHAQADAAQJ0RCQSQAHAQAuAAQKfzQAAgMACQlYGpgjAD4CAAMACQlYGpgjAD4CAAAA.Trojaan:BAABLgAECn8VAAIcAAkJMgVBXQDcAAAcAAkJMgVBXQDcAAAAAA==.Trostani:BAAALgAECgQJBAAAAA==.Trulisha:BAABLgAECn8XAAIOAAgJMxtwMACdAQAOAAgJMxtwMACdAQAAAA==.Trurala:BAAALgAECgMJBQABLgAECgYJBgAKAAAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgMJAwAAAA==.',
Ue='Uelfaen:BAAALgADCgYJBwAAAA==.',
Un='Undolf:BAAALgAECgYJDQAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8kAAIQAAkJkQahKgAAAQAQAAkJkQahKgAAAQAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAABLgAECn8hAAITAAcJtQcGRQD4AAATAAcJtQcGRQD4AAAAAA==.',
Va='Vacum:BAAALgAECgYJBwABLgAECgcJIQAHAFMbAA==.Vaderon:BAAALgAECgYJCwAAAA==.Vaelanar:BAAALgAECgYJCAAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vayine:BAACLgAFFH8QAAIIAAQJfwfxDACmAAAIAAQJfwfxDACmAAAuAAQKfysAAggACQkxFKIVAHYBAAgACQkxFKIVAHYBAAAA.Vaynitee:BAAALgADCgcJEQAAAA==.',
Ve='Venmo:BAAALgAECgYJCAABLgAECgkJNQAQACYbAA==.Veridesh:BAAALgAECgcJCwABLgAFFAQJFwATAAYXAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAAALgAECggJEwAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAECgYJBgABLgAFFAQJCQAJAEMkAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8iAAIQAAkJQhMBGACiAQAQAAkJQhMBGACiAQAAAA==.',
Vy='Vynlash:BAAALgADCgYJAQAAAA==.',
['Vì']='Vìcious:BAACLgAFFH8FAAMNAAIJnApTKgCHAAANAAIJnApTKgCHAAAMAAEJrwW5qAA9AAAuAAQKfzUAAwwACAn/FRNLALwBAAwACAk3FRNLALwBAA0ABwloFDsfAKIBAAAA.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgcJHAADANEgAA==.Warpaths:BAAALgAECgEJAQAAAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wicks:BAAALgAECgYJBgAAAA==.Wigglyears:BAABLgAECn8uAAMTAAkJkRBXIgCzAQATAAkJkRBXIgCzAQAeAAcJwQ8iKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgQJBwAAAA==.',
Ws='Wselfwulf:BAAALgAECgUJEQABLgAECggJIAAIANAiAA==.',
Xa='Xanadaria:BAAALgAECgYJCwABLgAECgkJCAAKAAAAAA==.Xanalluna:BAAALgAECgQJAwABLgAECgkJCAAKAAAAAA==.Xandrelyra:BAAALgADCgMJBQABLgAECgkJCAAKAAAAAA==.Xanvarani:BAAALgAECgkJCAAAAA==.',
Xe='Xenwilder:BAAALgADCgUJBQAAAA==.Xeriirado:BAAALgAECgcJBwAAAA==.Xeril:BAAALgAECgUJBgAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgAECgcJCQAAAA==.Yakushimaru:BAABLgAECn82AAIEAAkJFSF+BgDtAgAEAAkJFSF+BgDtAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgMJBQAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgIJAwAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAABLgAFFH8PAAIHAAQJKBgYQAAlAQAHAAQJKBgYQAAlAQAAAA==.Zeith:BAABLgAECn8mAAIjAAkJXRbJDwDnAQAjAAkJXRbJDwDnAQAAAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgYJBgAAAA==.',
Zi='Zildon:BAAALgAECgYJCwAAAA==.',
Zu='Zurik:BAACLgAFFH8SAAIfAAUJlyH7AwB7AQAfAAUJlyH7AwB7AQAuAAQKfy0AAh8ACQm6IJkCAPgCAB8ACQm6IJkCAPgCAAAA.',
Zy='Zyphoros:BAAALgADCgkJCwAAAA==.',
['Äz']='Äzúlà:BAAALgAECgcJEgAAAA==.',
['År']='Årrowz:BAAALgAECgIJAgAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAABLgAECn8UAAIHAAcJ9wfazQDzAAAHAAcJ9wfazQDzAAAAAA==.',
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
