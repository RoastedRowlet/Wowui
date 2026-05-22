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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Paladin-Holy','Mage-Fire','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','DemonHunter-Havoc','Evoker-Devastation','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Priest-Holy','DemonHunter-Devourer','Monk-Mistweaver','Unknown-Unknown','Shaman-Elemental','Monk-Brewmaster','Monk-Windwalker','Druid-Restoration','Priest-Discipline','Shaman-Enhancement','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','Druid-Feral','DeathKnight-Frost','Paladin-Protection','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCgcJDAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allila:BAABLgAECn8dAAIBAAcJNh3CEwDjAQABAAcJNh3CEwDjAQAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.',
Am='Ambrozyn:BAAALgAECgMJBAAAAA==.',
An='Andrew:BAAALgAECgYJCgAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgACAKoQAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAAALgADCgkJJwABLgAECgYJGwADADICAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAAALgAECgIJAwAAAA==.Arieljoyeria:BAACLgAFFH8MAAMEAAQJ4B7LAQB7AQAEAAQJ4B7LAQB7AQAFAAIJjA1YFACtAAAuAAQKfyIAAwUACAkoH+MNAMACAAUACAl5HeMNAMACAAQABAkqGNQMABwBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAGANgQAA==.',
As='Ashog:BAAALgAECgEJAQAAAA==.Astar:BAAALgADCgcJDgABLgAECggJHwAHAJYdAA==.Astraea:BAABLgAECn8mAAIIAAgJxBaDCwDCAQAIAAgJxBaDCwDCAQAAAA==.',
At='Athika:BAAALgADCgQJBAAAAA==.',
Au='Auddorn:BAAALgAECgMJBAAAAA==.Auria:BAAALgAECgYJEAAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAABLgAECn8hAAIBAAgJ1wtCKACXAQABAAgJ1wtCKACXAQAAAA==.Azralia:BAABLgAECn8dAAIJAAkJpxXDEABJAgAJAAkJpxXDEABJAgAAAA==.',
Bb='Bbygee:BAAALgAECgYJDgAAAA==.',
Be='Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgYJDwAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn81AAIKAAkJCwvjAgCtAQAKAAkJCwvjAgCtAQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAAALgAECgcJEgAAAA==.Borgin:BAAALgAECgYJDwAAAA==.Borimor:BAAALgAECgcJEQABLgAECgkJFgACAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAAALgAECgYJEAAAAA==.Bridgetta:BAAALgAECgEJAQAAAA==.Briëlla:BAABLgAECn8eAAMLAAgJCBSvSACiAQALAAgJCBSvSACiAQAMAAEJOgNOTQAVAAAAAA==.Bromdrago:BAAALgADCgYJAgAAAA==.Bromkin:BAAALgAECgYJCwAAAA==.',
Ca='Caalu:BAAALgADCgEJAgAAAA==.Calindala:BAAALgADCggJBAAAAA==.Calinor:BAAALgAECgIJAwAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAABLgAECn8VAAINAAYJvwaG8AAZAQANAAYJvwaG8AAZAQAAAA==.',
Ce='Ceran:BAABLgAECn8aAAIOAAcJTAyjHgAeAQAOAAcJTAyjHgAeAQAAAA==.Cereus:BAABLgAECn8fAAMHAAgJlh2PBACeAgAHAAgJlh2PBACeAgAPAAIJMxhEEwCMAAAAAA==.',
Ch='Chaelenge:BAABLgAECn8ZAAMJAAcJuB0tGAD7AQAJAAcJuB0tGAD7AQAQAAMJpQn8/QBeAAAAAA==.Cheatt:BAAALgADCggJBQAAAA==.Chubbabuns:BAABLgAECn8vAAMRAAgJeCQfAwC5AgARAAgJgSMfAwC5AgASAAYJ2yPDIQCXAQAAAA==.Chyran:BAAALgAECgYJBgAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8eAAITAAgJPBfMFQDbAQATAAgJPBfMFQDbAQAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAECgYJDwAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCgMJCAAAAA==.Dalielah:BAAALgAECgIJAgAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Denvoker:BAAALgAECgYJCQAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEAAAAA==.',
Di='Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Docqt:BAAALgADCgEJAQAAAA==.Dolleez:BAAALgAECgcJCAAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn8bAAIDAAYJMgI9UQBwAAADAAYJMgI9UQBwAAAAAA==.',
Du='Dunkaroo:BAABLgAECn8bAAIUAAgJshTMPgCCAQAUAAgJshTMPgCCAQAAAA==.',
['Dé']='Dékü:BAAALgAECgEJAgAAAA==.',
Ei='Eikinskaldi:BAAALgADCgUJCgAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAABLgAECn8ZAAIQAAgJEguEbABMAQAQAAgJEguEbABMAQAAAA==.',
Er='Eraessyr:BAAALgADCgcJBwAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECgYJCAAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgkJNQAVADoVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fr='Freakadeek:BAAALgAECgIJAgABLgAECggJEQAWAAAAAA==.Frosh:BAABLgAECn8YAAMGAAgJ2BB2OACgAQAGAAgJ2BB2OACgAQAXAAMJ4h2/bQCMAAAAAA==.Frìeren:BAABLgAECn8mAAINAAgJphSXUACqAQANAAgJphSXUACqAQAAAA==.',
Fu='Fuegaluna:BAAALgADCgcJBwAAAA==.Fundetected:BAABLgAECn8dAAIUAAkJTBiYKgDYAQAUAAkJTBiYKgDYAQAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gillarria:BAAALgADCgMJAwAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgADCggJBAAAAA==.Grimmberly:BAAALgAECgQJBAAAAA==.Grimmothy:BAABLgAECn8mAAIYAAgJgxT1FgC2AQAYAAgJgxT1FgC2AQAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Guthunnel:BAABLgAECn8pAAICAAkJEQ5GLwDPAQACAAkJEQ5GLwDPAQAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgADCgYJCgAAAA==.Hakuri:BAAALgADCgcJDwAAAA==.Hannibow:BAAALgAECgcJBwAAAA==.Happydru:BAAALgADCgcJDgAAAA==.',
He='Helle:BAABLgAECn8ZAAQVAAcJMBYyGwDGAQAVAAcJMBYyGwDGAQAYAAYJ6Aj0TQALAQAZAAEJrw0qcQAyAAAAAA==.',
Hi='Highfever:BAABLgAECn8UAAIaAAUJ3A2NWgDkAAAaAAUJ3A2NWgDkAAAAAA==.',
Ho='Hoawatt:BAAALgADCgEJAgAAAA==.Holynova:BAAALgADCgQJBwABLgAECgQJBAAWAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgkJKgAaAOgaAA==.Huuch:BAABLgAECn8dAAICAAgJFAp8UQBWAQACAAgJFAp8UQBWAQAAAA==.',
Hy='Hycinari:BAAALgAECgEJAQAAAA==.Hyperius:BAAALgADCgUJBQAAAA==.',
Ic='Icrucify:BAABLgAECn85AAICAAkJnyVdAgBFAwACAAkJnyVdAgBFAwAAAA==.',
Ig='Ignia:BAAALgAECgEJAQABLgAECgYJCAAWAAAAAA==.',
Il='Ilanos:BAAALgAECgEJAQAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAWAAAAAA==.',
Ir='Iremoon:BAABLgAECn8rAAMLAAkJ1xPzMAD2AQALAAkJ1xPzMAD2AQAMAAIJRwQTQgBCAAAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.',
Je='Jestyr:BAAALgAFFAEJAgAAAA==.Jestyrd:BAAALgAECgMJAwABLgAFFAEJAgAWAAAAAA==.Jestyrmo:BAABLgAECn8rAAMYAAgJARttGwCOAQAYAAcJ2BltGwCOAQAVAAgJgBD3KQBRAQABLgAFFAEJAgAWAAAAAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8IAAIZAAMJOxa9EwDhAAAZAAMJOxa9EwDhAAAuAAQKfz0AAxkACQmQJO8BAC8DABkACQmQJO8BAC8DABUAAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJDgAAAA==.',
Ka='Kaceya:BAAALgAECgQJBQAAAA==.Kainarasa:BAAALgAECgYJEwABLgAECgcJCAAWAAAAAA==.Katarinea:BAABLgAECn8ZAAIDAAcJmw7iLwAGAQADAAcJmw7iLwAGAQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Ke='Keats:BAAALgAECgEJAQAAAA==.',
Kh='Khalessie:BAABLgAECn8jAAIbAAgJXg2MHACQAQAbAAgJXg2MHACQAQAAAA==.Kheldar:BAAALgAECgcJAQAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMcAAkJpB4fBABoAgAcAAkJpB4fBABoAgAGAAEJeQFQrwAZAAAAAA==.',
Ko='Korkneelious:BAAALgAECgUJBQAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Ky='Kyomu:BAAALgADCggJCAABLgAECgcJCAAWAAAAAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn8fAAISAAYJ0hI9NAAqAQASAAYJ0hI9NAAqAQAAAA==.Liths:BAABLgAECn8qAAIdAAkJ7QgVDABBAQAdAAkJ7QgVDABBAQAAAA==.Littlemoses:BAABLgAECn8bAAICAAYJniF9NAC6AQACAAYJniF9NAC6AQAAAA==.',
Lo='Lockdarkly:BAAALgAECgMJBQAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAAALgAECgYJDwAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJEAAWAAAAAA==.Malendren:BAAALgAECgEJAQAAAA==.Malignus:BAABLgAECn8fAAINAAgJBxSTSADAAQANAAgJBxSTSADAAQABLgADCgkJFwAWAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECgcJGwANAOobAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgQJBQAAAA==.',
Mc='Mcdavé:BAABLgAECn8rAAIXAAkJUA6lIQCEAQAXAAkJUA6lIQCEAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECgcJHQABADYdAA==.Meerclar:BAAALgAECgIJAwABLgAECgMJBQAWAAAAAA==.Melaila:BAABLgAECn8rAAIGAAYJ9yR2EgCCAgAGAAYJ9yR2EgCCAgABLgAECggJJgAIAMQWAA==.Mellwynn:BAAALgAECgMJAwAAAA==.Melunaura:BAAALgADCggJCAABLgAECggJJgAIAMQWAA==.',
Mf='Mf:BAABLgAECn8cAAIUAAcJzxJtUgBAAQAUAAcJzxJtUgBAAQAAAA==.',
Mi='Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAAALgAECgUJDwAAAA==.Mongrol:BAAALgAECgQJBQAAAA==.Monju:BAAALgAECgEJAQAAAA==.Moonowl:BAAALgADCgEJAgAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJFAAaANwNAA==.',
Mu='Mummrakhan:BAAALgAECgEJAgAAAA==.',
Na='Naniel:BAACLgAFFH8JAAISAAMJMAv1IgDZAAASAAMJMAv1IgDZAAAuAAQKfyIAAhIACAmdExwsAAUCABIACAmdExwsAAUCAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBgAAAA==.Neb:BAABLgAECn80AAMeAAkJKhf6IgAaAgAeAAkJKhf6IgAaAgAfAAIJuRFWVwBoAAAAAA==.Necroy:BAAALgAFFAEJAgAAAA==.',
Ni='Niccee:BAABLgAECn8ZAAIDAAcJcg3uLQARAQADAAcJcg3uLQARAQAAAA==.Nick:BAACLgAFFH8RAAIeAAUJ+BuIEQBYAQAeAAUJ+BuIEQBYAQAuAAQKfxgAAx4ACAkYIykbALECAB4ACAkYIykbALECAB8AAQkAAHuAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAWAAAAAA==.',
No='Noodles:BAAALgAECgQJBwABLgAECgYJDAAWAAAAAA==.Nosebleeds:BAABLgAECn8VAAMIAAgJCx3fCQDjAQAIAAcJeBzfCQDjAQAgAAIJfxymKgBWAAAAAA==.Notyourheals:BAABLgAECn8fAAMXAAgJbA6vJwBaAQAXAAgJbA6vJwBaAQAGAAQJSAGjjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIaAAkJNxbwHgAIAgAaAAkJNxbwHgAIAgAAAA==.',
Od='Odsum:BAABLgAECn8XAAIQAAYJWBp7fQB/AQAQAAYJWBp7fQB/AQAAAA==.',
Oo='Oogrutamu:BAAALgAECgEJAQAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgIJAgAAAA==.Pandabear:BAAALgADCgYJBgAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papichulo:BAAALgAECgEJAQAAAA==.',
Pe='Percival:BAABLgAECn8ZAAIQAAcJyAv+gAAjAQAQAAcJyAv+gAAjAQAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAAALgAECgcJCAAAAA==.',
Po='Poetbrat:BAAALgADCgMJCQABLgAECgYJGwADADICAA==.Porkles:BAAALgADCgMJBAAAAA==.',
Pr='Praxiscannon:BAAALgAECgQJBAAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIPAAkJswtaBgCiAQAPAAkJswtaBgCiAQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAAALgAECgUJCgAAAA==.',
Qu='Queue:BAAALgAECgMJBQAAAA==.Quilten:BAAALgAECgYJDwAAAA==.',
Ra='Raenii:BAAALgAFFAEJAQABLgAECgkJFAATAHYXAA==.Ramoth:BAAALgAECgYJCQAAAA==.Ranoe:BAAALgADCgYJBgAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgAECgEJAQAAAA==.Rayne:BAABLgAECn8bAAINAAcJ6hucUgCkAQANAAcJ6hucUgCkAQAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8WAAMLAAcJFhCqmQBNAQALAAYJKRCqmQBNAQAhAAMJ0QxgFwCRAAAAAA==.',
Ri='Rinnian:BAAALgAECgYJDgAAAA==.Rinny:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgYJCQAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECgkJPAAYAGwUAA==.Robbiemonk:BAABLgAECn88AAMYAAkJbBSiEQDtAQAYAAkJbBSiEQDtAQAZAAQJ9wMTXgCYAAAAAA==.Robbiesboomy:BAAALgAECgEJAQABLgAECgkJPAAYAGwUAA==.Rodric:BAAALgADCgMJAwABLgAECgkJFgACAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgYJCAAAAA==.Sannith:BAABLgAECn8rAAINAAkJihLuOAD1AQANAAkJihLuOAD1AQAAAA==.Sapphi:BAABLgAECn8ZAAIiAAcJihBMFgAdAQAiAAcJihBMFgAdAQAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAAALgAECgYJEwAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAWAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shakjabuti:BAAALgADCgUJBQAAAA==.Shauralin:BAAALgAECgEJAQAAAA==.Shespawn:BAAALgAFFAIJAgAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMCAAkJqhDkLwDxAQACAAkJqhDkLwDxAQAjAAEJLQJiMgApAAAAAA==.Shykara:BAAALgADCgMJCQABLgAECgYJCQAWAAAAAA==.Shâdê:BAAALgAECgEJAQAAAA==.',
Si='Sins:BAAALgAECgEJAQAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slipperybop:BAABLgAECn8aAAIQAAkJVCL3CwDRAgAQAAkJVCL3CwDRAgABLgAECgYJBgAWAAAAAA==.Slugbow:BAAALgAECgIJAgAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIGAAkJZAZ/TwAPAQAGAAkJZAZ/TwAPAQAAAA==.Snoroll:BAAALgADCgEJAgAAAA==.',
So='Soldanis:BAAALgADCggJBAAAAA==.Sorena:BAAALgADCgMJCAAAAA==.',
Sp='Spawny:BAAALgADCgYJBgAAAA==.Spyman:BAAALgAECgEJAwAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8qAAIaAAkJ6BpGDQCyAgAaAAkJ6BpGDQCyAgAAAA==.',
St='Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAWAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgADCgEJAQAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJDQAAAA==.Sydonai:BAAALgADCgQJBAAAAA==.',
Ta='Tanderina:BAAALgAECgEJAQAAAA==.',
Te='Tellah:BAAALgAECggJEAABLgAECgQJDgAWAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgADCgkJCQABLgAECgcJCAAWAAAAAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgUJEwAWAAAAAA==.',
Tw='Twomz:BAABLgAECn8gAAIGAAcJ4g1hQABMAQAGAAcJ4g1hQABMAQAAAA==.',
Um='Umi:BAAALgAECgEJAQABLgAECgkJLgAGABocAA==.',
Un='Unclebenjinn:BAAALgAECgMJAwAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgkJFwANAA0hAA==.',
Va='Vavaboom:BAAALgADCggJCAAAAA==.',
Vi='Vindication:BAABLgAECn8YAAIJAAYJJCXMDAB7AgAJAAYJJCXMDAB7AgAAAA==.Viz:BAAALgADCgMJCQAAAA==.',
Vo='Voidshådow:BAAALgAECgYJCQAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vu='Vulpain:BAAALgADCgkJCQABLgAECgcJCAAWAAAAAA==.',
Vy='Vylandra:BAAALgADCgcJCQAAAA==.',
We='Weepingwillo:BAAALgAECgQJBAAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Whiteangel:BAAALgADCgcJEQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCAAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAAALgAECgIJAwAAAA==.',
Xa='Xaela:BAABLgAECn8YAAIUAAgJnxcRNwCgAQAUAAgJnxcRNwCgAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgMJBQAAAA==.Xarous:BAAALgADCgkJFAABLgAECgcJCAAWAAAAAA==.',
Xe='Xeon:BAAALgADCgcJCgAAAA==.',
Xi='Xiabal:BAABLgAECn8cAAMaAAcJYiHsEQB8AgAaAAcJYiHsEQB8AgADAAMJUhjuOwDKAAAAAA==.',
Xw='Xweakling:BAAALgAECgQJBAABLgAECgkJIwASAGccAA==.Xweekling:BAABLgAECn8jAAISAAkJZxyCCwBrAgASAAkJZxyCCwBrAgAAAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgADCgYJAgAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgMJCAAAAA==.',
Za='Zaraeth:BAAALgAECgIJAgABLgAECgMJBQAWAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zerostar:BAAALgAECgUJBgABLgAECgkJLQACAPwaAA==.Zevon:BAAALgADCgQJBAABLgAECgMJBQAWAAAAAA==.',
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
