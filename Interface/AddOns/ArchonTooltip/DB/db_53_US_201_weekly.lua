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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Mage-Arcane',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Aceroth:BAAANQAECgIIAwAAAA==.',
Ae='Aelin:BAAANQAECgYIDAAAAA==.Aerillidan:BAAANQAECgEIAQAAAA==.',
Al='Alestair:BAAANQAECgUIBwAAAA==.Alythra:BAAANQADCgcIBwAAAA==.',
Am='Amorsith:BAAANQAECgUIBgAAAA==.Ampluslues:BAAANQADCgMIAgAAAA==.',
An='Angelyna:BAAANQADCggICgAAAA==.Angrä:BAAANQADCggIEAAAAA==.',
Ar='Arakfalas:BAAANQADCggIDgAAAA==.Argentnox:BAAANQADCgUIBQABNQAECgUIDgABAAAAAA==.Argoz:BAAANQAECgQIBQAAAA==.Arrethyn:BAAANQADCgUIBQAAAA==.',
As='Asbell:BAAANQAECgUICgAAAA==.Aspectz:BAAANQABCgMIAwAAAA==.',
At='Atsidi:BAAANQAECgMIBAAAAA==.',
Ax='Axecutioner:BAAANQADCgYIDwAAAA==.',
Az='Azaelara:BAAANQAECgIIAwAAAA==.',
Ba='Badmojojojo:BAAANQAECgUIDgAAAA==.Bankhand:BAAANQAECgQIBQAAAA==.Bartab:BAAANQADCggIFAAAAA==.',
Be='Beefytotems:BAAANQAECgYICAABNQAECggICQABAAAAAA==.Benjamin:BAAANQAECgcIEgAAAA==.',
Bi='Bibistraz:BAAANQAECgQIBwAAAA==.',
Bl='Blitzkrîeg:BAAANQAECgQIBQAAAA==.',
Bo='Boeboe:BAAANQAECgIIAgAAAA==.Boomloomly:BAAANQAECgcIDwAAAA==.Borgymorgy:BAAANQADCgEIAQAAAA==.',
Br='Bruzande:BAAANQAECgUICgAAAA==.',
Bu='Bumbaweatuna:BAAANQADCgEIAQAAAA==.Burntt:BAAANQABCgMIBAAAAA==.Buttjeans:BAAANQAECgYICwAAAA==.',
Ca='Catastrophez:BAAANQADCgcIBwAAAA==.',
Ce='Celine:BAAANQAECgMIAwAAAA==.Ceo:BAAANQAECgEIAQAAAA==.',
Ch='Chickynuggy:BAAANQAECgEIAQAAAA==.Chillypickle:BAAANQAECgEIAQAAAA==.Christopher:BAAANQAECgcIEgAAAA==.Chronicbuds:BAAANQAECgQIBAAAAA==.',
Cl='Clyde:BAAANQADCgYIBgAAAA==.',
Co='Cobrakai:BAAANQADCggIEAAAAA==.Cochuata:BAAANQAECgUIDAAAAA==.',
Cr='Crabbypatty:BAAANQADCgcICwABNQABCgQIBAABAAAAAA==.Cripstaet:BAAANQABCgQIBAAAAA==.Crow:BAAANQADCgYICwAAAA==.',
Cu='Curse:BAAANQAECgQIBgABNQAECgYIEAABAAAAAA==.',
Da='Dairydefendr:BAAANQAECgIIBQAAAA==.Damyn:BAAANQAECgQICgAAAA==.',
De='Deathsgrace:BAAANQAECgIIAwAAAA==.Delia:BAAANQABCggIDgAAAA==.Demark:BAAANQAECgMIAwAAAA==.Demonicneon:BAAANQAECgIIAgAAAA==.Devana:BAAANQAECgUICgAAAA==.',
Di='Diddycated:BAEANQAECgUIBQABNQAECgcIDgABAAAAAA==.Dingus:BAAANQAECgQIBQAAAA==.',
Dk='Dk:BAAANQADCgYIDQABNQAECgYIEAABAAAAAA==.',
Do='Doode:BAAANQAECgYIDgAAAA==.Doody:BAAANQADCgYIEAABNQAECgYIDgABAAAAAA==.',
Dr='Dreastotems:BAAANQAECgEIAgAAAA==.Drennifer:BAAANQAECgIIAgAAAA==.',
Eb='Ebtyrone:BAAANQADCgQIBAAAAA==.',
Em='Emmerson:BAAANQADCgQIBQAAAA==.Emphasis:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.',
Fa='Fajitajones:BAAANQADCgUICgAAAA==.',
Fo='Fooksdk:BAAANQAECgcIDQAAAA==.Fooksdruid:BAAANQADCgUIBQAAAA==.Forestpimp:BAAANQAECgEIAQAAAA==.',
Fu='Fullometal:BAAANQAECgYICgAAAA==.Furojin:BAAANQADCgIIAwABNQAECgUIDgABAAAAAA==.',
Ga='Galroot:BAAANQAECgUICgAAAA==.Garrett:BAAANQADCgEIAQAAAA==.',
Ge='Geff:BAAANQADCgQIBAAAAA==.',
Gi='Girthhquake:BAAANQAECgEIAQAAAA==.Gisokaashi:BAAANQADCgUIBQAAAA==.',
Gn='Gnomepwner:BAAANQADCgcIBwAAAA==.',
Go='Gothick:BAAANQADCgYICAAAAA==.',
Gr='Grimréaper:BAAANQADCgIIAgAAAA==.',
Gu='Guts:BAAANQAECgEIAQAAAA==.',
Ha='Harryhoudini:BAAANQADCgYIBgAAAA==.',
He='Healforfun:BAAANQAECgYIDgAAAA==.Heilung:BAAANQAECgcIDwAAAA==.',
Hi='Hirradee:BAABNQAECoEcAAICAAgJIhPLFQBIAgACAAgJIhPLFQBIAgAAAA==.',
Ho='Holyelf:BAAANQADCgYICgAAAA==.',
Hu='Hubelez:BAAANQAECgYICgAAAA==.',
Ic='Icecweam:BAAANQABCgIIAgAAAA==.Icthelight:BAAANQAECgMIAwAAAA==.',
Ii='Iista:BAAANQADCgIIAgAAAA==.',
Ir='Irontuskss:BAAANQADCgYIBgAAAA==.',
Iz='Iznthyr:BAAANQABCgIIAgAAAA==.',
Ja='Jayar:BAAANQAECgYICgAAAA==.',
Jd='Jdawgg:BAAANQADCgcIGAAAAA==.',
Jo='Jorley:BAAANQADCggIDwAAAA==.',
Jr='Jrwriter:BAAANQAECgYIEAAAAA==.',
Jy='Jym:BAAANQAECgQICQAAAA==.',
Ka='Kaijin:BAAANQAECgYIDAAAAA==.Kalyr:BAAANQAECgQIBAAAAA==.Kandrianna:BAAANQAECgQIBQAAAA==.',
Ke='Keraasi:BAAANQAECgYIDgAAAA==.Kevinv:BAAANQADCgEIAQAAAA==.',
Kh='Khristine:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.',
Ki='Kikai:BAAANQADCgUICQAAAA==.Kilrav:BAAANQAECgQIBAAAAA==.Kimberlee:BAAANQAECgYIBgAAAA==.Kiryanna:BAAANQAECgQIBQAAAA==.Kitiara:BAAANQADCggIDgAAAA==.',
Kl='Klayah:BAAANQAECgEIAQAAAA==.',
Ko='Koogz:BAAANQADCggIDgAAAA==.Kordelia:BAAANQAECgQIBwABNQAECgUICgABAAAAAA==.Korgmafx:BAAANQADCgQICwAAAA==.',
La='Larke:BAAANQADCgMIAwAAAA==.',
Le='Leilany:BAAANQAECgEIAQAAAA==.Lethäl:BAAANQADCgIIAgAAAA==.',
Li='Littledirk:BAAANQADCgcIAgAAAA==.',
Ll='Llillies:BAAANQADCgUIBAAAAA==.',
Lu='Lugnuts:BAAANQAECgMIAwAAAA==.',
Ma='Magebuff:BAABNQAECoEaAAIDAAgJtR4cPgCZAgADAAgJtR4cPgCZAgAAAA==.Malroy:BAAANQADCgYIBgAAAA==.',
Mc='Mcheals:BAAANQADCgcIDgAAAA==.',
Mi='Miidniter:BAAANQADCggIDgAAAA==.',
Mo='Monsunami:BAAANQAECgQICAAAAA==.Moogar:BAAANQAECgYIDgAAAA==.Moonlock:BAAANQADCggICAAAAA==.Morte:BAAANQADCgIIAgAAAA==.Moònflower:BAAANQAECgIIAgAAAA==.',
['Mø']='Møøse:BAAANQAECgQIBgAAAA==.',
Na='Nanwu:BAAANQAECgQIBwAAAA==.Narcyon:BAAANQAECgQIBgAAAA==.',
Nh='Nhox:BAAANQAECgEIAwAAAA==.',
No='Noobîtîs:BAAANQADCgYICwAAAA==.Notmaxxie:BAAANQADCggIFQAAAA==.',
Ob='Obz:BAAANQAECgUICQAAAA==.',
Od='Oddlylight:BAAANQAECgQICAAAAA==.',
Ol='Ollie:BAAANQADCgIIAgAAAA==.',
Pa='Pandicated:BAEANQAECgcIDgAAAA==.',
Pe='Pelondar:BAAANQADCggICAAAAA==.',
Ph='Phalanx:BAAANQADCgYIBgAAAA==.',
Pl='Plaguedoctor:BAAANQADCgQIBAAAAA==.',
Po='Pookalicious:BAAANQADCgQIBAAAAA==.Pookiebear:BAAANQADCgIIAgAAAA==.Possessed:BAAANQADCgYICgAAAA==.',
Pr='Prìdè:BAAANQAECgUICQAAAA==.',
Pu='Punjana:BAAANQABCgMIAwAAAA==.',
Ra='Razmae:BAAANQAECgMIAwAAAA==.',
Re='Rennala:BAAANQAECgEIAQAAAA==.',
Ri='Riptide:BAAANQAECgQICAAAAA==.Risto:BAAANQAECgIIAwAAAA==.',
Ro='Rockon:BAAANQAECgYICwABNQADCgcIDgABAAAAAA==.Roden:BAAANQABCgMIAwAAAA==.Ronzertnin:BAAANQAECgIIAwAAAA==.Roxen:BAAANQADCggIDwAAAA==.',
Ru='Runananako:BAAANQAECgIIAgAAAA==.',
['Ré']='Réaper:BAAANQADCgcIDwAAAA==.Rénji:BAAANQAECgMIAwAAAA==.',
Sa='Salana:BAAANQADCgQIBQAAAA==.San:BAAANQAECgIIAgAAAA==.Sandroin:BAAANQAECgEIAQAAAA==.Sarah:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.',
Sc='Scarf:BAAANQAECgMIBAAAAA==.',
Sh='Shiggy:BAAANQABCgMIAwABNQADCgMIAgABAAAAAA==.Shinerbock:BAAANQAECgQIBAAAAA==.Shipoopi:BAAANQAECgQIBQAAAA==.Shock:BAAANQAECgUICwAAAA==.Shortnshady:BAAANQAECgMIBAAAAA==.',
Si='Sithen:BAAANQAECgMIAwAAAA==.',
Sk='Skankadin:BAAANQADCgYICQABNQAECgIIBAABAAAAAA==.Skankerella:BAAANQAECgIIBAAAAA==.Skiatrochia:BAAANQADCggICAABNQAECggIHAACACITAA==.Skipuscales:BAAANQAECgYICwAAAA==.',
Sm='Smoaky:BAAANQAECgUICgAAAA==.',
So='Soul:BAAANQAECgYIDQAAAA==.Soulscorcher:BAAANQADCgYIDAAAAA==.Sovietpanda:BAAANQADCgUICAAAAA==.',
Sp='Spanky:BAAANQAECgEIAQAAAA==.Spankyohs:BAAANQADCgcICwAAAA==.Spindles:BAAANQAECgEIAQAAAA==.Spiritgun:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.',
St='Stimpack:BAAANQAECgMIBAAAAA==.',
Su='Sutures:BAAANQADCgYIDgAAAA==.',
['Sö']='Sönja:BAAANQAECgIIBAAAAA==.',
Ta='Tará:BAAANQAECgQIBAAAAA==.',
Te='Techpriest:BAAANQADCgYIBwAAAA==.Tehblink:BAAANQAECgQIBQAAAA==.Tenoch:BAAANQAECgIIAgAAAA==.Terah:BAAANQADCgIIAgAAAA==.',
To='Toomez:BAAANQADCggICgAAAA==.Touchmydemon:BAAANQADCggIFgAAAA==.',
Tr='Trea:BAAANQAECgUIBwAAAA==.',
Tu='Tupkiss:BAAANQAECgUICgAAAA==.',
Ty='Tygrand:BAAANQABCgIIAgAAAA==.',
Va='Vazer:BAAANQABCgMIAwAAAA==.',
Wa='Waffledead:BAAANQAECgUIDAAAAA==.Wafflelight:BAAANQADCgcIBwAAAA==.Warpfiend:BAAANQAECgQIBQAAAA==.',
We='Wetnugget:BAAANQAECgEIAQAAAA==.',
Wi='Winnie:BAAANQADCgEIAQAAAA==.',
Wo='Wolfnhowz:BAAANQAECgIIAgAAAA==.',
Yu='Yura:BAAANQADCgEIAQAAAA==.',
Za='Zandragon:BAAANQADCgQIBAAAAA==.',
Ze='Zebubblez:BAAANQAECgIIAwAAAA==.',
Zg='Zgux:BAAANQAECgEIAQAAAA==.',
Zo='Zoêy:BAAANQADCggIFwAAAA==.',
Zu='Zuraki:BAAANQAECgQIBgAAAA==.',
Zz='Zzin:BAAANQABCgEIAQAAAA==.',
['Ço']='Çountèr:BAAANQAECgIIAgAAAA==.',
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
