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

local lookup = {'Evoker-Preservation','Shaman-Restoration','DemonHunter-Devourer','Rogue-Assassination','Hunter-BeastMastery','Mage-Frost','Druid-Balance','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','DemonHunter-Havoc','Priest-Holy','Hunter-Marksmanship','Monk-Mistweaver','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Mage-Arcane','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','DemonHunter-Vengeance','Paladin-Protection','Warlock-Destruction','Evoker-Devastation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Abdervoke:BAABLgAECn8hAAIBAAkJRyL4AQBkAwABAAkJRyL4AQBkAwABLgAFFAMJBgACACYiAA==.Absent:BAAALgADCgEJAQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aeila:BAAALgADCgYJBgAAAA==.',
Af='Aferou:BAAALgADCgUJBQAAAA==.',
Ag='Agìnor:BAAALgAFFAMJAwABLgAFFAgJFgADACQQAA==.',
Ah='Ahsoul:BAAALgAECgEJAgAAAA==.',
Ai='Ainur:BAAALgAECgEJAgABLgAFFAMJCwAEAKEOAA==.',
Al='Alesia:BAAALgADCgEJAQAAAA==.Alessaah:BAAALgADCgcJCgABLgAFFAQJFQAFAIQeAA==.Aliadra:BAABLgAECn83AAIGAAkJqSRvDwD/AgAGAAkJqSRvDwD/AgAAAA==.Alistus:BAACLgAFFH8cAAIDAAQJPiUFEwCQAQADAAQJPiUFEwCQAQAuAAQKf0AAAgMACQlZJccDAEoDAAMACQlZJccDAEoDAAAA.Alphá:BAAALgAECgUJCQABLgAFFAMJBQACAAALAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJCQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAACLgAFFH8MAAIHAAMJlw5QGwCmAAAHAAMJlw5QGwCmAAAuAAQKf2IAAgcACQlWHeAOAG8CAAcACQlWHeAOAG8CAAAA.Anotheralt:BAAALgAECgcJDgAAAA==.',
Ar='Arcanegarm:BAABLgAECn8bAAIGAAcJIAJZ/wCuAAAGAAcJIAJZ/wCuAAAAAA==.Archeyois:BAABLgAECn8pAAMIAAkJVA9GKwCRAQAIAAkJVA9GKwCRAQABAAUJhQIRNwCzAAAAAA==.Armitage:BAABLgAECn8YAAMJAAkJ/w+0HABnAQAJAAkJXQ+0HABnAQAKAAcJQgvyHgARAQAAAA==.Arriorw:BAAALgAECgEJAQAAAA==.Arthonos:BAACLgAFFH8GAAILAAIJVAUBNABzAAALAAIJVAUBNABzAAAuAAQKfzUAAwsACQmaFQ8ZAP0BAAsACQmaFQ8ZAP0BAAwACAnjBWQnAFoBAAAA.Arugall:BAAALgAECgkJCQAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Aveliandis:BAAALgAECgUJBgAAAA==.Averille:BAAALgADCgYJCwAAAA==.',
Ax='Axuz:BAAALgADCgMJAwAAAA==.',
Ay='Ayraa:BAAALgAECgYJBQAAAA==.',
Az='Azerphage:BAAALgAECgYJDwABLgAECgcJCwANAAAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAABLgAECn8VAAIOAAYJOwrVrgDmAAAOAAYJOwrVrgDmAAAAAA==.Azzog:BAABLgAECn8bAAIPAAkJexfUBQBeAQAPAAkJexfUBQBeAQAAAA==.Azül:BAAALgAECgcJCAABLgAECgcJCwANAAAAAA==.',
Ba='Bacchanalian:BAAALgAECgcJDAABLgAECgkJCwANAAAAAA==.Baindyn:BAAALgAECgQJEwAAAA==.Barator:BAAALgAECgkJDQAAAA==.Barky:BAAALgADCgEJAQAAAA==.Bas:BAAALgAFFAEJBAAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJEAAAAA==.',
Bl='Blackröse:BAACLgAFFH8HAAIQAAQJfxbHBwAdAQAQAAQJfxbHBwAdAQAuAAQKfyMAAhAACAkzHYMQACoCABAACAkzHYMQACoCAAAA.Blackrøse:BAABLgAECn8pAAICAAkJHxf7CQCcAQACAAkJHxf7CQCcAQABLgAFFAQJBwAQAH8WAA==.Bladebane:BAABLgAECn8lAAIPAAkJGgFPPQCbAAAPAAkJGgFPPQCbAAAAAA==.Blandmonk:BAAALgAECgMJBQAAAA==.Blksunshine:BAAALgAECgkJDQAAAA==.',
Bo='Bolash:BAAALgAECgYJCwAAAA==.Boomnbloom:BAAALgAECgMJCAAAAA==.Bort:BAAALgAECgEJBAAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breegorn:BAAALgAECgUJBgAAAA==.Breni:BAAALgAFFAEJAQABLgAFFAQJFQAFAIQeAA==.Bruscha:BAAALgAECgUJEgAAAA==.',
Bu='Bulvhine:BAABLgAECn8xAAIRAAkJfyDGBAB9AgARAAkJfyDGBAB9AgAAAA==.',
['Bù']='Bùmblebee:BAAALgAECgMJAwAAAA==.',
Ca='Camferd:BAAALgAECgEJAgAAAA==.Camford:BAABLgAECn8ZAAIGAAcJ8QhZvQBoAQAGAAcJ8QhZvQBoAQAAAA==.Cantatrix:BAABLgAECn8bAAIOAAYJ9gt4owD5AAAOAAYJ9gt4owD5AAAAAA==.Capslok:BAAALgAFFAEJAQAAAA==.Captinmeat:BAAALgAECgUJCAAAAA==.Cargoan:BAAALgAECgMJAwAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgABLgAECgkJCwANAAAAAA==.',
Ce='Cecilx:BAABLgAECn8zAAISAAkJWCRrAgCGAwASAAkJWCRrAgCGAwAAAA==.Cellybelleri:BAAALgAECgQJBAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Chillana:BAAALgAECgQJBAAAAA==.Chimerax:BAACLgAFFH8bAAMTAAYJlx54AgCDAQATAAYJlx54AgCDAQAOAAEJlxedwQBHAAAuAAQKfy4AAxMACQkQIQACALACABMACQkQIQACALACAA4ACAlDEwt8AEEBAAAA.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIRAAgJMAZQoQA9AQARAAgJMAZQoQA9AQAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAACLgAFFH8PAAIDAAQJZRDlSAAOAQADAAQJZRDlSAAOAQAuAAQKfywAAwMACQkIG2AqACACAAMACQkIG2AqACACABQAAwmIBM1ZAH0AAAAA.',
Cl='Clairíty:BAABLgAECn8gAAIVAAgJsh4DDgCGAgAVAAgJsh4DDgCGAgAAAA==.Clarky:BAAALgAECgYJEAAAAA==.Click:BAABLgAECn9EAAIFAAkJUxzvEwCzAgAFAAkJUxzvEwCzAgAAAA==.Cloutfarmer:BAACLgAFFH8QAAIFAAQJGyC5KQBhAQAFAAQJGyC5KQBhAQAuAAQKf0AABAUACQlKJf0EAEEDAAUACQlKJf0EAEEDABYABgkZHFspAOABABAAAglFHfpVAFUAAAAA.',
Co='Comadore:BAACLgAFFH8QAAIRAAUJDQyFWgD7AAARAAUJDQyFWgD7AAAuAAQKfxwAAhEACAk4HNg4AEACABEACAk4HNg4AEACAAAA.Coronae:BAAALgAECgIJAwAAAA==.Corrose:BAAALgAECgIJAgAAAA==.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Crankycad:BAAALgADCgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEBLgAECn8VAAIXAAkJMyIQBgBFAwAXAAkJMyIQBgBFAwABLgADCgYJBgANAAAAAA==.Critmypants:BAAALgAECgIJAgAAAA==.',
Cu='Curator:BAAALgADCgUJBQAAAA==.',
Cy='Cylithina:BAAALgAECgQJCgAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Dalair:BAAALgAECgQJBAAAAA==.Daphe:BAAALgAECgEJAwAAAA==.Dartheior:BAAALgAECgIJAwAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAwAAAA==.Deadseksi:BAAALgAECgcJEAAAAA==.Deathslead:BAABLgAECn9NAAMFAAkJSxfjBwAOAgAFAAkJSxfjBwAOAgAWAAUJ3AHpMQBSAAAAAA==.Decrepe:BAACLgAFFH8RAAIYAAQJ2BhjJwAhAQAYAAQJ2BhjJwAhAQAuAAQKfzsAAhgACQlIIIAKABUDABgACQlIIIAKABUDAAAA.Dedrepe:BAAALgAECggJCQAAAA==.Delph:BAAALgAFFAEJAgAAAA==.Deshal:BAAALgAECgYJEQAAAA==.Desomas:BAAALgAECgIJAgAAAA==.Dethklock:BAAALgAECgEJAQAAAA==.Dethwingchun:BAAALgAECgQJCQABLgAECgQJEwANAAAAAA==.Detrath:BAAALgAECgEJAQAAAA==.',
Di='Dieurnal:BAAALgAECgQJAQAAAA==.Discostar:BAABLgAECn8vAAMYAAkJUxdaLgDsAQAYAAgJDBZaLgDsAQAHAAgJghd+CgAYAQAAAA==.Distill:BAAALgAECgIJAgABLgAFFAkJKAAZAAElAA==.',
Dn='Dni:BAAALgAECgMJBAABLgAECgkJLwAHAMAbAA==.',
Do='Dominicm:BAAALgAECgYJEgAAAA==.Dotdotdis:BAAALgAECgMJAwAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Dracosixth:BAAALgADCgkJHwAAAA==.Dragonpro:BAAALgADCgUJBQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgkJDQAAAA==.Druth:BAABLgAECn8tAAIaAAgJRx++CgBDAgAaAAgJRx++CgBDAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgUJEQAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einari:BAAALgAECggJCAAAAA==.Einark:BAACLgAFFH8MAAIXAAMJIBdOHwDHAAAXAAMJIBdOHwDHAAAuAAQKf1oAAxcACQltIOwBAMQCABcACQltIOwBAMQCABsACAnMHi4NAHICAAAA.Eino:BAAALgAECgEJAQAAAA==.',
Ek='Ekiim:BAAALgAECgQJBAABLgAECgUJCgANAAAAAA==.',
El='Eldrond:BAAALgAECgQJCAABLgAECgUJCQANAAAAAA==.Elinis:BAAALgAFFAEJAQAAAA==.Elsbett:BAAALgAECgUJBQABLgAECgkJLgAGAAEaAA==.Elska:BAAALgADCgkJCQAAAA==.',
Em='Emdralaeth:BAAALgAECgEJAQAAAA==.',
En='Ennauríon:BAAALgAECgUJCQAAAA==.Entropy:BAEALgAFFAMJBAABLgAFFAUJDAAcAPgSAA==.',
Er='Eridor:BAAALgAECgcJEQAAAA==.Erissama:BAAALgADCgEJAQAAAA==.',
Es='Esbernia:BAAALgADCgMJAwAAAA==.',
Ex='Exek:BAABLgAECn8yAAMVAAgJsBcvFwAVAgAVAAgJsBcvFwAVAgALAAYJCA4AFACfAAAAAA==.',
Ey='Eyeofnature:BAAALgAECgEJAQAAAA==.',
Ez='Ez:BAAALgAECgEJAQABLgAECgkJMAAdACgbAA==.',
Fa='Fabaztard:BAABLgAECn8kAAIHAAkJ1hIuIwCwAQAHAAkJ1hIuIwCwAQAAAA==.Faline:BAABLgAECn8zAAIYAAkJUwvJRQB5AQAYAAkJUwvJRQB5AQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8bAAIDAAYJNxHGJQDuAAADAAYJNxHGJQDuAAAuAAQKfyMAAgMACQlUGs00ACUCAAMACQlUGs00ACUCAAAA.Felghoul:BAAALgAECgcJEgAAAA==.Felldozer:BAAALgAECgEJAQAAAA==.Fenrakar:BAAALgAECgUJCAAAAA==.Ferlane:BAAALgADCgcJBwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn9BAAISAAkJKR4HCgDrAgASAAkJKR4HCgDrAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.Floofi:BAAALgAECgcJDwAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJCAAAAA==.Forloss:BAAALgAECgMJAwAAAA==.Foxknight:BAABLgAECn8YAAQeAAUJgBAdGgABAQAeAAUJgBAdGgABAQAPAAQJ4QM2SwBiAAAfAAMJ3A1dOgBeAAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgANAAAAAA==.Frostdrake:BAAALgAECgUJBQAAAA==.',
Ft='Ftx:BAABLgAECn8hAAMgAAkJcx2oDQC4AgAgAAgJlR+oDQC4AgAbAAUJYxe/RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAIRAAkJARwsOAAhAgARAAkJARwsOAAhAgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaern:BAAALgAECgEJAwABLgAFFAIJAgANAAAAAA==.Gaidan:BAACLgAFFH8RAAIHAAYJKRNsDQBFAQAHAAYJKRNsDQBFAQAuAAQKfyEAAgcACQmlFogRAI8CAAcACQmlFogRAI8CAAEuAAUUCAkWAAMAJBAA.Gaidin:BAACLgAFFH8WAAIDAAgJJBB+FwBgAQADAAgJJBB+FwBgAQAuAAQKfyAAAgMACQlGHgY9ANQBAAMACQlGHgY9ANQBAAAA.Gameslayer:BAABLgAECn8gAAMhAAkJcB2dKwCmAQAhAAYJcx+dKwCmAQAiAAQJzxdeMQACAQAAAA==.Gankzilla:BAACLgAFFH8bAAMZAAYJSBPUGQBGAQAZAAUJHRbUGQBGAQAEAAIJsAywBgBNAAAuAAQKfycAAwQACQmeG2EJAKoBABkABgl3GNklAMoBAAQABwkfG2EJAKoBAAAA.Garothos:BAAALgAECgIJAgABLgAECgUJCAANAAAAAA==.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Genrealwee:BAAALgAECgEJAQAAAA==.Get:BAAALgADCgkJDAAAAA==.',
Gh='Ghalumvhar:BAABLgAECn8fAAIRAAcJBRtXTwDaAQARAAcJBRtXTwDaAQAAAA==.Ghoulaid:BAAALgAECgcJBwAAAA==.Ghrìmm:BAABLgAECn8lAAQQAAkJ6w/EGgDIAQAQAAkJIA3EGgDIAQAFAAgJxA5OaQBwAQAWAAEJ+QZkRAAiAAAAAA==.',
Gi='Gila:BAAALgAECggJEAAAAA==.Gingasorrow:BAABLgAECn80AAIYAAkJnBkLFgCYAgAYAAkJnBkLFgCYAgAAAA==.Gizzle:BAACLgAFFH8TAAIRAAYJpg/zLADXAAARAAYJpg/zLADXAAAuAAQKfyYAAhEACQmoFltVAMoBABEACQmoFltVAMoBAAAA.',
Gl='Gloccamorra:BAAALgADCgEJAQAAAA==.',
Gr='Greekfire:BAABLgAECn8YAAISAAgJ3yE5GwA7AgASAAgJ3yE5GwA7AgAAAA==.Grimgrug:BAAALgADCgUJBQAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn80AAIFAAgJqSKCGQCNAgAFAAgJqSKCGQCNAgAAAA==.Grændal:BAACLgAFFH8IAAILAAQJRhDXDgAEAQALAAQJRhDXDgAEAQAuAAQKfxwAAgsABwkkGQMGAIkBAAsABwkkGQMGAIkBAAEuAAUUCAkWAAMAJBAA.',
Ha='Hahatotem:BAAALgADCgMJAwAAAA==.Hanjha:BAABLgAECn9HAAMQAAkJkR/AAwD4AgAQAAgJkR/AAwD4AgAFAAEJAAA7zwA3AAAAAA==.Harunhwa:BAAALgAECgMJBQAAAA==.Haseo:BAAALgAECgEJAQABLgAFFAMJCwAEAKEOAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAFFAMJBQARAAwdAA==.Helldozer:BAACLgAFFH8FAAIdAAIJZw3kJwBxAAAdAAIJZw3kJwBxAAAuAAQKf0oAAx0ACQkvFg4YACMCAB0ACQkvFg4YACMCAAIAAgnPFFynAH0AAAAA.',
Ho='Hooj:BAAALgADCgYJBgAAAA==.Horde:BAAALgADCgEJAQABLgAECgEJAQANAAAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAABLgAECn8WAAIGAAYJDA39HwDhAAAGAAYJDA39HwDhAAAAAA==.',
Hw='Hwore:BAAALgAECgQJBAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgANAAAAAA==.Hypnocide:BAECLgAFFH8HAAIDAAMJewRBSgBOAAADAAMJewRBSgBOAAAuAAQKf1UAAgMACQlnGXwDAC8CAAMACQlnGXwDAC8CAAAA.',
['Hã']='Hãil:BAAALgADCgIJAQAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
Ib='Ibuki:BAAALgAFFAEJAQABLgAFFAYJGwASADoHAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Ig='Iguanajon:BAAALgAECgEJAgAAAA==.',
Il='Illandren:BAACLgAFFH8RAAIQAAQJlggaGAARAQAQAAQJlggaGAARAQAuAAQKfxsAAxAACQljC+0cALUBABAACQljC+0cALUBABYACAk6A9gfALEAAAAA.Illusiveeyes:BAAALgADCgYJDAAAAA==.',
Im='Impsane:BAABLgAECn8uAAIOAAkJ1hByBwCoAQAOAAkJ1hByBwCoAQAAAA==.',
In='Incøgnitø:BAAALgAECgEJAQABLgAECgkJHQAYADIcAA==.Indolence:BAEALgAECgIJAgABLgAECgUJDgANAAAAAA==.Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8jAAIGAAcJsQj0wgAFAQAGAAcJsQj0wgAFAQAAAA==.Innøminate:BAABLgAECn8iAAIFAAgJwhF0DwB9AQAFAAgJwhF0DwB9AQABLgAECgkJHQAYADIcAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQEAAgJlhqJBwDgAQAEAAgJ5xmJBwDgAQAZAAUJoxxSMwBwAQAjAAQJjg9mCQDZAAAAAA==.',
Is='Isadavrah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgQJBwAAAA==.Isellrocks:BAAALgAECgQJBQAAAA==.Issadin:BAAALgAECgUJBwABLgAECgYJDAANAAAAAA==.Issadruiid:BAAALgADCgYJBgABLgAECgYJDAANAAAAAA==.Issammonk:BAAALgAECgEJAQABLgAECgYJDAANAAAAAA==.Issarage:BAAALgAECgQJCQABLgAECgYJDAANAAAAAA==.Issashammy:BAAALgAECgYJDAAAAA==.',
Ja='Jaxxa:BAABLgAECn88AAIFAAkJ6xqCHwBqAgAFAAkJ6xqCHwBqAgAAAA==.',
Je='Jeddiah:BAABLgAECn8kAAMEAAcJIQ/TDQBKAQAEAAcJIQ/TDQBKAQAZAAQJLgxhRwCdAAAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jiffarous:BAAALgAECgQJBwAAAA==.Jinkès:BAABLgAECn87AAIWAAkJRBYjAQAOAgAWAAkJRBYjAQAOAgAAAA==.',
Jp='Jpank:BAAALgAFFAEJAwAAAA==.',
Ju='Jubei:BAABLgAFFH8IAAIRAAYJBwxsVwBlAAARAAYJBwxsVwBlAAAAAA==.Judis:BAACLgAFFH8JAAIEAAMJ2hapAgDwAAAEAAMJ2hapAgDwAAAuAAQKf1QAAgQACQlFH7wBAOICAAQACQlFH7wBAOICAAAA.Judyth:BAAALgAECgIJBQAAAA==.Juicy:BAAALgADCgIJAgAAAA==.Justokevoker:BAABLgAFFH8LAAIIAAQJpxHcMgD2AAAIAAQJpxHcMgD2AAAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8cAAIbAAkJnR97CAC/AgAbAAkJnR97CAC/AgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kalipally:BAAALgAECgcJDgAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamford:BAAALgAECgEJAQAAAA==.Kamiportal:BAAALgAECgcJCgAAAA==.Kanajotoma:BAAALgAECgUJEgAAAA==.Karlai:BAACLgAFFH8GAAMeAAMJPg8WDQDNAAAeAAMJPg8WDQDNAAAfAAEJngtcpgA5AAAuAAQKfy0AAx8ACAlYHHYOAFEBAB4ABwm6GuUEAAACAB8ABwmFG3YOAFEBAAEuAAUUCAkWAAMAJBAA.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAABLgAECn8bAAILAAcJVQ0wDAD7AAALAAcJVQ0wDAD7AAAAAA==.Keleena:BAECLgAFFH8MAAISAAMJchebEwDIAAASAAMJchebEwDIAAAuAAQKf3EAAhIACQncIFIBAMgCABIACQncIFIBAMgCAAAA.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Kg='Kgor:BAAALgAECgcJBwAAAA==.',
Kh='Khaerne:BAAALgAECgEJAQABLgAFFAIJAgANAAAAAA==.Khordelia:BAAALgAFFAIJAgAAAA==.',
Ki='Killiana:BAAALgADCgUJBQAAAA==.Kinst:BAACLgAFFH8KAAIFAAMJHRovKwD3AAAFAAMJHRovKwD3AAAuAAQKf0YAAwUACQnEHzMSAMACAAUACQnEHzMSAMACABYABgmvEto/AFsBAAAA.Kirigaya:BAAALgAECgMJCQAAAA==.Kisäi:BAABLgAECn8pAAMDAAkJ1RxbIACPAgADAAkJ1RxbIACPAgAkAAIJHBGVKABiAAAAAA==.Kitanyia:BAABLgAECn9BAAIhAAkJKRnQAgA4AgAhAAkJKRnQAgA4AgAAAA==.Kittiy:BAACLgAFFH8FAAIHAAIJDwVIJwBVAAAHAAIJDwVIJwBVAAAuAAQKfzcAAwcACAlTCkxDAP8AAAcACAlTCkxDAP8AABgABgkqB1F8AMMAAAAA.',
Ko='Kordelia:BAABLgAECn8mAAIGAAkJJh8cHwCjAgAGAAkJJh8cHwCjAgABLgAFFAIJAgANAAAAAA==.Koru:BAAALgAECgIJAgAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kr='Krench:BAAALgAECgEJAQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgUJCQAAAA==.Kyloon:BAAALgAECggJDQAAAA==.Kyrah:BAACLgAFFH8GAAMTAAMJMxCzEwBOAAAOAAIJvwrupgCDAAATAAEJGxuzEwBOAAAuAAQKf0QAAw4ACQmuGvgEAAsCAA4ACQkAGPgEAAsCABMABgnfG8sGAOsBAAAA.',
La='Lamanira:BAAALgAECgkJDQAAAA==.Lancier:BAAALgAECgcJCwAAAA==.',
Ld='Ldyaria:BAAALgAECgQJCQAAAA==.',
Le='Lecleme:BAACLgAFFH8GAAIfAAMJZBEEoADUAAAfAAMJZBEEoADUAAAuAAQKfyEAAh8ACAleGE5IAOkBAB8ACAleGE5IAOkBAAAA.Lejend:BAABLgAECn9KAAMiAAkJyCXiAABxAwAiAAkJyCXiAABxAwAhAAMJfRW8fwC+AAAAAA==.Lenorra:BAAALgAECgMJBQAAAA==.Lenthalis:BAAALgAECgUJEQAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lifeslead:BAAALgADCgIJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECggJDgAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAIAOsLAA==.Lockheéd:BAAALgAFFAEJAQAAAA==.Lonelyhearts:BAABLgAECn89AAIRAAkJrQsRcwCIAQARAAkJrQsRcwCIAQAAAA==.Lonestar:BAAALgAECgYJDwAAAA==.Lonestarr:BAAALgAECgQJDAAAAA==.Loxricia:BAAALgADCgEJAQAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAIVAAkJ7w52LwCFAQAVAAkJ7w52LwCFAQAAAA==.',
Ly='Lytol:BAABLgAECn8qAAMcAAkJtReFAgAoAgAcAAkJtReFAgAoAgAGAAMJXgQ8IgF1AAAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAFFAQJCwAIANkVAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maege:BAAALgADCggJCAAAAA==.Maenad:BAAALgAECgkJCwAAAA==.Maeple:BAABLgAECn8pAAMVAAkJ+SEhBABDAwAVAAkJ+SEhBABDAwAMAAMJugpfXgCFAAAAAA==.Magikin:BAAALgAECgQJCAAAAA==.Magrat:BAAALgAECgYJDQAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.Maximilleon:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8gAAMQAAcJeiO5AgANAgAQAAcJeiO5AgANAgAWAAEJjAS6JABVAAAuAAQKfxsAAxAABwmMJXMEANQCABAABwkxJXMEANQCABYAAQksIwR3AGMAAAEuAAUUCAk0AAYAfyYA.',
Me='Mechagnome:BAACLgAFFH8GAAIbAAIJoBsILgCQAAAbAAIJoBsILgCQAAAuAAQKfzQAAxsACQnUIMsHAMsCABsACQnUIMsHAMsCABcACAkJBAU6AAABAAAA.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMRAAYJkhbKegCEAQARAAYJEhbKegCEAQAlAAQJTQn+NgCEAAAAAA==.Meigna:BAABLgAECn8qAAILAAgJuR2MEQBKAgALAAgJuR2MEQBKAgAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8qAAMKAAYJ9iKSBAByAQAKAAUJeyOSBAByAQAJAAUJMh4aCQBhAQAuAAQKfygAAwoABwlnJlYDAAMDAAoABwlnJlYDAAMDAAkABQnrIwEXAJoBAAAA.Melritza:BAAALgAECgQJCAABLgAFFAQJFQAFAIQeAA==.Mentock:BAABLgAECn8YAAIGAAYJ4hCEqwApAQAGAAYJ4hCEqwApAQAAAA==.Merdock:BAAALgAECgQJCQAAAA==.Merelandra:BAAALgADCgkJLwAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Michelle:BAAALgADCgQJBAAAAA==.Miliara:BAAALgADCgEJAQAAAA==.Miradh:BAEALgAECgQJBAABLgAECgUJDgANAAAAAA==.Missmaam:BAABLgAECn8ZAAMVAAkJjRpdFQAqAgAVAAgJ2hldFQAqAgALAAUJuxIGDQDsAAAAAA==.Mistroot:BAAALgAECgkJDAAAAA==.Mistshealz:BAAALgAECgEJAQABLgAFFAQJEAAfAMQdAA==.Mithrandir:BAACLgAFFH8HAAMOAAIJPwMhWABQAAAOAAIJPwMhWABQAAAmAAEJOQDVLQATAAAuAAQKfysAAyYABwnqFDsFABEBAA4ABwkFEfhxAFYBACYABQkQFzsFABEBAAAA.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAABLgAECn8cAAMaAAkJyxsdDwD4AQAaAAkJyxsdDwD4AQAhAAIJ6xAGlABvAAAAAA==.',
Mo='Moe:BAAALgAECgkJBAAAAA==.Monkfox:BAAALgAECgcJBwABLgAFFAQJEwAgABElAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudanca:BAAALgAECgMJAwABLgAECgUJEgANAAAAAA==.Mudflap:BAABLgAECn8VAAIFAAYJBg0/LwCWAAAFAAYJBg0/LwCWAAAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAFFAQJCwAIANkVAA==.Muztang:BAABLgAECn9CAAMiAAkJ1x5vBADUAgAiAAkJ1x5vBADUAgAhAAYJihOETgAOAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgYJCgAAAA==.',
My='Mythandwel:BAABLgAECn8wAAIUAAgJqgrjLQAUAQAUAAgJqgrjLQAUAQAAAA==.',
['Mä']='Mäddieness:BAAALgAECgIJAgAAAA==.Mäddiey:BAAALgAECgQJCgAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8TAAIgAAQJESXZDgCyAQAgAAQJESXZDgCyAQAuAAQKfz4AAyAACQnjJLICAC4DACAACQnjJLICAC4DABcAAQmvAhzfABEAAAAA.',
Na='Nace:BAABLgAECn8qAAIZAAkJ7BOvGQA2AgAZAAkJ7BOvGQA2AgAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgAECgUJBQAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nariar:BAAALgAECgMJAwABLgAFFAYJGwASADoHAA==.Nateldin:BAABLgAECn8YAAMRAAkJhwmIkABbAQARAAkJ8AeIkABbAQAlAAIJ9Q61UgArAAAAAA==.',
Ne='Neoba:BAAALgAECgUJCAAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECggJDQABLgAECgkJHwAVAKMHAA==.Nikiso:BAAALgADCgYJBwAAAA==.',
No='Nocainus:BAABLgAECn9NAAIPAAkJwCGJAwAFAwAPAAkJwCGJAwAFAwAAAA==.Nosehole:BAABLgAECn8iAAICAAcJ0hTZPAC7AQACAAcJ0hTZPAC7AQAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQABLgAFFAYJCQAbALELAA==.',
['Nø']='Nøtsure:BAABLgAECn8dAAMYAAkJMhy4JQAgAgAYAAkJMhy4JQAgAgAHAAIJqwyJdABdAAAAAA==.',
Ob='Obesityy:BAABLgAECn8xAAIZAAkJph5yCACfAgAZAAkJph5yCACfAgAAAA==.Obsidia:BAABLgAECn8oAAIOAAkJSQ8VSwC5AQAOAAkJSQ8VSwC5AQAAAA==.',
Oc='Octopusprime:BAAALgAECgkJEQAAAA==.',
Ol='Oled:BAAALgADCgIJAgAAAA==.Ollix:BAAALgAECgEJBAABLgAECgkJTAADAI4eAA==.',
Om='Omelette:BAABLgAECn8fAAIFAAkJiRz9GwB9AgAFAAkJiRz9GwB9AgAAAA==.',
On='Onik:BAAALgAECgIJAgABLgAECgUJCQANAAAAAA==.',
Op='Ophj:BAACLgAFFH8IAAIGAAQJsBR2awAMAQAGAAQJsBR2awAMAQAuAAQKfyAAAgYACQm2ImMHAJEDAAYACQm2ImMHAJEDAAAA.',
Or='Orangejulius:BAAALgAECgUJCgAAAA==.Orangutan:BAAALgAECgQJBQAAAA==.Oriclysmic:BAABLgAECn8iAAQBAAgJ5h3SBwB2AgABAAgJ5h3SBwB2AgAIAAQJhQSiTwCPAAAnAAEJAAAjPwAzAAAAAA==.Oriigami:BAAALgAECggJDAAAAA==.Orinoheal:BAAALgAECgYJBgAAAA==.Orochiimaru:BAAALgAECgQJBQABLgAFFAMJCwAEAKEOAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pa='Patala:BAAALgADCgcJCgAAAA==.',
Pe='Perilous:BAAALgAECgUJEgAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phalix:BAAALgAFFAIJAgABLgAFFAQJGgAWAAMhAA==.Phat:BAAALgAECgQJBgAAAA==.Phoelar:BAABLgAECn8ZAAMHAAkJ7BQkCwAMAQAHAAgJaxYkCwAMAQAYAAMJVQ7cEwB+AAAAAA==.Phuumyn:BAABLgAECn9FAAIbAAkJTyVOAQBoAwAbAAkJTyVOAQBoAwAAAA==.',
Pi='Piccoblast:BAACLgAFFH8fAAIGAAgJFBYSDQCzAQAGAAgJFBYSDQCzAQAuAAQKfy0AAgYACAnYIuEcAAIDAAYACAnYIuEcAAIDAAAA.Piccolocks:BAAALgAECgYJCwABLgAFFAgJHwAGABQWAA==.Piccopew:BAAALgAECgEJAQABLgAFFAgJHwAGABQWAA==.Pichus:BAAALgAECgEJAQABLgAFFAMJBQACAAALAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAFFAIJAwABLgAFFAQJGgAWAAMhAA==.Pierz:BAAALgAECgEJAQAAAA==.Piickles:BAACLgAFFH8qAAMVAAgJ0RVTBgD1AQAVAAgJ0RVTBgD1AQAMAAQJuxJMJgAYAQAuAAQKfyEAAhUACQlTHtoLAJMCABUACQlTHtoLAJMCAAAA.Pinkcanibus:BAABLgAECn8aAAIFAAgJvQSzbwAZAQAFAAgJvQSzbwAZAQAAAA==.Pippopper:BAAALgAECgEJAQABLgAFFAQJHAADAD4lAA==.Pity:BAABLgAECn8XAAIDAAkJjg2UUQCRAQADAAkJjg2UUQCRAQAAAA==.',
Pl='Plutø:BAABLgAECn9PAAQeAAkJ4xuNAQA5AgAPAAcJth4MDABRAgAeAAkJ/hWNAQA5AgAfAAkJghIMUQDQAQAAAA==.',
Po='Polylocks:BAABLgAECn8UAAIOAAgJPBQdSgC8AQAOAAgJPBQdSgC8AQAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAECLgAFFH8MAAIcAAUJ+BIOAgD4AAAcAAUJ+BIOAgD4AAAuAAQKfy4AAhwACQmsG9EDANEBABwACQmsG9EDANEBAAAA.Praycation:BAAALgAECgYJBgAAAA==.Promethius:BAAALgAECgcJCQABLgAFFAMJBwAOAD8DAA==.Protein:BAABLgAECn8gAAIhAAcJ0BURPQBSAQAhAAcJ0BURPQBSAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgANAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn9JAAIYAAkJER0UDQD0AgAYAAkJER0UDQD0AgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECggJFAAOADwUAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quiet:BAAALgAECgQJBAAAAA==.Quilian:BAACLgAFFH8ZAAIVAAUJdCS/BQAFAgAVAAUJdCS/BQAFAgAuAAQKfyYAAhUACQlAISkEABIDABUACQlAISkEABIDAAAA.',
Ra='Raelynn:BAABLgAECn9NAAIVAAkJvBk/DACiAgAVAAkJvBk/DACiAgAAAA==.Raevenhart:BAACLgAFFH8GAAIWAAMJlgivIACnAAAWAAMJlgivIACnAAAuAAQKfx0AAhYACAlZFWIkAAUCABYACAlZFWIkAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgAECgMJBAAAAA==.Rashalisk:BAAALgAECgQJBAAAAA==.Raymond:BAAALgADCgcJBwAAAA==.Razerblade:BAAALgAECgEJAQAAAA==.',
Re='Rebarbative:BAABLgAECn8iAAMOAAkJoQ5dSwC4AQAOAAkJoQ5dSwC4AQAmAAMJfAXZUQB5AAAAAA==.Rednecker:BAAALgAECgEJAQABLgAECgQJBwANAAAAAA==.Redvex:BAACLgAFFH8PAAIOAAQJyxnjRABAAQAOAAQJyxnjRABAAQAuAAQKf0UABA4ACQnFJYsEAEcDAA4ACQmQJYsEAEcDACYABQkxII8SALcBABMAAglwI5UkAJ4AAAAA.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn89AAMRAAkJ5RFqYwCpAQARAAkJ2A9qYwCpAQAlAAcJfxN8BwD8AAAAAA==.Renduval:BAAALgAECgIJAgAAAA==.Restohexual:BAAALgAECgEJAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8sAAISAAkJhRoeEwB4AgASAAkJhRoeEwB4AgAAAA==.',
Rh='Rhedman:BAABLgAECn8aAAMeAAYJ7QqrHADpAAAeAAUJ7QqrHADpAAAfAAYJdAU87wDBAAAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinah:BAABLgAFFH8JAAIZAAMJjhQSFADgAAAZAAMJjhQSFADgAAAAAA==.Rinahrune:BAAALgAECgMJBgAAAA==.Rinahvoid:BAAALgAECgEJAQAAAA==.',
Ro='Robat:BAAALgADCggJDQAAAA==.Ronwen:BAAALgAECgQJBQABLgAFFAYJGwASADoHAA==.Rootbeard:BAAALgAECgUJBgAAAA==.Rorhan:BAAALgAECgYJBgAAAA==.Rosanna:BAAALgAECggJCgAAAA==.Roselyn:BAABLgAECn8VAAIVAAcJaxHEKgByAQAVAAcJaxHEKgByAQAAAA==.Rotyr:BAABLgAECn9LAAIMAAkJKRrgAQCnAgAMAAkJKRrgAQCnAgAAAA==.',
Ru='Ruana:BAEALgAECgUJDgAAAA==.Rubberlip:BAAALgAECgQJBAAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Saffron:BAEALgAECgMJAwABLgAECgUJDgANAAAAAA==.Sairen:BAAALgADCgkJCQABLgAECgkJMQAKAIATAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Santhela:BAAALgAECgQJBwAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Saturñ:BAAALgAECgYJEgAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8lAAIFAAgJtBp5MwAOAgAFAAgJtBp5MwAOAgAAAA==.Scots:BAAALgADCgcJFwAAAA==.Scubbs:BAACLgAFFH8VAAICAAUJ4xIIJQBXAQACAAUJ4xIIJQBXAQAuAAQKfyEAAgIACAkuFkkiABECAAIACAkuFkkiABECAAAA.Scubbsboo:BAACLgAFFH8IAAIXAAUJ7Q/MGQD9AAAXAAUJ7Q/MGQD9AAAuAAQKfxsAAhcABwmoG54cADMCABcABwmoG54cADMCAAEuAAUUBQkVAAIA4xIA.',
Se='Seras:BAAALgAECgUJBQAAAA==.Serka:BAAALgADCgYJBgAAAA==.Servantes:BAABLgAECn9KAAMYAAkJghCNOAC0AQAYAAkJghCNOAC0AQAHAAEJTwW7ngAjAAAAAA==.',
Sg='Sgthulka:BAAALgAECgEJAQAAAA==.',
Sh='Shackleford:BAABLgAECn9HAAQMAAkJ4h4ZDQCbAgAMAAkJ4h4ZDQCbAgALAAgJpRZ2GwDpAQAVAAcJLBPDLABlAQAAAA==.Shamae:BAAALgAECgYJDQAAAA==.Shamrockk:BAAALgADCgIJAgAAAA==.Shamwõwz:BAAALgAFFAMJBAAAAA==.Shaolin:BAAALgAECgkJCQAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCgAAAA==.Shotya:BAABLgAECn9NAAIFAAkJlwvPTQC5AQAFAAkJlwvPTQC5AQAAAA==.Shyvàna:BAAALgAECgIJAgABLgAFFAYJGwASADoHAA==.',
Si='Siath:BAABLgAECn8UAAMIAAgJ6wtnQQAkAQAIAAgJ6wtnQQAkAQAnAAIJ6gg7PQA5AAAAAA==.Silvino:BAAALgADCgEJAQABLgAECgkJLwAHAMAbAA==.Simpforsouls:BAAALgADCgEJAQAAAA==.Sixpacktnt:BAAALgADCgkJNQAAAA==.Sixthdemon:BAAALgADCgUJCgAAAA==.Sixthknight:BAABLgAECn8jAAIRAAcJlAslMwCLAAARAAcJlAslMwCLAAAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8eAAISAAgJXyapBABNAwASAAgJXyapBABNAwAAAA==.',
Sn='Snacky:BAAALgAECgIJAgAAAA==.Snarkypony:BAABLgAECn8iAAIGAAkJsBCcCgC7AQAGAAkJsBCcCgC7AQAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorocide:BAAALgADCgUJBQAAAA==.Sorrowbane:BAAALgAECgEJAgAAAA==.Sorsere:BAABLgAECn9BAAIOAAkJzh4VFACtAgAOAAkJzh4VFACtAgAAAA==.',
Sp='Spcecialk:BAABLgAECn8dAAIaAAcJLQulKADvAAAaAAcJLQulKADvAAAAAA==.Specialk:BAACLgAFFH8IAAIdAAIJ0wsIRgBzAAAdAAIJ0wsIRgBzAAAuAAQKfz4AAx0ACAlJErwyAHIBAB0ACAlJErwyAHIBAAIAAwmsBr6xAGYAAAAA.',
Sq='Squallie:BAABLgAECn8ZAAIYAAYJqRNLTwBSAQAYAAYJqRNLTwBSAQAAAA==.',
St='Starcaller:BAAALgAECgYJBgAAAA==.Starryy:BAAALgAECgUJBQAAAA==.Steamedhams:BAAALgAECgcJCwAAAA==.Stirredihime:BAAALgAFFAEJAQAAAA==.',
Su='Sulph:BAAALgAECgEJAQABLgAECgkJTAADAI4eAA==.Sundorei:BAAALgAECgQJCQAAAA==.Sunscale:BAAALgADCgEJAQAAAA==.',
Sw='Swipper:BAAALgAECgMJBQABLgAECgUJGAAeAIAQAA==.',
Sy='Synnoxia:BAEALgAECgQJBAABLgAFFAUJDAAcAPgSAA==.',
['Sû']='Sûlph:BAAALgAECgkJAwAAAA==.',
Ta='Taartt:BAAALgAFFAQJBAABLgAFFAcJJwABAJkTAA==.Tahoe:BAAALgADCgIJAgAAAA==.Talan:BAAALgAECgcJCgAAAA==.Talshekar:BAABLgAECn8lAAInAAgJsw3RCgBuAQAnAAgJsw3RCgBuAQAAAA==.Tarsis:BAABLgAECn8oAAIPAAkJeB97BQDRAgAPAAkJeB97BQDRAgAAAA==.',
Te='Teiana:BAABLgAECn8vAAIRAAkJ9x8fJAB0AgARAAkJ9x8fJAB0AgAAAA==.Terizfolly:BAAALgAECgQJCQAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAABLgAECn8nAAIRAAkJVxX+TgDbAQARAAkJVxX+TgDbAQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thilendrel:BAAALgADCgYJBgAAAA==.Thingwan:BAACLgAFFH8RAAIYAAYJQhTAHgBjAQAYAAYJQhTAHgBjAQAuAAQKfzYAAhgACQk4G9kQAMoCABgACQk4G9kQAMoCAAAA.Thordak:BAAALgADCggJDQABLgAECgkJHwARANIUAA==.',
Ti='Tiamat:BAAALgAECgkJCQAAAA==.Timbuktoo:BAABLgAECn8XAAIKAAkJoRN9AgC6AQAKAAkJoRN9AgC6AQAAAA==.Tinietimm:BAAALgADCgQJBAAAAA==.Tinypoop:BAABLgAECn8WAAIGAAYJVBVnrwAiAQAGAAYJVBVnrwAiAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAABLgAECn8oAAIOAAkJWB+EAgChAgAOAAkJWB+EAgChAgAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAABLgAECn8uAAIeAAcJEBsuAgDaAQAeAAcJEBsuAgDaAQAAAA==.Tors:BAACLgAFFH8UAAIHAAMJ6hCpGgCrAAAHAAMJ6hCpGgCrAAAuAAQKf2sAAwcACQlKIS0BAOwCAAcACQlKIS0BAOwCAAkAAgnYE55PAG8AAAAA.',
Tr='Trasky:BAAALgAECgMJAwAAAA==.Trogdore:BAAALgAECgYJDQAAAA==.Trollololo:BAABLgAECn9LAAMGAAkJuRqFJACKAgAGAAkJuRqFJACKAgAoAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8qAAIGAAkJXx7+IwCNAgAGAAkJXx7+IwCNAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgYJCAABLgAECggJFAAOADwUAA==.',
Tt='Ttaartt:BAACLgAFFH8nAAMBAAcJmRNbCgAFAgABAAcJmRNbCgAFAgAIAAQJyxDzQQC/AAAuAAQKfx0AAgEABwmqGfESABICAAEABwmqGfESABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8WAAIEAAQJ2yAVAwBzAQAEAAQJ2yAVAwBzAQAuAAQKf0QAAgQACQm5JXUAAF4DAAQACQm5JXUAAF4DAAAA.Tyr:BAAALgAECgkJBwAAAA==.Tyresta:BAAALgAECgEJAQAAAA==.Tyrone:BAABLgAECn8kAAMbAAkJcRqLDQBtAgAbAAkJcRqLDQBtAgAXAAQJABCydwC1AAAAAA==.Tyrslan:BAAALgAECgYJEQAAAA==.',
Uf='Uffish:BAAALgAECgkJCQAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.Uglypriest:BAAALgADCgEJAQAAAA==.',
Un='Undeadaegir:BAAALgAECgEJAQABLgAECgkJIwAOACUdAA==.Undeaddemon:BAABLgAECn8jAAQOAAkJJR3EOQDzAQAOAAgJJR3EOQDzAQATAAMJEQ8THwB4AAAmAAEJkAbJeAAqAAAAAA==.Undeaddh:BAAALgAECgYJCAABLgAECgkJIwAOACUdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIwAOACUdAA==.Undeadscaly:BAAALgAECgYJBwABLgAECgkJIwAOACUdAA==.Undignified:BAACLgAFFH8LAAIEAAMJoQ5lAwC/AAAEAAMJoQ5lAwC/AAAuAAQKf2EAAgQACQksG5gAAGUCAAQACQksG5gAAGUCAAAA.Unholysixth:BAAALgAECgUJBQAAAA==.Unicornquen:BAAALgAECgYJCQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Valkar:BAAALgAECgEJAgAAAA==.Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgUJEgAAAA==.',
Vi='Vidikan:BAAALgAECgQJEwAAAA==.Vie:BAAALgAECgEJAgAAAA==.',
Vo='Voidreaper:BAAALgADCgMJAwAAAA==.Voidwarranty:BAACLgAFFH8FAAICAAMJAAtdWwCWAAACAAMJAAtdWwCWAAAuAAQKfzQAAwIACQl0F+EiAD0CAAIACQl0F+EiAD0CAB0ABwmRFo4kAMMBAAAA.Vondi:BAEALgAECgUJCwABLgAFFAUJDAAcAPgSAA==.Vontoot:BAAALgADCgEJAQAAAA==.Vortre:BAAALgAECggJCAAAAA==.',
Vv='Vvumpscut:BAABLgAECn8gAAICAAkJaxobIABPAgACAAkJaxobIABPAgAAAA==.',
Vy='Vysena:BAAALgAECgEJAwAAAA==.',
Wa='Waldón:BAABLgAECn9LAAIoAAkJPg3+BACRAQAoAAkJPg3+BACRAQAAAA==.',
We='Weatherley:BAAALgAECgEJAQAAAA==.Werrik:BAABLgAECn8aAAIOAAkJXyX8IgCJAgAOAAkJXyX8IgCJAgAAAA==.',
Wh='Whiskeytap:BAAALgAECgIJAgAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAICAAcJPxJcUgBqAQACAAcJPxJcUgBqAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJDAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAYJKgAKAPYiAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAABLgAECn8aAAIQAAkJ+wowGgDNAQAQAAkJ+wowGgDNAQAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.Xeroxpriest:BAAALgAECgcJCwAAAA==.',
Xi='Xilphira:BAAALgAECgUJCQAAAA==.',
Xl='Xlithz:BAABLgAECn80AAMhAAkJWRuaFgA6AgAhAAkJTxuaFgA6AgAiAAgJPhIiHQB0AQAAAA==.',
['Xí']='Xílo:BAABLgAECn9MAAMDAAkJjh4/FQCZAgADAAkJcxw/FQCZAgAUAAYJtx6SGAC+AQAAAA==.',
Yg='Yggdrasil:BAAALgAECgkJCgAAAA==.',
Yl='Ylene:BAABLgAECn82AAIYAAkJkBAmMwDRAQAYAAkJkBAmMwDRAQAAAA==.',
Yo='Yoink:BAACLgAFFH8TAAIfAAQJkxq7VQBGAQAfAAQJkxq7VQBGAQAuAAQKfzsAAh8ACQk7JGwIAC8DAB8ACQk7JGwIAC8DAAAA.Yondu:BAAALgAECgEJAwABLgAECgkJKwAfAMgUAA==.Yourgrandma:BAAALgAECgEJAgABLgAECgkJKwAfAMgUAA==.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgAECgUJBwAAAA==.Zarinfur:BAABLgAECn82AAIKAAkJHBnGBwBYAgAKAAkJHBnGBwBYAgAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgcJCwAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAACLgAFFH8MAAIFAAUJ5QZOMwDZAAAFAAUJ5QZOMwDZAAAuAAQKfy0AAwUABwmsG0ZAAOEBAAUABwmsG0ZAAOEBABYAAQn1AJGZABsAAAAA.Zequill:BAABLgAECn9QAAIaAAkJOCRgAgAjAwAaAAkJOCRgAgAjAwAAAA==.Zevsticles:BAABLgAECn8yAAIFAAkJmh+8CgDMAQAFAAkJmh+8CgDMAQAAAA==.',
Zh='Zhom:BAACLgAFFH8aAAIWAAQJAyGbDgB1AQAWAAQJAyGbDgB1AQAuAAQKf0AAAhYACQkcJIgBAAYDABYACQkcJIgBAAYDAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn9MAAIpAAkJQBseBQCVAgApAAkJQBseBQCVAgAAAA==.Zorlak:BAAALgAECgUJDgAAAA==.',
Zu='Zuxa:BAAALgADCgYJBgAAAA==.',
Zy='Zylofeather:BAAALgAECgUJBQAAAA==.',
['Àl']='Àlthor:BAABLgAECn8WAAMhAAgJ2RS7BADBAQAhAAgJ2RS7BADBAQAaAAIJ0wdHFwAjAAABLgAFFAgJFgADACQQAA==.',
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
