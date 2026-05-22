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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Warrior-Fury','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Monk-Mistweaver','DeathKnight-Frost','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','Druid-Restoration','Priest-Shadow','Warrior-Protection','Paladin-Holy','Shaman-Enhancement','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Addely:BAAALgADCgEJAgAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgMJBQAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRqucACbAQAEAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJDwAAAA==.',
Al='Alerion:BAABLgAECn8gAAIFAAgJHRlLEgDBAQAFAAgJHRlLEgDBAQAAAA==.Allan:BAABLgAECn8rAAIGAAkJbiF0AADyAgAGAAkJbiF0AADyAgAAAA==.',
Am='Amaneeda:BAABLgAECn8jAAIHAAgJMwxlJwA5AQAHAAgJMwxlJwA5AQAAAA==.Amazonia:BAAALgAECgEJAQAAAA==.Aminea:BAAALgADCgkJDQAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAIAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8FAAIJAAIJHhWhBwByAAAJAAIJHhWhBwByAAAuAAQKfx4AAgkABwk4H0oFAAICAAkABwk4H0oFAAICAAAA.Angyrain:BAAALgAECgUJBQAAAA==.Antagonis:BAABLgAECn8WAAIDAAcJ6AuNDgALAQADAAcJ6AuNDgALAQAAAA==.',
Ap='Apexchi:BAAALgAECgMJBQAAAA==.Apeximmortal:BAAALgAECgYJAwAAAA==.Apexlight:BAAALgAECgcJDgAAAA==.Apexwar:BAAALgADCgMJAwAAAA==.',
Ar='Arashe:BAAALgAECgQJCAAAAA==.Arganos:BAABLgAECn8qAAIKAAkJsyZ3AAB5AwAKAAkJsyZ3AAB5AwAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8UAAILAAYJhgVGlgCfAAALAAYJhgVGlgCfAAAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgADCgkJIQAAAA==.Atheîst:BAABLgAECn84AAMMAAkJbiXMAQBaAwAMAAkJbiXMAQBaAwANAAQJ5CEfHgCCAQAAAA==.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn82AAMOAAgJRR5bEgBpAgAOAAgJRR5bEgBpAgAPAAYJvhLbNQAKAQAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAUJEQAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJKgAKALMmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8YAAMQAAcJhRccEQCLAQAQAAcJcBccEQCLAQAKAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8eAAIRAAYJ9RUaJgBtAQARAAYJ9RUaJgBtAQAAAA==.Baelanoth:BAABLgAECn8aAAISAAcJ6htRBgDHAQASAAcJ6htRBgDHAQAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balkazaar:BAAALgAECgcJCgAAAA==.Bammbamm:BAABLgAECn8gAAIEAAcJjAjHkQAGAQAEAAcJjAjHkQAGAQAAAA==.Banewreak:BAABLgAECn8vAAIBAAkJHxUmKgD1AQABAAkJHxUmKgD1AQAAAA==.Banu:BAAALgADCgEJAQAAAA==.Baradin:BAAALgADCgUJBQAAAA==.Barind:BAABLgAECn8rAAQTAAkJFR2gBACuAgATAAkJahygBACuAgAUAAcJIxqYJAADAgAVAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgMJBgAAAA==.Betrayer:BAABLgAECn8VAAIWAAgJviAABgCOAgAWAAgJviAABgCOAgAAAA==.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAAALgAECgQJBAAAAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Biqdonk:BAAALgAECgUJCQAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDAABLgADCgYJCwAIAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAIAAAAAA==.Bossdwarf:BAAALgADCgYJBgABLgADCgYJCwAIAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
['Bú']='Búbblés:BAAALgAECgUJBwAAAA==.',
Ca='Caatia:BAAALgAECggJCQAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgcJHwABAOYWAA==.Carthel:BAABLgAECn8fAAIXAAgJMCCGIgBWAgAXAAgJMCCGIgBWAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCgYJBgAAAA==.',
Ce='Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Chasseresse:BAAALgAECgEJAQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chimarr:BAEBLgAECn8cAAIYAAgJFSLqCgDRAgAYAAgJFSLqCgDRAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Co='Coldsploder:BAABLgAECn8hAAIXAAgJCRTvTQCxAQAXAAgJCRTvTQCxAQAAAA==.',
Cr='Crackmonkéy:BAABLgAECn8aAAQNAAgJ2RibHACQAQANAAcJNBSbHACQAQAMAAQJkhlWTwD7AAAZAAQJdBA4QQDvAAAAAA==.Cranknspank:BAAALgAECgIJAgAAAA==.Cronoz:BAABLgAECn8gAAMOAAgJqwrbWQAhAQAOAAcJkgfbWQAhAQAPAAcJ7AcJPgDkAAAAAA==.Crotchshot:BAABLgAECn8XAAIVAAcJjw0vUwBQAQAVAAcJjw0vUwBQAQAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Cursess:BAACLgAFFH8GAAIBAAIJPB7FYwCrAAABAAIJPB7FYwCrAAAuAAQKfzIAAgEACQlrIukHAOsCAAEACQlrIukHAOsCAAAA.',
['Có']='Cózmik:BAAALgAECgUJDgAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn8eAAIBAAgJoQ/SSgB9AQABAAgJoQ/SSgB9AQAAAA==.Dalya:BAAALgAECgEJAQAAAA==.Dander:BAAALgADCgMJAwAAAA==.Dani:BAAALgAECgEJAgAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAAALgAECgYJCgAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deemaius:BAAALgADCgMJAwAAAA==.Dekard:BAAALgAECggJEQAAAA==.Dekariusly:BAAALgAECgEJAQABLgAECggJEQAIAAAAAA==.Demonatrixx:BAAALgAECgIJAgAAAA==.Demonhugger:BAAALgAECgEJAgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgMJBQAIAAAAAA==.Destinÿ:BAABLgAECn8iAAIaAAgJOheiDgCwAQAaAAgJOheiDgCwAQAAAA==.Devourer:BAABLgAECn8hAAILAAcJNBtkMQC4AQALAAcJNBtkMQC4AQAAAA==.',
Di='Disploder:BAABLgAECn8eAAIMAAcJPBPCHQCPAQAMAAcJPBPCHQCPAQAAAA==.Dist:BAAALgAECgYJCgAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJAQAAAA==.Drawwn:BAAALgAECgEJAgAAAA==.Dreathhammer:BAABLgAECn8nAAIbAAkJciLJBAAPAwAbAAkJciLJBAAPAwAAAA==.Drogo:BAAALgADCgIJAgAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAYJHAAbAF0jAA==.',
Du='Dunadin:BAAALgAECgYJEwABLgAECggJLQAJAJwmAA==.Dundyrn:BAABLgAECn8tAAIJAAgJnCbuAAAEAwAJAAgJnCbuAAAEAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECggJLQAJAJwmAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAUJDQAaAEUcAA==.',
El='Elememetal:BAABLgAECn8oAAIPAAkJwBiHEQAUAgAPAAkJwBiHEQAUAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Fa='Fanmir:BAAALgADCgYJBgAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAIOAAcJXQs/WQAjAQAOAAcJXQs/WQAjAQAAAA==.Fenix:BAAALgADCgEJAgAAAA==.',
Fi='Filbert:BAABLgAECn8aAAIHAAgJxCAjCQB7AgAHAAgJxCAjCQB7AgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Fomy:BAAALgAECgEJAQAAAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDQAIAAAAAA==.',
Fr='Fraw:BAAALgADCggJCAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAQAAAA==.',
['Fá']='Fálola:BAABLgAECn80AAMOAAgJ+BbfKADsAQAOAAgJ+BbfKADsAQAPAAYJwwMIUAChAAAAAA==.',
Ga='Gamblex:BAAALgAECgQJCQAAAA==.Garviel:BAABLgAECn8UAAIQAAcJ0xe/EACQAQAQAAcJ0xe/EACQAQAAAA==.',
Ge='Geethatlock:BAABLgAECn8UAAIBAAgJExbsNwC8AQABAAgJExbsNwC8AQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAAALgAECgYJDwAAAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgADCgYJCwAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAAALgAECgYJEAAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grogu:BAABLgAECn8YAAIXAAcJswkehAA1AQAXAAcJswkehAA1AQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJAgAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAECgYJCwAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgQJBAAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECggJJAAcAM4fAA==.Hiksham:BAABLgAECn8kAAMcAAgJzh9fBABfAgAcAAgJzh9fBABfAgAPAAYJSQr9RwAoAQAAAA==.',
Ho='Holycheeze:BAAALgADCgcJCgAAAA==.Holyhoof:BAAALgADCgMJBAAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgcJHwABAOYWAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgYJEwAIAAAAAA==.',
Ia='Iamreggi:BAAALgAECgIJAgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8ZAAIZAAcJHhDpJABOAQAZAAcJHhDpJABOAQAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Im:BAAALgAECgEJAQAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECgcJFAAdAPsXAA==.Jarlyss:BAABLgAECn8UAAIdAAcJ+xcZDgCWAQAdAAcJ+xcZDgCWAQAAAA==.Javieraa:BAABLgAECn8gAAILAAkJUBppGQA8AgALAAkJUBppGQA8AgAAAA==.',
Jd='Jdai:BAAALgAECgYJEwAAAA==.',
Jo='Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAAALgAECgUJBQAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgADCgQJBAAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8YAAILAAYJMyDkCgDSAQALAAYJMyDkCgDSAQAuAAQKfzsAAgsACQlMJFMDADADAAsACQlMJFMDADADAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn8mAAIWAAcJzA02HgAhAQAWAAcJzA02HgAhAQAAAA==.Kikyo:BAAALgAECgYJCgAAAA==.Kimmi:BAAALgAECgMJBQAAAA==.Kinzen:BAABLgAECn8sAAIcAAcJsh6xCQA6AgAcAAcJsh6xCQA6AgAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIeAAYJAyEjDQDmAQAeAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8bAAIXAAYJnwg+sQDlAAAXAAYJnwg+sQDlAAAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgADCgEJAgABLgAECggJKwANABYXAA==.',
Le='Lechwe:BAABLgAECn8cAAIOAAcJfxc0JQDZAQAOAAcJfxc0JQDZAQAAAA==.Legonator:BAAALgAECgUJCAAAAA==.',
Li='Lichmajor:BAABLgAECn8nAAIfAAkJ6BiBMAD4AQAfAAkJ6BiBMAD4AQAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn8aAAIRAAcJPiC3DgBQAgARAAcJPiC3DgBQAgAAAA==.Lovepet:BAABLgAECn8tAAMVAAgJch19HQAoAgAVAAgJch19HQAoAgAUAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAAALgAECgQJBAAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn81AAIXAAkJbiCDFACoAgAXAAkJbiCDFACoAgAAAA==.',
Ly='Lyda:BAABLgAECn8mAAIYAAcJdxvlHwACAgAYAAcJdxvlHwACAgAAAA==.',
Ma='Magice:BAAALgAECgQJDwAAAA==.Magmara:BAAALgADCgkJCQAAAA==.Malibubarbie:BAABLgAECn8fAAIMAAcJUAwQKAA+AQAMAAcJUAwQKAA+AQAAAA==.Malystron:BAAALgAECgkJCQAAAA==.Maneevent:BAABLgAECn8XAAQVAAYJGRcyWQA/AQAVAAYJGRcyWQA/AQATAAEJ1wTWTwAsAAAUAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn8rAAMNAAgJFhcxEQAKAgANAAgJFhcxEQAKAgAZAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn8sAAIVAAgJJwjaUwBOAQAVAAgJJwjaUwBOAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8SAAQeAAUJchoxAwBmAQAeAAQJ6RkxAwBmAQAdAAEJhxPoBgA6AAAHAAEJAABXOAAAAAAuAAQKfyEABB4ACAkvJPcBAD8DAB4ACAkvJPcBAD8DAB0AAQkxIY0pAFQAAAcAAQkqFUljAD4AAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn8qAAIMAAgJXxCJGwCjAQAMAAgJXxCJGwCjAQAAAA==.',
Mi='Midnightstar:BAAALgAECgYJDQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAIAAAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.',
Mo='Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgADCgYJBgAAAA==.Moonbayne:BAABLgAECn8hAAIHAAgJmhimHQATAgAHAAgJmhimHQATAgAAAA==.Mooszer:BAABLgAECn8UAAIEAAYJzwPixACyAAAEAAYJzwPixACyAAAAAA==.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBQAAAA==.Mushu:BAABLgAECn8eAAIgAAgJ+RiRBwA7AgAgAAgJ+RiRBwA7AgAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.',
Ne='Nepharim:BAAALgAECgYJBgAAAA==.Nephlim:BAACLgAFFH8XAAMfAAYJWR9NDAB8AQAfAAUJWR9NDAB8AQAhAAEJAAA2MwAAAAAuAAQKfywAAh8ACQmqIcQGAGwDAB8ACQmqIcQGAGwDAAAA.',
Ni='Ninobrown:BAAALgAECgYJEgAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNQAXAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNQAXAG4gAA==.Nizano:BAABLgAECn8WAAIEAAcJjAtcegAwAQAEAAcJjAtcegAwAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAIAAAAAA==.Noryaa:BAABLgAECn8XAAIVAAYJpQVVgQDbAAAVAAYJpQVVgQDbAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.',
Nu='Nuadå:BAABLgAECn8YAAMYAAcJQg7iPwBLAQAYAAcJQg7iPwBLAQAHAAQJbgWMagB3AAAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECgYJCwAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAAALgAECgQJDwAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAEALgADCgEJAQABLgAECggJHAAYABUiAA==.',
Po='Pogo:BAABLgAECn8fAAITAAkJcyQxAwDYAgATAAkJcyQxAwDYAgAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwATAHMkAA==.',
Pr='Pricedd:BAAALgADCgUJBQAAAA==.Prosperina:BAAALgADCgEJAQAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8cAAMDAAcJUQkPEwDTAAABAAcJ5wZ3fgABAQADAAYJvAoPEwDTAAAAAA==.',
Ra='Ranoa:BAAALgADCgkJCQAAAA==.Rastapopulos:BAAALgAECggJCAAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECggJLQAVAHIdAA==.Redrocket:BAAALgAECgEJAQABLgAECgMJBgAIAAAAAA==.Remixed:BAAALgAECgMJAwAAAA==.',
Ri='Rikaku:BAABLgAECn8nAAIVAAcJhBHiPgCzAQAVAAcJhBHiPgCzAQAAAA==.',
Ro='Ronananna:BAAALgADCgkJDwABLgADCgYJBgAIAAAAAA==.Rosemery:BAAALgAECgYJBgAAAA==.',
['Rä']='Räpodac:BAABLgAECn8hAAIWAAcJDwtBHwAYAQAWAAcJDwtBHwAYAQAAAA==.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Saphil:BAAALgADCgkJFAAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Schizo:BAACLgAFFH8IAAIfAAIJtxrARQCYAAAfAAIJtxrARQCYAAAuAAQKfx0AAh8ABwngIfNAADUCAB8ABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAgAAAA==.Sefiroth:BAABLgAECn8oAAILAAcJZRF1UgBAAQALAAcJZRF1UgBAAQAAAA==.Selillea:BAAALgAECgUJBQAAAA==.Semarius:BAAALgAECgEJAgABLgAECggJJgAWAEAfAA==.Semdorii:BAABLgAECn8mAAIWAAgJQB80CABXAgAWAAgJQB80CABXAgAAAA==.Sephywrath:BAABLgAECn84AAIiAAkJoRv9AAB4AgAiAAkJoRv9AAB4AgAAAA==.Seralith:BAABLgAECn8mAAIfAAgJIiFDGgBnAgAfAAgJIiFDGgBnAgAAAA==.Seranight:BAACLgAFFH8LAAMhAAQJkSRvBQCkAQAhAAQJkSRvBQCkAQAfAAEJJwEAAAAAAAAuAAQKfzkAAiEACAl2JmkCAJ4CACEACAl2JmkCAJ4CAAAA.Seven:BAAALgAECgIJBAABLgAECgcJHwABAOYWAA==.Sevenpaws:BAAALgAECgIJAgABLgAECgkJOAAMAG4lAA==.',
Sh='Shadowchi:BAAALgAECgEJAQAAAA==.Shaidon:BAAALgADCgkJEAAAAQ==.Shaly:BAABLgAECn8bAAIXAAYJMgSTwADJAAAXAAYJMgSTwADJAAAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shirohige:BAAALgAECgQJDwAAAA==.Shylan:BAAALgAFFAEJAQAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDQAAAA==.',
Sn='Snayre:BAABLgAECn8uAAITAAkJph2/AwDIAgATAAkJph2/AwDIAgAAAA==.Snipêr:BAAALgAECgYJDgAAAA==.Snowlia:BAABLgAECn8XAAIOAAcJyRPwNQCrAQAOAAcJyRPwNQCrAQAAAA==.',
So='Soularis:BAAALgAECgYJCAAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAAALgAECgcJCgAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJDgAAAA==.',
St='Stalkingwolf:BAABLgAECn8YAAIhAAcJQhXsGAApAQAhAAcJQhXsGAApAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgADCgIJAgAAAA==.',
Sy='Sylailia:BAABLgAECn8tAAIHAAkJHxyXBwCXAgAHAAkJHxyXBwCXAgAAAA==.Syleta:BAAALgADCgMJBAAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAECgkJFAAVABkZAA==.',
Tc='Tcon:BAABLgAECn8UAAITAAcJZxUmEQCxAQATAAcJZxUmEQCxAQAAAA==.',
Td='Tdragon:BAAALgADCgkJEgAAAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thissa:BAABLgAECn8uAAMHAAgJrx/dCgBcAgAHAAgJrx/dCgBcAgAeAAEJSBm4MwAzAAAAAA==.Thundarah:BAAALgADCgcJEAAAAA==.Thundruid:BAAALgADCgUJCgAAAA==.Thuniellas:BAAALgADCggJFwAAAA==.',
Ti='Tiarcis:BAABLgAECn8ZAAIVAAgJJRBpOgCiAQAVAAgJJRBpOgCiAQAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Totemsalot:BAABLgAECn8XAAIOAAkJax9wBAAqAwAOAAkJax9wBAAqAwAAAA==.',
Tr='Treesummoner:BAABLgAECn8nAAQBAAkJYxg3HQA5AgABAAkJYxg3HQA5AgADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgADCggJCQAAAA==.Tritanks:BAABLgAECn8xAAIJAAgJsR/kAwBEAgAJAAgJsR/kAwBEAgAAAA==.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAIAAAAAA==.',
['Tô']='Tôtemic:BAAALgADCgMJAwAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAAALgAECgYJDwAAAA==.Valiente:BAAALgAECgEJAQAAAA==.Vasilia:BAABLgAECn8mAAIhAAcJRRlcDwCYAQAhAAcJRRlcDwCYAQAAAA==.',
Ve='Velanna:BAAALgAECgEJAQAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgADCgYJCwAAAA==.',
Vo='Voclus:BAAALgAECgYJCQAAAA==.',
Wa='Warlodshenu:BAAALgADCgYJBgAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wuwindtang:BAAALgAECgUJCAAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgADCgMJAwAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAIKAAYJqQXYTgC6AAAKAAYJqQXYTgC6AAAAAA==.',
Za='Zachxd:BAABLgAECn8tAAILAAcJvhkkQAB9AQALAAcJvhkkQAB9AQABLgAFFAIJCAAfALcaAA==.Zanthe:BAAALgAECgQJCwAAAA==.Zapanese:BAAALgADCgIJAgAAAA==.Zaptism:BAABLgAECn8hAAMMAAkJqRxXCwCaAgAMAAkJqRxXCwCaAgANAAMJSA0uQgCiAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgADCggJFQAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgUJBwABLgAFFAIJBQAJAB4VAA==.Zhanbrew:BAAALgAFFAEJAQABLgAFFAIJBQAJAB4VAA==.Zhanfury:BAAALgAFFAEJAQABLgAFFAIJBQAJAB4VAA==.',
Zi='Zinder:BAABLgAECn8nAAMjAAgJTAinMwAOAQAjAAgJTAinMwAOAQAkAAEJLANAIAAhAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJmBcyAwAgAgADAAkJmBcyAwAgAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECgcJFAAdAPsXAA==.',
['Öb']='Öboron:BAACLgAFFH8IAAMTAAQJzwFGEwD4AAATAAQJzwFGEwD4AAAUAAEJywFVJQAzAAAuAAQKfy4ABBMACQmLFw4JAFMCABMACQknFg4JAFMCABQACAlWECgqANoBABUABgkpFTJTAG8BAAAA.',
['Üz']='Üz:BAABLgAECn8cAAIWAAYJ/RpvFgBvAQAWAAYJ/RpvFgBvAQAAAA==.',
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
