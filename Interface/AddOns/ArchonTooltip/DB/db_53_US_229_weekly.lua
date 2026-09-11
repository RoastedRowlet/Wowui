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

local lookup = {'Unknown-Unknown','Monk-Windwalker','Warlock-Affliction','Warlock-Demonology','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Paladin-Holy','Paladin-Retribution',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abmikaze:BAAANQADCgEIAQAAAA==.Abysseon:BAAANQAECgQIBQAAAA==.',
Ac='Ace:BAAANQAECgMIAwAAAA==.',
Ad='Adios:BAAANQAFFAIIAwAAAA==.Adorean:BAAANQAECgEIAQAAAA==.',
Ag='Age:BAAANQADCggIEQAAAA==.Agrohn:BAAANQADCgIIAgAAAA==.',
Ai='Aimnskin:BAAANQADCgYIDwAAAA==.',
Al='Alcore:BAAANQAECgEIAQAAAA==.Aliine:BAAANQADCggIEgAAAA==.',
Am='Ameiisaa:BAAANQAECgEIAQAAAA==.Amethaendron:BAAANQADCgYIBwAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAAANQAECgcIEAAAAA==.',
An='Anìtamaxwynn:BAAANQADCgQIBAABNQAFFAEIAQABAAAAAA==.',
Ao='Aoifae:BAAANQADCgYICAAAAA==.',
Ap='Applecider:BAAANQAECgYICAAAAA==.Apprentice:BAAANQAECgEIAQAAAA==.',
Ar='Aramos:BAAANQAECgQIBQAAAA==.Aramôs:BAAANQADCgYIDAAAAA==.Arkhangel:BAAANQAECgIIAgAAAA==.Arta:BAAANQADCgYIEQAAAA==.',
As='Asgnomeus:BAAANQADCgUIBQAAAA==.Ashhealz:BAAANQAECgIIAgAAAA==.',
At='Atraxx:BAAANQABCgIIAgAAAA==.',
Ax='Axlegrease:BAAANQADCgcIDAAAAA==.',
Ba='Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQADCgUIBgAAAA==.',
Be='Beaker:BAAANQAECgEIAgAAAA==.Beastmode:BAAANQAECgQIBgAAAA==.Bedlem:BAAANQADCgcIEgAAAA==.Beko:BAAANQAECgIIAgAAAA==.Bendytwotime:BAAANQABCgIIAgAAAA==.',
Bi='Bidoof:BAAANQAECgEIAQAAAA==.Billydan:BAAANQAECgEIAQAAAA==.',
Bl='Blackpanthxr:BAAANQAECgYIBgAAAA==.Blackvortex:BAAANQADCgIIAgAAAA==.Bloodsoul:BAAANQAECgMIBQAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECggIEAABAAAAAA==.Bloodyburst:BAAANQAECgUIBQABNQAECggIEAABAAAAAA==.Bloodyfistz:BAAANQAECggIEAAAAA==.Blue:BAAANQAECgMIBgAAAA==.Bluethreetwo:BAAANQAECgIIAgAAAA==.',
Bo='Bookofzeref:BAAANQADCgEIAQAAAA==.',
Br='Brayend:BAAANQAECgIIAgAAAA==.Brimscythe:BAAANQAECgUICQAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
Ca='Calaveras:BAAANQABCgYICAAAAA==.Caliandis:BAAANQADCggIDAAAAA==.Calvey:BAAANQADCgYIDQAAAA==.Cambrai:BAAANQADCggIEwAAAA==.Cannabelle:BAAANQAECgUICgAAAA==.Carclias:BAAANQAECgYICwAAAA==.Carthrix:BAAANQADCggICgAAAA==.Cattlerage:BAAANQAECgIIAgAAAA==.',
Ce='Cellika:BAAANQADCgcIBwAAAA==.Cerdelz:BAAANQADCgcIBwAAAA==.',
Ch='Chaoscookies:BAAANQAECgUICQAAAA==.Chartkov:BAAANQADCgYICQAAAA==.Chermer:BAAANQADCgQIBAAAAA==.',
Ci='Cinderpetal:BAAANQADCggIDgAAAA==.',
Ck='Ckay:BAAANQADCggICAAAAA==.',
Co='Cobrakaidojo:BAAANQAECgYIBwAAAA==.Cohemew:BAAANQAECgUIBwABNQAECgYIDAABAAAAAA==.Comlock:BAAANQADCgQIBQAAAA==.Complacent:BAAANQAECgEIAQAAAA==.Comspyder:BAAANQADCgYICgAAAA==.Coriander:BAAANQAECgQIBQAAAA==.Corii:BAAANQADCgMIAwAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQADCgQIBQABNQAECgkJGQACAHkgAA==.',
Cy='Cyonicus:BAAANQAECgEIAQAAAA==.Cyska:BAAANQAECgYICQAAAA==.',
['Cé']='Cécé:BAAANQAECgQIBQAAAA==.',
['Cë']='Cëcë:BAAANQADCgMIBAAAAA==.',
Da='Dababayaga:BAAANQADCgYICAAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagerlaurn:BAAANQAECgMIAwAAAA==.Dagevas:BAAANQADCgYIBgAAAA==.Dakeria:BAAANQADCgYIBgAAAA==.Darkando:BAAANQADCgYIBgAAAA==.Darksoldier:BAAANQAECgMIAwAAAA==.Darthfire:BAAANQABCgYIBgAAAA==.Dartoy:BAEANQAECgQIBwABNQAECgcIDwABAAAAAA==.Dax:BAAANQADCgcIDgAAAA==.Daxing:BAAANQADCggIFAABNQAECgMIBQABAAAAAA==.',
De='Deeppurple:BAAANQADCgYICAAAAA==.Del:BAAANQAECgQIBQAAAA==.Demoraliziñg:BAAANQADCgYIBgAAAA==.Demostache:BAAANQAECgYIDAAAAA==.Despot:BAAANQAECgEIAQAAAA==.',
Dh='Dhargal:BAAANQAECgQIBQAAAA==.',
Dk='Dkfaros:BAAANQADCgYICwABNQAECgMIAwABAAAAAA==.',
Do='Dolomite:BAAANQAECgQIBAAAAA==.Dorow:BAAANQAECgYIDQAAAA==.Dotabolt:BAAANQAECgMIBAAAAA==.',
Dr='Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgYIEAAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAAANQAECggICQAAAA==.',
Du='Dunsel:BAAANQADCggIDgABNQAECgUICQABAAAAAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQADCggIDgAAAA==.',
Dy='Dyanna:BAAANQABCgYICgAAAA==.',
['Dà']='Dànny:BAAANQAECgQIBAAAAA==.',
Eb='Ebonshade:BAAANQADCgUIBwAAAA==.',
Ed='Edena:BAAANQADCgEIAQAAAA==.Edginglord:BAAANQADCgUIBQAAAA==.Edya:BAAANQADCgIIAgAAAA==.',
El='Elgringo:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.Eloras:BAAANQAECgEIAQAAAA==.Elunbi:BAAANQAECgYIDAAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQADCgEIAQAAAA==.',
Ep='Epsilòn:BAEANQAECggICQAAAA==.',
Er='Ernest:BAAANQADCgcIDwAAAA==.Errani:BAAANQAECgEIAQAAAA==.',
Es='Esper:BAAANQADCggIEAAAAA==.',
Eu='Eureki:BAAANQAECgEIAQAAAA==.',
Ev='Evilkarma:BAAANQADCggIEwAAAA==.Evocatis:BAAANQAECgcIDAAAAA==.',
Ey='Eyesdeadeyed:BAAANQAECgYICwAAAA==.',
Fa='Faion:BAAANQAECgQIBAAAAA==.Farrea:BAAANQADCgYIBgAAAA==.Fayvia:BAAANQABCgMIBwAAAA==.',
Fe='Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgQIBgAAAA==.',
Fi='Firebirdz:BAAANQAECgcIDAAAAA==.',
Fl='Flygon:BAAANQADCgcIDQAAAA==.',
Fo='Forque:BAAANQADCgYICAAAAA==.',
Fr='Frater:BAAANQADCgEIAQAAAA==.Frequentine:BAAANQAECgQIBAAAAA==.Frizby:BAAANQADCgQIBAAAAA==.Frostypaw:BAAANQADCgIIAgAAAA==.',
Fu='Fuzzybut:BAAANQAECgEIAQAAAA==.',
Fy='Fyrelord:BAAANQADCggIEwAAAA==.Fyuna:BAAANQAECgQIBQAAAA==.',
Ga='Gark:BAAANQADCgYIDwAAAA==.Garkk:BAAANQABCgYICgAAAA==.Gazzi:BAAANQAECgQIBQAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQAAAA==.',
Gi='Gióvanna:BAAANQADCgQIBQAAAA==.',
Gl='Glodskegg:BAAANQAECgQIBQAAAA==.',
Go='Goyim:BAAANQADCggICAAAAA==.',
Gr='Gr:BAAANQADCgMIBwAAAA==.Grissoul:BAAANQABCgQIBAAAAA==.Grody:BAAANQADCggIDgAAAA==.',
Gu='Guroo:BAAANQAECgQIBQAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
Ha='Hagarn:BAAANQAECgYICAAAAA==.Halimah:BAAANQAECgIIAgAAAA==.Halois:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Hardtwosee:BAAANQAECggIDQABNQAFFAIIAQABAAAAAA==.Harleypaw:BAAANQADCggICAAAAA==.Hazan:BAAANQAECgQIAQABNQAECggICQABAAAAAA==.',
He='Hexmachine:BAAANQAECgQICAAAAA==.',
Ho='Hole:BAAANQADCgYIBgAAAA==.',
Hu='Huntzcatzup:BAAANQADCgQIBAAAAA==.',
Hy='Hypertext:BAAANQADCgYIDwAAAA==.',
Ia='Iamahriman:BAAANQAECgEIAgAAAA==.',
Ig='Ignite:BAAANQAECgQICAAAAA==.',
Il='Illestria:BAAANQAECgQIBAAAAA==.Illumiscotty:BAAANQAECgYICQAAAA==.',
In='Insania:BAAANQAECgEIAQAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
Iz='Izara:BAAANQADCgMIBwAAAA==.',
Ja='Jastirri:BAAANQAECgEIAQAAAA==.',
Ji='Jimothy:BAAANQADCgYIBgABNQABCgQIAgABAAAAAA==.',
Jo='Johneringo:BAAANQADCgYICwAAAA==.Jonjee:BAAANQAECgQIBQAAAA==.',
Ju='Juicez:BAAANQADCgYIBwAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgYICgAAAA==.Kain:BAAANQAECgYIBAAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECgIIAgAAAA==.Katio:BAAANQAECgUICQAAAA==.Kayanna:BAAANQADCgQIBAAAAA==.Kayhless:BAAANQADCggIDgAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQADCgYIDwAAAA==.Kessandra:BAABNQAECoEXAAMDAAkJASQzAACBAwADAAkJtiIzAACBAwAEAAMJ9Rs/WADvAAAAAA==.Kexally:BAAANQADCgYIDwAAAA==.Kexkan:BAAANQADCgQIBAABNQADCgYIDwABAAAAAA==.Kezzia:BAAANQADCgMIAwAAAA==.',
Kh='Khurri:BAAANQAECgQIBQAAAA==.',
Ki='Kiarah:BAAANQAECgEIAQAAAA==.Killplz:BAAANQADCgYIFQAAAA==.Kirr:BAAANQAECgIIAgAAAA==.Kisor:BAAANQADCgEIAQAAAA==.Kitchenstink:BAAANQAECgQIBQAAAA==.',
Ko='Koifo:BAAANQABCgQIBAAAAA==.',
Kp='Kplaow:BAAANQABCgIIAgAAAA==.',
Kr='Kritanta:BAAANQAECgQIBQAAAA==.Krystallus:BAAANQADCgUIBQAAAA==.',
Ku='Kurnea:BAAANQADCggIEwAAAA==.',
La='Lachlann:BAAANQADCgcIEgAAAA==.Lakartó:BAAANQAECgYIDgAAAA==.Law:BAAANQAECgMIAwAAAA==.',
Ld='Ldritch:BAABNQAECoEYAAMFAAkJviDzCQBxAgAFAAYJgSPzCQBxAgAGAAUJmR3YEgBtAQAAAA==.',
Le='Leifson:BAAANQAECgEIAQAAAA==.Leonedis:BAAANQADCggICwAAAA==.Lethea:BAAANQADCgIIAgAAAA==.',
Lu='Ludo:BAAANQAECgcIDAAAAA==.Lukri:BAAANQADCgYICAAAAA==.Lumisbrew:BAAANQAECgQIBQAAAA==.Luxurious:BAAANQAECgEIAQAAAA==.',
Ma='Maaca:BAAANQADCgYICgAAAA==.Malachor:BAAANQADCgQIBAABNQADCggIDwABAAAAAA==.Maligned:BAAANQAECgEIAQAAAA==.Martichoux:BAAANQAECgQIBQAAAA==.Match:BAAANQADCgIIAgAAAA==.Mathas:BAAANQAECgYICQAAAA==.Mathilda:BAAANQADCgYIBgAAAA==.',
Mc='Mccholock:BAAANQAECgEIAQAAAA==.Mcmach:BAAANQAECgIIAgAAAA==.',
Me='Meddox:BAAANQABCgUIBQAAAA==.Mehaoloka:BAAANQADCgYICQAAAA==.Memelle:BAAANQADCggICAAAAA==.Menith:BAAANQABCgMIAwAAAA==.Menoah:BAAANQADCgcICQAAAA==.Merdoc:BAAANQAECgQIBAAAAA==.Meredith:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Mesilana:BAAANQADCgQIBAAAAA==.Metrx:BAAANQADCgUIBQAAAA==.',
Mi='Miltank:BAAANQADCgYIDAAAAA==.Mirenna:BAAANQADCggIDgAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Molbeato:BAAANQAECgIIAgAAAA==.Monichan:BAAANQADCgYIBwAAAA==.Moosecheeks:BAAANQADCggIDQAAAA==.Morganna:BAAANQABCgMIAwAAAA==.Morior:BAAANQADCggICQAAAA==.Morslucifer:BAAANQAECgQIBAAAAA==.Motorcade:BAAANQAECgEIAQAAAA==.',
Mu='Murok:BAAANQADCgEIAQAAAA==.Mutent:BAAANQADCgYIBgAAAA==.',
My='Mypal:BAAANQADCggIEwAAAA==.Myrelis:BAAANQADCgYICQAAAA==.',
Na='Naula:BAAANQADCgUIBwAAAA==.',
Ne='Neather:BAAANQADCggIEwAAAA==.Neron:BAAANQABCgQICAAAAA==.Nezkima:BAAANQADCgQIBAAAAA==.',
Ni='Nikkto:BAAANQADCggICQAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Ninsane:BAAANQAECgMIAwAAAA==.Nintrovert:BAAANQAECgEIAQAAAA==.Nira:BAAANQAECgQIBQAAAA==.Niranrian:BAAANQADCgQIAwAAAA==.Nitroethane:BAAANQAECgEIAQAAAA==.',
No='Nodöts:BAAANQAECggICAABNQAFFAIIAQABAAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Notdeadyet:BAAANQADCgcIDAAAAA==.Notron:BAAANQAECgEIAgAAAA==.Noz:BAAANQADCgQIBAAAAA==.',
Ny='Nychophysis:BAAANQADCggIDQAAAA==.',
['Nø']='Nøcke:BAAANQADCggICAAAAA==.',
Om='Omars:BAAANQADCgcIDQAAAA==.',
On='Ontherun:BAAANQADCgQIBAAAAA==.',
Op='Oprawinfury:BAAANQADCgYIDwAAAA==.',
Ou='Ourus:BAAANQAECgYICwAAAA==.',
Pa='Pallaminnow:BAAANQADCggIEwAAAA==.Paulo:BAAANQAECgEIAQAAAA==.',
Pe='Pele:BAAANQADCgYIDwAAAA==.Perpetrator:BAAANQADCgYIFAAAAA==.',
Pi='Piki:BAAANQAECgEIAQAAAA==.',
Po='Poepwn:BAAANQADCggIFgAAAA==.',
Pu='Puffypanda:BAAANQADCgYICwAAAA==.',
Qu='Quill:BAAANQAECgQIBQAAAA==.',
Ra='Raging:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Ralz:BAAANQAECgEIAQAAAA==.Rannick:BAAANQADCggICgAAAA==.Ranua:BAAANQADCgUICQABNQAECgMIBQABAAAAAA==.Ratdemonmike:BAAANQAECgEIAQAAAA==.Ratio:BAAANQAECggICgAAAA==.Ravenhunt:BAAANQADCggIDQAAAA==.',
Re='Remi:BAAANQADCgYIBgAAAA==.',
Ri='Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Ronyn:BAAANQADCggICQAAAA==.',
Ru='Ruden:BAAANQADCggIDwAAAA==.Runed:BAAANQAECgQIBAAAAQ==.',
Rw='Rwqr:BAAANQAECgQIBgAAAA==.',
Sa='Salacakei:BAAANQAECgQIBAAAAA==.Salin:BAAANQAECgMIAwAAAA==.Salithril:BAAANQADCgEIAQAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAABNQAECoEYAAIHAAkJfyW6AACyAwAHAAkJfyW6AACyAwAAAA==.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scoobie:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Scoobydo:BAAANQABCgIIAgABNQAECgMIAwABAAAAAA==.Scratches:BAAANQABCgIIAgAAAA==.Scrubs:BAAANQAECgQIBwAAAA==.',
Se='Septemberr:BAAANQADCgQIBAAAAA==.',
Sh='Shadpriest:BAAANQABCgIIAgAAAA==.Shaggzy:BAABNQAECoEZAAICAAkJeSCkAgBZAwACAAkJeSCkAgBZAwAAAA==.Shamyaltak:BAAANQADCgIIAgAAAA==.Shandralore:BAAANQADCggIDgAAAA==.Shelgon:BAAANQAECgEIAQAAAA==.Shiel:BAAANQAECgEIAQAAAA==.Shockdoctor:BAAANQAECgQIBQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgkJFQAIAL0aAA==.',
Sl='Sleples:BAAANQAECgMIAwAAAA==.Slufgor:BAAANQADCgYIDwAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sm='Smolder:BAAANQADCgUIBQAAAA==.',
Sn='Snoo:BAAANQAECgEIAQAAAA==.',
So='Solarlite:BAAANQADCgEIAQAAAA==.Sophix:BAAANQADCgMIAwAAAA==.Sorovar:BAAANQAECgQIBQAAAA==.Soulbreakër:BAAANQAECgQIBQAAAA==.',
Sp='Specimen:BAAANQADCgYICgAAAA==.Speddling:BAAANQAECgMIAwAAAA==.Spiritomb:BAAANQADCgQIBAAAAA==.Spony:BAAANQADCgYIDgAAAA==.Sprayanpray:BAAANQABCgIIAgAAAA==.',
St='Starbrow:BAAANQAECgMIAwAAAA==.Stormlight:BAAANQADCgYIEQAAAA==.Strudelmaker:BAAANQADCgEIAQAAAA==.',
Su='Sushistryke:BAAANQADCgYICwAAAA==.',
Sy='Syland:BAAANQAECgEIAQAAAA==.Sylvanäs:BAAANQADCgYIDAAAAA==.Sysna:BAAANQAECgQICQAAAA==.',
Ta='Talley:BAAANQAECgQIBQAAAA==.Tankwar:BAAANQADCgUICAAAAA==.Targis:BAAANQAECgQIBQAAAA==.',
Te='Templeton:BAAANQADCgMIAwAAAA==.',
Th='Thaleas:BAAANQADCgEIAQAAAA==.Thegreatkhal:BAAANQADCggIEwAAAA==.Thorizine:BAAANQAECgYIBgAAAA==.Thorlas:BAAANQAECgIIAgAAAA==.',
Ti='Timmúk:BAAANQAECgIIAwAAAA==.',
To='Tolkorthuul:BAAANQADCggICQABNQADCgYICAABAAAAAA==.Tomma:BAAANQAECgQIBQAAAA==.Torsion:BAAANQADCggICAAAAA==.',
Tr='Trailerpark:BAAANQABCgIIBQAAAA==.Tratre:BAAANQAECgEIAQAAAA==.Trevally:BAAANQADCgYIBgAAAA==.Triana:BAAANQADCggICAAAAA==.Trupeti:BAAANQADCgYIEQAAAA==.',
Tu='Tumboflakes:BAAANQADCggICAABNQAFFAIIAgABAAAAAA==.Tust:BAAANQADCggIDgABNQABCgQIAgABAAAAAA==.',
Ty='Tylandy:BAAANQAECgIIBAAAAA==.Tytaniormu:BAAANQAECgQIBQAAAA==.',
['Tê']='Tês:BAAANQAECgIIAgAAAA==.',
Va='Vaayl:BAAANQAECgEIAQAAAA==.Vaelraen:BAAANQADCgcIDQAAAA==.Valcher:BAAANQADCgYICwAAAA==.Valendera:BAAANQAECgQIBQAAAA==.Valifadin:BAAANQADCggIDgAAAA==.Valndrevy:BAAANQADCgYICwAAAA==.Vansan:BAAANQAECgMIBQAAAA==.',
Ve='Venngennce:BAAANQAECgYICQAAAA==.',
Vi='Viktir:BAAANQADCgQIBAABNQADCgYIDwABAAAAAA==.Vintage:BAAANQAECgcIDAAAAA==.',
Vo='Voided:BAAANQAECgIIAgAAAA==.Vorkath:BAAANQAECgQIBQAAAA==.Vormette:BAAANQADCgUIBQAAAA==.',
Vt='Vtae:BAAANQADCggIEAAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAAANQAECgEIAQAAAA==.',
Wo='Woxkal:BAAANQADCggIFQAAAA==.',
Wu='Wubblebubble:BAAANQAECgEIAQAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQAECgEIAQAAAA==.',
Xu='Xuzhu:BAAANQADCgYICAAAAA==.',
Yl='Ylvis:BAAANQAECgEIAQAAAA==.',
Yo='Yol:BAAANQAECgYICAAAAA==.Yoliesha:BAAANQABCgYIBwAAAA==.Yoshymi:BAAANQAECgIIAwAAAQ==.',
Za='Zarion:BAAANQAECgcIDQAAAA==.Zarra:BAAANQAECgIIAgAAAA==.',
Ze='Zerofoxtogiv:BAAANQADCgMIAwAAAA==.',
Zf='Zf:BAAANQABCgQIBAAAAA==.',
Zi='Zilik:BAAANQADCgUIBQABNQAECgcIDQABAAAAAA==.Ziyar:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.',
Zo='Zocorro:BAAANQADCgYIDwAAAA==.',
Zy='Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAABNQAECoEYAAIJAAkJMyHmBgBTAwAJAAkJMyHmBgBTAwAAAA==.',
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
