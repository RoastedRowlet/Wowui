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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Warrior-Fury','Warrior-Protection','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Monk-Mistweaver','DeathKnight-Frost','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','Druid-Restoration','Priest-Shadow','Paladin-Holy','Shaman-Enhancement','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Monk-Brewmaster','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Addely:BAAALgAECgYJBgAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgQJBgAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRqucACbAQAEAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJEQAAAA==.',
Al='Alerion:BAABLgAECn8sAAIFAAkJKhk/CQBuAgAFAAkJKhk/CQBuAgAAAA==.Allan:BAABLgAECn8rAAIGAAkJbiGpAADgAgAGAAkJbiGpAADgAgAAAA==.Alligatorjoe:BAAALgADCgEJAQAAAA==.',
Am='Amaneeda:BAABLgAECn8nAAIHAAgJEA1HKwBLAQAHAAgJEA1HKwBLAQAAAA==.Amazonia:BAAALgAECgQJBQAAAA==.Aminea:BAAALgAECgYJBgAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAIAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8FAAIJAAIJHhVSCQBuAAAJAAIJHhVSCQBuAAAuAAQKfywAAgkABwnOIrMEAEYCAAkABwnOIrMEAEYCAAAA.Angyrain:BAAALgAECgUJBQABLgAFFAIJBQAJAB4VAA==.Annerila:BAAALgADCggJCAAAAA==.Antagonis:BAABLgAECn8YAAIDAAcJsQ6PDwAbAQADAAcJsQ6PDwAbAQAAAA==.',
Ap='Apexchi:BAAALgAECgMJBQAAAA==.Apeximmortal:BAAALgAECgYJAwAAAA==.Apexlight:BAAALgAECgkJEQAAAA==.Apexwar:BAAALgADCgMJAwAAAA==.',
Ar='Arashe:BAAALgAECgUJCQAAAA==.Arewen:BAAALgADCggJDQAAAA==.Arganos:BAABLgAECn8wAAMKAAkJtSbZAABvAwAKAAkJtSbZAABvAwALAAYJFxsgFACFAQAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8WAAIMAAcJ6wSknwC4AAAMAAcJ6wSknwC4AAAAAA==.Arkstrife:BAAALgADCgEJAQAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgADCgkJKQAAAA==.Atheîst:BAABLgAECn9AAAMNAAkJdyXMAQBaAwANAAkJdyXMAQBaAwAOAAYJCyP/DQBiAgAAAA==.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn8/AAMPAAkJfh5xFAB7AgAPAAgJUR5xFAB7AgAQAAgJ5hMsJgCMAQAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAUJEQAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJMAAKALUmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8cAAMRAAcJuRqzEAC8AQARAAcJuRqzEAC8AQAKAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8fAAISAAYJ9RWcLgBxAQASAAYJ9RWcLgBxAQAAAA==.Baelanoth:BAABLgAECn8iAAITAAgJVxyNBQAaAgATAAgJVxyNBQAaAgAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balkazaar:BAAALgAECgcJDQAAAA==.Bammbamm:BAABLgAECn8nAAIEAAgJEwgujgA0AQAEAAgJEwgujgA0AQAAAA==.Banewreak:BAABLgAECn8vAAIBAAkJHxWAMwDzAQABAAkJHxWAMwDzAQAAAA==.Banu:BAAALgAECgEJAQAAAA==.Baradin:BAAALgAECgYJCwAAAA==.Barind:BAABLgAECn8yAAQUAAkJFh00BgCnAgAUAAkJmRw0BgCnAgAVAAcJIxqYJAADAgAWAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgMJBgAAAA==.Betrayer:BAABLgAECn8cAAIXAAkJMyFrAwD4AgAXAAkJMyFrAwD4AgAAAA==.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAAALgAECggJEAAAAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Biqdonk:BAAALgAECgUJDAAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDQABLgADCgYJCwAIAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAIAAAAAA==.Bossdwarf:BAAALgADCgcJCwABLgADCgYJCwAIAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
['Bú']='Búbblés:BAAALgAECgcJDQAAAA==.',
Ca='Caatia:BAAALgAECggJCQAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECggJIQABAKEWAA==.Carthel:BAABLgAECn8fAAIYAAgJMiBYMQCtAgAYAAgJMiBYMQCtAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCggJDgAAAA==.',
Ce='Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Charley:BAAALgAECgEJAQAAAA==.Chasseresse:BAAALgAECgQJBQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chi:BAAALgAECgEJAQAAAA==.Chimarr:BAABLgAECn8cAAIZAAgJFiKhDQDPAgAZAAgJFiKhDQDPAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Co='Coldsploder:BAABLgAECn8hAAIYAAgJChToXgCmAQAYAAgJChToXgCmAQAAAA==.',
Cr='Crackmonkéy:BAABLgAECn8aAAQOAAgJ2BhnIgCLAQAOAAcJNBRnIgCLAQANAAQJkRlWTwD7AAAaAAQJdBA4QQDvAAABLgAECggJLgAHAK8fAA==.Cranknspank:BAAALgAECgYJBwAAAA==.Cronoz:BAABLgAECn8iAAMPAAgJqwrbWQAhAQAPAAcJkgfbWQAhAQAQAAcJNgruQgD4AAAAAA==.Crotchshot:BAABLgAECn8YAAIWAAgJLw70TgCIAQAWAAgJLw70TgCIAQAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Cursess:BAACLgAFFH8IAAIBAAIJPB5AdAClAAABAAIJPB5AdAClAAAuAAQKfzIAAgEACQlxInMLAN4CAAEACQlxInMLAN4CAAAA.',
['Có']='Cózmik:BAAALgAECgUJDgAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn8mAAIBAAgJ5w8TVACJAQABAAgJ5w8TVACJAQAAAA==.Dalya:BAAALgAECgcJBwAAAA==.Dander:BAAALgADCgMJAwAAAA==.Dani:BAAALgAECgEJAgABLgAECgQJBAAIAAAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAAALgAECgYJDQAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deathratellr:BAAALgADCgEJAQAAAA==.Deemaius:BAAALgADCgQJBgAAAA==.Dekard:BAAALgAECggJEQAAAA==.Dekariusly:BAAALgAECgEJAQABLgAECggJEQAIAAAAAA==.Demonatrixx:BAAALgAECgYJCQAAAA==.Demonhugger:BAAALgAECgEJAgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHwACAFwZAA==.Destinÿ:BAABLgAECn8jAAILAAgJPRczEgCeAQALAAgJPRczEgCeAQAAAA==.Devourer:BAABLgAECn8oAAIMAAgJGBt6JAAfAgAMAAgJGBt6JAAfAgAAAA==.',
Di='Disploder:BAABLgAECn8eAAINAAcJOhMpIwCHAQANAAcJOhMpIwCHAQAAAA==.Dist:BAAALgAECgYJCwAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJAQABLgAECgEJAgAIAAAAAA==.Drawwn:BAAALgAECgEJAgAAAA==.Dreathhammer:BAABLgAECn8uAAIbAAkJ1SJdAgBuAwAbAAkJ1SJdAgBuAwAAAA==.Drogo:BAAALgAECggJCAABLgAECggJLgAHAK8fAA==.Dryad:BAAALgAECgQJBAABLgAFFAYJHAAbAF0jAA==.',
Du='Duckcox:BAAALgAECgMJAwAAAA==.Dunadin:BAAALgAECgYJEwABLgAECggJNQAJAJ4mAA==.Dundyrn:BAABLgAECn81AAIJAAgJniZDAQAFAwAJAAgJniZDAQAFAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECggJNQAJAJ4mAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAYJDwALACsaAA==.',
El='Elememetal:BAABLgAECn8oAAIQAAkJvxhaFgAIAgAQAAkJvxhaFgAIAgAAAA==.Elfyparker:BAAALgAECgEJAQAAAA==.Elliott:BAAALgADCgIJAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Fa='Fanmir:BAAALgAECgEJAQAAAA==.Fatpao:BAAALgADCgQJBAAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAIPAAcJXQs/WQAjAQAPAAcJXQs/WQAjAQAAAA==.Fenix:BAAALgADCgEJAgAAAA==.',
Fi='Filbert:BAABLgAECn8bAAIHAAgJxSCLCwB2AgAHAAgJxSCLCwB2AgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Fomy:BAAALgAECgEJAQABLgAECgkJGgAHAKsMAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDgAIAAAAAA==.',
Fr='Fraw:BAAALgADCggJDAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAgAAAA==.',
['Fá']='Fálola:BAABLgAECn88AAMPAAgJrxffKADsAQAPAAgJrxffKADsAQAQAAYJwwPFXACdAAAAAA==.',
Ga='Gamblex:BAAALgAECgUJDgAAAA==.Garviel:BAABLgAECn8UAAIRAAcJ0xejFQCHAQARAAcJ0xejFQCHAQAAAA==.',
Ge='Geethatlock:BAABLgAECn8UAAIBAAgJExY5QQDAAQABAAgJExY5QQDAAQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAABLgAECn8VAAIVAAYJJBRMEAAvAQAVAAYJJBRMEAAvAQAAAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgADCgYJCwAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAABLgAECn8XAAIPAAcJghwJIQAbAgAPAAcJghwJIQAbAgAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grogu:BAABLgAECn8dAAIYAAcJBQo4mAAuAQAYAAcJBQo4mAAuAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJAwAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAECgYJCwAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgcJBwAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECgkJLQAcAL0fAA==.Hiksham:BAABLgAECn8tAAMcAAkJvR+cAwCgAgAcAAkJnB+cAwCgAgAQAAgJBw3TMABNAQAAAA==.',
Ho='Holycheeze:BAAALgADCgcJCgAAAA==.Holyhoof:BAAALgAECgEJAQAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECggJIQABAKEWAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgcJGQAPAGwVAA==.',
Ia='Iamreggi:BAAALgAECgQJBgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8hAAIaAAgJFhCqIwCDAQAaAAgJFhCqIwCDAQAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Im:BAAALgAECgEJAQAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECggJGgAdALsWAA==.Jarlyss:BAABLgAECn8aAAIdAAgJuxZIDgDDAQAdAAgJuxZIDgDDAQAAAA==.Javieraa:BAABLgAECn8gAAIMAAkJYRrRHgA+AgAMAAkJYRrRHgA+AgAAAA==.',
Jd='Jdai:BAABLgAECn8ZAAIPAAcJbBVpMQC/AQAPAAcJbBVpMQC/AQAAAA==.',
Jo='Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAAALgAECgYJCgAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgADCgQJBAAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8ZAAIMAAYJMyChEADIAQAMAAYJMyChEADIAQAuAAQKf0MAAgwACQlkJDoDAEQDAAwACQlkJDoDAEQDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn8tAAIXAAgJ5Ax8HgBKAQAXAAgJ5Ax8HgBKAQAAAA==.Kikyo:BAAALgAECgYJCwAAAA==.Kimmi:BAAALgAECgQJBgAAAA==.Kinzen:BAABLgAECn8xAAIcAAcJhSBNCgDfAQAcAAcJhSBNCgDfAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIeAAYJAyEjDQDmAQAeAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8jAAIYAAgJPAp1eABrAQAYAAgJPAp1eABrAQAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgADCgEJAgABLgAECggJMwAOAN4XAA==.',
Le='Lechwe:BAABLgAECn8jAAIPAAcJjRsPHwApAgAPAAcJjRsPHwApAgAAAA==.Legonator:BAAALgAECgUJCAAAAA==.Lenry:BAAALgAECgQJBAAAAA==.',
Li='Lichmajor:BAABLgAECn8nAAIfAAkJ6BjfOQD2AQAfAAkJ6BjfOQD2AQAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn8eAAISAAcJAiFvEQBfAgASAAcJAiFvEQBfAgAAAA==.Lovepet:BAABLgAECn81AAMWAAgJcx2NIwAqAgAWAAgJcx2NIwAqAgAVAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAAALgAECgQJBAAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn83AAIYAAkJbiD9GQCjAgAYAAkJbiD9GQCjAgAAAA==.',
Ly='Lyda:BAABLgAECn8tAAIZAAgJfhskFwBrAgAZAAgJfhskFwBrAgAAAA==.',
Ma='Magice:BAABLgAECn8UAAIYAAUJiALy+ACHAAAYAAUJiALy+ACHAAAAAA==.Magmara:BAAALgADCgkJCQAAAA==.Malibubarbie:BAABLgAECn8mAAINAAgJ/g3cIwCCAQANAAgJ/g3cIwCCAQAAAA==.Malystron:BAAALgAECgkJEAAAAA==.Maneevent:BAABLgAECn8ZAAQWAAYJGRdBbQA4AQAWAAYJGRdBbQA4AQAUAAEJ1wQ3WgAsAAAVAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn8zAAMOAAgJ3hdFEwAaAgAOAAgJ3hdFEwAaAgAaAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn80AAIWAAgJiQjVXQBfAQAWAAgJiQjVXQBfAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8TAAQeAAUJeRyOAwBgAQAeAAQJ8RuOAwBgAQAdAAEJhxPoBgA6AAAHAAEJAACLQgAAAAAuAAQKfyoABB4ACQkiI2ABABoDAB4ACQkiI2ABABoDAB0AAQkxIY0pAFQAAAcAAQkqFbVuAEEAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn8sAAINAAkJBw/wGwDBAQANAAkJBw/wGwDBAQAAAA==.',
Mi='Midnightstar:BAAALgAECgYJEwAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAIAAAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.Miseree:BAAALgAECgcJBwAAAA==.',
Mo='Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgAECgEJAQAAAA==.Moonbayne:BAABLgAECn8nAAIHAAgJpRnNGADYAQAHAAgJpRnNGADYAQAAAA==.Mooszer:BAABLgAECn8ZAAIEAAYJ7QPP4gCzAAAEAAYJ7QPP4gCzAAAAAA==.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBgAAAA==.Mushu:BAABLgAECn8tAAIgAAkJSBrDBAC3AgAgAAkJSBrDBAC3AgAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.Natre:BAAALgADCgIJAgAAAA==.',
Ne='Nepharim:BAAALgAECgYJCwAAAA==.Nephlim:BAACLgAFFH8YAAMfAAYJWR+hEwDKAQAfAAUJWR+hEwDKAQAhAAEJAAB3PQAAAAAuAAQKfzEAAh8ACQnmIcQGAGwDAB8ACQnmIcQGAGwDAAAA.',
Ni='Ninobrown:BAAALgAECgYJEwAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNwAYAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNwAYAG4gAA==.Nizano:BAABLgAECn8aAAIEAAcJ4AvskgAsAQAEAAcJ4AvskgAsAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAIAAAAAA==.Noryaa:BAABLgAECn8aAAIWAAYJpQV6lwDcAAAWAAYJpQV6lwDcAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.',
Nu='Nuadå:BAABLgAECn8cAAMZAAcJrw46RwBPAQAZAAcJrw46RwBPAQAHAAQJbgWMagB3AAAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECgYJCwAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAABLgAECn8RAAMaAAUJ9AqvRgDHAAAaAAUJ9AqvRgDHAAANAAQJ2wgRSACaAAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAAALgADCgEJAQABLgAECggJHAAZABYiAA==.Orkid:BAAALgAECgEJAQAAAA==.',
Ph='Phelyx:BAAALgAECgEJAQAAAA==.',
Po='Pogo:BAABLgAECn8fAAIUAAkJdiR9AgAbAwAUAAkJdiR9AgAbAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwAUAHYkAA==.',
Pr='Pricedd:BAAALgADCgUJBQAAAA==.Prosperina:BAAALgADCgQJBAAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8eAAMDAAcJtQmhFgDMAAABAAcJJgjViQARAQADAAYJvAqhFgDMAAAAAA==.',
Ra='Ranoa:BAAALgADCgkJCQAAAA==.Rastapopulos:BAAALgAECggJCAAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECggJNQAWAHMdAA==.Redrocket:BAAALgAECgEJAgABLgAECgMJBgAIAAAAAA==.Remixed:BAAALgAECgMJAwAAAA==.',
Ri='Rikaku:BAABLgAECn8sAAIWAAcJvBHiPgCzAQAWAAcJvBHiPgCzAQAAAA==.',
Ro='Ronananna:BAAALgADCgkJDwABLgADCgYJBgAIAAAAAA==.Rosemery:BAAALgAECgYJBgAAAA==.',
['Rä']='Räpodac:BAABLgAECn8oAAIXAAcJtgsKJQAVAQAXAAcJtgsKJQAVAQAAAA==.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Saphil:BAAALgADCgkJFAAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Schizo:BAACLgAFFH8IAAIfAAIJtxoLnQCaAAAfAAIJtxoLnQCaAAAuAAQKfx0AAh8ABwngIfNAADUCAB8ABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAgAAAA==.Sefiroth:BAABLgAECn8oAAIMAAcJZhFJXgBKAQAMAAcJZhFJXgBKAQAAAA==.Selillea:BAAALgAECgYJBwAAAA==.Semarius:BAAALgAECgEJAwABLgAECggJLgAXACkgAA==.Semdorii:BAABLgAECn8uAAIXAAgJKSBhCAB7AgAXAAgJKSBhCAB7AgAAAA==.Sephywrath:BAABLgAECn8+AAIiAAkJoRtVAQBwAgAiAAkJoRtVAQBwAgAAAA==.Seralith:BAABLgAECn8vAAIfAAkJ4iOMBgAqAwAfAAkJ4iOMBgAqAwAAAA==.Seranight:BAACLgAFFH8LAAMhAAQJkSTuCACPAQAhAAQJkSTuCACPAQAfAAEJJwFd3wAwAAAuAAQKfzkAAiEACAl2Jt4CAAIDACEACAl2Jt4CAAIDAAAA.Seven:BAAALgAECgIJBAABLgAECggJIQABAKEWAA==.Sevenpaws:BAAALgAECgIJAgABLgAECgkJQAANAHclAA==.',
Sh='Shadowchi:BAAALgAECgQJBQAAAA==.Shaidon:BAAALgAECgYJBgAAAQ==.Shaly:BAABLgAECn8jAAIYAAgJPwbTjgA+AQAYAAgJPwbTjgA+AQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shirohige:BAABLgAECn8UAAIdAAUJ1w8OLwCpAAAdAAUJ1w8OLwCpAAAAAA==.Shlonglord:BAAALgADCgIJAgAAAA==.Shylan:BAAALgAFFAEJAQAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDgAAAA==.',
Sn='Snayre:BAABLgAECn81AAIUAAkJcR7XAwDeAgAUAAkJcR7XAwDeAgAAAA==.Snipêr:BAAALgAECgYJDgAAAA==.Snowlia:BAACLgAFFH8FAAIPAAIJUxAmTACAAAAPAAIJUxAmTACAAAAuAAQKfxgAAw8ABwnJE/A1AKsBAA8ABwnJE/A1AKsBABAAAQk3D8WKAC0AAAAA.',
So='Soularis:BAAALgAECgYJCAAAAA==.Soulslice:BAEALgAECgcJBwABLgAECgQJEQAIAAAAAA==.Sovrano:BAAALgADCgEJAQAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAAALgAECgcJDgAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJEAAAAA==.',
St='Stalkingwolf:BAABLgAECn8cAAIhAAcJ1xY5GABxAQAhAAcJ1xY5GABxAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgAECgYJBgAAAA==.',
Sy='Sylailia:BAABLgAECn80AAIHAAkJYhxLCQCaAgAHAAkJYhxLCQCaAgAAAA==.Syleta:BAAALgADCgMJBAAAAA==.',
['Sí']='Síenna:BAAALgAECgEJAQAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAIJAgAIAAAAAA==.',
Tc='Tcon:BAABLgAECn8UAAIUAAcJRBX9GwCfAQAUAAcJRBX9GwCfAQAAAA==.',
Td='Tdragon:BAAALgADCgkJEgAAAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thissa:BAABLgAECn8uAAMHAAgJrx/fDQBUAgAHAAgJrx/fDQBUAgAeAAEJSBm4MwAzAAAAAA==.Thundarah:BAAALgADCgcJEAAAAA==.Thundruid:BAAALgADCgUJCgAAAA==.Thuniellas:BAAALgADCggJGQAAAA==.',
Ti='Tiarcis:BAABLgAECn8fAAIWAAgJ/RBhQgCvAQAWAAgJ/RBhQgCvAQAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Totemsalot:BAABLgAECn8YAAIPAAkJFiJsAwBjAwAPAAkJFiJsAwBjAwAAAA==.',
Tr='Treesummoner:BAABLgAECn8tAAQBAAkJjRhpIgA/AgABAAkJjRhpIgA/AgADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgADCggJCQAAAA==.Tritanks:BAABLgAECn8xAAIJAAgJsR8VBQA4AgAJAAgJsR8VBQA4AgAAAA==.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAIAAAAAA==.',
['Tô']='Tôtemic:BAAALgAECgIJAgAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAAALgAECgYJEQAAAA==.Valiente:BAAALgAECgEJAQAAAA==.Vasilia:BAABLgAECn8tAAIhAAgJDhd/EQDFAQAhAAgJDhd/EQDFAQAAAA==.',
Ve='Velanna:BAAALgAECgIJAgAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgAECgMJBAAAAA==.',
Vo='Voclus:BAAALgAECgYJDAAAAA==.',
Wa='Wall:BAAALgAECgQJBAAAAA==.Warlodshenu:BAAALgADCgYJBgAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wuwindtang:BAAALgAECgUJCwAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgADCgMJAwAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAIKAAYJqQX5WgC4AAAKAAYJqQX5WgC4AAAAAA==.Xiletank:BAAALgAECgUJBQAAAA==.',
Za='Zachxd:BAABLgAECn81AAIMAAcJvhn5SgCDAQAMAAcJvhn5SgCDAQABLgAFFAIJCAAfALcaAA==.Zanthe:BAAALgAECgQJCwAAAA==.Zapanese:BAAALgADCgMJBAAAAA==.Zapt:BAAALgADCgYJBgAAAA==.Zaptism:BAABLgAECn8qAAMNAAkJuBxXCwCaAgANAAkJuBxXCwCaAgAOAAUJTgsSPgDcAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgADCggJHQAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgYJDgABLgAFFAIJBQAJAB4VAA==.Zhanbrew:BAABLgAECn8UAAIjAAcJVht9FgDWAQAjAAcJVht9FgDWAQABLgAFFAIJBQAJAB4VAA==.Zhanfury:BAAALgAFFAEJAQABLgAFFAIJBQAJAB4VAA==.',
Zi='Zinder:BAABLgAECn8nAAMkAAgJTQiVOwAVAQAkAAgJTQiVOwAVAQAlAAEJLAOLJAAhAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJjRfwAwAiAgADAAkJjRfwAwAiAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECggJGgAdALsWAA==.',
['Öb']='Öboron:BAACLgAFFH8JAAMUAAQJVgOqFQD4AAAUAAQJVgOqFQD4AAAVAAEJywEBLAAxAAAuAAQKfy4ABBQACQmMF54LAE4CABQACQknFp4LAE4CABUACAlWECgqANoBABYABgkpFTJTAG8BAAAA.',
['Üz']='Üz:BAABLgAECn8kAAIXAAgJvha+EgDKAQAXAAgJvha+EgDKAQAAAA==.',
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
