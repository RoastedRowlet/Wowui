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
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abisio:BAAANQADCgUIBQAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAAANQADCgYIDAAAAA==.Acursedpeen:BAAANQADCgMIAwAAAA==.',
Ad='Adoryn:BAEANQADCggIDgAAAA==.',
Ag='Agares:BAAANQAECgEIAQAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Am='Amberscale:BAAANQADCggIDgAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Ancientuur:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Andazaren:BAAANQADCggIDgAAAA==.Angrulus:BAAANQADCgcIDQAAAA==.Animlshiftr:BAAANQADCggICAAAAA==.',
Ap='Apollo:BAAANQADCgcICgAAAA==.',
Ar='Aryllyn:BAAANQADCgYIBwAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQADCgYIDAAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQABCgIIAgABNQADCggIDgABAAAAAA==.',
Be='Bearett:BAAANQAECgEIAQAAAA==.Belysurge:BAAANQAECgQIBAAAAA==.Bernd:BAAANQADCgYICwAAAA==.Beörn:BAAANQADCgcIFQAAAA==.',
Bi='Birgir:BAAANQADCgQIBwAAAA==.',
Bl='Blackkgrin:BAAANQADCgMIAwAAAA==.',
Br='Breezy:BAAANQAECgIIAwAAAA==.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAAANQADCggIDgAAAA==.',
By='Byanca:BAAANQAECgIIAgAAAA==.',
Ca='Caine:BAAANQADCggIDgAAAA==.Casey:BAAANQADCgUICAAAAA==.Castyblasty:BAAANQADCggICQAAAA==.',
Ce='Cellina:BAAANQADCggIDQAAAA==.',
Cl='Classá:BAAANQAECgEIAQAAAA==.',
Co='Codedd:BAAANQADCgUIBQAAAA==.Corin:BAAANQAECgIIAgAAAA==.Corlys:BAAANQADCgYICwAAAA==.',
Cr='Crispìn:BAAANQADCgYICwAAAA==.Crue:BAAANQADCgcICwAAAA==.',
Cy='Cynboom:BAAANQADCgMIAwAAAA==.Cyndee:BAAANQADCgcIDQAAAA==.',
Da='Dadda:BAAANQADCggICgAAAA==.Damascus:BAAANQADCggIDgAAAA==.Dankdruid:BAAANQADCgUICgAAAA==.Darkschi:BAAANQADCggIDgAAAA==.Dartos:BAAANQAECgEIAQAAAA==.',
De='Deepshadow:BAAANQADCgcIDAAAAA==.',
Di='Diluvium:BAAANQADCggICAAAAA==.Discodank:BAAANQADCgEIAQABNQADCgUICgABAAAAAA==.',
Dj='Djpleasant:BAAANQAECgYICgAAAA==.',
Do='Dontcare:BAAANQAECgUIBQAAAA==.',
Dr='Dronos:BAAANQAECgEIAQAAAA==.',
['Dû']='Dûo:BAAANQADCgQIBAAAAA==.',
Ea='Eatmorpizza:BAAANQADCgQIBQAAAA==.',
Ee='Eegnormu:BAAANQAECgQIBAAAAA==.Eegroll:BAAANQAECgYICQAAAA==.',
Eg='Egraw:BAAANQADCgYICwAAAA==.',
El='Elendar:BAAANQADCgYIBQAAAA==.',
Ep='Epia:BAAANQADCggICgAAAA==.',
Es='Esdéath:BAAANQAECgUICQAAAA==.Essaila:BAAANQAECgEIAQAAAA==.',
Et='Etherwalker:BAAANQADCggIDgAAAA==.',
Ex='Excision:BAAANQAECgEIAQAAAA==.',
Fa='Fahbio:BAAANQADCgcIDQAAAA==.Fatallock:BAAANQAECgIIAwAAAA==.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgEIAQAAAA==.Fishdish:BAAANQADCgMIAwAAAA==.Fistsmither:BAAANQADCgMIAwABNQADCgQIBQABAAAAAA==.',
Fl='Flailuid:BAAANQADCggICAAAAA==.',
Fo='Forthstryke:BAAANQADCgQICAAAAA==.',
Fr='Fresita:BAAANQADCgUIBQAAAA==.Frozarke:BAAANQAECgIIAgAAAA==.',
Fu='Fudd:BAAANQADCgcIDQAAAA==.Fupa:BAAANQADCgUICQAAAA==.',
Ge='Genius:BAAANQADCgcIDAAAAA==.',
Gi='Gibley:BAAANQAECgEIAQAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAAANQADCgYICwAAAA==.Gnomie:BAAANQADCgYICwAAAA==.Gnomio:BAAANQADCgYICwAAAA==.',
Go='Gouge:BAAANQAECgQIBQAAAQ==.',
Gr='Griffynshu:BAAANQADCgUIBQAAAA==.Grudgetotem:BAAANQAECgEIAQAAAA==.',
Gu='Gungnir:BAAANQAECgEIAQAAAA==.',
Ha='Haki:BAAANQADCgcICQAAAA==.Handiboy:BAAANQAECgUIBwAAAA==.Hayate:BAAANQADCgUIBwAAAA==.',
He='Healabull:BAAANQADCgQICAABNQAECgEIAQABAAAAAA==.Heimdall:BAAANQAECgEIAQAAAA==.Hellaholy:BAAANQADCgYICgAAAA==.Hellavva:BAAANQADCgIIAgAAAA==.Henchling:BAAANQAECgMIAwAAAA==.',
Ho='Holexios:BAAANQAECgQIBAAAAA==.Horine:BAAANQADCggIDAAAAA==.',
Im='Immeira:BAAANQAECgEIAQAAAA==.',
Ja='Jackcsi:BAAANQAECgQIBgAAAA==.Jackiix:BAAANQADCgYIBgAAAA==.',
Je='Jenoside:BAAANQAECgIIAgAAAQ==.',
Jo='Journei:BAAANQADCggIDAAAAA==.',
Ju='Judging:BAAANQADCgYICwAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIDAAAAA==.',
Ke='Kegz:BAAANQADCgcICQAAAA==.Kellayna:BAAANQADCgUICQAAAA==.Keylö:BAAANQADCgQIBAAAAA==.',
Kl='Klerik:BAAANQAECggIDQAAAA==.',
Ko='Koragg:BAAANQAECgYICgAAAA==.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgIIAgAAAA==.Korrag:BAAANQADCggIDAAAAA==.Kozarke:BAAANQADCgYIBgAAAA==.',
Kr='Krissia:BAAANQAECgEIAQAAAA==.',
Ky='Kyntaliia:BAAANQADCgYIBgAAAA==.',
['Kî']='Kîn:BAAANQADCgcIDQAAAA==.',
La='Laisera:BAAANQAECgEIAQAAAA==.Lalipop:BAAANQADCgcIDQAAAA==.Landroval:BAAANQADCgYICwAAAA==.Lawson:BAAANQADCgYIBgAAAA==.',
Le='Leeoh:BAAANQADCggIDQAAAA==.Leeohd:BAAANQADCggIDQAAAA==.Lenthaden:BAAANQADCgYIBgAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.',
Lo='Lovenky:BAAANQADCgUIBgAAAA==.',
Lu='Lujuria:BAAANQAECgQIBAAAAA==.Lunchdk:BAAANQADCggICAAAAA==.',
Ly='Lyreth:BAAANQAECgEIAQAAAA==.',
Ma='Madax:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.',
Me='Megamilk:BAAANQAECgIIAgAAAA==.Meganfox:BAAANQAECgQIBgABNQAECgUIBQABAAAAAA==.Merilde:BAAANQADCgcIDgAAAA==.Metrolinea:BAAANQAECgEIAQAAAA==.',
Mi='Milliy:BAAANQADCggIEAAAAA==.Minamel:BAAANQADCgEIAQABNQADCggICAABAAAAAA==.Missbehaving:BAAANQADCgMIAwAAAA==.',
Mo='Mojorisin:BAAANQABCgEIAQAAAA==.Morefire:BAAANQADCgcICQAAAA==.Mosmos:BAAANQADCgEIAQAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAAANQADCggIDgAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.',
Na='Nannette:BAAANQADCgcIDQAAAA==.Narag:BAAANQADCggIDgAAAA==.',
Ne='Neph:BAAANQADCgIIAgAAAA==.Nephorma:BAAANQADCgIIAgAAAA==.Newport:BAAANQAECgEIAQAAAA==.',
Ni='Niara:BAAANQAECgMIAwAAAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAAANQADCgcIEQAAAA==.Nithén:BAAANQADCgIIAQAAAA==.',
No='Nonaleeta:BAAANQADCgYIDwAAAA==.Novaa:BAAANQADCgUICAAAAA==.Nowhere:BAAANQADCgQIBQAAAA==.Nowon:BAAANQAECgcIBwAAAA==.',
Nu='Nudream:BAAANQADCgMIAwAAAA==.Nuka:BAAANQADCgYIBgAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Op='Opalyte:BAAANQADCgcIDQAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAAANQADCgYICwAAAA==.',
Ov='Overtavo:BAAANQAECgIIAgAAAA==.',
Pa='Pacobell:BAAANQADCgYICgAAAA==.Pakoros:BAAANQADCggIDwAAAA==.Palamar:BAAANQADCggIDgAAAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAAANQADCgcIDAAAAA==.',
Pg='Pgorlelgy:BAAANQAECgEIAQAAAA==.',
Pl='Platious:BAAANQADCgUICgAAAA==.',
Po='Pookaboo:BAAANQADCgYICwAAAA==.',
Pr='Preacharoùnd:BAAANQAECgYICAAAAA==.',
Pu='Purdie:BAAANQADCgEIAQABNQADCggICAABAAAAAA==.Purdieturtle:BAAANQADCggICAAAAA==.',
Qe='Qeesa:BAAANQADCgYIDQAAAA==.',
Ra='Ranni:BAAANQAECgEIAQAAAA==.Rawmeat:BAAANQADCggIDgAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renix:BAAANQAECgEIAQAAAA==.',
Rh='Rhainnón:BAAANQADCgYIBgAAAA==.Rheã:BAAANQADCgcICgAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAAANQAECgEIAQAAAA==.',
Ro='Royfenix:BAAANQADCggICwAAAA==.',
Sa='Sack:BAAANQAECgMIAwAAAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sanctity:BAAANQADCgYICwAAAA==.Satine:BAAANQADCgYICgAAAA==.',
Sc='Scratlord:BAAANQADCgEIAQAAAA==.',
Se='Sevinas:BAAANQADCgYICgAAAA==.',
Sh='Shamwoww:BAAANQADCgMIAgABNQAECgYICAABAAAAAA==.Shelly:BAAANQADCgYIBgAAAA==.Shlumpcane:BAAANQAECgMIBQAAAA==.Shámjackson:BAAANQAECgYIBwAAAA==.',
Si='Silvey:BAAANQADCgYICwAAAA==.Sithtracker:BAAANQABCgIIAgAAAA==.',
Sk='Skeletorque:BAAANQADCgYIBwAAAA==.',
Sm='Smallwdruid:BAAANQADCgIIAgAAAA==.',
Sn='Snow:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Snowfawn:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Snusnurae:BAAANQADCgIIAgAAAA==.',
Sp='Splishsplásh:BAAANQADCgYICgAAAA==.Sprattyboii:BAAANQAECgEIAQAAAA==.',
Ss='Sscarlet:BAAANQADCgUICQAAAA==.',
St='Starzia:BAAANQADCggIDgAAAA==.',
Su='Sunk:BAAANQADCgYICwAAAA==.',
Sw='Swiftblossom:BAAANQADCgMIBAAAAA==.',
Ta='Talanot:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Tanadria:BAAANQADCgEIAQAAAA==.Tapioca:BAAANQADCgIIAgAAAA==.Taterdot:BAAANQADCgYICwAAAA==.',
Te='Telm:BAAANQADCggICAAAAA==.',
Th='Thaÿne:BAAANQADCggIDAAAAA==.Thebestpally:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.Thenemisis:BAAANQADCgYICgAAAA==.',
Ti='Tidds:BAAANQADCggICAAAAA==.',
To='Totemdown:BAAANQAFFAEIAQABNQAECgQIBAABAAAAAA==.',
Tr='Traedaei:BAAANQADCgQIBAAAAA==.Trazarath:BAAANQAECgQIBAAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgIIAwABNQADCgcIDQABAAAAAA==.',
Us='Usdaprime:BAAANQADCgIIAgABNQADCgYIBwABAAAAAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQADCgYIBgAAAA==.',
Uu='Uuyd:BAAANQAECgIIAgABNQAECgIIAgABAAAAAQ==.',
Va='Varala:BAAANQADCgQIBAAAAA==.',
Ve='Vel:BAAANQAECgcIEAAAAA==.Veritas:BAAANQAECgIIAgAAAA==.Veskara:BAAANQADCgQIBwAAAA==.',
Vy='Vylana:BAAANQADCgUIBQABNQAECgUIBgABAAAAAA==.',
['Vè']='Vèl:BAAANQADCgYICwABNQAECgcIEAABAAAAAA==.',
Wa='Warity:BAAANQAECgEIAQAAAA==.',
We='Wetdotpal:BAAANQADCggICAAAAA==.Wetdotthirst:BAAANQADCgQIBAAAAA==.',
Wh='Whiteabyss:BAAANQADCggIDAAAAA==.',
Xo='Xomby:BAAANQADCgYIBgAAAA==.',
['Xì']='Xìon:BAAANQADCgcIBwAAAA==.',
Ya='Yayrri:BAAANQADCgYICwAAAA==.',
Yo='Youngjedi:BAAANQADCgYIBgAAAA==.',
Za='Zatarra:BAAANQADCgUIBwAAAA==.',
Ze='Zextron:BAAANQADCgcICwAAAA==.',
Zi='Ziaya:BAAANQADCgcIBwAAAA==.',
Zo='Zolaeus:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Zu='Zuboo:BAAANQADCggIDgAAAA==.',
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
