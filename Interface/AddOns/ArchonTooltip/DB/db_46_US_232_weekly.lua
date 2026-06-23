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

local lookup = {'Paladin-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Warrior-Protection','Warrior-Arms','Priest-Holy','Paladin-Retribution','Paladin-Holy','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Mage-Frost','Priest-Shadow','Hunter-BeastMastery','Shaman-Elemental','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','Monk-Brewmaster','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','Priest-Discipline','Warlock-Affliction','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-06-21',data={Aa='Aadel:BAAALgADCgMJAwAAAA==.',
Ac='Acelara:BAAALgADCgUJBQAAAA==.',
Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ae='Aeons:BAAALgAECgEJAQABLgAECgkJUQABAK4hAA==.',
Ah='Ahmet:BAABLgAECn8WAAICAAkJZhODFQD3AQACAAkJZhODFQD3AQABLgAECgkJUQABAK4hAA==.',
Ai='Aiax:BAACLgAFFH8IAAIDAAMJRALVJAB2AAADAAMJRALVJAB2AAAuAAQKfxcABAQACAlODDQgACwBAAUABgmnDb0xADoBAAQABglkCjQgACwBAAMAAglJB0VGAEAAAAAA.',
Al='Alderok:BAAALgAECgQJCgABLgAECgYJDAAGAAAAAA==.Aliancia:BAABLgAECn9HAAMHAAkJPxWBAADGAQAHAAkJPxWBAADGAQAIAAgJggsuIwBKAQAAAA==.Almur:BAAALgAECgcJDQAAAA==.Alyda:BAAALgADCggJFAAAAA==.',
Am='Amalthea:BAAALgAECgIJBAAAAA==.Amet:BAABLgAECn9RAAIBAAkJriE1AwDoAgABAAkJriE1AwDoAgAAAA==.',
An='Anakinn:BAAALgAECgUJBQAAAA==.Ankelbyter:BAAALgAECgEJAQABLgAECggJHAABAMwTAA==.Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8wAAIJAAkJBxv9EwA3AgAJAAkJBxv9EwA3AgAAAA==.Annutar:BAAALgADCgcJCQAAAA==.Antherina:BAAALgADCgQJBwAAAA==.Antonious:BAAALgADCgMJAwAAAA==.Antonlavay:BAAALgAECgQJBAAAAA==.',
Ap='Aphyra:BAAALgADCgUJBQAAAA==.Apollyon:BAACLgAFFH8MAAIKAAQJJSGPKQBmAQAKAAQJJSGPKQBmAQAuAAQKfyoAAwoACQnEIbcSANMCAAoACQnEIbcSANMCAAsAAwnWG9xTAOgAAAAA.',
Ar='Arise:BAAALgADCgEJAQAAAA==.Arlechino:BAACLgAFFH8VAAIMAAQJ4RSyQQAjAQAMAAQJ4RSyQQAjAQAuAAQKfx0AAgwACAkXF1lAAPMBAAwACAkXF1lAAPMBAAAA.Arywyn:BAABLgAECn8eAAINAAkJGgp4XQAeAQANAAkJGgp4XQAeAQAAAA==.',
As='Assclapiuss:BAABLgAECn9AAAMKAAkJtyVcAwBkAwAKAAkJtyVcAwBkAwALAAEJTwdemgAmAAAAAA==.Asterchades:BAABLgAECn9UAAIOAAkJyB97BADQAgAOAAkJyB97BADQAgAAAA==.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgkJEAAAAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn9RAAIPAAkJvgVxkQBVAQAPAAkJvgVxkQBVAQAAAA==.Atuan:BAABLgAECn8bAAIQAAkJDhJvKgB/AQAQAAkJDhJvKgB/AQAAAA==.',
Au='Auralass:BAABLgAECn8cAAIRAAgJXRYRSQDGAQARAAgJXRYRSQDGAQAAAA==.Aurene:BAAALgAECgkJNAAAAQ==.Autym:BAAALgADCgkJCQAAAA==.',
Av='Avaric:BAAALgAECgEJAQABLgAECggJGAASAEIFAA==.Avatard:BAAALgAFFAIJAgABLgAFFAQJFAAPAD4HAA==.Avilla:BAAALgAECgYJDwAAAA==.',
Ax='Axem:BAABLgAECn8uAAITAAkJmB3vDQCQAgATAAkJmB3vDQCQAgAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azulathan:BAABLgAECn8bAAMUAAgJ3BYaCgDEAQAUAAgJ3BYaCgDEAQAMAAcJwwq9jgAEAQABLgAECggJNAAVAP4TAA==.',
Ba='Bamseyn:BAAALgADCgYJCwAAAA==.Bamsheyn:BAAALgADCgkJCQAAAA==.Bangpewpew:BAAALgAECgEJAQAAAA==.Baraxor:BAABLgAECn80AAMVAAgJ/hN5RACcAQAVAAgJ/hN5RACcAQASAAgJrw8gQAA0AQAAAA==.Barrelaged:BAAALgAECgYJCQAAAA==.Baunilha:BAACLgAFFH8PAAITAAYJ3BJcEQB8AQATAAYJ3BJcEQB8AQAuAAQKf0AAAxMACQn0I3kFAAkDABMACQn0I3kFAAkDAAgAAQkgDiV6AC8AAAAA.',
Be='Beararms:BAAALgAECgEJAgAAAA==.Beerguy:BAABLgAECn8bAAIWAAgJDw0UMwA4AQAWAAgJDw0UMwA4AQAAAA==.Behemothe:BAABLgAECn9RAAMXAAkJuiJ6AQAkAwAXAAkJuiJ6AQAkAwAVAAUJFiAnOADPAQAAAA==.Berníesandrs:BAABLgAECn8zAAIPAAkJuQ4MZgCxAQAPAAkJuQ4MZgCxAQAAAA==.Beryllos:BAABLgAECn8YAAIRAAYJqQ9BBgDnAAARAAYJqQ9BBgDnAAAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECggJDgAAAA==.Bigdamage:BAAALgAECgYJBwABLgAFFAIJBwAYAGUiAA==.Bigdmg:BAABLgAFFH8FAAIZAAIJVRcq1ACMAAAZAAIJVRcq1ACMAAAAAA==.Biggusdiscus:BAAALgAECgMJAwAAAA==.Bigimpin:BAAALgAECgQJBgAAAA==.Bisky:BAAALgAECggJEwABLgAECgkJIwAOAL8fAA==.',
Bj='Bjôrn:BAAALgAECgcJDQAAAA==.',
Bl='Bledana:BAAALgAECgcJDQAAAA==.Bleué:BAAALgADCgEJAQABLgAECgkJPAANAPEaAA==.Bloodmourne:BAABLgAECn8yAAIZAAkJmSXGBQBMAwAZAAkJmSXGBQBMAwAAAA==.Bloodytoutii:BAABLgAECn8YAAQaAAkJgR8qAgBJAgAaAAcJfCEqAgBJAgAbAAUJNxL9CQDeAAAPAAEJAABOGQAAAAAAAA==.',
Bo='Borthyr:BAABLgAECn8tAAMFAAkJvx/nCADJAgAFAAkJoR7nCADJAgAEAAYJ0RyqDgDwAQAAAA==.Bortman:BAAALgAECgUJCQABLgAECgkJLQAFAL8fAA==.Bowowner:BAABLgAECn8hAAIRAAgJxh4OQADiAQARAAgJxh4OQADiAQAAAA==.',
Br='Branchmanagr:BAABLgAECn8iAAIOAAkJ6REQFQCtAQAOAAkJ6REQFQCtAQAAAA==.Breddamon:BAAALgADCgMJAwAAAA==.Brewlee:BAAALgAFFAQJBAAAAA==.Bricter:BAAALgADCgkJCQABLgAECgkJPQAPAFkVAA==.Brokenkrayon:BAAALgAECgQJBgAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Bullséye:BAAALgAECgEJAQAAAA==.Busta:BAABLgAECn8fAAIPAAkJZwV6rgAkAQAPAAkJZwV6rgAkAQAAAA==.',
Bw='Bwicked:BAABLgAECn8lAAIPAAkJ/hcJNABIAgAPAAkJ/hcJNABIAgAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgcJDwAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Calzone:BAABLgAECn8UAAMMAAkJsw2seQAtAQAMAAgJLQuseQAtAQAcAAUJfAySUAB1AAAAAA==.Cantpurge:BAAALgAECgMJAwABLgAECgcJFwAQAAkIAA==.Carebears:BAAALgAECgQJBQAAAA==.Caroline:BAAALgAECgEJAQAAAA==.',
Ce='Celonge:BAAALgAECgUJBQABLgAFFAUJBgALAGMFAA==.',
Ch='Chamelean:BAAALgAECgYJEQABLgAFFAMJBwAMABEMAA==.Charmcaster:BAAALgAECgEJAQAAAA==.Chimpnzthat:BAABLgAECn83AAIdAAgJHhQ2IQCeAQAdAAgJHhQ2IQCeAQAAAA==.Chookicookie:BAABLgAECn9HAAMSAAkJ9h6gCgC1AgASAAkJ9h6gCgC1AgAVAAkJ1SDRFACkAgAAAA==.Chrome:BAABLgAECn9UAAMeAAkJDySSAgBLAwAeAAkJDySSAgBLAwANAAgJyB1+HgBLAgAAAA==.Chuckarita:BAABLgAECn8gAAIeAAkJnQp7MwBLAQAeAAkJnQp7MwBLAQAAAA==.',
Ci='Cinde:BAAALgADCgEJAQAAAA==.Cindyy:BAABLgAECn8iAAIWAAgJiyENDACDAgAWAAgJiyENDACDAgABLgAFFAQJDAARADscAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgIJAgAAAA==.',
Co='Coedwig:BAAALgAECgMJAwAAAA==.Consfiracy:BAAALgAFFAEJAQAAAA==.Coresh:BAAALgAFFAMJAwAAAA==.Cornpuff:BAABLgAECn8bAAMfAAkJsSSQCgCbAQAgAAYJkSSAMwAKAgAfAAUJ+CSQCgCbAQAAAA==.Cortiz:BAABLgAECn9CAAIRAAkJaRIKQgDcAQARAAkJaRIKQgDcAQAAAA==.',
Cr='Crankdog:BAABLgAECn8rAAMRAAkJ1iTyBQA1AwARAAkJ1iTyBQA1AwAhAAYJ8g9oSgApAQAAAA==.Creedd:BAABLgAECn8vAAINAAgJGiC3FACkAgANAAgJGiC3FACkAgABLgAECgkJGwAVAMIfAA==.Crialta:BAAALgADCgcJFAAAAA==.',
Cu='Cupsandcakes:BAABLgAECn8fAAIaAAgJOwyJBgBXAQAaAAgJOwyJBgBXAQAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Damessiah:BAABLgAECn81AAMJAAkJnBQ5FgAgAgAJAAkJnBQ5FgAgAgAQAAEJ8AFcnAAWAAAAAA==.Darandeh:BAAALgAECgMJAwAAAA==.Dark:BAABLgAECn9PAAIgAAkJ4SITBgAwAwAgAAkJ4SITBgAwAwAAAA==.Darkphyre:BAABLgAECn8dAAIKAAkJkw5PjwBTAQAKAAkJkw5PjwBTAQAAAA==.Darksparx:BAAALgAECgEJAQAAAA==.Darkstormn:BAAALgAECgYJCgAAAA==.Darthtree:BAAALgAECgcJCQAAAA==.Dawling:BAAALgAECggJDgAAAA==.',
De='Deadmandan:BAABLgAECn8vAAMgAAkJHSXCBQBgAwAgAAkJHSXCBQBgAwAfAAYJISSxBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn9UAAIiAAkJ4SSXAQBGAwAiAAkJ4SSXAQBGAwABLgAECgkJUQAUAGQmAA==.Decius:BAABLgAECn8dAAIjAAkJigkkDgBDAQAjAAkJigkkDgBDAQAAAA==.Dedsexxy:BAAALgADCgQJBAAAAA==.Deltairlines:BAACLgAFFH8TAAMFAAYJvhwMGACnAQAFAAYJvhwMGACnAQADAAQJQAWzHgC5AAAuAAQKfxoAAgUACQnWHt0JALoCAAUACQnWHt0JALoCAAAA.Deltayaya:BAABLgAFFH8MAAMVAAUJYBPJHwB1AQAVAAUJYBPJHwB1AQASAAEJpQ8YVQA/AAABLgAFFAYJEwAFAL4cAA==.Demagorgin:BAACLgAFFH8HAAIKAAMJBxG7bADWAAAKAAMJBxG7bADWAAAuAAQKfzkAAgoACQmeHB0jAHkCAAoACQmeHB0jAHkCAAAA.Demcheekz:BAAALgAECgIJAgAAAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAABLgAECn8WAAQkAAgJxwnMPAAbAQAkAAcJsAjMPAAbAQAJAAQJpQlgUQCaAAAQAAEJGAN8mgAcAAAAAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn84AAIKAAkJ/R4OFgC+AgAKAAkJ/R4OFgC+AgAAAA==.Desmus:BAABLgAECn83AAIeAAgJoRg4GwDxAQAeAAgJoRg4GwDxAQAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAFFAUJIAAgALcjAA==.Devilmaycry:BAAALgADCgEJAQAAAA==.Deáthreaver:BAABLgAECn82AAMKAAkJPBI0SwDlAQAKAAkJmBE0SwDlAQABAAMJtglgAgCTAAAAAA==.',
Di='Diddyy:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAABLgAECn8eAAILAAkJJhKOIwDoAQALAAkJJhKOIwDoAQAAAA==.Ditar:BAAALgAECgEJAgABLgAECgYJCgAGAAAAAA==.',
Dk='Dk:BAAALgADCgIJAgABLgAFFAMJCQARABkkAA==.',
Do='Domwarlock:BAABLgAFFH8JAAMgAAQJFQ1ggwC/AAAgAAMJagpggwC/AAAlAAEJExULIQBPAAAAAA==.Doogang:BAAALgAECgEJAQAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.Doublehungus:BAAALgAECgkJAQAAAA==.',
Dr='Drackal:BAAALgAECgEJAQAAAA==.Dradin:BAAALgADCgMJAwAAAA==.Dragondznutz:BAAALgAECgYJDAABLgAECgkJQAAKALclAA==.Dronin:BAABLgAECn8rAAQhAAkJQRocEABaAQAhAAcJZBYcEABaAQARAAUJxx1gcwBZAQACAAEJwBZ8BABEAAAAAA==.Drpatan:BAABLgAECn82AAIcAAgJSQmPAgCqAAAcAAgJSQmPAgCqAAAAAA==.Druni:BAABLgAECn8eAAIBAAkJEwlGIQAKAQABAAkJEwlGIQAKAQAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Ec='Echowalker:BAABLgAECn8ZAAIcAAgJnRhDFgDYAQAcAAgJnRhDFgDYAQAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
Eh='Ehdawg:BAAALgAECgEJAQAAAA==.',
Ei='Eisenthorne:BAAALgADCgEJAgAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elemann:BAAALgAECgQJBQAAAA==.Elguezo:BAABLgAECn8VAAIWAAYJUhxxIwCWAQAWAAYJUhxxIwCWAQAAAA==.Elysyn:BAAALgADCgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emmerick:BAAALgAECgUJCgAAAA==.Emokillaz:BAABLgAECn8WAAIcAAcJ2hitIwCgAQAcAAcJ2hitIwCgAQAAAA==.',
Ep='Epictaxes:BAABLgAECn8aAAISAAgJsBc5HwDpAQASAAgJsBc5HwDpAQAAAA==.Epimetheuz:BAAALgADCgYJAwABLgAECgcJCwAGAAAAAA==.Epsi:BAAALgAECgYJCQABLgAECgcJFwAQAAkIAA==.Epsilón:BAABLgAECn8XAAIQAAcJCQgwTADeAAAQAAcJCQgwTADeAAAAAA==.',
Et='Eternalpeace:BAAALgAECgEJAwAAAA==.',
Ev='Evelana:BAAALgADCgQJBwAAAA==.',
Ex='Exaduss:BAABLgAECn8VAAMfAAgJUyH+CAAxAgAfAAgJUyH+CAAxAgAgAAQJHB5yggA0AQAAAA==.',
Ez='Ezora:BAAALgAECgcJDAAAAA==.',
Fa='Famulimus:BAAALgAECgcJCgABLgAECgkJFwANAHkYAA==.Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAABLgAECn8uAAIRAAkJHRmtIABkAgARAAkJHRmtIABkAgAAAA==.Faylan:BAABLgAECn8VAAIRAAYJ/A0ZngAFAQARAAYJ/A0ZngAFAQAAAA==.',
Fe='Felshadow:BAAALgAECgEJAwAAAA==.Feronnia:BAAALgAECgUJBgAAAA==.Fett:BAAALgAFFAEJAQABLgAFFAQJFAAPAD4HAA==.',
Fi='Fibot:BAABLgAECn9IAAIXAAkJQCCAAgDzAgAXAAkJQCCAAgDzAgAAAA==.Fingon:BAAALgAECgcJEgAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJKgAPAKkUAA==.Florasol:BAAALgADCgIJAgAAAA==.Florezner:BAAALgADCgMJAwAAAA==.',
Fo='Foxling:BAEALgAECgUJCwAAAA==.',
Fr='Fraeyah:BAAALgAECgcJBwAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAACLgAFFH8MAAIPAAQJKA2haAASAQAPAAQJKA2haAASAQAuAAQKfxYAAg8ACQkaF2ZUADsCAA8ACQkaF2ZUADsCAAAA.Frogurt:BAAALgAECgEJAQAAAA==.',
Fu='Fulgora:BAABLgAECn8YAAISAAgJQgUOWADcAAASAAgJQgUOWADcAAAAAA==.Fullmoon:BAAALgAECgcJDQABLgAECgcJEAAGAAAAAA==.Furicor:BAAALgAECgEJAQAAAA==.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAECLgAFFH8YAAIPAAUJNwylCQAPAQAPAAUJNwylCQAPAQAuAAQKf0MAAg8ACQnGG4opAHQCAA8ACQnGG4opAHQCAAAA.Gasaraki:BAAALgAECgEJAgAAAA==.Gastdhunter:BAAALgAECgEJAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgADCggJCgAAAA==.',
Gi='Gimtar:BAAALgAECgYJCgAAAA==.Ginjockey:BAAALgADCgUJBQABLgAECgcJFwAQAAkIAA==.Gipsydanger:BAACLgAFFH8OAAIkAAMJVh/xJgASAQAkAAMJVh/xJgASAQAuAAQKf0MAAiQACQnWHT8KAMwCACQACQnWHT8KAMwCAAAA.Girllygirl:BAAALgAECgcJDgAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Gladiatrix:BAAALgAECgQJCAAAAA==.Glaurang:BAABLgAECn8UAAIgAAQJhAYY9QB3AAAgAAQJhAYY9QB3AAAAAA==.Glofor:BAAALgAECgcJEAABLgAECgkJKgAPAKkUAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECggJGAAVAMcWAA==.Gnomeregrets:BAAALgAECgUJBQABLgAECgYJDQAGAAAAAA==.Gnomestone:BAABLgAFFH8MAAIgAAMJ+QNSDwCZAAAgAAMJ+QNSDwCZAAAAAA==.',
Go='Goldencorpse:BAAALgAECgcJCwAAAA==.Goldenspoon:BAAALgAECgUJBQABLgAFFAIJBwAYAGUiAA==.Gorlokk:BAEALgADCgkJDAABLgADCgYJBgAGAAAAAA==.',
Gr='Grakonys:BAABLgAECn9FAAMFAAkJ3xdoEgBOAgAFAAkJ3xdoEgBOAgAEAAcJ4Qc7HQBFAQAAAA==.Granger:BAAALgAECgIJAgABLgAECgIJBAAGAAAAAA==.Greed:BAABLgAECn89AAIWAAkJuR4KCADHAgAWAAkJuR4KCADHAgAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAABLgAECn8aAAIiAAYJpBZiAQAcAQAiAAYJpBZiAQAcAQAAAA==.Grimmvelt:BAAALgAECgQJBAAAAA==.Grounch:BAAALgADCgcJDAAAAA==.Grunch:BAAALgADCgkJCwAAAA==.Grunnck:BAAALgAECgYJBgAAAA==.',
Gu='Guayusa:BAAALgAFFAEJAQAAAA==.Gunned:BAAALgADCgEJAQAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQAGAAAAAA==.',
Ha='Habibane:BAAALgAECgEJAQAAAA==.Hacheron:BAAALgADCgIJAgABLgAFFAUJDQAiAHoQAA==.Hallows:BAAALgAECgYJDgAAAA==.Harnix:BAABLgAECn8tAAIKAAgJ9g46fgByAQAKAAgJ9g46fgByAQAAAA==.Harron:BAAALgAECgUJBQAAAA==.Hawtbooty:BAABLgAECn83AAIJAAkJcByzAQAmAQAJAAkJcByzAQAmAQAAAA==.Haziel:BAEALgADCgYJBgAAAA==.',
He='Heartsbane:BAAALgAECgEJAQAAAA==.Helixrage:BAABLgAECn8XAAIHAAkJ/QUrJQAIAQAHAAkJ/QUrJQAIAQAAAA==.Hellreines:BAACLgAFFH8HAAIYAAQJFhb3AABFAQAYAAQJFhb3AABFAQAuAAQKfyMAAhgACQkzIuIEAHQCABgACQkzIuIEAHQCAAAA.Herpderplol:BAABLgAECn8cAAImAAkJDBGzEACsAQAmAAkJDBGzEACsAQAAAA==.',
Hi='Hildi:BAABLgAECn83AAMnAAgJ+QLyhACUAAAnAAgJ+QLyhACUAAAWAAEJyAEnjAAfAAAAAA==.Him:BAACLgAFFH8HAAITAAMJ0RhlMwDjAAATAAMJ0RhlMwDjAAAuAAQKfyoAAhMACQmcI6sFAAUDABMACQmcI6sFAAUDAAAA.',
Ho='Holy:BAACLgAFFH8MAAIkAAMJGhk1LgDiAAAkAAMJGhk1LgDiAAAuAAQKfz8AAyQACQk3IeEDAF4DACQACQk3IeEDAF4DAAkAAQmDHOtmAEgAAAAA.Holyscales:BAAALgAECgEJAQAAAA==.Hoots:BAAALgAECgQJBQAAAA==.Hottopic:BAAALgAECgcJDAAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgAECgEJAgAAAA==.Humânity:BAAALgADCgYJBgAAAA==.Hurcules:BAAALgAECgUJBQAAAA==.',
['Hø']='Høåx:BAAALgAECgYJBgABLgAECgQJBAAGAAAAAA==.',
['Hü']='Hümänïty:BAAALgAECgcJBQAAAA==.',
Ic='Icicle:BAAALgADCgIJAgAAAA==.',
Il='Illbloodarch:BAABLgAECn8/AAIIAAkJ7BC+EwDDAQAIAAkJ7BC+EwDDAQAAAA==.Illidaris:BAAALgAECggJCQAAAA==.Illvicious:BAABLgAECn8bAAMKAAYJbhFPBwDBAAAKAAYJbhFPBwDBAAABAAIJGgVmTgA2AAAAAA==.',
Im='Imaginos:BAAALgAECgUJBQABLgAECgUJBQAGAAAAAA==.',
In='Incredibread:BAAALgAECggJEwAAAA==.Indub:BAAALgAECgcJCwAAAA==.',
Ir='Ironfistmogu:BAAALgADCgkJCQAAAA==.',
Is='Ishura:BAABLgAECn8uAAILAAgJrwrePABTAQALAAgJrwrePABTAQAAAA==.',
It='Itslevi:BAABLgAECn8VAAIKAAgJRhWcBQDrAAAKAAgJRhWcBQDrAAAAAA==.',
Iv='Ivvy:BAABLgAECn8bAAIeAAgJswrcOQArAQAeAAgJswrcOQArAQAAAA==.',
Iz='Izanami:BAABLgAECn8tAAIcAAkJeR8fBgDYAgAcAAkJeR8fBgDYAgAAAA==.',
Ja='Jadinkalage:BAAALgAECgQJBAAAAA==.Jaewreth:BAAALgAECgcJCAAAAA==.Janntro:BAABLgAECn8hAAMcAAkJyx37DgA3AgAcAAkJphr7DgA3AgAUAAIJgyVvGQDSAAABLgAECgkJIwAOAL8fAA==.Jantra:BAAALgAECgEJAgABLgAECgkJIwAOAL8fAA==.Jantro:BAABLgAECn8jAAIOAAkJvx+UBADNAgAOAAkJvx+UBADNAgAAAA==.Janttro:BAAALgAECgIJBQABLgAECgkJIwAOAL8fAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAACLgAFFH8NAAMVAAQJ0hBHPwDnAAAVAAQJ0hBHPwDnAAASAAQJswQ8NAC+AAAuAAQKfykAAxUACQmyE2I7AMEBABUACQmyE2I7AMEBABIAAwnFCpRsAJEAAAAA.Jeleka:BAAALgAECgYJCAABLgAECgkJLAAVAC8fAA==.Jelmarr:BAABLgAECn8cAAIgAAcJ+xtkAQCZAQAgAAcJ+xtkAQCZAQAAAA==.Jemmâ:BAABLgAECn8UAAIHAAkJ0RkGGwBgAQAHAAkJ0RkGGwBgAQAAAA==.Jerauld:BAABLgAECn82AAImAAgJLxKREwCGAQAmAAgJLxKREwCGAQAAAA==.Jezrra:BAAALgAECggJDwAAAA==.',
Jh='Jhuloot:BAAALgAECgEJAQAAAA==.',
Ji='Jiddles:BAAALgAECgMJBgABLgAECgkJLAAVAC8fAA==.',
Jo='Johnnyzyns:BAABLgAECn8yAAMZAAkJOB3CHQCVAgAZAAkJOB3CHQCVAgAiAAEJthhEWQA7AAAAAA==.Jokhasta:BAABLgAECn8ZAAIXAAgJvBY/CwAYAgAXAAgJvBY/CwAYAgAAAA==.Joshc:BAABLgAECn8yAAIOAAkJHg3QIgA5AQAOAAkJHg3QIgA5AQAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
Ju='Judgejudee:BAAALgADCgcJFgAAAA==.Judgédred:BAAALgAECgcJDAAAAA==.',
['Já']='Ják:BAABLgAECn8cAAQBAAgJzBMPGwA2AQABAAcJJhEPGwA2AQALAAMJvwtZfQBSAAAKAAEJpwOhxAEhAAAAAA==.',
Ka='Kaaris:BAABLgAECn8wAAIfAAkJEBGUCQCuAQAfAAkJEBGUCQCuAQAAAA==.Kaetora:BAAALgADCgkJEgAAAA==.Kaiarie:BAABLgAECn8kAAIlAAgJAwk7EwA4AQAlAAgJAwk7EwA4AQAAAA==.Kainraziel:BAACLgAFFH8HAAIMAAMJEQyeaQC5AAAMAAMJEQyeaQC5AAAuAAQKfx4AAgwACQkMFWc8ANYBAAwACQkMFWc8ANYBAAAA.Kairos:BAABLgAECn9OAAIPAAkJDhMwRgAIAgAPAAkJDhMwRgAIAgAAAA==.Kalasta:BAAALgADCgIJAgAAAA==.Kanofworms:BAAALgAECgYJDgAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karem:BAAALgAECgEJAQAAAA==.Karkea:BAAALgAECgEJBAAAAA==.Kayper:BAAALgAECgcJAgAAAA==.Kayyos:BAAALgAECgkJCQAAAA==.',
Ke='Kebin:BAABLgAECn8xAAIHAAkJvhf6DgD6AQAHAAkJvhf6DgD6AQAAAA==.Kekkoken:BAAALgAECgEJAQAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgABLgAECgkJKwAhAEEaAA==.',
Ki='Kibil:BAAALgAECgYJDgABLgAECgkJKQAZAHMOAA==.Killmonger:BAAALgAECgYJCwAAAA==.Kimsambo:BAAALgAECgQJBAAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Kn='Knocksteady:BAAALgAECgUJCgAAAA==.',
Ko='Koga:BAAALgAECgQJBAAAAA==.Korax:BAAALgAECgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAABLgAECn8yAAIDAAkJTiNfAQCMAwADAAkJTiNfAQCMAwAAAA==.Korzillian:BAAALgAECgEJAQAAAA==.Kos:BAACLgAFFH8RAAIQAAQJxiWdCgC1AQAQAAQJxiWdCgC1AQAuAAQKfyUAAhAACQlFIjIFAAMDABAACQlFIjIFAAMDAAAA.',
Kr='Kreyali:BAAALgAECgIJAwAAAA==.Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgcJEwAAAA==.Kuntar:BAAALgAECgcJCwAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurkoh:BAAALgAECgIJBAAAAA==.Kurrent:BAABLgAECn8sAAIVAAkJLx88EgC7AgAVAAkJLx88EgC7AgAAAA==.',
['Kÿ']='Kÿtten:BAABLgAECn8kAAIBAAkJwwqpGQBMAQABAAkJwwqpGQBMAQAAAA==.',
La='Lad:BAACLgAFFH8KAAIZAAQJRRZwYgAxAQAZAAQJRRZwYgAxAQAuAAQKfxkAAxkACQm5HxgSAN0CABkACQm5HxgSAN0CABgAAQkeCqMXADEAAAAA.Laiyth:BAABLgAECn8bAAIgAAkJfxISPgDkAQAgAAkJfxISPgDkAQAAAA==.Lanfearz:BAAALgADCgEJAQAAAA==.Larryfish:BAABLgAECn8oAAMZAAkJZCGTHACcAgAZAAkJeyCTHACcAgAYAAgJTB7cBAB1AgAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgMJBgAAAA==.Lavos:BAABLgAECn8wAAIfAAkJ1A7fCwCBAQAfAAkJ1A7fCwCBAQAAAA==.',
Le='Levitikus:BAAALgAFFAEJAgAAAA==.Levìtikus:BAAALgAECgEJAgAAAA==.',
Li='Lideysse:BAAALgAECgMJAwAAAA==.Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lilslippah:BAAALgAECgUJBQAAAA==.Lisster:BAABLgAECn8zAAMRAAkJzyAeEQDIAgARAAkJzyAeEQDIAgAhAAEJkAG2mAAeAAAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8dAAMLAAkJNhuwIAAWAgALAAkJNhuwIAAWAgABAAEJBBULQQA5AAAAAA==.Lizcandor:BAAALgAECgQJEQAAAA==.',
Lo='Loafe:BAACLgAFFH8QAAIKAAQJNQ0MUQANAQAKAAQJNQ0MUQANAQAuAAQKfyoAAgoACAk6DyNlALYBAAoACAk6DyNlALYBAAAA.Lokni:BAAALgAECgYJEQAAAA==.Loriann:BAAALgAECgEJAQAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgAECggJDgAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgcJBwAAAA==.Luthais:BAABLgAECn8eAAIBAAkJMw3BHAAvAQABAAkJMw3BHAAvAQAAAA==.Luxury:BAABLgAECn9MAAIHAAkJqQRzJQAGAQAHAAkJqQRzJQAGAQAAAA==.',
Ly='Lykanthropos:BAAALgAECgEJAQAAAA==.',
Ma='Mahroq:BAABLgAECn8mAAMJAAgJwhk2HgDtAQAJAAgJnxk2HgDtAQAkAAYJoQl2SQDfAAABLgAFFAIJAgAGAAAAAA==.Maingauche:BAAALgAECgQJBAABLgAECgkJNAAGAAAAAA==.Mako:BAACLgAFFH8VAAMDAAQJqRQBGwDmAAADAAQJqRQBGwDmAAAFAAIJcQFvYABVAAAuAAQKfyUAAgMACAkKIZcEAOACAAMACAkKIZcEAOACAAAA.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8nAAMEAAgJDwy5DgAgAQAFAAcJtgq8NQAjAQAEAAgJygi5DgAgAQAAAA==.Malfuridan:BAAALgAECgMJAgAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Mandas:BAAALgAECgIJAgAAAA==.Maplebarkles:BAAALgAECgEJAQAAAA==.Maples:BAABLgAECn8nAAMnAAkJXwoSQwBhAQAnAAkJXwoSQwBhAQAWAAMJ3gHRwQAVAAAAAA==.Mariasha:BAABLgAECn8gAAIRAAYJnQ70jgAhAQARAAYJnQ70jgAhAQAAAA==.Marichika:BAAALgADCgcJEQAAAA==.Maryjaine:BAAALgAECgUJDAAAAA==.Mattdeamon:BAEALgADCgUJBwABLgAFFAUJGAAPADcMAA==.Mazzikin:BAACLgAFFH8HAAIMAAMJvhvFVQDuAAAMAAMJvhvFVQDuAAAuAAQKfy8AAgwACQmYIL8KAPQCAAwACQmYIL8KAPQCAAAA.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Megaterium:BAABLgAECn89AAMJAAkJLxszDgCEAgAJAAkJLxszDgCEAgAQAAcJHQwWTgDXAAAAAA==.Melkoor:BAAALgADCgcJFwAAAA==.Menethil:BAABLgAECn8jAAMLAAgJoiP5DADBAgALAAgJoiP5DADBAgAKAAEJbxbMEwBEAAAAAA==.Metheuz:BAAALgAECgcJCwAAAA==.Mexican:BAABLgAECn8yAAIPAAkJPxP+SgD6AQAPAAkJPxP+SgD6AQAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgAECgUJEgAAAA==.Mishgrail:BAABLgAECn9BAAIdAAkJOyGSBAD8AgAdAAkJOyGSBAD8AgAAAA==.Misosoup:BAAALgAECgUJBQABLgADCgEJAQAGAAAAAA==.Missmisery:BAABLgAECn8wAAMRAAkJAxI+OgD2AQARAAkJAxE+OgD2AQACAAMJAw7hAQC+AAAAAA==.Mithdraug:BAABLgAECn8dAAQeAAkJ2xKfMwBLAQAeAAgJFRKfMwBLAQANAAQJdwYxwABFAAAmAAEJwAfHXwAiAAAAAA==.Mitzi:BAACLgAFFH8YAAMZAAcJ0RZlMgCfAQAZAAYJ0RZlMgCfAQAiAAEJAABoZQAAAAAuAAQKfyQAAhkACQlwI14aAN8CABkACQlwI14aAN8CAAAA.',
Mo='Modrem:BAAALgADCgkJGwAAAA==.Mokhan:BAAALgADCgkJCQAAAA==.Molsan:BAAALgAECgQJBAAAAA==.Monache:BAABLgAECn8ZAAITAAgJdAvROQBfAQATAAgJdAvROQBfAQAAAA==.Mongalf:BAAALgADCgQJBAAAAA==.Montrois:BAAALgAECgQJBAAAAA==.Moocheala:BAAALgAECgEJAQAAAA==.Moofahsa:BAAALgAECgEJAQAAAA==.Moopally:BAAALgAECgQJCAAAAA==.Mortarîon:BAAALgAECgIJAgAAAA==.',
My='Mythrilblade:BAAALgAECgcJCQAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Na='Naromir:BAAALgAECgcJEAAAAA==.Nastytaco:BAAALgADCgMJAwABLgAECgkJIQAPAD0RAA==.',
Ne='Neletheus:BAABLgAECn8WAAIgAAcJihCggwAxAQAgAAcJihCggwAxAQAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAABLgAECn8fAAIZAAkJFSF5JABzAgAZAAkJFSF5JABzAgAAAA==.Nirvanik:BAAALgAECgQJBQAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECgkJQQAdADshAA==.',
No='Notditar:BAAALgAECgEJAQAAAA==.',
Nu='Nukusmaximus:BAABLgAECn8yAAIPAAgJIgkrmgBFAQAPAAgJIgkrmgBFAQAAAA==.',
Ny='Nyeneave:BAAALgAECgIJAgAAAA==.Nyiah:BAABLgAECn8vAAINAAkJNBpaFgCVAgANAAkJNBpaFgCVAgAAAA==.Nyxiie:BAAALgADCgIJAgAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Od='Odioz:BAAALgAECgMJAwAAAA==.',
Of='Offset:BAAALgAECgEJAgAAAA==.',
Og='Ogdoadtl:BAAALgAECgQJCgAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.',
On='Onex:BAAALgAECggJDAAAAA==.',
Or='Organicmeat:BAAALgAECggJCQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.Ori:BAAALgAECgQJCgAAAA==.',
Pa='Paleprincess:BAAALgADCgIJAgABLgAECgIJBAAGAAAAAA==.Palii:BAAALgAECgQJBQAAAA==.Partywizard:BAAALgAECgMJAwAAAA==.',
Pe='Persefini:BAACLgAFFH8FAAINAAMJKQI2WQBnAAANAAMJKQI2WQBnAAAuAAQKfxgAAg0ACQk9Cn5TAEIBAA0ACQk9Cn5TAEIBAAAA.Persephoneia:BAAALgADCgcJDQAAAA==.Petrokull:BAABLgAECn8YAAIOAAYJnAPoUABrAAAOAAYJnAPoUABrAAAAAA==.',
Ph='Phaeder:BAAALgAECgEJAQAAAA==.Pheeguh:BAAALgADCgkJEAAAAA==.Pheylan:BAABLgAECn8UAAICAAkJTRAuHAC7AQACAAkJTRAuHAC7AQAAAA==.Philidox:BAAALgAECgYJCgABLgAECggJHAABAMwTAA==.Phood:BAAALgAECgEJAgABLgAECgYJDAAGAAAAAA==.',
Pi='Piety:BAAALgAECgYJBgAAAA==.Pikxs:BAAALgAECgMJAgAAAA==.Pitchou:BAAALgAECgUJCAAAAA==.',
Pl='Plugugly:BAAALgAECgQJBgAAAA==.',
Po='Poenin:BAAALgAECgUJCAABLgAECgkJKwAhAEEaAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8fAAIRAAkJHQ1SWACbAQARAAkJHQ1SWACbAQAAAA==.Potatobear:BAACLgAFFH8NAAIRAAQJGyWJFwCtAQARAAQJGyWJFwCtAQAuAAQKfzUABBEACQm+JaYCAGYDABEACQm+JaYCAGYDACEABglfI/EZAFsCAAIACQlgGioPADsCAAAA.',
Pr='Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgAECgMJBAAAAA==.',
Qi='Qiursi:BAAALgAECgUJBQAAAA==.',
Qu='Quicktime:BAABLgAECn9IAAIMAAkJvhzFFACcAgAMAAkJvhzFFACcAgAAAA==.',
Ra='Rafael:BAAALgAECgYJBgABLgAFFAQJFQADAKkUAA==.Ragedh:BAABLgAECn8XAAIMAAkJ+BoSGQB/AgAMAAkJ+BoSGQB/AgAAAA==.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ragnoir:BAAALgAECggJEAAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAAALgADCgEJAQAAAA==.Rashish:BAAALgADCgcJAgAAAA==.Ravies:BAACLgAFFH8FAAIRAAMJSBSbXgDnAAARAAMJSBSbXgDnAAAuAAQKfx4AAhEACQkxHs0QAMoCABEACQkxHs0QAMoCAAAA.Rawdøg:BAAALgADCgEJAQAAAA==.Rayaz:BAAALgAECgUJCwABLgAECgkJFwANAHkYAA==.',
Re='Reeses:BAEALgAECgkJEwABLgADCgYJBgAGAAAAAA==.Refellos:BAAALgAECgEJAgAAAA==.Reinhearts:BAAALgAFFAEJAQAAAA==.Religgar:BAABLgAECn8xAAIZAAkJ7Bh7KQBbAgAZAAkJ7Bh7KQBbAgAAAA==.Reploidzero:BAAALgAECgUJAQAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAABLgAECn89AAIPAAkJWRWHPgAiAgAPAAkJWRWHPgAiAgAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Roglof:BAABLgAECn8qAAIPAAgJqRSVZwCtAQAPAAgJqRSVZwCtAQAAAA==.Rokkoks:BAAALgAECgIJAgAAAA==.Rowlah:BAAALgAECgcJDgAAAA==.Roxyfoxy:BAAALgAECgcJEAAAAA==.Rozy:BAABLgAECn8/AAMLAAkJRB5uEgB/AgALAAkJRB5uEgB/AgAKAAUJZxgdrgAiAQAAAA==.',
Ru='Ruffs:BAABLgAECn8XAAMMAAkJIR1AGwBxAgAMAAkJIR1AGwBxAgAUAAEJYhDoMwA0AAAAAA==.Ruiizu:BAABLgAECn8yAAIKAAkJJiTcCQAZAwAKAAkJJiTcCQAZAwAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn9GAAIkAAkJeB2SCgDHAgAkAAkJeB2SCgDHAgAAAA==.',
Sa='Saberjaw:BAABLgAECn8XAAMCAAYJrBU3FACCAQACAAYJkRQ3FACCAQARAAIJvwtKGAFEAAAAAA==.Sairicck:BAABLgAECn8tAAIRAAkJcx7zGgCDAgARAAkJcx7zGgCDAgAAAA==.Samaal:BAAALgADCgUJBQABLgAECgkJIwAOAL8fAA==.Samial:BAAALgADCgYJDAABLgAECgkJIwAOAL8fAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgAECgEJAQAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satorugojo:BAAALgAECgEJAQAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selenar:BAAALgAECgEJAQAAAA==.Selesé:BAAALgAECgEJAQABLgAECgkJFAAHANEZAA==.Selinora:BAAALgAECgkJDgAAAA==.Senaria:BAAALgAECgMJBwAAAA==.Serhalatath:BAAALgAECggJDAAAAA==.',
Sh='Shade:BAAALgADCgQJBAAAAA==.Shadowsbane:BAAALgAFFAIJAgAAAA==.Shaguar:BAABLgAECn8rAAMKAAkJ0CDhEgDRAgAKAAkJ0CDhEgDRAgALAAcJPhCGXAALAQAAAA==.Shamhawk:BAAALgAECgEJAgAAAA==.Shaolinsnake:BAACLgAFFH8FAAITAAMJ9hOzMwDiAAATAAMJ9hOzMwDiAAAuAAQKfxcAAhMACQmLHesZAB4CABMACQmLHesZAB4CAAAA.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.Shizzite:BAAALgADCgIJAgAAAA==.Shonuph:BAAALgAECgMJAwAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAACLgAFFH8UAAIPAAQJPgcscgD8AAAPAAQJPgcscgD8AAAuAAQKfyQAAg8ACAmWElxpAAMCAA8ACAmWElxpAAMCAAAA.Sinzala:BAABLgAECn8iAAIPAAkJVR/KHQCqAgAPAAkJVR/KHQCqAgAAAA==.',
Sk='Skeetsurfin:BAAALgAECgMJAwAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwABLgAECgkJKwAKANAgAA==.',
Sm='Smallblackdk:BAAALgAFFAIJAwAAAA==.Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.Snowbunnyy:BAAALgAECgEJAQABLgAECgIJBAAGAAAAAA==.',
So='Solai:BAAALgAECgEJAQAAAA==.Solenne:BAAALgAECgQJBAABLgAFFAUJBgALAGMFAA==.Solsti:BAACLgAFFH8GAAILAAUJYwXeIwABAQALAAUJYwXeIwABAQAuAAQKf0cAAgsACQnAGasAANcBAAsACQnAGasAANcBAAAA.Soulhunter:BAABLgAFFH8IAAIiAAcJdgSZHwDqAAAiAAcJdgSZHwDqAAABLgAFFAgJMAAiAJgaAA==.',
Sp='Spears:BAABLgAECn8bAAIRAAcJjganlwARAQARAAcJjganlwARAQAAAA==.Spoonarrow:BAAALgAECgEJAQABLgAFFAIJBwAYAGUiAA==.Spoonbrew:BAAALgAECgYJBgABLgAFFAIJBwAYAGUiAA==.Spoondot:BAABLgAECn8mAAMlAAkJ3iWLAQDjAgAlAAgJpySLAQDjAgAgAAgJbSPcFgCbAgABLgAFFAIJBwAYAGUiAA==.Spoonknight:BAACLgAFFH8HAAMYAAIJZSKCHQCXAAAZAAIJIh4WwgCmAAAYAAIJxBSCHQCXAAAuAAQKfx8ABBgACQl/IFMFAGUCABkACAnEHcMmAGgCABgACAmXH1MFAGUCACIABQluGUAlACkBAAAA.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Staceyrella:BAAALgAECgEJAwAAAA==.Stainpngolin:BAABLgAECn8gAAIOAAgJsh3iCQBKAgAOAAgJsh3iCQBKAgAAAA==.Stillhorn:BAABLgAECn8tAAMMAAkJTRokJgA0AgAMAAkJ4RgkJgA0AgAcAAgJGRvgDwAqAgAAAA==.Stinjeras:BAABLgAECn8yAAIgAAkJoSGDDQDhAgAgAAkJoSGDDQDhAgAAAA==.Stinkyjo:BAABLgAECn8yAAINAAkJbxrNEgC1AgANAAkJbxrNEgC1AgAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAACLgAFFH8KAAIRAAUJ9wqHRwAeAQARAAUJ9wqHRwAeAQAuAAQKfyIAAhEACQmGHkchAGECABEACQmGHkchAGECAAAA.',
Su='Suian:BAAALgADCgEJAQAAAA==.Sunadoria:BAAALgAECgUJEwAAAA==.Sunlite:BAAALgAECgEJBAAAAA==.Sunrae:BAABLgAECn8yAAQkAAgJMRpZFAA7AgAkAAgJZxhZFAA7AgAQAAYJZwnkSwDgAAAJAAMJShQXXQC+AAAAAA==.Sushi:BAABLgAECn8fAAIdAAkJlRMlGQDdAQAdAAkJlRMlGQDdAQAAAA==.',
Sv='Sven:BAAALgAECgUJCQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAABLgAECn8bAAIJAAYJ2gh+AwCUAAAJAAYJ2gh+AwCUAAAAAA==.',
['Sö']='Söap:BAAALgAECgYJCAAAAA==.',
Ta='Taggert:BAAALgAECgEJAQAAAA==.Tahl:BAABLgAECn86AAIJAAcJlxY0AQBxAQAJAAcJlxY0AQBxAQAAAA==.Talox:BAAALgAECgEJAQAAAA==.Tamanovitch:BAAALgAECgEJAQAAAA==.Tamashii:BAAALgAFFAIJAwABLgAFFAQJFQADAKkUAA==.Tangriah:BAAALgADCgEJAQAAAA==.Taproot:BAEALgADCgEJAQABLgAFFAUJGAAPADcMAA==.Taryen:BAAALgAECgUJCgABLgAECgkJFwAMAPgaAA==.Tavie:BAABLgAFFH8QAAIPAAQJ8xeBXAAmAQAPAAQJ8xeBXAAmAQAAAA==.',
Te='Teamet:BAAALgAECgEJAQAAAA==.Teddy:BAAALgADCgYJBgAAAA==.Tedo:BAAALgAECgEJAQABLgAFFAUJGQALABkfAA==.Teikkas:BAAALgAECggJDQAAAA==.Telaari:BAAALgAECgQJBwAAAA==.',
Th='Thalenia:BAACLgAFFH8TAAIRAAQJnwbYVAD+AAARAAQJnwbYVAD+AAAuAAQKfy0AAyEACAnTDeIbAM8AACEACAlhBuIbAM8AABEACAnTDdoKAIUAAAAA.Thallenia:BAAALgADCgEJAQAAAA==.Thalron:BAAALgAECgEJAQAAAA==.Thayne:BAAALgADCgYJBwAAAA==.Thekingdom:BAACLgAFFH8FAAIPAAIJWA+soQCLAAAPAAIJWA+soQCLAAAuAAQKfx4AAg8ACAlWHV9FAGcCAA8ACAlWHV9FAGcCAAAA.Therealnasus:BAAALgADCgMJAwAAAA==.Thom:BAAALgAECgIJAgAAAA==.Thriller:BAAALgAFFAMJAwABLgAFFAUJGQALABkfAA==.',
Ti='Tikeidari:BAABLgAECn9RAAIUAAkJZCYoAAB9AwAUAAkJZCYoAAB9AwAAAA==.Tiltedtroll:BAABLgAECn8rAAISAAkJnhJjKACrAQASAAkJnhJjKACrAQAAAA==.Timedemon:BAABLgAECn8mAAIMAAkJcRuYKQAjAgAMAAkJcRuYKQAjAgAAAA==.Tinuveuil:BAAALgADCgYJBgAAAA==.',
To='Toiletseat:BAAALgAECgUJBQAAAA==.Tombfyre:BAAALgAECgUJAQABLgAECggJGQAcAJ0YAA==.Tonjuras:BAABLgAECn8zAAMoAAkJ1SKOBADzAgAoAAkJLR+OBADzAgAjAAgJJB4WBABcAgAAAA==.Toona:BAACLgAFFH8FAAIMAAIJ5AmTiwBsAAAMAAIJ5AmTiwBsAAAuAAQKfxwAAgwACQn7GgYcAKoCAAwACQn7GgYcAKoCAAEuAAUUBAkKABkARRYA.Torogrande:BAAALgAECgUJBQAAAA==.Touchmyting:BAAALgAECgEJAwAAAA==.Toutii:BAAALgAECgUJBgABLgAECgkJGAAaAIEfAA==.',
Tr='Trappybear:BAAALgAFFAEJAQABLgAFFAUJDQAiAHoQAA==.Trappydh:BAABLgAFFH8JAAIUAAQJbRDxBwDXAAAUAAQJbRDxBwDXAAABLgAFFAUJDQAiAHoQAA==.Trappydk:BAACLgAFFH8NAAIiAAUJehD7IQDaAAAiAAUJehD7IQDaAAAuAAQKfxcAAiIACAnPGt4UAMgBACIACAnPGt4UAMgBAAAA.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8sAAMgAAgJsSStCwAdAwAgAAgJsSStCwAdAwAlAAEJAADgIQBqAAAAAA==.',
Ty='Tyraxus:BAAALgADCgkJEAAAAA==.Tyronne:BAAALgAECgcJBwAAAA==.',
Ul='Ultraball:BAAALgAECggJDwAAAA==.',
Un='Unagi:BAABLgAECn8sAAICAAkJfg7wFwDiAQACAAkJfg7wFwDiAQAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAABLgAECn8YAAIPAAgJOAgbnwA8AQAPAAgJOAgbnwA8AQAAAA==.Vaesir:BAAALgADCgcJDQAAAA==.Varleara:BAABLgAECn8gAAMMAAgJziFEEwDmAgAMAAgJziFEEwDmAgAUAAEJKQeHLQAqAAAAAA==.',
Ve='Vehlahi:BAAALgAECgQJCQAAAA==.Venenn:BAAALgADCgEJAgAAAA==.Venev:BAAALgAECgYJEQAAAA==.Ventana:BAACLgAFFH8FAAIXAAIJgBfkEgCaAAAXAAIJgBfkEgCaAAAuAAQKf0QAAhcACQllI0MBAC8DABcACQllI0MBAC8DAAAA.Verdilac:BAABLgAECn81AAIKAAkJexxXQwD8AQAKAAkJexxXQwD8AQABLgAFFAUJGAAmAMshAA==.',
Vi='Vinceglortho:BAABLgAECn8WAAIRAAYJKAx/BgDgAAARAAYJKAx/BgDgAAAAAA==.Vindicator:BAABLgAECn8fAAIKAAkJSB3EIACEAgAKAAkJSB3EIACEAgAAAA==.Violetnoir:BAAALgAECgQJBAABLgAECgcJGgAgANsIAA==.Visiroth:BAABLgAECn8pAAMZAAkJcw4caACWAQAZAAkJJAscaACWAQAiAAgJHQtlJQAoAQAAAA==.',
Vy='Vyyral:BAAALgAECgUJBwABLgAECgkJIwAOAL8fAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAFFAQJFAAPAD4HAA==.Wallydk:BAABLgAECn8xAAIZAAkJTBuXHQCWAgAZAAkJTBuXHQCWAgAAAA==.Wanji:BAABLgAECn8rAAIZAAkJCwuuZwCXAQAZAAkJCwuuZwCXAQAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Wenesday:BAAALgADCgcJGQAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Widginatrix:BAABLgAECn8ZAAIeAAgJwA37MQBTAQAeAAgJwA37MQBTAQAAAA==.Willkain:BAAALgAECgMJAwAAAA==.',
Wo='Woah:BAAALgAECgMJAwABLgAFFAIJBwAYAGUiAA==.Woons:BAAALgAECgMJCAAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Wy='Wytewytch:BAAALgADCgQJBAAAAA==.',
Xa='Xaharst:BAAALgADCgYJBgAAAA==.Xaya:BAABLgAECn8aAAMgAAcJ2wgynwAAAQAgAAcJ2wgynwAAAQAfAAQJ6AJJUQB6AAAAAA==.',
Xe='Xenophorge:BAAALgAFFAEJAQAAAA==.Xeralvezyn:BAAALgAECgYJCAAAAA==.',
Xi='Xiva:BAABLgAECn80AAIoAAgJ7BKCHACxAQAoAAgJ7BKCHACxAQAAAA==.',
Xo='Xovace:BAABLgAECn8aAAMcAAkJdAy4KQAwAQAcAAkJSwy4KQAwAQAMAAIJ8QYTCQFBAAAAAA==.',
Xt='Xtayse:BAABLgAECn8rAAIEAAkJuCA2AQD5AgAEAAkJuCA2AQD5AgAAAA==.Xtaysì:BAAALgAECgEJAQAAAA==.',
Ya='Yagorbomb:BAAALgAECgMJBQAAAA==.Yamyam:BAABLgAECn8VAAIeAAkJsg/HKQCyAQAeAAkJsg/HKQCyAQAAAA==.',
Yi='Yirya:BAAALgAECgYJCwAAAA==.',
Yo='Yoruechi:BAACLgAFFH8WAAIOAAQJ3iC+BwB6AQAOAAQJ3iC+BwB6AQAuAAQKfysAAg4ACAkoI3MFALUCAA4ACAkoI3MFALUCAAAA.',
Yu='Yuridia:BAAALgADCgEJAQAAAA==.',
['Yú']='Yúmyúm:BAABLgAECn8lAAIKAAkJWBdDSQDqAQAKAAkJWBdDSQDqAQAAAA==.',
Za='Zahel:BAABLgAECn8uAAIKAAkJlB7cGACuAgAKAAkJlB7cGACuAgAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECgkJLgAKAJQeAA==.Zalark:BAAALgADCgUJCgABLgAECgkJNQAJAJwUAA==.Zangai:BAAALgAECggJCAABLgAECggJGQATAHQLAA==.Zavier:BAAALgAECgQJBAABLgAECgYJDAAGAAAAAA==.',
Ze='Zeneri:BAABLgAECn84AAMnAAkJhRCrKwDSAQAnAAkJhRCrKwDSAQAWAAkJyRAkHQDFAQAAAA==.',
Zo='Zobi:BAABLgAECn8aAAIMAAYJsxLgAgATAQAMAAYJsxLgAgATAQAAAA==.Zodius:BAAALgADCgEJAQAAAA==.Zomboo:BAAALgAFFAEJAQAAAA==.',
Zu='Zugzugzug:BAAALgADCgMJBgAAAA==.Zuhali:BAAALgADCgQJBAAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAFFAQJDQAVANIQAA==.',
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
