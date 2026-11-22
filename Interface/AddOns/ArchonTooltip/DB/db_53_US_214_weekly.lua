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

local lookup = {'Hunter-BeastMastery','Paladin-Protection','Shaman-Elemental','Warrior-Arms','Priest-Holy','Priest-Shadow','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Warlock-Destruction','DeathKnight-Frost','Warrior-Protection','Warrior-Fury','Druid-Guardian','Druid-Feral','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Monk-Brewmaster','Rogue-Assassination','Hunter-Survival','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Mage-Fire','DemonHunter-Devourer','Rogue-Subtlety','Evoker-Devastation','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Aberdine:BAAANQAECgIIAgAAAA==.',
Ac='Acadya:BAABNQAECn8tAAIBAAoKPR+jLQDlAgABAAoKPR+jLQDlAgAAAA==.Accar:BAABNQAECn8ZAAICAAoK5BL9IQDTAQACAAoK5BL9IQDTAQAAAA==.Achu:BAABNQAECn8lAAIDAAoKOSKLCwAWAwADAAoKOSKLCwAWAwABNQAECgkJNgAEABglAA==.',
Ae='Aellori:BAAANQADCgcJBwAAAA==.',
Ag='Agrias:BAABNQAECn8aAAMFAAkKyRsaNwCLAgAFAAkKyRsaNwCLAgAGAAEKAACcigAfAAAAAA==.',
Al='Algodón:BAAANQADCgQIBgAAAA==.Althea:BAABNQAECn8dAAMHAAkK7BiHMwCWAgAHAAkK7BiHMwCWAgAIAAEKvgDMvwERAAAAAA==.',
Am='Amaltheah:BAAANQADCgQIBAABNQAECgMIAwAJAAAAAA==.Ambry:BAAANQABCgIIAgABNQADCgcIBwAJAAAAAA==.Ambryosia:BAAANQADCgcIBwAAAA==.',
Ar='Arcanyounot:BAAANQADCgcIGQABNQAECgcIGgAKAFcLAA==.',
As='Aspir:BAEANQAECgQIBAABNQAFFAYIEgALAAUWAA==.',
Au='Aubury:BAAANQADCgEIAQABNQAECgEIAQAJAAAAAA==.',
Av='Aviendha:BAAANQAECgMIAwAAAA==.Avvenge:BAAANQADCgcIBwAAAA==.',
Az='Azaria:BAAANQAECgQIBgAAAA==.',
Ba='Barricade:BAABNQAECn84AAQMAAoKSBWREAAfAgAMAAoKSBWREAAfAgAEAAIKZASvIAFBAAANAAEKAACNMAA9AAAAAA==.',
Bc='Bcshaman:BAAANQADCgYJBgABNQAECgcIBwAJAAAAAA==.Bcwarrior:BAAANQAECgYIEAABNQAECgcIBwAJAAAAAA==.',
Be='Bertabeef:BAAANQADCgYIBgAAAA==.',
Bi='Biróg:BAABNQAECn8YAAMOAAUKuh9XJgBSAQAOAAUKuh9XJgBSAQAPAAQKQQ93JwDSAAAAAA==.',
Bl='Blizzaga:BAABNQAECn8vAAMQAAkK8BLZRQDjAQAQAAkK8BLZRQDjAQALAAIKfQ3UlgBnAAAAAA==.Bluebaals:BAAANQAECgEIAQAAAA==.Blutrünstig:BAAANQADCgYIDAABNQAECgEIAQAJAAAAAA==.',
Bo='Bobbyperu:BAAANQADCgUICgAAAA==.Bootowsky:BAAANQADCggIDAAAAA==.',
Br='Bramian:BAAANQADCgEIAQABNQAECgEIAQAJAAAAAA==.Brocephus:BAABNQAECn8sAAMRAAkKdAvQNABoAQARAAkKdAvQNABoAQASAAIKqgercgA8AAAAAA==.Bruno:BAAANQADCgUIBwAAAA==.',
Bu='Burrgold:BAAANQAECgQIBQAAAA==.',
Ca='Callesa:BAAANQADCgUIBQAAAA==.Carpathiá:BAAANQAECgEJAgAAAA==.',
Ch='Chaoticelf:BAAANQADCgQIBAAAAA==.Chubzilla:BAAANQAECgQIBAAAAA==.',
Cl='Clockie:BAABNQAECn8vAAMTAAoKMCUGBABjAgAUAAkKKyQ/IwCFAgATAAgKDiQGBABjAgABNQAECgkJNgAEABglAA==.Clõüd:BAACNQAFFH8NAAMCAAYKWA4bCQDBAAACAAYKQw4bCQDBAAAIAAMKEw/KJgCIAAA1AAQKf18AAwgACgpeJAMsALECAAgACgpeJAMsALECAAIACAq/Gs0XADsCAAAA.',
Co='Combusting:BAAANQAECgIIAgAAAA==.Cosmo:BAAANQABCgMIAwAAAA==.',
Cr='Crimsonrain:BAAANQAECggICAAAAA==.',
Cu='Cuitlahuac:BAAANQADCgcIBwAAAA==.',
Cy='Cynthigosa:BAAANQAECgUICQAAAA==.',
Da='Daarion:BAAANQABCgcIEQAAAA==.Darrkmann:BAAANQAECgcIEgAAAA==.',
De='Demonicspeak:BAACNQAFFH8JAAIUAAQKgAVdHwC3AAAUAAQKgAVdHwC3AAA1AAQKfyYAAhQACgo7EwhaAEgCABQACgo7EwhaAEgCAAAA.Densepancake:BAABNQAECn8YAAMNAAYKZhk1GAABAQAEAAUKXBTB3AAyAQANAAMKlhw1GAABAQAAAA==.',
Di='Dianeneedrol:BAABNQAECn8oAAIVAAcKAwWcPgC6AAAVAAcKAwWcPgC6AAAAAA==.Dietpally:BAAANQABCgEIAQAAAA==.Dingle:BAAANQADCgUIBwAAAA==.Dinkster:BAAANQADCggICAAAAA==.',
Dk='Dkcloud:BAAANQADCgcIBwABNQAFFAYIDQACAFgOAA==.',
Do='Dotzillah:BAAANQAECgUIBwAAAA==.',
Ec='Echidna:BAAANQADCgYIBgABNQAECgMIBAAJAAAAAA==.Eclesiastes:BAAANQADCgEIAQAAAA==.',
El='Elcapnkikazz:BAABNQAECn9NAAMHAAoKFxUQMQBcAgAHAAoKFxUQMQBcAgAIAAYKFgXqQAG4AAAAAA==.Ellex:BAAANQAECgEIAgAAAA==.Ellexstrasza:BAAANQADCggIFQABNQAECgEIAgAJAAAAAA==.Elyssa:BAAANQAECgUICQABNQAECgkJOgAWALwdAA==.',
En='Enhancdepeen:BAAANQAECggIDwAAAA==.',
Er='Erìs:BAAANQAECgMIBgAAAA==.Erïck:BAABNQAECn8oAAQUAAkK3RKaRQAEAgAUAAkK3RKaRQAEAgATAAIK+Qp4LAA8AAAKAAEK7wwYNwA4AAAAAA==.',
Es='Estellandra:BAAANQABCggICAAAAA==.',
Ev='Evercy:BAAANQADCgYICgAAAA==.Eviseria:BAAANQABCgQIBgAAAA==.',
Fa='Faithykinz:BAAANQAECgMIBAAAAA==.',
Fi='Fininho:BAAANQAECgcIAQAAAA==.',
Fr='Frostlowe:BAAANQADCgMIBAAAAA==.',
['Fú']='Fúsion:BAEBNQAECn8oAAIXAAoKiCImAwAWAwAXAAoKiCImAwAWAwAAAA==.',
Go='Gonamanar:BAABNQAECn8eAAMBAAgKrx2JfQATAgABAAcKNx6JfQATAgAYAAYKiBJWDADpAAAAAA==.',
Gr='Grandreaper:BAAANQADCgUIBQAAAA==.Grimfall:BAAANQADCggICAAAAA==.Gripology:BAABNQAECn8cAAMQAAgK1RW6ZgBYAQAQAAgK1RW6ZgBYAQAZAAEKAACEpwAAAAABNQAFFAQIBgAEAEUMAA==.',
Ha='Happyhour:BAABNQAECn8/AAMaAAoK3goHGwACAQAbAAgKDwkKzAARAQAaAAUKIQsHGwACAQAAAA==.Harryportals:BAAANQADCgUIBwAAAA==.Hashball:BAAANQAECgcICQABNQAECgoKPAAEAL4kAA==.',
He='Hexidecimal:BAABNQAECn8aAAMGAAkKNxX1HwA7AgAGAAkKNxX1HwA7AgAFAAEKGAMYCgEgAAAAAA==.',
Hi='Highlowe:BAAANQAECgIIAgAAAA==.',
Ho='Hoiylight:BAAANQAECggIDAAAAA==.Holybeavis:BAAANQAECgUICAAAAA==.Holydh:BAABNQAECn8fAAMcAAoKVgvvTwBZAQAcAAkKewrvTwBZAQAdAAcK9QanHwCOAAAAAA==.Holydragonn:BAAANQAECgEIAQAAAA==.Holyhunt:BAABNQAECn8aAAMeAAoK+xnGHwBzAQAeAAgKuBjGHwBzAQABAAMKHx/bGgHKAAABNQAFFAIICgAaAHYjAA==.Holylock:BAAANQAECgcIEAAAAA==.Holymage:BAACNQAFFH8KAAMaAAIKdiO6DABdAAAbAAIKZiEnLwC2AAAaAAEKfyG6DABdAAA1AAQKf1MABBsACgoBJWwLAKgDABsACgoBJWwLAKgDABoAAgoWIzkhAM0AAB8AAgqwIO8GAMMAAAAA.Holyseeker:BAABNQAECn87AAQIAAkKTCIILwCmAgAIAAkKTCIILwCmAgACAAUKtRD4NwDPAAAHAAEKvgmSHwE2AAABNQAFFAIICgAaAHYjAA==.Holyshaman:BAAANQAECggIEAAAAA==.Holywarrior:BAABNQAECn8mAAMMAAoKdhH0EgD2AQAMAAoKdhH0EgD2AQAEAAIKwA3eSwE7AAAAAA==.Holyymonk:BAABNQAECn8YAAMWAAgKLBDcDABgAQAWAAcKpg/cDABgAQAVAAYKWA1MMgALAQAAAA==.Holyyseeker:BAABNQAECn8eAAMCAAkKIQ+ENwAuAQACAAkKtQqENwAuAQAIAAUKNBBDSAGFAAAAAA==.Hottamalie:BAABNQAECn8gAAIbAAgK8h0sVQATAgAbAAgK8h0sVQATAgAAAA==.',
Ia='Iampally:BAABNQAECn9DAAICAAkK5yN8AwA3AwACAAkK5yN8AwA3AwAAAA==.',
Ic='Iceyoyomak:BAAANQAECggIEAABNQAECgoKQAAHAAUjAA==.Icyloadz:BAAANQAECggIDQAAAA==.',
Im='Imdemonic:BAAANQAECgQICAAAAA==.Imogen:BAAANQADCgYIBgAAAA==.',
Ja='Jazashi:BAAANQADCggIDgAAAQ==.',
Ji='Jijingi:BAAANQADCgMIAwAAAA==.',
Jo='Jonesknight:BAAANQADCgUIBQABNQAECgcIGgAKAFcLAA==.Jonnytsunami:BAAANQAECgMIBAAAAA==.',
Ka='Kailler:BAAANQAECgQIDQAAAA==.Kariden:BAAANQAECgEIAQAAAA==.Kazukisdh:BAABNQAECn8fAAMdAAoK5BO6CQDOAQAdAAkK4xO6CQDOAQAgAAoKJAvrMwD6AAABNQAFFAIICgAaAHYjAA==.',
Ke='Keg:BAACNQAFFH8cAAIWAAgKISYaAAAgAwAWAAgKISYaAAAgAwA1AAQKfywAAhYACgriJlwAAPEDABYACgriJlwAAPEDAAAA.',
Ki='Kittyhawk:BAABNQAECn84AAIDAAoKsB0QHgCCAgADAAoKsB0QHgCCAgAAAA==.',
Kl='Klassic:BAAANQADCgYICQAAAA==.Klixx:BAAANQADCgYIDgAAAA==.',
Kr='Krimski:BAAANQADCgIIAgAAAA==.',
Ks='Kstab:BAABNQAECn8xAAIhAAkKcRAVHQDqAQAhAAkKcRAVHQDqAQAAAA==.',
Ku='Kuromeow:BAACNQAFFH8KAAIbAAQK8RcVMQAHAQAbAAQK8RcVMQAHAQA1AAQKfzkAAhsACgpAI+ArAJACABsACgpAI+ArAJACAAAA.',
La='Larake:BAABNQAECn8gAAIiAAoK8gihDwBHAQAiAAoK8gihDwBHAQAAAA==.Lazypie:BAAANQAECgQIBAAAAA==.',
Li='Lightkeeper:BAABNQAECn8jAAMGAAYK7RK5PABFAQAGAAYK7RK5PABFAQAFAAUKygXxzQCKAAAAAA==.Lilithhunter:BAAANQADCgIIAgAAAA==.Lilkneebiter:BAAANQADCgUIBQAAAA==.Litdealer:BAAANQAECgQICAABNQAFFAQIBgAEAEUMAA==.',
Lo='Lockinaround:BAABNQAECn8aAAIKAAcKVwskDgDiAAAKAAcKVwskDgDiAAAAAA==.Loozey:BAAANQADCgUIBgAAAA==.',
Ma='Magicfinger:BAAANQAECgIIAQAAAA==.Makshifu:BAAANQAECgYIBQABNQAECgoKQAAHAAUjAA==.Manaplague:BAAANQAECgEIAQAAAA==.Manashotz:BAAANQAECgEIAQAAAA==.Marleau:BAABNQAECn8ZAAMjAAYK6xvEcwBXAQAjAAUKsxzEcwBXAQADAAUKsA5BugAdAQAAAA==.Martymcfly:BAAANQAECgYIDAAAAA==.',
Me='Menion:BAABNQAECn8bAAMIAAkKfR9rLQASAwAIAAkKfR9rLQASAwACAAMKjBGvVgCGAAAAAA==.Meruk:BAAANQAECgcIDAAAAA==.Mesoholy:BAAANQAECgQICAABNQAECgoKJwAHAIolAA==.',
Mk='Mk:BAEANQAECgQIBQABNQAECgoKPQAVAFkfAA==.',
Mo='Moreldor:BAAANQADCgQJCAAAAA==.',
Mu='Muggle:BAAANQABCggIEwAAAA==.',
Ne='Nefarius:BAABNQAECn8YAAIbAAoKTxvFNgBqAgAbAAoKTxvFNgBqAgABNQAFFAIIBgAGAFcRAA==.',
Ni='Nillfurio:BAAANQAECgYIBgAAAA==.Ninjitsû:BAABNQAECn81AAMcAAoKdB8UEwCMAgAcAAoKch4UEwCMAgAgAAgK3RtzGgCFAgABNQAECgoKPAAEAL4kAA==.',
No='Noideea:BAABNQAECn8oAAIEAAkK4iLiHgA8AwAEAAkK4iLiHgA8AwAAAA==.',
Np='Np:BAAANQADCgUIBQAAAA==.',
Ny='Nyke:BAAANQAECgQIBgAAAA==.',
Od='Odinson:BAABNQAECn8hAAIDAAgKlghOfQAXAQADAAgKlghOfQAXAQAAAA==.',
Oi='Oiiaiooiai:BAAANQAECgMIBAAAAA==.',
Om='Omie:BAABNQAECn81AAIUAAoKHRv9MgBDAgAUAAoKHRv9MgBDAgAAAA==.',
Pa='Paulos:BAAANQAECgMIBAAAAA==.',
Ph='Phanick:BAAANQAECggICAAAAA==.',
Pi='Piouspancake:BAAANQAECgQIBQABNQAECgYIGAANAGYZAA==.',
Ps='Psylocké:BAAANQAECggICQAAAA==.',
Qi='Qilin:BAAANQAECgUIBwAAAA==.',
Ra='Rainymoon:BAAANQABCgQIBAAAAA==.Raythe:BAABNQAECn8gAAIcAAgKhRO2OgDfAQAcAAgKhRO2OgDfAQAAAA==.Razzeman:BAAANQABCgYICAAAAA==.',
Re='Reverend:BAAANQAECgEIAQAAAA==.',
Ru='Ruck:BAAANQAECggICgABNQAECgoKHwAMAJobAA==.Rucker:BAABNQAECn8fAAQMAAoKmhvMDABnAgAMAAgK9B3MDABnAgANAAUK3A8eHADUAAAEAAQKcArR5gCmAAAAAA==.Ruckkin:BAAANQAECgQIAwABNQAECgoKHwAMAJobAA==.Ruckomancer:BAAANQAECgMIAwABNQAECgoKHwAMAJobAA==.Rucksin:BAAANQAECggIDgABNQAECgoKHwAMAJobAA==.Rucksy:BAABNQAECn8VAAMCAAYK3R0xLgBsAQACAAYK3R0xLgBsAQAIAAEKgA10jwE6AAABNQAECgoKHwAMAJobAA==.',
Ry='Ryan:BAABNQAECn8VAAMIAAYKMhtDzwB9AQAIAAUK+hxDzwB9AQAHAAQKgx9blwBbAQAAAA==.',
Se='Senchá:BAABNQAECn8hAAIPAAgKAyUwAwBzAwAPAAgKAyUwAwBzAwAAAA==.Seraphae:BAAANQAECgcIDgAAAA==.Sereb:BAAANQADCgUIBQAAAA==.',
Sh='Shadeorheals:BAAANQAECggIDQAAAA==.Shalana:BAAANQADCgQIBAAAAA==.Shardik:BAAANQAECgMIBQAAAA==.Sheong:BAABNQAECn86AAIWAAkKvB1VBgAhAgAWAAkKvB1VBgAhAgAAAA==.Shèrlock:BAABNQAECn8kAAIUAAoKkhVMTwDmAQAUAAoKkhVMTwDmAQAAAA==.',
Si='Silverfox:BAABNQAECn8lAAMjAAoKRSJJEgA2AwAjAAoKRSJJEgA2AwADAAIKAAAgBQGDAAABNQAECgoKQAAHAAUjAA==.',
Sk='Skera:BAABNQAECn8aAAIEAAoKoQ40pADCAQAEAAoKoQ40pADCAQAAAA==.Skinnypuppy:BAAANQAECgIIAgAAAA==.Skippydippy:BAABNQAECn8aAAMQAAcKESMxMwBBAgAQAAcKYiExMwBBAgALAAYKAxyrOwCvAQAAAA==.Skye:BAAANQAECgcIDQAAAA==.',
Sl='Sleepysniper:BAABNQAECn8bAAIeAAgK8R48FAC+AgAeAAgK8R48FAC+AgABNQAECgkJKAAEAOIiAA==.',
Sm='Sm:BAAANQADCggIDAAAAA==.',
Sp='Spelldeala:BAAANQAECgQICAABNQAFFAQIBgAEAEUMAA==.',
Ss='Ssgtusmc:BAABNQAECn83AAIMAAoK+AZ5HwACAQAMAAoK+AZ5HwACAQAAAA==.Ssjgodxx:BAABNQAECn88AAIEAAoKviS8CABJAwAEAAoKviS8CABJAwAAAA==.',
St='Stargasm:BAABNQAECn90AAIFAAoK5RgTMwB0AgAFAAoK5RgTMwB0AgAAAA==.',
Sw='Swiftmend:BAAANQAECgcIDgABNQAFFAQIBgAEAEUMAA==.Swinghardz:BAAANQAECgQIBgAAAA==.',
Ta='Taggen:BAAANQAECgEIAQAAAA==.Taurentino:BAAANQAECgcIBwAAAA==.',
Te='Terainer:BAAANQADCggIDQAAAA==.',
Th='Theia:BAAANQADCgIIAgAAAA==.Thomassian:BAABNQAECn8UAAMQAAoK4guDQwAvAQAQAAgKVA2DQwAvAQALAAIKiwc3pQBQAAAAAA==.Throbbinknob:BAAANQAECgEIAQAAAA==.',
Ti='Timelord:BAAANQADCgEIAQAAAA==.Timewing:BAABNQAECn8eAAMkAAkK3A/YGgAYAgAkAAkK3A/YGgAYAgAlAAEKPg6aJQAuAAAAAA==.Tinkerspell:BAAANQADCgQIBAAAAA==.',
To='Toefunk:BAAANQADCgQIBAAAAA==.',
Tr='Transformer:BAAANQAECggIDAAAAA==.Triblequest:BAAANQADCgYIBgAAAA==.Trotndot:BAAANQADCgIJAgAAAA==.',
Tw='Twiltock:BAAANQAECgEJAQAAAA==.Twizztyd:BAABNQAECn8XAAIGAAoKCwyiHwCPAQAGAAoKCwyiHwCPAQAAAA==.',
Ut='Utotem:BAAANQAECgQIBgAAAA==.',
Va='Valerion:BAAANQADCgYIBgAAAA==.Valessa:BAABNQAECn8lAAIaAAcK1AWEJADJAAAaAAcK1AWEJADJAAAAAA==.',
Ve='Vektendra:BAAANQADCgYIBgAAAA==.',
Vi='Vilbald:BAAANQADCgIIAwAAAA==.Vita:BAAANQAECgIIBQAAAA==.',
['Vø']='Vødu:BAAANQADCggICAAAAA==.',
Wi='Windflower:BAABNQAECn8zAAIHAAoKYh66FAATAwAHAAoKYh66FAATAwABNQAFFAIICgAbAAAdAA==.Wizbee:BAAANQADCggICQAAAA==.',
Wo='Woltrik:BAAANQAECgQIBAAAAA==.Worldbreakèr:BAAANQAECggIBQAAAA==.',
['Wÿ']='Wÿcked:BAAANQAECgQICgAAAA==.',
Xi='Xiaobao:BAACNQAFFH8GAAIOAAIKTxu+BQCfAAAOAAIKTxu+BQCfAAA1AAQKfyAAAg4ACQoOIXcPAD8CAA4ACQoOIXcPAD8CAAAA.Xiaoduoduo:BAABNQAECn9AAAQHAAoKBSN6DABkAwAHAAoKBSN6DABkAwAIAAgKjCIgRwC/AgACAAcKlSHCDQBQAgAAAA==.Xiaomak:BAABNQAECn8mAAMBAAkKPiEDMQDZAgABAAkKPiEDMQDZAgAeAAUKcxCqSAAYAQABNQAECgoKQAAHAAUjAA==.',
Xx='Xxschafer:BAAANQADCgUIBQAAAA==.',
Za='Zab:BAAANQAECgUIBQABNQAECggIJQAIAGwZAA==.Zabexer:BAAANQADCgIIAgAAAA==.',
Ze='Zehelith:BAAANQADCgQIBAABNQAECgkJJwAHALgkAA==.Zeroskills:BAABNQAECn9HAAIhAAoK+gyMGwD6AQAhAAoK+gyMGwD6AQAAAA==.',
Zu='Zulinar:BAABNQAECn8dAAIjAAkK/wjghwAdAQAjAAkK/wjghwAdAQAAAA==.',
Zy='Zyierah:BAAANQADCgQIBAAAAA==.',
['Zé']='Zépar:BAAANQAECgQIBAABNQAECgQICgAJAAAAAA==.',
['Às']='Àsmodeus:BAABNQAECn8qAAQPAAoKkhHAGgBUAQAPAAcKUhTAGgBUAQAOAAkKnwovNQD3AAARAAIK3gJ3qQBEAAAAAA==.',
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
