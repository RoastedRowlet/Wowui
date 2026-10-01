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

local lookup = {'Warlock-Destruction','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Evoker-Preservation','DeathKnight-Blood','Paladin-Retribution','Monk-Windwalker','Evoker-Devastation','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Shaman-Enhancement','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Arcane','Paladin-Holy','Shaman-Elemental','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Monk-Mistweaver','Priest-Holy','Hunter-Survival','Evoker-Augmentation','Rogue-Subtlety','Paladin-Protection','Druid-Balance',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abbpriest:BAAANQADCgYJBgABNQAECggJGQABAO4XAA==.Abruum:BAAANQADCgcIDAAAAA==.',
Ad='Admetus:BAAANQAECgcIDQAAAA==.Adobe:BAAANQADCggIFwAAAA==.',
Am='Amathal:BAAANQAECgcIDgAAAA==.',
An='Anderson:BAAANQADCgQIBAAAAA==.Ankheloios:BAAANQAECgUICgAAAA==.',
Ar='Arcanehonkey:BAAANQADCggICAAAAA==.Aredhela:BAAANQAECgYIEAAAAA==.Arias:BAAANQAECgEIAQAAAA==.Armsdealer:BAAANQADCgUIBQAAAA==.Arro:BAAANQAECgEIAQAAAA==.',
As='Ascending:BAAANQAECgQICAAAAA==.Asha:BAABNQAECoEXAAMCAAkKKRqcEgClAgACAAkKKRqcEgClAgADAAEKsQElKAEoAAAAAA==.Ashveil:BAAANQADCgQIBAABNQAECgUIEgAEAAAAAA==.Astrialynn:BAAANQADCgYIBwAAAA==.Astrulawa:BAAANQAECgIIAgAAAA==.',
At='Athrea:BAAANQAECgcIEwAAAA==.',
Ba='Barakah:BAAANQADCgIJAgAAAA==.Barnre:BAAANQAECgIIBAAAAA==.',
Bd='Bdssm:BAAANQAECgcIBwAAAA==.',
Be='Bearito:BAAANQAECgQICwAAAA==.Beefstick:BAAANQAECgYICQAAAA==.Beserkfury:BAAANQAECgYIDwAAAA==.',
Bi='Biercan:BAAANQAECgYIDAAAAA==.Bigcarl:BAAANQAECgEIAQAAAA==.Binke:BAAANQADCgQIBAAAAA==.Bittyboop:BAAANQADCgYICwABNQADCgcIGQAEAAAAAA==.Bittywhite:BAAANQADCgcIGQAAAA==.',
Bj='Bjarna:BAAANQAECgIIAwAAAA==.',
Bl='Blayze:BAAANQADCgUIBQAAAA==.Blinkytime:BAAANQAECgUIDQAAAA==.Bloodskull:BAAANQADCgEIAQAAAA==.Blúnt:BAAANQADCgQIBAAAAA==.',
Bo='Bobheals:BAAANQAECgYIDgAAAA==.Boibye:BAAANQAECgQICwAAAA==.Bolblock:BAAANQAECggIDwAAAA==.Bolo:BAABNQAECoEmAAIFAAkKwh3aBQAzAwAFAAkKwh3aBQAzAwAAAA==.Boostedww:BAAANQAECgQICwAAAA==.',
Br='Brambleclaw:BAABNQAECoEgAAIGAAgKPiBHEwDnAgAGAAgKPiBHEwDnAgAAAA==.Brayker:BAABNQAECoEgAAIHAAgKIB8dMQDGAgAHAAgKIB8dMQDGAgAAAA==.Breadoneal:BAAANQAECgYICwAAAA==.Brewed:BAAANQAECgMIBAAAAA==.Brynjamin:BAAANQAECgQICAAAAA==.Brüenor:BAAANQAECgMIBQAAAA==.',
Bu='Bubbi:BAAANQADCgEIAQAAAA==.Bukkorosuzo:BAAANQADCggIJgAAAA==.Burntroot:BAAANQAECgUIDAAAAA==.',
['Bá']='Bálor:BAAANQAECgEIAgAAAA==.',
Ca='Cacci:BAAANQADCgcIBwAAAA==.Caedwyn:BAAANQAECgUICQAAAA==.Camdakablam:BAAANQAECgcJEQAAAA==.Careadin:BAAANQADCgQIBAABNQAECgYIEgAEAAAAAA==.Careradin:BAAANQAECgYIEgAAAA==.Carereaper:BAAANQADCggIDAABNQAECgYIEgAEAAAAAA==.Cartilage:BAAANQAECgUIDAAAAA==.Cassieruth:BAAANQAECgMIAwAAAA==.Catalei:BAAANQAECgEIAQAAAA==.',
Ce='Centrest:BAAANQADCgYJCAAAAA==.',
Ch='Chebbles:BAAANQADCgIIAgABNQAECgUIDAAEAAAAAA==.Chillidan:BAAANQAECgMIAwABNQAECgkJIAAIALUgAA==.Chivi:BAAANQADCggJDgABNQAECgcIGgAJAAYfAA==.Chonkmonk:BAAANQADCgQIBAAAAA==.Chupacabrass:BAAANQAECgIIAgAAAA==.Chëbbles:BAAANQADCgQJBAABNQAECgUIDAAEAAAAAA==.',
Co='Colman:BAAANQADCggIJgAAAA==.Coorsbanquet:BAAANQAECgYIDwAAAA==.Coorsbite:BAAANQAECgEIAQABNQAECgYIDwAEAAAAAA==.Coorslight:BAAANQADCgYIBgABNQAECgYIDwAEAAAAAA==.',
Cr='Craccjar:BAAANQADCgYIBwAAAA==.Crackjar:BAAANQADCgMIAwAAAA==.Croc:BAAANQAECgYIEAAAAA==.Crudala:BAAANQADCgQIBAABNQAECgMIAgAEAAAAAA==.Crystle:BAAANQAECgQIBQAAAA==.',
Cs='Csyasha:BAAANQADCgcJBwABNQAECgEIAQAEAAAAAA==.',
Cu='Cubcadet:BAAANQAECgUICQAAAA==.',
Cy='Cybear:BAAANQAECgcIBwAAAA==.',
Da='Dalanora:BAABNQAECoEgAAQKAAgKQBykJgC0AgAKAAgKQBykJgC0AgABAAMK2Ra1OgDCAAALAAMKxRHZFACwAAAAAA==.Dapalyu:BAAANQAECgcIDQAAAA==.Davidx:BAAANQADCgQIBgAAAA==.',
De='Dekig:BAAANQAECgEIAQAAAA==.Demine:BAAANQAECgMIBAAAAA==.Detrazeral:BAAANQADCggIEAAAAA==.',
Di='Dico:BAAANQAECgEIAQABNQAFFAUIDgAMAJsZAA==.Dipper:BAABNQAECoEbAAIHAAgK7xZwZQARAgAHAAgK7xZwZQARAgAAAA==.',
Do='Dohan:BAAANQADCggIEAAAAA==.Dorìan:BAAANQADCgcIDgAAAA==.',
Dr='Draael:BAAANQADCgQJBAAAAA==.Draetona:BAAANQADCgQJBAAAAA==.',
Ee='Eeveeko:BAABNQAECoEaAAINAAgKIBm0CwB9AgANAAgKIBm0CwB9AgAAAA==.',
Ej='Ejavuday:BAAANQAECgcIEQAAAA==.',
En='Enerchi:BAABNQAECoEgAAIIAAkKtSDxBwAsAwAIAAkKtSDxBwAsAwAAAA==.',
Er='Erianar:BAAANQADCgEIAQAAAA==.Ervyne:BAAANQAECgcIDAAAAA==.',
Ev='Evera:BAAANQAECgUICQAAAA==.Evos:BAAANQADCgYJBgAAAA==.',
Ex='Exning:BAAANQADCggICAAAAA==.',
Fa='Fauci:BAAANQADCgIJAgABNQAFFAMIBwAOAPElAA==.',
Fe='Feihao:BAAANQADCgYIEwAAAA==.Feile:BAAANQAECgcIEgAAAA==.Feltree:BAAANQADCgQIBAAAAA==.',
Fl='Flashir:BAAANQADCgIIAgAAAA==.Flinzza:BAAANQAECgcIEwAAAA==.Flyknit:BAAANQAECgQIBwAAAA==.',
Fr='Fredthedh:BAABNQAECoEZAAMPAAgKoxR7HgAjAgAPAAgKmxR7HgAjAgAQAAMKxBTpWACyAAAAAA==.Fromtheback:BAAANQAECgIIAgAAAA==.Frosticals:BAABNQAECoEgAAIRAAkK3xyyPgDoAgARAAkK3xyyPgDoAgAAAA==.',
Ga='Gaashw:BAAANQABCgQIBAAAAA==.Ganandor:BAABNQAECoEXAAIOAAkKUBhNEgClAgAOAAkKUBhNEgClAgAAAA==.Gaulish:BAAANQADCgcIBwAAAA==.',
Ge='Geocide:BAAANQAECgYIEQAAAA==.Gethalyn:BAAANQAECgQJBAAAAA==.',
Gh='Ghume:BAAANQADCgYIDAAAAA==.',
Gi='Gianthippo:BAAANQADCgYJCgAAAA==.Gilf:BAAANQAECgcICAABNQAFFAUICQAKAC0YAA==.',
Go='Goursh:BAAANQAECgEIAQAAAA==.',
Gr='Grizzoul:BAAANQAECgMIBgAAAA==.Grreenry:BAAANQADCgIIAgAAAA==.Grumly:BAAANQAECgIIBAAAAA==.',
Ha='Hanswoloqued:BAABNQAECoEbAAIKAAkKSw8gTgAiAgAKAAkKSw8gTgAiAgAAAA==.Haxz:BAAANQADCgUJBQAAAA==.',
He='Healufast:BAAANQAECgYIEgAAAA==.Heck:BAAANQADCgYIBgAAAA==.Helstrom:BAAANQADCggIDgAAAA==.',
Hj='Hjalmar:BAAANQAECgYIEAAAAA==.',
Ho='Holycõw:BAAANQAECggICwAAAA==.Holysabeline:BAABNQAECoEgAAISAAgK2xTBOwA2AgASAAgK2xTBOwA2AgAAAA==.Hotpots:BAAANQAECggIEAAAAA==.',
Hu='Huchar:BAABNQAECoEbAAIMAAgKvxrjCQBVAgAMAAgKvxrjCQBVAgAAAA==.Humpf:BAAANQADCgEIAQAAAA==.Hunterpanda:BAAANQADCgYIBgAAAA==.',
Hy='Hydraxix:BAAANQADCggICAAAAA==.Hypnose:BAAANQADCggIDgAAAA==.',
Ic='Iceblade:BAAANQAECgcIBwAAAA==.',
Id='Idtrapdat:BAAANQADCggICAAAAA==.',
If='If:BAAANQADCgQIBAAAAA==.',
Ir='Ironßest:BAAANQABCgUICwAAAA==.',
Ja='Jadzi:BAAANQADCgYJCwAAAA==.Jaxxion:BAAANQADCgYIBgAAAA==.',
Je='Jensthyra:BAAANQABCgcICgAAAA==.Jessaiyan:BAAANQAECgcICQAAAA==.',
Jo='Jobo:BAAANQAECgYIDQAAAA==.Jobodot:BAAANQAECgYIBgAAAA==.',
Ju='Julaudette:BAAANQADCgcIBwAAAA==.Julzaria:BAAANQAECgQIBAAAAA==.Jurny:BAAANQAECgQICQAAAA==.',
Ka='Kahlandra:BAABNQAECoEgAAIRAAgK+BNnkwAWAgARAAgK+BNnkwAWAgAAAA==.Kaizer:BAABNQAECoEoAAITAAkKYBlzJQC1AgATAAkKYBlzJQC1AgAAAA==.Kandera:BAAANQADCgUIBQAAAA==.Karina:BAAANQADCgUJBQABNQAECggIIAADAD4jAA==.Karmelo:BAAANQADCgQICQAAAA==.',
Ke='Keizer:BAAANQAECgEIAQAAAA==.Keunen:BAAANQAECgQIBgAAAA==.Kevdawg:BAAANQADCgYIBgABNQADCggICAAEAAAAAA==.Kevlock:BAAANQADCgYIBgAAAA==.Keyzer:BAAANQAECgQIBQAAAA==.',
Kh='Khanjuror:BAAANQAECgEIAQAAAA==.Khornedog:BAAANQAECgYIEQAAAA==.Khrama:BAABNQAECoEbAAIGAAgK8COjCwA0AwAGAAgK8COjCwA0AwAAAA==.',
Kl='Kleenonean:BAACNQAFFIELAAIUAAQKhyOUBQCEAQAUAAQKhyOUBQCEAQA1AAQKgVoAAhQACQrHJhwAAA4EABQACQrHJhwAAA4EAAAA.',
Kr='Krackjarr:BAAANQAECgMIBAAAAA==.Kredor:BAAANQAECgIIBAAAAA==.',
Ku='Kungpowbeef:BAAANQAECgIIAgAAAA==.Kurzaan:BAAANQADCggICQAAAA==.Kuyaj:BAAANQADCgIIAgAAAA==.',
La='Lacio:BAABNQAECoEeAAIUAAgKPgSsNwATAQAUAAgKPgSsNwATAQAAAA==.Larune:BAAANQABCgEIAQAAAA==.',
Le='Lemonpepper:BAAANQAECgcIDgAAAA==.Lexxix:BAAANQADCgcIDAAAAA==.Leyru:BAAANQAECgUJDAAAAA==.',
Li='Liberos:BAAANQAECgMIBwAAAA==.Littlechiken:BAAANQADCgUIBQABNQAECgkJMAAGADkbAA==.',
Ln='Lninedkhack:BAAANQAECgUIEgAAAA==.',
Lo='Logaar:BAABNQAECoEfAAMSAAkK6g+VNgBNAgASAAkK6g+VNgBNAgAHAAQKzwX3CQGXAAAAAA==.',
Lu='Lubuu:BAAANQADCgUIBQAAAA==.Lucyfurrawr:BAAANQADCgUIBQAAAA==.Luxurix:BAAANQADCggIEQAAAA==.',
Ma='Magtao:BAAANQADCgYIDwAAAA==.Malexannius:BAAANQADCgYIDwAAAA==.Manastorm:BAAANQAECgQIBQAAAA==.Maplebrick:BAAANQABCgIIAgAAAA==.Mariangel:BAAANQADCgEIAQAAAA==.Marric:BAAANQAECggJCgAAAA==.',
Me='Medean:BAAANQADCggICAAAAA==.Megtallica:BAAANQAECgIIBAAAAA==.Mehunglow:BAAANQADCgUIBAAAAA==.Mensrea:BAAANQAECgUIBgAAAA==.Merrycold:BAABNQAECoEbAAMVAAgK7Bd7NQDzAQAVAAgK7Bd7NQDzAQAWAAUKDhDMTgD0AAAAAA==.',
Mf='Mfgirthquake:BAABNQAECoElAAMNAAgKgCR8AwBPAwANAAgKgCR8AwBPAwAXAAMKOx0YlQD7AAAAAA==.',
Mi='Miisty:BAAANQADCggIEgAAAA==.Mikklelee:BAAANQADCggIDwAAAA==.Mings:BAAANQAECgQICAAAAA==.Mistweaver:BAABNQAECoEdAAIYAAcKrSa6BQAXAwAYAAcKrSa6BQAXAwAAAA==.',
Mo='Mochi:BAAANQAECgcIEgAAAA==.Mochïi:BAAANQADCgIJBAABNQAFFAYIDwARAHMVAA==.Moghorva:BAAANQADCgcIBwAAAA==.Mojoe:BAAANQAECgUIDwAAAA==.Mommyswaggin:BAAANQAECgMIBAAAAA==.Moopster:BAABNQAECoEfAAIZAAgKViTyDQAtAwAZAAgKViTyDQAtAwAAAA==.Moopy:BAAANQAECgQIBAABNQAECggIHwAZAFYkAA==.Mootangclan:BAAANQAECgYIEgAAAA==.',
Na='Nanashi:BAAANQAECgcICQAAAA==.Nazgru:BAAANQADCgYIDAAAAA==.',
Ne='Neiko:BAABNQAECoEZAAIOAAkK1xVKFwByAgAOAAkK1xVKFwByAgAAAA==.Neptuneakis:BAAANQAECgUIDAAAAA==.Neptuno:BAAANQADCgEIAQABNQAECgUIDAAEAAAAAA==.Newcarsmell:BAAANQADCggIJgAAAA==.',
Ni='Niceknife:BAAANQADCggIDQAAAA==.Niquid:BAAANQAECgYIBgAAAA==.Niylea:BAAANQADCgUIBQABNQAECgcIEwAEAAAAAA==.',
No='Nobu:BAACNQAFFIEHAAIOAAMK8SU4BQBUAQAOAAMK8SU4BQBUAQA1AAQKgR8AAg4ACQqFIhwEAHADAA4ACQqFIhwEAHADAAAA.Noobhuntard:BAAANQADCggICAAAAA==.Norinari:BAACNQAFFIEJAAMKAAUKLRiMCwBNAQAKAAQKPheMCwBNAQABAAIKyhIzCgCqAAA1AAQKgSIABAsACApPI8ADAHECAAsABgomI8ADAHECAAoABgrhIXdBAE4CAAEAAwoKG0YqABQBAAAA.Notahealer:BAAANQAECgYIBgAAAA==.Noxloxes:BAAANQADCgIIAgAAAA==.',
Oa='Oakshre:BAABNQAECoEfAAIIAAgKNR23DwCtAgAIAAgKNR23DwCtAgAAAA==.',
Ob='Obliteration:BAAANQAECgYIDQABNQAECgkJIAAIALUgAA==.',
Od='Odsw:BAAANQADCgMJAwAAAA==.',
Oe='Oenaa:BAAANQABCgQIBAAAAA==.',
Ol='Olivertwist:BAAANQAECgQIDAABNQAECgkJIAAIALUgAA==.',
On='Ontwou:BAAANQAECgYIEwAAAA==.',
Or='Orbz:BAABNQAECoEfAAIRAAcKBCTmRwDPAgARAAcKBCTmRwDPAgAAAA==.Orcazm:BAAANQAECgEIAQAAAA==.',
Pa='Palathal:BAAANQAECgEIAQABNQAECgcIDgAEAAAAAA==.Palyont:BAAANQADCgcIFwAAAA==.Pancakezebra:BAABNQAECoEgAAIaAAkK0Bg6AgDyAgAaAAkK0Bg6AgDyAgAAAA==.Parse:BAAANQAECgIIAwAAAA==.',
Pe='Perdido:BAAANQADCgIIAgAAAA==.',
Ph='Phoenix:BAABNQAECoEbAAIHAAcKZhr+ZwAJAgAHAAcKZhr+ZwAJAgAAAA==.',
Pi='Pikechu:BAAANQAECgUICQAAAA==.Pinkskies:BAAANQAECgIIAgAAAA==.',
Pl='Pleasy:BAAANQAECgQIBwAAAA==.Plugtobacca:BAAANQADCgIJAgABNQAFFAMIBwAOAPElAA==.',
Po='Pocketchange:BAABNQAECoEaAAMXAAgKixWfSgDoAQAXAAgKixWfSgDoAQATAAUK5BUdfgBTAQAAAA==.Pocketwatch:BAAANQAECgQIBwABNQAECggIGgAXAIsVAA==.',
Pr='Prayze:BAAANQADCgYIBgAAAA==.Preservation:BAAANQADCgIIAgABNQAECgcIHQAYAK0mAA==.Promethêus:BAAANQAECgEIAQAAAA==.',
Pu='Purefriction:BAAANQADCgYICQAAAA==.Purehate:BAAANQAECgQICQAAAA==.',
Qr='Qrz:BAAANQADCgMIAwAAAA==.',
Re='Relovan:BAAANQAECgYICgAAAA==.Renothidan:BAABNQAECoEaAAIHAAkKNxUqWAA6AgAHAAkKNxUqWAA6AgAAAA==.Ret:BAAANQADCgcICQABNQAECggIJQANAIAkAA==.Reuben:BAAANQAECgEIAQAAAA==.Revin:BAAANQAECgUIDgAAAA==.Revrynth:BAABNQAECoEaAAQJAAcKBh8NDABzAgAJAAcKBh8NDABzAgAbAAQKvhUNDwDwAAAFAAEK4hM3PwBIAAAAAA==.Rexorcist:BAAANQAECgYICQAAAA==.',
Ri='Rimed:BAABNQAECoEXAAIRAAcK7AxXygCgAQARAAcK7AxXygCgAQAAAA==.Rippèd:BAAANQADCgYIBgAAAA==.Rithcice:BAAANQADCgcIBwAAAA==.Rizzard:BAAANQADCgYIBgAAAA==.Rizzdolphler:BAABNQAECoEeAAMSAAkKJBq7GQDlAgASAAkKJBq7GQDlAgAHAAMKpgWOKwFaAAAAAA==.',
['Rö']='Rönburgundy:BAABNQAECoEgAAIKAAgK5hlXQABRAgAKAAgK5hlXQABRAgAAAA==.',
Sa='Sanako:BAAANQAECgcIDgAAAA==.Saneros:BAAANQAECgIIAgAAAA==.',
Sc='Scraggle:BAAANQAECgEIAQAAAA==.Scuffito:BAAANQAECgMIBAAAAA==.',
Sd='Sdh:BAAANQADCgEIAQAAAA==.',
Se='Seasondpally:BAAANQADCgcIBwAAAA==.Setheron:BAAANQADCggIIQAAAA==.',
Sh='Shlea:BAABNQAECoEZAAIbAAgK0woiCgB5AQAbAAgK0woiCgB5AQAAAA==.Shley:BAAANQADCgYIBgABNQAECggIGQAbANMKAA==.',
Si='Silvanna:BAAANQADCggICgAAAA==.Sivi:BAAANQAECgIIAgAAAA==.',
Sl='Slinkstir:BAAANQADCgYIBgAAAA==.',
So='Solendros:BAAANQAECgQIBAAAAA==.Sonoa:BAAANQAECgYIBwAAAA==.Sonthar:BAAANQADCgQJBAAAAA==.Sorix:BAAANQADCgIIAgAAAA==.Sorlight:BAAANQAECgUIBAAAAA==.Soulelf:BAAANQADCgEIAQAAAA==.Sourpets:BAAANQAECgUIBwAAAA==.Sourwords:BAAANQAECgEIAQAAAA==.',
St='Standarshh:BAABNQAECoEXAAIDAAkK+RUYMQCYAgADAAkK+RUYMQCYAgAAAA==.Stevenz:BAAANQAECgcIEQAAAA==.Stillflygon:BAAANQADCgYICQAAAA==.Stormcare:BAAANQADCgUIBQAAAA==.',
Su='Subtle:BAABNQAECoEfAAMOAAgKKBqwFQCCAgAOAAgK1hmwFQCCAgAcAAYKbA4lJAB8AQAAAA==.Sugarbabi:BAAANQAECgcJEAAAAA==.Sugarrush:BAAANQADCggICAAAAA==.Sugarshot:BAAANQAECgIIAgAAAA==.Sugartotem:BAAANQAECgIIBAAAAA==.Sunmere:BAAANQADCgUJBQAAAA==.',
Sw='Swiftwing:BAAANQADCgQJBAAAAA==.',
Sy='Sydarliia:BAAANQAECgYIEAAAAA==.Sylrianah:BAABNQAECoEgAAIZAAgKEA5uVQDHAQAZAAgKEA5uVQDHAQAAAA==.Sylveste:BAAANQAFFAEIAQAAAA==.',
Ta='Tal:BAAANQAECggIBwABNQAECggICwAEAAAAAA==.Talridor:BAAANQADCgcIBgAAAA==.Tankhiskhan:BAAANQAECgYIEAAAAA==.',
Te='Tei:BAAANQADCgEIAQAAAA==.Terily:BAAANQADCgQIAwAAAA==.',
Th='Thannill:BAAANQAECgYIDQAAAA==.',
Ti='Ticktoklock:BAAANQADCgIIAgAAAA==.Tie:BAABNQAECoEYAAIdAAcK9hfoGADXAQAdAAcK9hfoGADXAQAAAA==.Tirala:BAAANQAECgcICAAAAA==.',
To='Tomari:BAAANQABCgEIAQAAAA==.Torzhu:BAAANQAECgUIEwAAAA==.Toy:BAAANQAECgcIDAABNQAFFAYIEQAFAHAWAA==.',
Tr='Trauck:BAAANQAECgEIAQAAAA==.Travvy:BAACNQAFFIEYAAMcAAcKjSEyAwDjAQAcAAUKiiEyAwDjAQAOAAIKlSFSCQDJAAA1AAQKgSEAAxwACQojJmICAIMDABwACQpGImICAIMDAA4AAwr2IGlFACEBAAAA.Trevmo:BAAANQAECgcICQAAAA==.Trexin:BAAANQAECgEIAQAAAA==.',
Tu='Turaylon:BAAANQADCgIIAgAAAA==.',
Tz='Tzuyu:BAABNQAECoEgAAMDAAgKPiMoEAA9AwADAAgKPiMoEAA9AwACAAEKIxE5aAA7AAAAAA==.',
Ud='Uddershock:BAAANQADCggIDgAAAA==.',
Un='Unapologetic:BAAANQAECgIIAgABNQAECgcIHQAYAK0mAA==.Unbreakabull:BAAANQAECgcIDgAAAA==.Unver:BAAANQADCgYIBgAAAA==.',
Va='Vae:BAAANQAECgYJEQABNQAECggIEwAEAAAAAA==.Valka:BAAANQAECgEIAQAAAA==.',
Ve='Veldtt:BAAANQADCgIIAgAAAA==.Velera:BAAANQAECgUICAAAAA==.Veyle:BAABNQAECoEgAAMOAAgKeCO0BgA8AwAOAAgKeCO0BgA8AwAcAAYKbx8AFwAEAgAAAA==.',
Vi='Viibryd:BAAANQADCgYIBgAAAA==.Vine:BAAANQADCgIIAgAAAA==.',
Vy='Vyndria:BAAANQADCgcIDQAAAA==.Vynstus:BAAANQADCggICAAAAA==.Vyran:BAAANQADCgIIAgAAAA==.',
Wa='Waypal:BAAANQADCggIFwAAAA==.',
We='Weashock:BAAANQADCgYIDAAAAA==.Weasy:BAAANQADCggICAAAAA==.',
Wi='Windfury:BAAANQAECgcIEQAAAA==.Wingzard:BAABNQAECoEWAAIRAAcKcxP5ogDzAQARAAcKcxP5ogDzAQAAAA==.',
Wo='Wowdudesame:BAAANQAECgYIBwABNQAECggIJQANAIAkAA==.',
Xl='Xl:BAAANQAFFAEIAQAAAA==.',
Ya='Yaitoopmfp:BAAANQAECggIDQABNQAECggJGwAVAOwXAA==.Yao:BAABNQAECoEfAAIGAAgKTx3fHQCNAgAGAAgKTx3fHQCNAgAAAA==.Yasrena:BAAANQAECgUICgAAAA==.',
Za='Zabara:BAAANQADCgYIBgABNQAECgYIEAAEAAAAAA==.Zair:BAAANQADCgUIBQAAAA==.Zakaraki:BAABNQAECoEgAAMJAAgKxxrbCgCQAgAJAAgKxxrbCgCQAgAFAAcKqBcKGQD0AQAAAA==.Zaki:BAABNQAECoEcAAIPAAkKXBovDwDXAgAPAAkKXBovDwDXAgAAAA==.Zalujin:BAAANQABCgUIBAAAAA==.',
Ze='Zealot:BAAANQAECgUIBQAAAA==.Zeleria:BAAANQAECgMIAgAAAA==.Zerathis:BAAANQADCgEJAQAAAA==.',
Zi='Zinbek:BAAANQADCgUIBQAAAA==.Zip:BAAANQABCgYJBgAAAA==.Zipstin:BAAANQAECgEIAQAAAA==.',
Zo='Zoo:BAAANQAECgIIAgAAAA==.Zorb:BAABNQAECoEeAAIeAAgKPh3rGgDCAgAeAAgKPh3rGgDCAgAAAA==.Zoshow:BAAANQAECgUIBgAAAA==.',
['Zõ']='Zõshow:BAAANQAECgMJAwAAAA==.',
['Ða']='Ðaredevil:BAAANQAECggIEwAAAA==.',
['Ðp']='Ðp:BAAANQAECgcIEQAAAA==.',
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
