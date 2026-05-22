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

local lookup = {'Paladin-Holy','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Hunter-BeastMastery','Paladin-Retribution','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Paladin-Protection','Unknown-Unknown','Warrior-Fury','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Warrior-Protection','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Druid-Guardian','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Mage-Arcane','Warrior-Arms','Priest-Discipline','Priest-Holy','Shaman-Restoration','Priest-Shadow','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Preservation','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver','DeathKnight-Blood',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abysm:BAAALgADCgkJDwAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAQJBgABAFUTAA==.',
Ad='Adorabull:BAAALgAECgQJBgABLgAECgkJIQACAKsdAA==.',
Ae='Aemun:BAABLgAECn81AAMDAAkJihsSBwByAgADAAkJihsSBwByAgAEAAYJlAmwCAD2AAAAAA==.',
Ag='Aggfu:BAAALgADCgYJBgAAAA==.',
Ak='Akeeli:BAAALgADCgQJBAAAAA==.Akelita:BAABLgAECn8XAAIFAAYJrxhXGABZAQAFAAYJrxhXGABZAQAAAA==.',
Al='Alailea:BAABLgAECn8sAAIGAAkJ5xMkJgD5AQAGAAkJ5xMkJgD5AQAAAA==.Alwysafkable:BAAALgADCgQJBAAAAA==.',
Am='Amageadin:BAAALgADCgkJCQAAAA==.Amazadin:BAACLgAFFH8GAAIBAAQJVRNiFgAkAQABAAQJVRNiFgAkAQAuAAQKfxQAAwEACAmvGu8bADUCAAEACAmvGu8bADUCAAcAAQm4H5wAAVwAAAAA.Amazashock:BAAALgAECgUJDQABLgAFFAQJBgABAFUTAA==.',
An='Andiwin:BAAALgAFFAEJAQAAAA==.Andurthil:BAABLgAECn8gAAIIAAcJAQ6shgAwAQAIAAcJAQ6shgAwAQAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Archive:BAAALgAECgkJCwAAAA==.Artistic:BAABLgAECn8cAAIGAAgJeBlYJQD9AQAGAAgJeBlYJQD9AQAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8kAAMGAAgJUxfaMgDAAQAGAAgJUxfaMgDAAQAJAAYJTgfdTwAPAQAAAA==.',
Az='Azerith:BAAALgAECgYJCgAAAA==.',
Ba='Badmorda:BAAALgADCgEJAQAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8bAAIKAAgJnBjCLQBWAgAKAAgJnBjCLQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAABLgAECn8VAAMHAAYJfBQzhAAdAQAHAAYJfBQzhAAdAQALAAYJnQlzIwCmAAAAAA==.Bloodtemplar:BAABLgAECn8cAAIHAAcJuRYEVwB+AQAHAAcJuRYEVwB+AQAAAA==.',
Bo='Bombs:BAAALgAECgQJEAABLgAECgYJDQAMAAAAAA==.Bonesy:BAAALgAECgYJBgAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brutusdabull:BAAALgAECgYJBgAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAMAAAAAA==.Canan:BAAALgAECgMJAwAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8WAAINAAkJ7xlRIQBJAgANAAkJ7xlRIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgADCgEJAQAAAA==.',
Ce='Celum:BAAALgAECgYJEQAAAA==.Ceola:BAAALgAECgQJCAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAABLgAECn8bAAIOAAgJ1hZPCQDGAQAOAAgJ1hZPCQDGAQAAAA==.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8fAAQPAAYJshejCgBHAQAPAAYJshejCgBHAQADAAQJUgnOMwChAAAEAAMJ2wSREgB3AAAAAA==.Chaw:BAACLgAFFH8VAAMQAAUJ9iOjDQAzAQAQAAQJIyOjDQAzAQAGAAEJcCamIQBdAAAuAAQKfzIABBAACQnuJMkBAA4DABAACQntJMkBAA4DAAkABwnWHy0iABQCAAYABAk3I1BIAJEBAAAA.Chenkenichi:BAABLgAECn8ZAAMRAAkJuwYkJgAxAQARAAkJuwYkJgAxAQASAAUJKAKraACfAAAAAA==.Chergar:BAACLgAFFH8HAAITAAQJ7xetCgAoAQATAAQJ7xetCgAoAQAuAAQKfxwAAhMACAnmIUwFAOkCABMACAnmIUwFAOkCAAAA.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAgAAAA==.',
Ci='Cinny:BAABLgAECn85AAIGAAkJlRnfHABYAgAGAAkJlRnfHABYAgAAAA==.Cinnyrolls:BAABLgAECn8XAAMUAAgJ/xuOEgDxAQAUAAgJ/xuOEgDxAQAVAAQJtBBhhwDHAAAAAA==.Cityairlines:BAABLgAECn8nAAIWAAkJuRQiBgDPAQAWAAkJuRQiBgDPAQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Cm='Cmoneyy:BAAALgAECgQJBQAAAA==.',
Co='Cooldukenuke:BAACLgAFFH8KAAIBAAMJqRf4DwDaAAABAAMJqRf4DwDaAAAuAAQKfyEAAgEACQmjHDoTAHkCAAEACQmjHDoTAHkCAAAA.',
Cr='Creepychalk:BAAALgAECgUJDAAAAA==.Criticize:BAABLgAECn8fAAIHAAcJhw6rbQBKAQAHAAcJhw6rbQBKAQAAAA==.',
Cs='Csor:BAAALgAECgMJAwAAAA==.Csorb:BAABLgAECn8xAAMXAAkJ8SCfAgDMAgAXAAkJviCfAgDMAgAYAAEJySXaJQBuAAAAAA==.Csoren:BAAALgAECgEJAQAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8UAAIZAAUJTh//DgB9AQAZAAUJTh//DgB9AQAuAAQKfzMAAxkACQnjJUkBAGADABkACQnjJUkBAGADABoABQnaFG8iABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deathdogg:BAACLgAFFH8QAAIbAAQJ9hefNgD1AAAbAAQJ9hefNgD1AAAuAAQKfykAAhsACQlPIC0fAEsCABsACQlPIC0fAEsCAAAA.Dejavu:BAACLgAFFH8VAAISAAQJwxCBGwAQAQASAAQJwxCBGwAQAQAuAAQKfyYAAhIACAkgHZgaAC8CABIACAkgHZgaAC8CAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgAECgEJAQAAAA==.Deppthcharge:BAAALgAECgYJDAAAAA==.Desdemona:BAAALgAECgUJBQAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8ZAAIOAAkJQho+BQA/AgAOAAkJQho+BQA/AgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECgkJKAATABMmAA==.',
Du='Dunkhan:BAAALgAECgEJAQABLgAECgYJCwAMAAAAAA==.Duplexity:BAABLgAECn8oAAITAAkJEybbAABMAwATAAkJEybbAABMAwAAAA==.',
Dw='Dwalin:BAAALgAECgMJBwABLgAECgkJGQAOAEIaAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Ed='Edolah:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8RAAIHAAUJrx3YFwBfAQAHAAUJrx3YFwBfAQAuAAQKfzAAAgcACQkVJaQDADwDAAcACQkVJaQDADwDAAAA.',
El='Eloi:BAAALgAECggJEAABLgAECggJJQAVABUdAA==.',
Em='Emieretta:BAABLgAECn80AAIbAAkJ6hV2LgAAAgAbAAkJ6hV2LgAAAgAAAA==.',
Eq='Eqdk:BAABLgAECn8aAAIbAAkJ8RK/OQDVAQAbAAkJ8RK/OQDVAQAAAA==.',
Er='Erret:BAACLgAFFH8RAAIIAAUJxhfoNgBKAQAIAAUJxhfoNgBKAQAuAAQKfy8AAwgACQkPIwgJAAcDAAgACQkPIwgJAAcDABwAAQnKGeQNAEoAAAAA.',
Ez='Ezinder:BAAALgAECgQJBQAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faemos:BAAALgAECgkJBgAAAA==.Faience:BAABLgAECn8aAAIWAAgJYQPLFACyAAAWAAgJYQPLFACyAAAAAA==.Falorina:BAABLgAECn8lAAMFAAgJ9CFYBQCgAgAFAAgJ9CFYBQCgAgACAAEJAwXh6wAnAAAAAA==.Fathernature:BAABLgAECn8ZAAMUAAcJyxveKAC4AQAUAAcJyxveKAC4AQAYAAEJeQX8OAAlAAAAAA==.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn8kAAICAAkJWRtqHgAbAgACAAkJWRtqHgAbAgAAAA==.Felfaith:BAAALgADCgQJBAAAAA==.Fester:BAAALgADCgUJBQABLgAECgkJJgAKAJ0WAA==.',
Fi='Fightforbeer:BAAALgAECgEJAQAAAA==.Finnin:BAABLgAECn8jAAMNAAkJCSSVBADkAgANAAkJCSSVBADkAgAdAAEJ0gZ8SAAkAAAAAA==.',
Fo='Food:BAABLgAECn8mAAIGAAkJoRgrIQA/AgAGAAkJoRgrIQA/AgAAAA==.Formidabull:BAAALgAECgEJAQABLgAECgkJIQACAKsdAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Freidafondle:BAAALgAECgUJCAAAAA==.Frostbite:BAAALgAECgcJCAAAAA==.Frozenfaith:BAABLgAECn8mAAMeAAkJUwtRHwB4AQAeAAgJ1gtRHwB4AQAfAAMJMgQBUABPAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Furioushealz:BAABLgAECn8nAAIHAAkJpxlNJQApAgAHAAkJpxlNJQApAgAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Gh='Ghettomike:BAABLgAECn8nAAIbAAkJ/x0LIQBBAgAbAAkJ/x0LIQBBAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgEJAQAAAA==.Giranimo:BAABLgAECn8XAAIGAAcJUxP6SABvAQAGAAcJUxP6SABvAQAAAA==.',
Gl='Glabados:BAAALgAECgIJAwABLgAECgkJJwASADYiAA==.Glossy:BAACLgAFFH8bAAMDAAUJfiW/BAC0AQADAAUJfiW/BAC0AQAEAAMJ4hBtBwCgAAAuAAQKfzIABAMACQmEJp4AAGoDAAMACQmEJp4AAGoDAAQAAgmEIZsOAMIAAA8AAgkNHzAUALsAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAUJGwADAH4lAA==.Glossydh:BAAALgAECgYJBgABLgAFFAUJGwADAH4lAA==.Glossydk:BAAALgAECgQJBQABLgAFFAUJGwADAH4lAA==.Glossylock:BAAALgADCgcJDQABLgAFFAUJGwADAH4lAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAINAAkJkAtiIACgAQANAAkJkAtiIACgAQAAAA==.Greatclaw:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8NAAIHAAQJ/iFFDwCFAQAHAAQJ/iFFDwCFAQAuAAQKfysAAwcACAnaJWMJAEYDAAcACAnaJWMJAEYDAAsABQnzIG8PAHYBAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAAALgAECgYJEQAAAA==.',
Ha='Halîk:BAAALgAECgkJEwAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Harmshock:BAABLgAECn89AAIOAAkJgyQDAQAPAwAOAAkJgyQDAQAPAwAAAA==.Hathina:BAACLgAFFH8RAAINAAUJvCO+CAByAQANAAUJvCO+CAByAQAuAAQKfzMAAw0ACQnTJlIAAIIDAA0ACQnTJlIAAIIDAB0AAwmCHykeAP4AAAAA.',
He='Heket:BAABLgAECn8qAAIHAAgJlwe4hAAcAQAHAAgJlwe4hAAcAQAAAA==.Hektric:BAAALgAECgMJAwAAAA==.',
Hi='Highdra:BAAALgAECgQJBAAAAA==.Hill:BAABLgAECn8nAAIGAAkJhR/BFQBcAgAGAAkJhR/BFQBcAgAAAA==.Hive:BAABLgAECn8mAAINAAkJExSUGQDUAQANAAkJExSUGQDUAQAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8jAAIgAAgJdyMTBQAcAwAgAAgJdyMTBQAcAwABLgAECgcJIQAVAOgkAA==.',
Hu='Husentar:BAABLgAECn8wAAIIAAkJZR4zDgDXAgAIAAkJZR4zDgDXAgAAAA==.Huuhablo:BAABLgAECn84AAICAAkJMRuLGQA7AgACAAkJMRuLGQA7AgAAAA==.',
Ic='Icaron:BAAALgAECgcJCQAAAA==.',
Ig='Igothots:BAAALgAECgMJAwAAAA==.',
Il='Illuminottey:BAAALgAECggJDwAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAQJCwAMAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAQJCwAMAAAAAA==.Insatiabull:BAABLgAECn8hAAMCAAkJqx2+EgDqAgACAAgJ7x6+EgDqAgAFAAEJyxTXRABDAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Is='Ishaa:BAAALgAECgYJBgAAAA==.',
Ja='Jacksof:BAABLgAECn8UAAMhAAYJ7gVaQwCqAAAhAAYJ7gVaQwCqAAAeAAQJOQT2SgBaAAAAAA==.Jackstands:BAABLgAECn86AAMgAAkJTSAmBwD1AgAgAAkJTSAmBwD1AgAOAAgJgAUPEgAdAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJwASADYiAA==.January:BAAALgAECgYJBgABLgAFFAQJDQAGAFIUAA==.Jasmyne:BAAALgADCgYJBgAAAA==.',
Je='Jeromy:BAAALgAECgEJAQAAAA==.Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAIiAAgJyRrwBQA8AgAiAAgJyRrwBQA8AgAAAA==.Jinksy:BAAALgAECgUJDQAAAA==.',
Jm='Jme:BAAALgAECgcJCQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Jubag:BAAALgADCgIJAgAAAA==.Jumpercables:BAAALgAECgEJBAAAAA==.Junn:BAABLgAECn8nAAIjAAkJmBNGGQDGAQAjAAkJmBNGGQDGAQAAAA==.',
Ka='Kahayman:BAABLgAECn8oAAIIAAgJtRtBMQATAgAIAAgJtRtBMQATAgAAAA==.Karellen:BAAALgAECgYJBgAAAA==.',
Kh='Khathani:BAAALgAECgQJBgAAAA==.',
Ki='Kieran:BAAALgADCgcJBwAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAABLgAECn8gAAIHAAgJXRBOVgCAAQAHAAgJXRBOVgCAAQAAAA==.Koriggan:BAABLgAECn8iAAQQAAgJ5w+YFQCwAQAQAAgJ5w+YFQCwAQAGAAYJKhB6VQBoAQAJAAEJ6QBlmwAUAAAAAA==.',
Kr='Krea:BAABLgAECn8iAAILAAgJkiIjAwCfAgALAAgJkiIjAwCfAgAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Krystagosa:BAABLgAECn8uAAQkAAkJ+Q5kCwDZAQAkAAkJ+Q5kCwDZAQAZAAYJJg8xNwD9AAAaAAMJVArJEgCVAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8mAAIKAAkJnRY8KAD/AQAKAAkJnRY8KAD/AQAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
La='Lang:BAABLgAECn8wAAIiAAkJIBxuAgCTAgAiAAkJIBxuAgCTAgAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Li='Lightsfaith:BAAALgADCgYJBgABLgAECgkJJgAeAFMLAA==.',
Lo='Loopey:BAAALgAECgcJEAABLgAFFAQJFQASAMMQAA==.Lorethil:BAAALgAECgIJAgAAAA==.',
Lu='Luceriss:BAABLgAECn8bAAIDAAkJGw5fEwC0AQADAAkJGw5fEwC0AQAAAA==.Luminous:BAAALgADCgcJCAABLgAECgkJJgAKAJ0WAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAUJEQAKAHwNAA==.Magicboi:BAABLgAECn8WAAIIAAYJsw8LjwAhAQAIAAYJsw8LjwAhAQAAAA==.Magwar:BAACLgAFFH8OAAINAAUJVhkgDgBLAQANAAUJVhkgDgBLAQAuAAQKfzEAAg0ACQlWIacDAPwCAA0ACQlWIacDAPwCAAAA.Maike:BAABLgAECn8cAAIPAAcJ4RExCQBpAQAPAAcJ4RExCQBpAQAAAA==.Marcelyne:BAAALgAECgMJAwABLgAECggJHwAKAC8VAA==.Marothius:BAACLgAFFH8RAAQKAAUJfA2+KADTAAAKAAQJZQy+KADTAAAlAAEJvxAUFABWAAAmAAEJ3AKOFQA7AAAuAAQKfzMABAoACQlgHl8XAGACAAoACQlQHF8XAGACACUABgmLHBAXAJEBACYAAgnLGuATALwAAAAA.Martaug:BAABLgAECn8hAAIgAAkJJx9HCgDHAgAgAAkJJx9HCgDHAgAAAA==.Marune:BAAALgAECgkJDwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn8uAAMNAAkJGyEiBQDWAgANAAkJGyEiBQDWAgAdAAYJ6xMBGwApAQAAAA==.Mawg:BAAALgAECgYJBwAAAA==.Mayfair:BAABLgAECn8UAAMgAAYJ4hNDPABeAQAgAAYJ4hNDPABeAQAjAAYJuQZ4SAC7AAAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBQAAAA==.',
Me='Melee:BAACLgAFFH8nAAIHAAgJDSQkAAD2AgAHAAgJDSQkAAD2AgAuAAQKfxQAAgcACQmZJj0CALoDAAcACQmZJj0CALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgYJCgAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Minimee:BAAALgAECgEJAQAAAA==.Miquella:BAAALgAECgYJCwAAAA==.Misohotramen:BAACLgAFFH8OAAICAAQJiRr/HQBRAQACAAQJiRr/HQBRAQAuAAQKfyQAAgIACQnQILUzACsCAAIACQnQILUzACsCAAAA.',
Mo='Moist:BAABLgAECn8wAAIXAAkJqCI1AQAZAwAXAAkJqCI1AQAZAwAAAA==.Monkstrosity:BAAALgAECgMJAwAAAA==.Moofish:BAAALgAECgUJAwAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAAALgAECggJEwAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn8wAAMKAAkJRxv5HQA1AgAKAAgJRxv5HQA1AgAlAAIJMBi0UQB5AAAAAA==.Motgustus:BAAALgAECgYJCAAAAA==.',
Mu='Muirfire:BAAALgADCgYJBgAAAA==.Murrda:BAABLgAECn8sAAMKAAkJxCAgCADpAgAKAAkJxCAgCADpAgAmAAEJnwW8KQAkAAAAAA==.Musk:BAAALgAECgIJAwABLgAECggJIwAIAOATAA==.Muskrattsam:BAABLgAECn8jAAIIAAgJ4BNYSQC+AQAIAAgJ4BNYSQC+AQAAAA==.',
My='Myravia:BAABLgAECn8WAAIIAAcJrxAwkQCxAQAIAAcJrxAwkQCxAQAAAA==.Myrokos:BAABLgAECn86AAIHAAkJFiFACwDZAgAHAAkJFiFACwDZAgAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn86AAIXAAkJvBCHDgCPAQAXAAkJvBCHDgCPAQAAAA==.Nails:BAAALgAECgIJAgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nezar:BAAALgAFFAEJAwABLgAFFAEJBAAMAAAAAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECgkJEwAMAAAAAA==.Niddy:BAABLgAECn8rAAIIAAgJ4xRuRQDKAQAIAAgJ4xRuRQDKAQAAAA==.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8aAAMhAAUJ4CE/CQBvAQAhAAUJ4CE/CQBvAQAeAAQJzAKWHADuAAAuAAQKfzEABCEACQm6JAwCAC8DACEACQm6JAwCAC8DAB8ABgnIFcYuAIgBAB4AAgnNBOJZAC4AAAAA.Noel:BAAALgAECgYJEgAAAA==.Nomsayin:BAACLgAFFH8GAAIKAAMJHQtPXQC/AAAKAAMJHQtPXQC/AAAuAAQKfzAAAgoACQkuGTYsAOsBAAoACQkuGTYsAOsBAAAA.Nonospot:BAABLgAECn8kAAMhAAgJxBZJFQDSAQAhAAgJxBZJFQDSAQAeAAEJvANJWgAuAAAAAA==.Noobuddy:BAAALgAECgUJCgABLgAFFAUJGgAhAOAhAA==.Noraboo:BAABLgAECn8jAAMcAAgJQRqjBAD7AQAcAAYJbxyjBAD7AQAIAAgJmRgfQwDSAQAAAA==.Norannestra:BAAALgAECgYJDQAAAA==.Novalicious:BAAALgADCgIJAgAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8cAAMKAAkJpBR3MADZAQAKAAgJpBR3MADZAQAlAAEJAAD5cwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8YAAMDAAkJ8BlNGQA6AgADAAkJUhhNGQA6AgAPAAIJ5xdoFgCSAAAAAA==.Nystra:BAAALgAECggJBwAAAA==.Nyzstra:BAABLgAECn8wAAIIAAkJXiI+DQDfAgAIAAkJXiI+DQDfAgAAAA==.',
['Nê']='Nêwt:BAACLgAFFH8GAAIIAAIJmgg0eQCaAAAIAAIJmgg0eQCaAAAuAAQKfy8AAggACQmTGCcnAD4CAAgACQmTGCcnAD4CAAAA.',
['Nì']='Nìrvana:BAAALgAECgQJCwAAAA==.',
On='Onlybeams:BAABLgAECn8fAAICAAkJQBtyFQBYAgACAAkJQBtyFQBYAgAAAA==.',
Or='Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAECgYJBgABLgAECgkJKAATABMmAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Partyhard:BAAALgADCgYJCwAAAA==.Pastrydragon:BAACLgAFFH8KAAMZAAMJxBfhEAD7AAAZAAMJxBfhEAD7AAAaAAEJJxlLCABXAAAuAAQKfy4AAxkACAmrINUKAMgCABkACAmSHtUKAMgCABoABglYI5ULACICAAAA.',
Pi='Pistachio:BAABLgAECn8YAAIFAAYJOA4dIgACAQAFAAYJOA4dIgACAQAAAA==.Pitviper:BAABLgAECn8mAAIPAAkJ4x72AQCRAgAPAAkJ4x72AQCRAgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJCAAAAA==.Pogaca:BAAALgAECgYJCQABLgAECggJFwAUAP8bAA==.Portabull:BAAALgADCgcJBwABLgAECgkJIQACAKsdAA==.Possess:BAABLgAECn8lAAIKAAcJ8RzbNADHAQAKAAcJ8RzbNADHAQAAAA==.Pownora:BAABLgAECn8bAAMRAAcJdxsxFQC+AQARAAcJdxsxFQC+AQAnAAIJ/Q1XbwAvAAABLgAECggJIwAcAEEaAA==.',
Ps='Psarchasm:BAABLgAECn8kAAINAAkJGQ2iHwClAQANAAkJGQ2iHwClAQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn8wAAIGAAkJ5CNSAwAsAwAGAAkJ5CNSAwAsAwAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8nAAISAAkJNiLlAgD8AgASAAkJNiLlAgD8AgAAAA==.Rayyzer:BAABLgAECn8cAAIDAAkJqCEXBgCJAgADAAkJqCEXBgCJAgAAAA==.',
Re='Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAABLgAECn8YAAMXAAgJhBriBwARAgAXAAgJhBriBwARAgAVAAEJFiOEtQBaAAAAAA==.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn83AAMfAAkJAxhbCwBmAgAfAAkJAxhbCwBmAgAeAAgJ0w7HGwC4AQAAAA==.Rot:BAABLgAECn8nAAIoAAkJCSZGAQDQAgAoAAkJCSZGAQDQAgAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAUJEQANALwjAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAAALgAECggJEAABLgAECggJKAAIALUbAA==.Saphlocket:BAAALgAECgQJDAAAAA==.Sathin:BAABLgAECn8oAAICAAgJVgkyXwAcAQACAAgJVgkyXwAcAQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAUJEQAKAHwNAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.Sefekat:BAAALgAECgEJAQABLgAECgkJHwACAEAbAA==.September:BAAALgAECgIJAgABLgAFFAQJDQAGAFIUAA==.Sevatar:BAABLgAECn8VAAIFAAgJ7wrpGgBAAQAFAAgJ7wrpGgBAAQAAAA==.',
Sf='Sfcwarner:BAAALgAECgEJAQAAAA==.',
Sh='Shampooyou:BAABLgAECn8bAAIgAAcJdQUaWQDrAAAgAAcJdQUaWQDrAAAAAA==.Shockakhan:BAAALgAECggJDQAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECgkJKAATABMmAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.Sinistra:BAAALgAECgEJAQAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8kAAIIAAkJuhhmJQBHAgAIAAkJuhhmJQBHAgABLgAFFAMJAwAMAAAAAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Splashmountn:BAEALgAECgYJDgAAAA==.Spring:BAACLgAFFH8NAAMGAAQJUhTLHgA8AQAGAAQJUhTLHgA8AQAJAAEJpAAJLgA2AAAuAAQKfyUAAwYACQlfHW4aADsCAAYACQkjHW4aADsCAAkABgnTC/ZMAB0BAAAA.',
Ss='Ssgwarner:BAAALgAECgEJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQAAAA==.Sting:BAAALgAECgYJBgAAAA==.Stormclaw:BAABLgAECn8lAAIVAAgJFR3eEwBoAgAVAAgJFR3eEwBoAgAAAA==.Stormcrash:BAAALgADCgYJBgABLgAECgkJJgAKAJ0WAA==.Stregoica:BAAALgADCgcJDgABLgAFFAUJEQAKAHwNAA==.',
Su='Suhfering:BAAALgADCgYJBgABLgAECgkJHwACAEAbAA==.Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Ta='Tallron:BAACLgAFFH8YAAIVAAUJeRujDQCeAQAVAAUJeRujDQCeAQAuAAQKfy4AAxUACQmaJLcJAPcCABUACQmaJLcJAPcCABQABQmPFbUuAA0BAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAUJGAAVAHkbAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tamedsloth:BAAALgAECgQJBAABLgAECgQJBAAMAAAAAA==.Tandraella:BAAALgAECgQJBAABLgAFFAQJBgABAFUTAA==.Taroquin:BAAALgADCgkJCgAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgAECgcJDAAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theskabandit:BAAALgADCgcJEQAAAA==.Thrustruggle:BAAALgADCgEJAQAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.',
To='Tojikitoushi:BAABLgAECn8pAAIOAAkJzh9mAgCzAgAOAAkJzh9mAgCzAgAAAA==.Tombs:BAAALgAECgYJCAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Trid:BAAALgAECggJCAAAAA==.Tristex:BAAALgAECgQJBAABLgAECggJFwAUAP8bAA==.',
Tu='Tuha:BAAALgAFFAIJAgAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrolia:BAAALgAECgMJAwAAAA==.',
Um='Umibozu:BAAALgAECgIJAgAAAA==.',
Va='Valliya:BAAALgAECgMJAwAAAA==.',
Ve='Velratha:BAABLgAECn8UAAImAAgJtQ80DAB2AQAmAAgJtQ80DAB2AQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMhAAgJDBg4HACQAQAhAAcJRhs4HACQAQAfAAIJeBjAUwBCAAAAAA==.',
Vi='Vicsta:BAAALgAECgYJBwAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8nAAInAAkJNRZiEgAhAgAnAAkJNRZiEgAhAgAAAA==.Volq:BAAALgAECgEJAQAAAA==.Voltarix:BAAALgAECgQJBAAAAA==.Voodoopriest:BAABLgAECn8YAAIKAAcJMwRDpAAQAQAKAAcJMwRDpAAQAQAAAA==.Voyria:BAABLgAECn8nAAQVAAgJ7wTfWADqAAAVAAgJ7wTfWADqAAAUAAQJVwTlWABYAAAYAAIJwQL3MgAzAAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskaar:BAAALgADCgEJAQAAAA==.Vyskar:BAAALgAECgMJAwAAAA==.',
Wa='Warm:BAACLgAFFH8TAAIRAAUJ8hyBBwBVAQARAAUJ8hyBBwBVAQAuAAQKfycAAhEACQkTImsIAPMCABEACQkTImsIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAAAAA==.Weeziveli:BAAALgAECgQJCAAAAA==.Weledish:BAACLgAFFH8NAAIIAAMJxBbTUQACAQAIAAMJxBbTUQACAQAuAAQKfyoAAggACQnoGokpADMCAAgACQnoGokpADMCAAAA.',
Wi='Wienercat:BAABLgAECn8hAAIVAAcJ6CTGCQDjAgAVAAcJ6CTGCQDjAgAAAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Xt='Xtreeme:BAAALgAECgIJAgAAAA==.',
Ya='Yael:BAABLgAECn8pAAICAAkJNx5VEgBwAgACAAkJNx5VEgBwAgAAAA==.',
Za='Zarewien:BAABLgAECn8nAAIfAAkJ6ggtIwBjAQAfAAkJ6ggtIwBjAQAAAA==.',
Zi='Ziddles:BAAALgAECgYJEAAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAgABLgAECggJNwASAFcfAA==.Zomgmonk:BAABLgAECn83AAISAAgJVx+NCgBSAgASAAgJVx+NCgBSAgAAAA==.Zomgzilla:BAAALgAECggJAQABLgAECggJNwASAFcfAA==.',
Zu='Zuraq:BAAALgAECgEJAwAAAA==.Zurisdad:BAABLgAECn8uAAISAAkJWRsCCQBtAgASAAkJWRsCCQBtAgABLgAFFAUJEQAIAMYXAA==.Zurishmi:BAACLgAFFH8cAAIgAAUJ/h75CwCZAQAgAAUJ/h75CwCZAQAuAAQKfzMAAiAACQk6JoYAAMQDACAACQk6JoYAAMQDAAAA.',
['Äm']='Ämäteräsu:BAAALgAECgcJDAAAAA==.',
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
