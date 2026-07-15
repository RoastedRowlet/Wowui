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

local lookup = {'Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','Hunter-Survival','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Paladin-Protection','DeathKnight-Blood','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Druid-Balance','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','Rogue-Subtlety','Rogue-Outlaw','Evoker-Devastation','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=46,date='2026-07-12',data={Ad='Adhramex:BAAALgADCgEJAQAAAA==.Adrestia:BAEALgAFFAIJAgABLgAFFAgJJAABAFMaAA==.',
Ae='Aerglo:BAABLgAECn8iAAQCAAYJKRgqMABHAQACAAYJoxYqMABHAQADAAMJNBnbTgDFAAAEAAMJ+gZBowBUAAAAAA==.',
Al='Alidruid:BAAALgAECgQJCQAAAA==.',
An='Analog:BAACLgAFFH8KAAMFAAQJBBReEgCrAAAFAAQJBBReEgCrAAAGAAIJlQY5ZQA+AAAuAAQKfyUAAwUACQlQG5EVAGACAAUACAlBGpEVAGACAAYAAwk6CWgyAX0AAAAA.Anataea:BAAALgAECgEJAQAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBgABLgAECgYJDwAHAAAAAA==.Astraldoge:BAABLgAECn8cAAMIAAYJPgwvHgCqAAAIAAUJrQwvHgCqAAAJAAYJqgaRzACYAAAAAA==.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAABLgAFFH8HAAIKAAIJixYVKAB7AAAKAAIJixYVKAB7AAAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Ay='Ayeka:BAAALgADCgYJBgAAAA==.',
Az='Azshanal:BAABLgAECn8oAAIJAAkJZyCQFQCXAgAJAAkJZyCQFQCXAgAAAA==.',
Ba='Balance:BAAALgAECgEJAQAAAA==.Banana:BAAALgAECgMJAwABLgAFFAMJBQALALAYAA==.',
Bi='Bicepcurls:BAAALgAFFAMJAwAAAA==.Biggiee:BAAALgAECgQJBAAAAA==.Biggsthebold:BAABLgAECn8dAAIGAAcJiCQ6IQCmAgAGAAcJiCQ6IQCmAgAAAA==.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAGAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgcJEgAAAA==.',
Bo='Bossmàn:BAAALgAECgIJAgAAAA==.',
Br='Brewhousee:BAAALgAECgEJAwAAAA==.Brews:BAAALgAECgkJCQAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8oAAIMAAkJWST9DAAFAwAMAAkJWST9DAAFAwAAAA==.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgcJEgAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAINAAYJMhuIjAC5AQANAAYJMhuIjAC5AQAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAACLgAFFH8YAAIOAAQJnxyyJgBOAQAOAAQJnxyyJgBOAQAuAAQKfzkAAg4ACQlzIzQEAHYDAA4ACQlzIzQEAHYDAAAA.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8lAAIPAAkJZBqQCwACAgAPAAkJZBqQCwACAgAAAA==.',
Ck='Ckonquer:BAACLgAFFH8OAAIQAAMJwxYzMgDIAAAQAAMJwxYzMgDIAAAuAAQKfxwAAhAACQnTHnwLAKoCABAACQnTHnwLAKoCAAAA.',
Cr='Crazytaco:BAAALgAECgYJDwAAAA==.',
Cu='Cursewords:BAABLgAFFH8IAAMRAAYJUAhLFQCRAAASAAQJAglqhAC9AAARAAMJvgdLFQCRAAABLgAFFAcJEwAGAEEXAA==.',
Cz='Czaedyn:BAABLgAECn9rAAIRAAkJ1x4tAgCiAgARAAkJ1x4tAgCiAgAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECgkJFwAOAJwEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Darkseth:BAABLgAFFH8GAAMTAAMJQgWqBwB8AAATAAIJ/ASqBwB8AAARAAIJtAUFFwB7AAAAAA==.Darkwars:BAAALgADCgEJAQAAAA==.Darthswade:BAAALgAECgUJBQABLgAFFAEJAQAHAAAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgAECgEJAQAAAA==.',
De='Deathful:BAABLgAECn8XAAMSAAcJ4hh1RAD+AQASAAcJ4hh1RAD+AQATAAEJAAAKLQBEAAAAAA==.Deathkano:BAAALgAECgUJBQAAAA==.Deep:BAAALgAECggJDAAAAA==.Dellea:BAAALgAECgYJCQAAAA==.Depemonkimab:BAAALgAECgYJBwAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8oAAMUAAkJOA1bEgCjAQAUAAkJOA1bEgCjAQAVAAEJwAF3pQAXAAAAAA==.Deuceretro:BAAALgADCgMJAwAAAA==.Devourer:BAAALgAECgYJBgAAAA==.Dewdrop:BAAALgAECgkJAQAAAA==.',
Di='Diirt:BAAALgADCgYJBgAAAA==.Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIWAAgJPCGfDADYAgAWAAgJPCGfDADYAgAAAA==.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8gAAISAAcJlA3OhAAvAQASAAcJlA3OhAAvAQAAAA==.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dy:BAAALgADCgcJBwAAAA==.Dysis:BAABLgAECn8UAAMXAAYJkCCsEQCrAQAXAAYJHSCsEQCrAQAGAAEJNiAPVAFcAAAAAA==.Dysos:BAABLgAECn8UAAIYAAcJzRpOAgDYAQAYAAcJzRpOAgDYAQAAAA==.',
Eb='Eblocked:BAAALgAECgYJDQAAAA==.',
El='Elmorocho:BAAALgADCgEJAQAAAA==.Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgkJIwADAM8PAA==.',
Es='Esniper:BAAALgADCggJCQAAAA==.',
Ev='Evi:BAAALgAECgYJEwAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgAECgEJAQAAAA==.',
Fa='Faelar:BAABLgAECn8bAAIGAAYJqweNHACyAAAGAAYJqweNHACyAAAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.Feytality:BAAALgAECgYJBwAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgkJIgAGAAYjAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fl='Flatline:BAAALgAECgMJAwABLgAECgkJawARANceAA==.',
Fo='Fornath:BAAALgAECgEJAQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8VAAINAAUJSBO2XgAjAQANAAUJSBO2XgAjAQAuAAQKfzMAAg0ACAkmHtQ4ADUCAA0ACAkmHtQ4ADUCAAAA.',
Fu='Fury:BAAALgAECgQJCAAAAA==.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.Geztherion:BAAALgAECgYJDgAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.Gordan:BAAALgADCgkJDAABLgAECgkJMwAGAP0fAA==.',
Gr='Greasemonkèy:BAABLgAECn8XAAIOAAkJnASDZgD1AAAOAAkJnASDZgD1AAAAAA==.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
Ha='Hazyshadow:BAAALgAECgUJCgAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgAHAAAAAA==.Heavyroller:BAAALgAECgIJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgAHAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8ZAAIZAAcJZiQfAQDgAgAZAAcJZiQfAQDgAgAAAA==.Hotten:BAACLgAFFH8LAAILAAQJiRTEGAAMAQALAAQJiRTEGAAMAQAuAAQKfx4AAwsACAlIFCsXAOgBAAsACAlIFCsXAOgBABoABgmPAsjhAIsAAAAA.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
['Hü']='Hüntürd:BAAALgAECgMJAwAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8sAAMDAAkJuhJPGwDKAQADAAkJuhJPGwDKAQACAAcJRQcFSgDZAAAAAA==.',
In='Indomitable:BAAALgAECgYJCgAAAA==.Insigthful:BAABLgAFFH8FAAIMAAMJ2AV5vACwAAAMAAMJ2AV5vACwAAAAAA==.',
Is='Isabelaa:BAAALgAECgQJBAAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAACLgAFFH8GAAIMAAIJaQn/7gB8AAAMAAIJaQn/7gB8AAAuAAQKfxQAAgwABwlsC/SnACABAAwABwlsC/SnACABAAAA.',
Ka='Kalmea:BAAALgAECggJEQAAAA==.Kaoru:BAABLgAECn8nAAIbAAkJWRS1CgDBAQAbAAkJWRS1CgDBAQAAAA==.',
Ke='Kessra:BAAALgADCgYJBgAAAA==.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgcJEQAAAA==.Kittenhealer:BAAALgAECgkJCQAAAA==.',
Ko='Korrel:BAAALgADCgEJAQABLgAECgkJKgABAKEhAA==.Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn9SAAMSAAkJARy9GACPAgASAAkJARy9GACPAgARAAYJfgwRLQAJAQAAAA==.',
La='Lamar:BAABLgAECn8VAAICAAcJxR5BFgAGAgACAAcJxR5BFgAGAgAAAA==.Lark:BAABLgAECn8vAAMcAAkJVSAcCQC8AgAcAAkJVSAcCQC8AgAdAAYJTRYiNABuAQAAAA==.Laurranna:BAAALgADCgYJBgAAAA==.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Liaha:BAAALgAFFAEJAgABLgAFFAMJCQAWADEDAA==.Life:BAAALgADCgQJBAAAAA==.Lifebulwark:BAAALgAFFAEJAgAAAA==.Lifedeclined:BAABLgAFFH8JAAMYAAMJFhoOLQCUAAAMAAMJYxZXoQDTAAAYAAIJRxYOLQCUAAAAAA==.Lifegiver:BAACLgAFFH8PAAMeAAcJJB4xDwCvAQAeAAcJJB4xDwCvAQAWAAIJOxXaVAByAAAuAAQKfx4AAxYACQmEGckgAEECABYACAkoGskgAEECAB4ABwloIn83ADcBAAAA.Lifeisholy:BAABLgAECn8XAAMdAAcJ7BsMBQBQAQAdAAQJ9B0MBQBQAQAcAAcJQxmPBgAhAQAAAA==.Lifemania:BAAALgAECgQJBAAAAA==.Lindon:BAAALgADCgcJBwAAAA==.Listyn:BAACLgAFFH8JAAIWAAMJMQOzGgCSAAAWAAMJMQOzGgCSAAAuAAQKfx4AAhYABwnTEEFIAG4BABYABwnTEEFIAG4BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECgkJEgAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgcJDQAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maja:BAAALgAFFAEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8gAAIfAAkJyRnKDAD2AQAfAAkJyRnKDAD2AQAAAA==.Mart:BAACLgAFFH8MAAIUAAQJMh+QFgArAQAUAAQJMh+QFgArAQAuAAQKfykAAhQACQngHewMAGcCABQACQngHewMAGcCAAAA.Marwynne:BAABLgAECn8UAAIOAAcJ9hoZNQDdAQAOAAcJ9hoZNQDdAQAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAAUADIfAA==.',
Mi='Mina:BAAALgAECgMJAwAAAA==.Miyafuji:BAABLgAECn8sAAMdAAkJEiSsBgAIAwAdAAkJ6COsBgAIAwABAAYJGB/eEwAOAgAAAA==.',
Mo='Moonwell:BAACLgAFFH8VAAIWAAYJ3x1JEwDUAQAWAAYJ3x1JEwDUAQAuAAQKfyMAAhYACAnYJIEJACIDABYACAnYJIEJACIDAAAA.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8YAAMLAAcJdBtdBQC5AQALAAYJxh9dBQC5AQAaAAEJ2wX+XABLAAAuAAQKfysABAsACQnBI5YEANACAAsACQnBI5YEANACABsABAmdD1ZiALcAABoAAQk/FbzRADQAAAAA.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQAHAAAAAA==.Narnode:BAAALgAECgYJDgAAAA==.',
Ni='Ninamori:BAAALgAECgUJBwAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAABLgAECn8oAAIFAAgJoSL5AACOAgAFAAgJoSL5AACOAgABLgAECgcJGQAZAGYkAA==.',
Ob='Obwand:BAAALgAECgEJAQAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8dAAMgAAcJyxF6KwAdAQAgAAcJyxF6KwAdAQAhAAQJNAS4gwCwAAAAAA==.Palanthir:BAABLgAECn8zAAIGAAkJ/R+/EwDMAgAGAAkJ/R+/EwDMAgAAAA==.Pandapve:BAACLgAFFH8YAAMCAAYJHBzfCgByAQACAAYJHBzfCgByAQADAAEJEAdTWwA4AAAuAAQKfywAAwIACAnZIXkMAH0CAAIACAnZIXkMAH0CAAMABgkrEV9QAAIBAAAA.Pascratt:BAAALgAECgYJCgAAAA==.',
Pe='Peja:BAABLgAECn8sAAMiAAkJQQtPBAAyAQAiAAkJQQtPBAAyAQAjAAYJ7QP3FgCoAAAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgAHAAAAAA==.Perrywinkle:BAAALgAECgEJAQAAAA==.',
Ph='Phu:BAACLgAFFH8jAAIeAAcJ1BlsDwCtAQAeAAcJ1BlsDwCtAQAuAAQKfzMAAh4ACQlrJMMEABEDAB4ACQlrJMMEABEDAAAA.',
Po='Pockthelock:BAACLgAFFH8TAAITAAUJwBVyBABFAQATAAUJwBVyBABFAQAuAAQKfyoAAxMACQm1GjgFADoCABMACAkqHTgFADoCABIACAnVDj1iAHsBAAAA.Polokol:BAAALgADCgQJBAAAAA==.',
Pu='Puds:BAAALgADCggJEwABLgAECgkJKgABAKEhAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn9aAAISAAkJYx+gDgDXAgASAAkJYx+gDgDXAgAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAACLgAFFH8FAAIGAAIJawxulACLAAAGAAIJawxulACLAAAuAAQKfyMABAYACQm+GLxMAOABAAYACAnQFrxMAOABAAUABQmNAuRmAJoAABcAAQmWAQRgABAAAAAA.Ravioli:BAABLgAECn8rAAIDAAkJwSWzAQBPAwADAAkJwSWzAQBPAwABLgAECgcJGQAZAGYkAA==.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8jAAMNAAkJuA0qZwCuAQANAAkJuA0qZwCuAQAZAAIJOQT/GABQAAAAAA==.Rayliee:BAAALgADCgMJAwABLgAECgkJIwANALgNAA==.',
Rd='Rd:BAABLgAECn8UAAINAAcJ1BN5nwA8AQANAAcJ1BN5nwA8AQAAAA==.',
Re='Rendurface:BAAALgAECgMJAwAAAA==.Requiel:BAAALgAECgUJDAAAAA==.Ret:BAAALgAFFAEJAQAAAA==.',
Rh='Rhyssa:BAABLgAECn8dAAICAAcJACIfGwDXAQACAAcJACIfGwDXAQAAAA==.',
Ro='Roccet:BAAALgAECgMJAwABLgAECggJFQADAPQiAA==.Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAFFAEJAQAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIGAAgJtBZIRQAUAgAGAAgJtBZIRQAUAgAAAA==.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQdAAcJxAusPgA/AQAdAAcJxAusPgA/AQAcAAQJLAE2WgBQAAABAAIJ6wFnUQBGAAAAAA==.Sairae:BAAALgADCgIJAgAAAA==.Sasuke:BAAALgAECgYJBgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn9kAAMVAAkJ5BfyAQDAAQAVAAkJ5BfyAQDAAQAkAAUJwwEZMACWAAAAAA==.Scoopdapoop:BAAALgADCgUJCgAAAA==.',
Se='Sempii:BAAALgAECgUJCgAAAA==.Serarlan:BAAALgAECgEJCAAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Shentyphoon:BAAALgAECgUJBwAAAA==.Sheve:BAAALgAECgEJAgABLgAECgkJKgABAKEhAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAABLgAECn8sAAINAAkJdhr5KAB3AgANAAkJdhr5KAB3AgAAAA==.Sinisteredge:BAAALgADCgEJAQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skork:BAAALgAECgYJCgAAAA==.Skull:BAAALgAECgYJDQAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIlAAcJ2CCBCQCDAgAlAAcJ2CCBCQCDAgAAAA==.Slightcoyote:BAABLgAECn8kAAIWAAkJfBsiAQC/AgAWAAkJfBsiAQC/AgAAAA==.Slëëpy:BAAALgADCgEJAQAAAA==.',
Sm='Smokeyh:BAACLgAFFH8TAAIDAAQJayF2FgBuAQADAAQJayF2FgBuAQAuAAQKf0kAAwMACAneJGIGANUCAAMACAneJGIGANUCAAIAAQnMHZSDAFAAAAAA.',
Sn='Snow:BAABLgAECn8eAAIiAAkJdyIsDgBGAgAiAAkJdyIsDgBGAgAAAA==.',
So='Solarasis:BAAALgAECgYJCwAAAA==.Somos:BAAALgAECgYJCgAAAA==.',
Sp='Sparklepony:BAAALgAECgQJBAAAAA==.',
Ss='Sserka:BAAALgAECgUJBQAAAA==.',
St='Stevjibs:BAAALgADCgMJAwAAAA==.Strongtoast:BAACLgAFFH8IAAIcAAQJXguQDgDQAAAcAAQJXguQDgDQAAAuAAQKfxkAAhwACAkPFPoEAFIBABwACAkPFPoEAFIBAAAA.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.Swiftblood:BAACLgAFFH8GAAMJAAMJjwo3LQCmAAAJAAMJjwo3LQCmAAAIAAEJUQNCCwAeAAAuAAQKfx8AAwkACAmsHWQCABsCAAkABwmtHmQCABsCAAgABgkVG18BAI0BAAAA.',
Sy='Syndra:BAAALgADCgkJEwAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgcJDwAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Tad:BAAALgAECgYJBwAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAABLgAECn8eAAIGAAkJmgsOEAAaAQAGAAkJmgsOEAAaAQAAAA==.',
Th='Thonor:BAABLgAECn8vAAISAAkJpRUKLwAcAgASAAkJpRUKLwAcAgAAAA==.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8eAAMIAAkJjxBgFwDpAAAIAAcJ5ApgFwDpAAAmAAQJqBNINQDpAAAAAA==.',
To='Torí:BAABLgAECn8YAAIGAAkJZwmyowA5AQAGAAkJZwmyowA5AQAAAA==.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Tw='Twentycent:BAAALgADCgEJAQAAAA==.',
['Tâ']='Târä:BAAALgAECgUJBQAAAA==.',
Up='Upgrayedd:BAAALgAECgUJBgABLgAECgkJWgASAGMfAA==.',
Va='Vaelandir:BAAALgAECgUJDAAAAA==.Vallkyr:BAABLgAECn8iAAINAAkJ0x5qLABoAgANAAkJ0x5qLABoAgAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAIaAAgJ7A77OQDHAQAaAAgJ7A77OQDHAQAAAA==.',
Vi='Vinnyfr:BAAALgAECgMJBgABLgAECgYJCAAHAAAAAA==.Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyses:BAAALgADCgcJBwAAAA==.Vysys:BAAALgAECgEJAQAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJBAAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAABLgAECn8kAAISAAYJfRJwhgAsAQASAAYJfRJwhgAsAQAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAABLgAECn8dAAIJAAkJrw/kCAA0AQAJAAkJrw/kCAA0AQAAAA==.Zitta:BAABLgAECn8eAAIEAAgJYhV8FwAEAgAEAAgJYhV8FwAEAgAAAA==.Zittav:BAABLgAECn8bAAMFAAkJbBlnGwA5AgAFAAkJbBlnGwA5AgAGAAYJix6xdwB/AQAAAA==.',
Zo='Zoe:BAAALgAECgMJBQAAAA==.Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGQAZAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
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
