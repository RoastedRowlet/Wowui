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

local lookup = {'DemonHunter-Havoc','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Devastation','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Warrior-Fury','Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Paladin-Protection','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Mage-Fire','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','Monk-Windwalker','Druid-Restoration','Priest-Discipline','Hunter-Survival','Druid-Balance','Druid-Guardian','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaylasecura:BAACLgAFFH8RAAIBAAQJwxw9BgBkAQABAAQJwxw9BgBkAQAuAAQKfzwAAgEACQmkIwUCACoDAAEACQmkIwUCACoDAAAA.',
Ab='Absolutezero:BAACLgAFFH8HAAICAAQJFBNUSAA3AQACAAQJFBNUSAA3AQAuAAQKfzMAAwIACAnDIBAmAGcCAAIACAmmIBAmAGcCAAMAAgnuFvcUAHcAAAAA.',
Ad='Advïl:BAAALgAECgQJBAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Aletstrasza:BAACLgAFFH8RAAIEAAQJ4xBcFQAHAQAEAAQJ4xBcFQAHAQAuAAQKf0QAAwQACQlHHyADAAIDAAQACQlHHyADAAIDAAUAAQluBfaBACoAAAAA.Alexjuander:BAABLgAECn8bAAQGAAgJlRLMGQC2AAAHAAgJbwgrdgA3AQAIAAUJ6hQ2FADuAAAGAAQJqg3MGQC2AAAAAA==.Alexsander:BAABLgAECn8YAAMFAAYJJhF0OwAWAQAFAAYJJhF0OwAWAQAJAAIJNgbWHABIAAAAAA==.Allysah:BAAALgAECgEJAgABLgAFFAQJFAAKAEkDAA==.Alphard:BAABLgAECn82AAMLAAkJbCJ3AgAXAwALAAkJbCJ3AgAXAwAMAAEJvBvVHgA5AAAAAA==.',
An='Anelowyn:BAABLgAECn8oAAINAAkJNRhnFAAGAgANAAkJNRhnFAAGAgAAAA==.',
Ap='Apocal:BAACLgAFFH8QAAIOAAYJcxa1AQBsAQAOAAYJcxa1AQBsAQAuAAQKfxUAAg4ACAmnG3gGACsCAA4ACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Aralgi:BAAALgAECgEJAQAAAA==.Arete:BAABLgAECn8WAAIPAAYJ3xIUQAAcAQAPAAYJ3xIUQAAcAQAAAA==.Arlandil:BAAALgADCgMJAwAAAA==.Artaimya:BAAALgAECgYJCwAAAA==.Artemìs:BAAALgAECgQJBgAAAA==.',
At='Atmosphere:BAAALgAECgUJBwAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgUJBQAQAAAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAFFAQJBgACAJ0EAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgcJDQAAAA==.Babs:BAAALgAECgUJBgAAAA==.Baraden:BAAALgAECgUJDAAAAA==.Basutai:BAABLgAECn8iAAIRAAkJ5COfAQCKAwARAAkJ5COfAQCKAwAAAA==.',
Be='Beanohuntz:BAAALgADCgIJAgAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgYJDwAAAA==.Birgetta:BAABLgAECn8xAAMSAAkJXg+MOQDNAQASAAkJXg+MOQDNAQATAAYJbQPQHwCNAAAAAA==.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIEAAgJNhlHDABxAgAEAAgJNhlHDABxAgAAAA==.Blasphemous:BAAALgAECgEJAwAAAA==.Blee:BAABLgAECn8uAAIUAAkJTxt0DwDiAQAUAAkJTxt0DwDiAQAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAAQAAAAAA==.',
Bo='Bobodaklown:BAABLgAECn8jAAMKAAkJ9BabOgA5AgAKAAkJYhabOgA5AgAVAAIJmxVnMQBxAAAAAA==.Boomnblood:BAAALgADCgEJAQABLgAFFAQJCwAWAAkGAA==.Boomnbrew:BAACLgAFFH8LAAIWAAQJCQYtKADrAAAWAAQJCQYtKADrAAAuAAQKfzMAAhYACQm5EnMWANYBABYACQm5EnMWANYBAAAA.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8ZAAMTAAkJQAwUGADPAAASAAUJAQ9iegAbAQATAAcJBwoUGADPAAAAAA==.',
Br='Brewman:BAACLgAFFH8KAAIXAAMJeh4hHQALAQAXAAMJeh4hHQALAQAuAAQKfzEAAxcACQmQIakDAFkDABcACQmQIakDAFkDABYACAnhDWotADMBAAAA.',
Bu='Bubonic:BAABLgAECn8rAAIYAAgJ7BfxQgDYAQAYAAgJ7BfxQgDYAQAAAA==.Buenasalud:BAABLgAECn8lAAIZAAkJjBsECwCPAgAZAAkJjBsECwCPAgAAAA==.',
Ca='Caball:BAAALgAECgEJAgAAAA==.Carcharias:BAAALgAECgYJBwAAAA==.Caylea:BAACLgAFFH8dAAIPAAYJQBkgBwCcAQAPAAYJQBkgBwCcAQAuAAQKfywAAg8ACAkrHQYZAIMCAA8ACAkrHQYZAIMCAAAA.',
Ch='Chalis:BAABLgAECn8iAAMGAAcJYB/BCgATAgAHAAYJrB5bJgAqAgAGAAYJ5h3BCgATAgAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAACLgAFFH8HAAMaAAQJIA8zPQC7AAAaAAMJ6AwzPQC7AAAbAAEJ9AE+RgAxAAAuAAQKfx0AAxoACAkSEowyALkBABoACAkSEowyALkBABsAAglfBFKBAD0AAAAA.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAACLgAFFH8HAAICAAMJHQ0IaADlAAACAAMJHQ0IaADlAAAuAAQKfzAAAwIACQksFFNBAP0BAAIACQksFFNBAP0BABwAAQm6A2ARACsAAAAA.Corleon:BAAALgADCgMJAwAAAA==.Corvus:BAAALgAECgQJCwAAAA==.',
Cr='Crizlock:BAAALgAECgEJAQABLgAECgcJFwASAEYjAA==.Crizonk:BAAALgAECgEJAQABLgAECgcJFwASAEYjAA==.Crowdcontrol:BAABLgAECn8aAAIVAAkJFiBlBACRAgAVAAkJFiBlBACRAgAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAACLgAFFH8HAAIdAAMJ1hLiFQDGAAAdAAMJ1hLiFQDGAAAuAAQKfzAAAx4ACQksFjIMAN4BAB4ACQlZDjIMAN4BAB0ABAnIGcEeABMBAAAA.',
Cu='Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgAAAA==.Cursis:BAAALgAECgIJAgAAAA==.',
Da='Daddysixinch:BAAALgAECgMJCAAAAA==.Daelin:BAABLgAECn8qAAMKAAkJ5yKECgD4AgAKAAkJ5yKECgD4AgARAAEJJw3IgAAsAAAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darkcleric:BAAALgADCgYJBgAAAA==.Darknous:BAAALgAECgEJAQAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deante:BAAALgAECgYJEQAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathman:BAABLgAECn8YAAIUAAgJoBeaDwDgAQAUAAgJoBeaDwDgAQABLgAECggJGwAEADYZAA==.Deathrite:BAAALgAFFAEJAQAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCgAAAA==.Demo:BAAALgAFFAMJAwABLgAFFAQJCgAYAFMiAA==.Demonmommy:BAAALgADCgEJAQAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAACLgAFFH8GAAIbAAIJcAOjOABtAAAbAAIJcAOjOABtAAAuAAQKfyYAAhsACQkCElwfALsBABsACQkCElwfALsBAAAA.',
Dh='Dhchin:BAAALgAECgQJBgABLgAFFAUJGQALABslAA==.Dhomsak:BAABLgAFFH8FAAIfAAQJ+hUSKgA+AQAfAAQJ+hUSKgA+AQABLgAFFAUJEwACAD4jAA==.',
Di='Diamonds:BAAALgADCgEJAQAAAA==.Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgUJBQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQAAAA==.',
Do='Doadin:BAABLgAECn8sAAMRAAkJoBvCDQCqAgARAAkJoBvCDQCqAgAKAAEJ1gHBXQEgAAAAAA==.Doominatrix:BAACLgAFFH8JAAMHAAQJ0AndSgAMAQAHAAQJ0AndSgAMAQAIAAEJAwaXHQA+AAAuAAQKfzAAAwcACAmUF8k6ANYBAAcABwmUF8k6ANYBAAgAAQkAAKQqAEoAAAAA.',
Dr='Draggum:BAABLgAECn8eAAMFAAgJ+xmoFwD5AQAFAAgJ+xmoFwD5AQAEAAMJpxD7JACdAAABLgAECgcJIAACAPEaAA==.Dreadraven:BAABLgAECn9IAAMPAAgJYhWXJgAmAgAPAAgJYhWXJgAmAgAeAAEJZQS+aQAjAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8gAAMBAAgJgBRuIQCxAQABAAcJFRVuIQCxAQAfAAgJhBDVWQBWAQABLgAECgEJAQAQAAAAAA==.Dreddstorm:BAAALgAECgEJAgAAAA==.Drewuw:BAABLgAECn8bAAIgAAkJwBaOGQAVAgAgAAkJwBaOGQAVAgABLgAECgkJHQAfAJ0bAA==.Druidhams:BAACLgAFFH8LAAIhAAQJnxFbIwASAQAhAAQJnxFbIwASAQAuAAQKfzMAAiEACQn+HhMLAO4CACEACQn+HhMLAO4CAAAA.',
Ea='Eamon:BAAALgAECgQJCAABLgAFFAMJBQANAFcIAA==.',
Ei='Eightball:BAAALgADCgUJBQAAAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgUJBgAAAA==.Elisha:BAACLgAFFH8UAAIKAAQJSQNgRwDzAAAKAAQJSQNgRwDzAAAuAAQKf1UAAgoACQnyGKIjAFYCAAoACQnyGKIjAFYCAAAA.Elsyra:BAAALgAECgYJCQAAAA==.',
Er='Erebostro:BAABLgAECn82AAISAAkJNxnsHwA+AgASAAkJNxnsHwA+AgAAAA==.',
Ev='Everclear:BAAALgAECggJDAABLgAFFAQJCwAVAD8LAA==.Evillux:BAACLgAFFH8FAAMHAAIJbQWqkgBxAAAHAAIJbQWqkgBxAAAGAAEJZAAAIwAkAAAuAAQKfy8AAwcACQm2EMA8AM8BAAcACQlHEMA8AM8BAAYABQnmDH0qABcBAAAA.',
Ey='Eyeguy:BAABLgAECn8VAAMfAAkJHxyYJwBmAgAfAAkJLBmYJwBmAgABAAQJ+h+0NgAsAQAAAA==.',
Fa='Fathercow:BAACLgAFFH8LAAIiAAQJwB/8FAB1AQAiAAQJwB/8FAB1AQAuAAQKfykAAiIACQn3H60EACQDACIACQn3H60EACQDAAAA.',
Fi='Fingies:BAACLgAFFH8QAAQHAAQJaBuTNwA1AQAHAAQJrRaTNwA1AQAIAAEJoh70DgBdAAAGAAEJ1RKKGQBSAAAuAAQKfz0AAwcACQmhJDkMANcCAAcABwknJTkMANcCAAYABQmyHkoVAJ8BAAAA.Fistin:BAAALgAECgYJBwAAAA==.',
Fr='Frieren:BAAALgADCgYJBgAAAA==.',
Fu='Fungies:BAAALgAECgUJBQABLgAFFAQJEAAHAGgbAA==.Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAACLgAFFH8LAAISAAQJoxYFIQBEAQASAAQJoxYFIQBEAQAuAAQKfzIAAxIACQllIncHAAEDABIACQllIncHAAEDACMABQmiDRk1AN8AAAAA.',
Ga='Gaijin:BAAALgADCgMJAwABLgAFFAMJBQANAFcIAA==.Galaxsea:BAABLgAECn8YAAIgAAkJ1x2+CgBzAgAgAAkJ1x2+CgBzAgAAAA==.Gargapew:BAAALgAECgIJAgABLgAFFAMJBQACAMQJAA==.',
Ge='Gerthquake:BAABLgAECn8lAAMbAAkJzRk7EABLAgAbAAkJzRk7EABLAgAaAAkJEh7BJgD4AQAAAA==.',
Gf='Gfour:BAABLgAECn8fAAIXAAgJjhx2EwAvAgAXAAgJjhx2EwAvAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.Ghraxxy:BAAALgAECggJEAAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Gobø:BAAALgAECgYJEQAAAA==.Goodytwoshoe:BAAALgAECgIJBwAAAA==.',
Gr='Grimmreefer:BAAALgAECgUJBQAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgQJCgAAAA==.',
['Gâ']='Gâlvatron:BAAALgADCgEJAQAAAA==.',
Ha='Hakz:BAAALgADCgkJCQAAAA==.',
He='Heart:BAABLgAFFH8HAAMiAAMJtQfQJgDJAAAiAAMJtQfQJgDJAAANAAEJgAKMMAA9AAABLgAFFAQJCgAYAFMiAA==.Help:BAAALgADCgEJAQAAAA==.',
Ho='Homlock:BAAALgAECgYJEAABLgAFFAUJEwACAD4jAA==.Homsorc:BAACLgAFFH8TAAMCAAUJPiPiBwDlAQACAAUJPiPiBwDlAQADAAEJByTVAgBjAAAuAAQKfyMAAgIACQlLJTMFAK8DAAIACQlLJTMFAK8DAAAA.Homtard:BAABLgAFFH8PAAMTAAcJgCEvBAD5AQATAAcJ1CAvBAD5AQAjAAQJxRhIDQBEAQABLgAFFAUJEwACAD4jAA==.Hope:BAABLgAECn8zAAMRAAkJVhvTDgCDAgARAAkJVhvTDgCDAgAKAAQJ5wfc5ACwAAAAAA==.',
['Hô']='Hôûnd:BAAALgAECgEJAQAAAA==.',
Id='Idun:BAAALgAECgYJCgAAAA==.',
Il='Illiandray:BAABLgAECn8yAAMGAAkJyh3IAQCXAgAGAAkJyh3IAQCXAgAHAAgJUgr7ewAsAQAAAA==.Ilswyn:BAAALgADCgUJBQABLgAECgkJMAAfACAkAA==.',
Im='Imu:BAACLgAFFH8KAAMjAAMJoCFYEwAOAQAjAAMJoCFYEwAOAQASAAEJxhnZcQBNAAAuAAQKfyIABCMABwkOJSQKAGQCACMABwkOJSQKAGQCABMABQk/DfFUAPYAABIAAgmLCs6nAHYAAAEuAAUUBgkYAAoA8SUA.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn8wAAIfAAkJICQZBAAzAwAfAAkJICQZBAAzAwAAAA==.',
Io='Ionise:BAABLgAECn8kAAIFAAkJKRuADAB2AgAFAAkJKRuADAB2AgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Iskgard:BAAALgAECgcJBwAAAA==.Isklar:BAACLgAFFH8JAAIUAAIJJBzNIACeAAAUAAIJJBzNIACeAAAuAAQKfy8AAhQACAm4I4UEAAIDABQACAm4I4UEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAABLgAECn8kAAQFAAcJiRvwIQCnAQAFAAcJiRvwIQCnAQAJAAMJixcUEgDGAAAEAAMJbwy0OQCdAAAAAA==.',
Je='Jer:BAABLgAECn8cAAILAAkJ1RAyFABzAgALAAkJ1RAyFABzAgAAAA==.',
Ju='Jugernat:BAAALgADCgEJAQAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAFFAMJBQANAFcIAA==.',
Ka='Kaalo:BAAALgADCgUJBQAAAA==.Kairi:BAAALgAECgYJCAAAAA==.Kammo:BAACLgAFFH8TAAIYAAQJxiD4HgCWAQAYAAQJxiD4HgCWAQAuAAQKf0QAAhgACQkxJqcBAHgDABgACQkxJqcBAHgDAAAA.Kazypher:BAAALgAECgMJCgAAAA==.',
Ke='Keeah:BAAALgAECgQJCAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAIXAAkJCgfzMQAvAQAXAAkJCgfzMQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAFFAMJBQANAFcIAA==.Kiwi:BAAALgAECgcJBwAAAA==.',
Kl='Klingnor:BAAALgADCgMJAwAAAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8RAAITAAYJbhbOCQB8AQATAAYJbhbOCQB8AQAuAAQKfyAAAhMABwnLIYYJALUBABMABwnLIYYJALUBAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwikin:BAABLgAECn8gAAICAAcJ8RqMVQA3AgACAAcJ8RqMVQA3AgAAAA==.',
Ky='Kyreen:BAABLgAECn8ZAAISAAgJFAvkWwBjAQASAAgJFAvkWwBjAQAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECgkJGAAgANcdAA==.',
La='Laaz:BAACLgAFFH8KAAIfAAMJswXvVwCuAAAfAAMJswXvVwCuAAAuAAQKfzYAAh8ACQlXExUvAOsBAB8ACQlXExUvAOsBAAAA.Lamalen:BAABLgAECn8UAAIKAAcJnxoSYQDBAQAKAAcJnxoSYQDBAQAAAA==.Lasercow:BAAALgAECgcJCAABLgAFFAQJCwAiAMAfAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Liena:BAAALgADCgIJAgAAAA==.Linthvia:BAAALgAECgUJCAAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgAECgEJAgAAAA==.',
Lo='Locknloaded:BAAALgAECgQJBQAAAA==.',
Lu='Luciuos:BAABLgAECn8ZAAMkAAkJqwKmTwCeAAAkAAkJqwKmTwCeAAAhAAcJ9QEFjgB2AAAAAA==.Lucreesha:BAAALgAECgUJBQABLgAECgkJHQAfAJ0bAA==.Lukafox:BAACLgAFFH8XAAIaAAYJ3hwSCQDnAQAaAAYJ3hwSCQDnAQAuAAQKfyAAAxoACQlZH6gHAPoCABoACQlZH6gHAPoCABsAAQmKAn6WAB0AAAAA.Lunastarvale:BAABLgAECn87AAISAAkJTxxCFQB/AgASAAkJTxxCFQB/AgAAAA==.Luscinia:BAAALgAECgIJAgAAAA==.',
Ma='Madith:BAACLgAFFH8IAAIfAAMJ3hTHRgDlAAAfAAMJ3hTHRgDlAAAuAAQKfyMAAh8ACAlfIDkTAIsCAB8ACAlfIDkTAIsCAAAA.Magicjamo:BAAALgAECgUJBQAAAA==.Maleficênt:BAAALgAECggJDgABLgAFFAMJCgAlAMIHAA==.Malefisico:BAABLgAECn8cAAMHAAkJ7w/FbQCFAQAHAAkJ7w/FbQCFAQAGAAEJAACKeAArAAAAAA==.Malgarok:BAABLgAECn8lAAIHAAgJWBygHgCfAgAHAAgJWBygHgCfAgABLgAECgYJEAAQAAAAAA==.Mardríft:BAACLgAFFH8KAAIkAAQJsBE4GgAeAQAkAAQJsBE4GgAeAQAuAAQKfzoAAiQACQnYIRQHAMQCACQACQnYIRQHAMQCAAAA.Mazga:BAABLgAECn8rAAImAAgJpBaYDACyAQAmAAgJpBaYDACyAQAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8uAAIjAAkJihgvCwBVAgAjAAkJihgvCwBVAgAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgAECgQJBAAAAA==.Mezoti:BAACLgAFFH8GAAIFAAMJywI6OwCeAAAFAAMJywI6OwCeAAAuAAQKfxYAAwUACAmhDv8qAG4BAAUACAmhDv8qAG4BAAQACAm/CPgVAEgBAAAA.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCgkJEwAAAA==.',
Mo='Moji:BAABLgAECn80AAIXAAkJ+BxWCQDQAgAXAAkJ+BxWCQDQAgAAAA==.Monstermayi:BAACLgAFFH8LAAIPAAQJSRBVGgAlAQAPAAQJSRBVGgAlAQAuAAQKfy0AAg8ACQkrF8EVAB0CAA8ACQkrF8EVAB0CAAAA.Mooknight:BAABLgAECn82AAIUAAkJFBWMDwDhAQAUAAkJFBWMDwDhAQAAAA==.Moosen:BAAALgAECgcJBwAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8nAAIgAAgJXBreFgDVAQAgAAgJXBreFgDVAQAAAA==.',
Mu='Muggy:BAABLgAECn81AAIMAAgJbxcsBQAKAgAMAAgJbxcsBQAKAgAAAA==.',
My='Myluutarania:BAAALgAECgcJCwAAAA==.Myrothar:BAABLgAECn8UAAMRAAgJMhU0MwBeAQARAAcJKxY0MwBeAQAKAAYJDQPR7AClAAAAAA==.Mytastical:BAACLgAFFH8GAAICAAQJnQRNWwAFAQACAAQJnQRNWwAFAQAuAAQKfycAAgIACAlrFmd+ANQBAAIACAlrFmd+ANQBAAAA.',
['Mæ']='Mæve:BAACLgAFFH8FAAIhAAMJBQXCOwCjAAAhAAMJBQXCOwCjAAAuAAQKfzAAAyEACQnOGLcYAF0CACEACQnOGLcYAF0CACQABQmNESxGABUBAAAA.',
['Më']='Mëgatron:BAAALgAECgEJAQAAAA==.',
Na='Namalis:BAACLgAFFH8OAAMHAAQJSRt+MgBBAQAHAAQJMBp+MgBBAQAIAAEJ9h6pDwBaAAAuAAQKfx0ABAcACAkTJQU5ACcCAAcABgkPJQU5ACcCAAYAAgkWIqA8AMIAAAgAAQkAADIhAG0AAAAA.Nanielito:BAACLgAFFH8FAAICAAMJxAljbQDaAAACAAMJxAljbQDaAAAuAAQKfyUAAgIACQnGH/MUAMECAAIACQnGH/MUAMECAAAA.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8KAAICAAQJvRIMSgA0AQACAAQJvRIMSgA0AQAuAAQKfycAAgIACQklG2csAEoCAAIACQklG2csAEoCAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
No='Nokoa:BAAALgAECggJCAAAAA==.Nonae:BAABLgAECn8gAAISAAgJjh0bEgCnAgASAAgJjh0bEgCnAgAAAA==.Norivari:BAAALgAECgIJAgAAAA==.Nosliw:BAAALgADCgUJCAAAAA==.Notawarlock:BAAALgADCgMJAwAAAA==.Noxilis:BAAALgAECgEJAQAAAA==.',
Ob='Obiwon:BAAALgAECgQJCAAAAA==.',
Og='Ogsmashsauce:BAAALgAECgEJAQAAAA==.',
Om='Omegá:BAACLgAFFH8LAAIVAAQJPwujBwDRAAAVAAQJPwujBwDRAAAuAAQKfyIAAhUACQkuFVoOALABABUACQkuFVoOALABAAAA.',
Oo='Oopsalldruid:BAAALgAECgUJCAABLgAECgcJIAACAPEaAA==.',
Op='Optìmusprìme:BAABLgAECn82AAIdAAkJ+h36BQCPAgAdAAkJ+h36BQCPAgAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Papa:BAACLgAFFH8FAAMIAAIJcB8yFABTAAAHAAEJRyBSlgBcAAAIAAEJmh4yFABTAAAuAAQKfzAABAYACQkdIcUCANYCAAYABwlRIcUCANYCAAgACAm5Ij0CAI4CAAcABQmhHAlTAIwBAAAA.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAFFAEJAQAAAA==.',
Po='Pockets:BAABLgAECn8pAAICAAgJzBY0VADDAQACAAgJzBY0VADDAQAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAAALgAECgYJEwAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAACLgAFFH8FAAMNAAMJVwhHHQDUAAANAAMJVwhHHQDUAAAiAAIJ2BbrKgChAAAuAAQKfzcAAyIACQnjHogIAMYCACIACQnjHogIAMYCAA0AAgmcEihqADoAAAAA.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAECgYJEAAAAA==.',
Qu='Quick:BAAALgAECgEJAgABLgAECgcJIAACAPEaAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Rangedrhett:BAAALgADCgEJAQAAAA==.Ratha:BAACLgAFFH8KAAIVAAMJyBO+CAC7AAAVAAMJyBO+CAC7AAAuAAQKfzEAAxUACQmqGX8OAK0BABUACQmqGX8OAK0BAAoABAkVDJDzAJsAAAAA.Ravener:BAAALgAECgYJBwAAAA==.Razeal:BAABLgAECn8cAAMKAAYJliA7TADDAQAKAAYJPyA7TADDAQAVAAIJKxjiMQCGAAAAAA==.',
Re='Reaper:BAACLgAFFH8KAAIYAAQJUyLSIgCJAQAYAAQJUyLSIgCJAQAuAAQKfx0AAxgABwkPJaAjAFQCABgABwkPJaAjAFQCABQAAgk+B+BAAEkAAAAA.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAABLgAECn8WAAIkAAcJQwouOwDzAAAkAAcJQwouOwDzAAAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8ZAAMLAAUJGyXyBwCsAQALAAUJGyXyBwCsAQAMAAEJzQ77BQBeAAAuAAQKfysAAwsACQlIJToGAKkCAAsACAnGJToGAKkCAAwAAwnpI/4NADoBAAAA.Rokkgar:BAABLgAECn8fAAIbAAcJiw28PQANAQAbAAcJiw28PQANAQABLgAECgcJJgAMACYMAA==.Roosterr:BAAALgADCgkJFgAAAA==.',
Ru='Ruwazi:BAAALgAECgYJDwAAAA==.',
Rx='Rxdh:BAAALgAECgIJAgAAAA==.',
Ry='Ryujin:BAAALgAECgQJBgAAAA==.',
Sa='Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Secarious:BAABLgAECn8bAAIPAAgJnhADKwCEAQAPAAgJnhADKwCEAQAAAA==.Sehnsucht:BAACLgAFFH8KAAMkAAMJWBE3JADVAAAkAAMJWBE3JADVAAAhAAMJfg6vMwDCAAAuAAQKfygAAyEACQktHAkeAE4CACEACQktHAkeAE4CACQAAQkAGqB2AEkAAAAA.Serius:BAAALgAECgQJBAABLgAECgkJHQAfAJ0bAA==.',
Sh='Shmadu:BAAALgAECgcJCwAAAA==.Shockk:BAABLgAECn8gAAMbAAkJGRbYIQCoAQAbAAkJGRbYIQCoAQAaAAMJ4AKOigBpAAAAAA==.',
Si='Siovhan:BAAALgAECggJEAAAAA==.',
Sl='Sly:BAABLgAFFH8JAAInAAMJKRvhBQD+AAAnAAMJKRvhBQD+AAABLgAFFAQJCgAYAFMiAA==.',
Sm='Smóóthbói:BAABLgAECn8sAAICAAkJTBU0OQAYAgACAAkJTBU0OQAYAgAAAA==.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn83AAIFAAkJ8BfDDwBMAgAFAAkJ8BfDDwBMAgAAAA==.Soola:BAABLgAECn8fAAMaAAgJoQ18QQB1AQAaAAgJoQ18QQB1AQAbAAQJzAzZZwB6AAAAAA==.',
Sp='Spoof:BAAALgAECgIJAgAAAA==.Spoopadin:BAAALgAECgIJBgAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.',
St='Stack:BAACLgAFFH8IAAIjAAIJ8huGGwC8AAAjAAIJ8huGGwC8AAAuAAQKfxQAAiMABwkmHCsVAN8BACMABwkmHCsVAN8BAAEuAAUUBAkKABgAUyIA.Stompycouch:BAACLgAFFH8FAAIbAAIJJRGXMgCIAAAbAAIJJRGXMgCIAAAuAAQKfysAAhsACAnyHDsXAF4CABsACAnyHDsXAF4CAAAA.Stoned:BAABLgAECn8nAAMRAAkJJh/uCADhAgARAAkJJh/uCADhAgAKAAMJ3wr59ACZAAAAAA==.Stonedpriest:BAABLgAECn8wAAIZAAkJliA7BwDYAgAZAAkJliA7BwDYAgAAAA==.Stripes:BAAALgADCgUJBQAAAA==.',
Su='Sunreaver:BAABLgAECn8tAAIYAAkJcyPrDgDWAgAYAAkJcyPrDgDWAgAAAA==.Surrëal:BAAALgAECgkJEgABLgAECgkJMQASAF4PAA==.Surtain:BAACLgAFFH8FAAIkAAMJxwiWJwC+AAAkAAMJxwiWJwC+AAAuAAQKfx8AAiQACAk4Hq8QADECACQACAk4Hq8QADECAAAA.Suxiv:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetmask:BAABLgAECn8hAAIYAAcJgyPAKQA3AgAYAAcJgyPAKQA3AgAAAA==.',
Sx='Sxv:BAAALgAFFAEJAQAAAA==.',
Sy='Syl:BAACLgAFFH8JAAISAAQJ2hREKAAzAQASAAQJ2hREKAAzAQAuAAQKfysAAxIACQlyG5IYAGoCABIACQlyG5IYAGoCABMABQlVCnFZAN8AAAAA.Sylvanäs:BAAALgAECgkJCQABLgAECgkJMgAGAModAA==.',
['Sï']='Sïdëswïpë:BAAALgAECgEJAQAAAA==.',
['Só']='Sóúndwâve:BAAALgAECgEJAQAAAA==.',
Ta='Tahitian:BAABLgAECn8eAAISAAkJ9w7CNwDUAQASAAkJ9w7CNwDUAQAAAA==.Tahlreth:BAABLgAECn8zAAICAAkJLB7nFADBAgACAAkJLB7nFADBAgAAAA==.Tandlia:BAAALgAECgQJAwAAAA==.Tanickz:BAABLgAECn8kAAICAAkJ9g+dSADmAQACAAkJ9g+dSADmAQAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJLAAbAPscAA==.Tanidgetotem:BAABLgAECn8sAAIbAAkJ+xz8CQD0AgAbAAkJ+xz8CQD0AgAAAA==.Tanya:BAACLgAFFH8RAAIjAAQJ7Bb1CwBNAQAjAAQJ7Bb1CwBNAQAuAAQKf0AAAiMACQmKIyYCABUDACMACQmKIyYCABUDAAAA.Tayanna:BAAALgAECgYJEwAAAA==.',
Te='Teias:BAACLgAFFH8KAAIZAAMJLhgnFAD1AAAZAAMJLhgnFAD1AAAuAAQKfzEAAxkACQnOGBQTAEcCABkACQnOGBQTAEcCAA0ABgkCHXYgAJoBAAAA.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thuras:BAAALgADCgUJBQABLgAECgMJAwAQAAAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8iAAICAAgJox9KMgAyAgACAAgJox9KMgAyAgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgADCgUJCAAQAAAAAA==.',
Tr='Tricko:BAABLgAECn8yAAISAAgJaR/HIwApAgASAAgJaR/HIwApAgAAAA==.Trollskingx:BAAALgAECgcJEQAAAA==.Trollzy:BAABLgAECn82AAMmAAkJ5yAlAgDiAgAmAAkJ5yAlAgDiAgAaAAEJhgMupgApAAAAAA==.Trunkmonkey:BAACLgAFFH8FAAIHAAMJwAk8ZQDNAAAHAAMJwAk8ZQDNAAAuAAQKfy4AAgcACQkyGo4XAH4CAAcACQkyGo4XAH4CAAAA.Tryne:BAAALgADCgEJAQAAAA==.',
Ts='Tsaagan:BAACLgAFFH8LAAMHAAQJxBNwOAAzAQAHAAQJThNwOAAzAQAIAAEJmxKaFwBOAAAuAAQKfysABAcACQkLIR0PALwCAAcACQkeHx0PALwCAAgABAkII/4KAIwBAAYABAkHHrQgAE4BAAAA.',
Tu='Tucker:BAABLgAECn8rAAIXAAkJgh04BwD8AgAXAAkJgh04BwD8AgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ud='Uddershaman:BAAALgADCgIJAgAAAA==.',
Ul='Ultramagnús:BAAALgAECgEJAQAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAABLgAECn8bAAMYAAcJVBLgZwByAQAYAAcJVBLgZwByAQAoAAEJlwo2KgA0AAAAAA==.Under:BAAALgADCgcJDgABLgAECgcJGwAYAFQSAA==.Unparalleled:BAABLgAECn8jAAMEAAcJRwd+GwABAQAEAAcJRwd+GwABAQAJAAUJZAr7DwDoAAAAAA==.',
Va='Vaaleros:BAAALgADCgYJBgAAAA==.Valiithria:BAAALgAECgQJBAAAAA==.Valkyruid:BAACLgAFFH8SAAIhAAYJLxBoEgCSAQAhAAYJLxBoEgCSAQAuAAQKfxcAAiEABwnCF4w2AM0BACEABwnCF4w2AM0BAAAA.',
Ve='Vessel:BAAALgAFFAIJAgABLgAFFAQJCgAYAFMiAA==.',
Vi='Vixus:BAAALgAFFAEJAQAAAA==.',
Vx='Vxs:BAAALgAFFAEJAQAAAA==.',
['Vø']='Vøødu:BAAALgAECgUJBQABLgAECgcJGAAaAJEQAA==.',
Wa='Walshidan:BAABLgAECn8aAAIfAAkJ0xANRACZAQAfAAkJ0xANRACZAQAAAA==.Waywatcher:BAAALgAECgUJCAAAAA==.',
We='Wenus:BAAALgAECgUJBQAAAA==.',
Wi='Wiccaflame:BAABLgAECn8bAAICAAkJdSAXEgDVAgACAAkJdSAXEgDVAgAAAA==.Wiccasham:BAAALgAECgEJAQAAAA==.',
Wu='Wullgan:BAABLgAECn8fAAMiAAkJ2R5ODgBbAgAiAAgJvx5ODgBbAgANAAcJGBirJAB8AQAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAABLgAFFH8GAAIEAAMJQw4rGgDAAAAEAAMJQw4rGgDAAAAAAA==.',
Xo='Xole:BAABLgAECn8fAAMfAAgJnxTVSgCDAQAfAAgJnxTVSgCDAQAOAAQJIQSEIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8dAAIfAAkJnRuTMAA5AgAfAAkJnRuTMAA5AgAAAA==.Xyrna:BAAALgAECggJDQABLgAFFAMJCgAVAMgTAA==.',
Ya='Yareli:BAABLgAECn8oAAIOAAgJcQieEAAXAQAOAAgJcQieEAAXAQAAAA==.Yawa:BAAALgAFFAEJAwAAAA==.',
Ye='Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQAQAAAAAA==.Zankrah:BAAALgAECgQJBAABLgAFFAMJCgAZAC4YAA==.Zarill:BAAALgADCgcJBwAAAA==.Zartman:BAAALgAECgEJAgAAAA==.Zayzoo:BAAALgAECgUJDQAAAA==.Zazie:BAAALgAECgYJCwAAAA==.',
Ze='Zekröm:BAACLgAFFH8KAAIlAAMJwgemFgCIAAAlAAMJwgemFgCIAAAuAAQKfx8AAiUACQkyEsUPAK4BACUACQkyEsUPAK4BAAAA.Zekrøm:BAABLgAECn8dAAIbAAgJjxrvGQBEAgAbAAgJjxrvGQBEAgABLgAFFAMJCgAlAMIHAA==.Zeno:BAACLgAFFH8dAAIKAAgJlR7xAQCJAgAKAAgJlR7xAQCJAgAuAAQKfxcAAgoACQkyJfgCAKcDAAoACQkyJfgCAKcDAAAA.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgADCgkJCQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQAQAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQAQAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAABLgAECn8mAAIMAAcJJgyZDAA/AQAMAAcJJgyZDAA/AQAAAA==.',
Zi='Zinbar:BAAALgAECgcJEQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAABLgAECn8ZAAQgAAkJahk7DwAuAgAgAAkJPRk7DwAuAgAWAAQJ9BVWVADzAAAXAAEJTQJtcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQAQAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAICAAgJXCBkLwC1AgACAAgJXCBkLwC1AgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8qAAQiAAgJ2yEeCQCqAgAiAAgJ2yEeCQCqAgAZAAUJABoGOwBPAQANAAEJBhidZgBDAAAAAA==.',
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
