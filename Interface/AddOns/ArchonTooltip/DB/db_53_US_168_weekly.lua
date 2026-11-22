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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Paladin-Retribution','Unknown-Unknown','Mage-Arcane','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Paladin-Protection','Warrior-Arms','Warrior-Fury','Warrior-Protection','DeathKnight-Frost','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','DemonHunter-Vengeance','DemonHunter-Devourer','Warlock-Demonology','Hunter-Survival','Priest-Shadow','Paladin-Holy','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Balance','Druid-Restoration','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Evoker-Preservation','Shaman-Enhancement','Mage-Frost','Monk-Mistweaver','Druid-Feral',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=53,date='2026-11-17',data={Al='Aldrik:BAAANQABCgQIBAAAAA==.Allunnadora:BAAANQADCgcIBwAAAA==.',
Am='Amarantha:BAAANQADCgEIAQAAAA==.Amellwind:BAABNQAECn8xAAIBAAoKjBj2SwA3AgABAAoKjBj2SwA3AgAAAA==.',
An='Antiosto:BAEBNQAECn87AAICAAoKrBluOQAhAgACAAoKrBluOQAhAgAAAA==.',
Ar='Ariosto:BAEANQAECgEIBgABNQAECgoKOwACAKwZAA==.Arkadias:BAAANQABCgIIAgAAAA==.Arthea:BAAANQAECggIDgAAAA==.',
As='Asmmina:BAABNQAECn8ZAAIBAAoKfQhuuwCNAQABAAoKfQhuuwCNAQAAAA==.',
Ay='Ayrwen:BAABNQAECn8iAAIDAAkKjAifxwBGAQADAAkKjAifxwBGAQAAAA==.',
Az='Azarit:BAAANQADCgQIBAAAAA==.',
Ba='Babyluvv:BAAANQADCgIIAgAAAA==.Badgerbadger:BAAANQADCggIDwAAAA==.Baldr:BAAANQAECgQIBQABNQAFFAIIAgAEAAAAAA==.',
Be='Beatrixx:BAABNQAECn8YAAIBAAkKix6aMgB8AgABAAkKix6aMgB8AgAAAA==.',
Bi='Bitterman:BAABNQAECn8lAAIFAAoKvxlahgBxAgAFAAoKvxlahgBxAgAAAA==.',
Bl='Bloodhardt:BAABNQAECn8yAAICAAoKuxsSHAAdAgACAAoKuxsSHAAdAgAAAA==.Bloodwynn:BAAANQAECgIIAgAAAA==.Bluekoolaid:BAABNQAECn8zAAMGAAoKORmYFwCOAgAGAAoKORmYFwCOAgAHAAUKqBM4FQDVAAAAAA==.',
Br='Bringbackbfa:BAAANQAECgQIBAAAAA==.Brynfyre:BAAANQABCgUIBQABNQAECgIIAQAEAAAAAA==.',
Bu='Buglord:BAABNQAECn84AAIBAAoKoxPYbgDkAQABAAoKoxPYbgDkAQAAAA==.',
Bw='Bwonsamedí:BAAANQAECgIIAgAAAA==.',
Ce='Cellas:BAAANQADCgcIBwAAAA==.Cemeron:BAAANQABCgYIDgAAAA==.',
Ch='Cheba:BAABNQAECn87AAIIAAoKbBAAcQC4AQAIAAoKbBAAcQC4AQAAAA==.Chesleigh:BAAANQAECgEIAQAAAA==.',
Ci='Cinderlight:BAABNQAECn81AAMDAAoK6wdG0gA0AQADAAoKvQdG0gA0AQAJAAYKHQUzRgCNAAAAAA==.',
Cl='Clydas:BAAANQAECgEIAQAAAA==.',
Co='Cortock:BAACNQAFFH8FAAMKAAQKfAKWNgBwAAAKAAMKfAKWNgBwAAALAAEKAAATBgAAAAA1AAQKf1AABAwACgqMF+UUAHIBAAoACgrrDlOdANMBAAwACAqWFeUUAHIBAAsABAojEhEZAPUAAAAA.Corvell:BAABNQAECn8hAAIDAAkKARbuhgAZAgADAAkKARbuhgAZAgAAAA==.',
Cy='Cyssor:BAAANQAECgEIAQAAAA==.',
Da='Dagget:BAAANQAECgIIAwAAAA==.Dancingfox:BAAANQAECgEIAQAAAA==.Dathdeath:BAABNQAECn8bAAINAAcKdgXPdADQAAANAAcKdgXPdADQAAAAAA==.Davlindhag:BAAANQAECgIIAgAAAA==.',
De='Deadquick:BAAANQADCgUIBQAAAA==.Demo:BAAANQADCgMIBgABNQAECgUIEAAEAAAAAA==.Demonhunted:BAAANQAECgEIAgAAAA==.Deros:BAAANQADCgMIAwAAAA==.Dezzii:BAAANQAECgUIDgAAAA==.',
Di='Dimitri:BAAANQABCgIIAgAAAA==.Dirtnappzz:BAABNQAECn8YAAIOAAUKyRWKrwA0AQAOAAUKyRWKrwA0AQAAAA==.Divanna:BAAANQAECgcIDQAAAA==.',
Do='Doroga:BAAANQABCgYIBgAAAA==.Dotdotded:BAAANQAECgMIAwAAAA==.',
Dr='Dragonkiller:BAABNQAECn8xAAIPAAoKfhT1FgDbAQAPAAoKfhT1FgDbAQAAAA==.Draik:BAAANQADCgcICgABNQAECgUIEAAEAAAAAA==.Driftless:BAABNQAECn8jAAMQAAgKnhXYFwAfAgAQAAgKnhXYFwAfAgARAAEKyQNYqgAnAAAAAA==.',
Du='Dunce:BAABNQAECn8XAAIDAAgKLAam+wDwAAADAAgKLAam+wDwAAAAAA==.',
Eb='Ebsteen:BAAANQADCggIDwABNQAECgoKNQASAEkWAA==.',
Ec='Eccentricity:BAAANQADCggICAAAAA==.',
El='Eladamir:BAAANQAECggICwABNQAECggIIwAQAJ4VAA==.Elementalhro:BAABNQAECn8uAAMIAAoKHReyLgBnAgAIAAoKHReyLgBnAgAOAAYKWgMQvQCQAAAAAA==.Ellzik:BAAANQAECgUIDwAAAA==.',
En='Eneru:BAAANQAECgUIBQAAAA==.',
Es='Escanorr:BAAANQAECggICAABNQAECgoKJQAFAL8ZAA==.Esthero:BAAANQADCgYIBgABNQAFFAIIAgAEAAAAAA==.',
Ev='Eviaris:BAAANQABCgEIAQAAAA==.',
Fa='Falorien:BAAANQAECgUIDgAAAA==.',
Fe='Fearne:BAAANQAECgQIBAAAAA==.Fedler:BAAANQADCgYIBgAAAA==.Felray:BAABNQAECn8ZAAMTAAkKvAvJGgC/AAAUAAgKxwp7QgA7AQATAAcKCQjJGgC/AAAAAA==.',
Fl='Flamingpax:BAAANQAECgUIEAAAAA==.Floinhunt:BAAANQAECgEIAQAAAA==.Fluffinbaked:BAAANQAECgUICAAAAA==.Fluffybúnny:BAAANQAECgEIAQAAAA==.',
Fr='Frankenberry:BAEANQAECgUIBQABNQAECgoKOwACAKwZAA==.Freakadeek:BAAANQADCgYICwAAAA==.',
Fu='Furrious:BAAANQAECgQIBAAAAA==.',
Ga='Galekk:BAAANQAECgYIAQAAAA==.',
Gh='Ghostwolfer:BAAANQAECgEIAQAAAA==.Ghpwarlock:BAABNQAECn8yAAIVAAoKcRQfYwAwAgAVAAoKcRQfYwAwAgAAAA==.',
Gi='Gillgallad:BAAANQADCgMIAwAAAA==.',
Gl='Glasc:BAAANQAECgUIDgAAAA==.Glideyboi:BAAANQADCgcJBwAAAA==.',
Gn='Gnomagician:BAAANQAECgQIBgAAAA==.Gnowances:BAAANQADCggIDwAAAA==.',
Go='Gorakk:BAABNQAECn8jAAIKAAgKXhbtfgAeAgAKAAgKXhbtfgAeAgAAAA==.',
Gr='Greenknight:BAAANQADCgUIBQAAAA==.Grimli:BAAANQADCgUIBQAAAA==.Grimstone:BAAANQAECgcICgAAAA==.Groggu:BAAANQADCgcIFgAAAA==.',
Gs='Gsnviper:BAAANQAECgUICAAAAA==.',
Ha='Hanakala:BAAANQAECgIIAQAAAA==.',
He='Helgore:BAAANQABCgIIAgABNQAECgIIAQAEAAAAAA==.',
Hi='Hintou:BAAANQAECgMIAwAAAA==.',
Ho='Hodart:BAABNQAECn8pAAMRAAoK/g6aIAAlAQAQAAgKng0WbwBcAQARAAgKJQ+aIAAlAQAAAA==.Hotsauce:BAAANQADCgEIAQAAAA==.',
Hu='Hurt:BAAANQAECgEIAQABNQAFFAMICwABAM0ZAA==.',
If='Ifucmeurdead:BAAANQADCgMIAwAAAA==.',
Ij='Ijudgethat:BAAANQAECgIIAwABNQAECgcIGgAWAHETAA==.',
It='Itzli:BAABNQAECn8jAAMPAAoK2BzRFgCkAgAPAAoK2BzRFgCkAgABAAEKAAD/aAEAAAABNQAFFAIIAgAEAAAAAA==.',
Iv='Ivee:BAAANQADCgEIAQABNQAFFAIIAgAEAAAAAA==.',
Ja='Jaser:BAAANQAECgUICQAAAA==.',
Je='Jellybeane:BAAANQAECgEIAQAAAA==.',
Jg='Jgwentworth:BAACNQAFFH8RAAIDAAcK5QtuDAAnAQADAAcK5QtuDAAnAQA1AAQKfzgAAwMACgqlH7hfAHoCAAMACgqlH7hfAHoCAAkACApjB24tAA0BAAAA.',
Jo='Jojen:BAABNQAECn81AAMSAAoKSRaETQA8AgASAAoKSRaETQA8AgAXAAYKEglIPADBAAAAAA==.Jorj:BAABNQAECn9JAAIBAAoKRx+cKQCaAgABAAoKRx+cKQCaAgAAAA==.',
Ka='Katrex:BAAANQAECgEIAQAAAA==.Kavax:BAABNQAECn83AAIYAAoK+ReSPQBuAgAYAAoK+ReSPQBuAgAAAA==.Kayos:BAACNQAFFH8FAAIZAAQKcQKEGgBoAAAZAAQKcQKEGgBoAAA1AAQKf1YAAxkACgo+HhAOAMcCABkACgo+HhAOAMcCABQACArECaA0AJ4BAAAA.',
Ke='Kefan:BAAANQAECgMIAwABNQAFFAQIBQAZAHECAA==.Kelz:BAABNQAECn8lAAMaAAoKZgn/bABfAQAaAAgK0Qn/bABfAQANAAUKzQZkcADeAAAAAA==.Kelzexx:BAAANQAECgUIBQABNQAECgoKJQAaAGYJAA==.Keokea:BAAANQADCgQIBQABNQAECgcIGwABAMcJAA==.',
Kh='Khorne:BAABNQAECn8nAAICAAoKEBDoNAB0AQACAAoKEBDoNAB0AQAAAA==.',
Ki='Killdoom:BAAANQABCgcIBwAAAA==.Kimarah:BAAANQAFFAIIAgAAAA==.',
Kr='Kraven:BAAANQAECgQIBAAAAA==.Krica:BAAANQADCgMIBAAAAA==.Krillian:BAAANQAECgUIBwAAAA==.Kronnah:BAAANQABCgYIBgAAAA==.',
Ku='Kula:BAABNQAECn8bAAIBAAcKxwnsvwAyAQABAAcKxwnsvwAyAQAAAA==.Kuwata:BAAANQADCgMIAwAAAA==.',
La='Largetha:BAAANQAECgQIBAABNQAFFAIIAgAEAAAAAA==.Latro:BAACNQAFFH8LAAMBAAMKzRkvHwCkAAABAAMKzRkvHwCkAAAPAAEKAAAiJgAAAAA1AAQKfzwAAwEACgoeIs0YADYDAAEACgoeIs0YADYDAA8AAQoYDJaMADIAAAAA.',
Le='Lemiranas:BAABNQAECn8dAAIVAAgKJBCaiwDKAQAVAAgKJBCaiwDKAQAAAA==.Lepo:BAABNQAECn8qAAIQAAgKbA6cHADvAQAQAAgKbA6cHADvAQAAAA==.',
Lo='Lochnessy:BAAANQADCgEIAQABNQAECgoKLwABANQZAA==.',
Lu='Luciá:BAAANQAECgYICwABNQAFFAIIAgAEAAAAAA==.Lunden:BAABNQAECn8yAAQbAAoKqRQ2KQC2AQAbAAoKqRQ2KQC2AQAcAAMKchOwVQCxAAAdAAEKuwlgYAA0AAAAAA==.Luvalee:BAABNQAECn8eAAQeAAUKyQI0HQCUAAAeAAQKyQI0HQCUAAAVAAUKuwFNBAFPAAAfAAEKAACIiAAbAAAAAA==.',
['Lë']='Lëësa:BAAANQAECgIIAwAAAA==.',
Ma='Magdalena:BAAANQAECgMIBQABNQAFFAIIAgAEAAAAAA==.Magdaz:BAAANQABCgMIAgAAAA==.Magnificence:BAABNQAECn8vAAIDAAoKpAt0sgBrAQADAAoKpAt0sgBrAQAAAA==.Maladroit:BAAANQAECgEIAQABNQAFFAIIAgAEAAAAAA==.Maldus:BAABNQAECn8lAAIXAAoKQxwjEgDdAgAXAAoKQxwjEgDdAgABNQAFFAIIAgAEAAAAAA==.Mallacath:BAABNQAECn8lAAIMAAoKVBPGEwDpAQAMAAoKVBPGEwDpAQAAAA==.Marabet:BAAANQADCgEIAQAAAA==.Marloak:BAABNQAECn8YAAMcAAYKNxvvJQDDAQAcAAYKNxvvJQDDAQAbAAQKkgzzggDFAAAAAA==.Matalan:BAAANQADCgIIAgAAAA==.Maxxpower:BAAANQADCgUIBQAAAA==.',
Mc='Mcbain:BAAANQADCgcIBwAAAA==.Mccormick:BAAANQAECgIIAgABNQAFFAIIAgAEAAAAAA==.',
Me='Mendoza:BAAANQADCggICAAAAA==.Meresamun:BAAANQAECgUIBQAAAA==.Merrymanalow:BAABNQAECn8VAAIOAAcKEwlWiwD2AAAOAAcKEwlWiwD2AAAAAA==.Metaocalypse:BAAANQAECgQIBgAAAA==.',
Mi='Milough:BAABNQAECn8YAAMKAAkKGyCmUQCVAgAKAAkKGyCmUQCVAgALAAIKtRvqIACkAAAAAA==.',
Mo='Moreraz:BAAANQADCgYICAAAAA==.Mortdavol:BAAANQAECgIIAgAAAA==.',
Mu='Muteknight:BAAANQADCgYIDAABNQAECggIHgAOAM8RAA==.',
My='Myhealsuck:BAAANQAECgQIBAAAAA==.Mysweetheals:BAAANQAECgIIAgAAAA==.',
Na='Nathali:BAAANQAECgUICQAAAA==.',
Ne='Nergigante:BAAANQAECgIIAQAAAA==.Nessy:BAABNQAECn8vAAIBAAoK1BkvTQCHAgABAAoK1BkvTQCHAgAAAA==.',
Ni='Nicksamurai:BAABNQAECn8yAAIJAAoKJBS6HAAFAgAJAAoKJBS6HAAFAgAAAA==.Nikage:BAAANQADCggICAAAAA==.',
Nu='Nuggles:BAAANQADCgEIAQAAAA==.',
Ny='Nynaève:BAAANQAECgEIAQAAAA==.',
Om='Ombos:BAABNQAECn86AAIgAAoKvSJiAgCpAwAgAAoKvSJiAgCpAwAAAA==.',
Or='Ormeichi:BAAANQAECgUIDQAAAA==.Orticia:BAABNQAECn8fAAISAAYKeQzxmQAOAQASAAYKeQzxmQAOAQAAAA==.',
Os='Osnadh:BAAANQADCggICAAAAA==.',
Oz='Ozone:BAABNQAECn9IAAQhAAoKogfoFgCnAQAhAAoKKwfoFgCnAQAOAAcKWwVrqABDAQAIAAQKugPW5QBQAAAAAA==.',
Pa='Palii:BAAANQAECgMIAwAAAA==.Pallypocket:BAABNQAECn86AAMYAAoKiB/gDABfAwAYAAoKiB/gDABfAwADAAEKLwnHkwE3AAAAAA==.Pandahalf:BAAANQAECgEIAQAAAA==.Partyrocker:BAAANQADCgQIBAABNQAECgcIGgAWAHETAA==.',
Ph='Phantom:BAAANQAECgQIBgAAAA==.Pheldorai:BAABNQAECn8bAAIVAAkKFA/qfwBhAQAVAAkKFA/qfwBhAQABNQABCgEIAQAEAAAAAA==.Pheldrid:BAAANQADCgUIBQABNQABCgEIAQAEAAAAAA==.Phelnomie:BAABNQAECn8ZAAIBAAoKsgwRlQDeAQABAAoKsgwRlQDeAQABNQABCgEIAQAEAAAAAA==.Phil:BAAANQAECgEIAQAAAA==.Phixus:BAAANQAECgEIAQAAAA==.Phàntoms:BAAANQADCggIHAAAAA==.',
Pr='Pream:BAAANQAECgUICgABNQAECggIHgAOAM8RAA==.Precipitus:BAABNQAECn8bAAMiAAcKfAntIQDJAAAiAAYKAAvtIQDJAAAFAAYKiQVlFwGNAAAAAA==.Property:BAAANQAECgQICAABNQAFFAcIGgATAHQeAA==.',
Pu='Puma:BAAANQAECgIIAwAAAA==.',
Ra='Radiance:BAAANQADCgcIBwAAAA==.Raerion:BAAANQADCggIDgAAAA==.Raevynn:BAABNQAECn84AAISAAoKtQ5lYQD9AQASAAoKtQ5lYQD9AQAAAA==.Raiinzen:BAABNQAECn8vAAIjAAoKIxwnFAA4AgAjAAoKIxwnFAA4AgAAAA==.Rajun:BAAANQAECgIIAgAAAA==.Rawrgrr:BAAANQAECgQICQAAAA==.Razelka:BAABNQAECn8nAAILAAoKMBK8DAC4AQALAAoKMBK8DAC4AQAAAA==.',
Re='Redearslider:BAAANQAECgUICQAAAA==.Rellix:BAAANQAECgQICQABNQAECgUIGAAOAMkVAA==.Remmulas:BAABNQAECn8vAAIiAAoKERoLBQDMAgAiAAoKERoLBQDMAgAAAA==.Repunzel:BAABNQAECn8sAAIDAAYKJgfbAQHmAAADAAYKJgfbAQHmAAAAAA==.',
Rh='Rhoku:BAAANQADCgYIBgAAAA==.',
Ri='Rightmeow:BAAANQAECgcICgABNQAECgkJGQATALwLAA==.',
Ro='Rozco:BAABNQAECn8VAAIQAAYKHAxYMgAqAQAQAAYKHAxYMgAqAQAAAA==.',
Ru='Rubmywolf:BAABNQAECn8YAAIBAAcKshFyqgBdAQABAAcKshFyqgBdAQAAAA==.Rumichan:BAAANQADCgcICwAAAA==.',
['Rä']='Rägnär:BAAANQABCgUIBgAAAA==.',
Sc='Scrapshot:BAAANQAECgEIAgAAAA==.',
Se='Serina:BAABNQAECn8zAAIBAAoKSREpdwDPAQABAAoKSREpdwDPAQAAAA==.',
Sh='Shadowmisty:BAABNQAECn8aAAIBAAYK1APm/wCyAAABAAYK1APm/wCyAAAAAA==.Shame:BAACNQAFFH8HAAIIAAUKmQthEQBIAQAIAAUKmQthEQBIAQA1AAQKfz4AAwgACQo3GxAqAH8CAAgACQo3GxAqAH8CAA4AAgrnBP3fAFcAAAAA.Shammu:BAAANQAECgIIAwABNQAECgUIEAAEAAAAAA==.Shamocalypse:BAAANQADCggIDQAAAA==.Shevah:BAABNQAECn8pAAIkAAoKEhlLCwB6AgAkAAoKEhlLCwB6AgAAAA==.',
Si='Sid:BAECNQAFFH8JAAMFAAYKqhj3JQBYAQAFAAUKrRn3JQBYAQAiAAEKnxRvEABSAAA1AAQKf0wAAwUACgqPJaQEANQDAAUACgqPJaQEANQDACIABQqeIogSAGUBAAAA.',
So='Sophié:BAABNQAECn8XAAIfAAgK7xWmGgCXAQAfAAgK7xWmGgCXAQABNQAFFAIIAgAEAAAAAA==.Souxie:BAAANQAECgEIAQAAAA==.',
Sp='Splatlord:BAAANQAECgUIBQAAAA==.Sprout:BAABNQAECn8bAAIdAAcKsxoXIgBxAQAdAAcKsxoXIgBxAQAAAA==.',
Sq='Sqeeks:BAAANQADCggICAAAAA==.',
St='Stabittha:BAAANQAECgIIAQAAAA==.Starislost:BAAANQADCgcIDAAAAA==.Starwìsh:BAAANQAECggIAwAAAA==.Stevia:BAAANQAECgUIBQAAAA==.Stormcreaux:BAABNQAECn8bAAIHAAcKbQgfFQDWAAAHAAcKbQgfFQDWAAAAAA==.Stàrwish:BAAANQADCgYICgAAAA==.',
Su='Suelock:BAABNQAECn8ZAAIVAAcKlQKR2QCfAAAVAAcKlQKR2QCfAAAAAA==.Suldes:BAAANQAECgIIAwAAAA==.',
Sy='Syn:BAAANQADCggICAAAAA==.Synapse:BAABNQAECn8ZAAIGAAYKfwpbPQDCAAAGAAYKfwpbPQDCAAAAAA==.',
Ta='Taali:BAABNQAECn8bAAIDAAcK7gdK/ADvAAADAAcK7gdK/ADvAAAAAA==.Tala:BAAANQADCgEIAQAAAA==.Tarrant:BAAANQAECgQICQAAAA==.Tarvil:BAABNQAECn8pAAQeAAoK0gzuDQBYAQAVAAcKVwdbtgBiAQAeAAYKug7uDQBYAQAfAAIKqARnZQBZAAAAAA==.',
Te='Tesshi:BAAANQADCgYIBgAAAA==.',
Th='Thampe:BAAANQADCgEIAgAAAA==.Thjazi:BAABNQAECn8tAAIOAAoKHxInRgC8AQAOAAoKHxInRgC8AQAAAA==.Thomasten:BAACNQAFFH8GAAMUAAMK2BtFEABRAAAZAAEKSBzQGQBTAAAUAAIKaBtFEABRAAA1AAQKfyoAAxQACgpLJr4BAMwDABQACgpLJr4BAMwDABkABQrYJdwqALkBAAAA.Thomasthree:BAAANQAECgUIDQABNQAFFAcIBgAUANgbAA==.',
Tj='Tjorvi:BAEANQAECgQICQABNQAECgUIBQAEAAAAAA==.',
Tr='Trampozo:BAAANQAECgMIAwAAAA==.Trenady:BAAANQAECgUIBwAAAA==.Trent:BAAANQAECgYICAABNQAECgoKJQAFAL8ZAA==.Tricksï:BAAANQAECgEIAQAAAA==.',
Tu='Tuskdecay:BAAANQAECgUIBQAAAA==.',
Um='Umami:BAABNQAECn8kAAIIAAoK4BJPRAACAgAIAAoK4BJPRAACAgAAAA==.',
Ur='Urielseptim:BAAANQADCgEIAQAAAA==.',
Va='Vanderlay:BAABNQAECn8gAAIiAAcK5REEEQCWAQAiAAcK5REEEQCWAQAAAA==.',
Ve='Vellisara:BAAANQAECggIDAAAAA==.',
Vi='Viddar:BAAANQAECgUICQAAAA==.Viroqua:BAACNQAFFH8KAAIXAAUKAwzTBwAdAQAXAAUKAwzTBwAdAQA1AAQKfzkAAhcACgpzFxgcAGQCABcACgpzFxgcAGQCAAAA.',
Vo='Voxs:BAAANQADCgMIBgAAAA==.',
['Ví']='Ví:BAACNQAFFH8KAAIKAAQKHBTZGgA+AQAKAAQKHBTZGgA+AQA1AAQKfysAAgoACgp9IPceADwDAAoACgp9IPceADwDAAAA.',
Wi='Wiccamaster:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQADCgIIAgAAAA==.Wildfire:BAAANQADCgcICAAAAA==.Winkelsmom:BAABNQAECn84AAMcAAoKUxl8MABsAQAcAAYKMxR8MABsAQAdAAoK2A4zJwBMAQAAAA==.',
Wo='Woobers:BAAANQAECggICgABNQAECgoKLQAFAKcgAA==.Woru:BAABNQAECn8gAAIOAAkKlRWHOwDmAQAOAAkKlRWHOwDmAQAAAA==.',
Wr='Wrathofangus:BAAANQAECgUIBQAAAA==.',
Xa='Xarava:BAABNQAECn8oAAIIAAoK5Q+waQB4AQAIAAoK5Q+waQB4AQAAAA==.',
Ye='Yeetmachine:BAAANQAECgMIBQABNQAECgoKJQAFAL8ZAA==.',
Yo='Yogisa:BAAANQAECgEIAQAAAA==.',
Yu='Yuna:BAAANQAECgQIBgAAAA==.',
Za='Zarihanna:BAAANQAECgIIAgAAAA==.Zarijanna:BAAANQADCgcIBwAAAA==.Zarilenna:BAAANQADCgYICAAAAA==.Zarkanna:BAAANQADCgYIBwAAAA==.',
Ze='Zenogias:BAAANQAECgUIEgAAAA==.',
Zo='Zote:BAABNQAECn81AAIWAAoK5xzEAwBhAgAWAAoK5xzEAwBhAgAAAA==.',
['ße']='ßenzyte:BAAANQAECgQIDQAAAA==.',
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
