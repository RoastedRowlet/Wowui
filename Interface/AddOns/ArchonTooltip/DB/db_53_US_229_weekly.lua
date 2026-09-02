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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abmikaze:BAAANQADCgEIAQAAAA==.Abysseon:BAAANQAECgEIAQAAAA==.',
Ac='Ace:BAAANQADCgUIBQAAAA==.',
Ad='Adios:BAAANQAFFAEIAQAAAA==.Adorean:BAAANQADCgYICwAAAA==.',
Ag='Age:BAAANQADCggIDgAAAA==.Agrohn:BAAANQADCgIIAgAAAA==.',
Ai='Aimnskin:BAAANQADCgYICQAAAA==.',
Al='Alcore:BAAANQADCggIDgAAAA==.Aliine:BAAANQADCgcICgAAAA==.',
Am='Ameiisaa:BAAANQAECgEIAQAAAA==.Amethaendron:BAAANQADCgEIAQAAAA==.Amneesia:BAAANQADCgQIBQAAAA==.Amytiel:BAAANQAECgYICQAAAA==.',
An='Anìtamaxwynn:BAAANQADCgQIBAABNQAECgcIDQABAAAAAA==.',
Ao='Aoifae:BAAANQADCgYICAAAAA==.',
Ap='Applecider:BAAANQAECgEIAgAAAA==.Apprentice:BAAANQADCgYIDAAAAA==.',
Ar='Aramos:BAAANQAECgEIAQAAAA==.Aramôs:BAAANQADCgYIBgAAAA==.Arta:BAAANQADCgYICwAAAA==.',
As='Ashhealz:BAAANQADCgQIBAAAAA==.',
At='Atraxx:BAAANQABCgIIAgAAAA==.',
Ax='Axlegrease:BAAANQADCgYICwAAAA==.',
Ba='Balacarn:BAAANQAECgIIAwAAAA==.Barlok:BAAANQADCgUIBgAAAA==.',
Be='Beaker:BAAANQAECgEIAQAAAA==.Beastmode:BAAANQAECgIIAgAAAA==.Bedlem:BAAANQADCgcICwAAAA==.Beko:BAAANQAECgEIAQAAAA==.',
Bi='Bidoof:BAAANQADCgYICwAAAA==.Billydan:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.',
Bl='Blackvortex:BAAANQADCgIIAgAAAA==.Bloodsoul:BAAANQAECgMIBAAAAA==.Bloodybloodz:BAAANQADCggICAABNQAECgYICAABAAAAAA==.Bloodyburst:BAAANQADCgUIBQABNQAECgYICAABAAAAAA==.Bloodyfistz:BAAANQAECgYICAAAAA==.Blue:BAAANQAECgMIBAAAAA==.Bluethreetwo:BAAANQADCgIIAgAAAA==.',
Bo='Bookofzeref:BAAANQADCgEIAQAAAA==.',
Br='Brayend:BAAANQAECgEIAQAAAA==.Brimscythe:BAAANQAECgQIBAAAAA==.Brutalx:BAAANQADCggICAAAAA==.',
Ca='Caliandis:BAAANQADCgcICwAAAA==.Calvey:BAAANQADCgYICQAAAA==.Cambrai:BAAANQADCgYICwAAAA==.Cannabelle:BAAANQAECgQIBQAAAA==.Carclias:BAAANQAECgQIBQAAAA==.Carthrix:BAAANQADCggICgAAAA==.Cattlerage:BAAANQADCgcIDQAAAA==.',
Ce='Cellika:BAAANQADCgYIBgAAAA==.Cerdelz:BAAANQADCgcIBwAAAA==.',
Ch='Chaoscookies:BAAANQAECgQIBAAAAA==.Chartkov:BAAANQADCgYICQAAAA==.Chermer:BAAANQADCgQIBAAAAA==.',
Ci='Cinderpetal:BAAANQADCgcIDQAAAA==.',
Co='Cobrakaidojo:BAAANQAECgEIAQAAAA==.Cohemew:BAAANQAECgUIBgAAAA==.Comlock:BAAANQADCgQIBAAAAA==.Complacent:BAAANQADCgYIDAAAAA==.Comspyder:BAAANQADCgYIBgAAAA==.Coriander:BAAANQAECgEIAQAAAA==.Corii:BAAANQADCgMIAwAAAA==.',
Ct='Cthùlhù:BAAANQADCggICAAAAA==.',
Cu='Cursedchild:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.',
Cy='Cyonicus:BAAANQADCgYICwAAAA==.Cyska:BAAANQAECgMIAwAAAA==.',
['Cé']='Cécé:BAAANQADCgUIBQAAAA==.',
Da='Dababayaga:BAAANQADCgYICAAAAA==.Dagaroonie:BAAANQAECgMIAwAAAA==.Dagerlaurn:BAAANQADCgIIAgAAAA==.Darkando:BAAANQADCgYIBgAAAA==.Darksoldier:BAAANQABCgEIAQAAAA==.Dartoy:BAEANQAECgMIAwABNQAECgYICAABAAAAAA==.Dax:BAAANQADCgYICgAAAA==.Daxing:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.',
De='Deeppurple:BAAANQADCgYICAAAAA==.Del:BAAANQAECgEIAQAAAA==.Demoraliziñg:BAAANQADCgYIBgAAAA==.Demostache:BAAANQAECgQIBgABNQAECgUIBgABAAAAAA==.Despot:BAAANQADCggICAAAAA==.',
Dh='Dhargal:BAAANQAECgEIAQAAAA==.',
Dk='Dkfaros:BAAANQADCgYICwAAAA==.',
Do='Dolomite:BAAANQADCgYIBgAAAA==.Dorow:BAAANQAECgUIBwAAAA==.Dotabolt:BAAANQAECgEIAQAAAA==.',
Dr='Dragonash:BAAANQADCgYIBgAAAA==.Draéne:BAAANQADCgYICgAAAA==.Drinkme:BAAANQADCgEIAQAAAA==.Droki:BAAANQAECgQIBQAAAA==.',
Du='Dunsel:BAAANQADCgcIDQABNQAECgQIBAABAAAAAA==.Dunwich:BAAANQADCgIIAgAAAA==.Duulket:BAAANQADCgcIDQAAAA==.',
Dy='Dyanna:BAAANQABCgQIBgAAAA==.',
['Dà']='Dànny:BAAANQADCggIDgAAAA==.',
Eb='Ebonshade:BAAANQADCgUIBwAAAA==.',
Ed='Edena:BAAANQADCgEIAQAAAA==.Edginglord:BAAANQADCgMIAwAAAA==.',
El='Elunbi:BAAANQAECgUIBgAAAA==.',
Em='Emovoker:BAAANQADCgYIBAAAAA==.Emshady:BAAANQADCgEIAQAAAA==.',
Ep='Epsilòn:BAEANQAECgEIAQAAAA==.',
Er='Ernest:BAAANQADCgYICAAAAA==.Errani:BAAANQADCgYICwAAAA==.',
Es='Esper:BAAANQADCggICAAAAA==.',
Eu='Eureki:BAAANQADCggIDgAAAA==.',
Ev='Evilkarma:BAAANQADCgcICwAAAA==.Evocatis:BAAANQAECgQIBQAAAA==.',
Ey='Eyesdeadeyed:BAAANQAECgQIBQAAAA==.',
Fa='Faion:BAAANQADCggIDgAAAA==.',
Fe='Felzbirt:BAAANQAECgEIAQAAAA==.Feorely:BAAANQAECgIIAgAAAA==.',
Fi='Firebirdz:BAAANQAECgQIBQAAAA==.',
Fl='Flygon:BAAANQADCgYIBgAAAA==.',
Fo='Forque:BAAANQADCgEIAgAAAA==.',
Fr='Frequentine:BAAANQADCggICAAAAA==.Frostypaw:BAAANQADCgIIAgAAAA==.',
Fu='Fuzzybut:BAAANQADCgcIDAAAAA==.',
Fy='Fyrelord:BAAANQADCgYICwAAAA==.Fyuna:BAAANQAECgEIAQAAAA==.',
Ga='Gark:BAAANQADCgYICQAAAA==.Gazzi:BAAANQAECgEIAQAAAA==.',
Ge='Genevieve:BAAANQAECgEIAQAAAA==.',
Gi='Gióvanna:BAAANQADCgQIBQAAAA==.',
Gl='Glodskegg:BAAANQAECgEIAQAAAA==.',
Go='Goyim:BAAANQADCggICAAAAA==.',
Gr='Gr:BAAANQADCgMIBAAAAA==.Grody:BAAANQADCgcIDQAAAA==.',
Gu='Guroo:BAAANQAECgEIAQAAAA==.',
['Gá']='Gárp:BAAANQAECgEIAQAAAA==.',
Ha='Hagarn:BAAANQAECgEIAgAAAA==.Halimah:BAAANQADCggIDQAAAA==.Hardtwosee:BAAANQAECggIDQAAAA==.Hazan:BAAANQADCgIIAgABNQAECgQIBQABAAAAAA==.',
He='Hexmachine:BAAANQAECgIIAgAAAA==.',
Hy='Hypertext:BAAANQADCgYICQAAAA==.',
Ia='Iamahriman:BAAANQAECgEIAQAAAA==.',
Ig='Ignite:BAAANQAECgQIBQAAAA==.',
Il='Illestria:BAAANQADCgcIDAAAAA==.Illumiscotty:BAAANQAECgMIAwAAAA==.',
In='Incognonetoo:BAAANQADCggICAAAAA==.Insania:BAAANQADCggIDgAAAA==.',
Ir='Ironhands:BAAANQADCgYIBgAAAA==.',
Iz='Izara:BAAANQADCgMIBAAAAA==.',
Ji='Jimothy:BAAANQADCgYIBgABNQABCgQIAgABAAAAAA==.',
Jo='Johneringo:BAAANQADCgYICwAAAA==.Jonjee:BAAANQAECgEIAQAAAA==.',
Ju='Juicez:BAAANQADCgEIAQAAAA==.Jurkee:BAAANQADCgYICwAAAA==.',
Ka='Kahekili:BAAANQADCgUIBQAAAA==.Kalak:BAAANQABCgIIAgAAAA==.Kaleielin:BAAANQAECgIIAgAAAA==.Katio:BAAANQAECgMIBAAAAA==.Kayhless:BAAANQADCgcIDQAAAA==.Kazunt:BAAANQABCgQIBAAAAA==.',
Ke='Kershneep:BAAANQADCgYICQAAAA==.Kessandra:BAAANQAECgcIDQAAAA==.Kexally:BAAANQADCgYICQAAAA==.Kexkan:BAAANQADCgQIBAABNQADCgYICQABAAAAAA==.',
Kh='Khurri:BAAANQAECgEIAQAAAA==.',
Ki='Kiarah:BAAANQADCgcIDAAAAA==.Killplz:BAAANQADCgYIDQAAAA==.Kirr:BAAANQADCgIIAgAAAA==.Kitchenstink:BAAANQAECgEIAQAAAA==.',
Ko='Koifo:BAAANQABCgIIAgAAAA==.',
Kp='Kplaow:BAAANQABCgIIAgAAAA==.',
Kr='Kritanta:BAAANQAECgEIAQAAAA==.Krystallus:BAAANQADCgUIBQAAAA==.',
Ku='Kurnea:BAAANQADCgYICwAAAA==.',
La='Lachlann:BAAANQADCgYICwAAAA==.Lakartó:BAAANQAECgUICAAAAA==.Law:BAAANQAECgMIAwAAAA==.',
Ld='Ldritch:BAABNQAECoEOAAMCAAkJ2R2qBwBYAgACAAYJvCGqBwBYAgADAAMJFBZ9DAD9AAAAAA==.',
Le='Leifson:BAAANQADCgcIDQAAAA==.Leonedis:BAAANQADCgMIAwAAAA==.Lethea:BAAANQADCgIIAgAAAA==.Levious:BAAANQADCgYIBAAAAA==.',
Lu='Ludo:BAAANQAECgQIBQAAAA==.Lukri:BAAANQADCgYICAAAAA==.Lumisbrew:BAAANQAECgEIAQAAAA==.Luxurious:BAAANQADCgYICwAAAA==.',
Ma='Maaca:BAAANQADCgYICgAAAA==.Malachor:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Maligned:BAAANQADCgYIDAAAAA==.Martichoux:BAAANQAECgEIAQAAAA==.Mathas:BAAANQAECgMIAwAAAA==.',
Mc='Mccholock:BAAANQADCgcIDAAAAA==.Mcmach:BAAANQADCgYIBwAAAA==.',
Me='Meddox:BAAANQABCgIIAgAAAA==.Mehaoloka:BAAANQADCgYIBgAAAA==.Memelle:BAAANQADCgcIBwAAAA==.Menoah:BAAANQADCgcICQAAAA==.Meredith:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Mesilana:BAAANQADCgQIBAAAAA==.Metrx:BAAANQADCgUIBQAAAA==.',
Mi='Miltank:BAAANQADCgYIBgAAAA==.Mirenna:BAAANQADCgcIDQAAAA==.Misseymiss:BAAANQADCgIIAgAAAA==.',
Mo='Mogwhy:BAAANQADCgYIBgAAAA==.Monichan:BAAANQADCgEIAQAAAA==.Moosecheeks:BAAANQADCggICQAAAA==.Morior:BAAANQADCgcICAAAAA==.Morslucifer:BAAANQAECgEIAQAAAA==.Motorcade:BAAANQADCgYIDAAAAA==.',
My='Mypal:BAAANQADCgYICwAAAA==.Myrelis:BAAANQADCgYICQAAAA==.',
Na='Naula:BAAANQADCgUIBwAAAA==.',
Ne='Neather:BAAANQADCgYICwAAAA==.Neron:BAAANQABCgQIBgAAAA==.Nezkima:BAAANQADCgQIBAAAAA==.',
Ni='Nikkto:BAAANQADCggICAAAAA==.Ninfinite:BAAANQADCgYIBgAAAA==.Nintrovert:BAAANQAECgEIAQAAAA==.Nira:BAAANQAECgEIAQAAAA==.Nitroethane:BAAANQAECgEIAQAAAA==.',
No='Nodöts:BAAANQAECggICAABNQAECggIDQABAAAAAA==.Nokdis:BAAANQADCgIIAgAAAA==.Notdeadyet:BAAANQADCgcIDAAAAA==.Notron:BAAANQADCgYIBgAAAA==.',
Ny='Nychophysis:BAAANQADCgcIDAAAAA==.',
Od='Odyssius:BAAANQADCgYIBgAAAA==.',
Om='Omars:BAAANQADCgYIDAAAAA==.',
Op='Oprawinfury:BAAANQADCgYICQAAAA==.',
Ou='Ourus:BAAANQAECgQIBQAAAA==.',
Pa='Pallaminnow:BAAANQADCgYICwAAAA==.Paulo:BAAANQADCgEIAQAAAA==.',
Pe='Pele:BAAANQADCgYICQAAAA==.Perpetrator:BAAANQADCgYIDgAAAA==.',
Pi='Piki:BAAANQADCggIDQAAAA==.',
Po='Poepwn:BAAANQADCggIDwAAAA==.',
Pu='Puffypanda:BAAANQADCgUIBQAAAA==.',
Qu='Quill:BAAANQAECgEIAQAAAA==.',
Ra='Raging:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Ralz:BAAANQAECgEIAQAAAA==.Rannick:BAAANQADCgcICQAAAA==.Ranua:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Ratio:BAAANQAECgEIAgAAAA==.Ravenhunt:BAAANQADCgYIBQAAAA==.',
Re='Remi:BAAANQADCgYIBgAAAA==.',
Ri='Ripdvanwinkl:BAAANQADCgUICgAAAA==.',
Ro='Ronyn:BAAANQADCgcICAAAAA==.',
Ru='Ruden:BAAANQADCgcIBwAAAA==.Runed:BAAANQAECgQIBAAAAQ==.',
Rw='Rwqr:BAAANQAECgEIAQAAAA==.',
Sa='Salacakei:BAAANQADCgQIBAAAAA==.Samadams:BAAANQADCgcIEgAAAA==.Sarthy:BAAANQAECgcIDQAAAA==.Sassaphras:BAAANQAECgQIBAAAAA==.Satheron:BAAANQADCgEIAQAAAA==.',
Sc='Scoobie:BAAANQADCgEIAQABNQADCgcIDAABAAAAAA==.Scoobydo:BAAANQABCgIIAgABNQADCgcIDAABAAAAAA==.Scottypaly:BAAANQAECggICwABNQAECggIDQABAAAAAA==.Scratches:BAAANQABCgIIAgAAAA==.Scrubs:BAAANQAECgQIBAAAAA==.',
Se='Septemberr:BAAANQADCgQIBAAAAA==.',
Sh='Shadpriest:BAAANQABCgIIAgAAAA==.Shaggzy:BAAANQAECggIDgAAAA==.Shandralore:BAAANQADCgcIDQAAAA==.Shelgon:BAAANQAECgEIAQAAAA==.Shiel:BAAANQADCgcIDAAAAA==.Shockdoctor:BAAANQAECgEIAQAAAA==.Shurples:BAAANQAECgEIAgABNQAECgYIDQABAAAAAA==.',
Sl='Sleples:BAAANQADCgcIDAAAAA==.Slufgor:BAAANQADCgYICQAAAA==.Slyyxxi:BAAANQADCgQIBAAAAA==.',
Sn='Snoo:BAAANQADCgcIDAAAAA==.',
So='Solarlite:BAAANQADCgEIAQAAAA==.Sophix:BAAANQADCgMIAwAAAA==.Sorovar:BAAANQAECgEIAQAAAA==.Soulbreakër:BAAANQAECgEIAQAAAA==.',
Sp='Specimen:BAAANQADCgQIBAAAAA==.Spony:BAAANQADCgUICAAAAA==.',
St='Starbrow:BAAANQADCgQIBAABNQADCgYICwABAAAAAA==.Stormlight:BAAANQADCgYICwAAAA==.Strudelmaker:BAAANQADCgEIAQAAAA==.',
Su='Sushistryke:BAAANQADCgUIBQAAAA==.',
Sy='Syland:BAAANQADCgUIBQAAAA==.Sylvanäs:BAAANQADCgYIBgAAAA==.Sysna:BAAANQAECgQIBQAAAA==.',
Ta='Talley:BAAANQAECgEIAQAAAA==.Tankwar:BAAANQADCgUICAAAAA==.Targis:BAAANQAECgEIAQAAAA==.',
Te='Templeton:BAAANQADCgMIAwAAAA==.',
Th='Thegreatkhal:BAAANQADCgYICwAAAA==.Thorizine:BAAANQADCggIEAAAAA==.Thorlas:BAAANQADCgQIBAAAAA==.',
Ti='Timmúk:BAAANQAECgEIAQAAAA==.',
To='Tomma:BAAANQAECgEIAQAAAA==.',
Tr='Trailerpark:BAAANQABCgIIAwAAAA==.Tratre:BAAANQAECgEIAQAAAA==.Trupeti:BAAANQADCgYICwAAAA==.',
Tu='Tumboflakes:BAAANQADCggICAABNQAECgcICQABAAAAAA==.Tust:BAAANQADCggIDgABNQABCgQIAgABAAAAAA==.',
Ty='Tylandy:BAAANQAECgIIAgAAAA==.Tytaniormu:BAAANQAECgEIAQAAAA==.',
['Tê']='Tês:BAAANQADCgcIBwAAAA==.',
Va='Vaayl:BAAANQAECgEIAQAAAA==.Vaelraen:BAAANQADCgcIDQAAAA==.Valcher:BAAANQADCgYIBgAAAA==.Valendera:BAAANQAECgEIAQAAAA==.Valifadin:BAAANQADCgcIDQAAAA==.Valndrevy:BAAANQADCgUIBQAAAA==.Vansan:BAAANQAECgIIAgAAAA==.',
Ve='Venngennce:BAAANQAECgMIAwAAAA==.',
Vi='Viktir:BAAANQADCgQIBAABNQADCgYICQABAAAAAA==.Vintage:BAAANQAECgMIBQAAAA==.',
Vo='Vorkath:BAAANQAECgEIAQAAAA==.',
Vt='Vtae:BAAANQADCgYICwAAAA==.',
Wa='Warangel:BAAANQADCgQIBAAAAA==.',
We='Werehamster:BAAANQADCggIDwAAAA==.',
Wo='Woxkal:BAAANQADCggIDgAAAA==.',
Wu='Wubblebubble:BAAANQADCggIDgAAAA==.',
Wy='Wyndstorm:BAAANQADCgEIAQAAAA==.',
Xa='Xaelin:BAAANQADCgcIDAAAAA==.',
Xu='Xuzhu:BAAANQADCgYICAAAAA==.',
Yl='Ylvis:BAAANQADCgYIBgAAAA==.',
Yo='Yol:BAAANQAECgIIAgAAAA==.Yoliesha:BAAANQABCgEIAQAAAA==.Yoshymi:BAAANQAECgEIAQAAAQ==.',
Za='Zarion:BAAANQAECgUIBgAAAA==.Zarra:BAAANQADCgYIDAAAAA==.',
Zf='Zf:BAAANQABCgIIAgAAAA==.',
Zo='Zocorro:BAAANQADCgYICQAAAA==.',
Zy='Zytheline:BAAANQADCgIIAgAAAA==.',
['Ðe']='Ðecision:BAAANQAECgcIDQAAAA==.',
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
