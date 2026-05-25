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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Priest-Discipline','Paladin-Holy','Mage-Fire','Evoker-Augmentation','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','DemonHunter-Havoc','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Priest-Holy','Unknown-Unknown','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Elemental','Druid-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Paladin-Protection','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCggJFAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allila:BAABLgAECn8eAAIBAAgJghxyEQAmAgABAAgJghxyEQAmAgAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.',
Am='Ambrozyn:BAAALgAECgUJBgAAAA==.',
An='Andrew:BAAALgAECgYJCgAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgACAKoQAA==.Anna:BAAALgAECgYJBQAAAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAAALgADCgkJLwABLgAECgYJHAADADICAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAAALgAECgQJBgAAAA==.Arieljoyeria:BAACLgAFFH8NAAMEAAUJMh1/AgByAQAEAAQJ4B5/AgByAQAFAAMJhhBYFACtAAAuAAQKfyIAAwUACAkoH+MNAMACAAUACAl5HeMNAMACAAQABAkqGD8PABEBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAGANgQAA==.',
As='Ashog:BAAALgAECgIJAgAAAA==.Astar:BAAALgADCgcJDgABLgAECggJJQAHAJYdAA==.Astraea:BAABLgAECn8sAAIIAAgJrBjXCwDqAQAIAAgJrBjXCwDqAQAAAA==.',
At='Athika:BAAALgADCgcJCgAAAA==.',
Au='Auddorn:BAAALgAECgQJBQAAAA==.Auria:BAABLgAECn8WAAIJAAcJtRzmDgBUAgAJAAcJtRzmDgBUAgAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAACLgAFFH8FAAIBAAMJtAc4HwC9AAABAAMJtAc4HwC9AAAuAAQKfyEAAgEACAnXC0IoAJcBAAEACAnXC0IoAJcBAAAA.Azend:BAAALgADCgEJAQAAAA==.Azphrodite:BAAALgAECgMJAwAAAA==.Azralia:BAABLgAECn8dAAIKAAkJpxWRFQA5AgAKAAkJpxWRFQA5AgAAAA==.',
Ba='Barthamus:BAAALgADCgYJBgAAAA==.',
Bb='Bbygee:BAAALgAECgYJDgAAAA==.',
Be='Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgcJEQAAAA==.Benjaminadin:BAAALgAECgUJBQAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn88AAILAAkJBAxWAwC8AQALAAkJBAxWAwC8AQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAABLgAECn8ZAAMMAAgJ/BUiKgB0AQAMAAcJShQiKgB0AQAHAAcJiwpaKgAfAQAAAA==.Borgin:BAABLgAECn8UAAICAAYJ3QYHmADaAAACAAYJ3QYHmADaAAAAAA==.Borimor:BAABLgAECn8YAAINAAcJdgQrxQDdAAANAAcJdgQrxQDdAAABLgAECgkJFgACAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAABLgAECn8UAAMOAAYJQQ6bPADqAAAOAAYJQQ6bPADqAAAPAAEJuAMHiQAmAAABLgAECgkJLwAQAPcZAA==.Bridgetta:BAAALgAECgIJAgAAAA==.Briëlla:BAABLgAECn8vAAQQAAkJ9xnjIABiAgAQAAkJ9xnjIABiAgARAAEJDQh3LgAnAAASAAEJOgOBWQAUAAAAAA==.Bromdrago:BAAALgAECgEJAQAAAA==.Bromkin:BAAALgAECgYJEAAAAA==.',
Ca='Caalu:BAAALgADCgEJAgAAAA==.Calindala:BAAALgADCggJBAAAAA==.Calinor:BAAALgAECgIJBQAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAABLgAECn8aAAITAAYJCQeG8AAZAQATAAYJCQeG8AAZAQAAAA==.',
Ce='Ceran:BAABLgAECn8mAAIUAAgJShEIGACMAQAUAAgJShEIGACMAQAAAA==.Cereus:BAABLgAECn8lAAMHAAgJlh2VBQCXAgAHAAgJlh2VBQCXAgAVAAcJ5BXkBwCWAQAAAA==.',
Ch='Chaelenge:BAABLgAECn8jAAMKAAgJUR/XCQDJAgAKAAgJUR/XCQDJAgANAAMJpQkzJQFaAAAAAA==.Cheatt:BAAALgAECgEJAQAAAA==.Chubbabuns:BAABLgAECn8xAAMWAAkJ1ySsAQAmAwAWAAkJ/yOsAQAmAwAXAAYJ2yPrKgCEAQAAAA==.Chyran:BAAALgAECgYJBgAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8hAAIYAAgJCRmUFQAAAgAYAAgJCRmUFQAAAgAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAECgYJDwAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.',
['Cò']='Còffee:BAAALgADCgkJCQABLgAECgYJEgAZAAAAAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCgMJCwAAAA==.Dalielah:BAAALgAECgMJBQAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Demdots:BAAALgADCgEJAQAAAA==.Denvoker:BAAALgAECgYJDAAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEAAAAA==.',
Di='Diddykong:BAAALgAECgkJCQAAAA==.Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Docqt:BAAALgADCgEJAQAAAA==.Dolleez:BAAALgAECgcJCAAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn8cAAIDAAYJMgI+XQBsAAADAAYJMgI+XQBsAAAAAA==.',
Du='Dunkaroo:BAABLgAECn8dAAIaAAgJsxTWSgCDAQAaAAgJsxTWSgCDAQAAAA==.',
['Dé']='Dékü:BAAALgAECgEJAgAAAA==.',
Ei='Eikinskaldi:BAAALgAECgEJAQAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAABLgAECn8ZAAINAAgJEgsygABOAQANAAgJEgsygABOAQAAAA==.',
Er='Eraessyr:BAAALgADCgcJBwAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECgYJCAAAAA==.Fandris:BAAALgAECgEJAQAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgkJOgAbADoVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fr='Freakadeek:BAAALgAECgMJBAABLgAECgkJFQARAGsNAA==.Frosh:BAABLgAECn8YAAMGAAgJ2BB2OACgAQAGAAgJ2BB2OACgAQAcAAMJ4h2/bQCMAAAAAA==.Frìeren:BAABLgAECn8oAAITAAkJ1hNaQwD2AQATAAkJ1hNaQwD2AQAAAA==.',
Fu='Fuegaluna:BAAALgADCgcJBwAAAA==.Fundetected:BAABLgAECn8nAAIaAAkJ0RmdGgBXAgAaAAkJ0RmdGgBXAgAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gillarria:BAAALgADCgMJAwAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgAECgEJAQAAAA==.Grimmberly:BAAALgAECgcJDAAAAA==.Grimmothy:BAABLgAECn8oAAIOAAgJtxRsGQC8AQAOAAgJtxRsGQC8AQAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Guthunnel:BAABLgAECn8yAAICAAkJvhJ2LAABAgACAAkJvhJ2LAABAgAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgAECgEJAQAAAA==.Hakuri:BAAALgADCgcJDwABLgAECgQJBQAZAAAAAA==.Hannibow:BAAALgAECgcJBwAAAA==.Happydru:BAAALgADCgcJDgAAAA==.',
He='Helle:BAABLgAECn8cAAQbAAcJoxYOIQDOAQAbAAcJoxYOIQDOAQAOAAYJ6Aj0TQALAQAPAAEJrw0uggAwAAAAAA==.',
Hi='Highfever:BAABLgAECn8UAAIdAAUJ3A0VZQDlAAAdAAUJ3A0VZQDlAAAAAA==.',
Ho='Hoawatt:BAAALgADCgEJAgAAAA==.Holynova:BAAALgADCgQJBwABLgAECgQJBAAZAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgkJMwAdAIIbAA==.Huuch:BAABLgAECn8kAAICAAkJAQv2QwCqAQACAAkJAQv2QwCqAQAAAA==.',
Hy='Hycinari:BAAALgAECgEJAQAAAA==.Hyperius:BAAALgAECgUJBQAAAA==.',
Ic='Icrucify:BAABLgAECn85AAICAAkJoCVGBAAwAwACAAkJoCVGBAAwAwAAAA==.',
Ig='Ignia:BAAALgAECgEJAQABLgAECgYJCAAZAAAAAA==.',
Il='Ilanos:BAAALgAECgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAZAAAAAA==.',
Ir='Iremoon:BAABLgAECn80AAMQAAkJTRU5LAAsAgAQAAkJTRU5LAAsAgASAAIJRwQTQgBCAAAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.',
Je='Jestyr:BAAALgAFFAIJBAAAAA==.Jestyrd:BAAALgAECgMJAwABLgAFFAIJBAAZAAAAAA==.Jestyrmo:BAABLgAECn8rAAMOAAgJARsMIACIAQAOAAcJ2BkMIACIAQAbAAgJgBB3MwBVAQABLgAFFAIJBAAZAAAAAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8NAAIPAAMJqR0gEwADAQAPAAMJqR0gEwADAQAuAAQKf0YAAw8ACQnwJLYBAEwDAA8ACQnwJLYBAEwDABsAAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJDwAAAA==.',
Ka='Kaceya:BAAALgAECgQJBQAAAA==.Kainarasa:BAAALgAECgYJEwABLgAECgcJCgAZAAAAAA==.Katarinea:BAABLgAECn8bAAIDAAgJkw0bLwA0AQADAAgJkw0bLwA0AQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Ke='Keats:BAAALgAECgIJAgAAAA==.',
Kh='Khalessie:BAABLgAECn8lAAIJAAkJOQ1fGwDGAQAJAAkJOQ1fGwDGAQAAAA==.Kheldar:BAAALgAECgcJAQAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMeAAkJpB71BQBQAgAeAAkJpB71BQBQAgAGAAEJeQE2yQAZAAAAAA==.Kiselle:BAAALgAECgEJAQAAAA==.',
Ko='Korkneelious:BAAALgAECgYJBwAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Ky='Kyomu:BAAALgADCggJCAABLgAECgcJCgAZAAAAAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn8kAAIXAAYJehMxOwAxAQAXAAYJehMxOwAxAQAAAA==.Liths:BAABLgAECn8zAAIfAAkJDwlLDgA+AQAfAAkJDwlLDgA+AQAAAA==.Littlemoses:BAABLgAECn8hAAICAAcJwB59LwD1AQACAAcJwB59LwD1AQAAAA==.',
Lo='Lockdarkly:BAAALgAECgQJBgAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAAALgAECgYJEQAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJEAAZAAAAAA==.Malendren:BAAALgAECgEJAQAAAA==.Malignus:BAABLgAECn8lAAITAAgJ9Rb+SADlAQATAAgJ9Rb+SADlAQABLgADCgkJFwAZAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECggJJQATAAMcAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgcJCwAAAA==.',
Mc='Mcdavé:BAABLgAECn80AAIcAAkJsw5nJQCRAQAcAAkJsw5nJQCRAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECggJHgABAIIcAA==.Meerclar:BAAALgAECgIJAwABLgAECgQJBgAZAAAAAA==.Melaila:BAABLgAECn8zAAIGAAcJ9iN2EgCCAgAGAAcJ9iN2EgCCAgABLgAECggJLAAIAKwYAA==.Mellwynn:BAAALgAECgMJAwAAAA==.Melunaura:BAAALgADCggJCAABLgAECggJLAAIAKwYAA==.',
Mf='Mf:BAABLgAECn8cAAIaAAcJ0BJBXQBNAQAaAAcJ0BJBXQBNAQAAAA==.',
Mi='Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgAECgIJAQAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAAALgAECgYJEAAAAA==.Mongrol:BAAALgAECgQJBQAAAA==.Monju:BAAALgAECgEJAQAAAA==.Moonowl:BAAALgADCgEJAgAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJFAAdANwNAA==.',
Mu='Mummrakhan:BAAALgAECgUJBwAAAA==.',
Na='Naniel:BAACLgAFFH8KAAIXAAQJ6AhQIAAEAQAXAAQJ6AhQIAAEAQAuAAQKfyYAAhcACAnGExwsAAUCABcACAnGExwsAAUCAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBwAAAA==.Neb:BAABLgAECn88AAMgAAkJDRkPHQBcAgAgAAkJDRkPHQBcAgAhAAIJuRFWVwBoAAAAAA==.Necroy:BAAALgAFFAEJAgAAAA==.',
Ni='Niccee:BAABLgAECn8eAAIDAAgJSg3xKgBNAQADAAgJSg3xKgBNAQAAAA==.Nick:BAACLgAFFH8RAAIgAAUJ+BuIEQBYAQAgAAUJ+BuIEQBYAQAuAAQKfxgAAyAACAkYIykbALECACAACAkYIykbALECACEAAQkAAHuAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAZAAAAAA==.',
No='Noodles:BAAALgAECgQJBwABLgAECgcJHQAaAL4WAA==.Nosebleeds:BAABLgAECn8VAAMIAAgJCh1TDADiAQAIAAcJdxxTDADiAQAiAAIJfxwYMwBVAAAAAA==.Notyourheals:BAABLgAECn8jAAMcAAgJEA8sLgBcAQAcAAgJEA8sLgBcAQAGAAQJSAGjjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIdAAkJNxYAJAAIAgAdAAkJNxYAJAAIAgAAAA==.',
Od='Odsum:BAABLgAECn8XAAINAAYJWBr0cABsAQANAAYJWBr0cABsAQAAAA==.',
Oo='Oogrutamu:BAAALgAECgIJAgAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgMJBAAAAA==.Pandabear:BAAALgADCgkJDwAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papichulo:BAAALgAECgIJAgAAAA==.',
Pe='Percival:BAABLgAECn8jAAINAAgJYg29bwBvAQANAAgJYg29bwBvAQAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAAALgAECgcJCgAAAA==.',
Po='Poetbrat:BAAALgADCgMJDAABLgAECgYJHAADADICAA==.Porkles:BAAALgADCgMJBAAAAA==.',
Pr='Praxiscannon:BAAALgAECgQJBAAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIVAAkJswvOBwCaAQAVAAkJswvOBwCaAQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAAALgAECgYJEAAAAA==.',
Qu='Queue:BAAALgAECgMJCgAAAA==.Quilten:BAABLgAECn8UAAIPAAYJFgqePgDYAAAPAAYJFgqePgDYAAAAAA==.',
Ra='Raenii:BAAALgAFFAEJAQABLgAECgkJFQAYAHYXAA==.Ramoth:BAAALgAECgYJDAAAAA==.Ranoe:BAAALgADCgYJBgAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgAECgIJAgAAAA==.Rayne:BAABLgAECn8lAAITAAgJAxwwQAAAAgATAAgJAxwwQAAAAgAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8cAAMQAAgJrg7riQArAQAQAAcJng7riQArAQARAAQJLQu5GgCuAAAAAA==.',
Ri='Rinnian:BAAALgAECgYJDwAAAA==.Rinny:BAAALgAECgEJAQAAAA==.Riptideaf:BAAALgADCgIJAgAAAA==.',
Ro='Roadwanderer:BAAALgAECgYJCgAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECgkJQgAOAC4aAA==.Robbiemonk:BAABLgAECn9CAAMOAAkJLho1CwBjAgAOAAkJLho1CwBjAgAPAAQJ9wMTXgCYAAAAAA==.Robbiesboomy:BAAALgAECgIJAgABLgAECgkJQgAOAC4aAA==.Rodric:BAAALgADCgMJAwABLgAECgkJFgACAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgYJDQAAAA==.Sannith:BAABLgAECn80AAITAAkJrxOkPAAMAgATAAkJrxOkPAAMAgAAAA==.Sapphi:BAABLgAECn8jAAIjAAgJ9Q9hFABZAQAjAAgJ9Q9hFABZAQAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAAALgAECgYJEwAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAZAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shakjabuti:BAAALgADCgUJBQAAAA==.Shauralin:BAAALgAECgEJAQAAAA==.Shespawn:BAAALgAFFAIJAgAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMCAAkJqhDkLwDxAQACAAkJqhDkLwDxAQAkAAEJLQJiMgApAAAAAA==.Shykara:BAAALgADCgMJDAABLgAECgYJDAAZAAAAAA==.Shâdê:BAAALgAECgEJAgAAAA==.',
Si='Sindrak:BAAALgAECgEJAQAAAA==.Sins:BAAALgAECgIJAgAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slipperybop:BAACLgAFFH8JAAINAAMJFBoUOwAUAQANAAMJFBoUOwAUAQAuAAQKfxoAAg0ACQlUIk8RAMMCAA0ACQlUIk8RAMMCAAEuAAQKBgkGABkAAAAA.Slugbow:BAAALgAECgIJAgAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIGAAkJZAZvXQAMAQAGAAkJZAZvXQAMAQAAAA==.Snoroll:BAAALgADCgEJAgAAAA==.',
So='Soldanis:BAAALgAECgEJAQAAAA==.Sorena:BAAALgADCgMJCAAAAA==.',
Sp='Spawny:BAAALgADCgYJBgAAAA==.Spyman:BAAALgAECgEJBAAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8zAAIdAAkJghuXDgDEAgAdAAkJghuXDgDEAgAAAA==.',
St='Starz:BAAALgADCgkJCQAAAA==.Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAZAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgADCgEJAQAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJDQAAAA==.Sydonai:BAAALgADCgQJBAAAAA==.',
Ta='Tanderina:BAAALgAECgIJAgAAAA==.',
Te='Tellah:BAAALgAECggJEgABLgAECgQJDgAZAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgADCgkJCQABLgAECgcJCgAZAAAAAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgUJFAAYAHwVAA==.',
Tw='Twomz:BAABLgAECn8mAAMGAAgJEQ1uRABpAQAGAAgJEQ1uRABpAQAcAAEJAACSogAAAAAAAA==.',
Um='Umi:BAAALgAECgEJAQABLgAECgkJLgAGABkcAA==.',
Un='Unclebenjinn:BAAALgAECgMJAwAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgkJFwATAA0hAA==.',
Va='Varrieto:BAAALgAECgcJBwAAAA==.Vavaboom:BAAALgADCggJCAAAAA==.',
Ve='Veirlyn:BAAALgAECgkJCQAAAA==.',
Vi='Vindication:BAABLgAECn8eAAIKAAcJgST1CADWAgAKAAcJgST1CADWAgAAAA==.Viz:BAAALgADCgMJDAAAAA==.',
Vo='Voidshådow:BAAALgAECgYJDAAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vu='Vulpain:BAAALgAECgYJBgABLgAECgcJCgAZAAAAAA==.',
Vy='Vylandra:BAAALgADCgcJCQAAAA==.',
We='Weepingwillo:BAAALgAECgQJBAAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Whiteangel:BAAALgADCgcJEQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCAAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAAALgAECgIJBQAAAA==.',
Xa='Xaela:BAABLgAECn8bAAIaAAkJEhcELwDrAQAaAAkJEhcELwDrAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgQJBgAAAA==.Xarous:BAAALgADCgkJFAABLgAECgcJCgAZAAAAAA==.',
Xe='Xeon:BAAALgAECgEJAQAAAA==.',
Xi='Xiabal:BAABLgAECn8mAAMdAAgJGyGhCgD0AgAdAAgJGyGhCgD0AgADAAQJ0hdzNwAFAQAAAA==.',
Xw='Xweakling:BAAALgAECgcJCQABLgAFFAQJBgAXAC0aAA==.Xweekling:BAACLgAFFH8GAAIXAAQJLRq8DgBcAQAXAAQJLRq8DgBcAQAuAAQKfyMAAhcACQlmHOMPAFcCABcACQlmHOMPAFcCAAAA.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgAECgEJAQAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgMJCwAAAA==.',
Za='Zaraeth:BAAALgAECgQJBAABLgAECgQJBgAZAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zerostar:BAAALgAECgUJCAABLgAECgkJLgACAP0aAA==.Zevon:BAAALgADCgQJBAABLgAECgQJBgAZAAAAAA==.',
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
