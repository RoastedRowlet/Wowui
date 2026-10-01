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

local lookup = {'Unknown-Unknown','Druid-Restoration','Warrior-Arms','Mage-Arcane','DeathKnight-Unholy','Warlock-Affliction','Priest-Holy','Monk-Brewmaster','Druid-Balance','Hunter-BeastMastery','Warlock-Demonology','DemonHunter-Vengeance','Paladin-Retribution','DeathKnight-Blood','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Shaman-Elemental','Rogue-Outlaw','DemonHunter-Havoc','Warrior-Protection','Shaman-Restoration','Rogue-Assassination',}
local provider = {region='US',realm='Smolderthorn',name='US',type='weekly',zone=53,date='2026-09-29',data={Ai='Aitnd:BAAANQADCggIEAAAAA==.Aitns:BAAANQADCgIIAgAAAA==.',
Al='Alaszun:BAAANQADCggICQAAAA==.Alorothius:BAAANQAECgUICAABNQAECgUICQABAAAAAA==.Alpacalypse:BAAANQADCggICAAAAA==.Altha:BAABNQAECoEgAAICAAkK9wtkHQDvAQACAAkK9wtkHQDvAQAAAA==.',
Am='Amilde:BAAANQADCggICQABNQAECgkJGQADAKcYAA==.',
An='Anarisa:BAABNQAECoEdAAIEAAgKhxMUiwAqAgAEAAgKhxMUiwAqAgAAAA==.',
Ap='Appocolypto:BAAANQAECgUIBQAAAA==.',
Ar='Areese:BAAANQADCgUIAgAAAA==.Arës:BAAANQAECgEIAQAAAA==.',
Av='Averse:BAABNQAECoEkAAIFAAkKpyNQCABeAwAFAAkKpyNQCABeAwAAAA==.',
Ba='Balnor:BAAANQAECgYIDQAAAA==.',
Bi='Bigbeef:BAAANQADCgEIAQAAAA==.',
Bo='Borgus:BAAANQAECgUJEgAAAA==.',
Br='Brimstone:BAAANQADCggIEAAAAA==.Brokemav:BAABNQAECoErAAIGAAkKoByMAQAJAwAGAAkKoByMAQAJAwAAAA==.Brooklin:BAABNQAECoElAAIEAAkKSRJreQBUAgAEAAkKSRJreQBUAgAAAA==.',
Bu='Busky:BAAANQAECgYIEwAAAA==.',
Ca='Cao:BAAANQAECgcICgAAAA==.Cassiopea:BAABNQAECoEZAAIHAAgK8BkALAB5AgAHAAgK8BkALAB5AgAAAA==.',
Ce='Cellcept:BAAANQADCgYIDwAAAA==.',
Ch='Chinchillada:BAAANQAECgIIAgAAAA==.Chows:BAAANQADCgYIBgABNQAECgkJGQADAKcYAA==.Chre:BAAANQADCggICQAAAA==.',
Cl='Clafoutis:BAAANQADCgUIBwAAAA==.Clanker:BAACNQAFFIEKAAIIAAUKKBqlAQClAQAIAAUKKBqlAQClAQA1AAQKgSIAAggACQooIzYCAG8DAAgACQooIzYCAG8DAAAA.',
['Cà']='Càss:BAAANQABCgEIAQABNQAECggIGQAHAPAZAA==.',
Da='Dabajabaza:BAAANQAECgUICQAAAA==.Dabergerak:BAAANQAFFAEIAwAAAA==.',
De='Deathntaxes:BAAANQAECgcIBwAAAA==.Dejanira:BAABNQAECoEZAAMCAAgKEA0ZIwCtAQACAAgKEA0ZIwCtAQAJAAEK6AcKlwApAAAAAA==.Deyedrel:BAAANQAECgYIEQAAAA==.',
Di='Diddily:BAAANQAECgYICgAAAA==.',
Dr='Dridarok:BAAANQAECgYIDQAAAA==.',
El='Elise:BAAANQADCgUIBQABNQAECggIHgAKAAcbAA==.Elstrid:BAABNQAECoEaAAILAAYK4BS7eACdAQALAAYK4BS7eACdAQAAAA==.',
Er='Eremisa:BAAANQADCgYIBgABNQAECggIHQAEAIcTAA==.',
Ev='Eve:BAACNQAFFIEKAAIMAAUKLQ4kAQBEAQAMAAUKLQ4kAQBEAQA1AAQKgSEAAgwACQpzG10EALUCAAwACQpzG10EALUCAAAA.Evochre:BAAANQADCgQIBQAAAA==.',
Fa='Fantasy:BAAANQAECgYIDQAAAA==.',
Fe='Felbourn:BAAANQAECgcIEwAAAA==.Fendraim:BAAANQADCgMIBgAAAA==.',
Fi='Figurefour:BAAANQAECgIIAgAAAA==.',
Fl='Flaccidmass:BAAANQAECgEIAgAAAA==.',
Fr='Frailboosy:BAABNQAECoEhAAINAAkKfyDELwDMAgANAAkKfyDELwDMAgAAAA==.',
Ga='Gaara:BAAANQAECgcIBwAAAA==.',
Ge='Gemini:BAAANQAECgYIBwAAAA==.',
Gl='Glitz:BAAANQAECgQIBAABNQAFFAUICgAMAC0OAA==.',
Gr='Gravedigger:BAABNQAECoEkAAIOAAgKmB4BGQC1AgAOAAgKmB4BGQC1AgAAAA==.',
['Gü']='Güts:BAABNQAECoEdAAIDAAgKdRLAbwD2AQADAAgKdRLAbwD2AQAAAA==.',
Ho='Holywagyu:BAAANQADCgcIBwAAAA==.Howlimer:BAAANQADCgEIAQAAAA==.',
Hu='Huf:BAAANQADCgYIDAABNQAFFAUICgAPAKkTAA==.',
Ir='Ironnmonk:BAAANQADCgYIBQABNQAECgUIBQABAAAAAA==.',
Ja='Java:BAAANQADCgQIBgABNQAECgYIEwABAAAAAA==.Jawshoeuh:BAAANQAECgEIAQAAAA==.',
Ju='Jujumon:BAAANQADCgYIBgAAAA==.Jujuzor:BAAANQAECgEIAQAAAA==.Jujuzul:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Justimp:BAAANQAECgcIEwAAAA==.',
Ka='Karlek:BAABNQAECoEgAAINAAgKKxL5cADvAQANAAgKKxL5cADvAQAAAA==.Kassamella:BAAANQADCggJCAABNQAECgIIAgABAAAAAA==.Kassanndra:BAEANQAECggJCAABNQAECggIHwANAG8ZAA==.Kazeshiní:BAAANQADCgQIBAAAAA==.',
La='Lalana:BAAANQAECgEIAQAAAA==.Lan:BAAANQADCgYIDAAAAA==.',
Li='Lilshorty:BAAANQAECgEIAQAAAA==.',
Lo='Lofwyr:BAABNQAECoEXAAMQAAkK5AxeJABUAQAQAAcKjAheJABUAQARAAUKbQtcDgABAQAAAA==.',
Lu='Lumaie:BAAANQAECgYIDQAAAA==.Lumistress:BAEBNQAECoEfAAINAAgKbxnmUwBIAgANAAgKbxnmUwBIAgAAAA==.',
Ly='Lynni:BAAANQADCgUIBQAAAA==.',
Ma='Malcharion:BAAANQAECgQIBAAAAA==.Mamarue:BAAANQADCgYIBgAAAA==.',
Mc='Mcshâms:BAABNQAECoEXAAISAAgKUR9aIQDOAgASAAgKUR9aIQDOAgAAAA==.',
Mu='Munir:BAAANQADCggIIQAAAA==.',
Na='Naeltian:BAABNQAECoEgAAITAAkKoBxYAgAWAwATAAkKoBxYAgAWAwAAAA==.',
Ne='Necromachine:BAABNQAECoEgAAIFAAkK2R7sEQD2AgAFAAkK2R7sEQD2AgAAAA==.Nevermore:BAABNQAECoEZAAIUAAgK2hroGgB9AgAUAAgK2hroGgB9AgAAAA==.',
No='Noctislucis:BAAANQABCgIIAgAAAA==.Noobdk:BAAANQAFFAQIBAAAAA==.Noobmonkey:BAAANQADCgYIBgABNQAFFAQIBAABAAAAAA==.Noobwarr:BAABNQAECoEjAAMVAAkKviR1AQCcAwAVAAkKviR1AQCcAwADAAcKYxfMbQD7AQABNQAFFAQIBAABAAAAAA==.Novax:BAAANQAECgUIBwAAAA==.',
Ny='Nyquil:BAEANQAECggICAABNQAECggIHwANAG8ZAA==.',
Ol='Oldreligion:BAAANQADCggICAAAAA==.',
Pe='Perugius:BAAANQADCgYICgABNQAECgYIGgALAOAUAA==.',
Ph='Phrenulhum:BAAANQADCgcIBwAAAA==.',
Pr='Predmost:BAAANQABCgQIBAAAAA==.Prettypoison:BAAANQAECgQICAAAAA==.',
Pu='Pussehfart:BAAANQADCggJDAAAAA==.Putz:BAABNQAECoEnAAIMAAkKvhoyBAC7AgAMAAkKvhoyBAC7AgAAAA==.Putzadin:BAAANQAECgEIAQAAAA==.',
Ra='Rainbow:BAAANQAECgUICQABNQAECgYIDQABAAAAAA==.',
Re='Reialaleigh:BAAANQAECgcJEQAAAA==.',
Ry='Ryuk:BAAANQADCgMIAwAAAA==.',
Sa='Saberdiva:BAAANQAECggIAgAAAA==.Sabersidious:BAAANQADCgUIBQAAAA==.Sabpar:BAACNQAFFIEJAAMWAAUK0QqJCAB2AQAWAAUK0QqJCAB2AQASAAIKJQ47GQCYAAA1AAQKgSAAAhIACQoVH1YaAP8CABIACQoVH1YaAP8CAAAA.Sabs:BAAANQAECgQIBAABNQAFFAUICQAWANEKAA==.Saladin:BAAANQAECgUICQAAAA==.Sanakht:BAABNQAECoEVAAIXAAgKIBZuHABEAgAXAAgKIBZuHABEAgAAAA==.',
Se='Seditionist:BAAANQADCgYIDwAAAA==.Serafina:BAAANQADCgYIBgABNQAFFAUICgAMAC0OAA==.',
Sh='Shakira:BAAANQADCgYIBgABNQAECgcJEQABAAAAAA==.Sheepd:BAAANQADCgYIBgABNQAFFAQIBAABAAAAAA==.',
Si='Sidewind:BAAANQADCgYICgAAAA==.Sidthekid:BAAANQADCgYIDwAAAA==.Sinayion:BAAANQAECgQIBQAAAA==.',
Sm='Smokestackz:BAAANQAECgEIAQAAAA==.',
Sn='Snepaí:BAABNQAECoEZAAIDAAkKpxj7QQCKAgADAAkKpxj7QQCKAgAAAA==.',
So='Sonamis:BAAANQAECgEIAQAAAA==.',
St='Stepdemonh:BAAANQADCgYIBgAAAA==.',
Su='Sunofthewar:BAAANQADCgQIBAAAAA==.',
Ta='Tankobell:BAABNQAECoEWAAINAAgKowwvgwC8AQANAAgKowwvgwC8AQAAAA==.',
Te='Terrible:BAEANQAECgEIAQABNQAECgkJJgADAPghAA==.',
Th='Thañatos:BAAANQAECgUIBQABNQAECggIJAAOAJgeAA==.',
Tr='Truart:BAAANQAECgcIEgAAAA==.',
Tu='Tuerjoie:BAAANQADCgYIDQAAAA==.',
Va='Varfus:BAAANQADCgYIDAABNQAECgcIBwABAAAAAA==.',
Ve='Veinglory:BAAANQAECgUIEAAAAA==.Velentre:BAAANQAECgYIBgAAAA==.',
Vi='Vindictress:BAEANQAECggIBQABNQAECggIHwANAG8ZAA==.',
Wa='Walnut:BAAANQADCgYICAAAAA==.',
Wi='Wigskid:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Winney:BAAANQAECggIDQAAAA==.',
Wo='Wonkz:BAAANQABCgQIBwAAAA==.',
Wr='Wrequiem:BAAANQADCgUIBgAAAA==.',
Xh='Xhiaky:BAAANQADCgQIBAAAAA==.',
Yo='Yoyomba:BAAANQAECgMIAwABNQAECggIHQADAHUSAA==.',
Ze='Zenderal:BAAANQADCgEIAQAAAA==.Zeposo:BAAANQADCggIJQABNQAECgUIDAABAAAAAA==.Zeptide:BAAANQAECgUIDAAAAA==.',
['Zë']='Zëp:BAAANQAECgQIBwABNQAECgUIDAABAAAAAA==.',
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
