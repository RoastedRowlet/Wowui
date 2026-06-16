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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Priest-Discipline','Paladin-Holy','Mage-Fire','Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Mage-Frost','DemonHunter-Havoc','Warrior-Arms','Priest-Holy','Druid-Restoration','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','Warrior-Protection','Shaman-Enhancement','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCggJFAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allesar:BAAALgAECgUJBQAAAA==.Allila:BAABLgAECn8eAAIBAAgJghylFQAeAgABAAgJghylFQAeAgAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.',
Am='Ambrozyn:BAAALgAECgYJCgAAAA==.',
An='Andrew:BAAALgAECgYJCgAAAA==.Anik:BAAALgAECgYJBwAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgACAKoQAA==.Anna:BAABLgAFFH8LAAIBAAUJPBxBEgBQAQABAAUJPBxBEgBQAQAAAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAAALgAECgYJEAABLgAECggJLAADAH8DAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAABLgAECn8XAAIEAAgJdAtwOQBfAQAEAAgJdAtwOQBfAQAAAA==.Arieljoyeria:BAACLgAFFH8PAAMFAAUJMh3ZAwBVAQAFAAQJ4B7ZAwBVAQAGAAMJLxlYFACtAAAuAAQKfyQAAwYACQmZH+MNAMACAAYACQkfHuMNAMACAAUABAkqGMARAAYBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAHANgQAA==.',
As='Ashog:BAAALgAECgIJAgAAAA==.Astar:BAAALgADCgcJDgABLgAFFAMJBQAIALkaAA==.Astraea:BAABLgAECn88AAIJAAgJDB4YCQBWAgAJAAgJDB4YCQBWAgABLgAECgkJPAAHAFMiAA==.',
At='Athika:BAAALgADCgcJCgAAAA==.',
Au='Auddorn:BAAALgAECgUJCQAAAA==.Auria:BAABLgAECn8aAAIKAAgJ8RyHDACiAgAKAAgJ8RyHDACiAgAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAACLgAFFH8IAAIBAAMJ8Ae7KACwAAABAAMJ8Ae7KACwAAAuAAQKfyEAAgEACAnXC0IoAJcBAAEACAnXC0IoAJcBAAAA.Azend:BAAALgAECgIJAgAAAA==.Azphrodite:BAAALgAECgYJBgAAAA==.Azralia:BAABLgAECn8dAAILAAkJpxVtGgAvAgALAAkJpxVtGgAvAgAAAA==.',
Ba='Barthamus:BAAALgADCgYJBgAAAA==.',
Bb='Bbygee:BAAALgAECgYJEAAAAA==.',
Be='Beastlegion:BAAALgADCgMJAgAAAA==.Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgcJEwAAAA==.Benjaminadin:BAAALgAECgUJEQAAAA==.Berris:BAAALgADCgUJBQAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8+AAIMAAkJJAzxBACMAQAMAAkJJAzxBACMAQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAABLgAECn8cAAQNAAkJUxeNMQBtAQANAAcJShSNMQBtAQAIAAcJiwpaKgAfAQAOAAEJsiAKHQBiAAAAAA==.Boop:BAAALgADCgkJCQABLgAECgkJIwAPAKAjAA==.Borgin:BAABLgAECn8VAAICAAYJ3QYXtADWAAACAAYJ3QYXtADWAAAAAA==.Borimor:BAABLgAECn8fAAIPAAcJcAwLpAAuAQAPAAcJcAwLpAAuAQABLgAECgkJFgACAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAABLgAECn8dAAMQAAYJwhE7OQAVAQAQAAYJwhE7OQAVAQARAAEJuAMHiQAmAAABLgAECgkJQAASAPocAA==.Bridgetta:BAAALgAECgIJAgAAAA==.Brisli:BAAALgADCgcJBwABLgAECggJGgAKAPEcAA==.Briëlla:BAABLgAECn9AAAQSAAkJ+hwGGQCuAgASAAkJ+hwGGQCuAgATAAEJDQgSPwAmAAAUAAEJOgPmagATAAAAAA==.Bromdrago:BAAALgAECgEJAQAAAA==.Bromkin:BAABLgAECn8VAAIVAAYJVBlAGABYAQAVAAYJVBlAGABYAQAAAA==.',
['Bë']='Bëorn:BAAALgAECgUJBQABLgAECgkJFgACAKoQAA==.',
Ca='Calindala:BAAALgADCggJBAAAAA==.Calinor:BAAALgAECgQJDgAAAA==.Carl:BAAALgAECgYJCQAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAABLgAECn8aAAIWAAYJCQeG8AAZAQAWAAYJCQeG8AAZAQAAAA==.',
Ce='Ceran:BAABLgAECn8rAAIXAAkJhRISFgDVAQAXAAkJhRISFgDVAQAAAA==.Cereus:BAACLgAFFH8FAAMIAAMJuRo/GgDoAAAIAAMJuRo/GgDoAAAOAAIJpwzGCQCHAAAuAAQKfzMAAwgACQlcH/ACACYDAAgACQlcH/ACACYDAA4ACQktG9QCAH4CAAAA.',
Ch='Chaelenge:BAABLgAECn8lAAMLAAkJSh4wCAAGAwALAAkJSh4wCAAGAwAPAAMJpQkTUgFZAAAAAA==.Cheatt:BAAALgAECgEJAQAAAA==.Chubbabuns:BAABLgAECn8xAAMYAAkJ1yTCAgASAwAYAAkJ/yPCAgASAwAEAAYJ2yPqMwB6AQAAAA==.Chyran:BAAALgAECggJCQAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8lAAIZAAkJ4RjyEwA1AgAZAAkJ4RjyEwA1AgAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAFFAIJAgAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.Cutecop:BAAALgAECgIJAgAAAA==.',
['Cò']='Còffee:BAAALgADCgkJCQABLgAECgcJFQAQAP0gAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCgYJEQAAAA==.Dalielah:BAAALgAECgQJBgAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.Darkkstarr:BAAALgADCgUJCAAAAA==.Daromiciah:BAAALgADCgEJAQAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Demdots:BAAALgADCgEJAQAAAA==.Denvoker:BAAALgAECgYJEwAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEQAAAA==.',
Di='Diddykong:BAAALgAECgkJCQAAAA==.Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Docqt:BAAALgADCgEJAQAAAA==.Dolleez:BAAALgAECgcJCAAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn8sAAMDAAgJfwP7VAC3AAADAAgJfwP7VAC3AAAaAAIJiAGq9QAbAAAAAA==.',
Du='Dunkaroo:BAABLgAECn8eAAIbAAkJMhQUQwC7AQAbAAkJMhQUQwC7AQAAAA==.',
['Dé']='Dékü:BAAALgAECgcJCQAAAA==.',
Ei='Eikinskaldi:BAAALgAECgEJAgAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAABLgAECn8kAAIPAAkJpQtkdACDAQAPAAkJpQtkdACDAQAAAA==.',
En='Endormu:BAAALgAECgIJAgAAAA==.',
Er='Eraessyr:BAAALgADCgcJDQAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECggJCgAAAA==.Fandris:BAAALgAECgEJAQAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgkJRwAcAOEVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fo='Forsëti:BAAALgAECgIJAgAAAA==.',
Fr='Freakadeek:BAAALgAECgMJBAABLgAECgkJFQATAGsNAA==.Frosh:BAABLgAECn8YAAMHAAgJ2BB2OACgAQAHAAgJ2BB2OACgAQAdAAMJ4h2/bQCMAAAAAA==.Frìeren:BAABLgAECn8oAAIWAAkJ1hPwUQDjAQAWAAkJ1hPwUQDjAQAAAA==.',
Fu='Fuegaluna:BAAALgADCgkJCwAAAA==.Fundetected:BAABLgAECn8rAAIbAAkJfBolHgBcAgAbAAkJfBolHgBcAgAAAA==.',
['Fâ']='Fâllenboy:BAAALgAECgMJAwAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gillarria:BAAALgAECgQJAQAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgAECgEJAQAAAA==.Grimmberly:BAAALgAECgcJDAABLgAECgkJLAAQANwWAA==.Grimmothy:BAABLgAECn8sAAIQAAkJ3BZmEgAfAgAQAAkJ3BZmEgAfAgAAAA==.Grimoire:BAAALgAECgQJBAABLgAECgkJLAAQANwWAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Guthunnel:BAABLgAECn86AAICAAkJvhLrOAD2AQACAAkJvhLrOAD2AQAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgAECgIJAgAAAA==.Hakuri:BAAALgADCgcJDwABLgAECgYJDQAeAAAAAA==.Hannibow:BAAALgAECgcJCAAAAA==.Happydru:BAAALgADCgcJDgAAAA==.',
He='Helle:BAABLgAECn8eAAQcAAkJuxS6HAAtAgAcAAkJuxS6HAAtAgAQAAYJ6Aj0TQALAQARAAEJrw1HnQAvAAAAAA==.',
Hi='Highfever:BAABLgAECn8UAAIaAAUJ3A0ycADhAAAaAAUJ3A0ycADhAAAAAA==.',
Ho='Hoawatt:BAAALgADCgEJAgAAAA==.Holynova:BAAALgADCgQJBwABLgAECgQJBAAeAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgkJMwAaAIIbAA==.Huuch:BAABLgAECn8oAAICAAkJEAt9VAChAQACAAkJEAt9VAChAQAAAA==.',
Hy='Hycinari:BAAALgAECgIJAgAAAA==.Hyperius:BAAALgAECgUJBQAAAA==.',
Ic='Icrucify:BAACLgAFFH8FAAICAAMJ6RwlFQCwAAACAAMJ6RwlFQCwAAAuAAQKfzkAAgIACQmgJdAHABsDAAIACQmgJdAHABsDAAAA.',
Ig='Ignee:BAABLgAFFH8FAAMfAAMJRBMRHwCXAAAEAAMJpAQjPQCsAAAfAAIJnBgRHwCXAAAAAA==.Ignia:BAAALgAECgEJAQABLgAECggJCgAeAAAAAA==.',
Il='Ilanos:BAAALgAECgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAeAAAAAA==.',
Ir='Iremoon:BAABLgAECn88AAMSAAkJkxXENQAlAgASAAkJkxXENQAlAgAUAAIJRwQTQgBCAAABLgAECgkJQQAPAJoXAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.Jaeler:BAAALgAECgIJAgAAAA==.',
Je='Jedistang:BAAALgAECgQJBAAAAA==.Jestyr:BAACLgAFFH8NAAIXAAQJaRjzDAA9AQAXAAQJaRjzDAA9AQAuAAQKfxYAAxcACQlUHzMGANMCABcACQlUHzMGANMCABsAAQmBB2IjASUAAAAA.Jestyrd:BAAALgAECgMJAwABLgAFFAQJDQAXAGkYAA==.Jestyrdk:BAAALgAECgUJBQABLgAFFAQJDQAXAGkYAA==.Jestyrmo:BAABLgAECn8rAAMQAAgJARv5JACDAQAQAAcJ2Bn5JACDAQAcAAgJgBAuQwBYAQABLgAFFAQJDQAXAGkYAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8YAAIRAAQJhR5QCwBnAQARAAQJhR5QCwBnAQAuAAQKf0wAAxEACQnwJIoCAEEDABEACQnwJIoCAEEDABwAAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJEwAAAA==.',
Ju='Jules:BAAALgAFFAIJAgAAAA==.Jumbo:BAAALgAECgMJBAAAAA==.',
Ka='Kaceya:BAAALgAECgUJDQAAAA==.Kainarasa:BAAALgAECgYJEwABLgAECgkJIwAPAKAjAA==.Kairnei:BAAALgADCgYJBgAAAA==.Katarinea:BAABLgAECn8fAAIDAAkJiw6XKQCCAQADAAkJiw6XKQCCAQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Ke='Keats:BAAALgAECgIJAgAAAA==.',
Kh='Khalessie:BAABLgAECn8lAAIKAAkJOQ1uIgC4AQAKAAkJOQ1uIgC4AQAAAA==.Kheldar:BAAALgAECgcJAQAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMgAAkJpB4WCABCAgAgAAkJpB4WCABCAgAHAAEJeQEY8gAZAAAAAA==.Kiselle:BAAALgAECgQJBAABLgAECggJGgAKAPEcAA==.',
Ko='Korkneelious:BAAALgAECgYJDAAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Kw='Kwai:BAAALgAECgYJBgABLgAECgkJFgACAKoQAA==.',
Ky='Kyomu:BAAALgADCggJCAABLgAECgkJIwAPAKAjAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn82AAIEAAYJnhs5LgCXAQAEAAYJnhs5LgCXAQAAAA==.Liths:BAABLgAECn87AAIhAAkJlAkAEQA4AQAhAAkJlAkAEQA4AQAAAA==.Littlemoses:BAABLgAECn8lAAICAAgJqxvjLQAhAgACAAgJqxvjLQAhAgAAAA==.',
Lo='Lockdarkly:BAAALgAECgQJCAAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAABLgAECn8VAAMKAAYJIxXVKACKAQAKAAYJIxXVKACKAQAZAAUJZwk5UwDqAAAAAA==.Lulzimadrood:BAAALgADCgMJAwAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJEQAeAAAAAA==.Malendren:BAAALgAECgEJAQAAAA==.Malignus:BAABLgAECn8qAAIWAAkJIBaXPQAiAgAWAAkJIBaXPQAiAgABLgADCgkJFwAeAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECgkJJwAWAAIdAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgcJCwAAAA==.Mavane:BAAALgADCgUJAQAAAA==.',
Mc='Mcdavé:BAABLgAECn88AAIdAAkJyxDWJgCxAQAdAAkJyxDWJgCxAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECggJHgABAIIcAA==.Meerclar:BAAALgAECgIJAwABLgAECgUJCgAeAAAAAA==.Melaila:BAABLgAECn88AAIHAAkJUyKVDgDcAgAHAAkJUyKVDgDcAgAAAA==.Mellwynn:BAAALgAECgQJBgAAAA==.Melunaura:BAAALgAECggJCAABLgAECgkJPAAHAFMiAA==.',
Mf='Mf:BAABLgAECn8gAAIbAAcJ9BLeZgBVAQAbAAcJ9BLeZgBVAQAAAA==.',
Mi='Micheal:BAAALgAFFAIJAgAAAA==.Midir:BAAALgAECgQJBAAAAA==.Miladrayn:BAAALgADCgUJBQAAAA==.Min:BAAALgAECgIJAgAAAA==.Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgAECgIJAgAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAABLgAECn8fAAIVAAgJUh8FBwBuAgAVAAgJUh8FBwBuAgAAAA==.Monalina:BAAALgAECgkJBwAAAA==.Mongrol:BAAALgAECgQJBgAAAA==.Monju:BAAALgAECgEJAQAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJFAAaANwNAA==.',
Mu='Mummrakhan:BAABLgAECn8ZAAIiAAYJzgSkzAC3AAAiAAYJzgSkzAC3AAAAAA==.',
Na='Naniel:BAACLgAFFH8VAAIEAAUJ2g5FJAAfAQAEAAUJ2g5FJAAfAQAuAAQKfykAAgQACQmDFr4cAAcCAAQACQmDFr4cAAcCAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBwAAAA==.Neb:BAACLgAFFH8LAAIiAAQJ0g6lVgAVAQAiAAQJ0g6lVgAVAQAuAAQKf0kAAyIACQkMHAYYAJICACIACQkMHAYYAJICACMAAgm5EVZXAGgAAAAA.Necroy:BAABLgAECn8VAAIjAAkJCh6SAgCIAgAjAAkJCh6SAgCIAgAAAA==.',
Ni='Niccee:BAABLgAECn8gAAIDAAkJrwwQKgB/AQADAAkJrwwQKgB/AQAAAA==.Nick:BAACLgAFFH8RAAIiAAUJ+BuIEQBYAQAiAAUJ+BuIEQBYAQAuAAQKfxgAAyIACAkYIykbALECACIACAkYIykbALECACMAAQkAAHuAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAeAAAAAA==.',
No='Noodles:BAAALgAECgQJCgABLgAECgcJDQAeAAAAAA==.Nosebleeds:BAABLgAECn8VAAMJAAgJCh15EADcAQAJAAcJdxx5EADcAQAkAAIJfxw8QwBRAAAAAA==.Notyourheals:BAABLgAECn8wAAMdAAgJ2BEtMQB2AQAdAAgJ2BEtMQB2AQAHAAQJSAGjjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIaAAkJNxa+KQAEAgAaAAkJNxa+KQAEAgAAAA==.',
Od='Odsum:BAABLgAECn8XAAIPAAYJWBpNiQBbAQAPAAYJWBpNiQBbAQAAAA==.',
Om='Omegasupreme:BAAALgADCgMJAwAAAA==.',
Oo='Oogrutamu:BAAALgAECgIJAgAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgMJBgAAAA==.Pandabear:BAAALgADCgkJDwAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papasmurff:BAAALgADCgIJAgAAAA==.Papichulo:BAAALgAECgIJAgAAAA==.',
Pe='Percival:BAABLgAECn8lAAIPAAkJUA0GbACUAQAPAAkJUA0GbACUAQAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAABLgAECn8jAAIPAAkJoCMABgBAAwAPAAkJoCMABgBAAwAAAA==.',
Po='Poetbrat:BAAALgADCggJGQABLgAECggJLAADAH8DAA==.Porkles:BAAALgADCgMJBAAAAA==.',
Pr='Praxiscannon:BAAALgAECgUJBQAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIOAAkJswsUCgB9AQAOAAkJswsUCgB9AQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAABLgAECn8iAAMaAAgJlBEoNwC5AQAaAAgJlBEoNwC5AQADAAIJIAJ1pwATAAAAAA==.',
Qu='Queue:BAABLgAECn8WAAIjAAUJmBNWFgDuAAAjAAUJmBNWFgDuAAAAAA==.Quilten:BAABLgAECn8ZAAIRAAYJ5g1uRADqAAARAAYJ5g1uRADqAAAAAA==.',
Ra='Raenii:BAAALgAFFAEJAwABLgAFFAIJBgAZAMMSAA==.Ramoth:BAAALgAECgYJEwAAAA==.Ranoe:BAAALgADCgYJBgAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgAECgIJAgAAAA==.Rayne:BAABLgAECn8nAAIWAAkJAh1vLgBdAgAWAAkJAh1vLgBdAgAAAA==.Razelda:BAAALgAECgkJBgAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8gAAMTAAkJbA8eGQAHAQASAAcJng7SoQAmAQATAAUJ2Q0eGQAHAQAAAA==.',
Ri='Rinnian:BAAALgAECgYJDwAAAA==.Rinny:BAAALgAECgEJAQAAAA==.Riptideaf:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgYJEQAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECgkJSAAQAFMbAA==.Robbiemonk:BAABLgAECn9IAAMQAAkJUxskDABxAgAQAAkJUxskDABxAgARAAQJ9wMTXgCYAAAAAA==.Robbiesboomy:BAAALgAECgIJAgABLgAECgkJSAAQAFMbAA==.Rodric:BAAALgADCgMJAwABLgAECgkJFgACAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgYJDgAAAA==.Sannith:BAABLgAECn86AAIWAAkJUxaoOAAzAgAWAAkJUxaoOAAzAgAAAA==.Sapphi:BAABLgAECn8lAAIVAAkJew+EFACEAQAVAAkJew+EFACEAQAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAABLgAECn8XAAIYAAgJdgwQKQAlAQAYAAgJdgwQKQAlAQAAAA==.Senjinbenjin:BAAALgAECgQJBQAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAeAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shakjabuti:BAAALgADCgUJBQAAAA==.Shamanoodles:BAAALgADCgkJCQABLgAECgkJPAAHAFMiAA==.Shauralin:BAAALgAECgEJAQAAAA==.Shelbei:BAAALgAECgQJBgAAAA==.Shespawn:BAAALgAFFAIJBAAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMCAAkJqhDkLwDxAQACAAkJqhDkLwDxAQAlAAEJLQJiMgApAAAAAA==.Shykara:BAAALgADCgYJEgABLgAECgYJEwAeAAAAAA==.Shâdê:BAAALgAECgEJAwAAAA==.Shådowblade:BAAALgADCgkJCQAAAA==.',
Si='Sindrak:BAAALgAECgEJAgAAAA==.Sins:BAAALgAECgIJAgAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slabomeat:BAAALgAECgcJBwABLgAECgkJFgACAKoQAA==.Slipperybop:BAACLgAFFH8PAAIPAAMJ4CRGPQArAQAPAAMJ4CRGPQArAQAuAAQKfxwAAg8ACQlgI5wJABkDAA8ACQlgI5wJABkDAAEuAAUUAQkDAB4AAAAA.Slugbow:BAAALgAECgUJBwAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIHAAkJZAY7bwAJAQAHAAkJZAY7bwAJAQAAAA==.',
So='Soldanis:BAAALgAECgEJAQAAAA==.Sorena:BAAALgAECgMJAwAAAA==.',
Sp='Spawny:BAAALgADCgYJBgAAAA==.Spyman:BAAALgAECgEJBAAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8zAAIaAAkJghu7EQC/AgAaAAkJghu7EQC/AgAAAA==.',
St='Starz:BAAALgADCgkJCQAAAA==.Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAeAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJEQAAAA==.Sydonai:BAAALgAECgEJAgAAAA==.Syndra:BAAALgAECgEJAQABLgAECggJCgAeAAAAAA==.',
Ta='Tanderina:BAAALgAECgIJAgAAAA==.Tankshock:BAAALgAECgUJBgAAAA==.Taylor:BAAALgAECgcJAgABLgAFFAUJCwABADwcAA==.',
Te='Tellah:BAABLgAECn8VAAMHAAkJtxnIFgCQAgAHAAkJtxnIFgCQAgAdAAQJXAc5YwC2AAABLgAECgQJDgAeAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Thegreatland:BAAALgAECgMJAwAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgADCgkJCQABLgAECgkJIwAPAKAjAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgcJFwAZAGwTAA==.',
Tw='Twomz:BAABLgAECn8wAAMHAAkJHRGlLQD8AQAHAAkJHRGlLQD8AQAdAAEJAADmxAAAAAAAAA==.',
Um='Umi:BAAALgAECgEJAQABLgAECgkJLgAHABkcAA==.',
Un='Unclebenjinn:BAAALgAECgYJBgAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgkJFwAWAA0hAA==.',
Va='Varrieto:BAAALgAECgcJBwAAAA==.Vavaboom:BAAALgADCggJCAAAAA==.',
Ve='Veirlyn:BAAALgAECgkJCQAAAA==.',
Vi='Vindication:BAABLgAECn8iAAILAAgJ9iJMBwAVAwALAAgJ9iJMBwAVAwAAAA==.Viz:BAAALgADCggJGQAAAA==.',
Vo='Voidshådow:BAABLgAECn8XAAIbAAcJmxNNXgBqAQAbAAcJmxNNXgBqAQAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vu='Vulpain:BAAALgAECgYJBgABLgAECgkJIwAPAKAjAA==.',
Vy='Vylandra:BAAALgAECgQJBQAAAA==.',
We='Weepingwillo:BAAALgAECgQJBAAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Where:BAAALgAECgUJBQAAAA==.Whiteangel:BAAALgADCgcJEQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCQAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAAALgAECgMJDAAAAA==.',
Xa='Xaela:BAABLgAECn8dAAIbAAkJEhdUOADiAQAbAAkJEhdUOADiAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgUJCgAAAA==.Xarous:BAAALgADCgkJFAABLgAECgkJIwAPAKAjAA==.',
Xe='Xeon:BAAALgAECgIJBQAAAA==.',
Xi='Xiabal:BAABLgAECn8oAAMaAAkJ0x4gCQAlAwAaAAkJ0x4gCQAlAwADAAQJ0hdtQQADAQAAAA==.',
Xw='Xweakling:BAAALgAECgcJCwABLgAFFAQJDgAEAEobAA==.Xweekling:BAACLgAFFH8OAAIEAAQJSht7GABMAQAEAAQJSht7GABMAQAuAAQKfywAAgQACQl6I/4CAD0DAAQACQl6I/4CAD0DAAAA.Xweeklingdh:BAAALgADCgcJCwABLgAFFAQJDgAEAEobAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgAECgEJAQAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCggJGAAAAA==.',
Za='Zaraeth:BAAALgAECgUJCAABLgAECgUJCgAeAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zenhubba:BAAALgAECgYJBgABLgAECgkJMwAaAIIbAA==.Zerostar:BAABLgAECn8UAAIlAAYJGhFNLABCAQAlAAYJGhFNLABCAQABLgAECgkJLgACAP0aAA==.Zevon:BAAALgAECgIJAgABLgAECgUJCgAeAAAAAA==.',
['ße']='ßeastie:BAAALgADCgcJCwAAAA==.',
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
