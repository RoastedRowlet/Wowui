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

local lookup = {'Warlock-Demonology','Paladin-Holy','Priest-Shadow','Priest-Holy','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Augmentation','Hunter-BeastMastery','Mage-Frost','Shaman-Restoration','Monk-Windwalker','Warrior-Protection','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Retribution','Druid-Guardian','Rogue-Subtlety','Unknown-Unknown','Hunter-Survival','DemonHunter-Devourer','DemonHunter-Vengeance','Shaman-Elemental','Priest-Discipline','Druid-Balance','Druid-Restoration','Warlock-Destruction','Warlock-Affliction','Mage-Arcane','Mage-Fire','Druid-Feral','Rogue-Outlaw','Paladin-Protection','DeathKnight-Blood','Warrior-Arms','Evoker-Preservation','Warrior-Fury','Shaman-Enhancement','Rogue-Assassination','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Havoc',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Adaine:BAAALgADCgUJCQAAAA==.Adillyssa:BAAALgADCgcJBwABLgAECgYJFwABADwVAA==.Adriana:BAABLgAECn8fAAICAAgJ6x48CQCxAgACAAgJ6x48CQCxAgAAAA==.Adrianix:BAAALgADCgQJBAAAAA==.Adru:BAABLgAECn8cAAMDAAYJYghsNgDnAAADAAYJYghsNgDnAAAEAAMJoAYfUQBKAAAAAA==.',
Ae='Aeglos:BAACLgAFFH8NAAMFAAQJLCFbAwBWAQAFAAQJiR1bAwBWAQAGAAMJbBjCVgACAQAuAAQKfx8AAwYACQksIcMWAPMCAAYACAkKIsMWAPMCAAUABQnoHlQJAEYBAAAA.Aelera:BAAALgADCgkJDgAAAA==.Aellira:BAAALgADCggJCAAAAA==.Aentharion:BAABLgAECn8nAAIHAAgJGhn2FADnAQAHAAgJGhn2FADnAQAAAA==.Aer:BAAALgADCgUJBQAAAA==.Aertimis:BAAALgADCgMJAwAAAA==.Aevielyn:BAAALgAECgEJAQAAAA==.',
Ag='Aguth:BAAALgADCgMJAwAAAA==.',
Ai='Aidewey:BAAALgADCgYJBgAAAA==.Aileen:BAABLgAECn8YAAIIAAkJjhO2XgBLAQAIAAkJjhO2XgBLAQAAAA==.Airiya:BAAALgAECgUJBAAAAA==.',
Aj='Ajami:BAAALgADCgIJAgAAAA==.',
Al='Alacite:BAAALgAECgcJEwAAAA==.Aleyah:BAAALgAECgcJBAAAAA==.Alitikar:BAAALgAECgIJAgAAAA==.Allamura:BAAALgAECgUJBQAAAA==.Alleximage:BAACLgAFFH8HAAIJAAQJBwazSQAeAQAJAAQJBwazSQAeAQAuAAQKfxkAAgkACAnbFzFTAD4CAAkACAnbFzFTAD4CAAAA.Alliandria:BAAALgADCgIJAgAAAA==.Alorren:BAABLgAECn8eAAIKAAgJExATMACYAQAKAAgJExATMACYAQAAAA==.Althea:BAAALgADCgQJBAAAAA==.Alynia:BAABLgAECn8eAAIGAAgJaSAeNQDkAQAGAAgJaSAeNQDkAQAAAA==.Alyssa:BAAALgAECgUJBQAAAA==.',
Am='Amodegas:BAABLgAECn8XAAICAAgJ6CBfCADoAgACAAgJ6CBfCADoAgAAAA==.Amonk:BAAALgAECgQJBwAAAA==.Amonra:BAAALgAECgMJAwAAAA==.Amordil:BAAALgADCgQJBAAAAA==.Amynrar:BAAALgAECgcJDAAAAA==.',
An='Ancalagrond:BAAALgAECgUJCgAAAA==.Andrâste:BAAALgAECgUJCAAAAA==.Anecia:BAAALgADCgkJDwABLgAECgYJFwALAEEQAA==.Angyaras:BAABLgAFFH8QAAIMAAcJvh5OAQApAgAMAAcJvh5OAQApAgAAAA==.Animos:BAAALgADCgYJBgAAAA==.Annehathaway:BAAALgAECgIJAwAAAA==.Anothercaion:BAAALgAECgUJDQAAAA==.Anthor:BAAALgADCgMJAwAAAA==.Antiihr:BAACLgAFFH8cAAINAAcJeiFWAAB7AgANAAcJeiFWAAB7AgAuAAQKfzoAAg0ACQn5JN4AAL4DAA0ACQn5JN4AAL4DAAAA.',
Ap='Apix:BAAALgAECgEJAQABLgAFFAMJBwAOAOoSAA==.',
Ar='Arcaisme:BAAALgAECgYJEwAAAA==.Arcticsnow:BAABLgAECn8XAAIMAAYJYxdmGwAMAQAMAAYJYxdmGwAMAQAAAA==.Arkose:BAAALgAECgcJEQAAAA==.Arkädia:BAAALgAECgIJAQAAAA==.Armistice:BAABLgAECn8XAAIPAAgJQSE+EwD5AgAPAAgJQSE+EwD5AgAAAA==.Artanos:BAAALgAECgYJEgAAAA==.Artiazana:BAAALgADCgUJBgAAAA==.',
As='Ashlyngrace:BAAALgAECgIJAgABLgAFFAMJBwAKAHcaAA==.Ashlynne:BAACLgAFFH8HAAIKAAMJdxpDJwDtAAAKAAMJdxpDJwDtAAAuAAQKfyAAAgoACQnVHtcJANsCAAoACQnVHtcJANsCAAAA.Ashlynnemia:BAAALgAECgYJBwAAAA==.Ashvara:BAAALgADCggJGQAAAA==.Aslynna:BAAALgADCggJDQAAAA==.Asora:BAABLgAECn8nAAIJAAYJdQp3nwACAQAJAAYJdQp3nwACAQAAAA==.Aspect:BAAALgAECggJCwAAAA==.Aspensong:BAABLgAECn8nAAIQAAgJmB2cBQBVAgAQAAgJmB2cBQBVAgAAAA==.Astracious:BAAALgAECgYJBgAAAA==.',
At='Atax:BAABLgAECn8nAAIRAAgJtxb0EQDFAQARAAgJtxb0EQDFAQAAAA==.Athená:BAAALgAECgYJDgABLgAECggJDQASAAAAAA==.Atheum:BAAALgADCgQJBAAAAA==.',
Au='Auralyn:BAAALgADCgcJDgAAAA==.Aurelitrasza:BAAALgADCgkJFwAAAA==.',
Av='Avicena:BAAALgAECgUJCAAAAA==.Avicii:BAAALgADCgUJCgAAAA==.Avrice:BAAALgAECgYJBwAAAA==.',
Ax='Axfrosty:BAAALgADCgQJBAAAAA==.Axiona:BAAALgAECgEJAQAAAA==.',
Ay='Ayakia:BAAALgAECgcJEgAAAA==.Ayaku:BAAALgAECgIJAgAAAA==.',
Az='Azuraa:BAAALgADCgUJCAAAAA==.',
Ba='Badshot:BAAALgAECgYJDwAAAA==.Baiogg:BAABLgAECn8YAAIBAAcJMQWqiQDpAAABAAcJMQWqiQDpAAAAAA==.Baldord:BAAALgADCgMJBAAAAA==.Balthromaww:BAAALgAECgYJBwAAAA==.Balung:BAAALgAECgQJBgAAAA==.Bambu:BAAALgAECgYJEgAAAA==.Bamevoker:BAAALgAECgMJAwABLgAECgYJEgASAAAAAA==.Bariggs:BAACLgAFFH8GAAITAAIJvyPwFgDHAAATAAIJvyPwFgDHAAAuAAQKfxoAAhMACAkVI+cEAMYCABMACAkVI+cEAMYCAAAA.Barilia:BAAALgAECgYJCgAAAA==.',
Be='Bearlyalive:BAAALgAECgIJAgAAAA==.Beladra:BAAALgADCgUJCwAAAA==.Belekor:BAAALgAECgYJCQAAAA==.Beltayn:BAAALgAECgYJCwAAAA==.Ben:BAABLgAECn8gAAILAAkJfhouFABNAgALAAkJfhouFABNAgAAAA==.Beriadan:BAAALgAECggJDQAAAA==.Bevee:BAAALgAECgQJCQAAAA==.Bewitchin:BAAALgAECgEJAQAAAA==.',
Bi='Bigponch:BAAALgADCgEJAQAAAA==.Birst:BAAALgADCggJBAAAAA==.Bisque:BAAALgAECgMJAwAAAA==.',
Bl='Bladesrus:BAAALgAECgMJBQAAAA==.Blaithe:BAAALgAECgEJAQAAAA==.Bleddwen:BAAALgAECgYJGAAAAQ==.Bliggix:BAAALgADCgQJBAAAAA==.Blrsama:BAAALgADCgUJBgAAAA==.',
Bo='Bodok:BAABLgAECn8nAAMUAAkJrBQcJAD3AQAUAAkJrBQcJAD3AQAVAAEJyAWLKAAlAAAAAA==.Bohrnir:BAABLgAECn8zAAMKAAkJYx7lEQBsAgAKAAkJYx7lEQBsAgAWAAMJ/QjPWgB3AAAAAA==.Boomonster:BAAALgADCgcJBwAAAA==.Borealsnow:BAAALgADCggJCAAAAA==.Boüh:BAABLgAECn8aAAIXAAYJgBvNFwC7AQAXAAYJgBvNFwC7AQAAAA==.',
Br='Brackiss:BAAALgAECgMJAwAAAA==.Brokiinn:BAACLgAFFH8FAAIIAAIJ9BFiFQCvAAAIAAIJ9BFiFQCvAAAuAAQKfxoAAggACAl1GfAbAF8CAAgACAl1GfAbAF8CAAAA.Brutalix:BAAALgADCgYJDQAAAA==.Brynda:BAAALgADCgQJBAAAAA==.',
Bu='Budikah:BAAALgAECgQJAgAAAA==.Burd:BAAALgADCgcJBwAAAA==.Burmeister:BAABLgAECn8jAAMYAAcJ1gs+LgANAQAYAAcJ1gs+LgANAQAZAAYJqAfMYgDHAAAAAA==.Burnadine:BAABLgAECn8XAAMaAAYJBwa8FwCtAAAaAAYJBwa8FwCtAAABAAQJsQH42wBRAAAAAA==.Burnswhnpee:BAACLgAFFH8GAAIBAAMJXxGMTwDfAAABAAMJXxGMTwDfAAAuAAQKfxkABBoACQkHFR4cAG0BABoABgnnEh4cAG0BAAEABwn5EO9zABYBABsAAglUCMYiAGcAAAAA.Burtelby:BAAALgADCgYJBgAAAA==.',
['Bù']='Bùrd:BAAALgADCgkJEgAAAA==.',
['Bû']='Bûrd:BAABLgAECn81AAQcAAkJqxGNAgDpAQAcAAkJ7w+NAgDpAQAJAAcJlArHjwAeAQAdAAYJ6Q+XBQAMAQAAAA==.',
Ca='Cadsuàne:BAAALgADCgUJCAAAAA==.Caliie:BAABLgAECn8nAAMKAAgJxQmCUwD9AAAKAAcJFgeCUwD9AAAWAAgJkQQjPwDeAAAAAA==.Callira:BAAALgAECgUJEAAAAA==.Cambiare:BAAALgADCgYJCgAAAA==.Canaandra:BAAALgADCgkJBwAAAA==.Captclamslam:BAABLgAECn8jAAMQAAgJ/A2XGAAOAQAQAAgJ+g2XGAAOAQAeAAcJ6QvaFQADAQAAAA==.Carolline:BAAALgADCgkJCwAAAA==.Catherinecay:BAAALgADCgcJBwAAAA==.',
Ce='Cereania:BAAALgAECgYJEgAAAA==.Cerrabell:BAAALgADCgcJBwAAAA==.',
Ch='Charzzard:BAAALgADCgEJAQAAAA==.Checksmix:BAAALgAECgEJAQAAAA==.Chintakari:BAABLgAECn8aAAMIAAgJqhO0OwCbAQAIAAgJqhO0OwCbAQATAAEJLwe4MAAxAAAAAA==.Chlorofill:BAAALgAECgcJCQAAAA==.Chronologic:BAAALgAECgYJEAAAAA==.',
Co='Cocidiae:BAAALgAECgEJBAAAAA==.Confusious:BAACLgAFFH8OAAIKAAQJshgxHgAVAQAKAAQJshgxHgAVAQAuAAQKfy0AAwoACQnkGB4cABMCAAoACQnkGB4cABMCABYAAQkqCdaAACcAAAAA.Coree:BAABLgAECn9CAAIfAAgJARHmBgCKAQAfAAgJARHmBgCKAQAAAA==.Cornflower:BAABLgAECn8cAAIEAAgJkQ9hJgBJAQAEAAgJkQ9hJgBJAQAAAA==.Corvaan:BAABLgAECn8lAAIUAAkJ5BG8LwC9AQAUAAkJ5BG8LwC9AQAAAA==.',
Cr='Creg:BAABLgAECn8nAAIUAAgJYR/CFABcAgAUAAgJYR/CFABcAgAAAA==.Crotalhusk:BAAALgADCgcJDQAAAA==.Crowbarr:BAAALgADCgUJBQAAAA==.Cryostatic:BAAALgAECgUJBgABLgAECgYJIgAgAJ8JAA==.',
Cu='Cultel:BAACLgAFFH8HAAIVAAMJ0RniAwDnAAAVAAMJ0RniAwDnAAAuAAQKfzsAAhUACQm2IrIAABoDABUACQm2IrIAABoDAAAA.',
Cy='Cyendia:BAABLgAECn8jAAIKAAgJiBnPFABQAgAKAAgJiBnPFABQAgAAAA==.Cyer:BAAALgAECgQJBgAAAA==.',
Da='Daddyraz:BAABLgAECn8XAAIUAAgJnRWeZAB0AQAUAAgJnRWeZAB0AQAAAA==.Dakan:BAAALgAECgMJAwAAAA==.Daphcelyn:BAAALgAECgQJCwAAAA==.Dariusz:BAAALgAECggJEwAAAA==.Darkalen:BAABLgAECn8xAAIhAAgJvBviCQAiAgAhAAgJvBviCQAiAgAAAA==.Darklodus:BAAALgADCgcJEwAAAA==.Darriuss:BAABLgAECn8kAAIPAAYJqgS0uQDBAAAPAAYJqgS0uQDBAAAAAA==.Darthvaderp:BAAALgAFFAEJAQAAAA==.Dathea:BAAALgADCgYJBgAAAA==.Davìd:BAAALgAECgEJAQAAAA==.Dawnmist:BAAALgAECgQJCAAAAA==.Daxetandh:BAAALgAECgIJBgAAAA==.Daxetanir:BAAALgADCgMJAwABLgAFFAIJBQAWABEaAA==.Daxetans:BAACLgAFFH8FAAIWAAIJERpmFACpAAAWAAIJERpmFACpAAAuAAQKfz4AAxYACQnfIdICABUDABYACQnfIdICABUDAAoABwk+DN5GAGYBAAAA.',
De='Deadmoose:BAABLgAECn84AAIGAAkJcxVgLwD7AQAGAAkJcxVgLwD7AQAAAA==.Deathb:BAAALgADCgkJIAAAAA==.Deathjingle:BAACLgAFFH8IAAIGAAIJ4RwWggClAAAGAAIJ4RwWggClAAAuAAQKfzIAAyEACQmbHVIKABgCAAYACQmYF4RHAB0CACEABwlAIVIKABgCAAAA.Deecayed:BAABLgAECn8cAAIPAAgJjxRXSgCeAQAPAAgJjxRXSgCeAQAAAA==.Deecoy:BAAALgAECgYJDgAAAA==.Deestroyer:BAAALgAECgUJDwAAAA==.Deetermined:BAACLgAFFH8KAAIKAAQJEhEkIAALAQAKAAQJEhEkIAALAQAuAAQKfygAAgoACQneHgEGAAkDAAoACQneHgEGAAkDAAAA.Delion:BAAALgADCgIJAgAAAA==.Demhuloo:BAAALgAECgQJBwAAAA==.Demonburp:BAACLgAFFH8HAAIUAAMJ5RxUNAAHAQAUAAMJ5RxUNAAHAQAuAAQKfzMAAhQACQmDIS0HAOkCABQACQmDIS0HAOkCAAAA.Denchy:BAABLgAECn8kAAIiAAcJgga7JgDWAAAiAAcJgga7JgDWAAAAAA==.Dendris:BAAALgAECgQJCAAAAA==.Denogginator:BAAALgADCgEJAQAAAA==.Desetraz:BAAALgAECgYJCwAAAQ==.Deval:BAAALgADCgQJBAAAAA==.Deyndine:BAABLgAECn8XAAIBAAYJPBV6ZgAzAQABAAYJPBV6ZgAzAQAAAA==.',
Dh='Dhurza:BAAALgAFFAIJAgAAAA==.',
Di='Disdain:BAAALgAECgYJDAAAAA==.Div:BAABLgAECn9AAAIgAAkJpx7oAQDbAgAgAAkJpx7oAQDbAgAAAA==.',
Do='Dogdays:BAAALgADCgkJCQAAAA==.Doki:BAAALgAECgIJAgAAAA==.Donk:BAAALgADCgEJAQAAAA==.Dorden:BAABLgAECn84AAMHAAkJIhHMGwCnAQAHAAkJIhHMGwCnAQAjAAcJJxDOGAD9AAAAAA==.Dorilax:BAABLgAECn8UAAMEAAgJrBFBIQDZAQAEAAgJrBFBIQDZAQAXAAEJvwFgXgAlAAABLgAFFAIJAgASAAAAAA==.Dottarus:BAAALgAECgQJBQAAAA==.',
Dr='Draevus:BAAALgAECgQJBQAAAA==.Dragooniar:BAAALgAECgYJEgAAAA==.Draizen:BAAALgAECgkJDQAAAA==.Dralara:BAAALgADCggJDgAAAA==.Dreàd:BAABLgAECn8ZAAIWAAYJjxRgNAAPAQAWAAYJjxRgNAAPAQAAAA==.Driadora:BAAALgAECgQJBQAAAA==.Drinna:BAAALgAECgMJBgAAAA==.Drizzette:BAAALgADCgEJAQAAAA==.Droataxh:BAAALgADCgMJAwABLgAECgkJQAAJAOEgAA==.Droataxm:BAABLgAECn9AAAIJAAkJ4SBLDgBUAwAJAAkJ4SBLDgBUAwAAAA==.Druntress:BAABLgAECn8VAAIOAAgJ0xK8LADJAQAOAAgJ0xK8LADJAQAAAA==.',
Du='Duarraag:BAAALgADCgIJAQAAAA==.',
['Dà']='Dàvid:BAAALgAFFAEJAgAAAA==.Dàvìd:BAAALgAECgQJBAAAAA==.',
['Dè']='Dèmonic:BAAALgADCgQJBgAAAA==.',
['Dë']='Dëërez:BAABLgAECn8fAAIZAAYJ9gzaUQABAQAZAAYJ9gzaUQABAQAAAA==.',
Eb='Eburi:BAACLgAFFH8FAAIGAAMJ5Qn0bQDYAAAGAAMJ5Qn0bQDYAAAuAAQKfxYAAgYACAlkFddJAJ0BAAYACAlkFddJAJ0BAAAA.',
Ed='Edgybear:BAAALgADCggJCAAAAA==.',
Ei='Eililis:BAAALgAECgMJCAAAAA==.',
El='Elani:BAAALgAECgMJAwABLgAECgYJDwASAAAAAA==.Elaynaa:BAABLgAECn8UAAIWAAYJwhXHKwA+AQAWAAYJwhXHKwA+AQAAAA==.Eledweth:BAAALgADCgEJAgAAAA==.Elemengoat:BAAALgADCgQJBAAAAA==.Elfstar:BAAALgAECgYJEwAAAA==.Elihe:BAAALgADCgEJAQAAAA==.Elishaunt:BAAALgAECgUJEQAAAA==.Elivan:BAAALgAECgYJBgAAAA==.Elleth:BAAALgAECgYJEAAAAA==.Elliana:BAAALgAECgEJAQAAAA==.Eloper:BAABLgAFFH8HAAIkAAMJOQZDJgC5AAAkAAMJOQZDJgC5AAABLgAECgEJAQASAAAAAA==.Elvoidra:BAAALgAECgIJAwAAAA==.Elykk:BAAALgAECggJDQAAAA==.',
Em='Emanymton:BAAALgAECgQJBAAAAA==.Emberana:BAAALgADCgUJBQAAAA==.',
En='Endb:BAAALgADCggJGwAAAA==.Enjin:BAAALgADCgUJBQAAAA==.Envi:BAAALgADCgUJBQAAAA==.',
Er='Erisaria:BAAALgADCgQJBQAAAA==.Erixi:BAABLgAECn8YAAIlAAYJOBctDwBLAQAlAAYJOBctDwBLAQAAAA==.Erodoreal:BAAALgAECgcJEAAAAA==.',
Et='Etheria:BAAALgAECgYJCAAAAA==.',
Ev='Evissier:BAACLgAFFH8JAAIbAAMJkR2QAgAaAQAbAAMJkR2QAgAaAQAuAAQKfx0AAhsACAmuIAcBAAIDABsACAmuIAcBAAIDAAAA.Evocore:BAAALgAECgYJEgAAAA==.',
Ex='Excelimagust:BAAALgAECgQJCQAAAA==.',
Fa='Faelieline:BAAALgADCgYJBgAAAA==.Faithful:BAAALgAECgcJBwABLgAECgkJJAAgABwbAA==.Falanor:BAAALgAECgQJBAABLgAECgYJCQASAAAAAA==.Falcdhruid:BAAALgAECgQJCgAAAA==.Fangrage:BAAALgAECgMJBAAAAA==.Farundi:BAAALgAECgQJBwAAAA==.Fayemoon:BAAALgAECgYJDQAAAA==.',
Fe='Felara:BAAALgAECgYJBwABLgAFFAIJBQAMAAwhAA==.Felbutton:BAAALgAECgUJCQAAAA==.Feldemon:BAAALgAECgQJBgAAAA==.Fellost:BAAALgAECgQJBQABLgAFFAIJBQAMAAwhAA==.Felsen:BAAALgADCgEJAQABLgAFFAIJBQAMAAwhAA==.Felwit:BAACLgAFFH8FAAIMAAIJDCErEwC8AAAMAAIJDCErEwC8AAAuAAQKfxwAAgwACQlIG5sLAOUBAAwACQlIG5sLAOUBAAAA.Fennec:BAABLgAECn8dAAImAAcJTA+iCQBdAQAmAAcJTA+iCQBdAQAAAA==.',
Fh='Fhyn:BAAALgAECgQJBwABLgAECgQJCQASAAAAAA==.',
Fi='Fitzooth:BAAALgAFFAEJAQAAAA==.Fizzlezapp:BAAALgAECgEJAQAAAA==.',
Fl='Flamos:BAAALgADCgYJBgAAAA==.Florabelle:BAAALgAECgMJAwABLgAECggJHAAEAJEPAA==.Florid:BAABLgAECn8VAAIJAAYJmwoloAABAQAJAAYJmwoloAABAQAAAA==.',
Fo='Foshomomo:BAABLgAECn8mAAInAAgJ+xUsFgD2AQAnAAgJ+xUsFgD2AQAAAA==.Fozzle:BAABLgAECn8nAAIJAAkJCA/QQQDUAQAJAAkJCA/QQQDUAQAAAA==.',
Fr='Fredoku:BAAALgAECgMJBAAAAA==.Fredragon:BAAALgAECgEJAQAAAA==.Frenndi:BAAALgAECgQJDQAAAA==.Frostbites:BAAALgAECgEJAQAAAA==.',
Fu='Furroz:BAAALgAECgEJAQABLgAECggJMQAhALwbAA==.',
Fy='Fynedge:BAABLgAECn8jAAIPAAgJagojagBPAQAPAAgJagojagBPAQAAAA==.Fynnyntyss:BAABLgAECn80AAIoAAkJsBIiBAD8AQAoAAkJsBIiBAD8AQAAAA==.Fyrè:BAABLgAECn80AAIIAAkJjSJACADcAgAIAAkJjSJACADcAgAAAA==.',
['Fâ']='Fârrah:BAAALgAECgQJBgAAAA==.',
Ga='Gabriels:BAAALgADCgcJFQAAAA==.Gabrielspet:BAAALgADCgIJAgAAAA==.Gainsborough:BAAALgAECgYJBgAAAA==.Galactis:BAAALgAECgYJBwAAAA==.Gavinrad:BAAALgAECgQJBAAAAA==.',
Ge='Gelirri:BAAALgADCgIJAgAAAA==.Getschwiftyy:BAAALgAECgEJAQAAAA==.',
Gi='Githnor:BAABLgAECn81AAIPAAkJLAorUwCGAQAPAAkJLAorUwCGAQAAAA==.',
Gl='Glendara:BAAALgADCggJDwAAAA==.',
Go='Gorellan:BAAALgAECgQJBAAAAA==.Goretall:BAAALgADCgYJCAAAAA==.Gothen:BAAALgADCgEJAQAAAA==.',
Gr='Graelyn:BAABLgAECn8XAAMPAAcJLAvsjABhAQAPAAcJVgrsjABhAQAgAAIJQQmRQQA3AAAAAA==.Grimseth:BAAALgADCgUJBQAAAA==.Grimwharf:BAAALgAECgUJCQAAAA==.Gromnor:BAAALgAECgEJAQAAAA==.Grum:BAAALgADCgUJBQAAAA==.Grunaelyn:BAABLgAECn8YAAIWAAgJMhDAJgBeAQAWAAgJMhDAJgBeAQAAAA==.',
Gu='Guerrier:BAABLgAECn8VAAIOAAYJNA70EgDqAAAOAAYJNA70EgDqAAAAAA==.Gustgut:BAAALgAECgMJBAAAAA==.',
Ha='Haelynn:BAAALgADCgcJDAAAAA==.Hahkolhanna:BAAALgADCggJEwAAAA==.Handrido:BAAALgAECgYJCgAAAA==.Hantaro:BAAALgADCgMJAwAAAA==.Hasuna:BAAALgAECgYJDQAAAA==.',
He='Heikuro:BAABLgAECn8lAAMVAAYJ5iFHBgDcAQAVAAYJ5iFHBgDcAQAUAAYJwhnaZgBtAQAAAA==.Heiler:BAAALgAECgQJBAAAAA==.Heris:BAAALgADCgcJDAAAAA==.',
Hi='Hibby:BAAALgAECgMJBAAAAA==.',
Ho='Holymilk:BAAALgAECgIJAgAAAA==.Holysalt:BAAALgADCgUJCwAAAA==.Hommytick:BAAALgADCgEJAQAAAA==.Honadain:BAAALgAECgYJEwAAAA==.Honordin:BAABLgAECn8uAAIPAAgJNSG3HABXAgAPAAgJNSG3HABXAgAAAA==.Hordestalker:BAAALgAECgQJBwAAAA==.Houllian:BAAALgAECgYJEAAAAA==.',
Hu='Hucha:BAAALgAECgIJAgAAAA==.Hundren:BAAALgAECgEJAQAAAA==.',
Hw='Hweilan:BAAALgAECgUJBQAAAA==.',
['Hö']='Hölyföx:BAAALgAECgQJBAAAAA==.',
Ia='Iamearl:BAAALgAECgUJCQAAAA==.Iamirishgirl:BAAALgADCgIJAgAAAA==.',
Ic='Icyhotness:BAAALgADCgYJBgAAAA==.Icê:BAAALgADCgcJEgAAAA==.',
Ik='Iklyn:BAAALgAECgMJAQAAAA==.',
Il='Illanna:BAAALgAECgMJAwAAAA==.',
Im='Imckickinit:BAAALgAECgQJBAAAAA==.Imorith:BAAALgAECgYJDwAAAA==.',
In='Inania:BAAALgAECggJEwAAAA==.Inception:BAAALgAECgIJAwAAAA==.Incidental:BAABLgAECn87AAMNAAkJJiSrAQCOAwANAAkJJiSrAQCOAwALAAMJFRP6OwDBAAAAAA==.Inconell:BAABLgAECn8jAAIkAAYJKQXcTwC0AAAkAAYJKQXcTwC0AAAAAA==.Invega:BAAALgADCgkJDQAAAA==.',
Ip='Iport:BAAALgAECgIJAgAAAA==.',
Ir='Iric:BAAALgAECgMJBAAAAA==.Irinal:BAAALgADCggJCAAAAA==.Ironi:BAACLgAFFH8HAAIYAAMJyQPdIwCoAAAYAAMJyQPdIwCoAAAuAAQKfzcAAxkACQniFtkTAGcCABkACQniFtkTAGcCABgABgmVCnU+ALwAAAAA.',
Is='Isai:BAAALgAECgEJAQAAAA==.Iskandar:BAABLgAECn8qAAMkAAkJeBdwEwAMAgAkAAkJeBdwEwAMAgAiAAEJYgxBUgAtAAAAAA==.',
Iy='Iyashaau:BAAALgAECgEJAgAAAQ==.',
Iz='Izaer:BAABLgAECn8eAAIEAAYJXBLMJwA+AQAEAAYJXBLMJwA+AQAAAA==.Iziel:BAAALgAECgYJEQAAAA==.',
Ja='Jababa:BAAALgADCgMJAwAAAA==.Jabzaklok:BAAALgAECgcJEQAAAA==.Jahirah:BAABLgAECn8eAAIJAAgJvBb3SAC9AQAJAAgJvBb3SAC9AQABLgAECggJHgABAKANAA==.Jaleika:BAAALgADCgkJEQAAAA==.Janaian:BAABLgAECn8fAAMYAAgJUhO8KQApAQAYAAgJUhO8KQApAQAZAAMJ7g36nACRAAAAAA==.Jarius:BAABLgAECn8gAAICAAgJUQxQKQB1AQACAAgJUQxQKQB1AQAAAA==.Jashah:BAAALgADCgkJEQABLgAECgkJNAAoALASAA==.Jazaray:BAAALgADCgkJGQAAAA==.',
Je='Jean:BAABLgAECn8sAAIIAAgJ5x3ZGABzAgAIAAgJ5x3ZGABzAgAAAA==.Jeez:BAAALgAFFAMJBAAAAA==.Jeri:BAACLgAFFH8UAAMOAAYJmhTpEgAPAQAOAAUJ6AjpEgAPAQAIAAMJhx2LFACxAAAuAAQKfyYAAwgACQlHI1YhABACAAgACAmWI1YhABACAA4ABglTHMsnAOwBAAAA.Jeriaze:BAAALgADCgkJEgAAAA==.',
Jo='Jokuo:BAAALgADCgEJAQAAAA==.Jonyy:BAAALgADCgcJCAAAAA==.Joona:BAAALgADCgUJBQAAAA==.Jorianna:BAAALgAECgYJEAAAAA==.Joru:BAACLgAFFH8ZAAIlAAcJ1hpHAAARAgAlAAcJ1hpHAAARAgAuAAQKfx4AAiUACAmrJZ0CAKgCACUACAmrJZ0CAKgCAAAA.',
Ju='Jul:BAAALgAECgEJAQABLgAECgcJCgASAAAAAA==.',
Jy='Jynxmaze:BAAALgADCgQJAwAAAA==.',
['Jê']='Jênny:BAAALgAECgMJAwAAAA==.',
['Jí']='Jím:BAAALgADCgQJBAABLgAECggJIQABACElAA==.',
Ka='Kaai:BAAALgAECgYJEwAAAA==.Kabaul:BAABLgAECn8vAAMkAAkJDiJJAgCZAwAkAAkJDiJJAgCZAwAiAAEJcROVPgA7AAAAAA==.Kabir:BAABLgAECn8eAAIJAAcJ3ww7ewBEAQAJAAcJ3ww7ewBEAQAAAA==.Kadria:BAABLgAECn8YAAMZAAYJiyDTGQAvAgAZAAYJiyDTGQAvAgAYAAYJkxV9KQAqAQAAAA==.Kady:BAAALgAECgMJAwABLgAECgYJGAAgANYgAA==.Kaelon:BAAALgAECgkJCQAAAA==.Kail:BAAALgAECgUJDwAAAA==.Kailanii:BAABLgAECn8dAAMZAAgJLBTEJwDMAQAZAAgJLBTEJwDMAQAYAAIJ5QZOdABRAAAAAA==.Kaiscer:BAAALgAECgMJBAAAAA==.Kaitsura:BAAALgADCgUJBQAAAA==.Kaiyne:BAABLgAECn8jAAMBAAkJFhX2QACaAQABAAkJFhX2QACaAQAaAAEJdQ8ScQA1AAAAAA==.Kajiere:BAAALgADCgIJAgAAAA==.Kalagon:BAAALgAECgEJAQAAAA==.Kalakeri:BAAALgAECgMJAwAAAA==.Kalaman:BAAALgAECgYJCgAAAA==.Kalian:BAABLgAECn8XAAIIAAcJ+xUCRgB3AQAIAAcJ+xUCRgB3AQAAAA==.Kalito:BAAALgAECgQJDQAAAA==.Kamb:BAABLgAECn8nAAIVAAgJ3haRBgDTAQAVAAgJ3haRBgDTAQAAAA==.Kamuros:BAAALgADCgYJBgAAAA==.Karalee:BAAALgAECgUJDwAAAA==.Karn:BAAALgADCgEJAQAAAA==.Katieey:BAACLgAFFH8iAAIKAAgJDyECAAD0AgAKAAgJDyECAAD0AgAuAAQKfxcAAwoACQnYJMQHAPgCAAoACAmTJMQHAPgCABYABAmiHYQ7AF8BAAAA.Kayde:BAAALgAECgYJDAAAAA==.Kayil:BAAALgAECgYJDAAAAA==.Kayl:BAACLgAFFH8HAAIHAAMJ5AjOLADKAAAHAAMJ5AjOLADKAAAuAAQKfy0AAwcACQmQGMMOAC8CAAcACQmQGMMOAC8CACgABAk/EdQoANkAAAAA.Kaylli:BAAALgAECgQJCgAAAA==.',
Ke='Kedalin:BAAALgAECgQJBgAAAA==.Keelnin:BAAALgAECgIJBAAAAA==.Keloko:BAAALgAECgQJBgAAAA==.Kennyloggy:BAACLgAFFH8fAAIYAAgJDSCgAACcAgAYAAgJDSCgAACcAgAuAAQKfzYAAhgACQl0Jv8AANIDABgACQl0Jv8AANIDAAAA.Kerlock:BAAALgAECgUJBQABLgAECggJGQApAIQhAA==.Kerlok:BAAALgAECgQJBAABLgAECggJGQApAIQhAA==.Kernunnos:BAAALgAECgIJAgAAAA==.Kevris:BAABLgAECn8eAAIBAAgJoA0cWgBRAQABAAgJoA0cWgBRAQAAAA==.Keydan:BAABLgAECn8VAAIQAAYJghJJHADpAAAQAAYJghJJHADpAAAAAA==.',
Kh='Khaitiff:BAAALgADCgYJBgAAAA==.Khyn:BAAALgAECgQJCQAAAA==.',
Ki='Killmaim:BAAALgAECgYJBgAAAA==.Killrok:BAAALgADCgUJBQAAAA==.Kinikey:BAAALgAECgYJEgAAAA==.',
Kl='Klassy:BAACLgAFFH8FAAITAAMJhg6TEwD1AAATAAMJhg6TEwD1AAAuAAQKfzoAAhMACQmVIokBABkDABMACQmVIokBABkDAAAA.',
Kn='Knardil:BAAALgADCgIJBAAAAA==.',
Ko='Kolosim:BAAALgADCgYJBgAAAA==.Koppi:BAAALgAECgQJCgAAAA==.Korru:BAABLgAECn8YAAMDAAYJOAz6MgD6AAADAAYJOAz6MgD6AAAEAAIJUgxocQBhAAAAAA==.Kotie:BAABLgAECn8mAAIYAAgJhhbHFQDMAQAYAAgJhhbHFQDMAQAAAA==.',
Kr='Kramz:BAACLgAFFH8HAAIBAAMJqBUWRgD3AAABAAMJqBUWRgD3AAAuAAQKfxkAAwEACQkRG+gkAA4CAAEABwkYGOgkAA4CABoABgklG70TAK0BAAAA.Kronar:BAAALgAECgQJCgAAAA==.',
Ku='Kumojo:BAAALgADCgYJBwAAAA==.Kunka:BAAALgAECgYJCQAAAA==.Kurgan:BAAALgAECgEJBQAAAA==.',
Ky='Kyojin:BAAALgAECgEJAgAAAA==.Kyoshino:BAAALgAECgMJAwAAAA==.Kyrgune:BAAALgAECgMJAwAAAA==.',
['Kî']='Kîkuko:BAAALgAECgYJCAAAAA==.',
['Kÿ']='Kÿliah:BAAALgAECgEJAgAAAA==.',
La='Lalo:BAAALgAECgQJCgAAAA==.Landilion:BAAALgADCgYJBgAAAA==.Laoftey:BAACLgAFFH8HAAIKAAMJzRreJwDqAAAKAAMJzRreJwDqAAAuAAQKfy8AAwoACQnpHMEPAIICAAoACQnpHMEPAIICABYAAQnZD1uJAC8AAAAA.Laofty:BAAALgADCgYJBgAAAA==.Lar:BAAALgADCgEJAgAAAA==.Laserbeam:BAAALgAECgYJEwABLgAFFAEJAQASAAAAAA==.Lasmori:BAAALgAECgYJDwAAAA==.Laxxbroo:BAAALgAECgQJBAAAAA==.Lazaris:BAAALgADCgYJBgAAAA==.',
Le='Leglock:BAABLgAECn8VAAIUAAYJQw/VbQD0AAAUAAYJQw/VbQD0AAAAAA==.Leprhicon:BAAALgAECgYJBgAAAA==.Lesbireal:BAABLgAECn8jAAMPAAgJyRSfSACjAQAPAAgJoBSfSACjAQAgAAUJWRIiIQD+AAAAAA==.',
Li='Liastella:BAAALgADCgIJAgAAAA==.Liendria:BAAALgADCgIJAgAAAA==.Lifensoftpaw:BAACLgAFFH8YAAMLAAcJTxeGAQC9AQALAAUJJBuGAQC9AQAnAAUJXAEBGQD7AAAuAAQKfy4ABAsACQnnIzkDAPsCAAsACQnnIzkDAPsCAA0ABQl3HJ44AGcBACcAAglxAUNzAB8AAAAA.Lightcaller:BAAALgADCgEJAQAAAA==.Lightflasher:BAAALgAECgcJEwAAAA==.Likkash:BAAALgAECgcJBwABLgAECggJMQAhALwbAA==.Linari:BAAALgADCgMJAwAAAA==.Linthabeela:BAAALgADCgcJDgAAAA==.Lishalthen:BAAALgADCggJCAAAAA==.Lisyanthus:BAAALgAECgcJBwAAAA==.Livicecia:BAABLgAECn8UAAIeAAkJpQmkGQDZAAAeAAkJpQmkGQDZAAAAAA==.',
Lo='Loaftey:BAAALgADCggJCAAAAA==.Longworth:BAAALgADCgIJAgAAAA==.Lookman:BAABLgAECn8UAAICAAYJkBi+PwB5AQACAAYJkBi+PwB5AQAAAA==.Lothema:BAAALgAECgYJCgAAAA==.Lowang:BAAALgAECgEJAgAAAA==.',
Lu='Lucaromu:BAAALgAECgEJAQAAAA==.Lucielinna:BAAALgAECggJDQAAAA==.Luckiiem:BAACLgAFFH8HAAIJAAMJbxu2SQAeAQAJAAMJbxu2SQAeAQAuAAQKfzEAAgkACQnmHywOANYCAAkACQnmHywOANYCAAAA.Luisfriendsn:BAAALgADCgEJAQABLgAECgcJHAAcAKMZAA==.Lunabreeze:BAAALgADCgkJEAAAAA==.Lunarkin:BAABLgAECn8VAAMYAAYJFQ00NQDoAAAYAAYJFQ00NQDoAAAZAAEJCxEoqgAzAAAAAA==.Luoma:BAABLgAECn8XAAILAAYJQRBhKwARAQALAAYJQRBhKwARAQAAAA==.Luthane:BAABLgAECn8gAAIPAAcJ+AixjgAJAQAPAAcJ+AixjgAJAQAAAA==.',
Ly='Lyfeliss:BAAALgAECgYJDAAAAA==.Lykinea:BAAALgAECgUJBQAAAA==.Lynn:BAAALgAECgUJBQAAAA==.Lynnesa:BAAALgAECgIJAgAAAA==.',
Ma='Maccolyn:BAABLgAECn8hAAIPAAkJihn/JAAoAgAPAAkJihn/JAAoAgAAAA==.Magicpie:BAABLgAECn81AAIEAAkJ/yHHAgA6AwAEAAkJ/yHHAgA6AwAAAA==.Magikar:BAAALgAECgEJAQAAAA==.Magiren:BAAALgAECgYJBwAAAA==.Mahlock:BAACLgAFFH8HAAIRAAMJEgyTGgDmAAARAAMJEgyTGgDmAAAuAAQKfzsAAhEACQmTHZgFAJYCABEACQmTHZgFAJYCAAAA.Mainah:BAAALgAECgIJAgAAAA==.Makanai:BAAALgAECgYJDgAAAA==.Makenai:BAAALgADCgkJGQABLgAECgYJDgASAAAAAA==.Makishi:BAABLgAECn8kAAIVAAcJ7SCXBAAfAgAVAAcJ7SCXBAAfAgAAAA==.Malferious:BAAALgADCgYJBgAAAA==.Malfura:BAAALgAECgYJEwAAAA==.Malário:BAAALgADCgMJAwAAAA==.Manamontana:BAABLgAECn8XAAIJAAcJaQ4InACdAQAJAAcJaQ4InACdAQAAAA==.Mandragoria:BAAALgADCggJCAABLgAECgYJFwABADwVAA==.Maplebunny:BAAALgADCgMJAwAAAA==.Mascdomtop:BAACLgAFFH8HAAIEAAMJUB+6DQAXAQAEAAMJUB+6DQAXAQAuAAQKfyYAAwQACQmWHXMIAMQCAAQACQmWHXMIAMQCAAMACAlHCtMpAC0BAAAA.Maube:BAAALgAECgYJCQAAAA==.Mazzarzul:BAAALgAECgYJEwABLgAECgkJGgABABwLAA==.',
Me='Meebles:BAABLgAECn81AAIQAAkJGhM9CwDEAQAQAAkJGhM9CwDEAQAAAA==.Meiana:BAACLgAFFH8FAAIHAAIJZAdIOgCCAAAHAAIJZAdIOgCCAAAuAAQKfyMAAgcACQmyFfcSAPsBAAcACQmyFfcSAPsBAAAA.Mekanismz:BAAALgADCgkJCQABLgAFFAMJBwAkAGoeAA==.Melanthia:BAAALgAECgEJAQAAAA==.Melasmus:BAAALgAECgEJAQAAAA==.Mendu:BAAALgADCgcJBwAAAA==.Mes:BAAALgAECgkJEwAAAA==.Metacarpal:BAAALgAECgkJCQAAAA==.',
Mi='Micklaa:BAABLgAECn8hAAIJAAcJjgrFgwA0AQAJAAcJjgrFgwA0AQAAAA==.Mightybelle:BAAALgAECgkJAgAAAA==.Mightychi:BAAALgAECgUJEgAAAA==.Milan:BAAALgADCgkJCQAAAA==.Milicka:BAAALgADCgkJBwAAAA==.Milkbunny:BAAALgAECgEJAQAAAA==.Millenium:BAAALgAECgQJCgAAAA==.Mingtai:BAABLgAECn8VAAIJAAYJgguSmwAJAQAJAAYJgguSmwAJAQAAAA==.Mirixa:BAAALgADCgYJBgAAAA==.Mizzakien:BAAALgAECgYJEQAAAA==.',
Mo='Monk:BAACLgAFFH8GAAINAAMJPBvZFwCwAAANAAMJPBvZFwCwAAAuAAQKfyEAAg0ABwlKJQAaADQCAA0ABwlKJQAaADQCAAEuAAUUBAkQAAwAsB4A.Monkyo:BAAALgAECgcJEgAAAA==.Monrea:BAAALgADCgcJFgABLgAECgYJEwASAAAAAA==.Moondolli:BAAALgADCgEJAQAAAA==.Moonriver:BAABLgAECn8rAAQKAAkJEApMWgAfAQAKAAkJEApMWgAfAQAlAAYJHwqUFgDZAAAWAAQJDQojTgCmAAAAAA==.Moonsinde:BAABLgAECn8ZAAIYAAYJ2xMaMAADAQAYAAYJ2xMaMAADAQAAAA==.Moranta:BAABLgAECn8bAAMDAAcJ6gJvQwCnAAADAAYJRwNvQwCnAAAEAAMJiwIjSgBlAAAAAA==.Moressandra:BAAALgAECgYJDAAAAA==.',
Mu='Muncher:BAAALgAECgMJAwAAAA==.Munchiss:BAAALgADCgEJAQAAAA==.Murathiel:BAAALgAECgQJCQABLgAFFAUJEQAnAKwgAA==.Murdermass:BAAALgADCgkJEwAAAA==.Mushy:BAAALgAECgEJAQAAAA==.',
My='Mycoxinyou:BAAALgADCgQJBAAAAA==.Myke:BAAALgAECgEJAQAAAA==.Mykellcat:BAABLgAECn8ZAAMZAAYJICaODwCUAgAZAAYJICaODwCUAgAYAAUJzxzHJQBCAQAAAA==.Myrogue:BAAALgAFFAIJAgAAAA==.Mysticarc:BAAALgAECggJEgAAAA==.Mystichorn:BAAALgAECgEJAQAAAA==.Mysticmurv:BAACLgAFFH8HAAIpAAMJBw0xDgDfAAApAAMJBw0xDgDfAAAuAAQKfxoAAikACAmAHLsQAFwCACkACAmAHLsQAFwCAAAA.Myvirdaeth:BAAALgADCgEJAQAAAA==.',
Na='Naeni:BAAALgAECgEJAgAAAA==.Nahli:BAAALgAECgkJEgAAAA==.Nakkarn:BAAALgADCgQJBAAAAA==.Nalgotica:BAAALgAFFAMJAwAAAA==.Nalynahwe:BAABLgAECn8WAAMZAAcJqhW3RwAoAQAZAAYJahO3RwAoAQAeAAIJcAgfLABlAAAAAA==.Narima:BAABLgAECn8XAAMGAAYJUQ3IowDZAAAGAAUJxQ/IowDZAAAhAAUJqwWCMQCFAAAAAA==.Naura:BAAALgADCgEJAQAAAA==.Navirose:BAAALgAECgQJCAAAAA==.',
Ne='Neltheron:BAAALgADCgIJAgAAAA==.',
Nh='Nhala:BAAALgAECgIJAgABLgAECgQJBQASAAAAAA==.',
Ni='Nickspally:BAAALgADCggJCAABLgAECggJHgAeAMccAA==.Nightestrike:BAAALgADCgQJBAAAAA==.Nikodem:BAAALgAECgYJEwAAAA==.Ninali:BAAALgAECgYJCgAAAA==.Ninerva:BAAALgAECgkJEgAAAA==.Nivajh:BAAALgAECgEJAQAAAA==.',
No='Nore:BAABLgAECn8kAAIXAAcJoRrTEQD/AQAXAAcJoRrTEQD/AQAAAA==.',
Nv='Nvfos:BAAALgADCgUJBQAAAA==.',
Ny='Nyali:BAAALgAECgEJAQABLgAECggJHQAZACwUAA==.',
['Nà']='Nàdya:BAABLgAECn8+AAQKAAkJ7iCECADtAgAKAAkJ7iCECADtAgAlAAQJOwgfGgCtAAAWAAIJNAOkcAA+AAAAAA==.',
['Nî']='Nîghtshade:BAAALgADCgkJCAAAAA==.Nîkodemus:BAAALgADCgYJBgAAAA==.',
Ob='Oblivions:BAACLgAFFH8HAAIkAAMJah7RGQAPAQAkAAMJah7RGQAPAQAuAAQKfy4AAyQACQmtJIMGALsCACQACQmtJIMGALsCACIABAlwH0YWAE0BAAAA.Oblivionsdk:BAAALgAECggJCgABLgAFFAMJBwAkAGoeAA==.',
Od='Odyfan:BAAALgADCgEJAQAAAA==.',
Of='Ofelia:BAAALgAECgYJDAAAAA==.',
Og='Ogion:BAAALgAECgEJAQAAAA==.',
Om='Omniray:BAABLgAECn8jAAIYAAcJURTGIQBeAQAYAAcJURTGIQBeAQAAAA==.Omnitruce:BAAALgAECgMJAwAAAA==.',
On='Onekark:BAAALgAECgQJCAABLgAFFAcJIQAKACkbAA==.Onirei:BAAALgADCgEJAwAAAA==.',
Op='Ophèlia:BAAALgADCgMJDwAAAA==.',
Or='Orckus:BAAALgAECgQJCgAAAA==.Oreosbunny:BAAALgAECgUJBwAAAA==.',
Os='Oshrick:BAAALgAECgEJAQAAAA==.Osvaldr:BAAALgAECgQJBQAAAA==.',
Ot='Otterr:BAAALgAECgQJBAAAAA==.',
Ow='Owil:BAAALgAECggJEgAAAA==.',
Pa='Palamedes:BAAALgADCggJDgAAAA==.Paledin:BAAALgADCgEJAQAAAA==.Pandaburn:BAABLgAECn8gAAIJAAgJERp8NAAFAgAJAAgJERp8NAAFAgAAAA==.Pandais:BAAALgAECgYJDwAAAA==.Paranne:BAABLgAECn81AAIJAAkJnBwaHgBtAgAJAAkJnBwaHgBtAgAAAA==.Paroxism:BAABLgAECn8jAAIYAAgJnSKJBwCXAgAYAAgJnSKJBwCXAgAAAA==.Parthurnax:BAAALgAECgUJDgAAAA==.Patapouf:BAABLgAECn8jAAMXAAcJHSJADQBDAgAXAAYJBCNADQBDAgADAAcJsB1nEgDwAQAAAA==.Patrisse:BAAALgADCgMJAwAAAA==.Pauhana:BAAALgADCgkJFwABLgAECgYJFwALAEEQAA==.',
Pe='Peanût:BAACLgAFFH8HAAIZAAMJDwnBLwC2AAAZAAMJDwnBLwC2AAAuAAQKfzUAAhkACQl7HBYJAOsCABkACQl7HBYJAOsCAAAA.Pesante:BAABLgAECn8zAAIXAAkJEhkBCwBrAgAXAAkJEhkBCwBrAgAAAA==.',
Ph='Phaket:BAAALgADCgYJBwAAAA==.Phatums:BAACLgAFFH8QAAIGAAQJ/B+yJABqAQAGAAQJ/B+yJABqAQAuAAQKfyUAAgYACAnkIoESAA0DAAYACAnkIoESAA0DAAAA.Philippy:BAAALgADCgYJBwAAAA==.',
Pi='Pika:BAABLgAECn8ZAAMYAAgJcQ8KJwA5AQAYAAgJCgsKJwA5AQAeAAQJhRLsHQD3AAAAAA==.Pinix:BAAALgAECgEJAgAAAA==.Pinulito:BAAALgADCgMJAwAAAA==.Pippá:BAAALgAECgQJCAAAAA==.',
Po='Polonius:BAAALgAECggJEAAAAA==.',
Pr='Praline:BAAALgADCgEJAQAAAA==.Pranaverde:BAAALgAECgYJDAAAAA==.Prisevide:BAAALgAECgYJEwAAAA==.Priss:BAAALgADCgkJIAAAAA==.',
Pu='Pumpy:BAAALgADCgcJCAAAAA==.',
Py='Pythe:BAABLgAECn81AAIPAAkJmiEMCQDtAgAPAAkJmiEMCQDtAgAAAA==.',
Qa='Qap:BAABLgAECn8hAAIcAAgJZhXBAgDYAQAcAAgJZhXBAgDYAQAAAA==.Qara:BAAALgADCgYJBgAAAA==.',
Qu='Qualnorr:BAAALgAECgUJEgAAAA==.Quelastraaza:BAAALgADCgUJBQAAAA==.Queldraayan:BAAALgAECgUJCQAAAA==.Quixediah:BAACLgAFFH8NAAIZAAQJjBY+GQAyAQAZAAQJjBY+GQAyAQAuAAQKfx0AAhkACAn0IZAJAPkCABkACAn0IZAJAPkCAAAA.Quixhea:BAABLgAECn8WAAICAAYJDCNcEABMAgACAAYJDCNcEABMAgABLgAFFAQJDQAZAIwWAA==.Quixxie:BAAALgADCggJDgABLgAFFAQJDQAZAIwWAA==.Quixxum:BAAALgADCgMJAwABLgAFFAQJDQAZAIwWAA==.',
Ra='Radalas:BAABLgAECn8YAAIgAAYJ1iCKDwBzAQAgAAYJ1iCKDwBzAQAAAA==.Radreliris:BAAALgAECgYJDwAAAA==.Raelis:BAAALgADCggJCAABLgADCgkJCgASAAAAAA==.Rahdalas:BAAALgADCgEJAQABLgAECgYJGAAgANYgAA==.Rally:BAAALgAECgYJEwAAAA==.Ramanujan:BAAALgAECgIJAgAAAA==.Ramcco:BAEBLgAECn8cAAIDAAYJRx5pHQCEAQADAAYJRx5pHQCEAQAAAA==.Ranelle:BAABLgAECn81AAIEAAkJOxTmDgAvAgAEAAkJOxTmDgAvAgAAAA==.Rasmira:BAABLgAECn8WAAIpAAYJixDrNQAwAQApAAYJixDrNQAwAQAAAA==.Ravenis:BAABLgAECn8qAAIRAAgJQSJEBgCGAgARAAgJQSJEBgCGAgAAAA==.Razekial:BAAALgAECgYJCQAAAA==.Razelikh:BAAALgAECgEJAQAAAA==.',
Re='Reedem:BAABLgAECn8bAAILAAcJswvFKQAbAQALAAcJswvFKQAbAQAAAA==.Regilock:BAACLgAFFH8gAAQBAAgJYBtzAgBBAgABAAcJWx5zAgBBAgAaAAQJ0BHdBAAHAQAbAAEJUwwsBgBTAAAuAAQKfykABAEACQmNJdQIADoDAAEACQlZJdQIADoDABoABAnsHg8iAEUBABsAAQkAAO4jAGIAAAAA.Regilocklr:BAAALgAFFAIJAgAAAA==.Reikí:BAABLgAECn8cAAIJAAgJeBERXACJAQAJAAgJeBERXACJAQAAAA==.Relarria:BAAALgAECgQJBwAAAA==.Renbe:BAAALgADCgYJCQAAAA==.Renwald:BAABLgAECn8UAAMPAAYJdxF3kwBWAQAPAAYJdxF3kwBWAQAgAAMJ0Ao4NAB3AAAAAA==.Revgard:BAAALgAECgYJEQAAAA==.',
Rh='Rhasalgul:BAAALgAECgMJBwAAAA==.',
Ri='Risingull:BAAALgAECgEJAQAAAA==.',
Ro='Rolhen:BAAALgAECgYJCgAAAA==.Ronso:BAAALgADCgQJBAAAAA==.Ronta:BAAALgADCgYJCgAAAA==.Rowain:BAAALgADCgkJGQAAAA==.',
Ru='Rustyheals:BAAALgADCgkJGAAAAA==.',
Ry='Ryanari:BAAALgAECgcJDAAAAA==.Rylacus:BAABLgAECn8YAAIRAAYJvAkeJgAGAQARAAYJvAkeJgAGAQAAAA==.',
['Rá']='Rápháel:BAAALgADCgUJBQAAAA==.',
['Rê']='Rêgret:BAAALgADCgYJCQAAAA==.',
Sa='Saanda:BAAALgAECgYJEwAAAA==.Sagazboy:BAABLgAECn8WAAIPAAYJIRLZfwAjAQAPAAYJIRLZfwAjAQABLgAECggJJgAPAP4UAA==.Sagazpally:BAABLgAECn8mAAIPAAgJ/hTZRwCmAQAPAAgJ/hTZRwCmAQAAAA==.Salandre:BAAALgADCgMJAwAAAA==.Salutations:BAABLgAECn8ZAAMHAAkJvSPzBQDIAgAHAAgJgiTzBQDIAgAjAAEJTgN7MAAuAAABLgAFFAIJAgASAAAAAA==.Salv:BAAALgADCgIJAgAAAA==.Sandp:BAAALgAFFAEJAQAAAA==.Sapphin:BAAALgAECgIJAgAAAA==.Sarlef:BAABLgAECn8hAAIMAAgJuxU3DwCmAQAMAAgJuxU3DwCmAQAAAA==.Sashafel:BAAALgADCggJCAAAAA==.',
Sc='Scarm:BAAALgAECgEJAQAAAA==.Scyithe:BAAALgADCgYJBgAAAA==.',
Se='Sellidra:BAABLgAECn8fAAIIAAYJ1Q/cbAALAQAIAAYJ1Q/cbAALAQAAAA==.Sendcatpics:BAABLgAECn8sAAMCAAkJRBDkJgDzAQACAAkJRBDkJgDzAQAPAAUJBBrtgwByAQABLgAFFAIJAgASAAAAAA==.Seo:BAAALgAFFAIJBAAAAA==.Serenitara:BAAALgADCgYJBgAAAA==.Serharimia:BAAALgADCggJDgAAAA==.Sethia:BAAALgADCgQJBAABLgADCgUJBQASAAAAAA==.Sevotarthe:BAAALgADCgUJBQAAAA==.Seyana:BAABLgAECn8WAAIIAAYJrBiDTwBZAQAIAAYJrBiDTwBZAQAAAA==.',
Sh='Shaaddow:BAAALgAECgYJBgAAAA==.Shadowkaos:BAAALgAECgUJCAAAAA==.Shaffer:BAAALgAECgcJEwAAAA==.Shellmage:BAAALgAECgYJCwAAAA==.Shellshocker:BAACLgAFFH8HAAIWAAMJPSANDAApAQAWAAMJPSANDAApAQAuAAQKfyEAAhYACQn1Jb4BAD4DABYACQn1Jb4BAD4DAAAA.Shermantånk:BAAALgAECgQJBQAAAA==.Sheydon:BAAALgADCgQJBAAAAA==.Shiftstain:BAAALgADCgIJAgAAAA==.Shikï:BAACLgAFFH8IAAIDAAMJIiGEEQAqAQADAAMJIiGEEQAqAQAuAAQKfyUAAgMACQn/InoHAJYCAAMACQn/InoHAJYCAAAA.Shivermoón:BAABLgAECn8pAAIZAAkJshKxHwACAgAZAAkJshKxHwACAgAAAA==.Shobek:BAAALgAECgYJBgAAAA==.Shortie:BAAALgADCgYJBgAAAA==.',
Si='Sigesar:BAABLgAECn8nAAIEAAgJtQeFKQAxAQAEAAgJtQeFKQAxAQAAAA==.Sigrún:BAAALgAECgYJBAAAAA==.Silvaria:BAAALgAECgMJBAAAAA==.Simina:BAAALgAECgEJAQAAAA==.Simpforsouls:BAAALgAECgYJDwAAAA==.Simura:BAAALgAFFAEJAgAAAA==.Sinamara:BAAALgADCgkJGgAAAA==.Sinsimella:BAAALgAECgUJCAAAAA==.Sinõn:BAAALgAECggJEwAAAA==.',
Sk='Skyliner:BAAALgAECgQJBQAAAA==.Skyskitty:BAAALgAECgYJCwAAAA==.Skywatcher:BAABLgAECn8jAAIIAAcJ0AlLYwAiAQAIAAcJ0AlLYwAiAQAAAA==.',
Sl='Slaughtering:BAAALgAECgYJDwAAAA==.',
Sm='Smesus:BAAALgAECgEJAQAAAA==.Smitemare:BAAALgAECgQJCgAAAA==.',
Sn='Snowtigerr:BAAALgADCgEJAQAAAA==.',
So='Sohka:BAAALgADCgEJAQAAAA==.Solare:BAAALgADCggJHQAAAA==.Solianti:BAAALgADCgYJBgAAAA==.Solodan:BAAALgAECgYJDQABLgAECggJIgAYAKAaAA==.Solodane:BAAALgAECgcJEQABLgAECggJIgAYAKAaAA==.Sonnwar:BAABLgAECn8hAAICAAgJixuhLADTAQACAAgJixuhLADTAQAAAA==.',
Sp='Spinsocket:BAAALgADCgkJCQAAAA==.Spliphtoker:BAAALgAECgQJCwAAAA==.Spookytotems:BAABLgAECn8kAAIlAAgJghSwCgCjAQAlAAgJghSwCgCjAQAAAA==.',
St='Stenston:BAAALgAECgcJDwAAAA==.Sterede:BAAALgAECgQJCgAAAA==.Stonehenge:BAABLgAECn8fAAMPAAYJKA4AlwD6AAAPAAYJKA4AlwD6AAAgAAQJpQKvMABXAAAAAA==.Stormb:BAAALgADCgkJGwAAAA==.Stormwolves:BAAALgAECgUJBwAAAA==.',
Sy='Sylphr:BAAALgAECgQJCwAAAA==.Sylphwild:BAAALgAECgIJAgABLgAFFAMJAwASAAAAAA==.Sylvanase:BAAALgAECgcJCgAAAA==.Sylvara:BAAALgADCggJDgAAAA==.Synapze:BAABLgAECn8kAAIJAAcJRxEYaQBqAQAJAAcJRxEYaQBqAQAAAA==.Syreite:BAABLgAECn8rAAIQAAgJQhuFBwAaAgAQAAgJQhuFBwAaAgAAAA==.Syreyna:BAAALgADCgIJAwAAAA==.',
Ta='Taessa:BAAALgAECgUJCQAAAA==.Tahwye:BAAALgADCgkJKQAAAA==.Tainipuni:BAABLgAECn8WAAMEAAYJrgxhMwDvAAAEAAUJrg5hMwDvAAADAAUJmgZ/QwCmAAAAAA==.Takemi:BAAALgAECggJEQAAAA==.Tal:BAAALgAECggJCAABLgAFFAMJBwAgAKYPAA==.Tallac:BAAALgADCgYJBgABLgAFFAMJBwAgAKYPAA==.Tallaric:BAAALgAECgQJBAABLgAFFAMJBwAgAKYPAA==.Tallic:BAACLgAFFH8HAAIgAAMJpg9pBwCzAAAgAAMJpg9pBwCzAAAuAAQKfy8AAiAACQnxGIsHAA0CACAACQnxGIsHAA0CAAAA.Tamarah:BAAALgAECgYJDwAAAA==.Tamzyyn:BAABLgAECn8WAAIBAAYJEAWAnQDCAAABAAYJEAWAnQDCAAAAAA==.Tandemonium:BAAALgAECgEJAQABLgAFFAUJDQApANwgAA==.Taniz:BAABLgAECn8XAAMIAAgJ+hoLGQByAgAIAAgJ6hoLGQByAgAOAAMJ9Q2xdgBkAAAAAA==.Tankfu:BAAALgAECgYJDQAAAA==.Tarsi:BAAALgAECgYJDgAAAA==.Tashoonne:BAAALgADCgYJCAAAAA==.Taylin:BAAALgAECgIJAgABLgAECgQJCQASAAAAAA==.',
Te='Teareagana:BAAALgAECgYJCgABLgAECgkJHAAhAIIeAA==.Tearinurside:BAAALgAECgYJEwAAAA==.Teddy:BAAALgADCgUJBQABLgAFFAMJBwAnACAcAA==.Telchar:BAAALgAECgYJEwAAAA==.Telidrel:BAAALgADCgMJAwAAAA==.Telrienn:BAAALgADCgIJAgAAAA==.Teratin:BAABLgAECn8eAAINAAgJ/h+rCwBAAgANAAgJ/h+rCwBAAgAAAA==.Tevellan:BAAALgADCgYJBwAAAA==.',
Th='Thaddeaus:BAABLgAECn8ZAAIMAAgJDBkdDQA6AgAMAAgJDBkdDQA6AgAAAA==.Thaddeus:BAABLgAECn8nAAIPAAgJ/xhHLAAHAgAPAAgJ/xhHLAAHAgAAAA==.Thauris:BAAALgAECgEJBAAAAA==.Thealin:BAAALgAECgUJCAAAAA==.Thebeefyone:BAABLgAECn8UAAIJAAYJphFWhgAvAQAJAAYJphFWhgAvAQAAAA==.Thelesar:BAAALgADCgYJCAAAAA==.Therizin:BAAALgAECgYJEgAAAA==.Thesummoner:BAABLgAECn8XAAMBAAgJJiDQEwDeAgABAAgJJiDQEwDeAgAaAAEJxxVgawA8AAABLgAFFAEJAQASAAAAAA==.Thicciana:BAABLgAFFH8KAAINAAQJYx3qDQBdAQANAAQJYx3qDQBdAQAAAA==.Thorizan:BAAALgAECgQJBwAAAA==.Thugnificent:BAAALgADCgcJCgAAAA==.Thumpette:BAAALgADCgMJAwAAAA==.Thuviel:BAAALgAECgIJBAAAAA==.Thè:BAAALgAECgYJCwAAAA==.',
Ti='Tierant:BAAALgAECgUJBgAAAA==.Tituz:BAAALgADCgMJBAAAAA==.Tizaria:BAABLgAECn8dAAIEAAcJERaCGQC1AQAEAAcJERaCGQC1AQAAAA==.',
Tm='Tmai:BAAALgAECgYJEwAAAA==.',
To='Tolken:BAAALgAECgEJAQAAAA==.Tominaetor:BAABLgAECn8kAAIBAAYJOQwmewAGAQABAAYJOQwmewAGAQAAAA==.Tosoto:BAABLgAECn8tAAMiAAkJVh1qBQBmAgAiAAkJaRtqBQBmAgAkAAgJIhsoFQD7AQAAAA==.Toxerus:BAAALgAECgMJBAAAAA==.',
Tr='Trixigossa:BAAALgADCggJEgABLgAECgYJDQASAAAAAA==.Trobbio:BAAALgADCgIJAgAAAA==.',
Ts='Tso:BAABLgAECn8ZAAMnAAcJfRfpIwB7AQAnAAYJPBnpIwB7AQALAAEJKQZLgQAlAAAAAA==.Tsukuyomï:BAAALgAECgMJBwABLgAFFAMJCAADACIhAA==.',
Tu='Tuskmunkey:BAAALgAECgQJCgAAAA==.',
Ty='Tyernan:BAABLgAECn8xAAMCAAgJOQqdKgBrAQACAAgJOQqdKgBrAQAPAAIJyAQxJwFRAAAAAA==.Tyka:BAAALgADCgYJBgABLgAECgYJFwALAEEQAA==.Tym:BAAALgADCgkJDAAAAA==.Tyrael:BAABLgAECn82AAIPAAgJgQybYgBgAQAPAAgJgQybYgBgAQAAAA==.Tyreanna:BAAALgAECgMJAwAAAA==.Tyrioz:BAABLgAECn8eAAMCAAgJyRDxOAAWAQACAAcJXQ/xOAAWAQAPAAQJGw929ABnAAAAAA==.',
Tz='Tzavcat:BAABLgAECn8dAAIZAAYJGwirZADCAAAZAAYJGwirZADCAAAAAA==.',
Ul='Uluhn:BAAALgADCggJDgABLgAECgQJBQASAAAAAA==.',
Ur='Urklesnurkle:BAAALgAECgUJCgAAAA==.',
Ut='Utadia:BAAALgADCgIJAgABLgAECgcJCgASAAAAAA==.',
Uv='Uvsol:BAAALgAECgYJDgAAAA==.',
Va='Vahrik:BAAALgAECgEJAQAAAA==.Valcane:BAAALgADCgkJEgAAAA==.Valdictorian:BAAALgAECgEJAQAAAA==.Valius:BAABLgAECn8jAAIoAAgJVyFfAQCrAgAoAAgJVyFfAQCrAgAAAA==.Vallarium:BAAALgADCgYJHQAAAA==.Valornor:BAAALgAECgUJBwAAAA==.Valyerian:BAAALgAECgUJBgAAAA==.Vanacarde:BAAALgAECgUJBQAAAA==.Vandilious:BAAALgAECgYJEQABLgAECgcJGQAJANsQAA==.Vandill:BAABLgAECn8ZAAIJAAcJ2xArbgBfAQAJAAcJ2xArbgBfAQAAAA==.Vaneadra:BAAALgADCgUJCwAAAA==.Vaxis:BAAALgADCgcJCwAAAA==.',
Ve='Veasnacool:BAAALgAFFAIJAgAAAA==.Velanlan:BAAALgADCgUJCQAAAA==.Velion:BAAALgADCgYJBgAAAA==.Vestrit:BAAALgAECgIJAgAAAA==.',
Vh='Vhesper:BAAALgAECgQJBwAAAA==.',
Vi='Vii:BAABLgAECn8UAAIpAAgJ4gjwHQAiAQApAAgJ4gjwHQAiAQAAAA==.Vivacia:BAAALgAECgQJBAAAAA==.',
Vo='Voidfisting:BAABLgAECn8tAAMnAAgJ+wclNAAiAQAnAAgJ+wclNAAiAQALAAcJhQumKgAVAQAAAA==.Volfurion:BAAALgADCgQJBAAAAA==.Volthuun:BAAALgADCgIJBAAAAA==.Vontote:BAABLgAECn8bAAIhAAgJHCBSBgB5AgAhAAgJHCBSBgB5AgAAAA==.Vorix:BAAALgAECgYJEgAAAA==.Vorrel:BAAALgADCgkJFwABLgAFFAMJBwAHAOQIAA==.',
Vu='Vulzin:BAAALgAECgMJAwAAAA==.Vunak:BAAALgADCgcJDQAAAA==.',
['Ví']='Víc:BAABLgAECn8gAAICAAcJsiT5BgDcAgACAAcJsiT5BgDcAgAAAA==.',
Wa='Wandorf:BAEBLgAECn8nAAIGAAgJ8g43VQB9AQAGAAgJ8g43VQB9AQAAAA==.Warbacon:BAAALgADCgMJAwAAAA==.Wargyle:BAABLgAECn8gAAMBAAgJkBNFPwCgAQABAAgJkBNFPwCgAQAaAAEJAADMcAA1AAAAAA==.Warsmith:BAAALgAECgYJBgAAAA==.Warwolfe:BAABLgAECn81AAMBAAkJZgkuUABsAQABAAkJGQkuUABsAQAbAAUJ+QfyFgDIAAAAAA==.Wayler:BAAALgAECgIJAgAAAA==.',
We='Wealthywolf:BAABLgAECn8WAAMTAAcJwgdyKgD4AAATAAcJwgdyKgD4AAAOAAEJwgBxmwATAAAAAA==.Werepinguin:BAAALgADCgMJAwAAAA==.',
Wh='Whitewicca:BAAALgADCgQJBAAAAA==.',
Wi='Wilbrew:BAAALgAECgEJAgABLgAECggJEgASAAAAAA==.Wistful:BAAALgAECggJDwAAAA==.',
Wl='Wlitia:BAAALgAECgYJCgAAAA==.',
Wo='Wolferunner:BAABLgAECn8cAAIIAAYJTgs2cgD+AAAIAAYJTgs2cgD+AAAAAA==.',
Wr='Wrathome:BAABLgAECn8cAAMBAAcJgxqyQAALAgABAAcJgxqyQAALAgAaAAMJtgrURgCbAAAAAA==.Wráth:BAAALgADCggJCAAAAA==.',
Xa='Xalatäth:BAAALgAECgMJBAAAAA==.Xaldora:BAAALgAECgEJAgAAAA==.Xandrake:BAAALgAECgYJDAABLgAECggJNAACAPEiAA==.',
Xd='Xdxvuu:BAAALgAECgYJDgAAAA==.',
Xe='Xerimok:BAAALgAECgYJEwAAAA==.',
Xi='Xinya:BAABLgAECn8UAAIGAAcJ5xQcVACAAQAGAAcJ5xQcVACAAQAAAA==.Xipa:BAACLgAFFH8HAAIOAAMJ6hI7EADkAAAOAAMJ6hI7EADkAAAuAAQKfzAAAw4ACQkgHpEDAFICAA4ACAnCH5EDAFICAAgAAQmzEoLDAE4AAAAA.',
Xl='Xladykahlron:BAAALgADCgYJCAAAAA==.',
Xo='Xolara:BAAALgAECgIJBAAAAA==.',
Xs='Xsavior:BAAALgAECgYJDgAAAA==.Xshan:BAAALgAECgEJBAAAAA==.Xshando:BAAALgAECgQJCwAAAA==.',
Xy='Xyi:BAAALgAECggJEwAAAA==.',
Xz='Xzephyr:BAABLgAECn8tAAIYAAkJIiJqAwD9AgAYAAkJIiJqAwD9AgAAAA==.',
Ya='Yamato:BAABLgAECn8mAAIMAAkJ0QbKGAAmAQAMAAkJ0QbKGAAmAQAAAA==.',
Ye='Yesmín:BAAALgAECgcJDwAAAA==.',
Yo='Youwas:BAAALgAECgcJCgAAAA==.Yoveladari:BAAALgADCgIJAgAAAA==.',
Yu='Yukimenoko:BAABLgAECn8UAAIUAAgJvRtqJQDwAQAUAAgJvRtqJQDwAQAAAA==.Yukmouf:BAABLgAECn8ZAAIPAAgJNhxoIwCbAgAPAAgJNhxoIwCbAgAAAA==.',
Za='Zabrak:BAAALgAECgQJCgAAAA==.Zacharaius:BAAALgAECgYJBgAAAA==.Zakaris:BAAALgAECgUJDAAAAA==.Zalaeran:BAAALgADCgEJAQAAAA==.Zalatath:BAAALgADCgkJHgAAAA==.Zanbu:BAAALgAECgQJAgAAAA==.Zarrov:BAAALgADCgkJGgAAAA==.Zarrove:BAACLgAFFH8FAAILAAMJ3RtmDgAQAQALAAMJ3RtmDgAQAQAuAAQKfzcAAgsACQlyI1QCACADAAsACQlyI1QCACADAAAA.',
Ze='Zea:BAAALgAECgQJBwAAAA==.Zedael:BAABLgAECn8eAAIhAAgJaxeeEwCAAQAhAAgJaxeeEwCAAQAAAA==.Zeltri:BAAALgAECgMJBwAAAA==.Zephyran:BAAALgAECgIJAgAAAA==.Zeritha:BAAALgAECgQJBgAAAA==.',
Zh='Zhatva:BAABLgAECn8ZAAIIAAgJLSHKGABFAgAIAAgJLSHKGABFAgAAAA==.Zhöe:BAABLgAECn8UAAMKAAkJXh47DQCyAgAKAAgJtR07DQCyAgAWAAcJBhoZNgB8AQAAAA==.',
Zo='Zoldor:BAABLgAECn8hAAMBAAcJRxQNUQBpAQABAAYJRBQNUQBpAQAaAAIJVA+AMQAsAAAAAA==.Zoleia:BAAALgADCgIJAwAAAA==.Zoral:BAAALgADCgUJBQAAAA==.Zore:BAAALgADCgYJBgAAAA==.',
Zu='Zuldokah:BAAALgADCgEJAQAAAA==.',
Zy='Zy:BAABLgAFFH8FAAIIAAMJ5BeVMAD7AAAIAAMJ5BeVMAD7AAAAAA==.Zycorr:BAAALgAECgYJDgAAAA==.Zyheal:BAAALgAECggJEgAAAA==.Zymor:BAAALgAECgQJCgAAAA==.Zytrex:BAABLgAECn8XAAIaAAYJjwfIFQC9AAAaAAYJjwfIFQC9AAAAAA==.',
['Äm']='Ämaterasu:BAAALgADCgcJCgABLgAFFAMJCAADACIhAA==.',
['Ða']='Ðaniel:BAAALgAECgYJDQAAAA==.',
['Ðr']='Ðraevus:BAAALgAECgQJDAAAAA==.',
['Ñÿ']='Ñÿx:BAABLgAECn8cAAIBAAgJlQGEvQCCAAABAAgJlQGEvQCCAAAAAA==.',
['ßl']='ßlueshield:BAAALgAECgYJEgAAAA==.',
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
