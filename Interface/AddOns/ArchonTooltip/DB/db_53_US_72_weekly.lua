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
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aazula:BAAANQADCgcICwAAAA==.',
Al='Alethrix:BAAANQADCgIIAgAAAA==.',
An='Anderon:BAAANQADCggICAAAAA==.Animocity:BAAANQADCgcICwAAAA==.',
Ar='Arold:BAAANQAECgEIAQAAAA==.',
As='Asylia:BAAANQADCggIDgAAAA==.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Az='Azryll:BAAANQADCgQIBAAAAA==.',
Ba='Babalú:BAAANQADCgQIBAAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQADCgYICwAAAA==.',
Be='Beecrafty:BAAANQADCgUICgAAAA==.Belin:BAAANQADCgIIAgAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.',
Bo='Board:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.Bolf:BAAANQADCgUIBQAAAA==.Boombaaby:BAAANQADCgcIDgAAAA==.Bopples:BAAANQAECgYIDQAAAA==.',
Br='Brunhilian:BAAANQADCgMIAwAAAA==.',
Ca='Cadun:BAAANQADCgYICwAAAA==.Cakeismoist:BAAANQADCggIBgAAAA==.Calada:BAAANQADCgUICgAAAA==.Callypso:BAAANQADCgYICwAAAA==.Cariono:BAAANQAECgEIAQAAAA==.Cathslock:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Cathsmage:BAAANQAECgEIAQAAAA==.',
Ce='Cedarnia:BAAANQADCgQIBwAAAA==.',
Co='Corbyn:BAAANQABCgQIBgAAAA==.',
Cr='Cribbage:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.',
Cv='Cvaluenigma:BAAANQADCgcIDgAAAA==.',
Cy='Cytronsneak:BAAANQADCgQIBAAAAA==.',
Da='Daliå:BAAANQADCgMIAwAAAA==.Dalrook:BAAANQADCgYIDQAAAA==.Darkheaven:BAAANQADCgcIDgAAAA==.Darknyss:BAAANQADCgYICgAAAA==.Davethelock:BAAANQADCgEIAQAAAA==.Dazarek:BAAANQADCgYICQAAAA==.',
De='Demonbarbie:BAAANQADCgUIBQAAAA==.Desiinnorre:BAAANQADCgMIBAAAAA==.Devinetoro:BAAANQADCgcICQAAAA==.Devour:BAAANQADCggIDgAAAA==.',
Di='Diag:BAAANQADCgcIDAAAAA==.Diamos:BAAANQADCgcIDQAAAA==.Dijiaih:BAAANQADCgMIAwAAAA==.',
Do='Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwydeshuse:BAAANQADCgQIBAAAAA==.',
Ei='Einheri:BAAANQADCggIDwAAAA==.',
El='Elalian:BAAANQADCggIDgAAAA==.Elracc:BAAANQABCgQIBAAAAA==.',
Ep='Epistle:BAAANQADCgUICgAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Faffard:BAAANQADCgUIBgABNQADCggIDgABAAAAAA==.Fame:BAAANQADCggICAABNQAECggICwABAAAAAA==.Farsighted:BAAANQADCgIIAgAAAA==.',
Fe='Ferio:BAAANQADCgQICAAAAA==.Feyndra:BAAANQADCgUICgAAAA==.',
Fi='Fishfire:BAAANQADCgUICQAAAA==.',
Fu='Funenix:BAAANQABCgQIBAAAAA==.',
Fy='Fystie:BAAANQADCgUICgABNQADCggIDgABAAAAAA==.',
Ga='Galpally:BAAANQADCgQIBAAAAA==.',
Ge='Gebra:BAAANQADCgUICgAAAA==.',
Gh='Ghenghiskhan:BAAANQABCgIIAgAAAA==.',
Gi='Gilvader:BAAANQABCgEIAQAAAA==.',
Gl='Glorak:BAAANQADCgYICwAAAA==.',
Gr='Grashen:BAAANQADCgUIBQAAAA==.Gravorik:BAAANQADCgYIBgAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grogu:BAAANQADCgUIBQAAAA==.',
Gs='Gsm:BAAANQADCgcIDAAAAA==.',
Gu='Gurlyman:BAAANQADCgQIBAAAAA==.',
Ha='Hante:BAAANQADCgEIAQAAAA==.',
He='Hellblazer:BAAANQADCggIDgAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAAANQAECgMIAwAAAA==.Hoofnstien:BAAANQADCgQIBAAAAA==.Hoompukka:BAAANQADCgQIBAAAAA==.Hotspur:BAAANQADCgcIDQAAAA==.',
Il='Iliketurtles:BAAANQADCggICQABNQAECgQICQABAAAAAA==.',
Im='Imwithhir:BAAANQADCgYIBgAAAA==.',
Ir='Ironfist:BAAANQADCgMIAwAAAA==.',
Ja='Jacspally:BAAANQADCgcICgAAAA==.Janora:BAAANQADCgcICAAAAA==.',
Je='Jellexy:BAAANQADCgUIBQAAAA==.',
Jo='Jolah:BAAANQAECgIIAgAAAA==.',
Ka='Kaisa:BAAANQADCgcIBwAAAA==.Karst:BAAANQADCgYICwAAAA==.Kayzon:BAAANQAFFAQIAwAAAA==.',
Kl='Klavine:BAAANQAECgQIBAAAAA==.',
Ko='Korben:BAAANQADCggIDgAAAA==.',
Kr='Kragorn:BAAANQADCgQIBAAAAA==.Kronn:BAAANQADCgQIBAAAAA==.',
Ku='Kublakhan:BAAANQADCgQIBAAAAA==.',
Ky='Kylaania:BAAANQADCgEIAQAAAA==.',
['Kõ']='Kõrin:BAAANQADCgYIBwAAAA==.',
La='Lakhi:BAAANQADCgcIDAAAAA==.Laureli:BAAANQADCgUICgAAAA==.',
Le='Leeta:BAAANQADCgYICwAAAA==.Lemooski:BAAANQADCggICAAAAA==.Leorra:BAAANQADCgYIDAAAAA==.Letholdus:BAAANQADCgcICgAAAA==.',
Li='Lightningg:BAAANQADCgEIAQAAAA==.Linara:BAAANQAECgEIAQAAAA==.',
Lo='Loraemar:BAAANQADCgQIBAAAAA==.',
Lu='Lusilsandrus:BAAANQADCgQIBQAAAA==.',
Ma='Maddlib:BAAANQAECgUIBwAAAA==.Maegwin:BAAANQAECgEIAQAAAA==.Magicpie:BAAANQADCgQIBAABNQADCggICgABAAAAAA==.Maglani:BAAANQADCgYIBgAAAA==.Mahoutsukai:BAAANQADCgEIAQAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Mania:BAAANQAECgUICAAAAA==.Matti:BAAANQADCgYICwAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Mildrik:BAAANQADCgcIDgAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Mirkdrak:BAAANQADCgUIBgABNQAECgEIAQABAAAAAA==.Mishach:BAAANQADCgUIBQABNQADCgYICQABAAAAAA==.Misheard:BAAANQADCgcIDgAAAA==.Misjudged:BAAANQAECgUICQAAAA==.Missmarsha:BAAANQADCgcIDAAAAA==.Mit:BAAANQADCgcICAAAAA==.Mizzen:BAAANQADCgcIDAABNQAECgUICQABAAAAAA==.',
Mo='Mohtavius:BAAANQADCgcIDAAAAA==.Mommydearest:BAAANQADCggIDgAAAA==.Mongrell:BAAANQADCgYIBgAAAA==.Moonkissed:BAAANQADCgQIBAAAAA==.Motz:BAAANQADCgYIBwAAAA==.',
Mu='Muura:BAAANQADCggIDQAAAA==.',
My='Mylitlepwny:BAAANQADCgQIBAAAAA==.',
Na='Nabsta:BAAANQADCgMIBQAAAA==.',
Ne='Nekorii:BAAANQADCgQIBgAAAA==.',
Oe='Oekabe:BAAANQABCgQIBQAAAA==.',
Ot='Otwin:BAAANQADCgUICwAAAA==.',
Pa='Pahuum:BAAANQADCgQIBAAAAA==.Palleigh:BAAANQADCgcICgAAAA==.',
Pe='Pepperjack:BAAANQADCgYICwABNQADCgcIDQABAAAAAA==.Persimmon:BAAANQADCgcIDgAAAA==.',
Pr='Predaturd:BAAANQADCgcIDAAAAA==.Prettydruid:BAAANQADCggICAAAAA==.',
Qi='Qindere:BAAANQADCgUIBQAAAA==.',
Ra='Raeinthe:BAAANQAECgIIAgAAAA==.Rakshaman:BAAANQADCgcICwAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Resiaus:BAAANQAECgQIBQAAAA==.',
Ru='Run:BAAANQAECgEIAgABNQAECggICwABAAAAAA==.',
Ry='Ry:BAAANQAECgIIAgAAAA==.',
Sa='Sachtat:BAAANQADCgYICAAAAA==.Salandre:BAAANQABCgQIBAAAAA==.Saraya:BAAANQADCggICwAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAAANQADCgcIDgAAAA==.',
Sh='Shamanta:BAAANQADCgEIAQAAAA==.Shinstabber:BAAANQADCgcIDgAAAA==.Shruggie:BAAANQADCgYICgAAAA==.',
Si='Siphondark:BAAANQADCgcIDgAAAA==.',
Sm='Smolnad:BAAANQADCgUIBQAAAA==.',
Sp='Spudsy:BAAANQADCgUIBQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.',
Sy='Synsyn:BAEANQADCgUICQAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Taytemswift:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Taílorswift:BAAANQADCgYIBgAAAA==.',
Te='Temna:BAAANQADCgcIDAAAAA==.',
Th='Theel:BAAANQADCgUICgAAAA==.Theruss:BAAANQADCgEIAgAAAA==.',
Ti='Tinbasher:BAAANQADCgYICAAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.',
Tr='Tricky:BAAANQADCgMIAwAAAA==.',
Ug='Uglyboyryan:BAAANQADCgIIAgAAAA==.',
Ut='Uttrsdeek:BAAANQAECgQIBAAAAA==.',
Va='Valkky:BAAANQADCgcIDAAAAA==.Vallysong:BAAANQADCgUICAABNQADCggIFAABAAAAAA==.Vandeta:BAAANQADCgQIBAAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQADCggIDQAAAA==.Vessna:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Veti:BAAANQADCgcICgAAAA==.',
Vi='Vivîán:BAAANQADCgUICgAAAA==.',
Vo='Vodic:BAAANQAECgUIBQAAAA==.Voras:BAAANQAECgEIAQAAAA==.Vorttex:BAAANQADCgQIBAAAAA==.',
Wa='Wasure:BAAANQADCgYIBgAAAA==.',
Wo='Worthy:BAAANQADCgQIBAAAAA==.',
Xe='Xeleik:BAAANQADCgcICwAAAA==.',
Xy='Xylar:BAAANQADCgcIBwAAAA==.',
Yo='Yoshino:BAAANQADCgYICgABNQADCgEIAQABAAAAAA==.',
Yu='Yukilumi:BAAANQADCgEIAQAAAA==.',
Ze='Zeynah:BAAANQADCgYIBgAAAA==.',
Zo='Zoedan:BAAANQADCgEIAgAAAA==.Zoéy:BAAANQABCgIIAgAAAA==.',
Zu='Zube:BAAANQAECgEIAQAAAA==.',
['Âu']='Âuranna:BAAANQADCgQIBAAAAA==.',
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
