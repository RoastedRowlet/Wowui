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

local lookup = {'Paladin-Retribution','Druid-Balance','Shaman-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warrior-Protection','Monk-Brewmaster','Druid-Restoration','Druid-Feral','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Shaman-Elemental','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Rogue-Subtlety','DemonHunter-Devourer','DemonHunter-Havoc','Mage-Frost','Druid-Guardian','Paladin-Holy','Evoker-Devastation',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adolyn:BAAALgADCgkJCQAAAA==.Adventis:BAAALgADCgQJAwAAAA==.',
Al='Allavus:BAAALgADCgQJBQABLgAFFAQJDAABAL4cAA==.',
Am='Amrin:BAAALgADCgYJBgAAAA==.',
An='Andderson:BAAALgAECgEJAgAAAA==.Andersen:BAABLgAECn8gAAIBAAgJ6R1cIQA8AgABAAgJ6R1cIQA8AgAAAA==.Ando:BAAALgAECgEJAQABLgAECgkJKAACAGEYAA==.Andryu:BAABLgAECn8qAAICAAkJ8xLrFADUAQACAAkJ8xLrFADUAQAAAA==.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.',
Ap='Apolion:BAAALgADCgYJBgAAAA==.',
Aq='Aquastar:BAAALgAECgEJAQAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Arkanis:BAABLgAECn8vAAIDAAgJsB4kFABWAgADAAgJsB4kFABWAgAAAA==.Arïel:BAABLgAECn8jAAQEAAgJixlCDwAkAgAEAAgJhRlCDwAkAgAFAAEJfRukUQBIAAAGAAEJMAUcaAArAAAAAA==.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Banidor:BAAALgAECgIJAgAAAA==.Banthistoó:BAAALgAECgEJAgAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgAECgIJAgAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8WAAMHAAYJFAhOLAC3AAAIAAYJAwbaSADPAAAHAAYJnwZOLAC3AAAAAA==.',
Br='Broadfang:BAACLgAFFH8fAAMJAAcJpx8FAwBtAQAJAAUJliIFAwBtAQAKAAYJJRJZDwA4AQAuAAQKfyQABAkACQlPJZ0cAFoCAAoABwliIpAYAGcCAAkABgnHJJ0cAFoCAAsABAlWDjciAMMAAAAA.Broconis:BAAALgAECgUJBwAAAA==.',
Bu='Bubbleoseven:BAAALgAECgUJDwAAAA==.Bullorly:BAACLgAFFH8XAAIMAAUJFh7EMABRAQAMAAUJFh7EMABRAQAuAAQKfyEAAgwACQnpJE0EADoDAAwACQnpJE0EADoDAAAA.Bungulators:BAEALgAECgEJAQABLgAECgkJNQANAHkWAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.Catirus:BAAALgAECgEJAQAAAA==.',
Ch='Chunt:BAAALgADCgkJDQAAAA==.',
Cl='Clickshot:BAABLgAECn80AAMJAAkJ4yRvAgBEAwAJAAkJ4yRvAgBEAwAKAAQJBBL9WQDcAAAAAA==.Clipee:BAAALgAECgkJDwAAAA==.Clipeskeg:BAABLgAECn8gAAIOAAkJ3BuoCgBPAgAOAAkJ3BuoCgBPAgAAAA==.Clipex:BAAALgAECgYJBgAAAA==.',
Co='Contagium:BAAALgAECgQJCgAAAA==.',
Cr='Crunchberry:BAAALgAECgYJBwAAAA==.',
Cy='Cynîc:BAAALgAECgYJCAAAAA==.',
['Cø']='Cønståntine:BAAALgAECgEJAQAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgEJAQAAAA==.Darenas:BAABLgAECn8oAAMGAAkJlxgEFwAuAgAGAAkJlxgEFwAuAgAEAAEJpA1GVAA2AAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn8mAAQPAAkJkAhbRgAtAQAPAAkJkAhbRgAtAQACAAYJ7gZfOADYAAAQAAMJUQKiLgBSAAAAAA==.David:BAAALgADCgcJDwABLgAECgcJAQARAAAAAA==.',
De='Deathbooze:BAACLgAFFH8HAAIMAAQJnxrFKgBcAQAMAAQJnxrFKgBcAQAuAAQKfyoAAgwACAnbHlokACwCAAwACAnbHlokACwCAAAA.Deathmikee:BAABLgAECn8wAAIMAAkJkx6eDgC8AgAMAAkJkx6eDgC8AgAAAA==.Deyst:BAAALgADCgkJCQABLgAECgEJAQARAAAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECggJDgAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIGAAcJGyFPEwBaAgAGAAcJGyFPEwBaAgAAAA==.',
Dr='Draknol:BAAALgAECgYJCAAAAA==.Drakos:BAAALgAECgQJAwAAAA==.Drunknfist:BAAALgAECgYJBwAAAA==.',
Du='Durton:BAABLgAECn8lAAIIAAkJMR05GACKAgAIAAkJMR05GACKAgAAAA==.',
Ec='Echidna:BAABLgAFFH8FAAIJAAMJdBB1OwDZAAAJAAMJdBB1OwDZAAAAAA==.Echø:BAAALgADCgUJBQAAAA==.',
Ed='Edison:BAABLgAECn8xAAMIAAkJBiEoBwCtAgAIAAkJBiEoBwCtAgAHAAIJNBigQwBQAAAAAA==.Edrency:BAAALgADCgYJBgAAAA==.',
Ef='Eferis:BAAALgAECgYJBgAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAABLgAECn8vAAMSAAkJIx3WCwB3AgASAAkJIx3WCwB3AgATAAEJ7gH+iQAkAAAAAA==.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn8yAAMDAAkJFCZkAADQAwADAAkJFCZkAADQAwAUAAEJ/wYkdgAyAAAAAA==.',
Em='Emomorf:BAAALgAECgcJEgAAAA==.Employee:BAACLgAFFH8eAAIIAAcJrh2bAQD2AQAIAAcJrh2bAQD2AQAuAAQKfyIAAwgACQmvJVYBALsDAAgACQmvJVYBALsDAA0AAwmCGvoxALUAAAAA.',
Ev='Evangeliné:BAAALgAECgUJBgABLgAECgkJPAAFAAkZAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.',
Fi='Fistsofseno:BAAALgAECgkJCgAAAA==.Fizzenator:BAABLgAECn8oAAILAAkJXhxRBQCbAgALAAkJXhxRBQCbAgAAAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galatea:BAACLgAFFH8MAAIBAAQJvhw/FABsAQABAAQJvhw/FABsAQAuAAQKfyUAAgEACQnWISoOALwCAAEACQnWISoOALwCAAAA.Galifen:BAABLgAECn82AAICAAkJkSXfAABnAwACAAkJkSXfAABnAwAAAA==.Gank:BAAALgAFFAIJAgAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgAECgEJAgAAAA==.',
Ge='Gelidon:BAABLgAECn8hAAIVAAkJshlHBwBCAgAVAAkJshlHBwBCAgAAAA==.',
Gh='Ghreen:BAAALgAECgkJEgAAAA==.',
Gi='Gilgahmesh:BAABLgAECn8bAAMWAAcJuQpLGwDmAAAWAAcJuQpLGwDmAAABAAEJaQN3WAEmAAABLgAECggJJgAMAF0FAA==.',
Gn='Gnomegrown:BAABLgAECn8dAAICAAcJZBQDJQBHAQACAAcJZBQDJQBHAQAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDQAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAAALgAECggJEwAAAA==.Hankthesnake:BAAALgADCgcJGwAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgMJBAAAAA==.',
Ho='Hobbz:BAACLgAFFH8WAAIBAAYJKh3sBgDGAQABAAYJKh3sBgDGAQAuAAQKfywAAgEACQm2JB0HAF8DAAEACQm2JB0HAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgkJCgAAAA==.',
Il='Illandros:BAABLgAECn8TAAIGAAcJew3LKQAtAQAGAAcJew3LKQAtAQAAAA==.Illidankmeme:BAAALgADCgIJAgAAAA==.',
In='Ingredient:BAABLgAECn8hAAIQAAgJphJaCwCmAQAQAAgJphJaCwCmAQAAAA==.Inspire:BAAALgAECggJEQAAAA==.',
Is='Isinia:BAAALgAECgYJDwAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAAALgAECgQJCAAAAA==.Jayim:BAAALgAFFAEJAQAAAA==.Jaína:BAAALgAECgYJDQABLgAECggJIwABAL8VAA==.',
Je='Jencks:BAAALgAECgQJCAABLgAECgkJKAACAGEYAA==.',
Ji='Jiren:BAABLgAECn81AAMSAAkJMiEABAApAwASAAkJMiEABAApAwATAAMJTgktXwCTAAAAAA==.',
Jo='Johnson:BAAALgAECgYJEAAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAABLgAECn8YAAIBAAYJ8w8ZiAAUAQABAAYJ8w8ZiAAUAQAAAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAIMAAgJCw2BaABLAQAMAAgJCw2BaABLAQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
['Jë']='Jësûs:BAAALgAECgEJAQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Ki='Kiritø:BAAALgAECgQJBAAAAA==.',
Kr='Kravoxx:BAAALgADCgUJCQABLgAECgIJAgARAAAAAA==.Kro:BAAALgAECgYJEwAAAA==.Krysess:BAAALgADCgEJAQAAAA==.',
Le='Leanea:BAAALgAECgMJAwAAAA==.',
Li='Lich:BAAALgAFFAQJAgAAAA==.Liera:BAABLgAECn8cAAIMAAgJOw9TXABqAQAMAAgJOw9TXABqAQAAAA==.',
Ll='Lloydlei:BAABLgAECn8iAAMXAAkJ/xuPFwBeAgAXAAkJvRuPFwBeAgAYAAIJURxIRwCZAAAAAA==.',
Lo='Lodin:BAAALgAECgEJAQABLgAFFAMJBwAZAFgEAA==.',
Lu='Luminå:BAABLgAECn8gAAIYAAkJZhiiBwCIAQAYAAkJZhiiBwCIAQAAAA==.',
Ly='Lylenn:BAAALgADCgkJGwAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn8yAAMaAAkJByRqAwAtAwAaAAkJByRqAwAtAwAbAAYJ/RuOEwCSAQAAAA==.Malificent:BAABLgAECn8dAAIXAAcJ6x0/KwDuAQAXAAcJ6x0/KwDuAQAAAA==.Malighn:BAABLgAECn8mAAIMAAgJXQUOeAAqAQAMAAgJXQUOeAAqAQAAAA==.Masseffex:BAAALgAECgQJCQAAAA==.',
Mc='Mcshooty:BAAALgAECgEJAQAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJAwAAAA==.Mordecâi:BAAALgAECgEJAQAAAA==.Morf:BAAALgAECgMJAwABLgAECgkJIQAVALIZAA==.Morganä:BAAALgAECgQJCQAAAA==.Morthrin:BAAALgAECggJEwAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mysticdibs:BAAALgAECgEJAQAAAA==.Mystwolf:BAABLgAECn8pAAIDAAgJWhyTFABwAgADAAgJWhyTFABwAgAAAA==.',
Ne='Ned:BAAALgAECgIJAgABLgAECgQJBwARAAAAAA==.',
Ni='Niccelndime:BAAALgAECgYJDgAAAA==.Nightember:BAAALgAECgcJCAABLgAECgkJLwASACMdAA==.Nightski:BAABLgAECn8qAAIPAAkJfxcFGAA+AgAPAAkJfxcFGAA+AgAAAA==.Nikolatesla:BAAALgAECgUJBwAAAA==.Nizzari:BAACLgAFFH8HAAIZAAMJWAScHADHAAAZAAMJWAScHADHAAAuAAQKfykAAhkACQk0FVsNAAECABkACQk0FVsNAAECAAAA.',
No='Nothalyer:BAABLgAECn8sAAIVAAkJbA2vDwCGAQAVAAkJbA2vDwCGAQAAAA==.',
Of='Offline:BAABLgAECn8WAAIPAAgJth0eDwCZAgAPAAgJth0eDwCZAgAAAA==.',
Oh='Ohms:BAACLgAFFH8IAAIcAAMJcgcWYQDdAAAcAAMJcgcWYQDdAAAuAAQKfzcAAhwACQmfGuYgAF0CABwACQmfGuYgAF0CAAAA.',
Ol='Olaria:BAAALgADCgYJGQAAAA==.',
Or='Orwasitshrek:BAABLgAECn8UAAIIAAYJyhXDMQA1AQAIAAYJyhXDMQA1AQAAAA==.Orwasitwrekt:BAAALgADCgkJCQABLgAECgYJFAAIAMoVAA==.',
Pa='Palabop:BAAALgAECgYJDAAAAA==.Paladinii:BAAALgAECgMJAwAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAABLgAECn8yAAMDAAkJUBHNLACqAQADAAgJUhLNLACqAQAUAAkJVBNEIQCEAQAAAA==.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECgQJBwAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.',
Ra='Ranin:BAAALgAECgcJDAAAAA==.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJEAAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Ry='Ryzenther:BAAALgAECgYJBgAAAA==.',
Sa='Salvation:BAAALgAECgYJDwAAAA==.Sanctis:BAAALgAECgYJCQAAAA==.Santan:BAAALgADCgIJAgAAAA==.',
Sc='Scarecrow:BAAALgAECgEJAgAAAA==.',
Se='Sealgair:BAAALgAECgEJBAAAAA==.Senovourer:BAABLgAECn8fAAIaAAkJjCEJCwAqAwAaAAkJjCEJCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn8nAAMPAAkJvR4fBgAjAwAPAAkJvR4fBgAjAwAQAAEJggcSNAAwAAAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAABLgAECn8oAAIdAAgJCx2RBgAzAgAdAAgJCx2RBgAzAgAAAA==.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgAECgEJAQAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sizouze:BAABLgAECn8VAAIFAAcJXgT7NADkAAAFAAcJXgT7NADkAAAAAA==.',
Sk='Skeeter:BAAALgAECgYJBgAAAA==.Sklonda:BAAALgADCgYJBgAAAA==.Skyepic:BAACLgAFFH8bAAIeAAgJMBmsAQBzAgAeAAgJMBmsAQBzAgAuAAQKfyIAAx4ACQlgIC0HAPkCAB4ACQlgIC0HAPkCAAEABAllEn7VAOAAAAAA.Skylight:BAAALgAECgEJAQAAAA==.',
Sn='Snugwalnut:BAACLgAFFH8TAAIDAAUJ5iL+BQDrAQADAAUJ5iL+BQDrAQAuAAQKfzcAAgMACAlHI0wHAPICAAMACAlHI0wHAPICAAAA.',
So='Soejoedi:BAABLgAECn8oAAICAAkJYRgaDQA3AgACAAkJYRgaDQA3AgAAAA==.',
St='Stitchzpls:BAAALgAECgUJCQAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDgAAAA==.',
Sy='Sythar:BAAALgAECgEJAQAAAA==.',
Ta='Taintedrush:BAAALgAECgIJAwAAAA==.Tarhostamir:BAAALgAECgYJEQAAAA==.Taurup:BAAALgAECgYJBgABLgAFFAMJBwAZAFgEAA==.Tazz:BAABLgAECn8aAAIJAAYJQwfgegDpAAAJAAYJQwfgegDpAAAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaluus:BAAALgADCgUJBQAAAA==.Thaysinga:BAAALgAECgMJAwAAAA==.Thelandlord:BAACLgAFFH8UAAIVAAYJahVpBQChAQAVAAYJahVpBQChAQAuAAQKfxwAAxUACAkOG9oMAGgCABUACAkOG9oMAGgCAB8AAwnJDqIvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAABLgAECn8YAAIIAAYJXiMhGADgAQAIAAYJXiMhGADgAQAAAA==.Thuss:BAABLgAECn8dAAIaAAgJ3hdpKwDSAQAaAAgJ3hdpKwDSAQAAAA==.',
Ti='Titgunniz:BAAALgADCgYJCQAAAA==.',
Tu='Tugnutz:BAAALgAECgUJDQAAAA==.Tuk:BAAALgAECgMJAwAAAA==.',
Tw='Twirlywhirly:BAAALgAECgYJCAAAAA==.',
['Tè']='Tèmpos:BAAALgAECgMJAwAAAA==.',
Un='Unplug:BAAALgAECgQJDAAAAA==.',
Va='Vander:BAAALgAECgQJBAABLgAECgQJCAARAAAAAA==.Vanidossa:BAAALgAECgcJEwAAAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAABLgAECn82AAIGAAkJvCGrAwD0AgAGAAkJvCGrAwD0AgAAAA==.',
Ve='Veins:BAAALgAECgEJAQAAAA==.Verdict:BAABLgAECn8UAAIeAAkJsRasHADRAQAeAAkJsRasHADRAQAAAA==.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
We='Weemsy:BAABLgAECn8vAAIIAAkJFyRoAgAeAwAIAAkJFyRoAgAeAwAAAA==.',
Wi='Wildfire:BAACLgAFFH8VAAILAAUJniOhBACDAQALAAUJniOhBACDAQAuAAQKfzQAAgsACQntJooAAGADAAsACQntJooAAGADAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAUJFQALAJ4jAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAABLgAECn8hAAINAAkJbx9VAwDGAgANAAkJbx9VAwDGAgAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAABLgAECn8WAAMPAAYJhhukMwCGAQAPAAYJhhukMwCGAQACAAEJ1gJDeQAbAAAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xaxfen:BAACLgAFFH8QAAINAAYJURbxBAAoAQANAAYJURbxBAAoAQAuAAQKfx0ABA0ACAkxItcJAHoCAA0ACAkxItcJAHoCAAgAAwlMDzpSAKoAAAcAAQkAANddAAAAAAAA.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Za='Zappieboy:BAAALgAECgYJCgAAAA==.',
Zu='Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAAALgAECgYJEwAAAA==.',
['Zî']='Zîmìk:BAAALgAECgQJBgAAAA==.',
['Às']='Àsh:BAABLgAECn8uAAIFAAkJfyFwAgBIAwAFAAkJfyFwAgBIAwAAAA==.',
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
