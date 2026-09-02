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
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-09-01',data={Ae='Aelita:BAAANQAECgEIAQAAAA==.',
Ag='Agarne:BAAANQADCgUIAQAAAA==.',
Ak='Akhta:BAAANQAECgEIAQAAAA==.',
Al='Allaris:BAAANQADCggIDgAAAA==.Allíesin:BAAANQADCgEIAQAAAA==.Altryn:BAAANQABCgQIBAAAAA==.Alundrablaze:BAAANQAECgMIBAAAAA==.',
Am='Amarixa:BAAANQADCgIIAgABNQADCgYICQABAAAAAA==.',
An='Anoint:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.',
Ar='Aranthino:BAAANQADCggIDQAAAA==.Arnzul:BAAANQADCgcIDQAAAA==.Aryabhatta:BAAANQADCggIDgAAAA==.',
As='Asakura:BAAANQADCgYICAAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.',
Ba='Bamdk:BAAANQAECgQIBAAAAA==.Bamshambam:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Baoshengdadi:BAAANQADCgMIAwABNQADCgcICgABAAAAAA==.',
Be='Beansfu:BAAANQADCggIDQABNQAECgQIBAABAAAAAA==.Beansinator:BAAANQAECgQIBAAAAA==.Beefsupriem:BAAANQADCggIDgAAAA==.Bellatrïx:BAAANQADCgYICQABNQADCgEIAQABAAAAAA==.Belliaz:BAAANQADCgYICQAAAA==.',
Bi='Bialar:BAAANQADCgEIAQAAAA==.',
Bl='Bloodwell:BAAANQAECgIIAgAAAA==.',
Br='Bruzera:BAAANQADCgUIBQAAAA==.',
Bu='Bulldan:BAAANQADCggIDgAAAA==.Buzrkk:BAAANQADCgQIAwAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
Ca='Candyquartz:BAAANQADCgUIBQAAAA==.Captaïn:BAAANQADCgYIBgAAAA==.',
Ce='Celladorne:BAAANQADCgQICAAAAA==.',
Ch='Chibi:BAAANQADCgYIDAAAAA==.Chronokite:BAAANQADCggIDgAAAA==.',
Cl='Clawburr:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.Clelronah:BAAANQADCgYIBwAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQADCggIDgABAAAAAA==.',
Da='Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAAANQAECgMIAwAAAA==.',
De='Deader:BAAANQADCgMIAwAAAA==.Demonslice:BAAANQADCgUIBQAAAA==.Dentarus:BAAANQADCggICAAAAA==.',
Di='Divinewords:BAAANQADCgQIBAABNQADCgYICAABAAAAAA==.Divish:BAAANQADCgIIAgAAAA==.',
Do='Donhector:BAAANQAECgIIAgAAAA==.Dontsheep:BAAANQADCgEIAQAAAA==.',
Dr='Druecc:BAAANQADCggIDgAAAA==.Druidlord:BAAANQADCgUIAQAAAA==.',
['Då']='Dågon:BAAANQADCgYIBgAAAA==.',
Er='Era:BAAANQADCgUICAAAAA==.',
Fa='Farty:BAAANQADCgYICgAAAA==.',
Fo='Fortytwö:BAAANQADCgUIAQAAAA==.Foutre:BAAANQADCgYIDAAAAA==.',
Fr='Fruntstabba:BAAANQADCgUIBQAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBAAAAA==.Fungus:BAAANQAECgYICgAAAA==.Fuzzytotems:BAAANQADCgYICQAAAA==.',
Fy='Fynnick:BAAANQADCggIDgAAAA==.',
Ga='Galgar:BAAANQADCggIDAAAAA==.',
Ge='Getlnmyvan:BAAANQAECgEIAQAAAA==.',
Gh='Ghoulgranny:BAAANQADCgYIBgAAAA==.',
Gl='Glert:BAAANQADCgUIBQAAAA==.',
Go='Goinsolo:BAAANQAECgMIAwAAAA==.Gorvax:BAAANQADCggIDgAAAA==.',
Gr='Grimlóck:BAAANQADCggIBgAAAA==.Grumok:BAAANQABCgEIAQAAAA==.',
Gw='Gwenledyr:BAAANQAECgMIAwAAAA==.',
Ha='Hallebearie:BAAANQADCgYICQABNQADCgIIAgABAAAAAA==.',
He='Hekus:BAEANQAECgQIBAAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAAANQAECgYICwAAAA==.',
Hu='Hukari:BAAANQADCgQIBAABNQAECgcIDAABAAAAAA==.',
Ii='Iiambloody:BAAANQADCgQIBAAAAA==.Iil:BAAANQADCgQIBwAAAA==.',
Iq='Iqsamurai:BAAANQABCgQIBAAAAA==.',
Ja='Jaxxia:BAAANQADCgUICgABNQAECgIIAgABAAAAAA==.',
Jb='Jblaze:BAAANQADCggIDgAAAA==.',
Jh='Jhalicistu:BAAANQADCggIDgAAAA==.',
Ju='Juzomido:BAAANQAECgYICQAAAA==.',
['Jã']='Jãina:BAAANQAECgYICgAAAA==.',
Ka='Kaijhin:BAAANQADCgcIDgAAAA==.Kaline:BAAANQADCgYIBgAAAA==.Katianna:BAAANQAECgMIAwAAAA==.',
Ke='Keallach:BAAANQAECgEIAQAAAA==.Kelanath:BAAANQADCgYIDAAAAA==.',
Kh='Khalli:BAAANQAECgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.',
Ki='Kiffprime:BAAANQADCgUIBQAAAA==.Kittycatlj:BAAANQADCgEIAQAAAA==.Kiyosara:BAAANQADCgYIBgAAAA==.',
Kr='Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQADCgUIBAAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQADCgMIBQAAAA==.',
Li='Lightjohn:BAAANQADCgEIAQAAAA==.',
Lo='Lovemarauder:BAAANQADCgYIBgAAAA==.',
Ma='Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAAANQADCggICAAAAA==.Malganon:BAAANQADCgYIDAAAAA==.Martheiran:BAAANQADCggICAAAAA==.Mathelmana:BAAANQADCggIDgABNQAECgMIBAABAAAAAA==.Mawika:BAAANQADCgMIAwAAAA==.',
Me='Mechafour:BAAANQADCgYIBgAAAA==.',
Mi='Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAAANQAECgUIBwAAAA==.Missfrost:BAAANQADCgMIAwAAAA==.',
Mo='Moreblood:BAAANQADCgcIDAAAAA==.Morghella:BAAANQADCggIDgAAAA==.Morhsa:BAAANQABCgMIAwAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mythros:BAAANQADCggICAAAAA==.',
No='Noirra:BAAANQAECgQIBQAAAA==.',
Om='Omusa:BAAANQADCgQIBAAAAA==.',
Or='Orcnick:BAAANQADCgcIDgAAAA==.',
Ov='Overfrosty:BAAANQADCggIDgAAAA==.',
Oz='Ozaí:BAAANQADCgEIAQAAAA==.',
Pu='Purgedfire:BAAANQADCgUIBwAAAA==.',
Ra='Ravon:BAAANQADCgcIBgAAAA==.Rayda:BAAANQADCgYICgAAAA==.',
Re='Reighan:BAAANQADCgUIBQAAAA==.Renka:BAAANQAECgEIAQAAAA==.Revolting:BAAANQAECgYICAAAAA==.',
Ri='Rianne:BAAANQADCgYICgAAAA==.',
Ro='Rowanbow:BAAANQADCgUICAAAAA==.',
Sa='Saberhawk:BAAANQADCgMIAwAAAA==.Sakurazuka:BAAANQADCgUIAQAAAA==.Sanath:BAAANQAECgEIAQAAAA==.Sardenn:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAAANQADCggIDgAAAA==.',
Sg='Sgtmoose:BAAANQADCgYICAAAAA==.',
Sh='Shabamzoo:BAAANQADCgEIAQAAAA==.Shadeswift:BAAANQADCgYIBgAAAA==.Shadowhart:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Sharindlar:BAAANQADCgcICgAAAA==.Shokanu:BAAANQAECgIIAgAAAA==.',
Si='Sib:BAAANQADCgYIBgAAAA==.Silverlight:BAAANQAECgQIBgABNQADCgYIDAABAAAAAA==.',
Sk='Skeets:BAAANQADCgYICAAAAA==.',
Sm='Smolgoblin:BAAANQADCgYIBgAAAA==.',
Sn='Snakie:BAAANQADCgYICgAAAA==.',
So='Sokorag:BAAANQAECgEIAQAAAA==.Soulsnack:BAAANQADCggIDwAAAA==.',
Sp='Spedspidspud:BAAANQADCggICAAAAA==.',
St='Starrbuck:BAAANQADCggIDgAAAA==.Stryke:BAAANQADCgUICAAAAA==.',
Su='Suterareta:BAAANQADCgUIAQAAAA==.',
Sy='Synderella:BAAANQAECgQIBgAAAA==.',
['Sï']='Sïntaxerror:BAAANQADCgYIDAAAAA==.',
Ta='Taksun:BAAANQADCgYIDAAAAA==.Tanaka:BAAANQADCgYICAAAAA==.Tandy:BAAANQAECgIIBAAAAA==.Tauntindeath:BAAANQAECgEIAQAAAA==.Tav:BAAANQAECgMIAwAAAA==.',
Th='Thaladrin:BAAANQADCgUICAAAAA==.Thalard:BAAANQADCgYICAAAAA==.',
Ti='Tidebloom:BAAANQADCgcIBwAAAA==.',
To='Tokens:BAAANQADCgEIAQAAAA==.Toohottotrot:BAAANQADCgUIBQAAAA==.Torrent:BAAANQAECgQIBQAAAA==.',
Tr='Trixxe:BAAANQAECgQIBgAAAA==.Trojaan:BAAANQABCgEIAQAAAA==.Trostani:BAAANQABCgEIAQAAAA==.Trulisha:BAAANQAECgQICAAAAA==.Trurala:BAAANQADCgUIBwAAAA==.',
Ty='Tyleinthrel:BAAANQADCgIIAgAAAA==.',
Ur='Ursalaisis:BAAANQADCgEIAQAAAA==.',
Va='Vacum:BAAANQADCgYICgAAAA==.Vaderon:BAAANQADCgMIBAAAAA==.Vayine:BAAANQADCgYIDAAAAA==.',
Ve='Venmo:BAAANQADCgIIAgABNQADCggIDgABAAAAAA==.',
Vi='Visenya:BAAANQADCgUIBQAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAECgYIDQABAAAAAA==.',
Vu='Vuskar:BAAANQADCgcIDQAAAA==.',
Wa='Warpaths:BAAANQADCgYIDAAAAA==.',
Wi='Wigglyears:BAAANQAECgEIAQAAAA==.',
Wo='Wombat:BAAANQAECgYIBAABNQAECgcICQABAAAAAA==.',
Xa='Xanalluna:BAAANQADCggIEAAAAA==.Xanvarani:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.',
Ya='Yakushimaru:BAAANQADCgcIDQAAAA==.',
Ze='Zefren:BAAANQAECgMIBAAAAA==.',
Zi='Zildon:BAAANQADCgYICAAAAA==.',
Zu='Zurik:BAAANQAECgcIDAAAAA==.',
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
