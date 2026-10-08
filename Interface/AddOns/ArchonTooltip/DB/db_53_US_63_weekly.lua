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

local lookup = {'Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Hunter-BeastMastery','Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','Monk-Windwalker','Priest-Holy','Priest-Shadow','Paladin-Holy','Paladin-Retribution','Hunter-Survival','Shaman-Enhancement','Monk-Brewmaster','DeathKnight-Blood','Warlock-Demonology','Priest-Discipline','Warrior-Protection','Druid-Restoration','DemonHunter-Havoc','Warrior-Arms','Druid-Balance','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Hunter-Marksmanship','DemonHunter-Devourer',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abdalhazred:BAACNQAFFIEHAAIBAAMKLx5PAQAfAQABAAMKLx5PAQAfAQA1AAQKgSwAAwEACQrxIf8AAFcDAAEACQrtIf8AAFcDAAIAAgqsGVBHAJ8AAAAA.Abilus:BAABNQAECoEUAAIDAAQKYiBAKQBnAQADAAQKYiBAKQBnAQAAAA==.Abolis:BAAANQAECgUIDQAAAA==.',
Ad='Adarlan:BAAANQAECgIIAgAAAA==.',
Ae='Aelianna:BAAANQAECgEIAQAAAA==.',
Ai='Aintnowei:BAAANQAECgQIBQAAAA==.',
Al='Allina:BAAANQADCgYIBgAAAA==.Alnara:BAAANQAECgUIDgAAAA==.',
Am='Amoradis:BAAANQADCgUIDAAAAA==.',
An='Anarran:BAAANQADCgYIDAAAAA==.Animalfury:BAAANQAECgYIEgAAAA==.Anthestria:BAAANQAECgQIBQAAAA==.',
Aq='Aqurala:BAABNQAECoEdAAIEAAgKlCHXGgAUAwAEAAgKlCHXGgAUAwAAAA==.',
Ar='Arasham:BAAANQADCgQIBAABNQAECggIGQAEACkUAA==.Aravenn:BAABNQAECoEZAAIEAAgKKRQKYgAnAgAEAAgKKRQKYgAnAgAAAA==.Arkangel:BAAANQADCgYIBgAAAA==.Artemesia:BAAANQAECgMIAwABNQAFFAMIBwAFAEcfAA==.Artison:BAAANQADCgYIBgABNQAECgYIEQAGAAAAAA==.',
As='Ashiru:BAAANQADCgIIAgAAAA==.',
At='Ateup:BAAANQAECgEIAQABNQAECgUIDgAGAAAAAA==.Athenos:BAAANQADCgUIBwAAAA==.Atlás:BAAANQAECgUIBQAAAA==.',
Au='Aurum:BAAANQAECgQIBgAAAA==.',
Av='Avatartele:BAABNQAECoEXAAIHAAkKmxK5QQBEAgAHAAkKmxK5QQBEAgAAAA==.Avatartouka:BAABNQAECoErAAMFAAkKZyKACABsAwAFAAkKZyKACABsAwAHAAUKTBqBiABeAQAAAA==.Avrala:BAAANQADCgIJAgAAAA==.Avraria:BAAANQAECgcIDAAAAA==.Avylastral:BAAANQAECgIIAwAAAA==.',
Az='Azshaxa:BAACNQAFFIEIAAIIAAQKug9ICAAfAQAIAAQKug9ICAAfAQA1AAQKgSUAAggACQoQHacUAIwCAAgACQoQHacUAIwCAAAA.',
['Aí']='Aísling:BAAANQAECgIIBAAAAA==.',
Ba='Bagador:BAAANQAFFAEIAQAAAA==.Barby:BAAANQAECgEIAQAAAA==.Barrs:BAAANQADCgMIAwAAAA==.Bastille:BAAANQAECgEIAQAAAA==.',
Be='Bearbuthealz:BAAANQAECgIIAwAAAA==.Beautifulluv:BAABNQAECoEVAAMJAAgKIw4qZQC9AQAJAAgKIw4qZQC9AQAKAAYKrAtMOQA0AQAAAA==.Bekabeka:BAACNQAFFIEHAAILAAMKewpHFADiAAALAAMKewpHFADiAAA1AAQKgSwAAwsACQoLH9cUABsDAAsACQoLH9cUABsDAAwAAQqJDVdtATgAAAAA.Bekabekabeka:BAAANQABCggJAQABNQAFFAMIBwALAHsKAA==.Belfour:BAAANQADCgQIBAAAAA==.Bera:BAAANQAECggIBQAAAA==.',
Bi='Billybobjr:BAABNQAECoEYAAIFAAgK1xhIQAA1AgAFAAgK1xhIQAA1AgAAAA==.',
Bl='Bloodar:BAAANQAECggICAAAAA==.',
Bo='Bonski:BAAANQAECgEIBAAAAA==.Boosterman:BAAANQAECgYIEQAAAA==.',
Br='Brakkar:BAAANQADCggIGAAAAA==.Braxxis:BAAANQAECgQIBAABNQAFFAUICgANAG0PAA==.Breadstick:BAAANQAECgQIBgAAAA==.Bress:BAAANQADCgYIBgABNQAECgYIEwAGAAAAAA==.Britotems:BAAANQAECgEIAgAAAA==.Brozo:BAAANQAECgEIAQAAAA==.Brutaal:BAAANQADCgQJBAAAAA==.Bruutaal:BAAANQAECgEIAQAAAA==.Bryndel:BAAANQADCgYIBgAAAA==.',
Bu='Bubsydogo:BAAANQAECgEIAQAAAA==.',
Ca='Cacellice:BAAANQADCggICAAAAA==.Canoodles:BAAANQAECgYIDQAAAA==.',
Ce='Celaian:BAAANQAECgQICQABNQAECgQICQAGAAAAAA==.Celpanda:BAAANQAECgQICQAAAA==.',
Ch='Chadee:BAAANQADCggICAABNQAECgcICwAGAAAAAA==.Charybdia:BAAANQADCggJGwAAAA==.Cheesecake:BAABNQAECoEUAAIEAAcKLhARjQC/AQAEAAcKLhARjQC/AQAAAA==.Chidõri:BAABNQAECoEbAAMOAAkK+BU9DwBbAgAOAAkKYBU9DwBbAgAHAAQKhhf5uQDwAAAAAA==.Chunni:BAABNQAECoEXAAMPAAgKBgZnGQAoAQAPAAgK4ANnGQAoAQAIAAcK5AWgOAAXAQAAAA==.',
Co='Codap:BAAANQADCgEIAQAAAA==.',
Cr='Crayonman:BAAANQAECgcIEwAAAA==.Cronus:BAAANQAECgIIAwAAAA==.Cruelkitty:BAAANQAECgQIBQAAAA==.',
Da='Dahlinar:BAAANQAECgQIBwAAAA==.Dalov:BAABNQAECoEWAAMLAAYKKCG+QQBAAgALAAYKKCG+QQBAAgAMAAQKVB/PvwBkAQAAAA==.Damageworg:BAAANQADCgQIBAAAAA==.Dankley:BAAANQAECgIIBAAAAA==.Danystorm:BAAANQADCgcIBwABNQAFFAMIBwAFAEcfAA==.',
Dd='Ddream:BAAANQADCgEIAQAAAA==.',
De='Deaddude:BAABNQAECoEoAAIQAAgKshygJAB6AgAQAAgKshygJAB6AgAAAA==.Deathboi:BAAANQAECgUIEgAAAA==.Deathburgur:BAAANQADCggICAABNQAECgYIBwAGAAAAAA==.Deathcuddles:BAAANQAECgUIDgAAAA==.Deathflower:BAAANQAECgEIAQAAAA==.Dedcow:BAAANQAECgcICgAAAA==.',
Di='Diana:BAABNQAECoEZAAIEAAgKLwgoiADKAQAEAAgKLwgoiADKAQAAAA==.',
Do='Dontjudgemê:BAAANQADCgYJCgAAAA==.Dorcina:BAAANQADCgEIAQAAAA==.Downpour:BAAANQADCgUIBQAAAA==.',
Dr='Dracthyr:BAAANQAECgEIAQAAAA==.Dragonwarrio:BAABNQAECoEgAAIIAAkK5h4/DwDSAgAIAAkK5h4/DwDSAgAAAA==.Draltina:BAAANQAECgYIEgAAAA==.Drazira:BAAANQADCgcJDgAAAA==.Dresstokill:BAAANQADCggJEQAAAA==.Drmonkborg:BAAANQAECgUICwABNQAECggIFQAJAFUbAA==.Drovis:BAAANQAECgEIAgAAAA==.Druzzlek:BAAANQADCggIEQAAAA==.',
Du='Dubalnuar:BAAANQADCgUIDAAAAA==.Dubaltrok:BAAANQADCgUICQAAAA==.Dudde:BAAANQAECgcIDQABNQAECggIKAAQALIcAA==.Dulapin:BAAANQADCgIIAgAAAA==.Duskfu:BAABNQAECoEVAAIIAAcKUh2GGwAzAgAIAAcKUh2GGwAzAgAAAA==.Dustylock:BAABNQAECoEUAAMRAAYKHhaKggCyAQARAAYKHhaKggCyAQACAAEKzQdqdgAxAAAAAA==.',
Ea='Earthele:BAAANQAECgYICQAAAA==.',
El='Elfcaster:BAAANQAECgEIAQAAAA==.Elfowl:BAAANQADCgYIBwABNQAECgcIGgAJABkLAA==.',
Em='Emanonsahi:BAAANQAECgEIAQAAAA==.Emmel:BAAANQADCgcIDQAAAA==.',
Eq='Equeslucis:BAAANQAECggICQAAAA==.',
Er='Eromir:BAAANQAECgQICwABNQAECgUIDgAGAAAAAA==.Eryi:BAAANQADCggIKgAAAA==.',
Ev='Eviserator:BAAANQADCgMIBgAAAA==.',
Fa='Fable:BAAANQAECggIDQAAAA==.Faegen:BAAANQADCgMJAwAAAA==.Fangytooth:BAAANQADCgYIBgABNQAECgcIEwAGAAAAAA==.Faze:BAAANQAECgUICwAAAA==.',
Fb='Fbitortamilf:BAAANQAECgUIBgAAAA==.',
Fe='Fenlian:BAAANQADCgIIAgAAAA==.Feydoria:BAAANQAECgQIBQAAAA==.',
Fi='Firstfira:BAAANQAECgIIBQAAAA==.',
Fr='Frontman:BAAANQAECgYIEwAAAA==.Frostscythe:BAAANQAECgEIAQAAAA==.',
Fu='Funkycolors:BAAANQADCgYIBgABNQAECgYIFAARAB4WAA==.',
Ga='Gabomonk:BAAANQADCgEIAQABNQAECgIIAgAGAAAAAA==.Gavrael:BAAANQADCgQIBwAAAA==.',
Ge='Genma:BAAANQAECgIIBAAAAA==.Gewch:BAAANQAECgQIBQAAAA==.',
Gi='Gitgudder:BAAANQAECgIIAgAAAA==.',
Gl='Gloçk:BAAANQAECgcIEAAAAA==.',
Go='Goofy:BAAANQAECggIBgAAAA==.',
Gr='Graeae:BAAANQAECgIIAwAAAA==.Grimaldi:BAAANQAECgQICAAAAA==.Grimvaka:BAAANQADCgEIAQAAAA==.Gripforceone:BAAANQAECgMIAgAAAA==.',
Gu='Gunduin:BAABNQAECoEgAAIEAAcKJRgLZAAiAgAEAAcKJRgLZAAiAgAAAA==.',
Gy='Gyda:BAABNQAECoEuAAMJAAkK0BvRHADmAgAJAAkK0BvRHADmAgASAAIKCgxuHABmAAAAAA==.Gyuyuki:BAABNQAECoEdAAIHAAcKAg10ewCBAQAHAAcKAg10ewCBAQAAAA==.',
['Gó']='Gódofwàr:BAAANQAECgIIAgAAAA==.',
Ha='Haggish:BAAANQADCgQIBAAAAA==.Hakeo:BAEBNQAECoEUAAITAAYKSSNvCwBaAgATAAYKSSNvCwBaAgAAAA==.Hanokan:BAAANQADCgIIAgAAAA==.',
He='Heidie:BAAANQAECgEIAgAAAA==.Hemajang:BAAANQAECgEIAgAAAA==.Hermin:BAAANQADCggICAAAAA==.',
Hi='Hikomosil:BAAANQAECgcIEQAAAA==.',
Ho='Holdmybeerz:BAAANQADCgUIBQAAAA==.Homiekissér:BAAANQAECgYICwAAAA==.Hotzz:BAAANQAECgEIAQABNQAECggIFAAFACgWAA==.',
['Hë']='Hëllen:BAAANQADCgIIAgAAAA==.',
['Hú']='Húñtrèss:BAAANQAECgEIAgAAAA==.',
Im='Imakittycat:BAABNQAECoEcAAIUAAcKsR4BFwBkAgAUAAcKsR4BFwBkAgAAAA==.Impared:BAAANQAECgYIBwABNQAECggIDgAGAAAAAA==.',
Iv='Ivey:BAAANQADCggICwAAAA==.',
Ja='Jacenne:BAAANQAECgEIAwAAAA==.',
Je='Jenesis:BAABNQAECoEZAAMMAAkKVBuKPgC0AgAMAAkKVBuKPgC0AgALAAEKHgPrFwEkAAAAAA==.',
Jo='Josephyn:BAAANQAECgcIEgABNQAFFAMIBwAFAEcfAA==.',
Ju='Juggernåut:BAAANQADCgMIAwAAAA==.',
Ka='Kaale:BAAANQAECgEIAQABNQAECgQIDgAGAAAAAA==.Kadaffy:BAAANQAECgEIAQAAAA==.Kahoa:BAAANQAECgQIBAAAAA==.Kakuta:BAABNQAECoEnAAILAAgK4R9/HQDnAgALAAgK4R9/HQDnAgAAAA==.Kakutæ:BAAANQAECgEIAQABNQAECggIJwALAOEfAA==.Kalru:BAAANQADCgQIAQAAAA==.Kalypsso:BAAANQADCgMIAwAAAA==.Kargar:BAAANQAECgEJAgAAAA==.Karot:BAAANQAECgUICAAAAA==.Katharsis:BAABNQAECoEcAAIMAAkKzxORbAAqAgAMAAkKzxORbAAqAgAAAA==.',
Ke='Keit:BAEANQADCgUIBQABNQAFFAMIBgAVADYcAA==.Keévs:BAAANQADCgUIBQAAAA==.',
Kh='Khalidisi:BAABNQAECoEbAAILAAgK3ByxIgDKAgALAAgK3ByxIgDKAgAAAA==.Khalizar:BAAANQADCgUIBQAAAA==.Khanna:BAAANQADCgIIAgAAAA==.Khenja:BAAANQADCgUIBQAAAA==.',
Ki='Killinthyme:BAAANQADCgYIBgAAAA==.',
Kk='Kkiilleerr:BAAANQADCgcIBwAAAA==.',
Ko='Korbulo:BAAANQAECgUIBwAAAA==.Korlothel:BAAANQAECgEIAgABNQAECggIGQAEACkUAA==.',
Kr='Kriptos:BAAANQADCgEIAQABNQADCgEIAQAGAAAAAA==.Kronar:BAAANQADCgYICQAAAA==.Krumpus:BAAANQAECgEIAgAAAA==.Kryma:BAAANQAECgMIAwAAAA==.',
Ku='Kungfuuy:BAAANQAECgEIAQAAAA==.',
Ky='Kylogos:BAAANQAECgEIAQAAAA==.Kynsong:BAABNQAECoEcAAMJAAcKdBCZcgCMAQAJAAcKdBCZcgCMAQASAAEKJAH7LgAHAAAAAA==.Kysia:BAAANQAECgUICgABNQAECgkJHwAMADceAA==.',
['Kî']='Kîrah:BAAANQAECggIDAAAAA==.',
Le='Lerazal:BAAANQAECgQJCAAAAA==.Leshah:BAAANQADCgUIBQAAAA==.',
Li='Liir:BAAANQAECgUIBQAAAA==.Lilbilly:BAAANQAECgEIAwAAAA==.Lildh:BAAANQAECgYIDwAAAA==.',
Lo='Lorastyrell:BAAANQAECgEIAQAAAA==.Loughalnan:BAAANQADCgQIBAABNQAECggIHQAEAJQhAA==.Loìsbethe:BAAANQAECgQIBgAAAA==.',
Lu='Luciferra:BAABNQAECoEmAAIJAAkKvBslGAD/AgAJAAkKvBslGAD/AgABNQAFFAMIBwAFAEcfAA==.Luu:BAAANQAECgIIBAABNQAECgYIDQAGAAAAAA==.',
Ly='Lytho:BAAANQAECgUICAAAAA==.',
Ma='Magelock:BAAANQAECgIIAwABNQAECgQICAAGAAAAAA==.Magickul:BAAANQAECgYIAgABNQAECgQICAAGAAAAAA==.Malakii:BAAANQADCgEIAQAAAA==.Maletsy:BAAANQAECgYIEAABNQAECgcIIAAEACUYAA==.Maliboo:BAAANQAECgYIEgAAAA==.Mandalor:BAAANQADCgEIAQAAAA==.Maxamus:BAABNQAECoEeAAIWAAkKHB9cHQA1AwAWAAkKHB9cHQA1AwAAAA==.',
Mc='Mceuan:BAAANQADCgIIAgAAAA==.',
Me='Medarisa:BAAANQAECgQICgAAAA==.Mederia:BAAANQADCgEIAQAAAA==.Medívh:BAAANQAECgQICAAAAA==.Meelly:BAAANQADCgQIBAAAAA==.Melisandr:BAAANQADCgUIBQAAAA==.Merkenier:BAABNQAECoEVAAIXAAcKjQkdVwBPAQAXAAcKjQkdVwBPAQAAAA==.Merkshamalot:BAAANQAECgEIAwABNQAECgcIFQAXAI0JAA==.Merkur:BAAANQAECgEIAgABNQAECgcIFQAXAI0JAA==.Merkurry:BAAANQAECgEIAwABNQAECgcIFQAXAI0JAA==.',
Mo='Modifiedmix:BAAANQADCgUICwAAAA==.Monatazumaa:BAAANQADCggIDwAAAA==.',
Mu='Mugato:BAAANQABCgEIAQAAAA==.Murdette:BAAANQAECgUIBwABNQAECgkJJgAWABojAA==.',
My='Mystych:BAAANQAECgUIBQAAAA==.',
['Må']='Mågi:BAAANQAECgQICAAAAA==.',
['Mö']='Möôôöõöóòòõô:BAABNQAECoEuAAMLAAgKyRJRUwAAAgALAAgKyRJRUwAAAgAMAAQKhgoVIAGxAAAAAA==.',
Na='Nakednwasted:BAAANQADCgYIBgAAAA==.Nanakii:BAAANQAECgIJAwAAAA==.Nathrold:BAAANQAECgQIBQABNQAECgcIEAAGAAAAAA==.',
Ne='Neptune:BAACNQAFFIEHAAIFAAMKRx86EAAZAQAFAAMKRx86EAAZAQA1AAQKgSoAAgUACQqKIF8WAAMDAAUACQqKIF8WAAMDAAAA.Nerfpaladins:BAAANQAECgUIBgAAAA==.Nerfpriests:BAABNQAECoEXAAIKAAgKyRQGIAAUAgAKAAgKyRQGIAAUAgAAAA==.Nerissl:BAAANQADCgIIAgAAAA==.',
Ni='Niemwa:BAAANQADCgQIBAAAAA==.Nightbird:BAAANQAECgEIAQAAAA==.Nightwingqt:BAAANQAECgYICAAAAA==.Nimrock:BAAANQABCgIIAgAAAA==.',
['Nè']='Nèo:BAAANQADCgYIDAAAAA==.',
Oc='Oculo:BAAANQAECgEIAwAAAA==.',
Od='Odysseus:BAAANQAECgMIAwAAAA==.',
Ok='Oktobra:BAAANQAECgUIDgAAAA==.',
On='Onos:BAAANQADCggJCAAAAA==.',
Or='Orillin:BAABNQAECoEaAAMYAAcKqRv+KgAOAgAYAAcKqRv+KgAOAgAZAAIKbAtnuABYAAAAAA==.Orioan:BAABNQAECoEYAAIMAAgKch/YQwCkAgAMAAgKch/YQwCkAgAAAA==.',
Os='Osun:BAAANQADCggIEAAAAA==.Osÿrus:BAAANQADCgQIBAAAAA==.',
Pa='Padcadaver:BAAANQAECgEIAQAAAA==.Paddy:BAAANQAECgIIBAAAAA==.Padeönwë:BAAANQAECgEIAQAAAA==.Padraig:BAAANQAECgEIAQABNQAECgEIAQAGAAAAAA==.Padspectre:BAAANQAECgEIAQAAAA==.Padtipsy:BAAANQAECgEIAQAAAA==.Padvici:BAAANQAECgEIAQAAAA==.Palantyr:BAABNQAECoE3AAIHAAkKWBPuPABZAgAHAAkKWBPuPABZAgAAAA==.Pallytings:BAAANQADCgQIBAAAAA==.Panurita:BAABNQAECoEUAAIFAAgKKBaWSAAUAgAFAAgKKBaWSAAUAgAAAA==.',
Pe='Pellidillion:BAAANQADCgcICwAAAA==.Pepas:BAAANQAECggICAAAAA==.',
Pi='Picard:BAAANQAECgEIAwAAAA==.',
Po='Polgára:BAAANQAECgIIAgAAAA==.',
Pr='Prepotente:BAAANQADCgUIBQAAAA==.',
Pu='Puppysmacks:BAAANQAECgEIAQAAAA==.Purity:BAAANQAECgMIAwAAAA==.',
Qe='Qevelana:BAAANQADCgMIBAAAAA==.',
Qu='Quetzalcoatl:BAAANQADCgUICQAAAA==.',
Ra='Raambox:BAABNQAECoEWAAIWAAcKEwvHqwCCAQAWAAcKEwvHqwCCAQAAAA==.Raddish:BAAANQAECgUIDwAAAA==.Raedl:BAAANQAECgYIDAAAAA==.Ragriefy:BAAANQADCgUIBQAAAA==.Raiinn:BAAANQADCgEIAQAAAA==.Ramantu:BAAANQADCgIJAgAAAA==.Ramranch:BAAANQAECgQIBgABNQAECggIGAAFANcYAA==.Randay:BAAANQAECggIDgAAAA==.Rathix:BAAANQABCgIIAQAAAA==.Raylee:BAAANQAECgEIAQAAAA==.Razuki:BAAANQAECgQICQAAAA==.',
Re='Reeker:BAAANQAECgEIAQAAAA==.Revenge:BAABNQAECoEkAAIMAAgKHSSZJAAZAwAMAAgKHSSZJAAZAwAAAA==.',
Rh='Rhovanion:BAAANQADCgUIBQABNQAECggIHAAQADoMAA==.Rhuac:BAAANQADCggICgAAAA==.',
Ri='Riddik:BAAANQADCggIDQAAAA==.Rifle:BAAANQAECgEIAQABNQAECggIIQAHADEQAA==.Rika:BAAANQAECgEIAgAAAA==.',
Ro='Robolich:BAAANQAECgcICQAAAA==.Rosefist:BAEANQAECgUIBgAAAA==.Rosemourne:BAEANQADCggICAABNQAECgUIBgAGAAAAAA==.Roshwyn:BAAANQAECgIICgAAAA==.Rottedmeat:BAAANQAECggIDAAAAA==.',
Ru='Rubmytotems:BAAANQAECgUIEQAAAA==.Ruckus:BAABNQAECoEiAAIMAAgKKRhBZwA4AgAMAAgKKRhBZwA4AgAAAA==.',
Rx='Rxmblock:BAAANQAECgEIAgAAAA==.',
Sa='Saelin:BAAANQAECgQIBAABNQAECgQIDgAGAAAAAA==.Sareenastar:BAABNQAECoEZAAIJAAgKUCTUDgA6AwAJAAgKUCTUDgA6AwAAAA==.',
Se='Seafood:BAAANQAECggIDgAAAA==.Sennara:BAAANQAECgQIBAAAAA==.Serenitynow:BAAANQADCgIIAgAAAA==.Sethworgen:BAAANQAECgEIAQAAAA==.',
Sh='Shadowlillee:BAAANQABCgIIAgAAAA==.Shadowmeteor:BAAANQAECgQIBAAAAA==.Shakey:BAAANQAECgEIAQAAAA==.Shalen:BAAANQAECgIIAgAAAA==.Shamrox:BAAANQAECgUICAAAAA==.Sharar:BAAANQAECgUJCQAAAA==.Sharker:BAAANQADCgMIAwAAAA==.Sharkerprest:BAAANQADCgYIBgAAAA==.Sharkerwarlo:BAAANQAECgEJAQAAAA==.Sharpenator:BAAANQAECgEIAQAAAA==.Sheraa:BAAANQAECgIIBAAAAA==.Shieldknight:BAAANQAECgEIAgAAAA==.Shiftystrike:BAAANQAECgQICQAAAA==.Shifushield:BAAANQADCggIEQAAAA==.Shirazormu:BAAANQAECgEIAgABNQAECgUIBQAGAAAAAA==.Shrike:BAAANQADCgIIAwABNQAFFAYIFQAKAJUVAA==.',
Si='Silentwindy:BAAANQADCgYJCQAAAA==.Silmarkthree:BAABNQAECoEdAAIaAAgK+hClqgALAgAaAAgK+hClqgALAgAAAA==.Sinbåd:BAAANQADCggICgAAAA==.',
Sk='Skol:BAABNQAECoEcAAIQAAgKOgwtWABwAQAQAAgKOgwtWABwAQAAAA==.',
Sl='Slipknoth:BAACNQAFFIEPAAMKAAUKFhk3BwB5AQAKAAUKFhk3BwB5AQAJAAEKJwvGLgBGAAA1AAQKgScABAoACQp+IskIAD8DAAoACQp+IskIAD8DAAkAAwoTC0u7ALAAABIAAQrQGQsgAE0AAAAA.',
Sn='Snakeplizken:BAAANQADCggIAQAAAA==.',
So='Sorean:BAACNQAFFIEKAAINAAUKbQ91AADAAQANAAUKbQ91AADAAQA1AAQKgSUAAw0ACQoJH4sCAPECAA0ACQoJH4sCAPECABsAAQpjDS15ADcAAAAA.Sorrel:BAAANQADCggICQAAAA==.',
Sp='Specialmove:BAAANQAECgQIBgAAAA==.',
St='Staghealz:BAAANQAECgEIAwAAAA==.Staldorn:BAAANQADCgIIAgAAAA==.Starlet:BAAANQADCgIIAgAAAA==.Stifs:BAAANQAECgYIEAAAAA==.Stinkinglily:BAAANQABCgQIBwAAAA==.Stonebeard:BAAANQADCggIIQAAAA==.Stormstream:BAAANQADCgMIBgAAAA==.',
Su='Suelustra:BAAANQAECgUICAAAAA==.',
Sy='Sykotyk:BAABNQAECoEfAAIFAAgKEhprPABFAgAFAAgKEhprPABFAgAAAA==.',
Ta='Tadagain:BAAANQAECgUIDgAAAA==.Talix:BAAANQAECgIIAwAAAA==.Tamaira:BAAANQAECgUICwAAAA==.Tankybears:BAAANQAECgQIDgAAAA==.Tart:BAAANQADCgcJHQAAAA==.',
Te='Telekinesis:BAABNQAECoEWAAQbAAcKyxBiQwAKAQAEAAYKnBHDqwB6AQAbAAYK+QZiQwAKAQANAAEKqBCtEQAxAAAAAA==.Tenara:BAABNQAECoEYAAMFAAgKsBmPPABEAgAFAAgKsBmPPABEAgAHAAMKRAsr4ACcAAABNQAECgQIDgAGAAAAAA==.Teos:BAAANQADCgYIBgABNQAECggIHAAQADoMAA==.',
Th='Thalanor:BAAANQABCggIEgAAAA==.Thaliak:BAAANQADCgYIBwABNQAECgQICAAGAAAAAA==.Tharris:BAAANQADCgYIBgAAAA==.Tholin:BAAANQADCggIEwAAAA==.Thunderlily:BAAANQAECgYIDgAAAA==.',
Ti='Tinychaos:BAAANQAECgEIAgAAAA==.Tirra:BAAANQADCggIDgAAAA==.',
Tr='Tracther:BAAANQADCgYIDwAAAA==.Trapps:BAAANQADCgYIDAAAAA==.Treedemon:BAAANQADCgYIBgAAAA==.Treelock:BAAANQAECgcIEgAAAA==.Trelapin:BAAANQADCggIDQAAAA==.',
Tw='Twinrova:BAAANQADCggICAAAAA==.',
Ty='Tyrelitha:BAAANQADCgQIBgAAAA==.',
Uh='Uhtrad:BAAANQAECgcIEwAAAA==.',
Ul='Ulfrir:BAAANQADCgYIBgAAAA==.Ullhr:BAAANQADCgYICwAAAA==.',
Ur='Ursaline:BAAANQAECgEIAQABNQAECgYIBwAGAAAAAA==.',
Va='Valock:BAAANQAECgIIAgAAAA==.Vanshifty:BAABNQAECoEkAAIUAAgKKB9eDgDQAgAUAAgKKB9eDgDQAgAAAA==.',
Ve='Venli:BAAANQADCgQJBAAAAA==.',
Vo='Voidentine:BAAANQABCggIBgAAAA==.',
Vy='Vyx:BAAANQAECgIIBAAAAA==.',
Wa='Waffle:BAAANQAECgYIEAAAAA==.Wardaelos:BAAANQADCgUIBQAAAA==.Wargue:BAAANQAECgUJBgAAAA==.Wasprepared:BAAANQADCgQIBAAAAA==.',
We='Weeaboos:BAAANQADCgQICgAAAA==.Welindis:BAAANQADCgcJBwABNQADCggIFAAGAAAAAA==.Wenus:BAAANQABCgQIAwAAAA==.',
Wh='Whofurmoover:BAAANQAECgQICQAAAA==.',
Wi='Winrodan:BAAANQAECgcIEwABNQAECgYIEwAGAAAAAA==.Wizzard:BAAANQAECgcICwAAAQ==.',
['Wó']='Wóof:BAAANQADCgMIAwAAAA==.',
Xa='Xaandu:BAAANQADCgQIBAAAAA==.Xaris:BAAANQAECgQIDQABNQAECgcIHAAJAHQQAA==.',
Xi='Xiladin:BAAANQAECgEIAgAAAA==.',
Xt='Xtremes:BAAANQADCgcIBwAAAA==.',
['Xí']='Xíe:BAAANQAECgcIEwAAAA==.',
Yi='Yimm:BAAANQADCgEIAQAAAA==.',
['Yø']='Yø:BAAANQADCggIBwAAAA==.',
Za='Zalendria:BAAANQAECgEIAQAAAA==.',
Zb='Zbm:BAAANQAECgIJAgAAAA==.',
Ze='Zealotry:BAAANQAECgEIAQABNQAECgMIAQAGAAAAAA==.Zeldy:BAABNQAECoEaAAIEAAgKUhnHOQCaAgAEAAgKUhnHOQCaAgAAAA==.Zelene:BAAANQAECgEIAQAAAA==.Zenthareal:BAABNQAECoEbAAMcAAcKChQVKgDRAQAcAAcKChQVKgDRAQAVAAEKYwjVgwAzAAAAAA==.Zenzi:BAAANQADCgcIEAAAAA==.',
Zm='Zmaster:BAAANQAECgUIEAAAAA==.',
Zu='Zunarri:BAAANQADCgYJCAAAAA==.',
Zw='Zwar:BAAANQADCgMJAwABNQAECgUIEAAGAAAAAA==.',
Zy='Zyri:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAABNQAECoEnAAIEAAkKPyCuEwA5AwAEAAkKPyCuEwA5AwAAAA==.',
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
