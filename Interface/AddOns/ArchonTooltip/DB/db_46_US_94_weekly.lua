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

local lookup = {'Paladin-Holy','Warrior-Fury','Warrior-Protection','Warlock-Demonology','Warlock-Affliction','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','Mage-Frost','Mage-Fire','Priest-Holy','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','Paladin-Retribution','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Brewmaster','Hunter-Survival','Paladin-Protection','DemonHunter-Devourer','Druid-Balance','Monk-Windwalker','Monk-Mistweaver','Druid-Guardian','Mage-Arcane','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Evoker-Augmentation','Warrior-Arms',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aarchon:BAABLgAECn8oAAIBAAkJSh+bCQDyAgABAAkJSh+bCQDyAgAAAA==.',
Ad='Aduin:BAABLgAECn8fAAMCAAkJbxSiNgBtAQACAAkJbw6iNgBtAQADAAMJch43JgAAAQAAAA==.',
Ae='Aedarelyn:BAAALgAECgUJEgAAAA==.Aellet:BAABLgAECn8aAAMEAAkJ8xyaHgBtAgAEAAkJTRyaHgBtAgAFAAQJdx0aGAC6AAAAAA==.Aellita:BAABLgAECn8VAAIGAAYJZwhAqgDuAAAGAAYJZwhAqgDuAAAAAA==.Aeschylus:BAAALgAECgkJEQAAAA==.',
Ak='Akky:BAABLgAECn8tAAIDAAkJKiEBBwCXAgADAAkJKiEBBwCXAgAAAA==.Aksafiya:BAABLgAECn9aAAMHAAkJ8RNKGgDzAQAHAAkJ8RNKGgDzAQAIAAEJWAINiwAcAAAAAA==.',
Al='Alal:BAABLgAECn8gAAIJAAcJPg0AnwA8AQAJAAcJPg0AnwA8AQAAAA==.Alandras:BAABLgAECn8tAAICAAkJAAnOAgC5AAACAAkJAAnOAgC5AAAAAA==.Alaras:BAACLgAFFH8eAAIHAAcJ/g75CwCgAQAHAAcJ/g75CwCgAQAuAAQKfxcAAgcACQnQFQ8aAA8CAAcACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8rAAIFAAkJcxewBwDzAQAFAAkJcxewBwDzAQAAAA==.Allrianne:BAAALgAECgMJCgAAAA==.Allyriae:BAABLgAECn8WAAIKAAgJDgkgCQD0AAAKAAgJDgkgCQD0AAAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8lAAILAAgJTx1gDwBzAgALAAgJTx1gDwBzAgAAAA==.',
Am='Ambilena:BAABLgAECn8vAAMLAAkJgBVILQBiAQALAAYJVhhILQBiAQAHAAkJcRAyAQAwAQAAAA==.',
An='Andoros:BAABLgAECn86AAIMAAkJax6bEADMAgAMAAkJax6bEADMAgAAAA==.Angiliana:BAABLgAECn8UAAINAAUJAw8pPQDCAAANAAUJAw8pPQDCAAAAAA==.Angvall:BAAALgAECgYJCAABLgAFFAEJAQAOAAAAAA==.Animainiac:BAAALgAECgYJBgABLgAECgkJJgAPAGcSAA==.Anzurath:BAABLgAECn8mAAIQAAkJCxVrTgDcAQAQAAkJCxVrTgDcAQAAAA==.',
Ap='Applebow:BAABLgAECn8tAAIRAAkJ4xF1AQDeAAARAAkJ4xF1AQDeAAAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgAECgcJCgAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgcJEAAAAA==.Armas:BAAALgAECgcJBwAAAA==.Arylin:BAABLgAECn82AAIJAAkJlSMlCgApAwAJAAkJlSMlCgApAwAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEBLgAECn8aAAMDAAUJFxVGLQDRAAADAAUJExRGLQDRAAACAAEJtxVmoABBAAAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQAOAAAAAA==.Asky:BAAALgADCgYJBwABLgAECgcJIwAJAO0BAA==.Asnabel:BAABLgAECn8sAAISAAgJng7UEABpAQASAAgJng7UEABpAQAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astrai:BAAALgADCgcJBwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCgARAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgAECgQJCgAAAA==.Ayden:BAABLgAECn8cAAMNAAcJ1BmBGAC/AQANAAcJKhmBGAC/AQATAAIJTRSgAQBXAAAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwAOAAAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgIJBAAAAA==.',
Bl='Blee:BAABLgAECn85AAMIAAkJFRBnAQAUAQAIAAkJFRBnAQAUAQAHAAQJlgWRSgCwAAAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.Bluudclaaw:BAAALgADCgkJDAAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8lAAIEAAcJVh6oOAD3AQAEAAcJVh6oOAD3AQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8uAAIGAAkJ0yEDAgCLAQAGAAkJ0yEDAgCLAQAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8dAAIUAAgJbBAhdgB3AQAUAAgJbBAhdgB3AQAAAA==.Brood:BAABLgAECn8rAAIUAAkJyBRMUQDPAQAUAAkJyBRMUQDPAQAAAA==.Brundles:BAAALgAECgYJBgAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAABLgAECn83AAMVAAgJ0AccSwAIAQAVAAgJ0AccSwAIAQAPAAUJFgi9kAC3AAAAAA==.',
Ca='Cailaranel:BAABLgAECn8uAAMWAAkJigkVJAB0AQAWAAkJ0wcVJAB0AQAXAAcJaQlTEAAfAQAAAA==.Calaul:BAABLgAECn8oAAIQAAkJUBOUSgDmAQAQAAkJUBOUSgDmAQAAAA==.Calenbraga:BAABLgAECn8+AAIYAAkJnRgfCABQAgAYAAkJnRgfCABQAgAAAA==.Calisim:BAABLgAECn8fAAIEAAYJrQYbwADLAAAEAAYJrQYbwADLAAAAAA==.Callidae:BAABLgAECn8qAAILAAkJBxEvHADlAQALAAkJBxEvHADlAQAAAA==.Callum:BAAALgADCgMJAwAAAA==.Calmnbald:BAABLgAECn8ZAAIZAAcJeBfFPAAIAQAZAAcJeBfFPAAIAQAAAA==.Caloh:BAAALgAECgYJBwAAAA==.Cantallbis:BAAALgADCgcJBwAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8lAAIaAAkJlgwvHQCzAQAaAAkJlgwvHQCzAQAAAA==.Cataryn:BAABLgAECn8jAAIGAAkJNSRxDwDVAgAGAAkJNSRxDwDVAgAAAA==.Catt:BAABLgAECn9LAAIBAAkJGBkEFABvAgABAAkJGBkEFABvAgAAAA==.',
Ce='Cellebur:BAABLgAECn8hAAIGAAgJvwSMmQANAQAGAAgJvwSMmQANAQAAAA==.Ceta:BAABLgAECn87AAILAAkJDhyuDQCMAgALAAkJDhyuDQCMAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAACLgAFFH8HAAMVAAMJWQvJTABjAAAVAAIJ7QTJTABjAAAPAAIJ3QIWeQBMAAAuAAQKfysAAw8ACAncEe49ALYBAA8ACAncEe49ALYBABUABwm2GRAuAIoBAAAA.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn9PAAIJAAkJmwtIAgBcAQAJAAkJmwtIAgBcAQAAAA==.Cizean:BAABLgAECn8jAAIJAAcJ7QHtBwGgAAAJAAcJ7QHtBwGgAAAAAA==.',
Cr='Craivan:BAAALgAECgUJDwAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crill:BAAALgAECgUJBgAAAA==.Crilly:BAABLgAECn8rAAIJAAkJZRj8OgAtAgAJAAkJZRj8OgAtAgAAAA==.Crowe:BAAALgAECgUJCgABLgAECgUJBQAOAAAAAA==.Crowley:BAAALgADCgMJAwAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAABLgAECn8XAAIPAAYJsgulcQAHAQAPAAYJsgulcQAHAQAAAA==.Cyrr:BAAALgAECggJCQAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJDAAAAA==.Damia:BAABLgAECn8tAAMWAAkJKRgcAQAQAQAWAAkJKRgcAQAQAQAXAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8mAAIRAAkJ8CQJBAD5AgARAAkJ8CQJBAD5AgAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgEJAgABLgAECgkJJgARAPAkAA==.Delvarrieth:BAABLgAECn8jAAIbAAcJXA/eHgAdAQAbAAcJXA/eHgAdAQAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Demonzar:BAAALgAECgYJBgAAAA==.Demzy:BAAALgAECgEJAQAAAA==.Denth:BAABLgAECn8bAAIQAAkJjA0IbgCSAQAQAAkJjA0IbgCSAQAAAA==.Dercuur:BAABLgAECn8cAAIVAAgJzBXQJADBAQAVAAgJzBXQJADBAQAAAA==.Devoursol:BAABLgAECn85AAMcAAkJlQwAWQB8AQAcAAkJaAwAWQB8AQANAAIJrg45XABvAAAAAA==.',
Di='Dipndots:BAAALgAECgYJBwABLgAECgkJJgARAPAkAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Doist:BAAALgAECgIJAgAAAA==.Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgAECgYJDAAAAA==.Drainmee:BAABLgAECn8lAAMIAAYJNBRyMABcAQAIAAYJNBRyMABcAQAHAAUJagSlZQCFAAAAAA==.Draknol:BAAALgAECgEJAQAAAA==.Dregoth:BAABLgAECn8tAAIUAAkJUwkQAgBGAQAUAAkJUwkQAgBGAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.',
Du='Durpee:BAABLgAECn8uAAMIAAcJnCRVAABLAgAIAAcJnCRVAABLAgALAAIJOhSGawB9AAAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8hAAMMAAkJ4R5kEAC0AgAMAAkJ4R5kEAC0AgAdAAEJxgkZmgAnAAAAAA==.',
Ea='Eathur:BAAALgADCgcJDwAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elunariel:BAAALgAECgEJAgABLgAECgkJGgAEAPMcAA==.Elynth:BAABLgAECn8lAAIEAAkJGBx0IgBYAgAEAAkJGBx0IgBYAgAAAA==.',
En='Endlessyueh:BAABLgAECn8eAAMBAAcJsgWMTgAAAQABAAcJsgWMTgAAAQAQAAYJvg0fyAD9AAAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgkJGgAEAPMcAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAFFAQJBAABLgAFFAYJDwAQAPoMAA==.',
Fa='Face:BAAALgAECggJBgAAAA==.Faethian:BAACLgAFFH8UAAIbAAUJSiFwAwBxAQAbAAUJSiFwAwBxAQAuAAQKfywAAhsACAk7JacDANUCABsACAk7JacDANUCAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8uAAIJAAkJQAfBiwBgAQAJAAkJQAfBiwBgAQAAAA==.Fangren:BAABLgAECn8hAAIGAAYJahLxhAA1AQAGAAYJahLxhAA1AQAAAA==.Fariah:BAAALgAECgUJEwAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAABLgAECn8YAAIeAAcJ6QeSRwDhAAAeAAcJ6QeSRwDhAAAAAA==.',
Fe='Felscythe:BAABLgAECn8iAAIZAAcJgwFSWgCiAAAZAAcJgwFSWgCiAAAAAA==.Felynn:BAABLgAECn8rAAIBAAkJgxj+FQBcAgABAAkJgxj+FQBcAgAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feresdenn:BAAALgADCgQJBAAAAA==.Feyrha:BAAALgADCgYJBgABLgAECgkJKgAGALwPAA==.',
Fi='Fiadh:BAAALgAECgQJBgAAAA==.Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8dAAIfAAcJohsPHwAhAgAfAAcJohsPHwAhAgAAAA==.',
Fl='Flaeli:BAABLgAECn8rAAIJAAkJzRmZAgBFAQAJAAkJzRmZAgBFAQAAAA==.Flameshot:BAAALgADCgkJCQABLgAECgkJKgAgALQOAA==.Flemish:BAABLgAECn8XAAIVAAcJ7xboKwCWAQAVAAcJ7xboKwCWAQAAAA==.Flextame:BAAALgAECgQJDgAAAA==.Flipalicious:BAABLgAECn9AAAMPAAkJehyQEQDCAgAPAAkJehyQEQDCAgAVAAIJSxRingA9AAAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8dAAIHAAcJaBf/KQCBAQAHAAcJaBf/KQCBAQAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Fu='Furriousyueh:BAAALgADCgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn8qAAIGAAkJvA95VQCjAQAGAAkJvA95VQCjAQAAAA==.Gangstafred:BAAALgADCgYJBgAAAA==.Gazo:BAABLgAECn8YAAMHAAcJRBnGHgDPAQAHAAcJRBnGHgDPAQAIAAEJqxGiBQA7AAABLgAECgkJLwAeAJoiAA==.',
Ge='Gemboss:BAABLgAECn9OAAMQAAkJHSItDgD0AgAQAAkJHSItDgD0AgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8uAAMJAAkJmxO5XwDBAQAJAAkJmxO5XwDBAQAhAAMJoAbAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8wAAIeAAkJOworLQBYAQAeAAkJOworLQBYAQAAAA==.Ginodh:BAABLgAECn8OAAIcAAgJtQ1eewApAQAcAAgJtQ1eewApAQABLgAECgkJGQARAPwNAA==.Ginomage:BAAALgAECgcJCgABLgAECgkJGQARAPwNAA==.Ginomonk:BAAALgAECgYJBgABLgAECgkJGQARAPwNAA==.Ginopally:BAAALgAECgYJCwABLgAECgkJGQARAPwNAA==.Girth:BAAALgAECgQJBAAAAA==.Gizelli:BAAALgAFFAEJAQAAAA==.',
Gl='Glorby:BAAALgAECgQJBAABLgAFFAIJBQAfAGMXAA==.',
Go='Gordonn:BAAALgAECgYJBwAAAA==.',
Gr='Groblock:BAAALgADCgYJEgAAAA==.Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAfAGMXAA==.Grubetsella:BAACLgAFFH8FAAIfAAIJYxduDwClAAAfAAIJYxduDwClAAAuAAQKfzcAAh8ACQlsIeMMAM0CAB8ACQlsIeMMAM0CAAAA.Grumpÿ:BAAALgADCgYJBgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIcAAYJXBvFUAC0AQAcAAYJXBvFUAC0AQAAAA==.Gumpers:BAABLgAECn8qAAIgAAkJtA7WHQBeAQAgAAkJtA7WHQBeAQAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAABLgAECn8gAAIdAAYJfALfbwBoAAAdAAYJfALfbwBoAAAAAA==.',
Ha='Halfamazing:BAAALgAECgYJCwAAAA==.Hanoumatoi:BAAALgAECggJCwAAAA==.Haradar:BAAALgADCgEJAQABLgAECgUJHAAbAMASAA==.Haralambos:BAABLgAECn8cAAIbAAUJwBKcKADSAAAbAAUJwBKcKADSAAAAAA==.Haralogain:BAAALgAECgEJAQABLgAECgUJHAAbAMASAA==.Harithon:BAABLgAECn8rAAIiAAkJHyDYAwC9AgAiAAkJHyDYAwC9AgAAAA==.Harlar:BAAALgAECgIJAwAAAA==.Havvöc:BAABLgAECn8sAAIBAAkJoBx5DADHAgABAAkJoBx5DADHAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAABLgAECn8oAAIDAAgJUgRfKwDcAAADAAgJUgRfKwDcAAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAABLgAECn8pAAIJAAYJVgsvBgC7AAAJAAYJVgsvBgC7AAAAAA==.Heyokagi:BAABLgAECn8vAAQYAAkJNyIrAgANAwAYAAkJNyIrAgANAwAgAAIJ1BS5JgBnAAAMAAEJXwh12wAqAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgkJGgAEAPMcAA==.Hordkilla:BAABLgAECn8wAAIQAAkJxAfhlwBFAQAQAAkJxAfhlwBFAQAAAA==.Hottdealer:BAAALgADCgUJBQAAAA==.Hownowbrncw:BAABLgAECn8kAAIQAAgJ6hpIQgAAAgAQAAgJ6hpIQgAAAgAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn82AAMcAAkJ2BwmFgCSAgAcAAkJ2BwmFgCSAgATAAEJphoeLgBKAAAAAA==.Hylda:BAAALgADCgUJBQAAAA==.Hymno:BAAALgAECgEJAgAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAABLgAECn8WAAQMAAgJYQ28cQDfAAAMAAYJvwq8cQDfAAAdAAYJFgwUTADcAAAgAAEJmAMdiAAWAAAAAA==.',
Im='Imathdal:BAABLgAECn8tAAIjAAkJiRM3AAC0AQAjAAkJiRM3AAC0AQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAOAAAAAA==.Insoniacyun:BAABLgAECn8aAAIJAAgJGgs7jABfAQAJAAgJGgs7jABfAQAAAA==.',
Is='Iselian:BAAALgAECgkJKQAAAQ==.Ishanu:BAABLgAECn8iAAIHAAkJ/R49AABsAgAHAAkJ/R49AABsAgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAOAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgAECgkJCQABLgAFFAIJAgAOAAAAAA==.Jax:BAACLgAFFH8NAAIJAAQJRCLYTQBDAQAJAAQJRCLYTQBDAQAuAAQKfykAAgkACAlFIxATADUDAAkACAlFIxATADUDAAAA.',
Jb='Jbelbueno:BAAALgAECgYJBgAAAA==.Jblockiv:BAAALgADCgcJDAAAAA==.Jbprimero:BAAALgAECgIJAgAAAA==.Jbshami:BAABLgAECn86AAMPAAgJUB+BEgC5AgAPAAgJUB+BEgC5AgAVAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgUJBgAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn89AAIhAAkJWg6IBACrAQAhAAkJWg6IBACrAQAAAA==.Jetfires:BAABLgAECn9LAAIGAAkJPyDsDADsAgAGAAkJPyDsDADsAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAABLgAECn8wAAIeAAgJ0QY8QgD2AAAeAAgJ0QY8QgD2AAAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jovie:BAAALgAECgEJAQAAAA==.Jozhua:BAABLgAECn8WAAIGAAYJ5A0nkwAZAQAGAAYJ5A0nkwAZAQAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.Jungg:BAAALgAECgIJAgAAAA==.',
Ka='Kaedren:BAAALgAECgQJCgAAAA==.Kaelaya:BAABLgAECn8cAAIjAAYJgwqpHADJAAAjAAYJgwqpHADJAAAAAA==.Kaelorien:BAABLgAECn89AAIfAAkJKRJlJgDyAQAfAAkJKRJlJgDyAQAAAA==.Kaetta:BAABLgAECn8XAAIJAAgJ0APawwAEAQAJAAgJ0APawwAEAQAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgYJDgAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAABLgAECn8fAAIbAAgJHhDtFwBfAQAbAAgJHhDtFwBfAQAAAA==.Kaldevayn:BAAALgAECggJEQAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgQJBgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8oAAIcAAYJbw0MmQDvAAAcAAYJbw0MmQDvAAAAAA==.Kandandris:BAAALgAECgYJBgAAAA==.Kardanis:BAABLgAECn8rAAIPAAkJviRqAgCiAwAPAAkJviRqAgCiAwAAAA==.Kashe:BAABLgAECn8aAAIBAAUJ3x0wMACZAQABAAUJ3x0wMACZAQAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAABLgAECn8mAAIPAAkJZxKFPAC8AQAPAAkJZxKFPAC8AQAAAA==.Kaydencia:BAABLgAECn8XAAIQAAYJvxET0gDwAAAQAAYJvxET0gDwAAAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgQJBgAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgAECgYJBwAAAA==.Khortical:BAAALgADCgkJCQABLgAECgkJKwAiAB8gAA==.',
Ki='Ki:BAAALgAECgQJBAAAAA==.Kiddow:BAAALgAECgYJEwAAAA==.Kierea:BAAALgAECgMJAwAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgAECgEJAQAAAA==.Kiri:BAAALgADCgkJEQAAAA==.Kitamii:BAABLgAECn8UAAIYAAYJdRbHEQCQAQAYAAYJdRbHEQCQAQAAAA==.Kivrin:BAABLgAECn8RAAIHAAgJ6wcZAwCRAAAHAAgJ6wcZAwCRAAAAAA==.',
Kr='Kringlë:BAABLgAECn8oAAIGAAkJ3SDGGACSAgAGAAkJ3SDGGACSAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kurumi:BAAALgAECgIJAgAAAA==.Kushwizard:BAAALgADCgQJBQAAAA==.Kuunko:BAAALgAECgEJAQAAAA==.',
Ky='Kymma:BAABLgAECn80AAIQAAkJKA74BADRAAAQAAkJKA74BADRAAAAAA==.Kyunix:BAAALgAECgYJBgAAAA==.',
La='Lagoriatsua:BAABLgAECn8ZAAIVAAgJlQZWUgDvAAAVAAgJlQZWUgDvAAAAAA==.Laitue:BAAALgAECgQJDAAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgcJEgAAAA==.Lazengann:BAABLgAECn8mAAMcAAkJnRalOwDZAQAcAAkJERWlOwDZAQANAAIJ/BnEXABUAAAAAA==.',
Le='Leafbane:BAAALgAECgMJAwAAAA==.Leagann:BAAALgAECgEJAQAAAA==.Legevia:BAABLgAECn8cAAMiAAcJrQQ0JADVAAAiAAcJrQQ0JADVAAAPAAIJkgKWzwA8AAAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAABLgAECn88AAIQAAkJDRFsWgC+AQAQAAkJDRFsWgC+AQAAAA==.Leisha:BAAALgADCgEJAQAAAA==.Letifer:BAAALgADCgkJDAAAAA==.Leucetios:BAAALgAECgQJCgAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8iAAILAAkJRxmTDgB/AgALAAkJRxmTDgB/AgAAAA==.Lightbeard:BAABLgAECn8oAAQBAAcJHRxYHgAQAgABAAcJHRxYHgAQAgAQAAIJ+wX/bgFJAAAbAAEJ4A/gUwApAAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAABLgAECn8WAAIQAAgJ7RgTbQCUAQAQAAgJ7RgTbQCUAQAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgAECgQJBgAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lochli:BAAALgADCgIJAgAAAA==.Lorredain:BAAALgAECgQJBwAAAA==.Lothwen:BAAALgAECgYJDAAAAA==.Louisachan:BAAALgADCgUJBQABLgAFFAEJAQAOAAAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8VAAILAAUJFxCzFAAeAQALAAUJFxCzFAAeAQAuAAQKfzcAAgsACQmPFrIXABACAAsACQmPFrIXABACAAAA.Luxinine:BAABLgAECn8oAAIHAAkJPCB6BgDqAgAHAAkJPCB6BgDqAgAAAA==.',
Ly='Lyon:BAAALgADCgMJCgAAAA==.Lyshai:BAAALgAECgYJBgABLgAECgcJHQAkAPceAA==.',
Ma='Magamon:BAABLgAECn8tAAIJAAkJHBdoOgAwAgAJAAkJHBdoOgAwAgAAAA==.Magamus:BAAALgADCgYJBgAAAA==.Mahndarb:BAAALgAECgYJDAABLgAECggJJQALAE8dAA==.Majima:BAAALgAECgYJDgAAAA==.Malfuriia:BAABLgAECn8jAAIPAAcJnRmsLAAGAgAPAAcJnRmsLAAGAgAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Mamboke:BAAALgAECgYJCQAAAA==.Margerdria:BAABLgAECn8VAAIHAAUJDQ0aVADCAAAHAAUJDQ0aVADCAAAAAA==.Maskelle:BAABLgAECn8tAAITAAkJvBGTDgBnAQATAAkJvBGTDgBnAQAAAA==.Mauugrim:BAABLgAECn8pAAIUAAkJ9ghwBADLAAAUAAkJ9ghwBADLAAAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAABLgAECn8bAAIQAAcJXRZ6cACNAQAQAAcJXRZ6cACNAQAAAA==.',
Me='Mearadan:BAAALgAECgkJDwAAAA==.Meatsweats:BAABLgAECn8lAAIQAAgJEQvkrAAkAQAQAAgJEQvkrAAkAQAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDwAAAA==.Mekh:BAABLgAECn8dAAMkAAcJ9x5ABQAPAgAkAAcJ9x5ABQAPAgAlAAMJOhMmKwCTAAAAAA==.Mel:BAAALgAECgMJCgAAAA==.Melanara:BAABLgAECn9LAAIJAAkJNA/DAQCNAQAJAAkJNA/DAQCNAQAAAA==.Melstrom:BAAALgAECggJDgAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgYJBwAAAA==.Meticuluslyn:BAAALgAECgYJDQAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAABLgAECn8WAAIhAAkJ0RO9AwDVAQAhAAkJ0RO9AwDVAQAAAA==.Miyävii:BAABLgAECn8YAAIbAAkJxxNGFwBmAQAbAAkJxxNGFwBmAQAAAA==.',
Mj='Mjsage:BAABLgAECn8jAAIGAAkJDx6zJABQAgAGAAkJDx6zJABQAgAAAA==.',
Mm='Mmeow:BAAALgAECgQJBQABLgAECgkJFQAGAMkZAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8eAAIHAAcJ1hgEIgC3AQAHAAcJ1hgEIgC3AQAAAA==.Mooasha:BAAALgAECgEJAQABLgAECgkJJgAPAGcSAA==.Moonflowers:BAACLgAFFH8fAAIMAAgJ/BkNCAB9AgAMAAgJ/BkNCAB9AgAuAAQKfy8AAgwACAmcJM4HAA8DAAwACAmcJM4HAA8DAAAA.Mordsevoker:BAAALgAFFAIJAgABLgAFFAUJFgAUAFwSAA==.Morginoth:BAAALgADCgcJBwAAAA==.Morregu:BAAALgAECgMJAwAAAA==.Mousekee:BAABLgAECn8qAAILAAkJkw2OJwCJAQALAAkJkw2OJwCJAQAAAA==.',
Mu='Muku:BAAALgADCgkJCQABLgAECgkJSAAJAJURAA==.Murdrmitts:BAABLgAECn8kAAIYAAkJ7gxwGgA6AQAYAAkJ7gxwGgA6AQAAAA==.Mustikka:BAABLgAECn8aAAIYAAUJsQ/dKQDDAAAYAAUJsQ/dKQDDAAAAAA==.',
My='Myuriyanka:BAABLgAECn8pAAMVAAkJoBOIJADDAQAVAAkJoBOIJADDAQAPAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgYJBwAOAAAAAA==.',
Na='Naahommii:BAABLgAECn8gAAIGAAkJxRRQQgDbAQAGAAkJxRRQQgDbAQAAAA==.Nachtpranke:BAABLgAECn8ZAAIMAAgJ9B4rGACFAgAMAAgJ9B4rGACFAgAAAA==.Nadron:BAAALgAECgYJDAAAAA==.Naevala:BAAALgAECgkJCgAAAA==.Nagualli:BAAALgAECgQJBQAAAA==.',
Ne='Negargra:BAABLgAECn8tAAMEAAYJ/RFoAgD+AAAEAAYJ/RFoAgD+AAAmAAEJcgMufAAkAAAAAA==.Nephadin:BAABLgAECn8dAAMQAAgJpAr8uQARAQAQAAgJpAr8uQARAQABAAUJnAbMWQDPAAAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgYJDgAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAABLgAECn8aAAIMAAUJ8gwYgAC6AAAMAAUJ8gwYgAC6AAAAAA==.Nikooli:BAABLgAECn8iAAMNAAgJaxcpGgCvAQANAAgJaxcpGgCvAQATAAEJ+AYiPQAaAAAAAA==.Nimb:BAAALgAECgEJBAAAAA==.',
No='Nokkoh:BAAALgADCgQJBwAAAA==.Nolime:BAAALgAECgYJBwAAAA==.Noodledragon:BAAALgAECgYJBwAAAA==.Noopsie:BAABLgAECn8tAAIMAAgJRguSVAA+AQAMAAgJRguSVAA+AQAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAgJJwAlADQQAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMIAAgJxhqGFwAZAgAIAAcJLhyGFwAZAgAHAAcJsBxkLAByAQAAAA==.Notpeepuddle:BAAALgAECgEJAQAAAA==.Novarox:BAAALgAECgEJAQAAAA==.',
Nu='Nuhnoo:BAAALgADCgkJCQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8mAAIQAAcJoht1TADhAQAQAAcJoht1TADhAQAAAA==.Nyxalia:BAAALgAECgMJAwAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMhAAkJbgM/EgCgAAAJAAkJWQMq4ADaAAAhAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBQAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCggJDwAAAA==.Olympia:BAABLgAECn8pAAIbAAkJXQ1WHQAqAQAbAAkJXQ1WHQAqAQAAAA==.',
Or='Oraclemega:BAABLgAECn80AAIJAAkJBSA9EAD6AgAJAAkJBSA9EAD6AgAAAA==.Orweyna:BAAALgAECggJDwAAAA==.',
Os='Oscarmikey:BAACLgAFFH8dAAMMAAUJew1xAgAOAQAMAAUJew1xAgAOAQAdAAEJhAEHVgAqAAAuAAQKfzsABQwACQlHHoEQAM0CAAwACQlHHoEQAM0CAB0ABglhFaw3ADYBABgAAQlMArdhACAAACAAAQkAAOuUAAAAAAAA.Oshu:BAAALgAECgYJBgAAAA==.',
Ot='Ottoshot:BAABLgAECn8hAAIGAAcJyxLeZgB2AQAGAAcJyxLeZgB2AQAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
Ow='Owlaf:BAAALgAECgEJAQAAAA==.',
['Oö']='Oöps:BAAALgAECggJEgAAAA==.',
Pa='Panamone:BAABLgAECn8iAAMYAAcJRyOqCgAVAgAYAAYJuySqCgAVAgAMAAIJBRZdmACBAAAAAA==.Pandeism:BAABLgAECn8yAAMiAAkJZxTaDgDDAQAiAAgJHxTaDgDDAQAPAAYJixhjAwDEAAAAAA==.Papagrip:BAABLgAECn8wAAMSAAkJ7xJaDACyAQASAAkJ7xJaDACyAQAUAAgJCgr4pgAhAQAAAA==.Patrin:BAABLgAECn8gAAIJAAgJZw3fgwBwAQAJAAgJZw3fgwBwAQAAAA==.Paulee:BAAALgADCgkJDgAAAA==.',
Pe='Peanutbritle:BAABLgAECn8nAAIRAAkJaAZnLgDrAAARAAkJaAZnLgDrAAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.',
Ph='Phantdoom:BAAALgAECgYJEQAAAA==.Phean:BAAALgAECgEJAQAAAA==.Phylah:BAAALgAECgMJBAAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAECggJKQAQAA8lAA==.',
Pl='Plsdiddyno:BAAALgAFFAEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgMJBgAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Puchi:BAAALgAECgUJBQAAAA==.Punchabaal:BAAALgAECgcJDAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAIMAAcJWRnvMwDZAQAMAAcJWRnvMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgQJBAAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAYJJwAhAEQlAA==.Reyrocko:BAAALgAFFAEJAQAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAQJDQAHABsdAA==.Rezdk:BAAALgAECggJCAABLgAFFAQJDQAHABsdAA==.Rezhunt:BAABLgAFFH8FAAMjAAQJJxkSGgDjAAAjAAMJrhgSGgDjAAAaAAEJkhr0LwBUAAABLgAFFAQJDQAHABsdAA==.Rezmonk:BAAALgAECgYJCAABLgAFFAQJDQAHABsdAA==.Rezshift:BAABLgAECn8bAAMdAAgJwhziFQAgAgAdAAgJwhziFQAgAgAMAAQJBRbtbwAFAQABLgAFFAQJDQAHABsdAA==.Rezvoid:BAACLgAFFH8NAAMHAAQJGx0AFQA9AQAHAAQJGx0AFQA9AQALAAIJgyHxIgCjAAAuAAQKfzQAAwcACQkQI84GAOUCAAcACQkQI84GAOUCAAsAAgmjIOtJAL0AAAAA.',
Rh='Rhage:BAAALgAECgMJBwAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAABLgAECn8XAAIUAAcJlRKingAuAQAUAAcJlRKingAuAQAAAA==.Roxane:BAABLgAECn8lAAIdAAkJxQmLMABbAQAdAAkJxQmLMABbAQAAAA==.',
Ru='Runningelk:BAABLgAECn8xAAIgAAkJvBLaFQClAQAgAAkJvBLaFQClAQAAAA==.Runscapemain:BAABLgAECn8qAAMQAAkJ2xXyVADLAQAQAAkJvRXyVADLAQAbAAYJ/RAUIwD8AAAAAA==.',
Ry='Ryeti:BAAALgADCgkJFwAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDgANAAEkAA==.',
Sa='Saintulrick:BAAALgAECgIJAwAAAA==.Sajuice:BAACLgAFFH8HAAIjAAUJPwXHGwDSAAAjAAUJPwXHGwDSAAAuAAQKfyYAAiMACAnAGyIKAM8BACMACAnAGyIKAM8BAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn8mAAMLAAkJlw7PKwBrAQALAAkJlw7PKwBrAQAHAAEJmAMJlwAjAAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAOAAAAAA==.',
Se='Seeyen:BAACLgAFFH8YAAIGAAYJchXAMwBGAQAGAAYJchXAMwBGAQAuAAQKfywAAgYACQnSHgUHAB8DAAYACQnSHgUHAB8DAAAA.Selfdestruct:BAABLgAECn8UAAIQAAgJCwshAwAaAQAQAAgJCwshAwAaAQAAAA==.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8lAAIkAAkJgwrgCgBsAQAkAAkJgwrgCgBsAQAAAA==.Seren:BAAALgAFFAEJAwABLgAFFAcJGAAJAMALAA==.Serenityhate:BAABLgAECn8jAAMLAAYJVQ3MPQD7AAALAAYJVQ3MPQD7AAAHAAEJAABroAAAAAAAAA==.',
Sh='Shaaydo:BAAALgAECgEJBAAAAA==.Shaaytheyha:BAAALgAECgMJAwAAAA==.Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgYJCAAAAA==.Shandrilyn:BAABLgAECn8YAAIHAAcJIARiUQDMAAAHAAcJIARiUQDMAAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAIlAAkJwBQgGABQAQAlAAkJwBQgGABQAQAAAA==.',
Si='Sini:BAAALgAFFAcJBAABLgAFFAgJCwAGAKEjAA==.Sinthoras:BAAALgAECgQJBAAAAA==.Sionarra:BAAALgADCgIJAgAAAA==.',
Sj='Sjðfn:BAAALgAECgkJAgAAAA==.',
Sk='Skala:BAABLgAECn8YAAInAAkJThZoHADyAQAnAAkJThZoHADyAQAAAA==.Skibbie:BAACLgAFFH8eAAMnAAcJbQw3HgBuAQAnAAcJbQw3HgBuAQAkAAQJOwoEBgD9AAAuAAQKfx4ABCcACQk4GF8QAHMCACcACQk4GF8QAHMCACUABAmHDpImALgAACQABQnOBpAsALcAAAAA.Skibbward:BAABLgAECn8zAAQgAAgJTiS4AQAyAwAgAAgJTiS4AQAyAwAdAAUJxQ9jVADUAAAMAAYJ6QrsggDSAAABLgAFFAcJHgAnAG0MAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAABLgAECn8XAAIPAAgJRR4wFACrAgAPAAgJRR4wFACrAgAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgEJBQABLgAECgIJBgAOAAAAAA==.',
Sm='Smackdogg:BAACLgAFFH8IAAIdAAUJKBxWFwBgAQAdAAUJKBxWFwBgAQAuAAQKfxkAAh0ABwk9HRcdABgCAB0ABwk9HRcdABgCAAEuAAUUCAkvABUAeR4A.',
So='Solteria:BAABLgAECn8VAAIFAAcJqAk/DgBOAQAFAAcJqAk/DgBOAQABLgAECgkJAgAOAAAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAABLgAECn8ZAAINAAcJxxDAKAA2AQANAAcJxxDAKAA2AQAAAA==.Sorvina:BAABLgAECn84AAIEAAkJdBKrQADaAQAEAAkJdBKrQADaAQAAAA==.Soulflame:BAABLgAECn9IAAIJAAkJlRE5UQDoAQAJAAkJlRE5UQDoAQAAAA==.Soulshifter:BAABLgAECn8YAAIdAAcJswqgRQD2AAAdAAcJswqgRQD2AAAAAA==.Soultrader:BAAALgADCgkJFwABLgAECgUJHAAbAMASAA==.',
Sp='Spacetime:BAAALgAECgEJAQAAAA==.Spooñ:BAAALgADCgcJBwABLgAFFAUJFgAfAEocAA==.Spottedcoat:BAABLgAECn8nAAIMAAkJdwNlfADDAAAMAAkJdwNlfADDAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgAAAA==.Stasia:BAAALgADCgkJCQAAAA==.Strangerx:BAAALgAECgEJAgAAAA==.Stregnor:BAABLgAECn88AAIGAAkJBBh5JQBMAgAGAAkJBBh5JQBMAgAAAA==.Styggi:BAAALgAECgIJAgAAAA==.Styggian:BAAALgAECgUJBwAAAA==.Stygy:BAAALgAECgMJBAAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDgANAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn9DAAMeAAgJehizGQDjAQAeAAgJehizGQDjAQAZAAUJsQ7PUQC8AAAAAA==.',
Sv='Svéria:BAAALgADCgMJAwAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMnAAkJDxKrEwBHAgAnAAkJfhGrEwBHAgAkAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgkJJgAnAB4bAA==.Tachie:BAABLgAECn8mAAMnAAkJHhtGDwByAgAnAAkJuBpGDwByAgAkAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAcJGwAFAAQmAA==.Taele:BAABLgAECn8tAAMJAAkJTxzNJwB7AgAJAAkJtBvNJwB7AgAhAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn8/AAIdAAkJqhEPHwDPAQAdAAkJqhEPHwDPAQAAAA==.Tamalpais:BAABLgAECn8dAAIGAAUJZhF8BgCxAAAGAAUJZhF8BgCxAAAAAA==.Tamarind:BAAALgAECgYJBgABLgAECgkJKwAiAB8gAA==.Tamzred:BAAALgAECgYJBgABLgAECgkJJgAQAAsVAA==.Tanyab:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8jAAIGAAcJhQM1sQDiAAAGAAcJhQM1sQDiAAAAAA==.',
Th='Thaesan:BAAALgAECgYJDwAAAA==.Therin:BAABLgAECn8wAAIaAAkJHRWFEwAKAgAaAAkJHRWFEwAKAgAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tillymonick:BAAALgAECgUJBwAAAA==.Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgcJGQAAAA==.Toofast:BAABLgAECn87AAIPAAgJbCK1CgALAwAPAAgJbCK1CgALAwAAAA==.Toofurrious:BAAALgADCgkJOgAAAA==.Topswimmer:BAACLgAFFH8HAAIJAAIJfAdyqQCBAAAJAAIJfAdyqQCBAAAuAAQKfxkAAgkABwlSFstsAKEBAAkABwlSFstsAKEBAAAA.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgUJBgAAAA==.',
Tr='Traci:BAABLgAECn8bAAIgAAgJyxMBGACRAQAgAAgJyxMBGACRAQAAAA==.Trifus:BAABLgAECn8pAAMRAAkJ6hg3GACiAQARAAgJlRc3GACiAQAUAAcJ0w81ZACfAQAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAABLgAECn8fAAIMAAYJHR5WKgADAgAMAAYJHR5WKgADAgAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQABLgAECgQJBgAOAAAAAA==.',
Tu='Tulao:BAABLgAECn8wAAIJAAgJZxxkMgBPAgAJAAgJZxxkMgBPAgAAAA==.',
Tw='Twan:BAAALgAFFAEJAQABLgAFFAgJFAAcAAUVAA==.',
Ty='Tyledoriel:BAAALgADCgEJAQAAAA==.Tyrionel:BAAALgAECgUJCgAAAA==.',
Tz='Tzitzimitl:BAAALgAECgYJBwAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIfAAQJaRDuNADXAAAfAAQJaRDuNADXAAAAAA==.',
Ut='Utheli:BAACLgAFFH8RAAIQAAQJqRMrQwAlAQAQAAQJqRMrQwAlAQAuAAQKfx8AAhAACAkBG+FMAOABABAACAkBG+FMAOABAAAA.',
Va='Vaevictis:BAAALgAECgYJCwABLgAECgcJHQAHAGgXAA==.Vaildora:BAAALgAECgEJAQABLgAECgkJJgAnAB4bAA==.Valdra:BAABLgAECn89AAIDAAkJGRPuEgC9AQADAAkJGRPuEgC9AQAAAA==.Valkylpriest:BAAALgAECgEJAgAAAA==.',
Vi='Vidiablade:BAAALgAFFAIJAgAAAA==.Viralprepped:BAAALgAECgMJCgAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8fAAMcAAkJ6w5aUACVAQAcAAkJ6w5aUACVAQANAAYJEg7xNADrAAAAAA==.',
Vn='Vnasty:BAACLgAFFH8PAAIQAAYJ+gwWUgALAQAQAAYJ+gwWUgALAQAuAAQKfywAAhAACQkrICkKAD8DABAACQkrICkKAD8DAAAA.',
Vo='Vogue:BAAALgADCgcJBQAAAA==.',
Vr='Vrale:BAAALgAFFAIJAgAAAA==.',
['Vì']='Vì:BAAALgAECgMJAwABLgAFFAYJDwAQAPoMAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Wes:BAAALgAECgEJAQAAAA==.Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wildbear:BAAALgAECgYJBgAAAA==.Wilken:BAABLgAECn8zAAIoAAkJNRniCABjAgAoAAkJNRniCABjAgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8mAAIQAAkJ/xp8MQA6AgAQAAkJ/xp8MQA6AgAAAA==.',
Ws='Wspr:BAAALgAECgIJBgAAAA==.',
Wu='Wulff:BAAALgADCgMJBgAAAA==.',
Xa='Xaartahli:BAAALgAECgUJEAAAAA==.Xavencia:BAABLgAECn8XAAIJAAkJbgbFAgA8AQAJAAkJbgbFAgA8AQAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xe='Xenolithia:BAAALgAECgIJAgAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECgYJCAAAAA==.',
Ya='Yanut:BAABLgAECn8UAAIQAAYJqQdA7ADPAAAQAAYJqQdA7ADPAAAAAA==.',
Ye='Yeetjin:BAAALgAECgYJCAAAAA==.',
Yi='Yinamin:BAAALgAECgYJEgAAAA==.',
Yk='Yknub:BAAALgADCgYJDQAAAA==.',
Yo='Yotin:BAAALgAECgYJBgAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAABLgAECn8hAAIMAAkJTBP7JQAeAgAMAAkJTBP7JQAeAgAAAA==.Zalanto:BAAALgAECgEJAgAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn9UAAIGAAkJ/xQrAQDuAQAGAAkJ/xQrAQDuAQAAAA==.',
Ze='Zedraikis:BAAALgAECgEJAQAAAA==.Zelgaddis:BAABLgAECn8sAAMPAAkJCxTyAAC3AQAPAAkJCxTyAAC3AQAiAAIJTQSvQQAsAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn8oAAInAAcJdxBPPwAsAQAnAAcJdxBPPwAsAQAAAA==.',
Zr='Zriana:BAAALgAECgQJCAAAAA==.',
Zs='Zsarilya:BAABLgAECn8tAAILAAkJWQIdAwCCAAALAAkJWQIdAwCCAAAAAA==.',
Zu='Zurgen:BAABLgAECn89AAIEAAkJiyDrDADmAgAEAAkJiyDrDADmAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8yAAIMAAgJghUcKQAKAgAMAAgJghUcKQAKAgABLgAFFAUJFQALABcQAA==.',
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
