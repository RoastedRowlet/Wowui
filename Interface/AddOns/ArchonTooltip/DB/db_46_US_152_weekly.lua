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

local lookup = {'DemonHunter-Havoc','DeathKnight-Blood','Paladin-Protection','Mage-Frost','Mage-Fire','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Warrior-Fury','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warrior-Protection','Warrior-Arms','Priest-Discipline','DemonHunter-Devourer','Monk-Windwalker','Hunter-Survival','Druid-Balance','Druid-Feral','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aaylasecura:BAACLgAFFH8VAAIBAAQJOx1vDABIAQABAAQJOx1vDABIAQAuAAQKfz0AAgEACQkuJEYDACQDAAEACQkuJEYDACQDAAAA.',
Ab='Absinth:BAABLgAFFH8IAAICAAQJHhhGIgDZAAACAAQJHhhGIgDZAAABLgAFFAQJDgADAHAMAA==.Absolutezero:BAACLgAFFH8SAAMEAAQJdBqWVQAxAQAEAAQJdBqWVQAxAQAFAAIJWwIoBgBgAAAuAAQKfzYAAwQACAnRIJwvAFoCAAQACAmmIJwvAFoCAAYABAmFHTELAM8AAAAA.',
Ad='Advïl:BAAALgAECgQJBAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Alder:BAAALgADCgEJAgAAAA==.Aletstrasza:BAACLgAFFH8UAAIHAAQJ4xBzGwDgAAAHAAQJ4xBzGwDgAAAuAAQKf0UAAwcACQlHH+IDAP4CAAcACQlHH+IDAP4CAAgAAQluBVecACUAAAAA.Alexjuander:BAABLgAECn8fAAQJAAgJlRL6FQAaAQAKAAgJbwjnigAkAQAJAAYJAhP6FQAaAQALAAQJqg2kHwCvAAAAAA==.Alexsander:BAABLgAECn8YAAMIAAYJJxGfSAAIAQAIAAYJJxGfSAAIAQAMAAIJNgZ/IgBDAAAAAA==.Allysah:BAAALgAECgEJAgABLgAFFAQJIwANANgHAA==.Alphard:BAABLgAECn9EAAMOAAkJsSNEAgA5AwAOAAkJsSNEAgA5AwAPAAEJvBvVHgA5AAAAAA==.Alphatrion:BAAALgADCgQJBAAAAA==.',
Am='Amarri:BAAALgAECgUJBwAAAA==.',
An='Ancalagon:BAAALgAECgcJCQAAAA==.Anelowyn:BAABLgAECn8xAAIQAAkJtRm4DwBgAgAQAAkJtRm4DwBgAgAAAA==.',
Ap='Apocal:BAACLgAFFH8TAAIRAAgJZRQWAgCdAQARAAgJZRQWAgCdAQAuAAQKfxUAAhEACAmnG3gGACsCABEACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Aralgi:BAAALgAECgEJAQAAAA==.Arete:BAABLgAECn8WAAISAAYJ3xLcTAATAQASAAYJ3xLcTAATAQAAAA==.Arlandil:BAAALgADCgcJCAAAAA==.Artaimya:BAABLgAECn8VAAIGAAYJoyJ6AwDpAQAGAAYJoyJ6AwDpAQAAAA==.Artemìs:BAAALgAECgQJBgAAAA==.',
At='Ataraxya:BAAALgAECgUJBQAAAA==.Atmosphere:BAAALgAECgYJCAAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgYJCAATAAAAAA==.Aurelian:BAAALgADCgcJBwAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAFFAQJBgAEAJ0EAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgcJDwAAAA==.Babs:BAAALgAECgUJBgAAAA==.Backspin:BAAALgAECgUJBQABLgAECgkJLgAEABMWAA==.Baraden:BAAALgAECgUJDAAAAA==.Basutai:BAABLgAECn8iAAIUAAkJ5COlAgB+AwAUAAkJ5COlAgB+AwAAAA==.',
Be='Beanohuntz:BAAALgAECgEJAQAAAA==.Beefstout:BAAALgAECgkJCAAAAA==.Beefsun:BAAALgAECgkJAgAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgcJEAAAAA==.Bih:BAACLgAFFH8GAAIVAAMJcQk8HgBfAAAVAAMJcQk8HgBfAAAuAAQKfyEAAhUABwkKGPouAOgBABUABwkKGPouAOgBAAAA.Birgetta:BAACLgAFFH8OAAIWAAQJIgt0SwAVAQAWAAQJIgt0SwAVAQAuAAQKfzMAAxYACQmsEdk8AO0BABYACQmsEdk8AO0BABcABgltA/klAIYAAAEuAAQKCQkaAAEAWA4A.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIHAAgJNhlHDABxAgAHAAgJNhlHDABxAgABLgAECgkJGQACANkWAA==.Blasphemous:BAAALgAECgEJAwAAAA==.Blee:BAABLgAECn8zAAICAAkJGBwfEAAKAgACAAkJGBwfEAAKAgAAAA==.Bleefleenix:BAAALgAECgYJBgAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAATAAAAAA==.Bluffalo:BAAALgADCgEJAQABLgAFFAUJGwAYAHAOAA==.Blâster:BAAALgAECgEJAQAAAA==.',
Bo='Bobodaklown:BAABLgAECn8jAAMNAAkJ9BabOgA5AgANAAkJYhabOgA5AgADAAIJmxWvOwBtAAAAAA==.Boomnblood:BAAALgADCgEJAQABLgAFFAUJFgAZADwGAA==.Boomnbrew:BAACLgAFFH8WAAIZAAUJPAaHMgDeAAAZAAUJPAaHMgDeAAAuAAQKfzUAAhkACQkpFPYXAOgBABkACQkpFPYXAOgBAAAA.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8ZAAMXAAkJQAxLHQDEAAAWAAUJAQ/gkwAYAQAXAAcJBwpLHQDEAAAAAA==.',
Br='Brewman:BAACLgAFFH8bAAIaAAUJkR4fCwCdAQAaAAUJkR4fCwCdAQAuAAQKfzEAAxoACQmQITMFAFcDABoACQmQITMFAFcDABkACAnhDaI0ACwBAAAA.Bringtherain:BAAALgAECgEJAQAAAA==.',
Bu='Bubonic:BAABLgAECn8sAAIbAAkJHxYuPAAQAgAbAAkJHxYuPAAQAgAAAA==.Buenasalud:BAABLgAECn8lAAIcAAkJjBvHDgB8AgAcAAkJjBvHDgB8AgAAAA==.Business:BAAALgAECgEJAQABLgAFFAIJBAATAAAAAA==.',
Ca='Caball:BAAALgAECgEJAgAAAA==.Carcharias:BAAALgAECgYJBwAAAA==.Caylea:BAACLgAFFH8nAAISAAYJpRqDDgCSAQASAAYJpRqDDgCSAQAuAAQKfywAAhIACAkrHQYZAIMCABIACAkrHQYZAIMCAAAA.',
Ch='Chalis:BAABLgAECn8iAAMLAAcJYB/BCgATAgAKAAYJrB52LgAeAgALAAYJ5h3BCgATAgAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAACLgAFFH8SAAQdAAUJkxkILgAqAQAdAAQJCh0ILgAqAQAeAAIJrgKFTwBZAAAfAAEJAABBFQAAAAAuAAQKfyMABB0ACAmKFbYvAPYBAB0ACAmKFbYvAPYBAB4AAwkvCM+DAGgAAB8AAwmzCWIzAGMAAAAA.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAACLgAFFH8XAAIEAAQJPgxLKAACAQAEAAQJPgxLKAACAQAuAAQKfzIAAwQACQk4F1lRAOgBAAQACQk4F1lRAOgBAAUAAQm6A2ARACsAAAAA.Corleon:BAAALgADCgMJAwAAAA==.Corvus:BAAALgAECgUJDgAAAA==.',
Cr='Crizlock:BAAALgAECgEJAQABLgAECgcJGQAWAEYjAA==.Crowdcontrol:BAABLgAECn8aAAIDAAkJFiAtBgCGAgADAAkJFiAtBgCGAgAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAACLgAFFH8XAAIgAAQJQxZyCQDuAAAgAAQJQxZyCQDuAAAuAAQKfzwAAyAACQlgGywBAEACACAACAmIHSwBAEACACEACQlZDjIMAN4BAAAA.',
Cu='Cuahtemoc:BAAALgAECgEJAQAAAA==.Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgABLgAECgkJLgAEABMWAA==.Cursis:BAAALgAECgIJAgAAAA==.',
Da='Daddysixinch:BAABLgAFFH8MAAIbAAUJWhWDVABJAQAbAAUJWhWDVABJAQAAAA==.Daelin:BAABLgAECn8zAAMNAAkJ6CMJBwA3AwANAAkJ6CMJBwA3AwAUAAEJJw2jkgAsAAAAAA==.Danye:BAAALgAECgQJBQAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darkcleric:BAAALgADCgYJBgAAAA==.Darknous:BAAALgAECgEJAQAAAA==.Darktotems:BAAALgAECgUJBQAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deadball:BAAALgAECgEJAQABLgAECgkJLgAEABMWAA==.Deante:BAABLgAECn8ZAAIiAAYJWgxPPAAdAQAiAAYJWgxPPAAdAQAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathman:BAABLgAECn8ZAAICAAkJ2RYqEAAJAgACAAkJ2RYqEAAJAgAAAA==.Deathrite:BAAALgAFFAEJAQAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCgAAAA==.Demo:BAAALgAFFAMJAwABLgAFFAQJCgAbAFMiAA==.Demonmommy:BAAALgADCgEJAgAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAACLgAFFH8QAAIeAAUJEAsjLQDfAAAeAAUJEAsjLQDfAAAuAAQKfygAAh4ACQkTFBAfAOoBAB4ACQkTFBAfAOoBAAAA.',
Dh='Dhchin:BAAALgAFFAEJAQABLgAFFAgJJQAOAIQgAA==.Dhomsak:BAABLgAFFH8eAAIjAAcJ7RuHHwC7AQAjAAcJ7RuHHwC7AQABLgAFFAYJJwAEAB8kAA==.',
Di='Diamonds:BAAALgADCgEJAQABLgAECgkJLgAEABMWAA==.Die:BAABLgAFFH8JAAINAAMJwRKHKgDGAAANAAMJwRKHKgDGAAAAAA==.Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgYJCAAAAA==.Distrath:BAAALgADCgkJCQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQABLgAFFAgJJQAOAIQgAA==.',
Do='Doadin:BAABLgAECn8sAAMUAAkJoBvCDQCqAgAUAAkJoBvCDQCqAgANAAEJ1gHBXQEgAAAAAA==.Doominatrix:BAACLgAFFH8UAAMKAAUJsgq1YwD/AAAKAAQJagq1YwD/AAAJAAIJNAdGKgBDAAAuAAQKfzIAAwoACAm+GHU+AOIBAAoABwm+GHU+AOIBAAkAAQkAAKQqAEoAAAAA.Dotem:BAAALgAECgEJAQAAAA==.',
Dr='Draggum:BAABLgAECn8eAAMIAAgJ+xlxHADyAQAIAAgJ+xlxHADyAQAHAAMJpxDaKQCdAAAAAA==.Dragune:BAAALgAECgEJAQABLgAECgcJIgALAGAfAA==.Dreadmagey:BAAALgAECggJCAABLgAECgkJVwASACceAA==.Dreadraven:BAABLgAECn9XAAMSAAkJJx5FCQDOAgASAAkJJx5FCQDOAgAhAAMJ6AtNYwBbAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8pAAMBAAkJRxRuIQCxAQABAAgJvxRuIQCxAQAjAAgJuBA0awBOAQABLgAECgEJAQATAAAAAA==.Dreddstorm:BAAALgAECgEJAgAAAA==.Drewuw:BAABLgAECn8bAAIkAAkJwBaOGQAVAgAkAAkJwBaOGQAVAgABLgAECgkJHQAjAJ0bAA==.Druidhams:BAACLgAFFH8VAAIVAAUJGRg5KwALAQAVAAUJGRg5KwALAQAuAAQKfzUAAhUACQn+HpUNAO0CABUACQn+HpUNAO0CAAAA.',
Ea='Eamon:BAAALgAFFAEJAQABLgAFFAMJDQAiAMcUAA==.',
Ei='Eightball:BAAALgAECgYJCAABLgAECgkJLgAEABMWAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgUJBgAAAA==.Elisha:BAACLgAFFH8jAAINAAQJ2AcpXAD4AAANAAQJ2AcpXAD4AAAuAAQKf30AAg0ACQlRG7wnAGQCAA0ACQlRG7wnAGQCAAAA.Eloquence:BAAALgAECgQJBQAAAA==.Elsyra:BAAALgAECgYJDgAAAA==.',
Er='Erebostro:BAABLgAECn8/AAIWAAkJYxqTIQBfAgAWAAkJYxqTIQBfAgAAAA==.',
Ev='Everclear:BAAALgAECggJDAABLgAFFAQJDgADAHAMAA==.Evillux:BAACLgAFFH8FAAMKAAIJbQVatQBtAAAKAAIJbQVatQBtAAALAAEJZACpLQAhAAAuAAQKfy8AAwoACQm2ED1NALMBAAoACQlHED1NALMBAAsABQnmDH0qABcBAAAA.',
Ey='Eyeguy:BAABLgAECn8VAAMjAAkJHxyYJwBmAgAjAAkJLBmYJwBmAgABAAQJ+h+0NgAsAQAAAA==.',
Fa='Fadedvoker:BAAALgAFFAEJAQABLgAECgkJHQAQAPobAA==.Fathercow:BAACLgAFFH8WAAIiAAUJmh6hHQBtAQAiAAUJmh6hHQBtAQAuAAQKfywAAiIACQn3H3gGABkDACIACQn3H3gGABkDAAAA.Faultline:BAAALgAECgIJAgABLgAECgkJJAAkALcbAA==.',
Fi='Fingies:BAACLgAFFH8RAAQKAAQJaBvoUAAkAQAKAAQJrRboUAAkAQAJAAEJoh68GwBWAAALAAEJ1RI9IwBPAAAuAAQKfz4AAwoACQm9JAcQAMwCAAoABwlHJQcQAMwCAAsABQmyHkoVAJ8BAAAA.Fistin:BAAALgAECgYJBwAAAA==.',
Fl='Flexyheals:BAAALgADCgYJBgAAAA==.',
Fr='Frieren:BAAALgADCgYJBgAAAA==.',
Fu='Fungies:BAABLgAFFH8HAAIVAAQJsgtXOQDIAAAVAAQJsgtXOQDIAAABLgAFFAQJEQAKAGgbAA==.Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAACLgAFFH8UAAIWAAUJQBh0NwA+AQAWAAUJQBh0NwA+AQAuAAQKfzQAAxYACQkhI8wKAP8CABYACQkhI8wKAP8CACUABQmiDdY9ANQAAAAA.',
Ga='Gaijin:BAAALgADCgMJAwABLgAFFAMJDQAiAMcUAA==.Galaxsea:BAABLgAECn8YAAIkAAkJ1x0xDgBkAgAkAAkJ1x0xDgBkAgAAAA==.Gargapew:BAAALgAECgIJAgABLgAFFAMJBgAEAMQJAA==.',
Ge='Gerthquake:BAABLgAECn8rAAMeAAkJzRnhFABCAgAeAAkJzRnhFABCAgAdAAkJOB4uNgDYAQAAAA==.',
Gf='Gfour:BAABLgAECn8fAAIaAAgJjhx2EwAvAgAaAAgJjhx2EwAvAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.Ghraxx:BAAALgADCgkJCQAAAA==.Ghraxxy:BAAALgAECgkJEQAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Gobø:BAABLgAECn8qAAIWAAcJxgnyFQDpAAAWAAcJxgnyFQDpAAAAAA==.Goodytwoshoe:BAAALgAECgIJBwAAAA==.',
Gr='Grimmreefer:BAAALgAECgUJBQAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgQJCgAAAA==.',
['Gâ']='Gâlvatron:BAAALgADCgEJAQAAAA==.',
Ha='Hacks:BAAALgADCgcJBwAAAA==.Hakz:BAAALgADCgkJCQAAAA==.',
He='Heart:BAABLgAFFH8HAAMiAAMJtQcpNwCuAAAiAAMJtQcpNwCuAAAQAAEJgAIwQQA0AAABLgAFFAQJCgAbAFMiAA==.Hefferhumper:BAAALgAECgQJBAAAAA==.Help:BAAALgADCgEJAQAAAA==.Helravn:BAAALgAECgIJAgAAAA==.',
Ho='Homlock:BAABLgAFFH8LAAMKAAYJTB7UPwBPAQAKAAYJTB7UPwBPAQAJAAEJYBR2HwBRAAABLgAFFAYJJwAEAB8kAA==.Homsorc:BAACLgAFFH8nAAQEAAYJHyTiBwDlAQAEAAYJHyTiBwDlAQAFAAQJ3Rv+AABzAQAGAAEJByRtBQBWAAAuAAQKfyQAAgQACQmuJTMFAK8DAAQACQmuJTMFAK8DAAAA.Homtard:BAABLgAFFH8TAAQXAAgJ4yAOBgAUAgAXAAgJ5R8OBgAUAgAlAAQJFh+QDABhAQAWAAEJ/iIlmABjAAABLgAFFAYJJwAEAB8kAA==.Homtotem:BAABLgAFFH8FAAIeAAUJ/xO/DQAXAQAeAAUJ/xO/DQAXAQABLgAFFAYJJwAEAB8kAA==.Hope:BAACLgAFFH8IAAIUAAMJ0hkIJwDqAAAUAAMJ0hkIJwDqAAAuAAQKfzoAAxQACQn3HHQKAOQCABQACQn3HHQKAOQCAA0ABAnnBzcSAaMAAAAA.',
['Hô']='Hôûnd:BAAALgAECgEJAQAAAA==.',
Id='Idun:BAAALgAECgYJCgAAAA==.',
Il='Illiandray:BAABLgAECn8yAAMLAAkJyh20AgCGAgALAAkJyh20AgCGAgAKAAgJUgp3kQAYAQAAAA==.Ilswyn:BAAALgADCgkJDwABLgAECgkJOQAjAGElAA==.',
Im='Imu:BAACLgAFFH8KAAMlAAMJoCGGHADsAAAlAAMJoCGGHADsAAAWAAEJxhmWoQBNAAAuAAQKfyIABCUABwkOJRYNAFQCACUABwkOJRYNAFQCABcABQk/DfFUAPYAABYAAgmLCs6nAHYAAAEuAAUUCAkrAA0APCQA.Imzadi:BAAALgAECgkJCQAAAA==.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn85AAIjAAkJYSWZAgBeAwAjAAkJYSWZAgBeAwAAAA==.',
Io='Ionise:BAABLgAECn8kAAIIAAkJKRt7DwBvAgAIAAkJKRt7DwBvAgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Iskgard:BAAALgAECgcJBwAAAA==.Isklar:BAACLgAFFH8JAAICAAIJJBz6LgCJAAACAAIJJBz6LgCJAAAuAAQKfy8AAgIACAm4I4UEAAIDAAIACAm4I4UEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAABLgAECn8wAAQIAAkJWh2DGQAKAgAIAAgJ0RuDGQAKAgAMAAUJ0hzOCAChAQAHAAMJbwy0OQCdAAAAAA==.',
Je='Jer:BAABLgAECn8cAAIOAAkJ1RAyFABzAgAOAAkJ1RAyFABzAgAAAA==.',
Ju='Jugernat:BAAALgADCgQJBwAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAFFAMJDQAiAMcUAA==.',
Ka='Kaalo:BAAALgADCgUJBQAAAA==.Kairi:BAAALgAECgYJCAAAAA==.Kammo:BAACLgAFFH8UAAIbAAQJxiDtPQB8AQAbAAQJxiDtPQB8AQAuAAQKf0QAAhsACQkxJlMDAGoDABsACQkxJlMDAGoDAAAA.Kazypher:BAAALgAECgMJCgAAAA==.',
Ke='Keeah:BAAALgAECgQJCAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAIaAAkJCgfzMQAvAQAaAAkJCgfzMQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAFFAMJDQAiAMcUAA==.Kiwi:BAAALgAFFAEJAQAAAA==.',
Kl='Klingnor:BAAALgADCgkJFQAAAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8fAAIXAAgJ+xYRBQAqAgAXAAgJ+xYRBQAqAgAuAAQKfyMAAhcABwnLIbIJANkBABcABwnLIbIJANkBAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwickin:BAAALgAECgYJCwABLgAECggJHgAIAPsZAA==.Kwikin:BAABLgAECn8gAAIEAAcJ8RqMVQA3AgAEAAcJ8RqMVQA3AgABLgAECggJHgAIAPsZAA==.',
Ky='Kyreen:BAABLgAECn8cAAIWAAkJtgsodABXAQAWAAkJtgsodABXAQAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECgkJGAAkANcdAA==.',
La='Laaz:BAACLgAFFH8bAAIjAAUJKAtlJADQAAAjAAUJKAtlJADQAAAuAAQKfzYAAiMACQlXEzQ6AN4BACMACQlXEzQ6AN4BAAAA.Lamalen:BAABLgAECn8UAAINAAcJnxoSYQDBAQANAAcJnxoSYQDBAQAAAA==.Lasercow:BAAALgAECgcJCAABLgAFFAUJFgAiAJoeAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Liena:BAAALgADCgkJCwAAAA==.Linthvia:BAAALgAECgYJDgAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgAECgEJAwAAAA==.',
Lo='Locknloaded:BAAALgAFFAEJAQAAAA==.',
Lu='Luciuos:BAABLgAECn8ZAAMmAAkJqwJTXwCbAAAmAAkJqwJTXwCbAAAVAAcJ9QHvngByAAAAAA==.Lucreesha:BAAALgAECgYJBgABLgAECgkJHQAjAJ0bAA==.Lukafox:BAACLgAFFH8eAAIdAAcJaR/FEADjAQAdAAcJaR/FEADjAQAuAAQKfyAAAx0ACQlZH6gHAPoCAB0ACQlZH6gHAPoCAB4AAQmKAn6WAB0AAAAA.Lunastarvale:BAABLgAECn9GAAIWAAkJBR5gFQCoAgAWAAkJBR5gFQCoAgAAAA==.Lunereclips:BAAALgAECgQJCgAAAA==.Lupuis:BAAALgAECgEJAgAAAA==.',
Ly='Lyruh:BAAALgAECggJCAAAAA==.',
Ma='Macha:BAAALgAFFAEJAQAAAA==.Madith:BAACLgAFFH8QAAIjAAUJBR7eEQBnAQAjAAUJBR7eEQBnAQAuAAQKfyUAAiMACAmMIEMYAIQCACMACAmMIEMYAIQCAAAA.Magicjamo:BAAALgAECgUJBQAAAA==.Maleficênt:BAAALgAECggJEQABLgAFFAUJGwAYAHAOAA==.Malefisico:BAABLgAECn8lAAMLAAkJ8hJCFgD2AAAKAAkJKBHFbQCFAQALAAUJ3BRCFgD2AAAAAA==.Malgarok:BAABLgAECn8lAAIKAAgJWBygHgCfAgAKAAgJWBygHgCfAgABLgAECgYJEAATAAAAAA==.Mardríft:BAACLgAFFH8VAAImAAQJUheDHwAgAQAmAAQJUheDHwAgAQAuAAQKfzoAAiYACQnYIX0JALwCACYACQnYIX0JALwCAAAA.Mazga:BAABLgAECn9MAAIfAAkJmR12BACpAgAfAAkJmR12BACpAgAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8vAAIlAAkJihiODgBCAgAlAAkJihiODgBCAgAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgAECgQJBAAAAA==.Metta:BAABLgAFFH8SAAIjAAYJiQdrGQAcAQAjAAYJiQdrGQAcAQAAAA==.Mezoti:BAACLgAFFH8SAAMIAAQJGwUYQQDDAAAIAAQJGwUYQQDDAAAHAAIJwAHPKgBEAAAuAAQKfxkAAwgACAniDoEyAGsBAAgACAniDoEyAGsBAAcACAm/CHUZAD4BAAAA.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCgkJEwAAAA==.Miraclehwip:BAAALgAECgcJBwAAAA==.',
Mo='Moji:BAACLgAFFH8KAAIaAAMJjxFFQACjAAAaAAMJjxFFQACjAAAuAAQKfzQAAhoACQn4HGAMANMCABoACQn4HGAMANMCAAAA.Monstermayi:BAACLgAFFH8UAAISAAUJ7BTBHwAzAQASAAUJ7BTBHwAzAQAuAAQKfy8AAhIACQnXGNUYACcCABIACQnXGNUYACcCAAAA.Mooknight:BAABLgAECn8/AAICAAkJ8BXvEgDhAQACAAkJ8BXvEgDhAQAAAA==.Moomoo:BAAALgAFFAEJAQAAAA==.Moosen:BAAALgAECgcJBwAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8nAAIkAAgJXBrPHADIAQAkAAgJXBrPHADIAQAAAA==.',
Mu='Muggy:BAABLgAECn9FAAIPAAkJRBvKAgCgAgAPAAkJRBvKAgCgAgAAAA==.',
My='Myluutarania:BAAALgAECgcJCwABLgAFFAcJDgAMANoUAA==.Myrothar:BAABLgAECn8aAAMUAAgJVhbnLQCmAQAUAAcJeBfnLQCmAQANAAYJDQO+HAGXAAAAAA==.Mytastical:BAACLgAFFH8GAAIEAAQJnQRidwDrAAAEAAQJnQRidwDrAAAuAAQKfykAAgQACQl4F152AI0BAAQACQl4F152AI0BAAAA.',
['Mæ']='Mæve:BAACLgAFFH8UAAIVAAQJSAuYEgC+AAAVAAQJSAuYEgC+AAAuAAQKfzMAAxUACQnOGCwdAF0CABUACQnOGCwdAF0CACYABQmNESxGABUBAAAA.',
['Më']='Mëgatron:BAAALgAECgEJAQAAAA==.',
Na='Namalis:BAACLgAFFH8TAAQKAAYJ7hhhTAAuAQAKAAQJMBphTAAuAQAJAAIJ9h6iHABVAAALAAEJgw8yIQBSAAAuAAQKfx0ABAoACAkTJQU5ACcCAAoABgkPJQU5ACcCAAsAAgkWIqA8AMIAAAkAAQkAADIhAG0AAAAA.Nanielito:BAACLgAFFH8GAAIEAAMJxAmriwDCAAAEAAMJxAmriwDCAAAuAAQKfyUAAgQACQnGH4IcALECAAQACQnGH4IcALECAAAA.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8TAAIEAAUJfBWuYQAeAQAEAAUJfBWuYQAeAQAuAAQKfygAAgQACQmCHAomAIMCAAQACQmCHAomAIMCAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
Ni='Nineball:BAAALgAECgEJAQABLgAECgkJLgAEABMWAA==.',
No='Nojak:BAAALgAECgUJCAABLgAFFAIJBgAWALMHAA==.Nokoa:BAAALgAECggJCAAAAA==.Nonae:BAABLgAECn8gAAIWAAgJjh0bEgCnAgAWAAgJjh0bEgCnAgAAAA==.Norivari:BAAALgAECgUJCwAAAA==.Nosali:BAAALgAECgcJEwABLgAFFAUJGwAcAEodAA==.Notawarlock:BAAALgADCgMJAwAAAA==.Noxilis:BAAALgAECgEJAQAAAA==.',
Ob='Obiwon:BAAALgAECgYJEQAAAA==.',
Og='Ogsmashsauce:BAAALgAECgEJAQAAAA==.',
Ol='Oldschooler:BAAALgAECggJCAAAAA==.',
Om='Omegá:BAACLgAFFH8OAAIDAAQJcAwkCwDDAAADAAQJcAwkCwDDAAAuAAQKfyIAAgMACQkuFcERAKkBAAMACQkuFcERAKkBAAAA.',
Oo='Oopsalldruid:BAAALgAECgUJCQABLgAECggJHgAIAPsZAA==.',
Op='Optìmusprìme:BAABLgAECn8/AAIgAAkJJh8zBgCrAgAgAAkJJh8zBgCrAgAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Pandalock:BAAALgAECgYJBgAAAA==.Papa:BAACLgAFFH8FAAMJAAIJcB/hIQBOAAAKAAEJRyBGvABSAAAJAAEJmh7hIQBOAAAuAAQKfzUABAsACQmjIcUCANYCAAsABwlRIcUCANYCAAkACAmEI6kCAKECAAoABQmhHIBhAHwBAAAA.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAFFAEJAQAAAA==.',
Po='Pockets:BAABLgAECn8uAAIEAAkJExYgSwD6AQAEAAkJExYgSwD6AQAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAABLgAECn8kAAIKAAgJkQPvsADjAAAKAAgJkQPvsADjAAAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAACLgAFFH8NAAMiAAMJxxRyMADRAAAiAAMJxxRyMADRAAAQAAIJowhTMgB8AAAuAAQKfzcAAyIACQnjHkgLALsCACIACQnjHkgLALsCABAAAgmcEvmCADgAAAAA.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAFFAIJBAAAAA==.',
['Pø']='Pø:BAAALgAFFAEJAgAAAA==.',
Qu='Quantum:BAAALgAECgEJAQAAAA==.Quick:BAAALgAECgEJAwABLgAECggJHgAIAPsZAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Ragnarök:BAAALgADCgEJAQAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Ratchet:BAAALgAECgEJAQAAAA==.Ratha:BAACLgAFFH8bAAIDAAUJoRETBADMAAADAAUJoRETBADMAAAuAAQKfzEAAwMACQmqGRISAKUBAAMACQmqGRISAKUBAA0ABAkVDJsgAZMAAAAA.Ravener:BAAALgAECgYJBwAAAA==.Ravincible:BAAALgAECgYJCAAAAA==.Razeal:BAABLgAECn8gAAMNAAYJ/yEBXgC1AQANAAYJqSEBXgC1AQADAAIJKxjiMQCGAAAAAA==.',
Re='Reaper:BAACLgAFFH8KAAIbAAQJUyKPRQBpAQAbAAQJUyKPRQBpAQAuAAQKfyEAAxsABwkPJUItAEsCABsABwkPJUItAEsCAAIAAgk+B+BAAEkAAAAA.Reeah:BAAALgADCgkJCQAAAA==.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAABLgAECn8lAAMmAAgJbQ0cPAAhAQAmAAgJaQscPAAhAQAnAAEJ0A8cVAAxAAAAAA==.Reported:BAAALgAECgEJAQAAAA==.',
Rh='Rhettranger:BAAALgADCgEJAQAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8lAAMOAAgJhCAABQDcAQAOAAcJ5x8ABQDcAQAPAAIJgRkgBABgAAAuAAQKfysAAw4ACQlIJSMJAJMCAA4ACAnGJSMJAJMCAA8AAwnpI/4NADoBAAAA.Rokkgar:BAABLgAECn8qAAIeAAkJiRHlJwCuAQAeAAkJiRHlJwCuAQABLgAECgkJMQAPAEEQAA==.Roosterr:BAAALgADCgkJFgAAAA==.Rottontoe:BAAALgAECgYJDAAAAA==.',
Ru='Ruwazi:BAAALgAECgYJDwAAAA==.',
Rx='Rxdh:BAAALgAECgIJAgAAAA==.',
Ry='Ryujin:BAAALgAECgUJBwAAAA==.',
Sa='Sainted:BAAALgAECgUJBAAAAA==.Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scared:BAACLgAFFH8WAAIcAAUJexvyBABnAQAcAAUJexvyBABnAQAuAAQKfz0AAhwACAkxH7kKALsCABwACAkxH7kKALsCAAAA.Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Secarious:BAABLgAECn8bAAISAAgJnhDnNQBxAQASAAgJnhDnNQBxAQAAAA==.Sediaria:BAAALgAECgkJCQABLgAECgkJGgABAFgOAA==.Sehnsucht:BAACLgAFFH8MAAMmAAQJJBI0JQABAQAmAAQJJBI0JQABAQAVAAMJfg6vRQCeAAAuAAQKfygAAxUACQktHAkeAE4CABUACQktHAkeAE4CACYAAQkAGqB2AEkAAAAA.Serius:BAAALgAECgQJBAABLgAECgkJHQAjAJ0bAA==.',
Sh='Shavoo:BAAALgAECgkJCQAAAA==.Shmadu:BAAALgAECgcJCwAAAA==.Shockk:BAABLgAECn8gAAMeAAkJGRZqKgCfAQAeAAkJGRZqKgCfAQAdAAMJ4AKOigBpAAAAAA==.Shone:BAAALgAECgUJBQAAAA==.',
Si='Siovhan:BAAALgAECgkJEgAAAA==.',
Sl='Sly:BAACLgAFFH8KAAIoAAMJKRvGCADwAAAoAAMJKRvGCADwAAAuAAQKfxUAAigABwkuIM4EACoCACgABwkuIM4EACoCAAEuAAUUBAkKABsAUyIA.',
Sm='Smóóthbói:BAACLgAFFH8IAAIEAAUJVAZTdAD1AAAEAAUJVAZTdAD1AAAuAAQKfy0AAgQACQmuFWNFAAsCAAQACQmuFWNFAAsCAAAA.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn83AAIIAAkJ8BdPEwBEAgAIAAkJ8BdPEwBEAgAAAA==.Soola:BAABLgAECn8fAAMdAAgJoQ0XUAByAQAdAAgJoQ0XUAByAQAeAAQJzAwLfQB5AAAAAA==.Soulmonkey:BAAALgAFFAMJAwAAAA==.',
Sp='Spoof:BAAALgAECgIJAgAAAA==.Spoopadin:BAAALgAECgIJBgAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.Sprigg:BAAALgADCgkJCQABLgAFFAUJCAAEAFQGAA==.',
St='Stabbymoose:BAAALgAECgEJAQAAAA==.Stack:BAACLgAFFH8JAAIlAAIJ8hvkJACrAAAlAAIJ8hvkJACrAAAuAAQKfxcAAiUABwnHHmoVAPgBACUABwnHHmoVAPgBAAEuAAUUBAkKABsAUyIA.Stompycouch:BAACLgAFFH8FAAIeAAIJJRH6RAB2AAAeAAIJJRH6RAB2AAAuAAQKfysAAh4ACAnyHDsXAF4CAB4ACAnyHDsXAF4CAAAA.Stoned:BAABLgAECn8nAAMUAAkJJh/uCADhAgAUAAkJJh/uCADhAgANAAMJ3wpdKAGJAAAAAA==.Stonedpriest:BAABLgAECn87AAIcAAkJliA7BwDYAgAcAAkJliA7BwDYAgAAAA==.Stripes:BAAALgADCgUJBQABLgAECgkJLgAEABMWAA==.',
Su='Sunreaver:BAABLgAECn8tAAIbAAkJcyOtFQDFAgAbAAkJcyOtFQDFAgAAAA==.Surrëal:BAABLgAECn8aAAIBAAkJWA7LIAByAQABAAkJWA7LIAByAQAAAA==.Surtain:BAACLgAFFH8JAAImAAMJfgwCNACwAAAmAAMJfgwCNACwAAAuAAQKfx8AAiYACAk4Hs4UACsCACYACAk4Hs4UACsCAAAA.Suxiv:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetmask:BAABLgAECn8pAAMbAAkJjyPnDQD9AgAbAAkJjyPnDQD9AgApAAIJ2BoSJgChAAAAAA==.',
Sx='Sxv:BAAALgAFFAIJAwAAAA==.',
Sy='Sybela:BAAALgAECgEJAQABLgAECgcJEwATAAAAAA==.Syl:BAACLgAFFH8UAAIWAAUJ4xX7OwA1AQAWAAUJ4xX7OwA1AQAuAAQKfy0AAxYACQlyG6sjAFQCABYACQlyG6sjAFQCABcABQlVCnFZAN8AAAAA.Sylvanii:BAAALgAECgIJAgAAAA==.Sylvanäs:BAABLgAECn8UAAIXAAkJ5AssDgB8AQAXAAkJ5AssDgB8AQABLgAECgkJMgALAModAA==.',
['Sï']='Sïdëswïpë:BAAALgAECgEJAgAAAA==.',
['Só']='Sóúndwâve:BAAALgAECgEJAgAAAA==.',
Ta='Tahitian:BAACLgAFFH8GAAIWAAIJswfXQACDAAAWAAIJswfXQACDAAAuAAQKfx8AAhYACQn3DmZKAMIBABYACQn3DmZKAMIBAAAA.Tahlreth:BAABLgAECn88AAMEAAkJ4R/vFgDPAgAEAAkJ4R/vFgDPAgAFAAEJuhm4EQBKAAAAAA==.Tandlia:BAAALgAECgUJCQAAAA==.Tanickz:BAABLgAECn8tAAIEAAkJ2BLXSQD9AQAEAAkJ2BLXSQD9AQAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJLAAeAPscAA==.Tanidgetotem:BAABLgAECn8sAAIeAAkJ+xz8CQD0AgAeAAkJ+xz8CQD0AgAAAA==.Tanya:BAACLgAFFH8SAAIlAAQJ7BYSEgA3AQAlAAQJ7BYSEgA3AQAuAAQKf0AAAiUACQmKI3kDAP8CACUACQmKI3kDAP8CAAAA.Tayanna:BAABLgAECn8cAAMNAAkJ2B4/eQB8AQANAAkJ2B4/eQB8AQADAAcJAQgFKwDDAAAAAA==.',
Te='Teias:BAACLgAFFH8bAAIcAAUJSh26BABvAQAcAAUJSh26BABvAQAuAAQKfzIAAxwACQn5GhQTAEcCABwACQn5GhQTAEcCABAABgkCHfcnAI8BAAAA.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thoradin:BAAALgADCgEJAQAAAA==.Thuras:BAAALgADCgUJBQABLgAECgMJAwATAAAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8iAAIEAAgJox8TPgAjAgAEAAgJox8TPgAjAgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgAECgkJCQATAAAAAA==.',
Tr='Tricko:BAABLgAECn9SAAIWAAkJFB9yEgC+AgAWAAkJFB9yEgC+AgAAAA==.Trollskingx:BAABLgAECn8eAAIEAAcJwBacdADpAQAEAAcJwBacdADpAQAAAA==.Trollzy:BAABLgAECn8/AAMfAAkJLyGeAgDuAgAfAAkJLyGeAgDuAgAdAAQJjQljpACFAAAAAA==.Trunkmonkey:BAACLgAFFH8KAAIKAAQJXw7pXwAIAQAKAAQJXw7pXwAIAQAuAAQKfy8AAgoACQlbGhEfAGoCAAoACQlbGhEfAGoCAAAA.Trunky:BAAALgAECgYJCwAAAA==.Tryne:BAAALgAECgMJAwAAAA==.',
Ts='Tsaagan:BAACLgAFFH8TAAMKAAUJvha1TwAnAQAKAAQJNha1TwAnAQAJAAIJ5RJoIgBOAAAuAAQKfy0ABAoACQkXIaMSALcCAAoACQkqH6MSALcCAAkABAkII/4KAIwBAAsABAkHHrQgAE4BAAAA.',
Tu='Tucker:BAABLgAECn8rAAIaAAkJgh3pCQD6AgAaAAkJgh3pCQD6AgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ud='Uddershaman:BAAALgAFFAIJAgAAAA==.',
Ul='Ultramagnús:BAAALgAECgEJAgAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAABLgAECn8eAAQbAAkJ/g6LfwBkAQAbAAcJVBKLfwBkAQACAAMJFQd/DgBPAAApAAEJlwprOgA0AAAAAA==.Unclear:BAAALgAECgYJBgABLgAECgkJHgAbAP4OAA==.Under:BAAALgADCgcJDgABLgAECgkJHgAbAP4OAA==.Unparalleled:BAABLgAECn8nAAMHAAkJngldHwD7AAAHAAcJ5AddHwD7AAAMAAcJHAsnEwDYAAAAAA==.Unqualified:BAAALgAECgIJAgAAAA==.',
Va='Vaaleros:BAAALgADCgYJBgAAAA==.Valiithria:BAAALgAECgQJBAAAAA==.Valkyruid:BAACLgAFFH8UAAIVAAgJBQ5dHwBeAQAVAAgJBQ5dHwBeAQAuAAQKfxcAAhUABwnCF4w2AM0BABUABwnCF4w2AM0BAAAA.',
Ve='Veluthil:BAAALgAECgYJBwABLgAFFAQJFAAVAEgLAA==.Vessel:BAAALgAFFAIJAgABLgAFFAQJCgAbAFMiAA==.',
Vi='Vixus:BAAALgAFFAEJAgAAAA==.',
Vx='Vxs:BAAALgAFFAIJAwAAAA==.',
['Vø']='Vøødu:BAAALgAECgYJCwABLgAECgcJGAAdAJEQAA==.',
Wa='Walshidan:BAABLgAECn8aAAIjAAkJ0xBHUgCPAQAjAAkJ0xBHUgCPAQAAAA==.Walshlel:BAAALgADCgkJCQAAAA==.Waywatcher:BAAALgAFFAIJAwAAAA==.',
We='Wenus:BAAALgAECgUJBQAAAA==.',
Wi='Wiccaflame:BAABLgAECn8bAAIEAAkJdSDMGADFAgAEAAkJdSDMGADFAgAAAA==.Wiccasham:BAAALgAECgEJAQAAAA==.',
Wu='Wullgan:BAABLgAECn8fAAMiAAkJ2R6PEgBPAgAiAAgJvx6PEgBPAgAQAAcJGBgnLQBuAQAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAABLgAFFH8MAAIHAAUJZRK2GQD7AAAHAAUJZRK2GQD7AAAAAA==.',
Xo='Xole:BAABLgAECn8fAAMjAAgJnxThWgB3AQAjAAgJnxThWgB3AQARAAQJIQSEIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8dAAIjAAkJnRuTMAA5AgAjAAkJnRuTMAA5AgAAAA==.Xyrna:BAAALgAFFAIJAgABLgAFFAUJGwADAKERAA==.',
Ya='Yareli:BAABLgAECn88AAIRAAkJFgmWEABDAQARAAkJFgmWEABDAQAAAA==.Yawa:BAABLgAFFH8HAAIbAAIJtA285ACCAAAbAAIJtA285ACCAAAAAA==.',
Ye='Yeahreally:BAAALgADCgkJCQAAAA==.Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQATAAAAAA==.Zankrah:BAAALgAECgQJBAABLgAFFAUJGwAcAEodAA==.Zarill:BAAALgADCgcJBwAAAA==.Zartman:BAAALgAECgMJBwAAAA==.Zayzoo:BAABLgAECn8bAAIdAAkJjxZmCABeAQAdAAkJjxZmCABeAQAAAA==.Zazie:BAABLgAECn8VAAIEAAcJ9QZoyAD9AAAEAAcJ9QZoyAD9AAAAAA==.',
Ze='Zekröm:BAACLgAFFH8bAAIYAAUJcA5WDgCdAAAYAAUJcA5WDgCdAAAuAAQKfx8AAhgACQkyEmwVAKkBABgACQkyEmwVAKkBAAAA.Zekrøm:BAABLgAECn8lAAIeAAgJjxrvGQBEAgAeAAgJjxrvGQBEAgABLgAFFAUJGwAYAHAOAA==.Zeno:BAACLgAFFH8kAAINAAkJxh0yBgB6AgANAAkJxh0yBgB6AgAuAAQKfxcAAg0ACQkyJfgCAKcDAA0ACQkyJfgCAKcDAAAA.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgAECgEJAQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQATAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQATAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAABLgAECn8xAAIPAAkJQRBZCQCpAQAPAAkJQRBZCQCpAQAAAA==.',
Zi='Zinbar:BAABLgAECn8YAAIlAAgJHxBjIwCCAQAlAAgJHxBjIwCCAQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAABLgAECn8ZAAQkAAkJahmREwAfAgAkAAkJPRmREwAfAgAZAAQJ9BVWVADzAAAaAAEJTQJtcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQATAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAIEAAgJXCBkLwC1AgAEAAgJXCBkLwC1AgAAAA==.Çloudsham:BAAALgAECgEJAgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8vAAQiAAgJpiKpBwD/AgAiAAgJpiKpBwD/AgAcAAUJABoGOwBPAQAQAAEJBhiLfQBDAAAAAA==.',
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
