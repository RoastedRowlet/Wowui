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

local lookup = {'DemonHunter-Havoc','DeathKnight-Blood','Paladin-Protection','Mage-Frost','Mage-Fire','Mage-Arcane','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Warrior-Fury','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Hunter-BeastMastery','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warrior-Protection','Warrior-Arms','Priest-Discipline','DemonHunter-Devourer','Monk-Windwalker','Hunter-Survival','Druid-Balance','Druid-Guardian','Druid-Feral','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aaylasecura:BAACLgAFFH8VAAIBAAQJOx1vDABIAQABAAQJOx1vDABIAQAuAAQKfz0AAgEACQkuJEYDACQDAAEACQkuJEYDACQDAAAA.',
Ab='Absinth:BAABLgAFFH8IAAICAAQJHhhGIgDZAAACAAQJHhhGIgDZAAABLgAFFAQJDgADAHAMAA==.Absolutezero:BAACLgAFFH8SAAMEAAQJdBqWVQAxAQAEAAQJdBqWVQAxAQAFAAIJWwIoBgBgAAAuAAQKfzYAAwQACAnRIJwvAFoCAAQACAmmIJwvAFoCAAYABAmFHTELAM8AAAAA.',
Ac='Acetamnophen:BAAALgADCgYJBgABLgAFFAkJIwAHAGoWAA==.',
Ad='Advïl:BAAALgAECgQJBAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ah='Ahronzis:BAAALgADCgUJBQAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Alder:BAAALgAECgkJEgAAAA==.Aletstrasza:BAACLgAFFH8UAAIIAAQJ4xBzGwDgAAAIAAQJ4xBzGwDgAAAuAAQKf0UAAwgACQlHH+IDAP4CAAgACQlHH+IDAP4CAAkAAQluBVecACUAAAAA.Alexjuander:BAABLgAECn8fAAQKAAgJlRL6FQAaAQALAAgJbwjnigAkAQAKAAYJAhP6FQAaAQAMAAQJqg2kHwCvAAAAAA==.Alexsander:BAABLgAECn8YAAMJAAYJJxGfSAAIAQAJAAYJJxGfSAAIAQANAAIJNgZ/IgBDAAAAAA==.Allysah:BAAALgAECgEJAgABLgAFFAQJIwAOANgHAA==.Alphard:BAABLgAECn9EAAMPAAkJsSNEAgA5AwAPAAkJsSNEAgA5AwAQAAEJvBvVHgA5AAAAAA==.Alphatrion:BAAALgADCgQJBAAAAA==.',
Am='Amarri:BAAALgAECgUJBwAAAA==.',
An='Anelowyn:BAABLgAECn8xAAIRAAkJtRm4DwBgAgARAAkJtRm4DwBgAgAAAA==.',
Ap='Apocal:BAACLgAFFH8UAAISAAkJWRIWAgCdAQASAAkJWRIWAgCdAQAuAAQKfxUAAhIACAmnG3gGACsCABIACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Aralgi:BAAALgAECgEJAQAAAA==.Arete:BAABLgAECn8cAAITAAYJcB1QBQCtAQATAAYJcB1QBQCtAQAAAA==.Arlandil:BAAALgAECgQJBAAAAA==.Artaimya:BAABLgAECn8VAAIGAAYJoyJ6AwDpAQAGAAYJoyJ6AwDpAQAAAA==.Artemìs:BAAALgAECgQJBgAAAA==.',
As='Asmodyus:BAAALgADCgYJBgAAAA==.',
At='Ataraxya:BAAALgAECgUJBQAAAA==.Atmosphere:BAAALgAECgYJCAAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgYJCAAUAAAAAA==.Aurelian:BAAALgADCgcJBwAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAFFAQJBgAEAJ0EAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgcJDwAAAA==.Babs:BAAALgAECgUJBgAAAA==.Backspin:BAAALgAECgUJBQABLgAFFAIJAgAUAAAAAA==.Baraden:BAAALgAECgUJDAAAAA==.Basutai:BAABLgAECn8iAAIVAAkJ5COlAgB+AwAVAAkJ5COlAgB+AwAAAA==.',
Be='Beanohuntz:BAAALgAECgEJAQAAAA==.Beefstout:BAAALgAECgkJCAAAAA==.Beefsun:BAAALgAECgkJAgAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgcJEAAAAA==.Bih:BAACLgAFFH8GAAIWAAMJcQkWTgCHAAAWAAMJcQkWTgCHAAAuAAQKfyEAAhYABwkKGPouAOgBABYABwkKGPouAOgBAAAA.Birgetta:BAACLgAFFH8OAAIXAAQJIgt0SwAVAQAXAAQJIgt0SwAVAQAuAAQKfzMAAxcACQmsEdk8AO0BABcACQmsEdk8AO0BAAcABgltA/klAIYAAAEuAAQKCQkaAAEAWA4A.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIIAAgJNhlHDABxAgAIAAgJNhlHDABxAgABLgAECgkJGQACANkWAA==.Blasphemous:BAAALgAECgEJAwAAAA==.Blee:BAABLgAECn8zAAICAAkJGBwfEAAKAgACAAkJGBwfEAAKAgAAAA==.Bleefleenix:BAAALgAECgYJBgAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAAUAAAAAA==.Blâster:BAAALgAECgEJAQAAAA==.',
Bo='Bobodaklown:BAABLgAECn8jAAMOAAkJ9BabOgA5AgAOAAkJYhabOgA5AgADAAIJmxWvOwBtAAAAAA==.Boomnblood:BAAALgADCgEJAQABLgAFFAUJFgAYADwGAA==.Boomnbrew:BAACLgAFFH8WAAIYAAUJPAaHMgDeAAAYAAUJPAaHMgDeAAAuAAQKfzUAAhgACQkpFPYXAOgBABgACQkpFPYXAOgBAAAA.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8ZAAMHAAkJQAxLHQDEAAAXAAUJAQ/gkwAYAQAHAAcJBwpLHQDEAAAAAA==.',
Br='Brewman:BAACLgAFFH8cAAIZAAYJxBsIDADNAQAZAAYJxBsIDADNAQAuAAQKfzYAAxkACQnmITMFAFcDABkACQnmITMFAFcDABgACAnhDaI0ACwBAAAA.Bringtherain:BAAALgAECgEJAQAAAA==.Brisket:BAAALgAECgYJBgAAAA==.',
Bu='Bubonic:BAABLgAECn8sAAIaAAkJHxYuPAAQAgAaAAkJHxYuPAAQAgAAAA==.Buenasalud:BAABLgAECn8lAAIbAAkJjBvHDgB8AgAbAAkJjBvHDgB8AgAAAA==.Business:BAAALgAECgEJAQABLgAFFAIJBAAUAAAAAA==.',
Ca='Caball:BAAALgAECgEJAgAAAA==.Carcharias:BAAALgAECgYJBwAAAA==.Caylea:BAACLgAFFH8pAAITAAcJhRf9CACNAQATAAcJhRf9CACNAQAuAAQKfy4AAhMACQm6IAYZAIMCABMACQm6IAYZAIMCAAAA.',
Ch='Chalis:BAABLgAECn8iAAMMAAcJYB/BCgATAgALAAYJrB52LgAeAgAMAAYJ5h3BCgATAgAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAACLgAFFH8SAAQcAAUJkxkILgAqAQAcAAQJCh0ILgAqAQAdAAIJrgKFTwBZAAAeAAEJAADKGwAAAAAuAAQKfyMABBwACAmKFbYvAPYBABwACAmKFbYvAPYBAB0AAwkvCM+DAGgAAB4AAwmzCWIzAGMAAAAA.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAACLgAFFH8XAAIEAAQJPgyCNAD1AAAEAAQJPgyCNAD1AAAuAAQKfzIAAwQACQk4F1lRAOgBAAQACQk4F1lRAOgBAAUAAQm6A2ARACsAAAAA.Corleon:BAAALgADCgMJAwAAAA==.Corvus:BAAALgAECgUJDgAAAA==.',
Cr='Crizlock:BAAALgAECgEJAQABLgAECgcJGQAXAEYjAA==.Crowdcontrol:BAABLgAECn8aAAIDAAkJFiAtBgCGAgADAAkJFiAtBgCGAgAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAACLgAFFH8XAAIfAAQJQxYdDQDaAAAfAAQJQxYdDQDaAAAuAAQKf0IAAx8ACQmIGwECADQCAB8ACAm1HQECADQCACAACQlZDjIMAN4BAAAA.',
Cu='Cuahtemoc:BAAALgAECgEJAQAAAA==.Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgABLgAFFAIJAgAUAAAAAA==.Cursis:BAAALgAECgIJAgAAAA==.',
Da='Daddysixinch:BAABLgAFFH8MAAIaAAUJWhWDVABJAQAaAAUJWhWDVABJAQAAAA==.Daelin:BAABLgAECn8zAAMOAAkJ6CMJBwA3AwAOAAkJ6CMJBwA3AwAVAAEJJw2jkgAsAAAAAA==.Danye:BAAALgAECgQJBQAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darkcleric:BAAALgADCgYJBgAAAA==.Darknous:BAAALgAECgEJAQAAAA==.Darktotems:BAAALgAECgUJBQAAAA==.Dasyra:BAAALgADCgYJBgABLgAFFAQJFAAWAEgLAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deadball:BAAALgAECgEJAQABLgAFFAIJAgAUAAAAAA==.Deante:BAABLgAECn8ZAAIhAAYJWgxPPAAdAQAhAAYJWgxPPAAdAQAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathman:BAABLgAECn8ZAAICAAkJ2RYqEAAJAgACAAkJ2RYqEAAJAgAAAA==.Deathrite:BAAALgAFFAEJAQAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCgAAAA==.Demo:BAAALgAFFAMJAwABLgAFFAQJCgAaAFMiAA==.Demonmommy:BAAALgADCgEJAgAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAACLgAFFH8QAAIdAAUJEAsjLQDfAAAdAAUJEAsjLQDfAAAuAAQKfygAAh0ACQkTFBAfAOoBAB0ACQkTFBAfAOoBAAAA.',
Dh='Dhchin:BAAALgAFFAMJAwABLgAFFAkJLwAPADQgAA==.Dhomsak:BAABLgAFFH8iAAIiAAgJlx3fDgDMAQAiAAgJlx3fDgDMAQABLgAFFAgJLwAEAD4gAA==.',
Di='Diamonds:BAAALgADCgEJAQABLgAFFAIJAgAUAAAAAA==.Die:BAABLgAFFH8JAAIOAAMJwRLZOQCyAAAOAAMJwRLZOQCyAAAAAA==.Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgYJCAAAAA==.Distrath:BAAALgADCgkJCQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQABLgAFFAkJLwAPADQgAA==.',
Do='Doadin:BAABLgAECn8sAAMVAAkJoBvCDQCqAgAVAAkJoBvCDQCqAgAOAAEJ1gHBXQEgAAAAAA==.Doominatrix:BAACLgAFFH8UAAMLAAUJsgq1YwD/AAALAAQJagq1YwD/AAAKAAIJNAdGKgBDAAAuAAQKfzIAAwsACAm+GHU+AOIBAAsABwm+GHU+AOIBAAoAAQkAAKQqAEoAAAAA.Dotem:BAAALgAECgEJAQAAAA==.',
Dr='Draggum:BAABLgAECn8eAAMJAAgJ+xlxHADyAQAJAAgJ+xlxHADyAQAIAAMJpxDaKQCdAAABLgAECgcJIAAEAPEaAA==.Dragune:BAAALgAECgEJAQABLgAECgcJIgAMAGAfAA==.Dreadmagey:BAAALgAECggJCAABLgAECgkJVwATACceAA==.Dreadraven:BAABLgAECn9XAAMTAAkJJx5FCQDOAgATAAkJJx5FCQDOAgAgAAMJ6AtNYwBbAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8pAAMBAAkJRxRuIQCxAQABAAgJvxRuIQCxAQAiAAgJuBA0awBOAQABLgAECgEJAQAUAAAAAA==.Dreddstorm:BAAALgAECgEJAgAAAA==.Drewuw:BAABLgAECn8bAAIjAAkJwBaOGQAVAgAjAAkJwBaOGQAVAgABLgAECgkJHQAiAJ0bAA==.Druidhams:BAACLgAFFH8VAAIWAAUJGRg5KwALAQAWAAUJGRg5KwALAQAuAAQKfzUAAhYACQn+HpUNAO0CABYACQn+HpUNAO0CAAAA.',
Ea='Eamon:BAAALgAFFAEJAQABLgAFFAMJDQAhAMcUAA==.',
Ei='Eightball:BAAALgAFFAIJAgAAAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgUJBgAAAA==.Elisha:BAACLgAFFH8jAAIOAAQJ2AcpXAD4AAAOAAQJ2AcpXAD4AAAuAAQKf30AAg4ACQlRG7wnAGQCAA4ACQlRG7wnAGQCAAAA.Eloquence:BAAALgAECgQJBQAAAA==.Elsyra:BAAALgAECgYJDgAAAA==.',
Er='Erebostro:BAABLgAECn8/AAIXAAkJYxqTIQBfAgAXAAkJYxqTIQBfAgAAAA==.',
Ev='Everclear:BAAALgAECggJDAABLgAFFAQJDgADAHAMAA==.Evillux:BAACLgAFFH8FAAMLAAIJbQVatQBtAAALAAIJbQVatQBtAAAMAAEJZACpLQAhAAAuAAQKfy8AAwsACQm2ED1NALMBAAsACQlHED1NALMBAAwABQnmDH0qABcBAAAA.',
Ey='Eyeguy:BAABLgAECn8VAAMiAAkJHxyYJwBmAgAiAAkJLBmYJwBmAgABAAQJ+h+0NgAsAQAAAA==.',
Fa='Fadedvoker:BAAALgAFFAEJAQABLgAFFAUJCwARALQTAA==.Fathercow:BAACLgAFFH8WAAIhAAUJmh6hHQBtAQAhAAUJmh6hHQBtAQAuAAQKfywAAiEACQn3H3gGABkDACEACQn3H3gGABkDAAAA.Faultline:BAAALgAECgIJAgABLgAECgkJJAAjALcbAA==.Fauxtotem:BAAALgAECgUJBQAAAA==.',
Fi='Fingies:BAACLgAFFH8RAAQLAAQJaBvoUAAkAQALAAQJrRboUAAkAQAKAAEJoh68GwBWAAAMAAEJ1RI9IwBPAAAuAAQKfz4AAwsACQm9JAcQAMwCAAsABwlHJQcQAMwCAAwABQmyHkoVAJ8BAAAA.Fistin:BAAALgAECgYJBwAAAA==.',
Fl='Flexyheals:BAAALgADCgYJBgAAAA==.',
Fr='Frieren:BAAALgADCgYJBgABLgAFFAYJEwALAO4YAA==.',
Fu='Fungies:BAABLgAFFH8HAAIWAAQJsgtXOQDIAAAWAAQJsgtXOQDIAAABLgAFFAQJEQALAGgbAA==.Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAACLgAFFH8UAAIXAAUJQBh0NwA+AQAXAAUJQBh0NwA+AQAuAAQKfzQAAxcACQkhI8wKAP8CABcACQkhI8wKAP8CACQABQmiDdY9ANQAAAAA.',
Ga='Gaijin:BAAALgADCgMJAwABLgAFFAMJDQAhAMcUAA==.Galaxsea:BAABLgAECn8YAAIjAAkJ1x0xDgBkAgAjAAkJ1x0xDgBkAgAAAA==.Gargapew:BAAALgAECgIJAgABLgAFFAMJBgAEAMQJAA==.',
Ge='Gerthquake:BAABLgAECn8rAAMdAAkJzRnhFABCAgAdAAkJzRnhFABCAgAcAAkJOB4uNgDYAQAAAA==.',
Gf='Gfour:BAABLgAECn8fAAIZAAgJjhx2EwAvAgAZAAgJjhx2EwAvAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.Ghraxx:BAAALgADCgkJCQAAAA==.Ghraxxy:BAAALgAECgkJEQAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.Giren:BAAALgAFFAMJAwABLgAFFAkJLAAOANwdAA==.',
Go='Gobø:BAABLgAECn8uAAIXAAcJ5wp6IADiAAAXAAcJ5wp6IADiAAAAAA==.Goodytwoshoe:BAAALgAECgIJBwAAAA==.',
Gr='Grimmreefer:BAAALgAECgUJBQAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgQJCgAAAA==.',
['Gâ']='Gâlvatron:BAAALgADCgEJAQAAAA==.',
Ha='Hacks:BAAALgADCgcJBwAAAA==.Hakz:BAAALgADCgkJCQAAAA==.',
He='Heart:BAABLgAFFH8HAAMhAAMJtQcpNwCuAAAhAAMJtQcpNwCuAAARAAEJgAIwQQA0AAABLgAFFAQJCgAaAFMiAA==.Hefferhumper:BAAALgAECgcJDQAAAA==.Help:BAAALgADCgEJAQAAAA==.Helravn:BAAALgAECgIJAgAAAA==.',
Ho='Homlock:BAABLgAFFH8TAAMLAAYJeiSsEgCkAQALAAYJpiOsEgCkAQAKAAEJNCVECwBwAAABLgAFFAgJLwAEAD4gAA==.Homsorc:BAACLgAFFH8vAAQEAAgJPiDiBwDlAQAEAAgJPiDiBwDlAQAFAAUJRxosAQCoAQAGAAEJByRtBQBWAAAuAAQKfyQAAgQACQmuJTMFAK8DAAQACQmuJTMFAK8DAAAA.Homtard:BAABLgAFFH8WAAQHAAkJciIOBgAUAgAHAAgJ5R8OBgAUAgAkAAQJFh+QDABhAQAXAAMJjSMnNADXAAABLgAFFAgJLwAEAD4gAA==.Homtotem:BAABLgAFFH8FAAIdAAUJ/xNOFAD8AAAdAAUJ/xNOFAD8AAABLgAFFAgJLwAEAD4gAA==.Hope:BAACLgAFFH8IAAIVAAMJ0hkIJwDqAAAVAAMJ0hkIJwDqAAAuAAQKf0kAAxUACQmRIHQKAOQCABUACQmRIHQKAOQCAA4ABAnnBzcSAaMAAAAA.',
['Hô']='Hôûnd:BAAALgAECgEJAQAAAA==.',
Id='Idun:BAAALgAECgYJCgAAAA==.',
Il='Illiandray:BAABLgAECn8yAAMMAAkJyh20AgCGAgAMAAkJyh20AgCGAgALAAgJUgp3kQAYAQAAAA==.Ilswyn:BAAALgADCgkJDwABLgAECgkJOQAiAGElAA==.',
Im='Imu:BAACLgAFFH8KAAMkAAMJoCGGHADsAAAkAAMJoCGGHADsAAAXAAEJxhmWoQBNAAAuAAQKfyIABCQABwkOJRYNAFQCACQABwkOJRYNAFQCAAcABQk/DfFUAPYAABcAAgmLCs6nAHYAAAEuAAUUCAksAA4APCQA.Imzadi:BAAALgAECgkJCQAAAA==.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn85AAIiAAkJYSWZAgBeAwAiAAkJYSWZAgBeAwAAAA==.',
Io='Ionise:BAABLgAECn8kAAIJAAkJKRt7DwBvAgAJAAkJKRt7DwBvAgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Iskgard:BAAALgAECgcJBwAAAA==.Isklar:BAACLgAFFH8JAAICAAIJJBz6LgCJAAACAAIJJBz6LgCJAAAuAAQKfy8AAgIACAm4I4UEAAIDAAIACAm4I4UEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAABLgAECn8wAAQJAAkJWh2DGQAKAgAJAAgJ0RuDGQAKAgANAAUJ0hzOCAChAQAIAAMJbwy0OQCdAAAAAA==.Jaxattax:BAAALgAECgIJAgAAAA==.',
Je='Jer:BAABLgAECn8cAAIPAAkJ1RAyFABzAgAPAAkJ1RAyFABzAgAAAA==.',
Ju='Jugernat:BAAALgADCgQJBwAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAFFAMJDQAhAMcUAA==.',
Ka='Kaalo:BAAALgADCgUJBQAAAA==.Kammo:BAACLgAFFH8UAAIaAAQJxiDtPQB8AQAaAAQJxiDtPQB8AQAuAAQKf0QAAhoACQkxJlMDAGoDABoACQkxJlMDAGoDAAAA.Kazypher:BAAALgAECgMJCgAAAA==.',
Ke='Keeah:BAAALgAECgUJEAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAIZAAkJCgfzMQAvAQAZAAkJCgfzMQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAFFAMJDQAhAMcUAA==.Kiwi:BAAALgAFFAEJAQAAAA==.',
Kl='Klingnor:BAAALgAECgQJBAAAAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8jAAIHAAkJahYRBQAqAgAHAAkJahYRBQAqAgAuAAQKfyMAAgcABwnLIbIJANkBAAcABwnLIbIJANkBAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwickin:BAAALgAECgYJCwABLgAECgcJIAAEAPEaAA==.Kwikin:BAABLgAECn8gAAIEAAcJ8RqMVQA3AgAEAAcJ8RqMVQA3AgAAAA==.',
Ky='Kyreen:BAABLgAECn8gAAIXAAkJhRFfEQBkAQAXAAkJhRFfEQBkAQAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECgkJGAAjANcdAA==.',
La='Laaz:BAACLgAFFH8cAAIiAAYJJwuMIgACAQAiAAYJJwuMIgACAQAuAAQKfzYAAiIACQlXEzQ6AN4BACIACQlXEzQ6AN4BAAAA.Lamalen:BAABLgAECn8UAAIOAAcJnxoSYQDBAQAOAAcJnxoSYQDBAQAAAA==.Lasercow:BAAALgAECgcJCAABLgAFFAUJFgAhAJoeAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Liena:BAAALgADCgkJCwAAAA==.Linthvia:BAAALgAECgYJDgAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgAECgEJAwAAAA==.',
Lo='Locknloaded:BAAALgAFFAEJAQAAAA==.',
Lu='Luciuos:BAABLgAECn8ZAAMlAAkJqwJTXwCbAAAlAAkJqwJTXwCbAAAWAAcJ9QHvngByAAAAAA==.Lucreesha:BAAALgAECgYJBgABLgAECgkJHQAiAJ0bAA==.Lukafox:BAACLgAFFH8iAAIcAAgJ0R7FEADjAQAcAAgJ0R7FEADjAQAuAAQKfyAAAxwACQlZH6gHAPoCABwACQlZH6gHAPoCAB0AAQmKAn6WAB0AAAAA.Lunastarvale:BAABLgAECn9GAAIXAAkJBR5gFQCoAgAXAAkJBR5gFQCoAgAAAA==.Lunereclips:BAAALgAECgQJCgAAAA==.Lupuis:BAAALgAECgEJAgAAAA==.',
Ly='Lyruh:BAAALgAECggJCAAAAA==.',
Ma='Macha:BAABLgAECn8UAAMcAAgJxx05BgADAgAcAAcJehw5BgADAgAdAAEJYhLIKwA0AAAAAA==.Madith:BAACLgAFFH8QAAIiAAUJBR7iGABSAQAiAAUJBR7iGABSAQAuAAQKfyUAAiIACAmMIEMYAIQCACIACAmMIEMYAIQCAAAA.Magicjamo:BAAALgAECgUJBQAAAA==.Maleficênt:BAAALgAECggJEQABLgAFFAYJHAAmAPALAA==.Malefisico:BAABLgAECn8lAAMMAAkJ8hJCFgD2AAALAAkJKBHFbQCFAQAMAAUJ3BRCFgD2AAAAAA==.Malgarok:BAABLgAECn8lAAILAAgJWBygHgCfAgALAAgJWBygHgCfAgABLgAECgYJEAAUAAAAAA==.Mardríft:BAACLgAFFH8VAAIlAAQJUheDHwAgAQAlAAQJUheDHwAgAQAuAAQKfzoAAiUACQnYIX0JALwCACUACQnYIX0JALwCAAAA.Marero:BAAALgAECgEJAQAAAA==.Mazga:BAABLgAECn9MAAIeAAkJmR12BACpAgAeAAkJmR12BACpAgAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8vAAIkAAkJihiODgBCAgAkAAkJihiODgBCAgAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgAECgQJBAAAAA==.Metta:BAABLgAFFH8WAAIiAAcJAQuuFwBeAQAiAAcJAQuuFwBeAQAAAA==.Mezoti:BAACLgAFFH8SAAMJAAQJGwUYQQDDAAAJAAQJGwUYQQDDAAAIAAIJwAHPKgBEAAAuAAQKfxkAAwkACAniDoEyAGsBAAkACAniDoEyAGsBAAgACAm/CHUZAD4BAAAA.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCgkJEwAAAA==.Miraclehwip:BAAALgAECgcJDQAAAA==.',
Mo='Moji:BAACLgAFFH8KAAIZAAMJjxFFQACjAAAZAAMJjxFFQACjAAAuAAQKfzQAAhkACQn4HGAMANMCABkACQn4HGAMANMCAAAA.Monstermayi:BAACLgAFFH8UAAITAAUJ7BTBHwAzAQATAAUJ7BTBHwAzAQAuAAQKfy8AAhMACQnXGNUYACcCABMACQnXGNUYACcCAAAA.Mooknight:BAABLgAECn8/AAICAAkJ8BXvEgDhAQACAAkJ8BXvEgDhAQAAAA==.Moomoo:BAAALgAFFAEJAQAAAA==.Moosen:BAAALgAECgcJBwAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moreina:BAAALgAECgQJBAABLgAFFAYJHAAbAJscAA==.Morgoth:BAAALgAFFAEJAwAAAA==.Moyapanda:BAABLgAECn8nAAIjAAgJXBrPHADIAQAjAAgJXBrPHADIAQAAAA==.',
Mu='Muggy:BAABLgAECn9JAAIQAAkJkRzKAgCgAgAQAAkJkRzKAgCgAgAAAA==.',
My='Myluutarania:BAAALgAECgcJCwABLgAFFAcJDgANANoUAA==.Myrothar:BAABLgAECn8aAAMVAAgJVhbnLQCmAQAVAAcJeBfnLQCmAQAOAAYJDQO+HAGXAAAAAA==.Mytastical:BAACLgAFFH8GAAIEAAQJnQRidwDrAAAEAAQJnQRidwDrAAAuAAQKfykAAgQACQl4F152AI0BAAQACQl4F152AI0BAAAA.',
['Må']='Måzikeen:BAAALgAECgQJBAABLgAFFAQJFAAWAEgLAA==.',
['Mæ']='Mæve:BAACLgAFFH8UAAIWAAQJSAtaGACwAAAWAAQJSAtaGACwAAAuAAQKfzMAAxYACQnOGCwdAF0CABYACQnOGCwdAF0CACUABQmNESxGABUBAAAA.',
['Më']='Mëgatron:BAAALgAECgEJAQAAAA==.',
Na='Namalis:BAACLgAFFH8TAAQLAAYJ7hhhTAAuAQALAAQJMBphTAAuAQAKAAIJ9h6iHABVAAAMAAEJgw8yIQBSAAAuAAQKfx8ABAsACQkPJAU5ACcCAAsABwnnIwU5ACcCAAwAAgkWIqA8AMIAAAoAAQkAADIhAG0AAAAA.Nanielito:BAACLgAFFH8GAAIEAAMJxAmriwDCAAAEAAMJxAmriwDCAAAuAAQKfyUAAgQACQnGH4IcALECAAQACQnGH4IcALECAAAA.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8TAAIEAAUJfBWuYQAeAQAEAAUJfBWuYQAeAQAuAAQKfygAAgQACQmCHAomAIMCAAQACQmCHAomAIMCAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
Ni='Nineball:BAAALgAECgEJAQABLgAFFAIJAgAUAAAAAA==.',
No='Nojak:BAAALgAECgUJCAABLgAFFAIJBgAXALMHAA==.Nokoa:BAAALgAECggJCAAAAA==.Nonae:BAABLgAECn8lAAIXAAkJJxwbEgCnAgAXAAkJJxwbEgCnAgAAAA==.Norivari:BAAALgAECgUJCwAAAA==.Nosali:BAAALgAECgcJEwABLgAFFAYJHAAbAJscAA==.Notawarlock:BAAALgADCgMJAwAAAA==.Noxilis:BAAALgAECgEJAQAAAA==.',
Ob='Obiwon:BAAALgAECgYJEQAAAA==.',
Og='Ogsmashsauce:BAAALgAECgEJAQAAAA==.',
Ol='Oldschooler:BAAALgAECggJCAAAAA==.',
Om='Omegá:BAACLgAFFH8OAAIDAAQJcAwkCwDDAAADAAQJcAwkCwDDAAAuAAQKfyIAAgMACQkuFcERAKkBAAMACQkuFcERAKkBAAAA.',
Oo='Oopsalldruid:BAAALgAECgUJCQABLgAECgcJIAAEAPEaAA==.',
Op='Optìmusprìme:BAABLgAECn8/AAIfAAkJJh8zBgCrAgAfAAkJJh8zBgCrAgAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Pandalock:BAAALgAECgYJBgAAAA==.Papa:BAACLgAFFH8FAAMKAAIJcB/hIQBOAAALAAEJRyBGvABSAAAKAAEJmh7hIQBOAAAuAAQKfzUABAwACQmjIcUCANYCAAwABwlRIcUCANYCAAoACAmEI6kCAKECAAsABQmhHIBhAHwBAAAA.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAFFAEJAQAAAA==.',
Po='Pockets:BAABLgAECn8uAAIEAAkJExYgSwD6AQAEAAkJExYgSwD6AQABLgAFFAIJAgAUAAAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAABLgAECn8kAAILAAgJkQPvsADjAAALAAgJkQPvsADjAAAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAACLgAFFH8NAAMhAAMJxxRyMADRAAAhAAMJxxRyMADRAAARAAIJowhTMgB8AAAuAAQKf0YAAyEACQkmH0gLALsCACEACQkmH0gLALsCABEABAkIFdsWAIIAAAAA.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAFFAIJBAAAAA==.',
['Pø']='Pø:BAAALgAFFAEJAgAAAA==.',
Qu='Quantum:BAAALgAECgEJAQAAAA==.Quick:BAAALgAECgEJAwABLgAECgcJIAAEAPEaAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Ragnarök:BAAALgADCgEJAQAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Ratchet:BAAALgAECgEJAQAAAA==.Ratha:BAACLgAFFH8cAAIDAAYJCRKmBAD5AAADAAYJCRKmBAD5AAAuAAQKfzEAAwMACQmqGRISAKUBAAMACQmqGRISAKUBAA4ABAkVDJsgAZMAAAAA.Ravener:BAAALgAECgYJBwAAAA==.Ravincible:BAAALgAECgYJCwAAAA==.Razeal:BAABLgAECn8gAAMOAAYJ/yEBXgC1AQAOAAYJqSEBXgC1AQADAAIJKxjiMQCGAAAAAA==.',
Re='Reaper:BAACLgAFFH8KAAIaAAQJUyKPRQBpAQAaAAQJUyKPRQBpAQAuAAQKfyEAAxoABwkPJUItAEsCABoABwkPJUItAEsCAAIAAgk+B+BAAEkAAAAA.Reeah:BAAALgADCgkJCQAAAA==.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAABLgAECn8lAAMlAAgJbQ0cPAAhAQAlAAgJaQscPAAhAQAnAAEJ0A8cVAAxAAAAAA==.Reported:BAAALgAECgEJAQAAAA==.',
Rh='Rhettranger:BAAALgADCgEJAQAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8vAAMPAAkJNCBEAgDFAgAPAAgJoh9EAgDFAgAQAAIJgRnqDABmAAAuAAQKfysAAw8ACQlIJSMJAJMCAA8ACAnGJSMJAJMCABAAAwnpI/4NADoBAAAA.Rokkgar:BAABLgAECn8wAAIdAAkJjRXlJwCuAQAdAAkJjRXlJwCuAQABLgAECgkJNAAQAGgRAA==.Roosterr:BAAALgADCgkJFgAAAA==.Rottontoe:BAAALgAECgcJDgAAAA==.',
Ru='Ruwazi:BAAALgAECgYJDwAAAA==.',
Rx='Rxdh:BAAALgAECgIJAgAAAA==.',
Ry='Ryujin:BAAALgAECgUJBwAAAA==.',
Sa='Sainted:BAAALgAECgUJBAAAAA==.Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scared:BAACLgAFFH8YAAIbAAUJext0BwBRAQAbAAUJext0BwBRAQAuAAQKfz0AAhsACAkxH7kKALsCABsACAkxH7kKALsCAAAA.Scottamus:BAAALgAFFAMJBAAAAA==.',
Se='Secarious:BAABLgAECn8bAAITAAgJnhDnNQBxAQATAAgJnhDnNQBxAQAAAA==.Sediaria:BAAALgAECgkJCQABLgAECgkJGgABAFgOAA==.Sehnsucht:BAACLgAFFH8MAAMlAAQJJBI0JQABAQAlAAQJJBI0JQABAQAWAAMJfg6vRQCeAAAuAAQKfygAAxYACQktHAkeAE4CABYACQktHAkeAE4CACUAAQkAGqB2AEkAAAAA.Serius:BAAALgAECgQJBAABLgAECgkJHQAiAJ0bAA==.',
Sh='Shavoo:BAAALgAECgkJCQAAAA==.Shmadu:BAAALgAECgcJCwAAAA==.Shockk:BAABLgAECn8gAAMdAAkJGRZqKgCfAQAdAAkJGRZqKgCfAQAcAAMJ4AKOigBpAAAAAA==.Shone:BAAALgAECgUJBQAAAA==.',
Si='Siovhan:BAAALgAECgkJEgAAAA==.',
Sl='Sly:BAACLgAFFH8KAAIoAAMJKRvGCADwAAAoAAMJKRvGCADwAAAuAAQKfxUAAigABwkuIM4EACoCACgABwkuIM4EACoCAAEuAAUUBAkKABoAUyIA.',
Sm='Smóóthbói:BAACLgAFFH8JAAIEAAYJPgZTdAD1AAAEAAYJPgZTdAD1AAAuAAQKfzIAAgQACQkaGOoOAHgBAAQACQkaGOoOAHgBAAAA.',
So='Sohei:BAAALgADCgEJAQABLgAFFAYJEwALAO4YAA==.Sona:BAABLgAECn83AAIJAAkJ8BdPEwBEAgAJAAkJ8BdPEwBEAgAAAA==.Soola:BAABLgAECn8fAAMcAAgJoQ0XUAByAQAcAAgJoQ0XUAByAQAdAAQJzAwLfQB5AAABLgAFFAYJHAADAAkSAA==.Soulmonkey:BAAALgAFFAMJAwAAAA==.',
Sp='Spoof:BAAALgAECgIJAgAAAA==.Spoopadin:BAAALgAECgIJBgAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.Sprigg:BAAALgADCgkJCQABLgAFFAYJCQAEAD4GAA==.',
St='Stabbymoose:BAAALgAECgEJAQAAAA==.Stack:BAACLgAFFH8JAAIkAAIJ8hvkJACrAAAkAAIJ8hvkJACrAAAuAAQKfxcAAiQABwnHHmoVAPgBACQABwnHHmoVAPgBAAEuAAUUBAkKABoAUyIA.Stompycouch:BAACLgAFFH8FAAIdAAIJJRH6RAB2AAAdAAIJJRH6RAB2AAAuAAQKfysAAh0ACAnyHDsXAF4CAB0ACAnyHDsXAF4CAAAA.Stoned:BAABLgAECn8nAAMVAAkJJh/uCADhAgAVAAkJJh/uCADhAgAOAAMJ3wpdKAGJAAAAAA==.Stonedpriest:BAABLgAECn87AAIbAAkJliA7BwDYAgAbAAkJliA7BwDYAgAAAA==.Stripes:BAAALgADCgUJBQABLgAFFAIJAgAUAAAAAA==.',
Su='Sunreaver:BAABLgAECn8tAAIaAAkJcyOtFQDFAgAaAAkJcyOtFQDFAgAAAA==.Surrëal:BAABLgAECn8aAAIBAAkJWA7LIAByAQABAAkJWA7LIAByAQAAAA==.Surtain:BAACLgAFFH8JAAIlAAMJfgwCNACwAAAlAAMJfgwCNACwAAAuAAQKfx8AAiUACAk4Hs4UACsCACUACAk4Hs4UACsCAAAA.Suxiv:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetmask:BAABLgAECn8pAAMaAAkJjyPnDQD9AgAaAAkJjyPnDQD9AgApAAIJ2BoSJgChAAAAAA==.',
Sx='Sxv:BAAALgAFFAIJAwAAAA==.',
Sy='Sybela:BAAALgAECgEJAQABLgAECgcJEwAUAAAAAA==.Syl:BAACLgAFFH8UAAIXAAUJ4xX7OwA1AQAXAAUJ4xX7OwA1AQAuAAQKfy0AAxcACQlyG6sjAFQCABcACQlyG6sjAFQCAAcABQlVCnFZAN8AAAAA.Sylvanii:BAAALgAECgIJAgAAAA==.Sylvanäs:BAABLgAECn8UAAIHAAkJ5AssDgB8AQAHAAkJ5AssDgB8AQABLgAECgkJMgAMAModAA==.',
['Sï']='Sïdëswïpë:BAAALgAECgEJAgAAAA==.',
['Só']='Sóúndwâve:BAAALgAECgEJAgAAAA==.',
Ta='Tahitian:BAACLgAFFH8GAAIXAAIJsweIUQB8AAAXAAIJsweIUQB8AAAuAAQKfx8AAhcACQn3DmZKAMIBABcACQn3DmZKAMIBAAAA.Tahlreth:BAABLgAECn88AAMEAAkJ4R/vFgDPAgAEAAkJ4R/vFgDPAgAFAAEJuhm4EQBKAAAAAA==.Tandlia:BAAALgAECgUJCQAAAA==.Tanickz:BAABLgAECn8tAAIEAAkJ2BLXSQD9AQAEAAkJ2BLXSQD9AQAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJLAAdAPscAA==.Tanidgetotem:BAABLgAECn8sAAIdAAkJ+xz8CQD0AgAdAAkJ+xz8CQD0AgAAAA==.Tanya:BAACLgAFFH8SAAIkAAQJ7BYSEgA3AQAkAAQJ7BYSEgA3AQAuAAQKf0AAAiQACQmKI3kDAP8CACQACQmKI3kDAP8CAAAA.Tayanna:BAABLgAECn8cAAMOAAkJ2B4/eQB8AQAOAAkJ2B4/eQB8AQADAAcJAQgFKwDDAAAAAA==.',
Te='Teias:BAACLgAFFH8cAAIbAAYJmxyvBACnAQAbAAYJmxyvBACnAQAuAAQKfzcAAxsACQn5GhQTAEcCABsACQn5GhQTAEcCABEABgkCHfcnAI8BAAAA.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thoradin:BAAALgADCgEJAQAAAA==.Thuras:BAAALgADCgUJBQAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8iAAIEAAgJox8TPgAjAgAEAAgJox8TPgAjAgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgAECgkJCQAUAAAAAA==.',
Tr='Tricko:BAABLgAECn9SAAIXAAkJFB9yEgC+AgAXAAkJFB9yEgC+AgAAAA==.Trollskingx:BAABLgAECn8eAAIEAAcJwBacdADpAQAEAAcJwBacdADpAQAAAA==.Trollzy:BAABLgAECn8/AAMeAAkJLyGeAgDuAgAeAAkJLyGeAgDuAgAcAAQJjQljpACFAAAAAA==.Trunkmonkey:BAACLgAFFH8KAAILAAQJXw7pXwAIAQALAAQJXw7pXwAIAQAuAAQKfy8AAgsACQlbGhEfAGoCAAsACQlbGhEfAGoCAAAA.Trunky:BAAALgAECgYJCwAAAA==.Tryne:BAAALgAECgMJAwAAAA==.',
Ts='Tsaagan:BAACLgAFFH8TAAMLAAUJvha1TwAnAQALAAQJNha1TwAnAQAKAAIJ5RJoIgBOAAAuAAQKfy0ABAsACQkXIaMSALcCAAsACQkqH6MSALcCAAoABAkII/4KAIwBAAwABAkHHrQgAE4BAAAA.',
Tu='Tucker:BAABLgAECn8rAAIZAAkJgh3pCQD6AgAZAAkJgh3pCQD6AgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ud='Uddershaman:BAAALgAFFAIJAgAAAA==.',
Ul='Ultramagnús:BAAALgAECgEJAgAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAABLgAECn8eAAQaAAkJ/g6LfwBkAQAaAAcJVBKLfwBkAQACAAMJFQdtFQBRAAApAAEJlwprOgA0AAAAAA==.Unclear:BAAALgAECggJDQABLgAECgkJHgAaAP4OAA==.Under:BAAALgADCgcJDgABLgAECgkJHgAaAP4OAA==.Unparalleled:BAABLgAECn8nAAMIAAkJngldHwD7AAAIAAcJ5AddHwD7AAANAAcJHAsnEwDYAAAAAA==.Unqualified:BAAALgAECgIJAgAAAA==.',
Va='Vaaleros:BAAALgADCgYJBgAAAA==.Valiithria:BAAALgAECgQJBAAAAA==.Valkyruid:BAACLgAFFH8UAAIWAAgJBQ5dHwBeAQAWAAgJBQ5dHwBeAQAuAAQKfxcAAhYABwnCF4w2AM0BABYABwnCF4w2AM0BAAAA.',
Ve='Veluthil:BAAALgAECgYJCAABLgAFFAQJFAAWAEgLAA==.Vessel:BAAALgAFFAIJAgABLgAFFAQJCgAaAFMiAA==.',
Vi='Vixus:BAAALgAFFAEJAgAAAA==.',
Vx='Vxs:BAAALgAFFAIJAwAAAA==.',
['Vø']='Vøødu:BAAALgAECgYJCwABLgAECgcJGAAcAJEQAA==.',
Wa='Walshidan:BAABLgAECn8aAAIiAAkJ0xBHUgCPAQAiAAkJ0xBHUgCPAQAAAA==.Walshlel:BAAALgADCgkJCQAAAA==.Warangel:BAAALgAECgEJAQAAAA==.Waywatcher:BAAALgAFFAIJAwAAAA==.',
We='Wenus:BAAALgAECgUJBQAAAA==.',
Wi='Wiccaflame:BAABLgAECn8bAAIEAAkJdSDMGADFAgAEAAkJdSDMGADFAgAAAA==.Wiccasham:BAAALgAECgEJAQAAAA==.',
Wu='Wullgan:BAABLgAECn8fAAMhAAkJ2R6PEgBPAgAhAAgJvx6PEgBPAgARAAcJGBgnLQBuAQAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAABLgAFFH8MAAIIAAUJZRK2GQD7AAAIAAUJZRK2GQD7AAAAAA==.',
Xo='Xole:BAABLgAECn8fAAMiAAgJnxThWgB3AQAiAAgJnxThWgB3AQASAAQJIQSEIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8dAAIiAAkJnRuTMAA5AgAiAAkJnRuTMAA5AgAAAA==.Xyrna:BAAALgAFFAIJAgABLgAFFAYJHAADAAkSAA==.',
Ya='Yareli:BAABLgAECn88AAISAAkJFgmWEABDAQASAAkJFgmWEABDAQAAAA==.Yawa:BAABLgAFFH8HAAIaAAIJtA285ACCAAAaAAIJtA285ACCAAAAAA==.',
Ye='Yeahreally:BAAALgADCgkJCQAAAA==.Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQAUAAAAAA==.Zankrah:BAAALgAECgQJBAABLgAFFAYJHAAbAJscAA==.Zarill:BAAALgADCgcJBwAAAA==.Zartman:BAAALgAECgMJBwAAAA==.Zayzoo:BAABLgAECn8dAAIcAAkJMRqeBwDYAQAcAAkJMRqeBwDYAQAAAA==.Zazie:BAABLgAECn8VAAIEAAcJ9QZoyAD9AAAEAAcJ9QZoyAD9AAAAAA==.',
Ze='Zekröm:BAACLgAFFH8cAAImAAYJ8AuoDgC2AAAmAAYJ8AuoDgC2AAAuAAQKfyQAAiYACQneEmwVAKkBACYACQneEmwVAKkBAAAA.Zekrøm:BAABLgAECn8lAAIdAAgJjxrvGQBEAgAdAAgJjxrvGQBEAgABLgAFFAYJHAAmAPALAA==.Zeno:BAACLgAFFH8sAAIOAAkJ3B0yBgB6AgAOAAkJ3B0yBgB6AgAuAAQKfxcAAg4ACQkyJfgCAKcDAA4ACQkyJfgCAKcDAAAA.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgAECgIJAgAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQAUAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQAUAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAABLgAECn80AAIQAAkJaBFZCQCpAQAQAAkJaBFZCQCpAQAAAA==.',
Zi='Zinbar:BAABLgAECn8dAAIkAAkJ3hA4BQAcAQAkAAkJ3hA4BQAcAQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zo='Zoroark:BAAALgAECgEJAgABLgAFFAYJHAAmAPALAA==.',
Zu='Zune:BAABLgAECn8ZAAQjAAkJahmREwAfAgAjAAkJPRmREwAfAgAYAAQJ9BVWVADzAAAZAAEJTQJtcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQAUAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAIEAAgJXCBkLwC1AgAEAAgJXCBkLwC1AgAAAA==.Çloudsham:BAAALgAECgEJAgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8vAAQhAAgJpiKpBwD/AgAhAAgJpiKpBwD/AgAbAAUJABoGOwBPAQARAAEJBhiLfQBDAAAAAA==.',
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
