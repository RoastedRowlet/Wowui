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

local lookup = {'Hunter-BeastMastery','Paladin-Protection','Shaman-Elemental','Warrior-Arms','Priest-Holy','Priest-Shadow','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Warlock-Destruction','DeathKnight-Frost','Warrior-Protection','Warrior-Fury','Druid-Guardian','Druid-Feral','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','Rogue-Assassination','Hunter-Survival','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Mage-Fire','DemonHunter-Devourer','Rogue-Subtlety','Evoker-Devastation','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Aberdine:BAAANQAECgIIAgAAAA==.',
Ac='Acadya:BAABNQAECn8rAAIBAAoK3B6eJQB+AgABAAoK3B6eJQB+AgAAAA==.Accar:BAABNQAECn8ZAAICAAoK5BL9IQDTAQACAAoK5BL9IQDTAQAAAA==.Achu:BAABNQAECn8ZAAIDAAgK4SDAPQB/AgADAAgK4SDAPQB/AgABNQAECgkJNAAEAOAkAA==.Acylies:BAAANQAECgEIAQAAAA==.',
Ae='Aellori:BAAANQADCgcJCQAAAA==.',
Ag='Agrias:BAABNQAECn8aAAMFAAkKyRsaNwCLAgAFAAkKyRsaNwCLAgAGAAEKAACcigAfAAAAAA==.',
Al='Algodón:BAAANQADCgQIBgAAAA==.Althea:BAABNQAECn8dAAMHAAkK7BiHMwCWAgAHAAkK7BiHMwCWAgAIAAEKvgA+kQESAAAAAA==.',
Am='Amaltheah:BAAANQADCgQIBQABNQAECgMIAwAJAAAAAA==.Ambry:BAAANQADCgEIAQABNQADCgcIBwAJAAAAAA==.Ambryosia:BAAANQADCgcIBwAAAA==.',
An='Angarato:BAAANQADCgEIAQAAAA==.Angorius:BAAANQADCgEIAQAAAA==.',
Ar='Arcanyounot:BAAANQADCgcIHAABNQAECgUIFAAKADwIAA==.',
As='Aspir:BAEANQAECgQIBAABNQAFFAUIEQALAPMWAA==.',
Au='Aubury:BAAANQADCgEIAQABNQAECgEIAQAJAAAAAA==.',
Av='Aviendha:BAAANQAECgMIAwAAAA==.Avvenge:BAAANQADCgcIBwAAAA==.',
Az='Azaria:BAAANQAECgQIBwAAAA==.',
Ba='Barricade:BAABNQAECn8zAAQMAAkKYBWREAAfAgAMAAkKYBWREAAfAgAEAAIKZAT6BAFBAAANAAEKAACNMAA9AAAAAA==.',
Bc='Bcshaman:BAAANQADCgYJCAABNQAECgcICQAJAAAAAA==.Bcwarrior:BAAANQAECgYIEAABNQAECgcICQAJAAAAAA==.',
Be='Bekannt:BAAANQADCgEIAQAAAA==.Bertabeef:BAAANQADCgYICAAAAA==.',
Bi='Biróg:BAABNQAECn8YAAMOAAUKuh/xHQBZAQAOAAUKuh/xHQBZAQAPAAQKQQ93JwDSAAAAAA==.',
Bl='Blizzaga:BAABNQAECn8sAAMQAAgKixPZRQDjAQAQAAgKixPZRQDjAQALAAIKfQ3UlgBnAAAAAA==.Bluebaals:BAAANQADCgEIAQAAAA==.Blutrünstig:BAAANQADCgYIDAABNQAECgEIAQAJAAAAAA==.',
Bo='Bobbyperu:BAAANQADCgUICwAAAA==.Bootowsky:BAAANQADCggIDQAAAA==.',
Br='Bramian:BAAANQADCgEIAQABNQAECgEIAQAJAAAAAA==.Brocephus:BAABNQAECn8hAAMRAAgKmwgzPAAJAQARAAgKmwgzPAAJAQASAAIKqgd3cAAhAAAAAA==.Bruno:BAAANQADCgUIBwAAAA==.',
Bu='Burrgold:BAAANQAECgQIBQAAAA==.',
Ca='Callesa:BAAANQADCgUIBQAAAA==.Carpathiá:BAAANQAECgEJAgAAAA==.',
Ch='Chaoticelf:BAAANQADCgQIBAAAAA==.Chubzilla:BAAANQAECgQIBAAAAA==.',
Cl='Clockie:BAABNQAECn8iAAMTAAoKniItNgCyAgATAAgKayEtNgCyAgAUAAQKHCY4DQCIAQABNQAECgkJNAAEAOAkAA==.Clõüd:BAACNQAFFH8MAAMCAAUKhg8bCQDBAAACAAUKag8bCQDBAAAIAAMKEw/KJgCIAAA1AAQKf1sAAwgACgpeJMkfAMICAAgACgpeJMkfAMICAAIACArzGM0XADsCAAAA.',
Co='Combusting:BAAANQAECgIIAgAAAA==.Cosmo:BAAANQABCgMIAwAAAA==.',
Cr='Crimsonrain:BAAANQAECggICAAAAA==.',
Cu='Cuitlahuac:BAAANQADCgcIBwAAAA==.',
Cy='Cynthigosa:BAAANQAECgUICQAAAA==.',
Da='Daarion:BAAANQADCgEIAQAAAA==.Danteangelo:BAAANQADCgEIAQAAAA==.Darrkmann:BAAANQAECgYIDQAAAA==.',
De='Demonicspeak:BAACNQAFFH8IAAITAAMKgAUaFwC/AAATAAMKgAUaFwC/AAA1AAQKfx8AAhMACgo7EwhaAEgCABMACgo7EwhaAEgCAAAA.Densepancake:BAABNQAECn8VAAIEAAUKXBTB3AAyAQAEAAUKXBTB3AAyAQAAAA==.',
Di='Dianeneedrol:BAABNQAECn8jAAIVAAcKwgTONwCvAAAVAAcKwgTONwCvAAAAAA==.Dietpally:BAAANQADCgEIAgAAAA==.Dingle:BAAANQADCgUIBwAAAA==.Dinkster:BAAANQADCggICQAAAA==.',
Dk='Dkcloud:BAAANQADCgcICAABNQAFFAUIDAACAIYPAA==.',
Do='Dotzillah:BAAANQAECgUIBwAAAA==.',
Ec='Echidna:BAAANQADCgYIBgABNQAECgMIBAAJAAAAAA==.Eclesiastes:BAAANQADCgEIAgAAAA==.',
El='Elcapnkikazz:BAABNQAECn9NAAMHAAoKFxUyJAB0AgAHAAoKFxUyJAB0AgAIAAYKFgXqQAG4AAAAAA==.Ellex:BAAANQAECgEIAgAAAA==.Ellexstrasza:BAAANQADCggIFQABNQAECgEIAgAJAAAAAA==.Elyssa:BAAANQAECgUIBgABNQAECgkJOgAWALwdAA==.',
En='Enhancdepeen:BAAANQAECggIEQAAAA==.Ennyi:BAAANQADCgEIAQAAAA==.',
Er='Erìs:BAAANQAECgMIBgAAAA==.Erïck:BAABNQAECn8cAAITAAgKzxBcWACRAQATAAgKzxBcWACRAQAAAA==.',
Es='Estellandra:BAAANQADCgEIAQAAAA==.',
Ev='Evercy:BAAANQADCgYIDAAAAA==.Eviseria:BAAANQADCgEIAQAAAA==.',
Fa='Faithykinz:BAAANQAECgMIBAAAAA==.',
Fi='Fininho:BAAANQAECgcIAQAAAA==.',
Fr='Frostlowe:BAAANQADCgMIBAAAAA==.',
['Fú']='Fúsion:BAEBNQAECn8kAAIXAAoKYCLYAgALAwAXAAoKYCLYAgALAwAAAA==.',
Go='Gonamanar:BAABNQAECn8XAAMBAAcKgh2JfQATAgABAAcKgh2JfQATAgAYAAQKWBDKDAADAQAAAA==.',
Gr='Grandreaper:BAAANQADCgUIBwAAAA==.Grimfall:BAAANQADCggICgAAAA==.Grimtyr:BAAANQADCgEIAQAAAA==.Gripology:BAABNQAECn8cAAMQAAgK1RU+SwDmAAAQAAgK1RU+SwDmAAAZAAEKAABvlgAAAAABNQAFFAQIBgAEAEUMAA==.',
Ha='Happyhour:BAABNQAECn82AAMaAAkKnApAGwDKAAAbAAgKDwnTsQAXAQAaAAQKvgpAGwDKAAAAAA==.Harryportals:BAAANQADCgUIBwAAAA==.',
He='Helmsdeep:BAAANQAECgEIAwAAAA==.Hexidecimal:BAABNQAECn8aAAMGAAkKNxX1HwA7AgAGAAkKNxX1HwA7AgAFAAEKGAMYCgEgAAAAAA==.',
Hi='Highlowe:BAAANQAECgIIAgAAAA==.',
Ho='Hoiylight:BAAANQAECgUICgAAAA==.Holybeavis:BAAANQAECgUICAAAAA==.Holydh:BAABNQAECn8bAAMcAAoK3QrvTwBZAQAcAAkK8QnvTwBZAQAdAAcK9QbTGQCZAAAAAA==.Holydragonn:BAAANQAECgEIAQAAAA==.Holyhunt:BAABNQAECn8aAAMeAAoK+xmPGQB6AQAeAAgKuBiPGQB6AQABAAMKHx/bGgHKAAABNQAFFAIICAAbAHYjAA==.Holylock:BAAANQAECgUIEAAAAA==.Holymage:BAACNQAFFH8IAAMbAAIKdiMFJQC/AAAbAAIKZiEFJQC/AAAaAAEKfyF1CQBjAAA1AAQKf0wABBsACgrtJGwLAKgDABsACgrtJGwLAKgDABoAAgpDIXEcAMAAAB8AAQpAII0HAGMAAAAA.Holyseeker:BAABNQAECn8vAAQIAAkKLyIpPADiAgAIAAkKLyIpPADiAgACAAQKUxNGNgCrAAAHAAEKvgmSHwE2AAABNQAFFAIICAAbAHYjAA==.Holyshaman:BAAANQAECgYIEgAAAA==.Holywarrior:BAABNQAECn8iAAMMAAoKBRH0EgD2AQAMAAoKBRH0EgD2AQAEAAEKAADeSwE7AAAAAA==.Holyymonk:BAAANQAECgUIEQAAAA==.Holyyseeker:BAABNQAECn8aAAMCAAkKYQyENwAuAQACAAkK1wmENwAuAQAIAAQKOA3jUwGaAAAAAA==.Hottamalie:BAABNQAECn8gAAIbAAgK8h0ZQQAlAgAbAAgK8h0ZQQAlAgAAAA==.',
Ia='Iampally:BAABNQAECn86AAICAAkKGyNvBAAIAwACAAkKGyNvBAAIAwAAAA==.',
Ic='Iceyoyomak:BAAANQAECggIEQABNQAECgoKMQAHACciAA==.Icyloadz:BAAANQAECggIDQAAAA==.',
Im='Imdemonic:BAAANQAECgQICAAAAA==.Imogen:BAAANQADCgYIBgAAAA==.',
Ja='Jazashi:BAAANQADCggIDwAAAQ==.',
Jo='Jonesknight:BAAANQADCgUIBgABNQAECgUIFAAKADwIAA==.',
Ka='Kailler:BAAANQAECgQIDQAAAA==.Kazukisdh:BAABNQAECn8eAAMdAAoK5BOABwDUAQAdAAkK4xOABwDUAQAgAAoKJAsGLAAAAQABNQAFFAIICAAbAHYjAA==.',
Ke='Keg:BAACNQAFFH8aAAIWAAcKKSYaAAAgAwAWAAcKKSYaAAAgAwA1AAQKfywAAhYACgriJlwAAPEDABYACgriJlwAAPEDAAAA.',
Ki='Kittyhawk:BAABNQAECn82AAIDAAoKJBz+GgBsAgADAAoKJBz+GgBsAgAAAA==.',
Kl='Klassic:BAAANQADCgYICgAAAA==.Klixx:BAAANQAECgIIBAAAAA==.',
Kr='Krimski:BAAANQADCgIIAgAAAA==.',
Ks='Kstab:BAABNQAECn8xAAIhAAkKcRAVHQDqAQAhAAkKcRAVHQDqAQAAAA==.',
Ku='Kuromeow:BAACNQAFFH8KAAIbAAQK8RcVMQAHAQAbAAQK8RcVMQAHAQA1AAQKfzkAAhsACgpAIyYjAJcCABsACgpAIyYjAJcCAAAA.',
La='Larake:BAABNQAECn8dAAIiAAgKVAiXDwASAQAiAAgKVAiXDwASAQAAAA==.Lazypie:BAAANQAECgQIBAAAAA==.',
Li='Lightkeeper:BAABNQAECn8bAAMGAAYKjhK5PABFAQAGAAYKjhK5PABFAQAFAAUKNAWtuACKAAAAAA==.Lilithhunter:BAAANQADCgIIAgAAAA==.Lilkneebiter:BAAANQADCgUIBgAAAA==.Litdealer:BAAANQAECgQICAABNQAFFAQIBgAEAEUMAA==.',
Lo='Lockinaround:BAABNQAECn8UAAIKAAUKPAg2OADgAAAKAAUKPAg2OADgAAAAAA==.Loozey:BAAANQADCgUIBgAAAA==.',
Lu='Lunacia:BAAANQADCgEIAgAAAA==.',
Ma='Makshifu:BAAANQAECgYIBgABNQAECgoKMQAHACciAA==.Manaplague:BAAANQAECgEIAQAAAA==.Manashotz:BAAANQAECgEIAQAAAA==.Marleau:BAABNQAECn8ZAAMjAAYK6xvTXwBmAQAjAAUKsxzTXwBmAQADAAUKsA5BugAdAQAAAA==.Martymcfly:BAAANQAECgYIDAAAAA==.',
Me='Menion:BAABNQAECn8bAAMIAAkKfR9rLQASAwAIAAkKfR9rLQASAwACAAMKjBGvVgCGAAAAAA==.Meruk:BAAANQAECgcIDAAAAA==.Mesoholy:BAAANQAECgQICAABNQAECgkJGAAHAPIlAA==.',
Mk='Mk:BAEANQAECgQIBQABNQAECgoKNAAVACEfAA==.',
Mo='Moonfall:BAAANQADCgEIAQAAAA==.Moreldor:BAAANQADCgQJCAAAAA==.',
Mu='Muggle:BAAANQADCgEIAQAAAA==.',
Ne='Nefarius:BAAANQAECggIEgAAAA==.',
Ni='Nillfurio:BAAANQAECgYIBgAAAA==.Ninjitsû:BAABNQAECn81AAMcAAoKdB+ZDgCXAgAcAAoKch6ZDgCXAgAgAAgK3RtzGgCFAgABNQAECgoKNwAEALgkAA==.',
No='Noideea:BAABNQAECn8oAAIEAAkK4iLiHgA8AwAEAAkK4iLiHgA8AwAAAA==.',
Np='Np:BAAANQADCgUIBQAAAA==.',
Ny='Nyke:BAAANQAECgQIBgAAAA==.',
Od='Odinson:BAABNQAECn8gAAIDAAcK0ghYdwDsAAADAAcK0ghYdwDsAAAAAA==.',
Oi='Oiiaiooiai:BAAANQAECgMIBgAAAA==.',
Om='Omie:BAABNQAECn8uAAITAAgK4BxzQQCOAgATAAgK4BxzQQCOAgAAAA==.',
Pa='Paulos:BAAANQAECgMIBAAAAA==.',
Ph='Phanick:BAAANQAECggICAAAAA==.',
Pi='Piouspancake:BAAANQAECgQIBQAAAA==.',
Ps='Psylocké:BAAANQAECggICgAAAA==.',
Qi='Qilin:BAAANQAECgUIBwAAAA==.',
Ra='Rainymoon:BAAANQAECgEIAQAAAA==.Raythe:BAABNQAECn8gAAIcAAgKhRO2OgDfAQAcAAgKhRO2OgDfAQAAAA==.Razzeman:BAAANQADCgEIAwAAAA==.',
Re='Reverend:BAAANQAECgEIAQAAAA==.',
Ru='Ruck:BAAANQAECggIDgABNQAECgoKHwAMAJobAA==.Rucker:BAABNQAECn8fAAQMAAoKmhvMDABnAgAMAAgK9B3MDABnAgANAAUK3A/SFQDaAAAEAAQKcApYzQCnAAAAAA==.Ruckkin:BAAANQAECgQIBAABNQAECgoKHwAMAJobAA==.Rucksin:BAAANQAECgMIBAABNQAECgoKHwAMAJobAA==.Rucksy:BAABNQAECn8UAAMCAAYK3R0xLgBsAQACAAYK3R0xLgBsAQAIAAEKgA3zXQE+AAABNQAECgoKHwAMAJobAA==.',
Ry='Ryan:BAABNQAECn8VAAMIAAYKMhtDzwB9AQAIAAUK+hxDzwB9AQAHAAQKgx9blwBbAQAAAA==.',
Se='Senchá:BAABNQAECn8hAAIPAAgKAyUwAwBzAwAPAAgKAyUwAwBzAwAAAA==.Seraphae:BAAANQAECgcIDwAAAA==.Sereb:BAAANQADCgUIBQAAAA==.',
Sh='Shadeorheals:BAAANQAECggIDgAAAA==.Shalana:BAAANQADCgQIBAAAAA==.Shardik:BAAANQAECgMICwAAAA==.Sheong:BAABNQAECn86AAIWAAkKvB0ABQAlAgAWAAkKvB0ABQAlAgAAAA==.Shèrlock:BAABNQAECn8kAAITAAoKkhWjPwDkAQATAAoKkhWjPwDkAQAAAA==.',
Si='Silverfox:BAABNQAECn8fAAMjAAoK9iBJEgA2AwAjAAoK9iBJEgA2AwADAAIKAAAgBQGDAAABNQAECgoKMQAHACciAA==.',
Sk='Skera:BAABNQAECn8aAAIEAAoKoQ40pADCAQAEAAoKoQ40pADCAQAAAA==.Skinnypuppy:BAAANQAECgIIAgAAAA==.Skippydippy:BAABNQAECn8ZAAMQAAcKqyIxMwBBAgAQAAcKYiExMwBBAgALAAYKaxrUWwDpAAAAAA==.Skye:BAAANQAECgUIDAAAAA==.',
Sl='Sleepysniper:BAABNQAECn8bAAIeAAgK8R48FAC+AgAeAAgK8R48FAC+AgABNQAECgkJKAAEAOIiAA==.',
Sm='Sm:BAAANQADCggIDAAAAA==.',
Sp='Spelldeala:BAAANQAECgQICAABNQAFFAQIBgAEAEUMAA==.',
Ss='Ssgtusmc:BAABNQAECn8oAAIMAAcKUwSaKgDkAAAMAAcKUwSaKgDkAAAAAA==.Ssjgodxx:BAABNQAECn83AAIEAAoKuCT+CAA8AwAEAAoKuCT+CAA8AwAAAA==.',
St='Stargasm:BAABNQAECn9iAAIFAAoK5hdCLABhAgAFAAoK5hdCLABhAgAAAA==.',
Sw='Swiftmend:BAAANQAECgcIEAABNQAFFAQIBgAEAEUMAA==.Swinghardz:BAAANQAECgQIBgAAAA==.',
Ta='Taggen:BAAANQAECgEIAQAAAA==.Taurentino:BAAANQAECggICgAAAA==.',
Te='Terainer:BAAANQADCggIDQAAAA==.',
Th='Theia:BAAANQADCgIIAgAAAA==.Thomassian:BAAANQABCgIIAgAAAA==.Throbbinknob:BAAANQAECgEIAgAAAA==.',
Ti='Timelord:BAAANQADCgEIAgAAAA==.Timewing:BAABNQAECn8eAAMkAAkK3A/YGgAYAgAkAAkK3A/YGgAYAgAlAAEKPg6aJQAuAAAAAA==.Tinkerspell:BAAANQADCgQIBAAAAA==.',
To='Toefunk:BAAANQADCgQIBAAAAA==.',
Tr='Transformer:BAAANQAECggIDQAAAA==.Triblequest:BAAANQADCgYIBwAAAA==.Trotndot:BAAANQADCgIJAgAAAA==.',
Tw='Twiltock:BAAANQAECgEJAQAAAA==.Twizztyd:BAAANQAECgMICQAAAA==.',
Ut='Utotem:BAAANQAECgUIBgAAAA==.',
Va='Valerion:BAAANQADCgYIBwAAAA==.Valessa:BAABNQAECn8gAAIaAAcKsQWEJADJAAAaAAcKsQWEJADJAAAAAA==.',
Ve='Vektendra:BAAANQADCgYIBwAAAA==.',
Vi='Vilbald:BAAANQADCgIIAwAAAA==.Vita:BAAANQAECgIIBQAAAA==.',
['Vø']='Vødu:BAAANQADCggICAAAAA==.',
Wi='Windflower:BAABNQAECn8rAAIHAAoKIh7xEwDtAgAHAAoKIh7xEwDtAgABNQAFFAIICAAbAAAdAA==.Wizbee:BAAANQADCggICAAAAA==.',
Wo='Woltrik:BAAANQAECgQIBAAAAA==.Worldbreakèr:BAAANQAECggIBQAAAA==.',
['Wÿ']='Wÿcked:BAAANQAECgQICwAAAA==.',
Xi='Xiaobao:BAACNQAFFH8GAAIOAAIKTxuqBACjAAAOAAIKTxuqBACjAAA1AAQKfx0AAg4ACQrbIFMMAEACAA4ACQrbIFMMAEACAAAA.Xiaoduoduo:BAABNQAECn8xAAQHAAoKJyJ6DABkAwAHAAoKJyJ6DABkAwAIAAgKjCIgRwC/AgACAAMK2CGHOQAhAQAAAA==.Xiaomak:BAABNQAECn8mAAMBAAkKPiEDMQDZAgABAAkKPiEDMQDZAgAeAAUKcxCqSAAYAQABNQAECgoKMQAHACciAA==.',
Xx='Xxschafer:BAAANQADCgUIBwAAAA==.',
Za='Zab:BAAANQAECgUIBQABNQAECggIJAAIAGwZAA==.Zabexer:BAAANQADCgIIAgAAAA==.',
Ze='Zehelith:BAAANQADCgQIBAABNQAECgkJJwAHALgkAA==.Zeroskills:BAABNQAECn8/AAIhAAoKOQyMGwD6AQAhAAoKOQyMGwD6AQAAAA==.',
Zu='Zulinar:BAABNQAECn8ZAAIjAAgK6ggGfwAEAQAjAAgK6ggGfwAEAQAAAA==.',
Zy='Zyierah:BAAANQADCgQIBAAAAA==.',
['Zé']='Zépar:BAAANQAECgQIBAABNQAECgQICwAJAAAAAA==.',
['Às']='Àsmodeus:BAABNQAECn8pAAQPAAoKkhHAGgBUAQAPAAcKUhTAGgBUAQAOAAkKfgp3KwD4AAARAAIK3gJ3qQBEAAAAAA==.',
['Ér']='Éres:BAAANQADCgYIBwAAAA==.',
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
