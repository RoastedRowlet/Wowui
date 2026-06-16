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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Unknown-Unknown','Shaman-Restoration','Druid-Feral','DemonHunter-Havoc','Priest-Shadow','Shaman-Elemental','Paladin-Retribution','Hunter-Survival','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Discipline','Monk-Mistweaver','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Druid-Balance','Monk-Brewmaster','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Priest-Holy','Evoker-Augmentation','Druid-Guardian','Warrior-Fury','Monk-Windwalker','Mage-Arcane','Warrior-Arms','DeathKnight-Blood','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Warlock-Destruction',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Acaval:BAACLgAFFH8KAAMBAAMJLB37FQDRAAACAAMJLB3LjwDnAAABAAMJwRD7FQDRAAAuAAQKfxUAAwIACQm+IXoKABkDAAIACQm+IXoKABkDAAEAAQlrIvItAGMAAAAA.Accursed:BAACLgAFFH8NAAIDAAQJPyXRAQCkAQADAAQJPyXRAQCkAQAuAAQKfyIAAgMACAl6JqsAAFYDAAMACAl6JqsAAFYDAAAA.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.Aduayro:BAAALgADCgQJBAAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Ai='Airpod:BAAALgAECgEJAQABLgAECggJEAAEAAAAAA==.',
Al='Aleighta:BAABLgAECn8cAAIFAAkJBAtuVQBbAQAFAAkJBAtuVQBbAQAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.Alyx:BAAALgAECgIJAgAAAA==.',
Am='Amadia:BAAALgAECgMJBgAAAA==.',
An='Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Anamae:BAABLgAECn8kAAIGAAgJsBHBEwB9AQAGAAgJsBHBEwB9AQAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ao='Aoi:BAAALgADCgcJBwABLgAECgkJGwAHACQVAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgIJAgAAAA==.',
As='Asatrath:BAAALgAECgYJDwAAAA==.Ashkillz:BAABLgAECn8hAAIIAAcJdh+yFgAUAgAIAAcJdh+yFgAUAgAAAA==.Ashtuck:BAAALgAECgYJCQAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAABLgAECn8aAAIJAAkJxw3+LACMAQAJAAkJxw3+LACMAQAAAA==.',
Av='Avenger:BAAALgADCgMJAwABLgAECgYJBQAEAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJCAAAAA==.',
Ba='Badoussi:BAAALgAECgUJDgABLgAECgkJJwAGAAMYAA==.Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgYJBwAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8TAAIKAAYJ9CCDGwCTAQAKAAYJ9CCDGwCTAQAuAAQKfxoAAgoACAn8Ij0RAAYDAAoACAn8Ij0RAAYDAAAA.',
Be='Beansy:BAAALgAECgYJCAAAAA==.Beefomancer:BAAALgAECgQJBAABLgAECgkJNwALADYcAA==.Belan:BAABLgAECn8pAAIMAAkJpRUQOQAyAgAMAAkJpRUQOQAyAgAAAA==.Belladin:BAABLgAECn8gAAIKAAkJ0x/THgCyAgAKAAkJ0x/THgCyAgAAAA==.',
Bl='Blakeshelton:BAAALgAECgIJBAABLgAECggJEAAEAAAAAA==.Blameurself:BAABLgAECn8UAAINAAkJ+x5kIwBAAgANAAkJ+x5kIwBAAgAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECgkJFAANAPseAA==.Blaster:BAAALgAECgEJBgAAAA==.Blite:BAAALgADCgQJDQAAAA==.Bluethain:BAAALgAECggJCQAAAA==.',
Bo='Bombakaap:BAAALgAECgYJCwAAAA==.Bomburst:BAABLgAECn8gAAIOAAgJvxBoEgCLAQAOAAgJvxBoEgCLAQAAAA==.Bonelespizza:BAACLgAFFH8IAAICAAIJOQqFSACTAAACAAIJOQqFSACTAAAuAAQKfzgAAwIACQlhH9sjAK8CAAIACQmHHtsjAK8CAAEABgmKH84MAKcBAAAA.Boogiebabe:BAAALgAECgcJDAAAAA==.Boomhauerr:BAAALgAECgYJBgAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgAECgQJBAAAAA==.Briaris:BAACLgAFFH8OAAILAAQJ6hTwEQA1AQALAAQJ6hTwEQA1AQAuAAQKfyMABAsACAmCHTgIAGsCAAsACAmCHTgIAGsCAA8AAQkuC7Y9ACwAABAAAQkIAvZFASQAAAAA.Bruel:BAAALgADCgUJBQAAAA==.Brugaras:BAAALgADCgQJBAAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
['Bê']='Bêz:BAAALgAECgEJAQAAAA==.',
['Bë']='Bëz:BAABLgAECn83AAIDAAkJ5SJJAQAgAwADAAkJ5SJJAQAgAwAAAA==.',
Ca='Cachinnare:BAAALgAECgUJCgABLgAFFAIJAgAEAAAAAA==.Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Capziesh:BAAALgAECgQJBQAAAA==.Casteel:BAAALgAECggJEAAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgYJBwABLgAFFAcJFwARAOcSAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAABLgAECn8WAAIKAAcJUhGAjgBSAQAKAAcJUhGAjgBSAQAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAABLgAECn8dAAISAAgJbCLGCAALAwASAAgJbCLGCAALAwAAAA==.Cosmicjay:BAECLgAFFH8FAAIJAAMJMBPxMwC3AAAJAAMJMBPxMwC3AAAuAAQKfxgAAgkACAmsIBkTAFICAAkACAmsIBkTAFICAAAA.Cosmicnova:BAEALgAFFAEJAQABLgAFFAMJBQAJADATAA==.Costa:BAAALgAECgMJBAAAAA==.',
Cr='Crentacles:BAABLgAECn8dAAIJAAkJrxbrGgAHAgAJAAkJrxbrGgAHAgAAAA==.Critshade:BAAALgAECgYJDQAAAA==.Crow:BAAALgAFFAUJJAAAAQ==.',
Da='Dadeulus:BAAALgAECgcJDAAAAA==.Daegán:BAAALgAECgEJAQAAAA==.Daffodil:BAABLgAECn8vAAMTAAkJZhGsBgDeAQATAAkJZhGsBgDeAQAUAAMJ2wKdMgBaAAAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgAEAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8VAAIVAAYJHQs1HwBXAQAVAAYJHQs1HwBXAQAuAAQKfyEAAxUACQl+HEkdAFMCABUACQl+HEkdAFMCABYAAQmSA6qfAB8AAAAA.Dantruis:BAAALgAECgEJAQABLgAFFAYJFQAVAB0LAA==.Darkshiver:BAAALgADCgEJAgABLgAECgEJBgAEAAAAAA==.Dawnslight:BAABLgAECn8WAAIKAAcJ3gE/OwFsAAAKAAcJ3gE/OwFsAAAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Dedebop:BAAALgAECgIJBAAAAA==.Deiside:BAAALgADCgkJCQAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAcJGwAXAFgfAA==.Denareyeth:BAAALgAECgUJCwAAAA==.Dephiance:BAAALgAECgcJCAABLgAECgkJKAAIAEEUAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJEAAAAA==.',
Di='Diabla:BAABLgAECn8XAAIYAAYJeCTQFwBTAgAYAAYJeCTQFwBTAgAAAA==.Dinsfirë:BAAALgAECgEJAQAAAA==.Diothorn:BAABLgAECn8kAAMKAAgJ+xiIVwDCAQAKAAcJtxmIVwDCAQAZAAMJ8hTjLAC1AAAAAA==.Disappointed:BAAALgADCggJBwAAAA==.Divanas:BAABLgAECn8bAAIaAAcJUgaUrADqAAAaAAcJUgaUrADqAAAAAA==.Divi:BAABLgAECn8gAAIbAAkJrCHeAwBJAwAbAAkJrCHeAwBJAwAAAA==.',
Do='Doxa:BAAALgADCgMJCAAAAA==.',
Dr='Dragonboi:BAABLgAECn8aAAIcAAkJhxGrJAC2AQAcAAkJhxGrJAC2AQAAAA==.Dreàd:BAAALgAECgEJAQAAAA==.Drpepperz:BAABLgAFFH8FAAIWAAQJqBKuIgAJAQAWAAQJqBKuIgAJAQAAAA==.Drägonwärior:BAAALgAECgEJAQAAAA==.',
Du='Durgan:BAAALgADCgQJBwAAAA==.Durock:BAAALgADCgQJBAABLgAECgkJGwAdALoXAA==.',
Ed='Edging:BAAALgADCgYJBgAAAA==.',
El='Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgAECgEJAQAAAA==.Ellayria:BAAALgAECgYJCgAAAA==.',
Em='Emberrose:BAAALgADCgkJGwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Enhancedpant:BAAALgAECgQJBQAAAA==.Ensetral:BAAALgAECgEJAQAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgcJCwAEAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJCQAAAA==.Evelithillyn:BAAALgAECgQJBQABLgAECgkJFAANAPseAA==.Everydae:BAACLgAFFH8FAAIcAAMJEAssGwCUAAAcAAMJEAssGwCUAAAuAAQKfyYAAhwACQnUHw0MAJgCABwACQnUHw0MAJgCAAAA.',
Ex='Extrajuicy:BAAALgAFFAIJAgAAAA==.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECgkJGgAaAI8YAA==.',
Fa='Fakedruid:BAABLgAECn8UAAIdAAcJliOACQBPAgAdAAcJliOACQBPAgABLgAECgkJNwALADYcAA==.Falarzer:BAAALgADCgIJAgAAAA==.Fatwarlock:BAAALgAECgEJAQAAAA==.',
Fe='Feledris:BAAALgAECgMJAwAAAA==.Feybeasts:BAAALgAECgYJBwAAAA==.Feárbomber:BAAALgAECgQJBAABLgAECggJPAAXACYlAA==.',
Ff='Ffand:BAABLgAECn8WAAIQAAYJ5x/VOADLAQAQAAYJ5x/VOADLAQAAAA==.',
Fh='Fharia:BAAALgAECgUJBgAAAA==.',
Fi='Filafal:BAAALgADCgEJAQABLgAECggJFwACAGUXAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flawless:BAAALgAECgEJAQAAAA==.Flayr:BAAALgADCgkJDQAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fortitude:BAAALgAECgcJCwAAAA==.',
Fu='Fusky:BAABLgAECn8lAAIFAAkJuBKCJwAdAgAFAAkJuBKCJwAdAgAAAA==.',
Fy='Fynn:BAACLgAFFH8NAAIOAAUJkQ32CgANAQAOAAUJkQ32CgANAQAuAAQKfyAAAw4ACAnFFwwLABwCAA4ACAnFFwwLABwCAAUAAQmjAYipACQAAAAA.',
['Fä']='Fätpàndà:BAAALgADCgYJBgAAAA==.',
Ga='Galadria:BAACLgAFFH8PAAIWAAUJWRFGJAAAAQAWAAUJWRFGJAAAAQAuAAQKfxQAAhYACQl0HIAfAMkBABYACQl0HIAfAMkBAAAA.Ganeda:BAAALgAECgcJDAABLgAECgkJGwAdALoXAA==.Garamond:BAAALgADCgEJAQAAAA==.Garchomp:BAAALgAECgcJBgAAAA==.Garrish:BAAALgADCgEJAQAAAA==.',
Ge='Geraldini:BAAALgAECgMJAwAAAA==.Gerwik:BAABLgAECn8sAAIQAAgJtRmiMgANAgAQAAgJtRmiMgANAgAAAA==.',
Gi='Ging:BAABLgAECn8UAAIeAAcJJw+oPQBOAQAeAAcJJw+oPQBOAQAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDQAAAA==.Gogetta:BAAALgAECgEJAQAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goldenlock:BAAALgAECgYJDwAAAA==.Goliather:BAAALgADCgEJAQAAAA==.Govana:BAABLgAECn8ZAAICAAgJoRWOTQDXAQACAAgJoRWOTQDXAQAAAA==.',
Gr='Greenleaves:BAABLgAECn8WAAIfAAgJ8hjDGwDNAQAfAAgJ8hjDGwDNAQAAAA==.Greenpepperz:BAAALgADCgYJBgAAAA==.Gregsh:BAABLgAECn86AAMMAAkJXRfGMgBLAgAMAAkJXRfGMgBLAgAgAAEJ6APUIQAkAAAAAA==.Grimward:BAAALgAECgYJBgAAAA==.Grocrush:BAAALgAECgEJAQAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Guenther:BAAALgAECgEJAQABLgAECgkJIgAFACIZAA==.Gummifishz:BAAALgADCgcJBwAAAA==.Gummiwormz:BAABLgAECn8sAAIYAAkJrx+XBABMAwAYAAkJrx+XBABMAwAAAA==.',
Ha='Hailin:BAABLgAECn8sAAIKAAkJ5xl4PQANAgAKAAkJ5xl4PQANAgAAAA==.Halfheal:BAAALgAECggJDgAAAA==.Halrem:BAAALgAECgIJAgAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8dAAIZAAcJmBqkEAC2AQAZAAcJmBqkEAC2AQAAAA==.',
He='Heherawr:BAAALgADCgMJAwABLgAECgQJCwAEAAAAAA==.Hellman:BAAALgADCgUJCQAAAA==.Hertzabit:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
Hi='Hightroller:BAABLgAECn8vAAIQAAkJehpvHwBnAgAQAAkJehpvHwBnAgAAAA==.Hima:BAABLgAECn8bAAIHAAkJJBVxFADqAQAHAAkJJBVxFADqAQAAAA==.',
Hn='Hnri:BAAALgAECgEJAQAAAA==.',
Ho='Holyjenkins:BAAALgADCgkJDgAAAA==.Holysathh:BAAALgAECgUJDgABLgAECgkJGwAdALoXAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Holystormm:BAAALgAECgQJBQAAAA==.Homulily:BAAALgADCggJGwAAAA==.Hornggry:BAAALgAECgQJAwABLgAECggJGgAXAJ4dAA==.Horngrry:BAAALgAECggJDwABLgAECggJGgAXAJ4dAA==.Horngryer:BAAALgAECgQJBQABLgAECggJGgAXAJ4dAA==.Horngryerr:BAABLgAECn8aAAIXAAgJnh1PJgB5AQAXAAgJnh1PJgB5AQAAAA==.Horngryish:BAAALgADCgEJAQABLgAECggJGgAXAJ4dAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJBQABLgAECgkJNgASABcaAA==.',
Hu='Hulkshe:BAAALgAECgkJCQAAAA==.Huntingpants:BAABLgAECn8eAAIPAAkJRRHPCgC7AQAPAAkJRRHPCgC7AQAAAA==.',
Ic='Icianri:BAAALgAFFAEJAQAAAA==.',
Il='Ilovebagels:BAAALgADCgkJCgAAAA==.',
Im='Imkillho:BAAALgAECgYJDAABLgAECggJGgAXAJ4dAA==.',
In='Inspiredbox:BAAALgAECgcJCQAAAA==.Inverness:BAAALgAECgEJAQAAAA==.',
It='Ithax:BAAALgADCgcJAQAAAA==.Itzuri:BAAALgADCgEJAQAAAA==.',
Ja='Jacobsangle:BAAALgAECgEJAQABLgAECgEJBgAEAAAAAA==.Jankismith:BAABLgAECn84AAISAAgJYxMIKgDUAQASAAgJYxMIKgDUAQAAAA==.Jayy:BAABLgAECn85AAILAAkJ9xTYEAAnAgALAAkJ9xTYEAAnAgAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAkJMwAhAF4kAA==.Jenny:BAABLgAECn8uAAIKAAgJMRqiPgAJAgAKAAgJMRqiPgAJAgAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgcJDwABLgAECgkJEwAEAAAAAA==.Jitoflight:BAAALgAECgYJBgAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgYJDAAAAA==.',
Ju='Jugger:BAAALgAECgEJAQAAAA==.Junieb:BAABLgAECn8eAAIMAAkJHwtojwBVAQAMAAkJHwtojwBVAQAAAA==.',
Ka='Kachiko:BAAALgADCggJIwAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAABLgAECn8VAAIaAAgJOwvUcgBTAQAaAAgJOwvUcgBTAQAAAA==.Kamerth:BAABLgAECn8yAAMRAAkJcwngJQCfAQARAAkJcwngJQCfAQAIAAgJQAlVOAAxAQAAAA==.Kamugi:BAAALgAECgEJAQABLgAFFAQJDwAUAAANAA==.Kapnkrunch:BAAALgAECgUJBQAAAA==.Karluron:BAABLgAECn8mAAIIAAkJuRk9DwBlAgAIAAkJuRk9DwBlAgAAAA==.Karlutros:BAABLgAECn8nAAIIAAkJ/hFUHwDJAQAIAAkJ/hFUHwDJAQAAAA==.Katastrafia:BAAALgAECgMJAwAAAA==.Katimeut:BAAALgAECgQJBAABLgAFFAYJIAAiAAQmAA==.Katowo:BAAALgAFFAEJAQABLgAFFAYJIAAiAAQmAA==.Katuwuagain:BAACLgAFFH8gAAIiAAYJBCaqBgAcAgAiAAYJBCaqBgAcAgAuAAQKfxcAAiIACQk3JrkAAGgDACIACQk3JrkAAGgDAAAA.Kazure:BAABLgAECn8rAAIUAAkJcQ02FACDAQAUAAkJcQ02FACDAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn9GAAIeAAkJ+xKtHgD4AQAeAAkJ+xKtHgD4AQAAAA==.Keniilar:BAAALgAECgEJAQAAAA==.Kenilar:BAAALgAECgEJAwAAAA==.Keybricker:BAAALgAECgcJEAABLgAECgkJNwALADYcAA==.',
Kh='Khaôtic:BAABLgAECn8XAAINAAYJCRkIbABIAQANAAYJCRkIbABIAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgAECgQJBwAAAA==.Kiraeshh:BAABLgAECn8ZAAIMAAcJ/RLkjwBVAQAMAAcJ/RLkjwBVAQAAAA==.Kittykat:BAAALgAECgQJBgAAAA==.',
Ko='Kolonna:BAAALgAECgMJAwAAAA==.Korngry:BAAALgAECgEJAQABLgAECggJGgAXAJ4dAA==.',
Kr='Krakkin:BAAALgAECgQJBwAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgAECgUJBQAAAA==.Krieash:BAAALgADCggJCAAAAA==.Krumpas:BAAALgAECgEJAQABLgAECggJGgAXAJ4dAA==.',
Ky='Kyllea:BAABLgAECn8ZAAIQAAgJhhf9PgDhAQAQAAgJhhf9PgDhAQAAAA==.',
['Kä']='Kätniss:BAAALgAECgYJBgAAAA==.',
La='Laaksy:BAACLgAFFH8MAAMTAAUJLAd7BgDnAAATAAUJ8AR7BgDnAAAcAAMJ9QgNVAB1AAAuAAQKfx4AAhMACAl+ENkLAFIBABMACAl+ENkLAFIBAAAA.Ladraina:BAAALgAECgMJBwAAAA==.Landock:BAAALgADCgYJJgAAAA==.Lavaca:BAABLgAECn8nAAQjAAkJOyMOAgCzAgAkAAgJwSGBCQD5AgAjAAgJKSMOAgCzAgAlAAYJIR/7CQCYAQABLgAFFAMJCgABACwdAA==.',
Le='Lebronjames:BAAALgAECgQJCAABLgAECgEJAQAEAAAAAA==.Legar:BAABLgAECn8bAAIdAAkJuhdKDAAYAgAdAAkJuhdKDAAYAgAAAA==.Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAACLgAFFH8PAAIVAAQJ9Q/wMADlAAAVAAQJ9Q/wMADlAAAuAAQKfysAAhUACQkIEH4/AJEBABUACQkIEH4/AJEBAAAA.Leprechaune:BAAALgAECgMJAwAAAA==.Leticia:BAAALgAECgkJDgAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Liechen:BAAALgAECgYJBgAAAA==.Linaraline:BAAALgADCgUJBQAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgUJEgAAAA==.Lotharmage:BAAALgAECgcJDwAAAA==.Lothlorìan:BAAALgAECgEJAQAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luminescent:BAAALgADCgIJAgAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAFFAEJAQAAAA==.',
Ma='Maelora:BAAALgADCgYJBgAAAA==.Magnessa:BAABLgAECn8XAAIMAAkJhgQkmgBCAQAMAAkJhgQkmgBCAQAAAA==.Malovious:BAAALgADCgkJCQAAAA==.Mandrakethan:BAAALgADCgkJHAAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgAECgEJAQAAAA==.Marist:BAABLgAECn8eAAMFAAkJGhHIWgBIAQAFAAgJfw7IWgBIAQAJAAEJVAUsuQAhAAAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.Maxumuss:BAAALgAECgYJBQAAAA==.',
Me='Medarana:BAAALgAECgEJAQAAAA==.Meliodäs:BAAALgAECgEJAQAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQAEAAAAAA==.Metamorlis:BAAALgAECgQJBAABLgAECgkJPAAbAMwSAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAABLgAECn8jAAImAAYJgx7+FQCTAQAmAAYJgx7+FQCTAQAAAA==.Miku:BAAALgAECgkJDQABLgAECgkJLAAKAOcZAA==.Milent:BAABLgAECn84AAIQAAkJUxoxJABPAgAQAAkJUxoxJABPAgAAAA==.Mimix:BAAALgAECgEJAQAAAA==.Miquiztli:BAAALgAECgkJBQAAAA==.Mizoci:BAAALgAECgEJAgAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJBAAAAA==.',
Mo='Moarteas:BAAALgAECgUJBgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Msspelled:BAABLgAECn8kAAQnAAkJ+RpCBABaAgAnAAkJHhpCBABaAgAaAAUJOg9yuADXAAAoAAIJ/hSfPAA2AAAAAA==.',
Mv='Mvpiam:BAAALgAECgQJDAAAAA==.',
Mx='Mximus:BAAALgAECgIJAQABLgAECgYJBQAEAAAAAA==.',
My='Mystí:BAAALgAECggJDgAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAECgkJSAARAKYjAA==.Nabstarr:BAABLgAECn9IAAQRAAkJpiNpAgCRAwARAAkJpiNpAgCRAwAbAAkJ8hWDEgBHAgAIAAMJdxCqaAB1AAAAAA==.Namtar:BAAALgAECgEJAgAAAA==.Nasroth:BAACLgAFFH8FAAIeAAMJFg9gOADKAAAeAAMJFg9gOADKAAAuAAQKfygAAh4ACAlHEts8ALEBAB4ACAlHEts8ALEBAAAA.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.Natureterror:BAAALgADCgkJGQAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Niibyter:BAABLgAECn8xAAImAAkJbiNJAgAkAwAmAAkJbiNJAgAkAwAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
No='Nowisforever:BAAALgADCgEJAgAAAA==.',
Ny='Nymneria:BAAALgAECgIJAgABLgAECgYJBQAEAAAAAA==.',
Od='Odînson:BAAALgAECgEJAQAAAA==.',
Ol='Oldgreyone:BAABLgAECn8UAAMVAAYJ2RA8bgDnAAAVAAYJ2RA8bgDnAAAWAAYJcgofTQDTAAAAAA==.',
On='Onlyheelz:BAAALgAECgQJBwAAAA==.Onlylocks:BAABLgAECn8mAAMaAAkJbhRSPADpAQAaAAkJmBNSPADpAQAoAAUJFRB2KgAXAQAAAA==.Ontius:BAAALgAECgQJBQAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAABLgAECn8eAAMIAAkJtw9HJgCYAQAIAAkJtw9HJgCYAQAbAAQJRAh8aACLAAAAAA==.',
Or='Orangedrives:BAAALgADCgYJCwAAAA==.Oreeoreo:BAABLgAECn8qAAICAAkJ9Q/6ZgCWAQACAAkJ9Q/6ZgCWAQAAAA==.Orlathil:BAAALgADCgkJCQABLgAECgkJPAAbAMwSAA==.Orlis:BAABLgAECn88AAIbAAkJzBLxGwDjAQAbAAkJzBLxGwDjAQAAAA==.Oroe:BAAALgAECgYJDAAAAA==.',
Pa='Pallydan:BAAALgAECgMJBAABLgAECgkJKQAMAI8WAA==.Pandamunx:BAAALgAECgQJAgAAAA==.',
Pe='Peludita:BAABLgAECn8WAAQVAAcJox0RMwDdAQAVAAcJox0RMwDdAQAWAAcJhBqfJADYAQAdAAEJsCCtKQBUAAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAECgYJCwABLgAECggJDgAEAAAAAA==.',
Ph='Philanthropy:BAABLgAECn8kAAMUAAgJeBmqCwAbAgAUAAgJeBmqCwAbAgAcAAcJlxTTNQBXAQAAAA==.Philtwifdloa:BAAALgADCgEJAQAAAA==.',
Pi='Pitchfiend:BAAALgAECgYJBgAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAFFAQJDgALAOoUAA==.',
Pl='Plumh:BAAALgADCgMJAwAAAA==.Pläze:BAAALgAECgYJEgAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppy:BAAALgAECgkJEwAAAA==.',
Pr='Prayformercy:BAAALgAECgEJAQAAAA==.Praîmfaya:BAAALgAECgQJBQAAAA==.Primeangus:BAAALgAECgkJCQABLgAFFAMJBgAQAFQHAA==.',
Pu='Punchpup:BAABLgAECn8pAAIfAAgJpRPJKQBqAQAfAAgJpRPJKQBqAQAAAA==.',
Py='Pyronorish:BAAALgADCgYJIwAAAA==.Pytthia:BAABLgAECn8oAAMIAAkJQRSAGQD5AQAIAAkJQRSAGQD5AQARAAcJyxJVMgBPAQAAAA==.',
['Pä']='Pändamonium:BAAALgAECgQJBAAAAA==.',
Qu='Quicknclever:BAAALgAECgQJAwAAAA==.Quzbis:BAAALgAECgIJAgAAAA==.',
Ra='Randamonk:BAAALgAECgUJBQAAAA==.Ranraku:BAAALgADCgEJAQAAAA==.Raptalia:BAAALgADCgcJBwABLgAECgkJLAAKAOcZAA==.Raziel:BAABLgAECn8RAAINAAgJSRk+NAAoAgANAAgJSRk+NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQABLgAFFAUJFQAGAA0NAA==.Rectalrazor:BAAALgADCgUJBQAAAA==.Regade:BAAALgAECgEJAgABLgAECgkJKAAIAEEUAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJCQAAAA==.Rem:BAAALgADCgUJCQAAAA==.',
Rh='Rhaena:BAABLgAECn8cAAIKAAgJDQuOoAA0AQAKAAgJDQuOoAA0AQAAAA==.Rhombus:BAABLgAECn85AAIYAAkJPwl/MwCDAQAYAAkJPwl/MwCDAQAAAA==.',
Ri='Rikiriki:BAABLgAECn8YAAMWAAYJuQJjZACFAAAWAAYJuQJjZACFAAAVAAYJFgIpoQBrAAAAAA==.',
Rn='Rndnfluffy:BAAALgAECgEJAgAAAA==.',
Ro='Robok:BAAALgAECgEJAQAAAA==.Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJCAAAAA==.Ronkzar:BAAALgAECgQJBQAAAA==.Rotblossom:BAAALgAECggJEQAAAA==.Rotskar:BAAALgADCggJDAAAAA==.Roxishybrid:BAAALgAECgEJAQAAAA==.',
Rp='Rpgovan:BAAALgAECgQJBAAAAA==.',
Ru='Rubidious:BAAALgAECgMJBQAAAA==.Rukah:BAAALgAECgEJAQAAAA==.Ruth:BAABLgAECn8oAAIcAAkJqg7kJgCpAQAcAAkJqg7kJgCpAQAAAA==.',
['Rô']='Rôflstômp:BAAALgAECgEJAgAAAA==.',
Sa='Sacini:BAAALgADCgYJCgAAAA==.Sakai:BAAALgADCgYJBgAAAA==.Saltydog:BAAALgADCgYJFgAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Saratar:BAAALgAECgMJAwAAAA==.Sarlaana:BAAALgAECgQJBQAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgcJEgAAAA==.',
Sc='Scurge:BAAALgAECgIJAwABLgAECgYJBQAEAAAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Seizo:BAAALgAECgYJDwAAAA==.Selfesteem:BAAALgAECgUJCgABLgAECgkJKQAMAI8WAA==.Setal:BAABLgAECn8+AAMcAAkJ1BxyCwCgAgAcAAkJ1BxyCwCgAgATAAEJIxHfPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAACLgAFFH8NAAIJAAUJrB0iHgAlAQAJAAUJrB0iHgAlAQAuAAQKfyUAAwkACQn2I2sBALIDAAkACQn2I2sBALIDAAUABgkbGOpCAHUBAAAA.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCQAAAA==.Sheenzilla:BAABLgAECn8mAAMcAAkJMgXVQwAXAQAcAAkJMgXVQwAXAQAUAAYJIQGDOACnAAAAAA==.Shelltear:BAAALgADCgYJCAAAAA==.Shelwreth:BAAALgAECgYJDAAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shiro:BAABLgAFFH8IAAISAAMJkAchRQCEAAASAAMJkAchRQCEAAABLgAFFAQJEAAVAHYNAA==.Shoinked:BAABLgAECn83AAIJAAgJaBBmNgBcAQAJAAgJaBBmNgBcAQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgAECgEJAQAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAABLgAECn88AAIXAAgJJiUdBQDuAgAXAAgJJiUdBQDuAgAAAA==.',
Sl='Slak:BAABLgAECn8UAAIgAAkJChHAAwDSAQAgAAkJChHAAwDSAQAAAA==.',
Sm='Smallblades:BAAALgAECgEJAQABLgAECgcJHgAHAMARAA==.Smallchaos:BAABLgAECn8eAAIHAAcJwBG5KgAkAQAHAAcJwBG5KgAkAQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgcJHgAHAMARAA==.Smallêntropy:BAABLgAECn8WAAIDAAgJSA0vDwBYAQADAAgJSA0vDwBYAQAAAA==.Smelt:BAAALgAECgMJDAAAAA==.',
Sn='Snøt:BAAALgADCgcJDAAAAA==.',
So='Sokáar:BAAALgAECgkJAQAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgYJEgABLgAECgkJGgAaAI8YAA==.',
St='Stabbytrout:BAABLgAECn8VAAIkAAkJKheEGgAuAgAkAAkJKheEGgAuAgAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.Stormtalon:BAAALgADCgIJAgAAAA==.',
Su='Sugondis:BAACLgAFFH8IAAIfAAYJtBL9FgAEAQAfAAYJtBL9FgAEAQAuAAQKfxUAAh8ACQn1IXAGABkDAB8ACQn1IXAGABkDAAEuAAUUCQkzACEAXiQA.Sunetra:BAABLgAECn8eAAIKAAkJRQyRggBnAQAKAAkJRQyRggBnAQAAAA==.Sunraku:BAAALgAECgEJAwABLgAECgEJBgAEAAAAAA==.Sunshine:BAABLgAECn8VAAIGAAgJFRZMDgDLAQAGAAgJFRZMDgDLAQAAAA==.Susì:BAAALgADCgIJAgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgcJCAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBwABLgAECgcJCAAEAAAAAA==.',
Ta='Taehyung:BAABLgAECn8WAAIaAAkJEwhffQA9AQAaAAkJEwhffQA9AQAAAA==.Taloki:BAAALgAECgQJBgAAAA==.Tangir:BAAALgAECgUJBQAAAA==.Tatavete:BAAALgADCgUJBQAAAA==.Tatsuhisa:BAAALgAECggJDQAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAABLgAECn8tAAMJAAgJXgXzUgDoAAAJAAgJXgXzUgDoAAAFAAUJAAUylgCiAAAAAA==.',
Th='Thallyn:BAAALgAECgcJBwAAAA==.',
Ti='Tinny:BAAALgAECgMJCAAAAA==.Tippshunter:BAABLgAECn83AAILAAkJNhxuCACXAgALAAkJNhxuCACXAgAAAA==.',
To='Tognuwa:BAAALgAECgEJAQAAAA==.Tonguefu:BAAALgAECgEJAQAAAA==.Tonton:BAAALgAECgEJAQAAAA==.Toph:BAACLgAFFH8KAAMTAAQJihhcBAAlAQATAAQJshZcBAAlAQAcAAEJFyHyHgBbAAAuAAQKfyEABBMACQmwIVQJAEwCABMABwkqIVQJAEwCABwAAwlgHhpkAKkAABQAAwljBE89AIAAAAAA.Tophdh:BAABLgAECn8fAAIDAAkJfSK6AQD/AgADAAkJfSK6AQD/AgABLgAFFAQJCgATAIoYAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECgkJLwAXAP4WAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECgkJLwAXAP4WAA==.Tryit:BAAALgAECgQJBAABLgAECgkJLwAXAP4WAA==.Trythefox:BAABLgAECn8vAAIXAAkJ/hYcGQDbAQAXAAkJ/hYcGQDbAQAAAA==.',
Ts='Tseris:BAAALgAECgUJDwAAAA==.Tsukihana:BAAALgAECgUJDQAAAA==.',
Tu='Tuini:BAABLgAECn8iAAMFAAkJIhnVGgBxAgAFAAkJIhnVGgBxAgAJAAUJtAzAYQC7AAAAAA==.',
Ty='Tydis:BAABLgAECn82AAIKAAgJnQ4CfwBuAQAKAAgJnQ4CfwBuAQAAAA==.',
['Tá']='Tálonstorm:BAABLgAECn88AAIhAAgJsAd5MAACAQAhAAgJsAd5MAACAQAAAA==.',
Ul='Ultra:BAAALgAECgMJBQAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.Untamed:BAAALgADCgkJCwAAAA==.',
Va='Vaehunt:BAEALgADCgMJBAABLgAFFAYJEAANAHgTAA==.Vaesar:BAEALgADCgUJBgABLgAFFAYJEAANAHgTAA==.Vaesara:BAECLgAFFH8QAAINAAYJeBMYMABcAQANAAYJeBMYMABcAQAuAAQKfy0AAg0ACQmBIUIKAPYCAA0ACQmBIUIKAPYCAAAA.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Valynaria:BAAALgAECgEJAQAAAA==.Vani:BAABLgAECn8dAAIbAAgJaQ1NMABJAQAbAAgJaQ1NMABJAQAAAA==.',
Ve='Velora:BAAALgAECgQJBAAAAA==.',
Vi='Vilthrax:BAAALgAECgYJBgAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwAEAAAAAA==.',
Wa='Wadorinramps:BAAALgAECgYJCwABLgAECgkJGwAdALoXAA==.Waffleiron:BAABLgAECn8XAAQRAAYJyyIdIgCDAQARAAYJyyIdIgCDAQAbAAMJsx6VSwAKAQAIAAQJKRBHTQDXAAAAAA==.Watermelon:BAAALgAECggJEAAAAA==.',
Wf='Wforwumbo:BAAALgADCgEJAQAAAA==.',
Wh='Whalaski:BAACLgAFFH8FAAIQAAIJiQznfwCRAAAQAAIJiQznfwCRAAAuAAQKfy4AAhAACQm6FgYpADYCABAACQm6FgYpADYCAAAA.Whistledown:BAAALgADCgEJAQAAAA==.',
Wi='Wickedsin:BAABLgAECn8bAAIoAAgJGgxREgAgAQAoAAgJGgxREgAgAQAAAA==.Windhurst:BAAALgAECgYJBgAAAA==.',
Wo='Woggieboggie:BAAALgAECgkJDAAAAA==.',
Wr='Wreckitman:BAACLgAFFH8WAAIVAAYJ9BMTFwCfAQAVAAYJ9BMTFwCfAQAuAAQKfx4AAhUACQlYHmMMAPoCABUACQlYHmMMAPoCAAAA.',
Xa='Xaalath:BAABLgAECn8oAAIMAAgJHQlXmQBDAQAMAAgJHQlXmQBDAQAAAA==.',
Xh='Xhile:BAAALgADCgEJAQAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAIUAAgJSwhvIQBwAQAUAAgJSwhvIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECggJEgAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.Yersn:BAAALgAECgQJBwAAAA==.',
Yo='Yobaz:BAAALgADCgYJFQAAAA==.Yohanan:BAAALgADCgYJBgAAAA==.Yozomi:BAAALgADCgQJBQAAAA==.',
Za='Zappya:BAAALgAECgYJBgAAAA==.Zarorisk:BAAALgAECgcJEAABLgAECgkJJwAGAAMYAA==.',
Ze='Zedd:BAAALgAECgEJAQABLgAECgkJIgAFACIZAA==.Zerø:BAAALgADCgcJBgAAAA==.Zetz:BAAALgADCgcJBwAAAA==.Zewse:BAAALgAECgEJAgAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAABLgAECn8cAAILAAYJ+Bd8EgCbAQALAAYJ+Bd8EgCbAQAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAABLgAECn8aAAIKAAgJXxoUTwD1AQAKAAgJXxoUTwD1AQAAAA==.',
Zu='Zuesb:BAAALgADCgUJBgAAAA==.',
Zy='Zyvidria:BAABLgAECn8aAAITAAgJ8xTTBwC3AQATAAgJ8xTTBwC3AQAAAA==.',
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
