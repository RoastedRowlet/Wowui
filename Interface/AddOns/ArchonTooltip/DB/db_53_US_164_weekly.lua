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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Shaman-Elemental','Shaman-Restoration',}
local provider = {region='US',realm='Nazgrel',name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Adicia:BAAANQADCgQIBAAAAA==.',
Ae='Aedercy:BAAANQABCgcICwAAAA==.Aestel:BAAANQABCgYIBQAAAA==.',
Al='Alarus:BAAANQADCgQIAQAAAA==.Alexithorn:BAAANQABCgUIBQAAAA==.Allila:BAAANQAECgMIBQAAAA==.',
Am='Ambrozyn:BAAANQADCgUICAAAAA==.',
An='Anarariellea:BAAANQADCggIDgAAAA==.',
Ap='Apalrapzz:BAAANQADCgIIAgABNQADCgcIHQABAAAAAA==.',
Aq='Aqari:BAAANQADCgYIDAAAAA==.',
Ar='Ardrelar:BAAANQADCgcIFAAAAA==.',
As='Asila:BAAANQADCgIIAgAAAA==.Astraea:BAAANQADCggIGwABNQADCggIIQABAAAAAA==.',
At='Athika:BAAANQADCgUIBQAAAA==.',
Au='Auria:BAAANQADCgEIAQABNQADCgYIDAABAAAAAA==.Autumnal:BAAANQADCgQIBgAAAA==.',
Az='Azralia:BAAANQAECgMIBQAAAA==.',
Bb='Bbygee:BAAANQADCgUIBQAAAA==.',
Be='Benjamin:BAAANQAECggIEQAAAA==.Beyblade:BAAANQADCgQIBgAAAA==.',
Bl='Blacksun:BAAANQAECgIIAwAAAA==.Blazinember:BAAANQAECgUICQAAAA==.',
Bo='Bolonmixto:BAABNQAECoEZAAICAAkJPB4QBAAsAwACAAkJPB4QBAAsAwAAAA==.Boop:BAAANQADCggIGwABNQAECgIIAgABAAAAAA==.Borghamer:BAAANQADCggIDQAAAA==.Borimor:BAAANQADCgUICQABNQAECgYICgABAAAAAA==.',
Br='Bromkin:BAAANQADCggIDwAAAA==.',
['Bë']='Bëorn:BAAANQAECgYIBgABNQAECgYICgABAAAAAA==.',
Ca='Calinor:BAAANQADCgUICwAAAA==.Callihunt:BAAANQADCgYICAAAAA==.Calliopeh:BAAANQADCggIDwAAAA==.',
Ce='Cedriq:BAAANQAECgEIAgAAAA==.Ceran:BAAANQAECgIIBAAAAA==.Cereus:BAAANQAECgYIDgAAAA==.',
Ch='Chaelenge:BAAANQAECgIIAgAAAA==.Chasatail:BAAANQADCgcICAAAAA==.Chyran:BAAANQAECgEIAQAAAA==.',
Co='Coloratura:BAAANQAECgQIBwAAAA==.',
Cr='Crimsonmoon:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
Da='Dagethon:BAAANQADCgUICwAAAA==.Danyah:BAAANQADCgUIBQABNQAECgYIDgABAAAAAA==.Darkshådow:BAAANQADCgYICAAAAA==.',
De='Deathangels:BAAANQADCgQIBAAAAA==.Denvoker:BAAANQADCgEIAQAAAA==.',
Di='Dissension:BAAANQAECgEIAQAAAA==.',
Do='Doubtfire:BAAANQADCgcIHQAAAA==.',
Dr='Dragii:BAAANQADCgYIBgAAAA==.',
Ed='Edelia:BAAANQAECgYIDAABNQAECgcIEAABAAAAAA==.',
El='Elek:BAAANQADCgEIAQAAAA==.',
Er='Eraessyr:BAAANQADCgQIBAAAAA==.',
Fa='Fabin:BAAANQADCgEIAQAAAA==.Faithfulness:BAAANQAECgQIBQAAAA==.Fangz:BAAANQAECgEIAQAAAA==.',
Fr='Freakadeëk:BAAANQADCgQIBAAAAA==.Frierenn:BAAANQAECgQIBgAAAA==.Frosh:BAAANQADCgMIAwAAAA==.',
Gh='Ghouldottie:BAAANQADCgIIAgAAAA==.',
Gi='Gilidar:BAAANQAECgQIBgAAAA==.',
Gn='Gnomerdenis:BAAANQADCgcICQAAAA==.',
Go='Goochiemon:BAAANQADCgcIDgAAAA==.',
Gr='Grimmberly:BAAANQAECgQIBwAAAA==.',
Gu='Guthunnel:BAAANQADCggIDgAAAA==.Gutshadra:BAAANQADCggIDgAAAA==.',
Ha='Haides:BAAANQADCgQIBAAAAA==.Hairybum:BAAANQABCgIIAgAAAA==.Halanji:BAAANQADCgUIBQAAAA==.Hannibow:BAAANQADCgQIBgAAAA==.',
He='Hellgrim:BAAANQADCgMIAQABNQAECgQIBwABAAAAAA==.',
Ho='Hoawatt:BAAANQADCgYIDwAAAA==.Holynova:BAAANQADCgQIBAABNQAECgMIBAABAAAAAA==.',
Hu='Huuch:BAAANQAECgMIAwAAAA==.',
Ig='Ignee:BAAANQAECgYIDgAAAA==.Ignia:BAAANQADCggIFgABNQAECgEIAQABAAAAAA==.',
Ir='Iremoon:BAAANQAECgMIBAABNQAECgUICgABAAAAAA==.',
Ji='Jiyao:BAAANQAECgUICgAAAA==.',
Ka='Kaceya:BAAANQADCgYICAAAAA==.Katarinea:BAAANQAECgIIAgAAAA==.',
Ke='Ketrus:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Kh='Khalessie:BAAANQAECgQIBgAAAA==.',
Ki='Killim:BAAANQADCgYIBgAAAA==.',
Kl='Klorick:BAAANQAECgYIBgABNQAECgYICgABAAAAAA==.',
Ku='Kungfudru:BAAANQADCgQIBQAAAA==.',
Kw='Kwai:BAAANQADCgQIBQABNQAECgYICgABAAAAAA==.',
Li='Lineofsight:BAAANQAECgEIAgAAAA==.Lipa:BAAANQADCgEIAQAAAA==.Liths:BAAANQAECgMIBAAAAA==.',
Lo='Loko:BAAANQADCgEIAQAAAA==.',
Lu='Lululuvely:BAAANQADCgYIDAAAAA==.',
['Lí']='Lív:BAAANQADCgMIAwAAAA==.',
Ma='Madelyn:BAAANQADCgUIBQAAAA==.Magejacob:BAAANQADCgYIDgAAAA==.Malendren:BAAANQABCgQIBAAAAA==.Margot:BAAANQAECgEIAQAAAA==.Marksmann:BAAANQABCgIIAgAAAA==.Mawhriccio:BAAANQADCggICgAAAA==.',
Mc='Mcdavé:BAAANQAECgMIBAAAAA==.',
Me='Meerclar:BAAANQADCgYIBgAAAA==.Melaila:BAAANQADCggIIQAAAA==.',
Mi='Micheal:BAAANQAECggICAAAAA==.Mistymay:BAAANQADCgYICwAAAA==.',
Mo='Moldthinur:BAAANQADCggIGwAAAA==.Mongrol:BAAANQADCgUIDAAAAA==.Monôpolyguy:BAAANQADCgYIDQAAAA==.Moonowl:BAAANQADCgUIDgAAAA==.',
Mu='Mummrakhan:BAAANQADCgYIEQAAAA==.Murraya:BAAANQADCgMIAwAAAA==.',
My='Mythdalkurim:BAAANQADCgMIBgAAAA==.',
Na='Naniel:BAAANQAECgYIEQAAAA==.Nazgrefry:BAAANQAECgYIBgAAAA==.',
Ne='Neb:BAAANQAECgUICgAAAA==.Necroy:BAAANQAECgQICQAAAA==.',
Ni='Niccee:BAAANQAECgIIBAAAAA==.',
No='Noggindeez:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Noodles:BAAANQAECgQIBwAAAA==.Nosebleeds:BAAANQADCgcIBwAAAA==.',
Nu='Numerouno:BAAANQAECgMIBAAAAA==.',
['Nî']='Nîtara:BAAANQADCgEIAQAAAA==.',
Oo='Ookthron:BAAANQAECgIIBAAAAA==.',
Oz='Ozempic:BAAANQADCgUIBQAAAA==.',
Pa='Papasmurff:BAAANQADCgYIBgAAAA==.Parachute:BAAANQADCgcIBwAAAA==.Parky:BAAANQADCgUIBgAAAA==.',
Pe='Percival:BAAANQAECgIIBAAAAA==.',
Ph='Phreakadeek:BAAANQADCgcIDgABNQAECgIIAwABAAAAAA==.',
Pi='Pinheadgarry:BAAANQADCgIIAgAAAA==.Pizzaslice:BAAANQAECgIIAgAAAA==.',
Pr='Praxiscannon:BAAANQAECgMIAwAAAA==.',
Pu='Pumpshire:BAAANQAECgYIBgAAAA==.',
Pw='Pwongo:BAAANQAECgQICAAAAA==.',
Qt='Qt:BAABNQAECoEeAAIDAAkJaR1xDwANAwADAAkJaR1xDwANAwAAAA==.',
Qu='Queue:BAAANQADCgUIAgAAAA==.Quilten:BAAANQADCgYIEgAAAA==.',
Ra='Raenii:BAAANQAECgQIBwABNQAECgcIEAABAAAAAA==.Ramoth:BAAANQADCgcIEAAAAA==.',
Rh='Rhodas:BAAANQADCggIFAABNQAECgMIBAABAAAAAA==.',
Ri='Riandras:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.',
Ro='Roadwanderer:BAAANQADCgMIAwAAAA==.Robbiedrake:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Robbiemonk:BAAANQAECgYICwAAAA==.',
Ru='Runetottem:BAAANQAECgIIBAAAAA==.',
Rx='Rxeight:BAAANQADCgQIBAAAAA==.',
Sa='Sakura:BAAANQADCgIIAgAAAA==.Samarii:BAAANQADCgYIEAAAAA==.Sannith:BAAANQAECgMIBAAAAA==.',
Sc='Scyllia:BAAANQAECgYICwAAAA==.Scârlett:BAEANQADCgUIBgABNQAECgEIAQABAAAAAA==.',
Sh='Shamanoodles:BAAANQADCgcIEgABNQADCggIIQABAAAAAA==.Shespawn:BAAANQADCgYIBgAAAA==.Shurie:BAAANQAECgYICgAAAA==.Shâdê:BAAANQAECgMIBAAAAA==.',
Sl='Slipperybop:BAAANQAFFAEIAQABNQAECgQICQABAAAAAA==.Slugbow:BAAANQADCgUIBQAAAA==.',
Sn='Snazzlehorn:BAAANQADCggIHAAAAA==.Snoroll:BAAANQADCgUICwAAAA==.',
So='Soldanis:BAAANQABCgEIAQAAAA==.',
Sp='Spazoff:BAAANQADCggIEQAAAA==.Spyman:BAAANQADCgYICgAAAA==.',
Sq='Squissh:BAAANQAECgQIBAABNQAECgYICgABAAAAAA==.',
Sr='Srhubbabubba:BAAANQAECgMIBAAAAA==.',
St='Sternn:BAAANQADCgcIDQAAAA==.Straif:BAAANQADCgYIDgAAAA==.Strawberrÿ:BAAANQAECgYIDwAAAA==.',
Sw='Swolman:BAAANQADCgIIAgAAAA==.',
Sy='Sydonai:BAAANQADCggIBgAAAA==.Syreithada:BAAANQADCgIIAgAAAA==.',
Ta='Talathra:BAAANQAECgQIBQAAAA==.',
Te='Teddy:BAAANQADCggIDgAAAA==.Tellah:BAAANQADCgQIBAABNQAECggIGwAEAAggAA==.',
Th='Thegodofwar:BAAANQAECgMIBAAAAA==.',
Ti='Tivon:BAAANQADCgcIFgAAAA==.',
Tw='Twomz:BAAANQADCgYIBgAAAA==.',
Um='Umi:BAAANQADCgQIBAABNQAECggIGgAEAGUhAA==.',
Va='Varkbyte:BAAANQADCgQIBQAAAA==.Varock:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
Vi='Vindication:BAAANQADCgUIBQAAAA==.Viz:BAAANQADCgQIBgAAAA==.',
Vr='Vraul:BAAANQAECgIIBAAAAA==.',
Vu='Vulpain:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Vv='Vvnth:BAAANQADCgUIBQAAAA==.',
Wh='Whiteangel:BAAANQADCgYICAAAAA==.',
Wi='Wickedgood:BAAANQADCgQIBQAAAA==.',
Wo='Wolfowl:BAAANQADCgUICwAAAA==.',
Xa='Xaela:BAAANQAECgIIAgAAAA==.',
Xi='Xiabal:BAAANQAECgIIBAAAAA==.',
Xw='Xweekling:BAAANQAECgQICgAAAA==.',
Yo='Yonnà:BAAANQAECgMIBAAAAA==.Yoshirou:BAAANQADCgIIAgAAAA==.Yourgrandma:BAAANQADCgcIBwAAAA==.',
Yu='Yuxiong:BAAANQADCgIIAgAAAA==.',
Ze='Zedra:BAEANQAECgEIAQAAAA==.Zedrâ:BAEANQADCggIDAABNQAECgEIAQABAAAAAA==.Zerostar:BAAANQADCgcIDgABNQAECgYIDgABAAAAAA==.',
['Ña']='Ñaman:BAAANQAECgEIAQAAAA==.',
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
