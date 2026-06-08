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
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aarchon:BAABLgAECn8oAAIBAAkJSh+9CAD1AgABAAkJSh+9CAD1AgAAAA==.',
Ad='Aduin:BAABLgAECn8bAAMCAAgJQBbzMgB3AQACAAgJZA/zMgB3AQADAAMJch4bJAACAQAAAA==.',
Ae='Aedarelyn:BAAALgAECgUJEQAAAA==.Aellet:BAABLgAECn8aAAMEAAkJ8xy6HAByAgAEAAkJTRy6HAByAgAFAAQJdx0aGAC6AAAAAA==.Aellita:BAAALgAECgUJDgAAAA==.Aeschylus:BAAALgAECgkJEQAAAA==.',
Ak='Akky:BAABLgAECn8lAAIDAAkJYiBMBgCfAgADAAkJYiBMBgCfAgAAAA==.Aksafiya:BAABLgAECn9WAAMGAAkJShOCGQDyAQAGAAkJShOCGQDyAQAHAAEJWAK8gAAcAAAAAA==.',
Al='Alal:BAABLgAECn8fAAIIAAcJPQ1PpQAuAQAIAAcJPQ1PpQAuAQAAAA==.Alandras:BAABLgAECn8pAAICAAgJXwlgPQBHAQACAAgJXwlgPQBHAQAAAA==.Alaras:BAACLgAFFH8XAAIGAAYJgRA8DwBgAQAGAAYJgRA8DwBgAQAuAAQKfxcAAgYACQnQFQ8aAA8CAAYACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8rAAIFAAkJcxf6BgD1AQAFAAkJcxf6BgD1AQAAAA==.Allrianne:BAAALgAECgMJCgAAAA==.Allyriae:BAABLgAECn8VAAIJAAcJjAlFCAD1AAAJAAcJjAlFCAD1AAAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8lAAIKAAgJTx0tDgB2AgAKAAgJTx0tDgB2AgAAAA==.',
Am='Ambilena:BAABLgAECn8jAAMGAAgJlQxSLQBmAQAGAAgJlQxSLQBmAQAKAAYJVhgFKwBkAQAAAA==.',
An='Andoros:BAABLgAECn86AAILAAkJax65DwDNAgALAAkJax65DwDNAgAAAA==.Angiliana:BAABLgAECn8UAAIMAAUJAw+IOADEAAAMAAUJAw+IOADEAAAAAA==.Angvall:BAAALgAECgYJCAABLgAFFAEJAQANAAAAAA==.Animainiac:BAAALgAECgYJBgABLgAECgkJJgAOAGcSAA==.Anzurath:BAABLgAECn8mAAIPAAkJCxXuSQDeAQAPAAkJCxXuSQDeAQAAAA==.',
Ap='Applebow:BAABLgAECn8pAAIQAAgJphF2HgBWAQAQAAgJphF2HgBWAQAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgAECgYJCAAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgYJCgAAAA==.Armas:BAAALgADCgQJBAAAAA==.Arylin:BAABLgAECn82AAIIAAkJlSMCCQAvAwAIAAkJlSMCCQAvAwAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEBLgAECn8aAAMDAAUJFxXhKgDTAAADAAUJExThKgDTAAACAAEJtxVmoABBAAAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQANAAAAAA==.Asky:BAAALgADCgYJBwABLgAECgYJIgAIAPsBAA==.Asnabel:BAABLgAECn8jAAIRAAgJEwurEQBJAQARAAgJEwurEQBJAQAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astrai:BAAALgADCgcJBwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCgAQAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgAECgQJBAAAAA==.Ayden:BAABLgAECn8bAAMMAAcJKhl9FgDDAQAMAAcJKhl9FgDDAQASAAEJkgqzMAAgAAAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwANAAAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgIJBAAAAA==.',
Bl='Blee:BAABLgAECn8wAAMHAAgJNxFEHwDFAQAHAAgJNxFEHwDFAQAGAAQJlgWRSgCwAAAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.Bluudclaaw:BAAALgADCgkJCgAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8lAAIEAAcJVh6JNgD6AQAEAAcJVh6JNgD6AQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8qAAITAAgJoSCeHABuAgATAAgJoSCeHABuAgAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8YAAIUAAcJAxCMkgA5AQAUAAcJAxCMkgA5AQAAAA==.Brood:BAABLgAECn8rAAIUAAkJyBQESwDaAQAUAAkJyBQESwDaAQAAAA==.Brundles:BAAALgAECgYJBgAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAABLgAECn8oAAMVAAgJ9QYnSAADAQAVAAgJ9QYnSAADAQAOAAUJFgiAiAC5AAAAAA==.',
Ca='Cailaranel:BAABLgAECn8tAAMWAAkJign3IQB1AQAWAAkJoQf3IQB1AQAXAAcJaQmaDwAhAQAAAA==.Calaul:BAABLgAECn8dAAIPAAcJww6XngAuAQAPAAcJww6XngAuAQAAAA==.Calenbraga:BAABLgAECn80AAIYAAkJNRZZCQAhAgAYAAkJNRZZCQAhAgAAAA==.Calisim:BAABLgAECn8fAAIEAAYJrQZNuADSAAAEAAYJrQZNuADSAAAAAA==.Callidae:BAABLgAECn8qAAIKAAkJBxFrGgDnAQAKAAkJBxFrGgDnAQAAAA==.Calmnbald:BAABLgAECn8ZAAIZAAcJeBewOgAJAQAZAAcJeBewOgAJAQAAAA==.Caloh:BAAALgAECgUJBQAAAA==.Cantallbis:BAAALgADCgcJBwAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8lAAIaAAkJlgxfGwC+AQAaAAkJlgxfGwC+AQAAAA==.Cataryn:BAABLgAECn8iAAITAAkJNSRSDgDUAgATAAkJNSRSDgDUAgAAAA==.Catt:BAABLgAECn9LAAIBAAkJGBnJEgBxAgABAAkJGBnJEgBxAgAAAA==.',
Ce='Cellebur:BAABLgAECn8gAAITAAgJvwRyjwATAQATAAgJvwRyjwATAQAAAA==.Ceta:BAABLgAECn87AAIKAAkJDhyEDACQAgAKAAkJDhyEDACQAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAACLgAFFH8GAAMVAAMJWQt0RABsAAAVAAIJ7QR0RABsAAAOAAIJTAJAbQBQAAAuAAQKfysAAw4ACAncEac6ALYBAA4ACAncEac6ALYBABUABwm2GUkrAIsBAAAA.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn88AAIIAAgJbwYNowAxAQAIAAgJbwYNowAxAQAAAA==.Cizean:BAABLgAECn8iAAIIAAYJ+wGMCgGPAAAIAAYJ+wGMCgGPAAAAAA==.',
Cr='Craivan:BAAALgAECgUJDwAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crilly:BAABLgAECn8rAAIIAAkJZRjlNwAyAgAIAAkJZRjlNwAyAgAAAA==.Crowe:BAAALgAECgUJCgABLgAECgUJBQANAAAAAA==.Crowley:BAAALgADCgMJAwAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAABLgAECn8XAAIOAAYJsgvUawAIAQAOAAYJsgvUawAIAQAAAA==.Cyrr:BAAALgAECgEJAQAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJDAAAAA==.Damia:BAABLgAECn8pAAMWAAgJRxleFQDnAQAWAAgJRxleFQDnAQAXAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8mAAIQAAkJ8CSSAwABAwAQAAkJ8CSSAwABAwAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgEJAgABLgAECgkJJgAQAPAkAA==.Delvarrieth:BAABLgAECn8iAAIbAAYJcBG1IQD5AAAbAAYJcBG1IQD5AAAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Denth:BAABLgAECn8bAAIPAAkJjA3IZgCXAQAPAAkJjA3IZgCXAQAAAA==.Dercuur:BAABLgAECn8cAAIVAAgJzBVdIgDEAQAVAAgJzBVdIgDEAQAAAA==.Devoursol:BAABLgAECn85AAMcAAkJlQzQVAB8AQAcAAkJaAzQVAB8AQAMAAIJrg45XABvAAAAAA==.',
Di='Dipndots:BAAALgAECgYJBwABLgAECgkJJgAQAPAkAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Doist:BAAALgAECgIJAgAAAA==.Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgAECgMJAwAAAA==.Drainmee:BAABLgAECn8ZAAIHAAYJiBIDLwBXAQAHAAYJiBIDLwBXAQAAAA==.Draknol:BAAALgAECgEJAQAAAA==.Dregoth:BAABLgAECn8lAAIUAAkJkQd7dgBuAQAUAAkJkQd7dgBuAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.',
Du='Durpee:BAABLgAECn8gAAMHAAcJJSTJCADeAgAHAAcJJSTJCADeAgAKAAIJOhSGawB9AAAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8gAAMLAAkJ4R5kEAC0AgALAAkJ4R5kEAC0AgAdAAEJxgkUkgAnAAAAAA==.',
Ea='Eathur:BAAALgADCgcJDwAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elunariel:BAAALgAECgEJAgABLgAECgkJGgAEAPMcAA==.Elynth:BAABLgAECn8lAAIEAAkJGBx6IABcAgAEAAkJGBx6IABcAgAAAA==.',
En='Endlessyueh:BAABLgAECn8YAAMPAAYJvw3XvAAAAQAPAAYJvw3XvAAAAQABAAYJNQUNWQDGAAAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgkJGgAEAPMcAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAFFAQJBAABLgAFFAUJDQAPAPAOAA==.',
Fa='Face:BAAALgAECggJBgAAAA==.Faethian:BAACLgAFFH8UAAIbAAUJSiHZAgB4AQAbAAUJSiHZAgB4AQAuAAQKfywAAhsACAk7JVcDANcCABsACAk7JVcDANcCAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8uAAIIAAkJQAe5gwBpAQAIAAkJQAe5gwBpAQAAAA==.Fangren:BAABLgAECn8ZAAITAAYJuw8ahgAlAQATAAYJuw8ahgAlAQAAAA==.Fariah:BAAALgAECgUJEwAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAABLgAECn8XAAIeAAcJ2gdSQwDkAAAeAAcJ2gdSQwDkAAAAAA==.',
Fe='Felscythe:BAABLgAECn8hAAIZAAYJpQHWYACFAAAZAAYJpQHWYACFAAAAAA==.Felynn:BAABLgAECn8rAAIBAAkJgxiiFABeAgABAAkJgxiiFABeAgAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feresdenn:BAAALgADCgQJBAAAAA==.Feyrha:BAAALgADCgYJBgABLgAECggJIgATAKoQAA==.',
Fi='Fiadh:BAAALgAECgQJBgAAAA==.Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8cAAIfAAYJJB01JADqAQAfAAYJJB01JADqAQAAAA==.',
Fl='Flaeli:BAABLgAECn8nAAIIAAgJYBfyTgDpAQAIAAgJYBfyTgDpAQAAAA==.Flemish:BAAALgAECgcJEQAAAA==.Flextame:BAAALgAECgQJDgAAAA==.Flipalicious:BAABLgAECn9AAAMOAAkJehw+EADDAgAOAAkJehw+EADDAgAVAAIJSxQplAA9AAAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8dAAIGAAcJaBc+KACEAQAGAAcJaBc+KACEAQAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn8iAAITAAgJqhCTVwCRAQATAAgJqhCTVwCRAQAAAA==.Gangstafred:BAAALgADCgYJBgAAAA==.Gazo:BAAALgAECgYJCwABLgAECgkJKwAeADsfAA==.',
Ge='Gemboss:BAABLgAECn9JAAMPAAgJ+yBXIQB4AgAPAAgJ+yBXIQB4AgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8uAAMIAAkJmxPqWgDHAQAIAAkJmxPqWgDHAQAgAAMJoAbAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8wAAIeAAkJOwoBKgBeAQAeAAkJOwoBKgBeAQAAAA==.Ginodh:BAABLgAECn8OAAIcAAgJtQ3FdQApAQAcAAgJtQ3FdQApAQABLgAECgkJGQAQAPwNAA==.Ginomage:BAAALgAECgcJCgABLgAECgkJGQAQAPwNAA==.Ginomonk:BAAALgAECgYJBgABLgAECgkJGQAQAPwNAA==.Ginopally:BAAALgAECgYJCwABLgAECgkJGQAQAPwNAA==.Girth:BAAALgADCgIJAgAAAA==.Gizelli:BAAALgAFFAEJAQAAAA==.',
Gl='Glorby:BAAALgAECgQJBAABLgAFFAIJBQAfAGMXAA==.',
Go='Gordonn:BAAALgAECgYJBwAAAA==.',
Gr='Groblock:BAAALgADCgYJEgAAAA==.Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAfAGMXAA==.Grubetsella:BAACLgAFFH8FAAIfAAIJYxduDwClAAAfAAIJYxduDwClAAAuAAQKfzMAAh8ACAmcIrsLAM0CAB8ACAmcIrsLAM0CAAAA.Grumpÿ:BAAALgADCgYJBgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIcAAYJXBvFUAC0AQAcAAYJXBvFUAC0AQAAAA==.Gumpers:BAABLgAECn8qAAIhAAkJtA6XGwBeAQAhAAkJtA6XGwBeAQAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAABLgAECn8UAAIdAAYJ6AG5cQBXAAAdAAYJ6AG5cQBXAAAAAA==.',
Ha='Halfamazing:BAAALgAECgQJBQAAAA==.Hanoumatoi:BAAALgAECgYJBwAAAA==.Haralambos:BAABLgAECn8bAAIbAAUJwBKeJgDTAAAbAAUJwBKeJgDTAAAAAA==.Haralogain:BAAALgAECgEJAQABLgAECgUJGwAbAMASAA==.Harithon:BAABLgAECn8rAAIiAAkJHyBsAwDDAgAiAAkJHyBsAwDDAgAAAA==.Harlar:BAAALgAECgIJAwAAAA==.Havvöc:BAABLgAECn8sAAIBAAkJoByJCwDKAgABAAkJoByJCwDKAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAABLgAECn8nAAIDAAgJUgT6KADfAAADAAgJUgT6KADfAAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAABLgAECn8gAAIIAAYJZwqsxgD6AAAIAAYJZwqsxgD6AAAAAA==.Heyokagi:BAABLgAECn8vAAQYAAkJNyLmAQARAwAYAAkJNyLmAQARAwAhAAIJ1BS5JgBnAAALAAEJXwha0QAsAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgkJGgAEAPMcAA==.Hordkilla:BAABLgAECn8vAAIPAAkJxAdnjgBJAQAPAAkJxAdnjgBJAQAAAA==.Hottdealer:BAAALgADCgUJBQAAAA==.Hownowbrncw:BAABLgAECn8fAAIPAAcJxhsqVQDAAQAPAAcJxhsqVQDAAQAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn82AAMcAAkJ2BzNFACTAgAcAAkJ2BzNFACTAgASAAEJphohKwBKAAAAAA==.Hylda:BAAALgADCgUJBQAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAAALgAECgcJEQAAAA==.',
Im='Imathdal:BAABLgAECn8lAAIjAAkJrw6gDACLAQAjAAkJrw6gDACLAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQANAAAAAA==.Insoniacyun:BAABLgAECn8aAAIIAAgJGgsuhABpAQAIAAgJGgsuhABpAQAAAA==.',
Is='Iselian:BAAALgAECgkJIQAAAQ==.Ishanu:BAABLgAECn8aAAIGAAkJIhxhDgBqAgAGAAkJIhxhDgBqAgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQANAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgADCgkJGgABLgAFFAIJAgANAAAAAA==.Jax:BAACLgAFFH8NAAIIAAQJRCJfQgBYAQAIAAQJRCJfQgBYAQAuAAQKfykAAggACAlFIxATADUDAAgACAlFIxATADUDAAAA.',
Jb='Jblockiv:BAAALgADCgcJDAAAAA==.Jbprimero:BAAALgADCgUJBQAAAA==.Jbshami:BAABLgAECn84AAMOAAgJUB8FEQC7AgAOAAgJUB8FEQC7AgAVAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgUJBgAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn89AAIgAAkJWg4dBACzAQAgAAkJWg4dBACzAQAAAA==.Jetfires:BAABLgAECn9LAAITAAkJPyD6CgD0AgATAAkJPyD6CgD0AgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAABLgAECn8iAAIeAAgJjwU2RADhAAAeAAgJjwU2RADhAAAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jovie:BAAALgAECgEJAQAAAA==.Jozhua:BAAALgAECgYJEAAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.Jungg:BAAALgAECgIJAgAAAA==.',
Ka='Kaedren:BAAALgAECgQJBAAAAA==.Kaelaya:BAABLgAECn8cAAIjAAYJgwriGgDMAAAjAAYJgwriGgDMAAAAAA==.Kaelorien:BAABLgAECn89AAIfAAkJKRJDIwDxAQAfAAkJKRJDIwDxAQAAAA==.Kaetta:BAABLgAECn8XAAIIAAgJ0AOvuwALAQAIAAgJ0AOvuwALAQAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgYJDgAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAABLgAECn8XAAIbAAYJRBHYIAAAAQAbAAYJRBHYIAAAAQAAAA==.Kaldevayn:BAAALgAECgYJDgAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgQJBgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8jAAIcAAYJsAxGlwDlAAAcAAYJsAxGlwDlAAAAAA==.Kandandris:BAAALgAECgYJBgAAAA==.Kardanis:BAABLgAECn8rAAIOAAkJviQBAgClAwAOAAkJviQBAgClAwAAAA==.Kashe:BAABLgAECn8ZAAIBAAUJox3/LQCbAQABAAUJox3/LQCbAQAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAABLgAECn8mAAIOAAkJZxKwOAC/AQAOAAkJZxKwOAC/AQAAAA==.Kaydencia:BAABLgAECn8XAAIPAAYJvxF1xwDxAAAPAAYJvxF1xwDxAAAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgQJBgAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgAECgEJAQAAAA==.',
Ki='Ki:BAAALgAECgQJBAAAAA==.Kiddow:BAAALgAECgUJEgAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgAECgEJAQAAAA==.Kiri:BAAALgADCgkJEQAAAA==.Kitamii:BAABLgAECn8UAAIYAAYJdRbHEQCQAQAYAAYJdRbHEQCQAQAAAA==.Kivrin:BAAALgAECgUJDQAAAA==.',
Kr='Kringlë:BAABLgAECn8oAAITAAkJ3SDTFQCaAgATAAkJ3SDTFQCaAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kushwizard:BAAALgADCgQJBQAAAA==.Kuunko:BAAALgAECgEJAQAAAA==.',
Ky='Kymma:BAABLgAECn8wAAIPAAgJBw7+hQBYAQAPAAgJBw7+hQBYAQAAAA==.Kyunix:BAAALgADCgYJDAAAAA==.',
La='Lagoriatsua:BAABLgAECn8ZAAIVAAgJlQYzTQDxAAAVAAgJlQYzTQDxAAAAAA==.Laitue:BAAALgAECgQJDAAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgYJCwAAAA==.Lazengann:BAABLgAECn8mAAMcAAkJnRYTOQDWAQAcAAkJERUTOQDWAQAMAAIJ/Bl9VQBVAAAAAA==.',
Le='Leafbane:BAAALgADCgEJAQAAAA==.Leagann:BAAALgAECgEJAQAAAA==.Legevia:BAABLgAECn8bAAMiAAYJ+wSnJAC8AAAiAAYJ+wSnJAC8AAAOAAIJkgJXwwA8AAAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAABLgAECn88AAIPAAkJDRE5VADDAQAPAAkJDRE5VADDAQAAAA==.Leisha:BAAALgADCgEJAQAAAA==.Letifer:BAAALgADCgkJDAAAAA==.Leucetios:BAAALgAECgQJBAAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8iAAIKAAkJRxlpDQCDAgAKAAkJRxlpDQCDAgAAAA==.Lightbeard:BAABLgAECn8kAAQBAAcJ0xt4IQDtAQABAAYJMh14IQDtAQAPAAIJ+wWCWQFLAAAbAAEJ4A9vTwApAAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAABLgAECn8WAAIPAAgJ7Rh6ZgCXAQAPAAgJ7Rh6ZgCXAQAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgAECgMJAwAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lorredain:BAAALgAECgQJBAAAAA==.Lothwen:BAAALgAECgYJDAAAAA==.Louisachan:BAAALgADCgUJBQABLgAFFAEJAQANAAAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8TAAIKAAUJFxAmEgAkAQAKAAUJFxAmEgAkAQAuAAQKfzcAAgoACQmPFhAWABMCAAoACQmPFhAWABMCAAAA.Luxinine:BAABLgAECn8dAAIGAAcJAx6mGAD6AQAGAAcJAx6mGAD6AQAAAA==.',
Ly='Lyon:BAAALgADCgMJCgAAAA==.Lyshai:BAAALgAECgYJBgABLgAECgYJHAAkAOQfAA==.',
Ma='Magamon:BAABLgAECn8tAAIIAAkJHBcsNgA5AgAIAAkJHBcsNgA5AgAAAA==.Magamus:BAAALgADCgYJBgAAAA==.Mahndarb:BAAALgAECgMJBgABLgAECggJJQAKAE8dAA==.Majima:BAAALgAECgYJDgAAAA==.Malfuriia:BAABLgAECn8iAAIOAAYJURv3MgDZAQAOAAYJURv3MgDZAQAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Mamboke:BAAALgAECgYJBgAAAA==.Margerdria:BAABLgAECn8VAAIGAAUJDQ1WTgDNAAAGAAUJDQ1WTgDNAAAAAA==.Maskelle:BAABLgAECn8pAAISAAgJoRG6DQBnAQASAAgJoRG6DQBnAQAAAA==.Mauugrim:BAABLgAECn8lAAIUAAgJowgZiQBJAQAUAAgJowgZiQBJAQAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAABLgAECn8aAAIPAAYJ9BbGhQBZAQAPAAYJ9BbGhQBZAQAAAA==.',
Me='Mearadan:BAAALgAECgkJDwAAAA==.Meatsweats:BAABLgAECn8eAAIPAAcJ4Qn5rgAVAQAPAAcJ4Qn5rgAVAQAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDwAAAA==.Mekh:BAABLgAECn8cAAMkAAYJ5B8ZBwDDAQAkAAYJ5B8ZBwDDAQAlAAMJOhOiKQCSAAAAAA==.Mel:BAAALgAECgMJCgAAAA==.Melanara:BAABLgAECn89AAIIAAkJbgwQYgC0AQAIAAkJbgwQYgC0AQAAAA==.Melstrom:BAAALgAECgYJDAAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgYJBwAAAA==.Meticuluslyn:BAAALgAECgQJBAAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAABLgAECn8WAAIgAAkJ0RNvAwDdAQAgAAkJ0RNvAwDdAQAAAA==.Miyävii:BAABLgAECn8YAAIbAAkJxxPlFQBpAQAbAAkJxxPlFQBpAQAAAA==.',
Mj='Mjsage:BAABLgAECn8jAAITAAkJDx67IABZAgATAAkJDx67IABZAgAAAA==.',
Mm='Mmeow:BAAALgAECgQJBQABLgAECgkJDwANAAAAAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8dAAIGAAYJFRq1KACBAQAGAAYJFRq1KACBAQAAAA==.Mooasha:BAAALgAECgEJAQABLgAECgkJJgAOAGcSAA==.Moonflowers:BAACLgAFFH8dAAILAAcJQxzyBQCLAgALAAcJQxzyBQCLAgAuAAQKfy8AAgsACAmcJM4HAA8DAAsACAmcJM4HAA8DAAAA.Mordsevoker:BAAALgAFFAIJAgABLgAFFAUJFgAUAFwSAA==.Morginoth:BAAALgADCgcJBwAAAA==.Mousekee:BAABLgAECn8iAAIKAAgJSQrYMAA7AQAKAAgJSQrYMAA7AQAAAA==.',
Mu='Muku:BAAALgADCgkJCQABLgAECgkJQAAIABwQAA==.Murdrmitts:BAABLgAECn8cAAIYAAgJJQySGQAwAQAYAAgJJQySGQAwAQAAAA==.Mustikka:BAABLgAECn8ZAAIYAAUJJg+4JgDDAAAYAAUJJg+4JgDDAAAAAA==.',
My='Myuriyanka:BAABLgAECn8pAAMVAAkJoBM7IgDFAQAVAAkJoBM7IgDFAQAOAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgYJBwANAAAAAA==.',
Na='Naahommii:BAABLgAECn8gAAITAAkJxRRRPADjAQATAAkJxRRRPADjAQAAAA==.Nachtpranke:BAABLgAECn8ZAAILAAgJ9B7xFgCGAgALAAgJ9B7xFgCGAgAAAA==.Nadron:BAAALgAECgMJBQAAAA==.Naevala:BAAALgAECgkJBAAAAA==.Nagualli:BAAALgAECgQJBQAAAA==.',
Ne='Negargra:BAABLgAECn8kAAMEAAYJ5w/dogD1AAAEAAYJ5w/dogD1AAAmAAEJcgMufAAkAAAAAA==.Nephadin:BAABLgAECn8WAAMPAAcJ5AfTwQD5AAAPAAcJ5AfTwQD5AAABAAUJEgbCVwDLAAAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgYJDgAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAABLgAECn8ZAAILAAUJ/AqGfAC5AAALAAUJ/AqGfAC5AAAAAA==.Nikooli:BAABLgAECn8YAAIMAAYJhRa3IwBHAQAMAAYJhRa3IwBHAQAAAA==.Nimb:BAAALgAECgEJAwAAAA==.Nitaya:BAAALgAECgEJAQAAAA==.',
No='Nokkoh:BAAALgADCgQJBwAAAA==.Nolime:BAAALgAECgYJBwAAAA==.Noodledragon:BAAALgAECgYJBwAAAA==.Noopsie:BAABLgAECn8qAAILAAgJRguEUQA/AQALAAgJRguEUQA/AQAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAcJIwAlAOQRAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMHAAgJxhoSFgAbAgAHAAcJLhwSFgAbAgAGAAcJsByTKgB2AQAAAA==.Notpeepuddle:BAAALgAECgEJAQAAAA==.Novarox:BAAALgAECgEJAQAAAA==.',
Nu='Nuhnoo:BAAALgADCgkJCQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8lAAIPAAYJwBzlYACkAQAPAAYJwBzlYACkAQAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMgAAkJbgM/EgCgAAAIAAkJWQM+1wDhAAAgAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBAAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCggJDwAAAA==.Olympia:BAABLgAECn8pAAIbAAkJXQ25GwAsAQAbAAkJXQ25GwAsAQAAAA==.',
Or='Oraclemega:BAABLgAECn8rAAIIAAkJyBsdHACsAgAIAAkJyBsdHACsAgAAAA==.Orweyna:BAAALgAECgcJCgAAAA==.',
Os='Oscarmikey:BAACLgAFFH8YAAMLAAUJDQu0IwAwAQALAAUJDQu0IwAwAQAdAAEJhAFSTgAqAAAuAAQKfzIABQsACQmSHJgPAM4CAAsACQmSHJgPAM4CAB0ABQmqERBMAM0AABgAAQlMApZXACEAACEAAQkAADqGAAAAAAAA.Oshu:BAAALgAECgYJBgAAAA==.',
Ot='Ottoshot:BAABLgAECn8gAAITAAYJZBK+egA8AQATAAYJZBK+egA8AQAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
Ow='Owlaf:BAAALgAECgEJAQAAAA==.',
['Oö']='Oöps:BAAALgAECgcJDwAAAA==.',
Pa='Panamone:BAABLgAECn8hAAMYAAYJuyTSCQAWAgAYAAYJuyTSCQAWAgALAAEJfxRawQA9AAAAAA==.Pandeism:BAABLgAECn8oAAMOAAgJnRlvQACeAQAOAAYJiRdvQACeAQAiAAcJKxSrEwBvAQAAAA==.Papagrip:BAABLgAECn8tAAMRAAkJDxIrCwC2AQARAAkJDxIrCwC2AQAUAAgJeQlrmgAsAQAAAA==.Patrin:BAABLgAECn8gAAIIAAgJZw2EewB6AQAIAAgJZw2EewB6AQAAAA==.Paulee:BAAALgADCgkJDgAAAA==.',
Pe='Peanutbritle:BAABLgAECn8nAAIQAAkJaAb2KgD3AAAQAAkJaAb2KgD3AAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.Pesch:BAAALgAECgkJEwAAAA==.',
Ph='Phantdoom:BAAALgAECgYJEQAAAA==.Phean:BAAALgAECgEJAQAAAA==.Phylah:BAAALgAECgMJAwAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAECggJKQAPAA8lAA==.',
Pl='Plsdiddyno:BAAALgAFFAEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgMJBgAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Puchi:BAAALgAECgUJBQAAAA==.Punchabaal:BAAALgAECgcJDAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAILAAcJWRnvMwDZAQALAAcJWRnvMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgQJBAAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAYJIgAIAEQlAA==.Reyrocko:BAAALgAECgQJBAAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAQJDQAGABsdAA==.Rezdk:BAAALgAECggJCAABLgAFFAQJDQAGABsdAA==.Rezhunt:BAAALgAFFAMJAwABLgAFFAQJDQAGABsdAA==.Rezshift:BAABLgAECn8bAAMdAAgJwhyuFAAgAgAdAAgJwhyuFAAgAgALAAQJBRbtbwAFAQABLgAFFAQJDQAGABsdAA==.Rezvoid:BAACLgAFFH8NAAMGAAQJGx3sEQBEAQAGAAQJGx3sEQBEAQAKAAIJgyGnHwCnAAAuAAQKfzIAAgYACQkQIyQGAOwCAAYACQkQIyQGAOwCAAAA.',
Rh='Rhage:BAAALgAECgMJBwAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAABLgAECn8XAAIUAAcJlRLglgAyAQAUAAcJlRLglgAyAQAAAA==.Roxane:BAABLgAECn8lAAIdAAkJxQlpLQBfAQAdAAkJxQlpLQBfAQAAAA==.',
Ru='Runningelk:BAABLgAECn8xAAIhAAkJvBIHFAClAQAhAAkJvBIHFAClAQAAAA==.Runscapemain:BAABLgAECn8qAAMPAAkJ2xUqTwDQAQAPAAkJvRUqTwDQAQAbAAYJ/RBNIQD9AAAAAA==.',
Ry='Ryeti:BAAALgADCgkJFwAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDgAMAAEkAA==.',
Sa='Saintulrick:BAAALgAECgIJAwAAAA==.Sajuice:BAACLgAFFH8HAAIjAAUJPwUlGADfAAAjAAUJPwUlGADfAAAuAAQKfyYAAiMACAnAG3QJANIBACMACAnAG3QJANIBAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn8lAAMKAAgJ1w6wKQBsAQAKAAgJ1w6wKQBsAQAGAAEJmAO8jQAjAAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgANAAAAAA==.',
Se='Seeyen:BAACLgAFFH8TAAITAAUJGBcyNwA0AQATAAUJGBcyNwA0AQAuAAQKfywAAhMACQnSHgUHAB8DABMACQnSHgUHAB8DAAAA.Selfdestruct:BAAALgADCgcJBwAAAA==.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8gAAIkAAkJiAklCgByAQAkAAkJiAklCgByAQAAAA==.Seren:BAAALgAFFAEJAgABLgAFFAcJFAAIAP4IAA==.Serenityhate:BAABLgAECn8YAAMKAAYJUwk7QADeAAAKAAYJUwk7QADeAAAGAAEJAADslQAAAAAAAA==.',
Sh='Shaaydo:BAAALgAECgEJAgAAAA==.Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgYJBgAAAA==.Shandrilyn:BAABLgAECn8YAAIGAAcJIAQsTADVAAAGAAcJIAQsTADVAAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAIlAAkJwBRZFwBSAQAlAAkJwBRZFwBSAQAAAA==.',
Si='Sini:BAAALgAFFAcJBAAAAA==.Sinthoras:BAAALgAECgQJBAAAAA==.',
Sj='Sjðfn:BAAALgAECgkJAgAAAA==.',
Sk='Skala:BAABLgAECn8YAAInAAkJThYSGwD1AQAnAAkJThYSGwD1AQAAAA==.Skibbie:BAACLgAFFH8XAAMkAAYJFwxSBQAHAQAnAAYJpAtlIwAuAQAkAAQJyghSBQAHAQAuAAQKfx4ABCcACQk4GF8QAHMCACcACQk4GF8QAHMCACQABQnOBpAsALcAACUABAmHDkklALcAAAAA.Skibbward:BAABLgAECn8zAAQhAAgJTiS4AQAyAwAhAAgJTiS4AQAyAwAdAAUJxQ9jVADUAAALAAYJ6QrsggDSAAABLgAFFAYJFwAkABcMAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAABLgAECn8VAAIOAAgJnB2HFACbAgAOAAgJnB2HFACbAgAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgEJAwABLgAECgIJBgANAAAAAA==.',
Sm='Smackdogg:BAABLgAECn8ZAAIdAAcJPR0XHQAYAgAdAAcJPR0XHQAYAgABLgAFFAgJKwAVAGkdAA==.',
So='Solteria:BAABLgAECn8VAAIFAAcJqAk/DgBOAQAFAAcJqAk/DgBOAQABLgAECgkJAgANAAAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAABLgAECn8ZAAIMAAcJxxB2JQA7AQAMAAcJxxB2JQA7AQAAAA==.Sorvina:BAABLgAECn84AAIEAAkJdBL1PADiAQAEAAkJdBL1PADiAQAAAA==.Soulflame:BAABLgAECn9AAAIIAAkJHBDKTADuAQAIAAkJHBDKTADuAQAAAA==.Soulshifter:BAABLgAECn8YAAIdAAcJswoGQgD3AAAdAAcJswoGQgD3AAAAAA==.Soultrader:BAAALgADCgkJFwABLgAECgUJGwAbAMASAA==.',
Sp='Spacetime:BAAALgAECgEJAQAAAA==.Spooñ:BAAALgADCgcJBwABLgAFFAUJFgAfAEocAA==.Spottedcoat:BAABLgAECn8nAAILAAkJdwMLeADFAAALAAkJdwMLeADFAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgAAAA==.Strangerx:BAAALgAECgEJAgAAAA==.Stregnor:BAABLgAECn88AAITAAkJBBjpIQBSAgATAAkJBBjpIQBSAgAAAA==.Styggi:BAAALgAECgIJAgAAAA==.Styggian:BAAALgAECgUJBgAAAA==.Stygy:BAAALgAECgMJAwAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDgAMAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn87AAMeAAgJuBUiHgCvAQAeAAgJuBUiHgCvAQAZAAUJsQ6QTgC+AAAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMnAAkJDxKrEwBHAgAnAAkJfhGrEwBHAgAkAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgkJJgAnAB4bAA==.Tachie:BAABLgAECn8mAAMnAAkJHhuaDgByAgAnAAkJuBqaDgByAgAkAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAYJGQAFABYmAA==.Taele:BAABLgAECn8tAAMIAAkJTxxXJQCAAgAIAAkJtBtXJQCAAgAgAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn80AAIdAAkJFQ4iJwCIAQAdAAkJFQ4iJwCIAQAAAA==.Tamalpais:BAABLgAECn8VAAITAAUJAQ0ZrQDYAAATAAUJAQ0ZrQDYAAAAAA==.Tamarind:BAAALgAECgYJBgABLgAECgkJKwAiAB8gAA==.Tamzred:BAAALgAECgYJBgABLgAECgkJJgAPAAsVAA==.Tanyab:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8iAAITAAYJtwMftgDHAAATAAYJtwMftgDHAAAAAA==.',
Th='Thaesan:BAAALgAECgYJDwAAAA==.Therin:BAABLgAECn8wAAIaAAkJHRXUEQAYAgAaAAkJHRXUEQAYAgAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tillymonick:BAAALgAECgUJBgAAAA==.Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgYJFAAAAA==.Toofast:BAABLgAECn8xAAIOAAgJDyGrCwD0AgAOAAgJDyGrCwD0AgAAAA==.Toofurrious:BAAALgADCgkJNwAAAA==.Topswimmer:BAACLgAFFH8FAAIIAAIJfAerngCJAAAIAAIJfAerngCJAAAuAAQKfxkAAggABwlSFqloAKQBAAgABwlSFqloAKQBAAAA.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgUJBgAAAA==.',
Tr='Traci:BAAALgAECggJEgAAAA==.Trifus:BAABLgAECn8hAAMUAAkJmxUYXgCmAQAUAAcJ0w8YXgCmAQAQAAcJOxReHwBOAQAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAABLgAECn8aAAILAAYJpx0dKgD7AQALAAYJpx0dKgD7AQAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.',
Tu='Tulao:BAABLgAECn8rAAIIAAgJvxuTMQBMAgAIAAgJvxuTMQBMAgAAAA==.',
Tw='Twan:BAAALgAECgYJBwABLgAFFAYJEQAcANkYAA==.',
Ty='Tyledoriel:BAAALgADCgEJAQAAAA==.Tyrionel:BAAALgAECgUJCgAAAA==.',
Tz='Tzitzimitl:BAAALgAECgYJBwAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIfAAQJaRCBLQDcAAAfAAQJaRCBLQDcAAAAAA==.',
Ut='Utheli:BAACLgAFFH8QAAIPAAQJXBMyPQAiAQAPAAQJXBMyPQAiAQAuAAQKfx8AAg8ACAkBGwRIAOMBAA8ACAkBGwRIAOMBAAAA.',
Va='Vaevictis:BAAALgAECgUJBgABLgAECgcJHQAGAGgXAA==.Vaildora:BAAALgAECgEJAQABLgAECgkJJgAnAB4bAA==.Valdra:BAABLgAECn89AAIDAAkJGROBEQDEAQADAAkJGROBEQDEAQAAAA==.',
Vi='Vidiablade:BAAALgAFFAIJAgAAAA==.Viralprepped:BAAALgAECgMJCgAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8fAAMcAAkJ6w5XTACUAQAcAAkJ6w5XTACUAQAMAAYJEg41MQDsAAAAAA==.',
Vn='Vnasty:BAACLgAFFH8NAAIPAAUJ8A7zRwAPAQAPAAUJ8A7zRwAPAQAuAAQKfywAAg8ACQkrICkKAD8DAA8ACQkrICkKAD8DAAAA.',
Vr='Vrale:BAAALgAECgkJEQAAAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Wes:BAAALgAECgEJAQAAAA==.Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wildbear:BAAALgAECgYJBgAAAA==.Wilken:BAABLgAECn8sAAIoAAkJ9BcdCQBRAgAoAAkJ9BcdCQBRAgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8mAAIPAAkJ/xr7LQA+AgAPAAkJ/xr7LQA+AgAAAA==.',
Ws='Wspr:BAAALgAECgIJBgAAAA==.',
Wu='Wulff:BAAALgADCgMJBgAAAA==.',
Xa='Xaartahli:BAAALgAECgUJDAAAAA==.Xavencia:BAAALgAECgYJDwAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECgYJCAAAAA==.',
Ya='Yanut:BAABLgAECn8UAAIPAAYJqQc23wDSAAAPAAYJqQc23wDSAAAAAA==.',
Ye='Yeetjin:BAAALgAECgMJAgAAAA==.',
Yi='Yinamin:BAAALgAECgYJEgAAAA==.',
Yk='Yknub:BAAALgADCgYJCQAAAA==.',
Yo='Yotin:BAAALgAECgYJBgAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAABLgAECn8hAAILAAkJTBOBJAAeAgALAAkJTBOBJAAeAgAAAA==.Zalanto:BAAALgAECgEJAgAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn8+AAITAAkJfhAwQQDTAQATAAkJfhAwQQDTAQAAAA==.',
Ze='Zelgaddis:BAABLgAECn8kAAMOAAkJiRP9OQC5AQAOAAgJYxP9OQC5AQAiAAIJTQR9PQAsAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn8oAAInAAcJdxCYPAAsAQAnAAcJdxCYPAAsAQAAAA==.',
Zr='Zriana:BAAALgAECgQJBgAAAA==.',
Zs='Zsarilya:BAABLgAECn8pAAIKAAgJVAJNQgDTAAAKAAgJVAJNQgDTAAAAAA==.',
Zu='Zurgen:BAABLgAECn89AAIEAAkJiyCYCwDsAgAEAAkJiyCYCwDsAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8xAAILAAgJghUmJwANAgALAAgJghUmJwANAgABLgAFFAUJEwAKABcQAA==.',
['Ýu']='Ýui:BAAALgADCgQJBAAAAA==.',
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
