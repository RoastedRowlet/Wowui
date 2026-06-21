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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Unknown-Unknown','Shaman-Restoration','Druid-Feral','DemonHunter-Havoc','Priest-Shadow','Priest-Discipline','Shaman-Elemental','Paladin-Retribution','Hunter-Survival','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Mistweaver','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Priest-Holy','Evoker-Augmentation','Druid-Guardian','Monk-Brewmaster','Warrior-Fury','Monk-Windwalker','Mage-Arcane','Warrior-Arms','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Warlock-Destruction',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Acaval:BAACLgAFFH8KAAMBAAMJLB0bFwDRAAACAAMJLB0ZkwDmAAABAAMJwRAbFwDRAAAuAAQKfxUAAwIACQm+IdYKABgDAAIACQm+IdYKABgDAAEAAQlrIicvAGMAAAAA.Accursed:BAACLgAFFH8NAAIDAAQJPyUCAgCjAQADAAQJPyUCAgCjAQAuAAQKfyIAAgMACAl6JqsAAFYDAAMACAl6JqsAAFYDAAAA.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.Aduayro:BAAALgADCgQJBAAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Ai='Airpod:BAAALgAECgEJAQABLgAECggJEAAEAAAAAA==.',
Al='Aleighta:BAABLgAECn8cAAIFAAkJBAvBVgBbAQAFAAkJBAvBVgBbAQAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.Alyx:BAAALgAECgMJBQAAAA==.',
Am='Amadia:BAAALgAECgMJBgAAAA==.',
An='Anabel:BAABLgAECn8pAAIGAAkJHhG+AAAMAQAGAAkJHhG+AAAMAQAAAA==.Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ao='Aoi:BAAALgADCgcJBwABLgAECgkJIQAHAMAXAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgIJAgAAAA==.',
As='Asatrath:BAAALgAECgYJDwAAAA==.Ashkillz:BAABLgAECn8jAAMIAAgJ/R/lFgASAgAIAAcJdh/lFgASAgAJAAEJcxuRBABSAAAAAA==.Ashtuck:BAAALgAECgYJCQAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAABLgAECn8jAAIKAAkJWRGpIwDJAQAKAAkJWRGpIwDJAQAAAA==.',
Av='Avenger:BAAALgAECgEJAQABLgAECgYJBQAEAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJCAAAAA==.',
Ba='Badoussi:BAAALgAECgYJEwABLgAFFAUJBgAGAGoTAA==.Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgYJBwAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8TAAILAAYJ9CDAHQCRAQALAAYJ9CDAHQCRAQAuAAQKfxoAAgsACAn8Ij0RAAYDAAsACAn8Ij0RAAYDAAAA.',
Be='Beansy:BAAALgAECgYJDAAAAA==.Beefomancer:BAAALgAECgQJBAABLgAECgkJNwAMADYcAA==.Belan:BAABLgAECn8pAAINAAkJpRUROgAxAgANAAkJpRUROgAxAgAAAA==.Belladin:BAABLgAECn8gAAILAAkJ0x/THgCyAgALAAkJ0x/THgCyAgAAAA==.',
Bi='Bismuth:BAAALgAECgYJBgAAAA==.',
Bl='Blakeshelton:BAAALgAECgIJBgABLgAECggJEAAEAAAAAA==.Blameurself:BAABLgAECn8VAAIOAAkJ+x72IwBAAgAOAAkJ+x72IwBAAgAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECgkJFQAOAPseAA==.Blaster:BAAALgAECgEJBgAAAA==.Blite:BAAALgADCgQJDQAAAA==.Bluethain:BAAALgAECggJDgAAAA==.',
Bo='Bombakaap:BAAALgAECgYJCwAAAA==.Bomburst:BAABLgAECn8gAAIPAAgJvxDUEgCKAQAPAAgJvxDUEgCKAQAAAA==.Bonelespizza:BAACLgAFFH8IAAICAAIJOQqFSACTAAACAAIJOQqFSACTAAAuAAQKfzgAAwIACQlhH9sjAK8CAAIACQmHHtsjAK8CAAEABgmKHw8NAKYBAAAA.Boogiebabe:BAAALgAECgcJDAAAAA==.Boomhauerr:BAAALgAECgYJBgAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgAECgQJBAAAAA==.Briaris:BAACLgAFFH8OAAIMAAQJ6hSbEgA0AQAMAAQJ6hSbEgA0AQAuAAQKfyMABAwACAmCHTgIAGsCAAwACAmCHTgIAGsCABAAAQkuC7E+ACwAABEAAQkIAkNNASQAAAAA.Bruel:BAAALgADCgUJBQAAAA==.Brugaras:BAAALgADCgcJCwAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
['Bê']='Bêz:BAAALgAECgEJAQAAAA==.',
['Bë']='Bëz:BAABLgAECn84AAIDAAkJ5SJSAQAgAwADAAkJ5SJSAQAgAwAAAA==.',
Ca='Cachinnare:BAAALgAECgUJCgABLgAFFAIJAgAEAAAAAA==.Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Capziesh:BAAALgAECgQJBQAAAA==.Casteel:BAAALgAECggJEAAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgYJBwABLgAFFAcJFwAJAOcSAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAABLgAECn8XAAILAAcJUhEnkABSAQALAAcJUhEnkABSAQAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAABLgAECn8dAAISAAgJbCIDCQALAwASAAgJbCIDCQALAwAAAA==.Cosmicjay:BAECLgAFFH8FAAIKAAMJMBPANQC3AAAKAAMJMBPANQC3AAAuAAQKfxgAAgoACAmsIH0TAFECAAoACAmsIH0TAFECAAAA.Cosmicnova:BAEALgAFFAEJAQABLgAFFAMJBQAKADATAA==.Costa:BAAALgAECgQJBQAAAA==.',
Cr='Crentacles:BAABLgAECn8dAAIKAAkJrxZoGwAGAgAKAAkJrxZoGwAGAgAAAA==.Critshade:BAAALgAECgYJDQAAAA==.Crow:BAAALgAFFAUJJAAAAQ==.',
Da='Dadeulus:BAAALgAECgcJDAAAAA==.Daedis:BAAALgAECgEJAQAAAA==.Daegán:BAAALgAECgEJAQAAAA==.Daffodil:BAABLgAECn8wAAMTAAkJZhHKBgDeAQATAAkJZhHKBgDeAQAUAAMJ2wJLMwBaAAAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgAEAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8WAAIVAAcJUgpCGACdAQAVAAcJUgpCGACdAQAuAAQKfyEAAxUACQl+HEkdAFMCABUACQl+HEkdAFMCABYAAQmSA4GiAB8AAAAA.Dantruis:BAAALgAECgEJAQABLgAFFAcJFgAVAFIKAA==.Darkshiver:BAAALgADCgEJAgABLgAECgEJBgAEAAAAAA==.Dawnslight:BAABLgAECn8WAAILAAcJ3gFsQQFqAAALAAcJ3gFsQQFqAAAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Dedebop:BAAALgAECgIJBQAAAA==.Deiside:BAAALgADCgkJCQAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAcJCwAXAG0aAA==.Denareyeth:BAAALgAECgUJCwAAAA==.Dephiance:BAAALgAECgcJCAABLgAECgkJKgAIALkUAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJEAAAAA==.',
Di='Diabla:BAABLgAECn8XAAIYAAYJeCTQFwBTAgAYAAYJeCTQFwBTAgAAAA==.Dinsfirë:BAAALgAECgEJAQAAAA==.Diothorn:BAABLgAECn8kAAMLAAgJ+xjqWADBAQALAAcJtxnqWADBAQAZAAMJ8hSPLQC0AAAAAA==.Disappointed:BAAALgADCggJDAAAAA==.Divanas:BAABLgAECn8gAAIaAAgJ/gcYnQAEAQAaAAgJ/gcYnQAEAQAAAA==.Divi:BAABLgAECn8lAAIbAAkJrCHTAwBMAwAbAAkJrCHTAwBMAwAAAA==.',
Do='Doxa:BAAALgADCgMJCAAAAA==.',
Dr='Dragonboi:BAABLgAECn8aAAIcAAkJhxGGJQCzAQAcAAkJhxGGJQCzAQAAAA==.Dreàd:BAAALgAECgEJAQAAAA==.Drpepperz:BAABLgAFFH8GAAIWAAQJqBLQIwAIAQAWAAQJqBLQIwAIAQAAAA==.Drägonwärior:BAAALgAECgEJAQAAAA==.',
Du='Durgan:BAAALgADCgQJBwAAAA==.Durock:BAAALgADCgQJBAABLgAECgkJGwAdALoXAA==.',
Dy='Dyria:BAAALgAECgIJAgAAAA==.',
Ed='Edging:BAAALgADCgYJBgAAAA==.',
El='Elegance:BAAALgAECgIJAgABLgAECgkJKgAIALkUAA==.Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgAECgEJAQAAAA==.Ellayria:BAAALgAECgYJCgAAAA==.',
Em='Emberrose:BAAALgADCgkJGwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Enhancedpant:BAAALgAECgQJBgAAAA==.Ensetral:BAAALgAECgEJAQAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgcJCwAEAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJCQAAAA==.Evelithillyn:BAAALgAECgQJBQABLgAECgkJFQAOAPseAA==.Everydae:BAACLgAFFH8FAAIcAAMJEAssGwCUAAAcAAMJEAssGwCUAAAuAAQKfyYAAhwACQnUHzgMAJcCABwACQnUHzgMAJcCAAAA.',
Ex='Extrajuicy:BAAALgAFFAIJAwAAAA==.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECgkJGgAaAI8YAA==.',
Fa='Fakedruid:BAABLgAECn8UAAIdAAcJliO0CQBOAgAdAAcJliO0CQBOAgABLgAECgkJNwAMADYcAA==.Falarzer:BAAALgADCgIJAgAAAA==.Fatwarlock:BAAALgAECgEJAQAAAA==.',
Fe='Feledris:BAAALgAECgQJBAAAAA==.Feybeasts:BAAALgAECgYJBwAAAA==.Feárbomber:BAAALgAECgQJBAABLgAECgkJQgAeAJskAA==.',
Ff='Ffand:BAABLgAECn8WAAIRAAYJ5x/VOADLAQARAAYJ5x/VOADLAQAAAA==.',
Fh='Fharia:BAAALgAECgUJBgAAAA==.',
Fi='Filafal:BAAALgADCgEJAQABLgAECggJGAACAJsaAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flawless:BAAALgAECgEJAQAAAA==.Flayr:BAAALgADCgkJDQAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fortitude:BAAALgAECgcJCwAAAA==.',
Fu='Fusky:BAABLgAECn8mAAIFAAkJuBJJKAAdAgAFAAkJuBJJKAAdAgAAAA==.',
Fy='Fynn:BAACLgAFFH8NAAIPAAUJkQ2aCwAIAQAPAAUJkQ2aCwAIAQAuAAQKfyAAAw8ACAnFFwwLABwCAA8ACAnFFwwLABwCAAUAAQmjAYipACQAAAAA.',
['Fä']='Fätpàndà:BAAALgADCgYJBgAAAA==.',
Ga='Galadria:BAACLgAFFH8PAAIWAAUJWRFuJQD/AAAWAAUJWRFuJQD/AAAuAAQKfxQAAhYACQl0HAUgAMgBABYACQl0HAUgAMgBAAAA.Ganeda:BAAALgAECgcJDAABLgAECgkJGwAdALoXAA==.Garamond:BAAALgADCgEJAQAAAA==.Garchomp:BAAALgAECgcJBgAAAA==.Garrish:BAAALgADCgEJAQAAAA==.',
Ge='Geraldini:BAAALgAECgMJAwAAAA==.Gerwik:BAABLgAECn8sAAIRAAgJtRn0MwANAgARAAgJtRn0MwANAgAAAA==.',
Gi='Ging:BAABLgAECn8WAAIfAAcJJw9DPwBIAQAfAAcJJw9DPwBIAQAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDQAAAA==.Gogetta:BAAALgAECgEJAQAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goldenlock:BAAALgAECgYJDwAAAA==.Goliather:BAAALgADCgEJAQAAAA==.Govana:BAABLgAECn8fAAICAAkJGhgCAQDZAQACAAkJGhgCAQDZAQAAAA==.',
Gr='Greenleaves:BAABLgAECn8WAAIgAAgJ8hhPHADMAQAgAAgJ8hhPHADMAQAAAA==.Greenpepperz:BAAALgADCgYJBgAAAA==.Gregsh:BAABLgAECn89AAMNAAkJyRiuMwBKAgANAAkJyRiuMwBKAgAhAAEJ6APUIQAkAAAAAA==.Grimward:BAAALgAECgYJBgAAAA==.Grocrush:BAAALgAECgEJAQAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Guenther:BAAALgAECgEJAQABLgAECgkJIgAFACIZAA==.Gummifishz:BAAALgADCgcJBwAAAA==.Gummiwormz:BAABLgAECn8sAAIYAAkJrx+8BABLAwAYAAkJrx+8BABLAwAAAA==.',
Ha='Hailin:BAABLgAECn8sAAILAAkJ5xlXPgAMAgALAAkJ5xlXPgAMAgAAAA==.Halfheal:BAAALgAECggJDgAAAA==.Halrem:BAAALgAECgIJAgAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8eAAIZAAcJAxvrEAC1AQAZAAcJAxvrEAC1AQAAAA==.',
He='Heherawr:BAAALgADCgcJBwABLgAECgQJCwAEAAAAAA==.Hellman:BAAALgADCgUJCQAAAA==.Hertzabit:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
Hi='Hightroller:BAABLgAECn8vAAIRAAkJehpUIABmAgARAAkJehpUIABmAgAAAA==.Hima:BAABLgAECn8hAAIHAAkJwBd2DgA+AgAHAAkJwBd2DgA+AgAAAA==.',
Hn='Hnri:BAAALgAECgEJAgAAAA==.',
Ho='Holyjenkins:BAAALgADCgkJDgAAAA==.Holysathh:BAAALgAECgUJDgABLgAECgkJGwAdALoXAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Holystormm:BAAALgAECgQJBgAAAA==.Homulily:BAAALgADCggJGwAAAA==.Hornggry:BAAALgAECgQJAwABLgAECggJGgAeAJ4dAA==.Horngrry:BAAALgAECggJDwABLgAECggJGgAeAJ4dAA==.Horngryer:BAAALgAECgQJBQABLgAECggJGgAeAJ4dAA==.Horngryerr:BAABLgAECn8aAAIeAAgJnh28JgB5AQAeAAgJnh28JgB5AQAAAA==.Horngryish:BAAALgADCgEJAQABLgAECggJGgAeAJ4dAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJBQABLgAECgkJNgASABcaAA==.',
Hu='Hulkshe:BAAALgAECgkJCQAAAA==.Huntingpants:BAABLgAECn8eAAIQAAkJRREKCwC7AQAQAAkJRREKCwC7AQAAAA==.',
Ic='Icianri:BAAALgAFFAEJAQAAAA==.',
Il='Ilovebagels:BAAALgADCgkJDwAAAA==.',
Im='Imkillho:BAAALgAECgYJDAABLgAECggJGgAeAJ4dAA==.',
In='Inspiredbox:BAAALgAECgcJCQAAAA==.Inverness:BAAALgAECgEJAQAAAA==.',
It='Ithax:BAAALgADCgcJAQAAAA==.Itzuri:BAAALgADCgEJAQAAAA==.',
Ja='Jacobsangle:BAAALgAECgEJAQABLgAECgEJBgAEAAAAAA==.Jankismith:BAABLgAECn89AAISAAkJSRNPAgAYAQASAAkJSRNPAgAYAQAAAA==.Jayy:BAABLgAECn86AAIMAAkJ9xRLEQAhAgAMAAkJ9xRLEQAhAgAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAkJPAAiAK4kAA==.Jenny:BAABLgAECn8wAAILAAkJMRq5PwAIAgALAAkJMRq5PwAIAgAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgcJDwABLgAECgkJEwAEAAAAAA==.Jitoflight:BAAALgAECgYJBgAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgYJDAAAAA==.',
Ju='Jugger:BAAALgAECgEJAQAAAA==.Junieb:BAABLgAECn8eAAINAAkJHwszkQBVAQANAAkJHwszkQBVAQAAAA==.',
Ka='Kachiko:BAAALgADCggJJAAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAABLgAECn8VAAIaAAgJOwv+dABQAQAaAAgJOwv+dABQAQAAAA==.Kamerth:BAABLgAECn8zAAMJAAkJcwlsJwCWAQAJAAkJcwlsJwCWAQAIAAgJQAmsOQAtAQAAAA==.Kamugi:BAAALgAECgEJAQABLgAFFAQJDwAUAAANAA==.Kapnkrunch:BAAALgAECgUJBQAAAA==.Karluron:BAABLgAECn8rAAIIAAkJTBqtDwBgAgAIAAkJTBqtDwBgAgAAAA==.Karlutros:BAABLgAECn8pAAIIAAkJ/hGKIADCAQAIAAkJ/hGKIADCAQAAAA==.Katastrafia:BAAALgAECgMJAwAAAA==.Katimeut:BAAALgAECgQJBAABLgAFFAYJIAAXAAQmAA==.Katowo:BAAALgAFFAEJAQABLgAFFAYJIAAXAAQmAA==.Katuwuagain:BAACLgAFFH8gAAIXAAYJBCY3BwAYAgAXAAYJBCY3BwAYAgAuAAQKfxcAAhcACQk3JskAAGUDABcACQk3JskAAGUDAAAA.Kazure:BAABLgAECn8rAAIUAAkJcQ16FACDAQAUAAkJcQ16FACDAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn9JAAIfAAkJUhSsGQAhAgAfAAkJUhSsGQAhAgAAAA==.Keniilar:BAAALgAECgEJAQAAAA==.Kenilar:BAAALgAECgcJDAAAAA==.Keybricker:BAAALgAECgcJEAABLgAECgkJNwAMADYcAA==.',
Kh='Khaôtic:BAABLgAECn8XAAIOAAYJCRmEbQBIAQAOAAYJCRmEbQBIAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgAECgQJBwAAAA==.Kiraeshh:BAABLgAECn8ZAAINAAcJ/RKZkQBVAQANAAcJ/RKZkQBVAQAAAA==.Kittykat:BAAALgAECgQJBwAAAA==.',
Ko='Kolonna:BAAALgAECgMJAwAAAA==.Korngry:BAAALgAECgEJAQABLgAECggJGgAeAJ4dAA==.',
Kr='Krakkin:BAAALgAECgYJDQAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgAECgYJBgAAAA==.Krieash:BAAALgADCggJCAAAAA==.Krumpas:BAAALgAECgEJAQABLgAECggJGgAeAJ4dAA==.',
Ky='Kyllea:BAABLgAECn8aAAIRAAkJ9haeQADgAQARAAkJ9haeQADgAQAAAA==.',
['Kä']='Kätniss:BAAALgAECgYJBgAAAA==.',
La='Laaksy:BAACLgAFFH8MAAMTAAUJLAepBgDnAAATAAUJ8ASpBgDnAAAcAAMJ9QiWVgBxAAAuAAQKfx4AAhMACAl+EAEMAFIBABMACAl+EAEMAFIBAAAA.Ladraina:BAAALgAECgMJCgAAAA==.Landock:BAAALgAECgUJBQAAAA==.Lavaca:BAABLgAECn8nAAQjAAkJOyMZAgCyAgAkAAgJwSGBCQD5AgAjAAgJKSMZAgCyAgAlAAYJIR8WCgCYAQABLgAFFAMJCgABACwdAA==.',
Le='Lebronjames:BAAALgAFFAEJAQABLgAECgEJAQAEAAAAAA==.Legar:BAABLgAECn8bAAIdAAkJuheEDAAYAgAdAAkJuheEDAAYAgAAAA==.Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAACLgAFFH8QAAIVAAQJ9Q9WMgDlAAAVAAQJ9Q9WMgDlAAAuAAQKfysAAhUACQkIEGVAAJABABUACQkIEGVAAJABAAAA.Leprechaune:BAAALgAECgMJAwAAAA==.Leticia:BAAALgAECgkJDgAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Liechen:BAAALgAECgYJBgAAAA==.Linaraline:BAAALgAECgEJAQAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgUJEgAAAA==.Lotharmage:BAAALgAECggJEQAAAA==.Lotharpally:BAAALgAECgQJBAAAAA==.Lothlorìan:BAAALgAECgEJAQAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luminescent:BAAALgADCgIJAgAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAFFAEJAQAAAA==.',
Ma='Maelora:BAAALgADCgYJBgAAAA==.Magnessa:BAABLgAECn8XAAINAAkJhgRdnABBAQANAAkJhgRdnABBAQAAAA==.Malovious:BAAALgADCgkJCQAAAA==.Mandrakethan:BAAALgADCgkJHAAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgAECgEJAQAAAA==.Marist:BAABLgAECn8eAAMFAAkJGhFIXABIAQAFAAgJfw5IXABIAQAKAAEJVAUBvQAhAAAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.Maxumuss:BAAALgAECgYJBQAAAA==.',
Me='Medarana:BAAALgAECgEJAgAAAA==.Meliodäs:BAAALgAECgEJAQAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQAEAAAAAA==.Metamorlis:BAAALgAECgQJBAABLgAECgkJQwAbALEWAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAABLgAECn8jAAImAAYJgx5YFgCSAQAmAAYJgx5YFgCSAQAAAA==.Miku:BAAALgAECgkJDQABLgAECgkJLAALAOcZAA==.Milent:BAABLgAECn8/AAIRAAkJjBrPAQCcAQARAAkJjBrPAQCcAQAAAA==.Mimix:BAAALgAECgEJAQAAAA==.Miquiztli:BAAALgAECgkJBQAAAA==.Mizoci:BAAALgAECgEJAgAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJBAAAAA==.',
Mo='Moarteas:BAAALgAECgUJBgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Msspelled:BAABLgAECn8kAAQnAAkJ+RpjBABZAgAnAAkJHhpjBABZAgAaAAUJOg9JuwDTAAAoAAIJ/hTDPQA2AAAAAA==.',
Mv='Mvpiam:BAAALgAECgQJDAAAAA==.',
Mx='Mximus:BAAALgAECgIJAQABLgAECgYJBQAEAAAAAA==.',
My='Mystí:BAAALgAECggJDgAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAECgkJTQAJAKYjAA==.Nabstarr:BAABLgAECn9NAAQJAAkJpiN+AgCOAwAJAAkJpiN+AgCOAwAbAAkJ8hXSEgBGAgAIAAMJdxBLagB1AAAAAA==.Namtar:BAAALgAECgEJAgAAAA==.Nasroth:BAACLgAFFH8FAAIfAAMJFg8iOgDKAAAfAAMJFg8iOgDKAAAuAAQKfygAAh8ACAlHEts8ALEBAB8ACAlHEts8ALEBAAAA.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.Natureterror:BAAALgAECgUJBgAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Niibyter:BAABLgAECn8yAAImAAkJbiNdAgAjAwAmAAkJbiNdAgAjAwAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
No='Nowisforever:BAAALgADCgEJAgAAAA==.',
Ny='Nymneria:BAAALgAECgIJAgABLgAECgYJBQAEAAAAAA==.',
Od='Odînson:BAAALgAECgEJAQAAAA==.',
Ol='Oldgreyone:BAABLgAECn8UAAMVAAYJ2RAMbwDnAAAVAAYJ2RAMbwDnAAAWAAYJcgpoTgDTAAAAAA==.',
On='Onlyheelz:BAAALgAECgQJBwAAAA==.Onlylocks:BAABLgAECn8mAAMaAAkJbhS+PQDlAQAaAAkJmBO+PQDlAQAoAAUJFRB2KgAXAQAAAA==.Ontius:BAAALgAECgQJBQAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAABLgAECn8eAAMIAAkJtw/UJwCQAQAIAAkJtw/UJwCQAQAbAAQJRAh8aACLAAAAAA==.',
Or='Orangedrives:BAAALgADCgYJCwAAAA==.Oreeoreo:BAABLgAECn8rAAICAAkJ9Q91aQCTAQACAAkJ9Q91aQCTAQAAAA==.Orlathil:BAAALgADCgkJCQABLgAECgkJQwAbALEWAA==.Orlis:BAABLgAECn9DAAIbAAkJsRZ+AADdAQAbAAkJsRZ+AADdAQAAAA==.Oroe:BAAALgAECgYJDAAAAA==.',
Pa='Pallydan:BAAALgAECgMJBAABLgAECgkJKQANAI8WAA==.Pandamunx:BAAALgAECgQJAgAAAA==.',
Pe='Peludita:BAABLgAECn8WAAQVAAcJox0RMwDdAQAVAAcJox0RMwDdAQAWAAcJhBqfJADYAQAdAAEJsCCtKQBUAAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAECgYJCwABLgAECggJDgAEAAAAAA==.',
Ph='Philanthropy:BAABLgAECn8kAAMUAAgJeBnMCwAbAgAUAAgJeBnMCwAbAgAcAAcJlxQxNgBXAQAAAA==.Philtwifdloa:BAAALgADCgEJAQAAAA==.',
Pi='Pitchfiend:BAAALgAECgYJBgAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAFFAQJDgAMAOoUAA==.',
Pl='Plumh:BAAALgADCgMJAwAAAA==.Pläze:BAAALgAECgYJEgAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppy:BAABLgAECn8UAAQSAAkJ8B2TDwBfAgASAAcJKySTDwBfAgAeAAMJFAwEawBvAAAgAAEJhgtdpAAsAAAAAA==.',
Pr='Prayformercy:BAAALgAECgEJAQAAAA==.Praîmfaya:BAAALgAECgQJBQAAAA==.Primeangus:BAAALgAECgkJCQABLgAFFAMJCQARAMIKAA==.',
Pu='Punchpup:BAABLgAECn8pAAIgAAgJpROiKgBoAQAgAAgJpROiKgBoAQAAAA==.',
Py='Pyronorish:BAAALgAECgIJAgAAAA==.Pytthia:BAABLgAECn8qAAMIAAkJuRQxGQD8AQAIAAkJuRQxGQD8AQAJAAcJyxLeMwBHAQAAAA==.',
['Pä']='Pändamonium:BAAALgAECgQJBAAAAA==.',
Qu='Quicknclever:BAAALgAECgQJAwAAAA==.Quzbis:BAAALgAECgMJBgAAAA==.',
Ra='Rainenvy:BAAALgAECgYJBgAAAA==.Randamonk:BAAALgAECgUJBQAAAA==.Ranraku:BAAALgADCgEJAQAAAA==.Raptalia:BAAALgADCgcJBwABLgAECgkJLAALAOcZAA==.Rayphe:BAAALgADCgMJAwAAAA==.Raziel:BAABLgAECn8RAAIOAAgJSRk+NAAoAgAOAAgJSRk+NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQABLgAFFAYJFgAGAOMLAA==.Rectalrazor:BAAALgADCgYJDwAAAA==.Regade:BAAALgAECgEJAgABLgAECgkJKgAIALkUAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJCQAAAA==.Rem:BAAALgADCgUJCQAAAA==.',
Rh='Rhaena:BAABLgAECn8cAAILAAgJDQtTpAAxAQALAAgJDQtTpAAxAQAAAA==.Rhombus:BAABLgAECn86AAIYAAkJiQl6NACAAQAYAAkJiQl6NACAAQAAAA==.',
Ri='Rikiriki:BAABLgAECn8YAAMWAAYJuQILZgCFAAAWAAYJuQILZgCFAAAVAAYJFgKvogBrAAAAAA==.',
Rn='Rndnfluffy:BAAALgAECgEJAgAAAA==.',
Ro='Robok:BAAALgAECgEJAQAAAA==.Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJCAAAAA==.Ronkzar:BAAALgAECgQJBgAAAA==.Rotblossom:BAAALgAECggJEQAAAA==.Rotskar:BAAALgADCggJDAAAAA==.Roxishybrid:BAAALgAECgEJAQAAAA==.',
Rp='Rpgovan:BAAALgAECgQJBAAAAA==.',
Ru='Rubidious:BAAALgAECgMJBwAAAA==.Rukah:BAAALgAECgEJAQAAAA==.Ruth:BAABLgAECn8oAAIcAAkJqg67JwCmAQAcAAkJqg67JwCmAQAAAA==.',
['Rô']='Rôflstômp:BAAALgAECgEJAgAAAA==.',
Sa='Sacini:BAAALgADCgYJCgAAAA==.Sakai:BAAALgADCgYJCQAAAA==.Saltydog:BAAALgAECgIJAgAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Saratar:BAAALgAECgMJAwAAAA==.Sarlaana:BAAALgAECgQJBQAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgcJEgAAAA==.',
Sc='Scurge:BAAALgAECgIJAwABLgAECgYJBQAEAAAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Seizo:BAAALgAECgYJDwAAAA==.Selfesteem:BAAALgAECgUJCgABLgAECgkJKQANAI8WAA==.Setal:BAABLgAECn9AAAMcAAkJVB6NCwCgAgAcAAkJVB6NCwCgAgATAAEJIxHfPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAACLgAFFH8NAAIKAAUJrB1/HwAjAQAKAAUJrB1/HwAjAQAuAAQKfyUAAwoACQn2I2sBALIDAAoACQn2I2sBALIDAAUABgkbGOpCAHUBAAAA.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCQAAAA==.Sheenzilla:BAABLgAECn8nAAMcAAkJMgVmRQAUAQAcAAkJMgVmRQAUAQAUAAYJIQGDOACnAAAAAA==.Shelltear:BAAALgADCgYJCAAAAA==.Shelwreth:BAAALgAECgYJDAAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shiro:BAABLgAFFH8IAAISAAMJkAdxSACDAAASAAMJkAdxSACDAAABLgAFFAQJEAAVAHYNAA==.Shoinked:BAABLgAECn83AAIKAAgJaBBONwBbAQAKAAgJaBBONwBbAQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgAECgEJAQAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAABLgAECn9CAAIeAAkJmyRABQDtAgAeAAkJmyRABQDtAgAAAA==.',
Sl='Slak:BAABLgAECn8UAAIhAAkJChHUAwDRAQAhAAkJChHUAwDRAQAAAA==.',
Sm='Smallblades:BAAALgAECgEJAQABLgAECgcJHgAHAMARAA==.Smallchaos:BAABLgAECn8eAAIHAAcJwBHTKwAhAQAHAAcJwBHTKwAhAQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgcJHgAHAMARAA==.Smallêntropy:BAABLgAECn8XAAIDAAkJhQ5xDwBYAQADAAkJhQ5xDwBYAQAAAA==.Smelt:BAAALgAECgMJDAAAAA==.',
Sn='Snøt:BAAALgADCgcJDAAAAA==.',
So='Sokáar:BAAALgAECgkJAQAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgYJEgABLgAECgkJGgAaAI8YAA==.',
St='Stabbytrout:BAABLgAECn8VAAIkAAkJKheEGgAuAgAkAAkJKheEGgAuAgAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.Stormtalon:BAAALgADCgIJAgAAAA==.',
Su='Sugondis:BAACLgAFFH8IAAIgAAYJtBK9FwAEAQAgAAYJtBK9FwAEAQAuAAQKfxUAAiAACQn1IXAGABkDACAACQn1IXAGABkDAAEuAAUUCQk8ACIAriQA.Sunetra:BAABLgAECn8eAAILAAkJRQwOhQBlAQALAAkJRQwOhQBlAQAAAA==.Sunraku:BAAALgAECgEJAwABLgAECgEJBgAEAAAAAA==.Sunshine:BAABLgAECn8VAAIGAAgJFRaLDgDMAQAGAAgJFRaLDgDMAQAAAA==.Susì:BAAALgADCgIJAgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgcJCAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBwABLgAECgcJCAAEAAAAAA==.',
Ta='Taehyung:BAABLgAECn8WAAIaAAkJEwgkfwA6AQAaAAkJEwgkfwA6AQAAAA==.Taloki:BAAALgAECgYJDQAAAA==.Tangir:BAAALgAECgUJBQAAAA==.Tatavete:BAAALgADCgUJBQAAAA==.Tatsuhisa:BAAALgAECggJDQAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAABLgAECn8uAAMKAAgJXgWvVADnAAAKAAgJXgWvVADnAAAFAAUJAAXMmACiAAAAAA==.',
Th='Thallyn:BAAALgAECgcJBwAAAA==.',
Ti='Tinkerfoot:BAAALgADCgIJAgAAAA==.Tinny:BAAALgAECgMJCAAAAA==.Tippshunter:BAABLgAECn83AAIMAAkJNhygCACVAgAMAAkJNhygCACVAgAAAA==.',
To='Tognuwa:BAAALgAECgEJAQAAAA==.Tonguefu:BAAALgAECgEJAQAAAA==.Tonton:BAAALgAECgEJAQAAAA==.Toph:BAACLgAFFH8KAAMTAAQJihiDBAAlAQATAAQJshaDBAAlAQAcAAEJFyHyHgBbAAAuAAQKfyEABBMACQmwIVQJAEwCABMABwkqIVQJAEwCABwAAwlgHrxlAKkAABQAAwljBE89AIAAAAAA.Tophdh:BAABLgAECn8fAAIDAAkJfSK6AQD/AgADAAkJfSK6AQD/AgABLgAFFAQJCgATAIoYAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECgkJMAAeAEUXAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECgkJMAAeAEUXAA==.Tryit:BAAALgAECgQJBAABLgAECgkJMAAeAEUXAA==.Trythefox:BAABLgAECn8wAAIeAAkJRRddGQDbAQAeAAkJRRddGQDbAQAAAA==.',
Ts='Tseris:BAAALgAECgUJDwAAAA==.Tsukihana:BAAALgAECgUJDQAAAA==.',
Tu='Tuini:BAABLgAECn8iAAMFAAkJIhljGwBwAgAFAAkJIhljGwBwAgAKAAUJtAyLYwC7AAAAAA==.',
Ty='Tydis:BAABLgAECn85AAILAAgJnQ4eggBrAQALAAgJnQ4eggBrAQAAAA==.',
['Tá']='Tálonstorm:BAABLgAECn9CAAIiAAkJ8QcdAQDRAAAiAAkJ8QcdAQDRAAAAAA==.',
Ul='Ultra:BAAALgAECgMJBQAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.Untamed:BAAALgADCgkJCwAAAA==.',
Va='Vaehunt:BAEALgADCgMJBAABLgAFFAYJEQAOAJoTAA==.Vaesar:BAEALgADCgUJBgABLgAFFAYJEQAOAJoTAA==.Vaesara:BAECLgAFFH8RAAIOAAYJmhM9MgBcAQAOAAYJmhM9MgBcAQAuAAQKfy0AAg4ACQmBIXYKAPYCAA4ACQmBIXYKAPYCAAAA.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Valynaria:BAAALgAECgIJAgAAAA==.Vani:BAABLgAECn8dAAIbAAgJaQ0MMQBJAQAbAAgJaQ0MMQBJAQAAAA==.',
Ve='Velora:BAAALgAECgQJBAAAAA==.',
Vi='Vilthrax:BAAALgAECgYJBgAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwAEAAAAAA==.',
Wa='Wadorinramps:BAAALgAECgYJCwABLgAECgkJGwAdALoXAA==.Waffleiron:BAABLgAECn8XAAQJAAYJyyIdIgCDAQAJAAYJyyIdIgCDAQAbAAMJsx6VSwAKAQAIAAQJKRDBTgDVAAAAAA==.Watermelon:BAAALgAECggJEAAAAA==.',
Wf='Wforwumbo:BAAALgADCgEJAQAAAA==.',
Wh='Whalaski:BAACLgAFFH8FAAIRAAIJiQwjhQCRAAARAAIJiQwjhQCRAAAuAAQKfy4AAhEACQm6FhkqADYCABEACQm6FhkqADYCAAAA.Whistledown:BAAALgADCgEJAQAAAA==.',
Wi='Wickedsin:BAABLgAECn8bAAIoAAgJGgzHEgAfAQAoAAgJGgzHEgAfAQAAAA==.Windhurst:BAAALgAECgYJBgAAAA==.',
Wo='Woggieboggie:BAAALgAECgkJDAAAAA==.',
Wr='Wreckitman:BAACLgAFFH8WAAIVAAYJ9BM6GACdAQAVAAYJ9BM6GACdAQAuAAQKfx4AAhUACQlYHpsMAPoCABUACQlYHpsMAPoCAAAA.',
Xa='Xaalath:BAABLgAECn8qAAINAAgJiwuYiwBgAQANAAgJiwuYiwBgAQAAAA==.',
Xh='Xhile:BAAALgADCgEJAQAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAIUAAgJSwhvIQBwAQAUAAgJSwhvIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECggJEgAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.Yersn:BAAALgAECgQJBwAAAA==.',
Yo='Yobaz:BAAALgAECgYJBgAAAA==.Yohanan:BAAALgADCgYJBgAAAA==.Yozomi:BAAALgADCgQJBQAAAA==.',
Za='Zappya:BAAALgAECgYJBgAAAA==.Zarorisk:BAAALgAFFAIJAgABLgAFFAUJBgAGAGoTAA==.',
Ze='Zedd:BAAALgAECgEJAgABLgAECgkJIgAFACIZAA==.Zerø:BAAALgADCgcJBgAAAA==.Zetz:BAAALgADCgcJBwAAAA==.Zewse:BAAALgAECgEJAgAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAABLgAECn8cAAIMAAYJ+Bd8EgCbAQAMAAYJ+Bd8EgCbAQAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAABLgAECn8aAAILAAgJXxoUTwD1AQALAAgJXxoUTwD1AQAAAA==.',
Zu='Zuesb:BAAALgADCgUJBgAAAA==.',
Zy='Zyvidria:BAABLgAECn8bAAITAAkJLxXxBwC3AQATAAkJLxXxBwC3AQAAAA==.',
['Ãñ']='Ãñgêl:BAAALgAECgEJAQAAAA==.',
['Øn']='Ønyx:BAAALgAECgMJBAAAAA==.',
['ße']='ßeam:BAAALgAECgEJAQAAAA==.',
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
