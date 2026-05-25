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

local lookup = {'Priest-Discipline','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Paladin-Holy','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','Unknown-Unknown','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Mage-Arcane','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Druid-Balance','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','Paladin-Protection','Evoker-Devastation','Warrior-Protection','Rogue-Subtlety','DemonHunter-Havoc',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adrestia:BAEALgAFFAIJAgABLgAFFAcJGgABAHsYAA==.',
Ae='Aerglo:BAABLgAECn8WAAQCAAYJahZYLgAmAQACAAYJ1hNYLgAmAQADAAMJNBmNRQDJAAAEAAMJ+gbDdABWAAAAAA==.',
Al='Alidruid:BAAALgAECgQJCAAAAA==.',
An='Analog:BAABLgAECn8cAAMFAAgJEhx0JgCvAQAFAAYJJBl0JgCvAQAGAAMJOgkCAQGHAAAAAA==.Anataea:BAAALgAECgEJAQAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJFAAAAA==.',
As='Asheda:BAAALgAECgEJBgAAAA==.Astraldoge:BAABLgAECn8aAAMHAAYJEQw5GAC0AAAHAAUJrQw5GAC0AAAIAAYJGgbTsgCSAAAAAA==.Astraldogeh:BAAALgAECgQJBAAAAA==.Astranaar:BAABLgAFFH8FAAIJAAIJixarFQCPAAAJAAIJixarFQCPAAAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Az='Azshanal:BAABLgAECn8mAAIIAAkJZyDvEACfAgAIAAkJZyDvEACfAgAAAA==.',
Ba='Banana:BAAALgADCgUJCQABLgAECgYJBgAKAAAAAA==.',
Bi='Biggsthebold:BAABLgAECn8dAAIGAAcJiCQ6IQCmAgAGAAcJiCQ6IQCmAgAAAA==.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQAGAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgcJEgAAAA==.',
Br='Brewhousee:BAAALgAECgEJAgAAAA==.Brews:BAAALgAECgkJCQAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8mAAILAAkJWSRvCAATAwALAAkJWSRvCAATAwAAAA==.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
['Bä']='Bänjo:BAAALgAECgcJDAAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgMJBwAAAA==.Castor:BAABLgAECn8VAAIMAAYJMhuIjAC5AQAMAAYJMhuIjAC5AQAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAABLgAECn83AAINAAkJcyN2AgCAAwANAAkJcyN2AgCAAwAAAA==.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8jAAIOAAkJFRriCAAJAgAOAAkJFRriCAAJAgAAAA==.',
Ck='Ckonquer:BAACLgAFFH8LAAIPAAMJwxZZIwDhAAAPAAMJwxZZIwDhAAAuAAQKfxoAAg8ACQnTHoMIALQCAA8ACQnTHoMIALQCAAAA.',
Cr='Crazytaco:BAAALgADCgYJCgAAAA==.',
Cu='Cursewords:BAABLgAFFH8IAAMQAAYJUAgLDgCbAAARAAQJAglSZgDKAAAQAAMJvgcLDgCbAAAAAA==.',
Cz='Czaedyn:BAABLgAECn82AAIQAAkJgRbsAwAiAgAQAAkJgRbsAwAiAgAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECgkJFwANAJwEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Darkseth:BAAALgAECgcJDAAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgAECgEJAQAAAA==.',
De='Deathful:BAABLgAECn8XAAMRAAcJ4hh1RAD+AQARAAcJ4hh1RAD+AQASAAEJAAAKLQBEAAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Dellea:BAAALgAECgQJBAAAAA==.Depemonkimab:BAAALgADCgQJBAAAAA==.Derpcat:BAAALgAECgcJDQAAAA==.Dervish:BAABLgAECn8mAAMTAAkJCQ17DwCvAQATAAkJCQ17DwCvAQAUAAEJwAEoiwAaAAAAAA==.Deuceretro:BAAALgADCgMJAwAAAA==.',
Di='Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIVAAgJPCGfDADYAgAVAAgJPCGfDADYAgAAAA==.',
Do='Dogwater:BAAALgADCgUJBAAAAA==.Doomcow:BAABLgAECn8gAAIRAAcJlA0hcQBCAQARAAcJlA0hcQBCAQAAAA==.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dysis:BAAALgAECgYJDQAAAA==.Dysos:BAAALgADCgcJBwAAAA==.',
Eb='Eblocked:BAAALgAECgQJBAAAAA==.',
El='Elmorocho:BAAALgADCgEJAQAAAA==.Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgYJGAAMAFgQAA==.',
Ev='Evi:BAAALgAECgEJAQAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgAECgEJAQAAAA==.',
Fa='Faelar:BAAALgAECgQJBgAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.',
Fi='Fishing:BAAALgADCgMJAwABLgAECgkJIAAGAKYiAA==.Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8OAAIMAAQJjw9WSgA0AQAMAAQJjw9WSgA0AQAuAAQKfy4AAgwACAkmHlAvAD0CAAwACAkmHlAvAD0CAAAA.',
Fu='Fury:BAAALgAECgQJBAAAAA==.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.Gordan:BAAALgADCgkJCgABLgAECgkJLgAGANMfAA==.',
Gr='Greasemonkèy:BAABLgAECn8XAAINAAkJnASDZgD1AAANAAkJnASDZgD1AAAAAA==.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
He='Healistraza:BAAALgAECggJEgABLgAFFAIJAgAKAAAAAA==.Heavyroller:BAAALgAECgIJAQAAAA==.Help:BAAALgAECgYJBgABLgAFFAIJAgAKAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8YAAIWAAcJZiQfAQDgAgAWAAcJZiQfAQDgAgAAAA==.Hotten:BAACLgAFFH8KAAIXAAQJiRTEEQAgAQAXAAQJiRTEEQAgAQAuAAQKfxkAAxcACAmzDCocAJ0BABcACAmzDCocAJ0BABgABgmPAti5AJAAAAAA.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAABLgAECn8mAAMDAAgJcxK1HwCLAQADAAgJcxK1HwCLAQACAAcJRQejOgDpAAAAAA==.',
In='Indomitable:BAAALgAECgYJCgAAAA==.',
Is='Isabelaa:BAAALgAECgQJBAAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAABLgAECn8UAAILAAcJbAtjjAAmAQALAAcJbAtjjAAmAQAAAA==.',
Ka='Kalmea:BAAALgAECgcJDwAAAA==.Kaoru:BAABLgAECn8lAAIZAAkJWRRMCADWAQAZAAkJWRRMCADWAQAAAA==.',
Ke='Kessra:BAAALgADCgYJBgAAAA==.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kinjari:BAAALgAECgIJAgAAAA==.Kittenhealer:BAAALgAECgkJAwAAAA==.',
Ko='Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn87AAMRAAkJ7BmhHgBTAgARAAkJ7BmhHgBTAgAQAAYJfgwRLQAJAQAAAA==.',
La='Lamar:BAABLgAECn8VAAICAAcJxR6+EQAQAgACAAcJxR6+EQAQAgAAAA==.Lark:BAABLgAECn8tAAMaAAgJQSB4DABoAgAaAAgJQSB4DABoAgAbAAYJTRYiNABuAQAAAA==.Laurranna:BAAALgADCgYJBgAAAA==.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Liaha:BAAALgAECgYJBgABLgAFFAMJCQAVADEDAA==.Life:BAAALgADCgQJBAAAAA==.Lifebulwark:BAAALgAECgQJBgAAAA==.Lifedeclined:BAABLgAFFH8GAAILAAMJYxaNcQDpAAALAAMJYxaNcQDpAAAAAA==.Lifegiver:BAACLgAFFH8IAAMcAAMJVBedIQDpAAAcAAMJVBedIQDpAAAVAAIJOxWKQgCIAAAuAAQKfxwAAxUACAkoGiwcAEECABUACAkoGiwcAEECABwABQk8IlhFABkBAAAA.Lindon:BAAALgADCgcJBwAAAA==.Listyn:BAACLgAFFH8JAAIVAAMJMQOzGgCSAAAVAAMJMQOzGgCSAAAuAAQKfx4AAhUABwnTEA5AAG8BABUABwnTEA5AAG8BAAAA.Litvyak:BAAALgAECgMJAwAAAA==.',
Lo='Lolly:BAAALgAECggJEQAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ly='Lyssandra:BAAALgAECgcJDAAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJEgAAAA==.Mandan:BAABLgAECn8eAAIdAAkJLxnKDAD2AQAdAAkJLxnKDAD2AQAAAA==.Mart:BAACLgAFFH8MAAITAAQJMh+yEQA/AQATAAQJMh+yEQA/AQAuAAQKfykAAhMACQngHewMAGcCABMACQngHewMAGcCAAAA.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Me='Megamart:BAAALgAECgMJBAABLgAFFAQJDAATADIfAA==.',
Mi='Miyafuji:BAABLgAECn8qAAMbAAkJ6COSBAAbAwAbAAkJ6COSBAAbAwABAAYJ1R7eEwAOAgAAAA==.',
Mo='Moonwell:BAACLgAFFH8QAAIVAAQJRCBpFQB2AQAVAAQJRCBpFQB2AQAuAAQKfyMAAhUACAnYJEYHACgDABUACAnYJEYHACgDAAAA.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8VAAIXAAUJOyM7BgB/AQAXAAUJOyM7BgB/AQAuAAQKfyoABBcACQnBI5YEANACABcACQnBI5YEANACABkABAmdD1ZiALcAABgAAQk/FbzRADQAAAAA.',
['Mí']='Míriel:BAAALgAECgEJAgAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEQAKAAAAAA==.',
Ni='Ninamori:BAAALgAECgUJBwAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEQAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAABLgAECn8YAAIFAAUJcCUwGAAfAgAFAAUJcCUwGAAfAgABLgAECgcJGAAWAGYkAA==.',
Ob='Obwand:BAAALgADCgMJAgAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAABLgAECn8dAAMeAAcJyxHqIQAnAQAeAAcJyxHqIQAnAQAfAAQJNAS4gwCwAAAAAA==.Palanthir:BAABLgAECn8uAAIGAAkJ0x8WDgDbAgAGAAkJ0x8WDgDbAgAAAA==.Pandapve:BAACLgAFFH8TAAMCAAQJ4iCBBQCNAQACAAQJ4iCBBQCNAQADAAEJEAc4TwA6AAAuAAQKfywAAwIACAnaIYAJAIgCAAIACAnaIYAJAIgCAAMABgkrEV9QAAIBAAAA.Pascratt:BAAALgAECgMJAwAAAA==.',
Pe='Peja:BAAALgAECgcJEwAAAA==.Pelan:BAAALgADCgIJAgABLgAFFAIJAgAKAAAAAA==.',
Ph='Phu:BAACLgAFFH8TAAIcAAUJexh9DQAJAQAcAAUJexh9DQAJAQAuAAQKfzEAAhwACAnhJF0FAEgDABwACAnhJF0FAEgDAAAA.',
Po='Pockthelock:BAABLgAECn8eAAMSAAcJdhg9CwBzAQASAAYJ2Bs9CwBzAQARAAcJuA/ZawBNAQAAAA==.',
Pu='Puds:BAAALgADCggJEwABLgAECgYJFAABAOgeAA==.',
Qu='Quanche:BAAALgAECgEJAQAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn8zAAIRAAkJTxorHABhAgARAAkJTxorHABhAgAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAABLgAECn8YAAQGAAgJyQxPqAAJAQAGAAcJiwhPqAAJAQAFAAUJjQK1WgCaAAAgAAEJlgG/TwAQAAAAAA==.Ravioli:BAABLgAECn8oAAIDAAkJnCUzAQBSAwADAAkJnCUzAQBSAwABLgAECgcJGAAWAGYkAA==.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8jAAMMAAkJuA0fVADDAQAMAAkJuA0fVADDAQAWAAIJOQT/GABQAAAAAA==.Rayliee:BAAALgADCgMJAwABLgAECgkJIwAMALgNAA==.',
Rd='Rd:BAAALgAECgcJCgAAAA==.',
Re='Ret:BAAALgAECgYJCgAAAA==.',
Rh='Rhyssa:BAABLgAECn8bAAICAAcJ2yDEGADCAQACAAcJ2yDEGADCAQAAAA==.',
Ro='Roccet:BAAALgAECgMJAwABLgAECggJFQADAPQiAA==.Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgUJCwAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAIGAAgJtBZIRQAUAgAGAAgJtBZIRQAUAgAAAA==.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQbAAcJxAusPgA/AQAbAAcJxAusPgA/AQAaAAQJLAE2WgBQAAABAAIJ6wFnUQBGAAAAAA==.Sairae:BAAALgADCgIJAgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn82AAMUAAkJCw5xIQCrAQAUAAkJCw5xIQCrAQAhAAUJwwEZMACWAAAAAA==.',
Se='Sempii:BAAALgAECgUJCQAAAA==.Serarlan:BAAALgAECgEJBwAAAA==.',
Sh='Shadowful:BAAALgAECggJAgAAAA==.Sheve:BAAALgAECgEJAQABLgAECgYJFAABAOgeAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBwAAAA==.',
Si='Sinist:BAABLgAECn8bAAIMAAgJfg73ZgCSAQAMAAgJfg73ZgCSAQAAAA==.Sinisteredge:BAAALgADCgEJAQAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skork:BAAALgAECgIJAQAAAA==.Skull:BAAALgAECgUJDAAAAA==.',
Sl='Slager:BAAALgAECgMJBAAAAA==.Slagr:BAABLgAECn8bAAIiAAcJ2CCBCQCDAgAiAAcJ2CCBCQCDAgAAAA==.Slightcoyote:BAAALgAECggJEwAAAA==.',
Sm='Smokeyh:BAACLgAFFH8TAAIDAAQJayGtDACEAQADAAQJayGtDACEAQAuAAQKf0gAAwMACAneJOgEANoCAAMACAneJOgEANoCAAIAAQnMHdVqAFMAAAAA.',
Sn='Snow:BAABLgAECn8eAAIjAAkJdyKRCgBXAgAjAAkJdyKRCgBXAgAAAA==.',
St='Strongtoast:BAAALgAECggJEgAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Su='Sugarworld:BAAALgAECgEJAQABLgAECgcJDAAKAAAAAA==.',
Sw='Swamperella:BAAALgAECgQJBgAAAA==.',
Sy='Syndra:BAAALgADCgkJEwAAAA==.',
['Sæ']='Sæstoo:BAAALgAECgYJBwAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECgIJAwAAAA==.',
Th='Thonor:BAABLgAECn8qAAIRAAgJuxaBPgDKAQARAAgJuxaBPgDKAQAAAA==.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAABLgAECn8aAAMHAAgJiw08EwDuAAAHAAcJ5Ao8EwDuAAAkAAMJpw1YOwCQAAAAAA==.',
To='Torí:BAABLgAECn8YAAIGAAkJZwmyowA5AQAGAAkJZwmyowA5AQAAAA==.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Va='Vaelandir:BAAALgAECgUJCwAAAA==.Vallkyr:BAABLgAECn8iAAIMAAkJ0x5ZIgB4AgAMAAkJ0x5ZIgB4AgAAAA==.Vanish:BAAALgAECgYJBgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAIYAAgJ7A77OQDHAQAYAAgJ7A77OQDHAQAAAA==.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgIJAwAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJEgAAAA==.',
Wh='Whitemage:BAAALgAECgcJAwAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAAALgAECgYJEAAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAAALgAECgcJEgAAAA==.Zitta:BAABLgAECn8eAAIEAAgJYhV8FwAEAgAEAAgJYhV8FwAEAgAAAA==.Zittav:BAABLgAECn8bAAMFAAkJbBlnGwA5AgAFAAkJbBlnGwA5AgAGAAYJix5rYgCMAQAAAA==.',
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
