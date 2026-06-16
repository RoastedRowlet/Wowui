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

local lookup = {'Paladin-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Warrior-Protection','Warrior-Arms','Priest-Holy','Paladin-Retribution','Paladin-Holy','DemonHunter-Devourer','Druid-Restoration','Druid-Guardian','Mage-Frost','Priest-Shadow','Hunter-BeastMastery','Shaman-Elemental','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Mage-Fire','Monk-Brewmaster','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','Priest-Discipline','Warlock-Affliction','DemonHunter-Havoc','Druid-Feral','Monk-Mistweaver','Rogue-Subtlety',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-06-14',data={Ac='Acelara:BAAALgADCgUJBQAAAA==.',
Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ae='Aeons:BAAALgAECgEJAQABLgAECgkJSgABADohAA==.',
Ah='Ahmet:BAABLgAECn8WAAICAAkJZhMUFQD8AQACAAkJZhMUFQD8AQABLgAECgkJSgABADohAA==.',
Ai='Aiax:BAACLgAFFH8IAAIDAAMJRAIuJAB2AAADAAMJRAIuJAB2AAAuAAQKfxcABAQACAlODDQgACwBAAUABgmnDb0xADoBAAQABglkCjQgACwBAAMAAglJB0VGAEAAAAAA.',
Al='Alderok:BAAALgAECgQJCQABLgAECgYJBwAGAAAAAA==.Aliancia:BAABLgAECn8+AAMHAAkJKhRCFwCGAQAHAAgJSRVCFwCGAQAIAAgJgguqIgBJAQAAAA==.Almur:BAAALgAECgcJDAAAAA==.Alyda:BAAALgADCggJFAAAAA==.',
Am='Amalthea:BAAALgAECgIJAwAAAA==.Amet:BAABLgAECn9KAAIBAAkJOiElAwDpAgABAAkJOiElAwDpAgAAAA==.',
An='Anakinn:BAAALgAECgUJBQAAAA==.Ankelbyter:BAAALgAECgEJAQABLgAECggJHAABAMwTAA==.Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8wAAIJAAkJBxvHEwA3AgAJAAkJBxvHEwA3AgAAAA==.Annutar:BAAALgADCgUJBQAAAA==.Antherina:BAAALgADCgQJBwAAAA==.Antonious:BAAALgADCgMJAwAAAA==.Antonlavay:BAAALgAECgQJBAAAAA==.',
Ap='Aphyra:BAAALgADCgUJBQAAAA==.Apollyon:BAACLgAFFH8MAAIKAAQJJSFMJwBoAQAKAAQJJSFMJwBoAQAuAAQKfycAAwoACQnEIUoSANQCAAoACQnEIUoSANQCAAsAAgkqFax+AH8AAAAA.',
Ar='Arlechino:BAACLgAFFH8UAAIMAAQJ4RTxPwAjAQAMAAQJ4RTxPwAjAQAuAAQKfx0AAgwACAkXF1lAAPMBAAwACAkXF1lAAPMBAAAA.Arywyn:BAABLgAECn8dAAINAAgJNAvqXAAeAQANAAgJNAvqXAAeAQAAAA==.',
As='Assclapiuss:BAABLgAECn9AAAMKAAkJtyUyAwBlAwAKAAkJtyUyAwBlAwALAAEJTwc+lgAoAAAAAA==.Asterchades:BAABLgAECn9UAAIOAAkJyB9iBADQAgAOAAkJyB9iBADQAgAAAA==.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgkJEAAAAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn9RAAIPAAkJvgUWkABVAQAPAAkJvgUWkABVAQAAAA==.Atuan:BAABLgAECn8aAAIQAAgJrBBBKgB/AQAQAAgJrBBBKgB/AQAAAA==.',
Au='Auralass:BAABLgAECn8bAAIRAAgJXRbtRwDHAQARAAgJXRbtRwDHAQAAAA==.Aurene:BAAALgAECgkJNAAAAQ==.Autym:BAAALgADCgkJCQAAAA==.',
Av='Avaric:BAAALgAECgEJAQABLgAECggJGAASAEIFAA==.Avatard:BAAALgAFFAIJAgABLgAFFAQJFAAPAD4HAA==.Avilla:BAAALgAECgUJCQAAAA==.',
Ax='Axem:BAABLgAECn8uAAITAAkJmB3EDQCSAgATAAkJmB3EDQCSAgAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azulathan:BAABLgAECn8bAAMUAAgJ3Bb6CQDEAQAUAAgJ3Bb6CQDEAQAMAAcJwwq9jgAEAQABLgAECggJNAAVAP4TAA==.',
Ba='Bamseyn:BAAALgADCgYJCwAAAA==.Bamsheyn:BAAALgADCgkJCQAAAA==.Bangpewpew:BAAALgAECgEJAQAAAA==.Baraxor:BAABLgAECn80AAMVAAgJ/hOqQwCcAQAVAAgJ/hOqQwCcAQASAAgJrw9zPwA0AQAAAA==.Barrelaged:BAAALgAECgYJCQAAAA==.',
Be='Beararms:BAAALgAECgEJAgAAAA==.Beerguy:BAABLgAECn8ZAAIWAAgJrgw+MgA6AQAWAAgJrgw+MgA6AQAAAA==.Behemothe:BAABLgAECn9RAAMXAAkJuiJxAQAlAwAXAAkJuiJxAQAlAwAVAAUJFiB5NwDPAQAAAA==.Berníesandrs:BAABLgAECn8zAAIPAAkJuQ4EZQCxAQAPAAkJuQ4EZQCxAQAAAA==.Beryllos:BAAALgAECgYJEwAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECggJDgAAAA==.Bigdamage:BAAALgAECgIJAgABLgAFFAIJBwAYAGUiAA==.Bigdmg:BAABLgAFFH8FAAIZAAIJVRc2zwCNAAAZAAIJVRc2zwCNAAAAAA==.Biggusdiscus:BAAALgAECgMJAwAAAA==.Bigimpin:BAAALgADCgcJBwAAAA==.Bisky:BAAALgAECggJDwABLgAECgkJIgAOAL8fAA==.',
Bj='Bjôrn:BAAALgAECgcJDQAAAA==.',
Bl='Bledana:BAAALgAECgcJDQAAAA==.Bleué:BAAALgADCgEJAQABLgAECgkJPAANAPEaAA==.Bloodmourne:BAABLgAECn8yAAIZAAkJmSWQBQBNAwAZAAkJmSWQBQBNAwAAAA==.Bloodytoutii:BAABLgAECn8VAAQaAAgJjh8lAgBJAgAaAAYJ3yElAgBJAgAbAAUJNxLLCQDeAAAPAAEJAADQgwEAAAAAAA==.',
Bo='Borthyr:BAABLgAECn8tAAMFAAkJvx/KCADKAgAFAAkJoR7KCADKAgAEAAYJ0RyqDgDwAQAAAA==.Bortman:BAAALgAECgUJCQABLgAECgkJLQAFAL8fAA==.Bowowner:BAABLgAECn8hAAIRAAgJxh4RPwDjAQARAAgJxh4RPwDjAQAAAA==.',
Br='Branchmanagr:BAABLgAECn8iAAIOAAkJ6RGuFACtAQAOAAkJ6RGuFACtAQAAAA==.Breddamon:BAAALgADCgMJAwAAAA==.Brewlee:BAAALgAFFAQJBAAAAA==.Bricter:BAAALgADCgkJCQABLgAECgkJPQAPAFkVAA==.Brokenkrayon:BAAALgAECgQJBgAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Bullséye:BAAALgAECgEJAQAAAA==.Busta:BAABLgAECn8fAAIPAAkJZwUArQAkAQAPAAkJZwUArQAkAQAAAA==.',
Bw='Bwicked:BAABLgAECn8lAAIPAAkJ/hd8MwBJAgAPAAkJ/hd8MwBJAgAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgcJDwAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Calzone:BAAALgAECggJEwAAAA==.Cantpurge:BAAALgAECgMJAwABLgAECgcJFwAQAAkIAA==.Carebears:BAAALgAECgQJBQAAAA==.Caroline:BAAALgAECgEJAQAAAA==.',
Ce='Celonge:BAAALgAECgUJBQABLgAFFAUJBQALAGMFAA==.',
Ch='Chamelean:BAAALgAECgYJEQABLgAFFAMJBwAMABEMAA==.Charmcaster:BAAALgAECgEJAQAAAA==.Chimpnzthat:BAABLgAECn82AAIcAAgJHhTrIACeAQAcAAgJHhTrIACeAQAAAA==.Chookicookie:BAABLgAECn9HAAMSAAkJ9h5xCgC2AgASAAkJ9h5xCgC2AgAVAAkJ1SCGFACkAgAAAA==.Chrome:BAABLgAECn9UAAMdAAkJDySCAgBLAwAdAAkJDySCAgBLAwANAAgJyB1+HgBLAgAAAA==.Chuckarita:BAABLgAECn8gAAIdAAkJnQr0MgBLAQAdAAkJnQr0MgBLAQAAAA==.',
Ci='Cinde:BAAALgADCgEJAQAAAA==.Cindyy:BAABLgAECn8iAAIWAAgJiyHZCwCEAgAWAAgJiyHZCwCEAgABLgAFFAQJCwARADscAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgIJAgAAAA==.',
Co='Coedwig:BAAALgAECgMJAwAAAA==.Consfiracy:BAAALgAFFAEJAQAAAA==.Coresh:BAAALgAFFAMJAwAAAA==.Cornpuff:BAABLgAECn8aAAMeAAgJoiRUCgCcAQAfAAUJdiTxMgAMAgAeAAUJ+CRUCgCcAQAAAA==.Cortiz:BAABLgAECn9CAAIRAAkJaRIeQQDcAQARAAkJaRIeQQDcAQAAAA==.',
Cr='Crankdog:BAABLgAECn8rAAMRAAkJ1iTBBQA2AwARAAkJ1iTBBQA2AwAgAAYJ8g9oSgApAQAAAA==.Creedd:BAABLgAECn8vAAINAAgJGiB+FACkAgANAAgJGiB+FACkAgABLgAECgkJGwAVAMIfAA==.Crialta:BAAALgADCgcJFAAAAA==.',
Cu='Cupsandcakes:BAABLgAECn8eAAIaAAgJOwx6BgBXAQAaAAgJOwx6BgBXAQAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Damessiah:BAABLgAECn81AAMJAAkJnBQGFgAgAgAJAAkJnBQGFgAgAgAQAAEJ8AE7mgAWAAAAAA==.Darandeh:BAAALgAECgMJAwAAAA==.Dark:BAABLgAECn9PAAIfAAkJ4SLlBQAyAwAfAAkJ4SLlBQAyAwAAAA==.Darkphyre:BAABLgAECn8cAAIKAAgJtQy7jABWAQAKAAgJtQy7jABWAQAAAA==.Darksparx:BAAALgAECgEJAQAAAA==.Darkstormn:BAAALgAECgYJCgAAAA==.Darthtree:BAAALgAECgMJAwAAAA==.Dawling:BAAALgAECggJDgAAAA==.',
De='Deadmandan:BAABLgAECn8vAAMfAAkJHSXCBQBgAwAfAAkJHSXCBQBgAwAeAAYJISSxBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn9RAAIhAAkJ3ySHAQBHAwAhAAkJ3ySHAQBHAwAAAA==.Decius:BAABLgAECn8cAAIiAAgJsggHDgBDAQAiAAgJsggHDgBDAQAAAA==.Dedsexxy:BAAALgADCgQJBAAAAA==.Deltairlines:BAACLgAFFH8SAAMFAAYJvhzZFgCqAQAFAAYJvhzZFgCqAQADAAQJQAUxHgC5AAAuAAQKfxoAAgUACQnWHsIJALsCAAUACQnWHsIJALsCAAAA.Deltayaya:BAABLgAFFH8LAAMVAAUJ1gyLKAA+AQAVAAUJ1gyLKAA+AQASAAEJpQ/DUgA/AAABLgAFFAYJEgAFAL4cAA==.Demagorgin:BAACLgAFFH8HAAIKAAMJBxH6aQDXAAAKAAMJBxH6aQDXAAAuAAQKfzkAAgoACQmeHK0iAHoCAAoACQmeHK0iAHoCAAAA.Demcheekz:BAAALgAECgIJAgAAAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAABLgAECn8WAAQjAAgJxwk0OwAjAQAjAAcJsAg0OwAjAQAJAAQJpQmTUACaAAAQAAEJGANwmAAcAAAAAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn84AAIKAAkJ/R6dFQDAAgAKAAkJ/R6dFQDAAgAAAA==.Desmus:BAABLgAECn82AAIdAAgJoRjvGgDwAQAdAAgJoRjvGgDwAQAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAFFAUJHAAfALcjAA==.Devilmaycry:BAAALgADCgEJAQAAAA==.Deáthreaver:BAABLgAECn8yAAIKAAkJmBFqSgDmAQAKAAkJmBFqSgDmAQAAAA==.',
Di='Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAABLgAECn8eAAILAAkJJhIvIwDpAQALAAkJJhIvIwDpAQAAAA==.Ditar:BAAALgAECgEJAgABLgAECgYJCgAGAAAAAA==.',
Dk='Dk:BAAALgADCgIJAgABLgAFFAMJCQARABkkAA==.',
Do='Domwarlock:BAABLgAFFH8JAAMfAAQJFQ1ogQC/AAAfAAMJagpogQC/AAAkAAEJExVAIABPAAAAAA==.Doogang:BAAALgAECgEJAQAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.Doublehungus:BAAALgAECgkJAQAAAA==.',
Dr='Drackal:BAAALgAECgEJAQAAAA==.Dradin:BAAALgADCgMJAwAAAA==.Dragondznutz:BAAALgAECgYJDAABLgAECgkJQAAKALclAA==.Dronin:BAABLgAECn8qAAMgAAkJQRrpDwBaAQAgAAcJZBbpDwBaAQARAAUJxx29cQBZAQAAAA==.Drpatan:BAABLgAECn8uAAIlAAgJVAiILQASAQAlAAgJVAiILQASAQAAAA==.Druni:BAABLgAECn8dAAIBAAgJ0wj5IAAKAQABAAgJ0wj5IAAKAQAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Ec='Echowalker:BAABLgAECn8ZAAIlAAgJnRj2FQDYAQAlAAgJnRj2FQDYAQAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
Eh='Ehdawg:BAAALgAECgEJAQAAAA==.',
Ei='Eisenthorne:BAAALgADCgEJAgAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elemann:BAAALgAECgQJBQAAAA==.Elguezo:BAABLgAECn8VAAIWAAYJUhwMIwCXAQAWAAYJUhwMIwCXAQAAAA==.Elysyn:BAAALgADCgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emmerick:BAAALgAECgQJCAAAAA==.Emokillaz:BAABLgAECn8WAAIlAAcJ2hitIwCgAQAlAAcJ2hitIwCgAQAAAA==.',
Ep='Epictaxes:BAABLgAECn8UAAISAAgJnxb2IQDSAQASAAgJnxb2IQDSAQAAAA==.Epimetheuz:BAAALgADCgYJAwABLgAECgcJCwAGAAAAAA==.Epsi:BAAALgAECgYJCQABLgAECgcJFwAQAAkIAA==.Epsilón:BAABLgAECn8XAAIQAAcJCQgRSwDiAAAQAAcJCQgRSwDiAAAAAA==.',
Et='Eternalpeace:BAAALgAECgEJAgAAAA==.',
Ev='Evelana:BAAALgADCgQJBwAAAA==.',
Ex='Exaduss:BAABLgAECn8VAAMeAAgJUyH+CAAxAgAeAAgJUyH+CAAxAgAfAAQJHB4aggA1AQAAAA==.',
Ez='Ezora:BAAALgAECgcJDAAAAA==.',
Fa='Famulimus:BAAALgAECgcJCgABLgAECgkJFwANAHkYAA==.Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAABLgAECn8uAAIRAAkJHRkDIABlAgARAAkJHRkDIABlAgAAAA==.Faylan:BAABLgAECn8VAAIRAAYJ/A0fnAAFAQARAAYJ/A0fnAAFAQAAAA==.',
Fe='Felshadow:BAAALgAECgEJAwAAAA==.Feronnia:BAAALgAECgUJBQAAAA==.',
Fi='Fibot:BAABLgAECn9IAAIXAAkJQCBuAgD0AgAXAAkJQCBuAgD0AgAAAA==.Fingon:BAAALgAECgcJEgAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJKgAPAKkUAA==.Florasol:BAAALgADCgIJAgAAAA==.Florezner:BAAALgADCgMJAwAAAA==.',
Fo='Foxling:BAEALgAECgUJCwAAAA==.',
Fr='Fraeyah:BAAALgAECgcJBwAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAACLgAFFH8MAAIPAAQJKA2qZgAcAQAPAAQJKA2qZgAcAQAuAAQKfxYAAg8ACQkaF2ZUADsCAA8ACQkaF2ZUADsCAAAA.',
Fu='Fulgora:BAABLgAECn8YAAISAAgJQgXRVgDdAAASAAgJQgXRVgDdAAAAAA==.Fullmoon:BAAALgAECgcJDQABLgAECgcJEAAGAAAAAA==.Furicor:BAAALgAECgEJAQAAAA==.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAACLgAFFH8UAAIPAAUJDQvGawARAQAPAAUJDQvGawARAQAuAAQKf0MAAg8ACQnGG/IoAHUCAA8ACQnGG/IoAHUCAAAA.Gasaraki:BAAALgAECgEJAgAAAA==.Gastdhunter:BAAALgAECgEJAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgADCggJCgAAAA==.',
Gi='Gimtar:BAAALgAECgYJCgAAAA==.Ginjockey:BAAALgADCgUJBQABLgAECgcJFwAQAAkIAA==.Gipsydanger:BAACLgAFFH8OAAIjAAMJVh/vJQATAQAjAAMJVh/vJQATAQAuAAQKf0MAAiMACQnWHRYKAM4CACMACQnWHRYKAM4CAAAA.Girllygirl:BAAALgAECgcJDgAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Gladiatrix:BAAALgAECgQJCAAAAA==.Glaurang:BAAALgAECgQJEwAAAA==.Glofor:BAAALgAECgcJDwABLgAECgkJKgAPAKkUAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECggJGAAVAMcWAA==.Gnomeregrets:BAAALgAECgUJBQABLgAECgYJDQAGAAAAAA==.Gnomestone:BAABLgAFFH8JAAIfAAMJ+QP+iwCoAAAfAAMJ+QP+iwCoAAAAAA==.',
Go='Goldencorpse:BAAALgAECgcJBwAAAA==.Goldenspoon:BAAALgADCgEJAQABLgAFFAIJBwAYAGUiAA==.Gorlokk:BAEALgADCgMJAwABLgADCgYJBgAGAAAAAA==.',
Gr='Grakonys:BAABLgAECn9FAAMFAAkJ3xf+EQBSAgAFAAkJ3xf+EQBSAgAEAAcJ4Qc7HQBFAQAAAA==.Granger:BAAALgAECgIJAgABLgAECgIJBAAGAAAAAA==.Greed:BAABLgAECn89AAIWAAkJuR7nBwDHAgAWAAkJuR7nBwDHAgAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAABLgAECn8UAAIhAAYJnhUeIQBHAQAhAAYJnhUeIQBHAQAAAA==.Grimmvelt:BAAALgAECgQJBAAAAA==.Grounch:BAAALgADCgcJDAAAAA==.Grunch:BAAALgADCgkJCQAAAA==.Grunnck:BAAALgADCgkJPwAAAA==.',
Gu='Guayusa:BAAALgAFFAEJAQAAAA==.Gunned:BAAALgADCgEJAQAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQAGAAAAAA==.',
Ha='Hacheron:BAAALgADCgIJAgABLgAFFAUJDQAhAHoQAA==.Hallows:BAAALgAECgYJDgAAAA==.Harnix:BAABLgAECn8tAAIKAAgJ9g4RfAB1AQAKAAgJ9g4RfAB1AQAAAA==.Harron:BAAALgAECgUJBQAAAA==.Hawtbooty:BAABLgAECn8yAAIJAAkJDRy8GAADAgAJAAkJDRy8GAADAgAAAA==.Haziel:BAEALgADCgYJBgAAAA==.',
He='Heartsbane:BAAALgAECgEJAQAAAA==.Helixrage:BAABLgAECn8XAAIHAAkJ/QXNJAAIAQAHAAkJ/QXNJAAIAQAAAA==.Hellreines:BAABLgAECn8iAAIYAAgJzCHBBAB3AgAYAAgJzCHBBAB3AgAAAA==.Herpderplol:BAABLgAECn8cAAImAAkJDBGKEACrAQAmAAkJDBGKEACrAQAAAA==.',
Hi='Hildi:BAABLgAECn82AAMnAAgJ8AL5gQCUAAAnAAgJ8AL5gQCUAAAWAAEJyAEnjAAfAAAAAA==.Him:BAACLgAFFH8HAAITAAMJ0RhDMgDjAAATAAMJ0RhDMgDjAAAuAAQKfyoAAhMACQmcI4sFAAcDABMACQmcI4sFAAcDAAAA.',
Ho='Holy:BAACLgAFFH8MAAIjAAMJGhkvLQDjAAAjAAMJGhkvLQDjAAAuAAQKfz8AAyMACQk3Ic0DAGADACMACQk3Ic0DAGADAAkAAQmDHM1lAEgAAAAA.Holyscales:BAAALgAECgEJAQAAAA==.Hoots:BAAALgAECgQJBQAAAA==.Hottopic:BAAALgAECgYJBwAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgAECgEJAgAAAA==.Humânity:BAAALgADCgYJBgAAAA==.Hurcules:BAAALgAECgUJBQAAAA==.',
['Hø']='Høåx:BAAALgAECgYJBgABLgAECgQJBAAGAAAAAA==.',
['Hü']='Hümänïty:BAAALgAECgcJBQABLgAFFAcJEgAKAFYSAA==.',
Il='Illbloodarch:BAABLgAECn8/AAIIAAkJ7BCEEwDDAQAIAAkJ7BCEEwDDAQAAAA==.Illidaris:BAAALgAECggJCQAAAA==.Illvicious:BAABLgAECn8VAAMKAAYJvxDmqgAlAQAKAAYJvxDmqgAlAQABAAIJGgWMTQA2AAAAAA==.',
Im='Imaginos:BAAALgAECgUJBQAAAA==.',
In='Incredibread:BAAALgAECggJEwAAAA==.Indub:BAAALgAECgcJCwAAAA==.',
Ir='Ironfistmogu:BAAALgADCgkJCQAAAA==.',
Is='Ishura:BAABLgAECn8tAAILAAgJZQoKPABWAQALAAgJZQoKPABWAQAAAA==.',
It='Itslevi:BAAALgAFFAEJAQAAAA==.',
Iv='Ivvy:BAABLgAECn8bAAIdAAgJswpLOQArAQAdAAgJswpLOQArAQAAAA==.',
Iz='Izanami:BAABLgAECn8tAAIlAAkJeR/8BQDZAgAlAAkJeR/8BQDZAgAAAA==.',
Ja='Jadinkalage:BAAALgAECgQJBAAAAA==.Jaewreth:BAAALgAECgIJAgAAAA==.Janntro:BAABLgAECn8hAAMlAAkJyx2+DgA3AgAlAAkJphq+DgA3AgAUAAIJgyUiGQDSAAABLgAECgkJIgAOAL8fAA==.Jantra:BAAALgAECgEJAgABLgAECgkJIgAOAL8fAA==.Jantro:BAABLgAECn8iAAIOAAkJvx95BADOAgAOAAkJvx95BADOAgAAAA==.Janttro:BAAALgAECgIJBAABLgAECgkJIgAOAL8fAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAACLgAFFH8MAAMVAAQJ0hDgPQDnAAAVAAQJ0hDgPQDnAAASAAQJswTvMgC+AAAuAAQKfykAAxUACQmyE8E6AMEBABUACQmyE8E6AMEBABIAAwnFCpRsAJEAAAAA.Jeleka:BAAALgAECgYJBgABLgAECgkJJgAVAAkeAA==.Jelmarr:BAABLgAECn8WAAIfAAcJ0xkVVACgAQAfAAcJ0xkVVACgAQAAAA==.Jemmâ:BAABLgAECn8UAAIHAAkJ0RmrGgBhAQAHAAkJ0RmrGgBhAQAAAA==.Jerauld:BAABLgAECn81AAImAAgJLxJjEwCEAQAmAAgJLxJjEwCEAQAAAA==.Jezrra:BAAALgAECggJDwAAAA==.',
Jh='Jhuloot:BAAALgAECgEJAQAAAA==.',
Ji='Jiddles:BAAALgAECgMJAwABLgAECgkJJgAVAAkeAA==.',
Jo='Johnnyzyns:BAABLgAECn8yAAMZAAkJOB1eHQCVAgAZAAkJOB1eHQCVAgAhAAEJthhOWAA7AAAAAA==.Jokhasta:BAABLgAECn8ZAAIXAAgJvBY/CwAYAgAXAAgJvBY/CwAYAgAAAA==.Joshc:BAABLgAECn8yAAIOAAkJHg1MIgA5AQAOAAkJHg1MIgA5AQAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
Ju='Judgejudee:BAAALgADCgcJFgAAAA==.Judgédred:BAAALgAECgcJDAAAAA==.',
['Já']='Ják:BAABLgAECn8cAAQBAAgJzBMPGwA2AQABAAcJJhEPGwA2AQALAAMJvwt4fABSAAAKAAEJpwNevwEhAAAAAA==.',
Ka='Kaaris:BAABLgAECn8lAAIeAAkJ3A+bCQCpAQAeAAkJ3A+bCQCpAQAAAA==.Kaetora:BAAALgADCgkJEgAAAA==.Kaiarie:BAABLgAECn8jAAIkAAgJAwngEgA6AQAkAAgJAwngEgA6AQAAAA==.Kainraziel:BAACLgAFFH8HAAIMAAMJEQyKZwC5AAAMAAMJEQyKZwC5AAAuAAQKfx4AAgwACQkMFdo7ANUBAAwACQkMFdo7ANUBAAAA.Kairos:BAABLgAECn9OAAIPAAkJDhODRQAIAgAPAAkJDhODRQAIAgAAAA==.Kalasta:BAAALgADCgIJAgAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karem:BAAALgAECgEJAQAAAA==.Karkea:BAAALgAECgEJBAAAAA==.Kayper:BAAALgAECgcJAgAAAA==.Kayyos:BAAALgAECgkJCQAAAA==.',
Ke='Kebin:BAABLgAECn8xAAIHAAkJvhfHDgD7AQAHAAkJvhfHDgD7AQAAAA==.Kekkoken:BAAALgAECgEJAQAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.Kenkenif:BAAALgAECgYJDgAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgAAAA==.',
Ki='Kibil:BAAALgAECgUJCAABLgAECgkJJAAZAHMOAA==.Killmonger:BAAALgAECgYJCwAAAA==.Kimsambo:BAAALgAECgQJBAAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Kn='Knocksteady:BAAALgAECgUJBgAAAA==.',
Ko='Koga:BAAALgAECgQJBAAAAA==.Korax:BAAALgAECgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAABLgAECn8yAAIDAAkJTiNcAQCMAwADAAkJTiNcAQCMAwAAAA==.Korzillian:BAAALgAECgEJAQAAAA==.Kos:BAACLgAFFH8QAAIQAAQJxiU6CgC2AQAQAAQJxiU6CgC2AQAuAAQKfyUAAhAACQlFIh8FAAUDABAACQlFIh8FAAUDAAAA.',
Kr='Kreyali:BAAALgAECgIJAwAAAA==.Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgcJEwAAAA==.Kuntar:BAAALgAECgcJCwAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurkoh:BAAALgAECgIJBAAAAA==.Kurrent:BAABLgAECn8mAAIVAAkJCR7JEwCrAgAVAAkJCR7JEwCrAgAAAA==.',
['Kÿ']='Kÿtten:BAABLgAECn8kAAIBAAkJwwp2GQBMAQABAAkJwwp2GQBMAQAAAA==.',
La='Lad:BAACLgAFFH8JAAIZAAQJRRbcXwAxAQAZAAQJRRbcXwAxAQAuAAQKfxgAAxkACQlyH8sRAN4CABkACQlyH8sRAN4CABgAAQkeCqMXADEAAAAA.Laiyth:BAABLgAECn8bAAIfAAkJfxKwPADpAQAfAAkJfxKwPADpAQAAAA==.Lanfearz:BAAALgADCgEJAQAAAA==.Larryfish:BAABLgAECn8mAAMZAAkJSiEuHACcAgAZAAkJeyAuHACcAgAYAAgJ4x0eBQBqAgAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgMJBgAAAA==.Lavos:BAABLgAECn8wAAIeAAkJ1A6xCwCCAQAeAAkJ1A6xCwCCAQAAAA==.',
Le='Levitikus:BAAALgAFFAEJAQAAAA==.Levìtikus:BAAALgAECgEJAgAAAA==.',
Li='Lideysse:BAAALgAECgMJAwAAAA==.Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lisster:BAABLgAECn8zAAMRAAkJzyCmEADJAgARAAkJzyCmEADJAgAgAAEJkAG2mAAeAAAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8dAAMLAAkJNhuwIAAWAgALAAkJNhuwIAAWAgABAAEJBBULQQA5AAAAAA==.Lizcandor:BAAALgAECgQJEQAAAA==.',
Lo='Loafe:BAACLgAFFH8PAAIKAAQJNQ3RTgANAQAKAAQJNQ3RTgANAQAuAAQKfyoAAgoACAk6DyNlALYBAAoACAk6DyNlALYBAAAA.Lokni:BAAALgAECgYJEQAAAA==.Loriann:BAAALgAECgEJAQAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgAECggJDgAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgcJBwAAAA==.Luthais:BAABLgAECn8dAAIBAAgJ3w19HAAvAQABAAgJ3w19HAAvAQAAAA==.Luxury:BAABLgAECn9FAAIHAAkJXQRkJQADAQAHAAkJXQRkJQADAQAAAA==.',
Ly='Lykanthropos:BAAALgAECgEJAQAAAA==.',
Ma='Mahroq:BAABLgAECn8mAAMJAAgJwhk2HgDtAQAJAAgJnxk2HgDtAQAjAAYJoQnPSADiAAABLgAFFAIJAgAGAAAAAA==.Maingauche:BAAALgAECgQJBAABLgAECgkJNAAGAAAAAA==.Mako:BAACLgAFFH8UAAMDAAQJHRGVGgDmAAADAAQJHRGVGgDmAAAFAAIJcQFeXgBVAAAuAAQKfyUAAgMACAkKIY0EAOACAAMACAkKIY0EAOACAAAA.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8nAAMEAAgJDwyMDgAgAQAFAAcJtgq8NQAjAQAEAAgJygiMDgAgAQAAAA==.Malfuridan:BAAALgAECgMJAgAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Mandas:BAAALgAECgIJAgAAAA==.Maples:BAABLgAECn8nAAMnAAkJXwryQQBgAQAnAAkJXwryQQBgAQAWAAMJ3gFYvwAVAAAAAA==.Mariasha:BAABLgAECn8gAAIRAAYJnQ4UjQAhAQARAAYJnQ4UjQAhAQAAAA==.Marichika:BAAALgADCgcJEQAAAA==.Maryjaine:BAAALgAECgUJDAAAAA==.Mattdeamon:BAAALgADCgUJBwABLgAFFAUJFAAPAA0LAA==.Mazzikin:BAACLgAFFH8HAAIMAAMJvhuoUwDvAAAMAAMJvhuoUwDvAAAuAAQKfy8AAgwACQmYIJUKAPQCAAwACQmYIJUKAPQCAAAA.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Megaterium:BAABLgAECn86AAMJAAkJLxsKDgCEAgAJAAkJLxsKDgCEAgAQAAYJnQq1XgCaAAAAAA==.Melkoor:BAAALgADCgcJEQAAAA==.Menethil:BAABLgAECn8iAAILAAgJoiPRDADCAgALAAgJoiPRDADCAgAAAA==.Metheuz:BAAALgAECgcJCwAAAA==.Mexican:BAABLgAECn8yAAIPAAkJPxNESgD6AQAPAAkJPxNESgD6AQAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgAECgUJDQAAAA==.Mishgrail:BAABLgAECn89AAIcAAkJyCA1BQDsAgAcAAkJyCA1BQDsAgAAAA==.Misosoup:BAAALgAECgUJBQABLgADCgEJAQAGAAAAAA==.Missmisery:BAABLgAECn8rAAIRAAkJAxFfOQD2AQARAAkJAxFfOQD2AQAAAA==.Mithdraug:BAABLgAECn8cAAQdAAgJwBIUMwBLAQAdAAcJ1BEUMwBLAQANAAQJdwbRvgBFAAAmAAEJwAe0XQAiAAAAAA==.Mitzi:BAACLgAFFH8YAAMZAAcJ0RYCMACeAQAZAAYJ0RYCMACeAQAhAAEJAAD/YgAAAAAuAAQKfyQAAhkACQlwI14aAN8CABkACQlwI14aAN8CAAAA.',
Mo='Modrem:BAAALgADCgkJGwAAAA==.Mokhan:BAAALgADCgkJCQAAAA==.Molsan:BAAALgAECgQJBAAAAA==.Monache:BAABLgAECn8ZAAITAAgJdAuAOABlAQATAAgJdAuAOABlAQAAAA==.Mongalf:BAAALgADCgQJBAAAAA==.Montrois:BAAALgAECgQJBAAAAA==.Moocheala:BAAALgAECgEJAQAAAA==.Moofahsa:BAAALgAECgEJAQAAAA==.Moopally:BAAALgAECgQJCAAAAA==.',
My='Mythrilblade:BAAALgAECgcJCQAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Na='Naromir:BAAALgAECgcJDAAAAA==.',
Ne='Neletheus:BAABLgAECn8WAAIfAAcJihCxgQA2AQAfAAcJihCxgQA2AQAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAABLgAECn8eAAIZAAgJAiEMJABzAgAZAAgJAiEMJABzAgAAAA==.Nirvanik:BAAALgAECgQJBQAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECgkJPQAcAMggAA==.',
Nu='Nukusmaximus:BAABLgAECn8xAAIPAAgJ4Qi9mABFAQAPAAgJ4Qi9mABFAQAAAA==.',
Ny='Nyeneave:BAAALgAECgIJAgAAAA==.Nyiah:BAABLgAECn8qAAINAAkJNRkVFgCVAgANAAkJNRkVFgCVAgAAAA==.Nyxiie:BAAALgADCgIJAgAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Od='Odioz:BAAALgAECgMJAwAAAA==.',
Of='Offset:BAAALgAECgEJAgAAAA==.',
Og='Ogdoadtl:BAAALgAECgQJCgAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.',
On='Onex:BAAALgAECgcJCwAAAA==.',
Or='Organicmeat:BAAALgAECggJCQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.Ori:BAAALgAECgQJCQAAAA==.',
Pa='Paleprincess:BAAALgADCgIJAgABLgAECgIJBAAGAAAAAA==.Palii:BAAALgAECgQJBQAAAA==.Partywizard:BAAALgAECgMJAwAAAA==.',
Pe='Persefini:BAACLgAFFH8FAAINAAMJKQLJVwBnAAANAAMJKQLJVwBnAAAuAAQKfxcAAg0ACAkPC/RSAEIBAA0ACAkPC/RSAEIBAAAA.Persephoneia:BAAALgADCgcJDQAAAA==.Petrokull:BAAALgAECgYJEgAAAA==.',
Ph='Phaeder:BAAALgAECgEJAQAAAA==.Pheeguh:BAAALgADCgkJEAAAAA==.Pheylan:BAAALgAECggJEwAAAA==.Philidox:BAAALgAECgYJCgABLgAECggJHAABAMwTAA==.Phood:BAAALgADCgcJBwABLgAECgYJBwAGAAAAAA==.',
Pi='Piety:BAAALgAECgYJBgAAAA==.Pikxs:BAAALgAECgMJAgAAAA==.Pitchou:BAAALgAECgUJCAAAAA==.',
Pl='Plugugly:BAAALgAECgQJBgAAAA==.',
Po='Poenin:BAAALgAECgUJCAAAAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8fAAIRAAkJHQ01VwCbAQARAAkJHQ01VwCbAQAAAA==.Potatobear:BAACLgAFFH8MAAIRAAQJGyWTFQCvAQARAAQJGyWTFQCvAQAuAAQKfzUABBEACQm+JY4CAGcDABEACQm+JY4CAGcDACAABglfI/EZAFsCAAIACQlgGskOAD8CAAAA.',
Pr='Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgAECgMJBAAAAA==.',
Qi='Qiursi:BAAALgAECgUJBQAAAA==.',
Qu='Quicktime:BAABLgAECn9FAAIMAAkJXxx/FACcAgAMAAkJXxx/FACcAgAAAA==.',
Ra='Rafael:BAAALgAECgYJBgABLgAFFAQJFAADAB0RAA==.Ragedh:BAABLgAECn8XAAIMAAkJ+BrKGAB+AgAMAAkJ+BrKGAB+AgAAAA==.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ragnoir:BAAALgAECggJEAAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAAALgADCgEJAQAAAA==.Rashish:BAAALgADCgIJAgAAAA==.Ravies:BAACLgAFFH8FAAIRAAMJSBS8WwDnAAARAAMJSBS8WwDnAAAuAAQKfx4AAhEACQkxHlcQAMsCABEACQkxHlcQAMsCAAAA.Rawdøg:BAAALgADCgEJAQAAAA==.Rayaz:BAAALgAECgUJCwABLgAECgkJFwANAHkYAA==.',
Re='Reeses:BAEALgAECgkJEQABLgADCgYJBgAGAAAAAA==.Refellos:BAAALgAECgEJAgAAAA==.Reinhearts:BAAALgAFFAEJAQAAAA==.Religgar:BAABLgAECn8xAAIZAAkJ7BgYKQBbAgAZAAkJ7BgYKQBbAgAAAA==.Reploidzero:BAAALgAECgUJAQAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAABLgAECn89AAIPAAkJWRXcPQAiAgAPAAkJWRXcPQAiAgAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Roglof:BAABLgAECn8qAAIPAAgJqRSWZgCtAQAPAAgJqRSWZgCtAQAAAA==.Rokkoks:BAAALgAECgIJAgAAAA==.Rowlah:BAAALgAECgcJDgAAAA==.Roxyfoxy:BAAALgAECgcJEAAAAA==.Rozy:BAABLgAECn89AAMLAAkJGBtuEgB/AgALAAkJGBtuEgB/AgAKAAUJZxi/rAAiAQAAAA==.',
Ru='Ruffs:BAABLgAECn8XAAMMAAkJIR37GgBwAgAMAAkJIR37GgBwAgAUAAEJYhAuMwA0AAAAAA==.Ruiizu:BAABLgAECn8yAAIKAAkJJiSgCQAaAwAKAAkJJiSgCQAaAwAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn9GAAIjAAkJeB1jCgDJAgAjAAkJeB1jCgDJAgAAAA==.',
Sa='Saberjaw:BAABLgAECn8XAAMCAAYJrBU3FACCAQACAAYJkRQ3FACCAQARAAIJvwv9EwFEAAAAAA==.Sairicck:BAABLgAECn8tAAIRAAkJcx5MGgCEAgARAAkJcx5MGgCEAgAAAA==.Samaal:BAAALgADCgUJBQABLgAECgkJIgAOAL8fAA==.Samial:BAAALgADCgYJDAABLgAECgkJIgAOAL8fAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgADCggJCgAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satorugojo:BAAALgAECgEJAQAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selenar:BAAALgAECgEJAQAAAA==.Selesé:BAAALgAECgEJAQABLgAECgkJFAAHANEZAA==.Selinora:BAAALgAECgkJDgAAAA==.Senaria:BAAALgAECgMJBwAAAA==.Serhalatath:BAAALgAECggJDAAAAA==.',
Sh='Shade:BAAALgADCgQJBAAAAA==.Shadowsbane:BAAALgAFFAIJAgAAAA==.Shaguar:BAABLgAECn8rAAMKAAkJ0CB/EgDTAgAKAAkJ0CB/EgDTAgALAAcJPhCGXAALAQAAAA==.Shamhawk:BAAALgAECgEJAgAAAA==.Shaolinsnake:BAACLgAFFH8FAAITAAMJ9hOUMgDiAAATAAMJ9hOUMgDiAAAuAAQKfxYAAhMACAm7HKgZACACABMACAm7HKgZACACAAAA.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.Shizzite:BAAALgADCgIJAgAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAACLgAFFH8UAAIPAAQJPgcIcAAFAQAPAAQJPgcIcAAFAQAuAAQKfyQAAg8ACAmWElxpAAMCAA8ACAmWElxpAAMCAAAA.Sinzala:BAABLgAECn8iAAIPAAkJVR9BHQCqAgAPAAkJVR9BHQCqAgAAAA==.',
Sk='Skeetsurfin:BAAALgAECgMJAwAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwABLgAECgkJKwAKANAgAA==.',
Sm='Smallblackdk:BAAALgAFFAIJAwAAAA==.Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.Snowbunnyy:BAAALgAECgEJAQABLgAECgIJBAAGAAAAAA==.',
So='Solai:BAAALgAECgEJAQAAAA==.Solsti:BAACLgAFFH8FAAILAAUJYwU6IwABAQALAAUJYwU6IwABAQAuAAQKf0AAAgsACQnrGGEVAGACAAsACQnrGGEVAGACAAAA.Soulhunter:BAABLgAFFH8HAAIhAAcJwwNwHgDvAAAhAAcJwwNwHgDvAAABLgAFFAgJLwAhAJgaAA==.',
Sp='Spears:BAABLgAECn8aAAIRAAcJjgbMlQARAQARAAcJjgbMlQARAQAAAA==.Spoonarrow:BAAALgAECgEJAQABLgAFFAIJBwAYAGUiAA==.Spoonbrew:BAAALgAECgYJBgABLgAFFAIJBwAYAGUiAA==.Spoondot:BAABLgAECn8mAAMkAAkJ3iWBAQDlAgAkAAgJpySBAQDlAgAfAAgJbSNxFgCcAgABLgAFFAIJBwAYAGUiAA==.Spoonknight:BAACLgAFFH8HAAMYAAIJZSJNHACYAAAZAAIJIh6lvQCmAAAYAAIJxBRNHACYAAAuAAQKfx8ABBgACQl/ICoFAGgCABkACAnEHUUmAGkCABgACAmXHyoFAGgCACEABQluGdIkACoBAAAA.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Staceyrella:BAAALgAECgEJAwAAAA==.Stainpngolin:BAABLgAECn8gAAIOAAgJsh28CQBKAgAOAAgJsh28CQBKAgAAAA==.Stillhorn:BAABLgAECn8oAAMMAAkJtBm/JQA0AgAMAAkJpRe/JQA0AgAlAAgJGRufDwAqAgAAAA==.Stinjeras:BAABLgAECn8yAAIfAAkJoSExDQDjAgAfAAkJoSExDQDjAgAAAA==.Stinkyjo:BAABLgAECn8yAAINAAkJbxqhEgC1AgANAAkJbxqhEgC1AgAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAACLgAFFH8KAAIRAAUJ9wovRQAeAQARAAUJ9wovRQAeAQAuAAQKfyIAAhEACQmGHpwgAGICABEACQmGHpwgAGICAAAA.',
Su='Suian:BAAALgADCgEJAQAAAA==.Sunadoria:BAAALgAECgUJEwAAAA==.Sunlite:BAAALgAECgEJAwAAAA==.Sunrae:BAABLgAECn8yAAQjAAgJMRrvEwA+AgAjAAgJZxjvEwA+AgAQAAYJZwneSgDiAAAJAAMJShQXXQC+AAAAAA==.Sushi:BAABLgAECn8fAAIcAAkJlRP1GADdAQAcAAkJlRP1GADdAQAAAA==.',
Sv='Sven:BAAALgAECgUJCQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAABLgAECn8VAAIJAAYJuwciRQDRAAAJAAYJuwciRQDRAAAAAA==.',
['Sö']='Söap:BAAALgAECgYJCAAAAA==.',
Ta='Taggert:BAAALgAECgEJAQAAAA==.Tahl:BAABLgAECn80AAIJAAcJFhVwIgCsAQAJAAcJFhVwIgCsAQAAAA==.Talox:BAAALgAECgEJAQAAAA==.Tamanovitch:BAAALgAECgEJAQAAAA==.Tamashii:BAAALgAFFAIJAwABLgAFFAQJFAADAB0RAA==.Tangriah:BAAALgADCgEJAQAAAA==.Taproot:BAAALgADCgEJAQABLgAFFAUJFAAPAA0LAA==.Taryen:BAAALgAECgUJCgABLgAECgkJFwAMAPgaAA==.Tavie:BAABLgAFFH8QAAIPAAQJ8xeIWgAxAQAPAAQJ8xeIWgAxAQAAAA==.',
Te='Teddy:BAAALgADCgYJBgAAAA==.Tedo:BAAALgAECgEJAQABLgAFFAUJGQALABkfAA==.Teikkas:BAAALgAECgcJDAAAAA==.Telaari:BAAALgAECgQJBgAAAA==.',
Th='Thalenia:BAACLgAFFH8SAAIRAAQJzQVbUgD+AAARAAQJzQVbUgD+AAAuAAQKfysAAyAACAmyDKIbAM8AABEACAmeDIOGAC4BACAACAlhBqIbAM8AAAAA.Thallenia:BAAALgADCgEJAQAAAA==.Thalron:BAAALgAECgEJAQAAAA==.Thayne:BAAALgADCgYJBwAAAA==.Thekingdom:BAABLgAECn8eAAIPAAgJVh1fRQBnAgAPAAgJVh1fRQBnAgAAAA==.Thom:BAAALgAECgIJAgAAAA==.Thriller:BAAALgAFFAMJAwABLgAFFAUJGQALABkfAA==.',
Ti='Tikeidari:BAABLgAECn9RAAIUAAkJZCYlAAB9AwAUAAkJZCYlAAB9AwABLgAECgkJUQAhAN8kAA==.Tiltedtroll:BAABLgAECn8rAAISAAkJnhKrJwCtAQASAAkJnhKrJwCtAQAAAA==.Timedemon:BAABLgAECn8mAAIMAAkJcRshKQAjAgAMAAkJcRshKQAjAgAAAA==.Tinuveuil:BAAALgADCgYJBgAAAA==.',
To='Toiletseat:BAAALgAECgUJBQAAAA==.Tonjuras:BAABLgAECn8uAAMoAAkJ1SKCBADzAgAoAAkJLR+CBADzAgAiAAgJJB4PBABcAgAAAA==.Toona:BAACLgAFFH8FAAIMAAIJ5AnXiABsAAAMAAIJ5AnXiABsAAAuAAQKfxwAAgwACQn7GgYcAKoCAAwACQn7GgYcAKoCAAEuAAUUBAkJABkARRYA.Torogrande:BAAALgADCgkJKgABLgAECgUJBQAGAAAAAA==.Touchmyting:BAAALgAECgEJAwAAAA==.Toutii:BAAALgAECgUJBgABLgAECggJFQAaAI4fAA==.',
Tr='Trappybear:BAAALgAFFAEJAQABLgAFFAUJDQAhAHoQAA==.Trappydh:BAABLgAFFH8JAAIUAAQJbRC7BwDXAAAUAAQJbRC7BwDXAAABLgAFFAUJDQAhAHoQAA==.Trappydk:BAACLgAFFH8NAAIhAAUJehDFIADgAAAhAAUJehDFIADgAAAuAAQKfxcAAiEACAnPGpoUAMkBACEACAnPGpoUAMkBAAAA.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8sAAMfAAgJsSStCwAdAwAfAAgJsSStCwAdAwAkAAEJAADgIQBqAAAAAA==.',
Ty='Tyraxus:BAAALgADCgkJEAAAAA==.Tyronne:BAAALgAECgcJBwAAAA==.',
['Tý']='Týr:BAAALgADCgYJDAAAAA==.',
Ul='Ultraball:BAAALgAECggJDwAAAA==.',
Un='Unagi:BAABLgAECn8sAAICAAkJfg6EFwDmAQACAAkJfg6EFwDmAQAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAABLgAECn8YAAIPAAgJOAi5nQA8AQAPAAgJOAi5nQA8AQAAAA==.Vaesir:BAAALgADCgcJDQAAAA==.Varleara:BAABLgAECn8gAAMMAAgJziFEEwDmAgAMAAgJziFEEwDmAgAUAAEJKQeHLQAqAAAAAA==.',
Ve='Vehlahi:BAAALgAECgMJAwAAAA==.Venenn:BAAALgADCgEJAgAAAA==.Venev:BAAALgAECgYJEAAAAA==.Ventana:BAABLgAECn9CAAIXAAkJ+yI9AQAwAwAXAAkJ+yI9AQAwAwAAAA==.Verdilac:BAABLgAECn81AAIKAAkJexyKQgD+AQAKAAkJexyKQgD+AQABLgAFFAQJFAAmAMshAA==.',
Vi='Vinceglortho:BAAALgAECgYJEQAAAA==.Vindicator:BAABLgAECn8fAAIKAAkJSB1gIACFAgAKAAkJSB1gIACFAgAAAA==.Violetnoir:BAAALgAECgQJBAABLgAECgcJGgAfANsIAA==.Visiroth:BAABLgAECn8kAAMZAAkJcw5pZgCYAQAZAAkJJAtpZgCYAQAhAAgJHQusJAArAQAAAA==.',
Vy='Vyyral:BAAALgAECgUJBQABLgAECgkJIgAOAL8fAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAFFAQJFAAPAD4HAA==.Wallydk:BAABLgAECn8xAAIZAAkJTBsoHQCXAgAZAAkJTBsoHQCXAgAAAA==.Wanji:BAABLgAECn8rAAIZAAkJCwvpZQCZAQAZAAkJCwvpZQCZAQAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Wenesday:BAAALgADCgcJGQAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Widginatrix:BAABLgAECn8ZAAIdAAgJwA1+MQBTAQAdAAgJwA1+MQBTAQAAAA==.Willkain:BAAALgAECgMJAwAAAA==.',
Wo='Woah:BAAALgAECgMJAwABLgAFFAIJBwAYAGUiAA==.Woons:BAAALgAECgMJCAAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Wy='Wytewytch:BAAALgADCgQJBAAAAA==.',
Xa='Xaharst:BAAALgADCgYJBgAAAA==.Xaya:BAABLgAECn8aAAMfAAcJ2whGnQAEAQAfAAcJ2whGnQAEAQAeAAQJ6AJJUQB6AAAAAA==.',
Xe='Xenophorge:BAAALgAECgkJCwAAAA==.Xeralvezyn:BAAALgAECgIJAgAAAA==.',
Xi='Xiva:BAABLgAECn8zAAIoAAgJ7BJJHACxAQAoAAgJ7BJJHACxAQAAAA==.',
Xo='Xovace:BAABLgAECn8ZAAMlAAgJfgvtKAAxAQAlAAgJTwvtKAAxAQAMAAIJ8QbnBQFBAAAAAA==.',
Xt='Xtayse:BAABLgAECn8rAAIEAAkJuCAuAQD6AgAEAAkJuCAuAQD6AgAAAA==.Xtaysì:BAAALgAECgEJAQAAAA==.',
Ya='Yagorbomb:BAAALgAECgEJAwAAAA==.Yamyam:BAABLgAECn8VAAIdAAkJsg/HKQCyAQAdAAkJsg/HKQCyAQAAAA==.',
Yi='Yirya:BAAALgAECgQJBgAAAA==.',
Yo='Yoruechi:BAACLgAFFH8VAAIOAAQJ3iBLBwB8AQAOAAQJ3iBLBwB8AQAuAAQKfysAAg4ACAkoI0sFALYCAA4ACAkoI0sFALYCAAAA.',
Yu='Yuridia:BAAALgADCgEJAQAAAA==.',
['Yú']='Yúmyúm:BAABLgAECn8lAAIKAAkJWBcoSADsAQAKAAkJWBcoSADsAQAAAA==.',
Za='Zahel:BAABLgAECn8uAAIKAAkJlB52GACvAgAKAAkJlB52GACvAgAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECgkJLgAKAJQeAA==.Zalark:BAAALgADCgUJCgABLgAECgkJNQAJAJwUAA==.Zangai:BAAALgAECggJCAABLgAECggJGQATAHQLAA==.Zavier:BAAALgAECgQJBAABLgAECgYJBwAGAAAAAA==.',
Ze='Zeneri:BAABLgAECn84AAMnAAkJhRAcKwDRAQAnAAkJhRAcKwDRAQAWAAkJyRCTHADHAQAAAA==.',
Zo='Zobi:BAABLgAECn8UAAIMAAUJohEinQDlAAAMAAUJohEinQDlAAAAAA==.Zodius:BAAALgADCgEJAQAAAA==.Zomboo:BAAALgAFFAEJAQAAAA==.',
Zu='Zugzugzug:BAAALgADCgMJBgAAAA==.Zuhali:BAAALgADCgQJBAAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAFFAQJDAAVANIQAA==.',
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
