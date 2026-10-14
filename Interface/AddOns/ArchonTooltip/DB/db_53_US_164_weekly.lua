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

local lookup = {'Priest-Shadow','Unknown-Unknown','Shaman-Restoration','Warrior-Arms','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','Hunter-BeastMastery','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Warrior-Protection','Mage-Arcane','Mage-Frost','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Druid-Guardian','Shaman-Elemental','Hunter-Survival','Druid-Restoration','Monk-Brewmaster','DemonHunter-Devourer','Druid-Balance','Warrior-Fury',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adicia:BAAANQAECgUICQAAAA==.',
Ae='Aedercy:BAAANQABCggIFgAAAA==.Aestel:BAAANQABCgYIBQAAAA==.',
Al='Alarus:BAAANQADCgQIAQAAAA==.Alexithorn:BAAANQABCgUIBQAAAA==.Allila:BAABNQAECn8fAAIBAAgKRCHiDgABAwABAAgKRCHiDgABAwAAAA==.Alynara:BAAANQADCgcIBwABNQAECgYIEQACAAAAAA==.',
Am='Ambrozyn:BAAANQAECgEIAQAAAA==.',
An='Anarariellea:BAAANQADCggJDgAAAA==.',
Ap='Apalrapzz:BAAANQADCgIJAgABNQAECgUIDAACAAAAAA==.',
Aq='Aqari:BAAANQAECgMIBwAAAA==.',
Ar='Araxiie:BAAANQADCgIIAgAAAA==.Ardrelar:BAAANQAECgEIAQAAAA==.',
As='Asila:BAAANQADCgUIBQAAAA==.Astraea:BAAANQADCggIGwABNQAECggIJwADAM8dAA==.',
At='Athika:BAAANQADCgUIBQAAAA==.',
Au='Auria:BAAANQAECgIIAwABNQAECgMIBwACAAAAAA==.Autumnal:BAAANQADCgQIBgAAAA==.',
Az='Azralia:BAAANQAECgYIEwAAAA==.',
Bb='Bbygee:BAAANQADCgUIBQAAAA==.',
Be='Benjamin:BAABNQAECn8aAAIEAAkK9A8kfAAhAgAEAAkK9A8kfAAhAgAAAA==.Beyblade:BAAANQADCgQIBgAAAA==.',
Bl='Blacksun:BAAANQAECggIAwAAAA==.Blazinember:BAABNQAECn8iAAIFAAgKlxDLAgD7AQAFAAgKlxDLAgD7AQAAAA==.Blockhead:BAAANQAECgIIAgAAAA==.',
Bo='Bolonmixto:BAABNQAECn8mAAMGAAkKSyH5BgANAwAGAAkKIyH5BgANAwAHAAIK4B0QhQCTAAAAAA==.Boop:BAAANQAECgYIEQABNQAECggIIQAIAI4gAA==.Borghamer:BAAANQAECgIIAgAAAA==.Borimor:BAAANQADCgUICQABNQAECgkJGQAJAGkSAA==.',
Br='Brendee:BAAANQADCgcIBwAAAA==.Bromkin:BAAANQAECgIIAgAAAA==.',
['Bë']='Bëorn:BAAANQAECgYIBgABNQAECgkJGQAJAGkSAA==.',
Ca='Calinor:BAAANQAECgEIAQAAAA==.Callihunt:BAAANQADCgYICAAAAA==.Calliopeh:BAAANQADCggIDwAAAA==.',
Ce='Cedriq:BAAANQAECgEIAgAAAA==.Ceran:BAAANQAECgYIEwAAAA==.Cereus:BAABNQAECn8eAAMKAAkKTx/ZCAAUAwAKAAkKTx/ZCAAUAwALAAQKvxHJKADlAAAAAA==.',
Ch='Chaelenge:BAAANQAECgYIDgAAAA==.Chasatail:BAAANQADCgcICAAAAA==.Chyran:BAAANQAECgQICgAAAA==.',
Co='Coldncrispy:BAAANQADCgcIFQAAAA==.Coloratura:BAABNQAECn8bAAIMAAcKViDKNwCGAgAMAAcKViDKNwCGAgAAAA==.',
Cr='Crimsonmoon:BAAANQADCggICAABNQAECggIIQAIAI4gAA==.Crylessia:BAAANQAECgMIAwAAAA==.',
Da='Dagethon:BAAANQADCgUJEAAAAA==.Dandon:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Danfortesque:BAAANQADCgcIBwAAAA==.Danyah:BAAANQADCgUJBQABNQAECgkJHgANACIZAA==.Darkshådow:BAAANQAECgEIAQAAAA==.Daromiciah:BAAANQADCgYIBgAAAA==.',
De='Deathangels:BAAANQADCgQIBAAAAA==.Deftdirk:BAAANQADCgYIBgAAAA==.Denvoker:BAAANQAECgEIAQAAAA==.Desdeanna:BAAANQABCgIIAgAAAA==.',
Di='Dissension:BAAANQAECgQIAwAAAA==.',
Do='Doubtfire:BAAANQAECgUIDAAAAA==.',
Dr='Dragii:BAAANQADCgYIBgAAAA==.',
Ed='Edelia:BAAANQAECgYIDAABNQAECggILwAMAIogAA==.',
Er='Eraessyr:BAAANQADCgQJBAAAAA==.',
Fa='Fabin:BAAANQADCgEIAQAAAA==.Faithfulness:BAAANQAECgQIBQAAAA==.Fangz:BAAANQAECgQIDQAAAA==.',
Fr='Freakadeëk:BAAANQAECgEIAQAAAA==.Frierenn:BAABNQAECn8hAAMOAAgK8g9+wAABAgAOAAgK8g9+wAABAgAPAAEKAADcRgA0AAAAAA==.Frosh:BAAANQAECgEIAQAAAA==.',
Gh='Ghouldottie:BAAANQADCgIIAgAAAA==.',
Gi='Gilidar:BAABNQAECn8hAAIEAAgKWSHGNgDlAgAEAAgKWSHGNgDlAgAAAA==.Gillarria:BAAANQADCgUIBQAAAA==.',
Gn='Gnomerdenis:BAAANQAECgEIAQAAAA==.',
Go='Goochiemon:BAAANQAECgMIAwAAAA==.',
Gr='Grimmberly:BAAANQAECgUIEQABNQAECgcIDgACAAAAAA==.Grimoire:BAAANQAECgcIDgAAAA==.Gronna:BAAANQADCgYIBgABNQAECggIHwABAEQhAA==.',
Gu='Guthunnel:BAAANQADCggIDgAAAA==.Gutshadra:BAAANQAECgEIAQAAAA==.',
Ha='Haides:BAAANQADCgQIBAAAAA==.Hairybum:BAAANQABCgIIAgAAAA==.Halanji:BAAANQADCgUIBQAAAA==.Hannibow:BAAANQADCgQIBgAAAA==.',
He='Hellgrim:BAAANQADCgMIAQABNQAECgcIDgACAAAAAA==.',
Ho='Hoawatt:BAAANQADCggIEwAAAA==.Holynova:BAAANQAECgEIAQABNQAECgcIFgAQAMQXAA==.Howlingfury:BAAANQABCgIIAgAAAA==.',
Hu='Huuch:BAAANQAECgcIDwAAAA==.',
Ig='Ignee:BAABNQAECn8eAAMNAAkKIhnuCwB3AgANAAkKIhnuCwB3AgAEAAMK9gqEIQGOAAAAAA==.Ignia:BAAANQAECggICQAAAA==.Igris:BAAANQADCggICAAAAA==.',
Ir='Iremoon:BAABNQAECn8bAAMRAAcKyQrbfgAdAQARAAYKOgzbfgAdAQASAAMKFgRuqgB3AAABNQAECggIIgATALELAA==.',
Je='Jestyr:BAABNQAECn8XAAIUAAgK9CKNBAD4AgAUAAgK9CKNBAD4AgAAAA==.',
Ji='Jimba:BAAANQADCgQIBAAAAA==.Jiyao:BAABNQAECn8jAAMVAAgKBBr8IAAgAgAVAAgKBBr8IAAgAgAWAAMKVwWeQABtAAAAAA==.',
Ka='Kaceya:BAAANQADCgYICAAAAA==.Kainarasa:BAAANQAECgYIBgABNQAECggIIQAIAI4gAA==.Katarinea:BAAANQAECgYIEAAAAA==.',
Ke='Ketrus:BAAANQADCgQIBAABNQAECggICQACAAAAAA==.',
Kh='Khala:BAAANQAECgQICQAAAA==.Khalessie:BAABNQAECn8hAAIXAAgK5hIRCADoAQAXAAgK5hIRCADoAQAAAA==.',
Ki='Killa:BAAANQAECgIIAgABNQAECgkJHAAEAFsZAA==.Killerfire:BAAANQAECgEIAQAAAA==.Killim:BAAANQADCgYICwAAAA==.',
Kl='Klorick:BAAANQAECgYICgABNQAECgkJGQAJAGkSAA==.',
Kr='Krillian:BAAANQABCgUIBQAAAA==.Krissa:BAAANQADCgcIBwAAAA==.',
Ku='Kungfudru:BAAANQADCgQJCQAAAA==.',
Kw='Kwai:BAAANQADCgQIBQABNQAECgkJGQAJAGkSAA==.',
Ky='Kyla:BAAANQAECgQIBQAAAA==.Kyomu:BAAANQADCggICAABNQAECggIIQAIAI4gAA==.',
Le='Legio:BAAANQADCgQJBAAAAA==.',
Li='Lineofsight:BAAANQAECgUIEgAAAA==.Lipa:BAAANQADCgEIAQAAAA==.Liths:BAABNQAECn8bAAIUAAcKYxBVEwBzAQAUAAcKYxBVEwBzAQAAAA==.',
Lo='Loading:BAAANQAECgEIAQABNQAECggIJgAYAGojAA==.Lockdarkly:BAAANQAECgEIAQAAAA==.Loko:BAAANQADCgEIAQAAAA==.',
Lu='Lululuvely:BAAANQAECgQICwAAAA==.',
['Lí']='Lív:BAAANQAECgMIAwAAAA==.',
Ma='Machrona:BAAANQADCgUIBgAAAA==.Madelyn:BAAANQADCgUJBQAAAA==.Magecat:BAAANQAECgEIAQABNQAECggICQACAAAAAA==.Magejacob:BAAANQADCgYIDgAAAA==.Malena:BAEANQAECgYICQAAAA==.Malendren:BAAANQABCgQIBAAAAA==.Margot:BAAANQADCgYIBgAAAA==.Marksmann:BAAANQADCgYIBQAAAA==.Mawhriccio:BAAANQADCggICgAAAA==.',
Mc='Mcdavé:BAABNQAECn8bAAIZAAcKOgxJjQB/AQAZAAcKOgxJjQB/AQAAAA==.',
Me='Meerclar:BAAANQAECgQIBgAAAA==.Melaila:BAABNQAECn8nAAIDAAgKzx32LQCoAgADAAgKzx32LQCoAgAAAA==.Melysithea:BAAANQAECgcIBwABNQAECggIJwADAM8dAA==.',
Mi='Micheal:BAAANQAECggICAAAAA==.Midir:BAAANQAECgEIAQAAAA==.Mistymay:BAAANQADCgYJCwAAAA==.Miñitañk:BAAANQAECgUIBQAAAA==.',
Mo='Moldthinur:BAAANQAECgUICAAAAA==.Mongrol:BAAANQAECgQICQAAAA==.Monôpolyguy:BAAANQAECgMIBwAAAA==.Moonowl:BAAANQAECgEIAQAAAA==.',
Mu='Mummrakhan:BAAANQAECgQIDQAAAA==.Murraya:BAAANQADCgMIAwAAAA==.',
My='Mythdalkurim:BAAANQADCgUICgAAAA==.',
Na='Naniel:BAABNQAECn8mAAINAAkKayIPBABOAwANAAkKayIPBABOAwAAAA==.Nazgrefry:BAAANQAECgYIDgAAAA==.',
Ne='Neb:BAABNQAECn8jAAITAAgKSxOqcwACAgATAAgKSxOqcwACAgAAAA==.Necroy:BAAANQAECgQJCQAAAA==.',
Ni='Niccee:BAAANQAECgYIEwAAAA==.',
No='Noggindeez:BAAANQADCgIIAgABNQAECgkJGAAZAGgfAA==.Noodles:BAAANQAECgUIEQAAAA==.Nosebleeds:BAAANQAECgIIAgAAAA==.',
Nu='Numerotres:BAAANQADCgQIBAAAAA==.Numerouno:BAABNQAECn8WAAMQAAcKxBd9gwCMAQAQAAYKLxZ9gwCMAQAIAAIKywTFfQFVAAAAAA==.',
['Nî']='Nîtara:BAAANQADCgEIAQAAAA==.',
Om='Omegasupreme:BAAANQABCgIJAgAAAA==.',
Oo='Ookthron:BAABNQAECn8ZAAMEAAcKBRj0kgDoAQAEAAcKBRj0kgDoAQANAAMKuxJNNACNAAAAAA==.',
Oz='Ozempic:BAAANQADCggIFQAAAA==.',
Pa='Pandi:BAAANQAECgEIAQAAAA==.Papasmurff:BAAANQAECgIIAgAAAA==.Parachute:BAAANQAECgUIBwAAAA==.Parky:BAAANQADCgUICAAAAA==.',
Pe='Percival:BAAANQAECgYIEwAAAA==.',
Ph='Phreakadeek:BAAANQADCgcIDgABNQAECgYIFQAaAPsVAA==.',
Pi='Pinheadgarry:BAAANQADCgIIAgAAAA==.Pizzaslice:BAABNQAECn8hAAIIAAgKjiB2LwAJAwAIAAgKjiB2LwAJAwAAAA==.',
Pr='Praxiscannon:BAAANQAECgUICQAAAA==.',
Pu='Pumpshire:BAAANQAECgcIEwAAAA==.',
Pw='Pwongo:BAABNQAECn8nAAIbAAcKwiI1EgC7AgAbAAcKwiI1EgC7AgAAAA==.',
Qt='Qt:BAACNQAFFH8GAAIZAAIKsha0IACoAAAZAAIKsha0IACoAAA1AAQKfyUAAhkACQr9IPskAO8CABkACQr9IPskAO8CAAAA.',
Qu='Queue:BAAANQAECgMIBQAAAA==.Quilten:BAAANQAECgQICAAAAA==.',
Ra='Raenii:BAAANQAECggIEAABNQAECggILwAMAIogAA==.Ramoth:BAAANQAECgIIAgAAAA==.Razelda:BAAANQAECggIAgAAAA==.',
Rh='Rhodas:BAAANQADCggIIwABNQAECggIHQAEAHohAA==.',
Ri='Riandras:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.',
Ro='Roadwanderer:BAAANQAECgIIAgAAAA==.Robbiedrake:BAAANQAECgEIAQABNQAECggIKgAcAIYaAA==.Robbiemonk:BAABNQAECn8qAAIcAAgKhhrfCgBgAgAcAAgKhhrfCgBgAgAAAA==.Rodric:BAAANQAECgYIBwABNQAECgkJGQAJAGkSAA==.',
Ru='Runetottem:BAAANQAECgYIDgAAAA==.',
Rx='Rxeight:BAAANQADCgYIDAAAAA==.',
Sa='Sakura:BAAANQADCgIIAgAAAA==.Samarii:BAAANQAECgEIAQAAAA==.Sannith:BAABNQAECn8bAAMOAAcKZBZ/yQDwAQAOAAcKKhR/yQDwAQAPAAEKlh6NQgA9AAAAAA==.',
Sc='Scyllia:BAABNQAECn8mAAIBAAkKwBj5FgCgAgABAAkKwBj5FgCgAgAAAA==.Scârlett:BAEANQADCgUICAABNQAECgYICQACAAAAAA==.',
Sh='Shadowklaw:BAAANQADCgMIBAAAAA==.Shamanoodles:BAAANQAECgYIDAABNQAECggIJwADAM8dAA==.Shespawn:BAAANQAECgQIBgAAAA==.Shurie:BAABNQAECn8ZAAIJAAkKaRLBYQBQAgAJAAkKaRLBYQBQAgAAAA==.Shâdê:BAAANQAECgMJBAAAAA==.',
Sl='Slipperybop:BAABNQAECn80AAIIAAkKjyHEKwAWAwAIAAkKjyHEKwAWAwABNQAECgQICQACAAAAAA==.Slugbow:BAAANQADCgUIBQAAAA==.',
Sn='Snakeshadow:BAAANQADCgcIBwAAAA==.Snazzlehorn:BAAANQAECgIIAgAAAA==.Snoroll:BAAANQAECgEIAQAAAA==.',
So='Soldanis:BAAANQABCgEIAQAAAA==.',
Sp='Spazoff:BAAANQAECgEIAQAAAA==.Spyman:BAAANQADCgYICgAAAA==.',
Sq='Squissh:BAAANQAECgYIEAABNQAECgkJGQAJAGkSAA==.',
Sr='Srhubbabubba:BAAANQAECgQICAABNQAECgYIEAACAAAAAA==.',
St='Sternn:BAAANQAECgIIAgAAAA==.Straif:BAAANQAECgQIBQAAAA==.Strawberrÿ:BAABNQAECn8aAAIIAAgK1wmQzwB2AQAIAAgK1wmQzwB2AQAAAA==.',
Sw='Swolman:BAAANQADCgIIAgAAAA==.',
Sy='Syreithada:BAAANQADCgcICQAAAA==.',
Ta='Talathra:BAAANQAECgYIEQAAAA==.',
Te='Teddy:BAABNQAECn8WAAIYAAcK7hXvHAC0AQAYAAcK7hXvHAC0AQAAAA==.Tellah:BAAANQADCgQIBAABNQAECgkJJQADAL4iAA==.',
Th='Thegodofwar:BAABNQAECn8dAAIEAAgKeiFDPQDQAgAEAAgKeiFDPQDQAgAAAA==.Thân:BAAANQAECgEIAQAAAA==.',
Ti='Tivon:BAAANQAECgEJAQAAAA==.',
To='Tonksie:BAAANQABCgIIAgAAAA==.',
Tt='Ttonkkalos:BAAANQAECgQIBAAAAA==.',
Tw='Twomz:BAAANQADCgYIBgAAAA==.',
Um='Um:BAAANQADCgIIAgABNQAECggIJgAYAGojAA==.Umi:BAAANQAECggICgAAAA==.',
Va='Varkbyte:BAAANQADCgUIBgAAAA==.Varock:BAAANQAECgIIAgABNQAECggIIQAIAI4gAA==.',
Vi='Vindication:BAAANQAECgMIBQAAAA==.Viz:BAAANQADCggIIAAAAA==.',
Vr='Vraul:BAABNQAECn8WAAIEAAcKtRMrqAC0AQAEAAcKtRMrqAC0AQAAAA==.',
Vu='Vulpain:BAAANQADCgYIBgABNQAECggIIQAIAI4gAA==.',
Vv='Vvnth:BAAANQADCgUIBQAAAA==.',
Wa='Washer:BAAANQADCgcIBwAAAA==.',
Wh='Whiteangel:BAAANQAECgEIAQAAAA==.',
Wi='Wickedgood:BAAANQADCgQIBQAAAA==.Willywallace:BAAANQABCgMIAwAAAA==.',
Wo='Wolfowl:BAAANQADCgYIGgAAAA==.',
Xa='Xaela:BAABNQAECn8aAAIdAAcKnA+aMgCpAQAdAAcKnA+aMgCpAQAAAA==.Xarous:BAAANQAECgYIBgABNQAECggIIQAIAI4gAA==.',
Xi='Xiabal:BAABNQAECn8cAAMeAAcKpBRIVgB6AQAeAAYKqRFIVgB6AQAbAAYK0xOHNAByAQAAAA==.',
Xw='Xweakling:BAAANQADCgYICAABNQAECggIHwAfAP4YAA==.Xweekling:BAABNQAECn8fAAIfAAgK/hjwCABNAgAfAAgK/hjwCABNAgAAAA==.',
Yo='Yonnà:BAAANQAECgMIAwAAAA==.Yoshirou:BAAANQADCgIIAgAAAA==.Yourgrandma:BAAANQAECgUIEQAAAA==.',
Yu='Yuxiong:BAAANQADCggIFwAAAA==.',
Ze='Zedra:BAEANQADCggIGAABNQAECgYICQACAAAAAA==.Zedrâ:BAEANQADCggIDAABNQAECgYICQACAAAAAA==.Zerostar:BAAANQAECgQICQABNQAECgkJLQAJALIfAA==.Zevon:BAAANQADCgEIAQABNQAECgQIBgACAAAAAA==.',
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
