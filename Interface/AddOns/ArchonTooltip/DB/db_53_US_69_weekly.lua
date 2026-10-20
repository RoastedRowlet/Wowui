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

local lookup = {'Mage-Arcane','Mage-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','Hunter-Survival','Paladin-Holy','Paladin-Retribution','Rogue-Assassination','Shaman-Restoration','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Shaman-Enhancement','Shaman-Elemental','Hunter-Marksmanship','Druid-Feral','Monk-Brewmaster','Druid-Guardian','Evoker-Devastation','Unknown-Unknown','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm='Detheroc',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abrak:BAABNQAECn8hAAMBAAkK9gWyAwGHAQABAAkK9gWyAwGHAQACAAEK1AKaUgAhAAAAAA==.',
Ae='Aerirea:BAAANQAECgUIDAAAAA==.',
Al='Aladiirn:BAACNQAFFH8OAAMDAAUK+gfHDABIAQADAAUK+gfHDABIAQAEAAIK+wMJEwBpAAA1AAQKfyAAAwQACgrAGpghAD8CAAQACQq6GZghAD8CAAMABAp2GsQZACUBAAAA.',
Am='Amii:BAAANQAECgIIAgAAAA==.',
Ao='Aoiphe:BAABNQAECn85AAMFAAoKlhY4BQAOAgAFAAoKlhY4BQAOAgAGAAEKAAApwQAgAAAAAA==.Aophei:BAAANQADCgYIBgAAAA==.',
As='Ashleeann:BAABNQAECn8YAAIHAAkKUwnslQDcAQAHAAkKUwnslQDcAQAAAA==.',
Az='Azuro:BAABNQAECn8fAAIIAAkKtyGWBgD7AgAIAAkKtyGWBgD7AgAAAA==.',
Ba='Bahlsak:BAAANQADCgcIBwAAAA==.',
Bb='Bbygrl:BAAANQABCgcICgAAAA==.',
Bl='Bloodbrew:BAAANQAFFAQIBAAAAA==.',
Bo='Botadin:BAAANQADCgYIBgAAAA==.',
Br='Brieg:BAABNQAECn8dAAMJAAgKBRIxEQBYAQAJAAgKBRIxEQBYAQAKAAIKAADjvwBrAAAAAA==.',
['Bä']='Bäzü:BAAANQAECgQIBAABNQAECggIKgALAPIbAA==.',
['Bô']='Bôw:BAABNQAECn8cAAIHAAoKywgRfwAPAgAHAAoKywgRfwAPAgAAAA==.',
Ca='Cassiis:BAAANQAECgUIBQAAAA==.',
Ce='Cerinis:BAABNQAECn8bAAIMAAkKVx4XAwDsAgAMAAkKVx4XAwDsAgAAAA==.',
Co='Corgtag:BAABNQAECn84AAMNAAoKBAaYgwCQAQANAAkKlQaYgwCQAQAOAAoKlA9lSQAyAQAAAA==.Cowpoke:BAAANQADCgEIAQAAAA==.',
Cr='Cr:BAAANQAECggIEgAAAA==.Creep:BAABNQAECn8kAAIPAAoKKBIjCgB/AQAPAAoKKBIjCgB/AQAAAA==.',
Da='Daroux:BAAANQAECgUIEAAAAA==.',
Di='Diazz:BAAANQADCgMIAwAAAA==.',
Do='Dove:BAAANQADCgIIAgAAAA==.',
Du='Dunspore:BAABNQAECn8fAAIQAAkKqhtHHwDuAgAQAAkKqhtHHwDuAgAAAA==.',
Em='Emmafrost:BAAANQADCgUIBQAAAA==.',
Ex='Exalt:BAAANQADCgQIBAAAAA==.',
Ez='Ezclass:BAAANQAECgIIAwAAAA==.',
Fi='Finalgodfury:BAAANQADCggICAAAAA==.Finn:BAAANQAECgYJCQAAAA==.',
Fu='Fullofbull:BAAANQAECgIIAgAAAA==.Furmidable:BAAANQAECgQIBAAAAA==.',
Ga='Gandi:BAAANQAECgQIBAAAAA==.',
Gi='Girthspell:BAAANQADCgMIAwAAAA==.',
Gr='Grizmo:BAAANQAECgMIBQAAAA==.Grock:BAABNQAECn8mAAIQAAgK/iNPFwAYAwAQAAgK/iNPFwAYAwAAAA==.',
Gx='Gxxse:BAACNQAFFH8IAAMPAAQKIQhkEQDUAAAPAAMKIQhkEQDUAAARAAEKAABiEAAAAAA1AAQKfxcAAxEACQoTFmohAOEAAA8ACQoEFD5AAMwBABEABArCGGohAOEAAAAA.',
He='Hewman:BAAANQAECgEIAQAAAA==.',
Hi='Higgz:BAAANQAECgUIBwAAAA==.',
Ho='Hoser:BAABNQAECn87AAIOAAoKvx5ELQATAwAOAAoKvx5ELQATAwAAAA==.',
['Hö']='Höllenhund:BAAANQADCgUIBQAAAA==.',
Im='Imptastic:BAABNQAECn8bAAISAAkKlBToBwAYAgASAAkKlBToBwAYAgAAAA==.',
Jo='Jollyolly:BAABNQAECn8pAAMTAAoKpxR5CgBPAgATAAoKdxJ5CgBPAgAUAAcKlQ9/mQCnAQAAAA==.Joseph:BAAANQADCggICAAAAA==.',
Kr='Krimzin:BAABNQAECn8jAAQVAAkK6xxLFAAkAgAVAAcKvxtLFAAkAgAQAAkKlRDSYADsAQAWAAMK/h215gDKAAABNQAFFAYIDQAHAN8VAA==.',
Le='Lebronmaldon:BAAANQAECgEIAgAAAA==.Lewiz:BAAANQAECgMIBwAAAA==.',
Lu='Lucetia:BAAANQABCgMJAgAAAA==.',
Ma='Macewindu:BAAANQAECgQIDAAAAA==.Magifrey:BAABNQAECn8XAAICAAYKtA8hFwBDAQACAAYKtA8hFwBDAQAAAA==.',
Mi='Mirabeaux:BAAANQADCgQIBAAAAA==.',
Mo='Mokar:BAAANQADCgEIAQAAAA==.Morelia:BAABNQAECn82AAIXAAgK1Qb4OQCBAQAXAAgK1Qb4OQCBAQAAAA==.',
Mu='Mugsfaru:BAABNQAECn8qAAIHAAkKXCN7EwBRAwAHAAkKXCN7EwBRAwAAAA==.',
Mv='Mvp:BAAANQAECgEIAQAAAA==.',
Na='Nabecovid:BAABNQAECn8uAAIYAAoKMB7cAQDyAQAYAAoKMB7cAQDyAQAAAA==.Nasha:BAABNQAECn8zAAIOAAoKwyGoBgDFAwAOAAoKwyGoBgDFAwAAAA==.',
Pa='Palifrey:BAAANQAECgIIAgAAAA==.Pantojak:BAABNQAFFH8FAAMLAAIK9AsjBwCAAAALAAIKeQkjBwCAAAAZAAIKbQt2CQB2AAABNQAECgkJHwAIALchAA==.Parksnar:BAAANQADCgEIAQAAAA==.',
Ph='Phouchg:BAABNQAECn83AAMHAAoKjCCCMADbAgAHAAkKjCCCMADbAgAXAAkK4RSuDwALAQAAAA==.',
Pi='Pirotessa:BAABNQAECn8rAAICAAoKih2uBQCzAgACAAoKih2uBQCzAgAAAA==.',
Pl='Plumpuddin:BAAANQAECgQIBAAAAA==.',
Ra='Rapscallion:BAAANQADCgQIBAABNQAECggIFgAHACEbAA==.Rayven:BAAANQAECgEIAQAAAA==.',
Re='Redtide:BAAANQAECgUICgAAAA==.Rei:BAAANQAECgQIBAAAAA==.Reptar:BAACNQAFFH8ZAAIGAAYKFByZBgAqAgAGAAYKFByZBgAqAgA1AAQKfyUAAwYACQriJM4RADkDAAYACQriJM4RADkDABoABArjH2gsADUBAAAA.',
Ro='Roaar:BAABNQAECn8uAAIMAAkKXx8OAgAxAwAMAAkKXx8OAgAxAwAAAA==.',
Ry='Ryukyu:BAABNQAECn8bAAIbAAkK7hgMEwAeAgAbAAkK7hgMEwAeAgAAAA==.',
Sa='Saintee:BAAANQADCgYICQAAAA==.Savz:BAAANQADCgMIAwAAAA==.',
Sc='Schro:BAABNQAECn8fAAIQAAoK1hc0PABvAgAQAAoK1hc0PABvAgAAAA==.',
Se='Seral:BAABNQAECn8YAAMBAAoKBA/QXgAAAQABAAkK6wzQXgAAAQACAAMK2BAtKQCtAAABNQAECgkJHwAIALchAA==.',
Si='Simoirette:BAAANQAECgUIEAAAAA==.',
Sk='Skoalman:BAAANQADCgMIAwAAAA==.',
So='Soulriot:BAAANQAECgcICwABNQAECggIEgAcAAAAAA==.',
St='Starlyn:BAAANQADCgcIBgAAAA==.',
Ta='Talmage:BAAANQAECgIIAgAAAA==.',
Tw='Twoinchfury:BAACNQAFFH8FAAIIAAIKRR7cAQCpAAAIAAIKRR7cAQCpAAA1AAQKfzMAAwgACgqhHS0DALgBAAgACgqhHS0DALgBAB0AAQoAAGNWATAAAAAA.',
Ve='Veledin:BAAANQAECgQIBAABNQAECgkJGwAMAFceAA==.Ventus:BAAANQAFFAEIAgAAAA==.Vergil:BAABNQAECn8jAAQDAAoKjxOeKABbAgADAAoKjxOeKABbAgAeAAEK8wh0MwAuAAAEAAEKQAGEdwAdAAAAAA==.',
Vi='Vinah:BAAANQAECgEIAQAAAA==.',
Wa='Wachabe:BAABNQAECn8WAAIaAAYKLRbGIwB4AQAaAAYKLRbGIwB4AQAAAA==.',
We='Weiden:BAABNQAECn84AAIGAAoKIBefCgCTAQAGAAoKIBefCgCTAQAAAA==.',
Yo='Yourpal:BAAANQADCgMIBgAAAA==.',
Ze='Zeldah:BAAANQADCgMIAwABNQAECgkJGwAbAO4YAA==.',
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
