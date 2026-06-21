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
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abaddón:BAAALgAECgEJAQABLgAECggJHwABALwiAA==.Abfuscatedd:BAABLgAECn8iAAMCAAkJShN0QgDUAQACAAkJShN0QgDUAQADAAEJAAARgAATAAAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJFgAEAPoYAA==.Acidrain:BAABLgAECn85AAIFAAkJMyEJCADcAgAFAAkJMyEJCADcAgAAAA==.Acmiax:BAABLgAECn8kAAMGAAkJkhVHPAATAgAGAAkJkhVHPAATAgABAAUJugseVgDfAAAAAA==.',
Ad='Adar:BAAALgAECgQJBwAAAA==.',
Ae='Aep:BAABLgAECn8ZAAMHAAgJ+hLzEwA+AQAHAAYJRRTzEwA+AQAIAAcJ/gyKmAA4AQABLgAECgMJAwAJAAAAAA==.',
Ah='Ahkari:BAAALgAECgEJAQABLgAFFAMJBgAKAJAXAA==.Ahrmanhamma:BAACLgAFFH8NAAIGAAQJUiEkIACHAQAGAAQJUiEkIACHAQAuAAQKfxoAAgYACQkvIvsSANECAAYACQkvIvsSANECAAAA.Ahu:BAABLgAECn8nAAMEAAgJsRcuMADwAQAEAAgJsRcuMADwAQALAAMJZAQjcwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgQJBQAAAA==.Airotciv:BAAALgAECgEJAQAAAA==.',
Al='Al:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgQJEgAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAACLgAFFH8SAAMLAAUJYwUuAQDxAAAEAAUJTgQRWQDzAAALAAQJSwQuAQDxAAAuAAQKf0QAAwQACQm7ESc+AOkBAAQACQl7ESc+AOkBAAsACAmfDB41AJUBAAAA.Alerus:BAAALgAECgEJAQAAAA==.Alexander:BAABLgAECn8eAAIMAAkJixrzJgDXAgAMAAkJixrzJgDXAgAAAA==.Alexijones:BAABLgAECn8cAAINAAkJJQ/1GgDGAQANAAkJJQ/1GgDGAQAAAA==.Allaria:BAAALgAECgcJCgAAAA==.',
Am='Ambassador:BAABLgAECn8eAAIOAAkJlBdaDAD+AQAOAAkJlBdaDAD+AQAAAA==.Amoondai:BAACLgAFFH8hAAIPAAUJ3R+OCADGAQAPAAUJ3R+OCADGAQAuAAQKf0gAAg8ACQn2JJ4BAKADAA8ACQn2JJ4BAKADAAAA.',
An='Analytics:BAAALgADCgYJBgAAAA==.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn8/AAMQAAkJUiLxBADfAgAQAAkJUiLxBADfAgAIAAYJ7wNo0gDcAAAAAA==.Apolyon:BAABLgAECn8mAAIRAAkJLSFkCQAkAwARAAkJLSFkCQAkAwAAAA==.',
Ar='Araon:BAAALgAECgYJCwAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
As='Asheraah:BAAALgAECgQJCAAAAA==.',
At='Atroxz:BAAALgADCgcJCAAAAA==.',
Au='Aurén:BAAALgAECgYJCgAAAA==.',
Az='Azuree:BAAALgAFFAIJBAAAAA==.',
Ba='Bacstabath:BAABLgAECn8sAAISAAkJTx4XBgAvAwASAAkJTx4XBgAvAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAFFAQJDQAGAFIhAA==.Banshee:BAABLgAECn8eAAITAAkJ1B+HFACeAgATAAkJ1B+HFACeAgAAAA==.Baychan:BAABLgAECn8WAAIUAAcJixuWGADiAQAUAAcJixuWGADiAQAAAA==.',
Be='Becca:BAABLgAECn87AAIOAAkJBRddDAD+AQAOAAkJBRddDAD+AQAAAA==.Berries:BAAALgAECgEJAQAAAA==.',
Bi='Bigaraon:BAAALgADCgIJAgAAAA==.Bigdamaj:BAABLgAECn81AAMHAAkJEhnEBwAYAgAHAAkJcxfEBwAYAgAIAAkJBhTdVQDDAQAAAA==.Birbdormu:BAAALgAECgQJBQABLgAECgkJOAAVANIeAA==.',
Bl='Blakdemon:BAAALgAECgUJBgABLgAFFAMJBAAJAAAAAA==.Bloodiblind:BAAALgAECgQJCQAAAA==.Bloodios:BAABLgAECn80AAIQAAkJNh+7BwCdAgAQAAkJNh+7BwCdAgAAAA==.Blázé:BAAALgADCgEJAQAAAA==.',
Bo='Bobbardment:BAAALgAFFAEJAQAAAA==.Bobin:BAAALgAECgMJBAABLgAECgkJHQAWAOwQAA==.Bobinforapl:BAABLgAECn8dAAIWAAkJ7BDcIwCwAQAWAAkJ7BDcIwCwAQAAAA==.Bokaya:BAAALgAFFAEJAQAAAA==.Bombadil:BAABLgAECn9HAAIWAAkJhgcCLAB3AQAWAAkJhgcCLAB3AQAAAA==.',
Br='Bribage:BAABLgAECn84AAQVAAkJ0h7/DACHAgAVAAkJ/R3/DACHAgAXAAYJahopEwDBAQARAAIJqRucjACdAAAAAA==.Brolavski:BAAALgAECgEJAQABLgAECgcJEAAJAAAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgUJBwABLgAECgcJCgAJAAAAAA==.Budderwar:BAABLgAECn81AAQYAAkJDyZ0AgAeAwAYAAkJDyZ0AgAeAwAZAAcJkRuXEQDdAQAaAAMJvw4KhwCjAAAAAA==.Buggz:BAAALgAECgQJBgAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgIJBQAAAA==.',
['Bà']='Bàdmofos:BAAALgAECgQJBwAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.Calvis:BAAALgADCgcJDAAAAA==.',
Cb='Cbreezy:BAAALgAECgQJBgAAAA==.',
Ce='Celerydk:BAABLgAECn8WAAIIAAkJnxEWRwDtAQAIAAkJnxEWRwDtAQAAAA==.Celhealz:BAAALgAECgIJAgAAAA==.Celjska:BAAALgAECgUJCAAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chikñ:BAABLgAECn8cAAMFAAgJuw/kQABGAQAFAAYJ5xHkQABGAQAbAAgJ7gkwXwA/AQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.Chuanthu:BAAALgAECgYJCQAAAA==.Chug:BAAALgAECgEJAQAAAA==.',
Ci='Cinderspella:BAAALgAECgIJAgAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8zAAIcAAkJdiVHAgBKAwAcAAkJdiVHAgBKAwAAAA==.',
Co='Cocoredbull:BAABLgAECn8dAAIXAAkJdw7eJAArAQAXAAkJdw7eJAArAQAAAA==.Corrail:BAAALgAECgYJDQAAAA==.Correin:BAABLgAECn8fAAIdAAkJbw9tIwBcAQAdAAkJbw9tIwBcAQAAAA==.',
Cr='Craszhin:BAABLgAECn8kAAIVAAkJqRDmIADBAQAVAAkJqRDmIADBAQAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn81AAIMAAkJIww0cACZAQAMAAkJIww0cACZAQAAAA==.',
Da='Dadeb:BAAALgAECgQJBgABLgAECgkJJAAGAJIVAA==.Daenarea:BAABLgAECn8qAAIeAAkJPxXZCABdAgAeAAkJPxXZCABdAgAAAA==.Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.Darksasuke:BAAALgADCgEJAQAAAA==.Darkwater:BAAALgADCgkJCQAAAA==.Dazinth:BAAALgAECgEJAQAAAA==.Dazînth:BAAALgAECgEJAgAAAA==.',
De='Deets:BAABLgAECn82AAIEAAkJSh9mFACvAgAEAAkJSh9mFACvAgAAAA==.Defoy:BAABLgAECn8WAAMLAAYJJhleGQDkAAALAAYJ4xZeGQDkAAAEAAQJZxCK6QB7AAAAAA==.Demona:BAABLgAECn8yAAMDAAkJDQ6aDAB2AQADAAkJDQ6aDAB2AQACAAYJWgPM3gCcAAAAAA==.Demonduckz:BAAALgAECgEJAgAAAA==.Demonicfates:BAABLgAECn8bAAIdAAgJWA7ZJQBLAQAdAAgJWA7ZJQBLAQAAAA==.Derffy:BAABLgAECn8tAAIfAAkJ8SH1AQAVAwAfAAkJ8SH1AQAVAwAAAA==.Descalabrada:BAAALgAECgYJDAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Di='Distol:BAAALgAECgUJCAAAAA==.',
Dm='Dmt:BAABLgAECn8iAAIgAAgJBh0OGgBHAgAgAAgJBh0OGgBHAgAAAA==.',
Do='Dotemdown:BAAALgAECgIJAgAAAA==.',
Dr='Dragonborn:BAAALgAECgEJAQAAAA==.Draiara:BAAALgAECgMJAwAAAA==.Dropdeadqtx:BAAALgAECgYJDQAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJHwABALwiAA==.Drpeppers:BAABLgAECn8sAAMRAAkJLAspRwBzAQARAAkJLAspRwBzAQAXAAEJAAAUPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathknight:BAAALgAECgEJAQABLgAFFAEJAQAJAAAAAA==.Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthadin:BAAALgAECgYJBgAAAA==.Earthling:BAAALgAECgUJDQAAAA==.',
Ec='Eclair:BAABLgAECn81AAMbAAkJkhS0LgD7AQAbAAkJkhS0LgD7AQAFAAYJ5BjLOABUAQAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgAECgQJBAABLgAECgkJLAASAE8eAA==.',
El='Eleysia:BAAALgAECgcJBwAAAA==.Elf:BAAALgAECgYJBwABLgAECgkJBgAJAAAAAA==.Elhayn:BAAALgAECgUJBwAAAA==.Elmore:BAAALgAECgQJBAAAAA==.Elmos:BAABLgAECn8zAAIcAAkJVh9qAADNAQAcAAkJVh9qAADNAQAAAA==.',
Er='Erestadh:BAAALgAECgEJAgABLgAECgcJHAAMAFwMAA==.Eris:BAAALgADCgcJBwAAAA==.',
Eu='Eucalyptus:BAAALgAECgEJAgAAAA==.',
Ev='Evilchuckle:BAAALgADCgcJBwAAAA==.Evilmonkeymg:BAEALgAECgEJAQABLgAECgkJGQAFACceAA==.Evilmonkeysh:BAEBLgAECn8ZAAMFAAkJJx5eHAAvAgAFAAkJJx5eHAAvAgAbAAcJQQvdTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECgkJGQAFACceAA==.',
Ex='Exto:BAAALgAECgMJBAABLgAECgQJBAAJAAAAAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8xAAMdAAkJthYaEgALAgAdAAkJthYaEgALAgAhAAYJngqoGQDQAAAAAA==.',
Fa='Fatehunter:BAAALgADCggJCAAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgcJEgABLgAECggJDgAJAAAAAA==.Fenrísulfr:BAAALgAECgUJCAABLgAECggJDgAJAAAAAA==.Ferg:BAAALgAECgYJCQABLgAECgkJOQAMAE4jAA==.Fergis:BAABLgAECn85AAIMAAkJTiP1DAASAwAMAAkJTiP1DAASAwAAAA==.Fergle:BAAALgAECgYJEgAAAA==.Fetchme:BAAALgAECgQJBwAAAA==.Fetchyou:BAAALgADCggJDgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8dAAMQAAkJsBc8EgDoAQAQAAkJ+xY8EgDoAQAHAAcJ0RVDCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECggJEQAAAA==.',
Fr='Freecaster:BAAALgAECgMJAwAAAA==.Frostybeary:BAAALgAECgkJCQAAAA==.Frostymonk:BAABLgAECn8ZAAMgAAcJOQmiZADpAAAgAAcJOQmiZADpAAAcAAEJVAYItwAhAAAAAA==.Frozenwaffle:BAAALgAECgYJEgABLgAECgkJJgAiAJkhAA==.',
Fu='Furryben:BAAALgAECgMJAwAAAA==.',
['Fá']='Fállen:BAAALgADCgYJDQAAAA==.',
Ga='Galeste:BAAALgAECgUJCQAAAA==.',
Gh='Ghidorahh:BAAALgAFFAEJAQAAAA==.',
Gi='Gigem:BAABLgAECn8UAAIEAAcJWhxLQgDbAQAEAAcJWhxLQgDbAQAAAA==.Girlshoon:BAAALgAECgIJAgAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQeAAkJkASTIwBcAQAeAAkJkASTIwBcAQAKAAUJ9gP/SgCoAAAjAAEJlQF3LAAYAAAAAA==.Glarious:BAAALgAECgYJEAABLgAECgkJGwAeAJAEAA==.',
Go='Golakuron:BAAALgADCgUJBQAAAA==.Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgcJEAAAAA==.Gredan:BAAALgAECgYJCAAAAA==.Greenwaffle:BAABLgAECn8mAAMiAAkJmSHnDACEAgAiAAkJmSHnDACEAgAPAAYJwBTCNQBmAQAAAA==.Grôg:BAAALgAECgkJDQAAAA==.',
Gu='Guldaniel:BAAALgAECgUJBgABLgAECgkJJAAGAJIVAA==.Guthx:BAABLgAECn8eAAIRAAkJzBjqIgAyAgARAAkJzBjqIgAyAgAAAA==.',
Ha='Harutah:BAAALgAECgQJBAAAAA==.Hazeran:BAAALgAECgMJBQAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgAJAAAAAA==.',
Ho='Holymolii:BAABLgAECn8pAAIOAAkJhBbdDgDVAQAOAAkJhBbdDgDVAQAAAA==.Hotcoffee:BAAALgAECgYJDgAAAA==.',
Hu='Huntermaster:BAABLgAECn8bAAQNAAgJFRf5IACUAQANAAcJwBf5IACUAQALAAUJRxiERABDAQAEAAEJEBKOLAE4AAABLgAECgkJNQAYAA8mAA==.',
Il='Ilulz:BAAALgADCgEJAQAAAA==.',
In='Incredabull:BAABLgAECn8fAAIYAAkJuRiEEQDSAQAYAAkJuRiEEQDSAQAAAA==.Intrepidz:BAAALgAECgEJAQABLgAECgkJJAAMABUYAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAABLgAECn8wAAIkAAkJ3xTOCADZAQAkAAkJ3xTOCADZAQAAAA==.Istayblunted:BAABLgAECn8fAAIOAAcJ6x8QEADEAQAOAAcJ6x8QEADEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDQAAAA==.',
Iw='Iwinwithhots:BAAALgAECgEJAgABLgAECgcJGAAGAIceAA==.',
Ja='Jacqualyn:BAAALgADCgMJAwAAAA==.',
Ji='Jiayerah:BAAALgAECgYJEAABLgAECggJLAAPAOcgAA==.Jinkuzo:BAABLgAECn8xAAIUAAkJIB+UCgCKAgAUAAkJIB+UCgCKAgAAAA==.Jinmu:BAABLgAECn80AAMSAAkJOxh9EgASAgASAAkJOxh9EgASAgAlAAEJJgtHKQAwAAAAAA==.',
Ju='Juggie:BAABLgAECn8vAAIPAAkJrhMtGgD5AQAPAAkJrhMtGgD5AQAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8pAAIlAAkJigviCwBxAQAlAAkJigviCwBxAQAAAA==.',
Ka='Kagami:BAAALgAECgIJAgAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAABLgAECn8XAAMCAAkJgRryKAA4AgACAAkJVhryKAA4AgADAAEJFBvWawA8AAAAAA==.Kanè:BAAALgAECgEJAQAAAA==.',
Ke='Keliez:BAAALgAFFAEJAgABLgAFFAcJIgARAFYOAA==.',
Kh='Khrodors:BAAALgADCgMJAwAAAA==.',
Ki='Kiannis:BAAALgADCgEJAQAAAA==.Kickerr:BAAALgAECggJEwABLgAECgkJDwAJAAAAAA==.Kickrr:BAAALgAECgkJDwAAAA==.Kikyo:BAAALgAECgEJAgAAAA==.Kirrby:BAAALgADCgEJAQAAAA==.',
Kl='Klodar:BAAALgAECgQJBAAAAA==.Klum:BAAALgAECgYJCgAAAA==.',
Kr='Krazee:BAAALgAECgEJAQAAAA==.Krotas:BAAALgAECgMJAwAAAA==.Krunkle:BAAALgAECgIJAwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgAECggJEQAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgAECgYJEAAAAA==.Lendela:BAAALgAECgUJDAAAAA==.',
Li='Liljugg:BAABLgAECn8UAAMPAAYJwglGRQDTAAAPAAYJwglGRQDTAAAiAAIJpgOHfgBAAAAAAA==.',
Lm='Lmaddk:BAAALgAECgIJAgAAAA==.',
Lo='Logi:BAAALgAECgMJAwAAAA==.Lor:BAAALgAECgQJBgAAAA==.Lostmana:BAAALgAECgYJDAAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Lu='Lunablade:BAAALgAECgEJAQAAAA==.',
Ly='Lygor:BAABLgAECn82AAIEAAkJpxMGNQAJAgAEAAkJpxMGNQAJAgAAAA==.Lyrasong:BAAALgADCgIJAgAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJHwABALwiAA==.',
Ma='Maelle:BAAALgADCgYJBwAAAA==.Magnifico:BAAALgAECgUJCgAAAA==.Majellan:BAAALgAECgQJCQAAAA==.Makrub:BAAALgAECggJDQAAAA==.Malystryix:BAAALgAECgQJBAAAAA==.Mandigosa:BAAALgAECgMJBAAAAA==.Marist:BAAALgAECgEJAwAAAA==.Marrius:BAAALgAECgEJAgAAAA==.Marsawn:BAABLgAECn8gAAMiAAkJERghFgAaAgAiAAkJERghFgAaAgAPAAMJYBg/SQDAAAAAAA==.',
Mc='Mcpeepants:BAACLgAFFH8IAAImAAQJaxdNCQAmAQAmAAQJaxdNCQAmAQAuAAQKfxQAAiYACQnsHlQEAK4CACYACQnsHlQEAK4CAAEuAAUUBAkNAAYAUiEA.',
Me='Meqi:BAABLgAECn8hAAMMAAgJqx1WQAAbAgAMAAgJqx1WQAAbAgAnAAEJDBcVDgBGAAAAAA==.',
Mi='Mikàsa:BAABLgAECn8mAAMNAAkJSBBXFgDvAQANAAkJSBBXFgDvAQALAAYJXwmaTgAVAQAAAA==.Minand:BAAALgAECgYJEQAAAA==.Mindlessness:BAABLgAECn8yAAIaAAkJ5yMDBgD/AgAaAAkJ5yMDBgD/AgAAAA==.Mineralelf:BAABLgAECn86AAIEAAkJxwxoUACxAQAEAAkJxwxoUACxAQAAAA==.Minichaos:BAABLgAECn8yAAMDAAkJ4Rj6AwBKAgADAAkJ4Rj6AwBKAgACAAQJgAYC3QCfAAAAAA==.Miriam:BAABLgAECn8eAAMoAAcJjAW6CgDZAAAoAAcJjAW6CgDZAAAMAAEJ9QJefAEiAAAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8fAAIBAAgJvCIpBwD5AgABAAgJvCIpBwD5AgAAAA==.',
Mo='Mojosavage:BAABLgAECn8YAAICAAcJ7gI62ACnAAACAAcJ7gI62ACnAAAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAgAAAA==.Moonblade:BAAALgAECgYJCwAAAA==.Mortshan:BAABLgAECn8bAAInAAkJRhZVAwDzAQAnAAkJRhZVAwDzAQAAAA==.Mournfull:BAAALgAECgEJBQAAAA==.',
My='Mysticalfox:BAAALgAECgQJBgAAAA==.',
Na='Nalfilas:BAAALgAECgUJDQAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgAECggJDQAAAA==.Nikru:BAABLgAFFH8FAAIOAAMJ5QZ2EgBnAAAOAAMJ5QZ2EgBnAAABLgAFFAcJIgARAFYOAA==.Ninok:BAABLgAECn8sAAIGAAkJGxXpRAD3AQAGAAkJGxXpRAD3AQAAAA==.',
No='Nornee:BAABLgAECn8rAAIbAAgJ4xDLSgCEAQAbAAgJ4xDLSgCEAQAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8dAAIfAAgJRR2WCgAWAgAfAAgJRR2WCgAWAgAAAA==.',
['Nà']='Nàtureswrath:BAAALgAECggJDQAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAABLgAECn8bAAMaAAgJ0xEiNgBwAQAaAAgJ0xEiNgBwAQAZAAEJ4wz6fgArAAAAAA==.',
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
Po='Pompompower:BAABLgAECn83AAIFAAkJ/Aq/AQDuAAAFAAkJ/Aq/AQDuAAAAAA==.Popple:BAABLgAECn8sAAIaAAkJ5xAeIwDaAQAaAAkJ5xAeIwDaAQAAAA==.Potential:BAACLgAFFH8MAAIUAAMJMB3WLAD2AAAUAAMJMB3WLAD2AAAuAAQKfysAAhQACQmvHScAAHYCABQACQmvHScAAHYCAAAA.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgUJEAAAAA==.Puggsly:BAAALgAECgEJBAABLgAECgkJJAAGAJIVAA==.Pugsta:BAAALgAECgQJBwABLgAECggJEgAJAAAAAA==.Pulpfiction:BAABLgAECn8yAAMoAAYJfwWQDQDvAAAoAAYJRAWQDQDvAAAMAAUJjQR4DAGaAAAAAA==.',
Py='Pyrocaster:BAAALgAECgQJBQAAAA==.',
Qa='Qaccy:BAABLgAECn8TAAIiAAcJqQ7eQAAMAQAiAAcJqQ7eQAAMAQAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAABLgAECn8bAAIaAAgJzhl+KQCzAQAaAAgJzhl+KQCzAQAAAA==.',
Ra='Radaghast:BAAALgAECgEJAQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Raoul:BAAALgAECgMJBQAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Regret:BAAALgAFFAEJAgABLgAFFAgJJwAhAG4WAA==.Reishirome:BAAALgAECgEJAQAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8eAAIXAAgJPSIZAwDlAgAXAAgJPSIZAwDlAgAAAA==.',
Rh='Rhaellia:BAAALgAECgcJDQAAAA==.Rhogar:BAAALgAECgMJBAAAAA==.Rhoke:BAAALgAECgQJAwAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8gAAIVAAkJpQZjOQAtAQAVAAkJpQZjOQAtAQAAAA==.Romeoz:BAAALgAECgUJBQAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAABLgAECn8UAAIEAAYJ5xPjewBIAQAEAAYJ5xPjewBIAQAAAA==.',
Ru='Rumincoke:BAAALgADCgkJEwAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAABLgAECn8sAAMPAAgJ5yBbCgDBAgAPAAgJ5yBbCgDBAgAWAAEJ6R+5aABdAAAAAA==.Saruma:BAAALgAECgQJAwAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwAJAAAAAA==.',
Sc='Scalygrob:BAAALgAECgkJEwAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8zAAIWAAkJ6RfYDgCBAgAWAAkJ6RfYDgCBAgAAAA==.Sellphie:BAAALgADCgcJCAAAAA==.',
Sh='Shadowhntr:BAAALgAECgYJCQAAAA==.Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shamehameha:BAAALgAFFAMJAwAAAA==.Shamonuu:BAAALgAECgEJAQAAAA==.Shavedussy:BAAALgADCgUJBQABLgAECgkJJAAGAJIVAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Siknes:BAAALgAECggJCwABLgAECgkJLAASAE8eAA==.Simmareth:BAAALgADCgcJBwAAAA==.Simpofmeerah:BAAALgAECgYJCAAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgYJDAAAAA==.',
Sl='Slargerita:BAAALgADCgcJBwAAAA==.',
Sm='Smallmoon:BAAALgAECgEJAQAAAA==.Smogcheck:BAACLgAFFH8TAAMeAAUJ/RSNGQD+AAAeAAQJSxGNGQD+AAAKAAMJDwbyXABhAAAuAAQKfyEAAx4ACQkOE2gbAK0BAB4ACQkOE2gbAK0BACMAAQl9CNM+ADQAAAAA.',
Sn='Snackcake:BAABLgAECn8oAAIRAAkJvBpdEwCwAgARAAkJvBpdEwCwAgAAAA==.Snakeoil:BAABLgAECn8cAAMFAAkJyh5HEABxAgAFAAkJyh5HEABxAgAbAAEJCgKR7QAiAAAAAA==.Snowsz:BAAALgAECgMJAwAAAA==.Snowws:BAABLgAECn8eAAITAAkJ9xozIQBOAgATAAkJ9xozIQBOAgAAAA==.',
So='Sortis:BAABLgAECn8kAAIMAAkJFRjeMwCjAgAMAAkJFRjeMwCjAgAAAA==.',
Sp='Spicebreff:BAABLgAFFH8GAAIeAAMJBwwfIgCTAAAeAAMJBwwfIgCTAAAAAA==.Spongerunner:BAABLgAECn8VAAICAAcJkxgoSwC5AQACAAcJkxgoSwC5AQAAAA==.Sprucetea:BAAALgADCgIJAwAAAA==.',
St='Steck:BAABLgAECn9EAAIEAAkJWhbILwAdAgAEAAkJWhbILwAdAgAAAA==.Strigo:BAABLgAFFH8OAAQNAAQJdRiuEwAuAQANAAQJCBiuEwAuAQAEAAEJtBy7IABfAAALAAEJnwy7KABKAAAAAA==.',
Su='Subway:BAAALgAECggJEAAAAA==.Sunbaby:BAABLgAECn8oAAIhAAgJnh6UBgAqAgAhAAgJnh6UBgAqAgAAAA==.',
['Sà']='Sàlís:BAAALgADCgkJDgAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8gAAIWAAkJdCBJBQD9AgAWAAkJdCBJBQD9AgAAAA==.Takhisoth:BAAALgADCgYJBgAAAA==.Talandaru:BAAALgAECgEJBAAAAA==.Talas:BAABLgAECn8zAAMEAAkJFh7cFQClAgAEAAkJFh7cFQClAgALAAUJswr3VwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Te='Temberle:BAAALgAECgQJBAABLgAECgkJOQADAMQQAA==.Temerald:BAAALgADCgkJCQAAAA==.Tevoran:BAAALgAECgYJEAAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thaelidari:BAAALgAECgkJDAAAAA==.Thieridan:BAAALgADCgIJBAAAAA==.Thrangus:BAAALgAECgIJAgABLgAFFAMJBQAIAMYdAA==.Thrann:BAACLgAFFH8FAAMIAAMJxh1qsQDBAAAIAAIJUyBqsQDBAAAHAAIJnBt3HACgAAAuAAQKfyAAAwcACQnrIvkJAOMBAAgABwmpIp86AE0CAAcABQmHI/kJAOMBAAAA.Thunderdex:BAACLgAFFH8UAAMTAAcJpBZDHwC9AQATAAcJpBZDHwC9AQAdAAEJ6ANKMQAzAAAuAAQKfx8AAhMACQl+HsgfAFYCABMACQl+HsgfAFYCAAAA.',
Ti='Tirium:BAAALgAECgcJCAABLgAFFAMJBgAeAAcMAA==.',
To='Togglesmith:BAAALgAECgYJDAAAAA==.Togglestein:BAAALgAECgYJEAAAAA==.Togglethorp:BAAALgAECgUJBQAAAA==.Togi:BAAALgADCgcJDQAAAA==.Totema:BAAALgAECgEJAQABLgAECgkJJAAGAJIVAA==.',
Tr='Trinitum:BAAALgAECgcJCwABLgAFFAMJBgAeAAcMAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Ud='Udderduckie:BAAALgAECgEJAgAAAA==.',
Um='Umaroth:BAAALgAECgYJBgABLgAECgkJMwAEABYeAA==.',
Un='Unfolrion:BAAALgADCgIJBAAAAA==.Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJCwAAAA==.Ursoconha:BAABLgAFFH8FAAMRAAQJoQpTVwBrAAARAAMJfQVTVwBrAAAXAAEJqR09MwBSAAABLgAFFAYJBgAMAIsYAA==.',
Va='Vaadboolin:BAAALgAECggJEgAAAA==.Vaadhands:BAAALgAECgEJAQAAAA==.Vaevicta:BAAALgAECgYJBgAAAA==.Vallius:BAABLgAECn8dAAISAAkJ5BKaGQDNAQASAAkJ5BKaGQDNAQAAAA==.Vanargandr:BAAALgAECggJDgAAAA==.',
Ve='Verðandi:BAAALgAECgIJAgAAAA==.',
Vo='Volcano:BAABLgAECn8bAAICAAkJIxo8KAA7AgACAAkJIxo8KAA7AgAAAA==.Volvox:BAAALgADCgEJAQAAAA==.Vonslarge:BAAALgADCgkJCQAAAA==.',
Vy='Vyxenn:BAABLgAECn82AAMbAAkJ0xbJIQBEAgAbAAkJ0xbJIQBEAgAFAAUJTQsEWADcAAAAAA==.',
Wa='Waffletoast:BAAALgADCgkJEQABLgAECgkJJgAiAJkhAA==.Wanders:BAABLgAECn8qAAMMAAkJIBqPJwB8AgAMAAkJIBqPJwB8AgAoAAYJLAmdCwAcAQAAAA==.Warlockk:BAAALgAECgUJCAAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Wc='Wckddreamer:BAAALgADCgEJAQAAAA==.',
We='Wenevella:BAAALgAECgIJAgAAAA==.',
Wu='Wurm:BAAALgAECgcJBwABLgAECgkJDQAJAAAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yejena:BAAALgAECgEJAgAAAA==.Yep:BAACLgAFFH8KAAIGAAQJVRjrMwBHAQAGAAQJVRjrMwBHAQAuAAQKfxsAAgYACQnwI4IKABMDAAYACQnwI4IKABMDAAAA.Yesenìa:BAAALgAECgYJBQAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zanderr:BAAALgADCgYJBgAAAA==.Zavia:BAAALgADCgYJDwAAAA==.Zazael:BAAALgAECgIJAgAAAA==.Zazreal:BAABLgAECn84AAQjAAkJgh0JAwB4AgAjAAkJgh0JAwB4AgAKAAMJ4Q9oSwClAAAeAAQJ7wIILQCCAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn85AAImAAkJ7gZ1FgBbAQAmAAkJ7gZ1FgBbAQAAAA==.Zillyanna:BAAALgAECggJEwAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zyper:BAAALgAECgYJDAAAAA==.Zywol:BAABLgAECn8mAAQVAAkJ5hgEFQApAgAVAAkJ5hgEFQApAgARAAMJlgbIpgB6AAAXAAEJjA8DegAqAAAAAA==.',
['Ër']='Ëresta:BAABLgAECn8cAAIMAAcJXAyToAA6AQAMAAcJXAyToAA6AQAAAA==.',
['Ðe']='Ðesire:BAAALgAECgYJCwAAAA==.Ðespair:BAACLgAFFH8QAAIiAAQJ/SC+DwBvAQAiAAQJ/SC+DwBvAQAuAAQKfzQABBYACQklICQKAJYCABYABwk9ISQKAJYCACIACQltH1MMAIsCAA8ABQmTGIxBAOYAAAAA.',
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
