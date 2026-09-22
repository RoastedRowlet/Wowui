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

local lookup = {'Warrior-Arms','Unknown-Unknown','Paladin-Retribution','Mage-Arcane','Hunter-BeastMastery','Monk-Brewmaster','Rogue-Subtlety','Priest-Holy','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Paladin-Holy',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Aberdine:BAAANQAECgIIAgAAAA==.',
Ac='Acadya:BAAANQAECgcJDQAAAA==.Accar:BAAANQAECgUJCQAAAA==.Achu:BAAANQAECgEIAQABNQAECgcIFgABAOsiAA==.Acylies:BAAANQADCgUJCAAAAA==.',
Ae='Aellori:BAAANQADCgcJBwAAAA==.',
Ag='Agrias:BAAANQAECgcIEwAAAA==.',
Al='Algodón:BAAANQADCgQIBgAAAA==.Alindriel:BAAANQADCgMJAwAAAA==.Althea:BAAANQAECgQJCgAAAA==.',
Am='Ambry:BAAANQABCgIIAgABNQADCgcIBwACAAAAAA==.Ambryosia:BAAANQADCgcIBwAAAA==.',
Ar='Arcanyounot:BAAANQADCgcIGQABNQAECgIJBAACAAAAAA==.',
Av='Avvenge:BAAANQADCgcIBwAAAA==.',
Ba='Barricade:BAAANQAECgQJCgAAAA==.',
Bc='Bcshaman:BAAANQADCgYJBgABNQAECgUICgACAAAAAA==.Bcwarrior:BAAANQAECgUICgAAAA==.',
Be='Bertabeef:BAAANQADCgYIBgAAAA==.',
Bi='Biróg:BAAANQAECgQIBgAAAA==.',
Bl='Blizzaga:BAAANQAECgUIEAAAAA==.Blutrünstig:BAAANQADCgMJBAABNQAECgEIAQACAAAAAA==.',
Bo='Bobbyperu:BAAANQADCgUJBQAAAA==.Bootowsky:BAAANQADCggIDAAAAA==.',
Br='Brocephus:BAAANQAECgEJAQAAAA==.Bruno:BAAANQADCgUIBwAAAA==.',
Bu='Burrgold:BAAANQAECgIJAgAAAA==.',
Ca='Callesa:BAAANQADCgUIBQAAAA==.Carpathiá:BAAANQAECgEJAgAAAA==.',
Ch='Chaoticelf:BAAANQADCgQIBAAAAA==.Chubzilla:BAAANQAECgQJBAAAAA==.',
Cl='Clockie:BAAANQAECgYICAABNQAECgcIFgABAOsiAA==.Clõüd:BAABNQAECoEqAAIDAAkKSiEvEQBMAwADAAkKSiEvEQBMAwAAAA==.',
Co='Combusting:BAAANQAECgIIAgAAAA==.',
Cr='Crimsonrain:BAAANQAECggICAAAAA==.',
Cu='Cuitlahuac:BAAANQADCgcIBwAAAA==.',
Cy='Cynthigosa:BAAANQAECgUJCAAAAA==.',
Da='Daarion:BAAANQABCgcIEQAAAA==.Darrkmann:BAAANQAECgUJBAAAAA==.',
De='Demonicspeak:BAAANQAECgQIBAAAAA==.Densepancake:BAAANQAECgQIBAAAAA==.',
Di='Dianeneedrol:BAAANQAECgMIBQAAAA==.Dietpally:BAAANQABCgEIAQAAAA==.Dinkster:BAAANQADCggICAAAAA==.',
Dk='Dkcloud:BAAANQADCgcIBwABNQAECgkJKgADAEohAA==.',
Ec='Echidna:BAAANQADCgYIBgABNQAECgMIBAACAAAAAA==.Eclesiastes:BAAANQADCgEIAQAAAA==.',
El='Elcapnkikazz:BAAANQAECgUIEAAAAA==.Ellex:BAAANQADCgQIBgABNQADCgUIBgACAAAAAA==.Ellexstrasza:BAAANQADCgUIBgAAAA==.',
En='Enhancdepeen:BAAANQADCggICAAAAA==.',
Er='Erìs:BAAANQAECgIIAwAAAA==.',
Es='Estellandra:BAAANQABCggICAAAAA==.',
Ev='Evercy:BAAANQADCgYICgAAAA==.Eviseria:BAAANQABCgQIBgAAAA==.',
Fa='Faithykinz:BAAANQAECgEJAQAAAA==.',
Fi='Fininho:BAAANQAECgYIAQAAAA==.',
Fr='Frostlowe:BAAANQADCgMIBAAAAA==.',
['Fú']='Fúsion:BAEANQAECggJEgAAAA==.',
Go='Gonamanar:BAAANQAECgUJBgAAAA==.',
Gr='Grandreaper:BAAANQADCgUIBQAAAA==.Grimfall:BAAANQADCggICAAAAA==.Gripology:BAAANQAECgQJDAABNQAECgkJHAABAO8bAA==.',
Ha='Happyhour:BAAANQAECgQICgAAAA==.',
He='Hexidecimal:BAAANQAECgYJDwAAAA==.',
Hi='Highlowe:BAAANQAECgIIAgAAAA==.',
Ho='Hoiylight:BAAANQAECgIIAgAAAA==.Holybeavis:BAAANQAECgUIBQAAAA==.Holydh:BAAANQAECgQJBQAAAA==.Holyhunt:BAAANQAECgcIBwABNQAECgkJJwAEAAYdAA==.Holylock:BAAANQAECgIIBAAAAA==.Holymage:BAABNQAECoEnAAIEAAkKBh3UIgAsAwAEAAkKBh3UIgAsAwAAAA==.Holyseeker:BAAANQAECgcJDgABNQAECgkJJwAEAAYdAA==.Holyshaman:BAAANQAECgIIAwAAAA==.Holywarrior:BAAANQAECgcICgAAAA==.Holyymonk:BAAANQAECgIIBAAAAA==.Holyyseeker:BAAANQAECgYJCAAAAA==.Hottamalie:BAAANQAECgQICgAAAA==.',
Ia='Iampally:BAAANQAECgcIDgAAAA==.',
Ic='Iceyoyomak:BAAANQAECgMIBAABNQAECggIGAAFACwhAA==.Icyloadz:BAAANQAECgUJBQAAAA==.',
Im='Imdemonic:BAAANQAECgQICAAAAA==.Imogen:BAAANQADCgYIBgAAAA==.',
Ja='Jazashi:BAAANQADCggIDgAAAQ==.',
Ka='Kailler:BAAANQAECgQIDQAAAA==.',
Ke='Keg:BAACNQAFFIEKAAIGAAQKyiXpAAC/AQAGAAQKyiXpAAC/AQA1AAQKgR4AAgYACQquJoUBAIgDAAYACQquJoUBAIgDAAAA.',
Ki='Kittyhawk:BAAANQAECgcICwAAAA==.',
Kl='Klassic:BAAANQADCgYICQAAAA==.Klixx:BAAANQADCgYIDgAAAA==.',
Ks='Kstab:BAABNQAECoEXAAIHAAgKdBD+GQDMAQAHAAgKdBD+GQDMAQAAAA==.',
Ku='Kuromeow:BAABNQAECoEYAAIEAAgKKRbTXgByAgAEAAgKKRbTXgByAgAAAA==.',
La='Larake:BAAANQAECgUICAAAAA==.',
Li='Lightkeeper:BAAANQAECgMJAwAAAA==.Lilithhunter:BAAANQADCgIIAgAAAA==.Lilkneebiter:BAAANQADCgUJBQAAAA==.Litdealer:BAAANQAECgQICAABNQAECgkJHAABAO8bAA==.',
Lo='Lockinaround:BAAANQAECgIJBAAAAA==.',
Ma='Manaplague:BAAANQAECgEIAQAAAA==.Marleau:BAAANQAECgQIBgAAAA==.Martymcfly:BAAANQAECgUIBgAAAA==.',
Me='Menion:BAAANQAECgYJDwAAAA==.Meruk:BAAANQAECgYJBQAAAA==.Mesoholy:BAAANQAECgQJCAAAAA==.',
Mk='Mk:BAEANQADCgcJDgABNQAECgYIEgACAAAAAA==.',
Mo='Moreldor:BAAANQADCgQJCAAAAA==.',
Ni='Nillfurio:BAAANQAECgYIBgAAAA==.Ninjitsû:BAAANQAECgUIDgAAAA==.',
No='Noideea:BAABNQAECoEWAAIBAAgKMx+2JgDWAgABAAgKMx+2JgDWAgAAAA==.',
Ny='Nyke:BAAANQAECgQIBgAAAA==.',
Od='Odinson:BAAANQAECgQJBQAAAA==.',
Om='Omie:BAAANQAECgUJBwAAAA==.',
Pa='Paulos:BAAANQAECgMIBAAAAA==.',
Ra='Razzeman:BAAANQABCgYJBgAAAA==.',
Re='Reverend:BAAANQADCgQIBAAAAA==.',
Ru='Ruck:BAAANQAECgEJAQABNQAECgcIDAACAAAAAA==.Rucker:BAAANQAECgcIDAAAAA==.Ruckkin:BAAANQABCgQJBAABNQAECgcIDAACAAAAAA==.Rucksy:BAAANQAECgQIBgABNQAECgcIDAACAAAAAA==.',
Ry='Ryan:BAAANQAECgUIDwAAAA==.',
Se='Senchá:BAAANQAECgcJCQABNQAECgcIFQAGAEQgAA==.Seraphae:BAAANQAECgUJCQAAAA==.Sereb:BAAANQADCgUIBQAAAA==.',
Sh='Shadeorheals:BAAANQABCgQICgAAAA==.Shalana:BAAANQADCgQIBAAAAA==.Sheong:BAABNQAECoEVAAIGAAcKRCB8BwBdAgAGAAcKRCB8BwBdAgAAAA==.Shèrlock:BAAANQAECgQIBgAAAA==.',
Si='Silverfox:BAAANQAECgYJCQABNQAECggIGAAFACwhAA==.',
Sk='Skera:BAAANQAECgcIDgAAAA==.Skippydippy:BAAANQAECgUIBQAAAA==.Skye:BAAANQAECgMJAwAAAA==.',
Sl='Sleepysniper:BAAANQAECggIDgABNQAECggIFgABADMfAA==.',
Sp='Spelldeala:BAAANQAECgQJBQABNQAECgkJHAABAO8bAA==.',
Ss='Ssgtusmc:BAAANQAECgQIDAAAAA==.Ssjgodxx:BAAANQAECgUICAABNQAECgUIDgACAAAAAA==.',
St='Stargasm:BAABNQAECoEqAAIIAAgKDRZHNwARAgAIAAgKDRZHNwARAgAAAA==.',
Sw='Swiftmend:BAAANQAECgQICAABNQAECgkJHAABAO8bAA==.Swinghardz:BAAANQAECgQJBgAAAA==.',
Ta='Taggen:BAAANQAECgEIAQAAAA==.Tardis:BAAANQADCgEIAQAAAA==.',
Te='Terainer:BAAANQADCggJDAAAAA==.',
Th='Theia:BAAANQADCgEIAQAAAA==.Throbbinknob:BAAANQAECgEIAQAAAA==.',
Ti='Timewing:BAABNQAECoEbAAMJAAkKkA6xEwAXAgAJAAkKkA6xEwAXAgAKAAEKPg51GAAyAAAAAA==.Tinkerspell:BAAANQADCgQIBAAAAA==.',
To='Toefunk:BAAANQADCgQIBAAAAA==.',
Tr='Trotndot:BAAANQADCgIJAgAAAA==.',
Tw='Twiltock:BAAANQAECgEJAQAAAA==.Twizztyd:BAAANQABCgQIBAAAAA==.',
Va='Valerion:BAAANQADCgYIBgAAAA==.Valessa:BAAANQAECgMIBQAAAA==.',
Ve='Vektendra:BAAANQADCgYJBgAAAA==.',
Vi='Vilbald:BAAANQADCgIIAwAAAA==.Vita:BAAANQAECgIJBAAAAA==.',
['Vø']='Vødu:BAAANQADCggICAAAAA==.',
Wi='Windflower:BAAANQAECgMIAwAAAA==.',
Xi='Xiaobao:BAAANQAECgMJBQAAAA==.Xiaoduoduo:BAAANQAECggJEgABNQAECggIGAAFACwhAA==.Xiaomak:BAABNQAECoEYAAMFAAgKLCFIGADoAgAFAAgKLCFIGADoAgALAAQK4RFqMwATAQAAAA==.',
Xx='Xxschafer:BAAANQADCgUIBQAAAA==.',
Za='Zabexer:BAAANQADCgIIAgAAAA==.',
Ze='Zehelith:BAAANQADCgQIBAABNQAECgkJIAAMALgkAA==.Zeroskills:BAAANQAECgYJEwAAAA==.',
Zu='Zulinar:BAAANQAECgQJCAAAAA==.',
Zy='Zyierah:BAAANQADCgQIBAAAAA==.',
['Zé']='Zépar:BAAANQADCgQIBAAAAA==.',
['Às']='Àsmodeus:BAAANQAECgUJCQAAAA==.',
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
