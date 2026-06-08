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

local lookup = {'DemonHunter-Havoc','DeathKnight-Blood','Paladin-Protection','Mage-Frost','Mage-Fire','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Warrior-Fury','Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Warrior-Arms','Priest-Discipline','DemonHunter-Devourer','Monk-Windwalker','Druid-Restoration','Hunter-Survival','Druid-Balance','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaylasecura:BAACLgAFFH8VAAIBAAQJOx2HCQBVAQABAAQJOx2HCQBVAQAuAAQKfz0AAgEACQkuJLACACoDAAEACQkuJLACACoDAAAA.',
Ab='Absinth:BAABLgAFFH8FAAICAAMJVBRgIADWAAACAAMJVBRgIADWAAABLgAFFAQJDgADAHAMAA==.Absolutezero:BAACLgAFFH8OAAMEAAQJdBpISgBFAQAEAAQJdBpISgBFAQAFAAIJWwLpBABgAAAuAAQKfzYAAwQACAnRIBktAF4CAAQACAmmIBktAF4CAAYABAmFHVMKANEAAAAA.',
Ad='Advïl:BAAALgAECgQJBAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Alder:BAAALgADCgEJAgAAAA==.Aletstrasza:BAACLgAFFH8UAAIHAAQJ4xBZGQDpAAAHAAQJ4xBZGQDpAAAuAAQKf0UAAwcACQlHH6YDAAADAAcACQlHH6YDAAADAAgAAQluBRqSACgAAAAA.Alexjuander:BAABLgAECn8fAAQJAAgJlRISFAAdAQAKAAgJbwj2gwAsAQAJAAYJAhMSFAAdAQALAAQJqg3SHQCwAAAAAA==.Alexsander:BAABLgAECn8YAAMIAAYJJxHGRAAMAQAIAAYJJxHGRAAMAQAMAAIJNgbUIABDAAAAAA==.Allysah:BAAALgAECgEJAgABLgAFFAQJIAANAJEHAA==.Alphard:BAABLgAECn8/AAMOAAkJsSPxAQA+AwAOAAkJsSPxAQA+AwAPAAEJvBvVHgA5AAAAAA==.',
An='Anelowyn:BAABLgAECn8xAAIQAAkJtRk/DgBsAgAQAAkJtRk/DgBsAgAAAA==.',
Ap='Apocal:BAACLgAFFH8SAAIRAAcJKBWgAQCjAQARAAcJKBWgAQCjAQAuAAQKfxUAAhEACAmnG3gGACsCABEACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Aralgi:BAAALgAECgEJAQAAAA==.Arete:BAABLgAECn8WAAISAAYJ3xLaSAAZAQASAAYJ3xLaSAAZAQAAAA==.Arlandil:BAAALgADCgMJAwAAAA==.Artaimya:BAABLgAECn8VAAIGAAYJoyI4AwDtAQAGAAYJoyI4AwDtAQAAAA==.Artemìs:BAAALgAECgQJBgAAAA==.',
At='Atmosphere:BAAALgAECgUJBwAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgYJCAATAAAAAA==.Aurelian:BAAALgADCgcJBwAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAFFAQJBgAEAJ0EAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgcJDQAAAA==.Babs:BAAALgAECgUJBgAAAA==.Baraden:BAAALgAECgUJDAAAAA==.Basutai:BAABLgAECn8iAAIUAAkJ5CNFAgCCAwAUAAkJ5CNFAgCCAwAAAA==.',
Be='Beanohuntz:BAAALgAECgEJAQAAAA==.Beefstout:BAAALgAECgkJCAAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgYJDwAAAA==.Birgetta:BAACLgAFFH8MAAIVAAQJAAjrRAAUAQAVAAQJAAjrRAAUAQAuAAQKfzMAAxUACQmsEVc3APUBABUACQmsEVc3APUBABYABgltA8cjAIgAAAAA.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIHAAgJNhlHDABxAgAHAAgJNhlHDABxAgABLgAECgkJGQACANkWAA==.Blasphemous:BAAALgAECgEJAwAAAA==.Blee:BAABLgAECn8zAAICAAkJGByxDgATAgACAAkJGByxDgATAgAAAA==.Bleefleenix:BAAALgAECgYJBgAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAATAAAAAA==.Bluffalo:BAAALgADCgEJAQABLgAFFAQJEgAXAHAOAA==.Blâster:BAAALgAECgEJAQAAAA==.',
Bo='Bobodaklown:BAABLgAECn8jAAMNAAkJ9BabOgA5AgANAAkJYhabOgA5AgADAAIJmxV7OABuAAAAAA==.Boomnblood:BAAALgADCgEJAQABLgAFFAQJEwAYADwGAA==.Boomnbrew:BAACLgAFFH8TAAIYAAQJPAYRLwDhAAAYAAQJPAYRLwDhAAAuAAQKfzUAAhgACQkpFPoWAOkBABgACQkpFPoWAOkBAAAA.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8ZAAMWAAkJQAx5GwDHAAAVAAUJAQ8kiwAbAQAWAAcJBwp5GwDHAAAAAA==.',
Br='Brewman:BAACLgAFFH8SAAIZAAQJ3Ru4HgBMAQAZAAQJ3Ru4HgBMAQAuAAQKfzEAAxkACQmQIbwEAFYDABkACQmQIbwEAFYDABgACAnhDWcyAC8BAAAA.Bringtherain:BAAALgAECgEJAQAAAA==.',
Bu='Bubonic:BAABLgAECn8sAAIaAAkJHxY4OAAXAgAaAAkJHxY4OAAXAgAAAA==.Buenasalud:BAABLgAECn8lAAIbAAkJjBuTDQCAAgAbAAkJjBuTDQCAAgAAAA==.',
Ca='Caball:BAAALgAECgEJAgAAAA==.Carcharias:BAAALgAECgYJBwAAAA==.Caylea:BAACLgAFFH8eAAISAAYJrxkEDACTAQASAAYJrxkEDACTAQAuAAQKfywAAhIACAkrHQYZAIMCABIACAkrHQYZAIMCAAAA.',
Ch='Chalis:BAABLgAECn8iAAMLAAcJYB/BCgATAgAKAAYJrB48LAAiAgALAAYJ5h3BCgATAgAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAACLgAFFH8PAAMcAAQJxBj8KQAkAQAcAAQJxBj8KQAkAQAdAAIJrgJxRwBdAAAuAAQKfx8AAxwACAmKFXosAPkBABwACAmKFXosAPkBAB0AAglfBO6WADgAAAAA.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAACLgAFFH8NAAIEAAQJwgv0YgAaAQAEAAQJwgv0YgAaAQAuAAQKfzAAAwQACQksFKBLAPIBAAQACQksFKBLAPIBAAUAAQm6A2ARACsAAAAA.Corleon:BAAALgADCgMJAwAAAA==.Corvus:BAAALgAECgUJDgAAAA==.',
Cr='Crizlock:BAAALgAECgEJAQABLgAECgcJFwAVAEYjAA==.Crowdcontrol:BAABLgAECn8aAAIDAAkJFiCbBQCJAgADAAkJFiCbBQCJAgAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAACLgAFFH8NAAIeAAQJQxZMEQAQAQAeAAQJQxZMEQAQAQAuAAQKfzMAAx8ACQkOFzIMAN4BAB8ACQlZDjIMAN4BAB4ABAmNG5sfACcBAAAA.',
Cu='Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgAAAA==.Cursis:BAAALgAECgIJAgAAAA==.Cushions:BAAALgAECgQJBAAAAA==.',
Da='Daddysixinch:BAABLgAFFH8LAAIaAAUJJRKvYAAqAQAaAAUJJRKvYAAqAQAAAA==.Daelin:BAABLgAECn8zAAMNAAkJ6CPxBQA8AwANAAkJ6CPxBQA8AwAUAAEJJw3JjAAsAAAAAA==.Danye:BAAALgAECgEJAQAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darkcleric:BAAALgADCgYJBgAAAA==.Darknous:BAAALgAECgEJAQAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deante:BAABLgAECn8YAAIgAAYJfgp8PAAOAQAgAAYJfgp8PAAOAQAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathman:BAABLgAECn8ZAAICAAkJ2Ra/DgASAgACAAkJ2Ra/DgASAgAAAA==.Deathrite:BAAALgAFFAEJAQAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCgAAAA==.Demo:BAAALgAFFAMJAwABLgAFFAQJCgAaAFMiAA==.Demonmommy:BAAALgADCgEJAQAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAACLgAFFH8NAAIdAAQJ0gf3KQDiAAAdAAQJ0gf3KQDiAAAuAAQKfygAAh0ACQkTFB0dAOsBAB0ACQkTFB0dAOsBAAAA.',
Dh='Dhchin:BAAALgAFFAEJAQABLgAFFAYJGgAOAO0kAA==.Dhomsak:BAABLgAFFH8PAAIhAAUJaB66LABaAQAhAAUJaB66LABaAQABLgAFFAUJEwAEAD4jAA==.',
Di='Diamonds:BAAALgADCgEJAQAAAA==.Die:BAAALgAECgcJCgAAAA==.Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgYJCAAAAA==.Distrath:BAAALgADCgkJCQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQABLgAFFAYJGgAOAO0kAA==.',
Do='Doadin:BAABLgAECn8sAAMUAAkJoBvCDQCqAgAUAAkJoBvCDQCqAgANAAEJ1gHBXQEgAAAAAA==.Doominatrix:BAACLgAFFH8RAAMKAAQJsgouWwACAQAKAAQJagouWwACAQAJAAEJNAcuJgBEAAAuAAQKfzIAAwoACAm+GEY6AOwBAAoABwm+GEY6AOwBAAkAAQkAAKQqAEoAAAAA.',
Dr='Draggum:BAABLgAECn8eAAMIAAgJ+xkeGwD1AQAIAAgJ+xkeGwD1AQAHAAMJpxBUKACeAAABLgAECgcJIAAEAPEaAA==.Dragune:BAAALgAECgEJAQABLgAECgcJIgALAGAfAA==.Dreadraven:BAABLgAECn9IAAMSAAgJYhWXJgAmAgASAAgJYhWXJgAmAgAfAAEJZQSUfQAiAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8pAAMBAAkJRxRuIQCxAQABAAgJvxRuIQCxAQAhAAgJuBBEZgBNAQABLgAECgEJAQATAAAAAA==.Dreddstorm:BAAALgAECgEJAgAAAA==.Drewuw:BAABLgAECn8bAAIiAAkJwBaOGQAVAgAiAAkJwBaOGQAVAgABLgAECgkJHQAhAJ0bAA==.Druidhams:BAACLgAFFH8TAAIjAAQJnhbDJwAXAQAjAAQJnhbDJwAXAQAuAAQKfzUAAiMACQn+HtAMAO4CACMACQn+HtAMAO4CAAAA.',
Ea='Eamon:BAAALgAFFAEJAQABLgAFFAMJCAAgAKMSAA==.',
Ei='Eightball:BAAALgAECgIJAgAAAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgUJBgAAAA==.Elisha:BAACLgAFFH8gAAINAAQJkQcfUgD5AAANAAQJkQcfUgD5AAAuAAQKf2oAAg0ACQlQG28lAGQCAA0ACQlQG28lAGQCAAAA.Eloquence:BAAALgAECgQJBQAAAA==.Elsyra:BAAALgAECgYJDgAAAA==.',
Er='Erebostro:BAABLgAECn8/AAIVAAkJYxrWHQBoAgAVAAkJYxrWHQBoAgAAAA==.',
Ev='Everclear:BAAALgAECggJDAABLgAFFAQJDgADAHAMAA==.Evillux:BAACLgAFFH8FAAMKAAIJbQWBqQBvAAAKAAIJbQWBqQBvAAALAAEJZAA5KgAiAAAuAAQKfy8AAwoACQm2EC9HAMABAAoACQlHEC9HAMABAAsABQnmDH0qABcBAAAA.',
Ey='Eyeguy:BAABLgAECn8VAAMhAAkJHxyYJwBmAgAhAAkJLBmYJwBmAgABAAQJ+h+0NgAsAQAAAA==.',
Fa='Fathercow:BAACLgAFFH8TAAIgAAQJ0SGgGQB1AQAgAAQJ0SGgGQB1AQAuAAQKfywAAiAACQn3H/MFABsDACAACQn3H/MFABsDAAAA.',
Fi='Fingies:BAACLgAFFH8RAAQKAAQJaBtNRwAqAQAKAAQJrRZNRwAqAQAJAAEJoh7UFwBYAAALAAEJ1RIBIABRAAAuAAQKfz4AAwoACQm9JGUOANMCAAoABwlHJWUOANMCAAsABQmyHkoVAJ8BAAAA.Fistin:BAAALgAECgYJBwAAAA==.',
Fl='Flexyheals:BAAALgADCgYJBgAAAA==.',
Fr='Frieren:BAAALgADCgYJBgAAAA==.',
Fu='Fungies:BAAALgAFFAQJBAABLgAFFAQJEQAKAGgbAA==.Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAACLgAFFH8RAAIVAAQJQBjQKwBMAQAVAAQJQBjQKwBMAQAuAAQKfzQAAxUACQkhIzMJAAYDABUACQkhIzMJAAYDACQABQmiDSo7ANsAAAAA.',
Ga='Gaijin:BAAALgADCgMJAwABLgAFFAMJCAAgAKMSAA==.Galaxsea:BAABLgAECn8YAAIiAAkJ1x1MDQBmAgAiAAkJ1x1MDQBmAgAAAA==.Gargapew:BAAALgAECgIJAgABLgAFFAMJBgAEAMQJAA==.',
Ge='Gerthquake:BAABLgAECn8rAAMdAAkJzRl7EwBEAgAdAAkJzRl7EwBEAgAcAAkJOB7xMgDZAQAAAA==.',
Gf='Gfour:BAABLgAECn8fAAIZAAgJjhx2EwAvAgAZAAgJjhx2EwAvAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.Ghraxx:BAAALgADCgkJCQAAAA==.Ghraxxy:BAAALgAECgkJEQAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Gobø:BAABLgAECn8bAAIVAAcJKwcahwAjAQAVAAcJKwcahwAjAQAAAA==.Goodytwoshoe:BAAALgAECgIJBwAAAA==.',
Gr='Grimmreefer:BAAALgAECgUJBQAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgQJCgAAAA==.',
['Gâ']='Gâlvatron:BAAALgADCgEJAQAAAA==.',
Ha='Hacks:BAAALgADCgcJBwAAAA==.Hakz:BAAALgADCgkJCQAAAA==.',
He='Heart:BAABLgAFFH8HAAMgAAMJtQd6MQCwAAAgAAMJtQd6MQCwAAAQAAEJgAI8OwA0AAABLgAFFAQJCgAaAFMiAA==.Hefferhumper:BAAALgADCgYJBgAAAA==.Help:BAAALgADCgEJAQAAAA==.Helravn:BAAALgAECgIJAgAAAA==.',
Ho='Homlock:BAABLgAFFH8FAAIKAAUJExwTNwBVAQAKAAUJExwTNwBVAQABLgAFFAUJEwAEAD4jAA==.Homsorc:BAACLgAFFH8TAAMEAAUJPiPiBwDlAQAEAAUJPiPiBwDlAQAGAAEJByReBABZAAAuAAQKfyMAAgQACQlLJTMFAK8DAAQACQlLJTMFAK8DAAAA.Homtard:BAABLgAFFH8SAAQWAAgJ4yARBAAvAgAWAAgJ5R8RBAAvAgAkAAQJFh++CgBiAQAVAAEJ/iLdhgBmAAABLgAFFAUJEwAEAD4jAA==.Hope:BAACLgAFFH8FAAIUAAIJHiCDLQC2AAAUAAIJHiCDLQC2AAAuAAQKfzoAAxQACQn3HJEJAOcCABQACQn3HJEJAOcCAA0ABAnnBy0FAaMAAAAA.',
['Hô']='Hôûnd:BAAALgAECgEJAQAAAA==.',
Id='Idun:BAAALgAECgYJCgAAAA==.',
Il='Illiandray:BAABLgAECn8yAAMLAAkJyh1sAgCLAgALAAkJyh1sAgCLAgAKAAgJUgrRiQAiAQAAAA==.Ilswyn:BAAALgADCgYJBgABLgAECgkJOQAhAGElAA==.',
Im='Imu:BAACLgAFFH8KAAMkAAMJoCHdGQDuAAAkAAMJoCHdGQDuAAAVAAEJxhn/jwBNAAAuAAQKfyIABCQABwkOJWUMAFkCACQABwkOJWUMAFkCABYABQk/DfFUAPYAABUAAgmLCs6nAHYAAAEuAAUUBwkeAA0AXyUA.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn85AAIhAAkJYSU7AgBgAwAhAAkJYSU7AgBgAwAAAA==.',
Io='Ionise:BAABLgAECn8kAAIIAAkJKRukDgByAgAIAAkJKRukDgByAgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Iskgard:BAAALgAECgcJBwAAAA==.Isklar:BAACLgAFFH8JAAICAAIJJBzWKQCTAAACAAIJJBzWKQCTAAAuAAQKfy8AAgIACAm4I4UEAAIDAAIACAm4I4UEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAABLgAECn8tAAQIAAkJWh2uGAAKAgAIAAgJ0RuuGAAKAgAMAAUJ0hxJCACiAQAHAAMJbwy0OQCdAAAAAA==.',
Je='Jer:BAABLgAECn8cAAIOAAkJ1RAyFABzAgAOAAkJ1RAyFABzAgAAAA==.',
Ju='Jugernat:BAAALgADCgEJAQAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAFFAMJCAAgAKMSAA==.',
Ka='Kaalo:BAAALgADCgUJBQAAAA==.Kairi:BAAALgAECgYJCAAAAA==.Kammo:BAACLgAFFH8UAAIaAAQJxiCIMQCHAQAaAAQJxiCIMQCHAQAuAAQKf0QAAhoACQkxJr4CAHADABoACQkxJr4CAHADAAAA.Kazypher:BAAALgAECgMJCgAAAA==.',
Ke='Keeah:BAAALgAECgQJCAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAIZAAkJCgfzMQAvAQAZAAkJCgfzMQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAFFAMJCAAgAKMSAA==.Kiwi:BAAALgAFFAEJAQAAAA==.',
Kl='Klingnor:BAAALgADCgkJDgAAAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8SAAIWAAcJ+hTcCQC0AQAWAAcJ+hTcCQC0AQAuAAQKfyMAAhYABwnLIQ0JANwBABYABwnLIQ0JANwBAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwickin:BAAALgAECgUJBwABLgAECgcJIAAEAPEaAA==.Kwikin:BAABLgAECn8gAAIEAAcJ8RqMVQA3AgAEAAcJ8RqMVQA3AgAAAA==.',
Ky='Kyreen:BAABLgAECn8aAAIVAAgJFAviawBdAQAVAAgJFAviawBdAQAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECgkJGAAiANcdAA==.',
La='Laaz:BAACLgAFFH8SAAIhAAQJ1gfsUADpAAAhAAQJ1gfsUADpAAAuAAQKfzYAAiEACQlXEzY3AN4BACEACQlXEzY3AN4BAAAA.Lamalen:BAABLgAECn8UAAINAAcJnxoSYQDBAQANAAcJnxoSYQDBAQAAAA==.Lasercow:BAAALgAECgcJCAABLgAFFAQJEwAgANEhAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Liena:BAAALgADCgkJCwAAAA==.Linthvia:BAAALgAECgYJDgAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgAECgEJAwAAAA==.',
Lo='Locknloaded:BAAALgAFFAEJAQAAAA==.',
Lu='Luciuos:BAABLgAECn8ZAAMlAAkJqwIFWgCcAAAlAAkJqwIFWgCcAAAjAAcJ9QHmmQBzAAAAAA==.Lucreesha:BAAALgAECgUJBQABLgAECgkJHQAhAJ0bAA==.Lukafox:BAACLgAFFH8bAAIcAAYJAR6qDgDUAQAcAAYJAR6qDgDUAQAuAAQKfyAAAxwACQlZH6gHAPoCABwACQlZH6gHAPoCAB0AAQmKAn6WAB0AAAAA.Lunastarvale:BAABLgAECn9GAAIVAAkJBR63EgCxAgAVAAkJBR63EgCxAgAAAA==.',
Ly='Lyruh:BAAALgAECggJCAAAAA==.',
Ma='Macha:BAAALgADCgYJBgAAAA==.Madith:BAACLgAFFH8IAAIhAAMJ3hQxWQDPAAAhAAMJ3hQxWQDPAAAuAAQKfyMAAiEACAlfIMMWAIQCACEACAlfIMMWAIQCAAAA.Magicjamo:BAAALgAECgUJBQAAAA==.Maleficênt:BAAALgAECggJDgABLgAFFAQJEgAXAHAOAA==.Malefisico:BAABLgAECn8lAAMLAAkJ8hLTFAD3AAAKAAkJKBHFbQCFAQALAAUJ3BTTFAD3AAAAAA==.Malgarok:BAABLgAECn8lAAIKAAgJWBygHgCfAgAKAAgJWBygHgCfAgABLgAECgYJEAATAAAAAA==.Mardríft:BAACLgAFFH8MAAIlAAQJBBPdHwAMAQAlAAQJBBPdHwAMAQAuAAQKfzoAAiUACQnYIcsIAL4CACUACQnYIcsIAL4CAAAA.Mazga:BAABLgAECn8+AAImAAkJVBxUBAClAgAmAAkJVBxUBAClAgAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8uAAIkAAkJihiGDQBKAgAkAAkJihiGDQBKAgAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgAECgQJBAAAAA==.Metta:BAABLgAFFH8GAAIhAAQJEwOAZQCvAAAhAAQJEwOAZQCvAAAAAA==.Mezoti:BAACLgAFFH8MAAMIAAQJrwRPOgDNAAAIAAQJrwRPOgDNAAAHAAIJwAHfJwBGAAAuAAQKfxkAAwgACAniDpIvAHABAAgACAniDpIvAHABAAcACAm/CB4YAEcBAAAA.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCgkJEwAAAA==.',
Mo='Moji:BAACLgAFFH8HAAIZAAMJjxEKNwCoAAAZAAMJjxEKNwCoAAAuAAQKfzQAAhkACQn4HHILANECABkACQn4HHILANECAAAA.Monstermayi:BAACLgAFFH8RAAISAAQJ7BSsGwA0AQASAAQJ7BSsGwA0AQAuAAQKfy8AAhIACQnXGNEWADICABIACQnXGNEWADICAAAA.Mooknight:BAABLgAECn8/AAICAAkJ8BV7EQDpAQACAAkJ8BV7EQDpAQAAAA==.Moosen:BAAALgAECgcJBwAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8nAAIiAAgJXBrkGgDMAQAiAAgJXBrkGgDMAQAAAA==.',
Mu='Muggy:BAABLgAECn8+AAIPAAkJeRrsAgCMAgAPAAkJeRrsAgCMAgAAAA==.',
My='Myluutarania:BAAALgAECgcJCwAAAA==.Myrothar:BAABLgAECn8aAAMUAAgJVhbtKwCnAQAUAAcJeBftKwCnAQANAAYJDQPYDAGaAAAAAA==.Mytastical:BAACLgAFFH8GAAIEAAQJnQQsbgD4AAAEAAQJnQQsbgD4AAAuAAQKfykAAgQACQl4F6lvAJUBAAQACQl4F6lvAJUBAAAA.',
['Mæ']='Mæve:BAACLgAFFH8LAAIjAAQJ2Ai+NQDSAAAjAAQJ2Ai+NQDSAAAuAAQKfzMAAyMACQnOGK8bAF8CACMACQnOGK8bAF8CACUABQmNESxGABUBAAAA.',
['Më']='Mëgatron:BAAALgAECgEJAQAAAA==.',
Na='Namalis:BAACLgAFFH8OAAMKAAQJSRubRQAuAQAKAAQJMBqbRQAuAQAJAAEJ9h7DGABXAAAuAAQKfx0ABAoACAkTJQU5ACcCAAoABgkPJQU5ACcCAAsAAgkWIqA8AMIAAAkAAQkAADIhAG0AAAAA.Nanielito:BAACLgAFFH8GAAIEAAMJxAmLgQDOAAAEAAMJxAmLgQDOAAAuAAQKfyUAAgQACQnGHwwaALcCAAQACQnGHwwaALcCAAAA.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8PAAIEAAUJuROIWAAuAQAEAAUJuROIWAAuAQAuAAQKfygAAgQACQmCHGQjAIkCAAQACQmCHGQjAIkCAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
No='Nokoa:BAAALgAECggJCAAAAA==.Nonae:BAABLgAECn8gAAIVAAgJjh0bEgCnAgAVAAgJjh0bEgCnAgAAAA==.Norivari:BAAALgAECgIJAgAAAA==.Nosali:BAAALgADCgkJCQABLgAFFAQJEgAbANYcAA==.Nosliw:BAAALgADCgUJCAAAAA==.Notawarlock:BAAALgADCgMJAwAAAA==.Noxilis:BAAALgAECgEJAQAAAA==.',
Ob='Obiwon:BAAALgAECgYJEQAAAA==.',
Og='Ogsmashsauce:BAAALgAECgEJAQAAAA==.',
Ol='Oldschooler:BAAALgAECggJCAAAAA==.',
Om='Omegá:BAACLgAFFH8OAAIDAAQJcAyaCQDOAAADAAQJcAyaCQDOAAAuAAQKfyIAAgMACQkuFcMQAKsBAAMACQkuFcMQAKsBAAAA.',
Oo='Oopsalldruid:BAAALgAECgUJCQABLgAECgcJIAAEAPEaAA==.',
Op='Optìmusprìme:BAABLgAECn8/AAIeAAkJJh+RBQCzAgAeAAkJJh+RBQCzAgAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Papa:BAACLgAFFH8FAAMJAAIJcB8vHgBQAAAKAAEJRyBGrwBWAAAJAAEJmh4vHgBQAAAuAAQKfzIABAsACQmBIcUCANYCAAsABwlRIcUCANYCAAkACAkrI5sCAJcCAAoABQmhHOBcAIMBAAAA.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAFFAEJAQAAAA==.',
Po='Pockets:BAABLgAECn8uAAIEAAkJExa2RAAHAgAEAAkJExa2RAAHAgAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAABLgAECn8dAAIKAAgJIwPisgDbAAAKAAgJIwPisgDbAAAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAACLgAFFH8IAAMgAAMJoxLSKwDPAAAgAAMJoxLSKwDPAAAQAAIJowiCLQB+AAAuAAQKfzcAAyAACQnjHn8KAL0CACAACQnjHn8KAL0CABAAAgmcEjV7ADgAAAAA.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAECgYJEgAAAA==.',
['Pø']='Pø:BAAALgAFFAEJAQAAAA==.',
Qu='Quantum:BAAALgAECgEJAQAAAA==.Quick:BAAALgAECgEJAgABLgAECgcJIAAEAPEaAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Rangedrhett:BAAALgADCgEJAQAAAA==.Ratchet:BAAALgAECgEJAQAAAA==.Ratha:BAACLgAFFH8SAAIDAAQJYhB2CADhAAADAAQJYhB2CADhAAAuAAQKfzEAAwMACQmqGQMRAKcBAAMACQmqGQMRAKcBAA0ABAkVDNUSAZMAAAAA.Ravener:BAAALgAECgYJBwAAAA==.Razeal:BAABLgAECn8fAAMNAAYJliBFWAC5AQANAAYJPyBFWAC5AQADAAIJKxjiMQCGAAAAAA==.',
Re='Reaper:BAACLgAFFH8KAAIaAAQJUyLVOAB0AQAaAAQJUyLVOAB0AQAuAAQKfx0AAxoABwkPJYMqAE8CABoABwkPJYMqAE8CAAIAAgk+B+BAAEkAAAAA.Reeah:BAAALgADCgkJCQAAAA==.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAABLgAECn8gAAIlAAcJ0QvTPwAAAQAlAAcJ0QvTPwAAAQAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8aAAMOAAYJ7SRaDgCNAQAOAAUJGyVaDgCNAQAPAAIJgRnOCwBpAAAuAAQKfysAAw4ACQlIJUUIAJcCAA4ACAnGJUUIAJcCAA8AAwnpI/4NADoBAAAA.Rokkgar:BAABLgAECn8oAAIdAAkJHhBwJQCvAQAdAAkJHhBwJQCvAQABLgAECgkJLwAPAH0MAA==.Roosterr:BAAALgADCgkJFgAAAA==.',
Ru='Ruwazi:BAAALgAECgYJDwAAAA==.',
Ry='Ryujin:BAAALgAECgUJBwAAAA==.',
Sa='Sainted:BAAALgAECgUJBAAAAA==.Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Secarious:BAABLgAECn8bAAISAAgJnhAdMgB8AQASAAgJnhAdMgB8AQAAAA==.Sediaria:BAAALgAECgkJCQABLgAFFAQJDAAVAAAIAA==.Sehnsucht:BAACLgAFFH8MAAMlAAQJJBJ2IQADAQAlAAQJJBJ2IQADAQAjAAMJfg4vPwCtAAAuAAQKfygAAyMACQktHAkeAE4CACMACQktHAkeAE4CACUAAQkAGqB2AEkAAAAA.Serius:BAAALgAECgQJBAABLgAECgkJHQAhAJ0bAA==.',
Sh='Shmadu:BAAALgAECgcJCwAAAA==.Shockk:BAABLgAECn8gAAMdAAkJGRbNJwCgAQAdAAkJGRbNJwCgAQAcAAMJ4AKOigBpAAAAAA==.Shone:BAAALgAECgUJBQAAAA==.',
Si='Siovhan:BAAALgAECgkJEgAAAA==.',
Sl='Sly:BAACLgAFFH8KAAInAAMJKRviBwDxAAAnAAMJKRviBwDxAAAuAAQKfxUAAicABwkuIIgEACwCACcABwkuIIgEACwCAAEuAAUUBAkKABoAUyIA.',
Sm='Smóóthbói:BAABLgAECn8tAAIEAAkJrhWpQQARAgAEAAkJrhWpQQARAgAAAA==.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn83AAIIAAkJ8BdSEgBHAgAIAAkJ8BdSEgBHAgAAAA==.Soola:BAABLgAECn8fAAMcAAgJoQ2fSwBzAQAcAAgJoQ2fSwBzAQAdAAQJzAx6dQB6AAAAAA==.',
Sp='Spoof:BAAALgAECgIJAgAAAA==.Spoopadin:BAAALgAECgIJBgAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.Sprigg:BAAALgADCgkJCQABLgAECgkJLQAEAK4VAA==.',
St='Stack:BAACLgAFFH8JAAIkAAIJ8hunIQCwAAAkAAIJ8hunIQCwAAAuAAQKfxYAAiQABwmqHZIVAPMBACQABwmqHZIVAPMBAAEuAAUUBAkKABoAUyIA.Stompycouch:BAACLgAFFH8FAAIdAAIJJRFbPQCBAAAdAAIJJRFbPQCBAAAuAAQKfysAAh0ACAnyHDsXAF4CAB0ACAnyHDsXAF4CAAAA.Stoned:BAABLgAECn8nAAMUAAkJJh/uCADhAgAUAAkJJh/uCADhAgANAAMJ3wrDGAGLAAAAAA==.Stonedpriest:BAABLgAECn87AAIbAAkJliA7BwDYAgAbAAkJliA7BwDYAgAAAA==.Stripes:BAAALgADCgUJBQAAAA==.',
Su='Sunreaver:BAABLgAECn8tAAIaAAkJcyOTEwDLAgAaAAkJcyOTEwDLAgAAAA==.Surrëal:BAABLgAECn8ZAAIBAAkJWgw+JgA1AQABAAkJWgw+JgA1AQABLgAFFAQJDAAVAAAIAA==.Surtain:BAACLgAFFH8HAAIlAAMJEAs/MACsAAAlAAMJEAs/MACsAAAuAAQKfx8AAiUACAk4HqMTACwCACUACAk4HqMTACwCAAAA.Suxiv:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetmask:BAABLgAECn8nAAMaAAkJjyNbDAADAwAaAAkJjyNbDAADAwAoAAIJ2BooIwCiAAAAAA==.',
Sx='Sxv:BAAALgAFFAIJAwAAAA==.',
Sy='Syl:BAACLgAFFH8RAAIVAAQJ4xVHMgA+AQAVAAQJ4xVHMgA+AQAuAAQKfy0AAxUACQlyGzogAFsCABUACQlyGzogAFsCABYABQlVCnFZAN8AAAAA.Sylvanäs:BAABLgAECn8UAAIWAAkJ5AsiDQCCAQAWAAkJ5AsiDQCCAQABLgAECgkJMgALAModAA==.',
['Sï']='Sïdëswïpë:BAAALgAECgEJAgAAAA==.',
['Só']='Sóúndwâve:BAAALgAECgEJAgAAAA==.',
Ta='Tahitian:BAABLgAECn8fAAIVAAkJ9w7bQwDKAQAVAAkJ9w7bQwDKAQAAAA==.Tahlreth:BAABLgAECn88AAMEAAkJ4R/4FADWAgAEAAkJ4R/4FADWAgAFAAEJuhkJEABLAAAAAA==.Tandlia:BAAALgAECgUJCQAAAA==.Tanickz:BAABLgAECn8tAAIEAAkJ2BLURQAEAgAEAAkJ2BLURQAEAgAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJLAAdAPscAA==.Tanidgetotem:BAABLgAECn8sAAIdAAkJ+xz8CQD0AgAdAAkJ+xz8CQD0AgAAAA==.Tanya:BAACLgAFFH8SAAIkAAQJ7BaADwA8AQAkAAQJ7BaADwA8AQAuAAQKf0AAAiQACQmKIwEDAAkDACQACQmKIwEDAAkDAAAA.Tayanna:BAABLgAECn8aAAMNAAkJFRx5cQCAAQANAAkJCBx5cQCAAQADAAcJAQj3KADDAAAAAA==.',
Te='Teias:BAACLgAFFH8SAAIbAAQJ1hz7DwA9AQAbAAQJ1hz7DwA9AQAuAAQKfzIAAxsACQn5GhQTAEcCABsACQn5GhQTAEcCABAABgkCHdQlAJUBAAAA.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thuras:BAAALgADCgUJBQABLgAECgMJAwATAAAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8iAAIEAAgJox8fOwAmAgAEAAgJox8fOwAmAgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgADCgUJCAATAAAAAA==.',
Tr='Tricko:BAABLgAECn9DAAIVAAkJwR48EwCtAgAVAAkJwR48EwCtAgAAAA==.Trollskingx:BAABLgAECn8eAAIEAAcJwBacdADpAQAEAAcJwBacdADpAQAAAA==.Trollzy:BAABLgAECn8/AAMmAAkJLyFNAgD0AgAmAAkJLyFNAgD0AgAcAAQJjQmdmwCFAAAAAA==.Trunkmonkey:BAACLgAFFH8JAAIKAAQJIg1kVwALAQAKAAQJIg1kVwALAQAuAAQKfy8AAgoACQlbGoQcAHMCAAoACQlbGoQcAHMCAAAA.Tryne:BAAALgADCgEJAQAAAA==.',
Ts='Tsaagan:BAACLgAFFH8RAAMKAAQJvhafRwAqAQAKAAQJNhafRwAqAQAJAAEJ5RK9HgBQAAAuAAQKfy0ABAoACQkXIS0RAL0CAAoACQkqHy0RAL0CAAkABAkII/4KAIwBAAsABAkHHrQgAE4BAAAA.',
Tu='Tucker:BAABLgAECn8rAAIZAAkJgh0KCQD5AgAZAAkJgh0KCQD5AgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ud='Uddershaman:BAAALgAECgEJAQAAAA==.',
Ul='Ultramagnús:BAAALgAECgEJAgAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAABLgAECn8bAAMaAAcJVBKcdgBuAQAaAAcJVBKcdgBuAQAoAAEJlwpmNQA0AAAAAA==.Under:BAAALgADCgcJDgABLgAECgcJGwAaAFQSAA==.Unparalleled:BAABLgAECn8jAAMHAAcJRwcIHgAAAQAHAAcJRwcIHgAAAQAMAAUJZAoCEgDdAAAAAA==.',
Va='Vaaleros:BAAALgADCgYJBgAAAA==.Valiithria:BAAALgAECgQJBAAAAA==.Valkyruid:BAACLgAFFH8SAAIjAAYJLxBQGgB5AQAjAAYJLxBQGgB5AQAuAAQKfxcAAiMABwnCF4w2AM0BACMABwnCF4w2AM0BAAAA.',
Ve='Vessel:BAAALgAFFAIJAgABLgAFFAQJCgAaAFMiAA==.',
Vi='Vixus:BAAALgAFFAEJAgAAAA==.',
Vx='Vxs:BAAALgAFFAIJAwAAAA==.',
['Vø']='Vøødu:BAAALgAECgYJCwABLgAECgcJGAAcAJEQAA==.',
Wa='Walshidan:BAABLgAECn8aAAIhAAkJ0xCQTgCOAQAhAAkJ0xCQTgCOAQAAAA==.Walshlel:BAAALgADCgkJCQAAAA==.Waywatcher:BAAALgAFFAIJAgAAAA==.',
We='Wenus:BAAALgAECgUJBQAAAA==.',
Wi='Wiccaflame:BAABLgAECn8bAAIEAAkJdSCDFgDLAgAEAAkJdSCDFgDLAgAAAA==.Wiccasham:BAAALgAECgEJAQAAAA==.',
Wu='Wullgan:BAABLgAECn8fAAMgAAkJ2R4CEQBVAgAgAAgJvx4CEQBVAgAQAAcJGBjoKgB0AQAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAABLgAFFH8JAAIHAAQJvhHyFwD/AAAHAAQJvhHyFwD/AAAAAA==.',
Xo='Xole:BAABLgAECn8fAAMhAAgJnxTcVgB2AQAhAAgJnxTcVgB2AQARAAQJIQSEIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8dAAIhAAkJnRuTMAA5AgAhAAkJnRuTMAA5AgAAAA==.Xyrna:BAAALgAECgkJEQABLgAFFAQJEgADAGIQAA==.',
Ya='Yareli:BAABLgAECn8xAAIRAAkJTQgTEAA7AQARAAkJTQgTEAA7AQAAAA==.Yawa:BAABLgAFFH8GAAIaAAIJkQwy0gCHAAAaAAIJkQwy0gCHAAAAAA==.',
Ye='Yeahreally:BAAALgADCgkJCQAAAA==.Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQATAAAAAA==.Zankrah:BAAALgAECgQJBAABLgAFFAQJEgAbANYcAA==.Zarill:BAAALgADCgcJBwAAAA==.Zartman:BAAALgAECgMJBQAAAA==.Zayzoo:BAABLgAECn8UAAIcAAcJHxWPNwDDAQAcAAcJHxWPNwDDAQAAAA==.Zazie:BAABLgAECn8VAAIEAAcJ9QbJwAADAQAEAAcJ9QbJwAADAQAAAA==.',
Ze='Zekröm:BAACLgAFFH8SAAIXAAQJcA5wEgDXAAAXAAQJcA5wEgDXAAAuAAQKfx8AAhcACQkyEsQTAKgBABcACQkyEsQTAKgBAAAA.Zekrøm:BAABLgAECn8dAAIdAAgJjxrvGQBEAgAdAAgJjxrvGQBEAgABLgAFFAQJEgAXAHAOAA==.Zeno:BAACLgAFFH8hAAINAAgJPB8HBAB/AgANAAgJPB8HBAB/AgAuAAQKfxcAAg0ACQkyJfgCAKcDAA0ACQkyJfgCAKcDAAAA.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgADCgkJCQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQATAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQATAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAABLgAECn8vAAIPAAkJfQzrCACqAQAPAAkJfQzrCACqAQAAAA==.',
Zi='Zinbar:BAABLgAECn8YAAIkAAgJHxC5IQCLAQAkAAgJHxC5IQCLAQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAABLgAECn8ZAAQiAAkJahlXEgAiAgAiAAkJPRlXEgAiAgAYAAQJ9BVWVADzAAAZAAEJTQJtcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQATAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAIEAAgJXCBkLwC1AgAEAAgJXCBkLwC1AgAAAA==.Çloudsham:BAAALgAECgEJAgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8qAAQgAAgJ2yEeCQCqAgAgAAgJ2yEeCQCqAgAbAAUJABoGOwBPAQAQAAEJBhgUdgBDAAAAAA==.',
['ßa']='ßaè:BAAALgAECgMJAgABLgAECgYJCgATAAAAAA==.',
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
