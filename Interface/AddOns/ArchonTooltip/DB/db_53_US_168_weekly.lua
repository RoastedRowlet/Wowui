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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Priest-Shadow','Mage-Arcane','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Shaman-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warlock-Demonology','Hunter-Survival','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Paladin-Protection','Evoker-Preservation','Shaman-Elemental','Shaman-Enhancement','DemonHunter-Vengeance','Monk-Mistweaver','Mage-Frost','Druid-Feral',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=53,date='2026-10-13',data={Al='Aldrik:BAAANQABCgQIBAAAAA==.Allunnadora:BAAANQADCgcIBwAAAA==.',
Am='Amarantha:BAAANQADCgEIAQAAAA==.Amellwind:BAABNQAECn8eAAIBAAgKQxS1ZABJAgABAAgKQxS1ZABJAgAAAA==.',
An='Antiosto:BAEBNQAECn8uAAICAAgK2RbZOAAhAgACAAgK2RbZOAAhAgAAAA==.',
Ar='Ariosto:BAEANQAECgEIBAABNQAECggILgACANkWAA==.Arkadias:BAAANQABCgIIAgAAAA==.Arthea:BAAANQAECgQIBgAAAA==.',
As='Asmmina:BAAANQAECgYIEwAAAA==.',
Ay='Ayrwen:BAAANQAECgUIBwAAAA==.',
Ba='Babyluvv:BAAANQADCgIIAgAAAA==.Badgerbadger:BAAANQADCggIDwAAAA==.Baldr:BAAANQAECgQIBQABNQAECgkJHgADAAIbAA==.',
Be='Beatrixx:BAAANQADCgMIAwAAAA==.',
Bi='Bitterman:BAABNQAECn8dAAIEAAkKGRorhQBzAgAEAAkKGRorhQBzAgAAAA==.',
Bl='Bloodhardt:BAABNQAECn8bAAICAAcKjBktOAAlAgACAAcKjBktOAAlAgAAAA==.Bluekoolaid:BAABNQAECn8lAAMFAAgKOxw8FwCOAgAFAAgKOxw8FwCOAgAGAAQKohOkHwDnAAAAAA==.',
Br='Bringbackbfa:BAAANQAECgIIAgAAAA==.Brynfyre:BAAANQABCgUIBQABNQADCgYIGgAHAAAAAA==.',
Bu='Buglord:BAABNQAECn8cAAIBAAcKAxG0kgDfAQABAAcKAxG0kgDfAQAAAA==.',
Bw='Bwonsamedí:BAAANQAECgIIAgAAAA==.',
Ce='Cellas:BAAANQADCgcIBwAAAA==.Cemeron:BAAANQABCgUJCgAAAA==.',
Ch='Cheba:BAABNQAECn8jAAIIAAgKxBCcbwC5AQAIAAgKxBCcbwC5AQAAAA==.Chesleigh:BAAANQADCgYIGgAAAA==.',
Ci='Cinderlight:BAAANQAECgYIEwAAAA==.',
Co='Cortock:BAABNQAECn8qAAMJAAkKoBQdFwC2AQAKAAkK7g2LmwDTAQAJAAYKtxkdFwC2AQAAAA==.Corvell:BAABNQAECn8ZAAILAAgKsRZdhAAaAgALAAgKsRZdhAAaAgAAAA==.',
Cy='Cyssor:BAAANQADCgYIGQAAAA==.',
Da='Dagget:BAAANQADCgMIAwAAAA==.Dancingfox:BAAANQADCgYIGgAAAA==.Dathdeath:BAAANQAECgIIBQAAAA==.Davlindhag:BAAANQADCgYIDAAAAA==.',
De='Deadquick:BAAANQADCgUIBQAAAA==.Demo:BAAANQADCgMIBAABNQADCgcILAAHAAAAAA==.Deros:BAAANQADCgMIAwAAAA==.Dezzii:BAAANQAECgUICQAAAA==.',
Di='Dimitri:BAAANQABCgIIAgAAAA==.Dirtnappzz:BAAANQAECgQICwAAAA==.',
Do='Doroga:BAAANQABCgYIBgAAAA==.Dotdotded:BAAANQAECgMIAwAAAA==.',
Dr='Dragonkiller:BAABNQAECn8hAAIMAAgKgxXAJQAbAgAMAAgKgxXAJQAbAgAAAA==.Driftless:BAABNQAECn8jAAMNAAgKnhWVFwAfAgANAAgKnhWVFwAfAgAOAAEKyQNgpgAnAAAAAA==.',
Du='Dunce:BAAANQAECgMIBQAAAA==.',
Eb='Ebsteen:BAAANQADCgcIBwABNQAECggIIQAPANwWAA==.',
Ec='Eccentricity:BAAANQADCggICAAAAA==.',
El='Elementalhro:BAAANQAECgcIEQAAAA==.Ellzik:BAAANQAECgUIBwAAAA==.',
Es='Escanorr:BAAANQADCgQIBAABNQAECgkJHQAEABkaAA==.Esthero:BAAANQADCgYIBgABNQAECgkJHgADAAIbAA==.',
Fa='Falorien:BAAANQAECgIIAwAAAA==.',
Fe='Felray:BAAANQAECgYIEAAAAA==.',
Fl='Flamingpax:BAAANQADCgUIDgABNQADCgcILAAHAAAAAA==.Fluffinbaked:BAAANQAECgUICAAAAA==.Fluffybúnny:BAAANQADCgYIFgAAAA==.',
Fr='Frankenberry:BAEANQAECgQIBQABNQAECggILgACANkWAA==.Freakadeek:BAAANQADCgYICgAAAA==.',
Ga='Galekk:BAAANQAECgYIAQAAAA==.',
Gh='Ghostwolfer:BAAANQAECgEIAQAAAA==.Ghpwarlock:BAABNQAECn8mAAIQAAkKOhSfYQAwAgAQAAkKOhSfYQAwAgAAAA==.',
Gl='Glasc:BAAANQAECgQICAAAAA==.Glideyboi:BAAANQADCgcJBwAAAA==.',
Gn='Gnomagician:BAAANQAECgQIBAAAAA==.Gnowances:BAAANQADCgcIBwAAAA==.',
Go='Gorakk:BAABNQAECn8jAAIKAAgKXhZVfQAeAgAKAAgKXhZVfQAeAgAAAA==.',
Gr='Greenknight:BAAANQADCgUIBQAAAA==.Grimli:BAAANQADCgUIBQAAAA==.Grimstone:BAAANQAECgYICQAAAA==.Groggu:BAAANQADCgcIFgAAAA==.',
Gs='Gsnviper:BAAANQADCgcIBwAAAA==.',
Ha='Hanakala:BAAANQAECgEIAQAAAA==.',
Hi='Hintou:BAAANQAECgMIAwAAAA==.',
Ho='Hodart:BAAANQAECgYIDAAAAA==.Hotsauce:BAAANQADCgEIAQAAAA==.',
Hu='Hurt:BAAANQAECgEIAQABNQAECgkJLQABAKshAA==.',
If='Ifucmeurdead:BAAANQADCgMIAwAAAA==.',
Ij='Ijudgethat:BAAANQAECgIIAgABNQAECgYIFQARAPsVAA==.',
It='Itzli:BAAANQAECgcIEQABNQAECgkJHgADAAIbAA==.',
Iv='Ivee:BAAANQADCgEIAQABNQAECgkJHgADAAIbAA==.',
Ja='Jaser:BAAANQADCgcIEwAAAA==.',
Je='Jellybeane:BAAANQADCgUIFAAAAA==.',
Jg='Jgwentworth:BAACNQAFFH8KAAILAAQKFBHTEQAsAQALAAQKFBHTEQAsAQA1AAQKfyQAAgsACQrBHjteAHoCAAsACQrBHjteAHoCAAAA.',
Jo='Jojen:BAABNQAECn8hAAMPAAgK3BZATAA9AgAPAAgK3BZATAA9AgADAAIKwgx7agBUAAAAAA==.Jorj:BAABNQAECn8lAAIBAAgKNR5hQwCfAgABAAgKNR5hQwCfAgAAAA==.',
Ka='Katrex:BAAANQADCgYIGgAAAA==.Kavax:BAABNQAECn8jAAISAAgKvBn6PABuAgASAAgKvBn6PABuAgAAAA==.Kayos:BAABNQAECn8tAAMTAAkKPxNMLwAoAgATAAcKyBhMLwAoAgAUAAgKxAkFNACeAQAAAA==.',
Ke='Kefan:BAAANQAECgMIAwABNQAECgkJLQATAD8TAA==.Kelz:BAAANQAECgYIEQAAAA==.Keokea:BAAANQADCgQIBAABNQAECgIIBQAHAAAAAA==.',
Kh='Khorne:BAABNQAECn8YAAICAAgKGhCzUACvAQACAAgKGhCzUACvAQAAAA==.',
Ki='Killdoom:BAAANQABCgcIBwAAAA==.Kimarah:BAAANQADCgcIBwABNQAECgkJHgADAAIbAA==.',
Kr='Krica:BAAANQADCgMJBAAAAA==.Krillian:BAAANQADCgIIAgAAAA==.Kronnah:BAAANQABCgYIBgAAAA==.',
Ku='Kula:BAAANQAECgIIBQAAAA==.Kuwata:BAAANQADCgMIAwAAAA==.',
La='Latro:BAABNQAECn8tAAMBAAkKqyFFGAA3AwABAAkKqyFFGAA3AwAMAAEKGAyqigAyAAAAAA==.',
Le='Leenex:BAAANQADCggIDQAAAA==.Lemiranas:BAABNQAECn8YAAIQAAgKJBChiQDKAQAQAAgKJBChiQDKAQAAAA==.Lepo:BAABNQAECn8eAAINAAgKbA5GHADvAQANAAgKbA5GHADvAQAAAA==.',
Lu='Lunden:BAABNQAECn8cAAQVAAcKShRKSADFAQAVAAcKShRKSADFAQAWAAMKchOjVACxAAAXAAEKuwkJXgA0AAAAAA==.Luvalee:BAAANQAECgQIDAAAAA==.',
['Lë']='Lëësa:BAAANQADCggIHAAAAA==.',
Ma='Magdalena:BAAANQAECgMIBQABNQAECgkJHgADAAIbAA==.Magdaz:BAAANQABCgMIAgAAAA==.Magnificence:BAABNQAECn8aAAILAAcK1guHywB+AQALAAcK1guHywB+AQAAAA==.Maladroit:BAAANQAECgEIAQABNQAECgkJHgADAAIbAA==.Maldus:BAABNQAECn8eAAIDAAkKAhvuEQDdAgADAAkKAhvuEQDdAgAAAA==.Mallacath:BAABNQAECn8YAAIJAAgKcBWLEwDqAQAJAAgKcBWLEwDqAQAAAA==.Marabet:BAAANQADCgEIAQAAAA==.Marloak:BAAANQAECgQICQAAAA==.Matalan:BAAANQADCgIIAgAAAA==.Maxxpower:BAAANQADCgUIBQAAAA==.',
Mc='Mcbain:BAAANQADCgcIBwAAAA==.Mccormick:BAAANQAECgIIAgABNQAECgkJHgADAAIbAA==.',
Me='Merrymanalow:BAAANQAECgIIAgAAAA==.Metaocalypse:BAAANQAECgQIBgAAAA==.',
Mi='Milough:BAAANQAFFAEIAQAAAA==.',
Mo='Moreraz:BAAANQADCgYICAAAAA==.Mortdavol:BAAANQAECgEIAQAAAA==.',
Mu='Muteknight:BAAANQADCgYIDAABNQAECgYIEAAHAAAAAA==.',
My='Myhealsuck:BAAANQAECgMIBAAAAA==.Mysweetheals:BAAANQAECgIIAgAAAA==.',
Ne='Nessy:BAABNQAECn8jAAIBAAgKbhmqSwCIAgABAAgKbhmqSwCIAgAAAA==.',
Ni='Nicksamurai:BAABNQAECn8eAAIYAAgK6xVeHAAGAgAYAAgK6xVeHAAGAgAAAA==.Nikage:BAAANQADCggICAAAAA==.',
Nu='Nuggles:BAAANQADCgEIAQAAAA==.',
Ny='Nynaève:BAAANQADCgcIGQAAAA==.',
Om='Ombos:BAABNQAECn8nAAIZAAkKXCD0BABdAwAZAAkKXCD0BABdAwAAAA==.',
Or='Ormeichi:BAAANQAECgUIDQAAAA==.Orticia:BAAANQAECgUIBQAAAA==.',
Oz='Ozone:BAABNQAECn8kAAQaAAgKLAZmpgBDAQAbAAgKtwTpHACQAQAaAAcKWwVmpgBDAQAIAAIK8AWkCAFRAAAAAA==.',
Pa='Pallypocket:BAABNQAECn8fAAISAAkKKxWGQgBYAgASAAkKKxWGQgBYAgAAAA==.Pandahalf:BAAANQADCgYIFgAAAA==.Partyrocker:BAAANQADCgQIBAABNQAECgYIFQARAPsVAA==.',
Ph='Phantom:BAAANQADCggIIQAAAA==.Pheldorai:BAAANQAECgYIDgABNQABCgEIAQAHAAAAAA==.Pheldrid:BAAANQADCgUIBQABNQABCgEIAQAHAAAAAA==.Phelnomie:BAABNQAECn8VAAIBAAgKzQrvkgDfAQABAAgKzQrvkgDfAQABNQABCgEIAQAHAAAAAA==.Phàntoms:BAAANQADCgYIDwAAAA==.',
Pr='Pream:BAAANQAECgMIAwABNQAECgYIEAAHAAAAAA==.Precipitus:BAAANQAECgMIBAAAAA==.Property:BAAANQAECgQICAABNQAFFAYIFwAcANoiAA==.',
Pu='Puma:BAAANQAECgIIAwAAAA==.',
Ra='Radiance:BAAANQADCgcIBwAAAA==.Raerion:BAAANQADCggIDgAAAA==.Raevynn:BAABNQAECn8sAAIPAAkKMA45YAD9AQAPAAkKMA45YAD9AQAAAA==.Raiinzen:BAABNQAECn8cAAIdAAcK+BzoEwA4AgAdAAcK+BzoEwA4AgAAAA==.Rajun:BAAANQABCgYIBwAAAA==.Rawrgrr:BAAANQAECgQICQAAAA==.Razelka:BAAANQAECgYIDwAAAA==.',
Re='Redearslider:BAAANQAECgUICQAAAA==.Rellix:BAAANQAECgQIBQAAAA==.Remmulas:BAABNQAECn8eAAIeAAgKVh7+BADNAgAeAAgKVh7+BADNAgAAAA==.Repunzel:BAAANQAECgUIEgAAAA==.',
Rh='Rhoku:BAAANQADCgYIBgAAAA==.',
Ri='Rightmeow:BAAANQAECgQICAABNQAECgYIEAAHAAAAAA==.',
Ro='Rozco:BAAANQAECgQIDgAAAA==.',
Ru='Rubmywolf:BAAANQAECgIIBAAAAA==.',
['Rä']='Rägnär:BAAANQABCgUIBgAAAA==.',
Sc='Scrapshot:BAAANQADCgIIAgAAAA==.',
Se='Serina:BAABNQAECn8cAAIBAAcKbhOpgwABAgABAAcKbhOpgwABAgAAAA==.',
Sh='Shadowmisty:BAAANQADCgEIAQAAAA==.Shame:BAABNQAECn8ZAAIIAAcKdxg/WgD9AQAIAAcKdxg/WgD9AQAAAA==.Shammu:BAAANQADCgcILAAAAA==.Shamocalypse:BAAANQADCggIDQAAAA==.Shevah:BAABNQAECn8aAAIfAAgKsRkXCwB9AgAfAAgKsRkXCwB9AgAAAA==.',
Si='Sid:BAECNQAFFH8HAAIEAAQKxxj5JABXAQAEAAQKxxj5JABXAQA1AAQKfy8AAgQACQqoJWwEANYDAAQACQqoJWwEANYDAAAA.',
So='Sophié:BAAANQAECgUIDgABNQAECgkJHgADAAIbAA==.Souxie:BAAANQADCgYIFQAAAA==.',
Sp='Sprout:BAAANQAECgIIBQAAAA==.',
St='Starislost:BAAANQADCgIIAgAAAA==.Stormcreaux:BAAANQAECgIIBQAAAA==.',
Su='Suelock:BAAANQAECgIIBQAAAA==.Suldes:BAAANQADCggIIQAAAA==.',
Sy='Syn:BAAANQADCggICAAAAA==.Synapse:BAAANQAECgQICQAAAA==.',
Ta='Taali:BAAANQAECgIIBAAAAA==.Tala:BAAANQADCgEIAQAAAA==.Tarrant:BAAANQADCgMIBQAAAA==.Tarvil:BAAANQAECgYIEQAAAA==.',
Te='Tesshi:BAAANQADCgYIBgAAAA==.',
Th='Thampe:BAAANQADCgEIAgAAAA==.Thjazi:BAABNQAECn8bAAIaAAgKzRJmXAAJAgAaAAgKzRJmXAAJAgAAAA==.Thomasten:BAABNQAECn8cAAIUAAkK0SatAQDNAwAUAAkK0SatAQDNAwAAAA==.Thomasthree:BAAANQAECgIIAgABNQAECgkJHAAUANEmAA==.',
Tj='Tjorvi:BAEANQAECgEIAQAAAA==.',
Tr='Trampozo:BAAANQADCgQIBAAAAA==.Trenady:BAAANQAECgUIBwAAAA==.Tricksï:BAAANQAECgEIAQAAAA==.',
Um='Umami:BAAANQAECgcIDQAAAA==.',
Ur='Urielseptim:BAAANQADCgEIAQAAAA==.',
Va='Valixanu:BAAANQADCgMIBQABNQADCgYIFQAHAAAAAA==.Vanderlay:BAAANQAECgQICQAAAA==.',
Ve='Vellisara:BAAANQAECgQIBQAAAA==.',
Vi='Viddar:BAAANQAECgQICQAAAA==.Viroqua:BAACNQAFFH8FAAIDAAMKwwhKDwDZAAADAAMKwwhKDwDZAAA1AAQKfyUAAgMACQo0Fs4bAGQCAAMACQo0Fs4bAGQCAAAA.',
['Ví']='Ví:BAACNQAFFH8KAAIKAAQKHBQ0GgA+AQAKAAQKHBQ0GgA+AQA1AAQKfyUAAgoACQotIG0eADwDAAoACQotIG0eADwDAAAA.',
Wi='Wiccamaster:BAAANQADCgUIBQAAAA==.Wildfire:BAAANQADCgcICAAAAA==.Winkelsmom:BAABNQAECn8cAAIXAAcKtQrqKQBCAQAXAAcKtQrqKQBCAQAAAA==.',
Wo='Woru:BAAANQAECgIIBQAAAA==.',
Wr='Wrathofangus:BAAANQAECgQIBAAAAA==.',
Xa='Xarava:BAAANQAECgYIDgAAAA==.',
Ye='Yeetmachine:BAAANQAECgMIBQABNQAECgkJHQAEABkaAA==.',
Yo='Yogisa:BAAANQAECgEIAQAAAA==.',
Yu='Yuna:BAAANQAECgQIBgAAAA==.',
Za='Zarihanna:BAAANQAECgIIAgAAAA==.Zarijanna:BAAANQADCgcIBwAAAA==.Zarilenna:BAAANQADCgYICAAAAA==.Zarkanna:BAAANQADCgYIBwAAAA==.',
Ze='Zenogias:BAAANQAECgUICQAAAA==.',
Zo='Zote:BAABNQAECn8hAAIRAAgKeRwjBACtAgARAAgKeRwjBACtAgAAAA==.',
['ße']='ßenzyte:BAAANQADCgcIDAAAAA==.',
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
