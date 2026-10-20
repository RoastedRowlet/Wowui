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

local lookup = {'Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Shaman-Restoration','Unknown-Unknown','Paladin-Holy','Warrior-Arms','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Warrior-Protection','Druid-Guardian','Mage-Arcane','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Shaman-Elemental','Warrior-Fury','Warlock-Demonology','Druid-Restoration','DemonHunter-Devourer',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adicia:BAAANQAECgUIDgAAAA==.',
Ae='Aedercy:BAAANQABCggIGwAAAA==.Aestel:BAAANQABCgYIBQAAAA==.',
Al='Alarus:BAAANQADCgQIAQAAAA==.Alexithorn:BAAANQABCgUIBQAAAA==.Allila:BAABNQAECn8kAAIBAAgKTyEgDwAAAwABAAgKTyEgDwAAAwAAAA==.Alynara:BAAANQADCgcIBwABNQAECggIGgACAMMJAA==.',
Am='Ambrozyn:BAAANQAECgMIBAAAAA==.',
An='Anarariellea:BAAANQADCggJDgAAAA==.',
Ap='Apalrapzz:BAAANQADCgIJAgABNQAECgYIFgADAAsDAA==.',
Aq='Aqari:BAAANQAECgMICQAAAA==.',
Ar='Araxiie:BAAANQADCgIIAgAAAA==.Ardrelar:BAAANQAECgEIAgAAAA==.',
As='Asila:BAAANQAECgIIAgAAAA==.Astraea:BAAANQADCggIGwABNQAECgkJLgAEAKocAA==.',
At='Athika:BAAANQADCggIDAAAAA==.',
Au='Auria:BAAANQAECgIIAwABNQAECgMICQAFAAAAAA==.Autumnal:BAAANQADCgQIBgAAAA==.',
Az='Azralia:BAABNQAECn8XAAIGAAcKVBhLYgDxAQAGAAcKVBhLYgDxAQAAAA==.',
Bb='Bbygee:BAAANQADCgUIBQAAAA==.',
Be='Benjamin:BAABNQAECn8cAAIHAAoKaw+6fQAgAgAHAAoKaw+6fQAgAgAAAA==.Beyblade:BAAANQADCgQIBgAAAA==.',
Bl='Blacksun:BAAANQAECggIAwAAAA==.Blazinember:BAABNQAECn8jAAIIAAgK5xDPAgD7AQAIAAgK5xDPAgD7AQAAAA==.Blockhead:BAAANQAECgIIAgAAAA==.',
Bo='Bolonmixto:BAACNQAFFH8JAAMJAAUKkQ9yBgDoAAAJAAUKkQ9yBgDoAAAKAAEK0wu9IABHAAA1AAQKfyoAAwkACgoeIhMHAAwDAAkACgr7IRMHAAwDAAoAAgrgHeCHAJMAAAAA.Boop:BAABNQAECn8VAAILAAcKUxIaFwBwAQALAAcKUxIaFwBwAQABNQAECgkJKAAMAMMfAA==.Borghamer:BAAANQAECgIIAgAAAA==.Borimor:BAAANQADCgUICQABNQAECgkJGQANAGkSAA==.',
Br='Brendee:BAAANQADCgcIDAAAAA==.Bromkin:BAAANQAECgIIAgAAAA==.',
['Bë']='Bëorn:BAAANQAECgYIBgABNQAECgkJGQANAGkSAA==.',
Ca='Calinor:BAAANQAECgEIAQAAAA==.Callihunt:BAAANQADCgYICAAAAA==.Calliopeh:BAAANQADCggIDwAAAA==.',
Ce='Cedriq:BAAANQAECgEIAgAAAA==.Ceran:BAABNQAECn8VAAIOAAcKyAvqTABqAQAOAAcKyAvqTABqAQAAAA==.Cereus:BAABNQAECn8mAAMPAAoKdSE5AQCnAgAPAAoKdSE5AQCnAgAQAAQKvxEYKQDlAAAAAA==.',
Ch='Chaelenge:BAAANQAECgYIDgAAAA==.Chasatail:BAAANQADCgcICAAAAA==.Chyran:BAAANQAECgQIDQAAAA==.',
Co='Coldncrispy:BAAANQAECgMIAwAAAA==.Coloratura:BAABNQAECn8iAAIRAAgKCSD2HACVAQARAAgKCSD2HACVAQAAAA==.',
Cr='Crimsonmoon:BAAANQADCggICAABNQAECgkJKAAMAMMfAA==.Crylessia:BAAANQAECgMIAwAAAA==.',
Da='Dagethon:BAAANQADCgUJEAAAAA==.Dandon:BAAANQADCgYIBgABNQAECgEIAQAFAAAAAA==.Danfortesque:BAAANQADCgcIBwAAAA==.Danyah:BAAANQADCgUJBQABNQAECgoKJgASACsaAA==.Darkshådow:BAAANQAECgIIAgAAAA==.Daromiciah:BAAANQADCgYIBgAAAA==.',
De='Deathangels:BAAANQADCgQIBAAAAA==.Deftdirk:BAAANQADCgYIBgAAAA==.Delve:BAAANQADCgEIAQAAAA==.Denvoker:BAAANQAECgEIAQAAAA==.Desdeanna:BAAANQABCgIIAgAAAA==.',
Di='Dissension:BAAANQAECgUIAwAAAA==.',
Do='Doubtfire:BAABNQAECn8WAAMDAAYKCwM6QQBgAAADAAYKCwM6QQBgAAATAAEKAADIcQAbAAAAAA==.',
Dr='Dragii:BAAANQADCgYIBgAAAA==.',
Ed='Edelia:BAAANQAECgYIDAABNQAECgkJNQARADMfAA==.',
Er='Eraessyr:BAAANQADCgQJBAAAAA==.',
Fa='Fabin:BAAANQADCgEIAQAAAA==.Faithfulness:BAAANQAECgQIBQAAAA==.Fangz:BAABNQAECn8WAAIHAAUKqQfNiwCIAAAHAAUKqQfNiwCIAAAAAA==.',
Fr='Freakadeëk:BAAANQAECgIIAwAAAA==.Frierenn:BAABNQAECn8hAAMUAAgK8g8uwgAAAgAUAAgK8g8uwgAAAgAVAAEKAAC7RwA0AAAAAA==.Frosh:BAAANQAECgEIAQAAAA==.',
Ga='Gadodagaps:BAAANQADCgcIBwAAAA==.',
Gh='Ghouldottie:BAAANQADCgIIAgAAAA==.',
Gi='Gilidar:BAABNQAECn8nAAIHAAgKbSEOEgDHAQAHAAgKbSEOEgDHAQAAAA==.Gillarria:BAAANQADCgcIDAAAAA==.',
Gn='Gnomerdenis:BAAANQAECgIIAgAAAA==.',
Go='Goochiemon:BAAANQAECgMIAwAAAA==.',
Gr='Grimmberly:BAAANQAECgUIEQABNQAECgcIDwAFAAAAAA==.Grimoire:BAAANQAECgcIDwAAAA==.Gronna:BAAANQADCgYIBgABNQAECggIJAABAE8hAA==.',
Gu='Guthunnel:BAAANQADCggIDgAAAA==.Gutshadra:BAAANQAECgEIAQAAAA==.',
Ha='Haides:BAAANQADCgQIBAAAAA==.Hairybum:BAAANQABCgIIAgAAAA==.Halanji:BAAANQADCgUIBQAAAA==.Hannibow:BAAANQADCgQIBgAAAA==.',
He='Hellgrim:BAAANQADCgMIAQABNQAECgcIDwAFAAAAAA==.Helpmee:BAAANQAECgQIBAAAAA==.',
Ho='Hoawatt:BAAANQADCggIEwAAAA==.Holynova:BAAANQAECgEIAQABNQAECgcIHAAGAMQXAA==.Honkky:BAAANQAECgIIAgAAAA==.Hoofkick:BAAANQADCgQIBAAAAA==.Howlingfury:BAAANQABCgIIAgAAAA==.',
Hu='Huuch:BAABNQAECn8UAAINAAgKpwZepgC5AQANAAgKpwZepgC5AQAAAA==.',
Ig='Ignee:BAABNQAECn8mAAMSAAoKKxp9AQA/AgASAAoKKxp9AQA/AgAHAAMK9goDJQGOAAAAAA==.Ignia:BAAANQAECggIDQAAAA==.Igris:BAAANQADCggICAAAAA==.',
Ir='Iremoon:BAABNQAECn8hAAMWAAcKVAuCHwDvAAAWAAcKVAuCHwDvAAAXAAMKFgThqwB3AAABNQAECgkJHgAMABUPAA==.',
Je='Jestyr:BAABNQAECn8XAAIYAAgK9CKgBAD4AgAYAAgK9CKgBAD4AgAAAA==.',
Ji='Jimba:BAAANQADCgQIBAAAAA==.Jiyao:BAABNQAECn8kAAMZAAgKBBpfIQAhAgAZAAgKBBpfIQAhAgAaAAMKVwWHQQBtAAAAAA==.',
Jo='Jojinn:BAAANQAECgEIAQAAAA==.',
Ka='Kaceya:BAAANQADCgYICAAAAA==.Kainarasa:BAAANQAECgYIBgABNQAECgkJKAAMAMMfAA==.Katarinea:BAABNQAECn8XAAIDAAgKzwaKYwBAAQADAAgKzwaKYwBAAQAAAA==.',
Ke='Ketrus:BAAANQADCgQIBAABNQAECggIDQAFAAAAAA==.',
Kh='Khala:BAAANQAECgYIDwAAAA==.Khalessie:BAABNQAECn8mAAIbAAgK5hImCADoAQAbAAgK5hImCADoAQAAAA==.',
Ki='Killa:BAAANQAECgIIAgABNQAECgoKIAAHAI4dAA==.Killerfire:BAAANQAECgEIAQAAAA==.Killim:BAAANQAECgQIBAAAAA==.',
Kl='Klorick:BAAANQAECgYICgABNQAECgkJGQANAGkSAA==.',
Kr='Krillian:BAAANQADCggICAAAAA==.Krissa:BAAANQADCgcIBwAAAA==.',
Ku='Kungfudru:BAAANQADCgQJCQAAAA==.',
Kw='Kwai:BAAANQADCgQIBQABNQAECgkJGQANAGkSAA==.',
Ky='Kyla:BAAANQAECgYICgAAAA==.Kyomu:BAAANQADCggICAABNQAECgkJKAAMAMMfAA==.',
Le='Legio:BAAANQADCgQJBAAAAA==.',
Li='Lineofsight:BAABNQAECn8fAAIHAAYKRRBwbADBAAAHAAYKRRBwbADBAAAAAA==.Lipa:BAAANQADCgEIAQAAAA==.Liths:BAABNQAECn8hAAIYAAcKYxCeCQDPAAAYAAcKYxCeCQDPAAAAAA==.',
Lo='Loading:BAAANQAECgEIAQABNQAECgkJKgAcABwZAA==.Lockdarkly:BAAANQAECgIIAgAAAA==.Loko:BAAANQADCgEIAQAAAA==.',
Lu='Lululuvely:BAAANQAECgQICwAAAA==.',
['Lí']='Lív:BAAANQAECgMIAwAAAA==.',
Ma='Machrona:BAAANQADCgUIBgAAAA==.Madelyn:BAAANQADCgUJBQAAAA==.Magecat:BAAANQAECgEIAQABNQAECggIDQAFAAAAAA==.Magejacob:BAAANQADCgYIDgAAAA==.Malena:BAEANQAECgYIDgAAAA==.Malendren:BAAANQABCgQIBAAAAA==.Margot:BAAANQAECgMIAwAAAA==.Marksmann:BAAANQADCgYIBQAAAA==.',
Mc='Mcdavé:BAABNQAECn8hAAIcAAcKPg4rJQAnAQAcAAcKPg4rJQAnAQAAAA==.',
Me='Meerclar:BAAANQAECgQICgAAAA==.Melaila:BAABNQAECn8uAAIEAAkKqhyTLgCnAgAEAAkKqhyTLgCnAgAAAA==.Melysithea:BAAANQAECgcICgABNQAECgkJLgAEAKocAA==.',
Mi='Micheal:BAAANQAECggIEAAAAA==.Midir:BAAANQAECgYIBgAAAA==.Mistymay:BAAANQADCgYJCwAAAA==.Miñitañk:BAAANQAECgUICQAAAA==.',
Mo='Moldthinur:BAAANQAECgUIDAAAAA==.Mongrol:BAAANQAECgQIDQAAAA==.Monôpolyguy:BAAANQAECgMICQAAAA==.Moonowl:BAAANQAECgEIAQAAAA==.',
Mu='Mummrakhan:BAAANQAECgQIDQAAAA==.Murraya:BAAANQADCgMIAwAAAA==.',
My='Mythdalkurim:BAAANQADCgUICgAAAA==.',
Na='Naniel:BAABNQAECn8tAAMSAAoKxh8hBABNAwASAAkKayIhBABNAwAdAAEKRg1qFgA9AAAAAA==.Nazgrefry:BAAANQAECgcIDwAAAA==.',
Ne='Neb:BAABNQAECn8qAAIeAAgK+xNqJQBZAQAeAAgK+xNqJQBZAQAAAA==.Necroy:BAAANQAECggIEAAAAA==.',
Ni='Niccee:BAABNQAECn8WAAIDAAgKBQgGYwBCAQADAAgKBQgGYwBCAQAAAA==.',
No='Noggindeez:BAAANQADCgIIAgABNQAECgoKGgAcAOwfAA==.Noodles:BAABNQAECn8UAAIMAAYKdRWUzACCAQAMAAYKdRWUzACCAQAAAA==.Nosebleeds:BAAANQAECgIIAgAAAA==.',
Nu='Numerotres:BAAANQADCgQIBAAAAA==.Numerouno:BAABNQAECn8cAAMGAAcKxBe0hACMAQAGAAYKLxa0hACMAQAMAAYKaQXoeADXAAAAAA==.',
['Nî']='Nîtara:BAAANQADCgEIAQAAAA==.',
Om='Omegasupreme:BAAANQABCgIJAgAAAA==.',
Oo='Ookthron:BAABNQAECn8aAAMHAAgK0xbflADoAQAHAAgK0xbflADoAQASAAMKuxILNQCNAAAAAA==.',
Oz='Ozempic:BAAANQAECgMIAwAAAA==.',
Pa='Pandi:BAAANQAECgUIBgAAAA==.Papasmurff:BAAANQAECgIIAgAAAA==.Parachute:BAAANQAECgUIDAAAAA==.Parky:BAAANQADCgUICAAAAA==.',
Pe='Percival:BAABNQAECn8VAAIMAAgKexIwrwDBAQAMAAgKexIwrwDBAQAAAA==.',
Ph='Phreakadeek:BAAANQADCgcIDgABNQAECgMIBgAFAAAAAA==.',
Pi='Pinheadgarry:BAAANQADCgIIAgAAAA==.Pizzaslice:BAABNQAECn8oAAIMAAkKwx93MAAIAwAMAAkKwx93MAAIAwAAAA==.',
Pr='Praxiscannon:BAAANQAECgUIDgAAAA==.',
Pu='Pumpshire:BAABNQAECn8ZAAIQAAkKOQcjHgBvAQAQAAkKOQcjHgBvAQAAAA==.',
Pw='Pwongo:BAABNQAECn8rAAIfAAgKYCGCEgC7AgAfAAgKYCGCEgC7AgAAAA==.',
Qt='Qt:BAACNQAFFH8JAAIcAAMKshZsCwCdAAAcAAMKshZsCwCdAAA1AAQKfyYAAhwACgqKIIMlAO4CABwACgqKIIMlAO4CAAAA.',
Qu='Queue:BAAANQAECgMIBQAAAA==.Quilten:BAAANQAECgUICgAAAA==.',
Ra='Raenii:BAABNQAECn8XAAIeAAgKMRAcEgC0AQAeAAgKMRAcEgC0AQABNQAECgkJNQARADMfAA==.Ramoth:BAAANQAECgMIAwAAAA==.Razelda:BAAANQAECggIAwAAAA==.',
Rh='Rhodas:BAAANQAECgcIBwABNQAECgkJIwAHAAceAA==.',
Ri='Riandras:BAAANQADCgQIBAABNQAECgQICgAFAAAAAA==.',
Ro='Roadwanderer:BAAANQAECgMIAwAAAA==.Robbiedrake:BAAANQAECgEIAQABNQAECgkJLQALAHEYAA==.Robbiemonk:BAABNQAECn8tAAILAAkKcRj9CgBfAgALAAkKcRj9CgBfAgAAAA==.Rodric:BAAANQAECgYIBwABNQAECgkJGQANAGkSAA==.',
Ru='Runetottem:BAAANQAECgYIDgAAAA==.',
Rx='Rxeight:BAAANQADCgYIDAAAAA==.',
Sa='Sakura:BAAANQADCgIIAgAAAA==.Samarii:BAAANQAECgEIAQAAAA==.Sannith:BAABNQAECn8hAAMUAAcK5Rf8MQBcAQAUAAcKqxX8MQBcAQAVAAEKlh5pQwA9AAAAAA==.',
Sc='Scyllia:BAABNQAECn8mAAIBAAkKwBgrFwCfAgABAAkKwBgrFwCfAgAAAA==.Scârlett:BAEANQADCgUICAABNQAECgYIDgAFAAAAAA==.',
Sh='Shadowklaw:BAAANQAECgIIBAAAAA==.Shamanoodles:BAAANQAECgYIDAABNQAECgkJLgAEAKocAA==.Shespawn:BAAANQAECgcIDQAAAA==.Shurie:BAABNQAECn8ZAAINAAkKaRI5YwBPAgANAAkKaRI5YwBPAgAAAA==.Shâdê:BAAANQAECgMJBAAAAA==.',
Si='Sindrak:BAAANQABCgYICAAAAA==.',
Sl='Slipperybop:BAABNQAECn80AAIMAAkKjyHDLAAVAwAMAAkKjyHDLAAVAwABNQAECgQICQAFAAAAAA==.Slugbow:BAAANQADCgUIBQAAAA==.',
Sn='Snakeshadow:BAAANQADCgcIBwAAAA==.Snazzlehorn:BAAANQAECgIIAgAAAA==.Snifflenips:BAAANQADCgcIBwABNQAECgEIAQAFAAAAAA==.Snoroll:BAAANQAECgEIAQAAAA==.',
So='Soldanis:BAAANQABCgEIAQAAAA==.',
Sp='Spazoff:BAAANQAECgQIBQAAAA==.Spyman:BAAANQADCgYICgAAAA==.',
Sq='Squissh:BAAANQAECgYIEAABNQAECgkJGQANAGkSAA==.',
Sr='Srhubbabubba:BAAANQAECgQICAABNQAECgcIGAARAM4dAA==.',
St='Sternn:BAAANQAECgIIAwAAAA==.Straif:BAAANQAECgQIBQAAAA==.Strawberrÿ:BAABNQAECn8bAAIMAAkKSQm00gB2AQAMAAkKSQm00gB2AQAAAA==.',
Sw='Swolman:BAAANQADCgIIAgAAAA==.',
Sy='Sydonai:BAAANQAECggICAAAAA==.Syreithada:BAAANQADCgcICQAAAA==.',
Ta='Talathra:BAABNQAECn8aAAICAAgKwwnMCgA9AQACAAgKwwnMCgA9AQAAAA==.',
Te='Teddy:BAABNQAECn8XAAITAAgKtxSEHQC1AQATAAgKtxSEHQC1AQAAAA==.Tellah:BAEANQADCgQIBAABNQAECgoKKQAEAIQiAA==.',
Th='Thegodofwar:BAABNQAECn8jAAIHAAkKBx6fGwCWAQAHAAkKBx6fGwCWAQAAAA==.Thân:BAAANQAECgMIBAAAAA==.',
Ti='Tivon:BAAANQAECgEJAQAAAA==.',
Tt='Ttonkkalos:BAAANQAECgQIBAAAAA==.',
Tw='Twomz:BAAANQADCgYIBgAAAA==.',
Um='Um:BAAANQADCgIIAgABNQAECgkJKgAcABwZAA==.Umi:BAAANQAECggICgAAAA==.Umzingeli:BAAANQADCggICAAAAA==.',
Va='Varkbyte:BAAANQADCgUICgAAAA==.Varock:BAAANQAECgIIAgABNQAECgkJKAAMAMMfAA==.',
Vi='Vindication:BAAANQAECgMIBwAAAA==.Viz:BAAANQADCggIJgAAAA==.',
Vr='Vraul:BAABNQAECn8XAAIHAAgKGxIJqgC0AQAHAAgKGxIJqgC0AQAAAA==.',
Vu='Vulpain:BAAANQADCgYIBgABNQAECgkJKAAMAMMfAA==.',
Vv='Vvnth:BAAANQAECgMIAwAAAA==.',
Wa='Washer:BAAANQADCgcIBwAAAA==.',
Wh='Whiteangel:BAAANQAECgEIAQAAAA==.',
Wi='Wickedgood:BAAANQADCgQIBQAAAA==.Willywallace:BAAANQABCgMIAwAAAA==.',
Wo='Wolfowl:BAAANQADCgYIHwAAAA==.',
Xa='Xaela:BAABNQAECn8aAAIgAAcKnA8uMwCoAQAgAAcKnA8uMwCoAQAAAA==.Xarous:BAAANQAECgYIDAABNQAECgkJKAAMAMMfAA==.',
Xi='Xiabal:BAABNQAECn8fAAMDAAkKSxYjVwB6AQADAAcKphIjVwB6AQAfAAcKSBQUNQByAQAAAA==.',
Xw='Xweakling:BAAANQADCgYICAABNQAECggIIwAdAEQZAA==.Xweekling:BAABNQAECn8jAAIdAAgKRBkGCQBNAgAdAAgKRBkGCQBNAgAAAA==.',
Yo='Yonnà:BAAANQAECgMIAwAAAA==.Yoshirou:BAAANQADCgIIAgAAAA==.Yourgrandma:BAAANQAECgUIEgAAAA==.',
Yu='Yuxiong:BAAANQADCggIGAAAAA==.',
Ze='Zedra:BAEANQADCggIGAABNQAECgYIDgAFAAAAAA==.Zedrâ:BAEANQADCggIDAABNQAECgYIDgAFAAAAAA==.Zerostar:BAAANQAECgQIDQABNQAECgoKNAANADkeAA==.Zevon:BAAANQADCgEIAQABNQAECgQICgAFAAAAAA==.',
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
