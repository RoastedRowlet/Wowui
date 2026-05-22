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

local lookup = {'DemonHunter-Havoc','Mage-Frost','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','Warrior-Fury','Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Paladin-Protection','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Unholy','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Mage-Fire','Warrior-Arms','Warrior-Protection','Rogue-Outlaw','DemonHunter-Devourer','Monk-Windwalker','Druid-Restoration','Priest-Discipline','Hunter-Survival','Druid-Balance','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Malorne',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaylasecura:BAACLgAFFH8NAAIBAAQJmRysBABhAQABAAQJmRysBABhAQAuAAQKfzcAAgEACQklIiICAAsDAAEACQklIiICAAsDAAAA.',
Ab='Absolutezero:BAABLgAECn8tAAMCAAgJGSCmIABfAgACAAgJ+x+mIABfAgADAAIJ7hb3FAB3AAAAAA==.',
Ad='Advïl:BAAALgAECgQJBAAAAA==.',
Ae='Aeriale:BAAALgADCggJCAAAAA==.',
Ai='Aidthrower:BAAALgAECgQJBAAAAA==.',
Al='Aletstrasza:BAACLgAFFH8NAAIEAAQJ4xC3EgAIAQAEAAQJ4xC3EgAIAQAuAAQKfz8AAwQACQkuH7MCAPwCAAQACQkuH7MCAPwCAAUAAQluBVRyACoAAAAA.Alexjuander:BAABLgAECn8XAAQGAAgJehKaDwDwAAAHAAgJKgaUcgAYAQAGAAUJ6hSaDwDwAAAIAAMJQhFmGQCgAAAAAA==.Alexsander:BAABLgAECn8UAAMFAAYJ9wwuSgCtAAAFAAYJ9wwuSgCtAAAJAAIJNgZyGQBIAAAAAA==.Allysah:BAAALgAECgEJAgABLgAFFAQJEAAKAIQCAA==.Alphard:BAABLgAECn8tAAMLAAkJKCDrAwDCAgALAAkJKCDrAwDCAgAMAAEJvBvVHgA5AAAAAA==.',
An='Anelowyn:BAABLgAECn8oAAINAAkJNRhqDwAUAgANAAkJNRhqDwAUAgAAAA==.',
Ap='Apocal:BAACLgAFFH8PAAIOAAYJcxYlAQB3AQAOAAYJcxYlAQB3AQAuAAQKfxUAAg4ACAmnG3gGACsCAA4ACAmnG3gGACsCAAAA.Apothecary:BAAALgAECgEJAgAAAA==.',
Ar='Aralgi:BAAALgAECgEJAQAAAA==.Arete:BAABLgAECn8WAAIPAAYJ3xKBNQAiAQAPAAYJ3xKBNQAiAQAAAA==.Arlandil:BAAALgADCgEJAQAAAA==.Artaimya:BAAALgAECgYJCwAAAA==.Artemìs:BAAALgAECgEJAgAAAA==.',
At='Atmosphere:BAAALgAECgUJBwAAAA==.Atteh:BAAALgADCgcJBwAAAA==.',
Au='Aug:BAAALgADCgMJAwABLgADCgUJBQAQAAAAAA==.',
Av='Avizandum:BAAALgADCgYJBgABLgAECggJJQACAGsWAA==.',
Az='Azazel:BAAALgAECgYJBgAAAA==.',
Ba='Baboloanji:BAAALgAECgcJDQAAAA==.Babs:BAAALgAECgUJBgAAAA==.Baraden:BAAALgAECgQJBwAAAA==.Basutai:BAABLgAECn8aAAIRAAkJjyNwAQB+AwARAAkJjyNwAQB+AwAAAA==.',
Be='Beanohuntz:BAAALgADCgIJAgAAAA==.Beefy:BAAALgAECgYJBgAAAA==.Beerusjr:BAAALgAFFAEJAQAAAA==.',
Bi='Biglight:BAAALgAECgMJAwAAAA==.Bigtimmehss:BAAALgAECgYJDQAAAA==.Birgetta:BAABLgAECn8uAAMSAAkJXw+zLQDUAQASAAkJXw+zLQDUAQATAAYJbQMeHACOAAAAAA==.',
Bl='Blacknife:BAAALgADCgQJBAAAAA==.Blahblahman:BAABLgAECn8bAAIEAAgJNhlHDABxAgAEAAgJNhlHDABxAgAAAA==.Blasphemous:BAAALgAECgEJAwAAAA==.Blee:BAABLgAECn8jAAIUAAkJTxvoCwD5AQAUAAkJTxvoCwD5AQAAAA==.Blitzkrieged:BAAALgADCgEJAQABLgAECgYJEAAQAAAAAA==.',
Bo='Bobodaklown:BAABLgAECn8jAAMKAAkJ9BaKNgDfAQAKAAkJYhaKNgDfAQAVAAIJmxVzKgB1AAAAAA==.Boomnblood:BAAALgADCgEJAQABLgAFFAIJBwAWAEoEAA==.Boomnbrew:BAACLgAFFH8HAAIWAAIJSgScOwBxAAAWAAIJSgScOwBxAAAuAAQKfzAAAhYACQn0EYUUAM0BABYACQn0EYUUAM0BAAAA.Boppa:BAAALgAECggJEgAAAA==.Bownir:BAABLgAECn8YAAMTAAgJ8QwAFQDSAAASAAQJ6BBGfQDjAAATAAcJBwoAFQDSAAAAAA==.',
Br='Brewman:BAACLgAFFH8HAAIXAAIJQR18IwCdAAAXAAIJQR18IwCdAAAuAAQKfzAAAxcACQmQIbACAF0DABcACQmQIbACAF0DABYACAnhDaQnADUBAAAA.',
Bu='Bubonic:BAABLgAECn8jAAIYAAgJmBZBQgC2AQAYAAgJmBZBQgC2AQAAAA==.Buenasalud:BAABLgAECn8lAAIZAAkJjBtLCACeAgAZAAkJjBtLCACeAgAAAA==.',
Ca='Caball:BAAALgAECgEJAQAAAA==.Carcharias:BAAALgAECgYJBwAAAA==.Caylea:BAACLgAFFH8XAAIPAAUJxBnrEAA9AQAPAAUJxBnrEAA9AQAuAAQKfycAAg8ACAllHAYZAIMCAA8ACAllHAYZAIMCAAAA.',
Ch='Chalis:BAABLgAECn8fAAMIAAcJCh/BCgATAgAIAAYJ5h3BCgATAgAHAAYJ6x0SJAASAgAAAA==.Cheezypoofs:BAAALgADCgQJBAAAAA==.Chorn:BAAALgADCgEJAQAAAA==.',
Cl='Clamsquirter:BAABLgAECn8aAAMaAAgJwxGNKQC9AQAaAAgJwxGNKQC9AQAbAAIJXwT+cAA9AAAAAA==.Clanistraza:BAAALgADCgMJAwAAAA==.',
Co='Coldhwip:BAABLgAECn8uAAMCAAkJuxOFNQABAgACAAkJuxOFNQABAgAcAAEJugNgEQArAAAAAA==.Corleon:BAAALgADCgMJAwAAAA==.Corvus:BAAALgAECgQJCgAAAA==.',
Cr='Crowdcontrol:BAABLgAECn8aAAIVAAkJFiA6AwCaAgAVAAkJFiA6AwCaAgAAAA==.Crushfoot:BAAALgAECgIJAgAAAA==.Crysis:BAABLgAECn8uAAMdAAkJKRYyDADeAQAdAAkJWQ4yDADeAQAeAAQJwxmxGQAdAQAAAA==.',
Cu='Cuddleßear:BAAALgAECgUJDgAAAA==.Cueball:BAAALgADCgYJBgAAAA==.Cursis:BAAALgAECgIJAgAAAA==.',
Da='Daddysixinch:BAAALgAECgMJBgAAAA==.Daelin:BAABLgAECn8oAAMKAAkJ4yJWBwABAwAKAAkJ4yJWBwABAwARAAEJJw0fdAAtAAAAAA==.Dardanis:BAAALgAECgYJCQAAAA==.Darknous:BAAALgAECgEJAQAAAA==.',
De='Dead:BAAALgAECgQJBwAAAA==.Deante:BAAALgAECgYJBgAAAA==.Deathblitz:BAAALgAECgYJEAAAAA==.Deathman:BAAALgAECggJEAABLgAECggJGwAEADYZAA==.Deathrite:BAAALgAFFAEJAQAAAA==.Delay:BAAALgADCgMJAwAAAA==.Delium:BAAALgAECgUJCgAAAA==.Demo:BAAALgAFFAIJAgABLgAFFAMJBwAfAM4XAA==.Demonmommy:BAAALgADCgEJAQAAAA==.Desmordin:BAAALgAECgYJBgAAAA==.Destis:BAAALgAECgUJBwAAAA==.Deäthrose:BAACLgAFFH8GAAIbAAIJcAPrLwBxAAAbAAIJcAPrLwBxAAAuAAQKfyMAAhsACQlLEXUbALABABsACQlLEXUbALABAAAA.',
Dh='Dhchin:BAAALgAECgEJAgABLgAFFAUJFAALALYjAA==.Dhomsak:BAAALgAFFAEJAQABLgAFFAUJEgACAD4jAA==.',
Di='Diamonds:BAAALgADCgEJAQAAAA==.Dirtyeclipse:BAAALgADCgYJBQAAAA==.Dirtytotemz:BAAALgADCgEJAQAAAA==.Disc:BAAALgADCgUJBQAAAA==.',
Dk='Dkchin:BAAALgADCgEJAQAAAA==.',
Do='Doadin:BAABLgAECn8sAAMRAAkJoBvCDQCqAgARAAkJoBvCDQCqAgAKAAEJ1gHBXQEgAAAAAA==.Doominatrix:BAACLgAFFH8FAAMHAAIJGwfafQCBAAAHAAIJGwfafQCBAAAGAAEJAwbDFABAAAAuAAQKfy0AAwcACAmGFVI7AK4BAAcABwmGFVI7AK4BAAYAAQkAAKQqAEoAAAAA.',
Dr='Draggum:BAABLgAECn8bAAMFAAgJDxn5FADnAQAFAAgJDxn5FADnAQAEAAMJpxD+IACgAAABLgAECgcJIAACAPAaAA==.Dreadraven:BAABLgAECn9IAAMPAAgJYhWXJgAmAgAPAAgJYhWXJgAmAgAdAAEJZQRSWAAjAAAAAA==.Dreckt:BAAALgAECgEJAQAAAA==.Drecktina:BAABLgAECn8gAAMBAAgJgBRuIQCxAQABAAcJFRVuIQCxAQAgAAgJhBBvSQBaAQABLgAECgEJAQAQAAAAAA==.Dreddstorm:BAAALgAECgEJAgAAAA==.Drewuw:BAABLgAECn8bAAIhAAkJwBaOGQAVAgAhAAkJwBaOGQAVAgAAAA==.Druidhams:BAACLgAFFH8HAAIiAAIJGBHrOgCFAAAiAAIJGBHrOgCFAAAuAAQKfzAAAiIACQmrHXQLAMkCACIACQmrHXQLAMkCAAAA.',
Ea='Eamon:BAAALgAECgQJBAABLgAECgkJNwAjAOMeAA==.',
Ei='Eightball:BAAALgADCgUJBQAAAA==.',
El='Elderp:BAAALgAECgYJDQAAAA==.Eline:BAAALgAECgUJBgAAAA==.Elisha:BAACLgAFFH8QAAIKAAQJhAK0OwD2AAAKAAQJhAK0OwD2AAAuAAQKfzwAAgoACQnOFlQoABgCAAoACQnOFlQoABgCAAAA.Elsyra:BAAALgAECgYJCQAAAA==.',
Er='Erebostro:BAABLgAECn8tAAISAAkJYBi6HgAgAgASAAkJYBi6HgAgAgAAAA==.',
Ev='Everclear:BAAALgAECggJDAABLgAFFAIJBwAVAPMMAA==.Evillux:BAACLgAFFH8FAAMHAAIJbQXngAB0AAAHAAIJbQXngAB0AAAIAAEJZAD6HQAkAAAuAAQKfy8AAwcACQm0EFI0AMgBAAcACQlGEFI0AMgBAAgABQnmDH0qABcBAAAA.',
Ey='Eyeguy:BAABLgAECn8VAAMgAAkJHxyYJwBmAgAgAAkJLBmYJwBmAgABAAQJ+h+0NgAsAQAAAA==.',
Fa='Fathercow:BAACLgAFFH8HAAIjAAIJLSPKIADIAAAjAAIJLSPKIADIAAAuAAQKfyYAAiMACQkUH3IEAAoDACMACQkUH3IEAAoDAAAA.',
Fi='Fingies:BAACLgAFFH8MAAMHAAQJrRYKKQBAAQAHAAQJrRYKKQBAAQAGAAEJ6gWpFABBAAAuAAQKfz0AAwcACQmhJKEIAOICAAcABwknJaEIAOICAAgABQmyHkoVAJ8BAAAA.Fistin:BAAALgAECgUJBgAAAA==.',
Fr='Frieren:BAAALgADCgYJBgAAAA==.',
Fu='Furina:BAAALgAECgQJBgAAAA==.',
['Fë']='Fënn:BAACLgAFFH8HAAISAAIJah5VRACtAAASAAIJah5VRACtAAAuAAQKfy8AAxIACQlvIfsGAO0CABIACQlvIfsGAO0CACQABQmiDXotAOAAAAAA.',
Ga='Gaijin:BAAALgADCgMJAwABLgAECgkJNwAjAOMeAA==.Galaxsea:BAABLgAECn8WAAIhAAgJQR2KDgARAgAhAAgJQR2KDgARAgAAAA==.',
Ge='Gerthquake:BAABLgAECn8hAAMbAAkJzRkmDABYAgAbAAkJzRkmDABYAgAaAAYJkB/BJgD4AQAAAA==.',
Gf='Gfour:BAABLgAECn8eAAIXAAgJAxx2EwAvAgAXAAgJAxx2EwAvAgAAAA==.',
Gh='Ghoul:BAAALgAECgYJDwAAAA==.Ghraxxy:BAAALgAECggJCAAAAA==.',
Gi='Gideonn:BAAALgADCgcJDQAAAA==.',
Go='Gobø:BAAALgAECgYJDAAAAA==.Goodytwoshoe:BAAALgAECgIJBwAAAA==.',
Gr='Grimmreefer:BAAALgAECgQJBAAAAA==.Grindlemorph:BAAALgAECgEJAQAAAA==.Grove:BAAALgAECgcJDQAAAA==.Grïllidan:BAAALgAECgQJCgAAAA==.',
['Gâ']='Gâlvatron:BAAALgADCgEJAQAAAA==.',
Ha='Hakz:BAAALgADCgkJCQAAAA==.',
He='Heart:BAAALgAFFAIJBAABLgAFFAMJBwAfAM4XAA==.Help:BAAALgADCgEJAQAAAA==.',
Ho='Homlock:BAAALgAECgYJEAABLgAFFAUJEgACAD4jAA==.Homsorc:BAACLgAFFH8SAAMCAAUJPiPiBwDlAQACAAUJPiPiBwDlAQADAAEJByRBAgBoAAAuAAQKfyMAAgIACQlLJTMFAK8DAAIACQlLJTMFAK8DAAAA.Homtard:BAABLgAFFH8OAAMTAAYJWyNbBQCqAQATAAYJiyJbBQCqAQAkAAQJxRjKCQBSAQABLgAFFAUJEgACAD4jAA==.Hope:BAABLgAECn8zAAMRAAkJVhuFCwCMAgARAAkJVhuFCwCMAgAKAAQJ5wcpxACxAAAAAA==.',
Id='Idun:BAAALgAECgUJBQAAAA==.',
Il='Illiandray:BAABLgAECn8yAAMIAAkJyx0xAQCiAgAIAAkJyx0xAQCiAgAHAAgJUAoAbgAiAQAAAA==.Ilswyn:BAAALgADCgUJBQABLgAECgkJJwAgAN8jAA==.',
Im='Imu:BAACLgAFFH8JAAMkAAMJoCGSDwAYAQAkAAMJoCGSDwAYAQASAAEJxhmIWwBWAAAuAAQKfyIABCQABwkOJVEHAHICACQABwkOJVEHAHICABMABQk/DfFUAPYAABIAAgmLCs6nAHYAAAEuAAUUBQkWAAoA5SUA.',
In='Incante:BAAALgAECgMJAwAAAA==.Insomniac:BAABLgAECn8nAAIgAAkJ3yPiAwAiAwAgAAkJ3yPiAwAiAwAAAA==.',
Io='Ionise:BAABLgAECn8kAAIFAAkJKRvtCQB4AgAFAAkJKRvtCQB4AgAAAA==.Ioniz:BAAALgADCgkJCQAAAA==.',
Is='Iskgard:BAAALgAECgcJBwAAAA==.Isklar:BAACLgAFFH8JAAIUAAIJJByDGgCoAAAUAAIJJByDGgCoAAAuAAQKfy8AAhQACAm4I4UEAAIDABQACAm4I4UEAAIDAAAA.',
Ja='Jahodre:BAAALgADCggJEQAAAA==.Jangles:BAABLgAECn8eAAQFAAcJiRucGgCwAQAFAAcJiRucGgCwAQAJAAMJixeVDwDLAAAEAAMJbwy0OQCdAAAAAA==.',
Je='Jer:BAABLgAECn8cAAILAAkJ1RAyFABzAgALAAkJ1RAyFABzAgAAAA==.',
Ju='Jugernat:BAAALgADCgEJAQAAAA==.',
Jy='Jynn:BAAALgAECgEJAQABLgAECgkJNwAjAOMeAA==.',
Ka='Kairi:BAAALgAECgYJCAAAAA==.Kammo:BAACLgAFFH8PAAIYAAQJxiDvFACgAQAYAAQJxiDvFACgAQAuAAQKfz8AAhgACQkAJvsBAGUDABgACQkAJvsBAGUDAAAA.Kazypher:BAAALgAECgMJBwAAAA==.',
Ke='Keeah:BAAALgAECgQJCAAAAA==.Keel:BAAALgADCgYJBgAAAA==.Kestra:BAABLgAECn8aAAIXAAkJCgfzMQAvAQAXAAkJCgfzMQAvAQAAAA==.Keyalordil:BAAALgADCgEJAQAAAA==.',
Ki='Kilma:BAAALgADCgIJAgABLgAECgkJNwAjAOMeAA==.Kiwi:BAAALgAECgcJBwAAAA==.',
Kl='Klingnor:BAAALgADCgEJAQAAAA==.',
Ko='Konico:BAAALgAECgYJDQAAAA==.',
Kr='Kravensteak:BAACLgAFFH8PAAITAAUJ2BvlCQBIAQATAAUJ2BvlCQBIAQAuAAQKfx0AAhMABwnLIbEYAGYCABMABwnLIbEYAGYCAAAA.',
Ku='Kungfopanda:BAAALgAECgEJAQAAAA==.',
Kw='Kwikin:BAABLgAECn8gAAICAAcJ8BqMVQA3AgACAAcJ8BqMVQA3AgAAAA==.',
Ky='Kyreen:BAABLgAECn8YAAISAAcJMArVYQAlAQASAAcJMArVYQAlAQAAAA==.',
['Kä']='Kärl:BAAALgADCgcJCAABLgAECggJFgAhAEEdAA==.',
La='Laaz:BAACLgAFFH8HAAIgAAIJfAaoXgB9AAAgAAIJfAaoXgB9AAAuAAQKfzUAAiAACQkyE+0oAN4BACAACQkyE+0oAN4BAAAA.Lamalen:BAABLgAECn8UAAIKAAcJnxoSYQDBAQAKAAcJnxoSYQDBAQAAAA==.Lasercow:BAAALgAECgcJCAABLgAFFAIJBwAjAC0jAA==.',
Le='Lestatt:BAAALgAECgYJBwAAAA==.Leyah:BAAALgADCgQJBAAAAA==.',
Li='Liena:BAAALgADCgIJAgAAAA==.Linthvia:BAAALgAECgQJBQAAAA==.Lioneyes:BAAALgAECgcJDQAAAA==.Lirael:BAAALgAECgEJAQAAAA==.',
Lo='Locknloaded:BAAALgAECgQJBQAAAA==.',
Lu='Luciuos:BAABLgAECn8XAAMiAAgJ3gF4fwB2AAAiAAcJ9QF4fwB2AAAlAAgJBgF+VQBgAAAAAA==.Lucreesha:BAAALgAECgUJBQABLgAECgkJGwAhAMAWAA==.Lukafox:BAACLgAFFH8VAAIaAAYJ3hzIBQDvAQAaAAYJ3hzIBQDvAQAuAAQKfyAAAxoACQlZH6gHAPoCABoACQlZH6gHAPoCABsAAQmKAn6WAB0AAAAA.Lunastarvale:BAABLgAECn8yAAISAAkJURviEwBpAgASAAkJURviEwBpAgAAAA==.Luscinia:BAAALgADCgEJAQAAAA==.',
Ma='Madith:BAACLgAFFH8GAAIgAAMJtxG7PgDhAAAgAAMJtxG7PgDhAAAuAAQKfxwAAiAACAnOHOEaADACACAACAnOHOEaADACAAAA.Magicjamo:BAAALgAECgUJBQAAAA==.Maleficênt:BAAALgAECggJDgABLgAFFAIJBwAmACAJAA==.Malefisico:BAABLgAECn8YAAMHAAgJxRDFbQCFAQAHAAgJxRDFbQCFAQAIAAEJAACKeAArAAAAAA==.Malgarok:BAABLgAECn8lAAIHAAgJWBygHgCfAgAHAAgJWBygHgCfAgABLgAECgYJEAAQAAAAAA==.Mardríft:BAACLgAFFH8FAAIlAAMJWQyrIgC0AAAlAAMJWQyrIgC0AAAuAAQKfzoAAiUACQnYIR8FAM0CACUACQnYIR8FAM0CAAAA.Mazga:BAABLgAECn8rAAInAAgJnhZ8CQDAAQAnAAgJnhZ8CQDAAQAAAA==.',
Me='Mechamon:BAAALgADCgEJAQAAAA==.Melee:BAABLgAECn8tAAIkAAgJ0RiFDQALAgAkAAgJ0RiFDQALAgAAAA==.Mesothorny:BAAALgADCgQJBAAAAA==.Metrom:BAAALgAECgQJBAAAAA==.Mezoti:BAABLgAECn8UAAMFAAgJlQ7VIwBrAQAFAAgJlQ7VIwBrAQAEAAgJwAgCEwBNAQAAAA==.',
Mi='Mick:BAAALgAECgMJAwAAAA==.Milarky:BAAALgADCgkJDgAAAA==.',
Mo='Moji:BAABLgAECn8rAAIXAAkJYhl1DABtAgAXAAkJYhl1DABtAgAAAA==.Monstermayi:BAACLgAFFH8HAAIPAAIJ8QwTLACUAAAPAAIJ8QwTLACUAAAuAAQKfyoAAg8ACQnQFmsSABYCAA8ACQnQFmsSABYCAAAA.Mooknight:BAABLgAECn8tAAIUAAkJThOvDgDJAQAUAAkJThOvDgDJAQAAAA==.Mordread:BAAALgADCgQJBQAAAA==.Moyapanda:BAABLgAECn8nAAIhAAgJXBq7EgDaAQAhAAgJXBq7EgDaAQAAAA==.',
Mu='Muggy:BAABLgAECn8nAAIMAAgJtREYBwChAQAMAAgJtREYBwChAQAAAA==.',
My='Myluutarania:BAAALgAECgcJCwAAAA==.Myrothar:BAAALgAECgcJDQAAAA==.Mytastical:BAABLgAECn8lAAICAAgJaxZnfgDUAQACAAgJaxZnfgDUAQAAAA==.',
['Mæ']='Mæve:BAABLgAECn8uAAMiAAkJzhi/FABdAgAiAAkJzhi/FABdAgAlAAUJjREsRgAVAQAAAA==.',
['Më']='Mëgatron:BAAALgADCgEJAQAAAA==.',
Na='Namalis:BAACLgAFFH8KAAMHAAQJ6xdWLAA4AQAHAAQJmBdWLAA4AQAGAAEJ2xulDABVAAAuAAQKfxwABAcACAkTJQU5ACcCAAcABgkPJQU5ACcCAAgAAgkWIqA8AMIAAAYAAQkAADIhAG0AAAAA.Nanielito:BAABLgAECn8iAAICAAkJax6+FACmAgACAAkJax6+FACmAgAAAA==.Nastydisco:BAAALgAECgkJBQAAAA==.Nazendeseth:BAAALgAECgYJBgAAAA==.',
Ne='Neffer:BAACLgAFFH8GAAICAAMJXBXANQDAAAACAAMJXBXANQDAAAAuAAQKfyIAAgIACQlNGnE7AIkCAAIACQlNGnE7AIkCAAAA.Nevadin:BAAALgAECgYJDwAAAA==.',
No='Nokoa:BAAALgAECggJCAAAAA==.Nonae:BAABLgAECn8gAAISAAgJjh0bEgCnAgASAAgJjh0bEgCnAgAAAA==.Norivari:BAAALgADCgYJCwAAAA==.Nosliw:BAAALgADCgUJCAAAAA==.Notawarlock:BAAALgADCgMJAwAAAA==.',
Ob='Obiwon:BAAALgAECgQJBAAAAA==.',
Og='Ogsmashsauce:BAAALgAECgEJAQAAAA==.',
Om='Omegá:BAACLgAFFH8HAAIVAAIJ8wy9CgBxAAAVAAIJ8wy9CgBxAAAuAAQKfx8AAhUACQlIE1EQAGYBABUACQlIE1EQAGYBAAAA.',
Oo='Oopsalldruid:BAAALgAECgUJCAABLgAECgcJIAACAPAaAA==.',
Op='Optìmusprìme:BAABLgAECn8tAAIeAAkJkxpqCAArAgAeAAkJkxpqCAArAgAAAA==.',
Os='Osydin:BAAALgAECgYJBwAAAA==.Osyriss:BAAALgADCgYJCQAAAA==.',
Oz='Ozyknight:BAAALgAECgEJAQAAAA==.',
Pa='Papa:BAACLgAFFH8FAAMGAAIJcB/hDABVAAAHAAEJRyCagwBiAAAGAAEJmh7hDABVAAAuAAQKfzAABAgACQkdIcUCANYCAAgABwlRIcUCANYCAAYACAm5IkwBAKECAAcABQmhHG5CAJUBAAAA.Papiblanco:BAAALgAECgIJAgAAAA==.',
Pl='Planeteer:BAAALgAECgIJBAAAAA==.',
Po='Pockets:BAABLgAECn8jAAICAAgJZBakTgCtAQACAAgJZBakTgCtAQAAAA==.Porditum:BAAALgAECgUJBwAAAA==.Pouches:BAAALgAECgYJDQAAAA==.',
Pr='Pristia:BAAALgAECgYJDwAAAA==.',
Ps='Psychic:BAABLgAECn83AAMjAAkJ4x5zBgDPAgAjAAkJ4x5zBgDPAgANAAIJnBIxXQA6AAAAAA==.',
Pu='Puddingchan:BAAALgAECgQJBAAAAA==.Purge:BAAALgAECgYJEAAAAA==.',
Qu='Quick:BAAALgAECgEJAgABLgAECgcJIAACAPAaAA==.',
Ra='Raelz:BAAALgAECgIJAwAAAA==.Rahuun:BAAALgAECgkJCAAAAA==.Raithfist:BAAALgADCgMJAwAAAA==.Rakhan:BAAALgADCgUJBQAAAA==.Rangedrhett:BAAALgADCgEJAQAAAA==.Ratha:BAACLgAFFH8HAAIVAAIJnBVoCQCLAAAVAAIJnBVoCQCLAAAuAAQKfzAAAxUACQmqGakLALQBABUACQmqGakLALQBAAoABAkVDLLRAJwAAAAA.Ravener:BAAALgAECgYJBwAAAA==.Razeal:BAABLgAECn8YAAMKAAYJjx+pSACjAQAKAAYJOR+pSACjAQAVAAIJKxjiMQCGAAAAAA==.',
Re='Reaper:BAACLgAFFH8GAAIYAAIJ9iO3cADOAAAYAAIJ9iO3cADOAAAuAAQKfxkAAxgABwkHJQcjADMCABgABwkHJQcjADMCABQAAgk+B+BAAEkAAAEuAAUUAwkHAB8AzhcA.Reeb:BAAALgAECgUJBgAAAA==.Remura:BAAALgAECgcJEgAAAA==.',
Ri='Rick:BAAALgADCgkJEAAAAA==.Rixxs:BAAALgADCgcJBwAAAA==.',
Ro='Robynhood:BAAALgADCgkJCQAAAA==.Roguechin:BAACLgAFFH8UAAMLAAUJtiNrCAB7AQALAAUJtiNrCAB7AQAMAAEJzQ77BQBeAAAuAAQKfysAAwsACQlIJVEEALYCAAsACAnGJVEEALYCAAwAAwnpI/4NADoBAAAA.Rokkgar:BAABLgAECn8fAAIbAAcJiw2GNAAOAQAbAAcJiw2GNAAOAQAAAA==.Roosterr:BAAALgADCgkJFgAAAA==.',
Ru='Ruwazi:BAAALgAECgYJDwAAAA==.',
Ry='Ryujin:BAAALgAECgEJAQAAAA==.',
Sa='Samael:BAAALgAECgUJCgAAAA==.',
Sc='Scottamus:BAAALgAFFAMJAwAAAA==.',
Se='Secarious:BAABLgAECn8bAAIPAAgJnhC8IgCOAQAPAAgJnhC8IgCOAQAAAA==.Sehnsucht:BAACLgAFFH8HAAMlAAMJWBHyHQDbAAAlAAMJWBHyHQDbAAAiAAMJMArVMQCtAAAuAAQKfygAAyIACQktHAkeAE4CACIACQktHAkeAE4CACUAAQkAGqB2AEkAAAAA.Serius:BAAALgAECgQJBAABLgAECgkJGwAhAMAWAA==.',
Sh='Shmadu:BAAALgAECgcJCwAAAA==.Shockk:BAABLgAECn8gAAMbAAkJGBapGwCvAQAbAAkJGBapGwCvAQAaAAMJ4AKOigBpAAAAAA==.',
Si='Siovhan:BAAALgAECggJEAAAAA==.',
Sl='Sly:BAABLgAFFH8HAAIfAAMJzheOBAAHAQAfAAMJzheOBAAHAQAAAA==.',
Sm='Smóóthbói:BAABLgAECn8jAAICAAgJVxQmTwCsAQACAAgJVxQmTwCsAQAAAA==.',
So='Sohei:BAAALgADCgEJAQAAAA==.Sona:BAABLgAECn8uAAIFAAkJSBTrEwDyAQAFAAkJSBTrEwDyAQAAAA==.Soola:BAABLgAECn8fAAMaAAgJoQ1yNgB4AQAaAAgJoQ1yNgB4AQAbAAQJzAziWAB/AAAAAA==.',
Sp='Spoopadin:BAAALgAECgIJBgAAAA==.Spoopymage:BAAALgAECgEJAQAAAA==.',
St='Stack:BAABLgAFFH8GAAIkAAIJORaEFwC9AAAkAAIJORaEFwC9AAABLgAFFAMJBwAfAM4XAA==.Stompycouch:BAACLgAFFH8FAAIbAAIJJRG6KgCNAAAbAAIJJRG6KgCNAAAuAAQKfysAAhsACAnyHFkVAOoBABsACAnyHFkVAOoBAAAA.Stoned:BAABLgAECn8nAAMRAAkJJh/uCADhAgARAAkJJh/uCADhAgAKAAMJ3wp/0wCaAAAAAA==.Stonedpriest:BAABLgAECn8oAAIZAAkJliA7BwDYAgAZAAkJliA7BwDYAgAAAA==.Stripes:BAAALgADCgUJBQAAAA==.',
Su='Sunreaver:BAABLgAECn8tAAIYAAkJcyMRCgDoAgAYAAkJcyMRCgDoAgAAAA==.Surrëal:BAAALgAECgkJCQABLgAECgkJLgASAF8PAA==.Surtain:BAABLgAECn8fAAIlAAgJOR4HDQA4AgAlAAgJOR4HDQA4AgAAAA==.',
Sw='Sweetmask:BAABLgAECn8bAAIYAAYJrSS3OQDTAQAYAAYJrSS3OQDTAQAAAA==.',
Sx='Sxv:BAAALgAFFAEJAQAAAA==.',
Sy='Syl:BAACLgAFFH8FAAISAAIJJxr3RgCmAAASAAIJJxr3RgCmAAAuAAQKfygAAxIACQn+GacWAFQCABIACQniGacWAFQCABMABQlVCnFZAN8AAAAA.Sylvanäs:BAAALgADCgkJEQABLgAECgkJMgAIAMsdAA==.',
Ta='Tahitian:BAABLgAECn8eAAISAAkJ9w54KgDjAQASAAkJ9w54KgDjAQAAAA==.Tahlreth:BAABLgAECn8qAAICAAkJOBztGgB/AgACAAkJOBztGgB/AgAAAA==.Tanickz:BAABLgAECn8dAAICAAkJCw3RSAC9AQACAAkJCw3RSAC9AQAAAA==.Tanidge:BAAALgADCgEJAQABLgAECgkJLAAbAPscAA==.Tanidgetotem:BAABLgAECn8sAAIbAAkJ+xz8CQD0AgAbAAkJ+xz8CQD0AgAAAA==.Tanya:BAACLgAFFH8NAAIkAAQJxRBvCwBHAQAkAAQJxRBvCwBHAQAuAAQKfzsAAiQACQmyHVcFAJsCACQACQmyHVcFAJsCAAAA.Tayanna:BAAALgAECgYJEgAAAA==.',
Te='Teias:BAACLgAFFH8HAAIZAAIJQyH5FQC8AAAZAAIJQyH5FQC8AAAuAAQKfzAAAxkACQnOGBQTAEcCABkACQnOGBQTAEcCAA0ABgkCHbYZAKUBAAAA.Tersus:BAAALgAECgYJDQAAAA==.',
Th='Thuras:BAAALgADCgUJBQAAAA==.',
Ti='Tidalwaveikz:BAAALgAECgQJCAAAAA==.Timonator:BAAALgADCgQJBAAAAA==.Tirence:BAABLgAECn8fAAICAAgJOx/BKAA1AgACAAgJOx/BKAA1AgAAAA==.',
To='Toriell:BAAALgADCgEJAQAAAA==.Torvald:BAAALgADCgEJAQABLgADCgUJCAAQAAAAAA==.',
Tr='Tricko:BAABLgAECn8yAAISAAgJaR/RGABEAgASAAgJaR/RGABEAgAAAA==.Trollskingx:BAAALgAECgcJEQAAAA==.Trollzy:BAABLgAECn8tAAMnAAkJoiDVAQDXAgAnAAkJoiDVAQDXAgAaAAEJhgMupgApAAAAAA==.Trunkmonkey:BAABLgAECn8lAAIHAAgJaxIUPgCkAQAHAAgJaxIUPgCkAQAAAA==.',
Ts='Tsaagan:BAACLgAFFH8HAAMHAAIJNxt7ZACoAAAHAAIJSxp7ZACoAAAGAAEJmxKgDwBQAAAuAAQKfygABAcACQnJIIsNAK0CAAcACQkvHosNAK0CAAYABAn/Iv4KAIwBAAgABAkHHrQgAE4BAAAA.',
Tu='Tucker:BAABLgAECn8jAAIXAAkJ7xi4CwB5AgAXAAkJ7xi4CwB5AgAAAA==.',
Ty='Tychus:BAAALgAECgUJCwAAAA==.',
Ul='Ultramagnús:BAAALgADCgEJAQAAAA==.Ultramiami:BAAALgADCgEJAQAAAA==.',
Un='Unbroken:BAABLgAECn8VAAIYAAYJoA+3gQAWAQAYAAYJoA+3gQAWAQAAAA==.Under:BAAALgADCgcJDgABLgAECgYJFQAYAKAPAA==.Unparalleled:BAABLgAECn8cAAMJAAYJZAqTDQDuAAAJAAUJZAqTDQDuAAAEAAYJogfrHQDBAAAAAA==.',
Va='Valkyruid:BAACLgAFFH8QAAIiAAUJ4BGMFQBPAQAiAAUJ4BGMFQBPAQAuAAQKfxcAAiIABwnCF4w2AM0BACIABwnCF4w2AM0BAAAA.',
Ve='Vessel:BAAALgAECgQJBAABLgAFFAMJBwAfAM4XAA==.',
Vi='Vixus:BAAALgAECgYJEAAAAA==.',
Vx='Vxs:BAAALgAFFAEJAQAAAA==.',
['Vø']='Vøødu:BAAALgAECgUJBQABLgAECgcJGAAaAJEQAA==.',
Wa='Walshidan:BAABLgAECn8aAAIgAAkJ0BCbOgCQAQAgAAkJ0BCbOgCQAQAAAA==.Waywatcher:BAAALgAECgUJCAAAAA==.',
We='Wenus:BAAALgAECgUJBQAAAA==.',
Wi='Wiccaflame:BAABLgAECn8aAAICAAgJYCGAGACOAgACAAgJYCGAGACOAgAAAA==.Wiccasham:BAAALgAECgEJAQAAAA==.',
Wu='Wullgan:BAAALgAECgkJEQAAAA==.',
Xe='Xelaheal:BAAALgAECgEJAQAAAA==.Xencure:BAABLgAFFH8FAAIEAAIJNBClGwB7AAAEAAIJNBClGwB7AAAAAA==.',
Xo='Xole:BAABLgAECn8cAAMgAAgJpxTZbQBaAQAgAAgJpxTZbQBaAQAOAAQJIQSEIQB3AAAAAA==.',
Xy='Xybos:BAABLgAECn8ZAAIgAAkJnRuTMAA5AgAgAAkJnRuTMAA5AgABLgAECgkJGwAhAMAWAA==.Xyrna:BAAALgADCgYJBgABLgAFFAIJBwAVAJwVAA==.',
Ya='Yareli:BAABLgAECn8gAAIOAAgJawVwEADyAAAOAAgJawVwEADyAAAAAA==.Yawa:BAAALgAFFAEJAgAAAA==.',
Ye='Yeet:BAAALgAECgYJEQAAAA==.',
Yu='Yunara:BAAALgADCgcJBQAAAA==.',
Za='Zaezar:BAAALgADCgYJBgABLgAECgcJEQAQAAAAAA==.Zarill:BAAALgADCgcJBwAAAA==.Zartman:BAAALgADCgEJAQAAAA==.Zayzoo:BAAALgAECgQJBAAAAA==.Zazie:BAAALgAECgYJCQAAAA==.',
Ze='Zekröm:BAACLgAFFH8HAAImAAIJIAmeEwBiAAAmAAIJIAmeEwBiAAAuAAQKfx4AAiYACQkyEkQMALIBACYACQkyEkQMALIBAAAA.Zekrøm:BAABLgAECn8dAAIbAAgJjxrvGQBEAgAbAAgJjxrvGQBEAgABLgAFFAIJBwAmACAJAA==.Zeno:BAACLgAFFH8bAAIKAAgJrR1KAQBzAgAKAAgJrR1KAQBzAgAuAAQKfxYAAgoACQkyJfgCAKcDAAoACQkyJfgCAKcDAAAA.Zeraprywin:BAAALgAECgEJAQAAAA==.Zetetic:BAAALgADCgkJCQAAAA==.Zezer:BAAALgAECgMJBAABLgAECgcJEQAQAAAAAA==.Zezlock:BAAALgAECgYJEQABLgAECgcJEQAQAAAAAA==.Zezz:BAAALgAECgcJEQAAAA==.',
Zg='Zgystrdst:BAABLgAECn8fAAIMAAcJ5ws4CwA5AQAMAAcJ5ws4CwA5AQABLgAECgcJHwAbAIsNAA==.',
Zi='Zinbar:BAAALgAECgcJDQAAAA==.',
Zj='Zjaros:BAAALgAECgYJCQAAAA==.',
Zu='Zune:BAABLgAECn8YAAQhAAgJ+xnOEADyAQAhAAgJyBnOEADyAQAWAAQJ9BVWVADzAAAXAAEJTQJtcwAfAAAAAA==.',
['Zê']='Zêz:BAAALgADCgUJBQABLgAECgcJEQAQAAAAAA==.',
['Çl']='Çloud:BAABLgAECn8UAAICAAgJXCBkLwC1AgACAAgJXCBkLwC1AgAAAA==.Çløud:BAAALgADCgUJBQAAAA==.',
['Çu']='Çup:BAABLgAECn8qAAQjAAgJ2yGvCACZAgAjAAgJ2yGvCACZAgAZAAUJABoGOwBPAQANAAEJBhinWQBFAAAAAA==.',
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
