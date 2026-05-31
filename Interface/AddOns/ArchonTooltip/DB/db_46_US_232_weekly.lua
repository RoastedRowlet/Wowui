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

local lookup = {'Hunter-Survival','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Warrior-Protection','Warrior-Arms','Priest-Holy','Paladin-Retribution','Paladin-Holy','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Mage-Frost','Priest-Shadow','Hunter-BeastMastery','Shaman-Elemental','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','Monk-Brewmaster','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','Mage-Arcane','DeathKnight-Blood','Rogue-Assassination','Priest-Discipline','Warlock-Affliction','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-05-31',data={Ac='Acelara:BAAALgADCgUJBQAAAA==.',
Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ah='Ahmet:BAABLgAECn8VAAIBAAkJZhMHEwAEAgABAAkJZhMHEwAEAgABLgAECgkJQQACAI0dAA==.',
Ai='Aiax:BAACLgAFFH8IAAIDAAMJRAL4HwCPAAADAAMJRAL4HwCPAAAuAAQKfxcABAQACAlODDQgACwBAAUABgmnDb0xADoBAAQABglkCjQgACwBAAMAAglJB0VGAEAAAAAA.',
Al='Alderok:BAAALgAECgIJAwABLgAECgMJAwAGAAAAAA==.Aliancia:BAABLgAECn83AAMHAAgJSRWmFACRAQAHAAgJSRWmFACRAQAIAAMJ3AalXQBNAAAAAA==.Almur:BAAALgAECgcJDAAAAA==.Alyda:BAAALgADCggJFAAAAA==.Alydin:BAAALgADCgUJBQAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amet:BAABLgAECn9BAAICAAkJjR2MBACfAgACAAkJjR2MBACfAgAAAA==.',
An='Anakinn:BAAALgAECgUJBQAAAA==.Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8wAAIJAAkJBxtgEQBCAgAJAAkJBxtgEQBCAgAAAA==.Antherina:BAAALgADCgQJBwAAAA==.Antonious:BAAALgADCgMJAwAAAA==.Antonlavay:BAAALgAECgQJBAAAAA==.',
Ap='Aphyra:BAAALgADCgUJBQAAAA==.Apollyon:BAACLgAFFH8JAAIKAAQJ/CA6HABzAQAKAAQJ/CA6HABzAQAuAAQKfycAAwoACQnEIQAPANkCAAoACQnEIQAPANkCAAsAAgkqFax+AH8AAAAA.',
Ar='Arlechino:BAACLgAFFH8MAAIMAAQJ1gpjRgD9AAAMAAQJ1gpjRgD9AAAuAAQKfxwAAgwACAkXF1lAAPMBAAwACAkXF1lAAPMBAAAA.Arywyn:BAABLgAECn8aAAINAAcJNwt2YQABAQANAAcJNwt2YQABAQAAAA==.',
As='Assclapiuss:BAABLgAECn83AAMKAAkJiyUGBABNAwAKAAkJiyUGBABNAwALAAEJTwdhjAApAAAAAA==.Asterchades:BAABLgAECn9LAAIOAAkJcR7cBACsAgAOAAkJcR7cBACsAgAAAA==.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgkJEAAAAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn9IAAIPAAkJ+gMBmgAsAQAPAAkJ+gMBmgAsAQAAAA==.Atuan:BAABLgAECn8ZAAIQAAcJfxIqLABWAQAQAAcJfxIqLABWAQAAAA==.',
Au='Auralass:BAABLgAECn8bAAIRAAgJXRa0PQDVAQARAAgJXRa0PQDVAQAAAA==.Aurene:BAAALgAECgkJNAAAAQ==.Autym:BAAALgADCgkJCQAAAA==.',
Av='Avaric:BAAALgAECgEJAQABLgAECggJFAASADMEAA==.Avatard:BAAALgAECgIJAgABLgAFFAQJDQAPAKUEAA==.Avilla:BAAALgAECgEJAQAAAA==.',
Ax='Axem:BAABLgAECn8uAAITAAkJmB2hCwCbAgATAAkJmB2hCwCbAgAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azulathan:BAABLgAECn8bAAMUAAgJ3BYFCQDIAQAUAAgJ3BYFCQDIAQAMAAcJwwq9jgAEAQABLgAECggJNAAVAP4TAA==.',
Ba='Bamseyn:BAAALgADCgYJCwAAAA==.Bamsheyn:BAAALgADCgkJCQAAAA==.Baraxor:BAABLgAECn80AAMVAAgJ/hMUPQCgAQAVAAgJ/hMUPQCgAQASAAgJrw+OOAA8AQAAAA==.Barrelaged:BAAALgAECgMJBgAAAA==.',
Be='Beerguy:BAABLgAECn8WAAIWAAcJvQ2BMwAiAQAWAAcJvQ2BMwAiAQAAAA==.Behemothe:BAABLgAECn9DAAIXAAkJ2iEAAgD6AgAXAAkJ2iEAAgD6AgAAAA==.Berníesandrs:BAABLgAECn8tAAIPAAkJpA5JZACeAQAPAAkJpA5JZACeAQAAAA==.Beryllos:BAAALgAECgMJCwAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECggJDgAAAA==.Bigdamage:BAAALgAECgIJAgABLgAFFAIJBwAYAGUiAA==.Bigdmg:BAABLgAFFH8FAAIZAAIJVRd3rgCWAAAZAAIJVRd3rgCWAAAAAA==.Biggusdiscus:BAAALgAECgMJAwAAAA==.Bigimpin:BAAALgADCgcJBwAAAA==.Bisky:BAAALgAECgcJBwABLgAECgkJHwAaANYaAA==.',
Bj='Bjôrn:BAAALgAECgcJDQAAAA==.',
Bl='Bledana:BAAALgAECgcJDAAAAA==.Bleué:BAAALgADCgEJAQABLgAECgkJMwANAPEaAA==.Bloodmourne:BAABLgAECn8yAAIZAAkJmSVhBABTAwAZAAkJmSVhBABTAwAAAA==.Bloodytoutii:BAAALgAECgcJEgAAAA==.',
Bo='Borthyr:BAABLgAECn8tAAMFAAkJvx/dBwDFAgAFAAkJoR7dBwDFAgAEAAYJ0RyqDgDwAQAAAA==.Bortman:BAAALgAECgUJCAABLgAECgkJLQAFAL8fAA==.Bowowner:BAABLgAECn8hAAIRAAgJxh7oNgDtAQARAAgJxh7oNgDtAQAAAA==.',
Br='Branchmanagr:BAABLgAECn8iAAIOAAkJ6RGaEQCzAQAOAAkJ6RGaEQCzAQAAAA==.Breddamon:BAAALgADCgIJAgAAAA==.Brewlee:BAAALgAECgkJEgAAAA==.Bricter:BAAALgADCgkJCQABLgAECgkJPQAPAFkVAA==.Brokenkrayon:BAAALgAECgQJBgAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Bullséye:BAAALgAECgEJAQAAAA==.Busta:BAABLgAECn8fAAIPAAkJZwW7qQASAQAPAAkJZwW7qQASAQAAAA==.',
Bw='Bwicked:BAABLgAECn8lAAIPAAkJ/hdhLgBKAgAPAAkJ/hdhLgBKAgAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgcJDwAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Calzone:BAAALgAECgcJDQAAAA==.Cantpurge:BAAALgAECgMJAwABLgAECgcJFwAQAAkIAA==.Carebears:BAAALgAECgQJBQAAAA==.',
Ce='Celliss:BAAALgAECgEJAQAAAA==.Celonge:BAAALgAECgUJBQABLgAFFAUJBQALAGMFAA==.',
Ch='Chamelean:BAAALgAECgYJDQABLgAECgkJHgAMAAwVAA==.Charmcaster:BAAALgAECgEJAQAAAA==.Chimpnzthat:BAABLgAECn8tAAIbAAgJQxMiIQCPAQAbAAgJQxMiIQCPAQAAAA==.Chookicookie:BAABLgAECn9HAAMSAAkJ9h7qCAC9AgASAAkJ9h7qCAC9AgAVAAkJ1SACEgCnAgAAAA==.Chrome:BAABLgAECn9LAAMcAAkJviNZAgBHAwAcAAkJviNZAgBHAwANAAgJyB1+HgBLAgAAAA==.Chuckarita:BAABLgAECn8gAAIcAAkJnQorLgBQAQAcAAkJnQorLgBQAQAAAA==.',
Ci='Cindyy:BAABLgAECn8iAAIWAAgJiyE4CgCMAgAWAAgJiyE4CgCMAgABLgAFFAQJBwARAPMZAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgIJAgAAAA==.',
Co='Coedwig:BAAALgADCgYJBwAAAA==.Consfiracy:BAAALgAFFAEJAQAAAA==.Coresh:BAAALgAECggJDAAAAA==.Cornpuff:BAABLgAECn8YAAMdAAcJECXxCAChAQAdAAUJ+CTxCAChAQAeAAMJpCTGegA6AQAAAA==.Cortiz:BAABLgAECn9CAAIRAAkJaRIIOADoAQARAAkJaRIIOADoAQAAAA==.',
Cr='Crankdog:BAABLgAECn8rAAMRAAkJ1iQsBABBAwARAAkJ1iQsBABBAwAfAAYJ8g9oSgApAQAAAA==.Creedd:BAABLgAECn8vAAINAAgJGiCbEgCnAgANAAgJGiCbEgCnAgABLgAECgkJFQAVAJ4cAA==.Crialta:BAAALgADCgcJFAAAAA==.',
Cu='Cupsandcakes:BAABLgAECn8dAAIgAAgJ7wlfBgBDAQAgAAgJ7wlfBgBDAQAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Damessiah:BAABLgAECn8xAAMJAAgJ7hWzGQDoAQAJAAgJ7hWzGQDoAQAQAAEJ8AEHigAYAAAAAA==.Dark:BAABLgAECn9GAAIeAAkJQyDRDQDTAgAeAAkJQyDRDQDTAgAAAA==.Darkphyre:BAABLgAECn8ZAAIKAAcJoA1ImQAoAQAKAAcJoA1ImQAoAQAAAA==.Darkstormn:BAAALgAECgQJBwAAAA==.Darthtree:BAAALgAECgMJAwAAAA==.Dawling:BAAALgAECggJCQAAAA==.',
De='Deadmandan:BAABLgAECn8vAAMeAAkJHSXCBQBgAwAeAAkJHSXCBQBgAwAdAAYJISSxBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn9FAAIhAAkJ3yQsAQBOAwAhAAkJ3yQsAQBOAwABLgAECgkJSAAUABAmAA==.Decius:BAABLgAECn8ZAAIiAAcJJgijDwAYAQAiAAcJJgijDwAYAQAAAA==.Dedsexxy:BAAALgADCgQJBAAAAA==.Deltairlines:BAACLgAFFH8OAAMFAAYJsRoTEgCjAQAFAAYJsRoTEgCjAQADAAMJ9gOTHwCWAAAuAAQKfxkAAgUACQnWHsMIALYCAAUACQnWHsMIALYCAAAA.Deltayaya:BAABLgAFFH8JAAIVAAUJBgcjKQAeAQAVAAUJBgcjKQAeAQABLgAFFAYJDgAFALEaAA==.Demagorgin:BAABLgAECn85AAIKAAkJnhxsHQB+AgAKAAkJnhxsHQB+AgAAAA==.Demcheekz:BAAALgAECgIJAgAAAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAABLgAECn8UAAMjAAcJHwpqPQDxAAAjAAYJ6AhqPQDxAAAJAAQJpQkxSgCkAAAAAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn84AAIKAAkJ/R7tEQDEAgAKAAkJ/R7tEQDEAgAAAA==.Desmus:BAABLgAECn8tAAIcAAgJoRiEGADyAQAcAAgJoRiEGADyAQAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAFFAUJFAAeAO0gAA==.Devilmaycry:BAAALgADCgEJAQAAAA==.Deáthreaver:BAABLgAECn8mAAIKAAkJpw3sZACNAQAKAAkJpw3sZACNAQAAAA==.',
Di='Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAABLgAECn8eAAILAAkJJhIbIADtAQALAAkJJhIbIADtAQAAAA==.Ditar:BAAALgAECgEJAgABLgAECgYJCgAGAAAAAA==.',
Dk='Dk:BAAALgADCgIJAgABLgAFFAMJCQARABkkAA==.',
Do='Domwarlock:BAABLgAFFH8JAAMeAAQJFQ0ocgDDAAAeAAMJagoocgDDAAAkAAEJExWtGQBRAAAAAA==.Doogang:BAAALgADCgEJAQAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.',
Dr='Drackal:BAAALgAECgEJAQAAAA==.Dradin:BAAALgADCgMJAwAAAA==.Dragondznutz:BAAALgAECgYJDAABLgAECgkJNwAKAIslAA==.Dronin:BAABLgAECn8lAAMfAAgJCRgsDgBjAQAfAAcJZBYsDgBjAQARAAQJ0xWcqgDRAAAAAA==.Drpatan:BAABLgAECn8lAAIaAAcJpwj8LQDzAAAaAAcJpwj8LQDzAAAAAA==.Druni:BAABLgAECn8aAAICAAcJPgi9JADVAAACAAcJPgi9JADVAAAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Ec='Echowalker:BAABLgAECn8ZAAIaAAgJnRhHEwDeAQAaAAgJnRhHEwDeAQAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
Eh='Ehdawg:BAAALgAECgEJAQAAAA==.',
Ei='Eisenthorne:BAAALgADCgEJAgAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elemann:BAAALgAECgQJBAAAAA==.Elguezo:BAABLgAECn8UAAIWAAYJUhznHwCbAQAWAAYJUhznHwCbAQAAAA==.Elysyn:BAAALgADCgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emmerick:BAAALgAECgMJAwAAAA==.Emokillaz:BAABLgAECn8WAAIaAAcJ2hitIwCgAQAaAAcJ2hitIwCgAQAAAA==.',
Ep='Epictaxes:BAAALgAECgYJBgAAAA==.Epimetheuz:BAAALgADCgYJAwABLgAECgcJCgAGAAAAAA==.Epsi:BAAALgAECgYJBQABLgAECgcJFwAQAAkIAA==.Epsilón:BAABLgAECn8XAAIQAAcJCQiiRgDQAAAQAAcJCQiiRgDQAAAAAA==.',
Et='Eternalpeace:BAAALgAECgEJAgAAAA==.',
Ev='Evelana:BAAALgADCgQJBwAAAA==.',
Ex='Exaduss:BAABLgAECn8VAAMdAAgJUyH+CAAxAgAdAAgJUyH+CAAxAgAeAAQJHB7UewA4AQAAAA==.',
Ez='Ezora:BAAALgAECgcJDAAAAA==.',
Fa='Famulimus:BAAALgAECgcJCgABLgAECgkJFQANAEsXAA==.Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAABLgAECn8nAAIRAAkJVxhUHwBXAgARAAkJVxhUHwBXAgAAAA==.Faylan:BAABLgAECn8VAAIRAAYJ/A2pjAAPAQARAAYJ/A2pjAAPAQAAAA==.',
Fe='Felshadow:BAAALgAECgEJAQAAAA==.Feronnia:BAAALgAECgMJAwAAAA==.',
Fi='Fibot:BAABLgAECn8/AAIXAAkJox08BACdAgAXAAkJox08BACdAgAAAA==.Fingon:BAAALgAECgcJEgAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJIQAPAI8TAA==.Florasol:BAAALgADCgIJAgAAAA==.',
Fo='Foxling:BAEALgAECgQJBgAAAA==.',
Fr='Fraeyah:BAAALgAECgcJBwAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAACLgAFFH8MAAIPAAQJKA1AWAAiAQAPAAQJKA1AWAAiAQAuAAQKfxYAAg8ACQkaF2ZUADsCAA8ACQkaF2ZUADsCAAAA.',
Fu='Fulgora:BAABLgAECn8UAAISAAgJMwQZUgDWAAASAAgJMwQZUgDWAAAAAA==.Fullmoon:BAAALgAECgcJBwABLgAECgcJDwAGAAAAAA==.Furicor:BAAALgADCgEJAQAAAA==.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAACLgAFFH8SAAIPAAQJDQt9XQAXAQAPAAQJDQt9XQAXAQAuAAQKf0MAAg8ACQnGG3okAHYCAA8ACQnGG3okAHYCAAAA.Gasaraki:BAAALgAECgEJAgAAAA==.Gastdhunter:BAAALgAECgEJAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgADCggJCgAAAA==.',
Gi='Gimtar:BAAALgAECgYJCgAAAA==.Ginjockey:BAAALgADCgUJBQABLgAECgcJFwAQAAkIAA==.Gipsydanger:BAACLgAFFH8HAAIjAAIJzxiVMACbAAAjAAIJzxiVMACbAAAuAAQKf0AAAiMACQndHEsKALECACMACQndHEsKALECAAAA.Girllygirl:BAAALgAECgcJDgAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Gladiatrix:BAAALgAECgQJCAAAAA==.Glaurang:BAAALgAECgQJDQAAAA==.Glofor:BAAALgAECgcJDwABLgAECgkJIQAPAI8TAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECggJGAAVAMcWAA==.Gnomeregrets:BAAALgAECgUJBQABLgAECgYJDQAGAAAAAA==.Gnomestone:BAAALgAFFAMJAwAAAA==.',
Go='Goldencorpse:BAAALgAECgUJBQAAAA==.Goldenspoon:BAAALgADCgEJAQABLgAFFAIJBwAYAGUiAA==.Gorlokk:BAEALgADCgMJAwABLgAECgUJBQAGAAAAAA==.',
Gr='Grakonys:BAABLgAECn88AAMFAAkJ6BOBGAD8AQAFAAkJ6BOBGAD8AQAEAAcJ4Qc7HQBFAQAAAA==.Granger:BAAALgAECgIJAgABLgAECgIJBAAGAAAAAA==.Greed:BAABLgAECn80AAIWAAkJHRvQCwBzAgAWAAkJHRvQCwBzAgAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAAALgAECgQJDAAAAA==.Grimmvelt:BAAALgAECgQJBAAAAA==.Grounch:BAAALgADCgUJBQAAAA==.Grunnck:BAAALgADCgkJMAAAAA==.',
Gu='Guayusa:BAAALgAECggJEwAAAA==.Gunned:BAAALgADCgEJAQAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQAGAAAAAA==.',
Ha='Hacheron:BAAALgADCgIJAgABLgAFFAQJDAAhAHoQAA==.Hallows:BAAALgAECgUJCQAAAA==.Harnix:BAABLgAECn8kAAIKAAgJzwtYjAA+AQAKAAgJzwtYjAA+AQAAAA==.Harron:BAAALgAECgUJBQAAAA==.Hawtbooty:BAABLgAECn8yAAIJAAkJDRy3FQARAgAJAAkJDRy3FQARAgAAAA==.',
He='Heartsbane:BAAALgAECgEJAQAAAA==.Helixrage:BAABLgAECn8XAAIHAAkJ/QVYIQAQAQAHAAkJ/QVYIQAQAQAAAA==.Hellreines:BAABLgAECn8fAAIYAAcJkiIoBgAfAgAYAAcJkiIoBgAfAgAAAA==.Herpderplol:BAABLgAECn8cAAIlAAkJDBFHDgCxAQAlAAkJDBFHDgCxAQAAAA==.',
Hi='Hildi:BAABLgAECn8tAAMmAAgJnQLEcACRAAAmAAgJnQLEcACRAAAWAAEJyAEnjAAfAAAAAA==.Him:BAACLgAFFH8HAAITAAMJ0RgIKgDrAAATAAMJ0RgIKgDrAAAuAAQKfyoAAhMACQmcI1oEABEDABMACQmcI1oEABEDAAAA.',
Ho='Holy:BAACLgAFFH8HAAIjAAIJbxSLMQCSAAAjAAIJbxSLMQCSAAAuAAQKfzoAAyMACQk6IGwEADcDACMACQk6IGwEADcDAAkAAQmDHP9eAEoAAAAA.Holyscales:BAAALgAECgEJAQAAAA==.Hoots:BAAALgAECgQJBQAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgADCgcJGAAAAA==.Humânity:BAAALgADCgYJBgAAAA==.Hurcules:BAAALgAECgUJBQAAAA==.',
['Hø']='Høåx:BAAALgAECgMJAwABLgAECgQJBAAGAAAAAA==.',
['Hü']='Hümänïty:BAAALgAECgcJBQABLgAFFAYJEQAKADESAA==.',
Il='Illbloodarch:BAABLgAECn82AAIIAAkJAQ7iFQCXAQAIAAkJAQ7iFQCXAQAAAA==.Illidaris:BAAALgAECgcJBwAAAA==.Illvicious:BAAALgAECgQJDQAAAA==.',
In='Incredibread:BAAALgAECgcJEQAAAA==.Indub:BAAALgAECgcJCwAAAA==.',
Ir='Ironfistmogu:BAAALgADCgkJCQAAAA==.',
Is='Ishura:BAABLgAECn8kAAILAAgJTwo6OABWAQALAAgJTwo6OABWAQAAAA==.',
It='Itslevi:BAAALgAECgcJEgAAAA==.',
Iv='Ivvy:BAABLgAECn8WAAIcAAcJ1gd3QgDpAAAcAAcJ1gd3QgDpAAAAAA==.',
Iz='Izanami:BAABLgAECn8nAAIaAAgJzhvwDAA5AgAaAAgJzhvwDAA5AgAAAA==.',
Ja='Jadinkalage:BAAALgAECgQJBAAAAA==.Jaewreth:BAAALgAECgIJAgAAAA==.Janntro:BAABLgAECn8fAAMaAAkJ1hrFDAA7AgAaAAkJmhrFDAA7AgAUAAIJ4hjyHQCUAAAAAA==.Jantra:BAAALgAECgEJAgABLgAECgkJHwAaANYaAA==.Jantro:BAABLgAECn8cAAIOAAkJqh7+BACoAgAOAAkJqh7+BACoAgABLgAECgkJHwAaANYaAA==.Janttro:BAAALgAECgIJBAABLgAECgkJHwAaANYaAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAACLgAFFH8HAAMSAAQJswQDKgDPAAASAAQJswQDKgDPAAAVAAIJjRBVVgCAAAAuAAQKfygAAxUACQmyEwU1AMMBABUACQmyEwU1AMMBABIAAwnFCpRsAJEAAAAA.Jelmarr:BAAALgAECgcJEgAAAA==.Jemmâ:BAAALgAECggJEwAAAA==.Jerauld:BAABLgAECn8sAAIlAAgJ7xA7EgB2AQAlAAgJ7xA7EgB2AQAAAA==.Jezrra:BAAALgAECggJDwAAAA==.',
Jh='Jhuloot:BAAALgAECgEJAQAAAA==.',
Ji='Jiddles:BAAALgADCgMJAwABLgAECgkJIwAVAAgeAA==.',
Jo='Johnnyzyns:BAABLgAECn8yAAMZAAkJOB06GQCdAgAZAAkJOB06GQCdAgAhAAEJthiBUAA9AAAAAA==.Jokhasta:BAABLgAECn8ZAAIXAAgJvBY/CwAYAgAXAAgJvBY/CwAYAgAAAA==.Joshc:BAABLgAECn8yAAIOAAkJHg1WHQBBAQAOAAkJHg1WHQBBAQAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
Ju='Judgejudee:BAAALgADCgcJFgAAAA==.Judgédred:BAAALgAECgcJDAAAAA==.',
['Já']='Ják:BAABLgAECn8bAAQCAAgJzBMPGwA2AQACAAcJJhEPGwA2AQALAAMJvwtCdQBSAAAKAAEJpwOKmgEhAAAAAA==.',
Ka='Kaaris:BAABLgAECn8eAAIdAAkJAwwGDABjAQAdAAkJAwwGDABjAQAAAA==.Kaetora:BAAALgADCgkJEgAAAA==.Kaiarie:BAABLgAECn8iAAIkAAgJYghuEQAtAQAkAAgJYghuEQAtAQAAAA==.Kainraziel:BAABLgAECn8eAAIMAAkJDBXaNgDWAQAMAAkJDBXaNgDWAQAAAA==.Kairos:BAABLgAECn9HAAIPAAkJChJvQgD/AQAPAAkJChJvQgD/AQAAAA==.Kalasta:BAAALgADCgIJAgAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karem:BAAALgAECgEJAQAAAA==.Karkea:BAAALgAECgEJBAAAAA==.Kayper:BAAALgAECgcJAgAAAA==.Kayyos:BAAALgAECgkJCQAAAA==.',
Ke='Kebin:BAABLgAECn8xAAIHAAkJvhfSDAAJAgAHAAkJvhfSDAAJAgAAAA==.Kekkoken:BAAALgAECgEJAQAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.Kenkenif:BAAALgAECgUJCQAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgAAAA==.',
Ki='Killmonger:BAAALgAECgYJCwAAAA==.Kimsambo:BAAALgAECgQJBAAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Ko='Koga:BAAALgAECgEJAQAAAA==.Korax:BAAALgAECgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAABLgAECn8yAAIDAAkJTiMqAQCSAwADAAkJTiMqAQCSAwAAAA==.Korzillian:BAAALgAECgEJAQAAAA==.Kos:BAACLgAFFH8IAAIQAAQJsCRRCACuAQAQAAQJsCRRCACuAQAuAAQKfyQAAhAACQmxIWwFAOgCABAACQmxIWwFAOgCAAAA.',
Kr='Kreyali:BAAALgAECgIJAwAAAA==.Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgcJEwAAAA==.Kuntar:BAAALgAECgcJCwAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurkoh:BAAALgAECgIJBAAAAA==.Kurrent:BAABLgAECn8jAAIVAAkJCB4xEQCvAgAVAAkJCB4xEQCvAgAAAA==.',
['Kÿ']='Kÿtten:BAABLgAECn8kAAICAAkJwwrlFgBQAQACAAkJwwrlFgBQAQAAAA==.',
La='Lad:BAACLgAFFH8FAAIZAAQJcRKPVgAsAQAZAAQJcRKPVgAsAQAuAAQKfxgAAxkACQlyH+UOAOUCABkACQlyH+UOAOUCABgAAQkeCqMXADEAAAAA.Laiyth:BAABLgAECn8bAAIeAAkJfxIRNwDyAQAeAAkJfxIRNwDyAQAAAA==.Lanfearz:BAAALgADCgEJAQAAAA==.Larryfish:BAABLgAECn8iAAMZAAkJQx+OIAB1AgAZAAkJjB6OIAB1AgAYAAcJLx3zBgAHAgAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgMJBgAAAA==.Lavos:BAABLgAECn8wAAIdAAkJ1A45CgCGAQAdAAkJ1A45CgCGAQAAAA==.',
Le='Levitikus:BAAALgAECgIJBwAAAA==.Levìtikus:BAAALgAECgEJAgAAAA==.',
Li='Lideysse:BAAALgADCgUJBQAAAA==.Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lisster:BAABLgAECn8zAAMRAAkJzyAjDQDXAgARAAkJzyAjDQDXAgAfAAEJkAG2mAAeAAAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8dAAMLAAkJNhuwIAAWAgALAAkJNhuwIAAWAgACAAEJBBULQQA5AAAAAA==.Lizcandor:BAAALgAECgQJEQAAAA==.',
Lo='Loafe:BAACLgAFFH8HAAIKAAQJIgmTSAAEAQAKAAQJIgmTSAAEAQAuAAQKfykAAgoACAk6DyNlALYBAAoACAk6DyNlALYBAAAA.Lokni:BAAALgAECgYJEQAAAA==.Loriann:BAAALgAECgEJAQAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgAECggJDgAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgcJBwAAAA==.Luthais:BAABLgAECn8aAAICAAcJdQ7rHgAFAQACAAcJdQ7rHgAFAQAAAA==.Luxury:BAABLgAECn81AAIHAAkJxgPhIwD7AAAHAAkJxgPhIwD7AAAAAA==.',
Ly='Lykanthropos:BAAALgADCgcJBwAAAA==.',
Ma='Mahroq:BAABLgAECn8lAAMJAAgJwhk2HgDtAQAJAAgJnxk2HgDtAQAjAAUJgwdyTgCbAAAAAA==.Maingauche:BAAALgAECgQJBAAAAA==.Mako:BAACLgAFFH8QAAMDAAQJ8gxLGAD4AAADAAQJ8gxLGAD4AAAFAAIJcQFEUwBYAAAuAAQKfyQAAgMACAkKIRYEAOQCAAMACAkKIRYEAOQCAAAA.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8nAAMEAAgJDwwZDQArAQAEAAgJyggZDQArAQAFAAcJtgq8NQAjAQAAAA==.Malfuridan:BAAALgAECgMJAgAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Mandas:BAAALgAECgIJAgAAAA==.Maples:BAABLgAECn8nAAMmAAkJXworOQBfAQAmAAkJXworOQBfAQAWAAMJ3gHprAAVAAAAAA==.Mariasha:BAABLgAECn8UAAIRAAYJlAuJiwARAQARAAYJlAuJiwARAQAAAA==.Marichika:BAAALgADCgcJEQAAAA==.Maryjaine:BAAALgAECgQJCAAAAA==.Mattdeamon:BAAALgADCgUJBwABLgAFFAQJEgAPAA0LAA==.Mazzikin:BAACLgAFFH8HAAIMAAMJvhvtRgD7AAAMAAMJvhvtRgD7AAAuAAQKfy8AAgwACQmYIBIJAPQCAAwACQmYIBIJAPQCAAAA.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Megaterium:BAABLgAECn86AAMJAAkJLxsHDACQAgAJAAkJLxsHDACQAgAQAAYJnQpfUwCdAAAAAA==.Melkoor:BAAALgADCgEJAQAAAA==.Menethil:BAABLgAECn8iAAILAAgJoiMkCwDHAgALAAgJoiMkCwDHAgAAAA==.Metheuz:BAAALgAECgcJCgAAAA==.Mexican:BAABLgAECn8yAAIPAAkJPxPKQwD6AQAPAAkJPxPKQwD6AQAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgAECgMJCAAAAA==.Mishgrail:BAABLgAECn84AAIbAAkJyCCBBADxAgAbAAkJyCCBBADxAgAAAA==.Misosoup:BAAALgAECgUJBQABLgADCgEJAQAGAAAAAA==.Missmisery:BAABLgAECn8iAAIRAAkJ/A4MPADaAQARAAkJ/A4MPADaAQAAAA==.Mithdraug:BAABLgAECn8ZAAMcAAcJdhKOOgANAQAcAAYJTBGOOgANAQANAAQJdwbusgBJAAAAAA==.Mitzi:BAACLgAFFH8YAAMZAAcJ0RYVIQCpAQAZAAYJ0RYVIQCpAQAhAAEJAACAVAAAAAAuAAQKfyQAAhkACQlwI14aAN8CABkACQlwI14aAN8CAAAA.',
Mo='Modrem:BAAALgADCgkJGwAAAA==.Mokhan:BAAALgADCgkJCQAAAA==.Molsan:BAAALgAECgQJBAAAAA==.Monache:BAABLgAECn8ZAAITAAgJdAtWMwBqAQATAAgJdAtWMwBqAQAAAA==.Mongalf:BAAALgADCgQJBAAAAA==.Montrois:BAAALgAECgQJBAAAAA==.Moopally:BAAALgAECgQJCAAAAA==.',
My='Mythrilblade:BAAALgAECgYJBgAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Na='Naromir:BAAALgAECgUJBQAAAA==.',
Ne='Neletheus:BAABLgAECn8WAAIeAAcJihBGdgBDAQAeAAcJihBGdgBDAQAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAABLgAECn8bAAIZAAcJ1CAZNgAVAgAZAAcJ1CAZNgAVAgAAAA==.Nirvanik:BAAALgAECgQJBQAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECgkJOAAbAMggAA==.',
Nu='Nukusmaximus:BAABLgAECn8oAAIPAAgJNwjPkwA3AQAPAAgJNwjPkwA3AQAAAA==.',
Ny='Nyeneave:BAAALgAECgIJAgAAAA==.Nyiah:BAABLgAECn8mAAINAAkJdxjfFQCIAgANAAkJdxjfFQCIAgAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Og='Ogdoadtl:BAAALgAECgQJCgAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.',
Ol='Oldbull:BAAALgAECgEJAQAAAA==.',
On='Onex:BAAALgAECgYJCgAAAA==.',
Or='Organicmeat:BAAALgAECggJCQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.Ori:BAAALgAECgQJCQAAAA==.',
Pa='Paleprincess:BAAALgADCgIJAgABLgAECgIJBAAGAAAAAA==.Palii:BAAALgAECgQJBQAAAA==.Partywizard:BAAALgAECgMJAwAAAA==.',
Pe='Persefini:BAABLgAECn8VAAINAAcJaAtuVQApAQANAAcJaAtuVQApAQAAAA==.Persephoneia:BAAALgADCgcJDQAAAA==.Petrokull:BAAALgAECgQJCgAAAA==.',
Ph='Phaeder:BAAALgADCgUJBQAAAA==.Pheeguh:BAAALgADCgkJEAAAAA==.Pheylan:BAAALgAECgcJEAAAAA==.Philidox:BAAALgAECgYJCgABLgAECggJGwACAMwTAA==.Phood:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.',
Pi='Pikxs:BAAALgAECgMJAgAAAA==.Pitchou:BAAALgAECgUJCAAAAA==.',
Pl='Plugugly:BAAALgAECgQJBgAAAA==.',
Po='Poenin:BAAALgAECgEJAQAAAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8fAAIRAAkJHQ3STAClAQARAAkJHQ3STAClAQAAAA==.Potatobear:BAACLgAFFH8FAAIRAAQJTSKkEgCSAQARAAQJTSKkEgCSAQAuAAQKfzUABBEACQm+JbsBAHADABEACQm+JbsBAHADAB8ABglfI/EZAFsCAAEACQlgGgMNAEkCAAAA.',
Pr='Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgAECgMJBAAAAA==.',
Qi='Qiursi:BAAALgAECgUJBQAAAA==.',
Qu='Quicktime:BAABLgAECn9FAAIMAAkJXxwcEgCfAgAMAAkJXxwcEgCfAgAAAA==.',
Ra='Rafael:BAAALgAECgYJBgABLgAFFAQJEAADAPIMAA==.Ragedh:BAAALgAECgkJEgAAAA==.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ragnoir:BAAALgAECggJEAAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAAALgADCgEJAQAAAA==.Rashish:BAAALgADCgIJAgAAAA==.Ravies:BAABLgAECn8UAAIRAAgJdhprJQA3AgARAAgJdhprJQA3AgAAAA==.Rawdøg:BAAALgADCgEJAQAAAA==.Rayaz:BAAALgAECgUJCwABLgAECgkJFQANAEsXAA==.',
Re='Reeses:BAEALgAECgUJBQAAAA==.Reinhearts:BAAALgAFFAEJAQAAAA==.Religgar:BAABLgAECn8tAAIZAAgJjxoDNQAZAgAZAAgJjxoDNQAZAgAAAA==.Reploidzero:BAAALgAECgUJAQAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAABLgAECn89AAIPAAkJWRW6NwAjAgAPAAkJWRW6NwAjAgAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Roglof:BAABLgAECn8hAAIPAAgJjxPzYgChAQAPAAgJjxPzYgChAQAAAA==.Rokkoks:BAAALgADCggJEAAAAA==.Rowlah:BAAALgAECgcJBwAAAA==.Roxyfoxy:BAAALgAECgcJDwAAAA==.Rozy:BAABLgAECn84AAMLAAkJGBtuEgB/AgALAAkJGBtuEgB/AgAKAAUJ+xEXxwDiAAAAAA==.',
Ru='Ruffs:BAABLgAECn8XAAMMAAkJIR1tGABwAgAMAAkJIR1tGABwAgAUAAEJYhBdLgA1AAAAAA==.Ruiizu:BAABLgAECn8yAAIKAAkJJiRtBwAfAwAKAAkJJiRtBwAfAwAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn89AAIjAAkJexvBDACGAgAjAAkJexvBDACGAgAAAA==.',
Sa='Saberjaw:BAABLgAECn8XAAMBAAYJrBU3FACCAQABAAYJkRQ3FACCAQARAAIJvwu1+ABIAAAAAA==.Sairicck:BAABLgAECn8tAAIRAAkJcx7VFQCQAgARAAkJcx7VFQCQAgAAAA==.Samaal:BAAALgADCgUJBQABLgAECgkJHwAaANYaAA==.Samial:BAAALgADCgYJDAABLgAECgkJHwAaANYaAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgADCggJCgAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selenar:BAAALgAECgEJAQAAAA==.Selesé:BAAALgAECgEJAQABLgAECggJEwAGAAAAAA==.Selinora:BAAALgAECgkJDgAAAA==.Senaria:BAAALgAECgIJAwAAAA==.Serhalatath:BAAALgAECgcJCwAAAA==.',
Sh='Shadowsbane:BAAALgAECgQJBQABLgAECggJJQAJAMIZAA==.Shaguar:BAABLgAECn8rAAMKAAkJ0CAsDwDXAgAKAAkJ0CAsDwDXAgALAAcJPhCGXAALAQAAAA==.Shamhawk:BAAALgAECgEJAgAAAA==.Shaolinsnake:BAABLgAECn8UAAITAAcJWByQIgDMAQATAAcJWByQIgDMAQAAAA==.Shiftace:BAAALgAECgMJAwAAAA==.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.Shizzite:BAAALgADCgIJAgAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAACLgAFFH8NAAIPAAQJpQS8ZQD+AAAPAAQJpQS8ZQD+AAAuAAQKfyMAAg8ACAmWElxpAAMCAA8ACAmWElxpAAMCAAAA.Sinzala:BAABLgAECn8iAAIPAAkJVR+rGQCrAgAPAAkJVR+rGQCrAgAAAA==.',
Sk='Skeetsurfin:BAAALgAECgMJAwAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwABLgAECgkJKwAKANAgAA==.',
Sm='Smallblackdk:BAAALgAFFAIJAwAAAA==.Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.Snowbunnyy:BAAALgAECgEJAQABLgAECgIJBAAGAAAAAA==.',
So='Solai:BAAALgAECgEJAQAAAA==.Solsti:BAACLgAFFH8FAAILAAUJYwWSHAAlAQALAAUJYwWSHAAlAQAuAAQKfzUAAgsACQnrGPwSAGUCAAsACQnrGPwSAGUCAAAA.',
Sp='Spears:BAAALgAECgYJEwAAAA==.Spoonbrew:BAAALgAECgYJBgABLgAFFAIJBwAYAGUiAA==.Spoondot:BAABLgAECn8kAAMkAAgJ7yXjAgB7AgAeAAgJbSPaEwCkAgAkAAcJhiTjAgB7AgABLgAFFAIJBwAYAGUiAA==.Spoonknight:BAACLgAFFH8HAAMYAAIJZSLxFACiAAAZAAIJIh4noACwAAAYAAIJxBTxFACiAAAuAAQKfxoAAxgACQl/IC8EAGgCABkACAnEHY4hAHACABgACAmXHy8EAGgCAAAA.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Staceyrella:BAAALgAECgEJAgAAAA==.Stainpngolin:BAABLgAECn8gAAIOAAgJsh1MCABPAgAOAAgJsh1MCABPAgAAAA==.Stillhorn:BAABLgAECn8mAAMMAAkJtBm0IQA5AgAMAAkJpRe0IQA5AgAaAAgJGRteDQAyAgAAAA==.Stinjeras:BAABLgAECn8yAAIeAAkJoSEECwDsAgAeAAkJoSEECwDsAgAAAA==.Stinkyjo:BAABLgAECn8yAAINAAkJbxoCEQC3AgANAAkJbxoCEQC3AgAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAACLgAFFH8IAAIRAAQJbQvuVgDPAAARAAQJbQvuVgDPAAAuAAQKfyIAAhEACQmGHgobAHACABEACQmGHgobAHACAAAA.',
Su='Suian:BAAALgADCgEJAQAAAA==.Sunadoria:BAAALgAECgUJEwAAAA==.Sunlite:BAAALgAECgEJAgAAAA==.Sunrae:BAABLgAECn8pAAQjAAgJMRrGEQA8AgAjAAgJZxjGEQA8AgAJAAMJShQXXQC+AAAQAAUJcwmqUwCbAAAAAA==.Sushi:BAABLgAECn8fAAIbAAkJlRMbFwDhAQAbAAkJlRMbFwDhAQAAAA==.',
Sv='Sven:BAAALgAECgUJCQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAAALgAECgQJDQAAAA==.',
['Sö']='Söap:BAAALgAECgYJCAAAAA==.',
Ta='Taggert:BAAALgAECgEJAQAAAA==.Tahl:BAABLgAECn8wAAIJAAcJRhK4JgB8AQAJAAcJRhK4JgB8AQAAAA==.Talox:BAAALgAECgEJAQAAAA==.Tamanovitch:BAAALgAECgEJAQAAAA==.Tamashii:BAAALgAFFAIJBAABLgAFFAQJEAADAPIMAA==.Tangriah:BAAALgADCgEJAQAAAA==.Taproot:BAAALgADCgEJAQABLgAFFAQJEgAPAA0LAA==.Taryen:BAAALgAECgQJBQABLgAECgkJEgAGAAAAAA==.Tavie:BAABLgAFFH8QAAIPAAQJ8xeZSwA3AQAPAAQJ8xeZSwA3AQAAAA==.',
Te='Teddy:BAAALgADCgYJBgAAAA==.Tedo:BAAALgADCgcJDgABLgAFFAQJFgALAMogAA==.Teikkas:BAAALgAECgYJCwAAAA==.Telaari:BAAALgAECgQJBgAAAA==.',
Th='Thalenia:BAACLgAFFH8KAAIRAAQJFQSjRgD4AAARAAQJFQSjRgD4AAAuAAQKfygAAx8ACAm3CfsYANYAABEABwnQCixhAEQBAB8ACAlhBvsYANYAAAAA.Thallenia:BAAALgADCgEJAQAAAA==.Thalron:BAAALgADCgEJAgAAAA==.Thayne:BAAALgADCgEJAQAAAA==.Thekingdom:BAABLgAECn8eAAIPAAgJVh1fRQBnAgAPAAgJVh1fRQBnAgAAAA==.Thom:BAAALgADCgEJAQAAAA==.Thriller:BAAALgAECgUJCwABLgAFFAQJFgALAMogAA==.',
Ti='Tikeidari:BAABLgAECn9IAAIUAAkJECY5AABxAwAUAAkJECY5AABxAwAAAA==.Tiltedtroll:BAABLgAECn8rAAISAAkJnhJ4IwCzAQASAAkJnhJ4IwCzAQAAAA==.Timedemon:BAABLgAECn8mAAIMAAkJcRuyJAAnAgAMAAkJcRuyJAAnAgAAAA==.Tinuveuil:BAAALgADCgYJBgAAAA==.',
To='Toiletseat:BAAALgAECgUJBQAAAA==.Tonjuras:BAABLgAECn8iAAMiAAkJSyGcAwBfAgAiAAgJJB6cAwBfAgAnAAkJKByACwBWAgAAAA==.Toona:BAACLgAFFH8FAAIMAAIJ5Am3eAByAAAMAAIJ5Am3eAByAAAuAAQKfxwAAgwACQn7GgYcAKoCAAwACQn7GgYcAKoCAAEuAAUUBAkFABkAcRIA.Torogrande:BAAALgADCgkJKgAAAA==.Touchmyting:BAAALgAECgEJAwAAAA==.Toutii:BAAALgAECgUJBgABLgAECgcJEgAGAAAAAA==.',
Tr='Trappybear:BAAALgAECgIJAgABLgAFFAQJDAAhAHoQAA==.Trappydh:BAABLgAFFH8IAAIUAAQJbRALBgDcAAAUAAQJbRALBgDcAAABLgAFFAQJDAAhAHoQAA==.Trappydk:BAACLgAFFH8MAAIhAAQJehBQGgDtAAAhAAQJehBQGgDtAAAuAAQKfxYAAiEACAmFGkETAMMBACEACAmFGkETAMMBAAAA.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8sAAMeAAgJsSStCwAdAwAeAAgJsSStCwAdAwAkAAEJAADgIQBqAAAAAA==.',
Ty='Tyraxus:BAAALgADCgkJEAAAAA==.Tyronne:BAAALgAECgcJBwAAAA==.',
['Tý']='Týr:BAAALgADCgUJBwAAAA==.',
Ul='Ultraball:BAAALgAECggJDwAAAA==.',
Un='Unagi:BAABLgAECn8qAAIBAAgJeA81HACuAQABAAgJeA81HACuAQAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAABLgAECn8YAAIPAAgJOAiRmQAtAQAPAAgJOAiRmQAtAQAAAA==.Vaesir:BAAALgADCgcJDQAAAA==.Varleara:BAABLgAECn8gAAMMAAgJziFEEwDmAgAMAAgJziFEEwDmAgAUAAEJKQeHLQAqAAAAAA==.',
Ve='Venenn:BAAALgADCgEJAgAAAA==.Venev:BAAALgAECgUJCgAAAA==.Ventana:BAABLgAECn80AAIXAAgJrCETBAClAgAXAAgJrCETBAClAgAAAA==.Verdilac:BAABLgAECn8wAAIKAAkJIxv8PQD2AQAKAAkJIxv8PQD2AQABLgAFFAQJDQAlABYfAA==.',
Vi='Vinceglortho:BAAALgAECgQJCQAAAA==.Vindicator:BAABLgAECn8fAAIKAAkJSB1RGwCJAgAKAAkJSB1RGwCJAgAAAA==.Violetnoir:BAAALgAECgQJBAABLgAECgcJGgAeANsIAA==.Visiroth:BAABLgAECn8gAAMZAAkJNQ1fXACgAQAZAAkJJAtfXACgAQAhAAgJmQjSJAAUAQAAAA==.',
Vy='Vyyral:BAAALgAECgIJAgABLgAECgkJHwAaANYaAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAFFAQJDQAPAKUEAA==.Wallydk:BAABLgAECn8xAAIZAAkJTBvPGACgAgAZAAkJTBvPGACgAgAAAA==.Wanji:BAABLgAECn8rAAIZAAkJCwtCXACgAQAZAAkJCwtCXACgAQAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Wenesday:BAAALgADCgcJEgAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Widginatrix:BAABLgAECn8ZAAIcAAgJwA1qLQBUAQAcAAgJwA1qLQBUAQAAAA==.Willkain:BAAALgAECgMJAwAAAA==.',
Wo='Woah:BAAALgAECgMJAwABLgAFFAIJBwAYAGUiAA==.Woons:BAAALgAECgMJCAAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Xa='Xaya:BAABLgAECn8aAAMeAAcJ2wjzkQAPAQAeAAcJ2wjzkQAPAQAdAAQJ6AJJUQB6AAAAAA==.',
Xe='Xenophorge:BAAALgAECgEJAQAAAA==.Xeralvezyn:BAAALgADCgkJCQAAAA==.',
Xi='Xiva:BAABLgAECn8rAAInAAgJWBGBGwCkAQAnAAgJWBGBGwCkAQAAAA==.',
Xo='Xovace:BAABLgAECn8WAAMaAAcJFwurKgAIAQAaAAcJFwurKgAIAQAMAAEJHwM/HAEcAAAAAA==.',
Xt='Xtayse:BAABLgAECn8nAAIEAAkJYx9UAQDhAgAEAAkJYx9UAQDhAgAAAA==.Xtaysì:BAAALgAECgEJAQAAAA==.',
Ya='Yagorbomb:BAAALgAECgEJAgAAAA==.Yamyam:BAABLgAECn8VAAIcAAkJsg/HKQCyAQAcAAkJsg/HKQCyAQAAAA==.',
Yi='Yirya:BAAALgADCgcJFwAAAA==.',
Yo='Yoruechi:BAACLgAFFH8NAAIOAAQJBRx0BwBOAQAOAAQJBRx0BwBOAQAuAAQKfyoAAg4ACAkoI3IEALoCAA4ACAkoI3IEALoCAAAA.',
['Yú']='Yúmyúm:BAABLgAECn8lAAIKAAkJWBfxQADsAQAKAAkJWBfxQADsAQAAAA==.',
Za='Zahel:BAABLgAECn8uAAIKAAkJlB6jFACzAgAKAAkJlB6jFACzAgAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECgkJLgAKAJQeAA==.Zalark:BAAALgADCgUJCgABLgAECggJMQAJAO4VAA==.Zangai:BAAALgAECggJCAABLgAECggJGQATAHQLAA==.Zavier:BAAALgAECgEJAQABLgAECgMJAwAGAAAAAA==.',
Ze='Zeneri:BAABLgAECn84AAMmAAkJhRDvJQDNAQAmAAkJhRDvJQDNAQAWAAkJyRD7GQDLAQAAAA==.',
Zo='Zobi:BAAALgAECgQJDgAAAA==.Zodius:BAAALgADCgEJAQAAAA==.Zomboo:BAAALgAFFAEJAQAAAA==.',
Zu='Zugzugzug:BAAALgADCgMJBgAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAFFAQJBwASALMEAA==.',
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
