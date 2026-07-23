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

local lookup = {'Evoker-Preservation','Shaman-Restoration','DemonHunter-Devourer','Rogue-Assassination','Mage-Frost','Druid-Balance','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Mage-Arcane','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','DemonHunter-Vengeance','Paladin-Protection','Warlock-Destruction','Evoker-Devastation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abdervoke:BAABLgAECn8hAAIBAAkJRyL4AQBkAwABAAkJRyL4AQBkAwABLgAFFAMJBQACAPchAA==.Absent:BAAALgADCgEJAQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aeila:BAAALgADCgYJBgAAAA==.',
Af='Aferou:BAAALgADCgUJBQAAAA==.',
Ag='Agnithor:BAAALgADCgEJAQAAAA==.Agìnor:BAAALgAECgYJBgABLgAFFAgJEgADAJwKAA==.',
Ah='Ahsoul:BAAALgAECgEJAgAAAA==.',
Ai='Ainur:BAAALgAECgEJAQABLgAFFAMJCAAEAHMNAA==.',
Al='Alesia:BAAALgADCgEJAQAAAA==.Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8zAAIFAAkJSSJvDwD/AgAFAAkJSSJvDwD/AgAAAA==.Alistus:BAACLgAFFH8ZAAIDAAQJPiXPDwCTAQADAAQJPiXPDwCTAQAuAAQKfz8AAgMACQlZJccDAEoDAAMACQlZJccDAEoDAAAA.Alphá:BAAALgAECgUJCQABLgAFFAMJBQACAAALAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJCQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAACLgAFFH8IAAIGAAMJgg0bFgCuAAAGAAMJgg0bFgCuAAAuAAQKf2EAAgYACQlWHeAOAG8CAAYACQlWHeAOAG8CAAAA.Anotheralt:BAAALgAECgYJCAAAAA==.',
Ar='Arcanegarm:BAABLgAECn8bAAIFAAcJIAJZ/wCuAAAFAAcJIAJZ/wCuAAAAAA==.Archeyois:BAABLgAECn8pAAMHAAkJVA9GKwCRAQAHAAkJVA9GKwCRAQABAAUJhQIRNwCzAAAAAA==.Armitage:BAABLgAECn8YAAMIAAkJ/w+0HABnAQAIAAkJXQ+0HABnAQAJAAcJQgvyHgARAQAAAA==.Arthonos:BAACLgAFFH8GAAIKAAIJVAUBNABzAAAKAAIJVAUBNABzAAAuAAQKfzUAAwoACQmaFQ8ZAP0BAAoACQmaFQ8ZAP0BAAsACAnjBWQnAFoBAAAA.Arugall:BAAALgAECggJCAAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Aveliandis:BAAALgAECgQJBAAAAA==.Averille:BAAALgADCgYJCwAAAA==.',
Ay='Ayraa:BAAALgAECgYJBAAAAA==.',
Az='Azerphage:BAAALgAECgYJDwABLgAECgcJCwAMAAAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAABLgAECn8VAAINAAYJOwrVrgDmAAANAAYJOwrVrgDmAAAAAA==.Azzog:BAABLgAECn8bAAIOAAkJexchBABjAQAOAAkJexchBABjAQAAAA==.Azül:BAAALgAECgYJBgABLgAECgcJCwAMAAAAAA==.',
Ba='Bacchanalian:BAAALgAECgcJDAABLgAECgkJCwAMAAAAAA==.Baindyn:BAAALgAECgQJEwAAAA==.Barator:BAAALgAECggJDAAAAA==.Barky:BAAALgADCgEJAQAAAA==.Bas:BAAALgAFFAEJBAAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJEAAAAA==.',
Bl='Blackröse:BAACLgAFFH8GAAIPAAMJCRZKCwDOAAAPAAMJCRZKCwDOAAAuAAQKfyMAAg8ACAkzHYMQACoCAA8ACAkzHYMQACoCAAAA.Blackrøse:BAABLgAECn8pAAICAAkJHxdNBwCdAQACAAkJHxdNBwCdAQABLgAFFAMJBgAPAAkWAA==.Bladebane:BAABLgAECn8lAAIOAAkJGgFPPQCbAAAOAAkJGgFPPQCbAAAAAA==.Blandmonk:BAAALgAECgMJBQAAAA==.Blksunshine:BAAALgAECggJDAAAAA==.',
Bo='Bolash:BAAALgAECgYJCwAAAA==.Boomnbloom:BAAALgAECgMJCAAAAA==.Bort:BAAALgAECgEJBAAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breegorn:BAAALgAECgUJBgAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgUJEgAAAA==.',
Bu='Bulvhine:BAABLgAECn8xAAIQAAkJfyBdAwCIAgAQAAkJfyBdAwCIAgAAAA==.',
Ca='Camferd:BAAALgAECgEJAQAAAA==.Camford:BAABLgAECn8ZAAIFAAcJ8QhZvQBoAQAFAAcJ8QhZvQBoAQAAAA==.Cantatrix:BAABLgAECn8bAAINAAYJ9gt4owD5AAANAAYJ9gt4owD5AAAAAA==.Capslok:BAAALgAFFAEJAQAAAA==.Captinmeat:BAAALgAECgUJCAAAAA==.Cargoan:BAAALgAECgMJAwAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgABLgAECgkJCwAMAAAAAA==.',
Ce='Cecilx:BAABLgAECn8zAAIRAAkJWCRrAgCGAwARAAkJWCRrAgCGAwAAAA==.Cellybelleri:BAAALgAECgQJBAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Chillana:BAAALgAECgQJBAAAAA==.Chimerax:BAACLgAFFH8bAAMSAAYJlx54AgCDAQASAAYJlx54AgCDAQANAAEJlxedwQBHAAAuAAQKfy4AAxIACQkQIQACALACABIACQkQIQACALACAA0ACAlDEwt8AEEBAAAA.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIQAAgJMAZQoQA9AQAQAAgJMAZQoQA9AQAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAACLgAFFH8PAAIDAAQJZRDlSAAOAQADAAQJZRDlSAAOAQAuAAQKfywAAwMACQkIG2AqACACAAMACQkIG2AqACACABMAAwmIBM1ZAH0AAAAA.',
Cl='Clairíty:BAABLgAECn8gAAIUAAgJsh4DDgCGAgAUAAgJsh4DDgCGAgAAAA==.Clarky:BAAALgAECgYJEAAAAA==.Click:BAABLgAECn9EAAIVAAkJUxzvEwCzAgAVAAkJUxzvEwCzAgAAAA==.Cloutfarmer:BAACLgAFFH8QAAIVAAQJGyC5KQBhAQAVAAQJGyC5KQBhAQAuAAQKf0AABBUACQlKJf0EAEEDABUACQlKJf0EAEEDABYABgkZHFspAOABAA8AAglFHfpVAFUAAAAA.',
Co='Comadore:BAACLgAFFH8QAAIQAAUJDQyFWgD7AAAQAAUJDQyFWgD7AAAuAAQKfxwAAhAACAk4HNg4AEACABAACAk4HNg4AEACAAAA.Coronae:BAAALgAECgIJAwAAAA==.Corrose:BAAALgAECgIJAgAAAA==.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEBLgAECn8VAAIXAAkJMyIQBgBFAwAXAAkJMyIQBgBFAwABLgADCgYJBgAMAAAAAA==.Critmypants:BAAALgAECgIJAgAAAA==.',
Cu='Curator:BAAALgADCgUJBQAAAA==.',
Cy='Cylithina:BAAALgAECgQJCgAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Dalair:BAAALgAECgQJBAAAAA==.Daphe:BAAALgAECgEJAwAAAA==.Dartheior:BAAALgAECgIJAwAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAgAAAA==.Deadseksi:BAAALgAECgcJEAAAAA==.Deathslead:BAABLgAECn9NAAMVAAkJSxdVBQAlAgAVAAkJSxdVBQAlAgAWAAUJ3AHpMQBSAAAAAA==.Decrepe:BAACLgAFFH8RAAIYAAQJ2BhjJwAhAQAYAAQJ2BhjJwAhAQAuAAQKfzsAAhgACQlIIIAKABUDABgACQlIIIAKABUDAAAA.Dedrepe:BAAALgAECggJCQAAAA==.Delph:BAAALgAFFAEJAQAAAA==.Deshal:BAAALgAECgUJDwAAAA==.Desomas:BAAALgAECgIJAgAAAA==.Dethklock:BAAALgAECgEJAQAAAA==.Dethwingchun:BAAALgAECgQJCQABLgAECgQJEwAMAAAAAA==.Detrath:BAAALgAECgEJAQAAAA==.',
Di='Dieurnal:BAAALgAECgQJAQAAAA==.Discostar:BAABLgAECn8vAAMYAAkJUxdaLgDsAQAYAAgJDBZaLgDsAQAGAAgJghceBwAgAQAAAA==.Distill:BAAALgAECgEJAQABLgAFFAkJJgAZAAElAA==.',
Dn='Dni:BAAALgAECgMJBAABLgAECgkJLwAGAMAbAA==.',
Do='Dominicm:BAAALgAECgYJEgAAAA==.Dotdotdis:BAAALgAECgMJAwAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Dracosixth:BAAALgADCgUJBQAAAA==.Dragonpro:BAAALgADCgUJBQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECggJDAAAAA==.Druth:BAABLgAECn8tAAIaAAgJRx++CgBDAgAaAAgJRx++CgBDAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgUJEQAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einari:BAAALgAECggJCAAAAA==.Einark:BAACLgAFFH8IAAIXAAMJIhFwIACmAAAXAAMJIhFwIACmAAAuAAQKf1kAAxcACQk4IG0BAMQCABcACQk4IG0BAMQCABsACAnMHi4NAHICAAAA.Eino:BAAALgAECgEJAQAAAA==.',
Ek='Ekiim:BAAALgAECgQJBAABLgAECgQJCQAMAAAAAA==.',
El='Eldrond:BAAALgAECgQJCAABLgAECgUJCQAMAAAAAA==.Elinis:BAAALgAFFAEJAQAAAA==.Elsbett:BAAALgAECgUJBQABLgAECgkJGQAFACsVAA==.Elska:BAAALgADCgkJCQAAAA==.',
En='Ennauríon:BAAALgAECgUJCQAAAA==.Entropy:BAEALgAFFAMJBAABLgAFFAMJBwAcADUOAA==.',
Er='Eridor:BAAALgAECgcJEQAAAA==.Erissama:BAAALgADCgEJAQAAAA==.',
Es='Esbernia:BAAALgADCgMJAwAAAA==.',
Ex='Exek:BAABLgAECn8yAAMUAAgJsBcvFwAVAgAUAAgJsBcvFwAVAgAKAAYJCA6fDgCrAAAAAA==.',
Ey='Eyeofnature:BAAALgAECgEJAQAAAA==.',
Ez='Ez:BAAALgAECgEJAQABLgAECgkJMAAdACgbAA==.',
Fa='Fabaztard:BAABLgAECn8kAAIGAAkJ1hIuIwCwAQAGAAkJ1hIuIwCwAQAAAA==.Faline:BAABLgAECn8zAAIYAAkJUwvJRQB5AQAYAAkJUwvJRQB5AQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8bAAIDAAYJNxETIAD7AAADAAYJNxETIAD7AAAuAAQKfyMAAgMACQlUGs00ACUCAAMACQlUGs00ACUCAAAA.Felghoul:BAAALgAECgcJEgAAAA==.Felldozer:BAAALgAECgEJAQAAAA==.Fenrakar:BAAALgAECgQJBwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn9BAAIRAAkJKR4HCgDrAgARAAkJKR4HCgDrAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.Floofi:BAAALgAECgcJDwAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJCAAAAA==.Forloss:BAAALgAECgMJAwAAAA==.Foxknight:BAABLgAECn8YAAQeAAUJgBAdGgABAQAeAAUJgBAdGgABAQAfAAMJ3A0aLQBjAAAOAAQJ4QM2SwBiAAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgAMAAAAAA==.Frostdrake:BAAALgAECgUJBQAAAA==.',
Ft='Ftx:BAABLgAECn8gAAMgAAgJuh+oDQC4AgAgAAgJlR+oDQC4AgAbAAQJ2hm/RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAIQAAkJARwsOAAhAgAQAAkJARwsOAAhAgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaern:BAAALgAECgEJAwABLgAFFAIJAgAMAAAAAA==.Gaidan:BAACLgAFFH8RAAIGAAYJKRPwCQBbAQAGAAYJKRPwCQBbAQAuAAQKfyEAAgYACQmlFogRAI8CAAYACQmlFogRAI8CAAEuAAUUCAkSAAMAnAoA.Gaidin:BAACLgAFFH8SAAIDAAgJnApjLAB1AQADAAgJnApjLAB1AQAuAAQKfyAAAgMACQlGHgY9ANQBAAMACQlGHgY9ANQBAAAA.Gameslayer:BAABLgAECn8gAAMhAAkJcB2dKwCmAQAhAAYJcx+dKwCmAQAiAAQJzxdeMQACAQAAAA==.Gankzilla:BAACLgAFFH8bAAMZAAYJSBPUGQBGAQAZAAUJHRbUGQBGAQAEAAIJsAyKBQBRAAAuAAQKfycAAwQACQmeG2EJAKoBABkABgl3GNklAMoBAAQABwkfG2EJAKoBAAAA.Garothos:BAAALgAECgIJAgABLgAECgQJBwAMAAAAAA==.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Genrealwee:BAAALgAECgEJAQAAAA==.Get:BAAALgADCgkJDAAAAA==.',
Gh='Ghalumvhar:BAABLgAECn8fAAIQAAcJBRtXTwDaAQAQAAcJBRtXTwDaAQAAAA==.Ghoulaid:BAAALgAECgcJBwAAAA==.Ghrìmm:BAABLgAECn8lAAQPAAkJ6w/EGgDIAQAPAAkJIA3EGgDIAQAVAAgJxA5OaQBwAQAWAAEJ+QZkRAAiAAAAAA==.',
Gi='Gila:BAAALgAECggJEAAAAA==.Gingasorrow:BAABLgAECn80AAIYAAkJnBkLFgCYAgAYAAkJnBkLFgCYAgAAAA==.Gizzle:BAACLgAFFH8TAAIQAAYJpg+IJgDdAAAQAAYJpg+IJgDdAAAuAAQKfyYAAhAACQmoFltVAMoBABAACQmoFltVAMoBAAAA.',
Gl='Gloccamorra:BAAALgADCgEJAQAAAA==.',
Gr='Greekfire:BAABLgAECn8YAAIRAAgJ3yE5GwA7AgARAAgJ3yE5GwA7AgAAAA==.Grimgrug:BAAALgADCgUJBQAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn80AAIVAAgJqSKCGQCNAgAVAAgJqSKCGQCNAgAAAA==.Grændal:BAABLgAECn8cAAIKAAcJJBkqBACVAQAKAAcJJBkqBACVAQABLgAFFAgJEgADAJwKAA==.',
Ha='Hahatotem:BAAALgADCgMJAwAAAA==.Hanjha:BAABLgAECn9HAAMPAAkJkR/AAwD4AgAPAAgJkR/AAwD4AgAVAAEJAAA7zwA3AAAAAA==.Harunhwa:BAAALgAECgMJBQAAAA==.Haseo:BAAALgAECgEJAQABLgAFFAMJCAAEAHMNAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAFFAMJBQAQAAwdAA==.Helldozer:BAACLgAFFH8FAAIdAAIJZw3SIQB4AAAdAAIJZw3SIQB4AAAuAAQKf0oAAx0ACQkvFg4YACMCAB0ACQkvFg4YACMCAAIAAgnPFFynAH0AAAAA.',
Ho='Hooj:BAAALgADCgYJBgAAAA==.Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAABLgAECn8WAAIFAAYJDA0cGADqAAAFAAYJDA0cGADqAAAAAA==.',
Hw='Hwore:BAAALgAECgQJBAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgAMAAAAAA==.Hypnocide:BAECLgAFFH8GAAIDAAMJGgQrRQBJAAADAAMJGgQrRQBJAAAuAAQKf1UAAgMACQlnGYkCADcCAAMACQlnGYkCADcCAAAA.',
['Hã']='Hãil:BAAALgADCgIJAQAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
Ib='Ibuki:BAAALgAFFAEJAQABLgAFFAYJGwARADoHAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Ig='Iguanajon:BAAALgAECgEJAgAAAA==.',
Il='Illandren:BAACLgAFFH8RAAIPAAQJlggaGAARAQAPAAQJlggaGAARAQAuAAQKfxsAAw8ACQljC+0cALUBAA8ACQljC+0cALUBABYACAk6A9gfALEAAAAA.Illusiveeyes:BAAALgADCgYJDAAAAA==.',
Im='Impsane:BAABLgAECn8uAAINAAkJ1hCABQCxAQANAAkJ1hCABQCxAQAAAA==.',
In='Incøgnitø:BAAALgAECgEJAQABLgAECgkJHQAYADIcAA==.Indolence:BAEALgAECgIJAgABLgAECgUJDgAMAAAAAA==.Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8jAAIFAAcJsQj0wgAFAQAFAAcJsQj0wgAFAQAAAA==.Innøminate:BAABLgAECn8iAAIVAAgJwhEJCwCNAQAVAAgJwhEJCwCNAQABLgAECgkJHQAYADIcAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQEAAgJlhqJBwDgAQAEAAgJ5xmJBwDgAQAZAAUJoxxSMwBwAQAjAAQJjg9mCQDZAAAAAA==.',
Is='Isadavrah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgQJBwAAAA==.Isellrocks:BAAALgAECgQJBQAAAA==.Issadin:BAAALgAECgUJBwABLgAECgYJDAAMAAAAAA==.Issadruiid:BAAALgADCgYJBgABLgAECgYJDAAMAAAAAA==.Issammonk:BAAALgAECgEJAQABLgAECgYJDAAMAAAAAA==.Issarage:BAAALgAECgQJCQABLgAECgYJDAAMAAAAAA==.Issashammy:BAAALgAECgYJDAAAAA==.',
Ja='Jaxxa:BAABLgAECn88AAIVAAkJ6xqCHwBqAgAVAAkJ6xqCHwBqAgAAAA==.',
Je='Jeddiah:BAABLgAECn8kAAMEAAcJIQ/TDQBKAQAEAAcJIQ/TDQBKAQAZAAQJLgxhRwCdAAAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jiffarous:BAAALgAECgQJBwAAAA==.Jinkès:BAABLgAECn84AAIWAAkJrBXbAAD+AQAWAAkJrBXbAAD+AQAAAA==.',
Jp='Jpank:BAAALgAFFAEJAwAAAA==.',
Ju='Jubei:BAABLgAFFH8IAAIQAAYJBwynSwBqAAAQAAYJBwynSwBqAAAAAA==.Judis:BAACLgAFFH8JAAIEAAMJ2hYFAgD8AAAEAAMJ2hYFAgD8AAAuAAQKf1QAAgQACQlFH7wBAOICAAQACQlFH7wBAOICAAAA.Judyth:BAAALgAECgIJBQAAAA==.Juicy:BAAALgADCgIJAgAAAA==.Justokevoker:BAABLgAFFH8LAAIHAAQJpxHcMgD2AAAHAAQJpxHcMgD2AAAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8cAAIbAAkJnR97CAC/AgAbAAkJnR97CAC/AgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kalipally:BAAALgAECgcJDgAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgcJCgAAAA==.Kanajotoma:BAAALgAECgUJEgAAAA==.Karlai:BAACLgAFFH8GAAMeAAMJPg+DCgDYAAAeAAMJPg+DCgDYAAAfAAEJngtzlwA7AAAuAAQKfy0AAx8ACAlYHOIKAFQBAB4ABwm6GuUEAAACAB8ABwmFG+IKAFQBAAEuAAUUCAkSAAMAnAoA.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAABLgAECn8aAAIKAAcJVQ1gCAARAQAKAAcJVQ1gCAARAQAAAA==.Keleena:BAECLgAFFH8IAAIRAAMJ+RV4EQDEAAARAAMJ+RV4EQDEAAAuAAQKf3AAAhEACQlpIBcBAKUCABEACQlpIBcBAKUCAAAA.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Kg='Kgor:BAAALgAECgcJBwAAAA==.',
Kh='Khaerne:BAAALgAECgEJAQABLgAFFAIJAgAMAAAAAA==.Khordelia:BAAALgAFFAIJAgAAAA==.',
Ki='Killiana:BAAALgADCgUJBQAAAA==.Kinst:BAACLgAFFH8GAAIVAAMJ5RFmKgDkAAAVAAMJ5RFmKgDkAAAuAAQKf0YAAxUACQnEHzMSAMACABUACQnEHzMSAMACABYABgmvEto/AFsBAAAA.Kirigaya:BAAALgAECgMJCQAAAA==.Kisäi:BAABLgAECn8pAAMDAAkJ1RxbIACPAgADAAkJ1RxbIACPAgAkAAIJHBGVKABiAAAAAA==.Kitanyia:BAABLgAECn87AAIhAAkJlxgsAgAtAgAhAAkJlxgsAgAtAgAAAA==.Kittiy:BAACLgAFFH8FAAIGAAIJDwXwHgBfAAAGAAIJDwXwHgBfAAAuAAQKfzcAAwYACAlTCkxDAP8AAAYACAlTCkxDAP8AABgABgkqB1F8AMMAAAAA.',
Ko='Kordelia:BAABLgAECn8mAAIFAAkJJh8cHwCjAgAFAAkJJh8cHwCjAgABLgAFFAIJAgAMAAAAAA==.Koru:BAAALgAECgIJAgAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kr='Krench:BAAALgAECgEJAQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgUJCQAAAA==.Kyloon:BAAALgAECgYJCgAAAA==.Kyrah:BAACLgAFFH8FAAMSAAMJ+w70EQBMAAANAAIJvwrupgCDAAASAAEJdBf0EQBMAAAuAAQKf0QAAw0ACQmuGqoDABMCAA0ACQkAGKoDABMCABIABgnfG8sGAOsBAAAA.',
La='Lamanira:BAAALgAECggJDAAAAA==.Lancier:BAAALgAECgcJCwAAAA==.',
Ld='Ldyaria:BAAALgAECgQJCQAAAA==.',
Le='Lecleme:BAACLgAFFH8GAAIfAAMJZBEEoADUAAAfAAMJZBEEoADUAAAuAAQKfyEAAh8ACAleGE5IAOkBAB8ACAleGE5IAOkBAAAA.Lejend:BAABLgAECn9KAAMiAAkJyCXiAABxAwAiAAkJyCXiAABxAwAhAAMJfRW8fwC+AAAAAA==.Lenorra:BAAALgAECgMJBQAAAA==.Lenthalis:BAAALgAECgUJEQAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lifeslead:BAAALgADCgIJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECggJDAAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAHAOsLAA==.Lockheéd:BAAALgAFFAEJAQAAAA==.Lonelyhearts:BAABLgAECn89AAIQAAkJrQsRcwCIAQAQAAkJrQsRcwCIAQAAAA==.Lonestar:BAAALgAECgYJDwAAAA==.Lonestarr:BAAALgAECgQJDAAAAA==.Loxricia:BAAALgADCgEJAQAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAIUAAkJ7w52LwCFAQAUAAkJ7w52LwCFAQAAAA==.',
Ly='Lytol:BAABLgAECn8qAAMcAAkJtReFAgAoAgAcAAkJtReFAgAoAgAFAAMJXgQ8IgF1AAAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAFFAQJCwAHANkVAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maege:BAAALgADCggJCAAAAA==.Maenad:BAAALgAECgkJCwAAAA==.Maeple:BAABLgAECn8pAAMUAAkJ+SEhBABDAwAUAAkJ+SEhBABDAwALAAMJugpfXgCFAAAAAA==.Magikin:BAAALgAECgQJCAAAAA==.Magrat:BAAALgAECgYJDQAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8fAAMPAAcJeiMgAQAJAgAPAAcJeiMgAQAJAgAWAAEJjAS6JABVAAAuAAQKfxsAAw8ABwmMJXMEANQCAA8ABwkxJXMEANQCABYAAQksIwR3AGMAAAEuAAUUCAkwAAUAuyUA.',
Me='Mechagnome:BAACLgAFFH8GAAIbAAIJoBsILgCQAAAbAAIJoBsILgCQAAAuAAQKfzQAAxsACQnUIMsHAMsCABsACQnUIMsHAMsCABcACAkJBAU6AAABAAAA.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMQAAYJkhbKegCEAQAQAAYJEhbKegCEAQAlAAQJTQn+NgCEAAAAAA==.Meigna:BAABLgAECn8qAAIKAAgJuR2MEQBKAgAKAAgJuR2MEQBKAgAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8qAAMJAAYJ9iKSBAByAQAJAAUJeyOSBAByAQAIAAUJMh4aCQBhAQAuAAQKfygAAwkABwlnJlYDAAMDAAkABwlnJlYDAAMDAAgABQnrIwEXAJoBAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAABLgAECn8YAAIFAAYJ4hCEqwApAQAFAAYJ4hCEqwApAQAAAA==.Merdock:BAAALgAECgQJCAAAAA==.Merelandra:BAAALgADCgkJKQAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Michelle:BAAALgADCgQJBAAAAA==.Miliara:BAAALgADCgEJAQAAAA==.Miradh:BAEALgAECgQJBAABLgAECgUJDgAMAAAAAA==.Missmaam:BAABLgAECn8ZAAMUAAkJjRpdFQAqAgAUAAgJ2hldFQAqAgAKAAUJuxKPCQDzAAAAAA==.Mistroot:BAAALgAECgkJDAAAAA==.Mistshealz:BAAALgAECgEJAQABLgAFFAQJEAAfAMQdAA==.Mithrandir:BAACLgAFFH8HAAMNAAIJPwPPSQBeAAANAAIJPwPPSQBeAAAmAAEJOQDVLQATAAAuAAQKfysAAyYABwnqFM4DAA8BAA0ABwkFEfhxAFYBACYABQkQF84DAA8BAAAA.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAABLgAECn8cAAMaAAkJyxsdDwD4AQAaAAkJyxsdDwD4AQAhAAIJ6xAGlABvAAAAAA==.',
Mo='Moe:BAAALgAECgkJBAAAAA==.Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudanca:BAAALgAECgMJAwABLgAECgUJEgAMAAAAAA==.Mudflap:BAABLgAECn8VAAIVAAYJBg06JQCcAAAVAAYJBg06JQCcAAAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAFFAQJCwAHANkVAA==.Muztang:BAABLgAECn9CAAMiAAkJ1x5vBADUAgAiAAkJ1x5vBADUAgAhAAYJihOETgAOAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgYJCgAAAA==.',
My='Mythandwel:BAABLgAECn8wAAITAAgJqgrjLQAUAQATAAgJqgrjLQAUAQAAAA==.',
['Mä']='Mäddieness:BAAALgAECgIJAgAAAA==.Mäddiey:BAAALgAECgQJCgAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8TAAIgAAQJESXZDgCyAQAgAAQJESXZDgCyAQAuAAQKfz4AAyAACQnjJLICAC4DACAACQnjJLICAC4DABcAAQmvAhzfABEAAAAA.',
Na='Nace:BAABLgAECn8qAAIZAAkJ7BOvGQA2AgAZAAkJ7BOvGQA2AgAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgAECgUJBQAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nariar:BAAALgAECgMJAwABLgAFFAYJGwARADoHAA==.Nateldin:BAABLgAECn8YAAMQAAkJhwmIkABbAQAQAAkJ8AeIkABbAQAlAAIJ9Q61UgArAAAAAA==.',
Ne='Neoba:BAAALgAECgUJCAAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECggJDQABLgAECgkJHwAUAKMHAA==.Nikiso:BAAALgADCgYJBwAAAA==.',
No='Nocainus:BAABLgAECn9NAAIOAAkJwCGJAwAFAwAOAAkJwCGJAwAFAwAAAA==.Nosehole:BAABLgAECn8iAAICAAcJ0hTZPAC7AQACAAcJ0hTZPAC7AQAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQABLgAFFAUJCAAbAGwKAA==.',
['Nø']='Nøtsure:BAABLgAECn8dAAMYAAkJMhy4JQAgAgAYAAkJMhy4JQAgAgAGAAIJqwyJdABdAAAAAA==.',
Ob='Obesityy:BAABLgAECn8xAAIZAAkJph5yCACfAgAZAAkJph5yCACfAgAAAA==.Obsidia:BAABLgAECn8oAAINAAkJSQ8VSwC5AQANAAkJSQ8VSwC5AQAAAA==.',
Oc='Octopusprime:BAAALgAECgkJEQAAAA==.',
Ol='Oled:BAAALgADCgIJAgAAAA==.Ollix:BAAALgAECgEJBAABLgAECgkJTAADAI4eAA==.',
Om='Omelette:BAABLgAECn8fAAIVAAkJiRz9GwB9AgAVAAkJiRz9GwB9AgAAAA==.',
On='Onik:BAAALgAECgIJAgABLgAECgUJCQAMAAAAAA==.',
Op='Ophj:BAACLgAFFH8IAAIFAAQJsBR2awAMAQAFAAQJsBR2awAMAQAuAAQKfyAAAgUACQm2ImMHAJEDAAUACQm2ImMHAJEDAAAA.',
Or='Orangejulius:BAAALgAECgQJCQAAAA==.Orangutan:BAAALgAECgQJBQAAAA==.Oriclysmic:BAABLgAECn8iAAQBAAgJ5h3SBwB2AgABAAgJ5h3SBwB2AgAHAAQJhQSiTwCPAAAnAAEJAAAjPwAzAAAAAA==.Oriigami:BAAALgAECggJDAAAAA==.Orinoheal:BAAALgAECgYJBgAAAA==.Orochiimaru:BAAALgAECgQJBQABLgAFFAMJCAAEAHMNAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pa='Patala:BAAALgADCgYJBgAAAA==.',
Pe='Perilous:BAAALgAECgUJEgAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phalix:BAAALgAFFAIJAgABLgAFFAQJGgAWAAMhAA==.Phat:BAAALgAECgQJBgAAAA==.Phoelar:BAABLgAECn8UAAMGAAcJoRUELQBxAQAGAAcJoRUELQBxAQAYAAEJJhYuGwA3AAAAAA==.Phuumyn:BAABLgAECn9FAAIbAAkJTyVOAQBoAwAbAAkJTyVOAQBoAwAAAA==.',
Pi='Piccoblast:BAACLgAFFH8cAAIFAAcJyhQSDQCzAQAFAAcJyhQSDQCzAQAuAAQKfy0AAgUACAnYIuEcAAIDAAUACAnYIuEcAAIDAAAA.Piccolocks:BAAALgAECgYJCwABLgAFFAcJHAAFAMoUAA==.Piccopew:BAAALgAECgEJAQABLgAFFAcJHAAFAMoUAA==.Pichus:BAAALgAECgEJAQABLgAFFAMJBQACAAALAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAFFAIJAwABLgAFFAQJGgAWAAMhAA==.Piickles:BAACLgAFFH8qAAMUAAgJ0RVTBgD1AQAUAAgJ0RVTBgD1AQALAAQJuxJMJgAYAQAuAAQKfyEAAhQACQlTHtoLAJMCABQACQlTHtoLAJMCAAAA.Pinkcanibus:BAABLgAECn8aAAIVAAgJvQSzbwAZAQAVAAgJvQSzbwAZAQAAAA==.Pippopper:BAAALgAECgEJAQABLgAFFAQJGQADAD4lAA==.Pity:BAABLgAECn8XAAIDAAkJjg2UUQCRAQADAAkJjg2UUQCRAQAAAA==.',
Pl='Plutø:BAABLgAECn9PAAQeAAkJ4xsdAQAyAgAOAAcJth4MDABRAgAeAAkJ/hUdAQAyAgAfAAkJghIMUQDQAQAAAA==.',
Po='Polylocks:BAABLgAECn8UAAINAAgJPBQdSgC8AQANAAgJPBQdSgC8AQAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAECLgAFFH8HAAIcAAMJNQ6GAgDLAAAcAAMJNQ6GAgDLAAAuAAQKfy0AAhwACQkPGtEDANEBABwACQkPGtEDANEBAAAA.Praycation:BAAALgAECgYJBgAAAA==.Promethius:BAAALgAECgcJCQABLgAFFAMJBwANAD8DAA==.Protein:BAABLgAECn8gAAIhAAcJ0BURPQBSAQAhAAcJ0BURPQBSAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgAMAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn9JAAIYAAkJER0UDQD0AgAYAAkJER0UDQD0AgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECggJFAANADwUAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quiet:BAAALgAECgQJBAAAAA==.Quilian:BAACLgAFFH8ZAAIUAAUJdCS/BQAFAgAUAAUJdCS/BQAFAgAuAAQKfyYAAhQACQlAISkEABIDABQACQlAISkEABIDAAAA.',
Ra='Raelynn:BAABLgAECn9NAAIUAAkJvBk/DACiAgAUAAkJvBk/DACiAgAAAA==.Raevenhart:BAACLgAFFH8GAAIWAAMJlgivIACnAAAWAAMJlgivIACnAAAuAAQKfx0AAhYACAlZFWIkAAUCABYACAlZFWIkAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgAECgMJBAAAAA==.Rashalisk:BAAALgAECgIJAgAAAA==.Raymond:BAAALgADCgcJBwAAAA==.Razerblade:BAAALgAECgEJAQAAAA==.',
Re='Rebarbative:BAABLgAECn8iAAMNAAkJoQ5dSwC4AQANAAkJoQ5dSwC4AQAmAAMJfAXZUQB5AAAAAA==.Redvex:BAACLgAFFH8OAAINAAQJXhjjRABAAQANAAQJXhjjRABAAQAuAAQKf0UABA0ACQnFJYsEAEcDAA0ACQmQJYsEAEcDACYABQkxII8SALcBABIAAglwI5UkAJ4AAAAA.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn89AAMQAAkJ5RFqYwCpAQAQAAkJ2A9qYwCpAQAlAAcJfxNmBQACAQAAAA==.Renduval:BAAALgAECgIJAgAAAA==.Restohexual:BAAALgAECgEJAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8sAAIRAAkJhRoeEwB4AgARAAkJhRoeEwB4AgAAAA==.',
Rh='Rhedman:BAABLgAECn8aAAMeAAYJ7QqrHADpAAAeAAUJ7QqrHADpAAAfAAYJdAU87wDBAAAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinah:BAAALgAFFAMJBAAAAA==.Rinahrune:BAAALgAECgMJBgAAAA==.Rinahvoid:BAAALgAECgEJAQAAAA==.',
Ro='Robat:BAAALgADCggJDQAAAA==.Ronwen:BAAALgAECgQJBQABLgAFFAYJGwARADoHAA==.Rootbeard:BAAALgAECgQJBAAAAA==.Rorhan:BAAALgAECgYJBgAAAA==.Rosanna:BAAALgAECggJCgAAAA==.Roselyn:BAABLgAECn8VAAIUAAcJaxHEKgByAQAUAAcJaxHEKgByAQAAAA==.Rotyr:BAABLgAECn9LAAILAAkJKRpZAQCrAgALAAkJKRpZAQCrAgAAAA==.',
Ru='Ruana:BAEALgAECgUJDgAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Saffron:BAEALgAECgMJAwABLgAECgUJDgAMAAAAAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Santhela:BAAALgAECgQJBQAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Saturñ:BAAALgAECgYJEgAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8lAAIVAAgJtBp5MwAOAgAVAAgJtBp5MwAOAgAAAA==.Scots:BAAALgADCgcJFwAAAA==.Scubbs:BAACLgAFFH8VAAICAAUJ4xIIJQBXAQACAAUJ4xIIJQBXAQAuAAQKfyEAAgIACAkuFkkiABECAAIACAkuFkkiABECAAAA.Scubbsboo:BAACLgAFFH8IAAIXAAUJ7Q8aFgAGAQAXAAUJ7Q8aFgAGAQAuAAQKfxsAAhcABwmoG54cADMCABcABwmoG54cADMCAAEuAAUUBQkVAAIA4xIA.',
Se='Seras:BAAALgAECgUJBQAAAA==.Serka:BAAALgADCgYJBgAAAA==.Servantes:BAABLgAECn9KAAMYAAkJghCNOAC0AQAYAAkJghCNOAC0AQAGAAEJTwW7ngAjAAAAAA==.',
Sg='Sgthulka:BAAALgAECgEJAQAAAA==.',
Sh='Shackleford:BAABLgAECn9HAAQLAAkJ4h4ZDQCbAgALAAkJ4h4ZDQCbAgAKAAgJpRZ2GwDpAQAUAAcJLBPDLABlAQAAAA==.Shamae:BAAALgAECgQJBAAAAA==.Shamrockk:BAAALgADCgIJAgAAAA==.Shamwõwz:BAAALgAFFAMJBAAAAA==.Shaolin:BAAALgAECgkJCQAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCgAAAA==.Shotya:BAABLgAECn9NAAIVAAkJlwvPTQC5AQAVAAkJlwvPTQC5AQAAAA==.Shyvàna:BAAALgAECgIJAgABLgAFFAYJGwARADoHAA==.',
Si='Siath:BAABLgAECn8UAAMHAAgJ6wtnQQAkAQAHAAgJ6wtnQQAkAQAnAAIJ6gg7PQA5AAAAAA==.Silvino:BAAALgADCgEJAQABLgAECgkJLwAGAMAbAA==.Simpforsouls:BAAALgADCgEJAQAAAA==.Sixpacktnt:BAAALgADCgkJNQAAAA==.Sixthdemon:BAAALgADCgUJBQAAAA==.Sixthknight:BAABLgAECn8jAAIQAAcJlAsRKACLAAAQAAcJlAsRKACLAAAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8eAAIRAAgJXyapBABNAwARAAgJXyapBABNAwAAAA==.',
Sn='Snacky:BAAALgAECgIJAgAAAA==.Snarkypony:BAABLgAECn8ZAAIFAAgJNA2gEQAlAQAFAAgJNA2gEQAlAQAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorocide:BAAALgADCgUJBQAAAA==.Sorsere:BAABLgAECn9BAAINAAkJzh4VFACtAgANAAkJzh4VFACtAgAAAA==.',
Sp='Spcecialk:BAABLgAECn8dAAIaAAcJLQulKADvAAAaAAcJLQulKADvAAAAAA==.Specialk:BAACLgAFFH8IAAIdAAIJ0wsIRgBzAAAdAAIJ0wsIRgBzAAAuAAQKfz4AAx0ACAlJErwyAHIBAB0ACAlJErwyAHIBAAIAAwmsBr6xAGYAAAAA.',
Sq='Squallie:BAABLgAECn8ZAAIYAAYJqRNLTwBSAQAYAAYJqRNLTwBSAQAAAA==.',
St='Starcaller:BAAALgAECgYJBgAAAA==.Starryy:BAAALgAECgUJBQAAAA==.Steamedhams:BAAALgAECgcJCwAAAA==.Stirredihime:BAAALgAFFAEJAQAAAA==.',
Su='Sundorei:BAAALgAECgQJCQAAAA==.Sunscale:BAAALgADCgEJAQAAAA==.',
Sw='Swipper:BAAALgAECgMJBQABLgAECgUJGAAeAIAQAA==.',
['Sû']='Sûlph:BAAALgAECgkJAwAAAA==.',
Ta='Taartt:BAAALgAFFAQJBAABLgAFFAcJJwABAJkTAA==.Tahoe:BAAALgADCgIJAgAAAA==.Talan:BAAALgAECgcJCgABLgAFFAgJEgADAJwKAA==.Talshekar:BAABLgAECn8lAAInAAgJsw3RCgBuAQAnAAgJsw3RCgBuAQAAAA==.Tarsis:BAABLgAECn8oAAIOAAkJeB97BQDRAgAOAAkJeB97BQDRAgAAAA==.',
Te='Teiana:BAABLgAECn8vAAIQAAkJ9x8fJAB0AgAQAAkJ9x8fJAB0AgAAAA==.Terizfolly:BAAALgAECgQJCAAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAABLgAECn8nAAIQAAkJVxX+TgDbAQAQAAkJVxX+TgDbAQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAACLgAFFH8QAAIYAAYJQhTAHgBjAQAYAAYJQhTAHgBjAQAuAAQKfzYAAhgACQk4G9kQAMoCABgACQk4G9kQAMoCAAAA.Thordak:BAAALgADCggJDQABLgAECgkJHwAQANIUAA==.',
Ti='Tiamat:BAAALgAECgkJCQAAAA==.Timbuktoo:BAABLgAECn8XAAIJAAkJoRO0AQDIAQAJAAkJoRO0AQDIAQAAAA==.Tinietimm:BAAALgADCgQJBAAAAA==.Tinypoop:BAABLgAECn8WAAIFAAYJVBVnrwAiAQAFAAYJVBVnrwAiAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAABLgAECn8oAAINAAkJWB/mAQCsAgANAAkJWB/mAQCsAgAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAABLgAECn8jAAIeAAYJUxlyEQBhAQAeAAYJUxlyEQBhAQAAAA==.Tors:BAACLgAFFH8SAAIGAAMJ6hCAFQC0AAAGAAMJ6hCAFQC0AAAuAAQKf2sAAwYACQlKIdIAAAIDAAYACQlKIdIAAAIDAAgAAgnYE55PAG8AAAAA.',
Tr='Trasky:BAAALgAECgMJAwAAAA==.Trogdore:BAAALgAECgYJDQAAAA==.Trollololo:BAABLgAECn9LAAMFAAkJuRqFJACKAgAFAAkJuRqFJACKAgAoAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8qAAIFAAkJXx7+IwCNAgAFAAkJXx7+IwCNAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgYJCAABLgAECggJFAANADwUAA==.',
Tt='Ttaartt:BAACLgAFFH8nAAMBAAcJmRNbCgAFAgABAAcJmRNbCgAFAgAHAAQJyxDzQQC/AAAuAAQKfx0AAgEABwmqGfESABICAAEABwmqGfESABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8WAAIEAAQJ2yAVAwBzAQAEAAQJ2yAVAwBzAQAuAAQKf0QAAgQACQm5JXUAAF4DAAQACQm5JXUAAF4DAAAA.Tyr:BAAALgAECgkJBwAAAA==.Tyresta:BAAALgAECgEJAQAAAA==.Tyrone:BAABLgAECn8kAAMbAAkJcRqLDQBtAgAbAAkJcRqLDQBtAgAXAAQJABCydwC1AAAAAA==.Tyrslan:BAAALgAECgYJEQAAAA==.',
Uf='Uffish:BAAALgAECgkJCQAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.Uglypriest:BAAALgADCgEJAQAAAA==.',
Un='Undeaddemon:BAABLgAECn8jAAQNAAkJJR3EOQDzAQANAAgJJR3EOQDzAQASAAMJEQ8THwB4AAAmAAEJkAbJeAAqAAAAAA==.Undeaddh:BAAALgAECgYJCAABLgAECgkJIwANACUdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIwANACUdAA==.Undeadscaly:BAAALgAECgYJBwABLgAECgkJIwANACUdAA==.Undignified:BAACLgAFFH8IAAIEAAMJcw3MAgC/AAAEAAMJcw3MAgC/AAAuAAQKf2EAAgQACQksG2YAAGwCAAQACQksG2YAAGwCAAAA.Unholysixth:BAAALgADCgkJNAAAAA==.Unicornquen:BAAALgAECgYJCQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Valkar:BAAALgAECgEJAgAAAA==.Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgUJEgAAAA==.',
Vi='Vidikan:BAAALgAECgQJEwAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAACLgAFFH8FAAICAAMJAAtdWwCWAAACAAMJAAtdWwCWAAAuAAQKfzQAAwIACQl0F+EiAD0CAAIACQl0F+EiAD0CAB0ABwmRFo4kAMMBAAAA.Vondi:BAEALgAECgUJBQABLgAFFAMJBwAcADUOAA==.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8gAAICAAkJaxobIABPAgACAAkJaxobIABPAgAAAA==.',
Vy='Vysena:BAAALgAECgEJAwAAAA==.',
Wa='Waldón:BAABLgAECn9LAAIoAAkJPg3+BACRAQAoAAkJPg3+BACRAQAAAA==.',
We='Weatherley:BAAALgAECgEJAQAAAA==.Werrik:BAABLgAECn8aAAINAAkJXyX8IgCJAgANAAkJXyX8IgCJAgABLgAFFAIJAgAMAAAAAA==.',
Wh='Whiskeytap:BAAALgAECgIJAgAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAICAAcJPxJcUgBqAQACAAcJPxJcUgBqAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJDAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAYJKgAJAPYiAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAABLgAECn8aAAIPAAkJ+wowGgDNAQAPAAkJ+wowGgDNAQAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.Xeroxpriest:BAAALgAECgcJCwAAAA==.',
Xi='Xilphira:BAAALgAECgUJCQAAAA==.',
Xl='Xlithz:BAABLgAECn80AAMhAAkJWRuaFgA6AgAhAAkJTxuaFgA6AgAiAAgJPhIiHQB0AQAAAA==.',
['Xí']='Xílo:BAABLgAECn9MAAMDAAkJjh4/FQCZAgADAAkJcxw/FQCZAgATAAYJtx6SGAC+AQAAAA==.',
Yg='Yggdrasil:BAAALgAECgkJCgAAAA==.',
Yl='Ylene:BAABLgAECn82AAIYAAkJkBDBBgA9AQAYAAkJkBDBBgA9AQAAAA==.',
Yo='Yoink:BAACLgAFFH8TAAIfAAQJkxq7VQBGAQAfAAQJkxq7VQBGAQAuAAQKfzsAAh8ACQk7JGwIAC8DAB8ACQk7JGwIAC8DAAAA.Yondu:BAAALgAECgEJAwABLgAECgkJKwAfAMgUAA==.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgAECgUJBwAAAA==.Zarinfur:BAABLgAECn82AAIJAAkJHBnGBwBYAgAJAAkJHBnGBwBYAgAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgYJCgAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAACLgAFFH8MAAIVAAUJ5QbuKwDfAAAVAAUJ5QbuKwDfAAAuAAQKfy0AAxUABwmsG0ZAAOEBABUABwmsG0ZAAOEBABYAAQn1AJGZABsAAAAA.Zequill:BAABLgAECn9QAAIaAAkJOCRgAgAjAwAaAAkJOCRgAgAjAwAAAA==.Zevsticles:BAABLgAECn8yAAIVAAkJmh++BwDWAQAVAAkJmh++BwDWAQAAAA==.',
Zh='Zhom:BAACLgAFFH8aAAIWAAQJAyGbDgB1AQAWAAQJAyGbDgB1AQAuAAQKf0AAAhYACQkcJIgBAAYDABYACQkcJIgBAAYDAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn9MAAIpAAkJQBseBQCVAgApAAkJQBseBQCVAgAAAA==.Zorlak:BAAALgAECgUJDgAAAA==.',
Zu='Zuxa:BAAALgADCgYJBgAAAA==.',
Zy='Zylofeather:BAAALgAECgUJBQAAAA==.',
['Àl']='Àlthor:BAAALgAECgcJDwABLgAFFAgJEgADAJwKAA==.',
['ße']='ßeast:BAABLgAECn8jAAIbAAgJiwn3NwAiAQAbAAgJiwn3NwAiAQAAAA==.',
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
