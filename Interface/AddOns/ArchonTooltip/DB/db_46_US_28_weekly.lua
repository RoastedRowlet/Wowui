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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Protection','Priest-Holy','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Rogue-Subtlety','DemonHunter-Devourer','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Druid-Guardian','Warrior-Protection','Warrior-Arms','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','DemonHunter-Havoc','Druid-Feral','Monk-Mistweaver','DemonHunter-Vengeance','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Monk-Brewmaster','Rogue-Assassination','Shaman-Enhancement','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abaddón:BAAALgAECgEJAQABLgAECggJHwABALwiAA==.Abfuscatedd:BAABLgAECn8iAAMCAAkJShPRNADtAQACAAkJShPRNADtAQADAAEJAAARgAATAAAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJFgAEAPoYAA==.Acidrain:BAABLgAECn85AAIFAAkJMyGWBQDoAgAFAAkJMyGWBQDoAgAAAA==.Acmiax:BAABLgAECn8aAAMGAAcJQxskeACKAQAGAAYJhhkkeACKAQABAAUJugttSwDjAAAAAA==.',
Ad='Adar:BAAALgAECgQJBAAAAA==.',
Ae='Aep:BAAALgAECggJEgABLgAECgMJAwAHAAAAAA==.',
Ah='Ahrmanhamma:BAACLgAFFH8IAAIGAAQJshkxHQBeAQAGAAQJshkxHQBeAQAuAAQKfxoAAgYACQkvIrcMAOUCAAYACQkvIrcMAOUCAAAA.Ahu:BAABLgAECn8nAAMEAAgJsRcuMADwAQAEAAgJsRcuMADwAQAIAAMJZAQjcwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgQJBQAAAA==.',
Al='Al:BAAALgAECgEJAQABLgAECgYJCAAHAAAAAA==.Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgQJDwAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAABLgAECn87AAMEAAkJOhBvNwDVAQAEAAkJ+g9vNwDVAQAIAAgJnwweNQCVAQAAAA==.Alerus:BAAALgAECgEJAQAAAA==.Alexander:BAABLgAECn8eAAIJAAkJixrzJgDXAgAJAAkJixrzJgDXAgAAAA==.Alexijones:BAABLgAECn8cAAIKAAkJJQ/aFQDYAQAKAAkJJQ/aFQDYAQAAAA==.Allaria:BAAALgAECgcJCgAAAA==.',
Am='Ambassador:BAABLgAECn8eAAILAAkJlBdjCQALAgALAAkJlBdjCQALAgAAAA==.Amoondai:BAACLgAFFH8UAAIMAAQJpCIHCACPAQAMAAQJpCIHCACPAQAuAAQKf0QAAgwACQn2JOkAALEDAAwACQn2JOkAALEDAAAA.',
An='Analytics:BAAALgADCgMJAwAAAA==.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn8/AAMNAAkJUiIoAwD2AgANAAkJUiIoAwD2AgAOAAYJ7wNo0gDcAAAAAA==.Apolyon:BAABLgAECn8mAAIPAAkJLSFTBwAnAwAPAAkJLSFTBwAnAwAAAA==.',
Ar='Araon:BAAALgAECgYJBgAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
As='Asheraah:BAAALgAECgEJAQAAAA==.',
At='Atroxz:BAAALgADCgcJCAAAAA==.',
Ba='Bacstabath:BAABLgAECn8sAAIQAAkJTx4XBgAvAwAQAAkJTx4XBgAvAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAFFAQJCAAGALIZAA==.Banshee:BAABLgAECn8eAAIRAAkJ1B/mDwCoAgARAAkJ1B/mDwCoAgAAAA==.Baychan:BAAALgAECgIJAgAAAA==.',
Be='Becca:BAABLgAECn84AAILAAkJkBZfCQALAgALAAkJkBZfCQALAgAAAA==.Berries:BAAALgAECgEJAQAAAA==.',
Bi='Bigaraon:BAAALgADCgIJAgAAAA==.Bigdamaj:BAABLgAECn8vAAMSAAkJEhljBwDeAQASAAgJwxdjBwDeAQAOAAkJBhS0RADSAQAAAA==.Birbdormu:BAAALgAECgQJBQABLgAECgkJLwATAFAeAA==.',
Bl='Blakdemon:BAAALgADCgUJBQAAAA==.Bloodiblind:BAAALgAECgQJBQAAAA==.Bloodios:BAABLgAECn8wAAINAAkJfh5xBgCXAgANAAkJfh5xBgCXAgAAAA==.Blázé:BAAALgADCgEJAQAAAA==.',
Bo='Bobin:BAAALgADCgcJCAABLgAECgkJHQAUAOwQAA==.Bobinforapl:BAABLgAECn8dAAIUAAkJ7BBCGwDHAQAUAAkJ7BBCGwDHAQAAAA==.Bombadil:BAABLgAECn85AAIUAAkJmAaxIgCJAQAUAAkJmAaxIgCJAQAAAA==.',
Br='Bribage:BAABLgAECn8vAAQTAAkJUB6KCQCXAgATAAkJ/R2KCQCXAgAVAAQJHRLdJwDSAAAPAAEJtyEfmwBdAAAAAA==.Brolavski:BAAALgAECgEJAQABLgAECgYJCAAHAAAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgUJBwABLgAECgcJCgAHAAAAAA==.Budderwar:BAABLgAECn81AAQWAAkJDyZfAQA5AwAWAAkJDyZfAQA5AwAXAAcJkRuODQDoAQAYAAMJvw4KhwCjAAAAAA==.Buggz:BAAALgAECgMJAwAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgIJBQAAAA==.',
['Bà']='Bàdmofos:BAAALgAECgQJBwAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.',
Cb='Cbreezy:BAAALgAECgEJAQAAAA==.',
Ce='Celjska:BAAALgAECgUJBgAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chikñ:BAABLgAECn8aAAMFAAgJDg7kQABGAQAFAAYJjw/kQABGAQAZAAgJ7gkwTgBDAQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.Chuanthu:BAAALgADCgUJBgAAAA==.Chug:BAAALgAECgEJAQAAAA==.',
Ci='Cinderspella:BAAALgAECgIJAgAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8zAAIaAAkJdiVlAQBZAwAaAAkJdiVlAQBZAwAAAA==.',
Co='Cocoredbull:BAABLgAECn8dAAIVAAkJdw6oGgA2AQAVAAkJdw6oGgA2AQAAAA==.Corrail:BAAALgAECgYJCgAAAA==.Correin:BAABLgAECn8fAAIbAAkJbw+KGwBmAQAbAAkJbw+KGwBmAQAAAA==.',
Cr='Craszhin:BAABLgAECn8kAAITAAkJqRD1GQDOAQATAAkJqRD1GQDOAQAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn80AAIJAAkJIwygWwCuAQAJAAkJIwygWwCuAQAAAA==.',
Da='Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.Darkwater:BAAALgADCgkJCQAAAA==.Dazinth:BAAALgAECgEJAQAAAA==.',
De='Deets:BAABLgAECn82AAIEAAkJSh/qDADFAgAEAAkJSh/qDADFAgAAAA==.Defoy:BAABLgAECn8WAAMIAAYJJhklFQDtAAAIAAYJ4xYlFQDtAAAEAAQJZxBOwACBAAAAAA==.Demona:BAABLgAECn8yAAMDAAkJDQ4cCQCJAQADAAkJDQ4cCQCJAQACAAYJWgMZwQCsAAAAAA==.Demonduckz:BAAALgAECgEJAgAAAA==.Demonicfates:BAABLgAECn8bAAIbAAgJWA6RHABcAQAbAAgJWA6RHABcAQAAAA==.Derffy:BAABLgAECn8jAAIcAAcJER/uBwAhAgAcAAcJER/uBwAhAgAAAA==.Descalabrada:BAAALgAECgQJCAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Di='Distol:BAAALgAECgQJBQAAAA==.',
Dm='Dmt:BAABLgAECn8iAAIdAAgJBh27EwBFAgAdAAgJBh27EwBFAgAAAA==.',
Do='Dotemdown:BAAALgAECgIJAgAAAA==.',
Dr='Draiara:BAAALgAECgMJAwAAAA==.Dropdeadx:BAAALgAECgYJDQAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJHwABALwiAA==.Drpeppers:BAABLgAECn8sAAMPAAkJLAvxPQB5AQAPAAkJLAvxPQB5AQAVAAEJAAAUPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthling:BAAALgAECgUJCgAAAA==.',
Ec='Eclair:BAABLgAECn81AAMZAAkJkhQmJQABAgAZAAkJkhQmJQABAgAFAAYJ5Bj1LQBdAQAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgAECgQJBAABLgAECgkJLAAQAE8eAA==.',
El='Eleysia:BAAALgAECgYJBgAAAA==.Elf:BAAALgAECgYJBgABLgAECggJIgAGAAEmAA==.Elhayn:BAAALgAECgUJBwAAAA==.Elmore:BAAALgAECgQJBAAAAA==.Elmos:BAABLgAECn8tAAIaAAkJ7B61CACVAgAaAAkJ7B61CACVAgAAAA==.',
Er='Erestadh:BAAALgAECgEJAgABLgAECgcJHAAJAFwMAA==.',
Eu='Eucalyptus:BAAALgAECgEJAgAAAA==.',
Ev='Evilmonkeymg:BAEALgAECgEJAQABLgAECgkJGQAFACceAA==.Evilmonkeysh:BAEBLgAECn8ZAAMFAAkJJx5eHAAvAgAFAAkJJx5eHAAvAgAZAAcJQQvdTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECgkJGQAFACceAA==.',
Ex='Exto:BAAALgAECgMJBAABLgAECgQJBAAHAAAAAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8xAAMbAAkJthZSDQAaAgAbAAkJthZSDQAaAgAeAAYJngooFQDWAAAAAA==.',
Fa='Fatehunter:BAAALgADCggJCAAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgYJCwABLgAECggJDgAHAAAAAA==.Fenrísulfr:BAAALgAECgMJAwABLgAECggJDgAHAAAAAA==.Ferg:BAAALgAECgYJCQABLgAECgkJOQAJAE4jAA==.Fergis:BAABLgAECn85AAIJAAkJTiOGCAAkAwAJAAkJTiOGCAAkAwAAAA==.Fergle:BAAALgAECgYJEgAAAA==.Fetchme:BAAALgAECgQJBwAAAA==.Fetchyou:BAAALgADCggJDgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8dAAMNAAkJsBc8EgDoAQANAAkJ+xY8EgDoAQASAAcJ0RVDCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECggJEAAAAA==.',
Fr='Freecaster:BAAALgAECgMJAwAAAA==.Frostybeary:BAAALgAECgcJCAAAAA==.Frostymonk:BAABLgAECn8YAAIdAAcJOQliSQDrAAAdAAcJOQliSQDrAAAAAA==.Frozenwaffle:BAAALgAECgYJEgABLgAECgkJJgAfAJkhAA==.',
Fu='Furryben:BAAALgADCgkJIQAAAA==.',
['Fá']='Fállen:BAAALgADCgQJBAAAAA==.',
Ga='Galeste:BAAALgAECgQJBQAAAA==.',
Gi='Gigem:BAAALgAECgYJDQAAAA==.Girlshoon:BAAALgAECgEJAQAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQgAAkJkASTIwBcAQAgAAkJkASTIwBcAQAhAAUJ9gP/SgCoAAAiAAEJlQEpJQAZAAAAAA==.Glarious:BAAALgAECgYJEAABLgAECgkJGwAgAJAEAA==.',
Go='Golakuron:BAAALgADCgUJBQAAAA==.Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgYJCAAAAA==.Greenwaffle:BAABLgAECn8mAAMfAAkJmSGRCQCTAgAfAAkJmSGRCQCTAgAMAAYJwBTCNQBmAQAAAA==.Grôg:BAAALgAECgcJBwAAAA==.',
Gu='Guldaniel:BAAALgAECgQJBQAAAA==.Guthx:BAABLgAECn8eAAIPAAkJzBiGHQA2AgAPAAkJzBiGHQA2AgAAAA==.',
Ha='Harutah:BAAALgAECgQJBAAAAA==.Hazeran:BAAALgAECgIJAgAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgAHAAAAAA==.',
Ho='Holymolii:BAABLgAECn8nAAILAAgJoBfLDgCpAQALAAgJoBfLDgCpAQAAAA==.Hotcoffee:BAAALgAECgYJDgAAAA==.',
Hu='Huntermaster:BAABLgAECn8bAAQKAAgJFRdJGwCkAQAKAAcJwBdJGwCkAQAIAAUJRxiERABDAQAEAAEJEBJu+AA4AAABLgAECgkJNQAWAA8mAA==.',
Il='Ilulz:BAAALgADCgEJAQAAAA==.',
In='Incredabull:BAABLgAECn8aAAIWAAcJqReJFACBAQAWAAcJqReJFACBAQAAAA==.Intrepidz:BAAALgAECgEJAQABLgAECgkJJAAJABUYAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAABLgAECn8qAAIjAAkJQxQ+BgDnAQAjAAkJQxQ+BgDnAQAAAA==.Istayblunted:BAABLgAECn8eAAILAAcJxx8QEADEAQALAAcJxx8QEADEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDQAAAA==.',
Iw='Iwinwithhots:BAAALgAECgEJAgABLgAECgcJGAAGAIceAA==.',
Ji='Jiayerah:BAAALgAECgQJBgABLgAECgYJHwAMAPkhAA==.Jinkuzo:BAABLgAECn8xAAIkAAkJIB8iCACUAgAkAAkJIB8iCACUAgAAAA==.Jinmu:BAABLgAECn80AAMQAAkJOxiaDQApAgAQAAkJOxiaDQApAgAlAAEJJgulIgAxAAAAAA==.',
Ju='Juggie:BAABLgAECn8nAAIMAAgJZhOvHQCzAQAMAAgJZhOvHQCzAQAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8mAAIlAAkJigsBCgB3AQAlAAkJigsBCgB3AQAAAA==.',
Ka='Kagami:BAAALgAECgIJAgAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAABLgAECn8XAAMCAAkJgRoIIQBGAgACAAkJVhoIIQBGAgADAAEJFBvWawA8AAAAAA==.',
Ke='Keliez:BAAALgAECgEJAQABLgAFFAYJFQAPADcPAA==.',
Kh='Khrodors:BAAALgADCgMJAwAAAA==.',
Ki='Kiannis:BAAALgADCgEJAQAAAA==.Kickerr:BAAALgAECggJEwABLgAECgkJIwAkAAAaAA==.Kickrr:BAAALgAECgYJBgABLgAECgkJIwAkAAAaAA==.',
Kl='Klodar:BAAALgAECgEJAQAAAA==.Klum:BAAALgAECgUJCQAAAA==.',
Kr='Krazee:BAAALgADCgEJAQAAAA==.Krunkle:BAAALgAECgIJAwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgADCgcJCwAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgAECgQJBgAAAA==.Lendela:BAAALgAECgUJDAAAAA==.',
Li='Liljugg:BAAALgAECgYJDAAAAA==.',
Lm='Lmaddk:BAAALgAECgIJAgAAAA==.',
Lo='Logi:BAAALgAECgMJAwAAAA==.Lor:BAAALgAECgQJBgAAAA==.Lostmana:BAAALgAECgIJAgAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Lu='Lunablade:BAAALgAECgEJAQAAAA==.',
Ly='Lygor:BAABLgAECn8rAAIEAAgJqRKCQgCvAQAEAAgJqRKCQgCvAQAAAA==.Lyrasong:BAAALgADCgIJAgAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJHwABALwiAA==.',
Ma='Maelle:BAAALgADCgYJBQAAAA==.Majellan:BAAALgAECgMJBgAAAA==.Makrub:BAAALgAECggJDQAAAA==.Malystryix:BAAALgAECgQJBAAAAA==.Mandigosa:BAAALgAECgIJAgAAAA==.Marist:BAAALgAECgEJAwAAAA==.Marrius:BAAALgAECgEJAgAAAA==.Marsawn:BAABLgAECn8gAAMfAAkJERjuEAArAgAfAAkJERjuEAArAgAMAAMJYBgxQADHAAAAAA==.',
Mc='Mcpeepants:BAACLgAFFH8HAAImAAQJaxd7BABKAQAmAAQJaxd7BABKAQAuAAQKfxQAAiYACQnsHt0CAMACACYACQnsHt0CAMACAAEuAAUUBAkIAAYAshkA.',
Me='Meqi:BAABLgAECn8dAAMJAAYJ0hwUfABjAQAJAAYJ0hwUfABjAQAnAAEJDBcVDgBGAAAAAA==.',
Mi='Mikàsa:BAABLgAECn8lAAMKAAgJLxGiGAC8AQAKAAgJLxGiGAC8AQAIAAYJXwmaTgAVAQAAAA==.Minand:BAAALgAECgYJEQAAAA==.Mindlessness:BAABLgAECn8yAAIYAAkJ5yOqAwAWAwAYAAkJ5yOqAwAWAwAAAA==.Mineralelf:BAABLgAECn8yAAIEAAkJ6QshRACpAQAEAAkJ6QshRACpAQAAAA==.Minichaos:BAABLgAECn8kAAMDAAcJAxW6CgBoAQADAAcJAxW6CgBoAQACAAQJgAbMwACtAAAAAA==.Miriam:BAABLgAECn8dAAIoAAcJjAUyCADrAAAoAAcJjAUyCADrAAAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8fAAIBAAgJvCIpBwD5AgABAAgJvCIpBwD5AgAAAA==.',
Mo='Mojosavage:BAABLgAECn8YAAICAAcJ7gKrvQCzAAACAAcJ7gKrvQCzAAAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAgAAAA==.Moonblade:BAAALgAECgYJCwAAAA==.Mortshan:BAABLgAECn8bAAInAAkJRhYRAgAfAgAnAAkJRhYRAgAfAgAAAA==.Mournfull:BAAALgAECgEJAwAAAA==.',
My='Mysticalfox:BAAALgAECgQJBgAAAA==.',
Na='Nalfilas:BAAALgAECgUJDQAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgAECgYJBwAAAA==.Nikru:BAAALgAFFAEJAQABLgAFFAYJFQAPADcPAA==.Ninok:BAABLgAECn8jAAIGAAkJPBPSOQD7AQAGAAkJPBPSOQD7AQAAAA==.',
No='Nocturnous:BAAALgAECgEJAQAAAA==.Nornee:BAABLgAECn8kAAIZAAgJ0A5NRwBeAQAZAAgJ0A5NRwBeAQAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8dAAIcAAgJRR34BwAhAgAcAAgJRR34BwAhAgAAAA==.',
['Nà']='Nàtureswrath:BAAALgAECgIJBAAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAABLgAECn8bAAMYAAgJ0xGPKwCBAQAYAAgJ0xGPKwCBAQAXAAEJ4wzVYgAtAAAAAA==.',
Ol='Ollïee:BAAALgAECgUJBQAAAA==.',
Op='Oprawyndfury:BAAALgAECgcJCwAAAA==.',
Or='Orceo:BAABLgAECn8lAAIEAAkJ+iPIBQAxAwAEAAkJ+iPIBQAxAwAAAA==.Orkreghar:BAAALgAECgEJAgAAAA==.',
Os='Osaro:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgAECgIJAgAAAA==.',
Ow='Ownlyshamz:BAAALgADCgMJAwABLgAECggJCAAHAAAAAA==.',
Ox='Oxcanor:BAAALgADCgkJDwAAAA==.',
Pa='Patches:BAAALgAECgUJBwABLgAECggJHwABALwiAA==.',
Pe='Pepsipoutine:BAABLgAECn8WAAICAAYJmB+9TgDcAQACAAYJmB+9TgDcAQAAAA==.Petiterage:BAAALgADCggJCwAAAA==.',
Pi='Pindapind:BAAALgADCgMJBAABLgAECgkJNQAWAA8mAA==.Pindapinda:BAAALgAECgUJBQABLgAECgkJNQAWAA8mAA==.',
Pl='Plaguexion:BAAALgADCgQJBgAAAA==.',
Po='Pompompower:BAABLgAECn8xAAIFAAkJGQiQMwA+AQAFAAkJGQiQMwA+AQAAAA==.Popple:BAABLgAECn8sAAIYAAkJ5xA5GwDvAQAYAAkJ5xA5GwDvAQAAAA==.Potential:BAABLgAECn8jAAIkAAkJCRqJDABOAgAkAAkJCRqJDABOAgAAAA==.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgUJEAAAAA==.Puggsly:BAAALgAECgEJAgAAAA==.Pugsta:BAAALgAECgMJAwABLgAECggJEgAHAAAAAA==.',
Py='Pyrocaster:BAAALgAECgEJAgAAAA==.',
Qa='Qaccy:BAABLgAECn8SAAIfAAcJxQxSNAAfAQAfAAcJxQxSNAAfAQAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAABLgAECn8bAAIYAAgJzhnnIQC9AQAYAAgJzhnnIQC9AQAAAA==.',
Ra='Radaghast:BAAALgAECgEJAQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Regret:BAAALgAECgEJAQABLgAFFAcJJQAeAHAZAA==.Reishirome:BAAALgAECgEJAQAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8eAAIVAAgJPSIZAwDlAgAVAAgJPSIZAwDlAgAAAA==.',
Rh='Rhogar:BAAALgAECgMJBAAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8fAAITAAkJjgbALgA2AQATAAkJjgbALgA2AQAAAA==.Romeoz:BAAALgADCgEJAQAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAAALgAECgYJEgAAAA==.',
Ru='Rumincoke:BAAALgADCgkJEwAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAABLgAECn8fAAIMAAYJ+SGWEgAiAgAMAAYJ+SGWEgAiAgAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwAHAAAAAA==.',
Sc='Scalygrob:BAAALgAECgkJEwAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8rAAIUAAkJARe1DgBWAgAUAAkJARe1DgBWAgAAAA==.Sellphie:BAAALgADCgYJBgAAAA==.',
Sh='Shadowhntr:BAAALgAECgEJAQAAAA==.Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shavedussy:BAAALgADCgUJBQAAAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Siknes:BAAALgAECggJCAABLgAECgkJLAAQAE8eAA==.Simpofmeerah:BAAALgAECgYJBwAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgYJDAAAAA==.',
Sl='Slargerita:BAAALgADCgcJBwAAAA==.',
Sm='Smallmoon:BAAALgAECgEJAQAAAA==.Smogcheck:BAACLgAFFH8MAAIgAAQJRRErFAAXAQAgAAQJRRErFAAXAQAuAAQKfyEAAyAACQkOE2gbAK0BACAACQkOE2gbAK0BACIAAQl9CNM+ADQAAAAA.',
Sn='Snackcake:BAABLgAECn8nAAIPAAgJXRxsFQB7AgAPAAgJXRxsFQB7AgAAAA==.Snakeoil:BAABLgAECn8cAAMFAAkJyh48DAB8AgAFAAkJyh48DAB8AgAZAAEJCgKgwQAiAAAAAA==.Snowsz:BAAALgAECgIJAgAAAA==.Snowws:BAABLgAECn8eAAIRAAkJ9xqZGgBYAgARAAkJ9xqZGgBYAgAAAA==.',
So='Sortis:BAABLgAECn8kAAIJAAkJFRjeMwCjAgAJAAkJFRjeMwCjAgAAAA==.',
Sp='Spicebreff:BAAALgAECggJCAAAAA==.Spongerunner:BAAALgAECgYJDgAAAA==.Sprucetea:BAAALgADCgIJAwAAAA==.',
St='Steck:BAABLgAECn8qAAIEAAgJyxVTOwDHAQAEAAgJyxVTOwDHAQAAAA==.Strigo:BAABLgAFFH8OAAQKAAQJdRjEDABIAQAKAAQJCBjEDABIAQAEAAEJtBy7IABfAAAIAAEJnwy7KABKAAAAAA==.',
Su='Subway:BAAALgAECggJEAAAAA==.Sunbaby:BAABLgAECn8nAAIeAAgJnh4mBQA1AgAeAAgJnh4mBQA1AgAAAA==.',
['Sà']='Sàlís:BAAALgADCgkJDgAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8gAAIUAAkJdCBJBQD9AgAUAAkJdCBJBQD9AgAAAA==.Talandaru:BAAALgAECgEJAwAAAA==.Talas:BAABLgAECn8yAAMEAAkJFh68DgC0AgAEAAkJFh68DgC0AgAIAAUJswr3VwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Te='Temerald:BAAALgADCgkJCQAAAA==.Tevoran:BAAALgAECgUJBQAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thaelidari:BAAALgAECgkJDAAAAA==.Thieridan:BAAALgADCgIJBAAAAA==.Thrangus:BAAALgAECgIJAgABLgAECgkJHQAOAOsiAA==.Thrann:BAABLgAECn8dAAMOAAkJ6yKfOgBNAgAOAAcJqSKfOgBNAgASAAQJzyPaCgCIAQAAAA==.Thunderdex:BAACLgAFFH8NAAMRAAcJpBZdDQDnAQARAAcJpBZdDQDnAQAbAAEJ6AOSIAA5AAAuAAQKfx8AAhEACQl+HpoZAF4CABEACQl+HpoZAF4CAAAA.',
Ti='Tirium:BAAALgAECgEJAQABLgAECggJCAAHAAAAAA==.',
To='Togglesmith:BAAALgADCgcJDgAAAA==.Togglestein:BAAALgADCgYJDQAAAA==.Togglethorp:BAAALgADCgYJDAAAAA==.Togi:BAAALgADCgcJDQAAAA==.',
Tr='Trinitum:BAAALgAECgUJCQABLgAECggJCAAHAAAAAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Ud='Udderduckie:BAAALgAECgEJAgAAAA==.',
Un='Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJBwAAAA==.Ursoconha:BAAALgAECgUJBQABLgAFFAYJBQAJAIsYAA==.',
Va='Vaadboolin:BAAALgAECggJEgAAAA==.Vallius:BAABLgAECn8dAAIQAAkJ5BLeEwDfAQAQAAkJ5BLeEwDfAQAAAA==.Vanargandr:BAAALgAECggJDgAAAA==.',
Ve='Verðandi:BAAALgAECgIJAgAAAA==.',
Vo='Volcano:BAABLgAECn8bAAICAAkJIxqlHwBOAgACAAkJIxqlHwBOAgAAAA==.Volvox:BAAALgADCgEJAQAAAA==.Vonslarge:BAAALgADCgkJCQAAAA==.',
Vy='Vyxenn:BAABLgAECn8wAAMZAAkJ0xZQGgBLAgAZAAkJ0xZQGgBLAgAFAAMJVQrWbABpAAAAAA==.',
Wa='Waffletoast:BAAALgADCgkJEQABLgAECgkJJgAfAJkhAA==.Wanders:BAABLgAECn8hAAMJAAgJIhXJUADNAQAJAAgJIhXJUADNAQAoAAYJLAmdCwAcAQAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Wu='Wurm:BAAALgAECgcJBwABLgAECgcJBwAHAAAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yep:BAACLgAFFH8GAAIGAAQJohYsIQBSAQAGAAQJohYsIQBSAQAuAAQKfxsAAgYACQnwI14GACYDAAYACQnwI14GACYDAAAA.Yesenìa:BAAALgAECgQJAwAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zans:BAABLgAECn8vAAMoAAYJfwWQDQDvAAAoAAYJRAWQDQDvAAAJAAUJ3wJq/AB/AAAAAA==.Zavia:BAAALgADCgUJCQAAAA==.Zazael:BAAALgAECgIJAgAAAA==.Zazreal:BAABLgAECn84AAQiAAkJgh0iAgCNAgAiAAkJgh0iAgCNAgAhAAMJ4Q9oSwClAAAgAAQJ7wJpJwCGAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn85AAImAAkJ7gYXEQBlAQAmAAkJ7gYXEQBlAQAAAA==.Zillyanna:BAAALgAECgcJEgAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zyper:BAAALgAECgQJBAAAAA==.Zywol:BAABLgAECn8mAAQTAAkJ5hgnEAA3AgATAAkJ5hgnEAA3AgAPAAMJlgbIpgB6AAAVAAEJjA/XVQAsAAAAAA==.',
['Ër']='Ëresta:BAABLgAECn8cAAIJAAcJXAwQigBHAQAJAAcJXAwQigBHAQAAAA==.',
['Ðe']='Ðesire:BAAALgAECgYJCAAAAA==.Ðespair:BAACLgAFFH8JAAIfAAQJzR1LCwByAQAfAAQJzR1LCwByAQAuAAQKfzQABB8ACQltHwUJAJ0CAB8ACQltHwUJAJ0CABQABwk9ISQKAJYCAAwABQmTGIw5AO4AAAAA.',
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
