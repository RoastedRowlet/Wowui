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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Warrior-Fury','Warrior-Protection','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Monk-Mistweaver','DeathKnight-Frost','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','Druid-Restoration','Priest-Shadow','Paladin-Holy','Monk-Brewmaster','Monk-Windwalker','Shaman-Enhancement','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Addely:BAAALgAECgYJBgAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgQJBwAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRqucACbAQAEAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJEQAAAA==.',
Al='Alerion:BAABLgAECn8sAAIFAAkJKhm0CgBiAgAFAAkJKhm0CgBiAgAAAA==.Allan:BAABLgAECn8rAAIGAAkJbiHRAADPAgAGAAkJbiHRAADPAgAAAA==.Alligatorjoe:BAAALgADCgEJAQAAAA==.',
Am='Amaneeda:BAABLgAECn8uAAIHAAgJFA7WKwBcAQAHAAgJFA7WKwBcAQAAAA==.Amazonia:BAAALgAECgQJBQAAAA==.Aminea:BAAALgAFFAEJAQAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAIAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8HAAIJAAIJHhUeCgB9AAAJAAIJHhUeCgB9AAAuAAQKfy8AAgkACAkhIkkDAJcCAAkACAkhIkkDAJcCAAAA.Angyrain:BAAALgAECgUJBgABLgAFFAIJBwAJAB4VAA==.Annerila:BAAALgADCgkJEQAAAA==.Antagonis:BAABLgAECn8YAAIDAAcJsQ59EQAUAQADAAcJsQ59EQAUAQAAAA==.',
Ap='Apexchi:BAAALgAECgMJBQAAAA==.Apeximmortal:BAAALgAECgYJAwAAAA==.Apexlight:BAAALgAECgkJEQAAAA==.Apexwar:BAAALgAECgEJAQAAAA==.',
Ar='Arashe:BAAALgAECgUJCQAAAA==.Arewen:BAAALgADCggJDAAAAA==.Arganos:BAABLgAECn8wAAMKAAkJtSYoAQBoAwAKAAkJtSYoAQBoAwALAAYJFxs6FgB9AQAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8WAAIMAAcJ6wT1rACrAAAMAAcJ6wT1rACrAAAAAA==.Arkstrife:BAAALgADCgEJAQAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgADCgkJMgAAAA==.Atheîst:BAABLgAECn9AAAMNAAkJdyXMAQBaAwANAAkJdyXMAQBaAwAOAAYJCyONDwBXAgAAAA==.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn9BAAMPAAkJ1x5IFwB3AgAPAAgJUR5IFwB3AgAQAAgJ5hN3KQCKAQAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAYJEwAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJMAAKALUmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8cAAMRAAcJuRrAEgC1AQARAAcJuRrAEgC1AQAKAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8fAAISAAYJ9RXmNABxAQASAAYJ9RXmNABxAQAAAA==.Baelanoth:BAABLgAECn8qAAITAAgJmhwABgAiAgATAAgJmhwABgAiAgAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balerion:BAAALgAECgEJAQAAAA==.Balkazaar:BAAALgAECggJEQAAAA==.Bammbamm:BAABLgAECn8nAAIEAAgJEwjHoAAbAQAEAAgJEwjHoAAbAQAAAA==.Banewreak:BAABLgAECn83AAIBAAkJwhdMIQBRAgABAAkJwhdMIQBRAgAAAA==.Banu:BAAALgAECgEJAQAAAA==.Baradin:BAAALgAECgYJDAAAAA==.Barind:BAABLgAECn8yAAQUAAkJFh1mBwCdAgAUAAkJmRxmBwCdAgAVAAcJIxqYJAADAgAWAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgQJBwAAAA==.Betrayer:BAACLgAFFH8FAAIXAAMJAxbyEgDeAAAXAAMJAxbyEgDeAAAuAAQKfyIAAhcACQnuIQEDABMDABcACQnuIQEDABMDAAAA.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAAALgAECggJEAAAAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Biqdonk:BAAALgAECgUJDAAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.Bloodhornz:BAAALgAECgEJAQAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDQABLgADCgYJCwAIAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAIAAAAAA==.Bossdwarf:BAAALgADCgcJCwABLgADCgYJCwAIAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleosévèn:BAAALgADCgUJBQABLgAECgkJQAANAHclAA==.',
['Bú']='Búbblés:BAAALgAECgcJDQAAAA==.',
Ca='Caatia:BAAALgAECggJCQAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECggJIQABAKEWAA==.Carthel:BAABLgAECn8fAAIYAAgJMiBYMQCtAgAYAAgJMiBYMQCtAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCggJDgAAAA==.',
Ce='Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Charley:BAAALgAECgYJBwAAAA==.Chasseresse:BAAALgAECgQJBQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chi:BAAALgAECgEJAQAAAA==.Chimarr:BAABLgAECn8cAAIZAAgJFiLfDgDOAgAZAAgJFiLfDgDOAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Co='Coldsploder:BAABLgAECn8pAAIYAAkJARcuMABBAgAYAAkJARcuMABBAgAAAA==.',
Cr='Crackmonkéy:BAABLgAECn8aAAQOAAgJ2BjAJgB2AQAOAAcJNBTAJgB2AQANAAQJkRlWTwD7AAAaAAQJdBA4QQDvAAAAAA==.Cranknspank:BAAALgAECgYJBwAAAA==.Cronoz:BAABLgAECn8kAAMPAAgJqwrbWQAhAQAPAAcJkgfbWQAhAQAQAAcJNgpbSAD2AAAAAA==.Crotchshot:BAABLgAECn8gAAIWAAgJuA/LTQCgAQAWAAgJuA/LTQCgAQAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Cursess:BAACLgAFFH8LAAIBAAMJsRmuWgD4AAABAAMJsRmuWgD4AAAuAAQKfzUAAgEACQlxIo4KAPACAAEACQlxIo4KAPACAAAA.',
['Có']='Cózmik:BAABLgAECn8UAAIWAAcJ3RYgUQCWAQAWAAcJ3RYgUQCWAQAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn8oAAIBAAgJ7Q9qWgCDAQABAAgJ7Q9qWgCDAQAAAA==.Dalya:BAAALgAECggJCgAAAA==.Dander:BAAALgADCgMJAwAAAA==.Dani:BAAALgAECgEJAgABLgAECgQJBQAIAAAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAAALgAECgYJEQAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deathratellr:BAAALgADCgEJAQAAAA==.Deemaius:BAAALgADCgUJCQAAAA==.Dekard:BAAALgAECggJEQAAAA==.Dekariusly:BAAALgAECgEJAQABLgAECggJEQAIAAAAAA==.Demonatrixx:BAAALgAECgYJCQAAAA==.Demonhugger:BAAALgAECgEJAgABLgAECgQJBAAIAAAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHwACAFwZAA==.Destinÿ:BAABLgAECn8jAAILAAgJPRdjFACRAQALAAgJPRdjFACRAQAAAA==.Devourer:BAABLgAECn8oAAIMAAgJGBuWJwAYAgAMAAgJGBuWJwAYAgAAAA==.',
Di='Disploder:BAABLgAECn8lAAINAAcJOhOyJQCBAQANAAcJOhOyJQCBAQAAAA==.Dist:BAAALgAECggJCwAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJAQABLgAECgEJAgAIAAAAAA==.Drawwn:BAAALgAECgEJAgAAAA==.Dreathhammer:BAABLgAECn8uAAIbAAkJ1SLgAgBpAwAbAAkJ1SLgAgBpAwAAAA==.Drogo:BAAALgAECggJCAABLgAECggJGgAOANgYAA==.Drureds:BAAALgAECgMJAwAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAgJHwAbAIIgAA==.',
Du='Duckcox:BAAALgAECgQJBwAAAA==.Dunadin:BAABLgAECn8WAAQSAAYJ/Rm2KgCrAQASAAYJ/Rm2KgCrAQAcAAIJ4xJlYgB1AAAdAAEJthWRgABAAAABLgAECgkJPAAJAK4mAA==.Dundyrn:BAABLgAECn88AAIJAAkJriYfAAB7AwAJAAkJriYfAAB7AwAAAA==.',
Dv='Dvera:BAAALgADCgMJAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECgkJPAAJAK4mAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAYJEAALAOkbAA==.',
El='Elememetal:BAABLgAECn8oAAIQAAkJvxi5GAAFAgAQAAkJvxi5GAAFAgAAAA==.Elfyparker:BAAALgAECgEJAQAAAA==.Elliott:BAAALgADCgIJAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Fa='Fanmir:BAAALgAECgEJAQAAAA==.Fatpao:BAAALgAECgYJBgAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAIPAAcJXQs/WQAjAQAPAAcJXQs/WQAjAQAAAA==.Fenix:BAAALgADCgEJAgAAAA==.',
Fi='Filbert:BAABLgAECn8dAAIHAAkJUyFHBgDjAgAHAAkJUyFHBgDjAgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Foldyholds:BAAALgADCgMJAwAAAA==.Fomy:BAAALgAECgEJAQABLgAECgkJGwAHAKANAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDgAIAAAAAA==.',
Fr='Fraw:BAAALgADCggJDAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAwAAAA==.Fuzzyhunter:BAAALgAECgEJAQAAAA==.',
['Fá']='Fálola:BAABLgAECn88AAMPAAgJrxffKADsAQAPAAgJrxffKADsAQAQAAYJwwPdYwCdAAAAAA==.',
Ga='Gamblex:BAAALgAECgUJDgAAAA==.Garviel:BAABLgAECn8bAAIRAAcJNhlOEwCvAQARAAcJNhlOEwCvAQAAAA==.',
Ge='Geethatlock:BAABLgAECn8ZAAIBAAgJExbfQADNAQABAAgJExbfQADNAQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAABLgAECn8bAAIVAAYJ7BbUDgBVAQAVAAYJ7BbUDgBVAQAAAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgADCgYJCwAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAABLgAECn8bAAIPAAgJ8RvsGwBSAgAPAAgJ8RvsGwBSAgAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grogu:BAABLgAECn8dAAIYAAcJBQp/qQAQAQAYAAcJBQp/qQAQAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJAwAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAFFAMJAwAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgcJBwAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECgkJLgAeAL0fAA==.Hiksham:BAABLgAECn8uAAMeAAkJvR9MBACaAgAeAAkJnB9MBACaAgAQAAgJBw3DNABMAQAAAA==.',
Ho='Holycheeze:BAAALgADCgcJCgAAAA==.Holyhoof:BAAALgAECgEJAQAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECggJIQABAKEWAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgcJGQAPAGwVAA==.',
Ia='Iamreggi:BAAALgAECgQJBgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8pAAIaAAgJDhR3HQC7AQAaAAgJDhR3HQC7AQAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Im:BAAALgAECgEJAQAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
Ir='Irisi:BAAALgADCgUJBQAAAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECggJGgAfALsWAA==.Jarlyss:BAABLgAECn8aAAIfAAgJuxaDEAC+AQAfAAgJuxaDEAC+AQAAAA==.Javieraa:BAABLgAECn8gAAIMAAkJYRqAIwAtAgAMAAkJYRqAIwAtAgAAAA==.',
Jd='Jdai:BAABLgAECn8ZAAIPAAcJbBUjNgC9AQAPAAcJbBUjNgC9AQAAAA==.',
Jo='Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAAALgAECgcJEAAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgADCgQJBAAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8aAAIMAAYJkCCcFQDEAQAMAAYJkCCcFQDEAQAuAAQKf0MAAgwACQlkJLYDADwDAAwACQlkJLYDADwDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn8tAAIXAAgJ5AztIQBEAQAXAAgJ5AztIQBEAQAAAA==.Kikyo:BAAALgAECgYJDQAAAA==.Kimmi:BAAALgAECgQJBwAAAA==.Kinzen:BAABLgAECn8xAAIeAAcJhSDECwDaAQAeAAcJhSDECwDaAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIgAAYJAyEjDQDmAQAgAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8jAAIYAAgJPAqdhQBRAQAYAAgJPAqdhQBRAQAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgAECgIJAgABLgAECgkJOgAOAFgcAA==.',
Le='Lechwe:BAABLgAECn8pAAIPAAgJpBpwFwB2AgAPAAgJpBpwFwB2AgAAAA==.Legonator:BAAALgAECgUJCAAAAA==.Lenry:BAAALgAFFAEJAQAAAA==.',
Li='Lichmajor:BAABLgAECn8nAAIhAAkJ6BiYPwDyAQAhAAkJ6BiYPwDyAQAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn8eAAISAAcJAiG6EwBdAgASAAcJAiG6EwBdAgAAAA==.Lovepet:BAABLgAECn8+AAMWAAkJ9x2mFACWAgAWAAkJ9x2mFACWAgAVAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAAALgAECgQJBAAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn83AAIYAAkJbiAnHQCXAgAYAAkJbiAnHQCXAgAAAA==.Lunavis:BAAALgAECgEJAQABLgAECgkJGAAZAPUNAA==.',
Ly='Lyda:BAABLgAECn8tAAIZAAgJfhsLGQBrAgAZAAgJfhsLGQBrAgAAAA==.',
Ma='Magice:BAABLgAECn8UAAIYAAUJiAI4CgFyAAAYAAUJiAI4CgFyAAAAAA==.Magmara:BAAALgADCgkJEgAAAA==.Malibubarbie:BAABLgAECn8mAAINAAgJ/g2iJgB6AQANAAgJ/g2iJgB6AQAAAA==.Malthael:BAAALgAECgEJAQAAAA==.Malystron:BAAALgAECgkJEAAAAA==.Maneevent:BAABLgAECn8ZAAQWAAYJGReAdwA3AQAWAAYJGReAdwA3AQAUAAEJ1wSHYAAsAAAVAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn86AAMOAAkJWBxmBwDpAgAOAAkJWBxmBwDpAgAaAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn89AAIWAAkJyQlSSQCtAQAWAAkJyQlSSQCtAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8UAAQgAAUJphw1BABYAQAgAAQJHRw1BABYAQAfAAEJhxPoBgA6AAAHAAEJAADVSgAAAAAuAAQKfyoABCAACQkiI7wBAA4DACAACQkiI7wBAA4DAB8AAQkxIY0pAFQAAAcAAQkqFVJ3AEEAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn8sAAINAAkJBw96HgC5AQANAAkJBw96HgC5AQAAAA==.',
Mi='Midnightstar:BAABLgAECn8VAAIZAAYJqxL5SgBQAQAZAAYJqxL5SgBQAQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAIAAAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.Miseree:BAAALgAECgcJBwAAAA==.',
Mo='Modest:BAAALgAECgQJBAAAAA==.Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgAECgEJAQAAAA==.Moonbayne:BAABLgAECn8qAAIHAAgJCRomFwD+AQAHAAgJCRomFwD+AQAAAA==.Mooszer:BAABLgAECn8bAAIEAAcJ0wOr4wC7AAAEAAcJ0wOr4wC7AAAAAA==.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBgAAAA==.Mushu:BAABLgAECn8tAAIiAAkJSBpeBQCvAgAiAAkJSBpeBQCvAgAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.Natre:BAAALgADCgIJAgAAAA==.',
Ne='Nepharim:BAAALgAECgYJCwAAAA==.Nephlim:BAACLgAFFH8ZAAMhAAYJWR9XHAC9AQAhAAUJWR9XHAC9AQAjAAEJAADlRQAAAAAuAAQKfzEAAiEACQnmIcQGAGwDACEACQnmIcQGAGwDAAAA.Nergal:BAAALgADCgMJAwAAAA==.',
Ni='Ninobrown:BAAALgAECgYJEwAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNwAYAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNwAYAG4gAA==.Nizano:BAABLgAECn8aAAIEAAcJ4AvTpAAVAQAEAAcJ4AvTpAAVAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAIAAAAAA==.Noryaa:BAABLgAECn8aAAIWAAYJpQWsowDcAAAWAAYJpQWsowDcAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.Notfurry:BAAALgAECgIJAgAAAA==.',
Nu='Nuadå:BAABLgAECn8gAAMZAAcJrw4nSwBPAQAZAAcJrw4nSwBPAQAHAAQJbgWMagB3AAAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECgcJDAAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAABLgAECn8RAAMaAAUJ9AoWTgCwAAAaAAUJ9AoWTgCwAAANAAQJ2wjETACTAAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAAALgADCgEJAQABLgAECggJHAAZABYiAA==.Orkid:BAAALgAECgEJAQAAAA==.',
Pa='Pawsome:BAAALgAECgQJBAABLgAECggJLAAQAEcXAA==.',
Ph='Phelyx:BAAALgAECgEJAgAAAA==.',
Po='Pogo:BAABLgAECn8fAAIUAAkJdiR9AgAbAwAUAAkJdiR9AgAbAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwAUAHYkAA==.',
Pr='Pricedd:BAAALgADCgcJBwAAAA==.Prosperina:BAAALgADCgQJBAAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8lAAMDAAgJdQgMGQDGAAABAAgJhgeQiwAZAQADAAYJvAoMGQDGAAAAAA==.',
Qu='Quetzani:BAAALgAECgEJAQAAAA==.',
Ra='Ranoa:BAAALgADCgkJCQAAAA==.Rastapopulos:BAAALgAECggJCgAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECgkJPgAWAPcdAA==.Redrocket:BAAALgAECgEJAgABLgAECgQJBwAIAAAAAA==.Remixed:BAAALgAECgMJAwAAAA==.Reptilectric:BAAALgAECgQJBAAAAA==.Retxd:BAAALgADCgEJAQABLgAECgQJBQAIAAAAAA==.',
Ri='Rikaku:BAABLgAECn8sAAIWAAcJvBHiPgCzAQAWAAcJvBHiPgCzAQAAAA==.',
Ro='Ronananna:BAAALgADCgkJDwABLgADCgYJBgAIAAAAAA==.Rosemery:BAAALgAECgYJBgAAAA==.',
['Rä']='Räpodac:BAABLgAECn8qAAIXAAcJlg2NJgAgAQAXAAcJlg2NJgAgAQAAAA==.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Saphil:BAAALgADCgkJFAAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Schizo:BAACLgAFFH8IAAIhAAIJtxqbswCQAAAhAAIJtxqbswCQAAAuAAQKfx0AAiEABwngIfNAADUCACEABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAgAAAA==.Sefiroth:BAACLgAFFH8FAAIMAAMJfwp/YQCnAAAMAAMJfwp/YQCnAAAuAAQKfy0AAgwABwmMFLpVAG0BAAwABwmMFLpVAG0BAAAA.Selillea:BAAALgAECgYJBwAAAA==.Semarius:BAAALgAECgEJAwABLgAECgkJNwAXAKQhAA==.Semdorii:BAABLgAECn83AAIXAAkJpCFOAwALAwAXAAkJpCFOAwALAwAAAA==.Sephywrath:BAABLgAECn8+AAIkAAkJoRulAQBhAgAkAAkJoRulAQBhAgAAAA==.Seralith:BAABLgAECn84AAIhAAkJCyU3AwBjAwAhAAkJCyU3AwBjAwAAAA==.Seranight:BAACLgAFFH8NAAMjAAQJtiRoCgCUAQAjAAQJtiRoCgCUAQAhAAEJJwFg+QAqAAAuAAQKf0IAAiMACQlgJnMAAHIDACMACQlgJnMAAHIDAAAA.Seven:BAAALgAECgIJBAABLgAECggJIQABAKEWAA==.Sevenpaws:BAAALgAECgYJCAABLgAECgkJQAANAHclAA==.',
Sh='Shadowchi:BAAALgAECgQJBQAAAA==.Shaidon:BAAALgAECgYJBgAAAQ==.Shaly:BAABLgAECn8jAAIYAAgJPwbHnwAhAQAYAAgJPwbHnwAhAQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shinjihirako:BAAALgAECgIJAgAAAA==.Shirohige:BAABLgAECn8UAAIfAAUJ1w8GNgCnAAAfAAUJ1w8GNgCnAAAAAA==.Shlonglord:BAAALgADCgIJAgAAAA==.Shylan:BAAALgAFFAEJAgAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDgAAAA==.',
Sn='Snayre:BAACLgAFFH8FAAIUAAIJKR3jHgC6AAAUAAIJKR3jHgC6AAAuAAQKfzUAAhQACQlxHrQEANUCABQACQlxHrQEANUCAAAA.Snipêr:BAABLgAECn8cAAIWAAgJtBMsPADXAQAWAAgJtBMsPADXAQAAAA==.Snowlia:BAACLgAFFH8HAAIPAAIJUxBdWAB3AAAPAAIJUxBdWAB3AAAuAAQKfxsAAw8ACAmZEvA1AKsBAA8ACAmZEvA1AKsBABAAAQk3D/SWAC0AAAAA.',
So='Soularis:BAAALgAECgYJCAAAAA==.Soulslice:BAEALgAECggJCAABLgAECgQJEQAIAAAAAA==.Sovrano:BAAALgADCgEJAQAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAAALgAECgcJEgAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJEAAAAA==.',
St='Stalkingwolf:BAABLgAECn8gAAIjAAcJ1xaHGgBvAQAjAAcJ1xaHGgBvAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgAECgYJCgAAAA==.',
Sy='Sylailia:BAACLgAFFH8FAAIHAAIJEgxSNQB1AAAHAAIJEgxSNQB1AAAuAAQKfzQAAgcACQliHIAKAJcCAAcACQliHIAKAJcCAAAA.Syleta:BAAALgADCgMJBAAAAA==.',
['Sí']='Síenna:BAAALgAECgEJAgAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAMJBAAIAAAAAA==.',
Tc='Tcon:BAABLgAECn8UAAIUAAcJRBWNHgCZAQAUAAcJRBWNHgCZAQAAAA==.',
Td='Tdragon:BAAALgADCgkJEgAAAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thissa:BAABLgAECn8uAAMHAAgJrx9ZDwBSAgAHAAgJrx9ZDwBSAgAgAAEJSBm4MwAzAAABLgAECggJGgAOANgYAA==.Thundarah:BAAALgADCgcJFwAAAA==.Thundruid:BAAALgADCgUJCgAAAA==.Thuniellas:BAAALgADCggJGQAAAA==.',
Ti='Tiarcis:BAABLgAECn8oAAIWAAkJXxJ/MAADAgAWAAkJXxJ/MAADAgAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Totemsalot:BAACLgAFFH8IAAIPAAQJYBjsJAAvAQAPAAQJYBjsJAAvAQAuAAQKfxkAAg8ACQkWIi4EAGEDAA8ACQkWIi4EAGEDAAAA.',
Tr='Treesummoner:BAABLgAECn8tAAQBAAkJjRg1JgA3AgABAAkJjRg1JgA3AgADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgADCggJCQAAAA==.Tritanks:BAABLgAECn86AAIJAAkJ+B2/AwB/AgAJAAkJ+B2/AwB/AgAAAA==.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAIAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAABLgAECn8UAAIaAAcJpgxvNwAVAQAaAAcJpgxvNwAVAQAAAA==.Valiente:BAAALgAECgIJAgAAAA==.Valkah:BAAALgAECgEJAQAAAA==.Vasilia:BAABLgAECn8tAAIjAAgJDhdtEwC/AQAjAAgJDhdtEwC/AQAAAA==.',
Ve='Velanna:BAAALgAECgIJAgAAAA==.Vexara:BAAALgADCgUJAgAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgAECgQJBgAAAA==.',
Vo='Voclus:BAAALgAECgYJEAAAAA==.',
Wa='Wall:BAAALgAECgYJEAAAAA==.Warlodshenu:BAAALgADCgYJBgAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wuwindtang:BAAALgAECgUJDAAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgADCgMJAwAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAIKAAYJqQWIYQC2AAAKAAYJqQWIYQC2AAAAAA==.Xiletank:BAAALgAECgUJBQAAAA==.',
Za='Zachxd:BAABLgAECn84AAIMAAcJ6RlYSwCMAQAMAAcJ6RlYSwCMAQABLgAFFAIJCAAhALcaAA==.Zanthe:BAAALgAECgQJCwAAAA==.Zapanese:BAAALgADCgMJBAAAAA==.Zapt:BAAALgAECgIJAgAAAA==.Zaptism:BAABLgAECn8xAAMNAAkJVB9XCwCaAgANAAkJVB9XCwCaAgAOAAUJZgzlQwDMAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgADCgkJJgAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgYJEAABLgAFFAIJBwAJAB4VAA==.Zhanbear:BAAALgADCgcJDAABLgAFFAIJBwAJAB4VAA==.Zhanbrew:BAACLgAFFH8FAAIcAAIJjhNLPwCIAAAcAAIJjhNLPwCIAAAuAAQKfxwAAhwACAlfHfMMAFQCABwACAlfHfMMAFQCAAEuAAUUAgkHAAkAHhUA.Zhanfury:BAAALgAFFAEJAQABLgAFFAIJBwAJAB4VAA==.',
Zi='Zinder:BAABLgAECn8nAAMlAAgJTQiIRAD2AAAlAAgJTQiIRAD2AAAmAAEJLANlJwAhAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJjRerBAAWAgADAAkJjRerBAAWAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECggJGgAfALsWAA==.',
['Öb']='Öboron:BAACLgAFFH8JAAMUAAQJVgOPGAD0AAAUAAQJVgOPGAD0AAAVAAEJywGTMQAsAAAuAAQKfy4ABBQACQmMFxoNAEcCABQACQknFhoNAEcCABUACAlWECgqANoBABYABgkpFTJTAG8BAAAA.',
['Üz']='Üz:BAABLgAECn8kAAIXAAgJvhYNFQDDAQAXAAgJvhYNFQDDAQAAAA==.',
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
