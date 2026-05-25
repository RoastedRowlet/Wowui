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

local lookup = {'Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Unknown-Unknown','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Survival','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Priest-Shadow','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Mage-Arcane','DemonHunter-Havoc','Druid-Guardian','Monk-Windwalker','Warrior-Fury','Priest-Discipline','Priest-Holy','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety','Mage-Fire','Warrior-Protection','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abelothh:BAABLgAECn8aAAMBAAgJNQsZawBPAQABAAgJjwkZawBPAQACAAQJOw34EwDwAAAAAA==.Aborted:BAAALgADCgEJAQAAAA==.',
Ad='Adialin:BAAALgADCgQJBwAAAA==.',
Ae='Aelirra:BAABLgAECn8VAAIDAAcJyBqmMgAvAgADAAcJyBqmMgAvAgAAAA==.',
Ag='Agarmon:BAAALgAECgUJBgAAAA==.Agarne:BAABLgAECn8YAAMEAAgJ7hP8LgA1AQAEAAUJ8BX8LgA1AQAFAAUJPA92agDUAAAAAA==.Agman:BAAALgADCgkJCQAAAA==.',
Ai='Aimster:BAAALgAECgkJBwAAAA==.Aiyania:BAAALgADCgMJAwAAAA==.',
Ak='Akhta:BAABLgAECn8eAAMGAAkJ1By0CwCuAgAGAAkJ1By0CwCuAgAHAAYJeAz/qQAGAQAAAA==.Akoni:BAAALgAECgYJCgABLgAECgcJGwAIAKUjAA==.',
Al='Allaris:BAABLgAECn8ZAAIBAAYJAAXitQDBAAABAAYJAAXitQDBAAAAAA==.Allíesin:BAAALgAECgUJCAAAAA==.Altryn:BAAALgAECgMJBgAAAA==.Alundrablaze:BAABLgAECn8iAAIJAAgJ8hdaHQA0AgAJAAgJ8hdaHQA0AgABLgAECggJKAABAN4SAA==.',
Am='Amarixa:BAAALgADCgcJCgABLgAECgUJBwAKAAAAAA==.',
An='Angerissue:BAAALgADCgYJEQAAAA==.Anithaya:BAAALgADCgcJBwAAAA==.Anoint:BAACLgAFFH8OAAILAAQJyxl8FwA3AQALAAQJyxl8FwA3AQAuAAQKfzgAAgsACQlrIW4FAM4CAAsACQlrIW4FAM4CAAAA.Anrraakk:BAAALgADCgYJBgAAAA==.',
Ap='Apollis:BAAALgADCgcJBwAAAA==.',
Ar='Aram:BAAALgAECggJCAAAAA==.Aranthino:BAAALgAECggJDgAAAA==.Aryabhatta:BAABLgAECn8iAAMMAAgJHx2KIwAqAgAMAAgJHx2KIwAqAgANAAYJ4RDKHgCHAQAAAA==.',
As='Ashrom:BAAALgADCgkJEwAAAA==.Asrai:BAAALgADCgEJAQAAAA==.Astel:BAAALgAECggJCQAAAA==.',
At='Athenarelia:BAABLgAECn8ZAAIJAAgJjBA2OgCUAQAJAAgJjBA2OgCUAQAAAA==.',
Ba='Backbush:BAAALgAECgQJBwAAAA==.Baelskrim:BAABLgAECn8WAAIOAAcJUR26HQDHAQAOAAcJUR26HQDHAQAAAA==.Ballofsoy:BAAALgAECgEJAQAAAA==.Ballrogg:BAAALgADCgYJBgAAAA==.Bamdk:BAABLgAECn9HAAMPAAkJfSBCFwCZAgAPAAkJ3B9CFwCZAgAQAAMJng5yPwBhAAAAAA==.',
Be='Beansination:BAACLgAFFH8FAAIJAAIJrB3fQQCrAAAJAAIJrB3fQQCrAAAuAAQKfxYAAw4ACQmtF04bANsBAA4ACQmtF04bANsBAAkABQnIFPlRAD0BAAAA.Beefsupriem:BAAALgAECggJEwAAAA==.Bellatrïx:BAAALgAECgEJAgABLgAECgUJCAAKAAAAAA==.Belliaz:BAAALgAECgUJBwAAAA==.',
Bi='Biamdon:BAAALgADCgYJBgAAAA==.Bigcheese:BAAALgAECgEJAQAAAA==.Bigfinger:BAAALgAECgEJAQAAAA==.Biohazard:BAAALgAECgYJDgABLgAFFAMJBgAGADkTAA==.',
Bl='Bloodlyfrost:BAABLgAECn8sAAIRAAkJCAa8cgB3AQARAAkJCAa8cgB3AQAAAA==.Bloodwell:BAAALgAECgUJBQAAAA==.Bloodyguthix:BAAALgAECgcJCwAAAA==.',
Bo='Bonekrusha:BAAALgADCgYJBgAAAA==.Boombostic:BAAALgADCgcJBwAAAA==.',
Br='Brallaghan:BAAALgADCgEJAQAAAA==.Bramblegrove:BAAALgAECgYJCQABLgAFFAMJDQASAGwPAA==.Breaknasweat:BAAALgAECgIJAgAAAA==.Breakstuff:BAAALgAECgEJAQAAAA==.Brewsandboos:BAAALgADCgYJBgAAAA==.Bruzera:BAAALgADCgYJBgAAAA==.Bréwtality:BAAALgAECgEJAQABLgAFFAQJCwAPAOocAA==.',
['Bò']='Bòóberry:BAAALgAECgMJAwAAAA==.',
Ca='Candyquartz:BAAALgADCgcJFwAAAA==.Caylda:BAAALgAECgUJBQAAAA==.',
Ce='Celladorne:BAAALgAECgcJCwAAAA==.',
Ch='Chibi:BAACLgAFFH8QAAITAAQJ5gJ1CADrAAATAAQJ5gJ1CADrAAAuAAQKfyoAAhMACQnVEskPALwBABMACQnVEskPALwBAAAA.Chronokite:BAABLgAECn8YAAMUAAgJtAkgGwAFAQAUAAcJAgcgGwAFAQAVAAcJcwlMQAABAQAAAA==.',
Co='Colair:BAAALgAECgQJBQAAAA==.',
Cp='Cpr:BAAALgAECgQJDgAAAA==.',
Cr='Crushed:BAABLgAECn8UAAMWAAYJbRpgEwCwAQAWAAYJbRpgEwCwAQABAAIJQQvC4gBsAAAAAA==.',
Cy='Cybele:BAABLgAECn8XAAMJAAcJvBJkRgBoAQAJAAcJvBJkRgBoAQAOAAUJxwesZwCkAAABLgAECggJGAAUALQJAA==.',
Da='Da:BAAALgADCgUJBQAAAA==.Dantioch:BAAALgADCgMJAwAAAA==.Darafragen:BAABLgAECn82AAIGAAkJaho5DACnAgAGAAkJaho5DACnAgAAAA==.Darkfuse:BAAALgAECgIJAgAAAA==.Darkliter:BAAALgADCgcJBwAAAA==.Darrethuzad:BAAALgADCgUJBQAAAA==.Daveycrocket:BAAALgADCgUJBQAAAA==.Dayman:BAABLgAECn8YAAIHAAYJKRzNWACiAQAHAAYJKRzNWACiAQAAAA==.',
Db='Dbk:BAAALgAECgYJEgAAAA==.',
De='Deader:BAAALgAECggJDwAAAA==.Deadlyydot:BAABLgAECn8WAAISAAYJ5gbRQgDZAAASAAYJ5gbRQgDZAAAAAA==.Deadlyykiss:BAABLgAECn8cAAIXAAYJywYoCQDPAAAXAAYJywYoCQDPAAAAAA==.Deathhowl:BAAALgAECgMJBAAAAA==.Demonsaber:BAAALgAECgYJDQAAAA==.Demonseed:BAAALgAECgYJBwAAAA==.Demonslice:BAABLgAECn8ZAAMYAAYJagpKLwDPAAAYAAYJagpKLwDPAAADAAQJ2wSTwAB1AAAAAA==.Derrf:BAAALgADCgMJAwAAAA==.Derrickalen:BAAALgADCgIJAgAAAA==.',
Di='Dinhdinh:BAAALgAECgQJBAAAAA==.Dire:BAAALgAECgIJBAAAAA==.Dirtydotz:BAAALgADCgUJBgAAAA==.Disengage:BAABLgAECn8tAAIMAAgJ3A+HTQCMAQAMAAgJ3A+HTQCMAQAAAA==.Displace:BAAALgAECgYJCwAAAA==.Divish:BAABLgAECn8qAAMUAAkJMRzEBQCQAgAUAAkJMRzEBQCQAgAVAAEJAADZjQAAAAAAAA==.',
Do='Dogan:BAAALgAECgQJBAAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Dorim:BAAALgADCgQJBQAAAA==.Dotaldtrump:BAAALgAECgIJAgAAAA==.',
Dr='Dragkin:BAAALgADCgYJBgAAAA==.Dragonrunner:BAAALgAECgEJAQAAAA==.Dragoon:BAAALgADCgQJBAAAAA==.Drenne:BAAALgADCgIJAgAAAA==.Dreyvia:BAAALgADCgUJBQAAAA==.Drfelgood:BAAALgADCgYJBgAAAA==.Drillanne:BAAALgAECgYJDQAAAA==.Droggnoir:BAAALgADCgEJAQABLgAECggJEwAKAAAAAA==.Dropdeath:BAAALgAECgUJBQAAAA==.Druecc:BAABLgAECn8eAAIRAAgJZxBaZgCUAQARAAgJZxBaZgCUAQAAAA==.Druidlord:BAABLgAECn8ZAAIZAAgJpALVNQCGAAAZAAgJpALVNQCGAAAAAA==.Drág:BAAALgADCgMJAwAAAA==.',
Du='Duckie:BAAALgAECggJCQAAAA==.Dumplíng:BAAALgAECgQJBAABLgAECggJGAAEAO4TAA==.',
Dy='Dyrre:BAAALgADCgEJAQABLgAECgIJBAAKAAAAAA==.',
Dz='Dzhunter:BAAALgAECgkJAQAAAA==.',
Ed='Edgerallen:BAABLgAECn8bAAMLAAgJFBARJwBYAQALAAgJFBARJwBYAQAaAAYJrgL/YQCHAAAAAA==.',
El='Elchronomagi:BAAALgADCgIJAgABLgAECggJGAAUALQJAA==.Elcuh:BAAALgADCgEJAQAAAA==.Eldenringtwo:BAAALgAECgUJCQAAAA==.Elereeste:BAAALgAECgcJCgAAAA==.Elianaa:BAAALgADCgMJBgAAAA==.Ellennia:BAAALgAECgUJBwAAAA==.',
Er='Era:BAABLgAECn8hAAIbAAcJCxsbIwC1AQAbAAcJCxsbIwC1AQAAAA==.',
Ex='Executions:BAAALgAECgQJBQAAAA==.',
Fa='Fanara:BAAALgAECgQJCwAAAA==.Fangtazia:BAAALgADCgQJBAAAAA==.Fartbiscuits:BAAALgADCgcJDQAAAA==.Farty:BAABLgAECn8aAAQJAAgJCB55EgCNAgAJAAgJCB55EgCNAgAOAAEJggpakwAnAAATAAEJHQCqNQAEAAAAAA==.Fathuman:BAAALgAECgYJBwAAAA==.',
Fe='Feff:BAAALgADCgQJBgABLgAECgEJAQAKAAAAAA==.Felbládes:BAAALgAECgMJBQAAAA==.Felrushu:BAAALgAECgMJAwAAAA==.Fenaly:BAAALgADCgUJBQAAAA==.Fenryumei:BAAALgADCgUJBQAAAA==.Fensdead:BAABLgAECn8kAAIaAAgJzRf7FwDKAQAaAAgJzRf7FwDKAQAAAA==.Fentarus:BAAALgADCggJCAAAAA==.',
Fi='Finluzzertok:BAAALgADCgQJBAABLgAECgkJJwARAKgDAA==.Fitua:BAABLgAECn8gAAIPAAkJjwu3fgCGAQAPAAkJjwu3fgCGAQAAAA==.Fizzbann:BAAALgAECgYJDgABLgAECgcJGwAIAKUjAA==.',
Fk='Fkingbeast:BAAALgAFFAgJAQAAAA==.',
Fl='Flowercat:BAAALgADCgcJDgAAAA==.',
Fo='Fordemocracy:BAAALgAECggJDgAAAA==.Foutre:BAABLgAECn8cAAIEAAgJEgoPMQApAQAEAAgJEgoPMQApAQAAAA==.',
Fr='Froghugger:BAAALgAECgUJBQAAAA==.Fruntstabba:BAAALgAECgEJAQAAAA==.',
Fu='Fudgefisting:BAAALgAECgEJAQAAAA==.Fuzzytotems:BAAALgAECgUJCAAAAA==.',
['Få']='Fång:BAAALgAECggJEAAAAA==.',
Ga='Galadenn:BAAALgADCgEJAQAAAA==.Garo:BAABLgAECn88AAITAAkJ8x9HAgDdAgATAAkJ8x9HAgDdAgAAAA==.',
Ge='Getlnmyvan:BAABLgAECn8qAAIHAAkJuCCCDADmAgAHAAkJuCCCDADmAgAAAA==.',
Gh='Ghoulgranny:BAAALgADCgMJAwAAAA==.Ghoulie:BAAALgAECgQJCAAAAA==.',
Gi='Gigglebytes:BAAALgADCgEJAQAAAA==.Gigipi:BAAALgAECgEJAQAAAA==.Gile:BAAALgAECgIJAQABLgAECgkJIAAPAI8LAA==.',
Gl='Glert:BAABLgAECn8WAAIRAAcJSxAcngCaAQARAAcJSxAcngCaAQAAAA==.',
Go='Goinpriest:BAABLgAECn8lAAQSAAkJcAZWLgA+AQASAAkJcAZWLgA+AQAcAAYJAwS8NQD3AAAdAAYJUAIxVQDiAAAAAA==.Goinsolo:BAABLgAECn8fAAMMAAkJgRGYLwD0AQAMAAkJgRGYLwD0AQANAAYJ4wKbOQDAAAAAAA==.Goonergizmo:BAAALgADCgYJBgAAAA==.Gorbon:BAABLgAECn8kAAMFAAgJzBnyHwBCAgAFAAgJzBnyHwBCAgAEAAUJeQ6eTQDzAAAAAA==.Gorecrush:BAAALgADCgEJAQABLgAFFAMJDQASAGwPAA==.Gorvax:BAABLgAECn8kAAMQAAgJYhaOFACcAQAQAAgJYhaOFACcAQAPAAMJ4xDR+wB1AAAAAA==.',
Gr='Grimnyx:BAAALgADCgYJCwAAAA==.Grimstout:BAAALgAECgEJAQAAAA==.Gripe:BAAALgADCggJEAAAAA==.Groguk:BAAALgAECgIJAgAAAA==.',
Gu='Gummymagic:BAAALgAECgcJEgABLgAFFAUJHQAMAMMgAA==.',
Gw='Gwenledyr:BAABLgAECn8+AAQCAAkJWB4iAwBbAgACAAgJmB0iAwBbAgABAAkJzxVoMQD7AQAWAAYJKBklDgAvAQAAAA==.',
Ha='Hairydeer:BAAALgADCgUJBQAAAA==.Hamrinuranus:BAAALgAECgEJAgAAAA==.Hazee:BAAALgADCgEJAQAAAA==.',
He='Heimei:BAAALgADCgEJAQABLgAECgYJEAAKAAAAAA==.Heimthrall:BAABLgAECn80AAIHAAkJpw2LVACtAQAHAAkJpw2LVACtAQAAAA==.Hekatee:BAAALgAECgQJCAAAAA==.Hekkruk:BAAALgAECgMJAwABLgAFFAQJCgAeAEIeAA==.Hekus:BAAALgAECgQJBAABLgAECgcJDgAKAAAAAA==.Hemesia:BAAALgAECgEJAgAAAA==.Henshin:BAABLgAECn8kAAMFAAgJ0CILFwBsAgAFAAcJOiMLFwBsAgAEAAcJ/RSWJQBwAQAAAA==.Herak:BAABLgAECn8hAAINAAcJxwsqJQBTAQANAAcJxwsqJQBTAQAAAA==.Hermiecrabbs:BAAALgAECgMJAwAAAA==.',
Hi='Highchairjr:BAABLgAECn8nAAMWAAgJZhrWDwAYAQABAAUJfBkjewAtAQAWAAcJABfWDwAYAQAAAA==.Hildaelf:BAAALgAECgYJDQABLgAECgcJGwAIAKUjAA==.',
Ho='Hojdeeznuts:BAABLgAECn8vAAMGAAgJSx7bEABrAgAGAAgJSx7bEABrAgAHAAYJ6gYsvwDmAAAAAA==.Holyfudge:BAAALgAECgMJAwAAAA==.Holysatan:BAAALgAECgQJBAAAAA==.Holytyr:BAAALgAECgMJBgAAAA==.Horazi:BAAALgAECgEJAQABLgAECgkJHgAGANQcAA==.Horohöro:BAAALgAFFAQJBAABLgAFFAQJDgALAMsZAA==.',
Hu='Huehue:BAAALgADCgYJBwAAAA==.',
Hy='Hybrid:BAAALgADCgkJGwAAAA==.',
['Hé']='Héaler:BAAALgADCgUJBwAAAA==.',
Ii='Iil:BAABLgAECn8lAAMRAAcJOhZXZwCRAQARAAcJOhZXZwCRAQAXAAEJFRSWGwA9AAAAAA==.',
Im='Imabustmommy:BAAALgAECgQJBwAAAA==.Imperator:BAAALgADCgUJBQAAAA==.',
Iq='Iqsamurai:BAAALgADCgQJAwAAAA==.',
Ir='Irwarrioryo:BAAALgADCgMJAwABLgAECgcJJQARADoWAA==.',
Is='Istor:BAAALgAECgUJCgAAAA==.',
Ja='Jaxxia:BAABLgAECn8lAAIGAAcJug6eMABuAQAGAAcJug6eMABuAQAAAA==.',
Jb='Jblaze:BAAALgAECgYJDQAAAA==.',
Je='Jellzilla:BAAALgAECgEJAQAAAA==.Jenjas:BAAALgADCgYJCwAAAA==.Jenjaz:BAABLgAECn8XAAIaAAgJDBU+HACjAQAaAAgJDBU+HACjAQAAAA==.Jenzo:BAAALgADCgcJCAAAAA==.',
Jh='Jhalicistu:BAAALgAECgIJAgAAAA==.',
Jo='Joesphkony:BAAALgADCgUJBQAAAA==.Jorick:BAABLgAECn8VAAIHAAYJPQdCyQDXAAAHAAYJPQdCyQDXAAAAAA==.',
Ju='Ju:BAABLgAECn8VAAIfAAYJoBaWLwBsAQAfAAYJoBaWLwBsAQAAAA==.Juzodots:BAAALgAECgEJAgAAAA==.Juzomido:BAACLgAFFH8WAAINAAUJ+xRbDABLAQANAAUJ+xRbDABLAQAuAAQKfycAAg0ACQlsHHkEANMCAA0ACQlsHHkEANMCAAAA.',
Ka='Kaidre:BAAALgADCgQJBAAAAA==.Kaijhin:BAABLgAECn8uAAIaAAgJvxjJFQDhAQAaAAgJvxjJFQDhAQAAAA==.Kaline:BAABLgAECn8XAAIZAAgJ4xqoBgBbAgAZAAgJ4xqoBgBbAgAAAA==.Karupted:BAABLgAECn8XAAIMAAYJHAjyjQDxAAAMAAYJHAjyjQDxAAAAAA==.Katianna:BAABLgAECn8sAAIJAAkJvB1BCgDpAgAJAAkJvB1BCgDpAgAAAA==.Kayfitz:BAAALgAECgcJAgAAAA==.',
Ke='Keallach:BAABLgAECn8gAAIHAAgJGQ8XaQB9AQAHAAgJGQ8XaQB9AQAAAA==.Keola:BAAALgAECgUJBQABLgAECgkJBgAKAAAAAA==.Kerra:BAAALgADCgMJAwAAAA==.',
Kh='Khalli:BAABLgAECn8oAAMdAAgJJxm+FwDpAQAdAAcJxBi+FwDpAQASAAEJJQfGdgAqAAAAAA==.Khapri:BAAALgADCgEJAQAAAA==.Khirah:BAAALgADCgUJBgAAAA==.Khora:BAAALgADCgUJCAAAAA==.',
Ki='Kinddurid:BAAALgADCgEJAQAAAA==.Kindmonk:BAAALgADCgMJAwAAAA==.Kindpaladin:BAABLgAECn8ZAAMHAAcJVRIMcwBoAQAHAAcJVRIMcwBoAQAIAAIJ0wAvSgAdAAAAAA==.Kissesnhugs:BAAALgADCgUJBwAAAA==.Kittycatlj:BAAALgADCgUJBQAAAA==.Kiwirage:BAAALgAECgUJBQAAAA==.Kizent:BAAALgAECgMJBAAAAA==.',
Ko='Koraena:BAAALgAECgUJCgAAAA==.Koronuss:BAAALgAFFAIJAgAAAA==.',
Kr='Krivgar:BAAALgAECgcJDwAAAA==.Krivgarr:BAAALgADCgEJAQAAAA==.Krongar:BAAALgADCgEJAQAAAA==.Kronoz:BAAALgAECgQJBQAAAA==.',
Ku='Kulrig:BAACLgAFFH8NAAQSAAMJbA9SGwDoAAASAAMJbA9SGwDoAAAdAAMJ/gWmHACmAAAcAAIJ3QK4MwBfAAAuAAQKf0YABBIACAmGG6wRACMCABIACAmGG6wRACMCAB0ABwlxF14fAOYBABwAAQkNBrxsACUAAAAA.Kurwa:BAAALgADCgcJCAAAAA==.Kushisgreat:BAAALgADCgEJAQAAAA==.',
['Ká']='Kám:BAAALgAECgUJBQAAAA==.',
['Kï']='Kïkîëzz:BAAALgADCggJDAAAAA==.',
La='Landrei:BAAALgAECgEJAQABLgAECgcJGQAMADcPAA==.Lanlong:BAAALgADCgcJCgABLgAECgYJEAAKAAAAAA==.Lastmark:BAAALgADCgcJDgAAAA==.',
Le='Lesrak:BAAALgADCgcJDQAAAA==.',
Li='Lightjohn:BAAALgADCgkJFgAAAA==.Liliac:BAAALgADCgEJAQAAAA==.',
Lo='Lockitdownz:BAAALgAECgEJAQAAAA==.Loryian:BAAALgADCgYJBgAAAA==.Loww:BAAALgAECgEJAQAAAA==.',
Lu='Luminnas:BAAALgAECgYJCwABLgAECgcJGwAIAKUjAA==.Lunaari:BAAALgAECgYJBgAAAA==.Lunalei:BAAALgAECgIJAgAAAA==.',
Ly='Lysius:BAAALgADCgMJBAAAAA==.',
Ma='Madeye:BAAALgADCgUJBQAAAA==.Maesunrays:BAAALgAECgEJAQAAAA==.Mahoraga:BAABLgAECn8cAAIgAAkJmB3IFwBKAgAgAAkJmB3IFwBKAgAAAA==.Malach:BAAALgADCgEJAgAAAA==.Malganon:BAABLgAECn8pAAIHAAgJihqNOQD8AQAHAAgJihqNOQD8AQAAAA==.Marcille:BAAALgAECgEJAQAAAA==.Margarrann:BAAALgAECgIJAgABLgAFFAMJDQASAGwPAA==.Martheiran:BAAALgAECgYJCgAAAA==.Marzanna:BAAALgADCgMJAwAAAA==.Mashpewtater:BAAALgAECgcJEgAAAA==.Mathelmana:BAABLgAECn8oAAMBAAgJ3hIAYwBiAQABAAcJIxEAYwBiAQACAAcJ6g8gEwD9AAAAAA==.Mawika:BAAALgAECgQJBQAAAA==.',
Me='Mellwin:BAAALgAECgQJBAAAAA==.Mezthyr:BAAALgADCggJCAAAAA==.',
Mi='Miliandra:BAAALgADCgYJDwAAAA==.Minervasande:BAAALgADCgIJAgAAAA==.Minshara:BAAALgADCgEJAQAAAA==.Mintcocoa:BAABLgAECn8mAAISAAgJ8A9DIwCGAQASAAgJ8A9DIwCGAQAAAA==.Miseral:BAABLgAECn86AAIYAAkJASDWBADOAgAYAAkJASDWBADOAgAAAA==.Missfrost:BAAALgAECgIJBwAAAA==.Mitzy:BAAALgAECgUJCAAAAA==.',
Mo='Moganchee:BAABLgAECn8dAAMRAAkJtgRggQBYAQARAAkJtgRggQBYAQAhAAcJCgJmCADiAAAAAA==.Mooeck:BAAALgAECgEJAQAAAA==.Mordakka:BAAALgAFFAEJAQABLgAFFAMJDQASAGwPAA==.Morghella:BAABLgAECn85AAIMAAkJbh4iEACoAgAMAAkJbh4iEACoAgAAAA==.Morticiaa:BAAALgAECgEJAQAAAA==.Mortician:BAAALgADCgcJBwAAAA==.Mourningwood:BAAALgADCggJCAAAAA==.Moána:BAAALgADCgQJBAAAAA==.',
My='Mynadshealu:BAAALgADCgUJCgAAAA==.Mythros:BAAALgAECgcJBwAAAA==.Mythweaver:BAAALgADCgYJBQAAAA==.',
Na='Nasman:BAAALgADCggJCwAAAA==.',
Ne='Needswowaa:BAAALgAECgcJDgAAAA==.Nesmae:BAAALgAECggJEQABLgAFFAQJCgAMAP4aAA==.',
Ni='Nightwitch:BAAALgAECgMJBAAAAA==.Ninjetta:BAAALgADCgEJAQAAAA==.',
No='Noirra:BAACLgAFFH8KAAIMAAQJ/hrLIABFAQAMAAQJ/hrLIABFAQAuAAQKfzAAAgwACQkcI3wMANwCAAwACQkcI3wMANwCAAAA.Nokzul:BAAALgADCgYJCQAAAA==.Noobtube:BAAALgADCgUJCQAAAA==.Nosferatuss:BAAALgADCgIJAgAAAA==.Novajiin:BAAALgADCgQJBQAAAA==.Noxxival:BAAALgAECgEJAQAAAA==.',
Ny='Nyakalii:BAAALgAECggJDQAAAA==.Nyxiana:BAAALgADCgYJCgAAAA==.',
Oc='Ocktuupas:BAAALgAECgYJCgAAAA==.',
Ol='Oleyinka:BAAALgAECgcJDgAAAA==.',
Om='Omnissiah:BAABLgAECn8mAAIdAAgJhRVkGADjAQAdAAgJhRVkGADjAQAAAA==.',
On='Once:BAAALgAECgcJEwAAAA==.Oneyedemon:BAAALgADCggJCQAAAA==.Oneyeshoter:BAAALgADCgEJAQABLgAECgYJFwAMABwIAA==.',
Op='Opaths:BAABLgAECn8lAAIPAAgJJSGsGQCKAgAPAAgJJSGsGQCKAgAAAA==.',
Or='Orcnick:BAAALgADCgYJBgAAAA==.',
Ov='Overfrosty:BAABLgAECn8kAAIIAAgJkSFDBACWAgAIAAgJkSFDBACWAgAAAA==.',
Pe='Peng:BAABLgAECn8UAAQiAAgJhg7zIgDvAAAiAAcJCw/zIgDvAAAjAAEJYwuFXwAxAAAbAAEJhQIMlwAhAAAAAA==.',
Po='Popedope:BAAALgAECgUJDAABLgAFFAMJBgAGADkTAA==.Potatospud:BAAALgADCgIJAwAAAA==.',
Pr='Priedorei:BAAALgADCgIJAgAAAA==.Prodagy:BAAALgADCgYJBgAAAA==.Prìde:BAAALgAECgcJBwAAAA==.',
Ps='Psyberollin:BAAALgAECgcJBwABLgAECgkJBgAKAAAAAA==.',
Pu='Punishedbill:BAAALgAECgYJBgAAAA==.Purgedfire:BAAALgAECgEJAgAAAA==.',
Pv='Pvp:BAABLgAECn8UAAIGAAgJ1hIBIwDHAQAGAAgJ1hIBIwDHAQAAAA==.',
Ra='Raal:BAAALgAECgIJAwAAAA==.Rahtas:BAAALgADCgYJCQAAAA==.Rangi:BAAALgAECgYJDAAAAA==.Ransus:BAAALgAECgEJAQAAAA==.Ratings:BAABLgAECn8XAAMfAAgJmiNOBQApAwAfAAgJmiNOBQApAwAaAAIJ0wWOdQBBAAAAAA==.Ravon:BAAALgADCgcJDAAAAA==.Rayda:BAABLgAECn8lAAIGAAkJPhkAFABJAgAGAAkJPhkAFABJAgAAAA==.Raydoink:BAAALgAECgYJBgAAAA==.',
Re='Reighan:BAAALgADCgUJBwAAAA==.Remiel:BAAALgAECgEJAQAAAA==.Renka:BAAALgAECgQJBgAAAA==.Revolting:BAABLgAFFH8SAAIDAAUJgQ7NNwAWAQADAAUJgQ7NNwAWAQAAAA==.Reze:BAAALgAECgEJAQABLgAFFAMJAwAKAAAAAA==.Rezme:BAAALgADCgkJFAAAAA==.',
Ri='Rianne:BAAALgAECgUJCwAAAA==.Rizeen:BAAALgAECgYJEAAAAA==.',
Ro='Rowanbow:BAAALgAECgQJDAAAAA==.',
Ru='Rumi:BAAALgADCgcJBwAAAA==.',
['Ré']='Rédd:BAABLgAECn8zAAMFAAkJ8RogDwC8AgAFAAkJ8RogDwC8AgAEAAUJsAfyVQCGAAAAAA==.',
Sa='Saberhawk:BAABLgAECn8UAAIMAAcJWQ5CXwBbAQAMAAcJWQ5CXwBbAQAAAA==.Sadness:BAAALgADCgEJAgAAAA==.Safaera:BAAALgAECgQJBQAAAA==.Sakurazuka:BAABLgAECn8lAAIBAAcJxhAeZABgAQABAAcJxhAeZABgAQAAAA==.Salaminizer:BAAALgAECgEJBAAAAA==.Samidudu:BAABLgAECn8YAAIZAAcJSRXWGABJAQAZAAcJSRXWGABJAQAAAA==.Sanath:BAABLgAECn8kAAIVAAkJwQ74IwCaAQAVAAkJwQ74IwCaAQAAAA==.Sanctusdeus:BAAALgAFFAEJAQAAAA==.Sandbag:BAAALgAECgMJAwAAAA==.Sardenn:BAAALgAECgEJAQABLgAECgkJNAANAJgXAA==.Sarelyn:BAAALgADCgEJAQAAAA==.',
Sc='Scarydream:BAABLgAECn8dAAIEAAcJdiRQHwAFAgAEAAcJdiRQHwAFAgAAAA==.Scoobyxdooby:BAAALgADCgUJBQAAAA==.Scottcooney:BAABLgAECn8oAAITAAgJJyJKAwCuAgATAAgJJyJKAwCuAgAAAA==.',
Se='Secondiceage:BAAALgADCgMJAwAAAA==.Serge:BAAALgAECgEJAQABLgAFFAMJDQASAGwPAA==.Sevotharte:BAAALgAECgIJAgAAAA==.',
Sg='Sgtmoose:BAAALgADCgYJBgAAAA==.',
Sh='Shadobread:BAAALgAECgcJEwAAAA==.Shadowglider:BAAALgAECgQJBgAAAA==.Shammhammer:BAAALgADCgEJAQAAAA==.Shaoxing:BAAALgAECgEJAQAAAA==.Sharindlar:BAACLgAFFH8SAAIJAAMJayQMIAAwAQAJAAMJayQMIAAwAQAuAAQKfyYAAgkACQnRJDIBAK4DAAkACQnRJDIBAK4DAAAA.Shmastus:BAAALgADCgUJBQAAAA==.Shockandrawr:BAAALgAECgYJCgAAAA==.Shokanu:BAABLgAECn8eAAIeAAkJHRkTBwA5AgAeAAkJHRkTBwA5AgAAAA==.',
Si='Sib:BAAALgAECgEJAgAAAA==.Silkysmooth:BAAALgADCgMJBgAAAA==.Sissyo:BAAALgADCgYJDQAAAA==.',
Sk='Skeets:BAAALgADCgcJDwAAAA==.Skeëts:BAAALgADCgUJBgAAAA==.',
Sl='Sliceschmax:BAAALgAECgQJCwAAAA==.',
Sn='Snakie:BAABLgAECn8dAAIHAAgJmBeeQADmAQAHAAgJmBeeQADmAQAAAA==.Snke:BAAALgADCgcJBwABLgAECggJHQAHAJgXAA==.',
So='Sofieeus:BAAALgADCgcJCQAAAA==.Sokorag:BAABLgAECn8tAAIPAAkJvR+tHgDJAgAPAAkJvR+tHgDJAgAAAA==.Sonofgods:BAABLgAECn8YAAIMAAYJ5RGIeAAfAQAMAAYJ5RGIeAAfAQAAAA==.Soulscape:BAAALgADCgkJJAAAAA==.Soulsnack:BAAALgAECgEJAgABLgAECgYJGwADACAOAA==.',
Sp='Spectrahl:BAABLgAECn8mAAIOAAgJQRLlKAB7AQAOAAgJQRLlKAB7AQABLgAFFAQJCgAMAP4aAA==.Spedspidspud:BAAALgAECgcJEwAAAA==.Spooky:BAAALgAECgEJAQAAAA==.Spoone:BAAALgAECgEJAgAAAA==.Sprinkler:BAAALgAECgUJBQAAAA==.',
Sq='Squee:BAAALgADCgEJAQABLgAECgkJLAASAE0QAA==.',
St='Starrbuck:BAABLgAECn8nAAMFAAgJ+wexawDQAAAFAAcJwwWxawDQAAAEAAEJrwINiwAZAAAAAA==.Stephii:BAAALgADCgYJBgAAAA==.Strongarrow:BAABLgAECn8YAAINAAgJfRKdGQCzAQANAAgJfRKdGQCzAQAAAA==.Stryke:BAABLgAECn8cAAIdAAcJYRiwGQDVAQAdAAcJYRiwGQDVAQAAAA==.',
Su='Sunfury:BAAALgAECgQJBQAAAA==.Supersack:BAAALgADCgIJAgAAAA==.Sushii:BAAALgAECgMJBQAAAA==.Suterareta:BAABLgAECn8dAAMkAAgJ6RNZDABmAQAkAAgJsBBZDABmAQAYAAYJbxWPPwD9AAAAAA==.',
Sy='Sylareith:BAAALgAECgYJDgAAAA==.Syntara:BAABLgAECn81AAITAAkJPCCyAgDIAgATAAkJPCCyAgDIAgAAAA==.',
['Sí']='Síelys:BAAALgAECgYJCgAAAA==.',
Ta='Taggalongg:BAAALgADCgYJBgAAAA==.Taksun:BAABLgAECn8vAAIZAAgJkBleDADiAQAZAAgJkBleDADiAQAAAA==.Tankque:BAAALgAECgEJAQAAAA==.Tauntindeath:BAABLgAECn80AAIQAAkJzg2yGQBgAQAQAAkJzg2yGQBgAQAAAA==.Tav:BAABLgAFFH8HAAMjAAMJaxhTGQDRAAAjAAMJahBTGQDRAAAiAAIJnxomGgCWAAAAAA==.',
Th='Thaia:BAAALgADCgEJAQAAAA==.Thaladrin:BAABLgAECn8bAAMIAAcJpSMhBwBCAgAIAAcJpSMhBwBCAgAHAAUJQBHQxQDcAAAAAA==.Thalard:BAAALgADCgEJAQAAAA==.Thawnos:BAAALgADCggJCgAAAA==.Thewarwithin:BAAALgADCggJCAAAAA==.',
Ti='Tianara:BAACLgAFFH8GAAMGAAMJOROcIwDUAAAGAAMJOROcIwDUAAAHAAIJtRnbYQCnAAAuAAQKfxcAAwYACAmNIfIEAB0DAAYACAmNIfIEAB0DAAgABAk+FWwqALgAAAAA.Titania:BAAALgADCgQJBAAAAA==.',
Tj='Tjismyname:BAAALgAECgYJDwAAAA==.',
To='Toasteon:BAAALgADCgYJBwAAAA==.Todesbär:BAAALgADCgcJCwAAAA==.Tok:BAAALgAECgMJBAAAAA==.Tokens:BAAALgAECgEJAQAAAA==.Tolerabull:BAABLgAECn8qAAQGAAgJtR3CFQA3AgAGAAcJDB3CFQA3AgAIAAYJjwgGIgDTAAAHAAEJng3nVwE1AAAAAA==.',
Tr='Tralynna:BAAALgADCgIJAwAAAA==.Trixxe:BAABLgAECn8yAAIDAAkJWBqYHQBFAgADAAkJWBqYHQBFAgAAAA==.Trojaan:BAABLgAECn8VAAIbAAkJMgVQUADdAAAbAAkJMgVQUADdAAAAAA==.Trulisha:BAAALgAECgYJEAAAAA==.',
Tw='Twolip:BAAALgAECgMJBwAAAA==.',
Ty='Tyleinthrel:BAAALgAECgIJAgAAAA==.',
Ue='Uelfaen:BAAALgADCgYJBwAAAA==.',
Un='Undolf:BAAALgADCgMJAwAAAA==.',
Uo='Uog:BAAALgADCgIJAgAAAA==.',
Ur='Urgott:BAABLgAECn8kAAIQAAkJkQZYIwAJAQAQAAkJkQZYIwAJAQAAAA==.Urmaria:BAAALgAECgYJBgAAAA==.Ursalaisis:BAAALgAECgcJEwAAAA==.',
Va='Vaderon:BAAALgAECgYJCgAAAA==.Vaelanar:BAAALgAECgYJBgAAAA==.Vajaina:BAAALgADCgEJAQAAAA==.Valalerie:BAAALgADCgYJBgAAAA==.Valentyn:BAAALgAECgEJAgAAAA==.Vayine:BAACLgAFFH8QAAIIAAQJfwfZCAC5AAAIAAQJfwfZCAC5AAAuAAQKfysAAggACQkxFKIVAHYBAAgACQkxFKIVAHYBAAAA.Vaynitee:BAAALgADCgcJDQAAAA==.',
Ve='Venmo:BAAALgAECgYJCAABLgAECggJJAAQAGIWAA==.Veridesh:BAAALgAECgcJCwABLgAFFAMJDQASAGwPAA==.',
Vi='Vinceoffer:BAAALgADCgkJDAAAAA==.Visenya:BAAALgAECgcJDAAAAA==.Vitrovius:BAAALgAECgEJAQAAAA==.',
Vo='Voidset:BAAALgADCgMJAwAAAA==.Voladus:BAAALgAECgYJBgABLgAECgkJLwAJAOwkAA==.Volaire:BAAALgAECgMJBAAAAA==.',
Vu='Vuskar:BAABLgAECn8gAAIQAAkJQhPnEgCyAQAQAAkJQhPnEgCyAQAAAA==.',
Vy='Vynlash:BAAALgADCgMJAQAAAA==.',
['Vì']='Vìcious:BAABLgAECn8tAAMMAAgJNxV5OADRAQAMAAgJNxV5OADRAQANAAYJRQ90JwBBAQAAAA==.',
Wa='Wangwingwong:BAAALgADCgMJAwABLgAECgcJEwAKAAAAAA==.',
Wh='Whozyerdaddy:BAAALgADCgMJAwAAAA==.',
Wi='Wicks:BAAALgAECgYJBgAAAA==.Wigglyears:BAABLgAECn8sAAMSAAkJTRCNHAC6AQASAAkJTRCNHAC6AQAcAAcJwQ8iKQBOAQAAAA==.Wildberd:BAAALgADCgEJAQAAAA==.Winwings:BAAALgADCgQJBwAAAA==.',
Ws='Wselfwulf:BAAALgAECgUJDwABLgAECgcJGwAIAKUjAA==.',
Xa='Xanadaria:BAAALgAECgUJCgABLgAECgkJCAAKAAAAAA==.Xanalluna:BAAALgAECgEJAQABLgAECgkJCAAKAAAAAA==.Xandrelyra:BAAALgADCgMJAwABLgAECgkJCAAKAAAAAA==.Xanvarani:BAAALgAECgkJCAAAAA==.',
Xe='Xeriirado:BAAALgAECgcJBwAAAA==.Xeril:BAAALgAECgQJBAAAAA==.',
Xx='Xxluminati:BAAALgADCgMJAwAAAA==.',
Ya='Yagermeister:BAAALgADCgcJBwABLgAECgQJCAAKAAAAAA==.Yakushimaru:BAABLgAECn8yAAIEAAkJmiBpBQDmAgAEAAkJmiBpBQDmAgAAAA==.Yasil:BAAALgADCgIJAgAAAA==.',
Yi='Yishan:BAAALgAECgMJBQAAAA==.',
Yo='Yos:BAAALgAECgEJAQAAAA==.',
Yu='Yuengling:BAAALgADCgEJAQAAAA==.Yuk:BAAALgAECgIJAwAAAA==.',
Za='Zaare:BAAALgAECgEJAQAAAA==.',
Ze='Zefren:BAABLgAFFH8HAAIHAAMJOhLNTQDnAAAHAAMJOhLNTQDnAAAAAA==.Zeith:BAABLgAECn8mAAIiAAkJXRZNDAAAAgAiAAkJXRZNDAAAAgAAAA==.Zev:BAAALgAECgIJAgAAAA==.',
Zh='Zhe:BAAALgADCgYJBgAAAA==.',
Zi='Zildon:BAAALgAECgYJCwAAAA==.',
Zu='Zurik:BAACLgAFFH8KAAIeAAQJQh6/AgB4AQAeAAQJQh6/AgB4AQAuAAQKfywAAh4ACQkKICUCAO8CAB4ACQkKICUCAO8CAAAA.',
Zy='Zyphoros:BAAALgADCgkJCwAAAA==.',
['Äz']='Äzúlà:BAAALgAECgMJBQAAAA==.',
['Ça']='Çaptainçhaos:BAAALgADCgMJAwAAAA==.',
['Ér']='Érodar:BAABLgAECn8UAAIHAAcJ9wfXqAAIAQAHAAcJ9wfXqAAIAQAAAA==.',
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
