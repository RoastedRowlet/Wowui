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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Hunter-Survival','Paladin-Retribution','Priest-Discipline','Shaman-Restoration','DemonHunter-Devourer','Mage-Frost','Monk-Mistweaver','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Druid-Feral','Paladin-Holy','Paladin-Protection','Shaman-Elemental','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Unknown-Unknown','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAAALgAECggJDgAAAA==.',
An='Andeys:BAAALgAECggJDwAAAA==.Angelius:BAABLgAFFH8FAAIBAAMJrA0aJgC0AAABAAMJrA0aJgC0AAAAAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHgACAJkTAA==.',
Ba='Badgirl:BAAALgAECgQJBAAAAA==.Baggigy:BAACLgAFFH8JAAMDAAMJehFTFQDWAAADAAMJehFTFQDWAAAEAAIJUwYD8gB2AAAuAAQKfyEABAMACAmEHysWACUBAAQABgnUHHGZADQBAAMAAwlWISsWACUBAAUABAlABOBIAGcAAAAA.Balance:BAABLgAFFH8IAAMGAAMJcA/6QQClAAAGAAMJcA/6QQClAAAHAAEJjgcuQAApAAAAAA==.Bandwagon:BAAALgAECgUJBQAAAA==.',
Be='Bentpanda:BAABLgAECn8YAAIIAAkJaBZnEwAMAgAIAAkJaBZnEwAMAgAAAA==.',
Bh='Bhain:BAABLgAFFH8QAAIJAAUJfB57KgBcAQAJAAUJfB57KgBcAQAAAA==.',
Bi='Bigcocko:BAACLgAFFH8hAAIGAAgJ3h2pAwDiAgAGAAgJ3h2pAwDiAgAuAAQKfy4AAgYACQmGJYkCAHIDAAYACQmGJYkCAHIDAAAA.Bigwheels:BAAALgAECgMJAwAAAA==.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAFFAMJCQADAHoRAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECgYJCQAAAA==.',
Br='Brogh:BAABLgAECn8eAAIKAAkJcRQaEQBfAgAKAAkJcRQaEQBfAgAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAILAAkJ/AwuOQCdAQALAAkJ/AwuOQCdAQAAAA==.',
Ca='Camouflage:BAABLgAECn9AAAIIAAkJBCWlAgAbAwAIAAkJBCWlAgAbAwAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBQAJAAcVAA==.Chilyn:BAAALgAECgUJEgAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8cAAIMAAYJEw5GnwDgAAAMAAYJEw5GnwDgAAAAAA==.Corrupthell:BAABLgAECn8WAAIEAAcJHhANhwBTAQAEAAcJHhANhwBTAQAAAA==.Cowi:BAABLgAECn8WAAILAAYJ+g4EYgAwAQALAAYJ+g4EYgAwAQABLgAFFAIJBQANAF4OAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAACLgAFFH8FAAINAAMJXgmYjgC9AAANAAMJXgmYjgC9AAAuAAQKfxgAAg0ACAlKGilcACUCAA0ACAlKGilcACUCAAAA.Daswassap:BAAALgAECgYJCgAAAA==.',
De='Def:BAAALgAECgIJBgAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8eAAQCAAkJmRMYMACVAQACAAcJexMYMACVAQABAAUJOhb6OwAsAQAOAAIJrBz2lwBeAAAAAA==.Driver:BAACLgAFFH8PAAMPAAUJtgv8RgA1AQAPAAUJtgv8RgA1AQAQAAIJ3QbeEACDAAAuAAQKfzUAAw8ACAniHvMZALkCAA8ACAniHvMZALkCABEABgniGNEUAKQBAAAA.',
['Dä']='Däenerys:BAAALgAECgkJEQAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAgJEwAMABEfAA==.',
Ex='Exemplio:BAABLgAECn8lAAICAAkJmCTKAwAPAwACAAkJmCTKAwAPAwAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHgACAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fr='Frahmunda:BAAALgAECgIJBAAAAA==.Frosty:BAABLgAECn8UAAINAAcJzw3UqACIAQANAAcJzw3UqACIAQAAAA==.Frybeam:BAAALgAECgIJAwAAAA==.',
Gi='Gilfoyle:BAAALgAECgIJBwAAAA==.Giovahni:BAACLgAFFH8RAAIMAAYJhxLZLgBiAQAMAAYJhxLZLgBiAQAuAAQKfzEAAgwACAnXHyQfAFcCAAwACAnXHyQfAFcCAAAA.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAINAAcJsAVXyABYAQANAAcJsAVXyABYAQAAAA==.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8cAAISAAgJ3hPROgBZAQASAAgJ3hPROgBZAQAAAA==.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAwAAAA==.Janaria:BAABLgAFFH8KAAITAAMJER6XHAADAQATAAMJER6XHAADAQAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJBAAAAA==.Jessiescool:BAABLgAECn8aAAIJAAYJNQ7SlwBOAQAJAAYJNQ7SlwBOAQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIHAAkJMw4wEAB1AQAHAAkJMw4wEAB1AQAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Joyluka:BAACLgAFFH8PAAIJAAMJjxz3UQAGAQAJAAMJjxz3UQAGAQAuAAQKfxsAAgkABwmLJH8mAGgCAAkABwmLJH8mAGgCAAAA.',
Ka='Kalvin:BAABLgAECn8dAAIUAAgJiA4FJQBqAQAUAAgJiA4FJQBqAQAAAA==.Kanari:BAABLgAECn8jAAQVAAgJNhIaMwA2AQAVAAcJlRMaMwA2AQAKAAUJxgk3RwDnAAAWAAcJKQcQVgC3AAAAAA==.',
Ke='Kelak:BAAALgADCgEJAgAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgIJBgAAAA==.',
La='Lagoles:BAACLgAFFH8GAAIIAAMJIxEHJwCXAAAIAAMJIxEHJwCXAAAuAAQKfzoAAwgACQkuIz8DAAUDAAgACQmcIj8DAAUDABcACAl9H5oTAJgCAAEuAAUUAwkIAA0AvRYA.Lance:BAAALgAECgUJBQAAAA==.Landis:BAAALgAECgUJEAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJQAAIAAQlAA==.Leoben:BAAALgAECgEJBAAAAA==.',
Li='Liltracey:BAAALgAFFAIJAwABLgAFFAMJCAAGAHAPAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAHADMOAA==.',
Mi='Miggles:BAACLgAFFH8QAAIGAAMJRRLOPAC3AAAGAAMJRRLOPAC3AAAuAAQKfzEAAwYACQk5IL0KAA4DAAYACQk5IL0KAA4DABgAAglmDk1sAG8AAAAA.Milo:BAABLgAFFH8JAAIZAAMJbhn0CwDvAAAZAAMJbhn0CwDvAAAAAA==.',
Mk='Mk:BAEBLgAECn9BAAQBAAkJgCAfBgAfAwABAAgJiCMfBgAfAwACAAUJpgk9VwCoAAAOAAEJiAfMvwAlAAAAAA==.',
Mo='Monzo:BAABLgAECn8kAAMEAAgJ2iEEGQDmAgAEAAgJ2iEEGQDmAgAFAAIJ1A+SPQBcAAABLgAFFAMJCAAGAHAPAA==.Morgane:BAAALgAECgcJCAAAAA==.Morvayne:BAACLgAFFH8IAAINAAMJvRbVegDoAAANAAMJvRbVegDoAAAuAAQKfz4AAg0ACQmqINgQAPQCAA0ACQmqINgQAPQCAAAA.',
My='Myneemo:BAABLgAECn8VAAINAAgJZReXTADzAQANAAgJZReXTADzAQAAAA==.Myro:BAABLgAECn8iAAIJAAgJ3QpglABIAQAJAAgJ3QpglABIAQAAAA==.',
No='Nomoneydown:BAAALgAECgIJBgAAAA==.Nosam:BAABLgAECn8hAAIPAAcJwhP7ZgBvAQAPAAcJwhP7ZgBvAQAAAA==.',
Nt='Nthegreat:BAAALgAECggJDAAAAA==.',
Nw='Nwf:BAABLgAECn8aAAISAAgJHRkLJwDAAQASAAgJHRkLJwDAAQAAAA==.',
['Nè']='Nèbula:BAABLgAECn8oAAQaAAgJYxm6FgBTAgAaAAgJYxm6FgBTAgAbAAYJ7Q75JQDiAAAJAAEJdAcnrAEoAAAAAA==.',
Or='Ornatas:BAACLgAFFH8NAAIcAAUJMiEEGQBKAQAcAAUJMiEEGQBKAQAuAAQKfxgAAhwACAm0HJYVAG8CABwACAm0HJYVAG8CAAAA.',
Pa='Pandamonium:BAABLgAECn8dAAQOAAgJPxT8KwBWAQAOAAgJPxT8KwBWAQACAAQJ+AOrbQBnAAABAAEJOAkhsAAkAAAAAA==.',
Pe='Perdyblues:BAACLgAFFH8GAAIPAAMJgwJ3kgCXAAAPAAMJgwJ3kgCXAAAuAAQKfxcAAg8ACAnTBh+OAB4BAA8ACAnTBh+OAB4BAAAA.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgAECgYJEQAAAA==.',
Qi='Qiana:BAABLgAECn8dAAIaAAcJvhPuLQCjAQAaAAcJvhPuLQCjAQAAAA==.',
Qu='Quickstabbin:BAABLgAECn8bAAIBAAgJCQxSRgDjAAABAAgJCQxSRgDjAAAAAA==.Quinoaffle:BAAALgAECgEJAQABLgAFFAMJBQAPAEkPAA==.',
Ra='Rainootra:BAAALgAECgcJCgAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHgACAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAABLgAECn8eAAMNAAkJKhClWgDKAQANAAkJ4w+lWgDKAQAdAAcJGQnzDQCTAAAAAA==.',
Sc='Scylla:BAACLgAFFH8SAAIeAAcJvx0uAQBCAgAeAAcJvx0uAQBCAgAuAAQKfywAAx4ACQkAJh8AAOUDAB4ACQkAJh8AAOUDAB8AAQmlDkVeAEIAAAEuAAQKBgkPACAAAAAA.',
Se='Sephiroth:BAABLgAECn8VAAIJAAkJDhSIQgAdAgAJAAkJDhSIQgAdAgAAAA==.Serephant:BAAALgADCgEJAgAAAA==.',
Si='Siegeshock:BAAALgADCgUJBQABLgAECgQJDQAgAAAAAA==.Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAFFAEJAQABLgAECgkJQAAIAAQlAA==.',
So='Soothe:BAABLgAECn8XAAIVAAYJgxmNJACbAQAVAAYJgxmNJACbAQAAAA==.',
St='Stormride:BAAALgAECgIJAwAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8lAAMJAAgJxiGFJABxAgAJAAgJxiGFJABxAgAaAAEJlwMdkAAsAAAAAA==.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJAwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8VAAISAAQJlhyzEwBnAQASAAQJlhyzEwBnAQAuAAQKfx8AAhIACAlEH5kTAFQCABIACAlEH5kTAFQCAAAA.',
Te='Tengoo:BAAALgAECgUJBQAAAA==.',
Th='Thewaitress:BAABLgAFFH8FAAIJAAIJBxV1kwCHAAAJAAIJBxV1kwCHAAAAAA==.Thylight:BAAALgAECgUJBgAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ty='Tysotcan:BAAALgAECgEJAQAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgIJBwAAAA==.',
Ve='Veew:BAABLgAECn8XAAMSAAgJ8RGROgC8AQASAAgJOhGROgC8AQATAAUJshEKGwAZAQAAAA==.',
Vy='Vynaca:BAAALgAECgIJBwAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8pAAIhAAgJTQyhaQBqAQAhAAgJTQyhaQBqAQAAAA==.',
Wo='Wontan:BAAALgAECgcJCAAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Xa='Xania:BAAALgAECgIJBwAAAA==.',
Yu='Yungmage:BAABLgAECn8dAAINAAcJYBuQggDMAQANAAcJYBuQggDMAQAAAA==.',
Za='Zaifu:BAAALgAECgIJBwAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAINAAkJABhSRQBoAgANAAkJABhSRQBoAgAAAA==.',
['Èl']='Èlfman:BAABLgAECn8VAAIGAAcJJhh1NADIAQAGAAcJJhh1NADIAQAAAA==.',
['Øm']='Ømega:BAAALgAECgEJAQAAAA==.',
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
