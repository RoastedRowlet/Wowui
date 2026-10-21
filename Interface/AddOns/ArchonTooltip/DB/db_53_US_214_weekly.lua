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

local lookup = {'Hunter-BeastMastery','Shaman-Elemental','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Paladin-Holy','Unknown-Unknown','DeathKnight-Frost','Warrior-Protection','Warrior-Arms','Warrior-Fury','Druid-Guardian','Druid-Feral','Warlock-Demonology','Warlock-Affliction','Paladin-Protection','Paladin-Retribution','Monk-Windwalker','Rogue-Assassination','Hunter-Survival','Mage-Arcane','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Hunter-Marksmanship','Monk-Brewmaster','Rogue-Subtlety','Evoker-Devastation','Shaman-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Druid-Balance',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Aberdine:BAAANQAECgIIAgAAAA==.',
Ac='Acadya:BAABNQAECn8hAAIBAAoKcxqjLQDlAgABAAoKcxqjLQDlAgAAAA==.Accar:BAAANQAECggIEQAAAA==.Achu:BAABNQAECn8VAAICAAgKsB4nCQDUAQACAAgKsB4nCQDUAQABNQAECgoKOgADAKkiAA==.',
Ae='Aellori:BAAANQADCgcJBwAAAA==.',
Ag='Agrias:BAABNQAECn8aAAMEAAkKyRsaNwCLAgAEAAkKyRsaNwCLAgAFAAEKAACcigAfAAAAAA==.',
Al='Algodón:BAAANQADCgQIBgAAAA==.Althea:BAABNQAECn8aAAIGAAkK7BiHMwCWAgAGAAkK7BiHMwCWAgAAAA==.',
Am='Amaltheah:BAAANQADCgQIBAABNQAECgMIAwAHAAAAAA==.Ambry:BAAANQABCgIIAgABNQADCgcIBwAHAAAAAA==.Ambryosia:BAAANQADCgcIBwAAAA==.',
Ar='Arcanyounot:BAAANQADCgcIGQABNQAECgQIDgAHAAAAAA==.',
As='Aspir:BAEANQAECgQIBAABNQAFFAQIDgAIAD0YAA==.',
Au='Aubury:BAAANQADCgEIAQABNQADCgQIBAAHAAAAAA==.',
Av='Aviendha:BAAANQAECgMIAwAAAA==.Avvenge:BAAANQADCgcIBwAAAA==.',
Az='Azaria:BAAANQAECgMIAwAAAA==.',
Ba='Barricade:BAABNQAECn8oAAQJAAgK7BaREAAfAgAJAAgK7BaREAAfAgAKAAIKZASwtwBFAAALAAEKAACNMAA9AAAAAA==.',
Bc='Bcshaman:BAAANQADCgYJBgABNQAECggIBwAHAAAAAA==.Bcwarrior:BAAANQAECgYIEAABNQAECggIBwAHAAAAAA==.',
Be='Bertabeef:BAAANQADCgYIBgAAAA==.',
Bi='Biróg:BAABNQAECn8XAAMMAAQKDCGYDQArAQAMAAQKDCGYDQArAQANAAQKQQ93JwDSAAAAAA==.',
Bl='Blizzaga:BAABNQAECn8rAAMDAAgKsxPZRQDjAQADAAgKsxPZRQDjAQAIAAIKfQ3UlgBnAAAAAA==.Blutrünstig:BAAANQADCgYIDAABNQAECgEIAQAHAAAAAA==.',
Bo='Bobbyperu:BAAANQADCgUICgAAAA==.Bootowsky:BAAANQADCggIDAAAAA==.',
Br='Bramian:BAAANQADCgEIAQABNQADCgQIBAAHAAAAAA==.Brocephus:BAAANQAECgUIDgAAAA==.Bruno:BAAANQADCgUIBwAAAA==.',
Bu='Burrgold:BAAANQAECgQIBQAAAA==.',
Ca='Callesa:BAAANQADCgUIBQAAAA==.Carpathiá:BAAANQAECgEJAgAAAA==.',
Ch='Chaoticelf:BAAANQADCgQIBAAAAA==.Chubzilla:BAAANQAECgQIBAAAAA==.',
Cl='Clockie:BAABNQAECn8gAAMOAAoKniItNgCyAgAOAAgKayEtNgCyAgAPAAQKHCY4DQCIAQABNQAECgoKOgADAKkiAA==.Clõüd:BAACNQAFFH8LAAMQAAUKhg8bCQDBAAAQAAUKag8bCQDBAAARAAIKEw/KJgCIAAA1AAQKf0gAAxEACgqYH78uAA4DABEACQogIr8uAA4DABAACArzGM0XADsCAAAA.',
Co='Combusting:BAAANQAECgIIAgAAAA==.Cosmo:BAAANQABCgMIAwAAAA==.',
Cr='Crimsonrain:BAAANQAECggICAAAAA==.',
Cu='Cuitlahuac:BAAANQADCgcIBwAAAA==.',
Cy='Cynthigosa:BAAANQAECgUICQAAAA==.',
Da='Daarion:BAAANQABCgcIEQAAAA==.Darrkmann:BAAANQAECgcIDQAAAA==.',
De='Demonicspeak:BAABNQAECn8XAAIOAAoKexEIWgBIAgAOAAoKexEIWgBIAgAAAA==.Densepancake:BAAANQAECgUIEQAAAA==.',
Di='Dianeneedrol:BAABNQAECn8dAAISAAcKqATkHQC7AAASAAcKqATkHQC7AAAAAA==.Dietpally:BAAANQABCgEIAQAAAA==.Dingle:BAAANQADCgMIAwAAAA==.Dinkster:BAAANQADCggICAAAAA==.',
Dk='Dkcloud:BAAANQADCgcIBwABNQAFFAUICwAQAIYPAA==.',
Do='Dotzillah:BAAANQADCgUIBQAAAA==.',
Ec='Echidna:BAAANQADCgYIBgABNQAECgMIBAAHAAAAAA==.Eclesiastes:BAAANQADCgEIAQAAAA==.',
El='Elcapnkikazz:BAABNQAECn8yAAMGAAoKTA8/FgCjAQAGAAoKTA8/FgCjAQARAAYK7gLqQAG4AAAAAA==.Ellex:BAAANQAECgEIAQAAAA==.Ellexstrasza:BAAANQADCgcIDQABNQAECgEIAQAHAAAAAA==.',
En='Enhancdepeen:BAAANQADCggICAAAAA==.',
Er='Erìs:BAAANQAECgMIBgAAAA==.Erïck:BAABNQAECn8XAAIOAAcK9Q9BHwByAQAOAAcK9Q9BHwByAQAAAA==.',
Es='Estellandra:BAAANQABCggICAAAAA==.',
Ev='Evercy:BAAANQADCgYICgAAAA==.Eviseria:BAAANQABCgQIBgAAAA==.',
Fa='Faithykinz:BAAANQAECgMIBAAAAA==.',
Fi='Fininho:BAAANQAECgYIAQAAAA==.',
Fr='Frostlowe:BAAANQADCgMIBAAAAA==.',
['Fú']='Fúsion:BAEBNQAECn8bAAITAAoK8iHrEgDlAgATAAoK8iHrEgDlAgAAAA==.',
Go='Gonamanar:BAABNQAECn8UAAMBAAcKlhqJfQATAgABAAcKlhqJfQATAgAUAAQKWBDKDAADAQAAAA==.',
Gr='Grandreaper:BAAANQADCgUIBQAAAA==.Grimfall:BAAANQADCggICAAAAA==.Gripology:BAABNQAECn8VAAIDAAcKqhO6ZgBYAQADAAcKqhO6ZgBYAQABNQAFFAQIBgAKAEUMAA==.',
Ha='Happyhour:BAABNQAECn8oAAMVAAkKFwpwTQAhAQAVAAcKXApwTQAhAQAWAAQKbQkiLwCGAAAAAA==.Harryportals:BAAANQADCgUIBQAAAA==.',
He='Hexidecimal:BAABNQAECn8aAAMFAAkKNxX1HwA7AgAFAAkKNxX1HwA7AgAEAAEKGAMYCgEgAAAAAA==.',
Hi='Highlowe:BAAANQAECgIIAgAAAA==.',
Ho='Hoiylight:BAAANQAECgUIBwAAAA==.Holybeavis:BAAANQAECgUICAAAAA==.Holydh:BAABNQAECn8XAAMXAAoK5AjCDACfAAAYAAgKpgjvTwBZAQAXAAcKCAbCDACfAAAAAA==.Holydragonn:BAAANQAECgEIAQAAAA==.Holyhunt:BAABNQAECn8ZAAMZAAkKZR0sBAC/AQAZAAcKfxwsBAC/AQABAAMKHx/bGgHKAAABNQAECgoKPgAVAOEfAA==.Holylock:BAAANQAECgQICAAAAA==.Holymage:BAABNQAECn8+AAIVAAoK4R9sCwCoAwAVAAoK4R9sCwCoAwAAAA==.Holyseeker:BAABNQAECn8lAAMRAAkK6CD+CQA/AgARAAkK6CD+CQA/AgAGAAEKvgmSHwE2AAABNQAECgoKPgAVAOEfAA==.Holyshaman:BAAANQAECgUICQAAAA==.Holywarrior:BAABNQAECn8fAAMJAAoKAA/0EgD2AQAJAAoKAA/0EgD2AQAKAAEKAADeSwE7AAAAAA==.Holyymonk:BAAANQAECgQICAAAAA==.Holyyseeker:BAABNQAECn8WAAMQAAkKIgpaGQDCAAAQAAkK3whaGQDCAAARAAMKggzjUwGaAAAAAA==.Hottamalie:BAABNQAECn8eAAIVAAcKXSKTBwBUAgAVAAcKXSKTBwBUAgAAAA==.',
Ia='Iampally:BAABNQAECn8rAAIQAAkKACGhAgAVAgAQAAkKACGhAgAVAgAAAA==.',
Ic='Iceyoyomak:BAAANQAECggIEAABNQAECgoKLAAGACciAA==.Icyloadz:BAAANQAECggIDQAAAA==.',
Im='Imdemonic:BAAANQAECgQICAAAAA==.Imogen:BAAANQADCgYIBgAAAA==.',
Ja='Jazashi:BAAANQADCggIDgAAAQ==.',
Jo='Jonesknight:BAAANQADCgUIBQABNQAECgQIDgAHAAAAAA==.',
Ka='Kailler:BAAANQAECgQIDQAAAA==.Kazukisdh:BAAANQAECggIDAABNQAECgoKPgAVAOEfAA==.',
Ke='Keg:BAACNQAFFH8ZAAIaAAcKKSYaAAAgAwAaAAcKKSYaAAAgAwA1AAQKfycAAhoACgriJlwAAPEDABoACgriJlwAAPEDAAAA.',
Ki='Kittyhawk:BAABNQAECn8lAAICAAoK1xlGDQCoAQACAAoK1xlGDQCoAQAAAA==.',
Kl='Klassic:BAAANQADCgYICQAAAA==.',
Kr='Krimski:BAAANQADCgIIAgAAAA==.',
Ks='Kstab:BAABNQAECn8iAAIbAAgKNRAVHQDqAQAbAAgKNRAVHQDqAQAAAA==.',
Ku='Kuromeow:BAACNQAFFH8GAAIVAAMK8RcVMQAHAQAVAAMK8RcVMQAHAQA1AAQKfy4AAhUACgofIaADALoCABUACgofIaADALoCAAAA.',
La='Larake:BAABNQAECn8cAAIcAAcKegiIBwAAAQAcAAcKegiIBwAAAQAAAA==.Lazypie:BAAANQAECgQIBAAAAA==.',
Li='Lightkeeper:BAABNQAECn8WAAMFAAYK2Ba5PABFAQAFAAUKvhG5PABFAQAEAAUKNAX0ZQCiAAAAAA==.Lilithhunter:BAAANQADCgIIAgAAAA==.Lilkneebiter:BAAANQADCgUIBQAAAA==.Litdealer:BAAANQAECgQICAABNQAFFAQIBgAKAEUMAA==.',
Lo='Lockinaround:BAAANQAECgQIDgAAAA==.',
Ma='Makshifu:BAAANQAECgQIBAABNQAECgoKLAAGACciAA==.Manaplague:BAAANQAECgEIAQAAAA==.Marleau:BAABNQAECn8YAAMdAAUKxRvEKwAzAQAdAAQKtRzEKwAzAQACAAUKsA5BugAdAQAAAA==.Martymcfly:BAAANQAECgYIDAAAAA==.',
Me='Menion:BAABNQAECn8bAAMRAAkKfR9rLQASAwARAAkKfR9rLQASAwAQAAMKjBGvVgCGAAAAAA==.Meruk:BAAANQAECgYICwAAAA==.Mesoholy:BAAANQAECgQICAABNQAECgYIEAAHAAAAAA==.',
Mk='Mk:BAEANQAECgQIBQABNQAECgkJJwASABYcAA==.',
Mo='Moreldor:BAAANQADCgQJCAAAAA==.',
Mu='Muggle:BAAANQABCggIEwAAAA==.',
Ne='Nefarius:BAAANQAECgYIBgABNQAFFAIIBgAFAFcRAA==.',
Ni='Nillfurio:BAAANQAECgYIBgAAAA==.Ninjitsû:BAABNQAECn8pAAMYAAoKlBvDCwCVAQAeAAgK3RtzGgCFAgAYAAkKjRnDCwCVAQAAAA==.',
No='Noideea:BAABNQAECn8oAAIKAAkK4iLiHgA8AwAKAAkK4iLiHgA8AwAAAA==.',
Np='Np:BAAANQADCgUIBQAAAA==.',
Ny='Nyke:BAAANQAECgQIBgAAAA==.',
Od='Odinson:BAABNQAECn8YAAICAAYKMAhQswAsAQACAAYKMAhQswAsAQAAAA==.',
Om='Omie:BAABNQAECn8lAAIOAAgK4BwSFACnAQAOAAgK4BwSFACnAQAAAA==.',
Pa='Paulos:BAAANQAECgMIBAAAAA==.',
Ph='Phanick:BAAANQAECggICAAAAA==.',
Pi='Piouspancake:BAAANQAECgUIBQAAAA==.',
Qi='Qilin:BAAANQAECgUIBwAAAA==.',
Ra='Raythe:BAABNQAECn8ZAAIYAAgKhRO2OgDfAQAYAAgKhRO2OgDfAQAAAA==.Razzeman:BAAANQABCgYIBgAAAA==.',
Re='Reverend:BAAANQADCgQIBAAAAA==.',
Ru='Ruck:BAAANQAECggIBwABNQAECggIFQAJAO8bAA==.Rucker:BAABNQAECn8VAAMJAAgK7xvMDABnAgAJAAgK7xvMDABnAgAKAAIKdAVSwQA6AAAAAA==.Ruckkin:BAAANQAECgQIAwABNQAECggIFQAJAO8bAA==.Rucksy:BAAANQAECgQIDgABNQAECggIFQAJAO8bAA==.',
Ry='Ryan:BAABNQAECn8VAAMRAAYKMhtDzwB9AQARAAUK+hxDzwB9AQAGAAQKgx9blwBbAQAAAA==.',
Se='Senchá:BAABNQAECn8hAAINAAgKAyUwAwBzAwANAAgKAyUwAwBzAwABNQAECggILQAaAI8fAA==.Seraphae:BAAANQAECgUIDgAAAA==.Sereb:BAAANQADCgUIBQAAAA==.',
Sh='Shadeorheals:BAAANQAECggICgAAAA==.Shalana:BAAANQADCgQIBAAAAA==.Sheong:BAABNQAECn8tAAIaAAgKjx/WCACaAgAaAAgKjx/WCACaAgAAAA==.Shèrlock:BAABNQAECn8gAAIOAAkKaBSSGACQAQAOAAkKaBSSGACQAQAAAA==.',
Si='Silverfox:BAABNQAECn8aAAMdAAoK9iBJEgA2AwAdAAoK9iBJEgA2AwACAAIKAAAgBQGDAAABNQAECgoKLAAGACciAA==.',
Sk='Skera:BAABNQAECn8WAAIKAAoKeA56WADoAAAKAAoKeA56WADoAAAAAA==.Skinnypuppy:BAAANQAECgIIAgAAAA==.Skippydippy:BAAANQAECgYIEAAAAA==.Skye:BAAANQAECgUIDAAAAA==.',
Sl='Sleepysniper:BAABNQAECn8bAAIZAAgK8R48FAC+AgAZAAgK8R48FAC+AgABNQAECgkJKAAKAOIiAA==.',
Sp='Spelldeala:BAAANQAECgQICAABNQAFFAQIBgAKAEUMAA==.',
Ss='Ssgtusmc:BAABNQAECn8iAAIJAAcKwwOaKgDkAAAJAAcKwwOaKgDkAAAAAA==.Ssjgodxx:BAABNQAECn8mAAIKAAoKah1pBgBjAgAKAAoKah1pBgBjAgABNQAECgoKKQAYAJQbAA==.',
St='Stargasm:BAABNQAECn9FAAIEAAoK8xXuRgBSAgAEAAoK8xXuRgBSAgAAAA==.',
Sw='Swiftmend:BAAANQAECgYIDgABNQAFFAQIBgAKAEUMAA==.Swinghardz:BAAANQAECgQIBgAAAA==.',
Ta='Taggen:BAAANQAECgEIAQAAAA==.Tardis:BAAANQADCgEIAQAAAA==.',
Te='Terainer:BAAANQADCggIDQAAAA==.',
Th='Theia:BAAANQADCgIIAgAAAA==.Thomassian:BAAANQABCgIIAgAAAA==.Throbbinknob:BAAANQAECgEIAQAAAA==.',
Ti='Timewing:BAABNQAECn8eAAMfAAkK3A/YGgAYAgAfAAkK3A/YGgAYAgAgAAEKPg6aJQAuAAAAAA==.Tinkerspell:BAAANQADCgQIBAAAAA==.',
To='Toefunk:BAAANQADCgQIBAAAAA==.',
Tr='Transformer:BAAANQAECggIDAAAAA==.Triblequest:BAAANQADCgYIBgAAAA==.Trotndot:BAAANQADCgIJAgAAAA==.',
Tw='Twiltock:BAAANQAECgEJAQAAAA==.',
Va='Valerion:BAAANQADCgYIBgAAAA==.Valessa:BAABNQAECn8aAAIWAAYKMAaEJADJAAAWAAYKMAaEJADJAAAAAA==.',
Ve='Vektendra:BAAANQADCgYIBgAAAA==.',
Vi='Vilbald:BAAANQADCgIIAwAAAA==.Vita:BAAANQAECgIIBQAAAA==.',
['Vø']='Vødu:BAAANQADCggICAAAAA==.',
Wi='Windflower:BAABNQAECn8bAAIGAAoKKxi6FACuAQAGAAoKKxi6FACuAQABNQAECgoKMAAVAJkeAA==.',
Wo='Woltrik:BAAANQAECgQIBAAAAA==.Worldbreakèr:BAAANQAECggIBQAAAA==.',
['Wÿ']='Wÿcked:BAAANQAECgQICgAAAA==.',
Xi='Xiaobao:BAABNQAECn8VAAIMAAcKQBroGgDNAQAMAAcKQBroGgDNAQAAAA==.Xiaoduoduo:BAABNQAECn8sAAQGAAoKJyJ6DABkAwAGAAoKJyJ6DABkAwARAAcKjCIgRwC/AgAQAAMK2CGHOQAhAQAAAA==.Xiaomak:BAABNQAECn8mAAMBAAkKPiEDMQDZAgABAAkKPiEDMQDZAgAZAAUKcxCqSAAYAQABNQAECgoKLAAGACciAA==.',
Xx='Xxschafer:BAAANQADCgUIBQAAAA==.',
Za='Zab:BAAANQAECgUIBQABNQAECggIJAARAGwZAA==.Zabexer:BAAANQADCgIIAgAAAA==.',
Ze='Zehelith:BAAANQADCgQIBAABNQAECgkJJwAGALgkAA==.Zeroskills:BAABNQAECn8xAAIbAAoKdgqMGwD6AQAbAAoKdgqMGwD6AQAAAA==.',
Zu='Zulinar:BAAANQAECgYIEwAAAA==.',
Zy='Zyierah:BAAANQADCgQIBAAAAA==.',
['Zé']='Zépar:BAAANQAECgQIBAABNQAECgQICgAHAAAAAA==.',
['Às']='Àsmodeus:BAABNQAECn8aAAQNAAoKkhHAGgBUAQANAAcKUhTAGgBUAQAMAAYKkgtMIACTAAAhAAIK3gJ3qQBEAAAAAA==.',
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
