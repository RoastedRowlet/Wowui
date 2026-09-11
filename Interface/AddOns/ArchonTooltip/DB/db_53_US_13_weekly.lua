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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','DeathKnight-Unholy',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abisio:BAAANQAECgEIAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAAANQADCgYIDAAAAA==.Acursedpeen:BAAANQADCgMIAwAAAA==.',
Ad='Adoryn:BAEANQAECgEIAQAAAA==.',
Ae='Aessan:BAAANQAECgMIAwAAAA==.',
Ag='Agares:BAAANQAECgUIBgAAAA==.',
Ai='Aisathya:BAAANQADCggICAAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Am='Amberfox:BAAANQADCgUIBQAAAA==.Amberscale:BAAANQAECgIIAgAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Ancientuur:BAAANQADCgYIBgAAAA==.Andazaren:BAAANQAECgIIAgAAAA==.Angrulus:BAAANQADCgcIDQAAAA==.Animal:BAAANQADCgMIAwAAAA==.Animlshiftr:BAAANQADCggICAAAAA==.',
Ap='Apollo:BAAANQADCggIEgAAAA==.',
Ar='Arixx:BAAANQABCgEIAQAAAA==.Aryllyn:BAAANQADCgYIDAAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQADCgcIEwAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQABCgMIAwABNQAECgEIAQABAAAAAA==.',
Be='Bearett:BAAANQAECgQIBQAAAA==.Belysurge:BAAANQAECgQIBwAAAA==.Bernd:BAAANQADCggIEwAAAA==.Beörn:BAAANQAECgMIAwAAAA==.',
Bi='Birgir:BAAANQADCgQIBwAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAAANQAECgEIAQAAAA==.',
Br='Braids:BAAANQADCggICAAAAA==.Breezy:BAAANQAECgUICAAAAA==.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAAANQAECgEIAQAAAA==.',
Bu='Buttrbiskit:BAAANQAECgcIBwAAAA==.',
By='Byanca:BAAANQAECgMIBQAAAA==.',
Ca='Caine:BAAANQAECgEIAQAAAA==.Casey:BAAANQADCgYIDgAAAA==.Castyblasty:BAAANQAECgQIBAAAAA==.',
Ce='Cellina:BAAANQAECgIIAgAAAA==.',
Cl='Classá:BAAANQAECgEIAgAAAA==.',
Co='Codedd:BAAANQADCgUIBgAAAA==.Corin:BAAANQAECgQIBwAAAA==.Corlys:BAAANQADCggIEwAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAAANQAECgEIAQAAAA==.Crue:BAAANQADCgcIDAAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIIAgAAAA==.',
Cy='Cynboom:BAAANQADCgMIAwAAAA==.Cyndee:BAAANQAECgIIAgAAAA==.',
Da='Dadda:BAAANQAECgcICgAAAA==.Daisynukes:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAAANQAECgEIAQAAAA==.Dankdruid:BAAANQADCgUICgABNQADCgYIBwABAAAAAA==.Darkschi:BAAANQAECgEIAQAAAA==.Dartos:BAAANQAECgQIBQAAAA==.',
De='Deepmagic:BAAANQAECgEIAQAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.',
Di='Diluvium:BAAANQAECgIIAgAAAA==.Discodank:BAAANQADCgYIBwAAAA==.',
Dj='Djpleasant:BAAANQAECggIEgAAAA==.',
Do='Dontcare:BAAANQAECgcICwAAAA==.',
Dr='Dronos:BAAANQAECgQIBQAAAA==.',
['Dû']='Dûo:BAAANQAECgUIBQAAAA==.',
Ea='Eatmorpizza:BAAANQADCgQIBQAAAA==.',
Ee='Eegnormu:BAAANQAECgQIBgAAAA==.Eegroll:BAAANQAECgYIDwAAAA==.',
Eg='Egraw:BAAANQADCggIEwAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Ep='Epia:BAAANQAECggIAQAAAA==.',
Es='Esdéath:BAAANQAECgYIEAAAAA==.Essaila:BAAANQAECgUIBgAAAA==.',
Et='Etherwalker:BAAANQAECgEIAQAAAA==.',
Ex='Excision:BAAANQAECgQIBQAAAA==.',
Fa='Fahbio:BAAANQADCggIEgAAAA==.Fatallock:BAAANQAECggIBwAAAA==.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQADCgMIAwAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgUIBwABAAAAAA==.',
Fl='Flailuid:BAAANQAECgMIAwAAAA==.',
Fo='Forthstryke:BAAANQADCgUICQAAAA==.',
Fr='Fresita:BAAANQADCgYICwAAAA==.Fridaychill:BAAANQAECgUIBwAAAA==.Frozarke:BAAANQAECgQIBgAAAA==.',
Fu='Fudd:BAAANQADCggIEgAAAA==.Funk:BAAANQABCgIIAgABNQADCgMIAwABAAAAAA==.Fupa:BAAANQAECgEIAQAAAA==.',
Ga='Garres:BAAANQADCgcIBwAAAA==.',
Ge='Genius:BAAANQADCggIFAAAAA==.',
Gi='Gibley:BAAANQAECgEIAQAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAAANQADCgYIEQAAAA==.Gnomie:BAAANQADCggIEwAAAA==.Gnomio:BAAANQADCggIEwAAAA==.',
Go='Gouge:BAAANQAECgQICQAAAQ==.',
Gr='Griffynshu:BAAANQAECgEIAQAAAA==.Grrv:BAAANQABCgQIBAAAAA==.Grudgetotem:BAAANQAECgIIAwAAAA==.',
Gu='Gungnir:BAAANQAECgIIAwAAAA==.',
Ha='Haki:BAAANQADCgcICQAAAA==.Handiboy:BAAANQAECgcIDgAAAA==.Hayate:BAAANQADCgcIDwAAAA==.',
He='Healabull:BAAANQADCgYIDgABNQAECgQIBQABAAAAAA==.Heimdall:BAAANQAECgMIBAAAAA==.Hellaholy:BAAANQADCgYICwAAAA==.Hellavva:BAAANQADCgUIBwAAAA==.Henchling:BAAANQAECgQIBwAAAA==.',
Ho='Holexios:BAAANQAECgQIBAAAAA==.Horine:BAAANQAECgEIAQAAAA==.',
Ic='Icieblade:BAAANQADCgEIAQAAAA==.',
Im='Immeira:BAAANQAECgQIBQAAAA==.',
In='Intense:BAAANQADCgEIAQAAAA==.',
Ja='Jackcsi:BAAANQAFFAEIAQAAAA==.Jackiix:BAAANQADCgYIBgAAAA==.',
Je='Jenoside:BAAANQAECgQIBgAAAQ==.',
Jo='Journei:BAAANQAECgIIAgAAAA==.',
Ju='Judging:BAAANQADCggIEwAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIEgAAAA==.',
Ke='Kegz:BAAANQAECgIIAgAAAA==.Kellayna:BAAANQADCgYIDwAAAA==.Keylö:BAAANQADCgYICgAAAA==.',
Kh='Khoulethius:BAAANQABCgIIAgAAAA==.',
Kl='Klerik:BAABNQAECoEYAAQCAAkJExx0FgBMAgACAAcJXRt0FgBMAgADAAYJZw44GABuAQAEAAEJCgYDGAAyAAAAAA==.',
Kn='Kníghtmare:BAAANQAECgEIAQAAAA==.',
Ko='Koragg:BAAANQAECgcIEQAAAA==.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgQIBAAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAAANQADCggIDgAAAA==.',
Kr='Krissia:BAAANQAECgQIBQAAAA==.',
Ky='Kymerah:BAAANQABCgYIBgAAAA==.Kyntaliia:BAAANQADCgYIBgAAAA==.',
['Kî']='Kîn:BAAANQADCggIEgAAAA==.',
La='Laisera:BAAANQAECgQIBQAAAA==.Lalipop:BAAANQADCggIEgAAAA==.Landroval:BAAANQADCggIEwAAAA==.Lawson:BAAANQAECgEIAQAAAA==.',
Le='Leeoh:BAAANQAECgQIBQAAAA==.Leeohd:BAAANQADCggIEwAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAAANQADCgcIBwAAAA==.',
Lo='Lovenky:BAAANQADCgUIBgAAAA==.',
Lu='Lujuria:BAAANQAECgQICAAAAA==.Lunchdk:BAAANQADCggICAAAAA==.',
Ly='Lyreth:BAAANQAECgQIBQAAAA==.',
Ma='Madax:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.Manach:BAAANQADCgYIBgAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAAANQAECgUICAAAAA==.Meganfox:BAAANQAECgQIBgABNQAECgcICwABAAAAAA==.Merilde:BAAANQADCgcIDgAAAA==.Metrolinea:BAAANQAECgUIBQAAAA==.',
Mi='Milliy:BAAANQAECgQIBAAAAA==.Minamel:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Missbehaving:BAAANQADCgMIAwAAAA==.',
Mo='Mojorisin:BAAANQABCgEIAQAAAA==.Morefire:BAAANQAECgEIAQAAAA==.Mosmos:BAAANQADCgIIAwAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAAANQAECgQIBAAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAAANQAECgQIBAAAAA==.',
Na='Nannette:BAAANQADCggIEgAAAA==.Narag:BAAANQADCggIDgAAAA==.',
Ne='Neph:BAAANQAECgEIAQAAAA==.Nephorma:BAAANQADCggICgAAAA==.Newport:BAAANQAECgQIBQAAAA==.',
Ni='Niara:BAAANQAECgMIBAAAAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAAANQADCggIGQAAAA==.Nithén:BAAANQADCgYIBwAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Novaa:BAAANQADCgUICAAAAA==.Nowhere:BAAANQAECgUIBwAAAA==.Nowon:BAAANQAECgcIBwAAAA==.',
Nu='Nudream:BAAANQADCgMIAwAAAA==.Nuka:BAAANQADCgYIBgAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgUIBwABAAAAAA==.',
Op='Opalyte:BAAANQADCggIEgAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAAANQADCgcIEwAAAA==.',
Ov='Overtavo:BAAANQAECgUIBwAAAA==.',
Pa='Pacobell:BAAANQADCgYICgAAAA==.Pakoros:BAAANQAECgQIBAAAAA==.Palamar:BAAANQAECgEIAQAAAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAAANQADCggIFAAAAA==.',
Pg='Pgorlelgy:BAAANQAECgIIAwAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.',
Pl='Platious:BAAANQADCgUICgAAAA==.',
Po='Pookaboo:BAAANQADCggIEwAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAAANQAECgcIDwAAAA==.',
Pu='Purdie:BAAANQADCgEIAQABNQAECgMIAwABAAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.',
Py='Pyrolock:BAAANQAECgIIAgAAAA==.',
['Pì']='Pìke:BAAANQABCgIIAgAAAA==.',
Qe='Qeesa:BAAANQAECgUIBQAAAA==.',
Ra='Rafikie:BAAANQADCgUIBQAAAA==.Ranni:BAAANQAECgUICgAAAA==.Rawmeat:BAAANQADCggIFgAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renix:BAAANQAECgQIBQAAAA==.',
Rh='Rhainnón:BAAANQAECgYIBgAAAA==.Rheã:BAAANQADCggIDwAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAAANQAECgEIAgAAAA==.',
Ro='Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sack:BAAANQAECgQIBgAAAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sanctity:BAAANQAECgEIAQAAAA==.Satine:BAAANQADCgYICgAAAA==.',
Sc='Scratlord:BAAANQADCgEIAQAAAA==.',
Se='Sevinas:BAAANQADCggIEgAAAA==.',
Sh='Shamthis:BAAANQAECgQIBAAAAA==.Shamwoww:BAAANQADCgMIAgABNQAECgcIDwABAAAAAA==.Shelly:BAAANQADCgYIBgAAAA==.Shlumpcane:BAAANQAECgMIBgAAAA==.Shokcz:BAAANQADCgMIAwAAAA==.Shámjackson:BAAANQAECgcIDgAAAA==.',
Si='Silvey:BAAANQADCggIEwAAAA==.Sithknight:BAAANQABCgQIAgAAAA==.Sithtracker:BAAANQABCgYICAAAAA==.Sizzurp:BAAANQADCgcICQAAAA==.',
Sk='Skeletorque:BAAANQADCgYICQABNQADCgcICwABAAAAAA==.',
Sm='Smallwdruid:BAAANQADCgIIAgAAAA==.',
Sn='Snow:BAAANQADCgcIBwABNQAECgQIBwABAAAAAA==.Snowfawn:BAAANQADCgYICwABNQAECgMIAwABAAAAAA==.Snusnurae:BAAANQADCgMIBQAAAA==.',
Sp='Splishsplásh:BAAANQADCggIEgAAAA==.Sprattyboii:BAAANQAECgIIAwAAAA==.',
Ss='Sscarlet:BAAANQADCgcIEAAAAA==.',
St='Starzia:BAAANQAECgEIAQAAAA==.Storee:BAAANQAECgQIBAAAAA==.',
Su='Sunk:BAAANQADCggIEwAAAA==.',
Sw='Swiftblossom:BAAANQADCgMIBwAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcICwABNQAECgQIBAABAAAAAA==.Tanadria:BAAANQADCggICQAAAA==.Tapioca:BAAANQADCgYICAAAAA==.Taterdot:BAAANQAECgQIBAAAAA==.',
Te='Telm:BAAANQAECgIIAgAAAA==.Tentilious:BAAANQABCgIIAgAAAA==.',
Th='Thaÿne:BAAANQAECgIIAgAAAA==.Thebestpally:BAAANQAECgQIBwAAAA==.Thenemisis:BAAANQADCggIEgAAAA==.Thiccidàn:BAAANQADCgYIBgAAAA==.Thiccsister:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Thiccstraza:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
Ti='Tidds:BAAANQAECgMIAwAAAA==.',
To='Totemdown:BAACNQAFFIEFAAIFAAQJhxLCAQBjAQAFAAQJhxLCAQBjAQA1AAQKgRgAAgUACQkVJYsAANADAAUACQkVJYsAANADAAE1AAQKBAgIAAEAAAAA.',
Tr='Traedaei:BAAANQADCgQIBAAAAA==.Trazarath:BAAANQAECgYICgAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgIIAwABNQADCggIDgABAAAAAA==.',
Us='Usdaprime:BAAANQADCgIIAgABNQADCgcICwABAAAAAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECgQIBgABNQAECgQIBgABAAAAAQ==.',
Va='Valedaren:BAAANQADCgUIBQAAAA==.Varala:BAAANQADCgYICgAAAA==.',
Ve='Vel:BAABNQAECoEdAAIGAAkJGSPAAgCZAwAGAAkJGSPAAgCZAwAAAA==.Veritas:BAAANQAECgUIBwAAAA==.Veskara:BAAANQADCgQIBwAAAA==.',
Vy='Vylana:BAAANQADCgcIDAABNQAECgYICAABAAAAAA==.',
['Vè']='Vèl:BAAANQADCgYICwABNQAECgkJHQAGABkjAA==.',
Wa='Warity:BAAANQAECgMIAwAAAA==.',
We='Wetdotpal:BAAANQADCggIDwAAAA==.Wetdotthirst:BAAANQADCgQIBAAAAA==.',
Wh='Whiteabyss:BAAANQAECgIIAgAAAA==.',
Xe='Xerxseizee:BAAANQADCggICAAAAA==.',
Xo='Xomby:BAAANQADCgcIDQAAAA==.',
['Xì']='Xìon:BAAANQAECgQIBAAAAA==.',
Ya='Yayrri:BAAANQADCggIEwAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQADCgYIBgAAAA==.',
Za='Zatarra:BAAANQADCgUIBwAAAA==.',
Ze='Zex:BAAANQADCgMIBQABNQAECgEIAQABAAAAAA==.Zextron:BAAANQAECgEIAQAAAA==.',
Zi='Ziaya:BAAANQADCggICAAAAA==.',
Zo='Zolaeus:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.',
Zu='Zuboo:BAAANQAECgEIAQAAAA==.',
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
