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
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Adicia:BAAANQABCgIIBAAAAA==.',
Ae='Aedercy:BAAANQABCgUIBwAAAA==.Aestel:BAAANQABCgEIAQAAAA==.',
Al='Alarus:BAAANQADCgQIAQAAAA==.Alexithorn:BAAANQABCgUIBQAAAA==.Allila:BAAANQAECgIIAgAAAA==.',
Am='Ambrozyn:BAAANQADCgMIAwAAAA==.',
An='Anarariellea:BAAANQADCggIDgAAAA==.',
Aq='Aqari:BAAANQADCgQIBgAAAA==.',
Ar='Ardrelar:BAAANQADCgYIDQAAAA==.',
As='Asila:BAAANQADCgIIAgAAAA==.Astraea:BAAANQADCggIFAABNQADCggIGQABAAAAAA==.',
At='Athika:BAAANQADCgEIAQAAAA==.',
Au='Auria:BAAANQADCgEIAQABNQADCgQIBgABAAAAAA==.Autumnal:BAAANQADCgQIBAAAAA==.',
Az='Azralia:BAAANQAECgIIAgAAAA==.',
Bb='Bbygee:BAAANQADCgUIBQAAAA==.',
Be='Benjamin:BAAANQAECgMIAwAAAA==.Beyblade:BAAANQADCgQIBgAAAA==.',
Bl='Blacksun:BAAANQAECgIIAwAAAA==.Blazinember:BAAANQAECgQIBAAAAA==.',
Bo='Bolonmixto:BAAANQAECggIEAAAAA==.Boop:BAAANQADCggIEwABNQADCggIJwABAAAAAA==.Borghamer:BAAANQADCgYICwAAAA==.Borimor:BAAANQADCgUICQABNQAECgQIBAABAAAAAA==.',
Br='Bromkin:BAAANQADCgYIDQAAAA==.',
Ca='Calinor:BAAANQADCgMIBgAAAA==.Callihunt:BAAANQADCgYICAAAAA==.Calliopeh:BAAANQADCggIDwAAAA==.',
Ce='Cedriq:BAAANQAECgEIAgAAAA==.Ceran:BAAANQAECgIIAgAAAA==.Cereus:BAAANQAECgYICAAAAA==.',
Ch='Chaelenge:BAAANQADCgcIFAAAAA==.Chasatail:BAAANQADCgcICAAAAA==.Chyran:BAAANQADCgcIEQAAAA==.',
Co='Coloratura:BAAANQAECgMIAwAAAA==.',
Cr='Crimsonmoon:BAAANQADCggICAABNQADCggIJwABAAAAAA==.',
Da='Dagethon:BAAANQADCgQIBgAAAA==.Danyah:BAAANQADCgUIBQABNQAECgYICAABAAAAAA==.Darkshådow:BAAANQADCgUIBwAAAA==.',
De='Denvoker:BAAANQADCgEIAQAAAA==.',
Di='Dissension:BAAANQADCggIDQAAAA==.',
Do='Doubtfire:BAAANQADCgcIEgAAAA==.',
Ed='Edelia:BAAANQAECgYIDAABNQAECgUICQABAAAAAA==.',
El='Elek:BAAANQADCgEIAQAAAA==.',
Er='Eraessyr:BAAANQADCgQIBAAAAA==.',
Fa='Fabin:BAAANQADCgEIAQAAAA==.Faithfulness:BAAANQAECgEIAQAAAA==.Fangz:BAAANQADCgcIEQAAAA==.',
Fr='Freakadeëk:BAAANQADCgQIBAAAAA==.Frierenn:BAAANQAECgIIAgAAAA==.Frosh:BAAANQADCgMIAwAAAA==.',
Gh='Ghouldottie:BAAANQADCgIIAgAAAA==.',
Gi='Gilidar:BAAANQAECgIIAgAAAA==.',
Gn='Gnomerdenis:BAAANQADCgYICAAAAA==.',
Go='Goochiemon:BAAANQADCgUIDAAAAA==.',
Gr='Grimmberly:BAAANQAECgMIAwAAAA==.',
Gu='Guthunnel:BAAANQADCggIDgAAAA==.Gutshadra:BAAANQADCggIDQAAAA==.',
Ha='Haides:BAAANQADCgQIBAAAAA==.Hairybum:BAAANQABCgIIAgAAAA==.Halanji:BAAANQADCgUIBQAAAA==.Hannibow:BAAANQADCgQIBgAAAA==.',
He='Hellgrim:BAAANQADCgMIAQABNQAECgMIAwABAAAAAA==.',
Ho='Hoawatt:BAAANQADCgQICQAAAA==.',
Hu='Huuch:BAAANQADCgcIBwAAAA==.',
Ig='Ignee:BAAANQAECgYICAAAAA==.Ignia:BAAANQADCggIEgAAAA==.',
Ir='Iremoon:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.',
Ji='Jiyao:BAAANQAECgQIBQAAAA==.',
Jo='Jodi:BAEANQAECgEIAQAAAA==.',
Ka='Kaceya:BAAANQADCgYICAAAAA==.Katarinea:BAAANQADCgYIBwAAAA==.',
Kh='Khalessie:BAAANQAECgIIAgAAAA==.',
Kl='Klorick:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.',
Ku='Kungfudru:BAAANQADCgQIBQAAAA==.',
Kw='Kwai:BAAANQADCgQIBQABNQAECgQIBAABAAAAAA==.',
Li='Lineofsight:BAAANQAECgEIAQAAAA==.Lipa:BAAANQADCgEIAQAAAA==.Liths:BAAANQAECgEIAQAAAA==.',
Lo='Loko:BAAANQABCgIIAgAAAA==.',
Lu='Lululuvely:BAAANQADCgYIDAAAAA==.',
['Lí']='Lív:BAAANQADCgMIAwAAAA==.',
Ma='Magejacob:BAAANQADCgYIDAAAAA==.Malendren:BAAANQABCgQIBAAAAA==.Margot:BAAANQAECgEIAQAAAA==.Marksmann:BAAANQABCgIIAgAAAA==.Mawhriccio:BAAANQADCggICgAAAA==.',
Mc='Mcdavé:BAAANQAECgEIAQAAAA==.',
Me='Meerclar:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.Melaila:BAAANQADCggIGQAAAA==.',
Mi='Mistymay:BAAANQADCgYICwAAAA==.',
Mo='Moldthinur:BAAANQADCggIEwAAAA==.Mongrol:BAAANQADCgUIDAAAAA==.Monôpolyguy:BAAANQADCgQIBwAAAA==.Moonowl:BAAANQADCgQICQAAAA==.',
Mu='Mummrakhan:BAAANQADCgYICwAAAA==.Murraya:BAAANQADCgMIAwAAAA==.',
Na='Naniel:BAAANQAECgUICwAAAA==.Nazgrefry:BAAANQAECgYIBgAAAA==.',
Ne='Neb:BAAANQAECgQIBQAAAA==.Necroy:BAAANQAECgQICQAAAA==.',
Ni='Niccee:BAAANQAECgIIAgAAAA==.',
No='Noggindeez:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.Noodles:BAAANQAECgMIAwAAAA==.',
Nu='Numerouno:BAAANQAECgEIAQAAAA==.',
['Nî']='Nîtara:BAAANQADCgEIAQAAAA==.',
Oo='Ookthron:BAAANQAECgIIAgAAAA==.',
Pa='Parky:BAAANQADCgEIAQAAAA==.',
Pe='Percival:BAAANQAECgIIAgAAAA==.',
Ph='Phreakadeek:BAAANQADCgcIDgABNQAECgEIAQABAAAAAA==.',
Pi='Pinheadgarry:BAAANQADCgIIAgAAAA==.Pizzaslice:BAAANQADCggIJwAAAA==.',
Pr='Praxiscannon:BAAANQADCgcIDQAAAA==.',
Pu='Pumpshire:BAAANQADCggIDgAAAA==.',
Pw='Pwongo:BAAANQAECgMIAwAAAA==.',
Qt='Qt:BAAANQAFFAIIAgAAAA==.',
Qu='Queue:BAAANQABCgQIBgAAAA==.Quilten:BAAANQADCgYIDQAAAA==.',
Ra='Raenii:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.Ramoth:BAAANQADCgYICwAAAA==.Razelda:BAAANQADCgYICQAAAA==.',
Rh='Rhodas:BAAANQADCggIDQABNQAECgIIAwABAAAAAA==.',
Ri='Riandras:BAAANQADCgQIBAAAAA==.',
Ro='Roadwanderer:BAAANQADCgMIAwAAAA==.Robbiedrake:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Robbiemonk:BAAANQAECgQIBQAAAA==.',
Ru='Runetottem:BAAANQAECgIIAgAAAA==.',
Rx='Rxeight:BAAANQADCgQIBAAAAA==.',
Sa='Sakura:BAAANQADCgIIAgAAAA==.Samarii:BAAANQADCgQICgAAAA==.Sannith:BAAANQAECgEIAQAAAA==.',
Sc='Scyllia:BAAANQAECgMIBQAAAA==.Scârlett:BAEANQADCgEIAQABNQAECgEIAQABAAAAAA==.',
Sh='Shamanoodles:BAAANQADCgcIEgABNQADCggIGQABAAAAAA==.Shespawn:BAAANQADCgYIBgAAAA==.Shurie:BAAANQAECgQIBAAAAA==.Shâdê:BAAANQAECgEIAQAAAA==.',
Sl='Slipperybop:BAAANQAFFAEIAQABNQAECgQIBgABAAAAAA==.Slugbow:BAAANQADCgUIBQAAAA==.',
Sn='Snoroll:BAAANQADCgQICgAAAA==.',
So='Soldanis:BAAANQABCgEIAQAAAA==.',
Sp='Spazoff:BAAANQADCgYICgAAAA==.Spyman:BAAANQADCgYICgAAAA==.',
Sq='Squissh:BAAANQAECgQIBAABNQAECgQIBAABAAAAAA==.',
Sr='Srhubbabubba:BAAANQAECgEIAQAAAA==.',
St='Sternn:BAAANQADCgUIBgAAAA==.Straif:BAAANQADCgQICgAAAA==.Strawberrÿ:BAAANQAECgUICQAAAA==.',
Sw='Swolman:BAAANQADCgIIAgAAAA==.',
Sy='Sydonai:BAAANQADCggIBgAAAA==.Syreithada:BAAANQADCgIIAgAAAA==.',
Ta='Talathra:BAAANQAECgMIAwAAAA==.',
Te='Teddy:BAAANQADCggIDgAAAA==.Tellah:BAAANQADCgQIBAABNQAECgYIEAABAAAAAA==.',
Th='Thegodofwar:BAAANQAECgIIAwAAAA==.',
Ti='Tivon:BAAANQADCgYIDwAAAA==.',
Tw='Twomz:BAAANQADCgYIBgAAAA==.',
Um='Umi:BAAANQADCgQIBAABNQAECgcIDwABAAAAAA==.',
Va='Varkbyte:BAAANQADCgQIBQAAAA==.Varock:BAAANQADCggICAABNQADCggIJwABAAAAAA==.',
Vi='Viz:BAAANQADCgIIAgAAAA==.',
Vr='Vraul:BAAANQAECgIIAgAAAA==.',
Vu='Vulpain:BAAANQADCgYIBgABNQADCggIJwABAAAAAA==.',
Vv='Vvnth:BAAANQADCgUIBQAAAA==.',
Wh='Whiteangel:BAAANQADCgIIAgAAAA==.',
Wi='Wickedgood:BAAANQADCgQIBQAAAA==.',
Wo='Wolfowl:BAAANQADCgMIBgAAAA==.',
Xa='Xaela:BAAANQADCggIFQAAAA==.',
Xi='Xiabal:BAAANQAECgIIAgAAAA==.',
Xw='Xweekling:BAAANQAECgMIBgAAAA==.',
Yo='Yonnà:BAAANQAECgMIBAAAAA==.Yoshirou:BAAANQADCgIIAgAAAA==.',
Yu='Yuxiong:BAAANQADCgIIAgAAAA==.',
Ze='Zedra:BAEANQADCggIDAABNQAECgEIAQABAAAAAA==.Zerostar:BAAANQADCgUIDAABNQAECgYICAABAAAAAA==.',
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
