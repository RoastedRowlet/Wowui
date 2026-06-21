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

local lookup = {'Druid-Restoration','Druid-Balance','Monk-Mistweaver','Evoker-Augmentation','Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Mage-Frost','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Priest-Discipline','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Monk-Brewmaster','DeathKnight-Blood','Monk-Windwalker','Warrior-Fury','Druid-Guardian','DeathKnight-Frost','DemonHunter-Devourer','Priest-Shadow','Evoker-Devastation','DemonHunter-Havoc','Mage-Fire','Evoker-Preservation','Druid-Feral','Shaman-Elemental','DeathKnight-Unholy','Rogue-Assassination','DemonHunter-Vengeance','Shaman-Enhancement','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Aconite:BAAALgAECgYJDwAAAA==.',
Ad='Adhoria:BAAALgAECgEJAgAAAA==.Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8rAAMBAAcJ+hzqCQBZAgABAAcJ+hzqCQBZAgACAAUJCB+qGwA8AQAuAAQKfzMAAwIACQnQI5QQAJsCAAIACAncJJQQAJsCAAEACQmgHU8jAC8CAAAA.',
Ai='Ailuria:BAABLgAECn8yAAIDAAkJIiRYAwCHAwADAAkJIiRYAwCHAwAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgAECgIJAgAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIEAAgJzA1QIwCjAQAEAAgJzA1QIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Alikith:BAABLgAECn84AAQGAAkJJBXBCwAKAgAGAAkJJBXBCwAKAgAHAAMJgAhmJgGMAAAIAAEJyRI3iQA4AAAAAA==.Alkaline:BAAALgADCggJDAAAAA==.Altheyra:BAAALgAECgYJCgAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alyas:BAAALgAECggJBgAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrai:BAAALgAECgUJBQAAAA==.Ambrìel:BAABLgAECn9CAAIJAAkJ/xCyTwDtAQAJAAkJ/xCyTwDtAQAAAA==.Amelía:BAAALgAECgYJBgABLgAFFAQJEwABAMoJAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8TAAMBAAQJyglgOwDBAAABAAQJyglgOwDBAAACAAIJwwLOFwB5AAAuAAQKfyEAAwEACQn1F6ErAPwBAAEACQn1F6ErAPwBAAIAAQlOHVR9AEwAAAAA.',
An='Angando:BAABLgAECn8zAAIKAAkJdxYNDQAZAgAKAAkJdxYNDQAZAgAAAA==.Angandomix:BAAALgAECgEJAQAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Ankleblaster:BAAALgADCgYJBgAAAA==.Anneliesë:BAAALgADCgUJFAAAAA==.',
Ao='Aozora:BAABLgAECn8gAAICAAgJKxHHLAByAQACAAgJKxHHLAByAQAAAA==.',
Ap='Aperfecttool:BAAALgAECggJBgAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Ariellá:BAAALgAECgQJCgAAAA==.Arrows:BAAALgAECgMJAwAAAA==.Artemidoros:BAABLgAECn8vAAQLAAkJTyDPBgCzAgALAAkJfB/PBgCzAgAMAAYJGiEVIQA/AgANAAEJngr/igAwAAAAAA==.Artishard:BAAALgADCgMJAwAAAA==.',
As='Ashkaari:BAACLgAFFH8VAAIOAAUJCBARLwAmAQAOAAUJCBARLwAmAQAuAAQKfyEAAg4ACQkoHR8SALwCAA4ACQkoHR8SALwCAAAA.Asuná:BAABLgAECn8hAAMPAAkJchHJGwDxAQAPAAkJJhDJGwDxAQAQAAYJVQoVRwAdAQAAAA==.',
Au='Aurelyus:BAAALgAECgMJBAAAAA==.Aurevior:BAAALgAECgYJDgAAAA==.Ausuna:BAAALgAECgUJCgAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaderr:BAAALgAECgYJCwAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgIJAgABLgAFFAcJKwABAPocAA==.',
Ba='Backerrz:BAACLgAFFH8nAAIRAAcJzRBbJQC2AQARAAcJzRBbJQC2AQAuAAQKfzEAAxEACQlPHFsaAIYCABEACQlPHFsaAIYCABIAAwlAGS45ANAAAAAA.Bamberk:BAAALgADCgMJAwABLgAECgcJKAARAAYfAA==.Barathor:BAAALgAECgYJBgAAAA==.',
Be='Bearbrownie:BAAALgAECgEJAQAAAA==.Bearwidit:BAAALgAECgYJCQAAAA==.Beefbrownie:BAABLgAECn8qAAIKAAkJ0yMiAgArAwAKAAkJ0yMiAgArAwAAAA==.Bellezora:BAAALgAECgUJBQABLgAECgkJIAABAFcTAA==.Berz:BAAALgAECgYJCwAAAA==.Berzerked:BAACLgAFFH8IAAITAAQJOByxEwBAAQATAAQJOByxEwBAAQAuAAQKfy8AAhMACQltI6wBACcDABMACQltI6wBACcDAAAA.Bestboygrip:BAAALgAECgcJEwAAAA==.Betelgues:BAAALgAECgEJAQAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAABLgAECn8dAAMDAAcJqR5kAABHAgADAAcJqR5kAABHAgAUAAYJiAfNUAC/AAAAAA==.Bigjonkillzz:BAAALgADCgEJAQAAAA==.Bigsave:BAABLgAECn8dAAIBAAkJCA91UQBJAQABAAkJCA91UQBJAQAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blindem:BAAALgADCgEJAQABLgAECgkJJgABAA8lAA==.Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8fAAIVAAUJ5BojGAAmAQAVAAUJ5BojGAAmAQAuAAQKf1EAAhUACQl/INcFAMkCABUACQl/INcFAMkCAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.Borghild:BAAALgADCgYJCgAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAABLgAECn83AAMDAAkJQRv/DgCyAgADAAkJQRv/DgCyAgAWAAEJ1xZjjgBDAAAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brick:BAAALgAFFAEJAQAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAABLgAECn8bAAIXAAgJ8RkYHgD+AQAXAAgJ8RkYHgD+AQAAAA==.',
Bu='Buckett:BAAALgAECgUJBQAAAA==.Buckfuttz:BAAALgAECggJEgAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH87AAIUAAYJkyZMAACAAgAUAAYJkyZMAACAAgAuAAQKfxcAAhQACQlfJngAANkDABQACQlfJngAANkDAAEuAAUUCQkcABgA/yMA.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAABLgAECn84AAIKAAkJRxhhAADGAQAKAAkJRxhhAADGAQAAAA==.',
Ch='Chainmalejr:BAAALgAECgYJBgABLgAFFAQJGAAJABcaAA==.Changedragon:BAAALgAECgUJBQAAAA==.Chelseyb:BAAALgADCgcJBwAAAA==.Chiron:BAAALgAECgcJDQABLgAECgkJGQARALsJAA==.Chirón:BAABLgAECn8VAAIZAAcJ+QwRFgApAQAZAAcJ+QwRFgApAQAAAA==.Chiyukii:BAAALgAECgkJAQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQABLgAECgkJKgAGAL0cAA==.',
Co='Colorss:BAAALgADCgEJAQAAAA==.Connie:BAABLgAECn8oAAIMAAkJrxwmKQA6AgAMAAkJrxwmKQA6AgAAAA==.Cowmein:BAABLgAECn8YAAMCAAgJhwtlPAAfAQACAAgJhwtlPAAfAQABAAEJ4AQj4AAkAAAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crune:BAAALgAECgEJAgAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAABLgAECn8aAAIaAAcJ9RkpRQC3AQAaAAcJ9RkpRQC3AQAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAcJLQAbAIQaAA==.',
Da='Dameian:BAAALgAECgEJAQAAAA==.Dapur:BAAALgADCgkJEgAAAA==.Davidmamet:BAAALgADCgIJAwAAAA==.Dayne:BAABLgAECn8fAAIUAAkJ+A4BIgCYAQAUAAkJ+A4BIgCYAQAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAFFAQJGAAJABcaAA==.',
De='Demontot:BAAALgADCgkJCgAAAA==.Derik:BAAALgAECgcJDQABLgAFFAUJHAAXAPUeAA==.Deäthknight:BAAALgAECgEJAQAAAA==.',
Dh='Dheginsea:BAAALgAECgYJBgAAAA==.',
Di='Dillexis:BAACLgAFFH8cAAIXAAUJ9R5AFQBjAQAXAAUJ9R5AFQBjAQAuAAQKfyEAAhcACQnXGfAdAP8BABcACQnXGfAdAP8BAAAA.Dipindots:BAAALgADCgEJAQAAAA==.Divinemark:BAAALgAECgYJCQAAAA==.',
Do='Donald:BAABLgAECn9jAAMCAAkJwxtCAAB4AgACAAkJwxtCAAB4AgABAAMJiwdCpwB5AAAAAA==.Doublea:BAAALgAECggJEwAAAA==.',
Dr='Dragonchest:BAAALgAECggJDAAAAA==.Dragonista:BAAALgAECgEJAgAAAA==.Dragonswolf:BAABLgAECn8uAAIXAAgJtRX5KQCwAQAXAAgJtRX5KQCwAQAAAA==.Dragonwing:BAAALgAECgEJAgAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAABLgAECn8WAAMEAAgJ0QtFRgARAQAEAAcJ7wpFRgARAQAcAAIJ9AsaHwBYAAAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAcJJwADAOUkAA==.Dregon:BAACLgAFFH8nAAIDAAcJ5SR/BADaAgADAAcJ5SR/BADaAgAuAAQKfy0AAwMACQkwJmACAGYDAAMACQkwJmACAGYDABYAAgnlIalaAKUAAAAA.Dreinara:BAABLgAECn8UAAIQAAcJ1Ax/MwA5AQAQAAcJ1Ax/MwA5AQAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Duff:BAAALgADCggJCQAAAA==.Dummysezwhut:BAABLgAECn8zAAICAAgJ6BPQAABzAQACAAgJ6BPQAABzAQAAAA==.',
Ea='Earthborn:BAAALgAECgcJAQAAAA==.',
Ec='Echinopsis:BAAALgAECgYJBgAAAA==.',
Ei='Eilyn:BAABLgAECn9CAAIHAAkJthZUNwAkAgAHAAkJthZUNwAkAgAAAA==.',
El='Elena:BAAALgAECgQJBgABLgAECgkJMgADACIkAA==.Elesis:BAAALgADCgQJBAAAAA==.Ellida:BAABLgAECn8aAAIbAAcJMxGQIwC7AQAbAAcJMxGQIwC7AQAAAA==.Elystraeya:BAABLgAECn8iAAMaAAkJrAIN4gBzAAAaAAkJJgIN4gBzAAAdAAkJdQFdZABFAAAAAA==.',
Em='Emastoned:BAAALgAECgYJEAAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAABLgAECn8iAAMSAAkJPR5kBAA4AgASAAgJIB9kBAA4AgARAAgJBhpOQwDRAQAAAA==.',
Fa='Fangmage:BAABLgAECn8UAAMeAAcJbQ8RCAAVAQAeAAYJhRARCAAVAQAJAAYJ2wjO0QDvAAAAAA==.Fayker:BAAALgAECggJDQAAAA==.Fazlain:BAABLgAECn8oAAIMAAgJiR7NKAA7AgAMAAgJiR7NKAA7AgAAAA==.',
Fe='Feldraca:BAAALgAECgEJAQAAAA==.Felestis:BAAALgAECgYJCQAAAA==.Felnir:BAAALgAECgMJBAABLgAECgkJGQARALsJAA==.',
Fi='Fighter:BAAALgADCgEJAQABLgAFFAUJGQAPAHoUAA==.',
Fl='Fluffydragon:BAACLgAFFH8SAAIfAAQJOBuZFgArAQAfAAQJOBuZFgArAQAuAAQKfyYAAx8ACQkkHDUFAMUCAB8ACQkkHDUFAMUCABwABQnnB2QoAN0AAAAA.',
Fr='Friartuck:BAAALgAECgkJEgABLgAFFAMJDQAMAAgeAA==.Frosteez:BAAALgAECgEJAQABLgAECgYJEwAFAAAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgAECgEJAQAAAA==.Furryem:BAABLgAECn8mAAMBAAkJDyXGAQC8AwABAAkJDyXGAQC8AwAgAAMJGyJaHAAoAQAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
['Fô']='Fôxx:BAAALgAECggJBgAAAA==.',
Ga='Galaena:BAAALgAECgcJBwAAAA==.Galvvatron:BAAALgAECgYJBgAAAA==.Ganden:BAABLgAECn9DAAICAAkJXiExAADLAgACAAkJXiExAADLAgAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAACLgAFFH8MAAIHAAQJQxJeRwAdAQAHAAQJQxJeRwAdAQAuAAQKf0oAAgcACQlHGqQBAI8BAAcACQlHGqQBAI8BAAAA.Gatelinka:BAAALgAECggJEgABLgAFFAQJEgAfADgbAA==.Gateto:BAABLgAECn8tAAMOAAkJTiDnCQDaAgAOAAkJTiDnCQDaAgAhAAQJiBB9XgDJAAABLgAFFAQJEgAfADgbAA==.',
Ge='Genfindel:BAAALgADCgYJBgAAAA==.Getinthevan:BAAALgADCgcJBwAAAA==.',
Gh='Ghaghlin:BAAALgADCgQJBAAAAA==.',
Gi='Gidden:BAAALgAECgYJDAAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Gl='Glynistann:BAAALgAECggJBgAAAA==.',
Gn='Gnomechomsky:BAAALgADCggJDAAAAA==.',
Go='Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgkJDgAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.Grindcore:BAAALgAECgUJCAAAAA==.Grogon:BAAALgAECgIJAgAAAA==.',
Gu='Gundox:BAAALgAECggJBgAAAA==.',
Gw='Gwenneth:BAAALgAECgUJBQAAAA==.',
['Gú']='Gúr:BAAALgAECgcJCgAAAA==.',
Ha='Halfordin:BAAALgADCgYJBgAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8rAAISAAkJ9BXwBgDtAQASAAkJ9BXwBgDtAQAAAA==.Helsreach:BAAALgAECgEJAQAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.Hoshi:BAAALgAECgEJAQAAAA==.',
Hr='Hrungnir:BAAALgAECgUJCAAAAA==.Hruoth:BAAALgAECgEJAQAAAA==.',
Hu='Hunt:BAABLgAECn8YAAMMAAYJ1RcuhQA0AQAMAAYJNBcuhQA0AQANAAQJsw3cXQDKAAAAAA==.Huntinbub:BAABLgAECn9KAAMMAAkJsBJpAQDFAQAMAAkJsBJpAQDFAQANAAEJzQAxmgAZAAAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgkJBAAAAA==.',
In='Instaque:BAAALgAECgUJBQAAAA==.',
Ir='Irim:BAAALgAFFAMJBAAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgAECggJEAABLgAFFAUJHAAXAPUeAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAFAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8bAAIaAAYJDBaaOABCAQAaAAYJDBaaOABCAQAuAAQKfyQAAxoACAmYIeARAPACABoACAmYIeARAPACAB0AAglECPthAFoAAAAA.Izlaar:BAAALgAECgMJAwAAAA==.Izzytt:BAAALgAECgUJCQAAAA==.',
Ja='Jacenskie:BAABLgAECn8jAAIXAAkJbBIXMwB/AQAXAAkJbBIXMwB/AQAAAA==.Jacob:BAAALgAECgQJDQAAAA==.Jadedbabe:BAAALgAECgYJCAAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.Jexter:BAAALgADCgIJAgAAAA==.',
Ji='Jimmyjams:BAAALgAECgYJBwABLgAFFAQJGAAJABcaAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Johncena:BAAALgAECgYJBgAAAA==.Joppa:BAAALgAECgMJBQABLgAFFAcJGgAbALAaAA==.Joyvimon:BAAALgAECgYJDwAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8aAAIiAAgJdwvWlQA8AQAiAAgJdwvWlQA8AQAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAFAAAAAA==.',
Kh='Khal:BAACLgAFFH8VAAMEAAYJyxuHCQBYAQAEAAYJyxuHCQBYAQAcAAIJEgemBgClAAAuAAQKfxUAAxwACQkBIL4OAO8BAAQABwmCGvgXABMCABwABgnGI74OAO8BAAAA.Khornedaemon:BAAALgAECgQJBQAAAA==.',
Ki='Kickstarter:BAAALgAFFAIJAwAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kilysta:BAAALgAECgEJAQAAAA==.Kiy:BAAALgAECgkJEQAAAA==.',
Kn='Knìghtmare:BAAALgADCgcJEwAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAABLgAECn8bAAIRAAkJwwO+mgAIAQARAAkJwwO+mgAIAQAAAA==.Kronas:BAAALgAECgcJDgAAAA==.',
Ku='Kurosaki:BAABLgAECn8ZAAIaAAkJfxu3PAABAgAaAAkJfxu3PAABAgAAAA==.',
La='Lazyheal:BAACLgAFFH8ZAAQPAAUJehRoHgBlAQAPAAUJ5hJoHgBlAQAQAAIJVhSpDACZAAAbAAIJfAC7QQAyAAAuAAQKfx8ABBAACQl+G+YNAIgCABAACQl+G+YNAIgCAA8ABAlUBrE/ALEAABsAAgkgBi5YAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAUJGQAPAHoUAA==.',
Le='Leetsteve:BAAALgADCgYJCwAAAA==.Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8rAAIQAAcJ/RpEBgD2AQAQAAcJ/RpEBgD2AQAuAAQKfzQAAxAACQnOIKYDAB8DABAACQnOIKYDAB8DABsAAwktCxRvAGUAAAAA.Leomoon:BAAALgAECgMJCAAAAA==.Leshy:BAAALgAECgYJDAAAAA==.Levite:BAABLgAECn8eAAMQAAYJqxtfIAC/AQAQAAYJqxtfIAC/AQAPAAUJGhLpPwAMAQAAAA==.Lewval:BAAALgAECgEJAgAAAA==.',
Li='Lickytung:BAAALgAECgEJAQAAAA==.Lightwork:BAAALgAECgEJAQAAAA==.Lilara:BAABLgAECn8ZAAIRAAgJzAehjAAhAQARAAgJzAehjAAhAQAAAA==.Linthsong:BAAALgAECgYJCgABLgAECgkJJwAQACYVAA==.Lionknite:BAACLgAFFH8QAAIiAAQJ+Q9eDgCfAAAiAAQJ+Q9eDgCfAAAuAAQKfy0AAiIACQnqG+AxADcCACIACQnqG+AxADcCAAAA.Lionshame:BAAALgAECgUJBQAAAA==.Liontabu:BAAALgAECgQJBgAAAA==.Liorii:BAAALgAECgEJAwAAAA==.Liteshocklet:BAAALgAECgIJAwABLgAFFAUJGQAPAHoUAA==.Littledung:BAAALgAECgMJAwAAAA==.Liwellan:BAAALgAECgcJBwAAAA==.',
Lo='Looting:BAABLgAECn8tAAIjAAgJlhQmCADMAQAjAAgJlhQmCADMAQAAAA==.Loving:BAAALgAECgIJBQAAAA==.',
Lu='Lucky:BAAALgAECgEJAQAAAA==.Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAACLgAFFH8JAAIBAAMJgwgkSwCQAAABAAMJgwgkSwCQAAAuAAQKfyEAAwEACAnuCwhdADsBAAEACAnuCwhdADsBACAAAQkoAoFlABkAAAAA.',
Ma='Mageko:BAAALgAECgEJBgAAAA==.Mageroni:BAAALgAECgcJCAABLgAECgkJIAAUADAWAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAFAAAAAA==.Makarion:BAABLgAECn8WAAIMAAgJxQtzegBLAQAMAAgJxQtzegBLAQAAAA==.Malvina:BAAALgAFFAEJAQAAAA==.Maoli:BAABLgAECn8UAAMHAAQJLhX9/gC5AAAHAAMJGhX9/gC5AAAIAAQJHguRaACUAAAAAA==.Marcelius:BAAALgAECgEJAgAAAA==.Markeleth:BAAALgAECgYJBgABLgAECgkJQwAGAHMcAA==.Marohen:BAAALgADCgYJBgAAAA==.Matsumoto:BAAALgAECgEJAwAAAA==.Mauka:BAABLgAECn8tAAMBAAgJUg2rRgB1AQABAAgJUg2rRgB1AQACAAYJQBTdOABUAQAAAA==.Mauzer:BAAALgAECgEJAwABLgAECgkJPgAdAAIcAA==.',
Mc='Mcfallen:BAAALgAECgIJAgAAAA==.Mcksquizy:BAABLgAECn8nAAIiAAkJUh4UMAB3AgAiAAkJUh4UMAB3AgAAAA==.Mclinkdink:BAAALgADCgkJCQAAAA==.Mcscrotie:BAABLgAECn8UAAIiAAgJQgZPtwAJAQAiAAgJQgZPtwAJAQAAAA==.',
Me='Mes:BAABLgAECn8jAAIhAAkJghvFGwADAgAhAAkJghvFGwADAgAAAA==.Metatrøn:BAAALgADCgkJDwAAAA==.',
Mi='Mimmi:BAAALgAECgUJEwABLgAECgkJPgAdAAIcAA==.Mishri:BAACLgAFFH8VAAIaAAUJCSPSJQCWAQAaAAUJCSPSJQCWAQAuAAQKfzQAAhoACQn2JIMEAD8DABoACQn2JIMEAD8DAAAA.',
Mo='Monbonestorm:BAAALgAFFAIJAgABLgAECggJGgAaAIgUAA==.Mooittooit:BAAALgAECgcJCgAAAA==.Moonsorrow:BAAALgAECgEJAQAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAABLgAECn8+AAMdAAkJAhxiCgCCAgAdAAkJAhxiCgCCAgAkAAIJURqXLgBIAAAAAA==.',
My='Mykana:BAABLgAECn8XAAMHAAYJPwja/gC5AAAHAAYJPwja/gC5AAAGAAQJ0wIuNgBrAAAAAA==.Myodieboy:BAAALgAECgIJAgAAAA==.Mywifesaidno:BAAALgADCggJCAAAAA==.',
Na='Nakabeam:BAABLgAECn8vAAIaAAkJIhZ8NAD0AQAaAAkJIhZ8NAD0AQAAAA==.Nakatwin:BAABLgAECn8YAAIaAAcJJhXmWACXAQAaAAcJJhXmWACXAQABLgAECgkJLwAaACIWAA==.Naklek:BAABLgAECn8hAAMgAAgJBh6TBgCOAgAgAAgJBh6TBgCOAgAYAAEJYgtiNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAFAAAAAA==.',
Ni='Nicked:BAECLgAFFH8aAAIMAAcJ1xUWHwCIAQAMAAcJ1xUWHwCIAQAuAAQKfyMAAwwACQmtH5sOAMYCAAwACQmtH5sOAMYCAA0ABAl0BlRpAJkAAAAA.Nika:BAAALgAECgYJCgAAAA==.Niraleth:BAAALgAECgMJAwAAAA==.Nistik:BAABLgAECn8oAAMQAAkJmAkHLwBWAQAQAAkJmAkHLwBWAQAbAAEJ0wHeawAaAAAAAA==.',
No='Noriala:BAAALgAECgYJCAABLgAECgkJMwAJAC0kAA==.Nozomí:BAAALgAECgUJBQAAAA==.',
Ob='Obergefel:BAAALgAECgEJAQAAAA==.',
Op='Ophiuchus:BAABLgAECn8ZAAIRAAkJuwmKZQBzAQARAAkJuwmKZQBzAQAAAA==.',
Or='Orcdung:BAAALgAECgEJAQAAAA==.',
Os='Ostpeppar:BAAALgADCgUJEAAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAABLgAECn8XAAQIAAgJ7xRONwBxAQAIAAcJeRRONwBxAQAGAAgJeA/0HgARAQAHAAEJcwNryQEfAAABLgAECgkJIAAUADAWAA==.Pamelina:BAAALgADCgUJFAAAAA==.Pandaexpress:BAAALgAECgYJBgABLgAFFAUJHAAXAPUeAA==.Panzerfäust:BAAALgAECgYJEwAAAA==.Pawrina:BAAALgAFFAEJAQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgAECgIJAwAAAA==.Pestis:BAAALgAECgQJBAAAAA==.Pewpewbambam:BAAALgAECgUJBQAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAABLgAECn8uAAMHAAkJwBZ9QgD/AQAHAAkJwBZ9QgD/AQAIAAQJzgh5ZgCbAAAAAA==.Philster:BAAALgAFFAIJBAAAAA==.',
Pi='Pilfering:BAAALgADCgQJBAAAAA==.',
Pl='Plumpt:BAAALgAECgcJEwAAAA==.',
Po='Poochieboo:BAAALgADCgQJBAAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAABLgAECn8kAAIQAAkJRRX0GAAEAgAQAAkJRRX0GAAEAgAAAA==.Punchem:BAAALgADCgcJBwABLgAECgkJJgABAA8lAA==.Punchykicky:BAAALgAECgMJAwABLgAECgkJQwAGAHMcAA==.Purex:BAABLgAECn8dAAIjAAkJKQYwCgCSAQAjAAkJKQYwCgCSAQAAAA==.',
Py='Pyria:BAAALgADCgUJCAAAAA==.',
['Pé']='Pérrywinklé:BAAALgAFFAEJAgAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAABLgAECn8UAAIGAAgJ4BoNDgDjAQAGAAgJ4BoNDgDjAQAAAA==.Rathus:BAABLgAECn8oAAIRAAcJBh/vNAAFAgARAAcJBh/vNAAFAgAAAA==.Rawdata:BAACLgAFFH8OAAMlAAMJXQmYEAC+AAAlAAMJXQmYEAC+AAAOAAMJwApHWgCYAAAuAAQKfykAAyUACQk5FYMRAJwBACUACQk5FYMRAJwBAA4ACAkvD1RCAHgBAAAA.Razenka:BAAALgAECgIJAgAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8gAAIMAAgJqRetPQC4AQAMAAgJqRetPQC4AQABLgAECgkJKAAIAPceAA==.Rebeka:BAABLgAECn8oAAIIAAkJ9x4nCAAJAwAIAAkJ9x4nCAAJAwAAAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgcJEQABLgAECgkJHwAUAPgOAA==.Reniel:BAAALgAECgUJBgABLgAECgkJOAAGACQVAA==.Ressie:BAAALgAECgQJCQAAAA==.Reston:BAAALgAECgYJBgABLgAFFAMJAwAFAAAAAA==.Reverendlion:BAABLgAECn8WAAIbAAgJ7BbaIAC/AQAbAAgJ7BbaIAC/AQAAAA==.',
Ri='Riyu:BAAALgADCgEJAgAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.Rule:BAAALgAECggJBgAAAA==.',
Ry='Ryblade:BAABLgAFFH8LAAIHAAMJMAuodwDGAAAHAAMJMAuodwDGAAABLgAFFAUJHQAHACUVAA==.',
Sa='Saiko:BAAALgAECgYJCAABLgAFFAUJGQAmAFkNAA==.Sainthealz:BAAALgAECgEJAgAAAA==.Saladcake:BAABLgAECn80AAIJAAkJExYlAQDXAQAJAAkJExYlAQDXAQAAAA==.Salleane:BAACLgAFFH8QAAIHAAQJtA3bCACnAAAHAAQJtA3bCACnAAAuAAQKfxoAAgcACQmOFTNeAMkBAAcACQmOFTNeAMkBAAAA.Samgompers:BAAALgADCgIJAgAAAA==.Sampal:BAABLgAECn9DAAMGAAkJcxwYCABYAgAGAAgJjx4YCABYAgAHAAEJqw1CewFAAAAAAA==.Sampriest:BAABLgAECn80AAMQAAkJtSBmBQAlAwAQAAkJtSBmBQAlAwAPAAEJpxBSewAwAAABLgAECgkJQwAGAHMcAA==.Samwield:BAECLgAFFH8hAAInAAUJDiLOFQBdAQAnAAUJDiLOFQBdAQAuAAQKf0MABCcACQn1IdwFANICACcACQn1IdwFANICACMAAwlCGEsTAM0AACgAAQnUClkmACsAAAAA.Sanchoe:BAAALgAFFAEJAQAAAA==.Sanjana:BAAALgAECgQJBQAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.Saucemoe:BAAALgAECgEJAgAAAA==.',
Se='Seireitei:BAABLgAECn80AAMOAAkJpRtWFACpAgAOAAkJpRtWFACpAgAhAAEJIAY9uwAiAAAAAA==.Selaheal:BAABLgAECn9BAAIbAAkJ3hfkEwAwAgAbAAkJ3hfkEwAwAgAAAA==.Seraath:BAACLgAFFH8nAAIkAAcJVxlwAQDSAQAkAAcJVxlwAQDSAQAuAAQKfyYAAyQACQn3IZAAAGQDACQACQn3IZAAAGQDABoAAQkAAJDSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.Serius:BAAALgAECgMJAwAAAA==.',
Sh='Shadowskull:BAAALgADCgkJFQAAAA==.Shadowydream:BAAALgAECgMJAwAAAA==.Shadwkllr:BAABLgAECn8VAAMhAAYJtw5jUQDyAAAhAAYJtw5jUQDyAAAOAAIJ3g5fuQBaAAAAAA==.Shamloo:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAABLgAECn8XAAISAAYJQiBGCADKAQASAAYJQiBGCADKAQAAAA==.Shortie:BAAALgADCggJDwAAAA==.',
Si='Sinister:BAABLgAFFH8HAAIdAAQJ6xblDgAtAQAdAAQJ6xblDgAtAQAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skid:BAAALgADCgEJAQAAAA==.Skies:BAAALgAECgEJAgABLgAECgcJCAAFAAAAAA==.',
Sn='Sneakyhoof:BAAALgADCgcJBwAAAA==.Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgAECgYJDgAAAA==.',
Ss='Ssteroidss:BAAALgAECgIJBAAAAA==.',
St='Stabbem:BAAALgADCgEJAQABLgAECgkJJgABAA8lAA==.Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBQAAAA==.Stepfist:BAAALgAFFAMJAwABLgAFFAQJGAAJABcaAA==.Stergertha:BAAALgAECgEJAQABLgAFFAMJBQAhAM0QAA==.Stersèbuk:BAAALgAECgEJAQABLgAFFAMJBQAhAM0QAA==.Stervana:BAACLgAFFH8KAAIEAAQJjxp+KwAYAQAEAAQJjxp+KwAYAQAuAAQKfy0AAgQACQl0IOIDAFoDAAQACQl0IOIDAFoDAAEuAAUUAwkFACEAzRAA.Stickytoes:BAAALgADCgYJBgAAAA==.Stilettoes:BAAALgADCgIJAgAAAA==.Stormyknight:BAABLgAECn8sAAMfAAkJ3g5EFgBqAQAfAAkJ3g5EFgBqAQAcAAcJOwtMEwDWAAAAAA==.Stærk:BAACLgAFFH8FAAIhAAMJzRDgMwDAAAAhAAMJzRDgMwDAAAAuAAQKfxQAAiEABwluF9EmALUBACEABwluF9EmALUBAAEuAAUUAwkFACEAzRAA.',
Su='Sundemonhunt:BAAALgAECgMJAwAAAA==.Sunnmonk:BAAALgADCgQJBAAAAA==.Sunpally:BAAALgAFFAEJAQAAAA==.Sunwrath:BAAALgAECgcJCAAAAA==.Susmonk:BAAALgAECgQJBQAAAA==.Suspectedd:BAABLgAFFH8KAAIJAAMJmxJkLwD5AAAJAAMJmxJkLwD5AAABLgAFFAcJKgAKAKckAA==.Suswar:BAACLgAFFH8qAAIKAAcJpyT/AgBdAgAKAAcJpyT/AgBdAgAuAAQKfzAAAgoACQnIJJoAALgDAAoACQnIJJoAALgDAAAA.Suvulaan:BAABLgAECn9IAAMfAAkJXAoFGwArAQAfAAgJ7gcFGwArAQAEAAkJPwUtRAAZAQAAAA==.',
Sw='Swifix:BAAALgAECgYJBgAAAA==.Swordsmyth:BAAALgAECgUJBQAAAA==.',
Ta='Tacostand:BAACLgAFFH8bAAIaAAYJKhW/EABJAQAaAAYJKhW/EABJAQAuAAQKfzIAAhoACQlNIOUHAEwDABoACQlNIOUHAEwDAAAA.Tamarlane:BAAALgADCgIJAgAAAA==.Tatoo:BAACLgAFFH8NAAIMAAMJCB6QBwDRAAAMAAMJCB6QBwDRAAAuAAQKf0gAAgwACQlyJJMEAEcDAAwACQlyJJMEAEcDAAAA.',
Te='Teeice:BAABLgAECn8iAAIjAAkJdRPEBgD4AQAjAAkJdRPEBgD4AQAAAA==.Teo:BAABLgAECn8jAAIbAAkJmxMgHQDcAQAbAAkJmxMgHQDcAQAAAA==.Tereus:BAAALgAECggJBgAAAA==.Terian:BAAALgAECgkJCAAAAA==.',
Th='Thaodan:BAABLgAECn8aAAIhAAkJAhFlOgBMAQAhAAkJAhFlOgBMAQAAAA==.That:BAAALgAECgEJAgAAAA==.Thekan:BAABLgAECn8bAAIdAAkJlhRYFgDXAQAdAAkJlhRYFgDXAQAAAA==.Theriot:BAACLgAFFH8GAAMHAAMJuRDAbQDVAAAHAAMJuRDAbQDVAAAGAAIJmAKCFgBHAAAuAAQKfzAABAcACQnbHX46ABkCAAcACQnbHX46ABkCAAYABgkIDNkpAMsAAAgAAQkzCEegACgAAAAA.Thianá:BAABLgAECn8cAAIOAAgJMQwcUQBuAQAOAAgJMQwcUQBuAQAAAA==.Thypriest:BAAALgAECgEJAQAAAA==.Thüclides:BAAALgAECgcJAgAAAA==.',
Ti='Tiermoghuen:BAAALgAECgkJCQAAAA==.Tikidragoona:BAAALgAECgQJBgAAAA==.Timberdoodle:BAAALgAECgMJAwAAAA==.Timtamslam:BAAALgAECgYJDAAAAA==.Tinkerspell:BAABLgAECn8gAAIBAAkJVxNKLwDmAQABAAkJVxNKLwDmAQAAAA==.Tinkiebella:BAAALgAECgEJAgABLgAECgkJIAABAFcTAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
Tl='Tlitlitzin:BAAALgAECgQJCAAAAA==.',
To='Tobivoker:BAAALgAECgQJBQAAAA==.Toosus:BAABLgAFFH8PAAIVAAQJVSHyIQDbAAAVAAQJVSHyIQDbAAABLgAFFAcJKgAKAKckAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAACLgAFFH8HAAIlAAQJYQcMDQDwAAAlAAQJYQcMDQDwAAAuAAQKfxoAAiUACAkrFG0KACoCACUACAkrFG0KACoCAAAA.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgQJBwAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Totec:BAAALgAECgkJCgAAAA==.',
Tr='Treatimus:BAAALgADCgMJAwABLgAECgkJQwAbAH8kAA==.Treesum:BAAALgADCgQJBAAAAA==.Trolldung:BAAALgAECgQJBwAAAA==.Truffaut:BAAALgAECgEJAQAAAA==.',
Tt='Tturtle:BAACLgAFFH8YAAIHAAcJ3gjAMwBIAQAHAAcJ3gjAMwBIAQAuAAQKfyUAAgcACQl+Fd8wAF8CAAcACQl+Fd8wAF8CAAAA.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Tw='Twoblock:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tystraz:BAAALgAECgYJDwAAAA==.',
Ud='Udúnnaur:BAAALgADCggJDgAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Unclebuck:BAAALgADCgYJCQAAAA==.Undermage:BAAALgADCgQJBAAAAA==.Unholysam:BAEALgAECgcJEAABLgAFFAUJIQAnAA4iAA==.',
Va='Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vecna:BAAALgAECgQJBgABLgAECgYJCAAFAAAAAA==.Vector:BAAALgAECgYJCAAAAA==.Velata:BAABLgAECn8cAAIJAAUJWw9k4ADaAAAJAAUJWw9k4ADaAAAAAA==.Velvethunda:BAAALgAECgYJBgAAAA==.Verdugo:BAAALgAECgUJDwAAAA==.Verite:BAABLgAECn8bAAMiAAcJzQOKFwGPAAAiAAcJxwKKFwGPAAAZAAMJOgUEFABTAAAAAA==.',
Vi='Vicar:BAAALgADCggJDgAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAABLgAECn8jAAIXAAkJ9RtmEwBWAgAXAAkJ9RtmEwBWAgAAAA==.',
Vo='Vodka:BAAALgADCgcJFQAAAA==.Voelva:BAAALgAFFAIJAgAAAA==.Voidedge:BAABLgAECn8lAAMSAAcJxQ+BHQC8AAARAAcJjQ0YdgBxAQASAAUJBxGBHQC8AAAAAA==.Voidgazer:BAAALgAECgYJDAAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.Voltage:BAAALgAECgEJAQAAAA==.',
Vy='Vynivar:BAAALgAECgEJAgAAAA==.Vynlan:BAAALgAECgQJBAABLgAFFAcJJwADAOUkAA==.',
Wa='Warlockboi:BAAALgAECgQJBAAAAA==.',
We='Wes:BAABLgAECn89AAIjAAkJvRqHAwB4AgAjAAkJvRqHAwB4AgAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willybcastin:BAAALgAFFAEJAQABLgAFFAgJJwAiAAAiAA==.Willybwankin:BAACLgAFFH8nAAIiAAgJACKbAABrAgAiAAgJACKbAABrAgAuAAQKfykAAiIACQkxJsoAAOEDACIACQkxJsoAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAABLgAECn8VAAIGAAkJsgv3IQD4AAAGAAkJsgv3IQD4AAAAAA==.',
Wy='Wylalena:BAAALgADCgUJBQAAAA==.Wyvern:BAABLgAECn8gAAIRAAkJFA70UgCjAQARAAkJFA70UgCjAQAAAA==.',
Xa='Xanstar:BAAALgAECgEJAQAAAA==.Xanthion:BAAALgAECgUJCAAAAA==.Xarinn:BAAALgADCgEJAQAAAA==.',
Yo='Yodapopz:BAAALgADCgYJBgAAAA==.',
Za='Zacarly:BAACLgAFFH8FAAMBAAMJzANGUwB3AAABAAMJzANGUwB3AAACAAEJ8wFdVgApAAAuAAQKfxsAAwEACAkAGnAaAHICAAEACAkAGnAaAHICAAIAAgloAjqqABQAAAAA.Zalarian:BAAALgAECgYJBwABLgAECgkJYQAJADsjAA==.Zalmage:BAABLgAECn9hAAMJAAkJOyMiCgApAwAJAAkJOyMiCgApAwApAAIJ5wlqFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgADCgcJDgAAAA==.Zeseroth:BAACLgAFFH8mAAIHAAcJQB0ODQAQAgAHAAcJQB0ODQAQAgAuAAQKfycAAgcACQmkIywDAKMDAAcACQmkIywDAKMDAAAA.Zeserotho:BAAALgAFFAEJAQAAAA==.',
Zy='Zyn:BAACLgAFFH8MAAIQAAQJ1SQuDQB3AQAQAAQJ1SQuDQB3AQAuAAQKfyUAAxAACQndIBEGAO4CABAACQndIBEGAO4CABsABAllEzByAF0AAAAA.',
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
