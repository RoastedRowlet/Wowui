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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Evoker-Preservation','DeathKnight-Blood','Paladin-Retribution','Monk-Windwalker','Evoker-Devastation','Warlock-Destruction','Warlock-Affliction','Rogue-Assassination','Mage-Arcane','Paladin-Holy','Shaman-Elemental','Hunter-BeastMastery','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Enhancement','Shaman-Restoration','Priest-Holy','Hunter-Survival','Evoker-Augmentation','Rogue-Subtlety','DemonHunter-Devourer',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abbpriest:BAAANQADCgYJBgABNQAECggJGQABAO4XAA==.Abruum:BAAANQADCgYIBgAAAA==.',
Ad='Admetus:BAAANQAECgQIBgAAAA==.Adobe:BAAANQADCggJFQAAAA==.',
Am='Amathal:BAAANQAECgcJBwAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgUICgAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICAAAAA==.Aredhela:BAAANQAECgUICgAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQAECgQICAAAAA==.Asha:BAAANQAECggJEQAAAA==.Astrialynn:BAAANQADCgYIBwAAAA==.Astrulawa:BAAANQADCgYJBgAAAA==.',
At='Athrea:BAAANQAECgYJEQAAAA==.',
Ba='Barakah:BAAANQADCgIJAgAAAA==.Barnre:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgUJBQAAAA==.',
Be='Bearito:BAAANQAECgQIBwAAAA==.Beefstick:BAAANQAECgUJBQAAAA==.Beserkfury:BAAANQAECgUJCQAAAA==.',
Bi='Biercan:BAAANQAECgYIDAAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBAAAAA==.Bittyboop:BAAANQADCgQIBQABNQADCgYJEgACAAAAAA==.Bittywhite:BAAANQADCgYJEgAAAA==.',
Bj='Bjarna:BAAANQAECgIIAgAAAA==.',
Bl='Blayze:BAAANQADCgUIBQAAAA==.Blinkytime:BAAANQAECgUJCAAAAA==.Blúnt:BAAANQADCgQIBAAAAA==.',
Bo='Bobheals:BAAANQAECgUJCgAAAA==.Boibye:BAAANQAECgQJCQAAAA==.Bolblock:BAAANQAECgcIDgAAAA==.Bolo:BAABNQAECoEeAAIDAAgKRh+dCADkAgADAAgKRh+dCADkAgAAAA==.Boostedww:BAAANQAECgQICwAAAA==.',
Br='Brambleclaw:BAABNQAECoEYAAIEAAcKpiGxFQCwAgAEAAcKpiGxFQCwAgAAAA==.Brayker:BAABNQAECoEYAAIFAAcKACCeNgB6AgAFAAcKACCeNgB6AgAAAA==.Breadoneal:BAAANQAECgQIBwAAAA==.Brewed:BAAANQAECgEIAQAAAA==.Brynjamin:BAAANQAECgQICAAAAA==.Brüenor:BAAANQAECgMIBQAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAAANQADCggIHgAAAA==.Burntroot:BAAANQAECgQJBwAAAA==.',
['Bá']='Bálor:BAAANQAECgEJAgAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Caedwyn:BAAANQAECgQJBAAAAA==.Camdakablam:BAAANQAECgcJEQAAAA==.Careadin:BAAANQADCgQIBAABNQAECgYIDAACAAAAAA==.Careradin:BAAANQAECgYIDAAAAA==.Carereaper:BAAANQADCggIDAABNQAECgYIDAACAAAAAA==.Cartilage:BAAANQAECgUIBwAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ce='Centrest:BAAANQADCgYJCAAAAA==.',
Ch='Chebbles:BAAANQADCgIIAgABNQAECgQJBwACAAAAAA==.Chillidan:BAAANQAECgMIAwABNQAECgkJHQAGAH4fAA==.Chivi:BAAANQADCggJDgABNQAECgcIFAAHAAUfAA==.Chonkmonk:BAAANQADCgQIBAAAAA==.Chupacabrass:BAAANQAECgIIAgAAAA==.Chëbbles:BAAANQADCgQJBAABNQAECgQJBwACAAAAAA==.',
Co='Colman:BAAANQADCggJHgAAAA==.Coorsbanquet:BAAANQAECgUICQAAAA==.Coorsbite:BAAANQAECgEIAQABNQAECgUICQACAAAAAA==.Coorslight:BAAANQADCgYIBgABNQAECgUICQACAAAAAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgMIAwAAAA==.Croc:BAAANQAECgUIDgAAAA==.Crudala:BAAANQABCgUJBQABNQAECgIIAQACAAAAAA==.Crystle:BAAANQAECgEIAQAAAA==.',
Cs='Csyasha:BAAANQADCgcJBwABNQAECgUICQACAAAAAA==.',
Cu='Cubcadet:BAAANQAECgQIBAAAAA==.',
Cy='Cybear:BAAANQAECgIJAgAAAA==.',
Da='Dalanora:BAABNQAECoEYAAQBAAcKPhwpSwDzAQABAAYKKBwpSwDzAQAIAAMK2RaANQDIAAAJAAMKxRE6EQC0AAAAAA==.Dapalyu:BAAANQAECgMJBgAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQADCgYIBgAAAA==.Demine:BAAANQAECgMIBAAAAA==.Detrazeral:BAAANQADCggIEAAAAA==.',
Di='Dico:BAAANQAECgEIAQAAAA==.Dipper:BAAANQAECgcJEwAAAA==.',
Do='Dohan:BAAANQADCggIEAAAAA==.Dorìan:BAAANQADCgcJBwAAAA==.',
Dr='Draael:BAAANQADCgQJBAAAAA==.Draetona:BAAANQADCgQJBAAAAA==.',
Ee='Eeveeko:BAAANQAECgcIEwAAAA==.',
Ej='Ejavuday:BAAANQAECgYIDQAAAA==.',
En='Enerchi:BAABNQAECoEdAAIGAAkKfh9yBgAwAwAGAAkKfh9yBgAwAwAAAA==.',
Er='Ervyne:BAAANQAECgcJCwAAAA==.',
Ev='Evera:BAAANQAECgMIAwAAAA==.Evos:BAAANQADCgYJBgAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fauci:BAAANQADCgIJAgABNQAECgkJHAAKAIUiAA==.',
Fe='Feihao:BAAANQADCgYIEwAAAA==.Feile:BAAANQAECgYJCwAAAA==.Feltree:BAAANQADCgQIBAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAAANQAECgcJEQAAAA==.Flyknit:BAAANQAECgIIAwAAAA==.',
Fr='Fredthedh:BAAANQAECgcIEQAAAA==.Fromtheback:BAAANQAECgIIAgAAAA==.Frosticals:BAABNQAECoEaAAILAAkK0hoVPQDVAgALAAkK0hoVPQDVAgAAAA==.',
Ga='Gaashw:BAAANQABCgQIBAAAAA==.Ganandor:BAAANQAECgcIEgAAAA==.Gaulish:BAAANQADCgcIBwAAAA==.',
Ge='Geocide:BAAANQAECgYIEQAAAA==.Gethalyn:BAAANQAECgQJBAAAAA==.',
Gh='Ghume:BAAANQADCgYIDAAAAA==.',
Gi='Gianthippo:BAAANQADCgYJCgAAAA==.Gilf:BAAANQADCgYJBgABNQAFFAUICAABAEAXAA==.',
Gr='Grizzoul:BAAANQAECgMJAwAAAA==.Grreenry:BAAANQADCgIIAgAAAA==.Grumly:BAAANQAECgIJAgAAAA==.',
Ha='Hanswoloqued:BAABNQAECoEZAAIBAAgKKA2SUADeAQABAAgKKA2SUADeAQAAAA==.Haxz:BAAANQADCgUJBQAAAA==.',
He='Healufast:BAAANQAECgYJDQAAAA==.Heck:BAAANQADCgYIBgAAAA==.Helstrom:BAAANQADCgYJBgAAAA==.',
Hj='Hjalmar:BAAANQAECgUICgAAAA==.',
Ho='Holycõw:BAAANQAECggJBwAAAA==.Holysabeline:BAABNQAECoEYAAIMAAcKlwqWXQB/AQAMAAcKlwqWXQB/AQAAAA==.Hotpots:BAAANQAECggJCgAAAA==.',
Hu='Huchar:BAAANQAECgYJEQAAAA==.Humpf:BAAANQADCgEIAQAAAA==.',
Hy='Hydraxix:BAAANQADCggICAAAAA==.Hypnose:BAAANQADCgYJBgAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
Ir='Ironßest:BAAANQABCgUICwAAAA==.',
Ja='Jadzi:BAAANQADCgYJCwAAAA==.Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jensthyra:BAAANQABCgcICgAAAA==.Jessaiyan:BAAANQAECgcIBwAAAA==.',
Jo='Jobo:BAAANQAECgYIDQAAAA==.',
Ju='Julaudette:BAAANQADCgcIBwAAAA==.Julzaria:BAAANQAECgEJAQAAAA==.Jurny:BAAANQAECgMJBQAAAA==.',
Ka='Kahlandra:BAABNQAECoEYAAILAAcKjBAboQDGAQALAAcKjBAboQDGAQAAAA==.Kaizer:BAABNQAECoEfAAINAAgK7hhFLwBOAgANAAgK7hhFLwBOAgAAAA==.Kandera:BAAANQADCgUIBQAAAA==.Karina:BAAANQADCgUJBQABNQAECgcJGAAOAE0lAA==.Karmelo:BAAANQADCgQICQAAAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAAANQAECgIJAgAAAA==.Kevdawg:BAAANQADCgEIAQAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECgQIBAAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Khornedog:BAAANQAECgYJDgAAAA==.Khrama:BAAANQAECgYJEQAAAA==.',
Kl='Kleenonean:BAACNQAFFIEIAAIPAAQKRx7sAwB/AQAPAAQKRx7sAwB/AQA1AAQKgUIAAg8ACQp2JiwAAAUEAA8ACQp2JiwAAAUEAAAA.',
Kr='Krackjarr:BAAANQAECgEIAQAAAA==.Kredor:BAAANQAECgEJAgAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQADCggICQAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAAANQAECgYJEAAAAA==.',
Le='Lemonpepper:BAAANQAECgcICwAAAA==.Lexxix:BAAANQADCgcIDAAAAA==.Leyru:BAAANQAECgUJDAAAAA==.',
Li='Liberos:BAAANQAECgMJBAAAAA==.Littlechiken:BAAANQADCgUIBQABNQAECgkJJwAEAIMZAA==.',
Ln='Lninedkhack:BAAANQAECgUJDQAAAA==.',
Lo='Logaar:BAABNQAECoEeAAMMAAgKphAsOQAUAgAMAAgKphAsOQAUAgAFAAQKzwWv3AClAAAAAA==.',
Lu='Luxurix:BAAANQADCggIEQAAAA==.',
Ma='Magtao:BAAANQADCgYIDwAAAA==.Malexannius:BAAANQADCgYIDwAAAA==.Manastorm:BAAANQAECgEIAQAAAA==.Maplebrick:BAAANQABCgIIAgAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECggJCgAAAA==.',
Me='Medean:BAAANQADCggICAAAAA==.Megtallica:BAAANQAECgIJAgAAAA==.Mensrea:BAAANQAECgEIAQAAAA==.Merrycold:BAABNQAECoEbAAMQAAgK7BdSJABCAgAQAAgK7BdSJABCAgARAAUKDhCCPgAHAQAAAA==.',
Mf='Mfgirthquake:BAABNQAECoEbAAMSAAgKxyNfAwBAAwASAAgKxyNfAwBAAwATAAEKmgPf0QA2AAAAAA==.',
Mi='Miisty:BAAANQADCggICwAAAA==.Mikklelee:BAAANQADCggIDwAAAA==.Mings:BAAANQAECgQICAAAAA==.Mistweaver:BAAANQAECgYIEgAAAA==.',
Mo='Mochi:BAAANQAECgYJCwAAAA==.Mochïi:BAAANQADCgIJBAABNQAFFAUICQALAAoMAA==.Mojoe:BAAANQAECgUJCgAAAA==.Mommyswaggin:BAAANQAECgEIAQAAAA==.Moopster:BAABNQAECoEYAAIUAAgK1iI8DwAEAwAUAAgK1iI8DwAEAwAAAA==.Moopy:BAAANQADCgUIBQABNQAECggJGAAUANYiAA==.Mootangclan:BAAANQAECgYIDAAAAA==.',
Na='Nanashi:BAAANQAECgUIBwAAAA==.Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Neiko:BAABNQAECoEXAAIKAAgKWhZVFQBNAgAKAAgKWhZVFQBNAgAAAA==.Neptuneakis:BAAANQAECgQJBwAAAA==.Newcarsmell:BAAANQADCggIIAAAAA==.',
Ni='Niceknife:BAAANQADCggIDQAAAA==.Niquid:BAAANQADCggIEwAAAA==.Niylea:BAAANQADCgUJBQABNQAECgYJEQACAAAAAA==.',
No='Nobu:BAABNQAECoEcAAIKAAkKhSKMAgCIAwAKAAkKhSKMAgCIAwAAAA==.Noobhuntard:BAAANQADCggICAAAAA==.Norinari:BAACNQAFFIEIAAMBAAUKQBfxBgBPAQABAAQKFhbxBgBPAQAIAAIKyhKJBwCwAAA1AAQKgRwABAkACAruInoDAFgCAAEABgrDIbAwAFwCAAkABgowIXoDAFgCAAgAAwoKGwsnABgBAAAA.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAAANQAECgYJEwAAAA==.',
Ob='Obliteration:BAAANQAECgYIDAABNQAECgkJHQAGAH4fAA==.',
Od='Odsw:BAAANQADCgMJAwAAAA==.',
Oe='Oenaa:BAAANQABCgQIBAAAAA==.',
Ol='Olivertwist:BAAANQAECgQICAABNQAECgkJHQAGAH4fAA==.',
On='Ontwou:BAAANQAECgUJDQAAAA==.',
Or='Orbz:BAABNQAECoEYAAILAAcKpCIjRQC7AgALAAcKpCIjRQC7AgAAAA==.Orcazm:BAAANQAECgEIAQAAAA==.',
Pa='Palyont:BAAANQADCgYIEAAAAA==.Pancakezebra:BAABNQAECoEYAAIVAAgKqBKbAwBSAgAVAAgKqBKbAwBSAgAAAA==.Parse:BAAANQAECgIIAwAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAAANQAECgYJEQAAAA==.',
Pi='Pikechu:BAAANQAECgQIBgAAAA==.Pinkskies:BAAANQAECgIIAgAAAA==.',
Pl='Pleasy:BAAANQAECgQIBwAAAA==.Plugtobacca:BAAANQADCgIJAgABNQAECgkJHAAKAIUiAA==.',
Po='Pocketchange:BAAANQAECgcIEwAAAA==.Pocketwatch:BAAANQAECgMIAwABNQAECgcIEwACAAAAAA==.',
Pr='Prayze:BAAANQADCgYIBgAAAA==.Preservation:BAAANQADCgIIAgABNQAECgYIEgACAAAAAA==.Promethêus:BAAANQAECgEIAQAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQAECgMJBQAAAA==.',
Qr='Qrz:BAAANQADCgMIAwAAAA==.',
Ra='Raavatu:BAAANQADCgIJAgAAAA==.',
Re='Relovan:BAAANQAECgQIBgAAAA==.Renothidan:BAABNQAECoEYAAIFAAgKzBVuTwAXAgAFAAgKzBVuTwAXAgAAAA==.Ret:BAAANQADCgcICQABNQAECggIGwASAMcjAA==.Reuben:BAAANQAECgEIAQAAAA==.Revin:BAAANQAECgQJDQAAAA==.Revrynth:BAABNQAECoEUAAQHAAcKBR83DwAQAgAHAAYKEx83DwAQAgAWAAQKvhU+DAD/AAADAAEK4hNQNwBLAAAAAA==.Rexorcist:BAAANQAECgUJCAAAAA==.',
Ri='Rimed:BAAANQAECgYJDwAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcIBwAAAA==.Rizzdolphler:BAABNQAECoEaAAMMAAkKJBqIEwDwAgAMAAkKJBqIEwDwAgAFAAMKpgW8+QBmAAAAAA==.',
['Rö']='Rönburgundy:BAABNQAECoEZAAIBAAgK5hktLgBnAgABAAgK5hktLgBnAgAAAA==.',
Sa='Sanako:BAAANQAECgQIBwAAAA==.Saneros:BAAANQAECgIIAgAAAA==.',
Sc='Scraggle:BAAANQADCgcJEQAAAA==.Scuffito:BAAANQAECgMIBAAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Setheron:BAAANQADCggJGQAAAA==.',
Sh='Shlea:BAABNQAECoEZAAIWAAgK0woOCACNAQAWAAgK0woOCACNAQAAAA==.Shley:BAAANQADCgYIBgABNQAECggIGQAWANMKAA==.',
Si='Silvanna:BAAANQADCggICAAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
So='Solendros:BAAANQAECgQIBAAAAA==.Sonoa:BAAANQAECgQJAwAAAA==.Sonthar:BAAANQADCgQJBAAAAA==.Sorlight:BAAANQADCgcICQAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAAANQAECgIIAgAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
St='Standarshh:BAAANQAECgYJDgAAAA==.Stevenz:BAAANQAECgUICgAAAA==.Stillflygon:BAAANQADCgUIBQAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAABNQAECoEWAAMKAAgKBhhGFABZAgAKAAgKpBZGFABZAgAXAAYKbA4sIACHAQAAAA==.Sugarbabi:BAAANQAECgcJEAAAAA==.Sugarshot:BAAANQADCgQJBAAAAA==.Sugartotem:BAAANQAECgIIAwAAAA==.Sunmere:BAAANQADCgUJBQAAAA==.',
Sw='Swiftwing:BAAANQADCgQJBAAAAA==.',
Sy='Sydarliia:BAAANQAECgYJEAAAAA==.Sylrianah:BAABNQAECoEYAAIUAAcKUAnBXABlAQAUAAcKUAnBXABlAQAAAA==.Sylveste:BAAANQAECgcJDAAAAA==.',
Ta='Tal:BAAANQAECggJAQABNQAECggJBwACAAAAAA==.Talridor:BAAANQADCgcIBgAAAA==.Tankhiskhan:BAAANQAECgUIDgAAAA==.',
Te='Tei:BAAANQADCgEIAQAAAA==.',
Th='Thannill:BAAANQAECgQJCQAAAA==.',
Ti='Tie:BAAANQAECgcIEwAAAA==.Tirala:BAAANQAECgEIAQAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Torzhu:BAAANQAECgUJDwAAAA==.Toy:BAAANQAECgcJCwABNQAFFAYIEQADAHAWAA==.',
Tr='Trauck:BAAANQAECgEIAQAAAA==.Travvy:BAACNQAFFIERAAMXAAcKCCEnAgDvAQAXAAUKzyAnAgDvAQAKAAIKlSGZBQDSAAA1AAQKgSAAAxcACQodJh4CAIYDABcACQpAIh4CAIYDAAoAAwr2ILE2ACYBAAAA.Trevmo:BAAANQAECgIIAgAAAA==.Trexin:BAAANQADCgMIAwAAAA==.',
Tz='Tzuyu:BAABNQAECoEYAAIOAAcKTSWRFAAAAwAOAAcKTSWRFAAAAwAAAA==.',
Ud='Uddershock:BAAANQADCggIDgAAAA==.',
Un='Unapologetic:BAAANQAECgIIAgABNQAECgYIEgACAAAAAA==.Unbreakabull:BAAANQAECgcICwAAAA==.Unver:BAAANQADCgYIBgAAAA==.',
Va='Vae:BAAANQAECgYJEQABNQAECgcIDAACAAAAAA==.Valka:BAAANQAECgEIAQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAAANQAECgQIBwAAAA==.Veyle:BAABNQAECoEYAAMKAAcK7yCeDgCjAgAKAAcK7yCeDgCjAgAXAAYKbx9yEwAYAgAAAA==.',
Vi='Viibryd:BAAANQADCgYIBgAAAA==.Vine:BAAANQADCgIJAgAAAA==.',
Vy='Vyndria:BAAANQADCgcIDQAAAA==.Vyran:BAAANQADCgIIAgAAAA==.',
Wa='Waypal:BAAANQADCggIFwAAAA==.',
We='Weashock:BAAANQADCgYIDAAAAA==.Weasy:BAAANQADCggICAAAAA==.',
Wi='Windfury:BAAANQAECgcJDAAAAA==.Wingzard:BAAANQAECgcJEwAAAA==.',
Xl='Xl:BAAANQAECggICwAAAA==.',
Ya='Yaitoopmfp:BAAANQAECgQJBQABNQAECggJGwAQAOwXAA==.Yao:BAAANQAECgYJEwAAAA==.Yasrena:BAAANQAECgUJBQAAAA==.',
Za='Zabara:BAAANQADCgYIBgABNQAECgUICgACAAAAAA==.Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAABNQAECoEYAAIDAAcKqBdBFQD9AQADAAcKqBdBFQD9AQAAAA==.Zaki:BAABNQAECoEaAAIYAAgKDxt4EACwAgAYAAgKDxt4EACwAgAAAA==.Zalujin:BAAANQABCgUIBAAAAA==.',
Ze='Zealot:BAAANQADCgEIAQAAAA==.Zeleria:BAAANQAECgIIAQAAAA==.Zerathis:BAAANQADCgEJAQAAAA==.',
Zi='Zinbek:BAAANQADCgUIBQAAAA==.Zip:BAAANQABCgYJBgAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zoo:BAAANQAECgIIAgAAAA==.Zorb:BAAANQAECgYJEwABNQAECgcICAACAAAAAA==.Zoshow:BAAANQAECgUJBQAAAA==.',
['Zõ']='Zõshow:BAAANQAECgMJAwAAAA==.',
['Ða']='Ðaredevil:BAAANQAECgcIDAAAAA==.',
['Ðp']='Ðp:BAAANQAECgcJCwAAAA==.',
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
