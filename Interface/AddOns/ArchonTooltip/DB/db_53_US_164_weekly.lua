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

local lookup = {'Priest-Shadow','Unknown-Unknown','Shaman-Restoration','Warrior-Arms','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','Hunter-BeastMastery','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Warrior-Protection','Mage-Arcane','Mage-Frost','Warlock-Demonology','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Shaman-Elemental','Druid-Restoration','Monk-Brewmaster','Warrior-Fury',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Adicia:BAAANQAECgQIBAAAAA==.',
Ae='Aedercy:BAAANQABCggIFgAAAA==.Aestel:BAAANQABCgYIBQAAAA==.',
Al='Alarus:BAAANQADCgQIAQAAAA==.Alexithorn:BAAANQABCgUIBQAAAA==.Allila:BAABNQAECoEXAAIBAAcKiB8LGABxAgABAAcKiB8LGABxAgAAAA==.Alynara:BAAANQADCgcIBwABNQAECgYIEQACAAAAAA==.',
Am='Ambrozyn:BAAANQADCgcICwAAAA==.',
An='Anarariellea:BAAANQADCggJDgAAAA==.',
Ap='Apalrapzz:BAAANQADCgIJAgABNQAECgUICAACAAAAAA==.',
Aq='Aqari:BAAANQAECgIIBAAAAA==.',
Ar='Araxiie:BAAANQADCgIIAgAAAA==.Ardrelar:BAAANQADCgcIGwAAAA==.',
As='Asila:BAAANQADCgUIBQAAAA==.Astraea:BAAANQADCggIGwABNQAECggIHwADAOIZAA==.',
At='Athika:BAAANQADCgUIBQAAAA==.',
Au='Auria:BAAANQAECgEIAQABNQAECgIIBAACAAAAAA==.Autumnal:BAAANQADCgQIBgAAAA==.',
Az='Azralia:BAAANQAECgcIDQAAAA==.',
Bb='Bbygee:BAAANQADCgUIBQAAAA==.',
Be='Benjamin:BAABNQAECoEXAAIEAAkKGg+/dAAWAgAEAAkKGg+/dAAWAgAAAA==.Beyblade:BAAANQADCgQIBgAAAA==.',
Bl='Blacksun:BAAANQAECggIAwAAAA==.Blazinember:BAABNQAECoEiAAIFAAgKURBRAgAKAgAFAAgKURBRAgAKAgAAAA==.Blockhead:BAAANQAECgIIAgAAAA==.',
Bo='Bolonmixto:BAABNQAECoEkAAMGAAkKlx/EBgAKAwAGAAkKeB/EBgAKAwAHAAIK4B1vcACZAAAAAA==.Boop:BAAANQAECgUICwABNQAECggIGAAIABQhAA==.Borghamer:BAAANQAECgIIAgAAAA==.Borimor:BAAANQADCgUICQABNQAECgkJFwAJAIARAA==.',
Br='Bromkin:BAAANQAECgIIAgAAAA==.',
['Bë']='Bëorn:BAAANQAECgYIBgABNQAECgkJFwAJAIARAA==.',
Ca='Calinor:BAAANQADCgYIGQAAAA==.Callihunt:BAAANQADCgYICAAAAA==.Calliopeh:BAAANQADCggIDwAAAA==.',
Ce='Cedriq:BAAANQAECgEIAgAAAA==.Ceran:BAAANQAECgUIEgAAAA==.Cereus:BAABNQAECoEbAAMKAAgK4x9sDADNAgAKAAgK4x9sDADNAgALAAQKIxLzJQDpAAAAAA==.',
Ch='Chaelenge:BAAANQAECgUIDQAAAA==.Chasatail:BAAANQADCgcICAAAAA==.Chyran:BAAANQAECgIIBgAAAA==.',
Co='Coldncrispy:BAAANQADCgYIDgAAAA==.Coloratura:BAABNQAECoEbAAIMAAcKViCMLQCSAgAMAAcKViCMLQCSAgAAAA==.',
Cr='Crimsonmoon:BAAANQADCggICAABNQAECggIGAAIABQhAA==.Crylessia:BAAANQAECgMIAwAAAA==.',
Da='Dagethon:BAAANQADCgUJEAAAAA==.Dandon:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Danfortesque:BAAANQADCgcIBwAAAA==.Danyah:BAAANQADCgUJBQABNQAECggIGwANAA0ZAA==.Darkshådow:BAAANQAECgEIAQAAAA==.',
De='Deathangels:BAAANQADCgQIBAAAAA==.Denvoker:BAAANQAECgEIAQAAAA==.Desdeanna:BAAANQABCgIIAgAAAA==.',
Di='Dissension:BAAANQAECgQIAwAAAA==.',
Do='Doubtfire:BAAANQAECgUICAAAAA==.',
Dr='Dragii:BAAANQADCgYIBgAAAA==.',
Ed='Edelia:BAAANQAECgYIDAABNQAECggIJwAMANAdAA==.',
El='Elek:BAAANQADCgEIAQAAAA==.',
Er='Eraessyr:BAAANQADCgQJBAAAAA==.',
Fa='Fabin:BAAANQADCgEIAQAAAA==.Faithfulness:BAAANQAECgQIBQAAAA==.Fangz:BAAANQAECgQICQAAAA==.',
Fr='Freakadeëk:BAAANQAECgEIAQAAAA==.Frierenn:BAABNQAECoEZAAMOAAcK7g+81AC3AQAOAAcK7g+81AC3AQAPAAEKqw4NQAA0AAAAAA==.Frosh:BAAANQAECgEIAQAAAA==.',
Gh='Ghouldottie:BAAANQADCgIIAgAAAA==.',
Gi='Gilidar:BAABNQAECoEZAAIEAAgK5x00PgC4AgAEAAgK5x00PgC4AgAAAA==.Gillarria:BAAANQADCgUIBQAAAA==.',
Gn='Gnomerdenis:BAAANQAECgEIAQAAAA==.',
Go='Goochiemon:BAAANQADCgcIDgAAAA==.',
Gr='Gravecrawler:BAAANQADCgIIAgAAAA==.Grimmberly:BAAANQAECgUIEQABNQAECgYIBwACAAAAAA==.Grimoire:BAAANQAECgYIBwAAAA==.',
Gu='Guthunnel:BAAANQADCggIDgAAAA==.Gutshadra:BAAANQAECgEIAQAAAA==.',
Ha='Haides:BAAANQADCgQIBAAAAA==.Hairybum:BAAANQABCgIIAgAAAA==.Halanji:BAAANQADCgUIBQAAAA==.Hannibow:BAAANQADCgQIBgAAAA==.',
He='Hellgrim:BAAANQADCgMIAQABNQAECgYIBwACAAAAAA==.',
Ho='Hoawatt:BAAANQADCggIEwAAAA==.Holynova:BAAANQAECgEIAQABNQAECgUIDgACAAAAAA==.Howlingfury:BAAANQABCgIIAgAAAA==.',
Hu='Huuch:BAAANQAECgYIDQAAAA==.',
Ig='Ignee:BAABNQAECoEbAAMNAAgKDRlEDQAzAgANAAgKDRlEDQAzAgAEAAMKCA6WCAGVAAAAAA==.Ignia:BAAANQAECgUIBQAAAA==.Igris:BAAANQADCggICAAAAA==.',
Ir='Iremoon:BAAANQAECgUIEgABNQAECggIIAAQAKsKAA==.',
Je='Jestyr:BAABNQAECoEXAAIRAAgKoyFpAwAIAwARAAgKoyFpAwAIAwAAAA==.',
Ji='Jiyao:BAABNQAECoEjAAMSAAgKtxhsGwA0AgASAAgKtxhsGwA0AgATAAMKVwXWOgBuAAAAAA==.',
Ka='Kaceya:BAAANQADCgYICAAAAA==.Kainarasa:BAAANQAECgYIBgABNQAECggIGAAIABQhAA==.Katarinea:BAAANQAECgUIDwAAAA==.',
Ke='Ketrus:BAAANQADCgQIBAABNQAECgUIBQACAAAAAA==.',
Kh='Khala:BAAANQAECgQIBgAAAA==.Khalessie:BAABNQAECoEZAAIUAAcK9hOkCAC/AQAUAAcK9hOkCAC/AQAAAA==.',
Ki='Killa:BAAANQAECgIIAgABNQAECgkJGgAEAFgZAA==.Killerfire:BAAANQAECgEIAQAAAA==.Killim:BAAANQADCgYICwAAAA==.',
Kl='Klorick:BAAANQAECgYICgABNQAECgkJFwAJAIARAA==.',
Ku='Kungfudru:BAAANQADCgQJCQAAAA==.',
Kw='Kwai:BAAANQADCgQIBQABNQAECgkJFwAJAIARAA==.',
Ky='Kyla:BAAANQAECgEIAQAAAA==.Kyomu:BAAANQADCggICAABNQAECggIGAAIABQhAA==.',
Le='Legio:BAAANQADCgQJBAAAAA==.',
Li='Lineofsight:BAAANQAECgQIDQAAAA==.Lipa:BAAANQADCgEIAQAAAA==.Liths:BAAANQAECgUIEgAAAA==.',
Lo='Loading:BAAANQAECgEIAQABNQAECggIHgAVALEUAA==.Lockdarkly:BAAANQAECgEIAQAAAA==.Loko:BAAANQADCgEIAQAAAA==.',
Lu='Lululuvely:BAAANQAECgQICwAAAA==.',
['Lí']='Lív:BAAANQADCgMIAwAAAA==.',
Ma='Machrona:BAAANQADCgUIBgAAAA==.Madelyn:BAAANQADCgUJBQAAAA==.Magecat:BAAANQAECgEIAQABNQAECgUIBQACAAAAAA==.Magejacob:BAAANQADCgYIDgAAAA==.Malena:BAEANQAECgQIBQAAAA==.Malendren:BAAANQABCgQIBAAAAA==.Margot:BAAANQADCgYIBgAAAA==.Mawhriccio:BAAANQADCggICgAAAA==.',
Mc='Mcdavé:BAAANQAECgUIEgAAAA==.',
Me='Meerclar:BAAANQAECgQIBgAAAA==.Melaila:BAABNQAECoEfAAIDAAgK4hlYOABWAgADAAgK4hlYOABWAgAAAA==.',
Mi='Micheal:BAAANQAECggICAAAAA==.Midir:BAAANQADCgUIBQAAAA==.Mistymay:BAAANQADCgYJCwAAAA==.',
Mo='Moldthinur:BAAANQAECgUIBQAAAA==.Mongrol:BAAANQAECgQIBgAAAA==.Monôpolyguy:BAAANQAECgMIBQAAAA==.Moonowl:BAAANQAECgEIAQAAAA==.',
Mu='Mummrakhan:BAAANQAECgEIBQAAAA==.Murraya:BAAANQADCgMIAwAAAA==.',
My='Mythdalkurim:BAAANQADCgUICgAAAA==.',
Na='Naniel:BAABNQAECoEjAAINAAkKeiI6AwBWAwANAAkKeiI6AwBWAwAAAA==.Nazgrefry:BAAANQAECgYIDgAAAA==.',
Ne='Neb:BAABNQAECoEjAAIQAAgKpxIHXwAYAgAQAAgKpxIHXwAYAgAAAA==.Necroy:BAAANQAECgQJCQAAAA==.',
Ni='Niccee:BAAANQAECgUIEgAAAA==.',
No='Noggindeez:BAAANQADCgIIAgABNQAECgcICQACAAAAAA==.Noodles:BAAANQAECgUIEQAAAA==.Nosebleeds:BAAANQADCggICgAAAA==.',
Nu='Numerotres:BAAANQADCgQIBAAAAA==.Numerouno:BAAANQAECgUIDgAAAA==.',
['Nî']='Nîtara:BAAANQADCgEIAQAAAA==.',
Om='Omegasupreme:BAAANQABCgIJAgAAAA==.',
Oo='Ookthron:BAAANQAECgUIEgAAAA==.',
Oz='Ozempic:BAAANQADCggIEQAAAA==.',
Pa='Pandi:BAAANQADCgcIBwAAAA==.Papasmurff:BAAANQADCgYIBwAAAA==.Parachute:BAAANQADCggIIAAAAA==.Parky:BAAANQADCgUICAAAAA==.',
Pe='Percival:BAAANQAECgUIEgAAAA==.',
Ph='Phreakadeek:BAAANQADCgcIDgABNQAECgIIBQACAAAAAA==.',
Pi='Pinheadgarry:BAAANQADCgIIAgAAAA==.Pizzaslice:BAABNQAECoEYAAIIAAgKFCHaPAC7AgAIAAgKFCHaPAC7AgAAAA==.',
Pr='Praxiscannon:BAAANQAECgUICAAAAA==.',
Pu='Pumpshire:BAAANQAECgcIDQAAAA==.',
Pw='Pwongo:BAABNQAECoEfAAIWAAYKhCOVFwBeAgAWAAYKhCOVFwBeAgAAAA==.',
Qt='Qt:BAABNQAECoEkAAIVAAkKqx6lIQDlAgAVAAkKqx6lIQDlAgAAAA==.',
Qu='Queue:BAAANQAECgEIAgAAAA==.Quilten:BAAANQAECgIIBAAAAA==.',
Ra='Raenii:BAAANQAECgUICAABNQAECggIJwAMANAdAA==.Ramoth:BAAANQAECgIIAgAAAA==.Razelda:BAAANQAECggIAgAAAA==.',
Rh='Rhodas:BAAANQADCggIIwABNQAECggIFwAEABYfAA==.',
Ri='Riandras:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.',
Ro='Roadwanderer:BAAANQAECgIIAgAAAA==.Robbiedrake:BAAANQAECgEIAQABNQAECggIIwAXAHQaAA==.Robbiemonk:BAABNQAECoEjAAIXAAgKdBrhCQBeAgAXAAgKdBrhCQBeAgAAAA==.Rodric:BAAANQAECgYIBwABNQAECgkJFwAJAIARAA==.',
Ru='Runetottem:BAAANQAECgUIDQAAAA==.',
Rx='Rxeight:BAAANQADCgQIBgAAAA==.',
Sa='Sakura:BAAANQADCgIIAgAAAA==.Samarii:BAAANQAECgEIAQAAAA==.Sannith:BAAANQAECgUIEgAAAA==.',
Sc='Scyllia:BAABNQAECoEjAAIBAAgKmxu1FwB0AgABAAgKmxu1FwB0AgAAAA==.Scârlett:BAEANQADCgUICAABNQAECgQIBQACAAAAAA==.',
Sh='Shadowklaw:BAAANQADCgMIAwAAAA==.Shamanoodles:BAAANQAECgYIDAABNQAECggIHwADAOIZAA==.Shespawn:BAAANQAECgEIAgAAAA==.Shurie:BAABNQAECoEXAAIJAAkKgBGJVABLAgAJAAkKgBGJVABLAgAAAA==.Shâdê:BAAANQAECgMJBAAAAA==.',
Sl='Slipperybop:BAABNQAECoEsAAIIAAkK8yGJHgAyAwAIAAkK8yGJHgAyAwABNQAECgQICQACAAAAAA==.Slugbow:BAAANQADCgUIBQAAAA==.',
Sn='Snakeshadow:BAAANQADCgcIBwAAAA==.Snazzlehorn:BAAANQAECgIIAgAAAA==.Snoroll:BAAANQAECgEIAQAAAA==.',
So='Soldanis:BAAANQABCgEIAQAAAA==.',
Sp='Spazoff:BAAANQADCggIEgAAAA==.Spyman:BAAANQADCgYICgAAAA==.',
Sq='Squissh:BAAANQAECgYICwABNQAECgkJFwAJAIARAA==.',
Sr='Srhubbabubba:BAAANQAECgQJCAABNQAECgUICgACAAAAAA==.',
St='Sternn:BAAANQADCgcIDQAAAA==.Straif:BAAANQAECgEIAQAAAA==.Strawberrÿ:BAABNQAECoEaAAIIAAgKsglCsgCBAQAIAAgKsglCsgCBAQAAAA==.',
Sw='Swolman:BAAANQADCgIIAgAAAA==.',
Sy='Syreithada:BAAANQADCgcICQAAAA==.',
Ta='Talathra:BAAANQAECgYIEQAAAA==.',
Te='Teddy:BAAANQAECgUIDgAAAA==.Tellah:BAAANQADCgQIBAABNQAECgkJIwADAPIhAA==.',
Th='Thegodofwar:BAABNQAECoEXAAIEAAgKFh+FOwDBAgAEAAgKFh+FOwDBAgAAAA==.Thân:BAAANQADCgYIDQAAAA==.',
Ti='Tivon:BAAANQAECgEJAQAAAA==.',
To='Tonksie:BAAANQABCgIIAgAAAA==.',
Tt='Ttonkkalos:BAAANQADCggICwAAAA==.',
Tw='Twomz:BAAANQADCgYIBgAAAA==.',
Um='Umi:BAAANQAECggICgAAAA==.',
Va='Varkbyte:BAAANQADCgUIBgAAAA==.Varock:BAAANQAECgIIAgABNQAECggIGAAIABQhAA==.',
Vi='Vindication:BAAANQAECgIIAwAAAA==.Viz:BAAANQADCggIGQAAAA==.',
Vr='Vraul:BAAANQAECgUIEgAAAA==.',
Vu='Vulpain:BAAANQADCgYIBgABNQAECggIGAAIABQhAA==.',
Vv='Vvnth:BAAANQADCgUIBQAAAA==.',
Wa='Washer:BAAANQADCgcIBwAAAA==.',
Wh='Whiteangel:BAAANQAECgEIAQAAAA==.',
Wi='Wickedgood:BAAANQADCgQIBQAAAA==.Willywallace:BAAANQABCgMIAwAAAA==.',
Wo='Wolfowl:BAAANQADCgYIGQAAAA==.',
Xa='Xaela:BAAANQAECgUIDgAAAA==.Xarous:BAAANQADCggICAABNQAECggIGAAIABQhAA==.',
Xi='Xiabal:BAAANQAECgUIEgAAAA==.',
Xw='Xweakling:BAAANQADCgYICAABNQAECggIGgAYABIYAA==.Xweekling:BAABNQAECoEaAAIYAAgKEhimCAAtAgAYAAgKEhimCAAtAgAAAA==.',
Yo='Yonnà:BAAANQAECgMIAwAAAA==.Yoshirou:BAAANQADCgIIAgAAAA==.Yourgrandma:BAAANQAECgQICwAAAA==.',
Yu='Yuxiong:BAAANQADCggIEAAAAA==.',
Ze='Zedra:BAEANQADCggIGAABNQAECgQIBQACAAAAAA==.Zedrâ:BAEANQADCggIDAABNQAECgQIBQACAAAAAA==.Zerostar:BAAANQAECgQIBgABNQAECgkJJgAJADsfAA==.Zevon:BAAANQADCgEIAQABNQAECgQIBgACAAAAAA==.',
['Ña']='Ñaman:BAAANQAECgEIAQAAAA==.',
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
