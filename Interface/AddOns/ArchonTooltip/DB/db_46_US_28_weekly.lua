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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Elemental','Paladin-Retribution','Unknown-Unknown','Hunter-Marksmanship','Mage-Frost','Hunter-Survival','Paladin-Protection','Priest-Holy','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Rogue-Subtlety','DemonHunter-Devourer','Shaman-Enhancement','DeathKnight-Frost','Druid-Balance','Priest-Discipline','Druid-Guardian','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','DemonHunter-Havoc','Druid-Feral','Monk-Mistweaver','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Monk-Brewmaster','Rogue-Assassination','Mage-Fire','Mage-Arcane','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm='Baelgun',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abaddón:BAAALgAECgEJAQABLgAECggJHwABALwiAA==.Abfuscatedd:BAABLgAECn8iAAMCAAkJaBM9LADpAQACAAkJaBM9LADpAQADAAEJAAARgAATAAAAAA==.',
Ac='Acharia:BAAALgADCgkJDgABLgAECgYJFgAEAPoYAA==.Acidrain:BAABLgAECn8xAAIFAAkJ1yASBQDZAgAFAAkJ1yASBQDZAgAAAA==.Acmiax:BAABLgAECn8aAAMGAAcJQhskeACKAQAGAAYJhhkkeACKAQABAAUJuQsOQgDlAAAAAA==.',
Ad='Adar:BAAALgAECgQJBAAAAA==.',
Ae='Aep:BAAALgAECgUJCQABLgAECgMJAwAHAAAAAA==.',
Ah='Ahrmanhamma:BAACLgAFFH8HAAIGAAQJpBgiGABdAQAGAAQJpBgiGABdAQAuAAQKfxoAAgYACQktIqIIAPECAAYACQktIqIIAPECAAAA.Ahu:BAABLgAECn8nAAMEAAgJsRcuMADwAQAEAAgJsRcuMADwAQAIAAMJZAQjcwBxAAAAAA==.',
Ai='Airocket:BAAALgAECgQJBQAAAA==.',
Al='Al:BAAALgAECgEJAQABLgAECgYJCAAHAAAAAA==.Alakazam:BAAALgADCgUJBQAAAA==.Alakill:BAAALgAECgQJDAAAAA==.Alandramun:BAAALgADCgkJCQAAAA==.Aleroderp:BAABLgAECn87AAMEAAkJOhDzKgDhAQAEAAkJ+g/zKgDhAQAIAAgJnwweNQCVAQAAAA==.Alerus:BAAALgAECgEJAQAAAA==.Alexander:BAABLgAECn8eAAIJAAkJixrzJgDXAgAJAAkJixrzJgDXAgAAAA==.Alexijones:BAABLgAECn8cAAIKAAkJJA9rEQDbAQAKAAkJJA9rEQDbAQAAAA==.Allaria:BAAALgAECgMJAwAAAA==.',
Am='Ambassador:BAABLgAECn8eAAILAAkJkxc8BwAXAgALAAkJkxc8BwAXAgAAAA==.Amoondai:BAACLgAFFH8QAAIMAAMJiSFXDQAcAQAMAAMJiSFXDQAcAQAuAAQKfz8AAgwACQmkJM8AAKcDAAwACQmkJM8AAKcDAAAA.',
Ap='Apoch:BAAALgADCgEJAQAAAA==.Apochryphal:BAABLgAECn83AAMNAAkJpiEXAwDeAgANAAkJpiEXAwDeAgAOAAYJ7wNo0gDcAAAAAA==.Apolyon:BAABLgAECn8mAAIPAAkJLiHKBQApAwAPAAkJLiHKBQApAwAAAA==.',
Ar='Araon:BAAALgAECgYJBgAAAA==.Arcadian:BAAALgAECgQJBAAAAA==.',
At='Atroxz:BAAALgADCgcJCAAAAA==.',
Ba='Bacstabath:BAABLgAECn8sAAIQAAkJTx4XBgAvAwAQAAkJTx4XBgAvAwAAAA==.Baggadonuts:BAAALgADCgYJBQABLgAFFAQJBwAGAKQYAA==.Banshee:BAABLgAECn8eAAIRAAkJ0x/jCwCtAgARAAkJ0x/jCwCtAgAAAA==.Baychan:BAAALgAECgIJAgABLgAECggJHgASAPAhAA==.',
Be='Becca:BAABLgAECn8vAAILAAkJYxaOBwANAgALAAkJYxaOBwANAgAAAA==.Berries:BAAALgAECgEJAQAAAA==.',
Bi='Bigdamaj:BAABLgAECn8uAAMTAAkJExkkBQDxAQATAAgJwxckBQDxAQAOAAkJBhS2OADXAQAAAA==.Birbdormu:BAAALgAECgQJBQABLgAECgkJLwAUAFAeAA==.',
Bl='Bloodiblind:BAAALgAECgQJBAAAAA==.Bloodios:BAABLgAECn8wAAINAAkJfh5jBACxAgANAAkJfh5jBACxAgAAAA==.Blázé:BAAALgADCgEJAQAAAA==.',
Bo='Bobin:BAAALgADCgcJCAABLgAECgkJHQAVAOsQAA==.Bobinforapl:BAABLgAECn8dAAIVAAkJ6xBEFgDNAQAVAAkJ6xBEFgDNAQAAAA==.Bombadil:BAABLgAECn8xAAIVAAkJvARYIABtAQAVAAkJvARYIABtAQAAAA==.',
Br='Bribage:BAABLgAECn8vAAQUAAkJUB40BwCdAgAUAAkJ/R00BwCdAgAWAAQJHRKfHgDUAAAPAAEJtyGUiwBeAAAAAA==.Brolavski:BAAALgAECgEJAQABLgAECgYJCAAHAAAAAA==.Bruceleeroi:BAAALgAECgEJAQAAAA==.',
Bu='Buckey:BAAALgAECgUJBwABLgAECgcJCgAHAAAAAA==.Budderwar:BAABLgAECn8tAAMXAAkJBibzAABGAwAXAAkJBibzAABGAwAYAAMJvw4KhwCjAAAAAA==.Bundaberg:BAAALgADCgkJEgAAAA==.Bunny:BAAALgAECgIJBQAAAA==.',
['Bà']='Bàdmofos:BAAALgAECgQJBwAAAA==.',
Ca='Callyday:BAAALgADCgMJAwAAAA==.',
Cb='Cbreezy:BAAALgAECgEJAQAAAA==.',
Ce='Celjska:BAAALgAECgUJBgAAAA==.Cerel:BAAALgADCgYJBgAAAA==.',
Ch='Chikñ:BAABLgAECn8aAAMZAAgJ7glLQQBGAQAZAAgJ7glLQQBGAQAFAAYJjw/kQABGAQAAAA==.Chronaus:BAAALgAECgQJBgAAAA==.Chuanthu:BAAALgADCgEJAQAAAA==.Chug:BAAALgAECgEJAQAAAA==.',
Ci='Cinderspella:BAAALgAECgIJAgAAAA==.Cindresh:BAAALgADCgcJCgAAAA==.Citan:BAABLgAECn8uAAIaAAkJdCUFAQBZAwAaAAkJdCUFAQBZAwAAAA==.',
Co='Cocoredbull:BAABLgAECn8dAAIWAAkJdw6NFAA6AQAWAAkJdw6NFAA6AQAAAA==.Corrail:BAAALgAECgYJCgAAAA==.Correin:BAABLgAECn8eAAIbAAkJbg8uFgBwAQAbAAkJbg8uFgBwAQAAAA==.',
Cr='Craszhin:BAABLgAECn8cAAIUAAkJmQ7VGwCQAQAUAAkJmQ7VGwCQAQAAAA==.',
Cy='Cyclonic:BAAALgADCgEJAgAAAA==.',
['Cè']='Cèl:BAABLgAECn8zAAIJAAkJIwzPTgCsAQAJAAkJIwzPTgCsAQAAAA==.',
Da='Daenore:BAAALgADCgcJDgAAAA==.Dardris:BAAALgADCgMJAwAAAA==.Darkdelight:BAAALgAECgkJEwAAAA==.Darkwater:BAAALgADCgkJCQAAAA==.',
De='Deets:BAABLgAECn8uAAIEAAkJ0R6bDACpAgAEAAkJ0R6bDACpAgAAAA==.Defoy:BAABLgAECn8WAAMIAAYJJhn8EQD2AAAIAAYJ4xb8EQD2AAAEAAQJZxDFpACFAAAAAA==.Demona:BAABLgAECn8qAAMDAAgJUgxpDAApAQADAAgJUgxpDAApAQACAAYJWgPDqACtAAAAAA==.Demonicfates:BAABLgAECn8bAAIbAAgJWA7BFwBeAQAbAAgJWA7BFwBeAQAAAA==.Derffy:BAABLgAECn8eAAIcAAcJqhwwCADuAQAcAAcJqhwwCADuAQAAAA==.Descalabrada:BAAALgAECgQJCAAAAA==.Devourdeez:BAAALgADCgQJBAAAAA==.',
Di='Distol:BAAALgAECgQJBAAAAA==.',
Dm='Dmt:BAABLgAECn8iAAIdAAgJBx1cDwBFAgAdAAgJBx1cDwBFAgAAAA==.',
Do='Dotemdown:BAAALgAECgIJAgAAAA==.',
Dr='Draiara:BAAALgAECgMJAwAAAA==.Dropdeadx:BAAALgAECgYJDQAAAA==.Drpep:BAAALgAECgcJEgABLgAECggJHwABALwiAA==.Drpeppers:BAABLgAECn8kAAMPAAkJ1gjYPwBKAQAPAAkJ1gjYPwBKAQAWAAEJAAAUPAAMAAAAAA==.',
Du='Durroz:BAAALgAECgEJAQAAAA==.',
['Dé']='Déathsavage:BAAALgADCgkJKgAAAA==.',
Ea='Earthling:BAAALgAECgUJCgAAAA==.',
Ec='Eclair:BAABLgAECn8tAAMZAAkJDBRFHgADAgAZAAkJDBRFHgADAgAFAAMJXxqsQQDUAAAAAA==.',
Ed='Edelgard:BAAALgAECgMJAwAAAA==.',
Ee='Eelli:BAAALgAECgQJBAABLgAECgkJLAAQAE8eAA==.',
El='Eleysia:BAAALgADCgkJDwAAAA==.Elf:BAAALgAECgYJBgABLgAECggJIAAGAAEmAA==.Elhayn:BAAALgAECgQJBAAAAA==.Elmore:BAAALgAECgQJBAAAAA==.Elmos:BAABLgAECn8tAAIaAAkJ7B5oBgCkAgAaAAkJ7B5oBgCkAgAAAA==.',
Er='Erestadh:BAAALgAECgEJAgABLgAECgcJHAAJAF0MAA==.',
Ev='Evilmonkeymg:BAEALgAECgEJAQABLgAECgkJGQAFACceAA==.Evilmonkeysh:BAEBLgAECn8ZAAMFAAkJJx5eHAAvAgAFAAkJJx5eHAAvAgAZAAcJQQvdTABPAQAAAA==.Evilmonkeywl:BAEALgADCgYJBgABLgAECgkJGQAFACceAA==.',
Ex='Exto:BAAALgAECgMJBAABLgAECgQJBAAHAAAAAA==.',
Ey='Eyeballs:BAAALgADCgUJBQAAAA==.',
Ez='Ezaylia:BAABLgAECn8pAAIbAAkJ2hW+CgAcAgAbAAkJ2hW+CgAcAgAAAA==.',
Fe='Felclaw:BAAALgAECgEJBAAAAA==.Fenrisulfr:BAAALgAECgEJAQABLgAECggJDQAHAAAAAA==.Ferg:BAAALgAECgQJBAABLgAECgkJMQAJAHMhAA==.Fergis:BAABLgAECn8xAAIJAAkJcyHyDADhAgAJAAkJcyHyDADhAgAAAA==.Fergle:BAAALgAECgMJAwAAAA==.Fetchme:BAAALgAECgQJBwAAAA==.Fetchyou:BAAALgADCggJDgAAAA==.',
Fi='Fiery:BAAALgADCgIJAwAAAA==.Firefox:BAABLgAECn8dAAMNAAkJsBc8EgDoAQANAAkJ+xY8EgDoAQATAAcJ0RVDCQBIAQAAAA==.',
Fl='Flypig:BAAALgAECggJEAAAAA==.',
Fr='Freecaster:BAAALgAECgMJAwAAAA==.Frostybeary:BAAALgAECgcJBwAAAA==.Frostymonk:BAABLgAECn8YAAIdAAcJOQnmOgDqAAAdAAcJOQnmOgDqAAAAAA==.Frozenwaffle:BAAALgAECgUJCQABLgAECgkJIwAeAGkhAA==.',
Fu='Furryben:BAAALgADCgkJGgAAAA==.',
['Fá']='Fállen:BAAALgADCgQJBAAAAA==.',
Ga='Galeste:BAAALgAECgQJBAAAAA==.',
Gi='Gigem:BAAALgAECgUJCwAAAA==.Girlshoon:BAAALgAECgEJAQAAAA==.',
Gl='Glarheals:BAABLgAECn8bAAQfAAkJkASTIwBcAQAfAAkJkASTIwBcAQAgAAUJ9gP/SgCoAAAhAAEJlQGoIAAZAAAAAA==.Glarious:BAAALgAECgYJDQABLgAECgkJGwAfAJAEAA==.',
Go='Golakuron:BAAALgADCgUJBQAAAA==.Goldarrow:BAAALgADCgQJBAAAAA==.',
Gr='Granolaf:BAAALgAECgYJCAAAAA==.Greenwaffle:BAABLgAECn8jAAMeAAkJaSESDQCyAgAeAAkJaSESDQCyAgAMAAYJwBTCNQBmAQAAAA==.Grôg:BAAALgAECgUJBwABLgAECgcJBwAHAAAAAA==.',
Gu='Guldaniel:BAAALgAECgQJBQAAAA==.Guthx:BAABLgAECn8eAAIPAAkJzBjtGAA2AgAPAAkJzBjtGAA2AgAAAA==.',
Ha='Harutah:BAAALgAECgQJBAAAAA==.',
He='Heping:BAAALgADCgUJBgABLgAECgQJBgAHAAAAAA==.',
Ho='Holymolii:BAABLgAECn8mAAILAAgJoBfiCwCxAQALAAgJoBfiCwCxAQAAAA==.Hotcoffee:BAAALgAECgYJDgAAAA==.',
Hu='Huntermaster:BAABLgAECn8bAAQKAAgJFRemFQCtAQAKAAcJwBemFQCtAQAIAAUJRxiERABDAQAEAAEJEBL82QA4AAABLgAECgkJLQAXAAYmAA==.',
Il='Ilulz:BAAALgADCgEJAQAAAA==.',
In='Incredabull:BAABLgAECn8UAAIXAAYJjhgsFQBQAQAXAAYJjhgsFQBQAQAAAA==.Intrepidz:BAAALgAECgEJAQABLgAECgkJJAAJABYYAA==.',
Is='Isabelle:BAAALgADCgcJBwAAAA==.Isharded:BAABLgAECn8qAAIiAAkJQxRhBADxAQAiAAkJQxRhBADxAQAAAA==.Istayblunted:BAABLgAECn8bAAILAAcJrh8QEADEAQALAAcJrh8QEADEAQAAAA==.',
It='Itwasme:BAAALgAECgQJDQAAAA==.',
Iw='Iwinwithhots:BAAALgAECgEJAgABLgAECgcJGAAGAIceAA==.',
Ji='Jiayerah:BAAALgAECgIJAgABLgAECgYJGQAMAPkhAA==.Jinkuzo:BAABLgAECn8vAAIjAAkJHB9SBgCfAgAjAAkJHB9SBgCfAgAAAA==.Jinmu:BAABLgAECn8uAAMQAAkJwBQVDgD2AQAQAAkJwBQVDgD2AQAkAAEJJgsfHwA1AAAAAA==.',
Ju='Juggie:BAABLgAECn8mAAIMAAgJZRPuGAC7AQAMAAgJZRPuGAC7AQAAAA==.Juggsië:BAAALgADCgkJCQAAAA==.Julienned:BAABLgAECn8mAAIkAAkJigvmBwCIAQAkAAkJigvmBwCIAQAAAA==.',
Ka='Kagami:BAAALgAECgIJAgAAAA==.Kaiju:BAAALgADCgcJCwAAAA==.Kalath:BAABLgAECn8XAAMCAAkJfxoaGQBUAgACAAkJVBoaGQBUAgADAAEJFBvWawA8AAAAAA==.',
Kh='Khrodors:BAAALgADCgMJAwAAAA==.',
Ki='Kiannis:BAAALgADCgEJAQAAAA==.Kickerr:BAAALgAECgYJCgABLgAECgkJIwAjAAAaAA==.Kickrr:BAAALgAECgYJBgABLgAECgkJIwAjAAAaAA==.',
Kl='Klodar:BAAALgAECgEJAQAAAA==.Klum:BAAALgAECgEJAQAAAA==.',
Kr='Krazee:BAAALgADCgEJAQAAAA==.Krunkle:BAAALgAECgIJAwAAAA==.',
Kv='Kvothe:BAAALgADCgUJBQAAAA==.',
La='Lanfear:BAAALgADCgcJCwAAAA==.Laravin:BAAALgADCgYJBgAAAA==.',
Lc='Lcpiss:BAAALgADCgEJAQAAAA==.',
Le='Leida:BAAALgAECgIJAgAAAA==.Lendela:BAAALgAECgUJDAAAAA==.',
Li='Liljugg:BAAALgAECgYJDAAAAA==.',
Lm='Lmaddk:BAAALgAECgIJAgAAAA==.',
Lo='Logi:BAAALgAECgMJAwAAAA==.Lor:BAAALgAECgQJBQAAAA==.Lostmana:BAAALgAECgIJAgAAAA==.Loudlarry:BAAALgAECgYJCgAAAA==.',
Ly='Lygor:BAABLgAECn8nAAIEAAgJhhGyOwCbAQAEAAgJhhGyOwCbAQAAAA==.',
['Lú']='Lúná:BAAALgADCgYJBgABLgAECggJHwABALwiAA==.',
Ma='Maelle:BAAALgADCgYJBQAAAA==.Majellan:BAAALgAECgMJBgAAAA==.Makrub:BAAALgAECggJDQAAAA==.Malystryix:BAAALgADCgIJAgAAAA==.Mandigosa:BAAALgAECgIJAgAAAA==.Marist:BAAALgAECgEJAwAAAA==.Marrius:BAAALgAECgEJAQAAAA==.Marsawn:BAABLgAECn8gAAMeAAkJEhjCDAA4AgAeAAkJEhjCDAA4AgAMAAMJYBiCOADNAAAAAA==.',
Mc='Mcpeepants:BAABLgAECn8UAAISAAkJ6h7dAQDVAgASAAkJ6h7dAQDVAgABLgAFFAQJBwAGAKQYAA==.',
Me='Meqi:BAABLgAECn8XAAMJAAYJ0hxnZwBuAQAJAAYJ0hxnZwBuAQAlAAEJDBcVDgBGAAAAAA==.',
Mi='Mikàsa:BAABLgAECn8kAAMKAAgJsxB9FAC4AQAKAAgJsxB9FAC4AQAIAAYJXwmaTgAVAQAAAA==.Minand:BAAALgAECgYJEQAAAA==.Mindlessness:BAABLgAECn8yAAIYAAkJFiT6AQAuAwAYAAkJFiT6AQAuAwAAAA==.Mineralelf:BAABLgAECn8xAAIEAAkJ6QugNgCvAQAEAAkJ6QugNgCvAQAAAA==.Minichaos:BAABLgAECn8cAAMDAAcJyBMxCgBPAQADAAcJyBMxCgBPAQACAAQJgAZwqACtAAAAAA==.Miriam:BAABLgAECn8WAAImAAYJ5gTmCAC9AAAmAAYJ5gTmCAC9AAAAAA==.Mistmaster:BAAALgADCgMJAwAAAA==.Mittensqt:BAABLgAECn8fAAIBAAgJvCIpBwD5AgABAAgJvCIpBwD5AgAAAA==.',
Mo='Mojosavage:BAABLgAECn8YAAICAAcJ7gKEpQCzAAACAAcJ7gKEpQCzAAAAAA==.Monchidruid:BAAALgADCgQJBAAAAA==.Monmouth:BAAALgADCgEJAgAAAA==.Moonblade:BAAALgAECgQJBAAAAA==.Mortshan:BAABLgAECn8bAAIlAAkJQhafAQAgAgAlAAkJQhafAQAgAgAAAA==.Mournfull:BAAALgAECgEJAQAAAA==.',
My='Mysticalfox:BAAALgAECgQJBgAAAA==.',
Na='Nalfilas:BAAALgAECgQJDAAAAA==.Naliqa:BAAALgAECgMJAwAAAA==.',
Ne='Nephìon:BAAALgADCgcJBwAAAA==.',
Ni='Nihlus:BAAALgAECgUJBQAAAA==.Nikru:BAAALgAECgMJAwABLgAFFAUJEwAPAEcRAA==.Ninok:BAABLgAECn8aAAIGAAkJmhAAOgDSAQAGAAkJmhAAOgDSAQAAAA==.',
No='Nornee:BAABLgAECn8dAAIZAAcJ8w7dSgBXAQAZAAcJ8w7dSgBXAQAAAA==.Nowyouseeme:BAAALgADCgQJBAAAAA==.',
Ny='Nyrvana:BAABLgAECn8dAAIcAAgJRR1HBgAmAgAcAAgJRR1HBgAmAgAAAA==.',
['Nà']='Nàtureswrath:BAAALgAECgIJAwAAAA==.',
['Në']='Nërdrage:BAAALgADCgcJBgAAAA==.',
Og='Ogre:BAABLgAECn8bAAMYAAgJ0xGQJACCAQAYAAgJ0xGQJACCAQAnAAEJ4ww8UgAtAAAAAA==.',
Ol='Ollïee:BAAALgAECgUJBQAAAA==.',
Op='Oprawyndfury:BAAALgAECgcJCgAAAA==.',
Or='Orceo:BAABLgAECn8gAAIEAAkJ+iPIBQAxAwAEAAkJ+iPIBQAxAwAAAA==.Orkreghar:BAAALgAECgEJAgAAAA==.',
Os='Osaro:BAAALgAECgEJAQAAAA==.',
Ov='Overdose:BAAALgAECgIJAgAAAA==.',
Ow='Ownlyshamz:BAAALgADCgMJAwAAAA==.',
Ox='Oxcanor:BAAALgADCgkJDwAAAA==.',
Pa='Patches:BAAALgAECgUJBwABLgAECggJHwABALwiAA==.',
Pe='Pepsipoutine:BAABLgAECn8WAAICAAYJmB+9TgDcAQACAAYJmB+9TgDcAQAAAA==.Petiterage:BAAALgADCggJCwAAAA==.',
Pi='Pindapind:BAAALgADCgMJBAABLgAECgkJLQAXAAYmAA==.',
Pl='Plaguexion:BAAALgADCgQJBgAAAA==.',
Po='Pompompower:BAABLgAECn8pAAIFAAkJWQdxLwAoAQAFAAkJWQdxLwAoAQAAAA==.Popple:BAABLgAECn8kAAIYAAgJ4A09JwBxAQAYAAgJ4A09JwBxAQAAAA==.Potential:BAABLgAECn8jAAIjAAkJEBoWDAA5AgAjAAkJEBoWDAA5AgAAAA==.',
Pr='Prepared:BAAALgADCgkJDwAAAA==.',
Pu='Pubstar:BAAALgAECgUJEAAAAA==.Puggsly:BAAALgAECgEJAgAAAA==.Pugsta:BAAALgAECgIJAgABLgAECggJEgAHAAAAAA==.',
Qa='Qaccy:BAABLgAECn8SAAIeAAcJxQztLQAWAQAeAAcJxQztLQAWAQAAAA==.',
Qu='Quixotical:BAAALgADCgMJAwAAAA==.',
['Qê']='Qêxê:BAABLgAECn8bAAIYAAgJzhkCGgDOAQAYAAgJzhkCGgDOAQAAAA==.',
Ra='Radaghast:BAAALgAECgEJAQAAAA==.Radicalrage:BAAALgADCgcJBwAAAA==.Rathe:BAAALgADCgUJBQAAAA==.Raven:BAAALgADCgEJAQAAAA==.',
Re='Reishirome:BAAALgADCgkJJgAAAA==.Reject:BAAALgAECgMJAwAAAA==.Reymoon:BAABLgAECn8eAAIWAAgJPSIZAwDlAgAWAAgJPSIZAwDlAgAAAA==.',
Rh='Rhogar:BAAALgAECgMJBAAAAA==.',
Rm='Rmx:BAAALgAECgUJBQAAAA==.',
Ro='Rofellos:BAABLgAECn8fAAIUAAkJjgapJwA1AQAUAAkJjgapJwA1AQAAAA==.Rona:BAAALgAECgMJAwAAAA==.Roofhouse:BAAALgAECgYJDAAAAA==.',
Ru='Rumincoke:BAAALgADCgkJEwAAAA==.',
Ry='Ryebacker:BAAALgAECgYJCQAAAA==.',
Sa='Sacerdote:BAAALgADCgUJBQAAAA==.Sansa:BAABLgAECn8ZAAIMAAYJ+SEWDwAsAgAMAAYJ+SEWDwAsAgAAAA==.Saucin:BAAALgADCgYJCwABLgAECgMJAwAHAAAAAA==.',
Sc='Scalygrob:BAAALgAECgkJEwAAAA==.Scrügemcmonk:BAAALgADCggJEwAAAA==.',
Se='Selatey:BAABLgAECn8rAAIVAAkJAReSCwBgAgAVAAkJAReSCwBgAgAAAA==.Sellphie:BAAALgADCgYJBgAAAA==.',
Sh='Shadowhntr:BAAALgAECgEJAQAAAA==.Shadôh:BAAALgADCgMJAwAAAA==.Shamannexus:BAAALgAECgYJCAAAAA==.Shavedussy:BAAALgADCgUJBQAAAA==.Shockzalot:BAAALgAECgMJAwAAAA==.',
Si='Simpofmeerah:BAAALgAECgYJBwAAAA==.',
Sk='Skadirage:BAAALgAECggJAQAAAA==.Skinsgetwins:BAAALgAECgYJDAAAAA==.',
Sl='Slargerita:BAAALgADCgcJBwAAAA==.',
Sm='Smogcheck:BAACLgAFFH8IAAIfAAMJ6hRwFQDbAAAfAAMJ6hRwFQDbAAAuAAQKfyEAAx8ACQkPE2gbAK0BAB8ACQkPE2gbAK0BACEAAQl9CNM+ADQAAAAA.',
Sn='Snackcake:BAABLgAECn8mAAIPAAgJSRxDEgB4AgAPAAgJSRxDEgB4AgAAAA==.Snakeoil:BAABLgAECn8cAAMFAAkJyx7GCACMAgAFAAkJyx7GCACMAgAZAAEJCgL5pwAiAAAAAA==.Snowsz:BAAALgAECgIJAgAAAA==.Snowws:BAABLgAECn8eAAIRAAkJ9xqeFABdAgARAAkJ9xqeFABdAgAAAA==.',
So='Sortis:BAABLgAECn8kAAIJAAkJFhjeMwCjAgAJAAkJFhjeMwCjAgAAAA==.',
Sp='Spongerunner:BAAALgAECgYJDgAAAA==.Sprucetea:BAAALgADCgIJAwAAAA==.',
St='Steck:BAABLgAECn8gAAIEAAgJMRLKOgCfAQAEAAgJMRLKOgCfAQAAAA==.Strigo:BAABLgAFFH8OAAQKAAQJdRhWCQBWAQAKAAQJCBhWCQBWAQAEAAEJtBy7IABfAAAIAAEJnwy7KABKAAAAAA==.',
Su='Subway:BAAALgAECggJEAAAAA==.Sunbaby:BAABLgAECn8mAAIoAAgJnR7yAwBAAgAoAAgJnR7yAwBAAgAAAA==.',
['Sà']='Sàlís:BAAALgADCgkJDAAAAA==.',
Ta='Tacktyks:BAAALgAECgYJEgAAAA==.Takamaka:BAABLgAECn8gAAIVAAkJdCBJBQD9AgAVAAkJdCBJBQD9AgAAAA==.Talandaru:BAAALgAECgEJAQAAAA==.Talas:BAABLgAECn8qAAMEAAkJbRz4DwCJAgAEAAkJbRz4DwCJAgAIAAUJswr3VwDnAAAAAA==.Taurasaurus:BAAALgAECgEJAQAAAA==.',
Te='Temerald:BAAALgADCgkJCQAAAA==.Tevoran:BAAALgADCgYJCgAAAA==.',
Th='Thaeker:BAAALgAECggJEgAAAA==.Thaelidari:BAAALgAECgkJDAAAAA==.Thieridan:BAAALgADCgIJBAAAAA==.Thrangus:BAAALgAECgIJAgABLgAECgkJHQAOAOsiAA==.Thrann:BAABLgAECn8dAAMOAAkJ6yKfOgBNAgAOAAcJqSKfOgBNAgATAAQJzyP0BwCTAQAAAA==.Thunderdex:BAACLgAFFH8LAAMRAAYJoxjJDwCiAQARAAYJoxjJDwCiAQAbAAEJ6AODGgA/AAAuAAQKfx8AAhEACQl9Hr0TAGQCABEACQl9Hr0TAGQCAAAA.',
Ti='Tirium:BAAALgAECgEJAQAAAA==.',
To='Togglesmith:BAAALgADCgcJDgAAAA==.Togglestein:BAAALgADCgYJDQAAAA==.Togglethorp:BAAALgADCgYJDAAAAA==.Togi:BAAALgADCgcJDQAAAA==.',
Tr='Trinitum:BAAALgAECgQJBwAAAA==.Tripdaddy:BAAALgADCgIJAgAAAA==.Trishal:BAAALgADCgMJAwAAAA==.',
Tu='Tul:BAAALgADCgMJAwAAAA==.',
Un='Unmoogled:BAAALgADCgIJAgAAAA==.',
Ur='Ursae:BAAALgAECgQJBwAAAA==.',
Va='Vaadboolin:BAAALgAECggJEgAAAA==.Vallius:BAABLgAECn8dAAIQAAkJ5BKGDwDlAQAQAAkJ5BKGDwDlAQAAAA==.Vanargandr:BAAALgAECggJDQAAAA==.',
Ve='Verðandi:BAAALgAECgIJAgAAAA==.',
Vo='Volcano:BAABLgAECn8bAAICAAkJIBrcFwBcAgACAAkJIBrcFwBcAgAAAA==.Volvox:BAAALgADCgEJAQAAAA==.Vonslarge:BAAALgADCgkJCQAAAA==.',
Vy='Vyxenn:BAABLgAECn8vAAMZAAkJ0xacFABSAgAZAAkJ0xacFABSAgAFAAMJVQrIXQBsAAAAAA==.',
Wa='Waffletoast:BAAALgADCgcJCQABLgAECgkJIwAeAGkhAA==.Wanders:BAABLgAECn8cAAMJAAgJLRLBUgCiAQAJAAgJ0hHBUgCiAQAmAAYJLAmdCwAcAQAAAA==.Wasiolka:BAAALgADCgIJAgAAAA==.',
Wu='Wurm:BAAALgAECgcJBwAAAA==.',
Xa='Xannies:BAABLgAECn8rAAMmAAYJfwWQDQDvAAAmAAYJRAWQDQDvAAAJAAUJbwLD5QB8AAAAAA==.',
Xe='Xeromercy:BAAALgADCgUJBQAAAA==.',
Ye='Yep:BAABLgAECn8bAAIGAAkJ7yMzBAAwAwAGAAkJ7yMzBAAwAwAAAA==.Yesenìa:BAAALgAECgMJAwAAAA==.',
Za='Zacattack:BAAALgADCgUJBQAAAA==.Zaleras:BAAALgAECgUJDAAAAA==.Zazael:BAAALgAECgIJAgAAAA==.Zazreal:BAABLgAECn8wAAQhAAkJgh2HAQCfAgAhAAkJgh2HAQCfAgAgAAMJ4Q9oSwClAAAfAAQJ7wJYIwCGAAAAAA==.',
Ze='Zedis:BAAALgADCgMJAwAAAA==.',
Zi='Zillaamiri:BAABLgAECn8xAAISAAkJGAaZDgBUAQASAAkJGAaZDgBUAQAAAA==.Zillyanna:BAAALgAECgcJEgAAAA==.',
Zo='Zolar:BAAALgADCgQJBAAAAA==.',
Zy='Zyper:BAAALgAECgQJBAAAAA==.Zywol:BAABLgAECn8lAAMUAAkJ5xi4DAA9AgAUAAkJ5xi4DAA9AgAPAAMJlgbIpgB6AAAAAA==.',
['Ër']='Ëresta:BAABLgAECn8cAAIJAAcJXQzgeQBHAQAJAAcJXQzgeQBHAQAAAA==.',
['Ðe']='Ðesire:BAAALgAECgYJCAAAAA==.Ðespair:BAABLgAECn8zAAQVAAkJJSAkCgCWAgAVAAcJPSEkCgCWAgAeAAkJWR4tCACJAgAMAAUJkxieMgD0AAAAAA==.',
['Ðr']='Ðream:BAAALgAECgYJCQAAAA==.',
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
