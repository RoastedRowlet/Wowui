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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Paladin-Retribution','Unknown-Unknown','Mage-Arcane','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Warrior-Protection','DeathKnight-Frost','Shaman-Elemental','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warlock-Demonology','Hunter-Survival','Paladin-Protection','Priest-Shadow','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Druid-Balance','Druid-Restoration','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Evoker-Preservation','Shaman-Enhancement','Mage-Frost','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=53,date='2026-11-10',data={Al='Aldrik:BAAANQABCgQIBAAAAA==.Allunnadora:BAAANQADCgcIBwAAAA==.',
Am='Amarantha:BAAANQADCgEIAQAAAA==.Amellwind:BAABNQAECn8xAAIBAAoKjBiIQwA5AgABAAoKjBiIQwA5AgAAAA==.',
An='Antiosto:BAEBNQAECn87AAICAAoKrBluOQAhAgACAAoKrBluOQAhAgAAAA==.',
Ar='Ariosto:BAEANQAECgEICgABNQAECgoKOwACAKwZAA==.Arkadias:BAAANQABCgIIAgAAAA==.Arthea:BAAANQAECggIEAAAAA==.',
As='Asmmina:BAABNQAECn8ZAAIBAAoKfQhuuwCNAQABAAoKfQhuuwCNAQAAAA==.',
Ay='Ayrwen:BAABNQAECn8hAAIDAAgKZAi70QAfAQADAAgKZAi70QAfAQAAAA==.',
Az='Azarit:BAAANQADCgQIBAAAAA==.',
Ba='Babyluvv:BAAANQADCgIIAgAAAA==.Badgerbadger:BAAANQADCggIDwAAAA==.Baldr:BAAANQAECgQICQABNQAFFAIIAgAEAAAAAA==.',
Be='Beatrixx:BAABNQAECn8VAAIBAAkKhRxZNQBjAgABAAkKhRxZNQBjAgAAAA==.',
Bi='Bitterman:BAABNQAECn8lAAIFAAoKvxlahgBxAgAFAAoKvxlahgBxAgAAAA==.',
Bl='Bloodhardt:BAABNQAECn8uAAICAAoKERtjGwAVAgACAAoKERtjGwAVAgAAAA==.Bloodwynn:BAAANQAECgIIAgAAAA==.Bluekoolaid:BAABNQAECn8vAAMGAAkKNRuYFwCOAgAGAAkKNRuYFwCOAgAHAAUKqBOmEwDVAAAAAA==.',
Br='Bringbackbfa:BAAANQAECgQIBgAAAA==.Brynfyre:BAAANQABCgUIBQABNQAECgEIAwAEAAAAAA==.',
Bu='Buglord:BAABNQAECn8tAAIBAAoKnBNIagDUAQABAAoKnBNIagDUAQAAAA==.',
Bw='Bwonsamedí:BAAANQAECgIIAgAAAA==.',
Ce='Cellas:BAAANQADCgcIBwAAAA==.Cemeron:BAAANQAECgEIAQAAAA==.',
Ch='Cheba:BAABNQAECn83AAIIAAoKbBAAcQC4AQAIAAoKbBAAcQC4AQAAAA==.Chesleigh:BAAANQADCgcILAAAAA==.',
Ci='Cinderlight:BAABNQAECn8qAAIDAAoKBgdT0gAeAQADAAoKBgdT0gAeAQAAAA==.',
Cl='Clydas:BAAANQAECgEIAQAAAA==.',
Co='Cortock:BAACNQAFFH8FAAMJAAQKfAKWNgBwAAAJAAMKfAKWNgBwAAAKAAEKAACfBQAAAAA1AAQKf1AABAsACgqMF9ISAHYBAAkACgrrDlOdANMBAAsACAqWFdISAHYBAAoABAojEmgWAP0AAAAA.Corvell:BAABNQAECn8hAAIDAAkKARbuhgAZAgADAAkKARbuhgAZAgAAAA==.',
Cy='Cyssor:BAAANQADCgcIKwAAAA==.',
Da='Dagget:BAAANQAECgEIAQAAAA==.Dancingfox:BAAANQADCgcILAAAAA==.Dathdeath:BAABNQAECn8WAAIMAAcKzQT0cQDDAAAMAAcKzQT0cQDDAAAAAA==.Davlindhag:BAAANQAECgIIAgAAAA==.',
De='Deadquick:BAAANQADCgUIBQAAAA==.Demo:BAAANQADCgMIBgABNQAECgUIEAAEAAAAAA==.Demonhunted:BAAANQAECgEIAQAAAA==.Deros:BAAANQADCgMIAwAAAA==.Dezzii:BAAANQAECgUIDgAAAA==.',
Di='Dimitri:BAAANQABCgIIAgAAAA==.Dirtnappzz:BAABNQAECn8UAAINAAUKyRWKrwA0AQANAAUKyRWKrwA0AQAAAA==.Divanna:BAAANQAECgcIDQAAAA==.',
Do='Doroga:BAAANQABCgYIBgAAAA==.Dotdotded:BAAANQAECgMIAwAAAA==.',
Dr='Dragonkiller:BAABNQAECn8tAAIOAAkKDBYDGgChAQAOAAkKDBYDGgChAQAAAA==.Draik:BAAANQADCgcICgABNQAECgUIEAAEAAAAAA==.Driftless:BAABNQAECn8jAAMPAAgKnhXYFwAfAgAPAAgKnhXYFwAfAgAQAAEKyQNYqgAnAAAAAA==.',
Du='Dunce:BAABNQAECn8XAAIDAAgKLAZ/7ADzAAADAAgKLAZ/7ADzAAAAAA==.',
Eb='Ebsteen:BAAANQADCggIDwABNQAECgkJMQARALMWAA==.',
Ec='Eccentricity:BAAANQADCggICAAAAA==.',
El='Eladamir:BAAANQAECggICgABNQAECggIIwAPAJ4VAA==.Elementalhro:BAABNQAECn8uAAMIAAoKHRfXKQBsAgAIAAoKHRfXKQBsAgANAAYKWgOqsgCQAAAAAA==.Ellzik:BAAANQAECgUIEAAAAA==.',
Es='Escanorr:BAAANQAECggICAABNQAECgoKJQAFAL8ZAA==.Esthero:BAAANQADCgYIBgABNQAFFAIIAgAEAAAAAA==.',
Ev='Eviaris:BAAANQABCgEIAQAAAA==.',
Fa='Falorien:BAAANQAECgUIDAAAAA==.',
Fe='Fearne:BAAANQAECgQIBAAAAA==.Fedler:BAAANQADCgYIBgAAAA==.Felray:BAAANQAECgcIEgAAAA==.',
Fl='Flamingpax:BAAANQAECgUIEAAAAA==.Floinhunt:BAAANQAECgEIAQAAAA==.Fluffinbaked:BAAANQAECgUICAAAAA==.Fluffybúnny:BAAANQAECgEIAQAAAA==.',
Fr='Frankenberry:BAEANQAECgUICAABNQAECgoKOwACAKwZAA==.Freakadeek:BAAANQADCgYICwAAAA==.',
Fu='Furrious:BAAANQAECgQIBAAAAA==.',
Ga='Galekk:BAAANQAECgYIAQAAAA==.',
Gh='Ghostwolfer:BAAANQAECgEIAQAAAA==.Ghpwarlock:BAABNQAECn8yAAISAAoKcRQfYwAwAgASAAoKcRQfYwAwAgAAAA==.',
Gi='Gillgallad:BAAANQADCgMIAwAAAA==.',
Gl='Glasc:BAAANQAECgUIDQAAAA==.Glideyboi:BAAANQAECgEIAQAAAA==.',
Gn='Gnomagician:BAAANQAECgQIBgAAAA==.Gnowances:BAAANQAECgEIAQAAAA==.',
Go='Gorakk:BAABNQAECn8jAAIJAAgKXhbtfgAeAgAJAAgKXhbtfgAeAgAAAA==.',
Gr='Greenknight:BAAANQAECgEIAQAAAA==.Grimli:BAAANQADCgUIBQAAAA==.Grimstone:BAAANQAECgcICwAAAA==.Groggu:BAAANQADCgcIFgAAAA==.',
Gs='Gsnviper:BAAANQAECgUICAAAAA==.',
Ha='Hanakala:BAAANQAECgIIAQAAAA==.',
He='Helgore:BAAANQABCgIIAgABNQAECgIIAQAEAAAAAA==.',
Hi='Hintou:BAAANQAECgMIBAAAAA==.',
Ho='Hodart:BAABNQAECn8hAAMQAAoK/g7aHgAqAQAPAAYK/QyYZgBYAQAQAAgKJQ/aHgAqAQAAAA==.Hotsauce:BAAANQADCgEIAQAAAA==.',
Hu='Hurt:BAAANQAECgEIAQABNQAFFAMICgABAM0ZAA==.',
If='Ifucmeurdead:BAAANQADCgMIAwAAAA==.',
Ij='Ijudgethat:BAAANQAECgIIAwABNQAECgcIGgATAHETAA==.',
It='Itzli:BAABNQAECn8jAAMOAAoK2BzRFgCkAgAOAAoK2BzRFgCkAgABAAEKAABpWwEAAAABNQAFFAIIAgAEAAAAAA==.',
Iv='Ivee:BAAANQADCgEIAQABNQAFFAIIAgAEAAAAAA==.',
Ja='Jaser:BAAANQAECgUICQAAAA==.',
Je='Jellybeane:BAAANQADCgcIIAAAAA==.',
Jg='Jgwentworth:BAACNQAFFH8RAAIDAAcK5QtFCgArAQADAAcK5QtFCgArAQA1AAQKfzgAAwMACgqlH7hfAHoCAAMACgqlH7hfAHoCABQACApjBx8qAA0BAAAA.',
Jo='Jojen:BAABNQAECn8xAAMRAAkKsxaETQA8AgARAAkKsxaETQA8AgAVAAYKiwi/OQC5AAAAAA==.Jorj:BAABNQAECn9JAAIBAAoKRx9hIwCkAgABAAoKRx9hIwCkAgAAAA==.',
Ka='Katrex:BAAANQADCgcIJgAAAA==.Kavax:BAABNQAECn8zAAIWAAkKFRiSPQBuAgAWAAkKFRiSPQBuAgAAAA==.Kayos:BAACNQAFFH8FAAIXAAQKcQKEGgBoAAAXAAQKcQKEGgBoAAA1AAQKf1EAAxcACgonGiUVAGICABcACgonGiUVAGICABgACArECaA0AJ4BAAAA.',
Ke='Kefan:BAAANQAECgMIBQABNQAFFAQIBQAXAHECAA==.Kelz:BAABNQAECn8gAAMZAAoKXgn/bABfAQAZAAgK0Qn/bABfAQAMAAQKrAaNeQCtAAAAAA==.Keokea:BAAANQADCgQIBQABNQAECgcIFgABAA8IAA==.',
Kh='Khorne:BAABNQAECn8jAAICAAkKlxBaOwBGAQACAAkKlxBaOwBGAQAAAA==.',
Ki='Killdoom:BAAANQABCgcIBwAAAA==.Kimarah:BAAANQAFFAIIAgAAAA==.',
Kr='Kraven:BAAANQAECgQIBAAAAA==.Krica:BAAANQADCgMIBAAAAA==.Krillian:BAAANQAECgUICAAAAA==.Kronnah:BAAANQABCgYIBgAAAA==.',
Ku='Kula:BAABNQAECn8WAAIBAAcKDwj7uwAfAQABAAcKDwj7uwAfAQAAAA==.Kuwata:BAAANQADCgMIAwAAAA==.',
La='Largetha:BAAANQAECgQIBAABNQAFFAIIAgAEAAAAAA==.Latro:BAACNQAFFH8KAAIBAAMKzRnSGwCnAAABAAMKzRnSGwCnAAA1AAQKfzsAAwEACgoeIs0YADYDAAEACgoeIs0YADYDAA4AAQoYDJaMADIAAAAA.',
Le='Leenex:BAAANQAECgEIAQAAAA==.Lemiranas:BAABNQAECn8dAAISAAgKJBCaiwDKAQASAAgKJBCaiwDKAQAAAA==.Lepo:BAABNQAECn8qAAIPAAgKbA6cHADvAQAPAAgKbA6cHADvAQAAAA==.',
Lo='Lochnessy:BAAANQADCgEIAQABNQAECgoKLgABAH4ZAA==.',
Lu='Luciá:BAAANQAECgYICwABNQAFFAIIAgAEAAAAAA==.Lunden:BAABNQAECn8tAAQaAAoKoRSDJgC1AQAaAAoKoRSDJgC1AQAbAAMKchOwVQCxAAAcAAEKuwlgYAA0AAAAAA==.Luvalee:BAABNQAECn8bAAQdAAUKyQI0HQCUAAAdAAQKyQI0HQCUAAASAAUKuwEa+wBPAAAeAAEKAACIiAAbAAAAAA==.',
['Lë']='Lëësa:BAAANQAECgMIBAAAAA==.',
Ma='Magdalena:BAAANQAECgMICAABNQAFFAIIAgAEAAAAAA==.Magdaz:BAAANQABCgMIAgAAAA==.Magnificence:BAABNQAECn8qAAIDAAoKmQtdpQBtAQADAAoKmQtdpQBtAQAAAA==.Maladroit:BAAANQAECgEIAwABNQAFFAIIAgAEAAAAAA==.Maldus:BAABNQAECn8lAAIVAAoKQxwjEgDdAgAVAAoKQxwjEgDdAgABNQAFFAIIAgAEAAAAAA==.Mallacath:BAABNQAECn8kAAILAAoKVBPGEwDpAQALAAoKVBPGEwDpAQAAAA==.Marabet:BAAANQADCgEIAQAAAA==.Marloak:BAABNQAECn8YAAMbAAYKNxtiIgDHAQAbAAYKNxtiIgDHAQAaAAQKkgzzggDFAAAAAA==.Matalan:BAAANQADCgIIAgAAAA==.Maxxpower:BAAANQADCgUIBQAAAA==.',
Mc='Mcbain:BAAANQADCgcIBwAAAA==.Mccormick:BAAANQAECgIIBAABNQAFFAIIAgAEAAAAAA==.',
Me='Mendoza:BAAANQADCggICAAAAA==.Merrymanalow:BAABNQAECn8UAAINAAcKEwm7gQD2AAANAAcKEwm7gQD2AAAAAA==.Metaocalypse:BAAANQAECgQIBwAAAA==.',
Mi='Milough:BAABNQAECn8YAAMJAAkKGyCmUQCVAgAJAAkKGyCmUQCVAgAKAAIKtRvmHQCmAAAAAA==.Minkan:BAAANQAECgEIAwAAAA==.',
Mo='Moreraz:BAAANQAECgEIAQAAAA==.Mortdavol:BAAANQAECgIIAgAAAA==.',
Mu='Muteknight:BAAANQADCgYIDAABNQAECggIHgANAM8RAA==.',
My='Myhealsuck:BAAANQAECgQICQAAAA==.Mysweetheals:BAAANQAECgIIAgAAAA==.',
Na='Nathali:BAAANQAECgUICQAAAA==.',
Ne='Nergigante:BAAANQAECgIIAQAAAA==.Nessy:BAABNQAECn8uAAIBAAoKfhkvTQCHAgABAAoKfhkvTQCHAgAAAA==.',
Ni='Nicksamurai:BAABNQAECn8uAAIUAAkKxxW6HAAFAgAUAAkKxxW6HAAFAgAAAA==.Nikage:BAAANQADCggICAAAAA==.',
Nu='Nuggles:BAAANQADCgEIAQAAAA==.',
Ny='Nynaève:BAAANQAECgEIAQAAAA==.',
Om='Ombos:BAABNQAECn85AAIfAAoKvSIcAgCsAwAfAAoKvSIcAgCsAwAAAA==.',
Or='Ormeichi:BAAANQAECgUIDQAAAA==.Orticia:BAABNQAECn8aAAIRAAYKBwwgkAARAQARAAYKBwwgkAARAQAAAA==.',
Oz='Ozone:BAABNQAECn9AAAQgAAoKogcnFQCoAQAgAAoKKwcnFQCoAQANAAcKWwVrqABDAQAIAAQKugO9CwFRAAAAAA==.',
Pa='Palii:BAAANQAECgMIAwAAAA==.Pallypocket:BAABNQAECn82AAIWAAoKex9nCwBlAwAWAAoKex9nCwBlAwAAAA==.Pandahalf:BAAANQADCgcIJQAAAA==.Partyrocker:BAAANQADCgQIBAABNQAECgcIGgATAHETAA==.',
Ph='Phantom:BAAANQAECgQICgAAAA==.Pheldorai:BAABNQAECn8bAAISAAkKFA9OdgBkAQASAAkKFA9OdgBkAQABNQABCgEIAQAEAAAAAA==.Pheldrid:BAAANQADCgUIBQABNQABCgEIAQAEAAAAAA==.Phelnomie:BAABNQAECn8ZAAIBAAoKsgwRlQDeAQABAAoKsgwRlQDeAQABNQABCgEIAQAEAAAAAA==.Phàntoms:BAAANQADCgYIFQAAAA==.',
Pr='Pream:BAAANQAECgUICgABNQAECggIHgANAM8RAA==.Precipitus:BAABNQAECn8XAAMhAAcKfAkaHwDJAAAhAAYKAAsaHwDJAAAFAAYKiQW5DQGNAAAAAA==.Property:BAAANQAECgQICgABNQAFFAcIGgAiAHQeAA==.',
Pu='Puma:BAAANQAECgIIBgAAAA==.',
Ra='Radiance:BAAANQADCgcIBwAAAA==.Raerion:BAAANQADCggIDgAAAA==.Raevynn:BAABNQAECn84AAIRAAoKtQ5lYQD9AQARAAoKtQ5lYQD9AQAAAA==.Raiinzen:BAABNQAECn8qAAIjAAoKXBsnFAA4AgAjAAoKXBsnFAA4AgAAAA==.Rajun:BAAANQABCgYIBwAAAA==.Rawrgrr:BAAANQAECgQICwAAAA==.Razelka:BAABNQAECn8kAAIKAAoKfhHNCwC0AQAKAAoKfhHNCwC0AQAAAA==.',
Re='Redearslider:BAAANQAECgUIDwAAAA==.Rellix:BAAANQAECgQICQAAAA==.Remmulas:BAABNQAECn8rAAIhAAkK9BwLBQDMAgAhAAkK9BwLBQDMAgAAAA==.Repunzel:BAABNQAECn8nAAIDAAYKAQea9gDjAAADAAYKAQea9gDjAAAAAA==.',
Rh='Rhoku:BAAANQADCgYIBgAAAA==.',
Ri='Rightmeow:BAAANQAECgcIDAABNQAECgcIEgAEAAAAAA==.',
Ro='Rozco:BAABNQAECn8VAAIPAAYKHAxYMgAqAQAPAAYKHAxYMgAqAQAAAA==.',
Ru='Rubmywolf:BAAANQAECgYIEgAAAA==.Rumichan:BAAANQADCgcICwAAAA==.',
['Rä']='Rägnär:BAAANQABCgUIBgAAAA==.',
Sc='Scrapshot:BAAANQAECgEIAQAAAA==.',
Se='Serina:BAABNQAECn8oAAIBAAgKwxO/hQAAAgABAAgKwxO/hQAAAgAAAA==.',
Sh='Shadowmisty:BAABNQAECn8aAAIBAAYK1AN38gCyAAABAAYK1AN38gCyAAAAAA==.Shame:BAABNQAECn83AAMIAAkKqBoUKQBwAgAIAAkKqBoUKQBwAgANAAIK5wQY1QBXAAAAAA==.Shammu:BAAANQAECgIIAwABNQAECgUIEAAEAAAAAA==.Shamocalypse:BAAANQADCggIDQAAAA==.Shevah:BAABNQAECn8lAAIkAAkKxxtLCwB6AgAkAAkKxxtLCwB6AgAAAA==.',
Si='Sid:BAECNQAFFH8JAAMFAAYKqhj3JQBYAQAFAAUKrRn3JQBYAQAhAAEKnxTCDgBSAAA1AAQKf0wAAwUACgqPJaQEANQDAAUACgqPJaQEANQDACEABQqeImUQAGkBAAAA.',
So='Sophié:BAABNQAECn8XAAIeAAgK7xWmGgCXAQAeAAgK7xWmGgCXAQABNQAFFAIIAgAEAAAAAA==.Souxie:BAAANQAECgEIBQAAAA==.',
Sp='Sprout:BAABNQAECn8WAAIcAAcKKhrHIQBeAQAcAAcKKhrHIQBeAQAAAA==.',
St='Stabittha:BAAANQAECgIIAQAAAA==.Starislost:BAAANQADCgcIDAAAAA==.Starwìsh:BAAANQAECggIBAAAAA==.Stormcreaux:BAABNQAECn8WAAIHAAcKbQiUEwDWAAAHAAcKbQiUEwDWAAAAAA==.Stàrwish:BAAANQADCgQIBAAAAA==.',
Su='Suelock:BAABNQAECn8VAAISAAcKbwK10wCZAAASAAcKbwK10wCZAAAAAA==.Suldes:BAAANQAECgMIBAAAAA==.',
Sy='Syn:BAAANQADCggICAAAAA==.Synapse:BAABNQAECn8ZAAIGAAYKfwrDOQDCAAAGAAYKfwrDOQDCAAAAAA==.',
Ta='Taali:BAABNQAECn8WAAIDAAcKfgcr8ADtAAADAAcKfgcr8ADtAAAAAA==.Tala:BAAANQADCgEIAQAAAA==.Tarrant:BAAANQAECgQIBwAAAA==.Tarvil:BAABNQAECn8kAAQdAAoK4wvhDQBCAQASAAcKVwdbtgBiAQAdAAYKfA3hDQBCAQAeAAIKqARnZQBZAAAAAA==.',
Te='Teakat:BAAANQADCggICAAAAA==.Tesshi:BAAANQADCgYIBgAAAA==.',
Th='Thampe:BAAANQADCgEIAgAAAA==.Thjazi:BAABNQAECn8pAAINAAgKfxW1XQAJAgANAAgKfxW1XQAJAgAAAA==.Thomasten:BAABNQAECn8qAAMYAAoKSya+AQDMAwAYAAoKSya+AQDMAwAXAAUK2CVnJwC7AQABNQAFFAIICgAgAB8eAA==.Thomasthree:BAAANQAECgcIDAABNQAFFAIICgAgAB8eAA==.',
Tj='Tjorvi:BAEANQAECgQIBgABNQAECgUIBQAEAAAAAA==.',
Tr='Trampozo:BAAANQAECgMIAwAAAA==.Trenady:BAAANQAECgUICAAAAA==.Trent:BAAANQAECgYICAABNQAECgoKJQAFAL8ZAA==.Tricksï:BAAANQAECgEIAQAAAA==.',
Tu='Tuskdecay:BAAANQAECgUIBQAAAA==.',
Um='Umami:BAABNQAECn8gAAIIAAkKDxH6WQCWAQAIAAkKDxH6WQCWAQAAAA==.',
Ur='Urielseptim:BAAANQADCgEIAQAAAA==.',
Va='Valixanu:BAAANQAECgEIAQABNQAECgEIBQAEAAAAAA==.Vanderlay:BAABNQAECn8dAAIhAAYKuhQEEQCWAQAhAAYKuhQEEQCWAQAAAA==.',
Ve='Vellisara:BAAANQAECggIDQAAAA==.',
Vi='Viddar:BAAANQAECgUICwAAAA==.Viroqua:BAACNQAFFH8KAAIVAAUKAwytBgAdAQAVAAUKAwytBgAdAQA1AAQKfzYAAhUACgqmFhgcAGQCABUACgqmFhgcAGQCAAAA.',
Vo='Voxs:BAAANQADCgMIBgAAAA==.',
['Ví']='Ví:BAACNQAFFH8KAAIJAAQKHBTZGgA+AQAJAAQKHBTZGgA+AQA1AAQKfysAAgkACgp9IPceADwDAAkACgp9IPceADwDAAAA.',
Wi='Wiccamaster:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQADCgIIAgAAAA==.Wildfire:BAAANQADCgcICAAAAA==.Winkelsmom:BAABNQAECn8tAAIcAAoK2A7YIwBOAQAcAAoK2A7YIwBOAQAAAA==.',
Wo='Woobers:BAAANQAECggICgABNQAECgoKLQAFAKcgAA==.Woru:BAABNQAECn8bAAINAAkKiBO8PgDDAQANAAkKiBO8PgDDAQAAAA==.',
Wr='Wrathofangus:BAAANQAECgUICQAAAA==.',
Xa='Xarava:BAABNQAECn8jAAIIAAoKrA4IaQBjAQAIAAoKrA4IaQBjAQAAAA==.',
Ye='Yeetmachine:BAAANQAECgMICQABNQAECgoKJQAFAL8ZAA==.',
Yo='Yogisa:BAAANQAECgEIBAAAAA==.',
Yu='Yuna:BAAANQAECgQICAAAAA==.',
Za='Zarihanna:BAAANQAECgIIAgAAAA==.Zarijanna:BAAANQADCgcIBwAAAA==.Zarilenna:BAAANQADCgYICAAAAA==.Zarkanna:BAAANQADCgYIBwAAAA==.',
Ze='Zenogias:BAAANQAECgYIEQAAAA==.',
Zo='Zote:BAABNQAECn8xAAITAAkKSx4sBACtAgATAAkKSx4sBACtAgAAAA==.',
['ße']='ßenzyte:BAAANQAECgQICwAAAA==.',
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
