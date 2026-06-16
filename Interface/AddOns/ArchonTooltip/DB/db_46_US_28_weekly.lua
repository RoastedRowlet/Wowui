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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Evoker-Augmentation','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Protection','Priest-Holy','DeathKnight-Blood','Druid-Restoration','Rogue-Subtlety','DemonHunter-Devourer','Monk-Brewmaster','Druid-Balance','Priest-Discipline','Druid-Guardian','Warrior-Protection','Warrior-Arms','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','DemonHunter-Havoc','Evoker-Preservation','Druid-Feral','Monk-Mistweaver','DemonHunter-Vengeance','Priest-Shadow','Evoker-Devastation','Warlock-Affliction','Rogue-Assassination','Shaman-Enhancement','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abaddón:BAAALgAECgEJAQABLgAECggJHwABALwiAA==.Abfuscatedd:BAABLgAECn8iAAMCAAkJShPjQQDVAQACAAkJShPjQQDVAQADAAEJAAARgAATAAAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJFgAEAPoYAA==.Acidrain:BAABLgAECn85AAIFAAkJMyHHBwDdAgAFAAkJMyHHBwDdAgAAAA==.Acmiax:BAABLgAECn8kAAMGAAkJkhWGOgAXAgAGAAkJkhWGOgAXAgABAAUJugvkVADhAAAAAA==.',
Ad='Adar:BAAALgAECgQJBwAAAA==.',
Ae='Aep:BAABLgAECn8ZAAMHAAgJ+hJ+EwBAAQAHAAYJRRR+EwBAAQAIAAcJ/gwnlQA6AQABLgAECgMJAwAJAAAAAA==.',
Ah='Ahkari:BAAALgAECgEJAQABLgAFFAMJBgAKAJAXAA==.Ahrmanhamma:BAACLgAFFH8NAAIGAAQJUiHKHQCJAQAGAAQJUiHKHQCJAQAuAAQKfxoAAgYACQkvInMSANICAAYACQkvInMSANICAAAA.Ahu:BAABLgAECn8nAAMEAAgJsRcuMADwAQAEAAgJsRcuMADwAQALAAMJZAQjcwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgQJBQAAAA==.Airotciv:BAAALgAECgEJAQAAAA==.',
Al='Al:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgQJEgAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAACLgAFFH8OAAIEAAUJTgR1VQDzAAAEAAUJTgR1VQDzAAAuAAQKf0QAAwQACQm7EbE8AOkBAAQACQl7EbE8AOkBAAsACAmfDB41AJUBAAAA.Alerus:BAAALgAECgEJAQAAAA==.Alexander:BAABLgAECn8eAAIMAAkJixrzJgDXAgAMAAkJixrzJgDXAgAAAA==.Alexijones:BAABLgAECn8cAAINAAkJJQ9wGgDLAQANAAkJJQ9wGgDLAQAAAA==.Allaria:BAAALgAECgcJCgAAAA==.',
Am='Ambassador:BAABLgAECn8eAAIOAAkJlBcWDAD/AQAOAAkJlBcWDAD/AQAAAA==.Amoondai:BAACLgAFFH8hAAIPAAUJ3R/4BwDIAQAPAAUJ3R/4BwDIAQAuAAQKf0UAAg8ACQn2JJIBAKEDAA8ACQn2JJIBAKEDAAAA.',
An='Analytics:BAAALgADCgYJBgAAAA==.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn8/AAMQAAkJUiLQBADiAgAQAAkJUiLQBADiAgAIAAYJ7wNo0gDcAAAAAA==.Apolyon:BAABLgAECn8mAAIRAAkJLSE2CQAkAwARAAkJLSE2CQAkAwAAAA==.',
Ar='Araon:BAAALgAECgYJBgAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
As='Asheraah:BAAALgAECgQJBwAAAA==.',
At='Atroxz:BAAALgADCgcJCAAAAA==.',
Au='Aurén:BAAALgAECgYJCgAAAA==.',
Az='Azuree:BAAALgAFFAIJAwAAAA==.',
Ba='Bacstabath:BAABLgAECn8sAAISAAkJTx4XBgAvAwASAAkJTx4XBgAvAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAFFAQJDQAGAFIhAA==.Banshee:BAABLgAECn8eAAITAAkJ1B8tFACeAgATAAkJ1B8tFACeAgAAAA==.Baychan:BAABLgAECn8UAAIUAAcJNRsPGQDcAQAUAAcJNRsPGQDcAQAAAA==.',
Be='Becca:BAABLgAECn85AAIOAAkJkBYdDAD+AQAOAAkJkBYdDAD+AQAAAA==.Berries:BAAALgAECgEJAQAAAA==.',
Bi='Bigaraon:BAAALgADCgIJAgAAAA==.Bigdamaj:BAABLgAECn81AAMHAAkJEhmeBwAaAgAHAAkJcxeeBwAaAgAIAAkJBhTQUwDGAQAAAA==.Birbdormu:BAAALgAECgQJBQABLgAECgkJOAAVANIeAA==.',
Bl='Blakdemon:BAAALgADCgUJBQABLgAFFAMJBAAJAAAAAA==.Bloodiblind:BAAALgAECgQJCQAAAA==.Bloodios:BAABLgAECn80AAIQAAkJNh+ABwCgAgAQAAkJNh+ABwCgAgAAAA==.Blázé:BAAALgADCgEJAQAAAA==.',
Bo='Bobbardment:BAAALgAECgYJBgAAAA==.Bobin:BAAALgAECgMJBAABLgAECgkJHQAWAOwQAA==.Bobinforapl:BAABLgAECn8dAAIWAAkJ7BCmIgC3AQAWAAkJ7BCmIgC3AQAAAA==.Bokaya:BAAALgAECgcJAgAAAA==.Bombadil:BAABLgAECn9HAAIWAAkJhgeGKgB+AQAWAAkJhgeGKgB+AQAAAA==.',
Br='Bribage:BAABLgAECn84AAQVAAkJ0h6gDACLAgAVAAkJ/R2gDACLAgAXAAYJahquEgDBAQARAAIJqRtZiwCdAAAAAA==.Brolavski:BAAALgAECgEJAQABLgAECgcJEAAJAAAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgUJBwABLgAECgcJCgAJAAAAAA==.Budderwar:BAABLgAECn81AAQYAAkJDyZhAgAgAwAYAAkJDyZhAgAgAwAZAAcJkRtFEQDdAQAaAAMJvw4KhwCjAAAAAA==.Buggz:BAAALgAECgQJBgAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgIJBQAAAA==.',
['Bà']='Bàdmofos:BAAALgAECgQJBwAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.Calvis:BAAALgADCgcJDAAAAA==.',
Cb='Cbreezy:BAAALgAECgQJBgAAAA==.',
Ce='Celerydk:BAABLgAECn8WAAIIAAkJnxEJRgDuAQAIAAkJnxEJRgDuAQAAAA==.Celhealz:BAAALgAECgIJAgAAAA==.Celjska:BAAALgAECgUJBgAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chikñ:BAABLgAECn8aAAMFAAgJDg7kQABGAQAFAAYJjw/kQABGAQAbAAgJ7gmjXQA/AQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.Chuanthu:BAAALgAECgYJBgAAAA==.Chug:BAAALgAECgEJAQAAAA==.',
Ci='Cinderspella:BAAALgAECgIJAgAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8zAAIcAAkJdiUpAgBLAwAcAAkJdiUpAgBLAwAAAA==.',
Co='Cocoredbull:BAABLgAECn8dAAIXAAkJdw4CJAArAQAXAAkJdw4CJAArAQAAAA==.Corrail:BAAALgAECgYJDQAAAA==.Correin:BAABLgAECn8fAAIdAAkJbw+XIgBeAQAdAAkJbw+XIgBeAQAAAA==.',
Cr='Craszhin:BAABLgAECn8kAAIVAAkJqRD5HwDFAQAVAAkJqRD5HwDFAQAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn81AAIMAAkJIwx2bgCaAQAMAAkJIwx2bgCaAQAAAA==.',
Da='Dadeb:BAAALgAECgQJBQABLgAECgkJJAAGAJIVAA==.Daenarea:BAABLgAECn8qAAIeAAkJPxW1CABdAgAeAAkJPxW1CABdAgAAAA==.Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.Darksasuke:BAAALgADCgEJAQAAAA==.Darkwater:BAAALgADCgkJCQAAAA==.Dazinth:BAAALgAECgEJAQAAAA==.Dazînth:BAAALgAECgEJAgAAAA==.',
De='Deets:BAABLgAECn82AAIEAAkJSh+kEwCxAgAEAAkJSh+kEwCxAgAAAA==.Defoy:BAABLgAECn8WAAMLAAYJJhn1GADkAAALAAYJ4xb1GADkAAAEAAQJZxD95AB7AAAAAA==.Demona:BAABLgAECn8yAAMDAAkJDQ5RDAB2AQADAAkJDQ5RDAB2AQACAAYJWgMj3ACfAAAAAA==.Demonduckz:BAAALgAECgEJAgAAAA==.Demonicfates:BAABLgAECn8bAAIdAAgJWA6lJABOAQAdAAgJWA6lJABOAQAAAA==.Derffy:BAABLgAECn8tAAIfAAkJ8SHpAQAUAwAfAAkJ8SHpAQAUAwAAAA==.Descalabrada:BAAALgAECgYJDAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Di='Distol:BAAALgAECgUJCAAAAA==.',
Dm='Dmt:BAABLgAECn8iAAIgAAgJBh1vGQBHAgAgAAgJBh1vGQBHAgAAAA==.',
Do='Dotemdown:BAAALgAECgIJAgAAAA==.',
Dr='Dragonborn:BAAALgAECgEJAQAAAA==.Draiara:BAAALgAECgMJAwAAAA==.Dropdeadqtx:BAAALgAECgYJDQAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJHwABALwiAA==.Drpeppers:BAABLgAECn8sAAMRAAkJLAtBRgB0AQARAAkJLAtBRgB0AQAXAAEJAAAUPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathknight:BAAALgAECgEJAQABLgAECgcJAgAJAAAAAA==.Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthadin:BAAALgAECgQJBAAAAA==.Earthling:BAAALgAECgUJDQAAAA==.',
Ec='Eclair:BAABLgAECn81AAMbAAkJkhTXLQD7AQAbAAkJkhTXLQD7AQAFAAYJ5BjjNwBUAQAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgAECgQJBAABLgAECgkJLAASAE8eAA==.',
El='Eleysia:BAAALgAECgcJBwAAAA==.Elf:BAAALgAECgYJBwABLgAECgkJBAAJAAAAAA==.Elhayn:BAAALgAECgUJBwAAAA==.Elmore:BAAALgAECgQJBAAAAA==.Elmos:BAABLgAECn8tAAIcAAkJ7B4NCAD5AgAcAAkJ7B4NCAD5AgAAAA==.',
Eo='Eondel:BAAALgAECgEJAQAAAA==.',
Er='Erestadh:BAAALgAECgEJAgABLgAECgcJHAAMAFwMAA==.Eris:BAAALgADCgcJBwAAAA==.',
Eu='Eucalyptus:BAAALgAECgEJAgAAAA==.',
Ev='Evilchuckle:BAAALgADCgcJBwAAAA==.Evilmonkeymg:BAEALgAECgEJAQABLgAECgkJGQAFACceAA==.Evilmonkeysh:BAEBLgAECn8ZAAMFAAkJJx5eHAAvAgAFAAkJJx5eHAAvAgAbAAcJQQvdTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECgkJGQAFACceAA==.',
Ex='Exto:BAAALgAECgMJBAABLgAECgQJBAAJAAAAAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8xAAMdAAkJthayEQANAgAdAAkJthayEQANAgAhAAYJngo9GQDQAAAAAA==.',
Fa='Fatehunter:BAAALgADCggJCAAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgcJEgABLgAECggJDgAJAAAAAA==.Fenrísulfr:BAAALgAECgUJCAABLgAECggJDgAJAAAAAA==.Ferg:BAAALgAECgYJCQABLgAECgkJOQAMAE4jAA==.Fergis:BAABLgAECn85AAIMAAkJTiOCDAATAwAMAAkJTiOCDAATAwAAAA==.Fergle:BAAALgAECgYJEgAAAA==.Fetchme:BAAALgAECgQJBwAAAA==.Fetchyou:BAAALgADCggJDgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8dAAMQAAkJsBc8EgDoAQAQAAkJ+xY8EgDoAQAHAAcJ0RVDCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECggJEQAAAA==.',
Fr='Freecaster:BAAALgAECgMJAwAAAA==.Frostybeary:BAAALgAECgkJCQAAAA==.Frostymonk:BAABLgAECn8ZAAMgAAcJOQnqYQDpAAAgAAcJOQnqYQDpAAAcAAEJVAaqswAhAAAAAA==.Frozenwaffle:BAAALgAECgYJEgABLgAECgkJJgAiAJkhAA==.',
Fu='Furryben:BAAALgAECgMJAwAAAA==.',
['Fá']='Fállen:BAAALgADCgYJDQAAAA==.',
Ga='Galeste:BAAALgAECgUJCQAAAA==.',
Gh='Ghidorahh:BAAALgAFFAEJAQAAAA==.',
Gi='Gigem:BAABLgAECn8UAAIEAAcJWhyAQADcAQAEAAcJWhyAQADcAQAAAA==.Girlshoon:BAAALgAECgEJAQAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQeAAkJkASTIwBcAQAeAAkJkASTIwBcAQAKAAUJ9gP/SgCoAAAjAAEJlQGyKwAYAAAAAA==.Glarious:BAAALgAECgYJEAABLgAECgkJGwAeAJAEAA==.',
Go='Golakuron:BAAALgADCgUJBQAAAA==.Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgcJEAAAAA==.Gredan:BAAALgAECgYJCAAAAA==.Greenwaffle:BAABLgAECn8mAAMiAAkJmSGtDACGAgAiAAkJmSGtDACGAgAPAAYJwBTCNQBmAQAAAA==.Grôg:BAAALgAECgkJDQAAAA==.',
Gu='Guldaniel:BAAALgAECgUJBgABLgAECgkJJAAGAJIVAA==.Guthx:BAABLgAECn8eAAIRAAkJzBhnIgAzAgARAAkJzBhnIgAzAgAAAA==.',
Ha='Harutah:BAAALgAECgQJBAAAAA==.Hazeran:BAAALgAECgMJBQAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgAJAAAAAA==.',
Ho='Holymolii:BAABLgAECn8pAAIOAAkJhBaWDgDWAQAOAAkJhBaWDgDWAQAAAA==.Hotcoffee:BAAALgAECgYJDgAAAA==.',
Hu='Huntermaster:BAABLgAECn8bAAQNAAgJFRdTIACZAQANAAcJwBdTIACZAQALAAUJRxiERABDAQAEAAEJEBILJgE4AAABLgAECgkJNQAYAA8mAA==.',
Il='Ilulz:BAAALgADCgEJAQAAAA==.',
In='Incredabull:BAABLgAECn8dAAIYAAgJZhk2EQDTAQAYAAgJZhk2EQDTAQAAAA==.Intrepidz:BAAALgAECgEJAQABLgAECgkJJAAMABUYAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAABLgAECn8wAAIkAAkJ3xSACADbAQAkAAkJ3xSACADbAQAAAA==.Istayblunted:BAABLgAECn8eAAIOAAcJxx8QEADEAQAOAAcJxx8QEADEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDQAAAA==.',
Iw='Iwinwithhots:BAAALgAECgEJAgABLgAECgcJGAAGAIceAA==.',
Ja='Jacqualyn:BAAALgADCgMJAwAAAA==.',
Ji='Jiayerah:BAAALgAECgYJEAABLgAECggJLAAPAOcgAA==.Jinkuzo:BAABLgAECn8xAAIUAAkJIB9mCgCLAgAUAAkJIB9mCgCLAgAAAA==.Jinmu:BAABLgAECn80AAMSAAkJOxgEEgAUAgASAAkJOxgEEgAUAgAlAAEJJgueKAAwAAAAAA==.',
Ju='Juggie:BAABLgAECn8vAAIPAAkJrhO9GQD5AQAPAAkJrhO9GQD5AQAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8pAAIlAAkJigu7CwBxAQAlAAkJigu7CwBxAQAAAA==.',
Ka='Kagami:BAAALgAECgIJAgAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAABLgAECn8XAAMCAAkJgRpXKAA5AgACAAkJVhpXKAA5AgADAAEJFBvWawA8AAAAAA==.Kanè:BAAALgAECgEJAQAAAA==.',
Ke='Keliez:BAAALgAFFAEJAgABLgAFFAcJHwARAJINAA==.',
Kh='Khrodors:BAAALgADCgMJAwAAAA==.',
Ki='Kiannis:BAAALgADCgEJAQAAAA==.Kickerr:BAAALgAECggJEwABLgAECgkJJAAUANQaAA==.Kickrr:BAAALgAECggJCQABLgAECgkJJAAUANQaAA==.Kikyo:BAAALgAECgEJAgAAAA==.Kirrby:BAAALgADCgEJAQAAAA==.',
Kl='Klodar:BAAALgAECgQJBAAAAA==.Klum:BAAALgAECgYJCgAAAA==.',
Kr='Krazee:BAAALgAECgEJAQAAAA==.Krotas:BAAALgAECgMJAwAAAA==.Krunkle:BAAALgAECgIJAwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgAECggJDgAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgAECgYJEAAAAA==.Lendela:BAAALgAECgUJDAAAAA==.',
Li='Liljugg:BAAALgAECgYJDwAAAA==.',
Lm='Lmaddk:BAAALgAECgIJAgAAAA==.',
Lo='Logi:BAAALgAECgMJAwAAAA==.Lor:BAAALgAECgQJBgAAAA==.Lostmana:BAAALgAECgYJDAAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Lu='Lunablade:BAAALgAECgEJAQAAAA==.',
Ly='Lygor:BAABLgAECn82AAIEAAkJpxPOMwAJAgAEAAkJpxPOMwAJAgAAAA==.Lyrasong:BAAALgADCgIJAgAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJHwABALwiAA==.',
Ma='Maelle:BAAALgADCgYJBQAAAA==.Magnifico:BAAALgAECgUJBgAAAA==.Majellan:BAAALgAECgQJCQAAAA==.Makrub:BAAALgAECggJDQAAAA==.Malystryix:BAAALgAECgQJBAAAAA==.Mandigosa:BAAALgAECgMJBAAAAA==.Marist:BAAALgAECgEJAwAAAA==.Marrius:BAAALgAECgEJAgAAAA==.Marsawn:BAABLgAECn8gAAMiAAkJERiGFQAfAgAiAAkJERiGFQAfAgAPAAMJYBguSADAAAAAAA==.',
Mc='Mcpeepants:BAACLgAFFH8IAAImAAQJaxe9CAAsAQAmAAQJaxe9CAAsAQAuAAQKfxQAAiYACQnsHjcEAK8CACYACQnsHjcEAK8CAAEuAAUUBAkNAAYAUiEA.',
Me='Meqi:BAABLgAECn8hAAMMAAgJqx1iPwAcAgAMAAgJqx1iPwAcAgAnAAEJDBcVDgBGAAAAAA==.',
Mi='Mikàsa:BAABLgAECn8mAAMNAAkJSBDNFQD1AQANAAkJSBDNFQD1AQALAAYJXwmaTgAVAQAAAA==.Minand:BAAALgAECgYJEQAAAA==.Mindlessness:BAABLgAECn8yAAIaAAkJ5yPTBQABAwAaAAkJ5yPTBQABAwAAAA==.Mineralelf:BAABLgAECn86AAIEAAkJxwy8TgCxAQAEAAkJxwy8TgCxAQAAAA==.Minichaos:BAABLgAECn8xAAMDAAkJ4RjTAwBLAgADAAkJ4RjTAwBLAgACAAQJgAYJ2gCiAAAAAA==.Miriam:BAABLgAECn8eAAMoAAcJjAV0CgDZAAAoAAcJjAV0CgDZAAAMAAEJ9QIydwEiAAAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8fAAIBAAgJvCIpBwD5AgABAAgJvCIpBwD5AgAAAA==.',
Mo='Mojosavage:BAABLgAECn8YAAICAAcJ7gKf1QCpAAACAAcJ7gKf1QCpAAAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAgAAAA==.Moonblade:BAAALgAECgYJCwAAAA==.Mortshan:BAABLgAECn8bAAInAAkJRhY7AwD0AQAnAAkJRhY7AwD0AQAAAA==.Mournfull:BAAALgAECgEJBAAAAA==.',
My='Mysticalfox:BAAALgAECgQJBgAAAA==.',
Na='Nalfilas:BAAALgAECgUJDQAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgAECggJDQAAAA==.Nikru:BAABLgAFFH8FAAIOAAMJ5QbSEQBoAAAOAAMJ5QbSEQBoAAABLgAFFAcJHwARAJINAA==.Ninok:BAABLgAECn8sAAIGAAkJGxX/QwD4AQAGAAkJGxX/QwD4AQAAAA==.',
No='Nornee:BAABLgAECn8rAAIbAAgJ4xChSQCEAQAbAAgJ4xChSQCEAQAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8dAAIfAAgJRR1lCgAVAgAfAAgJRR1lCgAVAgAAAA==.',
['Nà']='Nàtureswrath:BAAALgAECgcJCwAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAABLgAECn8bAAMaAAgJ0xGHNAB3AQAaAAgJ0xGHNAB3AQAZAAEJ4wwwfAArAAAAAA==.',
Ol='Ollïee:BAAALgAECgYJBgAAAA==.',
Op='Oprawyndfury:BAAALgAECggJEAAAAA==.',
Or='Orceo:BAABLgAECn8rAAIEAAkJACTIBQAxAwAEAAkJACTIBQAxAwAAAA==.Orkreghar:BAAALgAECgIJBAAAAA==.',
Os='Osaro:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgAECgIJAgAAAA==.',
Ow='Ownlyshamz:BAAALgADCgMJAwABLgAFFAMJBgAeAAcMAA==.',
Ox='Oxcanor:BAAALgAECgUJCQAAAA==.',
Pa='Patches:BAAALgAECgUJBwABLgAECggJHwABALwiAA==.Patrick:BAAALgAECgQJBAAAAA==.',
Pe='Pepsipoutine:BAABLgAECn8WAAICAAYJmB+9TgDcAQACAAYJmB+9TgDcAQAAAA==.Petiterage:BAAALgADCggJCwAAAA==.',
Pi='Pindapind:BAAALgADCgMJBAABLgAECgkJNQAYAA8mAA==.Pindapinda:BAAALgAECggJDAABLgAECgkJNQAYAA8mAA==.',
Pl='Plaguexion:BAAALgADCgQJBgAAAA==.',
Po='Pompompower:BAABLgAECn8xAAIFAAkJGQiYPgA2AQAFAAkJGQiYPgA2AQAAAA==.Popple:BAABLgAECn8sAAIaAAkJ5xAkIgDgAQAaAAkJ5xAkIgDgAQAAAA==.Potential:BAACLgAFFH8MAAIUAAMJMB1zKwD3AAAUAAMJMB1zKwD3AAAuAAQKfyMAAhQACQkJGjoPAEUCABQACQkJGjoPAEUCAAAA.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgUJEAAAAA==.Puggsly:BAAALgAECgEJBAABLgAECgkJJAAGAJIVAA==.Pugsta:BAAALgAECgQJBwABLgAECggJEgAJAAAAAA==.Pulpfiction:BAABLgAECn8yAAMoAAYJfwWQDQDvAAAoAAYJRAWQDQDvAAAMAAUJjQQZCQGaAAAAAA==.',
Py='Pyrocaster:BAAALgAECgQJBQAAAA==.',
Qa='Qaccy:BAABLgAECn8SAAIiAAcJxQxQPwARAQAiAAcJxQxQPwARAQAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAABLgAECn8bAAIaAAgJzhkCKQC0AQAaAAgJzhkCKQC0AQAAAA==.',
Ra='Radaghast:BAAALgAECgEJAQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Raoul:BAAALgAECgMJBQAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Regret:BAAALgAFFAEJAgABLgAFFAgJJwAhAG4WAA==.Reishirome:BAAALgAECgEJAQAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8eAAIXAAgJPSIZAwDlAgAXAAgJPSIZAwDlAgAAAA==.',
Rh='Rhaellia:BAAALgAECgcJDQAAAA==.Rhogar:BAAALgAECgMJBAAAAA==.Rhoke:BAAALgAECgQJAwAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8fAAIVAAkJjgb7NwAwAQAVAAkJjgb7NwAwAQAAAA==.Romeoz:BAAALgADCgEJAQAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAABLgAECn8UAAIEAAYJ5xNfeQBIAQAEAAYJ5xNfeQBIAQAAAA==.',
Ru='Rumincoke:BAAALgADCgkJEwAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAABLgAECn8sAAMPAAgJ5yAgCgDCAgAPAAgJ5yAgCgDCAgAWAAEJ6R/jZgBdAAAAAA==.Saruma:BAAALgAECgQJAwAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwAJAAAAAA==.',
Sc='Scalygrob:BAAALgAECgkJEwAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8zAAIWAAkJ6Rd6DgCFAgAWAAkJ6Rd6DgCFAgAAAA==.Sellphie:BAAALgADCgcJCAAAAA==.',
Sh='Shadowhntr:BAAALgAECgYJCQAAAA==.Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shamehameha:BAAALgAFFAMJAwAAAA==.Shamonuu:BAAALgAECgEJAQAAAA==.Shavedussy:BAAALgADCgUJBQABLgAECgkJJAAGAJIVAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Siknes:BAAALgAECggJCAABLgAECgkJLAASAE8eAA==.Simmareth:BAAALgADCgcJBwAAAA==.Simpofmeerah:BAAALgAECgYJCAAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgYJDAAAAA==.',
Sl='Slargerita:BAAALgADCgcJBwAAAA==.',
Sm='Smallmoon:BAAALgAECgEJAQAAAA==.Smogcheck:BAACLgAFFH8TAAMeAAUJ/RTxGAD+AAAeAAQJSxHxGAD+AAAKAAMJDQa6WgBiAAAuAAQKfyEAAx4ACQkOE2gbAK0BAB4ACQkOE2gbAK0BACMAAQl9CNM+ADQAAAAA.',
Sn='Snackcake:BAABLgAECn8oAAIRAAkJvBoZEwCwAgARAAkJvBoZEwCwAgAAAA==.Snakeoil:BAABLgAECn8cAAMFAAkJyh79DwByAgAFAAkJyh79DwByAgAbAAEJCgIQ6QAiAAAAAA==.Snowsz:BAAALgAECgMJAwAAAA==.Snowws:BAABLgAECn8eAAITAAkJ9xq5IABOAgATAAkJ9xq5IABOAgAAAA==.',
So='Sortis:BAABLgAECn8kAAIMAAkJFRjeMwCjAgAMAAkJFRjeMwCjAgAAAA==.',
Sp='Spicebreff:BAABLgAFFH8GAAIeAAMJBwxZIQCTAAAeAAMJBwxZIQCTAAAAAA==.Spongerunner:BAABLgAECn8UAAICAAcJkxgnSgC7AQACAAcJkxgnSgC7AQAAAA==.Sprucetea:BAAALgADCgIJAwAAAA==.',
St='Steck:BAABLgAECn8/AAIEAAkJWhamLgAeAgAEAAkJWhamLgAeAgAAAA==.Strigo:BAABLgAFFH8OAAQNAAQJdRgpEwAuAQANAAQJCBgpEwAuAQAEAAEJtBy7IABfAAALAAEJnwy7KABKAAAAAA==.',
Su='Subway:BAAALgAECggJEAAAAA==.Sunbaby:BAABLgAECn8oAAIhAAgJnh56BgAqAgAhAAgJnh56BgAqAgAAAA==.',
['Sà']='Sàlís:BAAALgADCgkJDgAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8gAAIWAAkJdCBJBQD9AgAWAAkJdCBJBQD9AgAAAA==.Takhisoth:BAAALgADCgYJBgAAAA==.Talandaru:BAAALgAECgEJBAAAAA==.Talas:BAABLgAECn8zAAMEAAkJFh4WFQCmAgAEAAkJFh4WFQCmAgALAAUJswr3VwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Te='Temberle:BAAALgAECgQJBAABLgAECgkJOQADAMQQAA==.Temerald:BAAALgADCgkJCQAAAA==.Tevoran:BAAALgAECgYJEAAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thaelidari:BAAALgAECgkJDAAAAA==.Thieridan:BAAALgADCgIJBAAAAA==.Thrangus:BAAALgAECgIJAgABLgAFFAMJBQAIAOodAA==.Thrann:BAACLgAFFH8FAAMIAAMJ6h2wrADDAAAIAAIJiCCwrADDAAAHAAIJnBvuGgCgAAAuAAQKfyAAAwcACQnrIsUJAOUBAAgABwmpIp86AE0CAAcABQmHI8UJAOUBAAAA.Thunderdex:BAACLgAFFH8PAAMTAAcJpBZsHQC9AQATAAcJpBZsHQC9AQAdAAEJ6ANGLwAzAAAuAAQKfx8AAhMACQl+HjofAFYCABMACQl+HjofAFYCAAAA.',
Ti='Tirium:BAAALgAECgcJCAABLgAFFAMJBgAeAAcMAA==.',
To='Togglesmith:BAAALgAECgYJDAAAAA==.Togglestein:BAAALgAECgYJCwAAAA==.Togglethorp:BAAALgAECgUJBQAAAA==.Togi:BAAALgADCgcJDQAAAA==.',
Tr='Trinitum:BAAALgAECgcJCwABLgAFFAMJBgAeAAcMAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Ud='Udderduckie:BAAALgAECgEJAgAAAA==.',
Un='Unfolrion:BAAALgADCgIJBAAAAA==.Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJCwAAAA==.Ursoconha:BAABLgAFFH8FAAMRAAQJoQp0VQBrAAARAAMJfQV0VQBrAAAXAAEJqR0iMQBUAAABLgAFFAYJBgAMAIsYAA==.',
Va='Vaadboolin:BAAALgAECggJEgAAAA==.Vaevicta:BAAALgADCgYJBgAAAA==.Vallius:BAABLgAECn8dAAISAAkJ5BIPGQDOAQASAAkJ5BIPGQDOAQAAAA==.Vanargandr:BAAALgAECggJDgAAAA==.',
Ve='Verðandi:BAAALgAECgIJAgAAAA==.',
Vo='Volcano:BAABLgAECn8bAAICAAkJIxqdJwA8AgACAAkJIxqdJwA8AgAAAA==.Volvox:BAAALgADCgEJAQAAAA==.Vonslarge:BAAALgADCgkJCQAAAA==.',
Vy='Vyxenn:BAABLgAECn82AAMbAAkJ0xYhIQBEAgAbAAkJ0xYhIQBEAgAFAAUJTQtTVgDdAAAAAA==.',
Wa='Waffletoast:BAAALgADCgkJEQABLgAECgkJJgAiAJkhAA==.Wanders:BAABLgAECn8qAAMMAAkJIBqyJgB+AgAMAAkJIBqyJgB+AgAoAAYJLAmdCwAcAQAAAA==.Warlockk:BAAALgAECgUJBwAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Wc='Wckddreamer:BAAALgADCgEJAQAAAA==.',
Wu='Wurm:BAAALgAECgcJBwABLgAECgkJDQAJAAAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yejena:BAAALgAECgEJAQAAAA==.Yep:BAACLgAFFH8KAAIGAAQJVRgQMQBIAQAGAAQJVRgQMQBIAQAuAAQKfxsAAgYACQnwIyoKABQDAAYACQnwIyoKABQDAAAA.Yesenìa:BAAALgAECgYJBQAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zavia:BAAALgADCgYJDwAAAA==.Zazael:BAAALgAECgIJAgAAAA==.Zazreal:BAABLgAECn84AAQjAAkJgh30AgB4AgAjAAkJgh30AgB4AgAKAAMJ4Q9oSwClAAAeAAQJ7wJpLACCAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn85AAImAAkJ7gb/FQBcAQAmAAkJ7gb/FQBcAQAAAA==.Zillyanna:BAAALgAECggJEwAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zyper:BAAALgAECgYJDAAAAA==.Zywol:BAABLgAECn8mAAQVAAkJ5hh7FAAsAgAVAAkJ5hh7FAAsAgARAAMJlgbIpgB6AAAXAAEJjA8hdgAqAAAAAA==.',
['Ër']='Ëresta:BAABLgAECn8cAAIMAAcJXAxBngA7AQAMAAcJXAxBngA7AQAAAA==.',
['Ðe']='Ðesire:BAAALgAECgYJCwAAAA==.Ðespair:BAACLgAFFH8QAAIiAAQJ/SDfDgByAQAiAAQJ/SDfDgByAQAuAAQKfzQABBYACQklICQKAJYCABYABwk9ISQKAJYCACIACQltH+YLAJECAA8ABQmTGItAAOYAAAAA.',
['Ðr']='Ðream:BAAALgAECgYJCQAAAA==.',
['Ôr']='Ôrceo:BAAALgADCgYJBgAAAA==.',
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
