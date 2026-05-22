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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Priest-Shadow','Warrior-Fury','Mage-Fire','Priest-Holy','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Priest-Discipline','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Monk-Brewmaster','Hunter-Survival','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Balance','Monk-Mistweaver','Monk-Windwalker','Mage-Arcane','Druid-Guardian','Shaman-Enhancement','Druid-Feral','DemonHunter-Vengeance','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Evoker-Augmentation','Warrior-Arms',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aarchon:BAABLgAECn8iAAIBAAgJOyFmCADBAgABAAgJOyFmCADBAgAAAA==.',
Ad='Aduin:BAAALgAECgYJDAAAAA==.',
Ae='Aedarelyn:BAAALgAECgQJCwAAAA==.Aellet:BAABLgAECn8ZAAMCAAgJFyA2GQBTAgACAAgJWR82GQBTAgADAAQJdx0aGAC6AAAAAA==.Aellita:BAAALgAECgIJAgAAAA==.Aeschylus:BAAALgAECggJCgAAAA==.',
Ak='Akky:BAABLgAECn8jAAIEAAgJVCBJBgBlAgAEAAgJVCBJBgBlAgAAAA==.Aksafiya:BAABLgAECn86AAIFAAgJmhLCHQCBAQAFAAgJmhLCHQCBAQAAAA==.',
Al='Alal:BAAALgAECgYJDQAAAA==.Alandras:BAABLgAECn8dAAIGAAYJVQmmQwDjAAAGAAYJVQmmQwDjAAAAAA==.Alaras:BAACLgAFFH8UAAIFAAUJiBBeDwA+AQAFAAUJiBBeDwA+AQAuAAQKfxcAAgUACQnQFQ8aAA8CAAUACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8iAAIDAAgJcBc0BwCWAQADAAgJcBc0BwCWAQAAAA==.Allrianne:BAAALgAECgMJBAAAAA==.Allyriae:BAABLgAECn8VAAIHAAcJjAmNBQAOAQAHAAcJjAmNBQAOAQAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8XAAIIAAgJKw/uMQB5AQAIAAgJKw/uMQB5AQAAAA==.',
Am='Ambilena:BAAALgAECgYJEAAAAA==.',
An='Andoros:BAABLgAECn8xAAIJAAgJciCEDwCVAgAJAAgJciCEDwCVAgAAAA==.Angiliana:BAAALgAECgUJDAAAAA==.Angvall:BAAALgAECgYJBgABLgAECgEJAQAKAAAAAA==.Anzurath:BAABLgAECn8hAAILAAgJQhUuSQCiAQALAAgJQhUuSQCiAQAAAA==.',
Ap='Applebow:BAABLgAECn8dAAIMAAYJHhQqHwAFAQAMAAYJHhQqHwAFAQAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgADCgMJCAAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgMJAwAAAA==.Arylin:BAABLgAECn8kAAINAAgJsyKGFQChAgANAAgJsyKGFQChAgAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEALgAECgUJEAAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQAKAAAAAA==.Asnabel:BAABLgAECn8XAAIOAAcJWwhNDwD+AAAOAAcJWwhNDwD+AAAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCQAPAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgADCgkJHAAAAA==.Ayden:BAAALgAECgUJDAAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwAKAAAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.',
Bl='Blee:BAABLgAECn8fAAMQAAgJng91GAC1AQAQAAgJng91GAC1AQAFAAQJlgWRSgCwAAAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8ZAAICAAYJuhwXTwBvAQACAAYJuhwXTwBvAQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8eAAIRAAYJpiBtMgDAAQARAAYJpiBtMgDAAQAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8WAAIPAAYJOhGBiQAHAQAPAAYJOhGBiQAHAQAAAA==.Brood:BAABLgAECn8rAAIPAAkJxxRZNQDjAQAPAAkJxxRZNQDjAQAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAAALgAECgYJEgAAAA==.',
Ca='Cailaranel:BAABLgAECn8oAAMSAAgJ+wgcDAAoAQASAAcJagkcDAAoAQATAAgJYgXpIwAXAQAAAA==.Calaul:BAABLgAECn8XAAILAAYJ0Q81hwAVAQALAAYJ0Q81hwAVAQAAAA==.Calenbraga:BAAALgAECgUJEgAAAA==.Calisim:BAAALgAECgUJDAAAAA==.Callidae:BAABLgAECn8qAAIIAAkJBxFREgABAgAIAAkJBxFREgABAgAAAA==.Calmnbald:BAABLgAECn8ZAAIUAAcJeBfVLQATAQAUAAcJeBfVLQATAQAAAA==.Caloh:BAAALgADCgYJBgAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8dAAIVAAgJdwzcIABEAQAVAAgJdwzcIABEAQAAAA==.Cataryn:BAABLgAECn8eAAIRAAgJUSTaDgCTAgARAAgJUSTaDgCTAgAAAA==.Catt:BAABLgAECn8xAAIBAAgJtxjuEwAlAgABAAgJtxjuEwAlAgAAAA==.',
Ce='Cellebur:BAAALgAECgUJEAAAAA==.Ceta:BAABLgAECn8pAAIIAAgJyhy+DQBAAgAIAAgJyhy+DQBAAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAABLgAECn8rAAMWAAgJ3BFJKQC/AQAWAAgJ3BFJKQC/AQAXAAcJtBnkHQCdAQAAAA==.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn8mAAINAAYJ2gThvADPAAANAAYJ2gThvADPAAAAAA==.Cizean:BAABLgAECn8UAAINAAUJBAKS5QB9AAANAAUJBAKS5QB9AAAAAA==.',
Co='Cometopapa:BAABLgAECn8nAAMOAAgJ1RKrCACBAQAOAAgJ1RKrCACBAQAPAAcJqAjljgD+AAAAAA==.',
Cr='Craivan:BAAALgAECgUJBQAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crilly:BAABLgAECn8rAAINAAkJZRilJgA/AgANAAkJZRilJgA/AgAAAA==.Crowe:BAAALgAECgMJBAABLgAECgUJBQAKAAAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAAALgAECgUJDQAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJCwAAAA==.Damia:BAABLgAECn8dAAMTAAYJchoXGwBiAQATAAYJchoXGwBiAQASAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8iAAIMAAgJvyR9BACuAgAMAAgJvyR9BACuAgAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgEJAgABLgAECggJIgAMAL8kAA==.Delvarrieth:BAABLgAECn8UAAIYAAUJXhOGHADaAAAYAAUJXhOGHADaAAAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Denth:BAABLgAECn8UAAILAAgJwAt+cwA7AQALAAgJwAt+cwA7AQAAAA==.Dercuur:BAAALgAECgUJEAAAAA==.Devoursol:BAABLgAECn8nAAMZAAgJJAxFUgA+AQAZAAgJ8AtFUgA+AQAaAAIJrg45XABvAAAAAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgADCgkJFAAAAA==.Drainmee:BAAALgAECgYJEAAAAA==.Draknol:BAAALgADCgkJFAAAAA==.Dregoth:BAABLgAECn8jAAIPAAgJrQcSbwA8AQAPAAgJrQcSbwA8AQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8gAAMJAAkJ4R5kEAC0AgAJAAkJ4R5kEAC0AgAbAAEJxgkGcQAnAAAAAA==.',
Ea='Eathur:BAAALgADCgcJDwAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elynth:BAABLgAECn8hAAICAAgJwRvYJAAOAgACAAgJwRvYJAAOAgAAAA==.',
En='Endlessyueh:BAAALgAECgUJBgAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECggJGQACABcgAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAECgcJCAABLgAFFAQJCgALAHoOAA==.',
Fa='Face:BAAALgAECggJBgAAAA==.Faethian:BAACLgAFFH8KAAIYAAQJHx+9AQBrAQAYAAQJHx+9AQBrAQAuAAQKfywAAhgACAk6JdEBAOICABgACAk6JdEBAOICAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8iAAINAAcJXgcEkwAYAQANAAcJXgcEkwAYAQAAAA==.Fangren:BAAALgAECgYJEAAAAA==.Fariah:BAAALgAECgUJCgAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAAALgAECgYJEgAAAA==.',
Fe='Felscythe:BAAALgAECgUJEwAAAA==.Felynn:BAABLgAECn8dAAIBAAgJjBhKGAD4AQABAAgJjBhKGAD4AQAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feyrha:BAAALgADCgYJBgABLgAECgYJFwARAIoQAA==.',
Fi='Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8UAAIcAAUJUR5bHwCgAQAcAAUJUR5bHwCgAQAAAA==.',
Fl='Flaeli:BAABLgAECn8dAAINAAYJJRQCgQA5AQANAAYJJRQCgQA5AQAAAA==.Flemish:BAAALgADCgkJHwAAAA==.Flextame:BAAALgAECgQJCgAAAA==.Flipalicious:BAABLgAECn8uAAIWAAkJ7RuoCQDOAgAWAAkJ7RuoCQDOAgAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8bAAIFAAYJtBctJABSAQAFAAYJtBctJABSAQAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn8XAAIRAAYJihDWYgAjAQARAAYJihDWYgAjAQAAAA==.Gazo:BAAALgADCggJGQABLgAECggJHAAdAH4gAA==.',
Ge='Gemboss:BAABLgAECn80AAMLAAgJNB/9HwBEAgALAAgJNB/9HwBEAgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8pAAMNAAkJOxNDRQDJAQANAAkJOxNDRQDJAQAeAAMJrwXAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8eAAIdAAgJMgfJOADOAAAdAAgJMgfJOADOAAAAAA==.Ginodh:BAAALgAECggJEwAAAA==.Ginomage:BAAALgAECgcJCgABLgAECggJEwAKAAAAAA==.Ginomonk:BAAALgAECgYJBgABLgAECggJEwAKAAAAAA==.Ginopally:BAAALgAECgYJCwABLgAECggJEwAKAAAAAA==.Girth:BAAALgADCgIJAgAAAA==.Gizelli:BAAALgADCgMJAwAAAA==.',
Go='Gordonn:BAAALgAECgQJBAAAAA==.',
Gr='Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAcAGMXAA==.Grubetsella:BAACLgAFFH8FAAIcAAIJYxduDwClAAAcAAIJYxduDwClAAAuAAQKfycAAhwABgmSI7EQAFECABwABgmSI7EQAFECAAAA.',
Gu='Guenhywvar:BAABLgAECn8XAAIZAAYJXBvFUAC0AQAZAAYJXBvFUAC0AQAAAA==.Gumpers:BAABLgAECn8dAAIfAAgJLQ+cGAAOAQAfAAgJLQ+cGAAOAQAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAAALgAECgQJBAAAAA==.',
Ha='Halfamazing:BAAALgAECgQJBAAAAA==.Hanoumatoi:BAAALgAECgUJBQAAAA==.Haralambos:BAAALgAECgUJEAAAAA==.Haralogain:BAAALgAECgEJAQABLgAECgUJEAAKAAAAAA==.Harithon:BAABLgAECn8iAAIgAAgJQx/7BABHAgAgAAgJQx/7BABHAgAAAA==.Havvöc:BAABLgAECn8lAAIBAAgJBB/OCgCXAgABAAgJBB/OCgCXAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAAALgAECgYJEgAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAAALgAECgYJDQAAAA==.Heyokagi:BAABLgAECn8mAAQhAAgJER9vBABnAgAhAAgJER9vBABnAgAfAAIJ1BS5JgBnAAAJAAEJXwiPrwAsAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECggJGQACABcgAA==.Hordkilla:BAABLgAECn8cAAILAAgJtwV4jAAMAQALAAgJtwV4jAAMAQAAAA==.Hownowbrncw:BAABLgAECn8YAAILAAYJFxyGVQCAAQALAAYJFxyGVQCAAQAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn8kAAMZAAgJvRmlJgDqAQAZAAgJWhmlJgDqAQAiAAEJphoFIABOAAAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAAALgAECgQJCAAAAA==.',
Im='Imathdal:BAABLgAECn8jAAIjAAgJ1w0ZDABUAQAjAAgJ1w0ZDABUAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAKAAAAAA==.Insoniacyun:BAAALgAECgUJCAAAAA==.',
Is='Iselian:BAAALgAECggJHwAAAQ==.Ishanu:BAABLgAECn8YAAIFAAgJNx3tDAA1AgAFAAgJNx3tDAA1AgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAKAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgADCgkJGgABLgADCggJDgAKAAAAAA==.Jax:BAACLgAFFH8NAAINAAQJRCLrHQCJAQANAAQJRCLrHQCJAQAuAAQKfykAAg0ACAlFIxATADUDAA0ACAlFIxATADUDAAAA.',
Jb='Jblockiv:BAAALgADCgUJBQAAAA==.Jbprimero:BAAALgADCgUJBQAAAA==.Jbshami:BAABLgAECn8jAAMWAAYJKSFoGAAyAgAWAAYJKSFoGAAyAgAXAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgQJBQAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn8rAAIeAAgJgguBBABrAQAeAAgJgguBBABrAQAAAA==.Jetfires:BAABLgAECn8wAAIRAAkJ6RpBEwBuAgARAAkJ6RpBEwBuAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAAALgAECgQJDgAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jozhua:BAAALgAECgMJBgAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.',
Ka='Kaedren:BAAALgADCgkJFgAAAA==.Kaelaya:BAABLgAECn8YAAIjAAYJFAnaFQDJAAAjAAYJFAnaFQDJAAAAAA==.Kaelorien:BAABLgAECn8rAAIcAAgJpRBFIQCQAQAcAAgJpRBFIQCQAQAAAA==.Kaetta:BAABLgAECn8WAAINAAcJrQPjrwDlAAANAAcJrQPjrwDlAAAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgUJCAAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAAALgAECgEJAQAAAA==.Kaldevayn:BAAALgAECgMJAwAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgIJAgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8bAAIZAAYJsAwldADlAAAZAAYJsAwldADlAAAAAA==.Kardanis:BAABLgAECn8iAAIWAAgJcyXLAgBXAwAWAAgJcyXLAgBXAwAAAA==.Kashe:BAAALgAECgUJDgAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAABLgAECn8iAAIWAAgJmRGLOQBoAQAWAAgJmRGLOQBoAQAAAA==.Kaydencia:BAAALgAECgYJEQAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgMJAwAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgADCgMJAwAAAA==.',
Ki='Ki:BAAALgAECgQJBAAAAA==.Kiddow:BAAALgAECgQJCQAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgADCgkJDAAAAA==.Kiri:BAAALgADCgkJEAAAAA==.Kitamii:BAABLgAECn8UAAIhAAYJdRbHEQCQAQAhAAYJdRbHEQCQAQAAAA==.Kivrin:BAAALgAECgUJCgAAAA==.',
Kr='Kringlë:BAABLgAECn8hAAIRAAkJhSASDACvAgARAAkJhSASDACvAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kushwizard:BAAALgADCgQJBQAAAA==.',
Ky='Kymma:BAABLgAECn8jAAILAAYJqQ0XkwABAQALAAYJqQ0XkwABAQAAAA==.Kyunix:BAAALgADCgYJDAAAAA==.',
La='Lagoriatsua:BAABLgAECn8XAAIXAAgJYgahOQD3AAAXAAgJYgahOQD3AAAAAA==.Laitue:BAAALgAECgQJCQAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgIJAwAAAA==.Lazengann:BAABLgAECn8YAAMZAAgJbxMJWAAtAQAZAAgJBhMJWAAtAQAaAAEJvxboagA7AAAAAA==.',
Le='Leafbane:BAAALgADCgEJAQAAAA==.Legevia:BAAALgAECgUJDQAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAABLgAECn8qAAILAAgJoBCjUwCFAQALAAgJoBCjUwCFAQAAAA==.Letifer:BAAALgADCgkJCgAAAA==.Leucetios:BAAALgADCgkJFAAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8bAAIIAAkJPhldCACdAgAIAAkJPhldCACdAgAAAA==.Lightbeard:BAAALgAECgUJEAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAAALgAECgYJEwAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgADCgkJFwAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lorredain:BAAALgADCgkJEwAAAA==.Lothwen:BAAALgAECgMJAwAAAA==.Louisachan:BAAALgADCgUJBQAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8LAAIIAAQJkxNRDgARAQAIAAQJkxNRDgARAQAuAAQKfycAAggACQmTFJMsAJQBAAgACQmTFJMsAJQBAAAA.Luxinine:BAABLgAECn8XAAIFAAYJeh8sGACyAQAFAAYJeh8sGACyAQAAAA==.',
Ly='Lyon:BAAALgADCgMJBAAAAA==.Lyshai:BAAALgADCgUJCAABLgAECgUJFAAkALEgAA==.',
Ma='Madhawi:BAAALgAECgUJCwAAAA==.Magamon:BAABLgAECn8iAAINAAgJURe2RgDEAQANAAgJURe2RgDEAQAAAA==.Mahndarb:BAAALgAECgMJBgABLgAECggJFwAIACsPAA==.Majima:BAAALgAECgYJDgAAAA==.Malfuriia:BAABLgAECn8UAAIWAAUJOxdDQQBGAQAWAAUJOxdDQQBGAQAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Margerdria:BAAALgAECgUJDQAAAA==.Maskelle:BAABLgAECn8dAAIiAAYJ0g75EADoAAAiAAYJ0g75EADoAAAAAA==.Mauugrim:BAABLgAECn8cAAIPAAYJhwdvnADmAAAPAAYJhwdvnADmAAAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAAALgAECgUJEAAAAA==.',
Me='Mearadan:BAAALgAECggJDQAAAA==.Meatsweats:BAAALgAECgYJCwAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDgAAAA==.Mekh:BAABLgAECn8UAAMkAAUJsSCJBwB9AQAkAAUJsSCJBwB9AQAlAAEJVQjQSwAqAAAAAA==.Mel:BAAALgAECgMJBAAAAA==.Melanara:BAABLgAECn8vAAINAAgJ6QyxZwBtAQANAAgJ6QyxZwBtAQAAAA==.Melstrom:BAAALgAECgMJAwAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgUJBgAAAA==.Meticuluslyn:BAAALgADCgYJBgAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAAALgAECggJDgAAAA==.Miyävii:BAABLgAECn8XAAIYAAgJ3xT+EgBAAQAYAAgJ3xT+EgBAAQAAAA==.',
Mj='Mjsage:BAABLgAECn8fAAIRAAgJ0h4aHwAdAgARAAgJ0h4aHwAdAgAAAA==.',
Mm='Mmeow:BAAALgAECgEJAQABLgAECggJDQAKAAAAAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8TAAIFAAUJRxYnMAAJAQAFAAUJRxYnMAAJAQAAAA==.Moonflowers:BAACLgAFFH8VAAIJAAUJuhuJDwCIAQAJAAUJuhuJDwCIAQAuAAQKfykAAgkACAmNJCIGACIDAAkACAmNJCIGACIDAAAA.Mordsevoker:BAAALgAFFAEJAQABLgAFFAQJEAAPAL8RAA==.Morginoth:BAAALgADCgcJBwAAAA==.Mousekee:BAABLgAECn8XAAIIAAYJIgyPLAAdAQAIAAYJIgyPLAAdAQAAAA==.',
Mu='Murdrmitts:BAAALgAECgYJEQAAAA==.Mustikka:BAAALgAECgQJDwAAAA==.',
My='Myuriyanka:BAABLgAECn8mAAMXAAgJMhM/KQBOAQAXAAgJMhM/KQBOAQAWAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgUJBgAKAAAAAA==.',
Na='Naahommii:BAABLgAECn8ZAAIRAAgJ/RUDPQCXAQARAAgJ/RUDPQCXAQAAAA==.Nachtpranke:BAAALgAECgYJEQAAAA==.Nadron:BAAALgAECgIJAgAAAA==.Nagualli:BAAALgADCgkJDwAAAA==.',
Ne='Negargra:BAABLgAECn8aAAMCAAYJvg+mgAD7AAACAAYJvg+mgAD7AAAmAAEJcgMufAAkAAAAAA==.Nephadin:BAAALgAECgMJAwAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgUJCAAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAAALgAECgYJDgAAAA==.Nikooli:BAAALgAECgUJDwAAAA==.',
No='Nokkoh:BAAALgADCgQJBAAAAA==.Noodledragon:BAAALgAECgYJBgAAAA==.Noopsie:BAABLgAECn8VAAIJAAUJzAzyXgDUAAAJAAUJzAzyXgDUAAAAAA==.Nooterllus:BAAALgADCgYJCQABLgAECgMJBgAKAAAAAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMQAAgJxxqdDgAsAgAQAAcJLxydDgAsAgAFAAcJsBzpHACIAQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8UAAILAAUJ7xIemQD2AAALAAUJ7xIemQD2AAAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMeAAkJbgM/EgCgAAANAAkJWQPzqwDsAAAeAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBAAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCgYJDAAAAA==.Olympia:BAABLgAECn8kAAIYAAgJIw7BGAAAAQAYAAgJIw7BGAAAAQAAAA==.',
On='Ontai:BAAALgADCgkJFAAAAA==.',
Or='Oraclemega:BAABLgAECn8ZAAINAAcJYAhokgAaAQANAAcJYAhokgAaAQAAAA==.',
Os='Oscarmikey:BAACLgAFFH8RAAMJAAQJ1AcHJADvAAAJAAQJ1AcHJADvAAAbAAEJhAGMNgAvAAAuAAQKfyMABQkACAlFG3YhAPYBAAkACAlFG3YhAPYBABsABAmICtBTAGUAACEAAQlMAj46ACMAAB8AAQkAAO5RAAAAAAAA.',
Ot='Ottoshot:BAABLgAECn8UAAIRAAUJ3RBQeQDtAAARAAUJ3RBQeQDtAAAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
['Oö']='Oöps:BAAALgAECgUJCAAAAA==.',
Pa='Panamone:BAAALgAECgUJEwAAAA==.Pandeism:BAABLgAECn8XAAIgAAYJbRN5EgAUAQAgAAYJbRN5EgAUAQAAAA==.Patrin:BAABLgAECn8XAAINAAYJHgqXowD7AAANAAYJHgqXowD7AAAAAA==.Paulee:BAAALgADCgEJAQAAAA==.',
Pe='Peanutbritle:BAABLgAECn8iAAIMAAgJSwZpJQDSAAAMAAgJSwZpJQDSAAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.Pesch:BAAALgAECgkJEQAAAA==.',
Ph='Phantdoom:BAAALgAECgYJCwAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAFFAIJBAAKAAAAAA==.',
Pl='Plsdiddyno:BAAALgAECgIJAgAAAA==.',
Po='Pogmothoin:BAAALgAECgMJAwAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Punchabaal:BAAALgAECgYJCwAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAIJAAcJWRnvMwDZAQAJAAcJWRnvMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgMJAwAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAQJEAANALoiAA==.Reyrocko:BAAALgAECgEJAQAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAMJCQAFAF0dAA==.Rezshift:BAABLgAECn8bAAMbAAgJwhzADQAsAgAbAAgJwhzADQAsAgAJAAQJBRbtbwAFAQABLgAFFAMJCQAFAF0dAA==.Rezvoid:BAACLgAFFH8JAAMFAAMJXR0qFAAJAQAFAAMJXR0qFAAJAQAIAAIJgyHdFgC0AAAuAAQKfy8AAgUACQmeIpIDAPgCAAUACQmeIpIDAPgCAAAA.',
Rh='Rhage:BAAALgAECgMJBAAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAAALgAECgcJEgAAAA==.Roxane:BAABLgAECn8dAAIbAAgJbwhHMwDyAAAbAAgJbwhHMwDyAAAAAA==.',
Ru='Runningelk:BAABLgAECn8oAAIfAAgJ2RNwDwB9AQAfAAgJ2RNwDwB9AQAAAA==.Runscapemain:BAABLgAECn8fAAILAAgJuxZXSACkAQALAAgJuxZXSACkAQAAAA==.',
Ry='Ryeti:BAAALgADCggJCAAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDAAaAAEkAA==.',
Sa='Saintulrick:BAAALgAECgEJAQAAAA==.Sajuice:BAACLgAFFH8HAAIjAAUJPwUgDwD1AAAjAAUJPwUgDwD1AAAuAAQKfyYAAiMACAnAGzEGAO8BACMACAnAGzEGAO8BAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn8YAAIIAAYJYguWMQD7AAAIAAYJYguWMQD7AAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAKAAAAAA==.',
Se='Seeyen:BAACLgAFFH8OAAIRAAQJDhfjGwBDAQARAAQJDhfjGwBDAQAuAAQKfyoAAhEACQmQHgUHAB8DABEACQmQHgUHAB8DAAAA.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8eAAIkAAgJ4wneCABVAQAkAAgJ4wneCABVAQAAAA==.Seren:BAAALgAECgYJBgAAAA==.Serenityhate:BAAALgAECgYJEAAAAA==.',
Sh='Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgEJAQAAAA==.Shandrilyn:BAAALgAECgYJCgAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAIlAAkJwhSNEgBUAQAlAAkJwhSNEgBUAQAAAA==.',
Si='Sini:BAAALgAFFAcJBAAAAA==.Sinthoras:BAAALgAECgQJBAAAAA==.',
Sk='Skala:BAABLgAECn8UAAInAAgJKxYLHAClAQAnAAgJKxYLHAClAQAAAA==.Skibbie:BAACLgAFFH8UAAMkAAUJXw5oAwAgAQAkAAQJfQhoAwAgAQAnAAUJ/A0NHQAeAQAuAAQKfxgAAycACQk8Fl8QAHMCACcACQk8Fl8QAHMCACQABQnOBpAsALcAAAAA.Skibbward:BAABLgAECn8yAAQfAAgJTiS4AQAyAwAfAAgJTiS4AQAyAwAbAAUJxQ9jVADUAAAJAAYJ6QrsggDSAAABLgAFFAUJFAAkAF8OAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAAALgAECgcJDAAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgEJAgAAAA==.',
Sm='Smackdogg:BAABLgAECn8ZAAIbAAcJPR0XHQAYAgAbAAcJPR0XHQAYAgABLgAFFAgJJwAXAGkdAA==.',
So='Solteria:BAABLgAECn8VAAIDAAcJqAk/DgBOAQADAAcJqAk/DgBOAQAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAAALgAECgUJDAAAAA==.Sorvina:BAABLgAECn8vAAICAAkJMBE+NADIAQACAAkJMBE+NADIAQAAAA==.Soulflame:BAABLgAECn8tAAINAAgJPAq3cwBTAQANAAgJPAq3cwBTAQAAAA==.Soulshifter:BAABLgAECn8XAAIbAAYJWgu4OADXAAAbAAYJWgu4OADXAAAAAA==.Soultrader:BAAALgADCggJEQABLgAECgUJEAAKAAAAAA==.',
Sp='Spooñ:BAAALgADCgcJBwAAAA==.Spottedcoat:BAABLgAECn8iAAIJAAgJaQOqbACrAAAJAAgJaQOqbACrAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgAAAA==.Stregnor:BAABLgAECn8qAAIRAAgJJRM/NgCxAQARAAgJJRM/NgCxAQAAAA==.Stygy:BAAALgAECgMJAwAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDAAaAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn8qAAMdAAgJ2ROkGwCBAQAdAAgJ2ROkGwCBAQAUAAQJ7QqMZQCrAAAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMnAAkJDxKrEwBHAgAnAAkJfhGrEwBHAgAkAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECggJGAAnAFUVAA==.Tachie:BAABLgAECn8YAAMnAAgJVRWEJwBPAQAnAAgJjhOEJwBPAQAkAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAUJEwADACgmAA==.Taele:BAABLgAECn8hAAMNAAgJ3Bp+SwC2AQANAAcJihp+SwC2AQAeAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn8yAAIbAAkJ9AytHwBvAQAbAAkJ9AytHwBvAQAAAA==.Tamalpais:BAAALgAECgUJCAAAAA==.Tamarind:BAAALgADCgkJCQABLgAECggJIgAgAEMfAA==.Tanya:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8UAAIRAAUJtQNDmQChAAARAAUJtQNDmQChAAAAAA==.',
Th='Thaesan:BAAALgAECgUJCAAAAA==.Therin:BAABLgAECn8rAAIVAAgJjBWMEQDaAQAVAAgJjBWMEQDaAQAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgYJDAAAAA==.Toofast:BAABLgAECn8eAAIWAAYJTiTPFwA3AgAWAAYJTiTPFwA3AgAAAA==.Toofurrious:BAAALgADCgkJJQAAAA==.Topswimmer:BAAALgAECgQJCAAAAA==.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgQJBQAAAA==.',
Tr='Trifus:BAAALgAECgYJDQAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAAALgAECgUJDAAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQAAAA==.',
Tu='Tulao:BAABLgAECn8ZAAINAAYJrA8OpwD0AAANAAYJrA8OpwD0AAAAAA==.',
Tw='Twan:BAAALgAECgYJBgABLgAFFAUJDwAZAOcbAA==.',
Ty='Tyrionel:BAAALgAECgUJCQAAAA==.',
Tz='Tzitzimitl:BAAALgADCgkJCQAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIcAAQJaRBJGAADAQAcAAQJaRBJGAADAQAAAA==.',
Ut='Utheli:BAACLgAFFH8GAAILAAIJ9A9/WQCeAAALAAIJ9A9/WQCeAAAuAAQKfx4AAgsACAkBG+syAO0BAAsACAkBG+syAO0BAAAA.',
Va='Vaevictis:BAAALgADCgMJAwABLgAECgYJGwAFALQXAA==.Vaildora:BAAALgAECgEJAQABLgAECggJGAAnAFUVAA==.Valdra:BAABLgAECn8rAAIEAAgJ7BDPEwBiAQAEAAgJ7BDPEwBiAQAAAA==.',
Vi='Viralprepped:BAAALgAECgMJBAAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8ZAAIZAAkJ6g7xNwCaAQAZAAkJ6g7xNwCaAQAAAA==.',
Vn='Vnasty:BAACLgAFFH8KAAILAAQJeg4YKAAxAQALAAQJeg4YKAAxAQAuAAQKfyUAAgsACQnPHykKAD8DAAsACQnPHykKAD8DAAAA.',
Vr='Vrale:BAAALgAECgEJAwAAAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wilken:BAABLgAECn8bAAIoAAgJ4RU4DADPAQAoAAgJ4RU4DADPAQAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8iAAILAAgJnBxzKAAXAgALAAgJnBxzKAAXAgAAAA==.',
Ws='Wspr:BAAALgAECgIJBAAAAA==.',
Xa='Xaartahli:BAAALgAECgQJBwAAAA==.Xavencia:BAAALgAECgYJDwAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECgIJAgAAAA==.',
Ya='Yanut:BAAALgAECgYJDgAAAA==.',
Ye='Yeetjin:BAAALgAECgMJAgAAAA==.',
Yi='Yinamin:BAAALgAECgYJEAAAAA==.',
Yk='Yknub:BAAALgADCgYJCQAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAAALgAECgYJEQAAAA==.Zalanto:BAAALgADCggJDgAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn8rAAIRAAgJDA9hRAB8AQARAAgJDA9hRAB8AQAAAA==.',
Ze='Zelgaddis:BAABLgAECn8iAAMWAAgJ8BMvMwCIAQAWAAcJ1BMvMwCIAQAgAAIJTQRdJwAwAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn8WAAInAAYJLw3cPADiAAAnAAYJLw3cPADiAAAAAA==.',
Zr='Zriana:BAAALgADCgkJFwAAAA==.',
Zs='Zsarilya:BAABLgAECn8dAAIIAAYJcQLqPACyAAAIAAYJcQLqPACyAAAAAA==.',
Zu='Zurgen:BAABLgAECn8rAAICAAgJbR/6FwBbAgACAAgJbR/6FwBbAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8qAAIJAAgJFBFJKwC1AQAJAAgJFBFJKwC1AQABLgAFFAQJCwAIAJMTAA==.',
['Ýu']='Ýui:BAAALgADCgQJBAAAAA==.',
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
