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
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Addely:BAAALgAECgYJCAAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgUJEAAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRqucACbAQAEAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJEQAAAA==.',
Al='Alerion:BAABLgAECn8sAAIFAAkJKhnoDABYAgAFAAkJKhnoDABYAgAAAA==.Allan:BAABLgAECn8rAAIGAAkJbiEEAQDEAgAGAAkJbiEEAQDEAgAAAA==.Alligatorjoe:BAAALgADCgEJAQAAAA==.',
Am='Amaneeda:BAABLgAECn81AAIHAAkJghCyKgB/AQAHAAkJghCyKgB/AQAAAA==.Amazonia:BAABLgAECn8jAAIIAAYJWxgoEQBHAQAIAAYJWxgoEQBHAQAAAA==.Aminea:BAABLgAFFH8QAAIJAAQJ9hf9CwDeAAAJAAQJ9hf9CwDeAAAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAKAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8HAAILAAIJHhUMDQB3AAALAAIJHhUMDQB3AAAuAAQKfy8AAgsACAkhIuwDAJECAAsACAkhIuwDAJECAAEuAAUUBAkUAAwAYiEA.Angyrain:BAAALgAECgUJBgABLgAFFAQJFAAMAGIhAA==.Annerila:BAAALgAECgYJCQAAAA==.Antagonis:BAABLgAECn8iAAIDAAcJSA8tEwAZAQADAAcJSA8tEwAZAQAAAA==.',
Ap='Apexchi:BAAALgAECgYJEgAAAA==.Apeximmortal:BAAALgAECgkJDgAAAA==.Apexlight:BAAALgAECgkJEQAAAA==.Apexwar:BAAALgAECgEJAQAAAA==.',
Ar='Arashe:BAABLgAECn8aAAINAAYJagT8CwCSAAANAAYJagT8CwCSAAAAAA==.Arewen:BAAALgADCggJEQAAAA==.Arganos:BAABLgAECn8wAAMOAAkJtSbdAQBeAwAOAAkJtSbdAQBeAwAPAAYJFxtAGQBzAQAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8WAAIQAAcJ6wTouwC0AAAQAAcJ6wTouwC0AAAAAA==.Arkstrife:BAAALgADCgEJAQAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgAECgUJBQAAAA==.Atheîst:BAACLgAFFH8HAAMRAAMJJSYTEgA8AQARAAMJlyUTEgA8AQASAAMJQSDIDAARAQAuAAQKf0cAAxEACQl8JcwBAFoDABEACQl3JcwBAFoDABIACAmAIyoFADgDAAAA.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn9MAAMTAAkJjh+sGQB9AgATAAgJHx+sGQB9AgANAAgJgB2YFgAxAgAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAcJFQAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJMAAOALUmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8cAAMUAAcJuRqcFQCwAQAUAAcJuRqcFQCwAQAOAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8fAAIVAAYJ9RWiPgB0AQAVAAYJ9RWiPgB0AQAAAA==.Baelanoth:BAABLgAECn8wAAIWAAkJLB0iBgBJAgAWAAkJLB0iBgBJAgAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balerion:BAAALgAECgEJAgAAAA==.Balkazaar:BAAALgAECggJEQAAAA==.Bammbamm:BAABLgAECn8xAAIEAAkJ1QrQmwA+AQAEAAkJ1QrQmwA+AQAAAA==.Banewreak:BAACLgAFFH8MAAIBAAMJmAvHfwDFAAABAAMJmAvHfwDFAAAuAAQKfzkAAgEACQnCFzMmAEUCAAEACQnCFzMmAEUCAAAA.Banu:BAAALgAECgMJBAAAAA==.Baradin:BAABLgAECn8UAAIJAAcJGBWuKADHAQAJAAcJGBWuKADHAQAAAA==.Barind:BAABLgAECn8yAAQXAAkJFh0xCQCLAgAXAAkJmRwxCQCLAgAIAAcJIxqYJAADAgAYAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgQJCQAAAA==.Betrayer:BAACLgAFFH8QAAIZAAQJTRrXBQAcAQAZAAQJTRrXBQAcAQAuAAQKfyIAAhkACQnuIT8EAAcDABkACQnuIT8EAAcDAAAA.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAABLgAECn8WAAIWAAgJWBPWDACrAQAWAAgJWBPWDACrAQABLgAECgkJHgATAJcNAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Bignfugly:BAAALgADCgYJBgABLgAECgcJIAANAMYZAA==.Biqdonk:BAAALgAECgUJDAAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.Bloodhornz:BAAALgAECgEJAwAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDQABLgADCgYJCwAKAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAKAAAAAA==.Bossdwarf:BAAALgADCgcJCwABLgADCgYJCwAKAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleosévèn:BAABLgAECn8YAAMJAAcJLxl8AgCyAQAJAAcJLxl8AgCyAQAEAAQJyANgOgA5AAABLgAFFAMJBwARACUmAA==.Buddro:BAAALgAECgIJAwAAAA==.',
['Bú']='Búbblés:BAAALgAECgcJDQAAAA==.',
Ca='Caatia:BAAALgAFFAIJAwAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgkJJAABAEcWAA==.Carthel:BAABLgAECn8fAAIaAAgJMiBYMQCtAgAaAAgJMiBYMQCtAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCggJDgAAAA==.',
Ce='Cerisi:BAAALgAECgEJAQAAAA==.Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Charley:BAABLgAECn8cAAIaAAcJ9AsUDQAfAQAaAAcJ9AsUDQAfAQAAAA==.Chasseresse:BAABLgAECn8hAAIYAAYJiBk1XgCMAQAYAAYJiBk1XgCMAQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chi:BAAALgAECgEJAgAAAA==.Chimarr:BAABLgAECn8cAAIbAAgJFiK5EADLAgAbAAgJFiK5EADLAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Cm='Cmondie:BAAALgAECgYJCgAAAA==.',
Co='Coldsploder:BAACLgAFFH8IAAIaAAMJ4gZSjQC+AAAaAAMJ4gZSjQC+AAAuAAQKfy0AAhoACQlaF7gzAEoCABoACQlaF7gzAEoCAAAA.',
Cr='Crackmonkéy:BAACLgAFFH8IAAISAAMJpQ2oFgCeAAASAAMJpQ2oFgCeAAAuAAQKfxoABBIACAnYGBIrAH0BABIABwk0FBIrAH0BABEABAmRGVZPAPsAABwABAl0EDhBAO8AAAEuAAUUBAkHAB0Akw0A.Cranknspank:BAAALgAECgYJBwAAAA==.Cronoz:BAABLgAECn8mAAMTAAkJMQrbWQAhAQATAAgJUAfbWQAhAQANAAgJ0wnpRAAgAQAAAA==.Crotchshot:BAABLgAECn8oAAIYAAkJFxNBNgAEAgAYAAkJFxNBNgAEAgAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Culodevour:BAAALgAECgYJCAAAAA==.Cursess:BAACLgAFFH8SAAIBAAMJVSIDTQAsAQABAAMJVSIDTQAsAQAuAAQKfzUAAgEACQlxIh4NAOQCAAEACQlxIh4NAOQCAAAA.',
['Có']='Cózmik:BAABLgAECn8UAAIYAAcJ3RZBXQCOAQAYAAcJ3RZBXQCOAQAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn88AAIBAAkJvhUOLgAgAgABAAkJvhUOLgAgAgAAAA==.Dalya:BAABLgAFFH8HAAIYAAMJvwtLOACFAAAYAAMJvwtLOACFAAAAAA==.Dander:BAAALgAECgEJAQAAAA==.Dani:BAAALgAECgEJAgABLgAECgQJBQAKAAAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkridder:BAAALgAECgEJAQAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAABLgAECn8VAAIbAAcJvBtrKwD9AQAbAAcJvBtrKwD9AQAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deathratellr:BAAALgADCgEJAQAAAA==.Deemaius:BAAALgAECgEJAgAAAA==.Dekard:BAAALgAECggJEwAAAA==.Dekariusly:BAAALgAECgQJBAABLgAECggJEwAKAAAAAA==.Deltee:BAAALgAECgMJAwABLgAECgkJMwAVAEshAA==.Demonatrixx:BAAALgAECgYJCQAAAA==.Demonhugger:BAAALgAECgEJAgABLgAECgUJBQAKAAAAAA==.Demonkila:BAAALgAECgUJBgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHwACAFwZAA==.Destinÿ:BAABLgAECn8nAAIPAAkJjRWmFwCEAQAPAAkJjRWmFwCEAQAAAA==.Devourer:BAABLgAECn84AAIQAAkJQBueKgAeAgAQAAkJQBueKgAeAgAAAA==.',
Di='Disploder:BAABLgAECn8sAAIRAAgJdBQNHwDMAQARAAgJdBQNHwDMAQAAAA==.Dist:BAAALgAECgkJDgAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.Dommiemommie:BAAALgAECgIJAgAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJBAAAAA==.Drawwn:BAAALgAECgEJAgABLgAECgEJBAAKAAAAAA==.Dreathhammer:BAABLgAECn8uAAIJAAkJ1SLDAwBiAwAJAAkJ1SLDAwBiAwAAAA==.Drogo:BAABLgAFFH8HAAIdAAQJkw34MgD2AAAdAAQJkw34MgD2AAAAAA==.Drureds:BAAALgAECgQJCQAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAgJLAAJAPQgAA==.',
Du='Duckcox:BAAALgAECgQJBwAAAA==.Dunadin:BAABLgAECn8ZAAQVAAYJbR3eCQAaAQAVAAYJbR3eCQAaAQAMAAIJ4xJKaQB0AAAeAAEJthXekQA/AAABLgAECgkJPwALAK4mAA==.Dundyrn:BAABLgAECn8/AAILAAkJriY3AAB0AwALAAkJriY3AAB0AwAAAA==.Dunhara:BAAALgAECgEJAQABLgAECgkJPwALAK4mAA==.',
Dv='Dvera:BAAALgADCgMJAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECgkJPwALAK4mAA==.',
Ec='Echosïx:BAAALgADCgcJBwAAAA==.Ecks:BAAALgAECgMJAwABLgAFFAgJEgAPAP0aAA==.',
Ed='Edmunin:BAEALgAECgYJAwAAAA==.',
El='Elememetal:BAABLgAECn8pAAINAAkJvxgHHAABAgANAAkJvxgHHAABAgAAAA==.Elfyparker:BAAALgAECgEJAgAAAA==.Elliott:BAAALgADCgIJAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Ex='Exí:BAAALgAECgMJAwAAAA==.',
Fa='Fangzz:BAAALgADCgEJAQAAAA==.Fanmir:BAAALgAECgEJAgAAAA==.Fatpao:BAABLgAECn8dAAIUAAYJjRvdAQBdAQAUAAYJjRvdAQBdAQAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAITAAcJXQtGgQDdAAATAAcJXQtGgQDdAAAAAA==.Fenix:BAAALgADCgEJAgABLgAECgkJMQAcAP4VAA==.',
Fi='Filbert:BAABLgAECn8dAAIHAAkJUyGEBwDeAgAHAAkJUyGEBwDeAgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Foldyholds:BAAALgAECgUJCQAAAA==.Fomy:BAAALgAECgEJAQABLgAFFAMJCQAHAEAIAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDgAKAAAAAA==.',
Fr='Fraw:BAAALgADCggJDAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAwAAAA==.Fuzzyhunter:BAAALgAECgUJBwABLgAECgkJMQAcAP4VAA==.',
['Fá']='Fálola:BAABLgAECn89AAMTAAgJrxffKADsAQATAAgJrxffKADsAQANAAYJwwOjcACYAAAAAA==.',
Ga='Galestina:BAAALgAECgYJBgAAAA==.Gamblex:BAABLgAECn8cAAIPAAYJxBRiAwARAQAPAAYJxBRiAwARAQAAAA==.Garviel:BAABLgAECn8jAAIUAAkJCRwNCAB0AgAUAAkJCRwNCAB0AgAAAA==.',
Ge='Geeblast:BAAALgAECgMJAwABLgAECggJGQABABMWAA==.Geeplague:BAAALgAECgMJBQABLgAECggJGQABABMWAA==.Geethatlock:BAABLgAECn8ZAAIBAAgJExa5RwDDAQABAAgJExa5RwDDAQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAABLgAECn88AAIIAAgJGBevAADsAQAIAAgJGBevAADsAQAAAA==.Girthlord:BAAALgAECgQJBAABLgAECgkJPAABAL4VAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgAECgEJAQAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravincar:BAAALgAFFAEJAQABLgAECgkJPwALAK4mAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAABLgAECn8nAAITAAgJ8RtfBQCHAQATAAgJ8RtfBQCHAQAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grogu:BAABLgAECn8eAAIaAAcJBQpeswAcAQAaAAcJBQpeswAcAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJBgAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAFFAMJBAAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgcJBwAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECgkJLgAfAL0fAA==.Hiksham:BAABLgAECn8uAAMfAAkJvR9ABQCSAgAfAAkJnB9ABQCSAgANAAgJBw3+OwBFAQAAAA==.',
Ho='Holycheeze:BAAALgAECgEJAQAAAA==.Holyhoof:BAAALgAECgEJAQAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgkJJAABAEcWAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgcJGwATAMEVAA==.',
Ia='Iamreggi:BAAALgAECgQJBgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8xAAIcAAkJ/hW/FwAKAgAcAAkJ/hW/FwAKAgAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Im:BAAALgAFFAMJBAAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
In='Innogen:BAAALgAECgEJAQAAAA==.',
Ir='Irisi:BAAALgADCgUJBQAAAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECgkJKgAgAG0aAA==.Jarlyss:BAABLgAECn8qAAIgAAkJbRp4DAAZAgAgAAkJbRp4DAAZAgAAAA==.Javieraa:BAABLgAECn8gAAIQAAkJYRruJQA2AgAQAAkJYRruJQA2AgAAAA==.',
Jd='Jdai:BAABLgAECn8bAAITAAcJwRUYPQC6AQATAAcJwRUYPQC6AQAAAA==.',
Jo='Jocecilla:BAAALgAFFAEJAQABLgAFFAIJAwAKAAAAAA==.Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAAALgAECggJEwAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgAECgMJAwAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.Kaishuka:BAAALgAECgEJAwAAAA==.Karlplkngton:BAAALgAECgEJAQAAAA==.Kasna:BAAALgAECgkJCQAAAA==.Kazarian:BAAALgAECgUJBQAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8hAAIQAAgJDRxkFgD+AQAQAAgJDRxkFgD+AQAuAAQKf0MAAhAACQlkJLEEADsDABAACQlkJLEEADsDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn89AAIZAAkJsRDzIABxAQAZAAkJsRDzIABxAQAAAA==.Kikyo:BAAALgAECgYJEgAAAA==.Kimmi:BAAALgAECgUJEAAAAA==.Kinzen:BAABLgAECn8xAAIfAAcJhSDADQDTAQAfAAcJhSDADQDTAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIhAAYJAyEjDQDmAQAhAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8jAAIaAAgJPApLkABXAQAaAAgJPApLkABXAQAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgAECgIJAgABLgAECgkJPAASAPAeAA==.',
Le='Lechwe:BAABLgAECn8/AAITAAkJKhxhEADNAgATAAkJKhxhEADNAgAAAA==.Legolase:BAAALgAECgEJAQAAAA==.Legonator:BAAALgAECgUJCAAAAA==.Lenry:BAAALgAFFAEJAQAAAA==.',
Li='Lichmajor:BAABLgAECn8nAAIiAAkJ6BjnRwDqAQAiAAkJ6BjnRwDqAQAAAA==.Liion:BAAALgADCggJDwAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.Littlefang:BAAALgAECgQJBAAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn8zAAMVAAkJSyGWFQBtAgAVAAcJICGWFQBtAgAeAAgJTRotAQAeAgAAAA==.Lovepet:BAABLgAECn9CAAMYAAkJ9x1zGgCHAgAYAAkJ9x1zGgCHAgAIAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAABLgAECn8jAAIiAAcJLxgEBgCKAQAiAAcJLxgEBgCKAQAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn83AAIaAAkJbiB+IgCTAgAaAAkJbiB+IgCTAgAAAA==.Lunavis:BAAALgAECgcJDgABLgAECgkJGgAbAPUNAA==.',
Ly='Lyda:BAABLgAECn89AAIbAAkJSBv5GAB+AgAbAAkJSBv5GAB+AgAAAA==.',
Ma='Magice:BAABLgAECn8mAAIaAAYJkAXRFwC1AAAaAAYJkAXRFwC1AAAAAA==.Magmara:BAAALgAECgUJCAAAAA==.Malibubarbie:BAABLgAECn82AAIRAAkJsw7bJwCHAQARAAkJsw7bJwCHAQAAAA==.Malthael:BAAALgAECgIJAwAAAA==.Malystron:BAABLgAECn8UAAIEAAkJ/wrTfAB1AQAEAAkJ/wrTfAB1AQAAAA==.Maneevent:BAABLgAECn8ZAAQYAAYJGRfwiAAtAQAYAAYJGRfwiAAtAQAXAAEJ1wSAagAoAAAIAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn88AAMSAAkJ8B6bBwAAAwASAAkJ8B6bBwAAAwAcAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn9BAAIYAAkJUgoaVACnAQAYAAkJUgoaVACnAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8bAAQhAAcJsBraAgCmAQAhAAUJTxvaAgCmAQAgAAQJNxnFAwBCAQAHAAMJpxZIGwBOAAAuAAQKfyoABCEACQkiI0sCAAgDACEACQkiI0sCAAgDACAAAQkxIY0pAFQAAAcAAQkqFdODAEEAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn81AAIRAAkJCRHnIQCzAQARAAkJCRHnIQCzAQAAAA==.',
Mi='Midnightstar:BAABLgAECn8VAAIbAAYJqxKtTwBQAQAbAAYJqxKtTwBQAQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAKAAAAAA==.Mimolette:BAAALgAECgMJAwAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.Miseree:BAAALgAECgcJBwAAAA==.',
Mo='Modest:BAAALgAECgUJBQAAAA==.Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgAECgEJAgAAAA==.Moonbayne:BAABLgAECn8wAAIHAAkJvRs/DwBrAgAHAAkJvRs/DwBrAgAAAA==.Mooszer:BAACLgAFFH8GAAIEAAIJCwSKOgBvAAAEAAIJCwSKOgBvAAAuAAQKfyYAAgQACQmpCDwPAAABAAQACQmpCDwPAAABAAAA.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBwAAAA==.Mushu:BAABLgAECn8tAAIjAAkJSBr5BQCuAgAjAAkJSBr5BQCuAgAAAA==.',
Mv='Mvmt:BAAALgAECgUJCQAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.Natre:BAAALgADCgIJAgAAAA==.',
Ne='Nepharim:BAAALgAECgYJCwAAAA==.Nephlim:BAACLgAFFH8fAAMiAAgJ3x/RCgDmAQAiAAcJ3x/RCgDmAQAkAAEJAADMVQAAAAAuAAQKfzEAAiIACQnmIcQGAGwDACIACQnmIcQGAGwDAAAA.Nergal:BAAALgADCgMJAwAAAA==.Newt:BAAALgADCgEJAQAAAA==.',
Ni='Ninobrown:BAAALgAECgYJEwAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNwAaAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNwAaAG4gAA==.Nizano:BAABLgAECn8jAAIEAAcJHgwytQAXAQAEAAcJHgwytQAXAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAKAAAAAA==.Noobie:BAAALgADCgYJCAAAAA==.Noryaa:BAABLgAECn8fAAIYAAYJQwYnrwDmAAAYAAYJQwYnrwDmAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.Notfurry:BAAALgAECgIJAgAAAA==.',
Nu='Nuadå:BAABLgAECn8qAAMbAAcJthGwRQB6AQAbAAcJthGwRQB6AQAHAAQJbgWMagB3AAAAAA==.Nuala:BAAALgADCgUJBQAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECggJDgAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAABLgAECn8iAAMRAAYJURSNBQAPAQARAAUJnhKNBQAPAQAcAAUJshPASADsAAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAAALgADCgEJAQABLgAECggJHAAbABYiAA==.Orkid:BAAALgAECgEJAgAAAA==.',
Pa='Pantoprazole:BAAALgAECgEJAQAAAA==.Pawsome:BAAALgAECgQJBAABLgAECgkJOwANAOkZAA==.',
Pe='Penzmoo:BAAALgADCgEJAQAAAA==.',
Ph='Phelyx:BAACLgAFFH8FAAIbAAMJJwSYZwBMAAAbAAMJJwSYZwBMAAAuAAQKfxkAAxsACQmhEwICABICABsACQmhEwICABICAAcAAgkiBQiIADoAAAAA.',
Pi='Pivotremix:BAAALgAECgYJBgAAAA==.',
Po='Pogo:BAABLgAECn8fAAIXAAkJdiR9AgAbAwAXAAkJdiR9AgAbAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwAXAHYkAA==.',
Pr='Pricedd:BAAALgADCgcJCgAAAA==.Professional:BAAALgAECgEJAQAAAA==.Prosperina:BAAALgADCgQJBAAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8lAAMDAAgJdQgmHQC+AAABAAgJhgcPmQALAQADAAYJvAomHQC+AAAAAA==.',
Qu='Quetzani:BAAALgAECgEJAQAAAA==.',
Ra='Ranoa:BAAALgADCgkJDgABLgAECgcJFQAbALwbAA==.Rasputon:BAAALgAECgEJAQABLgAECgkJPAASAPAeAA==.Rastapopulos:BAAALgAECggJCgAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECgkJQgAYAPcdAA==.Redrocket:BAAALgAECgEJAgABLgAECgQJCQAKAAAAAA==.Rekkash:BAAALgAECgEJAQAAAA==.Remixed:BAAALgAECgQJBgAAAA==.Reptilectric:BAAALgAECgUJDgAAAA==.Retxd:BAAALgADCgIJAgABLgAECgQJBQAKAAAAAA==.',
Ri='Rikaku:BAABLgAECn88AAIYAAcJwRMSDQApAQAYAAcJwRMSDQApAQAAAA==.',
Ro='Roastbeef:BAAALgAECgEJAQAAAA==.Ronananna:BAAALgADCgkJDwABLgADCgYJBgAKAAAAAA==.Rosemery:BAAALgAECgYJBwAAAA==.',
['Râ']='Râpodac:BAAALgAECgUJBQAAAA==.Râpödac:BAAALgADCgIJAgAAAA==.',
['Rä']='Räpodac:BAACLgAFFH8HAAIZAAMJ7gUwCwC0AAAZAAMJ7gUwCwC0AAAuAAQKfy8AAhkACQljEX4FAPkAABkACQljEX4FAPkAAAAA.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Sajae:BAAALgAECgEJAQAAAA==.Saphil:BAAALgAECgEJAgAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Scarypantz:BAAALgAECgEJAgAAAA==.Schizo:BAACLgAFFH8KAAIiAAIJtxqG1ACMAAAiAAIJtxqG1ACMAAAuAAQKfx0AAiIABwngIfNAADUCACIABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAwAAAA==.Sefiroth:BAACLgAFFH8IAAIQAAMJZA1nKQCjAAAQAAMJZA1nKQCjAAAuAAQKfy4AAhAABwnTFSdbAHYBABAABwnTFSdbAHYBAAAA.Selillea:BAAALgAECgYJBwAAAA==.Semarius:BAAALgAECgEJAwABLgAECgkJNwAZAKQhAA==.Semdorii:BAABLgAECn83AAIZAAkJpCGdBAD+AgAZAAkJpCGdBAD+AgAAAA==.Sephywrath:BAABLgAECn8+AAIlAAkJoRs5AgBIAgAlAAkJoRs5AgBIAgAAAA==.Seralith:BAACLgAFFH8EAAIiAAMJXyH4awAjAQAiAAMJXyH4awAjAQAuAAQKf00AAyIACQmTJSoDAGwDACIACQmTJSoDAGwDABYABgk0H68OAIoBAAAA.Seranight:BAACLgAFFH8XAAMkAAQJtiQ6EACAAQAkAAQJtiQ6EACAAQAiAAEJJwEyKQEnAAAuAAQKf1kAAiQACQmTJmwAAHcDACQACQmTJmwAAHcDAAAA.Seven:BAAALgAECgIJBAABLgAECgkJJAABAEcWAA==.Sevenpaws:BAAALgAECgcJDAABLgAFFAMJBwARACUmAA==.',
Sh='Shadowchi:BAABLgAECn8jAAIDAAYJkgs7HQC+AAADAAYJkgs7HQC+AAAAAA==.Shadowspawnn:BAAALgADCgEJAQAAAA==.Shadowwhisp:BAAALgAECgEJAQAAAA==.Shaidon:BAAALgAECgYJBgAAAQ==.Shaly:BAABLgAECn8jAAIaAAgJPwZ7qAAtAQAaAAgJPwZ7qAAtAQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shinjihirako:BAAALgAECgQJBwAAAA==.Shirohige:BAABLgAECn8lAAIgAAYJRw5ZBwC9AAAgAAYJRw5ZBwC9AAAAAA==.Shlonglord:BAAALgADCgIJAgAAAA==.Shylan:BAABLgAFFH8FAAIPAAEJGB4OKgBMAAAPAAEJGB4OKgBMAAAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDgAAAA==.',
Sn='Snaarf:BAAALgADCgEJAQABLgAECgYJIQAdALgFAA==.Snayre:BAACLgAFFH8OAAIXAAQJohlhDgBSAQAXAAQJohlhDgBSAQAuAAQKfzUAAhcACQlxHt8FAMcCABcACQlxHt8FAMcCAAAA.Snipêr:BAABLgAECn8dAAIYAAgJ3RN7SADIAQAYAAgJ3RN7SADIAQAAAA==.Snowlia:BAACLgAFFH8KAAITAAMJahM5UgCuAAATAAMJahM5UgCuAAAuAAQKfyEAAxMACQkxE/A1AKsBABMACQkxE/A1AKsBAA0AAQk3D06qACwAAAAA.',
So='Soularis:BAAALgAECgYJCAAAAA==.Soulslice:BAEALgAECggJCAABLgAECgQJEQAKAAAAAA==.Sovrano:BAAALgADCgEJAQAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAABLgAECn8cAAMmAAcJvwbbEQDtAAAmAAcJvwbbEQDtAAAjAAEJ6gG3RgAXAAAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJEAAAAA==.',
St='Stalkingwolf:BAABLgAECn8qAAIkAAcJRxhHGQCWAQAkAAcJRxhHGQCWAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgAECgYJEQAAAA==.',
Sy='Sylailia:BAACLgAFFH8PAAIHAAQJNwxVDADzAAAHAAQJNwxVDADzAAAuAAQKfzwAAgcACQm3HbcJALgCAAcACQm3HbcJALgCAAAA.Syleta:BAAALgADCgMJBAAAAA==.Sylvia:BAAALgAECgIJAwAAAA==.',
['Sí']='Síenna:BAAALgAECgEJAwAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAMJBQANAG0LAA==.Tarlynna:BAAALgAECgMJAwAAAA==.',
Tc='Tcon:BAABLgAECn8UAAIXAAcJRBWpIQCPAQAXAAcJRBWpIQCPAQAAAA==.',
Td='Tdmage:BAAALgAECgMJAwABLgAECgkJMQAcAP4VAA==.Tdragon:BAAALgADCgkJEgABLgAECgkJMQAcAP4VAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Therea:BAAALgAECgEJAQAAAA==.Thissa:BAABLgAECn8uAAMHAAgJrx9rEQBPAgAHAAgJrx9rEQBPAgAhAAEJSBm4MwAzAAABLgAFFAQJBwAdAJMNAA==.Thundarah:BAAALgAECgIJAgAAAA==.Thundielocks:BAAALgADCgkJCQAAAA==.Thundruid:BAAALgADCgkJEgAAAA==.Thuniellas:BAAALgADCggJGQAAAA==.',
Ti='Tiarcis:BAABLgAECn82AAIYAAkJiBirIgBZAgAYAAkJiBirIgBZAgAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Tostitos:BAAALgADCgkJCQABLgAECgkJMQAcAP4VAA==.Totemsalot:BAACLgAFFH8MAAITAAQJjBu+KwA1AQATAAQJjBu+KwA1AQAuAAQKfxsAAhMACQnGI7MDAIIDABMACQnGI7MDAIIDAAAA.',
Tr='Treesummoner:BAABLgAECn8tAAQBAAkJjRjrKgAuAgABAAkJjRjrKgAuAgADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgAECgIJAgAAAA==.Tritanks:BAACLgAFFH8HAAILAAIJSSEDAwDFAAALAAIJSSEDAwDFAAAuAAQKf0kAAgsACQlYJBsBADMDAAsACQlYJBsBADMDAAAA.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAKAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAABLgAECn8UAAIcAAcJpgzgPAAdAQAcAAcJpgzgPAAdAQAAAA==.Vali:BAAALgAECgYJCgAAAA==.Valiente:BAAALgAECgIJAgAAAA==.Valkah:BAAALgAECgEJAQAAAA==.Vasilia:BAABLgAECn89AAIkAAkJRBk1EAAIAgAkAAkJRBk1EAAIAgAAAA==.',
Ve='Velanna:BAAALgAECgIJAgAAAA==.Vexaris:BAABLgAECn8XAAIaAAcJ4w59CwA3AQAaAAcJ4w59CwA3AQAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgAFFAEJAwAAAA==.',
Vo='Voclus:BAABLgAECn8UAAIMAAcJFhKJPAAJAQAMAAcJFhKJPAAJAQAAAA==.',
Vy='Vykyrnarreia:BAAALgAECgMJAwAAAA==.',
Wa='Wall:BAAALgAECgYJEwAAAA==.Warlodshenu:BAAALgADCgcJCwAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
We='Weyaeh:BAAALgADCgIJAgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wulfbayne:BAAALgAECgQJBQAAAA==.Wuwindtang:BAAALgAECgUJDAAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgAECgEJAQAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAIOAAYJqQXzbACxAAAOAAYJqQXzbACxAAAAAA==.Xiletank:BAAALgAECgUJBQAAAA==.',
Ya='Yasutorasado:BAAALgAECgYJBwAAAA==.',
Za='Zachxd:BAABLgAECn88AAIQAAcJ6RkTUgCPAQAQAAcJ6RkTUgCPAQABLgAFFAIJCgAiALcaAA==.Zanthe:BAABLgAECn8XAAIHAAUJphO1BgDlAAAHAAUJphO1BgDlAAAAAA==.Zapanese:BAAALgADCgMJBAAAAA==.Zapt:BAAALgAECgIJAgAAAA==.Zaptism:BAABLgAECn87AAMRAAkJMCFGCADnAgARAAkJMCFGCADnAgASAAUJhQ6hRwDoAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgAECgEJAQAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgYJEAABLgAFFAQJFAAMAGIhAA==.Zhanbear:BAAALgAECggJDAABLgAFFAQJFAAMAGIhAA==.Zhanbrew:BAACLgAFFH8UAAIMAAQJYiFGCQAFAQAMAAQJYiFGCQAFAQAuAAQKfyQAAgwACQnhIu8CACcDAAwACQnhIu8CACcDAAAA.Zhanfury:BAAALgAFFAEJAQABLgAFFAQJFAAMAGIhAA==.Zhanret:BAAALgAECgcJDQABLgAFFAQJFAAMAGIhAA==.',
Zi='Zinder:BAABLgAECn8nAAMdAAgJTQg+SgADAQAdAAgJTQg+SgADAQAmAAEJLAPXKwAeAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJjRe8BQAOAgADAAkJjRe8BQAOAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECgkJKgAgAG0aAA==.',
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
