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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Evoker-Augmentation','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Protection','Priest-Holy','DeathKnight-Blood','Druid-Restoration','Rogue-Subtlety','DemonHunter-Devourer','Druid-Balance','Priest-Discipline','Druid-Guardian','Warrior-Protection','Warrior-Arms','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','DemonHunter-Havoc','Evoker-Preservation','Druid-Feral','Monk-Mistweaver','DemonHunter-Vengeance','Priest-Shadow','Evoker-Devastation','Warlock-Affliction','Monk-Brewmaster','Rogue-Assassination','Shaman-Enhancement','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abaddón:BAAALgAECgEJAQABLgAECggJHwABALwiAA==.Abfuscatedd:BAABLgAECn8iAAMCAAkJShMZPgDeAQACAAkJShMZPgDeAQADAAEJAAARgAATAAAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJFgAEAPoYAA==.Acidrain:BAABLgAECn85AAIFAAkJMyEqBwDfAgAFAAkJMyEqBwDfAgAAAA==.Acmiax:BAABLgAECn8fAAMGAAkJmRMrUgDIAQAGAAkJmRMrUgDIAQABAAUJugutUgDiAAAAAA==.',
Ad='Adar:BAAALgAECgQJBAAAAA==.',
Ae='Aep:BAABLgAECn8ZAAMHAAgJ+hJVEgBBAQAHAAYJRRRVEgBBAQAIAAcJ/gyBjgBAAQABLgAECgMJAwAJAAAAAA==.',
Ah='Ahkari:BAAALgAECgEJAQABLgAFFAMJBgAKAJAXAA==.Ahrmanhamma:BAACLgAFFH8NAAIGAAQJUiH1GACOAQAGAAQJUiH1GACOAQAuAAQKfxoAAgYACQkvIvwQANUCAAYACQkvIvwQANUCAAAA.Ahu:BAABLgAECn8nAAMEAAgJsRcuMADwAQAEAAgJsRcuMADwAQALAAMJZAQjcwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgQJBQAAAA==.Airotciv:BAAALgAECgEJAQAAAA==.',
Al='Al:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgQJEgAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAACLgAFFH8JAAIEAAUJ8AJ5UQDwAAAEAAUJ8AJ5UQDwAAAuAAQKf0QAAwQACQm7Efs4AO8BAAQACQl7Efs4AO8BAAsACAmfDB41AJUBAAAA.Alerus:BAAALgAECgEJAQAAAA==.Alexander:BAABLgAECn8eAAIMAAkJixrzJgDXAgAMAAkJixrzJgDXAgAAAA==.Alexijones:BAABLgAECn8cAAINAAkJJQ8mGQDSAQANAAkJJQ8mGQDSAQAAAA==.Allaria:BAAALgAECgcJCgAAAA==.',
Am='Ambassador:BAABLgAECn8eAAIOAAkJlBduCwACAgAOAAkJlBduCwACAgAAAA==.Amoondai:BAACLgAFFH8cAAIPAAQJpCIhCwB9AQAPAAQJpCIhCwB9AQAuAAQKf0UAAg8ACQn2JG4BAKMDAA8ACQn2JG4BAKMDAAAA.',
An='Analytics:BAAALgADCgYJBgAAAA==.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn8/AAMQAAkJUiJmBADoAgAQAAkJUiJmBADoAgAIAAYJ7wNo0gDcAAAAAA==.Apolyon:BAABLgAECn8mAAIRAAkJLSG9CAAlAwARAAkJLSG9CAAlAwAAAA==.',
Ar='Araon:BAAALgAECgYJBgAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
As='Asheraah:BAAALgAECgQJBQAAAA==.',
At='Atroxz:BAAALgADCgcJCAAAAA==.',
Au='Aurén:BAAALgAECgYJCgAAAA==.',
Ba='Bacstabath:BAABLgAECn8sAAISAAkJTx4XBgAvAwASAAkJTx4XBgAvAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAFFAQJDQAGAFIhAA==.Banshee:BAABLgAECn8eAAITAAkJ1B88EwCeAgATAAkJ1B88EwCeAgAAAA==.Baychan:BAAALgAECgcJCAAAAA==.',
Be='Becca:BAABLgAECn85AAIOAAkJkBZ9CwABAgAOAAkJkBZ9CwABAgAAAA==.Berries:BAAALgAECgEJAQAAAA==.',
Bi='Bigaraon:BAAALgADCgIJAgAAAA==.Bigdamaj:BAABLgAECn81AAMHAAkJEhniBgAfAgAHAAkJcxfiBgAfAgAIAAkJBhQyTwDOAQAAAA==.Birbdormu:BAAALgAECgQJBQABLgAECgkJOAAUANIeAA==.',
Bl='Blakdemon:BAAALgADCgUJBQABLgAFFAMJBAAJAAAAAA==.Bloodiblind:BAAALgAECgQJCQAAAA==.Bloodios:BAABLgAECn80AAIQAAkJNh/wBgCmAgAQAAkJNh/wBgCmAgAAAA==.Blázé:BAAALgADCgEJAQAAAA==.',
Bo='Bobbardment:BAAALgAECgYJBgAAAA==.Bobin:BAAALgAECgMJBAABLgAECgkJHQAVAOwQAA==.Bobinforapl:BAABLgAECn8dAAIVAAkJ7BCuIAC6AQAVAAkJ7BCuIAC6AQAAAA==.Bombadil:BAABLgAECn9HAAIVAAkJhgdSKACCAQAVAAkJhgdSKACCAQAAAA==.',
Br='Bribage:BAABLgAECn84AAQUAAkJ0h7pCwCNAgAUAAkJ/R3pCwCNAgAWAAYJahp+EQDCAQARAAIJqRtRiACdAAAAAA==.Brolavski:BAAALgAECgEJAQABLgAECgcJEAAJAAAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgUJBwABLgAECgcJCgAJAAAAAA==.Budderwar:BAABLgAECn81AAQXAAkJDyYeAgAlAwAXAAkJDyYeAgAlAwAYAAcJkRt/EADfAQAZAAMJvw4KhwCjAAAAAA==.Buggz:BAAALgAECgQJBgAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgIJBQAAAA==.',
['Bà']='Bàdmofos:BAAALgAECgQJBwAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.Calvis:BAAALgADCgcJDAAAAA==.',
Cb='Cbreezy:BAAALgAECgQJBgAAAA==.',
Ce='Celerydk:BAAALgAECgkJDwAAAA==.Celhealz:BAAALgAECgIJAgAAAA==.Celjska:BAAALgAECgUJBgAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chikñ:BAABLgAECn8aAAMFAAgJDg7kQABGAQAFAAYJjw/kQABGAQAaAAgJ7gm4WQBBAQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.Chuanthu:BAAALgAECgYJBgAAAA==.Chug:BAAALgAECgEJAQAAAA==.',
Ci='Cinderspella:BAAALgAECgIJAgAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8zAAIbAAkJdiXoAQBPAwAbAAkJdiXoAQBPAwAAAA==.',
Co='Cocoredbull:BAABLgAECn8dAAIWAAkJdw7pIQAsAQAWAAkJdw7pIQAsAQAAAA==.Corrail:BAAALgAECgYJDQAAAA==.Correin:BAABLgAECn8fAAIcAAkJbw/XIABeAQAcAAkJbw/XIABeAQAAAA==.',
Cr='Craszhin:BAABLgAECn8kAAIUAAkJqRCYHgDGAQAUAAkJqRCYHgDGAQAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn81AAIMAAkJIwxnaAClAQAMAAkJIwxnaAClAQAAAA==.',
Da='Dadeb:BAAALgAECgQJBAABLgAECgkJHwAGAJkTAA==.Daenarea:BAABLgAECn8kAAIdAAkJohSPCQBGAgAdAAkJohSPCQBGAgAAAA==.Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.Darksasuke:BAAALgADCgEJAQAAAA==.Darkwater:BAAALgADCgkJCQAAAA==.Dazinth:BAAALgAECgEJAQAAAA==.Dazînth:BAAALgAECgEJAQAAAA==.',
De='Deets:BAABLgAECn82AAIEAAkJSh8DEgC2AgAEAAkJSh8DEgC2AgAAAA==.Defoy:BAABLgAECn8WAAMLAAYJJhkiGADlAAALAAYJ4xYiGADlAAAEAAQJZxCQ2wB+AAAAAA==.Demona:BAABLgAECn8yAAMDAAkJDQ5jCwB7AQADAAkJDQ5jCwB7AQACAAYJWgNS1ACkAAAAAA==.Demonduckz:BAAALgAECgEJAgAAAA==.Demonicfates:BAABLgAECn8bAAIcAAgJWA7BIgBPAQAcAAgJWA7BIgBPAQAAAA==.Derffy:BAABLgAECn8qAAIeAAgJ7SFVBACxAgAeAAgJ7SFVBACxAgAAAA==.Descalabrada:BAAALgAECgYJDAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Di='Distol:BAAALgAECgUJCAAAAA==.',
Dm='Dmt:BAABLgAECn8iAAIfAAgJBh0JGABGAgAfAAgJBh0JGABGAgAAAA==.',
Do='Dotemdown:BAAALgAECgIJAgAAAA==.',
Dr='Dragonborn:BAAALgADCgEJAQAAAA==.Draiara:BAAALgAECgMJAwAAAA==.Dropdeadqtx:BAAALgAECgYJDQAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJHwABALwiAA==.Drpeppers:BAABLgAECn8sAAMRAAkJLAs2RAB2AQARAAkJLAs2RAB2AQAWAAEJAAAUPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthling:BAAALgAECgUJDQAAAA==.',
Ec='Eclair:BAABLgAECn81AAMaAAkJkhTPKwD8AQAaAAkJkhTPKwD8AQAFAAYJ5BhrNQBVAQAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgAECgQJBAABLgAECgkJLAASAE8eAA==.',
El='Eleysia:BAAALgAECgcJBwAAAA==.Elf:BAAALgAECgYJBwABLgAECgkJAwAJAAAAAA==.Elhayn:BAAALgAECgUJBwAAAA==.Elmore:BAAALgAECgQJBAAAAA==.Elmos:BAABLgAECn8tAAIbAAkJ7B4NCAD5AgAbAAkJ7B4NCAD5AgAAAA==.',
Er='Erestadh:BAAALgAECgEJAgABLgAECgcJHAAMAFwMAA==.Eris:BAAALgADCgcJBwAAAA==.',
Eu='Eucalyptus:BAAALgAECgEJAgAAAA==.',
Ev='Evilmonkeymg:BAEALgAECgEJAQABLgAECgkJGQAFACceAA==.Evilmonkeysh:BAEBLgAECn8ZAAMFAAkJJx5eHAAvAgAFAAkJJx5eHAAvAgAaAAcJQQvdTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECgkJGQAFACceAA==.',
Ex='Exto:BAAALgAECgMJBAABLgAECgQJBAAJAAAAAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8xAAMcAAkJthaWEAAPAgAcAAkJthaWEAAPAgAgAAYJngodGADQAAAAAA==.',
Fa='Fatehunter:BAAALgADCggJCAAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgcJEgABLgAECggJDgAJAAAAAA==.Fenrísulfr:BAAALgAECgMJAwABLgAECggJDgAJAAAAAA==.Ferg:BAAALgAECgYJCQABLgAECgkJOQAMAE4jAA==.Fergis:BAABLgAECn85AAIMAAkJTiNzCwAYAwAMAAkJTiNzCwAYAwAAAA==.Fergle:BAAALgAECgYJEgAAAA==.Fetchme:BAAALgAECgQJBwAAAA==.Fetchyou:BAAALgADCggJDgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8dAAMQAAkJsBc8EgDoAQAQAAkJ+xY8EgDoAQAHAAcJ0RVDCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECggJEQAAAA==.',
Fr='Freecaster:BAAALgAECgMJAwAAAA==.Frostybeary:BAAALgAECgkJCQAAAA==.Frostymonk:BAABLgAECn8ZAAMfAAcJOQnAWwDoAAAfAAcJOQnAWwDoAAAbAAEJVAadqwAhAAAAAA==.Frozenwaffle:BAAALgAECgYJEgABLgAECgkJJgAhAJkhAA==.',
Fu='Furryben:BAAALgAECgMJAwAAAA==.',
['Fá']='Fállen:BAAALgADCgYJCgAAAA==.',
Ga='Galeste:BAAALgAECgUJCQAAAA==.',
Gh='Ghidorahh:BAAALgAFFAEJAQAAAA==.',
Gi='Gigem:BAABLgAECn8UAAIEAAcJWhwKPQDhAQAEAAcJWhwKPQDhAQAAAA==.Girlshoon:BAAALgAECgEJAQAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQdAAkJkASTIwBcAQAdAAkJkASTIwBcAQAKAAUJ9gP/SgCoAAAiAAEJlQETKgAYAAAAAA==.Glarious:BAAALgAECgYJEAABLgAECgkJGwAdAJAEAA==.',
Go='Golakuron:BAAALgADCgUJBQAAAA==.Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgcJEAAAAA==.Gredan:BAAALgAECgYJCAAAAA==.Greenwaffle:BAABLgAECn8mAAMhAAkJmSH5CwCKAgAhAAkJmSH5CwCKAgAPAAYJwBTCNQBmAQAAAA==.Grôg:BAAALgAECgkJDQAAAA==.',
Gu='Guldaniel:BAAALgAECgQJBQABLgAECgkJHwAGAJkTAA==.Guthx:BAABLgAECn8eAAIRAAkJzBhQIQA0AgARAAkJzBhQIQA0AgAAAA==.',
Ha='Harutah:BAAALgAECgQJBAAAAA==.Hazeran:BAAALgAECgMJBQAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgAJAAAAAA==.',
Ho='Holymolii:BAABLgAECn8pAAIOAAkJhBbYDQDZAQAOAAkJhBbYDQDZAQAAAA==.Hotcoffee:BAAALgAECgYJDgAAAA==.',
Hu='Huntermaster:BAABLgAECn8bAAQNAAgJFRczHwCeAQANAAcJwBczHwCeAQALAAUJRxiERABDAQAEAAEJEBJGHAE4AAABLgAECgkJNQAXAA8mAA==.',
Il='Ilulz:BAAALgADCgEJAQAAAA==.',
In='Incredabull:BAABLgAECn8cAAIXAAgJZhlQEADYAQAXAAgJZhlQEADYAQAAAA==.Intrepidz:BAAALgAECgEJAQABLgAECgkJJAAMABUYAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAABLgAECn8wAAIjAAkJ3xTqBwDcAQAjAAkJ3xTqBwDcAQAAAA==.Istayblunted:BAABLgAECn8eAAIOAAcJxx8QEADEAQAOAAcJxx8QEADEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDQAAAA==.',
Iw='Iwinwithhots:BAAALgAECgEJAgABLgAECgcJGAAGAIceAA==.',
Ji='Jiayerah:BAAALgAECgQJCgABLgAECggJKgAPAOcgAA==.Jinkuzo:BAABLgAECn8xAAIkAAkJIB/jCQCNAgAkAAkJIB/jCQCNAgAAAA==.Jinmu:BAABLgAECn80AAMSAAkJOxgmEQAUAgASAAkJOxgmEQAUAgAlAAEJJgs3JwAwAAAAAA==.',
Ju='Juggie:BAABLgAECn8pAAIPAAkJwRHlHQDIAQAPAAkJwRHlHQDIAQAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8pAAIlAAkJigtQCwByAQAlAAkJigtQCwByAQAAAA==.',
Ka='Kagami:BAAALgAECgIJAgAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAABLgAECn8XAAMCAAkJgRrsJgA8AgACAAkJVhrsJgA8AgADAAEJFBvWawA8AAAAAA==.',
Ke='Keliez:BAAALgAFFAEJAgABLgAFFAcJGwARAJINAA==.',
Kh='Khrodors:BAAALgADCgMJAwAAAA==.',
Ki='Kiannis:BAAALgADCgEJAQAAAA==.Kickerr:BAAALgAECggJEwABLgAECgkJJAAkANQaAA==.Kickrr:BAAALgAECgYJBgABLgAECgkJJAAkANQaAA==.Kikyo:BAAALgAECgEJAQAAAA==.Kirrby:BAAALgADCgEJAQAAAA==.',
Kl='Klodar:BAAALgAECgQJBAAAAA==.Klum:BAAALgAECgYJCgAAAA==.',
Kr='Krazee:BAAALgAECgEJAQAAAA==.Krotas:BAAALgAECgMJAwAAAA==.Krunkle:BAAALgAECgIJAwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgAECgcJCAAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgAECgQJCgAAAA==.Lendela:BAAALgAECgUJDAAAAA==.',
Li='Liljugg:BAAALgAECgYJDwAAAA==.',
Lm='Lmaddk:BAAALgAECgIJAgAAAA==.',
Lo='Logi:BAAALgAECgMJAwAAAA==.Lor:BAAALgAECgQJBgAAAA==.Lostmana:BAAALgAECgQJBgAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Lu='Lunablade:BAAALgAECgEJAQAAAA==.',
Ly='Lygor:BAABLgAECn81AAIEAAkJpxNxMQALAgAEAAkJpxNxMQALAgAAAA==.Lyrasong:BAAALgADCgIJAgAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJHwABALwiAA==.',
Ma='Maelle:BAAALgADCgYJBQAAAA==.Magnifico:BAAALgAECgUJBgAAAA==.Majellan:BAAALgAECgQJCQAAAA==.Makrub:BAAALgAECggJDQAAAA==.Malystryix:BAAALgAECgQJBAAAAA==.Mandigosa:BAAALgAECgMJBAAAAA==.Marist:BAAALgAECgEJAwAAAA==.Marrius:BAAALgAECgEJAgAAAA==.Marsawn:BAABLgAECn8gAAMhAAkJERhMFAAlAgAhAAkJERhMFAAlAgAPAAMJYBjkRQDBAAAAAA==.',
Mc='Mcpeepants:BAACLgAFFH8IAAImAAQJaxeFBwAzAQAmAAQJaxeFBwAzAQAuAAQKfxQAAiYACQnsHuQDALMCACYACQnsHuQDALMCAAEuAAUUBAkNAAYAUiEA.',
Me='Meqi:BAABLgAECn8fAAMMAAgJiB3vPwAWAgAMAAgJiB3vPwAWAgAnAAEJDBcVDgBGAAAAAA==.',
Mi='Mikàsa:BAABLgAECn8mAAMNAAkJSBC7FAD7AQANAAkJSBC7FAD7AQALAAYJXwmaTgAVAQAAAA==.Minand:BAAALgAECgYJEQAAAA==.Mindlessness:BAABLgAECn8yAAIZAAkJ5yMvBQAGAwAZAAkJ5yMvBQAGAwAAAA==.Mineralelf:BAABLgAECn86AAIEAAkJxwxqSQC5AQAEAAkJxwxqSQC5AQAAAA==.Minichaos:BAABLgAECn8vAAMDAAgJ4BkXBQAVAgADAAgJ4BkXBQAVAgACAAQJgAbT0wClAAAAAA==.Miriam:BAABLgAECn8dAAIoAAcJjAXDCQDeAAAoAAcJjAXDCQDeAAAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8fAAIBAAgJvCIpBwD5AgABAAgJvCIpBwD5AgAAAA==.',
Mo='Mojosavage:BAABLgAECn8YAAICAAcJ7gKYzwCsAAACAAcJ7gKYzwCsAAAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAgAAAA==.Moonblade:BAAALgAECgYJCwAAAA==.Mortshan:BAABLgAECn8bAAInAAkJRhbpAgD4AQAnAAkJRhbpAgD4AQAAAA==.Mournfull:BAAALgAECgEJBAAAAA==.',
My='Mysticalfox:BAAALgAECgQJBgAAAA==.',
Na='Nalfilas:BAAALgAECgUJDQAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgAECggJDQAAAA==.Nikru:BAABLgAFFH8FAAIOAAMJ5QYLEABxAAAOAAMJ5QYLEABxAAABLgAFFAcJGwARAJINAA==.Ninok:BAABLgAECn8sAAIGAAkJGxVbQAD7AQAGAAkJGxVbQAD7AQAAAA==.',
No='Nocturnous:BAAALgAECgEJAQAAAA==.Nornee:BAABLgAECn8rAAIaAAgJ4xDgRgCFAQAaAAgJ4xDgRgCFAQAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8dAAIeAAgJRR3NCQAXAgAeAAgJRR3NCQAXAgAAAA==.',
['Nà']='Nàtureswrath:BAAALgAECgcJCwAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAABLgAECn8bAAMZAAgJ0xEZMgB8AQAZAAgJ0xEZMgB8AQAYAAEJ4wwddgArAAAAAA==.',
Ol='Ollïee:BAAALgAECgYJBgAAAA==.',
Op='Oprawyndfury:BAAALgAECggJEAAAAA==.',
Or='Orceo:BAABLgAECn8rAAIEAAkJACTIBQAxAwAEAAkJACTIBQAxAwAAAA==.Orkreghar:BAAALgAECgIJBAAAAA==.',
Os='Osaro:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgAECgIJAgAAAA==.',
Ow='Ownlyshamz:BAAALgADCgMJAwABLgAFFAMJAwAJAAAAAA==.',
Ox='Oxcanor:BAAALgAECgEJAQAAAA==.',
Pa='Patches:BAAALgAECgUJBwABLgAECggJHwABALwiAA==.Patrick:BAAALgAECgQJBAAAAA==.',
Pe='Pepsipoutine:BAABLgAECn8WAAICAAYJmB+9TgDcAQACAAYJmB+9TgDcAQAAAA==.Petiterage:BAAALgADCggJCwAAAA==.',
Pi='Pindapind:BAAALgADCgMJBAABLgAECgkJNQAXAA8mAA==.Pindapinda:BAAALgAECggJDAABLgAECgkJNQAXAA8mAA==.',
Pl='Plaguexion:BAAALgADCgQJBgAAAA==.',
Po='Pompompower:BAABLgAECn8xAAIFAAkJGQjnOwA2AQAFAAkJGQjnOwA2AQAAAA==.Popple:BAABLgAECn8sAAIZAAkJ5xBSIADnAQAZAAkJ5xBSIADnAQAAAA==.Potential:BAACLgAFFH8MAAIkAAMJMB3LKAD8AAAkAAMJMB3LKAD8AAAuAAQKfyMAAiQACQkJGnwOAEgCACQACQkJGnwOAEgCAAAA.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgUJEAAAAA==.Puggsly:BAAALgAECgEJBAABLgAECgkJHwAGAJkTAA==.Pugsta:BAAALgAECgQJBwABLgAECggJEgAJAAAAAA==.Pulpfiction:BAABLgAECn8yAAMoAAYJfwWQDQDvAAAoAAYJRAWQDQDvAAAMAAUJjQSDAAGhAAAAAA==.',
Py='Pyrocaster:BAAALgAECgQJBQAAAA==.',
Qa='Qaccy:BAABLgAECn8SAAIhAAcJxQybPAAXAQAhAAcJxQybPAAXAQAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAABLgAECn8bAAIZAAgJzhmLJwC3AQAZAAgJzhmLJwC3AQAAAA==.',
Ra='Radaghast:BAAALgAECgEJAQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Raoul:BAAALgAECgMJAwAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Regret:BAAALgAFFAEJAgABLgAFFAgJJwAgAG4WAA==.Reishirome:BAAALgAECgEJAQAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8eAAIWAAgJPSIZAwDlAgAWAAgJPSIZAwDlAgAAAA==.',
Rh='Rhaellia:BAAALgAECgcJCQAAAA==.Rhogar:BAAALgAECgMJBAAAAA==.Rhoke:BAAALgAECgMJAwAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8fAAIUAAkJjgbINQAxAQAUAAkJjgbINQAxAQAAAA==.Romeoz:BAAALgADCgEJAQAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAAALgAECgYJEwAAAA==.',
Ru='Rumincoke:BAAALgADCgkJEwAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAABLgAECn8qAAIPAAgJ5yBnCQDFAgAPAAgJ5yBnCQDFAgAAAA==.Saruma:BAAALgAECgQJAwAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwAJAAAAAA==.',
Sc='Scalygrob:BAAALgAECgkJEwAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8zAAIVAAkJ6RfEDQCGAgAVAAkJ6RfEDQCGAgAAAA==.Sellphie:BAAALgADCgcJCAAAAA==.',
Sh='Shadowhntr:BAAALgAECgYJCAAAAA==.Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shamehameha:BAAALgAECggJCAAAAA==.Shavedussy:BAAALgADCgUJBQABLgAECgkJHwAGAJkTAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Siknes:BAAALgAECggJCAABLgAECgkJLAASAE8eAA==.Simmareth:BAAALgADCgcJBwAAAA==.Simpofmeerah:BAAALgAECgYJCAAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgYJDAAAAA==.',
Sl='Slargerita:BAAALgADCgcJBwAAAA==.',
Sm='Smallmoon:BAAALgAECgEJAQAAAA==.Smogcheck:BAACLgAFFH8RAAMdAAQJSxGFFwAGAQAdAAQJSxGFFwAGAQAKAAEJ4gO/YwAzAAAuAAQKfyEAAx0ACQkOE2gbAK0BAB0ACQkOE2gbAK0BACIAAQl9CNM+ADQAAAAA.',
Sn='Snackcake:BAABLgAECn8oAAIRAAkJvBpgEgCxAgARAAkJvBpgEgCxAgAAAA==.Snakeoil:BAABLgAECn8cAAMFAAkJyh4JDwB0AgAFAAkJyh4JDwB0AgAaAAEJCgL+3gAiAAAAAA==.Snowsz:BAAALgAECgMJAwAAAA==.Snowws:BAABLgAECn8eAAITAAkJ9xp6HwBNAgATAAkJ9xp6HwBNAgAAAA==.',
So='Sortis:BAABLgAECn8kAAIMAAkJFRjeMwCjAgAMAAkJFRjeMwCjAgAAAA==.',
Sp='Spicebreff:BAAALgAFFAMJAwAAAA==.Spongerunner:BAAALgAECgcJDwAAAA==.Sprucetea:BAAALgADCgIJAwAAAA==.',
St='Steck:BAABLgAECn87AAIEAAkJWhYbLQAdAgAEAAkJWhYbLQAdAgAAAA==.Strigo:BAABLgAFFH8OAAQNAAQJdRiTEQAuAQANAAQJCBiTEQAuAQAEAAEJtBy7IABfAAALAAEJnwy7KABKAAAAAA==.',
Su='Subway:BAAALgAECggJEAAAAA==.Sunbaby:BAABLgAECn8oAAIgAAgJnh4YBgArAgAgAAgJnh4YBgArAgAAAA==.',
['Sà']='Sàlís:BAAALgADCgkJDgAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8gAAIVAAkJdCBJBQD9AgAVAAkJdCBJBQD9AgAAAA==.Takhisoth:BAAALgADCgYJBgAAAA==.Talandaru:BAAALgAECgEJAwAAAA==.Talas:BAABLgAECn8yAAMEAAkJFh6vFACiAgAEAAkJFh6vFACiAgALAAUJswr3VwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Te='Temberle:BAAALgAECgMJAwABLgAECgkJOQADAMQQAA==.Temerald:BAAALgADCgkJCQAAAA==.Tevoran:BAAALgAECgYJEAAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thaelidari:BAAALgAECgkJDAAAAA==.Thieridan:BAAALgADCgIJBAAAAA==.Thrangus:BAAALgAECgIJAgABLgAECgkJIAAHAOsiAA==.Thrann:BAABLgAECn8gAAMHAAkJ6yLzCADoAQAIAAcJqSKfOgBNAgAHAAUJhyPzCADoAQAAAA==.Thunderdex:BAACLgAFFH8NAAMTAAcJpBaaGADJAQATAAcJpBaaGADJAQAcAAEJ6AMyKwAzAAAuAAQKfx8AAhMACQl+HuwdAFcCABMACQl+HuwdAFcCAAAA.',
Ti='Tirium:BAAALgAECgcJCAABLgAFFAMJAwAJAAAAAA==.',
To='Togglesmith:BAAALgAECgYJBwAAAA==.Togglestein:BAAALgAECgYJCwAAAA==.Togglethorp:BAAALgAECgUJBQAAAA==.Togi:BAAALgADCgcJDQAAAA==.',
Tr='Trinitum:BAAALgAECgcJCwABLgAFFAMJAwAJAAAAAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Ud='Udderduckie:BAAALgAECgEJAgAAAA==.',
Un='Unfolrion:BAAALgADCgIJBAAAAA==.Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJCwAAAA==.Ursoconha:BAAALgAFFAQJBAABLgAFFAYJBgAMAIsYAA==.',
Va='Vaadboolin:BAAALgAECggJEgAAAA==.Vaevicta:BAAALgADCgYJBgAAAA==.Vallius:BAABLgAECn8dAAISAAkJ5BLvFwDOAQASAAkJ5BLvFwDOAQAAAA==.Vanargandr:BAAALgAECggJDgAAAA==.',
Ve='Verðandi:BAAALgAECgIJAgAAAA==.',
Vo='Volcano:BAABLgAECn8bAAICAAkJIxqlJQBCAgACAAkJIxqlJQBCAgAAAA==.Volvox:BAAALgADCgEJAQAAAA==.Vonslarge:BAAALgADCgkJCQAAAA==.',
Vy='Vyxenn:BAABLgAECn82AAMaAAkJ0xajHwBFAgAaAAkJ0xajHwBFAgAFAAUJTQuCUgDdAAAAAA==.',
Wa='Waffletoast:BAAALgADCgkJEQABLgAECgkJJgAhAJkhAA==.Wanders:BAABLgAECn8qAAMMAAkJIBrFJACCAgAMAAkJIBrFJACCAgAoAAYJLAmdCwAcAQAAAA==.Warlockk:BAAALgAECgQJBQAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Wc='Wckddreamer:BAAALgADCgEJAQAAAA==.',
Wu='Wurm:BAAALgAECgcJBwABLgAECgkJDQAJAAAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yep:BAACLgAFFH8KAAIGAAQJVRhuKwBMAQAGAAQJVRhuKwBMAQAuAAQKfxsAAgYACQnwIykJABcDAAYACQnwIykJABcDAAAA.Yesenìa:BAAALgAECgUJBAAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zavia:BAAALgADCgYJDwAAAA==.Zazael:BAAALgAECgIJAgAAAA==.Zazreal:BAABLgAECn84AAQiAAkJgh3FAgB7AgAiAAkJgh3FAgB7AgAKAAMJ4Q9oSwClAAAdAAQJ7wIeKwCFAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn85AAImAAkJ7gaYFABiAQAmAAkJ7gaYFABiAQAAAA==.Zillyanna:BAAALgAECggJEwAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zyper:BAAALgAECgYJDAAAAA==.Zywol:BAABLgAECn8mAAQUAAkJ5hh+EwAtAgAUAAkJ5hh+EwAtAgARAAMJlgbIpgB6AAAWAAEJjA/ebQAqAAAAAA==.',
['Ër']='Ëresta:BAABLgAECn8cAAIMAAcJXAwGmQBCAQAMAAcJXAwGmQBCAQAAAA==.',
['Ðe']='Ðesire:BAAALgAECgYJCwAAAA==.Ðespair:BAACLgAFFH8QAAIhAAQJ/SDyDAB6AQAhAAQJ/SDyDAB6AQAuAAQKfzQABBUACQklICQKAJYCABUABwk9ISQKAJYCACEACQltH0wLAJUCAA8ABQmTGH8+AOcAAAAA.',
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
