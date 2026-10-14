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

local lookup = {'Paladin-Holy','Unknown-Unknown','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','Priest-Holy','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Warrior-Arms','DeathKnight-Blood','Evoker-Devastation','Rogue-Assassination','Mage-Arcane','Hunter-Survival','Hunter-BeastMastery','Monk-Windwalker','Shaman-Elemental','DeathKnight-Unholy','Paladin-Protection','Warlock-Demonology','Mage-Frost','Shaman-Restoration','Monk-Mistweaver','DemonHunter-Devourer','Druid-Balance','Warlock-Destruction','Hunter-Marksmanship','Evoker-Preservation','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aarchon:BAABNQAECn8iAAIBAAgKaxzeNACOAgABAAgKaxzeNACOAgAAAA==.',
Ad='Aduin:BAAANQAECgEIAQAAAA==.',
Ae='Aedarelyn:BAAANQAECgIIAgAAAA==.Aenoryae:BAAANQADCgYIBgABNQADCgYIBgACAAAAAA==.Aeschylus:BAAANQADCgIIAwAAAA==.',
Af='Afkinlife:BAAANQADCgYJBwAAAA==.',
Ai='Aias:BAAANQADCgcIBwAAAA==.',
Ak='Akky:BAAANQAECgcIEQAAAA==.Aksafiya:BAABNQAECn84AAMDAAgKyxKmJAAIAgADAAgKyxKmJAAIAgAEAAEK5QH1MAAgAAAAAA==.',
Al='Alal:BAAANQADCgYIEQAAAA==.Alaras:BAACNQAFFH8JAAIDAAQKGgqUDAASAQADAAQKGgqUDAASAQA1AAQKfyAAAgMACQpJFuYUALgCAAMACQpJFuYUALgCAAAA.Aleesha:BAAANQADCgYJBwAAAA==.Alissia:BAAANQADCgYIBgAAAA==.Allaras:BAAANQADCgYIDAAAAA==.Allistaris:BAAANQAECgcIEwAAAA==.Allrianne:BAAANQAECgEIAQAAAA==.Alluriela:BAAANQADCgIIAgAAAA==.Allyriae:BAAANQAECgYIDQAAAA==.Alphá:BAABNQAECn8dAAIFAAgK3AsNSQCRAQAFAAgK3AsNSQCRAQAAAA==.Althoraty:BAABNQAECn8eAAIGAAgKRRL+ZADsAQAGAAgKRRL+ZADsAQAAAA==.Alyx:BAAANQADCggIEAAAAA==.',
Am='Amberlilly:BAAANQAECgQIDQAAAA==.',
An='Andoros:BAABNQAECn8eAAIHAAcKWyDUFwB+AgAHAAcKWyDUFwB+AgAAAA==.Antilles:BAAANQADCgEIAQAAAA==.Anzurath:BAABNQAECn8aAAIIAAcKug0duQClAQAIAAcKug0duQClAQAAAA==.',
Ap='Apheron:BAABNQAECn8jAAIJAAgKcyKSBAD4AgAJAAgKcyKSBAD4AgAAAA==.Apollimy:BAAANQAECggIBgAAAA==.Applebow:BAAANQAECgUIDQAAAA==.Apples:BAAANQADCggICwAAAA==.',
Ar='Arathwr:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.Ardalel:BAAANQADCgMIAwAAAA==.Arknova:BAABNQAECn8dAAIIAAgK4hemegAyAgAIAAgK4hemegAyAgAAAA==.Arylin:BAAANQAECgIIAwAAAA==.',
As='Asheram:BAAANQADCgEIAQAAAA==.Ashkinassi:BAEANQADCgUIBgAAAA==.Asiain:BAAANQAECgUIBgABNQAFFAUIBwAKADsPAA==.Asnabel:BAAANQAECgUIDAAAAA==.',
At='Atvar:BAAANQADCggICAAAAA==.',
Au='Aurelith:BAAANQAECggICgAAAA==.Autumndeath:BAAANQAECgMIBQAAAA==.',
Av='Avinger:BAAANQABCggIGQAAAA==.',
Ay='Ayden:BAABNQAECn8hAAIJAAgKoRNwDgDPAQAJAAgKoRNwDgDPAQAAAA==.',
Az='Azorain:BAAANQADCgQIBAAAAA==.Azrim:BAAANQADCgYIDgABNQAECgIIAgACAAAAAA==.Azureis:BAAANQADCgcICAAAAA==.',
Ba='Balolz:BAAANQABCgYIEQAAAA==.',
Be='Belthar:BAABNQAECn8cAAILAAgKGBShTgC4AQALAAgKGBShTgC4AQAAAA==.Bendeye:BAAANQADCgYIDgAAAA==.',
Bl='Blee:BAAANQAECgIIBAAAAA==.Bluudclaaw:BAAANQADCgMIAwABNQAECgcIHwAMAEUZAA==.',
Bo='Boing:BAABNQAECn8aAAINAAgKVBk8JQBcAgANAAgKVBk8JQBcAgAAAA==.Boomhauer:BAAANQAECgUIDQAAAA==.',
Br='Braelia:BAAANQAECgYIEQAAAA==.Braetwo:BAAANQABCggJDwABNQAECgYIEQACAAAAAA==.Braughm:BAAANQADCgUJBQAAAA==.Braxius:BAAANQADCgMIAwABNQAECggIJAAOADsbAA==.Breye:BAAANQAECgYIDgAAAA==.Brindria:BAAANQADCgQIBgAAAA==.Brood:BAAANQAECgUIEwAAAA==.Brundles:BAABNQAECn8iAAIIAAgKAgdOzAB8AQAIAAgKAgdOzAB8AQAAAA==.',
Bu='Bubblepopper:BAABNQAECn8VAAIGAAYKBCH6VAAhAgAGAAYKBCH6VAAhAgAAAA==.Bunky:BAAANQAECgUICQAAAA==.',
Ca='Cailaranel:BAAANQAECgYICwAAAA==.Calaul:BAABNQAECn8dAAIIAAgKUQ1AoQDaAQAIAAgKUQ1AoQDaAQAAAA==.Calenbraga:BAAANQAECgQIBgAAAA==.Calisim:BAAANQAECgIIAwAAAA==.Caloh:BAAANQAECgQICQAAAA==.Cantholdagro:BAAANQAECgEIAQABNQAECgcIDwACAAAAAA==.Cassamaria:BAABNQAECn8VAAIPAAgKThG9BgAgAgAPAAgKThG9BgAgAgAAAA==.Cataryn:BAABNQAECn8iAAIQAAgKxh5tMgDTAgAQAAgKxh5tMgDTAgAAAA==.Catt:BAABNQAECn8cAAIBAAYKtxV2hQCHAQABAAYKtxV2hQCHAQAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECggIIgALAH4dAA==.',
Ce='Cellebur:BAAANQAECgIIAgAAAA==.Ceta:BAAANQAECgYIEwAAAA==.',
Ch='Chalfus:BAABNQAECn8kAAIOAAgKOxtcegCJAgAOAAgKOxtcegCJAgAAAA==.Chaszmyr:BAAANQADCggIHQAAAA==.Chewwy:BAAANQAECggIEgAAAA==.',
Ci='Cinamen:BAAANQADCggILAAAAA==.Cizean:BAAANQAECgQICAAAAA==.',
Cl='Clare:BAAANQABCgQIBAABNQAECggIIgAQAMYeAA==.Closetofsmut:BAAANQADCgcIBwAAAA==.',
Cr='Craivan:BAAANQADCgUICQAAAA==.Crendoal:BAAANQADCgQIBgABNQAECgcIHQARAPUYAA==.Crilly:BAAANQAECgMJAwAAAA==.Crowley:BAAANQADCgQIBAAAAA==.Crumpler:BAABNQAECn8ZAAIIAAgKNQ35tACuAQAIAAgKNQ35tACuAQAAAA==.Crüsnik:BAAANQADCgMIAwAAAA==.',
Cy='Cyroka:BAAANQAECgQICAAAAA==.Cytroncutoff:BAAANQAECgEIAQAAAA==.',
Da='Dalastish:BAAANQADCggIDAAAAA==.Damia:BAAANQAECgUIDQAAAA==.Danobun:BAABNQAECn8lAAISAAkK1x6UHwAMAwASAAkK1x6UHwAMAwAAAA==.Darkfoxcr:BAAANQABCgIIBAAAAA==.Darsithis:BAAANQAECgUICQAAAA==.',
De='Deadite:BAABNQAECn8iAAILAAgKfh3QHQDAAgALAAgKfh3QHQDAAgAAAA==.Deadstealth:BAAANQADCgYIBgAAAA==.Delphirose:BAAANQABCggIDwABNQAECgIIAgACAAAAAA==.Delvarrieth:BAAANQAECgQICAAAAA==.Demzy:BAAANQAECgIIAgAAAA==.Denth:BAAANQAECgMIBQAAAA==.Dercuur:BAABNQAECn8lAAISAAkKARaOQQBsAgASAAkKARaOQQBsAgAAAA==.',
Di='Displacer:BAAANQADCggICAAAAA==.',
Do='Dondeestasto:BAAANQADCgMIAwAAAA==.Dotur:BAAANQADCgIIAgAAAA==.',
Dr='Dragonkiss:BAAANQADCgQIBwAAAA==.Drainmee:BAAANQAECgUIBQAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAABNQAECn8aAAITAAcKBgyzbQBZAQATAAcKBgyzbQBZAQAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAAANQAECgQIBAAAAA==.',
['Dá']='Dárkbeard:BAAANQAECgIIBAAAAA==.',
Ek='Ekneirg:BAABNQAECn8aAAMIAAcKYxtCigANAgAIAAcKERpCigANAgAUAAYKHBnpKgCCAQAAAA==.',
El='Elleneilah:BAAANQADCgUICQAAAA==.Elynth:BAABNQAECn8iAAIVAAgKEROKcQAIAgAVAAgKEROKcQAIAgAAAA==.',
Em='Emmalily:BAAANQAECgIIAwAAAA==.',
En='Endlessyueh:BAAANQADCgQIDgAAAA==.',
Ex='Extragrippy:BAAANQAECgcIDwAAAA==.',
Ey='Eyris:BAAANQADCgYICAAAAA==.',
Fa='Faiesong:BAAANQABCgQIBAAAAA==.Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAABNQAECn8cAAIWAAgKpw9TDwCxAQAWAAgKpw9TDwCxAQAAAA==.Fangren:BAAANQAECgEIAQAAAA==.Farrseer:BAAANQAECgUIDQAAAA==.Fasthandslez:BAAANQAECgIIAgAAAA==.',
Fe='Felscythe:BAAANQAECgQICAAAAA==.',
Fi='Fierrastar:BAABNQAECn8cAAIPAAgKFyAWAwDsAgAPAAgKFyAWAwDsAgAAAA==.Finnius:BAAANQADCgIIAgAAAA==.Finshao:BAAANQAECgQIBgAAAA==.Fionn:BAAANQADCgcIBwABNQAECgIIAgACAAAAAA==.',
Fl='Flemish:BAAANQAECgUIDQAAAA==.Flextame:BAAANQADCgcIGgAAAA==.Flipalicious:BAABNQAECn8rAAMSAAgKnxTYeACzAQASAAcKCRHYeACzAQAXAAcKOA9dlQBOAQAAAA==.Flipanomicon:BAAANQADCgYIEAAAAA==.Flipkicks:BAAANQADCgYICgAAAA==.Flipmode:BAAANQADCgcIEAAAAA==.Flipnasty:BAAANQADCgYICwAAAA==.Flipocalypse:BAAANQADCgYICgAAAA==.',
Fo='Foxwynn:BAAANQABCgIIAgAAAA==.',
Fr='Freyalise:BAABNQAECn8dAAMDAAcKhxeuLwCiAQADAAYKqROuLwCiAQAGAAUKmwKLzQC0AAAAAA==.Freyjah:BAAANQADCgUIBQAAAA==.Frostycarbon:BAAANQADCgYICwAAAA==.',
Fu='Furriousyueh:BAAANQADCgUIFwAAAA==.',
Ga='Gaia:BAAANQAECgQICgAAAA==.Gallimaufrey:BAAANQAECgQIBgAAAA==.Garodan:BAAANQADCgcIDQAAAA==.',
Ge='Gerbo:BAABNQAECn8nAAIOAAgKlgvD6AC1AQAOAAgKlgvD6AC1AQAAAA==.',
Gi='Gianavel:BAABNQAECn8dAAIRAAgKRQvpMgB6AQARAAgKRQvpMgB6AQAAAA==.Ginodh:BAAANQAECgQIBgAAAA==.Ginomage:BAAANQAECgQIBQABNQAECgQIBgACAAAAAA==.Ginopally:BAAANQADCgMIAwABNQAECgQIBgACAAAAAA==.Ginoshaman:BAAANQADCgUIBgABNQAECgQIBgACAAAAAA==.Ginovoker:BAAANQADCgYICQABNQAECgQIBgACAAAAAA==.Gizelli:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.',
Gr='Grilled:BAAANQADCgYICwAAAA==.Gronke:BAAANQAECgMJAwABNQAECgcIGgAIAGMbAA==.Grubetsella:BAABNQAECn8dAAMRAAcK9Rg3MgCAAQARAAYKURY3MgCAAQAYAAUKfhCGLAADAQAAAA==.Grugachur:BAAANQAECgQIBwAAAA==.',
Gu='Gustice:BAAANQADCgIJAgAAAA==.',
Gy='Gyda:BAAANQAECgEIAQAAAA==.',
Ha='Hangi:BAAANQADCgEIAQABNQAECggICgACAAAAAA==.Hanoumatoi:BAAANQAECgUICQAAAA==.Haralambos:BAAANQAECgIIAgAAAA==.Harlar:BAAANQADCgUIBgAAAA==.Hasun:BAAANQAECggIDgABNQAECgkJJQASANceAA==.',
He='Hehasnoname:BAAANQADCgYICQAAAA==.Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQADCgcICwAAAA==.',
Ho='Hordkilla:BAAANQAECgQICAAAAA==.Hownowbrncw:BAAANQAECgUIDAAAAA==.',
Hy='Hyce:BAABNQAECn8bAAMZAAcK1hdMKAD+AQAZAAcKGhZMKAD+AQAJAAMK/hhDHQDmAAAAAA==.Hymno:BAAANQADCgUIBQAAAA==.',
Ih='Ihavenoname:BAAANQADCgYJCwAAAA==.',
Il='Illusionous:BAAANQAECgIIAwAAAA==.',
In='Insoniacyun:BAAANQADCgYIFQAAAA==.',
Is='Iselian:BAAANQAECgcIFwAAAQ==.Istrix:BAAANQADCgUJBQAAAA==.',
Ja='Jadefeather:BAAANQAECgYIDQAAAA==.',
Jb='Jbelbueno:BAAANQAECgEIAQAAAA==.Jblockiv:BAAANQAECgMIAwAAAA==.Jbprimero:BAAANQAECgUIBQAAAA==.Jbshami:BAABNQAECn8fAAIXAAgKnxqeRABMAgAXAAgKnxqeRABMAgAAAA==.',
Je='Jeman:BAAANQABCggICAAAAA==.Jenaelle:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAABNQAECn8bAAIOAAcK5gGQaAHjAAAOAAcK5gGQaAHjAAAAAA==.Jetfires:BAABNQAECn8uAAIQAAkKwhzCNgDEAgAQAAkKwhzCNgDEAgAAAA==.',
Ji='Jinger:BAAANQAECgUICAAAAA==.Jinnwoo:BAAANQADCgMIAwAAAA==.',
Jo='Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQAECgEIAgAAAA==.',
Ju='Juggernacht:BAAANQAECgEIAQABNQAECgcIHQAGADwbAA==.',
Ka='Kaedren:BAAANQADCgYIEQAAAA==.Kaelorien:BAABNQAECn8YAAIYAAcK0wjwKAAnAQAYAAcK0wjwKAAnAQAAAA==.Kalazaad:BAAANQAECgUIEAAAAA==.Kaldevayn:BAAANQAECgEIAgAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalrow:BAAANQAECgQIDgAAAA==.Kalto:BAAANQAECgIIBAAAAA==.Kalyna:BAAANQAECgQIBAAAAA==.Kardanika:BAAANQADCgcIBgAAAA==.Kardanis:BAABNQAECn8iAAIXAAgKMR0TMwCRAgAXAAgKMR0TMwCRAgAAAA==.Kashe:BAAANQAECgIIAgAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAABNQAECn8gAAIWAAgKYxUJCgAoAgAWAAgKYxUJCgAoAgAAAA==.Katavia:BAABNQAECn8iAAIXAAgKYwqjiQBuAQAXAAgKYwqjiQBuAQAAAA==.Kathii:BAAANQAECgQIBQAAAA==.Katrazath:BAAANQAECgUIDAAAAA==.Kaydencia:BAAANQABCgUIBwAAAA==.',
Ke='Kelmmers:BAAANQAECgUIBgAAAA==.Keyallandron:BAAANQAECgUIDAAAAA==.',
Kh='Khaleesie:BAAANQAECgEIAQAAAA==.Khiana:BAAANQADCgIIAgABNQAECggIIgAQAMYeAA==.Khrin:BAAANQADCgQIBAAAAA==.',
Ki='Kiddow:BAAANQAECgEIAQAAAA==.Kierea:BAAANQADCgcIDgAAAA==.Kiiarah:BAAANQAECgQIBgAAAA==.Killrah:BAAANQADCgIIAgAAAA==.Kilrah:BAAANQADCgEIAQAAAA==.Kilriella:BAAANQADCgYIBgAAAA==.Kinte:BAAANQADCgYIBgAAAA==.Kitamii:BAAANQAECgQIBAAAAA==.Kitaña:BAAANQABCggIEgAAAA==.Kivrin:BAAANQAECgQICgAAAA==.Kiára:BAAANQADCggIDQAAAA==.',
Ko='Kokujin:BAABNQAECn8fAAISAAYK6hLLewCsAQASAAYK6hLLewCsAQAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAABNQAECn8cAAIQAAgK2B61MQDVAgAQAAgK2B61MQDVAgAAAA==.',
Ku='Kurumi:BAAANQAECgEIAQAAAA==.',
Kw='Kwo:BAAANQAECgYICgAAAA==.',
Ky='Kymma:BAAANQAECgUIDQAAAA==.',
La='Laviz:BAAANQADCgYIBwABNQAECgkJJQASANceAA==.Lazengann:BAABNQAECn8aAAIZAAgKER8EFQC7AgAZAAgKER8EFQC7AgAAAA==.',
Le='Leafbane:BAABNQAECn8wAAMFAAkKuhlfIwByAgAFAAkKuhlfIwByAgALAAEK4BYTwABFAAAAAA==.Legevia:BAAANQAECgIIBQAAAA==.Leiris:BAAANQAECgYIEwAAAA==.Lejusticier:BAAANQADCggICAAAAA==.Leonaa:BAAANQADCgYIEwAAAA==.Leucetios:BAAANQAECgUICgAAAA==.',
Li='Liarace:BAAANQAECgUICAAAAA==.Lightbeard:BAAANQAECgIIAwAAAA==.Lightforge:BAAANQAECgYIEAAAAA==.Lionessi:BAAANQADCgcIBwAAAA==.Lithika:BAAANQADCgYIBgAAAA==.',
Lo='Lorredain:BAAANQADCgYIDQAAAA==.Lothaire:BAAANQAECgMIAwAAAA==.Lothwen:BAAANQAECgEIAQAAAA==.Louisachan:BAAANQAECgIIAgAAAA==.',
Lu='Lucamar:BAAANQADCgQIBAAAAA==.Luxinine:BAABNQAECn8gAAIDAAgKex0tFADBAgADAAgKex0tFADBAgAAAA==.',
Ma='Madhawi:BAAANQAECgEIBAAAAA==.Magamon:BAABNQAECn8iAAIOAAgKyBQnvQAIAgAOAAgKyBQnvQAIAgAAAA==.Magnix:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.Malfuriia:BAAANQAECgQICAAAAA==.Mamboke:BAAANQAECgUIDAAAAA==.Margerdria:BAAANQADCgcIEAAAAA==.Mauugrim:BAAANQAECgQICQAAAA==.Maxowen:BAAANQAECgQICAAAAA==.Maxxramas:BAAANQADCgcICgAAAA==.',
Me='Mearadan:BAAANQAECgcIEQAAAA==.Meatsweats:BAAANQAECgEIAQAAAA==.Megg:BAAANQADCgYIBgAAAA==.Mekh:BAAANQAECgQICAAAAA==.Mel:BAAANQADCgcIFQAAAA==.Melanara:BAABNQAECn8cAAIWAAgK1g41DgDGAQAWAAgK1g41DgDGAQAAAA==.Melstrom:BAAANQAECgEIAQAAAA==.Meticuluslyn:BAAANQADCgcIHAAAAA==.',
Mi='Milkmaiden:BAAANQADCgQJCAAAAA==.Milkthisbull:BAAANQADCgMIAwAAAA==.Mixler:BAAANQAECgUIDwAAAA==.',
Mm='Mmeow:BAAANQADCgYIEAABNQAECggIFwAQAOwdAA==.',
Mo='Moirine:BAAANQAECgQICAAAAA==.',
Mu='Murdrmitts:BAAANQAECgQICgAAAA==.Mustikka:BAAANQAECgIIAgAAAA==.',
My='Myuriyanka:BAABNQAECn8pAAISAAgKMhBnaQDhAQASAAgKMhBnaQDhAQAAAA==.',
['Mæ']='Mælstrôm:BAAANQABCgQICAAAAA==.',
Na='Naahommii:BAAANQADCgUIBQAAAA==.Nachtpranke:BAAANQAECgIIAgABNQAECgcIHQAGADwbAA==.Nachtteufel:BAAANQAECgEIAQABNQAECgcIHQAGADwbAA==.Naeri:BAAANQAECgUIDQAAAA==.Nagualli:BAAANQADCggIEAAAAA==.Naieve:BAABNQAECn8aAAIaAAgKHxC4PwD5AQAaAAgKHxC4PwD5AQAAAA==.Nastii:BAAANQADCgEIAQAAAA==.Nastychungus:BAABNQAECn8sAAMSAAkKLCI2GAA1AwASAAkKLCI2GAA1AwAXAAUK6AP90ADAAAAAAA==.Navira:BAAANQADCggIHgAAAA==.',
Ne='Negargra:BAAANQAECggIDgAAAA==.Nekoda:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Nephadin:BAAANQAECgEIAQAAAA==.Neyvin:BAAANQADCgcIBgAAAA==.',
Ni='Nighttiger:BAAANQAECgEIAQAAAA==.Nikooli:BAAANQAECgUIDAAAAA==.',
No='Noopsie:BAAANQAECgQIBgAAAA==.Nooters:BAABNQAECn8qAAIFAAkKSiTKBgB0AwAFAAkKSiTKBgB0AwABNQAFFAUIEwAMABwiAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAAANQAECgYIEwAAAA==.',
Nu='Nunavutt:BAAANQADCgUIBQAAAA==.',
Ny='Nyteweaver:BAAANQAECgQIBwAAAA==.',
Od='Oderica:BAAANQAECggIAQAAAA==.Odurn:BAAANQADCgYIBgAAAA==.',
Og='Ogafor:BAAANQABCgIIAgAAAA==.',
Oh='Ohminous:BAAANQADCggICAAAAA==.',
Or='Oranash:BAAANQADCgMIAwAAAA==.Orici:BAAANQAECgIIAgABNQAECgIIAwACAAAAAA==.Ornir:BAAANQADCgMIAwAAAA==.Orongosh:BAAANQADCgYIBgAAAA==.',
Os='Oscarmikey:BAABNQAECn8mAAMaAAkKfhfXNQA4AgAaAAgKYBjXNQA4AgAHAAQKsxCORgD3AAAAAA==.Oshu:BAAANQADCgYIBgAAAA==.',
Ot='Ottoshot:BAAANQAECgQICAAAAA==.Otum:BAAANQAECgMIBQAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
Ox='Oxmantle:BAAANQAECgIIAgAAAA==.',
['Oö']='Oöps:BAAANQAECgUIDAAAAA==.',
Pa='Panamone:BAAANQAECgQIBAAAAA==.Pandamaster:BAAANQAECgcIDgAAAA==.',
Pe='Pendragon:BAAANQADCgQIBQAAAA==.Pesch:BAAANQAECggICAAAAA==.',
Ph='Phylah:BAAANQAECgQICAAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Porterhouze:BAAANQABCgIIAgABNQAECgcIHgAbANcDAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.Prophetofham:BAAANQADCgYIBgAAAA==.',
Pu='Puchi:BAACNQAFFH8VAAIYAAUK7xrcAwCqAQAYAAUK7xrcAwCqAQA1AAQKfy4AAhgACQrwI3kEAF4DABgACQrwI3kEAF4DAAAA.Pug:BAAANQADCggIEwABNQAECggIGgANAFQZAA==.',
Qa='Qadhiræ:BAAANQAECgEIAQABNQADCgYIBgACAAAAAA==.',
['Qæ']='Qædhira:BAAANQADCgYIBgAAAA==.',
Ra='Raez:BAAANQAECgYIDAAAAA==.Ragnerock:BAAANQAECgMIBAAAAA==.Raynecira:BAAANQAECgUIDAAAAA==.',
Re='Reihino:BAAANQAECgEIAQAAAA==.Remixidora:BAAANQAECgQJCAABNQAECgkJIwAOALgkAA==.Reyrocko:BAAANQAECgEIAQAAAA==.Rezdh:BAAANQAECgYIDQABNQAFFAEIAQACAAAAAA==.Rezmage:BAAANQAFFAEIAQAAAA==.Reznal:BAAANQAECgMIAwABNQAFFAEIAQACAAAAAA==.Rezvoker:BAAANQADCgUJCgABNQAFFAEIAQACAAAAAA==.',
Rh='Rhage:BAAANQADCgcIFAAAAA==.Rhoaias:BAAANQADCggIIwAAAA==.Rhunyaye:BAAANQADCgUICgAAAA==.',
Ri='Rickness:BAAANQAECgIIBAAAAA==.Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQAECgEIAQAAAA==.Rottingturky:BAAANQAECggIEgAAAA==.Roxane:BAAANQAECgcIEgAAAA==.',
Ru='Rubyace:BAAANQAECgMIAgAAAA==.Runningelk:BAAANQAECgYIDgAAAA==.Runscapemain:BAABNQAECn8eAAIIAAgKkwmGtACvAQAIAAgKkwmGtACvAQAAAA==.',
Ry='Ryeti:BAAANQADCggIJwAAAA==.Ryuzu:BAAANQADCgYIBgAAAA==.Ryydia:BAAANQADCgMIBQAAAA==.',
Sa='Sahalia:BAAANQADCgUIDAABNQAECgEIAgACAAAAAA==.Saintulrick:BAAANQAECgQIBQAAAA==.Sajuice:BAABNQAECn8XAAMQAAkKthfTSQCNAgAQAAkKthfTSQCNAgAcAAQKKRRLUADlAAAAAA==.Salow:BAAANQABCgYICgAAAA==.Sanitas:BAABNQAECn8kAAIGAAkKow9CWQASAgAGAAkKow9CWQASAgAAAA==.',
Se='Seeyen:BAACNQAFFH8JAAIQAAQKDhIcEwAsAQAQAAQKDhIcEwAsAQA1AAQKfywAAhAACQp0I6oOAGsDABAACQp0I6oOAGsDAAAA.Sej:BAAANQABCgIIAgAAAA==.Seraphon:BAAANQADCggIJAAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAACAAAAAA==.',
Sh='Shaaydo:BAAANQADCgQIBAAAAA==.Shaayllee:BAAANQAECgQIBQAAAA==.Shaaytheyha:BAABNQAECn8ZAAIIAAcK6wZc6QBCAQAIAAcK6wZc6QBCAQAAAA==.Shaggyp:BAAANQAECgEIAQAAAA==.Shamump:BAAANQADCgcIBwAAAA==.Sharyl:BAAANQABCgcICwAAAA==.Shehasnoname:BAAANQADCgYIGAAAAA==.Shehulk:BAAANQAECgUICwAAAA==.Shingo:BAAANQADCgcIBwABNQAECgkJJwAFABshAA==.Ships:BAABNQAECn8ZAAIdAAkKLRQGFwBGAgAdAAkKLRQGFwBGAgAAAA==.',
Si='Silf:BAAANQAECgEIAQAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skibbward:BAAANQADCgQIBAABNQAFFAUICgAUAJcVAA==.Skrektwo:BAABNQAECn8bAAMXAAcKfRNpegCYAQAXAAcKfRNpegCYAQASAAUK4gW22ADfAAAAAA==.',
Sm='Smackdogg:BAACNQAFFH8MAAIaAAUKQiB1DQCNAQAaAAUKQiB1DQCNAQA1AAQKfx0AAhoACQrKJMITACcDABoACQrKJMITACcDAAAA.',
So='Solarspark:BAAANQAECgYIEQAAAA==.Sondaladan:BAAANQADCggIFQAAAA==.Sonomonom:BAAANQADCggIEAAAAA==.Soota:BAAANQABCgQIBwAAAA==.Sorvina:BAABNQAECn8kAAIVAAgKAgxLjwC7AQAVAAgKAgxLjwC7AQAAAA==.Soulflame:BAABNQAECn8iAAIWAAgKYQr1DwClAQAWAAgKYQr1DwClAQAAAA==.Soulkings:BAAANQADCggIGgAAAA==.',
Sp='Spriggs:BAAANQADCgUIBAAAAA==.',
St='Starpath:BAAANQAECgMIAwABNQAECggICgACAAAAAA==.Strangr:BAAANQADCggICwABNQAECgUIBQACAAAAAA==.Stregnor:BAAANQAECgYICwAAAA==.Styggi:BAAANQADCggICAAAAA==.Stygy:BAAANQADCgcIBwABNQADCggICAACAAAAAA==.',
Su='Sumyunguy:BAABNQAECn8UAAIRAAYKRRktLwCaAQARAAYKRRktLwCaAQAAAA==.',
Sy='Sylunia:BAABNQAECn8YAAIWAAcK2QO9HgDxAAAWAAcK2QO9HgDxAAAAAA==.Sylváñás:BAAANQABCggIFAAAAA==.Syrintha:BAAANQADCgYIDAAAAA==.',
Ta='Tachi:BAAANQAECgUICwABNQAECgcIGwAMAAEYAA==.Tachie:BAABNQAECn8bAAIMAAcKARjxEwAMAgAMAAcKARjxEwAMAgAAAA==.Talonclaw:BAAANQABCgQICQAAAA==.Talön:BAEANQAECgUJBQAAAA==.Tarvah:BAAANQADCgYIBgAAAA==.',
Te='Teranox:BAAANQABCgYIGwAAAA==.Tezzerae:BAAANQAECgQIBwAAAA==.',
Th='Theistica:BAAANQAECgUIDQAAAA==.Therin:BAABNQAECn8jAAMPAAcKABBCCADTAQAPAAcKABBCCADTAQAcAAcKBwZEQwA4AQAAAA==.Thodi:BAAANQABCgYICgAAAA==.',
To='Todes:BAAANQADCgIIAgAAAA==.Tongshi:BAAANQABCggIDAAAAA==.Toofast:BAABNQAECn8cAAIXAAcKvR4VPgBlAgAXAAcKvR4VPgBlAgAAAA==.Toofurrious:BAAANQADCgQJBgAAAA==.Toolotems:BAAANQAECgUIBwAAAA==.Topswimmer:BAAANQABCgIIAgAAAA==.',
Tr='Trifus:BAAANQAECgEIAQAAAA==.',
Tu='Tulao:BAAANQAECgYICwABNQAECgkJJQASANceAA==.',
Ty='Tylae:BAAANQADCgQIBwAAAA==.',
Ut='Utheli:BAABNQAECn8lAAIIAAkKNBucTQCoAgAIAAkKNBucTQCoAgAAAA==.',
Va='Vaeyethir:BAAANQABCgcICAAAAA==.Vaildora:BAAANQAECgQIBwABNQAECgcIGwAMAAEYAA==.Valdra:BAABNQAECn8YAAIeAAcKKBfYFQDHAQAeAAcKKBfYFQDHAQAAAA==.Valkyl:BAAANQADCgIIAgAAAA==.Valkyll:BAAANQADCgIIAgAAAA==.Valord:BAAANQADCgcIBwAAAA==.Vane:BAAANQADCgEIAQAAAA==.Vanillacain:BAAANQADCgMIAwAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgcIFwAAAA==.',
Vl='Vlonet:BAABNQAECn8pAAMZAAgKWxRaKgDrAQAZAAcKQhZaKgDrAQAfAAEK7QgvlQAuAAAAAA==.',
Vn='Vnasty:BAAANQAECgQIBwABNQAECgkJLAASACwiAA==.',
Vo='Vokola:BAAANQAECgQIBAABNQAECgcIGwAMAAEYAA==.',
We='Wehadnoname:BAAANQABCgEIAQAAAA==.',
Wi='Wilken:BAAANQAECgIIBAAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwACAAAAAA==.Wiva:BAAANQAECgQIBgAAAA==.',
Wo='Wolfsokol:BAAANQAFFAEIAwABNQAFFAcICwAdAMUdAA==.',
Wr='Wreckoner:BAABNQAECn8iAAIUAAgKSBBYJAC6AQAUAAgKSBBYJAC6AQAAAA==.',
Xa='Xavencia:BAAANQADCgYICgAAAA==.',
Xi='Xinthos:BAAANQAECgIIAgAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Yu='Yukiakari:BAAANQADCgQIBQAAAA==.',
Za='Zaderan:BAAANQADCgQIBAAAAA==.Zakainu:BAAANQAECgUIEAAAAA==.Zallister:BAAANQADCggIKAAAAA==.Zansarutobi:BAAANQABCgYIBgAAAA==.Zarathoszan:BAABNQAECn8aAAIQAAgK+wj9jgDoAQAQAAgK+wj9jgDoAQAAAA==.',
Ze='Zedator:BAABNQAECn8dAAIPAAgK6Bd/BQBhAgAPAAgK6Bd/BQBhAgAAAA==.Zedraikis:BAAANQADCgEIAQAAAA==.Zeedle:BAAANQABCgQIBAAAAA==.Zelgaddis:BAABNQAECn8cAAIXAAgKjBKUaQDMAQAXAAgKjBKUaQDMAQAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zh='Zhansaya:BAAANQAECgEIAgAAAA==.',
Zr='Zriana:BAAANQAECgIIAwAAAA==.',
Zs='Zsarilya:BAAANQAECgUIDQAAAA==.',
Zu='Zurgen:BAABNQAECn8eAAIVAAcKIRthWQBHAgAVAAcKIRthWQBHAgAAAA==.',
['Àn']='Àndrol:BAAANQAECgYIDwABNQAECgcIEwACAAAAAA==.',
['Êc']='Êclipse:BAEBNQAECn8kAAIHAAkKKhrXEQC/AgAHAAkKKhrXEQC/AgAAAA==.',
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
