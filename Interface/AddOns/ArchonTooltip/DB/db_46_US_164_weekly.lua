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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Priest-Discipline','Paladin-Holy','Paladin-Retribution','Mage-Fire','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Mage-Frost','DemonHunter-Havoc','Priest-Holy','Unknown-Unknown','Druid-Restoration','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Monk-Mistweaver','Shaman-Elemental','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Druid-Feral','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCggJFAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ae='Aestel:BAAALgADCgEJAQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allesar:BAAALgAECgcJEwAAAA==.Allila:BAABLgAECn8eAAIBAAgJghwpFgAaAgABAAgJghwpFgAaAgAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.Aloysia:BAAALgADCgUJBQAAAA==.',
Am='Ambrozyn:BAAALgAECggJDgAAAA==.',
An='Andrew:BAAALgAECgYJCgAAAA==.Anik:BAAALgAECgYJBwAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgACAKoQAA==.Anna:BAABLgAFFH8LAAIBAAUJPBwpEwBNAQABAAUJPBwpEwBNAQAAAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAABLgAECn8WAAIBAAYJtQOVEgBjAAABAAYJtQOVEgBjAAABLgAECggJOgADANUEAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAABLgAECn8YAAIEAAgJdAswOwBZAQAEAAgJdAswOwBZAQAAAA==.Arieljoyeria:BAACLgAFFH8PAAMFAAUJMh0EBABPAQAFAAQJ4B4EBABPAQAGAAMJLxlYFACtAAAuAAQKfyQAAwYACQmZH+MNAMACAAYACQkfHuMNAMACAAUABAkqGOIRAAcBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAHANgQAA==.',
As='Ashog:BAAALgAECgIJAgAAAA==.Astar:BAAALgAECgEJAQABLgAFFAMJCwAIAFQfAA==.Astraea:BAABLgAECn9MAAIJAAgJKR8gAQBEAgAJAAgJKR8gAQBEAgABLgAECgkJPAAHAFMiAA==.',
At='Athika:BAAALgAECgEJAQAAAA==.',
Au='Auddorn:BAAALgAECgYJDAAAAA==.Auria:BAABLgAECn8cAAIKAAkJJx3LDACgAgAKAAkJJx3LDACgAgAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAACLgAFFH8JAAIBAAMJ6wn6KQCvAAABAAMJ6wn6KQCvAAAuAAQKfyEAAgEACAnXC0IoAJcBAAEACAnXC0IoAJcBAAAA.Azend:BAAALgAECgIJAgAAAA==.Azphrodite:BAAALgAECgYJBgAAAA==.Azralia:BAABLgAECn8eAAMLAAkJpxXLGgAuAgALAAkJpxXLGgAuAgAMAAEJFg68SAAwAAAAAA==.',
Ba='Baconator:BAAALgAECgEJAQAAAA==.Barthamus:BAAALgADCgYJBgAAAA==.',
Bb='Bbygee:BAAALgAECgYJEwAAAA==.',
Be='Bearlyshådow:BAAALgADCgUJBQAAAA==.Beastlegion:BAAALgADCgYJEgAAAA==.Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgcJEwAAAA==.Benjaminadin:BAAALgAECgUJEQAAAA==.Berris:BAAALgADCgYJBgAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8+AAINAAkJJAwXBQCMAQANAAkJJAwXBQCMAQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAABLgAECn8cAAQOAAkJUxcgMgBtAQAOAAcJShQgMgBtAQAIAAcJiwpaKgAfAQAPAAEJsiCEHQBiAAAAAA==.Boop:BAAALgADCgkJCQABLgAECgkJJAAMAKAjAA==.Borgin:BAABLgAECn8VAAICAAYJ3QaVtwDWAAACAAYJ3QaVtwDWAAAAAA==.Borgofdeth:BAAALgAECgEJAQAAAA==.Borimor:BAABLgAECn8fAAIMAAcJcAxFpgAuAQAMAAcJcAxFpgAuAQABLgAECgkJFgACAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAABLgAECn8eAAMQAAYJwhHJOQAVAQAQAAYJwhHJOQAVAQARAAEJuAMHiQAmAAABLgAECgkJQQASAPocAA==.Bridgetta:BAAALgAECgIJAgAAAA==.Brisli:BAAALgADCgcJBwABLgAECgkJHAAKACcdAA==.Briëlla:BAABLgAECn9BAAQSAAkJ+hyOGQCtAgASAAkJ+hyOGQCtAgATAAEJDQjpQAAlAAAUAAEJOgMAbQASAAAAAA==.Bromdrago:BAAALgAECgEJAQAAAA==.Bromkin:BAABLgAECn8YAAIVAAgJmxqZGABYAQAVAAgJmxqZGABYAQAAAA==.',
Bu='Bubonics:BAAALgADCgIJAgAAAA==.',
['Bë']='Bëorn:BAAALgAECgUJBQABLgAECgkJFgACAKoQAA==.',
Ca='Calindala:BAAALgADCggJBAAAAA==.Calinor:BAABLgAECn8WAAIMAAQJ/RrbEgD9AAAMAAQJ/RrbEgD9AAAAAA==.Carl:BAAALgAECgkJDwAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAABLgAECn8aAAIWAAYJCQeG8AAZAQAWAAYJCQeG8AAZAQAAAA==.',
Ce='Ceran:BAABLgAECn8yAAIXAAkJ6hNDFADvAQAXAAkJ6hNDFADvAQAAAA==.Cereus:BAACLgAFFH8LAAMIAAMJVB9cCAD+AAAIAAMJVB9cCAD+AAAPAAIJpwwDCgCHAAAuAAQKf0EAAwgACQkXJPMAAKsDAAgACQkXJPMAAKsDAA8ACQktG+gCAH4CAAAA.',
Ch='Chaelenge:BAABLgAECn8lAAMLAAkJSh5iCAAFAwALAAkJSh5iCAAFAwAMAAMJpQlLWwFWAAAAAA==.Cheatt:BAAALgAECgEJAQAAAA==.Chyran:BAABLgAECn8UAAMMAAgJJAs1FQDnAAAMAAgJJAs1FQDnAAALAAIJHRY5bQCBAAAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8lAAIYAAkJ4RhPFAA0AgAYAAkJ4RhPFAA0AgAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAFFAIJAwAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.Cutecop:BAAALgAECgIJBAAAAA==.',
['Có']='Cóffee:BAAALgADCgkJCQAAAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCggJEwAAAA==.Dalielah:BAAALgAECgUJBwAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.Darkkstarr:BAAALgAECgEJAgAAAA==.Daromiciah:BAAALgAECgIJAgAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Demdots:BAAALgADCgEJAQAAAA==.Denvoker:BAABLgAECn8VAAQIAAgJBg4dHwD+AAAIAAYJrAodHwD+AAAOAAMJ5gV8FAA9AAAPAAEJAADhLwAAAAAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.Desmac:BAAALgAECgYJBgABLgAFFAIJAgAZAAAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEQAAAA==.',
Di='Diddykong:BAAALgAECgkJCQAAAA==.Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Docqt:BAAALgADCgEJAQAAAA==.Dolleez:BAAALgAECgcJCAAAAA==.Doodridder:BAAALgAECgQJBAAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgUJBQAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn86AAMDAAgJ1QTSCwChAAADAAgJ1QTSCwChAAAaAAIJiAE6+AAbAAAAAA==.',
Dr='Dragii:BAAALgAECgMJBAAAAA==.',
Du='Dunkaroo:BAABLgAECn8eAAIbAAkJMhQFRAC8AQAbAAkJMhQFRAC8AQAAAA==.',
['Dé']='Dékü:BAAALgAECgcJCgAAAA==.',
Ei='Eikinskaldi:BAAALgAECgEJAgAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.Elphysa:BAAALgADCgIJAgAAAA==.',
Em='Empty:BAABLgAECn8mAAIMAAkJ5gzsdgCAAQAMAAkJ5gzsdgCAAQAAAA==.',
En='Endormu:BAAALgAECgIJAgAAAA==.',
Ep='Epiduralrot:BAACLgAFFH8SAAQcAAYJbBPZDQDGAAAcAAQJLAjZDQDGAAAdAAMJYhBYhAC9AAAeAAIJlyBVDwCYAAAuAAQKfyYABB0ACAneHrguAFICAB0ACAleG7guAFICABwABAn1GWAiAEMBAB4AAwlJIsUSAAABAAAA.',
Er='Eraessyr:BAAALgADCgcJDQAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECggJCgAAAA==.Fandris:BAAALgAECgEJAQAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgkJRwAfAOEVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fl='Flaregun:BAAALgAECgIJAwABLgAECgkJDwAZAAAAAA==.',
Fo='Forsëti:BAAALgAECgIJAgAAAA==.',
Fr='Freakadeek:BAAALgAECgMJBAABLgAECgkJFQATAGsNAA==.Frosh:BAABLgAECn8YAAMHAAgJ2BB2OACgAQAHAAgJ2BB2OACgAQAgAAMJ4h2/bQCMAAAAAA==.Frìeren:BAABLgAECn8oAAIWAAkJ1hNMUwDjAQAWAAkJ1hNMUwDjAQAAAA==.',
Fu='Fuegaluna:BAAALgADCgkJCwAAAA==.Fundetected:BAACLgAFFH8IAAIbAAMJOA2nbQCvAAAbAAMJOA2nbQCvAAAuAAQKfysAAhsACQl8GpYeAF0CABsACQl8GpYeAF0CAAAA.',
['Fâ']='Fâllenboy:BAAALgAECgMJAwAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gilidar:BAABLgAECn8xAAMhAAkJ1yTkAgARAwAhAAkJ/yPkAgARAwAEAAYJ2yNsNAB5AQAAAA==.Gillarria:BAAALgAECgUJDQAAAA==.',
Gn='Gnomerdenis:BAAALgADCgUJBgAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgAECgMJAwAAAA==.Grimmberly:BAAALgAECgcJDAABLgAFFAEJAgAZAAAAAA==.Grimmothy:BAABLgAECn8sAAIQAAkJ3BafEgAfAgAQAAkJ3BafEgAfAgABLgAFFAEJAgAZAAAAAA==.Grimoire:BAAALgAFFAEJAgAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Gutdrunel:BAAALgAECgMJAwAAAA==.Guthumwar:BAAALgAECgYJBgAAAA==.Guthunnel:BAABLgAECn86AAICAAkJvhIgOgD2AQACAAkJvhIgOgD2AQAAAA==.Gutshadra:BAAALgAECgYJAgAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgAECgIJAgAAAA==.Hakuri:BAAALgADCgcJDwABLgAECgYJDQAZAAAAAA==.Hannibow:BAAALgAECgcJCAAAAA==.Happydru:BAAALgADCgcJDgAAAA==.Havic:BAAALgADCgYJBgAAAA==.Hazuki:BAAALgAECgEJAgAAAA==.',
He='Helle:BAABLgAECn8gAAQfAAkJuxRaHQAuAgAfAAkJuxRaHQAuAgAQAAYJ6Aj0TQALAQARAAIJ7g9KDwBgAAAAAA==.Hellgrim:BAAALgADCgEJAQABLgAFFAEJAgAZAAAAAA==.',
Hi='Highfever:BAABLgAECn8UAAIaAAUJ3A32cADiAAAaAAUJ3A32cADiAAAAAA==.',
Ho='Hoawatt:BAAALgAECgQJBAAAAA==.Holynova:BAAALgADCgQJBwABLgAECgQJBAAZAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgkJMwAaAIIbAA==.Huuch:BAABLgAECn8oAAICAAkJEAs4VgChAQACAAkJEAs4VgChAQAAAA==.',
Hy='Hycinari:BAAALgAECgIJAgAAAA==.Hyperius:BAAALgAECgUJBQAAAA==.',
Ic='Icrucify:BAACLgAFFH8FAAICAAMJ6RwlFQCwAAACAAMJ6RwlFQCwAAAuAAQKfzkAAgIACQmgJUQIABkDAAIACQmgJUQIABkDAAAA.',
Ig='Ignee:BAABLgAFFH8IAAMiAAMJRBMdEQB+AAAEAAMJpAT/PgCsAAAiAAIJnBgdEQB+AAAAAA==.Ignia:BAAALgAECgEJAQABLgAECggJCgAZAAAAAA==.',
Il='Ilanos:BAAALgAECgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAZAAAAAA==.',
Ir='Iremoon:BAABLgAECn88AAMSAAkJkxWwNgAkAgASAAkJkxWwNgAkAgAUAAIJRwQTQgBCAAABLgAFFAIJCAAMAJEQAA==.Iridio:BAAALgAECgYJBgAAAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.Jaeler:BAAALgAECgYJDAAAAA==.',
Je='Jedistang:BAAALgAECgQJBgAAAA==.Jestyr:BAACLgAFFH8RAAMXAAQJaRgiDgA1AQAXAAQJaRgiDgA1AQAjAAIJAxVFBQCJAAAuAAQKfxYAAxcACQlUH2IGANECABcACQlUH2IGANECABsAAQmBB28oASUAAAAA.Jestyrd:BAAALgAECgMJAwABLgAFFAQJEQAXAGkYAA==.Jestyrdk:BAAALgAFFAEJAgABLgAFFAQJEQAXAGkYAA==.Jestyrmo:BAABLgAECn8rAAMQAAgJARtiJQCDAQAQAAcJ2BliJQCDAQAfAAgJgBCxRABZAQABLgAFFAQJEQAXAGkYAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8eAAIRAAQJ4R+KBAA8AQARAAQJ4R+KBAA8AQAuAAQKf0wAAxEACQnwJKgCAEADABEACQnwJKgCAEADAB8AAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJEwAAAA==.',
Ju='Jules:BAAALgAFFAIJAgAAAA==.Jumbo:BAAALgAECgMJBAAAAA==.',
Ka='Kaceya:BAAALgAECgUJDQAAAA==.Kainarasa:BAAALgAECgYJEwABLgAECgkJJAAMAKAjAA==.Kairn:BAAALgADCgYJBgAAAA==.Kairnei:BAAALgADCgYJBwAAAA==.Katarinea:BAABLgAECn8fAAIDAAkJiw7DKgB/AQADAAkJiw7DKgB/AQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Ke='Keats:BAAALgAECgIJAgAAAA==.Keeytz:BAAALgADCgYJAgAAAA==.',
Kh='Khalessie:BAABLgAECn8lAAIKAAkJOQ3PIwCwAQAKAAkJOQ3PIwCwAQAAAA==.Kheldar:BAAALgAECgcJAQAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMkAAkJpB5LCABBAgAkAAkJpB5LCABBAgAHAAEJeQHi9gAZAAAAAA==.Kiselle:BAAALgAECgQJBAABLgAECgkJHAAKACcdAA==.',
Kl='Klorick:BAAALgAECgYJBgABLgAECgkJFgACAKoQAA==.',
Ko='Korkneelious:BAAALgAECgYJDAAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Ku='Kungfudru:BAAALgADCgcJBwAAAA==.',
Kw='Kwai:BAAALgAECgYJBgABLgAECgkJFgACAKoQAA==.',
Ky='Kyomu:BAAALgAECgcJBwABLgAECgkJJAAMAKAjAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn9EAAIEAAcJEhwCBACMAQAEAAcJEhwCBACMAQAAAA==.Liths:BAABLgAECn87AAIjAAkJlAlIEQA4AQAjAAkJlAlIEQA4AQAAAA==.Littlemoses:BAABLgAECn8nAAICAAkJiRsuLwAgAgACAAkJiRsuLwAgAgAAAA==.',
Lo='Lockdarkly:BAAALgAECgUJCQAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAABLgAECn8VAAMKAAYJIxV5KQCIAQAKAAYJIxV5KQCIAQAYAAUJZwk5UwDqAAAAAA==.Lulzimadrood:BAAALgADCgMJAwAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJEQAZAAAAAA==.Malendren:BAAALgAECgEJAQAAAA==.Malignus:BAABLgAECn82AAIWAAkJXx+yIgCSAgAWAAkJXx+yIgCSAgABLgADCgkJFwAZAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECgkJJwAWAAIdAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgcJCwAAAA==.Marriah:BAAALgAECgMJAwABLgAECgkJJwACAIkbAA==.Mavane:BAAALgADCgUJAQAAAA==.Mawhriccio:BAAALgADCgEJAQAAAA==.',
Mc='Mcdavé:BAABLgAECn88AAIgAAkJyxCNJwCwAQAgAAkJyxCNJwCwAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECggJHgABAIIcAA==.Meerclar:BAAALgAECgIJAwABLgAECgcJDgAZAAAAAA==.Melaila:BAABLgAECn88AAIHAAkJUyL6DgDbAgAHAAkJUyL6DgDbAgAAAA==.Mellwynn:BAAALgAECgUJDwAAAA==.Melunaura:BAAALgAECggJCQABLgAECgkJPAAHAFMiAA==.',
Mf='Mf:BAABLgAECn8hAAIbAAcJtxRaaABVAQAbAAcJtxRaaABVAQAAAA==.',
Mi='Micheal:BAAALgAFFAIJAgAAAA==.Midir:BAAALgAECgQJBAAAAA==.Miladrayn:BAAALgADCgcJDAAAAA==.Mimikyu:BAAALgAFFAEJAQABLgAFFAcJHQAgAJwdAA==.Min:BAAALgAECgIJAgAAAA==.Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgAECgIJAgAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAABLgAECn84AAIVAAkJayUtAABIAwAVAAkJayUtAABIAwAAAA==.Monalina:BAAALgAECgkJBwAAAA==.Mongrol:BAAALgAECgQJBgAAAA==.Monju:BAAALgAECgEJAQAAAA==.Moonowl:BAAALgAECgQJBQAAAA==.Mordecai:BAAALgADCgIJAQABLgAECgkJDwAZAAAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJFAAaANwNAA==.',
Mu='Mummrakhan:BAABLgAECn8cAAIdAAgJ4ASlpgD0AAAdAAgJ4ASlpgD0AAAAAA==.',
Na='Nagasaki:BAAALgAECgkJCQAAAA==.Naniel:BAACLgAFFH8ZAAIEAAUJ2g6CJQAfAQAEAAUJ2g6CJQAfAQAuAAQKfy0AAwQACQmLGMMdAAACAAQACQmDFsMdAAACACIABAneG2ADAEIBAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBwABLgAFFAIJAgAZAAAAAA==.Neb:BAACLgAFFH8TAAIdAAQJ/g9EHwD5AAAdAAQJ/g9EHwD5AAAuAAQKf0oAAx0ACQnHHJUYAJACAB0ACQnHHJUYAJACABwAAgm5EVZXAGgAAAAA.Necroy:BAABLgAECn8VAAIcAAkJCh6rAgCHAgAcAAkJCh6rAgCHAgAAAA==.',
Ni='Niccee:BAABLgAECn8gAAIDAAkJrwwgKwB8AQADAAkJrwwgKwB8AQAAAA==.Nick:BAACLgAFFH8RAAIdAAUJ+BuIEQBYAQAdAAUJ+BuIEQBYAQAuAAQKfxgAAx0ACAkYIykbALECAB0ACAkYIykbALECABwAAQkAAHuAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAZAAAAAA==.',
No='Noodles:BAAALgAECgQJCgABLgAECggJIgAbAH0WAA==.Nosebleeds:BAABLgAECn8VAAMJAAgJCh3nEADcAQAJAAcJdxznEADcAQAlAAIJfxw8RQBRAAAAAA==.Notyourheals:BAABLgAECn8wAAMgAAgJ2BEIMgB1AQAgAAgJ2BEIMgB1AQAHAAQJSAGjjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIaAAkJNxZAKgADAgAaAAkJNxZAKgADAgAAAA==.',
Od='Odette:BAAALgADCgYJBgAAAA==.Odsum:BAABLgAECn8XAAIMAAYJWBpciwBaAQAMAAYJWBpciwBaAQAAAA==.',
Om='Omegasupreme:BAAALgADCgcJEAAAAA==.',
Oo='Oogrutamu:BAAALgAECgIJAgAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgMJBgAAAA==.Pandabear:BAAALgADCgkJDwAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papasmurff:BAAALgADCgIJAgAAAA==.Papichulo:BAAALgAECgIJAgAAAA==.',
Pe='Percival:BAABLgAECn8mAAIMAAkJUA2bbgCRAQAMAAkJUA2bbgCRAQAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAABLgAECn8kAAIMAAkJoCNIBgA/AwAMAAkJoCNIBgA/AwAAAA==.',
Po='Poetbrat:BAAALgADCgkJIQABLgAECggJOgADANUEAA==.Porkles:BAAALgADCgQJBQAAAA==.',
Pr='Praxiscannon:BAAALgAECgUJBgAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIPAAkJswsyCgB9AQAPAAkJswsyCgB9AQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAACLgAFFH8GAAIaAAIJBws/HgBfAAAaAAIJBws/HgBfAAAuAAQKfzcAAxoACAnZG48BAGsCABoACAnZG48BAGsCAAMAAgkgAqCqABMAAAAA.',
Qu='Queue:BAABLgAECn8hAAIcAAYJxhQIAwAcAQAcAAYJxhQIAwAcAQAAAA==.Quilten:BAABLgAECn8cAAIRAAcJuA08OwAUAQARAAcJuA08OwAUAQAAAA==.',
Ra='Raenii:BAAALgAFFAEJAwABLgAFFAIJBgAYAMMSAA==.Ramoth:BAABLgAECn8VAAIgAAgJrQcNZAC5AAAgAAgJrQcNZAC5AAAAAA==.Ranoe:BAAALgADCgcJDQAAAA==.Rapids:BAAALgADCgYJCAAAAA==.Rashamka:BAAALgAECgIJAgAAAA==.Rayne:BAABLgAECn8nAAIWAAkJAh0gLwBcAgAWAAkJAh0gLwBcAgAAAA==.Razelda:BAAALgAECgkJBgAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8gAAMTAAkJbA8mGgAAAQASAAcJng6wpQAjAQATAAUJ2Q0mGgAAAQAAAA==.',
Ri='Rinnian:BAAALgAECgYJDwAAAA==.Rinny:BAAALgAECgEJAQAAAA==.Riptideaf:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgcJEgAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECgkJSAAQAFMbAA==.Robbiemonk:BAABLgAECn9IAAMQAAkJUxtXDABwAgAQAAkJUxtXDABwAgARAAQJ9wMTXgCYAAAAAA==.Robbiesboomy:BAAALgAECgIJAgABLgAECgkJSAAQAFMbAA==.Rodric:BAAALgADCgMJAwABLgAECgkJFgACAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Ru='Runetottem:BAAALgADCgEJAQAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgcJDwAAAA==.Sannith:BAABLgAECn86AAIWAAkJUxasOQAyAgAWAAkJUxasOQAyAgAAAA==.Sapphi:BAABLgAECn8lAAIVAAkJew/PFACEAQAVAAkJew/PFACEAQAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAABLgAECn8hAAIhAAkJpQ/ZAwALAQAhAAkJpQ/ZAwALAQAAAA==.Senjinbenjin:BAAALgAECgQJBQAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAZAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shakjabuti:BAAALgADCgUJBQAAAA==.Shamanoodles:BAAALgADCgkJCQABLgAECgkJPAAHAFMiAA==.Sharma:BAAALgAECgcJBwABLgAECgQJDgAZAAAAAA==.Shattersun:BAAALgAECgMJAQAAAA==.Shauralin:BAAALgAECgEJAQAAAA==.Shelbei:BAAALgAECgQJBgAAAA==.Shespawn:BAAALgAFFAIJBAAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMCAAkJqhDkLwDxAQACAAkJqhDkLwDxAQAmAAEJLQJiMgApAAAAAA==.Shykara:BAAALgADCgcJGAABLgAECggJFQAgAK0HAA==.Shâdê:BAAALgAECgEJBAAAAA==.Shådowblade:BAAALgADCgkJCQAAAA==.',
Si='Sinae:BAAALgAECgEJAQAAAA==.Sindrak:BAAALgAECgEJAgAAAA==.Sins:BAAALgAECgIJAgAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slabomeat:BAAALgAECgcJBwABLgAECgkJFgACAKoQAA==.Slipperybop:BAACLgAFFH8PAAIMAAMJ4CT7QAApAQAMAAMJ4CT7QAApAQAuAAQKfxwAAgwACQlgI/sJABcDAAwACQlgI/sJABcDAAEuAAUUAQkDABkAAAAA.Slugbow:BAAALgAECgYJCQAAAA==.',
Sm='Smashed:BAAALgAFFAIJAgABLgAFFAIJAgAZAAAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIHAAkJZAYVcQAJAQAHAAkJZAYVcQAJAQAAAA==.',
So='Soldanis:BAAALgAECgEJAQAAAA==.Sorena:BAAALgAECgMJAwAAAA==.',
Sp='Spawny:BAAALgADCgYJBgAAAA==.Spazoff:BAAALgAECgEJAQAAAA==.Spyman:BAAALgAECgEJBAAAAA==.Spyro:BAAALgAECgMJAwAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8zAAIaAAkJghv7EQC/AgAaAAkJghv7EQC/AgAAAA==.',
St='Starz:BAAALgADCgkJCQAAAA==.Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAZAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgAECgEJAQAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgAECgQJBwAAAA==.',
Sv='Sveliaa:BAAALgAECgIJAgABLgAFFAQJBAAZAAAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJEQAAAA==.Sydonai:BAAALgAECgEJAgAAAA==.Syndra:BAAALgAECgEJAQABLgAECggJCgAZAAAAAA==.',
Ta='Tanderina:BAAALgAECgIJAgAAAA==.Tankshock:BAAALgAECgcJEQAAAA==.Taylor:BAAALgAECgcJAgABLgAFFAUJCwABADwcAA==.',
Te='Teddy:BAAALgAECgMJAgAAAA==.Tellah:BAABLgAECn8XAAMHAAkJtxk7FwCPAgAHAAkJtxk7FwCPAgAgAAQJXAc5YwC2AAABLgAECgQJDgAZAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Thegreatland:BAAALgAECgMJAwAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgAECggJCAABLgAECgkJJAAMAKAjAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgcJFwAYAGwTAA==.',
Tw='Twomz:BAACLgAFFH8HAAIHAAMJ+gaJNgBYAAAHAAMJ+gaJNgBYAAAuAAQKfzUAAwcACQkdEX8uAPwBAAcACQkdEX8uAPwBACAABQlQDRsMALIAAAAA.',
Um='Umi:BAAALgAECgEJAQABLgAFFAMJBwAHAOMVAA==.',
Un='Unclebenjin:BAAALgAECgYJBgAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgkJFwAWAA0hAA==.',
Va='Varrieto:BAAALgAECgcJBwAAAA==.Vavaboom:BAAALgADCggJCAAAAA==.',
Ve='Veirlyn:BAAALgAECgkJCQAAAA==.',
Vi='Vindication:BAABLgAECn8jAAILAAgJ9iJ8BwAUAwALAAgJ9iJ8BwAUAwAAAA==.Viz:BAAALgADCgkJIQAAAA==.',
Vo='Voidshådow:BAABLgAECn8XAAIbAAcJmxOBXwBrAQAbAAcJmxOBXwBrAQAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vr='Vraul:BAAALgAECgMJAgABLgAECgkJJwAWAAIdAA==.',
Vu='Vulpain:BAAALgAECgYJBgABLgAECgkJJAAMAKAjAA==.',
Vy='Vylandra:BAAALgAECgQJBQAAAA==.',
We='Weepingwillo:BAAALgAECgQJBAAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Where:BAAALgAECgUJCQABLgAECgkJDwAZAAAAAA==.Whiteangel:BAAALgAECgEJAQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCQAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAABLgAECn8VAAIDAAMJXQirDwBpAAADAAMJXQirDwBpAAAAAA==.',
Xa='Xaela:BAABLgAECn8dAAIbAAkJEhcYOQDiAQAbAAkJEhcYOQDiAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgcJDgAAAA==.Xarous:BAAALgADCgkJFAABLgAECgkJJAAMAKAjAA==.',
Xe='Xeon:BAAALgAECgIJBQAAAA==.',
Xi='Xiabal:BAACLgAFFH8FAAMDAAIJfA+/FwCIAAADAAIJfA+/FwCIAAAaAAEJngmfLQAuAAAuAAQKfywAAxoACQnTHlIJACQDABoACQnTHlIJACQDAAMABAkEGVJCAAQBAAAA.',
Xw='Xweakling:BAAALgAECgcJCwABLgAFFAQJEAAEAEobAA==.Xweekling:BAACLgAFFH8QAAIEAAQJShu8GQBLAQAEAAQJShu8GQBLAQAuAAQKfywAAgQACQl6IyMDADsDAAQACQl6IyMDADsDAAAA.Xweeklingdh:BAAALgAECgYJBgABLgAFFAQJEAAEAEobAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgAECgEJAQAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgkJIAAAAA==.',
Za='Zaraeth:BAAALgAECgUJDAABLgAECgcJDgAZAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zenhubba:BAAALgAECgYJBgABLgAECgkJMwAaAIIbAA==.Zerostar:BAABLgAECn8XAAImAAcJshEHLQA9AQAmAAcJshEHLQA9AQABLgAECgkJMwACAOYdAA==.Zevon:BAAALgAECgIJAgABLgAECgcJDgAZAAAAAA==.',
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
