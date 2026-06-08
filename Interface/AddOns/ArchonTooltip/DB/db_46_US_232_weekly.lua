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

local lookup = {'Hunter-Survival','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Warrior-Protection','Warrior-Arms','Priest-Holy','Paladin-Retribution','Paladin-Holy','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Mage-Frost','Priest-Shadow','Hunter-BeastMastery','Shaman-Elemental','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Mage-Fire','Monk-Brewmaster','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','Priest-Discipline','Warlock-Affliction','DemonHunter-Havoc','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-06-07',data={Ac='Acelara:BAAALgADCgUJBQAAAA==.',
Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ah='Ahmet:BAABLgAECn8WAAIBAAkJZhM3FAACAgABAAkJZhM3FAACAgABLgAECgkJRQACAMAeAA==.',
Ai='Aiax:BAACLgAFFH8IAAIDAAMJRAJgIgB8AAADAAMJRAJgIgB8AAAuAAQKfxcABAQACAlODDQgACwBAAUABgmnDb0xADoBAAQABglkCjQgACwBAAMAAglJB0VGAEAAAAAA.',
Al='Alderok:BAAALgAECgIJBQABLgAECgYJBwAGAAAAAA==.Aliancia:BAABLgAECn83AAMHAAgJSRUfFgCKAQAHAAgJSRUfFgCKAQAIAAMJ3AbfYwBNAAAAAA==.Almur:BAAALgAECgcJDAAAAA==.Alyda:BAAALgADCggJFAAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amet:BAABLgAECn9FAAICAAkJwB7TAwDEAgACAAkJwB7TAwDEAgAAAA==.',
An='Anakinn:BAAALgAECgUJBQAAAA==.Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8wAAIJAAkJBxu2EgA6AgAJAAkJBxu2EgA6AgAAAA==.Antherina:BAAALgADCgQJBwAAAA==.Antonious:BAAALgADCgMJAwAAAA==.Antonlavay:BAAALgAECgQJBAAAAA==.',
Ap='Aphyra:BAAALgADCgUJBQAAAA==.Apollyon:BAACLgAFFH8MAAIKAAQJJSEZIQBwAQAKAAQJJSEZIQBwAQAuAAQKfycAAwoACQnEIcwQANcCAAoACQnEIcwQANcCAAsAAgkqFax+AH8AAAAA.',
Ar='Arlechino:BAACLgAFFH8QAAIMAAQJ8AyBSQABAQAMAAQJ8AyBSQABAQAuAAQKfx0AAgwACAkXF1lAAPMBAAwACAkXF1lAAPMBAAAA.Arywyn:BAABLgAECn8aAAINAAcJNwsoZQD9AAANAAcJNwsoZQD9AAAAAA==.',
As='Assclapiuss:BAABLgAECn83AAMKAAkJiyXBBABMAwAKAAkJiyXBBABMAwALAAEJTwe9kQApAAAAAA==.Asterchades:BAABLgAECn9LAAIOAAkJcR5oBQCoAgAOAAkJcR5oBQCoAgAAAA==.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgkJEAAAAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn9IAAIPAAkJ+gPcmQBCAQAPAAkJ+gPcmQBCAQAAAA==.Atuan:BAABLgAECn8ZAAIQAAcJfxIILwBcAQAQAAcJfxIILwBcAQAAAA==.',
Au='Auralass:BAABLgAECn8bAAIRAAgJXRZpQwDNAQARAAgJXRZpQwDNAQAAAA==.Aurene:BAAALgAECgkJNAAAAQ==.Autym:BAAALgADCgkJCQAAAA==.',
Av='Avaric:BAAALgAECgEJAQABLgAECggJFAASADMEAA==.Avatard:BAAALgAECgIJAgABLgAFFAQJEQAPAD4HAA==.Avilla:BAAALgAECgUJBgAAAA==.',
Ax='Axem:BAABLgAECn8uAAITAAkJmB3fDACXAgATAAkJmB3fDACXAgAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azulathan:BAABLgAECn8bAAMUAAgJ3BaBCQDFAQAUAAgJ3BaBCQDFAQAMAAcJwwq9jgAEAQABLgAECggJNAAVAP4TAA==.',
Ba='Bamseyn:BAAALgADCgYJCwAAAA==.Bamsheyn:BAAALgADCgkJCQAAAA==.Baraxor:BAABLgAECn80AAMVAAgJ/hOjQACfAQAVAAgJ/hOjQACfAQASAAgJrw/aPAA0AQAAAA==.Barrelaged:BAAALgAECgQJBwAAAA==.',
Be='Beerguy:BAABLgAECn8ZAAIWAAgJrgykLwA+AQAWAAgJrgykLwA+AQAAAA==.Behemothe:BAABLgAECn9DAAIXAAkJ2iE/AgD2AgAXAAkJ2iE/AgD2AgAAAA==.Berníesandrs:BAABLgAECn8xAAIPAAkJpA6vXwC7AQAPAAkJpA6vXwC7AQAAAA==.Beryllos:BAAALgAECgQJDAAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECggJDgAAAA==.Bigdamage:BAAALgAECgIJAgABLgAFFAIJBwAYAGUiAA==.Bigdmg:BAABLgAFFH8FAAIZAAIJVRcbvwCVAAAZAAIJVRcbvwCVAAAAAA==.Biggusdiscus:BAAALgAECgMJAwAAAA==.Bigimpin:BAAALgADCgcJBwAAAA==.Bisky:BAAALgAECggJDQABLgAECgkJIgAOAL8fAA==.',
Bj='Bjôrn:BAAALgAECgcJDQAAAA==.',
Bl='Bledana:BAAALgAECgcJDQAAAA==.Bleué:BAAALgADCgEJAQABLgAECgkJOwANAPEaAA==.Bloodmourne:BAABLgAECn8yAAIZAAkJmSUQBQBRAwAZAAkJmSUQBQBRAwAAAA==.Bloodytoutii:BAABLgAECn8UAAQaAAgJjh8HAgBLAgAaAAYJ3yEHAgBLAgAbAAUJNxIsCQDgAAAPAAEJAAAXeQEAAAAAAA==.',
Bo='Borthyr:BAABLgAECn8tAAMFAAkJvx96CADLAgAFAAkJoR56CADLAgAEAAYJ0RyqDgDwAQAAAA==.Bortman:BAAALgAECgUJCQABLgAECgkJLQAFAL8fAA==.Bowowner:BAABLgAECn8hAAIRAAgJxh6EOwDnAQARAAgJxh6EOwDnAQAAAA==.',
Br='Branchmanagr:BAABLgAECn8iAAIOAAkJ6RFyEwCtAQAOAAkJ6RFyEwCtAQAAAA==.Breddamon:BAAALgADCgMJAwAAAA==.Brewlee:BAAALgAFFAMJAwAAAA==.Bricter:BAAALgADCgkJCQABLgAECgkJPQAPAFkVAA==.Brokenkrayon:BAAALgAECgQJBgAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Bulastus:BAAALgAECgEJAgAAAA==.Bullséye:BAAALgAECgEJAQAAAA==.Burntsteak:BAAALgAECgEJAgAAAA==.Busta:BAABLgAECn8fAAIPAAkJZwUUqQAoAQAPAAkJZwUUqQAoAQAAAA==.',
Bw='Bwicked:BAABLgAECn8lAAIPAAkJ/he9MQBMAgAPAAkJ/he9MQBMAgAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgcJDwAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Calzone:BAAALgAECggJDwAAAA==.Cantpurge:BAAALgAECgMJAwABLgAECgcJFwAQAAkIAA==.Carebears:BAAALgAECgQJBQAAAA==.Caroline:BAAALgAECgEJAQAAAA==.',
Ce='Celonge:BAAALgAECgUJBQABLgAFFAUJBQALAGMFAA==.',
Ch='Chamelean:BAAALgAECgYJEQABLgAECgkJHgAMAAwVAA==.Charmcaster:BAAALgAECgEJAQAAAA==.Chimpnzthat:BAABLgAECn81AAIcAAgJ1BN8IACcAQAcAAgJ1BN8IACcAQAAAA==.Chookicookie:BAABLgAECn9HAAMSAAkJ9h7GCQC4AgASAAkJ9h7GCQC4AgAVAAkJ1SCFEwCmAgAAAA==.Chrome:BAABLgAECn9LAAMdAAkJviOiAgBFAwAdAAkJviOiAgBFAwANAAgJyB1+HgBLAgAAAA==.Chuckarita:BAABLgAECn8gAAIdAAkJnQqbMABOAQAdAAkJnQqbMABOAQAAAA==.',
Ci='Cindyy:BAABLgAECn8iAAIWAAgJiyFJCwCGAgAWAAgJiyFJCwCGAgABLgAFFAQJCwARADscAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgIJAgAAAA==.',
Co='Coedwig:BAAALgADCgYJBwAAAA==.Consfiracy:BAAALgAFFAEJAQAAAA==.Coresh:BAAALgAECgkJEAAAAA==.Cornpuff:BAABLgAECn8YAAMeAAcJECWjCQCeAQAeAAUJ+CSjCQCeAQAfAAMJpCTAfQA5AQAAAA==.Cortiz:BAABLgAECn9CAAIRAAkJaRKyPADjAQARAAkJaRKyPADjAQAAAA==.',
Cr='Crankdog:BAABLgAECn8rAAMRAAkJ1iQEBQA7AwARAAkJ1iQEBQA7AwAgAAYJ8g9oSgApAQAAAA==.Creedd:BAABLgAECn8vAAINAAgJGiC5EwClAgANAAgJGiC5EwClAgABLgAECgkJGwAVAMIfAA==.Crialta:BAAALgADCgcJFAAAAA==.',
Cu='Cupsandcakes:BAABLgAECn8dAAIaAAgJ7wn5BgA3AQAaAAgJ7wn5BgA3AQAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Damessiah:BAABLgAECn80AAMJAAkJnBTWFAAkAgAJAAkJnBTWFAAkAgAQAAEJ8AFtkwAWAAAAAA==.Dark:BAABLgAECn9GAAIfAAkJQyAtDwDNAgAfAAkJQyAtDwDNAgAAAA==.Darkphyre:BAABLgAECn8ZAAIKAAcJoA2mnQAxAQAKAAcJoA2mnQAxAQAAAA==.Darkstormn:BAAALgAECgUJCAAAAA==.Darthtree:BAAALgAECgMJAwAAAA==.Dawling:BAAALgAECggJCQAAAA==.',
De='Deadmandan:BAABLgAECn8vAAMfAAkJHSXCBQBgAwAfAAkJHSXCBQBgAwAeAAYJISSxBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn9OAAIhAAkJ3yRgAQBLAwAhAAkJ3yRgAQBLAwABLgAECgkJSAAUABAmAA==.Decius:BAABLgAECn8ZAAIiAAcJJghwEAATAQAiAAcJJghwEAATAQAAAA==.Dedsexxy:BAAALgADCgQJBAAAAA==.Deltairlines:BAACLgAFFH8SAAMFAAYJvhwyEwC6AQAFAAYJvhwyEwC6AQADAAQJQAXYHADAAAAuAAQKfxoAAgUACQnWHm4JALsCAAUACQnWHm4JALsCAAAA.Deltayaya:BAABLgAFFH8LAAMVAAUJ1gy3IwBFAQAVAAUJ1gy3IwBFAQASAAEJpQ9XTQBBAAABLgAFFAYJEgAFAL4cAA==.Demagorgin:BAABLgAECn85AAIKAAkJnhx0IAB9AgAKAAkJnhx0IAB9AgAAAA==.Demcheekz:BAAALgAECgIJAgAAAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAABLgAECn8UAAMjAAcJHwr3PwD/AAAjAAYJ6Aj3PwD/AAAJAAQJpQlMTgCaAAAAAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn84AAIKAAkJ/R4GFADDAgAKAAkJ/R4GFADDAgAAAA==.Desmus:BAABLgAECn81AAIdAAgJoRgBGgDwAQAdAAgJoRgBGgDwAQAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAFFAUJGAAfALcjAA==.Devilmaycry:BAAALgADCgEJAQAAAA==.Deáthreaver:BAABLgAECn8mAAIKAAkJpw3IZgCXAQAKAAkJpw3IZgCXAQAAAA==.',
Di='Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAABLgAECn8eAAILAAkJJhIAIgDqAQALAAkJJhIAIgDqAQAAAA==.Ditar:BAAALgAECgEJAgABLgAECgYJCgAGAAAAAA==.',
Dk='Dk:BAAALgADCgIJAgABLgAFFAMJCQARABkkAA==.',
Do='Domwarlock:BAABLgAFFH8JAAMfAAQJFQ12egDCAAAfAAMJagp2egDCAAAkAAEJExXLHQBRAAAAAA==.Doogang:BAAALgADCgEJAgAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.Doublehungus:BAAALgAECgkJAQAAAA==.',
Dr='Drackal:BAAALgAECgEJAQAAAA==.Dradin:BAAALgADCgMJAwAAAA==.Dragondznutz:BAAALgAECgYJDAABLgAECgkJNwAKAIslAA==.Dronin:BAABLgAECn8nAAMgAAkJrRg7DwBZAQAgAAcJZBY7DwBZAQARAAUJoBpBfAA7AQAAAA==.Drpatan:BAABLgAECn8rAAIlAAgJVAgwKwAVAQAlAAgJVAgwKwAVAQAAAA==.Druni:BAABLgAECn8aAAICAAcJPgj6JgDSAAACAAcJPgj6JgDSAAAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Ec='Echowalker:BAABLgAECn8ZAAIlAAgJnRjOFADaAQAlAAgJnRjOFADaAQAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
Eh='Ehdawg:BAAALgAECgEJAQAAAA==.',
Ei='Eisenthorne:BAAALgADCgEJAgAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elemann:BAAALgAECgQJBQAAAA==.Elguezo:BAABLgAECn8VAAIWAAYJUhyzIQCXAQAWAAYJUhyzIQCXAQAAAA==.Elysyn:BAAALgADCgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emmerick:BAAALgAECgMJBAAAAA==.Emokillaz:BAABLgAECn8WAAIlAAcJ2hitIwCgAQAlAAcJ2hitIwCgAQAAAA==.',
Ep='Epictaxes:BAAALgAECggJDgAAAA==.Epimetheuz:BAAALgADCgYJAwABLgAECgcJCwAGAAAAAA==.Epsi:BAAALgAECgYJBQABLgAECgcJFwAQAAkIAA==.Epsilón:BAABLgAECn8XAAIQAAcJCQjHRwDoAAAQAAcJCQjHRwDoAAAAAA==.',
Et='Eternalpeace:BAAALgAECgEJAgAAAA==.',
Ev='Evelana:BAAALgADCgQJBwAAAA==.',
Ex='Exaduss:BAABLgAECn8VAAMeAAgJUyH+CAAxAgAeAAgJUyH+CAAxAgAfAAQJHB4lfwA2AQAAAA==.',
Ez='Ezora:BAAALgAECgcJDAAAAA==.',
Fa='Famulimus:BAAALgAECgcJCgABLgAECgkJFQANAEsXAA==.Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAABLgAECn8uAAIRAAkJHRlXHQBsAgARAAkJHRlXHQBsAgAAAA==.Faylan:BAABLgAECn8VAAIRAAYJ/A36lAAKAQARAAYJ/A36lAAKAQAAAA==.',
Fe='Felshadow:BAAALgAECgEJAgAAAA==.Feronnia:BAAALgAECgMJAwAAAA==.',
Fi='Fibot:BAABLgAECn8/AAIXAAkJox3FBACXAgAXAAkJox3FBACXAgAAAA==.Fingon:BAAALgAECgcJEgAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJKQAPAKkUAA==.Florasol:BAAALgADCgIJAgAAAA==.',
Fo='Foxling:BAEALgAECgUJCwAAAA==.',
Fr='Fraeyah:BAAALgAECgcJBwAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAACLgAFFH8MAAIPAAQJKA2SYAAhAQAPAAQJKA2SYAAhAQAuAAQKfxYAAg8ACQkaF2ZUADsCAA8ACQkaF2ZUADsCAAAA.',
Fu='Fulgora:BAABLgAECn8UAAISAAgJMwQgVwDRAAASAAgJMwQgVwDRAAAAAA==.Fullmoon:BAAALgAECgcJCAABLgAECgcJDwAGAAAAAA==.Furicor:BAAALgAECgEJAQAAAA==.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAACLgAFFH8SAAIPAAQJDQugZQAWAQAPAAQJDQugZQAWAQAuAAQKf0MAAg8ACQnGGygnAHgCAA8ACQnGGygnAHgCAAAA.Gasaraki:BAAALgAECgEJAgAAAA==.Gastdhunter:BAAALgAECgEJAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgADCggJCgAAAA==.',
Gi='Gimtar:BAAALgAECgYJCgAAAA==.Ginjockey:BAAALgADCgUJBQABLgAECgcJFwAQAAkIAA==.Gipsydanger:BAACLgAFFH8LAAIjAAMJGRssKADyAAAjAAMJGRssKADyAAAuAAQKf0IAAiMACQnWHYYJANACACMACQnWHYYJANACAAAA.Girllygirl:BAAALgAECgcJDgAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Gladiatrix:BAAALgAECgQJCAAAAA==.Glaurang:BAAALgAECgQJDgAAAA==.Glofor:BAAALgAECgcJDwABLgAECgkJKQAPAKkUAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECggJGAAVAMcWAA==.Gnomeregrets:BAAALgAECgUJBQABLgAECgYJDQAGAAAAAA==.Gnomestone:BAABLgAFFH8GAAIfAAMJMgNrhwClAAAfAAMJMgNrhwClAAAAAA==.',
Go='Goldencorpse:BAAALgAECgYJBgAAAA==.Goldenspoon:BAAALgADCgEJAQABLgAFFAIJBwAYAGUiAA==.Gorlokk:BAEALgADCgMJAwABLgADCgYJBgAGAAAAAA==.',
Gr='Grakonys:BAABLgAECn88AAMFAAkJ6BP8GQD/AQAFAAkJ6BP8GQD/AQAEAAcJ4Qc7HQBFAQAAAA==.Granger:BAAALgAECgIJAgABLgAECgIJBAAGAAAAAA==.Greed:BAABLgAECn80AAIWAAkJHRvSDABvAgAWAAkJHRvSDABvAgAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAAALgAECgUJDQAAAA==.Grimmvelt:BAAALgAECgQJBAAAAA==.Grounch:BAAALgADCgcJDAAAAA==.Grunnck:BAAALgADCgkJOQAAAA==.',
Gu='Guayusa:BAAALgAFFAEJAQAAAA==.Gunned:BAAALgADCgEJAQAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQAGAAAAAA==.',
Ha='Hacheron:BAAALgADCgIJAgABLgAFFAUJDQAhAHoQAA==.Hallows:BAAALgAECgUJCQAAAA==.Harnix:BAABLgAECn8sAAIKAAgJ9g5fdwB1AQAKAAgJ9g5fdwB1AQAAAA==.Harron:BAAALgAECgUJBQAAAA==.Hawtbooty:BAABLgAECn8yAAIJAAkJDRyKFwAGAgAJAAkJDRyKFwAGAgAAAA==.Haziel:BAEALgADCgYJBgAAAA==.',
He='Heartsbane:BAAALgAECgEJAQAAAA==.Helixrage:BAABLgAECn8XAAIHAAkJ/QVdIwAKAQAHAAkJ/QVdIwAKAQAAAA==.Hellreines:BAABLgAECn8fAAIYAAcJkiLJBgAlAgAYAAcJkiLJBgAlAgAAAA==.Herpderplol:BAABLgAECn8cAAImAAkJDBFjDwCwAQAmAAkJDBFjDwCwAQAAAA==.',
Hi='Hildi:BAABLgAECn81AAMnAAgJ5AKheQCUAAAnAAgJ5AKheQCUAAAWAAEJyAEnjAAfAAAAAA==.Him:BAACLgAFFH8HAAITAAMJ0RiqLgDjAAATAAMJ0RiqLgDjAAAuAAQKfyoAAhMACQmcIwEFAAwDABMACQmcIwEFAAwDAAAA.',
Ho='Holy:BAACLgAFFH8JAAIjAAMJGhn2KQDlAAAjAAMJGhn2KQDlAAAuAAQKfz8AAyMACQk3IYsDAGIDACMACQk3IYsDAGIDAAkAAQmDHLdiAEgAAAAA.Holyscales:BAAALgAECgEJAQAAAA==.Hoots:BAAALgAECgQJBQAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgAECgEJAQAAAA==.Humânity:BAAALgADCgYJBgAAAA==.Hurcules:BAAALgAECgUJBQAAAA==.',
['Hø']='Høåx:BAAALgAECgYJBgABLgAECgQJBAAGAAAAAA==.',
['Hü']='Hümänïty:BAAALgAECgcJBQABLgAFFAYJEQAKADESAA==.',
Il='Illbloodarch:BAABLgAECn82AAIIAAkJAQ6cFwCVAQAIAAkJAQ6cFwCVAQAAAA==.Illidaris:BAAALgAECggJCQAAAA==.Illvicious:BAAALgAECgUJDgAAAA==.',
In='Incredibread:BAAALgAECggJEwAAAA==.Indub:BAAALgAECgcJCwAAAA==.',
Ir='Ironfistmogu:BAAALgADCgkJCQAAAA==.',
Is='Ishura:BAABLgAECn8sAAILAAgJYwpBOgBWAQALAAgJYwpBOgBWAQAAAA==.',
It='Itslevi:BAAALgAECgcJEgAAAA==.',
Iv='Ivvy:BAABLgAECn8WAAIdAAcJ1gfoRQDoAAAdAAcJ1gfoRQDoAAAAAA==.',
Iz='Izanami:BAABLgAECn8rAAIlAAgJbB/7CQB9AgAlAAgJbB/7CQB9AgAAAA==.',
Ja='Jadinkalage:BAAALgAECgQJBAAAAA==.Jaewreth:BAAALgAECgIJAgAAAA==.Janntro:BAABLgAECn8gAAMlAAkJvx0dDgA1AgAlAAkJmhodDgA1AgAUAAIJgyUXGADTAAABLgAECgkJIgAOAL8fAA==.Jantra:BAAALgAECgEJAgABLgAECgkJIgAOAL8fAA==.Jantro:BAABLgAECn8iAAIOAAkJvx8nBADPAgAOAAkJvx8nBADPAgAAAA==.Janttro:BAAALgAECgIJBAABLgAECgkJIgAOAL8fAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAACLgAFFH8LAAMVAAQJ0hB7OQDpAAAVAAQJ0hB7OQDpAAASAAQJswSNLgDKAAAuAAQKfykAAxUACQmyExM4AMMBABUACQmyExM4AMMBABIAAwnFCpRsAJEAAAAA.Jeleka:BAAALgAECgYJBgABLgAECgkJJAAVAAgeAA==.Jelmarr:BAAALgAECgcJEgAAAA==.Jemmâ:BAAALgAECggJEwAAAA==.Jerauld:BAABLgAECn80AAImAAgJLxJnEgCFAQAmAAgJLxJnEgCFAQAAAA==.Jezrra:BAAALgAECggJDwAAAA==.',
Jh='Jhuloot:BAAALgAECgEJAQAAAA==.',
Ji='Jiddles:BAAALgADCgMJAwABLgAECgkJJAAVAAgeAA==.',
Jo='Johnnyzyns:BAABLgAECn8yAAMZAAkJOB2HGwCbAgAZAAkJOB2HGwCbAgAhAAEJthjOVAA8AAAAAA==.Jokhasta:BAABLgAECn8ZAAIXAAgJvBY/CwAYAgAXAAgJvBY/CwAYAgAAAA==.Joshc:BAABLgAECn8yAAIOAAkJHg1eIAA6AQAOAAkJHg1eIAA6AQAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
Ju='Judgejudee:BAAALgADCgcJFgAAAA==.Judgédred:BAAALgAECgcJDAAAAA==.',
['Já']='Ják:BAABLgAECn8bAAQCAAgJzBMPGwA2AQACAAcJJhEPGwA2AQALAAMJvwtOeQBSAAAKAAEJpwPUrwEhAAAAAA==.',
Ka='Kaaris:BAABLgAECn8lAAIeAAkJ3A/gCACuAQAeAAkJ3A/gCACuAQAAAA==.Kaetora:BAAALgADCgkJEgAAAA==.Kaiarie:BAABLgAECn8jAAIkAAgJAwm8EQA6AQAkAAgJAwm8EQA6AQAAAA==.Kainraziel:BAABLgAECn8eAAIMAAkJDBXwOQDUAQAMAAkJDBXwOQDUAQAAAA==.Kairos:BAABLgAECn9HAAIPAAkJChK9RgABAgAPAAkJChK9RgABAgAAAA==.Kalasta:BAAALgADCgIJAgAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karem:BAAALgAECgEJAQAAAA==.Kargrim:BAAALgAECgEJAQAAAA==.Karkea:BAAALgAECgEJBAAAAA==.Kayper:BAAALgAECgcJAgAAAA==.Kayyos:BAAALgAECgkJCQAAAA==.',
Ke='Kebin:BAABLgAECn8xAAIHAAkJvhcTDgD/AQAHAAkJvhcTDgD/AQAAAA==.Kekkoken:BAAALgAECgEJAQAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.Kenkenif:BAAALgAECgYJDgAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgAAAA==.',
Ki='Kibil:BAAALgAECgUJBQABLgAECgkJIgAZAEIOAA==.Killmonger:BAAALgAECgYJCwAAAA==.Kimsambo:BAAALgAECgQJBAAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Kn='Knocksteady:BAAALgAECgMJAwAAAA==.',
Ko='Koga:BAAALgAECgQJBAAAAA==.Korax:BAAALgAECgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAABLgAECn8yAAIDAAkJTiNAAQCQAwADAAkJTiNAAQCQAwAAAA==.Korzillian:BAAALgAECgEJAQAAAA==.Kos:BAACLgAFFH8MAAIQAAQJxiX2CAC7AQAQAAQJxiX2CAC7AQAuAAQKfyUAAhAACQlFIrAEAAkDABAACQlFIrAEAAkDAAAA.',
Kr='Kreyali:BAAALgAECgIJAwAAAA==.Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgcJEwAAAA==.Kuntar:BAAALgAECgcJCwAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurkoh:BAAALgAECgIJBAAAAA==.Kurrent:BAABLgAECn8kAAIVAAkJCB6+EgCtAgAVAAkJCB6+EgCtAgAAAA==.',
['Kÿ']='Kÿtten:BAABLgAECn8kAAICAAkJwwpsGABNAQACAAkJwwpsGABNAQAAAA==.',
La='Lad:BAACLgAFFH8FAAIZAAQJcRJYYQArAQAZAAQJcRJYYQArAQAuAAQKfxgAAxkACQlyH5UQAOICABkACQlyH5UQAOICABgAAQkeCqMXADEAAAAA.Laiyth:BAABLgAECn8bAAIfAAkJfxKyOgDqAQAfAAkJfxKyOgDqAQAAAA==.Lanfearz:BAAALgADCgEJAQAAAA==.Larryfish:BAABLgAECn8kAAMZAAkJHyEeGwCdAgAZAAkJUCAeGwCdAgAYAAgJ4x25BABtAgAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgMJBgAAAA==.Lavos:BAABLgAECn8wAAIeAAkJ1A75CgCDAQAeAAkJ1A75CgCDAQAAAA==.',
Le='Levitikus:BAAALgAECgcJDAAAAA==.Levìtikus:BAAALgAECgEJAgAAAA==.',
Li='Lideysse:BAAALgADCgUJBgAAAA==.Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lisster:BAABLgAECn8zAAMRAAkJzyAFDwDQAgARAAkJzyAFDwDQAgAgAAEJkAG2mAAeAAAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8dAAMLAAkJNhuwIAAWAgALAAkJNhuwIAAWAgACAAEJBBULQQA5AAAAAA==.Lizcandor:BAAALgAECgQJEQAAAA==.',
Lo='Loafe:BAACLgAFFH8LAAIKAAQJNgskTQAHAQAKAAQJNgskTQAHAQAuAAQKfyoAAgoACAk6DyNlALYBAAoACAk6DyNlALYBAAAA.Lokni:BAAALgAECgYJEQAAAA==.Loriann:BAAALgAECgEJAQAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgAECggJDgAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgcJBwAAAA==.Luthais:BAABLgAECn8aAAICAAcJdQ7IIAADAQACAAcJdQ7IIAADAQAAAA==.Luxury:BAABLgAECn8+AAIHAAkJ7gNeJQD7AAAHAAkJ7gNeJQD7AAAAAA==.',
Ly='Lykanthropos:BAAALgAECgEJAQAAAA==.',
Ma='Mahroq:BAABLgAECn8mAAMJAAgJwhk2HgDtAQAJAAgJnxk2HgDtAQAjAAYJoQmLRQDjAAABLgAFFAEJAQAGAAAAAA==.Maingauche:BAAALgAECgQJBAABLgAECgkJNAAGAAAAAA==.Mako:BAACLgAFFH8UAAMDAAQJHRE6GQDtAAADAAQJHRE6GQDtAAAFAAIJcQF4WQBXAAAuAAQKfyUAAgMACAkKIU4EAOMCAAMACAkKIU4EAOMCAAAA.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8nAAMEAAgJDwziDQAlAQAEAAgJygjiDQAlAQAFAAcJtgq8NQAjAQAAAA==.Malfuridan:BAAALgAECgMJAgAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Mandas:BAAALgAECgIJAgAAAA==.Maples:BAABLgAECn8nAAMnAAkJXwpHPgBfAQAnAAkJXwpHPgBfAQAWAAMJ3gHotgAUAAAAAA==.Mariasha:BAABLgAECn8aAAIRAAYJNAzHjgAWAQARAAYJNAzHjgAWAQAAAA==.Marichika:BAAALgADCgcJEQAAAA==.Maryjaine:BAAALgAECgUJCQAAAA==.Mattdeamon:BAAALgADCgUJBwABLgAFFAQJEgAPAA0LAA==.Mazzikin:BAACLgAFFH8HAAIMAAMJvhujTgDzAAAMAAMJvhujTgDzAAAuAAQKfy8AAgwACQmYIPoJAPQCAAwACQmYIPoJAPQCAAAA.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Megaterium:BAABLgAECn86AAMJAAkJLxswDQCHAgAJAAkJLxswDQCHAgAQAAYJnQoTXACaAAAAAA==.Melkoor:BAAALgADCgcJCwAAAA==.Menethil:BAABLgAECn8iAAILAAgJoiMWDADEAgALAAgJoiMWDADEAgAAAA==.Metheuz:BAAALgAECgcJCwAAAA==.Mexican:BAABLgAECn8yAAIPAAkJPxMSSAD9AQAPAAkJPxMSSAD9AQAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgAECgMJCAAAAA==.Mishgrail:BAABLgAECn89AAIcAAkJyCDnBADvAgAcAAkJyCDnBADvAgAAAA==.Misosoup:BAAALgAECgUJBQABLgADCgEJAQAGAAAAAA==.Missmisery:BAABLgAECn8pAAIRAAkJAxGoNQD8AQARAAkJAxGoNQD8AQAAAA==.Mithdraug:BAABLgAECn8ZAAMdAAcJdhKCPQANAQAdAAYJTBGCPQANAQANAAQJdwYuuABIAAAAAA==.Mitzi:BAACLgAFFH8YAAMZAAcJ0RZjJwCtAQAZAAYJ0RZjJwCtAQAhAAEJAABpXAAAAAAuAAQKfyQAAhkACQlwI14aAN8CABkACQlwI14aAN8CAAAA.',
Mo='Modrem:BAAALgADCgkJGwAAAA==.Mokhan:BAAALgADCgkJCQAAAA==.Molsan:BAAALgAECgQJBAAAAA==.Monache:BAABLgAECn8ZAAITAAgJdAveNQBqAQATAAgJdAveNQBqAQAAAA==.Mongalf:BAAALgADCgQJBAAAAA==.Montrois:BAAALgAECgQJBAAAAA==.Moocheala:BAAALgAECgEJAQAAAA==.Moopally:BAAALgAECgQJCAAAAA==.',
My='Mythrilblade:BAAALgAECgYJBgAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Na='Naromir:BAAALgAECgcJDAAAAA==.',
Ne='Neletheus:BAABLgAECn8WAAIfAAcJihCcfQA5AQAfAAcJihCcfQA5AQAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAABLgAECn8bAAIZAAcJ1CCxOQATAgAZAAcJ1CCxOQATAgAAAA==.Nirvanik:BAAALgAECgQJBQAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECgkJPQAcAMggAA==.',
Nu='Nukusmaximus:BAABLgAECn8wAAIPAAgJggh+lQBJAQAPAAgJggh+lQBJAQAAAA==.',
Ny='Nyeneave:BAAALgAECgIJAgAAAA==.Nyiah:BAABLgAECn8oAAINAAkJdxjrFgCHAgANAAkJdxjrFgCHAgAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Of='Offset:BAAALgAECgEJAQAAAA==.',
Og='Ogdoadtl:BAAALgAECgQJCgAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.',
Ol='Oldbull:BAAALgAECgEJAgAAAA==.',
On='Onex:BAAALgAECgYJCgAAAA==.',
Or='Organicmeat:BAAALgAECggJCQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.Ori:BAAALgAECgQJCQAAAA==.',
Pa='Paleprincess:BAAALgADCgIJAgABLgAECgIJBAAGAAAAAA==.Palii:BAAALgAECgQJBQAAAA==.Partywizard:BAAALgAECgMJAwAAAA==.',
Pe='Persefini:BAACLgAFFH8FAAINAAMJKQK5UgBxAAANAAMJKQK5UgBxAAAuAAQKfxUAAg0ABwloC/NYACUBAA0ABwloC/NYACUBAAAA.Persephoneia:BAAALgADCgcJDQAAAA==.Petrokull:BAAALgAECgUJCwAAAA==.',
Ph='Phaeder:BAAALgADCgUJBQAAAA==.Pheeguh:BAAALgADCgkJEAAAAA==.Pheylan:BAAALgAECgcJEAAAAA==.Philidox:BAAALgAECgYJCgABLgAECggJGwACAMwTAA==.Phood:BAAALgADCgcJBwABLgAECgYJBwAGAAAAAA==.',
Pi='Piety:BAAALgAECgYJBgAAAA==.Pikxs:BAAALgAECgMJAgAAAA==.Pitchou:BAAALgAECgUJCAAAAA==.',
Pl='Plugugly:BAAALgAECgQJBgAAAA==.',
Po='Poenin:BAAALgAECgUJBQAAAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8fAAIRAAkJHQ0zUgChAQARAAkJHQ0zUgChAQAAAA==.Potatobear:BAACLgAFFH8JAAIRAAQJoySaEwClAQARAAQJoySaEwClAQAuAAQKfzUABBEACQm+JRsCAGsDABEACQm+JRsCAGsDACAABglfI/EZAFsCAAEACQlgGgQOAEUCAAAA.',
Pr='Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgAECgMJBAAAAA==.',
Qi='Qiursi:BAAALgAECgUJBQAAAA==.',
Qu='Quicktime:BAABLgAECn9FAAIMAAkJXxySEwCdAgAMAAkJXxySEwCdAgAAAA==.',
Ra='Rafael:BAAALgAECgYJBgABLgAFFAQJFAADAB0RAA==.Ragedh:BAABLgAECn8XAAIMAAkJ+BrFFwB+AgAMAAkJ+BrFFwB+AgAAAA==.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ragnoir:BAAALgAECggJEAAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAAALgADCgEJAQAAAA==.Rashish:BAAALgADCgIJAgAAAA==.Ravies:BAACLgAFFH8FAAIRAAMJSBQ3VADoAAARAAMJSBQ3VADoAAAuAAQKfx4AAhEACQkxHtEOANECABEACQkxHtEOANECAAAA.Rawdøg:BAAALgADCgEJAQAAAA==.Rayaz:BAAALgAECgUJCwABLgAECgkJFQANAEsXAA==.',
Re='Reeses:BAEALgAECgYJCwABLgADCgYJBgAGAAAAAA==.Refellos:BAAALgAECgEJAgAAAA==.Reinhearts:BAAALgAFFAEJAQAAAA==.Religgar:BAABLgAECn8wAAIZAAkJ7Bj5JgBgAgAZAAkJ7Bj5JgBgAgAAAA==.Reploidzero:BAAALgAECgUJAQAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAABLgAECn89AAIPAAkJWRWqOwAlAgAPAAkJWRWqOwAlAgAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Roglof:BAABLgAECn8pAAIPAAgJqRTYYQC2AQAPAAgJqRTYYQC2AQAAAA==.Rokkoks:BAAALgADCggJEAAAAA==.Rowlah:BAAALgAECgcJDgAAAA==.Roxyfoxy:BAAALgAECgcJDwAAAA==.Rozy:BAABLgAECn89AAMLAAkJGBtuEgB/AgALAAkJGBtuEgB/AgAKAAUJZxjcpQAkAQAAAA==.',
Ru='Ruffs:BAABLgAECn8XAAMMAAkJIR3sGQBwAgAMAAkJIR3sGQBwAgAUAAEJYhD/MAA0AAAAAA==.Ruiizu:BAABLgAECn8yAAIKAAkJJiS1CAAdAwAKAAkJJiS1CAAdAwAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn89AAIjAAkJexvbDQCGAgAjAAkJexvbDQCGAgAAAA==.',
Sa='Saberjaw:BAABLgAECn8XAAMBAAYJrBU3FACCAQABAAYJkRQ3FACCAQARAAIJvwtLBwFGAAAAAA==.Sairicck:BAABLgAECn8tAAIRAAkJcx5QGACKAgARAAkJcx5QGACKAgAAAA==.Samaal:BAAALgADCgUJBQABLgAECgkJIgAOAL8fAA==.Samial:BAAALgADCgYJDAABLgAECgkJIgAOAL8fAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgADCggJCgAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selenar:BAAALgAECgEJAQAAAA==.Selesé:BAAALgAECgEJAQABLgAECggJEwAGAAAAAA==.Selinora:BAAALgAECgkJDgAAAA==.Senaria:BAAALgAECgMJBQAAAA==.Serhalatath:BAAALgAECggJDAAAAA==.',
Sh='Shadowsbane:BAAALgAFFAEJAQAAAA==.Shaguar:BAABLgAECn8rAAMKAAkJ0CAJEQDVAgAKAAkJ0CAJEQDVAgALAAcJPhCGXAALAQAAAA==.Shamhawk:BAAALgAECgEJAgAAAA==.Shaolinsnake:BAACLgAFFH8FAAITAAMJ9hNOLgDkAAATAAMJ9hNOLgDkAAAuAAQKfxQAAhMABwlYHNAkAMoBABMABwlYHNAkAMoBAAAA.Shiftace:BAAALgAECgYJBwAAAA==.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.Shizzite:BAAALgADCgIJAgAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAACLgAFFH8RAAIPAAQJPgfsaQAKAQAPAAQJPgfsaQAKAQAuAAQKfyQAAg8ACAmWElxpAAMCAA8ACAmWElxpAAMCAAAA.Sinzala:BAABLgAECn8iAAIPAAkJVR+rGwCuAgAPAAkJVR+rGwCuAgAAAA==.',
Sk='Skeetsurfin:BAAALgAECgMJAwAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwABLgAECgkJKwAKANAgAA==.',
Sm='Smallblackdk:BAAALgAFFAIJAwAAAA==.Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.Snowbunnyy:BAAALgAECgEJAQABLgAECgIJBAAGAAAAAA==.',
So='Solai:BAAALgAECgEJAQAAAA==.Solsti:BAACLgAFFH8FAAILAAUJYwXEHwAXAQALAAUJYwXEHwAXAQAuAAQKfzsAAgsACQnrGHQUAGICAAsACQnrGHQUAGICAAAA.',
Sp='Spears:BAABLgAECn8ZAAIRAAYJrAYSpADtAAARAAYJrAYSpADtAAAAAA==.Spoonbrew:BAAALgAECgYJBgABLgAFFAIJBwAYAGUiAA==.Spoondot:BAABLgAECn8lAAMkAAgJ7yVaAwB4AgAfAAgJbSNpFQCfAgAkAAcJhiRaAwB4AgABLgAFFAIJBwAYAGUiAA==.Spoonknight:BAACLgAFFH8HAAMYAAIJZSKtGACbAAAZAAIJIh7erwCtAAAYAAIJxBStGACbAAAuAAQKfxoAAxgACQl/IL8EAG0CABkACAnEHS8kAG4CABgACAmXH78EAG0CAAAA.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Staceyrella:BAAALgAECgEJAwAAAA==.Stainpngolin:BAABLgAECn8gAAIOAAgJsh0WCQBMAgAOAAgJsh0WCQBMAgAAAA==.Stillhorn:BAABLgAECn8mAAMlAAkJtBmvDgAtAgAMAAkJpRc8JAA0AgAlAAgJGRuvDgAtAgAAAA==.Stinjeras:BAABLgAECn8yAAIfAAkJoSFZDADmAgAfAAkJoSFZDADmAgAAAA==.Stinkyjo:BAABLgAECn8yAAINAAkJbxr3EQC2AgANAAkJbxr3EQC2AgAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAACLgAFFH8JAAIRAAQJbQsHYQDLAAARAAQJbQsHYQDLAAAuAAQKfyIAAhEACQmGHt8dAGkCABEACQmGHt8dAGkCAAAA.',
Su='Suian:BAAALgADCgEJAQAAAA==.Sunadoria:BAAALgAECgUJEwAAAA==.Sunlite:BAAALgAECgEJAwAAAA==.Sunrae:BAABLgAECn8xAAQjAAgJMRoGEwA/AgAjAAgJZxgGEwA/AgAQAAYJZwleRwDpAAAJAAMJShQXXQC+AAAAAA==.Sushi:BAABLgAECn8fAAIcAAkJlRMrGADfAQAcAAkJlRMrGADfAQAAAA==.',
Sv='Sven:BAAALgAECgUJCQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAAALgAECgUJDgAAAA==.',
['Sö']='Söap:BAAALgAECgYJCAAAAA==.',
Ta='Taggert:BAAALgAECgEJAQAAAA==.Tahl:BAABLgAECn8wAAIJAAcJRhL2KABzAQAJAAcJRhL2KABzAQAAAA==.Talox:BAAALgAECgEJAQAAAA==.Tamanovitch:BAAALgAECgEJAQAAAA==.Tamashii:BAAALgAFFAIJBAABLgAFFAQJFAADAB0RAA==.Tangriah:BAAALgADCgEJAQAAAA==.Taproot:BAAALgADCgEJAQABLgAFFAQJEgAPAA0LAA==.Taryen:BAAALgAECgUJCgABLgAECgkJFwAMAPgaAA==.Tavie:BAABLgAFFH8QAAIPAAQJ8xc2VAA2AQAPAAQJ8xc2VAA2AQAAAA==.',
Te='Teddy:BAAALgADCgYJBgAAAA==.Tedo:BAAALgADCgcJDgABLgAFFAUJGAALABkfAA==.Teikkas:BAAALgAECgYJCwAAAA==.Telaari:BAAALgAECgQJBgAAAA==.',
Th='Thalenia:BAACLgAFFH8OAAIRAAQJFQSmTwD0AAARAAQJFQSmTwD0AAAuAAQKfykAAyAACAm3CYQaAM8AABEABwnQCixhAEQBACAACAlhBoQaAM8AAAAA.Thallenia:BAAALgADCgEJAQAAAA==.Thalron:BAAALgADCgEJAgAAAA==.Thayne:BAAALgADCgYJBwAAAA==.Thekingdom:BAABLgAECn8eAAIPAAgJVh1fRQBnAgAPAAgJVh1fRQBnAgAAAA==.Thom:BAAALgADCgYJBwAAAA==.Thriller:BAAALgAECgUJCwABLgAFFAUJGAALABkfAA==.',
Ti='Tikeidari:BAABLgAECn9IAAIUAAkJECY+AABsAwAUAAkJECY+AABsAwAAAA==.Tiltedtroll:BAABLgAECn8rAAISAAkJnhLVJQCuAQASAAkJnhLVJQCuAQAAAA==.Timedemon:BAABLgAECn8mAAIMAAkJcRuhJwAjAgAMAAkJcRuhJwAjAgAAAA==.Tinuveuil:BAAALgADCgYJBgAAAA==.',
To='Toiletseat:BAAALgAECgUJBQAAAA==.Tonjuras:BAABLgAECn8pAAMoAAkJqSFWBQDWAgAoAAkJAR5WBQDWAgAiAAgJJB7gAwBcAgAAAA==.Toona:BAACLgAFFH8FAAIMAAIJ5AlmgQBvAAAMAAIJ5AlmgQBvAAAuAAQKfxwAAgwACQn7GgYcAKoCAAwACQn7GgYcAKoCAAEuAAUUBAkFABkAcRIA.Torogrande:BAAALgADCgkJKgAAAA==.Touchmyting:BAAALgAECgEJAwAAAA==.Toutii:BAAALgAECgUJBgABLgAECggJFAAaAI4fAA==.',
Tr='Trappybear:BAAALgAFFAEJAQABLgAFFAUJDQAhAHoQAA==.Trappydh:BAABLgAFFH8IAAIUAAQJbRAMBwDXAAAUAAQJbRAMBwDXAAABLgAFFAUJDQAhAHoQAA==.Trappydk:BAACLgAFFH8NAAIhAAUJehAAHgDmAAAhAAUJehAAHgDmAAAuAAQKfxcAAiEACAnPGowTAM0BACEACAnPGowTAM0BAAAA.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8sAAMfAAgJsSStCwAdAwAfAAgJsSStCwAdAwAkAAEJAADgIQBqAAAAAA==.',
Ty='Tyraxus:BAAALgADCgkJEAAAAA==.Tyronne:BAAALgAECgcJBwAAAA==.',
['Tý']='Týr:BAAALgADCgYJDAAAAA==.',
Ul='Ultraball:BAAALgAECggJDwAAAA==.',
Un='Unagi:BAABLgAECn8sAAIBAAkJfg5aFgDtAQABAAkJfg5aFgDtAQAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAABLgAECn8YAAIPAAgJOAi5lwBFAQAPAAgJOAi5lwBFAQAAAA==.Vaesir:BAAALgADCgcJDQAAAA==.Varleara:BAABLgAECn8gAAMMAAgJziFEEwDmAgAMAAgJziFEEwDmAgAUAAEJKQeHLQAqAAAAAA==.',
Ve='Venenn:BAAALgADCgEJAgAAAA==.Venev:BAAALgAECgYJDwAAAA==.Ventana:BAABLgAECn87AAIXAAgJWSK6AwC6AgAXAAgJWSK6AwC6AgAAAA==.Verdilac:BAABLgAECn81AAIKAAkJexw2PwD/AQAKAAkJexw2PwD/AQABLgAFFAQJEQAmAIUgAA==.',
Vi='Vinceglortho:BAAALgAECgUJCgAAAA==.Vindicator:BAABLgAECn8fAAIKAAkJSB01HgCHAgAKAAkJSB01HgCHAgAAAA==.Violetnoir:BAAALgAECgQJBAABLgAECgcJGgAfANsIAA==.Visiroth:BAABLgAECn8iAAMZAAkJQg7MYACgAQAZAAkJJAvMYACgAQAhAAgJ5QpZIwAtAQAAAA==.',
Vy='Vyyral:BAAALgAECgIJAgABLgAECgkJIgAOAL8fAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAFFAQJEQAPAD4HAA==.Wallydk:BAABLgAECn8xAAIZAAkJTBvuGgCeAgAZAAkJTBvuGgCeAgAAAA==.Wanji:BAABLgAECn8rAAIZAAkJCwuoYACgAQAZAAkJCwuoYACgAQAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Wenesday:BAAALgADCgcJEgAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Widginatrix:BAABLgAECn8ZAAIdAAgJwA2+LwBTAQAdAAgJwA2+LwBTAQAAAA==.Willkain:BAAALgAECgMJAwAAAA==.',
Wo='Woah:BAAALgAECgMJAwABLgAFFAIJBwAYAGUiAA==.Woons:BAAALgAECgMJCAAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Xa='Xaya:BAABLgAECn8aAAMfAAcJ2wgzmQAGAQAfAAcJ2wgzmQAGAQAeAAQJ6AJJUQB6AAAAAA==.',
Xe='Xenophorge:BAAALgAECggJCAAAAA==.Xeralvezyn:BAAALgADCgkJCQAAAA==.',
Xi='Xiva:BAABLgAECn8zAAIoAAgJ7BITGwCyAQAoAAgJ7BITGwCyAQAAAA==.',
Xo='Xovace:BAABLgAECn8WAAMlAAcJFwvCLQAEAQAlAAcJFwvCLQAEAQAMAAEJHwNeKgEcAAAAAA==.',
Xt='Xtayse:BAABLgAECn8pAAIEAAkJuCAbAQD9AgAEAAkJuCAbAQD9AgAAAA==.Xtaysì:BAAALgAECgEJAQAAAA==.',
Ya='Yagorbomb:BAAALgAECgEJAwAAAA==.Yamyam:BAABLgAECn8VAAIdAAkJsg/HKQCyAQAdAAkJsg/HKQCyAQAAAA==.',
Yi='Yirya:BAAALgAECgQJBgAAAA==.',
Yo='Yoruechi:BAACLgAFFH8RAAIOAAQJdSCqBgB6AQAOAAQJdSCqBgB6AQAuAAQKfysAAg4ACAkoI+sEALcCAA4ACAkoI+sEALcCAAAA.',
Yu='Yuridia:BAAALgADCgEJAQAAAA==.',
['Yú']='Yúmyúm:BAABLgAECn8lAAIKAAkJWBcRRQDtAQAKAAkJWBcRRQDtAQAAAA==.',
Za='Zahel:BAABLgAECn8uAAIKAAkJlB7BFgCxAgAKAAkJlB7BFgCxAgAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECgkJLgAKAJQeAA==.Zalark:BAAALgADCgUJCgABLgAECgkJNAAJAJwUAA==.Zangai:BAAALgAECggJCAABLgAECggJGQATAHQLAA==.Zavier:BAAALgAECgQJBAABLgAECgYJBwAGAAAAAA==.',
Ze='Zeneri:BAABLgAECn84AAMnAAkJhRDcKADPAQAnAAkJhRDcKADPAQAWAAkJyRCDGwDIAQAAAA==.',
Zo='Zobi:BAAALgAECgUJDwAAAA==.Zodius:BAAALgADCgEJAQAAAA==.Zomboo:BAAALgAFFAEJAQAAAA==.',
Zu='Zugzugzug:BAAALgADCgMJBgAAAA==.Zuhali:BAAALgADCgQJBAAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAFFAQJCwAVANIQAA==.',
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
