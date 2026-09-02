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
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abhire:BAAANQADCgYIBgAAAA==.',
Ad='Advisor:BAAANQAECgEIAgAAAA==.',
Ae='Aería:BAAANQAECgUIBgAAAA==.',
Am='Amandakk:BAAANQADCgUIBQAAAA==.',
Ap='Aparajita:BAAANQADCggIDwAAAA==.Aphrodite:BAAANQADCggIDAAAAA==.',
Ar='Arianda:BAAANQAECgEIAQAAAA==.Aristoleh:BAAANQADCgYIBwABNQAECgQIBgABAAAAAA==.Arolder:BAAANQAECgIIAgAAAA==.',
At='Atoadaso:BAAANQADCgUIBQAAAA==.',
Az='Azazél:BAAANQAECgQIBAAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQADCgQIBAAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAAANQADCgUIBQAAAA==.',
Bo='Bogarash:BAAANQABCgIIAgAAAA==.Boombástic:BAAANQADCggIDgAAAA==.Boomco:BAAANQAECgEIAQAAAA==.',
Br='Bravillius:BAAANQABCgIIAwAAAA==.Breeti:BAAANQADCgYICwAAAA==.Broin:BAAANQADCgQIBAAAAA==.Bryda:BAAANQADCgMIAwAAAA==.',
Bu='Butlust:BAAANQADCgEIAQAAAA==.Butteskull:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.',
Bw='Bwucewee:BAAANQADCgMIBQAAAA==.',
Ca='Cajbo:BAAANQAECgEIAQAAAA==.Calyssa:BAAANQAECgEIAQAAAA==.Capmkrunch:BAAANQADCgUIBQAAAA==.Cartan:BAAANQAECgQIBAAAAA==.',
Ch='Charizaardx:BAAANQAECgcIDAAAAA==.Chromeski:BAAANQADCgYICAAAAA==.',
Cl='Cletus:BAAANQADCgQIBwAAAA==.',
Cr='Crystalys:BAAANQADCgMIAwAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIBgAAAA==.',
Cy='Cyblade:BAAANQAECgQIBQAAAA==.',
Da='Dalna:BAAANQADCggIDAAAAA==.Darkderek:BAAANQADCgUIBwAAAA==.Darklürker:BAAANQADCgYICwAAAA==.Darkwi:BAAANQAECgQIBgAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Deathby:BAAANQAECgEIAQAAAA==.Deathtardza:BAAANQADCgQIBwAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAAANQADCgIIAgAAAA==.Deldawalth:BAAANQADCggICAAAAA==.Demonica:BAAANQADCgcIBwAAAA==.Devick:BAAANQADCgEIAQAAAA==.',
Di='Dinta:BAAANQAECgIIAgAAAA==.',
Do='Dominoes:BAAANQADCgYICwAAAA==.',
Dr='Drakth:BAAANQADCgYIBgAAAA==.',
Du='Dummblond:BAAANQAECgIIAgAAAA==.',
Dy='Dysfunction:BAAANQADCggIDwAAAA==.',
['Dä']='Därkstone:BAAANQADCgEIAQAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQADCgYIEAABAAAAAA==.',
Eg='Ego:BAAANQAECgIIAgAAAA==.',
Em='Emordat:BAAANQADCgEIAQAAAA==.',
Ex='Exine:BAAANQADCgcIDAAAAA==.',
Fa='Faethe:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Fananabanana:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Fi='Finite:BAAANQADCgQIBAAAAA==.Firewater:BAAANQAECgEIAQAAAA==.',
Fl='Flameheart:BAAANQADCgYICwAAAA==.Fleathulhu:BAAANQAECgEIAQAAAA==.Flungpu:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.',
Fo='Fostock:BAAANQADCgQIBAAAAA==.',
Fr='Frostmoon:BAAANQABCgQIBQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Garwynn:BAAANQAECgEIAQAAAA==.',
Gh='Ghostkev:BAAANQADCgUIBgAAAA==.',
Gl='Glaistia:BAAANQADCgUIBQAAAA==.Glowstik:BAAANQADCgUIBQAAAA==.',
Ha='Habbyb:BAAANQADCgMIAwAAAA==.Halixan:BAAANQADCgUICQAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQADCgQIBAAAAA==.',
Ho='Honir:BAAANQAECgEIAQAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgYIDAAAAA==.',
['Hü']='Hünter:BAAANQADCgQIBQAAAA==.',
Ih='Ihlyria:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Im='Imonster:BAAANQADCgcIBwAAAA==.Imooforu:BAAANQADCgUIBgABNQADCgUIBwABAAAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jamus:BAAANQADCgYIEAAAAA==.Jarvy:BAAANQADCgUIBQAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Ka='Kaazel:BAAANQADCggIDgAAAA==.Kaladiin:BAAANQADCgMIAwAAAA==.Kallias:BAAANQAECgEIAQAAAA==.Karite:BAAANQADCggIDwAAAA==.Kaymyn:BAAANQAECgEIAQAAAA==.Kazenoth:BAAANQADCgUIBQAAAA==.',
Ke='Kennychaoss:BAAANQAECgEIAQAAAA==.',
Ki='Kille:BAAANQADCgYICwAAAA==.Killyoualot:BAAANQADCggIDwAAAA==.',
Ko='Kosseluna:BAAANQADCggIDQAAAA==.Kostazu:BAAANQAECgEIAQAAAA==.',
La='Laity:BAAANQAECgEIAQAAAA==.Lazariir:BAAANQABCgQIBAAAAA==.',
Le='Lebigmu:BAAANQADCgYIDAAAAA==.',
Li='Lisettar:BAAANQAECgEIAQAAAA==.',
Lo='Lockncreep:BAAANQADCgUICgAAAA==.Lolwut:BAAANQABCgIIAwAAAA==.',
Lu='Lunariss:BAAANQADCgMIAwAAAA==.',
Ly='Lycanbyte:BAAANQADCgUICQAAAA==.Lylith:BAAANQADCggIDwAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magnólia:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Mahan:BAAANQADCgQIBAAAAA==.Maribelle:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Me='Melomel:BAAANQADCgQIBAAAAA==.Melonsquezer:BAAANQADCggIDwAAAA==.Menmei:BAAANQADCgQIBAAAAA==.Merphia:BAAANQADCgEIAQAAAA==.Meygen:BAAANQADCggICAAAAA==.',
Mi='Minien:BAAANQADCggIDwAAAA==.Minore:BAAANQADCgcIBwAAAA==.',
Mo='Moa:BAAANQADCgYICwABNQAECgQIBAABAAAAAA==.Moonshot:BAAANQAECgEIAQAAAA==.Moortz:BAAANQADCgMIAwAAAA==.Morillic:BAAANQADCggIDwAAAA==.',
My='Myros:BAAANQADCgcIBwAAAA==.',
Na='Narestor:BAAANQADCgcICwAAAA==.Nazervis:BAAANQAECggIDQAAAA==.',
Ne='Nekopunch:BAAANQADCgcIDAAAAA==.Nelcor:BAAANQADCgIIAQAAAA==.Nemesîs:BAAANQABCgIIAgAAAA==.Neudru:BAAANQADCgIIAwAAAA==.Newhealer:BAAANQADCgYIBgAAAA==.',
No='Noint:BAAANQADCgMIAwAAAA==.Nortree:BAAANQADCgQIBAAAAA==.',
Nu='Nulwyrm:BAAANQADCgYICwAAAA==.',
Ny='Nymue:BAAANQADCgYICwAAAA==.Nyyrivik:BAAANQADCgIIAgAAAA==.',
Oc='Octapie:BAAANQADCggICwAAAA==.',
Oh='Ohitsadragon:BAAANQADCgYICwAAAA==.',
Or='Oranur:BAAANQAECgEIAQAAAA==.Oreoscruunit:BAAANQADCgIIAgABNQADCgUIBQABAAAAAA==.',
Os='Oscuridad:BAAANQADCgYICwAAAA==.',
Ow='Owl:BAAANQADCggICAAAAA==.Owlcatraz:BAAANQAECgYICQAAAA==.',
Pa='Paendrag:BAAANQADCggICgAAAA==.Panteragon:BAAANQADCgQIBAAAAA==.Panthean:BAAANQADCgMIAwAAAA==.Pashene:BAAANQADCgQIBAAAAA==.',
Pe='Periwinkle:BAAANQAECgEIAQAAAA==.Persaud:BAAANQAECgMIAwAAAA==.Pettacular:BAAANQAECgEIAQAAAA==.',
Ph='Phidra:BAAANQADCggIDwAAAA==.',
Po='Poprocks:BAAANQADCgUICQAAAA==.',
Pr='Predatorc:BAAANQADCggIDgAAAA==.Primevil:BAAANQADCgUICQAAAA==.Primevl:BAAANQAECgEIAQAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Ra='Radïance:BAAANQADCgYIBgAAAA==.Raediant:BAAANQADCggIDgAAAA==.Raggaemon:BAAANQADCgQICAAAAA==.Raquel:BAAANQADCggIDgAAAA==.',
Re='Rede:BAAANQADCgQIBwAAAA==.Reeyou:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Reign:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.Relieff:BAAANQADCgQIBAAAAA==.Revival:BAAANQADCgEIAQABNQADCgYIEAABAAAAAA==.',
Ri='Rio:BAAANQAECgEIAQAAAA==.Ris:BAAANQAECgMIAgAAAA==.Ritami:BAAANQAECgUIBQAAAA==.',
Ro='Rockyrogue:BAAANQADCgMIAwAAAA==.Roffy:BAAANQADCggIDwAAAA==.Roknathar:BAAANQAECgIIAgAAAA==.',
Sa='Saerin:BAAANQAECgQIBgAAAA==.Sargeth:BAAANQADCgcIBwAAAA==.',
Se='Sedo:BAAANQADCgQIBwAAAA==.Selenis:BAAANQADCggIDwABNQAECgUIBQABAAAAAA==.',
Sh='Shadowmonarc:BAAANQADCgUIBgAAAA==.Shamania:BAAANQADCgMIAwABNQADCgUICgABAAAAAA==.Shaomai:BAAANQAECgMIBAAAAA==.Shariae:BAAANQADCgIIAgAAAA==.Shidandfard:BAAANQAECgMIAwAAAA==.Shifte:BAAANQAECgEIAQAAAA==.Shiv:BAAANQADCgQIBgABNQADCggIDwABAAAAAA==.',
Sl='Slimage:BAAANQAECgEIAQAAAA==.Slushius:BAAANQADCgEIAQAAAA==.',
Sm='Smittens:BAAANQADCgcIBwAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAAANQADCgcIDQAAAA==.',
Sp='Spaarkle:BAAANQADCgMIAwAAAA==.Spectrehawk:BAAANQABCgIIAgABNQAECgYICgABAAAAAA==.Speçtre:BAAANQAECgYICgAAAA==.',
Su='Supak:BAAANQADCgYIBgAAAA==.Suppabad:BAAANQADCggIDwAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Tadlight:BAAANQADCgQIBwAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tazara:BAAANQADCgIIAgAAAA==.',
Tb='Tbone:BAAANQADCgUIBQAAAA==.',
Te='Teapha:BAAANQAECgEIAQAAAA==.Ted:BAAANQAECgIIAgAAAA==.Temptressxx:BAAANQADCggICAAAAA==.Tenstar:BAAANQADCgcIBwAAAA==.',
Th='Thokmay:BAAANQADCgUICQAAAA==.Thunden:BAAANQADCgYICAAAAA==.',
Ti='Tiandrinna:BAAANQAECgEIAQAAAA==.Tigirius:BAAANQADCgQIBQAAAA==.Timkaoss:BAAANQADCgUIBwAAAA==.',
Tm='Tmagnet:BAAANQADCgQIBAAAAA==.',
Tw='Tweedildee:BAAANQAECgQIBQAAAA==.',
['Tà']='Tàttersail:BAAANQADCgYIBgAAAA==.',
Un='Unholycreep:BAAANQADCgIIAgABNQADCgUICgABAAAAAA==.',
Va='Valdor:BAAANQAECgEIAQAAAA==.Valicous:BAAANQADCgUICQAAAA==.Vaylorian:BAAANQADCgUIBQAAAA==.Vaült:BAAANQADCggIDwAAAA==.',
Ve='Vellathor:BAAANQADCgQIBAAAAA==.Verianna:BAAANQAECgUIBQAAAA==.',
Vo='Vodkâshots:BAAANQADCggICAAAAA==.Voidbinder:BAAANQADCgQIBAAAAA==.',
Wi='Willowy:BAAANQAECgEIAQAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgIIAgAAAA==.',
Xa='Xaerius:BAAANQADCggIDwAAAA==.Xantyr:BAAANQADCgQIBgAAAA==.',
Ya='Yarman:BAAANQADCgQIBAAAAA==.',
Yo='Yojimbro:BAAANQADCgQIBwAAAA==.Yoshial:BAAANQADCgEIAQAAAA==.',
Za='Zalantir:BAAANQAECgQIBAABNQAECgYICgABAAAAAA==.Zariski:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Zarthus:BAAANQADCgMIAwAAAA==.',
Ze='Zealins:BAAANQAECgEIAQAAAA==.',
Zi='Zirl:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Ziyn:BAAANQAECgYICgAAAA==.',
Zo='Zoplete:BAAANQABCgIIBAAAAA==.',
['Ÿe']='Ÿeñnefer:BAAANQADCgUIBwAAAA==.',
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
