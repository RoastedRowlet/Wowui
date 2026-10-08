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

local lookup = {'Hunter-Marksmanship','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Holy','Evoker-Preservation','Rogue-Subtlety','Druid-Balance','Druid-Restoration','Mage-Arcane','Hunter-BeastMastery','Monk-Windwalker','Unknown-Unknown','Warrior-Protection','Warrior-Arms','Monk-Mistweaver','Priest-Shadow','Priest-Holy','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Protection','Monk-Brewmaster','Shaman-Restoration','Hunter-Survival','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Devastation','Rogue-Assassination','Shaman-Elemental',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=53,date='2026-10-06',data={Ah='Ahote:BAAANQAECgUIEAAAAA==.',
Ai='Airrows:BAABNQAECoEaAAIBAAgKABoPFwCKAgABAAgKABoPFwCKAgAAAA==.',
Al='Alaois:BAAANQAECgYIEgAAAA==.Alatar:BAAANQADCgMIAwAAAA==.Almitywitey:BAAANQAECgMIBQAAAA==.Alphaomega:BAAANQAECgIIAgAAAA==.Alurea:BAAANQAECgEIBAAAAA==.',
Am='Ampharosen:BAAANQAECgcIBwAAAA==.',
An='Anthredis:BAACNQAFFIEdAAICAAcKLxYQAQCTAgACAAcKLxYQAQCTAgA1AAQKgSEAAwIACQoTILUMAAkDAAIACQoTILUMAAkDAAMAAgoWCopzAG8AAAAA.Anvi:BAAANQADCgYIDQAAAA==.',
Ar='Ara:BAACNQAFFIERAAIEAAcKwSOgAADOAgAEAAcKwSOgAADOAgA1AAQKgSYAAgQACQqHJuUAAOMDAAQACQqHJuUAAOMDAAAA.Argonäut:BAABNQAECoEjAAIDAAgKYyL/DQAfAwADAAgKYyL/DQAfAwAAAA==.',
As='Asmindissa:BAAANQAECgMIAgAAAA==.Astragos:BAABNQAECoEZAAIFAAgKbBR/GQAOAgAFAAgKbBR/GQAOAgAAAA==.',
Au='Automedusa:BAAANQADCgYICwAAAA==.',
Az='Azagorod:BAAANQADCgQIBAABNQAECgkJHgAGAI0eAA==.',
Ba='Baern:BAAANQAECgEIBAAAAA==.',
Be='Bearricade:BAABNQAECoEiAAMHAAgKKxaQMgAqAgAHAAgKKxaQMgAqAgAIAAYKNxJhMQBbAQAAAA==.',
Bi='Billamong:BAAANQAECgEIBAAAAA==.Biren:BAAANQADCgYIBgAAAA==.',
Bl='Blitzer:BAAANQAECgQICQAAAA==.',
Bo='Bonechill:BAAANQAECgQIBAAAAA==.Boney:BAAANQABCgQIBgAAAA==.',
Br='Brightstorm:BAAANQAECgEIAQAAAA==.Brisket:BAAANQAECgcIDAABNQAECggIIgAHACsWAA==.',
Ca='Calciferkyo:BAABNQAECoEXAAIJAAcKhwSDFAFDAQAJAAcKhwSDFAFDAQAAAA==.Cassilune:BAAANQADCgcIBwABNQAECggIKQAEAEwbAA==.Catelaya:BAABNQAECoEhAAIKAAgKVhF3ZwAaAgAKAAgKVhF3ZwAaAgAAAA==.',
Ch='Chaosrows:BAAANQADCggICAAAAA==.Chexk:BAABNQAECoEeAAIGAAkKjR6bBQAmAwAGAAkKjR6bBQAmAwAAAA==.Chixnu:BAAANQAECgIIAgAAAA==.Chushing:BAABNQAECoEkAAILAAkKjB63DAD1AgALAAkKjB63DAD1AgAAAA==.',
Co='Conejomalo:BAAANQAECgcIEQAAAA==.',
Cr='Cryblood:BAAANQAECgQIBQAAAA==.',
Cu='Cutsiecow:BAABNQAECoEoAAIHAAkKhB7RFAAKAwAHAAkKhB7RFAAKAwAAAA==.',
Cy='Cynos:BAAANQADCgEIAQAAAA==.Cynthic:BAAANQAECgQICAAAAA==.',
Da='Daelynn:BAAANQAECgUICgAAAA==.Daffodil:BAAANQABCgIIBAAAAA==.',
De='Deathpluck:BAAANQADCgUICQABNQAECgUICQAMAAAAAA==.',
Dj='Djiinar:BAABNQAECoEmAAMNAAgK8Ru4DQApAgANAAcKKhu4DQApAgAOAAgKjxUCdQAVAgAAAA==.Djiink:BAAANQADCgIIAgAAAA==.Djiinra:BAAANQADCgcIBwAAAA==.Djiinz:BAAANQADCgcIBwAAAA==.',
Do='Doomlocke:BAABNQAECoEcAAMLAAgK4gioLgBvAQALAAgK4gioLgBvAQAPAAMKGgN8PQBbAAAAAA==.',
Eb='Ebonymoon:BAAANQABCgQIBAAAAA==.',
El='Elise:BAACNQAFFIEkAAMQAAgKFSE4AAAvAwAQAAgKFSE4AAAvAwARAAEKoRjCLQBIAAA1AAQKgSEAAxAACQppJnkEAIQDABAACQppJnkEAIQDABEAAQotFtPYAEsAAAAA.',
Em='Em:BAAANQAECgcIEwAAAA==.',
En='Enzo:BAAANQAECgMIAwAAAA==.',
Er='Eraline:BAABNQAECoEjAAIPAAgK+A9BGgCvAQAPAAgK+A9BGgCvAQAAAA==.Erisa:BAAANQAECgUICAAAAA==.',
Fa='Facehunter:BAAANQAECgIIAwAAAA==.Faelyn:BAAANQADCgUIDAAAAA==.',
Fc='Fcawf:BAAANQADCgIIAgAAAA==.',
Fe='Fearless:BAABNQAECoEWAAISAAcK2SOEIACoAgASAAcK2SOEIACoAgAAAA==.Felygog:BAAANQADCgQIBwAAAA==.Fenrirblood:BAAANQAECgcIEQAAAA==.',
Fi='Fiizz:BAAANQAECgEIAQAAAA==.Firecaneost:BAAANQADCgcIBwAAAA==.Fiyer:BAAANQADCgQIBAAAAA==.Fizzlepriest:BAAANQADCggIDgABNQAECggIEgAMAAAAAA==.',
Fr='Fraydun:BAAANQADCggICwAAAA==.Frostblood:BAAANQAECgQICAAAAA==.',
Fu='Fuknar:BAAANQADCgUIBQAAAA==.Funk:BAAANQADCgIIAgABNQAFFAYIGwATAEEgAA==.',
Ge='Genivan:BAAANQADCgQICgAAAA==.Genocya:BAAANQAECgYJDAAAAA==.',
Gh='Ghost:BAAANQAECgQIBwAAAA==.',
Gi='Gilden:BAAANQAECgIIAgAAAA==.',
Gn='Gnot:BAAANQAECgQIBgAAAA==.',
Go='Goshujinsama:BAAANQADCgYJCAAAAA==.',
Gr='Griz:BAAANQAECgcICAAAAA==.',
Gy='Gyoza:BAAANQAECgIIAgABNQAECggIIgAHACsWAA==.',
['Gò']='Gòddess:BAAANQAECgMIAwAAAA==.',
Ha='Hannahsmad:BAAANQAECgQIBQAAAA==.Harlee:BAAANQAECgQIBAAAAA==.Haukkah:BAABNQAECoEeAAIKAAcKgAjCnACbAQAKAAcKgAjCnACbAQAAAA==.',
He='Heffalump:BAABNQAECoEbAAIHAAgKdBJIOwDvAQAHAAgKdBJIOwDvAQAAAA==.Hetfield:BAAANQAECgIIAgAAAA==.Hexanyth:BAAANQADCgQIBAAAAA==.',
Ho='Holycrves:BAAANQADCgQIBAAAAA==.',
['Hï']='Hïbiki:BAAANQADCgQIBQAAAA==.',
If='Ifa:BAAANQADCgQICAAAAA==.',
Im='Impact:BAAANQADCgcIEQABNQAECggIIwAUAFYfAA==.',
In='Inazuma:BAAANQADCgYICwAAAA==.Innerlect:BAAANQADCgYIBgABNQAECgUIBQAMAAAAAA==.',
Is='Ishalich:BAAANQADCggIEQAAAA==.',
Iy='Iyotanka:BAAANQADCgUIDAAAAA==.',
Ja='Jameo:BAAANQAECgYIDAABNQAECgUICQAMAAAAAA==.',
Ji='Jig:BAAANQAECgYIDwABNQAECgUICQAMAAAAAA==.',
Ju='Juicebox:BAAANQADCggICQABNQAECgkJKAAVABsNAA==.Juuzau:BAAANQAECgEIAQAAAA==.',
['Jå']='Jåmes:BAAANQAECgEIAQAAAA==.',
Ka='Kaners:BAABNQAECoEcAAIGAAgKNiBnCQDTAgAGAAgKNiBnCQDTAgAAAA==.Kathoran:BAAANQAECgUIEgAAAA==.Katie:BAAANQAECgMIAwABNQAFFAcIHAAWAO4jAA==.',
Ke='Kealey:BAAANQAECgUIBwAAAA==.Kessik:BAAANQAECgYICwAAAA==.',
Kh='Khaless:BAAANQAECgIIAgAAAA==.',
Ki='Kiamors:BAAANQAECgUIEgAAAA==.',
Ko='Kolaid:BAAANQADCgIIAgAAAA==.',
Kr='Kragzug:BAAANQAECgYIEwAAAA==.Kreleing:BAAANQADCgIIAgAAAA==.',
La='Labiaminoris:BAAANQADCgQIAwAAAA==.',
Le='Leda:BAAANQADCgUIDAAAAA==.Lexy:BAAANQADCgEIAQAAAA==.',
Li='Lightfighter:BAAANQAECgUICQAAAA==.Lighthouse:BAACNQAFFIEbAAITAAYKQSAvAwA+AgATAAYKQSAvAwA+AgA1AAQKgR8AAxMACQpvI2oMAD4DABMACQpvI2oMAD4DABIAAwpJFZ+UALYAAAAA.Lilkiwi:BAAANQAECgIIAgAAAA==.Linley:BAAANQADCggICAAAAA==.',
Lo='Loozer:BAABNQAECoEmAAIXAAgKVh2IAwCsAgAXAAgKVh2IAwCsAgAAAA==.',
Lu='Lunchbox:BAAANQAECgQIBwAAAA==.Lunecy:BAAANQAECgMIBAAAAA==.',
Ly='Lyumi:BAAANQAECgYIDAAAAA==.',
['Lå']='Låz:BAAANQADCggIFQAAAA==.',
Ma='Matty:BAAANQAECgcIEgABNQAFFAUIDwAJAN0ZAA==.Maxkiwi:BAAANQADCgMJBAAAAA==.Mazikeenx:BAAANQADCgEIAQAAAA==.',
Me='Medie:BAABNQAECoEcAAIRAAgK3hkAOwBaAgARAAgK3hkAOwBaAgAAAA==.Melody:BAAANQAECgQIBgAAAA==.',
Mi='Michelle:BAABNQAECoEgAAMEAAgKcSKfEwAjAwAEAAgKcSKfEwAjAwAYAAEKqw+/dwEyAAAAAA==.',
Mo='Monstrosity:BAAANQAECgIIAwABNQAECggIDwAMAAAAAA==.',
['Mä']='Mäenard:BAAANQADCgcIDgAAAA==.',
Na='Naji:BAACNQAFFIEJAAQZAAQKYiJ7AwDYAAAZAAIK3SR7AwDYAAAaAAEKmSbcLwBzAAAbAAEKNhlHCQBNAAA1AAQKgSoABBkACQpHJH8KAEUCABoABgouJEBIAFwCABkABwpDHn8KAEUCABsABAqoICUOAEsBAAAA.',
Ne='Necro:BAAANQADCgUICgAAAA==.Neesa:BAAANQADCgMIAwABNQAECgkJKQAQABUgAA==.',
Ni='Ninguem:BAAANQAECgUIBgAAAA==.',
No='Noodge:BAAANQADCgQIBAAAAA==.Nostariel:BAAANQAECgIIAgAAAA==.Noxadin:BAAANQAECgEIAQAAAA==.',
Nu='Nutshotz:BAAANQABCgIIAwAAAA==.',
Pe='Peterpiper:BAABNQAECoEcAAIcAAgKRxP6EwDvAQAcAAgKRxP6EwDvAQAAAA==.',
['Pè']='Pètitemort:BAAANQADCgMIAwAAAA==.',
Ra='Raymane:BAAANQAECgIIAgAAAA==.',
Re='Reverendbdt:BAAANQADCgQIBQABNQAECgUIBQAMAAAAAA==.',
Ri='Rivanon:BAAANQADCggICAAAAA==.',
Ro='Rosastrasza:BAAANQADCgYICgAAAA==.',
Ru='Ruhster:BAAANQADCggIEAAAAA==.Ruthos:BAAANQAECgMIBwAAAA==.',
Ry='Rykka:BAAANQAECgUIEwAAAA==.Ryukie:BAAANQADCggICgAAAA==.',
Sa='Sathoran:BAAANQADCgQIBAAAAA==.Savall:BAAANQAECgYICwAAAA==.',
Se='Servatal:BAAANQAECgUIDQAAAA==.',
Sh='Sharun:BAAANQAECgIIAgAAAA==.Shireska:BAAANQADCgQIBAAAAA==.Shori:BAAANQADCgMIAwAAAA==.',
Si='Sidehussy:BAABNQAECoEeAAIFAAgK4RjdEwBdAgAFAAgK4RjdEwBdAgAAAA==.',
So='Sorinmarkov:BAAANQAECgEIAgAAAA==.',
Sq='Squirt:BAAANQADCgcIBwABNQAECgQICAAMAAAAAA==.',
St='Stats:BAAANQAECgYIDAAAAA==.Stingerslick:BAABNQAECoEfAAIdAAgKYwm0NgC+AQAdAAgKYwm0NgC+AQAAAA==.Stoompbda:BAAANQADCgQIBAAAAA==.Stormtusk:BAAANQADCgUIBQABNQAECgQIBwAMAAAAAA==.',
Sy='Syehanan:BAAANQADCgcICgAAAA==.',
Ta='Tazrii:BAAANQADCggICAAAAA==.',
Th='Thorfine:BAABNQAECoEZAAMOAAYKNwynwABIAQAOAAYKNwynwABIAQANAAIKMQejNQBQAAAAAA==.',
To='Toetaah:BAAANQADCggICAAAAA==.Touraine:BAAANQAECgYIDAAAAA==.',
Tr='Traedalei:BAAANQADCgMIAwAAAA==.Trajann:BAAANQADCgIIAgAAAA==.Trayndra:BAAANQAECgUIBgAAAA==.',
Ty='Tycharious:BAAANQADCggICAABNQAECggIFQAXAFEaAA==.',
Un='Unmei:BAABNQAECoEZAAMWAAcKrQSHngANAQAWAAcKrQSHngANAQAeAAYK/gUErQAKAQAAAA==.',
Va='Valkrynd:BAAANQAECgIIAgAAAA==.Valynor:BAAANQAECgcIBwABNQAECgkJHgAGAI0eAA==.Varaz:BAAANQAECgYIEwAAAA==.',
Ve='Vendle:BAABNQAECoEiAAMKAAgKoRlIRgBzAgAKAAgKoRlIRgBzAgABAAEKyQs5fwAwAAAAAA==.',
Wa='Wapow:BAAANQAECgUJCQAAAA==.Wazo:BAAANQADCgcIBwAAAA==.',
Wi='Windrunners:BAAANQAECgQICgAAAA==.',
Xe='Xenophon:BAAANQADCgYICwAAAA==.',
Xo='Xolthoras:BAAANQAECgcIBwAAAA==.',
Xu='Xuedk:BAAANQAECgQICQAAAA==.',
Yo='Yohshee:BAAANQAECgUIBgAAAA==.',
Za='Zap:BAABNQAECoEZAAIeAAcKwRMBYgDLAQAeAAcKwRMBYgDLAQAAAA==.Zargabaath:BAAANQAECgQIBQAAAA==.',
Ze='Zebranjin:BAAANQADCgUICAAAAA==.Zeldoris:BAABNQAECoEjAAIUAAgKVh/KCwC8AgAUAAgKVh/KCwC8AgAAAA==.',
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
