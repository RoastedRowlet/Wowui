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

local lookup = {'Evoker-Preservation','Mage-Frost','DemonHunter-Devourer','Druid-Balance','Evoker-Augmentation','Priest-Shadow','Priest-Discipline','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','Unknown-Unknown','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Mage-Arcane','Monk-Brewmaster','Warrior-Arms','Warrior-Fury','Rogue-Assassination','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Druid-Feral','Druid-Guardian','Shaman-Restoration','Warlock-Destruction','Evoker-Devastation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abdervoke:BAABLgAECn8dAAIBAAcJcSPFAwDAAgABAAcJcSPFAwDAAgAAAA==.Absent:BAAALgADCgEJAQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aethos:BAAALgAECgkJBQAAAA==.',
Al='Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8yAAICAAkJ3iHCCAAJAwACAAkJ3iHCCAAJAwAAAA==.Alistus:BAACLgAFFH8FAAIDAAMJ6iMJIgBAAQADAAMJ6iMJIgBAAQAuAAQKfzQAAgMACAm9JGkIANcCAAMACAm9JGkIANcCAAAA.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJCQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAABLgAECn8pAAIEAAcJwg52LQASAQAEAAcJwg52LQASAQAAAA==.',
Ar='Arcanegarm:BAABLgAECn8ZAAICAAYJNwKM1ACiAAACAAYJNwKM1ACiAAAAAA==.Archeyois:BAABLgAECn8mAAMFAAkJLQ5zIQB8AQAFAAkJLQ5zIQB8AQABAAUJhQIRNwCzAAAAAA==.Armitage:BAAALgAECggJDwAAAA==.Arnaya:BAAALgADCgEJAQAAAA==.Arthonos:BAACLgAFFH8GAAIGAAIJVAVEIQCEAAAGAAIJVAVEIQCEAAAuAAQKfzUAAwYACQmbFUAPABcCAAYACQmbFUAPABcCAAcACAnjBWQnAFoBAAAA.Arugall:BAAALgAECgQJBAAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Averille:BAAALgADCgYJCwAAAA==.',
Ay='Ayraa:BAAALgADCgkJDQAAAA==.',
Az='Azerphage:BAAALgAECgYJDgAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAAALgAECgQJCwAAAA==.Azzog:BAAALgAECgUJDAAAAA==.',
Ba='Baindyn:BAAALgAECgQJDAAAAA==.Barator:BAAALgAECgQJCAAAAA==.Bas:BAAALgAECgUJCQAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJDAAAAA==.',
Bl='Blackröse:BAABLgAECn8hAAIIAAcJgx6XDwDyAQAIAAcJgx6XDwDyAQAAAA==.Bladebane:BAABLgAECn8XAAIJAAgJmwCxNgBnAAAJAAgJmwCxNgBnAAAAAA==.Blandmonk:BAAALgADCgkJBQAAAA==.Blksunshine:BAAALgAECgQJCAAAAA==.',
Bo='Bolash:BAAALgAECgQJCAAAAA==.Bort:BAAALgAECgEJBAAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgQJBwAAAA==.',
Bu='Bulvhine:BAABLgAECn8UAAIKAAYJLx3JTwCPAQAKAAYJLx3JTwCPAQAAAA==.',
Ca='Camford:BAAALgAECgcJEAAAAA==.Cantatrix:BAAALgAECgYJCgAAAA==.Capslok:BAAALgAECgQJBwAAAA==.Captinmeat:BAAALgAECgIJAgAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgABLgAECggJCgALAAAAAA==.',
Ce='Cecilx:BAABLgAECn8gAAIMAAgJgiPdBAAMAwAMAAgJgiPdBAAMAwAAAA==.Cellybelleri:BAAALgADCgUJCAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Chimerax:BAACLgAFFH8JAAMNAAMJQBiKAwD1AAANAAMJUROKAwD1AAAOAAEJlxfliABQAAAuAAQKfy0AAw0ACQljHwACALACAA0ACAlCIgACALACAA4ACAk/E2dZAFMBAAAA.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIKAAgJMAZ/mwDzAAAKAAgJMAZ/mwDzAAAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAABLgAECn8oAAMDAAkJnRngHgAXAgADAAkJnRngHgAXAgAPAAMJiATNWQB9AAAAAA==.',
Cl='Clairíty:BAABLgAECn8bAAIQAAYJYiG4EAAXAgAQAAYJYiG4EAAXAgAAAA==.Clarky:BAAALgAECgUJCwAAAA==.Click:BAABLgAECn8oAAIRAAcJkBUANwCuAQARAAcJkBUANwCuAQAAAA==.Cloutfarmer:BAACLgAFFH8FAAIRAAIJGBqkQgC0AAARAAIJGBqkQgC0AAAuAAQKfzgAAxEACQlEJZoBAF0DABEACQlEJZoBAF0DABIABglKG1spAOABAAAA.',
Co='Comadore:BAACLgAFFH8GAAIKAAMJZAadRwDRAAAKAAMJZAadRwDRAAAuAAQKfxwAAgoACAk4HNg4AEACAAoACAk4HNg4AEACAAAA.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEBLgAECn8VAAITAAkJNCIEAwBOAwATAAkJNCIEAwBOAwABLgADCgYJBgALAAAAAA==.',
Cy='Cylithina:BAAALgAECgQJBwAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Daphe:BAAALgAECgEJAgAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAQAAAA==.Deathslead:BAAALgAECggJEgAAAA==.Decrepe:BAACLgAFFH8GAAIUAAIJcBJGOQCJAAAUAAIJcBJGOQCJAAAuAAQKfzkAAhQACQnxH+QGABIDABQACQnxH+QGABIDAAAA.Delph:BAAALgAECgcJEQAAAA==.Desomas:BAAALgAECgIJAgAAAA==.',
Di='Discostar:BAABLgAECn8eAAMUAAcJIBWkPQBUAQAUAAcJIBWkPQBUAQAEAAQJORAsOgDQAAAAAA==.Distill:BAAALgAECgEJAQABLgAFFAgJFgAVAO0gAA==.',
Do='Dominicm:BAAALgAECgYJEQAAAA==.Dotdotdis:BAAALgAECgMJAwAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgQJCAAAAA==.Druth:BAABLgAECn8lAAIWAAgJ0x21CQAPAgAWAAgJ0x21CQAPAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgQJCQAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einark:BAABLgAECn8pAAMTAAcJFCDQDQBaAgATAAcJFCDQDQBaAgAXAAEJNBbeeAA5AAAAAA==.',
Ek='Ekiim:BAAALgAECgQJBAAAAA==.',
El='Eldrond:BAAALgAECgQJCAAAAA==.Elinis:BAAALgAECgYJBgAAAA==.Elska:BAAALgADCgkJCQAAAA==.',
En='Ennauríon:BAAALgAECgQJBAAAAA==.Entropy:BAEALgAECgYJBgABLgAECggJJAAYACUXAA==.',
Er='Eridor:BAAALgAECgYJDAAAAA==.',
Ex='Exek:BAABLgAECn8dAAMQAAYJfhSUKQAwAQAQAAYJfhSUKQAwAQAGAAMJhgKxVABXAAAAAA==.',
Fa='Fabaztard:BAABLgAECn8XAAIEAAcJ1xBaJwA3AQAEAAcJ1xBaJwA3AQAAAA==.Faline:BAABLgAECn8qAAIUAAgJ5wqEQgA9AQAUAAgJ5wqEQgA9AQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8JAAIDAAMJPhWqOwDrAAADAAMJPhWqOwDrAAAuAAQKfyMAAgMACQlTGs00ACUCAAMACQlTGs00ACUCAAAA.Fenrakar:BAAALgAECgQJBwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn8uAAIMAAgJbCD8BwDJAgAMAAgJbCD8BwDJAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJCAAAAA==.Foxknight:BAAALgAECgQJDAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgALAAAAAA==.',
Ft='Ftx:BAABLgAECn8gAAMZAAgJuh+oDQC4AgAZAAgJlR+oDQC4AgAXAAQJ2hm/RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAIKAAkJARxaHwBHAgAKAAkJARxaHwBHAgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaidan:BAACLgAFFH8IAAIEAAUJAQpoGQAGAQAEAAUJAQpoGQAGAQAuAAQKfx4AAgQACQk9FogRAI8CAAQACQk9FogRAI8CAAEuAAUUBQkJAAMAzAUA.Gameslayer:BAABLgAECn8dAAMaAAcJDh3wHQAQAQAaAAQJzxfwHQAQAQAbAAQJByDEPAABAQAAAA==.Gankzilla:BAACLgAFFH8JAAMcAAMJzAllCwBUAAAVAAIJ6AYPJACKAAAcAAEJlA9lCwBUAAAuAAQKfyMAAxwACQmeG2EJAKoBABUABgnhF9klAMoBABwABwkfG2EJAKoBAAAA.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Genrealwee:BAAALgAECgEJAQAAAA==.Get:BAAALgADCgkJDAAAAA==.',
Gh='Ghalumvhar:BAAALgAECgYJEQAAAA==.Ghrìmm:BAABLgAECn8jAAQRAAgJdBAwRAB9AQAIAAgJQg0+GACUAQARAAgJww4wRAB9AQASAAEJ+QavMwAmAAAAAA==.',
Gi='Gila:BAAALgAECgUJBwAAAA==.Gingasorrow:BAABLgAECn8fAAIUAAcJDhfGJgDSAQAUAAcJDhfGJgDSAQAAAA==.Gizzle:BAACLgAFFH8HAAIKAAMJFgziQgDlAAAKAAMJFgziQgDlAAAuAAQKfyYAAgoACQmoFgkzAOwBAAoACQmoFgkzAOwBAAAA.',
Gr='Greekfire:BAABLgAECn8YAAIMAAgJ4CE5GwA7AgAMAAgJ4CE5GwA7AgAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn8rAAIRAAcJqCF6HwBIAgARAAcJqCF6HwBIAgAAAA==.',
Ha='Hanjha:BAABLgAECn8mAAMIAAcJ+RLoGQCEAQAIAAYJ+RLoGQCEAQARAAEJAAA7zwA3AAAAAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgQJEQALAAAAAA==.Helldozer:BAABLgAECn8uAAIdAAcJBhOULAA5AQAdAAcJBhOULAA5AQAAAA==.',
Ho='Hooj:BAAALgADCgYJBgAAAA==.Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAAALgAECgEJAwAAAA==.',
Hw='Hwore:BAAALgAECgQJBAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgALAAAAAA==.Hypnocide:BAEBLgAECn8nAAIDAAcJTRPbcADtAAADAAcJTRPbcADtAAAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
['Hü']='Hüngry:BAABLgAECn8mAAIVAAkJLR1tEgCJAgAVAAkJLR1tEgCJAgAAAA==.',
Ib='Ibuki:BAAALgAECgUJCAABLgAFFAMJCQAMALIGAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Il='Illandren:BAACLgAFFH8GAAIIAAIJoQdhHACaAAAIAAIJoQdhHACaAAAuAAQKfxoAAwgACQljCysTAMcBAAgACQljCysTAMcBABIACAk0AxMXALwAAAAA.',
Im='Impsane:BAAALgAECgkJCwAAAA==.',
In='Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8jAAICAAcJsQiMjwAfAQACAAcJsQiMjwAfAQAAAA==.Innøminate:BAAALgAECgUJCAABLgAECgYJFgAUABQgAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQcAAgJlBqxBAD4AQAcAAgJ5RmxBAD4AQAVAAUJoxxSMwBwAQAeAAQJjg9mCQDZAAAAAA==.',
Is='Isadavrah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgMJBAAAAA==.Issadin:BAAALgAECgUJBAAAAA==.Issadruiid:BAAALgADCgYJBgABLgAECgUJBAALAAAAAA==.',
Ja='Jaxxa:BAABLgAECn8iAAIRAAgJCRaQNAC3AQARAAgJCRaQNAC3AQAAAA==.',
Je='Jeddiah:BAABLgAECn8aAAIcAAcJ/QqwDAAdAQAcAAcJ/QqwDAAdAQAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jinkès:BAAALgAECgUJEAAAAA==.',
Jp='Jpank:BAAALgAFFAEJAgAAAA==.',
Ju='Jubei:BAABLgAFFH8FAAIKAAQJQw9/SADMAAAKAAQJQw9/SADMAAAAAA==.Judis:BAABLgAECn9BAAIcAAgJhxjvBADtAQAcAAgJhxjvBADtAQAAAA==.Juicy:BAAALgADCgIJAgAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8bAAIXAAkJkh8wBADeAgAXAAkJkh8wBADeAgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgYJCQAAAA==.Kanajotoma:BAAALgAECgQJDAAAAA==.Karlai:BAABLgAECn8gAAIfAAcJuBrlBAAAAgAfAAcJuBrlBAAAAgABLgAFFAUJCQADAMwFAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAAALgAECgEJAQAAAA==.Keleena:BAEBLgAECn8pAAIMAAcJLSDCFAAcAgAMAAcJLSDCFAAcAgAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Ki='Kinst:BAABLgAECn8pAAMRAAcJCRwRNwCtAQARAAcJCRwRNwCtAQASAAYJrxLOFQDKAAAAAA==.Kisäi:BAABLgAECn8lAAIDAAkJ1RxbIACPAgADAAkJ1RxbIACPAgAAAA==.Kitanyia:BAAALgAECggJEgAAAA==.Kittiy:BAABLgAECn8gAAMUAAYJbQXuZwC4AAAUAAYJbQXuZwC4AAAEAAYJCQJqUgBqAAAAAA==.',
Ko='Kordelia:BAABLgAECn8hAAICAAgJUh5bJABMAgACAAgJUh5bJABMAgAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgQJBAABLgAECgQJCAALAAAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAABLgAECn8iAAMNAAcJaBrLBgDrAQANAAYJ3xvLBgDrAQAOAAcJRBSmewAFAQAAAA==.',
La='Lamanira:BAAALgAECgQJCAAAAA==.Lancier:BAAALgAECgQJCAAAAA==.',
Le='Lecleme:BAABLgAECn8VAAIgAAgJ4hLseAAoAQAgAAgJ4hLseAAoAQAAAA==.Lejend:BAABLgAECn8rAAMaAAgJLyMfAwC2AgAaAAgJLyMfAwC2AgAbAAMJfRW8fwC+AAAAAA==.Lenthalis:BAAALgAECgUJDAAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECgYJCgAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAFAOcLAA==.Lockheéd:BAAALgAECgQJBAAAAA==.Lonelyhearts:BAABLgAECn8eAAIKAAcJGAY5lgD8AAAKAAcJGAY5lgD8AAAAAA==.Lonestar:BAAALgAECgYJDwAAAA==.Lonestarr:BAAALgAECgQJDAAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAIQAAkJ8A7oHQCMAQAQAAkJ8A7oHQCMAQAAAA==.',
Ly='Lytol:BAAALgAECgYJEgAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAECgkJMQAFAC4dAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maenad:BAAALgAECggJCgAAAA==.Maeple:BAABLgAECn8YAAIQAAgJ9Bx3CQCIAgAQAAgJ9Bx3CQCIAgAAAA==.Magikin:BAAALgAECgQJBgAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8QAAMIAAUJxR+LAQDOAQAIAAQJlCaLAQDOAQASAAEJjAS6JABVAAAuAAQKfxcAAwgABwmMJXMEANQCAAgABwkxJXMEANQCABIAAQksIwR3AGMAAAEuAAUUCAkfAAIAuCMA.',
Me='Mechagnome:BAACLgAFFH8GAAIXAAIJoBvNGQCpAAAXAAIJoBvNGQCpAAAuAAQKfzQAAxcACQnTIMADAOsCABcACQnTIMADAOsCABMACAkJBAU6AAABAAAA.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMKAAYJkhbKegCEAQAKAAYJEhbKegCEAQAhAAQJTQnMJwCHAAAAAA==.Meigna:BAABLgAECn8iAAIGAAgJwhnlEQD2AQAGAAgJwhnlEQD2AQAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8fAAIiAAUJaSKBAQCVAQAiAAUJaSKBAQCVAQAuAAQKfygAAyIABwlnJlYDAAMDACIABwlnJlYDAAMDACMABQnrI28NAJ4BAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAAALgAECgUJDAAAAA==.Merelandra:BAAALgADCgcJEAAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Miliara:BAAALgADCgEJAQAAAA==.Missmaam:BAAALgAECgUJDAAAAA==.Mithrandir:BAAALgAFFAEJAQAAAA==.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAABLgAECn8aAAMWAAkJkRufCAAnAgAWAAkJkRufCAAnAgAbAAIJ6xAGlABvAAAAAA==.',
Mo='Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudflap:BAAALgAECgYJDgAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAECgkJMQAFAC4dAA==.Muztang:BAABLgAECn8hAAMaAAcJzReWDwCdAQAaAAcJHReWDwCdAQAbAAYJihNyNgAeAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgMJAwAAAA==.',
My='Mythandwel:BAABLgAECn8ZAAIPAAYJJQTlMACeAAAPAAYJJQTlMACeAAAAAA==.',
['Mä']='Mäddiey:BAAALgAECgQJBQAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8IAAIZAAMJBR99GQAYAQAZAAMJBR99GQAYAQAuAAQKfzkAAhkACQngJFMBADwDABkACQngJFMBADwDAAAA.',
Na='Nace:BAABLgAECn8mAAIVAAkJ7BNMEwC1AQAVAAkJ7BNMEwC1AQAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgAECgUJBQAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nateldin:BAABLgAECn8XAAMKAAgJ3wmIkABbAQAKAAgJDgiIkABbAQAhAAIJ9Q7TOwAsAAAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECggJDQAAAA==.Nikiso:BAAALgADCgYJBwAAAA==.',
No='Nocainus:BAABLgAECn8sAAIJAAcJ0x3kCwD5AQAJAAcJ0x3kCwD5AQAAAA==.Nosehole:BAABLgAECn8WAAIkAAYJIAvyXgDUAAAkAAYJIAvyXgDUAAAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQAAAA==.',
['Nø']='Nøtsure:BAABLgAECn8WAAMUAAYJFCDkJAAmAgAUAAYJFCDkJAAmAgAEAAIJqwwvVQBhAAAAAA==.',
Ob='Obsidia:BAABLgAECn8UAAIOAAcJ8QhVjgDgAAAOAAcJ8QhVjgDgAAAAAA==.',
Oc='Octopusprime:BAAALgAECgkJEQAAAA==.',
Ol='Ollix:BAEALgAECgEJAgABLgAECgcJKwADAGwYAA==.',
Om='Omelette:BAABLgAECn8eAAIRAAgJVh2WFgBVAgARAAgJVh2WFgBVAgAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgQJCAALAAAAAA==.',
Op='Ophj:BAABLgAECn8gAAICAAkJtiJjBwCRAwACAAkJtiJjBwCRAwAAAA==.',
Or='Orangejulius:BAAALgAECgIJBwABLgAECgQJBAALAAAAAA==.Orangutan:BAAALgAECgMJBAAAAA==.Oriigami:BAAALgAECgQJBgAAAA==.Orinoheal:BAAALgADCgUJBQAAAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pe='Perilous:BAAALgAECgQJCAAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phoelar:BAAALgAECgEJAgAAAA==.Phuumyn:BAABLgAECn8rAAIXAAcJvyC5CwA7AgAXAAcJvyC5CwA7AgAAAA==.',
Pi='Piccoblast:BAACLgAFFH8UAAICAAYJwhISDQCzAQACAAYJwhISDQCzAQAuAAQKfycAAgIACAnYIuEcAAIDAAIACAnYIuEcAAIDAAAA.Piccopew:BAAALgAECgEJAQABLgAFFAYJFAACAMISAA==.Pichus:BAAALgAECgEJAQAAAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAECgQJBwABLgAFFAMJDAASAKYfAA==.Piickles:BAACLgAFFH8dAAMQAAYJZhdSBgCLAQAQAAUJKBhSBgCLAQAHAAQJiQ/VFgAsAQAuAAQKfx8AAhAABwndItoLAJMCABAABwndItoLAJMCAAAA.Pinkcanibus:BAAALgAECgYJDAAAAA==.Pity:BAAALgAECgcJDwAAAA==.',
Pl='Plutø:BAABLgAECn8vAAMJAAkJPhoMDABRAgAJAAcJaB4MDABRAgAgAAkJtxGsTQCSAQAAAA==.',
Po='Polylocks:BAAALgAECgUJBQAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAEBLgAECn8kAAIYAAgJJRdrAgD0AQAYAAgJJRdrAgD0AQAAAA==.Promethius:BAAALgAECgcJCQABLgAFFAEJAQALAAAAAA==.Protein:BAABLgAECn8gAAIbAAcJ0BV+KABpAQAbAAcJ0BV+KABpAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgALAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn8rAAIUAAgJaByFEACKAgAUAAgJaByFEACKAgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECgUJBQALAAAAAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quilian:BAACLgAFFH8JAAIQAAMJ+iP0CwAtAQAQAAMJ+iP0CwAtAQAuAAQKfyYAAhAACQlAISkEABIDABAACQlAISkEABIDAAAA.',
Ra='Raelynn:BAABLgAECn8sAAIQAAcJdRYxGgCvAQAQAAcJdRYxGgCvAQAAAA==.Raevenhart:BAACLgAFFH8GAAISAAMJlghvEgDEAAASAAMJlghvEgDEAAAuAAQKfx0AAhIACAlYFWIkAAUCABIACAlYFWIkAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgADCgcJBwAAAA==.Raymond:BAAALgADCgcJBwAAAA==.',
Re='Rebarbative:BAABLgAECn8XAAMOAAgJsAu3WwBNAQAOAAgJsAu3WwBNAQAlAAMJfAXZUQB5AAAAAA==.Redvex:BAACLgAFFH8GAAIOAAIJYiMNWADMAAAOAAIJYiMNWADMAAAuAAQKfzsABA4ACQlSJSYDAD0DAA4ACQnzJCYDAD0DACUABQkxII8SALcBAA0AAglwI2wVAKYAAAAA.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn8hAAMKAAgJ1A+xaQBQAQAKAAgJlguxaQBQAQAhAAUJfBXtHQAaAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8qAAIMAAgJAxy4DwBUAgAMAAgJAxy4DwBUAgAAAA==.',
Rh='Rhedman:BAAALgAECgYJDwAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinahrune:BAAALgAECgMJBgAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJDQAAAA==.Roselyn:BAAALgAECgIJAgAAAA==.Rotyr:BAABLgAECn8bAAIHAAYJMxdAGwCaAQAHAAYJMxdAGwCaAQAAAA==.',
Ru='Ruana:BAEALgAECgQJCQAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Saturñ:BAAALgAECgIJAgAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8VAAIRAAYJRR3eQACJAQARAAYJRR3eQACJAQAAAA==.Scubbs:BAACLgAFFH8JAAIkAAMJ4QxjMQC/AAAkAAMJ4QxjMQC/AAAuAAQKfyEAAiQACAkuFkkiABECACQACAkuFkkiABECAAAA.Scubbsboo:BAAALgAECgUJDAABLgAFFAMJCQAkAOEMAA==.',
Se='Servantes:BAABLgAECn8pAAIUAAcJRg/HSQAfAQAUAAcJRg/HSQAfAQAAAA==.',
Sh='Shackleford:BAABLgAECn8mAAMHAAcJfR/lEQAmAgAHAAcJfR/lEQAmAgAQAAEJMRiieQBCAAAAAA==.Shamwõwz:BAAALgAFFAMJBAAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCgAAAA==.Shotya:BAABLgAECn8sAAIRAAcJpApsWAA/AQARAAcJpApsWAA/AQAAAA==.',
Si='Siath:BAABLgAECn8UAAMFAAgJ5wv5LgAkAQAFAAgJ5wv5LgAkAQAmAAIJ6gg7PQA5AAAAAA==.Sixpacktnt:BAAALgADCgcJDQAAAA==.Sixthknight:BAAALgAECgQJBAAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8eAAIMAAgJXyZHAgBbAwAMAAgJXyZHAgBbAwAAAA==.',
Sn='Snarkypony:BAAALgAECgQJCAAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorocide:BAAALgADCgUJBQAAAA==.Sorsere:BAABLgAECn8nAAIOAAcJ9xhGSwB6AQAOAAcJ9xhGSwB6AQAAAA==.',
Sp='Spcecialk:BAABLgAECn8YAAIWAAcJHQrUHgDuAAAWAAcJHQrUHgDuAAAAAA==.Specialk:BAABLgAECn85AAMdAAgJtxL4KgBDAQAdAAcJ+BH4KgBDAQAkAAMJrAZ/fgBnAAAAAA==.',
Sq='Squallie:BAAALgAECgYJDQAAAA==.',
St='Steamedhams:BAAALgAECgMJAwABLgAECgYJDgALAAAAAA==.Stirredihime:BAAALgAECgIJAgAAAA==.Stromm:BAACLgAFFH8JAAIDAAUJzAXJOAD2AAADAAUJzAXJOAD2AAAuAAQKfxcAAgMACAkdFjw8AIoBAAMACAkdFjw8AIoBAAAA.',
Su='Sundorei:BAAALgADCgEJAQAAAA==.',
Ta='Tahoe:BAAALgADCgIJAgAAAA==.Talshekar:BAABLgAECn8XAAImAAcJdgepDAABAQAmAAcJdgepDAABAQAAAA==.Tarsis:BAAALgAECgcJBwAAAA==.',
Te='Teiana:BAABLgAECn8pAAIKAAkJ9x/PEQCeAgAKAAkJ9x/PEQCeAgAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAABLgAECn8eAAIKAAcJMxTfZwBUAQAKAAcJMxTfZwBUAQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAABLgAECn8pAAIUAAkJRhi/FQBSAgAUAAkJRhi/FQBSAgAAAA==.Thordak:BAAALgADCggJDQABLgAECggJGQAKAPgPAA==.',
Ti='Timbuktoo:BAAALgAECgQJBgAAAA==.Tinypoop:BAABLgAECn8WAAICAAYJVBX0fwA7AQACAAYJVBX0fwA7AQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAAALgAECgQJCAAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAABLgAECn8VAAIfAAYJmRC+DgAHAQAfAAYJmRC+DgAHAQAAAA==.Tors:BAABLgAECn89AAIEAAkJzRRyEQD9AQAEAAkJzRRyEQD9AQAAAA==.',
Tr='Trogdore:BAAALgAECgYJDQAAAA==.Trollololo:BAABLgAECn8sAAMCAAcJmRPXWgCMAQACAAcJmRPXWgCMAQAnAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8nAAICAAgJwB18JgBAAgACAAgJwB18JgBAAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgIJAgABLgAECgUJBQALAAAAAA==.',
Tt='Ttaartt:BAACLgAFFH8gAAIBAAYJgRV6BgDjAQABAAYJgRV6BgDjAQAuAAQKfx0AAgEABwmqGfESABICAAEABwmqGfESABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8LAAIcAAMJLBxiBAAJAQAcAAMJLBxiBAAJAQAuAAQKfzkAAhwACQmYJIMAADQDABwACQmYJIMAADQDAAAA.Tyr:BAAALgAECgEJAQAAAA==.Tyrone:BAABLgAECn8hAAMXAAgJ9BuZCwA9AgAXAAgJ9BuZCwA9AgATAAQJABBkTwCPAAAAAA==.',
Uf='Uffish:BAAALgADCgUJBgAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.',
Un='Undeaddemon:BAABLgAECn8jAAQOAAkJIx21JAAOAgAOAAgJIx21JAAOAgANAAMJEQ8THwB4AAAlAAEJkAbJeAAqAAAAAA==.Undeaddh:BAAALgADCgkJAgABLgAECgkJIwAOACMdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIwAOACMdAA==.Undeadscaly:BAAALgAECgUJBQABLgAECgkJIwAOACMdAA==.Undignified:BAABLgAECn8nAAIcAAcJKhJQCQBlAQAcAAcJKhJQCQBlAQAAAA==.Unholysixth:BAAALgADCgcJFgAAAA==.Unicornquen:BAAALgAECgEJAQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgQJCgAAAA==.',
Vi='Vidikan:BAAALgAECgQJDAAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAABLgAECn8rAAMkAAgJxxiuGwAWAgAkAAgJxxiuGwAWAgAdAAcJWRXLHAClAQAAAA==.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8eAAIkAAcJRRyTJQDVAQAkAAcJRRyTJQDVAQAAAA==.',
Vy='Vysena:BAAALgAECgEJAQAAAA==.',
Wa='Waldón:BAABLgAECn8tAAInAAgJuAsUBABeAQAnAAgJuAsUBABeAQAAAA==.',
We='Werrik:BAABLgAECn8WAAIOAAgJ+ST8IgCJAgAOAAgJ+ST8IgCJAgABLgAFFAIJAgALAAAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAIkAAcJPxKVNwByAQAkAAcJPxKVNwByAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJDAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAUJHwAiAGkiAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAAALgAECgcJEQAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.',
Xi='Xilphira:BAAALgAECgEJAQAAAA==.',
Xl='Xlithz:BAABLgAECn8uAAMbAAgJThrCFAD/AQAbAAgJQxrCFAD/AQAaAAgJPhIQEgB9AQAAAA==.',
['Xí']='Xílo:BAEBLgAECn8rAAMDAAcJbBgJPQCHAQADAAcJbBgJPQCHAQAPAAEJ+AfpUAArAAAAAA==.',
Yl='Ylene:BAABLgAECn8WAAIUAAcJWg4nWwDgAAAUAAcJWg4nWwDgAAAAAA==.',
Yo='Yoink:BAACLgAFFH8IAAIgAAMJkQ9baQDjAAAgAAMJkQ9baQDjAAAuAAQKfzAAAiAACQnhIEcIAPwCACAACQnhIEcIAPwCAAAA.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgADCgkJEgAAAA==.Zarinfur:BAABLgAECn8sAAIiAAgJvRaHCQDNAQAiAAgJvRaHCQDNAQAAAA==.Zazikalestra:BAABLgAECn8bAAQBAAgJEBddFwDcAQABAAgJEBddFwDcAQAFAAQJhQSiTwCPAAAmAAEJAAAjPwAzAAAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgQJCAAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAABLgAECn8gAAMRAAcJFRk4OgChAQARAAcJFRk4OgChAQASAAEJ9QCRmQAbAAAAAA==.Zequill:BAABLgAECn8uAAIWAAgJmiJ5BACbAgAWAAgJmiJ5BACbAgAAAA==.Zevsticles:BAABLgAECn8oAAIRAAkJUx/iFQBaAgARAAkJUx/iFQBaAgAAAA==.',
Zh='Zhom:BAACLgAFFH8MAAISAAMJph8dDwD2AAASAAMJph8dDwD2AAAuAAQKfz0AAhIACQnHIdYBAL0CABIACQnHIdYBAL0CAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn8rAAIoAAcJEQ4CEAA7AQAoAAcJEQ4CEAA7AQAAAA==.Zorlak:BAAALgAECgUJDQAAAA==.',
Zy='Zylofeather:BAAALgAECgQJBAAAAA==.',
['ße']='ßeast:BAABLgAECn8VAAIXAAcJiwbwMQDuAAAXAAcJiwbwMQDuAAAAAA==.',
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
