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

local lookup = {'Paladin-Holy','Warrior-Protection','Warrior-Fury','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','Mage-Frost','Warlock-Affliction','Mage-Fire','Priest-Holy','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Vengeance','Warlock-Demonology','DeathKnight-Unholy','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Brewmaster','Hunter-Survival','DemonHunter-Devourer','Druid-Balance','Monk-Windwalker','Warrior-Arms','Monk-Mistweaver','Druid-Guardian','Mage-Arcane','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Evoker-Augmentation',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aarchon:BAABLgAECn8qAAIBAAkJhB+ZCQDyAgABAAkJhB+ZCQDyAgAAAA==.',
Ad='Aduin:BAABLgAECn8lAAMCAAkJBBfmAwBGAQADAAkJbw6jNgBtAQACAAUJux3mAwBGAQAAAA==.',
Ae='Aedarelyn:BAABLgAECn8bAAMEAAcJ8BDVGADiAAAEAAcJ8BDVGADiAAAFAAEJGAa1XAAWAAAAAA==.Aellita:BAABLgAECn8VAAIGAAYJZwhFqgDuAAAGAAYJZwhFqgDuAAAAAA==.Aeschylus:BAABLgAECn8WAAIEAAkJYg8CFgD5AAAEAAkJYg8CFgD5AAAAAA==.',
Af='Afkinlife:BAAALgADCgIJAgAAAA==.',
Ak='Akky:BAABLgAECn8tAAICAAkJKiH/BgCXAgACAAkJKiH/BgCXAgAAAA==.Aksafiya:BAABLgAECn9fAAMHAAkJhxRKGgDzAQAHAAkJhxRKGgDzAQAIAAEJWAINiwAcAAAAAA==.',
Al='Alal:BAABLgAECn8mAAIJAAgJDBLBDQBQAQAJAAgJDBLBDQBQAQAAAA==.Alandras:BAABLgAECn8tAAIDAAkJAAnkQQA9AQADAAkJAAnkQQA9AQAAAA==.Alaras:BAACLgAFFH8gAAIHAAgJRA7iBQCOAQAHAAgJRA7iBQCOAQAuAAQKfxcAAgcACQnQFQ8aAA8CAAcACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8rAAIKAAkJcxexBwDzAQAKAAkJcxexBwDzAQAAAA==.Allrianne:BAAALgAECgQJEAAAAA==.Allyriae:BAABLgAECn8WAAILAAgJDgkgCQD0AAALAAgJDgkgCQD0AAAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8lAAIMAAgJTx1gDwBzAgAMAAgJTx1gDwBzAgAAAA==.',
Am='Ambilena:BAABLgAECn8vAAMMAAkJhRVMLQBiAQAMAAYJVhhMLQBiAQAHAAkJeBDHBwAgAQAAAA==.',
An='Andoros:BAABLgAECn86AAINAAkJax6bEADMAgANAAkJax6bEADMAgAAAA==.Angiliana:BAABLgAECn8UAAIOAAUJAw8sPQDCAAAOAAUJAw8sPQDCAAAAAA==.Angvall:BAAALgAECgYJCAABLgAFFAMJBAAPAAAAAA==.Animainiac:BAAALgAECgYJBgABLgAECgkJKQAQAGcSAA==.Anzurath:BAABLgAECn8pAAIEAAkJzxVqTgDcAQAEAAkJzxVqTgDcAQAAAA==.',
Ap='Apheron:BAAALgAECgEJAQABLgAECgkJMAARANUgAA==.Applebow:BAABLgAECn8uAAISAAkJ/hEpBgAHAQASAAkJ/hEpBgAHAQAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgAECgkJEwAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECggJEQAAAA==.Armas:BAAALgAECggJCAAAAA==.Arylin:BAABLgAECn82AAIJAAkJlSMiCgApAwAJAAkJlSMiCgApAwAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEBLgAECn8eAAMCAAcJ+BSlBwCwAAACAAcJShSlBwCwAAADAAIJHhEsIwAxAAAAAA==.Asiain:BAAALgADCgEJAQABLgAFFAkJJgADADEaAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQAPAAAAAA==.Asky:BAAALgADCgYJCQABLgAECgkJKQAJAHEDAA==.Asmodean:BAAALgAECgEJAQAAAA==.Asnabel:BAABLgAECn83AAITAAkJtRHfAQCrAQATAAkJtRHfAQCrAQAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astrai:BAAALgADCgcJBwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCgASAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgAECgYJEgAAAA==.Ayden:BAABLgAECn8iAAMUAAgJlxpWAgBAAQAOAAgJUhmBGAC/AQAUAAQJ+BtWAgBAAQAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwAPAAAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.Benkei:BAAALgAECgQJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgMJBQAAAA==.',
Bl='Blee:BAABLgAECn8+AAMIAAkJNBDLBQB3AQAIAAkJNBDLBQB3AQAHAAQJlgWRSgCwAAAAAA==.Bloodbourne:BAAALgAECgEJAQAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.Bluudclaaw:BAAALgAECgYJBwAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8lAAIVAAcJVh6rOAD3AQAVAAcJVh6rOAD3AQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8uAAIGAAkJxiHrHwBoAgAGAAkJxiHrHwBoAgAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8fAAIWAAkJuhAjdgB3AQAWAAkJuhAjdgB3AQAAAA==.Brood:BAABLgAECn8rAAIWAAkJyBRRUQDPAQAWAAkJyBRRUQDPAQAAAA==.Brundles:BAAALgAECgYJBgAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAABLgAECn9JAAMXAAkJagoFBwA0AQAXAAkJagoFBwA0AQAQAAUJFgjEkAC3AAAAAA==.',
Ca='Cailaranel:BAABLgAECn8wAAMYAAkJigkUJAB0AQAYAAkJPggUJAB0AQAZAAcJaQlUEAAfAQAAAA==.Calaul:BAABLgAECn80AAMEAAkJ6hRIDwA8AQAEAAkJ6hRIDwA8AQAFAAUJnAZ5CwBuAAAAAA==.Calenbraga:BAABLgAECn9UAAIaAAkJbx7HAABnAgAaAAkJbx7HAABnAgAAAA==.Calisim:BAABLgAECn8hAAIVAAYJMwcZwADLAAAVAAYJMwcZwADLAAAAAA==.Callidae:BAABLgAECn8qAAIMAAkJBxEwHADlAQAMAAkJBxEwHADlAQAAAA==.Calmnbald:BAABLgAECn8ZAAIbAAcJeBfGPAAIAQAbAAcJeBfGPAAIAQAAAA==.Caloh:BAAALgAECgcJCwAAAA==.Cantallbis:BAAALgADCgcJBwAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8lAAIcAAkJlgwuHQCzAQAcAAkJlgwuHQCzAQAAAA==.Cataryn:BAABLgAECn8mAAIGAAkJNSRwDwDVAgAGAAkJNSRwDwDVAgAAAA==.Catt:BAABLgAECn9LAAIBAAkJGBkDFABvAgABAAkJGBkDFABvAgAAAA==.',
Ce='Cellebur:BAABLgAECn8nAAIGAAgJ5AfAJQCaAAAGAAgJ5AfAJQCaAAAAAA==.Ceta:BAABLgAECn87AAIMAAkJDhyuDQCLAgAMAAkJDhyuDQCLAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAACLgAFFH8HAAMXAAMJWQvHTABjAAAXAAIJ7QTHTABjAAAQAAIJ3QIYeQBMAAAuAAQKfysAAxAACAncEfA9ALYBABAACAncEfA9ALYBABcABwm2GRMuAIoBAAAA.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn9SAAIJAAkJlgugDgBFAQAJAAkJlgugDgBFAQAAAA==.Cinderelah:BAAALgAECgEJAQAAAA==.Cizean:BAABLgAECn8pAAIJAAkJcQPVKwBxAAAJAAkJcQPVKwBxAAAAAA==.',
Cr='Craivan:BAAALgAECgYJEAAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crill:BAAALgAECgYJBwAAAA==.Crilly:BAABLgAECn8rAAIJAAkJZRj5OgAtAgAJAAkJZRj5OgAtAgAAAA==.Crowe:BAAALgAECgUJCgABLgAECgUJBQAPAAAAAA==.Crowley:BAAALgADCgMJAwAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAABLgAECn8bAAIQAAkJ0gzrFAC0AAAQAAkJ0gzrFAC0AAAAAA==.Cyrr:BAAALgAECggJDwAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJDAAAAA==.Damia:BAABLgAECn8tAAMYAAkJPBjpFgDlAQAYAAkJPBjpFgDlAQAZAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgADCgcJFgAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8mAAISAAkJ8CQHBAD5AgASAAkJ8CQHBAD5AgAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgIJBQABLgAECgkJJgASAPAkAA==.Delvarrieth:BAABLgAECn8pAAIFAAkJvQ3dHgAdAQAFAAkJvQ3dHgAdAQAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Demonzar:BAAALgAECgYJCgAAAA==.Demzy:BAAALgAECgYJBwAAAA==.Denth:BAABLgAECn8gAAIEAAkJsQ4EbgCSAQAEAAkJsQ4EbgCSAQAAAA==.Dercuur:BAACLgAFFH8FAAIXAAMJKhjXEwDhAAAXAAMJKhjXEwDhAAAuAAQKfx0AAhcACAlVF84kAMEBABcACAlVF84kAMEBAAAA.Devoursol:BAABLgAECn85AAMdAAkJlQz+WAB8AQAdAAkJaAz+WAB8AQAOAAIJrg45XABvAAAAAA==.',
Di='Dipndots:BAAALgAECgYJBwABLgAECgkJJgASAPAkAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Doist:BAAALgAECgIJAgAAAA==.Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgAECgcJDgAAAA==.Drainmee:BAABLgAECn8nAAMIAAcJdxRzMABcAQAIAAcJdxRzMABcAQAHAAUJagSxZQCFAAAAAA==.Draknol:BAAALgAECgEJAQAAAA==.Dreadspark:BAABLgAECn8cAAMVAAkJ8xyaHgBtAgAVAAkJTRyaHgBtAgAKAAQJdx0aGAC6AAAAAA==.Dregoth:BAABLgAECn8tAAIWAAkJdAlmDgAlAQAWAAkJdAlmDgAlAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8hAAMNAAkJ4R5kEAC0AgANAAkJ4R5kEAC0AgAeAAEJxgkemgAnAAAAAA==.',
Ea='Eathur:BAAALgAECgYJBgAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
Ed='Edeveren:BAAALgAECgUJBQAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elunariel:BAAALgAECgEJAgABLgAECgkJHAAVAPMcAA==.Elynth:BAABLgAECn8nAAIVAAkJcxx2IgBYAgAVAAkJcxx2IgBYAgAAAA==.',
En='Endlessyueh:BAABLgAECn8lAAMEAAcJxA8hyAD9AAAEAAYJCxAhyAD9AAABAAcJFwfyDACVAAAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgkJHAAVAPMcAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAFFAQJBAABLgAFFAYJEAAEAPoMAA==.',
Ex='Excelsior:BAAALgAECgcJBAAAAA==.',
Fa='Faethian:BAACLgAFFH8UAAIFAAUJSiFwAwBxAQAFAAUJSiFwAwBxAQAuAAQKfywAAgUACAk7JacDANUCAAUACAk7JacDANUCAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8xAAIJAAkJ6wnDiwBgAQAJAAkJ6wnDiwBgAQAAAA==.Fangren:BAABLgAECn8nAAIGAAYJtxLJHwC9AAAGAAYJtxLJHwC9AAAAAA==.Fariah:BAAALgAECgUJEwAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAABLgAECn8YAAIfAAcJ6QeSRwDhAAAfAAcJ6QeSRwDhAAAAAA==.',
Fe='Felicja:BAAALgAFFAEJAgABLgAFFAgJKQAgALgYAA==.Felscythe:BAABLgAECn8oAAIbAAkJnwFbCQB4AAAbAAkJnwFbCQB4AAAAAA==.Felynn:BAABLgAECn8sAAIBAAkJgxj9FQBcAgABAAkJgxj9FQBcAgAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feresdenn:BAAALgADCgQJBAAAAA==.Feyrha:BAAALgADCgYJBgABLgAECgkJOgAGAE4RAA==.',
Fi='Fiadh:BAAALgAECgQJBgAAAA==.Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8jAAIhAAkJXR0OHwAhAgAhAAkJXR0OHwAhAgAAAA==.',
Fl='Flaeli:BAABLgAECn8rAAIJAAkJzhnmDwA3AQAJAAkJzhnmDwA3AQAAAA==.Flameshot:BAAALgADCgkJCQABLgAECgkJLwAiAHUQAA==.Flemish:BAABLgAECn8YAAIXAAgJLxXrKwCWAQAXAAgJLxXrKwCWAQAAAA==.Flextame:BAAALgAECgQJEQAAAA==.Flipalicious:BAABLgAECn9AAAMQAAkJehyQEQDCAgAQAAkJehyQEQDCAgAXAAIJSxRingA9AAAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8dAAIHAAcJaBcAKgCBAQAHAAcJaBcAKgCBAQABLgAECggJGgATAH0cAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Fu='Furriousyueh:BAAALgAECgQJCAAAAA==.',
['Fë']='Fënrír:BAAALgAECgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn86AAIGAAkJThFcDAB3AQAGAAkJThFcDAB3AQAAAA==.Gallimaufrey:BAAALgAECgEJAQAAAA==.Gangstafred:BAAALgADCgYJBgAAAA==.Ganzar:BAAALgAECgEJAQAAAA==.Gazo:BAABLgAECn8YAAMHAAcJRBnGHgDPAQAHAAcJRBnGHgDPAQAIAAEJqxFpGwA9AAABLgAECgkJMAAfAJoiAA==.',
Ge='Gemboss:BAABLgAECn9OAAMEAAkJHSIvDgD0AgAEAAkJHSIvDgD0AgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8uAAMJAAkJmxO4XwDBAQAJAAkJmxO4XwDBAQAjAAMJoAbAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8yAAIfAAkJsAstLQBYAQAfAAkJsAstLQBYAQAAAA==.Ginodh:BAABLgAECn8OAAIdAAgJtQ1eewApAQAdAAgJtQ1eewApAQABLgAECgkJGQASAPwNAA==.Ginomage:BAAALgAECgcJCgABLgAECgkJGQASAPwNAA==.Ginomonk:BAAALgAECgYJBgABLgAECgkJGQASAPwNAA==.Ginopally:BAAALgAECgYJCwABLgAECgkJGQASAPwNAA==.Girth:BAAALgAECgUJCgAAAA==.Gizelli:BAAALgAFFAEJAgAAAA==.',
Gl='Glorby:BAAALgAECgQJBAABLgAFFAIJBQAhAGMXAA==.',
Go='Gordonnpr:BAAALgAECgYJDQAAAA==.',
Gr='Groblock:BAAALgADCgYJEgAAAA==.Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAhAGMXAA==.Grubetsella:BAACLgAFFH8FAAIhAAIJYxduDwClAAAhAAIJYxduDwClAAAuAAQKfzgAAiEACQlfIeEMAM0CACEACQlfIeEMAM0CAAAA.Grumpÿ:BAAALgADCgYJDAAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIdAAYJXBvFUAC0AQAdAAYJXBvFUAC0AQAAAA==.Gumpers:BAABLgAECn8vAAIiAAkJdRDXBwDtAAAiAAkJdRDXBwDtAAAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gurl:BAAALgADCgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAABLgAECn8jAAIeAAcJ0ATwEwBdAAAeAAcJ0ATwEwBdAAAAAA==.',
Ha='Halfamazing:BAAALgAECgYJDAAAAA==.Hanoumatoi:BAAALgAECgkJDAAAAA==.Haradar:BAAALgADCgEJAQABLgAECgcJJQAFAGcUAA==.Haralambos:BAABLgAECn8lAAIFAAcJZxRABAAzAQAFAAcJZxRABAAzAQAAAA==.Haralogain:BAAALgAECgEJAQABLgAECgcJJQAFAGcUAA==.Harithon:BAABLgAECn8wAAIRAAkJ1SDXAwC9AgARAAkJ1SDXAwC9AgAAAA==.Harlar:BAAALgAECgIJAwAAAA==.Havvöc:BAABLgAECn8sAAIBAAkJoBx5DADHAgABAAkJoBx5DADHAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAABLgAECn8pAAICAAkJ5ANfKwDcAAACAAkJ5ANfKwDcAAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAABLgAECn8rAAIJAAYJ4wxKGQDgAAAJAAYJ4wxKGQDgAAAAAA==.Heyokagi:BAABLgAECn8vAAQaAAkJNyIrAgANAwAaAAkJNyIrAgANAwAiAAIJ1BS5JgBnAAANAAEJXwhz2wAqAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgkJHAAVAPMcAA==.Hordkilla:BAABLgAECn8wAAIEAAkJxAfflwBFAQAEAAkJxAfflwBFAQAAAA==.Hottdealer:BAAALgADCgUJBQAAAA==.Hownowbrncw:BAABLgAECn8lAAIEAAgJLxxGQgAAAgAEAAgJLxxGQgAAAgAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn82AAMdAAkJ2BwkFgCSAgAdAAkJ2BwkFgCSAgAUAAEJphoiLgBKAAAAAA==.Hylda:BAAALgADCgUJBQAAAA==.Hymno:BAAALgAECgEJAgAAAA==.',
Ic='Ic:BAAALgAECgQJBAAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAABLgAECn8jAAQNAAkJChBRBQB6AQANAAkJChBRBQB6AQAeAAcJsw/LDgCRAAAiAAEJmAMeiAAWAAAAAA==.',
Im='Imathdal:BAABLgAECn8tAAIkAAkJvRNQAQCdAQAkAAkJvRNQAQCdAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAPAAAAAA==.Insoniacyun:BAABLgAECn8cAAIJAAgJvws+jABfAQAJAAgJvws+jABfAQAAAA==.',
Is='Iselian:BAAALgAECgkJKQAAAQ==.Ishanu:BAABLgAECn8iAAIHAAkJ8B6yAQBTAgAHAAkJ8B6yAQBTAgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAPAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgAECgkJEgABLgAFFAIJAgAPAAAAAA==.Jax:BAACLgAFFH8NAAIJAAQJRCLATQBDAQAJAAQJRCLATQBDAQAuAAQKfykAAgkACAlFIxATADUDAAkACAlFIxATADUDAAAA.',
Jb='Jbelbueno:BAAALgAECgYJEgAAAA==.Jblockiv:BAAALgADCgcJDAAAAA==.Jblovo:BAAALgAECgUJBQAAAA==.Jbmago:BAAALgAECgEJAQAAAA==.Jbprimero:BAAALgAECgIJAgAAAA==.Jbshami:BAABLgAECn9BAAMQAAkJLiCBEgC5AgAQAAkJLiCBEgC5AgAXAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgUJBgAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn89AAIjAAkJWg6IBACrAQAjAAkJWg6IBACrAQAAAA==.Jetfires:BAABLgAECn9UAAIGAAkJPyDpDADsAgAGAAkJPyDpDADsAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAABLgAECn9BAAIfAAkJMgqSBABDAQAfAAkJMgqSBABDAQAAAA==.Jinnwoo:BAAALgAECgQJBAAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jovie:BAAALgAECgEJAQAAAA==.Jozhua:BAABLgAECn8aAAIGAAgJPA0mkwAZAQAGAAgJPA0mkwAZAQAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.Jungg:BAAALgAECgIJAgAAAA==.',
Ka='Kaedren:BAAALgAECgUJEQAAAA==.Kaelaya:BAABLgAECn8dAAIkAAcJOQqoHADJAAAkAAcJOQqoHADJAAAAAA==.Kaelorien:BAABLgAECn89AAIhAAkJKRJoJgDyAQAhAAkJKRJoJgDyAQAAAA==.Kaetta:BAABLgAECn8XAAIJAAgJ0APiwwAEAQAJAAgJ0APiwwAEAQAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgYJDgAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAABLgAECn8pAAIFAAkJvBCEBAAmAQAFAAkJvBCEBAAmAQAAAA==.Kaldevayn:BAABLgAECn8hAAMBAAkJ8Be+AQBMAgABAAkJ8Be+AQBMAgAEAAMJ8wx7JwCOAAAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgQJBgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8zAAIdAAYJ5hRjCwAeAQAdAAYJ5hRjCwAeAQAAAA==.Kalyna:BAAALgAECgcJDQAAAA==.Kandandris:BAAALgAECgcJCAAAAA==.Kanhoa:BAAALgAECgIJAgAAAA==.Kardanis:BAABLgAECn8uAAIQAAkJviRqAgCiAwAQAAkJviRqAgCiAwAAAA==.Kardzuni:BAAALgADCgEJAQAAAA==.Kashe:BAABLgAECn8jAAMBAAcJyRwyMACZAQABAAYJXxsyMACZAQAEAAEJygxCUgAuAAAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Kasume:BAAALgAECgEJAgAAAA==.Katavia:BAABLgAECn8pAAIQAAkJZxKHPAC8AQAQAAkJZxKHPAC8AQAAAA==.Kaydencia:BAABLgAECn8XAAIEAAYJvxET0gDwAAAEAAYJvxET0gDwAAAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgQJBgAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Ke='Keldormu:BAAALgADCgkJCQAAAA==.Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.Keyallandron:BAAALgAECgIJAgABLgAECggJEwAPAAAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgAECgYJCAAAAA==.Khortical:BAAALgADCgkJCQABLgAECgkJMAARANUgAA==.',
Ki='Ki:BAAALgAECgQJBQAAAA==.Kiddow:BAABLgAECn8XAAIJAAgJyhHmHADHAAAJAAgJyhHmHADHAAAAAA==.Kierea:BAAALgAECgMJAwAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgAECgEJAQAAAA==.Kiri:BAAALgADCgkJEQAAAA==.Kitamii:BAABLgAECn8UAAIaAAYJdRbHEQCQAQAaAAYJdRbHEQCQAQAAAA==.Kivrin:BAABLgAECn8XAAIHAAgJ3wwOBgBOAQAHAAgJ3wwOBgBOAQAAAA==.Kiára:BAAALgAECgEJAQAAAA==.',
Kr='Kringlë:BAABLgAECn8oAAIGAAkJ3SDEGACSAgAGAAkJ3SDEGACSAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kurumi:BAAALgAECgYJCAAAAA==.Kushwizard:BAAALgADCgQJBQAAAA==.Kuunko:BAAALgAECgEJAQAAAA==.',
Ky='Kymma:BAABLgAECn81AAIEAAkJIw4pGADoAAAEAAkJIw4pGADoAAAAAA==.Kyunix:BAAALgAECgYJBgAAAA==.',
La='Lagoriatsua:BAABLgAECn8ZAAIXAAgJlQZYUgDvAAAXAAgJlQZYUgDvAAAAAA==.Laitue:BAAALgAECgQJDAAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAABLgAECn8ZAAMHAAcJ3hqLAwC2AQAHAAcJ3hqLAwC2AQAIAAUJtxEcCQAdAQAAAA==.Lazengann:BAABLgAECn8mAAMdAAkJnRanOwDZAQAdAAkJERWnOwDZAQAOAAIJ/BnGXABUAAAAAA==.',
Le='Leafbane:BAAALgAECgMJAwAAAA==.Leagann:BAAALgAECgEJAQAAAA==.Legevia:BAABLgAECn8fAAMRAAgJwAUzJADVAAARAAgJwAUzJADVAAAQAAIJkgKWzwA8AAAAAA==.Leiris:BAABLgAECn88AAIEAAkJDRFrWgC+AQAEAAkJDRFrWgC+AQAAAA==.Leisha:BAAALgADCgEJAQAAAA==.Letifer:BAAALgAECgMJAwAAAA==.Leucetios:BAAALgAECgUJDgAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8iAAIMAAkJRxmTDgB/AgAMAAkJRxmTDgB/AgAAAA==.Lightbeard:BAABLgAECn8pAAQBAAcJHRxYHgAQAgABAAcJHRxYHgAQAgAEAAIJ+wUDbwFJAAAFAAEJ4A/gUwApAAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAABLgAECn8WAAIEAAgJ7RgPbQCUAQAEAAgJ7RgPbQCUAQAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgAECgYJCwAAAA==.Liubing:BAAALgADCgkJDwABLgAECgMJDwAPAAAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lochli:BAAALgAECgUJCgAAAA==.Loginus:BAAALgAECgUJBQAAAA==.Lorredain:BAAALgAECgUJCwAAAA==.Lothaire:BAAALgADCgEJAQABLgADCgIJAgAPAAAAAA==.Lothwen:BAAALgAECgcJEQAAAA==.Louisachan:BAAALgADCgUJBQABLgAFFAEJAgAPAAAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8dAAIMAAUJqxCzFAAeAQAMAAUJqxCzFAAeAQAuAAQKfzcAAgwACQmPFrUXABACAAwACQmPFrUXABACAAAA.Luxinine:BAABLgAECn8tAAMHAAkJuyB6BgDqAgAHAAkJuyB6BgDqAgAIAAIJsxSZEQCFAAAAAA==.',
Ly='Lyon:BAAALgADCgMJCgAAAA==.Lyshai:BAAALgAECgYJBgABLgAECgkJIwAlAGohAA==.',
Ma='Madhawi:BAABLgAECn9AAAMIAAgJhyWkAABYAwAIAAgJhyWkAABYAwAMAAIJOhSGawB9AAAAAA==.Magamon:BAABLgAECn8wAAIJAAkJBxhkOgAwAgAJAAkJBxhkOgAwAgAAAA==.Magamus:BAAALgADCgYJBgAAAA==.Mahndarb:BAABLgAECn8YAAMEAAYJexAgGADoAAAEAAYJexAgGADoAAABAAMJ1wJRfABUAAABLgAECggJJQAMAE8dAA==.Majima:BAAALgAECgYJDgAAAA==.Makedeader:BAAALgAECgkJBgAAAA==.Malfuriia:BAABLgAECn8pAAIQAAkJ+xeuLAAGAgAQAAkJ+xeuLAAGAgAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Mamboke:BAABLgAECn8UAAMkAAcJZhV3AgAbAQAkAAYJYxR3AgAbAQAGAAEJdBpzPQBKAAAAAA==.Margerdria:BAABLgAECn8YAAIHAAcJJxCYDgCrAAAHAAcJJxCYDgCrAAAAAA==.Maskelle:BAABLgAECn8uAAIUAAkJvBGTDgBnAQAUAAkJvBGTDgBnAQAAAA==.Mauugrim:BAABLgAECn8qAAIWAAkJMwl7FgDVAAAWAAkJMwl7FgDVAAAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAABLgAECn8hAAIEAAkJNhZ2cACNAQAEAAkJNhZ2cACNAQAAAA==.',
Me='Mearadan:BAAALgAECgkJDwAAAA==.Meatsweats:BAABLgAECn8lAAIEAAgJEQvjrAAkAQAEAAgJEQvjrAAkAQAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDwAAAA==.Mekh:BAABLgAECn8jAAMlAAkJaiFABQAPAgAlAAkJaiFABQAPAgAmAAMJOhMmKwCTAAAAAA==.Mel:BAAALgAECgMJDwAAAA==.Melanara:BAABLgAECn9LAAIJAAkJUg/RCwBwAQAJAAkJUg/RCwBwAQAAAA==.Melstrom:BAAALgAECggJEgAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgYJBwAAAA==.Meticuluslyn:BAAALgAECgYJEgAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAABLgAECn8XAAIjAAkJQRa9AwDVAQAjAAkJQRa9AwDVAQAAAA==.Miyävii:BAABLgAECn8YAAIFAAkJxxNGFwBmAQAFAAkJxxNGFwBmAQAAAA==.',
Mj='Mjsage:BAABLgAECn8kAAIGAAkJGR6yJABQAgAGAAkJGR6yJABQAgAAAA==.',
Mm='Mmeow:BAAALgAECgQJBQABLgAECgkJFQAGAMkZAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8kAAIHAAkJqRvfBQBUAQAHAAkJqRvfBQBUAQAAAA==.Mooasha:BAAALgAECgEJAQABLgAECgkJKQAQAGcSAA==.Moonflowers:BAACLgAFFH8fAAINAAgJ/BkJCAB9AgANAAgJ/BkJCAB9AgAuAAQKfy8AAg0ACAmcJM4HAA8DAA0ACAmcJM4HAA8DAAAA.Mordsevoker:BAAALgAFFAIJAgABLgAFFAYJHAAWAJgRAA==.Morginoth:BAAALgADCgcJBwAAAA==.Morregu:BAAALgAECgQJBQAAAA==.Mousekee:BAABLgAECn8qAAIMAAkJkg2UJwCJAQAMAAkJkg2UJwCJAQAAAA==.',
Mu='Muku:BAAALgADCgkJCQABLgAECgkJUQAJANsSAA==.Murdrmitts:BAABLgAECn8wAAIaAAkJyhO8AQDFAQAaAAkJyhO8AQDFAQAAAA==.Muross:BAAALgAECgEJAQAAAA==.Mustikka:BAABLgAECn8fAAIaAAcJThOqBgC7AAAaAAcJThOqBgC7AAAAAA==.',
My='Mystikah:BAAALgAECgEJAQAAAA==.Myuriyanka:BAABLgAECn8pAAMXAAkJoBOGJADDAQAXAAkJoBOGJADDAQAQAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgYJBwAPAAAAAA==.',
Na='Naahommii:BAABLgAECn8hAAIGAAkJxRRLQgDbAQAGAAkJxRRLQgDbAQAAAA==.Nachtpranke:BAABLgAECn8eAAINAAkJMyBaAwDxAQANAAkJMyBaAwDxAQAAAA==.Nadron:BAAALgAECgYJDAAAAA==.Naevala:BAAALgAECgkJCwAAAA==.Nagualli:BAAALgAECgQJBQAAAA==.Navira:BAAALgADCgYJBQAAAA==.',
Ne='Negargra:BAABLgAECn8wAAMVAAYJUxQ1CwAgAQAVAAYJUxQ1CwAgAQAnAAEJcgMufAAkAAAAAA==.Nekwid:BAAALgADCgIJAgAAAA==.Nephadin:BAABLgAECn8dAAMEAAgJpAr7uQARAQAEAAgJpAr7uQARAQABAAUJnAbNWQDPAAAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgYJDgAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nightrunner:BAAALgADCgYJBQAAAA==.Nighttiger:BAABLgAECn8jAAINAAcJTRDSCAD+AAANAAcJTRDSCAD+AAAAAA==.Nikooli:BAABLgAECn8qAAMOAAkJWxliBAB6AQAOAAkJWxliBAB6AQAUAAEJ+AYlPQAaAAAAAA==.Nimb:BAAALgAECgEJBAAAAA==.',
No='Nokkoh:BAAALgADCgQJBwAAAA==.Nolime:BAAALgAECgYJBwAAAA==.Noodledragon:BAAALgAECgYJBwAAAA==.Noopsie:BAABLgAECn87AAINAAgJ6A/OBgA7AQANAAgJ6A/OBgA7AQAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAgJKwAmADQQAA==.Nooters:BAAALgAECgEJAQABLgAFFAgJKwAmADQQAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMIAAgJxhqHFwAZAgAIAAcJLhyHFwAZAgAHAAcJsBxlLAByAQAAAA==.Notpeepuddle:BAAALgAECgEJAQAAAA==.Novarox:BAAALgAECgEJAQAAAA==.',
Nu='Nuhnoo:BAAALgADCgkJCQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8sAAIEAAkJshpyTADhAQAEAAkJshpyTADhAQAAAA==.Nyxalia:BAAALgAECgYJCAAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMjAAkJbgM/EgCgAAAJAAkJWQMu4ADaAAAjAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBQAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgAECgIJAgAAAA==.Olympia:BAABLgAECn8vAAIFAAkJ3A1WHQAqAQAFAAkJ3A1WHQAqAQAAAA==.',
Or='Oraclemega:BAABLgAECn80AAIJAAkJBSA5EAD6AgAJAAkJBSA5EAD6AgAAAA==.Oranash:BAAALgADCgcJCQAAAA==.Orweyna:BAAALgAECggJDwAAAA==.',
Os='Oscarmikey:BAACLgAFFH8fAAMNAAUJ+w4nDwAKAQANAAUJ+w4nDwAKAQAeAAIJXgINKwAtAAAuAAQKf0gABQ0ACQmGHoAQAM0CAA0ACQmGHoAQAM0CAB4ABgn9FU8JAOcAABoAAQlMAr1hACAAACIAAQkAAOuUAAAAAAAA.Oshu:BAAALgAECgYJBgAAAA==.',
Ot='Ottoshot:BAABLgAECn8nAAIGAAkJExT0FAAPAQAGAAkJExT0FAAPAQAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
Ow='Owlaf:BAAALgAECgEJAQAAAA==.',
['Oö']='Oöps:BAABLgAECn8aAAINAAkJKQ0tBgBVAQANAAkJKQ0tBgBVAQAAAA==.',
Pa='Paksen:BAAALgAECgEJAQAAAA==.Panamone:BAABLgAECn8nAAMaAAkJnSQMAgChAQAaAAkJnSQMAgChAQANAAIJBRZfmACBAAAAAA==.Pandeism:BAABLgAECn80AAMRAAkJZxTZDgDDAQARAAgJHxTZDgDDAQAQAAcJoBchRACdAQAAAA==.Papagrip:BAABLgAECn82AAMTAAkJ7xJZDACyAQATAAkJ7xJZDACyAQAWAAkJ6QrOHgCjAAAAAA==.Patrin:BAABLgAECn8gAAIJAAgJZw3ggwBwAQAJAAgJZw3ggwBwAQAAAA==.Paulee:BAAALgADCgkJDgAAAA==.',
Pe='Peanutbritle:BAABLgAECn8qAAISAAkJaAZrLgDrAAASAAkJaAZrLgDrAAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.Pesch:BAAALgAFFAYJAQAAAA==.',
Ph='Phantdoom:BAAALgAECgYJEQAAAA==.Phean:BAAALgAECgEJAQAAAA==.Phylah:BAAALgAECgMJBAAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAECggJKQAEAA8lAA==.',
Pl='Plsdiddyno:BAAALgAFFAEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgQJBwAAAA==.Porterhouze:BAAALgAECgEJAgAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Puchi:BAAALgAECgUJBQAAAA==.Punchabaal:BAAALgAECgcJDAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAINAAcJWRnvMwDZAQANAAcJWRnvMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgQJBAAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Redrollin:BAAALgAECgIJAgAAAA==.Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAYJMQAjAGklAA==.Reyrocko:BAAALgAFFAEJAQAAAA==.Reyva:BAAALgADCgEJAQAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAQJDQAHABsdAA==.Rezdk:BAAALgAECggJCAABLgAFFAQJDQAHABsdAA==.Rezhunt:BAABLgAFFH8FAAMkAAQJJxn/GQDjAAAkAAMJrhj/GQDjAAAcAAEJkhr2LwBUAAABLgAFFAQJDQAHABsdAA==.Rezmonk:BAAALgAFFAEJAQABLgAFFAQJDQAHABsdAA==.Rezshift:BAABLgAECn8bAAMeAAgJwhzjFQAgAgAeAAgJwhzjFQAgAgANAAQJBRbtbwAFAQABLgAFFAQJDQAHABsdAA==.Rezvoid:BAACLgAFFH8NAAMHAAQJGx0AFQA9AQAHAAQJGx0AFQA9AQAMAAIJgyHwIgCjAAAuAAQKfzQAAwcACQkQI84GAOUCAAcACQkQI84GAOUCAAwAAgmjIPFJAL0AAAAA.',
Rh='Rhage:BAAALgAECgMJCgAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAABLgAECn8XAAIWAAcJlRKnngAuAQAWAAcJlRKnngAuAQAAAA==.Roxane:BAABLgAECn8lAAIeAAkJxQmQMABbAQAeAAkJxQmQMABbAQAAAA==.',
Ru='Runningelk:BAABLgAECn8xAAIiAAkJvBLbFQClAQAiAAkJvBLbFQClAQAAAA==.Runscapemain:BAABLgAECn8sAAMEAAkJQBjwVADLAQAEAAkJQBjwVADLAQAFAAYJ/RAUIwD8AAAAAA==.',
Ry='Ryeti:BAAALgADCgkJFwAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDgAOAAEkAA==.',
Sa='Saintulrick:BAAALgAECgIJAwAAAA==.Sajuice:BAACLgAFFH8HAAIkAAUJPwW5GwDSAAAkAAUJPwW5GwDSAAAuAAQKfyYAAiQACAnAGyIKAM8BACQACAnAGyIKAM8BAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn8rAAMMAAkJmg7UKwBrAQAMAAkJmg7UKwBrAQAHAAEJmAMQlwAjAAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAPAAAAAA==.',
Se='Seeyen:BAACLgAFFH8bAAIGAAYJ9hW8MwBGAQAGAAYJ9hW8MwBGAQAuAAQKfywAAgYACQnSHgUHAB8DAAYACQnSHgUHAB8DAAAA.Seeyenn:BAAALgAECgMJAwAAAA==.Selendriel:BAAALgADCggJDwAAAA==.Selfdestruct:BAABLgAECn8iAAIEAAgJoxC/CwBxAQAEAAgJoxC/CwBxAQAAAA==.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8lAAIlAAkJgwrgCgBsAQAlAAkJgwrgCgBsAQAAAA==.Seren:BAAALgAFFAEJAwABLgAFFAcJIQAJAIQNAA==.Serenityhate:BAABLgAECn8jAAMMAAYJVQ3RPQD7AAAMAAYJVQ3RPQD7AAAHAAEJAABzoAAAAAAAAA==.',
Sh='Shaaydo:BAAALgAECgEJBAAAAA==.Shaayjynxx:BAAALgAECgEJAQAAAA==.Shaaytheyha:BAAALgAECgMJAwAAAA==.Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgYJCAAAAA==.Shandrilyn:BAABLgAECn8YAAIHAAcJIARnUQDMAAAHAAcJIARnUQDMAAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAImAAkJwBQgGABQAQAmAAkJwBQgGABQAQAAAA==.Shiziuno:BAAALgAECgQJDgAAAA==.',
Si='Sini:BAAALgAFFAcJBAAAAA==.Sinthoras:BAAALgAECgQJBAAAAA==.Sionarra:BAAALgADCgIJAgAAAA==.',
Sj='Sjðfn:BAAALgAECgkJAgAAAA==.',
Sk='Skala:BAABLgAECn8YAAIoAAkJThZnHADyAQAoAAkJThZnHADyAQAAAA==.Skibbie:BAACLgAFFH8fAAMoAAcJogwBHgBwAQAoAAcJogwBHgBwAQAlAAQJOwoCBgD9AAAuAAQKfx4ABCgACQk4GF8QAHMCACgACQk4GF8QAHMCACYABAmHDpImALgAACUABQnOBpAsALcAAAAA.Skibbward:BAABLgAECn8zAAQiAAgJTiS4AQAyAwAiAAgJTiS4AQAyAwAeAAUJxQ9jVADUAAANAAYJ6QrsggDSAAABLgAFFAcJHwAoAKIMAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAABLgAECn8XAAIQAAgJRR4vFACqAgAQAAgJRR4vFACqAgAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Slickdeath:BAAALgAECgIJBAAAAA==.Slickpraying:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgEJBgABLgAECgIJBwAPAAAAAA==.',
Sm='Smackdogg:BAACLgAFFH8IAAIeAAUJKBxOFwBgAQAeAAUJKBxOFwBgAQAuAAQKfxkAAh4ABwk9HRcdABgCAB4ABwk9HRcdABgCAAEuAAUUCAkwABcAnyAA.',
Sn='Snorpuff:BAAALgAECgUJBQAAAA==.',
So='Solteria:BAABLgAECn8VAAIKAAcJqAk/DgBOAQAKAAcJqAk/DgBOAQABLgAECgkJAgAPAAAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAABLgAECn8ZAAIOAAcJxxDFKAA2AQAOAAcJxxDFKAA2AQAAAA==.Sorvina:BAABLgAECn84AAIVAAkJdBKsQADaAQAVAAkJdBKsQADaAQAAAA==.Soulflame:BAABLgAECn9RAAIJAAkJ2xL7CwBuAQAJAAkJ2xL7CwBuAQAAAA==.Soulshifter:BAABLgAECn8YAAIeAAcJswqlRQD2AAAeAAcJswqlRQD2AAAAAA==.Soultrader:BAAALgADCgkJFwABLgAECgcJJQAFAGcUAA==.',
Sp='Spacetime:BAAALgAECgEJAQAAAA==.Spooñ:BAAALgADCgcJBwABLgAFFAUJFgAhAEocAA==.Spottedcoat:BAABLgAECn8qAAINAAkJhANnfADDAAANAAkJhANnfADDAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgABLgAFFAQJBQAGAOAHAA==.Stasia:BAAALgADCgkJCQAAAA==.Strangerx:BAAALgAECgEJAgAAAA==.Stregnor:BAABLgAECn88AAIGAAkJBBh5JQBMAgAGAAkJBBh5JQBMAgAAAA==.Styggi:BAAALgAECgQJBgAAAA==.Styggian:BAAALgAECggJCgAAAA==.Styggie:BAAALgAECgEJAQAAAA==.Stygy:BAAALgAECgMJBAAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDgAOAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn9DAAMfAAgJehi0GQDjAQAfAAgJehi0GQDjAQAbAAUJsQ7PUQC8AAAAAA==.',
Sv='Svéria:BAAALgADCgcJCgAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMoAAkJDxKrEwBHAgAoAAkJfhGrEwBHAgAlAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgkJJgAoAB4bAA==.Tachie:BAABLgAECn8mAAMoAAkJHhtEDwByAgAoAAkJuBpEDwByAgAlAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAcJHwAKAE4lAA==.Taele:BAABLgAECn8tAAMJAAkJTxzKJwB7AgAJAAkJtBvKJwB7AgAjAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn9gAAIeAAkJSBtrAQCEAgAeAAkJSBtrAQCEAgAAAA==.Tamalpais:BAABLgAECn8dAAIGAAUJZhENJACiAAAGAAUJZhENJACiAAAAAA==.Tamarind:BAAALgAECgYJBgABLgAECgkJMAARANUgAA==.Tamzred:BAAALgAECgYJBgABLgAECgkJKQAEAM8VAA==.Tanyab:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8pAAIGAAkJQAWxJACfAAAGAAkJQAWxJACfAAAAAA==.',
Th='Thaesan:BAAALgAECgYJDwAAAA==.Therin:BAABLgAECn83AAIcAAkJbBiOAgCLAQAcAAkJbBiOAgCLAQAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tillymonick:BAAALgAECgUJCAAAAA==.Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgcJGQAAAA==.Toofast:BAABLgAECn9JAAIQAAkJfiKzCgALAwAQAAkJfiKzCgALAwAAAA==.Toofurrious:BAAALgADCgkJQAAAAA==.Tooghast:BAAALgADCgcJBwAAAA==.Topswimmer:BAACLgAFFH8MAAIJAAIJthJFSQCRAAAJAAIJthJFSQCRAAAuAAQKfxkAAgkABwlSFsxsAKEBAAkABwlSFsxsAKEBAAAA.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgUJBgAAAA==.',
Tr='Traci:BAABLgAECn8jAAIiAAgJyxUBGACRAQAiAAgJyxUBGACRAQAAAA==.Tractor:BAAALgAECggJBgAAAA==.Trifus:BAABLgAECn8pAAMSAAkJ6hg4GACiAQASAAgJlRc4GACiAQAWAAcJ0w84ZACfAQAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAABLgAECn8hAAINAAYJHR5TKgADAgANAAYJHR5TKgADAgAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQABLgAECgQJBgAPAAAAAA==.',
Tu='Tulao:BAABLgAECn84AAIJAAkJtSCnAwB8AgAJAAkJtSCnAwB8AgAAAA==.',
Tw='Twan:BAAALgAFFAEJAgABLgAFFAgJFQAdAAUVAA==.',
Ty='Tyledoriel:BAAALgADCgEJAQAAAA==.Tyrionel:BAAALgAECgUJCgAAAA==.',
Tz='Tzitzimitl:BAAALgAECgYJBwAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIhAAQJaRDxNADXAAAhAAQJaRDxNADXAAAAAA==.',
Ut='Utheli:BAACLgAFFH8VAAIEAAUJqRMfQwAlAQAEAAUJqRMfQwAlAQAuAAQKfx8AAgQACAkBG95MAOABAAQACAkBG95MAOABAAAA.',
Va='Vaevictis:BAABLgAECn8aAAITAAgJfRzGAACeAgATAAgJfRzGAACeAgAAAA==.Vaildora:BAAALgAECgEJAQABLgAECgkJJgAoAB4bAA==.Valdra:BAABLgAECn89AAICAAkJGRPtEgC9AQACAAkJGRPtEgC9AQAAAA==.Valkyl:BAAALgAECgEJAQAAAA==.Valkylpriest:BAAALgAECgEJAgAAAA==.',
Vi='Vidiablade:BAAALgAFFAIJAgAAAA==.Viralprepped:BAAALgAECgMJDwAAAA==.Virelia:BAAALgAECgEJAQAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8hAAMdAAkJbxFWUACVAQAdAAkJbxFWUACVAQAOAAYJEg7zNADrAAAAAA==.',
Vn='Vnasty:BAACLgAFFH8QAAIEAAYJ+gwIUgALAQAEAAYJ+gwIUgALAQAuAAQKfywAAgQACQkrICkKAD8DAAQACQkrICkKAD8DAAAA.',
Vo='Vogue:BAAALgADCgcJBQAAAA==.',
Vr='Vrale:BAAALgAFFAIJAgAAAA==.',
['Vì']='Vì:BAAALgAECgMJAwABLgAFFAYJEAAEAPoMAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Wes:BAAALgAECgEJAQAAAA==.Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wildbear:BAAALgAECgYJBgAAAA==.Wilken:BAABLgAECn84AAIgAAkJ0BviCABjAgAgAAkJ0BviCABjAgAAAA==.Windria:BAAALgAECgMJAwAAAA==.',
Wo='Wobblenozzle:BAAALgAECgEJAQAAAA==.Wolves:BAAALgAECgIJAgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8pAAIEAAkJ/xp6MQA6AgAEAAkJ/xp6MQA6AgAAAA==.',
Ws='Wspr:BAAALgAECgIJBgAAAA==.',
Wu='Wulff:BAAALgADCgMJBgAAAA==.',
Xa='Xaartahli:BAAALgAECgUJEAAAAA==.Xavencia:BAABLgAECn8XAAIJAAkJjQakEQAlAQAJAAkJjQakEQAlAQAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xe='Xenolithia:BAAALgAECgQJBQAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECggJCwAAAA==.',
Ya='Yanut:BAABLgAECn8UAAIEAAYJqQdC7ADPAAAEAAYJqQdC7ADPAAAAAA==.',
Ye='Yeetjin:BAAALgAECggJCwAAAA==.',
Yi='Yinamin:BAABLgAECn8UAAIHAAYJlQtjTQDaAAAHAAYJlQtjTQDaAAAAAA==.',
Yk='Yknub:BAAALgAECgQJBAAAAA==.',
Yo='Yotin:BAAALgAECgYJBgAAAA==.',
Ys='Ysabéll:BAAALgADCgYJBgAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAABLgAECn8jAAINAAkJZhT5JQAeAgANAAkJZhT5JQAeAgAAAA==.Zalanto:BAAALgAECgMJBgAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn9lAAIGAAkJYRfUBAA7AgAGAAkJYRfUBAA7AgAAAA==.',
Ze='Zedator:BAAALgADCgMJAwAAAA==.Zedraikis:BAAALgAECgEJAQAAAA==.Zelgaddis:BAABLgAECn8sAAMQAAkJ6xPqBgCoAQAQAAkJ6xPqBgCoAQARAAIJTQSwQQAsAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn8yAAIoAAgJHhQJAwCMAQAoAAgJHhQJAwCMAQAAAA==.',
Zr='Zrathan:BAEALgAECgEJAQABLgAECgIJAgAPAAAAAA==.Zriana:BAAALgAECgQJCAAAAA==.',
Zs='Zsarilya:BAABLgAECn8uAAIMAAkJMANZDQCTAAAMAAkJMANZDQCTAAAAAA==.',
Zu='Zurgen:BAABLgAECn89AAIVAAkJiyDrDADmAgAVAAkJiyDrDADmAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8yAAINAAgJghUaKQAKAgANAAgJghUaKQAKAgABLgAFFAUJHQAMAKsQAA==.',
['Ýu']='Ýui:BAAALgADCgQJBAAAAA==.',
['ßo']='ßooßear:BAAALgAECgMJBQAAAA==.',
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
