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

local lookup = {'Paladin-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','Paladin-Retribution','DemonHunter-Vengeance','Unknown-Unknown','Warrior-Arms','DeathKnight-Blood','Evoker-Devastation','Priest-Holy','Hunter-BeastMastery','Mage-Arcane','Shaman-Elemental','Warlock-Demonology','Mage-Frost','Shaman-Restoration','Monk-Windwalker','Druid-Balance','Druid-Restoration','Warlock-Destruction','Monk-Mistweaver','Evoker-Preservation','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Devourer','Paladin-Protection',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aarchon:BAABNQAECoEaAAIBAAcKLB20PQBQAgABAAcKLB20PQBQAgAAAA==.',
Ad='Aduin:BAAANQAECgEIAQAAAA==.',
Ae='Aedarelyn:BAAANQADCggIGAAAAA==.Aellita:BAAANQADCggIDAAAAA==.Aenoryae:BAAANQADCgYIBgAAAA==.Aeschylus:BAAANQADCgIIAwAAAA==.',
Af='Afkinlife:BAAANQADCgYJBwAAAA==.',
Ai='Aias:BAAANQADCgcIBwAAAA==.',
Ak='Akky:BAAANQAECgYIEAAAAA==.Aksafiya:BAABNQAECoEpAAMCAAcK8A/UKwCfAQACAAcK8A/UKwCfAQADAAEK5QFmLAAiAAAAAA==.',
Al='Alal:BAAANQADCgUIDAAAAA==.Alaras:BAACNQAFFIEHAAICAAQK7QhICgAZAQACAAQK7QhICgAZAQA1AAQKgRsAAgIACQpTFPAbAEMCAAIACQpTFPAbAEMCAAAA.Aleesha:BAAANQADCgYJBwAAAA==.Alissia:BAAANQADCgYIBgAAAA==.Allaras:BAAANQADCgYIDAAAAA==.Allistaris:BAAANQAECgYIDAAAAA==.Allrianne:BAAANQAECgEIAQAAAA==.Allyriae:BAAANQAECgYIDAAAAA==.Alphá:BAABNQAECoEbAAIEAAgKUAwfPACdAQAEAAgKUAwfPACdAQAAAA==.Althoraty:BAAANQAECgYIEwAAAA==.Alyx:BAAANQADCggIEAAAAA==.',
Am='Amberlilly:BAAANQAECgQICQAAAA==.',
An='Andoros:BAAANQAECgYIEQAAAA==.Anzurath:BAABNQAECoEaAAIFAAcKrhA3mwC1AQAFAAcKrhA3mwC1AQAAAA==.',
Ap='Apheron:BAABNQAECoEbAAIGAAgKgCGgAwD+AgAGAAgKgCGgAwD+AgAAAA==.Apollimy:BAAANQAECggIBgAAAA==.Applebow:BAAANQAECgQICAAAAA==.Apples:BAAANQADCggICwAAAA==.',
Ar='Arathwr:BAAANQADCgcIBwABNQADCggIGAAHAAAAAA==.Ardalel:BAAANQADCgMIAwAAAA==.Arknova:BAABNQAECoEdAAIFAAgK2xiEYgBGAgAFAAgK2xiEYgBGAgAAAA==.Arylin:BAAANQAECgIIAwAAAA==.',
As='Asheram:BAAANQADCgEIAQAAAA==.Ashkinassi:BAEANQADCgUIBgAAAA==.Asiain:BAAANQAECgUIBgABNQAFFAUIBgAIAFIMAA==.Asnabel:BAAANQAECgUIDAAAAA==.',
At='Atvar:BAAANQADCggICAAAAA==.',
Au='Aurelith:BAAANQAECgYIBgAAAA==.Autumndeath:BAAANQAECgMIBQAAAA==.',
Av='Avinger:BAAANQABCggIGQAAAA==.',
Ay='Ayden:BAABNQAECoEfAAIGAAgKlhL7DADBAQAGAAgKlhL7DADBAQAAAA==.',
Az='Azorain:BAAANQADCgQIBAAAAA==.Azrim:BAAANQADCgYIDgAAAA==.Azureis:BAAANQADCgcICAAAAA==.',
Ba='Balolz:BAAANQABCgYIEQAAAA==.',
Be='Belthar:BAABNQAECoEaAAIJAAgKOhE6RQDGAQAJAAgKOhE6RQDGAQAAAA==.Bendeye:BAAANQADCgYIDgAAAA==.',
Bl='Blee:BAAANQAECgIIAgAAAA==.Bluudclaaw:BAAANQADCgMIAwABNQAECgcIGgAKAC4ZAA==.',
Bo='Boing:BAAANQAECgYIEAAAAA==.Boomhauer:BAAANQAECgQICAAAAA==.',
Br='Braelia:BAAANQAECgUICwAAAA==.Braetwo:BAAANQABCggJDwABNQAECgUICwAHAAAAAA==.Braughm:BAAANQADCgUJBQAAAA==.Breye:BAAANQAECgUICAAAAA==.Brindria:BAAANQADCgQIBgAAAA==.Brood:BAAANQAECgUIEQAAAA==.Brundles:BAABNQAECoEaAAIFAAcKbgeP0ABAAQAFAAcKbgeP0ABAAQAAAA==.',
Bu='Bubblepopper:BAABNQAECoEVAAILAAYKBCHMRgAsAgALAAYKBCHMRgAsAgAAAA==.Bunky:BAAANQAECgUIBgAAAA==.',
Ca='Cailaranel:BAAANQAECgQIBQAAAA==.Calaul:BAAANQAECgcIEwAAAA==.Calenbraga:BAAANQAECgIIAgAAAA==.Calisim:BAAANQAECgIIAgAAAA==.Caloh:BAAANQAECgQIBwAAAA==.Cantholdagro:BAAANQAECgEIAQABNQAECgcIDQAHAAAAAA==.Cassamaria:BAAANQAECgYIDQAAAA==.Cataryn:BAABNQAECoEaAAIMAAcKLR0GTABiAgAMAAcKLR0GTABiAgAAAA==.Catt:BAAANQAECgUIEgAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECgcIGgAJAGcbAA==.',
Ce='Cellebur:BAAANQADCggIIgAAAA==.Ceta:BAAANQAECgYIDQAAAA==.',
Ch='Chalfus:BAABNQAECoEcAAINAAgKyRhJdgB7AgANAAgKyRhJdgB7AgAAAA==.Chaszmyr:BAAANQADCggIHQAAAA==.Chewwy:BAAANQAECggIDQAAAA==.',
Ci='Cinamen:BAAANQADCggILAAAAA==.Cizean:BAAANQAECgIIBAAAAA==.',
Cl='Clare:BAAANQABCgQIBAABNQAECgcIGgAMAC0dAA==.Closetofsmut:BAAANQADCgcIBwAAAA==.',
Cr='Craivan:BAAANQADCgUICQAAAA==.Crendoal:BAAANQADCgQIBgABNQAECgYIEgAHAAAAAA==.Crilly:BAAANQAECgMJAwAAAA==.Crowley:BAAANQADCgQIBAAAAA==.Crumpler:BAAANQAECgcIEQAAAA==.Crüsnik:BAAANQADCgMIAwAAAA==.',
Cy='Cyroka:BAAANQAECgIIBAAAAA==.Cytroncutoff:BAAANQADCgcIEAAAAA==.',
Da='Dalastish:BAAANQADCggIDAAAAA==.Damia:BAAANQAECgQICAAAAA==.Danobun:BAABNQAECoEgAAIOAAkKIx24JQDOAgAOAAkKIx24JQDOAgAAAA==.Darkfoxcr:BAAANQABCgIIBAAAAA==.Darsithis:BAAANQAECgMIBAAAAA==.',
De='Deadite:BAABNQAECoEaAAIJAAcKZxubMQArAgAJAAcKZxubMQArAgAAAA==.Deadstealth:BAAANQADCgYIBgAAAA==.Delphirose:BAAANQABCggIDwABNQADCggIGAAHAAAAAA==.Delvarrieth:BAAANQAECgIIBAAAAA==.Demzy:BAAANQADCgcIBwAAAA==.Denth:BAAANQAECgMIBQAAAA==.Dercuur:BAABNQAECoEcAAIOAAkKERL9QgA+AgAOAAkKERL9QgA+AgAAAA==.',
Do='Dondeestasto:BAAANQADCgMIAwAAAA==.Dotur:BAAANQADCgIJAgAAAA==.',
Dr='Dragonkiss:BAAANQADCgQJBwAAAA==.Drainmee:BAAANQAECgUIBQAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAAANQAECgYIEAAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAAANQADCggIFwAAAA==.',
['Dá']='Dárkbeard:BAAANQAECgIIAwAAAA==.',
Ek='Ekneirg:BAAANQAECgYIEAAAAA==.',
El='Elleneilah:BAAANQADCgQIBAAAAA==.Elynth:BAABNQAECoEaAAIPAAcKlxFTewDHAQAPAAcKlxFTewDHAQAAAA==.',
Em='Emmalily:BAAANQAECgIIAwAAAA==.',
En='Endlessyueh:BAAANQADCgQIDgAAAA==.',
Ex='Extragrippy:BAAANQAECgcIDQAAAA==.',
Ey='Eyris:BAAANQADCgQIBAAAAA==.',
Fa='Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAABNQAECoEbAAIQAAgK6wzHDQCkAQAQAAgK6wzHDQCkAQAAAA==.Fangren:BAAANQAECgEIAQAAAA==.Farrseer:BAAANQAECgUIDQAAAA==.Fasthandslez:BAAANQAECgIIAgAAAA==.',
Fe='Felscythe:BAAANQAECgIIBAAAAA==.',
Fi='Fierrastar:BAAANQAECgYIEAAAAA==.Finshao:BAAANQAECgIIBAAAAA==.Fionn:BAAANQADCgcIBwABNQADCggIGQAHAAAAAA==.',
Fl='Flemish:BAAANQAECgQICAAAAA==.Flextame:BAAANQADCgcIFAAAAA==.Flipalicious:BAABNQAECoEkAAMOAAgKnhXEZADCAQAOAAcKMxPEZADCAQARAAcKmg7ehQBOAQAAAA==.Flipanomicon:BAAANQADCgYIEAAAAA==.Flipkicks:BAAANQADCgYICgAAAA==.Flipmode:BAAANQADCgcIEAAAAA==.Flipnasty:BAAANQADCgYICwAAAA==.Flipocalypse:BAAANQADCgYICgAAAA==.',
Fo='Foxwynn:BAAANQABCgIIAgAAAA==.',
Fr='Freyalise:BAAANQAECgUIEgAAAA==.Freyjah:BAAANQADCgUIBQAAAA==.Frostycarbon:BAAANQADCgYICwAAAA==.',
Fu='Furriousyueh:BAAANQADCgUIFwAAAA==.',
Ga='Gaia:BAAANQAECgMIBgAAAA==.Gallimaufrey:BAAANQAECgQIBgAAAA==.Garodan:BAAANQADCgcIDQAAAA==.',
Ge='Gerbo:BAABNQAECoEgAAINAAgKJAr9zwDBAQANAAgKJAr9zwDBAQAAAA==.',
Gi='Gianavel:BAABNQAECoEWAAISAAcKFQnaMwBAAQASAAcKFQnaMwBAAQAAAA==.Ginodh:BAAANQAECgQIBgAAAA==.Ginomage:BAAANQAECgEIAQABNQAECgQIBgAHAAAAAA==.Ginopally:BAAANQADCgMIAwABNQAECgQIBgAHAAAAAA==.Ginoshaman:BAAANQADCgUIBgABNQAECgQIBgAHAAAAAA==.Ginovoker:BAAANQADCgYICQABNQAECgQIBgAHAAAAAA==.Gizelli:BAAANQAECgIIAgABNQAECgIIAgAHAAAAAA==.',
Gr='Grilled:BAAANQADCgYICwAAAA==.Gronke:BAAANQAECgMJAwABNQAECgYIEAAHAAAAAA==.Grubetsella:BAAANQAECgYIEgAAAA==.Grugachur:BAAANQAECgEIAwAAAA==.',
Gu='Gustice:BAAANQADCgIJAgAAAA==.',
Gy='Gyda:BAAANQADCgcIGQAAAA==.',
Ha='Hanoumatoi:BAAANQAECgQIBgAAAA==.Haralambos:BAAANQADCgcIEwAAAA==.Harlar:BAAANQADCgUIBgAAAA==.Hasun:BAAANQAECgQIBAAAAA==.',
He='Hehasnoname:BAAANQADCgYICQAAAA==.Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQADCgcICwAAAA==.',
Ho='Hordkilla:BAAANQAECgMJBQAAAA==.Hownowbrncw:BAAANQAECgUIDAAAAA==.',
Hy='Hyce:BAAANQAECgYIEAAAAA==.',
Ih='Ihavenoname:BAAANQADCgYJCwAAAA==.',
Il='Illusionous:BAAANQAECgIIAwAAAA==.',
In='Insoniacyun:BAAANQADCgYIFQAAAA==.',
Is='Iselian:BAAANQAECgYIEAAAAQ==.Istrix:BAAANQADCgUJBQAAAA==.',
Ja='Jadefeather:BAAANQAECgYIDQAAAA==.',
Jb='Jbelbueno:BAAANQADCggICgAAAA==.Jblockiv:BAAANQADCgQICAAAAA==.Jbprimero:BAAANQAECgUIBQAAAA==.Jbshami:BAABNQAECoEYAAIRAAgKfhm7OwBIAgARAAgKfhm7OwBIAgAAAA==.',
Je='Jeman:BAAANQABCggICAAAAA==.Jenaelle:BAAANQAECggIAQABNQAECggIBgAHAAAAAA==.Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAAANQAECgYIEAAAAA==.Jetfires:BAABNQAECoEmAAIMAAgKkRmdSgBmAgAMAAgKkRmdSgBmAgAAAA==.',
Ji='Jinger:BAAANQAECgUIBgAAAA==.Jinnwoo:BAAANQADCgMIAwAAAA==.',
Jo='Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQAECgEIAQAAAA==.',
Ka='Kaedren:BAAANQADCgYIEQAAAA==.Kaelorien:BAAANQAECgUIDgAAAA==.Kalazaad:BAAANQAECgUICwAAAA==.Kaldevayn:BAAANQADCggINQAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalrow:BAAANQAECgQICAAAAA==.Kalto:BAAANQAECgIIAwAAAA==.Kalyna:BAAANQADCggICAAAAA==.Kardanis:BAABNQAECoEaAAIRAAcK6R0jOgBOAgARAAcK6R0jOgBOAgAAAA==.Kashe:BAAANQADCggIGQAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAABNQAECoEZAAIQAAgK3RQ1CQASAgAQAAgK3RQ1CQASAgAAAA==.Katavia:BAABNQAECoEaAAIRAAcKjgorjAA9AQARAAcKjgorjAA9AQAAAA==.Kathii:BAAANQAECgIIAgAAAA==.Katrazath:BAAANQAECgUIBwAAAA==.Kaydencia:BAAANQABCgUIBwAAAA==.',
Ke='Kelmmers:BAAANQAECgUIBAAAAA==.Keyallandron:BAAANQAECgUIBwAAAA==.',
Kh='Khaleesie:BAAANQADCgMIAwAAAA==.Khiana:BAAANQADCgIIAgABNQAECgcIGgAMAC0dAA==.',
Ki='Kiddow:BAAANQADCggIIQAAAA==.Kierea:BAAANQADCgcIDgAAAA==.Kiiarah:BAAANQAECgIIAgAAAA==.Kilrah:BAAANQADCgEIAQAAAA==.Kinte:BAAANQADCgYIBgAAAA==.Kitamii:BAAANQAECgQIBAAAAA==.Kitaña:BAAANQABCggIEgAAAA==.Kivrin:BAAANQAECgQIBgAAAA==.Kiára:BAAANQADCgQIBQAAAA==.',
Ko='Kokujin:BAABNQAECoEZAAIOAAYK8RNCdwCMAQAOAAYK8RNCdwCMAQAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAAANQAECgcIEgAAAA==.',
Ku='Kurumi:BAAANQAECgEIAQAAAA==.',
Kw='Kwo:BAAANQAECgYIBgAAAA==.',
Ky='Kymma:BAAANQAECgQICAAAAA==.',
La='Laviz:BAAANQADCgYIBwAAAA==.Lazengann:BAAANQAECgYIEgAAAA==.',
Le='Leafbane:BAABNQAECoEnAAMEAAkKERVXIwBIAgAEAAkKmxRXIwBIAgAJAAEK4BaqsQBHAAAAAA==.Legevia:BAAANQAECgIIAwAAAA==.Leiris:BAAANQAECgYIDQAAAA==.Lejusticier:BAAANQADCggICAAAAA==.Leonaa:BAAANQADCgYIEwAAAA==.Leucetios:BAAANQAECgMIBQAAAA==.',
Li='Liarace:BAAANQAECgUICAAAAA==.Lightbeard:BAAANQAECgEIAQAAAA==.Lightforge:BAAANQAECgYICgAAAA==.Lionessi:BAAANQADCgcIBwAAAA==.Lithika:BAAANQADCgYIBgAAAA==.',
Lo='Lorredain:BAAANQADCgYIDQAAAA==.Lothwen:BAAANQADCggIGgAAAA==.Louisachan:BAAANQAECgIIAgAAAA==.',
Lu='Luxinine:BAABNQAECoEaAAICAAgK1BsaFACkAgACAAgK1BsaFACkAgAAAA==.',
Ma='Madhawi:BAAANQAECgEIBAAAAA==.Magamon:BAABNQAECoEaAAINAAcKvxGNyQDOAQANAAcKvxGNyQDOAQAAAA==.Magnix:BAAANQADCgQIBAABNQAECgIIAwAHAAAAAA==.Malfuriia:BAAANQAECgIIBAAAAA==.Mamboke:BAAANQAECgUIBQAAAA==.Margerdria:BAAANQADCgcIEAAAAA==.Mauugrim:BAAANQAECgQIBgAAAA==.Maxowen:BAAANQAECgIIBAAAAA==.Maxxramas:BAAANQADCgcICgAAAA==.',
Me='Mearadan:BAAANQAECgYICgAAAA==.Meatsweats:BAAANQAECgEIAQAAAA==.Megg:BAAANQADCgYIBgAAAA==.Mekh:BAAANQAECgIIBAAAAA==.Mel:BAAANQADCgcIDwAAAA==.Melanara:BAAANQAECgYIEAAAAA==.Melstrom:BAAANQADCggIHAAAAA==.Meticuluslyn:BAAANQADCgcIHAAAAA==.',
Mi='Milkmaiden:BAAANQADCgQJCAAAAA==.Milkthisbull:BAAANQADCgMIAwAAAA==.Mixler:BAAANQAECgUICgAAAA==.',
Mm='Mmeow:BAAANQADCgYIEAABNQAECgYIEAAHAAAAAA==.',
Mo='Moirine:BAAANQAECgIIBAAAAA==.',
Mu='Murdrmitts:BAAANQAECgMIBgAAAA==.Mustikka:BAAANQADCgQIBAABNQADCgYIDgAHAAAAAA==.',
My='Myuriyanka:BAABNQAECoEgAAIOAAgKhQ/oXADcAQAOAAgKhQ/oXADcAQAAAA==.',
['Mæ']='Mælstrôm:BAAANQABCgQIBgAAAA==.',
Na='Naahommii:BAAANQADCgUIBQAAAA==.Nachtpranke:BAAANQAECgEIAQABNQAECgUIEgAHAAAAAA==.Naeri:BAAANQAECgQICAAAAA==.Nagualli:BAAANQADCggIEAAAAA==.Naieve:BAAANQAECgYIDgAAAA==.Nastii:BAAANQADCgEIAQAAAA==.Nastychungus:BAABNQAECoErAAMOAAkKYiLUEgBGAwAOAAkKYiLUEgBGAwARAAUK6ANrwAC9AAAAAA==.Navira:BAAANQADCggIHgAAAA==.',
Ne='Negargra:BAAANQAECggICAAAAA==.Nekoda:BAAANQAECggIAwABNQAECggIBgAHAAAAAA==.Nephadin:BAAANQAECgEIAQAAAA==.',
Ni='Nighttiger:BAAANQADCggIFwAAAA==.Nikooli:BAAANQAECgUICQAAAA==.',
No='Noopsie:BAAANQAECgQIAwAAAA==.Nooters:BAABNQAECoEmAAIEAAkKJiPEBACFAwAEAAkKJiPEBACFAwABNQAFFAUIDgAKAIobAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAAANQAECgYIDQAAAA==.',
Ny='Nyteweaver:BAAANQAECgIIAwAAAA==.',
Od='Oderica:BAAANQAECgEIAQAAAA==.Odurn:BAAANQADCgYIBgAAAA==.',
Og='Ogafor:BAAANQABCgIIAgAAAA==.',
Or='Oranash:BAAANQADCgMIAwAAAA==.Orici:BAAANQAECgIIAgABNQAECgIIAwAHAAAAAA==.Ornir:BAAANQADCgMIAwAAAA==.',
Os='Oscarmikey:BAABNQAECoEgAAMTAAkKtRduMwAkAgATAAgKZRhuMwAkAgAUAAIKjA9/VwB3AAAAAA==.Oshu:BAAANQADCgYIBgAAAA==.',
Ot='Ottoshot:BAAANQAECgIIBAAAAA==.Otum:BAAANQAECgMIBAAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
Ox='Oxmantle:BAAANQABCgUIBgAAAA==.',
['Oö']='Oöps:BAAANQAECgQIBwAAAA==.',
Pa='Panamone:BAAANQABCgEIAQAAAA==.Pandamaster:BAAANQAECgcICwAAAA==.',
Pe='Pendragon:BAAANQADCgQIBQAAAA==.Pesch:BAAANQAECggICAAAAA==.',
Ph='Phylah:BAAANQAECgQIBAAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Porterhouze:BAAANQABCgIIAgABNQAECgcIHgAVAPoDAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.Prophetofham:BAAANQADCgYIBgAAAA==.',
Pu='Puchi:BAACNQAFFIEQAAIWAAUKnBhuAwCkAQAWAAUKnBhuAwCkAQA1AAQKgSsAAhYACQrwIyADAHEDABYACQrwIyADAHEDAAAA.Pug:BAAANQADCggIEwABNQAECgYIEAAHAAAAAA==.',
Qa='Qadhiræ:BAAANQADCgUIBQAAAA==.',
['Qæ']='Qædhira:BAAANQADCgEIAQAAAA==.',
Ra='Raez:BAAANQAECgYICgAAAA==.Ragnerock:BAAANQAECgIIAgAAAA==.Raynecira:BAAANQAECgUIBwAAAA==.',
Re='Reihino:BAAANQAECgEIAQAAAA==.Remixidora:BAAANQAECgQJCAABNQAECgkJIQANAJskAA==.Reyrocko:BAAANQAECgEIAQAAAA==.Rezdh:BAAANQAECgYIDQABNQAECggIGgAOAH4fAA==.Rezmage:BAAANQAECgYIBgABNQAECggIGgAOAH4fAA==.Reznal:BAAANQAECgMIAwABNQAECggIGgAOAH4fAA==.Rezvoker:BAAANQADCgUJCgABNQAECggIGgAOAH4fAA==.',
Rh='Rhage:BAAANQADCgcIDgAAAA==.Rhoaias:BAAANQADCggIIwAAAA==.Rhunyaye:BAAANQADCgUICgAAAA==.',
Ri='Rickness:BAAANQAECgIIBAAAAA==.Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQAECgEIAQAAAA==.Rottingturky:BAAANQAECgcIDgAAAA==.Roxane:BAAANQAECgYICwAAAA==.',
Ru='Rubyace:BAAANQAECgMIAgAAAA==.Runningelk:BAAANQAECgYICAAAAA==.Runscapemain:BAAANQAECgYIEwAAAA==.',
Ry='Ryeti:BAAANQADCggIIQAAAA==.Ryydia:BAAANQADCgIIAgAAAA==.',
Sa='Sahalia:BAAANQADCgUIDAABNQAECgEIAQAHAAAAAA==.Saintulrick:BAAANQAECgQIBQAAAA==.Sajuice:BAAANQAFFAIIAgAAAA==.Salow:BAAANQABCgYICgAAAA==.Sanitas:BAABNQAECoEVAAILAAcKjgzpdACEAQALAAcKjgzpdACEAQAAAA==.',
Se='Seeyen:BAACNQAFFIEFAAIMAAMK/RHSEQAFAQAMAAMK/RHSEQAFAQA1AAQKgSgAAgwACQrqIm0LAHEDAAwACQrqIm0LAHEDAAAA.Sej:BAAANQABCgIIAgAAAA==.Seraphon:BAAANQADCggIJAAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAAHAAAAAA==.',
Sh='Shaaydo:BAAANQADCgMIAwAAAA==.Shaayllee:BAAANQAECgQIBQAAAA==.Shaaytheyha:BAAANQAECgUIDwAAAA==.Shaggyp:BAAANQAECgEIAQAAAA==.Shamump:BAAANQADCgcIBwAAAA==.Sharyl:BAAANQABCgcICwAAAA==.Shehasnoname:BAAANQADCgYIGAAAAA==.Shehulk:BAAANQAECgUICwAAAA==.Shingo:BAAANQADCgcIBwABNQAECgkJJwAEADUhAA==.Ships:BAABNQAECoEXAAIXAAkKLRTDFABQAgAXAAkKLRTDFABQAgAAAA==.',
Si='Silf:BAAANQAECgEIAQAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skibbward:BAAANQADCgQIBAABNQAFFAMIBAAHAAAAAA==.Skrektwo:BAABNQAECoEVAAMRAAYKehVGegBuAQARAAYKehVGegBuAQAOAAUKSQVnwgDfAAAAAA==.',
Sm='Smackdogg:BAACNQAFFIEMAAITAAUKXhq2CgCUAQATAAUKXhq2CgCUAQA1AAQKgR0AAhMACQoAJdgPADcDABMACQoAJdgPADcDAAAA.',
So='Solarspark:BAAANQAECgYIEQAAAA==.Sondaladan:BAAANQADCgYIDQAAAA==.Sonomonom:BAAANQADCggIEAAAAA==.Soota:BAAANQABCgQIBwAAAA==.Sorvina:BAABNQAECoEeAAIPAAgKpgsRfwC8AQAPAAgKpgsRfwC8AQAAAA==.Soulflame:BAABNQAECoEbAAIQAAgKEgu9DgCSAQAQAAgKEgu9DgCSAQAAAA==.Soulkings:BAAANQADCggIGgAAAA==.',
Sp='Spriggs:BAAANQADCgMIBAAAAA==.',
St='Strangr:BAAANQADCggICwABNQAECgkJIwASAKYdAA==.Stregnor:BAAANQAECgUIBgAAAA==.Styggi:BAAANQADCggICAAAAA==.Stygy:BAAANQADCgcIBwABNQADCggICAAHAAAAAA==.',
Su='Sumyunguy:BAABNQAECoEUAAISAAYKsxhRKACqAQASAAYKsxhRKACqAQAAAA==.',
Sy='Sylunia:BAAANQAECgUIEAAAAA==.Sylváñás:BAAANQABCggIFAAAAA==.Syrintha:BAAANQADCgYJBgAAAA==.',
Ta='Tachi:BAAANQAECgUIBwABNQAECgcIFgAKAF8XAA==.Tachie:BAABNQAECoEWAAIKAAcKXxfgEwDxAQAKAAcKXxfgEwDxAQAAAA==.Talön:BAEANQAECgUJBQAAAA==.Tarvah:BAAANQADCgYIBgAAAA==.',
Te='Teranox:BAAANQABCgYIGwAAAA==.Tezzerae:BAAANQAECgIIAwAAAA==.',
Th='Theistica:BAAANQAECgQICAAAAA==.Therin:BAABNQAECoEcAAMYAAcKSAtAPABAAQAZAAcKtwpyCACdAQAYAAcKswZAPABAAQAAAA==.Thodi:BAAANQABCgYICgAAAA==.',
To='Tongshi:BAAANQABCggIDAAAAA==.Toofast:BAAANQAECgYIEQAAAA==.Toofurrious:BAAANQADCgQJBgAAAA==.Toolotems:BAAANQAECgUIBwAAAA==.Topswimmer:BAAANQABCgIIAgAAAA==.',
Tr='Trifus:BAAANQAECgEIAQAAAA==.',
Tu='Tulao:BAAANQAECgUIBgAAAA==.',
Ty='Tylae:BAAANQADCgQIBwAAAA==.',
Ut='Utheli:BAABNQAECoEiAAIFAAkK3hpdQwClAgAFAAkK3hpdQwClAgAAAA==.',
Va='Vaeyethir:BAAANQABCgcICAAAAA==.Vaildora:BAAANQAECgQIBAABNQAECgcIFgAKAF8XAA==.Valdra:BAAANQAECgYIDgAAAA==.Valord:BAAANQADCgcIBwAAAA==.Vane:BAAANQADCgEIAQAAAA==.Vanillacain:BAAANQADCgMIAwAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgcIEQAAAA==.',
Vl='Vlonet:BAABNQAECoEhAAIaAAcKChPpKQDTAQAaAAcKChPpKQDTAQAAAA==.',
Vn='Vnasty:BAAANQAECgIIAwABNQAECgkJKwAOAGIiAA==.',
Vo='Vokola:BAAANQADCggIDQABNQAECgcIFgAKAF8XAA==.',
Wi='Wilken:BAAANQAECgEIAgAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwAHAAAAAA==.Wiva:BAAANQAECgQIBgAAAA==.',
Wo='Wolfsokol:BAAANQAECgUIDQABNQAFFAcIBwAXANIcAA==.',
Wr='Wreckoner:BAABNQAECoEaAAIbAAcK0A5KJwB3AQAbAAcK0A5KJwB3AQAAAA==.',
Xa='Xavencia:BAAANQADCgYICgAAAA==.',
Xi='Xinthos:BAAANQAECgIIAgAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Yu='Yukiakari:BAAANQADCgQIBQAAAA==.',
Za='Zakainu:BAAANQAECgUIEAAAAA==.Zallister:BAAANQADCggIKAAAAA==.Zansarutobi:BAAANQABCgYIBgAAAA==.Zarathoszan:BAAANQAECgcIEQAAAA==.',
Ze='Zedator:BAABNQAECoEXAAIZAAcKhBuEBQA5AgAZAAcKhBuEBQA5AgAAAA==.Zeedle:BAAANQABCgQIBAAAAA==.Zelgaddis:BAAANQAECgYIEAAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zh='Zhansaya:BAAANQAECgEIAQAAAA==.',
Zr='Zriana:BAAANQAECgEIAQAAAA==.',
Zs='Zsarilya:BAAANQAECgQICAAAAA==.',
Zu='Zurgen:BAABNQAECoEYAAIPAAcKjRxdTwBGAgAPAAcKjRxdTwBGAgAAAA==.',
['Àn']='Àndrol:BAAANQAECgYIDAABNQAFFAQIBwAaAJUGAA==.',
['Êc']='Êclipse:BAEBNQAECoEbAAIUAAgKGxcPGgBBAgAUAAgKGxcPGgBBAgAAAA==.',
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
