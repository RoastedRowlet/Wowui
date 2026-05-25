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

local lookup = {'Paladin-Retribution','Druid-Balance','Shaman-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','Druid-Restoration','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warrior-Protection','Monk-Brewmaster','Monk-Windwalker','Druid-Feral','Unknown-Unknown','Monk-Mistweaver','Shaman-Elemental','DemonHunter-Havoc','Rogue-Assassination','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Rogue-Subtlety','DemonHunter-Devourer','Druid-Guardian','Paladin-Holy','Evoker-Devastation',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adolyn:BAAALgADCgkJCQAAAA==.Adventis:BAAALgADCgQJAwAAAA==.',
Al='Allavus:BAAALgADCgQJBQABLgAFFAQJEAABAL4cAA==.',
An='Andderson:BAAALgAECgEJAgAAAA==.Andersen:BAABLgAECn8jAAIBAAgJEB/EIwBWAgABAAgJEB/EIwBWAgAAAA==.Ando:BAAALgAECgEJAQABLgAECgkJLQACAG8ZAA==.Andryu:BAACLgAFFH8FAAICAAMJDgcXKQCyAAACAAMJDgcXKQCyAAAuAAQKfzMAAgIACQlcFn0OAEsCAAIACQlcFn0OAEsCAAAA.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.',
Ap='Apolion:BAAALgADCgYJBgAAAA==.',
Aq='Aquastar:BAAALgAECgEJAQAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Ardre:BAAALgADCgEJAQAAAA==.Arkanis:BAABLgAECn8zAAIDAAgJlR8IGABdAgADAAgJlR8IGABdAgAAAA==.Arïel:BAABLgAECn8kAAQEAAgJ6hlxDgBZAgAEAAgJ5BlxDgBZAgAFAAEJfRttWgBHAAAGAAEJMAXxdgAqAAAAAA==.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Backstabath:BAAALgAECgkJDgABLgAECgkJFgAHALYdAA==.Banidor:BAAALgAECgIJAgAAAA==.Banthistoó:BAAALgAECgQJBgAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgAECgIJAgAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8WAAMIAAYJFAhQNwC2AAAJAAYJAwa+VQDKAAAIAAYJnwZQNwC2AAAAAA==.',
Br='Broadfang:BAACLgAFFH8lAAMKAAgJQB8FAwBtAQAKAAUJ9yIFAwBtAQALAAcJrBNZDwA4AQAuAAQKfyQABAoACQlPJZ0cAFoCAAsABwliIpAYAGcCAAoABgnHJJ0cAFoCAAwABAlWDjciAMMAAAAA.Broconis:BAAALgAECgUJBwAAAA==.',
Bu='Bubbleoseven:BAAALgAECgUJDwAAAA==.Bullorly:BAACLgAFFH8cAAINAAUJ4SHDKAB4AQANAAUJ4SHDKAB4AQAuAAQKfyEAAg0ACQnqJGEGACwDAA0ACQnqJGEGACwDAAAA.Bungulators:BAEALgAECgEJAQABLgAECgkJPAAOAMUWAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.Catirus:BAAALgAECgEJAQAAAA==.',
Ch='Chunt:BAAALgAECgEJAQAAAA==.',
Cl='Clickshot:BAACLgAFFH8HAAIKAAMJah4bNQAQAQAKAAMJah4bNQAQAQAuAAQKfz0AAwoACQkYJmkBAHEDAAoACQkYJmkBAHEDAAsABAkEEv1ZANwAAAAA.Clipe:BAAALgAECgYJBgAAAA==.Clipee:BAAALgAECgkJDwAAAA==.Clipeskeg:BAABLgAECn8jAAMPAAkJQhzmCwBXAgAPAAkJQhzmCwBXAgAQAAEJFwt/dwA9AAAAAA==.Clipex:BAAALgAECgYJBgAAAA==.',
Co='Connor:BAAALgAECgEJAQAAAA==.Contagium:BAAALgAECgQJCgAAAA==.',
Cr='Crunchberry:BAAALgAECgYJCAAAAA==.',
Cy='Cynîc:BAAALgAECgYJCAAAAA==.',
['Cø']='Cønståntine:BAAALgAECgEJAQAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgYJBgAAAA==.Darenas:BAABLgAECn8oAAMGAAkJlxgEFwAuAgAGAAkJlxgEFwAuAgAEAAEJpA0JYQA2AAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn8mAAQHAAkJjwiXTwAtAQAHAAkJjwiXTwAtAQACAAYJ7gZ4QgDRAAARAAMJUQKiLgBSAAAAAA==.David:BAAALgADCgcJDwABLgAECgkJLAAMAJkgAA==.',
De='Deathbooze:BAACLgAFFH8MAAINAAUJEx2qJwB7AQANAAUJEx2qJwB7AQAuAAQKfyoAAg0ACAnbHoctACYCAA0ACAnbHoctACYCAAAA.Deathmikee:BAABLgAECn8wAAINAAkJkx6mFACrAgANAAkJkx6mFACrAgAAAA==.Demonrush:BAAALgAECgEJAQAAAA==.Deyst:BAAALgADCgkJCQABLgAECgEJAQASAAAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECggJDgAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIGAAcJGyFPEwBaAgAGAAcJGyFPEwBaAgAAAA==.',
Dr='Draknol:BAAALgAECgYJCAAAAA==.Drakos:BAAALgAECgQJAwAAAA==.Drunknfist:BAAALgAECgYJBwAAAA==.',
Du='Durton:BAACLgAFFH8GAAIJAAMJ7hcDJADuAAAJAAMJ7hcDJADuAAAuAAQKfycAAgkACQlBHTkYAIoCAAkACQlBHTkYAIoCAAAA.',
Ec='Echidna:BAABLgAFFH8GAAIKAAMJ+xVdQwDjAAAKAAMJ+xVdQwDjAAABLgAFFAUJCgATALwRAA==.Echø:BAAALgADCgUJBQAAAA==.',
Ed='Edison:BAACLgAFFH8HAAIJAAMJTR5YGgAlAQAJAAMJTR5YGgAlAQAuAAQKfzMAAwkACQkGIXUKAJwCAAkACQkGIXUKAJwCAAgAAgk0GDNTAE4AAAAA.Edrency:BAAALgADCgYJBgAAAA==.',
Ef='Eferis:BAAALgAECgkJDwAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAACLgAFFH8FAAITAAMJ6BAtJwC7AAATAAMJ6BAtJwC7AAAuAAQKfy8AAxMACQkjHUMPAHgCABMACQkjHUMPAHgCABAAAQnuAf6JACQAAAAA.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn87AAMDAAkJGiZ9AADOAwADAAkJGiZ9AADOAwAUAAEJ/wZjhwAyAAAAAA==.',
Em='Emomorf:BAABLgAECn8YAAIVAAcJRxBwJAAaAQAVAAcJRxBwJAAaAQAAAA==.Employee:BAACLgAFFH8eAAIJAAcJtx01AwDkAQAJAAcJtx01AwDkAQAuAAQKfyIAAwkACQmvJVYBALsDAAkACQmvJVYBALsDAA4AAwmCGvoxALUAAAAA.',
Ev='Evangeliné:BAAALgAECgYJDAABLgAECgkJQwAFAAkZAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.',
Fe='Femboi:BAAALgAECgkJBgAAAA==.',
Fi='Fistsofseno:BAAALgAECgkJCgAAAA==.Fizzenator:BAACLgAFFH8FAAIMAAMJihxtEwANAQAMAAMJihxtEwANAQAuAAQKfygAAgwACQlfHIoHAI0CAAwACQlfHIoHAI0CAAAA.',
Fr='Freshlight:BAAALgAECgUJBQABLgAECgkJNQATADIhAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galatea:BAACLgAFFH8QAAIBAAQJvhxnHgBaAQABAAQJvhxnHgBaAQAuAAQKfyoAAgEACQmbIoYIAA0DAAEACQmbIoYIAA0DAAAA.Galifen:BAACLgAFFH8FAAICAAMJ/yMxFAA/AQACAAMJ/yMxFAA/AQAuAAQKfz4AAgIACQn/JcMAAHwDAAIACQn/JcMAAHwDAAAA.Gank:BAABLgAFFH8FAAIWAAMJDhdaBQAGAQAWAAMJDhdaBQAGAQAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgAECgEJAgAAAA==.',
Ge='Gelidon:BAABLgAECn8mAAMXAAkJshnZCAA9AgAXAAkJshnZCAA9AgAYAAQJtgryTQDKAAAAAA==.Getoutalive:BAAALgADCgEJAQAAAA==.',
Gh='Ghreen:BAABLgAECn8UAAIQAAkJFRt6CgB3AgAQAAkJFRt6CgB3AgAAAA==.',
Gi='Gilgahmesh:BAABLgAECn8iAAMZAAgJTgyyFwAyAQAZAAgJTgyyFwAyAQABAAEJaQN3WAEmAAABLgAECgkJMQANAFIJAA==.',
Gn='Gnomegrown:BAABLgAECn8jAAICAAcJ6xWaJwBiAQACAAcJ6xWaJwBiAQAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDQAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAAALgAECggJEwAAAA==.Hamalainen:BAAALgAECgEJAQABLgAECgkJNQATADIhAA==.Hankthesnake:BAAALgADCgcJGwAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgMJBQAAAA==.',
Ho='Hobbz:BAACLgAFFH8ZAAIBAAYJLR3HAwC2AQABAAYJLR3HAwC2AQAuAAQKfywAAgEACQm2JB0HAF8DAAEACQm2JB0HAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgkJCgAAAA==.',
Il='Illandros:BAABLgAECn8bAAIGAAgJVQ8jJACAAQAGAAgJVQ8jJACAAQAAAA==.Illidankmeme:BAAALgADCgIJAgAAAA==.',
In='Ingredient:BAABLgAECn8nAAIRAAkJMBOkCgDgAQARAAkJMBOkCgDgAQAAAA==.Inspire:BAABLgAECn8VAAIHAAgJ9xwwIwAvAgAHAAgJ9xwwIwAvAgAAAA==.',
Is='Isinia:BAAALgAECgYJEwAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAAALgAECgUJCgAAAA==.Jayim:BAAALgAFFAEJAwAAAA==.Jaína:BAABLgAECn8ZAAIaAAgJ/gv3bACEAQAaAAgJ/gv3bACEAQABLgAECggJJgABAOEZAA==.',
Jc='Jcvd:BAAALgADCgQJBAABLgAECgkJNQATADIhAA==.',
Je='Jencks:BAAALgAECgUJCQABLgAECgkJLQACAG8ZAA==.',
Ji='Jiren:BAABLgAECn81AAMTAAkJMiGDBQAjAwATAAkJMiGDBQAjAwAQAAMJTgktXwCTAAAAAA==.',
Jo='Johnson:BAABLgAECn8WAAIOAAYJrhybEgCZAQAOAAYJrhybEgCZAQAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAABLgAECn8fAAIBAAcJrhKZcwBnAQABAAcJrhKZcwBnAQAAAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAINAAgJCw3SegBIAQANAAgJCw3SegBIAQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
['Jë']='Jësûs:BAAALgAECgEJAQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Kr='Kravoxx:BAAALgADCgUJCQABLgAECgIJAgASAAAAAA==.Kro:BAABLgAECn8aAAIBAAcJkhQpbAB2AQABAAcJkhQpbAB2AQAAAA==.Krysess:BAAALgADCgEJAQAAAA==.',
Le='Leanea:BAAALgAECgMJAwAAAA==.',
Li='Lich:BAAALgAFFAQJAgAAAA==.Liera:BAABLgAECn8kAAINAAgJbRWQQwDWAQANAAgJbRWQQwDWAQAAAA==.',
Ll='Lloydlei:BAABLgAECn8pAAQbAAkJ/xuuHwBOAgAbAAkJvRuuHwBOAgAcAAMJEhdZIACDAAAdAAIJABFEHwB+AAAAAA==.',
Lo='Lodin:BAAALgAECgcJBwABLgAFFAQJCQAeAJEEAA==.',
Lu='Luminå:BAABLgAECn8gAAIcAAkJZhgpCQCIAQAcAAkJZhgpCQCIAQAAAA==.',
Ly='Lylenn:BAAALgADCgkJGwAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn8+AAMfAAkJ/SVoBAAvAwAfAAkJDSRoBAAvAwAVAAgJPCZ3AgAXAwAAAA==.Malificent:BAABLgAECn8dAAIbAAcJ7R2XNADuAQAbAAcJ7R2XNADuAQAAAA==.Malighn:BAABLgAECn8xAAINAAkJUgmqVwCaAQANAAkJUgmqVwCaAQAAAA==.Masseffex:BAAALgAECgUJCwAAAA==.',
Mc='Mcshooty:BAAALgAECgQJBgAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJBAAAAA==.Mordecâi:BAAALgAECgEJAQAAAA==.Morf:BAAALgAECgMJAwABLgAECgkJJgAXALIZAA==.Morganä:BAAALgAECgQJCgAAAA==.Morthrin:BAABLgAECn8UAAIHAAgJcRX+KgDdAQAHAAgJcRX+KgDdAQAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mysticdibs:BAAALgAECgEJAQAAAA==.Mystwolf:BAABLgAECn8wAAIDAAgJzB6TFABwAgADAAgJzB6TFABwAgAAAA==.',
Ne='Ned:BAAALgAECgIJAgABLgAECgQJCAASAAAAAA==.',
Ni='Niccelndime:BAABLgAECn8VAAIMAAYJ5xsRHQCVAQAMAAYJ5xsRHQCVAQAAAA==.Nightember:BAAALgAECgkJEQABLgAFFAMJBQATAOgQAA==.Nightski:BAABLgAECn8qAAIHAAkJgBeNHAA9AgAHAAkJgBeNHAA9AgAAAA==.Nikolatesla:BAAALgAECgcJDQAAAA==.Nizzari:BAACLgAFFH8JAAIeAAQJkQRQGwAFAQAeAAQJkQRQGwAFAQAuAAQKfy8AAx4ACQk1FSQRAPwBAB4ACQk1FSQRAPwBABYAAQmHCfUgADkAAAAA.',
No='Nothalyer:BAABLgAECn8sAAIXAAkJbQ09EgCCAQAXAAkJbQ09EgCCAQAAAA==.',
Of='Offline:BAABLgAECn8WAAIHAAgJth14EgCYAgAHAAgJth14EgCYAgAAAA==.',
Oh='Ohms:BAACLgAFFH8IAAIaAAMJcgfBcADRAAAaAAMJcgfBcADRAAAuAAQKfzcAAhoACQmeGhcrAFACABoACQmeGhcrAFACAAAA.',
Ol='Olaria:BAAALgADCgYJGQAAAA==.',
Or='Orwasitshrek:BAABLgAECn8eAAIJAAgJmBMWJACvAQAJAAgJmBMWJACvAQAAAA==.Orwasitwrekt:BAAALgADCgkJCQABLgAECggJHgAJAJgTAA==.',
Pa='Palabop:BAAALgAECgYJEQAAAA==.Paladinii:BAAALgAECgMJAwAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAACLgAFFH8IAAIUAAUJ+ApZHwD+AAAUAAUJ+ApZHwD+AAAuAAQKfzIAAwMACQlREYw2AKUBAAMACAlSEow2AKUBABQACQlUE7MoAHwBAAAA.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECgQJCAAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQASAAAAAA==.',
Ra='Ranin:BAAALgAECgcJDAAAAA==.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Ricklepick:BAAALgAECgYJBgABLgAECgkJNQATADIhAA==.Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJEAAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Ry='Ryzenther:BAAALgAECgYJCQAAAA==.',
Sa='Salvation:BAAALgAECgYJDwAAAA==.Sanctis:BAAALgAECgYJCQAAAA==.Santan:BAAALgADCgIJAgAAAA==.Satrat:BAAALgAECgEJAQAAAA==.',
Sc='Scarecrow:BAAALgAECgEJAgAAAA==.',
Se='Sealgair:BAAALgAECgEJBQAAAA==.Senovourer:BAABLgAECn8fAAIfAAkJjCEJCwAqAwAfAAkJjCEJCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn8wAAMHAAkJZiBHBQBMAwAHAAkJZiBHBQBMAwARAAEJggd2PgAwAAAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAABLgAECn83AAIgAAgJ4yDVBACUAgAgAAgJ4yDVBACUAgAAAA==.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgAECgEJAQAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sindora:BAAALgADCgYJBgAAAA==.Sizouze:BAABLgAECn8bAAIFAAcJwgWaOQDuAAAFAAcJwgWaOQDuAAAAAA==.',
Sk='Skeeter:BAAALgAECgYJBgAAAA==.Sklonda:BAAALgADCgYJBgAAAA==.Skyepic:BAACLgAFFH8bAAIhAAgJKRlWAwBTAgAhAAgJKRlWAwBTAgAuAAQKfyIAAyEACQlgIC0HAPkCACEACQlgIC0HAPkCAAEABAllEn7VAOAAAAAA.Skylight:BAAALgAECgEJAQAAAA==.',
Sn='Snugwalnut:BAACLgAFFH8YAAIDAAUJ5iJ8CQDhAQADAAUJ5iJ8CQDhAQAuAAQKfzcAAgMACAlHIx0KAOsCAAMACAlHIx0KAOsCAAAA.',
So='Soejoedi:BAABLgAECn8tAAICAAkJbxnMDQBVAgACAAkJbxnMDQBVAgAAAA==.',
Sp='Spicyburrito:BAAALgADCgcJBwAAAA==.',
St='Stitchzpls:BAAALgAECgUJCQAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDwAAAA==.',
Sy='Sythar:BAAALgAECgEJAQAAAA==.',
Ta='Taintedrush:BAAALgAECgIJBAAAAA==.Talan:BAAALgAECgMJAwABLgAECgUJCgASAAAAAA==.Tarhostamir:BAABLgAECn8XAAICAAcJjQ8FLgA6AQACAAcJjQ8FLgA6AQAAAA==.Taurup:BAAALgAECgYJCAABLgAFFAQJCQAeAJEEAA==.Tazz:BAABLgAECn8bAAIKAAYJQwfxkADqAAAKAAYJQwfxkADqAAAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaluus:BAAALgADCgYJCgAAAA==.Thaysinga:BAAALgAECgQJBAAAAA==.Thelandlord:BAACLgAFFH8UAAIXAAYJahVpBQChAQAXAAYJahVpBQChAQAuAAQKfxwAAxcACAkOG9oMAGgCABcACAkOG9oMAGgCACIAAwnJDqIvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAABLgAECn8fAAIJAAcJBCM3EQBKAgAJAAcJBCM3EQBKAgAAAA==.Thuss:BAABLgAECn8lAAIfAAkJbBiJIgApAgAfAAkJbBiJIgApAgAAAA==.',
Ti='Titgunniz:BAAALgADCgYJCQAAAA==.',
Tu='Tugnutz:BAAALgAECgUJDQAAAA==.Tuk:BAAALgAECgMJAwAAAA==.',
Tw='Twirlywhirly:BAAALgAECgYJCQAAAA==.',
['Tè']='Tèmpos:BAAALgAECgMJAwAAAA==.',
Ul='Ulansiola:BAAALgADCgYJBgABLgADCgcJGwASAAAAAA==.',
Un='Unplug:BAAALgAECgQJDAAAAA==.',
Va='Vander:BAAALgAECgQJBAABLgAECgUJCgASAAAAAA==.Vanidossa:BAAALgAECgcJEwAAAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAACLgAFFH8FAAIGAAMJLhOqGgDtAAAGAAMJLhOqGgDtAAAuAAQKfz8AAgYACQkXInADABYDAAYACQkXInADABYDAAAA.',
Ve='Veins:BAAALgAECgEJAQAAAA==.Verdict:BAACLgAFFH8IAAIhAAMJnBMGJgDEAAAhAAMJnBMGJgDEAAAuAAQKfxYAAiEACQkCFzciAMwBACEACQkCFzciAMwBAAAA.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
We='Weemsy:BAABLgAECn81AAIJAAkJXiQjAwAiAwAJAAkJXiQjAwAiAwAAAA==.',
Wi='Wildfire:BAACLgAFFH8ZAAIMAAUJniOSBgB7AQAMAAUJniOSBgB7AQAuAAQKfzQAAgwACQntJu8AAFQDAAwACQntJu8AAFQDAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAUJGQAMAJ4jAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAABLgAECn8qAAIOAAkJbx+9BAC3AgAOAAkJbx+9BAC3AgAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAABLgAECn8WAAMHAAYJhhsUOwCGAQAHAAYJhhsUOwCGAQACAAEJ1gJ6igAaAAAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xaxfen:BAACLgAFFH8RAAIOAAYJURbxBAAoAQAOAAYJURbxBAAoAQAuAAQKfyQABA4ACAlzItcJAHoCAA4ACAlzItcJAHoCAAkABQlEFJBHAP4AAAgAAQkAAPpvAAAAAAAA.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Yo='Yogurt:BAAALgAECgIJAgAAAA==.',
Za='Zappieboy:BAAALgAECgcJDAAAAA==.',
Ze='Zeurie:BAAALgAFFAMJBAAAAA==.',
Zu='Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAAALgAECgYJEwAAAA==.',
['Zî']='Zîmìk:BAAALgAECgQJBgAAAA==.',
['Às']='Àsh:BAABLgAECn8xAAIFAAkJmiKaAgBbAwAFAAkJmiKaAgBbAwAAAA==.',
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
