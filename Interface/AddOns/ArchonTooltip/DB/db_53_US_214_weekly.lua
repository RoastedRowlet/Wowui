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

local lookup = {'Hunter-BeastMastery','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Paladin-Holy','Unknown-Unknown','DeathKnight-Frost','Warrior-Protection','Warrior-Fury','Warlock-Demonology','Warlock-Affliction','Paladin-Protection','Paladin-Retribution','Rogue-Assassination','Warrior-Arms','Mage-Frost','Mage-Arcane','Monk-Brewmaster','Shaman-Elemental','Rogue-Subtlety','Evoker-Devastation','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Feral','Shaman-Restoration','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Aberdine:BAAANQAECgIIAgAAAA==.',
Ac='Acadya:BAABNQAECn8dAAIBAAkKyxuULADmAgABAAkKyxuULADmAgAAAA==.Accar:BAAANQAECgcIEAAAAA==.Achu:BAAANQAECgYIDgABNQAECgkJMQACABEjAA==.Acylies:BAAANQADCgUICAAAAA==.',
Ae='Aellori:BAAANQADCgcJBwAAAA==.',
Ag='Agrias:BAABNQAECn8aAAMDAAkKyRtINgCMAgADAAkKyRtINgCMAgAEAAEKAADSiAAfAAAAAA==.',
Al='Algodón:BAAANQADCgQIBgAAAA==.Alindriel:BAAANQADCgMIAwAAAA==.Althea:BAABNQAECn8aAAIFAAkK7Bj1MgCWAgAFAAkK7Bj1MgCWAgAAAA==.',
Am='Amaltheah:BAAANQADCgQIBAABNQAECgMIAwAGAAAAAA==.Ambry:BAAANQABCgIIAgABNQADCgcIBwAGAAAAAA==.Ambryosia:BAAANQADCgcIBwAAAA==.',
Ar='Arcanyounot:BAAANQADCgcIGQABNQAECgUICgAGAAAAAA==.',
As='Aspir:BAEANQAECgQIBAABNQAFFAQIDAAHAPwWAA==.',
Au='Aubury:BAAANQADCgEIAQABNQADCgQIBAAGAAAAAA==.',
Av='Aviendha:BAAANQAECgMIAwAAAA==.Avvenge:BAAANQADCgcIBwAAAA==.',
Ba='Barricade:BAABNQAECn8gAAMIAAgK7BZgEAAfAgAIAAgK7BZgEAAfAgAJAAEKAADnLwA9AAAAAA==.',
Bc='Bcshaman:BAAANQADCgYJBgABNQAECgYIEAAGAAAAAA==.Bcwarrior:BAAANQAECgYIEAAAAA==.',
Be='Bertabeef:BAAANQADCgYIBgAAAA==.',
Bi='Biróg:BAAANQAECgYIEwAAAA==.',
Bl='Blizzaga:BAABNQAECn8qAAMCAAgKixMrRQDjAQACAAgKixMrRQDjAQAHAAIKfQ21kwBnAAAAAA==.Blutrünstig:BAAANQADCgYIDAABNQAECgEIAQAGAAAAAA==.',
Bo='Bobbyperu:BAAANQADCgUICgAAAA==.Bootowsky:BAAANQADCggIDAAAAA==.',
Br='Bramian:BAAANQADCgEIAQABNQADCgQIBAAGAAAAAA==.Brocephus:BAAANQAECgUIDAAAAA==.Bruno:BAAANQADCgUIBwAAAA==.',
Bu='Burrgold:BAAANQAECgIJAgAAAA==.',
Ca='Callesa:BAAANQADCgUIBQAAAA==.Carpathiá:BAAANQAECgEJAgAAAA==.',
Ch='Chaoticelf:BAAANQADCgQIBAAAAA==.Chubzilla:BAAANQAECgQIBAAAAA==.',
Cl='Clockie:BAABNQAECn8fAAMKAAkKYiMeNQCzAgAKAAcKHSIeNQCzAgALAAQKHCYaDQCIAQABNQAECgkJMQACABEjAA==.Clõüd:BAACNQAFFH8JAAMMAAMKhg/4CADBAAAMAAMKag/4CADBAAANAAIKEw/XJQCIAAA1AAQKfz8AAw0ACQpbIqgtAA8DAA0ACQogIqgtAA8DAAwABwp9G4UXADsCAAAA.',
Co='Combusting:BAAANQAECgIIAgAAAA==.Cosmo:BAAANQABCgMIAwAAAA==.',
Cr='Crimsonrain:BAAANQAECggICAAAAA==.',
Cu='Cuitlahuac:BAAANQADCgcIBwAAAA==.',
Cy='Cynthigosa:BAAANQAECgUICQAAAA==.',
Da='Daarion:BAAANQABCgcIEQAAAA==.Darrkmann:BAAANQAECgYIDAAAAA==.',
De='Demonicspeak:BAAANQAFFAEIAQAAAA==.Densepancake:BAAANQAECgUIDwAAAA==.',
Di='Dianeneedrol:BAAANQAECgUIEQAAAA==.Dietpally:BAAANQABCgEIAQAAAA==.Dinkster:BAAANQADCggICAAAAA==.',
Dk='Dkcloud:BAAANQADCgcIBwABNQAFFAMICQAMAIYPAA==.',
Do='Dotzillah:BAAANQADCgMIAwAAAA==.',
Ec='Echidna:BAAANQADCgYIBgABNQAECgMIBAAGAAAAAA==.Eclesiastes:BAAANQADCgEIAQAAAA==.',
El='Elcapnkikazz:BAABNQAECn8lAAMFAAkKTQ1fXgD6AQAFAAkKTQ1fXgD6AQANAAYK7gJVPAG4AAAAAA==.Ellex:BAAANQAECgEIAQAAAA==.Ellexstrasza:BAAANQADCgUIBgABNQAECgEIAQAGAAAAAA==.',
En='Enhancdepeen:BAAANQADCggICAAAAA==.',
Er='Erìs:BAAANQAECgMIBgAAAA==.Erïck:BAAANQAECgUIDgAAAA==.',
Es='Estellandra:BAAANQABCggICAAAAA==.',
Ev='Evercy:BAAANQADCgYICgAAAA==.Eviseria:BAAANQABCgQIBgAAAA==.',
Fa='Faithykinz:BAAANQAECgMIBAAAAA==.',
Fi='Fininho:BAAANQAECgYIAQAAAA==.',
Fr='Frostlowe:BAAANQADCgMIBAAAAA==.',
['Fú']='Fúsion:BAEBNQAECn8YAAIOAAkKYCGXEgDlAgAOAAkKYCGXEgDlAgAAAA==.',
Go='Gonamanar:BAAANQAECgYIEAAAAA==.',
Gr='Grandreaper:BAAANQADCgUIBQAAAA==.Grimfall:BAAANQADCggICAAAAA==.Gripology:BAABNQAECn8UAAICAAYKChb9ZQBYAQACAAYKChb9ZQBYAQABNQAECgkJHgAPADgaAA==.',
Ha='Happyhour:BAABNQAECn8fAAMQAAcKEAmbLgCGAAARAAQKygooZwHlAAAQAAMK6gebLgCGAAAAAA==.Harryportals:BAAANQADCgUIBQAAAA==.',
He='Hexidecimal:BAAANQAECggIEgAAAA==.',
Hi='Highlowe:BAAANQAECgIIAgAAAA==.',
Ho='Hoiylight:BAAANQAECgUIBwAAAA==.Holybeavis:BAAANQAECgUICAAAAA==.Holydh:BAAANQAECgcIDgAAAA==.Holydragonn:BAAANQAECgEIAQAAAA==.Holyhunt:BAAANQAECggIEgABNQAECgkJOAARAKQjAA==.Holylock:BAAANQAECgQIBwAAAA==.Holymage:BAABNQAECn84AAIRAAkKpCMcCwCqAwARAAkKpCMcCwCqAwAAAA==.Holyseeker:BAABNQAECn8fAAMNAAgKoh8ROwDjAgANAAgKoh8ROwDjAgAFAAEKvgk2HAE2AAABNQAECgkJOAARAKQjAA==.Holyshaman:BAAANQAECgQICAAAAA==.Holywarrior:BAABNQAECn8aAAMIAAkKZg/BEgD2AQAIAAkKZg/BEgD2AQAPAAEKAACGRwE7AAAAAA==.Holyymonk:BAAANQAECgIIBQAAAA==.Holyyseeker:BAAANQAECgcIEgAAAA==.Hottamalie:BAABNQAECn8XAAIRAAQKvSCd/QCPAQARAAQKvSCd/QCPAQAAAA==.',
Ia='Iampally:BAABNQAECn8jAAIMAAgKoh5GDgC0AgAMAAgKoh5GDgC0AgAAAA==.',
Ic='Iceyoyomak:BAAANQAECggIEAABNQAECgkJKQAFANEhAA==.Icyloadz:BAAANQAECggIDQAAAA==.',
Im='Imdemonic:BAAANQAECgQICAAAAA==.Imogen:BAAANQADCgYIBgAAAA==.',
Ja='Jazashi:BAAANQADCggIDgAAAQ==.',
Jo='Jonesknight:BAAANQADCgUIBQABNQAECgUICgAGAAAAAA==.',
Ka='Kailler:BAAANQAECgQIDQAAAA==.Kazukisdh:BAAANQAECggICAABNQAECgkJOAARAKQjAA==.',
Ke='Keg:BAACNQAFFH8YAAISAAcKKSYZAAAgAwASAAcKKSYZAAAgAwA1AAQKfyMAAhIACQrUJlcAAPIDABIACQrUJlcAAPIDAAAA.',
Ki='Kittyhawk:BAABNQAECn8dAAITAAkKlBqVLADJAgATAAkKlBqVLADJAgAAAA==.',
Kl='Klassic:BAAANQADCgYICQAAAA==.Klixx:BAAANQADCgYIDgAAAA==.',
Kr='Krimski:BAAANQADCgIIAgAAAA==.',
Ks='Kstab:BAABNQAECn8dAAIUAAgKpg/AHADqAQAUAAgKpg/AHADqAQAAAA==.',
Ku='Kuromeow:BAABNQAECn8kAAIRAAkK7ho3VQDWAgARAAkK7ho3VQDWAgAAAA==.',
La='Larake:BAABNQAECn8VAAIVAAYKNwkxJAAdAQAVAAYKNwkxJAAdAQAAAA==.Lazypie:BAAANQAECgQIBAAAAA==.',
Li='Lightkeeper:BAAANQAECgYIDQAAAA==.Lilithhunter:BAAANQADCgIIAgAAAA==.Lilkneebiter:BAAANQADCgUIBQAAAA==.Litdealer:BAAANQAECgQICAABNQAECgkJHgAPADgaAA==.',
Lo='Lockinaround:BAAANQAECgUICgAAAA==.',
Ma='Makshifu:BAAANQAECgIIAgABNQAECgkJKQAFANEhAA==.Manaplague:BAAANQAECgEIAQAAAA==.Marleau:BAAANQAECgQIDwAAAA==.Martymcfly:BAAANQAECgYIDAAAAA==.',
Me='Menion:BAABNQAECn8bAAMNAAkKfR9pLAATAwANAAkKfR9pLAATAwAMAAMKjBG3VQCGAAAAAA==.Meruk:BAAANQAECgYICwAAAA==.Mesoholy:BAAANQAECgQICAABNQAECgYICgAGAAAAAA==.',
Mk='Mk:BAEANQAECgQIBQABNQAECggIJQAWAOIdAA==.',
Mo='Moreldor:BAAANQADCgQJCAAAAA==.',
Mu='Muggle:BAAANQABCggIDwAAAA==.',
Ne='Nefarius:BAAANQAECgQIBAABNQAECgkJJQAEAK4fAA==.',
Ni='Nillfurio:BAAANQAECgYIBgAAAA==.Ninjitsû:BAABNQAECn8jAAMXAAkKjxoeGgCGAgAXAAgK3RseGgCGAgAYAAgKKRdlLgAuAgAAAA==.',
No='Noideea:BAABNQAECn8oAAIPAAkK4iJMHgA9AwAPAAkK4iJMHgA9AwAAAA==.',
Ny='Nyke:BAAANQAECgQIBgAAAA==.',
Od='Odinson:BAAANQAECgYIEwAAAA==.',
Om='Omie:BAABNQAECn8eAAIKAAgK/hocQACPAgAKAAgK/hocQACPAgAAAA==.',
Pa='Paulos:BAAANQAECgMIBAAAAA==.',
Ph='Phanick:BAAANQAECggICAAAAA==.',
Pi='Piouspancake:BAAANQAECgMIAwAAAA==.',
Qi='Qilin:BAAANQAECgIIAgAAAA==.',
Ra='Raythe:BAAANQAECggIEwAAAA==.Razzeman:BAAANQABCgYIBgAAAA==.',
Re='Reverend:BAAANQADCgQIBAAAAA==.',
Ru='Ruck:BAAANQAECgEJAQABNQAECgcIEAAGAAAAAA==.Rucker:BAAANQAECgcIEAAAAA==.Ruckkin:BAAANQADCgUIBQABNQAECgcIEAAGAAAAAA==.Rucksy:BAAANQAECgQIDAABNQAECgcIEAAGAAAAAA==.',
Ry='Ryan:BAABNQAECn8VAAMNAAYKMhvYywB9AQANAAUK+hzYywB9AQAFAAQKgx/jlQBbAQAAAA==.',
Se='Senchá:BAABNQAECn8hAAIZAAgKAyUhAwBzAwAZAAgKAyUhAwBzAwABNQAECggILQASAI8fAA==.Seraphae:BAAANQAECgUIDgAAAA==.Sereb:BAAANQADCgUIBQAAAA==.',
Sh='Shadeorheals:BAAANQAECgUIBQAAAA==.Shalana:BAAANQADCgQIBAAAAA==.Shardik:BAAANQABCgMIAwAAAA==.Sheong:BAABNQAECn8tAAISAAgKjx/ECACaAgASAAgKjx/ECACaAgAAAA==.Shèrlock:BAABNQAECn8ZAAIKAAgKFxQeYwAsAgAKAAgKFxQeYwAsAgAAAA==.',
Si='Silverfox:BAABNQAECn8ZAAMaAAkKyiDxEQA2AwAaAAkKyiDxEQA2AwATAAIKAAC5AQGDAAABNQAECgkJKQAFANEhAA==.',
Sk='Skera:BAAANQAECgcIEAAAAA==.Skinnypuppy:BAAANQAECgIIAgAAAA==.Skippydippy:BAAANQAECgYIDgAAAA==.Skye:BAAANQAECgUIDAAAAA==.',
Sl='Sleepysniper:BAABNQAECn8bAAIbAAgK8R74EwC+AgAbAAgK8R74EwC+AgABNQAECgkJKAAPAOIiAA==.',
Sp='Spelldeala:BAAANQAECgQICAABNQAECgkJHgAPADgaAA==.',
Ss='Ssgtusmc:BAABNQAECn8iAAIIAAcKwwMVKgDkAAAIAAcKwwMVKgDkAAAAAA==.Ssjgodxx:BAABNQAECn8fAAIPAAkKkhw6PgDNAgAPAAkKkhw6PgDNAgABNQAECgkJIwAXAI8aAA==.',
St='Stargasm:BAABNQAECn89AAIDAAkKGRbURQBSAgADAAkKGRbURQBSAgAAAA==.',
Sw='Swiftmend:BAAANQAECgUIDAABNQAECgkJHgAPADgaAA==.Swinghardz:BAAANQAECgQIBgAAAA==.',
Ta='Taggen:BAAANQAECgEIAQAAAA==.Tardis:BAAANQADCgEIAQAAAA==.',
Te='Terainer:BAAANQADCggIDQAAAA==.',
Th='Theia:BAAANQADCgIIAgAAAA==.Throbbinknob:BAAANQAECgEIAQAAAA==.',
Ti='Timewing:BAABNQAECn8eAAMcAAkK3A+YGgAZAgAcAAkK3A+YGgAZAgAdAAEKPg4iJQAuAAAAAA==.Tinkerspell:BAAANQADCgQIBAAAAA==.',
To='Toefunk:BAAANQADCgQIBAAAAA==.',
Tr='Transformer:BAAANQAECggICwAAAA==.Triblequest:BAAANQADCgYIBgAAAA==.Trotndot:BAAANQADCgIJAgAAAA==.',
Tw='Twiltock:BAAANQAECgEJAQAAAA==.Twizztyd:BAAANQABCgQIBAAAAA==.',
Va='Valerion:BAAANQADCgYIBgAAAA==.Valessa:BAAANQAECgYIEQAAAA==.',
Ve='Vektendra:BAAANQADCgYIBgAAAA==.',
Vi='Vilbald:BAAANQADCgIIAwAAAA==.Vita:BAAANQAECgIIBQAAAA==.',
['Vø']='Vødu:BAAANQADCggICAAAAA==.',
Wi='Windflower:BAAANQAFFAEIAQAAAA==.',
Wo='Worldbreakèr:BAAANQAECggIBQAAAA==.',
['Wÿ']='Wÿcked:BAAANQAECgQIBgAAAA==.',
Xi='Xiaobao:BAAANQAECgUIDAAAAA==.Xiaoduoduo:BAABNQAECn8pAAQFAAkK0SFTDABkAwAFAAkK0SFTDABkAwANAAcKjCLkRQDAAgAMAAMK2CG5OAAiAQAAAA==.Xiaomak:BAABNQAECn8jAAMBAAkKPiHxLwDbAgABAAkKPiHxLwDbAgAbAAUKcxDeRwAYAQABNQAECgkJKQAFANEhAA==.',
Xx='Xxschafer:BAAANQADCgUIBQAAAA==.',
Za='Zab:BAAANQAECgUIBQABNQAECggIIwANAGwZAA==.Zabexer:BAAANQADCgIIAgAAAA==.',
Ze='Zehelith:BAAANQADCgQIBAABNQAECgkJJwAFALgkAA==.Zeroskills:BAABNQAECn8tAAIUAAkKXgs1GwD6AQAUAAkKXgs1GwD6AQAAAA==.',
Zu='Zulinar:BAAANQAECgYIEwAAAA==.',
Zy='Zyierah:BAAANQADCgQIBAAAAA==.',
['Zé']='Zépar:BAAANQAECgQIBAABNQAECgQIBgAGAAAAAA==.',
['Às']='Àsmodeus:BAAANQAECgcIEQAAAA==.',
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
