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

local lookup = {'Shaman-Restoration','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','Hunter-Marksmanship','Mage-Frost','Mage-Arcane','Shaman-Elemental','Shaman-Enhancement','Monk-Brewmaster','Monk-Mistweaver','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Unholy','Hunter-BeastMastery',}
local provider = {region='US',realm='Antonidas',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abisio:BAAANQAECgEJAQAAAA==.Abyssius:BAAANQADCgIIAgAAAA==.',
Ac='Achillesheal:BAAANQADCgIIAwAAAA==.Acuna:BAAANQAECgUJBQAAAA==.Acursedpeen:BAAANQADCggJCwAAAA==.',
Ad='Aderna:BAAANQADCgUIBQAAAA==.Adoryn:BAEANQAECgQJBQAAAA==.',
Ae='Aelara:BAAANQADCgYJBgABNQAECgkJGAABALQQAA==.Aessan:BAAANQAECgUJDAAAAA==.',
Ag='Agares:BAAANQAECgYIEgAAAA==.',
Ai='Aisathya:BAAANQAECgIIAgAAAA==.',
Ak='Akrinn:BAAANQADCggICAAAAA==.',
Al='Aleysia:BAAANQAECgQIBAABNQAECgkJGAABALQQAA==.',
Am='Amberfox:BAAANQADCgYIEAAAAA==.Amberscale:BAAANQAECgYIDAAAAA==.',
An='Ancientiur:BAAANQADCgIIAgABNQAECgIIAwACAAAAAA==.Ancientuur:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.Andazaren:BAAANQAECgYJDQAAAA==.Andracca:BAAANQADCgQIBAAAAA==.Angrulus:BAAANQAECgYICwAAAA==.Animal:BAAANQADCgMIAwAAAA==.Animlshiftr:BAAANQAECgQJBAAAAA==.',
Ap='Apollo:BAAANQAECgQJBAAAAA==.',
Ar='Arixx:BAAANQABCgIIAgAAAA==.Aryllyn:BAAANQADCgcJDwAAAA==.',
As='Asti:BAAANQAECgIIAgAAAA==.Astralon:BAAANQAECgQIBgAAAA==.',
Az='Azrathalos:BAAANQADCggICwAAAA==.',
Ba='Baldric:BAAANQABCgMIBAABNQAECgUICQACAAAAAA==.',
Be='Bearett:BAAANQAECgUJDgAAAA==.Bearwolf:BAAANQABCgEIAQAAAA==.Belyrune:BAAANQADCgMIAwABNQAECgYIEgACAAAAAA==.Belysurge:BAAANQAECgYIEgAAAA==.Bernd:BAAANQAECgIIAgAAAA==.Beörn:BAAANQAECgUIDAAAAA==.',
Bi='Birgir:BAAANQADCgYICgAAAA==.',
Bl='Blackgrinn:BAAANQADCgEIAQAAAA==.Blackkgrin:BAAANQAECgUICgAAAA==.',
Bo='Bowie:BAAANQABCgEIAQAAAA==.',
Br='Braids:BAAANQAECgIIAgAAAA==.Breezy:BAABNQAECoEYAAIDAAgKxxQlTgAcAgADAAgKxxQlTgAcAgAAAA==.Brianelf:BAAANQADCgIIAgAAAA==.Bruche:BAAANQAECgQJBQAAAA==.',
Bu='Buttrbiskit:BAAANQAECggIDwAAAA==.',
By='Byanca:BAAANQAECgYIEAAAAA==.',
Ca='Caine:BAAANQAECgQJBQAAAA==.Casey:BAAANQADCgcIGwAAAA==.Castyblasty:BAAANQAECgYIDwAAAA==.',
Ce='Cellina:BAAANQAECgQIBwAAAA==.',
Ch='Chiman:BAAANQADCgcJCQABNQAECgQIBAACAAAAAA==.',
Cl='Classá:BAAANQAECgcIEAAAAA==.',
Co='Codedd:BAAANQADCgYIDAAAAA==.Corin:BAABNQAECoEZAAMEAAcKOh/cNQAjAgAEAAYKfx/cNQAjAgADAAQKMhicrQAMAQAAAA==.Corlys:BAAANQAECgIIAgAAAA==.Cottonmouth:BAAANQADCgMIAwAAAA==.',
Cr='Crispìn:BAAANQAECgMJBwAAAA==.Crossbones:BAAANQABCgEIAQAAAA==.Crue:BAAANQAECgQIBQAAAA==.',
Cu='Cupofcoffee:BAAANQADCgIJAgAAAA==.',
Cy='Cynboom:BAAANQADCgQIBAAAAA==.Cyndee:BAAANQAECgYIDQAAAA==.Cynnafrost:BAAANQADCgQJCAAAAA==.',
Da='Dadda:BAABNQAECoEYAAIFAAkKfhVMFABzAgAFAAkKfhVMFABzAgAAAA==.Daisynukes:BAAANQAECgQIBwABNQAECgYJDwACAAAAAA==.Daloah:BAAANQABCgQIBQAAAA==.Damascus:BAAANQAECgUICQAAAA==.Dankdruid:BAAANQADCgUICgABNQADCggJFgACAAAAAA==.Darkschi:BAAANQAECgQJBQAAAA==.Darthwing:BAAANQADCgcIDgAAAA==.Dartos:BAAANQAECgYIEAAAAA==.',
De='Deepmagic:BAAANQAECgQICAAAAA==.Deepshadow:BAAANQAECgEIAQAAAA==.Demyx:BAAANQABCgUIBQAAAA==.Destrûction:BAAANQADCgUIBQAAAA==.',
Di='Diluvium:BAAANQAECgUJCgAAAA==.Discodank:BAAANQADCggJFgAAAA==.',
Dj='Djpleasant:BAABNQAECoEjAAMGAAkKfyEZAQBWAwAGAAkKfyEZAQBWAwAHAAUKTRlF1gBUAQAAAA==.',
Do='Dontcare:BAAANQAECggIEwAAAA==.',
Dr='Dronos:BAAANQAECgYICwAAAA==.',
Dw='Dwailn:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûo:BAABNQAECoEWAAMIAAkKJRczLwBOAgAIAAgKqhgzLwBOAgAJAAEK/wooJABIAAAAAA==.',
Ea='Eatmorpizza:BAAANQAECgQJBAAAAA==.',
Ee='Eegnormu:BAAANQAECgQJCQAAAA==.Eegroll:BAABNQAECoEcAAMKAAgKuhbLCAAvAgAKAAgKuhbLCAAvAgALAAcKqgWnHgAYAQAAAA==.',
Eg='Egraw:BAAANQAECgIJAgAAAA==.',
El='Elendar:BAAANQADCggICgAAAA==.',
Em='Emilwhaury:BAAANQADCgYIBgAAAA==.',
Ep='Epia:BAAANQAECggJBAAAAA==.',
Es='Esdéath:BAABNQAECoEhAAIMAAgKyhVxLwA5AgAMAAgKyhVxLwA5AgAAAA==.Essaila:BAAANQAECgYIBwAAAA==.',
Et='Etherwalker:BAAANQAECgYICwAAAA==.',
Ex='Excision:BAAANQAECgUJDgAAAA==.',
Fa='Fahbio:BAAANQAECgMIBgAAAA==.Fatallock:BAAANQAECggIEwAAAA==.',
Fe='Felpaws:BAAANQADCgEIAQAAAA==.',
Fi='Firetelm:BAAANQAECgQIBQAAAA==.Fishdish:BAAANQADCgMIAwAAAA==.Fistsmither:BAAANQADCgMIAwABNQAECgYIBgACAAAAAA==.',
Fl='Flailuid:BAAANQAECgMJBwAAAA==.',
Fo='Forthstryke:BAAANQADCggIEQAAAA==.',
Fr='Fresita:BAAANQADCgYJCwAAAA==.Fridaychill:BAAANQAECgYIEwAAAA==.Frozarke:BAAANQAECgcIEwAAAA==.',
Fu='Fudd:BAAANQAECgMIBAAAAA==.Funk:BAAANQABCgIIAwABNQADCgMIAwACAAAAAA==.Fupa:BAAANQAECgEIAgAAAA==.',
Ga='Garou:BAAANQAECgYICgAAAA==.Garres:BAAANQAECgQJCAAAAA==.',
Ge='Genius:BAAANQAECgQJBAAAAA==.',
Gi='Gibley:BAAANQAECgQIBAAAAA==.',
Gl='Gladorf:BAAANQADCgMIAwAAAA==.',
Gn='Gnazgul:BAAANQADCggJIAAAAA==.Gnomie:BAAANQAECgQJBQAAAA==.Gnomio:BAAANQAECgQJBQAAAA==.',
Go='Gouge:BAAANQAECgYJFAAAAQ==.',
Gr='Griffynshu:BAAANQAECgQJBAAAAA==.Grrv:BAAANQABCgQIBgAAAA==.Grudgetotem:BAAANQAECgQICAABNQAECgYICgACAAAAAA==.',
Gu='Gungnir:BAAANQAECgcIDQAAAA==.',
Ha='Haki:BAAANQAECgQIBwAAAA==.Handiboy:BAABNQAECoEaAAIMAAkKPSV5AgCmAwAMAAkKPSV5AgCmAwAAAA==.Hayate:BAAANQAECgQJAwAAAA==.',
He='Healabull:BAAANQADCgYIDgABNQAECgYJEAACAAAAAA==.Heimdall:BAAANQAECgYIDwAAAA==.Hellaholy:BAAANQAECgIIAgAAAA==.Hellavva:BAAANQADCggJCgAAAA==.Henchling:BAAANQAECgYJEAAAAA==.',
Ho='Holexios:BAAANQAECgQIBAAAAA==.Horine:BAAANQAECgIJAwAAAA==.',
Ic='Icieblade:BAAANQADCgEIAQAAAA==.',
Im='Immeira:BAAANQAECgUJDwAAAA==.',
In='Intense:BAAANQADCgEJAQAAAA==.',
Ja='Jackiix:BAAANQADCgYIBgAAAA==.Jackmends:BAABNQAECoEiAAIMAAkKcCFsBACBAwAMAAkKcCFsBACBAwAAAA==.Jacksprouts:BAAANQAECgIIAgAAAA==.Jarryl:BAAANQAECggJCAAAAA==.',
Je='Jenoside:BAAANQAECgcIEwAAAQ==.',
Ji='Jindu:BAAANQAECggICAAAAA==.',
Jo='Journei:BAAANQAECgUJCQAAAA==.',
Ju='Judging:BAAANQAECgIIAgAAAA==.',
Ka='Kaedrenis:BAAANQADCgYIGQAAAA==.',
Ke='Kegz:BAAANQAECgUJCwAAAA==.Kellayna:BAAANQAECgIJAgAAAA==.Keylö:BAAANQAECgQIBQAAAA==.',
Kh='Khoulethius:BAAANQABCgIIAgAAAA==.',
Ki='Kimbot:BAAANQADCgUJBgAAAA==.',
Kl='Klerik:BAABNQAECoEoAAQNAAkKxiKTBwBaAwANAAkKxiKTBwBaAwAOAAYKZw4JHwBVAQAPAAEKCgZMJAAvAAAAAA==.',
Kn='Kníghtmare:BAAANQAECgQIBQAAAA==.',
Ko='Koragg:BAABNQAECoEmAAIQAAkKCyBuCwAjAwAQAAkKCyBuCwAjAwAAAA==.Korah:BAAANQADCgIIAgAAAA==.Korama:BAAANQABCgUIBwAAAA==.Korrag:BAAANQADCggIEwAAAA==.Kozarke:BAAANQAECgIIAgAAAA==.',
Kr='Krissia:BAAANQAECgYJEAAAAA==.',
Ky='Kymerah:BAAANQABCgYICAAAAA==.Kyntaliia:BAAANQADCgYIBgAAAA==.',
['Kî']='Kîn:BAAANQAECgMIBgAAAA==.',
La='Laisera:BAAANQAECgUICgAAAA==.Lalipop:BAAANQAECgMIBgAAAA==.Landroval:BAAANQAECgIIAgAAAA==.Langedamort:BAAANQADCgEIAQAAAA==.Lawson:BAAANQAECgQJBQAAAA==.',
Le='Leeoh:BAAANQAECgUICQAAAA==.Leeohd:BAAANQADCggIHgAAAA==.Lenthaden:BAAANQAECgEIAQAAAA==.',
Li='Lightsmasher:BAAANQADCgMIAwAAAA==.Lissetteliz:BAAANQADCgUIBQAAAA==.Littlemynx:BAAANQAECgIJAgAAAA==.',
Lo='Lovenky:BAAANQADCgUIBgAAAA==.',
Lu='Lujuria:BAAANQAECgYIDgAAAA==.Lumawig:BAAANQADCgcIBwAAAA==.Lunchdk:BAAANQAECgIJAgAAAA==.',
Ly='Lyreth:BAAANQAECgYIEAAAAA==.',
Ma='Madax:BAAANQAECgQJBQABNQAECgYIEgACAAAAAA==.Manach:BAAANQADCgYIEgAAAA==.',
Me='Meaculpa:BAAANQADCgMIAwAAAA==.Megamilk:BAAANQAECgYIEwAAAA==.Meganfox:BAAANQAECgQJCAABNQAECggIEwACAAAAAA==.Merilde:BAAANQADCgcIDgAAAA==.Metrolinea:BAAANQAECgcJDgAAAA==.',
Mi='Milliy:BAAANQAECgUICQAAAA==.Minamel:BAAANQAECgEJAQABNQAECgUJCwACAAAAAA==.Missbehaving:BAAANQAECgMIAwAAAA==.',
Mo='Mojorisin:BAAANQADCgQIBAAAAA==.Morefire:BAAANQAECggJCQAAAA==.Mosmos:BAAANQAECgQJBAAAAA==.',
Mu='Muddbutt:BAAANQADCgUIBQAAAA==.Mumra:BAAANQAECgUJDQAAAA==.',
My='Mynxy:BAAANQADCgUICAAAAA==.Mysticblazie:BAAANQAECgYJDwAAAA==.',
Na='Nannette:BAAANQAECgMIBAAAAA==.Narag:BAAANQAECgQIBAAAAA==.',
Ne='Neph:BAAANQAECggIAgAAAA==.Nephorma:BAAANQADCggJCgAAAA==.Newport:BAAANQAECgUJDgAAAA==.',
Ni='Niara:BAAANQAECgcJDwAAAA==.Ninewings:BAAANQADCgYIBgAAAA==.Ninisina:BAAANQAECgQIBgAAAA==.Nithén:BAAANQADCggJDwAAAA==.',
No='Nonaleeta:BAAANQADCgcIFgAAAA==.Novaa:BAAANQADCgUJCAAAAA==.Nowhere:BAAANQAECgUIBwABNQAECgYIBgACAAAAAA==.Nowon:BAAANQAECgcIDQAAAA==.',
Nu='Nudream:BAAANQAECgQICAAAAA==.Nuka:BAAANQADCgYJBgAAAA==.',
Oc='Oceansong:BAAANQADCgQICAAAAA==.',
Ol='Oldjerry:BAAANQAECgMIAwABNQAECgYIBgACAAAAAA==.',
Op='Opalyte:BAAANQAECgMIBgAAAA==.',
Oq='Oqisa:BAAANQADCgMIAwABNQAECgUJBQACAAAAAA==.',
Or='Orichalcum:BAAANQADCggICQAAAA==.Orphiee:BAAANQAECgIIBgAAAA==.',
Ov='Overtavo:BAABNQAECoEXAAQNAAgKeRnTQAAaAgANAAcKchnTQAAaAgAOAAEKqBnPWQBLAAAPAAEKExePHQBEAAAAAA==.',
Pa='Pacobell:BAAANQADCggIEgAAAA==.Pakoros:BAAANQAECgYJDwAAAA==.Palamar:BAAANQAECgQJBQAAAA==.Pandsala:BAAANQADCgYIDAABNQAECgYIDwACAAAAAA==.',
Pe='Penderin:BAAANQADCgYICgAAAA==.Perlindree:BAAANQAECgMJAwAAAA==.',
Pg='Pgorlelgy:BAAANQAECgYIDgAAAA==.',
Ph='Phanora:BAAANQADCgIIAgAAAA==.',
Pl='Platious:BAAANQAECgMIAwAAAA==.',
Po='Pookaboo:BAAANQAECgIJAgAAAA==.Popplockdot:BAAANQADCgUIBQAAAA==.',
Pr='Preacharoùnd:BAABNQAECoEXAAIRAAkKOxncDQDCAgARAAkKOxncDQDCAgABNQAECgkKFwARADsZAA==.',
Pu='Purdie:BAAANQADCgEIAQABNQAECgUJDAACAAAAAA==.Purdienir:BAAANQADCgQJBAAAAA==.Purdieturtle:BAAANQADCggICAABNQAECgUJDAACAAAAAA==.',
Py='Pyrolock:BAAANQAECgcIDAAAAA==.',
['Pì']='Pìke:BAAANQADCgMJAwAAAA==.',
Qe='Qeesa:BAAANQAECgUJBQAAAA==.',
Ra='Radzog:BAAANQADCgMIAwAAAA==.Rafikie:BAAANQADCgUIBQAAAA==.Ranni:BAABNQAECoEYAAMBAAkKtBARQgDlAQABAAgKYxARQgDlAQAIAAUK0AtPhQAKAQAAAA==.Rawmeat:BAAANQAECgQJBAAAAA==.',
Re='Rebeca:BAAANQADCggICAAAAA==.Renix:BAAANQAECgQIBQAAAA==.',
Rh='Rhainnón:BAAANQAECgcIDQAAAA==.Rheã:BAAANQAECgMIBgAAAA==.',
Ri='Riftstrider:BAAANQADCgQIBAAAAA==.Rivulet:BAAANQAECgEIAQAAAA==.Rize:BAAANQAECgYIDwAAAA==.',
Ro='Royfenix:BAAANQADCggIDAAAAA==.',
Sa='Sack:BAAANQAECgQIBgABNQAECgYICgACAAAAAA==.Saetyl:BAAANQADCgUIBwAAAA==.Sanctity:BAAANQAECgMIBAAAAA==.Satine:BAAANQADCggIEgAAAA==.',
Sc='Scratlord:BAAANQAECgQJBgAAAA==.',
Se='Sevinas:BAAANQAECgIJAwAAAA==.',
Sh='Shadeira:BAAANQAECgYIBgAAAA==.Shamthis:BAAANQAECgYJDwAAAA==.Shamwoww:BAAANQAECgQJBgABNQAECgkKFwARADsZAA==.Shelly:BAAANQADCgcIFAAAAA==.Shlumpa:BAAANQAECgUIBQAAAA==.Shlumpcane:BAAANQAECggIBwAAAA==.Shokcz:BAAANQAECgQIBAAAAA==.Shámjackson:BAABNQAECoEbAAIBAAkKeCUFAQDOAwABAAkKeCUFAQDOAwAAAA==.',
Si='Silvey:BAAANQAECgIIAgAAAA==.Sinroot:BAAANQADCgQJBAAAAA==.Sithknight:BAAANQABCgQIBgAAAA==.Sithtracker:BAAANQABCgYICAAAAA==.Sizzurp:BAAANQAECgMIAwAAAA==.',
Sk='Skeletorque:BAAANQAECgQJBQAAAA==.',
Sm='Smallwdruid:BAAANQADCgIIAgAAAA==.',
Sn='Snow:BAAANQADCgcIBwABNQAECgcJGQAEADofAA==.Snowfawn:BAAANQAECgMJAQABNQAECggJBwACAAAAAA==.Snusnurae:BAAANQADCgMIBQAAAA==.',
So='Soape:BAAANQADCgIIAgAAAA==.',
Sp='Specialist:BAAANQAECgMIBQABNQAECggIEwACAAAAAA==.Splishsplásh:BAAANQAECgIJAwAAAA==.Spooty:BAAANQAECggJCAAAAA==.Sprattyboii:BAAANQAECgQIBwAAAA==.',
Sq='Squishydk:BAAANQADCgUJBQABNQAECgUJCgACAAAAAA==.',
Ss='Sscarlet:BAAANQAECgIJAgAAAA==.',
St='Staltis:BAAANQADCgYIBgABNQAECgcIEwACAAAAAA==.Starzia:BAAANQAECgQJBQAAAA==.Storee:BAAANQAECgUJDQAAAA==.',
Su='Sunk:BAAANQAECgIIAgAAAA==.',
Sw='Swiftblossom:BAAANQADCgUIEAAAAA==.',
Ta='Taffbones:BAAANQAECgEIAQAAAA==.Talanot:BAAANQADCgcJCwABNQAECgQIBAACAAAAAA==.Talarus:BAAANQADCgEIAQAAAA==.Tanadria:BAAANQADCggICwAAAA==.Tapioca:BAAANQAECgIIAgAAAA==.Taterdot:BAAANQAECgQIBwAAAA==.',
Te='Telm:BAAANQAECgUJCwAAAA==.Tentilious:BAAANQABCgIJBAAAAA==.Tetsu:BAAANQAECgEIAQAAAA==.',
Th='Thaka:BAAANQADCgcIBwAAAA==.Thaÿne:BAAANQAECgMIBQAAAA==.Thebestpally:BAAANQAECgcIEgAAAA==.Thenemisis:BAAANQADCggIEgAAAA==.Thiccidàn:BAAANQADCgYIBgABNQADCggICgACAAAAAA==.Thiccsister:BAAANQADCgQIBAABNQADCggICgACAAAAAA==.Thiccstraza:BAAANQADCggICgAAAA==.',
Ti='Tidds:BAAANQAECgQICwAAAA==.Tinker:BAAANQADCgYICQAAAA==.',
To='Totemdown:BAACNQAFFIENAAIBAAYKtxuKAQA0AgABAAYKtxuKAQA0AgA1AAQKgSQAAgEACQqQJSkBAMsDAAEACQqQJSkBAMsDAAE1AAQKBQgJAAIAAAAA.',
Tr='Traedaei:BAAANQADCgQIBAAAAA==.Trazarath:BAABNQAECoEfAAMSAAcKyBIGFACuAQASAAcK6A8GFACuAQATAAMK9RD5DwCsAAAAAA==.Tritankills:BAAANQADCgEIAQAAAA==.',
Tu='Turoxas:BAAANQADCgEIAQAAAA==.',
Uj='Ujio:BAAANQADCgIIAwABNQAECgMIBgACAAAAAA==.',
Us='Usdaprime:BAAANQADCgYIDAABNQAECgQJBQACAAAAAA==.Usopp:BAAANQABCgEIAQAAAA==.',
Ut='Uthilla:BAAANQAECgEIAQAAAA==.',
Uu='Uuyd:BAAANQAECgYIDQABNQAECgcIEwACAAAAAQ==.',
Va='Valedaren:BAAANQADCgUIBgAAAA==.Valefyre:BAAANQADCgUIBQAAAA==.Varala:BAAANQADCgYIEAAAAA==.',
Ve='Vel:BAABNQAECoEqAAIUAAkKdCXMAgC+AwAUAAkKdCXMAgC+AwAAAA==.Veritas:BAAANQAECgYIDQAAAA==.Veskara:BAAANQADCgYICgAAAA==.',
Vy='Vylana:BAAANQAECgUICgABNQAECgkJJwAVAOAaAA==.',
['Và']='Vàlkyrie:BAAANQADCgUJBQAAAA==.',
['Vè']='Vèl:BAAANQADCggIEQABNQAECgkJKgAUAHQlAA==.',
Wa='Warity:BAAANQAECgMIAwAAAA==.',
We='Wetdotpal:BAAANQAECgUIBQAAAA==.Wetdotthirst:BAAANQADCgQIBAAAAA==.',
Wh='Whiteabyss:BAAANQAECgUJCwAAAA==.',
Wr='Wraith:BAAANQAECgMIAwAAAA==.',
Xe='Xerxseizee:BAAANQAECgIJAgAAAA==.',
Xo='Xomby:BAAANQAECgMJAwAAAA==.',
['Xì']='Xìon:BAAANQAECgUJDgAAAA==.',
Ya='Yayrri:BAAANQAECgIIAgAAAA==.',
Ye='Yersipestis:BAAANQABCgMIAwAAAA==.',
Yo='Youngjedi:BAAANQAECgIIAgAAAA==.',
Za='Zatarra:BAAANQADCgUIBwAAAA==.Zavya:BAAANQADCgMJAwABNQAECgIJAgACAAAAAA==.',
Ze='Zex:BAAANQADCgUIBwABNQAECgQJCQACAAAAAA==.Zextron:BAAANQAECgQJCQAAAA==.',
Zi='Ziaya:BAAANQAECgIJAgAAAA==.',
Zo='Zolaeus:BAAANQADCgcIDQABNQAECgQIBAACAAAAAA==.',
Zu='Zuboo:BAAANQAECgQJBQAAAA==.',
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
