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

local lookup = {'Paladin-Holy','Warrior-Fury','Warrior-Protection','Hunter-BeastMastery','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Mage-Frost','Warlock-Affliction','Mage-Fire','Priest-Holy','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Vengeance','Warlock-Demonology','DeathKnight-Unholy','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Brewmaster','Hunter-Survival','Paladin-Protection','DemonHunter-Devourer','Druid-Balance','Monk-Windwalker','Monk-Mistweaver','Druid-Guardian','Mage-Arcane','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Evoker-Augmentation','Warrior-Arms',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aarchon:BAABLgAECn8oAAIBAAkJSh+ZCQDyAgABAAkJSh+ZCQDyAgAAAA==.',
Ad='Aduin:BAABLgAECn8hAAMCAAkJbxSjNgBtAQACAAkJbw6jNgBtAQADAAQJexs4JgAAAQAAAA==.',
Ae='Aedarelyn:BAAALgAECgUJEwAAAA==.Aellita:BAABLgAECn8VAAIEAAYJZwhFqgDuAAAEAAYJZwhFqgDuAAAAAA==.Aeschylus:BAABLgAECn8WAAIFAAkJYg9oCgABAQAFAAkJYg9oCgABAQAAAA==.',
Af='Afkinlife:BAAALgADCgIJAgAAAA==.',
Ak='Akky:BAABLgAECn8tAAIDAAkJKiH/BgCXAgADAAkJKiH/BgCXAgAAAA==.Aksafiya:BAABLgAECn9cAAMGAAkJhxRKGgDzAQAGAAkJhxRKGgDzAQAHAAEJWAINiwAcAAAAAA==.',
Al='Alal:BAABLgAECn8gAAIIAAcJPg0AnwA8AQAIAAcJPg0AnwA8AQAAAA==.Alandras:BAABLgAECn8tAAICAAkJAAmaBwC4AAACAAkJAAmaBwC4AAAAAA==.Alaras:BAACLgAFFH8eAAIGAAcJ/g76CwCgAQAGAAcJ/g76CwCgAQAuAAQKfxcAAgYACQnQFQ8aAA8CAAYACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8rAAIJAAkJcxexBwDzAQAJAAkJcxexBwDzAQAAAA==.Allrianne:BAAALgAECgMJCgAAAA==.Allyriae:BAABLgAECn8WAAIKAAgJDgkgCQD0AAAKAAgJDgkgCQD0AAAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8lAAILAAgJTx1gDwBzAgALAAgJTx1gDwBzAgAAAA==.',
Am='Ambilena:BAABLgAECn8vAAMLAAkJgBVMLQBiAQALAAYJVhhMLQBiAQAGAAkJcRBHAwArAQAAAA==.',
An='Andoros:BAABLgAECn86AAIMAAkJax6bEADMAgAMAAkJax6bEADMAgAAAA==.Angiliana:BAABLgAECn8UAAINAAUJAw8sPQDCAAANAAUJAw8sPQDCAAAAAA==.Angvall:BAAALgAECgYJCAABLgAFFAMJBAAOAAAAAA==.Animainiac:BAAALgAECgYJBgABLgAECgkJJwAPAGcSAA==.Anzurath:BAABLgAECn8nAAIFAAkJRxVqTgDcAQAFAAkJRxVqTgDcAQAAAA==.',
Ap='Applebow:BAABLgAECn8tAAIQAAkJ4xGAAwDeAAAQAAkJ4xGAAwDeAAAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgAECgcJDAAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgcJEAAAAA==.Armas:BAAALgAECgcJBwAAAA==.Arylin:BAABLgAECn82AAIIAAkJlSMiCgApAwAIAAkJlSMiCgApAwAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEBLgAECn8aAAMDAAUJFxVGLQDRAAADAAUJExRGLQDRAAACAAEJtxVmoABBAAAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQAOAAAAAA==.Asky:BAAALgADCgYJBwABLgAECgcJJAAIAPQBAA==.Asnabel:BAABLgAECn8vAAIRAAkJeg7UEABpAQARAAkJeg7UEABpAQAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astrai:BAAALgADCgcJBwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCgAQAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgAECgQJDAAAAA==.Ayden:BAABLgAECn8dAAMNAAcJ1BmBGAC/AQANAAcJxxmBGAC/AQASAAIJTRQ4BABWAAAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwAOAAAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgMJBQAAAA==.',
Bl='Blee:BAABLgAECn88AAMHAAkJPxABAwBPAQAHAAkJPxABAwBPAQAGAAQJlgWRSgCwAAAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.Bluudclaaw:BAAALgAECgUJBQAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8lAAITAAcJVh6rOAD3AQATAAcJVh6rOAD3AQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8uAAIEAAkJ0yHrHwBoAgAEAAkJ0yHrHwBoAgAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8eAAIUAAkJOhAjdgB3AQAUAAkJOhAjdgB3AQAAAA==.Brood:BAABLgAECn8rAAIUAAkJyBRRUQDPAQAUAAkJyBRRUQDPAQAAAA==.Brundles:BAAALgAECgYJBgAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAABLgAECn8/AAMVAAgJHAmcBAD5AAAVAAgJHAmcBAD5AAAPAAUJFgjEkAC3AAAAAA==.',
Ca='Cailaranel:BAABLgAECn8uAAMWAAkJigkUJAB0AQAWAAkJ0wcUJAB0AQAXAAcJaQlUEAAfAQAAAA==.Calaul:BAABLgAECn8uAAIFAAkJ6hSrBgBMAQAFAAkJ6hSrBgBMAQAAAA==.Calenbraga:BAABLgAECn9CAAIYAAkJJhkhCABPAgAYAAkJJhkhCABPAgAAAA==.Calisim:BAABLgAECn8hAAITAAYJMwcZwADLAAATAAYJMwcZwADLAAAAAA==.Callidae:BAABLgAECn8qAAILAAkJBxEwHADlAQALAAkJBxEwHADlAQAAAA==.Callum:BAAALgADCgMJAwAAAA==.Calmnbald:BAABLgAECn8ZAAIZAAcJeBfGPAAIAQAZAAcJeBfGPAAIAQAAAA==.Caloh:BAAALgAECgYJCAAAAA==.Cantallbis:BAAALgADCgcJBwAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8lAAIaAAkJlgwuHQCzAQAaAAkJlgwuHQCzAQAAAA==.Cataryn:BAABLgAECn8kAAIEAAkJNSRwDwDVAgAEAAkJNSRwDwDVAgAAAA==.Catt:BAABLgAECn9LAAIBAAkJGBkDFABvAgABAAkJGBkDFABvAgAAAA==.',
Ce='Cellebur:BAABLgAECn8iAAIEAAgJvwSMmQANAQAEAAgJvwSMmQANAQAAAA==.Ceta:BAABLgAECn87AAILAAkJDhyuDQCLAgALAAkJDhyuDQCLAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAACLgAFFH8HAAMVAAMJWQvHTABjAAAVAAIJ7QTHTABjAAAPAAIJ3QIYeQBMAAAuAAQKfysAAw8ACAncEfA9ALYBAA8ACAncEfA9ALYBABUABwm2GRMuAIoBAAAA.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn9QAAIIAAkJmwt2BgBWAQAIAAkJmwt2BgBWAQAAAA==.Cizean:BAABLgAECn8kAAIIAAcJ9AHzBwGgAAAIAAcJ9AHzBwGgAAAAAA==.',
Cr='Craivan:BAAALgAECgUJDwAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crill:BAAALgAECgUJBgAAAA==.Crilly:BAABLgAECn8rAAIIAAkJZRj5OgAtAgAIAAkJZRj5OgAtAgAAAA==.Crowe:BAAALgAECgUJCgABLgAECgUJBQAOAAAAAA==.Crowley:BAAALgADCgMJAwAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAABLgAECn8XAAIPAAYJsgutcQAHAQAPAAYJsgutcQAHAQAAAA==.Cyrr:BAAALgAECggJDwAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJDAAAAA==.Damia:BAABLgAECn8tAAMWAAkJKRjpFgDlAQAWAAkJKRjpFgDlAQAXAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8mAAIQAAkJ8CQHBAD5AgAQAAkJ8CQHBAD5AgAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgEJAwABLgAECgkJJgAQAPAkAA==.Delvarrieth:BAABLgAECn8kAAIbAAcJdxDdHgAdAQAbAAcJdxDdHgAdAQAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Demonzar:BAAALgAECgYJCgAAAA==.Demzy:BAAALgAECgYJBwAAAA==.Denth:BAABLgAECn8gAAIFAAkJsQ4EbgCSAQAFAAkJsQ4EbgCSAQAAAA==.Dercuur:BAABLgAECn8dAAIVAAgJVRfOJADBAQAVAAgJVRfOJADBAQAAAA==.Devoursol:BAABLgAECn85AAMcAAkJlQz+WAB8AQAcAAkJaAz+WAB8AQANAAIJrg45XABvAAAAAA==.',
Di='Dipndots:BAAALgAECgYJBwABLgAECgkJJgAQAPAkAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Doist:BAAALgAECgIJAgAAAA==.Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgAECgYJDAAAAA==.Drainmee:BAABLgAECn8lAAMHAAYJNBRzMABcAQAHAAYJNBRzMABcAQAGAAUJagSxZQCFAAAAAA==.Draknol:BAAALgAECgEJAQAAAA==.Dreadspark:BAABLgAECn8bAAMTAAkJ8xyaHgBtAgATAAkJTRyaHgBtAgAJAAQJdx0aGAC6AAAAAA==.Dregoth:BAABLgAECn8tAAIUAAkJUwkWBgA/AQAUAAkJUwkWBgA/AQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.',
Du='Durpee:BAABLgAECn8xAAMHAAcJnCTZAABSAgAHAAcJnCTZAABSAgALAAIJOhSGawB9AAAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8hAAMMAAkJ4R5kEAC0AgAMAAkJ4R5kEAC0AgAdAAEJxgkemgAnAAAAAA==.',
Ea='Eathur:BAAALgAECgYJBgAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elunariel:BAAALgAECgEJAgABLgAECgkJGwATAPMcAA==.Elynth:BAABLgAECn8lAAITAAkJGBx2IgBYAgATAAkJGBx2IgBYAgAAAA==.',
En='Endlessyueh:BAABLgAECn8hAAMBAAcJAwaNTgAAAQABAAcJAwaNTgAAAQAFAAYJCxAhyAD9AAAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgkJGwATAPMcAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAFFAQJBAABLgAFFAYJEAAFAPoMAA==.',
Fa='Face:BAAALgAECggJBgAAAA==.Faethian:BAACLgAFFH8UAAIbAAUJSiFwAwBxAQAbAAUJSiFwAwBxAQAuAAQKfywAAhsACAk7JacDANUCABsACAk7JacDANUCAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8uAAIIAAkJQAfDiwBgAQAIAAkJQAfDiwBgAQAAAA==.Fangren:BAABLgAECn8mAAIEAAYJtxJiEAC+AAAEAAYJtxJiEAC+AAAAAA==.Fariah:BAAALgAECgUJEwAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAABLgAECn8YAAIeAAcJ6QeSRwDhAAAeAAcJ6QeSRwDhAAAAAA==.',
Fe='Felscythe:BAABLgAECn8jAAIZAAcJmAFTWgCiAAAZAAcJmAFTWgCiAAAAAA==.Felynn:BAABLgAECn8sAAIBAAkJgxj9FQBcAgABAAkJgxj9FQBcAgAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feresdenn:BAAALgADCgQJBAAAAA==.Feyrha:BAAALgADCgYJBgABLgAECgkJMAAEAPMPAA==.',
Fi='Fiadh:BAAALgAECgQJBgAAAA==.Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8eAAIfAAcJjBwOHwAhAgAfAAcJjBwOHwAhAgAAAA==.',
Fl='Flaeli:BAABLgAECn8rAAIIAAkJzRmwBwA9AQAIAAkJzRmwBwA9AQAAAA==.Flameshot:BAAALgADCgkJCQABLgAECgkJLwAgAHUQAA==.Flemish:BAABLgAECn8XAAIVAAcJ7xbrKwCWAQAVAAcJ7xbrKwCWAQAAAA==.Flextame:BAAALgAECgQJDgAAAA==.Flipalicious:BAABLgAECn9AAAMPAAkJehyQEQDCAgAPAAkJehyQEQDCAgAVAAIJSxRingA9AAAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8dAAIGAAcJaBcAKgCBAQAGAAcJaBcAKgCBAQABLgAECggJEgAOAAAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Fu='Furriousyueh:BAAALgADCgQJBAAAAA==.',
['Fë']='Fënrír:BAAALgAECgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn8wAAIEAAkJ8w8SBgByAQAEAAkJ8w8SBgByAQAAAA==.Gangstafred:BAAALgADCgYJBgAAAA==.Gazo:BAABLgAECn8YAAMGAAcJRBnGHgDPAQAGAAcJRBnGHgDPAQAHAAEJqxFQDgA7AAABLgAECgkJLwAeAJoiAA==.',
Ge='Gemboss:BAABLgAECn9OAAMFAAkJHSIvDgD0AgAFAAkJHSIvDgD0AgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8uAAMIAAkJmxO4XwDBAQAIAAkJmxO4XwDBAQAhAAMJoAbAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8xAAIeAAkJ4AotLQBYAQAeAAkJ4AotLQBYAQAAAA==.Ginodh:BAABLgAECn8OAAIcAAgJtQ1eewApAQAcAAgJtQ1eewApAQABLgAECgkJGQAQAPwNAA==.Ginomage:BAAALgAECgcJCgABLgAECgkJGQAQAPwNAA==.Ginomonk:BAAALgAECgYJBgABLgAECgkJGQAQAPwNAA==.Ginopally:BAAALgAECgYJCwABLgAECgkJGQAQAPwNAA==.Girth:BAAALgAECgUJCAAAAA==.Gizelli:BAAALgAFFAEJAgAAAA==.',
Gl='Glorby:BAAALgAECgQJBAABLgAFFAIJBQAfAGMXAA==.',
Go='Gordonnpr:BAAALgAECgYJCAAAAA==.',
Gr='Groblock:BAAALgADCgYJEgAAAA==.Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAfAGMXAA==.Grubetsella:BAACLgAFFH8FAAIfAAIJYxduDwClAAAfAAIJYxduDwClAAAuAAQKfzcAAh8ACQlsIeEMAM0CAB8ACQlsIeEMAM0CAAAA.Grumpÿ:BAAALgADCgYJBgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIcAAYJXBvFUAC0AQAcAAYJXBvFUAC0AQAAAA==.Gumpers:BAABLgAECn8vAAIgAAkJdRCwAwDyAAAgAAkJdRCwAwDyAAAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gurl:BAAALgADCgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAABLgAECn8iAAIdAAYJtgPhbwBoAAAdAAYJtgPhbwBoAAAAAA==.',
Ha='Halfamazing:BAAALgAECgYJCwAAAA==.Hanoumatoi:BAAALgAECggJCwAAAA==.Haradar:BAAALgADCgEJAQABLgAECgUJHQAbAN0SAA==.Haralambos:BAABLgAECn8dAAIbAAUJ3RKcKADSAAAbAAUJ3RKcKADSAAAAAA==.Haralogain:BAAALgAECgEJAQABLgAECgUJHQAbAN0SAA==.Harithon:BAABLgAECn8wAAIiAAkJ1SDXAwC9AgAiAAkJ1SDXAwC9AgAAAA==.Harlar:BAAALgAECgIJAwAAAA==.Havvöc:BAABLgAECn8sAAIBAAkJoBx5DADHAgABAAkJoBx5DADHAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAABLgAECn8pAAIDAAkJ6ANfKwDcAAADAAkJ6ANfKwDcAAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAABLgAECn8rAAIIAAYJ4wzmCwDyAAAIAAYJ4wzmCwDyAAAAAA==.Heyokagi:BAABLgAECn8vAAQYAAkJNyIrAgANAwAYAAkJNyIrAgANAwAgAAIJ1BS5JgBnAAAMAAEJXwhz2wAqAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgkJGwATAPMcAA==.Hordkilla:BAABLgAECn8wAAIFAAkJxAfflwBFAQAFAAkJxAfflwBFAQAAAA==.Hottdealer:BAAALgADCgUJBQAAAA==.Hownowbrncw:BAABLgAECn8kAAIFAAgJ6hpGQgAAAgAFAAgJ6hpGQgAAAgAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn82AAMcAAkJ2BwkFgCSAgAcAAkJ2BwkFgCSAgASAAEJphoiLgBKAAAAAA==.Hylda:BAAALgADCgUJBQAAAA==.Hymno:BAAALgAECgEJAgAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAABLgAECn8aAAQMAAgJxQ/NBADnAAAMAAgJxQ/NBADnAAAdAAYJFgwYTADcAAAgAAEJmAMeiAAWAAAAAA==.',
Im='Imathdal:BAABLgAECn8tAAIjAAkJiROPAACrAQAjAAkJiROPAACrAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAOAAAAAA==.Insoniacyun:BAABLgAECn8cAAIIAAgJvws+jABfAQAIAAgJvws+jABfAQAAAA==.',
Is='Iselian:BAAALgAECgkJKQAAAQ==.Ishanu:BAABLgAECn8iAAIGAAkJ/R6nAABgAgAGAAkJ/R6nAABgAgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAOAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgAECgkJCQABLgAFFAIJAgAOAAAAAA==.Jax:BAACLgAFFH8NAAIIAAQJRCLATQBDAQAIAAQJRCLATQBDAQAuAAQKfykAAggACAlFIxATADUDAAgACAlFIxATADUDAAAA.',
Jb='Jbelbueno:BAAALgAECgYJDAAAAA==.Jblockiv:BAAALgADCgcJDAAAAA==.Jbprimero:BAAALgAECgIJAgAAAA==.Jbshami:BAABLgAECn88AAMPAAgJUB+BEgC5AgAPAAgJUB+BEgC5AgAVAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgUJBgAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn89AAIhAAkJWg6IBACrAQAhAAkJWg6IBACrAQAAAA==.Jetfires:BAABLgAECn9LAAIEAAkJPyDpDADsAgAEAAkJPyDpDADsAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAABLgAECn84AAIeAAgJTQhJBADLAAAeAAgJTQhJBADLAAAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jovie:BAAALgAECgEJAQAAAA==.Jozhua:BAABLgAECn8XAAIEAAYJ5A0mkwAZAQAEAAYJ5A0mkwAZAQAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.Jungg:BAAALgAECgIJAgAAAA==.',
Ka='Kaedren:BAAALgAECgQJDAAAAA==.Kaelaya:BAABLgAECn8cAAIjAAYJgwqoHADJAAAjAAYJgwqoHADJAAAAAA==.Kaelorien:BAABLgAECn89AAIfAAkJKRJoJgDyAQAfAAkJKRJoJgDyAQAAAA==.Kaetta:BAABLgAECn8XAAIIAAgJ0APiwwAEAQAIAAgJ0APiwwAEAQAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgYJDgAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAABLgAECn8fAAIbAAgJHhDtFwBfAQAbAAgJHhDtFwBfAQAAAA==.Kaldevayn:BAABLgAECn8VAAMBAAgJwhUrHgARAgABAAgJwhUrHgARAgAFAAEJqQrlLwAtAAAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgQJBgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8oAAIcAAYJbw0LmQDvAAAcAAYJbw0LmQDvAAAAAA==.Kandandris:BAAALgAECgYJBgAAAA==.Kardanis:BAABLgAECn8sAAIPAAkJviRqAgCiAwAPAAkJviRqAgCiAwAAAA==.Kashe:BAABLgAECn8bAAIBAAUJ3x0yMACZAQABAAUJ3x0yMACZAQAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAABLgAECn8nAAIPAAkJZxKHPAC8AQAPAAkJZxKHPAC8AQAAAA==.Kaydencia:BAABLgAECn8XAAIFAAYJvxET0gDwAAAFAAYJvxET0gDwAAAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgQJBgAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgAECgYJBwAAAA==.Khortical:BAAALgADCgkJCQABLgAECgkJMAAiANUgAA==.',
Ki='Ki:BAAALgAECgQJBAAAAA==.Kiddow:BAABLgAECn8UAAIIAAYJWw8xvwAKAQAIAAYJWw8xvwAKAQAAAA==.Kierea:BAAALgAECgMJAwAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgAECgEJAQAAAA==.Kiri:BAAALgADCgkJEQAAAA==.Kitamii:BAABLgAECn8UAAIYAAYJdRbHEQCQAQAYAAYJdRbHEQCQAQAAAA==.Kivrin:BAABLgAECn8XAAIGAAgJ6QxeAgBiAQAGAAgJ6QxeAgBiAQAAAA==.',
Kr='Kringlë:BAABLgAECn8oAAIEAAkJ3SDEGACSAgAEAAkJ3SDEGACSAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kurumi:BAAALgAECgIJAgAAAA==.Kushwizard:BAAALgADCgQJBQAAAA==.Kuunko:BAAALgAECgEJAQAAAA==.',
Ky='Kymma:BAABLgAECn80AAIFAAkJKA5qDgDIAAAFAAkJKA5qDgDIAAAAAA==.Kyunix:BAAALgAECgYJBgAAAA==.',
La='Lagoriatsua:BAABLgAECn8ZAAIVAAgJlQZYUgDvAAAVAAgJlQZYUgDvAAAAAA==.Laitue:BAAALgAECgQJDAAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgcJEwAAAA==.Lazengann:BAABLgAECn8mAAMcAAkJnRanOwDZAQAcAAkJERWnOwDZAQANAAIJ/BnGXABUAAAAAA==.',
Le='Leafbane:BAAALgAECgMJAwAAAA==.Leagann:BAAALgAECgEJAQAAAA==.Legevia:BAABLgAECn8cAAMiAAcJrQQzJADVAAAiAAcJrQQzJADVAAAPAAIJkgKWzwA8AAAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAABLgAECn88AAIFAAkJDRFrWgC+AQAFAAkJDRFrWgC+AQAAAA==.Leisha:BAAALgADCgEJAQAAAA==.Letifer:BAAALgADCgkJDAAAAA==.Leucetios:BAAALgAECgQJCgAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8iAAILAAkJRxmTDgB/AgALAAkJRxmTDgB/AgAAAA==.Lightbeard:BAABLgAECn8pAAQBAAcJHRxYHgAQAgABAAcJHRxYHgAQAgAFAAIJ+wUDbwFJAAAbAAEJ4A/gUwApAAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAABLgAECn8WAAIFAAgJ7RgPbQCUAQAFAAgJ7RgPbQCUAQAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgAECgQJBgAAAA==.Liubing:BAAALgADCgIJAgABLgADCgYJGwAOAAAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lochli:BAAALgAECgUJBQAAAA==.Lorredain:BAAALgAECgQJCQAAAA==.Lothaire:BAAALgADCgEJAQABLgADCgIJAgAOAAAAAA==.Lothwen:BAAALgAECgYJDAAAAA==.Louisachan:BAAALgADCgUJBQABLgAFFAEJAgAOAAAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8WAAILAAUJFxCzFAAeAQALAAUJFxCzFAAeAQAuAAQKfzcAAgsACQmPFrUXABACAAsACQmPFrUXABACAAAA.Luxinine:BAABLgAECn8qAAMGAAkJPCB6BgDqAgAGAAkJPCB6BgDqAgAHAAIJsxSHCACDAAAAAA==.',
Ly='Lyon:BAAALgADCgMJCgAAAA==.Lyshai:BAAALgAECgYJBgABLgAECgcJHgAkANIfAA==.',
Ma='Magamon:BAABLgAECn8uAAIIAAkJfBdkOgAwAgAIAAkJfBdkOgAwAgAAAA==.Magamus:BAAALgADCgYJBgAAAA==.Mahndarb:BAAALgAECgYJEAABLgAECggJJQALAE8dAA==.Majima:BAAALgAECgYJDgAAAA==.Makedeader:BAAALgAECgkJBgAAAA==.Malfuriia:BAABLgAECn8kAAIPAAcJhxuuLAAGAgAPAAcJhxuuLAAGAgAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Mamboke:BAAALgAECgcJDgAAAA==.Margerdria:BAABLgAECn8VAAIGAAUJDQ0cVADCAAAGAAUJDQ0cVADCAAAAAA==.Maskelle:BAABLgAECn8tAAISAAkJvBGTDgBnAQASAAkJvBGTDgBnAQAAAA==.Mauugrim:BAABLgAECn8pAAIUAAkJ9giuDADJAAAUAAkJ9giuDADJAAAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAABLgAECn8cAAIFAAcJXRZ2cACNAQAFAAcJXRZ2cACNAQAAAA==.',
Me='Mearadan:BAAALgAECgkJDwAAAA==.Meatsweats:BAABLgAECn8lAAIFAAgJEQvjrAAkAQAFAAgJEQvjrAAkAQAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDwAAAA==.Mekh:BAABLgAECn8eAAMkAAcJ0h9ABQAPAgAkAAcJ0h9ABQAPAgAlAAMJOhMmKwCTAAAAAA==.Mel:BAAALgAECgMJCgAAAA==.Melanara:BAABLgAECn9LAAIIAAkJNA8aBQCHAQAIAAkJNA8aBQCHAQAAAA==.Melstrom:BAAALgAECggJDgAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgYJBwAAAA==.Meticuluslyn:BAAALgAECgYJEgAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAABLgAECn8WAAIhAAkJ0RO9AwDVAQAhAAkJ0RO9AwDVAQAAAA==.Miyävii:BAABLgAECn8YAAIbAAkJxxNGFwBmAQAbAAkJxxNGFwBmAQAAAA==.',
Mj='Mjsage:BAABLgAECn8kAAIEAAkJGR6yJABQAgAEAAkJGR6yJABQAgAAAA==.',
Mm='Mmeow:BAAALgAECgQJBQABLgAECgkJFQAEAMkZAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8fAAIGAAcJfhkFIgC3AQAGAAcJfhkFIgC3AQAAAA==.Mooasha:BAAALgAECgEJAQABLgAECgkJJwAPAGcSAA==.Moonflowers:BAACLgAFFH8fAAIMAAgJ/BkJCAB9AgAMAAgJ/BkJCAB9AgAuAAQKfy8AAgwACAmcJM4HAA8DAAwACAmcJM4HAA8DAAAA.Mordsevoker:BAAALgAFFAIJAgABLgAFFAUJFwAUAFwSAA==.Morginoth:BAAALgADCgcJBwAAAA==.Morregu:BAAALgAECgQJBQAAAA==.Mousekee:BAABLgAECn8qAAILAAkJkw2UJwCJAQALAAkJkw2UJwCJAQAAAA==.',
Mu='Muku:BAAALgADCgkJCQABLgAECgkJTQAIAJURAA==.Murdrmitts:BAABLgAECn8qAAIYAAkJwQ4fAQB0AQAYAAkJwQ4fAQB0AQAAAA==.Mustikka:BAABLgAECn8bAAIYAAUJsQ/eKQDDAAAYAAUJsQ/eKQDDAAAAAA==.',
My='Mystikah:BAAALgAECgEJAQAAAA==.Myuriyanka:BAABLgAECn8pAAMVAAkJoBOGJADDAQAVAAkJoBOGJADDAQAPAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgYJBwAOAAAAAA==.',
Na='Naahommii:BAABLgAECn8hAAIEAAkJxRRLQgDbAQAEAAkJxRRLQgDbAQAAAA==.Nachtpranke:BAABLgAECn8ZAAIMAAgJ9B4rGACFAgAMAAgJ9B4rGACFAgAAAA==.Nadron:BAAALgAECgYJDAAAAA==.Naevala:BAAALgAECgkJCgAAAA==.Nagualli:BAAALgAECgQJBQAAAA==.',
Ne='Negargra:BAABLgAECn8tAAMTAAYJ/REjBwDzAAATAAYJ/REjBwDzAAAmAAEJcgMufAAkAAAAAA==.Nekwid:BAAALgADCgIJAgAAAA==.Nephadin:BAABLgAECn8dAAMFAAgJpAr7uQARAQAFAAgJpAr7uQARAQABAAUJnAbNWQDPAAAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgYJDgAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAABLgAECn8bAAIMAAUJ8gwZgAC6AAAMAAUJ8gwZgAC6AAAAAA==.Nikooli:BAABLgAECn8iAAMNAAgJaxcoGgCvAQANAAgJaxcoGgCvAQASAAEJ+AYlPQAaAAAAAA==.Nimb:BAAALgAECgEJBAAAAA==.',
No='Nokkoh:BAAALgADCgQJBwAAAA==.Nolime:BAAALgAECgYJBwAAAA==.Noodledragon:BAAALgAECgYJBwAAAA==.Noopsie:BAABLgAECn8uAAIMAAgJRguOVAA+AQAMAAgJRguOVAA+AQAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAgJKAAlADQQAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMHAAgJxhqHFwAZAgAHAAcJLhyHFwAZAgAGAAcJsBxlLAByAQAAAA==.Notpeepuddle:BAAALgAECgEJAQAAAA==.Novarox:BAAALgAECgEJAQAAAA==.',
Nu='Nuhnoo:BAAALgADCgkJCQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8nAAIFAAcJohtyTADhAQAFAAcJohtyTADhAQAAAA==.Nyxalia:BAAALgAECgYJCAAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMhAAkJbgM/EgCgAAAIAAkJWQMu4ADaAAAhAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBQAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCggJDwAAAA==.Olympia:BAABLgAECn8uAAIbAAkJ0A1WHQAqAQAbAAkJ0A1WHQAqAQAAAA==.',
Or='Oraclemega:BAABLgAECn80AAIIAAkJBSA5EAD6AgAIAAkJBSA5EAD6AgAAAA==.Orweyna:BAAALgAECggJDwAAAA==.',
Os='Oscarmikey:BAACLgAFFH8dAAMMAAUJew0ZCAAKAQAMAAUJew0ZCAAKAQAdAAEJhAECVgAqAAAuAAQKfz8ABQwACQlHHoAQAM0CAAwACQlHHoAQAM0CAB0ABglhFbA3ADYBABgAAQlMAr1hACAAACAAAQkAAOuUAAAAAAAA.Oshu:BAAALgAECgYJBgAAAA==.',
Ot='Ottoshot:BAABLgAECn8iAAIEAAcJyxLbZgB2AQAEAAcJyxLbZgB2AQAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
Ow='Owlaf:BAAALgAECgEJAQAAAA==.',
['Oö']='Oöps:BAAALgAECggJEwAAAA==.',
Pa='Paksen:BAAALgAECgEJAQAAAA==.Panamone:BAABLgAECn8iAAMYAAcJRyOrCgAVAgAYAAYJuySrCgAVAgAMAAIJBRZfmACBAAAAAA==.Pandeism:BAABLgAECn80AAMiAAkJZxTZDgDDAQAiAAgJHxTZDgDDAQAPAAcJoBeDBwD6AAAAAA==.Papagrip:BAABLgAECn8wAAMRAAkJ7xJZDACyAQARAAkJ7xJZDACyAQAUAAgJCgr6pgAhAQAAAA==.Patrin:BAABLgAECn8gAAIIAAgJZw3ggwBwAQAIAAgJZw3ggwBwAQAAAA==.Paulee:BAAALgADCgkJDgAAAA==.',
Pe='Peanutbritle:BAABLgAECn8oAAIQAAkJaAZrLgDrAAAQAAkJaAZrLgDrAAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.',
Ph='Phantdoom:BAAALgAECgYJEQAAAA==.Phean:BAAALgAECgEJAQAAAA==.Phylah:BAAALgAECgMJBAAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAECggJKQAFAA8lAA==.',
Pl='Plsdiddyno:BAAALgAFFAEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgMJBgAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Puchi:BAAALgAECgUJBQAAAA==.Punchabaal:BAAALgAECgcJDAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAIMAAcJWRnvMwDZAQAMAAcJWRnvMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgQJBAAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Redrollin:BAAALgAECgEJAQAAAA==.Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAYJLAAhAEQlAA==.Reyrocko:BAAALgAFFAEJAQAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAQJDQAGABsdAA==.Rezdk:BAAALgAECggJCAABLgAFFAQJDQAGABsdAA==.Rezhunt:BAABLgAFFH8FAAMjAAQJJxn/GQDjAAAjAAMJrhj/GQDjAAAaAAEJkhr2LwBUAAABLgAFFAQJDQAGABsdAA==.Rezmonk:BAAALgAECgcJCgABLgAFFAQJDQAGABsdAA==.Rezshift:BAABLgAECn8bAAMdAAgJwhzjFQAgAgAdAAgJwhzjFQAgAgAMAAQJBRbtbwAFAQABLgAFFAQJDQAGABsdAA==.Rezvoid:BAACLgAFFH8NAAMGAAQJGx0AFQA9AQAGAAQJGx0AFQA9AQALAAIJgyHwIgCjAAAuAAQKfzQAAwYACQkQI84GAOUCAAYACQkQI84GAOUCAAsAAgmjIPFJAL0AAAAA.',
Rh='Rhage:BAAALgAECgMJBwAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAABLgAECn8XAAIUAAcJlRKnngAuAQAUAAcJlRKnngAuAQAAAA==.Roxane:BAABLgAECn8lAAIdAAkJxQmQMABbAQAdAAkJxQmQMABbAQAAAA==.',
Ru='Runningelk:BAABLgAECn8xAAIgAAkJvBLbFQClAQAgAAkJvBLbFQClAQAAAA==.Runscapemain:BAABLgAECn8rAAMFAAkJ4hbwVADLAQAFAAkJ4hbwVADLAQAbAAYJ/RAUIwD8AAAAAA==.',
Ry='Ryeti:BAAALgADCgkJFwAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDgANAAEkAA==.',
Sa='Saintulrick:BAAALgAECgIJAwAAAA==.Sajuice:BAACLgAFFH8HAAIjAAUJPwW5GwDSAAAjAAUJPwW5GwDSAAAuAAQKfyYAAiMACAnAGyIKAM8BACMACAnAGyIKAM8BAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn8mAAMLAAkJlw7UKwBrAQALAAkJlw7UKwBrAQAGAAEJmAMQlwAjAAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAOAAAAAA==.',
Se='Seeyen:BAACLgAFFH8ZAAIEAAYJ9hW8MwBGAQAEAAYJ9hW8MwBGAQAuAAQKfywAAgQACQnSHgUHAB8DAAQACQnSHgUHAB8DAAAA.Selfdestruct:BAABLgAECn8UAAIFAAgJCwtMCQATAQAFAAgJCwtMCQATAQAAAA==.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8lAAIkAAkJgwrgCgBsAQAkAAkJgwrgCgBsAQAAAA==.Seren:BAAALgAFFAEJAwABLgAFFAcJGAAIAMALAA==.Serenityhate:BAABLgAECn8jAAMLAAYJVQ3RPQD7AAALAAYJVQ3RPQD7AAAGAAEJAABzoAAAAAAAAA==.',
Sh='Shaaydo:BAAALgAECgEJBAAAAA==.Shaaytheyha:BAAALgAECgMJAwAAAA==.Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgYJCAAAAA==.Shandrilyn:BAABLgAECn8YAAIGAAcJIARnUQDMAAAGAAcJIARnUQDMAAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAIlAAkJwBQgGABQAQAlAAkJwBQgGABQAQAAAA==.Shiziuno:BAAALgAECgQJBAAAAA==.',
Si='Sini:BAAALgAFFAcJBAABLgAFFAkJNAAcANglAA==.Sinthoras:BAAALgAECgQJBAAAAA==.Sionarra:BAAALgADCgIJAgAAAA==.',
Sj='Sjðfn:BAAALgAECgkJAgAAAA==.',
Sk='Skala:BAABLgAECn8YAAInAAkJThZnHADyAQAnAAkJThZnHADyAQAAAA==.Skibbie:BAACLgAFFH8eAAMnAAcJbgwBHgBwAQAnAAcJbgwBHgBwAQAkAAQJOwoCBgD9AAAuAAQKfx4ABCcACQk4GF8QAHMCACcACQk4GF8QAHMCACUABAmHDpImALgAACQABQnOBpAsALcAAAAA.Skibbward:BAABLgAECn8zAAQgAAgJTiS4AQAyAwAgAAgJTiS4AQAyAwAdAAUJxQ9jVADUAAAMAAYJ6QrsggDSAAABLgAFFAcJHgAnAG4MAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAABLgAECn8XAAIPAAgJRR4vFACqAgAPAAgJRR4vFACqAgAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Slickdeath:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgEJBQABLgAECgIJBwAOAAAAAA==.',
Sm='Smackdogg:BAACLgAFFH8IAAIdAAUJKBxOFwBgAQAdAAUJKBxOFwBgAQAuAAQKfxkAAh0ABwk9HRcdABgCAB0ABwk9HRcdABgCAAEuAAUUCAkwABUAnyAA.',
So='Solteria:BAABLgAECn8VAAIJAAcJqAk/DgBOAQAJAAcJqAk/DgBOAQABLgAECgkJAgAOAAAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAABLgAECn8ZAAINAAcJxxDFKAA2AQANAAcJxxDFKAA2AQAAAA==.Sorvina:BAABLgAECn84AAITAAkJdBKsQADaAQATAAkJdBKsQADaAQAAAA==.Soulflame:BAABLgAECn9NAAIIAAkJlRGYBwA/AQAIAAkJlRGYBwA/AQAAAA==.Soulshifter:BAABLgAECn8YAAIdAAcJswqlRQD2AAAdAAcJswqlRQD2AAAAAA==.Soultrader:BAAALgADCgkJFwABLgAECgUJHQAbAN0SAA==.',
Sp='Spacetime:BAAALgAECgEJAQAAAA==.Spooñ:BAAALgADCgcJBwABLgAFFAUJFgAfAEocAA==.Spottedcoat:BAABLgAECn8oAAIMAAkJdwNnfADDAAAMAAkJdwNnfADDAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgABLgAECgkJGQAUAEUZAA==.Stasia:BAAALgADCgkJCQAAAA==.Strangerx:BAAALgAECgEJAgAAAA==.Stregnor:BAABLgAECn88AAIEAAkJBBh5JQBMAgAEAAkJBBh5JQBMAgAAAA==.Styggi:BAAALgAECgIJAwAAAA==.Styggian:BAAALgAECgUJBwAAAA==.Stygy:BAAALgAECgMJBAAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDgANAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn9DAAMeAAgJehi0GQDjAQAeAAgJehi0GQDjAQAZAAUJsQ7PUQC8AAAAAA==.',
Sv='Svéria:BAAALgADCgMJAwAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMnAAkJDxKrEwBHAgAnAAkJfhGrEwBHAgAkAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgkJJgAnAB4bAA==.Tachie:BAABLgAECn8mAAMnAAkJHhtEDwByAgAnAAkJuBpEDwByAgAkAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAcJGwAJAAQmAA==.Taele:BAABLgAECn8tAAMIAAkJTxzKJwB7AgAIAAkJtBvKJwB7AgAhAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn9KAAIdAAkJZxUxAQDvAQAdAAkJZxUxAQDvAQAAAA==.Tamalpais:BAABLgAECn8dAAIEAAUJZhHuEQCuAAAEAAUJZhHuEQCuAAAAAA==.Tamarind:BAAALgAECgYJBgABLgAECgkJMAAiANUgAA==.Tamzred:BAAALgAECgYJBgABLgAECgkJJwAFAEcVAA==.Tanyab:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8kAAIEAAcJ2QM6sQDiAAAEAAcJ2QM6sQDiAAAAAA==.',
Th='Thaesan:BAAALgAECgYJDwAAAA==.Therin:BAABLgAECn8wAAIaAAkJHRWEEwAKAgAaAAkJHRWEEwAKAgAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tillymonick:BAAALgAECgUJCAAAAA==.Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgcJGQAAAA==.Toofast:BAABLgAECn9AAAIPAAkJhiGzCgALAwAPAAkJhiGzCgALAwAAAA==.Toofurrious:BAAALgADCgkJOgAAAA==.Topswimmer:BAACLgAFFH8JAAIIAAIJvQheLwB/AAAIAAIJvQheLwB/AAAuAAQKfxkAAggABwlSFsxsAKEBAAgABwlSFsxsAKEBAAAA.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgUJBgAAAA==.',
Tr='Traci:BAABLgAECn8eAAIgAAgJyxUBGACRAQAgAAgJyxUBGACRAQAAAA==.Trifus:BAABLgAECn8pAAMQAAkJ6hg4GACiAQAQAAgJlRc4GACiAQAUAAcJ0w84ZACfAQAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAABLgAECn8hAAIMAAYJHR5TKgADAgAMAAYJHR5TKgADAgAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQABLgAECgQJBgAOAAAAAA==.',
Tu='Tulao:BAABLgAECn80AAIIAAgJGyBhMgBPAgAIAAgJGyBhMgBPAgAAAA==.',
Tw='Twan:BAAALgAFFAEJAgABLgAFFAgJFQAcAAUVAA==.',
Ty='Tyledoriel:BAAALgADCgEJAQAAAA==.Tyrionel:BAAALgAECgUJCgAAAA==.',
Tz='Tzitzimitl:BAAALgAECgYJBwAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIfAAQJaRDxNADXAAAfAAQJaRDxNADXAAAAAA==.',
Ut='Utheli:BAACLgAFFH8SAAIFAAQJqRMfQwAlAQAFAAQJqRMfQwAlAQAuAAQKfx8AAgUACAkBG95MAOABAAUACAkBG95MAOABAAAA.',
Va='Vaevictis:BAAALgAECggJEgAAAA==.Vaildora:BAAALgAECgEJAQABLgAECgkJJgAnAB4bAA==.Valdra:BAABLgAECn89AAIDAAkJGRPtEgC9AQADAAkJGRPtEgC9AQAAAA==.Valkyl:BAAALgAECgEJAQAAAA==.Valkylpriest:BAAALgAECgEJAgAAAA==.',
Vi='Vidiablade:BAAALgAFFAIJAgAAAA==.Viralprepped:BAAALgAECgMJCgAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8hAAMcAAkJbxFWUACVAQAcAAkJbxFWUACVAQANAAYJEg7zNADrAAAAAA==.',
Vn='Vnasty:BAACLgAFFH8QAAIFAAYJ+gwIUgALAQAFAAYJ+gwIUgALAQAuAAQKfywAAgUACQkrICkKAD8DAAUACQkrICkKAD8DAAAA.',
Vo='Vogue:BAAALgADCgcJBQAAAA==.',
Vr='Vrale:BAAALgAFFAIJAgAAAA==.',
['Vì']='Vì:BAAALgAECgMJAwABLgAFFAYJEAAFAPoMAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Wes:BAAALgAECgEJAQAAAA==.Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wildbear:BAAALgAECgYJBgAAAA==.Wilken:BAABLgAECn8zAAIoAAkJNRniCABjAgAoAAkJNRniCABjAgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8nAAIFAAkJ/xp6MQA6AgAFAAkJ/xp6MQA6AgAAAA==.',
Ws='Wspr:BAAALgAECgIJBgAAAA==.',
Wu='Wulff:BAAALgADCgMJBgAAAA==.',
Xa='Xaartahli:BAAALgAECgUJEAAAAA==.Xavencia:BAABLgAECn8XAAIIAAkJbgb4BwA3AQAIAAkJbgb4BwA3AQAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xe='Xenolithia:BAAALgAECgQJBQAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECgYJCAAAAA==.',
Ya='Yanut:BAABLgAECn8UAAIFAAYJqQdC7ADPAAAFAAYJqQdC7ADPAAAAAA==.',
Ye='Yeetjin:BAAALgAECgcJCQAAAA==.',
Yi='Yinamin:BAAALgAECgYJEwAAAA==.',
Yk='Yknub:BAAALgAECgIJAgAAAA==.',
Yo='Yotin:BAAALgAECgYJBgAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAABLgAECn8iAAIMAAkJPRT5JQAeAgAMAAkJPRT5JQAeAgAAAA==.Zalanto:BAAALgAECgEJAgAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn9VAAIEAAkJ/xQkAwDzAQAEAAkJ/xQkAwDzAQAAAA==.',
Ze='Zedraikis:BAAALgAECgEJAQAAAA==.Zelgaddis:BAABLgAECn8sAAMPAAkJCxTvAgCyAQAPAAkJCxTvAgCyAQAiAAIJTQSwQQAsAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn8pAAInAAcJChFRPwAsAQAnAAcJChFRPwAsAQAAAA==.',
Zr='Zrathan:BAEALgAECgEJAQABLgAECgIJAgAOAAAAAA==.Zriana:BAAALgAECgQJCAAAAA==.',
Zs='Zsarilya:BAABLgAECn8tAAILAAkJWQKDBwCAAAALAAkJWQKDBwCAAAAAAA==.',
Zu='Zurgen:BAABLgAECn89AAITAAkJiyDrDADmAgATAAkJiyDrDADmAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8yAAIMAAgJghUaKQAKAgAMAAgJghUaKQAKAgABLgAFFAUJFgALABcQAA==.',
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
