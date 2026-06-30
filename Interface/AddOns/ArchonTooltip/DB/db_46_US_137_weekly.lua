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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Unknown-Unknown','Shaman-Restoration','Druid-Feral','DemonHunter-Havoc','Priest-Shadow','Priest-Discipline','Shaman-Elemental','Paladin-Retribution','Hunter-Survival','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Mistweaver','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Priest-Holy','Evoker-Augmentation','Druid-Guardian','Warrior-Fury','Monk-Windwalker','Mage-Arcane','Monk-Brewmaster','Warrior-Arms','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Warlock-Destruction',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-06-27',data={Ac='Acaval:BAACLgAFFH8KAAMBAAMJLB0cFwDRAAACAAMJLB0UkwDmAAABAAMJwRAcFwDRAAAuAAQKfxUAAwIACQm+IdYKABgDAAIACQm+IdYKABgDAAEAAQlrIiYvAGMAAAAA.Accursed:BAACLgAFFH8NAAIDAAQJPyUCAgCjAQADAAQJPyUCAgCjAQAuAAQKfyIAAgMACAl6JqsAAFYDAAMACAl6JqsAAFYDAAAA.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.Aduayro:BAAALgADCgQJBAAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Ai='Airpod:BAAALgAECgEJAQABLgAECggJEAAEAAAAAA==.',
Al='Aleighta:BAABLgAECn8cAAIFAAkJBAvGVgBbAQAFAAkJBAvGVgBbAQAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.Alyx:BAAALgAECgMJBQAAAA==.',
Am='Amadia:BAAALgAECgMJBgAAAA==.',
An='Anabel:BAABLgAECn8rAAIGAAkJbBGJAQA6AQAGAAkJbBGJAQA6AQAAAA==.Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ao='Aoi:BAAALgADCgcJBwABLgAECgkJIQAHAMAXAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgIJAgAAAA==.',
As='Asatrath:BAAALgAECgYJDwAAAA==.Ashkillz:BAABLgAECn8pAAMIAAkJxSAwAQDrAQAIAAgJbSAwAQDrAQAJAAEJcxvOCwBUAAAAAA==.Ashtuck:BAAALgAECgYJCQAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAABLgAECn8kAAIKAAkJWRGnIwDJAQAKAAkJWRGnIwDJAQAAAA==.',
Av='Avenger:BAAALgAECgEJAQABLgAECgYJBQAEAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJCAAAAA==.',
Ba='Badoussi:BAAALgAECgYJEwABLgAFFAUJCAAGAPYUAA==.Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgYJBwAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8TAAILAAYJ9CCsHQCRAQALAAYJ9CCsHQCRAQAuAAQKfxoAAgsACAn8Ij0RAAYDAAsACAn8Ij0RAAYDAAAA.',
Be='Beansy:BAAALgAECggJEQAAAA==.Beefomancer:BAAALgAECgYJBgABLgAECgkJNwAMADYcAA==.Belan:BAABLgAECn8uAAINAAkJ/hgQBQCIAQANAAkJ/hgQBQCIAQAAAA==.Belladin:BAABLgAECn8gAAILAAkJ0x/THgCyAgALAAkJ0x/THgCyAgAAAA==.',
Bi='Bismuth:BAAALgAECgYJBgAAAA==.',
Bl='Blakeshelton:BAAALgAECgIJBgABLgAECggJEAAEAAAAAA==.Blameurself:BAABLgAECn8VAAIOAAkJ+x70IwBAAgAOAAkJ+x70IwBAAgAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECgkJFQAOAPseAA==.Blaster:BAAALgAECgEJBgAAAA==.Blite:BAAALgADCgQJDQAAAA==.Bluethain:BAAALgAECggJDgAAAA==.',
Bo='Bombakaap:BAAALgAECgYJCwAAAA==.Bomburst:BAABLgAECn8hAAIPAAgJyBDUEgCKAQAPAAgJyBDUEgCKAQAAAA==.Bonelespizza:BAACLgAFFH8IAAICAAIJOQqFSACTAAACAAIJOQqFSACTAAAuAAQKfzgAAwIACQlhH9sjAK8CAAIACQmHHtsjAK8CAAEABgmKHw8NAKYBAAAA.Boogiebabe:BAAALgAECgcJDAAAAA==.Boomhauerr:BAAALgAECgYJBgAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgAECgQJBAAAAA==.Briaris:BAACLgAFFH8OAAIMAAQJ6hScEgA0AQAMAAQJ6hScEgA0AQAuAAQKfyMABAwACAmCHTgIAGsCAAwACAmCHTgIAGsCABAAAQkuC64+ACwAABEAAQkIAklNASQAAAAA.Bruel:BAAALgADCgUJBQAAAA==.Brugaras:BAAALgADCgcJCwAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
['Bê']='Bêz:BAAALgAECgEJAQAAAA==.',
['Bë']='Bëz:BAABLgAECn84AAIDAAkJ5SJSAQAgAwADAAkJ5SJSAQAgAwAAAA==.',
Ca='Cachinnare:BAAALgAECgUJCgABLgAFFAIJAgAEAAAAAA==.Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Capziesh:BAAALgAECgQJBQAAAA==.Casteel:BAAALgAECggJEAAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgYJBwABLgAFFAcJFwAJAOcSAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAABLgAECn8ZAAILAAcJcBEmkABSAQALAAcJcBEmkABSAQAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAABLgAECn8fAAISAAkJ0SEBCQALAwASAAkJ0SEBCQALAwAAAA==.Cosmicjay:BAECLgAFFH8FAAIKAAMJMBO/NQC3AAAKAAMJMBO/NQC3AAAuAAQKfxgAAgoACAmsIHwTAFECAAoACAmsIHwTAFECAAAA.Cosmicnova:BAEALgAFFAEJAQABLgAFFAMJBQAKADATAA==.Costa:BAAALgAECgQJBQAAAA==.',
Cr='Crentacles:BAABLgAECn8dAAIKAAkJrxZmGwAGAgAKAAkJrxZmGwAGAgAAAA==.Critshade:BAAALgAFFAIJAgAAAA==.Crow:BAAALgAFFAUJJAAAAQ==.',
Da='Dadeulus:BAAALgAECgcJDAAAAA==.Daedis:BAAALgAECgEJAgAAAA==.Daegán:BAAALgAECgEJAgAAAA==.Daffodil:BAABLgAECn8wAAMTAAkJZhHKBgDeAQATAAkJZhHKBgDeAQAUAAMJ2wJKMwBaAAAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgAEAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8XAAIVAAcJ0Qs9GACdAQAVAAcJ0Qs9GACdAQAuAAQKfyEAAxUACQl+HEkdAFMCABUACQl+HEkdAFMCABYAAQmSA4eiAB8AAAAA.Dantruis:BAAALgAECgEJAQABLgAFFAcJFwAVANELAA==.Darkshiver:BAAALgADCgEJAgABLgAECgEJBgAEAAAAAA==.Darqlaidee:BAAALgADCgEJAQAAAA==.Dawnslight:BAABLgAECn8WAAILAAcJ3gF2QQFqAAALAAcJ3gF2QQFqAAAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Dedebop:BAAALgAECgIJBQAAAA==.Deiside:BAAALgADCgkJCQAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAcJDAAXAG0aAA==.Denareyeth:BAAALgAECgUJCwAAAA==.Dephiance:BAAALgAECgcJCAABLgAECgkJMAAIAOIVAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJEAAAAA==.',
Di='Diabla:BAABLgAECn8XAAIYAAYJeCTQFwBTAgAYAAYJeCTQFwBTAgAAAA==.Dinsfirë:BAAALgAECgEJAQAAAA==.Diothorn:BAABLgAECn8kAAMLAAgJ+xjmWADBAQALAAcJtxnmWADBAQAZAAMJ8hSOLQC0AAAAAA==.Disappointed:BAAALgADCggJDAAAAA==.Divanas:BAABLgAECn8hAAIaAAgJKQganQAEAQAaAAgJKQganQAEAQAAAA==.Divi:BAABLgAECn8lAAIbAAkJrCHSAwBMAwAbAAkJrCHSAwBMAwAAAA==.',
Do='Doxa:BAAALgADCgMJCAAAAA==.',
Dr='Dragonboi:BAABLgAECn8aAAIcAAkJhxGIJQCzAQAcAAkJhxGIJQCzAQAAAA==.Dreàd:BAAALgAECgEJAQAAAA==.Drpepperz:BAABLgAFFH8GAAIWAAQJqBLLIwAIAQAWAAQJqBLLIwAIAQAAAA==.Drägonwärior:BAAALgAECgEJAQAAAA==.',
Du='Durgan:BAAALgADCgQJBwAAAA==.Durock:BAAALgADCgQJBAABLgAECgkJGwAdALoXAA==.',
Dy='Dyria:BAAALgAECgIJAgAAAA==.',
Ed='Edging:BAAALgADCgYJBgAAAA==.',
El='Elegance:BAAALgAECgIJAgABLgAECgkJMAAIAOIVAA==.Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgAECgEJAQAAAA==.Ellayria:BAAALgAECgYJCgAAAA==.',
Em='Emberrose:BAAALgADCgkJGwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Enhancedpant:BAAALgAECgQJBgAAAA==.Ensetral:BAAALgAECgEJAQAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgcJCwAEAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJCQAAAA==.Evelithillyn:BAAALgAECgQJBQABLgAECgkJFQAOAPseAA==.Everydae:BAACLgAFFH8FAAIcAAMJEAssGwCUAAAcAAMJEAssGwCUAAAuAAQKfyYAAhwACQnUHzgMAJcCABwACQnUHzgMAJcCAAAA.',
Ex='Extrajuicy:BAAALgAFFAIJBAAAAA==.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECgkJGgAaAI8YAA==.',
Fa='Fakedruid:BAABLgAECn8WAAIdAAcJGiS0CQBOAgAdAAcJGiS0CQBOAgABLgAECgkJNwAMADYcAA==.Falarzer:BAAALgADCgIJAgAAAA==.Fatwarlock:BAAALgAECgEJAQAAAA==.',
Fe='Feledris:BAAALgAECgQJBQAAAA==.Feybeasts:BAAALgAFFAIJAgAAAA==.Feárbomber:BAAALgAFFAEJAQAAAA==.',
Ff='Ffand:BAABLgAECn8WAAIRAAYJ5x/VOADLAQARAAYJ5x/VOADLAQAAAA==.',
Fh='Fharia:BAAALgAECgUJBgAAAA==.',
Fi='Filafal:BAAALgADCgEJAQABLgAECggJGQACAK0aAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flawless:BAAALgAECgEJAQAAAA==.Flayr:BAAALgADCgkJDQAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fordaferson:BAAALgADCgMJAwAAAA==.Fortitude:BAAALgAECgcJCwAAAA==.',
Fu='Fusky:BAABLgAECn8mAAIFAAkJuBJMKAAdAgAFAAkJuBJMKAAdAgAAAA==.',
Fy='Fynn:BAACLgAFFH8NAAIPAAUJkQ2YCwAIAQAPAAUJkQ2YCwAIAQAuAAQKfyAAAw8ACAnFFwwLABwCAA8ACAnFFwwLABwCAAUAAQmjAYipACQAAAAA.',
['Fä']='Fätpàndà:BAAALgADCgYJBgAAAA==.',
Ga='Galadria:BAACLgAFFH8PAAIWAAUJWRFqJQAAAQAWAAUJWRFqJQAAAQAuAAQKfxkAAhYACQmwIOoBAIsBABYACQmwIOoBAIsBAAAA.Ganeda:BAAALgAECgcJDAABLgAECgkJGwAdALoXAA==.Garamond:BAAALgADCgEJAQAAAA==.Garchomp:BAAALgAECgcJBgAAAA==.Garrish:BAAALgADCgEJAQAAAA==.',
Ge='Geraldini:BAAALgAECgMJAwAAAA==.Gerwik:BAABLgAECn8tAAIRAAkJkxjzMwANAgARAAkJkxjzMwANAgAAAA==.',
Gi='Ging:BAABLgAECn8WAAIeAAcJJw9CPwBIAQAeAAcJJw9CPwBIAQAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDQAAAA==.Gogetta:BAAALgAECgEJAQAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goldenlock:BAAALgAECgYJDwAAAA==.Goliather:BAAALgADCgEJAQAAAA==.Govana:BAABLgAECn8hAAICAAkJbxgTAwDQAQACAAkJbxgTAwDQAQAAAA==.',
Gr='Greenleaves:BAABLgAECn8ZAAIfAAgJ8hhPHADMAQAfAAgJ8hhPHADMAQAAAA==.Greenpepperz:BAAALgADCgYJBgAAAA==.Gregsh:BAABLgAECn9CAAMNAAkJJBmrMwBKAgANAAkJJBmrMwBKAgAgAAEJ6APUIQAkAAAAAA==.Grimward:BAAALgAECgYJBgAAAA==.Grocrush:BAAALgAECgEJAQAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Guenther:BAAALgAECgEJAQABLgAECgkJIgAFACIZAA==.Gummifishz:BAAALgADCgcJBwAAAA==.Gummiwormz:BAABLgAECn8sAAIYAAkJrx+7BABLAwAYAAkJrx+7BABLAwAAAA==.',
Ha='Hailin:BAABLgAECn8sAAILAAkJ5xlVPgAMAgALAAkJ5xlVPgAMAgAAAA==.Halfheal:BAAALgAECggJDgAAAA==.Halrem:BAAALgAECgIJAgAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8gAAIZAAgJuBrrEAC1AQAZAAgJuBrrEAC1AQAAAA==.Havocskiss:BAAALgAECgEJAQAAAA==.',
He='Heherawr:BAAALgADCgcJBwABLgAECgUJDAAEAAAAAA==.Hellman:BAAALgADCgUJCQAAAA==.Hertzabit:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
Hi='Hightroller:BAABLgAECn8vAAIRAAkJehpSIABmAgARAAkJehpSIABmAgAAAA==.Hima:BAABLgAECn8hAAIHAAkJwBd0DgA+AgAHAAkJwBd0DgA+AgAAAA==.',
Hn='Hnri:BAAALgAECgEJAgAAAA==.',
Ho='Holyjenkins:BAAALgADCgkJDgAAAA==.Holysathh:BAAALgAECgUJDgABLgAECgkJGwAdALoXAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Holystormm:BAAALgAECgQJBgAAAA==.Homulily:BAAALgADCggJGwAAAA==.Hornggry:BAAALgAECgQJAwABLgAECggJGgAhAJ4dAA==.Horngrry:BAAALgAECggJEQABLgAECggJGgAhAJ4dAA==.Horngryer:BAAALgAECgQJBQABLgAECggJGgAhAJ4dAA==.Horngryerr:BAABLgAECn8aAAIhAAgJnh2/JgB5AQAhAAgJnh2/JgB5AQAAAA==.Horngryish:BAAALgADCgEJAQABLgAECggJGgAhAJ4dAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJBQABLgAECgkJNwASABcaAA==.',
Hu='Hulkshe:BAAALgAECgkJCQAAAA==.Huntingpants:BAABLgAECn8eAAIQAAkJRREKCwC7AQAQAAkJRREKCwC7AQAAAA==.',
Ic='Icianri:BAAALgAFFAEJAQAAAA==.',
Il='Ilovebagels:BAAALgADCgkJDwAAAA==.',
Im='Imkillho:BAAALgAECgYJDAABLgAECggJGgAhAJ4dAA==.',
In='Inspiredbox:BAAALgAECgcJCQAAAA==.Inverness:BAAALgAECgEJAQAAAA==.',
It='Itzuri:BAAALgADCgEJAQAAAA==.',
Ja='Jacobsangle:BAAALgAECgEJAQABLgAECgEJBgAEAAAAAA==.Jankismith:BAABLgAECn8/AAISAAkJTRMYKwDVAQASAAkJTRMYKwDVAQAAAA==.Jayy:BAABLgAECn86AAIMAAkJ9xRJEQAhAgAMAAkJ9xRJEQAhAgAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAkJRQAiAK4kAA==.Jenny:BAABLgAECn8wAAILAAkJMRq4PwAIAgALAAkJMRq4PwAIAgAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgcJDwABLgAECgkJEwAEAAAAAA==.Jitoflight:BAAALgAECgYJBgAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgYJDAAAAA==.',
Ju='Jugger:BAAALgAECgEJAQAAAA==.Junieb:BAABLgAECn8eAAINAAkJHws1kQBVAQANAAkJHws1kQBVAQAAAA==.',
Ka='Kachiko:BAAALgADCggJJQAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAABLgAECn8VAAIaAAgJOwsAdQBQAQAaAAgJOwsAdQBQAQAAAA==.Kamerth:BAABLgAECn8zAAMJAAkJcwlvJwCWAQAJAAkJcwlvJwCWAQAIAAgJQAmxOQAtAQAAAA==.Kamugi:BAAALgAECgEJAQABLgAFFAQJEgAUAAANAA==.Kapnkrunch:BAAALgAECgUJBQAAAA==.Karluron:BAABLgAECn8rAAIIAAkJTBqqDwBhAgAIAAkJTBqqDwBhAgAAAA==.Karlutros:BAABLgAECn8pAAIIAAkJ/hGLIADCAQAIAAkJ/hGLIADCAQAAAA==.Katastrafia:BAAALgAECgMJAwAAAA==.Katimeut:BAAALgAECgQJBAABLgAFFAcJIQAXAHklAA==.Katowo:BAAALgAFFAEJAQABLgAFFAcJIQAXAHklAA==.Katuwuagain:BAACLgAFFH8hAAIXAAcJeSUqBwAYAgAXAAcJeSUqBwAYAgAuAAQKfxcAAhcACQk3JsoAAGUDABcACQk3JsoAAGUDAAAA.Kazure:BAABLgAECn8rAAIUAAkJcQ16FACDAQAUAAkJcQ16FACDAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn9JAAIeAAkJUhSsGQAhAgAeAAkJUhSsGQAhAgAAAA==.Keniilar:BAAALgAECgEJAQAAAA==.Kenilar:BAAALgAECgcJDwAAAA==.Keybricker:BAAALgAECgcJEAABLgAECgkJNwAMADYcAA==.',
Kh='Khaôtic:BAABLgAECn8XAAIOAAYJCRmDbQBIAQAOAAYJCRmDbQBIAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgAECgQJBwAAAA==.Kiraeshh:BAABLgAECn8ZAAINAAcJ/RKbkQBVAQANAAcJ/RKbkQBVAQAAAA==.Kittykat:BAAALgAECgQJBwAAAA==.',
Ko='Kolonna:BAAALgAECgMJAwAAAA==.Korngry:BAAALgAECgEJAQABLgAECggJGgAhAJ4dAA==.',
Kr='Krakkin:BAAALgAECgYJEQAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgAECgYJBgAAAA==.Krieash:BAAALgADCggJCAAAAA==.Krumpas:BAAALgAECgEJAQABLgAECggJGgAhAJ4dAA==.',
Ky='Kyllea:BAABLgAECn8aAAIRAAkJ9habQADgAQARAAkJ9habQADgAQAAAA==.',
['Kä']='Kätniss:BAAALgAECgYJBgAAAA==.',
La='Laaksy:BAACLgAFFH8MAAMTAAUJLAenBgDnAAATAAUJ8ASnBgDnAAAcAAMJ9QiXVgBxAAAuAAQKfx4AAhMACAl+EAAMAFIBABMACAl+EAAMAFIBAAAA.Ladraina:BAAALgAECgMJCgAAAA==.Landock:BAAALgAECgYJCwAAAA==.Lavaca:BAABLgAECn8nAAQjAAkJOyMZAgCyAgAkAAgJwSGBCQD5AgAjAAgJKSMZAgCyAgAlAAYJIR8WCgCYAQABLgAFFAMJCgABACwdAA==.',
Le='Lebronjames:BAABLgAECn8UAAMkAAgJGBYxAQCxAQAkAAcJiRYxAQCxAQAjAAEJcROEIwA6AAABLgAECgEJAQAEAAAAAA==.Legar:BAABLgAECn8bAAIdAAkJuheEDAAYAgAdAAkJuheEDAAYAgAAAA==.Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAACLgAFFH8SAAIVAAQJ9Q9PMgDlAAAVAAQJ9Q9PMgDlAAAuAAQKfysAAhUACQkIEGJAAJABABUACQkIEGJAAJABAAAA.Leprechaune:BAAALgAECgMJAwAAAA==.Leticia:BAAALgAECgkJDgAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Liechen:BAAALgAECgYJBgAAAA==.Linaraline:BAAALgAECgEJAgAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgUJEgAAAA==.Lotharmage:BAAALgAECggJEQAAAA==.Lotharpally:BAAALgAECgQJBAAAAA==.Lothlorìan:BAAALgAECgEJAQAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luminescent:BAAALgADCgIJAgAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAFFAEJAQAAAA==.',
Ma='Maelora:BAAALgADCgYJBgAAAA==.Magnessa:BAABLgAECn8XAAINAAkJhgRfnABBAQANAAkJhgRfnABBAQAAAA==.Malovious:BAAALgADCgkJCQAAAA==.Mandrakethan:BAAALgADCgkJHAAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgAECgEJAQAAAA==.Marist:BAABLgAECn8eAAMFAAkJGhFQXABIAQAFAAgJfw5QXABIAQAKAAEJVAUFvQAhAAAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.Maxumuss:BAAALgAECgYJBQAAAA==.',
Me='Medarana:BAAALgAECgEJAgAAAA==.Meliodäs:BAAALgAECgEJAQAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQAEAAAAAA==.Metamorlis:BAAALgAECgQJBAABLgAECgkJRQAbAA4XAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAABLgAECn8jAAImAAYJgx5WFgCSAQAmAAYJgx5WFgCSAQAAAA==.Miku:BAAALgAECgkJDQABLgAECgkJLAALAOcZAA==.Milent:BAABLgAECn9FAAIRAAkJ5hoHBAC+AQARAAkJ5hoHBAC+AQAAAA==.Mimix:BAAALgAECgEJAQAAAA==.Miquiztli:BAAALgAECgkJBQAAAA==.Mizoci:BAAALgAECgEJAgAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJBAAAAA==.',
Mo='Moarteas:BAAALgAECgUJBgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Mss:BAAALgADCgEJAQAAAA==.Msspelled:BAABLgAECn8kAAQnAAkJ+RpjBABZAgAnAAkJHhpjBABZAgAaAAUJOg9IuwDTAAAoAAIJ/hTEPQA2AAAAAA==.',
Mv='Mvpiam:BAAALgAECgQJDAAAAA==.',
Mx='Mximus:BAAALgAECgIJAQABLgAECgYJBQAEAAAAAA==.',
My='Mystí:BAAALgAECggJDgAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAFFAIJBgAJAAkWAA==.Nabstarr:BAACLgAFFH8GAAIJAAIJCRasEgB7AAAJAAIJCRasEgB7AAAuAAQKf1IABAkACQnLI30CAI4DAAkACQnLI30CAI4DABsACQnyFdISAEYCAAgAAwl3EFdqAHUAAAAA.Namtar:BAAALgAECgEJAgAAAA==.Nasroth:BAACLgAFFH8FAAIeAAMJFg8eOgDKAAAeAAMJFg8eOgDKAAAuAAQKfygAAh4ACAlHEts8ALEBAB4ACAlHEts8ALEBAAAA.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.Natureterror:BAAALgAECgQJBQAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Niibyter:BAABLgAECn8yAAImAAkJbiNdAgAjAwAmAAkJbiNdAgAjAwAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
No='Nowisforever:BAAALgADCgEJAgAAAA==.',
Ny='Nymneria:BAAALgAECgIJAgABLgAECgYJBQAEAAAAAA==.',
Od='Odînson:BAAALgAECgEJAQAAAA==.',
Ol='Oldgreyone:BAABLgAECn8UAAMVAAYJ2RAKbwDnAAAVAAYJ2RAKbwDnAAAWAAYJcgpvTgDTAAAAAA==.',
On='Onlyheelz:BAAALgAECgQJBwAAAA==.Onlylocks:BAABLgAECn8mAAMaAAkJbhTAPQDlAQAaAAkJmBPAPQDlAQAoAAUJFRB2KgAXAQAAAA==.Ontius:BAAALgAECgQJBQAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAABLgAECn8eAAMIAAkJtw/VJwCQAQAIAAkJtw/VJwCQAQAbAAQJRAh8aACLAAAAAA==.',
Or='Orangedrives:BAAALgADCgYJCwAAAA==.Oreeoreo:BAABLgAECn8wAAICAAkJshBBCQD6AAACAAkJshBBCQD6AAAAAA==.Orlathil:BAAALgADCgkJEgABLgAECgkJRQAbAA4XAA==.Orlis:BAABLgAECn9FAAIbAAkJDhfNAABKAgAbAAkJDhfNAABKAgAAAA==.Oroe:BAAALgAECgYJDAAAAA==.',
Pa='Pallydan:BAAALgAECgMJBAABLgAECgkJKgANAI8WAA==.Pandamunx:BAAALgAECgQJAgAAAA==.',
Pe='Peludita:BAABLgAECn8WAAQVAAcJox0RMwDdAQAVAAcJox0RMwDdAQAWAAcJhBqfJADYAQAdAAEJsCCtKQBUAAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAFFAIJAgABLgAECggJDgAEAAAAAA==.',
Ph='Phaka:BAAALgAECgEJAQABLgAECgkJKgANAI8WAA==.Philanthropy:BAABLgAECn8kAAMUAAgJeBnMCwAbAgAUAAgJeBnMCwAbAgAcAAcJlxQzNgBXAQAAAA==.Philtwifdloa:BAAALgADCgEJAQAAAA==.',
Pi='Pitchfiend:BAAALgAECgYJBgAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAFFAQJDgAMAOoUAA==.',
Pl='Plissken:BAAALgADCgcJAQAAAA==.Plumh:BAAALgADCgMJAwAAAA==.Pläze:BAAALgAECgYJEgAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppasmuurf:BAABLgAECn8aAAIaAAkJjxjbKgAvAgAaAAkJjxjbKgAvAgAAAA==.Poppy:BAABLgAECn8UAAQSAAkJ8B2TDwBfAgASAAcJKySTDwBfAgAhAAMJFAwHawBvAAAfAAEJhgtepAAsAAAAAA==.',
Pr='Prayformercy:BAAALgAECgEJAQAAAA==.Praîmfaya:BAAALgAECgQJBQAAAA==.Primeangus:BAAALgAECgkJCQABLgAFFAMJCwARAMIKAA==.',
Pu='Punchpup:BAABLgAECn8pAAIfAAgJpROjKgBoAQAfAAgJpROjKgBoAQAAAA==.',
Py='Pyronorish:BAAALgAECgQJBQAAAA==.Pytthia:BAABLgAECn8wAAMIAAkJ4hUxGQD8AQAIAAkJ4hUxGQD8AQAJAAcJyxLfMwBHAQAAAA==.',
['Pä']='Pändamonium:BAAALgAECgQJBAAAAA==.',
Qu='Quicknclever:BAAALgAECgQJAwAAAA==.Quzbis:BAAALgAECgMJBgAAAA==.',
Ra='Rainenvy:BAAALgAECgYJBgAAAA==.Randamonk:BAAALgAECgUJBQAAAA==.Ranraku:BAAALgADCgEJAQAAAA==.Raptalia:BAAALgADCgcJBwABLgAECgkJLAALAOcZAA==.Rayphe:BAAALgADCgMJAwAAAA==.Rayquaza:BAABLgAFFH8KAAIUAAYJphbYAQDkAQAUAAYJphbYAQDkAQABLgAFFAkJIgAEAAAAAA==.Raziel:BAABLgAECn8RAAIOAAgJSRk+NAAoAgAOAAgJSRk+NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQAAAA==.Rectalrazor:BAAALgAECgQJBQAAAA==.Regade:BAAALgAECgEJAgABLgAECgkJMAAIAOIVAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJCQAAAA==.Rem:BAAALgADCgUJCQAAAA==.',
Rh='Rhaena:BAABLgAECn8cAAILAAgJDQtTpAAxAQALAAgJDQtTpAAxAQAAAA==.Rhombus:BAABLgAECn86AAIYAAkJiQl7NACAAQAYAAkJiQl7NACAAQAAAA==.',
Ri='Rickjamesbia:BAAALgAECgEJAQAAAA==.Rikiriki:BAABLgAECn8YAAMWAAYJuQIPZgCFAAAWAAYJuQIPZgCFAAAVAAYJFgKuogBrAAAAAA==.',
Rn='Rndnfluffy:BAAALgAECgEJAgAAAA==.',
Ro='Robok:BAAALgAECgEJAQAAAA==.Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJCAAAAA==.Ronkzar:BAAALgAECgQJBgAAAA==.Rotblossom:BAAALgAECggJEQAAAA==.Rotskar:BAAALgADCggJDAAAAA==.Roxishybrid:BAAALgAECgEJAQAAAA==.',
Rp='Rpgovan:BAAALgAECgQJBAAAAA==.',
Ru='Rubidious:BAAALgAECgMJBwAAAA==.Rukah:BAAALgAECgEJAQAAAA==.Ruth:BAABLgAECn8oAAIcAAkJqg68JwCmAQAcAAkJqg68JwCmAQAAAA==.',
['Rô']='Rôflstômp:BAAALgAECgEJAgAAAA==.',
Sa='Sacini:BAAALgADCgYJCgAAAA==.Sakai:BAAALgADCgYJCQAAAA==.Saltydog:BAAALgAECgQJBgAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Saratar:BAAALgAECgMJAwAAAA==.Sarlaana:BAAALgAECgQJBQAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgcJEgAAAA==.',
Sc='Scurge:BAAALgAECgIJAwABLgAECgYJBQAEAAAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Seizo:BAAALgAECgYJDwAAAA==.Selfesteem:BAAALgAECgUJCgABLgAECgkJKgANAI8WAA==.Setal:BAABLgAECn9AAAMcAAkJVB6OCwCgAgAcAAkJVB6OCwCgAgATAAEJIxHfPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAACLgAFFH8OAAIKAAUJrB1/HwAjAQAKAAUJrB1/HwAjAQAuAAQKfyUAAwoACQn2I2sBALIDAAoACQn2I2sBALIDAAUABgkbGOpCAHUBAAAA.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCQAAAA==.Sheenzilla:BAABLgAECn8rAAMUAAkJsgqDOACnAAAUAAYJIQGDOACnAAAcAAkJPgbTBgCLAAAAAA==.Shelltear:BAAALgADCgYJCAAAAA==.Shelwreth:BAAALgAECgYJDAAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shiro:BAABLgAFFH8IAAISAAMJkAd0SACDAAASAAMJkAd0SACDAAABLgAFFAQJEAAVAHYNAA==.Shoinked:BAABLgAECn83AAIKAAgJaBBQNwBbAQAKAAgJaBBQNwBbAQAAAA==.Shoveldin:BAAALgAECgEJAQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgAECgEJAQAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAABLgAECn9EAAIhAAkJmyRBBQDtAgAhAAkJmyRBBQDtAgABLgAFFAEJAQAEAAAAAA==.',
Sl='Slak:BAABLgAECn8UAAIgAAkJChHUAwDRAQAgAAkJChHUAwDRAQAAAA==.',
Sm='Smallblades:BAAALgAECgEJAQABLgAECgcJHgAHAMARAA==.Smallchaos:BAABLgAECn8eAAIHAAcJwBHXKwAhAQAHAAcJwBHXKwAhAQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgcJHgAHAMARAA==.Smallêntropy:BAABLgAECn8XAAIDAAkJhQ5xDwBYAQADAAkJhQ5xDwBYAQAAAA==.Smelt:BAAALgAECgMJDAAAAA==.',
Sn='Snøt:BAAALgADCgcJDAAAAA==.',
So='Sokáar:BAAALgAECgkJAQAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgYJEgABLgAECgkJGgAaAI8YAA==.',
St='Stabbytrout:BAABLgAECn8VAAIkAAkJKheEGgAuAgAkAAkJKheEGgAuAgAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.Stormtalon:BAAALgAECgEJAQAAAA==.Støney:BAAALgAECgcJBgAAAA==.',
Su='Sugondis:BAACLgAFFH8JAAIfAAYJZxW7FwAEAQAfAAYJZxW7FwAEAQAuAAQKfxUAAh8ACQn1IXAGABkDAB8ACQn1IXAGABkDAAEuAAUUCQlFACIAriQA.Sunetra:BAABLgAECn8fAAILAAkJ0g0OhQBlAQALAAkJ0g0OhQBlAQAAAA==.Sunraku:BAAALgAECgEJAwABLgAECgEJBgAEAAAAAA==.Sunshine:BAABLgAECn8VAAIGAAgJFRaMDgDMAQAGAAgJFRaMDgDMAQAAAA==.Susì:BAAALgADCgIJAgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgcJDAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBwABLgAECgcJDAAEAAAAAA==.',
Ta='Taehyung:BAABLgAECn8WAAIaAAkJEwgnfwA6AQAaAAkJEwgnfwA6AQAAAA==.Taloki:BAAALgAECgYJDwAAAA==.Tangir:BAAALgAECgUJBQAAAA==.Tatavete:BAAALgADCgUJBQAAAA==.Tatsuhisa:BAAALgAECggJDQAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAABLgAECn8wAAMKAAkJ3QWxVADnAAAKAAkJ3QWxVADnAAAFAAUJAAXPmACiAAAAAA==.',
Th='Thallyn:BAAALgAECgcJBwAAAA==.',
Ti='Tinkerfoot:BAAALgADCgIJAgAAAA==.Tinny:BAAALgAECgMJCAAAAA==.Tippshunter:BAABLgAECn83AAIMAAkJNhyfCACVAgAMAAkJNhyfCACVAgAAAA==.',
To='Tognuwa:BAAALgAECgEJAQAAAA==.Tonguefu:BAAALgAECgEJAQAAAA==.Tonton:BAAALgAECgEJAQAAAA==.Toph:BAACLgAFFH8KAAMTAAQJihiBBAAlAQATAAQJshaBBAAlAQAcAAEJFyHyHgBbAAAuAAQKfyEABBMACQmwIVQJAEwCABMABwkqIVQJAEwCABwAAwlgHr9lAKkAABQAAwljBE89AIAAAAAA.Tophdh:BAABLgAECn8fAAIDAAkJfSK6AQD/AgADAAkJfSK6AQD/AgABLgAFFAQJCgATAIoYAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECgkJNQAhAIMZAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECgkJNQAhAIMZAA==.Tryit:BAAALgAECgQJBAABLgAECgkJNQAhAIMZAA==.Trythefox:BAABLgAECn81AAIhAAkJgxmcAQBSAQAhAAkJgxmcAQBSAQAAAA==.',
Ts='Tseris:BAAALgAECgUJDwAAAA==.Tsukihana:BAAALgAECgUJDQAAAA==.',
Tu='Tuini:BAABLgAECn8iAAMFAAkJIhllGwBwAgAFAAkJIhllGwBwAgAKAAUJtAyNYwC7AAAAAA==.',
Ty='Tydis:BAABLgAECn85AAILAAgJnQ4dggBrAQALAAgJnQ4dggBrAQAAAA==.',
['Tá']='Tálonstorm:BAABLgAECn9DAAIiAAkJYAj9AgDUAAAiAAkJYAj9AgDUAAAAAA==.',
Ul='Ultra:BAAALgAECgMJBQAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.Untamed:BAAALgADCgkJCwAAAA==.',
Va='Vaehunt:BAEALgAFFAIJAgABLgAFFAYJEgAOAPcTAA==.Vaesar:BAEALgADCgUJBgABLgAFFAYJEgAOAPcTAA==.Vaesara:BAECLgAFFH8SAAIOAAYJ9xMzMgBcAQAOAAYJ9xMzMgBcAQAuAAQKfy0AAg4ACQmBIXMKAPYCAA4ACQmBIXMKAPYCAAAA.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Valynaria:BAAALgAECgIJAgAAAA==.Vani:BAABLgAECn8eAAIbAAgJaQ0PMQBJAQAbAAgJaQ0PMQBJAQAAAA==.',
Ve='Velora:BAAALgAECgQJBAAAAA==.',
Vi='Vilthrax:BAAALgAECgcJCAAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwAEAAAAAA==.',
Wa='Wadorinramps:BAAALgAECgYJCwABLgAECgkJGwAdALoXAA==.Waffleiron:BAABLgAECn8XAAQJAAYJyyIdIgCDAQAJAAYJyyIdIgCDAQAbAAMJsx6VSwAKAQAIAAQJKRDETgDVAAAAAA==.Watermelon:BAAALgAECggJEAAAAA==.',
Wf='Wforwumbo:BAAALgADCgEJAQAAAA==.',
Wh='Whalaski:BAACLgAFFH8FAAIRAAIJiQwjhQCRAAARAAIJiQwjhQCRAAAuAAQKfy4AAhEACQm6FhcqADYCABEACQm6FhcqADYCAAAA.Whistledown:BAAALgADCgEJAQAAAA==.',
Wi='Wickedsin:BAABLgAECn8bAAIoAAgJGgzGEgAfAQAoAAgJGgzGEgAfAQAAAA==.Windhurst:BAAALgAECgYJBgAAAA==.',
Wo='Woggieboggie:BAAALgAECgkJDAAAAA==.',
Wr='Wreckitman:BAACLgAFFH8WAAIVAAYJ9BM1GACdAQAVAAYJ9BM1GACdAQAuAAQKfx4AAhUACQlYHpoMAPoCABUACQlYHpoMAPoCAAAA.',
Xa='Xaalath:BAABLgAECn8sAAINAAgJqwuaiwBgAQANAAgJqwuaiwBgAQAAAA==.',
Xh='Xhile:BAAALgADCgEJAQAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAIUAAgJSwhvIQBwAQAUAAgJSwhvIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECggJEgAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.Yersn:BAAALgAECgQJBwAAAA==.',
Yo='Yobaz:BAAALgAECgYJBgAAAA==.Yohanan:BAAALgADCgYJBgAAAA==.Yozomi:BAAALgADCgYJCwAAAA==.',
Za='Zappya:BAAALgAECgYJBgAAAA==.Zarorisk:BAAALgAFFAIJAgABLgAFFAUJCAAGAPYUAA==.',
Ze='Zedd:BAAALgAECgEJAgABLgAECgkJIgAFACIZAA==.Zerø:BAAALgADCgcJBgAAAA==.Zetz:BAAALgADCgcJBwAAAA==.Zewse:BAAALgAECgEJAgAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAABLgAECn8cAAIMAAYJ+Bd8EgCbAQAMAAYJ+Bd8EgCbAQAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAABLgAECn8aAAILAAgJXxoUTwD1AQALAAgJXxoUTwD1AQAAAA==.Zorru:BAAALgADCgMJAwAAAA==.',
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
