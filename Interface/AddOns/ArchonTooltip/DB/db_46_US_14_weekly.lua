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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','Hunter-Survival','Druid-Balance','Druid-Restoration','Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Warrior-Arms','Warrior-Fury','Rogue-Subtlety','Rogue-Outlaw','Evoker-Devastation','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=46,date='2026-08-18',data={Ad='Adhramex:BAAALgADCgEJAQAAAA==.Adrestia:BAEALgAFFAIJAgABLgAFFAYJDQABACofAA==.',
Ae='Aerglo:BAABLgAECn8iAAQCAAYJKRgqMABHAQACAAYJoxYqMABHAQADAAMJNBnbTgDFAAABAAMJ+gZBowBUAAAAAA==.',
Al='Alidruid:BAAALgAECgUJDAABLgAECgcJDQAEAAAAAA==.',
An='Analog:BAACLgAFFH8PAAMFAAYJLxByCgBuAQAFAAYJLxByCgBuAQAGAAIJlQaocgA+AAAuAAQKfyUAAwUACQlQG5EVAGACAAUACAlBGpEVAGACAAYAAwk6CWgyAX0AAAAA.Anataea:BAAALgAECgEJAQAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBgABLgAECgYJDwAEAAAAAA==.Astraldoge:BAABLgAECn8cAAMHAAYJPgwvHgCqAAAHAAUJrQwvHgCqAAAIAAYJqgaRzACYAAAAAA==.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAABLgAFFH8HAAIJAAIJixYVKAB7AAAJAAIJixYVKAB7AAAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Ay='Ayeka:BAAALgADCgYJBgAAAA==.',
Az='Azshanal:BAABLgAECn8oAAIIAAkJZyCQFQCXAgAIAAkJZyCQFQCXAgAAAA==.',
Ba='Balance:BAAALgAECgEJAQAAAA==.Banana:BAAALgAECgMJAwABLgAFFAMJBQAKALAYAA==.',
Bi='Bicepcurls:BAABLgAFFH8FAAMLAAMJaATXHwCDAAALAAMJaATXHwCDAAAMAAEJhwKBOQAcAAAAAA==.Biggiee:BAAALgAECgQJBAAAAA==.Biggsthebold:BAABLgAECn8dAAIGAAcJiCQ6IQCmAgAGAAcJiCQ6IQCmAgAAAA==.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAGAIgkAA==.Bishöp:BAAALgAECgcJCwABLgAECgkJbgANABEhAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgcJEgAAAA==.',
Bo='Bossmàn:BAAALgAECgIJAgAAAA==.',
Br='Brewhousee:BAAALgAECgEJAwAAAA==.Brews:BAAALgAECgkJCQAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bubblebuddy:BAAALgAECgEJAgAAAA==.Bungus:BAABLgAECn8oAAIOAAkJWST9DAAFAwAOAAkJWST9DAAFAwAAAA==.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgcJEgAAAA==.',
Ca='Cabo:BAAALgAECgcJBwAAAA==.Caps:BAAALgAECgYJCAAAAA==.Casmoto:BAAALgADCgQJBAAAAA==.Cassa:BAAALgAECgMJCQAAAA==.Castor:BAABLgAECn8VAAIPAAYJMhuIjAC5AQAPAAYJMhuIjAC5AQAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAACLgAFFH8YAAIQAAQJnxyyJgBOAQAQAAQJnxyyJgBOAQAuAAQKfzkAAhAACQlzIzQEAHYDABAACQlzIzQEAHYDAAAA.Cherovski:BAAALgADCgIJAgAAAA==.Chestpress:BAAALgADCgMJAwAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8lAAIRAAkJZBqQCwACAgARAAkJZBqQCwACAgAAAA==.',
Ck='Ckonquer:BAACLgAFFH8OAAISAAMJwxYzMgDIAAASAAMJwxYzMgDIAAAuAAQKfxwAAhIACQnTHnwLAKoCABIACQnTHnwLAKoCAAAA.',
Cr='Crazytaco:BAAALgAECgYJDwAAAA==.',
Cu='Cumpkin:BAAALgAECgEJAQAAAA==.Cursewords:BAABLgAFFH8IAAMTAAYJUAhLFQCRAAANAAQJAglqhAC9AAATAAMJvgdLFQCRAAABLgADCgIJAgAEAAAAAA==.',
Cz='Czaedyn:BAABLgAECn9rAAITAAkJ1x4tAgCiAgATAAkJ1x4tAgCiAgAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECgkJFwAQAJwEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Darkseth:BAABLgAFFH8GAAMUAAMJQgWoCgB2AAATAAIJtAUFFwB7AAAUAAIJ/ASoCgB2AAAAAA==.Darkwars:BAAALgADCgEJAQAAAA==.Darthswade:BAAALgAECgYJCQABLgAECggJFAAVAJsWAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgAECgEJAQAAAA==.',
De='Deathful:BAABLgAECn8XAAMNAAcJ4hh1RAD+AQANAAcJ4hh1RAD+AQAUAAEJAAAKLQBEAAAAAA==.Deathkano:BAAALgAECgUJBQAAAA==.Deep:BAAALgAECggJDAAAAA==.Dellea:BAAALgAECgYJCQAAAA==.Depemonkimab:BAAALgAECgYJBwAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8oAAMWAAkJOA1bEgCjAQAWAAkJOA1bEgCjAQAXAAEJwAF3pQAXAAAAAA==.Deuceretro:BAAALgADCgMJAwAAAA==.Devourer:BAAALgAECgYJBgAAAA==.Dewdrop:BAAALgAECgkJAQAAAA==.',
Di='Diirt:BAAALgADCgYJBgAAAA==.Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIMAAgJPCGfDADYAgAMAAgJPCGfDADYAgAAAA==.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8gAAINAAcJlA3OhAAvAQANAAcJlA3OhAAvAQAAAA==.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dy:BAAALgADCgcJBwAAAA==.Dysis:BAABLgAECn8UAAMYAAYJkCCsEQCrAQAYAAYJHSCsEQCrAQAGAAEJNiAPVAFcAAAAAA==.Dysos:BAABLgAECn8YAAMZAAkJmBxpAgBCAgAZAAgJmBxpAgBCAgAOAAEJAACkZQAAAAAAAA==.',
Eb='Eblocked:BAAALgAECgYJDQAAAA==.',
El='Elmorocho:BAAALgADCgEJAQAAAA==.Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgkJIwADAM8PAA==.',
Es='Esniper:BAAALgADCggJCQAAAA==.',
Ev='Evi:BAAALgAECgYJEwAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgAECgEJAQAAAA==.',
Fa='Faelar:BAABLgAECn8fAAIGAAYJvgdsLgCeAAAGAAYJvgdsLgCeAAAAAA==.Fatroph:BAAALgAECgEJAQAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.Feytality:BAAALgAECggJEQAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgkJIgAGAAYjAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fl='Flatline:BAABLgAECn8ZAAMaAAkJCRGsAwD5AQAaAAkJCRGsAwD5AQAbAAEJxQCFLgAHAAABLgAECgkJawATANceAA==.',
Fo='Fornath:BAAALgAECgEJAQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8VAAIPAAUJSBO2XgAjAQAPAAUJSBO2XgAjAQAuAAQKfzMAAg8ACAkmHtQ4ADUCAA8ACAkmHtQ4ADUCAAAA.',
Fu='Fury:BAAALgAECgQJCAAAAA==.',
['Fë']='Fëýrè:BAAALgADCgYJEgAAAA==.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.Geztherion:BAAALgAECgYJEwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.Gordan:BAAALgADCgkJDAABLgAECgkJMwAGAP0fAA==.',
Gr='Greasemonkèy:BAABLgAECn8XAAIQAAkJnASDZgD1AAAQAAkJnASDZgD1AAAAAA==.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
Gu='Gumba:BAAALgAECgMJAwAAAA==.',
Ha='Hazyshadow:BAAALgAECgUJCgAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgAEAAAAAA==.Heavyroller:BAAALgAECgIJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgAEAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8ZAAIcAAcJZiQfAQDgAgAcAAcJZiQfAQDgAgAAAA==.Hotten:BAACLgAFFH8LAAIKAAQJiRTEGAAMAQAKAAQJiRTEGAAMAQAuAAQKfx4AAwoACAlIFCsXAOgBAAoACAlIFCsXAOgBAB0ABgmPAsjhAIsAAAAA.',
Hr='Hruid:BAAALgAECgQJBAAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
['Hü']='Hüntürd:BAAALgAECgMJAwAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8sAAMDAAkJuhJPGwDKAQADAAkJuhJPGwDKAQACAAcJRQcFSgDZAAAAAA==.',
In='Indomitable:BAAALgAECgYJCgAAAA==.Insigthful:BAABLgAFFH8FAAIOAAMJ2AV5vACwAAAOAAMJ2AV5vACwAAAAAA==.',
Ir='Irisheyes:BAAALgAECgQJBAAAAA==.',
Is='Isabelaa:BAAALgAECgQJBAAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.Jasreha:BAAALgAECgkJAQAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAACLgAFFH8GAAIOAAIJaQn/7gB8AAAOAAIJaQn/7gB8AAAuAAQKfxQAAg4ABwlsC/SnACABAA4ABwlsC/SnACABAAAA.',
Ka='Kalmea:BAAALgAECggJEQAAAA==.Kaoru:BAABLgAECn8nAAIeAAkJWRS1CgDBAQAeAAkJWRS1CgDBAQAAAA==.Katînka:BAAALgAECgEJAQAAAA==.',
Ke='Kessra:BAAALgADCgYJBgAAAA==.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Killazs:BAAALgAECgIJAgAAAA==.Kinjari:BAAALgAECgcJEQAAAA==.Kittenhealer:BAAALgAECgkJCQAAAA==.',
Ko='Korrel:BAAALgADCgMJBAABLgAECgkJKgAbAKEhAA==.Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krucal:BAABLgAECn9SAAMNAAkJARy9GACPAgANAAkJARy9GACPAgATAAYJfgwRLQAJAQAAAA==.',
La='Lamar:BAABLgAECn8VAAICAAcJxR5BFgAGAgACAAcJxR5BFgAGAgAAAA==.Lark:BAABLgAECn8vAAMfAAkJVSAcCQC8AgAfAAkJVSAcCQC8AgAaAAYJTRYiNABuAQAAAA==.Laurranna:BAAALgADCgYJBgAAAA==.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Liaha:BAAALgAFFAEJAgABLgAFFAMJCQAMADEDAA==.Life:BAAALgADCgQJBAAAAA==.Lifebulwark:BAAALgAFFAIJBAAAAA==.Lifedeclined:BAABLgAFFH8JAAMZAAMJFhoOLQCUAAAOAAMJYxZXoQDTAAAZAAIJRxYOLQCUAAAAAA==.Lifegiver:BAACLgAFFH8RAAMLAAgJ8R4xDwCvAQALAAgJ8R4xDwCvAQAMAAIJOxXaVAByAAAuAAQKfx4AAwwACQmEGckgAEECAAwACAkoGskgAEECAAsABwloIn83ADcBAAAA.Lifeisholy:BAABLgAECn8XAAMaAAcJ7BvXBwBMAQAaAAQJ9B3XBwBMAQAfAAcJQxlvCgAdAQAAAA==.Lifemania:BAAALgAFFAMJBAAAAA==.Liferanger:BAAALgAFFAQJBAAAAA==.Lindon:BAAALgADCgcJBwAAAA==.Listyn:BAACLgAFFH8JAAIMAAMJMQOzGgCSAAAMAAMJMQOzGgCSAAAuAAQKfx4AAgwABwnTEEFIAG4BAAwABwnTEEFIAG4BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECgkJEgAAAA==.',
Lu='Lunaheim:BAAALgAECgkJCAAAAA==.Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgcJDQAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maja:BAAALgAFFAEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8gAAIVAAkJyRnKDAD2AQAVAAkJyRnKDAD2AQAAAA==.Mart:BAACLgAFFH8MAAIWAAQJMh+QFgArAQAWAAQJMh+QFgArAQAuAAQKfykAAhYACQngHewMAGcCABYACQngHewMAGcCAAAA.Marwynne:BAABLgAECn8VAAIQAAcJ9hoZNQDdAQAQAAcJ9hoZNQDdAQAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAAWADIfAA==.',
Mi='Mina:BAAALgAECgQJBQAAAA==.Miyafuji:BAABLgAECn8sAAMaAAkJEiSsBgAIAwAaAAkJ6COsBgAIAwAbAAYJGB/eEwAOAgAAAA==.',
Mo='Moonwell:BAACLgAFFH8WAAIMAAcJHBtJEwDUAQAMAAcJHBtJEwDUAQAuAAQKfyMAAgwACAnYJIEJACIDAAwACAnYJIEJACIDAAAA.Motsuharo:BAAALgAECgUJBQABLgAECgYJEwAEAAAAAA==.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8aAAMKAAgJ7BhdBQC5AQAKAAcJGRxdBQC5AQAdAAEJ2wXCcwBEAAAuAAQKfysABAoACQnBI5YEANACAAoACQnBI5YEANACAB4ABAmdD1ZiALcAAB0AAQk/FbzRADQAAAAA.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQAEAAAAAA==.Narnode:BAAALgAECgkJEwAAAA==.',
Ni='Ninamori:BAAALgAECgUJBwAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAABLgAECn8wAAIFAAkJqiLWAAATAwAFAAkJqiLWAAATAwABLgAECgcJGQAcAGYkAA==.',
Ob='Obwand:BAAALgAECgMJBAAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8dAAMgAAcJyxF6KwAdAQAgAAcJyxF6KwAdAQAhAAQJNAS4gwCwAAAAAA==.Palanthir:BAABLgAECn8zAAIGAAkJ/R+/EwDMAgAGAAkJ/R+/EwDMAgAAAA==.Pandapve:BAACLgAFFH8ZAAMCAAcJPxvfCgByAQACAAcJPxvfCgByAQADAAEJEAdTWwA4AAAuAAQKfywAAwIACAnZIXkMAH0CAAIACAnZIXkMAH0CAAMABgkrEV9QAAIBAAAA.Pascratt:BAAALgAECgYJCgAAAA==.',
Pe='Peja:BAABLgAECn8sAAMiAAkJQQvbBgAdAQAiAAkJQQvbBgAdAQAjAAYJ7QP3FgCoAAAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgAEAAAAAA==.Perrywinkle:BAAALgAECgIJAgAAAA==.',
Ph='Phu:BAACLgAFFH8jAAILAAcJ1BlsDwCtAQALAAcJ1BlsDwCtAQAuAAQKfzMAAgsACQlrJMMEABEDAAsACQlrJMMEABEDAAAA.',
Po='Pockthelock:BAACLgAFFH8VAAIUAAUJwBVyBABFAQAUAAUJwBVyBABFAQAuAAQKfzAABBQACQmcHTgFADoCABQACAnPHjgFADoCAA0ACAnVDj1iAHsBABMAAwmLIe0HAMUAAAAA.Polokol:BAAALgADCgQJBAAAAA==.',
Pu='Puds:BAAALgADCggJEwABLgAECgkJKgAbAKEhAA==.',
['Pï']='Pïnky:BAAALgAECgQJBAAAAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn9uAAINAAkJESGVAQD8AgANAAkJESGVAQD8AgAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAACLgAFFH8FAAIGAAIJawxulACLAAAGAAIJawxulACLAAAuAAQKfycABAYACQm+GLxMAOABAAYACAnQFrxMAOABAAUABQmBA+RmAJoAABgAAwkYBVoVAEYAAAAA.Ravioli:BAABLgAECn8rAAIDAAkJwSWzAQBPAwADAAkJwSWzAQBPAwABLgAECgcJGQAcAGYkAA==.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8jAAMPAAkJuA0qZwCuAQAPAAkJuA0qZwCuAQAcAAIJOQT/GABQAAAAAA==.Rayliee:BAAALgADCgMJAwABLgAECgkJIwAPALgNAA==.',
Rd='Rd:BAABLgAECn8UAAIPAAcJ1BN5nwA8AQAPAAcJ1BN5nwA8AQAAAA==.',
Re='Rendurface:BAAALgAECgMJAwAAAA==.Requiel:BAAALgAECgUJDAAAAA==.Ret:BAAALgAFFAEJAQAAAA==.',
Rh='Rhyssa:BAABLgAECn8dAAICAAcJACIfGwDXAQACAAcJACIfGwDXAQAAAA==.',
Ro='Roccet:BAAALgAECgMJAwABLgAECggJFQADAPQiAA==.Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAFFAEJAQAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIGAAgJtBZIRQAUAgAGAAgJtBZIRQAUAgAAAA==.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQaAAcJxAusPgA/AQAaAAcJxAusPgA/AQAfAAQJLAE2WgBQAAAbAAIJ6wFnUQBGAAAAAA==.Sairae:BAAALgADCgIJAgAAAA==.Sashimidog:BAAALgAECgUJBQAAAA==.Sasuke:BAAALgAECgYJBgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn9kAAMXAAkJ5BflAgC2AQAXAAkJ5BflAgC2AQAkAAUJwwEZMACWAAAAAA==.Scoopdapoop:BAABLgAECn8WAAIIAAkJ5hClBwCOAQAIAAkJ5hClBwCOAQAAAA==.',
Se='Sempii:BAAALgAECgUJCgAAAA==.Serarlan:BAAALgAECgEJCAAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Shampanda:BAAALgAECgYJCgAAAA==.Shentyphoon:BAAALgAECgUJBwAAAA==.Sheve:BAAALgAECgEJAgABLgAECgkJKgAbAKEhAA==.Shiine:BAAALgADCgUJBQAAAA==.Shwip:BAAALgAECgEJAQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAABLgAECn8wAAIPAAkJNRv5KAB3AgAPAAkJNRv5KAB3AgAAAA==.Sinisteredge:BAAALgADCgEJAQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skork:BAAALgAECgYJCgAAAA==.Skull:BAAALgAECgYJDQAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIlAAcJ2CCBCQCDAgAlAAcJ2CCBCQCDAgAAAA==.Slightcoyote:BAABLgAECn85AAIMAAkJax8SAQAvAwAMAAkJax8SAQAvAwAAAA==.Slëëpy:BAAALgADCgEJAQAAAA==.',
Sm='Smokeyh:BAACLgAFFH8TAAIDAAQJayF2FgBuAQADAAQJayF2FgBuAQAuAAQKf0kAAwMACAneJGIGANUCAAMACAneJGIGANUCAAIAAQnMHZSDAFAAAAAA.',
Sn='Snow:BAABLgAECn8eAAIiAAkJdyIsDgBGAgAiAAkJdyIsDgBGAgAAAA==.',
So='Solarasis:BAAALgAECgYJDAAAAA==.Somos:BAAALgAECgYJCgAAAA==.',
Sp='Sparklepony:BAAALgAECgQJBAAAAA==.',
Ss='Sserka:BAAALgAECgUJBQAAAA==.',
St='Stevjibs:BAAALgADCgMJAwAAAA==.Strongtoast:BAECLgAFFH8IAAIfAAQJXgviFAC8AAAfAAQJXgviFAC8AAAuAAQKfxoAAh8ACQnOFIcFAJoBAB8ACQnOFIcFAJoBAAAA.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAFFAEJAQAEAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.Swiftdh:BAACLgAFFH8MAAMIAAQJhBRPHQAqAQAIAAQJhBRPHQAqAQAHAAEJvQ4bDQAqAAAuAAQKf2oAAwgACQnOJKEAAFkDAAgACQnOJKEAAFkDAAcACQm1G8AAAJACAAAA.',
Sy='Syndra:BAAALgADCgkJEwAAAA==.',
['Sæ']='Sæstoo:BAAALgAFFAEJAQAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Tad:BAAALgAECgYJBwAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAABLgAECn8eAAIGAAkJmgu2GwACAQAGAAkJmgu2GwACAQAAAA==.Testcyp:BAAALgAECgEJAQAAAA==.',
Th='Thonor:BAABLgAECn8vAAINAAkJpRUKLwAcAgANAAkJpRUKLwAcAgAAAA==.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8eAAMHAAkJjxBgFwDpAAAHAAcJ5ApgFwDpAAAmAAQJqBNINQDpAAAAAA==.',
To='Torí:BAABLgAECn8YAAIGAAkJZwmyowA5AQAGAAkJZwmyowA5AQAAAA==.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tren:BAAALgAECgIJAgAAAA==.Tryla:BAAALgAECggJAQAAAA==.',
Tw='Twentycent:BAAALgADCgEJAQAAAA==.',
['Tâ']='Târä:BAAALgAECgUJBQAAAA==.',
Up='Upgrayedd:BAAALgAECgUJBgABLgAECgkJbgANABEhAA==.',
Va='Vaelandir:BAAALgAECgUJDAAAAA==.Vallkyr:BAABLgAECn8iAAIPAAkJ0x5qLABoAgAPAAkJ0x5qLABoAgAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAIdAAgJ7A77OQDHAQAdAAgJ7A77OQDHAQAAAA==.',
Vi='Vinnyfr:BAAALgAECgMJBgABLgAFFAIJAwAEAAAAAA==.Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyses:BAAALgADCgcJBwAAAA==.Vysys:BAAALgAECgIJAwAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJBAAAAA==.',
Wi='Wildshifter:BAAALgAECgEJAQAAAA==.',
Xe='Xeriaah:BAABLgAECn8kAAINAAYJfRJwhgAsAQANAAYJfRJwhgAsAQAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAABLgAECn8dAAIIAAkJrw97DgAhAQAIAAkJrw97DgAhAQAAAA==.Zitta:BAABLgAECn8eAAIBAAgJYhV8FwAEAgABAAgJYhV8FwAEAgAAAA==.Zittav:BAABLgAECn8bAAMFAAkJbBlnGwA5AgAFAAkJbBlnGwA5AgAGAAYJix6xdwB/AQAAAA==.',
Zo='Zoe:BAAALgAECgMJBQAAAA==.Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGQAcAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
Zy='Zylia:BAAALgADCgIJAgAAAA==.',
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
