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

local lookup = {'Warlock-Destruction','Unknown-Unknown','Warrior-Protection','Rogue-Assassination','Shaman-Elemental','Priest-Shadow','DeathKnight-Blood','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Evoker-Preservation','Rogue-Subtlety',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abbpriest:BAAANQADCgYIBgABNQAECgcIFgABACcaAA==.Abruum:BAAANQADCgYIBgAAAA==.',
Ad='Admetus:BAAANQAECgQIBgAAAA==.Adobe:BAAANQADCggIDwAAAA==.',
Am='Amathal:BAAANQABCgIIAgAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgQIBQAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICAAAAA==.Aredhela:BAAANQAECgUICQAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQAECgQIBAAAAA==.Asha:BAAANQAECggIDgAAAA==.Astrialynn:BAAANQADCgYIBwAAAA==.Astrulawa:BAAANQADCgUIBQAAAA==.',
At='Athrea:BAAANQAECgUICwAAAA==.',
Ba='Barakah:BAAANQADCgIIAgAAAA==.Barnre:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgUIBQAAAA==.',
Be='Bearito:BAAANQAECgQIBwAAAA==.Beefstick:BAAANQAECgMIAwAAAA==.Beserkfury:BAAANQAECgMIBAAAAA==.',
Bi='Biercan:BAAANQAECgYIDAAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBAAAAA==.Bittywhite:BAAANQADCgYIDAAAAA==.',
Bl='Blayze:BAAANQADCgUIBQAAAA==.Blinkytime:BAAANQAECgIIAwAAAA==.Blúnt:BAAANQADCgQIBAAAAA==.',
Bo='Bobheals:BAAANQAECgQIBwAAAA==.Boibye:BAAANQAECgQIBgAAAA==.Bolblock:BAAANQAECgYIBwAAAA==.Bolo:BAAANQAECgcIEwAAAA==.Boostedww:BAAANQAECgQICwAAAA==.',
Br='Brambleclaw:BAAANQAECgUIDgAAAA==.Brayker:BAAANQAECgUIDgAAAA==.Breadoneal:BAAANQAECgQIBwAAAA==.Brewed:BAAANQAECgEIAQAAAA==.Brynjamin:BAAANQAECgQICAAAAA==.Brüenor:BAAANQAECgMIBQAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAAANQADCgcIFgAAAA==.Burntroot:BAAANQAECgMIAwAAAA==.',
['Bá']='Bálor:BAAANQAECgEIAQAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Camdakablam:BAAANQAECgYIDwAAAA==.Careadin:BAAANQADCgQIBAABNQAECgUIBwACAAAAAA==.Careradin:BAAANQAECgUIBwAAAA==.Carereaper:BAAANQADCggIDAABNQAECgUIBwACAAAAAA==.Cartilage:BAAANQAECgUIBwAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ce='Centrest:BAAANQADCgIIAgAAAA==.',
Ch='Chebbles:BAAANQADCgIIAgABNQAECgIIAwACAAAAAA==.Chillidan:BAAANQADCgQIBAABNQAECgcIEQACAAAAAA==.Chivi:BAAANQADCggIDgABNQAECgYIDQACAAAAAA==.Chonkmonk:BAAANQADCgQIBAAAAA==.Chupacabrass:BAAANQAECgIIAgAAAA==.',
Co='Colman:BAAANQADCgcIFgAAAA==.Coorsbanquet:BAAANQAECgUICQAAAA==.Coorsbite:BAAANQADCggIDAABNQAECgUICQACAAAAAA==.Coorslight:BAAANQADCgYIBgABNQAECgUICQACAAAAAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgMIAwAAAA==.Croc:BAAANQAECgUIDgAAAA==.',
Cs='Csyasha:BAAANQADCgcIBwABNQAECgQIBwACAAAAAA==.',
Cu='Cubcadet:BAAANQAECgQIBAAAAA==.',
Cy='Cybear:BAAANQADCggICAAAAA==.',
Da='Dalanora:BAAANQAECgUIDgAAAA==.Dapalyu:BAAANQAECgEIAQAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQADCgYIBgAAAA==.Demine:BAAANQAECgMIBAAAAA==.Detrazeral:BAAANQADCggIEAAAAA==.',
Di='Dico:BAAANQAECgEIAQABNQAECgkJIAADAMccAA==.Dipper:BAAANQAECgYIDAAAAA==.',
Do='Dohan:BAAANQADCggICgAAAA==.',
Ee='Eeveeko:BAAANQAECgYIDAAAAA==.',
Ej='Ejavuday:BAAANQAECgUIBwAAAA==.',
En='Enerchi:BAAANQAECgcIEQAAAA==.',
Er='Ervyne:BAAANQAECgQIBAAAAA==.',
Ev='Evera:BAAANQAECgMIAwAAAA==.Evos:BAAANQADCgYIBgAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fauci:BAAANQADCgIIAgABNQAECgkJGgAEAEwiAA==.',
Fe='Feihao:BAAANQADCgYIEwAAAA==.Feile:BAAANQAECgUIBQAAAA==.Feltree:BAAANQADCgQIBAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAAANQAECgcIDAAAAA==.Flyknit:BAAANQAECgIIAgAAAA==.',
Fr='Fredthedh:BAAANQAECgQICgAAAA==.Fromtheback:BAAANQAECgIIAgABNQAECgQIBQACAAAAAA==.Frosticals:BAAANQAECggIEgAAAA==.',
Ga='Gaashw:BAAANQABCgQIBAAAAA==.Ganandor:BAAANQAECgYIDAAAAA==.Gaulish:BAAANQADCgcIBwAAAA==.',
Ge='Geocide:BAAANQAECgYIEQAAAA==.Gethalyn:BAAANQADCgUICgAAAA==.',
Gh='Ghume:BAAANQADCgYIDAAAAA==.',
Gi='Gianthippo:BAAANQADCgQIBAAAAA==.',
Gr='Grizzoul:BAAANQADCgQIBAAAAA==.Grreenry:BAAANQADCgIIAgAAAA==.Grumly:BAAANQADCggIDwAAAA==.',
Ha='Hanswoloqued:BAAANQAECgcIDwAAAA==.',
He='Healufast:BAAANQAECgQIBwAAAA==.Helstrom:BAAANQABCggIDQAAAA==.',
Hj='Hjalmar:BAAANQAECgUICQAAAA==.',
Ho='Holysabeline:BAAANQAECgUIDgAAAA==.Hotpots:BAAANQAECggIBAAAAA==.',
Hu='Huchar:BAAANQAECgUICwAAAA==.',
Hy='Hydraxix:BAAANQADCggICAAAAA==.Hypnose:BAAANQABCgUIBQAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
Ir='Ironßest:BAAANQABCgUICwAAAA==.',
Ja='Jadzi:BAAANQADCgYIBgAAAA==.Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jensthyra:BAAANQABCgcICgAAAA==.',
Jo='Jobo:BAAANQAECgQIBgAAAA==.',
Ju='Julzaria:BAAANQADCggIGgAAAA==.Jurny:BAAANQAECgIIAwAAAA==.',
Ka='Kahlandra:BAAANQAECgUIDgAAAA==.Kaizer:BAABNQAECoEYAAIFAAgJhRgUIwBbAgAFAAgJhRgUIwBbAgAAAA==.Kandera:BAAANQADCgUIBQAAAA==.Karina:BAAANQADCgUIBQABNQAECgUIDgACAAAAAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAAANQABCgQIBgAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQADCgYIBwAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Khornedog:BAAANQAECgUICAAAAA==.Khrama:BAAANQAECgUICwAAAA==.',
Kl='Kleenonean:BAABNQAECoEwAAIGAAkJ8SVFAAD3AwAGAAkJ8SVFAAD3AwAAAA==.',
Kr='Krackjarr:BAAANQADCggIDQAAAA==.Kredor:BAAANQAECgEIAQAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQADCggICQAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAAANQAECgUICgAAAA==.',
Le='Lemonpepper:BAAANQAECgUICQAAAA==.Lexxix:BAAANQADCgcIDAAAAA==.Leyru:BAAANQAECgUIDAAAAA==.',
Li='Liberos:BAAANQAECgEIAQAAAA==.Littlechiken:BAAANQADCgUIBQABNQAECgkJHgAHAHEWAA==.',
Ln='Lninedkhack:BAAANQAECgQICAAAAA==.',
Lo='Logaar:BAAANQAECgcIEgAAAA==.',
Lu='Luxurix:BAAANQADCggIEQAAAA==.',
Ma='Magtao:BAAANQADCgYIDwAAAA==.Malexannius:BAAANQADCgYIDwAAAA==.Maplebrick:BAAANQABCgIIAgAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECggICgAAAA==.',
Me='Medean:BAAANQADCggICAAAAA==.Megtallica:BAAANQADCggIDwAAAA==.Mensrea:BAAANQAECgEIAQAAAA==.Merrycold:BAAANQAECgcIEAAAAA==.',
Mf='Mfgirthquake:BAAANQAECgcIDwAAAA==.',
Mi='Miisty:BAAANQADCggICwAAAA==.Mikklelee:BAAANQADCggIDwAAAA==.Mings:BAAANQAECgQICAAAAA==.Mistweaver:BAAANQAECgYIDAAAAA==.',
Mo='Mochi:BAAANQAECgQIBQAAAA==.Mochïi:BAAANQADCgIIBAABNQAECgkJHwAIAMIiAA==.Mojoe:BAAANQAECgQIBAAAAA==.Mommyswaggin:BAAANQAECgEIAQAAAA==.Moopster:BAAANQAECgYIDgAAAA==.Moopy:BAAANQADCgUIBQABNQAECgYIDgACAAAAAA==.Mootangclan:BAAANQAECgQIBgAAAA==.',
Na='Nanashi:BAAANQAECgIIAgAAAA==.Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Neiko:BAAANQAECgYIDgAAAA==.Neptuneakis:BAAANQAECgIIAwAAAA==.Newcarsmell:BAAANQADCggIGgAAAA==.',
Ni='Niceknife:BAAANQADCggIDQAAAA==.Niquid:BAAANQADCggIDwAAAA==.Niylea:BAAANQADCgUIBQABNQAECgUICwACAAAAAA==.',
No='Nobu:BAABNQAECoEaAAIEAAkJTCJvAQCfAwAEAAkJTCJvAQCfAwAAAA==.Norinari:BAAANQAFFAIIAwAAAA==.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAAANQAECgUIDgAAAA==.',
Ob='Obliteration:BAAANQAECgQIBgABNQAECgcIEQACAAAAAA==.',
Oe='Oenaa:BAAANQABCgQIBAAAAA==.',
Ol='Olivertwist:BAAANQAECgMIBAABNQAECgcIEQACAAAAAA==.',
On='Ontwou:BAAANQAECgQICAAAAA==.',
Or='Orbz:BAAANQAECgYIDAAAAA==.Orcazm:BAAANQAECgEIAQAAAA==.',
Pa='Palyont:BAAANQADCgYIEAAAAA==.Pancakezebra:BAAANQAECgYIDQAAAA==.Parse:BAAANQAECgIIAwAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAAANQAECgUICwAAAA==.',
Pi='Pikechu:BAAANQAECgQIBgAAAA==.Pinkskies:BAAANQAECgIIAgAAAA==.',
Pl='Pleasy:BAAANQAECgQIBwAAAA==.Plugtobacca:BAAANQADCgIIAgABNQAECgkJGgAEAEwiAA==.',
Po='Pocketchange:BAAANQAECgYIDwAAAA==.Pocketwatch:BAAANQADCggICAABNQAECgYIDwACAAAAAA==.',
Pr='Preservation:BAAANQADCgIIAgABNQAECgYIDAACAAAAAA==.Promethêus:BAAANQAECgEIAQAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQAECgIIAgAAAA==.',
Qr='Qrz:BAAANQADCgMIAwAAAA==.',
Re='Relovan:BAAANQAECgQIBgAAAA==.Renothidan:BAAANQAECgcIDwAAAA==.Ret:BAAANQADCgcIBwABNQAECgcIDwACAAAAAA==.Reuben:BAAANQAECgEIAQAAAA==.Revin:BAAANQAECgQICgAAAA==.Revrynth:BAAANQAECgYIDQAAAA==.Rexorcist:BAAANQAECgQIBwAAAA==.',
Ri='Rimed:BAAANQAECgUICQAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcIBwAAAA==.Rizzdolphler:BAABNQAECoEXAAMJAAkJMhmgDQD9AgAJAAkJMhmgDQD9AgAKAAMJpgUByABoAAAAAA==.',
['Rö']='Rönburgundy:BAAANQAECgYIDwAAAA==.',
Sa='Sanako:BAAANQAECgQIBwAAAA==.Saneros:BAAANQAECgIIAgAAAA==.',
Sc='Scraggle:BAAANQADCgcICwAAAA==.Scuffito:BAAANQAECgMIBAAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Setheron:BAAANQADCgcIFgAAAA==.',
Sh='Shlea:BAAANQAECgcIDwAAAA==.Shley:BAAANQADCgYIBgABNQAECgcIDwACAAAAAA==.',
Si='Silvanna:BAAANQADCggICAAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
So='Solendros:BAAANQAECgQIBAAAAA==.Sonoa:BAAANQADCgYIDwAAAA==.Sonthar:BAAANQADCgQIBAAAAA==.Sorlight:BAAANQADCgcICQAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAAANQAECgIIAgAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
St='Standarshh:BAAANQAECgQICQAAAA==.Stevenz:BAAANQAECgUICQAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAAANQAECggIDwAAAA==.Sugarbabi:BAAANQAECgYICgAAAA==.Sugarshot:BAAANQADCgQIBAAAAA==.Sugartotem:BAAANQAECgIIAgAAAA==.',
Sw='Swiftwing:BAAANQADCgQIBAAAAA==.',
Sy='Sydarliia:BAAANQAECgUICgAAAA==.Sylrianah:BAAANQAECgUIDgAAAA==.Sylveste:BAAANQAECgUIBQAAAA==.',
Ta='Tal:BAAANQAECgcIAQAAAA==.Tankhiskhan:BAAANQAECgUICQAAAA==.',
Te='Tei:BAAANQADCgEIAQAAAA==.',
Th='Thannill:BAAANQAECgQIBQAAAA==.',
Ti='Tie:BAAANQAECgcIDwAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Torzhu:BAAANQAECgUICwAAAA==.Toy:BAAANQAECgcICgABNQAFFAUIDAALAF4UAA==.',
Tr='Travvy:BAACNQAFFIERAAMMAAcJCCEgAQAHAgAMAAUJzyAgAQAHAgAEAAIJlSG4AgDdAAA1AAQKgR8AAwwACQkdJpEBAJgDAAwACQlAIpEBAJgDAAQAAwn2IOUmAC4BAAAA.Trevmo:BAAANQAECgIIAgAAAA==.Trexin:BAAANQADCgMIAwAAAA==.',
Tz='Tzuyu:BAAANQAECgUIDgAAAA==.',
Ud='Uddershock:BAAANQADCggIDgAAAA==.',
Un='Unbreakabull:BAAANQAECgUICQAAAA==.Unver:BAAANQADCgYIBgAAAA==.',
Va='Vae:BAAANQAECgYICwAAAA==.Valka:BAAANQAECgEIAQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAAANQAECgQIBwAAAA==.Veyle:BAAANQAECgUIDgAAAA==.',
Vi='Viibryd:BAAANQADCgYIBgAAAA==.',
Vy='Vyndria:BAAANQADCgcIDQAAAA==.Vyran:BAAANQADCgIIAgAAAA==.',
Wa='Waypal:BAAANQADCggIFwAAAA==.',
We='Weashock:BAAANQADCgYIDAAAAA==.Weasy:BAAANQADCggICAAAAA==.',
Wi='Windfury:BAAANQAECgYICwAAAA==.Wingzard:BAAANQAECgUIDAAAAA==.',
Xl='Xl:BAAANQAECggIBgAAAA==.',
Ya='Yaitoopmfp:BAAANQAECgEIAQABNQAECgcIEAACAAAAAA==.Yao:BAAANQAECgYIDQAAAA==.Yasrena:BAAANQADCgIIAgAAAA==.',
Za='Zabara:BAAANQADCgYIBgABNQAECgUICQACAAAAAA==.Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAAANQAECgUIDgAAAA==.Zaki:BAAANQAECgYIEAAAAA==.',
Ze='Zealot:BAAANQADCgEIAQAAAA==.Zeleria:BAAANQADCgcIDgAAAA==.Zerathis:BAAANQADCgEIAQAAAA==.',
Zi='Zinbek:BAAANQADCgUIBQAAAA==.Zip:BAAANQABCgYIBgAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zoo:BAAANQAECgIIAgAAAA==.Zorb:BAAANQAECgUIDQAAAA==.Zoshow:BAAANQADCggIEwAAAA==.',
['Zõ']='Zõshow:BAAANQADCggICwAAAA==.',
['Ða']='Ðaredevil:BAAANQAECgQIBAABNQAECgYICwACAAAAAA==.',
['Ðp']='Ðp:BAAANQAECgMIBAAAAA==.',
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
