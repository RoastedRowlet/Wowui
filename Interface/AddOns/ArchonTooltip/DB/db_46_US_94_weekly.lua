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

local lookup = {'Paladin-Holy','Warrior-Fury','Warrior-Protection','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','Mage-Frost','Warlock-Affliction','Mage-Fire','Priest-Holy','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Vengeance','Warlock-Demonology','DeathKnight-Unholy','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Brewmaster','Hunter-Survival','DemonHunter-Devourer','Druid-Balance','Monk-Windwalker','Monk-Mistweaver','Druid-Guardian','Mage-Arcane','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Evoker-Augmentation','Warrior-Arms',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aarchon:BAABLgAECn8qAAIBAAkJhB+ZCQDyAgABAAkJhB+ZCQDyAgAAAA==.',
Ad='Aduin:BAABLgAECn8hAAMCAAkJbxSjNgBtAQACAAkJbw6jNgBtAQADAAQJexs4JgAAAQAAAA==.',
Ae='Aedarelyn:BAABLgAECn8WAAMEAAcJwhDBHwB9AAAEAAcJwhDBHwB9AAAFAAEJGAa1XAAWAAAAAA==.Aellita:BAABLgAECn8VAAIGAAYJZwhFqgDuAAAGAAYJZwhFqgDuAAAAAA==.Aeschylus:BAABLgAECn8WAAIEAAkJYg+ODwD8AAAEAAkJYg+ODwD8AAAAAA==.',
Af='Afkinlife:BAAALgADCgIJAgAAAA==.',
Ak='Akky:BAABLgAECn8tAAIDAAkJKiH/BgCXAgADAAkJKiH/BgCXAgAAAA==.Aksafiya:BAABLgAECn9fAAMHAAkJhxRKGgDzAQAHAAkJhxRKGgDzAQAIAAEJWAINiwAcAAAAAA==.',
Al='Alal:BAABLgAECn8iAAIJAAgJmg0AnwA8AQAJAAgJmg0AnwA8AQAAAA==.Alandras:BAABLgAECn8tAAICAAkJAAnkQQA9AQACAAkJAAnkQQA9AQAAAA==.Alaras:BAACLgAFFH8eAAIHAAcJ/g76CwCgAQAHAAcJ/g76CwCgAQAuAAQKfxcAAgcACQnQFQ8aAA8CAAcACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8rAAIKAAkJcxexBwDzAQAKAAkJcxexBwDzAQAAAA==.Allrianne:BAAALgAECgQJDgAAAA==.Allyriae:BAABLgAECn8WAAILAAgJDgkgCQD0AAALAAgJDgkgCQD0AAAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8lAAIMAAgJTx1gDwBzAgAMAAgJTx1gDwBzAgAAAA==.',
Am='Ambilena:BAABLgAECn8vAAMMAAkJhRVMLQBiAQAMAAYJVhhMLQBiAQAHAAkJeBApBQAjAQAAAA==.',
An='Andoros:BAABLgAECn86AAINAAkJax6bEADMAgANAAkJax6bEADMAgAAAA==.Angiliana:BAABLgAECn8UAAIOAAUJAw8sPQDCAAAOAAUJAw8sPQDCAAAAAA==.Angvall:BAAALgAECgYJCAABLgAFFAMJBAAPAAAAAA==.Animainiac:BAAALgAECgYJBgABLgAECgkJKQAQAGcSAA==.Anzurath:BAABLgAECn8pAAIEAAkJzxVqTgDcAQAEAAkJzxVqTgDcAQAAAA==.',
Ap='Applebow:BAABLgAECn8tAAIRAAkJ/hFEBQDYAAARAAkJ/hFEBQDYAAAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgAECggJDgAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECggJEQAAAA==.Armas:BAAALgAECggJCAAAAA==.Arylin:BAABLgAECn82AAIJAAkJlSMiCgApAwAJAAkJlSMiCgApAwAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEBLgAECn8dAAMDAAcJSxJGLQDRAAADAAYJoxJGLQDRAAACAAIJHhEKGwAxAAAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQAPAAAAAA==.Asky:BAAALgADCgYJBwABLgAECgkJKAAJAHEDAA==.Asmodean:BAAALgAECgEJAQAAAA==.Asnabel:BAABLgAECn80AAISAAkJaw/oAQBNAQASAAkJaw/oAQBNAQAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astrai:BAAALgADCgcJBwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCgARAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgAECgQJDAAAAA==.Ayden:BAABLgAECn8eAAMOAAgJbhmBGAC/AQAOAAcJxxmBGAC/AQATAAMJNhXOAwCaAAAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwAPAAAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgMJBQAAAA==.',
Bl='Blee:BAABLgAECn8+AAMIAAkJNBDNAwB6AQAIAAkJNBDNAwB6AQAHAAQJlgWRSgCwAAAAAA==.Bloodbourne:BAAALgAECgEJAQAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.Bluudclaaw:BAAALgAECgYJBwAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8lAAIUAAcJVh6rOAD3AQAUAAcJVh6rOAD3AQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8uAAIGAAkJxiHrHwBoAgAGAAkJxiHrHwBoAgAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8eAAIVAAkJOhAjdgB3AQAVAAkJOhAjdgB3AQAAAA==.Brood:BAABLgAECn8rAAIVAAkJyBRRUQDPAQAVAAkJyBRRUQDPAQAAAA==.Brundles:BAAALgAECgYJBgAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAABLgAECn9EAAMWAAgJtQmJBgD+AAAWAAgJtQmJBgD+AAAQAAUJFgjEkAC3AAAAAA==.',
Ca='Cailaranel:BAABLgAECn8uAAMXAAkJigkUJAB0AQAXAAkJ0wcUJAB0AQAYAAcJaQlUEAAfAQAAAA==.Calaul:BAABLgAECn8vAAIEAAkJ6hQ0CgBGAQAEAAkJ6hQ0CgBGAQAAAA==.Calenbraga:BAABLgAECn9HAAIZAAkJhxosAQDDAQAZAAkJhxosAQDDAQAAAA==.Calisim:BAABLgAECn8hAAIUAAYJMwcZwADLAAAUAAYJMwcZwADLAAAAAA==.Callidae:BAABLgAECn8qAAIMAAkJBxEwHADlAQAMAAkJBxEwHADlAQAAAA==.Callum:BAAALgADCgMJAwAAAA==.Calmnbald:BAABLgAECn8ZAAIaAAcJeBfGPAAIAQAaAAcJeBfGPAAIAQAAAA==.Caloh:BAAALgAECgYJCQAAAA==.Cantallbis:BAAALgADCgcJBwAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8lAAIbAAkJlgwuHQCzAQAbAAkJlgwuHQCzAQAAAA==.Cataryn:BAABLgAECn8mAAIGAAkJNSRwDwDVAgAGAAkJNSRwDwDVAgAAAA==.Catt:BAABLgAECn9LAAIBAAkJGBkDFABvAgABAAkJGBkDFABvAgAAAA==.',
Ce='Cellebur:BAABLgAECn8lAAIGAAgJ5Ac2HQCOAAAGAAgJ5Ac2HQCOAAAAAA==.Ceta:BAABLgAECn87AAIMAAkJDhyuDQCLAgAMAAkJDhyuDQCLAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAACLgAFFH8HAAMWAAMJWQvHTABjAAAWAAIJ7QTHTABjAAAQAAIJ3QIYeQBMAAAuAAQKfysAAxAACAncEfA9ALYBABAACAncEfA9ALYBABYABwm2GRMuAIoBAAAA.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn9QAAIJAAkJjguSCgBCAQAJAAkJjguSCgBCAQAAAA==.Cinderelah:BAAALgAECgEJAQAAAA==.Cizean:BAABLgAECn8oAAIJAAkJcQODIQBvAAAJAAkJcQODIQBvAAAAAA==.',
Cr='Craivan:BAAALgAECgUJDwAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crill:BAAALgAECgUJBgAAAA==.Crilly:BAABLgAECn8rAAIJAAkJZRj5OgAtAgAJAAkJZRj5OgAtAgAAAA==.Crowe:BAAALgAECgUJCgABLgAECgUJBQAPAAAAAA==.Crowley:BAAALgADCgMJAwAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAABLgAECn8aAAIQAAgJfw0QEgCNAAAQAAgJfw0QEgCNAAAAAA==.Cyrr:BAAALgAECggJDwAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJDAAAAA==.Damia:BAABLgAECn8tAAMXAAkJPBjpFgDlAQAXAAkJPBjpFgDlAQAYAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8mAAIRAAkJ8CQHBAD5AgARAAkJ8CQHBAD5AgAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgIJBQABLgAECgkJJgARAPAkAA==.Delvarrieth:BAABLgAECn8oAAIFAAkJvQ3dHgAdAQAFAAkJvQ3dHgAdAQAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Demonzar:BAAALgAECgYJCgAAAA==.Demzy:BAAALgAECgYJBwAAAA==.Denth:BAABLgAECn8gAAIEAAkJsQ4EbgCSAQAEAAkJsQ4EbgCSAQAAAA==.Dercuur:BAABLgAECn8dAAIWAAgJVRfOJADBAQAWAAgJVRfOJADBAQAAAA==.Devoursol:BAABLgAECn85AAMcAAkJlQz+WAB8AQAcAAkJaAz+WAB8AQAOAAIJrg45XABvAAAAAA==.',
Di='Dipndots:BAAALgAECgYJBwABLgAECgkJJgARAPAkAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Doist:BAAALgAECgIJAgAAAA==.Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgAECgYJDAAAAA==.Drainmee:BAABLgAECn8lAAMIAAYJNBRzMABcAQAIAAYJNBRzMABcAQAHAAUJagSxZQCFAAAAAA==.Draknol:BAAALgAECgEJAQAAAA==.Dreadspark:BAABLgAECn8bAAMUAAkJ8xyaHgBtAgAUAAkJTRyaHgBtAgAKAAQJdx0aGAC6AAAAAA==.Dregoth:BAABLgAECn8tAAIVAAkJdAnjCQAsAQAVAAkJdAnjCQAsAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8hAAMNAAkJ4R5kEAC0AgANAAkJ4R5kEAC0AgAdAAEJxgkemgAnAAAAAA==.',
Ea='Eathur:BAAALgAECgYJBgAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elunariel:BAAALgAECgEJAgABLgAECgkJGwAUAPMcAA==.Elynth:BAABLgAECn8nAAIUAAkJcxx2IgBYAgAUAAkJcxx2IgBYAgAAAA==.',
En='Endlessyueh:BAABLgAECn8lAAMEAAcJxA8hyAD9AAAEAAYJCxAhyAD9AAABAAcJFwdeCQCVAAAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgkJGwAUAPMcAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAFFAQJBAABLgAFFAYJEAAEAPoMAA==.',
Fa='Face:BAAALgAECggJBgAAAA==.Faethian:BAACLgAFFH8UAAIFAAUJSiFwAwBxAQAFAAUJSiFwAwBxAQAuAAQKfywAAgUACAk7JacDANUCAAUACAk7JacDANUCAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8xAAIJAAkJ6wnDiwBgAQAJAAkJ6wnDiwBgAQAAAA==.Fangren:BAABLgAECn8mAAIGAAYJtxL/GACvAAAGAAYJtxL/GACvAAAAAA==.Fariah:BAAALgAECgUJEwAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAABLgAECn8YAAIeAAcJ6QeSRwDhAAAeAAcJ6QeSRwDhAAAAAA==.',
Fe='Felscythe:BAABLgAECn8nAAIaAAkJnwEmBwB9AAAaAAkJnwEmBwB9AAAAAA==.Felynn:BAABLgAECn8sAAIBAAkJgxj9FQBcAgABAAkJgxj9FQBcAgAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feresdenn:BAAALgADCgQJBAAAAA==.Feyrha:BAAALgADCgYJBgABLgAECgkJMAAGAAUQAA==.',
Fi='Fiadh:BAAALgAECgQJBgAAAA==.Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8iAAIfAAkJXR0OHwAhAgAfAAkJXR0OHwAhAgAAAA==.',
Fl='Flaeli:BAABLgAECn8rAAIJAAkJzhmkCwA1AQAJAAkJzhmkCwA1AQAAAA==.Flameshot:BAAALgADCgkJCQABLgAECgkJLwAgAHUQAA==.Flemish:BAABLgAECn8XAAIWAAcJ7xbrKwCWAQAWAAcJ7xbrKwCWAQAAAA==.Flextame:BAAALgAECgQJEQAAAA==.Flipalicious:BAABLgAECn9AAAMQAAkJehyQEQDCAgAQAAkJehyQEQDCAgAWAAIJSxRingA9AAAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8dAAIHAAcJaBcAKgCBAQAHAAcJaBcAKgCBAQABLgAECggJFQASAG0bAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Fu='Furriousyueh:BAAALgAECgMJAwAAAA==.',
['Fë']='Fënrír:BAAALgAECgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn8wAAIGAAkJBRCqCQBdAQAGAAkJBRCqCQBdAQAAAA==.Gangstafred:BAAALgADCgYJBgAAAA==.Gazo:BAABLgAECn8YAAMHAAcJRBnGHgDPAQAHAAcJRBnGHgDPAQAIAAEJqxFYFAA8AAABLgAECgkJLwAeAJoiAA==.',
Ge='Gemboss:BAABLgAECn9OAAMEAAkJHSIvDgD0AgAEAAkJHSIvDgD0AgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8uAAMJAAkJmxO4XwDBAQAJAAkJmxO4XwDBAQAhAAMJoAbAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8yAAIeAAkJsAstLQBYAQAeAAkJsAstLQBYAQAAAA==.Ginodh:BAABLgAECn8OAAIcAAgJtQ1eewApAQAcAAgJtQ1eewApAQABLgAECgkJGQARAPwNAA==.Ginomage:BAAALgAECgcJCgABLgAECgkJGQARAPwNAA==.Ginomonk:BAAALgAECgYJBgABLgAECgkJGQARAPwNAA==.Ginopally:BAAALgAECgYJCwABLgAECgkJGQARAPwNAA==.Girth:BAAALgAECgUJCgAAAA==.Gizelli:BAAALgAFFAEJAgAAAA==.',
Gl='Glorby:BAAALgAECgQJBAABLgAFFAIJBQAfAGMXAA==.',
Go='Gordonnpr:BAAALgAECgYJCAAAAA==.',
Gr='Groblock:BAAALgADCgYJEgAAAA==.Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAfAGMXAA==.Grubetsella:BAACLgAFFH8FAAIfAAIJYxduDwClAAAfAAIJYxduDwClAAAuAAQKfzcAAh8ACQlsIeEMAM0CAB8ACQlsIeEMAM0CAAAA.Grumpÿ:BAAALgADCgYJBgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIcAAYJXBvFUAC0AQAcAAYJXBvFUAC0AQAAAA==.Gumpers:BAABLgAECn8vAAIgAAkJdRCFBQDxAAAgAAkJdRCFBQDxAAAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gurl:BAAALgADCgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAABLgAECn8iAAIdAAYJtgPhbwBoAAAdAAYJtgPhbwBoAAAAAA==.',
Ha='Halfamazing:BAAALgAECgYJDAAAAA==.Hanoumatoi:BAAALgAECgkJDAAAAA==.Haradar:BAAALgADCgEJAQABLgAECgcJIAAFAKsTAA==.Haralambos:BAABLgAECn8gAAIFAAcJqxOyBQCwAAAFAAcJqxOyBQCwAAAAAA==.Haralogain:BAAALgAECgEJAQABLgAECgcJIAAFAKsTAA==.Harithon:BAABLgAECn8wAAIiAAkJ1SDXAwC9AgAiAAkJ1SDXAwC9AgAAAA==.Harlar:BAAALgAECgIJAwAAAA==.Havvöc:BAABLgAECn8sAAIBAAkJoBx5DADHAgABAAkJoBx5DADHAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAABLgAECn8pAAIDAAkJ5ANfKwDcAAADAAkJ5ANfKwDcAAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAABLgAECn8rAAIJAAYJ4wySEQDrAAAJAAYJ4wySEQDrAAAAAA==.Heyokagi:BAABLgAECn8vAAQZAAkJNyIrAgANAwAZAAkJNyIrAgANAwAgAAIJ1BS5JgBnAAANAAEJXwhz2wAqAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgkJGwAUAPMcAA==.Hordkilla:BAABLgAECn8wAAIEAAkJxAfflwBFAQAEAAkJxAfflwBFAQAAAA==.Hottdealer:BAAALgADCgUJBQAAAA==.Hownowbrncw:BAABLgAECn8lAAIEAAgJLxxGQgAAAgAEAAgJLxxGQgAAAgAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn82AAMcAAkJ2BwkFgCSAgAcAAkJ2BwkFgCSAgATAAEJphoiLgBKAAAAAA==.Hylda:BAAALgADCgUJBQAAAA==.Hymno:BAAALgAECgEJAgAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAABLgAECn8gAAQNAAkJChBzBABUAQANAAkJChBzBABUAQAdAAYJFgwYTADcAAAgAAEJmAMeiAAWAAAAAA==.',
Im='Imathdal:BAABLgAECn8tAAIjAAkJvRPfAACrAQAjAAkJvRPfAACrAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAPAAAAAA==.Insoniacyun:BAABLgAECn8cAAIJAAgJvws+jABfAQAJAAgJvws+jABfAQAAAA==.',
Is='Iselian:BAAALgAECgkJKQAAAQ==.Ishanu:BAABLgAECn8iAAIHAAkJ8B4eAQBZAgAHAAkJ8B4eAQBZAgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAPAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgAECgkJEgABLgAFFAIJAgAPAAAAAA==.Jax:BAACLgAFFH8NAAIJAAQJRCLATQBDAQAJAAQJRCLATQBDAQAuAAQKfykAAgkACAlFIxATADUDAAkACAlFIxATADUDAAAA.',
Jb='Jbelbueno:BAAALgAECgYJDAAAAA==.Jblockiv:BAAALgADCgcJDAAAAA==.Jbprimero:BAAALgAECgIJAgAAAA==.Jbshami:BAABLgAECn9BAAMQAAkJLiCBEgC5AgAQAAkJLiCBEgC5AgAWAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgUJBgAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn89AAIhAAkJWg6IBACrAQAhAAkJWg6IBACrAQAAAA==.Jetfires:BAABLgAECn9TAAIGAAkJPyDpDADsAgAGAAkJPyDpDADsAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAABLgAECn89AAIeAAgJ7Qk5BAASAQAeAAgJ7Qk5BAASAQAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jovie:BAAALgAECgEJAQAAAA==.Jozhua:BAABLgAECn8XAAIGAAYJ5A0mkwAZAQAGAAYJ5A0mkwAZAQAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.Jungg:BAAALgAECgIJAgAAAA==.',
Ka='Kaedren:BAAALgAECgQJDAAAAA==.Kaelaya:BAABLgAECn8cAAIjAAYJgwqoHADJAAAjAAYJgwqoHADJAAAAAA==.Kaelorien:BAABLgAECn89AAIfAAkJKRJoJgDyAQAfAAkJKRJoJgDyAQAAAA==.Kaetta:BAABLgAECn8XAAIJAAgJ0APiwwAEAQAJAAgJ0APiwwAEAQAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgYJDgAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAABLgAECn8fAAIFAAgJHhDtFwBfAQAFAAgJHhDtFwBfAQAAAA==.Kaldevayn:BAABLgAECn8aAAMBAAgJ8hfAAgCfAQABAAgJ8hfAAgCfAQAEAAMJ8AzOHQCLAAAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgQJBgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8uAAIcAAYJ1g/wEACxAAAcAAYJ1g/wEACxAAAAAA==.Kandandris:BAAALgAECgcJCAAAAA==.Kardanis:BAABLgAECn8uAAIQAAkJviRqAgCiAwAQAAkJviRqAgCiAwAAAA==.Kardzuni:BAAALgADCgEJAQAAAA==.Kashe:BAABLgAECn8eAAMBAAcJyRwyMACZAQABAAYJXxsyMACZAQAEAAEJOgx4PgAvAAAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Kasume:BAAALgAECgEJAQAAAA==.Katavia:BAABLgAECn8pAAIQAAkJZxKHPAC8AQAQAAkJZxKHPAC8AQAAAA==.Kaydencia:BAABLgAECn8XAAIEAAYJvxET0gDwAAAEAAYJvxET0gDwAAAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgQJBgAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Ke='Keldormu:BAAALgADCgkJCQAAAA==.Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgAECgYJCAAAAA==.Khortical:BAAALgADCgkJCQABLgAECgkJMAAiANUgAA==.',
Ki='Ki:BAAALgAECgQJBAAAAA==.Kiddow:BAABLgAECn8WAAIJAAcJ/BEFHQCOAAAJAAcJ/BEFHQCOAAAAAA==.Kierea:BAAALgAECgMJAwAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgAECgEJAQAAAA==.Kiri:BAAALgADCgkJEQAAAA==.Kitamii:BAABLgAECn8UAAIZAAYJdRbHEQCQAQAZAAYJdRbHEQCQAQAAAA==.Kivrin:BAABLgAECn8XAAIHAAgJ3wzEAwBbAQAHAAgJ3wzEAwBbAQAAAA==.',
Kr='Kringlë:BAABLgAECn8oAAIGAAkJ3SDEGACSAgAGAAkJ3SDEGACSAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kurumi:BAAALgAECgQJBAAAAA==.Kushwizard:BAAALgADCgQJBQAAAA==.Kuunko:BAAALgAECgEJAQAAAA==.',
Ky='Kymma:BAABLgAECn80AAIEAAkJIw7xFQDAAAAEAAkJIw7xFQDAAAAAAA==.Kyunix:BAAALgAECgYJBgAAAA==.',
La='Lagoriatsua:BAABLgAECn8ZAAIWAAgJlQZYUgDvAAAWAAgJlQZYUgDvAAAAAA==.Laitue:BAAALgAECgQJDAAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAABLgAECn8YAAMHAAcJ3horAgC/AQAHAAcJ3horAgC/AQAIAAUJtxE9BgAdAQAAAA==.Lazengann:BAABLgAECn8mAAMcAAkJnRanOwDZAQAcAAkJERWnOwDZAQAOAAIJ/BnGXABUAAAAAA==.',
Le='Leafbane:BAAALgAECgMJAwAAAA==.Leagann:BAAALgAECgEJAQAAAA==.Legevia:BAABLgAECn8eAAMiAAgJsgUzJADVAAAiAAgJsgUzJADVAAAQAAIJkgKWzwA8AAAAAA==.Leiris:BAABLgAECn88AAIEAAkJDRFrWgC+AQAEAAkJDRFrWgC+AQAAAA==.Leisha:BAAALgADCgEJAQAAAA==.Letifer:BAAALgADCgkJDAAAAA==.Leucetios:BAAALgAECgQJCgAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8iAAIMAAkJRxmTDgB/AgAMAAkJRxmTDgB/AgAAAA==.Lightbeard:BAABLgAECn8pAAQBAAcJHRxYHgAQAgABAAcJHRxYHgAQAgAEAAIJ+wUDbwFJAAAFAAEJ4A/gUwApAAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAABLgAECn8WAAIEAAgJ7RgPbQCUAQAEAAgJ7RgPbQCUAQAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgAECgQJBgAAAA==.Liubing:BAAALgADCgIJAgABLgADCgYJGwAPAAAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lochli:BAAALgAECgUJCgAAAA==.Lorredain:BAAALgAECgQJCQAAAA==.Lothaire:BAAALgADCgEJAQABLgADCgIJAgAPAAAAAA==.Lothwen:BAAALgAECgYJDgAAAA==.Louisachan:BAAALgADCgUJBQABLgAFFAEJAgAPAAAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8cAAIMAAUJqxCzFAAeAQAMAAUJqxCzFAAeAQAuAAQKfzcAAgwACQmPFrUXABACAAwACQmPFrUXABACAAAA.Luxinine:BAABLgAECn8qAAMHAAkJPCB6BgDqAgAHAAkJPCB6BgDqAgAIAAIJsxSCDACCAAAAAA==.',
Ly='Lyon:BAAALgADCgMJCgAAAA==.Lyshai:BAAALgAECgYJBgABLgAECgkJIgAkAGohAA==.',
Ma='Madhawi:BAABLgAECn81AAMIAAcJnCQ9AQBfAgAIAAcJnCQ9AQBfAgAMAAIJOhSGawB9AAAAAA==.Magamon:BAABLgAECn8wAAIJAAkJBxhkOgAwAgAJAAkJBxhkOgAwAgAAAA==.Magamus:BAAALgADCgYJBgAAAA==.Mahndarb:BAAALgAECgYJEAABLgAECggJJQAMAE8dAA==.Majima:BAAALgAECgYJDgAAAA==.Makedeader:BAAALgAECgkJBgAAAA==.Malfuriia:BAABLgAECn8oAAIQAAkJ+xeuLAAGAgAQAAkJ+xeuLAAGAgAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Mamboke:BAAALgAECgcJDwAAAA==.Margerdria:BAABLgAECn8XAAIHAAYJ3w+2DQBxAAAHAAYJ3w+2DQBxAAAAAA==.Maskelle:BAABLgAECn8tAAITAAkJvBGTDgBnAQATAAkJvBGTDgBnAQAAAA==.Mauugrim:BAABLgAECn8pAAIVAAkJ+giOFAC2AAAVAAkJ+giOFAC2AAAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAABLgAECn8gAAIEAAkJNhZzEQDoAAAEAAkJNhZzEQDoAAAAAA==.',
Me='Mearadan:BAAALgAECgkJDwAAAA==.Meatsweats:BAABLgAECn8lAAIEAAgJEQvjrAAkAQAEAAgJEQvjrAAkAQAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDwAAAA==.Mekh:BAABLgAECn8iAAMkAAkJaiGmAACVAQAkAAkJaiGmAACVAQAlAAMJOhMmKwCTAAAAAA==.Mel:BAAALgAECgMJDQAAAA==.Melanara:BAABLgAECn9LAAIJAAkJUg/nBwB5AQAJAAkJUg/nBwB5AQAAAA==.Melstrom:BAAALgAECggJEAAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgYJBwAAAA==.Meticuluslyn:BAAALgAECgYJEgAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAABLgAECn8WAAIhAAkJ0RO9AwDVAQAhAAkJ0RO9AwDVAQAAAA==.Miyävii:BAABLgAECn8YAAIFAAkJxxNGFwBmAQAFAAkJxxNGFwBmAQAAAA==.',
Mj='Mjsage:BAABLgAECn8kAAIGAAkJGR6yJABQAgAGAAkJGR6yJABQAgAAAA==.',
Mm='Mmeow:BAAALgAECgQJBQABLgAECgkJFQAGAMkZAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8jAAIHAAkJvhpkBABAAQAHAAkJvhpkBABAAQAAAA==.Mooasha:BAAALgAECgEJAQABLgAECgkJKQAQAGcSAA==.Moonflowers:BAACLgAFFH8fAAINAAgJ/BkJCAB9AgANAAgJ/BkJCAB9AgAuAAQKfy8AAg0ACAmcJM4HAA8DAA0ACAmcJM4HAA8DAAAA.Mordsevoker:BAAALgAFFAIJAgABLgAFFAUJFwAVAFwSAA==.Morginoth:BAAALgADCgcJBwAAAA==.Morregu:BAAALgAECgQJBQAAAA==.Mousekee:BAABLgAECn8qAAIMAAkJkg2UJwCJAQAMAAkJkg2UJwCJAQAAAA==.',
Mu='Muku:BAAALgADCgkJCQABLgAECgkJTQAJAJURAA==.Murdrmitts:BAABLgAECn8qAAIZAAkJ1w7UAQBpAQAZAAkJ1w7UAQBpAQAAAA==.Muross:BAAALgAECgEJAQAAAA==.Mustikka:BAABLgAECn8eAAIZAAcJThOEBADCAAAZAAcJThOEBADCAAAAAA==.',
My='Mystikah:BAAALgAECgEJAQAAAA==.Myuriyanka:BAABLgAECn8pAAMWAAkJoBOGJADDAQAWAAkJoBOGJADDAQAQAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgYJBwAPAAAAAA==.',
Na='Naahommii:BAABLgAECn8hAAIGAAkJxRRLQgDbAQAGAAkJxRRLQgDbAQAAAA==.Nachtpranke:BAABLgAECn8ZAAINAAgJ9B4rGACFAgANAAgJ9B4rGACFAgAAAA==.Nadron:BAAALgAECgYJDAAAAA==.Naevala:BAAALgAECgkJCgAAAA==.Nagualli:BAAALgAECgQJBQAAAA==.Navira:BAAALgADCgYJBQAAAA==.',
Ne='Negargra:BAABLgAECn8wAAMUAAYJUxQNCAAlAQAUAAYJUxQNCAAlAQAmAAEJcgMufAAkAAAAAA==.Nekwid:BAAALgADCgIJAgAAAA==.Nephadin:BAABLgAECn8dAAMEAAgJpAr7uQARAQAEAAgJpAr7uQARAQABAAUJnAbNWQDPAAAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgYJDgAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nightrunner:BAAALgADCgYJBQAAAA==.Nighttiger:BAABLgAECn8eAAINAAcJxw+cCAC+AAANAAcJxw+cCAC+AAAAAA==.Nikooli:BAABLgAECn8mAAMOAAkJOReyAwBIAQAOAAkJOReyAwBIAQATAAEJ+AYlPQAaAAAAAA==.Nimb:BAAALgAECgEJBAAAAA==.',
No='Nokkoh:BAAALgADCgQJBwAAAA==.Nolime:BAAALgAECgYJBwAAAA==.Noodledragon:BAAALgAECgYJBwAAAA==.Noopsie:BAABLgAECn8zAAINAAgJlg6ZBwDXAAANAAgJlg6ZBwDXAAAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAgJKQAlADQQAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMIAAgJxhqHFwAZAgAIAAcJLhyHFwAZAgAHAAcJsBxlLAByAQAAAA==.Notpeepuddle:BAAALgAECgEJAQAAAA==.Novarox:BAAALgAECgEJAQAAAA==.',
Nu='Nuhnoo:BAAALgADCgkJCQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8rAAIEAAkJshrBCwAvAQAEAAkJshrBCwAvAQAAAA==.Nyxalia:BAAALgAECgYJCAAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMhAAkJbgM/EgCgAAAJAAkJWQMu4ADaAAAhAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBQAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCggJDwAAAA==.Olympia:BAABLgAECn8uAAIFAAkJ0A1WHQAqAQAFAAkJ0A1WHQAqAQAAAA==.',
Or='Oraclemega:BAABLgAECn80AAIJAAkJBSA5EAD6AgAJAAkJBSA5EAD6AgAAAA==.Orweyna:BAAALgAECggJDwAAAA==.',
Os='Oscarmikey:BAACLgAFFH8eAAMNAAUJew3rCwAEAQANAAUJew3rCwAEAQAdAAIJXgIIIwAuAAAuAAQKfz8ABQ0ACQlgHoAQAM0CAA0ACQlgHoAQAM0CAB0ABglhFbA3ADYBABkAAQlMAr1hACAAACAAAQkAAOuUAAAAAAAA.Oshu:BAAALgAECgYJBgAAAA==.',
Ot='Ottoshot:BAABLgAECn8mAAIGAAkJ9xPDDwAGAQAGAAkJ9xPDDwAGAQAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
Ow='Owlaf:BAAALgAECgEJAQAAAA==.',
['Oö']='Oöps:BAABLgAECn8UAAINAAkJ6wUrcQDhAAANAAkJ6wUrcQDhAAAAAA==.',
Pa='Paksen:BAAALgAECgEJAQAAAA==.Panamone:BAABLgAECn8mAAMZAAkJnSRQAQCoAQAZAAkJnSRQAQCoAQANAAIJBRZfmACBAAAAAA==.Pandeism:BAABLgAECn80AAMiAAkJZxTZDgDDAQAiAAgJHxTZDgDDAQAQAAcJoBfeCgD5AAAAAA==.Papagrip:BAABLgAECn8wAAMSAAkJ7xJZDACyAQASAAkJ7xJZDACyAQAVAAgJBQr6pgAhAQAAAA==.Patrin:BAABLgAECn8gAAIJAAgJZw3ggwBwAQAJAAgJZw3ggwBwAQAAAA==.Paulee:BAAALgADCgkJDgAAAA==.',
Pe='Peanutbritle:BAABLgAECn8qAAIRAAkJaAZrLgDrAAARAAkJaAZrLgDrAAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.',
Ph='Phantdoom:BAAALgAECgYJEQAAAA==.Phean:BAAALgAECgEJAQAAAA==.Phylah:BAAALgAECgMJBAAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAECggJKQAEAA8lAA==.',
Pl='Plsdiddyno:BAAALgAFFAEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgQJBwAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Puchi:BAAALgAECgUJBQAAAA==.Punchabaal:BAAALgAECgcJDAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAINAAcJWRnvMwDZAQANAAcJWRnvMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgQJBAAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Redrollin:BAAALgAECgIJAgAAAA==.Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAYJMQAhAGklAA==.Reyrocko:BAAALgAFFAEJAQAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAQJDQAHABsdAA==.Rezdk:BAAALgAECggJCAABLgAFFAQJDQAHABsdAA==.Rezhunt:BAABLgAFFH8FAAMjAAQJJxn/GQDjAAAjAAMJrhj/GQDjAAAbAAEJkhr2LwBUAAABLgAFFAQJDQAHABsdAA==.Rezmonk:BAAALgAECgcJCgABLgAFFAQJDQAHABsdAA==.Rezshift:BAABLgAECn8bAAMdAAgJwhzjFQAgAgAdAAgJwhzjFQAgAgANAAQJBRbtbwAFAQABLgAFFAQJDQAHABsdAA==.Rezvoid:BAACLgAFFH8NAAMHAAQJGx0AFQA9AQAHAAQJGx0AFQA9AQAMAAIJgyHwIgCjAAAuAAQKfzQAAwcACQkQI84GAOUCAAcACQkQI84GAOUCAAwAAgmjIPFJAL0AAAAA.',
Rh='Rhage:BAAALgAECgMJCgAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAABLgAECn8XAAIVAAcJlRKnngAuAQAVAAcJlRKnngAuAQAAAA==.Roxane:BAABLgAECn8lAAIdAAkJxQmQMABbAQAdAAkJxQmQMABbAQAAAA==.',
Ru='Runningelk:BAABLgAECn8xAAIgAAkJvBLbFQClAQAgAAkJvBLbFQClAQAAAA==.Runscapemain:BAABLgAECn8sAAMEAAkJQBjwVADLAQAEAAkJQBjwVADLAQAFAAYJ/RAUIwD8AAAAAA==.',
Ry='Ryeti:BAAALgADCgkJFwAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDgAOAAEkAA==.',
Sa='Saintulrick:BAAALgAECgIJAwAAAA==.Sajuice:BAACLgAFFH8HAAIjAAUJPwW5GwDSAAAjAAUJPwW5GwDSAAAuAAQKfyYAAiMACAnAGyIKAM8BACMACAnAGyIKAM8BAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn8mAAMMAAkJmg7UKwBrAQAMAAkJmg7UKwBrAQAHAAEJmAMQlwAjAAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAPAAAAAA==.',
Se='Seeyen:BAACLgAFFH8ZAAIGAAYJ9hW8MwBGAQAGAAYJ9hW8MwBGAQAuAAQKfywAAgYACQnSHgUHAB8DAAYACQnSHgUHAB8DAAAA.Selendriel:BAAALgADCgcJBwAAAA==.Selfdestruct:BAABLgAECn8UAAIEAAgJCQvSDgAEAQAEAAgJCQvSDgAEAQAAAA==.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8lAAIkAAkJgwrgCgBsAQAkAAkJgwrgCgBsAQAAAA==.Seren:BAAALgAFFAEJAwABLgAFFAcJGAAJAMALAA==.Serenityhate:BAABLgAECn8jAAMMAAYJVQ3RPQD7AAAMAAYJVQ3RPQD7AAAHAAEJAABzoAAAAAAAAA==.',
Sh='Shaaydo:BAAALgAECgEJBAAAAA==.Shaaytheyha:BAAALgAECgMJAwAAAA==.Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgYJCAAAAA==.Shandrilyn:BAABLgAECn8YAAIHAAcJIARnUQDMAAAHAAcJIARnUQDMAAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAIlAAkJwBQgGABQAQAlAAkJwBQgGABQAQAAAA==.Shiziuno:BAAALgAECgQJCAAAAA==.',
Si='Sini:BAAALgAFFAcJBAAAAA==.Sinthoras:BAAALgAECgQJBAAAAA==.Sionarra:BAAALgADCgIJAgAAAA==.',
Sj='Sjðfn:BAAALgAECgkJAgAAAA==.',
Sk='Skala:BAABLgAECn8YAAInAAkJThZnHADyAQAnAAkJThZnHADyAQAAAA==.Skibbie:BAACLgAFFH8eAAMnAAcJbgwBHgBwAQAnAAcJbgwBHgBwAQAkAAQJOwoCBgD9AAAuAAQKfx4ABCcACQk4GF8QAHMCACcACQk4GF8QAHMCACUABAmHDpImALgAACQABQnOBpAsALcAAAAA.Skibbward:BAABLgAECn8zAAQgAAgJTiS4AQAyAwAgAAgJTiS4AQAyAwAdAAUJxQ9jVADUAAANAAYJ6QrsggDSAAABLgAFFAcJHgAnAG4MAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAABLgAECn8XAAIQAAgJRR4vFACqAgAQAAgJRR4vFACqAgAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Slickdeath:BAAALgAECgEJAgAAAA==.Sliyce:BAAALgAECgEJBgABLgAECgIJBwAPAAAAAA==.',
Sm='Smackdogg:BAACLgAFFH8IAAIdAAUJKBxOFwBgAQAdAAUJKBxOFwBgAQAuAAQKfxkAAh0ABwk9HRcdABgCAB0ABwk9HRcdABgCAAEuAAUUCAkwABYAnyAA.',
So='Solteria:BAABLgAECn8VAAIKAAcJqAk/DgBOAQAKAAcJqAk/DgBOAQABLgAECgkJAgAPAAAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAABLgAECn8ZAAIOAAcJxxDFKAA2AQAOAAcJxxDFKAA2AQAAAA==.Sorvina:BAABLgAECn84AAIUAAkJdBKsQADaAQAUAAkJdBKsQADaAQAAAA==.Soulflame:BAABLgAECn9NAAIJAAkJlRFnCwA4AQAJAAkJlRFnCwA4AQAAAA==.Soulshifter:BAABLgAECn8YAAIdAAcJswqlRQD2AAAdAAcJswqlRQD2AAAAAA==.Soultrader:BAAALgADCgkJFwABLgAECgcJIAAFAKsTAA==.',
Sp='Spacetime:BAAALgAECgEJAQAAAA==.Spooñ:BAAALgADCgcJBwABLgAFFAUJFgAfAEocAA==.Spottedcoat:BAABLgAECn8qAAINAAkJhANnfADDAAANAAkJhANnfADDAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgABLgAECgkJGQAVAEUZAA==.Stasia:BAAALgADCgkJCQAAAA==.Strangerx:BAAALgAECgEJAgAAAA==.Stregnor:BAABLgAECn88AAIGAAkJBBh5JQBMAgAGAAkJBBh5JQBMAgAAAA==.Styggi:BAAALgAECgMJBQAAAA==.Styggian:BAAALgAECggJCgAAAA==.Stygy:BAAALgAECgMJBAAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDgAOAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn9DAAMeAAgJehi0GQDjAQAeAAgJehi0GQDjAQAaAAUJsQ7PUQC8AAAAAA==.',
Sv='Svéria:BAAALgADCgMJAwAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMnAAkJDxKrEwBHAgAnAAkJfhGrEwBHAgAkAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgkJJgAnAB4bAA==.Tachie:BAABLgAECn8mAAMnAAkJHhtEDwByAgAnAAkJuBpEDwByAgAkAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAcJHwAKAE4lAA==.Taele:BAABLgAECn8tAAMJAAkJTxzKJwB7AgAJAAkJtBvKJwB7AgAhAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn9OAAIdAAkJXxXaAQDgAQAdAAkJXxXaAQDgAQAAAA==.Tamalpais:BAABLgAECn8dAAIGAAUJZhG7GQCpAAAGAAUJZhG7GQCpAAAAAA==.Tamarind:BAAALgAECgYJBgABLgAECgkJMAAiANUgAA==.Tamzred:BAAALgAECgYJBgABLgAECgkJKQAEAM8VAA==.Tanyab:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8oAAIGAAkJQAX7GwCZAAAGAAkJQAX7GwCZAAAAAA==.',
Th='Thaesan:BAAALgAECgYJDwAAAA==.Therin:BAABLgAECn8wAAIbAAkJHRWEEwAKAgAbAAkJHRWEEwAKAgAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tillymonick:BAAALgAECgUJCAAAAA==.Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgcJGQAAAA==.Toofast:BAABLgAECn9FAAIQAAkJDSKzCgALAwAQAAkJDSKzCgALAwAAAA==.Toofurrious:BAAALgADCgkJQAAAAA==.Topswimmer:BAACLgAFFH8KAAIJAAIJthJdOgCaAAAJAAIJthJdOgCaAAAuAAQKfxkAAgkABwlSFsxsAKEBAAkABwlSFsxsAKEBAAAA.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgUJBgAAAA==.',
Tr='Traci:BAABLgAECn8fAAIgAAgJyxUBGACRAQAgAAgJyhUBGACRAQAAAA==.Trifus:BAABLgAECn8pAAMRAAkJ6hg4GACiAQARAAgJlRc4GACiAQAVAAcJ0w84ZACfAQAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAABLgAECn8hAAINAAYJHR5TKgADAgANAAYJHR5TKgADAgAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQABLgAECgQJBgAPAAAAAA==.',
Tu='Tulao:BAABLgAECn80AAIJAAgJGyBhMgBPAgAJAAgJGyBhMgBPAgAAAA==.',
Tw='Twan:BAAALgAFFAEJAgABLgAFFAgJFQAcAAUVAA==.',
Ty='Tyledoriel:BAAALgADCgEJAQAAAA==.Tyrionel:BAAALgAECgUJCgAAAA==.',
Tz='Tzitzimitl:BAAALgAECgYJBwAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIfAAQJaRDxNADXAAAfAAQJaRDxNADXAAAAAA==.',
Ut='Utheli:BAACLgAFFH8UAAIEAAUJqRMfQwAlAQAEAAUJqRMfQwAlAQAuAAQKfx8AAgQACAkBG95MAOABAAQACAkBG95MAOABAAAA.',
Va='Vaevictis:BAABLgAECn8VAAISAAgJbRupAABTAgASAAgJbRupAABTAgAAAA==.Vaildora:BAAALgAECgEJAQABLgAECgkJJgAnAB4bAA==.Valdra:BAABLgAECn89AAIDAAkJGRPtEgC9AQADAAkJGRPtEgC9AQAAAA==.Valkyl:BAAALgAECgEJAQAAAA==.Valkylpriest:BAAALgAECgEJAgAAAA==.',
Vi='Vidiablade:BAAALgAFFAIJAgAAAA==.Viralprepped:BAAALgAECgMJDQAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8hAAMcAAkJbxFWUACVAQAcAAkJbxFWUACVAQAOAAYJEg7zNADrAAAAAA==.',
Vn='Vnasty:BAACLgAFFH8QAAIEAAYJ+gwIUgALAQAEAAYJ+gwIUgALAQAuAAQKfywAAgQACQkrICkKAD8DAAQACQkrICkKAD8DAAAA.',
Vo='Vogue:BAAALgADCgcJBQAAAA==.',
Vr='Vrale:BAAALgAFFAIJAgAAAA==.',
['Vì']='Vì:BAAALgAECgMJAwABLgAFFAYJEAAEAPoMAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Wes:BAAALgAECgEJAQAAAA==.Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wildbear:BAAALgAECgYJBgAAAA==.Wilken:BAABLgAECn84AAIoAAkJ0BviCABjAgAoAAkJ0BviCABjAgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8pAAIEAAkJ/xp6MQA6AgAEAAkJ/xp6MQA6AgAAAA==.',
Ws='Wspr:BAAALgAECgIJBgAAAA==.',
Wu='Wulff:BAAALgADCgMJBgAAAA==.',
Xa='Xaartahli:BAAALgAECgUJEAAAAA==.Xavencia:BAABLgAECn8XAAIJAAkJjQamDAAlAQAJAAkJjQamDAAlAQAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xe='Xenolithia:BAAALgAECgQJBQAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECggJCwAAAA==.',
Ya='Yanut:BAABLgAECn8UAAIEAAYJqQdC7ADPAAAEAAYJqQdC7ADPAAAAAA==.',
Ye='Yeetjin:BAAALgAECggJCwAAAA==.',
Yi='Yinamin:BAABLgAECn8UAAIHAAYJlQtjTQDaAAAHAAYJlQtjTQDaAAAAAA==.',
Yk='Yknub:BAAALgAECgQJBAAAAA==.',
Yo='Yotin:BAAALgAECgYJBgAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAABLgAECn8jAAINAAkJZhT5JQAeAgANAAkJZhT5JQAeAgAAAA==.Zalanto:BAAALgAECgEJAgAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn9VAAIGAAkJ4xQaBQDWAQAGAAkJ4xQaBQDWAQAAAA==.',
Ze='Zedraikis:BAAALgAECgEJAQAAAA==.Zelgaddis:BAABLgAECn8sAAMQAAkJ6xPABACjAQAQAAkJ6xPABACjAQAiAAIJTQSwQQAsAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn8vAAInAAcJjxKvBAAJAQAnAAcJjxKvBAAJAQAAAA==.',
Zr='Zrathan:BAEALgAECgEJAQABLgAECgIJAgAPAAAAAA==.Zriana:BAAALgAECgQJCAAAAA==.',
Zs='Zsarilya:BAABLgAECn8tAAIMAAkJWAKBRQDSAAAMAAkJWAKBRQDSAAAAAA==.',
Zu='Zurgen:BAABLgAECn89AAIUAAkJiyDrDADmAgAUAAkJiyDrDADmAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8yAAINAAgJghUaKQAKAgANAAgJghUaKQAKAgABLgAFFAUJHAAMAKsQAA==.',
['Ýu']='Ýui:BAAALgADCgQJBAAAAA==.',
['ßo']='ßooßear:BAAALgAECgMJAwAAAA==.',
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
