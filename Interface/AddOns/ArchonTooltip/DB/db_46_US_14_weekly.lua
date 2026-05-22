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

local lookup = {'DemonHunter-Vengeance','DemonHunter-Devourer','Unknown-Unknown','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Mage-Arcane','Hunter-Survival','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Druid-Balance','Shaman-Enhancement','Priest-Discipline','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Warrior-Protection','Rogue-Subtlety','DemonHunter-Havoc','Monk-Mistweaver','Paladin-Holy',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adrestia:BAEALgAFFAIJAgAAAA==.',
Ae='Aerglo:BAAALgAECgYJDwAAAA==.',
Al='Alidruid:BAAALgAECgQJBQAAAA==.',
An='Analog:BAAALgAECgYJEwAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBgAAAA==.Astraldoge:BAABLgAECn8UAAMBAAYJhgp2FAC5AAACAAYJqwOfpQDHAAABAAUJrQx2FAC5AAAAAA==.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAAALgAFFAIJAwAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Az='Azshanal:BAABLgAECn8hAAICAAgJgyDdFwBFAgACAAgJgyDdFwBFAgAAAA==.',
Ba='Banana:BAAALgADCgUJCQABLgADCgcJBwADAAAAAA==.',
Bi='Biggsthebold:BAABLgAECn8dAAIEAAcJiCQ6IQCmAgAEAAcJiCQ6IQCmAgAAAA==.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAEAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgYJEAAAAA==.',
Br='Brewhousee:BAAALgAECgEJAgAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8hAAIFAAgJNiKFGABwAgAFAAgJNiKFGABwAgAAAA==.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgQJBAAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAIGAAYJMhuIjAC5AQAGAAYJMhuIjAC5AQAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAABLgAECn8xAAIHAAkJOiK7AgBZAwAHAAkJOiK7AgBZAwAAAA==.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8eAAIIAAgJyxdYDACTAQAIAAgJyxdYDACTAQAAAA==.',
Ck='Ckonquer:BAACLgAFFH8LAAIJAAMJwxbSHADqAAAJAAMJwxbSHADqAAAuAAQKfxoAAgkACQnNHkMGAL0CAAkACQnNHkMGAL0CAAAA.',
Cr='Crazytaco:BAAALgADCgYJCgAAAA==.',
Cu='Cursewords:BAABLgAFFH8IAAMKAAYJUAhXCgCmAAALAAQJAgkIVwDPAAAKAAMJvgdXCgCmAAAAAA==.',
Cz='Czaedyn:BAABLgAECn8pAAIKAAkJRBJ1BQDDAQAKAAkJRBJ1BQDDAQAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECggJFgAHAJoEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgADCgYJDQAAAA==.',
De='Deathful:BAABLgAECn8XAAMLAAcJ4hh1RAD+AQALAAcJ4hh1RAD+AQAMAAEJAAAKLQBEAAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Dellea:BAAALgAECgQJBAAAAA==.Depemonkimab:BAAALgADCgQJBAAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8hAAMNAAgJAAzOEQBiAQANAAgJAAzOEQBiAQAOAAEJwAGxegAaAAAAAA==.Deuceretro:BAAALgADCgMJAwAAAA==.',
Di='Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIPAAgJPCGfDADYAgAPAAgJPCGfDADYAgAAAA==.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8eAAILAAcJ1AslaQAsAQALAAcJ1AslaQAsAQAAAA==.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dysis:BAAALgAECgYJDQAAAA==.',
Eb='Eblocked:BAAALgAECgQJBAAAAA==.',
El='Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgYJGAAGAFgQAA==.',
Ev='Evi:BAAALgADCgkJCQAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgADCgkJEwAAAA==.',
Fa='Faelar:BAAALgAECgQJBAAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgcJHgAEAPYjAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8MAAIGAAQJ4Q5jPQA/AQAGAAQJ4Q5jPQA/AQAuAAQKfy4AAgYACAlCHnQmAEACAAYACAlCHnQmAEACAAAA.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.Gordan:BAAALgADCgMJAwABLgAECgkJJAAEAFweAA==.',
Gr='Greasemonkèy:BAABLgAECn8WAAIHAAgJmgSDZgD1AAAHAAgJmgSDZgD1AAAAAA==.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgADAAAAAA==.Heavyroller:BAAALgAECgIJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgADAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8YAAIQAAcJZiQfAQDgAgAQAAcJZiQfAQDgAgAAAA==.Hotten:BAACLgAFFH8HAAIRAAQJTRCEDwAZAQARAAQJTRCEDwAZAQAuAAQKfxgAAxEACAmzDM0WAKIBABEACAmzDM0WAKIBABIABgmPAgGgAJEAAAAA.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8eAAMTAAgJUBA9HwBuAQATAAgJJhA9HwBuAQAUAAcJRQdXMwDnAAAAAA==.',
In='Indomitable:BAAALgAECgYJCgAAAA==.',
Is='Isabelaa:BAAALgAECgQJBAAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAAALgAECgcJEwAAAA==.',
Ka='Kalmea:BAAALgAECgUJCAAAAA==.Kaoru:BAABLgAECn8gAAIVAAgJghMJCgCCAQAVAAgJghMJCgCCAQAAAA==.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgIJAgAAAA==.Kittenhealer:BAAALgAECgkJAwAAAA==.',
Ko='Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn8xAAMLAAgJohl2KgDyAQALAAgJohl2KgDyAQAKAAYJfgwRLQAJAQAAAA==.',
La='Lamar:BAAALgAECgcJEAAAAA==.Lark:BAABLgAECn8nAAMWAAgJnx9zCgBeAgAWAAgJnx9zCgBeAgAXAAYJTRYiNABuAQAAAA==.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Life:BAAALgADCgQJBAAAAA==.Lifedeclined:BAABLgAFFH8GAAIFAAMJYxZTWwD6AAAFAAMJYxZTWwD6AAAAAA==.Lifegiver:BAACLgAFFH8IAAMYAAMJVBdZGwDzAAAYAAMJVBdZGwDzAAAPAAIJOxXHOQCIAAAuAAQKfxwAAw8ACAkoGqoXAEECAA8ACAkoGqoXAEECABgABQk8IlhFABkBAAAA.Lindon:BAAALgADCgIJAgAAAA==.Listyn:BAACLgAFFH8JAAIPAAMJMQOzGgCSAAAPAAMJMQOzGgCSAAAuAAQKfx4AAg8ABwnTEC84AG4BAA8ABwnTEC84AG4BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECggJEQAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgQJBAAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8aAAIZAAgJBBjKDAD2AQAZAAgJBBjKDAD2AQAAAA==.Mart:BAACLgAFFH8MAAINAAQJMh/LDgBGAQANAAQJMh/LDgBGAQAuAAQKfykAAg0ACQngHboIABkCAA0ACQngHboIABkCAAAA.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAANADIfAA==.',
Mi='Miyafuji:BAABLgAECn8hAAMXAAgJ2iNrCQC1AgAXAAgJ2iNrCQC1AgAaAAYJ1R7eEwAOAgAAAA==.',
Mo='Moonwell:BAACLgAFFH8MAAIPAAQJRCDJEAB6AQAPAAQJRCDJEAB6AQAuAAQKfyMAAg8ACAnYJLUFACoDAA8ACAnYJLUFACoDAAAA.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8SAAIRAAUJPCGJBQB3AQARAAUJPCGJBQB3AQAuAAQKfygABBEACQmoIpYEANACABEACQmoIpYEANACABUABAmdD1ZiALcAABIAAQk/FbzRADQAAAAA.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQADAAAAAA==.',
Ni='Ninamori:BAAALgAECgUJBQAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAAALgAECgQJDgABLgAECgcJGAAQAGYkAA==.',
Ob='Obwand:BAAALgADCgMJAgAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8dAAMbAAcJyxH7GgAnAQAbAAcJyxH7GgAnAQAcAAQJNAS4gwCwAAAAAA==.Palanthir:BAABLgAECn8kAAIEAAkJXB65KQASAgAEAAkJXB65KQASAgAAAA==.Pandapve:BAACLgAFFH8PAAMUAAQJpBztBgBcAQAUAAQJpBztBgBcAQATAAEJEAebRwA7AAAuAAQKfykAAxQACAkMIWMKAFMCABQACAkMIWMKAFMCABMABgkpEV9QAAIBAAAA.',
Pe='Peja:BAAALgAECgYJEAAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgADAAAAAA==.',
Ph='Phu:BAACLgAFFH8RAAIYAAUJexh9DQAJAQAYAAUJexh9DQAJAQAuAAQKfzEAAhgACAngJF0FAEgDABgACAngJF0FAEgDAAAA.',
Po='Pockthelock:BAABLgAECn8XAAMMAAcJUxbFDAAhAQALAAcJuA+9XQBHAQAMAAQJ0hvFDAAhAQAAAA==.',
Pu='Puds:BAAALgADCggJEwABLgAECgUJDgADAAAAAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn8oAAILAAkJKhcSLQDmAQALAAkJKhcSLQDmAQAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAAALgAECggJEAAAAA==.Ravioli:BAABLgAECn8jAAITAAgJbiXTAwDdAgATAAgJbiXTAwDdAgABLgAECgcJGAAQAGYkAA==.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8eAAMGAAkJzQwKTgCuAQAGAAkJzQwKTgCuAQAQAAIJOQT/GABQAAAAAA==.Rayliee:BAAALgADCgMJAwABLgAECgkJHgAGAM0MAA==.',
Rd='Rd:BAAALgADCggJDQAAAA==.',
Re='Ret:BAAALgAECgUJBQAAAA==.',
Rh='Rhyssa:BAABLgAECn8WAAIUAAYJmiBOGgAOAgAUAAYJmiBOGgAOAgAAAA==.',
Ro='Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgUJCwAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIEAAgJtBZIRQAUAgAEAAgJtBZIRQAUAgAAAA==.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQXAAcJxAusPgA/AQAXAAcJxAusPgA/AQAWAAQJLAE2WgBQAAAaAAIJ6wFnUQBGAAAAAA==.Sairae:BAAALgADCgIJAgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn8pAAMOAAkJvgvRIQB6AQAOAAkJvgvRIQB6AQAdAAUJwwEZMACWAAAAAA==.',
Se='Sempii:BAAALgAECgUJCQAAAA==.Serarlan:BAAALgAECgEJBQAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Sheve:BAAALgAECgEJAQABLgAECgUJDgADAAAAAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAAALgAECggJEQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skull:BAAALgAECgUJDAAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIeAAcJ2CCBCQCDAgAeAAcJ2CCBCQCDAgAAAA==.Slightcoyote:BAAALgAECgcJEQAAAA==.',
Sm='Smokeyh:BAACLgAFFH8NAAITAAMJ5iGhFQAqAQATAAMJ5iGhFQAqAQAuAAQKf0cAAxMACAneJMUDAN8CABMACAneJMUDAN8CABQAAQnMHWRcAFUAAAAA.',
Sn='Snow:BAABLgAECn8YAAIfAAcJRRtYFwBQAgAfAAcJRRtYFwBQAgAAAA==.',
St='Strongtoast:BAAALgAECggJEgAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAECgcJDAADAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.',
Sy='Syndra:BAAALgADCgYJDAAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgIJAQAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECgIJAwAAAA==.',
Th='Thonor:BAABLgAECn8lAAILAAgJ+BT5OgCvAQALAAgJ+BT5OgCvAQAAAA==.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8ZAAMBAAgJiw1OEAD0AAABAAcJ5ApOEAD0AAAgAAMJpw3cMQCYAAAAAA==.',
To='Torí:BAABLgAECn8XAAIEAAgJvgmyowA5AQAEAAgJvgmyowA5AQAAAA==.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Va='Vaelandir:BAAALgAECgUJCAAAAA==.Vallkyr:BAABLgAECn8iAAIGAAkJ0x6FGwB7AgAGAAkJ0x6FGwB7AgAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAISAAgJ7A77OQDHAQASAAgJ7A77OQDHAQAAAA==.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJAgAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAAALgAECgYJDwAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAAALgAECgYJEQAAAA==.Zitta:BAABLgAECn8eAAIhAAgJYhV8FwAEAgAhAAgJYhV8FwAEAgAAAA==.Zittav:BAABLgAECn8bAAMiAAkJaxlnGwA5AgAiAAkJaxlnGwA5AgAEAAYJix6ESwCbAQAAAA==.',
Zo='Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGAAQAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
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
