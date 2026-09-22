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

local lookup = {'Mage-Frost','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Warlock-Demonology','Hunter-BeastMastery','Shaman-Enhancement','Shaman-Restoration','Monk-Windwalker','Unknown-Unknown','Warlock-Destruction','Hunter-Marksmanship','Shaman-Elemental','Priest-Shadow','Warrior-Fury','Warrior-Arms','Warlock-Affliction','DemonHunter-Vengeance',}
local provider = {region='US',realm='Vashj',name='US',type='weekly',zone=53,date='2026-09-22',data={Ah='Ahtreyou:BAAANQADCggIDgAAAA==.',
An='Anblod:BAAANQADCgYIBgAAAA==.Anduin:BAAANQAECgIIAwAAAA==.Angelona:BAABNQAECoEeAAMBAAkKtyUoAADhAwABAAkKtyUoAADhAwACAAEKNgn3ZgE0AAAAAA==.Angelsenvy:BAABNQAECoEZAAMDAAgKzBhBKQBjAgADAAgKzBhBKQBjAgAEAAYK3hItfQCHAQAAAA==.Antal:BAAANQADCgQJBgAAAA==.',
Ar='Archadis:BAAANQAECgYJEQAAAA==.',
Av='Avyhn:BAAANQAECggJDAABNQAFFAYIDwAFAEohAA==.',
Az='Azazel:BAAANQABCgMIAwAAAA==.Azmoodan:BAAANQADCggICAAAAA==.',
Ba='Bariki:BAAANQADCgcIDQABNQAECggIHwAGAEQgAA==.',
Be='Bellithia:BAAANQAECgUJCQAAAA==.Benji:BAAANQAECgEIAQAAAA==.Bennylava:BAAANQADCgYIBwAAAA==.Bewear:BAAANQAECgUIDgAAAA==.',
Bi='Bigexplosion:BAAANQABCgMIBAAAAA==.',
Bl='Blitzkreig:BAAANQADCgYIBgAAAA==.Blueberry:BAAANQAECgIJAwAAAA==.',
Bu='Bubbulubb:BAAANQAECgYIDgAAAA==.Bulla:BAAANQAECgYJDgAAAA==.Bullthing:BAAANQAECgcJEAAAAA==.',
Ca='Calex:BAAANQAECgEJAQAAAA==.Cathedrian:BAAANQADCggJDgAAAA==.',
Ch='Chantu:BAAANQADCggJDwAAAA==.Chipsbambee:BAAANQAECgQJBwAAAA==.Chttrbox:BAACNQAFFIEMAAMHAAYKdB5+AAAKAgAHAAUKoyB+AAAKAgAIAAMKbBxQCQAHAQA1AAQKgSQAAwgACQpOIlQJAEcDAAgACQpOIlQJAEcDAAcACAryI7UDADQDAAAA.',
Co='Colacan:BAAANQADCgYIDQAAAA==.Combust:BAABNQAECoEcAAIBAAgKqiLtAQAHAwABAAgKqiLtAQAHAwAAAA==.',
Cr='Creepndeath:BAAANQADCgYIBgAAAA==.Crux:BAAANQAECgQJBAAAAA==.',
Da='Dallan:BAAANQADCgIIAgAAAA==.Davechapally:BAAANQADCgYIBgAAAA==.',
De='Delaomega:BAAANQAECgYJEgAAAA==.',
Do='Doozler:BAAANQAECgUICwAAAA==.',
Dr='Drash:BAAANQAECgEIAQAAAA==.Drown:BAAANQAECgMIBQAAAA==.',
Du='Durotagg:BAAANQADCgYIBgAAAA==.',
Ea='Earlgrips:BAAANQAECgIIBAAAAA==.',
El='Elfguy:BAAANQADCgcIDwAAAA==.Elvishblood:BAAANQADCgcIDwAAAA==.',
Er='Eremetrii:BAEANQAECgQIBAAAAA==.',
Ev='Evocat:BAAANQAECgcIEgAAAA==.',
Fe='Fec:BAABNQAECoEZAAIHAAgKWhxABwC/AgAHAAgKWhxABwC/AgAAAA==.',
Fi='Fibaldrachi:BAAANQAECgUJDQAAAA==.',
Gh='Ghantu:BAAANQAECgQIDgAAAA==.Ghazghkull:BAAANQABCgYIBgAAAA==.',
Gr='Granniekat:BAAANQAECgEIAQAAAA==.',
Ha='Haven:BAAANQADCgYICwAAAA==.',
He='Helendir:BAAANQADCgcICAAAAA==.Herbertwest:BAAANQADCgYIBgAAAA==.',
Hi='Hiimmas:BAACNQAFFIEVAAIJAAcK6hIRAQBVAgAJAAcK6hIRAQBVAgA1AAQKgSYAAgkACQpNI2AEAGUDAAkACQpNI2AEAGUDAAAA.',
Ho='Hoggmaxxing:BAAANQADCggICAAAAA==.',
Hy='Hyacinthe:BAAANQAECgYIEAAAAA==.',
If='Ifany:BAAANQADCgQIBgAAAA==.',
Il='Illidanswife:BAAANQAECgEJAQAAAA==.',
In='Inspiremoon:BAAANQAECgUIDAAAAA==.',
Ir='Irishpryde:BAAANQABCgMJBQAAAA==.',
Jo='Jojojojojojo:BAAANQAECgQJCgABNQAECgYIBgAKAAAAAA==.',
Ka='Kaliv:BAAANQAECgEJAQAAAA==.Kantherath:BAAANQABCggJEwAAAA==.',
Ke='Kensonse:BAAANQADCgIJAgAAAA==.Keyadron:BAAANQADCgQIBAAAAA==.',
Ki='Kirab:BAAANQAECgQIDAAAAA==.Kis:BAAANQAECgEJAQAAAA==.Kisten:BAAANQADCgYICQAAAA==.',
Kr='Kreid:BAAANQAECgQJBQAAAA==.',
La='Larryirl:BAAANQABCgEIAQABNQAECgEIAgAKAAAAAA==.Larryp:BAAANQAECgEIAgAAAA==.',
Le='Lemén:BAAANQAECgUIDAAAAA==.',
Li='Ligmaw:BAAANQAECgQIBAAAAA==.Lildonny:BAAANQADCgYIDAAAAA==.Lilpriest:BAAANQAECgIIAgAAAA==.Linaei:BAAANQAECgcICQAAAA==.',
Lo='Lockinflame:BAACNQAFFIEGAAMFAAMKfQn9GgCPAAAFAAIKrwf9GgCPAAALAAEKGA1kEABXAAA1AAQKgSIAAwsACQqMHcwOAPABAAUACAobG3YlAI8CAAsABwqfGMwOAPABAAAA.',
Lu='Luman:BAAANQAECgcJCQAAAA==.',
Ly='Lyndras:BAAANQAECgUIEQAAAA==.',
Ma='Maloob:BAAANQABCgIIAgAAAA==.',
Me='Meerlin:BAAANQABCggICQAAAA==.Melathia:BAAANQAECgMJBgAAAA==.',
Mi='Minimerlin:BAAANQAECgMIAwAAAA==.',
Mo='Moaroak:BAABNQAECoEfAAMGAAgKRCD/HADNAgAGAAgKRCD/HADNAgAMAAEKiRRWWAA9AAAAAA==.Monilara:BAAANQAECgYICwAAAA==.Moredis:BAAANQABCgEIAQAAAA==.Morsiroth:BAAANQADCgEJAQAAAA==.',
Mu='Muskei:BAAANQADCggIDAABNQAECgYIEAAKAAAAAA==.',
Na='Narcissus:BAAANQADCggICwAAAA==.',
Ne='Neero:BAAANQAECgEIAQAAAA==.Nelena:BAAANQAECgQICwAAAA==.Nerdbynature:BAAANQAECgQIBwAAAA==.Nezhyt:BAAANQAECgUJDQAAAA==.',
Ni='Niña:BAAANQADCgUJBQAAAA==.',
No='Noodles:BAAANQADCgEIAQABNQAECgUIDAAKAAAAAA==.Nori:BAABNQAECoEWAAINAAcK7hy9MwA1AgANAAcK7hy9MwA1AgABNQAFFAYJDwACAP4gAA==.Notorious:BAAANQAECgEJAQAAAA==.',
Ny='Ny:BAAANQAECgEJAQABNQAECgQIBAAKAAAAAA==.Nyssebows:BAAANQAECggJBQAAAA==.Nythaenia:BAABNQAECoEhAAIDAAkKDR1NEAAJAwADAAkKDR1NEAAJAwAAAA==.',
Ob='Obe:BAABNQAECoEZAAIOAAgKPhh4EgB5AgAOAAgKPhh4EgB5AgAAAA==.',
On='One:BAAANQAECgYJDwAAAA==.',
Pa='Palydawg:BAAANQABCgYIBgAAAA==.Paÿp:BAAANQAECgUJCgAAAA==.',
Pe='Pentasaurusr:BAAANQAECgUJEQAAAA==.',
Pl='Platemedic:BAAANQAECgYIBgAAAA==.',
Pu='Purp:BAAANQAECgEIAQAAAA==.',
Py='Pyromainiac:BAAANQAECgEIAQAAAA==.',
Qu='Queteimporta:BAAANQAECgMIBAAAAA==.',
Ra='Raynsera:BAAANQAECgEIAQAAAA==.',
Re='Recmod:BAAANQAECgQJEQAAAA==.',
Rk='Rkaitoufashi:BAAANQAECgIIAgAAAA==.',
Ro='Roussalina:BAAANQAECgMIAwAAAA==.',
Ru='Ruhua:BAAANQAECggJEwAAAA==.',
Ry='Ryahask:BAAANQAECgQJBwAAAA==.',
Sa='Sadisticrage:BAAANQAECgcJDAAAAA==.Samana:BAAANQAECgUJCAAAAA==.',
Se='Seeturtle:BAAANQAECgYIEQAAAA==.Selûne:BAAANQADCgEIAQAAAA==.',
Sh='Shera:BAAANQADCgcIDQAAAA==.Shocksalot:BAAANQAECgUICQABNQAECgEIAQAKAAAAAA==.',
Sm='Smell:BAABNQAECoEaAAIEAAcKhhPNbAC2AQAEAAcKhhPNbAC2AQAAAA==.',
So='Solheim:BAAANQAFFAEJAQAAAA==.Soullie:BAAANQAECgEIAQAAAA==.',
Sp='Spacemonk:BAAANQADCggICAAAAA==.Spire:BAAANQADCggICQAAAA==.Sproutling:BAAANQAECgUJCAAAAA==.',
St='Stearphen:BAAANQAECgYJCQAAAA==.Stephmage:BAAANQABCgMIAwAAAA==.Stormlight:BAAANQAECgEIAQAAAA==.Strawhatdon:BAAANQADCgYIBgAAAA==.',
Sw='Swizky:BAAANQADCgcIBwABNQAECgQIBwAKAAAAAA==.',
Sy='Syrxxa:BAAANQABCgYJCwAAAA==.',
Ta='Tatri:BAAANQADCgIIAgAAAA==.Taurnil:BAAANQAECgQICwAAAA==.',
Te='Telperion:BAAANQADCgQIBAAAAA==.',
Th='Thorodinson:BAAANQADCgcICAAAAA==.',
Ti='Ticktickboom:BAAANQABCgMIAwAAAA==.Timika:BAAANQAECgUIDgAAAA==.Tinamarie:BAAANQAECgQJBQAAAA==.',
Uk='Ukan:BAABNQAECoEaAAIIAAgK0hZaMQAyAgAIAAgK0hZaMQAyAgAAAA==.',
Un='Unholydkguy:BAAANQADCgcIDQAAAA==.',
Ux='Uxx:BAAANQAECgEIAQAAAA==.',
Va='Vaeron:BAAANQAECgUICAAAAA==.Valareon:BAAANQAECgEIAQAAAA==.',
Ve='Vengeancez:BAABNQAECoEjAAMPAAkK1RpwBQBAAgAPAAcK3BlwBQBAAgAQAAUKNRdbhQB3AQAAAA==.',
Vi='Violetta:BAAANQAECgIIAgAAAA==.Visionaries:BAAANQADCgUIBwAAAA==.',
Vy='Vyeli:BAAANQABCgcJBwAAAA==.',
We='Weathergirl:BAAANQAECgEIAQAAAA==.',
Wy='Wy:BAAANQAECgQIBAAAAA==.',
Xa='Xanna:BAAANQADCgYIBgABNQAECgYJEQAKAAAAAA==.',
Xe='Xera:BAAANQADCgUIBgAAAA==.',
Yu='Yunàlestrà:BAABNQAECoEhAAQFAAgK9A1wbAB/AQAFAAcKcQ1wbAB/AQARAAIKOQfZGABdAAALAAEKjBF4YwA6AAAAAA==.',
Zy='Zylith:BAABNQAECoEfAAISAAkKZh0pAgAHAwASAAkKZh0pAgAHAwAAAA==.',
['Ád']='Ádelaida:BAAANQAECgIIAgABNQAECgMIBAAKAAAAAA==.',
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
