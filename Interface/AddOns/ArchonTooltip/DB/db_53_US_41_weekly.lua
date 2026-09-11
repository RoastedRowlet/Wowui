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

local lookup = {'Unknown-Unknown','Priest-Shadow','Mage-Arcane','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abruum:BAAANQADCgYIBgAAAA==.',
Ad='Admetus:BAAANQAECgQIBgAAAA==.Adobe:BAAANQADCgYIBwAAAA==.',
Am='Amathal:BAAANQABCgIIAgAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgEIAQAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICAAAAA==.Aredhela:BAAANQAECgQIBAAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQADCggIDgAAAA==.Asha:BAAANQAECgYIBgAAAA==.Astrialynn:BAAANQADCgYIBgAAAA==.',
At='Athrea:BAAANQAECgQIBgAAAA==.',
Ba='Barakah:BAAANQADCgIIAgAAAA==.Barnre:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgQIBAAAAA==.',
Be='Bearito:BAAANQAECgMIAwAAAA==.Beefstick:BAAANQAECgMIAwAAAA==.Beserkfury:BAAANQAECgEIAQAAAA==.',
Bi='Biercan:BAAANQAECgYICwAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBAAAAA==.Bittywhite:BAAANQADCgYIDAAAAA==.',
Bl='Blayze:BAAANQADCgUIBQAAAA==.Blinkytime:BAAANQAECgEIAQAAAA==.Blúnt:BAAANQADCgQIBAAAAA==.',
Bo='Bobheals:BAAANQAECgIIAgAAAA==.Boibye:BAAANQAECgIIAgAAAA==.Bolblock:BAAANQAECgYIBwAAAA==.Bolo:BAAANQAECgYIDAAAAA==.Boostedww:BAAANQAECgQICAAAAA==.',
Br='Brambleclaw:BAAANQAECgUICQAAAA==.Brayker:BAAANQAECgUICQAAAA==.Breadoneal:BAAANQAECgIIAwAAAA==.Brewed:BAAANQADCgcIBwAAAA==.Brynjamin:BAAANQAECgQIBAAAAA==.Brüenor:BAAANQAECgEIAgAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAAANQADCgYIDwAAAA==.Burntroot:BAAANQAECgMIAwAAAA==.',
['Bá']='Bálor:BAAANQADCgcIDgAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Camdakablam:BAAANQAECgYICgAAAA==.Careradin:BAAANQAECgIIAgAAAA==.Carereaper:BAAANQADCggIDAABNQAECgIIAgABAAAAAA==.Cartilage:BAAANQAECgIIAgAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ch='Chebbles:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Chivi:BAAANQADCggIDgABNQAECgYICAABAAAAAA==.Chonkmonk:BAAANQADCgQIBAAAAA==.Chupacabrass:BAAANQAECgEIAQAAAA==.',
Co='Colman:BAAANQADCgYIDwAAAA==.Coorsbanquet:BAAANQAECgQIBAAAAA==.Coorsbite:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgMIAwAAAA==.Croc:BAAANQAECgUICQAAAA==.',
Cs='Csyasha:BAAANQADCgcIBwABNQAECgMIAwABAAAAAA==.',
Cu='Cubcadet:BAAANQADCggIEgAAAA==.',
Cy='Cybear:BAAANQADCggICAAAAA==.',
Da='Dalanora:BAAANQAECgUICQAAAA==.Dapalyu:BAAANQAECgEIAQAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQADCgYIBgAAAA==.Demine:BAAANQAECgMIAwAAAA==.Detrazeral:BAAANQADCggICAAAAA==.',
Di='Dico:BAAANQAECgEIAQAAAA==.Dipper:BAAANQAECgQIBgAAAA==.',
Do='Dohan:BAAANQADCgEIAQAAAA==.',
Ee='Eeveeko:BAAANQAECgQIBgAAAA==.',
Ej='Ejavuday:BAAANQAECgIIAgAAAA==.',
En='Enerchi:BAAANQAECgYICgAAAA==.',
Er='Ervyne:BAAANQADCgYICgAAAA==.',
Ev='Evera:BAAANQAECgMIAwAAAA==.Evos:BAAANQADCgYIBgAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fauci:BAAANQADCgIIAgABNQAECgcIEAABAAAAAA==.',
Fe='Feihao:BAAANQADCgYIEAAAAA==.Feltree:BAAANQADCgQIBAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAAANQAECgcIBwAAAA==.Flyknit:BAAANQADCgcIEgAAAA==.',
Fr='Fredthedh:BAAANQAECgQIBgAAAA==.Fromtheback:BAAANQAECgIIAgAAAA==.Frosticals:BAAANQAECgcICwABNQAECggIDwABAAAAAA==.',
Ga='Gaashw:BAAANQABCgQIBAAAAA==.Ganandor:BAAANQAECgUIBgAAAA==.Gaulish:BAAANQADCgcIBwAAAA==.',
Ge='Geocide:BAAANQAECgUICwAAAA==.Gethalyn:BAAANQADCgUIBgAAAA==.',
Gh='Ghume:BAAANQADCgUIBwAAAA==.',
Gr='Grizzoul:BAAANQADCgQIBAAAAA==.Grumly:BAAANQADCgcIDgAAAA==.',
Ha='Hanswoloqued:BAAANQAECgYICQAAAA==.',
He='Healufast:BAAANQAECgIIAwAAAA==.',
Hj='Hjalmar:BAAANQAECgQIBAAAAA==.',
Ho='Holysabeline:BAAANQAECgUICQAAAA==.Hotpots:BAAANQAECgQIBAAAAA==.',
Hu='Huchar:BAAANQAECgQIBgAAAA==.',
Hy='Hydraxix:BAAANQADCggICAAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
Ir='Ironßest:BAAANQABCgUICQAAAA==.',
Ja='Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jensthyra:BAAANQABCgUIBwAAAA==.',
Jo='Jobo:BAAANQAECgEIAQAAAA==.',
Ju='Julzaria:BAAANQADCgcIEgAAAA==.Jurny:BAAANQAECgIIAgAAAA==.',
Ka='Kahlandra:BAAANQAECgUICQAAAA==.Kaizer:BAAANQAECgcIDgAAAA==.Karina:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAAANQABCgQIBgAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Khornedog:BAAANQAECgQIBAAAAA==.Khrama:BAAANQAECgQIBgAAAA==.',
Kl='Kleenonean:BAABNQAECoEhAAICAAkJ1yL8AADBAwACAAkJ1yL8AADBAwAAAA==.',
Kr='Krackjarr:BAAANQADCgUIBQAAAA==.Kredor:BAAANQAECgEIAQAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQADCggICQAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAAANQAECgUIBQAAAA==.',
Le='Lemonpepper:BAAANQAECgUICQAAAA==.Lexxix:BAAANQADCgQIBAAAAA==.Leyru:BAAANQAECgUIBwAAAA==.',
Li='Liberos:BAAANQADCgcIEQAAAA==.Littlechiken:BAAANQADCgMIAwABNQAECgcIEwABAAAAAA==.',
Ln='Lninedkhack:BAAANQAECgMIBAAAAA==.',
Lo='Logaar:BAAANQAECgYICwAAAA==.',
Lu='Luxurix:BAAANQADCggIEQAAAA==.',
Ma='Magtao:BAAANQADCgYICgAAAA==.Malexannius:BAAANQADCgYIDwAAAA==.Maplebrick:BAAANQABCgIIAgAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECgQICgAAAA==.',
Me='Megtallica:BAAANQADCgcIDgAAAA==.Mensrea:BAAANQAECgEIAQAAAA==.Merrycold:BAAANQAECgUICQAAAA==.',
Mf='Mfgirthquake:BAAANQAECgUICAAAAA==.',
Mi='Miisty:BAAANQADCggICwAAAA==.Mikklelee:BAAANQADCggIDwAAAA==.Mings:BAAANQAECgQIBAAAAA==.Mistweaver:BAAANQAECgQIBgAAAA==.',
Mo='Mochi:BAAANQAECgQIBQAAAA==.Mochïi:BAAANQADCgIIBAABNQAECgkJHAADAKohAA==.Mojoe:BAAANQADCgcICwAAAA==.Mommyswaggin:BAAANQAECgEIAQAAAA==.Moopster:BAAANQAECgYICAAAAA==.Moopy:BAAANQADCgUIBQABNQAECgYICAABAAAAAA==.Mootangclan:BAAANQAECgIIAgAAAA==.',
Na='Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Neiko:BAAANQAECgUICAAAAA==.Neptuneakis:BAAANQAECgEIAQAAAA==.Newcarsmell:BAAANQADCggIEgAAAA==.',
Ni='Niceknife:BAAANQADCggIDQAAAA==.Niquid:BAAANQADCggIDwAAAA==.',
No='Nobu:BAAANQAECgcIEAAAAA==.Norinari:BAAANQAFFAIIAgAAAA==.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAAANQAECgUICQAAAA==.',
Ob='Obliteration:BAAANQAECgQIBQABNQAECgYICgABAAAAAA==.',
Ol='Olivertwist:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.',
On='Ontwou:BAAANQAECgQIBAAAAA==.',
Or='Orbz:BAAANQAECgQIBgAAAA==.Orcazm:BAAANQAECgEIAQAAAA==.',
Pa='Palyont:BAAANQADCgYICgAAAA==.Pancakezebra:BAAANQAECgUIBwAAAA==.Parse:BAAANQAECgEIAQAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAAANQAECgQIBgAAAA==.',
Pi='Pikechu:BAAANQAECgQIBgAAAA==.Pinkskies:BAAANQADCgIIAgAAAA==.',
Pl='Pleasy:BAAANQAECgIIAwAAAA==.Plugtobacca:BAAANQADCgIIAgABNQAECgcIEAABAAAAAA==.',
Po='Pocketchange:BAAANQAECgUICQAAAA==.',
Pr='Preservation:BAAANQADCgIIAgAAAA==.Promethêus:BAAANQADCggICAAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQADCggIFAAAAA==.',
Qr='Qrz:BAAANQADCgMIAwAAAA==.',
Re='Relovan:BAAANQAECgIIAgAAAA==.Renothidan:BAAANQAECgYICQAAAA==.Reuben:BAAANQADCggIEgAAAA==.Revin:BAAANQAECgQIBgAAAA==.Revrynth:BAAANQAECgYICAAAAA==.Rexorcist:BAAANQAECgMIAwAAAA==.',
Ri='Rimed:BAAANQAECgUIBQAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcIBwAAAA==.Rizzdolphler:BAAANQAECggIDAAAAA==.',
['Rö']='Rönburgundy:BAAANQAECgYICQAAAA==.',
Sa='Sanako:BAAANQAECgMIAwAAAA==.Saneros:BAAANQAECgIIAgAAAA==.',
Sc='Scraggle:BAAANQADCgQIBAAAAA==.Scuffito:BAAANQAECgEIAQAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Setheron:BAAANQADCgYIDwAAAA==.',
Sh='Shlea:BAAANQAECgYICQAAAA==.Shley:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.',
Si='Silvanna:BAAANQABCgQIBwAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
So='Solendros:BAAANQADCgQIBAAAAA==.Sonoa:BAAANQADCgUICQAAAA==.Sorlight:BAAANQADCgIIAgAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAAANQADCggIEwAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
St='Standarshh:BAAANQAECgMIBQAAAA==.Stevenz:BAAANQAECgUICQAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAAANQAECgcICQAAAA==.Sugarbabi:BAAANQAECgQIBgAAAA==.Sugarshot:BAAANQADCgQIBAAAAA==.Sugartotem:BAAANQADCgQIBgAAAA==.',
Sw='Swiftwing:BAAANQADCgQIBAAAAA==.',
Sy='Sydarliia:BAAANQAECgUIBQAAAA==.Sylrianah:BAAANQAECgUICQAAAA==.Sylveste:BAAANQAECgUIBQAAAA==.',
Ta='Tankhiskhan:BAAANQAECgQIBAAAAA==.',
Te='Tei:BAAANQADCgEIAQAAAA==.',
Th='Thannill:BAAANQAECgEIAQAAAA==.',
Ti='Tie:BAAANQAECgYICgAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Torzhu:BAAANQAECgUIBgAAAA==.Toy:BAAANQAECgEIAQABNQAFFAUIBwAEAGwLAA==.',
Tr='Travvy:BAACNQAFFIENAAMFAAcJoB+DAAAVAgAFAAUJ+x6DAAAVAgAGAAIJPCH0AADgAAA1AAQKgRoAAwUACQmyJQEDADgDAAUACAmnIQEDADgDAAYAAwnGHxkYACMBAAAA.Trevmo:BAAANQAECgIIAgAAAA==.Trexin:BAAANQADCgIIAgAAAA==.',
Tz='Tzuyu:BAAANQAECgUICQAAAA==.',
Ud='Uddershock:BAAANQADCgYIBgAAAA==.',
Un='Unbreakabull:BAAANQAECgUICQAAAA==.',
Va='Vae:BAAANQAECgYICwAAAA==.Valka:BAAANQADCgcIDQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAAANQAECgIIAwAAAA==.Veyle:BAAANQAECgUICQAAAA==.',
Vy='Vyndria:BAAANQADCgcIDQAAAA==.',
Wa='Waypal:BAAANQADCggIEQAAAA==.',
We='Weashock:BAAANQADCgYIDAAAAA==.',
Wi='Windfury:BAAANQAECgQIBQAAAA==.Wingzard:BAAANQAECgUICAAAAA==.',
Ya='Yaitoopmfp:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Yao:BAAANQAECgUIBwAAAA==.',
Za='Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAAANQAECgUICQAAAA==.Zaki:BAAANQAECgYICwAAAA==.',
Ze='Zeleria:BAAANQADCgYICQAAAA==.Zerathis:BAAANQADCgEIAQAAAA==.',
Zi='Zip:BAAANQABCgYIBgAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zorb:BAAANQAECgUICQAAAA==.Zoshow:BAAANQADCggIEwAAAA==.',
['Zõ']='Zõshow:BAAANQADCggICwAAAA==.',
['Ðp']='Ðp:BAAANQAECgMIAwAAAA==.',
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
