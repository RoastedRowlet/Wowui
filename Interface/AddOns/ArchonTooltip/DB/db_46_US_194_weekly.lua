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

local lookup = {'Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Priest-Holy','Shaman-Enhancement','Evoker-Augmentation','Evoker-Preservation','Warlock-Destruction','Mage-Arcane','DemonHunter-Havoc','Druid-Guardian','Monk-Windwalker','Warrior-Fury','Priest-Shadow','Priest-Discipline','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety','Mage-Fire','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abelothh:BAABLgAECn8YAAMBAAgJvwqUYwA8AQABAAgJGQmUYwA8AQACAAQJOw34EwDwAAAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIDAAcJyBqmMgAvAgADAAcJyBqmMgAvAgAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAABLgAECn8VAAMEAAcJWxCtNQDoAAAEAAQJ3BOtNQDoAAAFAAUJKQ/fagCxAAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aimster:BAAALgAECgkJBwAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAABLgAECn8eAAMGAAkJ1By3CAC7AgAGAAkJ1By3CAC7AgAHAAYJeAwpjgAMAQAAAA==.Akoni:BAAALgAECgYJBgABLgAECgcJGgAIAKUjAA==.',
Al='Allaris:BAABLgAECn8YAAIBAAYJwQTToAC+AAABAAYJwQTToAC+AAAAAA==.Allíesin:BAAALgAECgQJBQAAAA==.Altryn:BAAALgAECgMJBQAAAA==.Alundrablaze:BAABLgAECn8aAAIJAAYJ/hRxPABdAQAJAAYJ/hRxPABdAQABLgAECggJIAABAIkPAA==.',
Am='Amarixa:BAAALgADCgcJCgABLgAECgUJBwAKAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8OAAILAAQJyxndEQBAAQALAAQJyxndEQBAAQAuAAQKfzgAAgsACQlmIRMEANcCAAsACQlmIRMEANcCAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.',
Ap='Apollis:BAAALgADCgcJBwAAAA==.',
Ar='Aranthino:BAAALgAECgYJCwAAAA==.Aryabhatta:BAABLgAECn8cAAMMAAgJKBu7JgD2AQAMAAcJRh67JgD2AQANAAMJIg7wNACrAAAAAA==.',
As='Ashrom:BAAALgADCgkJEwAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECgQJBAAAAA==.',
At='Athenarelia:BAAALgAFFAIJBAAAAA==.',
Ba='Backbush:BAAALgAECgQJBgAAAA==.Baelskrim:BAABLgAECn8UAAIOAAYJrR+kHgCZAQAOAAYJrR+kHgCZAQAAAA==.Ballofsoy:BAAALgAECgEJAQAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAABLgAECn8+AAMPAAkJdiCJFQCGAgAPAAkJuR+JFQCGAgAQAAMJig5XNQBlAAAAAA==.',
Be='Beansination:BAABLgAECn8WAAMOAAkJpxdCFgDjAQAOAAkJpxdCFgDjAQAJAAUJyBT5UQA9AQAAAA==.Beefsupriem:BAAALgAECgcJEgAAAA==.Bellatrïx:BAAALgAECgEJAQABLgAECgQJBQAKAAAAAA==.Belliaz:BAAALgAECgUJBwAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgADCgcJFAAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAECggJFwAGAI0hAA==.',
Bl='Bloodlyfrost:BAABLgAECn8qAAIRAAkJzAV/ZwBvAQARAAkJzAV/ZwBvAQAAAA==.Bloodwell:BAAALgAECgUJBQAAAA==.Bloodyguthix:BAAALgAECgQJBAAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgYJCQABLgAFFAMJDAASAP4FAA==.Breaknasweat:BAAALgAECgEJAQAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bruzera:BAAALgADCgYJBgAAAA==.Bréwtality:BAAALgAECgEJAQABLgAFFAQJCgAPAOocAA==.',
['Bò']='Bòóberry:BAAALgAECgMJAwAAAA==.',
Ca='Candyquartz:BAAALgADCgcJFwAAAA==.',
Ce='Celladorne:BAAALgAECgcJCgAAAA==.',
Ch='Chibi:BAACLgAFFH8MAAITAAQJKQKRBgDtAAATAAQJKQKRBgDtAAAuAAQKfycAAhMACQk7EskPALwBABMACQk7EskPALwBAAAA.Chronokite:BAABLgAECn8WAAMUAAcJcwlONgACAQAUAAcJcwlONgACAQAVAAYJ3AekGgDoAAAAAA==.',
Co='Colair:BAAALgAECgQJBQAAAA==.',
Cp='Cpr:BAAALgAECgQJDQAAAA==.',
Cr='Crushed:BAABLgAECn8UAAMWAAYJbRpgEwCwAQAWAAYJbRpgEwCwAQABAAIJQQuLyQBsAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMJAAcJvBLMRwAtAQAJAAcJvBLMRwAtAQAOAAUJxwesZwCkAAABLgAECggJFgAUAHMJAA==.',
Da='Da:BAAALgADCgUJBQAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8tAAIGAAkJ7BkdCgClAgAGAAkJ7BkdCgClAgAAAA==.Darkfuse:BAAALgAECgIJAgAAAA==.Darkliter:BAAALgADCgcJBwAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgADCgUJCAAAAA==.Dayman:BAAALgAECgYJEwAAAA==.',
Db='Dbk:BAAALgAECgYJDAAAAA==.',
De='Deader:BAAALgAECggJCgAAAA==.Deadlyydot:BAAALgAECgUJEAAAAA==.Deadlyykiss:BAABLgAECn8ZAAIXAAYJZQZSCADQAAAXAAYJZQZSCADQAAAAAA==.Deathhowl:BAAALgAECgIJAgAAAA==.Demonsaber:BAAALgAECgUJBwAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAABLgAECn8ZAAMYAAYJagrdJgDdAAAYAAYJagrdJgDdAAADAAQJ2wSsqgBzAAAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgIJBAAAAA==.Dirtydotz:BAAALgADCgUJBgAAAA==.Disengage:BAABLgAECn8kAAIMAAgJdQ40QQCJAQAMAAgJdQ40QQCJAQAAAA==.Displace:BAAALgAECgYJCgAAAA==.Divish:BAABLgAECn8qAAMVAAkJMRy7BACWAgAVAAkJMRy7BACWAgAUAAEJAADNfQAAAAAAAA==.',
Do='Dogan:BAAALgAECgMJAwAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgADCgQJBQAAAA==.Dotaldtrump:BAAALgAECgIJAgAAAA==.',
Dr='Dragkin:BAAALgADCgYJBgAAAA==.Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgYJCAAAAA==.Droggnoir:BAAALgADCgEJAQABLgAECggJEwAKAAAAAA==.Dropdeath:BAAALgAECgUJBQAAAA==.Druecc:BAABLgAECn8eAAIRAAgJZxA+WACUAQARAAgJZxA+WACUAQAAAA==.Druidlord:BAABLgAECn8WAAIZAAcJ3wK1LAB4AAAZAAcJ3wK1LAB4AAAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECggJCQAAAA==.Dumplíng:BAAALgAECgQJBAABLgAECgcJFQAEAFsQAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgIJBAAKAAAAAA==.',
Dz='Dzhunter:BAAALgAECgkJAQAAAA==.',
Ed='Edgerallen:BAABLgAECn8bAAMLAAgJExC2IQBeAQALAAgJExC2IQBeAQAaAAYJrgL/YQCHAAAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECggJFgAUAHMJAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECgcJCQAAAA==.Elianaa:BAAALgADCgMJBgAAAA==.',
Er='Era:BAABLgAECn8aAAIbAAcJZhiWIgCRAQAbAAcJZhiWIgCRAQAAAA==.',
Ex='Executions:BAAALgAECgEJAQAAAA==.',
Fa='Fanara:BAAALgAECgQJBAAAAA==.Fangtazia:BAAALgADCgQJBAAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAABLgAECn8VAAQJAAgJqByNFQBMAgAJAAgJqByNFQBMAgAOAAEJggp2ewAsAAATAAEJHQBwLAAEAAAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgQJBgAAAA==.Felbládes:BAAALgAECgMJBQAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenaly:BAAALgADCgUJBQAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8iAAIaAAgJzBfFEwDPAQAaAAgJzBfFEwDPAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Fitua:BAABLgAECn8fAAIPAAkJiQu3fgCGAQAPAAkJiQu3fgCGAQAAAA==.Fizzbann:BAAALgAECgYJBwABLgAECgcJGgAIAKUjAA==.',
Fk='Fkingbeast:BAAALgAFFAgJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAAALgAECggJDgAAAA==.Foutre:BAABLgAECn8YAAIEAAcJnwqqMQD9AAAEAAcJnwqqMQD9AAAAAA==.',
Fr='Fruntstabba:BAAALgADCgcJDQAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fuzzytotems:BAAALgAECgUJCAAAAA==.',
['Få']='Fång:BAAALgAECggJEAAAAA==.',
Ga='Galadenn:BAAALgADCgEJAQAAAA==.Garo:BAABLgAECn8zAAITAAkJrh/GAwB3AgATAAkJrh/GAwB3AgAAAA==.',
Ge='Getlnmyvan:BAABLgAECn8qAAIHAAkJuCB7CAD0AgAHAAkJuCB7CAD0AgAAAA==.',
Gh='Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgAECgEJAQAAAA==.',
Gl='Glert:BAABLgAECn8WAAIRAAcJSxAcngCaAQARAAcJSxAcngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQcAAkJcQYkKAA5AQAcAAkJcQYkKAA5AQAdAAYJAwS8NQD3AAASAAYJUAIxVQDiAAAAAA==.Goinsolo:BAABLgAECn8WAAMMAAkJLQ8ELQDZAQAMAAkJLQ8ELQDZAQANAAYJ4wKpMQDDAAAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMFAAgJzBnyHwBCAgAFAAgJzBnyHwBCAgAEAAUJeQ6eTQDzAAAAAA==.Gorvax:BAABLgAECn8ZAAIQAAcJPRV8GQAkAQAQAAcJPRV8GQAkAQAAAA==.',
Gr='Grimnyx:BAAALgADCgYJCwAAAA==.Grimstout:BAAALgADCgMJAwAAAA==.Gripe:BAAALgADCgcJDwAAAA==.Groguk:BAAALgAECgIJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgABLgAFFAUJGAAMAK4gAA==.',
Gw='Gwenledyr:BAABLgAECn81AAQBAAkJ8hmOKgDzAQABAAkJqxSOKgDzAQAWAAYJJxn9CwAyAQACAAUJBhVWDwD3AAAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAECgYJEAAKAAAAAA==.Heimthrall:BAABLgAECn8rAAIHAAkJswyfUwCHAQAHAAkJswyfUwCHAQAAAA==.Hekatee:BAAALgAECgQJBAAAAA==.Hekkruk:BAAALgADCgcJCQABLgAFFAMJBgAeALoTAA==.Hekus:BAAALgAECgMJAwABLgAECgcJDgAKAAAAAA==.Hemesia:BAAALgAECgEJAgAAAA==.Henshin:BAABLgAECn8cAAMFAAcJOiN0EwBsAgAFAAcJOiN0EwBsAgAEAAYJnhMeKwAiAQAAAA==.Herak:BAABLgAECn8hAAINAAcJxwu7HgBaAQANAAcJxwu7HgBaAQAAAA==.Hermiecrabbs:BAAALgAECgMJAwAAAA==.',
Hi='Highchairjr:BAABLgAECn8fAAMWAAYJSRsdGQCjAAABAAUJHRcdgAD+AAAWAAUJfxgdGQCjAAAAAA==.Hildaelf:BAAALgAECgIJBAABLgAECgcJGgAIAKUjAA==.',
Ho='Hojdeeznuts:BAABLgAECn8pAAMGAAgJSx4NDQB4AgAGAAgJSx4NDQB4AgAHAAEJDQPKUwEjAAAAAA==.Holyfudge:BAAALgAECgIJAgAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgAECgMJBQAAAA==.Horazi:BAAALgAECgEJAQABLgAECgkJHgAGANQcAA==.Horohöro:BAAALgAFFAQJBAABLgAFFAQJDgALAMsZAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ii='Iil:BAABLgAECn8eAAMRAAcJBhXfWwCLAQARAAcJBhXfWwCLAQAXAAEJFRSWGwA9AAAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECgcJHgARAAYVAA==.',
Is='Istor:BAAALgAECgUJCgAAAA==.',
Ja='Jaxxia:BAABLgAECn8eAAIGAAYJCQ4dNgAoAQAGAAYJCQ4dNgAoAQAAAA==.',
Jb='Jblaze:BAAALgAECgYJDQAAAA==.',
Je='Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAABLgAECn8XAAIaAAgJCxUTFwCsAQAaAAgJCxUTFwCsAQAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgAECgIJAgAAAA==.',
Jo='Joesphkony:BAAALgADCgUJBQAAAA==.Jorick:BAAALgAECgYJDwAAAA==.',
Ju='Ju:BAABLgAECn8VAAIfAAYJoBaCJgBrAQAfAAYJoBaCJgBrAQAAAA==.Juzodots:BAAALgAECgEJAQAAAA==.Juzomido:BAACLgAFFH8RAAINAAUJWhK1DQAzAQANAAUJWhK1DQAzAQAuAAQKfyQAAg0ACQlsHHkEANMCAA0ACQlsHHkEANMCAAAA.',
Ka='Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn8mAAIaAAgJSBc7FADKAQAaAAgJSBc7FADKAQAAAA==.Kaline:BAABLgAECn8XAAIZAAgJ4xqoBgBbAgAZAAgJ4xqoBgBbAgAAAA==.Karupted:BAAALgAECgYJEgAAAA==.Katianna:BAABLgAECn8jAAIJAAkJtxn/DwCBAgAJAAkJtxn/DwCBAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAABLgAECn8dAAIHAAcJCg8ecwA+AQAHAAcJCg8ecwA+AQAAAA==.Keola:BAAALgAECgUJBQABLgAECgkJBgAKAAAAAA==.Kerra:BAAALgADCgMJAwAAAA==.',
Kh='Khalli:BAABLgAECn8gAAMSAAgJ5xg1FADtAQASAAcJehg1FADtAQAcAAEJTQYPagApAAAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Kinddurid:BAAALgADCgEJAQAAAA==.Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAAALgAECgcJEgAAAA==.Kissesnhugs:BAAALgADCgUJBwAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.',
Ko='Koraena:BAAALgAECgUJCQAAAA==.Koronuss:BAAALgADCgEJAQAAAA==.',
Kr='Krivgar:BAAALgAECgcJDwAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgQJBQAAAA==.',
Ku='Kulrig:BAACLgAFFH8MAAQSAAMJ/gUrGACrAAASAAMJ/gUrGACrAAAcAAMJ0wqxEQCTAAAdAAIJ3QLrKwBfAAAuAAQKf0EABBwACAlrG5QOACECABwACAlrG5QOACECABIABwlxF14fAOYBAB0AAQkNBgxfACUAAAAA.Kurwa:BAAALgADCgYJBwAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgAECgUJBQAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECgYJEwAKAAAAAA==.Lanlong:BAAALgADCgcJCgABLgAECgYJEAAKAAAAAA==.Lastmark:BAAALgADCgcJDgAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFgAAAA==.Liliac:BAAALgADCgEJAQAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loryian:BAAALgADCgYJBgAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgAECgIJAwABLgAECgcJGgAIAKUjAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunalei:BAAALgAECgIJAgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAABLgAECn8cAAIgAAkJmB3IFwBKAgAgAAkJmB3IFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malganon:BAABLgAECn8mAAIHAAgJxRn5MwDrAQAHAAgJxRn5MwDrAQAAAA==.Marcille:BAAALgAECgEJAQAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Mashpewtater:BAAALgAECgcJEgAAAA==.Mathelmana:BAABLgAECn8gAAMBAAgJiQ8jYABDAQABAAcJGA8jYABDAQACAAUJOw4QFQDgAAAAAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Me='Mellwin:BAAALgADCgIJAgAAAA==.',
Mi='Miliandra:BAAALgADCgQJCQAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8eAAIcAAgJFgv4JQBHAQAcAAgJFgv4JQBHAQAAAA==.Miseral:BAABLgAECn8xAAIYAAkJBR5lBgCEAgAYAAkJBR5lBgCEAgAAAA==.Missfrost:BAAALgAECgIJBwAAAA==.Mitzy:BAAALgAECgUJCAAAAA==.',
Mo='Moganchee:BAABLgAECn8dAAMRAAkJtgS+cQBZAQARAAkJtgS+cQBZAQAhAAcJCgJmCADiAAAAAA==.Mordakka:BAAALgAFFAEJAQABLgAFFAMJDAASAP4FAA==.Morghella:BAABLgAECn8wAAIMAAkJsR36DwCKAgAMAAkJsR36DwCKAgAAAA==.Morticiaa:BAAALgADCgEJAwAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Mourningwood:BAAALgADCggJCAAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgADCgUJCgAAAA==.Mythros:BAAALgADCgMJBAAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Na='Nasman:BAAALgADCggJCwAAAA==.',
Ne='Needswowaa:BAAALgAECgcJCQAAAA==.Nesmae:BAAALgAECggJEAABLgAFFAMJCAAMAOkfAA==.',
Ni='Nightwitch:BAAALgAECgEJAQAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAACLgAFFH8IAAIMAAMJ6R8KKwARAQAMAAMJ6R8KKwARAQAuAAQKfzAAAgwACQkcI3wMANwCAAwACQkcI3wMANwCAAAA.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECggJDQAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAECgYJCgAAAA==.',
Ol='Oleyinka:BAAALgAECgUJCQAAAA==.',
Om='Omnissiah:BAABLgAECn8eAAISAAgJhRUAFADvAQASAAgJhRUAFADvAQAAAA==.',
On='Once:BAAALgAECgUJDAAAAA==.Oneyedemon:BAAALgADCggJCAAAAA==.Oneyeshoter:BAAALgADCgEJAQABLgAECgYJEgAKAAAAAA==.',
Op='Opaths:BAABLgAECn8eAAIPAAgJdB/hKgAPAgAPAAgJdB/hKgAPAgAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAABLgAECn8cAAIIAAgJJxzaBgAhAgAIAAgJJxzaBgAhAgAAAA==.',
Pe='Peng:BAABLgAECn8UAAQiAAgJhg6EHgDyAAAiAAcJDA+EHgDyAAAjAAEJYwu0TwAxAAAbAAEJhQIHhgAiAAAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAECggJFwAGAI0hAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Priedorei:BAAALgADCgIJAgAAAA==.Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgcJBwAAAA==.',
Ps='Psyberollin:BAAALgAECgYJBgABLgAECgkJBgAKAAAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Pv='Pvp:BAAALgAECggJEwAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJCQAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAABLgAECn8VAAMfAAcJ3iOCBwDMAgAfAAcJ3iOCBwDMAgAaAAIJ0wUpZQBEAAAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAABLgAECn8gAAIGAAkJPRmnDwBWAgAGAAkJPRmnDwBWAgAAAA==.Raydoink:BAAALgAECgIJAgAAAA==.',
Re='Reighan:BAAALgADCgUJBwAAAA==.Remiel:BAAALgAECgEJAQAAAA==.Renka:BAAALgAECgQJBgAAAA==.Revolting:BAABLgAFFH8RAAIDAAUJgQ6ZLQAeAQADAAUJgQ6ZLQAeAQAAAA==.Reze:BAAALgAECgEJAQABLgAFFAEJAQAKAAAAAA==.Rezme:BAAALgADCggJDAAAAA==.',
Ri='Rianne:BAAALgAECgQJBgAAAA==.Rizeen:BAAALgAECgYJDwAAAA==.',
Ro='Rowanbow:BAAALgAECgQJCAAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn8qAAMFAAgJYBxUEQCCAgAFAAgJYBxUEQCCAgAEAAUJsAfKSwCIAAAAAA==.',
Sa='Saberhawk:BAAALgAECgYJDQAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sakurazuka:BAABLgAECn8jAAIBAAcJ4hCjVwBZAQABAAcJ4hCjVwBZAQAAAA==.Salaminizer:BAAALgAECgEJBAAAAA==.Samidudu:BAABLgAECn8UAAIZAAcJWBOuFgAlAQAZAAcJWBOuFgAlAQAAAA==.Sanath:BAABLgAECn8kAAIUAAkJwA5THwCPAQAUAAkJwA5THwCPAQAAAA==.Sanctusdeus:BAAALgAFFAEJAQAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECgkJLwANAH4XAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8dAAIEAAcJdiRQHwAFAgAEAAcJdiRQHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAABLgAECn8gAAITAAgJih/KAwB2AgATAAgJih/KAwB2AgAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAFFAMJDAASAP4FAA==.Sevotharte:BAAALgAECgIJAgAAAA==.',
Sg='Sgtmoose:BAAALgADCgYJBgAAAA==.',
Sh='Shadobread:BAAALgAECgcJEwAAAA==.Shadowglider:BAAALgAECgMJBQAAAA==.Shammhammer:BAAALgADCgEJAQAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8OAAIJAAMJaySyGAA0AQAJAAMJaySyGAA0AQAuAAQKfyAAAgkACQkII88BAH0DAAkACQkII88BAH0DAAAA.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8eAAIeAAkJGhmlBQA7AgAeAAkJGhmlBQA7AgAAAA==.',
Si='Sib:BAAALgAECgEJAQAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Sissyo:BAAALgADCgYJDQAAAA==.',
Sk='Skeets:BAAALgADCgYJDgAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAABLgAECn8YAAIHAAgJOBbZPwDBAQAHAAgJOBbZPwDBAQAAAA==.Snke:BAAALgADCgcJBwABLgAECggJGAAHADgWAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8tAAIPAAkJvR+tHgDJAgAPAAkJvR+tHgDJAgAAAA==.Sonofgods:BAABLgAECn8YAAIMAAYJ5RE5ZAAiAQAMAAYJ5RE5ZAAiAQAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.Soulsnack:BAAALgAECgEJAgABLgAECgYJFQADABYOAA==.',
Sp='Spectrahl:BAABLgAECn8iAAIOAAgJMxJKIgB/AQAOAAgJMxJKIgB/AQABLgAFFAMJCAAMAOkfAA==.Spedspidspud:BAAALgAECgcJEwAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECgkJKwAcABQQAA==.',
St='Starrbuck:BAABLgAECn8fAAIFAAcJvAWEYADQAAAFAAcJvAWEYADQAAAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8YAAINAAgJfBLFFAC4AQANAAgJfBLFFAC4AQAAAA==.Stryke:BAABLgAECn8VAAISAAYJThrCGgCqAQASAAYJThrCGgCqAQAAAA==.',
Su='Sunfury:BAAALgAECgQJBQAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgAECgIJAgAAAA==.Suterareta:BAABLgAECn8aAAMkAAcJPRRCDwAHAQAkAAYJRxFCDwAHAQAYAAYJbxWPPwD9AAAAAA==.',
Sy='Sylareith:BAAALgAECgYJDgAAAA==.Syntara:BAABLgAECn8tAAITAAkJCh3QAgCgAgATAAkJCh3QAgCgAgAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taggalongg:BAAALgADCgYJBgAAAA==.Taksun:BAABLgAECn8rAAIZAAgJwRjPCgDSAQAZAAgJwRjPCgDSAQAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn8vAAIQAAkJdg0KGAAyAQAQAAkJdg0KGAAyAQAAAA==.Tav:BAAALgAFFAIJBAAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAABLgAECn8aAAMIAAcJpSOxBQBHAgAIAAcJpSOxBQBHAgAHAAUJug/SqADeAAAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.',
Ti='Tianara:BAABLgAECn8XAAMGAAgJjSHyBAAdAwAGAAgJjSHyBAAdAwAIAAQJPhVsKgC4AAAAAA==.Titania:BAAALgADCgQJBAAAAA==.',
Tj='Tjismyname:BAAALgAECgYJDwAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgMJBAAAAA==.Tolerabull:BAABLgAECn8iAAQGAAgJPRzcGwDaAQAGAAYJwxzcGwDaAQAIAAYJjwgzHgDNAAAHAAEJ1AhXQAEwAAAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trixxe:BAABLgAECn8qAAIDAAgJFRpmJgDtAQADAAgJFRpmJgDtAQAAAA==.Trojaan:BAABLgAECn8VAAIbAAkJMgVxRADhAAAbAAkJMgVxRADhAAAAAA==.Trulisha:BAAALgAECgYJEAAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgIJAgAAAA==.',
Ue='Uelfaen:BAAALgADCgYJBwAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8kAAIQAAkJjgYMHwD1AAAQAAkJjgYMHwD1AAAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAAALgAECgcJDwAAAA==.',
Va='Vaderon:BAAALgAECgUJCAAAAA==.Vaelanar:BAAALgADCgUJBQAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vayine:BAACLgAFFH8MAAIIAAQJwwZ1BwCzAAAIAAQJwwZ1BwCzAAAuAAQKfygAAggACQnVE6IVAHYBAAgACQnVE6IVAHYBAAAA.Vaynitee:BAAALgADCgcJBwAAAA==.',
Ve='Venmo:BAAALgAECgYJCAABLgAECgcJGQAQAD0VAA==.Veridesh:BAAALgAECgcJBwABLgAFFAMJDAASAP4FAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAAALgAECgYJBgAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAECgYJBgABLgAECggJJwAJAAAmAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8gAAIQAAkJQBMJDwCcAQAQAAkJQBMJDwCcAQAAAA==.',
['Vì']='Vìcious:BAABLgAECn8gAAIMAAgJLxNBPwCQAQAMAAgJLxNBPwCQAQAAAA==.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgcJEwAKAAAAAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wicks:BAAALgAECgYJBgAAAA==.Wigglyears:BAABLgAECn8rAAMcAAkJFBAGGAC2AQAcAAkJFBAGGAC2AQAdAAcJwQ8iKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgQJBwAAAA==.',
Ws='Wselfwulf:BAAALgAECgUJCQABLgAECgcJGgAIAKUjAA==.',
Xa='Xanadaria:BAAALgAECgUJCQAAAA==.Xanalluna:BAAALgADCgkJDAABLgAECgUJCQAKAAAAAA==.Xandrelyra:BAAALgADCgMJAwABLgAECgUJCQAKAAAAAA==.',
Xe='Xeriirado:BAAALgAECgcJBwAAAA==.Xeril:BAAALgADCgYJCgAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgADCgQJBAABLgAECgQJCAAKAAAAAA==.Yakushimaru:BAABLgAECn8tAAIEAAgJux/iCgBcAgAEAAgJux/iCgBcAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgMJBQAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgEJAQAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAABLgAFFH8FAAIHAAMJ6xGDPwDvAAAHAAMJ6xGDPwDvAAAAAA==.Zeith:BAABLgAECn8kAAIiAAkJRxUWDADeAQAiAAkJRxUWDADeAQAAAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgYJBgAAAA==.',
Zi='Zildon:BAAALgAECgYJCwAAAA==.',
Zu='Zurik:BAACLgAFFH8GAAIeAAMJuhOJBgAHAQAeAAMJuhOJBgAHAQAuAAQKfykAAh4ACQlBH8kBAOUCAB4ACQlBH8kBAOUCAAAA.',
Zy='Zyphoros:BAAALgADCgkJCgAAAA==.',
['Äz']='Äzúlà:BAAALgAECgMJAwAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAAALgAECgcJEwAAAA==.',
['Ìt']='Ìta:BAAALgAECgEJAQAAAA==.',
['Ðe']='Ðeadlymyth:BAAALgADCgEJAQAAAA==.',
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
