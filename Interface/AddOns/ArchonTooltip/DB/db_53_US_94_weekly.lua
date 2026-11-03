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

local lookup = {'Paladin-Holy','Unknown-Unknown','Warrior-Arms','Priest-Shadow','Priest-Discipline','Hunter-BeastMastery','Rogue-Assassination','DeathKnight-Frost','Priest-Holy','Paladin-Retribution','Druid-Restoration','Druid-Feral','DemonHunter-Vengeance','DeathKnight-Blood','DemonHunter-Havoc','DeathKnight-Unholy','Mage-Arcane','Shaman-Elemental','Shaman-Enhancement','Rogue-Subtlety','Paladin-Protection','Druid-Balance','Warrior-Protection','Hunter-Survival','Mage-Frost','Monk-Windwalker','Shaman-Restoration','Warlock-Demonology','Monk-Brewmaster','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Devourer','Evoker-Devastation','Hunter-Marksmanship','Evoker-Preservation','Warlock-Destruction','Mage-Fire','Druid-Guardian',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aarchon:BAABNQAECn82AAIBAAkKCB+lGgC1AgABAAkKCB+lGgC1AgAAAA==.',
Ad='Aduin:BAAANQAECggICQAAAA==.',
Ae='Aedarelyn:BAAANQAECgQICwAAAA==.Aellita:BAAANQAECgMIAwAAAA==.Aenoryae:BAAANQADCgYIBwABNQADCgYIDAACAAAAAA==.Aeschylus:BAAANQAECgQIBAAAAA==.Aeson:BAAANQAECgIIAgAAAA==.',
Af='Afkinlife:BAAANQADCgYJBwAAAA==.',
Ai='Aias:BAAANQADCgcIBwAAAA==.',
Ak='Akky:BAABNQAECn8hAAIDAAoKnRY0iwAAAgADAAoKnRY0iwAAAgAAAA==.Aksafiya:BAABNQAECn9XAAMEAAkKzRFNFwCxAQAEAAkKzRFNFwCxAQAFAAEK5QGHMQAgAAAAAA==.',
Al='Alal:BAAANQADCgYIFgAAAA==.Alaras:BAACNQAFFH8QAAIEAAYKqwweBQAwAQAEAAYKqwweBQAwAQA1AAQKfyIAAgQACgrcFSIVALgCAAQACgrcFSIVALgCAAAA.Alissia:BAAANQADCggIDgAAAA==.Allaras:BAAANQADCgYIDQAAAA==.Allistaris:BAABNQAECn8mAAIGAAoKExdVZwBFAgAGAAoKExdVZwBFAgAAAA==.Allrianne:BAAANQAECgEIAQAAAA==.Alluriela:BAAANQADCgIIAwAAAA==.Allyriae:BAAANQAECggIDgAAAA==.Alphard:BAAANQAECgYIBwABNQAECgkJHwAHAI8ZAA==.Alphá:BAABNQAECn8gAAIIAAkKMwtaSgCRAQAIAAkKMwtaSgCRAQAAAA==.Althoraty:BAABNQAECn8mAAIJAAkKDRZNTgDGAQAJAAkKDRZNTgDGAQAAAA==.Alucion:BAAANQADCgEIAQAAAA==.',
Am='Amberlilly:BAABNQAECn8hAAIKAAgKqAfUuAAgAQAKAAgKqAfUuAAgAQAAAA==.',
An='Andoros:BAABNQAECn8zAAMLAAoKfh/fCQD2AgALAAkKJCLfCQD2AgAMAAEK3wUAAAAAAAAAAA==.Angelhoofs:BAAANQADCgEIAQAAAA==.Angelon:BAAANQADCgQIBgAAAA==.Antilles:BAAANQADCgIIBAAAAA==.Anzurath:BAABNQAECn8uAAIKAAgKeQ/RmwBUAQAKAAgKeQ/RmwBUAQAAAA==.',
Ap='Apheron:BAABNQAECn8zAAINAAoKoSJ4AgDXAgANAAoKoSJ4AgDXAgAAAA==.Apollimy:BAAANQAECggIBgAAAA==.Applebow:BAABNQAECn8hAAIOAAcKhRLxRQD8AAAOAAcKhRLxRQD8AAAAAA==.Apples:BAAANQAECgcIDAAAAA==.',
Ar='Arathwr:BAAANQADCgcICAABNQAECgQICwACAAAAAA==.Ardalel:BAAANQADCgcICAAAAA==.Arknova:BAABNQAECn8rAAIKAAoKYhkNSQAbAgAKAAoKYhkNSQAbAgAAAA==.Arylin:BAAANQAECgIIAwAAAA==.',
As='Asheram:BAAANQADCgEIAQAAAA==.Ashkinassi:BAEANQADCgUIBwAAAA==.Asiain:BAAANQAECgUIBgABNQAFFAYICwADAO8MAA==.Asmin:BAAANQAECggICwAAAA==.Asnabel:BAABNQAECn8iAAIIAAcKrgi9WAD2AAAIAAcKrgi9WAD2AAAAAA==.',
At='Atsa:BAAANQADCgQIBAAAAA==.Atvar:BAAANQADCggICAAAAA==.',
Au='Aurelith:BAAANQAECgcICwAAAA==.Autumndeath:BAAANQAECgMIBQAAAA==.',
Av='Avinger:BAAANQADCgEIAQAAAA==.',
Ay='Ayden:BAABNQAECn8nAAMNAAgKoROeDgDPAQANAAgKoROeDgDPAQAPAAUKRwyMVACdAAAAAA==.',
Az='Azorain:BAAANQADCgQIBAAAAA==.Azrim:BAAANQADCgYIEQABNQAECgQICQACAAAAAA==.Azureis:BAAANQADCgcICQAAAA==.',
['Aì']='Aìry:BAAANQADCgEIAQAAAA==.',
Ba='Badman:BAAANQAECgcIBgABNQAECgoKMAABAJUUAA==.Balolz:BAAANQABCgYIEQAAAA==.',
Be='Belthar:BAABNQAECn8fAAIOAAkKnBRtTwC3AQAOAAkKnBRtTwC3AQAAAA==.Bendeye:BAAANQADCgcIEAAAAA==.',
Bl='Blee:BAAANQAECgMICwAAAA==.Bludleddr:BAAANQADCgEIAQAAAA==.Bluudclaaw:BAAANQADCgMIBAABNQAECggIDwACAAAAAA==.',
Bo='Boing:BAABNQAECn8fAAIHAAkKjxkCJgBcAgAHAAkKjxkCJgBcAgAAAA==.Bondad:BAAANQAECgYICQABNQAECgcICwACAAAAAA==.Boomhauer:BAABNQAECn8fAAIGAAcKwxiPgwBpAQAGAAcKwxiPgwBpAQAAAA==.',
Br='Braelia:BAABNQAECn8VAAIQAAcKHg6DaQBsAQAQAAcKHg6DaQBsAQAAAA==.Braetwo:BAAANQADCgEIAQABNQAECgcIFQAQAB4OAA==.Braughm:BAAANQADCgUJBQAAAA==.Braxius:BAAANQADCgMIAwABNQAECgkJPQARALkfAA==.Brettcooper:BAAANQABCgcIBwAAAA==.Breye:BAABNQAECn8VAAISAAgKdAW0pwBFAQASAAgKdAW0pwBFAQAAAA==.Brightstone:BAAANQAECgIIAgABNQAECgQICwACAAAAAA==.Brindria:BAAANQADCgQIBgAAAA==.Brood:BAABNQAECn8WAAQQAAYKXRJKfQAnAQAQAAUKfxFKfQAnAQAIAAQKtQw3bwCpAAAOAAEKLhXvwgBCAAABNQAECgcIEQACAAAAAA==.Brundles:BAABNQAECn82AAIKAAgK6ghmzwB8AQAKAAgK6ghmzwB8AQAAAA==.Brutallity:BAAANQADCgEIAQAAAA==.',
Bu='Bubblepopper:BAABNQAECn8hAAMJAAgK0h1BVgAgAgAJAAgK0h1BVgAgAgAEAAUKpQwJLgDdAAAAAA==.Bunky:BAABNQAECn8gAAITAAgKegTYHAANAQATAAgKegTYHAANAQAAAA==.',
Ca='Cailaranel:BAABNQAECn8kAAIUAAkKPgsXTQCAAQAUAAkKPgsXTQCAAQAAAA==.Calaul:BAABNQAECn8xAAMKAAkK9wymowDZAQAKAAgKvg6mowDZAQAVAAEKSwIeZgAaAAAAAA==.Calenbraga:BAABNQAECn8mAAMMAAgKUBqPCwDMAQAMAAgKUBqPCwDMAQAWAAEKAACvlAAAAAAAAA==.Calisim:BAAANQAECgMICgAAAA==.Caloh:BAABNQAECn8YAAIXAAUKCRgkHgDVAAAXAAUKCRgkHgDVAAAAAA==.Cantholdagro:BAAANQAECgEIAQABNQAECggIGgAOADkSAA==.Cassamaria:BAABNQAECn8pAAIYAAkKGhHOBgAgAgAYAAkKGhHOBgAgAgAAAA==.Cataryn:BAABNQAECn82AAIGAAgK0R9bMwDSAgAGAAgK0R9bMwDSAgAAAA==.Catt:BAABNQAECn8vAAIBAAkKnhDlSgC1AQABAAkKnhDlSgC1AQAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECggINgAOAOoeAA==.',
Ce='Cellebur:BAAANQAECgQICwAAAA==.Ceta:BAABNQAECn8vAAIJAAkK1ha8SwDQAQAJAAkK1ha8SwDQAQAAAA==.',
Ch='Chalfus:BAABNQAECn89AAIRAAkKuR/eIQCdAgARAAkKuR/eIQCdAgAAAA==.Chaszmyr:BAAANQADCggIHwAAAA==.Chewwy:BAABNQAECn8tAAIOAAkKYBzLFgApAgAOAAkKYBzLFgApAgAAAA==.',
Ci='Cinamen:BAAANQAECgQIBAAAAA==.Cinderelah:BAAANQAECgMIAwAAAA==.Cizean:BAABNQAECn8YAAIZAAYKmgJeLgCMAAAZAAYKmgJeLgCMAAAAAA==.',
Cl='Clare:BAAANQADCgEIAQABNQAECggINgAGANEfAA==.Closetofsmut:BAAANQADCgcICAABNQAECgUIBQACAAAAAA==.',
Cr='Craivan:BAAANQADCgUICwAAAA==.Crendoal:BAAANQADCgQIBgABNQAECgoKNQAaAMEWAA==.Crilly:BAAANQAECgMJAwAAAA==.Crowley:BAAANQADCgQIBAAAAA==.Crumpler:BAABNQAECn8rAAIKAAkKhA/4gQCIAQAKAAkKhA/4gQCIAQAAAA==.Crüsnik:BAAANQADCgMIBAAAAA==.',
Cy='Cyroka:BAAANQAECgUIDgAAAA==.Cyrr:BAAANQAECgIIAgAAAA==.Cytroncutoff:BAAANQAECgQIBwAAAA==.',
Da='Dalastish:BAAANQADCggIDAAAAA==.Damia:BAABNQAECn8hAAMUAAcK0BX4IgCyAQAUAAcK0BX4IgCyAQAHAAMKnQx9fwC2AAAAAA==.Danobun:BAABNQAECn8vAAMSAAoK6R7+HwAMAwASAAoK6R7+HwAMAwAbAAEKLAcE6QAuAAAAAA==.Daring:BAAANQADCgEIAQAAAA==.Darsithis:BAABNQAECn8WAAIIAAYKXAVFawDxAAAIAAYKXAVFawDxAAAAAA==.',
De='Deadite:BAABNQAECn82AAIOAAgK6h45HgDAAgAOAAgK6h45HgDAAgAAAA==.Deadstealth:BAAANQADCgYIBgAAAA==.Delphirose:BAAANQADCgEIAQABNQAECgQICwACAAAAAA==.Delvarrieth:BAABNQAECn8YAAIVAAYKRQ1kNAC0AAAVAAYKRQ1kNAC0AAAAAA==.Demzy:BAAANQAECgUICwAAAA==.Denth:BAAANQAECgMIBQAAAA==.Dercuur:BAACNQAFFH8KAAISAAMKpgztDwDSAAASAAMKpgztDwDSAAA1AAQKfy8AAhIACgp7GoBCAGsCABIACgp7GoBCAGsCAAAA.Devira:BAAANQADCgYICQAAAA==.Dezardez:BAAANQAECgQIBAAAAA==.',
Di='Displacer:BAAANQADCggICAAAAA==.',
Do='Dondeestasto:BAAANQADCgMIBAAAAA==.Dotur:BAAANQADCgIIAgAAAA==.',
Dr='Dragonkiss:BAAANQADCgQIBwAAAA==.Drainmee:BAAANQAECgUIBgAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAABNQAECn8pAAIQAAoK4QuAPQDxAAAQAAoK4QuAPQDxAAAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAABNQAECn8VAAIKAAkKfxIgbAC5AQAKAAkKfxIgbAC5AQAAAA==.',
Dv='Dva:BAAANQADCggICAAAAA==.',
['Dá']='Dárkbeard:BAAANQAECgIIBAAAAA==.',
Ea='Eazzekin:BAAANQAECgYIBQAAAA==.',
Ek='Ekneirg:BAABNQAECn8xAAMKAAkKHBpVaADDAQAKAAkKKhlVaADDAQAVAAcKrheaKwCAAQABNQABCgEIAQACAAAAAA==.',
El='Elleneilah:BAAANQADCgUICQAAAA==.Elynth:BAABNQAECn83AAIcAAkK3xNPSQDDAQAcAAkK3xNPSQDDAQAAAA==.',
Em='Emmalily:BAAANQAECgMIBQAAAA==.',
En='Endlessyueh:BAAANQAECgQIBAAAAA==.',
Ex='Extragrippy:BAABNQAECn8aAAIOAAgKORLDVwCUAQAOAAgKORLDVwCUAQAAAA==.',
Ey='Eyris:BAAANQAECgEIAQAAAA==.',
Fa='Faiesong:BAAANQADCgEIAQAAAA==.Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAABNQAECn80AAIZAAoKPBUXBwAQAgAZAAoKPBUXBwAQAgAAAA==.Fangren:BAAANQAECgEIAQAAAA==.Farrseer:BAABNQAECn8WAAIPAAYKBAoUVgA1AQAPAAYKBAoUVgA1AQAAAA==.Fasthandslez:BAAANQAECgQIBgAAAA==.',
Fe='Felscythe:BAABNQAECn8YAAIdAAYKHQKMGgBuAAAdAAYKHQKMGgBuAAAAAA==.Felynn:BAAANQAECgQIBwAAAA==.',
Fi='Fierradin:BAAANQAECgQIAwABNQAECgoKJwAYAKIhAA==.Fierrastar:BAABNQAECn8nAAIYAAoKoiEfAwDrAgAYAAoKoiEfAwDrAgAAAA==.Finnius:BAAANQADCgMIBAAAAA==.Finshao:BAAANQAECgUIDwAAAA==.Fionn:BAAANQAECgMIAgABNQAECgQICwACAAAAAA==.',
Fl='Flemish:BAABNQAECn8pAAISAAoKWREiMADiAQASAAoKWREiMADiAQAAAA==.Flextame:BAAANQADCggIJAAAAA==.Flipalicious:BAABNQAECn9HAAMSAAoKoBUCKgACAgASAAoKoBUCKgACAgAbAAgKyA7ilgBOAQAAAA==.Flipanomicon:BAAANQADCgYIFgAAAA==.Flipkicks:BAAANQADCgYICgAAAA==.Flipmode:BAAANQADCgcIEgAAAA==.Flipnasty:BAAANQADCgYIDAAAAA==.Flipocalypse:BAAANQADCgYICgAAAA==.',
Fo='Foxwynn:BAAANQADCgEIAQAAAA==.',
Fr='Freyalise:BAABNQAECn8hAAMEAAgKGRouMACiAQAEAAYKqRMuMACiAQAJAAYKZgIi0AC0AAAAAA==.Freyjah:BAAANQADCgUIBgAAAA==.Frostycarbon:BAAANQADCgYICwAAAA==.',
Fu='Fuchsía:BAAANQADCgEIAQABNQAECgoKQgAbAG4TAA==.',
Fy='Fya:BAAANQADCgEIAQAAAA==.',
Ga='Gaia:BAABNQAECn8eAAIGAAcKkQrmtgAAAQAGAAcKkQrmtgAAAQAAAA==.Gallimaufrey:BAAANQAECgUIBwAAAA==.Garodan:BAAANQADCgcIDgAAAA==.',
Ge='Gerbo:BAABNQAECn84AAIRAAoKPQq+fACCAQARAAoKPQq+fACCAQAAAA==.',
Gi='Gianavel:BAABNQAECn8wAAIaAAkK4QqCIwBGAQAaAAkK4QqCIwBGAQAAAA==.Ginodh:BAAANQAECgQIBgABNQAECgoKFQAZANUNAA==.Ginomage:BAABNQAECn8VAAMZAAoK1Q0NCgDAAQAZAAoK1Q0NCgDAAQARAAUKSAkKagHlAAAAAA==.Ginopally:BAAANQADCgMIAwABNQAECgoKFQAZANUNAA==.Ginoshaman:BAAANQADCgUIBwABNQAECgoKFQAZANUNAA==.Ginovoker:BAAANQADCgYICQABNQAECgoKFQAZANUNAA==.Gizelli:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.',
Gr='Grilled:BAAANQADCgYIDQAAAA==.Grimoak:BAAANQAECgIIAwAAAA==.Gronke:BAAANQAECgQIAwABNQABCgEIAQACAAAAAA==.Grubetsella:BAABNQAECn81AAQaAAoKwRZJHwBsAQAaAAgKwBVJHwBsAQAeAAgKGRFqHAAMAQAdAAUKnBFeFQCnAAAAAA==.Grugachur:BAABNQAECn8XAAIfAAcKQR2HCQDpAQAfAAcKQR2HCQDpAQAAAA==.',
Gu='Gustice:BAAANQADCgIJAgAAAA==.',
Gw='Gwenwyfar:BAAANQAECggICAAAAA==.',
Gy='Gyda:BAAANQAECgEIAwAAAA==.',
Ha='Hadooken:BAAANQADCgEIAQAAAA==.Hangi:BAAANQADCgEIAQABNQAECgcICwACAAAAAA==.Hanoumatoi:BAAANQAECgYIDAAAAA==.Haralambos:BAAANQAECgQICwAAAA==.Harlar:BAAANQADCgYIDwAAAA==.Hasun:BAABNQAECn8fAAIKAAoK8R26IwCuAgAKAAoK8R26IwCuAgABNQAECgoKLwASAOkeAA==.',
He='Hehasnoname:BAAANQADCgYICwAAAA==.Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQAECgUIDAAAAA==.',
Ho='Hordkilla:BAAANQAECgUIEQAAAA==.Hottdealer:BAAANQADCgEIAQAAAA==.Hownowbrncw:BAABNQAECn8bAAIKAAgK8BLg1QBwAQAKAAgK8BLg1QBwAQAAAA==.',
Hy='Hyce:BAABNQAECn8yAAQPAAkKrxPCKgB6AQAgAAgKlRPRKAD9AQAPAAgKwQ3CKgB6AQANAAMK/hiWHQDmAAAAAA==.Hymno:BAAANQADCgYICQAAAA==.',
Ih='Ihavenoname:BAAANQADCgYJCwAAAA==.',
Il='Illusionous:BAAANQAECgMIAwAAAA==.',
In='Insoniacyun:BAAANQAECgQIBAAAAA==.',
Is='Iselian:BAAANQAECggIIQAAAQ==.Istrix:BAAANQADCgUJBQAAAA==.',
Ja='Jadefeather:BAAANQAECggIEgAAAA==.',
Jb='Jbelbueno:BAAANQAECgIIAgAAAA==.Jblockiv:BAAANQAECgMIAwAAAA==.Jbprimero:BAAANQAECgUIBQAAAA==.Jbshami:BAABNQAECn8mAAIbAAoKTBt3RQBLAgAbAAoKTBt3RQBLAgAAAA==.',
Je='Jeman:BAAANQABCggICAAAAA==.Jenaelle:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAABNQAECn8vAAIRAAgKJwMWxwDwAAARAAgKJwMWxwDwAAAAAA==.Jetfires:BAABNQAECn9JAAIGAAoKax7NIQCQAgAGAAoKax7NIQCQAgAAAA==.',
Ji='Jinger:BAABNQAECn8dAAIaAAgKcAVqMADiAAAaAAgKcAVqMADiAAAAAA==.Jinnwoo:BAAANQADCgUIBwAAAA==.',
Jo='Jonn:BAAANQAECgMIBAAAAA==.Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQAECgEIAgAAAA==.',
Ju='Juggernacht:BAAANQAECgEIAgABNQAECgkJJAAJALgZAA==.',
Ka='Kaedren:BAAANQADCgcIEgAAAA==.Kaelorien:BAABNQAECn8fAAIeAAgKTwwxGgAoAQAeAAgKTwwxGgAoAQAAAA==.Kaitja:BAAANQADCgIIAgAAAA==.Kalazaad:BAABNQAECn8uAAIVAAoKEAmtHgBDAQAVAAoKEAmtHgBDAQAAAA==.Kaldevayn:BAAANQAECggIDgAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalrow:BAABNQAECn8oAAMgAAkKpQ2EHQCDAQAgAAkKpQ2EHQCDAQAPAAEKAABVnwAgAAAAAA==.Kalto:BAAANQAECgIIBQAAAA==.Kalyna:BAAANQAECgUIBgAAAA==.Kardanika:BAAANQAECgQIBAAAAA==.Kardanis:BAABNQAECn82AAIbAAgKMCBvIgB+AgAbAAgKMCBvIgB+AgAAAA==.Kashe:BAAANQAECgQICwAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAABNQAECn8jAAIZAAgKpBU5CgAoAgAZAAgKpBU5CgAoAgAAAA==.Katavia:BAABNQAECn82AAIbAAgKzA8oXAByAQAbAAgKzA8oXAByAQAAAA==.Kathii:BAAANQAECgUIDgAAAA==.Katrazath:BAABNQAECn8eAAIhAAYKTwfhJQAJAQAhAAYKTwfhJQAJAQAAAA==.Kaydencia:BAAANQADCgEIAQAAAA==.',
Ke='Kelmmers:BAAANQAECggIBgAAAA==.Kelân:BAAANQAECgIIAgAAAA==.Keyallandron:BAABNQAECn8WAAIGAAUKOgba3QC0AAAGAAUKOgba3QC0AAAAAA==.Keywi:BAAANQAECgcICQAAAA==.',
Kh='Khaleesie:BAAANQAECgEIAgAAAA==.Khiana:BAAANQADCgIIBAABNQAECggINgAGANEfAA==.Khrin:BAAANQADCgYIFgAAAA==.',
Ki='Kiddow:BAAANQAECgQIDQAAAA==.Kierea:BAAANQADCgcIEgAAAA==.Kiiarah:BAAANQAECgcIEAAAAA==.Killrah:BAAANQADCgQIBAAAAA==.Kilrah:BAAANQADCggIEAAAAA==.Kilriella:BAAANQADCgYIBwAAAA==.Kitamii:BAAANQAECgYIDQAAAA==.Kivrin:BAABNQAECn8aAAIEAAYKYAUTOgCYAAAEAAYKYAUTOgCYAAAAAA==.Kiára:BAAANQADCggIDQAAAA==.',
Ko='Kokujin:BAABNQAECn8rAAISAAgKSBSVfQCrAQASAAgKSBSVfQCrAQAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAABNQAECn8pAAIGAAoKciDEHACpAgAGAAoKciDEHACpAgAAAA==.',
Ku='Kurumi:BAAANQAECgEIAQAAAA==.',
Kw='Kwo:BAABNQAECn8cAAIdAAgKGAY0EgDOAAAdAAgKGAY0EgDOAAAAAA==.',
Ky='Kymma:BAABNQAECn8lAAIKAAgKnAnKsgArAQAKAAgKnAnKsgArAQAAAA==.',
La='Laviz:BAAANQADCgYIBwABNQAECgoKLwASAOkeAA==.Laz:BAAANQADCgUICgAAAA==.Lazengann:BAABNQAECn8uAAMgAAoKwRxYFQC6AgAgAAkKmx5YFQC6AgAPAAIKyQ/YdAA0AAAAAA==.',
Le='Leafbane:BAABNQAECn9LAAQIAAkKDRr9IwBxAgAIAAkKDRr9IwBxAgAQAAMKTxBhSAC+AAAOAAEK4BbNwQBFAAAAAA==.Legevia:BAAANQAECgUIDgAAAA==.Leiris:BAABNQAECn8vAAMKAAkKIwzRlQBgAQAKAAkKIwzRlQBgAQABAAEKoQAbOwEZAAAAAA==.Lejusticier:BAAANQADCggIDAAAAA==.Leonaa:BAAANQADCgcIFQAAAA==.Letifer:BAAANQADCgEIAQAAAA==.Leucetios:BAAANQAECgUIDAAAAA==.',
Li='Liarace:BAAANQAECggIEAAAAA==.Lightbeard:BAAANQAECgUIDwAAAA==.Lightforge:BAABNQAECn8VAAIKAAkKoBRskwD9AQAKAAkKoBRskwD9AQAAAA==.Lionessi:BAAANQADCgcIBwAAAA==.Lithika:BAAANQADCgYIBgAAAA==.',
Lo='Lorredain:BAAANQADCgcIDgAAAA==.Lothaire:BAAANQAECgMIAwAAAA==.Lothwen:BAAANQAECgMIBQAAAA==.Louisachan:BAAANQAECgIIAgAAAA==.',
Lu='Lucamar:BAAANQADCgQIBAAAAA==.Luxinine:BAABNQAECn83AAIEAAkKMR1tFADBAgAEAAkKMR1tFADBAgAAAA==.',
Ma='Madhawi:BAAANQAECgEIBAAAAA==.Magamon:BAABNQAECn82AAIRAAgK2RTFgwByAQARAAgK2RTFgwByAQAAAA==.Magnix:BAAANQADCgQIBAABNQAECgUIDwACAAAAAA==.Malfuriia:BAAANQAECgUIEQAAAA==.Mamboke:BAABNQAECn8mAAMGAAkKxQ7LYQC8AQAGAAkKxQ7LYQC8AQAiAAQKVgKIaQCHAAAAAA==.Margerdria:BAAANQADCgcIFAAAAA==.Mauugrim:BAABNQAECn8XAAMQAAcKAwffQgDWAAAQAAcK5wbfQgDWAAAIAAQK9gYpggCkAAAAAA==.Maxowen:BAABNQAECn8YAAIKAAYKsRQn0wD0AAAKAAYKsRQn0wD0AAAAAA==.Maxxramas:BAAANQADCgcICgAAAA==.',
Me='Mearadan:BAABNQAECn8lAAIbAAoKJAl7kgBaAQAbAAoKJAl7kgBaAQAAAA==.Meatsweats:BAAANQAECgYIBgAAAA==.Megg:BAAANQAECgUIBgAAAA==.Mekh:BAABNQAECn8aAAMhAAcKVh0CDQBKAQAhAAYKgBwCDQBKAQAjAAEK0x4+MABNAAAAAA==.Mel:BAAANQADCgcIHAAAAA==.Melanara:BAABNQAECn8rAAIZAAoK7w5VDgDGAQAZAAoK7w5VDgDGAQAAAA==.Melstrom:BAAANQAECgMIBQAAAA==.Meticuluslyn:BAAANQAECgUIBQAAAA==.',
Mi='Milkmaiden:BAAANQADCgQJCgAAAA==.Milkthisbull:BAAANQADCgMIBAAAAA==.Mixler:BAABNQAECn8ZAAIRAAgKwQaurAAgAQARAAgKwQaurAAgAQAAAA==.',
Mm='Mmeow:BAAANQADCgYIEAABNQAECgkJKQAGAH4dAA==.',
Mo='Moirine:BAABNQAECn8YAAMFAAYK7BSvBQBpAQAFAAYK7BSvBQBpAQAEAAQKlR2CRwABAQAAAA==.Moonflowers:BAAANQAECggICQAAAA==.',
Mu='Muffiñs:BAAANQADCgEIAwAAAA==.Murdrmitts:BAABNQAECn8WAAIMAAUKcwjTJQDfAAAMAAUKcwjTJQDfAAAAAA==.Mustikka:BAAANQAECgQICQAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Myuriyanka:BAABNQAECn8+AAISAAoKExDUNQDGAQASAAoKExDUNQDGAQAAAA==.',
['Mæ']='Mælstrôm:BAAANQADCgEIAQAAAA==.',
Na='Naahommii:BAAANQADCgUIBgAAAA==.Nachtamus:BAAANQAECgIIAQABNQAECgkJJAAJALgZAA==.Nachtkampfer:BAAANQAECgEIAgABNQAECgkJJAAJALgZAA==.Nachtkreiger:BAAANQABCgEIAQABNQAECgkJJAAJALgZAA==.Nachtpranke:BAAANQAECgIIBAABNQAECgkJJAAJALgZAA==.Nachtteufel:BAAANQAECgEIAgABNQAECgkJJAAJALgZAA==.Naeri:BAABNQAECn8hAAILAAcKRhIUJgB2AQALAAcKRhIUJgB2AQAAAA==.Nagualli:BAAANQAECgQIBQAAAA==.Naieve:BAABNQAECn8pAAIWAAoKIxJQQAD5AQAWAAoKIxJQQAD5AQAAAA==.Nastii:BAAANQADCgEIAQAAAA==.Nastychungus:BAABNQAECn8sAAMSAAkKLCKVGAA1AwASAAkKLCKVGAA1AwAbAAUK6AM60wDAAAAAAA==.Navira:BAAANQADCggIHwAAAA==.',
Ne='Negargra:BAABNQAECn8iAAIcAAoKMgpiVwCUAQAcAAoKMgpiVwCUAQAAAA==.Nekoda:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Nephadin:BAAANQAECgEIAQAAAA==.Nephilim:BAAANQAECgYIBQAAAA==.Neyvin:BAAANQADCggICAAAAA==.',
Ni='Niduun:BAAANQABCggICAAAAA==.Nightfend:BAAANQADCgcICwAAAA==.Nighttiger:BAAANQAECgQICgAAAA==.Nikooli:BAABNQAECn8XAAMPAAYKlA0jUQBSAQAPAAYKlA0jUQBSAQANAAEKygU1LgAhAAAAAA==.',
No='Noopsie:BAABNQAECn8gAAILAAYKfRVNJgBzAQALAAYKfRVNJgBzAQAAAA==.Nooters:BAABNQAECn84AAIIAAoK8iMMBwBzAwAIAAoK8iMMBwBzAwABNQAFFAcIGwAhADciAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAABNQAECn8kAAMJAAkKth2GKQBwAgAJAAkKth2GKQBwAgAEAAcKVReOGQCUAQAAAA==.',
Nu='Nunavutt:BAAANQADCgUIBgAAAA==.',
Ny='Nyteweaver:BAABNQAECn8WAAIKAAYKARI+6ABLAQAKAAYKARI+6ABLAQAAAA==.',
Od='Oderica:BAAANQAECggIDwAAAA==.Odurn:BAAANQADCgYIBgAAAA==.',
Og='Ogafor:BAAANQABCgIIAgAAAA==.Ogayac:BAAANQAECgEIAQAAAA==.',
Oh='Ohminous:BAAANQAECggICAAAAA==.',
Or='Oranash:BAAANQADCgMIAwAAAA==.Orici:BAAANQAECgIIAgABNQAECgIIAwACAAAAAA==.Ornir:BAAANQADCgMIAwAAAA==.Orongosh:BAAANQADCgYIBgAAAA==.',
Os='Oscarmikey:BAABNQAECn8zAAMWAAoKPBVqNgA4AgAWAAoKPBVqNgA4AgALAAcKuxP2KABdAQAAAA==.Oshu:BAAANQADCgcIBwAAAA==.',
Ot='Ottoshot:BAABNQAECn8YAAIGAAYKnQ17vAD1AAAGAAYKnQ17vAD1AAAAAA==.Otum:BAAANQAECgMICAAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
Ox='Oxmantle:BAAANQAECgMIAgAAAA==.',
['Oö']='Oöps:BAABNQAECn8bAAILAAYKrwcWSwDiAAALAAYKrwcWSwDiAAAAAA==.',
Pa='Paksen:BAAANQAECgYIBgAAAA==.Panamone:BAAANQAECgYIBQAAAA==.Pandamaster:BAAANQAECggIEAAAAA==.Paulee:BAAANQAECgEIAQAAAA==.',
Pe='Pendragon:BAAANQADCgQIBQAAAA==.Pesch:BAAANQAECggICAAAAA==.',
Ph='Phylah:BAABNQAECn8WAAMbAAYKKBAWfwAEAQAbAAYKKBAWfwAEAQASAAEKAABvUQElAAAAAA==.',
Pi='Pixystain:BAAANQADCgEIAQAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Porterhouze:BAAANQADCgEIAQABNQAECgcIJAAkAIwEAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.Prophetofham:BAAANQADCgYIBwAAAA==.',
Pu='Puchi:BAACNQAFFH8XAAIeAAcK6xT5AwCpAQAeAAcK6xT5AwCpAQA1AAQKfzwAAh4ACgohIokEAF0DAB4ACgohIokEAF0DAAAA.',
Py='Pyrocles:BAAANQABCgQICQAAAA==.',
Qa='Qadhiræ:BAAANQAECgEIAgABNQADCgYIDAACAAAAAA==.',
['Qæ']='Qædhira:BAAANQADCgYIDAAAAA==.',
Ra='Raez:BAAANQAECggIEgAAAA==.Ragnerock:BAAANQAECgMIBQAAAA==.Raynecira:BAABNQAECn8aAAIGAAcKGQw2pgAhAQAGAAcKGQw2pgAhAQAAAA==.',
Re='Reihino:BAAANQAECgYIBgAAAA==.Remixidora:BAAANQAECgQJCAABNQAFFAUIBgARAMAeAA==.Reyrocko:BAAANQAECgEIAQAAAA==.Rezdh:BAAANQAECgYIDQABNQAFFAIIBQARADwTAA==.Rezmage:BAACNQAFFH8FAAMRAAIKPBMQPQBSAAARAAEKhhYQPQBSAAAZAAEK8g/0EQBEAAA1AAQKfxoABBEACgpLG9B3AI0BABEACAqmGNB3AI0BABkABArmEoYfAKoAACUAAQqtEiIKADcAAAAA.Reznal:BAAANQAECgMIAwABNQAFFAIIBQARADwTAA==.Rezvoker:BAAANQADCgUJCgABNQAFFAIIBQARADwTAA==.',
Rh='Rhage:BAAANQADCgcIGgAAAA==.Rhoaias:BAAANQAECgEIAQAAAA==.Rhunyaye:BAAANQADCgYIDgAAAA==.',
Ri='Rickness:BAAANQAECgIIBAAAAA==.Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokform:BAAANQAECgcIBgAAAA==.Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQAECgEIAQAAAA==.Rottingturky:BAAANQAECggIEgAAAA==.Roxane:BAABNQAECn8gAAIWAAgKaAe0PgD9AAAWAAgKaAe0PgD9AAAAAA==.',
Ru='Rubyace:BAAANQAECgQICwAAAA==.Runningelk:BAABNQAECn8pAAImAAkKBhwwEABeAgAmAAkKBhwwEABeAgAAAA==.Runscapemain:BAABNQAECn8lAAIKAAgK1AlktwCvAQAKAAgK1AlktwCvAQAAAA==.',
Ry='Ryeti:BAAANQADCggINAAAAA==.Ryuzu:BAAANQADCgYIBgAAAA==.Ryydia:BAAANQADCgMIBQAAAA==.',
Sa='Sableanne:BAAANQAECgIIAQAAAA==.Sahalia:BAAANQADCgUIDwABNQAECgIIBAACAAAAAA==.Saintulrick:BAAANQAECgUIBQAAAA==.Sajuice:BAABNQAECn8cAAMGAAkKFRsgSwCMAgAGAAkKFRsgSwCMAgAiAAQKKRRDUQDlAAAAAA==.Salow:BAAANQABCgYICgAAAA==.Sanitas:BAABNQAECn8vAAMJAAoKChB1WgASAgAJAAoKChB1WgASAgAEAAQK3QJ5RQBmAAAAAA==.Sanivar:BAAANQADCgYIBgABNQAECgoKIwAFAE4ZAA==.',
Se='Seeyen:BAACNQAFFH8KAAIGAAQKDhKeEwAsAQAGAAQKDhKeEwAsAQA1AAQKfz8AAgYACgoqI/MOAGoDAAYACgoqI/MOAGoDAAAA.Sej:BAAANQABCgIIAgAAAA==.Seraphon:BAAANQADCggIJAAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAACAAAAAA==.Serenityhate:BAAANQAECgQIBAAAAA==.',
Sh='Shaaydo:BAAANQADCgQIBQAAAA==.Shaayllee:BAAANQAECgQIBQAAAA==.Shaaytheyha:BAABNQAECn8hAAIKAAcKfAfZ7ABCAQAKAAcKfAfZ7ABCAQAAAA==.Shaggyp:BAACNQAFFH8NAAIJAAQKVQ75FQAZAQAJAAQKVQ75FQAZAQA1AAQKfyAAAgkACgpuD9RGAOQBAAkACgpuD9RGAOQBAAAA.Shamump:BAAANQADCgcIBwAAAA==.Sharington:BAAANQADCgUIBQAAAA==.Sharyl:BAAANQADCgEIBAAAAA==.Shehasnoname:BAAANQADCgYIGwAAAA==.Shehulk:BAAANQAECgUICwAAAA==.Shingo:BAAANQADCgcIBwABNQAECgoKOwAIAHgfAA==.Ships:BAABNQAECn8eAAIjAAoKChU0FwBFAgAjAAoKChU0FwBFAgAAAA==.Sholo:BAAANQADCgEIAQAAAA==.',
Si='Silf:BAAANQAECgEIAQAAAA==.Silverapples:BAAANQADCgIIAgAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skrektwo:BAABNQAECn8oAAMbAAgKlBSqXABxAQAbAAgKlBSqXABxAQASAAUK4gVs2wDeAAAAAA==.',
Sm='Smackdogg:BAACNQAFFH8MAAIWAAUKQSDQDQCNAQAWAAUKQSDQDQCNAQA1AAQKfx0AAhYACQrKJAEUACcDABYACQrKJAEUACcDAAAA.',
So='Solarspark:BAAANQAECgYIEQAAAA==.Sondaladan:BAAANQADCggIGgAAAA==.Sonomonom:BAAANQADCggIEQAAAA==.Sorvina:BAABNQAECn86AAIcAAoKZw4mSQDDAQAcAAoKZw4mSQDDAQAAAA==.Soulflame:BAABNQAECn87AAIZAAkKgQojEAClAQAZAAkKgQojEAClAQAAAA==.Soulkings:BAAANQADCggIGgAAAA==.',
Sp='Spriggs:BAAANQADCgUIBAAAAA==.',
St='Starpath:BAAANQAECgMIAwABNQAECgcICwACAAAAAA==.Strangr:BAAANQADCggIDAABNQAECgoKQgAaAJsfAA==.Stregnor:BAABNQAECn8gAAIGAAgKGxBWdACNAQAGAAgKGxBWdACNAQAAAA==.Styggi:BAAANQADCggICQAAAA==.Stygii:BAAANQADCgEIAQABNQADCggICQACAAAAAA==.Stygy:BAAANQADCgcICAABNQADCggICQACAAAAAA==.',
Su='Sumyunguy:BAABNQAECn8aAAIaAAcKwBa8LwCZAQAaAAcKwBa8LwCZAQAAAA==.',
Sy='Syllenne:BAAANQABCgMIAwAAAA==.Sylunia:BAABNQAECn8YAAIZAAcK2QMeHwDxAAAZAAcK2QMeHwDxAAAAAA==.Sylváñás:BAAANQADCgEIAQAAAA==.Syrintha:BAAANQADCgYIDQAAAA==.',
Ta='Tachi:BAAANQAECgUIEAABNQAECgkJHgAIAMwRAA==.Tachie:BAABNQAECn8oAAIhAAgKPRiXCgCHAQAhAAgKPRiXCgCHAQABNQAECgkJHgAIAMwRAA==.Tairi:BAAANQABCgMIBQAAAA==.Talonclaw:BAAANQABCgQICQAAAA==.Talön:BAEANQAECgUJBQAAAA==.Tarvah:BAAANQADCgYIBgAAAA==.',
Te='Teranox:BAAANQADCgEIAQAAAA==.Tezzerae:BAAANQAECgUIDQAAAA==.',
Th='Thaesan:BAAANQAECgUIBAAAAA==.Theistica:BAABNQAECn8cAAIVAAcKjAvYLgDSAAAVAAcKjAvYLgDSAAAAAA==.Theomir:BAAANQAECgIIAQAAAA==.Therin:BAABNQAECn8wAAMYAAoKFA8TBgCoAQAYAAoKFA8TBgCoAQAiAAcKBwYORAA4AQAAAA==.Thodi:BAAANQADCgEIAQAAAA==.',
Ti='Tillymonick:BAAANQAECgMIBAAAAA==.',
To='Todes:BAAANQADCgIIAgAAAA==.Tongshi:BAAANQADCgEIAQAAAA==.Toofast:BAABNQAECn8wAAIbAAgKPCEgFgDaAgAbAAgKPCEgFgDaAgAAAA==.Toofurrious:BAAANQADCgQIBgAAAA==.Toolotems:BAAANQAECgUIBwAAAA==.Topswimmer:BAAANQADCgEIAgAAAA==.',
Tr='Trifus:BAAANQAECgYIBgAAAA==.',
Tu='Tulao:BAABNQAECn8aAAIRAAkKZhHXdwCNAQARAAkKZhHXdwCNAQABNQAECgoKLwASAOkeAA==.',
Ty='Tylae:BAAANQADCgQICAAAAA==.',
Ut='Utheli:BAABNQAECn83AAIKAAoKwR7cLgB8AgAKAAoKwR7cLgB8AgAAAA==.',
Va='Vaevictis:BAAANQAECgEIAQABNQAECggIIQAEABkaAA==.Vaeyethir:BAAANQADCgEIAgAAAA==.Vaildora:BAABNQAECn8eAAMIAAkKzBGWJAD1AQAIAAkKqhGWJAD1AQAOAAQKuA41ZQCQAAAAAA==.Valdra:BAABNQAECn8pAAIXAAkKqBbeDQCfAQAXAAkKqBbeDQCfAQAAAA==.Valkyl:BAAANQADCgMIBQAAAA==.Valkyll:BAAANQADCgIIBAAAAA==.Valkylpal:BAAANQADCgEIAQAAAA==.Valord:BAAANQADCgcIBwAAAA==.Vane:BAAANQADCgEIAgAAAA==.Vanillacain:BAAANQADCgMIBAAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgcIHQAAAA==.',
Vl='Vlonet:BAABNQAECn85AAMgAAkKYRXnFQDaAQAgAAkKYRXnFQDaAQAPAAEK7QholwAuAAAAAA==.',
Vn='Vnasty:BAAANQAECgQIBwABNQAECgkJLAASACwiAA==.',
Vo='Vokola:BAAANQAECgQIBgABNQAECgkJHgAIAMwRAA==.',
Wa='Warthexn:BAAANQAECgQIBAAAAA==.',
We='Wehadnoname:BAAANQADCgEIAQAAAA==.Weshalas:BAAANQAECgMIAwAAAA==.',
Wh='Whelp:BAAANQAECgIIAgAAAA==.',
Wi='Wilken:BAAANQAECgYIDQAAAA==.Wilohart:BAAANQABCgMIAwAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwACAAAAAA==.Wiva:BAAANQAECgQIBgAAAA==.',
Wo='Wolfsokol:BAABNQAECn8aAAQOAAoKwxitQwDsAQAOAAcK0R6tQwDsAQAIAAMKiwXefQB9AAAQAAEKAADrlAAAAAABNQAFFAgIEgAjAEAcAA==.',
Wr='Wreckoner:BAABNQAECn82AAIVAAgK8xL6GgBjAQAVAAgK8xL6GgBjAQAAAA==.',
Xa='Xannah:BAAANQAECgMIAgAAAA==.Xavencia:BAAANQADCgYIDAAAAA==.',
Xi='Xinthos:BAAANQAECgIIAgAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Za='Zaderan:BAAANQADCgYIFgAAAA==.Zakainu:BAABNQAECn8cAAITAAkKxhQ0GwCxAQATAAkKxhQ0GwCxAQAAAA==.Zallister:BAAANQADCggIKAAAAA==.Zansarutobi:BAAANQADCgEIAQAAAA==.Zapan:BAAANQADCgEIAQAAAA==.Zarathoszan:BAABNQAECn8pAAIGAAgKKAkfkQDnAQAGAAgKKAkfkQDnAQAAAA==.Zarkra:BAAANQAECgYIBwABNQAECgkJKQAmAAYcAA==.',
Ze='Zedator:BAABNQAECn8iAAIYAAgKORiQBQBhAgAYAAgKORiQBQBhAgAAAA==.Zedraikis:BAAANQADCgEIAQABNQADCggIEAACAAAAAA==.Zelgaddis:BAABNQAECn8rAAIbAAoKeRK/agDLAQAbAAoKeRK/agDLAQAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zh='Zhansaya:BAAANQAECgIIBAAAAA==.',
Zr='Zriana:BAAANQAECgMICgAAAA==.',
Zs='Zsarilya:BAABNQAECn8hAAMJAAcKLAJtpgC4AAAJAAcKLAJtpgC4AAAEAAEKAACAbgAAAAAAAA==.',
Zu='Zurgen:BAABNQAECn84AAIcAAkKAhvkOgD2AQAcAAkKAhvkOgD2AQAAAA==.',
['Àn']='Àndrol:BAABNQAECn8jAAIRAAkKaA0GhABxAQARAAkKaA0GhABxAQABNQAFFAYIEgAgACURAA==.',
['Êc']='Êclipse:BAEBNQAECn89AAILAAoKtR1DCQAEAwALAAoKtR1DCQAEAwAAAA==.',
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
