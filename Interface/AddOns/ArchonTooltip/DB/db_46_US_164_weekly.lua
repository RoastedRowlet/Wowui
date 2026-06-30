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

local lookup = {'Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Evoker-Preservation','Druid-Guardian','Priest-Discipline','Paladin-Holy','Paladin-Retribution','Mage-Fire','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Mage-Frost','DemonHunter-Havoc','Warrior-Arms','Priest-Holy','Druid-Restoration','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Hunter-Survival',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abbaddon:BAAALgADCgcJBwAAAA==.Aberration:BAAALgADCgMJAwAAAA==.Absolutezero:BAAALgADCggJFAAAAA==.',
Ad='Addison:BAAALgAECgQJBQAAAA==.Adormi:BAAALgAECgQJBQAAAA==.',
Ai='Aidum:BAAALgADCgMJAwAAAA==.',
Al='Alarus:BAAALgADCgYJCAAAAA==.Allesar:BAAALgAECgcJDgAAAA==.Allila:BAABLgAECn8eAAIBAAgJghwpFgAaAgABAAgJghwpFgAaAgAAAA==.Aloreith:BAAALgAECgEJAQAAAA==.',
Am='Ambrozyn:BAAALgAECgcJDQAAAA==.',
An='Andrew:BAAALgAECgYJCgAAAA==.Anik:BAAALgAECgYJBwAAAA==.Animalz:BAAALgADCgYJBgABLgAECgkJFgACAKoQAA==.Anna:BAABLgAFFH8LAAIBAAUJPBwpEwBNAQABAAUJPBwpEwBNAQAAAA==.Anturoc:BAAALgADCgkJFwAAAA==.',
Ap='Apalrapzz:BAABLgAECn8WAAIBAAYJtQM7CgBpAAABAAYJtQM7CgBpAAABLgAECggJMwADAHQEAA==.Apollo:BAAALgADCgEJAQAAAA==.',
Ar='Araphael:BAAALgAECgYJBwAAAA==.Ardrelar:BAABLgAECn8YAAIEAAgJdAswOwBZAQAEAAgJdAswOwBZAQAAAA==.Arieljoyeria:BAACLgAFFH8PAAMFAAUJMh0EBABPAQAFAAQJ4B4EBABPAQAGAAMJLxlYFACtAAAuAAQKfyQAAwYACQmZH+MNAMACAAYACQkfHuMNAMACAAUABAkqGOIRAAcBAAAA.Aroseath:BAAALgADCgMJAwAAAA==.Arthoz:BAAALgADCgIJAgABLgAECggJGAAHANgQAA==.',
As='Ashog:BAAALgAECgIJAgAAAA==.Astar:BAAALgAECgEJAQABLgAFFAMJCQAIAGQdAA==.Astraea:BAABLgAECn9MAAIJAAgJKR+cAABMAgAJAAgJKR+cAABMAgABLgAECgkJPAAHAFMiAA==.',
At='Athika:BAAALgAECgEJAQAAAA==.',
Au='Auddorn:BAAALgAECgYJDAAAAA==.Auria:BAABLgAECn8bAAIKAAgJZh3LDACgAgAKAAgJZh3LDACgAgAAAA==.Ausser:BAAALgADCgQJAwAAAA==.',
Az='Azarine:BAACLgAFFH8IAAIBAAMJ8Af6KQCvAAABAAMJ8Af6KQCvAAAuAAQKfyEAAgEACAnXC0IoAJcBAAEACAnXC0IoAJcBAAAA.Azend:BAAALgAECgIJAgAAAA==.Azphrodite:BAAALgAECgYJBgAAAA==.Azralia:BAABLgAECn8eAAMLAAkJpxXLGgAuAgALAAkJpxXLGgAuAgAMAAEJFg5/LQAyAAAAAA==.',
Ba='Baconator:BAAALgAECgEJAQAAAA==.Barthamus:BAAALgADCgYJBgAAAA==.',
Bb='Bbygee:BAAALgAECgYJEwAAAA==.',
Be='Beastlegion:BAAALgADCgUJDAAAAA==.Beaverboys:BAAALgADCgEJAQAAAA==.Bella:BAAALgAECgcJEwAAAA==.Benjaminadin:BAAALgAECgUJEQAAAA==.Berris:BAAALgADCgYJBgAAAA==.Beyblade:BAAALgAECgQJBQAAAA==.',
Bi='Bigstones:BAAALgADCgYJDAAAAA==.',
Bj='Bjorn:BAAALgADCgYJBwAAAA==.',
Bl='Blazinember:BAABLgAECn8+AAINAAkJJAwXBQCMAQANAAkJJAwXBQCMAQAAAA==.Bloodpal:BAAALgAECgQJBQAAAA==.Blueberri:BAAALgAECgMJAwAAAA==.',
Bo='Bobbydrac:BAAALgADCgIJAgAAAA==.Boggy:BAABLgAECn8cAAQOAAkJUxcgMgBtAQAOAAcJShQgMgBtAQAIAAcJiwpaKgAfAQAPAAEJsiCEHQBiAAAAAA==.Boop:BAAALgADCgkJCQABLgAECgkJJAAMAKAjAA==.Borgin:BAABLgAECn8VAAICAAYJ3QaVtwDWAAACAAYJ3QaVtwDWAAAAAA==.Borimor:BAABLgAECn8fAAIMAAcJcAxFpgAuAQAMAAcJcAxFpgAuAQABLgAECgkJFgACAKoQAA==.Bowehunter:BAAALgAECgEJAQAAAA==.',
Br='Braina:BAAALgAECgEJAQAAAA==.Braylia:BAAALgADCggJCAAAAA==.Briaella:BAABLgAECn8dAAMQAAYJwhHJOQAVAQAQAAYJwhHJOQAVAQARAAEJuAMHiQAmAAABLgAECgkJQQASAPocAA==.Bridgetta:BAAALgAECgIJAgAAAA==.Brisli:BAAALgADCgcJBwABLgAECggJGwAKAGYdAA==.Briëlla:BAABLgAECn9BAAQSAAkJ+hyOGQCtAgASAAkJ+hyOGQCtAgATAAEJDQjpQAAlAAAUAAEJOgMAbQASAAAAAA==.Bromdrago:BAAALgAECgEJAQAAAA==.Bromkin:BAABLgAECn8XAAIVAAcJQRyZGABYAQAVAAcJQRyZGABYAQAAAA==.',
['Bë']='Bëorn:BAAALgAECgUJBQABLgAECgkJFgACAKoQAA==.',
Ca='Calindala:BAAALgADCggJBAAAAA==.Calinor:BAABLgAECn8TAAIMAAQJpBljCwDxAAAMAAQJpBljCwDxAAAAAA==.Carl:BAAALgAECgcJCgAAAA==.Case:BAAALgADCgEJAQAAAA==.Castandie:BAABLgAECn8aAAIWAAYJCQeG8AAZAQAWAAYJCQeG8AAZAQAAAA==.',
Ce='Ceran:BAABLgAECn8wAAIXAAkJ4xNDFADvAQAXAAkJ4xNDFADvAQAAAA==.Cereus:BAACLgAFFH8JAAMIAAMJZB0TBQD2AAAIAAMJZB0TBQD2AAAPAAIJpwwDCgCHAAAuAAQKf0EAAwgACQkXJPMAAKsDAAgACQkXJPMAAKsDAA8ACQktG+gCAH4CAAAA.',
Ch='Chaelenge:BAABLgAECn8lAAMLAAkJSh5iCAAFAwALAAkJSh5iCAAFAwAMAAMJpQlLWwFWAAAAAA==.Cheatt:BAAALgAECgEJAQAAAA==.Chubbabuns:BAABLgAECn8xAAMYAAkJ1yTkAgARAwAYAAkJ/yPkAgARAwAEAAYJ2yNsNAB5AQAAAA==.Chyran:BAAALgAECggJEAAAAA==.',
Cl='Clock:BAAALgAFFAEJAQAAAA==.Cloeh:BAAALgAECgEJAQAAAA==.',
Co='Cocobutters:BAAALgADCgEJAQAAAA==.Coloratura:BAABLgAECn8lAAIZAAkJ4RhPFAA0AgAZAAkJ4RhPFAA0AgAAAA==.Corydh:BAAALgAECgYJEAAAAA==.',
Cp='Cptkanuckles:BAAALgAFFAIJAwAAAA==.',
Cr='Crazyelf:BAAALgADCgQJCAAAAA==.Crunchbar:BAAALgADCgUJBQAAAA==.',
Cu='Cubscout:BAAALgADCgcJBwAAAA==.Cutecop:BAAALgAECgIJBAAAAA==.',
['Cò']='Còffee:BAAALgADCgkJCQABLgAECgkJGAAQAMYgAA==.',
Da='Dagast:BAAALgADCgYJCQAAAA==.Dagethon:BAAALgADCggJEwAAAA==.Dalielah:BAAALgAECgQJBgAAAA==.Danfortesque:BAAALgADCgIJAgAAAA==.Darkkstarr:BAAALgAECgEJAQAAAA==.Daromiciah:BAAALgAECgIJAgAAAA==.',
De='Deathnome:BAAALgADCgYJAwAAAA==.Demdots:BAAALgADCgEJAQAAAA==.Denvoker:BAAALgAECgYJEwAAAA==.Deputyfluff:BAAALgADCgEJAQAAAA==.',
Dh='Dhjacob:BAAALgAECgYJEQAAAA==.',
Di='Diddykong:BAAALgAECgkJCQAAAA==.Dirtnapp:BAAALgADCgEJAgAAAA==.',
Do='Docqt:BAAALgADCgEJAQAAAA==.Dolleez:BAAALgAECgcJCAAAAA==.Dooman:BAAALgADCgcJDAAAAA==.Dotpockets:BAAALgAECgQJBAAAAA==.Dotsenpai:BAAALgADCgQJBQAAAA==.Doubtfire:BAABLgAECn8zAAMDAAgJdAQ4BwCaAAADAAgJdAQ4BwCaAAAaAAIJiAE6+AAbAAAAAA==.',
Dr='Dragii:BAAALgAECgMJBAAAAA==.',
Du='Dunkaroo:BAABLgAECn8eAAIbAAkJMhQFRAC8AQAbAAkJMhQFRAC8AQAAAA==.',
['Dé']='Dékü:BAAALgAECgcJCgAAAA==.',
Ei='Eikinskaldi:BAAALgAECgEJAgAAAA==.',
El='Elcarly:BAAALgAECgEJAgAAAA==.Eleridus:BAAALgADCgMJAwAAAA==.',
Em='Empty:BAABLgAECn8mAAIMAAkJ5gzsdgCAAQAMAAkJ5gzsdgCAAQAAAA==.',
En='Endormu:BAAALgAECgIJAgAAAA==.',
Er='Eraessyr:BAAALgADCgcJDQAAAA==.Erind:BAAALgADCgcJBwAAAA==.',
Et='Etërnal:BAAALgADCgkJDwAAAA==.',
Fa='Faiye:BAAALgAECggJCgAAAA==.Fandris:BAAALgAECgEJAQAAAA==.',
Fe='Feldrus:BAAALgAECgMJBAABLgAECgkJRwAcAOEVAA==.Fendre:BAAALgADCgEJAQAAAA==.',
Fl='Flaregun:BAAALgAECgIJAgAAAA==.',
Fo='Forsëti:BAAALgAECgIJAgAAAA==.',
Fr='Freakadeek:BAAALgAECgMJBAABLgAECgkJFQATAGsNAA==.Frosh:BAABLgAECn8YAAMHAAgJ2BB2OACgAQAHAAgJ2BB2OACgAQAdAAMJ4h2/bQCMAAAAAA==.Frìeren:BAABLgAECn8oAAIWAAkJ1hNMUwDjAQAWAAkJ1hNMUwDjAQAAAA==.',
Fu='Fuegaluna:BAAALgADCgkJCwAAAA==.Fundetected:BAACLgAFFH8GAAIbAAMJOA2nbQCvAAAbAAMJOA2nbQCvAAAuAAQKfysAAhsACQl8GpYeAF0CABsACQl8GpYeAF0CAAAA.',
['Fâ']='Fâllenboy:BAAALgAECgMJAwAAAA==.',
Ga='Garross:BAAALgADCgYJCAAAAA==.',
Ge='Geoffrii:BAAALgADCgcJBwAAAA==.',
Gh='Ghouldottie:BAAALgAECgMJAwAAAA==.',
Gi='Gillarria:BAAALgAECgUJCgAAAA==.',
Gn='Gnomerdenis:BAAALgADCgEJAQAAAA==.',
Go='Goochiemon:BAAALgAECgQJBAAAAA==.Gotalight:BAAALgAECgcJCAAAAA==.',
Gr='Gravecrawler:BAAALgAECgEJAQAAAA==.Grimmberly:BAAALgAECgcJDAABLgAECgYJCwAeAAAAAA==.Grimmothy:BAABLgAECn8sAAIQAAkJ3BafEgAfAgAQAAkJ3BafEgAfAgABLgAECgYJCwAeAAAAAA==.Grimoire:BAAALgAECgYJCwAAAA==.Grindr:BAAALgAECgIJAgAAAA==.',
Gu='Guanyin:BAAALgAECgEJAQAAAA==.Guthunnel:BAABLgAECn86AAICAAkJvhIgOgD2AQACAAkJvhIgOgD2AQAAAA==.Gutshadra:BAAALgAECgYJAgAAAA==.',
['Gö']='Göldenvenom:BAAALgADCgQJBAAAAA==.',
Ha='Haides:BAAALgAECgIJAgAAAA==.Hakuri:BAAALgADCgcJDwABLgAECgYJDQAeAAAAAA==.Hannibow:BAAALgAECgcJCAAAAA==.Happydru:BAAALgADCgcJDgAAAA==.Hazuki:BAAALgAECgEJAQAAAA==.',
He='Helle:BAABLgAECn8eAAQcAAkJuxRaHQAuAgAcAAkJuxRaHQAuAgAQAAYJ6Aj0TQALAQARAAEJrw1doAAvAAAAAA==.',
Hi='Highfever:BAABLgAECn8UAAIaAAUJ3A32cADiAAAaAAUJ3A32cADiAAAAAA==.',
Ho='Hoawatt:BAAALgAECgMJAwAAAA==.Holynova:BAAALgADCgQJBwABLgAECgQJBAAeAAAAAA==.',
Hr='Hrum:BAAALgADCgEJAQAAAA==.',
Hu='Hubbaroo:BAAALgADCgQJBAABLgAECgkJMwAaAIIbAA==.Huuch:BAABLgAECn8oAAICAAkJEAs4VgChAQACAAkJEAs4VgChAQAAAA==.',
Hy='Hycinari:BAAALgAECgIJAgAAAA==.Hyperius:BAAALgAECgUJBQAAAA==.',
Ic='Icrucify:BAACLgAFFH8FAAICAAMJ6RwlFQCwAAACAAMJ6RwlFQCwAAAuAAQKfzkAAgIACQmgJUQIABkDAAIACQmgJUQIABkDAAAA.',
Ig='Ignee:BAABLgAFFH8IAAMfAAMJRBM4CgCIAAAEAAMJpAT/PgCsAAAfAAIJnBg4CgCIAAAAAA==.Ignia:BAAALgAECgEJAQABLgAECggJCgAeAAAAAA==.',
Il='Ilanos:BAAALgAECgIJAgAAAA==.',
Im='Imeria:BAAALgAECgQJBgAAAA==.Imissmobo:BAAALgADCgIJAgAAAA==.',
In='Inhyai:BAAALgAECgMJAwABLgAFFAQJBAAeAAAAAA==.',
Ir='Iremoon:BAABLgAECn88AAMSAAkJkxWwNgAkAgASAAkJkxWwNgAkAgAUAAIJRwQTQgBCAAABLgAFFAIJBgAMAKQLAA==.',
Ja='Jadexx:BAAALgAECgMJAwAAAA==.Jaeler:BAAALgAECgUJBQAAAA==.',
Je='Jedistang:BAAALgAECgQJBgAAAA==.Jestyr:BAACLgAFFH8RAAMXAAQJaRgiDgA1AQAXAAQJaRgiDgA1AQAgAAIJAxXxAgCTAAAuAAQKfxYAAxcACQlUH2IGANECABcACQlUH2IGANECABsAAQmBB28oASUAAAAA.Jestyrd:BAAALgAECgMJAwABLgAFFAQJEQAXAGkYAA==.Jestyrdk:BAAALgAFFAEJAQABLgAFFAQJEQAXAGkYAA==.Jestyrmo:BAABLgAECn8rAAMQAAgJARtiJQCDAQAQAAcJ2BliJQCDAQAcAAgJgBCxRABZAQABLgAFFAQJEQAXAGkYAA==.',
Ji='Jitjitjitjit:BAAALgAECgEJAQAAAA==.Jiyao:BAACLgAFFH8eAAIRAAQJ4R9TAgBIAQARAAQJ4R9TAgBIAQAuAAQKf0wAAxEACQnwJKgCAEADABEACQnwJKgCAEADABwAAQmeB+tsACgAAAAA.',
Jo='Jodi:BAAALgAECgYJEwAAAA==.',
Ju='Jules:BAAALgAFFAIJAgAAAA==.Jumbo:BAAALgAECgMJBAAAAA==.',
Ka='Kaceya:BAAALgAECgUJDQAAAA==.Kainarasa:BAAALgAECgYJEwABLgAECgkJJAAMAKAjAA==.Kairnei:BAAALgADCgYJBwAAAA==.Katarinea:BAABLgAECn8fAAIDAAkJiw7DKgB/AQADAAkJiw7DKgB/AQAAAA==.Kaypop:BAAALgAECgcJEwAAAA==.',
Ke='Keats:BAAALgAECgIJAgAAAA==.Keeytz:BAAALgADCgYJAgAAAA==.',
Kh='Khalessie:BAABLgAECn8lAAIKAAkJOQ3PIwCwAQAKAAkJOQ3PIwCwAQAAAA==.Kheldar:BAAALgAECgcJAQAAAA==.Khrone:BAAALgAECgEJAgAAAA==.',
Ki='Kirsi:BAABLgAECn8kAAMhAAkJpB5LCABBAgAhAAkJpB5LCABBAgAHAAEJeQHi9gAZAAAAAA==.Kiselle:BAAALgAECgQJBAABLgAECggJGwAKAGYdAA==.',
Ko='Korkneelious:BAAALgAECgYJDAAAAA==.',
Kr='Kretor:BAAALgAECgQJDgAAAA==.',
Ku='Kungfudru:BAAALgADCgcJBwAAAA==.',
Kw='Kwai:BAAALgAECgYJBgABLgAECgkJFgACAKoQAA==.',
Ky='Kyomu:BAAALgAECgcJBwABLgAECgkJJAAMAKAjAA==.',
La='Lavendarmoon:BAAALgAECgEJAQAAAA==.',
Li='Lillock:BAAALgAECgIJAgAAAA==.Lineofsight:BAABLgAECn9BAAIEAAYJDCAVAwBQAQAEAAYJDCAVAwBQAQAAAA==.Liths:BAABLgAECn87AAIgAAkJlAlIEQA4AQAgAAkJlAlIEQA4AQAAAA==.Littlemoses:BAABLgAECn8mAAICAAgJqxsuLwAgAgACAAgJqxsuLwAgAgAAAA==.',
Lo='Lockdarkly:BAAALgAECgQJCAAAAA==.Lono:BAAALgADCgQJBwAAAA==.Lostdru:BAAALgADCgEJAgAAAA==.',
Lu='Lululuvely:BAABLgAECn8VAAMKAAYJIxV5KQCIAQAKAAYJIxV5KQCIAQAZAAUJZwk5UwDqAAAAAA==.Lulzimadrood:BAAALgADCgMJAwAAAA==.',
Ma='Magejacob:BAAALgADCgcJCQABLgAECgYJEQAeAAAAAA==.Malendren:BAAALgAECgEJAQAAAA==.Malignus:BAABLgAECn8wAAIWAAkJERyyIgCSAgAWAAkJERyyIgCSAgABLgADCgkJFwAeAAAAAA==.Malthaos:BAAALgADCgQJBAABLgAECgkJJwAWAAIdAA==.Maneyen:BAAALgADCgQJAwAAAA==.Margot:BAAALgAECgYJEgAAAA==.Marksmann:BAAALgADCgcJCwAAAA==.Mavane:BAAALgADCgUJAQAAAA==.Mawhriccio:BAAALgADCgEJAQAAAA==.',
Mc='Mcdavé:BAABLgAECn88AAIdAAkJyxCNJwCwAQAdAAkJyxCNJwCwAQAAAA==.',
Me='Meathshield:BAAALgADCgMJAwABLgAECggJHgABAIIcAA==.Meerclar:BAAALgAECgIJAwABLgAECgYJDQAeAAAAAA==.Melaila:BAABLgAECn88AAIHAAkJUyL6DgDbAgAHAAkJUyL6DgDbAgAAAA==.Mellwynn:BAAALgAECgUJDwAAAA==.Melunaura:BAAALgAECggJCQABLgAECgkJPAAHAFMiAA==.',
Mf='Mf:BAABLgAECn8hAAIbAAcJtxRaaABVAQAbAAcJtxRaaABVAQAAAA==.',
Mi='Micheal:BAAALgAFFAIJAgAAAA==.Midir:BAAALgAECgQJBAAAAA==.Miladrayn:BAAALgADCgYJBgAAAA==.Min:BAAALgAECgIJAgAAAA==.Minthe:BAAALgAECgQJBQAAAA==.Mistwallker:BAAALgADCgUJBQAAAA==.Miñitañk:BAAALgAECgIJAgAAAA==.',
Mo='Moardotz:BAAALgADCgUJBgAAAA==.Moldthinur:BAABLgAECn8vAAIVAAgJVyNDAACoAgAVAAgJVyNDAACoAgAAAA==.Monalina:BAAALgAECgkJBwAAAA==.Mongrol:BAAALgAECgQJBgAAAA==.Monju:BAAALgAECgEJAQAAAA==.Moonowl:BAAALgAECgQJBQAAAA==.Mordrack:BAAALgAECgYJBgAAAA==.Moreganna:BAAALgADCgYJCQABLgAECgUJFAAaANwNAA==.',
Mu='Mummrakhan:BAABLgAECn8bAAIiAAgJmwSlpgD0AAAiAAgJmwSlpgD0AAAAAA==.',
Na='Naniel:BAACLgAFFH8ZAAIEAAUJ2g7GDADTAAAEAAUJ2g7GDADTAAAuAAQKfykAAgQACQmDFsMdAAACAAQACQmDFsMdAAACAAAA.Narmaya:BAAALgADCgMJAwAAAA==.',
Ne='Neat:BAAALgAECgcJBwAAAA==.Neb:BAACLgAFFH8SAAIiAAQJ/g/YEAAIAQAiAAQJ/g/YEAAIAQAuAAQKf0kAAyIACQkMHJUYAJACACIACQkMHJUYAJACACMAAgm5EVZXAGgAAAAA.Necroy:BAABLgAECn8VAAIjAAkJCh6rAgCHAgAjAAkJCh6rAgCHAgAAAA==.',
Ni='Niccee:BAABLgAECn8gAAIDAAkJrwwgKwB8AQADAAkJrwwgKwB8AQAAAA==.Nick:BAACLgAFFH8RAAIiAAUJ+BuIEQBYAQAiAAUJ+BuIEQBYAQAuAAQKfxgAAyIACAkYIykbALECACIACAkYIykbALECACMAAQkAAHuAABAAAAAA.Nightflurry:BAAALgAECgcJEgAAAA==.Nightslife:BAAALgADCgUJBQABLgADCgUJBQAeAAAAAA==.',
No='Noodles:BAAALgAECgQJCgABLgAECggJIgAbAH0WAA==.Nosebleeds:BAABLgAECn8VAAMJAAgJCh3nEADcAQAJAAcJdxznEADcAQAkAAIJfxw8RQBRAAAAAA==.Notyourheals:BAABLgAECn8wAAMdAAgJ2BEIMgB1AQAdAAgJ2BEIMgB1AQAHAAQJSAGjjQBfAAAAAA==.',
Oa='Oakay:BAAALgAECgMJAwAAAA==.',
Ob='Obee:BAABLgAECn8nAAIaAAkJNxZAKgADAgAaAAkJNxZAKgADAgAAAA==.',
Od='Odette:BAAALgADCgYJBgAAAA==.Odsum:BAABLgAECn8XAAIMAAYJWBpciwBaAQAMAAYJWBpciwBaAQAAAA==.',
Om='Omegasupreme:BAAALgADCgQJBAAAAA==.',
Oo='Oogrutamu:BAAALgAECgIJAgAAAA==.',
Or='Orionna:BAAALgADCggJBAAAAA==.',
Pa='Pal:BAAALgAECgEJAQAAAA==.Palanious:BAAALgAECgMJBgAAAA==.Pandabear:BAAALgADCgkJDwAAAA==.Papamidnight:BAAALgAECgIJAwAAAA==.Papasmurff:BAAALgADCgIJAgAAAA==.Papichulo:BAAALgAECgIJAgAAAA==.',
Pe='Percival:BAABLgAECn8lAAIMAAkJUA2bbgCRAQAMAAkJUA2bbgCRAQAAAA==.',
Pi='Pinheadjerry:BAAALgAECgEJAQAAAA==.Pinhêadlarry:BAAALgADCgYJBgAAAA==.Pizzaslice:BAABLgAECn8kAAIMAAkJoCNIBgA/AwAMAAkJoCNIBgA/AwAAAA==.',
Po='Poetbrat:BAAALgADCgkJGwABLgAECggJMwADAHQEAA==.Porkles:BAAALgADCgQJBQAAAA==.',
Pr='Praxiscannon:BAAALgAECgUJBgAAAA==.Prettydead:BAAALgADCgIJAgAAAA==.',
Pu='Pumpshire:BAABLgAECn8jAAIPAAkJswsyCgB9AQAPAAkJswsyCgB9AQAAAA==.',
Pw='Pwnstar:BAAALgADCgMJAwAAAA==.Pwongo:BAABLgAECn8rAAMaAAgJ9xlmAQAJAgAaAAgJ9xlmAQAJAgADAAIJIAKgqgATAAAAAA==.',
Qu='Queue:BAABLgAECn8dAAIjAAYJfRMSAgD+AAAjAAYJfRMSAgD+AAAAAA==.Quilten:BAABLgAECn8bAAIRAAcJuA08OwAUAQARAAcJuA08OwAUAQAAAA==.',
Ra='Raenii:BAAALgAFFAEJAwABLgAFFAIJBgAZAMMSAA==.Ramoth:BAAALgAECgYJEwAAAA==.Ranoe:BAAALgADCgcJDQAAAA==.Rapids:BAAALgADCgYJBwAAAA==.Rashamka:BAAALgAECgIJAgAAAA==.Rayne:BAABLgAECn8nAAIWAAkJAh0gLwBcAgAWAAkJAh0gLwBcAgAAAA==.Razelda:BAAALgAECgkJBgAAAA==.',
Re='Reolz:BAAALgADCgUJBAAAAA==.Reveya:BAABLgAECn8gAAMTAAkJbA8mGgAAAQASAAcJng6wpQAjAQATAAUJ2Q0mGgAAAQAAAA==.',
Ri='Rinnian:BAAALgAECgYJDwAAAA==.Rinny:BAAALgAECgEJAQAAAA==.Riptideaf:BAAALgAECgEJAQAAAA==.',
Ro='Roadwanderer:BAAALgAECgYJEQAAAA==.Robbiedrake:BAAALgAECgEJAQABLgAECgkJSAAQAFMbAA==.Robbiemonk:BAABLgAECn9IAAMQAAkJUxtXDABwAgAQAAkJUxtXDABwAgARAAQJ9wMTXgCYAAAAAA==.Robbiesboomy:BAAALgAECgIJAgABLgAECgkJSAAQAFMbAA==.Rodric:BAAALgADCgMJAwABLgAECgkJFgACAKoQAA==.Rokage:BAAALgADCgYJCwAAAA==.',
Ru='Runetottem:BAAALgADCgEJAQAAAA==.',
Rx='Rxeight:BAAALgAECgYJBgAAAA==.',
Sa='Sakura:BAAALgAECgYJDgAAAA==.Sannith:BAABLgAECn86AAIWAAkJUxasOQAyAgAWAAkJUxasOQAyAgAAAA==.Sapphi:BAABLgAECn8lAAIVAAkJew/PFACEAQAVAAkJew/PFACEAQAAAA==.Sarjarus:BAAALgADCgYJAgAAAA==.',
Se='Seespottank:BAABLgAECn8dAAIYAAkJZw5kAgD3AAAYAAkJZw5kAgD3AAAAAA==.Senjinbenjin:BAAALgAECgQJBQAAAA==.',
Sh='Shadowallker:BAAALgADCgMJAwABLgADCgUJBQAeAAAAAA==.Shadowlich:BAAALgAECgYJBgAAAA==.Shakjabuti:BAAALgADCgUJBQAAAA==.Shamanoodles:BAAALgADCgkJCQABLgAECgkJPAAHAFMiAA==.Shauralin:BAAALgAECgEJAQAAAA==.Shelbei:BAAALgAECgQJBgAAAA==.Shespawn:BAAALgAFFAIJBAAAAA==.Shoukkan:BAAALgADCgcJBwAAAA==.Shurie:BAABLgAECn8WAAMCAAkJqhDkLwDxAQACAAkJqhDkLwDxAQAlAAEJLQJiMgApAAAAAA==.Shykara:BAAALgADCgcJEwABLgAECgYJEwAeAAAAAA==.Shâdê:BAAALgAECgEJBAAAAA==.Shådowblade:BAAALgADCgkJCQAAAA==.',
Si='Sinae:BAAALgAECgEJAQAAAA==.Sindrak:BAAALgAECgEJAgAAAA==.Sins:BAAALgAECgIJAgAAAA==.Sinsorain:BAAALgADCgEJAQAAAA==.Sipsy:BAAALgAECgcJBQAAAA==.',
Sk='Skulcrack:BAAALgADCgcJDgAAAA==.',
Sl='Slabomeat:BAAALgAECgcJBwABLgAECgkJFgACAKoQAA==.Slipperybop:BAACLgAFFH8PAAIMAAMJ4CT7QAApAQAMAAMJ4CT7QAApAQAuAAQKfxwAAgwACQlgI/sJABcDAAwACQlgI/sJABcDAAEuAAUUAQkDAB4AAAAA.Slugbow:BAAALgAECgUJBwAAAA==.',
Sm='Smashed:BAAALgAECgcJAQAAAA==.',
Sn='Snakeshadow:BAAALgAECgMJAwAAAA==.Snoom:BAABLgAECn8kAAIHAAkJZAYVcQAJAQAHAAkJZAYVcQAJAQAAAA==.',
So='Soldanis:BAAALgAECgEJAQAAAA==.Sorena:BAAALgAECgMJAwAAAA==.',
Sp='Spawny:BAAALgADCgYJBgAAAA==.Spyman:BAAALgAECgEJBAAAAA==.',
Sr='Srhubbabubba:BAABLgAECn8zAAIaAAkJghv7EQC/AgAaAAkJghv7EQC/AgAAAA==.',
St='Starz:BAAALgADCgkJCQAAAA==.Staticbdk:BAAALgAECgEJAQABLgAFFAQJBAAeAAAAAA==.Statickling:BAAALgAFFAQJBAAAAA==.Steamynix:BAAALgADCgUJBQAAAA==.Sternn:BAAALgADCgcJCAAAAA==.Steviathan:BAAALgAECgYJDAAAAA==.Straif:BAAALgAECgQJBAAAAA==.',
Sw='Sweetest:BAAALgAECgYJBwAAAA==.Swolman:BAAALgADCgYJBgAAAA==.',
Sy='Sydeon:BAAALgAECgYJEQAAAA==.Sydonai:BAAALgAECgEJAgAAAA==.Syndra:BAAALgAECgEJAQABLgAECggJCgAeAAAAAA==.',
Ta='Tanderina:BAAALgAECgIJAgAAAA==.Tankshock:BAAALgAECgYJCwAAAA==.Taylor:BAAALgAECgcJAgABLgAFFAUJCwABADwcAA==.',
Te='Tellah:BAABLgAECn8XAAMHAAkJtxk7FwCPAgAHAAkJtxk7FwCPAgAdAAQJXAc5YwC2AAABLgAECgQJDgAeAAAAAA==.',
Th='Thegodofwar:BAAALgADCggJCQAAAA==.Thegreatland:BAAALgAECgMJAwAAAA==.Theiren:BAAALgAECgEJAQAAAA==.Themuffinman:BAAALgAECggJCAABLgAECgkJJAAMAKAjAA==.',
To='Tongari:BAAALgADCgQJBAAAAA==.',
Tu='Tullinnelor:BAAALgADCgEJAQABLgAECgcJFwAZAGwTAA==.',
Tw='Twomz:BAABLgAECn8xAAMHAAkJHRF/LgD8AQAHAAkJHRF/LgD8AQAdAAIJ1AmvrQAqAAAAAA==.',
Um='Umi:BAAALgAECgEJAQABLgAFFAMJBwAHAOMVAA==.',
Un='Unclebenjinn:BAAALgAECgYJBgAAAA==.Unkadier:BAAALgADCgMJAwABLgAECgkJFwAWAA0hAA==.',
Va='Varrieto:BAAALgAECgcJBwAAAA==.Vavaboom:BAAALgADCggJCAAAAA==.',
Ve='Veirlyn:BAAALgAECgkJCQAAAA==.',
Vi='Vindication:BAABLgAECn8jAAILAAgJ9iJ8BwAUAwALAAgJ9iJ8BwAUAwAAAA==.Viz:BAAALgADCgkJGwAAAA==.',
Vo='Voidshådow:BAABLgAECn8XAAIbAAcJmxOBXwBrAQAbAAcJmxOBXwBrAQAAAA==.Voreho:BAAALgADCggJCAAAAA==.',
Vu='Vulpain:BAAALgAECgYJBgABLgAECgkJJAAMAKAjAA==.',
Vy='Vylandra:BAAALgAECgQJBQAAAA==.',
We='Weepingwillo:BAAALgAECgQJBAAAAA==.Wennon:BAAALgADCgQJBAAAAA==.',
Wh='Whatsituya:BAAALgADCgcJCwAAAA==.Where:BAAALgAECgUJCAAAAA==.Whiteangel:BAAALgAECgEJAQAAAA==.',
Wi='Willythewolf:BAAALgADCgEJAQAAAA==.Willywallace:BAAALgAECggJCQAAAA==.Wiseman:BAAALgAECgMJAwAAAA==.',
Wo='Wolfowl:BAAALgAECgMJEgAAAA==.',
Xa='Xaela:BAABLgAECn8dAAIbAAkJEhcYOQDiAQAbAAkJEhcYOQDiAQAAAA==.Xantriar:BAAALgADCgUJBQAAAA==.Xarbariste:BAAALgAECgYJDQAAAA==.Xarous:BAAALgADCgkJFAABLgAECgkJJAAMAKAjAA==.',
Xe='Xeon:BAAALgAECgIJBQAAAA==.',
Xi='Xiabal:BAABLgAECn8qAAMaAAkJ0x5SCQAkAwAaAAkJ0x5SCQAkAwADAAQJBBngBgCjAAAAAA==.',
Xw='Xweakling:BAAALgAECgcJCwABLgAFFAQJDwAEAEobAA==.Xweekling:BAACLgAFFH8PAAIEAAQJShu8GQBLAQAEAAQJShu8GQBLAQAuAAQKfywAAgQACQl6IyMDADsDAAQACQl6IyMDADsDAAAA.Xweeklingdh:BAAALgAECgYJBgABLgAFFAQJDwAEAEobAA==.',
Xy='Xynoria:BAAALgAECgEJAQAAAA==.',
Ye='Yendara:BAAALgAECgEJAQAAAA==.Yetihunter:BAAALgADCgMJBAAAAA==.',
Yu='Yuxiong:BAAALgADCgkJGgAAAA==.',
Za='Zaraeth:BAAALgAECgUJDAABLgAECgYJDQAeAAAAAA==.',
Ze='Zedra:BAAALgAECgQJEgAAAA==.Zenhubba:BAAALgAECgYJBgABLgAECgkJMwAaAIIbAA==.Zerostar:BAABLgAECn8XAAIlAAcJQRIHLQA9AQAlAAcJQRIHLQA9AQABLgAECgkJMgACABscAA==.Zevon:BAAALgAECgIJAgABLgAECgYJDQAeAAAAAA==.',
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
