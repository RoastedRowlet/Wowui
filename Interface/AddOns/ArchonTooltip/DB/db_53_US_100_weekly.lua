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

local lookup = {'Paladin-Retribution','DeathKnight-Blood','Hunter-BeastMastery','Unknown-Unknown','Shaman-Elemental','Mage-Arcane','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Warlock-Demonology','Evoker-Preservation','Shaman-Restoration','Warlock-Affliction','Warrior-Arms',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aamodar:BAAANQAECgIIAgAAAA==.',
Ab='Abadon:BAAANQAECgYIBwAAAA==.',
Ad='Adino:BAAANQAECgMIBAAAAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAAANQAECgIIBAAAAA==.Aeryn:BAABNQAECoEZAAIBAAgJJh4qKAB0AgABAAgJJh4qKAB0AgAAAA==.Aerís:BAAANQADCggIDgAAAA==.',
Ag='Agrolazor:BAAANQAECgYIEAAAAA==.',
Ah='Ahtee:BAAANQAECgMIBgAAAA==.',
Al='Alara:BAAANQABCgQIBgAAAA==.Alseena:BAAANQAECgMIAwAAAA==.',
An='Anaru:BAAANQADCgMIAwAAAA==.Anvar:BAAANQAECgcIEQAAAA==.',
Ar='Arathion:BAAANQAECgMIBAAAAA==.Arcanemommy:BAAANQAECgEIAQAAAA==.Arianrhod:BAAANQAECgUIBwAAAA==.Arx:BAAANQAECgcIDgAAAA==.',
As='Ashaldrin:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgEIAQAAAA==.',
At='Atrumdeus:BAABNQAECoEZAAIBAAcJzxdaQQD0AQABAAcJzxdaQQD0AQAAAA==.',
Au='Audiamer:BAAANQAECgQIBwAAAA==.Aufsela:BAAANQADCgYIBgAAAA==.',
Ba='Babydragon:BAAANQAECgYIDgAAAA==.Bangerz:BAAANQADCgcIBwAAAA==.Bannann:BAAANQAECgQIBgAAAA==.Baojai:BAAANQADCgUIBQABNQAECggIFQACAHEWAA==.',
Be='Beaksbigdk:BAAANQAFFAEIAQAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgQIBQAAAA==.Belldia:BAABNQAECoEYAAIDAAkJoRakFgDEAgADAAkJoRakFgDEAgAAAA==.Belphaegor:BAAANQAECgMIAwAAAA==.Beni:BAAANQADCgEIAQAAAA==.Beniaru:BAAANQAECgQICAAAAA==.Bennyflipz:BAAANQADCgQIBAAAAA==.',
Bi='Bigmuzz:BAAANQADCgUIBwAAAA==.',
Bl='Blightedmilk:BAAANQADCgUIBwABNQAECgYICQAEAAAAAA==.Bloopmasta:BAAANQADCggICgAAAA==.Blufox:BAAANQAECggICQAAAA==.',
Bo='Bobfresh:BAABNQAECoEWAAIFAAkJiR5hDAAyAwAFAAkJiR5hDAAyAwAAAA==.Bootwitdafur:BAAANQADCggICAAAAA==.',
Br='Broherum:BAAANQADCgQIBAAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYICwAAAA==.Busting:BAAANQAECggICAAAAA==.',
['Bà']='Bàhamut:BAAANQADCgUIBQAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Captchaos:BAAANQADCgYIBQAAAA==.Carritha:BAAANQADCgYICAABNQAECgMIBgAEAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAAANQAECgYIDAAAAA==.',
Ch='Chimneybones:BAAANQAECgQIBAAAAA==.Chizz:BAABNQAECoEZAAIGAAkJAgxqZAAaAgAGAAkJAgxqZAAaAgAAAA==.Chriswong:BAAANQAECgEIAQAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chá:BAAANQADCggIEAABNQAECgcIEQAEAAAAAA==.',
Cl='Clairebenet:BAAANQAECgYIDgAAAA==.Clumzylock:BAAANQAECgIIAgABNQAECgYIEAAEAAAAAA==.Clumzyninja:BAAANQAECgYIEAAAAA==.',
Co='Code:BAAANQADCggICAABNQAECgkJFwAFAL4fAA==.Coolbreez:BAAANQADCgYICQAAAA==.Coolynn:BAAANQAECgMIBQAAAA==.Corl:BAAANQADCgEIAQAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Crew:BAAANQADCggICgAAAA==.',
Cu='Cumb:BAAANQADCggICgABNQAECgkJFgAFAIkeAA==.',
['Cä']='Cäldius:BAAANQADCgMIAwAAAA==.',
Da='Daioh:BAAANQADCgYIBgAAAA==.Damacraze:BAAANQAECgQIBgAAAA==.Danielwu:BAAANQAECgQIBAAAAA==.Dawigrund:BAAANQAECgIIAgAAAA==.',
De='Deadroar:BAABNQAECoEVAAICAAgJcRZuIQAQAgACAAgJcRZuIQAQAgAAAA==.Deadwill:BAAANQAECgQICQAAAA==.Deaminase:BAAANQAECgUIBQAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAAANQAECgcIEwAAAA==.Deggle:BAAANQADCgIIAgAAAA==.Delphoxx:BAAANQADCggIFAAAAA==.Demidru:BAAANQAECgIIAgAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMIBQAEAAAAAA==.Deshojo:BAAANQADCggICAAAAA==.Desrook:BAAANQAECgIIAgAAAA==.',
Dh='Dhqt:BAAANQADCgcIDAABNQADCgcICQAEAAAAAA==.',
Di='Divinèhero:BAAANQADCgYIBgAAAA==.',
Do='Doomgirl:BAAANQADCggICAAAAA==.Double:BAAANQAECgIIAgAAAA==.Doublelift:BAAANQAECgcIEgAAAA==.',
Dr='Dragondeznut:BAAANQADCggICgAAAA==.Drakisara:BAAANQADCggIBgAAAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAAANQAECgMIAwAAAA==.Dröbi:BAABNQAECoEaAAIHAAkJOh4HBAAgAwAHAAkJOh4HBAAgAwAAAA==.',
Du='Dundundun:BAAANQAECgQIBQAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
Eg='Egufro:BAAANQAECgEIAQABNQAECgkJGAAIAOcOAA==.',
Eh='Ehgu:BAABNQAECoEYAAIIAAkJ5w5hBwCGAgAIAAkJ5w5hBwCGAgAAAA==.',
El='Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAAANQADCggICAAAAA==.',
Em='Emidget:BAAANQADCgYIBgAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMIBgAEAAAAAA==.',
Er='Erhmer:BAAANQAECggIAQAAAA==.',
Et='Etom:BAAANQAECggIAQAAAA==.',
Ev='Eviae:BAAANQADCgQIBAAAAA==.',
Fa='Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgMIBAAAAA==.Fatfatfat:BAAANQAECgEIAQABNQAECggIFQACAHEWAA==.Fañgrat:BAAANQADCggIDQABNQADCgcICQAEAAAAAA==.',
Fe='Femboyluvr:BAAANQADCgcIDQAAAA==.',
Fi='Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flandia:BAAANQAECgMIBAAAAA==.Floppiterry:BAAANQAECgQIBAAAAA==.Floppyterry:BAAANQADCgUIBQAAAA==.Flow:BAAANQAECgUICQAAAA==.',
Fo='Fowl:BAAANQAECgUIBwAAAA==.',
Fr='Fricher:BAAANQAECgMIBAAAAA==.Froznrage:BAABNQAECoEcAAIIAAkJsxckBQDWAgAIAAkJsxckBQDWAgAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBAAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQABCgYIBgAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.',
Ge='Geneman:BAAANQABCgYICgAAAA==.Getsyouwet:BAAANQAECgEIAQABNQAFFAEIAQAEAAAAAA==.Getter:BAAANQADCggIFQAAAA==.',
Gh='Ghettomike:BAAANQADCgQIBAAAAA==.',
Gi='Giny:BAAANQAECgMIBQAAAA==.',
Go='Gobbledeez:BAAANQAECgUIBQAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Govinniuur:BAAANQAECgIIAgAAAA==.',
Gr='Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAAANQAECgYICwAAAA==.Grue:BAAANQADCggIEAAAAA==.',
Gw='Gwendilyn:BAAANQADCggICAAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMIAwAAAA==.',
Ha='Hafadude:BAAANQADCggIBQAAAA==.Hahgottum:BAAANQAECgQIAgAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAAANQAECgIIAgAAAA==.',
Ho='Holyflame:BAAANQADCgQIBAAAAA==.Holypewpewz:BAAANQAECgEIAQAAAA==.Holyyshift:BAAANQADCggIGQABNQAECgEIAQAEAAAAAA==.Horhel:BAAANQADCgYIBgABNQADCggIBgAEAAAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.',
Hy='Hyperiann:BAAANQADCgQIBAAAAA==.',
Ia='Iamfried:BAAANQAECgYIDgAAAA==.',
Ih='Ihatemodels:BAAANQADCgIIAgAAAA==.',
Il='Illidigle:BAAANQADCggIDAAAAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAAANQAECgcIEAAAAA==.Innarius:BAAANQADCgMIAwAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAAANQAECgMIBQAAAA==.',
Ir='Ironheãrt:BAAANQAECgYIDgAAAA==.Ironsight:BAAANQAECgMIAwAAAA==.Irontaco:BAAANQAECgMIAwAAAA==.Irsa:BAAANQAECggIBwAAAA==.',
Is='Isaacnewton:BAAANQAECgEIAgAAAA==.',
It='Itai:BAAANQAECgcIEQAAAA==.',
Iv='Iverson:BAAANQABCgYICgAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECgYIDAAEAAAAAA==.',
Ja='Jackk:BAACNQAFFIEIAAIJAAUJ6BWMAgC4AQAJAAUJ6BWMAgC4AQA1AAQKgR4AAwkACQkUJI8CAJ8DAAkACQkUJI8CAJ8DAAEAAgllCZDMAF0AAAAA.Jackks:BAAANQAECgQIBQABNQAFFAUICAAJAOgVAA==.Jaddix:BAAANQADCgYIBwAAAA==.Jasmonk:BAAANQAECgMIBAAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.',
Ji='Jimmyray:BAAANQABCgYIBgAAAA==.Jinkua:BAAANQAECgEIAQABNQAECggIAQAEAAAAAA==.Jinkz:BAAANQADCggIFgAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIAgAAAA==.Jorhel:BAAANQADCggIDgAAAA==.',
Ju='Judgevis:BAAANQAECgQIBgAAAA==.Jumbles:BAAANQADCggICAAAAA==.',
Jy='Jynxy:BAAANQADCgUIBQAAAA==.',
['Jø']='Jøshu:BAAANQADCgYIBgAAAA==.',
Ka='Kaeliis:BAAANQAECgEIAQAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Karrona:BAAANQADCgcIBgAAAA==.Kazuu:BAAANQADCgYICwAAAA==.',
Kb='Kbeckinsale:BAAANQAECgMIBAABNQAECgYIEAAEAAAAAA==.',
Ke='Keladun:BAAANQADCgUIDgAAAA==.',
Kh='Kharga:BAAANQAECgQICgAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAMIBAAEAAAAAA==.',
Ki='Kidgroove:BAAANQADCgEIAQAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Ko='Konamy:BAAANQAECgIIAgAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAAANQAECgUICAAAAA==.',
Kr='Kriss:BAAANQADCgEIAQAAAA==.Kristeena:BAAANQADCggIEAAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAAANQADCgYIDwAAAA==.Kröw:BAAANQAECgUIBwAAAA==.',
Ku='Kudrix:BAAANQAECgMIBQAAAA==.Kurø:BAAANQADCgcICQAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgIIAgAAAA==.Laurijaydn:BAAANQADCggIDQAAAA==.Laurynn:BAAANQADCggIDQAAAA==.',
Le='Legionremix:BAAANQADCgEIAQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQADCgMIAwAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgcIEwAEAAAAAA==.Littlestarz:BAAANQAECgMIAwAAAA==.Lizzieag:BAEANQADCgYICwABNQAECgYIEAAEAAAAAA==.',
Ll='Llazz:BAAANQADCgUIBQAAAA==.Llemons:BAAANQADCggIFQABNQAECgQIBgAEAAAAAA==.',
Lo='Locknlizzie:BAEANQAECgYIEAAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggIGwAAAA==.Lovecox:BAAANQADCgUICgAAAA==.',
Lu='Luke:BAAANQAECgQIBAAAAA==.Luminali:BAAANQAECgQIBAAAAA==.Lunadari:BAAANQAECgIIAwAAAA==.Lunareva:BAAANQAECgMIBAAAAA==.',
Ly='Lyxon:BAAANQADCggIFQAAAA==.',
['Læ']='Lænna:BAAANQADCgUIBQAAAA==.',
['Lí']='Lílîth:BAAANQAECgEIAQAAAA==.',
Ma='Maeltne:BAAANQADCgYIBgAAAA==.Mafoôza:BAAANQAECgcICwAAAA==.Magicalama:BAABNQAECoEXAAIGAAgJ5RPfWgA4AgAGAAgJ5RPfWgA4AgAAAA==.Magnanimity:BAEANQAECgEIAQABNQAECgQIBQAEAAAAAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAAANQAECgQIBgAAAA==.Makto:BAAANQADCgYICAAAAA==.Malia:BAAANQADCggIDwAAAA==.Maliciouso:BAAANQAECgcICAAAAA==.Malédiction:BAAANQAECgEIAQAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Mariemaya:BAAANQADCgcIBwAAAA==.Marley:BAAANQAECgQIBgAAAA==.Matua:BAAANQADCgYICwAAAA==.Maximillian:BAAANQAECgIIAgAAAA==.',
Me='Megamacdin:BAAANQAECgYIDAAAAA==.Mendietta:BAAANQADCgUIBQAAAA==.',
Mi='Miistral:BAAANQAECgIIAwAAAA==.Mimie:BAAANQAECgQICwAAAA==.Mistyeva:BAAANQAECgEIAQABNQAECgMIBAAEAAAAAA==.',
Mo='Moistooltip:BAAANQAECggIDgAAAA==.Mokotrize:BAAANQAECgMIBAAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAAANQAECgQIBQAAAA==.Mordred:BAAANQADCgYIFQAAAA==.Mouthkisser:BAAANQAECgQIAwAAAA==.',
Mu='Mud:BAAANQAECgEIAQAAAA==.Mudslinger:BAAANQADCgQIBAAAAA==.Munchies:BAAANQADCggIEwAAAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwAEAAAAAA==.Myrrha:BAAANQADCggICAAAAA==.',
Na='Nanoko:BAAANQAECgEIAQAAAA==.Naora:BAAANQAECgEIAQABNQAECgQICwAEAAAAAA==.',
Ne='Neckslice:BAABNQAECoEXAAIFAAkJvh8nDQAoAwAFAAkJvh8nDQAoAwAAAA==.Nemophilist:BAAANQABCgIIAgAAAA==.Neuro:BAAANQAECgYIDAAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQADCggIFwAAAA==.Nightnite:BAAANQADCgYIDgAAAA==.Nirri:BAAANQADCggIEAAAAA==.Nitefall:BAAANQAECgMIBQAAAA==.',
No='Nocando:BAAANQAECgcIEwAAAA==.Notadk:BAAANQABCgYICgAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECgYIEAAEAAAAAA==.',
Nu='Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obsydia:BAAANQADCgcIBwAAAA==.',
Ol='Oline:BAABNQAECoEVAAIKAAkJsyIvBABqAwAKAAkJsyIvBABqAwAAAA==.',
Oo='Oonaki:BAAANQAECgYICwAAAA==.',
Or='Orchideva:BAAANQADCgcIBwABNQAECgMIBAAEAAAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAAANQADCggIEgAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAAANQAECgYIDAAAAA==.',
Ph='Phelefica:BAAANQAECgMIAwAAAA==.Phreyja:BAAANQADCgYICAAAAA==.Phylgon:BAAANQAECgQIBwAAAA==.',
Po='Pointybrows:BAAANQADCgcIDgAAAA==.',
Pu='Putrescence:BAAANQADCggICAAAAA==.',
Py='Pyràbànks:BAAANQADCgYIBgAAAA==.',
Qu='Quelestraza:BAAANQAECgMIAwAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Raewyck:BAAANQAECgEIAgAAAA==.Raginbull:BAAANQAECgYIBgAAAA==.Ragingmaze:BAAANQAECgYIDgAAAA==.Rainburrow:BAAANQADCggIEwAAAA==.Raptormortis:BAAANQADCgYICwAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Restingbface:BAAANQADCggICAAAAA==.Resurrection:BAAANQADCgYICQAAAA==.Retana:BAABNQAECoEWAAIBAAgJXBaVNAAxAgABAAgJXBaVNAAxAgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAAANQAECgIIAgAAAA==.',
Ri='Rickypeepee:BAAANQAECgUIBQAAAA==.Rider:BAAANQABCgIIBAAAAA==.Rigatoni:BAAANQABCgYIBQAAAA==.',
Ro='Roastedz:BAAANQADCgcICwAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQADCgYIDgAAAA==.Rorthu:BAAANQADCggICAAAAA==.',
Ru='Rukélie:BAAANQADCggICAAAAA==.',
Ry='Ry:BAAANQAECgYIBAABNQAECgYIBAAEAAAAAA==.Ryanna:BAAANQADCggIFgAAAA==.',
Sa='Saevio:BAAANQAECgMIAwAAAA==.Sajin:BAAANQAECgMIAwAAAA==.Salvader:BAAANQAECgIIAwAAAA==.Sashimi:BAAANQAECgQIBQAAAA==.',
Sc='Scarlet:BAAANQADCgcIBwAAAA==.Scarllett:BAAANQAECgQIBwAAAA==.',
Se='Selfward:BAAANQAECgEIAQAAAA==.Serenade:BAAANQADCgcICQAAAA==.Seviana:BAAANQAECgMIBQAAAA==.Sevie:BAACNQAFFIEIAAILAAMJGiR/BABEAQALAAMJGiR/BABEAQA1AAQKgSAAAgsACQlqJaAAAMADAAsACQlqJaAAAMADAAAA.',
Sh='Shabbyy:BAAANQADCgUICwABNQAECgQIBwAEAAAAAA==.Shadowpump:BAAANQAECgQICwAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAAANQADCggIEQAAAA==.Shellack:BAAANQABCgIIAgAAAA==.Shinnz:BAAANQAECgYICwAAAA==.Shockcaller:BAAANQAECgQIBwAAAA==.Shockingnut:BAAANQAECgUICQAAAA==.Showtooltip:BAAANQADCgcIBwABNQAECggIDgAEAAAAAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAAANQADCggICQABNQADCgcICQAEAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAAANQAECgIIAwAAAA==.Simmara:BAAANQAECgMIBgAAAA==.Sip:BAAANQADCggICAAAAA==.',
Sk='Skipper:BAAANQABCgYIBgAAAA==.Skylinelol:BAAANQAECgcIBwAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIAgAEAAAAAA==.',
Sm='Smallcurse:BAAANQADCgYIBgAAAA==.Smallighting:BAAANQAECgQIDgAAAA==.',
So='Solanthis:BAAANQAECgEIAQAAAA==.Solstica:BAAANQAECgEIAQAAAA==.',
Sp='Spiritualone:BAAANQAECgMIAwAAAA==.',
Sq='Sqwaat:BAAANQAECgEIAQAAAA==.',
St='Steelrib:BAAANQAECgIIAgAAAA==.Stonystark:BAAANQADCgYIDAAAAA==.Straam:BAABNQAECoEbAAMMAAkJERaRGACSAgAMAAkJERaRGACSAgAFAAEJMA49ugAzAAAAAA==.Strizzle:BAEANQAECgUICgAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQADCggIFQAAAA==.',
Su='Subatronic:BAACNQAFFIEHAAICAAUJLyHFAQDtAQACAAUJLyHFAQDtAQA1AAQKgR8AAgIACQnKJjwAAAIEAAIACQnKJjwAAAIEAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAUIBwACAC8hAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAAANQAECgEIAQAAAA==.Syrothea:BAAANQADCgUIBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAAANQAECgMIAwAAAA==.Takki:BAAANQAECgQIAgAAAA==.Talethia:BAAANQADCgYIBgAAAA==.Tamsîn:BAABNQAECoEYAAINAAgJvxTAAgA+AgANAAgJvxTAAgA+AgAAAA==.',
Te='Teinuya:BAAANQAECgYICQAAAA==.Tenderfiddle:BAAANQADCgEIAQAAAA==.Tenochitilan:BAAANQAECgIIAgAAAA==.',
Th='Theocracy:BAAANQAECgIIAgAAAA==.Thoorz:BAAANQADCggIDQAAAA==.Thorimeir:BAAANQADCgIIAgAAAA==.Thraxacious:BAAANQAECgYIDQAAAA==.Thulsadoomm:BAAANQADCgYICgAAAA==.Thundermay:BAAANQADCgYIBgAAAA==.',
Ti='Tiduss:BAAANQADCgYIEwAAAA==.Tigó:BAAANQAECgQIAgAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAAANQAECgIIAgAAAA==.Tinkerbel:BAAANQAECgYIBwAAAA==.Tinkerbella:BAAANQAECgEIAQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAECgkJGAADAKEWAA==.Tireliaa:BAAANQADCgUIBgAAAA==.',
To='Tohsaka:BAAANQADCgIIAgAAAA==.Torsin:BAAANQADCgIIAgAAAA==.',
Tr='Trafalgour:BAAANQAECgEIAQAAAA==.Trazen:BAAANQADCgQIBwAAAA==.Try:BAAANQAECgYIBAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAAANQAECgMIBAAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tyylerdurden:BAAANQABCgIIAgAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgQIBQAEAAAAAA==.Uddertrouble:BAEANQAECgQIBQAAAA==.',
Un='Unholytiran:BAAANQADCgcIEwAAAA==.',
Ur='Urmada:BAAANQAECgMIBAAAAA==.Urmami:BAAANQAECgMIBAAAAA==.',
Uz='Uzui:BAAANQAECgIIAgAAAA==.',
Va='Valyne:BAAANQADCgYIEgAAAA==.Vampire:BAAANQAECgYIBwAAAA==.Vampyre:BAAANQAECggIEwAAAA==.Vanadie:BAAANQADCgcIBwAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Vargmal:BAAANQADCgYIBQAAAA==.',
Vi='Virala:BAAANQADCgcICQAAAQ==.Visenya:BAAANQADCgEIAQAAAA==.Vitamin:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.Vitaminn:BAAANQAECgEIAQAAAA==.',
Vl='Vlaen:BAAANQADCggICAAAAA==.',
Vo='Voodoojones:BAAANQAECgIIAgAAAA==.Votum:BAAANQADCggIFgAAAA==.',
Vy='Vyrisa:BAAANQADCgYICQAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Wasabii:BAAANQADCggIDQAAAA==.',
Wh='White:BAAANQADCggICAABNQAECgkJFwAFAL4fAA==.',
Wi='Wildwolff:BAAANQADCgUIBQAAAA==.Wilhedin:BAAANQAECgcIEwAAAA==.',
Wo='Wolfblade:BAAANQADCgIIAgAAAA==.Worm:BAABNQAECoEfAAIOAAkJWRxMGwDzAgAOAAkJWRxMGwDzAgAAAA==.',
Wu='Wulfnbolt:BAAANQAECgUICAAAAA==.',
Wy='Wyon:BAAANQAECgIIAgAAAQ==.',
Ya='Yasnah:BAAANQADCggIDgAAAA==.',
Yu='Yunahpabo:BAAANQAECgcIEAAAAA==.Yurna:BAAANQADCgMIAgAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQADCgMIAwAAAA==.Zathara:BAAANQAECgcIEgAAAA==.',
Zo='Zodiac:BAAANQAECgMIBAAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQADCgMIAwAAAA==.Zuluk:BAAANQAECgQICAAAAA==.',
['Zö']='Zörö:BAAANQAECgUIDwAAAA==.',
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
