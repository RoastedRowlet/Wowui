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

local lookup = {'Priest-Shadow','Priest-Discipline','DeathKnight-Frost','Paladin-Retribution','Warrior-Arms','DemonHunter-Vengeance','DeathKnight-Blood','Unknown-Unknown','Mage-Arcane','Shaman-Elemental','Mage-Frost','Shaman-Restoration','Hunter-BeastMastery','Evoker-Devastation','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Warlock-Demonology','Monk-Windwalker','DemonHunter-Devourer',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aarchon:BAAANQAECgUIDwAAAA==.',
Ad='Aduin:BAAANQAECgEIAQAAAA==.',
Ae='Aedarelyn:BAAANQADCgcIFwAAAA==.Aellita:BAAANQADCggIDAAAAA==.Aenoryae:BAAANQADCgYIBgAAAA==.Aeschylus:BAAANQADCgIIAwAAAA==.',
Af='Afkinlife:BAAANQADCgYJBwAAAA==.',
Ai='Aias:BAAANQADCgcIBwAAAA==.',
Ak='Akky:BAAANQAECgYICgAAAA==.Aksafiya:BAABNQAECoEcAAMBAAYKShCeLQBmAQABAAYKShCeLQBmAQACAAEK5QF2JwAjAAAAAA==.',
Al='Alal:BAAANQADCgUICAAAAA==.Alaras:BAABNQAECoEZAAIBAAkKGxRZFwBZAgABAAkKGxRZFwBZAgAAAA==.Aleesha:BAAANQADCgYJBwAAAA==.Alissia:BAAANQADCgYIBgAAAA==.Allaras:BAAANQADCgYIDAAAAA==.Allistaris:BAAANQAECgYIBgAAAA==.Allrianne:BAAANQAECgEIAQAAAA==.Allyriae:BAAANQAECgYIDAAAAA==.Alphá:BAABNQAECoEZAAIDAAgKBQxsNACeAQADAAgKBQxsNACeAQAAAA==.Althoraty:BAAANQAECgYIDQAAAA==.Alyx:BAAANQADCgcICAAAAA==.',
Am='Amberlilly:BAAANQAECgQIBQAAAA==.',
An='Andoros:BAAANQAECgUICwAAAA==.Anzurath:BAAANQAECgUIDwAAAA==.',
Ap='Apheron:BAAANQAECgcIEgAAAA==.Apollimy:BAAANQAECggIBgAAAA==.Applebow:BAAANQAECgMIBAAAAA==.Apples:BAAANQADCggICwAAAA==.',
Ar='Arknova:BAABNQAECoEWAAIEAAgKPxc0VwA+AgAEAAgKPxc0VwA+AgAAAA==.Arylin:BAAANQAECgIIAwAAAA==.',
As='Asheram:BAAANQADCgEIAQAAAA==.Ashkinassi:BAEANQADCgUJBgAAAA==.Asiain:BAAANQAECgUIBgABNQAECgkJHQAFAKEfAA==.Asnabel:BAAANQAECgUICAAAAA==.',
At='Atvar:BAAANQADCggICAAAAA==.',
Au='Autumndeath:BAAANQAECgMIBQAAAA==.',
Av='Avinger:BAAANQABCggIFAAAAA==.',
Ay='Ayden:BAABNQAECoEcAAIGAAgKjhEaCwDBAQAGAAgKjhEaCwDBAQAAAA==.',
Az='Azorain:BAAANQADCgQIBAAAAA==.Azrim:BAAANQADCgYIDgAAAA==.Azureis:BAAANQADCgcICAAAAA==.',
Ba='Balolz:BAAANQABCgYIDwAAAA==.',
Be='Belthar:BAABNQAECoEVAAIHAAgK+w/bQAC4AQAHAAgK+w/bQAC4AQAAAA==.Bendeye:BAAANQADCgYICwAAAA==.',
Bl='Blee:BAAANQADCggILAAAAA==.Bluudclaaw:BAAANQADCgMIAwABNQAECgUIDgAIAAAAAA==.',
Bo='Boing:BAAANQAECgYICgAAAA==.Boomhauer:BAAANQAECgMIBAAAAA==.',
Br='Braelia:BAAANQAECgUICwAAAA==.Braetwo:BAAANQABCggJDwABNQAECgUICwAIAAAAAA==.Braughm:BAAANQADCgUJBQAAAA==.Breye:BAAANQAECgUICAAAAA==.Brindria:BAAANQADCgQJBAAAAA==.Brood:BAAANQAECgUIDAAAAA==.Brundles:BAAANQAECgUIDwAAAA==.',
Bu='Bubblepopper:BAAANQAECgYIDwAAAA==.Bunky:BAAANQAECgEIAQAAAA==.',
Ca='Cailaranel:BAAANQAECgMIBAAAAA==.Calaul:BAAANQAECgYIDAAAAA==.Calenbraga:BAAANQADCggIOwAAAA==.Calisim:BAAANQADCggIIAAAAA==.Caloh:BAAANQAECgIIAwAAAA==.Cantholdagro:BAAANQAECgEIAQABNQAECgcICgAIAAAAAA==.Cassamaria:BAAANQAECgUIBwAAAA==.Cataryn:BAAANQAECgUIDwAAAA==.Catt:BAAANQAECgUIEgAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECgUIDwAIAAAAAA==.',
Ce='Cellebur:BAAANQADCgcIGQAAAA==.Ceta:BAAANQAECgUIBwAAAA==.',
Ch='Chalfus:BAABNQAECoEWAAIJAAgKkhL1jQAjAgAJAAgKkhL1jQAjAgAAAA==.Chaszmyr:BAAANQADCggIHQAAAA==.Chewwy:BAAANQAECggICQAAAA==.',
Ci='Cinamen:BAAANQADCgcIJQAAAA==.Cizean:BAAANQAECgEIAgAAAA==.',
Cl='Clare:BAAANQABCgQIBAABNQAECgUIDwAIAAAAAA==.Closetofsmut:BAAANQADCgcIBwAAAA==.',
Cr='Craivan:BAAANQADCgUICQAAAA==.Crendoal:BAAANQADCgQIBgABNQAECgQIDQAIAAAAAA==.Crilly:BAAANQAECgMJAwAAAA==.Crowley:BAAANQADCgQIBAAAAA==.Crumpler:BAAANQAECgYICQAAAA==.Crüsnik:BAAANQADCgMIAwAAAA==.',
Cy='Cyroka:BAAANQAECgEIAgAAAA==.Cytroncutoff:BAAANQADCgYIDwAAAA==.',
Da='Dalastish:BAAANQADCggIDAAAAA==.Damia:BAAANQAECgMIBAAAAA==.Danobun:BAABNQAECoEdAAIKAAkKIx1EHQDqAgAKAAkKIx1EHQDqAgAAAA==.Darkfoxcr:BAAANQABCgIIBAAAAA==.Darsithis:BAAANQAECgMIBAAAAA==.',
De='Deadite:BAAANQAECgUIDwAAAA==.Deadstealth:BAAANQADCgYIBgAAAA==.Delphirose:BAAANQABCggIDwABNQADCgcIFwAIAAAAAA==.Delvarrieth:BAAANQAECgEIAgAAAA==.Denth:BAAANQAECgMIBQAAAA==.Dercuur:BAAANQAECgcIEgAAAA==.',
Do='Dondeestasto:BAAANQADCgMIAwAAAA==.Dotur:BAAANQADCgIJAgAAAA==.',
Dr='Dragonkiss:BAAANQADCgQJBwAAAA==.Drainmee:BAAANQAECgEIAQAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAAANQAECgYICgAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAAANQADCggIFwAAAA==.',
['Dá']='Dárkbeard:BAAANQAECgEIAQAAAA==.',
Ek='Ekneirg:BAAANQAECgUICgAAAA==.',
El='Elynth:BAAANQAECgUIDwAAAA==.',
Em='Emmalily:BAAANQAECgEIAQAAAA==.',
En='Endlessyueh:BAAANQADCgQIDgAAAA==.',
Ex='Extragrippy:BAAANQAECgcICgAAAA==.',
Fa='Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAABNQAECoEXAAILAAgKJwt/CwC2AQALAAgKJwt/CwC2AQAAAA==.Fangren:BAAANQAECgEIAQAAAA==.Farrseer:BAAANQAECgUICAAAAA==.Fastburn:BAAANQAECgUIDwAAAA==.Fasthandslez:BAAANQADCggIFQAAAA==.',
Fe='Felscythe:BAAANQAECgEIAgAAAA==.',
Fi='Fierrastar:BAAANQAECgYICgAAAA==.Finshao:BAAANQAECgEIAgAAAA==.',
Fl='Flemish:BAAANQAECgMIBAAAAA==.Flextame:BAAANQADCgUJDQAAAA==.Flipalicious:BAABNQAECoEcAAMKAAgKJxTmXQC2AQAKAAcKhhHmXQC2AQAMAAcKig5ddQBTAQAAAA==.Flipanomicon:BAAANQADCgYIDAAAAA==.Flipkicks:BAAANQADCgYICgAAAA==.Flipmode:BAAANQADCgcIDQAAAA==.Flipnasty:BAAANQADCgYICwAAAA==.Flipocalypse:BAAANQADCgYICgAAAA==.',
Fo='Foxwynn:BAAANQABCgIIAgAAAA==.',
Fr='Freyalise:BAAANQAECgUIDQAAAA==.Freyjah:BAAANQADCgUIBQAAAA==.Frostycarbon:BAAANQADCgYICwAAAA==.',
Fu='Furriousyueh:BAAANQADCgUIFwAAAA==.',
Ga='Gaia:BAAANQAECgMIAwAAAA==.Gallimaufrey:BAAANQAECgQIBgAAAA==.Garodan:BAAANQADCgcIDQAAAA==.',
Ge='Gerbo:BAABNQAECoEZAAIJAAcK/gmW1gCIAQAJAAcK/gmW1gCIAQAAAA==.',
Gi='Gianavel:BAAANQAECgUIDgAAAA==.Ginodh:BAAANQAECgQIBgAAAA==.Ginopally:BAAANQADCgMIAwABNQAECgQIBgAIAAAAAA==.Ginoshaman:BAAANQADCgUIBgABNQAECgQIBgAIAAAAAA==.Ginovoker:BAAANQADCgYICQABNQAECgQIBgAIAAAAAA==.Gizelli:BAAANQAECgIIAgABNQAECgIIAgAIAAAAAA==.',
Gr='Grilled:BAAANQADCgYJBgAAAA==.Gronke:BAAANQAECgMJAwABNQAECgUICgAIAAAAAA==.Grubetsella:BAAANQAECgQIDQAAAA==.Grugachur:BAAANQAECgEIAgAAAA==.',
Gu='Gustice:BAAANQADCgIJAgAAAA==.',
Gy='Gyda:BAAANQADCgYIGAAAAA==.',
Ha='Hanoumatoi:BAAANQAECgQIBQAAAA==.Haralambos:BAAANQADCgYIEgAAAA==.Harlar:BAAANQADCgUJBQAAAA==.',
He='Hehasnoname:BAAANQADCgYJCQAAAA==.Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQADCgcICwAAAA==.',
Ho='Hordkilla:BAAANQAECgMJBQAAAA==.Hownowbrncw:BAAANQAECgQIBwAAAA==.',
Hy='Hyce:BAAANQAECgUICgAAAA==.',
Ih='Ihavenoname:BAAANQADCgYJCwAAAA==.',
Il='Illusionous:BAAANQAECgIIAwAAAA==.',
In='Insoniacyun:BAAANQADCgYIFQAAAA==.',
Is='Iselian:BAAANQAECgYICgAAAQ==.Istrix:BAAANQADCgUJBQAAAA==.',
Ja='Jadefeather:BAAANQAECgUIBwAAAA==.',
Jb='Jbelbueno:BAAANQADCgYIBgAAAA==.Jblockiv:BAAANQADCgQJCAAAAA==.Jbprimero:BAAANQADCgQIBAAAAA==.Jbshami:BAAANQAECgYIDgAAAA==.',
Je='Jenaelle:BAAANQAECggIAQABNQAECggIBgAIAAAAAA==.Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAAANQAECgUICgAAAA==.Jetfires:BAABNQAECoEfAAINAAgKkRm4OQB4AgANAAgKkRm4OQB4AgAAAA==.',
Ji='Jinger:BAAANQAECgEIAQAAAA==.Jinnwoo:BAAANQADCgMIAwAAAA==.',
Jo='Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQADCggIGQAAAA==.',
Ka='Kaedren:BAAANQADCgYIDgAAAA==.Kaelorien:BAAANQAECgUICQAAAA==.Kalazaad:BAAANQAECgQIBgAAAA==.Kaldevayn:BAAANQADCgcILQAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalrow:BAAANQAECgQIBAAAAA==.Kalto:BAAANQAECgEIAQAAAA==.Kalyna:BAAANQADCggICAAAAA==.Kardanis:BAAANQAECgUIDwAAAA==.Kashe:BAAANQADCgcIGAAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAAANQAECgYIEQAAAA==.Katavia:BAAANQAECgUIDwAAAA==.Kathii:BAAANQADCggIDAAAAA==.Katrazath:BAAANQAECgIIAgAAAA==.Kaydencia:BAAANQABCgUIBwAAAA==.',
Ke='Kelmmers:BAAANQAECgMIAgAAAA==.Keyallandron:BAAANQAECgQIBgAAAA==.',
Kh='Khiana:BAAANQADCgIIAgABNQAECgUIDwAIAAAAAA==.',
Ki='Kiddow:BAAANQADCggIIAAAAA==.Kierea:BAAANQADCgcIDgAAAA==.Kiiarah:BAAANQADCgUIBgAAAA==.Kilrah:BAAANQADCgEIAQAAAA==.Kinte:BAAANQADCgYIBgAAAA==.Kitamii:BAAANQADCgEIAQAAAA==.Kivrin:BAAANQAECgIIAgAAAA==.',
Ko='Kokujin:BAAANQAECgUIDwAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAAANQAECgcIEgAAAA==.',
Ku='Kurumi:BAAANQADCggIFAAAAA==.',
Kw='Kwo:BAAANQADCggIDgAAAA==.',
Ky='Kymma:BAAANQAECgMIBAAAAA==.',
La='Laviz:BAAANQADCgYIBwAAAA==.Lazengann:BAAANQAECgUIDAAAAA==.',
Le='Leafbane:BAABNQAECoEfAAMDAAkKURIwJQAOAgADAAkKKREwJQAOAgAHAAEK4BYEowBHAAAAAA==.Legevia:BAAANQAECgEIAQAAAA==.Leiris:BAAANQAECgUIBwAAAA==.Lejusticier:BAAANQADCggICAAAAA==.Leonaa:BAAANQADCgYIEAAAAA==.Leucetios:BAAANQAECgIIAgAAAA==.',
Li='Liarace:BAAANQAECgUICAAAAA==.Lightbeard:BAAANQADCggIKAAAAA==.Lightforge:BAAANQAECgUICQAAAA==.Lionessi:BAAANQADCgcIBwAAAA==.Lithika:BAAANQADCgYIBgAAAA==.',
Lo='Lorredain:BAAANQADCgYJCgAAAA==.Lothwen:BAAANQADCgcIEwAAAA==.Louisachan:BAAANQAECgIIAgAAAA==.',
Lu='Luxinine:BAAANQAECgYIDgAAAA==.',
Ma='Madhawi:BAAANQAECgEIBAAAAA==.Magamon:BAAANQAECgUIDwAAAA==.Magnix:BAAANQADCgQIBAABNQAECgEIAQAIAAAAAA==.Malfuriia:BAAANQAECgEIAgAAAA==.Mamboke:BAAANQADCgUIDQAAAA==.Margerdria:BAAANQADCgcIEAAAAA==.Mauugrim:BAAANQAECgIIAgAAAA==.Maxowen:BAAANQAECgEIAgAAAA==.Maxxramas:BAAANQADCgcICgAAAA==.',
Me='Mearadan:BAAANQAECgYICgAAAA==.Meatsweats:BAAANQAECgEIAQAAAA==.Megg:BAAANQADCgYIBgAAAA==.Mekh:BAAANQAECgEIAgAAAA==.Mel:BAAANQADCgQJCAAAAA==.Melanara:BAAANQAECgYICgAAAA==.Melstrom:BAAANQADCgcIFQAAAA==.Meticuluslyn:BAAANQADCgcIHAAAAA==.',
Mi='Milkmaiden:BAAANQADCgQJCAAAAA==.Milkthisbull:BAAANQADCgMIAwAAAA==.Mixler:BAAANQAECgUIBQAAAA==.',
Mm='Mmeow:BAAANQADCgYIEAABNQAECgYICgAIAAAAAA==.',
Mo='Moirine:BAAANQAECgEIAgAAAA==.',
Mu='Murdrmitts:BAAANQAECgMIAwAAAA==.Mustikka:BAAANQADCgMIAwABNQADCgYIDgAIAAAAAA==.',
My='Myuriyanka:BAABNQAECoEZAAIKAAgKsAtaWQDGAQAKAAgKsAtaWQDGAQAAAA==.',
['Mæ']='Mælstrôm:BAAANQABCgQIBgAAAA==.',
Na='Naahommii:BAAANQADCgUIBQAAAA==.Naeri:BAAANQAECgMIBAAAAA==.Nagualli:BAAANQADCggIEAAAAA==.Naieve:BAAANQAECgYICAAAAA==.Nastii:BAAANQADCgEIAQAAAA==.Nastychungus:BAABNQAECoElAAIKAAkKYiI7DgBcAwAKAAkKYiI7DgBcAwAAAA==.Navira:BAAANQADCggIGAAAAA==.',
Ne='Negargra:BAAANQAECggIBAAAAA==.Nekoda:BAAANQAECggIAwABNQAECggIBgAIAAAAAA==.Nephadin:BAAANQAECgEIAQAAAA==.',
Ni='Nighttiger:BAAANQADCggIFgAAAA==.Nikooli:BAAANQAECgQIBAAAAA==.',
No='Noopsie:BAAANQAECgQIAwAAAA==.Nooters:BAABNQAECoEgAAIDAAgK6CNlCAA6AwADAAgK6CNlCAA6AwABNQAFFAUICgAOADcZAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAAANQAECgQIBwAAAA==.',
Ny='Nyteweaver:BAAANQAECgEIAQAAAA==.',
Od='Oderica:BAAANQAECgEIAQAAAA==.Odurn:BAAANQADCgYIBgAAAA==.',
Or='Orici:BAAANQAECgIIAgABNQAECgIIAwAIAAAAAA==.',
Os='Oscarmikey:BAABNQAECoEcAAMPAAkKtReuLwAdAgAPAAgKZRiuLwAdAgAQAAIKjA/2SwB8AAAAAA==.Oshu:BAAANQADCgYIBgAAAA==.',
Ot='Ottoshot:BAAANQAECgEIAgAAAA==.Otum:BAAANQAECgMIBAAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
Ox='Oxmantle:BAAANQABCgMIBAAAAA==.',
['Oö']='Oöps:BAAANQAECgQIBwAAAA==.',
Pa='Panamone:BAAANQABCgEIAQAAAA==.Pandamaster:BAAANQAECgcICwAAAA==.',
Pe='Pendragon:BAAANQADCgQIBQAAAA==.Pesch:BAAANQAECggICAAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Porterhouze:BAAANQABCgIIAgABNQADCggICAAIAAAAAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.Prophetofham:BAAANQADCgYIBgAAAA==.',
Pu='Puchi:BAACNQAFFIELAAIRAAUKnBiDAgCsAQARAAUKnBiDAgCsAQA1AAQKgSgAAhEACQrwI2wCAHsDABEACQrwI2wCAHsDAAAA.Pug:BAAANQADCggIEwABNQAECgYICgAIAAAAAA==.',
Ra='Raez:BAAANQAECgYICgAAAA==.Ragnerock:BAAANQAECgIIAgAAAA==.Raynecira:BAAANQAECgIIAgAAAA==.',
Re='Reihino:BAAANQAECgEIAQAAAA==.Remixidora:BAAANQAECgQJCAABNQAECgkJIQAJAJskAA==.Reyrocko:BAAANQAECgEIAQAAAA==.Rezdh:BAAANQAECgYIDQAAAA==.Rezmage:BAAANQAECgQIBAABNQAECgYIDQAIAAAAAA==.Reznal:BAAANQAECgMIAwABNQAECgYIDQAIAAAAAA==.Rezvoker:BAAANQADCgUJCgABNQAECgYIDQAIAAAAAA==.',
Rh='Rhage:BAAANQADCgQIBwAAAA==.Rhoaias:BAAANQADCggIHAAAAA==.Rhunyaye:BAAANQADCgUICgAAAA==.',
Ri='Rickness:BAAANQAECgIIBAAAAA==.Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQADCgYIBgAAAA==.Rottingturky:BAAANQAECgUIBwAAAA==.Roxane:BAAANQAECgUIBQAAAA==.',
Ru='Runningelk:BAAANQAECgEIAgAAAA==.Runscapemain:BAAANQAECgUIDQAAAA==.',
Ry='Ryeti:BAAANQADCgcIGQAAAA==.',
Sa='Sahalia:BAAANQADCgUIDAABNQADCgcIEwAIAAAAAA==.Saintulrick:BAAANQAECgQIBQAAAA==.Sajuice:BAAANQAFFAIIAgAAAA==.Salow:BAAANQABCgYICgAAAA==.Sanitas:BAAANQAECgUIDQAAAA==.',
Se='Seeyen:BAABNQAECoEfAAINAAkKaiKNCQBxAwANAAkKaiKNCQBxAwAAAA==.Sej:BAAANQABCgIIAgAAAA==.Seraphon:BAAANQADCggIHAAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAAIAAAAAA==.',
Sh='Shaaydo:BAAANQADCgMIAwAAAA==.Shaayllee:BAAANQAECgQIBQAAAA==.Shaaytheyha:BAAANQAECgUICgAAAA==.Shaggyp:BAAANQAECgEIAQAAAA==.Shamump:BAAANQADCgcIBwAAAA==.Sharyl:BAAANQABCgcICwAAAA==.Shehasnoname:BAAANQADCgYJEwAAAA==.Shehulk:BAAANQAECgUICwAAAA==.Shingo:BAAANQADCgcIBwABNQAECggIJAADAO8hAA==.Ships:BAAANQAECggIEQAAAA==.',
Si='Silf:BAAANQAECgEIAQAAAA==.Sini:BAAANQAECggIBgAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skibbward:BAAANQADCgQIBAABNQAFFAIIAgAIAAAAAA==.Skrektwo:BAAANQAECgUIEAAAAA==.',
Sm='Smackdogg:BAACNQAFFIEMAAIPAAUKXhr/BwCgAQAPAAUKXhr/BwCgAQA1AAQKgR0AAg8ACQoAJWcMAEwDAA8ACQoAJWcMAEwDAAAA.',
So='Solarspark:BAAANQAECgYIEQAAAA==.Sondaladan:BAAANQADCgYICgAAAA==.Sonomonom:BAAANQADCggIEAAAAA==.Soota:BAAANQABCgQIBwAAAA==.Sorvina:BAABNQAECoEbAAISAAcK4QtcgACGAQASAAcK4QtcgACGAQAAAA==.Soulflame:BAAANQAECgYIEAAAAA==.Soulkings:BAAANQADCggIGgAAAA==.',
Sp='Spriggs:BAAANQADCgMIBAAAAA==.',
St='Strangr:BAAANQADCggICwABNQAECgkJIQATAHgcAA==.Stregnor:BAAANQAECgUIBgAAAA==.Styggi:BAAANQADCggICAAAAA==.Stygy:BAAANQADCgcIBwABNQADCggICAAIAAAAAA==.',
Su='Sumyunguy:BAAANQAECgYIDgAAAA==.',
Sy='Sylunia:BAAANQAECgUIDAAAAA==.Sylváñás:BAAANQABCggIDAAAAA==.Syrintha:BAAANQADCgYJBgAAAA==.',
Ta='Tachi:BAAANQAECgIIAgABNQAECgUIDgAIAAAAAA==.Tachie:BAAANQAECgUIDgAAAA==.Talön:BAEANQAECgUJBQAAAA==.',
Te='Teranox:BAAANQABCgYIFwAAAA==.Tezzerae:BAAANQAECgEIAQAAAA==.',
Th='Theistica:BAAANQAECgMIBAAAAA==.Therin:BAAANQAECgYIEQAAAA==.Thodi:BAAANQABCgYICgAAAA==.',
To='Tongshi:BAAANQABCggIDAAAAA==.Toofast:BAAANQAECgUICwAAAA==.Toofurrious:BAAANQADCgQJBgAAAA==.Toolotems:BAAANQAECgUIBwAAAA==.Topswimmer:BAAANQABCgIIAgAAAA==.',
Tr='Trifus:BAAANQAECgEIAQAAAA==.',
Tu='Tulao:BAAANQADCgYICwAAAA==.',
Ty='Tylae:BAAANQADCgQIBwAAAA==.',
Ut='Utheli:BAABNQAECoEfAAIEAAgK4BolSQBsAgAEAAgK4BolSQBsAgAAAA==.',
Va='Vaildora:BAAANQADCgcIFwABNQAECgUIDgAIAAAAAA==.Valdra:BAAANQAECgQICAAAAA==.Vane:BAAANQADCgEIAQAAAA==.Vanillacain:BAAANQADCgMIAwAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgQJCgAAAA==.',
Vl='Vlonet:BAABNQAECoEdAAIUAAcKMhK4JQDbAQAUAAcKMhK4JQDbAQAAAA==.',
Vn='Vnasty:BAAANQAECgIIAgABNQAECgkJJQAKAGIiAA==.',
Vo='Vokola:BAAANQADCgYIBgABNQAECgUIDgAIAAAAAA==.',
Wi='Wilken:BAAANQAECgEIAQAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwAIAAAAAA==.Wiva:BAAANQAECgQIBgAAAA==.',
Wo='Wolfsokol:BAAANQAECgUICwAAAA==.',
Wr='Wreckoner:BAAANQAECgUIDwAAAA==.',
Xa='Xavencia:BAAANQADCgYICgAAAA==.',
Xi='Xinthos:BAAANQAECgIIAgAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Yu='Yukiakari:BAAANQADCgQIBQAAAA==.',
Za='Zakainu:BAAANQAECgUIDAAAAA==.Zallister:BAAANQADCggIIAAAAA==.Zansarutobi:BAAANQABCgYIBgAAAA==.Zarathoszan:BAAANQAECgYIEAAAAA==.',
Ze='Zedator:BAAANQAECgUIEQAAAA==.Zeedle:BAAANQABCgQIBAAAAA==.Zelgaddis:BAAANQAECgYICgAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zh='Zhansaya:BAAANQADCgcIEwAAAA==.',
Zr='Zriana:BAAANQADCggIIQAAAA==.',
Zs='Zsarilya:BAAANQAECgMIBAAAAA==.',
Zu='Zurgen:BAAANQAECgUIDgAAAA==.',
['Àn']='Àndrol:BAAANQAECgQIBgABNQAECgYIBgAIAAAAAA==.',
['Êc']='Êclipse:BAEANQAECgcIEwAAAA==.',
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
