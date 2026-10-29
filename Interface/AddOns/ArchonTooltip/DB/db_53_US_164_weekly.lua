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

local lookup = {'DeathKnight-Unholy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Shaman-Restoration','Unknown-Unknown','Paladin-Holy','Warrior-Arms','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Warrior-Protection','Druid-Guardian','Mage-Arcane','Mage-Frost','Druid-Restoration','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Shaman-Elemental','Paladin-Protection','Warrior-Fury','Hunter-Survival','DemonHunter-Devourer',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adicia:BAABNQAECn8YAAIBAAYKRQmsgQAXAQABAAYKRQmsgQAXAQAAAA==.',
Ae='Aedercy:BAAANQABCggIGwAAAA==.Aestel:BAAANQABCgYIBgAAAA==.',
Al='Alarus:BAAANQAECgIIAgAAAA==.Alexithorn:BAAANQABCgUIBQAAAA==.Allila:BAABNQAECn8tAAICAAkKyyAgDwAAAwACAAkKyyAgDwAAAwAAAA==.Alynara:BAAANQADCgcIBwABNQAECgoKHQADAHgKAA==.',
Am='Ambrozyn:BAAANQAECgQIBgAAAA==.',
An='Anarariellea:BAAANQADCggJDgAAAA==.',
Ap='Apalrapzz:BAAANQADCgIJAgABNQAECgYIGwAEADIDAA==.',
Aq='Aqari:BAAANQAECgMICQAAAA==.',
Ar='Araxiie:BAAANQADCgIIAgAAAA==.Ardrelar:BAAANQAECgIIAwAAAA==.',
As='Asila:BAAANQAECgIIAwAAAA==.Astraea:BAAANQADCggIGwABNQAECgoKNwAFAJccAA==.',
At='Athika:BAAANQADCggIDAAAAA==.',
Au='Auria:BAAANQAECgIIAwABNQAECgMICQAGAAAAAA==.Autumnal:BAAANQADCgQIBgAAAA==.',
Az='Azralia:BAABNQAECn8XAAIHAAcKVBhLYgDxAQAHAAcKVBhLYgDxAQAAAA==.',
Ba='Baddock:BAAANQAECgMIAgAAAA==.Banzamakeher:BAAANQAECgMIAwAAAA==.',
Bb='Bbygee:BAAANQADCgUIBQAAAA==.',
Be='Benjamin:BAABNQAECn8iAAIIAAoKlRG6fQAgAgAIAAoKlRG6fQAgAgAAAA==.Beyblade:BAAANQADCgQIBgAAAA==.',
Bl='Blacksun:BAAANQAECggIAwAAAA==.Blazinember:BAABNQAECn8nAAIJAAkKZRDPAgD7AQAJAAkKZRDPAgD7AQAAAA==.Blockhead:BAAANQAECgIIAgAAAA==.',
Bo='Bolonmixto:BAACNQAFFH8KAAMKAAUKkQ/ODQDZAAAKAAUKkQ/ODQDZAAALAAEK0wu9IABHAAA1AAQKfzYAAwoACgo9IhMHAAwDAAoACgoaIhMHAAwDAAsAAgrgHeCHAJMAAAAA.Boop:BAABNQAECn8bAAIMAAcKHxZKCQBGAQAMAAcKHxZKCQBGAQABNQAECgkJMAANAJQgAA==.Borghamer:BAAANQAECgIIAgAAAA==.Borimor:BAAANQADCgUICQABNQAECgoKIgAOAGsRAA==.',
Br='Brendee:BAAANQADCgcIEAAAAA==.Bromkin:BAAANQAECgIIAgAAAA==.',
['Bë']='Bëorn:BAAANQAECgYIBgABNQAECgoKIgAOAGsRAA==.',
Ca='Calinor:BAAANQAECgEIAQAAAA==.Callihunt:BAAANQADCgYICAAAAA==.Calliopeh:BAAANQADCggIDwAAAA==.',
Ce='Cedriq:BAAANQAECgEIAgAAAA==.Ceran:BAABNQAECn8bAAIPAAgKZgunMwAOAQAPAAgKZgunMwAOAQAAAA==.Cereus:BAABNQAECn8wAAMQAAoKnyG7AgA5AwAQAAoKnyG7AgA5AwARAAQKvxEYKQDlAAAAAA==.',
Ch='Chaelenge:BAAANQAECggIDwAAAA==.Chasatail:BAAANQADCgcICAAAAA==.Chyran:BAABNQAECn8bAAINAAcK2wKy7gCXAAANAAcK2wKy7gCXAAAAAA==.',
Co='Coldncrispy:BAAANQAECgMIAwAAAA==.Coloratura:BAABNQAECn8sAAISAAkKAx5BJwAzAgASAAkKAx5BJwAzAgAAAA==.',
Cr='Crimsonmoon:BAAANQADCggICAABNQAECgkJMAANAJQgAA==.Crylessia:BAAANQAECgMIAwAAAA==.',
Da='Dagethon:BAAANQADCgUJEAAAAA==.Dandon:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.Danfortesque:BAAANQADCgcIBwAAAA==.Danyah:BAAANQADCgUJBQABNQAECgoKMAATAAgdAA==.Darkshådow:BAAANQAECgMIBQAAAA==.Daromiciah:BAAANQADCgYIBgAAAA==.',
De='Deathangels:BAAANQADCgQIBAAAAA==.Deftdirk:BAAANQADCgYIBgAAAA==.Delve:BAAANQADCgEIAQAAAA==.Denvoker:BAAANQAECgEIAQAAAA==.Desdeanna:BAAANQABCgIIAgAAAA==.',
Di='Dissension:BAAANQAECgYIAwAAAA==.',
Do='Doubtfire:BAABNQAECn8bAAMEAAYKMgOpVQByAAAEAAYKMgOpVQByAAAUAAEKAADIcQAbAAAAAA==.',
Dr='Dragii:BAAANQADCgYIBgAAAA==.',
Ed='Edelia:BAAANQAECgcIDgABNQAECgkJPgASANsgAA==.',
Er='Eraessyr:BAAANQADCgQJBAAAAA==.Eragön:BAAANQADCgUIBQAAAA==.',
Fa='Fabin:BAAANQADCgEIAQAAAA==.Faithfulness:BAAANQAECgQIBQAAAA==.Fangz:BAABNQAECn8dAAIIAAcKVgfHkgDnAAAIAAcKVgfHkgDnAAAAAA==.',
Fo='Forsëti:BAAANQAECgIIAgAAAA==.',
Fr='Freakadeëk:BAAANQAECgIIBQAAAA==.Frierenn:BAABNQAECn8hAAMVAAgK8g8uwgAAAgAVAAgK8g8uwgAAAgAWAAEKAAC7RwA0AAAAAA==.Frosh:BAAANQAECgEIAQAAAA==.',
Ga='Gadodagaps:BAAANQADCgcIBwAAAA==.',
Gh='Ghouldottie:BAAANQADCgIIAgAAAA==.',
Gi='Gilidar:BAABNQAECn8uAAIIAAgKbSH0NwDkAgAIAAgKbSH0NwDkAgAAAA==.Gillarria:BAAANQADCgcIDAAAAA==.',
Gl='Glori:BAAANQADCgQIBAABNQAECgQIBgAGAAAAAA==.',
Gn='Gnomerdenis:BAAANQAECgMIBQAAAA==.',
Go='Goochiemon:BAAANQAECgMIAwAAAA==.',
Gr='Greenspawn:BAAANQAECggICAAAAA==.Grimmberly:BAAANQAECgUIEQABNQAECgoKGgAUAAQhAA==.Grimoire:BAABNQAECn8aAAMUAAoKBCFNCwC4AgAUAAoKBCFNCwC4AgAXAAEKDQaegQAdAAAAAA==.Gronna:BAAANQADCgYIBgABNQAECgkJLQACAMsgAA==.',
Gu='Guthunnel:BAAANQADCggIDgAAAA==.Gutshadra:BAAANQAECgEIAQAAAA==.',
Ha='Haides:BAAANQADCgQIBAAAAA==.Hairybum:BAAANQABCgIIAgAAAA==.Halanji:BAAANQADCgUIBQAAAA==.Hannibow:BAAANQADCgQIBgAAAA==.',
He='Hellgrim:BAAANQADCgMIAQABNQAECgoKGgAUAAQhAA==.Helpmee:BAAANQAECgcIBAAAAA==.',
Ho='Hoawatt:BAAANQADCggIEwAAAA==.Holynova:BAAANQAECgEIAQABNQAECgcIHAAHAMQXAA==.Honkky:BAAANQAECgIIAgAAAA==.Hoofkick:BAAANQADCgQIBAAAAA==.',
Hu='Huuch:BAABNQAECn8YAAIOAAgKEwdepgC5AQAOAAgKEwdepgC5AQAAAA==.',
Ig='Ignee:BAABNQAECn8wAAMTAAoKCB3lAwCLAgATAAoKCB3lAwCLAgAIAAMK9goDJQGOAAAAAA==.Ignia:BAAANQAECggIEAAAAA==.Igris:BAAANQADCggICAAAAA==.',
Ir='Iremoon:BAABNQAECn8hAAMBAAcKVAsROADcAAABAAcKVAsROADcAAAYAAMKFgThqwB3AAABNQAECgoKLAAZAG8LAA==.',
Je='Jestyr:BAABNQAECn8XAAIaAAgK9CKgBAD4AgAaAAgK9CKgBAD4AgAAAA==.',
Ji='Jimba:BAAANQADCgQIBAAAAA==.Jiyao:BAABNQAECn8nAAMbAAkKuBlfIQAhAgAbAAkKuBlfIQAhAgAcAAMKVwWHQQBtAAAAAA==.',
Jo='Jojinn:BAAANQAECgEIAQAAAA==.',
Ka='Kaceya:BAAANQADCgYICAAAAA==.Kainarasa:BAAANQAECgYIBgABNQAECgkJMAANAJQgAA==.Katarinea:BAABNQAECn8XAAIEAAgKzwaKYwBAAQAEAAgKzwaKYwBAAQAAAA==.Kaylle:BAAANQAECgcIDQAAAA==.',
Ke='Ketrus:BAAANQADCgQIBAABNQAECggIEAAGAAAAAA==.',
Kh='Khala:BAABNQAECn8YAAIZAAkK8QRmbgAgAQAZAAkK8QRmbgAgAQAAAA==.Khalessie:BAABNQAECn8tAAIdAAgKhRQmCADoAQAdAAgKhRQmCADoAQAAAA==.',
Ki='Killa:BAAANQAECgIIAgABNQAECgoKKQAIABkjAA==.Killerfire:BAAANQAECgEIAQAAAA==.Killim:BAAANQAECgYICQAAAA==.',
Kl='Klorick:BAAANQAECgYICgABNQAECgoKIgAOAGsRAA==.',
Kr='Krillian:BAAANQADCggICAAAAA==.Krissa:BAAANQADCgcIBwAAAA==.',
Ku='Kungfudru:BAAANQADCgQJCQAAAA==.',
Kw='Kwai:BAAANQADCgQIBQABNQAECgoKIgAOAGsRAA==.',
Ky='Kyla:BAAANQAECgUICgAAAA==.Kyomu:BAAANQADCggICAABNQAECgkJMAANAJQgAA==.',
La='Lazzarus:BAAANQADCggICgAAAA==.',
Le='Legio:BAAANQADCgQJBAAAAA==.',
Li='Lineofsight:BAABNQAECn8mAAIIAAcKJA8TggAPAQAIAAcKJA8TggAPAQAAAA==.Lipa:BAAANQADCgEIAQAAAA==.Liths:BAABNQAECn8hAAIaAAcKYxCfEwBzAQAaAAcKYxCfEwBzAQAAAA==.',
Lo='Loading:BAAANQAECgEIAQABNQAECgoKLgAeAN8XAA==.Lockdarkly:BAAANQAECgMIBAAAAA==.Loko:BAAANQADCgEIAQAAAA==.',
Lu='Lululuvely:BAAANQAECgQICwAAAA==.',
['Lí']='Lív:BAAANQAECgMIAwAAAA==.',
Ma='Machrona:BAAANQADCgUIBgAAAA==.Madelyn:BAAANQADCgUJBQAAAA==.Magecat:BAAANQAECgEIAQABNQAECggIEAAGAAAAAA==.Magejacob:BAAANQADCgYIDgAAAA==.Malena:BAEANQAECgcIDwAAAA==.Malendren:BAAANQABCgQIBAAAAA==.Margot:BAAANQAECggICQAAAA==.Marksmann:BAAANQADCgYIBQAAAA==.',
Mc='Mcdavé:BAABNQAECn8hAAIeAAcKPg6SWAADAQAeAAcKPg6SWAADAQAAAA==.',
Me='Meerclar:BAAANQAECgQICgAAAA==.Melaila:BAABNQAECn83AAIFAAoKlxwxFwCLAgAFAAoKlxwxFwCLAgAAAA==.Melysithea:BAAANQAECgcIDgABNQAECgoKNwAFAJccAA==.',
Mi='Micheal:BAAANQAECggICAAAAA==.Midir:BAAANQAECgYIBgAAAA==.Mistymay:BAAANQADCgYJCwAAAA==.Miñitañk:BAAANQAECgUIDgAAAA==.',
Mo='Moldthinur:BAABNQAECn8WAAIfAAYKOx2+HwDnAQAfAAYKOx2+HwDnAQAAAA==.Mongrol:BAAANQAECgQIDQAAAA==.Monôpolyguy:BAAANQAECgMICQAAAA==.Moonowl:BAAANQAECgEIAQAAAA==.',
Mu='Mummrakhan:BAABNQAECn8UAAIZAAUKzAISBQHBAAAZAAUKzAISBQHBAAAAAA==.Murraya:BAAANQADCgMIAwAAAA==.',
My='Mythdalkurim:BAAANQADCgUICgAAAA==.',
Na='Naniel:BAABNQAECn80AAMTAAoK4CI1AgD4AgATAAoK4CI1AgD4AgAgAAEKRg3SIQA7AAAAAA==.Nazgrefry:BAAANQAECgcIDwAAAA==.',
Ne='Neb:BAABNQAECn8uAAIZAAkKcxTGOgC+AQAZAAkKcxTGOgC+AQAAAA==.Necroy:BAAANQAECggIEAAAAA==.',
Ni='Niccee:BAABNQAECn8XAAIEAAkKiQcGYwBCAQAEAAkKiQcGYwBCAQAAAA==.',
No='Noggindeez:BAAANQADCgIIAgABNQAECgoKHAAeAEcgAA==.Noodles:BAABNQAECn8UAAINAAYKdRWUzACCAQANAAYKdRWUzACCAQAAAA==.Nosebleeds:BAAANQAECgcICQAAAA==.',
Nu='Numerotres:BAAANQADCgQIBAAAAA==.Numerouno:BAABNQAECn8cAAMHAAcKxBe0hACMAQAHAAYKLxa0hACMAQANAAYKaQUxzQDHAAAAAA==.',
['Nî']='Nîtara:BAAANQADCgEIAQAAAA==.',
Om='Omegasupreme:BAAANQABCgIJAgAAAA==.',
Oo='Ookthron:BAABNQAECn8cAAMIAAkKohTflADoAQAIAAkKohTflADoAQATAAMKuxILNQCNAAAAAA==.',
Oz='Ozempic:BAAANQAECgQIBwAAAA==.',
Pa='Papasmurff:BAAANQAECgQIAgAAAA==.Parachute:BAAANQAECgUIDAAAAA==.Parky:BAAANQADCgUICAAAAA==.',
Pe='Percival:BAABNQAECn8WAAINAAkKEREwrwDBAQANAAkKEREwrwDBAQAAAA==.',
Ph='Phreakadeek:BAAANQADCgcIDgABNQAECgcIGgAhAHETAA==.',
Pi='Pinheadgarry:BAAANQADCgIIAgAAAA==.Pizzaslice:BAABNQAECn8wAAINAAkKlCB3MAAIAwANAAkKlCB3MAAIAwAAAA==.',
Pr='Praxiscannon:BAABNQAECn8UAAIZAAYKYAXg6AD3AAAZAAYKYAXg6AD3AAAAAA==.',
Pu='Pumpshire:BAABNQAECn8dAAIRAAoKiQgCDwDkAAARAAoKiQgCDwDkAAAAAA==.',
Pw='Pwongo:BAABNQAECn80AAIXAAoKqR6CEgC7AgAXAAoKqR6CEgC7AgAAAA==.',
Qt='Qt:BAACNQAFFH8OAAIeAAUKvhlVCQDvAAAeAAUKvhlVCQDvAAA1AAQKfy8AAh4ACgqCIk0IAP0CAB4ACgqCIk0IAP0CAAAA.',
Qu='Queue:BAAANQAECgMIBQAAAA==.Quilten:BAAANQAECgUICgAAAA==.',
Ra='Raenii:BAABNQAECn8bAAIZAAkKBBG4MwDcAQAZAAkKBBG4MwDcAQABNQAECgkJPgASANsgAA==.Ramoth:BAAANQAECgQIBgAAAA==.Razelda:BAAANQAECggIBgAAAA==.',
Rh='Rhodas:BAAANQAECggIDAABNQAECgkJLAAIAFchAA==.',
Ri='Riandras:BAAANQADCgQIBAABNQAECgQICgAGAAAAAA==.',
Ro='Roadwanderer:BAAANQAECgMIBgAAAA==.Robbiedrake:BAAANQAECgEIAQABNQAECgoKNwAMAG0ZAA==.Robbiemonk:BAABNQAECn83AAIMAAoKbRkHBAAVAgAMAAoKbRkHBAAVAgAAAA==.Rodric:BAAANQAECggIDwABNQAECgoKIgAOAGsRAA==.',
Ru='Runetottem:BAAANQAECgcIDwAAAA==.',
Rx='Rxeight:BAAANQADCgYIDAAAAA==.',
Sa='Sakura:BAAANQADCgIIAgAAAA==.Samarii:BAAANQAECgEIAQAAAA==.Sannith:BAABNQAECn8hAAMVAAcK5RctgwA8AQAVAAcKqxUtgwA8AQAWAAEKlh5pQwA9AAAAAA==.',
Sc='Scyllia:BAABNQAECn8mAAICAAkKwBgrFwCfAgACAAkKwBgrFwCfAgAAAA==.Scârlett:BAEANQADCgUICAABNQAECgcIDwAGAAAAAA==.',
Sh='Shadowklaw:BAAANQAECgUIBwAAAA==.Shamanoodles:BAAANQAECgYIDAABNQAECgoKNwAFAJccAA==.Shespawn:BAAANQAECggIDgAAAA==.Shurie:BAABNQAECn8iAAIOAAoKaxHNSwC5AQAOAAoKaxHNSwC5AQAAAA==.Shâdê:BAAANQAECgMJBAAAAA==.',
Si='Sinae:BAAANQADCggICAAAAA==.Sindrak:BAAANQABCgYICAAAAA==.',
Sl='Slipperybop:BAABNQAECn80AAINAAkKjyHDLAAVAwANAAkKjyHDLAAVAwABNQAECgQICQAGAAAAAA==.Slugbow:BAAANQADCgUIBQAAAA==.',
Sn='Snakeshadow:BAAANQADCggICAAAAA==.Snazzlehorn:BAAANQAECgQIBQAAAA==.Snifflenips:BAAANQADCgcIBwABNQAECgEIAQAGAAAAAA==.Snoroll:BAAANQAECgEIAQAAAA==.',
So='Soldanis:BAAANQABCgEIAQAAAA==.',
Sp='Spazoff:BAAANQAECgQIBQAAAA==.Spyman:BAAANQADCgYICgAAAA==.',
Sq='Squissh:BAAANQAECgYIEAABNQAECgoKIgAOAGsRAA==.',
Sr='Srhubbabubba:BAAANQAECgQICAABNQAECgcIGAASAM4dAA==.',
St='Sternn:BAAANQAECgQIBgAAAA==.Straif:BAAANQAECgUICgAAAA==.Strawberrÿ:BAABNQAECn8bAAINAAkKSQm00gB2AQANAAkKSQm00gB2AQAAAA==.',
Sw='Swolman:BAAANQADCgIIAgAAAA==.',
Sy='Sydonai:BAAANQAECggICAAAAA==.Syreithada:BAAANQADCgcICQAAAA==.',
Ta='Talathra:BAABNQAECn8dAAMDAAoKeAreFwBMAQADAAkKBAneFwBMAQAOAAIKTw2l3QB3AAAAAA==.',
Td='Tddaddy:BAAANQADCgEIAQAAAA==.',
Te='Teddy:BAABNQAECn8YAAIUAAkKLhWEHQC1AQAUAAkKLhWEHQC1AQAAAA==.Tellah:BAEANQADCgQIBAABNQAFFAMIBQAFAFsjAA==.',
Th='Thegodofwar:BAABNQAECn8sAAIIAAkKVyGbEwDIAgAIAAkKVyGbEwDIAgAAAA==.Thân:BAAANQAECgQIBwAAAA==.',
Ti='Tivon:BAAANQAECgEJAQAAAA==.',
To='Tonksie:BAAANQAECgUIBQAAAA==.',
Tt='Ttonkkalos:BAAANQAECgQIBAAAAA==.',
Tw='Twomz:BAAANQADCgYIBgAAAA==.',
Um='Um:BAAANQADCgIIAgABNQAECgoKLgAeAN8XAA==.Umi:BAAANQAECggICwAAAA==.Umzingeli:BAAANQADCggIEAAAAA==.',
Va='Varkbyte:BAAANQADCgUICgAAAA==.Varock:BAAANQAECgIIAgABNQAECgkJMAANAJQgAA==.',
Vi='Vindication:BAAANQAECgMIBwAAAA==.',
Vr='Vraul:BAABNQAECn8YAAIIAAkK+BAJqgC0AQAIAAkK+BAJqgC0AQAAAA==.',
Vu='Vulpain:BAAANQADCgYIBgABNQAECgkJMAANAJQgAA==.',
Vv='Vvnth:BAAANQAECgMIAwAAAA==.',
Wa='Washer:BAAANQADCggIDwAAAA==.',
Wh='Whiteangel:BAAANQAECgEIAQAAAA==.',
Wi='Wickedgood:BAAANQADCgQIBQAAAA==.Willywallace:BAAANQABCgMIAwAAAA==.',
Wo='Wolfowl:BAAANQADCgYIJQAAAA==.',
Xa='Xaela:BAABNQAECn8aAAIiAAcKnA8uMwCoAQAiAAcKnA8uMwCoAQAAAA==.Xarous:BAAANQAECgYIDAABNQAECgkJMAANAJQgAA==.',
Xi='Xiabal:BAABNQAECn8hAAMEAAoKRhUjVwB6AQAEAAgK5REjVwB6AQAXAAcKSBQUNQByAQAAAA==.',
Xw='Xweakling:BAAANQADCgYICAABNQAECgoKKgAgAMQYAA==.Xweekling:BAABNQAECn8qAAIgAAoKxBgGCQBNAgAgAAoKxBgGCQBNAgAAAA==.',
Yo='Yonnà:BAAANQAECgMIAwAAAA==.Yoshirou:BAAANQADCgIIAgAAAA==.Yourgrandma:BAABNQAECn8XAAIYAAYKsgrlTACyAAAYAAYKsgrlTACyAAAAAA==.',
Ze='Zedra:BAEANQADCggIGAABNQAECgcIDwAGAAAAAA==.Zedrâ:BAEANQADCggIDAABNQAECgcIDwAGAAAAAA==.Zerostar:BAAANQAECgYIEAABNQAECgoKOAAOAAcfAA==.Zevon:BAAANQADCgEIAQABNQAECgQICgAGAAAAAA==.',
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
