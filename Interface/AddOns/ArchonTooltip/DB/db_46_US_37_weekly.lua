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
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-06-13',data={Ac='Aconite:BAAALgAECgYJDQAAAA==.',
Ad='Adhoria:BAAALgAECgEJAgAAAA==.Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8qAAMBAAcJxhw2CQBaAgABAAcJxhw2CQBaAgACAAUJCB+AGgA/AQAuAAQKfzMAAwIACQnQI5QQAJsCAAIACAncJJQQAJsCAAEACQmgHU8jAC8CAAAA.',
Ai='Ailuria:BAABLgAECn8yAAIDAAkJIiRBAwCHAwADAAkJIiRBAwCHAwAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgAECgIJAgAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIEAAgJzA1QIwCjAQAEAAgJzA1QIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Alikith:BAABLgAECn84AAQGAAkJJBWFCwAKAgAGAAkJJBWFCwAKAgAHAAMJgAhFIgGMAAAIAAEJyRKYhwA4AAAAAA==.Alkaline:BAAALgADCggJDAAAAA==.Altheyra:BAAALgAECgYJCgAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrìel:BAABLgAECn9BAAIJAAkJ/xBHTgDuAQAJAAkJ/xBHTgDuAQAAAA==.Amelía:BAAALgAECgYJBgABLgAFFAQJEwABAMoJAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8TAAMBAAQJygn7OQDBAAABAAQJygn7OQDBAAACAAIJwwLOFwB5AAAuAAQKfyEAAwEACQn1F0crAPsBAAEACQn1F0crAPsBAAIAAQlOHSt7AEwAAAAA.',
An='Angando:BAABLgAECn8tAAIKAAkJpRXEDgD6AQAKAAkJpRXEDgD6AQAAAA==.Angandomix:BAAALgAECgEJAQAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Anneliesë:BAAALgADCgUJFAAAAA==.',
Ao='Aozora:BAABLgAECn8dAAICAAgJzBC4LABuAQACAAgJzBC4LABuAQAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Ariellá:BAAALgAECgQJBAAAAA==.Arrows:BAAALgADCgcJBwAAAA==.Artemidoros:BAABLgAECn8vAAQLAAkJTyCmBgC1AgALAAkJfB+mBgC1AgAMAAYJGiEVIQA/AgANAAEJngr/igAwAAAAAA==.Artishard:BAAALgADCgMJAwAAAA==.',
As='Ashkaari:BAACLgAFFH8VAAIOAAUJCBAsLQAmAQAOAAUJCBAsLQAmAQAuAAQKfyEAAg4ACQkoHbMRAL0CAA4ACQkoHbMRAL0CAAAA.Asuná:BAABLgAECn8gAAMPAAkJchGpGgD4AQAPAAkJJhCpGgD4AQAQAAYJVQoVRwAdAQAAAA==.',
Au='Aurelyus:BAAALgAECgMJBAAAAA==.Aurevior:BAAALgAECgYJDgAAAA==.Ausuna:BAAALgAECgUJCgAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaderr:BAAALgAECgYJCwAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgIJAgABLgAFFAcJKgABAMYcAA==.',
Ba='Backerrz:BAACLgAFFH8mAAIRAAcJzRBTIgC3AQARAAcJzRBTIgC3AQAuAAQKfzEAAxEACQlPHMkZAIgCABEACQlPHMkZAIgCABIAAwlAGS45ANAAAAAA.Bamberk:BAAALgADCgMJAwABLgAECgcJKAARAAYfAA==.',
Be='Bearbrownie:BAAALgAECgEJAQAAAA==.Bearwidit:BAAALgAECgYJCQAAAA==.Beefbrownie:BAABLgAECn8qAAIKAAkJ0yMMAgAsAwAKAAkJ0yMMAgAsAwAAAA==.Bellezora:BAAALgAECgUJBQABLgAECgkJIAABAFcTAA==.Berz:BAAALgAECgYJCwAAAA==.Berzerked:BAACLgAFFH8IAAITAAQJOByEEgBDAQATAAQJOByEEgBDAQAuAAQKfy8AAhMACQltI6wBACcDABMACQltI6wBACcDAAAA.Bestboygrip:BAAALgAECgcJEwAAAA==.Betelgues:BAAALgAECgEJAQAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAABLgAECn8WAAMDAAcJKhpdNACdAQADAAcJKhpdNACdAQAUAAYJiAf8TwC/AAAAAA==.Bigjonkillzz:BAAALgADCgEJAQAAAA==.Bigsave:BAABLgAECn8dAAIBAAkJCA9rUABKAQABAAkJCA9rUABKAQAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blindem:BAAALgADCgEJAQABLgAECgkJJgABAA8lAA==.Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8eAAIVAAUJ5BoUFwAqAQAVAAUJ5BoUFwAqAQAuAAQKf0oAAhUACQldIAwJAIECABUACQldIAwJAIECAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.Borghild:BAAALgADCgYJCgAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAABLgAECn83AAMDAAkJQRutDgCxAgADAAkJQRutDgCxAgAWAAEJ1xa/iwBDAAAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brick:BAAALgAFFAEJAQAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAABLgAECn8ZAAIXAAcJ5Ry6HQD/AQAXAAcJ5Ry6HQD/AQAAAA==.',
Bu='Buckett:BAAALgAECgUJBQAAAA==.Buckfuttz:BAAALgAECggJEgAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH87AAIUAAYJkyZMAACAAgAUAAYJkyZMAACAAgAuAAQKfxcAAhQACQlfJngAANkDABQACQlfJngAANkDAAEuAAUUCQkcABgA/yMA.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAABLgAECn8uAAIKAAgJNBmPDwDrAQAKAAgJNBmPDwDrAQAAAA==.',
Ch='Chainmalejr:BAAALgAECgYJBgABLgAFFAQJGAAJABcaAA==.Changedragon:BAAALgAECgUJBQAAAA==.Chelseyb:BAAALgADCgcJBwAAAA==.Chiron:BAAALgAECgcJBwABLgAECgkJGQARALsJAA==.Chirón:BAABLgAECn8UAAIZAAcJ+Qw+FQAuAQAZAAcJ+Qw+FQAuAQAAAA==.Chiyukii:BAAALgAECgkJAQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQABLgAECgkJKgAGAL0cAA==.',
Co='Colorss:BAAALgADCgEJAQAAAA==.Connie:BAABLgAECn8oAAIMAAkJrxwFKAA7AgAMAAkJrxwFKAA7AgAAAA==.Cowmein:BAABLgAECn8YAAMCAAgJhwt6OwAfAQACAAgJhwt6OwAfAQABAAEJ4AQj4AAkAAAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crune:BAAALgAECgEJAQAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAABLgAECn8aAAIaAAcJ9RlGRAC3AQAaAAcJ9RlGRAC3AQAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAYJLAAbAIUcAA==.',
Da='Dameian:BAAALgAECgEJAQAAAA==.Dapur:BAAALgADCgkJEgAAAA==.Davidmamet:BAAALgADCgIJAwAAAA==.Dayne:BAABLgAECn8fAAIUAAkJ+A6mIQCYAQAUAAkJ+A6mIQCYAQAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAFFAQJGAAJABcaAA==.',
De='Demontot:BAAALgADCgkJCgAAAA==.Derik:BAAALgAECgYJBgABLgAFFAUJHAAXAPUeAA==.Deäthknight:BAAALgAECgEJAQAAAA==.',
Dh='Dheginsea:BAAALgAECgYJBgAAAA==.',
Di='Dillexis:BAACLgAFFH8cAAIXAAUJ9R4KFABlAQAXAAUJ9R4KFABlAQAuAAQKfyEAAhcACQnXGXUdAAECABcACQnXGXUdAAECAAAA.Dipindots:BAAALgADCgEJAQAAAA==.Divinemark:BAAALgAECgYJCQAAAA==.',
Do='Donald:BAABLgAECn9aAAMCAAkJ1xmoDwBkAgACAAkJ1xmoDwBkAgABAAMJiwdCpwB5AAAAAA==.Doublea:BAAALgAECggJEwAAAA==.',
Dr='Dragonchest:BAAALgAECgYJCQAAAA==.Dragonista:BAAALgAECgEJAgAAAA==.Dragonswolf:BAABLgAECn8uAAIXAAgJtRU5KQCzAQAXAAgJtRU5KQCzAQAAAA==.Dragonwing:BAAALgAECgEJAgAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAAALgAECgYJEgAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAcJJgADAOUkAA==.Dregon:BAACLgAFFH8mAAIDAAcJ5STsAwDcAgADAAcJ5STsAwDcAgAuAAQKfy0AAwMACQkwJmACAGYDAAMACQkwJmACAGYDABYAAgnlIalaAKUAAAAA.Dreinara:BAAALgAECgcJEAAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Duff:BAAALgADCggJCQAAAA==.Dummysezwhut:BAABLgAECn8rAAICAAgJxBItJQCeAQACAAgJxBItJQCeAQAAAA==.',
Ea='Earthborn:BAAALgAECgcJAQAAAA==.',
Ec='Echinopsis:BAAALgAECgYJBgAAAA==.',
Ei='Eilyn:BAABLgAECn9CAAIHAAkJthZgNgAlAgAHAAkJthZgNgAlAgAAAA==.',
El='Elena:BAAALgAECgQJBgABLgAECgkJMgADACIkAA==.Elesis:BAAALgADCgQJBAAAAA==.Ellida:BAABLgAECn8aAAIbAAcJMxGQIwC7AQAbAAcJMxGQIwC7AQAAAA==.',
Em='Emastoned:BAAALgAECgYJEAAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAABLgAECn8iAAMSAAkJPR43BAA6AgASAAgJIB83BAA6AgARAAgJBhqqQgDSAQAAAA==.',
Fa='Fangmage:BAABLgAECn8UAAMcAAcJbQ/hBwAUAQAcAAYJhRDhBwAUAQAJAAYJ2wjYzgDwAAAAAA==.Fayker:BAAALgAECggJDQAAAA==.Fazlain:BAABLgAECn8oAAIMAAgJiR63JwA9AgAMAAgJiR63JwA9AgAAAA==.',
Fe='Feldraca:BAAALgAECgEJAQAAAA==.Felestis:BAAALgAECgYJCQAAAA==.Felnir:BAAALgAECgMJBAABLgAECgkJGQARALsJAA==.',
Fi='Fighter:BAAALgADCgEJAQABLgAFFAUJGQAPAHoUAA==.',
Fl='Fluffydragon:BAACLgAFFH8SAAIdAAQJOBsHFgArAQAdAAQJOBsHFgArAQAuAAQKfyYAAx0ACQkkHCAFAMUCAB0ACQkkHCAFAMUCAB4ABQnnB2QoAN0AAAAA.',
Fr='Friartuck:BAAALgAECgkJEgABLgAFFAMJCwAMACIdAA==.Frosteez:BAAALgAECgEJAQABLgAECgYJEwAFAAAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgAECgEJAQAAAA==.Furryem:BAABLgAECn8mAAMBAAkJDyWuAQC9AwABAAkJDyWuAQC9AwAfAAMJGyKsGwAoAQAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
Ga='Galaena:BAAALgAECgcJBwAAAA==.Galvvatron:BAAALgAECgYJBgAAAA==.Ganden:BAABLgAECn86AAICAAkJnyAIBgD2AgACAAkJnyAIBgD2AgAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAACLgAFFH8MAAIHAAQJQxJYRAAdAQAHAAQJQxJYRAAdAQAuAAQKfz0AAgcACQlHGmwyADQCAAcACQlHGmwyADQCAAAA.Gatelinka:BAAALgAECgcJEQABLgAFFAQJEgAdADgbAA==.Gateto:BAABLgAECn8tAAMOAAkJTiDnCQDaAgAOAAkJTiDnCQDaAgAgAAQJiBAhXQDJAAABLgAFFAQJEgAdADgbAA==.',
Ge='Genfindel:BAAALgADCgYJBgAAAA==.Getinthevan:BAAALgADCgcJBwAAAA==.',
Gi='Gidden:BAAALgAECgYJDAAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Gn='Gnomechomsky:BAAALgADCggJDAAAAA==.',
Go='Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgkJDgAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.Grindcore:BAAALgAECgUJCAAAAA==.',
Gw='Gwenneth:BAAALgAECgQJBAAAAA==.',
['Gú']='Gúr:BAAALgAECgUJBQAAAA==.',
Ha='Halfordin:BAAALgADCgYJBgAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8pAAISAAkJ1hTABgDuAQASAAkJ1hTABgDuAQAAAA==.Helsreach:BAAALgAECgEJAQAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.Hoshi:BAAALgAECgEJAQAAAA==.',
Hr='Hrungnir:BAAALgAECgUJCAAAAA==.Hruoth:BAAALgAECgEJAQAAAA==.',
Hu='Hunt:BAABLgAECn8YAAMMAAYJ1Rd6ggA0AQAMAAYJNBd6ggA0AQANAAQJsw3cXQDKAAAAAA==.Huntinbub:BAABLgAECn9CAAMMAAkJaxD4PQDkAQAMAAkJaxD4PQDkAQANAAEJzQAxmgAZAAAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgkJBAAAAA==.',
In='Instaque:BAAALgAECgUJBQAAAA==.',
Ir='Irim:BAAALgAFFAIJAwAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgAECggJDwABLgAFFAUJHAAXAPUeAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAFAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8aAAIaAAUJmhkoNgBEAQAaAAUJmhkoNgBEAQAuAAQKfyQAAxoACAmYIeARAPACABoACAmYIeARAPACACEAAglECPthAFoAAAAA.Izlaar:BAAALgAECgMJAwAAAA==.Izzytt:BAAALgAECgUJCQAAAA==.',
Ja='Jacenskie:BAABLgAECn8jAAIXAAkJbBLRMQCEAQAXAAkJbBLRMQCEAQAAAA==.Jacob:BAAALgAECgQJDQAAAA==.Jadedbabe:BAAALgAECgUJBwAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.Jexter:BAAALgADCgIJAgAAAA==.',
Ji='Jimmyjams:BAAALgAECgYJBwABLgAFFAQJGAAJABcaAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Johncena:BAAALgAECgYJBgAAAA==.Joppa:BAAALgAECgMJBAABLgAFFAcJGgAbALAaAA==.Joyvimon:BAAALgAECgYJDwAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8aAAIiAAgJdwtxkgA/AQAiAAgJdwtxkgA/AQAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAFAAAAAA==.',
Kh='Khal:BAACLgAFFH8VAAMEAAYJyxuHCQBYAQAEAAYJyxuHCQBYAQAeAAIJEgemBgClAAAuAAQKfxUAAx4ACQkBIL4OAO8BAAQABwmCGvgXABMCAB4ABgnGI74OAO8BAAAA.Khornedaemon:BAAALgAECgQJBQAAAA==.',
Ki='Kickstarter:BAAALgAFFAIJAwAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kilysta:BAAALgAECgEJAQAAAA==.Kiy:BAAALgAECggJEAAAAA==.',
Kn='Knìghtmare:BAAALgADCgcJEwAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAABLgAECn8bAAIRAAkJwwM1mQAKAQARAAkJwwM1mQAKAQAAAA==.Kronas:BAAALgAECgcJDgAAAA==.',
Ku='Kurosaki:BAABLgAECn8ZAAIaAAkJfxu3PAABAgAaAAkJfxu3PAABAgAAAA==.',
La='Lazyheal:BAACLgAFFH8ZAAQPAAUJehQxHQBnAQAPAAUJ5hIxHQBnAQAQAAIJVhSpDACZAAAbAAIJfADIPwAyAAAuAAQKfx8ABBAACQl+G6QNAIgCABAACQl+G6QNAIgCAA8ABAlUBrE/ALEAABsAAgkgBi5YAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAUJGQAPAHoUAA==.',
Le='Leetsteve:BAAALgADCgYJCwAAAA==.Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8qAAIQAAcJ/RqsBQD5AQAQAAcJ/RqsBQD5AQAuAAQKfzQAAxAACQnOIKYDAB8DABAACQnOIKYDAB8DABsAAwktC1ZtAGUAAAAA.Leomoon:BAAALgAECgMJCAAAAA==.Leshy:BAAALgAECgYJDAAAAA==.Levite:BAABLgAECn8eAAMQAAYJqxvIHwDAAQAQAAYJqxvIHwDAAQAPAAUJGhLVPgAPAQAAAA==.',
Li='Lickytung:BAAALgADCgkJCgAAAA==.Lightwork:BAAALgAECgEJAQAAAA==.Lilara:BAABLgAECn8ZAAIRAAgJzAeCigAkAQARAAgJzAeCigAkAQAAAA==.Linthsong:BAAALgAECgUJBQABLgAECgkJIAAQAOcTAA==.Lionknite:BAACLgAFFH8OAAIiAAQJcQ94bAAhAQAiAAQJcQ94bAAhAQAuAAQKfy0AAiIACQnqG/YwADgCACIACQnqG/YwADgCAAAA.Lionshame:BAAALgAECgUJBQAAAA==.Liontabu:BAAALgAECgQJBgAAAA==.Liorii:BAAALgAECgEJAgAAAA==.Liteshocklet:BAAALgAECgEJAgABLgAFFAUJGQAPAHoUAA==.Littledung:BAAALgAECgMJAwAAAA==.Liwellan:BAAALgAECgcJBwAAAA==.',
Lo='Looting:BAABLgAECn8oAAIjAAgJlhQKCADNAQAjAAgJlhQKCADNAQAAAA==.Loving:BAAALgAECgIJBQAAAA==.',
Lu='Lucky:BAAALgAECgEJAQAAAA==.Lunexiya:BAABLgAECn8ZAAIaAAkJJgLR3gByAAAaAAkJJgLR3gByAAAAAA==.Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAACLgAFFH8JAAIBAAMJgwhbSQCQAAABAAMJgwhbSQCQAAAuAAQKfyEAAwEACAnuCwhdADsBAAEACAnuCwhdADsBAB8AAQkoAmliABkAAAAA.',
Ma='Mageko:BAAALgAECgEJBgAAAA==.Mageroni:BAAALgAECgcJBwABLgAECgkJIAAUADAWAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAFAAAAAA==.Makarion:BAABLgAECn8WAAIMAAgJxQsieABLAQAMAAgJxQsieABLAQAAAA==.Malvina:BAAALgAFFAEJAQAAAA==.Maoli:BAABLgAECn8UAAMHAAQJLhXM+wC5AAAHAAMJGhXM+wC5AAAIAAQJHgsIZwCWAAAAAA==.Marcelius:BAAALgAECgEJAgAAAA==.Markeleth:BAAALgAECgYJBgABLgAECgkJQwAGAHMcAA==.Marohen:BAAALgADCgYJBgAAAA==.Matsumoto:BAAALgAECgEJAwAAAA==.Mauka:BAABLgAECn8tAAMBAAgJUg3MRQB2AQABAAgJUg3MRQB2AQACAAYJQBTdOABUAQAAAA==.Mauzer:BAAALgAECgEJAwABLgAECgkJPQAhAPobAA==.',
Mc='Mcfallen:BAAALgAECgIJAgAAAA==.Mcksquizy:BAABLgAECn8nAAIiAAkJUh4UMAB3AgAiAAkJUh4UMAB3AgAAAA==.Mclinkdink:BAAALgADCgkJCQAAAA==.Mcscrotie:BAABLgAECn8UAAIiAAgJQga3swAMAQAiAAgJQga3swAMAQAAAA==.',
Me='Mes:BAABLgAECn8jAAIgAAkJghtdGwADAgAgAAkJghtdGwADAgAAAA==.Metatrøn:BAAALgADCgkJDgAAAA==.',
Mi='Mimmi:BAAALgAECgUJEwABLgAECgkJPQAhAPobAA==.Mishri:BAACLgAFFH8UAAIaAAQJCSOFIwCYAQAaAAQJCSOFIwCYAQAuAAQKfzQAAhoACQn2JEwEAD8DABoACQn2JEwEAD8DAAAA.',
Mo='Monbonestorm:BAAALgAFFAIJAgABLgAECggJGgAaAIgUAA==.Mooittooit:BAAALgAECgYJBwAAAA==.Moonsorrow:BAAALgAECgEJAQAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAABLgAECn89AAMhAAkJ+hshCgCEAgAhAAkJ+hshCgCEAgAkAAIJURrBLQBIAAAAAA==.',
My='Mykana:BAABLgAECn8XAAMHAAYJPwgP+wC6AAAHAAYJPwgP+wC6AAAGAAQJ0wIuNgBrAAAAAA==.Myodieboy:BAAALgAECgIJAgAAAA==.Mywifesaidno:BAAALgADCggJCAAAAA==.',
Na='Nakabeam:BAABLgAECn8vAAIaAAkJIhbeMwD0AQAaAAkJIhbeMwD0AQAAAA==.Nakatwin:BAABLgAECn8YAAIaAAcJJhXmWACXAQAaAAcJJhXmWACXAQABLgAECgkJLwAaACIWAA==.Naklek:BAABLgAECn8hAAMfAAgJBh6TBgCOAgAfAAgJBh6TBgCOAgAYAAEJYgtiNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAFAAAAAA==.',
Ni='Nicked:BAECLgAFFH8ZAAIMAAYJuhe8HACIAQAMAAYJuhe8HACIAQAuAAQKfyMAAwwACQmtH5sOAMYCAAwACQmtH5sOAMYCAA0ABAl0BlRpAJkAAAAA.Nika:BAAALgAECgYJCgAAAA==.Niraleth:BAAALgAECgMJAwAAAA==.Nistik:BAABLgAECn8oAAMQAAkJmAlHLgBWAQAQAAkJmAlHLgBWAQAbAAEJ0wHeawAaAAAAAA==.',
No='Noriala:BAAALgAECgYJCAABLgAECgkJMwAJAC0kAA==.Nozomí:BAAALgAECgUJBQAAAA==.',
Ob='Obergefel:BAAALgADCgEJAQAAAA==.',
Op='Ophiuchus:BAABLgAECn8ZAAIRAAkJuwnKYwB2AQARAAkJuwnKYwB2AQAAAA==.',
Or='Orcdung:BAAALgADCgYJBgAAAA==.',
Os='Ostpeppar:BAAALgADCgUJEAAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAABLgAECn8XAAQIAAgJ7xTANgBxAQAIAAcJeRTANgBxAQAGAAgJeA/0HgARAQAHAAEJcwORwQEfAAABLgAECgkJIAAUADAWAA==.Pamelina:BAAALgADCgUJFAAAAA==.Pandaexpress:BAAALgAECgYJBgABLgAFFAUJHAAXAPUeAA==.Panzerfäust:BAAALgAECgYJEwAAAA==.Pawrina:BAAALgAFFAEJAQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgAECgEJAQAAAA==.Pestis:BAAALgAECgQJBAAAAA==.Pewpewbambam:BAAALgAECgUJBQAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAABLgAECn8uAAMHAAkJwBYFQQABAgAHAAkJwBYFQQABAgAIAAQJzgjxZACeAAAAAA==.Philster:BAAALgAFFAIJBAAAAA==.',
Pi='Pilfering:BAAALgADCgQJBAAAAA==.',
Pl='Plumpt:BAAALgAECgcJEwAAAA==.',
Po='Poochieboo:BAAALgADCgQJBAAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAABLgAECn8jAAIQAAkJRRWMGAAEAgAQAAkJRRWMGAAEAgAAAA==.Punchem:BAAALgADCgcJBwABLgAECgkJJgABAA8lAA==.Purex:BAABLgAECn8dAAIjAAkJKQYwCgCSAQAjAAkJKQYwCgCSAQAAAA==.',
Py='Pylonshots:BAAALgAECgYJBgAAAA==.Pyria:BAAALgADCgUJCAAAAA==.',
['Pé']='Pérrywinklé:BAAALgAFFAIJAgAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAABLgAECn8UAAIGAAgJ4BrIDQDkAQAGAAgJ4BrIDQDkAQAAAA==.Rathus:BAABLgAECn8oAAIRAAcJBh8SNAAHAgARAAcJBh8SNAAHAgAAAA==.Rawdata:BAACLgAFFH8OAAMlAAMJXQnYDwDEAAAlAAMJXQnYDwDEAAAOAAMJwArHVwCYAAAuAAQKfykAAyUACQk5FRQRAJ0BACUACQk5FRQRAJ0BAA4ACAkvD1RCAHgBAAAA.Razenka:BAAALgAECgIJAgAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8gAAIMAAgJqRetPQC4AQAMAAgJqRetPQC4AQABLgAECgkJJgAIADwdAA==.Rebeka:BAABLgAECn8mAAIIAAkJPB38BwAKAwAIAAkJPB38BwAKAwAAAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgcJEQABLgAECgkJHwAUAPgOAA==.Reniel:BAAALgAECgUJBgABLgAECgkJOAAGACQVAA==.Ressie:BAAALgAECgQJCQAAAA==.Reston:BAAALgAECgYJBgABLgAFFAMJAwAFAAAAAA==.Reverendlion:BAABLgAECn8WAAIbAAgJ7BZMIADCAQAbAAgJ7BZMIADCAQAAAA==.',
Ri='Riyu:BAAALgADCgEJAgAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.',
Ry='Ryblade:BAABLgAFFH8JAAIHAAMJHQh1eAC+AAAHAAMJHQh1eAC+AAABLgAFFAUJHAAHACUVAA==.',
Sa='Saiko:BAAALgAECgMJAwABLgAFFAUJGQAmAFkNAA==.Sainthealz:BAAALgAECgEJAgAAAA==.Saladcake:BAABLgAECn8qAAIJAAgJWxapVwDTAQAJAAgJWxapVwDTAQAAAA==.Salleane:BAACLgAFFH8NAAIHAAQJgw0vTwALAQAHAAQJgw0vTwALAQAuAAQKfxoAAgcACQmOFTNeAMkBAAcACQmOFTNeAMkBAAAA.Samgompers:BAAALgADCgIJAgAAAA==.Sampal:BAABLgAECn9DAAMGAAkJcxzwBwBYAgAGAAgJjx7wBwBYAgAHAAEJqw2+dAFAAAAAAA==.Sampriest:BAABLgAECn8tAAMQAAgJsCAyCQDTAgAQAAgJsCAyCQDTAgAPAAEJpxD1dgAyAAABLgAECgkJQwAGAHMcAA==.Samwield:BAECLgAFFH8fAAInAAUJDiKDFABgAQAnAAUJDiKDFABgAQAuAAQKfz4ABCcACQnHIbUFANQCACcACQnHIbUFANQCACMAAwlCGEsTAM0AACgAAQnUCvckAC8AAAAA.Sanchoe:BAAALgAFFAEJAQAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.Saucemoe:BAAALgAECgEJAgAAAA==.',
Se='Seireitei:BAABLgAECn80AAMOAAkJpRvsEwCpAgAOAAkJpRvsEwCpAgAgAAEJIAZ+twAiAAAAAA==.Selaheal:BAABLgAECn9BAAIbAAkJ3hc/EwA2AgAbAAkJ3hc/EwA2AgAAAA==.Seraath:BAACLgAFFH8nAAIkAAcJVxlHAQDTAQAkAAcJVxlHAQDTAQAuAAQKfyYAAyQACQn3IZAAAGQDACQACQn3IZAAAGQDABoAAQkAAJDSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.Serius:BAAALgAECgMJAwAAAA==.',
Sh='Shadowskull:BAAALgADCgkJFQAAAA==.Shadowydream:BAAALgAECgIJAgAAAA==.Shadwkllr:BAABLgAECn8VAAMgAAYJtw7UTwDzAAAgAAYJtw7UTwDzAAAOAAIJ3g4LtgBaAAAAAA==.Shamloo:BAAALgADCgEJAQAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAABLgAECn8XAAISAAYJQiACCADLAQASAAYJQiACCADLAQAAAA==.Shortie:BAAALgADCggJDwAAAA==.',
Si='Sinister:BAABLgAFFH8HAAIhAAQJ6xbcDQAzAQAhAAQJ6xbcDQAzAQAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skid:BAAALgADCgEJAQAAAA==.Skies:BAAALgAECgEJAgABLgAECgcJCAAFAAAAAA==.',
Sn='Sneakyhoof:BAAALgADCgcJBwAAAA==.Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgAECgYJDgAAAA==.',
Ss='Ssteroidss:BAAALgAECgIJBAAAAA==.',
St='Stabbem:BAAALgADCgEJAQABLgAECgkJJgABAA8lAA==.Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBQAAAA==.Stepfist:BAAALgAFFAMJAwABLgAFFAQJGAAJABcaAA==.Stergertha:BAAALgAECgEJAQABLgAFFAMJBQAgAM0QAA==.Stersèbuk:BAAALgAECgEJAQABLgAFFAMJBQAgAM0QAA==.Stervana:BAACLgAFFH8KAAIEAAQJjxq/KQAcAQAEAAQJjxq/KQAcAQAuAAQKfy0AAgQACQl0IOIDAFoDAAQACQl0IOIDAFoDAAEuAAUUAwkFACAAzRAA.Stickytoes:BAAALgADCgYJBgAAAA==.Stilettoes:BAAALgADCgIJAgAAAA==.Stormyknight:BAABLgAECn8sAAMdAAkJ3g4FFgBqAQAdAAkJ3g4FFgBqAQAeAAcJOwsFEwDVAAAAAA==.Stêrk:BAACLgAFFH8FAAIgAAMJzRADMgDBAAAgAAMJzRADMgDBAAAuAAQKfxQAAiAABwluFycmALUBACAABwluFycmALUBAAAA.',
Su='Sundemonhunt:BAAALgAECgMJAwAAAA==.Sunnmonk:BAAALgADCgQJBAAAAA==.Sunpally:BAAALgAECggJBQAAAA==.Sunwrath:BAAALgAECgcJCAAAAA==.Susmonk:BAAALgAECgQJBQAAAA==.Suspectedd:BAABLgAFFH8KAAIJAAMJmxJkLwD5AAAJAAMJmxJkLwD5AAABLgAFFAcJKQAKAKckAA==.Suswar:BAACLgAFFH8pAAIKAAcJpySkAgBhAgAKAAcJpySkAgBhAgAuAAQKfzAAAgoACQnIJJoAALgDAAoACQnIJJoAALgDAAAA.Suvulaan:BAABLgAECn9GAAMdAAkJXAqyGgAsAQAdAAgJ7geyGgAsAQAEAAkJGQW7QgAbAQAAAA==.',
Sw='Swifix:BAAALgAECgYJBgAAAA==.Swordsmyth:BAAALgAECgUJBQAAAA==.',
Ta='Tacostand:BAACLgAFFH8aAAIaAAYJKhWELgBjAQAaAAYJKhWELgBjAQAuAAQKfzIAAhoACQlNIOUHAEwDABoACQlNIOUHAEwDAAAA.Tamarlane:BAAALgADCgIJAgAAAA==.Tatoo:BAACLgAFFH8LAAIMAAMJIh2/TwADAQAMAAMJIh2/TwADAQAuAAQKf0cAAgwACQlyJFYEAEkDAAwACQlyJFYEAEkDAAAA.',
Te='Teeice:BAABLgAECn8iAAIjAAkJdROsBgD4AQAjAAkJdROsBgD4AQAAAA==.Teo:BAABLgAECn8jAAIbAAkJmxNFHADhAQAbAAkJmxNFHADhAQAAAA==.Terian:BAAALgAECgkJBwAAAA==.',
Th='Thaodan:BAABLgAECn8aAAIgAAkJAhFaOQBNAQAgAAkJAhFaOQBNAQAAAA==.That:BAAALgAECgEJAgAAAA==.Thekan:BAABLgAECn8bAAIhAAkJlhTmFQDXAQAhAAkJlhTmFQDXAQAAAA==.Theriot:BAACLgAFFH8GAAMHAAMJuRDHaQDVAAAHAAMJuRDHaQDVAAAGAAIJmAKoFQBIAAAuAAQKfy8ABAcACQnbHZo5ABoCAAcACQnbHZo5ABoCAAYABgkIDEcpAMsAAAgAAQkzCEegACgAAAAA.Thianá:BAABLgAECn8ZAAIOAAgJlgsAUQBqAQAOAAgJlgsAUQBqAQAAAA==.Thüclides:BAAALgAECgcJAgAAAA==.',
Ti='Tiermoghuen:BAAALgAECgkJCQAAAA==.Tikidragoona:BAAALgAECgIJAgAAAA==.Timberdoodle:BAAALgAECgMJAwAAAA==.Timtamslam:BAAALgAECgYJDAAAAA==.Tinkerspell:BAABLgAECn8gAAIBAAkJVxO4LgDnAQABAAkJVxO4LgDnAQAAAA==.Tinkiebella:BAAALgAECgEJAgABLgAECgkJIAABAFcTAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
Tl='Tlitlitzin:BAAALgAECgQJCAAAAA==.',
To='Tobivoker:BAAALgAECgQJBQAAAA==.Toosus:BAABLgAFFH8PAAIVAAQJVSEGIQDeAAAVAAQJVSEGIQDeAAABLgAFFAcJKQAKAKckAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAACLgAFFH8HAAIlAAQJYQdwDAD1AAAlAAQJYQdwDAD1AAAuAAQKfxoAAiUACAkrFG0KACoCACUACAkrFG0KACoCAAAA.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgQJBwAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Totec:BAAALgAECgkJCgAAAA==.',
Tr='Treatimus:BAAALgADCgMJAwABLgAECgkJQwAbAH8kAA==.Treesum:BAAALgADCgQJBAAAAA==.Trolldung:BAAALgAECgQJBwAAAA==.Truffaut:BAAALgAECgEJAQAAAA==.',
Tt='Tturtle:BAACLgAFFH8XAAIHAAYJ4gkrMQBIAQAHAAYJ4gkrMQBIAQAuAAQKfyUAAgcACQl+Fd8wAF8CAAcACQl+Fd8wAF8CAAAA.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Tw='Twoblock:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tystraz:BAAALgAECgYJDwAAAA==.',
Ud='Udúnnaur:BAAALgADCggJDgAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Unclebuck:BAAALgADCgQJBAAAAA==.Undermage:BAAALgADCgQJBAAAAA==.Unholysam:BAEALgAECgcJDwABLgAFFAUJHwAnAA4iAA==.',
Va='Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vecna:BAAALgAECgQJBgABLgAECgYJCAAFAAAAAA==.Vector:BAAALgAECgYJCAAAAA==.Velata:BAABLgAECn8cAAIJAAUJWw+k3QDaAAAJAAUJWw+k3QDaAAAAAA==.Velvethunda:BAAALgAECgYJBgAAAA==.Verdugo:BAAALgAECgUJDwAAAA==.Verite:BAABLgAECn8bAAMiAAcJzQPnEQGRAAAiAAcJxwLnEQGRAAAZAAMJOgUEFABTAAAAAA==.',
Vi='Vicar:BAAALgADCggJDgAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAABLgAECn8jAAIXAAkJ9RsZEwBYAgAXAAkJ9RsZEwBYAgAAAA==.',
Vo='Vodka:BAAALgADCgcJFQAAAA==.Voelva:BAAALgAECgIJBQAAAA==.Voidedge:BAABLgAECn8lAAMSAAcJxQ/iHAC9AAARAAcJjQ0YdgBxAQASAAUJBxHiHAC9AAAAAA==.Voidgazer:BAAALgAECgYJDAAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.Voltage:BAAALgAECgEJAQAAAA==.',
Vy='Vynivar:BAAALgAECgEJAgAAAA==.Vynlan:BAAALgAECgQJBAABLgAFFAcJJgADAOUkAA==.',
Wa='Warlockboi:BAAALgAECgQJBAAAAA==.',
We='Wes:BAABLgAECn87AAIjAAkJvRp5AwB4AgAjAAkJvRp5AwB4AgAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willybcastin:BAAALgAFFAEJAQABLgAFFAgJJAAiAAAiAA==.Willybwankin:BAACLgAFFH8kAAIiAAgJACKbAABrAgAiAAgJACKbAABrAgAuAAQKfykAAiIACQkxJsoAAOEDACIACQkxJsoAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAABLgAECn8VAAIGAAkJsgv3IQD4AAAGAAkJsgv3IQD4AAAAAA==.',
Wy='Wylalena:BAAALgADCgUJBQAAAA==.Wyvern:BAABLgAECn8gAAIRAAkJFA5XUgCkAQARAAkJFA5XUgCkAQAAAA==.',
Xa='Xanstar:BAAALgAECgEJAQAAAA==.Xanthion:BAAALgAECgUJCAAAAA==.Xarinn:BAAALgADCgEJAQAAAA==.',
Yo='Yodapopz:BAAALgADCgYJBgAAAA==.',
Za='Zacarly:BAACLgAFFH8FAAMBAAMJzANrUQB3AAABAAMJzANrUQB3AAACAAEJ8wG4UwApAAAuAAQKfxkAAgEACAkAGhMaAHICAAEACAkAGhMaAHICAAAA.Zalarian:BAAALgAECgYJBwABLgAECgkJWgAJADsjAA==.Zalmage:BAABLgAECn9aAAMJAAkJOyO+CQAqAwAJAAkJOyO+CQAqAwApAAIJ5wlqFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgADCgcJDgAAAA==.Zeseroth:BAACLgAFFH8lAAIHAAcJQB2cCwASAgAHAAcJQB2cCwASAgAuAAQKfycAAgcACQmkIywDAKMDAAcACQmkIywDAKMDAAAA.Zeserotho:BAAALgAFFAEJAQAAAA==.',
Zy='Zyn:BAACLgAFFH8MAAIQAAQJ1SSHDAB6AQAQAAQJ1SSHDAB6AQAuAAQKfyUAAxAACQndIBEGAO4CABAACQndIBEGAO4CABsABAllE15wAF0AAAAA.',
['Äs']='Äshra:BAAALgADCgMJAwAAAA==.',
['Ön']='Önion:BAAALgADCgUJBAAAAA==.',
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
