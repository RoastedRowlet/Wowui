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

local lookup = {'Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aazula:BAAANQADCggIEwAAAA==.',
Ab='Aburocket:BAAANQADCgMIAwAAAA==.',
Ak='Akusenshi:BAAANQADCgEIAQAAAA==.',
Al='Alethrix:BAAANQADCgIIAgAAAA==.',
An='Anderon:BAAANQADCggIEAAAAA==.Animocity:BAAANQADCggIEwAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAAANQAECgEIAgAAAA==.',
As='Asylia:BAAANQAECgYIBgAAAA==.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Az='Azryll:BAAANQADCgYICgAAAA==.',
Ba='Babalú:BAAANQADCgYICgAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQADCgcIEgAAAA==.Barcaust:BAAANQADCgcIBwAAAA==.',
Be='Beecrafty:BAAANQADCgcIEQAAAA==.Belin:BAAANQADCgIIAgAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.',
Bi='Biras:BAAANQADCgQIBAAAAA==.',
Bl='Blackmill:BAAANQADCgYIBgAAAA==.',
Bo='Board:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.Bolf:BAAANQADCgYICwAAAA==.Boombaaby:BAAANQADCggIGwAAAA==.Bopples:BAABNQAECoEVAAICAAkJvRpcBwAWAwACAAkJvRpcBwAWAwAAAA==.',
Br='Britishchick:BAAANQAECgIIAgAAAA==.Brunhilian:BAAANQADCgUIBwAAAA==.',
Ca='Cadun:BAAANQADCgcIEgAAAA==.Cakeismoist:BAAANQADCggICAAAAA==.Calada:BAAANQADCgYIEAAAAA==.Callypso:BAAANQADCggIEwAAAA==.Cariono:BAAANQAECgQIBQAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Cathslock:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Cathsmage:BAAANQAECgEIAQAAAA==.',
Ce='Cedarnia:BAAANQADCgYIDAAAAA==.',
Co='Corbyn:BAAANQABCgQICAAAAA==.',
Cr='Cribbage:BAAANQADCgYIBgABNQAECgYIDQABAAAAAA==.',
Cv='Cvaluenigma:BAAANQAECgMIAwAAAA==.',
Cy='Cytronsneak:BAAANQADCgQIBAAAAA==.',
Da='Daliå:BAAANQADCgMIAwAAAA==.Dalrook:BAAANQADCgcIDgAAAA==.Darkheaven:BAAANQAECgMIAwAAAA==.Darknyss:BAAANQADCggIDwAAAA==.Davethelock:BAAANQADCgEIAQAAAA==.Dazarek:BAAANQADCggIDAAAAA==.',
De='Demonbarbie:BAAANQADCgcICwAAAA==.Denae:BAAANQADCggICAAAAA==.Desiinnorre:BAAANQADCgQICAAAAA==.Devinetoro:BAAANQADCggIEQAAAA==.Devour:BAAANQAECgQIBAAAAA==.',
Di='Diag:BAAANQADCggIFAAAAA==.Diamos:BAAANQAECgIIAgAAAA==.Dijiaih:BAAANQADCgQIBwAAAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQADCgMIAwAAAA==.Dwydeshuse:BAAANQADCgQIBwAAAA==.',
Ei='Einheri:BAAANQAECgIIAgAAAA==.',
El='Elalian:BAAANQAECgQIBAAAAA==.Elracc:BAAANQABCgQIBAAAAA==.',
En='Endeavour:BAAANQAECgcIBwAAAA==.Enoira:BAAANQABCgIIAgAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAAANQADCgYIEAAAAA==.',
Er='Erfing:BAAANQADCgYIBgAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Faffard:BAAANQADCgUIBgABNQAECgIIAgABAAAAAA==.Fame:BAAANQADCggICAABNQAFFAMIAwABAAAAAA==.Farsighted:BAAANQADCgIIAgAAAA==.',
Fe='Ferio:BAAANQADCgYIDAAAAA==.Feyndra:BAAANQADCgYIEAAAAA==.',
Fi='Fishfire:BAAANQADCgcIEAAAAA==.',
Fu='Funenix:BAAANQABCgQIBAAAAA==.',
Fy='Fystie:BAAANQADCggIEgABNQAECgIIAgABAAAAAA==.',
Ga='Galpally:BAAANQAECgQIBAAAAA==.',
Ge='Gebra:BAAANQADCggIEgAAAA==.',
Gh='Ghenghiskhan:BAAANQADCgIIAgAAAA==.',
Gl='Glorak:BAAANQADCgcIEgAAAA==.',
Gr='Grashen:BAAANQADCgcICwAAAA==.Gravorik:BAAANQAECgQIBAAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grogu:BAAANQADCgYICwAAAA==.',
Gs='Gsm:BAAANQADCggIFAAAAA==.',
Gu='Gurlyman:BAAANQADCgQIBAAAAA==.',
Ha='Halyon:BAAANQAECgIIAgAAAA==.Hante:BAAANQADCgEIAQAAAA==.',
He='Hellblazer:BAAANQAECgMIAwAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAAANQAECgcICgAAAA==.Hoofnstien:BAAANQAECgQIBAAAAA==.Hoompukka:BAAANQADCgQIBAAAAA==.Hotspur:BAAANQAECgIIAgAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Il='Iliketurtles:BAAANQADCggICgABNQAECgQIDQABAAAAAA==.Ilokana:BAAANQADCgUIBQAAAA==.',
Im='Imwithhir:BAAANQADCggIDQAAAA==.',
Ir='Ironfist:BAAANQADCgUIBwAAAA==.',
Ja='Jacspally:BAAANQADCggIEgAAAA==.Janora:BAAANQAECgMIAwAAAA==.',
Je='Jellexy:BAAANQADCgYICwAAAA==.',
Jo='Jolah:BAAANQAECgUIBwAAAA==.',
Ka='Kaisa:BAAANQADCgcIBwAAAA==.Karst:BAAANQADCgcIEgAAAA==.Kayzon:BAABNQAFFIEIAAIDAAUJ2Bg0AADLAQADAAUJ2Bg0AADLAQAAAA==.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.',
Kl='Klavine:BAAANQAECgYICgAAAA==.',
Ko='Korben:BAAANQAECgQIBAAAAA==.',
Kr='Kragorn:BAAANQAECgMIAwAAAA==.Kronn:BAAANQADCgQIBAAAAA==.',
Ku='Kublakhan:BAAANQADCggICwAAAA==.',
Ky='Kylaania:BAAANQADCgEIAQAAAA==.Kynleria:BAAANQADCgMIAwAAAA==.',
['Kõ']='Kõrin:BAAANQADCgYIBwAAAA==.',
La='Lakhi:BAAANQAECgEIAQAAAA==.Lapras:BAEANQAFFAQIAgAAAA==.Laureli:BAAANQADCgYIEAAAAA==.',
Le='Leeta:BAAANQADCggIEwABNQAECgIIAgABAAAAAA==.Lemooski:BAAANQAECgIIAgABNQAECggICQABAAAAAA==.Leorra:BAAANQADCggIFAAAAA==.Letholdus:BAAANQADCggIEgAAAA==.',
Li='Lightningg:BAAANQAECgIIAgAAAA==.Linara:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Lo='Loraemar:BAAANQADCgQIBAAAAA==.Losoz:BAAANQADCgcIBwAAAA==.',
Lu='Lusilsandrus:BAAANQADCgQIBQAAAA==.',
Ma='Maddlib:BAAANQAECgYIDQAAAA==.Maegwin:BAAANQAECgEIAQAAAA==.Magicpie:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Maglani:BAAANQADCggIDgAAAA==.Mahoutsukai:BAAANQADCgcIBwAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Mania:BAAANQAECgcIDAAAAA==.Matti:BAAANQADCgcIEgAAAA==.Maul:BAAANQADCgEIAQAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Mildrik:BAAANQAECgMIAwAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Mirkdrak:BAAANQADCgYIDAABNQAECgMIBAABAAAAAA==.Mishach:BAAANQADCgcIDAAAAA==.Misheard:BAAANQAECgMIAwAAAA==.Misjudged:BAAANQAECgcIEAAAAA==.Missmarsha:BAAANQADCggIFAAAAA==.Mit:BAAANQAECgMIAwAAAA==.Mizzen:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.',
Mo='Mohtavius:BAAANQADCggIFAAAAA==.Mommydearest:BAAANQAECgIIAgAAAA==.Mongrell:BAAANQADCgYIBgAAAA==.Moonkissed:BAAANQADCgUICAAAAA==.Motz:BAAANQADCgYIDQAAAA==.',
Mu='Muura:BAAANQAECgQIBAAAAA==.',
My='Mylitlepwny:BAAANQADCgQIBAAAAA==.',
Na='Nabsta:BAAANQADCgMIBQAAAA==.',
Ne='Nekorii:BAAANQADCggIDgAAAA==.',
Oe='Oekabe:BAAANQABCgYIBwAAAA==.',
Ot='Otwin:BAAANQAECgEIAQAAAA==.',
Pa='Pahuum:BAAANQADCgQIBAAAAA==.Paimon:BAAANQAECgQIBAABNQAFFAMIAwABAAAAAA==.Palleigh:BAAANQADCggIEgAAAA==.Pamaro:BAAANQADCgYIBgAAAA==.',
Pe='Pepperjack:BAAANQADCgcIEgABNQAECgIIAgABAAAAAA==.Peril:BAAANQABCgYICgAAAA==.Persimmon:BAAANQAECgMIAwAAAA==.',
Po='Poondor:BAAANQADCgEIAQAAAA==.',
Pr='Predaturd:BAAANQADCgcIDAAAAA==.Prettydruid:BAAANQAECgEIAQAAAA==.',
Qi='Qindere:BAAANQADCgUIBQAAAA==.',
Ra='Raeinthe:BAAANQAECgMIBQAAAA==.Rakshaman:BAAANQADCggIEwAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Resiaus:BAAANQAECgYICwAAAA==.',
Ru='Run:BAAANQAECggIDgABNQAFFAMIAwABAAAAAA==.',
Ry='Ry:BAAANQAECgIIAwAAAA==.',
Sa='Sachtat:BAAANQADCggIEAAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAAANQADCggIEwAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAAANQAECgMIAwAAAA==.',
Sh='Shamanta:BAAANQADCgEIAQAAAA==.Shinstabber:BAAANQAECgMIAwAAAA==.Shivantice:BAAANQADCgYIBgAAAA==.Shruggie:BAAANQADCgYIEAAAAA==.',
Si='Siphondark:BAAANQAECgMIAwAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sm='Smolnad:BAAANQADCgYICwAAAA==.',
So='Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spudsy:BAAANQADCgUIBQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.',
Sy='Synfyl:BAEANQADCgYICgABNQAECgIIAgABAAAAAA==.Synpathi:BAEANQADCgIIAgABNQAECgIIAgABAAAAAA==.Synsyn:BAEANQAECgIIAgAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Taytemswift:BAAANQADCgEIAQABNQADCggIDgABAAAAAA==.Taílorswift:BAAANQADCggIDgAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAAANQADCggIFAAAAA==.Terepal:BAAANQADCggICAAAAA==.',
Th='Theel:BAAANQADCgUICgAAAA==.Theruss:BAAANQADCgEIAgAAAA==.',
Ti='Tinbasher:BAAANQADCggIEAAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.',
Tr='Tricky:BAAANQADCgUICAAAAA==.',
Tw='Tweetêr:BAAANQABCgQIBAAAAA==.',
Ug='Uglyboyryan:BAAANQADCgIIAgAAAA==.',
Ut='Uttrsdeek:BAAANQAECgcICwAAAA==.',
Va='Valfurian:BAAANQADCggICAABNQADCggIEwABAAAAAA==.Valkky:BAAANQADCggIFAAAAA==.Vallysong:BAAANQADCgUICAABNQADCggIFAABAAAAAA==.Vandeta:BAAANQADCgQIBAAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQADCggIFQAAAA==.Vessna:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.Veti:BAAANQADCgcIEQAAAA==.',
Vi='Vivîán:BAAANQADCggIEgAAAA==.',
Vo='Vodic:BAAANQAECgYICwAAAA==.Voras:BAAANQAECgUIBgAAAA==.Vorttex:BAAANQADCgQIBAAAAA==.',
Wa='Wasure:BAAANQADCgcIDQAAAA==.',
Wo='Worthy:BAAANQADCgQIBAAAAA==.',
Xe='Xeleik:BAAANQAECgEIAQAAAA==.',
Xy='Xylar:BAAANQADCgcIBwAAAA==.',
Yo='Yoshino:BAAANQADCggIEgABNQADCgEIAQABAAAAAA==.',
Yu='Yukilumi:BAAANQADCgEIAQAAAA==.',
Ze='Zeynah:BAAANQADCgYICQAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zophier:BAAANQADCgYIBgAAAA==.Zoéy:BAAANQABCgMIAwAAAA==.',
Zu='Zube:BAAANQAECgYIBwAAAA==.',
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
