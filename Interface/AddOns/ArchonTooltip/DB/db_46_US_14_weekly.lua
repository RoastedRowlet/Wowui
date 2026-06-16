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

local lookup = {'Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','Hunter-Survival','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Mage-Arcane','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','DeathKnight-Blood','Druid-Balance','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Evoker-Devastation','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adrestia:BAEALgAFFAIJAgABLgAFFAgJIAABAFMaAA==.',
Ae='Aerglo:BAABLgAECn8eAAQCAAYJVBe+MwAxAQACAAYJ7BS+MwAxAQADAAMJNBkITgDFAAAEAAMJ+gYMngBUAAAAAA==.',
Al='Alidruid:BAAALgAECgQJCQAAAA==.',
An='Analog:BAACLgAFFH8FAAMFAAMJLhXtKADYAAAFAAMJLhXtKADYAAAGAAEJsgCqywAiAAAuAAQKfyQAAwUACQkkGzQVAGECAAUACAkQGjQVAGECAAYAAwk6CRosAX8AAAAA.Anataea:BAAALgAECgEJAQAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBgABLgAECgYJCgAHAAAAAA==.Astraldoge:BAABLgAECn8cAAMIAAYJPgyfHQCqAAAIAAUJrQyfHQCqAAAJAAYJqgZlyQCYAAAAAA==.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAABLgAFFH8HAAIKAAIJixYbJgB+AAAKAAIJixYbJgB+AAAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Ay='Ayeka:BAAALgADCgYJBgAAAA==.',
Az='Azshanal:BAABLgAECn8oAAIJAAkJZyA4FQCWAgAJAAkJZyA4FQCWAgAAAA==.',
Ba='Banana:BAAALgADCgUJCQABLgAECggJMwALANUZAA==.',
Bi='Bicepcurls:BAAALgAECgYJBgAAAA==.Biggsthebold:BAABLgAECn8dAAIGAAcJiCQ6IQCmAgAGAAcJiCQ6IQCmAgAAAA==.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAGAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgcJEgAAAA==.',
Br='Brewhousee:BAAALgAECgEJAwAAAA==.Brews:BAAALgAECgkJCQAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8oAAIMAAkJWSSgDAAGAwAMAAkJWSSgDAAGAwAAAA==.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgcJDQAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAINAAYJMhuIjAC5AQANAAYJMhuIjAC5AQAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAACLgAFFH8KAAIOAAMJMR2VOAD4AAAOAAMJMR2VOAD4AAAuAAQKfzcAAg4ACQlzIwQEAHcDAA4ACQlzIwQEAHcDAAAA.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8lAAIPAAkJZBpmCwABAgAPAAkJZBpmCwABAgAAAA==.',
Ck='Ckonquer:BAACLgAFFH8OAAIQAAMJwxZiMADIAAAQAAMJwxZiMADIAAAuAAQKfxwAAhAACQnTHksLAKsCABAACQnTHksLAKsCAAAA.',
Cr='Crazytaco:BAAALgAECgYJCAAAAA==.',
Cu='Cursewords:BAABLgAFFH8IAAMRAAYJUAgoFACXAAASAAQJAgmegQC9AAARAAMJvgcoFACXAAABLgAFFAcJEQAGAAcWAA==.',
Cz='Czaedyn:BAABLgAECn9cAAIRAAkJ0xwcAgCkAgARAAkJ0xwcAgCkAgAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECgkJFwAOAJwEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Darkseth:BAAALgAFFAEJAQAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgAECgEJAQAAAA==.',
De='Deathful:BAABLgAECn8XAAMSAAcJ4hh1RAD+AQASAAcJ4hh1RAD+AQATAAEJAAAKLQBEAAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Deep:BAAALgAECggJDAAAAA==.Dellea:BAAALgAECgYJCQAAAA==.Depemonkimab:BAAALgAECgYJBwAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8oAAMUAAkJOA0iEgCjAQAUAAkJOA0iEgCjAQAVAAEJwAFyoQAYAAAAAA==.Deuceretro:BAAALgADCgMJAwAAAA==.Devourer:BAAALgAECgYJBgAAAA==.',
Di='Diirt:BAAALgADCgYJBgAAAA==.Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIWAAgJPCGfDADYAgAWAAgJPCGfDADYAgAAAA==.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8gAAISAAcJlA0yggA0AQASAAcJlA0yggA0AQAAAA==.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dysis:BAAALgAECgYJEwAAAA==.Dysos:BAAALgAECgMJBwAAAA==.',
Eb='Eblocked:BAAALgAECgYJCgAAAA==.',
El='Elmorocho:BAAALgADCgEJAQAAAA==.Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECggJGgADAAMRAA==.',
Es='Esniper:BAAALgADCggJCQAAAA==.',
Ev='Evi:BAAALgAECgYJDgAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgAECgEJAQAAAA==.',
Fa='Faelar:BAAALgAECgUJDwAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgkJIgAGAAYjAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fo='Fornath:BAAALgAECgEJAQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8VAAINAAUJSBP6WwAyAQANAAUJSBP6WwAyAQAuAAQKfzMAAg0ACAkmHs03ADYCAA0ACAkmHs03ADYCAAAA.',
Fu='Fury:BAAALgAECgQJCAAAAA==.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.Geztherion:BAAALgAECgEJAQABLgAECgUJEQAHAAAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.Gordan:BAAALgADCgkJDAABLgAECgkJMwAGAP0fAA==.',
Gr='Greasemonkèy:BAABLgAECn8XAAIOAAkJnASDZgD1AAAOAAkJnASDZgD1AAAAAA==.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
Ha='Hazyshadow:BAAALgAECgQJBgAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgAHAAAAAA==.Heavyroller:BAAALgAECgIJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgAHAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8ZAAIXAAcJZiQfAQDgAgAXAAcJZiQfAQDgAgAAAA==.Hotten:BAACLgAFFH8LAAILAAQJiRQEGAANAQALAAQJiRQEGAANAQAuAAQKfx4AAwsACAlIFBIXAOkBAAsACAlIFBIXAOkBABgABgmPAmjdAIsAAAAA.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8qAAMDAAkJShIGGwDLAQADAAkJShIGGwDLAQACAAcJRQdcSADcAAAAAA==.',
In='Indomitable:BAAALgAECgYJCgAAAA==.Insigthful:BAABLgAFFH8FAAIMAAMJ2AV/tgCzAAAMAAMJ2AV/tgCzAAAAAA==.',
Is='Isabelaa:BAAALgAECgQJBAAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAABLgAECn8UAAIMAAcJbAu/pQAgAQAMAAcJbAu/pQAgAQAAAA==.',
Ka='Kalmea:BAAALgAECggJEQAAAA==.Kaoru:BAABLgAECn8nAAIZAAkJWRR/CgDBAQAZAAkJWRR/CgDBAQAAAA==.',
Ke='Kessra:BAAALgADCgYJBgAAAA==.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgcJDQAAAA==.Kittenhealer:BAAALgAECgkJCAAAAA==.',
Ko='Korrel:BAAALgADCgEJAQABLgAECgcJJwABAK8iAA==.Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn9SAAMSAAkJARwwGACRAgASAAkJARwwGACRAgARAAYJfgwRLQAJAQAAAA==.',
La='Lamar:BAABLgAECn8VAAICAAcJxR7SFQAHAgACAAcJxR7SFQAHAgAAAA==.Lark:BAABLgAECn8vAAMaAAkJVSDyCAC/AgAaAAkJVSDyCAC/AgAbAAYJTRYiNABuAQAAAA==.Laurranna:BAAALgADCgYJBgAAAA==.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Liaha:BAAALgAFFAEJAgABLgAFFAMJCQAWADEDAA==.Life:BAAALgADCgQJBAAAAA==.Lifebulwark:BAAALgAFFAEJAgAAAA==.Lifedeclined:BAABLgAFFH8IAAMcAAMJFhr/KwCWAAAMAAMJYxaUnADXAAAcAAIJRxb/KwCWAAAAAA==.Lifegiver:BAACLgAFFH8NAAMdAAYJ3x0YDgCyAQAdAAYJ3x0YDgCyAQAWAAIJOxX5UgByAAAuAAQKfx4AAxYACQmEGW4gAEACABYACAkoGm4gAEACAB0ABwloIng2ADgBAAAA.Lifeisholy:BAAALgAECgcJDQAAAA==.Lindon:BAAALgADCgcJBwAAAA==.Listyn:BAACLgAFFH8JAAIWAAMJMQOzGgCSAAAWAAMJMQOzGgCSAAAuAAQKfx4AAhYABwnTEHJHAG8BABYABwnTEHJHAG8BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECgkJEgAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgcJDQAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8gAAIeAAkJyRnKDAD2AQAeAAkJyRnKDAD2AQAAAA==.Mart:BAACLgAFFH8MAAIUAAQJMh8IFgArAQAUAAQJMh8IFgArAQAuAAQKfykAAhQACQngHewMAGcCABQACQngHewMAGcCAAAA.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAAUADIfAA==.',
Mi='Miyafuji:BAABLgAECn8sAAMbAAkJEiSBBgAIAwAbAAkJ6COBBgAIAwABAAYJGB/eEwAOAgAAAA==.',
Mo='Moonwell:BAACLgAFFH8UAAIWAAUJiSFZEgDVAQAWAAUJiSFZEgDVAQAuAAQKfyMAAhYACAnYJEoJACMDABYACAnYJEoJACMDAAAA.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8WAAILAAYJxh//BAC7AQALAAYJxh//BAC7AQAuAAQKfyoABAsACQnBI5YEANACAAsACQnBI5YEANACABkABAmdD1ZiALcAABgAAQk/FbzRADQAAAAA.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQAHAAAAAA==.Narnode:BAAALgAECgYJCgAAAA==.',
Ni='Ninamori:BAAALgAECgUJBwAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAABLgAECn8eAAIFAAYJ+SRKEgB+AgAFAAYJ+SRKEgB+AgABLgAECgcJGQAXAGYkAA==.',
Ob='Obwand:BAAALgAECgEJAQAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8dAAMfAAcJyxFaKgAfAQAfAAcJyxFaKgAfAQAgAAQJNAS4gwCwAAAAAA==.Palanthir:BAABLgAECn8zAAIGAAkJ/R8uEwDNAgAGAAkJ/R8uEwDNAgAAAA==.Pandapve:BAACLgAFFH8XAAMCAAUJ4iBHCgBzAQACAAUJ4iBHCgBzAQADAAEJEAfZWQA4AAAuAAQKfywAAwIACAnZITYMAH4CAAIACAnZITYMAH4CAAMABgkrEV9QAAIBAAAA.Pascratt:BAAALgAECgYJCQAAAA==.',
Pe='Peja:BAABLgAECn8lAAMhAAgJKwscIwB3AQAhAAgJKwscIwB3AQAiAAYJ7QOTFgCqAAAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgAHAAAAAA==.Perrywinkle:BAAALgAECgEJAQAAAA==.',
Ph='Phu:BAACLgAFFH8iAAIdAAYJdBxXDgCvAQAdAAYJdBxXDgCvAQAuAAQKfzMAAh0ACQlrJKoEABEDAB0ACQlrJKoEABEDAAAA.',
Po='Pockthelock:BAACLgAFFH8KAAITAAUJCBTLBQAjAQATAAUJCBTLBQAjAQAuAAQKfyoAAxMACQm1GhUFADsCABMACAkqHRUFADsCABIACAnVDi5gAH8BAAAA.',
Pu='Puds:BAAALgADCggJEwABLgAECgcJJwABAK8iAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn9OAAISAAkJ/B4zDgDZAgASAAkJ/B4zDgDZAgAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAABLgAECn8hAAQGAAkJJBi/UADUAQAGAAgJIBa/UADUAQAFAAUJjQL+ZQCaAAAjAAEJlgFvXgAQAAAAAA==.Ravioli:BAABLgAECn8qAAIDAAkJwSWiAQBQAwADAAkJwSWiAQBQAwABLgAECgcJGQAXAGYkAA==.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8jAAMNAAkJuA2VZQCvAQANAAkJuA2VZQCvAQAXAAIJOQT/GABQAAAAAA==.Rayliee:BAAALgADCgMJAwABLgAECgkJIwANALgNAA==.',
Rd='Rd:BAABLgAECn8TAAINAAYJfhIgnQA9AQANAAYJfhIgnQA9AQAAAA==.',
Re='Rendurface:BAAALgAECgEJAQAAAA==.Requiel:BAAALgAECgUJCwAAAA==.Ret:BAAALgAECgkJEgAAAA==.',
Rh='Rhyssa:BAABLgAECn8dAAICAAcJACKMGgDYAQACAAcJACKMGgDYAQAAAA==.',
Ro='Roccet:BAAALgAECgMJAwABLgAECggJFQADAPQiAA==.Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgUJDAAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIGAAgJtBZIRQAUAgAGAAgJtBZIRQAUAgAAAA==.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQbAAcJxAusPgA/AQAbAAcJxAusPgA/AQAaAAQJLAE2WgBQAAABAAIJ6wFnUQBGAAAAAA==.Sairae:BAAALgADCgIJAgAAAA==.Sasuke:BAAALgAECgYJBgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn9YAAMVAAkJhxQtFgAmAgAVAAkJhxQtFgAmAgAkAAUJwwEZMACWAAAAAA==.',
Se='Sempii:BAAALgAECgUJCgAAAA==.Serarlan:BAAALgAECgEJCAAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Shentyphoon:BAAALgAECgEJAQAAAA==.Sheve:BAAALgAECgEJAgABLgAECgcJJwABAK8iAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAABLgAECn8nAAINAAkJARa1OgAsAgANAAkJARa1OgAsAgAAAA==.Sinisteredge:BAAALgADCgEJAQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skork:BAAALgAECgYJCgAAAA==.Skull:BAAALgAECgUJDAAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIlAAcJ2CCBCQCDAgAlAAcJ2CCBCQCDAgAAAA==.Slightcoyote:BAABLgAECn8ZAAIWAAgJzg6nQACMAQAWAAgJzg6nQACMAQAAAA==.',
Sm='Smokeyh:BAACLgAFFH8TAAIDAAQJayFjFQBwAQADAAQJayFjFQBwAQAuAAQKf0gAAwMACAneJFQGANMCAAMACAneJFQGANMCAAIAAQnMHTiBAFAAAAAA.',
Sn='Snow:BAABLgAECn8eAAIhAAkJdyLdDQBHAgAhAAkJdyLdDQBHAgAAAA==.',
So='Solarasis:BAAALgAECgEJAgAAAA==.Somos:BAAALgAECgQJBAAAAA==.',
St='Strongtoast:BAAALgAFFAIJAgAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.Swiftblood:BAAALgAECgUJBgAAAA==.',
Sy='Syndra:BAAALgADCgkJEwAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgcJCgAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Tad:BAAALgAECgYJBwAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECggJEwAAAA==.',
Th='Thonor:BAABLgAECn8vAAISAAkJpRVkLgAdAgASAAkJpRVkLgAdAgAAAA==.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8dAAMIAAkJ8w8CFwDpAAAmAAQJbxJaNADpAAAIAAcJ5AoCFwDpAAAAAA==.',
To='Torí:BAABLgAECn8YAAIGAAkJZwmyowA5AQAGAAkJZwmyowA5AQAAAA==.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Up='Upgrayedd:BAAALgAECgUJBgABLgAECgkJTgASAPweAA==.',
Va='Vaelandir:BAAALgAECgUJCwAAAA==.Vallkyr:BAABLgAECn8iAAINAAkJ0x6NKwBpAgANAAkJ0x6NKwBpAgAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAIYAAgJ7A77OQDHAQAYAAgJ7A77OQDHAQAAAA==.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vysys:BAAALgAECgEJAQAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJBAAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAABLgAECn8hAAISAAYJbhJwhQAuAQASAAYJbhJwhQAuAQAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAABLgAECn8VAAIJAAgJwwzaewAlAQAJAAgJwwzaewAlAQAAAA==.Zitta:BAABLgAECn8eAAIEAAgJYhV8FwAEAgAEAAgJYhV8FwAEAgAAAA==.Zittav:BAABLgAECn8bAAMFAAkJbBlnGwA5AgAFAAkJbBlnGwA5AgAGAAYJix7cdQCAAQAAAA==.',
Zo='Zoe:BAAALgAECgMJAwAAAA==.Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGQAXAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
Zy='Zylia:BAAALgADCgIJAgAAAA==.',
['Zà']='Zàpster:BAAALgAECgkJAQAAAA==.',
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
