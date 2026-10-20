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

local lookup = {'Paladin-Holy','Unknown-Unknown','Warrior-Arms','Priest-Shadow','Priest-Discipline','Hunter-BeastMastery','DeathKnight-Frost','Priest-Holy','Paladin-Retribution','Druid-Restoration','DemonHunter-Vengeance','DeathKnight-Blood','Evoker-Devastation','Rogue-Assassination','DeathKnight-Unholy','Mage-Arcane','Rogue-Subtlety','Hunter-Survival','Monk-Mistweaver','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Mage-Frost','DemonHunter-Havoc','Monk-Windwalker','DemonHunter-Devourer','Hunter-Marksmanship','Druid-Balance','Warlock-Destruction','Druid-Guardian','Evoker-Preservation','Warrior-Protection','Shaman-Enhancement',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aarchon:BAABNQAECn8pAAIBAAgKxx2mCAA5AgABAAgKxx2mCAA5AgAAAA==.',
Ad='Aduin:BAAANQAECgcIBwAAAA==.',
Ae='Aedarelyn:BAAANQAECgMIBAAAAA==.Aellita:BAAANQAECgMIAwAAAA==.Aenoryae:BAAANQADCgYIBgABNQADCgYICwACAAAAAA==.Aeschylus:BAAANQADCgIIAwAAAA==.',
Af='Afkinlife:BAAANQADCgYJBwAAAA==.',
Ai='Aias:BAAANQADCgcIBwAAAA==.',
Ak='Akky:BAABNQAECn8aAAIDAAkK0hM0iwAAAgADAAkK0hM0iwAAAgAAAA==.Aksafiya:BAABNQAECn9FAAMEAAkKuhFJBwCBAQAEAAkKuhFJBwCBAQAFAAEK5QGHMQAgAAAAAA==.',
Al='Alal:BAAANQADCgYIFQAAAA==.Alaras:BAACNQAFFH8JAAIEAAQKGgrcDAASAQAEAAQKGgrcDAASAQA1AAQKfyAAAgQACQpJFiIVALgCAAQACQpJFiIVALgCAAAA.Aleesha:BAAANQADCgYJBwAAAA==.Alissia:BAAANQADCgYIBgAAAA==.Allaras:BAAANQADCgYIDAAAAA==.Allistaris:BAABNQAECn8cAAIGAAkK2BVVZwBFAgAGAAkK2BVVZwBFAgAAAA==.Allrianne:BAAANQAECgEIAQAAAA==.Alluriela:BAAANQADCgIIAwAAAA==.Allyriae:BAAANQAECgcIDgAAAA==.Alphá:BAABNQAECn8gAAIHAAkKMwtaSgCRAQAHAAkKMwtaSgCRAQAAAA==.Althoraty:BAABNQAECn8lAAIIAAgKBRb7FQDBAQAIAAgKBRb7FQDBAQAAAA==.',
Am='Amberlilly:BAABNQAECn8VAAIJAAYKrwSUsQCEAAAJAAYKrwSUsQCEAAAAAA==.',
An='Andoros:BAABNQAECn8iAAIKAAgKmR8uGAB+AgAKAAgKmR8uGAB+AgAAAA==.Angelon:BAAANQADCgQIBgAAAA==.Antilles:BAAANQADCgMIAwAAAA==.Anzurath:BAABNQAECn8hAAIJAAgKXA5xMwBmAQAJAAgKXA5xMwBmAQAAAA==.',
Ap='Apheron:BAABNQAECn8qAAILAAgKcyI1AQArAgALAAgKcyI1AQArAgAAAA==.Apollimy:BAAANQAECggIBgAAAA==.Applebow:BAABNQAECn8WAAIMAAYKxxTCKgDJAAAMAAYKxxTCKgDJAAAAAA==.Apples:BAAANQAECgUIBQAAAA==.',
Ar='Arathwr:BAAANQADCgcIBwABNQAECgMIBAACAAAAAA==.Ardalel:BAAANQADCgcICAAAAA==.Arknova:BAABNQAECn8fAAIJAAkKVxfVfAAxAgAJAAkKVxfVfAAxAgAAAA==.Arylin:BAAANQAECgIIAwAAAA==.',
As='Asheram:BAAANQADCgEIAQAAAA==.Ashkinassi:BAEANQADCgUIBgAAAA==.Asiain:BAAANQAECgUIBgABNQAFFAUICAADADsPAA==.Asnabel:BAABNQAECn8WAAIHAAcKLAf2OwCzAAAHAAcKLAf2OwCzAAAAAA==.',
At='Atsa:BAAANQADCgQIBAAAAA==.Atvar:BAAANQADCggICAAAAA==.',
Au='Aurelith:BAAANQAECgcICwAAAA==.Autumndeath:BAAANQAECgMIBQAAAA==.',
Av='Avinger:BAAANQABCggIGQAAAA==.',
Ay='Ayden:BAABNQAECn8hAAILAAgKoROeDgDPAQALAAgKoROeDgDPAQAAAA==.',
Az='Azorain:BAAANQADCgQIBAAAAA==.Azrim:BAAANQADCgYIDgABNQAECgIIAgACAAAAAA==.Azureis:BAAANQADCgcICAAAAA==.',
Ba='Balolz:BAAANQABCgYIEQAAAA==.',
Be='Belthar:BAABNQAECn8cAAIMAAgKGBRtTwC3AQAMAAgKGBRtTwC3AQAAAA==.Bendeye:BAAANQADCgYIDgAAAA==.',
Bl='Blee:BAAANQAECgMIBgAAAA==.Bluudclaaw:BAAANQADCgMIAwABNQAECgcIIAANAEUZAA==.',
Bo='Boing:BAABNQAECn8fAAIOAAkKjxkPEwAsAQAOAAkKjxkPEwAsAQAAAA==.Bondad:BAAANQAECgIIAgABNQAECgcICwACAAAAAA==.Boomhauer:BAABNQAECn8WAAIGAAYK7RjmSQAgAQAGAAYK7RjmSQAgAQAAAA==.',
Br='Braelia:BAABNQAECn8VAAIPAAcKHg6DaQBsAQAPAAcKHg6DaQBsAQAAAA==.Braetwo:BAAANQABCggJDwABNQAECgcIFQAPAB4OAA==.Braughm:BAAANQADCgUJBQAAAA==.Braxius:BAAANQADCgMIAwABNQAECggILAAQALMeAA==.Breye:BAAANQAECgYIDgAAAA==.Brindria:BAAANQADCgQIBgAAAA==.Brood:BAAANQAECgUIEwABNQAECgYIDgACAAAAAA==.Brundles:BAABNQAECn8pAAIJAAgKeAeAawDuAAAJAAgKeAeAawDuAAAAAA==.',
Bu='Bubblepopper:BAABNQAECn8VAAIIAAYKBCFBVgAgAgAIAAYKBCFBVgAgAgAAAA==.Bunky:BAAANQAECgUIDgAAAA==.',
Ca='Cailaranel:BAABNQAECn8YAAIRAAkKjwdjEwA9AQARAAkKjwdjEwA9AQAAAA==.Calaul:BAABNQAECn8kAAIJAAgKWQ6SVwAVAQAJAAgKWQ6SVwAVAQAAAA==.Calenbraga:BAAANQAECgQIDwAAAA==.Calisim:BAAANQAECgMIBQAAAA==.Caloh:BAAANQAECgUIDgAAAA==.Cantholdagro:BAAANQAECgEIAQABNQAECggIEQACAAAAAA==.Cassamaria:BAABNQAECn8cAAISAAkKSRCeAgByAQASAAkKSRCeAgByAQAAAA==.Cataryn:BAABNQAECn8pAAIGAAgKqh+xCwAWAgAGAAgKqh+xCwAWAgAAAA==.Catt:BAABNQAECn8jAAIBAAcKahNiHgBxAQABAAcKahNiHgBxAQAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECggIKQAMABIeAA==.',
Ce='Cellebur:BAAANQAECgMIBAAAAA==.Ceta:BAABNQAECn8fAAIIAAgKhxUFGgClAQAIAAgKhxUFGgClAQAAAA==.',
Ch='Chalfus:BAABNQAECn8sAAIQAAgKsx52BgBoAgAQAAgKsx52BgBoAgAAAA==.Chaszmyr:BAAANQADCggIHQAAAA==.Chewwy:BAABNQAECn8gAAIMAAkKzRkABAAjAgAMAAkKzRkABAAjAgAAAA==.',
Ci='Cinamen:BAAANQAECgIIAgAAAA==.Cizean:BAAANQAECgQICwAAAA==.',
Cl='Clare:BAAANQABCgQIBAABNQAECggIKQAGAKofAA==.Closetofsmut:BAAANQADCgcIBwAAAA==.',
Cr='Craivan:BAAANQADCgUICQAAAA==.Crendoal:BAAANQADCgQIBgABNQAECgcIIwATAGEVAA==.Crilly:BAAANQAECgMJAwAAAA==.Crowley:BAAANQADCgQIBAAAAA==.Crumpler:BAABNQAECn8fAAIJAAgKHA4sUQAiAQAJAAgKHA4sUQAiAQAAAA==.Crüsnik:BAAANQADCgMIAwAAAA==.',
Cy='Cyroka:BAAANQAECgUICAAAAA==.Cytroncutoff:BAAANQAECgEIAQAAAA==.',
Da='Dalastish:BAAANQADCggIDAAAAA==.Damia:BAABNQAECn8WAAMRAAYKnhdCGwAIAQARAAYKnhdCGwAIAQAOAAMKnQx9fwC2AAAAAA==.Danobun:BAABNQAECn8nAAMUAAoKzR7+HwAMAwAUAAoKzR7+HwAMAwAVAAEKLAdpnQAyAAAAAA==.Darsithis:BAAANQAECgUIDgAAAA==.',
De='Deadite:BAABNQAECn8pAAIMAAgKEh74BgDLAQAMAAgKEh74BgDLAQAAAA==.Deadstealth:BAAANQADCgYIBgAAAA==.Delphirose:BAAANQABCggIDwABNQAECgMIBAACAAAAAA==.Delvarrieth:BAAANQAECgQICwAAAA==.Demzy:BAAANQAECgIIAgAAAA==.Denth:BAAANQAECgMIBQAAAA==.Dercuur:BAABNQAECn8pAAIUAAoKeRWAQgBrAgAUAAoKeRWAQgBrAgAAAA==.Devira:BAAANQADCgYICQAAAA==.',
Di='Displacer:BAAANQADCggICAAAAA==.',
Do='Dondeestasto:BAAANQADCgMIAwAAAA==.Dotur:BAAANQADCgIIAgAAAA==.',
Dr='Dragonkiss:BAAANQADCgQIBwAAAA==.Drainmee:BAAANQAECgUIBgAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAABNQAECn8fAAIPAAkKVQrNbgBZAQAPAAkKVQrNbgBZAQAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAAANQAECgQIBQAAAA==.',
['Dá']='Dárkbeard:BAAANQAECgIIBAAAAA==.',
Ek='Ekneirg:BAABNQAECn8hAAMJAAgK5xqVFgDLAQAJAAgKzRmVFgDLAQAWAAYKHBmaKwCAAQABNQABCgEIAQACAAAAAA==.',
El='Elleneilah:BAAANQADCgUICQAAAA==.Elynth:BAABNQAECn8pAAIXAAgK9xM2GQCNAQAXAAgK9xM2GQCNAQAAAA==.',
Em='Emmalily:BAAANQAECgIIAwAAAA==.',
En='Endlessyueh:BAAANQAECgEIAQAAAA==.',
Ex='Extragrippy:BAAANQAECggIEQAAAA==.',
Ey='Eyris:BAAANQADCgYICAAAAA==.',
Fa='Faiesong:BAAANQABCgQIBAAAAA==.Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAABNQAECn8kAAIYAAkKLxTjAQDdAQAYAAkKLxTjAQDdAQAAAA==.Fangren:BAAANQAECgEIAQAAAA==.Farrseer:BAABNQAECn8WAAIZAAYKBArNJQDaAAAZAAYKBArNJQDaAAAAAA==.Fasthandslez:BAAANQAECgIIAgAAAA==.',
Fe='Felscythe:BAAANQAECgQICwAAAA==.Felynn:BAAANQABCgMIAwAAAA==.',
Fi='Fierrastar:BAABNQAECn8hAAISAAkKmSAfAwDrAgASAAkKmSAfAwDrAgAAAA==.Finnius:BAAANQADCgMIBAAAAA==.Finshao:BAAANQAECgQICQAAAA==.Fionn:BAAANQADCgcIBwABNQAECgMIBAACAAAAAA==.',
Fl='Flemish:BAABNQAECn8WAAIUAAYK/w5kOwDYAAAUAAYK/w5kOwDYAAAAAA==.Flextame:BAAANQADCggIHAAAAA==.Flipalicious:BAABNQAECn80AAMUAAkKERJkEQCLAQAUAAkKERJkEQCLAQAVAAgKyA7ilgBOAQAAAA==.Flipanomicon:BAAANQADCgYIEAAAAA==.Flipkicks:BAAANQADCgYICgAAAA==.Flipmode:BAAANQADCgcIEAAAAA==.Flipnasty:BAAANQADCgYICwAAAA==.Flipocalypse:BAAANQADCgYICgAAAA==.',
Fo='Foxwynn:BAAANQABCgQIBgAAAA==.',
Fr='Freyalise:BAABNQAECn8dAAMEAAcKhxcuMACiAQAEAAYKqRMuMACiAQAIAAUKmwIi0AC0AAAAAA==.Freyjah:BAAANQADCgUIBQAAAA==.Frostycarbon:BAAANQADCgYICwAAAA==.',
Ga='Gaia:BAABNQAECn8YAAIGAAcKkQo+TQAYAQAGAAcKkQo+TQAYAQAAAA==.Gallimaufrey:BAAANQAECgQIBwAAAA==.Garodan:BAAANQADCgcIDQAAAA==.',
Ge='Gerbo:BAABNQAECn8vAAIQAAkKrgraLgBkAQAQAAkKrgraLgBkAQAAAA==.',
Gi='Gianavel:BAABNQAECn8hAAIaAAkKOgqBMwB5AQAaAAkKOgqBMwB5AQAAAA==.Ginodh:BAAANQAECgQIBgABNQAECgcICgACAAAAAA==.Ginomage:BAAANQAECgcICgAAAA==.Ginopally:BAAANQADCgMIAwABNQAECgcICgACAAAAAA==.Ginoshaman:BAAANQADCgUIBgABNQAECgcICgACAAAAAA==.Ginovoker:BAAANQADCgYICQABNQAECgcICgACAAAAAA==.Gizelli:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.',
Gr='Grilled:BAAANQADCgYICwAAAA==.Gronke:BAAANQAECgMJAwABNQABCgEIAQACAAAAAA==.Grubetsella:BAABNQAECn8jAAMTAAcKYRUELQADAQATAAUKfhAELQADAQAaAAYKURahFgD0AAAAAA==.Grugachur:BAAANQAECgQICQAAAA==.',
Gu='Gustice:BAAANQADCgIJAgAAAA==.',
Gy='Gyda:BAAANQAECgEIAgAAAA==.',
Ha='Hadooken:BAAANQABCgQIBAAAAA==.Hangi:BAAANQADCgEIAQABNQAECgcICwACAAAAAA==.Hanoumatoi:BAAANQAECgYICwAAAA==.Haralambos:BAAANQAECgMIBAAAAA==.Harlar:BAAANQADCgUICgAAAA==.Hasun:BAABNQAECn8UAAIJAAoKFxOWUQAhAQAJAAoKFxOWUQAhAQABNQAECgoKJwAUAM0eAA==.',
He='Hehasnoname:BAAANQADCgYICQAAAA==.Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQAECgIIAgAAAA==.',
Ho='Hordkilla:BAAANQAECgUIDQAAAA==.Hownowbrncw:BAABNQAECn8WAAIJAAcKABNDbQDrAAAJAAcKABNDbQDrAAAAAA==.',
Hy='Hyce:BAABNQAECn8iAAMbAAgKBxUmCgBwAQAbAAgKlRMmCgBwAQALAAMK/hiWHQDmAAAAAA==.Hymno:BAAANQADCgYICQAAAA==.',
Ih='Ihavenoname:BAAANQADCgYJCwAAAA==.',
Il='Illusionous:BAAANQAECgIIAwAAAA==.',
In='Insoniacyun:BAAANQAECgIIAQAAAA==.',
Is='Iselian:BAAANQAECggIGgAAAQ==.Istrix:BAAANQADCgUJBQAAAA==.',
Ja='Jadefeather:BAAANQAECggIDgAAAA==.',
Jb='Jbelbueno:BAAANQAECgEIAQAAAA==.Jblockiv:BAAANQAECgMIAwAAAA==.Jbprimero:BAAANQAECgUIBQAAAA==.Jbshami:BAABNQAECn8gAAIVAAkKzhp3RQBLAgAVAAkKzhp3RQBLAgAAAA==.',
Je='Jeman:BAAANQABCggICAAAAA==.Jenaelle:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAABNQAECn8iAAIQAAgK/AFzfgDEAAAQAAgK/AFzfgDEAAAAAA==.Jetfires:BAABNQAECn81AAIGAAkKwhyEIQCSAQAGAAkKwhyEIQCSAQAAAA==.',
Ji='Jinger:BAAANQAECgYIDQAAAA==.Jinnwoo:BAAANQADCgUIBgAAAA==.',
Jo='Jonn:BAAANQAECgEIAQAAAA==.Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQAECgEIAgAAAA==.',
Ju='Juggernacht:BAAANQAECgIIAgABNQAECgcIHgAIADwbAA==.',
Ka='Kaedren:BAAANQADCgYIEQAAAA==.Kaelorien:BAABNQAECn8YAAITAAcK0whiKQAnAQATAAcK0whiKQAnAQAAAA==.Kalazaad:BAABNQAECn8cAAIWAAgKkAUWFgDZAAAWAAgKkAUWFgDZAAAAAA==.Kaldevayn:BAAANQAECgIIBAAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalrow:BAABNQAECn8UAAMbAAcKLQyIIwCWAAAbAAcKLQyIIwCWAAAZAAEKAABVnwAgAAAAAA==.Kalto:BAAANQAECgIIBQAAAA==.Kalyna:BAAANQAECgUIBgAAAA==.Kardanika:BAAANQADCgcIBgAAAA==.Kardanis:BAABNQAECn8pAAIVAAgKnB8fBgB0AgAVAAgKnB8fBgB0AgAAAA==.Kashe:BAAANQAECgMIBAAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAABNQAECn8gAAIYAAgKYxU5CgAoAgAYAAgKYxU5CgAoAgAAAA==.Katavia:BAABNQAECn8pAAIVAAgK2g66HAB5AQAVAAgK2g66HAB5AQAAAA==.Kathii:BAAANQAECgQICQAAAA==.Katrazath:BAAANQAECgUIEAAAAA==.Kaydencia:BAAANQABCgUICAAAAA==.',
Ke='Kelmmers:BAAANQAECgUIBgAAAA==.Keyallandron:BAAANQAECgUIDAAAAA==.Keywi:BAAANQAECgIIAQAAAA==.',
Kh='Khaleesie:BAAANQAECgEIAgAAAA==.Khiana:BAAANQADCgIIAgABNQAECggIKQAGAKofAA==.Khrin:BAAANQADCgYICgAAAA==.',
Ki='Kiddow:BAAANQAECgMIBAAAAA==.Kierea:BAAANQADCgcIDgAAAA==.Kiiarah:BAAANQAECgYIDQAAAA==.Killrah:BAAANQADCgQIBAAAAA==.Kilrah:BAAANQADCggICgAAAA==.Kilriella:BAAANQADCgYIBwAAAA==.Kinte:BAAANQADCgYIBgAAAA==.Kitamii:BAAANQAECgYICgAAAA==.Kitaña:BAAANQABCggIEgAAAA==.Kivrin:BAAANQAECgUIDQAAAA==.Kiára:BAAANQADCggIDQAAAA==.',
Ko='Kokujin:BAABNQAECn8lAAIUAAcK3hOaKQAXAQAUAAcK3hOaKQAXAQAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAABNQAECn8gAAIGAAoKih7LMgDUAgAGAAoKih7LMgDUAgAAAA==.',
Ku='Kurumi:BAAANQAECgEIAQAAAA==.',
Kw='Kwo:BAAANQAECgYIDQAAAA==.',
Ky='Kymma:BAABNQAECn8YAAIJAAYKBAn8fgDOAAAJAAYKBAn8fgDOAAAAAA==.',
La='Laviz:BAAANQADCgYIBwABNQAECgoKJwAUAM0eAA==.Laz:BAAANQADCgMIAwAAAA==.Lazengann:BAABNQAECn8gAAMbAAkK9RtYFQC6AgAbAAkK9RtYFQC6AgAZAAEKAAAOXQAAAAAAAA==.',
Le='Leafbane:BAABNQAECn84AAMHAAkKuhn9IwBxAgAHAAkKuhn9IwBxAgAMAAEK4BbNwQBFAAAAAA==.Legevia:BAAANQAECgMICAAAAA==.Leiris:BAABNQAECn8fAAMJAAgKHAzUQABFAQAJAAgKHAzUQABFAQABAAEKoQAbOwEZAAAAAA==.Lejusticier:BAAANQADCggIDAAAAA==.Leonaa:BAAANQADCgYIEwAAAA==.Leucetios:BAAANQAECgUICwAAAA==.',
Li='Liarace:BAAANQAECgYICAAAAA==.Lightbeard:BAAANQAECgMIBgAAAA==.Lightforge:BAAANQAECgYIEAAAAA==.Lionessi:BAAANQADCgcIBwAAAA==.Lithika:BAAANQADCgYIBgAAAA==.',
Lo='Lorredain:BAAANQADCgYIDQAAAA==.Lothaire:BAAANQAECgMIAwAAAA==.Lothwen:BAAANQAECgIIAwAAAA==.Louisachan:BAAANQAECgIIAgAAAA==.',
Lu='Lucamar:BAAANQADCgQIBAAAAA==.Luxinine:BAABNQAECn8nAAIEAAgKex2EBwB+AQAEAAgKex2EBwB+AQAAAA==.',
Ma='Madhawi:BAAANQAECgEIBAAAAA==.Magamon:BAABNQAECn8pAAIQAAgKyBSJLABrAQAQAAgKyBSJLABrAQAAAA==.Magnix:BAAANQADCgQIBAABNQAECgQICgACAAAAAA==.Malfuriia:BAAANQAECgQICwAAAA==.Mamboke:BAABNQAECn8aAAMGAAkK7wg1IgCPAQAGAAkK7wg1IgCPAQAcAAQKVgKIaQCHAAAAAA==.Margerdria:BAAANQADCgcIEAAAAA==.Mauugrim:BAAANQAECgQIDQAAAA==.Maxowen:BAAANQAECgQICwAAAA==.Maxxramas:BAAANQADCgcICgAAAA==.',
Me='Mearadan:BAABNQAECn8bAAIVAAkKUAlxTgDDAAAVAAkKUAlxTgDDAAAAAA==.Meatsweats:BAAANQAECgEIAQAAAA==.Megg:BAAANQAECgUIBQAAAA==.Mekh:BAAANQAECgQICwAAAA==.Mel:BAAANQADCgcIFQAAAA==.Melanara:BAABNQAECn8hAAIYAAkK/w1VDgDGAQAYAAkK/w1VDgDGAQAAAA==.Melstrom:BAAANQAECgIIAwAAAA==.Meticuluslyn:BAAANQAECgEIAQAAAA==.',
Mi='Milkmaiden:BAAANQADCgQJCAAAAA==.Milkthisbull:BAAANQADCgMIAwAAAA==.Mixler:BAAANQAECgcIDwAAAA==.',
Mm='Mmeow:BAAANQADCgYIEAABNQAECggIHQAGAOwdAA==.',
Mo='Moirine:BAAANQAECgQICwAAAA==.',
Mu='Murdrmitts:BAAANQAECgUIDAAAAA==.Mustikka:BAAANQAECgIIAgAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Myuriyanka:BAABNQAECn8qAAIUAAkKXg7bagDgAQAUAAkKXg7bagDgAQAAAA==.',
['Mæ']='Mælstrôm:BAAANQABCgQICAAAAA==.',
Na='Naahommii:BAAANQADCgUIBQAAAA==.Nachtamus:BAAANQAECgIIAQABNQAECgcIHgAIADwbAA==.Nachtpranke:BAAANQAECgMIAwABNQAECgcIHgAIADwbAA==.Nachtteufel:BAAANQAECgEIAQABNQAECgcIHgAIADwbAA==.Naeri:BAAANQAECgUIEgAAAA==.Naieve:BAABNQAECn8fAAIdAAkKYBBQQAD5AQAdAAkKYBBQQAD5AQAAAA==.Nastii:BAAANQADCgEIAQAAAA==.Nastychungus:BAABNQAECn8sAAMUAAkKLCKVGAA1AwAUAAkKLCKVGAA1AwAVAAUK6AM60wDAAAAAAA==.Navira:BAAANQADCggIHgAAAA==.',
Ne='Negargra:BAABNQAECn8XAAIXAAoKdQiFTADuAAAXAAoKdQiFTADuAAAAAA==.Nekoda:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Nephadin:BAAANQAECgEIAQAAAA==.Neyvin:BAAANQADCggICAAAAA==.',
Ni='Nighttiger:BAAANQAECgMIAwAAAA==.Nikooli:BAABNQAECn8UAAMZAAYKlA0jUQBSAQAZAAYKlA0jUQBSAQALAAEKygXnGwAiAAAAAA==.',
No='Noopsie:BAAANQAECgQIDQAAAA==.Nooters:BAABNQAECn8xAAIHAAoK6SEMBwBzAwAHAAoK6SEMBwBzAwAAAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAABNQAECn8cAAMIAAgKnh7dBwBsAgAIAAgKnh7dBwBsAgAEAAEKVgcUdwA4AAAAAA==.',
Nu='Nunavutt:BAAANQADCgUIBQAAAA==.',
Ny='Nyteweaver:BAAANQAECgQICgAAAA==.',
Od='Oderica:BAAANQAECggIBQAAAA==.Odurn:BAAANQADCgYIBgAAAA==.',
Og='Ogafor:BAAANQABCgIIAgAAAA==.Ogayac:BAAANQAECgEIAQAAAA==.',
Oh='Ohminous:BAAANQADCggICAAAAA==.',
Or='Oranash:BAAANQADCgMIAwAAAA==.Orici:BAAANQAECgIIAgABNQAECgIIAwACAAAAAA==.Ornir:BAAANQADCgMIAwAAAA==.Orongosh:BAAANQADCgYIBgAAAA==.',
Os='Oscarmikey:BAABNQAECn8tAAMdAAoKPBXKEQBLAQAdAAoKPBXKEQBLAQAKAAQKsxN4RwD3AAAAAA==.Oshu:BAAANQADCgcIBgAAAA==.',
Ot='Ottoshot:BAAANQAECgQICwAAAA==.Otum:BAAANQAECgQIBgAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
Ox='Oxmantle:BAAANQAECgIIAgAAAA==.',
['Oö']='Oöps:BAAANQAECgUIEQAAAA==.',
Pa='Paksen:BAAANQAECgYIBgAAAA==.Panamone:BAAANQAECgUIBAAAAA==.Pandamaster:BAAANQAECggIDwAAAA==.Paulee:BAAANQAECgEIAQAAAA==.',
Pe='Pendragon:BAAANQADCgQIBQAAAA==.Pesch:BAAANQAECggICAAAAA==.',
Ph='Phylah:BAAANQAECgUIDwAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Porterhouze:BAAANQABCgIIAgABNQAECgcIJAAeAIwEAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.Prophetofham:BAAANQADCgYIBgAAAA==.',
Pu='Puchi:BAACNQAFFH8WAAITAAYKSxf5AwCpAQATAAYKSxf5AwCpAQA1AAQKfzIAAhMACgqkIYkEAF0DABMACgqkIYkEAF0DAAAA.Pug:BAAANQADCggIEwABNQAECgkJHwAOAI8ZAA==.',
Qa='Qadhiræ:BAAANQAECgEIAQABNQADCgYICwACAAAAAA==.',
['Qæ']='Qædhira:BAAANQADCgYICwAAAA==.',
Ra='Raez:BAAANQAECgcIDQAAAA==.Ragnerock:BAAANQAECgMIBAAAAA==.Raynecira:BAABNQAECn8UAAIGAAcKFQwivgCHAQAGAAcKFQwivgCHAQAAAA==.',
Re='Reihino:BAAANQAECgEIAQAAAA==.Remixidora:BAAANQAECgQJCAABNQAFFAUIBgAQAMAeAA==.Reyrocko:BAAANQAECgEIAQAAAA==.Rezdh:BAAANQAECgYIDQABNQAFFAEIAQACAAAAAA==.Rezmage:BAAANQAFFAEIAQAAAA==.Reznal:BAAANQAECgMIAwABNQAFFAEIAQACAAAAAA==.Rezvoker:BAAANQADCgUJCgABNQAFFAEIAQACAAAAAA==.',
Rh='Rhage:BAAANQADCgcIFAAAAA==.Rhoaias:BAAANQADCggIIwAAAA==.Rhunyaye:BAAANQADCgUICgAAAA==.',
Ri='Rickness:BAAANQAECgIIBAAAAA==.Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokform:BAAANQAECgQIBAAAAA==.Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQAECgEIAQAAAA==.Rottingturky:BAAANQAECggIEgAAAA==.Roxane:BAABNQAECn8YAAIdAAcKIQfoJADSAAAdAAcKIQfoJADSAAAAAA==.',
Ru='Rubyace:BAAANQAECgQIBQAAAA==.Runningelk:BAABNQAECn8ZAAIfAAgK9hnwBwB/AQAfAAgK9hnwBwB/AQAAAA==.Runscapemain:BAABNQAECn8lAAIJAAgK1AmtWQARAQAJAAgK1AmtWQARAQAAAA==.',
Ry='Ryeti:BAAANQADCggILwAAAA==.Ryuzu:BAAANQADCgYIBgAAAA==.Ryydia:BAAANQADCgMIBQAAAA==.',
Sa='Sahalia:BAAANQADCgUIDAABNQAECgIIBAACAAAAAA==.Saintulrick:BAAANQAECgUIBQAAAA==.Sajuice:BAABNQAECn8cAAMGAAkKFRs+IQCTAQAGAAkKFRs+IQCTAQAcAAQKKRRDUQDlAAAAAA==.Salow:BAAANQABCgYICgAAAA==.Sanitas:BAABNQAECn8oAAIIAAoKChB1WgASAgAIAAoKChB1WgASAgAAAA==.',
Se='Seeyen:BAACNQAFFH8JAAIGAAQKDhKeEwAsAQAGAAQKDhKeEwAsAQA1AAQKfzYAAgYACgoqI/MOAGoDAAYACgoqI/MOAGoDAAAA.Sej:BAAANQABCgIIAgAAAA==.Seraphon:BAAANQADCggIJAAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAACAAAAAA==.',
Sh='Shaaydo:BAAANQADCgQIBAAAAA==.Shaayllee:BAAANQAECgQIBQAAAA==.Shaaytheyha:BAABNQAECn8bAAIJAAcK6wbZ7ABCAQAJAAcK6wbZ7ABCAQAAAA==.Shaggyp:BAAANQAFFAIIAgAAAA==.Shamump:BAAANQADCgcIBwAAAA==.Sharyl:BAAANQABCgcIEQAAAA==.Shehasnoname:BAAANQADCgYIGAAAAA==.Shehulk:BAAANQAECgUICwAAAA==.Shingo:BAAANQADCgcIBwABNQAECgkJKQAHABshAA==.Ships:BAABNQAECn8cAAIgAAoKQxM0FwBFAgAgAAoKQxM0FwBFAgAAAA==.',
Si='Silf:BAAANQAECgEIAQAAAA==.Silverapples:BAAANQADCgIIAgAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skrektwo:BAABNQAECn8hAAMVAAcKxhOeLQArAQAVAAcKxhOeLQArAQAUAAUK4gVs2wDeAAAAAA==.',
Sm='Smackdogg:BAACNQAFFH8MAAIdAAUKQSDQDQCNAQAdAAUKQSDQDQCNAQA1AAQKfx0AAh0ACQrKJAEUACcDAB0ACQrKJAEUACcDAAAA.',
So='Solarspark:BAAANQAECgYIEQAAAA==.Sondaladan:BAAANQADCggIFQAAAA==.Sonomonom:BAAANQADCggIEAAAAA==.Sorvina:BAABNQAECn8pAAIXAAoKYQx/OwAZAQAXAAoKYQx/OwAZAQAAAA==.Soulflame:BAABNQAECn8pAAIYAAgKKwsjEAClAQAYAAgKKwsjEAClAQAAAA==.Soulkings:BAAANQADCggIGgAAAA==.',
Sp='Spriggs:BAAANQADCgUIBAAAAA==.',
St='Starpath:BAAANQAECgMIAwABNQAECgcICwACAAAAAA==.Strangr:BAAANQADCggICwABNQAECgoKMAAaAEAeAA==.Stregnor:BAABNQAECn8UAAIGAAgKGxBhqQCyAQAGAAgKGxBhqQCyAQAAAA==.Styggi:BAAANQADCggICAAAAA==.Stygy:BAAANQADCgcIBwABNQADCggICAACAAAAAA==.',
Su='Sumyunguy:BAABNQAECn8UAAIaAAYKRRm8LwCZAQAaAAYKRRm8LwCZAQAAAA==.',
Sy='Sylunia:BAABNQAECn8YAAIYAAcK2QMeHwDxAAAYAAcK2QMeHwDxAAAAAA==.Sylváñás:BAAANQABCggIFAAAAA==.Syrintha:BAAANQADCgYIDAAAAA==.',
Ta='Tachi:BAAANQAECgUIEAABNQAECggIIAANAAsYAA==.Tachie:BAABNQAECn8gAAINAAgKCxgkFAAMAgANAAgKCxgkFAAMAgAAAA==.Tairi:BAAANQABCgMIBQAAAA==.Talonclaw:BAAANQABCgQICQAAAA==.Talön:BAEANQAECgUJBQAAAA==.Tarvah:BAAANQADCgYIBgAAAA==.',
Te='Teranox:BAAANQABCgYIGwAAAA==.Tezzerae:BAAANQAECgQICgAAAA==.',
Th='Thaesan:BAAANQAECgQIBAAAAA==.Theistica:BAABNQAECn8WAAIWAAYKjQv6HACpAAAWAAYKjQv6HACpAAAAAA==.Therin:BAABNQAECn8qAAMSAAkKvgzxAgBgAQASAAkKvgzxAgBgAQAcAAcKBwYORAA4AQAAAA==.Thodi:BAAANQABCgYICgAAAA==.',
Ti='Tillymonick:BAAANQAECgIIAgAAAA==.',
To='Todes:BAAANQADCgIIAgAAAA==.Tongshi:BAAANQABCggIDAAAAA==.Toofast:BAABNQAECn8hAAIVAAgK0SDFDgDmAQAVAAgK0SDFDgDmAQAAAA==.Toofurrious:BAAANQADCgQJBgAAAA==.Toolotems:BAAANQAECgUIBwAAAA==.Topswimmer:BAAANQABCgIIAgAAAA==.',
Tr='Trifus:BAAANQAECgEIAQAAAA==.',
Tu='Tulao:BAAANQAECggIDAABNQAECgoKJwAUAM0eAA==.',
Ty='Tylae:BAAANQADCgQIBwAAAA==.',
Ut='Utheli:BAABNQAECn8pAAIJAAoKbxrjTgCoAgAJAAoKbxrjTgCoAgAAAA==.',
Va='Vaeyethir:BAAANQABCgcICAAAAA==.Vaildora:BAAANQAECgUIDgABNQAECggIIAANAAsYAA==.Valdra:BAABNQAECn8fAAIhAAgKARaUBACMAQAhAAgKARaUBACMAQAAAA==.Valkyl:BAAANQADCgIIAwAAAA==.Valkyll:BAAANQADCgIIBAAAAA==.Valkylpal:BAAANQADCgEIAQAAAA==.Valord:BAAANQADCgcIBwAAAA==.Vane:BAAANQADCgEIAQAAAA==.Vanillacain:BAAANQADCgMIAwAAAA==.',
Ve='Vekjari:BAAANQABCgEIAQAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgcIFwAAAA==.',
Vl='Vlonet:BAABNQAECn8yAAMbAAkKFBXDAgAcAgAbAAkKFBXDAgAcAgAZAAEK7QholwAuAAAAAA==.',
Vn='Vnasty:BAAANQAECgQIBwABNQAECgkJLAAUACwiAA==.',
Vo='Vokola:BAAANQAECgQIBgABNQAECggIIAANAAsYAA==.',
We='Wehadnoname:BAAANQABCgEIAQAAAA==.',
Wi='Wilken:BAAANQAECgMIBQAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwACAAAAAA==.Wiva:BAAANQAECgQIBgAAAA==.',
Wo='Wolfsokol:BAAANQAECgYIDgABNQAFFAgIEgAgAEAcAA==.',
Wr='Wreckoner:BAABNQAECn8pAAIWAAgKSBBGCwBHAQAWAAgKSBBGCwBHAQAAAA==.',
Xa='Xannah:BAAANQAECgMIAQAAAA==.Xavencia:BAAANQADCgYICgAAAA==.',
Xi='Xinthos:BAAANQAECgIIAgAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Za='Zaderan:BAAANQADCgYICgAAAA==.Zakainu:BAABNQAECn8VAAIiAAYKrRQ0GwCxAQAiAAYKrRQ0GwCxAQAAAA==.Zallister:BAAANQADCggIKAAAAA==.Zansarutobi:BAAANQABCgYICAAAAA==.Zarathoszan:BAABNQAECn8hAAIGAAgK+whyMQBcAQAGAAgK+whyMQBcAQAAAA==.',
Ze='Zedator:BAABNQAECn8iAAISAAgKORiQBQBhAgASAAgKORiQBQBhAgAAAA==.Zedraikis:BAAANQADCgIIAQAAAA==.Zeedle:BAAANQABCgQIBAAAAA==.Zelgaddis:BAABNQAECn8hAAIVAAkKjxG/agDLAQAVAAkKjxG/agDLAQAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zh='Zhansaya:BAAANQAECgIIBAAAAA==.',
Zr='Zriana:BAAANQAECgMIBQAAAA==.',
Zs='Zsarilya:BAAANQAECgUIEgAAAA==.',
Zu='Zurgen:BAABNQAECn8kAAIXAAcKgBsCGwCFAQAXAAcKgBsCGwCFAQAAAA==.',
['Àn']='Àndrol:BAABNQAECn8WAAIQAAgKVArihAC5AAAQAAgKVArihAC5AAABNQAFFAUICwAbAI8UAA==.',
['Êc']='Êclipse:BAEBNQAECn8uAAIKAAoKTRz5AQDaAgAKAAoKTRz5AQDaAgAAAA==.',
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
