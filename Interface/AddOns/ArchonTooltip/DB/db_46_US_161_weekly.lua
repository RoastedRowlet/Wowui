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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Warrior-Fury','Warrior-Protection','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Monk-Mistweaver','DeathKnight-Frost','Paladin-Holy','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Shaman-Enhancement','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Addely:BAAALgAECgYJBgAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgUJDAAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRqucACbAQAEAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJEQAAAA==.',
Al='Alerion:BAABLgAECn8sAAIFAAkJKhnGCwBcAgAFAAkJKhnGCwBcAgAAAA==.Allan:BAABLgAECn8rAAIGAAkJbiHvAADIAgAGAAkJbiHvAADIAgAAAA==.Alligatorjoe:BAAALgADCgEJAQAAAA==.',
Am='Amaneeda:BAABLgAECn8zAAIHAAgJIxBnKAB/AQAHAAgJIxBnKAB/AQAAAA==.Amazonia:BAAALgAECgQJBQAAAA==.Aminea:BAAALgAFFAIJAgAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAIAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8HAAIJAAIJHhVnCwB5AAAJAAIJHhVnCwB5AAAuAAQKfy8AAgkACAkhIpEDAJICAAkACAkhIpEDAJICAAAA.Angyrain:BAAALgAECgUJBgABLgAFFAIJBwAJAB4VAA==.Annerila:BAAALgAECgEJAQAAAA==.Antagonis:BAABLgAECn8cAAIDAAcJPw//EQAaAQADAAcJPw//EQAaAQAAAA==.',
Ap='Apexchi:BAAALgAECgYJEAAAAA==.Apeximmortal:BAAALgAECgkJCwAAAA==.Apexlight:BAAALgAECgkJEQAAAA==.Apexwar:BAAALgAECgEJAQAAAA==.',
Ar='Arashe:BAAALgAECgUJDAAAAA==.Arewen:BAAALgADCggJEQAAAA==.Arganos:BAABLgAECn8wAAMKAAkJtSZ/AQBlAwAKAAkJtSZ/AQBlAwALAAYJFxu9FwB3AQAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8WAAIMAAcJ6wTqsgC0AAAMAAcJ6wTqsgC0AAAAAA==.Arkstrife:BAAALgADCgEJAQAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgADCgkJOwAAAA==.Atheîst:BAABLgAECn9AAAMNAAkJdyXMAQBaAwANAAkJdyXMAQBaAwAOAAYJCyOdEABcAgAAAA==.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn9JAAMPAAkJaR/DFwB/AgAPAAgJ9B7DFwB/AgAQAAgJiBsaFQAyAgAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAYJFAAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJMAAKALUmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8cAAMRAAcJuRpEFACzAQARAAcJuRpEFACzAQAKAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8fAAISAAYJ9RW0OQByAQASAAYJ9RW0OQByAQAAAA==.Baelanoth:BAABLgAECn8tAAITAAgJgR57BQBOAgATAAgJgR57BQBOAgAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balerion:BAAALgAECgEJAQAAAA==.Balkazaar:BAAALgAECggJEQAAAA==.Bammbamm:BAABLgAECn8tAAIEAAgJQQlZmgA1AQAEAAgJQQlZmgA1AQAAAA==.Banewreak:BAACLgAFFH8FAAIBAAEJ7BGrtgBGAAABAAEJ7BGrtgBGAAAuAAQKfzgAAgEACQnCF28jAE0CAAEACQnCF28jAE0CAAAA.Banu:BAAALgAECgEJAQAAAA==.Baradin:BAABLgAECn8UAAIUAAcJGBVxJgDLAQAUAAcJGBVxJgDLAQAAAA==.Barind:BAABLgAECn8yAAQVAAkJFh0oCACXAgAVAAkJmRwoCACXAgAWAAcJIxqYJAADAgAXAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgQJBwAAAA==.Betrayer:BAACLgAFFH8IAAIYAAMJ+R26EAAKAQAYAAMJ+R26EAAKAQAuAAQKfyIAAhgACQnuIaUDAA0DABgACQnuIaUDAA0DAAAA.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAAALgAECggJEAAAAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Biqdonk:BAAALgAECgUJDAAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.Bloodhornz:BAAALgAECgEJAQAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDQABLgADCgYJCwAIAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAIAAAAAA==.Bossdwarf:BAAALgADCgcJCwABLgADCgYJCwAIAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleosévèn:BAAALgAECgQJBAABLgAECgkJQAANAHclAA==.',
['Bú']='Búbblés:BAAALgAECgcJDQAAAA==.',
Ca='Caatia:BAAALgAECggJCgAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgkJIwABAAwVAA==.Carthel:BAABLgAECn8fAAIZAAgJMiBYMQCtAgAZAAgJMiBYMQCtAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCggJDgAAAA==.',
Ce='Cerisi:BAAALgAECgEJAQAAAA==.Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Charley:BAAALgAECgYJCQAAAA==.Chasseresse:BAAALgAECgQJBQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chi:BAAALgAECgEJAQAAAA==.Chimarr:BAABLgAECn8cAAIaAAgJFiLNDwDMAgAaAAgJFiLNDwDMAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Co='Coldsploder:BAABLgAECn8tAAIZAAkJWhe8MABPAgAZAAkJWhe8MABPAgAAAA==.',
Cr='Crackmonkéy:BAABLgAECn8aAAQOAAgJ2BjMKAB/AQAOAAcJNBTMKAB/AQANAAQJkRlWTwD7AAAbAAQJdBA4QQDvAAABLgAFFAMJAwAIAAAAAA==.Cranknspank:BAAALgAECgYJBwAAAA==.Cronoz:BAABLgAECn8mAAMQAAkJbgujQAAhAQAQAAgJ0wmjQAAhAQAPAAgJUAfbWQAhAQAAAA==.Crotchshot:BAABLgAECn8kAAIXAAgJ8xBuTgCrAQAXAAgJ8xBuTgCrAQAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Culodevour:BAAALgAECgYJBgAAAA==.Cursess:BAACLgAFFH8OAAIBAAMJeSB4TAAgAQABAAMJeSB4TAAgAQAuAAQKfzUAAgEACQlxItALAOoCAAEACQlxItALAOoCAAAA.',
['Có']='Cózmik:BAABLgAECn8UAAIXAAcJ3RbaVgCSAQAXAAcJ3RbaVgCSAQAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn8zAAIBAAgJhBWoOwDnAQABAAgJhBWoOwDnAQAAAA==.Dalya:BAAALgAECggJCgAAAA==.Dander:BAAALgADCgMJAwAAAA==.Dani:BAAALgAECgEJAgABLgAECgQJBQAIAAAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkridder:BAAALgAECgEJAQAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAAALgAECgYJEwAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deathratellr:BAAALgADCgEJAQAAAA==.Deemaius:BAAALgAECgEJAQAAAA==.Dekard:BAAALgAECggJEQAAAA==.Dekariusly:BAAALgAECgQJBAABLgAECggJEQAIAAAAAA==.Demonatrixx:BAAALgAECgYJCQAAAA==.Demonhugger:BAAALgAECgEJAgABLgAECgUJBQAIAAAAAA==.Demonkila:BAAALgAECgIJAgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHwACAFwZAA==.Destinÿ:BAABLgAECn8lAAILAAgJPRfuFQCLAQALAAgJPRfuFQCLAQAAAA==.Devourer:BAABLgAECn8uAAIMAAgJGBt3KQAZAgAMAAgJGBt3KQAZAgAAAA==.',
Di='Disploder:BAABLgAECn8sAAINAAgJdBQoHQDOAQANAAgJdBQoHQDOAQAAAA==.Dist:BAAALgAECgkJDgAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.Dommiemommie:BAAALgAECgIJAgAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJAQABLgAECgEJAgAIAAAAAA==.Drawwn:BAAALgAECgEJAgAAAA==.Dreathhammer:BAABLgAECn8uAAIUAAkJ1SJNAwBlAwAUAAkJ1SJNAwBlAwAAAA==.Drogo:BAAALgAFFAMJAwAAAA==.Drureds:BAAALgAECgMJBQAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAgJJQAUAIIgAA==.',
Du='Duckcox:BAAALgAECgQJBwAAAA==.Dunadin:BAABLgAECn8WAAQSAAYJ/RmcLgCrAQASAAYJ/RmcLgCrAQAcAAIJ4xLZZQB1AAAdAAEJthWhiAA/AAABLgAECgkJPQAJAK4mAA==.Dundyrn:BAABLgAECn89AAIJAAkJriYnAAB2AwAJAAkJriYnAAB2AwAAAA==.',
Dv='Dvera:BAAALgADCgMJAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECgkJPQAJAK4mAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAYJEAALAOkbAA==.',
Ed='Edmunin:BAEALgAECgYJAwABLgAECgcJAQAIAAAAAA==.',
El='Elememetal:BAABLgAECn8oAAIQAAkJvxhPGgACAgAQAAkJvxhPGgACAgAAAA==.Elfyparker:BAAALgAECgEJAQAAAA==.Elliott:BAAALgADCgIJAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Fa='Fanmir:BAAALgAECgEJAQAAAA==.Fatpao:BAAALgAECgYJDAAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAIPAAcJXQs/WQAjAQAPAAcJXQs/WQAjAQAAAA==.Fenix:BAAALgADCgEJAgABLgAECggJLQAbAI8UAA==.',
Fi='Filbert:BAABLgAECn8dAAIHAAkJUyHRBgDhAgAHAAkJUyHRBgDhAgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Foldyholds:BAAALgAECgEJAQAAAA==.Fomy:BAAALgAECgEJAQABLgAFFAMJBQAHAL8FAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDgAIAAAAAA==.',
Fr='Fraw:BAAALgADCggJDAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAwAAAA==.Fuzzyhunter:BAAALgAECgEJAQABLgAECggJLQAbAI8UAA==.',
['Fá']='Fálola:BAABLgAECn88AAMPAAgJrxffKADsAQAPAAgJrxffKADsAQAQAAYJwwMAagCZAAAAAA==.',
Ga='Galestina:BAAALgAECgQJBAAAAA==.Gamblex:BAAALgAECgUJDgAAAA==.Garviel:BAABLgAECn8fAAIRAAgJRRuOCwAjAgARAAgJRRuOCwAjAgAAAA==.',
Ge='Geeplague:BAAALgADCgMJAwABLgAECggJGQABABMWAA==.Geethatlock:BAABLgAECn8ZAAIBAAgJExYrRADJAQABAAgJExYrRADJAQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAABLgAECn8iAAIWAAYJSRduDwBWAQAWAAYJSRduDwBWAQAAAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgAECgEJAQAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAABLgAECn8bAAIPAAgJ8Rs8HgBPAgAPAAgJ8Rs8HgBPAgAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grogu:BAABLgAECn8eAAIZAAcJBQpCqgAlAQAZAAcJBQpCqgAlAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJBAAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAFFAMJBAAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgcJBwAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECgkJLgAeAL0fAA==.Hiksham:BAABLgAECn8uAAMeAAkJvR/CBACWAgAeAAkJnB/CBACWAgAQAAgJBw1GOABHAQAAAA==.',
Ho='Holycheeze:BAAALgADCgcJCgAAAA==.Holyhoof:BAAALgAECgEJAQAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgkJIwABAAwVAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgcJGQAPAGwVAA==.',
Ia='Iamreggi:BAAALgAECgQJBgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8tAAIbAAgJjxSwHgDIAQAbAAgJjxSwHgDIAQAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Im:BAAALgAECgEJAQAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
Ir='Irisi:BAAALgADCgUJBQAAAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECggJIAAfAMwWAA==.Jarlyss:BAABLgAECn8gAAIfAAgJzBb6EADJAQAfAAgJzBb6EADJAQAAAA==.Javieraa:BAABLgAECn8gAAIMAAkJYRrOIwA1AgAMAAkJYRrOIwA1AgAAAA==.',
Jd='Jdai:BAABLgAECn8ZAAIPAAcJbBWHOQC7AQAPAAcJbBWHOQC7AQAAAA==.',
Jo='Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAAALgAECgcJEAAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgAECgIJAgAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8cAAIMAAcJaB4IEAARAgAMAAcJaB4IEAARAgAuAAQKf0MAAgwACQlkJCoEADwDAAwACQlkJCoEADwDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn8zAAIYAAgJaQ5PIgBSAQAYAAgJaQ5PIgBSAQAAAA==.Kikyo:BAAALgAECgYJEgAAAA==.Kimmi:BAAALgAECgUJDAAAAA==.Kinzen:BAABLgAECn8xAAIeAAcJhSC9DADYAQAeAAcJhSC9DADYAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIgAAYJAyEjDQDmAQAgAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8jAAIZAAgJPArbhwBhAQAZAAgJPArbhwBhAQAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgAECgIJAgABLgAECgkJOwAOADYdAA==.',
Le='Lechwe:BAABLgAECn8vAAIPAAgJhxtnFgCKAgAPAAgJhxtnFgCKAgAAAA==.Legonator:BAAALgAECgUJCAAAAA==.Lenry:BAAALgAFFAEJAQAAAA==.',
Li='Lichmajor:BAABLgAECn8nAAIhAAkJ6BhSQwDxAQAhAAkJ6BhSQwDxAQAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.Littlefang:BAAALgAECgQJBAAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn8iAAISAAcJICGZEwBtAgASAAcJICGZEwBtAgAAAA==.Lovepet:BAABLgAECn8/AAMXAAkJ9x1nFwCPAgAXAAkJ9x1nFwCPAgAWAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAAALgAECgYJCgAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn83AAIZAAkJbiC+HwCaAgAZAAkJbiC+HwCaAgAAAA==.Lunavis:BAAALgAECgcJCAABLgAECgkJGgAaAPUNAA==.',
Ly='Lyda:BAABLgAECn8zAAIaAAgJfhufGQBwAgAaAAgJfhufGQBwAgAAAA==.',
Ma='Magice:BAABLgAECn8XAAIZAAUJ+wIYDAGNAAAZAAUJ+wIYDAGNAAAAAA==.Magmara:BAAALgADCgkJEgAAAA==.Malibubarbie:BAABLgAECn8sAAINAAgJXw8aJgCGAQANAAgJXw8aJgCGAQAAAA==.Malthael:BAAALgAECgEJAQAAAA==.Malystron:BAABLgAECn8UAAIEAAkJ/woodQB5AQAEAAkJ/woodQB5AQAAAA==.Maneevent:BAABLgAECn8ZAAQXAAYJGReIfwAyAQAXAAYJGReIfwAyAQAVAAEJ1wTOZAAsAAAWAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn87AAMOAAkJNh3zBgAEAwAOAAkJNh3zBgAEAwAbAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn8+AAIXAAkJFgo9TQCuAQAXAAkJFgo9TQCuAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8WAAQgAAYJvRsRAgCwAQAgAAUJTxsRAgCwAQAHAAIJfB2EQQBWAAAfAAEJhxPoBgA6AAAuAAQKfyoABCAACQkiIwwCAAsDACAACQkiIwwCAAsDAB8AAQkxIY0pAFQAAAcAAQkqFUp9AEEAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn8zAAINAAkJfQ/WHwC2AQANAAkJfQ/WHwC2AQAAAA==.',
Mi='Midnightstar:BAABLgAECn8VAAIaAAYJqxJnTQBPAQAaAAYJqxJnTQBPAQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAIAAAAAA==.Mimolette:BAAALgADCgUJBQAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.Miseree:BAAALgAECgcJBwAAAA==.',
Mo='Modest:BAAALgAECgUJBQAAAA==.Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgAECgEJAQAAAA==.Moonbayne:BAABLgAECn8rAAIHAAgJGhr4FwABAgAHAAgJGhr4FwABAgAAAA==.Mooszer:BAABLgAECn8eAAIEAAgJWwSUzwDmAAAEAAgJWwSUzwDmAAAAAA==.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBwAAAA==.Mushu:BAABLgAECn8tAAIiAAkJSBqrBQCvAgAiAAkJSBqrBQCvAgAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.Natre:BAAALgADCgIJAgAAAA==.',
Ne='Nepharim:BAAALgAECgYJCwAAAA==.Nephlim:BAACLgAFFH8aAAMhAAcJFB9jFAASAgAhAAYJFB9jFAASAgAjAAEJAAD5TAAAAAAuAAQKfzEAAiEACQnmIcQGAGwDACEACQnmIcQGAGwDAAAA.Nergal:BAAALgADCgMJAwAAAA==.',
Ni='Ninobrown:BAAALgAECgYJEwAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNwAZAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNwAZAG4gAA==.Nizano:BAABLgAECn8eAAIEAAcJHgzwqQAcAQAEAAcJHgzwqQAcAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAIAAAAAA==.Noryaa:BAABLgAECn8fAAIXAAYJQwYnpADqAAAXAAYJQwYnpADqAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.Notfurry:BAAALgAECgIJAgAAAA==.',
Nu='Nuadå:BAABLgAECn8kAAMaAAcJHxHeRQBuAQAaAAcJHxHeRQBuAQAHAAQJbgWMagB3AAAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECggJDQAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAABLgAECn8UAAMbAAUJJBFcRQDwAAAbAAUJJBFcRQDwAAANAAQJ2wjNTwCPAAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAAALgADCgEJAQABLgAECggJHAAaABYiAA==.Orkid:BAAALgAECgEJAQAAAA==.',
Pa='Pawsome:BAAALgAECgQJBAABLgAECggJMQAQALIXAA==.',
Ph='Phelyx:BAAALgAFFAIJAgAAAA==.',
Po='Pogo:BAABLgAECn8fAAIVAAkJdiR9AgAbAwAVAAkJdiR9AgAbAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwAVAHYkAA==.',
Pr='Pricedd:BAAALgADCgcJCAAAAA==.Prosperina:BAAALgADCgQJBAAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8lAAMDAAgJdQjYGgDEAAABAAgJhgdtkQAUAQADAAYJvArYGgDEAAAAAA==.',
Qu='Quetzani:BAAALgAECgEJAQAAAA==.',
Ra='Ranoa:BAAALgADCgkJCQAAAA==.Rastapopulos:BAAALgAECggJCgAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECgkJPwAXAPcdAA==.Redrocket:BAAALgAECgEJAgABLgAECgQJBwAIAAAAAA==.Remixed:BAAALgAECgMJAwAAAA==.Reptilectric:BAAALgAECgUJCAAAAA==.Retxd:BAAALgADCgEJAQABLgAECgQJBQAIAAAAAA==.',
Ri='Rikaku:BAABLgAECn8uAAIXAAcJ6xHiPgCzAQAXAAcJ6xHiPgCzAQAAAA==.',
Ro='Roastbeef:BAAALgAECgEJAQAAAA==.Ronananna:BAAALgADCgkJDwABLgADCgYJBgAIAAAAAA==.Rosemery:BAAALgAECgYJBwAAAA==.',
['Rä']='Räpodac:BAABLgAECn8qAAIYAAcJlg2aKQAdAQAYAAcJlg2aKQAdAQAAAA==.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Saphil:BAAALgADCgkJFAAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Schizo:BAACLgAFFH8JAAIhAAIJtxqNvwCTAAAhAAIJtxqNvwCTAAAuAAQKfx0AAiEABwngIfNAADUCACEABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAgAAAA==.Sefiroth:BAACLgAFFH8FAAIMAAMJfwqTagCgAAAMAAMJfwqTagCgAAAuAAQKfy4AAgwABwnTFSNXAHUBAAwABwnTFSNXAHUBAAAA.Selillea:BAAALgAECgYJBwAAAA==.Semarius:BAAALgAECgEJAwABLgAECgkJNwAYAKQhAA==.Semdorii:BAABLgAECn83AAIYAAkJpCH/AwADAwAYAAkJpCH/AwADAwAAAA==.Sephywrath:BAABLgAECn8+AAIkAAkJoRv7AQBMAgAkAAkJoRv7AQBMAgAAAA==.Seralith:BAABLgAECn9BAAIhAAkJkyWdAgByAwAhAAkJkyWdAgByAwAAAA==.Seranight:BAACLgAFFH8QAAMjAAQJtiQaDQCMAQAjAAQJtiQaDQCMAQAhAAEJJwH/DQEpAAAuAAQKf0MAAiMACQl8JnwAAHQDACMACQl8JnwAAHQDAAAA.Seven:BAAALgAECgIJBAABLgAECgkJIwABAAwVAA==.Sevenpaws:BAAALgAECgYJCAABLgAECgkJQAANAHclAA==.',
Sh='Shadowchi:BAAALgAECgQJBQAAAA==.Shaidon:BAAALgAECgYJBgAAAQ==.Shaly:BAABLgAECn8jAAIZAAgJPwYyoAA2AQAZAAgJPwYyoAA2AQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shinjihirako:BAAALgAECgQJBAAAAA==.Shirohige:BAABLgAECn8XAAIfAAUJ1w/fOgCmAAAfAAUJ1w/fOgCmAAAAAA==.Shlonglord:BAAALgADCgIJAgAAAA==.Shylan:BAAALgAFFAEJAwAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDgAAAA==.',
Sn='Snaarf:BAAALgADCgEJAQABLgAECgUJFAAlANIDAA==.Snayre:BAACLgAFFH8IAAIVAAMJ1hlHGAD8AAAVAAMJ1hlHGAD8AAAuAAQKfzUAAhUACQlxHk4FAM4CABUACQlxHk4FAM4CAAAA.Snipêr:BAABLgAECn8cAAIXAAgJtBMAQgDQAQAXAAgJtBMAQgDQAQAAAA==.Snowlia:BAACLgAFFH8JAAIPAAMJahOJSgCwAAAPAAMJahOJSgCwAAAuAAQKfyEAAw8ACQkxE/A1AKsBAA8ACQkxE/A1AKsBABAAAQk3D/+eACwAAAAA.',
So='Soularis:BAAALgAECgYJCAAAAA==.Soulslice:BAEALgAECggJCAABLgAECgQJEQAIAAAAAA==.Sovrano:BAAALgADCgEJAQAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAABLgAECn8WAAMmAAcJqAb6EADtAAAmAAcJqAb6EADtAAAiAAEJ6gF9QgAbAAAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJEAAAAA==.',
St='Stalkingwolf:BAABLgAECn8kAAIjAAcJFRfAGQCGAQAjAAcJFRfAGQCGAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgAECgYJEAAAAA==.',
Sy='Sylailia:BAACLgAFFH8IAAIHAAMJKAtOMACrAAAHAAMJKAtOMACrAAAuAAQKfzQAAgcACQliHJYLAJECAAcACQliHJYLAJECAAAA.Syleta:BAAALgADCgMJBAAAAA==.',
['Sí']='Síenna:BAAALgAECgEJAgAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAMJBAAIAAAAAA==.',
Tc='Tcon:BAABLgAECn8UAAIVAAcJRBUbIACXAQAVAAcJRBUbIACXAQAAAA==.',
Td='Tdragon:BAAALgADCgkJEgABLgAECggJLQAbAI8UAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thissa:BAABLgAECn8uAAMHAAgJrx9REABQAgAHAAgJrx9REABQAgAgAAEJSBm4MwAzAAABLgAFFAMJAwAIAAAAAA==.Thundarah:BAAALgADCgcJFwAAAA==.Thundruid:BAAALgADCgUJCgAAAA==.Thuniellas:BAAALgADCggJGQAAAA==.',
Ti='Tiarcis:BAABLgAECn8xAAIXAAkJbBh/HwBfAgAXAAkJbBh/HwBfAgAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Tostitos:BAAALgADCgkJCQABLgAECggJLQAbAI8UAA==.Totemsalot:BAACLgAFFH8MAAIPAAQJjBsNJQA6AQAPAAQJjBsNJQA6AQAuAAQKfxsAAg8ACQnGIzIDAIYDAA8ACQnGIzIDAIYDAAAA.',
Tr='Treesummoner:BAABLgAECn8tAAQBAAkJjRjPKAAyAgABAAkJjRjPKAAyAgADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgADCggJCQAAAA==.Tritanks:BAABLgAECn86AAIJAAkJ+B1IBAByAgAJAAkJ+B1IBAByAgAAAA==.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAIAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAABLgAECn8UAAIbAAcJpgxDOAAqAQAbAAcJpgxDOAAqAQAAAA==.Valiente:BAAALgAECgIJAgAAAA==.Valkah:BAAALgAECgEJAQAAAA==.Vasilia:BAABLgAECn8zAAIjAAgJsBdHEgDeAQAjAAgJsBdHEgDeAQAAAA==.',
Ve='Velanna:BAAALgAECgIJAgAAAA==.Vexara:BAAALgAECgEJAgAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgAFFAEJAQAAAA==.',
Vo='Voclus:BAAALgAECgYJEgAAAA==.',
Wa='Wall:BAAALgAECgYJEwAAAA==.Warlodshenu:BAAALgADCgYJBgAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
We='Weyaeh:BAAALgADCgIJAgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wuwindtang:BAAALgAECgUJDAAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgADCgMJAwAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAIKAAYJqQV7ZgC2AAAKAAYJqQV7ZgC2AAAAAA==.Xiletank:BAAALgAECgUJBQAAAA==.',
Za='Zachxd:BAABLgAECn84AAIMAAcJ6RkmTgCPAQAMAAcJ6RkmTgCPAQABLgAFFAIJCQAhALcaAA==.Zanthe:BAAALgAECgQJDgAAAA==.Zapanese:BAAALgADCgMJBAAAAA==.Zapt:BAAALgAECgIJAgAAAA==.Zaptism:BAABLgAECn85AAMNAAkJMCGDBwDrAgANAAkJMCGDBwDrAgAOAAUJhQ7jQgDuAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgADCgkJJgAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgYJEAABLgAFFAIJBwAJAB4VAA==.Zhanbear:BAAALgAECgUJBQABLgAFFAIJBwAJAB4VAA==.Zhanbrew:BAACLgAFFH8IAAIcAAMJhh0jJwACAQAcAAMJhh0jJwACAQAuAAQKfyIAAhwACQkRISYEAAADABwACQkRISYEAAADAAEuAAUUAgkHAAkAHhUA.Zhanfury:BAAALgAFFAEJAQABLgAFFAIJBwAJAB4VAA==.',
Zi='Zinder:BAABLgAECn8nAAMlAAgJTQh0RQAJAQAlAAgJTQh0RQAJAQAmAAEJLANCKQAhAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJjRcoBQASAgADAAkJjRcoBQASAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECggJIAAfAMwWAA==.',
['Öb']='Öboron:BAACLgAFFH8JAAMVAAQJVgNkGwDjAAAVAAQJVgNkGwDjAAAWAAEJywHGNgAsAAAuAAQKfy4ABBUACQmMFxMOAEQCABUACQknFhMOAEQCABYACAlWECgqANoBABcABgkpFTJTAG8BAAAA.',
['Üz']='Üz:BAABLgAECn8kAAIYAAgJvhbZFgC/AQAYAAgJvhbZFgC/AQAAAA==.',
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
