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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Hunter-Marksmanship','Unknown-Unknown','DemonHunter-Vengeance','Warrior-Fury','Warrior-Protection','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Monk-Mistweaver','DeathKnight-Frost','Paladin-Holy','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','Druid-Restoration','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Shaman-Enhancement','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Addely:BAAALgAECgYJCAAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgUJDwAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRqucACbAQAEAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJEQAAAA==.',
Al='Alerion:BAABLgAECn8sAAIFAAkJKhmQDABaAgAFAAkJKhmQDABaAgAAAA==.Allan:BAABLgAECn8rAAIGAAkJbiH9AADFAgAGAAkJbiH9AADFAgAAAA==.Alligatorjoe:BAAALgADCgEJAQAAAA==.',
Am='Amaneeda:BAABLgAECn80AAIHAAgJIxAiKgB/AQAHAAgJIxAiKgB/AQAAAA==.Amazonia:BAABLgAECn8ZAAIIAAYJ9hYBEQBGAQAIAAYJ9hYBEQBGAQAAAA==.Aminea:BAAALgAFFAIJBAAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAJAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8HAAIKAAIJHhWVDAB3AAAKAAIJHhWVDAB3AAAuAAQKfy8AAgoACAkhItoDAJECAAoACAkhItoDAJECAAAA.Angyrain:BAAALgAECgUJBgABLgAFFAIJBwAKAB4VAA==.Annerila:BAAALgAECgEJAQAAAA==.Antagonis:BAABLgAECn8hAAIDAAcJSA/XEgAZAQADAAcJSA/XEgAZAQAAAA==.',
Ap='Apexchi:BAAALgAECgYJEQAAAA==.Apeximmortal:BAAALgAECgkJDAAAAA==.Apexlight:BAAALgAECgkJEQAAAA==.Apexwar:BAAALgAECgEJAQAAAA==.',
Ar='Arashe:BAAALgAECgUJEAAAAA==.Arewen:BAAALgADCggJEQAAAA==.Arganos:BAABLgAECn8wAAMLAAkJtSbGAQBgAwALAAkJtSbGAQBgAwAMAAYJFxvSGAB0AQAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8WAAINAAcJ6wQiuQC0AAANAAcJ6wQiuQC0AAAAAA==.Arkstrife:BAAALgADCgEJAQAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgADCgkJOwAAAA==.Atheîst:BAABLgAECn9EAAMOAAkJdyXMAQBaAwAOAAkJdyXMAQBaAwAPAAgJfCInBgAeAwAAAA==.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn9KAAMQAAkJaR8cGQB+AgAQAAgJ9B4cGQB+AgARAAgJiBs8FgAxAgAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAYJFAAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJMAALALUmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8cAAMSAAcJuRotFQCwAQASAAcJuRotFQCwAQALAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8fAAITAAYJ9RUgPQBzAQATAAYJ9RUgPQBzAQAAAA==.Baelanoth:BAABLgAECn8uAAIUAAgJgR75BQBKAgAUAAgJgR75BQBKAgAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balerion:BAAALgAECgEJAgAAAA==.Balkazaar:BAAALgAECggJEQAAAA==.Bammbamm:BAABLgAECn8vAAIEAAgJOwp2mABBAQAEAAgJOwp2mABBAQAAAA==.Banewreak:BAACLgAFFH8IAAIBAAMJmAsWfQDFAAABAAMJmAsWfQDFAAAuAAQKfzgAAgEACQnCF50lAEYCAAEACQnCF50lAEYCAAAA.Banu:BAAALgAECgEJAQAAAA==.Baradin:BAABLgAECn8UAAIVAAcJGBXcJwDKAQAVAAcJGBXcJwDKAQAAAA==.Barind:BAABLgAECn8yAAQWAAkJFh23CACSAgAWAAkJmRy3CACSAgAIAAcJIxqYJAADAgAXAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgQJCAAAAA==.Betrayer:BAACLgAFFH8MAAIYAAQJTRqXCwBNAQAYAAQJTRqXCwBNAQAuAAQKfyIAAhgACQnuIREEAAkDABgACQnuIREEAAkDAAAA.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAAALgAECggJEgABLgAECgkJHgAQAJcNAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Bignfugly:BAAALgADCgYJBgABLgAECgYJHAARAAkaAA==.Biqdonk:BAAALgAECgUJDAAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.Bloodhornz:BAAALgAECgEJAgAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDQABLgADCgYJCwAJAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAJAAAAAA==.Bossdwarf:BAAALgADCgcJCwABLgADCgYJCwAJAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleosévèn:BAAALgAECgcJCQABLgAECgkJRAAOAHclAA==.Buddro:BAAALgAECgEJAQAAAA==.',
['Bú']='Búbblés:BAAALgAECgcJDQAAAA==.',
Ca='Caatia:BAAALgAECggJCgAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgkJIwABAAwVAA==.Carthel:BAABLgAECn8fAAIZAAgJMiBYMQCtAgAZAAgJMiBYMQCtAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCggJDgAAAA==.',
Ce='Cerisi:BAAALgAECgEJAQAAAA==.Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Charley:BAAALgAECgYJCwAAAA==.Chasseresse:BAABLgAECn8ZAAIXAAYJzBWWcQBYAQAXAAYJzBWWcQBYAQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chi:BAAALgAECgEJAgAAAA==.Chimarr:BAABLgAECn8cAAIaAAgJFiJ7EADLAgAaAAgJFiJ7EADLAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Cm='Cmondie:BAAALgAECgQJBAAAAA==.',
Co='Coldsploder:BAACLgAFFH8GAAIZAAMJ4gY0igDJAAAZAAMJ4gY0igDJAAAuAAQKfy0AAhkACQlaFw0zAEoCABkACQlaFw0zAEoCAAAA.',
Cr='Crackmonkéy:BAACLgAFFH8FAAIPAAMJPQtfMwC4AAAPAAMJPQtfMwC4AAAuAAQKfxoABA8ACAnYGH4qAH8BAA8ABwk0FH4qAH8BAA4ABAmRGVZPAPsAABsABAl0EDhBAO8AAAEuAAUUBAkEAAkAAAAA.Cranknspank:BAAALgAECgYJBwAAAA==.Cronoz:BAABLgAECn8mAAMQAAkJMQrbWQAhAQAQAAgJUAfbWQAhAQARAAgJ0wmcQwAhAQAAAA==.Crotchshot:BAABLgAECn8mAAIXAAkJnhIANQAFAgAXAAkJnhIANQAFAgAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Culodevour:BAAALgAECgYJCAAAAA==.Cursess:BAACLgAFFH8RAAIBAAMJVSLbSQAuAQABAAMJVSLbSQAuAQAuAAQKfzUAAgEACQlxIrsMAOYCAAEACQlxIrsMAOYCAAAA.',
['Có']='Cózmik:BAABLgAECn8UAAIXAAcJ3RYlWwCPAQAXAAcJ3RYlWwCPAQAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn82AAIBAAkJnhRoLQAhAgABAAkJnhRoLQAhAgAAAA==.Dalya:BAAALgAFFAMJAwAAAA==.Dander:BAAALgAECgEJAQAAAA==.Dani:BAAALgAECgEJAgABLgAECgQJBQAJAAAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkridder:BAAALgAECgEJAQAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAABLgAECn8UAAIaAAYJnB0LKwD9AQAaAAYJnB0LKwD9AQAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deathratellr:BAAALgADCgEJAQAAAA==.Deemaius:BAAALgAECgEJAQAAAA==.Dekard:BAAALgAECggJEwAAAA==.Dekariusly:BAAALgAECgQJBAABLgAECggJEwAJAAAAAA==.Demonatrixx:BAAALgAECgYJCQAAAA==.Demonhugger:BAAALgAECgEJAgABLgAECgUJBQAJAAAAAA==.Demonkila:BAAALgAECgUJBgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHwACAFwZAA==.Destinÿ:BAABLgAECn8lAAIMAAgJPRc+FwCFAQAMAAgJPRc+FwCFAQAAAA==.Devourer:BAABLgAECn82AAINAAgJRhsKKgAeAgANAAgJRhsKKgAeAgAAAA==.',
Di='Disploder:BAABLgAECn8sAAIOAAgJdBR4HgDMAQAOAAgJdBR4HgDMAQAAAA==.Dist:BAAALgAECgkJDgAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.Dommiemommie:BAAALgAECgIJAgAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJAQABLgAECgEJAgAJAAAAAA==.Drawwn:BAAALgAECgEJAgAAAA==.Dreathhammer:BAABLgAECn8uAAIVAAkJ1SKiAwBjAwAVAAkJ1SKiAwBjAwAAAA==.Drogo:BAAALgAFFAQJBAAAAA==.Drureds:BAAALgAECgQJBgAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAgJJQAVAIIgAA==.',
Du='Duckcox:BAAALgAECgQJBwAAAA==.Dunadin:BAABLgAECn8WAAQTAAYJ/Rl6MQCsAQATAAYJ/Rl6MQCsAQAcAAIJ4xIyaAB0AAAdAAEJthUcjwA/AAABLgAECgkJPQAKAK4mAA==.Dundyrn:BAABLgAECn89AAIKAAkJriYzAAB0AwAKAAkJriYzAAB0AwAAAA==.',
Dv='Dvera:BAAALgADCgMJAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECgkJPQAKAK4mAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAcJEQAMABsaAA==.',
Ed='Edmunin:BAEALgAECgYJAwABLgAECgcJAQAJAAAAAA==.',
El='Elememetal:BAABLgAECn8oAAIRAAkJvxijGwABAgARAAkJvxijGwABAgAAAA==.Elfyparker:BAAALgAECgEJAgAAAA==.Elliott:BAAALgADCgIJAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Fa='Fanmir:BAAALgAECgEJAgAAAA==.Fatpao:BAABLgAECn8YAAISAAYJqhfqHgBiAQASAAYJqhfqHgBiAQAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAIQAAcJXQs/WQAjAQAQAAcJXQs/WQAjAQAAAA==.Fenix:BAAALgADCgEJAgABLgAECgkJLwAbANAUAA==.',
Fi='Filbert:BAABLgAECn8dAAIHAAkJUyFZBwDfAgAHAAkJUyFZBwDfAgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Foldyholds:BAAALgAECgQJBAAAAA==.Fomy:BAAALgAECgEJAQABLgAFFAMJBwAHAEAIAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDgAJAAAAAA==.',
Fr='Fraw:BAAALgADCggJDAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAwAAAA==.Fuzzyhunter:BAAALgAECgEJAgABLgAECgkJLwAbANAUAA==.',
['Fá']='Fálola:BAABLgAECn88AAMQAAgJrxffKADsAQAQAAgJrxffKADsAQARAAYJwwOObgCZAAAAAA==.',
Ga='Galestina:BAAALgAECgQJBAAAAA==.Gamblex:BAAALgAECgUJEgAAAA==.Garviel:BAABLgAECn8hAAISAAkJQxvbBwB1AgASAAkJQxvbBwB1AgAAAA==.',
Ge='Geeplague:BAAALgADCgUJCAABLgAECggJGQABABMWAA==.Geethatlock:BAABLgAECn8ZAAIBAAgJExYkRwDEAQABAAgJExYkRwDEAQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAABLgAECn8kAAIIAAYJbBfeDwBZAQAIAAYJbBfeDwBZAQAAAA==.Girthlord:BAAALgAECgQJBAABLgAECgkJNgABAJ4UAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgAECgEJAQAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravincar:BAAALgADCgIJAgABLgAECgkJPQAKAK4mAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAABLgAECn8gAAIQAAgJ8Rv8HgBTAgAQAAgJ8Rv8HgBTAgAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grogu:BAABLgAECn8eAAIZAAcJBQpFsQAcAQAZAAcJBQpFsQAcAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJBQAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAFFAMJBAAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgcJBwAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECgkJLgAeAL0fAA==.Hiksham:BAABLgAECn8uAAMeAAkJvR8bBQCSAgAeAAkJnB8bBQCSAgARAAgJBw3QOgBHAQAAAA==.',
Ho='Holycheeze:BAAALgADCgcJCgAAAA==.Holyhoof:BAAALgAECgEJAQAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgkJIwABAAwVAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgcJGQAQAGwVAA==.',
Ia='Iamreggi:BAAALgAECgQJBgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8vAAIbAAkJ0BT9FgAQAgAbAAkJ0BT9FgAQAgAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Im:BAAALgAFFAMJBAAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
Ir='Irisi:BAAALgADCgUJBQAAAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECggJKAAfABkbAA==.Jarlyss:BAABLgAECn8oAAIfAAgJGRs2DAAZAgAfAAgJGRs2DAAZAgAAAA==.Javieraa:BAABLgAECn8gAAINAAkJYRpVJQA1AgANAAkJYRpVJQA1AgAAAA==.',
Jd='Jdai:BAABLgAECn8ZAAIQAAcJbBUGPAC6AQAQAAcJbBUGPAC6AQAAAA==.',
Jo='Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAAALgAECgcJEQAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgAECgIJAgAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.Karlplkngton:BAAALgAECgEJAQAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8cAAINAAcJaB6HFAAAAgANAAcJaB6HFAAAAgAuAAQKf0MAAg0ACQlkJIAEADwDAA0ACQlkJIAEADwDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn87AAIYAAgJ9BApIABzAQAYAAgJ9BApIABzAQAAAA==.Kikyo:BAAALgAECgYJEgAAAA==.Kimmi:BAAALgAECgUJDwAAAA==.Kinzen:BAABLgAECn8xAAIeAAcJhSB2DQDUAQAeAAcJhSB2DQDUAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIgAAYJAyEjDQDmAQAgAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8jAAIZAAgJPAotjgBYAQAZAAgJPAotjgBYAQAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgAECgIJAgABLgAECgkJOwAPADYdAA==.',
Le='Lechwe:BAABLgAECn82AAIQAAkJVRv6DwDOAgAQAAkJVRv6DwDOAgAAAA==.Legonator:BAAALgAECgUJCAAAAA==.Lenry:BAAALgAFFAEJAQAAAA==.',
Li='Lichmajor:BAABLgAECn8nAAIhAAkJ6BisRgDsAQAhAAkJ6BisRgDsAQAAAA==.Liion:BAAALgADCgYJBgAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.Littlefang:BAAALgAECgQJBAAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn8mAAITAAcJICHvFABtAgATAAcJICHvFABtAgAAAA==.Lovepet:BAABLgAECn8/AAMXAAkJ9x1tGQCIAgAXAAkJ9x1tGQCIAgAIAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAABLgAECn8VAAIhAAYJyxRRkABCAQAhAAYJyxRRkABCAQAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn83AAIZAAkJbiCyIQCUAgAZAAkJbiCyIQCUAgAAAA==.Lunavis:BAAALgAECgcJDgABLgAECgkJGgAaAPUNAA==.',
Ly='Lyda:BAABLgAECn87AAIaAAgJTBylGAB+AgAaAAgJTBylGAB+AgAAAA==.',
Ma='Magice:BAABLgAECn8bAAIZAAUJ+wJIFAGHAAAZAAUJ+wJIFAGHAAAAAA==.Magmara:BAAALgADCgkJGgAAAA==.Malibubarbie:BAABLgAECn80AAIOAAgJtQ82JwCHAQAOAAgJtQ82JwCHAQAAAA==.Malthael:BAAALgAECgIJAwAAAA==.Malystron:BAABLgAECn8UAAIEAAkJ/woiegB4AQAEAAkJ/woiegB4AQAAAA==.Maneevent:BAABLgAECn8ZAAQXAAYJGRdZhgAtAQAXAAYJGRdZhgAtAQAWAAEJ1wToZwArAAAIAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn87AAMPAAkJNh1pBwACAwAPAAkJNh1pBwACAwAbAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn8+AAIXAAkJFgpiUgCnAQAXAAkJFgpiUgCnAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8WAAQgAAYJvRujAgCnAQAgAAUJTxujAgCnAQAHAAIJfB0HRgBUAAAfAAEJhxPoBgA6AAAuAAQKfyoABCAACQkiI0UCAAcDACAACQkiI0UCAAcDAB8AAQkxIY0pAFQAAAcAAQkqFcCBAEEAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn8zAAIOAAkJfQ9RIQC0AQAOAAkJfQ9RIQC0AQAAAA==.',
Mi='Midnightstar:BAABLgAECn8VAAIaAAYJqxIUTwBQAQAaAAYJqxIUTwBQAQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAJAAAAAA==.Mimolette:BAAALgADCgUJBQAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.Miseree:BAAALgAECgcJBwAAAA==.',
Mo='Modest:BAAALgAECgUJBQAAAA==.Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgAECgEJAgAAAA==.Moonbayne:BAABLgAECn8uAAIHAAkJrBoXDwBrAgAHAAkJrBoXDwBrAgAAAA==.Mooszer:BAABLgAECn8fAAIEAAgJWwTo1wDlAAAEAAgJWwTo1wDlAAAAAA==.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBwAAAA==.Mushu:BAABLgAECn8tAAIiAAkJSBriBQCuAgAiAAkJSBriBQCuAgAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.Natre:BAAALgADCgIJAgAAAA==.',
Ne='Nepharim:BAAALgAECgYJCwAAAA==.Nephlim:BAACLgAFFH8aAAMhAAcJFB8IGgAGAgAhAAYJFB8IGgAGAgAjAAEJAADNUgAAAAAuAAQKfzEAAiEACQnmIcQGAGwDACEACQnmIcQGAGwDAAAA.Nergal:BAAALgADCgMJAwAAAA==.',
Ni='Ninobrown:BAAALgAECgYJEwAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNwAZAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNwAZAG4gAA==.Nizano:BAABLgAECn8iAAIEAAcJHgw/sQAaAQAEAAcJHgw/sQAaAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAJAAAAAA==.Noobie:BAAALgADCgYJBgAAAA==.Noryaa:BAABLgAECn8fAAIXAAYJQwbQqwDmAAAXAAYJQwbQqwDmAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.Notfurry:BAAALgAECgIJAgAAAA==.',
Nu='Nuadå:BAABLgAECn8pAAMaAAcJthEnRQB5AQAaAAcJthEnRQB5AQAHAAQJbgWMagB3AAAAAA==.Nuala:BAAALgADCgUJBQAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECggJDQAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAABLgAECn8YAAMbAAUJJBH3RwDtAAAbAAUJJBH3RwDtAAAOAAQJyw7wSgCzAAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAAALgADCgEJAQABLgAECggJHAAaABYiAA==.Orkid:BAAALgAECgEJAQAAAA==.',
Pa='Pawsome:BAAALgAECgQJBAABLgAECggJOQARAPwZAA==.',
Ph='Phelyx:BAAALgAFFAIJBAAAAA==.',
Po='Pogo:BAABLgAECn8fAAIWAAkJdiR9AgAbAwAWAAkJdiR9AgAbAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwAWAHYkAA==.',
Pr='Pricedd:BAAALgADCgcJCAAAAA==.Prosperina:BAAALgADCgQJBAAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8lAAMDAAgJdQiFHAC/AAABAAgJhgcDlwAOAQADAAYJvAqFHAC/AAAAAA==.',
Qu='Quetzani:BAAALgAECgEJAQAAAA==.',
Ra='Ranoa:BAAALgADCgkJCQAAAA==.Rastapopulos:BAAALgAECggJCgAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECgkJPwAXAPcdAA==.Redrocket:BAAALgAECgEJAgABLgAECgQJCAAJAAAAAA==.Rekkash:BAAALgADCgIJAgAAAA==.Remixed:BAAALgAECgMJAwAAAA==.Reptilectric:BAAALgAECgUJDQAAAA==.Retxd:BAAALgADCgEJAQABLgAECgQJBQAJAAAAAA==.',
Ri='Rikaku:BAABLgAECn8yAAIXAAcJoBLiPgCzAQAXAAcJoBLiPgCzAQAAAA==.',
Ro='Roastbeef:BAAALgAECgEJAQAAAA==.Ronananna:BAAALgADCgkJDwABLgADCgYJBgAJAAAAAA==.Rosemery:BAAALgAECgYJBwAAAA==.',
['Râ']='Râpödac:BAAALgADCgIJAgAAAA==.',
['Rä']='Räpodac:BAABLgAECn8qAAIYAAcJlg3OKwAdAQAYAAcJlg3OKwAdAQAAAA==.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Sajae:BAAALgAECgEJAQAAAA==.Saphil:BAAALgADCgkJFAAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Schizo:BAACLgAFFH8JAAIhAAIJtxp7zQCQAAAhAAIJtxp7zQCQAAAuAAQKfx0AAiEABwngIfNAADUCACEABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAwAAAA==.Sefiroth:BAACLgAFFH8FAAINAAMJfwrxcQCcAAANAAMJfwrxcQCcAAAuAAQKfy4AAg0ABwnTFQtaAHYBAA0ABwnTFQtaAHYBAAAA.Selillea:BAAALgAECgYJBwAAAA==.Semarius:BAAALgAECgEJAwABLgAECgkJNwAYAKQhAA==.Semdorii:BAABLgAECn83AAIYAAkJpCFuBAAAAwAYAAkJpCFuBAAAAwAAAA==.Sephywrath:BAABLgAECn8+AAIkAAkJoRsrAgBIAgAkAAkJoRsrAgBIAgAAAA==.Seralith:BAABLgAECn9BAAIhAAkJkyX6AgBuAwAhAAkJkyX6AgBuAwAAAA==.Seranight:BAACLgAFFH8RAAMjAAQJtiQ6DwCEAQAjAAQJtiQ6DwCEAQAhAAEJJwFMIAEnAAAuAAQKf00AAiMACQmTJm4AAHcDACMACQmTJm4AAHcDAAAA.Seven:BAAALgAECgIJBAABLgAECgkJIwABAAwVAA==.Sevenpaws:BAAALgAECgcJDAABLgAECgkJRAAOAHclAA==.',
Sh='Shadowchi:BAABLgAECn8ZAAIDAAYJXQn1HAC8AAADAAYJXQn1HAC8AAAAAA==.Shaidon:BAAALgAECgYJBgAAAQ==.Shaly:BAABLgAECn8jAAIZAAgJPwYapgAuAQAZAAgJPwYapgAuAQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shinjihirako:BAAALgAECgQJBQAAAA==.Shirohige:BAABLgAECn8bAAIfAAUJ4w9oPQCqAAAfAAUJ4w9oPQCqAAAAAA==.Shlonglord:BAAALgADCgIJAgAAAA==.Shylan:BAAALgAFFAEJBAAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDgAAAA==.',
Sn='Snaarf:BAAALgADCgEJAQABLgAECgUJGAAlANIDAA==.Snayre:BAACLgAFFH8MAAIWAAQJohnNDQBSAQAWAAQJohnNDQBSAQAuAAQKfzUAAhYACQlxHqkFAMoCABYACQlxHqkFAMoCAAAA.Snipêr:BAABLgAECn8cAAIXAAgJtBOiRgDJAQAXAAgJtBOiRgDJAQAAAA==.Snowlia:BAACLgAFFH8KAAIQAAMJahP1TwCuAAAQAAMJahP1TwCuAAAuAAQKfyEAAxAACQkxE/A1AKsBABAACQkxE/A1AKsBABEAAQk3D9umACwAAAAA.',
So='Soularis:BAAALgAECgYJCAAAAA==.Soulslice:BAEALgAECggJCAABLgAECgQJEQAJAAAAAA==.Sovrano:BAAALgADCgEJAQAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAABLgAECn8bAAMmAAcJvwaOEQDtAAAmAAcJvwaOEQDtAAAiAAEJ6gGhRQAXAAAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJEAAAAA==.',
St='Stalkingwolf:BAABLgAECn8pAAIjAAcJRxi0GACaAQAjAAcJRxi0GACaAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgAECgYJEQAAAA==.',
Sy='Sylailia:BAACLgAFFH8IAAIHAAMJKAuaMwCrAAAHAAMJKAuaMwCrAAAuAAQKfzQAAgcACQliHEUMAI8CAAcACQliHEUMAI8CAAAA.Syleta:BAAALgADCgMJBAAAAA==.',
['Sí']='Síenna:BAAALgAECgEJAwAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAMJBAAJAAAAAA==.',
Tc='Tcon:BAABLgAECn8UAAIWAAcJRBVYIQCSAQAWAAcJRBVYIQCSAQAAAA==.',
Td='Tdragon:BAAALgADCgkJEgABLgAECgkJLwAbANAUAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thissa:BAABLgAECn8uAAMHAAgJrx8yEQBPAgAHAAgJrx8yEQBPAgAgAAEJSBm4MwAzAAABLgAFFAQJBAAJAAAAAA==.Thundarah:BAAALgADCgcJFwAAAA==.Thundielocks:BAAALgADCgkJCQAAAA==.Thundruid:BAAALgADCgUJCgAAAA==.Thuniellas:BAAALgADCggJGQAAAA==.',
Ti='Tiarcis:BAABLgAECn81AAIXAAkJbBi4IQBaAgAXAAkJbBi4IQBaAgAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Tostitos:BAAALgADCgkJCQABLgAECgkJLwAbANAUAA==.Totemsalot:BAACLgAFFH8MAAIQAAQJjBuzKQA2AQAQAAQJjBuzKQA2AQAuAAQKfxsAAhAACQnGI4gDAIMDABAACQnGI4gDAIMDAAAA.',
Tr='Treesummoner:BAABLgAECn8tAAQBAAkJjRhOKgAvAgABAAkJjRhOKgAvAgADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgADCggJCQAAAA==.Tritanks:BAABLgAECn9EAAIKAAkJWCQUAQAzAwAKAAkJWCQUAQAzAwAAAA==.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAJAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAABLgAECn8UAAIbAAcJpgzDOwAgAQAbAAcJpgzDOwAgAQAAAA==.Valiente:BAAALgAECgIJAgAAAA==.Valkah:BAAALgAECgEJAQAAAA==.Vasilia:BAABLgAECn87AAIjAAgJthrhDwAKAgAjAAgJthrhDwAKAgAAAA==.',
Ve='Velanna:BAAALgAECgIJAgAAAA==.Vexara:BAAALgAECgYJCgAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgAFFAEJAgAAAA==.',
Vo='Voclus:BAAALgAECgYJEwAAAA==.',
Vy='Vykyrnarreia:BAAALgADCgMJAwAAAA==.',
Wa='Wall:BAAALgAECgYJEwAAAA==.Warlodshenu:BAAALgADCgYJCgAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
We='Weyaeh:BAAALgADCgIJAgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wulfbayne:BAAALgAECgQJBAAAAA==.Wuwindtang:BAAALgAECgUJDAAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgAECgEJAQAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAILAAYJqQWYagC1AAALAAYJqQWYagC1AAAAAA==.Xiletank:BAAALgAECgUJBQAAAA==.',
Za='Zachxd:BAABLgAECn88AAINAAcJ6RkFUQCPAQANAAcJ6RkFUQCPAQABLgAFFAIJCQAhALcaAA==.Zanthe:BAAALgAECgQJDgAAAA==.Zapanese:BAAALgADCgMJBAAAAA==.Zapt:BAAALgAECgIJAgAAAA==.Zaptism:BAABLgAECn87AAMOAAkJMCEaCADoAgAOAAkJMCEaCADoAgAPAAUJhQ4BRgDtAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgADCgkJJgAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgYJEAABLgAFFAIJBwAKAB4VAA==.Zhanbear:BAAALgAECggJDAABLgAFFAIJBwAKAB4VAA==.Zhanbrew:BAACLgAFFH8LAAIcAAMJlB/EIwAXAQAcAAMJlB/EIwAXAQAuAAQKfyQAAhwACQnhItgCACgDABwACQnhItgCACgDAAEuAAUUAgkHAAoAHhUA.Zhanfury:BAAALgAFFAEJAQABLgAFFAIJBwAKAB4VAA==.',
Zi='Zinder:BAABLgAECn8nAAMlAAgJTQiQSAAFAQAlAAgJTQiQSAAFAQAmAAEJLAMhKwAeAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJjReMBQAPAgADAAkJjReMBQAPAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECggJKAAfABkbAA==.',
['Öb']='Öboron:BAACLgAFFH8JAAMWAAQJVgNPHQDiAAAWAAQJVgNPHQDiAAAIAAEJywEEOwAsAAAuAAQKfy4ABBYACQmMF9UOAD8CABYACQknFtUOAD8CAAgACAlWECgqANoBABcABgkpFTJTAG8BAAAA.',
['Üz']='Üz:BAABLgAECn8kAAIYAAgJvhY7GAC9AQAYAAgJvhY7GAC9AQAAAA==.',
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
