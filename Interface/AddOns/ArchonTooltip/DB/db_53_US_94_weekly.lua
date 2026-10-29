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

local lookup = {'Paladin-Holy','Unknown-Unknown','Warrior-Arms','Priest-Shadow','Priest-Discipline','Hunter-BeastMastery','Rogue-Assassination','DeathKnight-Frost','Priest-Holy','Paladin-Retribution','Druid-Restoration','Druid-Feral','DemonHunter-Vengeance','DeathKnight-Blood','Mage-Arcane','DemonHunter-Havoc','Evoker-Devastation','DeathKnight-Unholy','Shaman-Elemental','Shaman-Enhancement','Rogue-Subtlety','Paladin-Protection','Druid-Balance','Hunter-Survival','Mage-Frost','Monk-Windwalker','Shaman-Restoration','Warlock-Demonology','Monk-Brewmaster','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Devourer','Hunter-Marksmanship','Evoker-Preservation','Warlock-Destruction','Mage-Fire','Druid-Guardian','Warrior-Protection',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aarchon:BAABNQAECn8wAAIBAAgKNx7MHQBWAgABAAgKNx7MHQBWAgAAAA==.',
Ad='Aduin:BAAANQAECgcICwAAAA==.',
Ae='Aedarelyn:BAAANQAECgQICwAAAA==.Aellita:BAAANQAECgMIAwAAAA==.Aenoryae:BAAANQADCgYIBgABNQADCgYICwACAAAAAA==.Aeschylus:BAAANQAECgIIAgAAAA==.Aeson:BAAANQAECgIIAgAAAA==.',
Af='Afkinlife:BAAANQAECgEIAQAAAA==.',
Ai='Aias:BAAANQADCgcIBwAAAA==.',
Ak='Akky:BAABNQAECn8eAAIDAAkKBhc0iwAAAgADAAkKBhc0iwAAAgAAAA==.Aksafiya:BAABNQAECn9OAAMEAAkKuhGuEwCRAQAEAAkKuhGuEwCRAQAFAAEK5QGHMQAgAAAAAA==.',
Al='Alal:BAAANQADCgYIFQAAAA==.Alaras:BAACNQAFFH8KAAIEAAUKVgvcDAASAQAEAAUKVgvcDAASAQA1AAQKfyEAAgQACgrgFCIVALgCAAQACgrgFCIVALgCAAAA.Aleesha:BAAANQAECgEIAgAAAA==.Alissia:BAAANQAECgEIAgAAAA==.Allaras:BAAANQAECgEIAQAAAA==.Allistaris:BAABNQAECn8gAAIGAAkKpRdVZwBFAgAGAAkKpRdVZwBFAgAAAA==.Allrianne:BAAANQAECgEIAQAAAA==.Alluriela:BAAANQADCgIIAwAAAA==.Allyriae:BAAANQAECggIDwAAAA==.Alphard:BAAANQAECgQIBAABNQAECgkJHwAHAI8ZAA==.Alphá:BAABNQAECn8gAAIIAAkKMwtaSgCRAQAIAAkKMwtaSgCRAQAAAA==.Althoraty:BAABNQAECn8mAAIJAAkKDRadNwDaAQAJAAkKDRadNwDaAQAAAA==.Alyx:BAAANQAECgEIBQAAAA==.',
Am='Amberlilly:BAABNQAECn8aAAIKAAYKTAfS0gC/AAAKAAYKTAfS0gC/AAAAAA==.',
An='Andoros:BAABNQAECn8rAAMLAAoKZx8vBgAJAwALAAkKCSIvBgAJAwAMAAEK3wXvOQAQAAAAAA==.Angelon:BAAANQADCgQIBgAAAA==.Antaak:BAAANQAECgEIAQAAAA==.Antilles:BAAANQADCgMIAwAAAA==.Anzurath:BAABNQAECn8oAAIKAAgKuQ6WfgBUAQAKAAgKuQ6WfgBUAQAAAA==.',
Ap='Apheron:BAABNQAECn8vAAINAAoKoSKyAQDfAgANAAoKoSKyAQDfAgAAAA==.Apollimy:BAAANQAECggIBgAAAA==.Applebow:BAABNQAECn8bAAIOAAYKxxT6XwByAQAOAAYKxxT6XwByAQAAAA==.Apples:BAAANQAECgUIBQAAAA==.',
Ar='Arathwr:BAAANQADCgcIBwABNQAECgQICwACAAAAAA==.Ardalel:BAAANQADCgcICAAAAA==.Arknova:BAABNQAECn8iAAIKAAkKNBjVfAAxAgAKAAkKNBjVfAAxAgAAAA==.Armas:BAAANQAECgEIAgAAAA==.Arylin:BAAANQAECgIIBQAAAA==.',
As='Asheram:BAAANQADCgEIAQAAAA==.Ashkinassi:BAEANQADCgUIBgAAAA==.Asiain:BAAANQAECgUIBwABNQAFFAUICQADADsPAA==.Asmin:BAAANQAECgYICQABNQAECgkJIwAPAEggAA==.Asnabel:BAABNQAECn8cAAIIAAcKowftSwDmAAAIAAcKowftSwDmAAAAAA==.',
At='Atsa:BAAANQADCgQIBAAAAA==.Atvar:BAAANQADCggICAAAAA==.',
Au='Aurelith:BAAANQAECgcIDgAAAA==.Autumndeath:BAAANQAECgMIBQAAAA==.',
Av='Avinger:BAAANQABCggIGQAAAA==.',
Ay='Ayden:BAABNQAECn8iAAMNAAgKoROeDgDPAQANAAgKoROeDgDPAQAQAAEKmA1pagAyAAAAAA==.',
Az='Azorain:BAAANQADCgQIBAAAAA==.Azrim:BAAANQADCgYIDgABNQAECgQIBwACAAAAAA==.Azureis:BAAANQADCgcICAAAAA==.',
Ba='Babaganouj:BAAANQAECgEIAgABNQAECgQICgACAAAAAA==.Balolz:BAAANQAECgEIAgAAAA==.',
Be='Belthar:BAABNQAECn8cAAIOAAgKGBRtTwC3AQAOAAgKGBRtTwC3AQAAAA==.Bendeye:BAAANQADCgYIDgAAAA==.',
Bl='Blee:BAAANQAECgQIDAAAAA==.Bluudclaaw:BAAANQADCgMIAwABNQAECggIIgARAFUYAA==.',
Bo='Boing:BAABNQAECn8fAAIHAAkKjxkCJgBcAgAHAAkKjxkCJgBcAgAAAA==.Bondad:BAAANQAECgUIBwABNQAECgcIDgACAAAAAA==.Boomhauer:BAABNQAECn8bAAIGAAYKFxnNoADFAQAGAAYKFxnNoADFAQAAAA==.',
Br='Braelia:BAABNQAECn8VAAISAAcKHg6DaQBsAQASAAcKHg6DaQBsAQAAAA==.Braetwo:BAAANQABCggJDwABNQAECgcIFQASAB4OAA==.Braughm:BAAANQADCgUJBQAAAA==.Braxius:BAAANQADCgMIAwABNQAECggINAAPAHUfAA==.Breye:BAABNQAECn8VAAITAAgKdAW0pwBFAQATAAgKdAW0pwBFAQAAAA==.Brightstone:BAAANQAECgIIAgABNQAECgQICwACAAAAAA==.Brindria:BAAANQADCgQIBgAAAA==.Brood:BAAANQAECgUIEwABNQAECgYIEAACAAAAAA==.Brundles:BAABNQAECn8wAAIKAAgKwgdmzwB8AQAKAAgKwgdmzwB8AQAAAA==.',
Bu='Bubblepopper:BAABNQAECn8VAAIJAAYKBCFBVgAgAgAJAAYKBCFBVgAgAgAAAA==.Bunky:BAABNQAECn8YAAIUAAYKagTRJwDnAAAUAAYKagTRJwDnAAAAAA==.',
Ca='Cailaranel:BAABNQAECn8hAAIVAAkKHguSOACFAQAVAAkKHguSOACFAQAAAA==.Calaul:BAABNQAECn8qAAMKAAkK7QymowDZAQAKAAgKsw6mowDZAQAWAAEKSwK4VgAbAAAAAA==.Calenbraga:BAABNQAECn8eAAMMAAYKgRvgDgA9AQAMAAYKgRvgDgA9AQAXAAEKAACFggAAAAAAAA==.Calisim:BAAANQAECgQICgAAAA==.Caloh:BAAANQAECgUIEwAAAA==.Cantholdagro:BAAANQAECgEIAQABNQAECggIEwACAAAAAA==.Cassamaria:BAABNQAECn8jAAIYAAkK6xCwBACbAQAYAAkK6xCwBACbAQAAAA==.Cataryn:BAABNQAECn8wAAIGAAgK0R9bMwDSAgAGAAgK0R9bMwDSAgAAAA==.Catt:BAABNQAECn8sAAIBAAkK2Q9nOgCxAQABAAkK2Q9nOgCxAQAAAA==.Cattlerage:BAAANQADCgYIBgABNQAECggIMAAOACkeAA==.',
Ce='Cellebur:BAAANQAECgQICgAAAA==.Ceta:BAABNQAECn8nAAIJAAkKuRazNwDZAQAJAAkKuRazNwDZAQAAAA==.',
Ch='Chalfus:BAABNQAECn80AAIPAAgKdR/zKgBHAgAPAAgKdR/zKgBHAgAAAA==.Chaszmyr:BAAANQADCggIHQAAAA==.Chewwy:BAABNQAECn8mAAIOAAkKExtzFgDsAQAOAAkKExtzFgDsAQAAAA==.',
Ci='Cinamen:BAAANQAECgQIBQAAAA==.Cizean:BAABNQAECn8XAAIZAAYKPwJeLgCMAAAZAAYKPwJeLgCMAAAAAA==.',
Cl='Clare:BAAANQABCgQIBAABNQAECggIMAAGANEfAA==.Closetofsmut:BAAANQADCgcIBwABNQAECgUIBQACAAAAAA==.',
Cr='Craivan:BAAANQADCgUICQAAAA==.Crendoal:BAAANQAECgEIAQABNQAECggIKQAaAOsaAA==.Crilly:BAAANQAECgMJAwAAAA==.Crowley:BAAANQADCgQIBAAAAA==.Crumpler:BAABNQAECn8lAAIKAAgKog6sfQBWAQAKAAgKog6sfQBWAQAAAA==.Crüsnik:BAAANQADCgMIAwAAAA==.',
Cy='Cyroka:BAABNQAECn8UAAIbAAYKPQk+cgDnAAAbAAYKPQk+cgDnAAAAAA==.Cytroncutoff:BAAANQAECgMIBQAAAA==.',
Da='Dalastish:BAAANQADCggIDAAAAA==.Damia:BAABNQAECn8bAAMVAAYKnhf4IgCyAQAVAAYKnhf4IgCyAQAHAAMKnQx9fwC2AAAAAA==.Danobun:BAABNQAECn8uAAMTAAoK6R7+HwAMAwATAAoK6R7+HwAMAwAbAAEKLAdTzwAuAAAAAA==.Daring:BAAANQADCgEIAQAAAA==.Darkfoxcr:BAAANQAECgEIAQAAAA==.Darsithis:BAABNQAECn8WAAIIAAYKXAVFawDxAAAIAAYKXAVFawDxAAAAAA==.',
De='Deadite:BAABNQAECn8wAAIOAAgKKR45HgDAAgAOAAgKKR45HgDAAgAAAA==.Deadstealth:BAAANQADCgYIBgAAAA==.Delphirose:BAAANQABCggIDwABNQAECgQICwACAAAAAA==.Delvarrieth:BAABNQAECn8XAAIWAAYKRQ0CKgC5AAAWAAYKRQ0CKgC5AAAAAA==.Demzy:BAAANQAECgUIBwAAAA==.Denth:BAAANQAECgMIBQAAAA==.Dercuur:BAACNQAFFH8HAAITAAMKmQu4DADPAAATAAMKmQu4DADPAAA1AAQKfy0AAhMACgo8F4BCAGsCABMACgo8F4BCAGsCAAAA.Devira:BAAANQADCgYICQAAAA==.',
Di='Displacer:BAAANQADCggICAAAAA==.',
Do='Dondeestasto:BAAANQADCgMIAwAAAA==.Dotur:BAAANQADCgIIAgAAAA==.',
Dr='Dragonkiss:BAAANQADCgQIBwAAAA==.Drainmee:BAAANQAECgUIBgAAAA==.Drakmyrdok:BAAANQADCgQICAAAAA==.Dravorik:BAAANQADCgYIBwAAAA==.Dregoth:BAABNQAECn8jAAISAAkKFgvNbgBZAQASAAkKFgvNbgBZAQAAAA==.Drumpnelf:BAAANQADCgMIAwAAAA==.',
Ds='Dshivà:BAAANQAECgYIDgAAAA==.',
Dv='Dva:BAAANQADCggICAAAAA==.',
['Dá']='Dárkbeard:BAAANQAECgIIBQAAAA==.',
Ea='Eazzekin:BAAANQAECgEIAgAAAA==.',
Ek='Ekneirg:BAABNQAECn8pAAMKAAkKHBpYRwDiAQAKAAkKKhlYRwDiAQAWAAYKHBmaKwCAAQABNQABCgEIAQACAAAAAA==.',
El='Elleneilah:BAAANQADCgUICQAAAA==.Elynth:BAABNQAECn8xAAIcAAkKGBO1NgDPAQAcAAkKGBO1NgDPAQAAAA==.',
Em='Emmalily:BAAANQAECgQIBwAAAA==.',
En='Endlessyueh:BAAANQAECgQIBQAAAA==.',
Ex='Extragrippy:BAAANQAECggIEwAAAA==.',
Ey='Eyris:BAAANQAECgEIBAAAAA==.',
Fa='Faiesong:BAAANQABCgQIBAAAAA==.Fajathyme:BAAANQADCgUIDgAAAA==.Falunia:BAABNQAECn8rAAIZAAoKxhJ8BgDXAQAZAAoKxhJ8BgDXAQAAAA==.Fangren:BAAANQAECgEIAQAAAA==.Farrseer:BAABNQAECn8WAAIQAAYKBAoUVgA1AQAQAAYKBAoUVgA1AQAAAA==.Fasthandslez:BAAANQAECgIIAgAAAA==.',
Fe='Felscythe:BAABNQAECn8XAAIdAAYK/AHfFQByAAAdAAYK/AHfFQByAAAAAA==.Felynn:BAAANQAECgUIBgAAAA==.',
Fi='Fierradin:BAAANQADCgYIBgABNQAECgkJJQAYAJchAA==.Fierrastar:BAABNQAECn8lAAIYAAkKlyEfAwDrAgAYAAkKlyEfAwDrAgAAAA==.Finnius:BAAANQADCgMIBAAAAA==.Finshao:BAAANQAECgYIEwAAAA==.Fionn:BAAANQAECgIIAgABNQAECgQICwACAAAAAA==.',
Fl='Flemish:BAABNQAECn8aAAITAAYKjg8KlQBwAQATAAYKjg8KlQBwAQAAAA==.Flextame:BAAANQADCggIIgAAAA==.Flipalicious:BAABNQAECn89AAMTAAkK+RJzLwCcAQATAAkK+RJzLwCcAQAbAAgKyA7ilgBOAQAAAA==.Flipanomicon:BAAANQADCgYIFgAAAA==.Flipkicks:BAAANQADCgYICgAAAA==.Flipmode:BAAANQADCgcIEAAAAA==.Flipnasty:BAAANQADCgYICwAAAA==.Flipocalypse:BAAANQADCgYICgAAAA==.',
Fo='Foxwynn:BAAANQABCgQIBgAAAA==.',
Fr='Freyalise:BAABNQAECn8hAAMEAAgKGRouMACiAQAEAAYKqRMuMACiAQAJAAYKZgIi0AC0AAAAAA==.Freyjah:BAAANQADCgUIBQAAAA==.Frostycarbon:BAAANQADCgYICwAAAA==.',
Fu='Furriousyueh:BAAANQAECgEIAQAAAA==.',
Ga='Gaia:BAABNQAECn8cAAIGAAcKkQp3lgAEAQAGAAcKkQp3lgAEAQAAAA==.Gallimaufrey:BAAANQAECgUICgAAAA==.Garodan:BAAANQAECgEIAgAAAA==.',
Ge='Gerbo:BAABNQAECn8vAAIPAAkKrgrRfQBHAQAPAAkKrgrRfQBHAQAAAA==.',
Gi='Gianavel:BAABNQAECn8oAAIaAAkK4QofIgAVAQAaAAkK4QofIgAVAQAAAA==.Ginodh:BAAANQAECgQIBgABNQAECggIDwACAAAAAA==.Ginomage:BAAANQAECggIDwAAAA==.Ginopally:BAAANQADCgMIAwABNQAECggIDwACAAAAAA==.Ginoshaman:BAAANQADCgUIBgABNQAECggIDwACAAAAAA==.Ginovoker:BAAANQADCgYICQABNQAECggIDwACAAAAAA==.Gizelli:BAAANQAECgIIAgABNQAECgIIAgACAAAAAA==.',
Gr='Grilled:BAAANQADCgYICwAAAA==.Grimoak:BAAANQAECgMIAwAAAA==.Gronke:BAAANQAECgQIBQABNQABCgEIAQACAAAAAA==.Grubetsella:BAABNQAECn8pAAQaAAgK6xrUMgCAAQAaAAYKURbUMgCAAQAeAAYKmRAELQADAQAdAAUKnBHqEACxAAAAAA==.Grugachur:BAABNQAECn8VAAIfAAcKGRvNBQB4AQAfAAcKGRvNBQB4AQAAAA==.',
Gu='Gustice:BAAANQADCgIJAgAAAA==.',
Gw='Gwenwyfar:BAAANQAECggICQAAAA==.',
Gy='Gyda:BAAANQAECgEIAwAAAA==.',
Ha='Hadooken:BAAANQAECgEIAQAAAA==.Hammerhead:BAAANQAECgEIAgAAAA==.Hangi:BAAANQADCgEIAQABNQAECgcIDgACAAAAAA==.Hanoumatoi:BAAANQAECgYIDwAAAA==.Haralambos:BAAANQAECgQICgAAAA==.Harlar:BAAANQADCgYIDAAAAA==.Hasun:BAABNQAECn8XAAIKAAoKSRYckQACAgAKAAoKSRYckQACAgABNQAECgoKLgATAOkeAA==.',
He='Hehasnoname:BAAANQADCgYICQAAAA==.Helbrede:BAAANQADCgIIAwAAAA==.Heledosia:BAAANQAECgYICQAAAA==.',
Ho='Hordkilla:BAAANQAECgUIDgAAAA==.Hownowbrncw:BAABNQAECn8aAAIKAAgK8BIZlQAoAQAKAAgK8BIZlQAoAQAAAA==.',
Hy='Hyce:BAABNQAECn8qAAQQAAkKVROVIQCJAQAgAAgKlRPRKAD9AQAQAAgKXA2VIQCJAQANAAMK/hiWHQDmAAAAAA==.Hymno:BAAANQADCgYICQAAAA==.',
Ih='Ihavenoname:BAAANQADCgYJCwAAAA==.',
Il='Illusionous:BAAANQAECgIIBQAAAA==.',
In='Insoniacyun:BAAANQAECgQIBwAAAA==.',
Is='Isaak:BAAANQAECgEIAQAAAA==.Iselian:BAAANQAECggIJQAAAQ==.Istrix:BAAANQADCgUJBQAAAA==.',
Ja='Jadefeather:BAAANQAECggIEQAAAA==.',
Jb='Jbelbueno:BAAANQAECgIIAwAAAA==.Jblockiv:BAAANQAECgMIAwAAAA==.Jbprimero:BAAANQAECgYIBgAAAA==.Jbshami:BAABNQAECn8jAAIbAAkKARt3RQBLAgAbAAkKARt3RQBLAgAAAA==.',
Je='Jeman:BAAANQAECgEIAQAAAA==.Jenaelle:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Jenisys:BAAANQADCgYIBgAAAA==.Jenzak:BAABNQAECn8pAAIPAAgK7gK9sQDjAAAPAAgK7gK9sQDjAAAAAA==.Jetfires:BAABNQAECn8/AAIGAAoK3B3GHwBqAgAGAAoK3B3GHwBqAgAAAA==.',
Ji='Jinger:BAABNQAECn8XAAIaAAYK3QScSwDKAAAaAAYK3QScSwDKAAAAAA==.Jinnwoo:BAAANQADCgUIBgAAAA==.',
Jo='Jonn:BAAANQAECgQIBwAAAA==.Jordstrasza:BAAANQADCgYIBgAAAA==.Jozhua:BAAANQAECgEIAwAAAA==.',
Ju='Juggernacht:BAAANQAECgEIBQABNQAECggIIgAJAFobAA==.',
Ka='Kaedren:BAAANQADCgYIEQAAAA==.Kaelorien:BAABNQAECn8fAAIeAAgKTwxLFAA0AQAeAAgKTwxLFAA0AQAAAA==.Kaitja:BAAANQADCgIIAgAAAA==.Kalazaad:BAABNQAECn8jAAIWAAkKFgicHgAGAQAWAAkKFgicHgAGAQAAAA==.Kaldevayn:BAAANQAECgQICwAAAA==.Kaliantha:BAAANQADCgEIAQAAAA==.Kalrow:BAABNQAECn8gAAMgAAkKCgthGgBeAQAgAAkKCgthGgBeAQAQAAEKAABVnwAgAAAAAA==.Kalto:BAAANQAECgIIBQAAAA==.Kalyna:BAAANQAECgUICwAAAA==.Kardanika:BAAANQADCgcIBgAAAA==.Kardanis:BAABNQAECn8wAAIbAAgKnB9dGwBmAgAbAAgKnB9dGwBmAgAAAA==.Kashe:BAAANQAECgQICwAAAA==.Kassaine:BAAANQADCgEIAQAAAA==.Kasume:BAABNQAECn8iAAIZAAgKYxU5CgAoAgAZAAgKYxU5CgAoAgAAAA==.Katavia:BAABNQAECn8wAAIbAAgK2g7PSwBmAQAbAAgK2g7PSwBmAQAAAA==.Kathii:BAAANQAECgUICgAAAA==.Katrazath:BAABNQAECn8aAAIRAAYKTwfhJQAJAQARAAYKTwfhJQAJAQAAAA==.Kaydencia:BAAANQABCgUICAAAAA==.',
Ke='Kelmmers:BAAANQAECgUICAAAAA==.Keyallandron:BAAANQAECgUIEQAAAA==.Keywi:BAAANQAECgQIBQAAAA==.',
Kh='Khaleesie:BAAANQAECgEIBQAAAA==.Khiana:BAAANQADCgIIAgABNQAECggIMAAGANEfAA==.Khrin:BAAANQADCgYIDwAAAA==.',
Ki='Kiddow:BAAANQAECgQIDQAAAA==.Kierea:BAAANQADCgcIEgAAAA==.Kiiarah:BAAANQAECgcIDgAAAA==.Killrah:BAAANQADCgQIBAAAAA==.Kilrah:BAAANQADCggIDQAAAA==.Kilriella:BAAANQADCgYIBwAAAA==.Kinte:BAAANQAECgEIBgAAAA==.Kitamii:BAAANQAECgcIDwAAAA==.Kitaña:BAAANQAECgEIAwAAAA==.Kivrin:BAABNQAECn8WAAIEAAUKzgSaUADPAAAEAAUKzgSaUADPAAAAAA==.Kiára:BAAANQADCggIDQAAAA==.',
Ko='Kokujin:BAABNQAECn8nAAITAAgKLBP1TQAjAQATAAgKLBP1TQAjAQAAAA==.',
Kr='Kraevok:BAAANQADCgMIBwAAAA==.Kraugug:BAAANQADCgQIBAAAAA==.Kringlë:BAABNQAECn8pAAIGAAoKciC9DgDZAgAGAAoKciC9DgDZAgAAAA==.',
Ku='Kurumi:BAAANQAECgEIAQAAAA==.',
Kw='Kwo:BAABNQAECn8VAAIdAAgKGAZuDwDHAAAdAAgKGAZuDwDHAAAAAA==.',
Ky='Kymma:BAABNQAECn8eAAIKAAcKOAgVvADjAAAKAAcKOAgVvADjAAAAAA==.',
La='Laviz:BAAANQADCgYIBwABNQAECgoKLgATAOkeAA==.Laz:BAAANQADCgUIBgAAAA==.Lazengann:BAABNQAECn8oAAMgAAoKfhxYFQC6AgAgAAkKTx5YFQC6AgAQAAIKyQ+cZgA6AAAAAA==.',
Le='Leafbane:BAABNQAECn9CAAQIAAkKDRr9IwBxAgAIAAkKDRr9IwBxAgASAAMKTxB2PQDEAAAOAAEK4BbNwQBFAAAAAA==.Legevia:BAAANQAECgYIEwAAAA==.Leilau:BAAANQAECggIAgAAAA==.Leiris:BAABNQAECn8nAAMKAAkKqQt5dwBjAQAKAAkKqQt5dwBjAQABAAEKoQAbOwEZAAAAAA==.Lejusticier:BAAANQADCggIDAAAAA==.Leonaa:BAAANQADCgYIEwAAAA==.Leucetios:BAAANQAECgUIDQAAAA==.',
Li='Liarace:BAAANQAECgYICwAAAA==.Lightbeard:BAAANQAECgQICgAAAA==.Lightforge:BAABNQAECn8VAAIKAAkKoBRskwD9AQAKAAkKoBRskwD9AQAAAA==.Lilianaa:BAAANQAECgEIAQAAAA==.Lionessi:BAAANQADCgcIBwAAAA==.Lithika:BAAANQADCgYIBgAAAA==.',
Lo='Lorredain:BAAANQADCgYIDQAAAA==.Lothaire:BAAANQAECgMIBAAAAA==.Lothwen:BAAANQAECgMIBQAAAA==.Louisachan:BAAANQAECgIIAgAAAA==.',
Lu='Lucamar:BAAANQADCgQIBAAAAA==.Luxinine:BAABNQAECn8vAAIEAAkKsRxtFADBAgAEAAkKsRxtFADBAgAAAA==.',
Ma='Madhawi:BAAANQAECgIICQAAAA==.Magamon:BAABNQAECn8wAAIPAAgKyBTIagByAQAPAAgKyBTIagByAQAAAA==.Magnix:BAAANQADCgQIBAABNQAECgUICwACAAAAAA==.Malfuriia:BAABNQAECn8XAAIbAAYKAw8CWwAuAQAbAAYKAw8CWwAuAQAAAA==.Mamboke:BAABNQAECn8iAAMGAAkKig7dQgDYAQAGAAkKig7dQgDYAQAhAAQKVgKIaQCHAAAAAA==.Margerdria:BAAANQADCgcIEAAAAA==.Mauugrim:BAAANQAECgQIEQAAAA==.Maxowen:BAABNQAECn8XAAIKAAYKsRQIsAD4AAAKAAYKsRQIsAD4AAAAAA==.Maxxramas:BAAANQADCgcICgAAAA==.',
Me='Mearadan:BAABNQAECn8fAAIbAAkKsQl7kgBaAQAbAAkKsQl7kgBaAQAAAA==.Meatsweats:BAAANQAECgEIAQAAAA==.Megg:BAAANQAECgYICQAAAA==.Mekh:BAABNQAECn8XAAMRAAYKch5tDQADAQARAAUKsh1tDQADAQAiAAEK0x6xKQBOAAAAAA==.Mel:BAAANQADCgcIGwAAAA==.Melanara:BAABNQAECn8lAAIZAAkKGA9VDgDGAQAZAAkKGA9VDgDGAQAAAA==.Melstrom:BAAANQAECgMIBQAAAA==.Meticuluslyn:BAAANQAECgUIBgAAAA==.',
Mi='Milkmaiden:BAAANQAECgEIAgAAAA==.Milkthisbull:BAAANQADCgMIAwAAAA==.Minxminx:BAEANQAECgEIAwAAAA==.Mixler:BAABNQAECn8YAAIPAAgKjgZhkwAdAQAPAAgKjgZhkwAdAQAAAA==.',
Mm='Mmeow:BAAANQADCgYIEAABNQAECgkJIwAGAL8cAA==.',
Mo='Moirine:BAABNQAECn8XAAMFAAYKrBROBABpAQAFAAYKrBROBABpAQAEAAQKlR2CRwABAQAAAA==.',
Mu='Murdrmitts:BAABNQAECn8UAAIMAAUKcwjTJQDfAAAMAAUKcwjTJQDfAAAAAA==.Mustikka:BAAANQAECgQIBwAAAA==.',
My='Mystikah:BAAANQADCgIIAgAAAA==.Myuriyanka:BAABNQAECn80AAITAAoK6A+TLQCmAQATAAoK6A+TLQCmAQAAAA==.',
['Mæ']='Mælstrôm:BAAANQABCgQICAAAAA==.',
Na='Naahommii:BAAANQADCgUIBQAAAA==.Nachtamus:BAAANQAECgIIAwABNQAECggIIgAJAFobAA==.Nachtkampfer:BAAANQAECgIIAgABNQAECggIIgAJAFobAA==.Nachtpranke:BAAANQAECgMICAABNQAECggIIgAJAFobAA==.Nachtteufel:BAAANQAECgIIBAABNQAECggIIgAJAFobAA==.Naeri:BAABNQAECn8bAAILAAYK3RIGIgBNAQALAAYK3RIGIgBNAQAAAA==.Nagualli:BAAANQAECgEIAgAAAA==.Naieve:BAABNQAECn8jAAIXAAkKYhJQQAD5AQAXAAkKYhJQQAD5AQAAAA==.Nastii:BAAANQADCgEIAQAAAA==.Nastychungus:BAABNQAECn8sAAMTAAkKLCKVGAA1AwATAAkKLCKVGAA1AwAbAAUK6AM60wDAAAAAAA==.Navira:BAAANQADCggIHgAAAA==.',
Ne='Negargra:BAABNQAECn8eAAIcAAoKEgo0QwCdAQAcAAoKEgo0QwCdAQAAAA==.Nekoda:BAAANQAECggIAwABNQAECggIBgACAAAAAA==.Nephadin:BAAANQAECgEIAQAAAA==.Nephilim:BAAANQADCgMIAwAAAA==.Neyvin:BAAANQADCggICAAAAA==.',
Ni='Niduun:BAAANQABCggICAAAAA==.Nightfend:BAAANQADCgQIBAAAAA==.Nighttiger:BAAANQAECgQICQAAAA==.Nikooli:BAABNQAECn8XAAMQAAYKlA0jUQBSAQAQAAYKlA0jUQBSAQANAAEKygUvJwAhAAAAAA==.',
No='Noopsie:BAABNQAECn8aAAILAAUKOxiPIABZAQALAAUKOxiPIABZAQAAAA==.Nooters:BAABNQAECn8yAAIIAAoK6SEMBwBzAwAIAAoK6SEMBwBzAwABNQAFFAYIGgARAI4jAA==.Notbaldmonk:BAAANQADCgMIAwAAAA==.Notbaldpries:BAABNQAECn8kAAMJAAkKth0fGwCGAgAJAAkKth0fGwCGAgAEAAcKVRe8EgCeAQAAAA==.',
Nu='Nunavutt:BAAANQADCgUIBQAAAA==.',
Ny='Nyteweaver:BAABNQAECn8VAAIKAAYKmRE+6ABLAQAKAAYKmRE+6ABLAQAAAA==.',
Od='Oderica:BAAANQAECggICAAAAA==.Odurn:BAAANQADCgYIBgAAAA==.',
Og='Ogafor:BAAANQAECgEIAgAAAA==.Ogayac:BAAANQAECgEIBAAAAA==.',
Oh='Ohminous:BAAANQAECgcICQAAAA==.',
Or='Oranash:BAAANQADCgMIAwAAAA==.Orici:BAAANQAECgIIAgABNQAECgIIBQACAAAAAA==.Ornir:BAAANQADCgMIAwAAAA==.Orongosh:BAAANQADCgYIBgAAAA==.',
Os='Oscarmikey:BAABNQAECn8uAAMXAAoKPBVqNgA4AgAXAAoKPBVqNgA4AgALAAUKGRR4RwD3AAAAAA==.Oshu:BAAANQADCgcIBgAAAA==.',
Ot='Ottoshot:BAABNQAECn8XAAIGAAYKnQ2YmgD7AAAGAAYKnQ2YmgD7AAAAAA==.Otum:BAAANQAECgQIDQAAAA==.',
Ov='Overlordock:BAAANQADCgcIBwAAAA==.',
Ox='Oxmantle:BAAANQAECgMIBQAAAA==.',
['Oö']='Oöps:BAABNQAECn8bAAILAAYKrweSOAC5AAALAAYKrweSOAC5AAAAAA==.',
Pa='Paksen:BAAANQAECgYIBgAAAA==.Panamone:BAAANQAECgUICQAAAA==.Pandamaster:BAAANQAECggIEwAAAA==.Paulee:BAAANQAECgEIAQAAAA==.',
Pe='Pendragon:BAAANQADCgQIBQAAAA==.Pesch:BAAANQAECggICAAAAA==.',
Ph='Phylah:BAABNQAECn8WAAMbAAYKKBCYZQANAQAbAAYKKBCYZQANAQATAAEKAABvUQElAAAAAA==.',
Pl='Plagues:BAAANQADCggIFQAAAA==.',
Po='Porterhouze:BAAANQABCgIIAgABNQAECgcIJAAjAIwEAA==.',
Pr='Priianka:BAAANQADCgEIAQAAAA==.Prophetofham:BAAANQADCgYIBgAAAA==.',
Pu='Puchi:BAACNQAFFH8XAAIeAAcK6xT5AwCpAQAeAAcK6xT5AwCpAQA1AAQKfzwAAh4ACgohIokEAF0DAB4ACgohIokEAF0DAAAA.Pug:BAAANQAECgEIAQABNQAECgkJHwAHAI8ZAA==.',
Qa='Qadhira:BAAANQAECgUIAQABNQADCgYICwACAAAAAA==.Qadhiræ:BAAANQAECgEIAgABNQADCgYICwACAAAAAA==.',
['Qæ']='Qædhira:BAAANQADCgYICwAAAA==.',
Ra='Raez:BAAANQAECgYIEwAAAA==.Ragnerock:BAAANQAECgMIBAAAAA==.Raynecira:BAABNQAECn8UAAIGAAcKFQwivgCHAQAGAAcKFQwivgCHAQAAAA==.',
Re='Reihino:BAAANQAECgEIAQAAAA==.Remixidora:BAAANQAECgQJCQABNQAFFAUIBgAPAMAeAA==.Reyrocko:BAAANQAECgEIAgAAAA==.Rezdh:BAAANQAECgYIDwABNQAECgoKGQAPAEsbAA==.Rezmage:BAABNQAECn8ZAAQPAAoKSxvTWwCaAQAPAAgKphjTWwCaAQAZAAQK5hKGGACuAAAkAAEKrRJ1BgA7AAAAAA==.Reznal:BAAANQAECgMIAwABNQAECgoKGQAPAEsbAA==.Rezvoker:BAAANQADCgUJCgABNQAECgoKGQAPAEsbAA==.',
Rh='Rhage:BAAANQADCgcIGgAAAA==.Rhoaias:BAAANQAECgEIAQAAAA==.Rhunyaye:BAAANQAECgEIAQAAAA==.',
Ri='Rickness:BAAANQAECgIIBAAAAA==.Rico:BAAANQADCgIIAgAAAA==.',
Ro='Rokform:BAAANQAECgcIBwAAAA==.Rokthul:BAAANQADCgYIBgAAAA==.Rooroo:BAAANQAECgEIAQAAAA==.Rottingturky:BAAANQAECggIEgAAAA==.Roxane:BAABNQAECn8fAAIXAAgKaAcgMgAJAQAXAAgKaAcgMgAJAQAAAA==.',
Ru='Rubyace:BAAANQAECgUICwAAAA==.Runningelk:BAABNQAECn8hAAIlAAkKBhwwEABeAgAlAAkKBhwwEABeAgAAAA==.Runscapemain:BAABNQAECn8lAAIKAAgK1AlktwCvAQAKAAgK1AlktwCvAQAAAA==.',
Ry='Ryeti:BAAANQADCggINAAAAA==.Ryuzu:BAAANQADCgYIBgAAAA==.Ryydia:BAAANQADCgMIBQAAAA==.',
Sa='Sableanne:BAAANQAECgEIAQAAAA==.Sahalia:BAAANQADCgUIDAABNQAECgIIBQACAAAAAA==.Saintulrick:BAAANQAECgUICAAAAA==.Sajuice:BAABNQAECn8cAAMGAAkKFRsgSwCMAgAGAAkKFRsgSwCMAgAhAAQKKRRDUQDlAAAAAA==.Salow:BAAANQAECgIIBgAAAA==.Sanitas:BAABNQAECn8tAAMJAAoKChB1WgASAgAJAAoKChB1WgASAgAEAAQK3QIbOQBoAAAAAA==.',
Se='Seeyen:BAACNQAFFH8JAAIGAAQKDhKeEwAsAQAGAAQKDhKeEwAsAQA1AAQKfz8AAgYACgoqI/MOAGoDAAYACgoqI/MOAGoDAAAA.Sej:BAAANQAECgEIBgAAAA==.Seraphon:BAAANQADCggIJAAAAA==.Seren:BAAANQADCgIIAgABNQADCggIEAACAAAAAA==.',
Sh='Shaaydo:BAAANQAECgEIAQAAAA==.Shaayllee:BAAANQAECgQIBwAAAA==.Shaaytheyha:BAABNQAECn8hAAIKAAcKfAfZ7ABCAQAKAAcKfAfZ7ABCAQAAAA==.Shaggyp:BAACNQAFFH8FAAIJAAMKUQcNGADAAAAJAAMKUQcNGADAAAA1AAQKfxcAAgkACgrWCL5RAGoBAAkACgrWCL5RAGoBAAAA.Shagmistress:BAAANQAECgEIAQAAAA==.Shamump:BAAANQADCgcIBwAAAA==.Sharyl:BAAANQABCgcIEQAAAA==.Shehasnoname:BAAANQADCgYIGAAAAA==.Shehulk:BAAANQAECgUIDgAAAA==.Shingo:BAAANQADCgcIBwABNQAECgoKMgAIABMfAA==.Ships:BAABNQAECn8cAAIiAAoKQxM0FwBFAgAiAAoKQxM0FwBFAgAAAA==.',
Si='Silf:BAAANQAECgIIBwAAAA==.Silverapples:BAAANQADCgIIAgAAAA==.Sizastrax:BAAANQADCgEIAQAAAA==.',
Sk='Skibbward:BAAANQAECgEIAQABNQAFFAYICwAWADsTAA==.Skrektwo:BAABNQAECn8oAAMbAAgKlBSXRgB6AQAbAAgKlBSXRgB6AQATAAUK4gVs2wDeAAAAAA==.',
Sm='Smackdogg:BAACNQAFFH8MAAIXAAUKQSDQDQCNAQAXAAUKQSDQDQCNAQA1AAQKfx0AAhcACQrKJAEUACcDABcACQrKJAEUACcDAAAA.',
So='Solarspark:BAAANQAECgYIEQAAAA==.Sondaladan:BAAANQADCggIGgAAAA==.Sonomonom:BAAANQAECgEIAQAAAA==.Soota:BAAANQAECgEIBQAAAA==.Sorvina:BAABNQAECn8xAAIcAAoKJg43NwDNAQAcAAoKJg43NwDNAQAAAA==.Soulflame:BAABNQAECn8yAAIZAAkKOwojEAClAQAZAAkKOwojEAClAQAAAA==.Soulkings:BAAANQADCggIGgAAAA==.',
Sp='Spriggs:BAAANQADCgUIBAAAAA==.',
St='Starpath:BAAANQAECgMIAwABNQAECgcIDgACAAAAAA==.Strangr:BAAANQADCggICwABNQAECgoKOQAaALseAA==.Stregnor:BAABNQAECn8ZAAIGAAgKGxBhqQCyAQAGAAgKGxBhqQCyAQAAAA==.Styggi:BAAANQADCggICAAAAA==.Stygy:BAAANQADCgcIBwABNQADCggICAACAAAAAA==.',
Su='Sumyunguy:BAABNQAECn8UAAIaAAYKRRm8LwCZAQAaAAYKRRm8LwCZAQAAAA==.',
Sy='Syllenne:BAAANQAECgEIAQAAAA==.Sylunia:BAABNQAECn8YAAIZAAcK2QMeHwDxAAAZAAcK2QMeHwDxAAAAAA==.Sylváñás:BAAANQAECgEIAgAAAA==.Syrintha:BAAANQADCgYIDAAAAA==.',
Ta='Tachi:BAAANQAECgUIEAABNQAECggIJwARAD0YAA==.Tachie:BAABNQAECn8nAAIRAAgKPRj0BwCRAQARAAgKPRj0BwCRAQAAAA==.Talonclaw:BAAANQAECgEIAQAAAA==.Talön:BAEANQAECgUJBgAAAA==.Tarvah:BAAANQADCgYIBgAAAA==.',
Te='Teranox:BAAANQAECgEIBgAAAA==.Tezzerae:BAAANQAECgYIEQAAAA==.',
Th='Thaesan:BAAANQAECgQIBAAAAA==.Theistica:BAABNQAECn8WAAIWAAYKjQueOwAVAQAWAAYKjQueOwAVAQAAAA==.Theomir:BAAANQAECgIIAgAAAA==.Therin:BAABNQAECn8vAAMYAAoKFA9kBACwAQAYAAoKFA9kBACwAQAhAAcKBwYORAA4AQAAAA==.Thodi:BAAANQAECgEIAQAAAA==.',
Ti='Tillymonick:BAAANQAECgMIBAAAAA==.',
To='Todes:BAAANQADCgIIAgAAAA==.Tongshi:BAAANQABCggIDAAAAA==.Toofast:BAABNQAECn8oAAIbAAgK0SD+GAB6AgAbAAgK0SD+GAB6AgAAAA==.Toofurrious:BAAANQADCgQJBgAAAA==.Toolotems:BAAANQAECgUICQAAAA==.Topswimmer:BAAANQABCgIIAgAAAA==.',
Tr='Trifus:BAAANQAECgEIAQAAAA==.',
Tu='Tulao:BAABNQAECn8WAAIPAAgKPxHfdABaAQAPAAgKPxHfdABaAQABNQAECgoKLgATAOkeAA==.',
Ty='Tylae:BAAANQADCgQIBwAAAA==.',
Ut='Utheli:BAABNQAECn8zAAIKAAoKtxyPJQBuAgAKAAoKtxyPJQBuAgAAAA==.',
Va='Vaeyethir:BAAANQAECgEIAgAAAA==.Vaildora:BAABNQAECn8UAAIIAAcKYgytOQA0AQAIAAcKYgytOQA0AQABNQAECggIJwARAD0YAA==.Valdra:BAABNQAECn8nAAImAAkKqBZtCQCyAQAmAAkKqBZtCQCyAQAAAA==.Valkyl:BAAANQADCgMIBQAAAA==.Valkyll:BAAANQADCgIIBAAAAA==.Valkylpal:BAAANQADCgEIAQAAAA==.Valord:BAAANQADCgcIBwAAAA==.Vane:BAAANQADCgEIAQAAAA==.Vanillacain:BAAANQADCgMIAwAAAA==.',
Ve='Vekjari:BAAANQAECgEIAQAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Viralprepped:BAAANQADCgcIHQAAAA==.',
Vl='Vlonet:BAABNQAECn85AAMgAAkKYRX5DwDpAQAgAAkKYRX5DwDpAQAQAAEK7QholwAuAAAAAA==.',
Vn='Vnasty:BAAANQAECgQIBwABNQAECgkJLAATACwiAA==.',
Vo='Vokola:BAAANQAECgUIBwABNQAECggIJwARAD0YAA==.',
We='Wehadnoname:BAAANQABCgEIAQAAAA==.',
Wi='Wilken:BAAANQAECgQIDAAAAA==.Wink:BAAANQADCgUIBQABNQADCggICwACAAAAAA==.Wiva:BAAANQAECgQIBgAAAA==.',
Wo='Wolfsokol:BAABNQAECn8YAAQOAAoKpxitQwDsAQAOAAcKrB6tQwDsAQAIAAMKiwViagCAAAASAAEKAAC7ggAAAAABNQAFFAgIEgAiAEAcAA==.',
Wr='Wreckoner:BAABNQAECn8wAAIWAAgKvxASGAA/AQAWAAgKvxASGAA/AQAAAA==.',
Xa='Xannah:BAAANQAECgMIAQAAAA==.Xavencia:BAAANQADCgYICgAAAA==.',
Xi='Xinthos:BAAANQAECgIIBAAAAA==.',
Yk='Yknub:BAAANQADCggIDgAAAA==.',
Yu='Yukiakari:BAAANQAECgEIAQAAAA==.',
Za='Zaderan:BAAANQADCgYIDwAAAA==.Zakainu:BAABNQAECn8aAAIUAAkKYhA0GwCxAQAUAAkKYhA0GwCxAQAAAA==.Zallister:BAAANQADCggIKAAAAA==.Zansarutobi:BAAANQABCgYICAAAAA==.Zarathoszan:BAABNQAECn8pAAIGAAgKKAnDbwBXAQAGAAgKKAnDbwBXAQAAAA==.Zarkra:BAAANQAECgUIBQABNQAECgkJIQAlAAYcAA==.',
Ze='Zedator:BAABNQAECn8iAAIYAAgKORiQBQBhAgAYAAgKORiQBQBhAgAAAA==.Zedraikis:BAAANQADCgEIAQAAAA==.Zeedle:BAAANQABCgQIBAAAAA==.Zelgaddis:BAABNQAECn8lAAIbAAkK1hK/agDLAQAbAAkK1hK/agDLAQAAAA==.Zenanor:BAAANQADCgMIAwAAAA==.',
Zh='Zhansaya:BAAANQAECgIIBQAAAA==.',
Zr='Zriana:BAAANQAECgQICgAAAA==.',
Zs='Zsarilya:BAABNQAECn8bAAMJAAYK6gE5ngCOAAAJAAYK6gE5ngCOAAAEAAEKAAArXAAAAAAAAA==.',
Zu='Zurgen:BAABNQAECn8sAAIcAAkKAhtLKwAEAgAcAAkKAhtLKwAEAgAAAA==.',
['Àn']='Àndrol:BAABNQAECn8cAAIPAAgKygvRjwAjAQAPAAgKygvRjwAjAQABNQAFFAYIDAAgAEsQAA==.',
['Êc']='Êclipse:BAEBNQAECn85AAILAAoKtR2WBQAcAwALAAoKtR2WBQAcAwAAAA==.',
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
