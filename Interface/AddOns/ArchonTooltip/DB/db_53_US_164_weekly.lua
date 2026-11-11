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

local lookup = {'DeathKnight-Unholy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Evoker-Preservation','Shaman-Restoration','Unknown-Unknown','Paladin-Holy','Warrior-Arms','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Devastation','Priest-Holy','Warrior-Protection','Druid-Guardian','Mage-Arcane','Mage-Frost','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Priest-Discipline','Shaman-Elemental','Paladin-Protection','Warrior-Fury','Hunter-Survival','Warlock-Affliction',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Adicia:BAABNQAECn8iAAIBAAcKJwl6QQD2AAABAAcKJwl6QQD2AAAAAA==.',
Ae='Aedercy:BAAANQABCggIHwAAAA==.Aestel:BAAANQABCgYIBQAAAA==.',
Al='Alarus:BAAANQAECgUIBgAAAA==.Alexithorn:BAAANQABCgUIBQAAAA==.Allila:BAABNQAECn8yAAICAAkKAyEgDwAAAwACAAkKAyEgDwAAAwAAAA==.Alynara:BAAANQADCgcIBwABNQAECgoKIwADALgMAA==.',
Am='Ambrozyn:BAAANQAECgUICwAAAA==.',
An='Anarariellea:BAAANQADCggJDgAAAA==.',
Ap='Apalrapzz:BAAANQADCgIJAgABNQAECgcIJgAEAOwIAA==.',
Aq='Aqari:BAAANQAECgYIEgAAAA==.',
Ar='Araxiie:BAAANQADCgIIAgAAAA==.Ardrelar:BAAANQAECgMIDAAAAA==.',
As='Asila:BAAANQAECgMIBAAAAA==.Astar:BAAANQAECgUIBQABNQAECgoKNgAFALchAA==.Astraea:BAAANQADCggIGwABNQAECgoKSQAGAGIfAA==.',
At='Athika:BAAANQADCggIDAAAAA==.',
Au='Auria:BAAANQAECgIIAwABNQAECgYIEgAHAAAAAA==.Autumnal:BAAANQADCgQIBgAAAA==.',
Az='Azralia:BAABNQAECn8XAAIIAAcKVBhLYgDxAQAIAAcKVBhLYgDxAQAAAA==.',
Ba='Baddock:BAAANQAECgYIDAAAAA==.Banzamakeher:BAAANQAECgQIBwAAAA==.',
Bb='Bbygee:BAAANQADCgUIBQAAAA==.',
Be='Bella:BAAANQAECggICAAAAA==.Benjamin:BAABNQAECn8uAAIJAAoK/hLVZAC8AQAJAAoK/hLVZAC8AQAAAA==.Bernixanders:BAAANQADCgMIAwAAAA==.Beyblade:BAAANQAECgEIAQAAAA==.',
Bl='Blacksun:BAAANQAECggIAwAAAA==.Blazinember:BAABNQAECn8xAAIKAAoKJhBqAgDEAQAKAAoKJhBqAgDEAQAAAA==.Blockhead:BAAANQAECgIIAwAAAA==.',
Bo='Bolonmixto:BAACNQAFFH8LAAMLAAYKRQ1LDAAqAQALAAYKRQ1LDAAqAQAMAAEK0wu9IABHAAA1AAQKfz8AAwsACgpdImQOAPsCAAsACgpdImQOAPsCAAwAAgrgHeCHAJMAAAAA.Boop:BAABNQAECn8iAAINAAkKZxXoCACtAQANAAkKZxXoCACtAQABNQAECgoKRgAOAMwhAA==.Borghamer:BAAANQAECgIIAgAAAA==.Borimor:BAAANQAECggICAABNQAECgoKLQAPAIsSAA==.',
Br='Brendee:BAAANQADCgcIFgAAAA==.Bromkin:BAAANQAECgIIAgAAAA==.',
['Bë']='Bëorn:BAAANQAECggIDgABNQAECgoKLQAPAIsSAA==.',
Ca='Calinor:BAAANQAECgEIAgAAAA==.Callihunt:BAAANQADCgYICAAAAA==.Calliopeh:BAAANQADCggIDwAAAA==.',
Ce='Cedriq:BAAANQAECgEIAgAAAA==.Ceran:BAABNQAECn8dAAIQAAkKbwxOPAA0AQAQAAkKbwxOPAA0AQAAAA==.Cereus:BAABNQAECn82AAMFAAoKtyFlBAA+AwAFAAoKtyFlBAA+AwARAAUK8xK6GQCTAAAAAA==.',
Ch='Chaelenge:BAABNQAECn8WAAIIAAoK1A36igB7AQAIAAoK1A36igB7AQAAAA==.Chasatail:BAAANQADCgcICAAAAA==.Chyran:BAABNQAECn8dAAIOAAgKCAM/IwGiAAAOAAgKCAM/IwGiAAAAAA==.',
Co='Coldncrispy:BAAANQAECgMIBAAAAA==.Coloratura:BAABNQAECn82AAISAAoK1RyPKwCGAgASAAoK1RyPKwCGAgAAAA==.',
Cr='Crimsonmoon:BAAANQAECgEIAQABNQAECgoKRgAOAMwhAA==.Crylessia:BAAANQAECgMIAwAAAA==.',
Da='Dagethon:BAAANQADCgUJEAAAAA==.Dandon:BAAANQADCgYIBgABNQAECgUICgAHAAAAAA==.Danfortesque:BAAANQADCgcIBwAAAA==.Danyah:BAAANQADCgUJBQABNQAECgoKOwATACoeAA==.Darkshådow:BAAANQAECgcIDQAAAA==.Daromiciah:BAAANQADCgYIBgAAAA==.',
De='Deathangels:BAAANQADCgQIBAAAAA==.Deftdirk:BAAANQADCgYIBgAAAA==.Delve:BAAANQADCgEIAQAAAA==.Demonbegone:BAAANQAECgEIAQAAAA==.Denvoker:BAAANQAECgEIBQAAAA==.Desdeanna:BAAANQABCgIIAgAAAA==.',
Di='Dissension:BAAANQAECgYIBAAAAA==.',
Do='Donpablo:BAAANQADCgcICgAAAA==.Doubtfire:BAABNQAECn8mAAMEAAcK7AhFXQCbAAAEAAcKbQNFXQCbAAAUAAMK/A/VVABgAAAAAA==.',
Dr='Dragii:BAAANQADCgYIBgAAAA==.',
Ed='Edelia:BAAANQAECgcIEAABNQAECgkJPwASANsgAA==.',
Eg='Egroeg:BAAANQADCgQIBAABNQAECgUICgAHAAAAAA==.',
Ei='Einar:BAAANQAECgQIBAAAAA==.',
Er='Eraessyr:BAAANQADCgQJBAAAAA==.Eragön:BAAANQADCgUIBQAAAA==.',
Fa='Fabin:BAAANQADCgEIAQAAAA==.Faithfulness:BAAANQAECgQIBgAAAA==.Fangz:BAABNQAECn8oAAIJAAgKWAeypgAZAQAJAAgKWAeypgAZAQAAAA==.',
Fl='Flarebeard:BAAANQADCgQIBAAAAA==.',
Fo='Forsëti:BAAANQAECggIDQAAAA==.',
Fr='Freakadeëk:BAAANQAECgIIBQAAAA==.Frierenn:BAABNQAECn8hAAMVAAgK8g8uwgAAAgAVAAgK8g8uwgAAAgAWAAEKAAC7RwA0AAAAAA==.Frosh:BAAANQAECgEIAgAAAA==.',
Ga='Gadodagaps:BAAANQADCgcIBwAAAA==.',
Gh='Ghouldottie:BAAANQAECgQIBAAAAA==.',
Gi='Gilidar:BAABNQAECn83AAIJAAkKZCL0NwDkAgAJAAkKZCL0NwDkAgAAAA==.Gillarria:BAAANQADCgcIDAAAAA==.',
Gl='Glori:BAAANQADCgYICgABNQAECgcIEwAHAAAAAA==.',
Gn='Gnomerdenis:BAAANQAECgcIDAAAAA==.',
Go='Goochiemon:BAAANQAECgMIAwAAAA==.',
Gr='Greenspawn:BAAANQAECggICQAAAA==.Grimmberly:BAAANQAECgUIEgABNQAECgoKHwAUAMIiAA==.Grimoire:BAABNQAECn8fAAMUAAoKwiJNCwC4AgAUAAoKwiJNCwC4AgAXAAEKDQaegQAdAAAAAA==.Gronna:BAAANQADCgYIBgABNQAECgkJMgACAAMhAA==.',
Gu='Guthunnel:BAAANQAECgUIBQAAAA==.Gutshadra:BAAANQAECgMIBQAAAA==.',
Ha='Haides:BAAANQADCgQIBAAAAA==.Hairybum:BAAANQABCgIIAgAAAA==.Hannibow:BAAANQAECgEIAQAAAA==.',
He='Hellgrim:BAAANQADCgMIAQABNQAECgoKHwAUAMIiAA==.Helpmee:BAAANQAECgYIBAAAAA==.',
Ho='Hoawatt:BAAANQAECgQIBgAAAA==.Holynova:BAAANQAECgEIAQABNQAECgcIHAAIAMQXAA==.Honkky:BAAANQAECgMIAwAAAA==.Hoofkick:BAAANQADCgQIBAAAAA==.Horaz:BAAANQADCgcIBwAAAA==.Howlingfury:BAAANQAECgEIAgAAAA==.',
Hu='Huuch:BAABNQAECn8aAAIPAAgKEwdepgC5AQAPAAgKEwdepgC5AQAAAA==.',
Ig='Ignee:BAABNQAECn87AAMTAAoKKh7ZBQCeAgATAAoKKh7ZBQCeAgAJAAMKUwwDJQGOAAAAAA==.Ignia:BAAANQAECggIEgAAAA==.Igris:BAAANQADCggICAAAAA==.',
Ir='Iremoon:BAABNQAECn8oAAQBAAgKBwtxPAARAQABAAgKBwtxPAARAQAYAAMKjAQbjAB3AAAZAAMKFgThqwB3AAAAAA==.',
Je='Jestyr:BAABNQAECn8ZAAMaAAgK9CKgBAD4AgAaAAgK9CKgBAD4AgAbAAIKEglBRwBpAAAAAA==.',
Ji='Jimba:BAAANQADCgQIBAAAAA==.Jimbah:BAAANQADCgMIAwAAAA==.Jiyao:BAABNQAECn8xAAMcAAoK9hh0GgC/AQAcAAoK9hh0GgC/AQAdAAMKVwWHQQBtAAAAAA==.',
Jo='Jojinn:BAAANQAECgEIAQAAAA==.',
Ka='Kaceya:BAAANQADCgYICAAAAA==.Kainarasa:BAAANQAECgYIBwABNQAECgoKRgAOAMwhAA==.Katarinea:BAABNQAECn8XAAIEAAgKzwaKYwBAAQAEAAgKzwaKYwBAAQAAAA==.Kaylle:BAABNQAECn8VAAIOAAkKIhHVjQCcAQAOAAkKIhHVjQCcAQAAAA==.',
Ke='Ketrus:BAAANQADCgQIBAABNQAECggIEgAHAAAAAA==.',
Kh='Khala:BAABNQAECn8cAAIeAAkKLgVEkQAjAQAeAAkKLgVEkQAjAQAAAA==.Khalessie:BAABNQAECn8xAAIfAAkK3xQmCADoAQAfAAkK3xQmCADoAQAAAA==.',
Ki='Killa:BAAANQAECgIIAgABNQAECgoKLwAJABkjAA==.Killerfire:BAAANQAECgEIAQAAAA==.Killim:BAAANQAECgYICQAAAA==.Kiselle:BAAANQADCgQIBAABNQAECgYIEgAHAAAAAA==.',
Kl='Klorick:BAABNQAECn8UAAIgAAoKOgQodQAVAQAgAAoKOgQodQAVAQABNQAECgoKLQAPAIsSAA==.',
Ko='Korkneelious:BAAANQAECgEIAQAAAA==.',
Kr='Krillian:BAAANQAECgEIAQAAAA==.Krissa:BAAANQADCgcIBwAAAA==.',
Ku='Kungfudru:BAAANQAECgMIAwAAAA==.',
Kw='Kwai:BAAANQADCgQIBQABNQAECgoKLQAPAIsSAA==.',
Ky='Kyla:BAAANQAECgUIDQAAAA==.Kyomu:BAAANQADCggICAABNQAECgoKRgAOAMwhAA==.',
La='Lazzarus:BAAANQAECgcIBwAAAA==.',
Le='Legio:BAAANQADCgQICAAAAA==.',
Li='Lineofsight:BAABNQAECn81AAIJAAkKdw7JeQCCAQAJAAkKdw7JeQCCAQAAAA==.Lipa:BAAANQADCgEIAQAAAA==.Liths:BAABNQAECn8nAAIaAAgKtxCfEwBzAQAaAAgKtxCfEwBzAQAAAA==.',
Lo='Loading:BAAANQAECgEIAQABNQAECgoKLgAgAN8XAA==.Lockdarkly:BAAANQAECgYICQAAAA==.Loko:BAAANQADCgEIAQAAAA==.',
Lu='Lululuvely:BAAANQAECgQIDAAAAA==.',
['Lí']='Lív:BAAANQAECgMIAwAAAA==.',
Ma='Machrona:BAAANQAECgQIBQAAAA==.Madelyn:BAAANQADCgUJBQAAAA==.Magecat:BAAANQAECgEIAQABNQAECggIEgAHAAAAAA==.Magejacob:BAAANQADCgYIDgAAAA==.Malena:BAEANQAECgcIEAAAAA==.Malendren:BAAANQAECgEIAQAAAA==.Margot:BAABNQAECn8YAAMWAAoK0xJeDAC3AQAWAAgKNxFeDAC3AQAVAAcKmRNdhACMAQAAAA==.Marksmann:BAAANQADCgYIBQAAAA==.Mawhriccio:BAAANQAECgEIAgAAAA==.',
Mc='Mcdavé:BAABNQAECn8nAAIgAAgKog54YwBEAQAgAAgKog54YwBEAQAAAA==.',
Me='Meerclar:BAAANQAECgUICwAAAA==.Melaila:BAABNQAECn9JAAIGAAoKYh+SEwAJAwAGAAoKYh+SEwAJAwAAAA==.Melysithea:BAABNQAECn8aAAIXAAkKgxDqIgDCAQAXAAkKgxDqIgDCAQABNQAECgoKSQAGAGIfAA==.',
Mi='Micheal:BAAANQAECggICAAAAA==.Midir:BAAANQAECgYIBwAAAA==.Mistymay:BAAANQADCgYJCwAAAA==.Miñitañk:BAAANQAECgUIEAAAAA==.',
Mo='Moldthinur:BAABNQAECn8mAAIhAAgK7hyVFQC+AQAhAAgK7hyVFQC+AQAAAA==.Mongrol:BAAANQAECgQIDQAAAA==.Monôpolyguy:BAABNQAECn8bAAIWAAcKbBVPEgBLAQAWAAcKbBVPEgBLAQAAAA==.Moonowl:BAAANQAECgUICgAAAA==.',
Mu='Mummrakhan:BAABNQAECn8WAAIeAAYKiAMi2wCJAAAeAAYKiAMi2wCJAAAAAA==.Murraya:BAAANQADCgMIAwAAAA==.',
My='Mythdalkurim:BAAANQADCgUICgAAAA==.',
Na='Naniel:BAABNQAECn80AAMTAAoK4CIhBABNAwATAAoK4CIhBABNAwAiAAEKRg3VLwA7AAAAAA==.Nazgrefry:BAAANQAECgcIDwAAAA==.',
Ne='Neb:BAABNQAECn84AAIeAAoKyBQAPwAIAgAeAAoKyBQAPwAIAgAAAA==.Necroy:BAAANQAECggIEQAAAA==.',
Ni='Niccee:BAABNQAECn8ZAAIEAAoKxgcGYwBCAQAEAAoKxgcGYwBCAQAAAA==.',
No='Noggindeez:BAAANQADCgIIAgABNQAECgoKHAAgAEcgAA==.Noodles:BAABNQAECn8UAAIOAAYKdRWUzACCAQAOAAYKdRWUzACCAQAAAA==.Nosebleeds:BAAANQAECgcICwAAAA==.',
Nu='Numerotres:BAAANQADCgQIBAAAAA==.Numerouno:BAABNQAECn8cAAMIAAcKxBe0hACMAQAIAAYKLxa0hACMAQAOAAYKaQXuDQG/AAAAAA==.',
['Nî']='Nîtara:BAAANQADCgEIAQAAAA==.',
Om='Omegasupreme:BAAANQABCgIJAgAAAA==.',
Oo='Ookthron:BAABNQAECn8mAAMJAAoK1BZobACmAQAJAAoK1BZobACmAQATAAMKuxILNQCNAAAAAA==.Ootred:BAAANQAECgIIAgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBwAAAA==.',
Pa='Palakin:BAAANQAECgIIAgAAAA==.Papasmurff:BAAANQAECgIIAgAAAA==.Parachute:BAAANQAECgUIDAAAAA==.Parky:BAAANQADCgUICAAAAA==.Pathald:BAAANQADCgQIBAAAAA==.',
Pe='Percival:BAABNQAECn8YAAIOAAoKGxEwrwDBAQAOAAoKGxEwrwDBAQAAAA==.',
Ph='Phreakadeek:BAAANQADCgcIDgABNQAECgcIGgAjAHETAA==.',
Pi='Pinheadgarry:BAAANQADCgIIAgAAAA==.Pizzaslice:BAABNQAECn9GAAIOAAoKzCHKGQDzAgAOAAoKzCHKGQDzAgAAAA==.',
Po='Pokimane:BAAANQAECgcIBwAAAA==.',
Pr='Praxiscannon:BAABNQAECn8WAAIeAAgKAgZOqADxAAAeAAgKAgZOqADxAAAAAA==.',
Pu='Pumpshire:BAABNQAECn8lAAIRAAoK/giQEAAdAQARAAoK/giQEAAdAQAAAA==.',
Pw='Pwongo:BAABNQAECn9UAAIXAAoKnSLdAgDSAwAXAAoKnSLdAgDSAwAAAA==.',
Qt='Qt:BAACNQAFFH8WAAIgAAUKqRzLCwAIAQAgAAUKqRzLCwAIAQA1AAQKfzAAAiAACgqCIrsQANwCACAACgqCIrsQANwCAAAA.',
Qu='Queue:BAAANQAECgcIEQAAAA==.Quilten:BAAANQAECgUIDAAAAA==.',
Ra='Raenii:BAABNQAECn8fAAIeAAkKLBS5RgDvAQAeAAkKLBS5RgDvAQABNQAECgkJPwASANsgAA==.Ramoth:BAAANQAECgcIEwAAAA==.Razelda:BAAANQAECggIDwAAAA==.',
Rh='Rhodas:BAAANQAECggIDgABNQAECgkJMQAJANIiAA==.',
Ri='Riandras:BAAANQADCgQIBAABNQAECgUICwAHAAAAAA==.Riannen:BAAANQADCgEIAQAAAA==.',
Ro='Roadwanderer:BAAANQAECgQICQAAAA==.Robbiedrake:BAAANQAECgEIAQABNQAECgoKRQANACIcAA==.Robbiemonk:BAABNQAECn9FAAINAAoKIhzVAwCFAgANAAoKIhzVAwCFAgAAAA==.Rodric:BAAANQAECggIDwABNQAECgoKLQAPAIsSAA==.',
Ru='Runetottem:BAABNQAECn8WAAMGAAkKRxHudgCnAQAGAAkKRxHudgCnAQAgAAIK0Q7M6QA8AAAAAA==.',
Rx='Rxeight:BAAANQADCgYIDAAAAA==.',
Sa='Sakura:BAAANQADCgIIAgAAAA==.Samarii:BAAANQAECgUICgAAAA==.Sannith:BAABNQAECn8hAAMVAAcK5RdfywDvAQAVAAcKqxVfywDvAQAWAAEKlh5pQwA9AAAAAA==.',
Sc='Scyllia:BAABNQAECn8mAAICAAkKwBgrFwCfAgACAAkKwBgrFwCfAgAAAA==.Scârlett:BAEANQADCgUICAABNQAECgcIEAAHAAAAAA==.',
Sh='Shadowklaw:BAAANQAECgQICAAAAA==.Shadowlich:BAAANQAECggICAAAAA==.Shadowsbane:BAAANQAECgEIAQAAAA==.Shamanoodles:BAABNQAECn8ZAAIGAAkKWRFQUgCyAQAGAAkKWRFQUgCyAQABNQAECgoKSQAGAGIfAA==.Shespawn:BAABNQAECn8VAAMBAAoK9RDpHwDOAQABAAoK9RDpHwDOAQAZAAEKAADkyAA3AAAAAA==.Shurie:BAABNQAECn8tAAIPAAoKixLpTAAhAgAPAAoKixLpTAAhAgAAAA==.Shâdê:BAAANQAECgMJCAAAAA==.Shânk:BAAANQAECgIIAgAAAA==.',
Si='Sinae:BAAANQADCggICAAAAA==.Sindrak:BAAANQABCgYICAAAAA==.',
Sl='Slipperybop:BAABNQAECn80AAIOAAkKjyHDLAAVAwAOAAkKjyHDLAAVAwABNQAECgQICQAHAAAAAA==.Slugbow:BAAANQADCgUIBQAAAA==.',
Sn='Snakeshadow:BAAANQADCggICAAAAA==.Snazzlehorn:BAAANQAECgQIBwAAAA==.Snifflenips:BAAANQAECgUIBQABNQAECgUICgAHAAAAAA==.Snoroll:BAAANQAECgEIAwAAAA==.',
So='Soldanis:BAAANQABCgEIAQAAAA==.',
Sp='Spazoff:BAAANQAECgcIDQAAAA==.Spyman:BAAANQADCgYICgAAAA==.',
Sq='Squissh:BAAANQAECgYIEAABNQAECgoKLQAPAIsSAA==.',
Sr='Srhubbabubba:BAAANQAECgQICQABNQAECggIHgASACYcAA==.',
St='Sternn:BAAANQAECgUIDwAAAA==.Straif:BAABNQAECn8YAAIOAAUKDwa/OQHDAAAOAAUKDwa/OQHDAAAAAA==.Strawberrÿ:BAABNQAECn8bAAIOAAkKSQm00gB2AQAOAAkKSQm00gB2AQAAAA==.',
Sw='Swolman:BAAANQADCgIIAgAAAA==.',
Sy='Sydonai:BAAANQAECggIDAAAAA==.Syreithada:BAAANQADCgcICQAAAA==.',
['Sì']='Sìnn:BAAANQADCgEIAQAAAA==.',
Ta='Talathra:BAABNQAECn8jAAMDAAoKuAzwIgA/AQADAAkKBAnwIgA/AQAPAAQKeg1xzQD9AAAAAA==.',
Td='Tddaddy:BAAANQADCgEIAQAAAA==.',
Te='Teddy:BAABNQAECn8bAAIUAAoKDxSEHQC1AQAUAAoKDxSEHQC1AQAAAA==.Tellah:BAEANQADCgQIBAABNQAFFAQIBgAGAGYiAA==.',
Th='Tharin:BAAANQAECgEIAQAAAA==.Thegodofwar:BAABNQAECn8xAAIJAAkK0iLDHQDGAgAJAAkK0iLDHQDGAgAAAA==.Thân:BAABNQAECn8WAAMkAAkKWw1ZEgD1AAAeAAgKRQwEcgBvAQAkAAUKVA5ZEgD1AAAAAA==.',
Ti='Tivon:BAAANQAECgEJAgAAAA==.',
To='Tonksie:BAAANQAECgUIDQAAAA==.',
Tt='Ttonkkalos:BAAANQAECgUICwAAAA==.',
Tw='Twomz:BAAANQADCgYIBgAAAA==.',
Um='Um:BAAANQADCgIIAgABNQAECgoKLgAgAN8XAA==.Umi:BAAANQAECggIEgAAAA==.Umzingeli:BAAANQADCggIEAAAAA==.',
Va='Varkbyte:BAAANQAECgMIAwAAAA==.Varock:BAAANQAECgIIAwABNQAECgoKRgAOAMwhAA==.',
Vi='Vindication:BAAANQAECgYIEwAAAA==.Viz:BAAANQAECgMIBAAAAA==.',
Vr='Vraul:BAABNQAECn8eAAIJAAoKrhAJqgC0AQAJAAoKrhAJqgC0AQAAAA==.',
Vu='Vulpain:BAAANQADCggIDgABNQAECgoKRgAOAMwhAA==.',
Vv='Vvnth:BAAANQAECgMIAwAAAA==.',
Wa='Washer:BAAANQAECgcICwAAAA==.',
Wh='Whiteangel:BAAANQAECgEIAQAAAA==.',
Wi='Wickedgood:BAAANQADCgQIBQAAAA==.Willywallace:BAAANQABCgMIAwAAAA==.',
Wo='Wolfowl:BAAANQADCgcILAAAAA==.Wolfrunner:BAAANQADCgEIAQABNQAECgoKMQATAHMhAA==.Wormon:BAAANQADCggICAAAAA==.',
Xa='Xaela:BAABNQAECn8cAAIbAAkK2A0uMwCoAQAbAAkK2A0uMwCoAQAAAA==.Xarous:BAAANQAECggIDgABNQAECgoKRgAOAMwhAA==.',
Xi='Xiabal:BAABNQAECn8pAAMXAAoKDBkUNQByAQAXAAcKSBQUNQByAQAEAAkKARTMPgAbAQAAAA==.',
Xw='Xweakling:BAAANQADCgYICAABNQAECgoKKgAiAMQYAA==.Xweekling:BAABNQAECn8qAAIiAAoKxBgGCQBNAgAiAAoKxBgGCQBNAgAAAA==.',
Yo='Yonnà:BAAANQAECgMIAwAAAA==.Yoshirou:BAAANQADCgIIAgAAAA==.Yourgrandma:BAABNQAECn8ZAAIZAAcKjAkaWADRAAAZAAcKjAkaWADRAAAAAA==.',
Yu='Yuxiong:BAAANQAECgMIBAAAAA==.',
Ze='Zedra:BAEANQADCggIGAABNQAECgcIEAAHAAAAAA==.Zedrâ:BAEANQADCggIDAABNQAECgcIEAAHAAAAAA==.Zerostar:BAABNQAECn8cAAMPAAkKhxIZSgAoAgAPAAkKhxIZSgAoAgAjAAIKIAaeEABrAAAAAA==.Zevon:BAAANQAECgQIBAABNQAECgUICwAHAAAAAA==.',
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
