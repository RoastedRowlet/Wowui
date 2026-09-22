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

local lookup = {'Priest-Shadow','Warrior-Arms','DemonHunter-Vengeance','Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Evoker-Devastation','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Mage-Arcane','Monk-Windwalker','Paladin-Retribution','DemonHunter-Devourer',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aarchon:BAAANQAECgUICgAAAA==.',
Ad='Aduin:BAAANQAECgEJAQAAAA==.',
Ae='Aedarelyn:BAAANQADCgYIFgAAAA==.Aellita:BAAANQADCgcICwAAAA==.Aeschylus:BAAANQADCgIIAwAAAA==.',
Af='Afkinlife:BAAANQADCgYJBwAAAA==.',
Ak='Akky:BAAANQAECgQJBAAAAA==.Aksafiya:BAAANQAECgUIDAAAAA==.',
Al='Alal:BAAANQADCgMJAwAAAA==.Alaras:BAABNQAECoEXAAIBAAkKpxJaEwBrAgABAAkKpxJaEwBrAgAAAA==.Aleesha:BAAANQADCgYJBwAAAA==.Allaras:BAAANQADCgYIDAAAAA==.Allistaris:BAAANQAECgQJBAAAAA==.Allrianne:BAAANQADCgQJCgAAAA==.Allyriae:BAAANQAECgYJBgAAAA==.Alphá:BAAANQAECgYJDwAAAA==.Althoraty:BAAANQAECgYJDAAAAA==.Alyx:BAAANQADCgcJCAAAAA==.',
Am='Amberlilly:BAAANQAECgEJAQAAAA==.',
An='Andoros:BAAANQAECgMJBgAAAA==.Anzurath:BAAANQAECgUICgAAAA==.',
Ap='Apheron:BAAANQAECgYJCwAAAA==.Applebow:BAAANQAECgEIAQAAAA==.Apples:BAAANQADCggICAAAAA==.',
Ar='Arknova:BAAANQAECgYJDgAAAA==.Arylin:BAAANQAECgIIAwAAAA==.',
As='Ashkinassi:BAEANQADCgUJBgAAAA==.Asiain:BAAANQAECgUIBgABNQAECgkJGgACAKEfAA==.Asnabel:BAAANQAECgMJAwAAAA==.',
At='Atvar:BAAANQADCggICAAAAA==.',
Au='Autumndeath:BAAANQAECgMIBQAAAA==.',
Av='Avinger:BAAANQABCggJEgAAAA==.',
Ay='Ayden:BAABNQAECoEcAAIDAAgKjhFuCADSAQADAAgKjhFuCADSAQAAAA==.',
Az='Azrim:BAAANQADCgYIDgAAAA==.Azureis:BAAANQADCgcICAAAAA==.',
Ba='Balolz:BAAANQABCgYJDAAAAA==.',
Be='Belthar:BAAANQAECgYJDQAAAA==.Bendeye:BAAANQADCgYJBgAAAA==.',
Bl='Blee:BAAANQADCggJJAAAAA==.Bluudclaaw:BAAANQADCgMIAwABNQAECgUICQAEAAAAAA==.',
Bo='Boing:BAAANQAECgQJBAAAAA==.Boomhauer:BAAANQAECgEIAQAAAA==.',
Br='Braelia:BAAANQAECgQJBgAAAA==.Braetwo:BAAANQABCggJDwABNQAECgQJBgAEAAAAAA==.Braughm:BAAANQADCgUJBQAAAA==.Breye:BAAANQAECgIIAwAAAA==.Brindria:BAAANQADCgQJBAAAAA==.Brood:BAAANQAECgUICgAAAA==.Brundles:BAAANQAECgUICgAAAA==.',
Bu='Bubblepopper:BAAANQAECgUICQAAAA==.Bunky:BAAANQADCggJIQAAAA==.',
Ca='Cailaranel:BAAANQAECgEJAQAAAA==.Calaul:BAAANQAECgUICAAAAA==.Calenbraga:BAAANQADCgcIMgAAAA==.Calisim:BAAANQADCggJGAAAAA==.Caloh:BAAANQAECgIJAgAAAA==.Cantholdagro:BAAANQAECgEIAQABNQAECgcICgAEAAAAAA==.Cassamaria:BAAANQAECgQIBgAAAA==.Cataryn:BAAANQAECgUICgAAAA==.Catt:BAAANQAECgUJDQAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECgUICgAEAAAAAA==.',
Ce='Cellebur:BAAANQADCgYJGAAAAA==.Ceta:BAAANQAECgEIAgAAAA==.',
Ch='Chalfus:BAAANQAECggIEQAAAA==.Chaszmyr:BAAANQADCggJFgAAAA==.Chewwy:BAAANQAECggIBQAAAA==.',
Ci='Cinamen:BAAANQADCgcJHgAAAA==.Cizean:BAAANQAECgEIAQAAAA==.',
Cl='Clare:BAAANQABCgQIBAABNQAECgUICgAEAAAAAA==.Closetofsmut:BAAANQADCgcIBwAAAA==.',
Cr='Craivan:BAAANQADCgUICQAAAA==.Crendoal:BAAANQADCgQIBgABNQAECgQJCgAEAAAAAA==.Crilly:BAAANQAECgMJAwAAAA==.Crowley:BAAANQADCgIIAgAAAA==.Crumpler:BAAANQAECgIJAwAAAA==.',
Cy='Cyroka:BAAANQAECgEIAQAAAA==.Cytroncutoff:BAAANQADCgYIDwAAAA==.',
Da='Dalastish:BAAANQADCggIDAAAAA==.Damia:BAAANQAECgEIAQAAAA==.Danobun:BAAANQAECgcIEQAAAA==.Darkfoxcr:BAAANQABCgIIBAAAAA==.Darsithis:BAAANQAECgEIAQAAAA==.',
De='Deadite:BAAANQAECgUICgAAAA==.Delvarrieth:BAAANQAECgEIAQAAAA==.Denth:BAAANQAECgIJAgAAAA==.Dercuur:BAAANQAECgcJDQAAAA==.Derpina:BAAANQAECgUJBQAAAA==.',
Do='Dotur:BAAANQADCgIJAgAAAA==.',
Dr='Dragonkiss:BAAANQADCgQJBwAAAA==.Drainmee:BAAANQABCgMIAwAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAAANQAECgQJBAAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAAANQADCggIFwAAAA==.',
['Dá']='Dárkbeard:BAAANQADCgUJCQAAAA==.',
Ek='Ekneirg:BAAANQAECgMIBQAAAA==.',
El='Elynth:BAAANQAECgUICgAAAA==.',
Em='Emmalily:BAAANQABCgQIBgAAAA==.',
En='Endlessyueh:BAAANQADCgQICgAAAA==.',
Ex='Extragrippy:BAAANQAECgcICgAAAA==.',
Fa='Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAAANQAECgYIDQAAAA==.Farrseer:BAAANQAECgIJAwAAAA==.Fastburn:BAAANQAECgUICgAAAA==.Fasthandslez:BAAANQADCgcIEwAAAA==.',
Fe='Felscythe:BAAANQAECgEIAQAAAA==.',
Fi='Fierrastar:BAAANQAECgQIBAAAAA==.Finshao:BAAANQAECgEIAQAAAA==.',
Fl='Flemish:BAAANQAECgEIAQAAAA==.Flextame:BAAANQADCgUJDQAAAA==.Flipalicious:BAAANQAECgYJEQAAAA==.Flipanomicon:BAAANQADCgYIDAAAAA==.Flipmode:BAAANQADCgcICAAAAA==.Flipnasty:BAAANQADCgYICAAAAA==.Flipocalypse:BAAANQADCgYIBgAAAA==.',
Fo='Foxwynn:BAAANQABCgIIAgAAAA==.',
Fr='Freyalise:BAAANQAECgUICAAAAA==.Freyjah:BAAANQADCgUIBQAAAA==.Frostycarbon:BAAANQADCgUIBQAAAA==.',
Fu='Furriousyueh:BAAANQADCgUJFAAAAA==.',
Ga='Gaia:BAAANQADCggIGgAAAA==.Gallimaufrey:BAAANQAECgQJBgAAAA==.Garodan:BAAANQADCgcIDQAAAA==.',
Ge='Gerbo:BAAANQAECgYIEQAAAA==.',
Gi='Gianavel:BAAANQAECgQICQAAAA==.Ginodh:BAAANQAECgQJBQAAAA==.Ginopally:BAAANQADCgMIAwABNQAECgQJBQAEAAAAAA==.Ginoshaman:BAAANQADCgUIBgABNQAECgQJBQAEAAAAAA==.Ginovoker:BAAANQADCgYICQABNQAECgQJBQAEAAAAAA==.',
Gr='Grilled:BAAANQADCgYJBgAAAA==.Gronke:BAAANQAECgMJAwABNQAECgMIBQAEAAAAAA==.Grubetsella:BAAANQAECgQJCgAAAA==.Grugachur:BAAANQAECgEIAQAAAA==.',
Gu='Gustice:BAAANQADCgIJAgAAAA==.',
Gy='Gyda:BAAANQADCgUJEgAAAA==.',
Ha='Hanoumatoi:BAAANQAECgIJAgAAAA==.Haralambos:BAAANQADCgYIEgAAAA==.Harlar:BAAANQADCgUJBQAAAA==.',
He='Hehasnoname:BAAANQADCgYJCQAAAA==.Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQADCgcICwAAAA==.',
Ho='Hordkilla:BAAANQAECgMJBQAAAA==.Hownowbrncw:BAAANQAECgQJBwAAAA==.',
Hy='Hyce:BAAANQAECgMJBQAAAA==.',
Ih='Ihavenoname:BAAANQADCgYJCwAAAA==.',
Il='Illusionous:BAAANQAECgEIAgAAAA==.',
In='Insoniacyun:BAAANQADCgUIDAAAAA==.',
Is='Iselian:BAAANQAECgQJBAAAAQ==.Istrix:BAAANQADCgUJBQAAAA==.',
Jb='Jbelbueno:BAAANQADCgYIBgAAAA==.Jblockiv:BAAANQADCgQJCAAAAA==.Jbprimero:BAAANQADCgQIBAAAAA==.Jbshami:BAAANQAECgUJCAAAAA==.',
Je='Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAAANQAECgMJBQAAAA==.Jetfires:BAABNQAECoEXAAIFAAgKihaZNABiAgAFAAgKihaZNABiAgAAAA==.',
Ji='Jinger:BAAANQADCggJHwAAAA==.Jinnwoo:BAAANQABCgIIAgAAAA==.',
Jo='Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQADCggJEQAAAA==.',
Ka='Kaedren:BAAANQADCgYJCwAAAA==.Kaelorien:BAAANQAECgMJBAAAAA==.Kalazaad:BAAANQAECgIJAgAAAA==.Kaldevayn:BAAANQADCgYJJQAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalrow:BAAANQADCgEJAQAAAA==.Kalto:BAAANQADCgMIAwAAAA==.Kalyna:BAAANQADCggICAAAAA==.Kardanis:BAAANQAECgUICgAAAA==.Kashe:BAAANQADCgYIFwAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAAANQAECgUICwAAAA==.Katavia:BAAANQAECgUICgAAAA==.Katrazath:BAAANQADCgUIDgAAAA==.Kaydencia:BAAANQABCgUIBwAAAA==.',
Ke='Keyallandron:BAAANQAECgIJAgAAAA==.',
Kh='Khiana:BAAANQADCgIIAgABNQAECgUICgAEAAAAAA==.',
Ki='Kiddow:BAAANQADCgYIHgAAAA==.Kierea:BAAANQADCgcIDgAAAA==.Kilrah:BAAANQADCgEIAQAAAA==.Kinte:BAAANQADCgYIBgAAAA==.Kitamii:BAAANQADCgEIAQAAAA==.Kivrin:BAAANQAECgEIAQAAAA==.',
Ko='Kokujin:BAAANQAECgQJCgAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAAANQAECgYJEQAAAA==.',
Ku='Kurumi:BAAANQADCgcJEwAAAA==.',
Kw='Kwo:BAAANQADCgQIBAAAAA==.',
Ky='Kymma:BAAANQAECgEIAQAAAA==.',
La='Laviz:BAAANQADCgYIBwAAAA==.Lazengann:BAAANQAECgQIBwAAAA==.',
Le='Leafbane:BAABNQAECoEWAAMGAAcKDhH+LACLAQAGAAcKzw/+LACLAQAHAAEKVQ/DkgA/AAAAAA==.Legevia:BAAANQAECgEIAQAAAA==.Leiris:BAAANQAECgEIAgAAAA==.Lejusticier:BAAANQADCggICAAAAA==.Leonaa:BAAANQADCgYJCgAAAA==.Leucetios:BAAANQADCgYICgAAAA==.',
Li='Liarace:BAAANQAECgUICAAAAA==.Lightbeard:BAAANQADCggIIAAAAA==.Lightforge:BAAANQAECgMIBAAAAA==.Lionessi:BAAANQADCgcIBwAAAA==.Lithika:BAAANQADCgYIBgAAAA==.',
Lo='Lorredain:BAAANQADCgYJCgAAAA==.Lothwen:BAAANQADCgYJDAAAAA==.Louisachan:BAAANQAECgIIAgAAAA==.',
Lu='Luxinine:BAAANQAECgUICAAAAA==.',
Ma='Madhawi:BAAANQAECgEIAwAAAA==.Magamon:BAAANQAECgUICgAAAA==.Malfuriia:BAAANQAECgEIAQAAAA==.Mamboke:BAAANQADCgUICQAAAA==.Margerdria:BAAANQADCgYIDwAAAA==.Mauugrim:BAAANQADCggIHgAAAA==.Maxowen:BAAANQAECgEIAQAAAA==.Maxxramas:BAAANQADCgcICgAAAA==.',
Me='Mearadan:BAAANQAECgQJBAAAAA==.Meatsweats:BAAANQAECgEJAQAAAA==.Megg:BAAANQADCgYIBgAAAA==.Mekh:BAAANQAECgEIAQAAAA==.Mel:BAAANQADCgQJCAAAAA==.Melanara:BAAANQAECgQJBAAAAA==.Melstrom:BAAANQADCgYJDgAAAA==.Meticuluslyn:BAAANQADCgYJGAAAAA==.',
Mi='Milkmaiden:BAAANQADCgQJCAAAAA==.Milkthisbull:BAAANQADCgMIAwAAAA==.Mixler:BAAANQADCgcIDgAAAA==.',
Mm='Mmeow:BAAANQADCgYIEAAAAA==.',
Mo='Moirine:BAAANQAECgEIAQAAAA==.',
Mu='Murdrmitts:BAAANQADCgQIBAAAAA==.Mustikka:BAAANQADCgIIAgABNQADCgYIDgAEAAAAAA==.',
My='Myuriyanka:BAAANQAECgYIEAAAAA==.',
['Mæ']='Mælstrôm:BAAANQABCgQIBgAAAA==.',
Na='Naahommii:BAAANQADCgUIBQAAAA==.Naeri:BAAANQAECgEIAQAAAA==.Nagualli:BAAANQADCggIEAAAAA==.Naieve:BAAANQAECgQJBAAAAA==.Nastii:BAAANQADCgEIAQAAAA==.Nastychungus:BAABNQAECoEiAAIIAAkKICGkCwBdAwAIAAkKICGkCwBdAwAAAA==.Navira:BAAANQADCggJEAAAAA==.',
Ne='Negargra:BAAANQAECggJAQAAAA==.Nephadin:BAAANQAECgEJAQAAAA==.',
Ni='Nighttiger:BAAANQADCggIFgAAAA==.Nikooli:BAAANQADCgcIGwAAAA==.',
No='Noopsie:BAAANQADCgYIJgAAAA==.Nooters:BAAANQAECgcJDwABNQAECgkJOgAJAFgmAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAAANQAECgMJBQAAAA==.',
Ny='Nyteweaver:BAAANQAECgEIAQAAAA==.',
Od='Oderica:BAAANQAECgEIAQAAAA==.Odurn:BAAANQADCgYIBgAAAA==.',
Or='Orici:BAAANQAECgIIAgABNQAECgIIAwAEAAAAAA==.',
Os='Oscarmikey:BAABNQAECoEXAAMKAAkKtRdGJwAvAgAKAAgKZRhGJwAvAgALAAEKig6xSABHAAAAAA==.Oshu:BAAANQABCggICAAAAA==.',
Ot='Ottoshot:BAAANQAECgEIAQAAAA==.Otum:BAAANQAECgMIAwAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
['Oö']='Oöps:BAAANQAECgIIAwAAAA==.',
Pa='Panamone:BAAANQABCgEIAQAAAA==.Pandamaster:BAAANQAECgcICwAAAA==.',
Pe='Pendragon:BAAANQADCgQIBQAAAA==.Pesch:BAAANQAECggICAAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Porterhouze:BAAANQABCgIIAgABNQAECgQICgAEAAAAAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.Prophetofham:BAAANQADCgYIBgAAAA==.',
Pu='Puchi:BAACNQAFFIEGAAIMAAQK6xSXAgBUAQAMAAQK6xSXAgBUAQA1AAQKgSUAAgwACQrnI4ABAJYDAAwACQrnI4ABAJYDAAAA.Pug:BAAANQADCggIEwABNQAECgQJBAAEAAAAAA==.',
Ra='Raez:BAAANQAECgQJBQAAAA==.Ragnerock:BAAANQAECgIIAgAAAA==.Raynecira:BAAANQADCggIHwAAAA==.',
Re='Reihino:BAAANQAECgEJAQAAAA==.Remixidora:BAAANQAECgQJCAABNQAECgkJHwANAIMkAA==.Reyrocko:BAAANQAECgEIAQAAAA==.Rezdh:BAAANQAECgYJDAABNQAECggIFwAIAEQfAA==.Reznal:BAAANQAECgMIAwABNQAECggIFwAIAEQfAA==.Rezvoker:BAAANQADCgUJCgABNQAECggIFwAIAEQfAA==.',
Rh='Rhage:BAAANQADCgQJBwAAAA==.Rhoaias:BAAANQADCggJEAAAAA==.Rhunyaye:BAAANQADCgUJCgAAAA==.',
Ri='Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQADCgYIBgAAAA==.Rottingturky:BAAANQAECgMIAwAAAA==.Roxane:BAAANQAECgQIBAAAAA==.',
Ru='Runningelk:BAAANQAECgEIAgAAAA==.Runscapemain:BAAANQAECgUICAAAAA==.',
Ry='Ryeti:BAAANQADCgcJEwAAAA==.',
Sa='Sahalia:BAAANQADCgUIDAABNQADCgYIDAAEAAAAAA==.Saintulrick:BAAANQAECgIIAgAAAA==.Sajuice:BAAANQAECgIIAgAAAA==.Salow:BAAANQABCgYJCgAAAA==.Sanitas:BAAANQAECgUJBQAAAA==.',
Se='Seeyen:BAAANQAFFAEJAQAAAA==.Sej:BAAANQABCgIJAgAAAA==.Seraphon:BAAANQADCggJFQAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAAEAAAAAA==.',
Sh='Shaaydo:BAAANQADCgMIAwAAAA==.Shaayllee:BAAANQAECgQIBQAAAA==.Shaaytheyha:BAAANQAECgUJBQAAAA==.Shaggyp:BAAANQAECgEIAQAAAA==.Shamump:BAAANQADCgcIBwAAAA==.Sharyl:BAAANQABCgcICwAAAA==.Shehasnoname:BAAANQADCgYJEwAAAA==.Shehulk:BAAANQAECgQJBwAAAA==.Ships:BAAANQAECgcIDQAAAA==.',
Si='Silf:BAAANQAECgEIAQAAAA==.Sini:BAAANQAECggIBgAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skibbward:BAAANQADCgQIBAABNQAECgUIBwAEAAAAAA==.Skrektwo:BAAANQAECgUJCwAAAA==.',
Sm='Smackdogg:BAACNQAFFIEMAAIKAAUKXhodBQC0AQAKAAUKXhodBQC0AQA1AAQKgR0AAgoACQoAJaAIAGYDAAoACQoAJaAIAGYDAAAA.',
So='Solarspark:BAAANQAECgYICwAAAA==.Sonomonom:BAAANQADCggIEAAAAA==.Soota:BAAANQABCgQJBwAAAA==.Sorvina:BAAANQAECgUJEQAAAA==.Soulflame:BAAANQAECgQJCgAAAA==.Soulkings:BAAANQADCggIDQAAAA==.',
Sp='Spriggs:BAAANQADCgMJBAAAAA==.',
St='Strangr:BAAANQADCggICwABNQAECgkJGQAOAFkZAA==.Stregnor:BAAANQAECgEIAQAAAA==.Styggi:BAAANQADCggICAAAAA==.Stygy:BAAANQADCgcIBwABNQADCggICAAEAAAAAA==.',
Su='Sumyunguy:BAAANQAECgUJCAAAAA==.',
Sy='Sylunia:BAAANQAECgUJBwAAAA==.Sylváñás:BAAANQABCggJCwAAAA==.Syrintha:BAAANQADCgYJBgAAAA==.',
Ta='Tachi:BAAANQADCggIGQABNQAECgQICQAEAAAAAA==.Tachie:BAAANQAECgQICQAAAA==.Talön:BAEANQAECgUJBQAAAA==.',
Te='Teranox:BAAANQABCgYJEQAAAA==.Tezzerae:BAAANQAECgEIAQAAAA==.',
Th='Theistica:BAAANQAECgEIAQAAAA==.Therin:BAAANQAECgUJCwAAAA==.Thodi:BAAANQABCgYICgAAAA==.',
To='Tongshi:BAAANQABCggIDAAAAA==.Toofast:BAAANQAECgQJBgAAAA==.Toofurrious:BAAANQADCgQJBgAAAA==.Toolotems:BAAANQAECgIIAgAAAA==.Topswimmer:BAAANQABCgIIAgAAAA==.',
Tr='Trifus:BAAANQAECgEJAQAAAA==.',
Tu='Tulao:BAAANQADCgUIBQAAAA==.',
Ty='Tylae:BAAANQADCgQIBwAAAA==.',
Ut='Utheli:BAABNQAECoEXAAIPAAgKPxfYTQAdAgAPAAgKPxfYTQAdAgAAAA==.',
Va='Vaildora:BAAANQADCgcIEwABNQAECgQICQAEAAAAAA==.Valdra:BAAANQAECgMJBQAAAA==.Vane:BAAANQADCgEIAQAAAA==.Vanillacain:BAAANQADCgMIAwAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgQJCgAAAA==.',
Vl='Vlonet:BAAANQAECgcJEgAAAA==.',
Vn='Vnasty:BAAANQAECgIIAgABNQAECgkJIgAIACAhAA==.',
Wi='Wilken:BAAANQADCgcJGwAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwAEAAAAAA==.Wiva:BAAANQAECgQIBgAAAA==.',
Wo='Wolfsokol:BAAANQAECgUJCQAAAA==.',
Wr='Wreckoner:BAAANQAECgUICgAAAA==.',
Xa='Xavencia:BAAANQADCgYICgAAAA==.',
Xi='Xinthos:BAAANQADCgcIBwAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Yu='Yukiakari:BAAANQADCgQIBQAAAA==.',
Za='Zakainu:BAAANQAECgQIBwAAAA==.Zallister:BAAANQADCggJGQAAAA==.Zansarutobi:BAAANQABCgYIBgAAAA==.Zarathoszan:BAAANQAECgQJCgAAAA==.',
Ze='Zedator:BAAANQAECgUJDAAAAA==.Zeedle:BAAANQABCgQIBAAAAA==.Zelgaddis:BAAANQAECgQJBAAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zh='Zhansaya:BAAANQADCgYIDAAAAA==.',
Zr='Zriana:BAAANQADCggJGQAAAA==.',
Zs='Zsarilya:BAAANQAECgEIAQAAAA==.',
Zu='Zurgen:BAAANQAECgQJCQAAAA==.',
['Àn']='Àndrol:BAAANQADCgYJBgABNQAECgkJGAAQAGgVAA==.',
['Êc']='Êclipse:BAEANQAECgYIDgAAAA==.',
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
