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

local lookup = {'Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Priest-Shadow','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Mage-Arcane','DemonHunter-Havoc','Druid-Guardian','Monk-Windwalker','Warrior-Fury','Priest-Discipline','Priest-Holy','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety','Mage-Fire','DeathKnight-Frost','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abelothh:BAABLgAECn8bAAMBAAkJOQwAVgCOAQABAAkJxwoAVgCOAQACAAQJOw34EwDwAAAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIDAAcJyBqmMgAvAgADAAcJyBqmMgAvAgAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAABLgAECn8fAAMEAAgJrRQRLwBJAQAEAAUJ3RYRLwBJAQAFAAUJ+RLYYQD+AAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aimster:BAAALgAECgkJBwAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAACLgAFFH8FAAIGAAIJvR02LQCuAAAGAAIJvR02LQCuAAAuAAQKfx4AAwYACQnUHCwNAKkCAAYACQnUHCwNAKkCAAcABgl4DIi8APAAAAAA.Akoni:BAAALgAECgYJDgABLgAECgcJGwAIAKUjAA==.',
Al='Allaris:BAABLgAECn8dAAIBAAgJjQRbnQD5AAABAAgJjQRbnQD5AAAAAA==.Allíesin:BAAALgAECgUJCAAAAA==.Altryn:BAAALgAECgMJBgAAAA==.Alundrablaze:BAABLgAECn8nAAIJAAgJ8hfEIAAxAgAJAAgJ8hfEIAAxAgABLgAECggJMAACAFgWAA==.',
Am='Amarixa:BAAALgADCgcJDwABLgAECgYJCAAKAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8OAAILAAQJyxlBHAAqAQALAAQJyxlBHAAqAQAuAAQKfzgAAgsACQlrITEGAMkCAAsACQlrITEGAMkCAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.Antsy:BAAALgAECgEJAgAAAA==.',
Ap='Apollis:BAAALgAECgMJBQAAAA==.',
Ar='Aram:BAAALgAECggJCgAAAA==.Aranthino:BAAALgAECggJDgAAAA==.Armson:BAAALgAECgQJBAAAAA==.Aryabhatta:BAABLgAECn8pAAMMAAgJJB4KJgAyAgAMAAgJJB4KJgAyAgANAAYJ7RLcHQCeAQAAAA==.',
As='Ashrom:BAAALgAECgEJAwAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECggJCQAAAA==.',
At='Athellios:BAAALgADCgcJBwAAAA==.Athenarelia:BAABLgAECn8dAAIJAAgJjBCYPwCSAQAJAAgJjBCYPwCSAQAAAA==.',
Ba='Backbush:BAAALgAECgQJBwAAAA==.Baelskrim:BAABLgAECn8WAAIOAAcJUR24IADFAQAOAAcJUR24IADFAQAAAA==.Ballofsoy:BAAALgAECgEJAQAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAABLgAECn9HAAMPAAkJfSBQGgCVAgAPAAkJ3B9QGgCVAgAQAAMJng7cRABgAAAAAA==.',
Be='Beansination:BAACLgAFFH8FAAIJAAIJrB2mSwClAAAJAAIJrB2mSwClAAAuAAQKfxYAAw4ACQmtFxkeANgBAA4ACQmtFxkeANgBAAkABQnIFPlRAD0BAAAA.Beefsupriem:BAAALgAECggJEwAAAA==.Bellatrïx:BAAALgAECgEJAgABLgAECgUJCAAKAAAAAA==.Belliaz:BAAALgAECgYJCAAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgAECgEJAQAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAFFAMJBgAGADkTAA==.',
Bl='Bloodlyfrost:BAABLgAECn8sAAIRAAkJCAZJggBYAQARAAkJCAZJggBYAQAAAA==.Bloodmaji:BAAALgAECgQJBAAAAA==.Bloodwell:BAAALgAECgUJBQAAAA==.Bloodyguthix:BAAALgAECggJEgAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgYJDgABLgAFFAMJDwASAOkRAA==.Breaknasweat:BAAALgAECgIJAgAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bruzera:BAAALgADCgYJDAAAAA==.Bréwtality:BAAALgAECgEJAQABLgAFFAQJDAAPAOocAA==.',
['Bò']='Bòóberry:BAAALgAECgMJAwAAAA==.',
Ca='Calientay:BAAALgAECgYJBgABLgAFFAQJDgAMAP4aAA==.Candyquartz:BAAALgADCgcJFwAAAA==.Caylda:BAAALgAECgUJBQAAAA==.',
Ce='Celladorne:BAAALgAECgcJCwAAAA==.',
Ch='Chibi:BAACLgAFFH8QAAITAAQJ5gKWCgDlAAATAAQJ5gKWCgDlAAAuAAQKfyoAAhMACQnVEskPALwBABMACQnVEskPALwBAAAA.Chronokite:BAABLgAECn8YAAMUAAgJtAmgHAAFAQAUAAcJAgegHAAFAQAVAAcJcwkRSgDfAAAAAA==.',
Co='Colair:BAAALgAECgQJBQAAAA==.Corpsegrin:BAAALgAECgIJAgAAAA==.',
Cp='Cpr:BAAALgAECgQJDgAAAA==.',
Cr='Crushed:BAABLgAECn8bAAMWAAgJqRlOCwBuAQAWAAgJqRlOCwBuAQABAAIJUw026wBwAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMJAAcJvBJkRgBoAQAJAAcJvBJkRgBoAQAOAAUJxwesZwCkAAABLgAECggJGAAUALQJAA==.',
Da='Da:BAAALgADCgUJBQAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn8/AAIGAAkJhhq0DQCiAgAGAAkJhhq0DQCiAgAAAA==.Darkfuse:BAAALgAECgMJBAAAAA==.Darkliter:BAAALgADCgcJBwAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.David:BAAALgAECgYJBAABLgAECgcJAQAKAAAAAA==.Dayman:BAABLgAECn8YAAIHAAYJKRw9YQCUAQAHAAYJKRw9YQCUAQAAAA==.',
Db='Dbk:BAAALgAECgYJEgAAAA==.',
De='Deader:BAAALgAECggJDwAAAA==.Deadlyydot:BAABLgAECn8cAAISAAcJ0Qa1QADoAAASAAcJ0Qa1QADoAAAAAA==.Deadlyykiss:BAABLgAECn8fAAIXAAYJZwhoCQDaAAAXAAYJZwhoCQDaAAAAAA==.Deathhowl:BAAALgAECgMJBAAAAA==.Demonsaber:BAABLgAECn8YAAIDAAcJ+APSugCRAAADAAcJ+APSugCRAAAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAABLgAECn8dAAMYAAgJHg1hIQBIAQAYAAgJHg1hIQBIAQADAAQJ2wQhzgBtAAAAAA==.Dengfeijien:BAAALgADCgUJCAABLgAECgkJCAAKAAAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgMJBgAAAA==.Dirtydotz:BAAALgADCgUJBgAAAA==.Disengage:BAABLgAECn8vAAIMAAgJhxHFUACXAQAMAAgJhxHFUACXAQAAAA==.Displace:BAAALgAECgcJEgAAAA==.Divinewords:BAAALgADCgEJAQAAAA==.Divish:BAABLgAECn8qAAMUAAkJMRxLBgCPAgAUAAkJMRxLBgCPAgAVAAEJAACUmAAAAAAAAA==.',
Do='Dogan:BAAALgAECgQJBAAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgAECgEJAQAAAA==.Dotaldtrump:BAAALgAECgIJAgAAAA==.',
Dr='Dragkin:BAAALgADCgYJBgAAAA==.Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Dreyvia:BAAALgADCgUJBQAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgYJDQAAAA==.Dropdeath:BAAALgAECgUJBQAAAA==.Druecc:BAABLgAECn8iAAIRAAgJOBR/YQCjAQARAAgJOBR/YQCjAQAAAA==.Druidlord:BAABLgAECn8gAAIZAAgJsQJePACLAAAZAAgJsQJePACLAAAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECggJCQAAAA==.Duckyfur:BAAALgAECgEJAQAAAA==.Dumplíng:BAAALgAECgQJBAABLgAECggJHwAEAK0UAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgMJBgAKAAAAAA==.',
Dz='Dzhunter:BAAALgAECgkJAQAAAA==.',
Ed='Edgerallen:BAABLgAECn8bAAMLAAgJFBCwKQBUAQALAAgJFBCwKQBUAQAaAAYJrgL/YQCHAAAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECggJGAAUALQJAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECggJEgAAAA==.Elianaa:BAAALgADCgMJBgAAAA==.Ellennia:BAAALgAECgUJCQAAAA==.',
Er='Era:BAABLgAECn8lAAIbAAgJnBzOFgAkAgAbAAgJnBzOFgAkAgAAAA==.',
Ex='Executions:BAAALgAECgUJCgAAAA==.',
Fa='Fanara:BAAALgAECgYJEgAAAA==.Fangtazia:BAAALgADCgQJBAAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAABLgAECn8aAAQJAAgJCB4FFQCJAgAJAAgJCB4FFQCJAgAOAAEJggrFnwAnAAATAAEJHQBSPQAEAAAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgQJBgABLgAECgEJAQAKAAAAAA==.Felbládes:BAAALgAECgMJBQAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenaly:BAAALgADCgUJBQAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8kAAIaAAgJzRc5GgDHAQAaAAgJzRc5GgDHAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Finluzzertok:BAAALgADCgQJBAABLgAECgkJKAARAKgDAA==.Fitua:BAABLgAECn8gAAIPAAkJjwu3fgCGAQAPAAkJjwu3fgCGAQAAAA==.Fizzbann:BAAALgAECgYJDgABLgAECgcJGwAIAKUjAA==.',
Fk='Fkingbeast:BAAALgAFFAgJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAAALgAECgkJEAAAAA==.Foutre:BAABLgAECn8kAAIEAAgJlAwvMABCAQAEAAgJlAwvMABCAQAAAA==.',
Fr='Froghugger:BAAALgAECgUJBQAAAA==.Fruntstabba:BAAALgAECgEJAQAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fuzzytotems:BAAALgAECgYJDQAAAA==.',
['Få']='Fång:BAAALgAECggJEAAAAA==.',
Ga='Galadenn:BAAALgADCgEJAQAAAA==.Garo:BAABLgAECn88AAITAAkJ8x++AgDXAgATAAkJ8x++AgDXAgAAAA==.',
Ge='Getlnmyvan:BAABLgAECn8qAAIHAAkJuCBGDwDWAgAHAAkJuCBGDwDWAgAAAA==.',
Gh='Ghanima:BAAALgAECgEJAQABLgAECgYJEQAKAAAAAA==.Ghoulgranny:BAAALgADCgMJAwAAAA==.Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgAECgEJAQAAAA==.Gile:BAAALgAECgIJAQABLgAECgkJIAAPAI8LAA==.',
Gl='Glert:BAABLgAECn8YAAIRAAgJzA8cngCaAQARAAgJzA8cngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQSAAkJcAZMNQAfAQASAAkJcAZMNQAfAQAcAAYJAwS8NQD3AAAdAAYJUAIxVQDiAAAAAA==.Goinsolo:BAABLgAECn8fAAMMAAkJgRH6NADyAQAMAAkJgRH6NADyAQANAAYJ4wKkPQC9AAAAAA==.Goldentusk:BAAALgAECgYJBgAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMFAAgJzBnyHwBCAgAFAAgJzBnyHwBCAgAEAAUJeQ6eTQDzAAAAAA==.Gorecrush:BAAALgADCgEJAQABLgAFFAMJDwASAOkRAA==.Gorvax:BAABLgAECn8sAAMQAAgJYRuWDgAFAgAQAAgJYRuWDgAFAgAPAAMJ4xC/DgF1AAAAAA==.',
Gr='Grimnyx:BAAALgADCgYJCwAAAA==.Grimstout:BAAALgAECgEJAQAAAA==.Gripe:BAAALgAECgEJAQAAAA==.Groguk:BAAALgAECgIJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgABLgAFFAUJHQAMAMMgAA==.',
Gw='Gwenledyr:BAABLgAECn9HAAQCAAkJux7GAwBRAgACAAgJmB3GAwBRAgABAAkJzxXQNQD1AQAWAAcJtRueBgDXAQAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAECgYJEQAKAAAAAA==.Heimthrall:BAABLgAECn80AAIHAAkJpw2JYwCPAQAHAAkJpw2JYwCPAQAAAA==.Hekatee:BAAALgAECgYJDgAAAA==.Hekkruk:BAAALgAECgMJAwABLgAFFAQJDAAeAF4gAA==.Hekus:BAAALgAECgUJBQABLgAECgcJEQAKAAAAAA==.Hemesia:BAAALgAECgEJAgAAAA==.Henshin:BAABLgAECn8sAAMFAAgJ2CKyDQDbAgAFAAgJ2CKyDQDbAgAEAAcJcxXxJQCDAQAAAA==.Herak:BAABLgAECn8hAAINAAcJxwv4JwBPAQANAAcJxwv4JwBPAQAAAA==.Hermiecrabbs:BAAALgAECgMJAwAAAA==.',
Hi='Highchairjr:BAABLgAECn8nAAMWAAgJZhpxEQAUAQABAAUJfBmvgQArAQAWAAcJABdxEQAUAQAAAA==.Hildaelf:BAAALgAECgYJDQABLgAECgcJGwAIAKUjAA==.',
Ho='Hojdeeznuts:BAABLgAECn8vAAMGAAgJSx6+EgBmAgAGAAgJSx6+EgBmAgAHAAYJ6gYO1gDMAAAAAA==.Holyfudge:BAAALgAECgMJAwAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgAECgMJBgAAAA==.Horazi:BAAALgAECgEJAQABLgAFFAIJBQAGAL0dAA==.Horohöro:BAAALgAFFAQJBAABLgAFFAQJDgALAMsZAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ib='Ibuprofen:BAAALgADCgcJBwAAAA==.',
Ii='Iil:BAABLgAECn8pAAMRAAgJjRdMSwDiAQARAAgJjRdMSwDiAQAXAAEJFRSWGwA9AAAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECggJKQARAI0XAA==.',
Is='Istor:BAAALgAECgUJCgAAAA==.',
Ja='Jaxxia:BAABLgAECn8rAAIGAAcJPBA1MQB9AQAGAAcJPBA1MQB9AQABLgAECggJJgAHABALAA==.',
Jb='Jblaze:BAAALgAECgYJDQAAAA==.',
Je='Jellzilla:BAAALgAECgEJAQAAAA==.Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAABLgAECn8XAAIaAAgJDBXzHgCgAQAaAAgJDBXzHgCgAQAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgAECgIJAgAAAA==.',
Jo='Joesphkony:BAAALgAECgIJAwAAAA==.Jorick:BAABLgAECn8VAAIHAAYJPQdO3gDBAAAHAAYJPQdO3gDBAAAAAA==.',
Ju='Ju:BAABLgAECn8bAAIfAAYJbRqgJwC+AQAfAAYJbRqgJwC+AQAAAA==.Juzodots:BAAALgAECgEJAgAAAA==.Juzomido:BAACLgAFFH8aAAINAAUJmhvyCwBXAQANAAUJmhvyCwBXAQAuAAQKfycAAg0ACQlsHHkEANMCAA0ACQlsHHkEANMCAAAA.',
Ka='Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn80AAIaAAkJ7BkaDgBQAgAaAAkJ7BkaDgBQAgAAAA==.Kaline:BAACLgAFFH8FAAIZAAQJfxQNDgDuAAAZAAQJfxQNDgDuAAAuAAQKfxcAAhkACAnjGqgGAFsCABkACAnjGqgGAFsCAAAA.Karupted:BAABLgAECn8XAAIMAAYJHAjKmQDxAAAMAAYJHAjKmQDxAAAAAA==.Katianna:BAABLgAECn81AAIJAAkJvB0FDADkAgAJAAkJvB0FDADkAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAABLgAECn8hAAIHAAgJERBNdwBlAQAHAAgJERBNdwBlAQAAAA==.Keola:BAAALgAECgUJBQABLgAECgkJBgAKAAAAAA==.Kerra:BAAALgADCgMJAwAAAA==.',
Kh='Khalli:BAABLgAECn8wAAMdAAgJDhofGAD2AQAdAAcJyxkfGAD2AQASAAEJVwccfwArAAAAAA==.Khalwena:BAAALgAECgEJAQAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Kinddurid:BAAALgADCgEJAQAAAA==.Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAABLgAECn8ZAAMHAAcJVRKNfABaAQAHAAcJVRKNfABaAQAIAAIJ0wA2UAAdAAAAAA==.Kissesnhugs:BAAALgADCgUJBwAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.Kiwirage:BAAALgAECgUJBQAAAA==.Kizent:BAAALgAECgQJCAAAAA==.',
Ko='Koraena:BAAALgAECgYJEAAAAA==.Koronuss:BAAALgAFFAIJAwAAAA==.',
Kr='Krivgar:BAAALgAECgcJDwAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgQJBQAAAA==.',
Ku='Kulrig:BAACLgAFFH8PAAQSAAMJ6REqHgDcAAASAAMJ6REqHgDcAAAdAAMJ/gUrIQCQAAAcAAIJ3QI7OgBcAAAuAAQKf0cABBIACAl6HA4RADMCABIACAl6HA4RADMCAB0ABwlxF14fAOYBABwAAQkNBuB5ABAAAAAA.Kurwa:BAAALgADCggJDQAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgAECgUJBQAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECgcJGQAMADcPAA==.Lanlong:BAAALgADCgcJCgABLgAECgYJEQAKAAAAAA==.Lastmark:BAAALgADCgcJDgAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFgAAAA==.Liliac:BAAALgADCgEJAQAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loryian:BAAALgADCgYJBgAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgAECgYJCwABLgAECgcJGwAIAKUjAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunalei:BAAALgAECgIJAgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAABLgAECn8cAAIgAAkJmB3IFwBKAgAgAAkJmB3IFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malganon:BAABLgAECn8xAAIHAAgJLB7gJQBUAgAHAAgJLB7gJQBUAgAAAA==.Marcille:BAAALgAECgEJAQAAAA==.Margarrann:BAAALgAECgIJAgABLgAFFAMJDwASAOkRAA==.Markymark:BAAALgADCgYJBgAAAA==.Martheiran:BAAALgAECgYJCgAAAA==.Marzanna:BAAALgAECgQJBAAAAA==.Mashpewtater:BAAALgAECgcJEgAAAA==.Mashpwntato:BAAALgAECgYJCwAAAA==.Mathelmana:BAABLgAECn8wAAMCAAgJWBYkEQAvAQABAAcJThEUaABiAQACAAcJ/xQkEQAvAQAAAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Me='Mellwin:BAAALgAECgQJBAAAAA==.Mezthyr:BAAALgADCggJCAAAAA==.',
Mi='Miliandra:BAAALgADCgYJDwAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8pAAISAAkJCRIBHADIAQASAAkJCRIBHADIAQAAAA==.Miseral:BAABLgAECn9DAAIYAAkJvSA4BADyAgAYAAkJvSA4BADyAgAAAA==.Missfrost:BAAALgAECgIJCAAAAA==.Mitzy:BAAALgAECgUJCAAAAA==.',
Mo='Moganchee:BAABLgAECn8dAAMRAAkJtgTMkAA7AQARAAkJtgTMkAA7AQAhAAcJCgJmCADiAAAAAA==.Mooeck:BAAALgAECgEJAgAAAA==.Mordakka:BAAALgAFFAEJAQABLgAFFAMJDwASAOkRAA==.Morghella:BAABLgAECn9CAAIMAAkJWB9nDQDTAgAMAAkJWB9nDQDTAgAAAA==.Morticiaa:BAAALgAECgEJAQAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Mourningwood:BAAALgADCggJCAAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgADCgUJCgAAAA==.Mysticjaina:BAAALgAECgUJBQABLgAECgkJJwAEAPIVAA==.Mythros:BAAALgAECgcJBwAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Na='Nasman:BAAALgADCggJCwAAAA==.',
Ne='Needswowaa:BAAALgAECgcJEQAAAA==.Nesmae:BAAALgAECggJEQABLgAFFAQJDgAMAP4aAA==.',
Ni='Nightwitch:BAAALgAECgYJCAAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAACLgAFFH8OAAIMAAQJ/hoWJgBMAQAMAAQJ/hoWJgBMAQAuAAQKfzAAAgwACQkcI3wMANwCAAwACQkcI3wMANwCAAAA.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECggJDQAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAECgYJCgAAAA==.',
Ol='Oleyinka:BAAALgAECgcJDgAAAA==.',
Om='Omnissiah:BAABLgAECn8sAAIdAAgJhRW3GgDcAQAdAAgJhRW3GgDcAQAAAA==.',
On='Once:BAABLgAECn8aAAMHAAcJyRqnZgCIAQAHAAYJ+xqnZgCIAQAGAAUJZBDuXwD9AAAAAA==.Oneyedemon:BAAALgADCggJCQAAAA==.Oneyeshoter:BAAALgADCgEJAQABLgAECgYJFwAMABwIAA==.',
Op='Opaths:BAABLgAECn8qAAMPAAgJJiHrGwCMAgAPAAgJJiHrGwCMAgAiAAIJzRDbIwB1AAAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAABLgAECn8sAAIIAAgJcyOeAwDAAgAIAAgJcyOeAwDAAgAAAA==.',
Pe='Peng:BAABLgAECn8VAAQjAAkJTw/NHQArAQAjAAgJ3g/NHQArAQAkAAEJYwsMbwArAAAbAAEJhQJSowAhAAAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAFFAMJBgAGADkTAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Priedorei:BAAALgAECgUJBQAAAA==.Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgcJBwAAAA==.',
Ps='Psyberollin:BAAALgAECgcJBwABLgAECgkJBgAKAAAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Pv='Pvp:BAABLgAECn8ZAAIGAAkJJhLBHQD/AQAGAAkJJhLBHQD/AQAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJCQAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAABLgAECn8XAAMfAAgJmiMrBgAmAwAfAAgJmiMrBgAmAwAaAAIJ0wUhgABBAAAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAABLgAECn8lAAIGAAkJPhnhFQBGAgAGAAkJPhnhFQBGAgAAAA==.Raydoink:BAAALgAECgYJBgAAAA==.',
Re='Reighan:BAAALgADCgUJBwAAAA==.Remiel:BAAALgAECgEJAQAAAA==.Renka:BAAALgAECgQJCAAAAA==.Revolting:BAABLgAFFH8YAAIDAAYJCRUuIQB8AQADAAYJCRUuIQB8AQAAAA==.Reze:BAAALgAECgEJAQABLgAFFAMJBQACAEUfAA==.Rezme:BAAALgADCgkJFAAAAA==.',
Rh='Rhaeny:BAAALgADCgEJAQAAAA==.',
Ri='Rianne:BAAALgAECgUJDwAAAA==.Rizeen:BAAALgAECgYJEAAAAA==.',
Ro='Rowanbow:BAAALgAECgQJDAAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn8zAAMFAAkJ8RqkEAC6AgAFAAkJ8RqkEAC6AgAEAAUJsAcvXACHAAAAAA==.',
Sa='Saberhawk:BAABLgAECn8UAAIMAAcJWQ5ragBVAQAMAAcJWQ5ragBVAQAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sakee:BAAALgAECgEJAQABLgAECgMJBgAKAAAAAA==.Sakurazuka:BAABLgAECn8sAAIBAAcJhxP5YABzAQABAAcJhxP5YABzAQAAAA==.Salaminizer:BAAALgAECgEJBAAAAA==.Samidudu:BAABLgAECn8YAAIZAAcJSRVkHABGAQAZAAcJSRVkHABGAQAAAA==.Sanath:BAABLgAECn8kAAIVAAkJwQ4SKACIAQAVAAkJwQ4SKACIAQAAAA==.Sanctusdeus:BAAALgAFFAEJAQAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECgkJNgANAO0YAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8dAAIEAAcJdiRQHwAFAgAEAAcJdiRQHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAABLgAECn8sAAITAAkJXSJdAQAYAwATAAkJXSJdAQAYAwAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAFFAMJDwASAOkRAA==.Sevotharte:BAAALgAECgIJAwAAAA==.',
Sg='Sgtmoose:BAAALgADCgYJBgAAAA==.',
Sh='Shadobread:BAAALgAECgcJEwAAAA==.Shadowglider:BAAALgAECgQJBgAAAA==.Shammhammer:BAAALgADCgEJAQAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8TAAIJAAMJayTkJQAqAQAJAAMJayTkJQAqAQAuAAQKfyoAAgkACQnRJJEBAKsDAAkACQnRJJEBAKsDAAAA.Shioban:BAAALgAECgIJAQAAAA==.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8eAAIeAAkJHRkTCAAuAgAeAAkJHRkTCAAuAgAAAA==.',
Si='Sib:BAAALgAECgMJBAAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Sissyo:BAAALgADCgYJDQAAAA==.',
Sk='Skeets:BAAALgADCgcJDwAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sleasem:BAAALgADCgIJAgAAAA==.Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAABLgAECn8dAAIHAAgJmBdMSADVAQAHAAgJmBdMSADVAQAAAA==.Snke:BAAALgADCgcJBwABLgAECggJHQAHAJgXAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8tAAIPAAkJvR+tHgDJAgAPAAkJvR+tHgDJAgAAAA==.Somah:BAAALgADCgEJAQAAAA==.Sonofgods:BAABLgAECn8aAAIMAAcJXRXgVgCGAQAMAAcJXRXgVgCGAQAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.Soulsnack:BAAALgAECgEJAgABLgAECggJIwADAHMOAA==.',
Sp='Spectrahl:BAABLgAECn8mAAIOAAgJQRKwLAB4AQAOAAgJQRKwLAB4AQABLgAFFAQJDgAMAP4aAA==.Spedspidspud:BAABLgAECn8aAAIDAAcJ0SDwJQAgAgADAAcJ0SDwJQAgAgAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECgkJLgASAJEQAA==.',
St='Starrbuck:BAABLgAECn8vAAMFAAgJWguqYgD7AAAFAAcJ5wiqYgD7AAAEAAEJrwJflgAZAAAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8YAAINAAgJfRLoGwCvAQANAAgJfRLoGwCvAQAAAA==.Stryke:BAABLgAECn8gAAIdAAgJgBo+EABPAgAdAAgJgBo+EABPAgAAAA==.',
Su='Sunfury:BAAALgAECgQJBQAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgAECgMJBQAAAA==.Suterareta:BAABLgAECn8kAAMlAAgJqBQBDQBrAQAlAAgJbhEBDQBrAQAYAAYJbxWPPwD9AAAAAA==.',
Sy='Sylareith:BAAALgAECgYJDgAAAA==.Syntara:BAABLgAECn81AAITAAkJPCA2AwDBAgATAAkJPCA2AwDBAgAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taggalongg:BAAALgADCgYJBgAAAA==.Taksun:BAABLgAECn83AAIZAAgJBRu1CgAZAgAZAAgJBRu1CgAZAgAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn82AAIQAAkJzg1DHABdAQAQAAkJzg1DHABdAQAAAA==.Tav:BAABLgAFFH8LAAMkAAQJVRghEwAaAQAkAAQJsRIhEwAaAQAjAAIJnxqcHQCLAAAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAABLgAECn8bAAMIAAcJpSMHCAA/AgAIAAcJpSMHCAA/AgAHAAUJPBFtxADkAAAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.Thewarwithin:BAAALgADCggJCAAAAA==.',
Ti='Tianara:BAACLgAFFH8GAAMGAAMJORN5KADKAAAGAAMJORN5KADKAAAHAAIJtRl9cQCcAAAuAAQKfxcAAwYACAmNIfIEAB0DAAYACAmNIfIEAB0DAAgABAk+FWwqALgAAAAA.Titania:BAAALgADCgQJBAAAAA==.',
Tj='Tjismyname:BAAALgAECgYJDwAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgMJBAAAAA==.Tokens:BAAALgAECgcJCAAAAA==.Tolerabull:BAABLgAECn8sAAQGAAgJdh61FgA+AgAGAAcJjh21FgA+AgAIAAYJjwjQJADSAAAHAAEJpxOxXQE7AAAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trixxe:BAABLgAECn8yAAIDAAkJWBp9IAA+AgADAAkJWBp9IAA+AgAAAA==.Trojaan:BAABLgAECn8VAAIbAAkJMgU0VgDbAAAbAAkJMgU0VgDbAAAAAA==.Trulisha:BAAALgAECgYJEQAAAA==.Trurala:BAAALgAECgEJAQABLgAECgYJBgAKAAAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgMJAwAAAA==.',
Ue='Uelfaen:BAAALgADCgYJBwAAAA==.',
Un='Undolf:BAAALgAECgMJAwAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8kAAIQAAkJkQZAJgAJAQAQAAkJkQZAJgAJAQAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAABLgAECn8VAAISAAcJoQWmRADWAAASAAcJoQWmRADWAAAAAA==.',
Va='Vaderon:BAAALgAECgYJCgAAAA==.Vaelanar:BAAALgAECgYJCAAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vayine:BAACLgAFFH8QAAIIAAQJfwdOCgC4AAAIAAQJfwdOCgC4AAAuAAQKfysAAggACQkxFKIVAHYBAAgACQkxFKIVAHYBAAAA.Vaynitee:BAAALgADCgcJDQAAAA==.',
Ve='Venmo:BAAALgAECgYJCAABLgAECggJLAAQAGEbAA==.Veridesh:BAAALgAECgcJCwABLgAFFAMJDwASAOkRAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAAALgAECggJEAAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAECgYJBgABLgAECgkJLwAJAOwkAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8iAAIQAAkJQhPjFACsAQAQAAkJQhPjFACsAQAAAA==.',
Vy='Vynlash:BAAALgADCgMJAQAAAA==.',
['Vì']='Vìcious:BAABLgAECn8tAAMMAAgJNxVJQADKAQAMAAgJNxVJQADKAQANAAYJRQ+CKgA9AQAAAA==.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgcJGgADANEgAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wicks:BAAALgAECgYJBgAAAA==.Wigglyears:BAABLgAECn8uAAMSAAkJkRDqHwCoAQASAAkJkRDqHwCoAQAcAAcJwQ8iKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgQJBwAAAA==.',
Ws='Wselfwulf:BAAALgAECgUJDwABLgAECgcJGwAIAKUjAA==.',
Xa='Xanadaria:BAAALgAECgYJCwABLgAECgkJCAAKAAAAAA==.Xanalluna:BAAALgAECgIJAgABLgAECgkJCAAKAAAAAA==.Xandrelyra:BAAALgADCgMJBQABLgAECgkJCAAKAAAAAA==.Xanvarani:BAAALgAECgkJCAAAAA==.',
Xe='Xeriirado:BAAALgAECgcJBwAAAA==.Xeril:BAAALgAECgQJBQAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgADCgkJEAABLgAECgQJCAAKAAAAAA==.Yakushimaru:BAABLgAECn80AAIEAAkJmiBFBgDjAgAEAAkJmiBFBgDjAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgMJBQAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgIJAwAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAABLgAFFH8LAAIHAAQJKBg+MQAxAQAHAAQJKBg+MQAxAQAAAA==.Zeith:BAABLgAECn8mAAIjAAkJXRbsDQDzAQAjAAkJXRbsDQDzAQAAAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgYJBgAAAA==.',
Zi='Zildon:BAAALgAECgYJCwAAAA==.',
Zu='Zurik:BAACLgAFFH8MAAIeAAQJXiBGAwByAQAeAAQJXiBGAwByAQAuAAQKfywAAh4ACQkKIJoCAOMCAB4ACQkKIJoCAOMCAAAA.',
Zy='Zyphoros:BAAALgADCgkJCwAAAA==.',
['Äz']='Äzúlà:BAAALgAECgUJCQAAAA==.',
['År']='Årrowz:BAAALgAECgIJAgAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAABLgAECn8UAAIHAAcJ9wfOvQDuAAAHAAcJ9wfOvQDuAAAAAA==.',
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
