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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Unknown-Unknown','Shaman-Restoration','Druid-Feral','DemonHunter-Havoc','Priest-Shadow','Shaman-Elemental','Paladin-Retribution','Hunter-Survival','Mage-Frost','Shaman-Enhancement','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Discipline','Monk-Mistweaver','Evoker-Devastation','Evoker-Preservation','Druid-Restoration','Druid-Balance','Monk-Brewmaster','Paladin-Holy','Paladin-Protection','Priest-Holy','Evoker-Augmentation','Druid-Guardian','Warlock-Demonology','Monk-Windwalker','Mage-Arcane','Warrior-Arms','DeathKnight-Blood','Warrior-Fury','DemonHunter-Devourer','Rogue-Outlaw','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Warlock-Affliction','Warlock-Destruction',}
local provider = {region='US',realm='Korialstrasz',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Acaval:BAACLgAFFH8KAAMBAAMJLB0OEADcAAACAAMJLB1YdQD0AAABAAMJwRAOEADcAAAuAAQKfxQAAwIACQm+IZwIAB4DAAIACQm+IZwIAB4DAAEAAQlrIk0nAF4AAAAA.Accursed:BAACLgAFFH8NAAIDAAQJPyUxAQCtAQADAAQJPyUxAQCtAQAuAAQKfyIAAgMACAl6JqsAAFYDAAMACAl6JqsAAFYDAAAA.Achanthu:BAAALgADCgcJBwAAAA==.',
Ad='Adol:BAAALgADCgMJAwAAAA==.Aduayro:BAAALgADCgQJBAAAAA==.',
Ae='Aerolias:BAAALgAECgQJBgAAAA==.',
Ai='Airpod:BAAALgAECgEJAQABLgAECggJEAAEAAAAAA==.',
Al='Aleighta:BAABLgAECn8bAAIFAAkJ6wokTgBbAQAFAAkJ6wokTgBbAQAAAA==.Allocer:BAAALgADCgMJAwAAAA==.Alyianna:BAAALgADCgEJAQAAAA==.Alyx:BAAALgAECgEJAQAAAA==.',
Am='Amadia:BAAALgAECgMJBgAAAA==.',
An='Anahu:BAAALgADCgUJBwAAAA==.Anaia:BAAALgADCgEJAgAAAA==.Anamae:BAABLgAECn8YAAIGAAcJ4AxAHAACAQAGAAcJ4AxAHAACAQAAAA==.Andagard:BAAALgADCgEJAQAAAA==.Angrael:BAAALgADCgEJAgAAAA==.',
Ao='Aoi:BAAALgADCgcJBwABLgAECggJGgAHAJMVAA==.',
Ap='Apogee:BAAALgADCgEJAQAAAA==.',
Ar='Arcey:BAAALgAECgIJAgAAAA==.',
As='Asatrath:BAAALgAECgYJDwAAAA==.Ashkillz:BAABLgAECn8gAAIIAAcJRx95FAANAgAIAAcJRx95FAANAgAAAA==.Ashtuck:BAAALgAECgYJCQAAAA==.Aspectoflol:BAAALgAECgYJCAAAAA==.Astrea:BAAALgAECgEJAQAAAA==.',
At='Atlantis:BAABLgAECn8UAAIJAAgJjAtUOwAsAQAJAAgJjAtUOwAsAQAAAA==.',
Av='Avenger:BAAALgADCgMJAwABLgAECgYJBQAEAAAAAA==.Averissa:BAAALgAECgMJAwAAAA==.',
Az='Azazely:BAAALgAECgkJCAAAAA==.',
Ba='Badoussi:BAAALgAECgQJCQABLgAECgkJIgAGAKUXAA==.Bahnanahamok:BAAALgAECgEJAQAAAA==.Baiguang:BAAALgADCgUJBwAAAA==.Baja:BAAALgAECgQJBQAAAA==.Balodir:BAAALgAECgQJBQAAAA==.Bananas:BAACLgAFFH8TAAIKAAYJ9CBFEACpAQAKAAYJ9CBFEACpAQAuAAQKfxoAAgoACAn8Ij0RAAYDAAoACAn8Ij0RAAYDAAAA.',
Be='Beefomancer:BAAALgAECgQJBAABLgAECgkJLwALACYcAA==.Belan:BAABLgAECn8jAAIMAAkJ7RQ3OQAdAgAMAAkJ7RQ3OQAdAgAAAA==.Belladin:BAABLgAECn8gAAIKAAkJ0x/THgCyAgAKAAkJ0x/THgCyAgAAAA==.',
Bl='Blakeshelton:BAAALgAECgIJAwABLgAECggJEAAEAAAAAA==.Blameurself:BAAALgAECgkJEwAAAA==.Blamezuko:BAAALgAECgUJBgABLgAECgkJEwAEAAAAAA==.Blaster:BAAALgAECgEJBgAAAA==.Blite:BAAALgADCgQJDQAAAA==.Bluethain:BAAALgAECgQJBAAAAA==.',
Bo='Bombakaap:BAAALgAECgYJCwAAAA==.Bomburst:BAABLgAECn8fAAINAAcJSxH7EwBYAQANAAcJSxH7EwBYAQAAAA==.Bonelespizza:BAACLgAFFH8IAAICAAIJOQqFSACTAAACAAIJOQqFSACTAAAuAAQKfzgAAwIACQlhH9sjAK8CAAIACQmHHtsjAK8CAAEABgmKH8MKAKMBAAAA.Boogiebabe:BAAALgAECgcJCgAAAA==.',
Br='Braye:BAAALgADCgMJAwAAAA==.Bresnick:BAAALgADCgkJEgAAAA==.Briaris:BAACLgAFFH8KAAILAAQJchNmDwBBAQALAAQJchNmDwBBAQAuAAQKfyMABAsACAmCHTgIAGsCAAsACAmCHTgIAGsCAA4AAQkuC0g5ACwAAA8AAQkIArklAScAAAAA.Bruel:BAAALgADCgUJBQAAAA==.',
Bu='Bullschmidt:BAAALgAECgYJDwAAAA==.Burntout:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
['Bê']='Bêz:BAAALgAECgEJAQAAAA==.',
['Bë']='Bëz:BAABLgAECn8rAAIDAAgJhCFQAwCUAgADAAgJhCFQAwCUAgAAAA==.',
Ca='Caducious:BAAALgADCgkJEgAAAA==.Calabretta:BAAALgAECgEJAQAAAA==.Capziesh:BAAALgAECgQJBQAAAA==.Casteel:BAAALgAECggJDAAAAA==.',
Ch='Chaindemon:BAAALgADCgIJBAAAAA==.Charysmaa:BAAALgADCgQJDQAAAA==.Cheoekar:BAAALgAECgYJBwABLgAFFAYJFgAQAKMTAA==.Chlorìne:BAAALgAECgQJBQAAAA==.',
Co='Cobey:BAABLgAECn8UAAIKAAcJUhFWfwBVAQAKAAcJUhFWfwBVAQAAAA==.Coca:BAAALgADCgEJAQAAAA==.Corgi:BAABLgAECn8bAAIRAAgJ/yHYBwACAwARAAgJ/yHYBwACAwAAAA==.Cosmicjay:BAECLgAFFH8FAAIJAAMJMBOZKgDJAAAJAAMJMBOZKgDJAAAuAAQKfxgAAgkACAmsII8QAFkCAAkACAmsII8QAFkCAAAA.Cosmicnova:BAEALgAFFAEJAQABLgAFFAMJBQAJADATAA==.Costa:BAAALgAECgEJAQAAAA==.',
Cr='Crentacles:BAABLgAECn8dAAIJAAkJrxZuFwAQAgAJAAkJrxZuFwAQAgAAAA==.Critshade:BAAALgAECgYJDQAAAA==.Crow:BAAALgAFFAUJJAAAAQ==.',
Da='Dadeulus:BAAALgAECgcJDAAAAA==.Daffodil:BAABLgAECn8lAAMSAAgJGxFjCACZAQASAAgJGxFjCACZAQATAAMJ2wLMLgBeAAAAAA==.Dannyscream:BAAALgADCgcJBwABLgAECgIJAgAEAAAAAA==.Dannyshoot:BAAALgAECgIJAgAAAA==.Dantreess:BAACLgAFFH8UAAIUAAUJrgwTIAA7AQAUAAUJrgwTIAA7AQAuAAQKfyEAAxQACQl+HEkdAFMCABQACQl+HEkdAFMCABUAAQmSAzCSAB8AAAAA.Dantruis:BAAALgAECgEJAQABLgAFFAUJFAAUAK4MAA==.Darkshiver:BAAALgADCgEJAgABLgAECgEJBgAEAAAAAA==.Dawnslight:BAABLgAECn8UAAIKAAYJtQGOMwFbAAAKAAYJtQGOMwFbAAAAAA==.',
De='Deathlypants:BAAALgAECgIJAwAAAA==.Dedebop:BAAALgAECgEJAwAAAA==.Deiside:BAAALgADCgkJCQAAAA==.Demonwolfss:BAAALgAECgQJBAABLgAFFAcJGgAWAFgfAA==.Denareyeth:BAAALgAECgUJCwAAAA==.Dephiance:BAAALgAECgcJCAABLgAECgkJJwAIAEEUAA==.Destroo:BAAALgADCgUJBgAAAA==.',
Dh='Dhiva:BAAALgAECgYJEAAAAA==.',
Di='Diabla:BAABLgAECn8XAAIXAAYJeCTQFwBTAgAXAAYJeCTQFwBTAgAAAA==.Dinsfirë:BAAALgAECgEJAQAAAA==.Diothorn:BAABLgAECn8gAAMKAAcJUhl3aQCCAQAKAAYJUBp3aQCCAQAYAAMJexAXLwCTAAAAAA==.Disappointed:BAAALgADCgYJBgAAAA==.Divanas:BAAALgAECgYJEQAAAA==.Divi:BAABLgAECn8bAAIZAAgJESO7BQAMAwAZAAgJESO7BQAMAwAAAA==.',
Do='Doxa:BAAALgADCgIJAgAAAA==.',
Dr='Dragonboi:BAABLgAECn8ZAAIaAAgJgBBFLgBjAQAaAAgJgBBFLgBjAQAAAA==.Drpepperz:BAAALgAFFAIJAgAAAA==.Drägonwärior:BAAALgAECgEJAQAAAA==.',
Du='Durgan:BAAALgADCgQJBwAAAA==.Durock:BAAALgADCgQJBAABLgAECgkJGwAbALoXAA==.',
Dy='Dymondsmashr:BAABLgAECn8tAAIXAAgJswnINwBWAQAXAAgJswnINwBWAQAAAA==.',
El='Elementz:BAAALgADCgYJCwAAAA==.Elfsa:BAAALgADCgYJBgAAAA==.Ellayria:BAAALgAECgYJCgAAAA==.',
Em='Emberrose:BAAALgADCgkJEwAAAA==.',
En='Endra:BAAALgADCgYJBgAAAA==.Enhancedpant:BAAALgAECgQJBAAAAA==.Ensetral:BAAALgADCgQJBAAAAA==.Envymytalent:BAAALgADCgQJBwABLgAECgcJCwAEAAAAAA==.',
Er='Eraleth:BAAALgADCgEJAQAAAA==.Eric:BAAALgADCgYJCQAAAA==.',
Ev='Evangaline:BAAALgADCgUJCQAAAA==.Evelithillyn:BAAALgAECgQJBQABLgAECgkJEwAEAAAAAA==.Everydae:BAACLgAFFH8FAAIaAAMJEAssGwCUAAAaAAMJEAssGwCUAAAuAAQKfyYAAhoACQnUH68KAJQCABoACQnUH68KAJQCAAAA.',
Ez='Eztradez:BAEALgADCgcJCwABLgAECgkJFgAcAAMXAA==.',
Fa='Fakedruid:BAAALgAECgcJDgABLgAECgkJLwALACYcAA==.Falarzer:BAAALgADCgIJAgAAAA==.',
Fe='Feledris:BAAALgADCgcJDgAAAA==.Feybeasts:BAAALgAECgYJBwAAAA==.Feárbomber:BAAALgAECgQJBAABLgAECggJMAAWAOMkAA==.',
Ff='Ffand:BAABLgAECn8WAAIPAAYJ5x/VOADLAQAPAAYJ5x/VOADLAQAAAA==.',
Fh='Fharia:BAAALgAECgEJAQAAAA==.',
Fl='Flarewalker:BAAALgAECgYJAQAAAA==.Flawless:BAAALgAECgEJAQAAAA==.Flayr:BAAALgADCgkJDQAAAA==.Flopper:BAAALgADCgIJAgAAAA==.',
Fo='Fortitude:BAAALgAECgcJCwAAAA==.',
Fu='Fusky:BAABLgAECn8iAAIFAAkJhhLHJAAYAgAFAAkJhhLHJAAYAgAAAA==.',
Fy='Fynn:BAACLgAFFH8NAAINAAUJkQ0PCAAeAQANAAUJkQ0PCAAeAQAuAAQKfyAAAw0ACAnFFwwLABwCAA0ACAnFFwwLABwCAAUAAQmjAYipACQAAAAA.',
Ga='Galadria:BAABLgAFFH8NAAIVAAQJWRHWHQAGAQAVAAQJWRHWHQAGAQAAAA==.Ganeda:BAAALgAECgcJDAABLgAECgkJGwAbALoXAA==.Garamond:BAAALgADCgEJAQAAAA==.Garchomp:BAAALgAECgcJBgAAAA==.Garrish:BAAALgADCgEJAQAAAA==.',
Ge='Geraldini:BAAALgAECgMJAwAAAA==.Gerwik:BAABLgAECn8iAAIPAAgJ4Bh0OADlAQAPAAgJ4Bh0OADlAQAAAA==.',
Gi='Ging:BAAALgAECgYJDAAAAA==.',
Go='Goatpaladin:BAAALgAECgYJDQAAAA==.Gogetta:BAAALgAECgEJAQAAAA==.Goibniu:BAAALgADCgEJAQAAAA==.Goldenlock:BAAALgAECgYJDwAAAA==.Goliather:BAAALgADCgEJAQAAAA==.Govana:BAAALgAECgcJDgAAAA==.',
Gr='Greenleaves:BAABLgAECn8WAAIdAAgJ8hgTGQDSAQAdAAgJ8hgTGQDSAQAAAA==.Greenpepperz:BAAALgADCgYJBgAAAA==.Gregsh:BAABLgAECn8zAAMMAAkJNxavMQA6AgAMAAkJNxavMQA6AgAeAAEJ6APUIQAkAAAAAA==.Grimward:BAAALgAECgYJBgAAAA==.Grosmash:BAAALgADCgEJAQAAAA==.',
Gu='Guay:BAAALgADCggJDAAAAA==.Guccisniper:BAAALgAECgkJBQAAAA==.Gummifishz:BAAALgADCgcJBwAAAA==.Gummiwormz:BAABLgAECn8gAAIXAAgJ5htWDQCnAgAXAAgJ5htWDQCnAgAAAA==.',
Ha='Hailin:BAABLgAECn8sAAIKAAkJ5xkGNgAQAgAKAAkJ5xkGNgAQAgAAAA==.Halfheal:BAAALgAECggJDgAAAA==.Halrem:BAAALgAECgIJAgAAAA==.Hatamarü:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8ZAAIYAAYJ1Bn7FQBZAQAYAAYJ1Bn7FQBZAQAAAA==.',
He='Heherawr:BAAALgADCgMJAwABLgAECgQJCwAEAAAAAA==.Hellman:BAAALgADCgUJCQAAAA==.Hertzabit:BAAALgAECgEJAQABLgAFFAYJFwACAPcbAA==.',
Hi='Hightroller:BAABLgAECn8uAAIPAAkJehonGgBzAgAPAAkJehonGgBzAgAAAA==.Hima:BAABLgAECn8aAAIHAAgJkxXWFgCvAQAHAAgJkxXWFgCvAQAAAA==.',
Ho='Holyjenkins:BAAALgADCgkJDgAAAA==.Holysathh:BAAALgAECgUJDgABLgAECgkJGwAbALoXAA==.Holysmoked:BAAALgADCgIJAgAAAA==.Holystormm:BAAALgAECgQJBAAAAA==.Homulily:BAAALgADCggJGwAAAA==.Hornggry:BAAALgAECgQJAwABLgAECggJGgAWAJ4dAA==.Horngrry:BAAALgAECgYJCwABLgAECggJGgAWAJ4dAA==.Horngryer:BAAALgAECgQJBQABLgAECggJGgAWAJ4dAA==.Horngryerr:BAABLgAECn8aAAIWAAgJnh2sIwB7AQAWAAgJnh2sIwB7AQAAAA==.Horngryish:BAAALgADCgEJAQABLgAECggJGgAWAJ4dAA==.Hortler:BAAALgAECgQJBAAAAA==.Howlingdeath:BAAALgAECgMJBQABLgAECggJMQARAD8aAA==.',
Hu='Hulkshe:BAAALgAECgkJCQAAAA==.Huntingpants:BAABLgAECn8eAAIOAAkJRRFqCQDJAQAOAAkJRRFqCQDJAQAAAA==.',
Il='Ilovebagels:BAAALgADCgYJBgAAAA==.',
Im='Imkillho:BAAALgAECgQJBwABLgAECggJGgAWAJ4dAA==.',
In='Inspiredbox:BAAALgAECgMJBAAAAA==.Inverness:BAAALgAECgEJAQAAAA==.',
It='Ithax:BAAALgADCgcJAQAAAA==.',
Ja='Jacobsangle:BAAALgAECgEJAQABLgAECgEJBgAEAAAAAA==.Jankismith:BAABLgAECn8sAAIRAAgJKg49OgBWAQARAAgJKg49OgBWAQAAAA==.Jayy:BAABLgAECn8tAAILAAgJUxE4GgC+AQALAAgJUxE4GgC+AQAAAA==.',
Je='Jelqmaxxing:BAAALgADCgcJBwABLgAFFAkJKAAfALwjAA==.Jenny:BAABLgAECn8uAAIKAAgJMRquNgAOAgAKAAgJMRquNgAOAgAAAA==.Jeralt:BAAALgADCgUJCQAAAA==.',
Ji='Jiraku:BAAALgAECgcJDwAAAA==.Jitoflight:BAAALgAECgYJBgAAAA==.',
Jo='Jolencila:BAAALgADCgEJAQAAAA==.Jozzartt:BAAALgAECgYJDAAAAA==.',
Ju='Junieb:BAABLgAECn8dAAIMAAkJHwtfhABTAQAMAAkJHwtfhABTAQAAAA==.',
Ka='Kachiko:BAAALgADCggJFAAAAA==.Kaethas:BAAALgADCgEJAgAAAA==.Kaia:BAABLgAECn8UAAIcAAcJrAsrhQAlAQAcAAcJrAsrhQAlAQAAAA==.Kamerth:BAABLgAECn8mAAMQAAgJjweNLQBIAQAQAAgJjweNLQBIAQAIAAgJVwinNQAdAQAAAA==.Kamugi:BAAALgADCgMJAwABLgAFFAMJBgATAJwJAA==.Kapnkrunch:BAAALgAECgUJBQAAAA==.Karluron:BAABLgAECn8ZAAIIAAkJyhSsFQABAgAIAAkJyhSsFQABAgAAAA==.Karlutros:BAABLgAECn8nAAIIAAkJ/hGpGwDLAQAIAAkJ/hGpGwDLAQAAAA==.Katastrafia:BAAALgAECgIJAgAAAA==.Katowo:BAAALgAECgQJCQABLgAFFAYJFgAgAAQmAA==.Katuwuagain:BAACLgAFFH8WAAIgAAYJBCa3BAASAgAgAAYJBCa3BAASAgAuAAQKfxYAAiAACQkxJokAAG0DACAACQkxJokAAG0DAAAA.Kazure:BAABLgAECn8rAAITAAkJcQ1pEgCPAQATAAkJcQ1pEgCPAQAAAA==.',
Ke='Keiforius:BAAALgADCgcJCwAAAA==.Kelilia:BAABLgAECn87AAIhAAkJhxCqIQDQAQAhAAkJhxCqIQDQAQAAAA==.Keniilar:BAAALgAECgEJAQAAAA==.Kenilar:BAAALgAECgEJAQAAAA==.Keybricker:BAAALgAECgcJEAABLgAECgkJLwALACYcAA==.',
Kh='Khaôtic:BAABLgAECn8XAAIiAAYJCRlXZABFAQAiAAYJCRlXZABFAQAAAA==.Khuno:BAAALgAECgYJCAAAAA==.',
Ki='Killzero:BAAALgAECgQJBwAAAA==.Kiraeshh:BAABLgAECn8ZAAIMAAcJ/RLkhgBOAQAMAAcJ/RLkhgBOAQAAAA==.Kittykat:BAAALgAECgQJBgAAAA==.',
Ko='Kolonna:BAAALgAECgMJAwAAAA==.Korngry:BAAALgAECgEJAQABLgAECggJGgAWAJ4dAA==.',
Kr='Krakkin:BAAALgADCgYJGQAAAA==.Kralkatorrik:BAAALgADCgcJBwAAAA==.Krenil:BAAALgADCgYJHgAAAA==.Krieash:BAAALgADCggJCAAAAA==.Krumpas:BAAALgAECgEJAQABLgAECggJGgAWAJ4dAA==.',
Ky='Kyllea:BAABLgAECn8VAAIPAAgJxBVCQgDDAQAPAAgJxBVCQgDDAQAAAA==.',
['Kä']='Kätniss:BAAALgAECgYJBgAAAA==.',
La='Laaksy:BAACLgAFFH8MAAMSAAUJLAdaBQD/AAASAAUJ8ARaBQD/AAAaAAMJ9Qj/SgB2AAAuAAQKfx4AAhIACAl+ENgKAFkBABIACAl+ENgKAFkBAAAA.Ladraina:BAAALgAECgEJAwAAAA==.Landock:BAAALgADCgYJIwAAAA==.Lavaca:BAABLgAECn8nAAQjAAkJOyO+AQC2AgAkAAgJwSGBCQD5AgAjAAgJKSO+AQC2AgAlAAYJIR8WCQCcAQABLgAFFAMJCgABACwdAA==.',
Le='Legar:BAABLgAECn8bAAIbAAkJuhdyCgAeAgAbAAkJuhdyCgAeAgAAAA==.Lemmefreak:BAAALgAECgQJAwAAAA==.Leotart:BAACLgAFFH8LAAIUAAMJ4xC/NgDCAAAUAAMJ4xC/NgDCAAAuAAQKfysAAhQACQkIELw6AJcBABQACQkIELw6AJcBAAAA.Leprechaune:BAAALgAECgMJAwAAAA==.Leticia:BAAALgAECgkJDgAAAA==.Lexyluthorr:BAAALgADCgIJAgAAAA==.',
Li='Liechen:BAAALgAECgYJBgAAAA==.Linaraline:BAAALgADCgUJBQAAAA==.Lindiin:BAAALgADCgEJAQAAAA==.Lizawizah:BAAALgADCgEJAgAAAA==.',
Lo='Lortnok:BAAALgAECgUJEAAAAA==.Lotharmage:BAAALgAECgcJDwAAAA==.',
Lu='Ludoshel:BAAALgADCgEJAQAAAA==.Luminescent:BAAALgADCgIJAgAAAA==.Luwwin:BAAALgAECgEJAQAAAA==.',
Ly='Lyx:BAAALgADCgYJBwAAAA==.',
['Lí']='Líanna:BAAALgAECgcJDQAAAA==.',
['Lö']='Lögäñ:BAAALgAFFAEJAQAAAA==.',
Ma='Maelora:BAAALgADCgYJBgAAAA==.Magnessa:BAABLgAECn8WAAIMAAgJpQSBrwAGAQAMAAgJpQSBrwAGAQAAAA==.Malovious:BAAALgADCgkJCQAAAA==.Mandrakethan:BAAALgADCgkJHAAAAA==.Mannafest:BAEALgADCgYJBgAAAA==.Mano:BAAALgAECgEJAQAAAA==.Marist:BAABLgAECn8dAAMFAAkJGhHyUgBJAQAFAAgJfw7yUgBJAQAJAAEJVAUspwAhAAAAAA==.Marwowi:BAAALgADCgQJBAAAAA==.Maxumuss:BAAALgAECgYJBQAAAA==.',
Me='Meliodäs:BAAALgAECgEJAQAAAA==.Memelord:BAAALgADCgEJAQABLgADCgEJAQAEAAAAAA==.Metamorlis:BAAALgAECgQJBAABLgAECgkJKgAZAIYQAA==.Mewlockian:BAAALgADCgUJBQAAAA==.',
Mi='Mianceden:BAABLgAECn8jAAImAAYJgx6hEwCcAQAmAAYJgx6hEwCcAQAAAA==.Miku:BAAALgAECgkJDQABLgAECgkJLAAKAOcZAA==.Milent:BAABLgAECn8rAAIPAAgJMxgGNgDuAQAPAAgJMxgGNgDuAQAAAA==.Mimix:BAAALgADCgEJAQAAAA==.Miquiztli:BAAALgAECgkJBQAAAA==.Mizoci:BAAALgAECgEJAQAAAA==.',
Mj='Mjolniïr:BAAALgAECgEJBAAAAA==.',
Mo='Moarteas:BAAALgAECgUJBgAAAA==.Moondew:BAAALgADCgEJAQAAAA==.Moral:BAAALgADCgkJEAAAAA==.',
Ms='Msspelled:BAABLgAECn8gAAQnAAcJjRhbDgBUAQAnAAYJnxpbDgBUAQAcAAUJOg+GqwDhAAAoAAIJ/hRWNwA2AAAAAA==.',
Mv='Mvpiam:BAAALgAECgQJDAAAAA==.',
Mx='Mximus:BAAALgAECgIJAQABLgAECgYJBQAEAAAAAA==.',
My='Mystí:BAAALgAECggJDgAAAA==.',
Na='Nabstar:BAAALgADCgYJBgABLgAECgkJNwAQAOwiAA==.Nabstarr:BAABLgAECn83AAQQAAkJ7CKbAgBzAwAQAAkJ7CKbAgBzAwAZAAEJRgOUhQArAAAIAAEJAAZzgQAoAAAAAA==.Namtar:BAAALgAECgEJAgAAAA==.Nasroth:BAACLgAFFH8FAAIhAAMJFg+BLwDRAAAhAAMJFg+BLwDRAAAuAAQKfygAAiEACAlHEts8ALEBACEACAlHEts8ALEBAAAA.Nasstina:BAAALgADCgEJAQAAAA==.Nastyfear:BAAALgADCggJEwAAAA==.Natureterror:BAAALgADCgYJBgAAAA==.',
Ne='Newagebeo:BAAALgADCgEJAQAAAA==.',
Ni='Niibyter:BAABLgAECn8oAAImAAgJuyEkBgCZAgAmAAgJuyEkBgCZAgAAAA==.Niriti:BAAALgADCgYJBgAAAA==.',
No='Nowisforever:BAAALgADCgEJAgAAAA==.',
Ny='Nymneria:BAAALgAECgIJAgABLgAECgYJBQAEAAAAAA==.',
Od='Odînson:BAAALgAECgEJAQAAAA==.',
Ol='Oldgreyone:BAABLgAECn8UAAMUAAYJ2RDKZwDrAAAUAAYJ2RDKZwDrAAAVAAYJcgqrRgDUAAAAAA==.',
On='Onlyheelz:BAAALgAECgQJBwAAAA==.Onlylocks:BAABLgAECn8lAAMcAAgJORV5SQCyAQAcAAgJRBR5SQCyAQAoAAUJFRB2KgAXAQAAAA==.Ontius:BAAALgAECgQJBAAAAA==.',
Oo='Oobi:BAAALgADCgIJAgAAAA==.',
Op='Opalais:BAABLgAECn8dAAMIAAgJ0A+kLABRAQAIAAgJ0A+kLABRAQAZAAQJRAh8aACLAAAAAA==.',
Or='Orangedrives:BAAALgADCgYJCwAAAA==.Oreeoreo:BAABLgAECn8kAAICAAkJ9Q8tXwCYAQACAAkJ9Q8tXwCYAQAAAA==.Orlathil:BAAALgADCgkJCQABLgAECgkJKgAZAIYQAA==.Orlis:BAABLgAECn8qAAIZAAkJhhDXHwCuAQAZAAkJhhDXHwCuAQAAAA==.Oroe:BAAALgAECgYJDAAAAA==.',
Pa='Pallydan:BAAALgAECgMJBAABLgAECggJJQAMAE8XAA==.Pandamunx:BAAALgAECgMJAQAAAA==.',
Pe='Peludita:BAABLgAECn8WAAQUAAcJox0RMwDdAQAUAAcJox0RMwDdAQAVAAcJhBqfJADYAQAbAAEJsCCtKQBUAAAAAA==.Perona:BAAALgADCgYJBgAAAA==.Perséfone:BAAALgAECgYJCwABLgAECggJDgAEAAAAAA==.',
Ph='Philanthropy:BAABLgAECn8kAAMTAAgJeBnQCgAeAgATAAgJeBnQCgAeAgAaAAcJlxTCMQBOAQAAAA==.Philtwifdloa:BAAALgADCgEJAQAAAA==.',
Pi='Pitchfiend:BAAALgAECgYJBgAAAA==.Pizzeroloko:BAAALgADCgcJBwABLgAFFAQJCgALAHITAA==.',
Pl='Plumh:BAAALgADCgMJAwAAAA==.Pläze:BAAALgAECgYJEgAAAA==.',
Pn='Pnut:BAAALgAECgMJAwAAAA==.',
Po='Poppy:BAAALgAECgkJEQAAAA==.',
Pr='Prayformercy:BAAALgADCgIJAgAAAA==.Praîmfaya:BAAALgAECgQJBQAAAA==.Primeangus:BAAALgAECgkJCQAAAA==.',
Pu='Punchpup:BAABLgAECn8pAAIdAAgJpRPsJAB1AQAdAAgJpRPsJAB1AQAAAA==.',
Py='Pyronorish:BAAALgADCgYJHgAAAA==.Pytthia:BAABLgAECn8nAAMIAAkJQRTUFgD3AQAIAAkJQRTUFgD3AQAQAAcJyxLXLQBGAQAAAA==.',
['Pä']='Pändamonium:BAAALgAECgQJBAAAAA==.',
Qu='Quicknclever:BAAALgAECgQJAwAAAA==.Quzbis:BAAALgADCgcJDAAAAA==.',
Ra='Randamonk:BAAALgAECgUJBQAAAA==.Ranraku:BAAALgADCgEJAQAAAA==.Raptalia:BAAALgADCgcJBwABLgAECgkJLAAKAOcZAA==.Raziel:BAABLgAECn8RAAIiAAgJSRk+NAAoAgAiAAgJSRk+NAAoAgAAAA==.',
Re='Reagin:BAAALgADCgUJBQAAAA==.Recon:BAAALgAECgEJAQAAAA==.Regade:BAAALgADCgkJCQABLgAECgkJJwAIAEEUAA==.Relacks:BAAALgADCgEJAQAAAA==.Reldruin:BAAALgAECgQJCQAAAA==.Rem:BAAALgADCgUJCQAAAA==.',
Rh='Rhaena:BAABLgAECn8cAAIKAAgJDQuHkAA2AQAKAAgJDQuHkAA2AQAAAA==.',
Ri='Rikiriki:BAABLgAECn8YAAMVAAYJuQJZXACGAAAVAAYJuQJZXACGAAAUAAYJFgKvmABtAAAAAA==.',
Rn='Rndnfluffy:BAAALgAECgEJAgAAAA==.',
Ro='Robok:BAAALgADCgYJBgAAAA==.Rochausia:BAAALgADCgMJAwAAAA==.Ronkey:BAAALgAECgkJBgAAAA==.Ronkzar:BAAALgAECgMJBAAAAA==.Rotskar:BAAALgADCggJDAAAAA==.',
Rp='Rpgovan:BAAALgAECgQJBAAAAA==.',
Ru='Rubidious:BAAALgAECgEJAgAAAA==.Ruth:BAABLgAECn8jAAIaAAgJSw13MgBKAQAaAAgJSw13MgBKAQAAAA==.',
['Rô']='Rôflstômp:BAAALgAECgEJAQAAAA==.',
Sa='Sacini:BAAALgADCgYJBgAAAA==.Sakai:BAAALgADCgYJBgAAAA==.Saltydog:BAAALgADCgYJEQAAAA==.Sandstone:BAAALgAECgEJAgAAAA==.Saratar:BAAALgADCgIJAgAAAA==.Sarlaana:BAAALgAECgEJAQAAAA==.Sashayleft:BAAALgAECgcJDgAAAA==.Satrazath:BAAALgAECgcJEgAAAA==.',
Sc='Scurge:BAAALgAECgIJAwABLgAECgYJBQAEAAAAAA==.',
Se='Secretlight:BAAALgADCgcJDAAAAA==.Secretmage:BAAALgADCgcJCAAAAA==.Seizo:BAAALgAECgYJDwAAAA==.Selfesteem:BAAALgADCgYJBgABLgAECggJJQAMAE8XAA==.Setal:BAABLgAECn81AAMaAAkJxxxMCgCaAgAaAAkJxxxMCgCaAgASAAEJIxHfPAA7AAAAAA==.',
Sg='Sgtpepperz:BAAALgADCgYJBgAAAA==.',
Sh='Shadovar:BAAALgADCgIJAgAAAA==.Shambio:BAAALgADCgEJAwAAAA==.Shammanized:BAAALgADCgkJCgAAAA==.Shamurloc:BAACLgAFFH8NAAIJAAUJrB0iFwA2AQAJAAUJrB0iFwA2AQAuAAQKfyUAAwkACQn2I2sBALIDAAkACQn2I2sBALIDAAUABgkbGOpCAHUBAAAA.Shayee:BAAALgADCgEJAQAAAA==.Sheenatonic:BAAALgAECgUJCQAAAA==.Sheenzilla:BAABLgAECn8mAAMaAAkJMgXsQAAFAQAaAAkJMgXsQAAFAQATAAYJIQGDOACnAAAAAA==.Shelltear:BAAALgADCgYJCAAAAA==.Shelwreth:BAAALgAECgYJDAAAAA==.Shigeko:BAAALgAECgMJAwAAAA==.Shikarra:BAAALgADCgkJFAAAAA==.Shindei:BAAALgADCgYJBgAAAA==.Shiro:BAABLgAFFH8IAAIRAAMJkAfMNQCPAAARAAMJkAfMNQCPAAABLgAFFAQJEAAUAHYNAA==.Shoinked:BAABLgAECn83AAIJAAgJaBD6MABhAQAJAAgJaBD6MABhAQAAAA==.Shâmwów:BAAALgAECgEJAQAAAA==.',
Si='Sices:BAAALgAECgEJAQAAAA==.Sifodyas:BAAALgADCggJCAAAAA==.Silentpaw:BAABLgAECn8wAAIWAAgJ4yT4BADmAgAWAAgJ4yT4BADmAgAAAA==.',
Sl='Slak:BAABLgAECn8UAAIeAAkJChFOAwDdAQAeAAkJChFOAwDdAQAAAA==.',
Sm='Smallchaos:BAABLgAECn8eAAIHAAcJwBHEJQAmAQAHAAcJwBHEJQAmAQAAAA==.Smallpaws:BAAALgADCgUJCgABLgAECgcJHgAHAMARAA==.Smallêntropy:BAAALgAECggJEwAAAA==.Smelt:BAAALgAECgIJCgAAAA==.Smuurfette:BAEBLgAECn8WAAIcAAkJAxdSLwAPAgAcAAkJAxdSLwAPAgAAAA==.',
Sn='Snøt:BAAALgADCgcJDAAAAA==.',
So='Sokáar:BAAALgAECgEJAQAAAA==.Solarflare:BAAALgAECgcJAgAAAA==.Solofarm:BAAALgADCgIJAgAAAA==.',
Sp='Spriest:BAEALgAECgUJCAABLgAECgkJFgAcAAMXAA==.',
St='Stabbytrout:BAABLgAECn8VAAIkAAkJKheEGgAuAgAkAAkJKheEGgAuAgAAAA==.Steeb:BAAALgAECgcJBwAAAA==.Stickyjr:BAAALgADCgEJAQAAAA==.Stormtalon:BAAALgADCgIJAgAAAA==.',
Su='Sugondis:BAACLgAFFH8IAAIdAAYJtBKCEQAdAQAdAAYJtBKCEQAdAQAuAAQKfxUAAh0ACQn1IXAGABkDAB0ACQn1IXAGABkDAAEuAAUUCQkoAB8AvCMA.Sunetra:BAABLgAECn8dAAIKAAkJRQyCdQBoAQAKAAkJRQyCdQBoAQAAAA==.Sunraku:BAAALgAECgEJAwABLgAECgEJBgAEAAAAAA==.Sunshine:BAAALgAECgYJEQAAAA==.Susì:BAAALgADCgIJAgAAAA==.',
['Sà']='Sàlanis:BAAALgAECgEJAQABLgAECgQJBgAEAAAAAA==.',
['Sã']='Sãlanis:BAAALgAECgQJBgAAAA==.',
Ta='Taehyung:BAAALgAECgkJEwAAAA==.Taloki:BAAALgAECgEJAQAAAA==.Tatavete:BAAALgADCgUJBQAAAA==.Tatsuhisa:BAAALgAECggJDQAAAA==.Tazdingo:BAAALgADCgMJAwAAAA==.',
Te='Telaliah:BAAALgADCgEJAQAAAA==.Terregoat:BAABLgAECn8sAAMJAAgJXgUzSgDwAAAJAAgJXgUzSgDwAAAFAAUJAAUqiQCkAAAAAA==.',
Th='Thallyn:BAAALgAECgcJBwAAAA==.',
Ti='Tinny:BAAALgAECgEJBQAAAA==.Tippshunter:BAABLgAECn8vAAILAAkJJhx2BwCcAgALAAkJJhx2BwCcAgAAAA==.',
To='Tonton:BAAALgAECgEJAQAAAA==.Toph:BAACLgAFFH8KAAMSAAQJihhPAwBCAQASAAQJshZPAwBCAQAaAAEJFyHyHgBbAAAuAAQKfyEABBIACQmwIVQJAEwCABIABwkqIVQJAEwCABoAAwlgHnJbAKEAABMAAwljBE89AIAAAAAA.Tophdh:BAABLgAECn8fAAIDAAkJfSK6AQD/AgADAAkJfSK6AQD/AgABLgAFFAQJCgASAIoYAA==.',
Tr='Traydle:BAAALgADCgkJCQABLgAECgkJKQAWAP4WAA==.Troncho:BAAALgAECgUJDgAAAA==.Trydel:BAAALgADCgQJBAABLgAECgkJKQAWAP4WAA==.Tryit:BAAALgAECgQJBAABLgAECgkJKQAWAP4WAA==.Trythefox:BAABLgAECn8pAAIWAAkJ/hZuFwDbAQAWAAkJ/hZuFwDbAQAAAA==.',
Ts='Tseris:BAAALgAECgUJCwAAAA==.Tsukihana:BAAALgAECgUJDAAAAA==.',
Tu='Tuini:BAABLgAECn8iAAMFAAkJIhmdFwB0AgAFAAkJIhmdFwB0AgAJAAUJtAxdWQC8AAAAAA==.',
Ty='Tydis:BAABLgAECn8vAAIKAAgJjwyvfQBYAQAKAAgJjwyvfQBYAQAAAA==.',
['Tá']='Tálonstorm:BAABLgAECn8wAAIfAAgJlwYRLgD3AAAfAAgJlwYRLgD3AAAAAA==.',
Ul='Ultra:BAAALgAECgEJAgAAAA==.',
Un='Unknownlord:BAAALgADCgUJBQAAAA==.Unotankhealz:BAAALgADCgMJAwAAAA==.Untamed:BAAALgADCgkJCwAAAA==.',
Va='Vaehunt:BAAALgADCgMJBAABLgAFFAUJDgAiAOIUAA==.Vaesar:BAAALgADCgUJBgABLgAFFAUJDgAiAOIUAA==.Vaesara:BAACLgAFFH8OAAIiAAUJ4hQhOQAeAQAiAAUJ4hQhOQAeAQAuAAQKfywAAiIACQmBIacIAPgCACIACQmBIacIAPgCAAAA.Valfenrys:BAAALgAECgEJAgAAAA==.Valkarrius:BAAALgADCgIJAgAAAA==.Valynaria:BAAALgADCgUJBgAAAA==.Vani:BAABLgAECn8cAAIZAAcJ2Q1MMAA2AQAZAAcJ2Q1MMAA2AQAAAA==.',
Ve='Velora:BAAALgAECgQJBAAAAA==.',
Vi='Vilthrax:BAAALgAECgYJBgAAAA==.',
Vo='Voidwrath:BAAALgADCgcJEQAAAA==.Vormav:BAAALgAECgcJCwABLgADCgMJAwAEAAAAAA==.',
Wa='Wadorinramps:BAAALgAECgYJCwABLgAECgkJGwAbALoXAA==.Waffleiron:BAABLgAECn8XAAQQAAYJyyIdIgCDAQAQAAYJyyIdIgCDAQAZAAMJsx6VSwAKAQAIAAQJKRBSRwDLAAAAAA==.Watermelon:BAAALgAECggJEAAAAA==.',
Wf='Wforwumbo:BAAALgADCgEJAQAAAA==.',
Wh='Whalaski:BAABLgAECn8tAAIPAAkJVxSjKgAcAgAPAAkJVxSjKgAcAgAAAA==.',
Wi='Wickedsin:BAABLgAECn8bAAIoAAgJGgwUEAAlAQAoAAgJGgwUEAAlAQAAAA==.Windhurst:BAAALgAECgYJBgAAAA==.',
Wo='Woggieboggie:BAAALgAECgkJDAAAAA==.',
Wr='Wreckitman:BAACLgAFFH8WAAIUAAYJ9BNjEQC7AQAUAAYJ9BNjEQC7AQAuAAQKfx4AAhQACQlYHhALAPwCABQACQlYHhALAPwCAAAA.',
Xa='Xaalath:BAABLgAECn8mAAIMAAgJ0giblQAyAQAMAAgJ0giblQAyAQAAAA==.',
['Xé']='Xéno:BAABLgAECn8ZAAITAAgJSwhvIQBwAQATAAgJSwhvIQBwAQAAAA==.',
Ya='Yaperbitally:BAAALgAECggJEgAAAA==.Yasia:BAAALgAECgMJAwAAAA==.',
Ye='Yellowsnowto:BAAALgADCgUJBQAAAA==.Yersn:BAAALgAECgIJBAAAAA==.',
Yo='Yobaz:BAAALgADCgYJDwAAAA==.Yohanan:BAAALgADCgYJBgAAAA==.',
Za='Zappya:BAAALgAECgYJBgAAAA==.Zarorisk:BAAALgAECgcJEAABLgAECgkJIgAGAKUXAA==.',
Ze='Zerø:BAAALgADCgcJBgAAAA==.Zetz:BAAALgADCgcJBwAAAA==.Zewse:BAAALgAECgEJAgAAAA==.',
Zi='Ziggiee:BAAALgAECgMJAwAAAA==.Ziggs:BAABLgAECn8cAAILAAYJ+Bd8EgCbAQALAAYJ+Bd8EgCbAQAAAA==.Zigzags:BAAALgADCgMJAwAAAA==.',
Zo='Zodiara:BAABLgAECn8aAAIKAAgJXxoUTwD1AQAKAAgJXxoUTwD1AQAAAA==.',
Zu='Zuesb:BAAALgADCgUJBgAAAA==.',
Zy='Zyvidria:BAABLgAECn8aAAISAAgJ8xTHBgDFAQASAAgJ8xTHBgDFAQAAAA==.',
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
