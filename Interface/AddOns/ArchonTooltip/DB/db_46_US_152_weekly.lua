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
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaylasecura:BAACLgAFFH8VAAIBAAQJOx1uDABIAQABAAQJOx1uDABIAQAuAAQKfz0AAgEACQkuJEgDACQDAAEACQkuJEgDACQDAAAA.',
Ab='Absinth:BAABLgAFFH8HAAICAAMJHhhMIgDZAAACAAMJHhhMIgDZAAABLgAFFAQJDgADAHAMAA==.Absolutezero:BAACLgAFFH8SAAMEAAQJdBqvVQAxAQAEAAQJdBqvVQAxAQAFAAIJWwIoBgBgAAAuAAQKfzYAAwQACAnRIJ8vAFoCAAQACAmmIJ8vAFoCAAYABAmFHTELAM8AAAAA.',
Ad='Advïl:BAAALgAECgQJBAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Alder:BAAALgADCgEJAgAAAA==.Aletstrasza:BAACLgAFFH8UAAIHAAQJ4xB2GwDgAAAHAAQJ4xB2GwDgAAAuAAQKf0UAAwcACQlHH+IDAP4CAAcACQlHH+IDAP4CAAgAAQluBVScACUAAAAA.Alexjuander:BAABLgAECn8fAAQJAAgJlRL7FQAaAQAKAAgJbwjiigAkAQAJAAYJAhP7FQAaAQALAAQJqg2iHwCvAAAAAA==.Alexsander:BAABLgAECn8YAAMIAAYJJxGeSAAIAQAIAAYJJxGeSAAIAQAMAAIJNgZ/IgBDAAAAAA==.Allysah:BAAALgAECgEJAgABLgAFFAQJIwANANgHAA==.Alphard:BAABLgAECn8/AAMOAAkJsSNEAgA5AwAOAAkJsSNEAgA5AwAPAAEJvBvVHgA5AAAAAA==.Alphatrion:BAAALgADCgQJBAAAAA==.',
Am='Amarri:BAAALgAECgUJBwAAAA==.',
An='Anelowyn:BAABLgAECn8xAAIQAAkJtRm5DwBgAgAQAAkJtRm5DwBgAgAAAA==.',
Ap='Apocal:BAACLgAFFH8TAAIRAAgJZRQVAgCdAQARAAgJZRQVAgCdAQAuAAQKfxUAAhEACAmnG3gGACsCABEACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Aralgi:BAAALgAECgEJAQAAAA==.Arete:BAABLgAECn8WAAISAAYJ3xLZTAATAQASAAYJ3xLZTAATAQAAAA==.Arlandil:BAAALgADCgcJCAAAAA==.Artaimya:BAABLgAECn8VAAIGAAYJoyJ6AwDpAQAGAAYJoyJ6AwDpAQAAAA==.Artemìs:BAAALgAECgQJBgAAAA==.',
At='Ataraxya:BAAALgADCgYJBgAAAA==.Atmosphere:BAAALgAECgUJBwAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgYJCAATAAAAAA==.Aurelian:BAAALgADCgcJBwAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAFFAQJBgAEAJ0EAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgcJDwAAAA==.Babs:BAAALgAECgUJBgAAAA==.Backspin:BAAALgAECgQJBAABLgAECgkJLgAEABMWAA==.Baraden:BAAALgAECgUJDAAAAA==.Basutai:BAABLgAECn8iAAIUAAkJ5COmAgB+AwAUAAkJ5COmAgB+AwAAAA==.',
Be='Beanohuntz:BAAALgAECgEJAQAAAA==.Beefstout:BAAALgAECgkJCAAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgcJEAAAAA==.Bih:BAABLgAECn8hAAIVAAcJChj8LgDoAQAVAAcJChj8LgDoAQAAAA==.Birgetta:BAACLgAFFH8OAAIWAAQJIgt2SwAVAQAWAAQJIgt2SwAVAQAuAAQKfzMAAxYACQmsEd08AO0BABYACQmsEd08AO0BABcABgltA/klAIYAAAAA.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIHAAgJNhlHDABxAgAHAAgJNhlHDABxAgABLgAECgkJGQACANkWAA==.Blasphemous:BAAALgAECgEJAwAAAA==.Blee:BAABLgAECn8zAAICAAkJGBwgEAAKAgACAAkJGBwgEAAKAgAAAA==.Bleefleenix:BAAALgAECgYJBgAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAATAAAAAA==.Bluffalo:BAAALgADCgEJAQABLgAFFAUJFQAYAHAOAA==.Blâster:BAAALgAECgEJAQAAAA==.',
Bo='Bobodaklown:BAABLgAECn8jAAMNAAkJ9BabOgA5AgANAAkJYhabOgA5AgADAAIJmxWuOwBtAAAAAA==.Boomnblood:BAAALgADCgEJAQABLgAFFAQJFQAZADwGAA==.Boomnbrew:BAACLgAFFH8VAAIZAAQJPAaRMgDeAAAZAAQJPAaRMgDeAAAuAAQKfzUAAhkACQkpFPUXAOgBABkACQkpFPUXAOgBAAAA.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8ZAAMXAAkJQAxLHQDEAAAWAAUJAQ/hkwAYAQAXAAcJBwpLHQDEAAAAAA==.',
Br='Brewman:BAACLgAFFH8VAAIaAAUJPhpgHACPAQAaAAUJPhpgHACPAQAuAAQKfzEAAxoACQmQITQFAFcDABoACQmQITQFAFcDABkACAnhDZ80ACwBAAAA.Bringtherain:BAAALgAECgEJAQAAAA==.',
Bu='Bubonic:BAABLgAECn8sAAIbAAkJHxYrPAAQAgAbAAkJHxYrPAAQAgAAAA==.Buenasalud:BAABLgAECn8lAAIcAAkJjBvHDgB8AgAcAAkJjBvHDgB8AgAAAA==.Business:BAAALgAECgEJAQABLgAECgYJEwATAAAAAA==.',
Ca='Caball:BAAALgAECgEJAgAAAA==.Carcharias:BAAALgAECgYJBwAAAA==.Caylea:BAACLgAFFH8fAAISAAYJrxmPDgCSAQASAAYJrxmPDgCSAQAuAAQKfywAAhIACAkrHQYZAIMCABIACAkrHQYZAIMCAAAA.',
Ch='Chalis:BAABLgAECn8iAAMLAAcJYB/BCgATAgAKAAYJrB52LgAeAgALAAYJ5h3BCgATAgAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAACLgAFFH8RAAMdAAQJCh0ALgAqAQAdAAQJCh0ALgAqAQAeAAIJrgKHTwBZAAAuAAQKfyMABB0ACAmKFbQvAPYBAB0ACAmKFbQvAPYBAB4AAwkvCNCDAGgAAB8AAwmzCWIzAGMAAAAA.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAACLgAFFH8QAAIEAAQJwgt1bAAKAQAEAAQJwgt1bAAKAQAuAAQKfzAAAwQACQksFFpRAOgBAAQACQksFFpRAOgBAAUAAQm6A2ARACsAAAAA.Corleon:BAAALgADCgMJAwAAAA==.Corvus:BAAALgAECgUJDgAAAA==.',
Cr='Crizlock:BAAALgAECgEJAQABLgAECgcJFwAWAEYjAA==.Crowdcontrol:BAABLgAECn8aAAIDAAkJFiAtBgCGAgADAAkJFiAtBgCGAgAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAACLgAFFH8QAAIgAAQJQxY/FAAAAQAgAAQJQxY/FAAAAQAuAAQKfzMAAyEACQkOFzIMAN4BACEACQlZDjIMAN4BACAABAmNG6MhACMBAAAA.',
Cu='Cuahtemoc:BAAALgAECgEJAQAAAA==.Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgABLgAECgkJLgAEABMWAA==.Cursis:BAAALgAECgIJAgAAAA==.',
Da='Daddysixinch:BAABLgAFFH8MAAIbAAUJWhWGVABJAQAbAAUJWhWGVABJAQAAAA==.Daelin:BAABLgAECn8zAAMNAAkJ6CMIBwA3AwANAAkJ6CMIBwA3AwAUAAEJJw2mkgAsAAAAAA==.Danye:BAAALgAECgEJAQAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darkcleric:BAAALgADCgYJBgAAAA==.Darknous:BAAALgAECgEJAQAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deante:BAABLgAECn8ZAAIiAAYJWgxQPAAdAQAiAAYJWgxQPAAdAQAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathman:BAABLgAECn8ZAAICAAkJ2RYrEAAJAgACAAkJ2RYrEAAJAgAAAA==.Deathrite:BAAALgAFFAEJAQAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCgAAAA==.Demo:BAAALgAFFAMJAwABLgAFFAQJCgAbAFMiAA==.Demonmommy:BAAALgADCgEJAgAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAACLgAFFH8PAAIeAAQJEAsiLQDfAAAeAAQJEAsiLQDfAAAuAAQKfygAAh4ACQkTFBEfAOoBAB4ACQkTFBEfAOoBAAAA.',
Dh='Dhchin:BAAALgAFFAEJAQABLgAFFAcJHAAOAKIkAA==.Dhomsak:BAABLgAFFH8VAAIjAAYJqhyZHwC7AQAjAAYJqhyZHwC7AQABLgAFFAYJIgAEAB8kAA==.',
Di='Diamonds:BAAALgADCgEJAQABLgAECgkJLgAEABMWAA==.Die:BAABLgAFFH8FAAINAAMJkAuSfgC5AAANAAMJkAuSfgC5AAAAAA==.Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgYJCAAAAA==.Distrath:BAAALgADCgkJCQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQABLgAFFAcJHAAOAKIkAA==.',
Do='Doadin:BAABLgAECn8sAAMUAAkJoBvCDQCqAgAUAAkJoBvCDQCqAgANAAEJ1gHBXQEgAAAAAA==.Doominatrix:BAACLgAFFH8TAAMKAAQJsgrMYwD/AAAKAAQJagrMYwD/AAAJAAEJNAdDKgBDAAAuAAQKfzIAAwoACAm+GHI+AOIBAAoABwm+GHI+AOIBAAkAAQkAAKQqAEoAAAAA.',
Dr='Draggum:BAABLgAECn8eAAMIAAgJ+xlzHADyAQAIAAgJ+xlzHADyAQAHAAMJpxDZKQCdAAABLgAECgcJIAAEAPEaAA==.Dragune:BAAALgAECgEJAQABLgAECgcJIgALAGAfAA==.Dreadmagey:BAAALgAECggJCAABLgAECgkJVgASACceAA==.Dreadraven:BAABLgAECn9WAAMSAAkJJx5DCQDOAgASAAkJJx5DCQDOAgAhAAMJ6AtNYwBbAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8pAAMBAAkJRxRuIQCxAQABAAgJvxRuIQCxAQAjAAgJuBA1awBOAQABLgAECgEJAQATAAAAAA==.Dreddstorm:BAAALgAECgEJAgAAAA==.Drewuw:BAABLgAECn8bAAIkAAkJwBaOGQAVAgAkAAkJwBaOGQAVAgABLgAECgkJHQAjAJ0bAA==.Druidhams:BAACLgAFFH8UAAIVAAQJnhZBKwALAQAVAAQJnhZBKwALAQAuAAQKfzUAAhUACQn+HpUNAO0CABUACQn+HpUNAO0CAAAA.',
Ea='Eamon:BAAALgAFFAEJAQABLgAFFAMJDQAQAKUOAA==.',
Ei='Eightball:BAAALgAECgYJCAABLgAECgkJLgAEABMWAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgUJBgAAAA==.Elisha:BAACLgAFFH8jAAINAAQJ2AcyXAD4AAANAAQJ2AcyXAD4AAAuAAQKf3wAAg0ACQlRG70nAGQCAA0ACQlRG70nAGQCAAAA.Eloquence:BAAALgAECgQJBQAAAA==.Elsyra:BAAALgAECgYJDgAAAA==.',
Er='Erebostro:BAABLgAECn8/AAIWAAkJYxqSIQBfAgAWAAkJYxqSIQBfAgAAAA==.',
Ev='Everclear:BAAALgAECggJDAABLgAFFAQJDgADAHAMAA==.Evillux:BAACLgAFFH8FAAMKAAIJbQVrtQBtAAAKAAIJbQVrtQBtAAALAAEJZACqLQAhAAAuAAQKfy8AAwoACQm2ED1NALMBAAoACQlHED1NALMBAAsABQnmDH0qABcBAAAA.',
Ey='Eyeguy:BAABLgAECn8VAAMjAAkJHxyYJwBmAgAjAAkJLBmYJwBmAgABAAQJ+h+0NgAsAQAAAA==.',
Fa='Fadedvoker:BAAALgAFFAEJAQABLgAECgkJHQAQAPobAA==.Fathercow:BAACLgAFFH8VAAIiAAQJ0SG0HQBtAQAiAAQJ0SG0HQBtAQAuAAQKfywAAiIACQn3H3gGABkDACIACQn3H3gGABkDAAAA.Faultline:BAAALgAECgIJAgABLgAECgkJJAAkALcbAA==.',
Fi='Fingies:BAACLgAFFH8RAAQKAAQJaBsEUQAkAQAKAAQJrRYEUQAkAQAJAAEJoh66GwBWAAALAAEJ1RJDIwBPAAAuAAQKfz4AAwoACQm9JAcQAMwCAAoABwlHJQcQAMwCAAsABQmyHkoVAJ8BAAAA.Fistin:BAAALgAECgYJBwAAAA==.',
Fl='Flexyheals:BAAALgADCgYJBgAAAA==.',
Fr='Frieren:BAAALgADCgYJBgAAAA==.',
Fu='Fungies:BAABLgAFFH8GAAIVAAQJ1gpcOQDIAAAVAAQJ1gpcOQDIAAABLgAFFAQJEQAKAGgbAA==.Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAACLgAFFH8TAAIWAAQJQBh4NwA+AQAWAAQJQBh4NwA+AQAuAAQKfzQAAxYACQkhI88KAP8CABYACQkhI88KAP8CACUABQmiDdU9ANQAAAAA.',
Ga='Gaijin:BAAALgADCgMJAwABLgAFFAMJDQAQAKUOAA==.Galaxsea:BAABLgAECn8YAAIkAAkJ1x0xDgBkAgAkAAkJ1x0xDgBkAgAAAA==.Gargapew:BAAALgAECgIJAgABLgAFFAMJBgAEAMQJAA==.',
Ge='Gerthquake:BAABLgAECn8rAAMeAAkJzRniFABCAgAeAAkJzRniFABCAgAdAAkJOB4sNgDYAQAAAA==.',
Gf='Gfour:BAABLgAECn8fAAIaAAgJjhx2EwAvAgAaAAgJjhx2EwAvAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.Ghraxx:BAAALgADCgkJCQAAAA==.Ghraxxy:BAAALgAECgkJEQAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Gobø:BAABLgAECn8iAAIWAAcJxQcWjAAnAQAWAAcJxQcWjAAnAQAAAA==.Goodytwoshoe:BAAALgAECgIJBwAAAA==.',
Gr='Grimmreefer:BAAALgAECgUJBQAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgQJCgAAAA==.',
['Gâ']='Gâlvatron:BAAALgADCgEJAQAAAA==.',
Ha='Hacks:BAAALgADCgcJBwAAAA==.Hakz:BAAALgADCgkJCQAAAA==.',
He='Heart:BAABLgAFFH8HAAMiAAMJtQcwNwCuAAAiAAMJtQcwNwCuAAAQAAEJgAIrQQA0AAABLgAFFAQJCgAbAFMiAA==.Hefferhumper:BAAALgADCgYJBgAAAA==.Help:BAAALgADCgEJAQAAAA==.Helravn:BAAALgAECgIJAgAAAA==.',
Ho='Homlock:BAABLgAFFH8JAAMKAAUJ5hz3PwBPAQAKAAUJ5hz3PwBPAQAJAAEJYBR2HwBRAAABLgAFFAYJIgAEAB8kAA==.Homsorc:BAACLgAFFH8iAAQEAAYJHyTiBwDlAQAEAAYJHyTiBwDlAQAFAAMJhhhSAAAMAQAGAAEJByRzBQBWAAAuAAQKfyQAAgQACQmuJTMFAK8DAAQACQmuJTMFAK8DAAAA.Homtard:BAABLgAFFH8SAAQXAAgJ4yAbBgAUAgAXAAgJ5R8bBgAUAgAlAAQJFh+PDABhAQAWAAEJ/iIkmABjAAABLgAFFAYJIgAEAB8kAA==.Hope:BAACLgAFFH8IAAIUAAMJ0hkKJwDqAAAUAAMJ0hkKJwDqAAAuAAQKfzoAAxQACQn3HHIKAOQCABQACQn3HHIKAOQCAA0ABAnnBzESAaMAAAAA.',
['Hô']='Hôûnd:BAAALgAECgEJAQAAAA==.',
Id='Idun:BAAALgAECgYJCgAAAA==.',
Il='Illiandray:BAABLgAECn8yAAMLAAkJyh20AgCGAgALAAkJyh20AgCGAgAKAAgJUgpzkQAYAQAAAA==.Ilswyn:BAAALgADCgkJDwABLgAECgkJOQAjAGElAA==.',
Im='Imu:BAACLgAFFH8KAAMlAAMJoCGGHADsAAAlAAMJoCGGHADsAAAWAAEJxhmVoQBNAAAuAAQKfyIABCUABwkOJRgNAFQCACUABwkOJRgNAFQCABcABQk/DfFUAPYAABYAAgmLCs6nAHYAAAEuAAUUCAkfAA0A+yMA.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn85AAIjAAkJYSWZAgBeAwAjAAkJYSWZAgBeAwAAAA==.',
Io='Ionise:BAABLgAECn8kAAIIAAkJKRt8DwBvAgAIAAkJKRt8DwBvAgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Iskgard:BAAALgAECgcJBwAAAA==.Isklar:BAACLgAFFH8JAAICAAIJJBwALwCJAAACAAIJJBwALwCJAAAuAAQKfy8AAgIACAm4I4UEAAIDAAIACAm4I4UEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAABLgAECn8uAAQIAAkJWh2EGQAKAgAIAAgJ0RuEGQAKAgAMAAUJ0hzOCAChAQAHAAMJbwy0OQCdAAAAAA==.',
Je='Jer:BAABLgAECn8cAAIOAAkJ1RAyFABzAgAOAAkJ1RAyFABzAgAAAA==.',
Ju='Jugernat:BAAALgADCgEJAQAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAFFAMJDQAQAKUOAA==.',
Ka='Kaalo:BAAALgADCgUJBQAAAA==.Kairi:BAAALgAECgYJCAAAAA==.Kammo:BAACLgAFFH8UAAIbAAQJxiD6PQB8AQAbAAQJxiD6PQB8AQAuAAQKf0QAAhsACQkxJlMDAGoDABsACQkxJlMDAGoDAAAA.Kazypher:BAAALgAECgMJCgAAAA==.',
Ke='Keeah:BAAALgAECgQJCAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAIaAAkJCgfzMQAvAQAaAAkJCgfzMQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAFFAMJDQAQAKUOAA==.Kiwi:BAAALgAFFAEJAQAAAA==.',
Kl='Klingnor:BAAALgADCgkJDgAAAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8WAAIXAAgJnBYfBQAqAgAXAAgJnBYfBQAqAgAuAAQKfyMAAhcABwnLIbIJANkBABcABwnLIbIJANkBAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwickin:BAAALgAECgYJCwABLgAECgcJIAAEAPEaAA==.Kwikin:BAABLgAECn8gAAIEAAcJ8RqMVQA3AgAEAAcJ8RqMVQA3AgAAAA==.',
Ky='Kyreen:BAABLgAECn8cAAIWAAkJtQstdABXAQAWAAkJtQstdABXAQAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECgkJGAAkANcdAA==.',
La='Laaz:BAACLgAFFH8VAAIjAAUJYAqTVQDuAAAjAAUJYAqTVQDuAAAuAAQKfzYAAiMACQlXEzI6AN4BACMACQlXEzI6AN4BAAAA.Lamalen:BAABLgAECn8UAAINAAcJnxoSYQDBAQANAAcJnxoSYQDBAQAAAA==.Lasercow:BAAALgAECgcJCAABLgAFFAQJFQAiANEhAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Liena:BAAALgADCgkJCwAAAA==.Linthvia:BAAALgAECgYJDgAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgAECgEJAwAAAA==.',
Lo='Locknloaded:BAAALgAFFAEJAQAAAA==.',
Lu='Luciuos:BAABLgAECn8ZAAMmAAkJqwJOXwCbAAAmAAkJqwJOXwCbAAAVAAcJ9QHvngByAAAAAA==.Lucreesha:BAAALgAECgYJBgABLgAECgkJHQAjAJ0bAA==.Lukafox:BAACLgAFFH8dAAIdAAYJIh/NEADiAQAdAAYJIh/NEADiAQAuAAQKfyAAAx0ACQlZH6gHAPoCAB0ACQlZH6gHAPoCAB4AAQmKAn6WAB0AAAAA.Lunastarvale:BAABLgAECn9GAAIWAAkJBR5hFQCoAgAWAAkJBR5hFQCoAgAAAA==.Lupuis:BAAALgAECgEJAQAAAA==.',
Ly='Lyruh:BAAALgAECggJCAAAAA==.',
Ma='Macha:BAAALgAECgYJCgAAAA==.Madith:BAACLgAFFH8IAAIjAAMJ3hT8YQDKAAAjAAMJ3hT8YQDKAAAuAAQKfyUAAiMACAmMIEUYAIQCACMACAmMIEUYAIQCAAAA.Magicjamo:BAAALgAECgUJBQAAAA==.Maleficênt:BAAALgAECggJEQABLgAFFAUJFQAYAHAOAA==.Malefisico:BAABLgAECn8lAAMLAAkJ8hI/FgD2AAAKAAkJKBHFbQCFAQALAAUJ3BQ/FgD2AAAAAA==.Malgarok:BAABLgAECn8lAAIKAAgJWBygHgCfAgAKAAgJWBygHgCfAgABLgAECgYJEAATAAAAAA==.Mardríft:BAACLgAFFH8PAAImAAQJuBWNHwAgAQAmAAQJuBWNHwAgAQAuAAQKfzoAAiYACQnYIX0JALwCACYACQnYIX0JALwCAAAA.Mazga:BAABLgAECn9LAAIfAAkJmR12BACpAgAfAAkJmR12BACpAgAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8vAAIlAAkJihiQDgBCAgAlAAkJihiQDgBCAgAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgAECgQJBAAAAA==.Metta:BAABLgAFFH8PAAIjAAUJ3QbtCAC+AAAjAAUJ3QbtCAC+AAAAAA==.Mezoti:BAACLgAFFH8PAAMIAAQJzwQQQQDDAAAIAAQJzwQQQQDDAAAHAAIJwAHRKgBEAAAuAAQKfxkAAwgACAniDn8yAGsBAAgACAniDn8yAGsBAAcACAm/CHQZAD4BAAAA.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCgkJEwAAAA==.',
Mo='Moji:BAACLgAFFH8KAAIaAAMJjxFBQACjAAAaAAMJjxFBQACjAAAuAAQKfzQAAhoACQn4HGIMANICABoACQn4HGIMANICAAAA.Monstermayi:BAACLgAFFH8TAAISAAQJ7BTGHwAzAQASAAQJ7BTGHwAzAQAuAAQKfy8AAhIACQnXGNUYACcCABIACQnXGNUYACcCAAAA.Mooknight:BAABLgAECn8/AAICAAkJ8BXuEgDhAQACAAkJ8BXuEgDhAQAAAA==.Moomoo:BAAALgAECgEJAQAAAA==.Moosen:BAAALgAECgcJBwAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8nAAIkAAgJXBrPHADIAQAkAAgJXBrPHADIAQAAAA==.',
Mu='Muggy:BAABLgAECn9FAAIPAAkJRBvKAgCgAgAPAAkJRBvKAgCgAgAAAA==.',
My='Myluutarania:BAAALgAECgcJCwABLgAFFAcJDgAMANoUAA==.Myrothar:BAABLgAECn8aAAMUAAgJVhblLQCmAQAUAAcJeBflLQCmAQANAAYJDQO4HAGXAAAAAA==.Mytastical:BAACLgAFFH8GAAIEAAQJnQR/dwDrAAAEAAQJnQR/dwDrAAAuAAQKfykAAgQACQl4F1p2AI0BAAQACQl4F1p2AI0BAAAA.',
['Mæ']='Mæve:BAACLgAFFH8OAAIVAAQJ2AiVPAC9AAAVAAQJ2AiVPAC9AAAuAAQKfzMAAxUACQnOGC4dAF0CABUACQnOGC4dAF0CACYABQmNESxGABUBAAAA.',
['Më']='Mëgatron:BAAALgAECgEJAQAAAA==.',
Na='Namalis:BAACLgAFFH8TAAQKAAYJ7hh7TAAuAQAKAAQJMBp7TAAuAQAJAAIJ9h6hHABVAAALAAEJgw84IQBSAAAuAAQKfx0ABAoACAkTJQU5ACcCAAoABgkPJQU5ACcCAAsAAgkWIqA8AMIAAAkAAQkAADIhAG0AAAAA.Nanielito:BAACLgAFFH8GAAIEAAMJxAnHiwDCAAAEAAMJxAnHiwDCAAAuAAQKfyUAAgQACQnGH4QcALECAAQACQnGH4QcALECAAAA.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8PAAIEAAUJuRPLYQAeAQAEAAUJuRPLYQAeAQAuAAQKfygAAgQACQmCHA0mAIMCAAQACQmCHA0mAIMCAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
Ni='Nineball:BAAALgAECgEJAQABLgAECgkJLgAEABMWAA==.',
No='Nojak:BAAALgAECgUJBQABLgAECgkJHwAWAPcOAA==.Nokoa:BAAALgAECggJCAAAAA==.Nonae:BAABLgAECn8gAAIWAAgJjh0bEgCnAgAWAAgJjh0bEgCnAgAAAA==.Norivari:BAAALgAECgQJBgAAAA==.Nosali:BAAALgAECgYJCgABLgAFFAUJFQAcAEUaAA==.Nosliw:BAAALgADCgUJCAAAAA==.Notawarlock:BAAALgADCgMJAwAAAA==.Noxilis:BAAALgAECgEJAQAAAA==.',
Ob='Obiwon:BAAALgAECgYJEQAAAA==.',
Og='Ogsmashsauce:BAAALgAECgEJAQAAAA==.',
Ol='Oldschooler:BAAALgAECggJCAAAAA==.',
Om='Omegá:BAACLgAFFH8OAAIDAAQJcAwkCwDDAAADAAQJcAwkCwDDAAAuAAQKfyIAAgMACQkuFcARAKkBAAMACQkuFcARAKkBAAAA.',
Oo='Oopsalldruid:BAAALgAECgUJCQABLgAECgcJIAAEAPEaAA==.',
Op='Optìmusprìme:BAABLgAECn8/AAIgAAkJJh81BgCrAgAgAAkJJh81BgCrAgAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Papa:BAACLgAFFH8FAAMJAAIJcB/gIQBOAAAKAAEJRyBSvABSAAAJAAEJmh7gIQBOAAAuAAQKfzUABAsACQmjIcUCANYCAAsABwlRIcUCANYCAAkACAmEI6kCAKECAAoABQmhHIBhAHwBAAAA.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAFFAEJAQAAAA==.',
Po='Pockets:BAABLgAECn8uAAIEAAkJExYjSwD6AQAEAAkJExYjSwD6AQAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAABLgAECn8jAAIKAAgJkQPwsADjAAAKAAgJkQPwsADjAAAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAACLgAFFH8NAAMQAAMJpQ5RMgB8AAAQAAIJowhRMgB8AAAiAAMJxxRpBgB0AAAuAAQKfzcAAyIACQnjHkkLALsCACIACQnjHkkLALsCABAAAgmcEvKCADgAAAAA.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAECgYJEwAAAA==.',
['Pø']='Pø:BAAALgAFFAEJAgAAAA==.',
Qu='Quantum:BAAALgAECgEJAQAAAA==.Quick:BAAALgAECgEJAgABLgAECgcJIAAEAPEaAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Ragnarök:BAAALgADCgEJAQAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Ratchet:BAAALgAECgEJAQAAAA==.Ratha:BAACLgAFFH8VAAIDAAUJcRCyCQDaAAADAAUJcRCyCQDaAAAuAAQKfzEAAwMACQmqGRISAKUBAAMACQmqGRISAKUBAA0ABAkVDJUgAZMAAAAA.Ravener:BAAALgAECgYJBwAAAA==.Ravincible:BAAALgAECgIJAgAAAA==.Razeal:BAABLgAECn8fAAMNAAYJliADXgC1AQANAAYJPyADXgC1AQADAAIJKxjiMQCGAAAAAA==.',
Re='Reaper:BAACLgAFFH8KAAIbAAQJUyKYRQBpAQAbAAQJUyKYRQBpAQAuAAQKfyEAAxsABwkPJcABAGsBABsABwkPJcABAGsBAAIAAgk+B+BAAEkAAAAA.Reeah:BAAALgADCgkJCQAAAA==.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAABLgAECn8lAAMmAAgJbQ0YPAAhAQAmAAgJaQsYPAAhAQAnAAEJ0A8bVAAxAAAAAA==.Reported:BAAALgAECgEJAQAAAA==.',
Rh='Rhettranger:BAAALgADCgEJAQAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8cAAMOAAcJoiQnCwDoAQAOAAYJuCQnCwDoAQAPAAIJgRnqDABmAAAuAAQKfysAAw4ACQlIJSEJAJMCAA4ACAnGJSEJAJMCAA8AAwnpI/4NADoBAAAA.Rokkgar:BAABLgAECn8oAAIeAAkJHhDmJwCuAQAeAAkJHhDmJwCuAQABLgAECgkJLwAPAH0MAA==.Roosterr:BAAALgADCgkJFgAAAA==.Rottontoe:BAAALgAECgYJDAAAAA==.',
Ru='Ruwazi:BAAALgAECgYJDwAAAA==.',
Ry='Ryujin:BAAALgAECgUJBwAAAA==.',
Sa='Sainted:BAAALgAECgUJBAAAAA==.Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scared:BAACLgAFFH8KAAIcAAUJ7RaGDACCAQAcAAUJ7RaGDACCAQAuAAQKfz0AAhwACAkxH7kKALsCABwACAkxH7kKALsCAAAA.Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Secarious:BAABLgAECn8bAAISAAgJnhDkNQBxAQASAAgJnhDkNQBxAQAAAA==.Sediaria:BAAALgAECgkJCQABLgAFFAQJDgAWACILAA==.Sehnsucht:BAACLgAFFH8MAAMmAAQJJBI4JQABAQAmAAQJJBI4JQABAQAVAAMJfg61RQCeAAAuAAQKfygAAxUACQktHAkeAE4CABUACQktHAkeAE4CACYAAQkAGqB2AEkAAAAA.Serius:BAAALgAECgQJBAABLgAECgkJHQAjAJ0bAA==.',
Sh='Shavoo:BAAALgAECgkJCQAAAA==.Shmadu:BAAALgAECgcJCwAAAA==.Shockk:BAABLgAECn8gAAMeAAkJGRZqKgCfAQAeAAkJGRZqKgCfAQAdAAMJ4AKOigBpAAAAAA==.Shone:BAAALgAECgUJBQAAAA==.',
Si='Siovhan:BAAALgAECgkJEgAAAA==.',
Sl='Sly:BAACLgAFFH8KAAIoAAMJKRvGCADwAAAoAAMJKRvGCADwAAAuAAQKfxUAAigABwkuIM4EACoCACgABwkuIM4EACoCAAEuAAUUBAkKABsAUyIA.',
Sm='Smóóthbói:BAACLgAFFH8GAAIEAAUJygVvdAD1AAAEAAUJygVvdAD1AAAuAAQKfy0AAgQACQmuFWVFAAsCAAQACQmuFWVFAAsCAAAA.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn83AAIIAAkJ8BdREwBEAgAIAAkJ8BdREwBEAgAAAA==.Soola:BAABLgAECn8fAAMdAAgJoQ0TUAByAQAdAAgJoQ0TUAByAQAeAAQJzAwLfQB5AAAAAA==.',
Sp='Spoof:BAAALgAECgIJAgAAAA==.Spoopadin:BAAALgAECgIJBgAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.Sprigg:BAAALgADCgkJCQABLgAFFAUJBgAEAMoFAA==.',
St='Stabbymoose:BAAALgAECgEJAQAAAA==.Stack:BAACLgAFFH8JAAIlAAIJ8hvjJACrAAAlAAIJ8hvjJACrAAAuAAQKfxcAAiUABwnHHm0VAPgBACUABwnHHm0VAPgBAAEuAAUUBAkKABsAUyIA.Stompycouch:BAACLgAFFH8FAAIeAAIJJRH9RAB2AAAeAAIJJRH9RAB2AAAuAAQKfysAAh4ACAnyHDsXAF4CAB4ACAnyHDsXAF4CAAAA.Stoned:BAABLgAECn8nAAMUAAkJJh/uCADhAgAUAAkJJh/uCADhAgANAAMJ3wpWKAGJAAAAAA==.Stonedpriest:BAABLgAECn87AAIcAAkJliA7BwDYAgAcAAkJliA7BwDYAgAAAA==.Stripes:BAAALgADCgUJBQABLgAECgkJLgAEABMWAA==.',
Su='Sunreaver:BAABLgAECn8tAAIbAAkJcyOrFQDFAgAbAAkJcyOrFQDFAgAAAA==.Surrëal:BAABLgAECn8aAAIBAAkJWA7JIAByAQABAAkJWA7JIAByAQABLgAFFAQJDgAWACILAA==.Surtain:BAACLgAFFH8JAAImAAMJfgwGNACwAAAmAAMJfgwGNACwAAAuAAQKfx8AAiYACAk4Hs0UACsCACYACAk4Hs0UACsCAAAA.Suxiv:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetmask:BAABLgAECn8oAAMbAAkJjyPmDQD9AgAbAAkJjyPmDQD9AgApAAIJ2BoQJgChAAAAAA==.',
Sx='Sxv:BAAALgAFFAIJAwAAAA==.',
Sy='Syl:BAACLgAFFH8TAAIWAAQJ4xX/OwA1AQAWAAQJ4xX/OwA1AQAuAAQKfy0AAxYACQlyG6wjAFQCABYACQlyG6wjAFQCABcABQlVCnFZAN8AAAAA.Sylvanii:BAAALgAECgIJAgAAAA==.Sylvanäs:BAABLgAECn8UAAIXAAkJ5AsrDgB8AQAXAAkJ5AsrDgB8AQABLgAECgkJMgALAModAA==.',
['Sï']='Sïdëswïpë:BAAALgAECgEJAgAAAA==.',
['Só']='Sóúndwâve:BAAALgAECgEJAgAAAA==.',
Ta='Tahitian:BAABLgAECn8fAAIWAAkJ9w5lSgDCAQAWAAkJ9w5lSgDCAQAAAA==.Tahlreth:BAABLgAECn88AAMEAAkJ4R/xFgDPAgAEAAkJ4R/xFgDPAgAFAAEJuhm4EQBKAAAAAA==.Tandlia:BAAALgAECgUJCQAAAA==.Tanickz:BAABLgAECn8tAAIEAAkJ2BLaSQD9AQAEAAkJ2BLaSQD9AQAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJLAAeAPscAA==.Tanidgetotem:BAABLgAECn8sAAIeAAkJ+xz8CQD0AgAeAAkJ+xz8CQD0AgAAAA==.Tanya:BAACLgAFFH8SAAIlAAQJ7BYSEgA3AQAlAAQJ7BYSEgA3AQAuAAQKf0AAAiUACQmKI3oDAP8CACUACQmKI3oDAP8CAAAA.Tayanna:BAABLgAECn8aAAMNAAkJFRxCeQB8AQANAAkJCBxCeQB8AQADAAcJAQgGKwDDAAAAAA==.',
Te='Teias:BAACLgAFFH8VAAIcAAUJRRroDAB8AQAcAAUJRRroDAB8AQAuAAQKfzIAAxwACQn5GhQTAEcCABwACQn5GhQTAEcCABAABgkCHfYnAI8BAAAA.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thuras:BAAALgADCgUJBQABLgAECgMJAwATAAAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8iAAIEAAgJox8WPgAjAgAEAAgJox8WPgAjAgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgADCgUJCAATAAAAAA==.',
Tr='Tricko:BAABLgAECn9QAAIWAAkJFB91EgC+AgAWAAkJFB91EgC+AgAAAA==.Trollskingx:BAABLgAECn8eAAIEAAcJwBacdADpAQAEAAcJwBacdADpAQAAAA==.Trollzy:BAABLgAECn8/AAMfAAkJLyGfAgDuAgAfAAkJLyGfAgDuAgAdAAQJjQldpACFAAAAAA==.Trunkmonkey:BAACLgAFFH8JAAIKAAQJIg3/XwAIAQAKAAQJIg3/XwAIAQAuAAQKfy8AAgoACQlbGhEfAGoCAAoACQlbGhEfAGoCAAAA.Trunky:BAAALgAECgYJCwAAAA==.Tryne:BAAALgADCgEJAQAAAA==.',
Ts='Tsaagan:BAACLgAFFH8SAAMKAAQJvhbRTwAmAQAKAAQJNhbRTwAmAQAJAAEJ5RJnIgBOAAAuAAQKfy0ABAoACQkXIaMSALcCAAoACQkqH6MSALcCAAkABAkII/4KAIwBAAsABAkHHrQgAE4BAAAA.',
Tu='Tucker:BAABLgAECn8rAAIaAAkJgh3sCQD6AgAaAAkJgh3sCQD6AgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ud='Uddershaman:BAAALgAECgIJAwAAAA==.',
Ul='Ultramagnús:BAAALgAECgEJAgAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAABLgAECn8cAAQbAAcJrBKIfwBkAQAbAAcJVBKIfwBkAQApAAEJlwpqOgA0AAACAAEJVg36YAAoAAAAAA==.Under:BAAALgADCgcJDgABLgAECgcJHAAbAKwSAA==.Unparalleled:BAABLgAECn8lAAMHAAcJ5AdcHwD7AAAHAAcJ5AdcHwD7AAAMAAUJZAooEwDYAAAAAA==.Unqualified:BAAALgAECgIJAgAAAA==.',
Va='Vaaleros:BAAALgADCgYJBgAAAA==.Valiithria:BAAALgAECgQJBAAAAA==.Valkyruid:BAACLgAFFH8TAAIVAAcJOA9iHwBeAQAVAAcJOA9iHwBeAQAuAAQKfxcAAhUABwnCF4w2AM0BABUABwnCF4w2AM0BAAAA.',
Ve='Vessel:BAAALgAFFAIJAgABLgAFFAQJCgAbAFMiAA==.',
Vi='Vixus:BAAALgAFFAEJAgAAAA==.',
Vx='Vxs:BAAALgAFFAIJAwAAAA==.',
['Vø']='Vøødu:BAAALgAECgYJCwABLgAECgcJGAAdAJEQAA==.',
Wa='Walshidan:BAABLgAECn8aAAIjAAkJ0xBKUgCPAQAjAAkJ0xBKUgCPAQAAAA==.Walshlel:BAAALgADCgkJCQAAAA==.Waywatcher:BAAALgAFFAIJAwAAAA==.',
We='Wenus:BAAALgAECgUJBQAAAA==.',
Wi='Wiccaflame:BAABLgAECn8bAAIEAAkJdSDOGADFAgAEAAkJdSDOGADFAgAAAA==.Wiccasham:BAAALgAECgEJAQAAAA==.',
Wu='Wullgan:BAABLgAECn8fAAMiAAkJ2R6PEgBPAgAiAAgJvx6PEgBPAgAQAAcJGBgkLQBuAQAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAABLgAFFH8KAAIHAAQJvhG7GQD7AAAHAAQJvhG7GQD7AAAAAA==.',
Xo='Xole:BAABLgAECn8fAAMjAAgJnxTiWgB3AQAjAAgJnxTiWgB3AQARAAQJIQSEIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8dAAIjAAkJnRuTMAA5AgAjAAkJnRuTMAA5AgAAAA==.Xyrna:BAAALgAFFAIJAgABLgAFFAUJFQADAHEQAA==.',
Ya='Yareli:BAABLgAECn88AAIRAAkJFgmWEABDAQARAAkJFgmWEABDAQAAAA==.Yawa:BAABLgAFFH8HAAIbAAIJtA2+5ACCAAAbAAIJtA2+5ACCAAAAAA==.',
Ye='Yeahreally:BAAALgADCgkJCQAAAA==.Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQATAAAAAA==.Zankrah:BAAALgAECgQJBAABLgAFFAUJFQAcAEUaAA==.Zarill:BAAALgADCgcJBwAAAA==.Zartman:BAAALgAECgMJBQAAAA==.Zayzoo:BAABLgAECn8WAAIdAAkJYhXCLQAAAgAdAAkJYhXCLQAAAgAAAA==.Zazie:BAABLgAECn8VAAIEAAcJ9QZiyAD9AAAEAAcJ9QZiyAD9AAAAAA==.',
Ze='Zekröm:BAACLgAFFH8VAAIYAAUJcA4zFwDKAAAYAAUJcA4zFwDKAAAuAAQKfx8AAhgACQkyEmsVAKkBABgACQkyEmsVAKkBAAAA.Zekrøm:BAABLgAECn8lAAIeAAgJjxrvGQBEAgAeAAgJjxrvGQBEAgABLgAFFAUJFQAYAHAOAA==.Zeno:BAACLgAFFH8jAAINAAgJcR82BgB6AgANAAgJcR82BgB6AgAuAAQKfxcAAg0ACQkyJfgCAKcDAA0ACQkyJfgCAKcDAAAA.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgADCgkJCQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQATAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQATAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAABLgAECn8vAAIPAAkJfQxYCQCpAQAPAAkJfQxYCQCpAQAAAA==.',
Zi='Zinbar:BAABLgAECn8YAAIlAAgJHxBiIwCCAQAlAAgJHxBiIwCCAQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAABLgAECn8ZAAQkAAkJahmREwAfAgAkAAkJPRmREwAfAgAZAAQJ9BVWVADzAAAaAAEJTQJtcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQATAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAIEAAgJXCBkLwC1AgAEAAgJXCBkLwC1AgAAAA==.Çloudsham:BAAALgAECgEJAgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8vAAQiAAgJpiKqBwD/AgAiAAgJpiKqBwD/AgAcAAUJABoGOwBPAQAQAAEJBhiFfQBDAAAAAA==.',
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
