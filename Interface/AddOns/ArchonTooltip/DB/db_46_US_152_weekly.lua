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

local lookup = {'DemonHunter-Havoc','Paladin-Protection','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Devastation','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Warrior-Fury','Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Druid-Guardian','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Mage-Fire','Warrior-Protection','Warrior-Arms','Priest-Discipline','DemonHunter-Devourer','Monk-Windwalker','Druid-Restoration','Hunter-Survival','Druid-Balance','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaylasecura:BAACLgAFFH8RAAIBAAQJwxykCABOAQABAAQJwxykCABOAQAuAAQKfz0AAgEACQkuJCwCADEDAAEACQkuJCwCADEDAAAA.',
Ab='Absinth:BAAALgAFFAIJAgABLgAFFAQJDQACAIYLAA==.Absolutezero:BAACLgAFFH8LAAIDAAQJdBqSQQBJAQADAAQJdBqSQQBJAQAuAAQKfzYAAwMACAnRIC8qAFsCAAMACAmmIC8qAFsCAAQABAmFHbAJANMAAAAA.',
Ad='Advïl:BAAALgAECgQJBAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Aletstrasza:BAACLgAFFH8SAAIFAAQJ4xCeFwD8AAAFAAQJ4xCeFwD8AAAuAAQKf0UAAwUACQlHH3YDAAADAAUACQlHH3YDAAADAAYAAQluBcyIACoAAAAA.Alexjuander:BAABLgAECn8bAAQHAAgJlRI6HACxAAAIAAgJbwgdfgAyAQAJAAUJ6hT0FgDnAAAHAAQJqg06HACxAAAAAA==.Alexsander:BAABLgAECn8YAAMGAAYJJxHpQAAFAQAGAAYJJxHpQAAFAQAKAAIJNgbnHgBHAAAAAA==.Allysah:BAAALgAECgEJAgABLgAFFAQJGAALAJEHAA==.Alphard:BAABLgAECn8/AAMMAAkJsSOyAQBDAwAMAAkJsSOyAQBDAwANAAEJvBvVHgA5AAAAAA==.',
An='Anelowyn:BAABLgAECn8xAAIOAAkJtRkyDQBlAgAOAAkJtRkyDQBlAgAAAA==.',
Ap='Apocal:BAACLgAFFH8RAAIPAAYJcxZMAgBlAQAPAAYJcxZMAgBlAQAuAAQKfxUAAg8ACAmnG3gGACsCAA8ACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Aralgi:BAAALgAECgEJAQAAAA==.Arete:BAABLgAECn8WAAIQAAYJ3xIpRQAZAQAQAAYJ3xIpRQAZAQAAAA==.Arlandil:BAAALgADCgMJAwAAAA==.Artaimya:BAAALgAECgYJCwAAAA==.Artemìs:BAAALgAECgQJBgAAAA==.',
At='Atmosphere:BAAALgAECgUJBwAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgYJCAARAAAAAA==.Aurelian:BAAALgADCgcJBwAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAFFAQJBgADAJ0EAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgcJDQAAAA==.Babs:BAAALgAECgUJBgAAAA==.Baraden:BAAALgAECgUJDAAAAA==.Basutai:BAABLgAECn8iAAISAAkJ5CP8AQCFAwASAAkJ5CP8AQCFAwAAAA==.',
Be='Beanohuntz:BAAALgADCgIJAgAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgYJDwAAAA==.Birgetta:BAACLgAFFH8IAAITAAQJ7gRlRgD4AAATAAQJ7gRlRgD4AAAuAAQKfzMAAxMACQmsEbkyAPsBABMACQmsEbkyAPsBABQABgltA/AhAIsAAAAA.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIFAAgJNhlHDABxAgAFAAgJNhlHDABxAgABLgAECgkJGQAVANkWAA==.Blasphemous:BAAALgAECgEJAwAAAA==.Blee:BAABLgAECn8wAAIVAAkJihs5EQDeAQAVAAkJihs5EQDeAQAAAA==.Bleefleenix:BAAALgAECgYJBgAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAARAAAAAA==.Bluffalo:BAAALgADCgEJAQABLgAFFAQJDgAWAGsNAA==.Blâster:BAAALgAECgEJAQAAAA==.',
Bo='Bobodaklown:BAABLgAECn8jAAMLAAkJ9BabOgA5AgALAAkJYhabOgA5AgACAAIJmxWNNQBvAAAAAA==.Boomnblood:BAAALgADCgEJAQABLgAFFAQJDwAXABIGAA==.Boomnbrew:BAACLgAFFH8PAAIXAAQJEgY2LADkAAAXAAQJEgY2LADkAAAuAAQKfzUAAhcACQkpFPYVAOoBABcACQkpFPYVAOoBAAAA.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8ZAAMUAAkJQAzpGQDMAAATAAUJAQ/ehAAcAQAUAAcJBwrpGQDMAAAAAA==.',
Br='Brewman:BAACLgAFFH8OAAIYAAQJohj/GwA9AQAYAAQJohj/GwA9AQAuAAQKfzEAAxgACQmQITgEAFcDABgACQmQITgEAFcDABcACAnhDVgwAC8BAAAA.',
Bu='Bubonic:BAABLgAECn8sAAIZAAkJHxbKNAAYAgAZAAkJHxbKNAAYAgAAAA==.Buenasalud:BAABLgAECn8lAAIaAAkJjBt1DACHAgAaAAkJjBt1DACHAgAAAA==.',
Ca='Caball:BAAALgAECgEJAgAAAA==.Carcharias:BAAALgAECgYJBwAAAA==.Caylea:BAACLgAFFH8eAAIQAAYJrxkmCQCdAQAQAAYJrxkmCQCdAQAuAAQKfywAAhAACAkrHQYZAIMCABAACAkrHQYZAIMCAAAA.',
Ch='Chalis:BAABLgAECn8iAAMHAAcJYB/BCgATAgAIAAYJrB6UKQAmAgAHAAYJ5h3BCgATAgAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAACLgAFFH8LAAMbAAQJZBdfNwDnAAAbAAMJwxZfNwDnAAAcAAIJrgKvQABgAAAuAAQKfx8AAxsACAmKFdMpAPoBABsACAmKFdMpAPoBABwAAglfBAmMAD0AAAAA.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAACLgAFFH8JAAIDAAMJHQ1lcwDbAAADAAMJHQ1lcwDbAAAuAAQKfzAAAwMACQksFCdMAN8BAAMACQksFCdMAN8BAB0AAQm6A2ARACsAAAAA.Corleon:BAAALgADCgMJAwAAAA==.Corvus:BAAALgAECgUJDQAAAA==.',
Cr='Crizlock:BAAALgAECgEJAQABLgAECgcJFwATAEYjAA==.Crowdcontrol:BAABLgAECn8aAAICAAkJFiAYBQCNAgACAAkJFiAYBQCNAgAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAACLgAFFH8JAAIeAAMJsRRHFwDJAAAeAAMJsRRHFwDJAAAuAAQKfzMAAx8ACQkOFzIMAN4BAB8ACQlZDjIMAN4BAB4ABAmNG8YdACwBAAAA.',
Cu='Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgAAAA==.Cursis:BAAALgAECgIJAgAAAA==.Cushions:BAAALgAECgQJBAAAAA==.',
Da='Daddysixinch:BAAALgAFFAMJBAAAAA==.Daelin:BAABLgAECn8zAAMLAAkJ6CMJBQA+AwALAAkJ6CMJBQA+AwASAAEJJw3DhwAsAAAAAA==.Danye:BAAALgAECgEJAQAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darkcleric:BAAALgADCgYJBgAAAA==.Darknous:BAAALgAECgEJAQAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deante:BAABLgAECn8YAAIgAAYJfgquOQACAQAgAAYJfgquOQACAQAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathman:BAABLgAECn8ZAAIVAAkJ2RaIDQAXAgAVAAkJ2RaIDQAXAgAAAA==.Deathrite:BAAALgAFFAEJAQAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCgAAAA==.Demo:BAAALgAFFAMJAwABLgAFFAQJCgAZAFMiAA==.Demonmommy:BAAALgADCgEJAQAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAACLgAFFH8KAAIcAAQJ9QURJwDeAAAcAAQJ9QURJwDeAAAuAAQKfygAAhwACQkTFDYbAO8BABwACQkTFDYbAO8BAAAA.',
Dh='Dhchin:BAAALgAECgQJBgABLgAFFAYJGgAMAO0kAA==.Dhomsak:BAABLgAFFH8KAAIhAAUJaB4aJgBkAQAhAAUJaB4aJgBkAQABLgAFFAUJEwADAD4jAA==.',
Di='Diamonds:BAAALgADCgEJAQAAAA==.Die:BAAALgAECgcJCgAAAA==.Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgYJCAAAAA==.Distrath:BAAALgADCgkJCQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQABLgAFFAYJGgAMAO0kAA==.',
Do='Doadin:BAABLgAECn8sAAMSAAkJoBvCDQCqAgASAAkJoBvCDQCqAgALAAEJ1gHBXQEgAAAAAA==.Doominatrix:BAACLgAFFH8NAAMIAAQJsgrHUgANAQAIAAQJagrHUgANAQAJAAEJNAdUIQBGAAAuAAQKfzIAAwgACAm+GDY3APABAAgABwm+GDY3APABAAkAAQkAAKQqAEoAAAAA.',
Dr='Draggum:BAABLgAECn8eAAMGAAgJ+xmtGQDvAQAGAAgJ+xmtGQDvAQAFAAMJpxDnJgCeAAABLgAECgcJIAADAPEaAA==.Dreadraven:BAABLgAECn9IAAMQAAgJYhWXJgAmAgAQAAgJYhWXJgAmAgAfAAEJZQSKdQAiAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8pAAMBAAkJRxRuIQCxAQABAAgJvxRuIQCxAQAhAAgJuBAsXgBVAQABLgAECgEJAQARAAAAAA==.Dreddstorm:BAAALgAECgEJAgAAAA==.Drewuw:BAABLgAECn8bAAIiAAkJwBaOGQAVAgAiAAkJwBaOGQAVAgABLgAECgkJHQAhAJ0bAA==.Druidhams:BAACLgAFFH8PAAIjAAQJYRQ1JwAOAQAjAAQJYRQ1JwAOAQAuAAQKfzUAAiMACQn+HhcMAO4CACMACQn+HhcMAO4CAAAA.',
Ea='Eamon:BAAALgAFFAEJAQABLgAFFAMJCAAgAKMSAA==.',
Ei='Eightball:BAAALgADCgUJBQAAAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgUJBgAAAA==.Elisha:BAACLgAFFH8YAAILAAQJkQeWSAABAQALAAQJkQeWSAABAQAuAAQKf2gAAgsACQlQG2MiAGUCAAsACQlQG2MiAGUCAAAA.Elsyra:BAAALgAECgYJDQAAAA==.',
Er='Erebostro:BAABLgAECn8/AAITAAkJYxrzGgBvAgATAAkJYxrzGgBvAgAAAA==.',
Ev='Everclear:BAAALgAECggJDAABLgAFFAQJDQACAIYLAA==.Evillux:BAACLgAFFH8FAAMIAAIJbQWTnwBxAAAIAAIJbQWTnwBxAAAHAAEJZAD8JgAkAAAuAAQKfy8AAwgACQm2EMpCAMcBAAgACQlHEMpCAMcBAAcABQnmDH0qABcBAAAA.',
Ey='Eyeguy:BAABLgAECn8VAAMhAAkJHxyYJwBmAgAhAAkJLBmYJwBmAgABAAQJ+h+0NgAsAQAAAA==.',
Fa='Fathercow:BAACLgAFFH8PAAIgAAQJ0SFzFgB/AQAgAAQJ0SFzFgB/AQAuAAQKfywAAiAACQn3H14FABoDACAACQn3H14FABoDAAAA.',
Fi='Fingies:BAACLgAFFH8RAAQIAAQJaBsyQQAxAQAIAAQJrRYyQQAxAQAJAAEJoh4FFABaAAAHAAEJ1RLdHQBRAAAuAAQKfz4AAwgACQm9JP4MANgCAAgABwlHJf4MANgCAAcABQmyHkoVAJ8BAAAA.Fistin:BAAALgAECgYJBwAAAA==.',
Fr='Frieren:BAAALgADCgYJBgAAAA==.',
Fu='Fungies:BAAALgAECgUJBQABLgAFFAQJEQAIAGgbAA==.Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAACLgAFFH8NAAITAAQJoxZ1KgBBAQATAAQJoxZ1KgBBAQAuAAQKfzQAAxMACQkhI8cHAAwDABMACQkhI8cHAAwDACQABQmiDfY4ANsAAAAA.',
Ga='Gaijin:BAAALgADCgMJAwABLgAFFAMJCAAgAKMSAA==.Galaxsea:BAABLgAECn8YAAIiAAkJ1x1SDABrAgAiAAkJ1x1SDABrAgAAAA==.Gargapew:BAAALgAECgIJAgABLgAFFAMJBgADAMQJAA==.',
Ge='Gerthquake:BAABLgAECn8rAAMcAAkJzRkQEgBIAgAcAAkJzRkQEgBIAgAbAAkJOB71LwDbAQAAAA==.',
Gf='Gfour:BAABLgAECn8fAAIYAAgJjhx2EwAvAgAYAAgJjhx2EwAvAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.Ghraxx:BAAALgADCgkJCQAAAA==.Ghraxxy:BAAALgAECgkJEQAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Gobø:BAABLgAECn8UAAITAAYJ5gbRmADzAAATAAYJ5gbRmADzAAAAAA==.Goodytwoshoe:BAAALgAECgIJBwAAAA==.',
Gr='Grimmreefer:BAAALgAECgUJBQAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgQJCgAAAA==.',
['Gâ']='Gâlvatron:BAAALgADCgEJAQAAAA==.',
Ha='Hakz:BAAALgADCgkJCQAAAA==.',
He='Heart:BAABLgAFFH8HAAMgAAMJtQeOLAC3AAAgAAMJtQeOLAC3AAAOAAEJgALCNQA5AAABLgAFFAQJCgAZAFMiAA==.Help:BAAALgADCgEJAQAAAA==.',
Ho='Homlock:BAABLgAFFH8FAAIIAAUJExxeLgBiAQAIAAUJExxeLgBiAQABLgAFFAUJEwADAD4jAA==.Homsorc:BAACLgAFFH8TAAMDAAUJPiPiBwDlAQADAAUJPiPiBwDlAQAEAAEJBySGAwBdAAAuAAQKfyMAAgMACQlLJTMFAK8DAAMACQlLJTMFAK8DAAAA.Homtard:BAABLgAFFH8RAAMUAAgJ4yD2AgA1AgAUAAgJ5R/2AgA1AgAkAAQJFh+uCQBpAQABLgAFFAUJEwADAD4jAA==.Hope:BAABLgAECn86AAMSAAkJ9xzECADqAgASAAkJ9xzECADqAgALAAQJ5wfx+wCcAAAAAA==.',
['Hô']='Hôûnd:BAAALgAECgEJAQAAAA==.',
Id='Idun:BAAALgAECgYJCgAAAA==.',
Il='Illiandray:BAABLgAECn8yAAMHAAkJyh0mAgCPAgAHAAkJyh0mAgCPAgAIAAgJUgpuhAAmAQAAAA==.Ilswyn:BAAALgADCgUJBQABLgAECgkJOQAhAGElAA==.',
Im='Imu:BAACLgAFFH8KAAMkAAMJoCF/FgAFAQAkAAMJoCF/FgAFAQATAAEJxhlgggBNAAAuAAQKfyIABCQABwkOJYULAF0CACQABwkOJYULAF0CABQABQk/DfFUAPYAABMAAgmLCs6nAHYAAAEuAAUUBgkaAAsANCYA.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn85AAIhAAkJYSX/AQBgAwAhAAkJYSX/AQBgAwAAAA==.',
Io='Ionise:BAABLgAECn8kAAIGAAkJKRu9DQBsAgAGAAkJKRu9DQBsAgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Iskgard:BAAALgAECgcJBwAAAA==.Isklar:BAACLgAFFH8JAAIVAAIJJBwjJQCYAAAVAAIJJBwjJQCYAAAuAAQKfy8AAhUACAm4I4UEAAIDABUACAm4I4UEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAABLgAECn8pAAQGAAgJ0RtSFwAEAgAGAAgJ0RtSFwAEAgAKAAQJMxZKDwAFAQAFAAMJbwy0OQCdAAAAAA==.',
Je='Jer:BAABLgAECn8cAAIMAAkJ1RAyFABzAgAMAAkJ1RAyFABzAgAAAA==.',
Ju='Jugernat:BAAALgADCgEJAQAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAFFAMJCAAgAKMSAA==.',
Ka='Kaalo:BAAALgADCgUJBQAAAA==.Kairi:BAAALgAECgYJCAAAAA==.Kammo:BAACLgAFFH8UAAIZAAQJxiDqJwCOAQAZAAQJxiDqJwCOAQAuAAQKf0QAAhkACQkxJjoCAHMDABkACQkxJjoCAHMDAAAA.Kazypher:BAAALgAECgMJCgAAAA==.',
Ke='Keeah:BAAALgAECgQJCAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAIYAAkJCgfzMQAvAQAYAAkJCgfzMQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAFFAMJCAAgAKMSAA==.Kiwi:BAAALgAECggJCAAAAA==.',
Kl='Klingnor:BAAALgADCgcJCgAAAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8RAAIUAAYJbhZ0DABlAQAUAAYJbhZ0DABlAQAuAAQKfyAAAhQABwnLIVYKALIBABQABwnLIVYKALIBAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwickin:BAAALgAECgEJAQABLgAECgcJIAADAPEaAA==.Kwikin:BAABLgAECn8gAAIDAAcJ8RqMVQA3AgADAAcJ8RqMVQA3AgAAAA==.',
Ky='Kyreen:BAABLgAECn8ZAAITAAgJFAsCZQBhAQATAAgJFAsCZQBhAQAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECgkJGAAiANcdAA==.',
La='Laaz:BAACLgAFFH8OAAIhAAQJcAf/SQDvAAAhAAQJcAf/SQDvAAAuAAQKfzYAAiEACQlXE1w0AN4BACEACQlXE1w0AN4BAAAA.Lamalen:BAABLgAECn8UAAILAAcJnxoSYQDBAQALAAcJnxoSYQDBAQAAAA==.Lasercow:BAAALgAECgcJCAABLgAFFAQJDwAgANEhAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Liena:BAAALgADCgkJCwAAAA==.Linthvia:BAAALgAECgUJCQAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgAECgEJAgAAAA==.',
Lo='Locknloaded:BAAALgAFFAEJAQAAAA==.',
Lu='Luciuos:BAABLgAECn8ZAAMlAAkJqwKSVQCeAAAlAAkJqwKSVQCeAAAjAAcJ9QHtlAB1AAAAAA==.Lucreesha:BAAALgAECgUJBQABLgAECgkJHQAhAJ0bAA==.Lukafox:BAACLgAFFH8ZAAIbAAYJ3hw2DQDPAQAbAAYJ3hw2DQDPAQAuAAQKfyAAAxsACQlZH6gHAPoCABsACQlZH6gHAPoCABwAAQmKAn6WAB0AAAAA.Lunastarvale:BAABLgAECn9EAAITAAkJBR6hEAC3AgATAAkJBR6hEAC3AgAAAA==.Luscinia:BAAALgAECgIJAgAAAA==.',
Ma='Madith:BAACLgAFFH8IAAIhAAMJ3hSuUADZAAAhAAMJ3hSuUADZAAAuAAQKfyMAAiEACAlfIHIVAIQCACEACAlfIHIVAIQCAAAA.Magicjamo:BAAALgAECgUJBQAAAA==.Maleficênt:BAAALgAECggJDgABLgAFFAQJDgAWAGsNAA==.Malefisico:BAABLgAECn8lAAMHAAkJ8hKbEwD5AAAIAAkJKBHFbQCFAQAHAAUJ3BSbEwD5AAAAAA==.Malgarok:BAABLgAECn8lAAIIAAgJWBygHgCfAgAIAAgJWBygHgCfAgABLgAECgYJEAARAAAAAA==.Mardríft:BAACLgAFFH8MAAIlAAQJBBMeHAARAQAlAAQJBBMeHAARAQAuAAQKfzoAAiUACQnYIRQIAMECACUACQnYIRQIAMECAAAA.Mazga:BAABLgAECn81AAImAAkJPhh3BwA6AgAmAAkJPhh3BwA6AgAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8uAAIkAAkJihiMDABPAgAkAAkJihiMDABPAgAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgAECgQJBAAAAA==.Metta:BAAALgAFFAMJAwAAAA==.Mezoti:BAACLgAFFH8IAAMGAAMJywLZQgCVAAAGAAMJywLZQgCVAAAFAAIJwAGcJABWAAAuAAQKfxkAAwYACAniDq0vAFsBAAYACAniDq0vAFsBAAUACAm/CEIXAEgBAAAA.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCgkJEwAAAA==.',
Mo='Moji:BAACLgAFFH8HAAIYAAMJjxHjLwCsAAAYAAMJjxHjLwCsAAAuAAQKfzQAAhgACQn4HH4KANECABgACQn4HH4KANECAAAA.Monstermayi:BAACLgAFFH8NAAIQAAQJzxCYHAArAQAQAAQJzxCYHAArAQAuAAQKfy8AAhAACQnXGBwVADMCABAACQnXGBwVADMCAAAA.Mooknight:BAABLgAECn8/AAIVAAkJ8BUXEADuAQAVAAkJ8BUXEADuAQAAAA==.Moosen:BAAALgAECgcJBwAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8nAAIiAAgJXBoVGQDSAQAiAAgJXBoVGQDSAQAAAA==.',
Mu='Muggy:BAABLgAECn82AAINAAkJpRYrBABGAgANAAkJpRYrBABGAgAAAA==.',
My='Myluutarania:BAAALgAECgcJCwAAAA==.Myrothar:BAABLgAECn8UAAMSAAgJMhWrNgBdAQASAAcJKxarNgBdAQALAAYJDQP5AgGTAAAAAA==.Mytastical:BAACLgAFFH8GAAIDAAQJnQTBZQD8AAADAAQJnQTBZQD8AAAuAAQKfycAAgMACAlrFmd+ANQBAAMACAlrFmd+ANQBAAAA.',
['Mæ']='Mæve:BAACLgAFFH8HAAIjAAMJEguIPACuAAAjAAMJEguIPACuAAAuAAQKfzMAAyMACQnOGHsaAF4CACMACQnOGHsaAF4CACUABQmNESxGABUBAAAA.',
['Më']='Mëgatron:BAAALgAECgEJAQAAAA==.',
Na='Namalis:BAACLgAFFH8OAAMIAAQJSRvoOwA8AQAIAAQJMBroOwA8AQAJAAEJ9h7CFABZAAAuAAQKfx0ABAgACAkTJQU5ACcCAAgABgkPJQU5ACcCAAcAAgkWIqA8AMIAAAkAAQkAADIhAG0AAAAA.Nanielito:BAACLgAFFH8GAAIDAAMJxAmqeADQAAADAAMJxAmqeADQAAAuAAQKfyUAAgMACQnGH+sXALQCAAMACQnGH+sXALQCAAAA.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8PAAIDAAUJuROYTwAyAQADAAUJuROYTwAyAQAuAAQKfygAAgMACQmCHKMgAIcCAAMACQmCHKMgAIcCAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
No='Nokoa:BAAALgAECggJCAAAAA==.Nonae:BAABLgAECn8gAAITAAgJjh0bEgCnAgATAAgJjh0bEgCnAgAAAA==.Norivari:BAAALgAECgIJAgAAAA==.Nosali:BAAALgADCgkJCQABLgAFFAQJDgAaACIaAA==.Nosliw:BAAALgADCgUJCAAAAA==.Notawarlock:BAAALgADCgMJAwAAAA==.Noxilis:BAAALgAECgEJAQAAAA==.',
Ob='Obiwon:BAAALgAECgYJEQAAAA==.',
Og='Ogsmashsauce:BAAALgAECgEJAQAAAA==.',
Ol='Oldschooler:BAAALgADCgkJCQAAAA==.',
Om='Omegá:BAACLgAFFH8NAAICAAQJhgvWCADSAAACAAQJhgvWCADSAAAuAAQKfyIAAgIACQkuFcgPAK0BAAIACQkuFcgPAK0BAAAA.',
Oo='Oopsalldruid:BAAALgAECgUJCAABLgAECgcJIAADAPEaAA==.',
Op='Optìmusprìme:BAABLgAECn8/AAIeAAkJJh/zBAC9AgAeAAkJJh/zBAC9AgAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Papa:BAACLgAFFH8FAAMJAAIJcB+tGQBTAAAIAAEJRyAppABYAAAJAAEJmh6tGQBTAAAuAAQKfzIABAcACQmBIcUCANYCAAcABwlRIcUCANYCAAkACAkrIywCAJ4CAAgABQmhHEhZAIYBAAAA.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAFFAEJAQAAAA==.',
Po='Pockets:BAABLgAECn8rAAIDAAgJzBb6XQCsAQADAAgJzBb6XQCsAQAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAABLgAECn8YAAIIAAcJbAJFzACpAAAIAAcJbAJFzACpAAAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAACLgAFFH8IAAMgAAMJoxJ9JwDWAAAgAAMJoxJ9JwDWAAAOAAMJVwhgIQDDAAAuAAQKfzcAAyAACQnjHqkJALsCACAACQnjHqkJALsCAA4AAgmcEnJyADgAAAAA.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAECgYJEAAAAA==.',
['Pø']='Pø:BAAALgAECgEJAQAAAA==.',
Qu='Quick:BAAALgAECgEJAgABLgAECgcJIAADAPEaAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Rangedrhett:BAAALgADCgEJAQAAAA==.Ratha:BAACLgAFFH8OAAICAAQJYhBzBwDrAAACAAQJYhBzBwDrAAAuAAQKfzEAAwIACQmqGfgPAKoBAAIACQmqGfgPAKoBAAsABAkVDEkEAZIAAAAA.Ravener:BAAALgAECgYJBwAAAA==.Razeal:BAABLgAECn8fAAMLAAYJliBUUgC6AQALAAYJPyBUUgC6AQACAAIJKxjiMQCGAAAAAA==.',
Re='Reaper:BAACLgAFFH8KAAIZAAQJUyIOLgB9AQAZAAQJUyIOLgB9AQAuAAQKfx0AAxkABwkPJW4nAFECABkABwkPJW4nAFECABUAAgk+B+BAAEkAAAAA.Reeah:BAAALgADCgkJCQAAAA==.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAABLgAECn8cAAIlAAcJnAsoPQD+AAAlAAcJnAsoPQD+AAAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8aAAMMAAYJ7SRKCwCbAQAMAAUJGyVKCwCbAQANAAIJgRngCgBrAAAuAAQKfysAAwwACQlIJWwHAJ0CAAwACAnGJWwHAJ0CAA0AAwnpI/4NADoBAAAA.Rokkgar:BAABLgAECn8nAAIcAAgJ2BAuKwCBAQAcAAgJ2BAuKwCBAQABLgAECggJLgANALEMAA==.Roosterr:BAAALgADCgkJFgAAAA==.',
Ru='Ruwazi:BAAALgAECgYJDwAAAA==.',
Rx='Rxdh:BAAALgAECgIJAgAAAA==.',
Ry='Ryujin:BAAALgAECgUJBwAAAA==.',
Sa='Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Secarious:BAABLgAECn8bAAIQAAgJnhCDLwB8AQAQAAgJnhCDLwB8AQAAAA==.Sediaria:BAAALgAECgkJCQABLgAFFAQJCAATAO4EAA==.Sehnsucht:BAACLgAFFH8MAAMlAAQJJBIXHgAFAQAlAAQJJBIXHgAFAQAjAAMJfg4QOgC2AAAuAAQKfygAAyMACQktHAkeAE4CACMACQktHAkeAE4CACUAAQkAGqB2AEkAAAAA.Serius:BAAALgAECgQJBAABLgAECgkJHQAhAJ0bAA==.',
Sh='Shmadu:BAAALgAECgcJCwAAAA==.Shockk:BAABLgAECn8gAAMcAAkJGRY4JQCmAQAcAAkJGRY4JQCmAQAbAAMJ4AKOigBpAAAAAA==.Shone:BAAALgAECgUJBQAAAA==.',
Si='Siovhan:BAAALgAECgkJEgAAAA==.',
Sl='Sly:BAACLgAFFH8KAAInAAMJKRvvBgDzAAAnAAMJKRvvBgDzAAAuAAQKfxQAAicABwkuID4EAC4CACcABwkuID4EAC4CAAEuAAUUBAkKABkAUyIA.',
Sm='Smóóthbói:BAABLgAECn8tAAIDAAkJrhWuPQANAgADAAkJrhWuPQANAgAAAA==.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn83AAIGAAkJ8BcOEQBDAgAGAAkJ8BcOEQBDAgAAAA==.Soola:BAABLgAECn8fAAMbAAgJoQ0/RwB1AQAbAAgJoQ0/RwB1AQAcAAQJzAzSbwB6AAAAAA==.',
Sp='Spoof:BAAALgAECgIJAgAAAA==.Spoopadin:BAAALgAECgIJBgAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.Sprigg:BAAALgADCgkJCQABLgAECgkJLQADAK4VAA==.',
St='Stack:BAACLgAFFH8IAAIkAAIJ8hsbHwC3AAAkAAIJ8hsbHwC3AAAuAAQKfxQAAiQABwkmHH4XANcBACQABwkmHH4XANcBAAEuAAUUBAkKABkAUyIA.Stompycouch:BAACLgAFFH8FAAIcAAIJJREyOACCAAAcAAIJJREyOACCAAAuAAQKfysAAhwACAnyHDsXAF4CABwACAnyHDsXAF4CAAAA.Stoned:BAABLgAECn8nAAMSAAkJJh/uCADhAgASAAkJJh/uCADhAgALAAMJ3wqlEAGCAAAAAA==.Stonedpriest:BAABLgAECn84AAIaAAkJliA7BwDYAgAaAAkJliA7BwDYAgAAAA==.Stripes:BAAALgADCgUJBQAAAA==.',
Su='Sunreaver:BAABLgAECn8tAAIZAAkJcyOQEQDPAgAZAAkJcyOQEQDPAgAAAA==.Surrëal:BAAALgAECgkJEwABLgAFFAQJCAATAO4EAA==.Surtain:BAACLgAFFH8FAAIlAAMJxwhqLQCkAAAlAAMJxwhqLQCkAAAuAAQKfx8AAiUACAk4HocSAC0CACUACAk4HocSAC0CAAAA.Suxiv:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetmask:BAABLgAECn8lAAMZAAgJnSPFGACeAgAZAAgJnSPFGACeAgAoAAIJ2BrtHgCiAAAAAA==.',
Sx='Sxv:BAAALgAFFAIJAwAAAA==.',
Sy='Syl:BAACLgAFFH8NAAITAAQJ4xVBKgBCAQATAAQJ4xVBKgBCAQAuAAQKfy0AAxMACQlyG0odAGACABMACQlyG0odAGACABQABQlVCnFZAN8AAAAA.Sylvanäs:BAAALgAECgkJEgABLgAECgkJMgAHAModAA==.',
['Sï']='Sïdëswïpë:BAAALgAECgEJAgAAAA==.',
['Só']='Sóúndwâve:BAAALgAECgEJAQAAAA==.',
Ta='Tahitian:BAABLgAECn8fAAITAAkJ9w4vPgDQAQATAAkJ9w4vPgDQAQAAAA==.Tahlreth:BAABLgAECn88AAMDAAkJ4R8gEwDTAgADAAkJ4R8gEwDTAgAdAAEJuhmPDgBMAAAAAA==.Tandlia:BAAALgAECgQJBAAAAA==.Tanickz:BAABLgAECn8tAAIDAAkJ2BJfQQABAgADAAkJ2BJfQQABAgAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJLAAcAPscAA==.Tanidgetotem:BAABLgAECn8sAAIcAAkJ+xz8CQD0AgAcAAkJ+xz8CQD0AgAAAA==.Tanya:BAACLgAFFH8SAAIkAAQJ7Bb3DQBKAQAkAAQJ7Bb3DQBKAQAuAAQKf0AAAiQACQmKI6wCAA0DACQACQmKI6wCAA0DAAAA.Tayanna:BAABLgAECn8YAAMLAAkJFRybfgBWAQALAAgJix6bfgBWAQACAAcJAQj4JgDDAAAAAA==.',
Te='Teias:BAACLgAFFH8OAAIaAAQJIhrEDgA8AQAaAAQJIhrEDgA8AQAuAAQKfzIAAxoACQn5GhQTAEcCABoACQn5GhQTAEcCAA4ABgkCHZsjAIwBAAAA.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thuras:BAAALgADCgUJBQABLgAECgMJAwARAAAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8iAAIDAAgJox9MNwAkAgADAAgJox9MNwAkAgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgADCgUJCAARAAAAAA==.',
Tr='Tricko:BAABLgAECn86AAITAAgJJSDwIgBBAgATAAgJJSDwIgBBAgAAAA==.Trollskingx:BAABLgAECn8cAAIDAAcJwBacdADpAQADAAcJwBacdADpAQAAAA==.Trollzy:BAABLgAECn8/AAMmAAkJLyENAgD3AgAmAAkJLyENAgD3AgAbAAQJjQlnkwCGAAAAAA==.Trunkmonkey:BAACLgAFFH8JAAIIAAQJIg02TwAVAQAIAAQJIg02TwAVAQAuAAQKfy8AAggACQlbGnwaAHgCAAgACQlbGnwaAHgCAAAA.Tryne:BAAALgADCgEJAQAAAA==.',
Ts='Tsaagan:BAACLgAFFH8PAAMIAAQJvha8PQA4AQAIAAQJNha8PQA4AQAJAAEJ5RJAGgBSAAAuAAQKfy0ABAgACQkXIdAPAMACAAgACQkqH9APAMACAAkABAkII/4KAIwBAAcABAkHHrQgAE4BAAAA.',
Tu='Tucker:BAABLgAECn8rAAIYAAkJgh02CAD6AgAYAAkJgh02CAD6AgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ud='Uddershaman:BAAALgADCgcJCQAAAA==.',
Ul='Ultramagnús:BAAALgAECgEJAgAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAABLgAECn8bAAMZAAcJVBLgcABuAQAZAAcJVBLgcABuAQAoAAEJlwowMAA0AAAAAA==.Under:BAAALgADCgcJDgABLgAECgcJGwAZAFQSAA==.Unparalleled:BAABLgAECn8jAAMFAAcJRwf3HAABAQAFAAcJRwf3HAABAQAKAAUJZAozEQDkAAAAAA==.',
Va='Vaaleros:BAAALgADCgYJBgAAAA==.Valiithria:BAAALgAECgQJBAAAAA==.Valkyruid:BAACLgAFFH8SAAIjAAYJLxDUFgCGAQAjAAYJLxDUFgCGAQAuAAQKfxcAAiMABwnCF4w2AM0BACMABwnCF4w2AM0BAAAA.',
Ve='Vessel:BAAALgAFFAIJAgABLgAFFAQJCgAZAFMiAA==.',
Vi='Vixus:BAAALgAFFAEJAgAAAA==.',
Vx='Vxs:BAAALgAFFAIJAwAAAA==.',
['Vø']='Vøødu:BAAALgAECgYJCwABLgAECgcJGAAbAJEQAA==.',
Wa='Walshidan:BAABLgAECn8aAAIhAAkJ0xAQSgCQAQAhAAkJ0xAQSgCQAQAAAA==.Walshlel:BAAALgADCgkJCQAAAA==.Waywatcher:BAAALgAFFAEJAQAAAA==.',
We='Wenus:BAAALgAECgUJBQAAAA==.',
Wi='Wiccaflame:BAABLgAECn8bAAIDAAkJdSDCFADIAgADAAkJdSDCFADIAgAAAA==.Wiccasham:BAAALgAECgEJAQAAAA==.',
Wu='Wullgan:BAABLgAECn8fAAMgAAkJ2R75EABEAgAgAAgJvx75EABEAgAOAAcJGBg7KABtAQAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAABLgAFFH8IAAIFAAQJvhEtFgASAQAFAAQJvhEtFgASAQAAAA==.',
Xo='Xole:BAABLgAECn8fAAMhAAgJnxSJUAB9AQAhAAgJnxSJUAB9AQAPAAQJIQSEIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8dAAIhAAkJnRuTMAA5AgAhAAkJnRuTMAA5AgAAAA==.Xyrna:BAAALgAECgkJDgABLgAFFAQJDgACAGIQAA==.',
Ya='Yareli:BAABLgAECn8pAAIPAAkJngdsDwA7AQAPAAkJngdsDwA7AQAAAA==.Yawa:BAAALgAFFAEJBAAAAA==.',
Ye='Yeahreally:BAAALgADCgkJCQAAAA==.Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQARAAAAAA==.Zankrah:BAAALgAECgQJBAABLgAFFAQJDgAaACIaAA==.Zarill:BAAALgADCgcJBwAAAA==.Zartman:BAAALgAECgMJBQAAAA==.Zayzoo:BAAALgAECgUJDQAAAA==.Zazie:BAABLgAECn8VAAIDAAcJ9QYGvADyAAADAAcJ9QYGvADyAAAAAA==.',
Ze='Zekröm:BAACLgAFFH8OAAIWAAQJaw2pDwDdAAAWAAQJaw2pDwDdAAAuAAQKfx8AAhYACQkyEg8SAKsBABYACQkyEg8SAKsBAAAA.Zekrøm:BAABLgAECn8dAAIcAAgJjxrvGQBEAgAcAAgJjxrvGQBEAgABLgAFFAQJDgAWAGsNAA==.Zeno:BAACLgAFFH8fAAILAAgJ7x67AgCMAgALAAgJ7x67AgCMAgAuAAQKfxcAAgsACQkyJfgCAKcDAAsACQkyJfgCAKcDAAAA.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgADCgkJCQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQARAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQARAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAABLgAECn8uAAINAAgJsQzlCgByAQANAAgJsQzlCgByAQAAAA==.',
Zi='Zinbar:BAAALgAECgcJEQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAABLgAECn8ZAAQiAAkJahkLEQAnAgAiAAkJPRkLEQAnAgAXAAQJ9BVWVADzAAAYAAEJTQJtcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQARAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAIDAAgJXCBkLwC1AgADAAgJXCBkLwC1AgAAAA==.Çloudsham:BAAALgAECgEJAQAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8qAAQgAAgJ2yEeCQCqAgAgAAgJ2yEeCQCqAgAaAAUJABoGOwBPAQAOAAEJBhjBbQBDAAAAAA==.',
['ßa']='ßaè:BAAALgAECgMJAgABLgAECgQJBQARAAAAAA==.',
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
