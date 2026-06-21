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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Hunter-Marksmanship','Paladin-Holy','Unknown-Unknown','DemonHunter-Vengeance','Warrior-Fury','Warrior-Protection','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Monk-Mistweaver','DeathKnight-Frost','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','Druid-Restoration','Priest-Shadow','Evoker-Augmentation','Monk-Brewmaster','Monk-Windwalker','Shaman-Enhancement','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Addely:BAAALgAECgYJCAAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgUJEAAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRqucACbAQAEAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJEQAAAA==.',
Al='Alerion:BAABLgAECn8sAAIFAAkJKhnnDABYAgAFAAkJKhnnDABYAgAAAA==.Allan:BAABLgAECn8rAAIGAAkJbiEEAQDEAgAGAAkJbiEEAQDEAgAAAA==.Alligatorjoe:BAAALgADCgEJAQAAAA==.',
Am='Amaneeda:BAABLgAECn81AAIHAAkJZhCwKgB/AQAHAAkJZhCwKgB/AQAAAA==.Amazonia:BAABLgAECn8fAAIIAAYJ9hYnEQBHAQAIAAYJ9hYnEQBHAQAAAA==.Aminea:BAABLgAFFH8HAAIJAAMJ4wzjMQCrAAAJAAMJ4wzjMQCrAAAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAKAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8HAAILAAIJHhUKDQB3AAALAAIJHhUKDQB3AAAuAAQKfy8AAgsACAkhIuwDAJECAAsACAkhIuwDAJECAAAA.Angyrain:BAAALgAECgUJBgABLgAFFAIJBwALAB4VAA==.Annerila:BAAALgAECgYJBgAAAA==.Antagonis:BAABLgAECn8hAAIDAAcJSA8tEwAZAQADAAcJSA8tEwAZAQAAAA==.',
Ap='Apexchi:BAAALgAECgYJEQAAAA==.Apeximmortal:BAAALgAECgkJDgAAAA==.Apexlight:BAAALgAECgkJEQAAAA==.Apexwar:BAAALgAECgEJAQAAAA==.',
Ar='Arashe:BAAALgAECgUJEwAAAA==.Arewen:BAAALgADCggJEQAAAA==.Arganos:BAABLgAECn8wAAMMAAkJtSbdAQBeAwAMAAkJtSbdAQBeAwANAAYJFxtBGQBzAQAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8WAAIOAAcJ6wTpuwC0AAAOAAcJ6wTpuwC0AAAAAA==.Arkstrife:BAAALgADCgEJAQAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgAECgUJBQAAAA==.Atheîst:BAABLgAECn9GAAMPAAkJfCXMAQBaAwAPAAkJdyXMAQBaAwAQAAgJgCMqBQA4AwAAAA==.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn9LAAMRAAkJjh+rGQB9AgARAAgJHx+rGQB9AgASAAgJiBuZFgAxAgAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAcJFQAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJMAAMALUmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8cAAMTAAcJuRqbFQCwAQATAAcJuRqbFQCwAQAMAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8fAAIUAAYJ9RWkPgB0AQAUAAYJ9RWkPgB0AQAAAA==.Baelanoth:BAABLgAECn8uAAIVAAgJgR4hBgBJAgAVAAgJgR4hBgBJAgAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balerion:BAAALgAECgEJAgAAAA==.Balkazaar:BAAALgAECggJEQAAAA==.Bammbamm:BAABLgAECn8xAAIEAAkJ2grQmwA+AQAEAAkJ2grQmwA+AQAAAA==.Banewreak:BAACLgAFFH8JAAIBAAMJmAvbfwDFAAABAAMJmAvbfwDFAAAuAAQKfzkAAgEACQnCFzMmAEUCAAEACQnCFzMmAEUCAAAA.Banu:BAAALgAECgMJBAAAAA==.Baradin:BAABLgAECn8UAAIJAAcJGBWsKADHAQAJAAcJGBWsKADHAQAAAA==.Barind:BAABLgAECn8yAAQWAAkJFh0yCQCLAgAWAAkJmRwyCQCLAgAIAAcJIxqYJAADAgAXAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgQJCQAAAA==.Betrayer:BAACLgAFFH8QAAIYAAQJTRoOAQAnAQAYAAQJTRoOAQAnAQAuAAQKfyIAAhgACQnuIUAEAAcDABgACQnuIUAEAAcDAAAA.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAABLgAECn8WAAIVAAgJWBPWDACrAQAVAAgJWBPWDACrAQABLgAECgkJHgARAJcNAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Bignfugly:BAAALgADCgYJBgABLgAECgYJHQASAAkaAA==.Biqdonk:BAAALgAECgUJDAAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.Bloodhornz:BAAALgAECgEJAgAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDQABLgADCgYJCwAKAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAKAAAAAA==.Bossdwarf:BAAALgADCgcJCwABLgADCgYJCwAKAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleosévèn:BAAALgAECgcJCgABLgAECgkJRgAPAHwlAA==.Buddro:BAAALgAECgIJAwAAAA==.',
['Bú']='Búbblés:BAAALgAECgcJDQAAAA==.',
Ca='Caatia:BAAALgAFFAIJAgAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgkJJAABAEcWAA==.Carthel:BAABLgAECn8fAAIZAAgJMiBYMQCtAgAZAAgJMiBYMQCtAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCggJDgAAAA==.',
Ce='Cerisi:BAAALgAECgEJAQAAAA==.Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Charley:BAABLgAECn8WAAIZAAYJNAwYBAD+AAAZAAYJNAwYBAD+AAAAAA==.Chasseresse:BAABLgAECn8fAAIXAAYJiBk5XgCMAQAXAAYJiBk5XgCMAQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chi:BAAALgAECgEJAgAAAA==.Chimarr:BAABLgAECn8cAAIaAAgJFiK5EADLAgAaAAgJFiK5EADLAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Cm='Cmondie:BAAALgAECgQJBAAAAA==.',
Co='Coldsploder:BAACLgAFFH8GAAIZAAMJ4gZvjQC+AAAZAAMJ4gZvjQC+AAAuAAQKfy0AAhkACQlaF7szAEoCABkACQlaF7szAEoCAAAA.',
Cr='Crackmonkéy:BAACLgAFFH8FAAIQAAMJPQszNQC3AAAQAAMJPQszNQC3AAAuAAQKfxoABBAACAnYGBArAH0BABAABwk0FBArAH0BAA8ABAmRGVZPAPsAABsABAl0EDhBAO8AAAEuAAUUBAkGABwAkw0A.Cranknspank:BAAALgAECgYJBwAAAA==.Cronoz:BAABLgAECn8mAAMRAAkJMQrbWQAhAQARAAgJUAfbWQAhAQASAAgJ0wnnRAAgAQAAAA==.Crotchshot:BAABLgAECn8mAAIXAAkJnhJCNgAEAgAXAAkJnhJCNgAEAgAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Culodevour:BAAALgAECgYJCAAAAA==.Cursess:BAACLgAFFH8RAAIBAAMJVSIkTQAsAQABAAMJVSIkTQAsAQAuAAQKfzUAAgEACQlxIh4NAOQCAAEACQlxIh4NAOQCAAAA.',
['Có']='Cózmik:BAABLgAECn8UAAIXAAcJ3RZEXQCOAQAXAAcJ3RZEXQCOAQAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn87AAIBAAkJQxUOLgAgAgABAAkJQxUOLgAgAgAAAA==.Dalya:BAAALgAFFAMJAwAAAA==.Dander:BAAALgAECgEJAQAAAA==.Dani:BAAALgAECgEJAgABLgAECgQJBQAKAAAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkridder:BAAALgAECgEJAQAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAABLgAECn8UAAIaAAYJnB1uKwD9AQAaAAYJnB1uKwD9AQAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deathratellr:BAAALgADCgEJAQAAAA==.Deemaius:BAAALgAECgEJAQAAAA==.Dekard:BAAALgAECggJEwAAAA==.Dekariusly:BAAALgAECgQJBAABLgAECggJEwAKAAAAAA==.Demonatrixx:BAAALgAECgYJCQAAAA==.Demonhugger:BAAALgAECgEJAgABLgAECgUJBQAKAAAAAA==.Demonkila:BAAALgAECgUJBgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHwACAFwZAA==.Destinÿ:BAABLgAECn8nAAINAAkJhxWoFwCEAQANAAkJhxWoFwCEAQAAAA==.Devourer:BAABLgAECn84AAIOAAkJOBuiKgAeAgAOAAkJOBuiKgAeAgAAAA==.',
Di='Disploder:BAABLgAECn8sAAIPAAgJdBQLHwDMAQAPAAgJdBQLHwDMAQAAAA==.Dist:BAAALgAECgkJDgAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.Dommiemommie:BAAALgAECgIJAgAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJAQABLgAECgEJAgAKAAAAAA==.Drawwn:BAAALgAECgEJAgAAAA==.Dreathhammer:BAABLgAECn8uAAIJAAkJ1SLEAwBiAwAJAAkJ1SLEAwBiAwAAAA==.Drogo:BAABLgAFFH8GAAIcAAQJkw38MgD2AAAcAAQJkw38MgD2AAAAAA==.Drureds:BAAALgAECgQJBgAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAgJKAAJAIIgAA==.',
Du='Duckcox:BAAALgAECgQJBwAAAA==.Dunadin:BAABLgAECn8ZAAQUAAYJbR0+AgAcAQAUAAYJbR0+AgAcAQAdAAIJ4xJIaQB0AAAeAAEJthXekQA/AAABLgAECgkJPQALAK4mAA==.Dundyrn:BAABLgAECn89AAILAAkJriY3AAB0AwALAAkJriY3AAB0AwAAAA==.',
Dv='Dvera:BAAALgADCgMJAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECgkJPQALAK4mAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAcJEQANABsaAA==.',
Ed='Edmunin:BAEALgAECgYJAwABLgAECgcJAQAKAAAAAA==.',
El='Elememetal:BAABLgAECn8oAAISAAkJvxgIHAABAgASAAkJvxgIHAABAgAAAA==.Elfyparker:BAAALgAECgEJAgAAAA==.Elliott:BAAALgADCgIJAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Fa='Fanmir:BAAALgAECgEJAgAAAA==.Fatpao:BAABLgAECn8YAAITAAYJqheZHwBhAQATAAYJqheZHwBhAQAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAIRAAcJXQtAgQDdAAARAAcJXQtAgQDdAAAAAA==.Fenix:BAAALgADCgEJAgABLgAECgkJLwAbANAUAA==.',
Fi='Filbert:BAABLgAECn8dAAIHAAkJUyGEBwDeAgAHAAkJUyGEBwDeAgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Foldyholds:BAAALgAECgQJBgAAAA==.Fomy:BAAALgAECgEJAQABLgAFFAMJBwAHAEAIAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDgAKAAAAAA==.',
Fr='Fraw:BAAALgADCggJDAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAwAAAA==.Fuzzyhunter:BAAALgAECgUJBwABLgAECgkJLwAbANAUAA==.',
['Fá']='Fálola:BAABLgAECn88AAMRAAgJrxffKADsAQARAAgJrxffKADsAQASAAYJwwOgcACYAAAAAA==.',
Ga='Galestina:BAAALgAECgYJBgAAAA==.Gamblex:BAABLgAECn8VAAINAAUJ2xWTAQCrAAANAAUJ2xWTAQCrAAAAAA==.Garviel:BAABLgAECn8hAAITAAkJQxsMCAB0AgATAAkJQxsMCAB0AgAAAA==.',
Ge='Geeplague:BAAALgAECgIJAQABLgAECggJGQABABMWAA==.Geethatlock:BAABLgAECn8ZAAIBAAgJExa4RwDDAQABAAgJExa4RwDDAQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAABLgAECn8uAAIIAAYJ/BpBAACOAQAIAAYJ/BpBAACOAQAAAA==.Girthlord:BAAALgAECgQJBAABLgAECgkJOwABAEMVAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgAECgEJAQAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravincar:BAAALgAECgYJCAABLgAECgkJPQALAK4mAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAABLgAECn8gAAIRAAgJ8RudHwBTAgARAAgJ8RudHwBTAgAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grogu:BAABLgAECn8eAAIZAAcJBQpZswAcAQAZAAcJBQpZswAcAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJBgAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAFFAMJBAAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgcJBwAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECgkJLgAfAL0fAA==.Hiksham:BAABLgAECn8uAAMfAAkJvR9ABQCSAgAfAAkJnB9ABQCSAgASAAgJBw38OwBFAQAAAA==.',
Ho='Holycheeze:BAAALgADCgcJCgAAAA==.Holyhoof:BAAALgAECgEJAQAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgkJJAABAEcWAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgcJGQARAGwVAA==.',
Ia='Iamreggi:BAAALgAECgQJBgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8vAAIbAAkJ0BS/FwAKAgAbAAkJ0BS/FwAKAgAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Im:BAAALgAFFAMJBAAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
Ir='Irisi:BAAALgADCgUJBQAAAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECgkJKgAgAGkaAA==.Jarlyss:BAABLgAECn8qAAIgAAkJaRp4DAAZAgAgAAkJaRp4DAAZAgAAAA==.Javieraa:BAABLgAECn8gAAIOAAkJYRryJQA2AgAOAAkJYRryJQA2AgAAAA==.',
Jd='Jdai:BAABLgAECn8ZAAIRAAcJbBUXPQC6AQARAAcJbBUXPQC6AQAAAA==.',
Jo='Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAAALgAECgcJEgAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgAECgIJAgAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.Kaishuka:BAAALgAECgEJAgAAAA==.Karlplkngton:BAAALgAECgEJAQAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8hAAIOAAgJDRwJAgDLAQAOAAgJDRwJAgDLAQAuAAQKf0MAAg4ACQlkJLIEADsDAA4ACQlkJLIEADsDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn89AAIYAAkJshDwIABxAQAYAAkJshDwIABxAQAAAA==.Kikyo:BAAALgAECgYJEgAAAA==.Kimmi:BAAALgAECgUJEAAAAA==.Kinzen:BAABLgAECn8xAAIfAAcJhSDADQDTAQAfAAcJhSDADQDTAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIhAAYJAyEjDQDmAQAhAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8jAAIZAAgJPApIkABXAQAZAAgJPApIkABXAQAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgAECgIJAgABLgAECgkJOwAQADYdAA==.',
Le='Lechwe:BAABLgAECn85AAIRAAkJFBxhEADNAgARAAkJFBxhEADNAgAAAA==.Legolase:BAAALgAECgEJAQAAAA==.Legonator:BAAALgAECgUJCAAAAA==.Lenry:BAAALgAFFAEJAQAAAA==.',
Li='Lichmajor:BAABLgAECn8nAAIiAAkJ6BjjRwDqAQAiAAkJ6BjjRwDqAQAAAA==.Liion:BAAALgADCgcJBwAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.Littlefang:BAAALgAECgQJBAAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn8qAAMUAAcJICGaFQBtAgAUAAcJICGaFQBtAgAeAAQJJxhjAQDbAAAAAA==.Lovepet:BAABLgAECn8/AAMXAAkJ9x10GgCHAgAXAAkJ9x10GgCHAgAIAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAABLgAECn8VAAIiAAYJyhTckQBCAQAiAAYJyhTckQBCAQAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn83AAIZAAkJbiCAIgCTAgAZAAkJbiCAIgCTAgAAAA==.Lunavis:BAAALgAECgcJDgABLgAECgkJGgAaAPUNAA==.',
Ly='Lyda:BAABLgAECn89AAIaAAkJShv6GAB+AgAaAAkJShv6GAB+AgAAAA==.',
Ma='Magice:BAABLgAECn8fAAIZAAYJKQP5CwBYAAAZAAYJKQP5CwBYAAAAAA==.Magmara:BAAALgAECgUJBQAAAA==.Malibubarbie:BAABLgAECn82AAIPAAkJuw7UJwCHAQAPAAkJuw7UJwCHAQAAAA==.Malthael:BAAALgAECgIJAwAAAA==.Malystron:BAABLgAECn8UAAIEAAkJ/wrWfAB1AQAEAAkJ/wrWfAB1AQAAAA==.Maneevent:BAABLgAECn8ZAAQXAAYJGRfziAAtAQAXAAYJGRfziAAtAQAWAAEJ1wR/agAoAAAIAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn87AAMQAAkJNh2cBwAAAwAQAAkJNh2cBwAAAwAbAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn8+AAIXAAkJFgobVACnAQAXAAkJFgobVACnAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8bAAQgAAcJsBrLAABAAQAhAAUJTxvZAgCmAQAgAAQJNxnLAABAAQAHAAMJpxaxBgBZAAAuAAQKfyoABCEACQkiI0sCAAgDACEACQkiI0sCAAgDACAAAQkxIY0pAFQAAAcAAQkqFdWDAEEAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn80AAIPAAkJCRHkIQCzAQAPAAkJCRHkIQCzAQAAAA==.',
Mi='Midnightstar:BAABLgAECn8VAAIaAAYJqxKvTwBQAQAaAAYJqxKvTwBQAQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAKAAAAAA==.Mimolette:BAAALgAECgEJAQAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.Miseree:BAAALgAECgcJBwAAAA==.',
Mo='Modest:BAAALgAECgUJBQAAAA==.Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgAECgEJAgAAAA==.Moonbayne:BAABLgAECn8uAAIHAAkJrBo9DwBrAgAHAAkJrBo9DwBrAgAAAA==.Mooszer:BAABLgAECn8fAAIEAAgJWwQ23ADjAAAEAAgJWwQ23ADjAAAAAA==.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBwAAAA==.Mushu:BAABLgAECn8tAAIjAAkJSBr6BQCuAgAjAAkJSBr6BQCuAgAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.Natre:BAAALgADCgIJAgAAAA==.',
Ne='Nepharim:BAAALgAECgYJCwAAAA==.Nephlim:BAACLgAFFH8fAAMiAAgJ3x+vAQD4AQAiAAcJ3x+vAQD4AQAkAAEJAADNVQAAAAAuAAQKfzEAAiIACQnmIcQGAGwDACIACQnmIcQGAGwDAAAA.Nergal:BAAALgADCgMJAwAAAA==.',
Ni='Ninobrown:BAAALgAECgYJEwAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNwAZAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNwAZAG4gAA==.Nizano:BAABLgAECn8iAAIEAAcJHgwztQAXAQAEAAcJHgwztQAXAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAKAAAAAA==.Noobie:BAAALgADCgYJCAAAAA==.Noryaa:BAABLgAECn8fAAIXAAYJQwYhrwDmAAAXAAYJQwYhrwDmAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.Notfurry:BAAALgAECgIJAgAAAA==.',
Nu='Nuadå:BAABLgAECn8pAAMaAAcJthGyRQB6AQAaAAcJthGyRQB6AQAHAAQJbgWMagB3AAAAAA==.Nuala:BAAALgADCgUJBQAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECggJDgAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAABLgAECn8bAAMbAAUJJBG8SADsAAAbAAUJJBG8SADsAAAPAAQJTBGUAgCkAAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAAALgADCgEJAQABLgAECggJHAAaABYiAA==.Orkid:BAAALgAECgEJAQAAAA==.',
Pa='Pawsome:BAAALgAECgQJBAABLgAECgkJOwASAOMZAA==.',
Ph='Phelyx:BAABLgAFFH8FAAIaAAMJJwSZZwBMAAAaAAMJJwSZZwBMAAAAAA==.',
Po='Pogo:BAABLgAECn8fAAIWAAkJdiR9AgAbAwAWAAkJdiR9AgAbAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwAWAHYkAA==.',
Pr='Pricedd:BAAALgADCgcJCAAAAA==.Prosperina:BAAALgADCgQJBAAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8lAAMDAAgJdQgkHQC+AAABAAgJhgcLmQALAQADAAYJvAokHQC+AAAAAA==.',
Qu='Quetzani:BAAALgAECgEJAQAAAA==.',
Ra='Ranoa:BAAALgADCgkJCQAAAA==.Rastapopulos:BAAALgAECggJCgAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECgkJPwAXAPcdAA==.Redrocket:BAAALgAECgEJAgABLgAECgQJCQAKAAAAAA==.Rekkash:BAAALgAECgEJAQAAAA==.Remixed:BAAALgAECgQJBgAAAA==.Reptilectric:BAAALgAECgUJDQAAAA==.Retxd:BAAALgADCgIJAgABLgAECgQJBQAKAAAAAA==.',
Ri='Rikaku:BAABLgAECn81AAIXAAcJoBLiPgCzAQAXAAcJoBLiPgCzAQAAAA==.',
Ro='Roastbeef:BAAALgAECgEJAQAAAA==.Ronananna:BAAALgADCgkJDwABLgADCgYJBgAKAAAAAA==.Rosemery:BAAALgAECgYJBwAAAA==.',
['Râ']='Râpödac:BAAALgADCgIJAgAAAA==.',
['Rä']='Räpodac:BAABLgAECn8rAAIYAAcJlg3uLAAaAQAYAAcJlg3uLAAaAQAAAA==.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Sajae:BAAALgAECgEJAQAAAA==.Saphil:BAAALgAECgEJAQAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Scarypantz:BAAALgAECgEJAQAAAA==.Schizo:BAACLgAFFH8KAAIiAAIJtxqO1ACMAAAiAAIJtxqO1ACMAAAuAAQKfx0AAiIABwngIfNAADUCACIABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAwAAAA==.Sefiroth:BAACLgAFFH8FAAIOAAMJfwrydACcAAAOAAMJfwrydACcAAAuAAQKfy4AAg4ABwnTFSlbAHYBAA4ABwnTFSlbAHYBAAAA.Selillea:BAAALgAECgYJBwAAAA==.Semarius:BAAALgAECgEJAwABLgAECgkJNwAYAKQhAA==.Semdorii:BAABLgAECn83AAIYAAkJpCGeBAD+AgAYAAkJpCGeBAD+AgAAAA==.Sephywrath:BAABLgAECn8+AAIlAAkJoRs6AgBIAgAlAAkJoRs6AgBIAgAAAA==.Seralith:BAABLgAECn9IAAMiAAkJkyUqAwBsAwAiAAkJkyUqAwBsAwAVAAUJayGwDgCKAQAAAA==.Seranight:BAACLgAFFH8TAAMkAAQJtiRAEACAAQAkAAQJtiRAEACAAQAiAAEJJwE4KQEnAAAuAAQKf1QAAiQACQmTJmwAAHcDACQACQmTJmwAAHcDAAAA.Seven:BAAALgAECgIJBAABLgAECgkJJAABAEcWAA==.Sevenpaws:BAAALgAECgcJDAABLgAECgkJRgAPAHwlAA==.',
Sh='Shadowchi:BAABLgAECn8fAAIDAAYJtwk5HQC+AAADAAYJtwk5HQC+AAAAAA==.Shaidon:BAAALgAECgYJBgAAAQ==.Shaly:BAABLgAECn8jAAIZAAgJPwZ3qAAtAQAZAAgJPwZ3qAAtAQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shinjihirako:BAAALgAECgQJBwAAAA==.Shirohige:BAABLgAECn8eAAIgAAUJ4w/kAwBfAAAgAAUJ4w/kAwBfAAAAAA==.Shlonglord:BAAALgADCgIJAgAAAA==.Shylan:BAABLgAFFH8FAAINAAEJGB4TKgBMAAANAAEJGB4TKgBMAAAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDgAAAA==.',
Sn='Snaarf:BAAALgADCgEJAQABLgAECgUJGwAcAKsEAA==.Snayre:BAACLgAFFH8OAAIWAAQJohlhDgBSAQAWAAQJohlhDgBSAQAuAAQKfzUAAhYACQlxHuAFAMcCABYACQlxHuAFAMcCAAAA.Snipêr:BAABLgAECn8cAAIXAAgJtBN5SADIAQAXAAgJtBN5SADIAQAAAA==.Snowlia:BAACLgAFFH8KAAIRAAMJahM4UgCuAAARAAMJahM4UgCuAAAuAAQKfyEAAxEACQkxE/A1AKsBABEACQkxE/A1AKsBABIAAQk3D0iqACwAAAAA.',
So='Soularis:BAAALgAECgYJCAAAAA==.Soulslice:BAEALgAECggJCAABLgAECgQJEQAKAAAAAA==.Sovrano:BAAALgADCgEJAQAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAABLgAECn8bAAMmAAcJvwbbEQDtAAAmAAcJvwbbEQDtAAAjAAEJ6gG4RgAXAAAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJEAAAAA==.',
St='Stalkingwolf:BAABLgAECn8pAAIkAAcJRxhGGQCWAQAkAAcJRxhGGQCWAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgAECgYJEQAAAA==.',
Sy='Sylailia:BAACLgAFFH8LAAIHAAMJKAuABACgAAAHAAMJKAuABACgAAAuAAQKfzsAAgcACQm3HbgJALgCAAcACQm3HbgJALgCAAAA.Syleta:BAAALgADCgMJBAAAAA==.Sylvia:BAAALgAECgEJAgAAAA==.',
['Sí']='Síenna:BAAALgAECgEJAwAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAMJBAAKAAAAAA==.',
Tc='Tcon:BAABLgAECn8UAAIWAAcJRBWpIQCPAQAWAAcJRBWpIQCPAQAAAA==.',
Td='Tdragon:BAAALgADCgkJEgABLgAECgkJLwAbANAUAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thissa:BAABLgAECn8uAAMHAAgJrx9qEQBPAgAHAAgJrx9qEQBPAgAhAAEJSBm4MwAzAAABLgAFFAQJBgAcAJMNAA==.Thundarah:BAAALgADCgcJFwAAAA==.Thundielocks:BAAALgADCgkJCQAAAA==.Thundruid:BAAALgADCgkJEAAAAA==.Thuniellas:BAAALgADCggJGQAAAA==.',
Ti='Tiarcis:BAABLgAECn81AAIXAAkJbBiqIgBZAgAXAAkJbBiqIgBZAgAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Tostitos:BAAALgADCgkJCQABLgAECgkJLwAbANAUAA==.Totemsalot:BAACLgAFFH8MAAIRAAQJjBu1KwA1AQARAAQJjBu1KwA1AQAuAAQKfxsAAhEACQnGI7QDAIIDABEACQnGI7QDAIIDAAAA.',
Tr='Treesummoner:BAABLgAECn8tAAQBAAkJjRjrKgAuAgABAAkJjRjrKgAuAgADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgAECgIJAgAAAA==.Tritanks:BAABLgAECn9JAAILAAkJWCQbAQAzAwALAAkJWCQbAQAzAwAAAA==.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAKAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAABLgAECn8UAAIbAAcJpgzbPAAdAQAbAAcJpgzbPAAdAQAAAA==.Vali:BAAALgAECgUJBQAAAA==.Valiente:BAAALgAECgIJAgAAAA==.Valkah:BAAALgAECgEJAQAAAA==.Vasilia:BAABLgAECn89AAIkAAkJRRk2EAAIAgAkAAkJRRk2EAAIAgAAAA==.',
Ve='Velanna:BAAALgAECgIJAgAAAA==.Vexara:BAAALgAECgYJDwAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgAFFAEJAgAAAA==.',
Vo='Voclus:BAAALgAECgYJEwAAAA==.',
Vy='Vykyrnarreia:BAAALgADCgMJAwAAAA==.',
Wa='Wall:BAAALgAECgYJEwAAAA==.Warlodshenu:BAAALgADCgcJCwAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
We='Weyaeh:BAAALgADCgIJAgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wulfbayne:BAAALgAECgQJBAAAAA==.Wuwindtang:BAAALgAECgUJDAAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgAECgEJAQAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAIMAAYJqQXwbACxAAAMAAYJqQXwbACxAAAAAA==.Xiletank:BAAALgAECgUJBQAAAA==.',
Ya='Yasutorasado:BAAALgAECgEJAgAAAA==.',
Za='Zachxd:BAABLgAECn88AAIOAAcJ6RkYUgCPAQAOAAcJ6RkYUgCPAQABLgAFFAIJCgAiALcaAA==.Zanthe:BAAALgAECgQJEQAAAA==.Zapanese:BAAALgADCgMJBAAAAA==.Zapt:BAAALgAECgIJAgAAAA==.Zaptism:BAABLgAECn87AAMPAAkJMCFGCADnAgAPAAkJMCFGCADnAgAQAAUJhQ6hRwDoAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgADCgkJJgAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgYJEAABLgAFFAIJBwALAB4VAA==.Zhanbear:BAAALgAECggJDAABLgAFFAIJBwALAB4VAA==.Zhanbrew:BAACLgAFFH8OAAIdAAMJJiJ8IAAsAQAdAAMJJiJ8IAAsAQAuAAQKfyQAAh0ACQnhIu8CACcDAB0ACQnhIu8CACcDAAEuAAUUAgkHAAsAHhUA.Zhanfury:BAAALgAFFAEJAQABLgAFFAIJBwALAB4VAA==.',
Zi='Zinder:BAABLgAECn8nAAMcAAgJTQg8SgADAQAcAAgJTQg8SgADAQAmAAEJLAPXKwAeAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJjRe7BQAOAgADAAkJjRe7BQAOAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECgkJKgAgAGkaAA==.',
['Öb']='Öboron:BAACLgAFFH8JAAMWAAQJVgMNHgDiAAAWAAQJVgMNHgDiAAAIAAEJywHRPAAsAAAuAAQKfy4ABBYACQmMF04PADkCABYACQknFk4PADkCAAgACAlWECgqANoBABcABgkpFTJTAG8BAAAA.',
['Üz']='Üz:BAABLgAECn8kAAIYAAgJvhbQGAC8AQAYAAgJvhbQGAC8AQAAAA==.',
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
