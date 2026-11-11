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

local lookup = {'Hunter-BeastMastery','Paladin-Protection','Shaman-Elemental','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Warlock-Destruction','DeathKnight-Frost','Warrior-Protection','Warrior-Arms','Warrior-Fury','Druid-Guardian','Druid-Feral','Druid-Balance','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Monk-Brewmaster','Rogue-Assassination','Hunter-Survival','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Mage-Fire','DemonHunter-Devourer','Rogue-Subtlety','Evoker-Devastation','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Aberdine:BAAANQAECgIIAgAAAA==.',
Ac='Acadya:BAABNQAECn8tAAIBAAoKPR+jLQDlAgABAAoKPR+jLQDlAgAAAA==.Accar:BAABNQAECn8ZAAICAAoK5BL9IQDTAQACAAoK5BL9IQDTAQAAAA==.Achu:BAABNQAECn8fAAIDAAoKzyBgDgDyAgADAAoKzyBgDgDyAgABNQAFFAMIDQAEADkgAA==.',
Ae='Aellori:BAAANQADCgcJBwAAAA==.',
Ag='Agrias:BAABNQAECn8aAAMFAAkKyRsaNwCLAgAFAAkKyRsaNwCLAgAGAAEKAACcigAfAAAAAA==.',
Al='Algodón:BAAANQADCgQIBgAAAA==.Althea:BAABNQAECn8dAAMHAAkK7BiHMwCWAgAHAAkK7BiHMwCWAgAIAAEKvgBXrQERAAAAAA==.',
Am='Amaltheah:BAAANQADCgQIBAABNQAECgMIAwAJAAAAAA==.Ambry:BAAANQABCgIIAgABNQADCgcIBwAJAAAAAA==.Ambryosia:BAAANQADCgcIBwAAAA==.',
Ar='Arcanyounot:BAAANQADCgcIGQABNQAECgUIGAAKANkJAA==.',
As='Aspir:BAEANQAECgQIBAABNQAFFAYIEgALAAUWAA==.',
Au='Aubury:BAAANQADCgEIAQABNQAECgEIAQAJAAAAAA==.',
Av='Aviendha:BAAANQAECgMIAwAAAA==.Avvenge:BAAANQADCgcIBwAAAA==.',
Az='Azaria:BAAANQAECgQIBgAAAA==.',
Ba='Barricade:BAABNQAECn80AAQMAAoKdBSREAAfAgAMAAoKdBSREAAfAgANAAIKZASdFQFBAAAOAAEKAACNMAA9AAAAAA==.',
Bc='Bcshaman:BAAANQADCgYJBgABNQAECgcIBwAJAAAAAA==.Bcwarrior:BAAANQAECgYIEAABNQAECgcIBwAJAAAAAA==.',
Be='Bertabeef:BAAANQADCgYIBgAAAA==.',
Bi='Biróg:BAABNQAECn8YAAMPAAUKuh/6IgBVAQAPAAUKuh/6IgBVAQAQAAQKQQ93JwDSAAAAAA==.',
Bl='Blizzaga:BAABNQAECn8vAAMEAAkK8BLZRQDjAQAEAAkK8BLZRQDjAQALAAIKfQ3UlgBnAAAAAA==.Blutrünstig:BAAANQADCgYIDAABNQAECgEIAQAJAAAAAA==.',
Bo='Bobbyperu:BAAANQADCgUICgAAAA==.Bootowsky:BAAANQADCggIDAAAAA==.',
Br='Bramian:BAAANQADCgEIAQABNQAECgEIAQAJAAAAAA==.Brocephus:BAABNQAECn8pAAMRAAgK/wtGOQA4AQARAAgK/wtGOQA4AQASAAIKqgd8bAA8AAAAAA==.Bruno:BAAANQADCgUIBwAAAA==.',
Bu='Burrgold:BAAANQAECgQIBQAAAA==.',
Ca='Callesa:BAAANQADCgUIBQAAAA==.Carpathiá:BAAANQAECgEJAgAAAA==.',
Ch='Chaoticelf:BAAANQADCgQIBAAAAA==.Chubzilla:BAAANQAECgQIBAAAAA==.',
Cl='Clockie:BAABNQAECn8oAAMTAAoKjSSFAwBpAgAUAAgKayEtNgCyAgATAAgKDiSFAwBpAgABNQAFFAMIDQAEADkgAA==.Clõüd:BAACNQAFFH8NAAMCAAYKWA4bCQDBAAACAAYKQw4bCQDBAAAIAAMKEw/KJgCIAAA1AAQKf18AAwgACgpeJCwnALkCAAgACgpeJCwnALkCAAIACAq/Gs0XADsCAAAA.',
Co='Combusting:BAAANQAECgIIAgAAAA==.Cosmo:BAAANQABCgMIAwAAAA==.',
Cr='Crimsonrain:BAAANQAECggICAAAAA==.',
Cu='Cuitlahuac:BAAANQADCgcIBwAAAA==.',
Cy='Cynthigosa:BAAANQAECgUICQAAAA==.',
Da='Daarion:BAAANQABCgcIEQAAAA==.Darrkmann:BAAANQAECgcIEgAAAA==.',
De='Demonicspeak:BAACNQAFFH8IAAIUAAMKgAW3GwC6AAAUAAMKgAW3GwC6AAA1AAQKfx8AAhQACgo7EwhaAEgCABQACgo7EwhaAEgCAAAA.Densepancake:BAABNQAECn8VAAINAAUKXBTB3AAyAQANAAUKXBTB3AAyAQAAAA==.',
Di='Dianeneedrol:BAABNQAECn8jAAIVAAcKwgTrPACtAAAVAAcKwgTrPACtAAAAAA==.Dietpally:BAAANQABCgEIAQAAAA==.Dingle:BAAANQADCgUIBwAAAA==.Dinkster:BAAANQADCggICAAAAA==.',
Dk='Dkcloud:BAAANQADCgcIBwABNQAFFAYIDQACAFgOAA==.',
Do='Dotzillah:BAAANQAECgUIBwAAAA==.',
Ec='Echidna:BAAANQADCgYIBgABNQAECgMIBAAJAAAAAA==.Eclesiastes:BAAANQADCgEIAQAAAA==.',
El='Elcapnkikazz:BAABNQAECn9NAAMHAAoKFxUBKwBqAgAHAAoKFxUBKwBqAgAIAAYKFgXqQAG4AAAAAA==.Ellex:BAAANQAECgEIAgAAAA==.Ellexstrasza:BAAANQADCggIFQABNQAECgEIAgAJAAAAAA==.Elyssa:BAAANQAECgUICQABNQAECgkJOgAWALwdAA==.',
En='Enhancdepeen:BAAANQAECggIDwAAAA==.',
Er='Erìs:BAAANQAECgMIBgAAAA==.Erïck:BAABNQAECn8iAAIUAAkKbRHJQwD4AQAUAAkKbRHJQwD4AQAAAA==.',
Es='Estellandra:BAAANQABCggICAAAAA==.',
Ev='Evercy:BAAANQADCgYICgAAAA==.Eviseria:BAAANQABCgQIBgAAAA==.',
Fa='Faithykinz:BAAANQAECgMIBAAAAA==.',
Fi='Fininho:BAAANQAECgcIAQAAAA==.',
Fr='Frostlowe:BAAANQADCgMIBAAAAA==.',
['Fú']='Fúsion:BAEBNQAECn8oAAIXAAoKiCLbAgAbAwAXAAoKiCLbAgAbAwAAAA==.',
Go='Gonamanar:BAABNQAECn8bAAMBAAcKNx6JfQATAgABAAcKNx6JfQATAgAYAAUKNQ/KDAADAQAAAA==.',
Gr='Grandreaper:BAAANQADCgUIBQAAAA==.Grimfall:BAAANQADCggICAAAAA==.Gripology:BAABNQAECn8cAAMEAAgK1RW6ZgBYAQAEAAgK1RW6ZgBYAQAZAAEKAAC4oAAAAAABNQAFFAQIBgANAEUMAA==.',
Ha='Happyhour:BAABNQAECn82AAMaAAkKnAqXHwDGAAAbAAgKDwmIwgAQAQAaAAQKvgqXHwDGAAAAAA==.Harryportals:BAAANQADCgUIBwAAAA==.Hashball:BAAANQAECggICAABNQAECgoKPAANAL4kAA==.',
He='Hexidecimal:BAABNQAECn8aAAMGAAkKNxX1HwA7AgAGAAkKNxX1HwA7AgAFAAEKGAMYCgEgAAAAAA==.',
Hi='Highlowe:BAAANQAECgIIAgAAAA==.',
Ho='Hoiylight:BAAANQAECgYICQAAAA==.Holybeavis:BAAANQAECgUICAAAAA==.Holydh:BAABNQAECn8dAAMcAAoK3QrvTwBZAQAcAAkK8QnvTwBZAQAdAAcK9QZpHQCOAAAAAA==.Holydragonn:BAAANQAECgEIAQAAAA==.Holyhunt:BAABNQAECn8aAAMeAAoK+xmAHQB2AQAeAAgKuBiAHQB2AQABAAMKHx/bGgHKAAABNQAFFAIICgAaAHYjAA==.Holylock:BAAANQAECgUIDAAAAA==.Holymage:BAACNQAFFH8KAAMaAAIKdiMRCwBgAAAbAAIKZiEkKgC8AAAaAAEKfyERCwBgAAA1AAQKf1EABBsACgoBJWwLAKgDABsACgoBJWwLAKgDABoAAgoWI0weAM8AAB8AAQpAIDQJAF8AAAAA.Holyseeker:BAABNQAECn81AAQIAAkKTCJAKwCnAgAIAAkKTCJAKwCnAgACAAQKUxN7PACnAAAHAAEKvgmSHwE2AAABNQAFFAIICgAaAHYjAA==.Holyshaman:BAAANQAECgYIDwAAAA==.Holywarrior:BAABNQAECn8kAAMMAAoKdhH0EgD2AQAMAAoKdhH0EgD2AQANAAEKAADeSwE7AAAAAA==.Holyymonk:BAAANQAECgUIEQAAAA==.Holyyseeker:BAABNQAECn8cAAMCAAkK4g2ENwAuAQACAAkKtQqENwAuAQAIAAQKfw7jUwGaAAAAAA==.Hottamalie:BAABNQAECn8gAAIbAAgK8h23TQAYAgAbAAgK8h23TQAYAgAAAA==.',
Ia='Iampally:BAABNQAECn9DAAICAAkK5yMuAwA5AwACAAkK5yMuAwA5AwAAAA==.',
Ic='Iceyoyomak:BAAANQAECggIEAABNQAECgoKOAAHAAUjAA==.Icyloadz:BAAANQAECggIDQAAAA==.',
Im='Imdemonic:BAAANQAECgQICAAAAA==.Imogen:BAAANQADCgYIBgAAAA==.',
Ja='Jazashi:BAAANQADCggIDgAAAQ==.',
Jo='Jonesknight:BAAANQADCgUIBQABNQAECgUIGAAKANkJAA==.Jonnytsunami:BAAANQAECgMIAwAAAA==.',
Ka='Kailler:BAAANQAECgQIDQAAAA==.Kazukisdh:BAABNQAECn8fAAMdAAoK5BO9CADPAQAdAAkK4xO9CADPAQAgAAoKJAubMAD+AAABNQAFFAIICgAaAHYjAA==.',
Ke='Keg:BAACNQAFFH8cAAIWAAgKISYaAAAgAwAWAAgKISYaAAAgAwA1AAQKfywAAhYACgriJlwAAPEDABYACgriJlwAAPEDAAAA.',
Ki='Kittyhawk:BAABNQAECn84AAIDAAoKsB0dGwCHAgADAAoKsB0dGwCHAgAAAA==.',
Kl='Klassic:BAAANQADCgYICQAAAA==.Klixx:BAAANQADCgYIDgAAAA==.',
Kr='Krimski:BAAANQADCgIIAgAAAA==.',
Ks='Kstab:BAABNQAECn8xAAIhAAkKcRAVHQDqAQAhAAkKcRAVHQDqAQAAAA==.',
Ku='Kuromeow:BAACNQAFFH8KAAIbAAQK8RcVMQAHAQAbAAQK8RcVMQAHAQA1AAQKfzkAAhsACgpAI2YoAJICABsACgpAI2YoAJICAAAA.',
La='Larake:BAABNQAECn8gAAIiAAoK8giZDgBHAQAiAAoK8giZDgBHAQAAAA==.Lazypie:BAAANQAECgQIBAAAAA==.',
Li='Lightkeeper:BAABNQAECn8fAAMGAAYK7RK5PABFAQAGAAYK7RK5PABFAQAFAAUKNAWIxgCHAAAAAA==.Lilithhunter:BAAANQADCgIIAgAAAA==.Lilkneebiter:BAAANQADCgUIBQAAAA==.Litdealer:BAAANQAECgQICAABNQAFFAQIBgANAEUMAA==.',
Lo='Lockinaround:BAABNQAECn8YAAIKAAUK2Qk2OADgAAAKAAUK2Qk2OADgAAAAAA==.Loozey:BAAANQADCgUIBgAAAA==.',
Ma='Magicfinger:BAAANQAECgIIAQAAAA==.Makshifu:BAAANQAECgYIBQABNQAECgoKOAAHAAUjAA==.Manaplague:BAAANQAECgEIAQAAAA==.Manashotz:BAAANQAECgEIAQAAAA==.Marleau:BAABNQAECn8ZAAMjAAYK6xuqagBdAQAjAAUKsxyqagBdAQADAAUKsA5BugAdAQAAAA==.Martymcfly:BAAANQAECgYIDAAAAA==.',
Me='Menion:BAABNQAECn8bAAMIAAkKfR9rLQASAwAIAAkKfR9rLQASAwACAAMKjBGvVgCGAAAAAA==.Meruk:BAAANQAECgcIDAAAAA==.Mesoholy:BAAANQAECgQICAABNQAECgkJHwAHAFImAA==.',
Mk='Mk:BAEANQAECgQIBQABNQAECgoKPQAVAFkfAA==.',
Mo='Moreldor:BAAANQADCgQJCAAAAA==.',
Mu='Muggle:BAAANQABCggIEwAAAA==.',
Ne='Nefarius:BAABNQAECn8VAAIbAAoKTxsuMwBqAgAbAAoKTxsuMwBqAgABNQAFFAIIBgAGAFcRAA==.',
Ni='Nillfurio:BAAANQAECgYIBgAAAA==.Ninjitsû:BAABNQAECn81AAMcAAoKdB9CEQCQAgAcAAoKch5CEQCQAgAgAAgK3RtzGgCFAgABNQAECgoKPAANAL4kAA==.',
No='Noideea:BAABNQAECn8oAAINAAkK4iLiHgA8AwANAAkK4iLiHgA8AwAAAA==.',
Np='Np:BAAANQADCgUIBQAAAA==.',
Ny='Nyke:BAAANQAECgQIBgAAAA==.',
Od='Odinson:BAABNQAECn8hAAIDAAgKlggpdAAXAQADAAgKlggpdAAXAQAAAA==.',
Oi='Oiiaiooiai:BAAANQAECgMIBAAAAA==.',
Om='Omie:BAABNQAECn8xAAIUAAoKHRurLQBJAgAUAAoKHRurLQBJAgAAAA==.',
Pa='Paulos:BAAANQAECgMIBAAAAA==.',
Ph='Phanick:BAAANQAECggICAAAAA==.',
Pi='Piouspancake:BAAANQAECgQIBQABNQAECgUIFQANAFwUAA==.',
Ps='Psylocké:BAAANQAECggICQAAAA==.',
Qi='Qilin:BAAANQAECgUIBwAAAA==.',
Ra='Rainymoon:BAAANQABCgQIBAAAAA==.Raythe:BAABNQAECn8gAAIcAAgKhRO2OgDfAQAcAAgKhRO2OgDfAQAAAA==.Razzeman:BAAANQABCgYICAAAAA==.',
Re='Reverend:BAAANQAECgEIAQAAAA==.',
Ru='Ruck:BAAANQAECggICgABNQAECgoKHwAMAJobAA==.Rucker:BAABNQAECn8fAAQMAAoKmhvMDABnAgAMAAgK9B3MDABnAgAOAAUK3A9DGQDYAAANAAQKcArC3ACmAAAAAA==.Ruckkin:BAAANQAECgQIAwABNQAECgoKHwAMAJobAA==.Rucksin:BAAANQAECggICgABNQAECgoKHwAMAJobAA==.Rucksy:BAABNQAECn8UAAMCAAYK3R0xLgBsAQACAAYK3R0xLgBsAQAIAAEKgA1zfQE7AAABNQAECgoKHwAMAJobAA==.',
Ry='Ryan:BAABNQAECn8VAAMIAAYKMhtDzwB9AQAIAAUK+hxDzwB9AQAHAAQKgx9blwBbAQAAAA==.',
Se='Senchá:BAABNQAECn8hAAIQAAgKAyUwAwBzAwAQAAgKAyUwAwBzAwAAAA==.Seraphae:BAAANQAECgcIDgAAAA==.Sereb:BAAANQADCgUIBQAAAA==.',
Sh='Shadeorheals:BAAANQAECggIDQAAAA==.Shalana:BAAANQADCgQIBAAAAA==.Shardik:BAAANQAECgMIBQAAAA==.Sheong:BAABNQAECn86AAIWAAkKvB3ZBQAiAgAWAAkKvB3ZBQAiAgAAAA==.Shèrlock:BAABNQAECn8kAAIUAAoKkhV0SADpAQAUAAoKkhV0SADpAQAAAA==.',
Si='Silverfox:BAABNQAECn8jAAMjAAoKRSJJEgA2AwAjAAoKRSJJEgA2AwADAAIKAAAgBQGDAAABNQAECgoKOAAHAAUjAA==.',
Sk='Skera:BAABNQAECn8aAAINAAoKoQ40pADCAQANAAoKoQ40pADCAQAAAA==.Skinnypuppy:BAAANQAECgIIAgAAAA==.Skippydippy:BAABNQAECn8aAAMEAAcKESMxMwBBAgAEAAcKYiExMwBBAgALAAYKAxy6NQC1AQAAAA==.Skye:BAAANQAECgUIDAAAAA==.',
Sl='Sleepysniper:BAABNQAECn8bAAIeAAgK8R48FAC+AgAeAAgK8R48FAC+AgABNQAECgkJKAANAOIiAA==.',
Sm='Sm:BAAANQADCggIDAAAAA==.',
Sp='Spelldeala:BAAANQAECgQICAABNQAFFAQIBgANAEUMAA==.',
Ss='Ssgtusmc:BAABNQAECn8uAAIMAAgKcgTWKACiAAAMAAgKcgTWKACiAAAAAA==.Ssjgodxx:BAABNQAECn88AAINAAoKviRsBwBQAwANAAoKviRsBwBQAwAAAA==.',
St='Stargasm:BAABNQAECn90AAIFAAoK5RjBLACAAgAFAAoK5RjBLACAAgAAAA==.',
Sw='Swiftmend:BAAANQAECgcIDgABNQAFFAQIBgANAEUMAA==.Swinghardz:BAAANQAECgQIBgAAAA==.',
Ta='Taggen:BAAANQAECgEIAQAAAA==.Taurentino:BAAANQAECgcIBwAAAA==.',
Te='Terainer:BAAANQADCggIDQAAAA==.',
Th='Theia:BAAANQADCgIIAgAAAA==.Thomassian:BAAANQABCgIIAgAAAA==.Throbbinknob:BAAANQAECgEIAQAAAA==.',
Ti='Timelord:BAAANQADCgEIAQAAAA==.Timewing:BAABNQAECn8eAAMkAAkK3A/YGgAYAgAkAAkK3A/YGgAYAgAlAAEKPg6aJQAuAAAAAA==.Tinkerspell:BAAANQADCgQIBAAAAA==.',
To='Toefunk:BAAANQADCgQIBAAAAA==.',
Tr='Transformer:BAAANQAECggIDAAAAA==.Triblequest:BAAANQADCgYIBgAAAA==.Trotndot:BAAANQADCgIJAgAAAA==.',
Tw='Twiltock:BAAANQAECgEJAQAAAA==.Twizztyd:BAABNQAECn8XAAIGAAoKCwxHHQCPAQAGAAoKCwxHHQCPAQAAAA==.',
Ut='Utotem:BAAANQAECgQIBAAAAA==.',
Va='Valerion:BAAANQADCgYIBgAAAA==.Valessa:BAABNQAECn8gAAIaAAcKsQWEJADJAAAaAAcKsQWEJADJAAAAAA==.',
Ve='Vektendra:BAAANQADCgYIBgAAAA==.',
Vi='Vilbald:BAAANQADCgIIAwAAAA==.Vita:BAAANQAECgIIBQAAAA==.',
['Vø']='Vødu:BAAANQADCggICAAAAA==.',
Wi='Windflower:BAABNQAECn8wAAIHAAoKOR44EwARAwAHAAoKOR44EwARAwABNQAFFAIICgAbAAAdAA==.Wizbee:BAAANQADCggICQAAAA==.',
Wo='Woltrik:BAAANQAECgQIBAAAAA==.Worldbreakèr:BAAANQAECggIBQAAAA==.',
['Wÿ']='Wÿcked:BAAANQAECgQICgAAAA==.',
Xi='Xiaobao:BAACNQAFFH8GAAIPAAIKTxtOBQChAAAPAAIKTxtOBQChAAA1AAQKfx4AAg8ACQr6IFIOAD8CAA8ACQr6IFIOAD8CAAAA.Xiaoduoduo:BAABNQAECn84AAQHAAoKBSN6DABkAwAHAAoKBSN6DABkAwAIAAgKjCIgRwC/AgACAAMKjSKHOQAhAQAAAA==.Xiaomak:BAABNQAECn8mAAMBAAkKPiEDMQDZAgABAAkKPiEDMQDZAgAeAAUKcxCqSAAYAQABNQAECgoKOAAHAAUjAA==.',
Xx='Xxschafer:BAAANQADCgUIBQAAAA==.',
Za='Zab:BAAANQAECgUIBQABNQAECggIJQAIAGwZAA==.Zabexer:BAAANQADCgIIAgAAAA==.',
Ze='Zehelith:BAAANQADCgQIBAABNQAECgkJJwAHALgkAA==.Zeroskills:BAABNQAECn9DAAIhAAoKhwyMGwD6AQAhAAoKhwyMGwD6AQAAAA==.',
Zu='Zulinar:BAABNQAECn8dAAIjAAkK/whEfwAfAQAjAAkK/whEfwAfAQAAAA==.',
Zy='Zyierah:BAAANQADCgQIBAAAAA==.',
['Zé']='Zépar:BAAANQAECgQIBAABNQAECgQICgAJAAAAAA==.',
['Às']='Àsmodeus:BAABNQAECn8qAAQQAAoKkhHAGgBUAQAQAAcKUhTAGgBUAQAPAAkKnwoGMQD5AAARAAIK3gJ3qQBEAAAAAA==.',
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
