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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Priest-Discipline','Paladin-Holy','Mage-Fire','Evoker-Augmentation','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','DemonHunter-Havoc','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Priest-Holy','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','Druid-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCggJFAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allesar:BAAALgADCgYJBgAAAA==.Allila:BAABLgAECn8eAAIBAAgJghzTFAAfAgABAAgJghzTFAAfAgAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.',
Am='Ambrozyn:BAAALgAECgYJCgAAAA==.',
An='Andrew:BAAALgAECgYJCgAAAA==.Anik:BAAALgAECgYJBwAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgACAKoQAA==.Anna:BAABLgAFFH8HAAIBAAQJNxmPEgA9AQABAAQJNxmPEgA9AQAAAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAAALgAECgYJDAABLgAECggJJQADAPgCAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAAALgAECgYJDwAAAA==.Arieljoyeria:BAACLgAFFH8PAAMEAAUJMh2QAwBZAQAEAAQJ4B6QAwBZAQAFAAMJLxlYFACtAAAuAAQKfyQAAwUACQmZH+MNAMACAAUACQkfHuMNAMACAAQABAkqGCwRAAcBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAGANgQAA==.',
As='Ashog:BAAALgAECgIJAgAAAA==.Astar:BAAALgADCgcJDgABLgAECgkJMgAHAFwfAA==.Astraea:BAABLgAECn80AAIIAAgJmBzzCQA2AgAIAAgJmBzzCQA2AgABLgAECgkJOgAGABIiAA==.',
At='Athika:BAAALgADCgcJCgAAAA==.',
Au='Auddorn:BAAALgAECgUJCQAAAA==.Auria:BAABLgAECn8aAAIJAAgJ8RzsCwCjAgAJAAgJ8RzsCwCjAgAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAACLgAFFH8IAAIBAAMJ8Af7JQCxAAABAAMJ8Af7JQCxAAAuAAQKfyEAAgEACAnXC0IoAJcBAAEACAnXC0IoAJcBAAAA.Azend:BAAALgAECgIJAgAAAA==.Azphrodite:BAAALgAECgYJBgAAAA==.Azralia:BAABLgAECn8dAAIKAAkJpxVMGQAwAgAKAAkJpxVMGQAwAgAAAA==.',
Ba='Barthamus:BAAALgADCgYJBgAAAA==.',
Bb='Bbygee:BAAALgAECgYJEAAAAA==.',
Be='Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgcJEwAAAA==.Benjaminadin:BAAALgAECgUJDQAAAA==.Berris:BAAALgADCgUJBQAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8+AAILAAkJJAyYBACRAQALAAkJJAyYBACRAQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAABLgAECn8bAAMMAAgJ/BWPLwBwAQAMAAcJShSPLwBwAQAHAAcJiwpaKgAfAQAAAA==.Borgin:BAABLgAECn8VAAICAAYJ3QYirADaAAACAAYJ3QYirADaAAAAAA==.Borimor:BAABLgAECn8fAAINAAcJcAwOngAvAQANAAcJcAwOngAvAQABLgAECgkJFgACAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAABLgAECn8ZAAMOAAYJ5Q4pQADxAAAOAAYJ5Q4pQADxAAAPAAEJuAMHiQAmAAABLgAECgkJOAAQAOccAA==.Bridgetta:BAAALgAECgIJAgAAAA==.Briëlla:BAABLgAECn84AAQQAAkJ5xzBFwCwAgAQAAkJ5xzBFwCwAgARAAEJDQgfOwAmAAASAAEJOgNEZgAUAAAAAA==.Bromdrago:BAAALgAECgEJAQAAAA==.Bromkin:BAAALgAECgYJEQAAAA==.',
['Bë']='Bëorn:BAAALgAECgUJBQABLgAECgkJFgACAKoQAA==.',
Ca='Calindala:BAAALgADCggJBAAAAA==.Calinor:BAAALgAECgQJDAAAAA==.Carl:BAAALgAECgQJAwAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAABLgAECn8aAAITAAYJCQeG8AAZAQATAAYJCQeG8AAZAQAAAA==.',
Ce='Ceran:BAABLgAECn8qAAIUAAgJrxLRGgCXAQAUAAgJrxLRGgCXAQAAAA==.Cereus:BAABLgAECn8yAAMHAAkJXB/PAgApAwAHAAkJXB/PAgApAwAVAAgJ8hpJBAArAgAAAA==.',
Ch='Chaelenge:BAABLgAECn8kAAMKAAgJkR+QCwDKAgAKAAgJkR+QCwDKAgANAAMJpQlQRgFZAAAAAA==.Cheatt:BAAALgAECgEJAQAAAA==.Chubbabuns:BAABLgAECn8xAAMWAAkJ1yRuAgAWAwAWAAkJ/yNuAgAWAwAXAAYJ2yMrMgB8AQAAAA==.Chyran:BAAALgAECggJCQAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8lAAIYAAkJ4RjhEgA3AgAYAAkJ4RjhEgA3AgAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAFFAIJAgAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.Cutecop:BAAALgAECgIJAgAAAA==.',
['Cò']='Còffee:BAAALgADCgkJCQABLgAECgcJFAAOAP0gAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCgUJEAAAAA==.Dalielah:BAAALgAECgQJBgAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.Darkkstarr:BAAALgADCgUJCAAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Demdots:BAAALgADCgEJAQAAAA==.Denvoker:BAAALgAECgYJEgAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEQAAAA==.',
Di='Diddykong:BAAALgAECgkJCQAAAA==.Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Docqt:BAAALgADCgEJAQAAAA==.Dolleez:BAAALgAECgcJCAAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn8lAAIDAAgJ+AL8VgCmAAADAAgJ+AL8VgCmAAAAAA==.',
Du='Dunkaroo:BAABLgAECn8eAAIZAAkJMhTIQAC7AQAZAAkJMhTIQAC7AQAAAA==.',
['Dé']='Dékü:BAAALgAECgcJCQAAAA==.',
Ei='Eikinskaldi:BAAALgAECgEJAgAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAABLgAECn8jAAINAAkJpQs4bwCEAQANAAkJpQs4bwCEAQAAAA==.',
Er='Eraessyr:BAAALgADCgcJDQAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECggJCgAAAA==.Fandris:BAAALgAECgEJAQAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgkJRQAaAHMVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fo='Forsëti:BAAALgAECgIJAgAAAA==.',
Fr='Freakadeek:BAAALgAECgMJBAABLgAECgkJFQARAGsNAA==.Frosh:BAABLgAECn8YAAMGAAgJ2BB2OACgAQAGAAgJ2BB2OACgAQAbAAMJ4h2/bQCMAAAAAA==.Frìeren:BAABLgAECn8oAAITAAkJ1hM6TQDtAQATAAkJ1hM6TQDtAQAAAA==.',
Fu='Fuegaluna:BAAALgADCgkJCwAAAA==.Fundetected:BAABLgAECn8rAAIZAAkJfBoBHQBcAgAZAAkJfBoBHQBcAgAAAA==.',
['Fâ']='Fâllenboy:BAAALgAECgMJAwAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gillarria:BAAALgAECgQJAQAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgAECgEJAQAAAA==.Grimmberly:BAAALgAECgcJDAAAAA==.Grimmothy:BAABLgAECn8sAAIOAAkJ3BagEQAhAgAOAAkJ3BagEQAhAgAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Guthunnel:BAABLgAECn86AAICAAkJvhKoNAD+AQACAAkJvhKoNAD+AQAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgAECgEJAQAAAA==.Hakuri:BAAALgADCgcJDwABLgAECgQJCAAcAAAAAA==.Hannibow:BAAALgAECgcJCAAAAA==.Happydru:BAAALgADCgcJDgAAAA==.',
He='Helle:BAABLgAECn8dAAQaAAgJwhWTIQD8AQAaAAgJwhWTIQD8AQAOAAYJ6Aj0TQALAQAPAAEJrw07lgAvAAAAAA==.',
Hi='Highfever:BAABLgAECn8UAAIdAAUJ3A3ibQDhAAAdAAUJ3A3ibQDhAAAAAA==.',
Ho='Hoawatt:BAAALgADCgEJAgAAAA==.Holynova:BAAALgADCgQJBwABLgAECgQJBAAcAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgkJMwAdAIIbAA==.Huuch:BAABLgAECn8oAAICAAkJEAsvTwCoAQACAAkJEAsvTwCoAQAAAA==.',
Hy='Hycinari:BAAALgAECgIJAgAAAA==.Hyperius:BAAALgAECgUJBQAAAA==.',
Ic='Icrucify:BAACLgAFFH8FAAICAAMJ6RwlFQCwAAACAAMJ6RwlFQCwAAAuAAQKfzkAAgIACQmgJeEGACEDAAIACQmgJeEGACEDAAAA.',
Ig='Ignee:BAAALgAECgYJBwAAAA==.Ignia:BAAALgAECgEJAQABLgAECggJCgAcAAAAAA==.',
Il='Ilanos:BAAALgAECgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAcAAAAAA==.',
Ir='Iremoon:BAABLgAECn88AAMQAAkJkxUWMwAqAgAQAAkJkxUWMwAqAgASAAIJRwQTQgBCAAAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.Jaeler:BAAALgADCgYJBgAAAA==.',
Je='Jedistang:BAAALgAECgQJBAAAAA==.Jestyr:BAACLgAFFH8JAAIUAAMJcxd7EwDyAAAUAAMJcxd7EwDyAAAuAAQKfxYAAxQACQlUH60FANcCABQACQlUH60FANcCABkAAQmBB4AYASUAAAAA.Jestyrd:BAAALgAECgMJAwABLgAFFAMJCQAUAHMXAA==.Jestyrmo:BAABLgAECn8rAAMOAAgJARvrIwCEAQAOAAcJ2BnrIwCEAQAaAAgJgBB9PwBWAQABLgAFFAMJCQAUAHMXAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8UAAIPAAQJlR0fCgBtAQAPAAQJlR0fCgBtAQAuAAQKf0kAAw8ACQnwJD0CAEUDAA8ACQnwJD0CAEUDABoAAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJEwAAAA==.',
Ju='Jumbo:BAAALgAECgMJBAAAAA==.',
Ka='Kaceya:BAAALgAECgQJCAAAAA==.Kainarasa:BAAALgAECgYJEwABLgAECgkJGQANAJEhAA==.Kairnei:BAAALgADCgYJBgAAAA==.Katarinea:BAABLgAECn8fAAIDAAkJiw7NJwCDAQADAAkJiw7NJwCDAQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Ke='Keats:BAAALgAECgIJAgAAAA==.',
Kh='Khalessie:BAABLgAECn8lAAIJAAkJOQ10IAC8AQAJAAkJOQ10IAC8AQAAAA==.Kheldar:BAAALgAECgcJAQAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMeAAkJpB6RBwBFAgAeAAkJpB6RBwBFAgAGAAEJeQGT5wAZAAAAAA==.Kiselle:BAAALgAECgQJBAABLgAECggJGgAJAPEcAA==.',
Ko='Korkneelious:BAAALgAECgYJDAAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Ky='Kyomu:BAAALgADCggJCAABLgAECgkJGQANAJEhAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn8xAAIXAAYJnhvHLACYAQAXAAYJnhvHLACYAQAAAA==.Liths:BAABLgAECn87AAIfAAkJlAlNEAA4AQAfAAkJlAlNEAA4AQAAAA==.Littlemoses:BAABLgAECn8lAAICAAgJqxviKgAnAgACAAgJqxviKgAnAgAAAA==.',
Lo='Lockdarkly:BAAALgAECgQJBwAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAABLgAECn8VAAMJAAYJIxXzJgCMAQAJAAYJIxXzJgCMAQAYAAUJZwk5UwDqAAAAAA==.Lulzimadrood:BAAALgADCgMJAwAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJEQAcAAAAAA==.Malendren:BAAALgAECgEJAQAAAA==.Malignus:BAABLgAECn8qAAITAAkJIBY9OwAmAgATAAkJIBY9OwAmAgABLgADCgkJFwAcAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECggJJgATAAMcAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgcJCwAAAA==.Mavane:BAAALgADCgUJAQAAAA==.',
Mc='Mcdavé:BAABLgAECn88AAIbAAkJyxACJQCyAQAbAAkJyxACJQCyAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECggJHgABAIIcAA==.Meerclar:BAAALgAECgIJAwABLgAECgUJCgAcAAAAAA==.Melaila:BAABLgAECn86AAIGAAkJEiI7DgDXAgAGAAkJEiI7DgDXAgAAAA==.Mellwynn:BAAALgAECgQJBgAAAA==.Melunaura:BAAALgAECggJCAABLgAECgkJOgAGABIiAA==.',
Mf='Mf:BAABLgAECn8gAAIZAAcJ9BKiYwBUAQAZAAcJ9BKiYwBUAQAAAA==.',
Mi='Micheal:BAAALgAFFAIJAgAAAA==.Midir:BAAALgAECgQJBAAAAA==.Miladrayn:BAAALgADCgUJBQAAAA==.Min:BAAALgAECgIJAgAAAA==.Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgAECgIJAgAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAABLgAECn8YAAIgAAgJDB/rBgBmAgAgAAgJDB/rBgBmAgAAAA==.Monalina:BAAALgAECgkJBAAAAA==.Mongrol:BAAALgAECgQJBgAAAA==.Monju:BAAALgAECgEJAQAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJFAAdANwNAA==.',
Mu='Mummrakhan:BAABLgAECn8ZAAIhAAYJzgTlxgC6AAAhAAYJzgTlxgC6AAAAAA==.',
Na='Naniel:BAACLgAFFH8SAAIXAAUJ2g5nIQAfAQAXAAUJ2g5nIQAfAQAuAAQKfycAAhcACAkMFvAmALsBABcACAkMFvAmALsBAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBwAAAA==.Neb:BAACLgAFFH8HAAIhAAMJRAyBdQDJAAAhAAMJRAyBdQDJAAAuAAQKf0EAAyEACQldGgoeAGoCACEACQldGgoeAGoCACIAAgm5EVZXAGgAAAAA.Necroy:BAABLgAECn8VAAIiAAkJCh5iAgCNAgAiAAkJCh5iAgCNAgAAAA==.',
Ni='Niccee:BAABLgAECn8fAAIDAAgJSg3/MABKAQADAAgJSg3/MABKAQAAAA==.Nick:BAACLgAFFH8RAAIhAAUJ+BuIEQBYAQAhAAUJ+BuIEQBYAQAuAAQKfxgAAyEACAkYIykbALECACEACAkYIykbALECACIAAQkAAHuAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAcAAAAAA==.',
No='Noodles:BAAALgAECgQJBwABLgAECgcJDQAcAAAAAA==.Nosebleeds:BAABLgAECn8VAAMIAAgJCh1sDwDdAQAIAAcJdxxsDwDdAQAjAAIJfxxdPgBSAAAAAA==.Notyourheals:BAABLgAECn8pAAMbAAgJAxAeNABcAQAbAAgJAxAeNABcAQAGAAQJSAGjjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIdAAkJNxZ8KAAFAgAdAAkJNxZ8KAAFAgAAAA==.',
Od='Odsum:BAABLgAECn8XAAINAAYJWBrZgwBcAQANAAYJWBrZgwBcAQAAAA==.',
Oo='Oogrutamu:BAAALgAECgIJAgAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgMJBgAAAA==.Pandabear:BAAALgADCgkJDwAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papasmurff:BAAALgADCgIJAgAAAA==.Papichulo:BAAALgAECgIJAgAAAA==.',
Pe='Percival:BAABLgAECn8kAAINAAgJYg3ihgBXAQANAAgJYg3ihgBXAQAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAABLgAECn8ZAAINAAkJkSEJCgAPAwANAAkJkSEJCgAPAwAAAA==.',
Po='Poetbrat:BAAALgADCgUJFgABLgAECggJJQADAPgCAA==.Porkles:BAAALgADCgMJBAAAAA==.',
Pr='Praxiscannon:BAAALgAECgQJBAAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIVAAkJswuUCQCCAQAVAAkJswuUCQCCAQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAABLgAECn8YAAIdAAgJNw8kPwCMAQAdAAgJNw8kPwCMAQAAAA==.',
Qu='Queue:BAAALgAECgUJEwAAAA==.Quilten:BAABLgAECn8ZAAIPAAYJ5g3RQQDqAAAPAAYJ5g3RQQDqAAAAAA==.',
Ra='Raenii:BAAALgAFFAEJAwABLgAFFAIJBQAYAMMSAA==.Ramoth:BAAALgAECgYJEgAAAA==.Ranoe:BAAALgADCgYJBgAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgAECgIJAgAAAA==.Rayne:BAABLgAECn8mAAITAAgJAxxpSgD1AQATAAgJAxxpSgD1AQAAAA==.Razelda:BAAALgAECgkJBgAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8gAAMRAAkJbA+HFwAKAQAQAAcJng73mgArAQARAAUJ2Q2HFwAKAQAAAA==.',
Ri='Rinnian:BAAALgAECgYJDwAAAA==.Rinny:BAAALgAECgEJAQAAAA==.Riptideaf:BAAALgADCgIJBAAAAA==.',
Ro='Roadwanderer:BAAALgAECgYJEAAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECgkJSAAOAFMbAA==.Robbiemonk:BAABLgAECn9IAAMOAAkJUxuSCwBzAgAOAAkJUxuSCwBzAgAPAAQJ9wMTXgCYAAAAAA==.Robbiesboomy:BAAALgAECgIJAgABLgAECgkJSAAOAFMbAA==.Rodric:BAAALgADCgMJAwABLgAECgkJFgACAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgYJDgAAAA==.Sannith:BAABLgAECn86AAITAAkJUxZxNgA4AgATAAkJUxZxNgA4AgAAAA==.Sapphi:BAABLgAECn8kAAIgAAgJEBC9FwBTAQAgAAgJEBC9FwBTAQAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAABLgAECn8XAAIWAAgJdgy6JgArAQAWAAgJdgy6JgArAQAAAA==.Senjinbenjin:BAAALgAECgQJBQAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAcAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shakjabuti:BAAALgADCgUJBQAAAA==.Shauralin:BAAALgAECgEJAQAAAA==.Shelbei:BAAALgAECgQJBgAAAA==.Shespawn:BAAALgAFFAIJBAAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMCAAkJqhDkLwDxAQACAAkJqhDkLwDxAQAkAAEJLQJiMgApAAAAAA==.Shykara:BAAALgADCgUJEQABLgAECgYJEgAcAAAAAA==.Shâdê:BAAALgAECgEJAgAAAA==.Shådowblade:BAAALgADCgkJCQAAAA==.',
Si='Sindrak:BAAALgAECgEJAgAAAA==.Sins:BAAALgAECgIJAgAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slabomeat:BAAALgAECgcJBwABLgAECgkJFgACAKoQAA==.Slipperybop:BAACLgAFFH8PAAINAAMJ4CSLNQAxAQANAAMJ4CSLNQAxAQAuAAQKfxwAAg0ACQlgI6AIAB0DAA0ACQlgI6AIAB0DAAEuAAUUAQkBABwAAAAA.Slugbow:BAAALgAECgIJAgAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIGAAkJZAa+agALAQAGAAkJZAa+agALAQAAAA==.',
So='Soldanis:BAAALgAECgEJAQAAAA==.Sorena:BAAALgAECgMJAwAAAA==.',
Sp='Spawny:BAAALgADCgYJBgAAAA==.Spyman:BAAALgAECgEJBAAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8zAAIdAAkJghsMEQDAAgAdAAkJghsMEQDAAgAAAA==.',
St='Starz:BAAALgADCgkJCQAAAA==.Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAcAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJEQAAAA==.Sydonai:BAAALgAECgEJAQAAAA==.',
Ta='Tanderina:BAAALgAECgIJAgAAAA==.',
Te='Tellah:BAABLgAECn8VAAMGAAkJtxmzFQCQAgAGAAkJtxmzFQCQAgAbAAQJXAc5YwC2AAABLgAECgQJDgAcAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgADCgkJCQABLgAECgkJGQANAJEhAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgYJFgAYABwWAA==.',
Tw='Twomz:BAABLgAECn8vAAMGAAgJQhLzNADPAQAGAAgJQhLzNADPAQAbAAEJAAC+uwAAAAAAAA==.',
Um='Umi:BAAALgAECgEJAQABLgAECgkJLgAGABkcAA==.',
Un='Unclebenjinn:BAAALgAECgYJBgAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgkJFwATAA0hAA==.',
Va='Varrieto:BAAALgAECgcJBwAAAA==.Vavaboom:BAAALgADCggJCAAAAA==.',
Ve='Veirlyn:BAAALgAECgkJCQAAAA==.',
Vi='Vindication:BAABLgAECn8iAAIKAAgJ9iLABgAXAwAKAAgJ9iLABgAXAwAAAA==.Viz:BAAALgADCgUJFgAAAA==.',
Vo='Voidshådow:BAAALgAECgYJEQAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vu='Vulpain:BAAALgAECgYJBgABLgAECgkJGQANAJEhAA==.',
Vy='Vylandra:BAAALgAECgQJBQAAAA==.',
We='Weepingwillo:BAAALgAECgQJBAAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Where:BAAALgAECgQJBAAAAA==.Whiteangel:BAAALgADCgcJEQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCQAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAAALgAECgMJCgAAAA==.',
Xa='Xaela:BAABLgAECn8dAAIZAAkJEhdGNgDhAQAZAAkJEhdGNgDhAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgUJCgAAAA==.Xarous:BAAALgADCgkJFAABLgAECgkJGQANAJEhAA==.',
Xe='Xeon:BAAALgAECgIJBAAAAA==.',
Xi='Xiabal:BAABLgAECn8nAAMdAAgJGyGNDADxAgAdAAgJGyGNDADxAgADAAQJ0hfuPgAEAQAAAA==.',
Xw='Xweakling:BAAALgAECgcJCQABLgAFFAQJCwAXAEobAA==.Xweekling:BAACLgAFFH8LAAIXAAQJShtbFQBRAQAXAAQJShtbFQBRAQAuAAQKfyMAAhcACQlmHDEUAEkCABcACQlmHDEUAEkCAAAA.Xweeklingdh:BAAALgADCgcJCwABLgAFFAQJCwAXAEobAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgAECgEJAQAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgUJFQAAAA==.',
Za='Zaraeth:BAAALgAECgUJCAABLgAECgUJCgAcAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zenhubba:BAAALgAECgYJBgABLgAECgkJMwAdAIIbAA==.Zerostar:BAABLgAECn8UAAIkAAYJGhG6KgBHAQAkAAYJGhG6KgBHAQABLgAECgkJLgACAP0aAA==.Zevon:BAAALgAECgIJAgABLgAECgUJCgAcAAAAAA==.',
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
