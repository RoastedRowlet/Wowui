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

local lookup = {'Druid-Restoration','Druid-Balance','Monk-Mistweaver','Evoker-Augmentation','Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Mage-Frost','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Priest-Discipline','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Monk-Brewmaster','DeathKnight-Blood','Monk-Windwalker','Warrior-Fury','Druid-Guardian','DeathKnight-Frost','DemonHunter-Devourer','Priest-Shadow','Mage-Fire','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','Rogue-Assassination','DemonHunter-Vengeance','Shaman-Enhancement','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-06-06',data={Ac='Aconite:BAAALgAECgYJCQAAAA==.',
Ad='Adhoria:BAAALgAECgEJAgAAAA==.Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8mAAMBAAcJrhqTDwDtAQABAAYJexqTDwDtAQACAAUJCB+qFwBFAQAuAAQKfzMAAwIACQnQI5QQAJsCAAIACAncJJQQAJsCAAEACQmgHU8jAC8CAAAA.',
Ai='Ailuria:BAABLgAECn8yAAIDAAkJIiT5AgCIAwADAAkJIiT5AgCIAwAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgAECgIJAgAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIEAAgJzA1QIwCjAQAEAAgJzA1QIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Alikith:BAABLgAECn84AAQGAAkJJBXnCgANAgAGAAkJJBXnCgANAgAHAAMJgAhYGAGMAAAIAAEJyRLOgwA4AAAAAA==.Alkaline:BAAALgADCggJDAAAAA==.Altheyra:BAAALgAECgYJCgAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrìel:BAABLgAECn9AAAIJAAkJuhA4SwDzAQAJAAkJuhA4SwDzAQAAAA==.Amelía:BAAALgAECgYJBgABLgAFFAQJEwABAMoJAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8TAAMBAAQJygnZNADWAAABAAQJygnZNADWAAACAAIJwwLOFwB5AAAuAAQKfyEAAwEACQn1FygqAPsBAAEACQn1FygqAPsBAAIAAQlOHc52AE0AAAAA.',
An='Angando:BAABLgAECn8mAAIKAAkJWxMHEgC8AQAKAAkJWxMHEgC8AQAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Anneliesë:BAAALgADCgUJFAAAAA==.',
Ao='Aozora:BAABLgAECn8dAAICAAgJzBDtKgBvAQACAAgJzBDtKgBvAQAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Ariellá:BAAALgAECgQJBAAAAA==.Arrows:BAAALgADCgcJBwAAAA==.Artemidoros:BAABLgAECn8vAAQLAAkJTyAmBgC6AgALAAkJfB8mBgC6AgAMAAYJGiEVIQA/AgANAAEJngr/igAwAAAAAA==.Artishard:BAAALgADCgMJAwAAAA==.',
As='Ashkaari:BAACLgAFFH8VAAIOAAUJCBCcKAAqAQAOAAUJCBCcKAAqAQAuAAQKfxsAAg4ACQnUHAAUAJ8CAA4ACQnUHAAUAJ8CAAAA.Asuná:BAABLgAECn8fAAMPAAkJchESGQD7AQAPAAkJJhASGQD7AQAQAAYJVQoVRwAdAQAAAA==.',
Au='Aurelyus:BAAALgAECgMJBAAAAA==.Aurevior:BAAALgAECgYJDgAAAA==.Ausuna:BAAALgAECgUJCgAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaderr:BAAALgAECgYJCwAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgIJAgABLgAFFAcJJgABAK4aAA==.',
Ba='Backerrz:BAACLgAFFH8iAAIRAAcJkw4PIACqAQARAAcJkw4PIACqAQAuAAQKfzEAAxEACQlPHE0YAIwCABEACQlPHE0YAIwCABIAAwlAGS45ANAAAAAA.Bamberk:BAAALgADCgMJAwABLgAECgcJJQARAK4eAA==.',
Be='Bearbrownie:BAAALgAECgEJAQAAAA==.Bearwidit:BAAALgAECgYJCQAAAA==.Beefbrownie:BAABLgAECn8qAAIKAAkJ0yPYAQAxAwAKAAkJ0yPYAQAxAwAAAA==.Bellezora:BAAALgAECgUJBQABLgAECgkJIAABAFcTAA==.Berz:BAAALgAECgYJCwAAAA==.Berzerked:BAACLgAFFH8IAAITAAQJOBzeDwBJAQATAAQJOBzeDwBJAQAuAAQKfy8AAhMACQltI6wBACcDABMACQltI6wBACcDAAAA.Bestboygrip:BAAALgAECgcJEwAAAA==.Betelgues:BAAALgAECgEJAQAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAABLgAECn8WAAMDAAcJKhqaMQCbAQADAAcJKhqaMQCbAQAUAAYJiAe/TQDBAAAAAA==.Bigjonkillzz:BAAALgADCgEJAQAAAA==.Bigsave:BAABLgAECn8dAAIBAAkJCA8ZTgBMAQABAAkJCA8ZTgBMAQAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blindem:BAAALgADCgEJAQABLgAECgkJJgABAA8lAA==.Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8bAAIVAAUJ5BrPFAAuAQAVAAUJ5BrPFAAuAQAuAAQKf0QAAhUACQldIJ8IAIMCABUACQldIJ8IAIMCAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAABLgAECn82AAMDAAkJFBqMDwCYAgADAAkJFBqMDwCYAgAWAAEJ1xYshQBDAAAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAABLgAECn8VAAIXAAYJ5xp6LQCUAQAXAAYJ5xp6LQCUAQAAAA==.',
Bu='Buckett:BAAALgAECgUJBQAAAA==.Buckfuttz:BAAALgAECggJEgAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH87AAIUAAYJkyZMAACAAgAUAAYJkyZMAACAAgAuAAQKfxcAAhQACQlfJngAANkDABQACQlfJngAANkDAAEuAAUUCQkcABgA/yMA.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAABLgAECn8rAAIKAAgJNBnCDgDwAQAKAAgJNBnCDgDwAQAAAA==.',
Ch='Chainmalejr:BAAALgAECgYJBgABLgAFFAQJGAAJABcaAA==.Chelseyb:BAAALgADCgcJBwAAAA==.Chirón:BAABLgAECn8UAAIZAAcJ+QzNEwAxAQAZAAcJ+QzNEwAxAQAAAA==.Chiyukii:BAAALgAECgkJAQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQABLgAECgkJKgAGAL0cAA==.',
Co='Colorss:BAAALgADCgEJAQAAAA==.Connie:BAABLgAECn8oAAIMAAkJrxzMJABEAgAMAAkJrxzMJABEAgAAAA==.Cowmein:BAABLgAECn8XAAMCAAcJSQzIQQD4AAACAAcJSQzIQQD4AAABAAEJ4AQj4AAkAAAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crune:BAAALgAECgEJAQAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAABLgAECn8aAAIaAAcJ9RngQQC2AQAaAAcJ9RngQQC2AQAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAYJLAAbAIUcAA==.',
Da='Dameian:BAAALgAECgEJAQAAAA==.Dapur:BAAALgADCgkJEgAAAA==.Davidmamet:BAAALgADCgIJAwAAAA==.Dayne:BAABLgAECn8fAAIUAAkJ+A6gIACaAQAUAAkJ+A6gIACaAQAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAFFAQJGAAJABcaAA==.',
De='Demontot:BAAALgADCgkJCgAAAA==.Deäthknight:BAAALgAECgEJAQAAAA==.',
Dh='Dheginsea:BAAALgAECgYJBgAAAA==.',
Di='Dillexis:BAACLgAFFH8ZAAIXAAUJmxytEgBgAQAXAAUJmxytEgBgAQAuAAQKfyEAAhcACQnXGfYbAAcCABcACQnXGfYbAAcCAAAA.Dipindots:BAAALgADCgEJAQAAAA==.Divinemark:BAAALgAECgYJCQAAAA==.',
Do='Donald:BAABLgAECn9QAAMCAAkJQRnFDwBYAgACAAkJQRnFDwBYAgABAAMJiwdCpwB5AAAAAA==.Doublea:BAAALgAECggJEwAAAA==.',
Dr='Dragonchest:BAAALgAECgYJCQAAAA==.Dragonista:BAAALgAECgEJAgAAAA==.Dragonswolf:BAABLgAECn8uAAIXAAgJtRWFJwC3AQAXAAgJtRWFJwC3AQAAAA==.Dragonwing:BAAALgAECgEJAgAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAAALgAECgYJDAAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAcJJgADAOUkAA==.Dregon:BAACLgAFFH8mAAIDAAcJ5STqAgDlAgADAAcJ5STqAgDlAgAuAAQKfy0AAwMACQkwJmACAGYDAAMACQkwJmACAGYDABYAAgnlIalaAKUAAAAA.Dreinara:BAAALgAECgcJEAAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Duff:BAAALgADCggJCQAAAA==.Dummysezwhut:BAABLgAECn8rAAICAAgJxRKzIwCfAQACAAgJxRKzIwCfAQAAAA==.',
Ea='Earthborn:BAAALgAECgcJAQAAAA==.',
Ei='Eilyn:BAABLgAECn9AAAIHAAgJIxX9UwDDAQAHAAgJIxX9UwDDAQAAAA==.',
El='Elena:BAAALgAECgQJBgABLgAECgkJMgADACIkAA==.Elesis:BAAALgADCgQJBAAAAA==.Ellida:BAABLgAECn8aAAIbAAcJMxGQIwC7AQAbAAcJMxGQIwC7AQAAAA==.',
Em='Emastoned:BAAALgAECgYJEAAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAABLgAECn8iAAMSAAkJPR7kAwA+AgASAAgJIB/kAwA+AgARAAgJBhpHQADWAQAAAA==.',
Fa='Fangmage:BAABLgAECn8UAAMcAAcJbQ9IBwAZAQAcAAYJhRBIBwAZAQAJAAYJ2wjjyAD3AAAAAA==.Fayker:BAAALgAECggJDQAAAA==.Fazlain:BAABLgAECn8jAAIMAAgJLB6pKgAoAgAMAAgJLB6pKgAoAgAAAA==.',
Fe='Feldraca:BAAALgAECgEJAQAAAA==.Felestis:BAAALgAECgYJCQAAAA==.Felnir:BAAALgAECgMJBAABLgAECgkJGQARALsJAA==.',
Fi='Fighter:BAAALgADCgEJAQABLgAFFAUJGQAPAHoUAA==.',
Fl='Fluffydragon:BAACLgAFFH8OAAIdAAQJkRVmFgAYAQAdAAQJkRVmFgAYAQAuAAQKfyYAAx0ACQkkHOAEAMkCAB0ACQkkHOAEAMkCAB4ABQnnB2QoAN0AAAAA.',
Fr='Friartuck:BAAALgAECgkJEgABLgAFFAMJCwAMACIdAA==.Frosteez:BAAALgAECgEJAQABLgAECgYJEwAFAAAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgAECgEJAQAAAA==.Furryem:BAABLgAECn8mAAMBAAkJDyWNAQC+AwABAAkJDyWNAQC+AwAfAAMJGyIVGgArAQAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
Ga='Galaena:BAAALgAECgcJBwAAAA==.Ganden:BAABLgAECn8zAAICAAkJix27CQCvAgACAAkJix27CQCvAgAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAACLgAFFH8MAAIHAAQJQxLCPQAhAQAHAAQJQxLCPQAhAQAuAAQKfzoAAgcACAkcGwNEAO8BAAcACAkcGwNEAO8BAAAA.Gatelinka:BAAALgAECgcJEQABLgAFFAQJDgAdAJEVAA==.Gateto:BAABLgAECn8sAAMOAAgJXiHnCQDaAgAOAAgJXiHnCQDaAgAgAAQJiBATWQDJAAABLgAFFAQJDgAdAJEVAA==.',
Ge='Genfindel:BAAALgADCgYJBgAAAA==.Getinthevan:BAAALgADCgcJBwAAAA==.',
Gi='Gidden:BAAALgAECgYJDAAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Gn='Gnomechomsky:BAAALgADCggJDAAAAA==.',
Go='Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgkJDgAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.Grindcore:BAAALgAECgUJCAAAAA==.',
Gw='Gwenneth:BAAALgAECgMJAwAAAA==.',
['Gú']='Gúr:BAAALgADCgkJGwAAAA==.',
Ha='Halfordin:BAAALgADCgYJBgAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Healthat:BAAALgAECgEJAgAAAA==.Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8pAAISAAkJ1hRDBgDxAQASAAkJ1hRDBgDxAQAAAA==.Helsreach:BAAALgAECgEJAQAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.',
Hr='Hrungnir:BAAALgAECgQJBgAAAA==.Hruoth:BAAALgAECgEJAQAAAA==.',
Hu='Hunt:BAABLgAECn8YAAMMAAYJ1RegfAA4AQAMAAYJNBegfAA4AQANAAQJsw3cXQDKAAAAAA==.Huntinbub:BAABLgAECn8+AAMMAAgJGRGxUgCeAQAMAAgJGRGxUgCeAQANAAEJzQAxmgAZAAAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgkJBAAAAA==.',
In='Instaque:BAAALgAECgQJBAAAAA==.',
Ir='Irim:BAAALgAFFAIJAgAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgAECggJDwABLgAFFAUJGQAXAJscAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAFAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8WAAIaAAUJahclPgAcAQAaAAUJahclPgAcAQAuAAQKfyQAAxoACAmYIeARAPACABoACAmYIeARAPACACEAAglECPthAFoAAAAA.Izlaar:BAAALgAECgMJAwAAAA==.Izzytt:BAAALgAECgUJCQAAAA==.',
Ja='Jacenskie:BAABLgAECn8jAAIXAAkJbBLVLwCIAQAXAAkJbBLVLwCIAQAAAA==.Jacob:BAAALgAECgQJCwAAAA==.Jadedbabe:BAAALgAECgUJBwAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.Jexter:BAAALgADCgIJAgAAAA==.',
Ji='Jimmyjams:BAAALgAECgYJBwABLgAFFAQJGAAJABcaAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Joppa:BAAALgAECgIJAgABLgAFFAcJGgAbALAaAA==.Joyvimon:BAAALgAECgYJDwAAAA==.',
Ju='Jugernaut:BAAALgAECgYJBgAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8aAAIiAAgJdwsbiwBFAQAiAAgJdwsbiwBFAQAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAFAAAAAA==.',
Kh='Khal:BAACLgAFFH8VAAMEAAYJyxuHCQBYAQAEAAYJyxuHCQBYAQAeAAIJEgemBgClAAAuAAQKfxUAAx4ACQkBIL4OAO8BAAQABwmCGvgXABMCAB4ABgnGI74OAO8BAAAA.Khornedaemon:BAAALgAECgQJBQAAAA==.',
Ki='Kickstarter:BAAALgAFFAIJAwAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kilysta:BAAALgAECgEJAQAAAA==.Kiy:BAAALgAECggJEAAAAA==.',
Kn='Knìghtmare:BAAALgADCgcJEwAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAABLgAECn8aAAIRAAgJxAMNqADsAAARAAgJxAMNqADsAAAAAA==.Kronas:BAAALgAECgcJDgAAAA==.',
Ku='Kurosaki:BAABLgAECn8ZAAIaAAkJfxu3PAABAgAaAAkJfxu3PAABAgAAAA==.',
La='Lazyheal:BAACLgAFFH8ZAAQPAAUJehRiGgBqAQAPAAUJ5hJiGgBqAQAQAAIJVhSpDACZAAAbAAIJfAB/OwAzAAAuAAQKfx8ABBAACQl+G78MAIwCABAACQl+G78MAIwCAA8ABAlUBrE/ALEAABsAAgkgBi5YAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAUJGQAPAHoUAA==.',
Le='Leetsteve:BAAALgADCgYJCwAAAA==.Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8mAAIQAAcJ/RqPBAACAgAQAAcJ/RqPBAACAgAuAAQKfzQAAxAACQnOIKYDAB8DABAACQnOIKYDAB8DABsAAwktC2FpAGUAAAAA.Leomoon:BAAALgAECgMJCAAAAA==.Leshy:BAAALgAECgYJDAAAAA==.Levite:BAABLgAECn8eAAMQAAYJqxtsHgDCAQAQAAYJqxtsHgDCAQAPAAUJGhKYOwASAQAAAA==.',
Li='Lickytung:BAAALgADCgcJBwAAAA==.Lightwork:BAAALgAECgEJAQAAAA==.Lilara:BAABLgAECn8ZAAIRAAgJzAfbhAArAQARAAgJzAfbhAArAQAAAA==.Linthsong:BAAALgAECgUJBQABLgAECgkJFgAQAOMOAA==.Lionknite:BAACLgAFFH8KAAIiAAQJtQyZaQAdAQAiAAQJtQyZaQAdAQAuAAQKfy0AAiIACQnqG38uADwCACIACQnqG38uADwCAAAA.Lionshame:BAAALgAECgUJBQAAAA==.Liontabu:BAAALgAECgQJBgAAAA==.Liorii:BAAALgAECgEJAgAAAA==.Liteshocklet:BAAALgAECgEJAgABLgAFFAUJGQAPAHoUAA==.Littledung:BAAALgADCgkJEAAAAA==.',
Lo='Looting:BAABLgAECn8mAAIjAAgJMxTlBwDLAQAjAAgJMxTlBwDLAQAAAA==.Loving:BAAALgAECgEJAQAAAA==.',
Lu='Lucky:BAAALgAECgEJAQAAAA==.Lunexiya:BAABLgAECn8ZAAIaAAkJJgKa1wBxAAAaAAkJJgKa1wBxAAAAAA==.Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAACLgAFFH8JAAIBAAMJgwhhRACeAAABAAMJgwhhRACeAAAuAAQKfyEAAwEACAnuCwhdADsBAAEACAnuCwhdADsBAB8AAQkoAm5aABwAAAAA.',
Ma='Mageko:BAAALgAECgEJBgAAAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAFAAAAAA==.Makarion:BAABLgAECn8WAAIMAAgJxQuPcQBRAQAMAAgJxQuPcQBRAQAAAA==.Malvina:BAAALgAFFAEJAQAAAA==.Maoli:BAABLgAECn8UAAMHAAQJLhXj8gC5AAAHAAMJGhXj8gC5AAAIAAQJHgsyZACWAAAAAA==.Marcelius:BAAALgAECgEJAgAAAA==.Marohen:BAAALgADCgYJBgAAAA==.Matsumoto:BAAALgAECgEJAwAAAA==.Mauka:BAABLgAECn8tAAMBAAgJUg3oQwB3AQABAAgJUg3oQwB3AQACAAYJQBTdOABUAQAAAA==.Mauzer:BAAALgAECgEJAgABLgAECggJNQAhAKAcAA==.',
Mc='Mcfallen:BAAALgAECgIJAgAAAA==.Mcksquizy:BAABLgAECn8nAAIiAAkJUh4UMAB3AgAiAAkJUh4UMAB3AgAAAA==.Mclinkdink:BAAALgADCgkJCQAAAA==.Mcscrotie:BAABLgAECn8UAAIiAAgJQgYtqwASAQAiAAgJQgYtqwASAQAAAA==.',
Me='Mes:BAABLgAECn8jAAIgAAkJghv5GQAEAgAgAAkJghv5GQAEAgAAAA==.Metatrøn:BAAALgADCgkJCgAAAA==.',
Mi='Mimmi:BAAALgAECgUJEwABLgAECggJNQAhAKAcAA==.Mishri:BAACLgAFFH8QAAIaAAQJICLsIgCIAQAaAAQJICLsIgCIAQAuAAQKfzQAAhoACQn2JOwDAEADABoACQn2JOwDAEADAAAA.',
Mo='Monbonestorm:BAAALgAFFAIJAgABLgAECggJGQAaAIgUAA==.Mooittooit:BAAALgAECgYJBwAAAA==.Moonsorrow:BAAALgADCgMJAwAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAABLgAECn81AAMhAAgJoBzMDQA3AgAhAAgJoBzMDQA3AgAkAAIJ8RmbLQBBAAAAAA==.',
My='Mykana:BAABLgAECn8XAAMHAAYJPwiZ8gC6AAAHAAYJPwiZ8gC6AAAGAAQJ0wIuNgBrAAAAAA==.Myodieboy:BAAALgAECgIJAgAAAA==.Mywifesaidno:BAAALgADCggJCAAAAA==.',
Na='Nakabeam:BAABLgAECn8uAAIaAAkJIhbOMQD0AQAaAAkJIhbOMQD0AQAAAA==.Nakatwin:BAABLgAECn8YAAIaAAcJJhXmWACXAQAaAAcJJhXmWACXAQABLgAECgkJLgAaACIWAA==.Naklek:BAABLgAECn8hAAMfAAgJBh6TBgCOAgAfAAgJBh6TBgCOAgAYAAEJYgtiNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAFAAAAAA==.',
Ni='Nicked:BAECLgAFFH8VAAIMAAYJuhfTFwCQAQAMAAYJuhfTFwCQAQAuAAQKfyMAAwwACQmtH5sOAMYCAAwACQmtH5sOAMYCAA0ABAl0BlRpAJkAAAAA.Nika:BAAALgAECgYJCgAAAA==.Niraleth:BAAALgAECgMJAwAAAA==.Nistik:BAABLgAECn8oAAMQAAkJmAmoLABYAQAQAAkJmAmoLABYAQAbAAEJ0wHeawAaAAAAAA==.',
No='Noriala:BAAALgAECgYJCAABLgAECgkJMwAJAC0kAA==.Nozomí:BAAALgAECgUJBQAAAA==.',
Ob='Obergefel:BAAALgADCgEJAQAAAA==.',
Op='Ophiuchus:BAABLgAECn8ZAAIRAAkJuwkXXwB+AQARAAkJuwkXXwB+AQAAAA==.',
Or='Orcdung:BAAALgADCgYJBgAAAA==.',
Os='Ostpeppar:BAAALgADCgUJCwAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAABLgAECn8XAAQIAAgJ7xQpNQBxAQAIAAcJeRQpNQBxAQAGAAgJeA/0HgARAQAHAAEJcwN7rwEgAAABLgAECgkJIAAUADAWAA==.Pamelina:BAAALgADCgUJFAAAAA==.Pandaexpress:BAAALgAECgYJBgABLgAFFAUJGQAXAJscAA==.Panzerfäust:BAAALgAECgYJEwAAAA==.Pawrina:BAAALgAFFAEJAQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgADCgMJAwAAAA==.Pestis:BAAALgAECgQJBAAAAA==.Pewpewbambam:BAAALgAECgUJBQAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAABLgAECn8uAAMHAAkJwBanPQADAgAHAAkJwBanPQADAgAIAAQJzggsYgCeAAAAAA==.Philster:BAAALgAFFAIJBAAAAA==.',
Pi='Pilfering:BAAALgADCgQJBAAAAA==.',
Pl='Plumpt:BAAALgAECgcJEwAAAA==.',
Po='Poochieboo:BAAALgADCgQJBAAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAABLgAECn8jAAIQAAkJRRUuFwAIAgAQAAkJRRUuFwAIAgAAAA==.Punchem:BAAALgADCgcJBwABLgAECgkJJgABAA8lAA==.Purex:BAABLgAECn8dAAIjAAkJKQYwCgCSAQAjAAkJKQYwCgCSAQAAAA==.',
Py='Pylonshots:BAAALgAECgYJBgAAAA==.Pyria:BAAALgADCgUJCAAAAA==.',
['Pé']='Pérrywinklé:BAAALgAECgcJAQAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAABLgAECn8UAAIGAAgJ4BoeDQDlAQAGAAgJ4BoeDQDlAQAAAA==.Rathus:BAABLgAECn8lAAIRAAcJrh5+NAABAgARAAcJrh5+NAABAgAAAA==.Rawdata:BAACLgAFFH8OAAMlAAMJXQnnDQDKAAAlAAMJXQnnDQDKAAAOAAMJwApbUgCaAAAuAAQKfykAAyUACQk5FQAQAKQBACUACQk5FQAQAKQBAA4ACAkvD1RCAHgBAAAA.Razenka:BAAALgAECgIJAgAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8gAAIMAAgJqRetPQC4AQAMAAgJqRetPQC4AQABLgAECgkJJAAIADwdAA==.Rebeka:BAABLgAECn8kAAIIAAkJPB1xBwAMAwAIAAkJPB1xBwAMAwAAAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgcJEQABLgAECgkJHwAUAPgOAA==.Reniel:BAAALgAECgUJBgABLgAECgkJOAAGACQVAA==.Ressie:BAAALgAECgQJCQAAAA==.Reston:BAAALgAECgYJBgABLgAECgkJNAADAL4jAA==.Reverendlion:BAABLgAECn8WAAIbAAgJ7BYBHwDFAQAbAAgJ7BYBHwDFAQAAAA==.',
Ri='Riyu:BAAALgADCgEJAgAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.',
Ry='Ryblade:BAABLgAFFH8HAAIHAAMJ/AczbwDAAAAHAAMJ/AczbwDAAAAAAA==.',
Sa='Saiko:BAAALgAECgMJAwABLgAFFAUJFgAmAPMMAA==.Sainthealz:BAAALgAECgEJAQAAAA==.Saladcake:BAABLgAECn8nAAIJAAgJJRYaVwDRAQAJAAgJJRYaVwDRAQAAAA==.Salleane:BAACLgAFFH8JAAIHAAMJBRDlZADTAAAHAAMJBRDlZADTAAAuAAQKfxoAAgcACQmPFTNeAMkBAAcACQmPFTNeAMkBAAAA.Samgompers:BAAALgADCgIJAgAAAA==.Sampal:BAABLgAECn9CAAMGAAkJoBtsBwBbAgAGAAgJjx5sBwBbAgAHAAEJFAfchgEvAAAAAA==.Sampriest:BAABLgAECn8qAAMQAAgJsCCFCADWAgAQAAgJsCCFCADWAgAPAAEJpxBccAA0AAABLgAECgkJQgAGAKAbAA==.Samwield:BAECLgAFFH8eAAInAAUJDiLREQBpAQAnAAUJDiLREQBpAQAuAAQKfz4ABCcACQnHIUEFANcCACcACQnHIUEFANcCACMAAwlCGEsTAM0AACgAAQnUChEjAC8AAAAA.Sanchoe:BAAALgAFFAEJAQAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.Saucemoe:BAAALgAECgEJAQAAAA==.',
Se='Seireitei:BAABLgAECn80AAMOAAkJpRvoEgCqAgAOAAkJpRvoEgCqAgAgAAEJIAYSrwAiAAAAAA==.Selaheal:BAABLgAECn9AAAIbAAkJmBdaEgA5AgAbAAkJmBdaEgA5AgAAAA==.Seraath:BAACLgAFFH8jAAIkAAcJORh6AQCsAQAkAAcJORh6AQCsAQAuAAQKfyYAAyQACQn3IZAAAGQDACQACQn3IZAAAGQDABoAAQkAAJDSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.Serius:BAAALgAECgMJAwAAAA==.',
Sh='Shadowskull:BAAALgADCgkJFQAAAA==.Shadowydream:BAAALgAECgIJAgAAAA==.Shadwkllr:BAABLgAECn8VAAMgAAYJtw5QTAD0AAAgAAYJtw5QTAD0AAAOAAIJ3g6BrgBaAAAAAA==.Shamloo:BAAALgADCgEJAQAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAABLgAECn8XAAISAAYJQiB9BwDOAQASAAYJQiB9BwDOAQAAAA==.Shortie:BAAALgADCggJDwAAAA==.',
Si='Sinister:BAABLgAFFH8HAAIhAAQJ6xbFCwA4AQAhAAQJ6xbFCwA4AQAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skid:BAAALgADCgEJAQAAAA==.Skies:BAAALgAECgEJAgABLgAECgcJCAAFAAAAAA==.',
Sn='Sneakyhoof:BAAALgADCgcJBwAAAA==.Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgAECgYJDgAAAA==.',
Ss='Ssteroidss:BAAALgAECgEJAQAAAA==.',
St='Stabbem:BAAALgADCgEJAQABLgAECgkJJgABAA8lAA==.Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBQAAAA==.Stergertha:BAAALgAECgEJAQABLgAECgcJFAAgAG4XAA==.Stersèbuk:BAAALgADCgMJAwABLgAECgcJFAAgAG4XAA==.Stervana:BAACLgAFFH8KAAIEAAQJjxpxJQAjAQAEAAQJjxpxJQAjAQAuAAQKfy0AAgQACQl0IOIDAFoDAAQACQl0IOIDAFoDAAEuAAQKBwkUACAAbhcA.Sterzephyr:BAABLgAECn8UAAIgAAcJbhdwJAC2AQAgAAcJbhdwJAC2AQAAAA==.Stickytoes:BAAALgADCgYJBgAAAA==.Stilettoes:BAAALgADCgIJAgAAAA==.Stormyknight:BAABLgAECn8sAAMdAAkJ3g4QFQByAQAdAAkJ3g4QFQByAQAeAAcJOwtlEgDWAAAAAA==.',
Su='Sundemonhunt:BAAALgAECgMJAwAAAA==.Sunnmonk:BAAALgADCgQJBAAAAA==.Sunpally:BAAALgAECgYJBQAAAA==.Sunwrath:BAAALgAECgcJCAAAAA==.Susmonk:BAAALgAECgQJBQAAAA==.Suspectedd:BAABLgAFFH8KAAIJAAMJmxJkLwD5AAAJAAMJmxJkLwD5AAABLgAFFAcJJQAKAKckAA==.Suswar:BAACLgAFFH8lAAIKAAcJpyRWAgBUAgAKAAcJpyRWAgBUAgAuAAQKfzAAAgoACQnIJJoAALgDAAoACQnIJJoAALgDAAAA.Suvulaan:BAABLgAECn8+AAMdAAkJXAp1GQA2AQAdAAgJ7gd1GQA2AQAEAAkJKgS9RQAIAQAAAA==.',
Sw='Swifix:BAAALgAECgYJBgAAAA==.Swordsmyth:BAAALgADCgMJAwAAAA==.',
Ta='Tacostand:BAACLgAFFH8aAAIaAAYJKhWiKABsAQAaAAYJKhWiKABsAQAuAAQKfzIAAhoACQlNIOUHAEwDABoACQlNIOUHAEwDAAAA.Tamarlane:BAAALgADCgIJAgAAAA==.Tatoo:BAACLgAFFH8LAAIMAAMJIh0oSQAHAQAMAAMJIh0oSQAHAQAuAAQKfz4AAgwACQlNJFkEAEQDAAwACQlNJFkEAEQDAAAA.',
Te='Teeice:BAABLgAECn8iAAIjAAkJdRNpBgD6AQAjAAkJdRNpBgD6AQAAAA==.Teo:BAABLgAECn8jAAIbAAkJmxOEGgDqAQAbAAkJmxOEGgDqAQAAAA==.Terian:BAAALgAECgkJBwAAAA==.',
Th='Thaodan:BAABLgAECn8aAAIgAAkJAhEFNwBNAQAgAAkJAhEFNwBNAQAAAA==.Thekan:BAABLgAECn8bAAIhAAkJlhS9FADYAQAhAAkJlhS9FADYAQAAAA==.Theriot:BAACLgAFFH8GAAMHAAMJuRBnYQDYAAAHAAMJuRBnYQDYAAAGAAIJmAKJFABIAAAuAAQKfy8ABAcACQnbHZ42ABwCAAcACQnbHZ42ABwCAAYABgkIDNMnAMsAAAgAAQkzCEegACgAAAAA.Thianá:BAABLgAECn8ZAAIOAAgJlgvcTQBrAQAOAAgJlgvcTQBrAQAAAA==.Thüclides:BAAALgAECgcJAgAAAA==.',
Ti='Tiermoghuen:BAAALgAECgMJAwAAAA==.Tikidragoona:BAAALgAECgIJAgAAAA==.Timberdoodle:BAAALgAECgMJAwAAAA==.Timtamslam:BAAALgAECgYJDAAAAA==.Tinkerspell:BAABLgAECn8gAAIBAAkJVxNSLQDoAQABAAkJVxNSLQDoAQAAAA==.Tinkiebella:BAAALgAECgEJAgABLgAECgkJIAABAFcTAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
Tl='Tlitlitzin:BAAALgAECgQJBAAAAA==.',
To='Tobivoker:BAAALgAECgQJBQAAAA==.Toosus:BAABLgAFFH8PAAIVAAQJVSGZHQDoAAAVAAQJVSGZHQDoAAABLgAFFAcJJQAKAKckAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAACLgAFFH8HAAIlAAQJYQf3CgD6AAAlAAQJYQf3CgD6AAAuAAQKfxoAAiUACAkrFG0KACoCACUACAkrFG0KACoCAAAA.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgQJBwAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Totec:BAAALgAECgkJCgAAAA==.',
Tr='Treatimus:BAAALgADCgMJAwABLgAECgkJQgAbAAchAA==.Treesum:BAAALgADCgQJBAAAAA==.Trolldung:BAAALgAECgQJBAAAAA==.Truffaut:BAAALgAECgEJAQAAAA==.',
Tt='Tturtle:BAACLgAFFH8TAAIHAAUJKgmxLQBFAQAHAAUJKgmxLQBFAQAuAAQKfyUAAgcACQl+Fd8wAF8CAAcACQl+Fd8wAF8CAAAA.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Tw='Twoblock:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tystraz:BAAALgAECgYJCwAAAA==.',
Ud='Udúnnaur:BAAALgADCggJDgAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Unclebuck:BAAALgADCgQJBAAAAA==.Undermage:BAAALgADCgQJBAAAAA==.Unholysam:BAEALgAECgcJDwABLgAFFAUJHgAnAA4iAA==.',
Va='Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vecna:BAAALgAECgQJBgABLgAECgYJCAAFAAAAAA==.Vector:BAAALgAECgYJCAAAAA==.Velata:BAABLgAECn8cAAIJAAUJWw9M1QDkAAAJAAUJWw9M1QDkAAAAAA==.Velvethunda:BAAALgAECgYJBgAAAA==.Verdugo:BAAALgAECgUJDwAAAA==.Verite:BAABLgAECn8bAAMiAAcJzQPxBgGUAAAiAAcJxwLxBgGUAAAZAAMJOgUEFABTAAAAAA==.',
Vi='Vicar:BAAALgADCggJDgAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAABLgAECn8jAAIXAAkJ9RsBEgBeAgAXAAkJ9RsBEgBeAgAAAA==.',
Vo='Vodka:BAAALgADCgcJFQAAAA==.Voelva:BAAALgAECgEJAgAAAA==.Voidedge:BAABLgAECn8lAAMSAAcJxQ+UGwC/AAARAAcJjQ0YdgBxAQASAAUJBxGUGwC/AAAAAA==.Voidgazer:BAAALgAECgYJDAAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.Voltage:BAAALgAECgEJAQAAAA==.',
Vy='Vynivar:BAAALgAECgEJAQAAAA==.Vynlan:BAAALgAECgQJBAABLgAFFAcJJgADAOUkAA==.',
Wa='Warlockboi:BAAALgAECgQJBAAAAA==.',
We='Wes:BAABLgAECn87AAIjAAkJvRpOAwB5AgAjAAkJvRpOAwB5AgAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willybcastin:BAAALgAFFAEJAQABLgAFFAgJIAAiAAAiAA==.Willybwankin:BAACLgAFFH8gAAIiAAgJACKbAABrAgAiAAgJACKbAABrAgAuAAQKfykAAiIACQkxJsoAAOEDACIACQkxJsoAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAABLgAECn8VAAIGAAkJsgv3IQD4AAAGAAkJsgv3IQD4AAAAAA==.',
Wy='Wyvern:BAABLgAECn8gAAIRAAkJFA7bTQCsAQARAAkJFA7bTQCsAQAAAA==.',
Xa='Xanthion:BAAALgAECgUJCAAAAA==.Xarinn:BAAALgADCgEJAQAAAA==.',
Yo='Yodapopz:BAAALgADCgYJBgAAAA==.',
Za='Zacarly:BAABLgAECn8UAAIBAAgJHhd2IgAsAgABAAgJHhd2IgAsAgAAAA==.Zalarian:BAAALgAECgYJBwABLgAECgkJUQAJAEkgAA==.Zalmage:BAABLgAECn9RAAMJAAkJSSBdEwDgAgAJAAkJSSBdEwDgAgApAAIJ5wlqFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgADCgYJCAAAAA==.Zeseroth:BAACLgAFFH8hAAIHAAcJ+hxkDADrAQAHAAcJ+hxkDADrAQAuAAQKfycAAgcACQmkIywDAKMDAAcACQmkIywDAKMDAAAA.Zeserotho:BAAALgAFFAEJAQAAAA==.',
Zy='Zyn:BAACLgAFFH8MAAIQAAQJ1SQKCwB/AQAQAAQJ1SQKCwB/AQAuAAQKfyUAAxAACQndIBEGAO4CABAACQndIBEGAO4CABsABAllE9BrAF4AAAAA.',
['Äs']='Äshra:BAAALgADCgMJAwAAAA==.',
['Øm']='Ømen:BAAALgADCgQJBAAAAA==.',
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
