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

local lookup = {'DemonHunter-Havoc','DeathKnight-Blood','Paladin-Protection','Mage-Frost','Mage-Fire','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Warrior-Fury','Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warrior-Protection','Warrior-Arms','Priest-Discipline','DemonHunter-Devourer','Monk-Windwalker','Druid-Restoration','Hunter-Survival','Druid-Balance','Druid-Feral','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaylasecura:BAACLgAFFH8VAAIBAAQJOx1ZCwBQAQABAAQJOx1ZCwBQAQAuAAQKfz0AAgEACQkuJBgDACYDAAEACQkuJBgDACYDAAAA.',
Ab='Absinth:BAABLgAFFH8GAAICAAMJHhheIQDcAAACAAMJHhheIQDcAAABLgAFFAQJDgADAHAMAA==.Absolutezero:BAACLgAFFH8QAAMEAAQJdBoCUgBCAQAEAAQJdBoCUgBCAQAFAAIJWwLEBQBgAAAuAAQKfzYAAwQACAnRIOwuAFsCAAQACAmmIOwuAFsCAAYABAmFHeoKAM8AAAAA.',
Ad='Advïl:BAAALgAECgQJBAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Alder:BAAALgADCgEJAgAAAA==.Aletstrasza:BAACLgAFFH8UAAIHAAQJ4xDfGgDgAAAHAAQJ4xDfGgDgAAAuAAQKf0UAAwcACQlHH9IDAP4CAAcACQlHH9IDAP4CAAgAAQluBTOYACgAAAAA.Alexjuander:BAABLgAECn8fAAQJAAgJlRJfFQAcAQAKAAgJbwiBiAAoAQAJAAYJAhNfFQAcAQALAAQJqg0VHwCvAAAAAA==.Alexsander:BAABLgAECn8YAAMIAAYJJxGbRwAIAQAIAAYJJxGbRwAIAQAMAAIJNgbzIQBDAAAAAA==.Allysah:BAAALgAECgEJAgABLgAFFAQJIQANANgHAA==.Alphard:BAABLgAECn8/AAMOAAkJsSMuAgA7AwAOAAkJsSMuAgA7AwAPAAEJvBvVHgA5AAAAAA==.',
Am='Amarri:BAAALgAECgEJAgAAAA==.',
An='Anelowyn:BAABLgAECn8xAAIQAAkJtRkyDwBmAgAQAAkJtRkyDwBmAgAAAA==.',
Ap='Apocal:BAACLgAFFH8SAAIRAAcJKBXtAQCdAQARAAcJKBXtAQCdAQAuAAQKfxUAAhEACAmnG3gGACsCABEACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Aralgi:BAAALgAECgEJAQAAAA==.Arete:BAABLgAECn8WAAISAAYJ3xJYSwAYAQASAAYJ3xJYSwAYAQAAAA==.Arlandil:BAAALgADCgQJBAAAAA==.Artaimya:BAABLgAECn8VAAIGAAYJoyJrAwDqAQAGAAYJoyJrAwDqAQAAAA==.Artemìs:BAAALgAECgQJBgAAAA==.',
At='Ataraxya:BAAALgADCgYJBgAAAA==.Atmosphere:BAAALgAECgUJBwAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgYJCAATAAAAAA==.Aurelian:BAAALgADCgcJBwAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAFFAQJBgAEAJ0EAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgcJDwAAAA==.Babs:BAAALgAECgUJBgAAAA==.Backspin:BAAALgAECgQJBAABLgAECgkJLgAEABMWAA==.Baraden:BAAALgAECgUJDAAAAA==.Basutai:BAABLgAECn8iAAIUAAkJ5COIAgCAAwAUAAkJ5COIAgCAAwAAAA==.',
Be='Beanohuntz:BAAALgAECgEJAQAAAA==.Beefstout:BAAALgAECgkJCAAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgYJDwAAAA==.Birgetta:BAACLgAFFH8NAAIVAAQJIgsuSAAVAQAVAAQJIgsuSAAVAQAuAAQKfzMAAxUACQmsEYk7AO0BABUACQmsEYk7AO0BABYABgltA2ElAIYAAAAA.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIHAAgJNhlHDABxAgAHAAgJNhlHDABxAgABLgAECgkJGQACANkWAA==.Blasphemous:BAAALgAECgEJAwAAAA==.Blee:BAABLgAECn8zAAICAAkJGBzADwANAgACAAkJGBzADwANAgAAAA==.Bleefleenix:BAAALgAECgYJBgAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAATAAAAAA==.Bluffalo:BAAALgADCgEJAQABLgAFFAUJFAAXAHAOAA==.Blâster:BAAALgAECgEJAQAAAA==.',
Bo='Bobodaklown:BAABLgAECn8jAAMNAAkJ9BabOgA5AgANAAkJYhabOgA5AgADAAIJmxXZOgBtAAAAAA==.Boomnblood:BAAALgADCgEJAQABLgAFFAQJFAAYADwGAA==.Boomnbrew:BAACLgAFFH8UAAIYAAQJPAabMQDeAAAYAAQJPAabMQDeAAAuAAQKfzUAAhgACQkpFLMXAOgBABgACQkpFLMXAOgBAAAA.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8ZAAMWAAkJQAzaHADEAAAVAAUJAQ8akQAYAQAWAAcJBwraHADEAAAAAA==.',
Br='Brewman:BAACLgAFFH8UAAIZAAUJPhqkGgCQAQAZAAUJPhqkGgCQAQAuAAQKfzEAAxkACQmQIRQFAFcDABkACQmQIRQFAFcDABgACAnhDRc0ACwBAAAA.Bringtherain:BAAALgAECgEJAQAAAA==.',
Bu='Bubonic:BAABLgAECn8sAAIaAAkJHxYbOwASAgAaAAkJHxYbOwASAgAAAA==.Buenasalud:BAABLgAECn8lAAIbAAkJjBuDDgB8AgAbAAkJjBuDDgB8AgAAAA==.Business:BAAALgAECgEJAQABLgAECgYJEwATAAAAAA==.',
Ca='Caball:BAAALgAECgEJAgAAAA==.Carcharias:BAAALgAECgYJBwAAAA==.Caylea:BAACLgAFFH8eAAISAAYJrxm/DQCSAQASAAYJrxm/DQCSAQAuAAQKfywAAhIACAkrHQYZAIMCABIACAkrHQYZAIMCAAAA.',
Ch='Chalis:BAABLgAECn8iAAMLAAcJYB/BCgATAgAKAAYJrB66LQAgAgALAAYJ5h3BCgATAgAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAACLgAFFH8QAAMcAAQJbhn4KwArAQAcAAQJbhn4KwArAQAdAAIJrgK+TABaAAAuAAQKfyMABBwACAmKFdEuAPYBABwACAmKFdEuAPYBAB0AAwkvCIOBAGgAAB4AAwmzCfoxAGMAAAAA.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAACLgAFFH8QAAIEAAQJwgtSaQAZAQAEAAQJwgtSaQAZAQAuAAQKfzAAAwQACQksFDNQAOgBAAQACQksFDNQAOgBAAUAAQm6A2ARACsAAAAA.Corleon:BAAALgADCgMJAwAAAA==.Corvus:BAAALgAECgUJDgAAAA==.',
Cr='Crizlock:BAAALgAECgEJAQABLgAECgcJFwAVAEYjAA==.Crowdcontrol:BAABLgAECn8aAAIDAAkJFiAFBgCGAgADAAkJFiAFBgCGAgAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAACLgAFFH8QAAIfAAQJQxZkEwADAQAfAAQJQxZkEwADAQAuAAQKfzMAAyAACQkOFzIMAN4BACAACQlZDjIMAN4BAB8ABAmNGwIhACQBAAAA.',
Cu='Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgABLgAECgkJLgAEABMWAA==.Cursis:BAAALgAECgIJAgAAAA==.',
Da='Daddysixinch:BAABLgAFFH8MAAIaAAUJWhX+TwBNAQAaAAUJWhX+TwBNAQAAAA==.Daelin:BAABLgAECn8zAAMNAAkJ6CO3BgA4AwANAAkJ6CO3BgA4AwAUAAEJJw3PkAAsAAAAAA==.Danye:BAAALgAECgEJAQAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darkcleric:BAAALgADCgYJBgAAAA==.Darknous:BAAALgAECgEJAQAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deante:BAABLgAECn8ZAAIhAAYJWgy+OgAjAQAhAAYJWgy+OgAjAQAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathman:BAABLgAECn8ZAAICAAkJ2RbKDwAMAgACAAkJ2RbKDwAMAgAAAA==.Deathrite:BAAALgAFFAEJAQAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCgAAAA==.Demo:BAAALgAFFAMJAwABLgAFFAQJCgAaAFMiAA==.Demonmommy:BAAALgADCgEJAQAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAACLgAFFH8OAAIdAAQJEAuTKwDgAAAdAAQJEAuTKwDgAAAuAAQKfygAAh0ACQkTFJUeAOoBAB0ACQkTFJUeAOoBAAAA.',
Dh='Dhchin:BAAALgAFFAEJAQABLgAFFAcJHAAOAKIkAA==.Dhomsak:BAABLgAFFH8TAAIiAAUJaB6SMgBSAQAiAAUJaB6SMgBSAQABLgAFFAUJGAAEAHMkAA==.',
Di='Diamonds:BAAALgADCgEJAQABLgAECgkJLgAEABMWAA==.Die:BAAALgAFFAMJBAAAAA==.Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgYJCAAAAA==.Distrath:BAAALgADCgkJCQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQABLgAFFAcJHAAOAKIkAA==.',
Do='Doadin:BAABLgAECn8sAAMUAAkJoBvCDQCqAgAUAAkJoBvCDQCqAgANAAEJ1gHBXQEgAAAAAA==.Doominatrix:BAACLgAFFH8SAAMKAAQJsgpMYQD/AAAKAAQJagpMYQD/AAAJAAEJNAcqKQBDAAAuAAQKfzIAAwoACAm+GAA9AOcBAAoABwm+GAA9AOcBAAkAAQkAAKQqAEoAAAAA.',
Dr='Draggum:BAABLgAECn8eAAMIAAgJ+xnvGwD1AQAIAAgJ+xnvGwD1AQAHAAMJpxBUKQCdAAABLgAECgcJIAAEAPEaAA==.Dragune:BAAALgAECgEJAQABLgAECgcJIgALAGAfAA==.Dreadraven:BAABLgAECn9WAAMSAAkJJx4FCQDQAgASAAkJJx4FCQDQAgAgAAMJ6At2YABcAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8pAAMBAAkJRxRuIQCxAQABAAgJvxRuIQCxAQAiAAgJuBCvaQBOAQABLgAECgEJAQATAAAAAA==.Dreddstorm:BAAALgAECgEJAgAAAA==.Drewuw:BAABLgAECn8bAAIjAAkJwBaOGQAVAgAjAAkJwBaOGQAVAgABLgAECgkJHQAiAJ0bAA==.Druidhams:BAACLgAFFH8UAAIkAAQJnhYFKgALAQAkAAQJnhYFKgALAQAuAAQKfzUAAiQACQn+HlwNAO0CACQACQn+HlwNAO0CAAAA.',
Ea='Eamon:BAAALgAFFAEJAQABLgAFFAMJCwAhAMcUAA==.',
Ei='Eightball:BAAALgAECgYJCAABLgAECgkJLgAEABMWAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgUJBgAAAA==.Elisha:BAACLgAFFH8hAAINAAQJ2Af8WAD4AAANAAQJ2Af8WAD4AAAuAAQKf2oAAg0ACQlQGzUoAGACAA0ACQlQGzUoAGACAAAA.Eloquence:BAAALgAECgQJBQAAAA==.Elsyra:BAAALgAECgYJDgAAAA==.',
Er='Erebostro:BAABLgAECn8/AAIVAAkJYxqSIABhAgAVAAkJYxqSIABhAgAAAA==.',
Ev='Everclear:BAAALgAECggJDAABLgAFFAQJDgADAHAMAA==.Evillux:BAACLgAFFH8FAAMKAAIJbQWrsQBtAAAKAAIJbQWrsQBtAAALAAEJZAChLAAiAAAuAAQKfy8AAwoACQm2EG9LALcBAAoACQlHEG9LALcBAAsABQnmDH0qABcBAAAA.',
Ey='Eyeguy:BAABLgAECn8VAAMiAAkJHxyYJwBmAgAiAAkJLBmYJwBmAgABAAQJ+h+0NgAsAQAAAA==.',
Fa='Fadedvoker:BAAALgAFFAEJAQABLgAECgkJHQAQAPobAA==.Fathercow:BAACLgAFFH8UAAIhAAQJ0SGAHABvAQAhAAQJ0SGAHABvAQAuAAQKfywAAiEACQn3H0cGABsDACEACQn3H0cGABsDAAAA.Faultline:BAAALgAECgIJAgABLgAECgkJJAAjALcbAA==.',
Fi='Fingies:BAACLgAFFH8RAAQKAAQJaBthTgAlAQAKAAQJrRZhTgAlAQAJAAEJoh6lGgBWAAALAAEJ1RKgIgBPAAAuAAQKfz4AAwoACQm9JH8PAM8CAAoABwlHJX8PAM8CAAsABQmyHkoVAJ8BAAAA.Fistin:BAAALgAECgYJBwAAAA==.',
Fl='Flexyheals:BAAALgADCgYJBgAAAA==.',
Fr='Frieren:BAAALgADCgYJBgAAAA==.',
Fu='Fungies:BAABLgAFFH8FAAIkAAQJ1goDOADIAAAkAAQJ1goDOADIAAABLgAFFAQJEQAKAGgbAA==.Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAACLgAFFH8SAAIVAAQJQBiKMwBAAQAVAAQJQBiKMwBAAQAuAAQKfzQAAxUACQkhI14KAAEDABUACQkhI14KAAEDACUABQmiDRo9ANcAAAAA.',
Ga='Gaijin:BAAALgADCgMJAwABLgAFFAMJCwAhAMcUAA==.Galaxsea:BAABLgAECn8YAAIjAAkJ1x3yDQBlAgAjAAkJ1x3yDQBlAgAAAA==.Gargapew:BAAALgAECgIJAgABLgAFFAMJBgAEAMQJAA==.',
Ge='Gerthquake:BAABLgAECn8rAAMdAAkJzRmPFABDAgAdAAkJzRmPFABDAgAcAAkJOB48NQDYAQAAAA==.',
Gf='Gfour:BAABLgAECn8fAAIZAAgJjhx2EwAvAgAZAAgJjhx2EwAvAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.Ghraxx:BAAALgADCgkJCQAAAA==.Ghraxxy:BAAALgAECgkJEQAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Gobø:BAABLgAECn8hAAIVAAcJxQdhiQAnAQAVAAcJxQdhiQAnAQAAAA==.Goodytwoshoe:BAAALgAECgIJBwAAAA==.',
Gr='Grimmreefer:BAAALgAECgUJBQAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgQJCgAAAA==.',
['Gâ']='Gâlvatron:BAAALgADCgEJAQAAAA==.',
Ha='Hacks:BAAALgADCgcJBwAAAA==.Hakz:BAAALgADCgkJCQAAAA==.',
He='Heart:BAABLgAFFH8HAAMhAAMJtQdMNQCvAAAhAAMJtQdMNQCvAAAQAAEJgAJIPwA0AAABLgAFFAQJCgAaAFMiAA==.Hefferhumper:BAAALgADCgYJBgAAAA==.Help:BAAALgADCgEJAQAAAA==.Helravn:BAAALgAECgIJAgAAAA==.',
Ho='Homlock:BAABLgAFFH8IAAMKAAUJExwHPQBRAQAKAAUJExwHPQBRAQAJAAEJYBRvHgBRAAABLgAFFAUJGAAEAHMkAA==.Homsorc:BAACLgAFFH8YAAMEAAUJcyTiBwDlAQAEAAUJcyTiBwDlAQAGAAEJByQOBQBWAAAuAAQKfyMAAgQACQlLJTMFAK8DAAQACQlLJTMFAK8DAAAA.Homtard:BAABLgAFFH8SAAQWAAgJ4yBHBQAhAgAWAAgJ5R9HBQAhAgAlAAQJFh8aDABhAQAVAAEJ/iInkgBkAAABLgAFFAUJGAAEAHMkAA==.Hope:BAACLgAFFH8IAAIUAAMJ0hkPJgDrAAAUAAMJ0hkPJgDrAAAuAAQKfzoAAxQACQn3HD8KAOUCABQACQn3HD8KAOUCAA0ABAnnB3IOAaMAAAAA.',
['Hô']='Hôûnd:BAAALgAECgEJAQAAAA==.',
Id='Idun:BAAALgAECgYJCgAAAA==.',
Il='Illiandray:BAABLgAECn8yAAMLAAkJyh2XAgCHAgALAAkJyh2XAgCHAgAKAAgJUgo5jwAcAQAAAA==.Ilswyn:BAAALgADCgYJBgABLgAECgkJOQAiAGElAA==.',
Im='Imu:BAACLgAFFH8KAAMlAAMJoCHUGwDsAAAlAAMJoCHUGwDsAAAVAAEJxhlXmwBNAAAuAAQKfyIABCUABwkOJfQMAFYCACUABwkOJfQMAFYCABYABQk/DfFUAPYAABUAAgmLCs6nAHYAAAEuAAUUBwkeAA0AXyUA.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn85AAIiAAkJYSV7AgBfAwAiAAkJYSV7AgBfAwAAAA==.',
Io='Ionise:BAABLgAECn8kAAIIAAkJKRtPDwBwAgAIAAkJKRtPDwBwAgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Iskgard:BAAALgAECgcJBwAAAA==.Isklar:BAACLgAFFH8JAAICAAIJJBzDLQCMAAACAAIJJBzDLQCMAAAuAAQKfy8AAgIACAm4I4UEAAIDAAIACAm4I4UEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAABLgAECn8tAAQIAAkJWh1aGQAKAgAIAAgJ0RtaGQAKAgAMAAUJ0hypCAChAQAHAAMJbwy0OQCdAAAAAA==.',
Je='Jer:BAABLgAECn8cAAIOAAkJ1RAyFABzAgAOAAkJ1RAyFABzAgAAAA==.',
Ju='Jugernat:BAAALgADCgEJAQAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAFFAMJCwAhAMcUAA==.',
Ka='Kaalo:BAAALgADCgUJBQAAAA==.Kairi:BAAALgAECgYJCAAAAA==.Kammo:BAACLgAFFH8UAAIaAAQJxiAfOgB/AQAaAAQJxiAfOgB/AQAuAAQKf0QAAhoACQkxJiIDAGwDABoACQkxJiIDAGwDAAAA.Kazypher:BAAALgAECgMJCgAAAA==.',
Ke='Keeah:BAAALgAECgQJCAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAIZAAkJCgfzMQAvAQAZAAkJCgfzMQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAFFAMJCwAhAMcUAA==.Kiwi:BAAALgAFFAEJAQAAAA==.',
Kl='Klingnor:BAAALgADCgkJDgAAAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8TAAIWAAgJABUSBwD8AQAWAAgJABUSBwD8AQAuAAQKfyMAAhYABwnLIXkJANoBABYABwnLIXkJANoBAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwickin:BAAALgAECgYJCwABLgAECgcJIAAEAPEaAA==.Kwikin:BAABLgAECn8gAAIEAAcJ8RqMVQA3AgAEAAcJ8RqMVQA3AgAAAA==.',
Ky='Kyreen:BAABLgAECn8aAAIVAAgJFAvscQBXAQAVAAgJFAvscQBXAQAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECgkJGAAjANcdAA==.',
La='Laaz:BAACLgAFFH8UAAIiAAUJYAo2UwDuAAAiAAUJYAo2UwDuAAAuAAQKfzYAAiIACQlXE2U5AN4BACIACQlXE2U5AN4BAAAA.Lamalen:BAABLgAECn8UAAINAAcJnxoSYQDBAQANAAcJnxoSYQDBAQAAAA==.Lasercow:BAAALgAECgcJCAABLgAFFAQJFAAhANEhAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Liena:BAAALgADCgkJCwAAAA==.Linthvia:BAAALgAECgYJDgAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgAECgEJAwAAAA==.',
Lo='Locknloaded:BAAALgAFFAEJAQAAAA==.',
Lu='Luciuos:BAABLgAECn8ZAAMmAAkJqwJfXQCcAAAmAAkJqwJfXQCcAAAkAAcJ9QFxnQByAAAAAA==.Lucreesha:BAAALgAECgUJBQABLgAECgkJHQAiAJ0bAA==.Lukafox:BAACLgAFFH8dAAIcAAYJIh+IDwDjAQAcAAYJIh+IDwDjAQAuAAQKfyAAAxwACQlZH6gHAPoCABwACQlZH6gHAPoCAB0AAQmKAn6WAB0AAAAA.Lunastarvale:BAABLgAECn9GAAIVAAkJBR6bFACqAgAVAAkJBR6bFACqAgAAAA==.',
Ly='Lyruh:BAAALgAECggJCAAAAA==.',
Ma='Macha:BAAALgAECgQJCAAAAA==.Madith:BAACLgAFFH8IAAIiAAMJ3hRPXwDKAAAiAAMJ3hRPXwDKAAAuAAQKfyMAAiIACAlfINoXAIQCACIACAlfINoXAIQCAAAA.Magicjamo:BAAALgAECgUJBQAAAA==.Maleficênt:BAAALgAECggJEQABLgAFFAUJFAAXAHAOAA==.Malefisico:BAABLgAECn8lAAMLAAkJ8hLPFQD2AAAKAAkJKBHFbQCFAQALAAUJ3BTPFQD2AAAAAA==.Malgarok:BAABLgAECn8lAAIKAAgJWBygHgCfAgAKAAgJWBygHgCfAgABLgAECgYJEAATAAAAAA==.Mardríft:BAACLgAFFH8PAAImAAQJuBVPHgAiAQAmAAQJuBVPHgAiAQAuAAQKfzoAAiYACQnYIVkJALwCACYACQnYIVkJALwCAAAA.Mazga:BAABLgAECn9FAAIeAAkJqxxYBACqAgAeAAkJqxxYBACqAgAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8uAAIlAAkJihh1DgBEAgAlAAkJihh1DgBEAgAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgAECgQJBAAAAA==.Metta:BAABLgAFFH8MAAIiAAUJAwTBYwDAAAAiAAUJAwTBYwDAAAAAAA==.Mezoti:BAACLgAFFH8PAAMIAAQJzwTUPgDHAAAIAAQJzwTUPgDHAAAHAAIJwAHSKQBEAAAuAAQKfxkAAwgACAniDngxAG4BAAgACAniDngxAG4BAAcACAm/CDEZAD4BAAAA.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCgkJEwAAAA==.',
Mo='Moji:BAACLgAFFH8KAAIZAAMJjxE+PQCkAAAZAAMJjxE+PQCkAAAuAAQKfzQAAhkACQn4HBoMANICABkACQn4HBoMANICAAAA.Monstermayi:BAACLgAFFH8SAAISAAQJ7BSPHgAzAQASAAQJ7BSPHgAzAQAuAAQKfy8AAhIACQnXGF0YACoCABIACQnXGF0YACoCAAAA.Mooknight:BAABLgAECn8/AAICAAkJ8BWREgDjAQACAAkJ8BWREgDjAQAAAA==.Moosen:BAAALgAECgcJBwAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8nAAIjAAgJXBpKHADIAQAjAAgJXBpKHADIAQAAAA==.',
Mu='Muggy:BAABLgAECn9FAAIPAAkJRBu/AgCgAgAPAAkJRBu/AgCgAgAAAA==.',
My='Myluutarania:BAAALgAECgcJCwABLgAFFAUJCgAMANUXAA==.Myrothar:BAABLgAECn8aAAMUAAgJVhZZLQCnAQAUAAcJeBdZLQCnAQANAAYJDQN+FwGZAAAAAA==.Mytastical:BAACLgAFFH8GAAIEAAQJnQSvdAD4AAAEAAQJnQSvdAD4AAAuAAQKfykAAgQACQl4F750AI0BAAQACQl4F750AI0BAAAA.',
['Mæ']='Mæve:BAACLgAFFH8OAAIkAAQJ2AgqOwC9AAAkAAQJ2AgqOwC9AAAuAAQKfzMAAyQACQnOGKAcAF4CACQACQnOGKAcAF4CACYABQmNESxGABUBAAAA.',
['Më']='Mëgatron:BAAALgAECgEJAQAAAA==.',
Na='Namalis:BAACLgAFFH8TAAQKAAYJ7hj9SQAuAQAKAAQJMBr9SQAuAQAJAAIJ9h6LGwBVAAALAAEJgw94IABSAAAuAAQKfx0ABAoACAkTJQU5ACcCAAoABgkPJQU5ACcCAAsAAgkWIqA8AMIAAAkAAQkAADIhAG0AAAAA.Nanielito:BAACLgAFFH8GAAIEAAMJxAmUiADNAAAEAAMJxAmUiADNAAAuAAQKfyUAAgQACQnGH90bALICAAQACQnGH90bALICAAAA.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8PAAIEAAUJuRP/XgAtAQAEAAUJuRP/XgAtAQAuAAQKfygAAgQACQmCHDslAIUCAAQACQmCHDslAIUCAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
No='Nokoa:BAAALgAECggJCAAAAA==.Nonae:BAABLgAECn8gAAIVAAgJjh0bEgCnAgAVAAgJjh0bEgCnAgAAAA==.Norivari:BAAALgAECgIJAgAAAA==.Nosali:BAAALgAECgYJBgABLgAFFAUJFAAbAEUaAA==.Nosliw:BAAALgADCgUJCAAAAA==.Notawarlock:BAAALgADCgMJAwAAAA==.Noxilis:BAAALgAECgEJAQAAAA==.',
Ob='Obiwon:BAAALgAECgYJEQAAAA==.',
Og='Ogsmashsauce:BAAALgAECgEJAQAAAA==.',
Ol='Oldschooler:BAAALgAECggJCAAAAA==.',
Om='Omegá:BAACLgAFFH8OAAIDAAQJcAzECgDEAAADAAQJcAzECgDEAAAuAAQKfyIAAgMACQkuFYARAKkBAAMACQkuFYARAKkBAAAA.',
Oo='Oopsalldruid:BAAALgAECgUJCQABLgAECgcJIAAEAPEaAA==.',
Op='Optìmusprìme:BAABLgAECn8/AAIfAAkJJh8IBgCtAgAfAAkJJh8IBgCtAgAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Papa:BAACLgAFFH8FAAMJAAIJcB/UIABOAAAKAAEJRyA2uABTAAAJAAEJmh7UIABOAAAuAAQKfzUABAsACQmjIcUCANYCAAsABwlRIcUCANYCAAkACAmEI5ACAKMCAAoABQmhHMVgAH4BAAAA.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAFFAEJAQAAAA==.',
Po='Pockets:BAABLgAECn8uAAIEAAkJExbOSQD7AQAEAAkJExbOSQD7AQAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAABLgAECn8jAAIKAAgJkQMZrwDlAAAKAAgJkQMZrwDlAAAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAACLgAFFH8LAAMhAAMJxxTfLgDSAAAhAAMJxxTfLgDSAAAQAAIJowjZMAB9AAAuAAQKfzcAAyEACQnjHgcLAL0CACEACQnjHgcLAL0CABAAAgmcEomAADgAAAAA.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAECgYJEwAAAA==.',
['Pø']='Pø:BAAALgAFFAEJAgAAAA==.',
Qu='Quantum:BAAALgAECgEJAQAAAA==.Quick:BAAALgAECgEJAgABLgAECgcJIAAEAPEaAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Ragnarök:BAAALgADCgEJAQAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Ratchet:BAAALgAECgEJAQAAAA==.Ratha:BAACLgAFFH8UAAIDAAUJcRBLCQDdAAADAAUJcRBLCQDdAAAuAAQKfzEAAwMACQmqGckRAKUBAAMACQmqGckRAKUBAA0ABAkVDKMcAZMAAAAA.Ravener:BAAALgAECgYJBwAAAA==.Razeal:BAABLgAECn8fAAMNAAYJliCAXAC2AQANAAYJPyCAXAC2AQADAAIJKxjiMQCGAAAAAA==.',
Re='Reaper:BAACLgAFFH8KAAIaAAQJUyKkQQBsAQAaAAQJUyKkQQBsAQAuAAQKfx0AAxoABwkPJY4sAEsCABoABwkPJY4sAEsCAAIAAgk+B+BAAEkAAAAA.Reeah:BAAALgADCgkJCQAAAA==.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAABLgAECn8lAAMmAAgJbQ1POwAgAQAmAAgJaQtPOwAgAQAnAAEJ0A+YUQAxAAAAAA==.Reported:BAAALgAECgEJAQAAAA==.',
Rh='Rhettranger:BAAALgADCgEJAQAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8cAAMOAAcJoiQ2CgDsAQAOAAYJuCQ2CgDsAQAPAAIJgRmkDABmAAAuAAQKfysAAw4ACQlIJfkIAJQCAA4ACAnGJfkIAJQCAA8AAwnpI/4NADoBAAAA.Rokkgar:BAABLgAECn8oAAIdAAkJHhA0JwCvAQAdAAkJHhA0JwCvAQABLgAECgkJLwAPAH0MAA==.Roosterr:BAAALgADCgkJFgAAAA==.Rottontoe:BAAALgAECgYJCwAAAA==.',
Ru='Ruwazi:BAAALgAECgYJDwAAAA==.',
Ry='Ryujin:BAAALgAECgUJBwAAAA==.',
Sa='Sainted:BAAALgAECgUJBAAAAA==.Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Secarious:BAABLgAECn8bAAISAAgJnhBpNAB3AQASAAgJnhBpNAB3AQAAAA==.Sediaria:BAAALgAECgkJCQABLgAFFAQJDQAVACILAA==.Sehnsucht:BAACLgAFFH8MAAMmAAQJJBIfJAABAQAmAAQJJBIfJAABAQAkAAMJfg4TRACeAAAuAAQKfygAAyQACQktHAkeAE4CACQACQktHAkeAE4CACYAAQkAGqB2AEkAAAAA.Serius:BAAALgAECgQJBAABLgAECgkJHQAiAJ0bAA==.',
Sh='Shmadu:BAAALgAECgcJCwAAAA==.Shockk:BAABLgAECn8gAAMdAAkJGRamKQCgAQAdAAkJGRamKQCgAQAcAAMJ4AKOigBpAAAAAA==.Shone:BAAALgAECgUJBQAAAA==.',
Si='Siovhan:BAAALgAECgkJEgAAAA==.',
Sl='Sly:BAACLgAFFH8KAAIoAAMJKRuFCADwAAAoAAMJKRuFCADwAAAuAAQKfxUAAigABwkuILAEACwCACgABwkuILAEACwCAAEuAAUUBAkKABoAUyIA.',
Sm='Smóóthbói:BAACLgAFFH8GAAIEAAUJygVncQADAQAEAAUJygVncQADAQAuAAQKfy0AAgQACQmuFXhEAAsCAAQACQmuFXhEAAsCAAAA.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn83AAIIAAkJ8BfdEgBHAgAIAAkJ8BfdEgBHAgAAAA==.Soola:BAABLgAECn8fAAMcAAgJoQ3QTgByAQAcAAgJoQ3QTgByAQAdAAQJzAyfegB6AAAAAA==.',
Sp='Spoof:BAAALgAECgIJAgAAAA==.Spoopadin:BAAALgAECgIJBgAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.Sprigg:BAAALgADCgkJCQABLgAFFAUJBgAEAMoFAA==.',
St='Stack:BAACLgAFFH8JAAIlAAIJ8hsJJACsAAAlAAIJ8hsJJACsAAAuAAQKfxcAAiUABwnHHhkVAPsBACUABwnHHhkVAPsBAAEuAAUUBAkKABoAUyIA.Stompycouch:BAACLgAFFH8FAAIdAAIJJRGpQgB2AAAdAAIJJRGpQgB2AAAuAAQKfysAAh0ACAnyHDsXAF4CAB0ACAnyHDsXAF4CAAAA.Stoned:BAABLgAECn8nAAMUAAkJJh/uCADhAgAUAAkJJh/uCADhAgANAAMJ3wobJAGJAAAAAA==.Stonedpriest:BAABLgAECn87AAIbAAkJliA7BwDYAgAbAAkJliA7BwDYAgAAAA==.Stripes:BAAALgADCgUJBQABLgAECgkJLgAEABMWAA==.',
Su='Sunreaver:BAABLgAECn8tAAIaAAkJcyMtFQDGAgAaAAkJcyMtFQDGAgAAAA==.Surrëal:BAABLgAECn8aAAIBAAkJWA4+IAByAQABAAkJWA4+IAByAQABLgAFFAQJDQAVACILAA==.Surtain:BAACLgAFFH8JAAImAAMJfgyCMgCwAAAmAAMJfgyCMgCwAAAuAAQKfx8AAiYACAk4HpoUACsCACYACAk4HpoUACsCAAAA.Suxiv:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetmask:BAABLgAECn8nAAMaAAkJjyODDQD+AgAaAAkJjyODDQD+AgApAAIJ2BpKJQChAAAAAA==.',
Sx='Sxv:BAAALgAFFAIJAwAAAA==.',
Sy='Syl:BAACLgAFFH8SAAIVAAQJ4xUCOQA1AQAVAAQJ4xUCOQA1AQAuAAQKfy0AAxUACQlyG8kiAFUCABUACQlyG8kiAFUCABYABQlVCnFZAN8AAAAA.Sylvanii:BAAALgADCgEJAQAAAA==.Sylvanäs:BAABLgAECn8UAAIWAAkJ5Av3DQB8AQAWAAkJ5Av3DQB8AQABLgAECgkJMgALAModAA==.',
['Sï']='Sïdëswïpë:BAAALgAECgEJAgAAAA==.',
['Só']='Sóúndwâve:BAAALgAECgEJAgAAAA==.',
Ta='Tahitian:BAABLgAECn8fAAIVAAkJ9w61SADCAQAVAAkJ9w61SADCAQAAAA==.Tahlreth:BAABLgAECn88AAMEAAkJ4R9bFgDQAgAEAAkJ4R9bFgDQAgAFAAEJuhkqEQBKAAAAAA==.Tandlia:BAAALgAECgUJCQAAAA==.Tanickz:BAABLgAECn8tAAIEAAkJ2BKYSAD+AQAEAAkJ2BKYSAD+AQAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJLAAdAPscAA==.Tanidgetotem:BAABLgAECn8sAAIdAAkJ+xz8CQD0AgAdAAkJ+xz8CQD0AgAAAA==.Tanya:BAACLgAFFH8SAAIlAAQJ7BZzEQA4AQAlAAQJ7BZzEQA4AQAuAAQKf0AAAiUACQmKI1IDAAMDACUACQmKI1IDAAMDAAAA.Tayanna:BAABLgAECn8aAAMNAAkJFRyAdwB9AQANAAkJCByAdwB9AQADAAcJAQhtKgDDAAAAAA==.',
Te='Teias:BAACLgAFFH8UAAIbAAUJRRpJDAB+AQAbAAUJRRpJDAB+AQAuAAQKfzIAAxsACQn5GhQTAEcCABsACQn5GhQTAEcCABAABgkCHaUnAJABAAAA.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thuras:BAAALgADCgUJBQABLgAECgMJAwATAAAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8iAAIEAAgJox8sPQAjAgAEAAgJox8sPQAjAgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgADCgUJCAATAAAAAA==.',
Tr='Tricko:BAABLgAECn9KAAIVAAkJ0B7+EQC+AgAVAAkJ0B7+EQC+AgAAAA==.Trollskingx:BAABLgAECn8eAAIEAAcJwBacdADpAQAEAAcJwBacdADpAQAAAA==.Trollzy:BAABLgAECn8/AAMeAAkJLyGGAgDvAgAeAAkJLyGGAgDvAgAcAAQJjQmKoQCFAAAAAA==.Trunkmonkey:BAACLgAFFH8JAAIKAAQJIg2fXQAIAQAKAAQJIg2fXQAIAQAuAAQKfy8AAgoACQlbGoAeAGwCAAoACQlbGoAeAGwCAAAA.Trunky:BAAALgAECgYJCwAAAA==.Tryne:BAAALgADCgEJAQAAAA==.',
Ts='Tsaagan:BAACLgAFFH8RAAMKAAQJvhYrTQAnAQAKAAQJNhYrTQAnAQAJAAEJ5RJfIQBOAAAuAAQKfy0ABAoACQkXITMSALkCAAoACQkqHzMSALkCAAkABAkII/4KAIwBAAsABAkHHrQgAE4BAAAA.',
Tu='Tucker:BAABLgAECn8rAAIZAAkJgh2wCQD6AgAZAAkJgh2wCQD6AgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ud='Uddershaman:BAAALgAECgEJAQAAAA==.',
Ul='Ultramagnús:BAAALgAECgEJAgAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAABLgAECn8cAAQaAAcJrBIHfQBmAQAaAAcJVBIHfQBmAQApAAEJlwrpOAA0AAACAAEJVg1IXwAoAAAAAA==.Under:BAAALgADCgcJDgABLgAECgcJHAAaAKwSAA==.Unparalleled:BAABLgAECn8lAAMHAAcJ5AfzHgD7AAAHAAcJ5AfzHgD7AAAMAAUJZArXEgDYAAAAAA==.Unqualified:BAAALgAECgEJAQAAAA==.',
Va='Vaaleros:BAAALgADCgYJBgAAAA==.Valiithria:BAAALgAECgQJBAAAAA==.Valkyruid:BAACLgAFFH8SAAIkAAYJLxAeHgBgAQAkAAYJLxAeHgBgAQAuAAQKfxcAAiQABwnCF4w2AM0BACQABwnCF4w2AM0BAAAA.',
Ve='Vessel:BAAALgAFFAIJAgABLgAFFAQJCgAaAFMiAA==.',
Vi='Vixus:BAAALgAFFAEJAgAAAA==.',
Vx='Vxs:BAAALgAFFAIJAwAAAA==.',
['Vø']='Vøødu:BAAALgAECgYJCwABLgAECgcJGAAcAJEQAA==.',
Wa='Walshidan:BAABLgAECn8aAAIiAAkJ0xA9UQCOAQAiAAkJ0xA9UQCOAQAAAA==.Walshlel:BAAALgADCgkJCQAAAA==.Waywatcher:BAAALgAFFAIJAgAAAA==.',
We='Wenus:BAAALgAECgUJBQAAAA==.',
Wi='Wiccaflame:BAABLgAECn8bAAIEAAkJdSAxGADGAgAEAAkJdSAxGADGAgAAAA==.Wiccasham:BAAALgAECgEJAQAAAA==.',
Wu='Wullgan:BAABLgAECn8fAAMhAAkJ2R7TEQBVAgAhAAgJvx7TEQBVAgAQAAcJGBiHLABwAQAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAABLgAFFH8JAAIHAAQJvhEgGQD7AAAHAAQJvhEgGQD7AAAAAA==.',
Xo='Xole:BAABLgAECn8fAAMiAAgJnxTFWQB3AQAiAAgJnxTFWQB3AQARAAQJIQSEIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8dAAIiAAkJnRuTMAA5AgAiAAkJnRuTMAA5AgAAAA==.Xyrna:BAAALgAFFAIJAgABLgAFFAUJFAADAHEQAA==.',
Ya='Yareli:BAABLgAECn88AAIRAAkJFglTEABCAQARAAkJFglTEABCAQAAAA==.Yawa:BAABLgAFFH8HAAIaAAIJtA2x3QCFAAAaAAIJtA2x3QCFAAAAAA==.',
Ye='Yeahreally:BAAALgADCgkJCQAAAA==.Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQATAAAAAA==.Zankrah:BAAALgAECgQJBAABLgAFFAUJFAAbAEUaAA==.Zarill:BAAALgADCgcJBwAAAA==.Zartman:BAAALgAECgMJBQAAAA==.Zayzoo:BAABLgAECn8VAAIcAAgJpxTnLAAAAgAcAAgJpxTnLAAAAgAAAA==.Zazie:BAABLgAECn8VAAIEAAcJ9QYPxgD9AAAEAAcJ9QYPxgD9AAAAAA==.',
Ze='Zekröm:BAACLgAFFH8UAAIXAAUJcA5OFQDTAAAXAAUJcA5OFQDTAAAuAAQKfx8AAhcACQkyEuYUAKkBABcACQkyEuYUAKkBAAAA.Zekrøm:BAABLgAECn8lAAIdAAgJjxrvGQBEAgAdAAgJjxrvGQBEAgABLgAFFAUJFAAXAHAOAA==.Zeno:BAACLgAFFH8jAAINAAgJcR9vBQB8AgANAAgJcR9vBQB8AgAuAAQKfxcAAg0ACQkyJfgCAKcDAA0ACQkyJfgCAKcDAAAA.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgADCgkJCQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQATAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQATAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAABLgAECn8vAAIPAAkJfQw5CQCpAQAPAAkJfQw5CQCpAQAAAA==.',
Zi='Zinbar:BAABLgAECn8YAAIlAAgJHxDOIgCHAQAlAAgJHxDOIgCHAQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAABLgAECn8ZAAQjAAkJahlEEwAgAgAjAAkJPRlEEwAgAgAYAAQJ9BVWVADzAAAZAAEJTQJtcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQATAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAIEAAgJXCBkLwC1AgAEAAgJXCBkLwC1AgAAAA==.Çloudsham:BAAALgAECgEJAgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8vAAQhAAgJpiJ1BwACAwAhAAgJpiJ1BwACAwAbAAUJABoGOwBPAQAQAAEJBhhJewBDAAAAAA==.',
['ßa']='ßaè:BAAALgAECgYJCAAAAA==.',
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
