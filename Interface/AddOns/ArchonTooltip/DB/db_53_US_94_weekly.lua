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

local lookup = {'Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Warrior-Arms','Priest-Shadow','Priest-Discipline','Hunter-BeastMastery','Rogue-Assassination','DeathKnight-Frost','Priest-Holy','Druid-Restoration','Druid-Feral','DemonHunter-Vengeance','DeathKnight-Blood','Rogue-Subtlety','DemonHunter-Havoc','DeathKnight-Unholy','Mage-Arcane','Shaman-Elemental','Shaman-Enhancement','Paladin-Protection','Druid-Balance','Warrior-Protection','Hunter-Survival','Mage-Frost','Monk-Windwalker','Shaman-Restoration','Warlock-Demonology','Monk-Brewmaster','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Devourer','Evoker-Devastation','Hunter-Marksmanship','Evoker-Preservation','Warlock-Destruction','Mage-Fire','Druid-Guardian',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aarchon:BAABNQAECn9GAAIBAAoKbB6zGQDqAgABAAoKbB6zGQDqAgAAAA==.',
Ad='Aduin:BAAANQAECggIDAAAAA==.',
Ae='Aedarelyn:BAABNQAECn8YAAICAAcK5w4w2QAoAQACAAcK5w4w2QAoAQAAAA==.Aellita:BAAANQAECgQICwAAAA==.Aenoryae:BAAANQADCgYIBgABNQADCgYICwADAAAAAA==.Aeschylus:BAAANQAECgcICwAAAA==.Aeson:BAAANQAECgIIAgAAAA==.',
Af='Afkinlife:BAAANQADCgYJBwAAAA==.',
Ai='Aias:BAAANQADCgcIBwAAAA==.',
Ak='Akky:BAABNQAECn8oAAIEAAoKCxc0iwAAAgAEAAoKCxc0iwAAAgAAAA==.Aksafiya:BAABNQAECn9xAAMFAAoKVxJzFgD7AQAFAAoKVxJzFgD7AQAGAAEK5QGHMQAgAAAAAA==.',
Al='Alal:BAAANQADCgYIFQAAAA==.Alandras:BAAANQAECggICAAAAA==.Alaras:BAACNQAFFH8RAAIFAAcKmAqeBQBwAQAFAAcKmAqeBQBwAQA1AAQKfyIAAgUACgrcFSIVALgCAAUACgrcFSIVALgCAAAA.Alissia:BAAANQAECgIIAgAAAA==.Allaras:BAAANQADCgYIDAAAAA==.Allistaris:BAABNQAECn8sAAIHAAoKUhdVZwBFAgAHAAoKUhdVZwBFAgAAAA==.Allrianne:BAAANQAECgEIAQAAAA==.Alluriela:BAAANQADCgIIAwAAAA==.Allyriae:BAAANQAECggIDwAAAA==.Alphard:BAAANQAECgUIDAABNQAECgkJHwAIAI8ZAA==.Alphá:BAABNQAECn8gAAIJAAkKMwtaSgCRAQAJAAkKMwtaSgCRAQAAAA==.Althoraty:BAABNQAECn8rAAIKAAoKGBVqUQD0AQAKAAoKGBVqUQD0AQAAAA==.',
Am='Amberlilly:BAABNQAECn8pAAICAAoK0Aj2pgCBAQACAAoK0Aj2pgCBAQAAAA==.',
An='Andoros:BAABNQAECn9AAAMLAAoKRyO3BgB2AwALAAoKRyO3BgB2AwAMAAEK3wWWWQAPAAAAAA==.Angelon:BAAANQADCgQIBgAAAA==.Antilles:BAAANQADCgIIAwAAAA==.Anzurath:BAABNQAECn9AAAICAAoKbQ4ZhADEAQACAAoKbQ4ZhADEAQAAAA==.',
Ap='Apheron:BAABNQAECn81AAINAAoKxSI8AwDSAgANAAoKxSI8AwDSAgAAAA==.Apollimy:BAAANQAECggIBgAAAA==.Applebow:BAABNQAECn8tAAIOAAgKyxJZQQA5AQAOAAgKyxJZQQA5AQAAAA==.Apples:BAAANQAECggIDwAAAA==.',
Ar='Arathwr:BAAANQADCgcIBwABNQAECgcIGAACAOcOAA==.Ardalel:BAAANQADCgcICAAAAA==.Arknova:BAABNQAECn84AAICAAoK+hruOQB/AgACAAoK+hruOQB/AgAAAA==.Arylin:BAAANQAECgIIAwAAAA==.',
As='Asheram:BAAANQADCgEIAQAAAA==.Ashkinassi:BAEANQADCgUIBgAAAA==.Asiain:BAAANQAECgUIBgABNQAFFAYICwAEAO8MAA==.Asmin:BAABNQAECn8cAAMPAAoKKhDaPgACAgAPAAoKKhDaPgACAgAIAAEKAAAyqQAqAAAAAA==.Asnabel:BAABNQAECn8sAAIJAAgK5wgzXAAmAQAJAAgK5wgzXAAmAQAAAA==.',
At='Atsa:BAAANQADCgQIBAAAAA==.Atvar:BAAANQADCggICAAAAA==.',
Au='Aurelith:BAAANQAECgcICwAAAA==.Autumndeath:BAAANQAECgMIBQAAAA==.',
Av='Avinger:BAAANQABCggIGQAAAA==.',
Ay='Ayden:BAABNQAECn8nAAMNAAgKoROeDgDPAQANAAgKoROeDgDPAQAQAAUKRwx1YgCbAAAAAA==.',
Az='Azorain:BAAANQADCgQIBAAAAA==.Azrim:BAAANQADCgYIDgABNQAECgYIEgADAAAAAA==.Azureis:BAAANQADCgcICAAAAA==.',
Ba='Badman:BAABNQAECn8VAAMNAAgKmQjAEwAQAQANAAgKmQjAEwAQAQAQAAQKBALYfQBCAAABNQAECgoKPQABAGkXAA==.Balolz:BAAANQABCgYIEQAAAA==.',
Be='Belthar:BAABNQAECn8jAAIOAAkKcRVtTwC3AQAOAAkKcRVtTwC3AQAAAA==.Bendeye:BAAANQADCgcIDwAAAA==.',
Bl='Blee:BAAANQAECgQIEwAAAA==.Bluudclaaw:BAAANQADCgMIAwABNQAECgcIEAADAAAAAA==.',
Bo='Boing:BAABNQAECn8fAAIIAAkKjxkCJgBcAgAIAAkKjxkCJgBcAgAAAA==.Bondad:BAAANQAECgYICQABNQAECgcICwADAAAAAA==.Boomhauer:BAABNQAECn8rAAIHAAgKuxh3ewDFAQAHAAgKuxh3ewDFAQAAAA==.',
Br='Braelia:BAABNQAECn8ZAAIRAAoKGQ6DaQBsAQARAAoKGQ6DaQBsAQAAAA==.Braetwo:BAAANQABCggIDwABNQAECgoKGQARABkOAA==.Braughm:BAAANQADCgUJBQAAAA==.Braxius:BAAANQADCgMIAwABNQAECgkJPwASALkfAA==.Brettcooper:BAAANQABCgcIBwAAAA==.Breye:BAABNQAECn8eAAITAAoKIgr4bwA5AQATAAoKIgr4bwA5AQAAAA==.Brightstone:BAAANQAECgMIAwABNQAECgcIGAACAOcOAA==.Brindria:BAAANQADCgYICAAAAA==.Brood:BAABNQAECn8YAAQRAAYKXRJKfQAnAQARAAUKfxFKfQAnAQAJAAQKtQxEcgDYAAAOAAEKLhXvwgBCAAABNQAECgcIEQADAAAAAA==.Brundles:BAABNQAECn9IAAICAAoKOgpAmACcAQACAAoKOgpAmACcAQAAAA==.',
Bu='Bubblepopper:BAABNQAECn8nAAMKAAgKER6AUAD3AQAKAAgKER6AUAD3AQAFAAYK2Q06LAAlAQAAAA==.Bunky:BAABNQAECn8uAAIUAAgK8AXEHwApAQAUAAgK8AXEHwApAQAAAA==.',
Ca='Cailaranel:BAABNQAECn8uAAIPAAoKlAsRUgC8AQAPAAoKlAsRUgC8AQAAAA==.Calaul:BAABNQAECn88AAMCAAoKaw2mowDZAQACAAkK5A6mowDZAQAVAAEKGgPScwAbAAAAAA==.Calenbraga:BAABNQAECn8+AAMMAAkKnRsCCgBAAgAMAAkKnRsCCgBAAgAWAAIKWQlnigA0AAAAAA==.Calisim:BAAANQAECgQIEgAAAA==.Caloh:BAABNQAECn8aAAIXAAcKEBfNHgAIAQAXAAcKEBfNHgAIAQAAAA==.Cantholdagro:BAAANQAECgEIAQABNQAECggIGgAOADkSAA==.Cassamaria:BAABNQAECn8sAAIYAAoKjxPCBAAvAgAYAAoKjxPCBAAvAgAAAA==.Cataryn:BAABNQAECn9IAAIHAAoKmR8JFgDwAgAHAAoKmR8JFgDwAgAAAA==.Catt:BAABNQAECn8vAAIBAAkKnhAgXgChAQABAAkKnhAgXgChAQAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECgoKSAAOAIchAA==.',
Ce='Cellebur:BAABNQAECn8ZAAIHAAYK/AMU+wC7AAAHAAYK/AMU+wC7AAAAAA==.Ceta:BAABNQAECn87AAIKAAoKfReFSQASAgAKAAoKfReFSQASAgAAAA==.',
Ch='Chalfus:BAABNQAECn8/AAISAAkKuR/wLQCIAgASAAkKuR/wLQCIAgAAAA==.Chaszmyr:BAAANQADCggIHQAAAA==.Chewwy:BAABNQAECn8yAAIOAAkKBiB9EgCAAgAOAAkKBiB9EgCAAgAAAA==.',
Ci='Cinamen:BAAANQAECgUIBgAAAA==.Cinderelah:BAAANQAECgQIBAAAAA==.Cizean:BAABNQAECn8kAAIZAAcKIgNeLgCMAAAZAAcKIgNeLgCMAAAAAA==.',
Cl='Clare:BAAANQABCgQIBAABNQAECgoKSAAHAJkfAA==.Closetofsmut:BAAANQADCgcIBwABNQAECgcIBwADAAAAAA==.',
Cr='Craivan:BAAANQADCgUICQAAAA==.Crendoal:BAAANQADCgQIBgABNQAECgoKRgAaALkaAA==.Crilly:BAAANQAECgMJAwAAAA==.Crowley:BAAANQADCgQIBAAAAA==.Crumpler:BAABNQAECn8xAAICAAkKrRBnmACcAQACAAkKrRBnmACcAQAAAA==.Crüsnik:BAAANQADCgMIAwAAAA==.',
Cy='Cyroka:BAABNQAECn8hAAIbAAcKlwmdjAAQAQAbAAcKlwmdjAAQAQAAAA==.Cyrr:BAAANQAECgIIAgAAAA==.Cytroncutoff:BAAANQAECgYIDAAAAA==.',
Da='Dalastish:BAAANQADCggIDAAAAA==.Damia:BAABNQAECn8tAAMPAAgKMhX4IgCyAQAPAAgKMhX4IgCyAQAIAAMKnQx9fwC2AAAAAA==.Danobun:BAABNQAECn82AAMTAAoK6R7+HwAMAwATAAoK6R7+HwAMAwAbAAEKLAel/wAuAAAAAA==.Daring:BAAANQADCgEIAQAAAA==.Darsithis:BAABNQAECn8dAAIJAAgKlgW/agDxAAAJAAgKlgW/agDxAAAAAA==.',
De='Deadite:BAABNQAECn9IAAIOAAoKhyGYBwAPAwAOAAoKhyGYBwAPAwAAAA==.Deadstealth:BAAANQADCgYIBgAAAA==.Delphirose:BAAANQABCggIDwABNQAECgcIGAACAOcOAA==.Delvarrieth:BAABNQAECn8kAAIVAAcKQg+yLAASAQAVAAcKQg+yLAASAQAAAA==.Demzy:BAABNQAECn8aAAMQAAkK9RcYHAAuAgAQAAkKXBYYHAAuAgANAAQK5BY/HQCmAAAAAA==.Denth:BAAANQAECgMIBQAAAA==.Dercuur:BAACNQAFFH8LAAITAAQKpgxQFADMAAATAAQKpgxQFADMAAA1AAQKfy8AAhMACgp7GoBCAGsCABMACgp7GoBCAGsCAAAA.Devira:BAAANQADCgYICQAAAA==.Dezardez:BAAANQAECgYIBwAAAA==.',
Di='Displacer:BAAANQADCggICAAAAA==.',
Do='Dondeestasto:BAAANQADCgMIAwAAAA==.Dotur:BAAANQADCgIIAgAAAA==.',
Dr='Dragonkiss:BAAANQADCgQIBwAAAA==.Drainmee:BAAANQAECgcICAAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAABNQAECn8uAAIRAAoKJgzMOQAwAQARAAoKJgzMOQAwAQAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAABNQAECn8VAAICAAkKfxK5iQC4AQACAAkKfxK5iQC4AQAAAA==.',
Dv='Dva:BAAANQADCggICAAAAA==.',
['Dá']='Dárkbeard:BAAANQAECgIIBAAAAA==.',
Ea='Eazzekin:BAAANQAECgYICgAAAA==.',
Ek='Ekneirg:BAABNQAECn85AAMCAAoKDRrdXQAYAgACAAoKPBndXQAYAgAVAAcKrheaKwCAAQABNQAECgUICgADAAAAAA==.',
El='Elleneilah:BAAANQADCgUICQAAAA==.Elynth:BAABNQAECn9FAAIcAAoK+xqeHgCaAgAcAAoK+xqeHgCaAgAAAA==.',
Em='Emmalily:BAAANQAECgMIBQAAAA==.',
En='Endlessyueh:BAAANQAECgQICAAAAA==.',
Ex='Extragrippy:BAABNQAECn8aAAIOAAgKORLDVwCUAQAOAAgKORLDVwCUAQAAAA==.',
Ey='Eyris:BAAANQAECgIIAQAAAA==.',
Fa='Faiesong:BAAANQABCgQIBAAAAA==.Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAABNQAECn9CAAIZAAoKxBavCAAiAgAZAAoKxBavCAAiAgAAAA==.Fangren:BAAANQAECgEIAQAAAA==.Farrseer:BAABNQAECn8WAAIQAAYKBAoUVgA1AQAQAAYKBAoUVgA1AQAAAA==.Fasthandslez:BAAANQAECgQIBgAAAA==.',
Fe='Felscythe:BAABNQAECn8kAAIdAAcKfQKpGgCWAAAdAAcKfQKpGgCWAAAAAA==.Felynn:BAAANQAECggIEwAAAA==.',
Fi='Fierradin:BAAANQAECgMIBgABNQAECgoKKQAYAKIhAA==.Fierrastar:BAABNQAECn8pAAIYAAoKoiEfAwDrAgAYAAoKoiEfAwDrAgAAAA==.Finnius:BAAANQADCgMIBAAAAA==.Finshao:BAABNQAECn8gAAIeAAcKyhjAEQDwAQAeAAcKyhjAEQDwAQAAAA==.Fionn:BAAANQAECgMIAwABNQAECgcIGwABAF0aAA==.',
Fl='Flemish:BAABNQAECn82AAITAAoKWRT8MwAGAgATAAoKWRT8MwAGAgAAAA==.Flextame:BAAANQADCggIIgAAAA==.Flipalicious:BAABNQAECn9aAAMTAAoKCha1MQARAgATAAoKCha1MQARAgAbAAoKIg43agB2AQAAAA==.Flipanomicon:BAAANQADCgYIFgAAAA==.Flipkicks:BAAANQADCgYICgAAAA==.Flipmode:BAAANQADCgcIEAAAAA==.Flipnasty:BAAANQADCgYICwAAAA==.Flipocalypse:BAAANQADCgYICgAAAA==.',
Fo='Foxwynn:BAAANQABCgQIBgAAAA==.',
Fr='Freyalise:BAABNQAECn8rAAMFAAoKUx4uMACiAQAFAAYKuxUuMACiAQAKAAgKQwTAsADRAAAAAA==.Freyjah:BAAANQADCgUIBQAAAA==.Frostycarbon:BAAANQADCgYICwAAAA==.',
Fu='Furriousyueh:BAAANQAECgIIAgAAAA==.',
Ga='Gaia:BAABNQAECn8hAAIHAAkKlwqJnAB7AQAHAAkKlwqJnAB7AQAAAA==.Gallimaufrey:BAAANQAECgUIBwAAAA==.Garodan:BAAANQADCgcIDQAAAA==.',
Ge='Gerbo:BAABNQAECn9JAAISAAoKnAzBcgDLAQASAAoKnAzBcgDLAQAAAA==.',
Gi='Gianavel:BAABNQAECn8zAAIaAAoKdQqcJgBkAQAaAAoKdQqcJgBkAQAAAA==.Ginodh:BAAANQAECgQIBgABNQAECgoKFQAZANUNAA==.Ginomage:BAABNQAECn8VAAMZAAoK1Q2/DQC6AQAZAAoK1Q2/DQC6AQASAAUKSAkKagHlAAAAAA==.Ginopally:BAAANQADCgMIAwABNQAECgoKFQAZANUNAA==.Ginoshaman:BAAANQADCgUIBgABNQAECgoKFQAZANUNAA==.Ginovoker:BAAANQADCgYICQABNQAECgoKFQAZANUNAA==.Gizelli:BAAANQAECgIIAgABNQAECgIIAgADAAAAAA==.',
Gr='Grilled:BAAANQADCgYICwAAAA==.Grimoak:BAAANQAECgIIAwAAAA==.Gronke:BAAANQAECgQIAwABNQAECgUICgADAAAAAA==.Grubetsella:BAABNQAECn9GAAQaAAoKuRpWFgAKAgAaAAkKKRlWFgAKAgAeAAgKpBEfIAAWAQAdAAYKThFDFQDUAAAAAA==.Grugachur:BAABNQAECn8kAAIfAAgK3B0SCADdAQAfAAgK3B0SCADdAQAAAA==.',
Gu='Gustice:BAAANQADCgIJAgAAAA==.',
Gw='Gwenwyfar:BAAANQAECggICAAAAA==.',
Gy='Gyda:BAAANQAECgMICQAAAA==.',
Ha='Hadooken:BAAANQABCgQIBAAAAA==.Hangi:BAAANQADCgEIAQABNQAECgcICwADAAAAAA==.Hanoumatoi:BAAANQAECgcIDQAAAA==.Haralambos:BAABNQAECn8ZAAIVAAYKsQt8PQC1AAAVAAYKsQt8PQC1AAAAAA==.Harlar:BAAANQADCgYIDQAAAA==.Hasun:BAABNQAECn8mAAICAAoKNh4CLwCmAgACAAoKNh4CLwCmAgABNQAECgoKNgATAOkeAA==.',
He='Hehasnoname:BAAANQADCgYICQAAAA==.Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQAECgUIDAAAAA==.Heyokagi:BAAANQAECgcIBwAAAA==.',
Ho='Hordkilla:BAAANQAECgUIEQAAAA==.Hownowbrncw:BAABNQAECn8hAAICAAkKhBEevwBVAQACAAkKhBEevwBVAQAAAA==.',
Hy='Hyce:BAABNQAECn8+AAQQAAoKQBQuJwDTAQAgAAgKlRPRKAD9AQAQAAkKwxAuJwDTAQANAAMK/hiWHQDmAAAAAA==.Hymno:BAAANQADCgYICQAAAA==.',
Ih='Ihavenoname:BAAANQADCgYJCwAAAA==.',
Il='Illusionous:BAAANQAECgMIBAAAAA==.',
In='Insoniacyun:BAAANQAECgQIBgAAAA==.',
Is='Iselian:BAAANQAECggIJgAAAQ==.Istrix:BAAANQADCgUJBQAAAA==.',
Ja='Jadefeather:BAAANQAECggIEwAAAA==.',
Jb='Jbelbueno:BAAANQAECgQIBQAAAA==.Jblockiv:BAAANQAECgMIAwAAAA==.Jbprimero:BAAANQAECgUIBQAAAA==.Jbshami:BAABNQAECn8uAAIbAAoKsht3RQBLAgAbAAoKsht3RQBLAgAAAA==.',
Je='Jeman:BAAANQABCggICAAAAA==.Jenaelle:BAAANQAECggIAwABNQAECggIBgADAAAAAA==.Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAABNQAECn87AAISAAoKpwNftQA6AQASAAoKpwNftQA6AQAAAA==.Jetfires:BAABNQAECn9MAAIHAAoKSB+1KgCWAgAHAAoKSB+1KgCWAgAAAA==.',
Ji='Jinger:BAABNQAECn8lAAIaAAgK+AUcNgDxAAAaAAgK+AUcNgDxAAAAAA==.Jinnwoo:BAAANQADCgUIBgAAAA==.',
Jo='Jonn:BAAANQAECgMIBAAAAA==.Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQAECgEIAgAAAA==.',
Ju='Juggernacht:BAAANQAECgMIAgABNQAECgoKKgAKAIsZAA==.',
Ka='Kaedren:BAAANQADCggIIAAAAA==.Kaelorien:BAABNQAECn8rAAIeAAoKtQuFGAB5AQAeAAoKtQuFGAB5AQAAAA==.Kaitja:BAAANQADCgIIAgAAAA==.Kalazaad:BAABNQAECn88AAIVAAoKnQmMJABKAQAVAAoKnQmMJABKAQAAAA==.Kaldevayn:BAABNQAECn8bAAMCAAgKDAgm8QABAQACAAgKDAgm8QABAQABAAMKcxPStgCuAAAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalrow:BAABNQAECn8yAAMgAAoK4Q2SHgCvAQAgAAoK4Q2SHgCvAQAQAAEKAABVnwAgAAAAAA==.Kalto:BAAANQAECgIIBQAAAA==.Kalyna:BAAANQAECgUIBgAAAA==.Kanhoa:BAAANQAECgQIBAAAAA==.Kardanika:BAAANQAECgYICgAAAA==.Kardanis:BAABNQAECn9CAAIbAAoK8B6YFAASAwAbAAoK8B6YFAASAwAAAA==.Karyudo:BAAANQAECgEIAQAAAA==.Kashe:BAABNQAECn8bAAIBAAcKXRpxQgAKAgABAAcKXRpxQgAKAgAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAABNQAECn8sAAIZAAkKGxQ5CgAoAgAZAAkKGxQ5CgAoAgAAAA==.Katavia:BAABNQAECn9IAAIbAAoKmg4JVADDAQAbAAoKmg4JVADDAQAAAA==.Kathii:BAAANQAECgYIDwAAAA==.Katrazath:BAABNQAECn8nAAIhAAkKdAxrDQB3AQAhAAkKdAxrDQB3AQAAAA==.Kaydencia:BAAANQABCgUICAAAAA==.',
Ke='Keledras:BAAANQAECggIBAAAAA==.Kelmmers:BAAANQAECgcIBgAAAA==.Kelân:BAAANQAECgMIBQAAAA==.Keyallandron:BAABNQAECn8cAAIHAAYKmAffzgAUAQAHAAYKmAffzgAUAQAAAA==.Keywi:BAAANQAECgcICQAAAA==.',
Kh='Khaleesie:BAAANQAECgEIAgAAAA==.Khiana:BAAANQADCgIIAgABNQAECgoKSAAHAJkfAA==.Khrin:BAAANQADCgYIFQAAAA==.',
Ki='Kiddow:BAABNQAECn8eAAIZAAYKvAzJIgDCAAAZAAYKvAzJIgDCAAAAAA==.Kierea:BAAANQADCgcIEgAAAA==.Kiiarah:BAAANQAECgcIEwAAAA==.Killrah:BAAANQADCgQIBAAAAA==.Kilrah:BAAANQADCggIEAAAAA==.Kilriella:BAAANQADCgYIBwAAAA==.Kinte:BAAANQADCgYIBgAAAA==.Kitamii:BAABNQAECn8UAAIMAAkKARBiEgCiAQAMAAkKARBiEgCiAQAAAA==.Kivrin:BAABNQAECn8eAAIFAAYKIgZnQQCpAAAFAAYKIgZnQQCpAAAAAA==.Kiára:BAAANQADCggIDQAAAA==.',
Ko='Kokujin:BAABNQAECn8zAAITAAkKeBdeTgCeAQATAAkKeBdeTgCeAQAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAABNQAECn8pAAIHAAoKciCjKACdAgAHAAoKciCjKACdAgAAAA==.',
Ku='Kurumi:BAAANQAECgEIAQAAAA==.',
Kw='Kwo:BAABNQAECn8nAAIdAAkKEQwgDgBHAQAdAAkKEQwgDgBHAQAAAA==.',
Ky='Kymma:BAABNQAECn8yAAICAAkKhAqDsgBrAQACAAkKhAqDsgBrAQAAAA==.',
La='Laviz:BAAANQADCgYIBwABNQAECgoKNgATAOkeAA==.Laz:BAAANQADCgUICgAAAA==.Lazengann:BAABNQAECn8uAAMgAAoKwRxYFQC6AgAgAAkKmx5YFQC6AgAQAAIKyQ/BhAA0AAAAAA==.',
Le='Leafbane:BAABNQAECn9LAAQJAAkKDRr9IwBxAgAJAAkKDRr9IwBxAgARAAMKTxAEUgC9AAAOAAEK4BbNwQBFAAAAAA==.Legevia:BAABNQAECn8fAAITAAcKQQV+mwDRAAATAAcKQQV+mwDRAAAAAA==.Leiris:BAABNQAECn87AAMCAAoKug5/fADUAQACAAoKug5/fADUAQABAAEKoQAbOwEZAAAAAA==.Lejusticier:BAAANQADCggIDAAAAA==.Leonaa:BAAANQADCggIIgAAAA==.Letifer:BAAANQADCgcIBwAAAA==.Leucetios:BAAANQAECgUIDAAAAA==.',
Li='Liarace:BAABNQAECn8eAAIKAAoK2BPeNgBiAgAKAAoK2BPeNgBiAgAAAA==.Lightbeard:BAAANQAECgUIEwAAAA==.Lightforge:BAABNQAECn8WAAICAAoKSRVskwD9AQACAAoKSRVskwD9AQAAAA==.Lionessi:BAAANQADCgcIBwAAAA==.Lithika:BAAANQADCgYIBgAAAA==.',
Lo='Lorredain:BAAANQADCgcIDgAAAA==.Lothaire:BAAANQAECgMIAwAAAA==.Lothwen:BAAANQAECgQICQAAAA==.Louisachan:BAAANQAECgIIAgAAAA==.',
Lu='Lucamar:BAAANQADCgQIBAAAAA==.Luxinine:BAABNQAECn9DAAIFAAoKeB1tFADBAgAFAAoKeB1tFADBAgAAAA==.',
Ly='Lyshai:BAAANQAECgUIBQABNQAECgkJKQAhAKkdAA==.',
Ma='Madhawi:BAAANQAECgEIBAAAAA==.Magamon:BAABNQAECn9IAAISAAoKWxMNWAALAgASAAoKWxMNWAALAgAAAA==.Magnix:BAAANQADCgQIBAABNQAECgYIFAAOABkeAA==.Malfuriia:BAABNQAECn8kAAIbAAcK9BLzZACHAQAbAAcK9BLzZACHAQAAAA==.Mamboke:BAABNQAECn83AAMHAAoKww+MWwASAgAHAAoKww+MWwASAgAiAAQKVgKIaQCHAAAAAA==.Margerdria:BAAANQADCgcIEAAAAA==.Mauugrim:BAABNQAECn8jAAMRAAgKNQcjSwDZAAARAAcK5wYjSwDZAAAJAAgK2QRkewC8AAAAAA==.Maxowen:BAABNQAECn8kAAICAAcKzRVNzQA8AQACAAcKzRVNzQA8AQAAAA==.Maxxramas:BAAANQADCgcICgAAAA==.',
Me='Mearadan:BAABNQAECn8qAAIbAAoKIgsqgQAwAQAbAAoKIgsqgQAwAQAAAA==.Meatsweats:BAAANQAECgYICwAAAA==.Megg:BAAANQAECgUIBgAAAA==.Mekh:BAABNQAECn8pAAMhAAkKqR1QBQBtAgAhAAkKqR1QBQBtAgAjAAEK0x76NgBMAAAAAA==.Mel:BAAANQADCgcIGwAAAA==.Melanara:BAABNQAECn80AAIZAAoKfw9VDgDGAQAZAAoKfw9VDgDGAQAAAA==.Melstrom:BAAANQAECgQICQAAAA==.Meticuluslyn:BAAANQAECgQIBgAAAA==.',
Mi='Milkmaiden:BAAANQADCgQJCAAAAA==.Milkthisbull:BAAANQADCgMIAwAAAA==.Mixler:BAABNQAECn8cAAISAAoKhgfAkQCCAQASAAoKhgfAkQCCAQAAAA==.',
Mm='Mmeow:BAAANQADCgYIEAABNQAECgoKMwAHAH4cAA==.',
Mo='Moirine:BAABNQAECn8kAAMGAAcKsRbsBgBwAQAGAAYKhRXsBgBwAQAFAAYKFxqTJQBXAQAAAA==.Moonflowers:BAAANQAECggICQAAAA==.',
Mu='Murdrmitts:BAABNQAECn8WAAIMAAUKcwjTJQDfAAAMAAUKcwjTJQDfAAAAAA==.Mustikka:BAAANQAECgYIEgAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Myuriyanka:BAABNQAECn9CAAITAAoKFBGAQADSAQATAAoKFBGAQADSAQAAAA==.',
['Mæ']='Mælstrôm:BAAANQABCgQICAAAAA==.',
Na='Naahommii:BAAANQAECgQIBAAAAA==.Nachtamus:BAAANQAECgMIAgABNQAECgoKKgAKAIsZAA==.Nachtkampfer:BAAANQAECgEIAwABNQAECgoKKgAKAIsZAA==.Nachtkreiger:BAAANQABCgEIAQABNQAECgoKKgAKAIsZAA==.Nachtpranke:BAAANQAECgQIBAABNQAECgoKKgAKAIsZAA==.Nachtteufel:BAAANQAECgEIAgABNQAECgoKKgAKAIsZAA==.Naeri:BAABNQAECn8tAAILAAgK+BWmHwAAAgALAAgK+BWmHwAAAgAAAA==.Nagualli:BAAANQAECggIEgAAAA==.Naieve:BAABNQAECn8uAAIWAAoKixJQQAD5AQAWAAoKixJQQAD5AQAAAA==.Nastii:BAAANQADCgEIAQAAAA==.Nastychungus:BAABNQAECn8sAAMTAAkKLCKVGAA1AwATAAkKLCKVGAA1AwAbAAUK6AM60wDAAAAAAA==.Navira:BAAANQADCggIHgAAAA==.',
Ne='Negargra:BAABNQAECn8uAAIcAAoKOgusYAC0AQAcAAoKOgusYAC0AQAAAA==.Nekoda:BAAANQAECggIAwABNQAECggIBgADAAAAAA==.Nephadin:BAAANQAECgEIAQAAAA==.Nephilim:BAAANQAECgYICgAAAA==.Neyvin:BAAANQADCggICAAAAA==.',
Ni='Niduun:BAAANQABCggICAAAAA==.Nightfend:BAAANQADCgcICwAAAA==.Nighttiger:BAAANQAECgYIEgAAAA==.Nikooli:BAABNQAECn8fAAMQAAcKOg7GRgAUAQAQAAcKOg7GRgAUAQANAAEKygVFNQAfAAAAAA==.',
No='Noopsie:BAABNQAECn8yAAILAAcKBBagJQDGAQALAAcKBBagJQDGAQAAAA==.Nooters:BAABNQAECn84AAIJAAoK8iMMBwBzAwAJAAoK8iMMBwBzAwABNQAFFAcIGwAhADciAA==.Norrina:BAAANQABCgEIAQAAAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAABNQAECn8oAAMKAAoKmBuZOABaAgAKAAkKth2ZOABaAgAFAAkKnxRHFQALAgAAAA==.',
Nu='Nunavutt:BAAANQADCgUIBQAAAA==.',
Ny='Nyteweaver:BAABNQAECn8iAAICAAcKTRFI3QAiAQACAAcKTRFI3QAiAQAAAA==.',
Ob='Oberonny:BAAANQAECgcICgAAAA==.',
Od='Oderica:BAAANQAECggIDwAAAA==.Odurn:BAAANQADCgYIBgAAAA==.',
Og='Ogayac:BAAANQAECgMIAQAAAA==.',
Oh='Ohminous:BAABNQAECn8UAAITAAgK9gbWbwA5AQATAAgK9gbWbwA5AQAAAA==.',
Or='Oranash:BAAANQADCgMIAwAAAA==.Orici:BAAANQAECgIIAgABNQAECgIIAwADAAAAAA==.Ornir:BAAANQADCgMIAwAAAA==.Orongosh:BAAANQADCggIDgAAAA==.',
Os='Oscarmikey:BAABNQAECn8+AAMWAAoKUhpqNgA4AgAWAAoKUhpqNgA4AgALAAgKlBm9GwArAgAAAA==.Oshu:BAAANQADCgcIBgAAAA==.',
Ot='Ottoshot:BAABNQAECn8kAAIHAAcK+w59rgBVAQAHAAcK+w59rgBVAQAAAA==.Otum:BAAANQAECgMICAAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
Ox='Oxmantle:BAAANQAECgMIAgAAAA==.',
['Oö']='Oöps:BAABNQAECn8cAAILAAcKRgfQSQDXAAALAAcKRgfQSQDXAAAAAA==.',
Pa='Paksen:BAAANQAECgYIBgAAAA==.Panamone:BAAANQAECggIDQAAAA==.Pandamaster:BAABNQAECn8UAAISAAoKLxWFyQDyAQASAAoKLxWFyQDyAQAAAA==.Paulee:BAAANQAECgEIAQAAAA==.',
Pe='Pendragon:BAAANQADCgQIBQAAAA==.Pesch:BAAANQAECggICAAAAA==.',
Ph='Phylah:BAABNQAECn8ZAAMbAAYKPxT+fQA5AQAbAAYKPxT+fQA5AQATAAEKAABvUQElAAAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Porterhouze:BAAANQABCgIIAgABNQAECgcIJQAkAIwEAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.Prophetofham:BAAANQADCgYIBgAAAA==.',
Pu='Puchi:BAACNQAFFH8ZAAIeAAgK+hP5AwCpAQAeAAgK+hP5AwCpAQA1AAQKfzwAAh4ACgohIokEAF0DAB4ACgohIokEAF0DAAAA.',
Py='Pyrocles:BAAANQABCgQICQAAAA==.',
Qa='Qadhiræ:BAAANQAECgMICAABNQADCgYICwADAAAAAA==.',
Qw='Qwyn:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
['Qæ']='Qædhira:BAAANQADCgYICwAAAA==.',
Ra='Raez:BAABNQAECn8fAAIbAAgK/g8taAB9AQAbAAgK/g8taAB9AQAAAA==.Ragnerock:BAAANQAECgMIBQAAAA==.Raynecira:BAABNQAECn8dAAIHAAgKgAwgpgBnAQAHAAgKgAwgpgBnAQAAAA==.',
Re='Reihino:BAAANQAECgYICwAAAA==.Remixidora:BAAANQAECgQICAABNQAFFAYICAASAOQbAA==.Reyrocko:BAAANQAECgIIAQAAAA==.Rezdh:BAAANQAECgYIDQABNQAFFAIIBQASADwTAA==.Rezmage:BAACNQAFFH8FAAMSAAIKPBM0SABOAAASAAEKhhY0SABOAAAZAAEK8g9wFgBEAAA1AAQKfx0ABBIACgq1HGd9ALABABIACAqSGWd9ALABABkABQoAFu8aAAMBACUAAQqtEokNADcAAAAA.Reznal:BAAANQAECgMIAwABNQAFFAIIBQASADwTAA==.Rezvoker:BAAANQADCgUJCgABNQAFFAIIBQASADwTAA==.',
Rh='Rhage:BAAANQADCgcIGgAAAA==.Rhoaias:BAAANQAECgEIAQAAAA==.',
Ri='Rickness:BAAANQAECgIIBAAAAA==.Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokform:BAAANQAECgYIBgAAAA==.Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQAECgEIAQAAAA==.Rottingturky:BAAANQAECggIEgAAAA==.Roxane:BAABNQAECn8iAAIWAAkKQAfxPgAuAQAWAAkKQAfxPgAuAQAAAA==.',
Ru='Rubyace:BAAANQAECggIEAAAAA==.Runningelk:BAABNQAECn81AAImAAoKYR3IDABrAgAmAAoKYR3IDABrAgAAAA==.Runscapemain:BAABNQAECn8lAAICAAgK1AlktwCvAQACAAgK1AlktwCvAQAAAA==.',
Ry='Ryeti:BAAANQADCggINAAAAA==.Ryuzu:BAAANQAECgUICAAAAA==.Ryydia:BAAANQADCgMIBQAAAA==.',
Sa='Sableanne:BAAANQAECgYIDgAAAA==.Sahalia:BAAANQAECgQIBAAAAA==.Saintulrick:BAAANQAECgUIBQAAAA==.Sajuice:BAABNQAECn8cAAMHAAkKFRsgSwCMAgAHAAkKFRsgSwCMAgAiAAQKKRRDUQDlAAAAAA==.Salow:BAAANQABCgYICgAAAA==.Sanitas:BAABNQAECn8vAAMKAAoKChB1WgASAgAKAAoKChB1WgASAgAFAAQK3QLBUQBmAAAAAA==.Sanivar:BAAANQADCgYIBgABNQAECgoKJQAGAPUaAA==.Sayle:BAAANQAECgUIBQABNQAECgoKKwAKABgVAA==.',
Se='Seeyen:BAACNQAFFH8KAAIHAAQKDhKeEwAsAQAHAAQKDhKeEwAsAQA1AAQKf0MAAgcACgoqI/MOAGoDAAcACgoqI/MOAGoDAAAA.Sej:BAAANQABCgIIAgAAAA==.Seraphon:BAAANQADCggIJAAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAADAAAAAA==.Serenityhate:BAAANQAECgQIBAAAAA==.',
Sh='Shaaydo:BAAANQADCgQIBAAAAA==.Shaayllee:BAAANQAECgQIBQAAAA==.Shaaytheyha:BAABNQAECn8lAAICAAcKpAfZ7ABCAQACAAcKpAfZ7ABCAQAAAA==.Shaggyp:BAACNQAFFH8QAAIKAAQKnxFsGwAXAQAKAAQKnxFsGwAXAQA1AAQKfyMAAgoACgqrEIlXAN4BAAoACgqrEIlXAN4BAAAA.Shamump:BAAANQADCgcIBwAAAA==.Sharington:BAAANQADCgUIBQAAAA==.Sharyl:BAAANQABCgcIEQAAAA==.Shehasnoname:BAAANQADCgYIGAAAAA==.Shehulk:BAAANQAECgUICwAAAA==.Shingo:BAAANQADCgcIBwABNQAECgoKQwAJAEogAA==.Ships:BAABNQAECn8fAAIjAAoKnRU0FwBFAgAjAAoKnRU0FwBFAgAAAA==.',
Si='Silf:BAAANQAECgEIAQAAAA==.Silverapples:BAAANQADCgIIAgAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skrektwo:BAABNQAECn8wAAMbAAkKyhXMewCYAQAbAAgKlBTMewCYAQATAAYKmQZs2wDeAAAAAA==.',
Sm='Smackdogg:BAACNQAFFH8MAAIWAAUKQSDQDQCNAQAWAAUKQSDQDQCNAQA1AAQKfx0AAhYACQrKJAEUACcDABYACQrKJAEUACcDAAAA.',
So='Solarspark:BAAANQAECgYIEQAAAA==.Sondaladan:BAAANQADCggIIgAAAA==.Sonomonom:BAAANQADCggIEAAAAA==.Sorvina:BAABNQAECn8+AAIcAAoKdQ4dWgDGAQAcAAoKdQ4dWgDGAQAAAA==.Soulflame:BAABNQAECn9LAAIZAAoK/gojEAClAQAZAAoK/gojEAClAQAAAA==.Soulkings:BAAANQADCggIGgAAAA==.',
Sp='Spriggs:BAAANQADCgUIBAAAAA==.',
St='Starpath:BAAANQAECgMIAwABNQAECgcICwADAAAAAA==.Strangr:BAAANQADCggICwABNQAECgoKSgAaABUgAA==.Stregnor:BAABNQAECn8oAAIHAAoKnw/zXgAKAgAHAAoKnw/zXgAKAgAAAA==.Styggi:BAAANQADCggICAAAAA==.Stygy:BAAANQADCgcIBwABNQADCggICAADAAAAAA==.',
Su='Sumyunguy:BAABNQAECn8fAAIaAAcKwBa0KABUAQAaAAcKwBa0KABUAQAAAA==.',
Sy='Syllenne:BAAANQABCgMIAwAAAA==.Sylunia:BAABNQAECn8YAAIZAAcK2QMeHwDxAAAZAAcK2QMeHwDxAAAAAA==.Sylváñás:BAAANQABCggIFAAAAA==.Syrintha:BAAANQADCgYIDAAAAA==.',
Ta='Tachi:BAAANQAECgUIEAABNQAECgkJKQAJAJUSAA==.Tachie:BAABNQAECn8oAAIhAAgKPRjpDACCAQAhAAgKPRjpDACCAQABNQAECgkJKQAJAJUSAA==.Tairi:BAAANQABCgMIBQAAAA==.Talonclaw:BAAANQABCgQICQAAAA==.Talön:BAEANQAECgUJBQAAAA==.Tarvah:BAAANQADCgYIBgAAAA==.',
Te='Teranox:BAAANQABCgYIGwAAAA==.Tezzerae:BAABNQAECn8eAAIHAAcK8QKs/AC4AAAHAAcK8QKs/AC4AAAAAA==.',
Th='Thaesan:BAAANQAECgcIDgAAAA==.Theistica:BAABNQAECn8kAAIVAAgKNQsUMQD2AAAVAAgKNQsUMQD2AAAAAA==.Theomir:BAAANQAECgIIAQAAAA==.Therin:BAABNQAECn87AAMYAAoK9BEoBgDlAQAYAAoK9BEoBgDlAQAiAAcKBwYORAA4AQAAAA==.Thodi:BAAANQABCgYICgAAAA==.',
Ti='Tigermyst:BAAANQADCgYIBgAAAA==.Tillymonick:BAAANQAECgUICwAAAA==.',
To='Todes:BAAANQADCgIIAgAAAA==.Tongshi:BAAANQABCggIDAAAAA==.Toofast:BAABNQAECn87AAIbAAoKiyAICgB8AwAbAAoKiyAICgB8AwAAAA==.Toofurrious:BAAANQADCgQIBgAAAA==.Toolotems:BAAANQAECgUIBwAAAA==.Topswimmer:BAAANQABCgIIAgAAAA==.',
Tr='Trifus:BAAANQAECgYIBwAAAA==.',
Tu='Tulao:BAABNQAECn8lAAISAAoKwBnjMwBzAgASAAoKwBnjMwBzAgABNQAECgoKNgATAOkeAA==.',
Ty='Tylae:BAAANQADCgQIBwAAAA==.',
Ut='Utheli:BAACNQAFFH8FAAICAAQK+Q+gGADLAAACAAQK+Q+gGADLAAA1AAQKf0AAAgIACgoEIOElAMkCAAIACgoEIOElAMkCAAAA.',
Va='Vaevictis:BAAANQAECgIIAgABNQAECgoKKwAFAFMeAA==.Vaeyethir:BAAANQABCgcICAAAAA==.Vaildora:BAABNQAECn8pAAMJAAkKlRJ0KwAEAgAJAAkKdBJ0KwAEAgAOAAQKuA5OcgCLAAAAAA==.Valdra:BAABNQAECn81AAIXAAoK0BcZCgAvAgAXAAoK0BcZCgAvAgAAAA==.Valkyl:BAAANQADCgMIBQAAAA==.Valkyll:BAAANQADCgIIBAAAAA==.Valkylpal:BAAANQADCgEIAQAAAA==.Valord:BAAANQADCgcIBwAAAA==.Vane:BAAANQADCgEIAQAAAA==.Vanillacain:BAAANQADCgMIAwAAAA==.',
Ve='Vekjari:BAAANQABCgEIAQAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgcIHQAAAA==.',
Vl='Vlonet:BAABNQAECn86AAMgAAkKjhUiGwDSAQAgAAkKjhUiGwDSAQAQAAEK7QholwAuAAAAAA==.',
Vn='Vnasty:BAAANQAECgQIBwABNQAECgkJLAATACwiAA==.',
Vo='Vokola:BAAANQAECgQIBgABNQAECgkJKQAJAJUSAA==.',
Wa='Warthexn:BAAANQAECgQIBAAAAA==.',
We='Wehadnoname:BAAANQABCgEIAQAAAA==.Weshalas:BAAANQAECgMIAwAAAA==.',
Wh='Whelp:BAAANQAECgIIAgAAAA==.',
Wi='Wilken:BAABNQAECn8aAAMEAAcKNAzRrQAeAQAEAAcKNAzRrQAeAQAXAAEKAACHUwAAAAAAAA==.Wilohart:BAAANQABCgMIAwAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwADAAAAAA==.Wiva:BAAANQAECgQIBgAAAA==.',
Wo='Wolfsokol:BAABNQAECn8aAAQOAAoKwxitQwDsAQAOAAcK0R6tQwDsAQAJAAMKiwV4kgB7AAARAAEKAAC3pQAAAAABNQAFFAkJFwAjAPAgAA==.',
Wr='Wreckoner:BAABNQAECn9IAAIVAAoKfRV2EgAFAgAVAAoKfRV2EgAFAgAAAA==.',
Xa='Xannah:BAAANQAECgMIAgAAAA==.Xavencia:BAAANQADCgYICgAAAA==.',
Xi='Xinthos:BAAANQAECgYIBgAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Za='Zaderan:BAAANQADCggIHgABNQAECgoKJQAUAA4XAA==.Zakainu:BAABNQAECn8lAAIUAAoKDhdlFQC+AQAUAAoKDhdlFQC+AQAAAA==.Zallister:BAAANQADCggIKAAAAA==.Zansarutobi:BAAANQABCgYICAAAAA==.Zarathoszan:BAABNQAECn8zAAIHAAoKHwtVbADpAQAHAAoKHwtVbADpAQAAAA==.Zarkra:BAAANQAECgYIDAABNQAECgoKNQAmAGEdAA==.',
Ze='Zedator:BAABNQAECn8kAAIYAAoKXBWQBQBhAgAYAAoKXBWQBQBhAgAAAA==.Zedraikis:BAAANQADCgEIAQABNQADCggIEAADAAAAAA==.Zelgaddis:BAABNQAECn8zAAIbAAoKqBWkVwC1AQAbAAoKqBWkVwC1AQAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zh='Zhansaya:BAAANQAECgIIBAABNQAECgQIBAADAAAAAA==.',
Zr='Zriana:BAAANQAECgQIEgAAAA==.',
Zs='Zsarilya:BAABNQAECn8tAAMKAAgKqAIjqQDjAAAKAAgKqAIjqQDjAAAFAAEKAAB1gAAAAAAAAA==.',
Zu='Zurgen:BAABNQAECn9FAAIcAAoKLh2xHACkAgAcAAoKLh2xHACkAgAAAA==.',
['Àn']='Àndrol:BAABNQAECn8jAAISAAkKaA2VnwBlAQASAAkKaA2VnwBlAQABNQAFFAcIEwAgAHUPAA==.',
['Ás']='Áshe:BAAANQAECgcICAAAAA==.',
['Êc']='Êclipse:BAEBNQAECn89AAILAAoKtR3BDAD+AgALAAoKtR3BDAD+AgAAAA==.',
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
