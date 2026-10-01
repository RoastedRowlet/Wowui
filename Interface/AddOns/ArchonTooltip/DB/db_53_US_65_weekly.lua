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

local lookup = {'DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Mage-Arcane','Paladin-Holy','Druid-Guardian','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','Druid-Feral','Evoker-Preservation','Mage-Fire','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','Druid-Restoration',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaphrodite:BAAANQADCgMIAwAAAA==.',
Ab='Abyssalblink:BAACNQAFFIEPAAMBAAYKJRNjAwD2AQABAAYKORJjAwD2AQACAAMK3wsBCgDPAAA1AAQKgR0AAwIACQqaHTcUAJgCAAIACQpgHDcUAJgCAAEAAgr0HQFaAKwAAAAA.',
Ah='Ahruud:BAAANQADCgMIAwAAAA==.',
Ak='Akeno:BAAANQADCgIIAgABNQAECgYICQADAAAAAA==.',
Al='Albie:BAABNQAECoEcAAIEAAkKbw+1eABVAgAEAAkKbw+1eABVAgAAAA==.Albtraum:BAAANQADCgMIAwAAAA==.Aleight:BAAANQAECgUIDAAAAA==.Alice:BAAANQADCgIIAgAAAA==.Alius:BAAANQADCggICAAAAA==.',
Am='Ambellina:BAABNQAECoEZAAIFAAcKoxilSAACAgAFAAcKoxilSAACAgAAAA==.',
Ba='Bambiietta:BAAANQAECgQIBgAAAA==.',
Bl='Blastoiz:BAAANQADCgYIBgAAAA==.',
Bu='Bulvar:BAAANQADCgIIAgAAAA==.',
Ca='Cardrin:BAABNQAECoEcAAIGAAgK6xfFDAAhAgAGAAgK6xfFDAAhAgAAAA==.',
Ce='Cerbulum:BAAANQADCgMIAwAAAA==.',
Ch='Chat:BAAANQADCgMIAwAAAA==.Choplo:BAACNQAFFIEYAAIHAAcKNho+AQB6AgAHAAcKNho+AQB6AgA1AAQKgRkAAgcACQruHxwRAJcCAAcACQruHxwRAJcCAAAA.Chudmuffin:BAAANQAECgQICQAAAA==.',
Cl='Clarence:BAAANQADCgIIAgAAAA==.',
Co='Cobalt:BAEANQAECgMJAwABNQAECgkJGgAIAD4dAA==.',
Cr='Creativename:BAAANQABCgUIBQAAAA==.Crona:BAAANQADCgIIAgAAAA==.',
Da='Daemon:BAABNQAECoEaAAQJAAkK7B+SBgCRAgAJAAkKkheSBgCRAgAIAAUKcyHTgACEAQAKAAEKVx8wIQBHAAAAAA==.Dalast:BAAANQAECgEIAQAAAA==.',
De='Debockulus:BAABNQAECoEfAAMIAAgK8g80XQDxAQAIAAgK8g80XQDxAQAJAAUKeAVnNwDPAAAAAA==.Decentychi:BAAANQADCggICAABNQAECgkJIQABAJ4lAA==.Dedia:BAAANQAECgEIAQAAAA==.Derangedxo:BAACNQAFFIESAAMIAAcKsR+aAgAXAgAIAAYK5CCaAgAXAgAJAAEKhBiyEgBbAAA1AAQKgRwAAwkACQqZJaIHAHcCAAkABwrvIKIHAHcCAAgABQqTJTlpAMsBAAAA.',
Do='Doggie:BAAANQADCgMIAwAAAA==.',
Dr='Drunkenhoe:BAAANQAECgUIBwAAAA==.',
Ed='Edger:BAAANQADCgMIAwAAAA==.',
El='Elcomer:BAAANQADCgIIAgAAAA==.',
En='Enana:BAABNQAECoEWAAILAAgKMQmGagB1AQALAAgKMQmGagB1AQAAAA==.Enkor:BAAANQAECgIIAgAAAA==.',
Er='Era:BAAANQAECgYIEwAAAA==.',
Ev='Everblack:BAABNQAECoEdAAQJAAgKvRsYGACeAQAJAAUKUxsYGACeAQAIAAUKfhXqlABNAQAKAAMKDh5iEgDUAAAAAA==.Evilcretin:BAABNQAECoEZAAIEAAcK1x/GZQCDAgAEAAcK1x/GZQCDAgAAAA==.',
Fa='Faraah:BAABNQAECoEtAAIMAAkKeCNQAQCkAwAMAAkKeCNQAQCkAwAAAA==.',
Ga='Ganondorf:BAAANQAECgYIDgAAAA==.Gatecrashr:BAAANQADCggIDQAAAA==.',
Gi='Gimlï:BAAANQADCgYICgAAAA==.',
Gn='Gnosis:BAAANQADCggIFgAAAA==.',
Go='Goch:BAAANQAECgYIEwAAAA==.Goldenwind:BAAANQADCgQIBAAAAA==.Goodluck:BAAANQADCgMIAwABNQAFFAQICAANAAkUAA==.',
Gr='Grimdark:BAABNQAECoEdAAILAAcKJxbdUADQAQALAAcKJxbdUADQAQAAAA==.Grunge:BAAANQAECgIIAgAAAA==.',
Ha='Haven:BAAANQAECgEIAQAAAA==.',
He='Heathermarie:BAABNQAECoEcAAIOAAgKEiOLAAAxAwAOAAgKEiOLAAAxAwAAAA==.',
Ho='Holdmyhammer:BAAANQADCgMIAwAAAA==.Holypride:BAAANQADCgUIBQAAAA==.Hotbut:BAAANQAECgUIDQAAAA==.',
['Hø']='Hørus:BAAANQADCgcIBwAAAA==.',
Ia='Iaptopz:BAAANQADCgcIDQAAAA==.',
Ir='Irishbaby:BAAANQAECgEJAgAAAA==.',
Iz='Iza:BAAANQAECgYIEQAAAA==.',
Ja='Jake:BAEANQAECgMIBgABNQAFFAcIGAAEAJAZAA==.Jay:BAAANQAECgEIAQAAAA==.',
Ju='Juri:BAAANQAFFAEIAQAAAA==.',
Ka='Kallivor:BAAANQAECgUIBQAAAA==.Kanbu:BAAANQADCgEIAQAAAA==.Kardd:BAAANQAECgQIBwAAAA==.',
Ke='Keltic:BAAANQAECggICAAAAA==.',
Kh='Khantyer:BAAANQADCgYIAwAAAA==.',
Ki='Kiing:BAAANQADCgUIBQAAAA==.',
Kr='Krowlhy:BAAANQAECgIIAgAAAA==.',
La='Laezel:BAABNQAECoEcAAIPAAgKgRq2UwBNAgAPAAgKgRq2UwBNAgAAAA==.Lamppost:BAAANQAFFAEIAQAAAA==.Landliebe:BAAANQADCggIHwAAAA==.Lannister:BAAANQADCgUIBQABNQAECggIIAANAN0TAA==.',
Le='Lereios:BAAANQAECgYIDgAAAA==.Lessons:BAAANQADCgEIAQAAAA==.',
Li='Lightsmith:BAAANQAECgQIBQAAAA==.Lilpump:BAAANQAECgUIBAABNQAECggICwADAAAAAA==.Lith:BAABNQAECoEgAAMBAAkKYSMFBgB3AwABAAkKYSMFBgB3AwACAAEKGAPnXQAnAAAAAA==.Liyun:BAAANQAECgIIAgAAAA==.',
Ma='Mahyor:BAAANQAFFAEIAQAAAA==.Maybringer:BAAANQADCgQIBAAAAA==.Mazzh:BAABNQAECoEZAAMQAAkKWR7PGgBHAgAQAAkKDxrPGgBHAgARAAYKChHiswAwAQABNQAFFAkJKgAEAPIiAA==.',
Na='Naric:BAAANQAECgQIBAABNQAECgYIDgADAAAAAA==.Narium:BAAANQADCggIHQAAAA==.',
No='Now:BAABNQAECoEaAAMSAAgKWxbRQAAnAgASAAgKWxbRQAAnAgALAAEKIwR9/QAgAAAAAA==.',
Nu='Nukenin:BAABNQAECoEjAAICAAkKTiUHAgC6AwACAAkKTiUHAgC6AwAAAA==.',
Ny='Nyrasha:BAABNQAECoEmAAIRAAkKrSGaCwBfAwARAAkKrSGaCwBfAwAAAA==.',
Pa='Paredes:BAAANQAECgMIAwAAAA==.',
Pe='Peonu:BAAANQAECgUIDQAAAA==.',
Po='Police:BAABNQAECoEdAAILAAgKDSJLFAD9AgALAAgKDSJLFAD9AgAAAA==.',
Pr='Pride:BAAANQAECgYIDgAAAA==.Proteus:BAAANQAECgMIAgAAAA==.Prounion:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Pu='Puff:BAAANQAECgYICwAAAA==.Puntme:BAAANQADCgQJBAAAAA==.',
Ra='Rana:BAAANQAECgMIBAAAAA==.Ratko:BAAANQADCggIDwAAAA==.',
Re='Rekk:BAAANQAECggICAAAAA==.Reventön:BAAANQADCgcIBgAAAA==.Rey:BAAANQAECgUIDgAAAA==.',
Ro='Rockandstone:BAAANQAECgQICAAAAA==.',
Ru='Rubyredyoshi:BAAANQADCgMJAwAAAA==.Runtzsr:BAAANQABCgQJBQAAAA==.',
['Rá']='Ráîstlin:BAAANQAECgcIEQAAAA==.',
Se='Selro:BAAANQAECgMIAwAAAA==.',
Sh='Shadøw:BAAANQAECgQIBQAAAA==.Shinoa:BAAANQAECgEIAQAAAA==.Shockzzer:BAAANQADCgMIAwAAAA==.',
So='Soulszaura:BAAANQAECgQIBAAAAA==.',
St='Starchucker:BAACNQAFFIEFAAICAAIK5xgmCwCjAAACAAIK5xgmCwCjAAA1AAQKgSoAAgIACQr3HMgMAPgCAAIACQr3HMgMAPgCAAAA.',
Sw='Swade:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.Sweetnwicked:BAAANQAECgQJCAAAAA==.',
Sy='Synarri:BAAANQAECggIEwABNQAFFAcIGAAFAF0YAA==.Syneria:BAACNQAFFIEYAAMFAAcKXRgKAQCNAgAFAAcKXRgKAQCNAgATAAEKkxXhIQBHAAA1AAQKgX4AAwUACQqxJTQAAP8DAAUACQqxJTQAAP8DABMACQprI88MAIIDAAAA.Syneriah:BAAANQAECgEIAQABNQAFFAcIGAAFAF0YAA==.Synn:BAAANQADCggICAABNQAFFAcIGAAFAF0YAA==.Synnamon:BAABNQAECoEdAAMTAAkKOSEBIQAPAwATAAgKHSIBIQAPAwAFAAUKvQl2iwAmAQABNQAFFAcIGAAFAF0YAA==.Synpai:BAACNQAFFIEFAAMFAAIK3BW2FACgAAAFAAIK3BW2FACgAAATAAEKUgsNJABCAAA1AAQKgTIAAxMACQpwH3gYADwDABMACQpwH3gYADwDAAUABgoKGnNPAOgBAAE1AAUUBwgYAAUAXRgA.',
Ta='Taciitus:BAABNQAECoEpAAIHAAkKyBwzDQDUAgAHAAkKyBwzDQDUAgAAAA==.Tailzz:BAAANQAECgUICgAAAA==.',
Th='Thebaptiser:BAAANQADCgUIBQAAAA==.',
Ti='Tiazy:BAAANQADCgYICAAAAA==.',
To='Toomato:BAAANQAECgQIBAAAAA==.Totemterror:BAEBNQAECoEWAAILAAgKWSX7CQBRAwALAAgKWSX7CQBRAwAAAA==.Tough:BAAANQADCgQIBAAAAA==.',
Ty='Tydraduel:BAABNQAECoEcAAIIAAgKFBwuMwCBAgAIAAgKFBwuMwCBAgAAAA==.',
Tz='Tzuruchanise:BAAANQADCgMIBAAAAA==.',
Va='Vala:BAAANQAECgEIAQABNQAECggIIAANAN0TAA==.Valy:BAAANQAECgEJBAAAAA==.Vannathyfall:BAAANQADCgQIBwAAAA==.Vany:BAAANQAECgEIAQAAAA==.',
Vo='Vora:BAAANQAECgIIAgAAAA==.',
Vw='Vw:BAAANQAECgIIAgAAAA==.',
Wh='Whalethen:BAEANQAECgYIBgABNQAECggIFgALAFklAA==.',
Wi='Wikkid:BAAANQADCgUJBwAAAA==.Wikkidsin:BAAANQADCgUICAABNQADCgUJBwADAAAAAA==.',
['Wù']='Wùlph:BAAANQADCggICgAAAA==.',
Xx='Xxz:BAAANQADCgUIBwAAAA==.',
Yi='Yiesus:BAAANQAECggIDQABNQAFFAYIDwACANMkAA==.',
Yo='Yomato:BAABNQAECoEgAAIUAAkK1hwLCAAWAwAUAAkK1hwLCAAWAwAAAA==.',
Yu='Yuanti:BAAANQADCgIIAgAAAA==.',
Za='Zabble:BAAANQABCgMIAwAAAA==.',
Ze='Zenocline:BAABNQAECoEYAAIHAAgK0hSEGgAWAgAHAAgK0hSEGgAWAgAAAA==.',
Zi='Zi:BAAANQAECggIBwAAAA==.',
['Ån']='Åntisocial:BAAANQAECgEIAQAAAA==.',
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
