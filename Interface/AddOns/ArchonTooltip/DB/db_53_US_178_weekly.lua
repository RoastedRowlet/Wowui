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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Warrior-Arms','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Holy','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Warrior-Protection','Druid-Balance','Druid-Restoration','Druid-Feral','Monk-Windwalker','Mage-Arcane','Hunter-BeastMastery','Monk-Mistweaver','Monk-Brewmaster','Unknown-Unknown','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Guardian','DeathKnight-Blood','Paladin-Protection','Warlock-Demonology','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Warrior-Fury','Shaman-Elemental','Hunter-Survival','Warlock-Destruction','Warlock-Affliction','Rogue-Assassination',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=53,date='2026-11-10',data={Ah='Ahote:BAABNQAECn8dAAIBAAgK/BMmAwCAAQABAAgK/BMmAwCAAQAAAA==.',
Ai='Airrows:BAABNQAECn84AAICAAoKdCCbBwDEAgACAAoKdCCbBwDEAgAAAA==.',
Al='Alaois:BAABNQAECn8nAAIDAAgK5RHxfwByAQADAAgK5RHxfwByAQAAAA==.Alatar:BAAANQADCgMIAwAAAA==.Almitywitey:BAAANQAECgYIDgAAAA==.Alphaomega:BAAANQAECgIIAgAAAA==.Alurea:BAAANQAECgQIEwAAAA==.Alèxis:BAAANQAECgEIAQAAAA==.',
Am='Ampharosen:BAABNQAECn8lAAIEAAkKNxNQcwDUAQAEAAkKNxNQcwDUAQAAAA==.',
An='Anguthar:BAAANQAECgQIBAAAAA==.Anigavnimuc:BAAANQADCgMIAwAAAA==.Anthredis:BAACNQAFFH8dAAIFAAcK6hYkAgBeAgAFAAcK6hYkAgBeAgA1AAQKfyIAAwUACgoyH2YRAOMCAAUACgoyH2YRAOMCAAYAAgoWCpyDAGkAAAAA.Anvi:BAAANQAECgEIAwAAAA==.',
Ar='Ara:BAACNQAFFH8TAAIHAAkK2CBlAAAgAwAHAAkK2CBlAAAgAwA1AAQKfzQAAgcACgp2JnQBANoDAAcACgp2JnQBANoDAAAA.Argonäut:BAABNQAECn9BAAMGAAoK9CMXDwArAwAGAAoK9CMXDwArAwAIAAUKYxjsEQAUAQAAAA==.Arimalo:BAAANQAECgQIBgAAAA==.',
As='Asmindissa:BAAANQAECgMIAgAAAA==.Astragos:BAABNQAECn8rAAIJAAoK/hWiDgAOAgAJAAoK/hWiDgAOAgAAAA==.',
Au='Automedusa:BAAANQADCgYICwAAAA==.',
Az='Azagorod:BAAANQAECgYICQABNQAECgoKNQAKAMkgAA==.',
Ba='Baern:BAABNQAECn8ZAAMDAAUKXwsG3gCjAAADAAUKxAoG3gCjAAALAAIKMwwrPgBKAAAAAA==.',
Be='Bearricade:BAABNQAECn9AAAQMAAoKCRQjOAAtAgAMAAoKCRQjOAAtAgANAAgK0RZLLwBZAQAOAAIKcw1oNQBtAAAAAA==.',
Bi='Bigdansell:BAAANQADCgEIAQAAAA==.Billamong:BAABNQAECn8XAAIPAAUKPxJ4PQCqAAAPAAUKPxJ4PQCqAAAAAA==.Biren:BAAANQADCgYIBgAAAA==.',
Bl='Blitzer:BAAANQAECgQICQAAAA==.',
Bo='Bonechill:BAAANQAECgUICAAAAA==.Boney:BAAANQABCgQIBgAAAA==.',
Br='Brightstorm:BAAANQAECgIIAwAAAA==.Brisket:BAABNQAECn8mAAIDAAoKsQ7mXgDOAQADAAoKsQ7mXgDOAQABNQAECgoKQAAMAAkUAA==.',
Bu='Bucko:BAAANQAECggIDQABNQAFFAgIHAAQAJYdAA==.',
Ca='Calciferkyo:BAABNQAECn8kAAIQAAoKnQQe2wDjAAAQAAoKnQQe2wDjAAAAAA==.Cassilune:BAAANQADCgcIBwABNQAECgoKTAAHAGUiAA==.Catelaya:BAABNQAECn9HAAIRAAoKexobNQBjAgARAAoKexobNQBjAgAAAA==.',
Ch='Chaosrows:BAAANQADCggICAAAAA==.Chexk:BAABNQAECn81AAIKAAoKySCvBABFAwAKAAoKySCvBABFAwAAAA==.Chixnu:BAAANQAECgUIBgAAAA==.Chushing:BAACNQAFFH8LAAIPAAQK6hExCQDUAAAPAAQK6hExCQDUAAA1AAQKfzcAAg8ACgrTH4MOAPgCAA8ACgrTH4MOAPgCAAAA.',
Co='Come:BAAANQAECgUICQAAAA==.',
Cr='Crush:BAABNQAECn8VAAMSAAoKehVYFwAHAgASAAoKehVYFwAHAgATAAEKfxHVJAA1AAABNQAFFAcIHAAMAPAZAA==.Cryblood:BAAANQAECggIDQAAAA==.',
Cu='Curebear:BAAANQADCgEIAQAAAA==.Cutsiecow:BAACNQAFFH8HAAIMAAMKoRGWGACPAAAMAAMKoRGWGACPAAA1AAQKf0cAAgwACgo6IugKAOUCAAwACgo6IugKAOUCAAAA.',
Cy='Cynos:BAAANQADCgEIAQAAAA==.Cynthic:BAAANQAECgQICAAAAA==.',
Da='Daelynn:BAAANQAECgcIEgAAAA==.Daffodil:BAAANQABCgIIBAAAAA==.',
De='Deathpluck:BAAANQADCgUICQABNQAECggIDAAUAAAAAA==.',
Dj='Djiinar:BAABNQAECn9EAAMLAAoKQh6iDABqAgALAAkK2RuiDABqAgADAAoKUhnBigABAgAAAA==.Djiink:BAAANQADCgIIAgAAAA==.Djiinra:BAAANQADCgcIBwAAAA==.Djiinz:BAAANQADCgcIBwAAAA==.',
Do='Doomlocke:BAABNQAECn9AAAMPAAoKBBjyDwBJAgAPAAoKBBjyDwBJAgASAAMKGgOLRABaAAAAAA==.',
Du='Dunkie:BAAANQAECgQIBQAAAA==.',
Eb='Ebonymoon:BAAANQADCgMIBAAAAA==.',
El='Elise:BAACNQAFFH84AAMVAAkK/CNAAACAAwAVAAkK/CNAAACAAwAWAAEKoRhVNABIAAA1AAQKfywAAxUACgp3JhkGAHYDABUACgp3JhkGAHYDABYAAQotFpzzAEkAAAAA.',
Em='Em:BAABNQAECn8vAAMWAAoKaR2XFwAJAwAWAAoKaR2XFwAJAwAVAAcKvQvEOQBYAQAAAA==.',
En='Enzo:BAAANQAECgMIAwAAAA==.',
Er='Eraline:BAABNQAECn9EAAISAAoKfBJREADzAQASAAoKfBJREADzAQAAAA==.Erisa:BAAANQAECgUICAAAAA==.',
Ey='Eyekora:BAAANQADCgMIAwAAAA==.',
Fa='Facehunter:BAAANQAECgMICwAAAA==.Faelyn:BAAANQADCgUIDAAAAA==.',
Fc='Fcawf:BAAANQADCgMICAAAAA==.',
Fe='Fearless:BAABNQAECn82AAMXAAkKfiMhGgDwAgAXAAgKCyIhGgDwAgAYAAcKMSG+IQAuAgAAAA==.Feitan:BAAANQAECgIIAgAAAA==.Felygog:BAAANQADCgQIBwAAAA==.Fenrirblood:BAABNQAECn8fAAQNAAkKHR1CGQByAgANAAgKTxxCGQByAgAZAAcKcQwsPgDEAAAMAAEKAAC6sAA1AAAAAA==.',
Fi='Fiizz:BAAANQAECgEIAQAAAA==.Firecaneost:BAAANQADCgcIBwAAAA==.Fiyer:BAAANQAECgUIBQAAAA==.Fizzlepriest:BAAANQADCggIDgABNQAECggIFQAEAGIXAA==.',
Fr='Fraydun:BAAANQADCggICwAAAA==.Frostblood:BAABNQAECn8kAAIGAAkKIQ51JwC7AQAGAAkKIQ51JwC7AQAAAA==.',
Fu='Fuknar:BAAANQADCgUIBQAAAA==.Funk:BAAANQADCgIIAgABNQAFFAcIHgAaAHMkAA==.',
Ge='Genivan:BAAANQAECgQIBAAAAA==.Genocya:BAAANQAECgYJDAAAAA==.',
Gh='Ghost:BAAANQAECgQIBwAAAA==.',
Gi='Gilden:BAAANQAECgcIDgAAAA==.',
Gn='Gnot:BAAANQAECgUIDgAAAA==.',
Go='Goshujinsama:BAAANQADCgYICAAAAA==.',
Gr='Griz:BAAANQAECgcICAAAAA==.',
Gy='Gyoza:BAAANQAECgIIAgABNQAECgoKQAAMAAkUAA==.',
['Gò']='Gòddess:BAAANQAECgUIDAAAAA==.',
Ha='Hannahsmad:BAAANQAECgQIBQAAAA==.Harlee:BAAANQAECgUIDwAAAA==.Haukkah:BAABNQAECn8rAAIRAAoKzQqImwDQAQARAAoKzQqImwDQAQAAAA==.Hawktuwah:BAAANQADCgEIAQAAAA==.',
He='Heffalump:BAABNQAECn8oAAIMAAoKAhSqMABrAQAMAAoKAhSqMABrAQAAAA==.Hetfield:BAAANQAECgYIDQAAAA==.Hexanyth:BAAANQADCgQIBAAAAA==.',
Ho='Holycrves:BAAANQADCgQICwAAAA==.',
['Hï']='Hïbiki:BAAANQAECgEIAQAAAA==.',
If='Ifa:BAAANQADCgQICAAAAA==.',
Im='Impact:BAAANQAECgQIBAABNQAECgoKOgAbAI0gAA==.',
In='Inazuma:BAAANQADCgYICwAAAA==.Innerlect:BAAANQADCgYIBgABNQAECgoKLwAKAFsMAA==.',
Ir='Iridian:BAAANQAECgUICQAAAA==.',
Iy='Iyotanka:BAAANQADCgUIDQAAAA==.',
Ja='Jakoby:BAAANQAECgEIAQAAAA==.Jameo:BAABNQAECn8cAAIcAAkK6wiqnQCcAQAcAAkK6wiqnQCcAQABNQAECggIDAAUAAAAAA==.',
Ji='Jig:BAABNQAECn8aAAMdAAoKJQiXEQAbAQAdAAcKqweXEQAbAQAeAAgKdgbsFgC4AAABNQAECggIDAAUAAAAAA==.',
Ju='Juicebox:BAAANQADCggICQABNQAFFAQICAATAD4IAA==.Juuzau:BAAANQAECgUICAAAAA==.',
['Jå']='Jåmes:BAAANQAECgEIAQAAAA==.',
Ka='Kaners:BAABNQAECn8iAAIKAAkKBCAvCwDBAgAKAAkKBCAvCwDBAgAAAA==.Kathoran:BAABNQAECn8dAAIRAAYKGQgS2gBMAQARAAYKGQgS2gBMAQAAAA==.Katie:BAABNQAECn8WAAIWAAoKmRhlOwA5AgAWAAoKmRhlOwA5AgABNQAFFAcIHAAfAO4jAA==.',
Ke='Kealey:BAABNQAECn8eAAIEAAcKeAmn5QD+AAAEAAcKeAmn5QD+AAAAAA==.Keine:BAAANQAECgMIBAAAAA==.Kessik:BAABNQAECn8bAAMDAAoK0Q7OjgBPAQADAAoKZQ7OjgBPAQAgAAIKgw2UJgBiAAAAAA==.',
Kh='Khaless:BAAANQAECgYIDAAAAA==.',
Ki='Kiamors:BAABNQAECn83AAMhAAoKlgPjjQDZAAAhAAoKlgPjjQDZAAAfAAgK9AEkvACPAAAAAA==.Kieru:BAAANQAECgIIAgABNQAECgoKQAAMAAkUAA==.',
Ko='Kobee:BAAANQAECgUIBQAAAA==.Kolaid:BAAANQADCgMICQAAAA==.',
Kr='Kragzug:BAABNQAECn8XAAMDAAcKXBmSlwDhAQADAAcKXBmSlwDhAQAgAAMKbR1rGwDxAAAAAA==.Kreleing:BAAANQADCgMIBAAAAA==.',
La='Labiaminoris:BAAANQADCgQIAwAAAA==.',
Le='Leda:BAAANQADCgUIDQAAAA==.Lexy:BAAANQADCgEIAQAAAA==.',
Li='Lightfighter:BAAANQAECggIDAAAAA==.Lighthouse:BAACNQAFFH8eAAIaAAcKcySiBAA0AgAaAAcKcySiBAA0AgA1AAQKfyoAAxoACgrSJB0QACwDABoACgrSJB0QACwDABcAAwpJFRWjALQAAAAA.Lilkiwi:BAAANQAECgcIEgAAAA==.Linley:BAAANQADCggICAAAAA==.',
Lo='Loozer:BAABNQAECn8vAAIiAAkK2R7wAgDyAgAiAAkK2R7wAgDyAgAAAA==.',
Lu='Lunchbox:BAABNQAECn8jAAIiAAgKxQYTCQBAAQAiAAgKxQYTCQBAAQAAAA==.Lunecy:BAAANQAECgQICQAAAA==.',
Ly='Lyumi:BAAANQAECgYIDAAAAA==.',
['Lå']='Låz:BAAANQAECgQIBAAAAA==.',
Ma='Matty:BAABNQAECn8bAAIEAAkKRxD7fwApAgAEAAkKRxD7fwApAgABNQAFFAgIHAAQAJYdAA==.Maxkiwi:BAAANQADCgMJBAAAAA==.Mazikeenx:BAAANQADCgEIAQAAAA==.',
Me='Medie:BAABNQAECn8oAAMWAAoKXBgBRgBVAgAWAAoKXBgBRgBVAgAVAAIKBQ68TABlAAAAAA==.Melody:BAAANQAECgUIEgAAAA==.',
Mi='Michelle:BAABNQAECn8rAAMHAAoKiyNDFQArAwAHAAgKUSNDFQArAwAEAAUKKQ9A7QDxAAAAAA==.Mitsuki:BAAANQADCgcIBwAAAA==.',
Mo='Monstrosity:BAAANQAECgUICwABNQAECggICAAUAAAAAA==.',
My='Mystikan:BAAANQADCgMIAwABNQAECgUIDwAUAAAAAA==.',
['Mä']='Mäenard:BAAANQADCgcIFQAAAA==.',
Na='Naji:BAACNQAFFH8SAAQjAAYKniVzBADRAAAcAAUKyiW1DQAxAQAjAAIK3SRzBADRAAAkAAEKAAAQDABNAAA1AAQKf0AABBwACgpnJsEBAHkDABwACgpnJsEBAHkDACMABwoyHrQLADwCACQABAo3IGMQAEcBAAAA.',
Ne='Necro:BAAANQADCgUICgAAAA==.Neesa:BAAANQADCgMIAwABNQAFFAQICgAVAIAQAA==.',
Ni='Ninguem:BAAANQAECgcIEgAAAA==.',
No='Noodge:BAAANQADCggIDAAAAA==.Nostariel:BAAANQAECgcIDgAAAA==.Noxadin:BAAANQAECgEIAQAAAA==.',
Nu='Nutshotz:BAAANQABCgIIAwABNQAECgEIBAAUAAAAAA==.',
Pa='Paladineela:BAAANQADCgYIBAAAAA==.',
Pe='Peterpiper:BAABNQAECn8lAAIeAAoKcxFzFAAHAgAeAAoKcxFzFAAHAgAAAA==.',
Po='Poughkeepsie:BAAANQAECgEIAgABNQAECgoKNAAKADAaAA==.',
['Pè']='Pètitemort:BAAANQADCgMIAwAAAA==.',
Qu='Quaxly:BAAANQAECgEIAQABNQAECgkJJQAEADcTAA==.',
Ra='Raymane:BAAANQAECgUICQAAAA==.Rayvash:BAAANQAECgIIAgAAAA==.',
Re='Reverendbdt:BAAANQADCgYICwABNQAECgoKLwAKAFsMAA==.',
Ri='Rivanon:BAAANQADCggICAAAAA==.',
Ro='Rosastrasza:BAAANQADCgYIDQAAAA==.',
Ru='Ruhster:BAAANQADCggIEAAAAA==.Ruthos:BAAANQAECgMIBwAAAA==.',
Ry='Rykka:BAABNQAECn8gAAIRAAYKrAii5QA2AQARAAYKrAii5QA2AQAAAA==.Ryukie:BAAANQADCggICgAAAA==.',
Sa='Sathoran:BAAANQADCgQIBAAAAA==.Savall:BAAANQAECgYICwAAAA==.',
Se='Servatal:BAABNQAECn8hAAIcAAgK5AVQsADfAAAcAAgK5AVQsADfAAAAAA==.',
Sh='Sharun:BAAANQAECgcIDgAAAA==.Shireska:BAAANQADCggIDAAAAA==.Shori:BAAANQADCgMIAwAAAA==.',
Si='Sidehussy:BAABNQAECn8vAAIJAAoK2Rg8FgBSAgAJAAoK2Rg8FgBSAgAAAA==.',
So='Sorinmarkov:BAABNQAECn8fAAIEAAoKoxqaPABmAgAEAAoKoxqaPABmAgAAAA==.',
Sp='Spicidark:BAAANQAECgEIAQAAAA==.Sploçk:BAAANQAECgEIAQAAAA==.',
Sq='Squirt:BAAANQADCgcIBwABNQAECgQICAAUAAAAAA==.',
St='Starbøy:BAABNQAECn8fAAMcAAoK6xCDjQDFAQAcAAgKbRCDjQDFAQAjAAQK5g0kRAC1AAAAAA==.Stats:BAABNQAECn8XAAIKAAkKowtXJgCUAQAKAAkKowtXJgCUAQAAAA==.Stingerslick:BAABNQAECn83AAIlAAoKdAvOEwCKAQAlAAoKdAvOEwCKAQAAAA==.Stoompbda:BAAANQADCgQIBAAAAA==.Stormtusk:BAAANQADCgUIBQABNQAECgQIBwAUAAAAAA==.',
Sy='Syehanan:BAAANQADCgcICgAAAA==.',
Ta='Tazrii:BAAANQADCggICAAAAA==.',
Th='Thorfine:BAABNQAECn86AAMLAAoKKBq8BwBbAgALAAkKKBq8BwBbAgADAAoKFA9gcgCWAQAAAA==.',
Ti='Tinymittenz:BAAANQAECgYICAAAAA==.',
To='Toetaah:BAAANQADCggICAAAAA==.Togetic:BAAANQAECgEIAQAAAA==.Touraine:BAAANQAECgYIDAAAAA==.',
Tr='Traedalei:BAAANQADCgMIAwAAAA==.Trajann:BAAANQADCgIIAgAAAA==.Trayndra:BAAANQAECgUIBgAAAA==.',
Ty='Tycharious:BAAANQADCggICAABNQAECggIFQAiAPsZAA==.',
Uk='Uka:BAAANQADCgYIBgABNQAECggIJgAZAGwPAA==.',
Un='Unmei:BAABNQAECn8jAAMhAAkKrgjirwAzAQAhAAgK7QXirwAzAQAfAAcKiQUdsgAKAQAAAA==.',
Va='Valkrynd:BAAANQAECgIIAgAAAA==.Valynor:BAABNQAECn8aAAIEAAkKZh5KKAC0AgAEAAkKZh5KKAC0AgABNQAECgoKNQAKAMkgAA==.Varaz:BAABNQAECn8ZAAMJAAcKURLsLAA/AQAJAAYKeg/sLAA/AQAeAAUKThH4JAAWAQAAAA==.',
Ve='Vendle:BAABNQAECn8zAAMRAAoK9xtMTwAaAgARAAoK9xtMTwAaAgACAAEKyQssjwAwAAAAAA==.',
Wa='Wapow:BAAANQAECgUICQAAAA==.Wazo:BAAANQADCgcIBwAAAA==.',
Wi='Windrunners:BAABNQAECn8WAAQMAAYKcw/AZgAyAQAMAAYKcw/AZgAyAQANAAEKFQYPewAoAAAOAAEK0wBlUgAJAAAAAA==.',
Xe='Xenophon:BAAANQADCgYICwAAAA==.',
Xo='Xolthoras:BAABNQAECn8lAAMHAAkKZR04OwAYAgAHAAYKLR84OwAYAgAEAAkKoBOUfwC5AQAAAA==.',
Xu='Xuedk:BAAANQAECgQIDgAAAA==.',
Ya='Yaoi:BAAANQAECggICAAAAA==.',
Yo='Yohshee:BAAANQAECgcICAAAAA==.',
Za='Zap:BAABNQAECn8uAAIhAAoKnhHtNADtAQAhAAoKnhHtNADtAQAAAA==.Zargabaath:BAAANQAECgQIBQAAAA==.',
Ze='Zebranjin:BAAANQADCgUICQAAAA==.Zeldoris:BAABNQAECn86AAQbAAoKjSBdDADUAgAbAAoKjSBdDADUAgAHAAQKEQl/tQCfAAAEAAEKLxCQjgExAAAAAA==.',
Zi='Zirina:BAAANQAECggIEQAAAA==.',
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
