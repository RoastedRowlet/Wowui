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

local lookup = {'Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Paladin-Holy','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','Unknown-Unknown','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Mage-Arcane','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Druid-Balance','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Evoker-Devastation','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Adrestia:BAEALgAFFAIJAgABLgAFFAcJGgABAHsYAA==.',
Ae='Aerglo:BAABLgAECn8ZAAQCAAYJRRdDMAAvAQACAAYJsRRDMAAvAQADAAMJNBmISQDHAAAEAAMJ+gbqhgBTAAAAAA==.',
Al='Alidruid:BAAALgAECgQJCAAAAA==.',
An='Analog:BAABLgAECn8fAAMFAAkJnhn7FgA7AgAFAAgJWRj7FgA7AgAGAAMJOgmvEQGAAAAAAA==.Anataea:BAAALgAECgEJAQAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBgAAAA==.Astraldoge:BAABLgAECn8aAAMHAAYJEQyXGgCtAAAHAAUJrQyXGgCtAAAIAAYJGgaMvwCJAAAAAA==.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAABLgAFFH8FAAIJAAIJixYwHACKAAAJAAIJixYwHACKAAAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Az='Azshanal:BAABLgAECn8mAAIIAAkJZyAQEwCWAgAIAAkJZyAQEwCWAgAAAA==.',
Ba='Banana:BAAALgADCgUJCQABLgAECgYJBgAKAAAAAA==.',
Bi='Biggsthebold:BAABLgAECn8dAAIGAAcJiCQ6IQCmAgAGAAcJiCQ6IQCmAgAAAA==.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAGAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgcJEgAAAA==.',
Br='Brewhousee:BAAALgAECgEJAgAAAA==.Brews:BAAALgAECgkJCQAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8mAAILAAkJWSRDCgANAwALAAkJWSRDCgANAwAAAA==.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgcJDAAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAIMAAYJMhuIjAC5AQAMAAYJMhuIjAC5AQAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAABLgAECn83AAINAAkJcyMdAwB8AwANAAkJcyMdAwB8AwAAAA==.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8jAAIOAAkJFRo1CgD8AQAOAAkJFRo1CgD8AQAAAA==.',
Ck='Ckonquer:BAACLgAFFH8OAAIPAAMJwxZIJwDcAAAPAAMJwxZIJwDcAAAuAAQKfxwAAg8ACQnTHpgJALECAA8ACQnTHpgJALECAAAA.',
Cr='Crazytaco:BAAALgAECgYJBgAAAA==.',
Cu='Cursewords:BAABLgAFFH8IAAMQAAYJUAjCEACZAAARAAQJAgn/cADJAAAQAAMJvgfCEACZAAAAAA==.',
Cz='Czaedyn:BAABLgAECn9FAAIQAAkJcxm/AgBrAgAQAAkJcxm/AgBrAgAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECgkJFwANAJwEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Darkseth:BAAALgAECgcJDAAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgAECgEJAQAAAA==.',
De='Deathful:BAABLgAECn8XAAMRAAcJ4hh1RAD+AQARAAcJ4hh1RAD+AQASAAEJAAAKLQBEAAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Deep:BAAALgAECggJCAAAAA==.Dellea:BAAALgAECgYJCQAAAA==.Depemonkimab:BAAALgAECgQJBQAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8mAAMTAAkJCQ3gEACpAQATAAkJCQ3gEACpAQAUAAEJwAHHkQAaAAAAAA==.Deuceretro:BAAALgADCgMJAwAAAA==.Devourer:BAAALgAECgYJBgAAAA==.',
Di='Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIVAAgJPCGfDADYAgAVAAgJPCGfDADYAgAAAA==.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8gAAIRAAcJlA10eAA9AQARAAcJlA10eAA9AQAAAA==.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dysis:BAAALgAECgYJDgAAAA==.Dysos:BAAALgAECgEJAQAAAA==.',
Eb='Eblocked:BAAALgAECgYJCgAAAA==.',
El='Elmorocho:BAAALgADCgEJAQAAAA==.Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgcJGwAMAMEOAA==.',
Es='Esniper:BAAALgADCggJCQAAAA==.',
Ev='Evi:BAAALgAECgEJAQAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgAECgEJAQAAAA==.',
Fa='Faelar:BAAALgAECgUJCwAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgkJIgAGAAYjAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fo='Fornath:BAAALgAECgEJAQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8TAAIMAAQJSBORTAA2AQAMAAQJSBORTAA2AQAuAAQKfzIAAgwACAkmHqAzADICAAwACAkmHqAzADICAAAA.',
Fu='Fury:BAAALgAECgQJBAAAAA==.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.Gordan:BAAALgADCgkJDAABLgAECgkJMwAGAP0fAA==.',
Gr='Greasemonkèy:BAABLgAECn8XAAINAAkJnASDZgD1AAANAAkJnASDZgD1AAAAAA==.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
Ha='Hazyshadow:BAAALgAECgMJAwAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgAKAAAAAA==.Heavyroller:BAAALgAECgIJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgAKAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8YAAIWAAcJZiQfAQDgAgAWAAcJZiQfAQDgAgAAAA==.Hotten:BAACLgAFFH8LAAIXAAQJiRSDFAAaAQAXAAQJiRSDFAAaAQAuAAQKfx4AAxcACAlIFOoUAPEBABcACAlIFOoUAPEBABgABgmPAlzIAJAAAAAA.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8nAAMDAAgJcxIQIgCHAQADAAgJcxIQIgCHAQACAAcJRQfXPwDnAAAAAA==.',
In='Indomitable:BAAALgAECgYJCgAAAA==.Insigthful:BAABLgAFFH8FAAILAAMJ2AVcmgC4AAALAAMJ2AVcmgC4AAAAAA==.',
Is='Isabelaa:BAAALgAECgQJBAAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAABLgAECn8UAAILAAcJbAv1lwAkAQALAAcJbAv1lwAkAQAAAA==.',
Ka='Kalmea:BAAALgAECggJEQAAAA==.Kaoru:BAABLgAECn8lAAIZAAkJWRQ7CQDOAQAZAAkJWRQ7CQDOAQAAAA==.',
Ke='Kessra:BAAALgADCgYJBgAAAA==.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgcJCAAAAA==.Kittenhealer:BAAALgAECgkJBAAAAA==.',
Ko='Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn87AAMRAAkJ7BncIQBOAgARAAkJ7BncIQBOAgAQAAYJfgwRLQAJAQAAAA==.',
La='Lamar:BAABLgAECn8VAAICAAcJxR6HEwAMAgACAAcJxR6HEwAMAgAAAA==.Lark:BAABLgAECn8vAAMaAAkJVSCeBwC9AgAaAAkJVSCeBwC9AgAbAAYJTRYiNABuAQAAAA==.Laurranna:BAAALgADCgYJBgAAAA==.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Liaha:BAAALgAFFAEJAgABLgAFFAMJCQAVADEDAA==.Life:BAAALgADCgQJBAAAAA==.Lifebulwark:BAAALgAECggJEgAAAA==.Lifedeclined:BAABLgAFFH8GAAILAAMJYxa7ggDdAAALAAMJYxa7ggDdAAAAAA==.Lifegiver:BAACLgAFFH8IAAMcAAMJVBfmJQDUAAAcAAMJVBfmJQDUAAAVAAIJOxWFSQB/AAAuAAQKfxwAAxUACAkoGh8eAEICABUACAkoGh8eAEICABwABQk8IlhFABkBAAAA.Lindon:BAAALgADCgcJBwAAAA==.Listyn:BAACLgAFFH8JAAIVAAMJMQOzGgCSAAAVAAMJMQOzGgCSAAAuAAQKfx4AAhUABwnTEGhDAHABABUABwnTEGhDAHABAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECgkJEgAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgcJDAAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8eAAIdAAkJLxnKDAD2AQAdAAkJLxnKDAD2AQAAAA==.Mart:BAACLgAFFH8MAAITAAQJMh+iEwA5AQATAAQJMh+iEwA5AQAuAAQKfykAAhMACQngHewMAGcCABMACQngHewMAGcCAAAA.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAATADIfAA==.',
Mi='Miyafuji:BAABLgAECn8qAAMbAAkJ6CNnBQASAwAbAAkJ6CNnBQASAwABAAYJ1R7eEwAOAgAAAA==.',
Mo='Moonwell:BAACLgAFFH8UAAIVAAUJiSEmDgDlAQAVAAUJiSEmDgDlAQAuAAQKfyMAAhUACAnYJDQIACYDABUACAnYJDQIACYDAAAA.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8WAAIXAAYJxh8cAwDMAQAXAAYJxh8cAwDMAQAuAAQKfyoABBcACQnBI5YEANACABcACQnBI5YEANACABkABAmdD1ZiALcAABgAAQk/FbzRADQAAAAA.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQAKAAAAAA==.',
Ni='Ninamori:BAAALgAECgUJBwAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAABLgAECn8ZAAIFAAYJ+SRZEACBAgAFAAYJ+SRZEACBAgABLgAECgcJGAAWAGYkAA==.',
Ob='Obwand:BAAALgAECgEJAQAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8dAAMeAAcJyxEPJgAhAQAeAAcJyxEPJgAhAQAfAAQJNAS4gwCwAAAAAA==.Palanthir:BAABLgAECn8zAAIGAAkJ/R+0DwDTAgAGAAkJ/R+0DwDTAgAAAA==.Pandapve:BAACLgAFFH8XAAMCAAUJ4iAiBwCGAQACAAUJ4iAiBwCGAQADAAEJEAcBVAA5AAAuAAQKfywAAwIACAnZIakKAIUCAAIACAnZIakKAIUCAAMABgkrEV9QAAIBAAAA.Pascratt:BAAALgAECgQJBgAAAA==.',
Pe='Peja:BAABLgAECn8aAAMgAAgJqgbEJQBLAQAgAAgJqgbEJQBLAQAhAAYJ7QN3FACsAAAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgAKAAAAAA==.Perrywinkle:BAAALgAECgEJAQAAAA==.',
Ph='Phu:BAACLgAFFH8WAAIcAAYJhxlRGAAqAQAcAAYJhxlRGAAqAQAuAAQKfzMAAhwACQlrJOUDABYDABwACQlrJOUDABYDAAAA.',
Po='Pockthelock:BAACLgAFFH8FAAISAAIJZBcLCgCuAAASAAIJZBcLCgCuAAAuAAQKfyMAAxIABwkrG9YIALgBABIABwkrG9YIALgBABEABwm4D45yAEoBAAAA.',
Pu='Puds:BAAALgADCggJEwABLgAECgYJGQABAG4gAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn88AAIRAAkJcRv1GACCAgARAAkJcRv1GACCAgAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAABLgAECn8eAAQGAAgJ0xMVhQBKAQAGAAcJwhAVhQBKAQAFAAUJjQLIXwCaAAAiAAEJlgEuVgAQAAAAAA==.Ravioli:BAABLgAECn8oAAIDAAkJnCV5AQBOAwADAAkJnCV5AQBOAwABLgAECgcJGAAWAGYkAA==.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8jAAMMAAkJuA0HXwCqAQAMAAkJuA0HXwCqAQAWAAIJOQT/GABQAAAAAA==.Rayliee:BAAALgADCgMJAwABLgAECgkJIwAMALgNAA==.',
Rd='Rd:BAABLgAECn8TAAIMAAYJfhLrkAA7AQAMAAYJfhLrkAA7AQAAAA==.',
Re='Ret:BAAALgAECgYJCgAAAA==.',
Rh='Rhyssa:BAABLgAECn8dAAICAAcJACLgFwDeAQACAAcJACLgFwDeAQAAAA==.',
Ro='Roccet:BAAALgAECgMJAwABLgAECggJFQADAPQiAA==.Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgUJCwAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIGAAgJtBZIRQAUAgAGAAgJtBZIRQAUAgAAAA==.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQbAAcJxAusPgA/AQAbAAcJxAusPgA/AQAaAAQJLAE2WgBQAAABAAIJ6wFnUQBGAAAAAA==.Sairae:BAAALgADCgIJAgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn9FAAMUAAkJfxA5HQDTAQAUAAkJfxA5HQDTAQAjAAUJwwEZMACWAAAAAA==.',
Se='Sempii:BAAALgAECgUJCgAAAA==.Serarlan:BAAALgAECgEJCAAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Shentyphoon:BAAALgAECgEJAQAAAA==.Sheve:BAAALgAECgEJAgABLgAECgYJGQABAG4gAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAABLgAECn8hAAIMAAgJWRO+VwC9AQAMAAgJWRO+VwC9AQAAAA==.Sinisteredge:BAAALgADCgEJAQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skork:BAAALgAECgYJBwAAAA==.Skull:BAAALgAECgUJDAAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIkAAcJ2CCBCQCDAgAkAAcJ2CCBCQCDAgAAAA==.Slightcoyote:BAAALgAECggJEwAAAA==.',
Sm='Smokeyh:BAACLgAFFH8TAAIDAAQJayEzEAB6AQADAAQJayEzEAB6AQAuAAQKf0gAAwMACAneJJEFANcCAAMACAneJJEFANcCAAIAAQnMHcZ0AFIAAAAA.',
Sn='Snow:BAABLgAECn8eAAIgAAkJdyLrCwBPAgAgAAkJdyLrCwBPAgAAAA==.',
So='Solarasis:BAAALgAECgEJAQAAAA==.',
St='Strongtoast:BAAALgAFFAIJAgAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAFFAEJAQAKAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.',
Sy='Syndra:BAAALgADCgkJEwAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgYJBwAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Tad:BAAALgAECgYJBwAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECggJCwAAAA==.',
Th='Thonor:BAABLgAECn8rAAIRAAkJGBVfMgACAgARAAkJGBVfMgACAgAAAA==.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8bAAMHAAkJ8w/ZFADqAAAlAAQJbxK6LQDwAAAHAAcJ5ArZFADqAAAAAA==.',
To='Torí:BAABLgAECn8YAAIGAAkJZwmyowA5AQAGAAkJZwmyowA5AQAAAA==.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Va='Vaelandir:BAAALgAECgUJCwAAAA==.Vallkyr:BAABLgAECn8iAAIMAAkJ0x7LJgBqAgAMAAkJ0x7LJgBqAgAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAIYAAgJ7A77OQDHAQAYAAgJ7A77OQDHAQAAAA==.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJBAAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAAALgAECgYJEQAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAAALgAECgcJEgAAAA==.Zitta:BAABLgAECn8eAAIEAAgJYhV8FwAEAgAEAAgJYhV8FwAEAgAAAA==.Zittav:BAABLgAECn8bAAMFAAkJbBlnGwA5AgAFAAkJbBlnGwA5AgAGAAYJix4waQCDAQAAAA==.',
Zo='Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGAAWAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
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
