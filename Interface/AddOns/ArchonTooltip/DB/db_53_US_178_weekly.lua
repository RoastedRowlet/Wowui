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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Warrior-Arms','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Holy','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Subtlety','Druid-Balance','Druid-Restoration','Druid-Feral','Mage-Arcane','Hunter-BeastMastery','Monk-Windwalker','Unknown-Unknown','Warrior-Protection','Monk-Mistweaver','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Guardian','DeathKnight-Blood','Paladin-Protection','Warlock-Demonology','Monk-Brewmaster','Shaman-Restoration','Warrior-Fury','Shaman-Elemental','Hunter-Survival','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Rogue-Assassination',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=53,date='2026-11-03',data={Ah='Ahote:BAABNQAECn8dAAIBAAgK/BOGAgCOAQABAAgK/BOGAgCOAQAAAA==.',
Ai='Airrows:BAABNQAECn8xAAICAAoKjR/FBwCrAgACAAoKjR/FBwCrAgAAAA==.',
Al='Alaois:BAABNQAECn8lAAIDAAgK5RFecQB1AQADAAgK5RFecQB1AQAAAA==.Alatar:BAAANQADCgMIAwAAAA==.Almitywitey:BAAANQAECgYIDQAAAA==.Alphaomega:BAAANQAECgIIAgAAAA==.Alurea:BAAANQAECgQIDAAAAA==.Alèxis:BAAANQAECgIIAQAAAA==.',
Am='Ampharosen:BAABNQAECn8kAAIEAAkKNxOqYgDRAQAEAAkKNxOqYgDRAQAAAA==.',
An='Anguthar:BAAANQAECgQIBAAAAA==.Anigavnimuc:BAAANQADCgMIAwAAAA==.Anthredis:BAACNQAFFH8dAAIFAAcK6hYkAgBeAgAFAAcK6hYkAgBeAgA1AAQKfyIAAwUACgoyH2YRAOMCAAUACgoyH2YRAOMCAAYAAgoWCpyDAGkAAAAA.Anvi:BAAANQAECgEIAgAAAA==.',
Ar='Ara:BAACNQAFFH8TAAIHAAkK2CBlAAAgAwAHAAkK2CBlAAAgAwA1AAQKfzQAAgcACgp2JnQBANoDAAcACgp2JnQBANoDAAAA.Argonäut:BAABNQAECn9BAAMGAAoK9CMXDwArAwAGAAoK9CMXDwArAwAIAAUKYxiiDwAYAQAAAA==.Arimalo:BAAANQAECgQIBQAAAA==.',
As='Asmindissa:BAAANQAECgMIAgAAAA==.Astragos:BAABNQAECn8rAAIJAAoK/RXdDAAQAgAJAAoK/RXdDAAQAgAAAA==.',
Au='Automedusa:BAAANQADCgYICwAAAA==.',
Az='Azagorod:BAAANQAECgUIBQABNQAECgoKMQAKAFYgAA==.',
Ba='Baern:BAAANQAECgQIDgAAAA==.',
Be='Bearricade:BAABNQAECn8+AAQLAAoKCRSiJwCIAQALAAoKCRSiJwCIAQAMAAcKahQmOQBVAQANAAIKcw1oNQBtAAAAAA==.',
Bi='Bigdansell:BAAANQADCgEIAQAAAA==.Billamong:BAAANQAECgQIDAAAAA==.Biren:BAAANQADCgYIBgAAAA==.',
Bl='Blitzer:BAAANQAECgQICQAAAA==.',
Bo='Bonechill:BAAANQAECgUIBwAAAA==.Boney:BAAANQABCgQIBgAAAA==.',
Br='Brightstorm:BAAANQAECgIIAwAAAA==.Brisket:BAABNQAECn8mAAIDAAoKsQ5PUwDRAQADAAoKsQ5PUwDRAQABNQAECgoKPgALAAkUAA==.',
Bu='Bucko:BAAANQAECggICwABNQAFFAcIGgAOALcfAA==.',
Ca='Calciferkyo:BAABNQAECn8kAAIOAAoKnQRNygDqAAAOAAoKnQRNygDqAAAAAA==.Cassilune:BAAANQADCgcIBwABNQAECgoKSQAHAGUiAA==.Catelaya:BAABNQAECn9DAAIPAAoKeRgoNABFAgAPAAoKeRgoNABFAgAAAA==.',
Ch='Chaosrows:BAAANQADCggICAAAAA==.Chexk:BAABNQAECn8xAAIKAAoKViCvBABFAwAKAAoKViCvBABFAwAAAA==.Chixnu:BAAANQAECgUIBgAAAA==.Chushing:BAACNQAFFH8HAAIQAAIKag9vDAB9AAAQAAIKag9vDAB9AAA1AAQKfzYAAhAACgqrH4MOAPgCABAACgqrH4MOAPgCAAAA.',
Co='Come:BAAANQAECgUICQAAAA==.',
Cr='Crush:BAAANQAFFAIIAgABNQAFFAcIHAALAPAZAA==.Cryblood:BAAANQAECgYICwAAAA==.',
Cu='Curebear:BAAANQADCgEIAQAAAA==.Cutsiecow:BAACNQAFFH8HAAILAAMKoREfFQCQAAALAAMKoREfFQCQAAA1AAQKf0MAAgsACgoLIssJAOUCAAsACgoLIssJAOUCAAAA.',
Cy='Cynos:BAAANQADCgEIAQAAAA==.Cynthic:BAAANQAECgQICAAAAA==.',
Da='Daelynn:BAAANQAECgcIEgAAAA==.Daffodil:BAAANQABCgIIBAAAAA==.',
De='Deathpluck:BAAANQADCgUICQABNQAECggIDAARAAAAAA==.',
Dj='Djiinar:BAABNQAECn9AAAMSAAoKjh2iDABqAgASAAkK2RuiDABqAgADAAoK1xfBigABAgAAAA==.Djiink:BAAANQADCgIIAgAAAA==.Djiinra:BAAANQADCgcIBwAAAA==.Djiinz:BAAANQADCgcIBwAAAA==.',
Do='Doomlocke:BAABNQAECn83AAMQAAoKSxVuEQAWAgAQAAoKSxVuEQAWAgATAAMKGgOLRABaAAAAAA==.',
Du='Dunkie:BAAANQAECgQIBAAAAA==.',
Eb='Ebonymoon:BAAANQADCgMIBAAAAA==.',
El='Elise:BAACNQAFFH8yAAMUAAkKwCNAAACAAwAUAAkKwCNAAACAAwAVAAEKoRhVNABIAAA1AAQKfysAAxQACgp3JhkGAHYDABQACgp3JhkGAHYDABUAAQotFpzzAEkAAAAA.',
Em='Em:BAABNQAECn8sAAMVAAoKaR02EwATAwAVAAoKaR02EwATAwAUAAcKvQvEOQBYAQAAAA==.',
En='Enzo:BAAANQAECgMIAwAAAA==.',
Er='Eraline:BAABNQAECn89AAITAAoKOxG7DwDXAQATAAoKOxG7DwDXAQAAAA==.Erisa:BAAANQAECgUICAAAAA==.',
Ey='Eyekora:BAAANQADCgMIAwAAAA==.',
Fa='Facehunter:BAAANQAECgMIBgAAAA==.Faelyn:BAAANQADCgUIDAAAAA==.',
Fc='Fcawf:BAAANQADCgMICAAAAA==.',
Fe='Fearless:BAABNQAECn8yAAMWAAkKOCMhGgDwAgAWAAgKCyIhGgDwAgAXAAcK1CBtHQArAgAAAA==.Feitan:BAAANQAECgIIAgAAAA==.Felygog:BAAANQADCgQIBwAAAA==.Fenrirblood:BAABNQAECn8fAAQMAAkKHR1CGQByAgAMAAgKTxxCGQByAgAYAAcKcQwsPgDEAAALAAEKAAC6sAA1AAAAAA==.',
Fi='Fiizz:BAAANQAECgEIAQAAAA==.Firecaneost:BAAANQADCgcIBwAAAA==.Fiyer:BAAANQAECgUIBQAAAA==.Fizzlepriest:BAAANQADCggIDgABNQAECggIFQAEAGIXAA==.',
Fr='Fraydun:BAAANQADCggICwAAAA==.Frostblood:BAABNQAECn8dAAIGAAkK6gtyJgCaAQAGAAkK6gtyJgCaAQAAAA==.',
Fu='Fuknar:BAAANQADCgUIBQAAAA==.Funk:BAAANQADCgIIAgABNQAFFAcIHgAZAHMkAA==.',
Ge='Genivan:BAAANQAECgQIBAAAAA==.Genocya:BAAANQAECgYJDAAAAA==.',
Gh='Ghost:BAAANQAECgQIBwAAAA==.',
Gi='Gilden:BAAANQAECgYIDAAAAA==.',
Gn='Gnot:BAAANQAECgUIDQAAAA==.',
Go='Goshujinsama:BAAANQADCgYICAAAAA==.',
Gr='Griz:BAAANQAECgcICAAAAA==.',
Gy='Gyoza:BAAANQAECgIIAgABNQAECgoKPgALAAkUAA==.',
['Gò']='Gòddess:BAAANQAECgUIDAAAAA==.',
Ha='Hannahsmad:BAAANQAECgQIBQAAAA==.Harlee:BAAANQAECgUIDwAAAA==.Haukkah:BAABNQAECn8rAAIPAAoKzQqImwDQAQAPAAoKzQqImwDQAQAAAA==.Hawktuwah:BAAANQADCgEIAQAAAA==.',
He='Heffalump:BAABNQAECn8oAAILAAoKAhQwKwBuAQALAAoKAhQwKwBuAQAAAA==.Hetfield:BAAANQAECgYIDAAAAA==.Hexanyth:BAAANQADCgQIBAAAAA==.',
Ho='Holycrves:BAAANQADCgQICwAAAA==.',
['Hï']='Hïbiki:BAAANQAECgEIAQAAAA==.',
If='Ifa:BAAANQADCgQICAAAAA==.',
Im='Impact:BAAANQAECgQIBAABNQAECgoKOgAaAI0gAA==.',
In='Inazuma:BAAANQADCgYICwAAAA==.Innerlect:BAAANQADCgYIBgABNQAECgoKLAAKAC0MAA==.',
Ir='Iridian:BAAANQAECgUICQAAAA==.',
Is='Ishalich:BAAANQADCggIEQABNQAECgYICgARAAAAAA==.',
Iy='Iyotanka:BAAANQADCgUIDQAAAA==.',
Ja='Jakoby:BAAANQAECgEIAQAAAA==.Jameo:BAABNQAECn8cAAIbAAkK6wiqnQCcAQAbAAkK6wiqnQCcAQABNQAECggIDAARAAAAAA==.',
Ji='Jig:BAAANQAECgcIEgABNQAECggIDAARAAAAAA==.',
Ju='Juicebox:BAAANQADCggICQABNQAECgoKQgAcAEgTAA==.Juuzau:BAAANQAECgUICAAAAA==.',
['Jå']='Jåmes:BAAANQAECgEIAQAAAA==.',
Ka='Kaners:BAABNQAECn8iAAIKAAkKBCAvCwDBAgAKAAkKBCAvCwDBAgAAAA==.Kathoran:BAABNQAECn8dAAIPAAYKGQgS2gBMAQAPAAYKGQgS2gBMAQAAAA==.Katie:BAAANQAECggIEwABNQAFFAcIHAAdAO4jAA==.',
Ke='Kealey:BAABNQAECn8YAAIEAAcKBgnF0wD0AAAEAAcKBgnF0wD0AAAAAA==.Kessik:BAABNQAECn8bAAMDAAoK0Q4HgABQAQADAAoKZQ4HgABQAQAeAAIKgw2zIQBjAAAAAA==.',
Kh='Khaless:BAAANQAECgUICgAAAA==.',
Ki='Kiamors:BAABNQAECn8zAAMfAAkKcQNJhgDJAAAfAAkKcQNJhgDJAAAdAAgK9AGXrACXAAAAAA==.Kieru:BAAANQAECgIIAgABNQAECgoKPgALAAkUAA==.',
Ko='Kobee:BAAANQAECgUIBQAAAA==.Kolaid:BAAANQADCgMICQAAAA==.',
Kr='Kragzug:BAABNQAECn8XAAMDAAcKXBmSlwDhAQADAAcKXBmSlwDhAQAeAAMKbR1rGwDxAAAAAA==.Kreleing:BAAANQADCgMIBAAAAA==.',
La='Labiaminoris:BAAANQADCgQIAwAAAA==.',
Le='Leda:BAAANQADCgUIDQAAAA==.Lexy:BAAANQADCgEIAQAAAA==.',
Li='Lightfighter:BAAANQAECggIDAAAAA==.Lighthouse:BAACNQAFFH8eAAIZAAcKcySiBAA0AgAZAAcKcySiBAA0AgA1AAQKfykAAxkACgrSJB0QACwDABkACgrSJB0QACwDABYAAwpJFRWjALQAAAAA.Lilkiwi:BAAANQAECgYIDQAAAA==.Linley:BAAANQADCggICAAAAA==.',
Lo='Loozer:BAABNQAECn8vAAIgAAkK2R7wAgDyAgAgAAkK2R7wAgDyAgAAAA==.',
Lu='Lunchbox:BAABNQAECn8cAAIgAAcKlAYtCQATAQAgAAcKlAYtCQATAQAAAA==.Lunecy:BAAANQAECgMIBAAAAA==.',
Ly='Lyumi:BAAANQAECgYIDAAAAA==.',
['Lå']='Låz:BAAANQAECgQIBAAAAA==.',
Ma='Matty:BAABNQAECn8bAAIEAAkKRxD7fwApAgAEAAkKRxD7fwApAgABNQAFFAcIGgAOALcfAA==.Maxkiwi:BAAANQADCgMJBAAAAA==.Mazikeenx:BAAANQADCgEIAQAAAA==.',
Me='Medie:BAABNQAECn8oAAMVAAoKXBgBRgBVAgAVAAoKXBgBRgBVAgAUAAIKBQ6DRQBlAAAAAA==.Melody:BAAANQAECgUIDQAAAA==.',
Mi='Michelle:BAABNQAECn8rAAMHAAoKiyNDFQArAwAHAAgKUSNDFQArAwAEAAUKKQ9K3QDkAAAAAA==.Mitsuki:BAAANQADCgcIBwAAAA==.',
Mo='Monstrosity:BAAANQAECgUICQABNQAECggICAARAAAAAA==.',
My='Mystikan:BAAANQADCgMIAwABNQAECgUIDwARAAAAAA==.',
['Mä']='Mäenard:BAAANQADCgcIFQAAAA==.',
Na='Naji:BAACNQAFFH8SAAQhAAYKniVzBADRAAAbAAUKyiV+CgA3AQAhAAIK3SRzBADRAAAiAAEKAAAQDABNAAA1AAQKfz8ABBsACgpnJiYBAHwDABsACgpnJiYBAHwDACEABwoyHrQLADwCACIABAo3IGMQAEcBAAAA.',
Ne='Necro:BAAANQADCgUICgAAAA==.Neesa:BAAANQADCgMIAwABNQAFFAQICgAUAIAQAA==.',
Ni='Ninguem:BAAANQAECgYIEAAAAA==.',
No='Noodge:BAAANQADCggIDAAAAA==.Nostariel:BAAANQAECgYIDAAAAA==.Noxadin:BAAANQAECgEIAQAAAA==.',
Nu='Nutshotz:BAAANQABCgIIAwAAAA==.',
Pa='Paladineela:BAAANQADCgYIBAAAAA==.',
Pe='Peterpiper:BAABNQAECn8lAAIjAAoKcxFzFAAHAgAjAAoKcxFzFAAHAgAAAA==.',
Po='Poughkeepsie:BAAANQABCgUIBQABNQAECgoKLgAKAMwZAA==.',
['Pè']='Pètitemort:BAAANQADCgMIAwAAAA==.',
Ra='Raymane:BAAANQAECgUICQAAAA==.Rayvash:BAAANQAECgIIAgAAAA==.',
Re='Reverendbdt:BAAANQADCgYICwABNQAECgoKLAAKAC0MAA==.',
Ri='Rivanon:BAAANQADCggICAAAAA==.',
Ro='Rosastrasza:BAAANQADCgYIDQAAAA==.',
Ru='Ruhster:BAAANQADCggIEAAAAA==.Ruthos:BAAANQAECgMIBwAAAA==.',
Ry='Rykka:BAABNQAECn8gAAIPAAYKrAii5QA2AQAPAAYKrAii5QA2AQAAAA==.Ryukie:BAAANQADCggICgAAAA==.',
Sa='Sathoran:BAAANQADCgQIBAAAAA==.Savall:BAAANQAECgYICwAAAA==.',
Se='Servatal:BAABNQAECn8hAAIbAAgK5AWAoADgAAAbAAgK5AWAoADgAAAAAA==.',
Sh='Sharun:BAAANQAECgYIDAAAAA==.Shireska:BAAANQADCggIDAAAAA==.Shori:BAAANQADCgMIAwAAAA==.',
Si='Sidehussy:BAABNQAECn8vAAIJAAoK2Rg8FgBSAgAJAAoK2Rg8FgBSAgAAAA==.',
So='Sorinmarkov:BAAANQAECggIEwAAAA==.',
Sp='Sploçk:BAAANQAECgEIAQAAAA==.',
Sq='Squirt:BAAANQADCgcIBwABNQAECgQICAARAAAAAA==.',
St='Starbøy:BAABNQAECn8fAAMbAAoK6xCDjQDFAQAbAAgKbRCDjQDFAQAhAAQK5g0kRAC1AAAAAA==.Stats:BAABNQAECn8XAAIKAAkKowtXJgCUAQAKAAkKowtXJgCUAQAAAA==.Stingerslick:BAABNQAECn8xAAIkAAoKdAs7EgCKAQAkAAoKdAs7EgCKAQAAAA==.Stoompbda:BAAANQADCgQIBAAAAA==.Stormtusk:BAAANQADCgUIBQABNQAECgQIBwARAAAAAA==.',
Sy='Syehanan:BAAANQADCgcICgAAAA==.',
Ta='Tazrii:BAAANQADCggICAAAAA==.',
Th='Thorfine:BAABNQAECn8yAAMSAAoKFRlLBwBBAgASAAkKFRlLBwBBAgADAAoK3A4xbACDAQAAAA==.',
Ti='Tinymittenz:BAAANQAECgUIBgAAAA==.',
To='Toetaah:BAAANQADCggICAAAAA==.Touraine:BAAANQAECgYIDAAAAA==.',
Tr='Traedalei:BAAANQADCgMIAwAAAA==.Trajann:BAAANQADCgIIAgAAAA==.Trayndra:BAAANQAECgUIBgAAAA==.',
Ty='Tycharious:BAAANQADCggICAABNQAECggIFQAgAPsZAA==.',
Uk='Uka:BAAANQADCgYIBgABNQAECgcIIAAYACYPAA==.',
Un='Unmei:BAABNQAECn8jAAMfAAkKrgjirwAzAQAfAAgK7QXirwAzAQAdAAcKiQUdsgAKAQAAAA==.',
Va='Valkrynd:BAAANQAECgIIAgAAAA==.Valynor:BAABNQAECn8YAAIEAAkKvxtpJwCdAgAEAAkKvxtpJwCdAgABNQAECgoKMQAKAFYgAA==.Varaz:BAABNQAECn8ZAAMJAAcKURLsLAA/AQAJAAYKeg/sLAA/AQAjAAUKThH4JAAWAQAAAA==.',
Ve='Vendle:BAABNQAECn8zAAMPAAoK9xvxPwAeAgAPAAoK9xvxPwAeAgACAAEKyQssjwAwAAAAAA==.',
Wa='Wapow:BAAANQAECgUICQAAAA==.Wazo:BAAANQADCgcIBwAAAA==.',
Wi='Windrunners:BAAANQAECgQIEgAAAA==.',
Xe='Xenophon:BAAANQADCgYICwAAAA==.',
Xo='Xolthoras:BAABNQAECn8kAAMHAAkKQx1uNAAYAgAHAAYK+h5uNAAYAgAEAAkKoBMUcgCrAQAAAA==.',
Xu='Xuedk:BAAANQAECgQICgAAAA==.',
Ya='Yaoi:BAAANQAECggICAAAAA==.',
Yo='Yohshee:BAAANQAECgcICAAAAA==.',
Za='Zap:BAABNQAECn8uAAIfAAoKnhEhLQDxAQAfAAoKnhEhLQDxAQAAAA==.Zargabaath:BAAANQAECgQIBQAAAA==.',
Ze='Zebranjin:BAAANQADCgUICQAAAA==.Zeldoris:BAABNQAECn86AAQaAAoKjSBdDADUAgAaAAoKjSBdDADUAgAHAAQKEQnBowCsAAAEAAEKLxAWcgExAAAAAA==.',
Zi='Zirina:BAAANQAECgcICwAAAA==.',
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
