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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Priest-Discipline','Paladin-Holy','Mage-Fire','Evoker-Augmentation','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','DemonHunter-Havoc','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Priest-Holy','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','Druid-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Paladin-Protection','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCggJFAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allila:BAABLgAECn8eAAIBAAgJghxiEwAZAgABAAgJghxiEwAZAgAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.',
Am='Ambrozyn:BAAALgAECgYJCAAAAA==.',
An='Andrew:BAAALgAECgYJCgAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgACAKoQAA==.Anna:BAAALgAECgcJCgAAAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAAALgAECgYJBgABLgAECggJHwADAKUCAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAAALgAECgYJCwAAAA==.Arieljoyeria:BAACLgAFFH8PAAMEAAUJMh0RAwBdAQAEAAQJ4B4RAwBdAQAFAAMJLxkUJwC4AAAuAAQKfyQAAwUACQmZH+MNAMACAAUACQkfHuMNAMACAAQABAkqGEYQAA4BAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAGANgQAA==.',
As='Ashog:BAAALgAECgIJAgAAAA==.Astar:BAAALgADCgcJDgABLgAECgkJJgAHANUcAA==.Astraea:BAABLgAECn8sAAIIAAgJrBiHDQDoAQAIAAgJrBiHDQDoAQABLgAECggJNgAGAO0jAA==.',
At='Athika:BAAALgADCgcJCgAAAA==.',
Au='Auddorn:BAAALgAECgUJBwAAAA==.Auria:BAABLgAECn8YAAIJAAgJ8Rz0CgCiAgAJAAgJ8Rz0CgCiAgAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAACLgAFFH8IAAIBAAMJ8AeCIgC4AAABAAMJ8AeCIgC4AAAuAAQKfyEAAgEACAnXC0IoAJcBAAEACAnXC0IoAJcBAAAA.Azend:BAAALgAECgIJAgAAAA==.Azphrodite:BAAALgAECgYJBgAAAA==.Azralia:BAABLgAECn8dAAIKAAkJpxW2FwA0AgAKAAkJpxW2FwA0AgAAAA==.',
Ba='Barthamus:BAAALgADCgYJBgAAAA==.',
Bb='Bbygee:BAAALgAECgYJDwAAAA==.',
Be='Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgcJEwAAAA==.Benjaminadin:BAAALgAECgUJCQAAAA==.Berris:BAAALgADCgUJBQAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn88AAILAAkJBAz3AwCmAQALAAkJBAz3AwCmAQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAABLgAECn8ZAAMMAAgJ/BX7LABrAQAMAAcJShT7LABrAQAHAAcJiwpaKgAfAQAAAA==.Borgin:BAABLgAECn8VAAICAAYJ3QbkogDdAAACAAYJ3QbkogDdAAAAAA==.Borimor:BAABLgAECn8YAAINAAcJdgSx1QDMAAANAAcJdgSx1QDMAAABLgAECgkJFgACAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAABLgAECn8YAAMOAAYJ5Q7IPQDyAAAOAAYJ5Q7IPQDyAAAPAAEJuAMHiQAmAAABLgAECgkJLwAQAPcZAA==.Bridgetta:BAAALgAECgIJAgAAAA==.Briëlla:BAABLgAECn8vAAQQAAkJ9xlXJQBaAgAQAAkJ9xlXJQBaAgARAAEJDQitNAAnAAASAAEJOgPSYAAUAAAAAA==.Bromdrago:BAAALgAECgEJAQAAAA==.Bromkin:BAAALgAECgYJEQAAAA==.',
Ca='Caalu:BAAALgADCgEJAgAAAA==.Calindala:BAAALgADCggJBAAAAA==.Calinor:BAAALgAECgMJCAAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAABLgAECn8aAAITAAYJCQeG8AAZAQATAAYJCQeG8AAZAQAAAA==.',
Ce='Ceran:BAABLgAECn8mAAIUAAgJShHqGgCFAQAUAAgJShHqGgCFAQAAAA==.Cereus:BAABLgAECn8mAAMHAAkJ1RxABADcAgAHAAkJ1RxABADcAgAVAAcJ5BWACACVAQAAAA==.',
Ch='Chaelenge:BAABLgAECn8jAAMKAAgJUR8nCwDGAgAKAAgJUR8nCwDGAgANAAMJpQn/NQFZAAAAAA==.Cheatt:BAAALgAECgEJAQAAAA==.Chubbabuns:BAABLgAECn8xAAMWAAkJ1yQnAgAcAwAWAAkJ/yMnAgAcAwAXAAYJ2yMXLwB/AQAAAA==.Chyran:BAAALgAECgYJBwAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8kAAIYAAgJCRn0FwD4AQAYAAgJCRn0FwD4AQAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAECgYJDwAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.',
['Cò']='Còffee:BAAALgADCgkJCQABLgAECgcJFAAOAP0gAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCgUJEAAAAA==.Dalielah:BAAALgAECgQJBgAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.Darkkstarr:BAAALgADCgUJBQAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Demdots:BAAALgADCgEJAQAAAA==.Denvoker:BAAALgAECgYJEAAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEAAAAA==.',
Di='Diddykong:BAAALgAECgkJCQAAAA==.Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Docqt:BAAALgADCgEJAQAAAA==.Dolleez:BAAALgAECgcJCAAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn8fAAIDAAgJpQL1VQCcAAADAAgJpQL1VQCcAAAAAA==.',
Du='Dunkaroo:BAABLgAECn8eAAIZAAkJMhT6OwDAAQAZAAkJMhT6OwDAAQAAAA==.',
['Dé']='Dékü:BAAALgAECgEJAgAAAA==.',
Ei='Eikinskaldi:BAAALgAECgEJAgAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAABLgAECn8cAAINAAkJdAu8aQCBAQANAAkJdAu8aQCBAQAAAA==.',
Er='Eraessyr:BAAALgADCgcJDQAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECgcJCQAAAA==.Fandris:BAAALgAECgEJAQAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgkJPAAaADoVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fo='Forsëti:BAAALgAECgIJAgAAAA==.',
Fr='Freakadeek:BAAALgAECgMJBAABLgAECgkJFQARAGsNAA==.Frosh:BAABLgAECn8YAAMGAAgJ2BB2OACgAQAGAAgJ2BB2OACgAQAbAAMJ4h2/bQCMAAAAAA==.Frìeren:BAABLgAECn8oAAITAAkJ1hPlSADpAQATAAkJ1hPlSADpAQAAAA==.',
Fu='Fuegaluna:BAAALgADCgkJCwAAAA==.Fundetected:BAABLgAECn8oAAIZAAkJfBrCGgBgAgAZAAkJfBrCGgBgAgAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gillarria:BAAALgAECgEJAQAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgAECgEJAQAAAA==.Grimmberly:BAAALgAECgcJDAAAAA==.Grimmothy:BAABLgAECn8rAAIOAAgJfxhkFgDmAQAOAAgJfxhkFgDmAQAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Guthunnel:BAABLgAECn8yAAICAAkJvhJkMQD/AQACAAkJvhJkMQD/AQAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgAECgEJAQAAAA==.Hakuri:BAAALgADCgcJDwABLgAECgQJCAAcAAAAAA==.Hannibow:BAAALgAECgcJCAAAAA==.Happydru:BAAALgADCgcJDgAAAA==.',
He='Helle:BAABLgAECn8cAAQaAAcJoxZDJQDNAQAaAAcJoxZDJQDNAQAOAAYJ6Aj0TQALAQAPAAEJrw3MjQAwAAAAAA==.',
Hi='Highfever:BAABLgAECn8UAAIdAAUJ3A27aQDlAAAdAAUJ3A27aQDlAAAAAA==.',
Ho='Hoawatt:BAAALgADCgEJAgAAAA==.Holynova:BAAALgADCgQJBwABLgAECgQJBAAcAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgkJMwAdAIIbAA==.Huuch:BAABLgAECn8oAAICAAkJEAtgSQCtAQACAAkJEAtgSQCtAQAAAA==.',
Hy='Hycinari:BAAALgAECgIJAgAAAA==.Hyperius:BAAALgAECgUJBQAAAA==.',
Ic='Icrucify:BAACLgAFFH8FAAICAAMJ6RwlFQCwAAACAAMJ6RwlFQCwAAAuAAQKfzkAAgIACQmgJbQFACcDAAIACQmgJbQFACcDAAAA.',
Ig='Ignia:BAAALgAECgEJAQABLgAECgcJCQAcAAAAAA==.',
Il='Ilanos:BAAALgAECgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAcAAAAAA==.',
Ir='Iremoon:BAABLgAECn80AAMQAAkJTRUgMQAmAgAQAAkJTRUgMQAmAgASAAIJRwQTQgBCAAAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.',
Je='Jestyr:BAABLgAFFH8GAAIUAAIJ0hyNFwCrAAAUAAIJ0hyNFwCrAAAAAA==.Jestyrd:BAAALgAECgMJAwABLgAFFAIJBgAUANIcAA==.Jestyrmo:BAABLgAECn8rAAMOAAgJARtWIgCFAQAOAAcJ2BlWIgCFAQAaAAgJgBB4OgBUAQABLgAFFAIJBgAUANIcAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8QAAIPAAMJUyH1DwApAQAPAAMJUyH1DwApAQAuAAQKf0YAAw8ACQnwJAYCAEcDAA8ACQnwJAYCAEcDABoAAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJEwAAAA==.',
Ju='Jumbo:BAAALgAECgEJAQAAAA==.',
Ka='Kaceya:BAAALgAECgQJCAAAAA==.Kainarasa:BAAALgAECgYJEwABLgAECggJFQANAPEgAA==.Kairnei:BAAALgADCgYJBgAAAA==.Katarinea:BAABLgAECn8bAAIDAAgJkw37MgAzAQADAAgJkw37MgAzAQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Ke='Keats:BAAALgAECgIJAgAAAA==.',
Kh='Khalessie:BAABLgAECn8lAAIJAAkJOQ0RHgC6AQAJAAkJOQ0RHgC6AQAAAA==.Kheldar:BAAALgAECgcJAQAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMeAAkJpB7mBgBLAgAeAAkJpB7mBgBLAgAGAAEJeQEl2wAZAAAAAA==.Kiselle:BAAALgAECgQJBAAAAA==.',
Ko='Korkneelious:BAAALgAECgYJDAAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Ky='Kyomu:BAAALgADCggJCAABLgAECggJFQANAPEgAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn8rAAIXAAYJnhulKwCRAQAXAAYJnhulKwCRAQAAAA==.Liths:BAABLgAECn8zAAIfAAkJDwnGDwA1AQAfAAkJDwnGDwA1AQAAAA==.Littlemoses:BAABLgAECn8jAAICAAgJzxpBKwAZAgACAAgJzxpBKwAZAgAAAA==.',
Lo='Lockdarkly:BAAALgAECgQJBwAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAABLgAECn8VAAMJAAYJIxVTJACJAQAJAAYJIxVTJACJAQAYAAUJZwk5UwDqAAAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJEAAcAAAAAA==.Malendren:BAAALgAECgEJAQAAAA==.Malignus:BAABLgAECn8pAAITAAkJIBaENwAjAgATAAkJIBaENwAjAgABLgADCgkJFwAcAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECggJJQATAAMcAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgcJCwAAAA==.',
Mc='Mcdavé:BAABLgAECn80AAIbAAkJsw7hKACOAQAbAAkJsw7hKACOAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECggJHgABAIIcAA==.Meerclar:BAAALgAECgIJAwABLgAECgUJCAAcAAAAAA==.Melaila:BAABLgAECn82AAIGAAgJ7SOqEgCfAgAGAAgJ7SOqEgCfAgAAAA==.Mellwynn:BAAALgAECgQJBgAAAA==.Melunaura:BAAALgAECggJCAABLgAECggJNgAGAO0jAA==.',
Mf='Mf:BAABLgAECn8gAAIZAAcJ9BI2XwBTAQAZAAcJ9BI2XwBTAQAAAA==.',
Mi='Micheal:BAAALgAFFAIJAgAAAA==.Midir:BAAALgAECgQJBAAAAA==.Miladrayn:BAAALgADCgUJBQAAAA==.Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgAECgIJAQAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAAALgAECgYJEAAAAA==.Monalina:BAAALgAECgMJAwAAAA==.Mongrol:BAAALgAECgQJBgAAAA==.Monju:BAAALgAECgEJAQAAAA==.Moonowl:BAAALgADCgEJAgAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJFAAdANwNAA==.',
Mu='Mummrakhan:BAAALgAECgYJDQAAAA==.',
Na='Naniel:BAACLgAFFH8RAAIXAAQJ2g67HQAmAQAXAAQJ2g67HQAmAQAuAAQKfycAAhcACAkMFnIkAL0BABcACAkMFnIkAL0BAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBwAAAA==.Neb:BAABLgAECn8/AAMgAAkJDRk+IABWAgAgAAkJDRk+IABWAgAhAAIJuRFWVwBoAAAAAA==.Necroy:BAABLgAECn8UAAIhAAgJOR1GBAAmAgAhAAgJOR1GBAAmAgAAAA==.',
Ni='Niccee:BAABLgAECn8eAAIDAAgJSg2ALgBMAQADAAgJSg2ALgBMAQAAAA==.Nick:BAACLgAFFH8RAAIgAAUJ+BuIEQBYAQAgAAUJ+BuIEQBYAQAuAAQKfxgAAyAACAkYIykbALECACAACAkYIykbALECACEAAQkAAHuAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAcAAAAAA==.',
No='Noodles:BAAALgAECgQJBwABLgAECgcJDQAcAAAAAA==.Nosebleeds:BAABLgAECn8VAAMIAAgJCh0TDgDfAQAIAAcJdxwTDgDfAQAiAAIJfxwROQBTAAAAAA==.Notyourheals:BAABLgAECn8jAAMbAAgJEA9AMgBZAQAbAAgJEA9AMgBZAQAGAAQJSAGjjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIdAAkJNxaxJgAGAgAdAAkJNxaxJgAGAgAAAA==.',
Od='Odsum:BAABLgAECn8XAAINAAYJWBojewBdAQANAAYJWBojewBdAQAAAA==.',
Oo='Oogrutamu:BAAALgAECgIJAgAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgMJBgAAAA==.Pandabear:BAAALgADCgkJDwAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papasmurff:BAAALgADCgIJAgAAAA==.Papichulo:BAAALgAECgIJAgAAAA==.',
Pe='Percival:BAABLgAECn8jAAINAAgJYg22gQBQAQANAAgJYg22gQBQAQAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAABLgAECn8VAAINAAgJ8SC9FwCeAgANAAgJ8SC9FwCeAgAAAA==.',
Po='Poetbrat:BAAALgADCgUJEQABLgAECggJHwADAKUCAA==.Porkles:BAAALgADCgMJBAAAAA==.',
Pr='Praxiscannon:BAAALgAECgQJBAAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIVAAkJswvOCACNAQAVAAkJswvOCACNAQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAABLgAECn8YAAIdAAgJNw8OPQCNAQAdAAgJNw8OPQCNAQAAAA==.',
Qu='Queue:BAAALgAECgUJEgAAAA==.Quilten:BAABLgAECn8ZAAIPAAYJ5g0tPQDyAAAPAAYJ5g0tPQDyAAAAAA==.',
Ra='Raenii:BAAALgAFFAEJAwABLgAECgkJFQAYAHYXAA==.Ramoth:BAAALgAECgYJEAAAAA==.Ranoe:BAAALgADCgYJBgAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgAECgIJAgAAAA==.Rayne:BAABLgAECn8lAAITAAgJAxylRwDtAQATAAgJAxylRwDtAQAAAA==.Razelda:BAAALgAECgkJBgAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8fAAMQAAgJCBCzkwArAQAQAAcJng6zkwArAQARAAQJhg6tGgDHAAAAAA==.',
Ri='Rinnian:BAAALgAECgYJDwAAAA==.Rinny:BAAALgAECgEJAQAAAA==.Riptideaf:BAAALgADCgIJAgAAAA==.',
Ro='Roadwanderer:BAAALgAECgYJDgAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECgkJSAAOAFMbAA==.Robbiemonk:BAABLgAECn9IAAMOAAkJUxvHCgB2AgAOAAkJUxvHCgB2AgAPAAQJ9wMTXgCYAAAAAA==.Robbiesboomy:BAAALgAECgIJAgABLgAECgkJSAAOAFMbAA==.Rodric:BAAALgADCgMJAwABLgAECgkJFgACAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgYJDgAAAA==.Sannith:BAABLgAECn80AAITAAkJrxNbRQD0AQATAAkJrxNbRQD0AQAAAA==.Sapphi:BAABLgAECn8jAAIjAAgJ9Q9BFgBWAQAjAAgJ9Q9BFgBWAQAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAABLgAECn8UAAIWAAYJTw55MADrAAAWAAYJTw55MADrAAAAAA==.Senjinbenjin:BAAALgAECgQJBAAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAcAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shakjabuti:BAAALgADCgUJBQAAAA==.Shauralin:BAAALgAECgEJAQAAAA==.Shelbei:BAAALgAECgQJBQAAAA==.Shespawn:BAAALgAFFAIJBAAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMCAAkJqhDkLwDxAQACAAkJqhDkLwDxAQAkAAEJLQJiMgApAAAAAA==.Shykara:BAAALgADCgUJEQABLgAECgYJEAAcAAAAAA==.Shâdê:BAAALgAECgEJAgAAAA==.',
Si='Sindrak:BAAALgAECgEJAgAAAA==.Sins:BAAALgAECgIJAgAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slabomeat:BAAALgAECgcJBwABLgAECgkJFgACAKoQAA==.Slipperybop:BAACLgAFFH8MAAINAAMJHiToMQAwAQANAAMJHiToMQAwAQAuAAQKfxoAAg0ACQlUIjIUALUCAA0ACQlUIjIUALUCAAEuAAUUAQkBABwAAAAA.Slugbow:BAAALgAECgIJAgAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIGAAkJZAYlZQAMAQAGAAkJZAYlZQAMAQAAAA==.Snoroll:BAAALgADCgEJAgAAAA==.',
So='Soldanis:BAAALgAECgEJAQAAAA==.Sorena:BAAALgAECgMJAwAAAA==.',
Sp='Spawny:BAAALgADCgYJBgAAAA==.Spyman:BAAALgAECgEJBAAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8zAAIdAAkJghsNEADBAgAdAAkJghsNEADBAgAAAA==.',
St='Starz:BAAALgADCgkJCQAAAA==.Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAcAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgADCgEJAQAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJEQAAAA==.Sydonai:BAAALgADCgQJBAAAAA==.',
Ta='Tanderina:BAAALgAECgIJAgAAAA==.',
Te='Tellah:BAAALgAECggJEgABLgAECgQJDgAcAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgADCgkJCQABLgAECggJFQANAPEgAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgYJFgAYABwWAA==.',
Tw='Twomz:BAABLgAECn8tAAMGAAgJJxDOPACeAQAGAAgJJxDOPACeAQAbAAEJAADXsAAAAAAAAA==.',
Um='Umi:BAAALgAECgEJAQABLgAECgkJLgAGABkcAA==.',
Un='Unclebenjinn:BAAALgAECgYJBgAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgkJFwATAA0hAA==.',
Va='Varrieto:BAAALgAECgcJBwAAAA==.Vavaboom:BAAALgADCggJCAAAAA==.',
Ve='Veirlyn:BAAALgAECgkJCQAAAA==.',
Vi='Vindication:BAABLgAECn8gAAIKAAgJ9iIzBgAaAwAKAAgJ9iIzBgAaAwAAAA==.Viz:BAAALgADCgUJEQAAAA==.',
Vo='Voidshådow:BAAALgAECgYJDwAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vu='Vulpain:BAAALgAECgYJBgABLgAECggJFQANAPEgAA==.',
Vy='Vylandra:BAAALgAECgQJBAAAAA==.',
We='Weepingwillo:BAAALgAECgQJBAAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Whiteangel:BAAALgADCgcJEQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCQAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAAALgAECgMJCAAAAA==.',
Xa='Xaela:BAABLgAECn8dAAIZAAkJEheqMwDhAQAZAAkJEheqMwDhAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgUJCAAAAA==.Xarous:BAAALgADCgkJFAABLgAECggJFQANAPEgAA==.',
Xe='Xeon:BAAALgAECgEJAwAAAA==.',
Xi='Xiabal:BAABLgAECn8mAAMdAAgJGyG2CwDyAgAdAAgJGyG2CwDyAgADAAQJ0hcJPAAEAQAAAA==.',
Xw='Xweakling:BAAALgAECgcJCQABLgAFFAQJCAAXAJ4aAA==.Xweekling:BAACLgAFFH8IAAIXAAQJnhoiEwBTAQAXAAQJnhoiEwBTAQAuAAQKfyMAAhcACQlmHIsSAEwCABcACQlmHIsSAEwCAAAA.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgAECgEJAQAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgUJEAAAAA==.',
Za='Zaraeth:BAAALgAECgUJCAABLgAECgUJCAAcAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zerostar:BAAALgAECgYJEAABLgAECgkJLgACAP0aAA==.Zevon:BAAALgADCgQJBAABLgAECgUJCAAcAAAAAA==.',
['ße']='ßeastie:BAAALgADCgQJBQAAAA==.',
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
