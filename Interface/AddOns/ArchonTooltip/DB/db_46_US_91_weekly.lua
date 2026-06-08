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

local lookup = {'Paladin-Retribution','Druid-Balance','Unknown-Unknown','Shaman-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','Druid-Restoration','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warlock-Demonology','Warrior-Protection','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Druid-Feral','DeathKnight-Blood','Druid-Guardian','Shaman-Elemental','DemonHunter-Havoc','Rogue-Assassination','Rogue-Subtlety','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Mage-Frost','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Rogue-Outlaw','Paladin-Holy',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Adolyn:BAAALgADCgkJCQAAAA==.Adventis:BAAALgADCgQJAwAAAA==.',
Al='Allavus:BAAALgADCgQJBQABLgAFFAUJEwABAL4cAA==.Alodiar:BAAALgAECgMJAwAAAA==.',
Am='Amrin:BAAALgAECgkJBgAAAA==.',
An='Andderson:BAAALgAECgEJAgAAAA==.Andersen:BAABLgAECn8jAAIBAAgJEB+uKwBIAgABAAgJEB+uKwBIAgAAAA==.Ando:BAAALgAECgEJAQABLgAECgkJLQACAG8ZAA==.Andryu:BAACLgAFFH8MAAICAAQJpQmkKgDMAAACAAQJpQmkKgDMAAAuAAQKf0UAAgIACQm7HDMJALgCAAIACQm7HDMJALgCAAAA.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.',
Ap='Apolion:BAAALgADCgYJBgAAAA==.',
Aq='Aquastar:BAAALgAECgEJAQAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Ardre:BAAALgADCgEJAQABLgAECgMJAwADAAAAAA==.Arkanis:BAABLgAECn80AAIEAAkJ3Rw9FwCEAgAEAAkJ3Rw9FwCEAgAAAA==.Arïel:BAABLgAECn8pAAQFAAgJYxvWDgB1AgAFAAgJXhvWDgB1AgAGAAEJfRsTYwBFAAAHAAEJMAWPiAAqAAAAAA==.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Backstabath:BAAALgAECgkJDgABLgAECgkJFwAIAM4hAA==.Banidor:BAAALgAECgIJAgAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgAECgIJAgAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8WAAMJAAYJFAhJQgCyAAAKAAYJAwaoYADIAAAJAAYJnwZJQgCyAAAAAA==.',
Br='Broadfang:BAACLgAFFH8lAAMLAAgJQB8FAwBtAQALAAUJ9yIFAwBtAQAMAAcJrBNZDwA4AQAuAAQKfyQABAsACQlPJZ0cAFoCAAwABwliIpAYAGcCAAsABgnHJJ0cAFoCAA0ABAlWDjciAMMAAAAA.Broconis:BAAALgAECgUJBwABLgAFFAYJAwADAAAAAA==.',
Bu='Bubbleoseven:BAAALgAECgUJEAAAAA==.Bullorly:BAACLgAFFH8iAAIOAAYJISGjIADJAQAOAAYJISGjIADJAQAuAAQKfyEAAg4ACQnqJAMJACIDAA4ACQnqJAMJACIDAAAA.Bullwînkle:BAAALgADCgcJBwABLgAECgcJFwAPAM4FAA==.Bungulators:BAEALgAECgEJAQABLgAECgkJRwAQABcaAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.Catirus:BAAALgAECgEJAQAAAA==.',
Ch='Chunt:BAAALgAECgEJAQAAAA==.',
Cl='Clickshot:BAACLgAFFH8OAAILAAQJHiT4FACdAQALAAQJHiT4FACdAQAuAAQKf0wAAwsACQk/JtEBAHIDAAsACQk/JtEBAHIDAAwABAkEEv1ZANwAAAAA.Clipe:BAAALgAECgcJCwAAAA==.Clipee:BAAALgAECgkJEgAAAA==.Clipeskeg:BAABLgAECn8jAAMRAAkJQhzrDQBQAgARAAkJQhzrDQBQAgASAAEJFws5jAA6AAAAAA==.Clipex:BAAALgAECgkJEAAAAA==.',
Co='Connor:BAAALgAFFAEJAQAAAA==.Contagium:BAAALgAECgQJCgAAAA==.',
Cr='Crunchberry:BAAALgAFFAIJAgAAAA==.Cryptus:BAAALgADCgMJAQABLgAECggJHQATABcgAA==.',
Cy='Cynîc:BAAALgAECgcJCQAAAA==.',
['Cø']='Cønståntine:BAAALgAECgEJAQAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgYJBgAAAA==.Darenas:BAABLgAECn8oAAMHAAkJlxgEFwAuAgAHAAkJlxgEFwAuAgAFAAEJpA2ddQAtAAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn82AAQIAAkJjw8xOQCoAQAIAAkJjw8xOQCoAQACAAYJNAhBSgDUAAAUAAMJUQKiLgBSAAAAAA==.David:BAAALgADCgcJDwABLgAECgkJLwANAEkiAA==.',
De='Deathbooze:BAACLgAFFH8SAAIOAAUJ9yCyOAB1AQAOAAUJ9yCyOAB1AQAuAAQKfywAAg4ACQl2IXIUAMUCAA4ACQl2IXIUAMUCAAAA.Deathmikee:BAACLgAFFH8JAAMVAAQJpxf3GgD6AAAVAAMJ5xv3GgD6AAAOAAMJnBCvkADbAAAuAAQKf0IAAg4ACQkEIjkJACADAA4ACQkEIjkJACADAAAA.Demonea:BAAALgAECgEJAQAAAA==.Demonrush:BAAALgAECgEJAQABLgAFFAEJAgADAAAAAA==.Deyst:BAAALgADCgkJCQABLgAECgEJAQADAAAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECgkJDwAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIHAAcJGyFPEwBaAgAHAAcJGyFPEwBaAgAAAA==.',
Dr='Draknol:BAABLgAECn8YAAINAAgJswT9KwA/AQANAAgJswT9KwA/AQAAAA==.Drakos:BAAALgAECgcJBwAAAA==.Drunknfist:BAAALgAECgYJBwAAAA==.',
Du='Durton:BAACLgAFFH8JAAIKAAMJlhnbKgDyAAAKAAMJlhnbKgDyAAAuAAQKfycAAgoACQlBHTkYAIoCAAoACQlBHTkYAIoCAAAA.',
Ec='Echidna:BAABLgAFFH8GAAILAAMJ+xVKWQDfAAALAAMJ+xVKWQDfAAABLgAFFAUJDgAWAMAWAA==.Echø:BAAALgADCgUJBQAAAA==.',
Ed='Edison:BAACLgAFFH8KAAIKAAMJ1SR2GwA1AQAKAAMJ1SR2GwA1AQAuAAQKfzUAAwoACQlyIckLAKUCAAoACQlyIckLAKUCAAkAAwmAGydDAK4AAAAA.Edrency:BAAALgADCgYJBgAAAA==.',
Ef='Eferis:BAAALgAECgkJDwAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAACLgAFFH8MAAITAAQJgRCZKwDpAAATAAQJgRCZKwDpAAAuAAQKfzAAAxMACQlMHTkSAHsCABMACQlMHTkSAHsCABIAAQnuAf6JACQAAAAA.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn9NAAMEAAkJVCZ/AADcAwAEAAkJVCZ/AADcAwAXAAEJ/wb4mgAyAAAAAA==.',
Em='Emomorf:BAABLgAECn8YAAIYAAcJRxCfKwAPAQAYAAcJRxCfKwAPAQAAAA==.Employee:BAACLgAFFH8eAAIKAAcJtx0TAwDGAQAKAAcJtx0TAwDGAQAuAAQKfyIAAwoACQmvJVYBALsDAAoACQmvJVYBALsDABAAAwmCGvoxALUAAAAA.',
Es='Estias:BAAALgAECgYJBgAAAA==.',
Ev='Evangeliné:BAABLgAECn8UAAIBAAYJ0gQ29QC3AAABAAYJ0gQ29QC3AAABLgAECgkJRQAGAHkZAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.',
Fe='Femboi:BAAALgAECgkJEQAAAA==.',
Fi='Fistsofseno:BAAALgAECgkJCgAAAA==.Fizzenator:BAACLgAFFH8HAAINAAMJihzXGQDuAAANAAMJihzXGQDuAAAuAAQKfygAAg0ACQlfHJYJAIACAA0ACQlfHJYJAIACAAAA.',
Fr='Freshlight:BAAALgAECgYJBgABLgAFFAQJBwATAMoYAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galatea:BAACLgAFFH8TAAIBAAUJvhz3LQBFAQABAAUJvhz3LQBFAQAuAAQKfyoAAgEACQmbIg8MAPwCAAEACQmbIg8MAPwCAAAA.Galifen:BAACLgAFFH8MAAICAAQJZSX3CwC4AQACAAQJZSX3CwC4AQAuAAQKf1AAAgIACQl9JlUAAJIDAAIACQl9JlUAAJIDAAAA.Gank:BAABLgAFFH8JAAMZAAQJiBjaBQATAQAZAAMJcx/aBQATAQAaAAEJyANYOQBDAAAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgAECgEJAgAAAA==.',
Ge='Gelidon:BAABLgAECn8xAAMbAAkJshn4CQA9AgAbAAkJshn4CQA9AgAcAAgJZQzbMgBeAQAAAA==.Getoutalive:BAAALgADCgEJAQAAAA==.',
Gh='Ghreen:BAABLgAECn8UAAISAAkJFRstDQBoAgASAAkJFRstDQBoAgAAAA==.',
Gi='Gilgahmesh:BAABLgAECn8sAAMdAAgJdwxuGwAuAQAdAAgJdwxuGwAuAQABAAEJaQN3WAEmAAABLgAFFAMJBQAOAFUCAA==.',
Gn='Gnomegrown:BAABLgAECn8xAAICAAgJwBdXGgDsAQACAAgJwBdXGgDsAQAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDwAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAABLgAECn8YAAMbAAkJaw1KFgBiAQAbAAcJDg5KFgBiAQAcAAYJjATlYwChAAAAAA==.Hamalainen:BAAALgAECgEJAgABLgAFFAQJBwATAMoYAA==.Hankthesnake:BAAALgADCgcJGwABLgAECgIJAgADAAAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgMJBQAAAA==.',
Hi='Highcurious:BAAALgAECgEJAQABLgAFFAQJBwATAMoYAA==.',
Ho='Hobbz:BAACLgAFFH8hAAIBAAcJfBlGCwD4AQABAAcJfBlGCwD4AQAuAAQKfy8AAgEACQm2JB0HAF8DAAEACQm2JB0HAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgkJCgAAAA==.',
['Hó']='Hólythunder:BAAALgAECgIJAgAAAA==.',
Il='Illandros:BAABLgAECn8nAAIHAAgJ4RJ2IwClAQAHAAgJ4RJ2IwClAQAAAA==.Illidankmeme:BAAALgADCgIJAgAAAA==.',
In='Ingredient:BAABLgAECn8oAAIUAAkJzxMUCwD7AQAUAAkJzxMUCwD7AQAAAA==.Inspire:BAACLgAFFH8JAAMIAAYJLBsPDgABAgAIAAYJLBsPDgABAgACAAMJHQZDMgChAAAuAAQKfxUAAggACAn3HDAjAC8CAAgACAn3HDAjAC8CAAAA.',
Is='Isinia:BAABLgAECn8XAAIPAAcJzgXCowD0AAAPAAcJzgXCowD0AAAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAABLgAECn8dAAITAAgJFyB7CgDgAgATAAgJFyB7CgDgAgAAAA==.Jayim:BAABLgAFFH8GAAIIAAMJvAEvTwB4AAAIAAMJvAEvTwB4AAAAAA==.Jaína:BAABLgAECn8aAAIeAAgJ/gtaewB7AQAeAAgJ/gtaewB7AQABLgAECggJJwABAAccAA==.',
Jc='Jcvd:BAAALgADCgQJBAABLgAFFAQJBwATAMoYAA==.',
Je='Jencks:BAAALgAECgUJCQABLgAECgkJLQACAG8ZAA==.',
Ji='Jiren:BAACLgAFFH8HAAITAAQJyhjJIgAoAQATAAQJyhjJIgAoAQAuAAQKfzYAAxMACQmSIXIGAC4DABMACQmSIXIGAC4DABIAAwlOCS1fAJMAAAAA.',
Jo='Johnson:BAABLgAECn8fAAIQAAgJSht+DAAYAgAQAAgJSht+DAAYAgAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAABLgAECn8rAAIBAAgJ9BTPUADLAQABAAgJ9BTPUADLAQAAAA==.Jormungandr:BAAALgAECgIJAgABLgAFFAQJBwATAMoYAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAIOAAgJCw3OigBGAQAOAAgJCw3OigBGAQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
['Jë']='Jësûs:BAAALgAECgEJAQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Ki='Killnoobs:BAAALgADCgEJAQAAAA==.',
Kr='Kravoxx:BAAALgADCgUJCQABLgAECgIJAgADAAAAAA==.Kro:BAABLgAECn8kAAIBAAgJ/BNHWwCxAQABAAgJ/BNHWwCxAQAAAA==.Krysess:BAAALgADCgEJAQAAAA==.Krèios:BAAALgAECgcJCAABLgAFFAQJEAAfAB8OAA==.',
Le='Leanea:BAAALgAECgMJAwAAAA==.Lenayuh:BAAALgAECgUJBwAAAA==.',
Li='Lich:BAAALgAFFAQJAgAAAA==.Liera:BAABLgAECn8sAAIOAAkJxRgPJQBnAgAOAAkJxRgPJQBnAgAAAA==.',
Ll='Lloydlei:BAABLgAECn8yAAQPAAkJBh1AHAB1AgAPAAkJdxxAHAB1AgAgAAQJ5hVGFAAaAQAhAAMJEhdgJACBAAAAAA==.',
Lo='Lodin:BAAALgAECgcJBwABLgAFFAUJDgAaANQHAA==.',
Lu='Luminå:BAABLgAECn8gAAIhAAkJZhgPCwCAAQAhAAkJZhgPCwCAAQAAAA==.',
Ly='Lylenn:BAAALgADCgkJGwAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn9QAAMYAAkJLSbBAAB4AwAYAAkJLSbBAAB4AwAfAAkJDiUwAwBOAwAAAA==.Malificent:BAABLgAECn8dAAIPAAcJ7R2QOwDnAQAPAAcJ7R2QOwDnAQAAAA==.Malighn:BAACLgAFFH8FAAIOAAMJVQIgsACpAAAOAAMJVQIgsACpAAAuAAQKfzEAAg4ACQlSCbpjAJgBAA4ACQlSCbpjAJgBAAAA.Masseffex:BAABLgAECn8VAAMCAAgJzRRoHwC/AQACAAgJzRRoHwC/AQAIAAIJAw9tnQBsAAAAAA==.',
Mc='Mcshooty:BAAALgAECgYJDAAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJBAAAAA==.Mordecâi:BAAALgAECgEJAQAAAA==.Morf:BAAALgAECgMJAwABLgAECgkJMQAbALIZAA==.Morganä:BAAALgAECgQJDgAAAA==.Morthrin:BAABLgAECn8VAAIIAAkJ5hQ9JgATAgAIAAkJ5hQ9JgATAgAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mysticdibs:BAAALgAECgEJAQAAAA==.Mystwolf:BAABLgAECn80AAIEAAgJVx+TFABwAgAEAAgJVx+TFABwAgAAAA==.',
Ne='Ned:BAAALgAECgcJCAABLgAECggJDwADAAAAAA==.Negora:BAAALgAECgEJAQAAAA==.Nelaris:BAAALgADCgEJAQAAAA==.',
Ni='Niccelndime:BAABLgAECn8VAAINAAYJ5BsQIQCQAQANAAYJ5BsQIQCQAQAAAA==.Nightember:BAABLgAECn8iAAQcAAkJjQ/iIADKAQAcAAkJjQ/iIADKAQAbAAgJoRHBDwDIAQAiAAEJgAkhJgAuAAABLgAFFAQJDAATAIEQAA==.Nightski:BAABLgAECn8qAAIIAAkJgBfUHwA/AgAIAAkJgBfUHwA/AgAAAA==.Nikolatesla:BAAALgAECgcJDgAAAA==.Nizzari:BAACLgAFFH8OAAIaAAUJ1AeiHgAbAQAaAAUJ1AeiHgAbAQAuAAQKfzsABBoACQk1FYYUAPEBABoACQk1FYYUAPEBABkAAQmHCeYlADMAACMAAQmUB3gkACgAAAAA.',
No='Nomas:BAAALgAECgYJBgAAAA==.Nothalyer:BAABLgAECn8zAAIbAAkJyQ4zEgCdAQAbAAkJyQ4zEgCdAQAAAA==.',
Of='Offline:BAABLgAECn8XAAIIAAgJziH4CwD4AgAIAAgJziH4CwD4AgAAAA==.',
Oh='Ohms:BAACLgAFFH8IAAIeAAMJcgfChADFAAAeAAMJcgfChADFAAAuAAQKfzcAAh4ACQmeGiMzAEUCAB4ACQmeGiMzAEUCAAAA.',
Ol='Olaria:BAAALgADCgYJGQAAAA==.',
Or='Orwasithim:BAAALgADCgYJBgABLgAECggJIAAKAJsTAA==.Orwasitme:BAAALgADCgcJCAABLgAECggJIAAKAJsTAA==.Orwasitshrek:BAABLgAECn8gAAIKAAgJmxMvKgCnAQAKAAgJmxMvKgCnAQAAAA==.Orwasitwrekt:BAAALgADCgkJCQABLgAECggJIAAKAJsTAA==.',
Pa='Palabop:BAAALgAECgYJEQAAAA==.Paladinii:BAAALgAFFAEJAQAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAACLgAFFH8PAAMEAAYJzAKRLwANAQAEAAYJzAKRLwANAQAXAAUJZQx3JgD0AAAuAAQKfzIAAwQACQlREao/AKEBAAQACAlSEqo/AKEBABcACQlUEyQvAHYBAAAA.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECggJDwAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.',
Ra='Ranin:BAAALgAECgcJDAAAAA==.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Ricklepick:BAABLgAECn8YAAMIAAYJDBXxRABzAQAIAAYJDBXxRABzAQACAAEJ0wktjAArAAABLgAFFAQJBwATAMoYAA==.Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJEAAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Ry='Ryzenther:BAAALgAECgYJDQAAAA==.',
Sa='Salvation:BAAALgAECgkJEgAAAA==.Sanctis:BAAALgAECgYJCQAAAA==.Santan:BAAALgADCgIJAgAAAA==.Satrat:BAAALgAFFAEJAQAAAA==.',
Sc='Scarecrow:BAAALgAECgEJAgAAAA==.',
Se='Sealgair:BAAALgAECgEJBgAAAA==.Senovourer:BAABLgAECn8fAAIfAAkJjCEJCwAqAwAfAAkJjCEJCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn85AAMIAAkJsyB+BQBZAwAIAAkJsyB+BQBZAwAUAAEJggfuTQAuAAAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAACLgAFFH8JAAIWAAQJHRpQCgAyAQAWAAQJHRpQCgAyAQAuAAQKfz4AAhYACAnXIyUEAM4CABYACAnXIyUEAM4CAAAA.Shazrast:BAAALgAECgUJAwAAAA==.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgAECgEJAQAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sindora:BAAALgADCgYJBgAAAA==.Sizouze:BAABLgAECn8mAAIGAAgJHQgxNwASAQAGAAgJHQgxNwASAQAAAA==.',
Sk='Skeeter:BAAALgAECgYJBgAAAA==.Sklonda:BAAALgADCgYJBgAAAA==.Skyepic:BAACLgAFFH8bAAIkAAgJKRnGAQDuAQAkAAgJKRnGAQDuAQAuAAQKfy0AAyQACQmjIi0HAPkCACQACQmjIi0HAPkCAAEABAllEn7VAOAAAAAA.Skylight:BAAALgAECgEJAQAAAA==.',
Sn='Snugwalnut:BAACLgAFFH8eAAIEAAYJ2yALCAAiAgAEAAYJ2yALCAAiAgAuAAQKfzcAAgQACAlHI/0MAOUCAAQACAlHI/0MAOUCAAAA.',
So='Soejoedi:BAABLgAECn8tAAICAAkJbxmGEABNAgACAAkJbxmGEABNAgAAAA==.',
Sp='Spicyburrito:BAAALgAECgcJDQAAAA==.',
St='Stitchzpls:BAAALgAECgUJCQAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDwAAAA==.',
Sy='Sythar:BAAALgAECgEJAQAAAA==.',
Ta='Taintedrush:BAAALgAFFAEJAgAAAA==.Talan:BAAALgAECgMJAwABLgAECggJHQATABcgAA==.Tarhostamir:BAABLgAECn8bAAICAAcJxw8LNAA6AQACAAcJxw8LNAA6AQAAAA==.Taurup:BAAALgAECgcJEAABLgAFFAUJDgAaANQHAA==.Tazz:BAABLgAECn8dAAILAAgJUgbMfwAyAQALAAgJUgbMfwAyAQAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaluus:BAAALgADCgYJDQAAAA==.Thaysinga:BAAALgAFFAIJAwAAAA==.Thelandlord:BAACLgAFFH8UAAIbAAYJahVpBQChAQAbAAYJahVpBQChAQAuAAQKfxwAAxsACAkOG9oMAGgCABsACAkOG9oMAGgCACIAAwnJDqIvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAABLgAECn8jAAIKAAgJ5SR2BwDgAgAKAAgJ5SR2BwDgAgAAAA==.Thuss:BAABLgAECn8pAAIfAAkJgxrHGgBqAgAfAAkJgxrHGgBqAgAAAA==.',
Ti='Titgunniz:BAAALgADCgYJCQAAAA==.',
Tu='Tugnutz:BAAALgAECgUJDQAAAA==.Tuk:BAAALgAECgQJBAAAAA==.',
Tw='Twirlywhirly:BAAALgAECgcJDAAAAA==.',
['Tè']='Tèmpos:BAAALgAECgMJAwAAAA==.',
Ul='Ulansiola:BAAALgAECgIJAgAAAA==.',
Un='Unplug:BAAALgAECgUJDQAAAA==.',
Va='Valkyrrie:BAAALgAECgQJBAABLgAECgkJGAAbAGsNAA==.Vander:BAAALgAECgQJBAABLgAECggJHQATABcgAA==.Vanidossa:BAABLgAECn8gAAIHAAcJ0A6yMwBBAQAHAAcJ0A6yMwBBAQAAAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAACLgAFFH8IAAIHAAMJLhNEIQDSAAAHAAMJLhNEIQDSAAAuAAQKf1EAAwcACQm5I3UCAEIDAAcACQm5I3UCAEIDAAUAAQmBBLJ8ACYAAAAA.',
Ve='Veins:BAAALgAECgEJAQAAAA==.Verdict:BAACLgAFFH8IAAIkAAMJnBMrLgCyAAAkAAMJnBMrLgCyAAAuAAQKfxYAAiQACQkCFyInAMYBACQACQkCFyInAMYBAAAA.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
We='Weemsy:BAABLgAECn87AAIKAAkJfiRaAwAwAwAKAAkJfiRaAwAwAwAAAA==.',
Wi='Wildfire:BAACLgAFFH8gAAINAAcJsSBjAQA6AgANAAcJsSBjAQA6AgAuAAQKfzQAAg0ACQntJoUAAJEDAA0ACQntJoUAAJEDAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAcJIAANALEgAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAABLgAECn83AAIQAAkJuyKCAgAWAwAQAAkJuyKCAgAWAwAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAABLgAECn8WAAMIAAYJhhvqQACEAQAIAAYJhhvqQACEAQACAAEJ1gKZnQAaAAAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xaxfen:BAACLgAFFH8TAAIQAAcJgBbxBAAoAQAQAAcJgBbxBAAoAQAuAAQKfyYABBAACAnjItcJAHoCABAACAnjItcJAHoCAAoABQlEFBVRAPsAAAkAAQkAAFqFAAAAAAAA.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Yo='Yogurt:BAAALgAECgIJAgAAAA==.',
Za='Zappieboy:BAAALgAECgcJDQAAAA==.',
Ze='Zeuree:BAAALgAFFAIJBAABLgAFFAMJCgAFALcKAA==.Zeurie:BAABLgAFFH8KAAIFAAMJtwrULwC4AAAFAAMJtwrULwC4AAAAAA==.',
Zu='Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAABLgAECn8UAAIIAAcJYhGFRAB1AQAIAAcJYhGFRAB1AQAAAA==.',
['Zî']='Zîmìk:BAAALgAECgQJBgAAAA==.',
['Às']='Àsh:BAACLgAFFH8JAAIGAAQJBRttDwBEAQAGAAQJBRttDwBEAQAuAAQKfzoAAgYACQnqIgYDAF4DAAYACQnqIgYDAF4DAAAA.',
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
