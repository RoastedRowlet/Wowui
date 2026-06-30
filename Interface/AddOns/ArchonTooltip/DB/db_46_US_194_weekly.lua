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
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abelothh:BAABLgAECn8bAAMBAAkJOQxYYQB9AQABAAkJxwpYYQB9AQACAAQJOw34EwDwAAAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIDAAcJyBqmMgAvAgADAAcJyBqmMgAvAgAAAA==.Aelita:BAAALgAECgcJEwAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAABLgAECn8vAAMEAAkJ+BsoDgB4AgAEAAkJ+BsoDgB4AgAFAAUJxhOnaAD6AAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aidanpryde:BAAALgAECgQJCgAAAA==.Aimster:BAAALgAECgkJBwAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAACLgAFFH8MAAIGAAQJAyKfFACGAQAGAAQJAyKfFACGAQAuAAQKfx4AAwYACQnUHDAPAKQCAAYACQnUHDAPAKQCAAcABgl4DJPOAPUAAAAA.Akoni:BAAALgAECgYJDwABLgAECgkJJAAIAPEiAA==.',
Al='Allaris:BAABLgAECn8oAAIBAAkJUQh1dQBOAQABAAkJUQh1dQBOAQAAAA==.Allíesin:BAAALgAECgUJCAAAAA==.Altryn:BAAALgAECgMJBgAAAA==.Alundrablaze:BAACLgAFFH8KAAIJAAMJ5hxNDAD4AAAJAAMJ5hxNDAD4AAAuAAQKfysAAgkACQnmF10bAHACAAkACQnmF10bAHACAAAA.',
Am='Amarixa:BAAALgAECgMJAgABLgAECggJCwAKAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8OAAILAAQJyxmgIwAcAQALAAQJyxmgIwAcAQAuAAQKfzgAAgsACQlrITUHAMQCAAsACQlrITUHAMQCAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.Antsy:BAAALgAECgEJAgAAAA==.',
Ap='Apollis:BAAALgAECgMJBgAAAA==.',
Ar='Aram:BAAALgAECggJCgAAAA==.Aranthino:BAABLgAECn8XAAIMAAkJ7Q8pEACwAQAMAAkJ7Q8pEACwAQAAAA==.Arell:BAAALgAECgEJAQAAAA==.Armson:BAAALgAECgQJBAAAAA==.Aryabhatta:BAABLgAECn8tAAMNAAkJPx50GwCAAgANAAkJPx50GwCAAgAOAAYJ/BSNHwCgAQAAAA==.',
As='Ashrom:BAAALgAECgYJDAAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECggJCQAAAA==.',
At='Athellios:BAAALgAECgEJAwAAAA==.Athenarelia:BAABLgAECn8dAAIJAAgJjBB6RwCQAQAJAAgJjBB6RwCQAQAAAA==.',
Ba='Backbush:BAAALgAECgQJBwAAAA==.Baelskrim:BAABLgAECn8WAAIPAAcJUR0pJQC/AQAPAAcJUR0pJQC/AQAAAA==.Ballofsoy:BAAALgAECgEJAQAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAACLgAFFH8HAAIQAAQJ2weeGwD8AAAQAAQJ2weeGwD8AAAuAAQKf0gAAxAACQkCIe0eAI8CABAACQncH+0eAI8CABEAAwkBEPgGAGUAAAAA.Baoshengdadi:BAAALgAECggJCAABLgAFFAQJFgAJADsjAA==.Bashirr:BAAALgADCgIJAgAAAA==.',
Be='Beansfu:BAAALgAFFAIJAgABLgAFFAIJBwAJAKMgAA==.Beansination:BAACLgAFFH8HAAMJAAIJoyA2IABhAAAJAAIJoyA2IABhAAAPAAEJ5g7kVwA5AAAuAAQKfxYAAw8ACQmtF+shANUBAA8ACQmtF+shANUBAAkABQnIFPlRAD0BAAAA.Beefsupriem:BAABLgAECn8VAAISAAkJ+RSeFgDSAQASAAkJ+RSeFgDSAQAAAA==.Bellatrïx:BAAALgAECgEJAgABLgAECgUJCAAKAAAAAA==.Belliaz:BAAALgAECggJCwAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgAECgIJAgAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAFFAMJBgAGADkTAA==.',
Bl='Bloodlyfrost:BAABLgAECn8sAAITAAkJCAYGiQBlAQATAAkJCAYGiQBlAQAAAA==.Bloodmaji:BAAALgAECgUJBgAAAA==.Bloodwell:BAAALgAECgUJBQAAAA==.Bloodyguthix:BAAALgAECggJEgAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.Boyo:BAAALgADCgUJBQAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgYJEgABLgAFFAQJGQAUAAYXAA==.Breaknasweat:BAAALgAECgIJAgAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bruzera:BAAALgAECgEJAQAAAA==.Bréwtality:BAAALgAECgEJAQABLgAFFAUJDgAQAOocAA==.',
Bu='Burningtaint:BAAALgAECgEJAgAAAA==.',
['Bò']='Bòóberry:BAAALgAECgMJAwAAAA==.',
Ca='Calientay:BAAALgAECgYJBgABLgAFFAUJFgANAGwbAA==.Candyquartz:BAAALgADCgcJFwAAAA==.Captaïn:BAAALgAECgIJAgAAAA==.Cathorn:BAAALgAECgEJAQAAAA==.Caylda:BAAALgAECgUJBQAAAA==.',
Ce='Celladorne:BAAALgAECgcJCwAAAA==.Centermass:BAAALgAECgMJAwAAAA==.',
Cg='Cg:BAAALgAECgYJBwAAAA==.',
Ch='Chibi:BAACLgAFFH8QAAIMAAQJ5gLiDgDSAAAMAAQJ5gLiDgDSAAAuAAQKfyoAAgwACQnVEi8YAEcBAAwACQnVEi8YAEcBAAAA.Chronokite:BAABLgAECn8bAAMVAAgJ8gikRAAXAQAVAAgJ8gikRAAXAQAWAAcJAgcWHwD+AAAAAA==.',
Co='Colair:BAAALgAECgQJBQAAAA==.Corpsegrin:BAAALgAECgIJAgAAAA==.',
Cp='Cpr:BAAALgAECgQJDgAAAA==.',
Cr='Crushed:BAABLgAECn8bAAMXAAgJqRlgEwCwAQAXAAgJqRlgEwCwAQABAAIJUw2h/wBpAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMJAAcJvBJkRgBoAQAJAAcJvBJkRgBoAQAPAAUJxwesZwCkAAABLgAECggJGwAVAPIIAA==.',
Da='Da:BAAALgAECgEJAQAAAA==.Daldenn:BAAALgADCgMJAwAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8/AAIGAAkJhhrsDwCbAgAGAAkJhhrsDwCbAgAAAA==.Darkfuse:BAAALgAECgMJBAAAAA==.Darkliter:BAAALgADCgcJBwAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgAECgYJBAABLgAFFAQJCQAOAHsZAA==.Dayman:BAABLgAECn8YAAIHAAYJKRwOcACOAQAHAAYJKRwOcACOAQAAAA==.',
Db='Dbk:BAAALgAECgYJEgAAAA==.',
De='Deader:BAABLgAECn8aAAMYAAgJ5x3ODgB7AgAYAAgJ5x3ODgB7AgAUAAIJsxGTagB0AAAAAA==.Deadlyydot:BAABLgAECn8nAAIUAAcJiglpBQDSAAAUAAcJiglpBQDSAAAAAA==.Deadlyykiss:BAABLgAECn8vAAIZAAYJLw7kAADrAAAZAAYJLw7kAADrAAAAAA==.Deanbaba:BAAALgADCgEJAQAAAA==.Deathhowl:BAAALgAECgkJEgAAAA==.Demonsaber:BAABLgAECn8nAAIDAAcJwgT3uwC0AAADAAcJwgT3uwC0AAAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAABLgAECn8lAAMSAAkJBw8mJQBPAQASAAkJBw8mJQBPAQADAAQJ2wRs4QB0AAAAAA==.Dengfeijien:BAAALgAECgUJBwABLgAECgkJCAAKAAAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.Desended:BAAALgAECgEJAQAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgYJDQAAAA==.Dirtydotz:BAAALgAECgEJAQAAAA==.Disengage:BAACLgAFFH8IAAINAAMJiAXEbwDBAAANAAMJiAXEbwDBAAAuAAQKfzMAAg0ACAmCEjlZAJkBAA0ACAmCEjlZAJkBAAAA.Displace:BAABLgAECn8bAAIQAAkJcQ+vUADRAQAQAAkJcQ+vUADRAQAAAA==.Divinewords:BAAALgAECgkJEAAAAA==.Divish:BAABLgAECn8qAAMWAAkJMRz2BgCPAgAWAAkJMRz2BgCPAgAVAAEJAABJqgAAAAAAAA==.',
Do='Dogan:BAAALgAECgQJBwAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgAECgEJAQAAAA==.Dotaldtrump:BAAALgAECgIJAgAAAA==.',
Dr='Dragkin:BAAALgADCgYJBgAAAA==.Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Dreyvia:BAAALgADCgUJBQAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgYJDQAAAA==.Dropdeath:BAAALgAECgUJBQAAAA==.Druecc:BAABLgAECn8sAAITAAkJPRdqNQBDAgATAAkJPRdqNQBDAgAAAA==.Druidlord:BAABLgAECn82AAIaAAkJ2QN4BgCRAAAaAAkJ2QN4BgCRAAAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECggJCQAAAA==.Duckyfur:BAAALgAECgIJAwAAAA==.Dumplíng:BAAALgAECgQJBAABLgAECgkJLwAEAPgbAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgYJDQAKAAAAAA==.',
Dz='Dzhunter:BAAALgAECgkJAgAAAA==.',
Ed='Edgerallen:BAACLgAFFH8GAAILAAMJ+w1KOQDBAAALAAMJ+w1KOQDBAAAuAAQKfx0AAwsACQn6D+4iAJIBAAsACQn6D+4iAJIBABsABgmuAv9hAIcAAAAA.',
Ei='Eitherwind:BAAALgAECgYJDAAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECggJGwAVAPIIAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECgkJEwAAAA==.Elianaa:BAAALgADCgMJBgAAAA==.Ellennia:BAAALgAECgUJEgAAAA==.',
Em='Emish:BAAALgADCgkJCQAAAA==.',
Er='Era:BAABLgAECn8wAAIcAAkJwhwPGAAuAgAcAAkJwhwPGAAuAgAAAA==.',
Ex='Executions:BAABLgAECn8WAAMdAAUJQRWlAwDoAAAeAAQJNhS/EQAJAQAdAAQJbRSlAwDoAAAAAA==.',
Fa='Fanara:BAABLgAECn8dAAIEAAYJ0w5BRAD7AAAEAAYJ0w5BRAD7AAAAAA==.Fangtazia:BAAALgAECgEJAQAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAABLgAECn8aAAQJAAgJCB7BGACEAgAJAAgJCB7BGACEAgAPAAEJggpRtQAmAAAMAAEJHQBvSgAEAAAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgQJBgABLgAECgEJAQAKAAAAAA==.Felbládes:BAAALgAECgMJBQAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8kAAIbAAgJzReBHQDBAQAbAAgJzReBHQDBAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Finluzzertok:BAAALgADCgQJBAABLgAECgkJKgATADcEAA==.Fitua:BAABLgAECn8gAAIQAAkJjwu3fgCGAQAQAAkJjwu3fgCGAQAAAA==.Fizzbann:BAAALgAECgcJEQABLgAECgkJJAAIAPEiAA==.',
Fk='Fkingbeast:BAAALgAFFAgJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAABLgAECn8dAAIRAAkJzApYIQBHAQARAAkJzApYIQBHAQAAAA==.Fortytwö:BAAALgAECgMJAwAAAA==.Foutre:BAABLgAECn8rAAIEAAkJ6w2oJwCSAQAEAAkJ6w2oJwCSAQAAAA==.',
Fr='Froghugger:BAAALgAECgUJBQAAAA==.Fruntstabba:BAAALgAECgEJAQAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fungus:BAACLgAFFH8LAAIEAAUJQh4AGQBSAQAEAAUJQh4AGQBSAQAuAAQKfyoAAxoACAmPJV0DAPICABoACAmPJV0DAPICAAQABglPIkchAPMBAAAA.Fuzzy:BAAALgAECgUJBAABLgAFFAQJDAAfALEgAA==.Fuzzytotems:BAAALgAECggJDwAAAA==.',
['Få']='Fång:BAAALgAECggJEAAAAA==.',
Ga='Galadenn:BAAALgADCgEJAQAAAA==.Galgar:BAAALgADCgkJCQAAAA==.Garo:BAABLgAECn88AAIMAAkJ8x+OAwDLAgAMAAkJ8x+OAwDLAgAAAA==.',
Ge='Getlnmyvan:BAACLgAFFH8IAAIHAAQJNhwkLABdAQAHAAQJNhwkLABdAQAuAAQKfyoAAgcACQm4IFMTAM4CAAcACQm4IFMTAM4CAAAA.',
Gh='Ghanima:BAAALgAECgEJAQABLgAFFAMJCQAPACQUAA==.Ghoulgranny:BAAALgADCgMJAwAAAA==.Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgAECgEJAQAAAA==.Gile:BAAALgAECgIJAwABLgAECgkJIAAQAI8LAA==.Gisul:BAAALgAECgMJAwAAAA==.',
Gl='Glert:BAABLgAECn8YAAITAAgJzA8cngCaAQATAAgJzA8cngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQUAAkJcAZ1OgApAQAUAAkJcAZ1OgApAQAgAAYJAwS8NQD3AAAYAAYJUAIxVQDiAAAAAA==.Goinsolo:BAABLgAECn8fAAMNAAkJgRF7PgDnAQANAAkJgRF7PgDnAQAOAAYJ4wL/QgC3AAAAAA==.Goldentusk:BAABLgAECn8XAAMEAAcJpgbfBQDBAAAEAAcJpgbfBQDBAAAFAAYJ3gM9kwCNAAAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMFAAgJzBnyHwBCAgAFAAgJzBnyHwBCAgAEAAUJeQ6eTQDzAAAAAA==.Gorecrush:BAAALgADCgEJAQABLgAFFAQJGQAUAAYXAA==.Gorvax:BAABLgAECn82AAMRAAkJJhv/CwBMAgARAAkJJhv/CwBMAgAQAAMJ4xDwKgF1AAAAAA==.',
Gr='Grimnyx:BAAALgADCgYJCwAAAA==.Grimstout:BAAALgAECgEJAQAAAA==.Gripe:BAAALgAECgQJBwAAAA==.Groguk:BAAALgAECgIJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgABLgAFFAUJHQANAMMgAA==.',
Gw='Gwenledyr:BAABLgAECn9HAAQCAAkJux7SBABIAgACAAgJmB3SBABIAgABAAkJzxV2PADpAQAXAAcJtRv9BwDPAQAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hayzell:BAAALgADCgEJAQAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAFFAMJCQAPACQUAA==.Heimthrall:BAABLgAECn80AAIHAAkJpw2TbgCRAQAHAAkJpw2TbgCRAQAAAA==.Hekatee:BAABLgAECn8gAAIBAAcJywmqCwCcAAABAAcJywmqCwCcAAAAAA==.Hekkruk:BAAALgAECgMJAwABLgAFFAUJEwAhAJchAA==.Hekus:BAEALgAECgYJCQABLgAECgcJEQAKAAAAAA==.Hemesia:BAAALgAECgEJAgAAAA==.Henshin:BAABLgAECn82AAMFAAkJaSSRCwAGAwAFAAgJWSSRCwAGAwAEAAgJ8BPwIQC5AQAAAA==.Herak:BAABLgAECn8hAAIOAAcJxwuzKwBFAQAOAAcJxwuzKwBFAQAAAA==.Hermiecrabbs:BAAALgAECgMJAwAAAA==.',
Hi='Highchairjr:BAABLgAECn8nAAMXAAgJZhreEwASAQABAAUJfBn8iQAmAQAXAAcJABfeEwASAQAAAA==.Hildaelf:BAAALgAECgYJDwABLgAECgkJJAAIAPEiAA==.',
Ho='Hojdeeznuts:BAABLgAECn8vAAMGAAgJSx64FQBfAgAGAAgJSx64FQBfAgAHAAYJ6gbF6gDRAAAAAA==.Holyfudge:BAAALgAECgMJAwAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgAECgMJBgAAAA==.Horazi:BAAALgAECgEJAQABLgAFFAQJDAAGAAMiAA==.Horohöro:BAAALgAFFAQJBAABLgAFFAQJDgALAMsZAA==.Hotlinebling:BAAALgAECgEJAQAAAA==.Hovp:BAAALgADCgUJBQAAAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hà']='Hàwk:BAAALgAECgEJAQAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ib='Ibuprofen:BAAALgAECgEJAwAAAA==.',
Ii='Iil:BAABLgAECn8xAAMTAAkJtBjgNQBBAgATAAkJtBjgNQBBAgAZAAEJFRSWGwA9AAAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECgkJMQATALQYAA==.',
Is='Istor:BAAALgAECgUJDQAAAA==.',
Ja='Jalir:BAAALgADCgEJAQAAAA==.Jaxxia:BAABLgAECn8tAAIGAAkJDw9sNQB7AQAGAAkJDw9sNQB7AQAAAA==.',
Jb='Jblaze:BAAALgAECgYJEAAAAA==.',
Je='Jellzilla:BAAALgAECgEJAQAAAA==.Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAABLgAECn8XAAIbAAgJDBXfIgCaAQAbAAgJDBXfIgCaAQAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgAECgIJAwAAAA==.',
Jo='Joesphkony:BAAALgAECgIJBAAAAA==.Jorick:BAABLgAECn8VAAIHAAYJPQfP8gDHAAAHAAYJPQfP8gDHAAAAAA==.',
Ju='Ju:BAABLgAECn8bAAIfAAYJbRoxLwC/AQAfAAYJbRoxLwC/AQAAAA==.Juzodots:BAAALgAECgEJAgAAAA==.Juzomido:BAACLgAFFH8bAAIOAAYJOhoQBwCcAQAOAAYJOhoQBwCcAQAuAAQKfygAAg4ACQmQHHkEANMCAA4ACQmQHHkEANMCAAAA.',
Ka='Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn88AAIbAAkJLRoEDwBZAgAbAAkJLRoEDwBZAgAAAA==.Kaline:BAACLgAFFH8FAAIaAAQJfxSwFADdAAAaAAQJfxSwFADdAAAuAAQKfxcAAhoACAnjGqgGAFsCABoACAnjGqgGAFsCAAAA.Karupmyazz:BAAALgADCgEJAQAAAA==.Karupted:BAABLgAECn8dAAINAAcJvgrLhwAvAQANAAcJvgrLhwAvAQAAAA==.Katianna:BAABLgAECn81AAIJAAkJvB2MDgDgAgAJAAkJvB2MDgDgAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAABLgAECn8jAAIHAAgJZhM6aACeAQAHAAgJZhM6aACeAQAAAA==.Keola:BAAALgAECgUJBQABLgAECgkJBgAKAAAAAA==.Kerra:BAAALgADCgMJAwAAAA==.',
Kh='Khalli:BAABLgAECn8zAAMYAAkJOxlbFQAqAgAYAAgJ5hhbFQAqAgAUAAEJVwcSkwAoAAAAAA==.Khalwena:BAAALgAECgQJBQAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Killossus:BAAALgAECgQJBAAAAA==.Kinddurid:BAAALgADCgEJAQAAAA==.Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAABLgAECn8ZAAMHAAcJVRL9jgBUAQAHAAcJVRL9jgBUAQAIAAIJ0wAsWQAdAAAAAA==.Kissesnhugs:BAAALgAECgEJAQAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.Kiwirage:BAAALgAECgcJDAABLgAECgkJKAAPAOwbAA==.Kizent:BAAALgAECgYJDgAAAA==.Kizlock:BAAALgAECgMJBAAAAA==.',
Kl='Klaya:BAAALgAECgQJBAABLgAFFAEJAQAKAAAAAA==.',
Ko='Koraena:BAABLgAECn8VAAINAAcJ/A/rgwA3AQANAAcJ/A/rgwA3AQAAAA==.Koronuss:BAABLgAFFH8GAAIQAAMJuw9QpQDPAAAQAAMJuw9QpQDPAAAAAA==.',
Kr='Krivgar:BAAALgAECgcJDwAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgQJBgAAAA==.',
Ku='Kulrig:BAACLgAFFH8ZAAQUAAQJBhftFQA1AQAUAAQJBhftFQA1AQAgAAMJawStOgCXAAAYAAMJ/gUjKACDAAAuAAQKf0cABBQACAl6HK0TADICABQACAl6HK0TADICABgABwlxF14fAOYBACAAAQkNBjiHACQAAAAA.Kurri:BAAALgAECgUJBQAAAA==.Kurwa:BAAALgADCggJDQAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgAECgUJBQAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECggJIAANAIMOAA==.Lanlong:BAAALgADCgcJCgABLgAFFAMJCQAPACQUAA==.Lastmark:BAAALgADCgcJDgAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFgAAAA==.Liliac:BAAALgADCgEJAQAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loryian:BAAALgADCgYJBgAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgAECgYJDgABLgAECgkJJAAIAPEiAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunalei:BAAALgAECgIJAgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAABLgAECn8cAAIdAAkJmB3IFwBKAgAdAAkJmB3IFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malcanious:BAAALgAECgQJBAAAAA==.Malganon:BAABLgAECn83AAIHAAkJnB0jHACcAgAHAAkJnB0jHACcAgAAAA==.Marcille:BAAALgAECgEJAQAAAA==.Marfeil:BAAALgAECgIJAgAAAA==.Margarrann:BAAALgAFFAIJAgABLgAFFAQJGQAUAAYXAA==.Markymark:BAAALgADCgYJBgAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Marzanna:BAAALgAECgYJCgAAAA==.Mashpewtater:BAAALgAECgcJEgAAAA==.Mashpwntato:BAAALgAECgYJDQAAAA==.Mathelmana:BAABLgAECn83AAMCAAkJ/RjgBABGAgACAAkJYhfgBABGAgABAAcJThFecQBXAQABLgAFFAMJCgAJAOYcAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Me='Melissandre:BAAALgAECggJDQAAAA==.Mellwin:BAAALgAECgQJBAAAAA==.Mezthyr:BAAALgADCggJCAAAAA==.',
Mi='Miliandra:BAAALgADCgkJEAAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Miniarrow:BAAALgADCggJCAAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8uAAIUAAkJYRLtHQDWAQAUAAkJYRLtHQDWAQAAAA==.Miseral:BAACLgAFFH8JAAISAAMJHR6CEgAPAQASAAMJHR6CEgAPAQAuAAQKf0UAAhIACQn9IEcFAO4CABIACQn9IEcFAO4CAAAA.Missfrost:BAAALgAFFAEJAQAAAA==.Mitzy:BAAALgAFFAEJAQAAAA==.Mizbeheaven:BAAALgADCgYJBgABLgAECggJCwAKAAAAAA==.',
Mo='Moganchee:BAABLgAECn8dAAMTAAkJtgTjmABHAQATAAkJtgTjmABHAQAiAAcJCgJmCADiAAAAAA==.Moobloom:BAAALgADCgEJAQABLgAECgkJLQAGAA8PAA==.Mooeck:BAAALgAECgUJCQAAAA==.Moostafer:BAAALgAECgMJAwABLgAECgkJLAAQACYhAA==.Mordakka:BAAALgAFFAEJAQABLgAFFAQJGQAUAAYXAA==.Morghella:BAABLgAECn9EAAINAAkJWB/BEQDDAgANAAkJWB/BEQDDAgAAAA==.Morney:BAAALgAECgUJBgAAAA==.Morticiaa:BAAALgAECgEJAQAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Mourningwood:BAAALgADCggJCAAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgAECgIJAwAAAA==.Mysticjaina:BAABLgAECn8dAAIPAAkJNxBkAgB2AQAPAAkJNxBkAgB2AQABLgAFFAMJBgAEAHMFAA==.Mythros:BAAALgAECgcJCQAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Na='Nasman:BAAALgADCggJCwAAAA==.',
Ne='Needswowaa:BAAALgAECgcJEgAAAA==.Nesmae:BAAALgAECggJEQABLgAFFAUJFgANAGwbAA==.',
Ni='Nightwitch:BAABLgAECn8nAAIOAAgJ3gY6AgAhAQAOAAgJ3gY6AgAhAQAAAA==.Nimuen:BAAALgADCgMJBgABLgAECgcJEAAKAAAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAACLgAFFH8WAAINAAUJbBtMDABAAQANAAUJbBtMDABAAQAuAAQKfzMAAg0ACQkrI3wMANwCAA0ACQkrI3wMANwCAAAA.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Nosferatuu:BAAALgADCgYJBgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECgkJDwAAAA==.Nyxari:BAAALgADCgQJBAAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAFFAIJAgAAAA==.',
Ol='Oleyinka:BAAALgAECgcJDgAAAA==.',
Om='Omnissiah:BAABLgAECn81AAMYAAkJ9hS3GAAGAgAYAAkJ9hS3GAAGAgAgAAIJHQYjcABJAAAAAA==.',
On='Once:BAABLgAECn8iAAMHAAcJUxv6TQDdAQAHAAcJUxv6TQDdAQAGAAUJdBLxBwBzAAAAAA==.Oneyedemon:BAAALgADCggJCQAAAA==.',
Op='Opaths:BAABLgAECn8sAAMQAAgJJiHMIACFAgAQAAgJJiHMIACFAgAjAAIJzRA3LQBuAAAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAABLgAECn81AAIIAAkJTSRiAQA9AwAIAAkJTSRiAQA9AwAAAA==.',
Pe='Peng:BAABLgAECn8VAAQkAAkJTw/qIQAgAQAkAAgJ3g/qIQAgAQAlAAEJYwuyfgArAAAcAAEJhQIltwAdAAAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAFFAMJBgAGADkTAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Preysight:BAAALgADCgYJBgABLgAECgkJEAAKAAAAAA==.Priedorei:BAAALgAECgUJBQAAAA==.Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgcJBwAAAA==.',
Ps='Psyberollin:BAAALgAECgcJBwABLgAECgkJBgAKAAAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Pv='Pvp:BAABLgAECn8iAAMGAAkJ9hPTHAAdAgAGAAkJ9hPTHAAdAgAHAAEJywykpAEsAAAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJCQAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAABLgAECn8hAAMfAAgJoiMIAQBdAgAfAAgJoiMIAQBdAgAbAAIJ0wUvkQA/AAAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAABLgAECn8sAAIGAAkJPhliGABEAgAGAAkJPhliGABEAgAAAA==.Raydoink:BAAALgAECgYJBgAAAA==.',
Re='Reighan:BAAALgADCgUJBwAAAA==.Renka:BAAALgAECgQJCAAAAA==.Revolting:BAABLgAFFH8YAAIDAAYJCRVfLwBoAQADAAYJCRVfLwBoAQAAAA==.Reze:BAAALgAECgIJAwABLgAFFAMJCQACAEUfAA==.Rezme:BAAALgADCgkJFAAAAA==.',
Rh='Rhaeny:BAAALgAECgEJAQAAAA==.Rhâine:BAAALgAECgEJAQAAAA==.',
Ri='Rianne:BAAALgAECgUJDwAAAA==.Rizeen:BAAALgAECgYJEwAAAA==.',
Ro='Rose:BAAALgAECgQJBAAAAA==.Rowanbow:BAAALgAECgQJEAAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn88AAMFAAkJ8RqYEgC4AgAFAAkJ8RqYEgC4AgAEAAUJsAeqZQCGAAAAAA==.',
Sa='Saberhawk:BAABLgAECn8gAAINAAcJ6hDAcQBdAQANAAcJ6hDAcQBdAQAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sailarmoon:BAAALgAECgYJBgABLgAECgkJOwABANQXAA==.Sakee:BAAALgAECgEJAQABLgAECgYJDQAKAAAAAA==.Sakurazuka:BAABLgAECn87AAIBAAkJ1BdiJABNAgABAAkJ1BdiJABNAgAAAA==.Salaminizer:BAAALgAECgEJBAAAAA==.Samidudu:BAABLgAECn8YAAIaAAcJSRV/IQBDAQAaAAcJSRV/IQBDAQAAAA==.Sanath:BAABLgAECn8kAAIVAAkJwQ7TLACJAQAVAAkJwQ7TLACJAQAAAA==.Sanctusdeus:BAAALgAFFAEJAQAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECgkJOAAOAO0YAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8dAAIEAAcJdiRQHwAFAgAEAAcJdiRQHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAABLgAECn8uAAIMAAkJAiORAQAdAwAMAAkJAiORAQAdAwAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAFFAQJGQAUAAYXAA==.Sevotharte:BAAALgAECgcJDQAAAA==.',
Sg='Sgtmoose:BAAALgADCgcJDAAAAA==.',
Sh='Shadobread:BAAALgAECgcJEwAAAA==.Shadowglider:BAAALgAECgUJCAAAAA==.Shadowofhate:BAABLgAECn8XAAIXAAcJrhqPAADYAQAXAAcJrhqPAADYAQABLgAECgkJJQAiAJEeAA==.Shammhammer:BAAALgADCgEJAQAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8WAAIJAAQJOyNMHwB4AQAJAAQJOyNMHwB4AQAuAAQKfzIAAgkACQkGJgMBAMwDAAkACQkGJgMBAMwDAAAA.Shioban:BAAALgAECgIJAgAAAA==.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8eAAIhAAkJHRmrCQAnAgAhAAkJHRmrCQAnAgAAAA==.Shootermacge:BAAALgAECgQJBgABLgAECggJGgAHAIUTAA==.',
Si='Sib:BAAALgAECgMJBAAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Silverlight:BAAALgAECgUJCQABLgAFFAQJGQAUAAYXAA==.Sissyo:BAAALgADCgYJDQAAAA==.',
Sk='Skeets:BAAALgADCgcJDwAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sleasem:BAAALgADCgIJAgAAAA==.Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAABLgAECn8kAAIHAAgJ2RlsPgAMAgAHAAgJ2RlsPgAMAgAAAA==.Snke:BAAALgADCgcJBwABLgAECggJJAAHANkZAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8tAAIQAAkJvR+tHgDJAgAQAAkJvR+tHgDJAgAAAA==.Somah:BAAALgADCgEJAQAAAA==.Sonofgods:BAABLgAECn8dAAINAAkJGBWmSgDBAQANAAkJGBWmSgDBAQAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.Soulsnack:BAAALgAECgcJEAAAAA==.',
Sp='Spectrahl:BAABLgAECn8sAAIPAAgJQRLGMgBxAQAPAAgJQRLGMgBxAQABLgAFFAUJFgANAGwbAA==.Spedspidspud:BAABLgAECn8cAAIDAAcJ0SAFKgAhAgADAAcJ0SAFKgAhAgAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECgkJLgAUAJEQAA==.',
St='Stall:BAAALgAECgIJAQABLgAECgYJBQAKAAAAAA==.Starrbuck:BAABLgAECn82AAMFAAkJ3gwCXwAZAQAFAAgJtwoCXwAZAQAEAAEJrwJlpwAZAAAAAA==.Steakumss:BAAALgADCgYJBgAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8bAAIOAAkJahJdFgDvAQAOAAkJahJdFgDvAQAAAA==.Stryke:BAABLgAECn8rAAIYAAkJjRq7EgBHAgAYAAkJjRq7EgBHAgAAAA==.',
Su='Sunfury:BAAALgAECgQJBgAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgAECgMJBQAAAA==.Suterareta:BAABLgAECn86AAMmAAkJdRQDAQBXAQAmAAkJZhMDAQBXAQASAAYJbxWPPwD9AAAAAA==.',
Sy='Sylareith:BAABLgAECn8fAAQfAAYJRRhdNgCbAQAfAAYJRRhdNgCbAQAbAAUJMhSuSQDaAAALAAUJSxMGWACpAAAAAA==.Synderella:BAAALgAFFAEJAQAAAA==.Syntara:BAABLgAECn81AAIMAAkJPCATBAC2AgAMAAkJPCATBAC2AgAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taggalongg:BAAALgADCgYJBgAAAA==.Tailung:BAAALgADCgMJAwAAAA==.Taksun:BAABLgAECn9CAAIaAAkJpBreCABeAgAaAAkJpBreCABeAgAAAA==.Tandas:BAAALgAFFAMJAwAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn84AAIRAAkJzg0OIABUAQARAAkJzg0OIABUAQAAAA==.Tav:BAABLgAFFH8XAAMlAAUJyh3yEABXAQAlAAUJyh3yEABXAQAkAAIJnxqHIwB+AAAAAA==.',
Te='Terrence:BAAALgADCgEJAQAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAABLgAECn8kAAMIAAkJ8SL5BACmAgAIAAkJ8SL5BACmAgAHAAUJUBbU3ADiAAAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.Theoryhazit:BAAALgAECgEJAQAAAA==.Thewarwithin:BAAALgADCggJCAAAAA==.',
Ti='Tialndreyvia:BAAALgAECgMJAwAAAA==.Tianara:BAACLgAFFH8GAAMGAAMJOROhLwC4AAAGAAMJOROhLwC4AAAHAAIJtRlzjgCVAAAuAAQKfxcAAwYACAmNIfIEAB0DAAYACAmNIfIEAB0DAAgABAk+FWwqALgAAAAA.Titania:BAAALgADCgQJBAAAAA==.',
Tj='Tjismyname:BAAALgAECgYJDwAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgQJBQAAAA==.Tokens:BAAALgAECgcJCgAAAA==.Tolerabull:BAABLgAECn8uAAQGAAkJ2x61DwCdAgAGAAgJHh61DwCdAgAIAAYJjwgoKQDPAAAHAAEJexSggQE8AAAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trebeck:BAAALgAECgEJAgABLgAECgkJJAAIAPEiAA==.Trixxe:BAACLgAFFH8MAAIDAAQJ0RDXSwAHAQADAAQJ0RDXSwAHAQAuAAQKfzQAAgMACQlYGgwkAD8CAAMACQlYGgwkAD8CAAAA.Trojaan:BAABLgAECn8VAAIcAAkJMgXWXgDZAAAcAAkJMgXWXgDZAAAAAA==.Trostani:BAAALgAECgQJBAAAAA==.Trulisha:BAACLgAFFH8JAAIPAAMJJBThDADGAAAPAAMJJBThDADGAAAuAAQKfxcAAg8ACAkzG3AwAJ0BAA8ACAkzG3AwAJ0BAAAA.Trurala:BAAALgAFFAEJAQAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgMJAwAAAA==.',
Ue='Uelfaen:BAAALgADCgYJBwAAAA==.',
Un='Undolf:BAABLgAECn8bAAINAAgJAx7pAQBeAgANAAgJAx7pAQBeAgAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8kAAIRAAkJkQbGKwD8AAARAAkJkQbGKwD8AAAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAABLgAECn8lAAIUAAcJHwiXRQD5AAAUAAcJHwiXRQD5AAAAAA==.',
Va='Vacum:BAAALgAECgYJDwABLgAECgcJIgAHAFMbAA==.Vaderon:BAAALgAECgcJDAAAAA==.Vaelanar:BAAALgAECgYJCAAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vanillacocoa:BAAALgADCgIJAgAAAA==.Vayine:BAACLgAFFH8QAAIIAAQJfwdbDQClAAAIAAQJfwdbDQClAAAuAAQKfysAAggACQkxFKIVAHYBAAgACQkxFKIVAHYBAAAA.Vaynitee:BAAALgADCgcJEQAAAA==.',
Ve='Venmo:BAAALgAECgYJCAABLgAECgkJNgARACYbAA==.Veridesh:BAAALgAECgcJCwABLgAFFAQJGQAUAAYXAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAABLgAECn8VAAMVAAkJHQsDTgD1AAAVAAcJzAkDTgD1AAAWAAYJug1YIwDUAAAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAECgYJBwABLgAFFAQJDAAJAEMkAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8kAAIRAAkJQhOcGACeAQARAAkJQhOcGACeAQAAAA==.',
Vy='Vynlash:BAAALgADCgYJAQAAAA==.',
['Vì']='Vìcious:BAACLgAFFH8GAAMOAAIJnApLKwCHAAAOAAIJnApLKwCHAAANAAEJrwU+rwA9AAAuAAQKfzUAAw0ACAn/FfFMALsBAA0ACAk3FfFMALsBAA4ABwloFOsfAJ0BAAAA.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgcJHAADANEgAA==.Warpaths:BAAALgAECgEJAQABLgAECgkJLAAQACYhAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wicks:BAAALgAECgYJBgABLgAFFAEJAQAKAAAAAA==.Wide:BAACLgAFFH8ZAAIHAAUJDCSqBwB4AQAHAAUJDCSqBwB4AQAuAAQKfyoAAwcACAl8JFYXAN0CAAcACAl8JFYXAN0CAAgAAwmaJbgBAE0BAAAA.Wigglyears:BAABLgAECn8uAAMUAAkJkRDiIwCqAQAUAAkJkRDiIwCqAQAgAAcJwQ8iKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgQJBwAAAA==.',
Ws='Wselfwulf:BAAALgAECgUJEgABLgAECgkJJAAIAPEiAA==.',
Xa='Xanadaria:BAAALgAECggJDQABLgAECgkJCAAKAAAAAA==.Xanalluna:BAAALgAECgQJAwABLgAECgkJCAAKAAAAAA==.Xandrelyra:BAAALgADCgMJBQABLgAECgkJCAAKAAAAAA==.Xanvarani:BAAALgAECgkJCAAAAA==.',
Xe='Xenwilder:BAAALgAECgEJAQAAAA==.Xeriirado:BAAALgAECgcJBwAAAA==.Xeril:BAAALgAECgUJBgAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgAECggJDwAAAA==.Yakushimaru:BAABLgAECn82AAIEAAkJFSGoBgDsAgAEAAkJFSGoBgDsAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgMJBQAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgIJAwAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAABLgAFFH8UAAIHAAQJgRoLPwAtAQAHAAQJgRoLPwAtAQAAAA==.Zeith:BAABLgAECn8mAAIkAAkJXRYTEADmAQAkAAkJXRYTEADmAQAAAA==.Zeta:BAAALgAECgQJBAABLgAFFAQJDgADANMcAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgYJBgAAAA==.',
Zi='Zildon:BAAALgAECgYJDQAAAA==.',
Zu='Zurik:BAACLgAFFH8TAAIhAAUJlyFQBAB5AQAhAAUJlyFQBAB5AQAuAAQKfy0AAiEACQm6IKoCAPgCACEACQm6IKoCAPgCAAAA.',
Zy='Zyphoros:BAAALgADCgkJCwAAAA==.',
['Äz']='Äzúlà:BAABLgAECn8YAAITAAcJHxJtDADpAAATAAcJHxJtDADpAAAAAA==.',
['År']='Årrowz:BAAALgAECgIJAgAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAABLgAECn8UAAIHAAcJ9wfC0QDwAAAHAAcJ9wfC0QDwAAAAAA==.',
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
