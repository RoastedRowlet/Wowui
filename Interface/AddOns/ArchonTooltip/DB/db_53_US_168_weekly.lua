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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Priest-Shadow','Mage-Arcane','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Paladin-Retribution','Warrior-Protection','Warrior-Arms','Unknown-Unknown','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warlock-Demonology','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Druid-Balance','Druid-Restoration','Druid-Guardian','Shaman-Elemental','Paladin-Protection','Evoker-Preservation','Shaman-Enhancement','DemonHunter-Vengeance','Monk-Mistweaver','Warrior-Fury','Mage-Frost','Druid-Feral','Warlock-Destruction','Warlock-Affliction','Hunter-Survival',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=53,date='2026-10-20',data={Al='Aldrik:BAAANQABCgQIBAAAAA==.Allunnadora:BAAANQADCgcIBwAAAA==.',
Am='Amarantha:BAAANQADCgEIAQAAAA==.Amellwind:BAABNQAECn8mAAIBAAkKRhaoGQCzAQABAAkKRhaoGQCzAQAAAA==.',
An='Antiosto:BAEBNQAECn8yAAICAAoKfBNuOQAhAgACAAoKfBNuOQAhAgAAAA==.',
Ar='Ariosto:BAEANQAECgEIBQABNQAECgoKMgACAHwTAA==.Arkadias:BAAANQABCgIIAgAAAA==.Arthea:BAAANQAECgUICQAAAA==.',
As='Asmmina:BAABNQAECn8WAAIBAAgKiAhuuwCNAQABAAgKiAhuuwCNAQAAAA==.',
Ay='Ayrwen:BAAANQAECgUICAAAAA==.',
Ba='Babyluvv:BAAANQADCgIIAgAAAA==.Badgerbadger:BAAANQADCggIDwAAAA==.Baldr:BAAANQAECgQIBQABNQAECgoKIgADAPsYAA==.',
Be='Beatrixx:BAAANQADCgMIAwAAAA==.',
Bi='Bitterman:BAABNQAECn8hAAIEAAoKxhhahgBxAgAEAAoKxhhahgBxAgAAAA==.',
Bl='Bloodhardt:BAABNQAECn8gAAICAAkKohihDwBmAQACAAkKohihDwBmAQAAAA==.Bluekoolaid:BAABNQAECn8rAAMFAAgKOxyYFwCOAgAFAAgKOxyYFwCOAgAGAAUKqBM0BwD2AAAAAA==.',
Br='Bringbackbfa:BAAANQAECgIIAgAAAA==.Brynfyre:BAAANQABCgUIBQAAAA==.',
Bu='Buglord:BAABNQAECn8gAAIBAAgKhhPvSgAdAQABAAgKhhPvSgAdAQAAAA==.',
Bw='Bwonsamedí:BAAANQAECgIIAgAAAA==.',
Ce='Cellas:BAAANQADCgcIBwAAAA==.Cemeron:BAAANQABCgYIDgAAAA==.',
Ch='Cheba:BAABNQAECn8pAAIHAAkK3BD2OwD5AAAHAAkK3BD2OwD5AAAAAA==.Chesleigh:BAAANQADCgYIHwAAAA==.',
Ci='Cinderlight:BAABNQAECn8dAAIIAAgKBAdc7QBBAQAIAAgKBAdc7QBBAQAAAA==.',
Co='Cortock:BAABNQAECn8yAAMJAAoKxxRvFwC1AQAJAAYKtxlvFwC1AQAKAAoK6w4NUAD9AAAAAA==.Corvell:BAABNQAECn8aAAIIAAgKERfuhgAZAgAIAAgKERfuhgAZAgAAAA==.',
Cy='Cyssor:BAAANQADCgYIHgAAAA==.',
Da='Dagget:BAAANQADCgMIAwAAAA==.Dancingfox:BAAANQADCgYIHwAAAA==.Dathdeath:BAAANQAECgIIBwAAAA==.Davlindhag:BAAANQAECgIIAgAAAA==.',
De='Deadquick:BAAANQADCgUIBQAAAA==.Demo:BAAANQADCgMIBQABNQAECgIIAwALAAAAAA==.Demonhunted:BAAANQADCgIIAgAAAA==.Deros:BAAANQADCgMIAwAAAA==.Dezzii:BAAANQAECgUIDgAAAA==.',
Di='Dimitri:BAAANQABCgIIAgAAAA==.Dirtnappzz:BAAANQAECgQIDwAAAA==.Divanna:BAAANQAECgIIAgAAAA==.',
Do='Doroga:BAAANQABCgYIBgAAAA==.Dotdotded:BAAANQAECgMIAwAAAA==.',
Dr='Dragonkiller:BAABNQAECn8jAAIMAAgKgxU1JgAaAgAMAAgKgxU1JgAaAgAAAA==.Draik:BAAANQADCgEIAQABNQAECgIIAwALAAAAAA==.Driftless:BAABNQAECn8jAAMNAAgKnhXYFwAfAgANAAgKnhXYFwAfAgAOAAEKyQNYqgAnAAAAAA==.',
Du='Dunce:BAAANQAECgMIBgAAAA==.',
Eb='Ebsteen:BAAANQADCgcIBwABNQAECggIJgAPANwWAA==.',
Ec='Eccentricity:BAAANQADCggICAAAAA==.',
El='Eladamir:BAAANQADCgEIAQABNQAECggIIwANAJ4VAA==.Elementalhro:BAAANQAECgcIEgAAAA==.Ellzik:BAAANQAECgUIBwAAAA==.',
Es='Escanorr:BAAANQADCgQIBAABNQAECgoKIQAEAMYYAA==.Esthero:BAAANQADCgYIBgABNQAECgoKIgADAPsYAA==.',
Ev='Eviaris:BAAANQABCgEIAQAAAA==.',
Fa='Falorien:BAAANQAECgMIBQAAAA==.',
Fe='Felray:BAAANQAECgcIEQAAAA==.',
Fl='Flamingpax:BAAANQADCgUIEQABNQAECgIIAwALAAAAAA==.Floinhunt:BAAANQAECgEIAQAAAA==.Fluffinbaked:BAAANQAECgUICAAAAA==.Fluffybúnny:BAAANQADCgYIGwAAAA==.',
Fr='Frankenberry:BAEANQAECgQIBQABNQAECgoKMgACAHwTAA==.Freakadeek:BAAANQADCgYICwAAAA==.',
Fu='Furrious:BAAANQAECgQIBAAAAA==.',
Ga='Galekk:BAAANQAECgYIAQAAAA==.',
Gh='Ghostwolfer:BAAANQAECgEIAQAAAA==.Ghpwarlock:BAABNQAECn8rAAIQAAoKcRQfYwAwAgAQAAoKcRQfYwAwAgAAAA==.',
Gl='Glasc:BAAANQAECgUICgAAAA==.Glideyboi:BAAANQADCgcJBwAAAA==.',
Gn='Gnomagician:BAAANQAECgQIBAAAAA==.Gnowances:BAAANQADCgcIBwAAAA==.',
Go='Gorakk:BAABNQAECn8jAAIKAAgKXhbtfgAeAgAKAAgKXhbtfgAeAgAAAA==.',
Gr='Greenknight:BAAANQADCgUIBQAAAA==.Grimli:BAAANQADCgUIBQAAAA==.Grimstone:BAAANQAECgcICgAAAA==.Groggu:BAAANQADCgcIFgAAAA==.',
Gs='Gsnviper:BAAANQADCggIDAAAAA==.',
Ha='Hanakala:BAAANQAECgIIAQAAAA==.',
He='Helgore:BAAANQABCgIIAgABNQAECgEIAQALAAAAAA==.',
Hi='Hintou:BAAANQAECgMIAwAAAA==.',
Ho='Hodart:BAAANQAECgcIEAAAAA==.Hotsauce:BAAANQADCgEIAQAAAA==.',
Hu='Hurt:BAAANQAECgEIAQABNQAFFAIIBQABAKgKAA==.',
If='Ifucmeurdead:BAAANQADCgMIAwAAAA==.',
Ij='Ijudgethat:BAAANQAECgIIAwABNQAECgMIBgALAAAAAA==.',
It='Itzli:BAABNQAECn8bAAIMAAoKehnRFgCkAgAMAAoKehnRFgCkAgABNQAECgoKIgADAPsYAA==.',
Iv='Ivee:BAAANQADCgEIAQABNQAECgoKIgADAPsYAA==.',
Ja='Jaser:BAAANQAECgQIBAAAAA==.',
Je='Jellybeane:BAAANQADCgUIGQAAAA==.',
Jg='Jgwentworth:BAACNQAFFH8OAAIIAAQKdRIdCADiAAAIAAQKdRIdCADiAAA1AAQKfygAAggACgpeG7hfAHoCAAgACgpeG7hfAHoCAAAA.',
Jo='Jojen:BAABNQAECn8mAAMPAAgK3BaETQA8AgAPAAgK3BaETQA8AgADAAIKwgzFawBUAAAAAA==.Jorj:BAABNQAECn8uAAIBAAkKCR+oBwBNAgABAAkKCR+oBwBNAgAAAA==.',
Ka='Katrex:BAAANQADCgYIHwAAAA==.Kavax:BAABNQAECn8oAAIRAAgKvBmSPQBuAgARAAgKvBmSPQBuAgAAAA==.Kayos:BAABNQAECn81AAMSAAoKDRN7CQCuAQASAAgKmRd7CQCuAQATAAgKxAmgNACeAQAAAA==.',
Ke='Kefan:BAAANQAECgMIAwABNQAECgoKNQASAA0TAA==.Kelz:BAABNQAECn8XAAIUAAcKswr/bABfAQAUAAcKswr/bABfAQAAAA==.Keokea:BAAANQADCgQIBQABNQAECgMIBwALAAAAAA==.',
Kh='Khorne:BAABNQAECn8YAAICAAgKGhByUQCvAQACAAgKGhByUQCvAQAAAA==.',
Ki='Killdoom:BAAANQABCgcIBwAAAA==.Kimarah:BAAANQADCgcIBwABNQAECgoKIgADAPsYAA==.',
Kr='Kraven:BAAANQAECgQIBAAAAA==.Krica:BAAANQADCgMJBAAAAA==.Krillian:BAAANQAECgEIAQAAAA==.Kronnah:BAAANQABCgYIBgAAAA==.',
Ku='Kula:BAAANQAECgMIBwAAAA==.Kuwata:BAAANQADCgMIAwAAAA==.',
La='Largetha:BAAANQAECgQIBAABNQAECgoKIgADAPsYAA==.Latro:BAACNQAFFH8FAAIBAAIKqAplEQCAAAABAAIKqAplEQCAAAA1AAQKfzEAAwEACgpFH80YADYDAAEACgpFH80YADYDAAwAAQoYDJaMADIAAAAA.',
Le='Leenex:BAAANQADCggIDQAAAA==.Lemiranas:BAABNQAECn8aAAIQAAgKJBCaiwDKAQAQAAgKJBCaiwDKAQAAAA==.Lepo:BAABNQAECn8jAAINAAgKbA6cHADvAQANAAgKbA6cHADvAQAAAA==.',
Lo='Lochnessy:BAAANQADCgEIAQABNQAECggIJAABAK8ZAA==.',
Lu='Lunden:BAABNQAECn8gAAQVAAgKMxMOHAAGAQAVAAgKMxMOHAAGAQAWAAMKchOwVQCxAAAXAAEKuwlgYAA0AAAAAA==.Luvalee:BAAANQAECgQIDgAAAA==.',
['Lë']='Lëësa:BAAANQADCggIIgAAAA==.',
Ma='Magdalena:BAAANQAECgMIBQABNQAECgoKIgADAPsYAA==.Magdaz:BAAANQABCgMIAgAAAA==.Magnificence:BAABNQAECn8eAAIIAAgKmguweADXAAAIAAgKmguweADXAAAAAA==.Maladroit:BAAANQAECgEIAQABNQAECgoKIgADAPsYAA==.Maldus:BAABNQAECn8iAAIDAAoK+xgjEgDdAgADAAoK+xgjEgDdAgAAAA==.Mallacath:BAABNQAECn8YAAIJAAgKcBXGEwDpAQAJAAgKcBXGEwDpAQAAAA==.Marabet:BAAANQADCgEIAQAAAA==.Marloak:BAAANQAECgQIEAAAAA==.Matalan:BAAANQADCgIIAgAAAA==.Maxxpower:BAAANQADCgUIBQAAAA==.',
Mc='Mcbain:BAAANQADCgcIBwAAAA==.Mccormick:BAAANQAECgIIAgABNQAECgoKIgADAPsYAA==.',
Me='Merrymanalow:BAAANQAECgIIAgAAAA==.Metaocalypse:BAAANQAECgQIBgAAAA==.',
Mi='Milough:BAAANQAFFAEIAQAAAA==.',
Mo='Moreraz:BAAANQADCgYICAAAAA==.Mortdavol:BAAANQAECgEIAQAAAA==.',
Mu='Muteknight:BAAANQADCgYIDAABNQAECggIGQAYAJwOAA==.',
My='Myhealsuck:BAAANQAECgMIBAAAAA==.Mysweetheals:BAAANQAECgIIAgAAAA==.',
Ne='Nergigante:BAAANQAECgEIAQAAAA==.Nessy:BAABNQAECn8kAAIBAAgKrxkvTQCHAgABAAgKrxkvTQCHAgAAAA==.',
Ni='Nicksamurai:BAABNQAECn8jAAIZAAgK6xW6HAAFAgAZAAgK6xW6HAAFAgAAAA==.Nikage:BAAANQADCggICAAAAA==.',
Nu='Nuggles:BAAANQADCgEIAQAAAA==.',
Ny='Nynaève:BAAANQADCgcIGQAAAA==.',
Om='Ombos:BAABNQAECn8qAAIaAAoKSiEQBQBcAwAaAAoKSiEQBQBcAwAAAA==.',
Or='Ormeichi:BAAANQAECgUIDQAAAA==.Orticia:BAAANQAECgUICgAAAA==.',
Oz='Ozone:BAABNQAECn8uAAQbAAoKXwgXCABzAQAbAAkKpQUXCABzAQAYAAcKWwVrqABDAQAHAAQKugPDiABGAAAAAA==.',
Pa='Palii:BAAANQADCgUIBQAAAA==.Pallypocket:BAABNQAECn8kAAIRAAoKfRpWFQCqAQARAAoKfRpWFQCqAQAAAA==.Pandahalf:BAAANQADCgYIGwAAAA==.Partyrocker:BAAANQADCgQIBAABNQAECgMIBgALAAAAAA==.',
Ph='Pheldorai:BAAANQAECgYIEAABNQABCgEIAQALAAAAAA==.Pheldrid:BAAANQADCgUIBQABNQABCgEIAQALAAAAAA==.Phelnomie:BAABNQAECn8VAAIBAAgKzQoRlQDeAQABAAgKzQoRlQDeAQABNQABCgEIAQALAAAAAA==.Phàntoms:BAAANQADCgYIFQAAAA==.',
Pr='Pream:BAAANQAECgMIAwABNQAECggIGQAYAJwOAA==.Precipitus:BAAANQAECgUICAAAAA==.Property:BAAANQAECgQICAABNQAFFAcIGQAcAHQeAA==.',
Pu='Puma:BAAANQAECgIIAwAAAA==.',
Ra='Radiance:BAAANQADCgcIBwAAAA==.Raerion:BAAANQADCggIDgAAAA==.Raevynn:BAABNQAECn8wAAIPAAoKNg5lYQD9AQAPAAoKNg5lYQD9AQAAAA==.Raiinzen:BAABNQAECn8gAAIdAAgK5RsnFAA4AgAdAAgK5RsnFAA4AgAAAA==.Rajun:BAAANQABCgYIBwAAAA==.Rawrgrr:BAAANQAECgQICQAAAA==.Razelka:BAABNQAECn8YAAIeAAgKJA3vBwASAQAeAAgKJA3vBwASAQAAAA==.',
Re='Redearslider:BAAANQAECgUICQAAAA==.Rellix:BAAANQAECgQICQAAAA==.Remmulas:BAABNQAECn8gAAIfAAgKVh4LBQDMAgAfAAgKVh4LBQDMAgAAAA==.Repunzel:BAABNQAECn8XAAIIAAUKLwaWpgCUAAAIAAUKLwaWpgCUAAAAAA==.',
Rh='Rhoku:BAAANQADCgYIBgAAAA==.',
Ri='Rightmeow:BAAANQAECgQICAABNQAECgcIEQALAAAAAA==.',
Ro='Rozco:BAAANQAECgQIDgAAAA==.',
Ru='Rubmywolf:BAAANQAECgIIBQAAAA==.',
['Rä']='Rägnär:BAAANQABCgUIBgAAAA==.',
Sc='Scrapshot:BAAANQADCgMIBAAAAA==.',
Se='Serina:BAABNQAECn8gAAIBAAgK1hLHTQAXAQABAAgK1hLHTQAXAQAAAA==.',
Sh='Shadowmisty:BAAANQAECgQICQAAAA==.Shame:BAABNQAECn8fAAIHAAgK+BmnIwBWAQAHAAgK+BmnIwBWAQAAAA==.Shammu:BAAANQAECgIIAwAAAA==.Shamocalypse:BAAANQADCggIDQAAAA==.Shevah:BAABNQAECn8fAAIgAAgKsRlLCwB6AgAgAAgKsRlLCwB6AgAAAA==.',
Si='Sid:BAECNQAFFH8IAAIEAAUKrRn3JQBYAQAEAAUKrRn3JQBYAQA1AAQKfz0AAwQACgp/JaQEANQDAAQACgp/JaQEANQDAB8AAwr3IcEGAC8BAAAA.',
So='Sophié:BAAANQAECgUIDgABNQAECgoKIgADAPsYAA==.Souxie:BAAANQADCgYIGgAAAA==.',
Sp='Sprout:BAAANQAECgIIBwAAAA==.',
St='Stabittha:BAAANQAECgEIAQAAAA==.Starislost:BAAANQADCgcIBwAAAA==.Stormcreaux:BAAANQAECgIIBwAAAA==.',
Su='Suelock:BAAANQAECgIIBwAAAA==.Suldes:BAAANQADCggIJwAAAA==.',
Sy='Syn:BAAANQADCggICAAAAA==.Synapse:BAAANQAECgQIEAAAAA==.',
Ta='Taali:BAAANQAECgIIBgAAAA==.Tala:BAAANQADCgEIAQAAAA==.Tarrant:BAAANQADCgMIBQAAAA==.Tarvil:BAABNQAECn8YAAQQAAcKVwdbtgBiAQAQAAcKVwdbtgBiAQAhAAIKqARnZQBZAAAiAAEKUwX5MwArAAAAAA==.',
Te='Tesshi:BAAANQADCgYIBgAAAA==.',
Th='Thampe:BAAANQADCgEIAgAAAA==.Thjazi:BAABNQAECn8fAAIYAAgKDxO1XQAJAgAYAAgKDxO1XQAJAgAAAA==.Thomasten:BAABNQAECn8dAAITAAoKyyS+AQDMAwATAAoKyyS+AQDMAwABNQAFFAIICgAbAB8eAA==.Thomasthree:BAAANQAECgIIBAABNQAFFAIICgAbAB8eAA==.',
Tj='Tjorvi:BAEANQAECgEIAQAAAA==.',
Tr='Trampozo:BAAANQADCgQIBAAAAA==.Trenady:BAAANQAECgUIBwAAAA==.Trent:BAAANQAECgMIAwABNQAECgoKIQAEAMYYAA==.Tricksï:BAAANQAECgEIAQAAAA==.',
Um='Umami:BAAANQAECgcIEgAAAA==.',
Ur='Urielseptim:BAAANQADCgEIAQAAAA==.',
Va='Valixanu:BAAANQADCgMIBQABNQADCgYIGgALAAAAAA==.Vanderlay:BAAANQAECgQIDQAAAA==.',
Ve='Vellisara:BAAANQAECgQIBQAAAA==.',
Vi='Viddar:BAAANQAECgUICQAAAA==.Viroqua:BAACNQAFFH8JAAIDAAQKWwoKBQDcAAADAAQKWwoKBQDcAAA1AAQKfykAAgMACgoTFhgcAGQCAAMACgoTFhgcAGQCAAAA.',
Vo='Voxs:BAAANQADCgMIAwAAAA==.',
['Ví']='Ví:BAACNQAFFH8KAAIKAAQKHBTZGgA+AQAKAAQKHBTZGgA+AQA1AAQKfykAAgoACgo6H/ceADwDAAoACgo6H/ceADwDAAAA.',
Wi='Wiccamaster:BAAANQADCgUIBQAAAA==.Wickerchickn:BAAANQADCgIIAgAAAA==.Wildfire:BAAANQADCgcICAAAAA==.Winkelsmom:BAABNQAECn8gAAIXAAgK9wugKgBCAQAXAAgK9wugKgBCAQAAAA==.',
Wo='Woobers:BAAANQADCgIIAgABNQAECgoKJwAEAN0dAA==.Woru:BAAANQAECgIIBwAAAA==.',
Wr='Wrathofangus:BAAANQAECgUIBQAAAA==.',
Xa='Xarava:BAAANQAECgcIEgAAAA==.',
Ye='Yeetmachine:BAAANQAECgMIBQABNQAECgoKIQAEAMYYAA==.',
Yo='Yogisa:BAAANQAECgEIAQAAAA==.',
Yu='Yuna:BAAANQAECgQIBgAAAA==.',
Za='Zarihanna:BAAANQAECgIIAgAAAA==.Zarijanna:BAAANQADCgcIBwAAAA==.Zarilenna:BAAANQADCgYICAAAAA==.Zarkanna:BAAANQADCgYIBwAAAA==.',
Ze='Zenogias:BAAANQAECgUICwAAAA==.',
Zo='Zote:BAABNQAECn8mAAIjAAgK4BwsBACtAgAjAAgK4BwsBACtAgAAAA==.',
['ße']='ßenzyte:BAAANQAECgQIBAAAAA==.',
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
