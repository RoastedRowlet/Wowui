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
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-09-01',data={Ac='Account:BAAANQABCgMIAwAAAA==.',
Ag='Agnithor:BAAANQADCggICQAAAA==.',
Al='Aliadra:BAAANQADCggIDgAAAA==.Alistus:BAAANQAECgQIBgAAAA==.',
An='Angua:BAAANQADCggIDwAAAA==.Anotheralt:BAAANQAECggIAQAAAA==.',
Au='Aurius:BAAANQADCggIDQAAAA==.',
Av='Aveliandis:BAAANQAECgEIAQAAAA==.',
Az='Azerphage:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Azhorra:BAAANQADCgIIAwAAAA==.Azzog:BAAANQADCgcICAAAAA==.Azül:BAAANQADCgcIDQAAAA==.',
Ba='Baelrin:BAAANQADCggICAAAAA==.Baindyn:BAAANQADCgQIBQAAAA==.Barator:BAAANQADCgUICAAAAA==.',
Be='Beaum:BAAANQAECgQIBAAAAA==.',
Bl='Blackröse:BAAANQAECgQIBAAAAA==.Bladebane:BAAANQADCgcIBwAAAA==.Blksunshine:BAAANQADCgUICAAAAA==.',
Bo='Bolash:BAAANQADCgYIDQAAAA==.',
Br='Bradthomas:BAAANQAECgEIAQAAAA==.Bruscha:BAAANQADCgEIAQAAAA==.',
Bu='Bulvhine:BAAANQADCggIDQAAAA==.',
Ca='Cactusteeth:BAAANQADCgcICwAAAA==.Cafeconpan:BAAANQADCggIDQAAAA==.Camford:BAAANQADCgYIBgAAAA==.',
Ce='Cecilx:BAAANQADCgYICwAAAA==.Censøred:BAAANQADCgYICwAAAA==.',
Ch='Chimerax:BAAANQAECgQICQAAAA==.Chully:BAAANQAECgQIBAAAAA==.',
Cl='Click:BAAANQADCgcIDQAAAA==.',
Co='Comadore:BAAANQAECgIIAgAAAA==.',
De='Deathslead:BAAANQADCggIDAAAAA==.Decrepe:BAAANQAECgMIAwAAAA==.Delph:BAAANQAECgQIBAAAAA==.Deshal:BAAANQADCgMIBQAAAA==.',
Di='Discostar:BAAANQADCggIDQAAAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCgUICAAAAA==.Druidcam:BAAANQADCgQIBAAAAA==.',
Eb='Ebonhorn:BAAANQADCgMIAwAAAA==.',
Ei='Einari:BAAANQADCggIDwAAAA==.',
Ek='Ekiim:BAAANQADCgUICAAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.',
Er='Eridor:BAAANQADCgQIBAAAAA==.',
Es='Esbernia:BAAANQAECgUIBgAAAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ew='Ew:BAAANQADCgcIBwAAAA==.',
Ex='Exek:BAAANQADCgIIAgAAAA==.',
Fa='Fabaztard:BAAANQADCgYICwAAAA==.Faline:BAAANQADCgcIDAAAAA==.',
Fe='Felgetabouit:BAAANQAECgQIBQAAAA==.Feort:BAAANQABCgIIAgAAAA==.',
Fi='Fidelity:BAAANQABCgIIAgAAAA==.Fights:BAAANQADCggIDwAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgAAAA==.',
Fo='Fontaine:BAAANQADCgMIAwAAAA==.Foradin:BAAANQADCggIDgAAAA==.Forky:BAAANQADCgYICAAAAA==.Foxknight:BAAANQADCgQIBQAAAA==.',
Fr='Franksnbeans:BAAANQADCgMIAwABNQADCgYIDAABAAAAAA==.',
Ga='Gaern:BAAANQAECgQIBQAAAA==.Gaidin:BAAANQAECgEIAQAAAA==.Gameslayer:BAAANQADCggIEAAAAA==.Gankzilla:BAAANQAECgQIBQAAAA==.',
Gi='Gila:BAAANQADCgEIAQAAAA==.Gizzle:BAAANQAECgQIBQAAAA==.',
Gr='Grimanack:BAAANQADCgMIAwAAAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Ha='Hanjha:BAAANQADCgcIDQAAAA==.',
He='Helldozer:BAAANQADCgcIDQAAAA==.Hexinu:BAAANQADCgcIDQAAAA==.',
Hy='Hypnocide:BAEANQADCggIDwAAAA==.',
Il='Illuvatar:BAAANQAECgEIAQAAAA==.',
Im='Impsane:BAAANQADCgQIBAAAAA==.',
Ir='Irv:BAAANQADCgIIAgAAAA==.',
Is='Isellrocks:BAAANQADCgIIAgAAAA==.',
Ja='Jaxxa:BAAANQADCggIDgAAAA==.',
Je='Jeddiah:BAAANQADCgUIBQAAAA==.',
Ji='Jinkès:BAAANQADCgIIAgAAAA==.',
Ju='Jubei:BAAANQAECgQIBAAAAA==.Judis:BAAANQADCggIGwAAAA==.Justokevoker:BAAANQAECgQIBAAAAA==.',
Ka='Kairì:BAAANQADCgcIBwAAAA==.Kalifist:BAAANQAECgYICgAAAA==.Kanajotoma:BAAANQADCgQIBQAAAA==.Karlai:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Ke='Keleena:BAEANQADCgcIBwAAAA==.Keze:BAAANQAECgQIBAAAAA==.',
Ki='Killzshot:BAAANQADCgQIBAAAAA==.Kinst:BAAANQADCgcIBwAAAA==.Kitanyia:BAAANQAECgEIAQAAAA==.Kittiy:BAAANQADCgIIAgAAAA==.Kizahnevo:BAAANQADCgcIBwAAAA==.',
Ko='Kordelia:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.',
Ky='Kyloon:BAAANQADCggIDgAAAA==.Kyrah:BAAANQADCggIDwAAAA==.',
La='Lakatryna:BAAANQADCggICQABNQAECggIDQABAAAAAA==.Lamanira:BAAANQADCgUICAAAAA==.',
Le='Lejend:BAAANQADCggIDwAAAA==.',
Ll='Llanedh:BAAANQADCgYIDAAAAA==.',
Lo='Lonelyhearts:BAAANQADCgcIDQAAAA==.Lorimuni:BAAANQADCggIDQAAAA==.',
Ma='Maenad:BAAANQAECgIIAgAAAA==.Maeple:BAAANQADCgcIBwAAAA==.Manamontana:BAAANQABCgMIBAAAAA==.',
Me='Meladyn:BAAANQAECgIIBAAAAA==.',
Mi='Miami:BAAANQAFFAEIAQAAAA==.Missmaam:BAAANQADCgUIBQAAAA==.Mistroot:BAAANQADCgMIAwAAAA==.',
Mo='Monkfox:BAAANQAECgYICQABNQAECgQIBAABAAAAAA==.Moon:BAAANQADCgUIBQAAAA==.',
Mu='Mushuwoonter:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.Muztang:BAAANQADCgcIDQAAAA==.',
My='Mythhunter:BAAANQADCgIIAgAAAA==.',
['Mô']='Mônkii:BAAANQAECgQIBAAAAA==.',
Na='Nace:BAAANQABCgIIAgAAAA==.Naenia:BAAANQADCgUIBQAAAA==.Nateldin:BAAANQADCgYIBgAAAA==.',
Ni='Nightcat:BAAANQADCgQIBAAAAA==.Niisha:BAAANQADCggICAAAAA==.',
No='Nocainus:BAAANQADCgcIDQAAAA==.',
Ob='Obsidia:BAAANQADCgYIBgAAAA==.',
Od='Oddlife:BAAANQAECgMIAwAAAA==.',
On='Onik:BAAANQADCgIIAwAAAA==.',
Op='Ophj:BAAANQAECgcIDAAAAA==.',
Or='Orangejulius:BAAANQADCgUIBQABNQADCgUICAABAAAAAA==.Orangutan:BAAANQABCgMIAwAAAA==.Oriigami:BAAANQADCgcICAAAAA==.Orinoheal:BAAANQADCgIIAgAAAA==.',
Os='Oskar:BAAANQAECgQIBAAAAA==.',
Pe='Pebda:BAAANQADCgUIBgAAAA==.Perilous:BAAANQADCgIIAgAAAA==.',
Ph='Phoelar:BAAANQADCgYIBgAAAA==.Phuumyn:BAAANQADCgcIDQAAAA==.',
Pi='Piccoblast:BAAANQAECgcICgAAAA==.Picklesoup:BAAANQADCgQIBwAAAA==.Piickles:BAAANQAECgUICAAAAA==.Pity:BAAANQADCgYIBgAAAA==.',
Pl='Plutø:BAAANQADCggICgAAAA==.',
Po='Polylocks:BAAANQADCgYICwAAAA==.',
Pr='Prókill:BAAANQADCgYIDAAAAA==.',
Ps='Psychokitty:BAAANQAECgIIAgAAAA==.',
Qu='Quilian:BAAANQAECgQIBQAAAA==.',
Ra='Raelynn:BAAANQADCgcIDQAAAA==.Rancier:BAAANQADCgUICAAAAA==.Rashalisk:BAAANQADCgMIAwAAAA==.',
Re='Redvex:BAAANQAECgQIBAAAAA==.Reinhard:BAAANQADCgYIBwAAAA==.Rencraw:BAAANQADCgIIAgAAAA==.Renras:BAAANQADCgQIBAAAAA==.',
Rh='Rhain:BAAANQADCggIDAAAAA==.',
Ri='Rinah:BAAANQAECgUIBQAAAA==.',
Ro='Rootbeard:BAAANQAECgEIAQAAAA==.Rosanna:BAAANQADCgMIBAAAAA==.Rotyr:BAAANQADCgcIDQAAAA==.',
Ru='Ruana:BAEANQADCgQIBAAAAA==.',
Ry='Rye:BAAANQADCgYICwAAAA==.',
Sc='Scoobey:BAAANQADCgUIBgAAAA==.Scubbs:BAAANQAECgQIBQAAAA==.',
Se='Servantes:BAAANQADCgcIDQAAAA==.',
Sh='Shamancam:BAAANQADCgIIAgAAAA==.Shamp:BAAANQADCgUICAAAAA==.Shiggy:BAAANQADCgUICAAAAA==.Shotya:BAAANQADCgcIDQAAAA==.',
Si='Sixthknight:BAAANQADCgYICgAAAA==.',
Sl='Slappi:BAAANQADCgcIDQAAAA==.',
Sn='Snarkypony:BAAANQADCgMIBAAAAA==.',
So='Sorsere:BAAANQADCgcIBwAAAA==.',
Sp='Specialk:BAAANQAECgMIBAAAAA==.',
St='Stirredihime:BAAANQADCggIDgAAAA==.',
Su='Sulph:BAAANQADCgcIDQAAAA==.Sundorei:BAAANQADCgIIAgAAAA==.',
Sv='Svalir:BAAANQADCgIIAgABNQADCgIIAwABAAAAAA==.',
Ta='Talshekar:BAAANQADCgcIDQAAAA==.',
Te='Teiana:BAAANQAECgUIBQAAAA==.',
Th='Thaevin:BAAANQADCggIDgAAAA==.Thews:BAAANQABCgEIAQAAAA==.Thilendrel:BAAANQAECgUIBgAAAA==.Thingwan:BAAANQAECgQIBQAAAA==.',
Ti='Tinystink:BAAANQAECgMIAwAAAA==.',
To='Toddstephens:BAAANQADCgYIBgAAAA==.Tors:BAAANQAECgIIAwAAAA==.',
Tr='Trasky:BAAANQADCgcIDAAAAA==.Trollololo:BAAANQADCgcIDQAAAA==.Troy:BAAANQADCgcICgAAAA==.Trëze:BAAANQADCggIEgAAAA==.',
Tt='Ttaartt:BAAANQAECgcIBwAAAA==.',
Ty='Typh:BAAANQAECgQIBAAAAA==.',
Un='Undeaddemon:BAAANQAECgQIBAAAAA==.Undeaddh:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Undignified:BAAANQADCggIDwAAAA==.Unholysixth:BAAANQADCgMIBgAAAA==.',
Va='Vanidarr:BAAANQADCgQIBAAAAA==.',
Ve='Verasia:BAAANQADCgQIBQAAAA==.',
Vi='Vidikan:BAAANQADCgIIAwAAAA==.Violett:BAAANQAECgEIAQAAAA==.',
Vo='Voidwarranty:BAAANQAECgQIBQAAAA==.',
Vv='Vvumpscut:BAAANQAECgQIBAAAAA==.',
Wa='Waldón:BAAANQADCgcIBwAAAA==.',
Wi='Wildsoul:BAAANQADCgcIBwAAAA==.Wistywind:BAAANQABCgIIAwAAAA==.',
Xc='Xclaw:BAAANQADCgMIAwAAAA==.',
Xe='Xeroxgravity:BAAANQADCgYIBgAAAA==.',
Xi='Xilphira:BAAANQADCgQIBQAAAA==.',
Xl='Xlithz:BAAANQADCgcIDAAAAA==.',
Ya='Yah:BAAANQADCgMIAwAAAA==.',
Yl='Ylene:BAAANQADCgUICgAAAA==.',
Yo='Yoink:BAAANQAECgQIBAAAAA==.',
Za='Zalzuke:BAAANQADCgUICAAAAA==.Zarinchaos:BAAANQAECgIIAgAAAA==.',
Ze='Zein:BAAANQADCgUICAAAAA==.Zente:BAAANQAECgQIBQAAAA==.Zequill:BAAANQADCggIDwAAAA==.Zevsticles:BAAANQAECgUIBQAAAA==.',
Zh='Zhom:BAAANQAECggIDQAAAA==.',
Zo='Zooj:BAAANQADCgcIDQAAAA==.',
Zy='Zylofeather:BAAANQADCgUIBQAAAA==.',
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
