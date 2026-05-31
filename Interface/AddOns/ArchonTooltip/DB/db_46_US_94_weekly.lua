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

local lookup = {'Paladin-Holy','Warrior-Fury','Warrior-Protection','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Priest-Discipline','Mage-Frost','Mage-Fire','Priest-Holy','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Hunter-BeastMastery','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Monk-Brewmaster','Hunter-Survival','Paladin-Protection','DemonHunter-Devourer','Druid-Balance','Monk-Windwalker','Monk-Mistweaver','Mage-Arcane','Druid-Guardian','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Evoker-Augmentation','Warrior-Arms',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aarchon:BAABLgAECn8lAAIBAAkJSh/vBwD5AgABAAkJSh/vBwD5AgAAAA==.',
Ad='Aduin:BAABLgAECn8VAAMCAAcJQxjvPAA8AQACAAcJQxDvPAA8AQADAAMJlx4bIgAGAQAAAA==.',
Ae='Aedarelyn:BAAALgAECgUJEAAAAA==.Aellet:BAABLgAECn8aAAMEAAkJ8xzWGgB2AgAEAAkJTRzWGgB2AgAFAAQJdx0aGAC6AAAAAA==.Aellita:BAAALgAECgQJCQAAAA==.Aeschylus:BAAALgAECgkJEQAAAA==.',
Ak='Akky:BAABLgAECn8lAAIDAAkJYiCZBQCqAgADAAkJYiCZBQCqAgAAAA==.Aksafiya:BAABLgAECn9OAAMGAAkJxhKAGQDdAQAGAAkJxhKAGQDdAQAHAAEJWAJ6eAAcAAAAAA==.',
Al='Alal:BAABLgAECn8WAAIIAAcJaQcquQD2AAAIAAcJaQcquQD2AAAAAA==.Alandras:BAABLgAECn8lAAICAAgJHwlaOwBDAQACAAgJHwlaOwBDAQAAAA==.Alaras:BAACLgAFFH8XAAIGAAYJgRDcDABwAQAGAAYJgRDcDABwAQAuAAQKfxcAAgYACQnQFQ8aAA8CAAYACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8rAAIFAAkJcxcjBgD9AQAFAAkJcxcjBgD9AQAAAA==.Allrianne:BAAALgAECgMJCgAAAA==.Allyriae:BAABLgAECn8VAAIJAAcJjAlrBwD/AAAJAAcJjAlrBwD/AAAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8gAAIKAAgJTx0JDQB9AgAKAAgJTx0JDQB9AgAAAA==.',
Am='Ambilena:BAABLgAECn8fAAMKAAgJ5xU6KQBoAQAKAAYJVhg6KQBoAQAGAAgJlQxjLABTAQAAAA==.',
An='Andoros:BAABLgAECn86AAILAAkJax7XDgDOAgALAAkJax7XDgDOAgAAAA==.Angiliana:BAABLgAECn8UAAIMAAUJAw+WNADIAAAMAAUJAw+WNADIAAAAAA==.Angvall:BAAALgAECgYJBwABLgAECgEJAQANAAAAAA==.Anzurath:BAABLgAECn8lAAIOAAkJrBSpTQDGAQAOAAkJrBSpTQDGAQAAAA==.',
Ap='Applebow:BAABLgAECn8lAAIPAAgJphHEHABXAQAPAAgJphHEHABXAQAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgAECgYJCAAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgYJCgAAAA==.Armas:BAAALgADCgQJBAAAAA==.Arylin:BAABLgAECn82AAIIAAkJlSPmBwArAwAIAAkJlSPmBwArAwAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEBLgAECn8aAAMDAAUJFxVoKADXAAADAAUJExRoKADXAAACAAEJtxVmoABBAAAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQANAAAAAA==.Asky:BAAALgADCgYJBwABLgAECgYJIAAIAPsBAA==.Asnabel:BAABLgAECn8fAAIQAAcJeQmSFgDzAAAQAAcJeQmSFgDzAAAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astrai:BAAALgADCgcJBwAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCgARAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgAECgMJAwAAAA==.Ayden:BAABLgAECn8WAAMMAAUJ+BoVIwA7AQAMAAUJ+BoVIwA7AQASAAEJkgqzMAAgAAAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwANAAAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgIJBAAAAA==.',
Bl='Blee:BAABLgAECn8rAAMHAAgJng83IQCgAQAHAAgJng83IQCgAQAGAAQJlgWRSgCwAAAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8lAAIEAAcJVh69MwD9AQAEAAcJVh69MwD9AQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8mAAITAAgJkiCpGgBwAgATAAgJkiCpGgBwAgAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8WAAIRAAYJOhFhsAD9AAARAAYJOhFhsAD9AAAAAA==.Brood:BAABLgAECn8rAAIRAAkJyBQ0RwDaAQARAAkJyBQ0RwDaAQAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAABLgAECn8dAAMUAAYJ2QWWWwC1AAAUAAYJ2QWWWwC1AAAVAAUJOQaeiACmAAAAAA==.',
Ca='Cailaranel:BAABLgAECn8oAAMWAAgJ+wjQDgAmAQAWAAcJaQnQDgAmAQAXAAgJYAX2LAAYAQAAAA==.Calaul:BAABLgAECn8YAAIOAAcJxg0ooQAaAQAOAAcJxg0ooQAaAQAAAA==.Calenbraga:BAABLgAECn8mAAIYAAYJSRZ7FQBIAQAYAAYJSRZ7FQBIAQAAAA==.Calisim:BAABLgAECn8ZAAIEAAUJdQdrxAC2AAAEAAUJdQdrxAC2AAAAAA==.Callidae:BAABLgAECn8qAAIKAAkJBxHPGADvAQAKAAkJBxHPGADvAQAAAA==.Calmnbald:BAABLgAECn8ZAAIZAAcJeBdjOAAKAQAZAAcJeBdjOAAKAQAAAA==.Caloh:BAAALgAECgQJBAAAAA==.Cantallbis:BAAALgADCgcJBwAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8lAAIaAAkJlgzmGQDBAQAaAAkJlgzmGQDBAQAAAA==.Cataryn:BAABLgAECn8iAAITAAkJNSRwDADcAgATAAkJNSRwDADcAgAAAA==.Catt:BAABLgAECn9DAAIBAAkJoBgaEwBiAgABAAkJoBgaEwBiAgAAAA==.',
Ce='Cellebur:BAABLgAECn8aAAITAAUJBwaLtQC2AAATAAUJBwaLtQC2AAAAAA==.Ceta:BAABLgAECn87AAIKAAkJDhx/CwCXAgAKAAkJDhx/CwCXAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAACLgAFFH8FAAMUAAMJWQuIPgBtAAAUAAIJ7QSIPgBtAAAVAAEJ8AHLcwAyAAAuAAQKfysAAxUACAncET43ALgBABUACAncET43ALgBABQABwm2GbYoAJABAAAA.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn87AAIIAAgJbwbbnwAgAQAIAAgJbwbbnwAgAQAAAA==.Cizean:BAABLgAECn8gAAIIAAYJ+wGSAwF+AAAIAAYJ+wGSAwF+AAAAAA==.',
Cr='Craivan:BAAALgAECgUJDwAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crilly:BAABLgAECn8rAAIIAAkJZRhSNAAvAgAIAAkJZRhSNAAvAgAAAA==.Crowe:BAAALgAECgUJCgABLgAECgUJBQANAAAAAA==.Crowley:BAAALgADCgMJAwAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAABLgAECn8VAAIVAAUJqAwLdADgAAAVAAUJqAwLdADgAAAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJDAAAAA==.Damia:BAABLgAECn8lAAMXAAgJRxnbEwDsAQAXAAgJRxnbEwDsAQAWAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8lAAIPAAkJ8CQXAwAGAwAPAAkJ8CQXAwAGAwAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgEJAgABLgAECgkJJQAPAPAkAA==.Delvarrieth:BAABLgAECn8gAAIbAAYJcBHjHwD7AAAbAAYJcBHjHwD7AAAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Denth:BAABLgAECn8aAAIOAAkJjA1PYwCQAQAOAAkJjA1PYwCQAQAAAA==.Dercuur:BAABLgAECn8cAAIUAAgJzBX4HwDKAQAUAAgJzBX4HwDKAQAAAA==.Devoursol:BAABLgAECn85AAMcAAkJlQxxTgCDAQAcAAkJaAxxTgCDAQAMAAIJrg45XABvAAAAAA==.',
Di='Dipndots:BAAALgAECgEJAQABLgAECgkJJQAPAPAkAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Doist:BAAALgAECgIJAgAAAA==.Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgAECgMJAwAAAA==.Drainmee:BAABLgAECn8VAAIHAAYJShIWLABSAQAHAAYJShIWLABSAQAAAA==.Draknol:BAAALgAECgEJAQAAAA==.Dregoth:BAABLgAECn8lAAIRAAkJkQf5cABuAQARAAkJkQf5cABuAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.Dretzerdor:BAAALgADCgkJCQABLgAECgUJCAANAAAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.',
Du='Durpee:BAABLgAECn8WAAMHAAYJBSSZDgBlAgAHAAYJBSSZDgBlAgAKAAIJOhSGawB9AAAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8gAAMLAAkJ4R5kEAC0AgALAAkJ4R5kEAC0AgAdAAEJxgnLigAnAAAAAA==.',
Ea='Eathur:BAAALgADCgcJDwAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elunariel:BAAALgAECgEJAgABLgAECgkJGgAEAPMcAA==.Elynth:BAABLgAECn8kAAIEAAkJURu5IgBJAgAEAAkJURu5IgBJAgAAAA==.',
En='Endlessyueh:BAABLgAECn8UAAMBAAYJNQW4VQDGAAABAAYJNQW4VQDGAAAOAAUJKA252wDEAAAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgkJGgAEAPMcAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAFFAQJBAABLgAFFAUJDAAOAHoOAA==.',
Fa='Face:BAAALgAECggJBgAAAA==.Faethian:BAACLgAFFH8SAAIbAAQJcCC1AgByAQAbAAQJcCC1AgByAQAuAAQKfywAAhsACAk7Jf0CANsCABsACAk7Jf0CANsCAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8sAAIIAAgJIAdXnAAmAQAIAAgJIAdXnAAmAQAAAA==.Fangren:BAABLgAECn8UAAITAAYJNA1niAAVAQATAAYJNA1niAAVAQAAAA==.Fariah:BAAALgAECgUJEwAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAABLgAECn8WAAIeAAYJVQiGSADHAAAeAAYJVQiGSADHAAAAAA==.',
Fe='Felscythe:BAABLgAECn8fAAIZAAYJpQGKXQCGAAAZAAYJpQGKXQCGAAAAAA==.Felynn:BAABLgAECn8rAAIBAAkJgxgVEwBiAgABAAkJgxgVEwBiAgAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feresdenn:BAAALgADCgQJBAAAAA==.Feyrha:BAAALgADCgYJBgABLgAECggJIQATAKoQAA==.',
Fi='Fiadh:BAAALgAECgQJBgAAAA==.Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8cAAIfAAYJJB0fIQDqAQAfAAYJJB0fIQDqAQAAAA==.',
Fl='Flaeli:BAABLgAECn8jAAIIAAgJGxawVADGAQAIAAgJGxawVADGAQAAAA==.Flemish:BAAALgAECgcJDAAAAA==.Flextame:BAAALgAECgQJDgAAAA==.Flipalicious:BAABLgAECn9AAAMVAAkJehzADgDGAgAVAAkJehzADgDGAgAUAAIJSxT8iwA9AAAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8dAAIGAAcJaBd5JQB/AQAGAAcJaBd5JQB/AQAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn8hAAITAAgJqhBwUQCVAQATAAgJqhBwUQCVAQAAAA==.Gangstafred:BAAALgADCgYJBgAAAA==.Gazo:BAAALgAECgYJBgABLgAECgkJKwAeADsfAA==.',
Ge='Gemboss:BAABLgAECn9FAAMOAAgJ+yAKHgB6AgAOAAgJ+yAKHgB6AgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8uAAMIAAkJmxMaVgDCAQAIAAkJmxMaVgDCAQAgAAMJoAbAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8tAAIeAAkJkQm3KABaAQAeAAkJkQm3KABaAQAAAA==.Ginodh:BAABLgAECn8OAAIcAAgJtQ3pbQAsAQAcAAgJtQ3pbQAsAQABLgAECgkJGQAPAPwNAA==.Ginomage:BAAALgAECgcJCgABLgAECgkJGQAPAPwNAA==.Ginomonk:BAAALgAECgYJBgABLgAECgkJGQAPAPwNAA==.Ginopally:BAAALgAECgYJCwABLgAECgkJGQAPAPwNAA==.Girth:BAAALgADCgIJAgAAAA==.Gizelli:BAAALgAFFAEJAQAAAA==.',
Gl='Glorby:BAAALgAECgQJBAABLgAFFAIJBQAfAGMXAA==.',
Go='Gordonn:BAAALgAECgQJBAAAAA==.',
Gr='Groblock:BAAALgADCgYJDAAAAA==.Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAfAGMXAA==.Grubetsella:BAACLgAFFH8FAAIfAAIJYxduDwClAAAfAAIJYxduDwClAAAuAAQKfy8AAh8ACAlCIiwLAMYCAB8ACAlCIiwLAMYCAAAA.Grumpÿ:BAAALgADCgYJBgAAAA==.',
Gu='Guenhywvar:BAABLgAECn8XAAIcAAYJXBvFUAC0AQAcAAYJXBvFUAC0AQAAAA==.Gumpers:BAABLgAECn8mAAIhAAkJtA71GQBaAQAhAAkJtA71GQBaAQAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAAALgAECgUJDgAAAA==.',
Ha='Halfamazing:BAAALgAECgQJBQAAAA==.Hanoumatoi:BAAALgAECgUJBQAAAA==.Haralambos:BAABLgAECn8aAAIbAAUJwBKRJADUAAAbAAUJwBKRJADUAAAAAA==.Haralogain:BAAALgAECgEJAQABLgAECgUJGgAbAMASAA==.Harithon:BAABLgAECn8nAAIiAAkJHyDSAwCrAgAiAAkJHyDSAwCrAgAAAA==.Harlar:BAAALgAECgEJAQAAAA==.Havvöc:BAABLgAECn8sAAIBAAkJoByGCgDPAgABAAkJoByGCgDPAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAABLgAECn8jAAIDAAgJxAPAJwDcAAADAAgJxAPAJwDcAAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAABLgAECn8aAAIIAAYJPgl4ygDaAAAIAAYJPgl4ygDaAAAAAA==.Heyokagi:BAABLgAECn8vAAQYAAkJNyKgAQAVAwAYAAkJNyKgAQAVAwAhAAIJ1BS5JgBnAAALAAEJXwibygAsAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgkJGgAEAPMcAA==.Hordkilla:BAABLgAECn8oAAIOAAgJnAa3rgAFAQAOAAgJnAa3rgAFAQAAAA==.Hottdealer:BAAALgADCgUJBQAAAA==.Hownowbrncw:BAABLgAECn8fAAIOAAcJxhuOTwDBAQAOAAcJxhuOTwDBAQAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn82AAMcAAkJ2BxPEwCUAgAcAAkJ2BxPEwCUAgASAAEJphqdKABLAAAAAA==.Hylda:BAAALgADCgUJBQAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAAALgAECgUJCwAAAA==.',
Im='Imathdal:BAABLgAECn8lAAIjAAkJrw6mCwCWAQAjAAkJrw6mCwCWAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQANAAAAAA==.Insoniacyun:BAABLgAECn8UAAIIAAgJHQlRiABLAQAIAAgJHQlRiABLAQAAAA==.',
Is='Iselian:BAAALgAECgkJIQAAAQ==.Ishanu:BAABLgAECn8aAAIGAAkJIhw4DQBlAgAGAAkJIhw4DQBlAgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQANAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgADCgkJGgABLgADCggJDgANAAAAAA==.Jax:BAACLgAFFH8NAAIIAAQJRCJJOQBeAQAIAAQJRCJJOQBeAQAuAAQKfykAAggACAlFIxATADUDAAgACAlFIxATADUDAAAA.',
Jb='Jblockiv:BAAALgADCgcJDAAAAA==.Jbprimero:BAAALgADCgUJBQAAAA==.Jbshami:BAABLgAECn8xAAMVAAcJFSATGABwAgAVAAcJFSATGABwAgAUAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgUJBgAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn89AAIgAAkJWg66AwC/AQAgAAkJWg66AwC/AQAAAA==.Jetfires:BAABLgAECn9CAAITAAkJUR4ZDwDEAgATAAkJUR4ZDwDEAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAABLgAECn8aAAIeAAYJtwX4UACtAAAeAAYJtwX4UACtAAAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jovie:BAAALgAECgEJAQAAAA==.Jozhua:BAAALgAECgYJCwAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.Jungg:BAAALgAECgIJAgAAAA==.',
Ka='Kaedren:BAAALgAECgMJAwAAAA==.Kaelaya:BAABLgAECn8aAAIjAAYJgwpiGQDRAAAjAAYJgwpiGQDRAAAAAA==.Kaelorien:BAABLgAECn89AAIfAAkJKRItIADxAQAfAAkJKRItIADxAQAAAA==.Kaetta:BAABLgAECn8XAAIIAAgJ0AMPuAD4AAAIAAgJ0AMPuAD4AAAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgYJDgAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAAALgAECgYJDAAAAA==.Kaldevayn:BAAALgAECgYJDQAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgQJBgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8jAAIcAAYJsAwvkADhAAAcAAYJsAwvkADhAAAAAA==.Kandandris:BAAALgADCgMJAwAAAA==.Kardanis:BAABLgAECn8kAAIVAAkJviSvAQCoAwAVAAkJviSvAQCoAwAAAA==.Kashe:BAABLgAECn8YAAIBAAUJox3lKwCdAQABAAUJox3lKwCdAQAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAABLgAECn8lAAIVAAkJZxJrNQDAAQAVAAkJZxJrNQDAAQAAAA==.Kaydencia:BAABLgAECn8XAAIOAAYJvxHGuwDxAAAOAAYJvxHGuwDxAAAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgQJBgAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgAECgEJAQAAAA==.',
Ki='Ki:BAAALgAECgQJBAAAAA==.Kiddow:BAAALgAECgUJEgAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgADCgkJDgAAAA==.Kiri:BAAALgADCgkJEQAAAA==.Kitamii:BAABLgAECn8UAAIYAAYJdRbHEQCQAQAYAAYJdRbHEQCQAQAAAA==.Kivrin:BAAALgAECgUJDAAAAA==.',
Kr='Kringlë:BAABLgAECn8mAAITAAkJ3SAmEwCjAgATAAkJ3SAmEwCjAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kushwizard:BAAALgADCgQJBQAAAA==.Kuunko:BAAALgAECgEJAQAAAA==.',
Ky='Kymma:BAABLgAECn8sAAIOAAgJBw5YggBPAQAOAAgJBw5YggBPAQAAAA==.Kyunix:BAAALgADCgYJDAAAAA==.',
La='Lagoriatsua:BAABLgAECn8YAAIUAAgJYgadSQDyAAAUAAgJYgadSQDyAAAAAA==.Laitue:BAAALgAECgQJDAAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgIJAwAAAA==.Lazengann:BAABLgAECn8kAAMcAAkJGxUCNgDXAQAcAAkJwBQCNgDXAQAMAAEJvxboagA7AAAAAA==.',
Le='Leafbane:BAAALgADCgEJAQAAAA==.Leagann:BAAALgAECgEJAQAAAA==.Legevia:BAABLgAECn8ZAAMiAAYJ5wYXJgCWAAAiAAUJQgUXJgCWAAAVAAIJkgL+uAA8AAAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAABLgAECn88AAIOAAkJDRFuTgDEAQAOAAkJDRFuTgDEAQAAAA==.Leisha:BAAALgADCgEJAQAAAA==.Letifer:BAAALgADCgkJDAAAAA==.Leucetios:BAAALgAECgMJAwAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8bAAIKAAkJPhmJDACFAgAKAAkJPhmJDACFAgAAAA==.Lightbeard:BAABLgAECn8dAAQBAAUJoR4vKQCtAQABAAUJoR4vKQCtAQAbAAEJ4A9xSwApAAAOAAEJRwMOlwEjAAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAABLgAECn8WAAIOAAgJ7RieYwCPAQAOAAgJ7RieYwCPAQAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgAECgMJAwAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lorredain:BAAALgAECgMJAwAAAA==.Lothwen:BAAALgAECgYJCAAAAA==.Louisachan:BAAALgADCgUJBQAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8RAAIKAAUJFxBqDwA0AQAKAAUJFxBqDwA0AQAuAAQKfyoAAgoACQmSFJMsAJQBAAoACQmSFJMsAJQBAAAA.Luxinine:BAABLgAECn8YAAIGAAcJPB33GgDRAQAGAAcJPB33GgDRAQAAAA==.',
Ly='Lyon:BAAALgADCgMJCgAAAA==.Lyshai:BAAALgAECgYJBgABLgAECgYJGgAkAOQfAA==.',
Ma='Magamon:BAABLgAECn8mAAIIAAkJBRcNPgAMAgAIAAkJBRcNPgAMAgAAAA==.Magamus:BAAALgADCgYJBgAAAA==.Mahndarb:BAAALgAECgMJBgABLgAECggJIAAKAE8dAA==.Majima:BAAALgAECgYJDgAAAA==.Malfuriia:BAABLgAECn8gAAIVAAYJLRvDMADXAQAVAAYJLRvDMADXAQAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Mamboke:BAAALgADCgEJAQAAAA==.Margerdria:BAABLgAECn8VAAIGAAUJDQ3dSQDAAAAGAAUJDQ3dSQDAAAAAAA==.Maskelle:BAABLgAECn8lAAISAAgJoBEcDQBoAQASAAgJoBEcDQBoAQAAAA==.Mauugrim:BAABLgAECn8hAAIRAAgJRwfviAA+AQARAAgJRwfviAA+AQAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAABLgAECn8YAAIOAAYJ9BaofQBYAQAOAAYJ9BaofQBYAQAAAA==.',
Me='Mearadan:BAAALgAECgkJDwAAAA==.Meatsweats:BAABLgAECn8YAAIOAAcJ7whgsAACAQAOAAcJ7whgsAACAQAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDwAAAA==.Mekh:BAABLgAECn8aAAMkAAYJ5B+0BgDHAQAkAAYJ5B+0BgDHAQAlAAEJVQjQSwAqAAAAAA==.Mel:BAAALgAECgMJCgAAAA==.Melanara:BAABLgAECn89AAIIAAkJbgwYXQCvAQAIAAkJbgwYXQCvAQAAAA==.Melstrom:BAAALgAECgYJCAAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgYJBwAAAA==.Meticuluslyn:BAAALgADCgcJDgAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAABLgAECn8UAAIgAAkJBRNDAwDhAQAgAAkJBRNDAwDhAQAAAA==.Miyävii:BAABLgAECn8YAAIbAAkJxxObFABrAQAbAAkJxxObFABrAQAAAA==.',
Mj='Mjsage:BAABLgAECn8iAAITAAkJCB4gHgBbAgATAAkJCB4gHgBbAgAAAA==.',
Mm='Mmeow:BAAALgAECgQJBQAAAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8bAAIGAAYJFRocJgB6AQAGAAYJFRocJgB6AQAAAA==.Mooasha:BAAALgAECgEJAQABLgAECgkJJQAVAGcSAA==.Moonflowers:BAACLgAFFH8cAAILAAYJmh4uCABAAgALAAYJmh4uCABAAgAuAAQKfy8AAgsACAmcJMUHAC0DAAsACAmcJMUHAC0DAAAA.Mordsevoker:BAAALgAFFAIJAgABLgAFFAUJFQARAFwSAA==.Morginoth:BAAALgADCgcJBwAAAA==.Mousekee:BAABLgAECn8hAAIKAAgJKgo/LgBEAQAKAAgJKgo/LgBEAQAAAA==.',
Mu='Murdrmitts:BAABLgAECn8bAAIYAAgJJQx9FwAxAQAYAAgJJQx9FwAxAQAAAA==.Mustikka:BAABLgAECn8ZAAIYAAUJJg/CIwDEAAAYAAUJJg/CIwDEAAAAAA==.',
My='Myuriyanka:BAABLgAECn8pAAMUAAkJphPEHwDLAQAUAAkJphPEHwDLAQAVAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgYJBwANAAAAAA==.',
Na='Naahommii:BAABLgAECn8eAAITAAgJrRbpSACvAQATAAgJrRbpSACvAQAAAA==.Nachtpranke:BAABLgAECn8XAAILAAgJ6R7WFQCHAgALAAgJ6R7WFQCHAgAAAA==.Nadron:BAAALgAECgMJBQAAAA==.Naevala:BAAALgAECgkJAwAAAA==.Nagualli:BAAALgAECgEJAQAAAA==.',
Ne='Negargra:BAABLgAECn8kAAMEAAYJ5w9DnAD7AAAEAAYJ5w9DnAD7AAAmAAEJcgMufAAkAAAAAA==.Nephadin:BAAALgAECgcJEAAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgYJDgAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAABLgAECn8YAAILAAUJ/AoqeAC9AAALAAUJ/AoqeAC9AAAAAA==.Nikooli:BAAALgAECgYJEgAAAA==.Nimb:BAAALgAECgEJAgAAAA==.Nitaya:BAAALgAECgEJAQAAAA==.',
No='Nokkoh:BAAALgADCgQJBAAAAA==.Nolime:BAAALgAECgYJBwAAAA==.Noodledragon:BAAALgAECgYJBgAAAA==.Noopsie:BAABLgAECn8kAAILAAYJTQwOYwD6AAALAAYJTQwOYwD6AAAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAcJIAAlAIYQAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMHAAgJxho+FAAcAgAHAAcJLhw+FAAcAgAGAAcJsBzGJwBvAQAAAA==.Notpeepuddle:BAAALgAECgEJAQAAAA==.Novarox:BAAALgAECgEJAQAAAA==.',
Nu='Nuhnoo:BAAALgADCgkJCQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8fAAIOAAYJwBxZWgClAQAOAAYJwBxZWgClAQAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMgAAkJbgM/EgCgAAAIAAkJWQP21ADKAAAgAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBAAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCggJDwAAAA==.Olympia:BAABLgAECn8pAAIbAAkJXQ0HGgAvAQAbAAkJXQ0HGgAvAQAAAA==.',
Or='Oraclemega:BAABLgAECn8rAAIIAAkJyBsEGgCoAgAIAAkJyBsEGgCoAgAAAA==.Orweyna:BAAALgAECgcJBwAAAA==.',
Os='Oscarmikey:BAACLgAFFH8YAAMLAAUJDQvqHwA8AQALAAUJDQvqHwA8AQAdAAEJhAHHRwAqAAAuAAQKfywABQsACQmSGZEXAHYCAAsACQmSGZEXAHYCAB0ABAnrDcxfAHoAABgAAQlMAiFQACEAACEAAQkAACF6AAAAAAAA.Oshu:BAAALgADCgcJCAAAAA==.',
Ot='Ottoshot:BAABLgAECn8gAAITAAYJZBKIcgBCAQATAAYJZBKIcgBCAQAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
['Oö']='Oöps:BAAALgAECgUJCQAAAA==.',
Pa='Panamone:BAABLgAECn8fAAMYAAYJuyQCCQAYAgAYAAYJuyQCCQAYAgALAAEJfxStuwA9AAAAAA==.Pandeism:BAABLgAECn8hAAMVAAcJdRiuPACfAQAVAAYJiReuPACfAQAiAAYJbRMkGAAhAQAAAA==.Papagrip:BAABLgAECn8tAAMQAAkJDxIrCgCvAQAQAAkJDxIrCgCvAQARAAgJeQklkwAsAQAAAA==.Patrin:BAABLgAECn8fAAIIAAgJDQuciwBFAQAIAAgJDQuciwBFAQAAAA==.Paulee:BAAALgADCgkJCwAAAA==.',
Pe='Peanutbritle:BAABLgAECn8mAAIPAAkJWQbNKAD3AAAPAAkJWQbNKAD3AAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.Pesch:BAAALgAECgkJEwAAAA==.',
Ph='Phantdoom:BAAALgAECgYJEQAAAA==.Phylah:BAAALgAECgMJAwAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAFFAIJBAANAAAAAA==.',
Pl='Plsdiddyno:BAAALgAFFAEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgMJBgAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Puchi:BAAALgAECgUJBQAAAA==.Punchabaal:BAAALgAECgcJDAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAILAAcJWRnvMwDZAQALAAcJWRnvMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgQJBAAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAUJHgAJAJ0lAA==.Reyrocko:BAAALgAECgQJBAAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAQJDQAGABsdAA==.Rezhunt:BAAALgAECgkJDgABLgAFFAQJDQAGABsdAA==.Rezshift:BAABLgAECn8bAAMdAAgJwhyQEwAiAgAdAAgJwhyQEwAiAgALAAQJBRbtbwAFAQABLgAFFAQJDQAGABsdAA==.Rezvoid:BAACLgAFFH8NAAMGAAQJGx0xEABNAQAGAAQJGx0xEABNAQAKAAIJgyFhHQCqAAAuAAQKfzIAAgYACQkQI30FAOUCAAYACQkQI30FAOUCAAAA.',
Rh='Rhage:BAAALgAECgMJBwAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAABLgAECn8XAAIRAAcJlRKcjwAyAQARAAcJlRKcjwAyAQAAAA==.Roxane:BAABLgAECn8lAAIdAAkJxQmtKgBjAQAdAAkJxQmtKgBjAQAAAA==.',
Ru='Runningelk:BAABLgAECn8xAAIhAAkJvBLqEQCsAQAhAAkJvBLqEQCsAQAAAA==.Runscapemain:BAABLgAECn8jAAIOAAkJvRX8TADIAQAOAAkJvRX8TADIAQAAAA==.',
Ry='Ryeti:BAAALgADCgkJDgAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDgAMAAEkAA==.',
Sa='Saintulrick:BAAALgAECgEJAQAAAA==.Sajuice:BAACLgAFFH8HAAIjAAUJPwXGFQDfAAAjAAUJPwXGFQDfAAAuAAQKfyYAAiMACAnAG+gIANYBACMACAnAG+gIANYBAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn8eAAMKAAgJvwoQLwA+AQAKAAgJvwoQLwA+AQAGAAEJmAOYhAAjAAAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgANAAAAAA==.',
Se='Seeyen:BAACLgAFFH8TAAITAAUJGBcCLwA4AQATAAUJGBcCLwA4AQAuAAQKfyoAAhMACQmQHgUHAB8DABMACQmQHgUHAB8DAAAA.Selfdestruct:BAAALgADCgcJBwAAAA==.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8gAAIkAAkJiAl/CQB8AQAkAAkJiAl/CQB8AQAAAA==.Seren:BAAALgAFFAEJAgABLgAFFAcJEgAIAGUIAA==.Serenityhate:BAABLgAECn8UAAIKAAYJUwmXPQDlAAAKAAYJUwmXPQDlAAAAAA==.',
Sh='Shaaydo:BAAALgAECgEJAQAAAA==.Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgYJBgAAAA==.Shandrilyn:BAABLgAECn8XAAIGAAcJIATISgC9AAAGAAcJIATISgC9AAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAIlAAkJwBShFgBRAQAlAAkJwBShFgBRAQAAAA==.',
Si='Sini:BAAALgAFFAcJBAAAAA==.Sinthoras:BAAALgAECgQJBAAAAA==.',
Sj='Sjðfn:BAAALgAECgkJAgAAAA==.',
Sk='Skala:BAABLgAECn8XAAInAAkJThbnGQDtAQAnAAkJThbnGQDtAQAAAA==.Skibbie:BAACLgAFFH8XAAMkAAYJFwzEBAAXAQAnAAYJpAsXHgA4AQAkAAQJygjEBAAXAQAuAAQKfx4ABCcACQk4GF8QAHMCACcACQk4GF8QAHMCACQABQnOBpAsALcAACUABAmHDhokALcAAAAA.Skibbward:BAABLgAECn8zAAQhAAgJTiS4AQAyAwAhAAgJTiS4AQAyAwAdAAUJxQ9jVADUAAALAAYJ6QrsggDSAAABLgAFFAYJFwAkABcMAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAAALgAECgcJDwAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgEJAwABLgAECgIJBgANAAAAAA==.',
Sm='Smackdogg:BAABLgAECn8ZAAIdAAcJPR0XHQAYAgAdAAcJPR0XHQAYAgABLgAFFAgJKwAUAGkdAA==.',
So='Solteria:BAABLgAECn8VAAIFAAcJqAk/DgBOAQAFAAcJqAk/DgBOAQABLgAECgkJAgANAAAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAAALgAECgYJEwAAAA==.Sorvina:BAABLgAECn84AAIEAAkJdBJzOQDnAQAEAAkJdBJzOQDnAQAAAA==.Soulflame:BAABLgAECn9AAAIIAAkJHBCCSADqAQAIAAkJHBCCSADqAQAAAA==.Soulshifter:BAABLgAECn8XAAIdAAYJWgtcSADOAAAdAAYJWgtcSADOAAAAAA==.Soultrader:BAAALgADCgkJFwABLgAECgUJGgAbAMASAA==.',
Sp='Spooñ:BAAALgADCgcJBwABLgAFFAUJFgAfAEocAA==.Spottedcoat:BAABLgAECn8mAAILAAkJZgOBdgDBAAALAAkJZgOBdgDBAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgAAAA==.Strangerx:BAAALgAECgEJAQAAAA==.Stregnor:BAABLgAECn88AAITAAkJBBivHgBYAgATAAkJBBivHgBYAgAAAA==.Styggi:BAAALgAECgEJAQAAAA==.Stygy:BAAALgAECgMJAwAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDgAMAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn82AAMeAAgJuBU9HAC0AQAeAAgJuBU9HAC0AQAZAAQJ7QqMZQCrAAAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMnAAkJDxKrEwBHAgAnAAkJfhGrEwBHAgAkAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECgkJJAAnAB4bAA==.Tachie:BAABLgAECn8kAAMnAAkJHhukDQBtAgAnAAkJuBqkDQBtAgAkAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAYJGAAFABYmAA==.Taele:BAABLgAECn8tAAMIAAkJTxySIgB9AgAIAAkJtBuSIgB9AgAgAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn8zAAIdAAkJ9AyNKAByAQAdAAkJ9AyNKAByAQAAAA==.Tamalpais:BAABLgAECn8VAAITAAUJAQ02owDdAAATAAUJAQ02owDdAAAAAA==.Tamarind:BAAALgAECgYJBgABLgAECgkJJwAiAB8gAA==.Tanya:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8gAAITAAYJtwMTrADKAAATAAYJtwMTrADKAAAAAA==.',
Th='Thaesan:BAAALgAECgUJCQAAAA==.Therin:BAABLgAECn8wAAIaAAkJHRWaEAAcAgAaAAkJHRWaEAAcAgAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tillymonick:BAAALgAECgUJBQAAAA==.Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgYJEQAAAA==.Toofast:BAABLgAECn8qAAIVAAgJ9iDdCgDzAgAVAAgJ9iDdCgDzAgAAAA==.Toofurrious:BAAALgADCgkJMQAAAA==.Topswimmer:BAABLgAECn8UAAIIAAcJZhSIcAB/AQAIAAcJZhSIcAB/AQAAAA==.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgUJBgAAAA==.',
Tr='Traci:BAAALgADCgUJBQAAAA==.Trifus:BAABLgAECn8dAAMRAAkJOBS2ZwCDAQARAAcJ/gy2ZwCDAQAPAAcJOxSKHQBQAQAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAABLgAECn8UAAILAAUJiB32NwClAQALAAUJiB32NwClAQAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.',
Tu='Tulao:BAABLgAECn8nAAIIAAcJQRhIUgDNAQAIAAcJQRhIUgDNAQAAAA==.',
Tw='Twan:BAAALgAECgYJBwABLgAFFAYJEQAcANkYAA==.',
Ty='Tyledoriel:BAAALgADCgEJAQAAAA==.Tyrionel:BAAALgAECgUJCgAAAA==.',
Tz='Tzitzimitl:BAAALgAECgEJAQAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIfAAQJaRA2JwDiAAAfAAQJaRA2JwDiAAAAAA==.',
Ut='Utheli:BAACLgAFFH8MAAIOAAMJ9BHYWADcAAAOAAMJ9BHYWADcAAAuAAQKfx4AAg4ACAkBG6xFAN0BAA4ACAkBG6xFAN0BAAAA.',
Va='Vaevictis:BAAALgAECgQJBAABLgAECgcJHQAGAGgXAA==.Vaildora:BAAALgAECgEJAQABLgAECgkJJAAnAB4bAA==.Valdra:BAABLgAECn89AAIDAAkJGRMvEADNAQADAAkJGRMvEADNAQAAAA==.',
Vi='Vidiablade:BAAALgAFFAIJAgAAAA==.Viralprepped:BAAALgAECgMJCgAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8fAAMcAAkJ6w7hRgCaAQAcAAkJ6w7hRgCaAQAMAAYJEg7KLQDwAAAAAA==.',
Vn='Vnasty:BAACLgAFFH8MAAIOAAUJeg5IQAAUAQAOAAUJeg5IQAAUAQAuAAQKfywAAg4ACQkrICkKAD8DAA4ACQkrICkKAD8DAAAA.',
Vr='Vrale:BAAALgAECgkJDgAAAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wildbear:BAAALgADCgMJAwAAAA==.Wilken:BAABLgAECn8sAAIoAAkJ9BdFCABWAgAoAAkJ9BdFCABWAgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8lAAIOAAkJ/xo1KgBAAgAOAAkJ/xo1KgBAAgAAAA==.',
Ws='Wspr:BAAALgAECgIJBgAAAA==.',
Wu='Wulff:BAAALgADCgMJBgAAAA==.',
Xa='Xaartahli:BAAALgAECgQJBwAAAA==.Xavencia:BAAALgAECgYJDwAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECgIJAgAAAA==.',
Ya='Yanut:BAAALgAECgYJDwAAAA==.',
Ye='Yeetjin:BAAALgAECgMJAgAAAA==.',
Yi='Yinamin:BAAALgAECgYJEgAAAA==.',
Yk='Yknub:BAAALgADCgYJCQAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAABLgAECn8dAAILAAcJvxY0LwDUAQALAAcJvxY0LwDUAQAAAA==.Zalanto:BAAALgAECgEJAQAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn8+AAITAAkJfhAbPADYAQATAAkJfhAbPADYAQAAAA==.',
Ze='Zelgaddis:BAABLgAECn8kAAMVAAkJiRO0NgC6AQAVAAgJYxO0NgC6AQAiAAIJTQQpOAAsAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn8hAAInAAcJdw99OwAcAQAnAAcJdw99OwAcAQAAAA==.',
Zr='Zriana:BAAALgAECgEJAwAAAA==.',
Zs='Zsarilya:BAABLgAECn8lAAIKAAgJVALGPgDeAAAKAAgJVALGPgDeAAAAAA==.',
Zu='Zurgen:BAABLgAECn89AAIEAAkJiyBVCgDyAgAEAAkJiyBVCgDyAgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8tAAILAAgJyBEVMwC+AQALAAgJyBEVMwC+AQABLgAFFAUJEQAKABcQAA==.',
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
