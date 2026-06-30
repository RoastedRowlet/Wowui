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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Evoker-Augmentation','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Protection','Priest-Holy','DeathKnight-Blood','Druid-Restoration','Rogue-Subtlety','DemonHunter-Devourer','Monk-Brewmaster','Shaman-Enhancement','Druid-Balance','Priest-Discipline','Druid-Guardian','Warrior-Protection','Warrior-Arms','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','DemonHunter-Havoc','Evoker-Preservation','Druid-Feral','Monk-Mistweaver','DemonHunter-Vengeance','Priest-Shadow','Evoker-Devastation','Warlock-Affliction','Rogue-Assassination','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abaddón:BAAALgAECgEJAQABLgAECggJHwABALwiAA==.Abfuscatedd:BAABLgAECn8iAAMCAAkJShN1QgDUAQACAAkJShN1QgDUAQADAAEJAAARgAATAAAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJFgAEAPoYAA==.Acidrain:BAABLgAECn85AAIFAAkJMyEJCADcAgAFAAkJMyEJCADcAgAAAA==.Acmiax:BAABLgAECn8kAAMGAAkJkhVEPAATAgAGAAkJkhVEPAATAgABAAUJugsdVgDfAAAAAA==.',
Ad='Adar:BAAALgAECgQJBwAAAA==.',
Ae='Aegos:BAAALgADCgUJBQAAAA==.Aep:BAABLgAECn8ZAAMHAAgJ+hLyEwA+AQAHAAYJRRTyEwA+AQAIAAcJ/gyMmAA4AQABLgAECgMJAwAJAAAAAA==.',
Ah='Ahkari:BAAALgAECgEJAQABLgAFFAMJBgAKAJAXAA==.Ahrmanhamma:BAACLgAFFH8NAAIGAAQJUiEQIACHAQAGAAQJUiEQIACHAQAuAAQKfxoAAgYACQkvIvsSANECAAYACQkvIvsSANECAAAA.Ahu:BAABLgAECn8nAAMEAAgJsRcuMADwAQAEAAgJsRcuMADwAQALAAMJZAQjcwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgQJBQAAAA==.Airotciv:BAAALgAECgEJAQAAAA==.',
Al='Al:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgQJEgAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAACLgAFFH8VAAMLAAUJYwW1BADpAAAEAAUJTgQRWQDzAAALAAQJkgS1BADpAAAuAAQKf0QAAwQACQm7ESU+AOkBAAQACQl7ESU+AOkBAAsACAmfDB41AJUBAAAA.Alerus:BAAALgAECgEJAQAAAA==.Alexander:BAABLgAECn8eAAIMAAkJixrzJgDXAgAMAAkJixrzJgDXAgAAAA==.Alexijones:BAABLgAECn8cAAINAAkJJQ/0GgDGAQANAAkJJQ/0GgDGAQAAAA==.Allaria:BAAALgAECgcJCgAAAA==.',
Am='Ambassador:BAABLgAECn8eAAIOAAkJlBdbDAD+AQAOAAkJlBdbDAD+AQAAAA==.Amoondai:BAACLgAFFH8lAAIPAAUJ3R+NCADGAQAPAAUJ3R+NCADGAQAuAAQKf0kAAg8ACQlhJZ0BAKADAA8ACQlhJZ0BAKADAAAA.',
An='Analytics:BAAALgADCgYJBgAAAA==.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn8/AAMQAAkJUiLvBADfAgAQAAkJUiLvBADfAgAIAAYJ7wNo0gDcAAAAAA==.Apolyon:BAABLgAECn8mAAIRAAkJLSFkCQAkAwARAAkJLSFkCQAkAwAAAA==.',
Ar='Araon:BAAALgAECgYJCwAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
As='Asheraah:BAAALgAECgQJCQAAAA==.',
At='Atroxz:BAAALgADCgcJCAAAAA==.',
Au='Aurén:BAAALgAECgYJDgAAAA==.',
Az='Azuree:BAABLgAFFH8FAAIFAAIJGxZIFQBlAAAFAAIJGxZIFQBlAAAAAA==.',
Ba='Bacstabath:BAABLgAECn8sAAISAAkJTx4XBgAvAwASAAkJTx4XBgAvAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAFFAQJDQAGAFIhAA==.Banshee:BAABLgAECn8eAAITAAkJ1B+EFACeAgATAAkJ1B+EFACeAgAAAA==.Baychan:BAABLgAECn8WAAIUAAcJixuXGADiAQAUAAcJixuXGADiAQABLgAECgkJNQAVAB0jAA==.',
Be='Becca:BAABLgAECn87AAIOAAkJBRddDAD+AQAOAAkJBRddDAD+AQAAAA==.Berries:BAAALgAECgEJAQAAAA==.',
Bi='Bigaraon:BAAALgADCgIJAgAAAA==.Bigdamaj:BAABLgAECn81AAMHAAkJEhnEBwAYAgAHAAkJcxfEBwAYAgAIAAkJBhTgVQDDAQAAAA==.Birbdormu:BAAALgAECgQJBQABLgAECgkJOAAWANIeAA==.',
Bl='Blakdemon:BAAALgAECgUJBgABLgAFFAMJBAAJAAAAAA==.Bloodiblind:BAAALgAECgQJCQAAAA==.Bloodios:BAABLgAECn80AAIQAAkJNh+4BwCdAgAQAAkJNh+4BwCdAgAAAA==.Blázé:BAAALgADCgEJAQAAAA==.',
Bo='Bobbardment:BAAALgAFFAEJAQAAAA==.Bobin:BAAALgAECgMJBAABLgAECgkJHQAXAOwQAA==.Bobinforapl:BAABLgAECn8dAAIXAAkJ7BDfIwCwAQAXAAkJ7BDfIwCwAQAAAA==.Bokaya:BAAALgAFFAEJAQAAAA==.Bombadil:BAABLgAECn9HAAIXAAkJhgcCLAB3AQAXAAkJhgcCLAB3AQAAAA==.',
Br='Bribage:BAABLgAECn84AAQWAAkJ0h4ADQCHAgAWAAkJ/R0ADQCHAgAYAAYJahoqEwDBAQARAAIJqRudjACdAAAAAA==.Brolavski:BAAALgAECgEJAQABLgAECgcJEAAJAAAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgUJBwABLgAECgcJCgAJAAAAAA==.Budderwar:BAABLgAECn81AAQZAAkJDyZ0AgAeAwAZAAkJDyZ0AgAeAwAaAAcJkRuYEQDdAQAbAAMJvw4KhwCjAAAAAA==.Buggz:BAAALgAECgQJBgAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgIJBQAAAA==.',
['Bà']='Bàdmofos:BAAALgAECgQJBwAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.Calvis:BAAALgADCgcJDAAAAA==.',
Cb='Cbreezy:BAAALgAECgQJBgAAAA==.',
Ce='Celerydk:BAABLgAECn8eAAIIAAkJ0RWaAgACAgAIAAkJ0RWaAgACAgAAAA==.Celhealz:BAAALgAECgIJAgAAAA==.Celjska:BAAALgAECgUJCAAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chaosgaara:BAAALgAECgEJAgAAAA==.Chikñ:BAABLgAECn8cAAMFAAgJuw/kQABGAQAFAAYJ5xHkQABGAQAcAAgJ7gk1XwA/AQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.Chuanthu:BAAALgAECgYJCQAAAA==.Chug:BAAALgAECgEJAQAAAA==.',
Ci='Cinderspella:BAAALgAECgIJAgAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8zAAIdAAkJdiVHAgBKAwAdAAkJdiVHAgBKAwAAAA==.',
Co='Cocoredbull:BAABLgAECn8dAAIYAAkJdw7cJAArAQAYAAkJdw7cJAArAQAAAA==.Corrail:BAAALgAECgYJDQAAAA==.Correin:BAABLgAECn8fAAIeAAkJbw9vIwBcAQAeAAkJbw9vIwBcAQAAAA==.',
Cr='Craszhin:BAABLgAECn8kAAIWAAkJqRDqIADBAQAWAAkJqRDqIADBAQAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn81AAIMAAkJIww1cACZAQAMAAkJIww1cACZAQAAAA==.',
Da='Dadeb:BAAALgAECgQJBgABLgAECgkJJAAGAJIVAA==.Daenarea:BAABLgAECn8qAAIfAAkJPxXYCABdAgAfAAkJPxXYCABdAgAAAA==.Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.Darksasuke:BAAALgAECgEJAQAAAA==.Darkwater:BAAALgADCgkJCQAAAA==.Dazinth:BAAALgAECgEJAQAAAA==.Dazînth:BAAALgAECgEJAgAAAA==.',
De='Deets:BAABLgAECn82AAIEAAkJSh9kFACvAgAEAAkJSh9kFACvAgAAAA==.Defoy:BAABLgAECn8WAAMLAAYJJhlfGQDkAAALAAYJ4xZfGQDkAAAEAAQJZxCR6QB7AAAAAA==.Demona:BAABLgAECn8yAAMDAAkJDQ6aDAB2AQADAAkJDQ6aDAB2AQACAAYJWgPM3gCcAAAAAA==.Demonduckz:BAAALgAECgEJAgAAAA==.Demonicfates:BAABLgAECn8bAAIeAAgJWA7cJQBLAQAeAAgJWA7cJQBLAQAAAA==.Derffy:BAABLgAECn8tAAIgAAkJ8SH1AQAVAwAgAAkJ8SH1AQAVAwAAAA==.Descalabrada:BAAALgAECgYJDAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Di='Distol:BAAALgAECgUJCAAAAA==.',
Dm='Dmt:BAABLgAECn8iAAIhAAgJBh0NGgBHAgAhAAgJBh0NGgBHAgAAAA==.',
Do='Dotemdown:BAAALgAECgIJAgAAAA==.',
Dr='Dragonborn:BAAALgAECgEJAgAAAA==.Draiara:BAAALgAECgMJAwAAAA==.Dropdeadqtx:BAAALgAECgYJDQAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJHwABALwiAA==.Drpeppers:BAABLgAECn8sAAMRAAkJLAsjRwBzAQARAAkJLAsjRwBzAQAYAAEJAAAUPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathknight:BAAALgAECgEJAQABLgAFFAEJAQAJAAAAAA==.Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthadin:BAAALgAECgYJBgAAAA==.Earthling:BAAALgAECgUJDQAAAA==.',
Ec='Eclair:BAABLgAECn81AAMcAAkJkhS2LgD7AQAcAAkJkhS2LgD7AQAFAAYJ5BjOOABUAQAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgAECgQJBAABLgAECgkJLAASAE8eAA==.',
El='Eleysia:BAAALgAECggJDQAAAA==.Elf:BAAALgAECgYJBwABLgAECgkJBgAJAAAAAA==.Elhayn:BAAALgAECgUJBwAAAA==.Elmore:BAAALgAECgQJBAAAAA==.Elmos:BAABLgAECn8zAAIdAAkJVh8VAQDHAQAdAAkJVh8VAQDHAQAAAA==.',
Er='Erestadh:BAAALgAECgIJAwABLgAECgcJHAAMAFwMAA==.Eris:BAAALgADCgcJBwAAAA==.',
Eu='Eucalyptus:BAAALgAECgEJAgAAAA==.',
Ev='Evilchuckle:BAAALgADCgcJBwAAAA==.Evilmonkeymg:BAEALgAECgEJAQABLgAECgkJGQAFACceAA==.Evilmonkeysh:BAEBLgAECn8ZAAMFAAkJJx5eHAAvAgAFAAkJJx5eHAAvAgAcAAcJQQvdTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECgkJGQAFACceAA==.',
Ex='Exto:BAAALgAECgMJBAABLgAECgQJBAAJAAAAAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8xAAMeAAkJthYYEgALAgAeAAkJthYYEgALAgAiAAYJngqnGQDQAAAAAA==.',
Fa='Fatehunter:BAAALgADCggJCAAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgcJEgABLgAECggJDgAJAAAAAA==.Fenrísulfr:BAAALgAECgUJCAABLgAECggJDgAJAAAAAA==.Ferg:BAAALgAECgYJCQABLgAECgkJOQAMAE4jAA==.Fergis:BAABLgAECn85AAIMAAkJTiPxDAASAwAMAAkJTiPxDAASAwAAAA==.Fergle:BAAALgAECgYJEgAAAA==.Fetchme:BAAALgAECgQJBwAAAA==.Fetchyou:BAAALgADCggJDgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8dAAMQAAkJsBc8EgDoAQAQAAkJ+xY8EgDoAQAHAAcJ0RVDCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECggJEQAAAA==.',
Fr='Freecaster:BAAALgAECgMJAwAAAA==.Frostybeary:BAAALgAECgkJCQAAAA==.Frostymonk:BAABLgAECn8ZAAMhAAcJOQmmZADpAAAhAAcJOQmmZADpAAAdAAEJVAYKtwAhAAAAAA==.Frozenwaffle:BAAALgAECgYJEgABLgAECgkJJgAjAJkhAA==.',
Fu='Furryben:BAAALgAECgMJAwAAAA==.',
['Fá']='Fállen:BAAALgADCgYJDQAAAA==.',
Ga='Galeste:BAAALgAECgUJCQAAAA==.',
Gh='Ghidorahh:BAAALgAFFAEJAQAAAA==.',
Gi='Gigem:BAABLgAECn8UAAIEAAcJWhxIQgDbAQAEAAcJWhxIQgDbAQAAAA==.Girlshoon:BAAALgAECgIJAgAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQfAAkJkASTIwBcAQAfAAkJkASTIwBcAQAKAAUJ9gP/SgCoAAAkAAEJlQF3LAAYAAAAAA==.Glarious:BAAALgAECgYJEAABLgAECgkJGwAfAJAEAA==.',
Go='Golakuron:BAAALgADCgUJBQAAAA==.Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgcJEAAAAA==.Gredan:BAAALgAECgYJDgAAAA==.Greenwaffle:BAABLgAECn8mAAMjAAkJmSHlDACEAgAjAAkJmSHlDACEAgAPAAYJwBTCNQBmAQAAAA==.Grôg:BAAALgAECgkJDQAAAA==.',
Gu='Guldaniel:BAAALgAECgUJCgABLgAECgkJJAAGAJIVAA==.Guthx:BAABLgAECn8eAAIRAAkJzBjpIgAyAgARAAkJzBjpIgAyAgAAAA==.',
Ha='Harutah:BAAALgAECgQJBAAAAA==.Hazeran:BAAALgAECgMJBQAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgAJAAAAAA==.',
Ho='Holymolii:BAABLgAECn8pAAIOAAkJhBbdDgDVAQAOAAkJhBbdDgDVAQAAAA==.Hotcoffee:BAAALgAECgYJDgAAAA==.',
Hu='Huntermaster:BAABLgAECn8bAAQNAAgJFRf5IACUAQANAAcJwBf5IACUAQALAAUJRxiERABDAQAEAAEJEBKTLAE4AAABLgAECgkJNQAZAA8mAA==.',
Il='Ilulz:BAAALgADCgEJAQAAAA==.',
In='Inali:BAAALgAECgEJAQAAAA==.Incredabull:BAABLgAECn8fAAIZAAkJuRiDEQDSAQAZAAkJuRiDEQDSAQAAAA==.Intrepidz:BAAALgAECgEJAQABLgAECgkJJAAMABUYAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAABLgAECn8wAAIlAAkJ3xTQCADZAQAlAAkJ3xTQCADZAQAAAA==.Istayblunted:BAABLgAECn8fAAIOAAcJ6x8QEADEAQAOAAcJ6x8QEADEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDQAAAA==.',
Iw='Iwinwithhots:BAAALgAECgEJAgABLgAECgcJGAAGAIceAA==.',
Ja='Jacqualyn:BAAALgAFFAMJAwAAAA==.',
Ji='Jiayerah:BAAALgAECgYJEwABLgAECggJMwAXAOcgAA==.Jinkuzo:BAABLgAECn8xAAIUAAkJIB+UCgCKAgAUAAkJIB+UCgCKAgAAAA==.Jinmu:BAABLgAECn80AAMSAAkJOxh+EgASAgASAAkJOxh+EgASAgAmAAEJJgtIKQAwAAAAAA==.',
Jo='Joaquin:BAAALgAECgQJBAABLgAECgYJCwAJAAAAAA==.',
Ju='Juggie:BAABLgAECn8vAAIPAAkJrhMvGgD5AQAPAAkJrhMvGgD5AQAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8pAAImAAkJigvhCwBxAQAmAAkJigvhCwBxAQAAAA==.',
Ka='Kagami:BAAALgAECgIJAgAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAABLgAECn8XAAMCAAkJgRryKAA4AgACAAkJVhryKAA4AgADAAEJFBvWawA8AAAAAA==.Kanè:BAAALgAECgEJAQAAAA==.',
Ke='Keliez:BAAALgAFFAEJAgABLgAFFAcJJgARAPkQAA==.',
Kh='Khrodors:BAAALgADCgMJAwAAAA==.',
Ki='Kiannis:BAAALgADCgEJAQAAAA==.Kickerr:BAAALgAECggJEwABLgAECgkJDwAJAAAAAA==.Kickrr:BAAALgAECgkJDwAAAA==.Kikyo:BAAALgAECgEJAwAAAA==.Kirrby:BAAALgADCgEJAQAAAA==.',
Kl='Klodar:BAAALgAECgQJBAAAAA==.Klum:BAAALgAECgYJCgAAAA==.',
Kr='Krazee:BAAALgAECgEJAgAAAA==.Krotas:BAAALgAECgMJAwAAAA==.Krunkle:BAAALgAECgIJAwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgAECgkJEgAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgAECgYJEwAAAA==.Lendela:BAAALgAECgUJDAAAAA==.',
Li='Liljugg:BAABLgAECn8UAAMPAAYJwglLRQDTAAAPAAYJwglLRQDTAAAjAAIJpgOPfgBAAAAAAA==.',
Lm='Lmaddk:BAAALgAECgIJAgAAAA==.',
Lo='Logi:BAAALgAECgMJAwAAAA==.Lor:BAAALgAECgQJBgAAAA==.Lostmana:BAAALgAECgYJDwAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Lu='Lunablade:BAAALgAECgEJAQAAAA==.',
Ly='Lygor:BAABLgAECn82AAIEAAkJpxMFNQAJAgAEAAkJpxMFNQAJAgAAAA==.Lyrasong:BAAALgADCgIJAgAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJHwABALwiAA==.',
Ma='Maelle:BAAALgADCgYJBwAAAA==.Magnifico:BAAALgAECgUJCgAAAA==.Majellan:BAAALgAECgQJCQAAAA==.Makrub:BAAALgAECggJDQAAAA==.Malystryix:BAAALgAECgQJBAAAAA==.Mandigosa:BAAALgAECgMJBAAAAA==.Marist:BAAALgAECgEJAwAAAA==.Marrius:BAAALgAECgEJAgAAAA==.Marsawn:BAABLgAECn8gAAMjAAkJERggFgAaAgAjAAkJERggFgAaAgAPAAMJYBhFSQDAAAAAAA==.',
Mc='Mcpeepants:BAACLgAFFH8IAAIVAAQJaxdLCQAmAQAVAAQJaxdLCQAmAQAuAAQKfxQAAhUACQnsHlQEAK4CABUACQnsHlQEAK4CAAEuAAUUBAkNAAYAUiEA.',
Me='Meqi:BAABLgAECn8hAAMMAAgJqx1UQAAbAgAMAAgJqx1UQAAbAgAnAAEJDBcVDgBGAAAAAA==.',
Mi='Mikàsa:BAABLgAECn8mAAMNAAkJSBBUFgDvAQANAAkJSBBUFgDvAQALAAYJXwmaTgAVAQAAAA==.Minand:BAAALgAECgYJEQAAAA==.Mindlessness:BAABLgAECn8yAAIbAAkJ5yMEBgD/AgAbAAkJ5yMEBgD/AgAAAA==.Mineralelf:BAABLgAECn86AAIEAAkJxwxlUACxAQAEAAkJxwxlUACxAQAAAA==.Minichaos:BAABLgAECn8yAAMDAAkJ4Rj6AwBKAgADAAkJ4Rj6AwBKAgACAAQJgAYC3QCfAAAAAA==.Miriam:BAABLgAECn8eAAMoAAcJjAW6CgDZAAAoAAcJjAW6CgDZAAAMAAEJ9QJifAEiAAAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8fAAIBAAgJvCIpBwD5AgABAAgJvCIpBwD5AgAAAA==.',
Mo='Mojosavage:BAABLgAECn8YAAICAAcJ7gI52ACnAAACAAcJ7gI52ACnAAAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAgAAAA==.Moonblade:BAAALgAECgYJCwAAAA==.Mortshan:BAABLgAECn8bAAInAAkJRhZVAwDzAQAnAAkJRhZVAwDzAQAAAA==.Mournfull:BAAALgAECgEJBQAAAA==.',
My='Mysticalfox:BAAALgAECgQJBgAAAA==.',
Na='Nalfilas:BAAALgAECgUJDQAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgAECggJDgAAAA==.Nikru:BAABLgAFFH8GAAIOAAMJtwd3EgBnAAAOAAMJtwd3EgBnAAABLgAFFAcJJgARAPkQAA==.Ninok:BAABLgAECn8sAAIGAAkJGxXnRAD3AQAGAAkJGxXnRAD3AQAAAA==.',
No='Nornee:BAABLgAECn8rAAIcAAgJ4xDQSgCEAQAcAAgJ4xDQSgCEAQAAAA==.Nourishing:BAAALgAECgQJBAABLgAECggJDQAJAAAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8dAAIgAAgJRR2XCgAWAgAgAAgJRR2XCgAWAgAAAA==.',
['Nà']='Nàtureswrath:BAAALgAECggJDQAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAABLgAECn8bAAMbAAgJ0xEhNgBwAQAbAAgJ0xEhNgBwAQAaAAEJ4wz3fgArAAAAAA==.',
Ol='Ollïee:BAAALgAECgYJBgAAAA==.',
Op='Oprawyndfury:BAAALgAECggJEAAAAA==.',
Or='Orceo:BAABLgAECn8rAAIEAAkJACTIBQAxAwAEAAkJACTIBQAxAwAAAA==.Orkreghar:BAAALgAFFAEJAQAAAA==.',
Os='Osaro:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgAECgIJAgAAAA==.',
Ow='Ownlyshamz:BAAALgADCgMJAwABLgAFFAMJCwAfAJUUAA==.',
Ox='Oxcanor:BAAALgAECgcJCwAAAA==.',
Pa='Patches:BAAALgAECgUJBwABLgAECggJHwABALwiAA==.Patrick:BAAALgAECgQJBAAAAA==.',
Pe='Pepsipoutine:BAABLgAECn8WAAICAAYJmB+9TgDcAQACAAYJmB+9TgDcAQAAAA==.Petiterage:BAAALgADCggJCwAAAA==.',
Pi='Pindapind:BAAALgADCgMJBAABLgAECgkJNQAZAA8mAA==.Pindapinda:BAAALgAECggJDAABLgAECgkJNQAZAA8mAA==.',
Pl='Plaguexion:BAAALgADCgQJBgAAAA==.',
Po='Pompompower:BAABLgAECn83AAIFAAkJ/AomBQDkAAAFAAkJ/AomBQDkAAAAAA==.Popple:BAABLgAECn8sAAIbAAkJ5xAeIwDaAQAbAAkJ5xAeIwDaAQAAAA==.Potential:BAACLgAFFH8PAAIUAAMJMB3nBwDrAAAUAAMJMB3nBwDrAAAuAAQKfysAAhQACQmvHWkAAHUCABQACQmvHWkAAHUCAAAA.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgUJEAAAAA==.Puggsly:BAAALgAECgEJBAABLgAECgkJJAAGAJIVAA==.Pugsta:BAAALgAECgQJCQABLgAECggJEgAJAAAAAA==.Pulpfiction:BAABLgAECn8yAAMoAAYJfwWQDQDvAAAoAAYJRAWQDQDvAAAMAAUJjQR9DAGaAAAAAA==.',
Py='Pyrocaster:BAAALgAECgQJBQAAAA==.',
Qa='Qaccy:BAABLgAECn8TAAIjAAcJqQ7kQAAMAQAjAAcJqQ7kQAAMAQAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAABLgAECn8bAAIbAAgJzhl+KQCzAQAbAAgJzhl+KQCzAQAAAA==.',
Ra='Radaghast:BAAALgAECgEJAQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Raoul:BAAALgAECgMJBQAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Regret:BAAALgAFFAEJAgABLgAFFAgJJwAiAG4WAA==.Reishirome:BAAALgAECgEJAQAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8eAAIYAAgJPSIZAwDlAgAYAAgJPSIZAwDlAgAAAA==.',
Rh='Rhaellia:BAABLgAECn8WAAIhAAgJUwmICQDSAAAhAAgJUwmICQDSAAAAAA==.Rhogar:BAAALgAECgMJBAAAAA==.Rhoke:BAAALgAECgQJAwAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8gAAIWAAkJpQZnOQAtAQAWAAkJpQZnOQAtAQAAAA==.Romeoz:BAAALgAECgUJCAAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAABLgAECn8UAAIEAAYJ5xPjewBIAQAEAAYJ5xPjewBIAQAAAA==.Roukia:BAAALgADCgQJBAAAAA==.',
Ru='Rugbeans:BAAALgAECgEJAQAAAA==.Rumincoke:BAAALgADCgkJEwAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAABLgAECn8zAAMXAAgJ5yAtAQAMAgAPAAgJ5yBbCgDBAgAXAAYJ4B4tAQAMAgAAAA==.Saruma:BAAALgAECgQJAwAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwAJAAAAAA==.',
Sc='Scalygrob:BAAALgAECgkJEwAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8zAAIXAAkJ6RfYDgCBAgAXAAkJ6RfYDgCBAgAAAA==.Sellphie:BAAALgADCgcJCAAAAA==.',
Sh='Shadowhntr:BAAALgAECgYJCQAAAA==.Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shamehameha:BAABLgAFFH8GAAIFAAMJQxJvDQDAAAAFAAMJQxJvDQDAAAAAAA==.Shamonuu:BAAALgAECgEJAQAAAA==.Shavedussy:BAAALgADCgUJBQABLgAECgkJJAAGAJIVAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Siknes:BAAALgAECggJCwABLgAECgkJLAASAE8eAA==.Simmareth:BAAALgADCgcJBwAAAA==.Simpofmeerah:BAAALgAECgYJCAAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgYJDAAAAA==.',
Sl='Slargerita:BAAALgADCgcJBwAAAA==.',
Sm='Smallmoon:BAAALgAECgEJAQAAAA==.Smogcheck:BAACLgAFFH8WAAMfAAUJyRWJGQD+AAAfAAQJSRKJGQD+AAAKAAMJDwb0XABhAAAuAAQKfyEAAx8ACQkOE2gbAK0BAB8ACQkOE2gbAK0BACQAAQl9CNM+ADQAAAAA.',
Sn='Snackcake:BAABLgAECn8oAAIRAAkJvBpeEwCwAgARAAkJvBpeEwCwAgAAAA==.Snakeoil:BAABLgAECn8cAAMFAAkJyh5GEABxAgAFAAkJyh5GEABxAgAcAAEJCgKQ7QAiAAAAAA==.Snowsz:BAAALgAECgMJAwAAAA==.Snowws:BAABLgAECn8eAAITAAkJ9xoyIQBOAgATAAkJ9xoyIQBOAgAAAA==.',
So='Sortis:BAABLgAECn8kAAIMAAkJFRjeMwCjAgAMAAkJFRjeMwCjAgAAAA==.',
Sp='Spicebreff:BAABLgAFFH8LAAIfAAMJlRSfBgC+AAAfAAMJlRSfBgC+AAAAAA==.Spongerunner:BAABLgAECn8ZAAICAAcJzRk3BgAMAQACAAcJzRk3BgAMAQAAAA==.Sprucetea:BAAALgADCgIJAwAAAA==.',
St='Steck:BAABLgAECn9FAAIEAAkJcBYlBgBwAQAEAAkJcBYlBgBwAQAAAA==.Strigo:BAABLgAFFH8OAAQNAAQJdRiuEwAuAQANAAQJCBiuEwAuAQAEAAEJtBy7IABfAAALAAEJnwy7KABKAAAAAA==.',
Su='Subway:BAAALgAECggJEAAAAA==.Sunbaby:BAABLgAECn8oAAIiAAgJnh6UBgAqAgAiAAgJnh6UBgAqAgAAAA==.',
['Sà']='Sàlís:BAAALgADCgkJDgAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8gAAIXAAkJdCBJBQD9AgAXAAkJdCBJBQD9AgAAAA==.Takhisoth:BAAALgADCgYJBgAAAA==.Talandaru:BAAALgAECgEJBAAAAA==.Talas:BAABLgAECn8zAAMEAAkJFh7bFQClAgAEAAkJFh7bFQClAgALAAUJswr3VwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Te='Temberle:BAAALgAECgQJBAABLgAECgkJOQADAMQQAA==.Temerald:BAAALgADCgkJCQAAAA==.Tevoran:BAAALgAECgYJEAAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thaelidari:BAAALgAECgkJDAAAAA==.Thieridan:BAAALgADCgIJBAAAAA==.Thrangus:BAAALgAECgIJAgABLgAFFAMJBQAIAMYdAA==.Thrann:BAACLgAFFH8FAAMIAAMJxh1fsQDBAAAIAAIJUyBfsQDBAAAHAAIJnBt0HACgAAAuAAQKfyAAAwcACQnrIvkJAOMBAAgABwmpIp86AE0CAAcABQmHI/kJAOMBAAAA.Thunderdex:BAACLgAFFH8UAAMTAAcJpBYwHwC9AQATAAcJpBYwHwC9AQAeAAEJ6ANOMQAzAAAuAAQKfx8AAhMACQl+HsYfAFYCABMACQl+HsYfAFYCAAAA.',
Ti='Tirium:BAAALgAECgcJCAABLgAFFAMJCwAfAJUUAA==.',
To='Togglesmith:BAAALgAECgYJDAAAAA==.Togglestein:BAAALgAECgYJEAAAAA==.Togglethorp:BAAALgAECgUJBQAAAA==.Togi:BAAALgADCgcJDQAAAA==.Totema:BAAALgAECgEJAQABLgAECgkJJAAGAJIVAA==.',
Tr='Trinitum:BAAALgAECgcJCwABLgAFFAMJCwAfAJUUAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Ud='Udderduckie:BAAALgAECgEJAgAAAA==.',
Um='Umaroth:BAAALgAECgYJBgABLgAECgkJMwAEABYeAA==.',
Un='Unfolrion:BAAALgADCgIJBAAAAA==.Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJCwAAAA==.Ursoconha:BAABLgAFFH8FAAMRAAQJoQpQVwBrAAARAAMJfQVQVwBrAAAYAAEJqR08MwBSAAABLgAFFAYJBgAMAIsYAA==.',
Va='Vaadboolin:BAAALgAECggJEgAAAA==.Vaadhands:BAAALgAECgUJCAAAAA==.Vaevicta:BAAALgAECgYJBgAAAA==.Vallius:BAABLgAECn8dAAISAAkJ5BKbGQDNAQASAAkJ5BKbGQDNAQAAAA==.Vanargandr:BAAALgAECggJDgAAAA==.',
Ve='Velirria:BAAALgAECgUJBQABLgAFFAMJEAAZAFUSAA==.Verðandi:BAAALgAECgIJAgAAAA==.',
Vo='Volcano:BAABLgAECn8bAAICAAkJIxo8KAA7AgACAAkJIxo8KAA7AgAAAA==.Volvox:BAAALgADCgEJAQAAAA==.Vonslarge:BAAALgADCgkJCQAAAA==.',
Vy='Vyxenn:BAABLgAECn82AAMcAAkJ0xbKIQBEAgAcAAkJ0xbKIQBEAgAFAAUJTQsHWADcAAAAAA==.',
Wa='Waffletoast:BAAALgADCgkJEQABLgAECgkJJgAjAJkhAA==.Wanders:BAACLgAFFH8FAAIMAAMJVge3jQC9AAAMAAMJVge3jQC9AAAuAAQKfyoAAwwACQkgGownAHwCAAwACQkgGownAHwCACgABgksCZ0LABwBAAAA.Warlockk:BAAALgAECgUJCQAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Wc='Wckddreamer:BAAALgADCgEJAQAAAA==.',
We='Wenevella:BAAALgAECgIJAgAAAA==.',
Wu='Wurm:BAAALgAECgcJBwABLgAECgkJDQAJAAAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yejena:BAAALgAECgEJAgAAAA==.Yep:BAACLgAFFH8KAAIGAAQJVRjbMwBHAQAGAAQJVRjbMwBHAQAuAAQKfxsAAgYACQnwI4QKABMDAAYACQnwI4QKABMDAAAA.Yesenìa:BAAALgAFFAEJAQAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zanderr:BAAALgADCgYJBgAAAA==.Zavia:BAAALgADCgYJFQAAAA==.Zazael:BAAALgAECgIJAgAAAA==.Zazreal:BAABLgAECn84AAQkAAkJgh0JAwB4AgAkAAkJgh0JAwB4AgAKAAMJ4Q9oSwClAAAfAAQJ7wIILQCCAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn85AAIVAAkJ7gZ1FgBbAQAVAAkJ7gZ1FgBbAQAAAA==.Zillyanna:BAAALgAECggJEwAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zyper:BAAALgAECgYJDAAAAA==.Zywol:BAABLgAECn8mAAQWAAkJ5hgDFQApAgAWAAkJ5hgDFQApAgARAAMJlgbIpgB6AAAYAAEJjA8FegAqAAAAAA==.',
['Ër']='Ëresta:BAABLgAECn8cAAIMAAcJXAyToAA6AQAMAAcJXAyToAA6AQAAAA==.',
['Ðe']='Ðesire:BAAALgAECgYJCwAAAA==.Ðespair:BAACLgAFFH8QAAIjAAQJ/SC9DwBvAQAjAAQJ/SC9DwBvAQAuAAQKfzQABBcACQklICQKAJYCABcABwk9ISQKAJYCACMACQltH1IMAIsCAA8ABQmTGJNBAOYAAAAA.',
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
