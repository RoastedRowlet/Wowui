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
local provider = {region='US',realm="Quel'dorei",name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Acaleus:BAAANQADCgUIBQAAAA==.',
Ad='Adric:BAAANQADCgYICQAAAA==.',
Ah='Ahnji:BAAANQADCgMIBAAAAA==.',
Ai='Aings:BAAANQAECgIIAgAAAA==.',
Al='Alarus:BAAANQAECgQIBgAAAA==.Alex:BAAANQAECgQIBAAAAA==.Allypally:BAAANQADCggIDQAAAA==.',
Am='Amgrod:BAEANQADCgUIBQAAAA==.',
An='Andaarian:BAAANQADCgUIBQAAAA==.',
Ar='Arkhitype:BAAANQADCgcIDQAAAA==.Aryahi:BAAANQAECgIIAQAAAA==.',
As='Ashyslashy:BAAANQAECgIIAgAAAA==.Asur:BAAANQADCgcIDQAAAA==.',
Au='Auracorusca:BAAANQADCgcICwAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Ay='Aydain:BAAANQADCgQIBAAAAA==.',
Ba='Bajr:BAAANQAECgEIAQAAAA==.Bakura:BAAANQAECgIIAgAAAA==.Banker:BAAANQAECgEIAQAAAA==.Baroo:BAAANQADCgYIEgAAAA==.',
Be='Berko:BAAANQAECgQIDQAAAA==.Beyorne:BAAANQABCgQIBQAAAA==.',
Bi='Bigbear:BAAANQADCgYIBgAAAA==.Bigbill:BAAANQADCgMIAwAAAA==.Bigdeath:BAAANQADCgYICgAAAA==.Bizco:BAAANQADCgYIBwAAAA==.',
Bj='Bjebo:BAAANQAECgMIAwAAAA==.',
Bl='Bluffshot:BAAANQAECgEIAQAAAA==.',
Br='Brynjalf:BAAANQADCgMIAwAAAA==.Bràe:BAAANQABCgMIAQAAAA==.',
['Bï']='Bïcho:BAAANQADCggIDgAAAA==.',
Ca='Calambar:BAAANQADCgYIBgAAAA==.Cascadio:BAAANQADCgUICAAAAA==.Castanza:BAAANQADCgQIBAAAAA==.',
Ch='Charjer:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Chokengag:BAAANQADCgMIAwAAAA==.',
Co='Codedgar:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Cojostudio:BAAANQADCggICAAAAA==.Comboost:BAAANQADCgUICgAAAA==.',
Cr='Crashcake:BAAANQADCggICwAAAA==.Croager:BAAANQAECgEIAQAAAA==.',
Cu='Cup:BAAANQAECgEIAQAAAA==.',
Cv='Cvv:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.',
Cy='Cywen:BAAANQADCggICAABNQAECgcICwABAAAAAA==.',
Da='Daelaris:BAAANQAECgMIAwAAAA==.Damonoris:BAAANQAECgIIAgAAAA==.Danielan:BAAANQADCggICAAAAA==.',
De='Deadzeo:BAAANQADCgYICQAAAA==.Dejavoid:BAAANQADCgIIAgAAAA==.Demonblades:BAAANQAECgEIAQAAAA==.Demonbreaker:BAAANQADCggICQAAAA==.Denarten:BAAANQAECgQIBAAAAA==.',
Di='Diotima:BAAANQADCgMIBAAAAA==.Dirtymorris:BAAANQAECgQIBQAAAA==.',
Do='Dockevorkian:BAAANQAECgQIBgAAAA==.Dornaaealdor:BAAANQADCgIIAgAAAA==.Dortwaz:BAAANQAECgIIAgAAAA==.Doublebonus:BAAANQADCggICAABNQAECgYICQABAAAAAA==.Dougdk:BAAANQAECgQIBgAAAA==.',
Dr='Dracoz:BAAANQADCgEIAQAAAA==.Druelf:BAAANQADCgUIBQAAAA==.Dryx:BAAANQADCgUIBQAAAA==.',
Du='Dunaarn:BAAANQADCgMIAwAAAA==.',
El='Elilla:BAAANQADCgcIDQAAAA==.Elorela:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.',
En='Enjoy:BAAANQAECgYICQAAAA==.',
Fa='Famiki:BAAANQADCgIIAgAAAA==.',
Fe='Felnollid:BAAANQAECgQIBAAAAA==.Fenanigans:BAAANQAECgQIBAAAAA==.',
Fi='Fistandcider:BAAANQADCgMIAwAAAA==.',
Fl='Fluffyhusky:BAAANQAECgQIBAAAAA==.',
Fo='Fontss:BAAANQADCgYIBgAAAA==.Fonyfish:BAAANQADCggICgAAAA==.',
Fu='Fubina:BAEANQAECgIIAgAAAA==.',
Fy='Fyjalla:BAAANQADCgcICAAAAA==.',
Gi='Gilgaglaive:BAAANQADCggICAAAAA==.Gilgämesh:BAAANQAECgcICwAAAA==.',
Gl='Glomah:BAAANQAECgEIAQAAAA==.Glorm:BAAANQAECgIIAgAAAA==.',
Go='Gobropro:BAAANQADCgYIBgAAAA==.Gorathan:BAAANQADCgMIAwAAAA==.',
Gr='Grantul:BAAANQAECgEIAQAAAA==.Grolgan:BAAANQADCgYIBgAAAA==.',
Gu='Gulbhang:BAAANQAECgQIBAAAAA==.',
He='Health:BAAANQADCgQIBAAAAA==.',
Ho='Holdi:BAAANQADCgUIBQAAAA==.Holyhammer:BAAANQADCggIDgAAAA==.Holyoke:BAAANQADCgEIAQAAAA==.',
Hu='Hujo:BAAANQAECgEIAQAAAA==.Hushpupi:BAAANQAECgMIBAAAAA==.Huskerpower:BAAANQADCgUICAAAAA==.',
Ic='Iceharted:BAAANQADCgEIAQAAAA==.Icesloth:BAAANQADCgcICwAAAA==.',
Id='Idamarie:BAAANQADCgcICQAAAA==.Iduun:BAAANQADCgEIAQAAAA==.',
Il='Iladelle:BAAANQAECgEIAQAAAA==.',
Io='Iorak:BAAANQADCgEIAQAAAA==.',
Ir='Irinon:BAAANQADCgcIBwAAAA==.',
Ix='Ixiya:BAAANQADCgQIBAAAAA==.',
Ja='Jaggerss:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Jamaican:BAAANQADCgYICwAAAA==.Jaste:BAAANQAECgEIAQAAAA==.',
Ji='Jimmym:BAAANQADCgUICAAAAA==.Jirakaidae:BAAANQADCgUIBQAAAA==.',
Ju='Juju:BAAANQAECgEIAQAAAA==.',
Ka='Kaeltharon:BAAANQADCgQIAwAAAA==.Kamekaze:BAAANQADCgUIBQAAAA==.Kandrys:BAAANQADCgQIBAAAAA==.Kayy:BAAANQADCgIIAgAAAA==.',
Kh='Khármá:BAAANQADCgYICAAAAA==.',
Ki='Killt:BAAANQAECgEIAQAAAA==.',
Ko='Koojoé:BAAANQADCgYIBwAAAA==.',
Ku='Kurzulan:BAAANQADCggIDQAAAA==.',
La='Laghles:BAAANQAECgQIBgAAAA==.Laylriely:BAAANQADCgcIDAAAAA==.',
Le='Lemanjá:BAAANQADCggIDAAAAA==.',
Li='Liliane:BAAANQAECgIIAgAAAA==.Limbless:BAAANQADCgIIAgABNQADCgQIBAABAAAAAA==.',
Lo='Lockrocks:BAAANQAECgEIAQAAAA==.Lontra:BAAANQADCgQIBAAAAA==.',
Lu='Luzifer:BAAANQADCgYIBgAAAA==.',
Ma='Magelyman:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Mahlaan:BAAANQAECgQIBgAAAA==.Malakai:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.Malekai:BAAANQADCggICAAAAA==.Malzen:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.Manaleia:BAAANQADCgYIBwAAAA==.Manasolid:BAAANQADCgEIAQAAAA==.Marvinah:BAAANQADCgUIBQAAAA==.',
Me='Meatcurtin:BAAANQADCgQIBAAAAA==.Meatlover:BAAANQAECgEIAQAAAA==.Meeshka:BAAANQAECgEIAQAAAA==.Meraleona:BAAANQAECgEIAQAAAA==.',
Mi='Migue:BAAANQABCgEIAQABNQAECgUICQABAAAAAA==.',
Mo='Moarass:BAAANQAECgIIAgAAAA==.Moris:BAAANQADCgYIBgAAAA==.',
Mu='Muldah:BAAANQADCgYIBgAAAA==.',
Na='Nas:BAAANQADCggIDwAAAA==.Navie:BAAANQAECgEIAQAAAA==.',
Ne='Nekros:BAAANQADCgcIBwAAAA==.Neø:BAAANQAECgEIAQAAAA==.',
Ni='Nicebud:BAAANQAECgEIAQAAAA==.Nightsfury:BAAANQADCgYIBwAAAA==.',
No='Nokastakaj:BAAANQADCgUIBQAAAA==.Nornyr:BAAANQADCgEIAQAAAA==.',
Nu='Nunsrsus:BAAANQAECgMIBAAAAA==.',
Ny='Nymerias:BAAANQADCgYIDgAAAA==.Nyrrah:BAAANQADCggICAAAAA==.',
['Ná']='Nácht:BAAANQADCggICAAAAA==.',
Ok='Oku:BAAANQADCgUIBQAAAA==.',
Om='Omaticaya:BAAANQADCggIDgAAAA==.Omèn:BAAANQADCgUIBQAAAA==.',
Op='Optikon:BAAANQAECgIIAgAAAA==.',
Ow='Owlbearcat:BAAANQAECgQIBAAAAA==.',
Pa='Packerssuck:BAAANQADCgEIAQAAAA==.Paean:BAAANQADCgMIAwAAAA==.',
Pk='Pkalygos:BAAANQAECgEIAQAAAA==.',
Po='Powerstrokee:BAAANQADCgMIBAAAAA==.',
Pr='Preyforme:BAAANQADCgMIAwAAAA==.',
Ps='Psychelone:BAAANQADCggIDAAAAA==.',
Qy='Qyxh:BAAANQADCggIDQAAAA==.',
Ra='Raine:BAAANQADCgMIAwAAAA==.Rastafarian:BAAANQADCgQIBAAAAA==.',
Re='Rexhavoc:BAAANQAECgQIBAAAAA==.',
Ro='Rosary:BAAANQADCggIDQAAAA==.Rosewoodren:BAAANQADCgYIBQAAAA==.',
Ru='Ruint:BAAANQADCgUIBQAAAA==.Runeclad:BAAANQAECgEIAQAAAA==.',
['Rï']='Rïvkah:BAAANQADCgEIAQABNQADCgYIBwABAAAAAA==.',
Sa='Salitheion:BAAANQADCgYIBQAAAA==.Sapper:BAAANQAECgMIAwAAAA==.Sarn:BAAANQADCggICAAAAA==.Sathi:BAAANQADCggICAAAAA==.Sayuri:BAAANQADCgEIAQAAAA==.',
Sh='Shladoran:BAAANQADCggIEAAAAA==.Shos:BAAANQAECgIIAgAAAA==.',
Si='Sinnister:BAAANQADCgYIBgAAAA==.',
Sk='Skully:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Sn='Snorina:BAAANQAECgIIAwAAAA==.',
So='Solàrflàré:BAAANQADCgMIAwAAAA==.Somsurvivor:BAAANQADCgUIBQAAAA==.Sosozen:BAAANQADCgcIDAAAAA==.',
Sp='Spirittoast:BAAANQADCgMIAwAAAA==.',
St='Starkiller:BAAANQADCgYIDQAAAA==.Stonesolid:BAAANQADCggIDgAAAA==.',
Su='Supremacy:BAAANQAECgMIAwAAAA==.',
Sw='Swiftshammy:BAAANQADCgQIBAAAAA==.Swytch:BAAANQAECgEIAQAAAA==.',
Sy='Sylvii:BAAANQAECgMIBAAAAA==.',
Ta='Tabor:BAAANQADCgYIBQAAAA==.Taladryn:BAAANQADCgcIDQAAAA==.Tarahly:BAAANQADCgYICQAAAA==.Tauryel:BAAANQADCgQIBAAAAA==.',
Te='Tekhan:BAAANQADCgQIBAAAAA==.',
Th='Themoosifer:BAAANQAECgcIDQAAAA==.Thyck:BAAANQADCggIDAAAAA==.Thydis:BAAANQAECgQIBQAAAA==.',
Ti='Tibbs:BAAANQAECgEIAQAAAA==.Ticklepickle:BAAANQADCgYIFgAAAA==.',
Tr='Trumalice:BAAANQADCgMIAwAAAA==.',
Tu='Tulpa:BAAANQABCgQIBgAAAA==.',
Ug='Uggar:BAAANQABCgEIAQAAAA==.',
Un='Uncorrupted:BAAANQAECgQIBgAAAA==.',
Va='Vaelm:BAAANQADCgEIAQAAAA==.Valericia:BAAANQADCgQIBAAAAA==.Valindrux:BAAANQAECgEIAQAAAA==.',
Ve='Velathila:BAAANQADCgQIBQAAAA==.',
Vi='Violêt:BAAANQADCgYIBgAAAA==.',
Vo='Voidchris:BAAANQAECgQIBAAAAA==.',
Wa='Warelf:BAAANQADCgYIBgAAAA==.',
Wy='Wylia:BAAANQADCgYIBgAAAA==.',
Za='Zakkmorris:BAAANQADCgEIAQAAAA==.Zakuren:BAAANQAECgIIAwAAAA==.',
Zi='Ziggi:BAAANQADCgYIBgAAAA==.',
Zo='Zondoul:BAAANQADCgYIBgAAAA==.',
Zu='Zuldave:BAAANQADCgYICAAAAA==.',
Zy='Zylera:BAAANQADCgYIBQAAAA==.',
['Ñî']='Ñîx:BAAANQADCggICwAAAA==.',
['Ød']='Ødinson:BAAANQADCgYICwAAAA==.',
['ßæ']='ßær:BAAANQADCgMIAwAAAA==.',
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
