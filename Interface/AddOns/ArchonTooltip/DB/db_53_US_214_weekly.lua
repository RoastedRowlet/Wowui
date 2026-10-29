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

local lookup = {'Hunter-BeastMastery','Paladin-Protection','Shaman-Elemental','Warrior-Arms','Priest-Holy','Priest-Shadow','Paladin-Holy','Unknown-Unknown','DeathKnight-Frost','Warrior-Protection','Warrior-Fury','Druid-Guardian','Druid-Feral','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Monk-Windwalker','Monk-Brewmaster','Rogue-Assassination','Hunter-Survival','Mage-Frost','Mage-Arcane','DemonHunter-Vengeance','DemonHunter-Havoc','Hunter-Marksmanship','DemonHunter-Devourer','Rogue-Subtlety','Evoker-Devastation','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Aberdine:BAAANQAECgIIAgAAAA==.',
Ac='Acadya:BAABNQAECn8mAAIBAAoK5hqEIgBcAgABAAoK5hqEIgBcAgAAAA==.Accar:BAABNQAECn8VAAICAAoK5BL9IQDTAQACAAoK5BL9IQDTAQAAAA==.Achu:BAABNQAECn8XAAIDAAgK4SBYJwDKAQADAAgK4SBYJwDKAQABNQAECgkJLAAEAOAjAA==.',
Ae='Aellori:BAAANQADCgcJBwAAAA==.',
Ag='Agrias:BAABNQAECn8aAAMFAAkKyRsaNwCLAgAFAAkKyRsaNwCLAgAGAAEKAACcigAfAAAAAA==.',
Al='Algodón:BAAANQADCgQIBgAAAA==.Althea:BAABNQAECn8bAAIHAAkK7BiHMwCWAgAHAAkK7BiHMwCWAgAAAA==.',
Am='Amaltheah:BAAANQADCgQIBAABNQAECgMIAwAIAAAAAA==.Ambry:BAAANQABCgIIAgABNQADCgcIBwAIAAAAAA==.Ambryosia:BAAANQADCgcIBwAAAA==.',
Ar='Arcanyounot:BAAANQADCgcIGQABNQAECgQIEAAIAAAAAA==.',
As='Aspir:BAEANQAECgQIBAABNQAFFAUIEQAJAPMWAA==.',
Au='Aubury:BAAANQADCgEIAQABNQADCgQIBAAIAAAAAA==.',
Av='Aviendha:BAAANQAECgMIAwAAAA==.Avvenge:BAAANQADCgcIBwAAAA==.',
Az='Azaria:BAAANQAECgMIBAAAAA==.',
Ba='Barricade:BAABNQAECn8wAAQKAAkKTBWREAAfAgAKAAkKTBWREAAfAgAEAAIKZATU6wBBAAALAAEKAACNMAA9AAAAAA==.',
Bc='Bcshaman:BAAANQADCgYJBgABNQAECgcIBwAIAAAAAA==.Bcwarrior:BAAANQAECgYIEAABNQAECgcIBwAIAAAAAA==.',
Be='Bertabeef:BAAANQADCgYIBgAAAA==.',
Bi='Biróg:BAABNQAECn8YAAMMAAUKuh/XFQBlAQAMAAUKuh/XFQBlAQANAAQKQQ93JwDSAAAAAA==.',
Bl='Blizzaga:BAABNQAECn8rAAMOAAgKixPZRQDjAQAOAAgKixPZRQDjAQAJAAIKfQ3UlgBnAAAAAA==.Blutrünstig:BAAANQADCgYIDAABNQAECgEIAQAIAAAAAA==.',
Bo='Bobbyperu:BAAANQADCgUICgAAAA==.Bootowsky:BAAANQADCggIDAAAAA==.',
Br='Bramian:BAAANQADCgEIAQABNQADCgQIBAAIAAAAAA==.Brocephus:BAABNQAECn8ZAAMPAAYKIAgGbQAXAQAPAAYKIAgGbQAXAQAQAAEKNgmpfgAiAAAAAA==.Bruno:BAAANQADCgUIBwAAAA==.',
Bu='Burrgold:BAAANQAECgQIBQAAAA==.',
Ca='Callesa:BAAANQADCgUIBQAAAA==.Carpathiá:BAAANQAECgEJAgAAAA==.',
Ch='Chaoticelf:BAAANQADCgQIBAAAAA==.Chubzilla:BAAANQAECgQIBAAAAA==.',
Cl='Clockie:BAABNQAECn8hAAMRAAoKniItNgCyAgARAAgKayEtNgCyAgASAAQKHCY4DQCIAQABNQAECgkJLAAEAOAjAA==.Clõüd:BAACNQAFFH8MAAMCAAUKhg8bCQDBAAACAAUKag8bCQDBAAATAAMKEw/KJgCIAAA1AAQKf1IAAxMACgrrIiceAJgCABMACgrrIiceAJgCAAIACArzGM0XADsCAAAA.',
Co='Combusting:BAAANQAECgIIAgAAAA==.Cosmo:BAAANQABCgMIAwAAAA==.',
Cr='Crimsonrain:BAAANQAECggICAAAAA==.',
Cu='Cuitlahuac:BAAANQADCgcIBwAAAA==.',
Cy='Cynthigosa:BAAANQAECgUICQAAAA==.',
Da='Daarion:BAAANQABCgcIEQAAAA==.Darrkmann:BAAANQAECgYIDQAAAA==.',
De='Demonicspeak:BAACNQAFFH8FAAIRAAIKKwbVHACAAAARAAIKKwbVHACAAAA1AAQKfxsAAhEACgoeEghaAEgCABEACgoeEghaAEgCAAAA.Densepancake:BAAANQAECgUIEgAAAA==.',
Di='Dianeneedrol:BAABNQAECn8jAAIUAAcKwgQLLwCxAAAUAAcKwgQLLwCxAAAAAA==.Dietpally:BAAANQABCgEIAQAAAA==.Dingle:BAAANQADCgMIAwAAAA==.Dinkster:BAAANQADCggICAAAAA==.',
Dk='Dkcloud:BAAANQADCgcIBwABNQAFFAUIDAACAIYPAA==.',
Do='Dotzillah:BAAANQAECgIIAgAAAA==.',
Ec='Echidna:BAAANQADCgYIBgABNQAECgMIBAAIAAAAAA==.Eclesiastes:BAAANQADCgEIAQAAAA==.',
El='Elcapnkikazz:BAABNQAECn8/AAMHAAoKpxCBLQDyAQAHAAoKpxCBLQDyAQATAAYK7gLqQAG4AAAAAA==.Ellex:BAAANQAECgEIAgAAAA==.Ellexstrasza:BAAANQADCggIFQABNQAECgEIAgAIAAAAAA==.Elyssa:BAAANQAECgUIBQABNQAECgkJOgAVALwdAA==.',
En='Enhancdepeen:BAAANQAECgUIBgAAAA==.',
Er='Erìs:BAAANQAECgMIBgAAAA==.Erïck:BAABNQAECn8XAAIRAAcK9Q91WwBRAQARAAcK9Q91WwBRAQAAAA==.',
Es='Estellandra:BAAANQABCggICAAAAA==.',
Ev='Evercy:BAAANQADCgYICgAAAA==.Eviseria:BAAANQABCgQIBgAAAA==.',
Fa='Faithykinz:BAAANQAECgMIBAAAAA==.',
Fi='Fininho:BAAANQAECgcIAQAAAA==.',
Fr='Frostlowe:BAAANQADCgMIBAAAAA==.',
['Fú']='Fúsion:BAEBNQAECn8cAAIWAAoK8iHrEgDlAgAWAAoK8iHrEgDlAgAAAA==.',
Go='Gonamanar:BAABNQAECn8VAAMBAAcKgh2JfQATAgABAAcKgh2JfQATAgAXAAQKWBDKDAADAQAAAA==.',
Gr='Grandreaper:BAAANQADCgUIBQAAAA==.Grimfall:BAAANQADCggICAAAAA==.Gripology:BAABNQAECn8bAAIOAAgK1RX5PADuAAAOAAgK1RX5PADuAAABNQAFFAQIBgAEAEUMAA==.',
Ha='Happyhour:BAABNQAECn8uAAMYAAkKnArzFADOAAAZAAcKXAr5nQAJAQAYAAQKvgrzFADOAAAAAA==.Harryportals:BAAANQADCgUIBwAAAA==.',
He='Hexidecimal:BAABNQAECn8aAAMGAAkKNxX1HwA7AgAGAAkKNxX1HwA7AgAFAAEKGAMYCgEgAAAAAA==.',
Hi='Highlowe:BAAANQAECgIIAgAAAA==.',
Ho='Hoiylight:BAAANQAECgUICAAAAA==.Holybeavis:BAAANQAECgUICAAAAA==.Holydh:BAABNQAECn8ZAAMaAAoKpwmGFACcAAAbAAkKjwjvTwBZAQAaAAcK9QaGFACcAAAAAA==.Holydragonn:BAAANQAECgEIAQAAAA==.Holyhunt:BAABNQAECn8ZAAMcAAkKZR0OFAB/AQAcAAcKfxwOFAB/AQABAAMKHx/bGgHKAAABNQAFFAIIBgAZABUgAA==.Holylock:BAAANQAECgQICQAAAA==.Holymage:BAACNQAFFH8GAAMZAAIKFSAhHwC4AAAZAAIKFSAhHwC4AAAYAAEKlwYDDwBAAAA1AAQKf0gAAxkACgqhJGwLAKgDABkACgqhJGwLAKgDABgAAgpDIYMVAMkAAAAA.Holyseeker:BAABNQAECn8pAAMTAAkK+SEpPADiAgATAAkK+SEpPADiAgAHAAEKvgmSHwE2AAABNQAFFAIIBgAZABUgAA==.Holyshaman:BAAANQAECgcICwAAAA==.Holywarrior:BAABNQAECn8hAAMKAAoKSA/0EgD2AQAKAAoKSA/0EgD2AQAEAAEKAADeSwE7AAAAAA==.Holyymonk:BAAANQAECgUICwAAAA==.Holyyseeker:BAABNQAECn8YAAMCAAkKAQyENwAuAQACAAkKIwmENwAuAQATAAQKOA3jUwGaAAAAAA==.Hottamalie:BAABNQAECn8gAAIZAAgK8h2+LQA7AgAZAAgK8h2+LQA7AgAAAA==.',
Ia='Iampally:BAABNQAECn8xAAICAAkKUyEqCABLAgACAAkKUyEqCABLAgAAAA==.',
Ic='Iceyoyomak:BAAANQAECggIEAABNQAECgoKLAAHACciAA==.Icyloadz:BAAANQAECggIDQAAAA==.',
Im='Imdemonic:BAAANQAECgQICAAAAA==.Imogen:BAAANQADCgYIBgAAAA==.',
Ja='Jazashi:BAAANQADCggIDgAAAQ==.',
Jo='Jonesknight:BAAANQADCgUIBQABNQAECgQIEAAIAAAAAA==.',
Ka='Kailler:BAAANQAECgQIDQAAAA==.Kazukisdh:BAABNQAECn8YAAMaAAoK2xLrBQDBAQAaAAkK2xLrBQDBAQAdAAkKaApGKwDNAAABNQAFFAIIBgAZABUgAA==.',
Ke='Keg:BAACNQAFFH8aAAIVAAcKKSYaAAAgAwAVAAcKKSYaAAAgAwA1AAQKfywAAhUACgriJlwAAPEDABUACgriJlwAAPEDAAAA.',
Ki='Kittyhawk:BAABNQAECn8uAAIDAAoKjhvoGAA2AgADAAoKjhvoGAA2AgAAAA==.',
Kl='Klassic:BAAANQADCgYICQAAAA==.',
Kr='Krimski:BAAANQADCgIIAgAAAA==.',
Ks='Kstab:BAABNQAECn8oAAIeAAgKyxEVHQDqAQAeAAgKyxEVHQDqAQAAAA==.',
Ku='Kuromeow:BAACNQAFFH8KAAIZAAQK8RcVMQAHAQAZAAQK8RcVMQAHAQA1AAQKfzgAAhkACgpAI9oVALMCABkACgpAI9oVALMCAAAA.',
La='Larake:BAABNQAECn8dAAIfAAgKVAhvDAAYAQAfAAgKVAhvDAAYAQAAAA==.Lazypie:BAAANQAECgQIBAAAAA==.',
Li='Lightkeeper:BAABNQAECn8bAAMGAAYKjhK5PABFAQAGAAYKjhK5PABFAQAFAAUKNAVHnwCLAAAAAA==.Lilithhunter:BAAANQADCgIIAgAAAA==.Lilkneebiter:BAAANQADCgUIBQAAAA==.Litdealer:BAAANQAECgQICAABNQAFFAQIBgAEAEUMAA==.',
Lo='Lockinaround:BAAANQAECgQIEAAAAA==.',
Ma='Makshifu:BAAANQAECgQIBAABNQAECgoKLAAHACciAA==.Manaplague:BAAANQAECgEIAQAAAA==.Marleau:BAABNQAECn8ZAAMgAAYK6xuZSABzAQAgAAUKsxyZSABzAQADAAUKsA5BugAdAQAAAA==.Martymcfly:BAAANQAECgYIDAAAAA==.',
Me='Menion:BAABNQAECn8bAAMTAAkKfR9rLQASAwATAAkKfR9rLQASAwACAAMKjBGvVgCGAAAAAA==.Meruk:BAAANQAECgYICwAAAA==.Mesoholy:BAAANQAECgQICAABNQAECggIFwAHAOklAA==.',
Mk='Mk:BAEANQAECgQIBQABNQAECgkJMAAUAFYeAA==.',
Mo='Moreldor:BAAANQADCgQJCAAAAA==.',
Mu='Muggle:BAAANQABCggIEwAAAA==.',
Ne='Nefarius:BAAANQAECggIDgABNQAFFAIIBgAGAFcRAA==.',
Ni='Nillfurio:BAAANQAECgYIBgAAAA==.Ninjitsû:BAABNQAECn8yAAMbAAoKCR4CCwCeAgAbAAoKBx0CCwCeAgAdAAgK3RtzGgCFAgAAAA==.',
No='Noideea:BAABNQAECn8oAAIEAAkK4iLiHgA8AwAEAAkK4iLiHgA8AwAAAA==.',
Np='Np:BAAANQADCgUIBQAAAA==.',
Ny='Nyke:BAAANQAECgQIBgAAAA==.',
Od='Odinson:BAABNQAECn8ZAAIDAAYKMAhQswAsAQADAAYKMAhQswAsAQAAAA==.',
Oi='Oiiaiooiai:BAAANQAECgMIAwAAAA==.',
Om='Omie:BAABNQAECn8mAAIRAAgK4BxzQQCOAgARAAgK4BxzQQCOAgAAAA==.',
Pa='Paulos:BAAANQAECgMIBAAAAA==.',
Ph='Phanick:BAAANQAECggICAAAAA==.',
Pi='Piouspancake:BAAANQAECgUIBQAAAA==.',
Ps='Psylocké:BAAANQAECggIBQAAAA==.',
Qi='Qilin:BAAANQAECgUIBwAAAA==.',
Ra='Raythe:BAABNQAECn8dAAIbAAgKhRO2OgDfAQAbAAgKhRO2OgDfAQAAAA==.Razzeman:BAAANQABCgYICAAAAA==.',
Re='Reverend:BAAANQADCgQIBAAAAA==.',
Ru='Ruck:BAAANQAECgYICQABNQAECgkJGAAKAOwbAA==.Rucker:BAABNQAECn8YAAQKAAkK7BvMDABnAgAKAAgK9B3MDABnAgAEAAMKkAbj0ABuAAALAAEKuw8+IQA9AAAAAA==.Ruckkin:BAAANQAECgQIAwABNQAECgkJGAAKAOwbAA==.Rucksy:BAAANQAECgQIEAABNQAECgkJGAAKAOwbAA==.',
Ry='Ryan:BAABNQAECn8VAAMTAAYKMhtDzwB9AQATAAUK+hxDzwB9AQAHAAQKgx9blwBbAQAAAA==.',
Se='Senchá:BAABNQAECn8hAAINAAgKAyUwAwBzAwANAAgKAyUwAwBzAwAAAA==.Seraphae:BAAANQAECgUIDgAAAA==.Sereb:BAAANQADCgUIBQAAAA==.',
Sh='Shadeorheals:BAAANQAECggICgAAAA==.Shalana:BAAANQADCgQIBAAAAA==.Shardik:BAAANQAECgEIAQAAAA==.Sheong:BAABNQAECn86AAIVAAkKvB2HAwA4AgAVAAkKvB2HAwA4AgAAAA==.Shèrlock:BAABNQAECn8kAAIRAAoKkhUPLQD7AQARAAoKkhUPLQD7AQAAAA==.',
Si='Silverfox:BAABNQAECn8aAAMgAAoK9iBJEgA2AwAgAAoK9iBJEgA2AwADAAIKAAAgBQGDAAABNQAECgoKLAAHACciAA==.',
Sk='Skera:BAABNQAECn8aAAIEAAoKoQ40pADCAQAEAAoKoQ40pADCAQAAAA==.Skinnypuppy:BAAANQAECgIIAgAAAA==.Skippydippy:BAABNQAECn8UAAMOAAcK0CExMwBBAgAOAAcKYiExMwBBAgAJAAMKSxk8TgDdAAAAAA==.Skye:BAAANQAECgUIDAAAAA==.',
Sl='Sleepysniper:BAABNQAECn8bAAIcAAgK8R48FAC+AgAcAAgK8R48FAC+AgABNQAECgkJKAAEAOIiAA==.',
Sm='Sm:BAAANQADCggICAAAAA==.',
Sp='Spelldeala:BAAANQAECgQICAABNQAFFAQIBgAEAEUMAA==.',
Ss='Ssgtusmc:BAABNQAECn8iAAIKAAcKwwOaKgDkAAAKAAcKwwOaKgDkAAAAAA==.Ssjgodxx:BAABNQAECn8vAAIEAAoKByKICgATAwAEAAoKByKICgATAwABNQAECgoKMgAbAAkeAA==.',
St='Stargasm:BAABNQAECn9IAAIFAAoKgRbuRgBSAgAFAAoKgRbuRgBSAgAAAA==.',
Sw='Swiftmend:BAAANQAECgcIDgABNQAFFAQIBgAEAEUMAA==.Swinghardz:BAAANQAECgQIBgAAAA==.',
Ta='Taggen:BAAANQAECgEIAQAAAA==.Tardis:BAAANQADCgEIAQAAAA==.Taurentino:BAAANQAECgcIBwAAAA==.',
Te='Terainer:BAAANQADCggIDQAAAA==.',
Th='Theia:BAAANQADCgIIAgAAAA==.Thomassian:BAAANQABCgIIAgAAAA==.Throbbinknob:BAAANQAECgEIAQAAAA==.',
Ti='Timewing:BAABNQAECn8eAAMhAAkK3A/YGgAYAgAhAAkK3A/YGgAYAgAiAAEKPg6aJQAuAAAAAA==.Tinkerspell:BAAANQADCgQIBAAAAA==.',
To='Toefunk:BAAANQADCgQIBAAAAA==.',
Tr='Transformer:BAAANQAECggIDAAAAA==.Triblequest:BAAANQADCgYIBgAAAA==.Trotndot:BAAANQADCgIJAgAAAA==.',
Tw='Twiltock:BAAANQAECgEJAQAAAA==.Twizztyd:BAAANQAECgIIAgAAAA==.',
Ut='Utotem:BAAANQAECgQIBAAAAA==.',
Va='Valerion:BAAANQADCgYIBgAAAA==.Valessa:BAABNQAECn8gAAIYAAcKsQXlFQDGAAAYAAcKsQXlFQDGAAAAAA==.',
Ve='Vektendra:BAAANQADCgYIBgAAAA==.',
Vi='Vilbald:BAAANQADCgIIAwAAAA==.Vita:BAAANQAECgIIBQAAAA==.',
['Vø']='Vødu:BAAANQADCggICAAAAA==.',
Wi='Windflower:BAABNQAECn8pAAIHAAoKKR6TEADNAgAHAAoKKR6TEADNAgABNQAFFAIIBgAZAMEWAA==.Wizbee:BAAANQADCggICAAAAA==.',
Wo='Woltrik:BAAANQAECgQIBAAAAA==.Worldbreakèr:BAAANQAECggIBQAAAA==.',
['Wÿ']='Wÿcked:BAAANQAECgQICgAAAA==.',
Xi='Xiaobao:BAABNQAECn8bAAIMAAkKcB5mDQDaAQAMAAkKcB5mDQDaAQAAAA==.Xiaoduoduo:BAABNQAECn8sAAQHAAoKJyJ6DABkAwAHAAoKJyJ6DABkAwATAAcKjCIgRwC/AgACAAMK2CGHOQAhAQAAAA==.Xiaomak:BAABNQAECn8mAAMBAAkKPiEDMQDZAgABAAkKPiEDMQDZAgAcAAUKcxCqSAAYAQABNQAECgoKLAAHACciAA==.',
Xx='Xxschafer:BAAANQADCgUIBQAAAA==.',
Za='Zab:BAAANQAECgUIBQABNQAECggIJAATAGwZAA==.Zabexer:BAAANQADCgIIAgAAAA==.',
Ze='Zehelith:BAAANQADCgQIBAABNQAECgkJJwAHALgkAA==.Zeroskills:BAABNQAECn87AAIeAAoK1QuMGwD6AQAeAAoK1QuMGwD6AQAAAA==.',
Zu='Zulinar:BAAANQAECgYIEwAAAA==.',
Zy='Zyierah:BAAANQADCgQIBAAAAA==.',
['Zé']='Zépar:BAAANQAECgQIBAABNQAECgQICgAIAAAAAA==.',
['Às']='Àsmodeus:BAABNQAECn8hAAQNAAoKkhHAGgBUAQANAAcKUhTAGgBUAQAMAAgK7wlYKADOAAAPAAIK3gJ3qQBEAAAAAA==.',
['Ér']='Éres:BAAANQADCgYIBgAAAA==.',
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
