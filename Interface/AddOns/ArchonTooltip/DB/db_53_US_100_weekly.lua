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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aamodar:BAAANQADCgYICwAAAA==.',
Ad='Adino:BAAANQADCggICAAAAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAAANQADCggIDwAAAA==.Aeryn:BAAANQAECgUIBwAAAA==.Aerís:BAAANQADCgYIBgAAAA==.',
Ag='Agrolazor:BAAANQAECgQIBAAAAA==.',
Ah='Ahtee:BAAANQAECgIIAwAAAA==.',
Al='Alara:BAAANQABCgMIAwAAAA==.Alseena:BAAANQADCgYIBwAAAA==.',
An='Anvar:BAAANQAECgQIBAAAAA==.',
Ar='Arathion:BAAANQADCggICwAAAA==.Arianrhod:BAAANQADCgYIBgAAAA==.Arx:BAAANQAECgIIAgAAAA==.',
As='Ashaldrin:BAAANQADCgYIBgAAAA==.',
At='Atrumdeus:BAAANQAECgQIBgAAAA==.',
Au='Audiamer:BAAANQAECgIIAgAAAA==.',
Ba='Babydragon:BAAANQAECgQIBAAAAA==.Babysaja:BAAANQADCgUIBwAAAA==.Bannann:BAAANQADCgcIDQAAAA==.',
Be='Beaksbigdk:BAAANQAECgcICgAAAA==.Beefÿfridge:BAAANQADCgYIBgAAAA==.Belfegor:BAAANQADCgcICgAAAA==.Belldia:BAAANQAECgYIBgAAAA==.Belphaegor:BAAANQADCggIDAAAAA==.Beni:BAAANQADCgEIAQAAAA==.Beniaru:BAAANQAECgIIAgAAAA==.',
Bi='Bigmuzz:BAAANQADCgMIAwAAAA==.',
Bl='Blightedmilk:BAAANQADCgUIBwABNQAECgMIAwABAAAAAA==.Bloopmasta:BAAANQADCggIBAAAAA==.Blufox:BAAANQAECggICAAAAA==.',
Bo='Bobfresh:BAAANQAECgQIBgAAAA==.Bootwitdafur:BAAANQADCggICAAAAA==.',
Br='Broherum:BAAANQABCgQIBgAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYIBQAAAA==.Busting:BAAANQADCggIDAAAAA==.',
Ca='Captchaos:BAAANQABCgIIAgAAAA==.Carritha:BAAANQADCgYICAABNQAECgMIAwABAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAAANQAECgEIAQAAAA==.',
Ch='Chimneybones:BAAANQADCgcICQAAAA==.Chizz:BAAANQAECgcICwAAAA==.Chriswong:BAAANQADCgMIAwAAAA==.',
Cl='Clairebenet:BAAANQAECgMIAwAAAA==.Clumzylock:BAAANQADCgQIBAABNQADCggIHAABAAAAAA==.Clumzyninja:BAAANQADCggIHAAAAA==.',
Co='Code:BAAANQADCggICAABNQAECggIDQABAAAAAA==.Coolbreez:BAAANQADCgMIAwAAAA==.Coolynn:BAAANQAECgIIAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.',
['Cä']='Cäldius:BAAANQADCgMIAwAAAA==.',
Da='Damacraze:BAAANQADCggIDQAAAA==.Danielwu:BAAANQADCgUIBQAAAA==.Dawigrund:BAAANQADCgUIBwAAAA==.',
De='Deadroar:BAAANQAECgcIDQAAAA==.Deadwill:BAAANQAECgMIAwAAAA==.Deaminase:BAAANQAECgUIBQAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAAANQAECgQIBQAAAA==.Delphoxx:BAAANQADCggIBgAAAA==.Demidru:BAAANQADCgYICwAAAA==.Depleterpann:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Desrook:BAAANQABCgMIBQAAAA==.',
Do='Double:BAAANQADCggICAAAAA==.Doublelift:BAAANQAECgQIBQAAAA==.',
Dr='Drakisara:BAAANQADCggIBgAAAA==.Drakuul:BAAANQADCgIIAgAAAA==.Droni:BAAANQADCgYICQAAAA==.Dröbi:BAAANQAECggICwAAAA==.',
Du='Dundundun:BAAANQADCgYIBgAAAA==.',
Eg='Eggdrop:BAAANQADCgQIBAAAAA==.Egufro:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.',
Eh='Ehgu:BAAANQAECgUICAAAAA==.',
El='Eleverclear:BAAANQADCgYIBgAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.',
Et='Etom:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Ev='Eviae:BAAANQADCgQIBAAAAA==.',
Fa='Fairyhunter:BAAANQADCgUIBQAAAA==.Fairymonk:BAAANQADCgEIAQAAAA==.Fatfatfat:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.Fañgrat:BAAANQADCgQIBAABNQADCgMIAwABAAAAAA==.',
Fl='Flandia:BAAANQADCggICgAAAA==.',
Fr='Fricher:BAAANQADCgcICgAAAA==.Froznrage:BAAANQAECgYICQAAAA==.',
Fy='Fylerianprie:BAAANQAECgEIAgAAAA==.',
Ga='Ganjja:BAAANQADCggIEAAAAA==.',
Ge='Geneman:BAAANQABCgIIAgAAAA==.Getsyouwet:BAAANQAECgEIAQABNQAECgcICgABAAAAAA==.Getter:BAAANQADCgYIBgAAAA==.',
Gi='Giny:BAAANQAECgEIAQAAAA==.',
Go='Gorvash:BAAANQADCgIIAgAAAA==.Govinniuur:BAAANQADCgcICwAAAA==.',
Gr='Grizzy:BAAANQAECgQIBQAAAA==.',
Gy='Gyndrinolara:BAAANQADCgIIAgAAAA==.',
Ha='Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAAANQADCgMIAwAAAA==.',
Ho='Holyflame:BAAANQADCgQIBAAAAA==.Holypewpewz:BAAANQADCgUIBQABNQADCgcICQABAAAAAA==.Holyyshift:BAAANQADCgcICQAAAA==.',
Hu='Hunterlizzie:BAEANQAECgMIAwAAAA==.',
Ia='Iamfried:BAAANQAECgQIBAAAAA==.',
Il='Illidigle:BAAANQADCgQIBAAAAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAAANQAECgUIBQAAAA==.Inyadraug:BAAANQADCgQIBQAAAA==.',
Ir='Ironheãrt:BAAANQAECgMIAwAAAA==.Ironsight:BAAANQADCgcIDQAAAA==.',
Is='Isaacnewton:BAAANQAECgEIAgAAAA==.',
It='Itai:BAAANQAECgQIBAAAAA==.',
Ja='Jackk:BAAANQAFFAEIAQAAAA==.Jackks:BAAANQAECgQIBAABNQAFFAEIAQABAAAAAA==.Jasmonk:BAAANQADCggICwAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jellysickle:BAAANQADCgcIAwAAAA==.',
Ji='Jinkua:BAAANQAECgEIAQAAAA==.Jinkz:BAAANQADCgYIBgAAAA==.',
Jo='Jolfurnuand:BAAANQADCgIIAgAAAA==.Jorhel:BAAANQADCggIDgAAAA==.',
Ju='Judgevis:BAAANQAECgEIAQAAAA==.',
Ka='Kaeliis:BAAANQADCgEIAQAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Kazuu:BAAANQABCgQIBgAAAA==.',
Kb='Kbeckinsale:BAAANQADCggICwABNQAECgQIBAABAAAAAA==.',
Ke='Keladun:BAAANQADCgUICgAAAA==.',
Kh='Kharga:BAAANQAECgEIAQAAAA==.Khonan:BAAANQADCgUIBQABNQAFFAEIAQABAAAAAA==.',
Ko='Kordarg:BAAANQADCgQIBAAAAA==.',
Kr='Kriss:BAAANQADCgEIAQAAAA==.Kristeena:BAAANQADCgUIBQAAAA==.Kryptonikk:BAAANQADCgQIBAAAAA==.Kröw:BAAANQADCgcIDQAAAA==.',
Ku='Kudrix:BAAANQADCggIDgAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQADCgYICgAAAA==.Laurijaydn:BAAANQADCgYICQAAAA==.Laurynn:BAAANQADCgQIBgAAAA==.',
Le='Legionremix:BAAANQADCgEIAQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.',
Li='Likeaglove:BAAANQADCgIIAgABNQAECgUIBgABAAAAAA==.Littlestarz:BAAANQADCgcICAAAAA==.Lizzieag:BAEANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
Ll='Llemons:BAAANQADCggIFQAAAA==.',
Lo='Lolblur:BAAANQADCgYIBgAAAA==.Lootah:BAAANQADCggIEAAAAA==.Loranoth:BAAANQADCgYICwAAAA==.Lovecox:BAAANQADCgIIAgAAAA==.',
Lu='Luminali:BAAANQAECgEIAQAAAA==.Lunadari:BAAANQADCgcICwAAAA==.Lunareva:BAAANQADCggICwABNQAECgEIAQABAAAAAA==.',
Ly='Lyxon:BAAANQADCggIDQAAAA==.',
['Læ']='Lænna:BAAANQADCgUIBQAAAA==.',
Ma='Mafoôza:BAAANQAECgQIBAAAAA==.Magicalama:BAAANQAECgQIBwAAAA==.Magnanimity:BAEANQADCgEIAQABNQAECgEIAQABAAAAAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAAANQADCgUIBwABNQADCggIFQABAAAAAA==.Maliciouso:BAAANQAECgEIAQAAAA==.Malédiction:BAAANQAECgEIAQAAAA==.Marley:BAAANQADCggICQAAAA==.Matua:BAAANQADCgYIBgAAAA==.',
Me='Medizine:BAAANQADCgYIDgAAAA==.Megamacdin:BAAANQAECgQIBgAAAA==.',
Mi='Miistral:BAAANQADCgcIDQAAAA==.Mimie:BAAANQAECgQIBAAAAA==.Mistyeva:BAAANQAECgEIAQAAAA==.',
Mo='Moistooltip:BAAANQADCgYIBgAAAA==.Mokotrize:BAAANQADCggICwAAAA==.Moosh:BAAANQADCgcIFAAAAA==.Mordred:BAAANQADCgUICgAAAA==.Mouthkisser:BAAANQAECgMIAwAAAA==.',
Mu='Mud:BAAANQAECgEIAQAAAA==.Mudslinger:BAAANQADCgQIBAAAAA==.Munchies:BAAANQADCggIDQAAAA==.',
My='Myrolan:BAAANQADCgYIBwABNQADCgcICwABAAAAAA==.',
Na='Nanoko:BAAANQAECgEIAQAAAA==.',
Ne='Neckslice:BAAANQAECggIDQAAAA==.Neuro:BAAANQAECgIIAgAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQADCggIDAAAAA==.Nirri:BAAANQADCgYICAAAAA==.Nitefall:BAAANQAECgEIAQAAAA==.',
No='Nocando:BAAANQAECgUIBgAAAA==.Notadk:BAAANQABCgQIBAAAAA==.Noturbudpal:BAAANQADCgIIAgABNQADCggIHAABAAAAAA==.',
Nu='Nuriel:BAAANQADCgQIBAAAAA==.',
Ol='Oline:BAAANQAECgYIBwAAAA==.',
Oo='Oonaki:BAAANQAECgEIAQAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Pa='Painloa:BAAANQADCgYICgAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Paradoxx:BAAANQADCggICAAAAA==.',
Ph='Phelefica:BAAANQADCgIIAgAAAA==.Phreyja:BAAANQADCgIIAgAAAA==.Phylgon:BAAANQABCgQIBgAAAA==.',
Po='Pointybrows:BAAANQADCgYIBwAAAA==.',
Qu='Quelestraza:BAAANQADCgcIDAAAAA==.Quikkmex:BAAANQADCgYIBgAAAA==.',
Ra='Raewyck:BAAANQADCgYIDAAAAA==.Raginbull:BAAANQADCgcIBwAAAA==.Ragingmaze:BAAANQAECgEIAQAAAA==.Rainburrow:BAAANQADCgYICwAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Restingbface:BAAANQADCggICAAAAA==.Retana:BAAANQAECggICgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.',
Rh='Rhalk:BAAANQABCgEIAQAAAA==.Rhinn:BAAANQADCgYICwAAAA==.',
Ro='Roastedz:BAAANQADCgQIBAAAAA==.Roflmaster:BAAANQADCgcIBwAAAA==.Rojen:BAAANQADCgQIAgAAAA==.',
Ry='Ry:BAAANQADCggIDgAAAA==.Ryanna:BAAANQADCgYIBgAAAA==.',
Sa='Saevio:BAAANQADCgYICQAAAA==.Salvader:BAAANQADCgYIDAAAAA==.Sashimi:BAAANQADCgIIAgAAAA==.',
Sc='Scarllett:BAAANQAECgIIAgAAAA==.',
Se='Sevie:BAAANQAFFAIIAgAAAA==.',
Sh='Shabbyy:BAAANQADCgUICwABNQADCgYIBgABAAAAAA==.Shadowpump:BAAANQAECgMIBwAAAA==.Shamsel:BAAANQADCggICgAAAA==.Shinnz:BAAANQADCgUIBgAAAA==.Shockcaller:BAAANQAECgMIAwAAAA==.Shockingnut:BAAANQAECgMIAwAAAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAAANQADCgYIBgABNQADCgMIAwABAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Simmara:BAAANQAECgMIAwAAAA==.',
Sm='Smallighting:BAAANQAECgQIBAAAAA==.',
So='Solanthis:BAAANQADCggIEgAAAA==.Solstica:BAAANQADCgYICQAAAA==.',
Sp='Spiritualone:BAAANQADCgYICwAAAA==.',
St='Steelrib:BAAANQADCgYICwAAAA==.Stonystark:BAAANQADCgYIBwAAAA==.Straam:BAAANQAECgUICgAAAA==.Strizzle:BAEANQAECgEIAQAAAA==.Støney:BAAANQADCggICQAAAA==.',
Su='Subatronic:BAAANQAECgcICwAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAAANQADCggICAAAAA==.Takki:BAAANQAECgIIAgAAAA==.Tamsîn:BAAANQAECgQIBgAAAA==.',
Te='Teinuya:BAAANQAECgMIAwAAAA==.',
Th='Thorimeir:BAAANQADCgIIAgAAAA==.Thraxacious:BAAANQAECgMIAwAAAA==.Thulsadoomm:BAAANQADCgQIBAAAAA==.',
Ti='Tiduss:BAAANQADCgYICgAAAA==.Tigó:BAAANQADCggIDgAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAAANQADCgYICwAAAA==.Tinkerbel:BAAANQADCgcIBwAAAA==.Tinkerbella:BAAANQADCgQIBQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAECgYIBgABAAAAAA==.Tireliaa:BAAANQADCgUIBgAAAA==.',
To='Tohsaka:BAAANQADCgIIAgAAAA==.',
Tr='Trafalgour:BAAANQADCgcICQAAAA==.Trazen:BAAANQADCgQIBwAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAAANQADCgcICgAAAA==.',
Tu='Tundal:BAAANQAECgEIAQAAAA==.',
Ud='Uddertrouble:BAEANQAECgEIAQAAAA==.',
Un='Unholytiran:BAAANQADCgYIBgAAAA==.',
Ur='Urmada:BAAANQADCggICgAAAA==.Urmami:BAAANQADCgcICQAAAA==.',
Va='Valyne:BAAANQADCgYIBgAAAA==.Vampire:BAAANQAECgEIAQAAAA==.Vampyre:BAAANQAECggIDgAAAA==.Vargmal:BAAANQADCgYIBQAAAA==.',
Vi='Virala:BAAANQADCgMIAwAAAQ==.Vitamin:BAAANQADCgcIBwAAAA==.Vitaminn:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.',
Vl='Vlaen:BAAANQADCgcIBwAAAA==.',
Vo='Votum:BAAANQADCggIDgAAAA==.',
Vy='Vyrisa:BAAANQADCgMIAwAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wh='White:BAAANQADCggICAABNQAECggIDQABAAAAAA==.',
Wi='Wilbertorc:BAAANQADCgEIAQAAAA==.Wildwolff:BAAANQADCgUIBQAAAA==.Wilhedin:BAAANQAECgcICAAAAA==.',
Wo='Worm:BAAANQAECgcIDQAAAA==.',
Wu='Wulfnbolt:BAAANQADCggICgAAAA==.',
Wy='Wyon:BAAANQADCgYICQAAAQ==.',
Yu='Yunahpabo:BAAANQAECgUIBQAAAA==.',
Za='Zaffyl:BAAANQADCggICwAAAA==.Zandi:BAAANQADCgMIAwAAAA==.Zathara:BAAANQAECgQIBAAAAA==.',
Zo='Zodiac:BAAANQADCggICwAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQADCgIIAgAAAA==.Zuluk:BAAANQADCgYIBgAAAA==.',
['Zö']='Zörö:BAAANQAECgIIAgAAAA==.',
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
