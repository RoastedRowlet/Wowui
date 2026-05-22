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

local lookup = {'Shaman-Restoration','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Monk-Brewmaster','Paladin-Retribution','Paladin-Protection','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Holy','Priest-Holy','DemonHunter-Havoc','Shaman-Elemental','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Devourer','Priest-Shadow','DeathKnight-Blood','Evoker-Devastation','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Warrior-Arms','Evoker-Augmentation','Rogue-Subtlety','Warlock-Affliction','Hunter-Survival','Druid-Guardian','Mage-Frost','Rogue-Outlaw','Evoker-Preservation',}
local provider = {region='US',realm='Durotan',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aarmorr:BAABLgAECn8tAAIBAAgJ2xIwLQCoAQABAAgJ2xIwLQCoAQAAAA==.',
Ab='Absoul:BAAALgADCgEJAQAAAA==.',
Ac='Acinianis:BAAALgAECgEJAQAAAA==.Acinthos:BAAALgAECgIJBAAAAA==.',
Ad='Adiros:BAAALgADCgUJBQAAAA==.',
Ae='Aeloriá:BAABLgAECn8pAAMCAAgJER3aEQB7AgACAAgJER3aEQB7AgADAAEJFQGgOwAPAAAAAA==.Aelyra:BAAALgAECgcJDAAAAA==.',
Ai='Aimeeiove:BAAALgAECgMJAwAAAA==.Airad:BAAALgADCgUJBgAAAA==.',
Al='Alchon:BAABLgAECn8cAAIEAAkJGBqvIABBAgAEAAkJGBqvIABBAgAAAA==.Aldera:BAABLgAECn8dAAIBAAgJ/ATDUQADAQABAAgJ/ATDUQADAQAAAA==.Aledish:BAAALgAECgEJAgAAAA==.Alicien:BAABLgAECn8jAAMFAAkJwBx/LwD6AQAFAAkJwBx/LwD6AQAGAAEJyhBgFgA3AAAAAA==.Alladon:BAAALgADCgUJBQAAAA==.Allykat:BAABLgAECn8yAAMCAAcJXBQQMQCUAQACAAcJXBQQMQCUAQAHAAIJqwm8WgBRAAAAAA==.Alorris:BAAALgAECgQJBAABLgAECgcJFQAIALwhAA==.Alunathsong:BAAALgADCgcJBwAAAA==.Alvagíngras:BAAALgAECgYJCgAAAA==.Alyra:BAAALgADCgYJBgAAAA==.',
Am='Amata:BAAALgAECgQJBAAAAA==.Ammastary:BAAALgAECgQJBQAAAA==.Amorfati:BAAALgAECgEJAQAAAA==.',
An='Ananiel:BAAALgADCgQJBQABLgAECggJHgAJAE4VAA==.Andragos:BAAALgAECgQJBgAAAA==.Andrea:BAABLgAECn8sAAIDAAgJUBcTCQDYAQADAAgJUBcTCQDYAQAAAA==.Anthria:BAAALgAECgYJDwAAAA==.',
Ao='Aoon:BAAALgAECgEJAQAAAA==.',
Ap='Apoleth:BAAALgADCgMJAwAAAA==.',
Aq='Aqules:BAAALgADCgEJAgAAAA==.',
Ar='Archonsfury:BAAALgAECgIJBAAAAA==.Arilyn:BAAALgADCgcJEQAAAA==.Array:BAAALgAECgUJBQAAAA==.',
As='Asath:BAAALgAECgYJDAAAAA==.Ascended:BAAALgAECgEJAgAAAA==.Askir:BAAALgADCgMJAwAAAA==.Asnew:BAAALgAECgkJDgAAAA==.Asyllaa:BAABLgAECn8WAAMKAAgJsh5kJgAhAgAKAAcJQCJkJgAhAgALAAUJtRBcHgDKAAAAAA==.',
At='Atnawuerus:BAAALgADCgMJAwAAAA==.Atonement:BAAALgAECgIJBAABLgAECggJGgAMAOAdAA==.',
Au='Aumaril:BAAALgAECgMJAwAAAA==.Auralynn:BAABLgAECn8aAAIKAAgJ5QegggAeAQAKAAgJ5QegggAeAQAAAA==.',
Av='Avathar:BAAALgAECgMJBgAAAA==.Averus:BAABLgAECn8tAAIHAAgJQgsGKgAnAQAHAAgJQgsGKgAnAQAAAA==.',
Az='Azariel:BAABLgAECn8tAAIKAAkJixMJPADLAQAKAAkJixMJPADLAQAAAA==.Azenwraith:BAAALgADCgkJCQAAAA==.Azuriah:BAABLgAECn8nAAILAAgJmxovCAD9AQALAAgJmxovCAD9AQAAAA==.',
Ba='Baane:BAAALgAECgQJBAABLgAECgUJCwANAAAAAA==.Babnik:BAEALgAECgYJEwAAAA==.Bagel:BAACLgAFFH8NAAIOAAQJqiBdDQB/AQAOAAQJqiBdDQB/AQAuAAQKfxkAAw4ACAmCH1AmAPYBAA4ACAmCH1AmAPYBAAoAAQnkCko3ATMAAAAA.Baldwin:BAAALgADCgcJBwAAAA==.Baminenherb:BAAALgADCgUJBQAAAA==.Bazluz:BAAALgADCgEJAQAAAA==.',
Be='Bearlysoberr:BAAALgAECgUJBQAAAA==.Bedhead:BAABLgAECn8tAAMIAAgJ0BiADwAgAgAIAAgJABiADwAgAgAPAAMJFBx6VQDgAAAAAA==.Bedrocked:BAAALgAECgIJAwAAAA==.Belaim:BAAALgADCgcJCwAAAA==.Belovis:BAACLgAFFH8KAAIKAAQJvxsDGQBaAQAKAAQJvxsDGQBaAQAuAAQKfyYAAgoACQk0JNQIAO8CAAoACQk0JNQIAO8CAAAA.Berathor:BAAALgAECggJCgAAAA==.Betsea:BAAALgAECgUJBQABLgAECgkJLAAOAHEPAA==.',
Bi='Bidoof:BAABLgAECn8ZAAIQAAcJNAX+JgDaAAAQAAcJNAX+JgDaAAAAAA==.Bigblunt:BAAALgADCgQJBgAAAA==.Bigjohnii:BAAALgADCgcJBwAAAA==.Bitemarks:BAAALgADCgcJDgAAAA==.',
Bl='Blackcoat:BAAALgAECgUJDgAAAA==.',
Bo='Boggrog:BAAALgADCggJCAABLgAECgQJBAANAAAAAA==.Boosch:BAAALgADCgIJAgAAAA==.Bosshog:BAABLgAECn8kAAIRAAgJHAdbOAD8AAARAAgJHAdbOAD8AAAAAA==.Bowgobrr:BAABLgAECn8qAAMSAAgJ4xXSCQCHAQASAAgJ4xXSCQCHAQAEAAYJ2goanwCTAAABLgAFFAcJFwASAHoOAA==.',
Br='Braelyne:BAABLgAECn8VAAIKAAYJdR1eVgB+AQAKAAYJdR1eVgB+AQAAAA==.Brasnite:BAAALgADCgEJAQAAAA==.Brewrock:BAAALgAECgQJCAAAAA==.Brolaf:BAAALgAECgUJBQAAAA==.Broseidon:BAAALgAECgcJCwAAAA==.',
Bu='Buffsalot:BAAALgAECgUJDAAAAA==.Buffwarlock:BAAALgAECgcJBwAAAA==.Burlycheeks:BAABLgAECn80AAIKAAkJOyCCDwCxAgAKAAkJOyCCDwCxAgAAAA==.',
Ca='Carlitocool:BAAALgADCgIJAgAAAA==.Carraxus:BAAALgAECgQJBgAAAA==.Cassidyn:BAAALgADCgcJCAAAAA==.Castle:BAAALgAECgUJDAAAAA==.Catsneverdie:BAAALgAECgMJDAABLgAFFAMJBgAFAGQFAA==.Catzinhatz:BAAALgAECgcJEAABLgAFFAMJBgAFAGQFAA==.',
Ce='Cecelya:BAABLgAECn8xAAMPAAkJ5hmqDgAyAgAPAAkJ5hmqDgAyAgAIAAMJUw2APgCgAAAAAA==.Celibate:BAAALgAECgUJBgAAAA==.Celothor:BAAALgADCgYJBgAAAA==.Celticmoon:BAAALgADCgQJBAAAAA==.',
Ch='Cherlia:BAABLgAECn8ZAAIRAAYJNBC2RQAyAQARAAYJNBC2RQAyAQABLgAECgkJFgAQANgbAA==.Chivactdl:BAAALgADCgEJAQABLgAECgcJFwABALkdAA==.Chozen:BAAALgAECgcJCgAAAA==.Chunknoriss:BAAALgAECgYJEQABLgAECgcJFwABALkdAA==.',
Cl='Claudiuss:BAAALgAECgUJBQABLgAECgkJJgABAAAYAA==.Clurefu:BAABLgAECn8nAAMTAAkJiB9FBgDmAgATAAkJiB9FBgDmAgAUAAMJ5BZVWACuAAAAAA==.Clurelock:BAAALgAECgcJEQABLgAECgkJJwATAIgfAA==.Cluremage:BAAALgAECgYJBwAAAA==.',
Co='Codenameknd:BAAALgAECgIJAgAAAA==.Comsuck:BAAALgAECgcJEQAAAA==.Conchobhar:BAAALgAECgYJDwAAAA==.Constella:BAAALgADCgUJBQAAAA==.Coppertan:BAAALgADCggJCwAAAA==.Coralyne:BAAALgADCgEJAQAAAA==.Corrosion:BAABLgAECn8bAAIVAAgJXRjuCADMAQAVAAgJXRjuCADMAQAAAA==.',
Cr='Crazyshammy:BAAALgAECgcJDgAAAA==.Crommash:BAAALgAECgcJCgAAAA==.Crono:BAAALgAECgQJCQAAAA==.Crunchynuget:BAAALgAECgcJCgABLgAFFAQJCAAKAPEXAA==.',
Ct='Cthuwu:BAAALgADCgcJDgABLgAFFAUJCQAEAMMHAA==.',
Cu='Cujotaro:BAAALgAECgEJAQAAAA==.',
Cy='Cybeast:BAABLgAECn8jAAIDAAkJwxsaBgCdAgADAAkJwxsaBgCdAgAAAA==.Cynortas:BAAALgAECgIJAwAAAA==.',
Da='Daciana:BAAALgAECgUJEQAAAA==.Dados:BAABLgAECn8qAAIPAAkJ0BuSEgBMAgAPAAkJ0BuSEgBMAgAAAA==.Dahleigh:BAAALgADCgkJDQAAAA==.Dakanar:BAAALgADCgkJGAAAAA==.Dambrien:BAAALgAECgEJAQAAAA==.Daravus:BAAALgAECgUJCAAAAA==.Darkhazel:BAAALgAECgEJAQAAAA==.Darkkromdor:BAABLgAECn8hAAIKAAkJNR/6EwCPAgAKAAkJNR/6EwCPAgAAAA==.Darloct:BAAALgAECgQJCgAAAA==.Dazzlor:BAAALgADCggJCAAAAA==.',
De='Deadelff:BAABLgAECn8WAAMQAAcJLBnxJwCDAQAQAAYJexvxJwCDAQAWAAcJwA4kZgAHAQAAAA==.Deadholypaly:BAAALgADCgEJAwAAAA==.Deadlighted:BAAALgADCgcJDgABLgAECggJFgAQACwZAA==.Deadslinger:BAAALgADCgUJBgAAAA==.Deathcat:BAACLgAFFH8GAAIFAAMJZAXSSwBvAAAFAAMJZAXSSwBvAAAuAAQKfywAAgUACQl4FJlCALQBAAUACQl4FJlCALQBAAAA.Deathkiss:BAAALgAECgYJEgAAAA==.Deathrat:BAAALgADCgUJBgAAAA==.Deathrixx:BAABLgAFFH8OAAMFAAQJLx2BKwBbAQAFAAQJCh2BKwBbAQAGAAIJhB1fCgC4AAAAAA==.Deathshadowx:BAAALgAECgQJBAAAAA==.Delryth:BAAALgADCgkJCQAAAA==.Demonkoh:BAAALgAECgUJCAAAAA==.',
Df='Dfault:BAAALgADCgEJAQAAAA==.',
Di='Discharged:BAAALgADCgIJAgABLgAECggJGQAUAGIXAA==.',
Dk='Dkdeathblade:BAAALgAECgEJAQAAAA==.Dkpheonix:BAABLgAECn8kAAIXAAgJfQ1BIgBfAQAXAAgJfQ1BIgBfAQAAAA==.',
Do='Dolemite:BAABLgAECn8iAAMTAAYJsw11QADOAAATAAUJLw11QADOAAAUAAUJ7ApiPgC4AAAAAA==.Donalbain:BAABLgAECn8mAAIBAAkJABgaFQBOAgABAAkJABgaFQBOAgAAAA==.Dotdotgoose:BAAALgAECgQJCAAAAA==.',
Dr='Draconz:BAAALgADCgYJBgABLgAECgQJBQANAAAAAA==.Drakkira:BAAALgADCgYJBgAAAA==.Draxon:BAAALgAECgEJAQAAAA==.Dremar:BAAALgAECgUJDQAAAA==.',
Du='Durock:BAAALgAECgEJAQAAAA==.',
Dy='Dynaris:BAAALgADCgMJAwAAAA==.',
Ei='Eianna:BAAALgAECgEJAQAAAA==.',
El='Eldinn:BAAALgADCgcJBgAAAA==.Elidor:BAAALgAECgMJBQAAAA==.Elthelas:BAAALgADCgEJAQAAAA==.Eluneatic:BAAALgADCggJCgAAAA==.Elyssaris:BAABLgAECn8oAAIYAAgJXxdsFQBpAQAYAAgJXxdsFQBpAQAAAA==.Elzulkin:BAAALgADCgcJCgAAAA==.',
Em='Emmdeath:BAAALgAECgMJBAAAAA==.Emmils:BAABLgAECn8sAAIHAAkJWQr6IwBPAQAHAAkJWQr6IwBPAQAAAA==.Emìly:BAABLgAECn8xAAQUAAgJ9yH3BgCWAgAUAAgJ9yH3BgCWAgAJAAUJRRWbNQDrAAATAAQJpwvPUwB9AAAAAA==.',
En='Enderelvarg:BAABLgAFFH8FAAIZAAUJbw/aAgA4AQAZAAUJbw/aAgA4AQAAAA==.Endmicrobuys:BAAALgADCgUJBQAAAA==.Entaria:BAABLgAECn8uAAQKAAgJYiACJwAeAgAKAAgJDR8CJwAeAgALAAcJLR8nCAD+AQAOAAUJ1wyVTwCgAAAAAA==.',
Ep='Episkey:BAABLgAECn8YAAMHAAgJiQ+WJgA9AQAHAAgJiQ+WJgA9AQACAAMJEx3eVAD3AAAAAA==.',
Er='Erindaglaze:BAAALgADCgQJBQAAAA==.Eropor:BAAALgAECgMJBgABLgAECgkJRwACABEeAA==.Eroversion:BAABLgAECn9HAAQCAAkJER5SEACMAgACAAkJER5SEACMAgAHAAQJNRQ+VADVAAADAAMJKAZ8KQB+AAAAAA==.',
Es='Esmay:BAABLgAECn8YAAIRAAcJoA8oNAAQAQARAAcJoA8oNAAQAQAAAA==.Eso:BAAALgADCgYJCwAAAA==.',
Et='Ethren:BAABLgAECn8sAAIaAAgJkwxvCAB7AQAaAAgJkwxvCAB7AQAAAA==.',
Ev='Evilrepu:BAAALgAECgEJAQAAAA==.',
Ey='Eyebrows:BAAALgAECgIJAgAAAA==.',
Fa='Faker:BAAALgADCgEJAQAAAA==.Falcone:BAAALgAECgMJBgAAAA==.',
Fe='Felbolter:BAAALgADCgUJBwAAAA==.',
Fi='Filgulfin:BAABLgAECn8zAAMEAAkJ0hhqFABmAgAEAAkJ0hhqFABmAgASAAgJgBDnDQA2AQAAAA==.Finkate:BAAALgADCgkJGwAAAA==.Firebad:BAABLgAECn8wAAMbAAkJqBxBAQCcAgAbAAkJqBxBAQCcAgAcAAYJHwoHtACXAAAAAA==.Firebringer:BAABLgAECn80AAIWAAkJqgguUABFAQAWAAkJqgguUABFAQAAAA==.Fistokaestey:BAAALgADCgkJEgABLgAECggJEwANAAAAAA==.',
Fl='Flamehunter:BAABLgAECn8iAAMWAAkJMRqEHACnAgAWAAkJcRmEHACnAgAQAAcJLRdgJACaAQAAAA==.Flo:BAABLgAECn82AAMXAAkJ0xS1FwC3AQAXAAgJvhW1FwC3AQAPAAMJSAcwRQCAAAAAAA==.Floki:BAAALgAECgcJEAAAAA==.',
Fo='Foods:BAACLgAFFH8FAAMdAAIJGAYSHQCKAAAdAAIJGAYSHQCKAAAeAAEJLwTsIAAsAAAuAAQKfz0ABB0ACQnmFcASABMCAB0ACQm0FcASABMCAB4ABwl5Eq0WAD0BAB8AAgnDDE0wAHUAAAAA.',
Fr='Fripouille:BAAALgADCgMJAwAAAA==.',
Fu='Fustín:BAAALgAECgYJEgAAAA==.Fuzzyewok:BAAALgAECgYJEwAAAA==.',
Ga='Gaboo:BAAALgAECgcJDQAAAA==.',
Gh='Ghostinhale:BAAALgAECgUJDAAAAA==.',
Gi='Gilorion:BAAALgAECgYJEAAAAA==.',
Gl='Glasgoww:BAAALgAECgMJAwABLgAECgkJJgABAAAYAA==.',
Gn='Gnibat:BAAALgAECgMJAwAAAA==.',
Go='Goburina:BAACLgAFFH8FAAIBAAMJcgO6OACeAAABAAMJcgO6OACeAAAuAAQKfxgAAgEACQlaC1M9AIwBAAEACQlaC1M9AIwBAAAA.Golias:BAAALgADCgEJAQAAAA==.',
Gr='Grievo:BAAALgAECgYJCAAAAA==.',
Gy='Gypsiey:BAAALgAECgIJAgAAAA==.',
['Gí']='Gímlí:BAABLgAECn8jAAIEAAgJjhuZLwDMAQAEAAgJjhuZLwDMAQAAAA==.',
Ha='Halcyndraag:BAABLgAECn8tAAMgAAgJ4xEDKgA/AQAgAAYJ6hADKgA/AQAZAAMJ7xWRKADcAAAAAA==.Handbannana:BAAALgADCgcJBwAAAA==.Handsome:BAAALgAECgYJBgABLgAECggJDgANAAAAAA==.Happydk:BAACLgAFFH8GAAMYAAMJgRyuGAC7AAAYAAMJKRGuGAC7AAAFAAIJ5h9TdwC4AAAuAAQKfycAAwUACQnYIO8RAJ4CAAUACQnXHu8RAJ4CABgABwlKGf8ZADYBAAAA.Hartu:BAABLgAECn8wAAIeAAkJgw68EQB9AQAeAAkJgw68EQB9AQAAAA==.Harukasan:BAAALgADCgIJAgAAAA==.Hashpipe:BAAALgADCgMJAwAAAA==.Hazl:BAAALgAECgMJBAAAAA==.',
He='Healsofpain:BAAALgADCgYJBgAAAA==.Hellankeller:BAAALgAECgQJBwAAAA==.Hemic:BAABLgAECn8qAAMhAAkJUSGTBgCAAgAhAAkJviCTBgCAAgAaAAQJ8BpbCwA3AQAAAA==.Hemmorage:BAAALgAECgYJCQABLgAECggJIAAFAFgdAA==.Herbalmist:BAAALgAECgQJBAAAAA==.',
Hi='Higag:BAAALgADCgQJBAAAAA==.Hippypally:BAAALgADCgEJAQAAAA==.Hircine:BAAALgAECgMJAwAAAA==.',
Ho='Horatio:BAAALgADCgcJBwABLgAECgkJJgABAAAYAA==.',
Hu='Hukruun:BAAALgADCgEJAgAAAA==.',
['Hé']='Hélénkéller:BAAALgADCggJDwABLgAECgkJFwAEAKUbAA==.',
Ib='Ibhuntin:BAAALgAECggJEgAAAA==.',
Id='Idiocracy:BAAALgAECgYJBwAAAA==.Idk:BAAALgADCgYJCgAAAA==.',
Il='Illigirl:BAAALgADCgEJAQAAAA==.',
Im='Imwithfloki:BAAALgAECgIJAwAAAA==.',
In='Indoti:BAAALgADCgUJBwAAAA==.',
Ir='Ironmark:BAAALgAECgQJBAAAAA==.Irys:BAAALgADCgcJDgAAAA==.',
Is='Isam:BAAALgADCgYJBgAAAA==.Isamidor:BAACLgAFFH8MAAIEAAUJZCETCwCDAQAEAAUJZCETCwCDAQAuAAQKfxwAAgQACQmWI+cEAD8DAAQACQmWI+cEAD8DAAAA.Ismokeu:BAABLgAECn8qAAIPAAgJvhiaEQALAgAPAAgJvhiaEQALAgAAAA==.Ismyn:BAAALgADCgEJAgAAAA==.',
It='Itskemba:BAAALgADCgYJBgAAAA==.',
Iy='Iyania:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneal:BAAALgAECgcJCAAAAA==.Jalidelo:BAABLgAECn8wAAMIAAkJdxczDABVAgAIAAkJdxczDABVAgAPAAEJ5gZihgAqAAAAAA==.Jaliwind:BAAALgADCgkJCQAAAA==.Jayan:BAAALgAECgEJAQAAAA==.',
Ji='Jimbowaboki:BAAALgADCgEJAQAAAA==.',
Jo='Johan:BAABLgAECn8eAAIcAAkJMRrpGgBHAgAcAAkJMRrpGgBHAgAAAA==.Jokers:BAAALgAECgYJCwAAAA==.Jokersfists:BAAALgAECgYJBgAAAA==.Joranbragi:BAAALgAECgQJCwAAAA==.Jordanjr:BAAALgAECgYJCQAAAA==.Jormun:BAAALgADCgEJAQAAAA==.Joshy:BAABLgAECn8YAAIiAAYJsRCBDgBJAQAiAAYJsRCBDgBJAQAAAA==.Jotoonice:BAAALgAECgYJEAAAAA==.',
Jt='Jtoothaordan:BAACLgAFFH8JAAQjAAQJqQ/ZDQAvAQAjAAQJHQ3ZDQAvAQAEAAEJfg7UYgBLAAASAAEJrQF1LQA8AAAuAAQKfyEABBIACAnHGq0gACACABIACAnwFa0gACACACMAAgkmHoY1AKQAAAQAAQlVJQW2AGIAAAAA.',
Ju='Juglfhednar:BAAALgADCgEJAQAAAA==.',
['Jú']='Júgg:BAAALgAECgIJBAAAAA==.',
Ka='Kaachow:BAABLgAECn8pAAICAAkJNx/PBgATAwACAAkJNx/PBgATAwAAAA==.Kaana:BAABLgAECn8sAAIEAAgJbRNZNwCsAQAEAAgJbRNZNwCsAQAAAA==.Kairis:BAAALgAECgYJCQAAAA==.Kallista:BAAALgADCgEJAQAAAA==.Kanoalandiwa:BAAALgAECgEJAQAAAA==.Karthagon:BAAALgAECgUJDgAAAA==.Karungash:BAACLgAFFH8LAAMcAAQJqgo7PQARAQAcAAQJqgo7PQARAQAbAAEJVQE+GwA+AAAuAAQKfx0AAxwACAm1Id4QAPMCABwACAm1Id4QAPMCABsAAgkTEk1SAHcAAAAA.Karva:BAABLgAECn8kAAIMAAkJzBqzAwBJAgAMAAkJzBqzAwBJAgAAAA==.Karvy:BAAALgAECgcJBwABLgAECgkJJAAMAMwaAA==.Kash:BAAALgADCgUJBQABLgAFFAMJCQADAMcgAA==.Kayzer:BAAALgADCgYJGAAAAA==.',
Ke='Kelonaar:BAACLgAFFH8KAAIRAAQJ9xvwDgBJAQARAAQJ9xvwDgBJAQAuAAQKfyUAAxEACQlhHlgNAEYCABEACQlhHlgNAEYCABUAAgn1Gm0iAFAAAAAA.Kelya:BAAALgAECgUJBQABLgAFFAQJCgARAPcbAA==.Kerrie:BAAALgADCgEJAQAAAA==.',
Kh='Khthonious:BAABLgAECn8VAAIWAAcJBx5fJwDmAQAWAAcJBx5fJwDmAQAAAA==.',
Ki='Kickingdonut:BAACLgAFFH8FAAIUAAMJNx8EDwAKAQAUAAMJNx8EDwAKAQAuAAQKfywAAxQACAk7IzgIAH0CABQACAk7IzgIAH0CAAkABgn1GUI3AG4BAAAA.Killerhottie:BAAALgADCgEJAQAAAA==.Killermoomoo:BAAALgAECgQJBAAAAA==.Kittykarma:BAAALgAECgEJAQAAAA==.',
Kl='Kloverr:BAAALgADCgIJAgAAAA==.Klub:BAAALgADCgYJBgAAAA==.',
Ko='Kollita:BAAALgAECgEJAQAAAA==.Komatsu:BAAALgADCgEJAQAAAA==.',
Kr='Kromir:BAAALgADCgkJHQAAAA==.Kronixrage:BAAALgAECgIJBAAAAA==.Kronn:BAAALgAECgYJBwAAAA==.Krum:BAACLgAFFH8NAAIKAAQJ4RbeHgBJAQAKAAQJ4RbeHgBJAQAuAAQKfx4AAgoACAmsHSQvAPsBAAoACAmsHSQvAPsBAAAA.',
Ku='Kungfoumoo:BAAALgAECgEJAQAAAA==.',
La='Ladgarkk:BAAALgADCggJFQAAAA==.Lanval:BAABLgAECn82AAIKAAkJnRZYLwD6AQAKAAkJnRZYLwD6AQAAAA==.Laurian:BAAALgADCgcJDgAAAA==.',
Le='Leaky:BAAALgAECgIJBAAAAA==.Leetah:BAABLgAECn86AAMkAAkJmRteBAB8AgAkAAkJmRteBAB8AgADAAMJfQ67HwCiAAAAAA==.Leftblank:BAAALgAECgQJBAAAAA==.Legitimas:BAAALgAECgEJAQAAAA==.Lemix:BAAALgAECgMJDAAAAA==.',
Li='Liasong:BAAALgADCgMJAwAAAA==.Lilyoptra:BAAALgAECgMJBQABLgAECgMJBQANAAAAAA==.Livingdemon:BAAALgAECgUJDwAAAA==.',
Lm='Lminus:BAAALgAECgYJEgAAAA==.',
Lo='Lockolus:BAAALgAECgMJAwAAAA==.Lockpockets:BAAALgADCgEJAQAAAA==.Lorianth:BAAALgADCgcJDgAAAA==.Lovegood:BAAALgADCgEJAQAAAA==.Loveisbeauty:BAAALgAECgUJBwAAAA==.Lowki:BAAALgAECgEJAQAAAA==.',
Ly='Lychi:BAAALgAECgQJBAAAAA==.Lylora:BAACLgAFFH8HAAICAAMJgRgbIwD2AAACAAMJgRgbIwD2AAAuAAQKfzUAAgIACQl4I4ICAH4DAAIACQl4I4ICAH4DAAAA.Lysera:BAAALgADCgMJAwAAAA==.',
['Lê']='Lêmonaide:BAABLgAECn8dAAMPAAgJ9A79IABzAQAPAAgJ9A79IABzAQAXAAIJoAPXawAkAAAAAA==.',
Ma='Madesh:BAABLgAECn80AAMMAAkJ6RksBgDfAQAWAAgJ6xsbJQDyAQAMAAkJRxMsBgDfAQAAAA==.Madman:BAABLgAECn8aAAITAAcJAhBhKgBNAQATAAcJAhBhKgBNAQAAAA==.Maelle:BAABLgAECn8tAAIKAAgJoiHqFgB7AgAKAAgJoiHqFgB7AgAAAA==.Magekaestey:BAAALgAECggJEwAAAA==.Majandra:BAAALgAECgQJBwAAAA==.Malyndra:BAABLgAECn8fAAIQAAgJABY+EwCWAQAQAAgJABY+EwCWAQAAAA==.Marle:BAAALgAECgEJBAAAAA==.Marvolt:BAAALgADCgkJGwAAAA==.',
Mc='Mcrae:BAAALgAECgYJBwAAAA==.',
Md='Md:BAAALgADCgMJAwAAAA==.',
Me='Medrare:BAAALgAECgEJAQAAAA==.Melon:BAAALgADCgEJAQABLgAECgcJCQANAAAAAA==.Merlot:BAAALgADCgEJAgABLgAECgQJBgANAAAAAA==.Mesmash:BAABLgAECn8gAAIeAAgJlhsQCQAdAgAeAAgJlhsQCQAdAgAAAA==.Metahunt:BAAALgAECgEJAQABLgAECggJGQAUAGIXAA==.Metamasters:BAAALgAECgQJBAABLgAECggJGQAUAGIXAA==.',
Mi='Mialtaa:BAABLgAECn8eAAIJAAgJThVtGACmAQAJAAgJThVtGACmAQAAAA==.Miink:BAAALgADCgYJBgAAAA==.Milkurs:BAAALgAECgQJBQAAAA==.Miniborg:BAABLgAECn8ZAAIEAAgJDxYfKwDgAQAEAAgJDxYfKwDgAQABLgAFFAQJCAAKAPEXAA==.Minidude:BAAALgAECgYJEAAAAA==.Miyuki:BAAALgAECgIJBAAAAA==.',
Mj='Mjolnir:BAAALgAECgcJBgAAAA==.',
Mo='Moejojojo:BAAALgAECgcJEAAAAA==.Monkter:BAABLgAECn8ZAAQUAAgJYhefEgDbAQAUAAgJYhefEgDbAQATAAEJ/gbfbgAmAAAJAAEJfgiwgAAiAAAAAA==.Moofasaha:BAAALgAECgcJDgAAAA==.Mooheals:BAAALgADCgEJAQAAAA==.Moonk:BAAALgAECgcJBQAAAA==.Morduos:BAAALgAECgcJBgABLgAECggJFQAWAAceAA==.Morog:BAACLgAFFH8JAAMjAAQJEhUSDABBAQAjAAQJEhUSDABBAQAEAAEJ0w0pYwBKAAAuAAQKfykABBIACQmpGyMsAM0BABIABgmOHSMsAM0BAAQABgkaGq0/ALABACMABgnrE0UeAFoBAAAA.Morragan:BAAALgADCgcJDgAAAA==.Moráthi:BAAALgADCgcJBwAAAA==.',
Mu='Mulvan:BAAALgAECgcJDwAAAA==.',
My='Myinja:BAAALgAECgQJBAABLgAECggJGQAUAGIXAA==.Myrddinwyllt:BAAALgAECgYJDAAAAA==.',
Na='Nabû:BAAALgADCggJDwAAAA==.Naema:BAAALgAECgcJDQAAAA==.Nalid:BAACLgAFFH8JAAIDAAMJxyAHBQApAQADAAMJxyAHBQApAQAuAAQKfzwAAwMACAmzJZsBAPACAAMACAmzJZsBAPACAAcAAQmuArx3AB4AAAAA.Nanarus:BAABLgAECn8sAAIPAAkJfhrnCACRAgAPAAkJfhrnCACRAgAAAA==.Nanosec:BAAALgADCgEJAQAAAA==.Nansea:BAAALgAECgEJAQAAAA==.Nashalie:BAABLgAECn8fAAIcAAkJhBovHAA+AgAcAAkJhBovHAA+AgAAAA==.Natedawg:BAAALgAECgUJCQAAAA==.',
Ne='Nefele:BAABLgAECn8aAAIBAAgJ7xXQIADzAQABAAgJ7xXQIADzAQAAAA==.Nepheli:BAABLgAECn8vAAIWAAkJ/R6DDACmAgAWAAkJ/R6DDACmAgAAAA==.Newrhu:BAAALgADCgIJAgAAAA==.Nexbasia:BAABLgAECn8tAAMDAAkJ4Q44CgC9AQADAAkJ4Q44CgC9AQACAAIJ9QJCyQAcAAAAAA==.',
Ni='Nickyboy:BAABLgAECn8jAAQbAAcJyiE9AwAdAgAbAAcJyiE9AwAdAgAcAAIJvg58xgBvAAAiAAEJrBchJQA3AAAAAA==.Nightevel:BAAALgAECgUJBQAAAA==.Nihimetal:BAAALgAECgEJAQAAAA==.Nikash:BAABLgAECn8eAAMHAAcJEwtyLgAMAQAHAAcJEwtyLgAMAQACAAYJ+QhXZQDAAAAAAA==.Nisato:BAAALgAECgQJBAAAAA==.',
No='Noctum:BAAALgAECgYJEAAAAA==.Nommei:BAAALgAECgYJEgAAAA==.',
Ny='Nyriah:BAAALgAECgUJCgAAAA==.',
Ob='Obm:BAAALgAECgQJBAAAAA==.',
Oc='Octt:BAABLgAECn8bAAIcAAkJOxtTIQAgAgAcAAkJOxtTIQAgAgAAAA==.',
Of='Offal:BAABLgAECn8bAAQfAAYJAQ8JGAA5AQAfAAYJCAsJGAA5AQAeAAQJeBJ4KQCgAAAdAAEJJQWsgwAmAAAAAA==.',
Ol='Olanna:BAAALgAECgYJDAAAAA==.Oldcannabis:BAAALgAECgIJBAAAAA==.',
Om='Ominis:BAAALgADCgkJKgAAAA==.',
Or='Orcal:BAACLgAFFH8XAAIgAAUJuRLUGAAwAQAgAAUJuRLUGAAwAQAuAAQKfx0AAiAACAn7GnQQAHECACAACAn7GnQQAHECAAAA.Ormie:BAAALgAECgQJBAAAAA==.Ornimus:BAAALgAECgUJDwAAAA==.',
Oz='Ozo:BAABLgAECn8WAAIEAAYJmhLlWQA6AQAEAAYJmhLlWQA6AQAAAA==.',
Pa='Paiva:BAAALgAECgQJBAAAAA==.Palandor:BAAALgADCgMJAwAAAA==.Pallyscorned:BAABLgAECn8tAAILAAkJ3iCfAgC0AgALAAkJ3iCfAgC0AgAAAA==.Pampas:BAABLgAECn8VAAMBAAcJRQSwWwDgAAABAAcJRQSwWwDgAAARAAEJRAFPigAaAAAAAA==.Paxdei:BAAALgAECgUJCQAAAA==.',
Pe='Ped:BAAALgAECgQJBgAAAA==.',
Ph='Phenixy:BAAALgAECgQJBAAAAA==.Phoebell:BAAALgAECgMJBQAAAA==.',
Pi='Pinkducky:BAABLgAECn8ZAAIFAAQJTQcb1gCAAAAFAAQJTQcb1gCAAAAAAA==.',
Pl='Plen:BAABLgAECn8gAAIFAAgJWB1aNQBhAgAFAAgJWB1aNQBhAgAAAA==.',
Po='Ponder:BAAALgAECgYJCgAAAA==.Poppyseed:BAAALgAECgEJAQAAAA==.Poquads:BAAALgADCgkJGAAAAA==.',
Pr='Primaris:BAAALgAECgEJAQAAAA==.Príestatute:BAAALgADCggJCAABLgAECggJIwAEAI4bAA==.',
Pu='Punka:BAAALgAECgEJAQAAAA==.Purplesea:BAAALgADCgcJDQABLgAECgkJLAAOAHEPAA==.',
Pv='Pve:BAAALgADCgYJBgAAAA==.',
Qu='Quasar:BAABLgAECn8lAAIlAAkJmBheKwAqAgAlAAkJmBheKwAqAgAAAA==.',
Ra='Radra:BAAALgAECgIJAgAAAA==.Raeku:BAABLgAECn8kAAIjAAkJgSAAAwAFAwAjAAkJgSAAAwAFAwAAAA==.Rainee:BAAALgADCgEJAQAAAA==.Raja:BAAALgAECgUJDQAAAA==.Rathalo:BAAALgAECgEJAQAAAA==.Rav:BAAALgADCgUJBQAAAA==.Ravick:BAAALgADCgEJAQAAAA==.Razzlor:BAAALgADCgUJBQAAAA==.',
Re='Reducto:BAABLgAECn8bAAMMAAYJKRQdEQDnAAAMAAUJ1RQdEQDnAAAWAAYJLREYfQDRAAAAAA==.Reenailinefh:BAAALgADCgcJDgAAAA==.Relitha:BAAALgADCgUJCQAAAA==.Remeii:BAABLgAECn8gAAMBAAcJaAjrZAC/AAABAAYJcQTrZAC/AAARAAYJUQOKUACdAAAAAA==.Retribution:BAABLgAECn8mAAIKAAgJmA+mVQCAAQAKAAgJmA+mVQCAAQAAAA==.Reylexgt:BAAALgAECgEJAQAAAA==.',
Rh='Rhaenera:BAAALgAECgIJAwABLgAECggJMQAUAPchAA==.',
Ro='Robomurph:BAAALgADCggJDwAAAA==.Ronfax:BAACLgAFFH8aAAMBAAYJPCISAQB8AgABAAYJPCISAQB8AgARAAEJ6QOHIABAAAAuAAQKfxcAAwEACQknIg4GABEDAAEACQknIg4GABEDABEAAQl1F66GADMAAAAA.Rooss:BAAALgAECgYJDQAAAA==.Roqane:BAAALgAECgQJBAAAAA==.Roserade:BAAALgAECgcJDwAAAA==.Rothkin:BAAALgADCgMJAwAAAA==.Rotreiter:BAAALgADCgEJAQAAAA==.Rowdyredneck:BAAALgADCgMJAwABLgAECggJGQAUAGIXAA==.',
Ru='Rukea:BAAALgADCgkJCQAAAA==.Rul:BAAALgAECgQJBAABLgAFFAMJBgAYAIEcAA==.',
Ry='Ryllae:BAAALgAECgMJAwABLgAECgkJFgAQANgbAA==.Ryuusythe:BAAALgADCgcJBwAAAA==.Ryân:BAAALgADCgEJAQAAAA==.',
Sa='Saara:BAAALgADCgEJAQAAAA==.Saint:BAAALgAECgUJBQAAAA==.Samson:BAAALgAECgUJDAABLgAECgQJBAANAAAAAA==.Sanivan:BAABLgAECn8VAAIQAAcJ+hdxGgDvAQAQAAcJ+hdxGgDvAQAAAA==.Sanoan:BAAALgADCgEJAQAAAA==.Sappy:BAABLgAECn8XAAQaAAcJdR9BCQCuAQAaAAYJAx5BCQCuAQAhAAQJrxwzOwA/AQAmAAQJ8BLcCQDFAAABLgAFFAMJBgAYAIEcAA==.Sarinae:BAABLgAECn8VAAMgAAcJfAMZRwC5AAAgAAcJfAMZRwC5AAAZAAEJwAG/IAAXAAAAAA==.Sarmuc:BAABLgAECn8UAAMVAAgJjA66EAAwAQAVAAgJjA66EAAwAQARAAEJXwtPfQAqAAAAAA==.Saryda:BAAALgAECgQJBgAAAA==.Sauda:BAAALgAECgEJAQAAAA==.Saurian:BAAALgADCgEJAQAAAA==.',
Sc='Schadoww:BAAALgAECggJCgABLgAECggJIAAFAFgdAA==.Scubagal:BAAALgAECgMJBQAAAA==.Scy:BAAALgADCgcJCgAAAA==.Scythraza:BAAALgAECgcJDQAAAA==.',
Se='Seablue:BAAALgAECgMJBQABLgAECgkJLAAOAHEPAA==.Sedaleice:BAAALgAECgEJAQAAAA==.Seedsprayer:BAAALgAECgYJCQAAAA==.Selara:BAAALgAECgMJAwAAAA==.Sellenah:BAAALgAECgYJEwAAAA==.Sensu:BAAALgAECgUJCwAAAA==.Sensual:BAAALgAECgMJAwAAAA==.Sernian:BAAALgAECgQJCAABLgAFFAQJDAAKAF4fAA==.Seä:BAABLgAECn8sAAIOAAkJcQ9xHQDLAQAOAAkJcQ9xHQDLAQAAAA==.',
Sh='Shadoweave:BAABLgAECn8XAAIXAAkJ2AZIJgBDAQAXAAkJ2AZIJgBDAQAAAA==.Shamtea:BAABLgAECn8ZAAIRAAcJZgOQSAC5AAARAAcJZgOQSAC5AAAAAA==.Shapzan:BAAALgAECgQJCwAAAA==.Sharks:BAAALgAECgQJDwAAAA==.Shivant:BAABLgAECn8XAAIBAAcJuR0yHwD9AQABAAcJuR0yHwD9AQAAAA==.Shroomhunter:BAAALgAECgEJAQAAAA==.Shîvå:BAABLgAECn8aAAIMAAgJ4B38BAAMAgAMAAgJ4B38BAAMAgAAAA==.',
Si='Sindice:BAAALgAECgYJBwABLgAFFAYJGgABADwiAA==.',
Sk='Skaa:BAAALgAECgEJAQAAAA==.',
Sl='Slammy:BAAALgAECgQJBAAAAA==.Slimpooshady:BAAALgAECgcJEAAAAA==.',
So='Solaspirus:BAABLgAECn8gAAMWAAgJIxfwLQDGAQAWAAgJIxfwLQDGAQAMAAEJawzfJQAwAAAAAA==.Solinius:BAAALgAECgEJAQAAAA==.Sope:BAAALgAECgYJBwAAAA==.Sorhtx:BAAALgAECgUJBwAAAA==.',
Sp='Spectors:BAAALgAECgcJDQAAAA==.Spekturx:BAAALgAECgEJAQAAAA==.Spideygirl:BAABLgAECn8WAAIOAAgJPxzQCgCXAgAOAAgJPxzQCgCXAgAAAA==.Sprayinseed:BAAALgADCgMJAwAAAA==.',
Sq='Squarepants:BAAALgAECgQJCQABLgAECgQJDwANAAAAAA==.',
St='Stabon:BAABLgAECn8gAAIhAAgJiQnzGgBkAQAhAAgJiQnzGgBkAQAAAA==.Stardre:BAAALgADCgQJBQAAAA==.Stevesmith:BAAALgAECgEJAgAAAA==.Stonedrage:BAAALgADCgEJAQAAAA==.Stormspirits:BAAALgADCgUJBQAAAA==.Sturdyy:BAAALgADCgMJAwAAAA==.Stãrkïllér:BAAALgADCgMJAwAAAA==.',
Su='Sugarmarks:BAAALgAECgQJCAAAAA==.',
Sw='Sweetstorm:BAABLgAECn8hAAIQAAgJ4gV8IQAFAQAQAAgJ4gV8IQAFAQAAAA==.',
Sy='Synvara:BAAALgADCgUJBQAAAA==.',
['Sê']='Sêphiroth:BAABLgAECn8mAAIOAAgJexQQGgDoAQAOAAgJexQQGgDoAQAAAA==.',
Ta='Tahlia:BAAALgAECgEJAQAAAA==.Tania:BAAALgAECgcJDAAAAA==.Tarixx:BAABLgAFFH8GAAMKAAMJ/w5hJACjAAAKAAIJQg5hJACjAAALAAEJeRA+DwA2AAAAAA==.Tazanoth:BAACLgAFFH8IAAQEAAMJBBI+PQDQAAAEAAMJ0Q8+PQDQAAAjAAIJKQ7JGwCeAAASAAEJTArEJgBPAAAuAAQKfxoAAyMACAmyGUgQAOoBACMACAmCGEgQAOoBABIABglBGtYwALABAAAA.',
Te='Teasa:BAABLgAECn8kAAIEAAgJ3BHaQQCFAQAEAAgJ3BHaQQCFAQAAAA==.Tekeelà:BAACLgAFFH8JAAQEAAUJwwdDAgB7AQAEAAUJwwdDAgB7AQAjAAEJhAF0JQA1AAASAAEJVgAiLgA1AAAuAAQKfy8ABAQACQn/IKMVAIoCAAQACAkfIKMVAIoCACMACQm6GPIIAFMCABIABwm3EeY5AHoBAAAA.Tekkamaki:BAAALgADCgcJCAAAAA==.',
Th='Thalion:BAAALgAECgQJBwAAAA==.Theenna:BAAALgADCgUJBQAAAA==.Thianna:BAABLgAECn8aAAMOAAgJwhUgIwChAQAOAAgJwhUgIwChAQAKAAYJ8Qq5nQDvAAAAAA==.Thiculuskage:BAAALgAECggJEAAAAA==.Thinkso:BAAALgADCgcJFQAAAA==.Thobu:BAAALgAECgUJBwAAAA==.Thornscale:BAABLgAECn8xAAQgAAkJ0xpADQBDAgAgAAkJ0xpADQBDAgAZAAUJvBYpCQBNAQAnAAYJogvrKAAsAQAAAA==.',
Ti='Tigolcrittys:BAAALgAECgUJBgABLgAECggJIwAEAI4bAA==.Timeforloads:BAABLgAECn8UAAMCAAYJyBvfOQBmAQACAAYJyBvfOQBmAQAHAAIJjxB5egA9AAAAAA==.',
To='Tolk:BAAALgAECgYJDgAAAA==.Tomzombe:BAAALgAECgIJBAAAAA==.Totem:BAAALgAECggJEQAAAA==.Totenz:BAAALgADCgYJBgAAAA==.',
Tr='Troloq:BAABLgAECn8sAAMcAAkJWB1cIwAWAgAcAAgJHhtcIwAWAgAbAAUJ8BkSDQAgAQAAAA==.Trondoom:BAAALgADCgYJBgAAAA==.',
Tu='Tugboattimmy:BAAALgAECgEJAQAAAA==.Tulisha:BAAALgADCgcJEQAAAA==.',
Ul='Uller:BAABLgAECn8YAAIlAAgJkxjjWwCKAQAlAAgJkxjjWwCKAQAAAA==.',
Um='Umbrafang:BAAALgAECgEJBAAAAA==.',
Un='Unholyspirit:BAAALgAECgQJDwAAAA==.',
Va='Vahlorraa:BAAALgAECgQJCwAAAA==.Vaimei:BAABLgAECn8mAAMbAAgJyyI/AQCcAgAbAAgJyyI/AQCcAgAcAAQJDR3VngAbAQAAAA==.Valashune:BAAALgADCgEJAQAAAA==.Vapor:BAABLgAECn8bAAIaAAYJxBSoCgBGAQAaAAYJxBSoCgBGAQAAAA==.Varanius:BAAALgAECgEJAgAAAA==.',
Ve='Veebs:BAAALgAECgYJDQAAAA==.Velóran:BAAALgADCgcJBwAAAA==.Vendola:BAABLgAECn8UAAIlAAgJNwV/nQAFAQAlAAgJNwV/nQAFAQAAAA==.Vento:BAABLgAECn8VAAIFAAgJjxUDQAC9AQAFAAgJjxUDQAC9AQAAAA==.Verité:BAAALgAECgYJCwAAAA==.Veterpeinss:BAAALgADCggJDgAAAA==.',
Vi='Viento:BAAALgADCgcJBwAAAA==.Villiveil:BAAALgADCgcJBwABLgAECggJLgAKAGIgAA==.Vintersorg:BAAALgAECgUJCQAAAA==.Virauca:BAABLgAECn8oAAIWAAkJ7BBIOACZAQAWAAkJ7BBIOACZAQAAAA==.Viuhl:BAAALgADCgQJAwAAAA==.',
Vo='Vodgrax:BAAALgAECgIJAgAAAA==.Voidstar:BAAALgAECgQJCwAAAA==.',
Vv='Vvicked:BAABLgAECn8YAAIFAAcJRB7WNwDaAQAFAAcJRB7WNwDaAQAAAA==.',
Vy='Vynesta:BAABLgAECn8WAAIQAAkJ2BsmBwBwAgAQAAkJ2BsmBwBwAgAAAA==.',
Wa='Wala:BAAALgAECgcJDAAAAA==.Wanagi:BAAALgADCgMJAwAAAA==.Wankz:BAAALgAECgcJDwAAAA==.Wankzerkin:BAAALgADCgEJAQAAAA==.Warriorguyes:BAABLgAECn8dAAIdAAgJSiKZCACUAgAdAAgJSiKZCACUAgAAAA==.',
We='Weyna:BAABLgAECn8oAAMTAAgJwQwyLABAAQATAAgJwQwyLABAAQAJAAUJtApoRwClAAABLgAFFAQJEQAnAGMTAA==.',
Wh='Whisperingei:BAAALgAECgUJCAAAAA==.',
Wi='Widowx:BAABLgAECn8lAAIRAAgJkRglGQDFAQARAAgJkRglGQDFAQAAAA==.Winfurdal:BAAALgADCggJCAAAAA==.',
Wo='Womphunt:BAAALgAECgQJBwABLgAECggJKQAPAM4fAA==.',
Wr='Wrandohunt:BAAALgAECgEJAwAAAA==.Wrandowdemon:BAAALgADCgcJBwAAAA==.Wryn:BAAALgAECgYJDgABLgAECggJIAAFAFgdAA==.',
Wu='Wulyn:BAAALgAECgUJCwAAAA==.',
Wy='Wylla:BAAALgAECgQJBgAAAA==.',
Xa='Xalethra:BAABLgAECn8mAAIWAAgJXyM4EACBAgAWAAgJXyM4EACBAgAAAA==.Xaltheris:BAAALgAECgUJBgAAAA==.',
Xe='Xenophobias:BAAALgAECgQJDQAAAA==.',
Xh='Xhosen:BAAALgAECgQJCwAAAA==.',
Xr='Xratedmurdaa:BAAALgAECgEJAQAAAA==.',
Xs='Xsuns:BAABLgAECn8tAAICAAgJRRgoJQDdAQACAAgJRRgoJQDdAQAAAA==.',
Yv='Yve:BAAALgAECgUJDQAAAA==.',
Za='Zalajin:BAAALgAECgQJBAAAAA==.Zalila:BAAALgADCgYJBgAAAA==.Zarayndia:BAAALgAECgQJCAAAAA==.',
Ze='Zeddicus:BAABLgAECn8dAAMiAAgJBQUkEADnAAAiAAcJAQUkEADnAAAcAAUJ0APQuQCKAAAAAA==.Zendragan:BAABLgAECn8cAAITAAgJUBgNFgD4AQATAAgJUBgNFgD4AQAAAA==.Zerhas:BAAALgAECgEJAwAAAA==.',
Zo='Zoidz:BAAALgAECgMJBAAAAA==.Zombiemagic:BAAALgADCgMJAwAAAA==.Zomgimlothar:BAAALgADCgIJAwAAAA==.Zoomy:BAAALgAECgQJCwAAAA==.',
Zy='Zyntarum:BAAALgADCgEJAQAAAA==.',
Zz='Zzilladinzz:BAACLgAFFH8SAAIKAAQJjR/SEwBtAQAKAAQJjR/SEwBtAQAuAAQKfyEAAgoACAl8IwsSAAIDAAoACAl8IwsSAAIDAAAA.',
['Ëu']='Ëulogy:BAAALgAECgQJCgABLgAECggJGgAMAOAdAA==.',
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
