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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Hunter-Marksmanship','Paladin-Holy','Unknown-Unknown','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Elemental','Warrior-Fury','Warrior-Protection','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Shaman-Restoration','Warrior-Arms','Monk-Mistweaver','DeathKnight-Frost','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','Druid-Restoration','Priest-Shadow','Evoker-Augmentation','Monk-Windwalker','Shaman-Enhancement','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Addely:BAAALgAECgYJCAAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgUJEAAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRqucACbAQAEAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJEQAAAA==.',
Al='Alerion:BAABLgAECn8sAAIFAAkJKhnoDABYAgAFAAkJKhnoDABYAgAAAA==.Allan:BAABLgAECn8rAAIGAAkJbiEEAQDEAgAGAAkJbiEEAQDEAgAAAA==.Alligatorjoe:BAAALgADCgEJAQAAAA==.',
Am='Amaneeda:BAABLgAECn81AAIHAAkJZhCyKgB/AQAHAAkJZhCyKgB/AQAAAA==.Amazonia:BAABLgAECn8hAAIIAAYJ9xYoEQBHAQAIAAYJ9xYoEQBHAQAAAA==.Aminea:BAABLgAFFH8NAAIJAAQJ9Q37CwClAAAJAAQJ9Q37CwClAAAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAKAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8HAAILAAIJHhUMDQB3AAALAAIJHhUMDQB3AAAuAAQKfy8AAgsACAkhIuwDAJECAAsACAkhIuwDAJECAAEuAAUUBAkUAAwAYiEA.Angyrain:BAAALgAECgUJBgABLgAFFAQJFAAMAGIhAA==.Annerila:BAAALgAECgYJBgAAAA==.Antagonis:BAABLgAECn8iAAIDAAcJSA8tEwAZAQADAAcJSA8tEwAZAQAAAA==.',
Ap='Apexchi:BAAALgAECgYJEQAAAA==.Apeximmortal:BAAALgAECgkJDgAAAA==.Apexlight:BAAALgAECgkJEQAAAA==.Apexwar:BAAALgAECgEJAQAAAA==.',
Ar='Arashe:BAABLgAECn8aAAINAAYJagTrBwCcAAANAAYJagTrBwCcAAAAAA==.Arewen:BAAALgADCggJEQAAAA==.Arganos:BAABLgAECn8wAAMOAAkJtSbdAQBeAwAOAAkJtSbdAQBeAwAPAAYJFxtAGQBzAQAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8WAAIQAAcJ6wTouwC0AAAQAAcJ6wTouwC0AAAAAA==.Arkstrife:BAAALgADCgEJAQAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgAECgUJBQAAAA==.Atheîst:BAACLgAFFH8GAAMRAAMJJSYTEgA8AQARAAMJlyUTEgA8AQASAAIJgyPWDADGAAAuAAQKf0cAAxEACQl8JcwBAFoDABEACQl3JcwBAFoDABIACAmAIyoFADgDAAAA.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn9MAAMTAAkJjh+sGQB9AgATAAgJHx+sGQB9AgANAAgJgB2YFgAxAgAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAcJFQAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJMAAOALUmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8cAAMUAAcJuRqcFQCwAQAUAAcJuRqcFQCwAQAOAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8fAAIVAAYJ9RWiPgB0AQAVAAYJ9RWiPgB0AQAAAA==.Baelanoth:BAABLgAECn8wAAIWAAkJIh0iBgBJAgAWAAkJIh0iBgBJAgAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balerion:BAAALgAECgEJAgAAAA==.Balkazaar:BAAALgAECggJEQAAAA==.Bammbamm:BAABLgAECn8xAAIEAAkJ2grQmwA+AQAEAAkJ2grQmwA+AQAAAA==.Banewreak:BAACLgAFFH8KAAIBAAMJmAvHfwDFAAABAAMJmAvHfwDFAAAuAAQKfzkAAgEACQnCFzMmAEUCAAEACQnCFzMmAEUCAAAA.Banu:BAAALgAECgMJBAAAAA==.Baradin:BAABLgAECn8UAAIJAAcJGBWuKADHAQAJAAcJGBWuKADHAQAAAA==.Barind:BAABLgAECn8yAAQXAAkJFh0xCQCLAgAXAAkJmRwxCQCLAgAIAAcJIxqYJAADAgAYAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgQJCQAAAA==.Betrayer:BAACLgAFFH8QAAIZAAQJTRqyAwAiAQAZAAQJTRqyAwAiAQAuAAQKfyIAAhkACQnuIT8EAAcDABkACQnuIT8EAAcDAAAA.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAABLgAECn8WAAIWAAgJWBPWDACrAQAWAAgJWBPWDACrAQABLgAECgkJHgATAJcNAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Bignfugly:BAAALgADCgYJBgABLgAECgcJHwANAE4aAA==.Biqdonk:BAAALgAECgUJDAAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.Bloodhornz:BAAALgAECgEJAwAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDQABLgADCgYJCwAKAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAKAAAAAA==.Bossdwarf:BAAALgADCgcJCwABLgADCgYJCwAKAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleosévèn:BAAALgAECgcJEQABLgAFFAMJBgARACUmAA==.Buddro:BAAALgAECgIJAwAAAA==.',
['Bú']='Búbblés:BAAALgAECgcJDQAAAA==.',
Ca='Caatia:BAAALgAFFAIJAgAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgkJJAABAEcWAA==.Carthel:BAABLgAECn8fAAIaAAgJMiBYMQCtAgAaAAgJMiBYMQCtAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCggJDgAAAA==.',
Ce='Cerisi:BAAALgAECgEJAQAAAA==.Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Charley:BAABLgAECn8YAAIaAAcJ9AvNCAAmAQAaAAcJ9AvNCAAmAQAAAA==.Chasseresse:BAABLgAECn8fAAIYAAYJiBk1XgCMAQAYAAYJiBk1XgCMAQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chi:BAAALgAECgEJAgAAAA==.Chimarr:BAABLgAECn8cAAIbAAgJFiK5EADLAgAbAAgJFiK5EADLAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Cm='Cmondie:BAAALgAECgQJBAAAAA==.',
Co='Coldsploder:BAACLgAFFH8IAAIaAAMJ4gZSjQC+AAAaAAMJ4gZSjQC+AAAuAAQKfy0AAhoACQlaF7gzAEoCABoACQlaF7gzAEoCAAAA.',
Cr='Crackmonkéy:BAACLgAFFH8IAAISAAMJpQ2eEACgAAASAAMJpQ2eEACgAAAuAAQKfxoABBIACAnYGBIrAH0BABIABwk0FBIrAH0BABEABAmRGVZPAPsAABwABAl0EDhBAO8AAAEuAAUUBAkGAB0Akw0A.Cranknspank:BAAALgAECgYJBwAAAA==.Cronoz:BAABLgAECn8mAAMTAAkJMQrbWQAhAQATAAgJUAfbWQAhAQANAAgJ0wnpRAAgAQAAAA==.Crotchshot:BAABLgAECn8oAAIYAAkJFxNBNgAEAgAYAAkJFxNBNgAEAgAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Culodevour:BAAALgAECgYJCAAAAA==.Cursess:BAACLgAFFH8SAAIBAAMJVSIDTQAsAQABAAMJVSIDTQAsAQAuAAQKfzUAAgEACQlxIh4NAOQCAAEACQlxIh4NAOQCAAAA.',
['Có']='Cózmik:BAABLgAECn8UAAIYAAcJ3RZBXQCOAQAYAAcJ3RZBXQCOAQAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn88AAIBAAkJwBUOLgAgAgABAAkJwBUOLgAgAgAAAA==.Dalya:BAAALgAFFAMJBAAAAA==.Dander:BAAALgAECgEJAQAAAA==.Dani:BAAALgAECgEJAgABLgAECgQJBQAKAAAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkridder:BAAALgAECgEJAQAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAABLgAECn8UAAIbAAYJnB1rKwD9AQAbAAYJnB1rKwD9AQAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deathratellr:BAAALgADCgEJAQAAAA==.Deemaius:BAAALgAECgEJAgAAAA==.Dekard:BAAALgAECggJEwAAAA==.Dekariusly:BAAALgAECgQJBAABLgAECggJEwAKAAAAAA==.Deltee:BAAALgAECgMJAwABLgAECgkJLQAVAGQhAA==.Demonatrixx:BAAALgAECgYJCQAAAA==.Demonhugger:BAAALgAECgEJAgABLgAECgUJBQAKAAAAAA==.Demonkila:BAAALgAECgUJBgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHwACAFwZAA==.Destinÿ:BAABLgAECn8nAAIPAAkJhxWmFwCEAQAPAAkJhxWmFwCEAQAAAA==.Devourer:BAABLgAECn84AAIQAAkJOBueKgAeAgAQAAkJOBueKgAeAgAAAA==.',
Di='Disploder:BAABLgAECn8sAAIRAAgJdBQNHwDMAQARAAgJdBQNHwDMAQAAAA==.Dist:BAAALgAECgkJDgAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.Dommiemommie:BAAALgAECgIJAgAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJBAAAAA==.Drawwn:BAAALgAECgEJAgABLgAECgEJBAAKAAAAAA==.Dreathhammer:BAABLgAECn8uAAIJAAkJ1SLDAwBiAwAJAAkJ1SLDAwBiAwAAAA==.Drogo:BAABLgAFFH8GAAIdAAQJkw34MgD2AAAdAAQJkw34MgD2AAAAAA==.Drureds:BAAALgAECgQJCQAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAgJKAAJAIIgAA==.',
Du='Duckcox:BAAALgAECgQJBwAAAA==.Dunadin:BAABLgAECn8ZAAQVAAYJbR2rBgAbAQAVAAYJbR2rBgAbAQAMAAIJ4xJKaQB0AAAeAAEJthXekQA/AAABLgAECgkJPwALAK4mAA==.Dundyrn:BAABLgAECn8/AAILAAkJriY3AAB0AwALAAkJriY3AAB0AwAAAA==.Dunhara:BAAALgAECgEJAQABLgAECgkJPwALAK4mAA==.',
Dv='Dvera:BAAALgADCgMJAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECgkJPwALAK4mAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAgJEgAPAP0aAA==.',
Ed='Edmunin:BAEALgAECgYJAwAAAA==.',
El='Elememetal:BAABLgAECn8pAAINAAkJvxgHHAABAgANAAkJvxgHHAABAgAAAA==.Elfyparker:BAAALgAECgEJAgAAAA==.Elliott:BAAALgADCgIJAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Ex='Exí:BAAALgAECgMJAwAAAA==.',
Fa='Fanmir:BAAALgAECgEJAgAAAA==.Fatpao:BAABLgAECn8dAAIUAAYJjRs+AQBfAQAUAAYJjRs+AQBfAQAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAITAAcJXQtGgQDdAAATAAcJXQtGgQDdAAAAAA==.Fenix:BAAALgADCgEJAgABLgAECgkJMQAcAPoVAA==.',
Fi='Filbert:BAABLgAECn8dAAIHAAkJUyGEBwDeAgAHAAkJUyGEBwDeAgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Foldyholds:BAAALgAECgUJCAAAAA==.Fomy:BAAALgAECgEJAQABLgAFFAMJCAAHAEAIAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDgAKAAAAAA==.',
Fr='Fraw:BAAALgADCggJDAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAwAAAA==.Fuzzyhunter:BAAALgAECgUJBwABLgAECgkJMQAcAPoVAA==.',
['Fá']='Fálola:BAABLgAECn89AAMTAAgJrxffKADsAQATAAgJrxffKADsAQANAAYJwwOjcACYAAAAAA==.',
Ga='Galestina:BAAALgAECgYJBgAAAA==.Gamblex:BAABLgAECn8cAAIPAAYJxBRfAgARAQAPAAYJxBRfAgARAQAAAA==.Garviel:BAABLgAECn8jAAIUAAkJCRwNCAB0AgAUAAkJCRwNCAB0AgAAAA==.',
Ge='Geeblast:BAAALgAECgMJAwABLgAECggJGQABABMWAA==.Geeplague:BAAALgAECgMJBAABLgAECggJGQABABMWAA==.Geethatlock:BAABLgAECn8ZAAIBAAgJExa5RwDDAQABAAgJExa5RwDDAQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAABLgAECn8wAAIIAAcJjxiHAAC9AQAIAAcJjxiHAAC9AQAAAA==.Girthlord:BAAALgAECgQJBAABLgAECgkJPAABAMAVAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgAECgEJAQAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravincar:BAAALgAFFAEJAQABLgAECgkJPwALAK4mAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAABLgAECn8nAAITAAgJ8RtPAwCaAQATAAgJ8RtPAwCaAQAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grogu:BAABLgAECn8eAAIaAAcJBQpeswAcAQAaAAcJBQpeswAcAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJBgAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAFFAMJBAAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgcJBwAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECgkJLgAfAL0fAA==.Hiksham:BAABLgAECn8uAAMfAAkJvR9ABQCSAgAfAAkJnB9ABQCSAgANAAgJBw3+OwBFAQAAAA==.',
Ho='Holycheeze:BAAALgAECgEJAQAAAA==.Holyhoof:BAAALgAECgEJAQAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgkJJAABAEcWAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgcJGgATAMEVAA==.',
Ia='Iamreggi:BAAALgAECgQJBgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8xAAIcAAkJ+hW/FwAKAgAcAAkJ+hW/FwAKAgAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Im:BAAALgAFFAMJBAAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
Ir='Irisi:BAAALgADCgUJBQAAAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECgkJKgAgAGkaAA==.Jarlyss:BAABLgAECn8qAAIgAAkJaRp4DAAZAgAgAAkJaRp4DAAZAgAAAA==.Javieraa:BAABLgAECn8gAAIQAAkJYRruJQA2AgAQAAkJYRruJQA2AgAAAA==.',
Jd='Jdai:BAABLgAECn8aAAITAAcJwRUYPQC6AQATAAcJwRUYPQC6AQAAAA==.',
Jo='Jocecilla:BAAALgAFFAEJAQABLgAFFAIJAgAKAAAAAA==.Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAAALgAECggJEwAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgAECgIJAgAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.Kaishuka:BAAALgAECgEJAgAAAA==.Karlplkngton:BAAALgAECgEJAQAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8hAAIQAAgJDRyDBgC6AQAQAAgJDRyDBgC6AQAuAAQKf0MAAhAACQlkJLEEADsDABAACQlkJLEEADsDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn89AAIZAAkJshDzIABxAQAZAAkJshDzIABxAQAAAA==.Kikyo:BAAALgAECgYJEgAAAA==.Kimmi:BAAALgAECgUJEAAAAA==.Kinzen:BAABLgAECn8xAAIfAAcJhSDADQDTAQAfAAcJhSDADQDTAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIhAAYJAyEjDQDmAQAhAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8jAAIaAAgJPApLkABXAQAaAAgJPApLkABXAQAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgAECgIJAgABLgAECgkJPAASAO8eAA==.',
Le='Lechwe:BAABLgAECn8/AAITAAkJLxxhEADNAgATAAkJLxxhEADNAgAAAA==.Legolase:BAAALgAECgEJAQAAAA==.Legonator:BAAALgAECgUJCAAAAA==.Lenry:BAAALgAFFAEJAQAAAA==.',
Li='Lichmajor:BAABLgAECn8nAAIiAAkJ6BjnRwDqAQAiAAkJ6BjnRwDqAQAAAA==.Liion:BAAALgADCggJDgAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.Littlefang:BAAALgAECgQJBAAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn8tAAMVAAkJZCGWFQBtAgAVAAcJICGWFQBtAgAeAAcJ6BY5AQCmAQAAAA==.Lovepet:BAABLgAECn9CAAMYAAkJ9x1zGgCHAgAYAAkJ9x1zGgCHAgAIAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAABLgAECn8iAAIiAAcJmhaSBAB7AQAiAAcJmhaSBAB7AQAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn83AAIaAAkJbiB+IgCTAgAaAAkJbiB+IgCTAgAAAA==.Lunavis:BAAALgAECgcJDgABLgAECgkJGgAbAPUNAA==.',
Ly='Lyda:BAABLgAECn89AAIbAAkJShv5GAB+AgAbAAkJShv5GAB+AgAAAA==.',
Ma='Magice:BAABLgAECn8mAAIaAAYJkAVxEAC6AAAaAAYJkAVxEAC6AAAAAA==.Magmara:BAAALgAECgUJBQAAAA==.Malibubarbie:BAABLgAECn82AAIRAAkJuw7bJwCHAQARAAkJuw7bJwCHAQAAAA==.Malthael:BAAALgAECgIJAwAAAA==.Malystron:BAABLgAECn8UAAIEAAkJ/wrTfAB1AQAEAAkJ/wrTfAB1AQAAAA==.Maneevent:BAABLgAECn8ZAAQYAAYJGRfwiAAtAQAYAAYJGRfwiAAtAQAXAAEJ1wSAagAoAAAIAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn88AAMSAAkJ7x6bBwAAAwASAAkJ7x6bBwAAAwAcAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn9BAAIYAAkJUQoaVACnAQAYAAkJUQoaVACnAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8bAAQgAAcJsBpjAgBKAQAhAAUJTxvaAgCmAQAgAAQJNxljAgBKAQAHAAMJpxbOEwBWAAAuAAQKfyoABCEACQkiI0sCAAgDACEACQkiI0sCAAgDACAAAQkxIY0pAFQAAAcAAQkqFdODAEEAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn81AAIRAAkJCRHnIQCzAQARAAkJCRHnIQCzAQAAAA==.',
Mi='Midnightstar:BAABLgAECn8VAAIbAAYJqxKtTwBQAQAbAAYJqxKtTwBQAQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAKAAAAAA==.Mimolette:BAAALgAECgMJAwAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.Miseree:BAAALgAECgcJBwAAAA==.',
Mo='Modest:BAAALgAECgUJBQAAAA==.Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgAECgEJAgAAAA==.Moonbayne:BAABLgAECn8wAAIHAAkJvRs/DwBrAgAHAAkJvRs/DwBrAgAAAA==.Mooszer:BAACLgAFFH8FAAIEAAIJCwRmJwB3AAAEAAIJCwRmJwB3AAAuAAQKfyAAAgQACQlABTncAOMAAAQACQlABTncAOMAAAAA.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBwAAAA==.Mushu:BAABLgAECn8tAAIjAAkJSBr5BQCuAgAjAAkJSBr5BQCuAgAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.Natre:BAAALgADCgIJAgAAAA==.',
Ne='Nepharim:BAAALgAECgYJCwAAAA==.Nephlim:BAACLgAFFH8fAAMiAAgJ3x95BgDtAQAiAAcJ3x95BgDtAQAkAAEJAADMVQAAAAAuAAQKfzEAAiIACQnmIcQGAGwDACIACQnmIcQGAGwDAAAA.Nergal:BAAALgADCgMJAwAAAA==.',
Ni='Ninobrown:BAAALgAECgYJEwAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNwAaAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNwAaAG4gAA==.Nizano:BAABLgAECn8jAAIEAAcJHgwytQAXAQAEAAcJHgwytQAXAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAKAAAAAA==.Noobie:BAAALgADCgYJCAAAAA==.Noryaa:BAABLgAECn8fAAIYAAYJQwYnrwDmAAAYAAYJQwYnrwDmAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.Notfurry:BAAALgAECgIJAgAAAA==.',
Nu='Nuadå:BAABLgAECn8qAAMbAAcJthGwRQB6AQAbAAcJthGwRQB6AQAHAAQJbgWMagB3AAAAAA==.Nuala:BAAALgADCgUJBQAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECggJDgAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAABLgAECn8iAAMRAAYJURS3AwAbAQARAAUJnhK3AwAbAQAcAAUJshPASADsAAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAAALgADCgEJAQABLgAECggJHAAbABYiAA==.Orkid:BAAALgAECgEJAgAAAA==.',
Pa='Pawsome:BAAALgAECgQJBAABLgAECgkJOwANAOMZAA==.',
Pe='Penzmoo:BAAALgADCgEJAQAAAA==.',
Ph='Phelyx:BAACLgAFFH8FAAIbAAMJJwSYZwBMAAAbAAMJJwSYZwBMAAAuAAQKfxkAAxsACQmfE0QBABsCABsACQmfE0QBABsCAAcAAgkiBQiIADoAAAAA.',
Po='Pogo:BAABLgAECn8fAAIXAAkJdiR9AgAbAwAXAAkJdiR9AgAbAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwAXAHYkAA==.',
Pr='Pricedd:BAAALgADCgcJCAAAAA==.Prosperina:BAAALgADCgQJBAAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8lAAMDAAgJdQgmHQC+AAABAAgJhgcPmQALAQADAAYJvAomHQC+AAAAAA==.',
Qu='Quetzani:BAAALgAECgEJAQAAAA==.',
Ra='Ranoa:BAAALgADCgkJCQABLgAECgYJFAAbAJwdAA==.Rasputon:BAAALgAECgEJAQABLgAECgkJPAASAO8eAA==.Rastapopulos:BAAALgAECggJCgAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECgkJQgAYAPcdAA==.Redrocket:BAAALgAECgEJAgABLgAECgQJCQAKAAAAAA==.Rekkash:BAAALgAECgEJAQAAAA==.Remixed:BAAALgAECgQJBgAAAA==.Reptilectric:BAAALgAECgUJDgAAAA==.Retxd:BAAALgADCgIJAgABLgAECgQJBQAKAAAAAA==.',
Ri='Rikaku:BAABLgAECn88AAIYAAcJwRNCCAA9AQAYAAcJwRNCCAA9AQAAAA==.',
Ro='Roastbeef:BAAALgAECgEJAQAAAA==.Ronananna:BAAALgADCgkJDwABLgADCgYJBgAKAAAAAA==.Rosemery:BAAALgAECgYJBwAAAA==.',
['Râ']='Râpödac:BAAALgADCgIJAgAAAA==.',
['Rä']='Räpodac:BAACLgAFFH8HAAIZAAMJ7gWcBwC4AAAZAAMJ7gWcBwC4AAAuAAQKfy8AAhkACQlwEY8DAP4AABkACQlwEY8DAP4AAAAA.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Sajae:BAAALgAECgEJAQAAAA==.Saphil:BAAALgAECgEJAQAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Scarypantz:BAAALgAECgEJAgAAAA==.Schizo:BAACLgAFFH8KAAIiAAIJtxqG1ACMAAAiAAIJtxqG1ACMAAAuAAQKfx0AAiIABwngIfNAADUCACIABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAwAAAA==.Sefiroth:BAACLgAFFH8IAAIQAAMJZA01HgCqAAAQAAMJZA01HgCqAAAuAAQKfy4AAhAABwnTFSdbAHYBABAABwnTFSdbAHYBAAAA.Selillea:BAAALgAECgYJBwAAAA==.Semarius:BAAALgAECgEJAwABLgAECgkJNwAZAKQhAA==.Semdorii:BAABLgAECn83AAIZAAkJpCGdBAD+AgAZAAkJpCGdBAD+AgAAAA==.Sephywrath:BAABLgAECn8+AAIlAAkJoRs5AgBIAgAlAAkJoRs5AgBIAgAAAA==.Seralith:BAABLgAECn9IAAMiAAkJkyUqAwBsAwAiAAkJkyUqAwBsAwAWAAUJayGvDgCKAQAAAA==.Seranight:BAACLgAFFH8VAAMkAAQJtiQ6EACAAQAkAAQJtiQ6EACAAQAiAAEJJwEyKQEnAAAuAAQKf1QAAiQACQmTJmwAAHcDACQACQmTJmwAAHcDAAAA.Seven:BAAALgAECgIJBAABLgAECgkJJAABAEcWAA==.Sevenpaws:BAAALgAECgcJDAABLgAFFAMJBgARACUmAA==.',
Sh='Shadowchi:BAABLgAECn8hAAIDAAYJIws7HQC+AAADAAYJIws7HQC+AAAAAA==.Shadowspawnn:BAAALgADCgEJAQAAAA==.Shadowwhisp:BAAALgAECgEJAQAAAA==.Shaidon:BAAALgAECgYJBgAAAQ==.Shaly:BAABLgAECn8jAAIaAAgJPwZ7qAAtAQAaAAgJPwZ7qAAtAQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shinjihirako:BAAALgAECgQJBwAAAA==.Shirohige:BAABLgAECn8lAAIgAAYJRw4EBQC+AAAgAAYJRw4EBQC+AAAAAA==.Shlonglord:BAAALgADCgIJAgAAAA==.Shylan:BAABLgAFFH8FAAIPAAEJGB4OKgBMAAAPAAEJGB4OKgBMAAAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDgAAAA==.',
Sn='Snaarf:BAAALgADCgEJAQABLgAECgYJIQAdALgFAA==.Snayre:BAACLgAFFH8OAAIXAAQJohlhDgBSAQAXAAQJohlhDgBSAQAuAAQKfzUAAhcACQlxHt8FAMcCABcACQlxHt8FAMcCAAAA.Snipêr:BAABLgAECn8dAAIYAAgJ3RN7SADIAQAYAAgJ3RN7SADIAQAAAA==.Snowlia:BAACLgAFFH8KAAITAAMJahM5UgCuAAATAAMJahM5UgCuAAAuAAQKfyEAAxMACQkxE/A1AKsBABMACQkxE/A1AKsBAA0AAQk3D06qACwAAAAA.',
So='Soularis:BAAALgAECgYJCAAAAA==.Soulslice:BAEALgAECggJCAABLgAECgQJEQAKAAAAAA==.Sovrano:BAAALgADCgEJAQAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAABLgAECn8cAAMmAAcJvwbbEQDtAAAmAAcJvwbbEQDtAAAjAAEJ6gG3RgAXAAAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJEAAAAA==.',
St='Stalkingwolf:BAABLgAECn8qAAIkAAcJRxhHGQCWAQAkAAcJRxhHGQCWAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgAECgYJEQAAAA==.',
Sy='Sylailia:BAACLgAFFH8PAAIHAAQJNwxWCAAAAQAHAAQJNwxWCAAAAQAuAAQKfzsAAgcACQm3HbcJALgCAAcACQm3HbcJALgCAAAA.Syleta:BAAALgADCgMJBAAAAA==.Sylvia:BAAALgAECgIJAwAAAA==.',
['Sí']='Síenna:BAAALgAECgEJAwAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAMJBAAKAAAAAA==.Tarlynna:BAAALgAECgIJAgAAAA==.',
Tc='Tcon:BAABLgAECn8UAAIXAAcJRBWpIQCPAQAXAAcJRBWpIQCPAQAAAA==.',
Td='Tdragon:BAAALgADCgkJEgABLgAECgkJMQAcAPoVAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Therea:BAAALgAECgEJAQAAAA==.Thissa:BAABLgAECn8uAAMHAAgJrx9rEQBPAgAHAAgJrx9rEQBPAgAhAAEJSBm4MwAzAAABLgAFFAQJBgAdAJMNAA==.Thundarah:BAAALgADCgcJFwAAAA==.Thundielocks:BAAALgADCgkJCQAAAA==.Thundruid:BAAALgADCgkJEgAAAA==.Thuniellas:BAAALgADCggJGQAAAA==.',
Ti='Tiarcis:BAABLgAECn81AAIYAAkJbBirIgBZAgAYAAkJbBirIgBZAgAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Tostitos:BAAALgADCgkJCQABLgAECgkJMQAcAPoVAA==.Totemsalot:BAACLgAFFH8MAAITAAQJjBu+KwA1AQATAAQJjBu+KwA1AQAuAAQKfxsAAhMACQnGI7MDAIIDABMACQnGI7MDAIIDAAAA.',
Tr='Treesummoner:BAABLgAECn8tAAQBAAkJjRjrKgAuAgABAAkJjRjrKgAuAgADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgAECgIJAgAAAA==.Tritanks:BAACLgAFFH8FAAILAAIJSSECAgDJAAALAAIJSSECAgDJAAAuAAQKf0kAAgsACQlYJBsBADMDAAsACQlYJBsBADMDAAAA.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAKAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAABLgAECn8UAAIcAAcJpgzgPAAdAQAcAAcJpgzgPAAdAQAAAA==.Vali:BAAALgAECgUJBQAAAA==.Valiente:BAAALgAECgIJAgAAAA==.Valkah:BAAALgAECgEJAQAAAA==.Vasilia:BAABLgAECn89AAIkAAkJRRk1EAAIAgAkAAkJRRk1EAAIAgAAAA==.',
Ve='Velanna:BAAALgAECgIJAgAAAA==.Vexara:BAAALgAECgYJEgAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgAFFAEJAwAAAA==.',
Vo='Voclus:BAAALgAECgYJEwAAAA==.',
Vy='Vykyrnarreia:BAAALgADCgMJAwAAAA==.',
Wa='Wall:BAAALgAECgYJEwAAAA==.Warlodshenu:BAAALgADCgcJCwAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
We='Weyaeh:BAAALgADCgIJAgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wulfbayne:BAAALgAECgQJBAAAAA==.Wuwindtang:BAAALgAECgUJDAAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgAECgEJAQAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAIOAAYJqQXzbACxAAAOAAYJqQXzbACxAAAAAA==.Xiletank:BAAALgAECgUJBQAAAA==.',
Ya='Yasutorasado:BAAALgAECgYJBwAAAA==.',
Za='Zachxd:BAABLgAECn88AAIQAAcJ6RkTUgCPAQAQAAcJ6RkTUgCPAQABLgAFFAIJCgAiALcaAA==.Zanthe:BAABLgAECn8XAAIHAAUJphN7BADtAAAHAAUJphN7BADtAAAAAA==.Zapanese:BAAALgADCgMJBAAAAA==.Zapt:BAAALgAECgIJAgAAAA==.Zaptism:BAABLgAECn87AAMRAAkJMCFGCADnAgARAAkJMCFGCADnAgASAAUJhQ6hRwDoAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgAECgEJAQAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgYJEAABLgAFFAQJFAAMAGIhAA==.Zhanbear:BAAALgAECggJDAABLgAFFAQJFAAMAGIhAA==.Zhanbrew:BAACLgAFFH8UAAIMAAQJYiGkBgANAQAMAAQJYiGkBgANAQAuAAQKfyQAAgwACQnhIu8CACcDAAwACQnhIu8CACcDAAAA.Zhanfury:BAAALgAFFAEJAQABLgAFFAQJFAAMAGIhAA==.Zhanret:BAAALgAECgcJDQABLgAFFAQJFAAMAGIhAA==.',
Zi='Zinder:BAABLgAECn8nAAMdAAgJTQg+SgADAQAdAAgJTQg+SgADAQAmAAEJLAPXKwAeAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJjRe8BQAOAgADAAkJjRe8BQAOAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECgkJKgAgAGkaAA==.',
['Öb']='Öboron:BAACLgAFFH8JAAMXAAQJVgMNHgDiAAAXAAQJVgMNHgDiAAAIAAEJywHKPAAsAAAuAAQKfy4ABBcACQmMF0wPADkCABcACQknFkwPADkCAAgACAlWECgqANoBABgABgkpFTJTAG8BAAAA.',
['Üz']='Üz:BAABLgAECn8kAAIZAAgJvhbQGAC8AQAZAAgJvhbQGAC8AQAAAA==.',
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
