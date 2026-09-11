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

local lookup = {'DeathKnight-Blood','Unknown-Unknown','Shaman-Elemental','Paladin-Holy','Warlock-Demonology','Evoker-Preservation','Warrior-Arms',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aamodar:BAAANQADCggIEwAAAA==.',
Ab='Abadon:BAAANQAECgEIAQAAAA==.',
Ad='Adino:BAAANQAECgIIAgAAAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAAANQAECgMIAgAAAA==.Aeryn:BAAANQAECgcIDgAAAA==.Aerís:BAAANQADCggIDgAAAA==.',
Ag='Agrolazor:BAAANQAECgYICgAAAA==.',
Ah='Ahtee:BAAANQAECgMIBQAAAA==.',
Al='Alara:BAAANQABCgQIBgAAAA==.Alseena:BAAANQAECgMIAwAAAA==.',
An='Anvar:BAAANQAECgYICgAAAA==.',
Ar='Arathion:BAAANQAECgIIAgAAAA==.Arianrhod:BAAANQAECgQIBAAAAA==.Arx:BAAANQAECgcICwAAAA==.',
As='Ashaldrin:BAAANQAECgEIAQAAAA==.Aska:BAAANQABCgMIAwAAAA==.',
At='Atrumdeus:BAAANQAECgYIDQAAAA==.',
Au='Audiamer:BAAANQAECgQIBgAAAA==.',
Ba='Babydragon:BAAANQAECgQICAAAAA==.Babysaja:BAAANQADCgYIDQAAAA==.Bannann:BAAANQAECgIIAgAAAA==.Baojai:BAAANQADCgUIBQABNQAECggIFQABAHEWAA==.',
Be='Beaksbigdk:BAAANQAFFAEIAQAAAA==.Beefÿfridge:BAAANQADCggIDgAAAA==.Belfegor:BAAANQAECgEIAQAAAA==.Belldia:BAAANQAFFAEIAQAAAA==.Belphaegor:BAAANQADCggIFAAAAA==.Beni:BAAANQADCgEIAQAAAA==.Beniaru:BAAANQAECgQIBgAAAA==.',
Bi='Bigmuzz:BAAANQADCgMIAwAAAA==.',
Bl='Blightedmilk:BAAANQADCgUIBwABNQAECgMIAwACAAAAAA==.Bloopmasta:BAAANQADCggICgAAAA==.Blufox:BAAANQAECggICAAAAA==.',
Bo='Bobfresh:BAAANQAECgYIDQAAAA==.Bootwitdafur:BAAANQADCggICAAAAA==.',
Br='Broherum:BAAANQADCgQIBAAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYIBgAAAA==.Busting:BAAANQADCggIEwAAAA==.',
['Bà']='Bàhamut:BAAANQADCgUIBQAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Captchaos:BAAANQADCgEIAQAAAA==.Carritha:BAAANQADCgYICAABNQAECgMIAwACAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAAANQAECgQIBQAAAA==.',
Ch='Chimneybones:BAAANQADCgcICQAAAA==.Chizz:BAAANQAECggIEwAAAA==.Chriswong:BAAANQAECgEIAQAAAA==.Chá:BAAANQADCggICAABNQAECgYICgACAAAAAA==.',
Cl='Clairebenet:BAAANQAECgUICAAAAA==.Clumzylock:BAAANQADCgYICgABNQAECgQIBAACAAAAAA==.Clumzyninja:BAAANQAECgQIBAAAAA==.',
Co='Code:BAAANQADCggICAABNQAECgkJFwADAL4fAA==.Coolbreez:BAAANQADCgYICQAAAA==.Coolynn:BAAANQAECgIIAwAAAA==.Corl:BAAANQADCgEIAQAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.',
Cu='Cumb:BAAANQADCggICAABNQAECgYIDQACAAAAAA==.',
['Cä']='Cäldius:BAAANQADCgMIAwAAAA==.',
Da='Daioh:BAAANQABCgYIDAAAAA==.Damacraze:BAAANQAECgIIAgAAAA==.Danielwu:BAAANQAECgQIBAAAAA==.',
De='Deadroar:BAABNQAECoEVAAIBAAgJcRYcFQA2AgABAAgJcRYcFQA2AgAAAA==.Deadwill:BAAANQAECgQIBwAAAA==.Deaminase:BAAANQAECgUIBQAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAAANQAECgcIDAAAAA==.Deggle:BAAANQADCgIIAgAAAA==.Delphoxx:BAAANQADCggIDgAAAA==.Demidru:BAAANQADCggIEwAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgIIAwACAAAAAA==.Deshojo:BAAANQADCggICAAAAA==.Desrook:BAAANQAECgIIAgAAAA==.',
Dh='Dhqt:BAAANQADCgUIBQABNQADCgYICAACAAAAAA==.',
Do='Double:BAAANQADCggIDwAAAA==.Doublelift:BAAANQAECgYICwAAAA==.',
Dr='Drakisara:BAAANQADCggIBgAAAA==.Drakuul:BAAANQADCgIIAgAAAA==.Droni:BAAANQADCggIEQAAAA==.Dröbi:BAAANQAECggIEwAAAA==.',
Du='Dundundun:BAAANQAECgIIAgAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIBwAAAA==.',
Eg='Egufro:BAAANQAECgEIAQABNQAECggIEAACAAAAAA==.',
Eh='Ehgu:BAAANQAECggIEAAAAA==.',
El='Eleverclear:BAAANQADCgYIBgAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
Er='Erhmer:BAAANQAECgcIAQAAAA==.',
Et='Etom:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.',
Ev='Eviae:BAAANQADCgQIBAAAAA==.',
Fa='Fairyhunter:BAAANQAECgQIBAAAAA==.Fairymonk:BAAANQAECgEIAQAAAA==.Fatfatfat:BAAANQAECgEIAQABNQAECggIFQABAHEWAA==.Fañgrat:BAAANQADCgYICgABNQADCgYICAACAAAAAA==.',
Fe='Femboyluvr:BAAANQADCgcIBwAAAA==.',
Fi='Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flandia:BAAANQAECgIIAgAAAA==.Floppiterry:BAAANQADCgYIBgAAAA==.Flow:BAAANQAECgQIBAAAAA==.',
Fo='Fowl:BAAANQAECgIIAgAAAA==.',
Fr='Fricher:BAAANQAECgIIAgAAAA==.Froznrage:BAAANQAECggIEgAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBAAAAA==.',
Ga='Gagli:BAAANQABCgYIBAAAAA==.Ganjja:BAAANQADCggIEgAAAA==.',
Ge='Geneman:BAAANQABCgIIBAAAAA==.Getsyouwet:BAAANQAECgEIAQABNQAFFAEIAQACAAAAAA==.Getter:BAAANQADCgcIDQAAAA==.',
Gh='Ghettomike:BAAANQADCgQIBAAAAA==.',
Gi='Giny:BAAANQAECgIIAwAAAA==.',
Go='Gobbledeez:BAAANQADCggICAAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Govinniuur:BAAANQADCgcICwAAAA==.',
Gr='Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAAANQAECgYICwAAAA==.Grue:BAAANQADCggICAAAAA==.',
Gy='Gyndrinolara:BAAANQADCggICgAAAA==.',
Ha='Hafadude:BAAANQADCggIBQAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAAANQADCgMIAwAAAA==.',
Ho='Holyflame:BAAANQADCgQIBAAAAA==.Holypewpewz:BAAANQADCggIDgABNQADCggIEQACAAAAAA==.Holyyshift:BAAANQADCggIEQAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.Hunterlizzie:BAEANQAECgUICAAAAA==.',
Hy='Hyperiann:BAAANQADCgQIBAAAAA==.',
Ia='Iamfried:BAAANQAECgQICAAAAA==.',
Ih='Ihatemodels:BAAANQADCgIIAgAAAA==.',
Il='Illidigle:BAAANQADCgYICgAAAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAAANQAECgYICwAAAA==.Inyadraug:BAAANQAECgIIAgAAAA==.',
Ir='Ironheãrt:BAAANQAECgUICAAAAA==.Ironsight:BAAANQADCgcIEwAAAA==.',
Is='Isaacnewton:BAAANQAECgEIAgAAAA==.',
It='Itai:BAAANQAECgYICgAAAA==.',
Iv='Iverson:BAAANQABCgYICgAAAA==.',
Ja='Jackk:BAABNQAECoEZAAIEAAkJjyOSAQChAwAEAAkJjyOSAQChAwAAAA==.Jackks:BAAANQAECgQIBAABNQAECgkJGQAEAI8jAA==.Jaddix:BAAANQADCgYIBwAAAA==.Jasmonk:BAAANQAECgIIAgAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jellysickle:BAAANQADCgcICAAAAA==.',
Ji='Jimmyray:BAAANQABCgUIBQAAAA==.Jinkua:BAAANQAECgEIAQAAAA==.Jinkz:BAAANQADCggIDgAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIAgAAAA==.Jorhel:BAAANQADCggIDgAAAA==.',
Ju='Judgevis:BAAANQAECgEIAgAAAA==.',
['Jø']='Jøshu:BAAANQADCgYIBgAAAA==.',
Ka='Kaeliis:BAAANQADCgUIBgAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Karrona:BAAANQADCgIIAgAAAA==.Kazuu:BAAANQADCgUIBQAAAA==.',
Kb='Kbeckinsale:BAAANQAECgIIAgABNQAECgYICgACAAAAAA==.',
Ke='Keladun:BAAANQADCgUICgAAAA==.',
Kh='Kharga:BAAANQAECgQIBwAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAEIAQACAAAAAA==.',
Ki='Kidgroove:BAAANQADCgEIAQAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Ko='Konamy:BAAANQADCgUIBQAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAAANQAECgMIAwAAAA==.',
Kr='Kriss:BAAANQADCgEIAQAAAA==.Kristeena:BAAANQADCgYICwAAAA==.Kryptonikk:BAAANQADCgYICgAAAA==.Kröw:BAAANQAECgIIAgAAAA==.',
Ku='Kudrix:BAAANQAECgIIAgAAAA==.Kurø:BAAANQADCgIIAgAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQADCgYICgAAAA==.Laurijaydn:BAAANQADCgYICQAAAA==.Laurynn:BAAANQADCggIDQAAAA==.',
Le='Legionremix:BAAANQADCgEIAQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQADCgMIAwAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgcIDQACAAAAAA==.Littlestarz:BAAANQAECgEIAQAAAA==.Lizzieag:BAEANQADCgYICwABNQAECgUICAACAAAAAA==.',
Ll='Llazz:BAAANQADCgUIBQAAAA==.Llemons:BAAANQADCggIFQABNQAECgQIBAACAAAAAA==.',
Lo='Lolblur:BAAANQADCgYIDAAAAA==.Lootah:BAAANQADCggIEgAAAA==.Loranoth:BAAANQADCggIEwAAAA==.Lovecox:BAAANQADCgQIBQAAAA==.',
Lu='Luke:BAAANQAECgQIBAAAAA==.Luminali:BAAANQAECgIIAgAAAA==.Lunadari:BAAANQADCgcICwAAAA==.Lunareva:BAAANQAECgIIAgAAAA==.',
Ly='Lyxon:BAAANQADCggIFQAAAA==.',
['Læ']='Lænna:BAAANQADCgUIBQAAAA==.',
['Lí']='Lílîth:BAAANQAECgEIAQAAAA==.',
Ma='Mafoôza:BAAANQAECgYICgAAAA==.Magicalama:BAAANQAECgYIDQAAAA==.Magnanimity:BAEANQAECgEIAQAAAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAAANQAECgQIBAAAAA==.Makto:BAAANQADCgYIBgAAAA==.Malia:BAAANQADCgcIBwAAAA==.Maliciouso:BAAANQAECgEIAQAAAA==.Malédiction:BAAANQAECgIIAQAAAA==.Mariemaya:BAAANQADCgcIBwAAAA==.Marley:BAAANQAECgIIAgAAAA==.Matua:BAAANQADCgYICwAAAA==.',
Me='Medizine:BAAANQADCgYIDgAAAA==.Megamacdin:BAAANQAECgYICgAAAA==.',
Mi='Miistral:BAAANQAECgEIAQAAAA==.Mimie:BAAANQAECgQIBwAAAA==.Mistyeva:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Mo='Moistooltip:BAAANQAECgYIBgAAAA==.Mokotrize:BAAANQAECgIIAgAAAA==.Moosh:BAAANQAECgIIAgAAAA==.Mordred:BAAANQADCgUIDwAAAA==.Mouthkisser:BAAANQAECgQIAwAAAA==.',
Mu='Mud:BAAANQAECgEIAQAAAA==.Mudslinger:BAAANQADCgQIBAAAAA==.Munchies:BAAANQADCggIEQAAAA==.',
My='Myrolan:BAAANQADCgYIBwABNQADCgcICwACAAAAAA==.',
Na='Nanoko:BAAANQAECgEIAQAAAA==.Naora:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.',
Ne='Neckslice:BAABNQAECoEXAAIDAAkJvh/UBgBKAwADAAkJvh/UBgBKAwAAAA==.Neuro:BAAANQAECgQIBgAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQADCggIFwAAAA==.Nirri:BAAANQADCgYICAAAAA==.Nitefall:BAAANQAECgEIAgAAAA==.',
No='Nocando:BAAANQAECgcIDQAAAA==.Notadk:BAAANQABCgYICgAAAA==.Noturbudpal:BAAANQADCgIIAgABNQAECgQIBAACAAAAAA==.',
Nu='Nuriel:BAAANQADCgQIBAAAAA==.',
Ob='Obsydia:BAAANQADCgcIBwAAAA==.',
Ol='Oline:BAABNQAECoESAAIFAAkJOB9IAgBdAwAFAAkJOB9IAgBdAwAAAA==.',
Oo='Oonaki:BAAANQAECgUIBQAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAAANQADCggIEgAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgMIAwAAAA==.Paradoxx:BAAANQAECgYIBgAAAA==.',
Ph='Phelefica:BAAANQAECgMIAwAAAA==.Phreyja:BAAANQADCgIIAgAAAA==.Phylgon:BAAANQADCggIEQAAAA==.',
Po='Pointybrows:BAAANQADCgYIBwAAAA==.',
Py='Pyràbànks:BAAANQADCgYIBgAAAA==.',
Qu='Quelestraza:BAAANQADCggIFAAAAA==.Quikkmex:BAAANQAECgMIAwAAAA==.',
Ra='Raewyck:BAAANQAECgEIAQAAAA==.Ragingmaze:BAAANQAECgYICAAAAA==.Rainburrow:BAAANQADCggIEwAAAA==.Raptormortis:BAAANQADCgUIBQAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Restingbface:BAAANQADCggICAAAAA==.Resurrection:BAAANQADCgUIBQAAAA==.Retana:BAAANQAECggIDgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAAANQADCggIEwAAAA==.',
Ri='Rickypeepee:BAAANQADCggICAAAAA==.Rider:BAAANQABCgIIBAAAAA==.',
Ro='Roastedz:BAAANQADCgQIBAAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQADCgYICAAAAA==.',
Ry='Ryanna:BAAANQADCggIDgAAAA==.',
Sa='Saevio:BAAANQADCggIEQAAAA==.Salvader:BAAANQAECgIIAgAAAA==.Sashimi:BAAANQAECgEIAQAAAA==.',
Sc='Scarllett:BAAANQAECgQIBwAAAA==.',
Se='Serenade:BAAANQADCgIIAgAAAA==.Seviana:BAAANQADCggICAAAAA==.Sevie:BAABNQAECoEYAAIGAAkJCiSxAACpAwAGAAkJCiSxAACpAwAAAA==.',
Sh='Shabbyy:BAAANQADCgUICwABNQAECgMIAwACAAAAAA==.Shadowpump:BAAANQAECgQIBwAAAA==.Shamsel:BAAANQADCggIEQAAAA==.Shellack:BAAANQABCgIIAgAAAA==.Shinnz:BAAANQAECgUIBQAAAA==.Shockcaller:BAAANQAECgMIAwAAAA==.Shockingnut:BAAANQAECgUIBwAAAA==.Showtooltip:BAAANQADCgcIBwABNQAECgYIBgACAAAAAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAAANQADCgYIBgABNQADCgYICAACAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAAANQADCgcIBwAAAA==.Simmara:BAAANQAECgMIAwAAAA==.',
Sk='Skylinelol:BAAANQAECgYIBgAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIAQACAAAAAA==.',
Sm='Smallcurse:BAAANQADCgYIBgAAAA==.Smallighting:BAAANQAECgUIDAAAAA==.',
So='Solanthis:BAAANQAECgEIAQAAAA==.Solstica:BAAANQADCgYIDwAAAA==.',
Sp='Spiritualone:BAAANQADCggIEwAAAA==.',
Sq='Sqwaat:BAAANQADCgEIAQAAAA==.',
St='Steelrib:BAAANQADCggIEwAAAA==.Stonystark:BAAANQADCgYIDAAAAA==.Straam:BAAANQAECgcIDwAAAA==.Strizzle:BAEANQAECgQIBQAAAA==.Støney:BAAANQADCggIDQAAAA==.',
Su='Subatronic:BAAANQAFFAIIAgAAAA==.Subfractal:BAAANQADCgYIBgABNQAFFAIIAgACAAAAAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAAANQAECgEIAQAAAA==.Takki:BAAANQAECgIIAgAAAA==.Tamsîn:BAAANQAECgcIDQAAAA==.',
Te='Teinuya:BAAANQAECgMIAwAAAA==.Tenochitilan:BAAANQAECgEIAQAAAA==.',
Th='Thorimeir:BAAANQADCgIIAgAAAA==.Thraxacious:BAAANQAECgQIBwAAAA==.Thulsadoomm:BAAANQADCgUIBAAAAA==.',
Ti='Tiduss:BAAANQADCgYIDAAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAAANQADCggIEwAAAA==.Tinkerbel:BAAANQAECgYIBwAAAA==.Tinkerbella:BAAANQAECgEIAQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAEIAQACAAAAAA==.Tireliaa:BAAANQADCgUIBgAAAA==.',
To='Tohsaka:BAAANQADCgIIAgAAAA==.Torsin:BAAANQADCgIIAgAAAA==.',
Tr='Trafalgour:BAAANQAECgEIAQAAAA==.Trazen:BAAANQADCgQIBwAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAAANQAECgIIAgAAAA==.',
Tu='Tundal:BAAANQAECgMIAwAAAA==.',
Ty='Tyylerdurden:BAAANQABCgIIAgAAAA==.',
Ud='Uddertrouble:BAEANQAECgEIAQABNQAECgEIAQACAAAAAA==.',
Un='Unholytiran:BAAANQADCgYIDAAAAA==.',
Ur='Urmada:BAAANQAECgIIAgAAAA==.Urmami:BAAANQAECgIIAgAAAA==.',
Va='Valyne:BAAANQADCgYIDAAAAA==.Vampire:BAAANQAECgEIAQAAAA==.Vampyre:BAAANQAECggIEwAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Vargmal:BAAANQADCgYIBQAAAA==.',
Vi='Virala:BAAANQADCgYICAAAAQ==.Visenya:BAAANQADCgEIAQAAAA==.Vitamin:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.Vitaminn:BAAANQAECgEIAQAAAA==.',
Vl='Vlaen:BAAANQADCggICAAAAA==.',
Vo='Votum:BAAANQADCggIFgAAAA==.',
Vy='Vyrisa:BAAANQADCgYICQAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Wasabii:BAAANQADCgcIBwAAAA==.',
Wh='White:BAAANQADCggICAABNQAECgkJFwADAL4fAA==.',
Wi='Wilbertorc:BAAANQADCgEIAQAAAA==.Wildwolff:BAAANQADCgUIBQAAAA==.Wilhedin:BAAANQAECgcIDgAAAA==.',
Wo='Worm:BAABNQAECoEXAAIHAAkJ4BsjFQDfAgAHAAkJ4BsjFQDfAgAAAA==.',
Wu='Wulfnbolt:BAAANQAECgIIAgAAAA==.',
Wy='Wyon:BAAANQADCggIEAAAAQ==.',
Ya='Yasnah:BAAANQADCgcIBwAAAA==.',
Yu='Yunahpabo:BAAANQAECgcIDAAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQADCgMIAwAAAA==.Zathara:BAAANQAECgYICwAAAA==.',
Zo='Zodiac:BAAANQAECgIIAgAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQADCgMIAwAAAA==.Zuluk:BAAANQAECgQIBAAAAA==.',
['Zö']='Zörö:BAAANQAECgUICQAAAA==.',
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
