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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Priest-Holy','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=53,date='2026-09-15',data={Al='Alys:BAAANQADCggIEQAAAA==.',
Am='Amaniatres:BAAANQAECgYIEAAAAA==.Amperage:BAAANQADCgUIEAABNQAECgYIEAABAAAAAA==.',
An='Anaan:BAAANQADCgYIBgAAAA==.Anahera:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Anzhelina:BAAANQADCggIDgAAAA==.',
Ap='Apis:BAAANQADCggICAAAAA==.',
Ar='Arihana:BAAANQADCgYIFQAAAA==.',
As='Asapshocky:BAAANQAFFAEIAQAAAA==.',
Ba='Baahp:BAAANQAECgQIBAAAAA==.Barley:BAAANQABCgIIAgAAAA==.',
Be='Belgerra:BAAANQAECgUIBwAAAA==.Bellabelle:BAAANQADCgIIAwAAAA==.Bevian:BAAANQADCgEIAQABNQADCgYIDwABAAAAAA==.',
Bi='Biggiepants:BAAANQAECgQIBQAAAA==.Biggnome:BAAANQADCgYIBgABNQADCgUICQABAAAAAA==.Bighead:BAAANQADCgQIBAABNQADCgUICQABAAAAAA==.Biollante:BAAANQADCgYICAAAAA==.',
Bo='Bootyßandaid:BAAANQAECgUICgAAAA==.',
Bu='Buckis:BAAANQADCgYIFwAAAA==.',
Ca='Camderags:BAAANQADCggICAAAAA==.Canon:BAAANQADCggIEAAAAA==.Catasucked:BAAANQADCgMIAwAAAA==.',
Ch='Chillin:BAAANQADCgEIAQAAAA==.Choggy:BAAANQAECgUICwAAAA==.',
Ci='Cindrõz:BAAANQAECgQIBAAAAA==.',
Co='Conception:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.Cough:BAAANQADCgUICQAAAA==.',
Cr='Crinklecut:BAAANQAECgIIAgAAAA==.Crow:BAAANQAECgYICwAAAA==.',
Da='Danielallen:BAAANQAECgEIAQAAAA==.',
De='Deadlybeard:BAAANQADCgQICQABNQAECgQICAABAAAAAA==.Deadlywrath:BAAANQAECgQICAAAAA==.Deadmenace:BAAANQADCgYICwAAAA==.Decåying:BAAANQAECgQICAAAAA==.Deni:BAAANQADCggICgAAAA==.',
Di='Diagnosis:BAAANQAECgIIAgAAAA==.',
Do='Donnabb:BAAANQAECgQICAAAAA==.Donteatbees:BAAANQAECgIIAgAAAA==.Dop:BAAANQAECgQIBwAAAA==.Doran:BAAANQADCgUIBQAAAA==.Dottierotten:BAAANQADCgYIDAAAAA==.',
Dr='Drenrah:BAAANQAECgMIBAAAAA==.',
Ed='Edend:BAAANQADCgUICgAAAA==.',
Ei='Eiduartpaw:BAAANQAECgUIBQAAAA==.',
El='Electracutie:BAAANQAECgIIAgAAAA==.Elementdemon:BAAANQAECgQIDAAAAA==.',
En='Enthalpy:BAAANQAECgYIDAAAAA==.',
Es='Esperzoa:BAAANQAECgIIAgAAAA==.',
Eu='Eucalicdes:BAAANQAECgYIDgAAAA==.',
Ev='Evøkër:BAAANQABCgIIAgAAAA==.',
Ez='Ezra:BAAANQADCgUICgAAAA==.',
Fa='Falshin:BAAANQADCggICAAAAA==.Fancy:BAAANQADCgYIEwAAAA==.Fangyi:BAAANQAECgQICAAAAA==.',
Fi='Fiction:BAAANQAECggIDAAAAA==.',
Fl='Florita:BAAANQADCggIGQAAAA==.',
Fo='Fordinn:BAAANQAECgQIDQAAAA==.',
Fr='Fren:BAAANQAECgQIBAAAAA==.',
Fu='Furrypunch:BAAANQABCgIIAgABNQABCgIIAgABAAAAAA==.',
Ga='Gasket:BAAANQAECgYIDgAAAA==.',
Gr='Graceful:BAAANQAECgQICgAAAA==.',
Ha='Handicap:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Hark:BAAANQAECgYIDgAAAA==.Harpin:BAAANQAECgUIBwAAAA==.Harvin:BAAANQAECgIIAwAAAA==.',
He='Heals:BAAANQAECggICAAAAA==.Heisenburgg:BAAANQADCgYIBgAAAA==.Helanua:BAAANQAECgIIAgAAAA==.',
Hi='Highlight:BAAANQADCgcIEQAAAA==.Hippopotamus:BAAANQADCgIIAgAAAA==.Hit:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.',
Ho='Holyish:BAAANQADCgIIAgAAAA==.Holytide:BAAANQAECgEIAQAAAA==.Hops:BAAANQADCgQIBAAAAA==.Hornsie:BAAANQADCgIIAgAAAA==.Horrorfang:BAAANQAECgIIAwAAAA==.',
['Hä']='Häwke:BAAANQADCgQIBwAAAA==.',
Ib='Ibaar:BAACNQAFFIEHAAICAAUJZRzYAADKAQACAAUJZRzYAADKAQA1AAQKgRwAAgIACQnCIP8CAE0DAAIACQnCIP8CAE0DAAAA.',
Ic='Icialiaa:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.',
In='Inno:BAAANQADCgcIBwAAAA==.',
It='Ithacus:BAAANQAECgQIBwAAAA==.Itspriesty:BAAANQAECgEIAQAAAA==.',
Ja='Janari:BAAANQABCggICQAAAA==.Jandaar:BAAANQADCgYICQAAAA==.Jatt:BAAANQADCggICAAAAA==.Jattwuzza:BAAANQADCgQIBAAAAA==.',
Jd='Jdawgprime:BAAANQABCgQIBAAAAA==.',
Ji='Jilkaeden:BAAANQADCgcIBwAAAA==.',
Jo='Jorek:BAAANQAECgQICAAAAA==.',
Ka='Kaiva:BAAANQAECgQIBQAAAA==.Kavik:BAAANQADCgYIBgAAAA==.',
Ke='Keflá:BAAANQADCgUIBQAAAA==.Kelencye:BAAANQADCgcIDgAAAA==.',
Kh='Khaas:BAAANQAECgEIAQAAAA==.Khanloa:BAAANQADCgUIBQAAAA==.',
Ki='Killshot:BAAANQADCgUIBwAAAA==.',
Ko='Korihor:BAAANQAECgIIAgAAAA==.',
Kr='Krestus:BAAANQAECgQIBgAAAA==.Krispy:BAAANQADCggIHAAAAA==.Krix:BAAANQADCgcIBgAAAA==.',
Ku='Kuroji:BAAANQABCgEIAQAAAA==.',
La='Laerin:BAAANQAECgIIAgAAAA==.Landreielea:BAAANQAECgIIAQABNQAECgIIAgABAAAAAA==.Laxus:BAAANQAECgUICQAAAA==.',
Le='Lerenor:BAAANQADCgEIAQAAAA==.Levophed:BAAANQAECgIIAwAAAA==.',
Li='Lily:BAAANQAECgEIAQAAAA==.Linnt:BAAANQADCgcIEgAAAA==.Liyara:BAAANQAECgYIDgAAAA==.',
Ll='Llorsa:BAAANQAECgEIAQAAAA==.Lltoj:BAAANQADCgEIAQAAAA==.',
Lu='Lusavahza:BAAANQADCgUIBgAAAA==.',
['Lä']='Ländrei:BAAANQAECgIIAgAAAA==.',
Ma='Macy:BAAANQABCgIIAgAAAA==.Maikagond:BAAANQADCgYIBgABNQAECgQIBwABAAAAAA==.Makaria:BAAANQAECgIIAgAAAA==.Malbisa:BAAANQADCgYIDAAAAA==.Malphoz:BAAANQADCgUIBQAAAA==.Mandragora:BAAANQADCgYIDQAAAA==.Marli:BAAANQADCgIIAgAAAA==.',
Mi='Mickey:BAAANQAECgYIDgAAAA==.Mikiik:BAAANQAECgEIAQAAAA==.Mildoo:BAAANQAECgMIBgAAAA==.Milkymoo:BAAANQADCgUIBQABNQAFFAUICgADACMUAA==.',
Mo='Monq:BAAANQAECgMIBAAAAA==.Moón:BAAANQAECgQIBAAAAA==.',
['Mî']='Mîlk:BAAANQADCgIIAgAAAA==.',
Na='Narus:BAAANQADCggIFwABNQAECgQIDQABAAAAAA==.',
Ne='Neviaa:BAAANQAECgEIAQAAAA==.',
Ni='Nickypoo:BAAANQADCgYICQAAAA==.Nightmenace:BAAANQAECgEIAgAAAA==.Niq:BAAANQAECgEIAQAAAA==.',
No='Nothealster:BAAANQAECgMIBAAAAA==.Novacane:BAAANQAECgEIAgAAAA==.',
Ob='Obitrice:BAAANQAECgMIAwAAAA==.Obsidiian:BAAANQAECgIIAgAAAA==.Obsidion:BAAANQADCggIGAABNQAECgQIDQABAAAAAA==.',
Od='Odie:BAAANQAECgIIAgAAAA==.',
Or='Organdonor:BAAANQAECgUIBQAAAA==.',
Os='Ossin:BAAANQAECgIIAQAAAA==.',
Ov='Overwhtrice:BAAANQADCggICAAAAA==.',
Pa='Pantherlilly:BAAANQADCgYIDwAAAA==.',
Pe='Perry:BAAANQAECgIIAwAAAA==.',
Po='Pozufuma:BAAANQAECgEIAQAAAA==.',
Ps='Psychomantis:BAAANQAECgQICAAAAA==.',
Ra='Ravenbear:BAAANQAECgIIAgAAAA==.',
Re='Redpool:BAAANQAECgQIBAAAAA==.Retrix:BAAANQAECgQICAAAAA==.Revorra:BAAANQAECgQIBAABNQAECgQIDQABAAAAAA==.',
Ri='Ristvakbaen:BAAANQAECgUICQAAAA==.',
Ro='Robynlee:BAAANQAECgQIBAAAAA==.Rohini:BAAANQADCgQIBgAAAA==.Rovik:BAAANQAECgEIAQAAAA==.',
Sc='Sceryna:BAAANQAECgYICwAAAA==.Schiftly:BAAANQABCgIIAgAAAA==.Scrmndemn:BAAANQAECgQIBgAAAA==.',
Se='Sef:BAAANQAECgQIBAAAAA==.Serpent:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.',
Sh='Shamtastical:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Shikita:BAAANQAECgEIAgAAAA==.Shimadin:BAABNQAECoEdAAIEAAkJIh9pFAD9AgAEAAkJIh9pFAD9AgAAAA==.Shimsong:BAAANQADCggIDQABNQAECgkJHQAEACIfAA==.Shmerek:BAAANQAECgQICAAAAA==.',
Si='Sierramist:BAAANQAECgQIBgAAAA==.Silverstream:BAAANQAECgYIDwAAAA==.',
So='Solbin:BAAANQAECgMIBwABNQAECgcICwABAAAAAA==.Solexine:BAAANQADCgQIBAAAAA==.Solitudé:BAAANQADCggIFQABNQAECgYIDgABAAAAAA==.Soteirian:BAAANQAECgQIBwAAAA==.',
Sp='Spiritlinkin:BAAANQADCgQIBAAAAA==.',
St='Stalariais:BAAANQADCgYIBgABNQAECgYICAABAAAAAA==.Steve:BAAANQAECgEIAQAAAA==.',
Su='Sugardawn:BAAANQAECgQIBAAAAA==.Sugarkitty:BAAANQADCgcIBwAAAA==.Supereclipse:BAAANQAECgEIAQAAAA==.',
Sy='Sydvicious:BAAANQAECgQIBAAAAA==.',
Ta='Taintedwater:BAAANQADCggICAAAAA==.Tairnanach:BAAANQADCgYIDgAAAA==.Taladiir:BAAANQADCggICAAAAA==.Tayger:BAAANQADCgYIDwAAAA==.',
Td='Tdog:BAAANQADCgcIDgAAAA==.',
Te='Tecks:BAAANQAECgQICAAAAA==.Teslá:BAAANQAECgEIAQAAAA==.',
Th='Thayo:BAAANQADCgUIDgAAAA==.Themajor:BAAANQADCggIFwAAAA==.Therossyas:BAAANQADCgYIBgAAAA==.Thicctotems:BAABNQAECoEZAAMFAAgJmx3uGACPAgAFAAgJmx3uGACPAgAGAAEJbQkhqwBGAAAAAA==.Threat:BAAANQAECgQICgAAAA==.',
Ti='Tiamaat:BAAANQAECgQICAAAAA==.Tinysanta:BAAANQAECgIIAgAAAA==.Titus:BAAANQADCgYICQAAAA==.',
To='Toatani:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Tokkaebi:BAAANQABCgIIAgAAAA==.Torvar:BAAANQADCggIDwAAAA==.',
Ty='Tyletos:BAAANQAECgcICwAAAA==.',
Ug='Ugolok:BAAANQADCgcIDAAAAA==.',
Ur='Uriél:BAAANQADCgQIBAABNQAECgYIDgABAAAAAA==.Urubaen:BAAANQADCgUIBgABNQAECgUICQABAAAAAA==.',
Va='Valanoth:BAAANQADCgIIAgAAAA==.Valeene:BAAANQAECgQIBwAAAA==.',
Ve='Veiler:BAAANQAECgYIDgAAAA==.Veruca:BAAANQADCggICAAAAA==.Veviseron:BAAANQAECgQIBwAAAA==.',
Vi='Vinstalation:BAAANQAECgQIBwAAAA==.',
Vo='Vonbismarck:BAAANQAECgMIAwAAAA==.',
Vr='Vritraz:BAAANQAECgYIDgAAAA==.',
Wa='Warsonge:BAAANQADCgUIBQAAAA==.',
We='Wendypini:BAAANQAECgYIDgAAAA==.',
Wh='Whitlock:BAAANQAECgEIAQAAAA==.',
Ya='Yannhal:BAAANQAECgIIAgAAAA==.',
Za='Zangelf:BAAANQABCgYICwAAAA==.Zangolf:BAAANQABCggICwAAAA==.',
Zo='Zodiaac:BAAANQAECgQICAAAAA==.',
Zy='Zy:BAAANQAECgEIAQAAAA==.',
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
