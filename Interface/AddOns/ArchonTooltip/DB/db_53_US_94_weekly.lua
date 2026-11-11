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

local lookup = {'Paladin-Holy','Unknown-Unknown','Warrior-Arms','Priest-Shadow','Priest-Discipline','Hunter-BeastMastery','Rogue-Assassination','DeathKnight-Frost','Priest-Holy','Paladin-Retribution','Druid-Restoration','Druid-Feral','DemonHunter-Vengeance','DeathKnight-Blood','Rogue-Subtlety','DemonHunter-Havoc','DeathKnight-Unholy','Mage-Arcane','Shaman-Elemental','Shaman-Enhancement','Paladin-Protection','Druid-Balance','Warrior-Protection','Hunter-Survival','Mage-Frost','Monk-Windwalker','Shaman-Restoration','Warlock-Demonology','Monk-Brewmaster','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Devourer','Evoker-Devastation','Hunter-Marksmanship','Evoker-Preservation','Warlock-Destruction','Mage-Fire','Druid-Guardian',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aarchon:BAABNQAECn8/AAIBAAoKbB5lFgD0AgABAAoKbB5lFgD0AgAAAA==.',
Ad='Aduin:BAAANQAECggIEAAAAA==.',
Ae='Aedarelyn:BAAANQAECgcIEAAAAA==.Aellita:BAAANQAECgQIBwAAAA==.Aenoryae:BAAANQADCgYIBgABNQADCgYICwACAAAAAA==.Aeschylus:BAAANQAECgQIBgAAAA==.Aeson:BAAANQAECgIIAgAAAA==.',
Af='Afkinlife:BAAANQAECgEIAQAAAA==.',
Ai='Aias:BAAANQADCgcIBwAAAA==.',
Ak='Akky:BAABNQAECn8jAAIDAAoKnRY0iwAAAgADAAoKnRY0iwAAAgAAAA==.Aksafiya:BAABNQAECn9kAAMEAAoK6BFrFQD0AQAEAAoK6BFrFQD0AQAFAAEK5QGHMQAgAAAAAA==.',
Al='Alal:BAAANQADCgYIFQAAAA==.Alandras:BAAANQAECggICAAAAA==.Alaras:BAACNQAFFH8RAAIEAAcKmAqTBABwAQAEAAcKmAqTBABwAQA1AAQKfyIAAgQACgrcFSIVALgCAAQACgrcFSIVALgCAAAA.Aleesha:BAAANQAECgEIAgAAAA==.Alissia:BAAANQAECgIIBAAAAA==.Allaras:BAAANQAECgEIAQAAAA==.Allistaris:BAABNQAECn8mAAIGAAoKExdVZwBFAgAGAAoKExdVZwBFAgAAAA==.Allrianne:BAAANQAECgEIAQAAAA==.Alluriela:BAAANQADCgIIAwAAAA==.Allyriae:BAAANQAECggIDwAAAA==.Alphard:BAAANQAECgQIBwABNQAECgkJHwAHAI8ZAA==.Alphá:BAABNQAECn8gAAIIAAkKMwtaSgCRAQAIAAkKMwtaSgCRAQAAAA==.Althoraty:BAABNQAECn8nAAIJAAkKDRZBWgC+AQAJAAkKDRZBWgC+AQAAAA==.Alyx:BAAANQAECgEIBQAAAA==.',
Am='Amberlilly:BAABNQAECn8mAAIKAAgKqQjRzAAnAQAKAAgKqQjRzAAnAQAAAA==.',
An='Andoros:BAABNQAECn83AAMLAAoK3SGuBwBPAwALAAoK3SGuBwBPAwAMAAEK3wXsUgAQAAAAAA==.Angelon:BAAANQADCgQIBgAAAA==.Antaak:BAAANQAECgEIAQAAAA==.Antilles:BAAANQADCgIIAwAAAA==.Anzurath:BAABNQAECn83AAIKAAoKGA5LegDFAQAKAAoKGA5LegDFAQAAAA==.',
Ap='Apheron:BAABNQAECn81AAINAAoKxSLmAgDVAgANAAoKxSLmAgDVAgAAAA==.Apollimy:BAAANQAECggIBgAAAA==.Applebow:BAABNQAECn8oAAIOAAgKqRJsPQA8AQAOAAgKqRJsPQA8AQAAAA==.Apples:BAAANQAECggIDwAAAA==.',
Ar='Arathwr:BAAANQADCgcIBwABNQAECgcIEAACAAAAAA==.Ardalel:BAAANQADCgcICAAAAA==.Arknova:BAABNQAECn81AAIKAAoK5Bp1NQCAAgAKAAoK5Bp1NQCAAgAAAA==.Armas:BAAANQAECgEIAgAAAA==.Arylin:BAAANQAECgIIBQAAAA==.',
As='Asheram:BAAANQADCgEIAQAAAA==.Ashkinassi:BAEANQADCgUIBgAAAA==.Asiain:BAAANQAECgUIBwABNQAFFAYICwADAO8MAA==.Asmin:BAABNQAECn8cAAMPAAoKKhC+OAADAgAPAAoKKhC+OAADAgAHAAEKAAAyqQAqAAAAAA==.Asnabel:BAABNQAECn8pAAIIAAgK5witVAAqAQAIAAgK5witVAAqAQAAAA==.',
At='Atsa:BAAANQADCgQIBAAAAA==.Atvar:BAAANQADCggICAAAAA==.',
Au='Aurelith:BAAANQAECgcIDQAAAA==.Autumndeath:BAAANQAECgMIBQAAAA==.',
Av='Avinger:BAAANQABCggIGQAAAA==.',
Ay='Ayden:BAABNQAECn8nAAMNAAgKoROeDgDPAQANAAgKoROeDgDPAQAQAAUKRwyaXACdAAAAAA==.',
Az='Azorain:BAAANQADCgQIBAAAAA==.Azrim:BAAANQADCgYIDgABNQAECgYIDwACAAAAAA==.Azureis:BAAANQADCgcICAAAAA==.',
Ba='Babaganouj:BAAANQAECgEIAgABNQAECgQICwACAAAAAA==.Badman:BAAANQAECgcIDQABNQAECgoKNwABAGkXAA==.Balolz:BAAANQAECgEIAgAAAA==.',
Be='Belthar:BAABNQAECn8iAAIOAAkKcRVtTwC3AQAOAAkKcRVtTwC3AQAAAA==.Bendeye:BAAANQADCgcIDwAAAA==.',
Bl='Blee:BAAANQAECgQIEQAAAA==.Bluudclaaw:BAAANQADCgMIAwABNQAECgcIEAACAAAAAA==.',
Bo='Boing:BAABNQAECn8fAAIHAAkKjxkCJgBcAgAHAAkKjxkCJgBcAgAAAA==.Bondad:BAAANQAECgYICQABNQAECgcIDQACAAAAAA==.Boomhauer:BAABNQAECn8mAAIGAAgKJhjXdAC5AQAGAAgKJhjXdAC5AQAAAA==.',
Br='Braelia:BAABNQAECn8ZAAIRAAoKGQ6DaQBsAQARAAoKGQ6DaQBsAQAAAA==.Braetwo:BAAANQABCggJDwABNQAECgoKGQARABkOAA==.Braughm:BAAANQADCgUJBQAAAA==.Braxius:BAAANQADCgMIAwABNQAECgkJPwASALkfAA==.Brettcooper:BAAANQABCgcIBwAAAA==.Breye:BAABNQAECn8aAAITAAkKxAe0pwBFAQATAAkKxAe0pwBFAQAAAA==.Brightstone:BAAANQAECgIIAgABNQAECgcIEAACAAAAAA==.Brindria:BAAANQADCgYICAAAAA==.Brood:BAABNQAECn8YAAQRAAYKXRJKfQAnAQARAAUKfxFKfQAnAQAIAAQKtQxTagDbAAAOAAEKLhXvwgBCAAABNQAECgcIEQACAAAAAA==.Brundles:BAABNQAECn8/AAIKAAoK3An0jwCXAQAKAAoK3An0jwCXAQAAAA==.',
Bu='Bubblepopper:BAABNQAECn8hAAMJAAgK0h1BVgAgAgAJAAgK0h1BVgAgAgAEAAUKpQxrMwDdAAAAAA==.Bunky:BAABNQAECn8oAAIUAAgK7gTLHgAaAQAUAAgK7gTLHgAaAQAAAA==.',
Ca='Cailaranel:BAABNQAECn8kAAIPAAkKPgu+VwCKAQAPAAkKPgu+VwCKAQAAAA==.Calaul:BAABNQAECn83AAMKAAoKxQymowDZAQAKAAkKJw6mowDZAQAVAAEKGAMObgAbAAAAAA==.Calenbraga:BAABNQAECn81AAMMAAkKthqiCQAtAgAMAAkKthqiCQAtAgAWAAIKWQk+hAA0AAAAAA==.Calisim:BAAANQAECgQIDwAAAA==.Caloh:BAABNQAECn8aAAIXAAcKEBdGHAAJAQAXAAcKEBdGHAAJAQAAAA==.Cantholdagro:BAAANQAECgEIAQABNQAECggIGgAOADkSAA==.Cassamaria:BAABNQAECn8sAAIYAAoKjxM+BAAvAgAYAAoKjxM+BAAvAgAAAA==.Cataryn:BAABNQAECn8/AAIGAAoKEB8SFwDgAgAGAAoKEB8SFwDgAgAAAA==.Catt:BAABNQAECn8vAAIBAAkKnhDhVgCnAQABAAkKnhDhVgCnAQAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECgoKPwAOALcgAA==.',
Ce='Cellebur:BAABNQAECn8VAAIGAAYK/AOi7QC7AAAGAAYK/AOi7QC7AAAAAA==.Ceta:BAABNQAECn8yAAIJAAkK1hZSWADFAQAJAAkK1hZSWADFAQAAAA==.',
Ch='Chalfus:BAABNQAECn8/AAISAAkKuR8jKQCPAgASAAkKuR8jKQCPAgAAAA==.Chaszmyr:BAAANQADCggIHQAAAA==.Chewwy:BAABNQAECn8yAAIOAAkKBiA4EQCGAgAOAAkKBiA4EQCGAgAAAA==.',
Ci='Cinamen:BAAANQAECgUIBwAAAA==.Cinderelah:BAAANQAECgQIBAAAAA==.Cizean:BAABNQAECn8eAAIZAAcKmgJeLgCMAAAZAAcKmgJeLgCMAAAAAA==.',
Cl='Clare:BAAANQABCgQIBAABNQAECgoKPwAGABAfAA==.Closetofsmut:BAAANQADCgcIBwABNQAECgYIBgACAAAAAA==.',
Cr='Craivan:BAAANQADCgUICQAAAA==.Crendoal:BAAANQAECgEIAQABNQAECgoKPgAaACcXAA==.Crilly:BAAANQAECgMJAwAAAA==.Crowley:BAAANQADCgQIBAAAAA==.Crumpler:BAABNQAECn8xAAIKAAkKrRBiiwCgAQAKAAkKrRBiiwCgAQAAAA==.Crüsnik:BAAANQADCgMIAwAAAA==.',
Cy='Cyroka:BAABNQAECn8bAAIbAAcKEgk/iQAEAQAbAAcKEgk/iQAEAQAAAA==.Cyrr:BAAANQAECgIIAgAAAA==.Cytroncutoff:BAAANQAECgYIDQAAAA==.',
Da='Dalastish:BAAANQADCggIDAAAAA==.Damia:BAABNQAECn8oAAMPAAgKMhWpWQCEAQAPAAgKMhWpWQCEAQAHAAMKnQx9fwC2AAAAAA==.Danobun:BAABNQAECn8xAAMTAAoK6R7+HwAMAwATAAoK6R7+HwAMAwAbAAEKLAfB9gAuAAAAAA==.Daring:BAAANQADCgEIAQAAAA==.Darkfoxcr:BAAANQAECgEIAQAAAA==.Darsithis:BAABNQAECn8dAAIIAAgKlgUUYwD1AAAIAAgKlgUUYwD1AAAAAA==.',
De='Deadite:BAABNQAECn8/AAIOAAoKtyAUCAACAwAOAAoKtyAUCAACAwAAAA==.Deadstealth:BAAANQADCgYIBgAAAA==.Delphirose:BAAANQABCggIDwABNQAECgcIEAACAAAAAA==.Delvarrieth:BAABNQAECn8eAAIVAAcK8g3+LgDuAAAVAAcK8g3+LgDuAAAAAA==.Demzy:BAAANQAECgcIDwAAAA==.Denth:BAAANQAECgMIBQAAAA==.Dercuur:BAACNQAFFH8LAAITAAQKpgxSEgDNAAATAAQKpgxSEgDNAAA1AAQKfy8AAhMACgp7GoBCAGsCABMACgp7GoBCAGsCAAAA.Devira:BAAANQADCgYICQAAAA==.Dezardez:BAAANQAECgYIBwAAAA==.',
Di='Displacer:BAAANQADCggICAAAAA==.',
Do='Dondeestasto:BAAANQADCgMIAwAAAA==.Dotur:BAAANQADCgIIAgAAAA==.',
Dr='Dragonkiss:BAAANQADCgQIBwAAAA==.Drainmee:BAAANQAECgcICAAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAABNQAECn8pAAIRAAoK4QsPQwDvAAARAAoK4QsPQwDvAAAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAABNQAECn8VAAIKAAkKfxI2fQC+AQAKAAkKfxI2fQC+AQAAAA==.',
Dv='Dva:BAAANQADCggICAAAAA==.',
['Dá']='Dárkbeard:BAAANQAECgIIBQAAAA==.',
Ea='Eazzekin:BAAANQAECgYIBwAAAA==.',
Ek='Ekneirg:BAABNQAECn80AAMKAAkKyxr5bwDcAQAKAAkK3Bn5bwDcAQAVAAcKrheaKwCAAQABNQAECgUIBQACAAAAAA==.',
El='Elleneilah:BAAANQADCgUICQAAAA==.Elynth:BAABNQAECn88AAIcAAoKUBbpMAA8AgAcAAoKUBbpMAA8AgAAAA==.',
Em='Emmalily:BAAANQAECgMIBwAAAA==.',
En='Endlessyueh:BAAANQAECgQIBwAAAA==.',
Ex='Extragrippy:BAABNQAECn8aAAIOAAgKORLDVwCUAQAOAAgKORLDVwCUAQAAAA==.',
Ey='Eyris:BAAANQAECgIIAwAAAA==.',
Fa='Faiesong:BAAANQABCgQIBAAAAA==.Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAABNQAECn89AAIZAAoKwRX/BwAdAgAZAAoKwRX/BwAdAgAAAA==.Fangren:BAAANQAECgEIAQAAAA==.Farrseer:BAABNQAECn8WAAIQAAYKBAoUVgA1AQAQAAYKBAoUVgA1AQAAAA==.Fasthandslez:BAAANQAECgQIBgAAAA==.',
Fe='Felscythe:BAABNQAECn8eAAIdAAcKdwL6GACWAAAdAAcKdwL6GACWAAAAAA==.Felynn:BAAANQAECggIEQAAAA==.',
Fi='Fierradin:BAAANQAECgQIAwABNQAECgoKJwAYAKIhAA==.Fierrastar:BAABNQAECn8nAAIYAAoKoiEfAwDrAgAYAAoKoiEfAwDrAgAAAA==.Finnius:BAAANQADCgMIBAAAAA==.Finshao:BAABNQAECn8aAAIeAAcKuRg2EQDhAQAeAAcKuRg2EQDhAQAAAA==.Fionn:BAAANQAECgMIAgABNQAECgcIEgACAAAAAA==.',
Fl='Flemish:BAABNQAECn8xAAITAAoKKxTrLwAEAgATAAoKKxTrLwAEAgAAAA==.Flextame:BAAANQADCggIIgAAAA==.Flipalicious:BAABNQAECn9RAAMTAAoKChYiLQATAgATAAoKChYiLQATAgAbAAkKIA7ilgBOAQAAAA==.Flipanomicon:BAAANQADCgYIFgAAAA==.Flipkicks:BAAANQADCgYICgAAAA==.Flipmode:BAAANQADCgcIEAAAAA==.Flipnasty:BAAANQADCgYICwAAAA==.Flipocalypse:BAAANQADCgYICgAAAA==.',
Fo='Foxwynn:BAAANQABCgQIBgAAAA==.',
Fr='Freyalise:BAABNQAECn8mAAMEAAkKHh0uMACiAQAEAAYKuxUuMACiAQAJAAcKhwIi0AC0AAAAAA==.Freyjah:BAAANQADCgUIBQAAAA==.Frostycarbon:BAAANQADCgYICwAAAA==.',
Fu='Furriousyueh:BAAANQAECgIIAgAAAA==.',
Ga='Gaia:BAABNQAECn8fAAIGAAgK+AmbrgA5AQAGAAgK+AmbrgA5AQAAAA==.Gallimaufrey:BAAANQAECgUICgAAAA==.Garodan:BAAANQADCgcIDQAAAA==.',
Ge='Gerbo:BAABNQAECn9BAAISAAoKDgx9bwDAAQASAAoKDgx9bwDAAQAAAA==.',
Gi='Gianavel:BAABNQAECn8zAAIaAAoKdQq3IwBkAQAaAAoKdQq3IwBkAQAAAA==.Ginodh:BAAANQAECgQIBgABNQAECgoKFQAZANUNAA==.Ginomage:BAABNQAECn8VAAMZAAoK1Q0mDAC8AQAZAAoK1Q0mDAC8AQASAAUKSAkKagHlAAAAAA==.Ginopally:BAAANQADCgMIAwABNQAECgoKFQAZANUNAA==.Ginoshaman:BAAANQADCgUIBgABNQAECgoKFQAZANUNAA==.Ginovoker:BAAANQADCgYICQABNQAECgoKFQAZANUNAA==.Gizelli:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.',
Gr='Grilled:BAAANQADCgYICwAAAA==.Grimoak:BAAANQAECgIIAwAAAA==.Gronke:BAAANQAECgQIBQABNQAECgUIBQACAAAAAA==.Grubetsella:BAABNQAECn8+AAQaAAoKJxdIFQABAgAaAAkKrBhIFQABAgAeAAgKGRFGHwAMAQAdAAUKnBHJFwCjAAAAAA==.Grugachur:BAABNQAECn8eAAIfAAgK3B03BwDiAQAfAAgK3B03BwDiAQAAAA==.',
Gu='Gustice:BAAANQADCgIJAgAAAA==.',
Gw='Gwenwyfar:BAAANQAECggICAAAAA==.',
Gy='Gyda:BAAANQAECgMIBgAAAA==.',
Ha='Hadooken:BAAANQABCgQIBAAAAA==.Hammerhead:BAAANQAECgEIAgAAAA==.Hangi:BAAANQADCgEIAQABNQAECgcIDQACAAAAAA==.Hanoumatoi:BAAANQAECgcIDwAAAA==.Haralambos:BAABNQAECn8VAAIVAAYK1gqBOwCrAAAVAAYK1gqBOwCrAAAAAA==.Harlar:BAAANQADCgYIDAAAAA==.Hasun:BAABNQAECn8hAAIKAAoK8R0lLQCgAgAKAAoK8R0lLQCgAgABNQAECgoKMQATAOkeAA==.',
He='Hehasnoname:BAAANQADCgYICQAAAA==.Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQAECgUIDAAAAA==.Heyokagi:BAAANQAECgcIBwAAAA==.',
Ho='Hordkilla:BAAANQAECgUIEQAAAA==.Hownowbrncw:BAABNQAECn8hAAIKAAkKhBHcrwBaAQAKAAkKhBHcrwBaAQAAAA==.',
Hy='Hyce:BAABNQAECn81AAQQAAkK1xRPLQCRAQAgAAgKlRPRKAD9AQAQAAgKqQ9PLQCRAQANAAMK/hiWHQDmAAAAAA==.Hymno:BAAANQADCgYICQAAAA==.',
Ih='Ihavenoname:BAAANQADCgYJCwAAAA==.',
Il='Illusionous:BAAANQAECgMIBgAAAA==.',
In='Insoniacyun:BAAANQAECgQIBwAAAA==.',
Is='Isaak:BAAANQAECgEIAQAAAA==.Iselian:BAAANQAECggIJgAAAQ==.Istrix:BAAANQADCgUJBQAAAA==.',
Ja='Jadefeather:BAAANQAECggIEwAAAA==.',
Jb='Jbelbueno:BAAANQAECgIIBQAAAA==.Jblockiv:BAAANQAECgMIAwAAAA==.Jbprimero:BAAANQAECgcIBQAAAA==.Jbshami:BAABNQAECn8qAAIbAAoKsht3RQBLAgAbAAoKsht3RQBLAgAAAA==.',
Je='Jeman:BAAANQAECgEIAQAAAA==.Jenaelle:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAABNQAECn8yAAISAAkKiAOiwAAUAQASAAkKiAOiwAAUAQAAAA==.Jetfires:BAABNQAECn9MAAIGAAoKSB8ZJQCdAgAGAAoKSB8ZJQCdAgAAAA==.',
Ji='Jinger:BAABNQAECn8kAAIaAAgKsgU6MwDuAAAaAAgKsgU6MwDuAAAAAA==.Jinnwoo:BAAANQADCgUIBgAAAA==.',
Jo='Jonn:BAAANQAECgMIBQAAAA==.Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQAECgEIAwAAAA==.',
Ju='Juggernacht:BAAANQAECgEIAwABNQAECgoKKgAJAIsZAA==.',
Ka='Kaedren:BAAANQADCggIGgAAAA==.Kaelorien:BAABNQAECn8iAAIeAAkKqQs/GgBJAQAeAAkKqQs/GgBJAQAAAA==.Kaitja:BAAANQADCgIIAgAAAA==.Kalazaad:BAABNQAECn81AAIVAAoKYQkxIwA/AQAVAAoKYQkxIwA/AQAAAA==.Kaldevayn:BAABNQAECn8bAAMKAAgKDAgJ4gAEAQAKAAgKDAgJ4gAEAQABAAMKcxMXrgCvAAAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalrow:BAABNQAECn8rAAMgAAoKBg0yHQCnAQAgAAoKBg0yHQCnAQAQAAEKAABVnwAgAAAAAA==.Kalto:BAAANQAECgIIBQAAAA==.Kalyna:BAAANQAECgUICgAAAA==.Kanhoa:BAAANQAECgQIBAAAAA==.Kardanika:BAAANQAECgYICgAAAA==.Kardanis:BAABNQAECn85AAIbAAoKMB7oFAD+AgAbAAoKMB7oFAD+AgAAAA==.Karyudo:BAAANQAECgEIAQAAAA==.Kashe:BAAANQAECgcIEgAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAABNQAECn8mAAIZAAgK5hU5CgAoAgAZAAgK5hU5CgAoAgAAAA==.Katavia:BAABNQAECn8/AAIbAAoKDA5aTwC9AQAbAAoKDA5aTwC9AQAAAA==.Kathii:BAAANQAECgYIDwAAAA==.Katrazath:BAABNQAECn8gAAIhAAgK6wfcEwDkAAAhAAgK6wfcEwDkAAAAAA==.Kaydencia:BAAANQABCgUICAAAAA==.',
Ke='Keledras:BAAANQAECgUIBAAAAA==.Kelmmers:BAAANQAECgcICAAAAA==.Kelân:BAAANQAECgMIBQAAAA==.Keyallandron:BAABNQAECn8cAAIGAAYKmAcAwQAVAQAGAAYKmAcAwQAVAQAAAA==.Keywi:BAAANQAECgcICgAAAA==.',
Kh='Khaleesie:BAAANQAECgEIBAAAAA==.Khiana:BAAANQADCgIIAgABNQAECgoKPwAGABAfAA==.Khrin:BAAANQADCgYIFQAAAA==.',
Ki='Kiddow:BAABNQAECn8YAAIZAAYKvAwiIADCAAAZAAYKvAwiIADCAAAAAA==.Kierea:BAAANQADCgcIEgAAAA==.Kiiarah:BAAANQAECgcIEwAAAA==.Killrah:BAAANQADCgQIBAAAAA==.Kilrah:BAAANQADCggIEAAAAA==.Kilriella:BAAANQADCgYIBwAAAA==.Kinte:BAAANQAECgEIBAAAAA==.Kitamii:BAAANQAECggIEQAAAA==.Kitaña:BAAANQAECgEIAgAAAA==.Kivrin:BAABNQAECn8cAAIEAAYKIgYdPQCpAAAEAAYKIgYdPQCpAAAAAA==.Kiára:BAAANQADCggIDQAAAA==.',
Ko='Kokujin:BAABNQAECn8vAAITAAkK5BW6TwCDAQATAAkK5BW6TwCDAQAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAABNQAECn8pAAIGAAoKciDqIgCmAgAGAAoKciDqIgCmAgAAAA==.',
Ku='Kurumi:BAAANQAECgEIAQAAAA==.',
Kw='Kwo:BAABNQAECn8gAAIdAAgKWwiJEQD3AAAdAAgKWwiJEQD3AAAAAA==.',
Ky='Kymma:BAABNQAECn8sAAIKAAkKhAocpgBsAQAKAAkKhAocpgBsAQAAAA==.',
La='Laviz:BAAANQADCgYIBwABNQAECgoKMQATAOkeAA==.Laz:BAAANQADCgUICgAAAA==.Lazengann:BAABNQAECn8uAAMgAAoKwRxYFQC6AgAgAAkKmx5YFQC6AgAQAAIKyQ84fgA0AAAAAA==.',
Le='Leafbane:BAABNQAECn9LAAQIAAkKDRr9IwBxAgAIAAkKDRr9IwBxAgARAAMKTxCMTgC9AAAOAAEK4BbNwQBFAAAAAA==.Legevia:BAABNQAECn8aAAITAAcKQQWRkQDRAAATAAcKQQWRkQDRAAAAAA==.Leilau:BAAANQAECggIAgAAAA==.Leiris:BAABNQAECn8yAAMKAAkKDw2AnQB8AQAKAAkKDw2AnQB8AQABAAEKoQAbOwEZAAAAAA==.Lejusticier:BAAANQADCggIDAAAAA==.Leonaa:BAAANQADCggIHAAAAA==.Letifer:BAAANQADCgcIBwAAAA==.Leucetios:BAAANQAECgUIDQAAAA==.',
Li='Liarace:BAAANQAECggIEgAAAA==.Lightbeard:BAAANQAECgUIEwAAAA==.Lightforge:BAABNQAECn8VAAIKAAkKoBRskwD9AQAKAAkKoBRskwD9AQAAAA==.Lionessi:BAAANQADCgcIBwAAAA==.Lithika:BAAANQADCgYIBgAAAA==.',
Lo='Lorredain:BAAANQADCgcIDgAAAA==.Lothaire:BAAANQAECgMIBAAAAA==.Lothwen:BAAANQAECgQICQAAAA==.Louisachan:BAAANQAECgIIAgAAAA==.',
Lu='Lucamar:BAAANQADCgQIBAAAAA==.Luxinine:BAABNQAECn89AAIEAAoKLB1tFADBAgAEAAoKLB1tFADBAgAAAA==.',
Ly='Lyshai:BAAANQAECgUIBQABNQAECgkJIwAhAP8cAA==.',
Ma='Madhawi:BAAANQAECgEIBwAAAA==.Magamon:BAABNQAECn8/AAISAAoK5RH9YQDiAQASAAoK5RH9YQDiAQAAAA==.Magnix:BAAANQADCgQIBAABNQAECgYIFAAOABkeAA==.Malfuriia:BAABNQAECn8eAAIbAAcK+BDTYwB0AQAbAAcK+BDTYwB0AQAAAA==.Mamboke:BAABNQAECn8uAAMGAAkKwQ7ZbwDFAQAGAAkKwQ7ZbwDFAQAiAAQKVgKIaQCHAAAAAA==.Margerdria:BAAANQADCgcIEAAAAA==.Mauugrim:BAABNQAECn8eAAMRAAgKNQepSADUAAARAAcK5wapSADUAAAIAAgK2QQ/cwC/AAAAAA==.Maxowen:BAABNQAECn8eAAIKAAcKzRVfwQA6AQAKAAcKzRVfwQA6AQAAAA==.Maxxramas:BAAANQADCgcICgAAAA==.',
Me='Mearadan:BAABNQAECn8lAAIbAAoKJAl7kgBaAQAbAAoKJAl7kgBaAQAAAA==.Meatsweats:BAAANQAECgYIBgAAAA==.Megg:BAAANQAECgUIBgAAAA==.Mekh:BAABNQAECn8jAAMhAAkK/xyLBQBUAgAhAAkK/xyLBQBUAgAjAAEK0x5QNABMAAAAAA==.Mel:BAAANQADCgcIGwAAAA==.Melanara:BAABNQAECn8vAAIZAAoKfw9VDgDGAQAZAAoKfw9VDgDGAQAAAA==.Melstrom:BAAANQAECgQICQAAAA==.Meticuluslyn:BAAANQAECgQIBgAAAA==.',
Mi='Milkmaiden:BAAANQAECgEIAgAAAA==.Milkthisbull:BAAANQADCgMIAwAAAA==.Minxminx:BAEANQAECgEIAgAAAA==.Mixler:BAABNQAECn8bAAISAAkKPAednwBSAQASAAkKPAednwBSAQAAAA==.',
Mm='Mmeow:BAAANQADCgYIEAABNQAECgoKLwAGAH4cAA==.',
Mo='Moirine:BAABNQAECn8eAAMFAAcKsBZWBgBzAQAFAAYKgxVWBgBzAQAEAAUKjhuCRwABAQAAAA==.Moonflowers:BAAANQAECggICQAAAA==.',
Mu='Murdrmitts:BAABNQAECn8WAAIMAAUKcwjTJQDfAAAMAAUKcwjTJQDfAAAAAA==.Mustikka:BAAANQAECgYIDwAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Myuriyanka:BAABNQAECn9CAAITAAoKFBETOwDSAQATAAoKFBETOwDSAQAAAA==.',
['Mæ']='Mælstrôm:BAAANQABCgQICAAAAA==.',
Na='Naahommii:BAAANQADCgUIBQAAAA==.Nachtamus:BAAANQAECgIIAgABNQAECgoKKgAJAIsZAA==.Nachtkampfer:BAAANQAECgEIAwABNQAECgoKKgAJAIsZAA==.Nachtkreiger:BAAANQABCgEIAQABNQAECgoKKgAJAIsZAA==.Nachtpranke:BAAANQAECgIIBgABNQAECgoKKgAJAIsZAA==.Nachtteufel:BAAANQAECgEIAwABNQAECgoKKgAJAIsZAA==.Naeri:BAABNQAECn8oAAILAAgKFhVFHgDxAQALAAgKFhVFHgDxAQAAAA==.Nagualli:BAAANQAECgUIDAAAAA==.Naieve:BAABNQAECn8pAAIWAAoKIxJQQAD5AQAWAAoKIxJQQAD5AQAAAA==.Nastii:BAAANQADCgEIAQAAAA==.Nastychungus:BAABNQAECn8sAAMTAAkKLCKVGAA1AwATAAkKLCKVGAA1AwAbAAUK6AM60wDAAAAAAA==.Navira:BAAANQADCggIHgAAAA==.',
Ne='Negargra:BAABNQAECn8oAAIcAAoKcQq+YACfAQAcAAoKcQq+YACfAQAAAA==.Nekoda:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Nephadin:BAAANQAECgEIAQAAAA==.Nephilim:BAAANQAECgYIBQAAAA==.Neyvin:BAAANQADCggICAAAAA==.',
Ni='Niduun:BAAANQABCggICAAAAA==.Nightfend:BAAANQADCgcICwAAAA==.Nighttiger:BAAANQAECgYIEAAAAA==.Nikooli:BAABNQAECn8eAAMQAAcK2Q0nQgAUAQAQAAcK2Q0nQgAUAQANAAEKygU4MgAfAAAAAA==.',
No='Noopsie:BAABNQAECn8uAAILAAcKBBY2IgDJAQALAAcKBBY2IgDJAQAAAA==.Nooters:BAABNQAECn84AAIIAAoK8iMMBwBzAwAIAAoK8iMMBwBzAwABNQAFFAcIGwAhADciAA==.Norrina:BAAANQABCgEIAQAAAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAABNQAECn8kAAMJAAkKth05MgBjAgAJAAkKth05MgBjAgAEAAcKVRf1HACSAQAAAA==.',
Nu='Nunavutt:BAAANQADCgUIBQAAAA==.',
Ny='Nyteweaver:BAABNQAECn8cAAIKAAcKDhGq0gAdAQAKAAcKDhGq0gAdAQAAAA==.',
Ob='Oberonny:BAAANQAECgQIBAAAAA==.',
Od='Oderica:BAAANQAECggIEAAAAA==.Odurn:BAAANQADCgYIBgAAAA==.',
Og='Ogafor:BAAANQAECgEIAgAAAA==.Ogayac:BAAANQAECgEIBAAAAA==.',
Oh='Ohminous:BAAANQAECgcIDgAAAA==.',
Or='Oranash:BAAANQADCgMIAwAAAA==.Orici:BAAANQAECgIIAgABNQAECgIIBQACAAAAAA==.Ornir:BAAANQADCgMIAwAAAA==.Orongosh:BAAANQADCgYIBgAAAA==.',
Os='Oscarmikey:BAABNQAECn8zAAMWAAoKPBVqNgA4AgAWAAoKPBVqNgA4AgALAAcKuxPmLgBcAQAAAA==.Oshu:BAAANQADCgcIBgAAAA==.',
Ot='Ottoshot:BAABNQAECn8eAAIGAAcKmQy0ugAhAQAGAAcKmQy0ugAhAQAAAA==.Otum:BAAANQAECgMIDAAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
Ox='Oxmantle:BAAANQAECgMIBAAAAA==.',
['Oö']='Oöps:BAABNQAECn8cAAILAAcKRgf1RADXAAALAAcKRgf1RADXAAAAAA==.',
Pa='Paksen:BAAANQAECgYIBgAAAA==.Panamone:BAAANQAECgUIBwAAAA==.Pandamaster:BAABNQAECn8UAAISAAoKLxWFyQDyAQASAAoKLxWFyQDyAQAAAA==.Paulee:BAAANQAECgEIAQAAAA==.',
Pe='Pendragon:BAAANQADCgQIBQAAAA==.Pesch:BAAANQAECggICAAAAA==.',
Ph='Phylah:BAABNQAECn8ZAAMbAAYKPxTIcwBBAQAbAAYKPxTIcwBBAQATAAEKAABvUQElAAAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Porterhouze:BAAANQABCgIIAgABNQAECgcIJQAkAIwEAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.Prophetofham:BAAANQADCgYIBgAAAA==.',
Pu='Puchi:BAACNQAFFH8XAAIeAAcK6xT5AwCpAQAeAAcK6xT5AwCpAQA1AAQKfzwAAh4ACgohIokEAF0DAB4ACgohIokEAF0DAAAA.Pug:BAAANQAECgEIAQABNQAECgkJHwAHAI8ZAA==.',
Py='Pyrocles:BAAANQABCgQICQAAAA==.',
Qa='Qadhira:BAAANQAECgYIAQABNQADCgYICwACAAAAAA==.Qadhiræ:BAAANQAECgMIBQABNQADCgYICwACAAAAAA==.',
['Qæ']='Qædhira:BAAANQADCgYICwAAAA==.',
Ra='Raez:BAABNQAECn8bAAIbAAgKsw4MaQBiAQAbAAgKsw4MaQBiAQAAAA==.Ragnerock:BAAANQAECgMIBQAAAA==.Raynecira:BAABNQAECn8dAAIGAAgKgAySmABnAQAGAAgKgAySmABnAQAAAA==.',
Re='Reihino:BAAANQAECgYIBgAAAA==.Remixidora:BAAANQAECgQJCQABNQAFFAYICAASAOQbAA==.Reyrocko:BAAANQAECgEIAgAAAA==.Rezdh:BAAANQAECgYIDwABNQAFFAIIBQASADwTAA==.Rezmage:BAACNQAFFH8FAAMSAAIKPBP5QwBOAAASAAEKhhb5QwBOAAAZAAEK8g9xFABEAAA1AAQKfx0ABBIACgq1HBp0ALQBABIACAqSGRp0ALQBABkABQoAFicYAAcBACUAAQqtEisMADcAAAAA.Reznal:BAAANQAECgMIAwABNQAFFAIIBQASADwTAA==.Rezvoker:BAAANQADCgUJCgABNQAFFAIIBQASADwTAA==.',
Rh='Rhage:BAAANQADCgcIGgAAAA==.Rhoaias:BAAANQAECgEIAQAAAA==.Rhunyaye:BAAANQAECgEIAQAAAA==.',
Ri='Rickness:BAAANQAECgIIBAAAAA==.Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokform:BAAANQAECgYIBgAAAA==.Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQAECgEIAQAAAA==.Rottingturky:BAAANQAECggIEgAAAA==.Roxane:BAABNQAECn8iAAIWAAkKQAfeOgAvAQAWAAkKQAfeOgAvAQAAAA==.',
Ru='Rubyace:BAAANQAECgUIDQAAAA==.Runningelk:BAABNQAECn8sAAImAAkK9RwwEABeAgAmAAkK9RwwEABeAgAAAA==.Runscapemain:BAABNQAECn8lAAIKAAgK1AlktwCvAQAKAAgK1AlktwCvAQAAAA==.',
Ry='Ryeti:BAAANQADCggINAAAAA==.Ryuzu:BAAANQAECgUIBQAAAA==.Ryydia:BAAANQADCgMIBQAAAA==.',
Sa='Sableanne:BAAANQAECgQICQAAAA==.Sahalia:BAAANQAECgQIBAAAAA==.Saintulrick:BAAANQAECgUICAAAAA==.Sajuice:BAABNQAECn8cAAMGAAkKFRsgSwCMAgAGAAkKFRsgSwCMAgAiAAQKKRRDUQDlAAAAAA==.Salow:BAAANQAECgEIAwAAAA==.Sanitas:BAABNQAECn8vAAMJAAoKChB1WgASAgAJAAoKChB1WgASAgAEAAQK3QKxTABmAAAAAA==.Sanivar:BAAANQADCgYIBgABNQAECgoKJAAFAE4ZAA==.',
Se='Seeyen:BAACNQAFFH8KAAIGAAQKDhKeEwAsAQAGAAQKDhKeEwAsAQA1AAQKfz8AAgYACgoqI/MOAGoDAAYACgoqI/MOAGoDAAAA.Sej:BAAANQAECgEIAwAAAA==.Seraphon:BAAANQADCggIJAAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAACAAAAAA==.Serenityhate:BAAANQAECgQIBAAAAA==.',
Sh='Shaaydo:BAAANQAECgEIAQAAAA==.Shaayllee:BAAANQAECgQIBwAAAA==.Shaaytheyha:BAABNQAECn8lAAIKAAcKpAfZ7ABCAQAKAAcKpAfZ7ABCAQAAAA==.Shaggyp:BAACNQAFFH8QAAIJAAQKnxE5GAAgAQAJAAQKnxE5GAAgAQA1AAQKfyMAAgkACgqrEIdOAOkBAAkACgqrEIdOAOkBAAAA.Shamump:BAAANQADCgcIBwAAAA==.Sharington:BAAANQADCgUIBQAAAA==.Sharyl:BAAANQABCgcIEQAAAA==.Shehasnoname:BAAANQADCgYIGAAAAA==.Shehulk:BAAANQAECgUIDgAAAA==.Shingo:BAAANQADCgcIBwABNQAECgoKPwAIABYgAA==.Ships:BAABNQAECn8fAAIjAAoKnRU0FwBFAgAjAAoKnRU0FwBFAgAAAA==.',
Si='Silf:BAAANQAECgIIBQAAAA==.Silverapples:BAAANQADCgIIAgAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skibbward:BAAANQAECgEIAQABNQAFFAcIEgAVALITAA==.Skrektwo:BAABNQAECn8vAAMbAAgKlBRgaABlAQAbAAgKlBRgaABlAQATAAUK4gVs2wDeAAAAAA==.',
Sm='Smackdogg:BAACNQAFFH8MAAIWAAUKQSDQDQCNAQAWAAUKQSDQDQCNAQA1AAQKfx0AAhYACQrKJAEUACcDABYACQrKJAEUACcDAAAA.',
So='Solarspark:BAAANQAECgYIEQAAAA==.Sondaladan:BAAANQADCggIGgAAAA==.Sonomonom:BAAANQAECgEIAQAAAA==.Soota:BAAANQAECgEIBAAAAA==.Sorvina:BAABNQAECn8+AAIcAAoKdQ63UgDIAQAcAAoKdQ63UgDIAQAAAA==.Soulflame:BAABNQAECn9FAAIZAAoKtwojEAClAQAZAAoKtwojEAClAQAAAA==.Soulkings:BAAANQADCggIGgAAAA==.',
Sp='Spriggs:BAAANQADCgUIBAAAAA==.',
St='Starpath:BAAANQAECgMIAwABNQAECgcIDQACAAAAAA==.Strangr:BAAANQADCggICwABNQAECgoKSgAaABUgAA==.Stregnor:BAABNQAECn8lAAIGAAgK2xD6hACTAQAGAAgK2xD6hACTAQAAAA==.Styggi:BAAANQADCggICAAAAA==.Stygy:BAAANQADCgcIBwABNQADCggICAACAAAAAA==.',
Su='Sumyunguy:BAABNQAECn8aAAIaAAcKwBa8LwCZAQAaAAcKwBa8LwCZAQAAAA==.',
Sy='Syllenne:BAAANQABCgMIAwAAAA==.Sylunia:BAABNQAECn8YAAIZAAcK2QMeHwDxAAAZAAcK2QMeHwDxAAAAAA==.Sylváñás:BAAANQAECgEIAgAAAA==.Syrintha:BAAANQADCgYIDAAAAA==.',
Ta='Tachi:BAAANQAECgUIEAABNQAECgkJJAAIANMRAA==.Tachie:BAABNQAECn8oAAIhAAgKPRgNDACDAQAhAAgKPRgNDACDAQABNQAECgkJJAAIANMRAA==.Tairi:BAAANQABCgMIBQAAAA==.Talonclaw:BAAANQAECgEIAQAAAA==.Talön:BAEANQAECgUJBgAAAA==.Tarvah:BAAANQADCgYIBgAAAA==.',
Te='Teranox:BAAANQAECgEIBgAAAA==.Tezzerae:BAABNQAECn8YAAIGAAcKsQKZ+QCkAAAGAAcKsQKZ+QCkAAAAAA==.',
Th='Thaesan:BAAANQAECgQICAAAAA==.Theistica:BAABNQAECn8jAAIVAAgKNQu0LQD2AAAVAAgKNQu0LQD2AAAAAA==.Theomir:BAAANQAECgIIAQAAAA==.Therin:BAABNQAECn81AAMYAAoK9BHaBQDXAQAYAAoK9BHaBQDXAQAiAAcKBwYORAA4AQAAAA==.Thodi:BAAANQAECgEIAQAAAA==.',
Ti='Tillymonick:BAAANQAECgQIBwAAAA==.',
To='Todes:BAAANQADCgIIAgAAAA==.Tongshi:BAAANQABCggIDAAAAA==.Toofast:BAABNQAECn82AAIbAAkK3B8/EwAMAwAbAAkK3B8/EwAMAwAAAA==.Toofurrious:BAAANQADCgQIBgAAAA==.Toolotems:BAAANQAECgUICQAAAA==.Topswimmer:BAAANQABCgIIAgAAAA==.',
Tr='Trifus:BAAANQAECgYIBgAAAA==.',
Tu='Tulao:BAABNQAECn8hAAISAAoKZRg6NgBfAgASAAoKZRg6NgBfAgABNQAECgoKMQATAOkeAA==.',
Ty='Tylae:BAAANQADCgQIBwAAAA==.',
Ut='Utheli:BAABNQAECn9AAAIKAAoKBCD5IADUAgAKAAoKBCD5IADUAgAAAA==.',
Va='Vaevictis:BAAANQAECgEIAQABNQAECgkJJgAEAB4dAA==.Vaeyethir:BAAANQABCgcICAAAAA==.Vaildora:BAABNQAECn8kAAMIAAkK0xEfKgD4AQAIAAkKsREfKgD4AQAOAAQKuA7kbACPAAAAAA==.Valdra:BAABNQAECn8sAAIXAAkKJBfwDgCwAQAXAAkKJBfwDgCwAQAAAA==.Valkyl:BAAANQADCgMIBQAAAA==.Valkyll:BAAANQADCgIIBAAAAA==.Valkylpal:BAAANQADCgEIAQAAAA==.Valord:BAAANQADCgcIBwAAAA==.Vane:BAAANQADCgEIAQAAAA==.Vanillacain:BAAANQADCgMIAwAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgcIHQAAAA==.',
Vl='Vlonet:BAABNQAECn85AAMgAAkKYRVIGQDTAQAgAAkKYRVIGQDTAQAQAAEK7QholwAuAAAAAA==.',
Vn='Vnasty:BAAANQAECgQIBwABNQAECgkJLAATACwiAA==.',
Vo='Vokola:BAAANQAECgQIBgABNQAECgkJJAAIANMRAA==.',
Wa='Warthexn:BAAANQAECgQIBAAAAA==.',
We='Wehadnoname:BAAANQABCgEIAQAAAA==.Weshalas:BAAANQAECgMIAwAAAA==.',
Wh='Whelp:BAAANQAECgIIAgAAAA==.',
Wi='Wilken:BAAANQAECgcIEwAAAA==.Wilohart:BAAANQABCgMIAwAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwACAAAAAA==.Wiva:BAAANQAECgQIBgAAAA==.',
Wo='Wolfsokol:BAABNQAECn8aAAQOAAoKwxitQwDsAQAOAAcK0R6tQwDsAQAIAAMKiwUjigB8AAARAAEKAAD+ngAAAAABNQAFFAkJFAAjAJgdAA==.',
Wr='Wreckoner:BAABNQAECn8/AAIVAAoKQxNjEwDdAQAVAAoKQxNjEwDdAQAAAA==.',
Xa='Xannah:BAAANQAECgMIAgAAAA==.Xavencia:BAAANQADCgYICgAAAA==.',
Xi='Xinthos:BAAANQAECgYICAAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Yu='Yukiakari:BAAANQAECgEIAQAAAA==.',
Za='Zaderan:BAAANQADCgYIGwAAAA==.Zakainu:BAABNQAECn8hAAIUAAoKsBaDFwCAAQAUAAoKsBaDFwCAAQAAAA==.Zallister:BAAANQADCggIKAAAAA==.Zansarutobi:BAAANQABCgYICAAAAA==.Zarathoszan:BAABNQAECn8zAAIGAAoKHwslYQDrAQAGAAoKHwslYQDrAQAAAA==.Zarkra:BAAANQAECgYIDAABNQAECgkJLAAmAPUcAA==.',
Ze='Zedator:BAABNQAECn8iAAIYAAgKORiQBQBhAgAYAAgKORiQBQBhAgAAAA==.Zedraikis:BAAANQADCgEIAQABNQADCggIEAACAAAAAA==.Zelgaddis:BAABNQAECn8uAAIbAAoKHRS/agDLAQAbAAoKHRS/agDLAQAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zh='Zhansaya:BAAANQAECgIIBQABNQAECgQIBAACAAAAAA==.',
Zr='Zriana:BAAANQAECgQIDwAAAA==.',
Zs='Zsarilya:BAABNQAECn8oAAMJAAgKdAI3oADkAAAJAAgKdAI3oADkAAAEAAEKAAAweQAAAAAAAA==.',
Zu='Zurgen:BAABNQAECn88AAIcAAoKGxwyKABgAgAcAAoKGxwyKABgAgAAAA==.',
['Àn']='Àndrol:BAABNQAECn8jAAISAAkKaA0plgBmAQASAAkKaA0plgBmAQABNQAFFAcIEwAgAHUPAA==.',
['Ás']='Áshe:BAAANQAECgIIAgAAAA==.',
['Êc']='Êclipse:BAEBNQAECn89AAILAAoKtR1bCwAAAwALAAoKtR1bCwAAAwAAAA==.',
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
