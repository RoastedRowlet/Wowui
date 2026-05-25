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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Priest-Shadow','Priest-Discipline','Warrior-Fury','Mage-Fire','Priest-Holy','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Hunter-BeastMastery','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Monk-Brewmaster','Hunter-Survival','Paladin-Protection','DemonHunter-Devourer','Druid-Balance','Monk-Mistweaver','Monk-Windwalker','Mage-Arcane','Druid-Guardian','Shaman-Enhancement','DemonHunter-Vengeance','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Evoker-Augmentation','Warrior-Arms',}
local provider = {region='US',realm='Feathermoon',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aarchon:BAABLgAECn8lAAIBAAkJSh/JBgD+AgABAAkJSh/JBgD+AgAAAA==.',
Ad='Aduin:BAAALgAECgcJEgAAAA==.',
Ae='Aedarelyn:BAAALgAECgQJCwAAAA==.Aellet:BAABLgAECn8aAAMCAAkJ8xy5FwB9AgACAAkJTRy5FwB9AgADAAQJdx0aGAC6AAAAAA==.Aellita:BAAALgAECgMJBQAAAA==.Aeschylus:BAAALgAECgkJEQAAAA==.',
Ak='Akky:BAABLgAECn8lAAIEAAkJYiC6BAC3AgAEAAkJYiC6BAC3AgAAAA==.Aksafiya:BAABLgAECn9FAAMFAAkJxhIlFwDrAQAFAAkJxhIlFwDrAQAGAAEJWAJ5bwAcAAAAAA==.',
Al='Alal:BAAALgAECgYJEwAAAA==.Alandras:BAABLgAECn8hAAIHAAgJTgg0QAAbAQAHAAgJTgg0QAAbAQAAAA==.Alaras:BAACLgAFFH8VAAIFAAUJiBCIEwAvAQAFAAUJiBCIEwAvAQAuAAQKfxcAAgUACQnQFQ8aAA8CAAUACQnQFQ8aAA8CAAAA.Alexeldin:BAAALgADCggJBgAAAA==.Allistair:BAABLgAECn8iAAIDAAgJcRe5CQCRAQADAAgJcRe5CQCRAQAAAA==.Allrianne:BAAALgAECgMJBwAAAA==.Allyriae:BAABLgAECn8VAAIIAAcJjAljBgAQAQAIAAcJjAljBgAQAQAAAA==.Alstrumeria:BAAALgADCgEJAQAAAA==.Althoraty:BAABLgAECn8ZAAIJAAgJbBDuMQB5AQAJAAgJbBDuMQB5AQAAAA==.',
Am='Ambilena:BAABLgAECn8bAAMJAAgJ3BRvJgBvAQAJAAYJVhhvJgBvAQAFAAgJ1AlHLABLAQAAAA==.',
An='Andoros:BAABLgAECn86AAIKAAkJax50DQDQAgAKAAkJax50DQDQAgAAAA==.Angiliana:BAABLgAECn8UAAILAAUJAw/uLwDLAAALAAUJAw/uLwDLAAAAAA==.Angvall:BAAALgAECgYJBwABLgAECgEJAQAMAAAAAA==.Anzurath:BAABLgAECn8kAAINAAkJrBSCQQDjAQANAAkJrBSCQQDjAQAAAA==.',
Ap='Applebow:BAABLgAECn8hAAIOAAgJphEMGgBcAQAOAAgJphEMGgBcAQAAAA==.',
Ar='Aranus:BAAALgADCgcJEgAAAA==.Archee:BAAALgADCgYJCAAAAA==.Ardiand:BAAALgAECgIJAgAAAA==.Areyah:BAAALgADCggJDwAAAA==.Arknova:BAAALgAECgMJAwAAAA==.Armas:BAAALgADCgQJBAAAAA==.Arylin:BAABLgAECn8tAAIPAAkJLCPcCAAgAwAPAAkJLCPcCAAgAwAAAA==.',
As='Asheerr:BAAALgAECgMJBAAAAA==.Ashkinassi:BAEBLgAECn8VAAMEAAUJehSrJgDUAAAEAAUJdhOrJgDUAAAHAAEJtxVmoABBAAAAAA==.Asiain:BAAALgADCgEJAQAAAA==.Asir:BAAALgADCgMJBAABLgADCgkJEQAMAAAAAA==.Asky:BAAALgADCgYJBwABLgAECgYJGgAPAOEBAA==.Asnabel:BAABLgAECn8YAAIQAAcJpAhBFAD0AAAQAAcJpAhBFAD0AAAAAA==.Aspirate:BAAALgADCgcJCgAAAA==.Astralspirit:BAAALgADCgYJBgABLgAFFAMJCQARAD0lAA==.',
Au='Aurorablade:BAAALgADCgkJDgAAAA==.',
Ay='Ayambe:BAAALgADCgkJHwAAAA==.Ayden:BAAALgAECgUJEQAAAA==.',
Az='Azabaal:BAAALgADCgYJBgAAAA==.Azesher:BAAALgADCgcJEgAAAA==.Azt:BAAALgAECgUJBQAAAA==.',
Ba='Babybox:BAAALgAECgYJDwAAAA==.Bahdeka:BAAALgADCgQJBQABLgADCgYJBwAMAAAAAA==.Baphie:BAAALgAECgEJAgAAAA==.',
Be='Belixe:BAAALgADCgEJBAAAAA==.',
Bh='Bhairavi:BAAALgAECgUJBQAAAA==.',
Bi='Bibimbap:BAAALgAECgIJAwAAAA==.',
Bl='Blee:BAABLgAECn8rAAMGAAgJng8YHgCuAQAGAAgJng8YHgCuAQAFAAQJlgWRSgCwAAAAAA==.Blueberrys:BAAALgAECgEJAQAAAA==.',
Bo='Boltsnhoes:BAABLgAECn8jAAICAAYJTB7oSQCmAQACAAYJTB7oSQCmAQAAAA==.Bonii:BAAALgADCgkJEQAAAA==.Boomhauer:BAABLgAECn8iAAISAAgJDB/KGQBjAgASAAgJDB/KGQBjAgAAAA==.Botsugo:BAAALgAECgMJAwAAAA==.',
Br='Braelia:BAABLgAECn8WAAIRAAYJOhHbowD+AAARAAYJOhHbowD+AAAAAA==.Brood:BAABLgAECn8rAAIRAAkJyBQOQQDeAQARAAkJyBQOQQDeAQAAAA==.Brøly:BAAALgADCgUJBQAAAA==.',
Bu='Bubblepopper:BAAALgADCgQJBgAAAA==.Bunky:BAABLgAECn8XAAMTAAYJowRYWgClAAATAAYJowRYWgClAAAUAAUJ5AT0ggCYAAAAAA==.',
Ca='Cailaranel:BAABLgAECn8oAAMVAAgJ+wjPDQArAQAVAAcJaQnPDQArAQAWAAgJYAUXKQAgAQAAAA==.Calaul:BAABLgAECn8XAAINAAYJ0Q/JpAAOAQANAAYJ0Q/JpAAOAQAAAA==.Calenbraga:BAABLgAECn8YAAIXAAUJQhU4GwD3AAAXAAUJQhU4GwD3AAAAAA==.Calisim:BAABLgAECn8UAAICAAUJkwUvxACnAAACAAUJkwUvxACnAAAAAA==.Callidae:BAABLgAECn8qAAIJAAkJBxGVFgD1AQAJAAkJBxGVFgD1AQAAAA==.Calmnbald:BAABLgAECn8ZAAIYAAcJeBctNQAMAQAYAAcJeBctNQAMAQAAAA==.Caloh:BAAALgAECgQJBAAAAA==.Cantoria:BAAALgADCgcJCwAAAA==.Carbonn:BAAALgADCgYJCQAAAA==.Cassamaria:BAABLgAECn8iAAIZAAgJUw2WJQBPAQAZAAgJUw2WJQBPAQAAAA==.Cataryn:BAABLgAECn8hAAISAAkJNSTwCQDmAgASAAkJNSTwCQDmAgAAAA==.Catt:BAABLgAECn86AAIBAAkJqBc4EgBdAgABAAkJqBc4EgBdAgAAAA==.',
Ce='Cellebur:BAABLgAECn8VAAISAAUJswVoqgCxAAASAAUJswVoqgCxAAAAAA==.Ceta:BAABLgAECn8yAAIJAAkJphpaDQBoAgAJAAkJphpaDQBoAgAAAA==.',
Ch='Chalfus:BAAALgADCgYJBQAAAA==.Chaotichealz:BAABLgAECn8rAAMUAAgJ3BFzMgC6AQAUAAgJ3BFzMgC6AQATAAcJthkHJQCTAQAAAA==.Charliesheen:BAAALgAECgkJBQAAAA==.Chubbyhunter:BAAALgAECgQJCAAAAA==.',
Ci='Cinamen:BAABLgAECn8uAAIPAAgJRwVMmgAqAQAPAAgJRwVMmgAqAQAAAA==.Cizean:BAABLgAECn8aAAIPAAYJ4QFn9gCNAAAPAAYJ4QFn9gCNAAAAAA==.',
Cr='Craivan:BAAALgAECgUJCgAAAA==.Creaminator:BAAALgAECgEJAQAAAA==.Cremate:BAAALgADCgEJAQAAAA==.Crilly:BAABLgAECn8rAAIPAAkJZRihLwA8AgAPAAkJZRihLwA8AgAAAA==.Crowe:BAAALgAECgUJCgABLgAECgUJBQAMAAAAAA==.Crowley:BAAALgADCgMJAwAAAA==.Crumpler:BAAALgADCgEJAQAAAA==.',
Cy='Cyroka:BAAALgAECgUJEQAAAA==.',
['Cö']='Cörgi:BAAALgADCgUJBQAAAA==.',
Da='Dalastish:BAAALgAECgYJDAAAAA==.Damia:BAABLgAECn8hAAMWAAgJQRmcEQD3AQAWAAgJQRmcEQD3AQAVAAIJ+guDFwB8AAAAAA==.Danobun:BAAALgADCgcJEAAAAA==.Darkdaysx:BAAALgADCgEJAQAAAA==.Darling:BAAALgADCgUJBQAAAA==.Darsithis:BAAALgAECgQJBQAAAA==.',
De='Deadite:BAABLgAECn8lAAIOAAkJ8CSPAgAOAwAOAAkJ8CSPAgAOAwAAAA==.Deathchip:BAAALgADCgIJAgAAAA==.Degenerate:BAAALgAECgEJAgABLgAECgkJJQAOAPAkAA==.Delvarrieth:BAABLgAECn8aAAIaAAYJcBFUHQD8AAAaAAYJcBFUHQD8AAAAAA==.Demonicblade:BAAALgADCgQJBAAAAA==.Denth:BAABLgAECn8VAAINAAgJvwuIiQA8AQANAAgJvwuIiQA8AQAAAA==.Dercuur:BAAALgAECgUJEAAAAA==.Devoursol:BAABLgAECn85AAMbAAkJlQwFSACMAQAbAAkJaAwFSACMAQALAAIJrg45XABvAAAAAA==.',
Dk='Dkalicious:BAAALgADCgcJEQAAAA==.',
Do='Doist:BAAALgAECgIJAgAAAA==.Dotur:BAAALgADCgEJAQAAAA==.',
Dr='Dragonkiss:BAAALgADCgkJGwAAAA==.Drainmee:BAABLgAECn8VAAIGAAYJShL2JwBiAQAGAAYJShL2JwBiAQAAAA==.Draknol:BAAALgADCgkJFAAAAA==.Dregoth:BAABLgAECn8lAAIRAAkJkQejaABwAQARAAkJkQejaABwAQAAAA==.Drekzy:BAAALgADCgcJBwAAAA==.Dretzerdor:BAAALgADCgkJCQABLgAECgQJBAAMAAAAAA==.',
Ds='Dshivà:BAAALgAECgEJBQAAAA==.',
Dy='Dyllin:BAAALgADCgEJAQAAAA==.',
['Dá']='Dálinar:BAABLgAECn8gAAMKAAkJ4R5kEAC0AgAKAAkJ4R5kEAC0AgAcAAEJxgmrgAAnAAAAAA==.',
Ea='Eathur:BAAALgADCgcJDwAAAA==.Eazz:BAAALgAECgEJAQAAAA==.',
Eb='Ebonmist:BAAALgAECgQJBgAAAA==.',
El='Elddib:BAAALgADCgkJCwAAAA==.Elunariel:BAAALgAECgEJAQABLgAECgkJGgACAPMcAA==.Elynth:BAABLgAECn8kAAICAAkJURuvHgBTAgACAAkJURuvHgBTAgAAAA==.',
En='Endlessyueh:BAAALgAECgYJDwAAAA==.',
Er='Eridormi:BAAALgAECgcJCQABLgAECgkJGgACAPMcAA==.',
Ev='Evilis:BAAALgADCgQJBQAAAA==.Evolnasty:BAAALgAFFAQJBAABLgAFFAQJCgANAHoOAA==.',
Fa='Face:BAAALgAECggJBgAAAA==.Faethian:BAACLgAFFH8OAAIaAAQJcCAAAgB7AQAaAAQJcCAAAgB7AQAuAAQKfywAAhoACAk7JYMCAN0CABoACAk7JYMCAN0CAAAA.Falunaria:BAAALgADCgYJBgAAAA==.Falunia:BAABLgAECn8rAAIPAAgJGgeaigBGAQAPAAgJGgeaigBGAQAAAA==.Fangren:BAABLgAECn8UAAISAAYJNA28fQAVAQASAAYJNA28fQAVAQAAAA==.Fariah:BAAALgAECgUJDgAAAA==.Farroukh:BAAALgADCgEJAQAAAA==.Farrseer:BAAALgAECgQJCAAAAA==.Fatalis:BAAALgAECgcJDAAAAA==.Fated:BAAALgAECgYJEwAAAA==.',
Fe='Felscythe:BAABLgAECn8ZAAIYAAYJcQEIXAB9AAAYAAYJcQEIXAB9AAAAAA==.Felynn:BAABLgAECn8iAAIBAAkJRxdFFwAoAgABAAkJRxdFFwAoAgAAAA==.Femboy:BAAALgAECgEJAQAAAA==.Feres:BAAALgAECgQJBwAAAA==.Feyrha:BAAALgADCgYJBgABLgAECggJGgASAMcPAA==.',
Fi='Fiadh:BAAALgAECgIJAgAAAA==.Fialova:BAAALgADCgcJDQAAAA==.Fierrastar:BAAALgAECgYJCQAAAA==.Finshao:BAABLgAECn8WAAIdAAYJbxz3HwDWAQAdAAYJbxz3HwDWAQAAAA==.',
Fl='Flaeli:BAABLgAECn8fAAIPAAgJRxQuWQC1AQAPAAgJRxQuWQC1AQAAAA==.Flemish:BAAALgAECgYJCwAAAA==.Flextame:BAAALgAECgQJCwAAAA==.Flipalicious:BAABLgAECn83AAIUAAkJ7Bs1DQDFAgAUAAkJ7Bs1DQDFAgAAAA==.Flipanomicon:BAAALgADCgYJCQAAAA==.',
Fr='Freyalise:BAABLgAECn8cAAIFAAYJtBeULABJAQAFAAYJtBeULABJAQAAAA==.Frozencorgi:BAAALgADCgQJBAAAAA==.',
Ga='Gaia:BAABLgAECn8aAAISAAgJxw/dTQCLAQASAAgJxw/dTQCLAQAAAA==.Gazo:BAAALgAECgYJBgABLgAECgkJJAAeAKYdAA==.',
Ge='Gemboss:BAABLgAECn89AAMNAAgJNB+sJgBHAgANAAgJNB+sJgBHAgABAAQJLhLAYwDtAAAAAA==.Gerbo:BAABLgAECn8rAAMPAAkJmxOuTwDQAQAPAAkJmxOuTwDQAQAfAAMJrwXAFQBuAAAAAA==.',
Gi='Gianavel:BAABLgAECn8kAAIeAAgJQwivNwD3AAAeAAgJQwivNwD3AAAAAA==.Ginodh:BAABLgAECn8OAAIbAAgJtQ0MZgA0AQAbAAgJtQ0MZgA0AQABLgAECgkJGQAOAPwNAA==.Ginomage:BAAALgAECgcJCgABLgAECgkJGQAOAPwNAA==.Ginomonk:BAAALgAECgYJBgABLgAECgkJGQAOAPwNAA==.Ginopally:BAAALgAECgYJCwABLgAECgkJGQAOAPwNAA==.Girth:BAAALgADCgIJAgAAAA==.Gizelli:BAAALgADCgMJAwAAAA==.',
Go='Gordonn:BAAALgAECgQJBAAAAA==.',
Gr='Groblock:BAAALgADCgYJBgAAAA==.Grubetsell:BAAALgADCgUJCgABLgAFFAIJBQAdAGMXAA==.Grubetsella:BAACLgAFFH8FAAIdAAIJYxduDwClAAAdAAIJYxduDwClAAAuAAQKfysAAh0ACAk3It8JAMgCAB0ACAk3It8JAMgCAAAA.',
Gu='Guenhywvar:BAABLgAECn8XAAIbAAYJXBvFUAC0AQAbAAYJXBvFUAC0AQAAAA==.Gumpers:BAABLgAECn8jAAIgAAgJhQ+YGwAuAQAgAAgJhQ+YGwAuAQAAAA==.Gundras:BAAALgAECgEJAQAAAA==.Gustice:BAAALgADCgkJEwAAAA==.',
Gy='Gyda:BAAALgAECgUJCQAAAA==.',
Ha='Halfamazing:BAAALgAECgQJBQAAAA==.Hanoumatoi:BAAALgAECgUJBQAAAA==.Haralambos:BAABLgAECn8VAAIaAAUJMQ9JKACnAAAaAAUJMQ9JKACnAAAAAA==.Haralogain:BAAALgAECgEJAQABLgAECgUJFQAaADEPAA==.Harithon:BAABLgAECn8kAAIhAAkJkR4cBACPAgAhAAkJkR4cBACPAgAAAA==.Harlar:BAAALgAECgEJAQAAAA==.Havvöc:BAABLgAECn8sAAIBAAkJoBwPCQDUAgABAAkJoBwPCQDUAgAAAA==.',
He='Hekâte:BAAALgADCgYJCQAAAA==.Heledosia:BAABLgAECn8fAAIEAAcJcQOLKgC6AAAEAAcJcQOLKgC6AAAAAA==.Hereticblood:BAAALgADCgEJAQAAAA==.Hermajesty:BAAALgADCgkJDQAAAA==.Hestiamajere:BAABLgAECn8VAAIPAAYJPgnzvQDvAAAPAAYJPgnzvQDvAAAAAA==.Heyokagi:BAABLgAECn8vAAQXAAkJNyJMAQAgAwAXAAkJNyJMAQAgAwAgAAIJ1BS5JgBnAAAKAAEJXwhCwQAsAAAAAA==.',
Ho='Hopemaker:BAAALgADCgkJFAABLgAECgkJGgACAPMcAA==.Hordkilla:BAABLgAECn8eAAINAAgJuAUbpAAPAQANAAgJuAUbpAAPAQAAAA==.Hottdealer:BAAALgADCgUJBQAAAA==.Hownowbrncw:BAABLgAECn8fAAINAAcJxhuQSQDLAQANAAcJxhuQSQDLAQAAAA==.',
Hu='Huuna:BAAALgADCgkJFwAAAA==.',
Hy='Hyce:BAABLgAECn8tAAMbAAkJ/RtwEgCSAgAbAAkJ/RtwEgCSAgAiAAEJphphJQBMAAAAAA==.Hylda:BAAALgADCgUJBQAAAA==.',
Ih='Ihavenoname:BAAALgADCgMJAwAAAA==.',
Il='Illusionous:BAAALgAECgUJCgAAAA==.',
Im='Imathdal:BAABLgAECn8lAAIjAAkJrw6nCgCcAQAjAAkJrw6nCgCcAQAAAA==.',
In='Ingwë:BAAALgADCgMJBQAAAA==.Innominat:BAAALgADCgYJBgABLgAECgUJBQAMAAAAAA==.Insoniacyun:BAAALgAECgUJCAAAAA==.',
Is='Iselian:BAAALgAECgkJIQAAAQ==.Ishanu:BAABLgAECn8aAAIFAAkJIhyxCwByAgAFAAkJIhyxCwByAgAAAA==.',
Iz='Izludez:BAAALgAECgIJAgABLgAECgUJBQAMAAAAAA==.',
Ja='Jabbah:BAAALgAECgYJCgAAAA==.Jamaicalife:BAAALgADCgkJGgABLgADCggJDgAMAAAAAA==.Jax:BAACLgAFFH8NAAIPAAQJRCJaLQBvAQAPAAQJRCJaLQBvAQAuAAQKfykAAg8ACAlFIxATADUDAA8ACAlFIxATADUDAAAA.',
Jb='Jblockiv:BAAALgADCgcJDAAAAA==.Jbprimero:BAAALgADCgUJBQAAAA==.Jbshami:BAABLgAECn8kAAMUAAcJFSBAFQB0AgAUAAcJFSBAFQB0AgATAAMJWQamcgB3AAAAAA==.',
Je='Jeb:BAAALgAECgUJBgAAAA==.Jeman:BAAALgADCgcJBwAAAA==.Jenzak:BAABLgAECn80AAIfAAkJ2gv0AwClAQAfAAkJ2gv0AwClAQAAAA==.Jetfires:BAABLgAECn85AAISAAkJFhsnFwBzAgASAAkJFhsnFwBzAgAAAA==.',
Jh='Jhenua:BAAALgADCgcJBQAAAA==.',
Ji='Jinger:BAABLgAECn8UAAIeAAYJkwVTSwCrAAAeAAYJkwVTSwCrAAAAAA==.',
Jo='Joel:BAAALgADCgUJBQAAAA==.Jonn:BAAALgADCgEJAQAAAA==.Jordun:BAAALgADCgcJBwAAAA==.Jozhua:BAAALgAECgUJCQAAAA==.',
Ju='Julliane:BAAALgADCgUJAwAAAA==.Jungg:BAAALgAECgIJAgAAAA==.',
Ka='Kaedren:BAAALgADCgkJFwAAAA==.Kaelaya:BAABLgAECn8ZAAIjAAYJFAkdGQDGAAAjAAYJFAkdGQDGAAAAAA==.Kaelorien:BAABLgAECn80AAIdAAkJtg/IIgDBAQAdAAkJtg/IIgDBAQAAAA==.Kaetta:BAABLgAECn8XAAIPAAgJ0APpqAASAQAPAAgJ0APpqAASAQAAAA==.Kaifaruo:BAAALgAECgEJAQAAAA==.Kairelia:BAAALgAECgQJBwAAAA==.Kairilean:BAAALgAECgUJCAAAAA==.Kakuru:BAAALgADCgEJAQAAAA==.Kalazaad:BAAALgAECgYJBwAAAA==.Kaldevayn:BAAALgAECgMJAwAAAA==.Kaldeyra:BAAALgADCgcJCwAAAA==.Kaliantha:BAAALgAECgQJBgAAAA==.Kalivanilian:BAAALgADCgEJAQAAAA==.Kalrow:BAABLgAECn8gAAIbAAYJsAxZiADmAAAbAAYJsAxZiADmAAAAAA==.Kardanis:BAABLgAECn8jAAIUAAkJviRHAQCrAwAUAAkJviRHAQCrAwAAAA==.Kashe:BAAALgAECgUJEwAAAA==.Kassarra:BAAALgADCgcJBwAAAA==.Katavia:BAABLgAECn8lAAIUAAkJZxLBMADCAQAUAAkJZxLBMADCAQAAAA==.Kaydencia:BAABLgAECn8XAAINAAYJvxFdsgD5AAANAAYJvxFdsgD5AAAAAA==.Kayrae:BAAALgAECgEJAgAAAA==.Kaznahla:BAAALgAECgMJAwAAAA==.Kazureshal:BAAALgAECgEJAQAAAA==.',
Ke='Kelenet:BAAALgADCgUJDQAAAA==.Keminar:BAAALgADCgcJDQAAAA==.',
Kh='Khaleanu:BAAALgADCgcJBwAAAA==.Khijara:BAAALgADCgMJAwAAAA==.',
Ki='Ki:BAAALgAECgQJBAAAAA==.Kiddow:BAAALgAECgUJDQAAAA==.Killision:BAAALgADCgUJBgAAAA==.Kilrah:BAAALgADCgkJDgAAAA==.Kiri:BAAALgADCgkJEAAAAA==.Kitamii:BAABLgAECn8UAAIXAAYJdRbHEQCQAQAXAAYJdRbHEQCQAQAAAA==.Kivrin:BAAALgAECgUJDAAAAA==.',
Kr='Kringlë:BAABLgAECn8mAAISAAkJ3SBMDwCvAgASAAkJ3SBMDwCvAgAAAA==.Kritish:BAAALgAECgEJAQAAAA==.',
Ku='Kushwizard:BAAALgADCgQJBQAAAA==.',
Ky='Kymma:BAABLgAECn8oAAINAAgJBw4ecgBqAQANAAgJBw4ecgBqAQAAAA==.Kyunix:BAAALgADCgYJDAAAAA==.',
La='Lagoriatsua:BAABLgAECn8XAAITAAgJYgYORADzAAATAAgJYgYORADzAAAAAA==.Laitue:BAAALgAECgQJCQAAAA==.Lanill:BAAALgAECgEJAQAAAA==.Laviz:BAAALgAECgIJAwAAAA==.Lazengann:BAABLgAECn8eAAMbAAgJrRNEYwA8AQAbAAgJRRNEYwA8AQALAAEJvxboagA7AAAAAA==.',
Le='Leafbane:BAAALgADCgEJAQAAAA==.Leagann:BAAALgAECgEJAQAAAA==.Legevia:BAAALgAECgYJEwAAAA==.Leilau:BAAALgAECgUJAQAAAA==.Leiris:BAABLgAECn8zAAINAAkJqxDHRwDQAQANAAkJqxDHRwDQAQAAAA==.Leisha:BAAALgADCgEJAQAAAA==.Letifer:BAAALgADCgkJDAAAAA==.Leucetios:BAAALgADCgkJFwAAAA==.Leywin:BAAALgAECgcJBgAAAA==.',
Li='Liarace:BAABLgAECn8bAAIJAAkJPhkPCwCOAgAJAAkJPhkPCwCOAgAAAA==.Lightbeard:BAABLgAECn8YAAQBAAUJ7R3iKACgAQABAAUJ7R3iKACgAQAaAAEJ4A+eRQApAAANAAEJRwPqewElAAAAAA==.Lightdawns:BAAALgAECgYJCQAAAA==.Lightforge:BAABLgAECn8VAAINAAcJfBmJZAC4AQANAAcJfBmJZAC4AQAAAA==.Lightseye:BAAALgADCgcJBwAAAA==.Lionessi:BAAALgADCgkJGQAAAA==.',
Ll='Llug:BAAALgAECgYJCwAAAA==.',
Lo='Lorredain:BAAALgADCgkJFgAAAA==.Lothwen:BAAALgAECgMJAwAAAA==.Louisachan:BAAALgADCgUJBQAAAA==.',
Lu='Luminar:BAAALgADCgEJAQAAAA==.Lunalaughs:BAAALgAECgEJAQAAAA==.Lunå:BAECLgAFFH8PAAIJAAQJyhOhEQAOAQAJAAQJyhOhEQAOAQAuAAQKfyoAAgkACQmSFJMsAJQBAAkACQmSFJMsAJQBAAAA.Luxinine:BAABLgAECn8XAAIFAAYJeh8LHwClAQAFAAYJeh8LHwClAQAAAA==.',
Ly='Lyon:BAAALgADCgMJCgAAAA==.Lyshai:BAAALgADCgUJCAABLgAECgYJGgAkAOQfAA==.',
Ma='Madhawi:BAAALgAECgYJDwAAAA==.Magamon:BAABLgAECn8lAAIPAAkJshasPQAJAgAPAAkJshasPQAJAgAAAA==.Mahndarb:BAAALgAECgMJBgABLgAECggJGQAJAGwQAA==.Majima:BAAALgAECgYJDgAAAA==.Malfuriia:BAABLgAECn8aAAIUAAYJ2hkHMQDBAQAUAAYJ2hkHMQDBAQAAAA==.Maluun:BAAALgADCgMJAwAAAA==.Mamboke:BAAALgADCgEJAQAAAA==.Margerdria:BAAALgAECgUJEgAAAA==.Maskelle:BAABLgAECn8hAAIiAAgJHRApDQBTAQAiAAgJHRApDQBTAQAAAA==.Mauugrim:BAABLgAECn8gAAIRAAgJRwe7fgBAAQARAAgJRwe7fgBAAQAAAA==.Mauva:BAAALgADCgEJAQAAAA==.Maxowen:BAAALgAECgYJEgAAAA==.',
Me='Mearadan:BAAALgAECgkJDwAAAA==.Meatsweats:BAABLgAECn8WAAINAAYJ8QizvADqAAANAAYJ8QizvADqAAAAAA==.Megg:BAAALgAECgMJAwAAAA==.Megumim:BAAALgAECgYJDwAAAA==.Mekh:BAABLgAECn8aAAMkAAYJ5B8kBgDKAQAkAAYJ5B8kBgDKAQAlAAEJVQjQSwAqAAAAAA==.Mel:BAAALgAECgMJBwAAAA==.Melanara:BAABLgAECn88AAIPAAkJbgzIVQC+AQAPAAkJbgzIVQC+AQAAAA==.Melstrom:BAAALgAECgMJAwAAAA==.Melynda:BAAALgADCgEJAQAAAA==.Memy:BAAALgAECgYJBwAAAA==.Meticuluslyn:BAAALgADCgcJDgAAAA==.',
Mg='Mgcklmari:BAAALgADCgEJAQAAAA==.',
Mi='Milkmaiden:BAAALgADCgYJCwAAAA==.Mixler:BAAALgAECggJEAAAAA==.Miyävii:BAABLgAECn8YAAIaAAkJxxPfEgBtAQAaAAkJxxPfEgBtAQAAAA==.',
Mj='Mjsage:BAABLgAECn8iAAISAAkJCB7eGQBiAgASAAkJCB7eGQBiAgAAAA==.',
Mm='Mmeow:BAAALgAECgQJBQABLgAECggJDQAMAAAAAA==.',
Mo='Mockingbird:BAAALgAECgUJBQAAAA==.Moirine:BAABLgAECn8VAAIFAAYJQBVJLgA+AQAFAAYJQBVJLgA+AQAAAA==.Moonflowers:BAACLgAFFH8bAAIKAAYJzh0HBwAyAgAKAAYJzh0HBwAyAgAuAAQKfy8AAgoACAmcJOMGAC4DAAoACAmcJOMGAC4DAAAA.Mordsevoker:BAAALgAFFAIJAgABLgAFFAUJFAARAFwSAA==.Morginoth:BAAALgADCgcJBwAAAA==.Mousekee:BAABLgAECn8aAAIJAAgJ/QkfKwBLAQAJAAgJ/QkfKwBLAQAAAA==.',
Mu='Murdrmitts:BAABLgAECn8UAAIXAAgJOgkVFwAjAQAXAAgJOgkVFwAjAQAAAA==.Mustikka:BAABLgAECn8UAAIXAAUJWgwdIgC8AAAXAAUJWgwdIgC8AAAAAA==.',
My='Myuriyanka:BAABLgAECn8mAAMTAAgJJBMXKgB0AQATAAgJJBMXKgB0AQAUAAEJDgEgrAAaAAAAAA==.Myzrian:BAAALgAECgEJAQABLgAECgYJBwAMAAAAAA==.',
Na='Naahommii:BAABLgAECn8dAAISAAgJrRbBQQCxAQASAAgJrRbBQQCxAQAAAA==.Nachtpranke:BAAALgAECgcJEwAAAA==.Nadron:BAAALgAECgMJBQAAAA==.Nagualli:BAAALgADCgkJDwAAAA==.',
Ne='Negargra:BAABLgAECn8kAAMCAAYJ5w9nkwD/AAACAAYJ5w9nkwD/AAAmAAEJcgMufAAkAAAAAA==.Nephadin:BAAALgAECgYJDgAAAA==.Nephilum:BAAALgAECgYJCgAAAA==.',
Ni='Nidarian:BAAALgAECgUJCAAAAA==.Nighlight:BAAALgADCggJEQAAAA==.Nighttiger:BAAALgAECgYJEwAAAA==.Nikooli:BAAALgAECgYJEgAAAA==.Nitaya:BAAALgAECgEJAQAAAA==.',
No='Nokkoh:BAAALgADCgQJBAAAAA==.Noodledragon:BAAALgAECgYJBgAAAA==.Noopsie:BAABLgAECn8aAAIKAAUJzAwTagDVAAAKAAUJzAwTagDVAAAAAA==.Nooterllus:BAAALgADCgYJCQABLgAFFAcJHAAlAOoPAA==.Norrina:BAAALgADCggJCAAAAA==.Notbaldpries:BAABLgAECn8cAAMGAAgJxhpcEgAlAgAGAAcJLhxcEgAlAgAFAAcJsBysJAB8AQAAAA==.Novarox:BAAALgAECgEJAQAAAA==.',
Ny='Nyteweaver:BAABLgAECn8ZAAINAAYJ5BKQkQAvAQANAAYJ5BKQkQAvAQAAAA==.Nyxiia:BAAALgADCgYJBgAAAA==.Nyxorya:BAABLgAECn8XAAMfAAkJbgM/EgCgAAAPAAkJWQONwgDoAAAfAAcJogE/EgCgAAAAAA==.',
Ob='Oberonny:BAAALgAECgQJBAAAAA==.',
Od='Oderica:BAAALgAECgIJAgAAAA==.Odynwolf:BAAALgADCgEJAQAAAA==.',
Ol='Olinar:BAAALgADCggJDwAAAA==.Olympia:BAABLgAECn8mAAIaAAkJ+gx/GAArAQAaAAkJ+gx/GAArAQAAAA==.',
On='Ontai:BAAALgADCgkJFAAAAA==.',
Or='Oraclemega:BAABLgAECn8hAAIPAAgJrBTvSQDiAQAPAAgJrBTvSQDiAQAAAA==.',
Os='Oscarmikey:BAACLgAFFH8VAAMKAAUJDQtUGwBHAQAKAAUJDQtUGwBHAQAcAAEJhAFdQAAvAAAuAAQKfysABQoACAlFG0gcAEACAAoACAlFG0gcAEACABwABAnrDUdZAHoAABcAAQlMAn1GACMAACAAAQkAAKNpAAAAAAAA.',
Ot='Ottoshot:BAABLgAECn8aAAISAAYJnA/LdwAhAQASAAYJnA/LdwAhAQAAAA==.',
Ov='Overlordock:BAAALgAECgQJBwAAAA==.',
['Oö']='Oöps:BAAALgAECgUJCQAAAA==.',
Pa='Panamone:BAABLgAECn8ZAAMXAAYJViAbCwDWAQAXAAYJViAbCwDWAQAKAAEJFA2YwgArAAAAAA==.Pandeism:BAABLgAECn8cAAMhAAcJ6xOBFQAiAQAhAAYJbROBFQAiAQAUAAEJPhXkpwBBAAAAAA==.Papagrip:BAABLgAECn8qAAMQAAgJ4xJIDABqAQAQAAgJ1hJIDABqAQARAAgJeQm2hwAvAQAAAA==.Patrin:BAABLgAECn8aAAIPAAgJAwgvmQAsAQAPAAgJAwgvmQAsAQAAAA==.Paulee:BAAALgADCgkJCwAAAA==.',
Pe='Peanutbritle:BAABLgAECn8lAAIOAAkJWQafJQD3AAAOAAkJWQafJQD3AAAAAA==.Pendragon:BAAALgADCgMJBAAAAA==.Pesch:BAAALgAECgkJEQAAAA==.',
Ph='Phantdoom:BAAALgAECgYJEQAAAA==.',
Pi='Picdruid:BAAALgAECgQJBwABLgAFFAIJBAAMAAAAAA==.',
Pl='Plsdiddyno:BAAALgAFFAEJAQAAAA==.',
Po='Pogmothoin:BAAALgAECgMJBQAAAA==.',
Pr='Priina:BAAALgADCgQJBwAAAA==.',
Pu='Puchi:BAAALgAECgUJBQAAAA==.Punchabaal:BAAALgAECgcJDAAAAA==.',
Qu='Quadradozin:BAAALgAECgQJCAAAAA==.',
Ra='Raez:BAAALgAECgYJDgAAAA==.Raharmin:BAABLgAECn8XAAIKAAcJWRnvMwDZAQAKAAcJWRnvMwDZAQAAAA==.Ranui:BAAALgADCgUJBQAAAA==.Rargnara:BAAALgAECgQJBAAAAA==.Rashona:BAAALgADCgkJHAAAAA==.Ravemom:BAAALgADCgcJBwAAAA==.',
Re='Reihino:BAAALgAECgYJCAAAAA==.Remixidora:BAAALgAECgYJBwABLgAFFAUJGQAPAFYlAA==.Reyrocko:BAAALgAECgQJAwAAAA==.Rezdh:BAAALgADCgMJAQABLgAFFAMJCgAFAF0dAA==.Rezhunt:BAAALgAECggJCAABLgAFFAMJCgAFAF0dAA==.Rezshift:BAABLgAECn8bAAMcAAgJwhy0EQAjAgAcAAgJwhy0EQAjAgAKAAQJBRbtbwAFAQABLgAFFAMJCgAFAF0dAA==.Rezvoid:BAACLgAFFH8KAAMFAAMJXR23GAD+AAAFAAMJXR23GAD+AAAJAAIJgyFlGwCvAAAuAAQKfzIAAgUACQkQI5oEAPYCAAUACQkQI5oEAPYCAAAA.',
Rh='Rhage:BAAALgAECgMJBwAAAA==.',
Ri='Riahana:BAAALgAECgMJBAAAAA==.',
Ro='Rooroo:BAAALgAECgYJCQAAAA==.Rottingturky:BAABLgAECn8XAAIRAAcJlRKnhQAzAQARAAcJlRKnhQAzAQAAAA==.Roxane:BAABLgAECn8iAAIcAAgJiwnONwADAQAcAAgJiwnONwADAQAAAA==.',
Ru='Runningelk:BAABLgAECn8oAAIgAAgJ2RMmFAB4AQAgAAgJ2RMmFAB4AQAAAA==.Runscapemain:BAABLgAECn8iAAINAAkJvRXMQQDiAQANAAkJvRXMQQDiAQAAAA==.',
Ry='Ryeti:BAAALgADCgkJDAAAAA==.',
['Rà']='Ràni:BAAALgADCgYJBgABLgAFFAMJDgALAAEkAA==.',
Sa='Saintulrick:BAAALgAECgEJAQAAAA==.Sajuice:BAACLgAFFH8HAAIjAAUJPwWfEgDyAAAjAAUJPwWfEgDyAAAuAAQKfyYAAiMACAnAGw4IANsBACMACAnAGw4IANsBAAAA.Sandía:BAAALgAECgcJDwAAAA==.Sanitas:BAABLgAECn8ZAAIJAAcJBgoTMwAWAQAJAAcJBgoTMwAWAQAAAA==.Sanluis:BAAALgADCgEJAQAAAA==.',
Sc='Scathea:BAAALgADCgMJAwABLgADCgQJBgAMAAAAAA==.',
Se='Seeyen:BAACLgAFFH8SAAISAAQJGBetJQA5AQASAAQJGBetJQA5AQAuAAQKfyoAAhIACQmQHgUHAB8DABIACQmQHgUHAB8DAAAA.Selûne:BAAALgAECgMJAwAAAA==.Sentrath:BAAALgADCgkJHQAAAA==.Seraphi:BAABLgAECn8gAAIkAAkJiAl2CACHAQAkAAkJiAl2CACHAQAAAA==.Seren:BAAALgAFFAEJAQABLgAFFAUJDAAPAJQFAA==.Serenityhate:BAABLgAECn8UAAIJAAYJUwm9OQDtAAAJAAYJUwm9OQDtAAAAAA==.',
Sh='Shadowhunder:BAAALgADCgMJAwAAAA==.Shaggyp:BAAALgAECgYJBgAAAA==.Shandrilyn:BAABLgAECn8VAAIFAAYJHwSnSQC6AAAFAAYJHwSnSQC6AAAAAA==.Shanthris:BAAALgADCgcJBwAAAA==.Sheep:BAAALgADCgMJAwAAAA==.Ships:BAABLgAECn8fAAIlAAkJwBRMFQBSAQAlAAkJwBRMFQBSAQAAAA==.',
Si='Sini:BAAALgAFFAcJBAAAAA==.Sinthoras:BAAALgAECgQJBAAAAA==.',
Sk='Skala:BAABLgAECn8XAAInAAkJThbQFwD4AQAnAAkJThbQFwD4AQAAAA==.Skibbie:BAACLgAFFH8VAAMkAAUJXw45BAAXAQAkAAQJfQg5BAAXAQAnAAUJHg6lJAAKAQAuAAQKfx4ABCcACQk4GF8QAHMCACcACQk4GF8QAHMCACQABQnOBpAsALcAACUABAmHDmkiALYAAAAA.Skibbward:BAABLgAECn8zAAQgAAgJTiS4AQAyAwAgAAgJTiS4AQAyAwAcAAUJxQ9jVADUAAAKAAYJ6QrsggDSAAABLgAFFAUJFQAkAF8OAA==.Skipýr:BAAALgADCgEJAQAAAA==.Skrektwo:BAAALgAECgcJDwAAAA==.',
Sl='Slaying:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgEJAgAAAA==.',
Sm='Smackdogg:BAABLgAECn8ZAAIcAAcJPR0XHQAYAgAcAAcJPR0XHQAYAgABLgAFFAgJKwATAGkdAA==.',
So='Solteria:BAABLgAECn8VAAIDAAcJqAk/DgBOAQADAAcJqAk/DgBOAQAAAA==.Sombra:BAAALgADCgMJAwAAAA==.Sooyoung:BAAALgAECgYJEgAAAA==.Sorvina:BAABLgAECn84AAICAAkJdBJeNADvAQACAAkJdBJeNADvAQAAAA==.Soulflame:BAABLgAECn82AAIPAAgJCQ6qagCJAQAPAAgJCQ6qagCJAQAAAA==.Soulshifter:BAABLgAECn8XAAIcAAYJWgsuQwDOAAAcAAYJWgsuQwDOAAAAAA==.Soultrader:BAAALgADCgkJFwABLgAECgUJFQAaADEPAA==.',
Sp='Spooñ:BAAALgADCgcJBwAAAA==.Spottedcoat:BAABLgAECn8lAAIKAAkJZgOzcADCAAAKAAkJZgOzcADCAAAAAA==.',
St='Stabmcshank:BAAALgAECgIJAgAAAA==.Standinit:BAAALgAECgYJBgAAAA==.Strangerx:BAAALgAECgEJAQAAAA==.Stregnor:BAABLgAECn8zAAISAAkJhxaXHwA/AgASAAkJhxaXHwA/AgAAAA==.Styggi:BAAALgAECgEJAQAAAA==.Stygy:BAAALgAECgMJAwAAAA==.Størmhide:BAAALgAECgEJAQABLgAFFAMJDgALAAEkAA==.',
Su='Suasponte:BAAALgADCgUJCAAAAA==.Sumyunguy:BAABLgAECn8wAAMeAAgJlhQAHQCeAQAeAAgJlhQAHQCeAQAYAAQJ7QqMZQCrAAAAAA==.',
Sy='Sylarì:BAAALgAECgEJAQAAAA==.Sylphy:BAAALgAECgMJBgAAAA==.Sylv:BAAALgADCgIJAgAAAA==.Syrintha:BAAALgAECgEJAQAAAA==.',
['Sö']='Söapy:BAABLgAECn8eAAMnAAkJDxKrEwBHAgAnAAkJfhGrEwBHAgAkAAYJoRL3HwAuAQAAAA==.',
Ta='Tachi:BAAALgADCgUJCAABLgAECggJHgAnAF0XAA==.Tachie:BAABLgAECn8eAAMnAAgJXRcUIgCnAQAnAAgJqhYUIgCnAQAkAAUJDBS1JQD2AAAAAA==.Tacobelle:BAAALgADCgQJBAABLgAFFAUJFgADAC0mAA==.Taele:BAABLgAECn8mAAMPAAkJlRuBNQAlAgAPAAgJaRuBNQAlAgAfAAUJlhq3CABnAQAAAA==.Taiche:BAABLgAECn8zAAIcAAkJ9Aw+JQBzAQAcAAkJ9Aw+JQBzAQAAAA==.Tamalpais:BAAALgAECgUJEAAAAA==.Tamarind:BAAALgAECgYJBgABLgAECgkJJAAhAJEeAA==.Tanya:BAAALgAECgUJBQAAAA==.Tareyn:BAAALgAECgcJDgAAAA==.Tavita:BAAALgADCgEJAQAAAA==.',
Te='Testrazilae:BAAALgADCgQJBQAAAA==.Tetranis:BAAALgAECgQJBwAAAA==.Tezzerae:BAABLgAECn8aAAISAAYJTgMjpwC4AAASAAYJTgMjpwC4AAAAAA==.',
Th='Thaesan:BAAALgAECgUJCQAAAA==.Therin:BAABLgAECn8wAAIZAAkJHRUEDwAiAgAZAAkJHRUEDwAiAgAAAA==.Thodi:BAAALgAECgQJAwAAAA==.',
Ti='Tingo:BAAALgADCgEJAgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Tiroin:BAAALgAECgIJAgAAAA==.',
To='Tongshi:BAAALgADCgYJEQAAAA==.Toofast:BAABLgAECn8nAAIUAAgJOCCkCQDxAgAUAAgJOCCkCQDxAgAAAA==.Toofurrious:BAAALgADCgkJKwAAAA==.Topswimmer:BAAALgAECgYJDgAAAA==.Touched:BAAALgADCgYJBgAAAA==.',
Tp='Tphoenix:BAAALgAECgUJBgAAAA==.',
Tr='Trifus:BAABLgAECn8YAAMOAAYJxxLRIwAFAQAOAAYJxxLRIwAFAQARAAQJ9Qc22gCqAAAAAA==.Trilex:BAAALgAECgEJAQAAAA==.Trydora:BAABLgAECn8UAAIKAAUJiB3CNAClAQAKAAUJiB3CNAClAQAAAA==.',
Ts='Tsugumi:BAAALgAECgEJAQABLgAECgIJAgAMAAAAAA==.',
Tu='Tulao:BAABLgAECn8hAAIPAAcJug4ZjABDAQAPAAcJug4ZjABDAQAAAA==.',
Tw='Twan:BAAALgAECgYJBwABLgAFFAYJEQAbANkYAA==.',
Ty='Tyledoriel:BAAALgADCgEJAQAAAA==.Tyrionel:BAAALgAECgUJCQAAAA==.',
Tz='Tzitzimitl:BAAALgADCgkJCQAAAA==.',
Ui='Uiknu:BAABLgAFFH8GAAIdAAQJaRAEIADzAAAdAAQJaRAEIADzAAAAAA==.',
Ut='Utheli:BAACLgAFFH8JAAINAAMJ9BFwSwDsAAANAAMJ9BFwSwDsAAAuAAQKfx4AAg0ACAkBGyU8APMBAA0ACAkBGyU8APMBAAAA.',
Va='Vaevictis:BAAALgAECgEJAQABLgAECgYJHAAFALQXAA==.Vaildora:BAAALgAECgEJAQABLgAECggJHgAnAF0XAA==.Valdra:BAABLgAECn80AAIEAAkJCBHNEQCkAQAEAAkJCBHNEQCkAQAAAA==.',
Vi='Vidiablade:BAAALgAFFAIJAgAAAA==.Viralprepped:BAAALgAECgMJBwAAAA==.Vitamix:BAAALgADCgYJDgAAAA==.',
Vl='Vlonet:BAABLgAECn8fAAMbAAkJ6w7EQAClAQAbAAkJ6w7EQAClAQALAAYJEg7eKQDzAAAAAA==.',
Vn='Vnasty:BAACLgAFFH8KAAINAAQJeg6SNQAiAQANAAQJeg6SNQAiAQAuAAQKfywAAg0ACQkrICkKAD8DAA0ACQkrICkKAD8DAAAA.',
Vr='Vrale:BAAALgAECgQJCAAAAA==.',
Wa='Wart:BAAALgADCggJEgAAAA==.',
We='Weslia:BAAALgADCgcJEQAAAA==.',
Wh='Whelp:BAAALgAECgEJAQAAAA==.',
Wi='Wilken:BAABLgAECn8nAAIoAAkJPxUHCgAhAgAoAAkJPxUHCgAhAgAAAA==.',
Wr='Wraithborne:BAAALgAECgIJAgAAAA==.Wreckoner:BAABLgAECn8lAAINAAkJ/xrLJABQAgANAAkJ/xrLJABQAgAAAA==.',
Ws='Wspr:BAAALgAECgIJBAAAAA==.',
Xa='Xaartahli:BAAALgAECgQJBwAAAA==.Xavencia:BAAALgAECgYJDwAAAA==.Xavienz:BAAALgADCgUJCAAAAA==.',
Xi='Xiangu:BAAALgAECgEJAQAAAA==.Xinthos:BAAALgAECgIJAgAAAA==.',
Ya='Yanut:BAAALgAECgYJDwAAAA==.',
Ye='Yeetjin:BAAALgAECgMJAgAAAA==.',
Yi='Yinamin:BAAALgAECgYJEQAAAA==.',
Yk='Yknub:BAAALgADCgYJCQAAAA==.',
Yu='Yumnomi:BAAALgADCgEJAQAAAA==.',
Za='Zadivya:BAABLgAECn8XAAIKAAcJgxAAUwAhAQAKAAcJgxAAUwAhAQAAAA==.Zalanto:BAAALgAECgEJAQAAAA==.Zamael:BAAALgAECgUJBwAAAA==.Zansarutobi:BAAALgADCgYJCgAAAA==.Zapla:BAAALgADCgQJCAAAAA==.Zarathoszan:BAABLgAECn80AAISAAgJyw8pTgCKAQASAAgJyw8pTgCKAQAAAA==.',
Ze='Zelgaddis:BAABLgAECn8kAAMUAAkJiRMNMgC8AQAUAAgJYxMNMgC8AQAhAAIJTQQnMQAsAAAAAA==.Zenanor:BAAALgAECgEJAQAAAA==.Zenatrat:BAAALgADCgEJAQAAAA==.Zerati:BAEALgAECgIJAgAAAA==.',
Zo='Zolthraxx:BAABLgAECn8bAAInAAcJVgyWPAARAQAnAAcJVgyWPAARAQAAAA==.',
Zr='Zriana:BAAALgAECgEJAQAAAA==.',
Zs='Zsarilya:BAABLgAECn8hAAIJAAgJNgLFPADbAAAJAAgJNgLFPADbAAAAAA==.',
Zu='Zurgen:BAABLgAECn80AAICAAkJGx+5DwC3AgACAAkJGx+5DwC3AgAAAA==.',
Zz='Zzypria:BAAALgADCgkJDQAAAA==.Zzyzzxi:BAAALgADCgcJCgAAAA==.',
['Êc']='Êclipse:BAEBLgAECn8sAAIKAAgJgBGwMAC7AQAKAAgJgBGwMAC7AQABLgAFFAQJDwAJAMoTAA==.',
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
