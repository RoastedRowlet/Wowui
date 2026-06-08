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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Unknown-Unknown','Shaman-Restoration','Druid-Feral','DemonHunter-Havoc','Priest-Shadow','Shaman-Elemental','Paladin-Retribution','Hunter-Survival','Mage-Frost','DemonHunter-Devourer','Shaman-Enhancement','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Discipline','Monk-Mistweaver','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Druid-Balance','Monk-Brewmaster','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Priest-Holy','Evoker-Augmentation','Druid-Guardian','Monk-Windwalker','Mage-Arcane','Warrior-Arms','DeathKnight-Blood','Warrior-Fury','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Warlock-Destruction',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Acaval:BAACLgAFFH8KAAMBAAMJLB1PEwDSAAACAAMJLB3vggDvAAABAAMJwRBPEwDSAAAuAAQKfxQAAwIACQm+IZ4JABwDAAIACQm+IZ4JABwDAAEAAQlrIvgqAGQAAAAA.Accursed:BAACLgAFFH8NAAIDAAQJPyWPAQCnAQADAAQJPyWPAQCnAQAuAAQKfyIAAgMACAl6JqsAAFYDAAMACAl6JqsAAFYDAAAA.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.Aduayro:BAAALgADCgQJBAAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Ai='Airpod:BAAALgAECgEJAQABLgAECggJEAAEAAAAAA==.',
Al='Aleighta:BAABLgAECn8cAAIFAAkJBAtZUgBbAQAFAAkJBAtZUgBbAQAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.Alyx:BAAALgAECgIJAgAAAA==.',
Am='Amadia:BAAALgAECgMJBgAAAA==.',
An='Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Anamae:BAABLgAECn8eAAIGAAgJgQ2PFwBDAQAGAAgJgQ2PFwBDAQAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ao='Aoi:BAAALgADCgcJBwABLgAECggJGgAHAJMVAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgIJAgAAAA==.',
As='Asatrath:BAAALgAECgYJDwAAAA==.Ashkillz:BAABLgAECn8hAAIIAAcJdh+ZFQAXAgAIAAcJdh+ZFQAXAgAAAA==.Ashtuck:BAAALgAECgYJCQAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAABLgAECn8XAAIJAAkJxw0FKwCNAQAJAAkJxw0FKwCNAQAAAA==.',
Av='Avenger:BAAALgADCgMJAwABLgAECgYJBQAEAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJCAAAAA==.',
Ba='Badoussi:BAAALgAECgUJDQABLgAECgkJJwAGAAMYAA==.Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgQJBQAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8TAAIKAAYJ9CBhFgCaAQAKAAYJ9CBhFgCaAQAuAAQKfxoAAgoACAn8Ij0RAAYDAAoACAn8Ij0RAAYDAAAA.',
Be='Beansy:BAAALgAECgIJAgAAAA==.Beefomancer:BAAALgAECgQJBAABLgAECgkJNgALADYcAA==.Belan:BAABLgAECn8jAAIMAAkJ7RQLPQAgAgAMAAkJ7RQLPQAgAgAAAA==.Belladin:BAABLgAECn8gAAIKAAkJ0x/THgCyAgAKAAkJ0x/THgCyAgAAAA==.',
Bl='Blakeshelton:BAAALgAECgIJBAABLgAECggJEAAEAAAAAA==.Blameurself:BAABLgAECn8UAAINAAkJ+x7SIQBAAgANAAkJ+x7SIQBAAgAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECgkJFAANAPseAA==.Blaster:BAAALgAECgEJBgAAAA==.Blite:BAAALgADCgQJDQAAAA==.Bluethain:BAAALgAECgcJCAAAAA==.',
Bo='Bombakaap:BAAALgAECgYJCwAAAA==.Bomburst:BAABLgAECn8gAAIOAAgJvxCHEQCNAQAOAAgJvxCHEQCNAQAAAA==.Bonelespizza:BAACLgAFFH8IAAICAAIJOQqFSACTAAACAAIJOQqFSACTAAAuAAQKfzgAAwIACQlhH9sjAK8CAAIACQmHHtsjAK8CAAEABgmKH/ALAKkBAAAA.Boogiebabe:BAAALgAECgcJCwAAAA==.Boomhauerr:BAAALgAECgYJBgAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgAECgQJBAAAAA==.Briaris:BAACLgAFFH8NAAILAAQJchPbEAAzAQALAAQJchPbEAAzAQAuAAQKfyMABAsACAmCHTgIAGsCAAsACAmCHTgIAGsCAA8AAQkuC8A7ACwAABAAAQkIAkI3ASYAAAAA.Bruel:BAAALgADCgUJBQAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
['Bê']='Bêz:BAAALgAECgEJAQAAAA==.',
['Bë']='Bëz:BAABLgAECn8vAAIDAAgJ5yIBAwCuAgADAAgJ5yIBAwCuAgAAAA==.',
Ca='Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Capziesh:BAAALgAECgQJBQAAAA==.Casteel:BAAALgAECggJEAAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgYJBwABLgAFFAYJFgARAKMTAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAABLgAECn8WAAIKAAcJUhHshwBVAQAKAAcJUhHshwBVAQAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAABLgAECn8cAAISAAgJ/yGkCAABAwASAAgJ/yGkCAABAwAAAA==.Cosmicjay:BAECLgAFFH8FAAIJAAMJMBOoLwDDAAAJAAMJMBOoLwDDAAAuAAQKfxgAAgkACAmsIPcRAFQCAAkACAmsIPcRAFQCAAAA.Cosmicnova:BAEALgAFFAEJAQABLgAFFAMJBQAJADATAA==.Costa:BAAALgAECgMJBAAAAA==.',
Cr='Crentacles:BAABLgAECn8dAAIJAAkJrxalGQAHAgAJAAkJrxalGQAHAgAAAA==.Critshade:BAAALgAECgYJDQAAAA==.Crow:BAAALgAFFAUJJAAAAQ==.',
Da='Dadeulus:BAAALgAECgcJDAAAAA==.Daegán:BAAALgAECgEJAQAAAA==.Daffodil:BAABLgAECn8nAAMTAAgJ6BFuCACfAQATAAgJ6BFuCACfAQAUAAMJ2wLMMABdAAAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgAEAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8VAAIVAAYJHQuQGwBtAQAVAAYJHQuQGwBtAQAuAAQKfyEAAxUACQl+HEkdAFMCABUACQl+HEkdAFMCABYAAQmSA9mZAB8AAAAA.Dantruis:BAAALgAECgEJAQABLgAFFAYJFQAVAB0LAA==.Darkshiver:BAAALgADCgEJAgABLgAECgEJBgAEAAAAAA==.Dawnslight:BAABLgAECn8VAAIKAAcJ2QHQMgFpAAAKAAcJ2QHQMgFpAAAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Dedebop:BAAALgAECgIJBAAAAA==.Deiside:BAAALgADCgkJCQAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAcJGgAXAFgfAA==.Denareyeth:BAAALgAECgUJCwAAAA==.Dephiance:BAAALgAECgcJCAABLgAECgkJKAAIAEEUAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJEAAAAA==.',
Di='Diabla:BAABLgAECn8XAAIYAAYJeCTQFwBTAgAYAAYJeCTQFwBTAgAAAA==.Dinsfirë:BAAALgAECgEJAQAAAA==.Diothorn:BAABLgAECn8jAAMKAAgJ2BijVADBAQAKAAcJjhmjVADBAQAZAAMJ8hQnKwC2AAAAAA==.Disappointed:BAAALgADCggJBwAAAA==.Divanas:BAABLgAECn8XAAIaAAYJ/gVnxAC+AAAaAAYJ/gVnxAC+AAAAAA==.Divi:BAABLgAECn8fAAIbAAgJGiMbBgAKAwAbAAgJGiMbBgAKAwAAAA==.',
Do='Doxa:BAAALgADCgMJBQAAAA==.',
Dr='Dragonboi:BAABLgAECn8ZAAIcAAgJgBBZMABsAQAcAAgJgBBZMABsAQAAAA==.Dreàd:BAAALgAECgEJAQAAAA==.Drpepperz:BAAALgAFFAIJAgAAAA==.Drägonwärior:BAAALgAECgEJAQAAAA==.',
Du='Durgan:BAAALgADCgQJBwAAAA==.Durock:BAAALgADCgQJBAABLgAECgkJGwAdALoXAA==.',
Dy='Dymondsmashr:BAABLgAECn8xAAIYAAgJswkhOgBWAQAYAAgJswkhOgBWAQAAAA==.',
El='Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgAECgEJAQAAAA==.Ellayria:BAAALgAECgYJCgAAAA==.',
Em='Emberrose:BAAALgADCgkJEwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Enhancedpant:BAAALgAECgQJBAAAAA==.Ensetral:BAAALgADCgQJBAAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgcJCwAEAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJCQAAAA==.Evelithillyn:BAAALgAECgQJBQABLgAECgkJFAANAPseAA==.Everydae:BAACLgAFFH8FAAIcAAMJEAssGwCUAAAcAAMJEAssGwCUAAAuAAQKfyYAAhwACQnUH30LAJoCABwACQnUH30LAJoCAAAA.',
Ex='Extrajuicy:BAAALgAFFAEJAQAAAA==.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECgkJGgAaAI8YAA==.',
Fa='Fakedruid:BAAALgAECgcJDgABLgAECgkJNgALADYcAA==.Falarzer:BAAALgADCgIJAgAAAA==.Fatwarlock:BAAALgAECgEJAQAAAA==.',
Fe='Feledris:BAAALgAECgMJAwAAAA==.Feybeasts:BAAALgAECgYJBwAAAA==.Feárbomber:BAAALgAECgQJBAABLgAECggJNgAXAOQkAA==.',
Ff='Ffand:BAABLgAECn8WAAIQAAYJ5x/VOADLAQAQAAYJ5x/VOADLAQAAAA==.',
Fh='Fharia:BAAALgAECgEJAQAAAA==.',
Fi='Filafal:BAAALgADCgEJAQABLgAECggJFwACAGUXAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flawless:BAAALgAECgEJAQAAAA==.Flayr:BAAALgADCgkJDQAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fortitude:BAAALgAECgcJCwAAAA==.',
Fu='Fusky:BAABLgAECn8lAAIFAAkJuBKwJQAeAgAFAAkJuBKwJQAeAgAAAA==.',
Fy='Fynn:BAACLgAFFH8NAAIOAAUJkQ2XCQAUAQAOAAUJkQ2XCQAUAQAuAAQKfyAAAw4ACAnFFwwLABwCAA4ACAnFFwwLABwCAAUAAQmjAYipACQAAAAA.',
Ga='Galadria:BAABLgAFFH8OAAIWAAUJWRFqIQADAQAWAAUJWRFqIQADAQAAAA==.Ganeda:BAAALgAECgcJDAABLgAECgkJGwAdALoXAA==.Garamond:BAAALgADCgEJAQAAAA==.Garchomp:BAAALgAECgcJBgAAAA==.Garrish:BAAALgADCgEJAQAAAA==.',
Ge='Geraldini:BAAALgAECgMJAwAAAA==.Gerwik:BAABLgAECn8pAAIQAAgJ5Bh7OQDtAQAQAAgJ5Bh7OQDtAQAAAA==.',
Gi='Ging:BAAALgAECgcJEgAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDQAAAA==.Gogetta:BAAALgAECgEJAQAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goldenlock:BAAALgAECgYJDwAAAA==.Goliather:BAAALgADCgEJAQAAAA==.Govana:BAAALgAECgcJEwAAAA==.',
Gr='Greenleaves:BAABLgAECn8WAAIeAAgJ8hioGgDOAQAeAAgJ8hioGgDOAQAAAA==.Greenpepperz:BAAALgADCgYJBgAAAA==.Gregsh:BAABLgAECn8zAAMMAAkJNxb9NAA+AgAMAAkJNxb9NAA+AgAfAAEJ6APUIQAkAAAAAA==.Grimward:BAAALgAECgYJBgAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Gummifishz:BAAALgADCgcJBwAAAA==.Gummiwormz:BAABLgAECn8nAAIYAAgJzR6MCQDoAgAYAAgJzR6MCQDoAgAAAA==.',
Ha='Hailin:BAABLgAECn8sAAIKAAkJ5xlNOgAPAgAKAAkJ5xlNOgAPAgAAAA==.Halfheal:BAAALgAECggJDgAAAA==.Halrem:BAAALgAECgIJAgAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8cAAIZAAcJmBrzDwC3AQAZAAcJmBrzDwC3AQAAAA==.',
He='Heherawr:BAAALgADCgMJAwABLgAECgQJCwAEAAAAAA==.Hellman:BAAALgADCgUJCQAAAA==.Hertzabit:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
Hi='Hightroller:BAABLgAECn8vAAIQAAkJehriHABtAgAQAAkJehriHABtAgAAAA==.Hima:BAABLgAECn8aAAIHAAgJkxXFGACrAQAHAAgJkxXFGACrAQAAAA==.',
Ho='Holyjenkins:BAAALgADCgkJDgAAAA==.Holysathh:BAAALgAECgUJDgABLgAECgkJGwAdALoXAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Holystormm:BAAALgAECgQJBAAAAA==.Homulily:BAAALgADCggJGwAAAA==.Hornggry:BAAALgAECgQJAwABLgAECggJGgAXAJ4dAA==.Horngrry:BAAALgAECgcJDQABLgAECggJGgAXAJ4dAA==.Horngryer:BAAALgAECgQJBQABLgAECggJGgAXAJ4dAA==.Horngryerr:BAABLgAECn8aAAIXAAgJnh1HJQB6AQAXAAgJnh1HJQB6AQAAAA==.Horngryish:BAAALgADCgEJAQABLgAECggJGgAXAJ4dAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJBQABLgAECggJNAASAMgaAA==.',
Hu='Hulkshe:BAAALgAECgkJCQAAAA==.Huntingpants:BAABLgAECn8eAAIPAAkJRRFBCgC/AQAPAAkJRRFBCgC/AQAAAA==.',
Ic='Icianri:BAAALgAFFAEJAQAAAA==.',
Il='Ilovebagels:BAAALgADCgYJBgAAAA==.',
Im='Imkillho:BAAALgAECgQJBwABLgAECggJGgAXAJ4dAA==.',
In='Inspiredbox:BAAALgAECgMJBAAAAA==.Inverness:BAAALgAECgEJAQAAAA==.',
It='Ithax:BAAALgADCgcJAQAAAA==.',
Ja='Jacobsangle:BAAALgAECgEJAQABLgAECgEJBgAEAAAAAA==.Jankismith:BAABLgAECn8yAAISAAgJUhH4LgCpAQASAAgJUhH4LgCpAQAAAA==.Jayy:BAABLgAECn8xAAILAAgJPhKlGgDEAQALAAgJPhKlGgDEAQAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAkJMQAgAF4kAA==.Jenny:BAABLgAECn8uAAIKAAgJMRo1OwAMAgAKAAgJMRo1OwAMAgAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgcJDwABLgAECgkJEwAEAAAAAA==.Jitoflight:BAAALgAECgYJBgAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgYJDAAAAA==.',
Ju='Jugger:BAAALgAECgEJAQAAAA==.Junieb:BAABLgAECn8eAAIMAAkJHwtCiABgAQAMAAkJHwtCiABgAQAAAA==.',
Ka='Kachiko:BAAALgADCggJGQAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAABLgAECn8VAAIaAAgJOwuIbgBZAQAaAAgJOwuIbgBZAQAAAA==.Kamerth:BAABLgAECn8qAAMRAAgJRggLLgBcAQARAAgJRggLLgBcAQAIAAgJQAkSNQA6AQAAAA==.Kamugi:BAAALgADCgMJAwABLgAFFAMJCgAUAMEQAA==.Kapnkrunch:BAAALgAECgUJBQAAAA==.Karluron:BAABLgAECn8gAAIIAAkJohl5DgBpAgAIAAkJohl5DgBpAgAAAA==.Karlutros:BAABLgAECn8nAAIIAAkJ/hHOHQDPAQAIAAkJ/hHOHQDPAQAAAA==.Katastrafia:BAAALgAECgMJAwAAAA==.Katimeut:BAAALgAECgQJBAABLgAFFAYJGwAhAAQmAA==.Katowo:BAAALgAECgQJCQABLgAFFAYJGwAhAAQmAA==.Katuwuagain:BAACLgAFFH8bAAIhAAYJBCa3BQAaAgAhAAYJBCa3BQAaAgAuAAQKfxcAAiEACQk3JqAAAGwDACEACQk3JqAAAGwDAAAA.Kazure:BAABLgAECn8rAAIUAAkJcQ06EwCNAQAUAAkJcQ06EwCNAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn9GAAIiAAkJ+xIqHQD+AQAiAAkJ+xIqHQD+AQAAAA==.Keniilar:BAAALgAECgEJAQAAAA==.Kenilar:BAAALgAECgEJAgAAAA==.Keybricker:BAAALgAECgcJEAABLgAECgkJNgALADYcAA==.',
Kh='Khaôtic:BAABLgAECn8XAAINAAYJCRmSaABIAQANAAYJCRmSaABIAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgAECgQJBwAAAA==.Kiraeshh:BAABLgAECn8ZAAIMAAcJ/RLCiwBaAQAMAAcJ/RLCiwBaAQAAAA==.Kittykat:BAAALgAECgQJBgAAAA==.',
Ko='Kolonna:BAAALgAECgMJAwAAAA==.Korngry:BAAALgAECgEJAQABLgAECggJGgAXAJ4dAA==.',
Kr='Krakkin:BAAALgAECgEJAQAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgADCgYJIgAAAA==.Krieash:BAAALgADCggJCAAAAA==.Krumpas:BAAALgAECgEJAQABLgAECggJGgAXAJ4dAA==.',
Ky='Kyllea:BAABLgAECn8ZAAIQAAgJhhcKOwDoAQAQAAgJhhcKOwDoAQAAAA==.',
['Kä']='Kätniss:BAAALgAECgYJBgAAAA==.',
La='Laaksy:BAACLgAFFH8MAAMTAAUJLAftBQDwAAATAAUJ8ATtBQDwAAAcAAMJ9QhbUAB2AAAuAAQKfx4AAhMACAl+EGkLAFMBABMACAl+EGkLAFMBAAAA.Ladraina:BAAALgAECgIJBAAAAA==.Landock:BAAALgADCgYJIwAAAA==.Lavaca:BAABLgAECn8nAAQjAAkJOyPyAQCzAgAkAAgJwSGBCQD5AgAjAAgJKSPyAQCzAgAlAAYJIR+cCQCaAQABLgAFFAMJCgABACwdAA==.',
Le='Legar:BAABLgAECn8bAAIdAAkJuheCCwAYAgAdAAkJuheCCwAYAgAAAA==.Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAACLgAFFH8PAAIVAAQJ9Q/+LAD5AAAVAAQJ9Q/+LAD5AAAuAAQKfysAAhUACQkIEJQ9AJMBABUACQkIEJQ9AJMBAAAA.Leprechaune:BAAALgAECgMJAwAAAA==.Leticia:BAAALgAECgkJDgAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Liechen:BAAALgAECgYJBgAAAA==.Linaraline:BAAALgADCgUJBQAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgUJEAAAAA==.Lotharmage:BAAALgAECgcJDwAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luminescent:BAAALgADCgIJAgAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAFFAEJAQAAAA==.',
Ma='Maelora:BAAALgADCgYJBgAAAA==.Magnessa:BAABLgAECn8XAAIMAAkJhgSZlABKAQAMAAkJhgSZlABKAQAAAA==.Malovious:BAAALgADCgkJCQAAAA==.Mandrakethan:BAAALgADCgkJHAAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgAECgEJAQAAAA==.Marist:BAABLgAECn8eAAMFAAkJGhFnVwBIAQAFAAgJfw5nVwBIAQAJAAEJVAWusAAhAAAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.Maxumuss:BAAALgAECgYJBQAAAA==.',
Me='Medarana:BAAALgAECgEJAQAAAA==.Meliodäs:BAAALgAECgEJAQAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQAEAAAAAA==.Metamorlis:BAAALgAECgQJBAABLgAECgkJNAAbAMwSAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAABLgAECn8jAAImAAYJgx78FACWAQAmAAYJgx78FACWAQAAAA==.Miku:BAAALgAECgkJDQABLgAECgkJLAAKAOcZAA==.Milent:BAABLgAECn8xAAIQAAgJMxhfOwDmAQAQAAgJMxhfOwDmAQAAAA==.Mimix:BAAALgAECgEJAQAAAA==.Miquiztli:BAAALgAECgkJBQAAAA==.Mizoci:BAAALgAECgEJAgAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJBAAAAA==.',
Mo='Moarteas:BAAALgAECgUJBgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Msspelled:BAABLgAECn8iAAQnAAgJoxm2CADKAQAnAAcJixu2CADKAQAaAAUJOg9JsgDcAAAoAAIJ/hRlOgA2AAAAAA==.',
Mv='Mvpiam:BAAALgAECgQJDAAAAA==.',
Mx='Mximus:BAAALgAECgIJAQABLgAECgYJBQAEAAAAAA==.',
My='Mystí:BAAALgAECggJDgAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAECgkJQAARAOwiAA==.Nabstarr:BAABLgAECn9AAAQRAAkJ7CLsAgB2AwARAAkJ7CLsAgB2AwAbAAkJ8hV1EQBJAgAIAAEJAAYPigAoAAAAAA==.Namtar:BAAALgAECgEJAgAAAA==.Nasroth:BAACLgAFFH8FAAIiAAMJFg94NADKAAAiAAMJFg94NADKAAAuAAQKfygAAiIACAlHEts8ALEBACIACAlHEts8ALEBAAAA.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.Natureterror:BAAALgADCggJEQAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Niibyter:BAABLgAECn8qAAImAAgJZCI8BgChAgAmAAgJZCI8BgChAgAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
No='Nowisforever:BAAALgADCgEJAgAAAA==.',
Ny='Nymneria:BAAALgAECgIJAgABLgAECgYJBQAEAAAAAA==.',
Od='Odînson:BAAALgAECgEJAQAAAA==.',
Ol='Oldgreyone:BAABLgAECn8UAAMVAAYJ2RD0awDnAAAVAAYJ2RD0awDnAAAWAAYJcgpHSgDUAAAAAA==.',
On='Onlyheelz:BAAALgAECgQJBwAAAA==.Onlylocks:BAABLgAECn8mAAMaAAkJbhSUOQDuAQAaAAkJmBOUOQDuAQAoAAUJFRB2KgAXAQAAAA==.Ontius:BAAALgAECgQJBQAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAABLgAECn8eAAMIAAkJtw8SJQCaAQAIAAkJtw8SJQCaAQAbAAQJRAh8aACLAAAAAA==.',
Or='Orangedrives:BAAALgADCgYJCwAAAA==.Oreeoreo:BAABLgAECn8kAAICAAkJ9Q/2YwCYAQACAAkJ9Q/2YwCYAQAAAA==.Orlathil:BAAALgADCgkJCQABLgAECgkJNAAbAMwSAA==.Orlis:BAABLgAECn80AAIbAAkJzBI/GwDfAQAbAAkJzBI/GwDfAQAAAA==.Oroe:BAAALgAECgYJDAAAAA==.',
Pa='Pallydan:BAAALgAECgMJBAABLgAECgkJKQAMAI8WAA==.Pandamunx:BAAALgAECgMJAQAAAA==.',
Pe='Peludita:BAABLgAECn8WAAQVAAcJox0RMwDdAQAVAAcJox0RMwDdAQAWAAcJhBqfJADYAQAdAAEJsCCtKQBUAAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAECgYJCwABLgAECggJDgAEAAAAAA==.',
Ph='Philanthropy:BAABLgAECn8kAAMUAAgJeBlRCwAeAgAUAAgJeBlRCwAeAgAcAAcJlxToMwBYAQAAAA==.Philtwifdloa:BAAALgADCgEJAQAAAA==.',
Pi='Pitchfiend:BAAALgAECgYJBgAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAFFAQJDQALAHITAA==.',
Pl='Plumh:BAAALgADCgMJAwAAAA==.Pläze:BAAALgAECgYJEgAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppy:BAAALgAECgkJEwAAAA==.',
Pr='Prayformercy:BAAALgAECgEJAQAAAA==.Praîmfaya:BAAALgAECgQJBQAAAA==.Primeangus:BAAALgAECgkJCQAAAA==.',
Pu='Punchpup:BAABLgAECn8pAAIeAAgJpROMJwBuAQAeAAgJpROMJwBuAQAAAA==.',
Py='Pyronorish:BAAALgADCgYJHgAAAA==.Pytthia:BAABLgAECn8oAAMIAAkJQRR3GAD8AQAIAAkJQRR3GAD8AQARAAcJyxLoLwBRAQAAAA==.',
['Pä']='Pändamonium:BAAALgAECgQJBAAAAA==.',
Qu='Quicknclever:BAAALgAECgQJAwAAAA==.Quzbis:BAAALgAECgEJAQAAAA==.',
Ra='Randamonk:BAAALgAECgUJBQAAAA==.Ranraku:BAAALgADCgEJAQAAAA==.Raptalia:BAAALgADCgcJBwABLgAECgkJLAAKAOcZAA==.Raziel:BAABLgAECn8RAAINAAgJSRk+NAAoAgANAAgJSRk+NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQABLgAFFAUJFQAGAA0NAA==.Regade:BAAALgAECgEJAgABLgAECgkJKAAIAEEUAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJCQAAAA==.Rem:BAAALgADCgUJCQAAAA==.',
Rh='Rhaena:BAABLgAECn8cAAIKAAgJDQu0mQA2AQAKAAgJDQu0mQA2AQAAAA==.',
Ri='Rikiriki:BAABLgAECn8YAAMWAAYJuQLNYACGAAAWAAYJuQLNYACGAAAVAAYJFgK1nQBrAAAAAA==.',
Rn='Rndnfluffy:BAAALgAECgEJAgAAAA==.',
Ro='Robok:BAAALgAECgEJAQAAAA==.Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJCAAAAA==.Ronkzar:BAAALgAECgMJBAAAAA==.Rotblossom:BAAALgAECggJDwAAAA==.Rotskar:BAAALgADCggJDAAAAA==.Roxishybrid:BAAALgAECgEJAQAAAA==.',
Rp='Rpgovan:BAAALgAECgQJBAAAAA==.',
Ru='Rubidious:BAAALgAECgEJAgAAAA==.Ruth:BAABLgAECn8oAAIcAAkJqg43JQCsAQAcAAkJqg43JQCsAQAAAA==.',
['Rô']='Rôflstômp:BAAALgAECgEJAgAAAA==.',
Sa='Sacini:BAAALgADCgYJCgAAAA==.Sakai:BAAALgADCgYJBgAAAA==.Saltydog:BAAALgADCgYJEQAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Saratar:BAAALgAECgMJAwAAAA==.Sarlaana:BAAALgAECgQJBQAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgcJEgAAAA==.',
Sc='Scurge:BAAALgAECgIJAwABLgAECgYJBQAEAAAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Seizo:BAAALgAECgYJDwAAAA==.Selfesteem:BAAALgAECgEJAQABLgAECgkJKQAMAI8WAA==.Setal:BAABLgAECn8+AAMcAAkJ1Bz/CgChAgAcAAkJ1Bz/CgChAgATAAEJIxHfPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAACLgAFFH8NAAIJAAUJrB33GgAuAQAJAAUJrB33GgAuAQAuAAQKfyUAAwkACQn2I2sBALIDAAkACQn2I2sBALIDAAUABgkbGOpCAHUBAAAA.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCQAAAA==.Sheenzilla:BAABLgAECn8mAAMcAAkJMgXxQAAbAQAcAAkJMgXxQAAbAQAUAAYJIQGDOACnAAAAAA==.Shelltear:BAAALgADCgYJCAAAAA==.Shelwreth:BAAALgAECgYJDAAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shiro:BAABLgAFFH8IAAISAAMJkAevPQCMAAASAAMJkAevPQCMAAABLgAFFAQJEAAVAHYNAA==.Shoinked:BAABLgAECn83AAIJAAgJaBAENABdAQAJAAgJaBAENABdAQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgAECgEJAQAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAABLgAECn82AAIXAAgJ5CQtBQDoAgAXAAgJ5CQtBQDoAgAAAA==.',
Sl='Slak:BAABLgAECn8UAAIfAAkJChGKAwDWAQAfAAkJChGKAwDWAQAAAA==.',
Sm='Smallblades:BAAALgAECgEJAQABLgAECgcJHgAHAMARAA==.Smallchaos:BAABLgAECn8eAAIHAAcJwBGRKAAkAQAHAAcJwBGRKAAkAQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgcJHgAHAMARAA==.Smallêntropy:BAABLgAECn8WAAIDAAgJSA2JDgBYAQADAAgJSA2JDgBYAQAAAA==.Smelt:BAAALgAECgIJCgAAAA==.',
Sn='Snøt:BAAALgADCgcJDAAAAA==.',
So='Sokáar:BAAALgAECgkJAQAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgYJDgABLgAECgkJGgAaAI8YAA==.',
St='Stabbytrout:BAABLgAECn8VAAIkAAkJKheEGgAuAgAkAAkJKheEGgAuAgAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.Stormtalon:BAAALgADCgIJAgAAAA==.',
Su='Sugondis:BAACLgAFFH8IAAIeAAYJtBLpEwAXAQAeAAYJtBLpEwAXAQAuAAQKfxUAAh4ACQn1IXAGABkDAB4ACQn1IXAGABkDAAEuAAUUCQkxACAAXiQA.Sunetra:BAABLgAECn8eAAIKAAkJRQwAfQBpAQAKAAkJRQwAfQBpAQAAAA==.Sunraku:BAAALgAECgEJAwABLgAECgEJBgAEAAAAAA==.Sunshine:BAAALgAECgYJEgAAAA==.Susì:BAAALgADCgIJAgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgEJAQABLgAECgQJBgAEAAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBgAAAA==.',
Ta='Taehyung:BAABLgAECn8WAAIaAAkJEwiHdwBFAQAaAAkJEwiHdwBFAQAAAA==.Taloki:BAAALgAECgEJAgAAAA==.Tangir:BAAALgAECgQJBAAAAA==.Tatavete:BAAALgADCgUJBQAAAA==.Tatsuhisa:BAAALgAECggJDQAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAABLgAECn8tAAMJAAgJXgVuTwDoAAAJAAgJXgVuTwDoAAAFAAUJAAUckACkAAAAAA==.',
Th='Thallyn:BAAALgAECgcJBwAAAA==.',
Ti='Tinny:BAAALgAECgEJBQAAAA==.Tippshunter:BAABLgAECn82AAILAAkJNhzoBwCcAgALAAkJNhzoBwCcAgAAAA==.',
To='Tognuwa:BAAALgAECgEJAQAAAA==.Tonguefu:BAAALgAECgEJAQAAAA==.Tonton:BAAALgAECgEJAQAAAA==.Toph:BAACLgAFFH8KAAMTAAQJihjSAwAwAQATAAQJshbSAwAwAQAcAAEJFyHyHgBbAAAuAAQKfyEABBMACQmwIVQJAEwCABMABwkqIVQJAEwCABwAAwlgHlphAKkAABQAAwljBE89AIAAAAAA.Tophdh:BAABLgAECn8fAAIDAAkJfSK6AQD/AgADAAkJfSK6AQD/AgABLgAFFAQJCgATAIoYAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECgkJKQAXAP4WAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECgkJKQAXAP4WAA==.Tryit:BAAALgAECgQJBAABLgAECgkJKQAXAP4WAA==.Trythefox:BAABLgAECn8pAAIXAAkJ/haUGADaAQAXAAkJ/haUGADaAQAAAA==.',
Ts='Tseris:BAAALgAECgUJCwAAAA==.Tsukihana:BAAALgAECgUJDQAAAA==.',
Tu='Tuini:BAABLgAECn8iAAMFAAkJIhmEGQByAgAFAAkJIhmEGQByAgAJAAUJtAyLXQC8AAAAAA==.',
Ty='Tydis:BAABLgAECn8wAAIKAAgJ/AyMgwBdAQAKAAgJ/AyMgwBdAQAAAA==.',
['Tá']='Tálonstorm:BAABLgAECn82AAIgAAgJ4AbfMAD5AAAgAAgJ4AbfMAD5AAAAAA==.',
Ul='Ultra:BAAALgAECgMJBQAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.Untamed:BAAALgADCgkJCwAAAA==.',
Va='Vaehunt:BAEALgADCgMJBAABLgAFFAUJDgANAOIUAA==.Vaesar:BAEALgADCgUJBgABLgAFFAUJDgANAOIUAA==.Vaesara:BAECLgAFFH8OAAINAAUJ4hTuQAAVAQANAAUJ4hTuQAAVAQAuAAQKfywAAg0ACQmBIZkJAPcCAA0ACQmBIZkJAPcCAAAA.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Valynaria:BAAALgAECgEJAQAAAA==.Vani:BAABLgAECn8dAAIbAAgJaQ2/LgBJAQAbAAgJaQ2/LgBJAQAAAA==.',
Ve='Velora:BAAALgAECgQJBAAAAA==.',
Vi='Vilthrax:BAAALgAECgYJBgAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwAEAAAAAA==.',
Wa='Wadorinramps:BAAALgAECgYJCwABLgAECgkJGwAdALoXAA==.Waffleiron:BAABLgAECn8XAAQRAAYJyyIdIgCDAQARAAYJyyIdIgCDAQAbAAMJsx6VSwAKAQAIAAQJKRChSQDfAAAAAA==.Watermelon:BAAALgAECggJEAAAAA==.',
Wf='Wforwumbo:BAAALgADCgEJAQAAAA==.',
Wh='Whalaski:BAABLgAECn8tAAIQAAkJVxSQLgAXAgAQAAkJVxSQLgAXAgAAAA==.',
Wi='Wickedsin:BAABLgAECn8bAAIoAAgJGgw/EQAkAQAoAAgJGgw/EQAkAQAAAA==.Windhurst:BAAALgAECgYJBgAAAA==.',
Wo='Woggieboggie:BAAALgAECgkJDAAAAA==.',
Wr='Wreckitman:BAACLgAFFH8WAAIVAAYJ9BNGFACyAQAVAAYJ9BNGFACyAQAuAAQKfx4AAhUACQlYHs0LAPoCABUACQlYHs0LAPoCAAAA.',
Xa='Xaalath:BAABLgAECn8oAAIMAAgJHQnBkgBNAQAMAAgJHQnBkgBNAQAAAA==.',
Xh='Xhile:BAAALgADCgEJAQAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAIUAAgJSwhvIQBwAQAUAAgJSwhvIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECggJEgAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.Yersn:BAAALgAECgQJBwAAAA==.',
Yo='Yobaz:BAAALgADCgYJFQAAAA==.Yohanan:BAAALgADCgYJBgAAAA==.Yozomi:BAAALgADCgQJBAAAAA==.',
Za='Zappya:BAAALgAECgYJBgAAAA==.Zarorisk:BAAALgAECgcJEAABLgAECgkJJwAGAAMYAA==.',
Ze='Zerø:BAAALgADCgcJBgAAAA==.Zetz:BAAALgADCgcJBwAAAA==.Zewse:BAAALgAECgEJAgAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAABLgAECn8cAAILAAYJ+Bd8EgCbAQALAAYJ+Bd8EgCbAQAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAABLgAECn8aAAIKAAgJXxoUTwD1AQAKAAgJXxoUTwD1AQAAAA==.',
Zu='Zuesb:BAAALgADCgUJBgAAAA==.',
Zy='Zyvidria:BAABLgAECn8aAAITAAgJ8xRvBwC4AQATAAgJ8xRvBwC4AQAAAA==.',
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
