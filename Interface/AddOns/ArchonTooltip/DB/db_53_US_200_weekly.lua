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

local lookup = {'Unknown-Unknown','Druid-Restoration','Warrior-Arms','Mage-Arcane','DeathKnight-Unholy','Warlock-Affliction','Priest-Holy','Monk-Brewmaster','Druid-Balance','Hunter-BeastMastery','Warlock-Demonology','DemonHunter-Vengeance','Shaman-Elemental','DemonHunter-Havoc','Paladin-Retribution','DeathKnight-Blood','Priest-Shadow','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Rogue-Outlaw','Warrior-Protection','Rogue-Assassination','Shaman-Restoration','Warrior-Fury',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=53,date='2026-10-06',data={Ai='Aitnd:BAAANQADCggIEAAAAA==.Aitns:BAAANQADCgQIBAAAAA==.',
Al='Alaszun:BAAANQADCggICQAAAA==.Alorothius:BAAANQAECgYIDgABNQAECgcIEAABAAAAAA==.Alpacalypse:BAAANQADCggICAAAAA==.Altha:BAABNQAECoEoAAICAAkKUgySIwDcAQACAAkKUgySIwDcAQAAAA==.',
Am='Amilde:BAAANQADCggICQABNQAECgkJIQADAIsbAA==.',
An='Anarisa:BAABNQAECoElAAIEAAgKPxWYlAA6AgAEAAgKPxWYlAA6AgAAAA==.',
Ap='Appocolypto:BAAANQAECgUIBQAAAA==.',
Ar='Areese:BAAANQADCgUIAgAAAA==.Arës:BAAANQAECgEIAQAAAA==.',
Av='Averse:BAABNQAECoEsAAIFAAkK7iOWCgBVAwAFAAkK7iOWCgBVAwAAAA==.',
Ba='Balnor:BAAANQAECgYIEwAAAA==.',
Bi='Bigbeef:BAAANQADCgEIAQAAAA==.',
Bo='Borgus:BAAANQAECgUJEgAAAA==.',
Br='Brimstone:BAAANQADCggIEAAAAA==.Brokemav:BAABNQAECoEwAAIGAAkKmB87AQBAAwAGAAkKmB87AQBAAwAAAA==.Brooklin:BAABNQAECoEuAAIEAAkKnBRtfQBrAgAEAAkKnBRtfQBrAgAAAA==.',
Bu='Busky:BAAANQAECgYIEwAAAA==.',
Ca='Cao:BAAANQAECgcIEQAAAA==.Cassiopea:BAABNQAECoEgAAIHAAgKwBzYLgCNAgAHAAgKwBzYLgCNAgAAAA==.',
Ce='Cellcept:BAAANQADCgYIEAAAAA==.',
Ch='Chinchillada:BAAANQAECgQIBgAAAA==.Chows:BAAANQADCgYIBgABNQAECgkJIQADAIsbAA==.Chre:BAAANQADCggICQAAAA==.',
Cl='Clafoutis:BAAANQAECgUIBQAAAA==.Clanker:BAACNQAFFIEPAAIIAAUKmxpvAgCbAQAIAAUKmxpvAgCbAQA1AAQKgSMAAggACQooI94CAGADAAgACQooI94CAGADAAAA.',
['Cà']='Càss:BAAANQABCgEIAQABNQAECggIIAAHAMAcAA==.',
Da='Dabajabaza:BAAANQAECgcIEAAAAA==.Dabergerak:BAACNQAFFIEFAAIDAAIKjRvuIwCfAAADAAIKjRvuIwCfAAA1AAQKgRcAAgMACQqSG5FGAJ0CAAMACQqSG5FGAJ0CAAAA.Dakrus:BAAANQAECgUIBQAAAA==.',
De='Deathntaxes:BAAANQAECggICAAAAA==.Dejanira:BAABNQAECoEZAAMCAAgKEA35KQCcAQACAAgKEA35KQCcAQAJAAEK6Ac7pgApAAAAAA==.Deyedrel:BAAANQAECgYIEwAAAA==.',
Di='Diddily:BAAANQAECgYICwAAAA==.',
Dr='Dridarok:BAAANQAECgYIDQAAAA==.Drixfu:BAAANQADCgcIBwAAAA==.',
El='Elise:BAAANQADCgUIBQABNQAECggIJQAKAEscAA==.Elstrid:BAABNQAECoEeAAILAAYKCRV3iwCbAQALAAYKCRV3iwCbAQAAAA==.',
Er='Eremisa:BAAANQADCgYIBgABNQAECggIJQAEAD8VAA==.',
Ev='Eve:BAACNQAFFIEPAAIMAAUKLQ6iAQA6AQAMAAUKLQ6iAQA6AQA1AAQKgSMAAgwACQotHF8FALICAAwACQotHF8FALICAAAA.Evochre:BAAANQADCgYICAAAAA==.',
Fa='Fantasy:BAABNQAECoEYAAINAAgKLSZQCwCBAwANAAgKLSZQCwCBAwAAAA==.',
Fe='Felbourn:BAABNQAECoEZAAIOAAgKkhyoIgBfAgAOAAgKkhyoIgBfAgAAAA==.Fendraim:BAAANQADCgMIBgAAAA==.',
Fi='Figurefour:BAAANQAECgIIAgAAAA==.',
Fl='Flaccidmass:BAAANQAECgIIAwAAAA==.',
Fo='Foedris:BAAANQAECgIIAgAAAA==.',
Fr='Frailboosy:BAABNQAECoEkAAIPAAkKfyD9QQCpAgAPAAkKfyD9QQCpAgAAAA==.',
Ga='Gaara:BAAANQAECggIDQAAAA==.',
Ge='Gemini:BAAANQAECgYIDQAAAA==.',
Gl='Glitz:BAAANQAECgQIBgABNQAFFAUIDwAMAC0OAA==.',
Gr='Gravedigger:BAABNQAECoEsAAIQAAkKOh+rEQALAwAQAAkKOh+rEQALAwAAAA==.',
['Gü']='Güts:BAABNQAECoEiAAIDAAkKtRPJYgBHAgADAAkKtRPJYgBHAgAAAA==.',
Ho='Holywagyu:BAAANQADCgcIBwAAAA==.Howlimer:BAAANQADCgEIAQAAAA==.',
Hu='Huf:BAAANQADCgYIDAABNQAFFAUIDwARAMUVAA==.',
Ir='Ironnmonk:BAAANQADCgYIBQABNQAECgUIBQABAAAAAA==.',
Ja='Java:BAAANQADCgQIBgABNQAECgYIEwABAAAAAA==.Jawshoeuh:BAAANQAECgEIAQAAAA==.',
Ju='Jujumon:BAAANQADCgYIBgAAAA==.Jujuzor:BAAANQAECgQIBQAAAA==.Jujuzul:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Justimp:BAABNQAECoEeAAILAAkKzBWQPgB7AgALAAkKzBWQPgB7AgAAAA==.',
Ka='Karlek:BAABNQAECoEhAAMPAAkKNxHeiQDfAQAPAAgKKxLeiQDfAQASAAEKnAkPZQAuAAAAAA==.Kassamella:BAAANQADCggJCAABNQAECgQIBgABAAAAAA==.Kassanndra:BAEANQAECggJCAABNQAECggIIQAPAOgZAA==.Kazeshiní:BAAANQADCgQIBAAAAA==.',
La='Lalana:BAAANQAECgEIAQAAAA==.Lan:BAAANQAECgQIBAAAAA==.',
Li='Lilshorty:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Lo='Lofwyr:BAABNQAECoEdAAMTAAkK5AxGKABOAQATAAcKjAhGKABOAQAUAAYKAgrkDgAnAQAAAA==.',
Lu='Lumaie:BAAANQAECgYIEwAAAA==.Lumistress:BAEBNQAECoEhAAIPAAgK6BkjagAxAgAPAAgK6BkjagAxAgAAAA==.',
Ly='Lynni:BAAANQADCgUIBQAAAA==.',
Ma='Malcharion:BAAANQAECgQIBAAAAA==.Mamarue:BAAANQADCgYIBgAAAA==.',
Mc='Mcshâms:BAABNQAECoEXAAINAAgKUR/qKAC7AgANAAgKUR/qKAC7AgAAAA==.',
Mu='Munir:BAAANQADCggIIQAAAA==.',
Na='Naeltian:BAABNQAECoEoAAIVAAkK/RynAgASAwAVAAkK/RynAgASAwAAAA==.',
Ne='Necromachine:BAABNQAECoEoAAIFAAkKmCEMCwBQAwAFAAkKmCEMCwBQAwAAAA==.Nevermore:BAABNQAECoEbAAIOAAgKEhu6IQBmAgAOAAgKEhu6IQBmAgAAAA==.',
No='Noctislucis:BAAANQABCgIIAgAAAA==.Noobdk:BAABNQAFFIEJAAIQAAUKoBbDCwBsAQAQAAUKoBbDCwBsAQAAAA==.Noobmonkey:BAAANQADCgYIBgABNQAFFAUICQAQAKAWAA==.Noobwarr:BAABNQAECoEjAAMWAAkKviQZAgCKAwAWAAkKviQZAgCKAwADAAcKYxdcggDxAQABNQAFFAUICQAQAKAWAA==.Novax:BAAANQAECgUIBwAAAA==.',
Ny='Nyquil:BAEANQAECggICAABNQAECggIIQAPAOgZAA==.',
Ol='Oldreligion:BAAANQADCggICAAAAA==.',
Pe='Perugius:BAAANQADCgYICgABNQAECgYIHgALAAkVAA==.',
Ph='Phrenulhum:BAAANQADCgcIBwAAAA==.',
Pr='Predmost:BAAANQABCgQIBAAAAA==.Prettypoison:BAAANQAECgUIDwAAAA==.',
Pu='Pussehfart:BAAANQADCggJDAAAAA==.Putz:BAABNQAECoEvAAIMAAkKMhsaBQC5AgAMAAkKMhsaBQC5AgAAAA==.Putzadin:BAAANQAECgEIAQAAAA==.',
Pw='Pwincess:BAAANQABCgIIAgAAAA==.',
Ra='Rainbow:BAAANQAECgcIEAABNQAECggIGAANAC0mAA==.',
Re='Reialaleigh:BAABNQAECoEaAAIXAAgK9QfaOQCrAQAXAAgK9QfaOQCrAQAAAA==.',
Ry='Ryuk:BAAANQADCgMIAwAAAA==.',
Sa='Saberdiva:BAAANQAECggIBgAAAA==.Sabersidious:BAAANQADCgUIBQAAAA==.Sabpar:BAACNQAFFIEOAAMNAAUK9gy0CwB7AQANAAUK9gy0CwB7AQAYAAUK0QqyCwBsAQA1AAQKgSAAAg0ACQoVHyEiAOICAA0ACQoVHyEiAOICAAAA.Sabs:BAAANQAECgYICAABNQAFFAUIDgANAPYMAA==.Saladin:BAAANQAECgcIEAAAAA==.Sanakht:BAABNQAECoEYAAIXAAkKOBdYGwB5AgAXAAkKOBdYGwB5AgAAAA==.',
Sc='Schweitzer:BAAANQADCgYIBgAAAA==.',
Se='Seditionist:BAAANQADCgYIFAAAAA==.Serafina:BAAANQAECgQIBAABNQAFFAUIDwAMAC0OAA==.',
Sh='Shakira:BAAANQADCgYICwABNQAECggIGgAXAPUHAA==.Sheepd:BAAANQAECgcIBwABNQAFFAUICQAQAKAWAA==.',
Si='Sidewind:BAAANQADCgYICgAAAA==.Sidthekid:BAAANQADCgYIDwAAAA==.Sinayion:BAAANQAECgQIBwAAAA==.',
Sm='Smokestackz:BAAANQAECgEIAQAAAA==.',
Sn='Snepaí:BAABNQAECoEhAAIDAAkKixtAOADMAgADAAkKixtAOADMAgAAAA==.',
So='Sonamis:BAAANQAECgEIAQAAAA==.',
St='Stepdemonh:BAAANQADCgYIBgAAAA==.',
Su='Sunofthewar:BAAANQADCgQIBAAAAA==.',
Ta='Tankobell:BAABNQAECoEWAAIPAAgKowzTngCtAQAPAAgKowzTngCtAQAAAA==.',
Te='Terrible:BAEANQAECgEIAQABNQAFFAUICAAZAOULAA==.',
Th='Thañatos:BAAANQAECgcICwABNQAECgkJLAAQADofAA==.',
Tr='Truart:BAABNQAECoEbAAIPAAkK7xFddQATAgAPAAkK7xFddQATAgAAAA==.',
Tu='Tuerjoie:BAAANQAECgIIAgAAAA==.',
Va='Varfus:BAAANQADCgYIDAABNQAECggICAABAAAAAA==.',
Ve='Veinglory:BAABNQAECoEZAAIQAAcK7x6OKABhAgAQAAcK7x6OKABhAgAAAA==.Velentre:BAAANQAECgYIBgAAAA==.',
Vi='Vindictress:BAEANQAECggIBQABNQAECggIIQAPAOgZAA==.',
Vo='Vonka:BAAANQADCgQIBAAAAA==.',
Wa='Walnut:BAAANQAECgEIAQAAAA==.',
Wi='Wigskid:BAAANQAECgQIBQAAAA==.Winney:BAAANQAECggIDQAAAA==.',
Wo='Wonkz:BAAANQABCgQIBwAAAA==.',
Wr='Wrequiem:BAAANQADCgUIBgAAAA==.',
Xh='Xhiaky:BAAANQADCgQIBAAAAA==.',
Xy='Xyran:BAAANQADCgQIBAAAAA==.',
Yo='Yoyomba:BAAANQAECgcICgABNQAECgkJIgADALUTAA==.',
Ze='Zenderal:BAAANQADCgEIAQAAAA==.Zeposo:BAAANQAECgUIBQABNQAECgYIEgABAAAAAA==.Zeptide:BAAANQAECgYIEgAAAA==.',
['Zë']='Zëp:BAAANQAECgQICwABNQAECgYIEgABAAAAAA==.',
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
