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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Holy','Evoker-Preservation','Rogue-Subtlety','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Monk-Windwalker','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Priest-Shadow','Priest-Holy','Monk-Mistweaver','DeathKnight-Blood','Paladin-Protection','Monk-Brewmaster','Shaman-Restoration','DeathKnight-Unholy','Hunter-Survival','Mage-Arcane','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Devastation','Hunter-Marksmanship',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=53,date='2026-09-29',data={Ah='Ahote:BAAANQAECgQIDAAAAA==.',
Ai='Airrows:BAAANQAECgYIEAAAAA==.',
Al='Alaois:BAAANQAECgQIDAAAAA==.Alatar:BAAANQADCgMIAwAAAA==.Almitywitey:BAAANQAECgMJBAAAAA==.Alphaomega:BAAANQAECgIIAgAAAA==.Alurea:BAAANQAECgEIAwAAAA==.',
An='Anthredis:BAACNQAFFIEXAAIBAAYKVxWoAgAQAgABAAYKVxWoAgAQAgA1AAQKgSEAAwEACQoTIBcKAB0DAAEACQoTIBcKAB0DAAIAAgoWCjJlAHEAAAAA.Anvi:BAAANQADCgYIDAAAAA==.',
Ar='Ara:BAACNQAFFIERAAIDAAcKwSNTAADdAgADAAcKwSNTAADdAgA1AAQKgSYAAgMACQqHJqEAAOkDAAMACQqHJqEAAOkDAAAA.Argonäut:BAABNQAECoEcAAICAAgKiSFFDgACAwACAAgKiSFFDgACAwAAAA==.',
As='Asmindissa:BAAANQAECgMIAgAAAA==.Astragos:BAABNQAECoEXAAIEAAgKbBSqFgAXAgAEAAgKbBSqFgAXAgAAAA==.',
Az='Azagorod:BAAANQADCgQIBAABNQAECggIHAAFABwhAA==.',
Ba='Baern:BAAANQAECgEIAwAAAA==.',
Be='Bearricade:BAABNQAECoEbAAMGAAgKkxWoKwA7AgAGAAgKkxWoKwA7AgAHAAUKxRBVNAAOAQAAAA==.',
Bi='Billamong:BAAANQAECgEIAwAAAA==.Biren:BAAANQADCgYIBgAAAA==.',
Bl='Blitzer:BAAANQAECgQICQAAAA==.',
Br='Brightstorm:BAAANQADCggIDwAAAA==.Brisket:BAAANQAECgUIBQAAAA==.',
Ca='Calciferkyo:BAAANQAECgYIDgAAAA==.Cassilune:BAAANQADCgcIBwABNQAECggIIQADAEwbAA==.Catelaya:BAABNQAECoEaAAIIAAgKwBD5WQAUAgAIAAgKwBD5WQAUAgAAAA==.',
Ch='Chexk:BAABNQAECoEcAAIFAAgKHCGGBgAEAwAFAAgKHCGGBgAEAwAAAA==.Chushing:BAABNQAECoEcAAIJAAgKshxJEgCFAgAJAAgKshxJEgCFAgAAAA==.',
Co='Conejomalo:BAAANQAECgcICwAAAA==.',
Cr='Cryblood:BAAANQAECgEIAQAAAA==.',
Cu='Cutsiecow:BAABNQAECoEgAAIGAAgKcR6wHACzAgAGAAgKcR6wHACzAgAAAA==.',
Cy='Cynos:BAAANQADCgEIAQAAAA==.Cynthic:BAAANQAECgQIBgAAAA==.',
Da='Daelynn:BAAANQAECgQIBQAAAA==.Daffodil:BAAANQABCgIIBAAAAA==.',
De='Deathpluck:BAAANQADCgUICQABNQAECgUICQAKAAAAAA==.',
Dj='Djiinar:BAABNQAECoEfAAMLAAgKdhfYYwAaAgALAAgKjxXYYwAaAgAMAAUKiRbJGQA5AQAAAA==.Djiink:BAAANQADCgIJAgAAAA==.Djiinra:BAAANQADCgcJBwAAAA==.Djiinz:BAAANQADCgcJBwAAAA==.',
Do='Doomlocke:BAAANQAECgYIEgAAAA==.',
El='Elise:BAACNQAFFIEiAAMNAAcKVyJpAADWAgANAAcKVyJpAADWAgAOAAEKoRihIwBTAAA1AAQKgR8AAw0ACQppJgsDAJoDAA0ACQppJgsDAJoDAA4AAQotFuu/AEsAAAAA.',
Em='Em:BAAANQAECgcIEwAAAA==.',
En='Enzo:BAAANQAECgMIAwAAAA==.',
Er='Eraline:BAABNQAECoEbAAIPAAgKlg5yGACgAQAPAAgKlg5yGACgAQAAAA==.Erisa:BAAANQAECgUICAAAAA==.',
Fa='Facehunter:BAAANQAECgIIAgAAAA==.Faelyn:BAAANQADCgUICAAAAA==.',
Fc='Fcawf:BAAANQADCgIIAgAAAA==.',
Fe='Fearless:BAAANQAECgcIEAAAAA==.Felygog:BAAANQADCgQIBwAAAA==.Fenrirblood:BAAANQAECgcIEQAAAA==.',
Fi='Fiizz:BAAANQAECgEIAQAAAA==.Firecaneost:BAAANQADCgcIBwAAAA==.Fizzlepriest:BAAANQADCggICAABNQAECggIDQAKAAAAAA==.',
Fr='Fraydun:BAAANQADCggICwAAAA==.Frostblood:BAAANQAECgQIBAAAAA==.',
Fu='Fuknar:BAAANQADCgUIBQAAAA==.Funk:BAAANQADCgIIAgABNQAFFAYIFQAQAEQfAA==.',
Ge='Genivan:BAAANQADCgQIBgAAAA==.Genocya:BAAANQAECgYJDAAAAA==.',
Gh='Ghost:BAAANQAECgQIBwAAAA==.',
Gn='Gnot:BAAANQAECgQIBAAAAA==.',
Go='Goshujinsama:BAAANQADCgYJCAAAAA==.',
Gr='Griz:BAAANQAECgcICAAAAA==.',
Gy='Gyoza:BAAANQADCggIDwABNQAECggIGwAGAJMVAA==.',
['Gò']='Gòddess:BAAANQAECgMIAwAAAA==.',
Ha='Hannahsmad:BAAANQAECgQIBQAAAA==.Harlee:BAAANQADCggIFwAAAA==.Haukkah:BAABNQAECoEYAAIIAAcKVwj0hwCYAQAIAAcKVwj0hwCYAQAAAA==.',
He='Heffalump:BAAANQAECgYIEQAAAA==.Hetfield:BAAANQADCgcIEwAAAA==.',
['Hï']='Hïbiki:BAAANQADCgQIBQAAAA==.',
If='Ifa:BAAANQADCgQICAAAAA==.',
Im='Impact:BAAANQADCgcIEQABNQAECggIHAARAJkdAA==.',
In='Inazuma:BAAANQADCgYICwAAAA==.Innerlect:BAAANQADCgYIBgABNQAECgQICQAKAAAAAA==.',
Is='Ishalich:BAAANQADCggIEQAAAA==.',
Iy='Iyotanka:BAAANQADCgUICAAAAA==.',
Ja='Jameo:BAAANQAECgUICQABNQAECgUICQAKAAAAAA==.',
Ji='Jig:BAAANQAECgYICgABNQAECgUICQAKAAAAAA==.',
Ju='Juicebox:BAAANQADCggICQABNQAECggIIgASABELAA==.Juuzau:BAAANQADCgcJCQAAAA==.',
['Jå']='Jåmes:BAAANQAECgEIAQAAAA==.',
Ka='Kaners:BAABNQAECoEcAAIFAAgKNiDbBwDnAgAFAAgKNiDbBwDnAgAAAA==.Kathoran:BAAANQAECgUIDgAAAA==.Katie:BAAANQAECgMIAwABNQAFFAYIFgATALskAA==.',
Ke='Kealey:BAAANQAECgIIAgAAAA==.Kessik:BAAANQAECgQIBQAAAA==.',
Ki='Kiamors:BAAANQAECgUIDQAAAA==.',
Ko='Kolaid:BAAANQADCgIIAgAAAA==.',
Kr='Kragzug:BAAANQAECgYIDQAAAA==.Kreleing:BAAANQADCgIIAgAAAA==.',
La='Labiaminoris:BAAANQADCgMIAQAAAA==.',
Le='Leda:BAAANQADCgUICAAAAA==.Lexy:BAAANQADCgEIAQAAAA==.',
Li='Lightfighter:BAAANQAECgUICQAAAA==.Lighthouse:BAACNQAFFIEVAAIQAAYKRB+rAgAuAgAQAAYKRB+rAgAuAgA1AAQKgR8AAxAACQpvI5kJAE4DABAACQpvI5kJAE4DABQAAwpJFV55AMcAAAAA.Linley:BAAANQADCggICAAAAA==.',
Lo='Loozer:BAABNQAECoEgAAIVAAgKexw7AwCiAgAVAAgKexw7AwCiAgAAAA==.',
Lu='Lunchbox:BAAANQAECgEIAwAAAA==.Lunecy:BAAANQAECgMIBAAAAA==.',
Ly='Lyumi:BAAANQAECgYIDAAAAA==.',
['Lå']='Låz:BAAANQADCggIFQAAAA==.',
Ma='Matty:BAAANQAECgYICwABNQAFFAUICgAWAI0TAA==.Maxkiwi:BAAANQADCgMJBAAAAA==.Mazikeenx:BAAANQADCgEIAQAAAA==.',
Me='Medie:BAAANQAECgcIEgAAAA==.Melody:BAAANQAECgQIBgAAAA==.',
Mi='Michelle:BAABNQAECoEZAAMDAAcKuCEpJACoAgADAAcKuCEpJACoAgAXAAEKqw9ETgEyAAAAAA==.',
Mo='Monstrosity:BAAANQAECgIIAwAAAA==.',
['Mä']='Mäenard:BAAANQADCgcIBwAAAA==.',
Na='Naji:BAACNQAFFIEFAAMYAAIK4yQhDwBtAAAYAAEKnyQhDwBtAAAZAAEKJyUiKABnAAA1AAQKgScABBgACQq7IoQJAFECABgABwpDHoQJAFECABkABgrcIU9KADACABoABAqoIOYLAFYBAAAA.',
Ne='Necro:BAAANQADCgUICgAAAA==.Neesa:BAAANQADCgMIAwABNQAECgkJIAANAO0bAA==.',
Ni='Ninguem:BAAANQAECgUIBgAAAA==.',
No='Noodge:BAAANQADCgQIBAAAAA==.Noxadin:BAAANQAECgEIAQAAAA==.',
Nu='Nutshotz:BAAANQABCgIIAwAAAA==.',
Pe='Peterpiper:BAABNQAECoEcAAIbAAgKRxOtEQD6AQAbAAgKRxOtEQD6AQAAAA==.',
['Pè']='Pètitemort:BAAANQADCgMIAwAAAA==.',
Ra='Raymane:BAAANQADCggJEAAAAA==.',
Re='Reverendbdt:BAAANQADCgQIBQABNQAECgQICQAKAAAAAA==.',
Ri='Rivanon:BAAANQADCggICAAAAA==.',
Ro='Rosastrasza:BAAANQADCgYICgAAAA==.',
Ru='Ruhster:BAAANQADCggIEAAAAA==.Ruthos:BAAANQAECgMJBwAAAA==.',
Ry='Rykka:BAAANQAECgUIDwAAAA==.Ryukie:BAAANQADCggICgAAAA==.',
Sa='Sathoran:BAAANQADCgQIBAAAAA==.Savall:BAAANQAECgYICwAAAA==.',
Se='Servatal:BAAANQAECgQICAAAAA==.',
Sh='Shori:BAAANQADCgMIAwAAAA==.',
Si='Sidehussy:BAABNQAECoEcAAIEAAgK4RhxEQBmAgAEAAgK4RhxEQBmAgAAAA==.',
So='Sorinmarkov:BAAANQAECgEIAgAAAA==.',
Sq='Squirt:BAAANQADCgcIBwABNQAECgQICAAKAAAAAA==.',
St='Stats:BAAANQAECgUIBgAAAA==.Stingerslick:BAAANQAECgcIEwAAAA==.Stoompbda:BAAANQADCgQIBAAAAA==.Stormtusk:BAAANQADCgUIBQABNQAECgQIBwAKAAAAAA==.',
Sy='Syehanan:BAAANQADCgcICgAAAA==.',
Ta='Tazrii:BAAANQADCggICAAAAA==.',
Th='Thorfine:BAABNQAECoEUAAMLAAYKNwz7rABBAQALAAYKNwz7rABBAQAMAAIKMQfJLgBRAAAAAA==.',
To='Toetaah:BAAANQADCggICAAAAA==.Touraine:BAAANQAECgYIDAAAAA==.',
Tr='Traedalei:BAAANQADCgMIAwAAAA==.Trajann:BAAANQADCgIIAgAAAA==.Trayndra:BAAANQAECgUIBgAAAA==.',
Ty='Tycharious:BAAANQADCggICAABNQAECggIFQAVAFEaAA==.',
Un='Unmei:BAAANQAECgYIEAAAAA==.',
Va='Valkrynd:BAAANQAECgIIAgAAAA==.Valynor:BAAANQADCgYICgABNQAECggIHAAFABwhAA==.Varaz:BAAANQAECgYIEwAAAA==.',
Ve='Vendle:BAABNQAECoEbAAMIAAgKSxkCOwBzAgAIAAgKSxkCOwBzAgAcAAEKyQvEcAAwAAAAAA==.',
Wa='Wapow:BAAANQAECgUJCQAAAA==.Wazo:BAAANQADCgcIBwAAAA==.',
Wi='Windrunners:BAAANQAECgMIBgAAAA==.',
Xu='Xuedk:BAAANQAECgQICQAAAA==.',
Yo='Yohshee:BAAANQAECgUIBQAAAA==.',
Za='Zap:BAAANQAECgUIDwAAAA==.Zargabaath:BAAANQADCgYIBgAAAA==.',
Ze='Zebranjin:BAAANQADCgMIBAAAAA==.Zeldoris:BAABNQAECoEcAAIRAAgKmR3eCwCaAgARAAgKmR3eCwCaAgAAAA==.',
Zi='Zirina:BAAANQAECgQIBAAAAA==.',
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
