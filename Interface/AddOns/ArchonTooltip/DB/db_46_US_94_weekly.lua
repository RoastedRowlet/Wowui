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

local lookup = {'Paladin-Holy','Warrior-Fury','Warrior-Protection','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Priest-Discipline','Mage-Frost','Mage-Fire','Priest-Holy','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','Paladin-Retribution','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Vengeance','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Brewmaster','Hunter-Survival','Paladin-Protection','DemonHunter-Devourer','Druid-Balance','Monk-Windwalker','Monk-Mistweaver','Mage-Arcane','Druid-Guardian','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Evoker-Augmentation','Warrior-Arms',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aarchon:BAABLgAECn8oAAIBAAkJSh9mCQDzAgABAAkJSh9mCQDzAgAAAA==.',
Ad='Aduin:BAABLgAECn8bAAMCAAgJQBZqNQByAQACAAgJZA9qNQByAQADAAMJch6bJQAAAQAAAA==.',
Ae='Aedarelyn:BAAALgAECgUJEQAAAA==.Aellet:BAABLgAECn8aAAMEAAkJ8xwOHgBuAgAEAAkJTRwOHgBuAgAFAAQJdx0aGAC6AAAAAA==.Aellita:BAAALgAECgUJEwAAAA==.Aeschylus:BAAALgAECgkJEQAAAA==.',
Ak='Akky:BAABLgAECn8lAAIDAAkJYiDWBgCZAgADAAkJYiDWBgCZAgAAAA==.Aksafiya:BAABLgAECn9aAAMGAAkJ8RM0GQD7AQAGAAkJ8RM0GQD7AQAHAAEJWAKyhwAcAAAAAA==.',
Al='Alal:BAABLgAECn8fAAIIAAcJPg0wnQA8AQAIAAcJPg0wnQA8AQAAAA==.Alandras:BAABLgAECn8pAAICAAgJXwkdQABDAQACAAgJXwkdQABDAQAAAA==.Alaras:BAACLgAFFH8ZAAIGAAcJ/g5vCwCiAQAGAAcJ/g5vCwCiAQAuAAQKfxcAAgYACQnQFQ8aAA8CAAYACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8rAAIFAAkJcxd5BwD0AQAFAAkJcxd5BwD0AQAAAA==.Allrianne:BAAALgAECgMJCgAAAA==.Allyriae:BAABLgAECn8VAAIJAAcJjAneCAD0AAAJAAcJjAneCAD0AAAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8lAAIKAAgJTx0YDwBzAgAKAAgJTx0YDwBzAgAAAA==.',
Am='Ambilena:BAABLgAECn8oAAMGAAkJYw8uIADCAQAGAAkJYw8uIADCAQAKAAYJVhiOLABiAQAAAA==.',
An='Andoros:BAABLgAECn86AAILAAkJax5hEADMAgALAAkJax5hEADMAgAAAA==.Angiliana:BAABLgAECn8UAAIMAAUJAw+7OwDDAAAMAAUJAw+7OwDDAAAAAA==.Angvall:BAAALgAECgYJCAABLgAFFAEJAQANAAAAAA==.Animainiac:BAAALgAECgYJBgABLgAECgkJJgAOAGcSAA==.Anzurath:BAABLgAECn8mAAIPAAkJCxVmTQDdAQAPAAkJCxVmTQDdAQAAAA==.',
Ap='Applebow:BAABLgAECn8pAAIQAAgJphHgHwBSAQAQAAgJphHgHwBSAQAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgAECgcJCgAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgcJEAAAAA==.Armas:BAAALgADCgQJBAAAAA==.Arylin:BAABLgAECn82AAIIAAkJlSPHCQAqAwAIAAkJlSPHCQAqAwAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEBLgAECn8aAAMDAAUJFxWPLADRAAADAAUJExSPLADRAAACAAEJtxVmoABBAAAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQANAAAAAA==.Asky:BAAALgADCgYJBwABLgAECgcJIwAIAO0BAA==.Asnabel:BAABLgAECn8qAAIRAAgJFg4nEABwAQARAAgJFg4nEABwAQAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astrai:BAAALgADCgcJBwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCgAQAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgAECgQJBwAAAA==.Ayden:BAABLgAECn8bAAMMAAcJKhneFwDBAQAMAAcJKhneFwDBAQASAAEJkgqzMAAgAAAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwANAAAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgIJBAAAAA==.',
Bl='Blee:BAABLgAECn8wAAMHAAgJNxH0IADEAQAHAAgJNxH0IADEAQAGAAQJlgWRSgCwAAAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.Bluudclaaw:BAAALgADCgkJCgAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8lAAIEAAcJVh4MOAD4AQAEAAcJVh4MOAD4AQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8qAAITAAgJoSD0HgBpAgATAAgJoSD0HgBpAgAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8YAAIUAAcJAxBxlwA3AQAUAAcJAxBxlwA3AQAAAA==.Brood:BAABLgAECn8rAAIUAAkJyBRuTwDSAQAUAAkJyBRuTwDSAQAAAA==.Brundles:BAAALgAECgYJBgAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAABLgAECn8vAAMVAAgJxAeTSQAKAQAVAAgJxAeTSQAKAQAOAAUJFghejgC3AAAAAA==.',
Ca='Cailaranel:BAABLgAECn8tAAMWAAkJiglkIwB1AQAWAAkJoQdkIwB1AQAXAAcJaQkzEAAfAQAAAA==.Calaul:BAABLgAECn8lAAIPAAkJchI/UADVAQAPAAkJchI/UADVAQAAAA==.Calenbraga:BAABLgAECn85AAIYAAkJQRYPCgAdAgAYAAkJQRYPCgAdAgAAAA==.Calisim:BAABLgAECn8fAAIEAAYJrQZ4vQDPAAAEAAYJrQZ4vQDPAAAAAA==.Callidae:BAABLgAECn8qAAIKAAkJBxGxGwDlAQAKAAkJBxGxGwDlAQAAAA==.Calmnbald:BAABLgAECn8ZAAIZAAcJeBcrPAAIAQAZAAcJeBcrPAAIAQAAAA==.Caloh:BAAALgAECgYJBwAAAA==.Cantallbis:BAAALgADCgcJBwAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8lAAIaAAkJlgybHAC4AQAaAAkJlgybHAC4AQAAAA==.Cataryn:BAABLgAECn8iAAITAAkJNSTcDwDOAgATAAkJNSTcDwDOAgAAAA==.Catt:BAABLgAECn9LAAIBAAkJGBm2EwBwAgABAAkJGBm2EwBwAgAAAA==.',
Ce='Cellebur:BAABLgAECn8gAAITAAgJvwSflgANAQATAAgJvwSflgANAQAAAA==.Ceta:BAABLgAECn87AAIKAAkJDhxrDQCMAgAKAAkJDhxrDQCMAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAACLgAFFH8HAAMVAAMJWQshSgBjAAAVAAIJ7QQhSgBjAAAOAAIJ3QKZdQBMAAAuAAQKfysAAw4ACAncEf88ALYBAA4ACAncEf88ALYBABUABwm2GVotAIoBAAAA.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn9EAAIIAAgJNAj9mwA+AQAIAAgJNAj9mwA+AQAAAA==.Cizean:BAABLgAECn8jAAIIAAcJ7QGeBAGgAAAIAAcJ7QGeBAGgAAAAAA==.',
Cr='Craivan:BAAALgAECgUJDwAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crill:BAAALgAECgUJBQAAAA==.Crilly:BAABLgAECn8rAAIIAAkJZRj9OQAuAgAIAAkJZRj9OQAuAgAAAA==.Crowe:BAAALgAECgUJCgABLgAECgUJBQANAAAAAA==.Crowley:BAAALgADCgMJAwAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAABLgAECn8XAAIOAAYJsgvNbwAHAQAOAAYJsgvNbwAHAQAAAA==.Cyrr:BAAALgAECgcJBwAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJDAAAAA==.Damia:BAABLgAECn8pAAMWAAgJRxl+FgDmAQAWAAgJRxl+FgDmAQAXAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8mAAIQAAkJ8CTtAwD7AgAQAAkJ8CTtAwD7AgAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgEJAgABLgAECgkJJgAQAPAkAA==.Delvarrieth:BAABLgAECn8jAAIbAAcJXA91HgAdAQAbAAcJXA91HgAdAQAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Demonzar:BAAALgAECgYJBgAAAA==.Demzy:BAAALgAECgEJAQAAAA==.Denth:BAABLgAECn8bAAIPAAkJjA2MawCVAQAPAAkJjA2MawCVAQAAAA==.Dercuur:BAABLgAECn8cAAIVAAgJzBUPJADDAQAVAAgJzBUPJADDAQAAAA==.Devoursol:BAABLgAECn85AAMcAAkJlQzQVwB8AQAcAAkJaAzQVwB8AQAMAAIJrg45XABvAAAAAA==.',
Di='Dipndots:BAAALgAECgYJBwABLgAECgkJJgAQAPAkAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Doist:BAAALgAECgIJAgAAAA==.Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgAECgQJBwAAAA==.Drainmee:BAABLgAECn8gAAMHAAYJgROAMABZAQAHAAYJgROAMABZAQAGAAUJ9AN9ZQCBAAAAAA==.Draknol:BAAALgAECgEJAQAAAA==.Dregoth:BAABLgAECn8lAAIUAAkJkQddfABoAQAUAAkJkQddfABoAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.',
Du='Durpee:BAABLgAECn8kAAMHAAcJOSQiCQDfAgAHAAcJOSQiCQDfAgAKAAIJOhSGawB9AAAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8gAAMLAAkJ4R5kEAC0AgALAAkJ4R5kEAC0AgAdAAEJxgldlwAnAAAAAA==.',
Ea='Eathur:BAAALgADCgcJDwAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elunariel:BAAALgAECgEJAgABLgAECgkJGgAEAPMcAA==.Elynth:BAABLgAECn8lAAIEAAkJGBzeIQBZAgAEAAkJGBzeIQBZAgAAAA==.',
En='Endlessyueh:BAABLgAECn8eAAMBAAcJsgWmTQABAQABAAcJsgWmTQABAQAPAAYJvg3IwwAAAQAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgkJGgAEAPMcAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAFFAQJBAABLgAFFAUJDgAPAPAOAA==.',
Fa='Face:BAAALgAECggJBgAAAA==.Faethian:BAACLgAFFH8UAAIbAAUJSiFLAwByAQAbAAUJSiFLAwByAQAuAAQKfywAAhsACAk7JY8DANYCABsACAk7JY8DANYCAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8uAAIIAAkJQAexiQBgAQAIAAkJQAexiQBgAQAAAA==.Fangren:BAABLgAECn8dAAITAAYJGRDOiwAiAQATAAYJGRDOiwAiAQAAAA==.Fariah:BAAALgAECgUJEwAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAABLgAECn8XAAIeAAcJ2gcHRgDkAAAeAAcJ2gcHRgDkAAAAAA==.',
Fe='Felscythe:BAABLgAECn8iAAIZAAcJgwFsWQCiAAAZAAcJgwFsWQCiAAAAAA==.Felynn:BAABLgAECn8rAAIBAAkJgxicFQBdAgABAAkJgxicFQBdAgAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feresdenn:BAAALgADCgQJBAAAAA==.Feyrha:BAAALgADCgYJBgABLgAECggJKAATAPARAA==.',
Fi='Fiadh:BAAALgAECgQJBgAAAA==.Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8dAAIfAAcJohtSHgAhAgAfAAcJohtSHgAhAgAAAA==.',
Fl='Flaeli:BAABLgAECn8nAAIIAAgJYBd8UwDfAQAIAAgJYBd8UwDfAQAAAA==.Flemish:BAABLgAECn8XAAIVAAcJ7xYmKwCWAQAVAAcJ7xYmKwCWAQAAAA==.Flextame:BAAALgAECgQJDgAAAA==.Flipalicious:BAABLgAECn9AAAMOAAkJehwpEQDCAgAOAAkJehwpEQDCAgAVAAIJSxRDmwA9AAAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8dAAIGAAcJaBexKQCCAQAGAAcJaBexKQCCAQAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Fu='Furriousyueh:BAAALgADCgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn8oAAITAAgJ8BGzUwCkAQATAAgJ8BGzUwCkAQAAAA==.Gangstafred:BAAALgADCgYJBgAAAA==.Gazo:BAAALgAECgcJEwABLgAECgkJKwAeADsfAA==.',
Ge='Gemboss:BAABLgAECn9MAAMPAAkJCCIIDgDzAgAPAAkJCCIIDgDzAgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8uAAMIAAkJmxMsXgDCAQAIAAkJmxMsXgDCAQAgAAMJoAbAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8wAAIeAAkJOwpFLABaAQAeAAkJOwpFLABaAQAAAA==.Ginodh:BAABLgAECn8OAAIcAAgJtQ22eQApAQAcAAgJtQ22eQApAQABLgAECgkJGQAQAPwNAA==.Ginomage:BAAALgAECgcJCgABLgAECgkJGQAQAPwNAA==.Ginomonk:BAAALgAECgYJBgABLgAECgkJGQAQAPwNAA==.Ginopally:BAAALgAECgYJCwABLgAECgkJGQAQAPwNAA==.Girth:BAAALgADCgYJBgAAAA==.Gizelli:BAAALgAFFAEJAQAAAA==.',
Gl='Glorby:BAAALgAECgQJBAABLgAFFAIJBQAfAGMXAA==.',
Go='Gordonn:BAAALgAECgYJBwAAAA==.',
Gr='Groblock:BAAALgADCgYJEgAAAA==.Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAfAGMXAA==.Grubetsella:BAACLgAFFH8FAAIfAAIJYxduDwClAAAfAAIJYxduDwClAAAuAAQKfzMAAh8ACAmcIowMAM0CAB8ACAmcIowMAM0CAAAA.Grumpÿ:BAAALgADCgYJBgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIcAAYJXBvFUAC0AQAcAAYJXBvFUAC0AQAAAA==.Gumpers:BAABLgAECn8qAAIhAAkJtA4xHQBeAQAhAAkJtA4xHQBeAQAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAABLgAECn8aAAIdAAYJTQKxbwBkAAAdAAYJTQKxbwBkAAAAAA==.',
Ha='Halfamazing:BAAALgAECgQJBQAAAA==.Hanoumatoi:BAAALgAECgcJCgAAAA==.Haradar:BAAALgADCgEJAQABLgAECgUJGwAbAMASAA==.Haralambos:BAABLgAECn8bAAIbAAUJwBIMKADSAAAbAAUJwBIMKADSAAAAAA==.Haralogain:BAAALgAECgEJAQABLgAECgUJGwAbAMASAA==.Harithon:BAABLgAECn8rAAIiAAkJHyC+AwC+AgAiAAkJHyC+AwC+AgAAAA==.Harlar:BAAALgAECgIJAwAAAA==.Havvöc:BAABLgAECn8sAAIBAAkJoBxEDADIAgABAAkJoBxEDADIAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAABLgAECn8nAAIDAAgJUgTRKgDcAAADAAgJUgTRKgDcAAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAABLgAECn8lAAIIAAYJkgrkywD0AAAIAAYJkgrkywD0AAAAAA==.Heyokagi:BAABLgAECn8vAAQYAAkJNyIcAgANAwAYAAkJNyIcAgANAwAhAAIJ1BS5JgBnAAALAAEJXwjB1wArAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgkJGgAEAPMcAA==.Hordkilla:BAABLgAECn8vAAIPAAkJxAfOlABHAQAPAAkJxAfOlABHAQAAAA==.Hottdealer:BAAALgADCgUJBQAAAA==.Hownowbrncw:BAABLgAECn8fAAIPAAcJxhsRWQC/AQAPAAcJxhsRWQC/AQAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn82AAMcAAkJ2BzJFQCSAgAcAAkJ2BzJFQCSAgASAAEJphpLLQBKAAAAAA==.Hylda:BAAALgADCgUJBQAAAA==.Hymno:BAAALgAECgEJAQAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAABLgAECn8VAAQLAAgJYQ1pcADhAAALAAYJvwppcADhAAAdAAYJFgz2SgDbAAAhAAEJmAP6gwAWAAAAAA==.',
Im='Imathdal:BAABLgAECn8lAAIjAAkJrw5fDQCHAQAjAAkJrw5fDQCHAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQANAAAAAA==.Insoniacyun:BAABLgAECn8aAAIIAAgJGgs4igBfAQAIAAgJGgs4igBfAQAAAA==.',
Is='Iselian:BAAALgAECgkJIQAAAQ==.Ishanu:BAABLgAECn8aAAIGAAkJIhwSDwBnAgAGAAkJIhwSDwBnAgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQANAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgAECgkJCQABLgAFFAIJAgANAAAAAA==.Jax:BAACLgAFFH8NAAIIAAQJRCJNSQBVAQAIAAQJRCJNSQBVAQAuAAQKfykAAggACAlFIxATADUDAAgACAlFIxATADUDAAAA.',
Jb='Jbelbueno:BAAALgAECgYJBgAAAA==.Jblockiv:BAAALgADCgcJDAAAAA==.Jbprimero:BAAALgAECgIJAgAAAA==.Jbshami:BAABLgAECn84AAMOAAgJUB8UEgC6AgAOAAgJUB8UEgC6AgAVAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgUJBgAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn89AAIgAAkJWg50BACsAQAgAAkJWg50BACsAQAAAA==.Jetfires:BAABLgAECn9LAAITAAkJPyBiDADtAgATAAkJPyBiDADtAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAABLgAECn8oAAIeAAgJEAYURQDnAAAeAAgJEAYURQDnAAAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jovie:BAAALgAECgEJAQAAAA==.Jozhua:BAABLgAECn8WAAITAAYJ5A1fkAAZAQATAAYJ5A1fkAAZAQAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.Jungg:BAAALgAECgIJAgAAAA==.',
Ka='Kaedren:BAAALgAECgQJBwAAAA==.Kaelaya:BAABLgAECn8cAAIjAAYJgwo0HADJAAAjAAYJgwo0HADJAAAAAA==.Kaelorien:BAABLgAECn89AAIfAAkJKRKCJQDyAQAfAAkJKRKCJQDyAQAAAA==.Kaetta:BAABLgAECn8XAAIIAAgJ0ANDwQAEAQAIAAgJ0ANDwQAEAQAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgYJDgAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAABLgAECn8dAAIbAAcJ7g7mHQAiAQAbAAcJ7g7mHQAiAQAAAA==.Kaldevayn:BAAALgAECgYJDgAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgQJBgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8oAAIcAAYJbw3qlgDuAAAcAAYJbw3qlgDuAAAAAA==.Kandandris:BAAALgAECgYJBgAAAA==.Kardanis:BAABLgAECn8rAAIOAAkJviRJAgCjAwAOAAkJviRJAgCjAwAAAA==.Kashe:BAABLgAECn8ZAAIBAAUJox2cLwCaAQABAAUJox2cLwCaAQAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAABLgAECn8mAAIOAAkJZxKFOwC8AQAOAAkJZxKFOwC8AQAAAA==.Kaydencia:BAABLgAECn8XAAIPAAYJvxFTzwDxAAAPAAYJvxFTzwDxAAAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgQJBgAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgAECgYJBwAAAA==.',
Ki='Ki:BAAALgAECgQJBAAAAA==.Kiddow:BAAALgAECgUJEgAAAA==.Kierea:BAAALgAECgEJAQAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgAECgEJAQAAAA==.Kiri:BAAALgADCgkJEQAAAA==.Kitamii:BAABLgAECn8UAAIYAAYJdRbHEQCQAQAYAAYJdRbHEQCQAQAAAA==.Kivrin:BAAALgAECgYJEgAAAA==.',
Kr='Kringlë:BAABLgAECn8oAAITAAkJ3SDfFwCTAgATAAkJ3SDfFwCTAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kushwizard:BAAALgADCgQJBQAAAA==.Kuunko:BAAALgAECgEJAQAAAA==.',
Ky='Kymma:BAABLgAECn8wAAIPAAgJBw4EjABWAQAPAAgJBw4EjABWAQAAAA==.Kyunix:BAAALgAECgUJBQAAAA==.',
La='Lagoriatsua:BAABLgAECn8ZAAIVAAgJlQaiUADxAAAVAAgJlQaiUADxAAAAAA==.Laitue:BAAALgAECgQJDAAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgcJDQAAAA==.Lazengann:BAABLgAECn8mAAMcAAkJnRb6OgDYAQAcAAkJERX6OgDYAQAMAAIJ/BmjWgBUAAAAAA==.',
Le='Leafbane:BAAALgAECgMJAwAAAA==.Leagann:BAAALgAECgEJAQAAAA==.Legevia:BAABLgAECn8cAAMiAAcJrQRRIwDVAAAiAAcJrQRRIwDVAAAOAAIJkgLOywA8AAAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAABLgAECn88AAIPAAkJDRFmWADAAQAPAAkJDRFmWADAAQAAAA==.Leisha:BAAALgADCgEJAQAAAA==.Letifer:BAAALgADCgkJDAAAAA==.Leucetios:BAAALgAECgQJBwAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8iAAIKAAkJRxlODgB/AgAKAAkJRxlODgB/AgAAAA==.Lightbeard:BAABLgAECn8mAAQBAAcJyxn3HQARAgABAAcJyxn3HQARAgAPAAIJ+wXeaAFJAAAbAAEJ4A+dUgApAAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAABLgAECn8WAAIPAAgJ7RiZawCVAQAPAAgJ7RiZawCVAQAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgAECgQJBgAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lochli:BAAALgADCgIJAgAAAA==.Lorredain:BAAALgAECgQJBwAAAA==.Lothwen:BAAALgAECgYJDAAAAA==.Louisachan:BAAALgADCgUJBQABLgAFFAEJAQANAAAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8VAAIKAAUJFxDwEwAgAQAKAAUJFxDwEwAgAQAuAAQKfzcAAgoACQmPFkwXABECAAoACQmPFkwXABECAAAA.Luxinine:BAABLgAECn8lAAIGAAkJISB7BgDrAgAGAAkJISB7BgDrAgAAAA==.',
Ly='Lyon:BAAALgADCgMJCgAAAA==.Lyshai:BAAALgAECgYJBgABLgAECgcJHQAkAPceAA==.',
Ma='Magamon:BAABLgAECn8tAAIIAAkJHBdrOQAwAgAIAAkJHBdrOQAwAgAAAA==.Magamus:BAAALgADCgYJBgAAAA==.Mahndarb:BAAALgAECgYJDAABLgAECggJJQAKAE8dAA==.Majima:BAAALgAECgYJDgAAAA==.Malfuriia:BAABLgAECn8jAAIOAAcJnRnXKwAGAgAOAAcJnRnXKwAGAgAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Mamboke:BAAALgAECgYJBgAAAA==.Margerdria:BAABLgAECn8VAAIGAAUJDQ2BUgDFAAAGAAUJDQ2BUgDFAAAAAA==.Maskelle:BAABLgAECn8pAAISAAgJoRFZDgBnAQASAAgJoRFZDgBnAQAAAA==.Mauugrim:BAABLgAECn8lAAIUAAgJowjwjwBDAQAUAAgJowjwjwBDAQAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAABLgAECn8bAAIPAAcJXRZqbQCRAQAPAAcJXRZqbQCRAQAAAA==.',
Me='Mearadan:BAAALgAECgkJDwAAAA==.Meatsweats:BAABLgAECn8kAAIPAAcJ0Au9qQAmAQAPAAcJ0Au9qQAmAQAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDwAAAA==.Mekh:BAABLgAECn8dAAMkAAcJ9x4lBQAPAgAkAAcJ9x4lBQAPAgAlAAMJOhOSKgCSAAAAAA==.Mel:BAAALgAECgMJCgAAAA==.Melanara:BAABLgAECn9DAAIIAAkJbgwnaACpAQAIAAkJbgwnaACpAQAAAA==.Melstrom:BAAALgAECgYJDAAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgYJBwAAAA==.Meticuluslyn:BAAALgAECgYJCgAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAABLgAECn8WAAIgAAkJ0ROrAwDWAQAgAAkJ0ROrAwDWAQAAAA==.Miyävii:BAABLgAECn8YAAIbAAkJxxP9FgBmAQAbAAkJxxP9FgBmAQAAAA==.',
Mj='Mjsage:BAABLgAECn8jAAITAAkJDx63IwBRAgATAAkJDx63IwBRAgAAAA==.',
Mm='Mmeow:BAAALgAECgQJBQABLgAECgkJEwANAAAAAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8eAAIGAAcJ1hirIQC4AQAGAAcJ1hirIQC4AQAAAA==.Mooasha:BAAALgAECgEJAQABLgAECgkJJgAOAGcSAA==.Moonflowers:BAACLgAFFH8eAAILAAcJQxxHBwCAAgALAAcJQxxHBwCAAgAuAAQKfy8AAgsACAmcJM4HAA8DAAsACAmcJM4HAA8DAAAA.Mordsevoker:BAAALgAFFAIJAgABLgAFFAUJFgAUAFwSAA==.Morginoth:BAAALgADCgcJBwAAAA==.Mousekee:BAABLgAECn8oAAIKAAgJCg/tJgCJAQAKAAgJCg/tJgCJAQAAAA==.',
Mu='Muku:BAAALgADCgkJCQABLgAECgkJQgAIAFEQAA==.Murdrmitts:BAABLgAECn8iAAIYAAgJNg32GQA4AQAYAAgJNg32GQA4AQAAAA==.Mustikka:BAABLgAECn8ZAAIYAAUJJg/zKADDAAAYAAUJJg/zKADDAAAAAA==.',
My='Myuriyanka:BAABLgAECn8pAAMVAAkJoBPXIwDEAQAVAAkJoBPXIwDEAQAOAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgYJBwANAAAAAA==.',
Na='Naahommii:BAABLgAECn8gAAITAAkJxRTYQADcAQATAAkJxRTYQADcAQAAAA==.Nachtpranke:BAABLgAECn8ZAAILAAgJ9B7NFwCFAgALAAgJ9B7NFwCFAgAAAA==.Nadron:BAAALgAECgUJCgAAAA==.Naevala:BAAALgAECgkJBwAAAA==.Nagualli:BAAALgAECgQJBQAAAA==.',
Ne='Negargra:BAABLgAECn8pAAMEAAYJ5w+rogD6AAAEAAYJ5w+rogD6AAAmAAEJcgMufAAkAAAAAA==.Nephadin:BAABLgAECn8cAAMPAAcJ2QpUtgATAQAPAAcJ2QpUtgATAQABAAUJnAYpWQDPAAAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgYJDgAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAABLgAECn8ZAAILAAUJ/AobfwC6AAALAAUJ/AobfwC6AAAAAA==.Nikooli:BAABLgAECn8fAAIMAAcJohibGQCvAQAMAAcJohibGQCvAQAAAA==.Nimb:BAAALgAECgEJBAAAAA==.',
No='Nokkoh:BAAALgADCgQJBwAAAA==.Nolime:BAAALgAECgYJBwAAAA==.Noodledragon:BAAALgAECgYJBwAAAA==.Noopsie:BAABLgAECn8qAAILAAgJRgvEUwA+AQALAAgJRgvEUwA+AQAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAgJJwAlADQQAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMHAAgJxhoRFwAaAgAHAAcJLhwRFwAaAgAGAAcJsBwPLABzAQAAAA==.Notpeepuddle:BAAALgAECgEJAQAAAA==.Novarox:BAAALgAECgEJAQAAAA==.',
Nu='Nuhnoo:BAAALgADCgkJCQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8mAAIPAAcJohsySwDjAQAPAAcJohsySwDjAQAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMgAAkJbgM/EgCgAAAIAAkJWQNd3QDaAAAgAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBAAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCggJDwAAAA==.Olympia:BAABLgAECn8pAAIbAAkJXQ3xHAAqAQAbAAkJXQ3xHAAqAQAAAA==.',
Or='Oraclemega:BAABLgAECn8zAAIIAAkJIB+lEAD1AgAIAAkJIB+lEAD1AgAAAA==.Orweyna:BAAALgAECgcJCgAAAA==.',
Os='Oscarmikey:BAACLgAFFH8YAAMLAAUJDQvyJwAYAQALAAUJDQvyJwAYAQAdAAEJhAFrUwAqAAAuAAQKfzUABQsACQmSHEEQAM0CAAsACQmSHEEQAM0CAB0ABgkvFFA6ACUBABgAAQlMArReACAAACEAAQkAAGOQAAAAAAAA.Oshu:BAAALgAECgYJBgAAAA==.',
Ot='Ottoshot:BAABLgAECn8hAAITAAcJyxKsZAB2AQATAAcJyxKsZAB2AQAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
Ow='Owlaf:BAAALgAECgEJAQAAAA==.',
['Oö']='Oöps:BAAALgAECgcJEAAAAA==.',
Pa='Panamone:BAABLgAECn8iAAMYAAcJRyNmCgAVAgAYAAYJuyRmCgAVAgALAAIJBRb6lgCBAAAAAA==.Pandeism:BAABLgAECn8uAAMiAAkJZxSPDgDDAQAiAAgJHxSPDgDDAQAOAAYJiRf9QgCdAQAAAA==.Papagrip:BAABLgAECn8tAAMRAAkJDxIhDACyAQARAAkJDxIhDACyAQAUAAgJeQkSowAkAQAAAA==.Patrin:BAABLgAECn8gAAIIAAgJZw32gQBwAQAIAAgJZw32gQBwAQAAAA==.Paulee:BAAALgADCgkJDgAAAA==.',
Pe='Peanutbritle:BAABLgAECn8nAAIQAAkJaAYqLQDwAAAQAAkJaAYqLQDwAAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.',
Ph='Phantdoom:BAAALgAECgYJEQAAAA==.Phean:BAAALgAECgEJAQAAAA==.Phylah:BAAALgAECgMJBAAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAECggJKQAPAA8lAA==.',
Pl='Plsdiddyno:BAAALgAFFAEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgMJBgAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Puchi:BAAALgAECgUJBQAAAA==.Punchabaal:BAAALgAECgcJDAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAILAAcJWRnvMwDZAQALAAcJWRnvMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgQJBAAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAYJIgAIAEQlAA==.Reyrocko:BAAALgAFFAEJAQAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAQJDQAGABsdAA==.Rezdk:BAAALgAECggJCAABLgAFFAQJDQAGABsdAA==.Rezhunt:BAABLgAFFH8FAAMjAAQJJxkZGQDoAAAjAAMJrhgZGQDoAAAaAAEJkhrVLgBUAAABLgAFFAQJDQAGABsdAA==.Rezmonk:BAAALgAECgYJBgABLgAFFAQJDQAGABsdAA==.Rezshift:BAABLgAECn8bAAMdAAgJwhyqFQAfAgAdAAgJwhyqFQAfAgALAAQJBRbtbwAFAQABLgAFFAQJDQAGABsdAA==.Rezvoid:BAACLgAFFH8NAAMGAAQJGx0OFAA/AQAGAAQJGx0OFAA/AQAKAAIJgyHyIQCkAAAuAAQKfzQAAwYACQkQI6gGAOcCAAYACQkQI6gGAOcCAAoAAgmjINNIAL0AAAAA.',
Rh='Rhage:BAAALgAECgMJBwAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAABLgAECn8XAAIUAAcJlRLenAAuAQAUAAcJlRLenAAuAQAAAA==.Roxane:BAABLgAECn8lAAIdAAkJxQlTLwBeAQAdAAkJxQlTLwBeAQAAAA==.',
Ru='Runningelk:BAABLgAECn8xAAIhAAkJvBJKFQClAQAhAAkJvBJKFQClAQAAAA==.Runscapemain:BAABLgAECn8qAAMPAAkJ2xX0UgDOAQAPAAkJvRX0UgDOAQAbAAYJ/RCVIgD8AAAAAA==.',
Ry='Ryeti:BAAALgADCgkJFwAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDgAMAAEkAA==.',
Sa='Saintulrick:BAAALgAECgIJAwAAAA==.Sajuice:BAACLgAFFH8HAAIjAAUJPwXVGgDWAAAjAAUJPwXVGgDWAAAuAAQKfyYAAiMACAnAG+kJANABACMACAnAG+kJANABAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn8lAAMKAAgJ1w4rKwBrAQAKAAgJ1w4rKwBrAQAGAAEJmAMtlAAjAAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgANAAAAAA==.',
Se='Seeyen:BAACLgAFFH8XAAITAAUJLhl6MABHAQATAAUJLhl6MABHAQAuAAQKfywAAhMACQnSHgUHAB8DABMACQnSHgUHAB8DAAAA.Selfdestruct:BAAALgAECggJDQAAAA==.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8gAAIkAAkJiAm8CgBsAQAkAAkJiAm8CgBsAQAAAA==.Seren:BAAALgAFFAEJAwABLgAFFAcJGAAIAMALAA==.Serenityhate:BAABLgAECn8eAAMKAAYJVQ34PAD6AAAKAAYJVQ34PAD6AAAGAAEJAAA5nQAAAAAAAA==.',
Sh='Shaaydo:BAAALgAECgEJAwAAAA==.Shaaytheyha:BAAALgAECgIJAgAAAA==.Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgYJBgAAAA==.Shandrilyn:BAABLgAECn8YAAIGAAcJIASsTwDPAAAGAAcJIASsTwDPAAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAIlAAkJwBTcFwBQAQAlAAkJwBTcFwBQAQAAAA==.',
Si='Sini:BAAALgAFFAcJBAAAAA==.Sinthoras:BAAALgAECgQJBAAAAA==.',
Sj='Sjðfn:BAAALgAECgkJAgAAAA==.',
Sk='Skala:BAABLgAECn8YAAInAAkJThY8HADyAQAnAAkJThY8HADyAQAAAA==.Skibbie:BAACLgAFFH8ZAAMnAAcJnAuRHABzAQAnAAcJPAuRHABzAQAkAAQJygjaBQD9AAAuAAQKfx4ABCcACQk4GF8QAHMCACcACQk4GF8QAHMCACUABAmHDhomALgAACQABQnOBpAsALcAAAAA.Skibbward:BAABLgAECn8zAAQhAAgJTiS4AQAyAwAhAAgJTiS4AQAyAwAdAAUJxQ9jVADUAAALAAYJ6QrsggDSAAABLgAFFAcJGQAnAJwLAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAABLgAECn8WAAIOAAgJ2x22FACiAgAOAAgJ2x22FACiAgAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgEJAwABLgAECgIJBgANAAAAAA==.',
Sm='Smackdogg:BAABLgAECn8ZAAIdAAcJPR0XHQAYAgAdAAcJPR0XHQAYAgABLgAFFAgJKwAVAGkdAA==.',
So='Solteria:BAABLgAECn8VAAIFAAcJqAk/DgBOAQAFAAcJqAk/DgBOAQABLgAECgkJAgANAAAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAABLgAECn8ZAAIMAAcJxxB8JwA6AQAMAAcJxxB8JwA6AQAAAA==.Sorvina:BAABLgAECn84AAIEAAkJdBIZPwDfAQAEAAkJdBIZPwDfAQAAAA==.Soulflame:BAABLgAECn9CAAIIAAkJURDuTwDpAQAIAAkJURDuTwDpAQAAAA==.Soulshifter:BAABLgAECn8YAAIdAAcJswqXRAD2AAAdAAcJswqXRAD2AAAAAA==.Soultrader:BAAALgADCgkJFwABLgAECgUJGwAbAMASAA==.',
Sp='Spacetime:BAAALgAECgEJAQAAAA==.Spooñ:BAAALgADCgcJBwABLgAFFAUJFgAfAEocAA==.Spottedcoat:BAABLgAECn8nAAILAAkJdwMpewDEAAALAAkJdwMpewDEAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgAAAA==.Stasia:BAAALgADCgkJCQAAAA==.Strangerx:BAAALgAECgEJAgAAAA==.Stregnor:BAABLgAECn88AAITAAkJBBhsJABNAgATAAkJBBhsJABNAgAAAA==.Styggi:BAAALgAECgIJAgAAAA==.Styggian:BAAALgAECgUJBwAAAA==.Stygy:BAAALgAECgMJAwAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDgAMAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn9DAAMeAAgJehg0GQDkAQAeAAgJehg0GQDkAQAZAAUJsQ4BUQC8AAAAAA==.',
Sv='Svéria:BAAALgADCgMJAwAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMnAAkJDxKrEwBHAgAnAAkJfhGrEwBHAgAkAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgkJJgAnAB4bAA==.Tachie:BAABLgAECn8mAAMnAAkJHhsdDwByAgAnAAkJuBodDwByAgAkAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAYJGQAFABYmAA==.Taele:BAABLgAECn8tAAMIAAkJTxwWJwB8AgAIAAkJtBsWJwB8AgAgAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn80AAIdAAkJFQ7rKACGAQAdAAkJFQ7rKACGAQAAAA==.Tamalpais:BAABLgAECn8aAAITAAUJLg7drwDeAAATAAUJLg7drwDeAAAAAA==.Tamarind:BAAALgAECgYJBgABLgAECgkJKwAiAB8gAA==.Tamzred:BAAALgAECgYJBgABLgAECgkJJgAPAAsVAA==.Tanyab:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8jAAITAAcJhQPVrQDiAAATAAcJhQPVrQDiAAAAAA==.',
Th='Thaesan:BAAALgAECgYJDwAAAA==.Therin:BAABLgAECn8wAAIaAAkJHRUHEwAQAgAaAAkJHRUHEwAQAgAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tillymonick:BAAALgAECgUJBgAAAA==.Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgcJGAAAAA==.Toofast:BAABLgAECn82AAIOAAgJbCJYCgAMAwAOAAgJbCJYCgAMAwAAAA==.Toofurrious:BAAALgADCgkJOgAAAA==.Topswimmer:BAACLgAFFH8GAAIIAAIJfAdbpgCIAAAIAAIJfAdbpgCIAAAuAAQKfxkAAggABwlSFlZrAKIBAAgABwlSFlZrAKIBAAAA.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgUJBgAAAA==.',
Tr='Traci:BAABLgAECn8VAAIhAAgJAxJ7HABkAQAhAAgJAxJ7HABkAQAAAA==.Trifus:BAABLgAECn8oAAMQAAkJ6hjVFwCkAQAQAAcJpRjVFwCkAQAUAAcJ0w8+YgChAQAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAABLgAECn8fAAILAAYJHR7zKQADAgALAAYJHR7zKQADAgAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.',
Tu='Tulao:BAABLgAECn8rAAIIAAgJvxusNABDAgAIAAgJvxusNABDAgAAAA==.',
Tw='Twan:BAAALgAECgkJDQABLgAFFAcJEwAcACQWAA==.',
Ty='Tyledoriel:BAAALgADCgEJAQAAAA==.Tyrionel:BAAALgAECgUJCgAAAA==.',
Tz='Tzitzimitl:BAAALgAECgYJBwAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIfAAQJaRB/MgDYAAAfAAQJaRB/MgDYAAAAAA==.',
Ut='Utheli:BAACLgAFFH8RAAIPAAQJqRMOQAAlAQAPAAQJqRMOQAAlAQAuAAQKfx8AAg8ACAkBG6RLAOEBAA8ACAkBG6RLAOEBAAAA.',
Va='Vaevictis:BAAALgAECgUJCAABLgAECgcJHQAGAGgXAA==.Vaildora:BAAALgAECgEJAQABLgAECgkJJgAnAB4bAA==.Valdra:BAABLgAECn89AAIDAAkJGROYEgC+AQADAAkJGROYEgC+AQAAAA==.',
Vi='Vidiablade:BAAALgAFFAIJAgAAAA==.Viralprepped:BAAALgAECgMJCgAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8fAAMcAAkJ6w4mTwCUAQAcAAkJ6w4mTwCUAQAMAAYJEg7hMwDsAAAAAA==.',
Vn='Vnasty:BAACLgAFFH8OAAIPAAUJ8A4CTwALAQAPAAUJ8A4CTwALAQAuAAQKfywAAg8ACQkrICkKAD8DAA8ACQkrICkKAD8DAAAA.',
Vo='Vogue:BAAALgADCgUJBQAAAA==.',
Vr='Vrale:BAAALgAFFAIJAgAAAA==.',
['Vì']='Vì:BAAALgAECgMJAwABLgAFFAUJDgAPAPAOAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Wes:BAAALgAECgEJAQAAAA==.Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wildbear:BAAALgAECgYJBgAAAA==.Wilken:BAABLgAECn8zAAIoAAkJNRmwCABkAgAoAAkJNRmwCABkAgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8mAAIPAAkJ/xqXMAA7AgAPAAkJ/xqXMAA7AgAAAA==.',
Ws='Wspr:BAAALgAECgIJBgAAAA==.',
Wu='Wulff:BAAALgADCgMJBgAAAA==.',
Xa='Xaartahli:BAAALgAECgUJEAAAAA==.Xavencia:BAAALgAECgYJDwAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xe='Xenolithia:BAAALgAECgEJAQAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECgYJCAAAAA==.',
Ya='Yanut:BAABLgAECn8UAAIPAAYJqQcf5wDSAAAPAAYJqQcf5wDSAAAAAA==.',
Ye='Yeetjin:BAAALgAECgMJAgAAAA==.',
Yi='Yinamin:BAAALgAECgYJEgAAAA==.',
Yk='Yknub:BAAALgADCgYJCQAAAA==.',
Yo='Yotin:BAAALgAECgYJBgAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAABLgAECn8hAAILAAkJTBOiJQAeAgALAAkJTBOiJQAeAgAAAA==.Zalanto:BAAALgAECgEJAgAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn9HAAITAAkJpRH0QADbAQATAAkJpRH0QADbAQAAAA==.',
Ze='Zedraikis:BAAALgAECgEJAQAAAA==.Zelgaddis:BAABLgAECn8kAAMOAAkJiRNHPAC5AQAOAAgJYxNHPAC5AQAiAAIJTQTFPwAsAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn8oAAInAAcJdxCBPgAsAQAnAAcJdxCBPgAsAQAAAA==.',
Zr='Zriana:BAAALgAECgQJBgAAAA==.',
Zs='Zsarilya:BAABLgAECn8pAAIKAAgJVAJ8RADSAAAKAAgJVAJ8RADSAAAAAA==.',
Zu='Zurgen:BAABLgAECn89AAIEAAkJiyCBDADoAgAEAAkJiyCBDADoAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8xAAILAAgJghWLKAALAgALAAgJghWLKAALAgABLgAFFAUJFQAKABcQAA==.',
['Ýu']='Ýui:BAAALgADCgQJBAAAAA==.',
['ßo']='ßooßear:BAAALgAECgIJAgAAAA==.',
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
