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

local lookup = {'Unknown-Unknown','Shaman-Elemental',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-09-08',data={Ae='Aelita:BAAANQAECgEIAgAAAA==.',
Ag='Agarne:BAAANQADCgcICAAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAAANQAECgQIBQAAAA==.',
Al='Allaris:BAAANQAECgIIAgAAAA==.Allíesin:BAAANQADCgYICQAAAA==.Altryn:BAAANQABCgQIBAAAAA==.Alundrablaze:BAAANQAECgQICAAAAA==.',
Am='Amarixa:BAAANQADCgQIBQABNQADCgYIDwABAAAAAA==.',
An='Anoint:BAAANQADCgQIBAABNQAECgcIEQABAAAAAA==.',
Ar='Aranthino:BAAANQAECgIIAgAAAA==.Arnzul:BAAANQADCgcIEgAAAA==.Aryabhatta:BAAANQAECgEIAQAAAA==.',
As='Asakura:BAAANQAECgYIBwAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.',
Ba='Bamdk:BAAANQAECgUICQAAAA==.Bamshambam:BAAANQAECgIIAwABNQAECgUICQABAAAAAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.',
Be='Beansfu:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.Beansinator:BAAANQAECgUICQAAAA==.Beefsupriem:BAAANQAECgIIAgAAAA==.Bellatrïx:BAAANQADCgYICQABNQADCgYICQABAAAAAA==.Belliaz:BAAANQADCgYIDwAAAA==.',
Bg='Bgwinnier:BAAANQADCgUIBQAAAA==.',
Bi='Bialar:BAAANQADCgYIBwAAAA==.Bigchéésé:BAAANQADCggICAAAAA==.',
Bl='Blackforge:BAAANQABCgMIAwAAAA==.Bloodwell:BAAANQAECgIIAgAAAA==.',
Bo='Bovinar:BAAANQADCgcIBwAAAA==.',
Br='Bruzera:BAAANQADCgUIBQAAAA==.',
Bu='Bulldan:BAAANQAECgIIAgAAAA==.Buzrkk:BAAANQADCgQIBAAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
Ca='Candyquartz:BAAANQADCgcIDAAAAA==.Captaïn:BAAANQAECgEIAQAAAA==.',
Ce='Celladorne:BAAANQADCgcIDwAAAA==.',
Cg='Cg:BAAANQAECgQIBAAAAA==.',
Ch='Chibi:BAAANQAECgEIAQAAAA==.Chrent:BAAANQAECgIIAgAAAA==.Chronokite:BAAANQAECgIIAgAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQADCgcIDAABAAAAAA==.Clelronah:BAAANQADCgYIBwAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgIIAgABAAAAAA==.',
Da='Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAAANQAECgUICAAAAA==.',
De='Deader:BAAANQADCgMIAwAAAA==.Demonseed:BAAANQADCgYIBgAAAA==.Demonslice:BAAANQADCgUICgAAAA==.Dentarus:BAAANQADCggICAAAAA==.',
Di='Disengage:BAAANQAECgEIAQAAAA==.Displace:BAAANQADCgcIBwAAAA==.Divinewords:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Divish:BAAANQADCggICAAAAA==.',
Do='Donhector:BAAANQAECgUIBwAAAA==.Dontsheep:BAAANQAECgEIAQAAAA==.Doubl:BAAANQAECgEIAQAAAA==.',
Dr='Drak:BAAANQADCgYIBgAAAA==.Druecc:BAAANQAECgIIAgAAAA==.Druidlord:BAAANQADCgcIBAAAAA==.',
Du='Dundalo:BAAANQADCgYIBgAAAA==.Duubee:BAAANQADCgMIAwAAAA==.',
['Då']='Dågon:BAAANQAECgEIAQAAAA==.',
El='Elchaman:BAAANQADCgMIBAAAAA==.Elcuh:BAAANQADCgMIAwAAAA==.',
Er='Era:BAAANQADCgYIDgAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Fa='Farty:BAAANQADCggIEgAAAA==.',
Fi='Fitua:BAAANQADCggICAAAAA==.',
Fo='Fortytwö:BAAANQADCgUIAQAAAA==.Foutre:BAAANQAECgIIAgAAAA==.',
Fr='Fruntstabba:BAAANQADCgcIDAAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAAANQAECggIEgAAAA==.Fuzzytotems:BAAANQADCgYIDwAAAA==.',
Fy='Fynnick:BAAANQADCggIEwAAAA==.',
Ga='Galgar:BAAANQADCggIFAAAAA==.',
Ge='Getlnmyvan:BAAANQAECgQIBQAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gl='Glert:BAAANQADCggIDQAAAA==.',
Go='Goinmonk:BAAANQADCgQIBAAAAA==.Goinsolo:BAAANQAECgYICQAAAA==.Gorvax:BAAANQAECgIIAgAAAA==.Gozz:BAAANQABCgQIBQAAAA==.',
Gr='Grimlóck:BAAANQADCggIDgAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAAANQAECgUICAAAAA==.Gwynhria:BAAANQADCggICAAAAA==.',
Ha='Hallebearie:BAAANQADCgYICQABNQADCgIIAgABAAAAAA==.',
He='Hekus:BAEANQAECgYICgAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAAANQAECgcIEQAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Hukari:BAAANQADCgQIBAABNQAFFAEIAQABAAAAAA==.',
Ic='Icelynn:BAAANQADCgcIBwABNQAFFAEIAQABAAAAAA==.',
Ii='Iiambloody:BAAANQADCgQIBAAAAA==.Iil:BAAANQADCgYIDQAAAA==.',
Iq='Iqsamurai:BAAANQABCgYIBgAAAA==.',
It='Itruszia:BAAANQADCgUIBQAAAA==.',
Ja='Jaxxia:BAAANQADCgcIEQABNQAECgIIAwABAAAAAA==.',
Jb='Jblaze:BAAANQADCggIGAAAAA==.',
Jh='Jhalicistu:BAAANQAECgEIAQAAAA==.',
Ju='Juzomido:BAAANQAECgcIEAAAAA==.',
['Jã']='Jãina:BAAANQAECggIEgAAAA==.',
Ka='Kaijhin:BAAANQAECgMIAwAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Katianna:BAAANQAECgUICAAAAA==.',
Ke='Keallach:BAAANQAECgIIAwAAAA==.Kelanath:BAAANQAECgIIAgAAAA==.',
Kh='Khalli:BAAANQAECgIIAwAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.',
Ki='Kiffprime:BAAANQADCgYICgAAAA==.Kittycatlj:BAAANQADCggICQAAAA==.Kiyosara:BAAANQADCgYIBgAAAA==.',
Kr='Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQADCggICgAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQADCgUICgAAAA==.',
La='Larde:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Li='Lightjohn:BAAANQADCgEIAQAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lovemarauder:BAAANQADCgYIBgAAAA==.',
Lu='Lunaari:BAAANQAECgIIAgAAAA==.Lurarind:BAAANQAECgIIAgAAAA==.',
Ma='Maeday:BAAANQADCgQIBAAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAAANQAECgMIAwAAAA==.Malganon:BAAANQADCggIEgAAAA==.Malygoz:BAAANQABCgQIBAABNQAECgcIEAABAAAAAA==.Martheiran:BAAANQAECgMIAwAAAA==.Mathelmana:BAAANQAECgIIAgABNQAECgQICAABAAAAAA==.Mawika:BAAANQADCgMIAwAAAA==.',
Me='Mechafour:BAAANQADCggIDgAAAA==.',
Mi='Miliandra:BAAANQADCgEIAQAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAAANQAECgUICwAAAA==.Missfrost:BAAANQADCgMIAwAAAA==.',
Mo='Moreblood:BAAANQAECgMIAwAAAA==.Morghella:BAAANQAECgQIBAAAAA==.Morhsa:BAAANQABCgMIAwAAAA==.Moána:BAAANQADCgMIAwAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mysticbrew:BAAANQAECgUIBQAAAA==.Mythros:BAAANQAECgEIAQAAAA==.',
Ni='Nightwitch:BAAANQADCgYIBgAAAA==.',
No='Noirra:BAAANQAECgYICwAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.',
Om='Omusa:BAAANQADCgQIBAAAAA==.',
Or='Orcnick:BAAANQADCgcIEQAAAA==.',
Ov='Overfrosty:BAAANQAECgIIAgAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQADCgMIBAAAAA==.',
Pe='Peng:BAAANQADCgMIAwAAAA==.Pesto:BAAANQADCgYICAAAAA==.',
Pi='Pinenuts:BAAANQABCgQIBgAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAAANQADCgUICQAAAA==.',
Ra='Ratings:BAAANQADCgUIBQAAAA==.Ravon:BAAANQAECgMIAwAAAA==.Rayda:BAAANQADCggIEgAAAA==.',
Re='Reighan:BAAANQADCgcIDAAAAA==.Renka:BAAANQAECgMIBAAAAA==.Revolting:BAAANQAECgcICwAAAA==.',
Ri='Rianne:BAAANQADCggIGAAAAA==.',
Ro='Rowanbow:BAAANQADCgUIDQAAAA==.',
Sa='Saberhawk:BAAANQADCgMIBgAAAA==.Sakurazuka:BAAANQADCgcICAAAAA==.Sanath:BAAANQAECgMIBAAAAA==.Sardenn:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAAANQAECgIIAgAAAA==.',
Se='Seal:BAAANQADCggICQABNQAECgYICwABAAAAAA==.',
Sg='Sgtmoose:BAAANQADCgcIDwAAAA==.',
Sh='Shabamzoo:BAAANQADCgEIAQAAAA==.Shadeswift:BAAANQADCgYICgAAAA==.Shadowhart:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Sharindlar:BAAANQAECgQIBAAAAA==.Shokanu:BAAANQAECgMIBQAAAA==.',
Si='Sib:BAAANQADCgYIBgAAAA==.Silverlight:BAAANQAECgQICAABNQADCgYIDAABAAAAAA==.',
Sk='Skeets:BAAANQADCgcIDAAAAA==.',
Sm='Smolgoblin:BAAANQADCgYIDgAAAA==.',
Sn='Snakie:BAAANQADCggIEgAAAA==.',
So='Sokorag:BAAANQAECgEIAQAAAA==.Soulsnack:BAAANQAECgQIBAAAAA==.',
Sp='Spedspidspud:BAAANQAECgQIBAAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Starrbuck:BAAANQAECgIIAgAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stryke:BAAANQADCgYIDgAAAA==.',
Su='Sunfury:BAAANQADCggIEAAAAA==.Suterareta:BAAANQADCgcICAAAAA==.',
Sy='Synderella:BAAANQAECgUICwAAAA==.',
['Sï']='Sïntaxerror:BAAANQADCgYIDAAAAA==.',
Ta='Taksun:BAAANQADCgcIEwAAAA==.Tanaka:BAAANQADCgcIEQAAAA==.Tandy:BAAANQAECgUIBwAAAA==.Tauntindeath:BAAANQAECgQIBQAAAA==.Tav:BAAANQAECgUICAAAAA==.',
Th='Thaladrin:BAAANQADCgYIDgAAAA==.Thalard:BAAANQADCgYIDQAAAA==.',
Ti='Tianara:BAAANQAECgMIAwAAAA==.Tidebloom:BAAANQADCggIDwAAAA==.',
To='Tokens:BAAANQADCgEIAQAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAAANQAECgYICwAAAA==.',
Tr='Trixxe:BAAANQAECgUICwAAAA==.Trojaan:BAAANQABCgEIAQAAAA==.Trostani:BAAANQABCgEIAQAAAA==.Trulisha:BAAANQAECgYIDwAAAA==.Trurala:BAAANQAECgIIAgAAAA==.',
Ty='Tyleinthrel:BAAANQADCgIIAgAAAA==.',
Ur='Ursalaisis:BAAANQADCgEIAQAAAA==.',
Va='Vacum:BAAANQADCgYICgAAAA==.Vaderon:BAAANQADCgMIBQAAAA==.Vandremont:BAAANQADCgMIAwAAAA==.Vayine:BAAANQAECgEIAQAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.',
Vi='Visenya:BAAANQADCgUIBQAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAECggIFgACAPsdAA==.',
Vu='Vuskar:BAAANQADCgcIDQAAAA==.',
Wa='Warpaths:BAAANQADCggIFAAAAA==.',
Wi='Wigglyears:BAAANQAECgQIBQAAAA==.',
Wo='Wombat:BAAANQAECggIBQAAAA==.',
Wr='Wreckoning:BAAANQADCgUIBQAAAA==.',
Xa='Xanadaria:BAAANQADCgEIAQABNQADCggIEAABAAAAAA==.Xanalluna:BAAANQADCggIEAAAAA==.Xanvarani:BAAANQADCggICwABNQADCggIEAABAAAAAA==.',
Ya='Yakushimaru:BAAANQAECgQIBAAAAA==.',
Yo='Yoonah:BAAANQADCgQICAAAAA==.',
Za='Zarella:BAAANQADCgEIAQAAAA==.',
Ze='Zefren:BAAANQAFFAEIAgAAAA==.',
Zi='Zildon:BAAANQADCgYIDQAAAA==.',
Zu='Zurik:BAAANQAFFAEIAQAAAA==.',
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
