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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Hunter-Marksmanship','Paladin-Holy','Unknown-Unknown','DemonHunter-Vengeance','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Warrior-Fury','Warrior-Protection','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Shaman-Restoration','Warrior-Arms','Monk-Mistweaver','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','Druid-Restoration','Priest-Shadow','Evoker-Augmentation','Monk-Windwalker','Druid-Feral','Shaman-Enhancement','Druid-Guardian','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Addely:BAAALgAECgYJCAAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgUJEAAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRqucACbAQAEAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJEQAAAA==.',
Al='Alerion:BAABLgAECn8sAAIFAAkJKhnoDABYAgAFAAkJKhnoDABYAgAAAA==.Allan:BAABLgAECn8rAAIGAAkJbiEEAQDEAgAGAAkJbiEEAQDEAgAAAA==.Alligatorjoe:BAAALgAECgMJAwAAAA==.',
Am='Amaneeda:BAABLgAECn81AAIHAAkJghCyKgB/AQAHAAkJghCyKgB/AQAAAA==.Amazonia:BAABLgAECn8jAAIIAAYJWxgoEQBHAQAIAAYJWxgoEQBHAQAAAA==.Aminea:BAABLgAFFH8QAAIJAAQJ9hcxDgDbAAAJAAQJ9hcxDgDbAAAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAKAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8HAAILAAIJHhUMDQB3AAALAAIJHhUMDQB3AAAuAAQKfy8AAgsACAkhIuwDAJECAAsACAkhIuwDAJECAAEuAAUUBAkUAAwAYiEA.Angyrain:BAAALgAECgUJBgABLgAFFAQJFAAMAGIhAA==.Annerila:BAAALgAECgYJDgAAAA==.Antagonis:BAABLgAECn8iAAIDAAcJSA8tEwAZAQADAAcJSA8tEwAZAQAAAA==.',
Ap='Apexchi:BAAALgAECgYJEgAAAA==.Apeximmortal:BAABLgAECn8UAAMNAAcJZwt3GwDzAAANAAcJZwt3GwDzAAAOAAEJUwhtMwElAAAAAA==.Apexlight:BAAALgAECgkJEQAAAA==.Apexwar:BAAALgAECgcJCAAAAA==.',
Ar='Arashe:BAABLgAECn8bAAIPAAYJWgVUDgCVAAAPAAYJWgVUDgCVAAAAAA==.Arewen:BAAALgADCggJEQAAAA==.Arganos:BAABLgAECn8wAAMQAAkJtSbdAQBeAwAQAAkJtSbdAQBeAwARAAYJFxtAGQBzAQAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8WAAISAAcJ6wTouwC0AAASAAcJ6wTouwC0AAAAAA==.Arkstrife:BAAALgADCgEJAQAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgAECgUJBQAAAA==.Atheîst:BAACLgAFFH8KAAMTAAMJJSbZBwAWAQATAAMJlyXZBwAWAQAUAAMJQSAYDwAMAQAuAAQKf0cAAxMACQl8JcwBAFoDABMACQl3JcwBAFoDABQACAmAIyoFADgDAAAA.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn9RAAMVAAkJjh+sGQB9AgAVAAgJHx+sGQB9AgAPAAgJgB2YFgAxAgAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAcJFQAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJMAAQALUmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8cAAMWAAcJuRqcFQCwAQAWAAcJuRqcFQCwAQAQAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8fAAIXAAYJ9RWiPgB0AQAXAAYJ9RWiPgB0AQAAAA==.Baelanoth:BAABLgAECn8wAAINAAkJLB0iBgBJAgANAAkJLB0iBgBJAgAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balerion:BAAALgAECgEJAgAAAA==.Balkazaar:BAAALgAECggJEQAAAA==.Bammbamm:BAABLgAECn8xAAIEAAkJ1QrQmwA+AQAEAAkJ1QrQmwA+AQAAAA==.Banewreak:BAACLgAFFH8PAAIBAAMJkxC/JQDTAAABAAMJkxC/JQDTAAAuAAQKfzkAAgEACQnCFzMmAEUCAAEACQnCFzMmAEUCAAAA.Banu:BAAALgAECgMJBAAAAA==.Baradin:BAABLgAECn8UAAIJAAcJGBWuKADHAQAJAAcJGBWuKADHAQAAAA==.Barind:BAABLgAECn8yAAQYAAkJFh0xCQCLAgAYAAkJmRwxCQCLAgAIAAcJIxqYJAADAgAZAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgQJCQAAAA==.Betrayer:BAACLgAFFH8QAAIaAAQJTRpIBwAXAQAaAAQJTRpIBwAXAQAuAAQKfyIAAhoACQnuIT8EAAcDABoACQnuIT8EAAcDAAAA.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAABLgAECn8WAAINAAgJWBPWDACrAQANAAgJWBPWDACrAQABLgAECgkJHgAVAJcNAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Bignfugly:BAAALgADCgYJBgABLgAECgcJIAAPAMYZAA==.Biqdonk:BAAALgAECgUJDAAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.Bloodhornz:BAAALgAECgUJCAAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boogie:BAAALgADCggJCgAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDQABLgADCgYJCwAKAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAKAAAAAA==.Bossdwarf:BAAALgADCgcJCwABLgADCgYJCwAKAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleosévèn:BAABLgAECn8ZAAMJAAcJMBmoAgDQAQAJAAcJMBmoAgDQAQAEAAQJyANSRQA3AAABLgAFFAMJCgATACUmAA==.Buddro:BAAALgAECgIJAwAAAA==.',
['Bú']='Búbblés:BAAALgAECgcJDQAAAA==.',
Ca='Caatia:BAAALgAFFAIJAwAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Capzeil:BAAALgAECgQJBQAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgkJJAABAEcWAA==.Carthel:BAABLgAECn8fAAIbAAgJMiBYMQCtAgAbAAgJMiBYMQCtAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCggJDgAAAA==.',
Ce='Cerisi:BAAALgAECgEJAQAAAA==.Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Charley:BAABLgAECn8cAAIbAAcJ9AupEAAWAQAbAAcJ9AupEAAWAQAAAA==.Chasseresse:BAABLgAECn8hAAIZAAYJiBk1XgCMAQAZAAYJiBk1XgCMAQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chi:BAAALgAECgEJAgAAAA==.Chimarr:BAABLgAECn8cAAIcAAgJFiK5EADLAgAcAAgJFiK5EADLAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Cm='Cmondie:BAAALgAECgYJCgAAAA==.',
Co='Coldsploder:BAACLgAFFH8IAAIbAAMJ4gZSjQC+AAAbAAMJ4gZSjQC+AAAuAAQKfy0AAhsACQlaF7gzAEoCABsACQlaF7gzAEoCAAAA.',
Cr='Crackmonkéy:BAACLgAFFH8IAAIUAAMJpQ1YGgCYAAAUAAMJpQ1YGgCYAAAuAAQKfxoABBQACAnYGBIrAH0BABQABwk0FBIrAH0BABMABAmRGVZPAPsAAB0ABAl0EDhBAO8AAAEuAAUUBAkHAB4Akw0A.Cranknspank:BAAALgAECgYJBwAAAA==.Cronoz:BAABLgAECn8mAAMVAAkJMQrbWQAhAQAVAAgJUAfbWQAhAQAPAAgJ0wnpRAAgAQAAAA==.Crotchshot:BAABLgAECn8oAAIZAAkJFxNBNgAEAgAZAAkJFxNBNgAEAgAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Culodevour:BAAALgAECgYJCAAAAA==.Cursess:BAACLgAFFH8SAAIBAAMJVSIDTQAsAQABAAMJVSIDTQAsAQAuAAQKfzUAAgEACQlxIh4NAOQCAAEACQlxIh4NAOQCAAAA.',
['Có']='Cózmik:BAABLgAECn8UAAIZAAcJ3RZBXQCOAQAZAAcJ3RZBXQCOAQAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn8+AAIBAAkJHBYOLgAgAgABAAkJHBYOLgAgAgAAAA==.Dalya:BAABLgAFFH8HAAIZAAMJvwtyQQB/AAAZAAMJvwtyQQB/AAAAAA==.Dander:BAAALgAECgEJAQAAAA==.Dani:BAAALgAECgEJAgABLgAECgQJBQAKAAAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkridder:BAAALgAECgEJAQAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAABLgAECn8WAAIcAAgJfxlrKwD9AQAcAAgJfxlrKwD9AQAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deathratellr:BAAALgADCgEJAQAAAA==.Deemaius:BAAALgAECgEJAgAAAA==.Dekard:BAAALgAFFAEJAQAAAA==.Dekariusly:BAAALgAECgQJBAABLgAFFAEJAQAKAAAAAA==.Deltee:BAAALgAECgMJAwABLgAECgkJOAAfAO0cAA==.Demonatrixx:BAAALgAECgYJCQAAAA==.Demonhugger:BAAALgAECgEJAgABLgAECgUJBQAKAAAAAA==.Demonkila:BAAALgAECgUJBgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHwACAFwZAA==.Destinÿ:BAABLgAECn8nAAIRAAkJjRWmFwCEAQARAAkJjRWmFwCEAQAAAA==.Devourer:BAABLgAECn84AAISAAkJQBueKgAeAgASAAkJQBueKgAeAgAAAA==.',
Di='Disploder:BAABLgAECn8sAAITAAgJdBQNHwDMAQATAAgJdBQNHwDMAQAAAA==.Dist:BAAALgAECgkJDgAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.Dommiemommie:BAAALgAECgIJAgAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJBAAAAA==.Drawwn:BAAALgAECgEJAgABLgAECgEJBAAKAAAAAA==.Dreathhammer:BAABLgAECn8uAAIJAAkJ1SLDAwBiAwAJAAkJ1SLDAwBiAwAAAA==.Drogo:BAABLgAFFH8HAAIeAAQJkw34MgD2AAAeAAQJkw34MgD2AAAAAA==.Drureds:BAAALgAECgQJDQAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAgJLAAJAPQgAA==.',
Du='Duckcox:BAAALgAECgQJBwAAAA==.Dunadin:BAABLgAECn8ZAAQXAAYJbR20MgCsAQAXAAYJbR20MgCsAQAMAAIJ4xJKaQB0AAAfAAEJthXekQA/AAABLgAECgkJPwALAK4mAA==.Dundyrn:BAABLgAECn8/AAILAAkJriY3AAB0AwALAAkJriY3AAB0AwAAAA==.Dunhara:BAAALgAECgEJAQABLgAECgkJPwALAK4mAA==.',
Dv='Dvera:BAAALgADCgMJAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECgkJPwALAK4mAA==.',
Ec='Echosïx:BAAALgADCgcJBwAAAA==.Ecks:BAAALgAECgMJAwABLgAFFAgJEgARAP0aAA==.',
Ed='Edmunin:BAEALgAECgYJAwAAAA==.',
El='Elememetal:BAABLgAECn8pAAIPAAkJvxgHHAABAgAPAAkJvxgHHAABAgAAAA==.Elfyparker:BAAALgAECgEJAgAAAA==.Elliott:BAAALgADCgIJAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Ex='Exí:BAAALgAECgMJAwAAAA==.',
Fa='Fangzz:BAAALgADCgEJAQAAAA==.Fanmir:BAAALgAECgEJAgAAAA==.Fatpao:BAABLgAECn8dAAIWAAYJjRtVAgBcAQAWAAYJjRtVAgBcAQAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAIVAAcJXQtGgQDdAAAVAAcJXQtGgQDdAAAAAA==.Fenix:BAAALgADCgEJAgABLgAECgkJMQAdAP4VAA==.',
Fi='Filbert:BAABLgAECn8dAAIHAAkJUyGEBwDeAgAHAAkJUyGEBwDeAgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Foldyholds:BAAALgAECgUJCQAAAA==.Fomy:BAAALgAECgEJAQABLgAFFAQJDwAgAHEMAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDgAKAAAAAA==.',
Fr='Fraw:BAAALgADCggJDAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAwAAAA==.Fuzzyhunter:BAAALgAECgUJBwABLgAECgkJMQAdAP4VAA==.',
['Fá']='Fálola:BAABLgAECn89AAMVAAgJrxffKADsAQAVAAgJrxffKADsAQAPAAYJwwOjcACYAAAAAA==.',
Ga='Galestina:BAAALgAECgYJBgAAAA==.Gamblex:BAABLgAECn8dAAIRAAYJxBRDBAAQAQARAAYJxBRDBAAQAQAAAA==.Garviel:BAABLgAECn8jAAIWAAkJCRwNCAB0AgAWAAkJCRwNCAB0AgAAAA==.',
Ge='Geeblast:BAAALgAECgMJAwABLgAECggJGQABABMWAA==.Geegoless:BAAALgAECgMJAwABLgAECggJGQABABMWAA==.Geeplague:BAAALgAECgMJBQABLgAECggJGQABABMWAA==.Geethatlock:BAABLgAECn8ZAAIBAAgJExa5RwDDAQABAAgJExa5RwDDAQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAABLgAECn9DAAIIAAgJMhjCAAD7AQAIAAgJMhjCAAD7AQAAAA==.Girthlord:BAAALgAECgQJBAABLgAECgkJPgABABwWAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgAECgEJAQAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravincar:BAAALgAFFAEJAQABLgAECgkJPwALAK4mAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAABLgAECn8nAAIVAAgJ8RueHwBSAgAVAAgJ8RueHwBSAgAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grimace:BAAALgADCgYJBgAAAA==.Grogu:BAABLgAECn8eAAIbAAcJBQpeswAcAQAbAAcJBQpeswAcAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJBgAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAFFAMJBAAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgcJBwAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECgkJLgAhAL0fAA==.Hiksham:BAABLgAECn8uAAMhAAkJvR9ABQCSAgAhAAkJnB9ABQCSAgAPAAgJBw3+OwBFAQAAAA==.',
Ho='Holycheeze:BAAALgAECgEJAQAAAA==.Holyhoof:BAAALgAECgEJAQAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgkJJAABAEcWAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgcJGwAVAMEVAA==.',
Ia='Iamreggi:BAAALgAECgQJBgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8xAAIdAAkJ/hW/FwAKAgAdAAkJ/hW/FwAKAgAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Im:BAAALgAFFAMJBAAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
In='Innogen:BAAALgAECgEJAQAAAA==.',
Ir='Irisi:BAAALgADCgUJBQAAAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECgkJKgAiAG0aAA==.Jarlyss:BAABLgAECn8qAAIiAAkJbRp4DAAZAgAiAAkJbRp4DAAZAgAAAA==.Javieraa:BAABLgAECn8gAAISAAkJYRruJQA2AgASAAkJYRruJQA2AgAAAA==.',
Jd='Jdai:BAABLgAECn8bAAIVAAcJwRUYPQC6AQAVAAcJwRUYPQC6AQAAAA==.',
Je='Jethrogibbs:BAAALgADCggJCAAAAA==.',
Jo='Jocecilla:BAAALgAFFAEJAQABLgAFFAIJAwAKAAAAAA==.Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAAALgAECggJEwAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgAECgMJAwAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.Kaishuka:BAAALgAECgEJAwAAAA==.Karlplkngton:BAAALgAECgEJAQAAAA==.Kasna:BAAALgAECgkJCQAAAA==.Kazarian:BAAALgAECgUJBQAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8hAAISAAgJDRxkFgD+AQASAAgJDRxkFgD+AQAuAAQKf0MAAhIACQlkJLEEADsDABIACQlkJLEEADsDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn89AAIaAAkJsRDzIABxAQAaAAkJsRDzIABxAQAAAA==.Kikyo:BAAALgAECgYJEgAAAA==.Kimmi:BAAALgAECgUJEAAAAA==.Kinzen:BAABLgAECn8xAAIhAAcJhSDADQDTAQAhAAcJhSDADQDTAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIgAAYJAyEjDQDmAQAgAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8jAAIbAAgJPApLkABXAQAbAAgJPApLkABXAQAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgAECgIJAgABLgAECgkJPAAUAPAeAA==.',
Le='Lechwe:BAABLgAECn8/AAIVAAkJKhxhEADNAgAVAAkJKhxhEADNAgAAAA==.Legolase:BAAALgAECgEJAQAAAA==.Legonator:BAAALgAECgUJCAAAAA==.Lenry:BAAALgAFFAEJAQAAAA==.',
Li='Lichmajor:BAABLgAECn8nAAIOAAkJ6BjnRwDqAQAOAAkJ6BjnRwDqAQAAAA==.Liion:BAAALgADCggJDwAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.Littlefang:BAAALgAECgQJBAAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn84AAMfAAkJ7RzOAACoAgAfAAkJ7RzOAACoAgAXAAcJICGWFQBtAgAAAA==.Lovepet:BAABLgAECn9CAAMZAAkJ9x1zGgCHAgAZAAkJ9x1zGgCHAgAIAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAABLgAECn8pAAIOAAcJyhxwBAD6AQAOAAcJyhxwBAD6AQAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn83AAIbAAkJbiB+IgCTAgAbAAkJbiB+IgCTAgAAAA==.Lunavis:BAAALgAECgcJDgABLgAECgkJGgAcAPUNAA==.',
Ly='Lyda:BAABLgAECn89AAIcAAkJSBv5GAB+AgAcAAkJSBv5GAB+AgAAAA==.',
['Lû']='Lûnitari:BAAALgAECgEJAQABLgAECgcJKgAcALYRAA==.',
Ma='Magice:BAABLgAECn8nAAIbAAYJkAURHQCvAAAbAAYJkAURHQCvAAAAAA==.Magmara:BAAALgAECgUJDQAAAA==.Majajical:BAAALgAECgEJAQAAAA==.Malibubarbie:BAABLgAECn82AAITAAkJsw7bJwCHAQATAAkJsw7bJwCHAQAAAA==.Malthael:BAAALgAECgIJAwAAAA==.Malystron:BAABLgAECn8UAAIEAAkJ/wrTfAB1AQAEAAkJ/wrTfAB1AQAAAA==.Maneevent:BAABLgAECn8ZAAQZAAYJGRfwiAAtAQAZAAYJGRfwiAAtAQAYAAEJ1wSAagAoAAAIAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn88AAMUAAkJ8B6bBwAAAwAUAAkJ8B6bBwAAAwAdAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn9BAAIZAAkJUgoaVACnAQAZAAkJUgoaVACnAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8bAAQgAAcJsBraAgCmAQAgAAUJTxvaAgCmAQAiAAQJNxnJBAA9AQAHAAMJpxZeHwBOAAAuAAQKfyoABCAACQkiI0sCAAgDACAACQkiI0sCAAgDACIAAQkxIY0pAFQAAAcAAQkqFdODAEEAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn87AAITAAkJMhMgBQBOAQATAAkJMhMgBQBOAQAAAA==.',
Mi='Midnightstar:BAABLgAECn8VAAIcAAYJqxKtTwBQAQAcAAYJqxKtTwBQAQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAKAAAAAA==.Mimolette:BAAALgAECgMJAwAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.Miseree:BAAALgAECgcJBwAAAA==.',
Mo='Modest:BAAALgAECgUJBQAAAA==.Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgAECgEJAgAAAA==.Moonbayne:BAACLgAFFH8HAAIHAAUJhQ0vDgD0AAAHAAUJhQ0vDgD0AAAuAAQKfzAAAgcACQm9Gz8PAGsCAAcACQm9Gz8PAGsCAAAA.Mooszer:BAACLgAFFH8IAAIEAAIJCwQfRABuAAAEAAIJCwQfRABuAAAuAAQKfyYAAgQACQmpCCcTAPoAAAQACQmpCCcTAPoAAAAA.Morder:BAAALgADCgYJCgAAAA==.Moregraine:BAAALgAECgEJAgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBwAAAA==.Mushu:BAABLgAECn8tAAIjAAkJSBr5BQCuAgAjAAkJSBr5BQCuAgAAAA==.',
Mv='Mvmt:BAAALgAECgcJCwAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.Natre:BAAALgADCgIJAgAAAA==.',
Ne='Nemamiah:BAAALgADCgcJBwAAAA==.Nepharim:BAAALgAECgYJCwAAAA==.Nephlim:BAACLgAFFH8fAAMOAAgJ3x/TDQDWAQAOAAcJ3x/TDQDWAQAkAAEJAADMVQAAAAAuAAQKfzEAAg4ACQnmIcQGAGwDAA4ACQnmIcQGAGwDAAAA.Nergal:BAAALgADCgMJAwAAAA==.Newt:BAAALgAECgEJAQAAAA==.',
Ni='Ninobrown:BAAALgAECgYJEwAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNwAbAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNwAbAG4gAA==.Nizano:BAABLgAECn8jAAIEAAcJHgwytQAXAQAEAAcJHgwytQAXAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAKAAAAAA==.Noobie:BAAALgADCgYJCAAAAA==.Noryaa:BAABLgAECn8fAAIZAAYJQwYnrwDmAAAZAAYJQwYnrwDmAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.Notfurry:BAAALgAECgIJAgAAAA==.',
Nu='Nuadå:BAABLgAECn8qAAMcAAcJthGwRQB6AQAcAAcJthGwRQB6AQAHAAQJbgWMagB3AAAAAA==.Nuala:BAAALgADCgUJBQAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Ol='Oliviä:BAAALgAECgEJAQAAAA==.',
Om='Om:BAAALgAECggJDgAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAABLgAECn8jAAMTAAYJLBXiBgALAQATAAUJnhLiBgALAQAdAAUJshPASADsAAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAAALgADCgEJAQABLgAECggJHAAcABYiAA==.Orcguyfive:BAAALgADCgEJAQAAAA==.Orkid:BAAALgAECgEJAgAAAA==.',
Pa='Pantoprazole:BAAALgAECgEJAQAAAA==.Pawsome:BAAALgAECgQJBAABLgAECgkJOwAPAOkZAA==.',
Pe='Penzmoo:BAAALgADCgEJAQAAAA==.',
Ph='Phelyx:BAACLgAFFH8FAAIcAAMJJwSYZwBMAAAcAAMJJwSYZwBMAAAuAAQKfxkAAxwACQmhE30CABECABwACQmhE30CABECAAcAAgkiBQiIADoAAAAA.',
Pi='Pivotremix:BAAALgAECgYJBwAAAA==.',
Po='Pogo:BAABLgAECn8fAAIYAAkJdiR9AgAbAwAYAAkJdiR9AgAbAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwAYAHYkAA==.',
Pr='Pricedd:BAAALgADCgcJCgAAAA==.Professional:BAAALgAECgEJAQAAAA==.Prosperina:BAAALgADCgQJBAAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8lAAMDAAgJdQgmHQC+AAABAAgJhgcPmQALAQADAAYJvAomHQC+AAAAAA==.',
Qu='Quetzani:BAAALgAECgEJAQAAAA==.',
Ra='Ranoa:BAAALgADCgkJDgABLgAECggJFgAcAH8ZAA==.Rasputon:BAAALgAECgEJAQABLgAECgkJPAAUAPAeAA==.Rastapopulos:BAAALgAECggJCgAAAA==.',
Re='Redmage:BAAALgADCgcJFgABLgAECgkJQgAZAPcdAA==.Redrocket:BAAALgAECgEJAgABLgAECgQJCQAKAAAAAA==.Rekkash:BAAALgAECgEJAQAAAA==.Remixed:BAAALgAECgQJBgAAAA==.Reptilectric:BAAALgAECgYJDwAAAA==.Retxd:BAAALgADCgIJAgABLgAECgQJBQAKAAAAAA==.',
Ri='Rikaku:BAABLgAECn89AAIZAAcJwRNKEAAjAQAZAAcJwRNKEAAjAQAAAA==.',
Ro='Roastbeef:BAAALgAECgEJAQAAAA==.Ronananna:BAAALgADCgkJDwABLgADCgYJBgAKAAAAAA==.Rosemery:BAAALgAECgYJBwAAAA==.',
['Râ']='Râpodac:BAAALgAECgUJBQAAAA==.Râpödac:BAAALgADCgIJAgAAAA==.',
['Rä']='Räpodac:BAACLgAFFH8KAAIaAAMJLQdrDQCwAAAaAAMJLQdrDQCwAAAuAAQKfy8AAhoACQljEbAGAP0AABoACQljEbAGAP0AAAAA.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Sajae:BAAALgAECgEJAQAAAA==.Saphil:BAAALgAECgEJAgAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Scarypantz:BAAALgAECgEJAgAAAA==.Schizo:BAACLgAFFH8KAAIOAAIJtxqG1ACMAAAOAAIJtxqG1ACMAAAuAAQKfx0AAg4ABwngIfNAADUCAA4ABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgIJBAAAAA==.Sefiroth:BAACLgAFFH8IAAISAAMJZA34LgCeAAASAAMJZA34LgCeAAAuAAQKfy4AAhIABwnTFSdbAHYBABIABwnTFSdbAHYBAAAA.Selenora:BAAALgAECgIJAgABLgAFFAMJCgAOAF8hAA==.Selillea:BAAALgAECgYJBwAAAA==.Semarius:BAAALgAECgEJAwABLgAECgkJNwAaAKQhAA==.Semdorii:BAABLgAECn83AAIaAAkJpCGdBAD+AgAaAAkJpCGdBAD+AgAAAA==.Sephywrath:BAABLgAECn8+AAIlAAkJoRs5AgBIAgAlAAkJoRs5AgBIAgAAAA==.Seralith:BAACLgAFFH8KAAIOAAMJXyFHKgAJAQAOAAMJXyFHKgAJAQAuAAQKf08AAw4ACQmTJSoDAGwDAA4ACQmTJSoDAGwDAA0ABgk0H68OAIoBAAAA.Seranight:BAACLgAFFH8cAAMkAAUJtiQ6EACAAQAkAAUJtiQ6EACAAQAOAAEJJwEyKQEnAAAuAAQKf1sAAiQACQmTJmwAAHcDACQACQmTJmwAAHcDAAAA.Seven:BAAALgAECgIJBAABLgAECgkJJAABAEcWAA==.Sevenpaws:BAAALgAECgcJDAABLgAFFAMJCgATACUmAA==.',
Sh='Shadowchi:BAABLgAECn8jAAIDAAYJkgs7HQC+AAADAAYJkgs7HQC+AAAAAA==.Shadowspawnn:BAAALgADCgEJAQAAAA==.Shadowwhisp:BAAALgAECgEJAQAAAA==.Shaidon:BAAALgAECgYJBgAAAQ==.Shaly:BAABLgAECn8jAAIbAAgJPwZ7qAAtAQAbAAgJPwZ7qAAtAQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Sheesh:BAAALgAECgUJBQAAAA==.Shinjihirako:BAAALgAECgQJBwAAAA==.Shirohige:BAABLgAECn8mAAIiAAYJRw7KCAC9AAAiAAYJRw7KCAC9AAAAAA==.Shlonglord:BAAALgADCgIJAgAAAA==.Shylan:BAABLgAFFH8FAAIRAAEJGB4OKgBMAAARAAEJGB4OKgBMAAAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDgAAAA==.',
Sn='Snaarf:BAAALgADCgEJAQABLgAECgYJIgAeALgFAA==.Snayre:BAACLgAFFH8OAAIYAAQJohlhDgBSAQAYAAQJohlhDgBSAQAuAAQKfzUAAhgACQlxHt8FAMcCABgACQlxHt8FAMcCAAAA.Snipêr:BAABLgAECn8dAAIZAAgJ3RN7SADIAQAZAAgJ3RN7SADIAQAAAA==.Snowlia:BAACLgAFFH8KAAIVAAMJahM5UgCuAAAVAAMJahM5UgCuAAAuAAQKfyEAAxUACQkxE/A1AKsBABUACQkxE/A1AKsBAA8AAQk3D06qACwAAAAA.',
So='Soularis:BAAALgAECgYJCAAAAA==.Soulslice:BAEALgAECggJCAABLgAECgQJEQAKAAAAAA==.Sovrano:BAAALgADCgEJAQAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAABLgAECn8dAAMmAAgJ2wbbEQDtAAAmAAcJvwbbEQDtAAAjAAIJxAS8CwAWAAAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJEAAAAA==.',
St='Stalkingwolf:BAABLgAECn8rAAIkAAgJbxhHGQCWAQAkAAgJbxhHGQCWAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgAECgYJEQAAAA==.',
Sy='Sylailia:BAACLgAFFH8QAAIHAAQJNwzUDgDrAAAHAAQJNwzUDgDrAAAuAAQKfz8AAgcACQm3HbcJALgCAAcACQm3HbcJALgCAAAA.Syleta:BAAALgADCgMJBAAAAA==.Sylvia:BAAALgAECgIJAwAAAA==.',
['Sí']='Síenna:BAAALgAECgEJAwAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAMJBgAPALsLAA==.Tarlynna:BAAALgAECgMJAwAAAA==.Tazervis:BAAALgADCgEJAQAAAA==.',
Tc='Tcon:BAABLgAECn8UAAIYAAcJRBWpIQCPAQAYAAcJRBWpIQCPAQAAAA==.',
Td='Tdmage:BAAALgAECgMJAwABLgAECgkJMQAdAP4VAA==.Tdragon:BAAALgADCgkJEgABLgAECgkJMQAdAP4VAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thammer:BAAALgAECgYJBwABLgAECgkJMQAdAP4VAA==.Therea:BAAALgAECgEJAQAAAA==.Thissa:BAABLgAECn8uAAMHAAgJrx9rEQBPAgAHAAgJrx9rEQBPAgAgAAEJSBm4MwAzAAABLgAFFAQJBwAeAJMNAA==.Thundarah:BAAALgAECgMJAwAAAA==.Thundielocks:BAAALgADCgkJCQAAAA==.Thundruid:BAAALgADCgkJEgAAAA==.Thuniellas:BAAALgADCggJGQAAAA==.',
Ti='Tiarcis:BAABLgAECn8/AAIZAAkJAhtJAwBkAgAZAAkJAhtJAwBkAgAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Tostitos:BAAALgADCgkJCQABLgAECgkJMQAdAP4VAA==.Totemsalot:BAACLgAFFH8MAAIVAAQJjBu+KwA1AQAVAAQJjBu+KwA1AQAuAAQKfxsAAhUACQnGI7MDAIIDABUACQnGI7MDAIIDAAAA.',
Tr='Treesummoner:BAABLgAECn8tAAQBAAkJjRjrKgAuAgABAAkJjRjrKgAuAgADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgAECgIJAgAAAA==.Tritanks:BAACLgAFFH8HAAILAAIJSSGjAwDCAAALAAIJSSGjAwDCAAAuAAQKf0kAAgsACQlYJBsBADMDAAsACQlYJBsBADMDAAAA.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAKAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAABLgAECn8UAAIdAAcJpgzgPAAdAQAdAAcJpgzgPAAdAQAAAA==.Vali:BAAALgAECgYJCgAAAA==.Valiente:BAAALgAECgIJAgAAAA==.Valkah:BAAALgAECgEJAQAAAA==.Vasilia:BAABLgAECn89AAIkAAkJRBk1EAAIAgAkAAkJRBk1EAAIAgAAAA==.',
Ve='Velanna:BAAALgAECgIJAgAAAA==.Vexaris:BAABLgAECn8YAAIbAAcJ4w4PDgA1AQAbAAcJ4w4PDgA1AQAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgAFFAEJAwAAAA==.',
Vo='Voclus:BAABLgAECn8VAAIMAAgJVxKJPAAJAQAMAAgJVxKJPAAJAQAAAA==.',
Vy='Vykyrnarreia:BAAALgAECgMJAwAAAA==.',
Wa='Wall:BAAALgAECgYJEwAAAA==.Warlodshenu:BAAALgADCgcJCwAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
We='Weyaeh:BAAALgADCgIJAgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wulfbayne:BAAALgAECgQJBQAAAA==.Wuwindtang:BAAALgAECgUJDAAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgAECgEJAQAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAIQAAYJqQXzbACxAAAQAAYJqQXzbACxAAAAAA==.Xiletank:BAAALgAECgUJBQAAAA==.',
Ya='Yasutorasado:BAAALgAECgYJBwAAAA==.',
Za='Zachxd:BAABLgAECn88AAISAAcJ6RkTUgCPAQASAAcJ6RkTUgCPAQABLgAFFAIJCgAOALcaAA==.Zanthe:BAABLgAECn8XAAIHAAUJphNFCADjAAAHAAUJphNFCADjAAAAAA==.Zapanese:BAAALgADCgMJBAAAAA==.Zapt:BAAALgAECgIJAgAAAA==.Zaptism:BAABLgAECn87AAMTAAkJMCFGCADnAgATAAkJMCFGCADnAgAUAAUJhQ6hRwDoAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgAECgEJAQAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgYJEAABLgAFFAQJFAAMAGIhAA==.Zhanbear:BAAALgAECggJDAABLgAFFAQJFAAMAGIhAA==.Zhanbrew:BAACLgAFFH8UAAIMAAQJYiHWCgD/AAAMAAQJYiHWCgD/AAAuAAQKfyQAAgwACQnhIu8CACcDAAwACQnhIu8CACcDAAAA.Zhanfury:BAAALgAFFAEJAQABLgAFFAQJFAAMAGIhAA==.Zhanret:BAAALgAECgcJDQABLgAFFAQJFAAMAGIhAA==.',
Zi='Zinder:BAABLgAECn8nAAMeAAgJTQg+SgADAQAeAAgJTQg+SgADAQAmAAEJLAPXKwAeAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJjRe8BQAOAgADAAkJjRe8BQAOAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECgkJKgAiAG0aAA==.',
['Öb']='Öboron:BAACLgAFFH8JAAMYAAQJVgMNHgDiAAAYAAQJVgMNHgDiAAAIAAEJywHKPAAsAAAuAAQKfy4ABBgACQmMF0wPADkCABgACQknFkwPADkCAAgACAlWECgqANoBABkABgkpFTJTAG8BAAAA.',
['Üz']='Üz:BAABLgAECn8kAAIaAAgJvhbQGAC8AQAaAAgJvhbQGAC8AQAAAA==.',
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
