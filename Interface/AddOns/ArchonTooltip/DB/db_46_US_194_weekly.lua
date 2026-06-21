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

local lookup = {'Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Survival','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Havoc','Mage-Frost','Priest-Shadow','Evoker-Augmentation','Evoker-Preservation','Warlock-Destruction','Priest-Holy','Mage-Arcane','Druid-Guardian','Monk-Windwalker','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','Priest-Discipline','Druid-Feral','Mage-Fire','DeathKnight-Frost','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abelothh:BAABLgAECn8bAAMBAAkJOQxZYQB9AQABAAkJxwpZYQB9AQACAAQJOw34EwDwAAAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIDAAcJyBqmMgAvAgADAAcJyBqmMgAvAgAAAA==.Aelita:BAAALgAECgYJCwAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAABLgAECn8oAAMEAAkJ3BomDgB4AgAEAAkJ3BomDgB4AgAFAAUJ+RKpaAD6AAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aidanpryde:BAAALgAECgQJCgAAAA==.Aimster:BAAALgAECgkJBwAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAACLgAFFH8MAAIGAAQJAyKmFACGAQAGAAQJAyKmFACGAQAuAAQKfx4AAwYACQnUHDAPAKQCAAYACQnUHDAPAKQCAAcABgl4DJLOAPUAAAAA.Akoni:BAAALgAECgYJDwABLgAECgkJIgAIAPEiAA==.',
Al='Allaris:BAABLgAECn8oAAIBAAkJUQhzdQBOAQABAAkJUQhzdQBOAQAAAA==.Allíesin:BAAALgAECgUJCAAAAA==.Altryn:BAAALgAECgMJBgAAAA==.Alundrablaze:BAACLgAFFH8HAAIJAAMJFxgsQQDhAAAJAAMJFxgsQQDhAAAuAAQKfysAAgkACQnmF1sbAHACAAkACQnmF1sbAHACAAAA.',
Am='Amarixa:BAAALgAECgMJAgABLgAECggJCwAKAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8OAAILAAQJyxmoIwAcAQALAAQJyxmoIwAcAQAuAAQKfzgAAgsACQlrITUHAMQCAAsACQlrITUHAMQCAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.Antsy:BAAALgAECgEJAgAAAA==.',
Ap='Apollis:BAAALgAECgMJBgAAAA==.',
Ar='Aram:BAAALgAECggJCgAAAA==.Aranthino:BAABLgAECn8WAAIMAAkJiQ8qEACwAQAMAAkJiQ8qEACwAQAAAA==.Arell:BAAALgAECgEJAQAAAA==.Armson:BAAALgAECgQJBAAAAA==.Aryabhatta:BAABLgAECn8tAAMNAAkJPx51GwCAAgANAAkJPx51GwCAAgAOAAYJ/BSNHwCgAQAAAA==.',
As='Ashrom:BAAALgAECgYJDAAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECggJCQAAAA==.',
At='Athellios:BAAALgAECgEJAwAAAA==.Athenarelia:BAABLgAECn8dAAIJAAgJjBB2RwCQAQAJAAgJjBB2RwCQAQAAAA==.',
Ba='Backbush:BAAALgAECgQJBwAAAA==.Baelskrim:BAABLgAECn8WAAIPAAcJUR0qJQC/AQAPAAcJUR0qJQC/AQAAAA==.Ballofsoy:BAAALgAECgEJAQAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAACLgAFFH8HAAIQAAQJ2wd/BwACAQAQAAQJ2wd/BwACAQAuAAQKf0cAAxAACQl9IO0eAI8CABAACQncH+0eAI8CABEAAwmeDhFNAFwAAAAA.Baoshengdadi:BAAALgAECggJCAAAAA==.',
Be='Beansfu:BAAALgAFFAIJAgABLgAFFAIJBwAJAKMgAA==.Beansination:BAACLgAFFH8HAAMJAAIJoyC5CQBmAAAJAAIJoyC5CQBmAAAPAAEJ5g7mVwA5AAAuAAQKfxYAAw8ACQmtF+0hANUBAA8ACQmtF+0hANUBAAkABQnIFPlRAD0BAAAA.Beefsupriem:BAABLgAECn8VAAISAAkJ+RSfFgDSAQASAAkJ+RSfFgDSAQAAAA==.Bellatrïx:BAAALgAECgEJAgABLgAECgUJCAAKAAAAAA==.Belliaz:BAAALgAECggJCwAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgAECgEJAQAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAFFAMJBgAGADkTAA==.',
Bl='Bloodlyfrost:BAABLgAECn8sAAITAAkJCAYEiQBlAQATAAkJCAYEiQBlAQAAAA==.Bloodmaji:BAAALgAECgUJBgAAAA==.Bloodwell:BAAALgAECgUJBQAAAA==.Bloodyguthix:BAAALgAECggJEgAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.Boyo:BAAALgADCgUJBQAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgYJDgABLgAFFAQJFwAUAAYXAA==.Breaknasweat:BAAALgAECgIJAgAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bruzera:BAAALgAECgEJAQAAAA==.Bréwtality:BAAALgAECgEJAQABLgAFFAUJDgAQAOocAA==.',
Bu='Burningtaint:BAAALgAECgEJAQAAAA==.',
['Bò']='Bòóberry:BAAALgAECgMJAwAAAA==.',
Ca='Calientay:BAAALgAECgYJBgABLgAFFAUJEwANAGwbAA==.Candyquartz:BAAALgADCgcJFwAAAA==.Captaïn:BAAALgAECgIJAgAAAA==.Caylda:BAAALgAECgUJBQAAAA==.',
Ce='Celladorne:BAAALgAECgcJCwAAAA==.Centermass:BAAALgAECgMJAwAAAA==.',
Ch='Chibi:BAACLgAFFH8QAAIMAAQJ5gLkDgDSAAAMAAQJ5gLkDgDSAAAuAAQKfyoAAgwACQnVEi8YAEcBAAwACQnVEi8YAEcBAAAA.Chronokite:BAABLgAECn8bAAMVAAgJ8gijRAAXAQAVAAgJ8gijRAAXAQAWAAcJAgcVHwD+AAAAAA==.',
Co='Colair:BAAALgAECgQJBQAAAA==.Corpsegrin:BAAALgAECgIJAgAAAA==.',
Cp='Cpr:BAAALgAECgQJDgAAAA==.',
Cr='Crushed:BAABLgAECn8bAAMXAAgJqRlgEwCwAQAXAAgJqRlgEwCwAQABAAIJUw2h/wBpAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMJAAcJvBJkRgBoAQAJAAcJvBJkRgBoAQAPAAUJxwesZwCkAAABLgAECggJGwAVAPIIAA==.',
Da='Da:BAAALgADCgUJBQAAAA==.Daldenn:BAAALgADCgMJAwAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8/AAIGAAkJhhrtDwCbAgAGAAkJhhrtDwCbAgAAAA==.Darkfuse:BAAALgAECgMJBAAAAA==.Darkliter:BAAALgADCgcJBwAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgAECgYJBAAAAA==.Dayman:BAABLgAECn8YAAIHAAYJKRwTcACOAQAHAAYJKRwTcACOAQAAAA==.',
Db='Dbk:BAAALgAECgYJEgAAAA==.',
De='Deader:BAABLgAECn8aAAMYAAgJ5x3ODgB7AgAYAAgJ5x3ODgB7AgAUAAIJsxGGagB0AAAAAA==.Deadlyydot:BAABLgAECn8gAAIUAAcJqQhCQwACAQAUAAcJqQhCQwACAQAAAA==.Deadlyykiss:BAABLgAECn8pAAIZAAYJxQvzCQDvAAAZAAYJxQvzCQDvAAAAAA==.Deathhowl:BAAALgAECgkJEgAAAA==.Demonsaber:BAABLgAECn8kAAIDAAcJkAT5uwC0AAADAAcJkAT5uwC0AAAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAABLgAECn8kAAMSAAkJBw8jJQBQAQASAAkJBw8jJQBQAQADAAQJ2wRr4QB0AAAAAA==.Dengfeijien:BAAALgAECgUJBwABLgAECgkJCAAKAAAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.Desended:BAAALgAECgEJAQAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgYJDQAAAA==.Dirtydotz:BAAALgAECgEJAQAAAA==.Disengage:BAACLgAFFH8HAAINAAMJhQXIbwDBAAANAAMJhQXIbwDBAAAuAAQKfzMAAg0ACAmCEjpZAJkBAA0ACAmCEjpZAJkBAAAA.Displace:BAABLgAECn8bAAIQAAkJcQ+sUADRAQAQAAkJcQ+sUADRAQAAAA==.Divinewords:BAAALgAECggJCgABLgAECgkJHwAMAIEbAA==.Divish:BAABLgAECn8qAAMWAAkJMRz3BgCPAgAWAAkJMRz3BgCPAgAVAAEJAABIqgAAAAAAAA==.',
Do='Dogan:BAAALgAECgQJBwAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgAECgEJAQAAAA==.Dotaldtrump:BAAALgAECgIJAgAAAA==.',
Dr='Dragkin:BAAALgADCgYJBgAAAA==.Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Dreyvia:BAAALgADCgUJBQAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgYJDQAAAA==.Dropdeath:BAAALgAECgUJBQAAAA==.Druecc:BAABLgAECn8sAAITAAkJPRdtNQBDAgATAAkJPRdtNQBDAgAAAA==.Druidlord:BAABLgAECn8vAAIaAAkJawPdOwC2AAAaAAkJawPdOwC2AAAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECggJCQAAAA==.Duckyfur:BAAALgAECgIJAwAAAA==.Dumplíng:BAAALgAECgQJBAABLgAECgkJKAAEANwaAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.',
Dz='Dzhunter:BAAALgAECgkJAgAAAA==.',
Ed='Edgerallen:BAACLgAFFH8GAAILAAMJ+w1UOQDBAAALAAMJ+w1UOQDBAAAuAAQKfx0AAwsACQn6D+wiAJIBAAsACQn6D+wiAJIBABsABgmuAv9hAIcAAAAA.',
Ei='Eitherwind:BAAALgAECgYJDAAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECggJGwAVAPIIAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECgkJEwAAAA==.Elianaa:BAAALgADCgMJBgAAAA==.Ellennia:BAAALgAECgUJEAAAAA==.',
Em='Emish:BAAALgADCgkJCQAAAA==.',
Er='Era:BAABLgAECn8vAAIcAAkJwhwRGAAuAgAcAAkJwhwRGAAuAgAAAA==.',
Ex='Executions:BAABLgAECn8VAAMdAAUJQRVhAQDpAAAeAAQJNhS+EQAJAQAdAAQJbRRhAQDpAAAAAA==.',
Fa='Fanara:BAABLgAECn8dAAIEAAYJ0w48RAD7AAAEAAYJ0w48RAD7AAAAAA==.Fangtazia:BAAALgAECgEJAQAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAABLgAECn8aAAQJAAgJCB7AGACEAgAJAAgJCB7AGACEAgAPAAEJggpNtQAmAAAMAAEJHQBtSgAEAAAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgQJBgABLgAECgEJAQAKAAAAAA==.Felbládes:BAAALgAECgMJBQAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8kAAIbAAgJzReBHQDBAQAbAAgJzReBHQDBAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Finluzzertok:BAAALgADCgQJBAABLgAECgkJKQATADcEAA==.Fitua:BAABLgAECn8gAAIQAAkJjwu3fgCGAQAQAAkJjwu3fgCGAQAAAA==.Fizzbann:BAAALgAECgcJEQABLgAECgkJIgAIAPEiAA==.',
Fk='Fkingbeast:BAAALgAFFAgJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAABLgAECn8dAAIRAAkJzApXIQBHAQARAAkJzApXIQBHAQAAAA==.Fortytwö:BAAALgAECgMJAwAAAA==.Foutre:BAABLgAECn8rAAIEAAkJ6w2lJwCSAQAEAAkJ6w2lJwCSAQAAAA==.',
Fr='Froghugger:BAAALgAECgUJBQAAAA==.Fruntstabba:BAAALgAECgEJAQAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fungus:BAACLgAFFH8LAAIEAAUJQh4KGQBSAQAEAAUJQh4KGQBSAQAuAAQKfyoAAxoACAmPJV0DAPICABoACAmPJV0DAPICAAQABglPIkchAPMBAAAA.Fuzzy:BAAALgAECgUJBAABLgAFFAQJDAAfALEgAA==.Fuzzytotems:BAAALgAECggJDwAAAA==.',
['Få']='Fång:BAAALgAECggJEAAAAA==.',
Ga='Galadenn:BAAALgADCgEJAQAAAA==.Garo:BAABLgAECn88AAIMAAkJ8x+PAwDLAgAMAAkJ8x+PAwDLAgAAAA==.',
Ge='Getlnmyvan:BAACLgAFFH8IAAIHAAQJNhw1LABdAQAHAAQJNhw1LABdAQAuAAQKfyoAAgcACQm4IFMTAM4CAAcACQm4IFMTAM4CAAAA.',
Gh='Ghanima:BAAALgAECgEJAQABLgAFFAMJBgAPAOASAA==.Ghoulgranny:BAAALgADCgMJAwAAAA==.Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgAECgEJAQAAAA==.Gile:BAAALgAECgIJAwABLgAECgkJIAAQAI8LAA==.Gisul:BAAALgAECgMJAwAAAA==.',
Gl='Glert:BAABLgAECn8YAAITAAgJzA8cngCaAQATAAgJzA8cngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQUAAkJcAZwOgApAQAUAAkJcAZwOgApAQAgAAYJAwS8NQD3AAAYAAYJUAIxVQDiAAAAAA==.Goinsolo:BAABLgAECn8fAAMNAAkJgRF+PgDnAQANAAkJgRF+PgDnAQAOAAYJ4wL+QgC3AAAAAA==.Goldentusk:BAAALgAECgYJEAAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMFAAgJzBnyHwBCAgAFAAgJzBnyHwBCAgAEAAUJeQ6eTQDzAAAAAA==.Gorecrush:BAAALgADCgEJAQABLgAFFAQJFwAUAAYXAA==.Gorvax:BAABLgAECn82AAMRAAkJJhsBDABMAgARAAkJJhsBDABMAgAQAAMJ4xDkKgF1AAAAAA==.',
Gr='Grimnyx:BAAALgADCgYJCwAAAA==.Grimstout:BAAALgAECgEJAQAAAA==.Gripe:BAAALgAECgQJBgAAAA==.Groguk:BAAALgAECgIJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgABLgAFFAUJHQANAMMgAA==.',
Gw='Gwenledyr:BAABLgAECn9HAAQCAAkJux7SBABIAgACAAgJmB3SBABIAgABAAkJzxV0PADpAQAXAAcJtRv9BwDPAQAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAFFAMJBgAPAOASAA==.Heimthrall:BAABLgAECn80AAIHAAkJpw2XbgCRAQAHAAkJpw2XbgCRAQAAAA==.Hekatee:BAABLgAECn8aAAIBAAcJaQkemQALAQABAAcJaQkemQALAQAAAA==.Hekkruk:BAAALgAECgMJAwABLgAFFAUJEwAhAJchAA==.Hekus:BAEALgAECgYJCAABLgAECgcJEQAKAAAAAA==.Hemesia:BAAALgAECgEJAgAAAA==.Henshin:BAABLgAECn82AAMFAAkJaSSSCwAGAwAFAAgJWSSSCwAGAwAEAAgJ8BPpIQC5AQAAAA==.Herak:BAABLgAECn8hAAIOAAcJxwuvKwBFAQAOAAcJxwuvKwBFAQAAAA==.Hermiecrabbs:BAAALgAECgMJAwAAAA==.',
Hi='Highchairjr:BAABLgAECn8nAAMXAAgJZhrfEwASAQABAAUJfBn4iQAmAQAXAAcJABffEwASAQAAAA==.Hildaelf:BAAALgAECgYJDwABLgAECgkJIgAIAPEiAA==.',
Ho='Hojdeeznuts:BAABLgAECn8vAAMGAAgJSx63FQBfAgAGAAgJSx63FQBfAgAHAAYJ6gbC6gDRAAAAAA==.Holyfudge:BAAALgAECgMJAwAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgAECgMJBgAAAA==.Horazi:BAAALgAECgEJAQABLgAFFAQJDAAGAAMiAA==.Horohöro:BAAALgAFFAQJBAABLgAFFAQJDgALAMsZAA==.Hotlinebling:BAAALgADCggJCAAAAA==.Hovp:BAAALgADCgUJBQAAAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ib='Ibuprofen:BAAALgAECgEJAwAAAA==.',
Ii='Iil:BAABLgAECn8wAAMTAAkJtBjjNQBBAgATAAkJtBjjNQBBAgAZAAEJFRSWGwA9AAAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECgkJMAATALQYAA==.',
Is='Istor:BAAALgAECgUJDAAAAA==.',
Ja='Jalir:BAAALgADCgEJAQAAAA==.Jaxxia:BAABLgAECn8tAAIGAAkJDw9rNQB7AQAGAAkJDw9rNQB7AQAAAA==.',
Jb='Jblaze:BAAALgAECgYJEAAAAA==.',
Je='Jellzilla:BAAALgAECgEJAQAAAA==.Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAABLgAECn8XAAIbAAgJDBXcIgCaAQAbAAgJDBXcIgCaAQAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgAECgIJAwAAAA==.',
Jo='Joesphkony:BAAALgAECgIJBAAAAA==.Jorick:BAABLgAECn8VAAIHAAYJPQfL8gDHAAAHAAYJPQfL8gDHAAAAAA==.',
Ju='Ju:BAABLgAECn8bAAIfAAYJbRouLwC/AQAfAAYJbRouLwC/AQAAAA==.Juzodots:BAAALgAECgEJAgAAAA==.Juzomido:BAACLgAFFH8bAAIOAAYJOhoPBwCcAQAOAAYJOhoPBwCcAQAuAAQKfygAAg4ACQmQHHkEANMCAA4ACQmQHHkEANMCAAAA.',
Ka='Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn88AAIbAAkJLRoEDwBZAgAbAAkJLRoEDwBZAgAAAA==.Kaline:BAACLgAFFH8FAAIaAAQJfxSvFADdAAAaAAQJfxSvFADdAAAuAAQKfxcAAhoACAnjGqgGAFsCABoACAnjGqgGAFsCAAAA.Karupted:BAABLgAECn8dAAINAAcJvgrNhwAvAQANAAcJvgrNhwAvAQAAAA==.Katianna:BAABLgAECn81AAIJAAkJvB2NDgDgAgAJAAkJvB2NDgDgAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAABLgAECn8jAAIHAAgJZhM7aACeAQAHAAgJZhM7aACeAQAAAA==.Keola:BAAALgAECgUJBQABLgAECgkJBgAKAAAAAA==.Kerra:BAAALgADCgMJAwAAAA==.',
Kh='Khalli:BAABLgAECn8zAAMYAAkJOxlbFQAqAgAYAAgJ5hhbFQAqAgAUAAEJVwcLkwAoAAAAAA==.Khalwena:BAAALgAECgQJBQAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Killossus:BAAALgAECgQJBAAAAA==.Kinddurid:BAAALgADCgEJAQAAAA==.Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAABLgAECn8ZAAMHAAcJVRIAjwBUAQAHAAcJVRIAjwBUAQAIAAIJ0wAsWQAdAAAAAA==.Kissesnhugs:BAAALgAECgEJAQAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.Kiwirage:BAAALgAECgcJDAABLgAECgkJJwAPAOwbAA==.Kizent:BAAALgAECgYJDgAAAA==.Kizlock:BAAALgAECgMJAwAAAA==.',
Kl='Klaya:BAAALgAECgQJBAABLgAFFAEJAQAKAAAAAA==.',
Ko='Koraena:BAABLgAECn8VAAINAAcJ/A/sgwA3AQANAAcJ/A/sgwA3AQAAAA==.Koronuss:BAABLgAFFH8GAAIQAAMJuw9UpQDPAAAQAAMJuw9UpQDPAAAAAA==.',
Kr='Krivgar:BAAALgAECgcJDwAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgQJBgAAAA==.',
Ku='Kulrig:BAACLgAFFH8XAAQUAAQJBhfuFQA1AQAUAAQJBhfuFQA1AQAgAAMJawSxOgCXAAAYAAMJ/gUgKACDAAAuAAQKf0cABBQACAl6HK4TADICABQACAl6HK4TADICABgABwlxF14fAOYBACAAAQkNBjiHACQAAAAA.Kurri:BAAALgAECgUJBQAAAA==.Kurwa:BAAALgADCggJDQAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgAECgUJBQAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECggJIAANAIMOAA==.Lanlong:BAAALgADCgcJCgABLgAFFAMJBgAPAOASAA==.Lastmark:BAAALgADCgcJDgAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFgAAAA==.Liliac:BAAALgADCgEJAQAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loryian:BAAALgADCgYJBgAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgAECgYJDgABLgAECgkJIgAIAPEiAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunalei:BAAALgAECgIJAgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAABLgAECn8cAAIdAAkJmB3IFwBKAgAdAAkJmB3IFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malcanious:BAAALgAECgQJBAAAAA==.Malganon:BAABLgAECn83AAIHAAkJnB0iHACcAgAHAAkJnB0iHACcAgAAAA==.Marcille:BAAALgAECgEJAQAAAA==.Margarrann:BAAALgAFFAIJAgABLgAFFAQJFwAUAAYXAA==.Markymark:BAAALgADCgYJBgAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Marzanna:BAAALgAECgYJCgAAAA==.Mashpewtater:BAAALgAECgcJEgAAAA==.Mashpwntato:BAAALgAECgYJDQAAAA==.Mathelmana:BAABLgAECn83AAMCAAkJ/RjgBABGAgACAAkJYhfgBABGAgABAAcJThFdcQBXAQABLgAFFAMJBwAJABcYAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Me='Mellwin:BAAALgAECgQJBAAAAA==.Mezthyr:BAAALgADCggJCAAAAA==.',
Mi='Miliandra:BAAALgADCgkJEAAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Miniarrow:BAAALgADCggJCAAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8uAAIUAAkJYRLtHQDWAQAUAAkJYRLtHQDWAQAAAA==.Miseral:BAACLgAFFH8JAAISAAMJHR6AEgAPAQASAAMJHR6AEgAPAQAuAAQKf0UAAhIACQn9IEcFAO4CABIACQn9IEcFAO4CAAAA.Missfrost:BAAALgAFFAEJAQAAAA==.Mitzy:BAAALgAECgYJCgAAAA==.Mizbeheaven:BAAALgADCgYJBgABLgAECggJCwAKAAAAAA==.',
Mo='Moganchee:BAABLgAECn8dAAMTAAkJtgTimABHAQATAAkJtgTimABHAQAiAAcJCgJmCADiAAAAAA==.Monkyourself:BAAALgAECgEJAQAAAA==.Mooeck:BAAALgAECgUJCAAAAA==.Moostafer:BAAALgAECgMJAwABLgAECgkJLAAQACYhAA==.Mordakka:BAAALgAFFAEJAQABLgAFFAQJFwAUAAYXAA==.Morghella:BAABLgAECn9EAAINAAkJWB/EEQDDAgANAAkJWB/EEQDDAgAAAA==.Morney:BAAALgAECgUJBgAAAA==.Morticiaa:BAAALgAECgEJAQAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Mourningwood:BAAALgADCggJCAAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgAECgIJAgAAAA==.Mysticjaina:BAABLgAECn8XAAIPAAkJzg0xAQA4AQAPAAkJzg0xAQA4AQABLgAFFAMJBgAEAHMFAA==.Mythros:BAAALgAECgcJCQAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Na='Nasman:BAAALgADCggJCwAAAA==.',
Ne='Needswowaa:BAAALgAECgcJEgAAAA==.Nesmae:BAAALgAECggJEQABLgAFFAUJEwANAGwbAA==.',
Ni='Nightwitch:BAABLgAECn8eAAIOAAcJNwaAAQC8AAAOAAcJNwaAAQC8AAAAAA==.Nimuen:BAAALgADCgMJAwAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAACLgAFFH8TAAINAAUJbBvGLQBVAQANAAUJbBvGLQBVAQAuAAQKfzAAAg0ACQkcI3wMANwCAA0ACQkcI3wMANwCAAAA.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Nosferatuu:BAAALgADCgYJBgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECgkJDwAAAA==.Nyxari:BAAALgADCgQJBAAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAFFAIJAgAAAA==.',
Ol='Oleyinka:BAAALgAECgcJDgAAAA==.',
Om='Omnissiah:BAABLgAECn81AAMYAAkJ9hS1GAAGAgAYAAkJ9hS1GAAGAgAgAAIJHQYhcABJAAAAAA==.',
On='Once:BAABLgAECn8hAAMHAAcJUxv9TQDdAQAHAAcJUxv9TQDdAQAGAAUJEhHuXwD9AAAAAA==.Oneyedemon:BAAALgADCggJCQAAAA==.Oneyeshoter:BAAALgADCgEJAQABLgAECgcJHQANAL4KAA==.',
Op='Opaths:BAABLgAECn8sAAMQAAgJJiHNIACFAgAQAAgJJiHNIACFAgAjAAIJzRA4LQBuAAAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAABLgAECn81AAIIAAkJTSRiAQA9AwAIAAkJTSRiAQA9AwAAAA==.',
Pe='Peng:BAABLgAECn8VAAQkAAkJTw/pIQAgAQAkAAgJ3g/pIQAgAQAlAAEJYwu1fgArAAAcAAEJhQIjtwAdAAAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAFFAMJBgAGADkTAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Preysight:BAAALgADCgYJBgABLgAECgkJHwAMAIEbAA==.Priedorei:BAAALgAECgUJBQAAAA==.Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgcJBwAAAA==.',
Ps='Psyberollin:BAAALgAECgcJBwABLgAECgkJBgAKAAAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Pv='Pvp:BAABLgAECn8iAAMGAAkJ9hPTHAAdAgAGAAkJ9hPTHAAdAgAHAAEJywyipAEsAAAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJCQAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAABLgAECn8aAAMfAAgJoiOKBwAmAwAfAAgJoiOKBwAmAwAbAAIJ0wUvkQA/AAAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAABLgAECn8sAAIGAAkJPhllGABEAgAGAAkJPhllGABEAgAAAA==.Raydoink:BAAALgAECgYJBgAAAA==.',
Re='Reighan:BAAALgADCgUJBwAAAA==.Remiel:BAAALgAECgEJAQAAAA==.Renka:BAAALgAECgQJCAAAAA==.Revolting:BAABLgAFFH8YAAIDAAYJCRVxLwBoAQADAAYJCRVxLwBoAQAAAA==.Reze:BAAALgAECgIJAwABLgAFFAMJBwAcAMwbAA==.Rezme:BAAALgADCgkJFAAAAA==.',
Rh='Rhaeny:BAAALgADCgEJAgAAAA==.',
Ri='Rianne:BAAALgAECgUJDwAAAA==.Rizeen:BAAALgAECgYJEwAAAA==.',
Ro='Rose:BAAALgAECgQJBAAAAA==.Rowanbow:BAAALgAECgQJEAAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn88AAMFAAkJ8RqYEgC4AgAFAAkJ8RqYEgC4AgAEAAUJsAenZQCGAAAAAA==.',
Sa='Saberhawk:BAABLgAECn8gAAINAAcJ6hDCcQBdAQANAAcJ6hDCcQBdAQAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sailarmoon:BAAALgAECgYJBgABLgAECgkJOAABANQXAA==.Sakee:BAAALgAECgEJAQABLgAECgYJDQAKAAAAAA==.Sakurazuka:BAABLgAECn84AAIBAAkJ1BdhJABNAgABAAkJ1BdhJABNAgAAAA==.Salaminizer:BAAALgAECgEJBAAAAA==.Samidudu:BAABLgAECn8YAAIaAAcJSRV/IQBDAQAaAAcJSRV/IQBDAQAAAA==.Sanath:BAABLgAECn8kAAIVAAkJwQ7SLACJAQAVAAkJwQ7SLACJAQAAAA==.Sanctusdeus:BAAALgAFFAEJAQAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECgkJOAAOAO0YAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8dAAIEAAcJdiRQHwAFAgAEAAcJdiRQHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAABLgAECn8uAAIMAAkJAiOSAQAdAwAMAAkJAiOSAQAdAwAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAFFAQJFwAUAAYXAA==.Sevotharte:BAAALgAECgcJDQAAAA==.',
Sg='Sgtmoose:BAAALgADCgcJDAAAAA==.',
Sh='Shadobread:BAAALgAECgcJEwAAAA==.Shadowglider:BAAALgAECgUJCAAAAA==.Shadowofhate:BAAALgAECgQJBAAAAA==.Shammhammer:BAAALgADCgEJAQAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8WAAIJAAQJOyNIHwB4AQAJAAQJOyNIHwB4AQAuAAQKfzIAAgkACQkGJgMBAMwDAAkACQkGJgMBAMwDAAAA.Shioban:BAAALgAECgIJAgAAAA==.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8eAAIhAAkJHRmqCQAnAgAhAAkJHRmqCQAnAgAAAA==.Shootermacge:BAAALgAECgQJBQABLgAECggJGgAHAIUTAA==.',
Si='Sib:BAAALgAECgMJBAAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Silverlight:BAAALgAECgQJCAABLgAFFAQJFwAUAAYXAA==.Sissyo:BAAALgADCgYJDQAAAA==.',
Sk='Skeets:BAAALgADCgcJDwAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sleasem:BAAALgADCgIJAgAAAA==.Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAABLgAECn8kAAIHAAgJ2RluPgAMAgAHAAgJ2RluPgAMAgAAAA==.Snke:BAAALgADCgcJBwABLgAECggJJAAHANkZAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8tAAIQAAkJvR+tHgDJAgAQAAkJvR+tHgDJAgAAAA==.Somah:BAAALgADCgEJAQAAAA==.Sonofgods:BAABLgAECn8cAAINAAgJxBWmSgDBAQANAAgJxBWmSgDBAQAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.Soulsnack:BAAALgAECgUJCwABLgAECgkJLAADACgRAA==.',
Sp='Spectrahl:BAABLgAECn8sAAIPAAgJQRLEMgBxAQAPAAgJQRLEMgBxAQABLgAFFAUJEwANAGwbAA==.Spedspidspud:BAABLgAECn8cAAIDAAcJ0SAJKgAhAgADAAcJ0SAJKgAhAgAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECgkJLgAUAJEQAA==.',
St='Stall:BAAALgAECgIJAQABLgAECgUJBQAKAAAAAA==.Starrbuck:BAABLgAECn82AAMFAAkJ3gwIXwAZAQAFAAgJtwoIXwAZAQAEAAEJrwJfpwAZAAAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8aAAIOAAkJYRJfFgDvAQAOAAkJYRJfFgDvAQAAAA==.Stryke:BAABLgAECn8qAAIYAAkJjRq7EgBHAgAYAAkJjRq7EgBHAgAAAA==.',
Su='Sunfury:BAAALgAECgQJBQAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgAECgMJBQAAAA==.Suterareta:BAABLgAECn8zAAMmAAkJdRRjCgC9AQAmAAkJBxJjCgC9AQASAAYJbxWPPwD9AAAAAA==.',
Sy='Sylareith:BAABLgAECn8fAAQfAAYJRRhbNgCbAQAfAAYJRRhbNgCbAQAbAAUJMhSqSQDbAAALAAUJSxMFWACpAAAAAA==.Synderella:BAAALgAECgMJBQAAAA==.Syntara:BAABLgAECn81AAIMAAkJPCAUBAC2AgAMAAkJPCAUBAC2AgAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taggalongg:BAAALgADCgYJBgAAAA==.Taksun:BAABLgAECn9CAAIaAAkJpBreCABeAgAaAAkJpBreCABeAgAAAA==.Tandas:BAAALgAECgcJCgAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn84AAIRAAkJzg0NIABUAQARAAkJzg0NIABUAQAAAA==.Tav:BAABLgAFFH8VAAMlAAUJOB3yEABXAQAlAAUJOB3yEABXAQAkAAIJnxqDIwB+AAAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAABLgAECn8iAAMIAAkJ8SL5BACmAgAIAAkJ8SL5BACmAgAHAAUJPBHR3ADiAAAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.Theoryhazit:BAAALgAECgEJAQAAAA==.Thewarwithin:BAAALgADCggJCAAAAA==.',
Ti='Tialndreyvia:BAAALgAECgMJAwAAAA==.Tianara:BAACLgAFFH8GAAMGAAMJOROgLwC4AAAGAAMJOROgLwC4AAAHAAIJtRl3jgCVAAAuAAQKfxcAAwYACAmNIfIEAB0DAAYACAmNIfIEAB0DAAgABAk+FWwqALgAAAAA.Titania:BAAALgADCgQJBAAAAA==.',
Tj='Tjismyname:BAAALgAECgYJDwAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgQJBQAAAA==.Tokens:BAAALgAECgcJCgAAAA==.Tolerabull:BAABLgAECn8uAAQGAAkJ2x62DwCdAgAGAAgJHh62DwCdAgAIAAYJjwgpKQDPAAAHAAEJexSegQE8AAAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trebeck:BAAALgAECgEJAQABLgAECgkJIgAIAPEiAA==.Trixxe:BAACLgAFFH8JAAIDAAQJ0RDlSwAHAQADAAQJ0RDlSwAHAQAuAAQKfzQAAgMACQlYGg0kAD8CAAMACQlYGg0kAD8CAAAA.Trojaan:BAABLgAECn8VAAIcAAkJMgXMXgDZAAAcAAkJMgXMXgDZAAAAAA==.Trostani:BAAALgAECgQJBAAAAA==.Trulisha:BAACLgAFFH8GAAIPAAMJ4BKzMwDAAAAPAAMJ4BKzMwDAAAAuAAQKfxcAAg8ACAkzG3AwAJ0BAA8ACAkzG3AwAJ0BAAAA.Trurala:BAAALgAFFAEJAQAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgMJAwAAAA==.',
Ue='Uelfaen:BAAALgADCgYJBwAAAA==.',
Un='Undolf:BAAALgAECgYJEwAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8kAAIRAAkJkQbCKwD8AAARAAkJkQbCKwD8AAAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAABLgAECn8hAAIUAAcJtgeQRQD5AAAUAAcJtgeQRQD5AAAAAA==.',
Va='Vacum:BAAALgAECgYJDQABLgAECgcJIQAHAFMbAA==.Vaderon:BAAALgAECgYJCwAAAA==.Vaelanar:BAAALgAECgYJCAAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vanillacocoa:BAAALgADCgIJAgAAAA==.Vayine:BAACLgAFFH8QAAIIAAQJfwdbDQClAAAIAAQJfwdbDQClAAAuAAQKfysAAggACQkxFKIVAHYBAAgACQkxFKIVAHYBAAAA.Vaynitee:BAAALgADCgcJEQAAAA==.',
Ve='Venmo:BAAALgAECgYJCAABLgAECgkJNgARACYbAA==.Veridesh:BAAALgAECgcJCwABLgAFFAQJFwAUAAYXAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAABLgAECn8VAAMVAAkJHQsCTgD1AAAVAAcJzAkCTgD1AAAWAAYJug1XIwDUAAAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAECgYJBwABLgAFFAQJCQAJAEMkAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8kAAIRAAkJQhObGACeAQARAAkJQhObGACeAQAAAA==.',
Vy='Vynlash:BAAALgADCgYJAQAAAA==.',
['Vì']='Vìcious:BAACLgAFFH8FAAMOAAIJnApJKwCHAAAOAAIJnApJKwCHAAANAAEJrwU9rwA9AAAuAAQKfzUAAw0ACAn/FfBMALsBAA0ACAk3FfBMALsBAA4ABwloFOkfAJ0BAAAA.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgcJHAADANEgAA==.Warpaths:BAAALgAECgEJAQABLgAECgkJLAAQACYhAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wicks:BAAALgAECgYJBgABLgAFFAEJAQAKAAAAAA==.Wide:BAACLgAFFH8WAAIHAAUJ7SOqBwB4AQAHAAUJ7SOqBwB4AQAuAAQKfyQAAwcACAl6JFYXAN0CAAcACAl6JFYXAN0CAAgAAQlyJp06AHIAAAAA.Wigglyears:BAABLgAECn8uAAMUAAkJkRDgIwCqAQAUAAkJkRDgIwCqAQAgAAcJwQ8iKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgQJBwAAAA==.',
Ws='Wselfwulf:BAAALgAECgUJEQABLgAECgkJIgAIAPEiAA==.',
Xa='Xanadaria:BAAALgAECggJDQABLgAECgkJCAAKAAAAAA==.Xanalluna:BAAALgAECgQJAwABLgAECgkJCAAKAAAAAA==.Xandrelyra:BAAALgADCgMJBQABLgAECgkJCAAKAAAAAA==.Xanvarani:BAAALgAECgkJCAAAAA==.',
Xe='Xenwilder:BAAALgAECgEJAQAAAA==.Xeriirado:BAAALgAECgcJBwAAAA==.Xeril:BAAALgAECgUJBgAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgAECggJDwAAAA==.Yakushimaru:BAABLgAECn82AAIEAAkJFSGoBgDsAgAEAAkJFSGoBgDsAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgMJBQAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgIJAwAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAABLgAFFH8TAAIHAAQJKBgXPwAtAQAHAAQJKBgXPwAtAQAAAA==.Zeith:BAABLgAECn8mAAIkAAkJXRYTEADmAQAkAAkJXRYTEADmAQAAAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgYJBgAAAA==.',
Zi='Zildon:BAAALgAECgYJDQAAAA==.',
Zu='Zurik:BAACLgAFFH8TAAIhAAUJlyFOBAB5AQAhAAUJlyFOBAB5AQAuAAQKfy0AAiEACQm6IKkCAPgCACEACQm6IKkCAPgCAAAA.',
Zy='Zyphoros:BAAALgADCgkJCwAAAA==.',
['Äz']='Äzúlà:BAABLgAECn8UAAITAAcJFRDSiwBgAQATAAcJFRDSiwBgAQAAAA==.',
['År']='Årrowz:BAAALgAECgIJAgAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAABLgAECn8UAAIHAAcJ9wfB0QDwAAAHAAcJ9wfB0QDwAAAAAA==.',
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
