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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Akama',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acronica:BAAANQADCgQIBAAAAA==.',
Ad='Addilynn:BAAANQABCgEIAQAAAA==.',
Al='Alecto:BAAANQADCgcIDAAAAA==.Allele:BAAANQADCgYICgAAAA==.',
Am='Amarah:BAAANQAECgIIBAAAAA==.Ameilie:BAAANQAECgMIAwAAAA==.',
An='Anapuwae:BAAANQAECgEIAQAAAA==.Animehero:BAAANQAECgQIBQAAAA==.',
Ar='Arcant:BAAANQADCggIDgAAAA==.Ardicov:BAAANQADCgQIBQAAAA==.Argadin:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Argrekh:BAAANQAECgUIBQAAAA==.Argrekt:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Aridol:BAAANQADCgYIBgAAAA==.Aronna:BAAANQADCgIIAQAAAA==.Arthaslk:BAAANQAECgYICgABNQAECgcIDQABAAAAAA==.',
At='Ate:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Attman:BAAANQAECgIIAwAAAA==.',
Be='Bearmane:BAAANQAECgMIAwAAAA==.Beastarsfan:BAAANQAECgEIAQAAAA==.Behmow:BAAANQAECgcIBwAAAA==.Belithel:BAAANQAECgIIAgAAAA==.Bencreepin:BAAANQADCgYICQAAAA==.Bernoulli:BAAANQAECgEIAQAAAA==.',
Bl='Blessedxx:BAAANQADCggIDQAAAA==.Bloodboo:BAAANQADCgQIBAAAAA==.Bloodyhpally:BAAANQAFFAEIAQAAAA==.',
Bo='Boopsnoopems:BAAANQADCgYICwAAAA==.',
Br='Bradcrit:BAAANQADCgEIAQAAAA==.',
Bu='Bustah:BAAANQADCgcIBwABNQAECgcIBwABAAAAAA==.',
Bw='Bwoodmorgan:BAAANQADCggICAAAAA==.',
Ca='Calene:BAAANQAECgcIDQAAAA==.Casare:BAAANQADCgYICgAAAA==.',
Ce='Celestinee:BAAANQADCgYICAAAAA==.Cenarian:BAAANQABCgIIAgAAAA==.',
Ch='Chape:BAAANQAECgYICgAAAA==.',
Ci='Cinderlee:BAAANQADCgUICgAAAA==.',
Cl='Cleaveage:BAAANQADCgEIAQAAAA==.',
Co='Colexn:BAAANQAECgYIBwAAAA==.Cong:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Congdh:BAAANQAECgcIDAAAAA==.Cornchipz:BAAANQAECgEIAQAAAA==.',
Cr='Cryonidus:BAAANQADCgYICwAAAA==.',
Cu='Curves:BAAANQAECgEIAQAAAA==.',
Da='Daangalanng:BAAANQAECgQICAAAAA==.Daegra:BAAANQAECgIIAgAAAA==.Darkacedia:BAAANQAECgQIBAAAAA==.',
De='Dealosed:BAAANQAECgQIBAAAAA==.Deathkilera:BAAANQADCgMIAwAAAA==.Delenn:BAAANQAECgUIBwAAAA==.',
Di='Disastastab:BAAANQAECgQIBAAAAA==.Dive:BAAANQAECgYICgAAAA==.',
Do='Doogru:BAAANQAECgMIAwAAAA==.Doogtwo:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Doryndoran:BAAANQADCgUIBQAAAA==.Dotproduct:BAAANQADCgEIAQABNQADCgIIAgABAAAAAA==.',
Dr='Dragoneggs:BAAANQAECgEIAQAAAA==.Dragonforce:BAAANQADCgYICgABNQADCgcIBwABAAAAAA==.Drakonutz:BAAANQADCgYICwAAAA==.Dreammachine:BAAANQADCgQIBwAAAA==.Drjoel:BAAANQADCgYICwAAAA==.Drunkenutz:BAAANQADCgYICgAAAA==.',
Dw='Dwallen:BAAANQADCgIIAgAAAA==.',
['Dä']='Dälf:BAAANQAECgIIAgABNQAFFAIIAwABAAAAAA==.',
Ea='Earthshocker:BAAANQADCgUIBwAAAA==.',
El='Elenix:BAAANQAECgYIAQAAAA==.Elmesia:BAAANQADCgYICAAAAA==.Eloris:BAAANQAECgEIAQAAAA==.',
Em='Emachine:BAAANQADCggICAAAAA==.Emz:BAAANQAECggIBQAAAA==.',
En='Eniar:BAAANQADCgQIBAAAAA==.',
Er='Erakk:BAAANQADCgEIAgAAAA==.Eric:BAAANQAECgQIBAAAAA==.Eroninja:BAAANQADCgUIBwABNQAECgIIAgABAAAAAA==.Erín:BAAANQADCgcIDAAAAA==.',
Eu='Eurong:BAAANQAECgcIBwAAAA==.',
Ez='Ezynuff:BAAANQADCgcIDQAAAA==.',
Fa='Faïry:BAAANQAECgYIBwAAAA==.',
Fe='Felwyrm:BAAANQAECgUIBwAAAA==.',
Fo='Foragh:BAAANQADCggIDwABNQAECgEIAQABAAAAAA==.',
Fr='Freakbeast:BAAANQAECgUIBwAAAA==.',
Fu='Fullkidney:BAAANQADCgcIDAAAAA==.Funch:BAAANQAECgMIAwAAAA==.',
Ga='Gaefaeryn:BAAANQAECgQIBQAAAA==.Garonnaa:BAAANQAECgQIBAAAAA==.',
Ge='Genetiks:BAAANQADCgYIDAAAAA==.',
Gh='Ghari:BAAANQAECgQIBAAAAA==.',
Gi='Gingerlock:BAAANQADCgYICwAAAA==.',
Gn='Gnoblin:BAAANQADCgUIBQAAAA==.',
Gr='Greka:BAAANQADCgYICwAAAA==.Greylooms:BAAANQADCgcIBwAAAA==.Griplock:BAAANQAECgIIAgAAAA==.',
He='Healalle:BAAANQADCgYICwABNQADCgcIDAABAAAAAA==.Healhole:BAAANQAECgEIAQAAAA==.Heàl:BAAANQADCgQIBAAAAA==.',
Hu='Hunterishard:BAAANQADCgcIBwAAAA==.',
Hy='Hylaina:BAAANQADCgYICgAAAA==.',
Ia='Iamamonk:BAAANQADCgEIAQAAAA==.',
Ik='Ikerous:BAAANQADCgMIAwAAAA==.',
Im='Imadwagon:BAAANQADCgcIAgAAAA==.Imcolorblind:BAAANQADCgIIAgAAAA==.Imhammered:BAAANQAECgMIAwAAAA==.',
It='Itiswhatitiz:BAAANQAECgIIBAAAAA==.Itsybityshiv:BAAANQAECgMIAwAAAA==.',
Jh='Jhani:BAAANQADCgYICwAAAA==.',
Jo='Joethemage:BAAANQADCgcIBwAAAA==.',
Ju='Jungol:BAAANQADCgUICQAAAA==.',
Ka='Kamin:BAAANQAECgYIBgABNQAECggIDAABAAAAAA==.Kaykaypally:BAAANQAECgEIAQAAAA==.',
Ki='Kidata:BAAANQAECgEIAQAAAA==.Kinji:BAAANQADCgUICAABNQAECgIIAgABAAAAAA==.',
Ko='Konfu:BAAANQADCgYIDAAAAA==.Korral:BAAANQADCgUIBQAAAA==.',
Kr='Krispies:BAAANQAECgEIAQAAAA==.Kristysavage:BAAANQAECgIIAgAAAA==.',
Ku='Kulaesca:BAAANQAECgYIBwAAAA==.',
Ky='Kynar:BAAANQAFFAEIAQAAAA==.',
La='Ladragona:BAAANQADCggICAAAAA==.Lambshot:BAAANQADCgUICQAAAA==.Lambsy:BAAANQAFFAEIAQAAAA==.Lanamama:BAAANQAECgEIAQAAAA==.Lanana:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Le='Lerat:BAAANQADCgcICgAAAA==.',
Li='Lightwarden:BAAANQADCgQIBAAAAA==.Lilyy:BAAANQAECgQIBAAAAA==.Lisanalgaib:BAAANQAECgQIBQAAAA==.Lizzimcguire:BAAANQAECgQIBQAAAA==.',
Lo='Lobobare:BAAANQAECggICwAAAA==.Loraen:BAAANQADCgUIBgAAAA==.',
Lu='Lunarmon:BAAANQADCgUIBQAAAA==.Lunchable:BAAANQAECgMIAwAAAA==.',
Ma='Maevora:BAAANQADCgcIDAAAAA==.Makaroni:BAAANQADCgUIBwAAAA==.Manticus:BAAANQADCgIIAgAAAA==.Marni:BAAANQADCgQIBAAAAA==.Martel:BAAANQADCgQIBAAAAA==.Matroxx:BAAANQAECgcICwAAAA==.',
Me='Meenoi:BAAANQAECgcIBwAAAA==.Metatron:BAAANQADCgIIAgAAAA==.',
Mi='Miadas:BAAANQADCgYIBgABNQAECgUIBQABAAAAAA==.',
Mo='Moardotsnow:BAAANQAECgIIAgAAAA==.Moby:BAAANQADCgYICgAAAA==.Mortiana:BAAANQADCggICAAAAA==.',
My='Mykaela:BAAANQADCgcIBwAAAA==.',
['Më']='Mëow:BAAANQADCgcIDQAAAA==.',
Na='Narrath:BAAANQADCgMIAwAAAA==.Nayalaah:BAAANQADCgcIBwAAAA==.',
Ne='Nehpets:BAAANQADCgUIBQAAAA==.Nephelym:BAAANQADCgcIDQAAAA==.Nerv:BAAANQADCgMIBQAAAA==.',
Ni='Nirina:BAAANQADCgYICwAAAA==.',
No='Nohtil:BAAANQADCgMIBAAAAA==.',
Nu='Nut:BAAANQAECgMIBAAAAA==.',
['Nö']='Nötprepared:BAAANQADCgQIBAABNQADCgYICAABAAAAAA==.',
Oi='Oiflar:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Ol='Olangi:BAAANQADCgcICwAAAA==.',
Om='Omnidh:BAAANQADCggICAABNQAECgYIBwABAAAAAA==.',
On='Onepavo:BAAANQAECgEIAQAAAA==.',
Op='Oppose:BAAANQADCggICQAAAA==.',
Or='Orexion:BAAANQADCggIDgAAAA==.Ormagöden:BAAANQAECgQIBQAAAA==.',
Pa='Palladean:BAAANQADCgYICgAAAA==.Palphen:BAAANQAECgIIAgAAAA==.Pastasauce:BAAANQAECgMIAwAAAA==.',
Pe='Pegero:BAAANQADCgYICAABNQAECgMIAwABAAAAAA==.Penelohpe:BAAANQAECggIDAAAAA==.',
Ph='Phatt:BAAANQADCgYIBgAAAA==.Phoenixdrac:BAAANQADCggICAAAAA==.Phoon:BAAANQAECgYIBgAAAA==.Phoondk:BAAANQAECgMIAwABNQAECgYIBgABAAAAAA==.',
Pi='Piggy:BAAANQAECgEIAQAAAA==.Pizzadriver:BAAANQAFFAEIAQAAAA==.',
Pl='Plaguefist:BAAANQADCgcIBwAAAA==.Plata:BAAANQADCgMIAwAAAA==.',
Pr='Praytroxx:BAAANQADCgYICAABNQAECgcICwABAAAAAA==.Premonitions:BAAANQADCggICAAAAA==.Premune:BAAANQAECgQIBQAAAA==.',
Pu='Pucco:BAAANQADCgIIAgAAAA==.',
Py='Pyrena:BAAANQADCgEIAQAAAA==.Pyroclasm:BAAANQAECgEIAQAAAA==.',
Qu='Quigly:BAAANQADCgIIAgAAAA==.',
Ra='Raine:BAAANQAFFAEIAQAAAA==.Raistlin:BAAANQADCgEIAQAAAA==.Ralfio:BAAANQAECgIIAgAAAA==.Rat:BAAANQAECgcICwAAAA==.Raynith:BAAANQAECgUIBQAAAA==.',
Rd='Rdyoshy:BAAANQADCgUIBQAAAA==.',
Re='Readycheck:BAAANQADCgUIBQAAAA==.Regirock:BAAANQABCgMIAwAAAA==.Rellek:BAAANQADCgcIDQAAAA==.Remulous:BAAANQADCgYICwAAAA==.Retallica:BAAANQADCgEIAgAAAA==.Revali:BAAANQAFFAEIAQAAAA==.Revelaen:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.',
Ri='Rick:BAAANQAECgYICQAAAA==.',
Rm='Rmagep:BAAANQAECgIIAgAAAA==.',
Ro='Roshango:BAAANQADCgYIBgAAAA==.Rowgar:BAAANQADCgUICAAAAA==.',
Ru='Rubenslik:BAAANQABCgQIBAAAAA==.',
['Rá']='Ráts:BAAANQADCgUIBQAAAA==.',
Sa='Saelyn:BAAANQADCggIBgAAAA==.Saephora:BAAANQADCgQIBgAAAA==.Saggypants:BAAANQADCgQIBAAAAA==.Sakurai:BAAANQAECgEIAQABNQAECgYIBgABAAAAAA==.Sammel:BAAANQAECgIIAgAAAA==.Sathreina:BAAANQAECgMIAwAAAA==.',
Sc='Scaries:BAAANQAECgIIAgAAAA==.Scuss:BAAANQADCggICAAAAA==.',
Se='Sego:BAAANQADCgYICgAAAA==.Sekimura:BAAANQAECgYIBgAAAA==.Sey:BAAANQADCgYIBgAAAA==.',
Sh='Shadowapoke:BAAANQADCgUIBQAAAA==.Shadowisbad:BAAANQAECgQIBAAAAA==.Shadvoker:BAAANQAECgQIBQAAAA==.Shamatroxx:BAAANQAECgEIAQABNQAECgcICwABAAAAAA==.Shamberry:BAAANQADCgIIAgAAAA==.Shambles:BAAANQADCgYICQAAAA==.Shieldwalle:BAAANQADCgcIDAAAAA==.',
Si='Sidric:BAAANQADCgYIBgAAAA==.Silre:BAAANQADCgYICQAAAA==.Sim:BAAANQAECgIIAgAAAA==.Sipplex:BAAANQADCgQIBAAAAA==.',
Sl='Slander:BAAANQADCgYICAAAAA==.',
Sn='Snuudle:BAAANQAECgcIDQAAAA==.',
So='Solokills:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.Sophia:BAAANQAECgEIAQAAAA==.Soundtrack:BAAANQADCgYIBwABNQADCggICAABAAAAAA==.Soyshine:BAAANQADCgYIBgAAAA==.',
Sq='Squab:BAAANQAECgMIAwAAAA==.Squanchy:BAAANQADCgYICAAAAA==.',
St='Stabbywixx:BAAANQADCgcIBwAAAA==.Stickman:BAAANQADCggICAABNQAECgUIBwABAAAAAA==.Stillcreepin:BAAANQADCgUIBQAAAA==.Storienn:BAAANQADCgcIDQAAAA==.Stormzpaly:BAAANQADCgYIBgAAAA==.',
Su='Suküna:BAAANQADCggICwAAAA==.Sunbur:BAAANQADCgQIBAAAAA==.Surch:BAAANQADCgEIAQAAAA==.',
Sw='Swaption:BAAANQAECgQIBAAAAA==.Sweetie:BAAANQADCgEIAQAAAA==.',
Sy='Syrelia:BAAANQADCggIEwAAAA==.',
['Só']='Sónny:BAAANQABCgIIAgAAAA==.',
Ta='Tauloe:BAAANQADCgYIBwAAAA==.Tayna:BAAANQABCgMIAwAAAA==.',
Te='Tenderoni:BAAANQADCgEIAQAAAA==.',
Th='Thatsmyhorse:BAAANQADCgIIAgAAAA==.Thunk:BAAANQADCggIDwABNQAECgIIAgABAAAAAA==.',
Ti='Timmolate:BAAANQAFFAEIAQAAAA==.',
To='Tomcruise:BAAANQAECgIIAgAAAA==.Tomotostein:BAAANQAECgUICQAAAA==.',
Tr='Tristîtia:BAAANQAECgIIAgAAAA==.',
Ts='Tsuma:BAAANQABCgIIAgAAAA==.',
Tt='Ttomas:BAAANQAECgMIAwAAAA==.',
Ty='Tyv:BAAANQADCgcIDgAAAA==.',
Uz='Uzì:BAAANQADCgIIAgAAAA==.',
Va='Vainatetosix:BAAANQADCgYICAAAAA==.Vallodon:BAAANQAECgIIAgAAAA==.Vanwolfy:BAAANQADCggIDQAAAA==.Vaylorian:BAAANQADCgYICwAAAA==.',
Ve='Velectran:BAAANQADCgUICgABNQADCggIEwABAAAAAA==.Velorian:BAAANQADCgMIAwAAAA==.',
Vi='Vikav:BAAANQADCgIIAgAAAA==.',
Vo='Voodoomike:BAAANQADCgQIBAAAAA==.Vortash:BAAANQADCgMIAwAAAA==.',
Vy='Vynle:BAAANQADCgcIEgAAAA==.',
Wa='Warheimer:BAAANQADCggIDwAAAA==.Warrgodx:BAAANQAECgcIDQAAAA==.',
Wh='Whoknows:BAAANQADCgIIAgAAAA==.',
Wr='Wrongwookie:BAAANQAECgQIBQAAAA==.',
Ya='Yapper:BAAANQADCgMIAwAAAA==.',
Yo='Yolanda:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Za='Zabada:BAAANQADCgEIAQAAAA==.',
Ze='Zemsen:BAAANQAECgcIDQAAAA==.Zenyea:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Zetta:BAAANQAECgYICgAAAA==.',
Zo='Zome:BAAANQAECgQIBAAAAA==.',
['Èl']='Èlytz:BAAANQADCgYICQAAAA==.',
['Êl']='Êlytz:BAAANQADCggICAAAAA==.',
['ßl']='ßlue:BAAANQADCgQIBQAAAA==.',
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
