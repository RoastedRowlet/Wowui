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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Unknown-Unknown','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Vengeance','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Warrior-Fury','Warrior-Protection','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Shaman-Restoration','Warrior-Arms','Monk-Mistweaver','DeathKnight-Blood','Hunter-Survival','Hunter-BeastMastery','DemonHunter-Havoc','Mage-Frost','Druid-Restoration','Priest-Shadow','Evoker-Augmentation','Monk-Windwalker','Druid-Guardian','Shaman-Enhancement','Druid-Feral','Evoker-Preservation','Mage-Fire','Evoker-Devastation','Paladin-Protection',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aandra:BAABLgAECn8wAAQBAAkJLiDlFwDFAgABAAkJLiDlFwDFAgACAAIJGxY+HACRAAADAAEJBAMDfgAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgABLgAECgEJAQAEAAAAAA==.',
Ad='Addely:BAAALgAECgYJCAAAAA==.Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgUJEAAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIFAAcJqRqucACbAQAFAAcJqRqucACbAQAAAA==.',
Ai='Aithis:BAEALgAECgQJEQAAAA==.',
Al='Alerion:BAABLgAECn8sAAIGAAkJKhnoDABYAgAGAAkJKhnoDABYAgAAAA==.Allan:BAABLgAECn8rAAIHAAkJbiEEAQDEAgAHAAkJbiEEAQDEAgAAAA==.Alligatorjoe:BAAALgAECgMJAwAAAA==.',
Am='Amaneeda:BAABLgAECn81AAIIAAkJghCyKgB/AQAIAAkJghCyKgB/AQAAAA==.Amazonia:BAABLgAECn8jAAIJAAYJWxgoEQBHAQAJAAYJWxgoEQBHAQAAAA==.Aminea:BAABLgAFFH8QAAIKAAQJ9hchEwDPAAAKAAQJ9hchEwDPAAAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAEAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAACLgAFFH8HAAILAAIJHhUMDQB3AAALAAIJHhUMDQB3AAAuAAQKfy8AAgsACAkhIuwDAJECAAsACAkhIuwDAJECAAEuAAUUBAkUAAwAYiEA.Angyrain:BAAALgAECgUJBgABLgAFFAQJFAAMAGIhAA==.Annerila:BAAALgAECgYJDgAAAA==.Antagonis:BAABLgAECn8iAAIDAAcJSA8tEwAZAQADAAcJSA8tEwAZAQAAAA==.',
Ap='Apexchi:BAAALgAECgYJEwAAAA==.Apeximmortal:BAABLgAECn8UAAMNAAcJZwt3GwDzAAANAAcJZwt3GwDzAAAOAAEJUwhtMwElAAAAAA==.Apexlight:BAAALgAECgkJEQAAAA==.Apexwar:BAAALgAECgcJCAAAAA==.',
Ar='Arashe:BAABLgAECn8cAAIPAAcJkgY+EwCtAAAPAAcJkgY+EwCtAAAAAA==.Arewen:BAAALgADCggJEQAAAA==.Arganos:BAABLgAECn8wAAMQAAkJtSbdAQBeAwAQAAkJtSbdAQBeAwARAAYJFxtAGQBzAQAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8WAAISAAcJ6wTouwC0AAASAAcJ6wTouwC0AAAAAA==.Arkstrife:BAAALgADCgEJAQAAAA==.Artherüs:BAAALgADCgEJAQAAAA==.Arthuse:BAAALgAECgEJAQAAAA==.Arwyn:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgAECgUJBQAAAA==.Atheîst:BAACLgAFFH8NAAMTAAMJJSahCgAIAQAUAAMJFSEmEgAaAQATAAMJlyWhCgAIAQAuAAQKf0gAAxMACQl8JcwBAFoDABMACQl3JcwBAFoDABQACQnnIioFADgDAAAA.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn9aAAMVAAkJjh+sGQB9AgAVAAgJHx+sGQB9AgAPAAgJgB2YFgAxAgAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAcJFQAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECgkJMAAQALUmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8cAAMWAAcJuRqcFQCwAQAWAAcJuRqcFQCwAQAQAAIJpRDykwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8fAAIXAAYJ9RWiPgB0AQAXAAYJ9RWiPgB0AQAAAA==.Baelanoth:BAABLgAECn89AAMNAAkJRB4iBgBJAgANAAkJLB0iBgBJAgAYAAUJZCBhBQByAQAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balerion:BAAALgAECgEJAgAAAA==.Balkazaar:BAAALgAECggJEQAAAA==.Bammbamm:BAABLgAECn8xAAIFAAkJ1QrQmwA+AQAFAAkJ1QrQmwA+AQAAAA==.Banewreak:BAACLgAFFH8QAAIBAAMJ8BEnMQDCAAABAAMJ8BEnMQDCAAAuAAQKfzoAAgEACQmtGDMmAEUCAAEACQmtGDMmAEUCAAAA.Banu:BAAALgAECgQJBQAAAA==.Baradin:BAABLgAECn8UAAIKAAcJGBWuKADHAQAKAAcJGBWuKADHAQAAAA==.Barind:BAABLgAECn8yAAQZAAkJFh0xCQCLAgAZAAkJmRwxCQCLAgAJAAcJIxqYJAADAgAaAAIJuRrOnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Belanklin:BAAALgAECgQJBAAAAA==.Bena:BAAALgADCgMJAwAAAA==.Benneel:BAAALgADCgcJBwAAAA==.Berñy:BAAALgAECgQJCQAAAA==.Betrayer:BAACLgAFFH8QAAIbAAQJTRqtDABFAQAbAAQJTRqtDABFAQAuAAQKfyIAAhsACQnuIT8EAAcDABsACQnuIT8EAAcDAAAA.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Bietony:BAABLgAECn8WAAINAAgJWBPWDACrAQANAAgJWBPWDACrAQABLgAECgkJHgAVAJcNAA==.Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Bignfugly:BAAALgAECgUJBQABLgAECgkJCQAEAAAAAA==.Biqdonk:BAAALgAECgUJDAAAAA==.',
Bl='Blindpenzu:BAAALgAECgMJBQAAAA==.Bloodhornz:BAAALgAECgUJCAAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Bobthemage:BAAALgAECgEJAQAAAA==.Boogie:BAABLgAECn8XAAMKAAkJLxmEAQCpAgAKAAkJLxmEAQCpAgAFAAEJAABxfQAAAAAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Booßoo:BAAALgAECgEJAQAAAA==.Bossbeast:BAAALgADCgcJDQABLgADCgYJCwAEAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAEAAAAAA==.Bossdwarf:BAAALgADCgcJCwABLgADCgYJCwAEAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleosévèn:BAABLgAECn8iAAMKAAgJQCANAQDsAgAKAAgJQCANAQDsAgAFAAQJyAM4ZAAyAAABLgAFFAMJDQATACUmAA==.Buddro:BAAALgAECgIJAwAAAA==.',
['Bú']='Búbblés:BAAALgAECgcJDQAAAA==.',
Ca='Caatia:BAAALgAFFAIJAwAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Capzeil:BAAALgAECgcJDAAAAA==.Carrier:BAAALgAECgEJAQAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgkJJAABAEcWAA==.Carthel:BAABLgAECn8fAAIcAAgJMiBYMQCtAgAcAAgJMiBYMQCtAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCggJDgAAAA==.',
Ce='Cerisi:BAAALgAECgEJAQABLgAFFAQJEAAKAPYXAA==.Cerrydwyn:BAAALgAECgUJBQAAAA==.',
Ch='Charley:BAABLgAECn8cAAIcAAcJ9AscGwADAQAcAAcJ9AscGwADAQAAAA==.Chasseresse:BAABLgAECn8hAAIaAAYJiBk1XgCMAQAaAAYJiBk1XgCMAQAAAA==.Cherry:BAAALgAECgYJAQAAAA==.Chi:BAAALgAECgEJAgAAAA==.Chimarr:BAABLgAECn8cAAIdAAgJFiK5EADLAgAdAAgJFiK5EADLAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Cm='Cmondie:BAAALgAECgYJCgAAAA==.',
Co='Coldsploder:BAACLgAFFH8IAAIcAAMJ4gZSjQC+AAAcAAMJ4gZSjQC+AAAuAAQKfy0AAhwACQlaF7gzAEoCABwACQlaF7gzAEoCAAAA.',
Cr='Crackmonkéy:BAACLgAFFH8IAAIUAAMJpQ0MIACQAAAUAAMJpQ0MIACQAAAuAAQKfxoABBQACAnYGBIrAH0BABQABwk0FBIrAH0BABMABAmRGVZPAPsAAB4ABAl0EDhBAO8AAAEuAAUUBAkHAB8Akw0A.Cranknspank:BAAALgAECgYJBwAAAA==.Cronoz:BAABLgAECn8mAAMVAAkJMQrbWQAhAQAVAAgJUAfbWQAhAQAPAAgJ0wnpRAAgAQAAAA==.Crotchshot:BAABLgAECn8oAAIaAAkJFxNBNgAEAgAaAAkJFxNBNgAEAgAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.Crâmps:BAAALgADCggJCwAAAA==.',
Cu='Culodevour:BAAALgAECgYJCAAAAA==.Cursess:BAACLgAFFH8SAAIBAAMJVSIDTQAsAQABAAMJVSIDTQAsAQAuAAQKfzUAAgEACQlxIh4NAOQCAAEACQlxIh4NAOQCAAAA.',
['Có']='Cózmik:BAABLgAECn8UAAIaAAcJ3RZBXQCOAQAaAAcJ3RZBXQCOAQAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAABLgAECn8+AAIBAAkJHBYOLgAgAgABAAkJHBYOLgAgAgAAAA==.Dalya:BAABLgAFFH8MAAIaAAMJBBhqLADyAAAaAAMJBBhqLADyAAAAAA==.Dander:BAAALgAECgEJAQAAAA==.Dani:BAAALgAECgEJAgABLgAECgQJBQAEAAAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkridder:BAAALgAECgEJAQAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAABLgAECn8WAAIdAAgJfxlrKwD9AQAdAAgJfxlrKwD9AQAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Deathratellr:BAAALgADCgEJAQAAAA==.Deemaius:BAAALgAECgEJAgAAAA==.Dekard:BAAALgAECgEJAgAAAA==.Dekariusly:BAAALgAECgQJBQABLgAFFAEJAQAEAAAAAA==.Deltee:BAAALgAECgMJAwABLgAECgkJOQAgAO0cAA==.Demonatrixx:BAAALgAECgYJCQAAAA==.Demonhugger:BAAALgAECgEJAgABLgAECgUJBQAEAAAAAA==.Demonicus:BAAALgADCgEJAQAAAA==.Demonkila:BAAALgAECgUJBgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHwACAFwZAA==.Destinÿ:BAABLgAECn8rAAIRAAkJvhYnBAB3AQARAAkJvhYnBAB3AQAAAA==.Devourer:BAABLgAECn84AAISAAkJQBueKgAeAgASAAkJQBueKgAeAgAAAA==.',
Di='Disploder:BAABLgAECn8sAAITAAgJdBQNHwDMAQATAAgJdBQNHwDMAQAAAA==.Dist:BAAALgAECgkJDgAAAA==.',
Do='Doctafuzz:BAAALgAECgcJDAAAAA==.Dommiemommie:BAAALgAECgIJAgAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJBAAAAA==.Drawwn:BAAALgAECgEJAgABLgAECgEJBAAEAAAAAA==.Dreathhammer:BAABLgAECn8uAAIKAAkJ1SLDAwBiAwAKAAkJ1SLDAwBiAwAAAA==.Drogo:BAABLgAFFH8HAAIfAAQJkw34MgD2AAAfAAQJkw34MgD2AAAAAA==.Drureds:BAAALgAECgQJDQABLgAECgYJCAAEAAAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAkJLwAKAAkfAA==.',
Du='Duckcox:BAAALgAECgQJBwAAAA==.Dunadin:BAABLgAECn8ZAAQXAAYJbR20MgCsAQAXAAYJbR20MgCsAQAMAAIJ4xJKaQB0AAAgAAEJthXekQA/AAABLgAECgkJPwALAK4mAA==.Dundyrn:BAABLgAECn8/AAILAAkJriY3AAB0AwALAAkJriY3AAB0AwAAAA==.Dunhara:BAABLgAFFH8GAAIhAAUJvBktBwAqAQAhAAUJvBktBwAqAQABLgAECgkJPwALAK4mAA==.',
Dv='Dvera:BAAALgAECgIJAgAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECgkJPwALAK4mAA==.',
Ec='Echosïx:BAAALgADCgcJBwAAAA==.Ecks:BAAALgAECgMJAwABLgAFFAgJEgARAP0aAA==.',
Ed='Edmunin:BAAALgAECgYJAwAAAA==.',
El='Elememetal:BAABLgAECn8pAAIPAAkJvxgHHAABAgAPAAkJvxgHHAABAgAAAA==.Elfyparker:BAAALgAECgEJAgAAAA==.Elliott:BAAALgADCgIJAgAAAA==.Elwhityy:BAAALgAECgEJAgAAAA==.',
En='Enigmä:BAAALgAECgIJBAAAAA==.',
Ex='Exí:BAAALgAECgMJAwAAAA==.',
Fa='Fangora:BAAALgADCgMJAwAAAA==.Fangzz:BAAALgADCgEJAQAAAA==.Fanmir:BAAALgAECgEJAgAAAA==.Fatpao:BAABLgAECn8dAAIWAAYJjRsdBABYAQAWAAYJjRsdBABYAQAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAIVAAcJXQtGgQDdAAAVAAcJXQtGgQDdAAAAAA==.Fenix:BAAALgADCgcJCQABLgAECgkJMQAeAP4VAA==.',
Ff='Ffxivlover:BAAALgADCgIJAgAAAA==.',
Fi='Filbert:BAABLgAECn8dAAIIAAkJUyGEBwDeAgAIAAkJUyGEBwDeAgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Foldyholds:BAAALgAECgUJCQAAAA==.Fomy:BAAALgAECgEJAQAAAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDgAEAAAAAA==.',
Fr='Fraw:BAAALgADCggJDAAAAA==.Frizzel:BAAALgAECgQJBAAAAA==.Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAwAAAA==.Furyofdawn:BAAALgAECgEJAwAAAA==.Fuzzyhunter:BAAALgAECgUJBwABLgAECgkJMQAeAP4VAA==.',
['Fá']='Fálola:BAABLgAECn89AAMVAAgJrxffKADsAQAVAAgJrxffKADsAQAPAAYJwwOjcACYAAAAAA==.',
Ga='Galestina:BAAALgAECgYJBgAAAA==.Gamblex:BAABLgAECn8eAAIRAAcJ5BQ1BQBDAQARAAcJ5BQ1BQBDAQAAAA==.Garviel:BAABLgAECn8jAAIWAAkJCRwNCAB0AgAWAAkJCRwNCAB0AgAAAA==.',
Ge='Geeblast:BAAALgAECgMJAwABLgAECggJGQABABMWAA==.Geegoless:BAAALgAECgQJBAABLgAECggJGQABABMWAA==.Geeplague:BAAALgAECgMJBQABLgAECggJGQABABMWAA==.Geethatlock:BAABLgAECn8ZAAIBAAgJExa5RwDDAQABAAgJExa5RwDDAQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAABLgAECn9HAAIJAAkJchneAABdAgAJAAkJchneAABdAgAAAA==.Girthlord:BAAALgAECgQJBAABLgAECgkJPgABABwWAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Goobgobbler:BAAALgAECgEJAQAAAA==.Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Gravincar:BAAALgAFFAIJAgABLgAECgkJPwALAK4mAA==.Gravlocks:BAAALgADCgEJAQAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAABLgAECn8nAAIVAAgJ8RueHwBSAgAVAAgJ8RueHwBSAgAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grimace:BAAALgAECgMJAwAAAA==.Grogu:BAABLgAECn8eAAIcAAcJBQpeswAcAQAcAAcJBQpeswAcAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Grooble:BAAALgAECgQJBAAAAA==.Grooldaddy:BAAALgAECgEJAQAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJBgAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Hahaha:BAAALgAFFAMJBAAAAA==.Halfas:BAAALgADCgkJDQAAAA==.Haranir:BAAALgAECgEJAgAAAA==.',
He='Helkyrie:BAAALgADCgcJJAAAAA==.Helleer:BAAALgADCgcJBwAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECgkJLgAiAL0fAA==.Hiksham:BAABLgAECn8uAAMiAAkJvR9ABQCSAgAiAAkJnB9ABQCSAgAPAAgJBw3+OwBFAQAAAA==.Hilarycliton:BAAALgADCgMJAwAAAA==.',
Ho='Holycheeze:BAAALgAECgEJAQAAAA==.Holyhoof:BAAALgAECgEJAQAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgkJJAABAEcWAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgcJHAAVAMcWAA==.',
Ia='Iamreggi:BAAALgAECgQJBgAAAA==.',
Ih='Ihealzufool:BAABLgAECn8xAAIeAAkJ/hW/FwAKAgAeAAkJ/hW/FwAKAgAAAA==.',
Il='Illistia:BAAALgADCgYJBgABLgAFFAQJEAAKAPYXAA==.',
Im='Im:BAAALgAFFAMJBAAAAA==.Imded:BAAALgAECgQJBAAAAA==.',
In='Innogen:BAAALgAECgEJAQAAAA==.',
Ir='Irisi:BAAALgADCgUJBQABLgAFFAQJEAAKAPYXAA==.',
Ja='Jalene:BAAALgAECgUJDwAAAA==.Jargyn:BAAALgAECgYJEQABLgAECgkJKgAhAG0aAA==.Jarlyss:BAABLgAECn8qAAIhAAkJbRp4DAAZAgAhAAkJbRp4DAAZAgAAAA==.Javieraa:BAABLgAECn8gAAISAAkJYRruJQA2AgASAAkJYRruJQA2AgAAAA==.',
Jd='Jdai:BAABLgAECn8cAAIVAAcJxxYYPQC6AQAVAAcJxxYYPQC6AQAAAA==.',
Je='Jethrogibbs:BAAALgADCggJCAAAAA==.',
Jo='Jocecilla:BAAALgAFFAEJAQABLgAFFAIJAwAEAAAAAA==.Jorschwa:BAAALgAECgEJAgAAAA==.',
Ju='Juglight:BAABLgAECn8TAAIFAAkJ/xrlPAARAgAFAAkJ/xrlPAARAgAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.Junovay:BAAALgAECgMJBAABLgAECgYJCAAEAAAAAA==.',
Ka='Kaelithra:BAAALgAECgQJBAAAAA==.Kaishuka:BAAALgAECgEJAwAAAA==.Karannya:BAAALgAECgMJAwAAAA==.Karlplkngton:BAAALgAECgEJAQAAAA==.Kasna:BAAALgAECgkJCQAAAA==.Kazarian:BAAALgAECgkJEAAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8jAAISAAkJ0xtkFgD+AQASAAkJ0xtkFgD+AQAuAAQKf0MAAhIACQlkJLEEADsDABIACQlkJLEEADsDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn89AAIbAAkJsRDzIABxAQAbAAkJsRDzIABxAQAAAA==.Kikyo:BAAALgAECgYJEgAAAA==.Kimmi:BAAALgAECgUJEAAAAA==.Kimmuriel:BAAALgADCgMJAwAAAA==.Kinzen:BAABLgAECn8xAAIiAAcJhSDADQDTAQAiAAcJhSDADQDTAQAAAA==.Kireffej:BAAALgADCgEJAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIjAAYJAyEjDQDmAQAjAAYJAyEjDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8jAAIcAAgJPApLkABXAQAcAAgJPApLkABXAQAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgAECgIJAgABLgAECgkJPAAUAPAeAA==.',
Le='Lechwe:BAABLgAECn8/AAIVAAkJKhxhEADNAgAVAAkJKhxhEADNAgAAAA==.Legolase:BAAALgAECgEJAQAAAA==.Legonator:BAAALgAECgUJCAAAAA==.Lenry:BAAALgAFFAEJAQABLgAFFAcJGAALAPAcAA==.',
Li='Lichmajor:BAABLgAECn8nAAIOAAkJ6BjnRwDqAQAOAAkJ6BjnRwDqAQAAAA==.Lightfeet:BAAALgAECgQJBQABLgAECgkJRAAaAAgeAA==.Liion:BAAALgADCggJDwAAAA==.Lilladi:BAAALgADCgIJAgAAAA==.Lilleymage:BAAALgAECgEJAQAAAA==.Lingmi:BAAALgADCgUJBQAAAA==.Littlefang:BAAALgAECgQJBAAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn85AAMgAAkJ7RxVAQCaAgAgAAkJ7RxVAQCaAgAXAAcJICGWFQBtAgAAAA==.Lostrage:BAAALgAECgEJAQABLgAECgkJOQAgAO0cAA==.Lovepet:BAABLgAECn9EAAMaAAkJCB5zGgCHAgAaAAkJCB5zGgCHAgAJAAYJCQdyUwD+AAAAAA==.',
Lt='Ltlesunshine:BAABLgAECn8yAAMOAAkJZh29AwCmAgAOAAkJZh29AwCmAgAYAAYJbQ2XCQDhAAAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn83AAIcAAkJbiB+IgCTAgAcAAkJbiB+IgCTAgAAAA==.Lunavis:BAAALgAECgcJDgABLgAECgkJGgAdAPUNAA==.',
Ly='Lyda:BAABLgAECn89AAIdAAkJSBv5GAB+AgAdAAkJSBv5GAB+AgAAAA==.',
['Lû']='Lûnitari:BAAALgAECgEJAQABLgAECgcJKgAdALYRAA==.',
Ma='Mabui:BAAALgADCgkJCQAAAA==.Magice:BAABLgAECn8pAAIcAAgJtwX/IQDVAAAcAAgJtwX/IQDVAAAAAA==.Magmara:BAABLgAECn8VAAIiAAYJvxBoBgAEAQAiAAYJvxBoBgAEAQAAAA==.Majajical:BAAALgAECgEJAQAAAA==.Malibubarbie:BAABLgAECn82AAITAAkJsw7bJwCHAQATAAkJsw7bJwCHAQAAAA==.Malthael:BAAALgAECgIJAwAAAA==.Malystron:BAABLgAECn8UAAIFAAkJ/wrTfAB1AQAFAAkJ/wrTfAB1AQAAAA==.Maneevent:BAABLgAECn8ZAAQaAAYJGRfwiAAtAQAaAAYJGRfwiAAtAQAZAAEJ1wSAagAoAAAJAAEJVQNjlQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn88AAMUAAkJ8B6bBwAAAwAUAAkJ8B6bBwAAAwAeAAYJbgz2NQA8AQAAAA==.Maysty:BAABLgAECn9CAAIaAAkJUgoaVACnAQAaAAkJUgoaVACnAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8cAAQjAAgJ9hfaAgCmAQAjAAUJTxvaAgCmAQAhAAQJNxkBBwAtAQAIAAQJoxFBHwCJAAAuAAQKfyoABCMACQkiI0sCAAgDACMACQkiI0sCAAgDACEAAQkxIY0pAFQAAAgAAQkqFdODAEEAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn8/AAITAAkJ9RPGBAC/AQATAAkJ9RPGBAC/AQAAAA==.',
Mi='Midnightstar:BAABLgAECn8VAAIdAAYJqxKtTwBQAQAdAAYJqxKtTwBQAQABLgAFFAQJEAAKAPYXAA==.Milk:BAAALgAECgEJAQAAAA==.Mimolette:BAAALgAECgMJAwAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.Miseree:BAAALgAECgcJBwAAAA==.',
Mo='Modest:BAAALgAECgUJBQAAAA==.Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgAECgEJAgAAAA==.Moonbayne:BAACLgAFFH8IAAIIAAYJgw90DgA2AQAIAAYJgw90DgA2AQAuAAQKfzAAAggACQm9Gz8PAGsCAAgACQm9Gz8PAGsCAAAA.Mooszer:BAACLgAFFH8MAAIFAAIJXAZ8UgBuAAAFAAIJXAZ8UgBuAAAuAAQKfycAAgUACQm2CuoaAAcBAAUACQm2CuoaAAcBAAAA.Morder:BAAALgADCgYJCgAAAA==.Moregraine:BAAALgAECgEJAgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBwAAAA==.Mushu:BAABLgAECn8tAAIkAAkJSBr5BQCuAgAkAAkJSBr5BQCuAgAAAA==.',
Mv='Mvmt:BAAALgAECgcJCwAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJBgAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.Natre:BAAALgADCgIJAgAAAA==.',
Ne='Nemamiah:BAAALgADCgcJBwAAAA==.Nepharim:BAAALgAECgYJCwAAAA==.Nephlim:BAACLgAFFH8hAAMOAAkJZR7zDgAMAgAOAAgJZR7zDgAMAgAYAAEJAADMVQAAAAAuAAQKfzEAAg4ACQnmIcQGAGwDAA4ACQnmIcQGAGwDAAAA.Nergal:BAAALgADCgMJAwAAAA==.Newt:BAAALgAECgEJAQAAAA==.',
Ni='Ninobrown:BAAALgAECgYJEwAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJNwAcAG4gAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJNwAcAG4gAA==.Nizano:BAABLgAECn8jAAIFAAcJHgwytQAXAQAFAAcJHgwytQAXAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAEAAAAAA==.Noobie:BAAALgADCgYJCAAAAA==.Noryaa:BAABLgAECn8fAAIaAAYJQwYnrwDmAAAaAAYJQwYnrwDmAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.Notfurry:BAAALgAECgIJAgAAAA==.Novaloaf:BAAALgAECgMJAwABLgAECgkJMQAeAP4VAA==.',
Nu='Nuadå:BAABLgAECn8qAAMdAAcJthGwRQB6AQAdAAcJthGwRQB6AQAIAAQJbgWMagB3AAAAAA==.Nuala:BAAALgADCgUJBQAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Ol='Oliviä:BAAALgAECgEJAQABLgAECgEJAwAEAAAAAA==.',
Om='Om:BAAALgAECgkJEAAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAABLgAECn8kAAMTAAcJLRVUCgAIAQATAAUJnhJUCgAIAQAeAAYJyxTaFQCMAAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAAALgADCgEJAQABLgAECggJHAAdABYiAA==.Orcguyfive:BAAALgADCgEJAQAAAA==.Orkid:BAAALgAECgEJAgAAAA==.',
Pa='Pantoprazole:BAAALgAECgEJAgAAAA==.Pawsome:BAAALgAECgQJBAABLgAECgkJOwAPAOkZAA==.',
Pe='Penzmoo:BAAALgADCgEJAQAAAA==.',
Ph='Phelyx:BAACLgAFFH8FAAIdAAMJJwSYZwBMAAAdAAMJJwSYZwBMAAAuAAQKfxkAAx0ACQmhE5YDABcCAB0ACQmhE5YDABcCAAgAAgkiBQiIADoAAAAA.',
Pi='Pivotremix:BAAALgAECgYJBwAAAA==.',
Po='Pogo:BAABLgAECn8fAAIZAAkJdiR9AgAbAwAZAAkJdiR9AgAbAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwAZAHYkAA==.',
Pr='Pricedd:BAAALgADCggJDgABLgAECggJKQAcALcFAA==.Professional:BAAALgAECgEJAwAAAA==.Prosperina:BAAALgADCgQJBAABLgAFFAQJEAAKAPYXAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8lAAMDAAgJdQgmHQC+AAABAAgJhgcPmQALAQADAAYJvAomHQC+AAAAAA==.',
Qu='Quetzani:BAAALgAECgEJAQAAAA==.',
Ra='Ranoa:BAAALgADCgkJDgABLgAECggJFgAdAH8ZAA==.Rasputon:BAAALgAECgEJAQABLgAECgkJPAAUAPAeAA==.Rastapopulos:BAAALgAECgkJCwAAAA==.',
Re='Redmage:BAAALgADCgcJFgABLgAECgkJRAAaAAgeAA==.Redrocket:BAAALgAECgEJAgABLgAECgQJCQAEAAAAAA==.Rekkash:BAAALgAECgIJAgAAAA==.Remixed:BAAALgAECgQJBgAAAA==.Reptilectric:BAAALgAECgYJDwAAAA==.Retxd:BAAALgADCgIJAgABLgAECgQJBQAEAAAAAA==.',
Ri='Rikaku:BAABLgAECn8+AAIaAAcJHBUoFABEAQAaAAcJHBUoFABEAQAAAA==.',
Ro='Roastbeef:BAAALgAECgEJAQAAAA==.Ronananna:BAAALgADCgkJDwABLgADCgYJBgAEAAAAAA==.Rosemery:BAAALgAECgYJBwAAAA==.Roughdruid:BAAALgADCgMJAwAAAA==.',
['Râ']='Râpodac:BAAALgAECgUJBQAAAA==.Râpödac:BAAALgADCgIJAgAAAA==.',
['Rä']='Räpodac:BAACLgAFFH8KAAIbAAMJLQdtEgCfAAAbAAMJLQdtEgCfAAAuAAQKfy8AAhsACQljEWUKAP0AABsACQljEWUKAP0AAAAA.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Sajae:BAAALgAECgEJAQAAAA==.Saphil:BAAALgAECgEJAgAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Scarypantz:BAAALgAECgEJAgAAAA==.Schizo:BAACLgAFFH8KAAIOAAIJtxqG1ACMAAAOAAIJtxqG1ACMAAAuAAQKfx0AAg4ABwngIfNAADUCAA4ABwngIfNAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgIJBAAAAA==.Sefiroth:BAACLgAFFH8IAAISAAMJZA2QOQCRAAASAAMJZA2QOQCRAAAuAAQKfy4AAhIABwnTFSdbAHYBABIABwnTFSdbAHYBAAAA.Selenora:BAAALgAECgIJAgABLgAFFAMJDwAOAF8hAA==.Selillea:BAAALgAECgYJBwAAAA==.Semarius:BAAALgAECgEJAwABLgAECgkJNwAbAKQhAA==.Semdorii:BAABLgAECn83AAIbAAkJpCGdBAD+AgAbAAkJpCGdBAD+AgAAAA==.Sephywrath:BAABLgAECn8+AAIlAAkJoRs5AgBIAgAlAAkJoRs5AgBIAgAAAA==.Seralith:BAACLgAFFH8PAAIOAAMJXyGeNQD+AAAOAAMJXyGeNQD+AAAuAAQKf1AAAw4ACQmTJSoDAGwDAA4ACQmTJSoDAGwDAA0ABgk0H68OAIoBAAAA.Seranight:BAACLgAFFH8kAAMYAAUJRiU7CQB/AQAYAAUJRiU7CQB/AQAOAAEJJwEyKQEnAAAuAAQKf2QAAhgACQmTJmwAAHcDABgACQmTJmwAAHcDAAAA.Seven:BAAALgAECgIJBAABLgAECgkJJAABAEcWAA==.Sevenpaws:BAAALgAFFAEJAgABLgAFFAMJDQATACUmAA==.',
Sh='Shadowchi:BAABLgAECn8jAAIDAAYJkgs7HQC+AAADAAYJkgs7HQC+AAAAAA==.Shadowspawnn:BAAALgADCgEJAQAAAA==.Shadowwhisp:BAAALgAECgEJAQAAAA==.Shaidon:BAAALgAECgYJBgAAAQ==.Shaly:BAABLgAECn8jAAIcAAgJPwZ7qAAtAQAcAAgJPwZ7qAAtAQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Sheesh:BAAALgAECgUJCAAAAA==.Shinjihirako:BAAALgAECgQJBwAAAA==.Shirohige:BAABLgAECn8nAAIhAAcJgwzMCwDEAAAhAAcJgwzMCwDEAAAAAA==.Shlonglord:BAAALgADCgIJAgAAAA==.Shylan:BAABLgAFFH8FAAIRAAEJGB4OKgBMAAARAAEJGB4OKgBMAAAAAA==.',
Si='Sicarius:BAAALgAFFAEJAQAAAA==.Simmer:BAAALgADCgMJAwAAAA==.',
Sk='Skiie:BAAALgAECgEJAQABLgAECgcJIwAfABIGAA==.',
Sm='Smasha:BAAALgAECgQJDgAAAA==.',
Sn='Snaarf:BAAALgADCgEJAQABLgAECgcJIwAfABIGAA==.Snayre:BAACLgAFFH8OAAIZAAQJohlhDgBSAQAZAAQJohlhDgBSAQAuAAQKfzUAAhkACQlxHt8FAMcCABkACQlxHt8FAMcCAAAA.Snipêr:BAABLgAECn8dAAIaAAgJ3RN7SADIAQAaAAgJ3RN7SADIAQAAAA==.Snowlia:BAACLgAFFH8KAAIVAAMJahM5UgCuAAAVAAMJahM5UgCuAAAuAAQKfyEAAxUACQkxE/A1AKsBABUACQkxE/A1AKsBAA8AAQk3D06qACwAAAEuAAUUBAkQAAoA9hcA.',
So='Soularis:BAAALgAECgYJCAAAAA==.Soulslice:BAEALgAECggJCAABLgAECgQJEQAEAAAAAA==.Sovrano:BAAALgADCgEJAQAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAFAKkaAA==.Spybro:BAABLgAECn8dAAMmAAgJ2wbbEQDtAAAmAAcJvwbbEQDtAAAkAAIJxAT6EAAfAAAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJEAAAAA==.',
St='Stalkingwolf:BAABLgAECn8rAAIYAAgJbxhHGQCWAQAYAAgJbxhHGQCWAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgAECgYJEQAAAA==.',
Sy='Sylailia:BAACLgAFFH8RAAIIAAQJJBDZEgD4AAAIAAQJJBDZEgD4AAAuAAQKfz8AAggACQm3HbcJALgCAAgACQm3HbcJALgCAAAA.Syleta:BAAALgADCgMJBAAAAA==.Sylvia:BAAALgAECgIJAwAAAA==.Syrø:BAAALgAECgYJBwAAAA==.',
['Sí']='Síenna:BAAALgAECgEJAwAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAQJBwAPAAcKAA==.Tanyon:BAAALgAECgQJBQAAAA==.Tarlynna:BAAALgAECgMJAwAAAA==.Tazervis:BAAALgADCgEJAQAAAA==.',
Tc='Tcon:BAACLgAFFH8FAAIZAAIJ3xveDwChAAAZAAIJ3xveDwChAAAuAAQKfxQAAhkABwlEFakhAI8BABkABwlEFakhAI8BAAAA.',
Td='Tdmage:BAAALgAECgMJAwABLgAECgkJMQAeAP4VAA==.Tdragon:BAAALgADCgkJEgABLgAECgkJMQAeAP4VAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thammer:BAABLgAECn8UAAMFAAcJ9xZHDQCUAQAFAAcJ9xZHDQCUAQAnAAUJDg5CCwCsAAABLgAECgkJMQAeAP4VAA==.Therea:BAAALgAECgEJAQABLgAFFAQJEAAKAPYXAA==.Thissa:BAABLgAECn8uAAMIAAgJrx9rEQBPAgAIAAgJrx9rEQBPAgAjAAEJSBm4MwAzAAABLgAFFAQJBwAfAJMNAA==.Thundarah:BAAALgAECgcJCgAAAA==.Thundielocks:BAAALgADCgkJCQAAAA==.Thundruid:BAAALgADCgkJEgAAAA==.Thuniellas:BAAALgAECgUJBwAAAA==.',
Ti='Tiarcis:BAABLgAECn9LAAIaAAkJOhwzBQBnAgAaAAkJOhwzBQBnAgAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Tostitos:BAAALgADCgkJCQABLgAECgkJMQAeAP4VAA==.Totemsalot:BAACLgAFFH8MAAIVAAQJjBu+KwA1AQAVAAQJjBu+KwA1AQAuAAQKfxsAAhUACQnGI7MDAIIDABUACQnGI7MDAIIDAAAA.',
Tr='Treesummoner:BAACLgAFFH8JAAIBAAUJ6hBdKwDcAAABAAUJ6hBdKwDcAAAuAAQKfy0ABAEACQmNGOsqAC4CAAEACQmNGOsqAC4CAAMABQnrCnAsAAwBAAIAAwmhC9EaAKAAAAAA.Trialboost:BAAALgAECgUJBwAAAA==.Tritanks:BAACLgAFFH8MAAILAAIJ8iEMBQC/AAALAAIJ8iEMBQC/AAAuAAQKf1IAAgsACQmGJBsBADMDAAsACQmGJBsBADMDAAAA.Troy:BAAALgAECgIJAwAAAA==.Trulylolly:BAAALgADCgMJAwAAAA==.',
Tu='Tutsee:BAAALgADCggJFAAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAEAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAABLgAECn8UAAIeAAcJpgzgPAAdAQAeAAcJpgzgPAAdAQAAAA==.Vali:BAAALgAECgYJCgAAAA==.Valiente:BAAALgAECgIJAgAAAA==.Valkah:BAAALgAECgEJAQAAAA==.Valle:BAAALgAECgUJCgAAAA==.Vasilia:BAABLgAECn89AAIYAAkJRBk1EAAIAgAYAAkJRBk1EAAIAgAAAA==.',
Ve='Veladori:BAAALgADCgEJAQAAAA==.Velanna:BAAALgAECgIJAgAAAA==.Vexaris:BAABLgAECn8cAAIcAAcJvBUPDQCSAQAcAAcJvBUPDQCSAQAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.Viradi:BAAALgAFFAEJAwAAAA==.',
Vo='Voclus:BAABLgAECn8VAAIMAAgJVxKJPAAJAQAMAAgJVxKJPAAJAQAAAA==.',
Vy='Vykyrnarreia:BAAALgAECgMJAwAAAA==.',
Wa='Waldre:BAAALgAECgIJAgAAAA==.Wall:BAAALgAECgYJEwAAAA==.Warlodshenu:BAAALgADCgcJCwAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
We='Weyaeh:BAAALgADCgIJAgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightfire:BAAALgADCgEJAQAAAA==.Wightknight:BAAALgADCgYJBgAAAA==.Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.Wishingtroll:BAAALgAECgEJAQAAAA==.',
Wu='Wulfbayne:BAAALgAECgQJBQAAAA==.Wuwindtang:BAAALgAECgUJDAAAAA==.',
Xa='Xalatoes:BAAALgAECgEJAQAAAA==.',
Xe='Xeniuz:BAAALgAECgEJAQAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8XAAIQAAYJqQXzbACxAAAQAAYJqQXzbACxAAAAAA==.Xiletank:BAAALgAECgUJBQAAAA==.',
Ya='Yasutorasado:BAAALgAECgYJBwAAAA==.',
Za='Zachxd:BAABLgAECn88AAISAAcJ6RkTUgCPAQASAAcJ6RkTUgCPAQABLgAFFAIJCgAOALcaAA==.Zanthe:BAABLgAECn8YAAIIAAYJCBMhCwAMAQAIAAYJCBMhCwAMAQAAAA==.Zapanese:BAAALgADCgMJBAAAAA==.Zapt:BAAALgAECgIJAgAAAA==.Zaptism:BAABLgAECn8+AAMTAAkJJSJGCADnAgATAAkJJSJGCADnAgAUAAUJhQ6hRwDoAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgAECgEJAQAAAA==.',
Ze='Zen:BAAALgADCgMJAwAAAA==.Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanaug:BAAALgAECgYJEAABLgAFFAQJFAAMAGIhAA==.Zhanbear:BAAALgAECggJDAABLgAFFAQJFAAMAGIhAA==.Zhanbrew:BAACLgAFFH8UAAIMAAQJYiFyIAAsAQAMAAQJYiFyIAAsAQAuAAQKfyQAAgwACQnhIu8CACcDAAwACQnhIu8CACcDAAAA.Zhanfury:BAAALgAFFAEJAQABLgAFFAQJFAAMAGIhAA==.Zhanret:BAAALgAECgcJDQABLgAFFAQJFAAMAGIhAA==.',
Zi='Zinder:BAABLgAECn8nAAMfAAgJTQg+SgADAQAfAAgJTQg+SgADAQAmAAEJLAPXKwAeAAAAAA==.Zipit:BAABLgAECn8nAAIDAAkJjRe8BQAOAgADAAkJjRe8BQAOAgAAAA==.',
Zy='Zyae:BAAALgAECgEJBAAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECgkJKgAhAG0aAA==.',
['Öb']='Öboron:BAACLgAFFH8JAAMZAAQJVgMNHgDiAAAZAAQJVgMNHgDiAAAJAAEJywHKPAAsAAAuAAQKfy4ABBkACQmMF0wPADkCABkACQknFkwPADkCAAkACAlWECgqANoBABoABgkpFTJTAG8BAAAA.',
['Üz']='Üz:BAABLgAECn8kAAIbAAgJvhbQGAC8AQAbAAgJvhbQGAC8AQAAAA==.',
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
