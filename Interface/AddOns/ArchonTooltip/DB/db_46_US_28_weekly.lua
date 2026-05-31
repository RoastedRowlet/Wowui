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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Protection','Priest-Holy','DeathKnight-Blood','Druid-Restoration','Rogue-Subtlety','DemonHunter-Devourer','Druid-Balance','Priest-Discipline','Druid-Guardian','Warrior-Protection','Warrior-Arms','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','DemonHunter-Havoc','Druid-Feral','Monk-Mistweaver','DemonHunter-Vengeance','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Monk-Brewmaster','Rogue-Assassination','Shaman-Enhancement','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abaddón:BAAALgAECgEJAQABLgAECggJHwABALwiAA==.Abfuscatedd:BAABLgAECn8iAAMCAAkJShNUOgDkAQACAAkJShNUOgDkAQADAAEJAAARgAATAAAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJFgAEAPoYAA==.Acidrain:BAABLgAECn85AAIFAAkJMyF5BgDkAgAFAAkJMyF5BgDkAgAAAA==.Acmiax:BAABLgAECn8aAAMGAAcJQxskeACKAQAGAAYJhhkkeACKAQABAAUJuguBTwDjAAAAAA==.',
Ad='Adar:BAAALgAECgQJBAAAAA==.',
Ae='Aep:BAABLgAECn8ZAAMHAAgJ/hKOEAA6AQAIAAcJ/gxxhwBAAQAHAAYJSxSOEAA6AQABLgAECgMJAwAJAAAAAA==.',
Ah='Ahrmanhamma:BAACLgAFFH8JAAIGAAQJ5xnAIgBaAQAGAAQJ5xnAIgBaAQAuAAQKfxoAAgYACQkvIhcPANcCAAYACQkvIhcPANcCAAAA.Ahu:BAABLgAECn8nAAMEAAgJsRcuMADwAQAEAAgJsRcuMADwAQAKAAMJZAQjcwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgQJBQAAAA==.',
Al='Al:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgQJEgAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAABLgAECn9EAAMEAAkJuxGQNAD0AQAEAAkJexGQNAD0AQAKAAgJnwweNQCVAQAAAA==.Alerus:BAAALgAECgEJAQAAAA==.Alexander:BAABLgAECn8eAAILAAkJixrzJgDXAgALAAkJixrzJgDXAgAAAA==.Alexijones:BAABLgAECn8cAAIMAAkJJQ+/FwDVAQAMAAkJJQ+/FwDVAQAAAA==.Allaria:BAAALgAECgcJCgAAAA==.',
Am='Ambassador:BAABLgAECn8eAAINAAkJlBeRCgAHAgANAAkJlBeRCgAHAgAAAA==.Amoondai:BAACLgAFFH8YAAIOAAQJpCLMCQCDAQAOAAQJpCLMCQCDAQAuAAQKf0UAAg4ACQn2JDgBAKoDAA4ACQn2JDgBAKoDAAAA.',
An='Analytics:BAAALgADCgYJBgAAAA==.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn8/AAMPAAkJUiLZAwDtAgAPAAkJUiLZAwDtAgAIAAYJ7wNo0gDcAAAAAA==.Apolyon:BAABLgAECn8mAAIQAAkJLSE2CAAmAwAQAAkJLSE2CAAmAwAAAA==.',
Ar='Araon:BAAALgAECgYJBgAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
As='Asheraah:BAAALgAECgQJBQAAAA==.',
At='Atroxz:BAAALgADCgcJCAAAAA==.',
Ba='Bacstabath:BAABLgAECn8sAAIRAAkJTx4XBgAvAwARAAkJTx4XBgAvAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAFFAQJCQAGAOcZAA==.Banshee:BAABLgAECn8eAAISAAkJ1B/5EQCfAgASAAkJ1B/5EQCfAgAAAA==.Baychan:BAAALgAECgcJCAAAAA==.',
Be='Becca:BAABLgAECn84AAINAAkJkBaKCgAHAgANAAkJkBaKCgAHAgAAAA==.Berries:BAAALgAECgEJAQAAAA==.',
Bi='Bigaraon:BAAALgADCgIJAgAAAA==.Bigdamaj:BAABLgAECn8wAAMHAAkJEhmFCADVAQAHAAgJwxeFCADVAQAIAAkJBhQISwDPAQAAAA==.Birbdormu:BAAALgAECgQJBQABLgAECgkJMgATAFAeAA==.',
Bl='Blakdemon:BAAALgADCgUJBQAAAA==.Bloodiblind:BAAALgAECgQJCAAAAA==.Bloodios:BAABLgAECn8wAAIPAAkJfh6UBwCNAgAPAAkJfh6UBwCNAgAAAA==.Blázé:BAAALgADCgEJAQAAAA==.',
Bo='Bobbardment:BAAALgAECgYJBgAAAA==.Bobin:BAAALgAECgMJBAABLgAECgkJHQAUAOwQAA==.Bobinforapl:BAABLgAECn8dAAIUAAkJ7BBsHwCvAQAUAAkJ7BBsHwCvAQAAAA==.Bombadil:BAABLgAECn9AAAIUAAkJqgbIJgB2AQAUAAkJqgbIJgB2AQAAAA==.',
Br='Bribage:BAABLgAECn8yAAQTAAkJUB7MCgCSAgATAAkJ/R3MCgCSAgAVAAYJ9BTmFwBsAQAQAAEJtyGVogBdAAAAAA==.Brolavski:BAAALgAECgEJAQABLgAECgcJCgAJAAAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgUJBwABLgAECgcJCgAJAAAAAA==.Budderwar:BAABLgAECn81AAQWAAkJDybDAQAuAwAWAAkJDybDAQAuAwAXAAcJkRtWDwDhAQAYAAMJvw4KhwCjAAAAAA==.Buggz:BAAALgAECgQJBgAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgIJBQAAAA==.',
['Bà']='Bàdmofos:BAAALgAECgQJBwAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.Calvis:BAAALgADCgUJBQAAAA==.',
Cb='Cbreezy:BAAALgAECgMJAwAAAA==.',
Ce='Celerydk:BAAALgAECgUJBQAAAA==.Celjska:BAAALgAECgUJBgAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chikñ:BAABLgAECn8aAAMFAAgJDg7kQABGAQAFAAYJjw/kQABGAQAZAAgJ7gnQVABCAQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.Chuanthu:BAAALgADCgUJBgAAAA==.Chug:BAAALgAECgEJAQAAAA==.',
Ci='Cinderspella:BAAALgAECgIJAgAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8zAAIaAAkJdiWlAQBUAwAaAAkJdiWlAQBUAwAAAA==.',
Co='Cocoredbull:BAABLgAECn8dAAIVAAkJdw5WHgA0AQAVAAkJdw5WHgA0AQAAAA==.Corrail:BAAALgAECgYJDQAAAA==.Correin:BAABLgAECn8fAAIbAAkJbw+SHgBhAQAbAAkJbw+SHgBhAQAAAA==.',
Cr='Craszhin:BAABLgAECn8kAAITAAkJqRCTHADLAQATAAkJqRCTHADLAQAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn81AAILAAkJIwxaZwCVAQALAAkJIwxaZwCVAQAAAA==.',
Da='Dadeb:BAAALgAECgQJBAAAAA==.Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.Darkwater:BAAALgADCgkJCQAAAA==.Dazinth:BAAALgAECgEJAQAAAA==.',
De='Deets:BAABLgAECn82AAIEAAkJSh/zDwC9AgAEAAkJSh/zDwC9AgAAAA==.Defoy:BAABLgAECn8WAAMKAAYJJhmeFgDrAAAKAAYJ4xaeFgDrAAAEAAQJZxAXzwCBAAAAAA==.Demona:BAABLgAECn8yAAMDAAkJDQ5tCgB/AQADAAkJDQ5tCgB/AQACAAYJWgO+zACoAAAAAA==.Demonduckz:BAAALgAECgEJAgAAAA==.Demonicfates:BAABLgAECn8bAAIbAAgJWA7qHwBVAQAbAAgJWA7qHwBVAQAAAA==.Derffy:BAABLgAECn8pAAIcAAcJUyFPBwBEAgAcAAcJUyFPBwBEAgAAAA==.Descalabrada:BAAALgAECgYJDAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Di='Distol:BAAALgAECgQJBgAAAA==.',
Dm='Dmt:BAABLgAECn8iAAIdAAgJBh0dFgBGAgAdAAgJBh0dFgBGAgAAAA==.',
Do='Dotemdown:BAAALgAECgIJAgAAAA==.',
Dr='Draiara:BAAALgAECgMJAwAAAA==.Dropdeadqtx:BAAALgAECgYJDQAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJHwABALwiAA==.Drpeppers:BAABLgAECn8sAAMQAAkJLAu+QQB4AQAQAAkJLAu+QQB4AQAVAAEJAAAUPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthling:BAAALgAECgUJDQAAAA==.',
Ec='Eclair:BAABLgAECn81AAMZAAkJkhQcKQD+AQAZAAkJkhQcKQD+AQAFAAYJ5BjyMQBbAQAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgAECgQJBAABLgAECgkJLAARAE8eAA==.',
El='Eleysia:BAAALgAECgcJBwAAAA==.Elf:BAAALgAECgYJBwABLgAECgkJAgAJAAAAAA==.Elhayn:BAAALgAECgUJBwAAAA==.Elmore:BAAALgAECgQJBAAAAA==.Elmos:BAABLgAECn8tAAIaAAkJ7B4NCAD5AgAaAAkJ7B4NCAD5AgAAAA==.',
Er='Erestadh:BAAALgAECgEJAgABLgAECgcJHAALAFwMAA==.Eris:BAAALgADCgcJBwAAAA==.',
Eu='Eucalyptus:BAAALgAECgEJAgAAAA==.',
Ev='Evilmonkeymg:BAEALgAECgEJAQABLgAECgkJGQAFACceAA==.Evilmonkeysh:BAEBLgAECn8ZAAMFAAkJJx5eHAAvAgAFAAkJJx5eHAAvAgAZAAcJQQvdTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECgkJGQAFACceAA==.',
Ex='Exto:BAAALgAECgMJBAABLgAECgQJBAAJAAAAAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8xAAMbAAkJthYzDwATAgAbAAkJthYzDwATAgAeAAYJngrGFgDSAAAAAA==.',
Fa='Fatehunter:BAAALgADCggJCAAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgcJDAABLgAECggJDgAJAAAAAA==.Fenrísulfr:BAAALgAECgMJAwABLgAECggJDgAJAAAAAA==.Ferg:BAAALgAECgYJCQABLgAECgkJOQALAE4jAA==.Fergis:BAABLgAECn85AAILAAkJTiMdCgAVAwALAAkJTiMdCgAVAwAAAA==.Fergle:BAAALgAECgYJEgAAAA==.Fetchme:BAAALgAECgQJBwAAAA==.Fetchyou:BAAALgADCggJDgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8dAAMPAAkJsBc8EgDoAQAPAAkJ+xY8EgDoAQAHAAcJ0RVDCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECggJEQAAAA==.',
Fr='Freecaster:BAAALgAECgMJAwAAAA==.Frostybeary:BAAALgAECgkJCQAAAA==.Frostymonk:BAABLgAECn8YAAIdAAcJOQkPVADoAAAdAAcJOQkPVADoAAAAAA==.Frozenwaffle:BAAALgAECgYJEgABLgAECgkJJgAfAJkhAA==.',
Fu='Furryben:BAAALgAECgMJAwAAAA==.',
['Fá']='Fállen:BAAALgADCgQJBAAAAA==.',
Ga='Galeste:BAAALgAECgUJBgAAAA==.',
Gh='Ghidorahh:BAAALgAFFAEJAQAAAA==.',
Gi='Gigem:BAABLgAECn8UAAIEAAcJWhzKNwDnAQAEAAcJWhzKNwDnAQAAAA==.Girlshoon:BAAALgAECgEJAQAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQgAAkJkASTIwBcAQAgAAkJkASTIwBcAQAhAAUJ9gP/SgCoAAAiAAEJlQEYKAAZAAAAAA==.Glarious:BAAALgAECgYJEAABLgAECgkJGwAgAJAEAA==.',
Go='Golakuron:BAAALgADCgUJBQAAAA==.Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgcJCgAAAA==.Gredan:BAAALgAECgYJCAAAAA==.Greenwaffle:BAABLgAECn8mAAMfAAkJmSH9CgCEAgAfAAkJmSH9CgCEAgAOAAYJwBTCNQBmAQAAAA==.Grôg:BAAALgAECgkJDQAAAA==.',
Gu='Guldaniel:BAAALgAECgQJBQAAAA==.Guthx:BAABLgAECn8eAAIQAAkJzBjbHwA0AgAQAAkJzBjbHwA0AgAAAA==.',
Ha='Harutah:BAAALgAECgQJBAAAAA==.Hazeran:BAAALgAECgMJBQAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgAJAAAAAA==.',
Ho='Holymolii:BAABLgAECn8pAAINAAkJhBbYDADcAQANAAkJhBbYDADcAQAAAA==.Hotcoffee:BAAALgAECgYJDgAAAA==.',
Hu='Huntermaster:BAABLgAECn8bAAQMAAgJFRe0HQCgAQAMAAcJwBe0HQCgAQAKAAUJRxiERABDAQAEAAEJEBLdDAE4AAABLgAECgkJNQAWAA8mAA==.',
Il='Ilulz:BAAALgADCgEJAQAAAA==.',
In='Incredabull:BAABLgAECn8bAAIWAAgJZhkdDwDgAQAWAAgJZhkdDwDgAQAAAA==.Intrepidz:BAAALgAECgEJAQABLgAECgkJJAALABUYAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAABLgAECn8rAAIjAAkJQxR2BwDZAQAjAAkJQxR2BwDZAQAAAA==.Istayblunted:BAABLgAECn8eAAINAAcJxx8QEADEAQANAAcJxx8QEADEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDQAAAA==.',
Iw='Iwinwithhots:BAAALgAECgEJAgABLgAECgcJGAAGAIceAA==.',
Ji='Jiayerah:BAAALgAECgQJCgABLgAECgYJJQAOAPkhAA==.Jinkuzo:BAABLgAECn8xAAIkAAkJIB8wCQCPAgAkAAkJIB8wCQCPAgAAAA==.Jinmu:BAABLgAECn80AAMRAAkJOxi4DwAbAgARAAkJOxi4DwAbAgAlAAEJJgtmJQAwAAAAAA==.',
Ju='Juggie:BAABLgAECn8pAAIOAAkJwRGiGwDSAQAOAAkJwRGiGwDSAQAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8pAAIlAAkJigupCgB4AQAlAAkJigupCgB4AQAAAA==.',
Ka='Kagami:BAAALgAECgIJAgAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAABLgAECn8XAAMCAAkJgRpnJABBAgACAAkJVhpnJABBAgADAAEJFBvWawA8AAAAAA==.',
Ke='Keliez:BAAALgAFFAEJAgABLgAFFAcJFwAQAHMNAA==.',
Kh='Khrodors:BAAALgADCgMJAwAAAA==.',
Ki='Kiannis:BAAALgADCgEJAQAAAA==.Kickerr:BAAALgAECggJEwABLgAECgkJJAAkANQaAA==.Kickrr:BAAALgAECgYJBgABLgAECgkJJAAkANQaAA==.Kirrby:BAAALgADCgEJAQAAAA==.',
Kl='Klodar:BAAALgAECgQJBAAAAA==.Klum:BAAALgAECgUJCQAAAA==.',
Kr='Krazee:BAAALgADCgEJAQAAAA==.Krunkle:BAAALgAECgIJAwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgADCgcJEQAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgAECgQJCgAAAA==.Lendela:BAAALgAECgUJDAAAAA==.',
Li='Liljugg:BAAALgAECgYJDwAAAA==.',
Lm='Lmaddk:BAAALgAECgIJAgAAAA==.',
Lo='Logi:BAAALgAECgMJAwAAAA==.Lor:BAAALgAECgQJBgAAAA==.Lostmana:BAAALgAECgQJBgAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Lu='Lunablade:BAAALgAECgEJAQAAAA==.',
Ly='Lygor:BAABLgAECn8zAAIEAAgJ6RM0QQDHAQAEAAgJ6RM0QQDHAQAAAA==.Lyrasong:BAAALgADCgIJAgAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJHwABALwiAA==.',
Ma='Maelle:BAAALgADCgYJBQAAAA==.Magnifico:BAAALgADCgEJAQAAAA==.Majellan:BAAALgAECgMJCAAAAA==.Makrub:BAAALgAECggJDQAAAA==.Malystryix:BAAALgAECgQJBAAAAA==.Mandigosa:BAAALgAECgMJBAAAAA==.Marist:BAAALgAECgEJAwAAAA==.Marrius:BAAALgAECgEJAgAAAA==.Marsawn:BAABLgAECn8gAAMfAAkJERjrEgAeAgAfAAkJERjrEgAeAgAOAAMJYBixQwDEAAAAAA==.',
Mc='Mcpeepants:BAACLgAFFH8IAAImAAQJaxciBgA/AQAmAAQJaxciBgA/AQAuAAQKfxQAAiYACQnsHmgDALoCACYACQnsHmgDALoCAAEuAAUUBAkJAAYA5xkA.',
Me='Meqi:BAABLgAECn8dAAMLAAYJ0hwnggBYAQALAAYJ0hwnggBYAQAnAAEJDBcVDgBGAAAAAA==.',
Mi='Mikàsa:BAABLgAECn8mAAMMAAkJSBB+EwD/AQAMAAkJSBB+EwD/AQAKAAYJXwmaTgAVAQAAAA==.Minand:BAAALgAECgYJEQAAAA==.Mindlessness:BAABLgAECn8yAAIYAAkJ5yOBBAAMAwAYAAkJ5yOBBAAMAwAAAA==.Mineralelf:BAABLgAECn81AAIEAAkJoQx+SACwAQAEAAkJoQx+SACwAQAAAA==.Minichaos:BAABLgAECn8rAAMDAAcJvxrJBgDTAQADAAcJvxrJBgDTAQACAAQJgAaqywCqAAAAAA==.Miriam:BAABLgAECn8dAAIoAAcJjAUOCQDjAAAoAAcJjAUOCQDjAAAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8fAAIBAAgJvCIpBwD5AgABAAgJvCIpBwD5AgAAAA==.',
Mo='Mojosavage:BAABLgAECn8YAAICAAcJ7gIsyACwAAACAAcJ7gIsyACwAAAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAgAAAA==.Moonblade:BAAALgAECgYJCwAAAA==.Mortshan:BAABLgAECn8bAAInAAkJRhZ1AgAPAgAnAAkJRhZ1AgAPAgAAAA==.Mournfull:BAAALgAECgEJBAAAAA==.',
My='Mysticalfox:BAAALgAECgQJBgAAAA==.',
Na='Nalfilas:BAAALgAECgUJDQAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgAECggJDQAAAA==.Nikru:BAAALgAFFAMJBAABLgAFFAcJFwAQAHMNAA==.Ninok:BAABLgAECn8jAAIGAAkJPBNYQwDkAQAGAAkJPBNYQwDkAQAAAA==.',
No='Nocturnous:BAAALgAECgEJAQAAAA==.Nornee:BAABLgAECn8kAAIZAAgJ0A6LTQBdAQAZAAgJ0A6LTQBdAQAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8dAAIcAAgJRR33CAAZAgAcAAgJRR33CAAZAgAAAA==.',
['Nà']='Nàtureswrath:BAAALgAECgMJBgAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAABLgAECn8bAAMYAAgJ0xGQLwB8AQAYAAgJ0xGQLwB8AQAXAAEJ4wwXbQAtAAAAAA==.',
Ol='Ollïee:BAAALgAECgYJBgAAAA==.',
Op='Oprawyndfury:BAAALgAECgcJCwAAAA==.',
Or='Orceo:BAABLgAECn8lAAIEAAkJ+iPIBQAxAwAEAAkJ+iPIBQAxAwAAAA==.Orkreghar:BAAALgAECgEJAwAAAA==.',
Os='Osaro:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgAECgIJAgAAAA==.',
Ow='Ownlyshamz:BAAALgADCgMJAwABLgAECggJCQAJAAAAAA==.',
Ox='Oxcanor:BAAALgAECgEJAQAAAA==.',
Pa='Patches:BAAALgAECgUJBwABLgAECggJHwABALwiAA==.',
Pe='Pepsipoutine:BAABLgAECn8WAAICAAYJmB+9TgDcAQACAAYJmB+9TgDcAQAAAA==.Petiterage:BAAALgADCggJCwAAAA==.',
Pi='Pindapind:BAAALgADCgMJBAABLgAECgkJNQAWAA8mAA==.Pindapinda:BAAALgAECggJDAABLgAECgkJNQAWAA8mAA==.',
Pl='Plaguexion:BAAALgADCgQJBgAAAA==.',
Po='Pompompower:BAABLgAECn8xAAIFAAkJGQjUNwA9AQAFAAkJGQjUNwA9AQAAAA==.Popple:BAABLgAECn8sAAIYAAkJ5xBPHgDoAQAYAAkJ5xBPHgDoAQAAAA==.Potential:BAACLgAFFH8JAAIkAAMJDhthKQDxAAAkAAMJDhthKQDxAAAuAAQKfyMAAiQACQkJGqYNAEoCACQACQkJGqYNAEoCAAAA.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgUJEAAAAA==.Puggsly:BAAALgAECgEJAwAAAA==.Pugsta:BAAALgAECgQJBwABLgAECggJEgAJAAAAAA==.',
Py='Pyrocaster:BAAALgAECgQJBQAAAA==.',
Qa='Qaccy:BAABLgAECn8SAAIfAAcJxQzDOwD/AAAfAAcJxQzDOwD/AAAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAABLgAECn8bAAIYAAgJzhkDJQC5AQAYAAgJzhkDJQC5AQAAAA==.',
Ra='Radaghast:BAAALgAECgEJAQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Regret:BAAALgAFFAEJAQABLgAFFAgJJgAeAG4WAA==.Reishirome:BAAALgAECgEJAQAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8eAAIVAAgJPSIZAwDlAgAVAAgJPSIZAwDlAgAAAA==.',
Rh='Rhogar:BAAALgAECgMJBAAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8fAAITAAkJjganMgA1AQATAAkJjganMgA1AQAAAA==.Romeoz:BAAALgADCgEJAQAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAAALgAECgYJEgAAAA==.',
Ru='Rumincoke:BAAALgADCgkJEwAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAABLgAECn8lAAIOAAYJ+SGTFAAaAgAOAAYJ+SGTFAAaAgAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwAJAAAAAA==.',
Sc='Scalygrob:BAAALgAECgkJEwAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8uAAIUAAkJ6RcqDQB+AgAUAAkJ6RcqDQB+AgAAAA==.Sellphie:BAAALgADCgcJCAAAAA==.',
Sh='Shadowhntr:BAAALgAECgEJAwAAAA==.Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shavedussy:BAAALgADCgUJBQAAAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Siknes:BAAALgAECggJCAABLgAECgkJLAARAE8eAA==.Simmareth:BAAALgADCgcJBwAAAA==.Simpofmeerah:BAAALgAECgYJBwAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgYJDAAAAA==.',
Sl='Slargerita:BAAALgADCgcJBwAAAA==.',
Sm='Smallmoon:BAAALgAECgEJAQAAAA==.Smogcheck:BAACLgAFFH8PAAIgAAQJSxEHFgATAQAgAAQJSxEHFgATAQAuAAQKfyEAAyAACQkOE2gbAK0BACAACQkOE2gbAK0BACIAAQl9CNM+ADQAAAAA.',
Sn='Snackcake:BAABLgAECn8oAAIQAAkJvBpiEQCyAgAQAAkJvBpiEQCyAgAAAA==.Snakeoil:BAABLgAECn8cAAMFAAkJyh7TDQB4AgAFAAkJyh7TDQB4AgAZAAEJCgKi0gAiAAAAAA==.Snowsz:BAAALgAECgIJAgAAAA==.Snowws:BAABLgAECn8eAAISAAkJ9xpaHQBQAgASAAkJ9xpaHQBQAgAAAA==.',
So='Sortis:BAABLgAECn8kAAILAAkJFRjeMwCjAgALAAkJFRjeMwCjAgAAAA==.',
Sp='Spicebreff:BAAALgAECggJCQAAAA==.Spongerunner:BAAALgAECgcJDwAAAA==.Sprucetea:BAAALgADCgIJAwAAAA==.',
St='Steck:BAABLgAECn8yAAIEAAgJ9hWDQQDGAQAEAAgJ9hWDQQDGAQAAAA==.Strigo:BAABLgAFFH8OAAQMAAQJdRhADwBCAQAMAAQJCBhADwBCAQAEAAEJtBy7IABfAAAKAAEJnwy7KABKAAAAAA==.',
Su='Subway:BAAALgAECggJEAAAAA==.Sunbaby:BAABLgAECn8oAAIeAAgJnh69BQAuAgAeAAgJnh69BQAuAgAAAA==.',
['Sà']='Sàlís:BAAALgADCgkJDgAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8gAAIUAAkJdCBJBQD9AgAUAAkJdCBJBQD9AgAAAA==.Takhisoth:BAAALgADCgYJBgAAAA==.Talandaru:BAAALgAECgEJAwAAAA==.Talas:BAABLgAECn8yAAMEAAkJFh5qEgCoAgAEAAkJFh5qEgCoAgAKAAUJswr3VwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Te='Temberle:BAAALgAECgMJAwABLgAECggJOAADAKURAA==.Temerald:BAAALgADCgkJCQAAAA==.Tevoran:BAAALgAECgUJCgAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thaelidari:BAAALgAECgkJDAAAAA==.Thieridan:BAAALgADCgIJBAAAAA==.Thrangus:BAAALgAECgIJAgABLgAECgkJHwAHAOsiAA==.Thrann:BAABLgAECn8fAAMHAAkJ6yIXCADjAQAIAAcJqSKfOgBNAgAHAAUJhyMXCADjAQAAAA==.Thunderdex:BAACLgAFFH8NAAMSAAcJpBYMEwDZAQASAAcJpBYMEwDZAQAbAAEJ6ANHJgAzAAAuAAQKfx8AAhIACQl+HkQcAFYCABIACQl+HkQcAFYCAAAA.',
Ti='Tirium:BAAALgAECgcJCAABLgAECggJCQAJAAAAAA==.',
To='Togglesmith:BAAALgAECgQJBAAAAA==.Togglestein:BAAALgAECgUJBQAAAA==.Togglethorp:BAAALgAECgUJBQAAAA==.Togi:BAAALgADCgcJDQAAAA==.',
Tr='Trinitum:BAAALgAECgcJCwABLgAECggJCQAJAAAAAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Ud='Udderduckie:BAAALgAECgEJAgAAAA==.',
Un='Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJCwAAAA==.Ursoconha:BAAALgAECgYJCgABLgAFFAYJBgALAIsYAA==.',
Va='Vaadboolin:BAAALgAECggJEgAAAA==.Vallies:BAABLgAECn8yAAMoAAYJfwWQDQDvAAAoAAYJRAWQDQDvAAALAAUJjQTE/QCJAAAAAA==.Vallius:BAABLgAECn8dAAIRAAkJ5BJRFgDUAQARAAkJ5BJRFgDUAQAAAA==.Vanargandr:BAAALgAECggJDgAAAA==.',
Ve='Verðandi:BAAALgAECgIJAgAAAA==.',
Vo='Volcano:BAABLgAECn8bAAICAAkJIxpBIwBHAgACAAkJIxpBIwBHAgAAAA==.Volvox:BAAALgADCgEJAQAAAA==.Vonslarge:BAAALgADCgkJCQAAAA==.',
Vy='Vyxenn:BAABLgAECn8xAAMZAAkJ0xZuHQBHAgAZAAkJ0xZuHQBHAgAFAAMJVQrcdQBoAAAAAA==.',
Wa='Waffletoast:BAAALgADCgkJEQABLgAECgkJJgAfAJkhAA==.Wanders:BAABLgAECn8qAAMLAAkJIBpKIgB+AgALAAkJIBpKIgB+AgAoAAYJLAmdCwAcAQAAAA==.Warlockk:BAAALgAECgQJBAAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Wu='Wurm:BAAALgAECgcJBwABLgAECgkJDQAJAAAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yep:BAACLgAFFH8KAAIGAAQJVRg/JABUAQAGAAQJVRg/JABUAQAuAAQKfxsAAgYACQnwI/IHABkDAAYACQnwI/IHABkDAAAA.Yesenìa:BAAALgAECgUJBAAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zavia:BAAALgADCgUJCQAAAA==.Zazael:BAAALgAECgIJAgAAAA==.Zazreal:BAABLgAECn84AAQiAAkJgh2UAgB/AgAiAAkJgh2UAgB/AgAhAAMJ4Q9oSwClAAAgAAQJ7wKBKQCGAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn85AAImAAkJ7gYaEwBlAQAmAAkJ7gYaEwBlAQAAAA==.Zillyanna:BAAALgAECggJEwAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zyper:BAAALgAECgQJBwAAAA==.Zywol:BAABLgAECn8mAAQTAAkJ5hj5EQA0AgATAAkJ5hj5EQA0AgAQAAMJlgbIpgB6AAAVAAEJjA/bYwArAAAAAA==.',
['Ër']='Ëresta:BAABLgAECn8cAAILAAcJXAw9jwA+AQALAAcJXAw9jwA+AQAAAA==.',
['Ðe']='Ðesire:BAAALgAECgYJCAAAAA==.Ðespair:BAACLgAFFH8LAAIfAAQJFB9jDQBqAQAfAAQJFB9jDQBqAQAuAAQKfzQABBQACQklICQKAJYCABQABwk9ISQKAJYCAB8ACQltH1AKAI8CAA4ABQmTGJs8AOoAAAAA.',
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
