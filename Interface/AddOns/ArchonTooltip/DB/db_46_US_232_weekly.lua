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

local lookup = {'Paladin-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Warrior-Protection','Warrior-Arms','Priest-Holy','Warlock-Demonology','Paladin-Retribution','Paladin-Holy','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Mage-Frost','Priest-Shadow','Hunter-BeastMastery','Shaman-Elemental','Warrior-Fury','Shaman-Enhancement','DemonHunter-Vengeance','Shaman-Restoration','Monk-Windwalker','Warlock-Affliction','DeathKnight-Unholy','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','Monk-Brewmaster','Druid-Balance','Warlock-Destruction','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aadel:BAAALgADCgMJAwAAAA==.',
Ac='Acelara:BAAALgADCgUJBQAAAA==.',
Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ae='Aeons:BAAALgAECgEJAQABLgAECgkJVgABAK4hAA==.',
Ag='Ages:BAAALgAECgUJBwAAAA==.',
Ah='Ahmet:BAABLgAECn8WAAICAAkJZhN/FQD3AQACAAkJZhN/FQD3AQABLgAECgkJVgABAK4hAA==.',
Ai='Aiax:BAACLgAFFH8IAAIDAAMJRALWJAB2AAADAAMJRALWJAB2AAAuAAQKfxcABAQACAlODDQgACwBAAUABgmnDb0xADoBAAQABglkCjQgACwBAAMAAglJB0VGAEAAAAAA.',
Al='Alderok:BAAALgAECgQJCgABLgAECgYJDAAGAAAAAA==.Aliancetrash:BAAALgAECgEJAQAAAA==.Aliancia:BAACLgAFFH8IAAIHAAMJHA2UEgCQAAAHAAMJHA2UEgCQAAAuAAQKf1gAAwcACQn0FdwCANMBAAcACQn0FdwCANMBAAgACAmCCy0jAEoBAAAA.Almur:BAAALgAECggJDwAAAA==.Alyda:BAEALgADCggJFAAAAA==.',
Am='Amalthea:BAAALgAECgIJBAAAAA==.Amet:BAABLgAECn9WAAIBAAkJriE1AwDoAgABAAkJriE1AwDoAgAAAA==.',
An='Anakinn:BAAALgAECgUJBQAAAA==.Ankelbyter:BAAALgAECgEJAQABLgAECggJHAABAMwTAA==.Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8wAAIJAAkJBxv9EwA3AgAJAAkJBxv9EwA3AgAAAA==.Annutar:BAAALgADCgcJCQABLgAECgUJHwAKAHcJAA==.Antherina:BAAALgAECgUJBQAAAA==.Antonious:BAAALgAECgcJBwAAAA==.Antonlavay:BAAALgAECgQJBAABLgAECgUJHwAKAHcJAA==.',
Ap='Aphyra:BAAALgADCgUJBQAAAA==.Apollyon:BAACLgAFFH8SAAILAAQJPiNhEgBpAQALAAQJPiNhEgBpAQAuAAQKfy0AAwsACQn9IrgSANICAAsACQn9IrgSANICAAwAAwnWG9xTAOgAAAAA.',
Ar='Ari:BAAALgAECgIJAgAAAA==.Ariioch:BAAALgAECggJDgAAAA==.Arise:BAAALgADCgEJAQAAAA==.Arlechino:BAACLgAFFH8cAAINAAQJtxayQQAjAQANAAQJtxayQQAjAQAuAAQKfx8AAg0ACQkGF1lAAPMBAA0ACQkGF1lAAPMBAAAA.Arywyn:BAABLgAECn8eAAIOAAkJIQp1XQAeAQAOAAkJIQp1XQAeAQAAAA==.',
As='Asheaneryl:BAAALgAECgEJAQAAAA==.Assclapiuss:BAABLgAECn9BAAMLAAkJtyVcAwBkAwALAAkJtyVcAwBkAwAMAAEJTwddmgAmAAABLgAFFAMJBAAGAAAAAA==.Asterchades:BAACLgAFFH8FAAIPAAMJuQvkLABnAAAPAAMJuQvkLABnAAAuAAQKf1UAAg8ACQnIH3sEANACAA8ACQnIH3sEANACAAAA.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgkJEAAAAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn9SAAIQAAkJ+QVxkQBVAQAQAAkJ+QVxkQBVAQAAAA==.Atuan:BAABLgAECn8bAAIRAAkJBxJwKgB/AQARAAkJBxJwKgB/AQAAAA==.',
Au='Auralass:BAABLgAECn8cAAISAAgJXRYSSQDGAQASAAgJXRYSSQDGAQAAAA==.Aurene:BAAALgAECgkJNAAAAQ==.Auti:BAAALgAECgYJCQAAAA==.Auty:BAAALgAECgYJBgAAAA==.Autym:BAAALgADCgkJCQAAAA==.',
Av='Avaric:BAAALgAECgEJAQABLgAECggJGAATAEIFAA==.Avatard:BAAALgAFFAMJBAABLgAFFAQJGwAQANIHAA==.Avida:BAAALgAECgEJAgAAAA==.Avilla:BAAALgAECgYJDwAAAA==.',
Ax='Axem:BAABLgAECn8wAAIUAAkJmB3wDQCQAgAUAAkJmB3wDQCQAgAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azol:BAABLgAFFH8FAAIVAAMJ4gTKDACNAAAVAAMJ4gTKDACNAAAAAA==.Azulathan:BAABLgAECn8bAAMWAAgJ3BYZCgDEAQAWAAgJ3BYZCgDEAQANAAcJwwq9jgAEAQABLgAECggJNAAXAP4TAA==.',
Ba='Baekyu:BAAALgAECgQJBAAAAA==.Bamseyn:BAAALgADCgYJCwAAAA==.Bamsheyn:BAAALgADCgkJCQAAAA==.Bangpewpew:BAAALgAECgcJCwAAAA==.Baraxor:BAABLgAECn80AAMXAAgJ/hN7RACcAQAXAAgJ/hN7RACcAQATAAgJrw8jQAA0AQAAAA==.Barrelaged:BAAALgAECgYJDgAAAA==.Baunilha:BAACLgAFFH8QAAIUAAYJ3BJeEQB8AQAUAAYJ3BJeEQB8AQAuAAQKf0AAAxQACQn0I3kFAAkDABQACQn0I3kFAAkDAAgAAQkgDiV6AC8AAAAA.',
Be='Beararms:BAAALgAECgEJAgAAAA==.Beerguy:BAABLgAECn8eAAIYAAkJkw4VMwA4AQAYAAkJkw4VMwA4AQAAAA==.Behemothe:BAACLgAFFH8FAAMVAAMJeBBSDgB0AAAVAAMJeBBSDgB0AAAXAAEJih/UQQBSAAAuAAQKf2AAAxUACQm6InoBACQDABUACQm6InoBACQDABcABgkfI2gEAE0CAAAA.Bejs:BAAALgAECgUJBgABLgAFFAQJEgAXAOIUAA==.Berníesandrs:BAABLgAECn8zAAIQAAkJuQ4MZgCxAQAQAAkJuQ4MZgCxAQAAAA==.Beryllos:BAABLgAECn8pAAISAAcJ+RH2EgBRAQASAAcJ+RH2EgBRAQAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECggJDgAAAA==.Bigdamage:BAABLgAFFH8JAAIQAAUJghWZJwA4AQAQAAUJghWZJwA4AQABLgAFFAUJCAAZAGkcAA==.Bigdmg:BAABLgAFFH8IAAIaAAIJRRss1ACMAAAaAAIJRRss1ACMAAAAAA==.Biggusdiscus:BAAALgAECgMJAwAAAA==.Bigimpin:BAAALgAECgQJBgAAAA==.Bisky:BAAALgAECggJEwABLgAECgkJIwAPAL8fAA==.',
Bj='Bjôrn:BAAALgAECgcJDgAAAA==.',
Bl='Bledana:BAAALgAECgcJDQAAAA==.Bleué:BAAALgADCgEJAQABLgAECgkJPAAOAPEaAA==.Bloodmourne:BAABLgAECn8yAAIaAAkJmSXGBQBMAwAaAAkJmSXGBQBMAwAAAA==.Bloodytoutii:BAABLgAECn8YAAQbAAkJRh8qAgBJAgAbAAcJOCEqAgBJAgAcAAUJNxL+CQDeAAAQAAEJAABBYwAAAAAAAA==.Blueogre:BAAALgAECgEJAgAAAA==.',
Bo='Borthyr:BAABLgAECn8tAAMFAAkJvx/mCADJAgAFAAkJoR7mCADJAgAEAAYJ0RyqDgDwAQAAAA==.Bortman:BAAALgAECgcJCwABLgAECgkJLQAFAL8fAA==.Bowowner:BAABLgAECn8hAAISAAgJxh4MQADiAQASAAgJxh4MQADiAQAAAA==.',
Br='Branchmanagr:BAABLgAECn8iAAIPAAkJ6REOFQCtAQAPAAkJ6REOFQCtAQAAAA==.Breddamon:BAAALgADCgMJAwABLgAECgUJHwAKAHcJAA==.Brewlee:BAABLgAFFH8FAAIYAAQJNgsnHgDiAAAYAAQJNgsnHgDiAAAAAA==.Bricter:BAAALgADCgkJCQABLgAECgkJPQAQAFkVAA==.Brokenkrayon:BAAALgAECgQJBgAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Buhbul:BAAALgAECggJCQAAAA==.Bullséye:BAAALgAECgEJAQAAAA==.Busta:BAABLgAECn8fAAIQAAkJZwV+rgAkAQAQAAkJZwV+rgAkAQAAAA==.Buzzball:BAAALgAECgIJBAAAAA==.',
Bw='Bwicked:BAABLgAECn8tAAIQAAkJ9Bu7BQBSAgAQAAkJ9Bu7BQBSAgAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgcJDwAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Calzone:BAABLgAECn8UAAMNAAkJsQ2seQAtAQANAAgJLQuseQAtAQAdAAUJeAyTUAB1AAAAAA==.Cantpurge:BAAALgAECgMJAwABLgAECgcJGAARAAkIAA==.Carebears:BAAALgAECgQJBQAAAA==.Caroline:BAAALgAECgEJAQAAAA==.',
Ce='Celonge:BAAALgAECgcJBwABLgAFFAUJBwAMAGMFAA==.',
Ch='Chamelean:BAAALgAECgYJEQABLgAFFAMJCQANABEMAA==.Charmcaster:BAAALgAECgEJAQAAAA==.Chimpnzthat:BAABLgAECn83AAIeAAgJHhQ4IQCeAQAeAAgJHhQ4IQCeAQAAAA==.Chookicookie:BAABLgAECn9IAAMTAAkJ+R6gCgC1AgATAAkJ+R6gCgC1AgAXAAkJ1SDQFACkAgAAAA==.Chrome:BAABLgAECn9VAAMfAAkJDySSAgBLAwAfAAkJDySSAgBLAwAOAAgJyB1+HgBLAgAAAA==.Chuckarita:BAABLgAECn8gAAIfAAkJnQp9MwBLAQAfAAkJnQp9MwBLAQAAAA==.',
Ci='Cinde:BAAALgADCgEJAQAAAA==.Cindyy:BAABLgAECn8iAAIYAAgJiyENDACDAgAYAAgJiyENDACDAgABLgAFFAQJEAASADscAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgQJBQAAAA==.',
Co='Coedwig:BAAALgAECgUJBgAAAA==.Consfiracy:BAAALgAFFAEJAQAAAA==.Coresh:BAACLgAFFH8TAAIVAAQJuR1XAwBhAQAVAAQJuR1XAwBhAQAuAAQKfxYAAhUACQlTG7gIADUCABUACQlTG7gIADUCAAAA.Cornpuff:BAABLgAECn8bAAMgAAkJsCSQCgCbAQAKAAYJjySAMwAKAgAgAAUJ+CSQCgCbAQAAAA==.Cortiz:BAABLgAECn9CAAISAAkJaRIIQgDcAQASAAkJaRIIQgDcAQAAAA==.',
Cr='Crankdog:BAABLgAECn8rAAMSAAkJ1iTxBQA1AwASAAkJ1iTxBQA1AwAhAAYJ8g9oSgApAQAAAA==.Creedd:BAABLgAECn8vAAIOAAgJGiC3FACkAgAOAAgJGiC3FACkAgABLgAECgkJGwAXAMIfAA==.Crialta:BAAALgADCgcJFAAAAA==.',
Cu='Cupsandcakes:BAABLgAECn8iAAIbAAkJ7g6JBgBXAQAbAAkJ7g6JBgBXAQAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Dadbody:BAAALgAFFAMJBAAAAA==.Damessiah:BAABLgAECn82AAMJAAkJshQ6FgAgAgAJAAkJshQ6FgAgAgARAAEJ8AFhnAAWAAAAAA==.Darandeh:BAAALgAECgMJAwAAAA==.Dark:BAABLgAECn9QAAIKAAkJHCMTBgAwAwAKAAkJHCMTBgAwAwAAAA==.Darkphyre:BAABLgAECn8dAAILAAkJlg5PjwBTAQALAAkJlg5PjwBTAQAAAA==.Darksparx:BAAALgAECgEJBgAAAA==.Darkstormn:BAAALgAECgYJEAAAAA==.Darthtree:BAAALgAECgcJCQAAAA==.Dawling:BAAALgAECggJDgAAAA==.',
De='Deadmandan:BAABLgAECn8vAAMKAAkJHSXCBQBgAwAKAAkJHSXCBQBgAwAgAAYJISSxBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn9UAAIiAAkJ4SSXAQBGAwAiAAkJ4SSXAQBGAwABLgAECgkJUgAWAGQmAA==.Decius:BAABLgAECn8dAAIjAAkJkAkkDgBDAQAjAAkJkAkkDgBDAQAAAA==.Dedsexxy:BAAALgADCgQJBAAAAA==.Deltairlines:BAACLgAFFH8nAAMFAAkJhSKEAQAaAwAFAAkJhSKEAQAaAwADAAQJQAWzHgC5AAAuAAQKfxoAAgUACQnWHt0JALoCAAUACQnWHt0JALoCAAAA.Deltayaya:BAABLgAFFH8MAAMXAAUJYBPAHwB1AQAXAAUJYBPAHwB1AQATAAEJpQ8YVQA/AAABLgAFFAkJJwAFAIUiAA==.Demagorgin:BAACLgAFFH8HAAILAAMJBxG5bADWAAALAAMJBxG5bADWAAAuAAQKfz0AAgsACQlWHR4jAHkCAAsACQlWHR4jAHkCAAAA.Demcheekz:BAAALgAECgIJAgABLgAFFAQJFAAgAA8IAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAABLgAECn8XAAQkAAgJxwnLPAAbAQAkAAcJNQnLPAAbAQAJAAQJpQllUQCaAAARAAEJGAOBmgAcAAAAAA==.Demonpanzar:BAAALgADCgIJAgAAAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn86AAILAAkJTR8NFgC+AgALAAkJTR8NFgC+AgAAAA==.Desmus:BAABLgAECn83AAIfAAgJoRg5GwDxAQAfAAgJoRg5GwDxAQAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAFFAYJIgAKAAMkAA==.Devilmaycry:BAAALgADCgEJAQAAAA==.Deáthreaver:BAABLgAECn82AAMLAAkJPBIzSwDlAQALAAkJmBEzSwDlAQABAAMJtgmKDQCEAAAAAA==.',
Di='Diddyy:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAABLgAECn8eAAIMAAkJJhKOIwDoAQAMAAkJJhKOIwDoAQAAAA==.Ditar:BAAALgAECgEJAgABLgAECgYJCgAGAAAAAA==.',
Dk='Dk:BAAALgADCgIJAgABLgAFFAMJCQASABkkAA==.',
Do='Domwarlock:BAABLgAFFH8JAAMKAAQJFQ1kgwC/AAAKAAMJagpkgwC/AAAZAAEJExUMIQBPAAAAAA==.Doogang:BAAALgAECgEJAQAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.Doublehungus:BAAALgAECgkJAQAAAA==.',
Dr='Drackal:BAAALgAECgEJAQAAAA==.Dradin:BAAALgADCgMJAwAAAA==.Dragondznutz:BAAALgAFFAEJAQABLgAFFAMJBAAGAAAAAA==.Dronin:BAACLgAFFH8FAAISAAMJYBgkLADzAAASAAMJYBgkLADzAAAuAAQKfysABCEACQlBGhwQAFoBACEABwlkFhwQAFoBABIABQnHHV5zAFkBAAIAAQnAFmsSADsAAAAA.Drpatan:BAABLgAECn88AAIdAAgJkA47CQAZAQAdAAgJkA47CQAZAQAAAA==.Druni:BAABLgAECn8eAAIBAAkJEwlHIQAKAQABAAkJEwlHIQAKAQAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Du='Dudetank:BAAALgAECgQJBAAAAA==.',
Ea='Eazye:BAAALgAECgEJAQAAAA==.',
Ec='Echowalker:BAABLgAECn8ZAAIdAAgJnRhDFgDYAQAdAAgJnRhDFgDYAQAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
Eh='Ehdawg:BAAALgAECgEJAQAAAA==.',
Ei='Eisenthorne:BAAALgADCgEJAgAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elemann:BAAALgAECgQJBQAAAA==.Elguezo:BAABLgAECn8VAAIYAAYJUhxwIwCWAQAYAAYJUhxwIwCWAQAAAA==.Elmaster:BAAALgADCgIJAgAAAA==.Elysyn:BAAALgAECgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emmerick:BAAALgAECgUJCwAAAA==.Emokillaz:BAABLgAECn8WAAIdAAcJ2hitIwCgAQAdAAcJ2hitIwCgAQAAAA==.',
Ep='Epictaxes:BAABLgAECn8jAAITAAkJUh0sAgCQAgATAAkJUh0sAgCQAgAAAA==.Epimetheuz:BAAALgADCgYJAwABLgAECgcJCwAGAAAAAA==.Epsi:BAAALgAECgYJCQABLgAECgcJGAARAAkIAA==.Epsilón:BAABLgAECn8YAAIRAAcJCQg0TADeAAARAAcJCQg0TADeAAAAAA==.',
Et='Eternalpeace:BAAALgAECgEJBAAAAA==.',
Eu='Euphrate:BAAALgAECgIJAgAAAA==.',
Ev='Evelana:BAAALgADCgQJBwAAAA==.',
Ex='Exaduss:BAABLgAECn8VAAMgAAgJUyH+CAAxAgAgAAgJUyH+CAAxAgAKAAQJHB50ggA0AQAAAA==.',
Ez='Ezora:BAAALgAECgcJDAAAAA==.',
Fa='Famulimus:BAAALgAECgcJCgABLgAECgkJFwAOAHkYAA==.Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAABLgAECn8uAAISAAkJHRmrIABkAgASAAkJHRmrIABkAgAAAA==.Faylan:BAABLgAECn8VAAISAAYJ/A0angAFAQASAAYJ/A0angAFAQAAAA==.',
Fe='Feardot:BAAALgADCgYJBgABLgAFFAQJGwAQANIHAA==.Felshadow:BAAALgAECgEJAwAAAA==.Felwynd:BAAALgAECgEJAQAAAA==.Feronnia:BAABLgAECn8WAAISAAYJywMJMgCJAAASAAYJywMJMgCJAAAAAA==.Fett:BAAALgAFFAIJAgABLgAFFAQJGwAQANIHAA==.',
Fi='Fibot:BAACLgAFFH8GAAIVAAMJEQ58CgC3AAAVAAMJEQ58CgC3AAAuAAQKf0kAAhUACQlAIH8CAPMCABUACQlAIH8CAPMCAAAA.Fingon:BAAALgAECgcJEgAAAA==.Fistavus:BAAALgAECgEJAwAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJKgAQAKkUAA==.Florasol:BAAALgAECgYJBgAAAA==.Florezner:BAAALgADCgMJAwAAAA==.',
Fo='Foxling:BAEALgAECgUJCwAAAA==.',
Fr='Fraeyah:BAAALgAECgcJBwAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAACLgAFFH8MAAIQAAQJKA2iaAASAQAQAAQJKA2iaAASAQAuAAQKfxYAAhAACQkaF2ZUADsCABAACQkaF2ZUADsCAAAA.Frogurt:BAAALgAECgEJAQAAAA==.',
Fu='Fulgora:BAABLgAECn8YAAITAAgJQgURWADcAAATAAgJQgURWADcAAAAAA==.Fullmoon:BAAALgAECgcJDQABLgAECgcJEAAGAAAAAA==.Furicor:BAAALgAECgEJAQAAAA==.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAECLgAFFH8cAAIQAAcJqwmKHwBzAQAQAAcJqwmKHwBzAQAuAAQKf0MAAhAACQnGG4gpAHQCABAACQnGG4gpAHQCAAAA.Gasaraki:BAAALgAECgEJAgAAAA==.Gastdhunter:BAAALgAECgEJAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgAECgYJBgAAAA==.',
Gi='Gideion:BAAALgADCgEJAQAAAA==.Gimtar:BAAALgAECgYJCgAAAA==.Ginjockey:BAAALgADCgUJBQABLgAECgcJGAARAAkIAA==.Gipsydanger:BAACLgAFFH8TAAIkAAQJNhnGFADuAAAkAAQJNhnGFADuAAAuAAQKf0QAAiQACQnWHT8KAMwCACQACQnWHT8KAMwCAAAA.Girllygirl:BAAALgAECgcJDgAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Gladiatrix:BAAALgAECgQJCAAAAA==.Glaurang:BAABLgAECn8fAAIKAAUJdwloHACXAAAKAAUJdwloHACXAAAAAA==.Glofor:BAAALgAECgcJEAABLgAECgkJKgAQAKkUAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECggJGAAXAMcWAA==.Gnomeregrets:BAAALgAECgYJBgABLgAFFAQJFAAgAA8IAA==.Gnomestone:BAABLgAFFH8UAAMgAAQJDwhIBQDlAAAgAAQJDwhIBQDlAAAKAAMJIwVFRACIAAAAAA==.',
Go='Goldencorpse:BAAALgAECggJDAAAAA==.Goldenspoon:BAAALgAECgUJBQABLgAFFAUJCAAZAGkcAA==.Gonnjass:BAAALgAECgUJCAAAAA==.',
Gr='Grakonys:BAABLgAECn9GAAMFAAkJ3xdmEgBOAgAFAAkJ3xdmEgBOAgAEAAcJ4Qc7HQBFAQAAAA==.Granger:BAAALgAECgIJAgAAAA==.Graves:BAAALgAECgEJAQAAAA==.Greed:BAABLgAECn9FAAIYAAkJuR4KCADHAgAYAAkJuR4KCADHAgAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAABLgAECn8vAAIiAAcJvRhhBACpAQAiAAcJvRhhBACpAQAAAA==.Grimmvelt:BAAALgAECgQJBAAAAA==.Gronch:BAAALgADCgkJCQABLgADCgkJMQAGAAAAAA==.Groonk:BAAALgADCgkJGwABLgADCgkJMQAGAAAAAA==.Grounch:BAAALgADCgcJDAAAAA==.Grunch:BAAALgADCgkJMQAAAA==.Grunnck:BAAALgAECgYJBgAAAA==.Grunnk:BAAALgADCgkJDwABLgADCgkJMQAGAAAAAA==.Grásshopper:BAAALgAECgEJAQAAAA==.',
Gu='Guayusa:BAAALgAFFAEJAQAAAA==.Gunned:BAAALgADCgEJAQAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQAGAAAAAA==.',
Gz='Gza:BAAALgAECgEJAQAAAA==.',
Ha='Habibane:BAAALgAECgEJAQAAAA==.Hacheron:BAAALgADCgIJAgABLgAFFAUJDQAiAHoQAA==.Hallows:BAAALgAECgYJDgAAAA==.Harnix:BAABLgAECn8tAAILAAgJ9g45fgByAQALAAgJ9g45fgByAQAAAA==.Harron:BAAALgAECgUJBQAAAA==.Hawtbooty:BAABLgAECn83AAIJAAkJcBwDGQADAgAJAAkJcBwDGQADAgAAAA==.Haziel:BAEALgADCgkJEAAAAA==.',
He='Heartsbane:BAAALgAECgEJAQAAAA==.Helixrage:BAABLgAECn8XAAIHAAkJ/QUrJQAIAQAHAAkJ/QUrJQAIAQAAAA==.Hellreines:BAACLgAFFH8SAAIlAAYJHCCFAwDYAQAlAAYJHCCFAwDYAQAuAAQKfyMAAiUACQkzIuIEAHQCACUACQkzIuIEAHQCAAAA.Herpderplol:BAABLgAECn8cAAImAAkJDBG0EACsAQAmAAkJDBG0EACsAQAAAA==.',
Hi='Hikantraz:BAAALgAECgEJAQAAAA==.Hildi:BAABLgAECn83AAMnAAgJ+QL0hACUAAAnAAgJ+QL0hACUAAAYAAEJyAEnjAAfAAAAAA==.Him:BAACLgAFFH8HAAIUAAMJ0RhnMwDjAAAUAAMJ0RhnMwDjAAAuAAQKfyoAAhQACQmcI6sFAAUDABQACQmcI6sFAAUDAAAA.Hiraaksam:BAAALgAECgQJBAAAAA==.',
Ho='Holy:BAACLgAFFH8SAAIkAAQJbBjfFQDfAAAkAAQJbBjfFQDfAAAuAAQKf0gAAyQACQn3IeEDAF4DACQACQn3IeEDAF4DAAkAAQmDHO1mAEgAAAAA.Holyscales:BAAALgAECgEJAQAAAA==.Hoots:BAAALgAECgQJBQAAAA==.Horarcius:BAAALgAECgQJBAAAAA==.Hottopic:BAAALgAECgcJDAAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgAECgEJAgAAAA==.Humânity:BAAALgADCgYJBgAAAA==.Hurcules:BAAALgAECgUJBQAAAA==.',
['Hø']='Høåx:BAAALgAECgcJBwAAAA==.',
['Hü']='Hümänïty:BAAALgAECgcJBQABLgAFFAcJEgALAFYSAA==.',
Ic='Icicle:BAAALgAECgYJCQAAAA==.',
Il='Illbloodarch:BAABLgAECn8/AAIIAAkJ7BC/EwDDAQAIAAkJ7BC/EwDDAQAAAA==.Illidaris:BAAALgAECggJCQAAAA==.Illikan:BAAALgADCgEJAQAAAA==.Illvicious:BAABLgAECn8cAAMLAAYJ9hHXIgDSAAALAAYJ9hHXIgDSAAABAAIJGgVmTgA2AAAAAA==.',
Im='Imaginos:BAAALgAECgUJBQABLgAECgUJBQAGAAAAAA==.',
In='Incredibread:BAAALgAECggJEwAAAA==.Indub:BAAALgAECgcJCwAAAA==.',
Ir='Ironfistmogu:BAAALgADCgkJCQAAAA==.Iroxxigo:BAAALgAECgEJAQAAAA==.',
Is='Ishura:BAABLgAECn8uAAIMAAgJrwrfPABTAQAMAAgJrwrfPABTAQAAAA==.',
It='Itank:BAAALgAECgUJBQAAAA==.Itslevi:BAABLgAECn8VAAILAAgJRBW6IgDTAAALAAgJRBW6IgDTAAAAAA==.',
Iv='Ivvy:BAABLgAECn8bAAIfAAgJswreOQArAQAfAAgJswreOQArAQAAAA==.',
Iz='Izanami:BAABLgAECn8tAAIdAAkJeR8gBgDYAgAdAAkJeR8gBgDYAgAAAA==.',
Ja='Jadinkalage:BAAALgAECgQJBAAAAA==.Jaewreth:BAAALgAECgcJCAAAAA==.Jaffer:BAAALgADCgYJBgABLgAFFAYJDwASAJwJAA==.Janntro:BAABLgAECn8hAAMdAAkJyx35DgA3AgAdAAkJphr5DgA3AgAWAAIJgyVvGQDSAAABLgAECgkJIwAPAL8fAA==.Jantra:BAAALgAECgEJAgABLgAECgkJIwAPAL8fAA==.Jantro:BAABLgAECn8jAAIPAAkJvx+UBADNAgAPAAkJvx+UBADNAgAAAA==.Janttro:BAAALgAECgIJBQABLgAECgkJIwAPAL8fAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAACLgAFFH8SAAMXAAQJ4hTyHwDUAAAXAAQJ4hTyHwDUAAATAAQJswQ+NAC+AAAuAAQKfyoAAxcACQmyE2Q7AMEBABcACQmyE2Q7AMEBABMABAkcDZRsAJEAAAAA.Jeleka:BAAALgAECgYJCAABLgAECgkJLAAXADEfAA==.Jelmarr:BAABLgAECn8qAAIKAAcJlCKrAwBSAgAKAAcJlCKrAwBSAgAAAA==.Jemmâ:BAABLgAECn8VAAIHAAkJ2BkFGwBgAQAHAAkJ2BkFGwBgAQAAAA==.Jerauld:BAABLgAECn82AAImAAgJLxKSEwCGAQAmAAgJLxKSEwCGAQAAAA==.Jezrra:BAAALgAECggJDwAAAA==.',
Jh='Jhuloot:BAAALgAECgEJAQAAAA==.',
Ji='Jiddles:BAAALgAECgMJBgABLgAECgkJLAAXADEfAA==.',
Jo='Johnnyzyns:BAABLgAECn8yAAMaAAkJOB3CHQCVAgAaAAkJOB3CHQCVAgAiAAEJthhFWQA7AAAAAA==.Jokhasta:BAABLgAECn8ZAAIVAAgJvBY/CwAYAgAVAAgJvBY/CwAYAgAAAA==.Jonnyjo:BAAALgAECgIJAwAAAA==.Joshc:BAABLgAECn8yAAIPAAkJHg3PIgA5AQAPAAkJHg3PIgA5AQAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
Ju='Judgejudee:BAAALgADCgcJFgABLgAECgUJHwAKAHcJAA==.Judgédred:BAAALgAECgcJDAAAAA==.',
['Já']='Ják:BAABLgAECn8cAAQBAAgJzBMPGwA2AQABAAcJJhEPGwA2AQAMAAMJvwtXfQBSAAALAAEJpwOkxAEhAAAAAA==.',
Ka='Kaaris:BAABLgAECn8wAAIgAAkJEBGUCQCuAQAgAAkJEBGUCQCuAQAAAA==.Kaetora:BAAALgADCgkJEgAAAA==.Kaiarie:BAABLgAECn8lAAIZAAkJywg5EwA4AQAZAAkJywg5EwA4AQAAAA==.Kainraziel:BAACLgAFFH8JAAINAAMJEQybaQC5AAANAAMJEQybaQC5AAAuAAQKfx4AAg0ACQkMFWk8ANYBAA0ACQkMFWk8ANYBAAAA.Kairos:BAACLgAFFH8NAAIQAAMJKRHSOQDeAAAQAAMJKRHSOQDeAAAuAAQKf1AAAhAACQnqEy1GAAgCABAACQnqEy1GAAgCAAAA.Kalasta:BAAALgAECgEJAQAAAA==.Kandolf:BAAALgAECgQJBAAAAA==.Kanofworms:BAABLgAECn8WAAIoAAYJrg9dCQDeAAAoAAYJrg9dCQDeAAAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karem:BAAALgAECgEJAQAAAA==.Karkea:BAAALgAECgEJBAAAAA==.Katrrina:BAAALgADCgcJBwAAAA==.Kayper:BAAALgAECgcJAgAAAA==.Kayyos:BAAALgAECgkJCQAAAA==.',
Ke='Kebin:BAABLgAECn8xAAIHAAkJvhf5DgD6AQAHAAkJvhf5DgD6AQAAAA==.Kekkoken:BAAALgAECgEJAQAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.Kenhyllrha:BAAALgADCgEJAQAAAA==.Kenora:BAAALgADCgEJAQAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgABLgAFFAMJBQASAGAYAA==.',
Ki='Kibil:BAAALgAECgYJDgABLgAECgkJKQAaAHMOAA==.Killmonger:BAAALgAECgYJCwAAAA==.Kimsambo:BAAALgAECgQJBAAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Kn='Knocksteady:BAAALgAECgUJCgAAAA==.',
Ko='Koga:BAAALgAECgQJBAAAAA==.Korax:BAAALgAECgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAABLgAECn8yAAIDAAkJTiNfAQCMAwADAAkJTiNfAQCMAwAAAA==.Korzillian:BAAALgAECgEJAQAAAA==.Kos:BAACLgAFFH8cAAIRAAcJiyFjAwBCAgARAAcJiyFjAwBCAgAuAAQKfygAAhEACQlrJDEFAAMDABEACQlrJDEFAAMDAAAA.',
Kr='Kreyali:BAAALgAECgMJCAAAAA==.Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgcJEwAAAA==.Kuntar:BAAALgAECgcJCwAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurrent:BAABLgAECn8sAAIXAAkJMR88EgC7AgAXAAkJMR88EgC7AgAAAA==.',
['Kÿ']='Kÿtten:BAACLgAFFH8JAAIBAAQJDwUlCgB4AAABAAQJDwUlCgB4AAAuAAQKfyYAAgEACQnvCqgZAEwBAAEACQnvCqgZAEwBAAAA.',
La='Lad:BAACLgAFFH8KAAIaAAQJRRZxYgAxAQAaAAQJRRZxYgAxAQAuAAQKfxkAAxoACQm5HxoSAN0CABoACQm5HxoSAN0CACUAAQkeCqMXADEAAAAA.Laiyth:BAABLgAECn8bAAIKAAkJfxIVPgDkAQAKAAkJfxIVPgDkAQAAAA==.Lanfearz:BAAALgADCgEJAQAAAA==.Larryfish:BAABLgAECn8oAAMaAAkJZCGTHACbAgAaAAkJeyCTHACbAgAlAAgJTB7cBAB1AgAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgMJBgAAAA==.Lavos:BAABLgAECn8yAAIgAAkJSQ/fCwCBAQAgAAkJSQ/fCwCBAQAAAA==.',
Le='Lepracy:BAAALgADCgEJAQAAAA==.Levitikus:BAAALgAFFAEJAgAAAA==.Levìtikus:BAAALgAECgUJBwAAAA==.',
Li='Lideysse:BAAALgAECgMJAwAAAA==.Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lilslippah:BAAALgAECgUJBQAAAA==.Liru:BAAALgAECgcJBwAAAA==.Lisster:BAABLgAECn8zAAMSAAkJzyAbEQDIAgASAAkJzyAbEQDIAgAhAAEJkAG2mAAeAAAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8dAAMMAAkJNhuwIAAWAgAMAAkJNhuwIAAWAgABAAEJBBULQQA5AAAAAA==.Lizcandor:BAAALgAECgQJEQAAAA==.',
Lo='Loafe:BAACLgAFFH8XAAILAAQJABLmIwD7AAALAAQJABLmIwD7AAAuAAQKfywAAgsACQkAEyNlALYBAAsACQkAEyNlALYBAAAA.Lokni:BAAALgAECgYJEQAAAA==.Look:BAAALgAFFAIJBAABLgAFFAMJBQANAH4SAA==.Loriann:BAAALgAECgEJAQAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgAECggJDgAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgcJBwAAAA==.Luthais:BAABLgAECn8eAAIBAAkJMw3BHAAvAQABAAkJMw3BHAAvAQAAAA==.Luxury:BAABLgAECn9VAAIHAAkJ+wV4CQC5AAAHAAkJ+wV4CQC5AAAAAA==.',
Ly='Lykanthropos:BAAALgAECgEJAQAAAA==.',
Ma='Mahroq:BAABLgAECn8mAAMJAAgJwhk2HgDtAQAJAAgJnxk2HgDtAQAkAAYJoQl3SQDfAAABLgAFFAIJAwAGAAAAAA==.Maingauche:BAAALgAFFAIJAgABLgAECgkJNAAGAAAAAA==.Mako:BAACLgAFFH8cAAMDAAQJ/hacCgAIAQADAAQJ/hacCgAIAQAFAAIJcQFzYABVAAAuAAQKfykAAgMACQnvIpcEAOACAAMACQnvIpcEAOACAAAA.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8nAAMEAAgJDwy5DgAgAQAFAAcJtgq8NQAjAQAEAAgJygi5DgAgAQAAAA==.Malfuridan:BAAALgAECgQJAwAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Mandas:BAAALgAECgIJAgAAAA==.Maplebarkles:BAAALgAECgEJAQAAAA==.Maples:BAABLgAECn8nAAMnAAkJXwoSQwBhAQAnAAkJXwoSQwBhAQAYAAMJ3gHVwQAVAAAAAA==.Mariasha:BAABLgAECn8jAAMSAAkJwQvyjgAhAQASAAYJnQ7yjgAhAQACAAMJ+wYiCwCBAAAAAA==.Marichika:BAAALgADCgcJEQAAAA==.Marvellous:BAAALgADCgUJBQAAAA==.Maryjaine:BAAALgAECgUJDAAAAA==.Mattdeamon:BAEALgADCgUJBwABLgAFFAcJHAAQAKsJAA==.Mazzikin:BAACLgAFFH8HAAINAAMJvhvEVQDuAAANAAMJvhvEVQDuAAAuAAQKfy8AAg0ACQmYIL0KAPMCAA0ACQmYIL0KAPMCAAAA.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Meatshield:BAAALgAECgEJAQAAAA==.Megaterium:BAABLgAECn9AAAMJAAkJLxs0DgCEAgAJAAkJLxs0DgCEAgARAAcJHQwXTgDXAAAAAA==.Melkoor:BAAALgADCgcJGQABLgAECgUJHwAKAHcJAA==.Meláni:BAAALgAECgIJAgABLgAECgUJBgAGAAAAAA==.Menethil:BAABLgAECn8lAAMMAAkJEiL5DADBAgAMAAgJoiP5DADBAgALAAMJ8Rh9IgDVAAAAAA==.Menethyl:BAAALgADCgcJBwAAAA==.Metheuz:BAAALgAECgcJCwAAAA==.Mexican:BAABLgAECn8yAAIQAAkJPxP8SgD6AQAQAAkJPxP8SgD6AQAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgAECgYJEwAAAA==.Mishgrail:BAABLgAECn9DAAIeAAkJcyGSBAD8AgAeAAkJcyGSBAD8AgAAAA==.Misosoup:BAAALgAECgUJBQABLgADCgEJAQAGAAAAAA==.Missmisery:BAABLgAECn8wAAMSAAkJAxI8OgD2AQASAAkJAxE8OgD2AQACAAMJAw6cCQCeAAAAAA==.Mistaya:BAAALgADCgIJAgAAAA==.Mithdraug:BAABLgAECn8dAAQfAAkJ7xKhMwBLAQAfAAgJLBKhMwBLAQAOAAQJdwYwwABFAAAmAAEJwAfJXwAiAAAAAA==.Mitzi:BAACLgAFFH8dAAMaAAkJHBJjMgCfAQAaAAcJohRjMgCfAQAiAAMJAAOVHQByAAAuAAQKfyQAAhoACQlwI14aAN8CABoACQlwI14aAN8CAAAA.',
Mo='Modrem:BAAALgAECgUJCgAAAA==.Mokhan:BAAALgADCgkJCQAAAA==.Molsan:BAAALgAECgQJBAAAAA==.Monache:BAABLgAECn8ZAAIUAAgJdAvROQBfAQAUAAgJdAvROQBfAQAAAA==.Mongalf:BAAALgADCgcJBwAAAA==.Montrois:BAAALgAECgQJBAABLgAECgcJBwAGAAAAAA==.Moocheala:BAAALgAECgEJAQAAAA==.Moochele:BAAALgAECgcJBwAAAA==.Moofahsa:BAAALgAECgEJAQAAAA==.Moonfire:BAAALgAECgMJAwAAAA==.Moopally:BAAALgAECgQJCQAAAA==.Moozenic:BAAALgAECgYJBgAAAA==.Mortarîon:BAAALgAECgMJAwAAAA==.',
My='Mythrilblade:BAAALgAECgcJCQAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Na='Naromir:BAAALgAECgcJEAAAAA==.Nastytaco:BAAALgADCgMJAwABLgAECgkJIgAQAD0RAA==.Natèbro:BAAALgADCgEJAQAAAA==.',
Ne='Neletheus:BAABLgAECn8WAAIKAAcJihCigwAxAQAKAAcJihCigwAxAQAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAABLgAECn8fAAIaAAkJFSF5JABzAgAaAAkJFSF5JABzAgAAAA==.Nirvanik:BAAALgAECgQJBQAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECgkJQwAeAHMhAA==.Nixie:BAAALgAECgEJAQAAAA==.',
No='Notditar:BAAALgAECgEJAQAAAA==.',
Nu='Nukusmaximus:BAABLgAECn8yAAIQAAgJIgktmgBFAQAQAAgJIgktmgBFAQAAAA==.',
Ny='Nyeneave:BAAALgAECgIJAgAAAA==.Nyiah:BAABLgAECn8vAAIOAAkJNxpbFgCVAgAOAAkJNxpbFgCVAgAAAA==.Nyxiie:BAAALgADCgIJAgAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Od='Odioz:BAAALgAECgMJAwAAAA==.',
Of='Offset:BAAALgAECgEJCAAAAA==.',
Og='Ogdoadtl:BAAALgAECgQJCgAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.Ohzone:BAAALgAECgEJAQAAAA==.',
On='Onex:BAAALgAECggJDAAAAA==.Onfleek:BAAALgAECgIJAgABLgAECgQJBwAGAAAAAA==.',
Or='Organicmeat:BAAALgAFFAEJAQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.Ori:BAAALgAECgYJDAAAAA==.Oriannaa:BAAALgADCggJCgAAAA==.',
Pa='Paleprincess:BAAALgADCgIJAgABLgAECgIJAgAGAAAAAA==.Palii:BAAALgAECgQJBQAAAA==.Panzrshiv:BAAALgAECgEJAQAAAA==.Partywizard:BAAALgAECgMJAwAAAA==.Pawmasutra:BAAALgAECgYJBwAAAA==.',
Pe='Pencil:BAAALgADCgMJAwAAAA==.Persefini:BAACLgAFFH8FAAIOAAMJKQI3WQBnAAAOAAMJKQI3WQBnAAAuAAQKfxgAAg4ACQlDCntTAEIBAA4ACQlDCntTAEIBAAAA.Persephoneia:BAAALgADCgcJDQAAAA==.Petrodrak:BAAALgAECgYJBgABLgAECgcJKQAPAE8DAA==.Petrokull:BAABLgAECn8pAAIPAAcJTwOwEQBzAAAPAAcJTwOwEQBzAAAAAA==.',
Ph='Phaeder:BAAALgAECgEJAQAAAA==.Pheeguh:BAAALgAFFAMJAwAAAA==.Pheylan:BAACLgAFFH8FAAICAAUJIAJPDQDJAAACAAUJIAJPDQDJAAAuAAQKfxQAAgIACQlOEC4cALsBAAIACQlOEC4cALsBAAAA.Philidox:BAAALgAECgYJCgABLgAECggJHAABAMwTAA==.Phood:BAAALgAECgEJAgABLgAECgYJDAAGAAAAAA==.',
Pi='Piety:BAAALgAECgYJBgAAAA==.Pikxs:BAAALgAECgMJAgAAAA==.Pitchou:BAAALgAECgUJCAAAAA==.',
Pl='Plugugly:BAAALgAECgQJBgAAAA==.',
Po='Poenin:BAAALgAECgUJCAABLgAFFAMJBQASAGAYAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8fAAISAAkJHQ1SWACbAQASAAkJHQ1SWACbAQAAAA==.Portal:BAAALgADCgEJAQABLgAECgYJJwAOAAsaAA==.Potatobear:BAACLgAFFH8UAAISAAQJIiWHFwCtAQASAAQJIiWHFwCtAQAuAAQKfzYABBIACQnvJaQCAGYDABIACQnvJaQCAGYDACEABglfI/EZAFsCAAIACQlgGicPADsCAAAA.',
Pr='Presta:BAEALgADCgUJBQABLgADCgkJEAAGAAAAAA==.Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgAECgMJBAAAAA==.',
Pu='Pumilio:BAAALgADCgUJBQAAAA==.Punchabull:BAAALgADCgYJBAAAAA==.Punt:BAAALgAECgEJAQAAAA==.',
Qi='Qiursi:BAAALgAECgUJBQAAAA==.',
Qu='Quicktime:BAABLgAECn92AAMNAAkJ8x45AgCPAgAdAAkJPB3LAQCrAgANAAkJZR05AgCPAgAAAA==.',
Ra='Radahn:BAAALgADCgUJBQABLgAFFAcJHAARAIshAA==.Rafael:BAAALgAECgYJBgABLgAFFAQJHAADAP4WAA==.Ragedh:BAACLgAFFH8FAAINAAMJfhIuZwC+AAANAAMJfhIuZwC+AAAuAAQKfxcAAg0ACQn4GhEZAH8CAA0ACQn4GhEZAH8CAAAA.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ragnoir:BAAALgAECggJEAAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAABLgAECn8dAAISAAgJ3CPQAgDcAgASAAgJ3CPQAgDcAgAAAA==.Rashish:BAAALgADCgcJAgAAAA==.Ravies:BAACLgAFFH8IAAISAAMJYhXONQDRAAASAAMJYhXONQDRAAAuAAQKfx4AAhIACQkxHsoQAMoCABIACQkxHsoQAMoCAAAA.Rawdøg:BAAALgADCgEJAQAAAA==.Rayaz:BAAALgAECgUJCwABLgAECgkJFwAOAHkYAA==.',
Re='Reeses:BAEALgAECgkJEwABLgADCgkJEAAGAAAAAA==.Refellos:BAAALgAECgEJAgAAAA==.Regime:BAAALgAFFAIJAgABLgAECgkJNAAGAAAAAA==.Reinhearts:BAAALgAFFAEJAQAAAA==.Religgar:BAABLgAECn8xAAIaAAkJ7Bh+KQBbAgAaAAkJ7Bh+KQBbAgAAAA==.Reploidzero:BAAALgAECgUJAQAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAABLgAECn89AAIQAAkJWRWGPgAiAgAQAAkJWRWGPgAiAgAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Robnsparkles:BAAALgADCgEJAQAAAA==.Roglof:BAABLgAECn8qAAIQAAgJqRSVZwCtAQAQAAgJqRSVZwCtAQAAAA==.Rokkoks:BAAALgAECgIJAgABLgAECgQJBAAGAAAAAA==.Rowlah:BAAALgAECgcJDgAAAA==.Roxyfoxy:BAAALgAECgcJEAAAAA==.Rozy:BAABLgAECn8/AAMMAAkJQR5uEgB/AgAMAAkJQR5uEgB/AgALAAUJZxgfrgAiAQAAAA==.',
Ru='Ruffs:BAABLgAECn8XAAMNAAkJIR0+GwBxAgANAAkJIR0+GwBxAgAWAAEJYhDqMwA0AAAAAA==.Ruiizu:BAABLgAECn8yAAILAAkJJiTeCQAZAwALAAkJJiTeCQAZAwAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn9HAAIkAAkJeB2SCgDHAgAkAAkJeB2SCgDHAgAAAA==.',
Sa='Saberjaw:BAABLgAECn8XAAMCAAYJrBU3FACCAQACAAYJkRQ3FACCAQASAAIJvwtLGAFEAAAAAA==.Sairicck:BAABLgAECn8tAAISAAkJcx7yGgCDAgASAAkJcx7yGgCDAgAAAA==.Samaal:BAAALgADCgUJBQABLgAECgkJIwAPAL8fAA==.Samial:BAAALgADCgYJDAABLgAECgkJIwAPAL8fAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgAECgYJCgAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satorugojo:BAAALgAECgEJAQAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.Sauger:BAAALgAECgIJBQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selenar:BAAALgAECgEJAQAAAA==.Selesé:BAAALgAECgEJAQABLgAECgkJFQAHANgZAA==.Selinora:BAAALgAECgkJDgAAAA==.Senaria:BAAALgAECgMJCQAAAA==.Serhalatath:BAAALgAECggJDAAAAA==.',
Sh='Shade:BAAALgAECgEJAQABLgAECgYJJwAOAAsaAA==.Shadowsbane:BAAALgAFFAIJAwAAAA==.Shaguar:BAABLgAECn8rAAMLAAkJ0CDiEgDRAgALAAkJ0CDiEgDRAgAMAAcJPhCGXAALAQAAAA==.Shamhawk:BAAALgAECgEJAgAAAA==.Shamwow:BAAALgADCgcJBwAAAA==.Shaolinsnake:BAACLgAFFH8FAAIUAAMJ9hO1MwDiAAAUAAMJ9hO1MwDiAAAuAAQKfxcAAhQACQmKHewZAB4CABQACQmKHewZAB4CAAAA.Shawbuffet:BAAALgADCgEJAQAAAA==.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.Shizzite:BAAALgAECggJCAAAAA==.Shonuph:BAAALgAECgUJCAAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAACLgAFFH8bAAIQAAQJ0gfaOQDdAAAQAAQJ0gfaOQDdAAAuAAQKfyYAAhAACQnoElxpAAMCABAACQnoElxpAAMCAAAA.Sinzala:BAABLgAECn8iAAIQAAkJVR/JHQCqAgAQAAkJVR/JHQCqAgAAAA==.',
Sk='Skeetsurfin:BAAALgAECgMJAwAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwABLgAECgkJKwALANAgAA==.',
Sl='Sloppyjo:BAAALgAECgYJBgAAAA==.',
Sm='Smallblackdk:BAAALgAFFAIJAwAAAA==.Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.Snowbunnyy:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.',
So='Solai:BAAALgAECgQJCwAAAA==.Solenne:BAAALgAECgQJBAABLgAFFAUJBwAMAGMFAA==.Solsti:BAACLgAFFH8HAAIMAAUJYwXcIwABAQAMAAUJYwXcIwABAQAuAAQKf0sAAgwACQnIGTkDABoCAAwACQnIGTkDABoCAAAA.Soulhunter:BAABLgAFFH8gAAIiAAkJhBgFAwBtAgAiAAkJhBgFAwBtAgAAAA==.',
Sp='Spears:BAABLgAECn8cAAISAAgJgQaplwARAQASAAgJgQaplwARAQAAAA==.Spoonarrow:BAAALgAECgEJAQABLgAFFAUJCAAZAGkcAA==.Spoonbrew:BAAALgAECgYJBgABLgAFFAUJCAAZAGkcAA==.Spoondot:BAACLgAFFH8IAAMZAAUJaRyEAgBEAQAZAAUJixqEAgBEAQAKAAIJxRVRkQChAAAuAAQKfy4AAxkACQkeJosBAOMCABkACAlDJYsBAOMCAAoACQlMI9wWAJsCAAAA.Spoonknight:BAACLgAFFH8HAAMlAAIJZSJ/HQCXAAAaAAIJIh4YwgCmAAAlAAIJxBR/HQCXAAAuAAQKfx8ABCUACQl/IFMFAGUCABoACAnEHcMmAGgCACUACAmXH1MFAGUCACIABQluGUAlACkBAAEuAAUUBQkIABkAaRwA.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Staceyrella:BAAALgAECgEJAwAAAA==.Stainpngolin:BAABLgAECn8gAAIPAAgJsh3jCQBKAgAPAAgJsh3jCQBKAgAAAA==.Stillhorn:BAABLgAECn8tAAMNAAkJThohJgA0AgANAAkJ4hghJgA0AgAdAAgJGRveDwAqAgAAAA==.Stinjeras:BAABLgAECn8yAAIKAAkJoSGDDQDhAgAKAAkJoSGDDQDhAgAAAA==.Stinkyjo:BAABLgAECn8yAAIOAAkJbxrNEgC1AgAOAAkJbxrNEgC1AgAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAACLgAFFH8PAAISAAYJnAmHRwAeAQASAAYJnAmHRwAeAQAuAAQKfyIAAhIACQmGHkYhAGECABIACQmGHkYhAGECAAAA.',
Su='Suian:BAAALgADCgEJAQAAAA==.Sunadoria:BAAALgAECgUJEwAAAA==.Sunlite:BAAALgAECgEJBgAAAA==.Sunrae:BAABLgAECn8yAAQkAAgJMRpaFAA7AgAkAAgJZxhaFAA7AgARAAYJZwnnSwDgAAAJAAMJShQXXQC+AAAAAA==.Sushi:BAABLgAECn8fAAIeAAkJlRMmGQDdAQAeAAkJlRMmGQDdAQAAAA==.',
Sv='Sven:BAAALgAECgUJCQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAABLgAECn8uAAIJAAcJrAl8DADYAAAJAAcJrAl8DADYAAAAAA==.',
['Sö']='Söap:BAAALgAECgYJCAAAAA==.',
Ta='Taggert:BAAALgAECgEJAQAAAA==.Tahl:BAABLgAECn8+AAIJAAkJXRRzBADQAQAJAAkJXRRzBADQAQAAAA==.Talox:BAAALgAECgEJAQAAAA==.Tamanovitch:BAAALgAECgEJAQAAAA==.Tamashii:BAAALgAFFAIJAwABLgAFFAQJHAADAP4WAA==.Tangriah:BAAALgADCgMJAQAAAA==.Taproot:BAEALgADCgEJAQABLgAFFAcJHAAQAKsJAA==.Taryen:BAAALgAECgUJCgABLgAFFAMJBQANAH4SAA==.Tavie:BAABLgAFFH8QAAIQAAQJ8xeGXAAmAQAQAAQJ8xeGXAAmAQAAAA==.',
Te='Teamet:BAAALgAECgEJAQAAAA==.Teddy:BAAALgADCgYJBgAAAA==.Tedo:BAAALgAECgEJAQABLgAFFAcJHQAMAA4ZAA==.Teikkas:BAAALgAECggJDQAAAA==.Telaari:BAAALgAECgQJBwAAAA==.',
Th='Thalenia:BAACLgAFFH8aAAISAAQJhQc0LQDvAAASAAQJhQc0LQDvAAAuAAQKfz0AAxIACQlcGaQFAFcCABIACQlcGaQFAFcCACEACAlhBuIbAM8AAAAA.Thallenia:BAAALgADCgEJAQAAAA==.Thalron:BAAALgAECgEJAQAAAA==.Thayne:BAAALgADCgYJBwAAAA==.Thekingdom:BAACLgAFFH8GAAIQAAIJWA+woQCLAAAQAAIJWA+woQCLAAAuAAQKfx4AAhAACAlWHV9FAGcCABAACAlWHV9FAGcCAAAA.Therealnasus:BAAALgADCgMJAwAAAA==.Thom:BAAALgAECgIJAwAAAA==.Thriller:BAAALgAFFAMJAwABLgAFFAcJHQAMAA4ZAA==.',
Ti='Tikeidari:BAABLgAECn9SAAIWAAkJZCYoAAB9AwAWAAkJZCYoAAB9AwAAAA==.Tiltedtroll:BAABLgAECn8rAAITAAkJnhJiKACrAQATAAkJnhJiKACrAQAAAA==.Timedemon:BAABLgAECn8mAAINAAkJcRuVKQAjAgANAAkJcRuVKQAjAgAAAA==.Tinuveuil:BAAALgADCgYJBgABLgAECgUJHwAKAHcJAA==.',
To='Toiletseat:BAAALgAECgUJBQAAAA==.Tombfyre:BAAALgAECgUJAQABLgAECggJGQAdAJ0YAA==.Tombs:BAEALgAFFAEJAgABLgAFFAcJHAAQAKsJAA==.Tonjuras:BAABLgAECn8zAAMoAAkJ1SKOBADyAgAoAAkJLR+OBADyAgAjAAgJJB4WBABcAgAAAA==.Toona:BAACLgAFFH8FAAINAAIJ5AmUiwBsAAANAAIJ5AmUiwBsAAAuAAQKfxwAAg0ACQn7GgYcAKoCAA0ACQn7GgYcAKoCAAEuAAUUBAkKABoARRYA.Tootty:BAAALgAECgEJAQAAAA==.Torogrande:BAAALgAECgUJBQAAAA==.Totemeri:BAAALgAECgIJAgAAAA==.Touchmyting:BAAALgAECgEJAwAAAA==.Toutii:BAAALgAECgUJCAABLgAECgkJGAAbAEYfAA==.',
Tr='Trappydh:BAACLgAFFH8JAAIWAAQJbRDzBwDXAAAWAAQJbRDzBwDXAAAuAAQKfxQAAhYACAmJF8wJAM8BABYACAmJF8wJAM8BAAEuAAUUBQkNACIAehAA.Trappydk:BAACLgAFFH8NAAIiAAUJehD8IQDaAAAiAAUJehD8IQDaAAAuAAQKfxcAAiIACAnPGt4UAMgBACIACAnPGt4UAMgBAAAA.Trappydruid:BAAALgAFFAEJAQABLgAFFAUJDQAiAHoQAA==.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8sAAMKAAgJsSStCwAdAwAKAAgJsSStCwAdAwAZAAEJAADgIQBqAAAAAA==.',
Ty='Tyraxus:BAAALgADCgkJEAAAAA==.Tyronne:BAAALgAECgcJBwAAAA==.',
['Tý']='Týr:BAAALgAECgQJBwAAAA==.',
Ul='Ultraball:BAAALgAECggJDwAAAA==.',
Un='Unagi:BAABLgAECn8sAAICAAkJfg7sFwDiAQACAAkJfg7sFwDiAQAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAABLgAECn8YAAIQAAgJOAgbnwA8AQAQAAgJOAgbnwA8AQAAAA==.Vaesir:BAAALgADCgcJDQAAAA==.Varleara:BAABLgAECn8hAAMNAAkJtSBEEwDmAgANAAkJtSBEEwDmAgAWAAEJKQeHLQAqAAAAAA==.Vazdun:BAAALgAECgEJAQABLgAECgkJIQANALUgAA==.',
Ve='Vehlahi:BAAALgAECgQJCQAAAA==.Velriah:BAAALgADCgcJBAAAAA==.Venefirous:BAAALgADCgEJAQAAAA==.Venenn:BAAALgADCgIJAwAAAA==.Venessa:BAAALgAECgEJAQAAAA==.Venev:BAABLgAECn8VAAIjAAgJ1Rh3CQCnAQAjAAgJ1Rh3CQCnAQAAAA==.Vennenn:BAAALgAECgEJAgAAAA==.Vennev:BAAALgADCggJCgAAAA==.Ventana:BAACLgAFFH8PAAIVAAIJyx21CgCyAAAVAAIJyx21CgCyAAAuAAQKf04AAhUACQmcI0MBAC8DABUACQmcI0MBAC8DAAAA.Verdilac:BAABLgAECn81AAILAAkJexxXQwD8AQALAAkJexxXQwD8AQABLgAFFAYJMwAmAJAfAA==.',
Vi='Vinceglortho:BAABLgAECn8ZAAISAAYJgQxOHwDpAAASAAYJgQxOHwDpAAAAAA==.Vindicator:BAABLgAECn8fAAILAAkJSB3GIACEAgALAAkJSB3GIACEAgAAAA==.Violetnoir:BAAALgAECgQJBAABLgAFFAQJCAAKACIEAA==.Visiroth:BAABLgAECn8pAAMaAAkJcw4caACWAQAaAAkJJAscaACWAQAiAAgJHQtmJQAoAQAAAA==.',
Vy='Vynedari:BAAALgAECgQJBAAAAA==.Vyyral:BAAALgAECgUJBwABLgAECgkJIwAPAL8fAA==.',
['Vë']='Vërondez:BAAALgADCgEJAQAAAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAFFAQJGwAQANIHAA==.Wallydk:BAABLgAECn8xAAIaAAkJTBuXHQCWAgAaAAkJTBuXHQCWAgAAAA==.Wanji:BAABLgAECn8rAAIaAAkJCwuuZwCXAQAaAAkJCwuuZwCXAQAAAA==.Warfrost:BAAALgAECgEJAgAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Wenesday:BAAALgADCgcJGQAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Widginatrix:BAABLgAECn8iAAIfAAkJwxzDAQCSAgAfAAkJwxzDAQCSAgAAAA==.Willkain:BAAALgAECgMJAwAAAA==.Wilomina:BAAALgAECgYJBgAAAA==.Wintyrstorm:BAAALgAECgEJAQAAAA==.',
Wo='Woah:BAAALgAECgUJCAABLgAFFAUJCAAZAGkcAA==.Woons:BAAALgAECgMJCAAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Wy='Wytewytch:BAAALgADCgQJBAAAAA==.',
Xa='Xaharst:BAAALgAECgEJAQAAAA==.Xaya:BAACLgAFFH8IAAIKAAQJIgR9gwC/AAAKAAQJIgR9gwC/AAAuAAQKfxsAAwoACAn6CDKfAAABAAoACAn6CDKfAAABACAABAnoAklRAHoAAAAA.',
Xe='Xenophorge:BAAALgAFFAIJBAAAAA==.Xeralvezyn:BAAALgAECgYJCAAAAA==.',
Xi='Xiurong:BAAALgAECgYJCAAAAA==.Xiva:BAABLgAECn80AAIoAAgJ7BKCHACxAQAoAAgJ7BKCHACxAQAAAA==.',
Xo='Xovace:BAABLgAECn8aAAMdAAkJdAy7KQAwAQAdAAkJSwy7KQAwAQANAAIJ8QYXCQFBAAAAAA==.',
Xt='Xtayse:BAABLgAECn8rAAIEAAkJuCA2AQD5AgAEAAkJuCA2AQD5AgAAAA==.Xtaysì:BAAALgAECgEJAQAAAA==.Xtàyse:BAAALgAECgEJAgAAAA==.',
Ya='Yagorbomb:BAAALgAECgMJBwAAAA==.Yamyam:BAABLgAECn8VAAIfAAkJsg/HKQCyAQAfAAkJsg/HKQCyAQAAAA==.',
Yi='Yirya:BAABLgAECn8ZAAMOAAYJjBBbCQAqAQAOAAYJjBBbCQAqAQAfAAMJLgPvkgAsAAAAAA==.',
Yo='Yoruechi:BAACLgAFFH8bAAIPAAQJ3iC+BwB6AQAPAAQJ3iC+BwB6AQAuAAQKfy0AAg8ACQn/InMFALUCAA8ACQn/InMFALUCAAAA.',
Yu='Yuridia:BAAALgADCgEJAQAAAA==.',
['Yú']='Yúmyúm:BAABLgAECn8lAAILAAkJWBdHSQDqAQALAAkJWBdHSQDqAQAAAA==.',
Za='Zahel:BAABLgAECn8uAAILAAkJlB7dGACuAgALAAkJlB7dGACuAgAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECgkJLgALAJQeAA==.Zalark:BAAALgADCgUJCgABLgAECgkJNgAJALIUAA==.Zangai:BAAALgAECggJCAABLgAECggJGQAUAHQLAA==.Zavier:BAAALgAECgQJBQABLgAECgYJDAAGAAAAAA==.',
Ze='Zefiryn:BAAALgAECgEJAgAAAA==.Zeneri:BAABLgAECn84AAMnAAkJhRCrKwDSAQAnAAkJhRCrKwDSAQAYAAkJyRAkHQDFAQAAAA==.Zeppola:BAAALgADCgMJAwABLgAECgkJFAANALENAA==.',
Zo='Zobi:BAABLgAECn8xAAINAAcJPBdYBwCUAQANAAcJPBdYBwCUAQAAAA==.Zocorra:BAAALgAECgEJAgAAAA==.Zodius:BAAALgADCgEJAQAAAA==.Zomboo:BAAALgAFFAEJAQAAAA==.',
Zu='Zugzugzug:BAAALgAECgYJBgAAAA==.Zuhali:BAAALgADCgQJBAAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAFFAQJEgAXAOIUAA==.',
['Ðr']='Ðream:BAAALgADCgMJAwAAAA==.',
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
