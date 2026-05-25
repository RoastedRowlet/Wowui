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

local lookup = {'Warlock-Demonology','Paladin-Holy','Priest-Shadow','Priest-Holy','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Augmentation','Hunter-BeastMastery','Mage-Frost','Shaman-Restoration','DemonHunter-Devourer','Monk-Windwalker','Warrior-Protection','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Retribution','Mage-Arcane','Druid-Guardian','Rogue-Subtlety','Monk-Mistweaver','Unknown-Unknown','Hunter-Survival','Shaman-Elemental','DemonHunter-Vengeance','Priest-Discipline','Druid-Balance','Druid-Restoration','Warlock-Destruction','Warlock-Affliction','Mage-Fire','Druid-Feral','Rogue-Outlaw','Paladin-Protection','DeathKnight-Blood','Warrior-Arms','Evoker-Preservation','Warrior-Fury','Shaman-Enhancement','Rogue-Assassination','Evoker-Devastation','DemonHunter-Havoc',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adaine:BAAALgADCgUJCQAAAA==.Adillyssa:BAAALgADCgcJBwABLgAECgcJHAABALYSAA==.Adriana:BAABLgAECn8fAAICAAgJ6x5RDACmAgACAAgJ6x5RDACmAgAAAA==.Adrianix:BAAALgADCgQJBwAAAA==.Adru:BAABLgAECn8hAAMDAAgJlAf8LwA1AQADAAgJlAf8LwA1AQAEAAMJoAYvWgBHAAAAAA==.',
Ae='Aeglos:BAACLgAFFH8RAAMFAAQJLCE8BQBYAQAFAAQJPh88BQBYAQAGAAMJbBjabADwAAAuAAQKfx8AAwYACQksIcMWAPMCAAYACAkKIsMWAPMCAAUABQnoHlQJAEYBAAAA.Aelera:BAAALgADCgkJDgAAAA==.Aellira:BAAALgADCgkJEQAAAA==.Aentharion:BAABLgAECn8rAAIHAAkJkxpiDwBRAgAHAAkJkxpiDwBRAgAAAA==.Aer:BAAALgADCgUJBQAAAA==.Aertimis:BAAALgADCgMJAwAAAA==.Aethiriel:BAAALgADCgMJAwAAAA==.Aevielyn:BAAALgAECgEJAQAAAA==.',
Ag='Aguth:BAAALgAECgIJAgAAAA==.',
Ai='Aidewey:BAAALgADCgYJBgAAAA==.Aileen:BAABLgAECn8ZAAIIAAkJiRO2XgBLAQAIAAkJiRO2XgBLAQAAAA==.Airiya:BAAALgAECgUJBAAAAA==.',
Aj='Ajami:BAAALgADCgIJAgAAAA==.',
Al='Alacite:BAAALgAECgcJEwAAAA==.Aleyah:BAAALgAECgcJBAAAAA==.Alisonia:BAAALgAECgYJAwAAAA==.Alitikar:BAAALgAECgIJAgAAAA==.Allamura:BAAALgAECgUJBQAAAA==.Alleximage:BAACLgAFFH8IAAIJAAQJzQY5VgAYAQAJAAQJzQY5VgAYAQAuAAQKfyIAAgkACQnPGQ0wADoCAAkACQnPGQ0wADoCAAAA.Alliandria:BAAALgADCgIJAgAAAA==.Alorren:BAABLgAECn8gAAIKAAgJEhBZOgCTAQAKAAgJEhBZOgCTAQAAAA==.Althea:BAAALgADCgQJBAAAAA==.Alynia:BAACLgAFFH8GAAIGAAMJygygewDbAAAGAAMJygygewDbAAAuAAQKfx4AAgYACAm/H6QdAHQCAAYACAm/H6QdAHQCAAAA.Alyssa:BAAALgAECgUJBQAAAA==.',
Am='Amodegas:BAACLgAFFH8FAAICAAIJWCPRJADMAAACAAIJWCPRJADMAAAuAAQKfxcAAgIACAnoIF8IAOgCAAIACAnoIF8IAOgCAAAA.Amonk:BAAALgAECgQJBwAAAA==.Amonra:BAAALgAECgMJAwAAAA==.Amordil:BAAALgADCgQJBAAAAA==.Amynrar:BAABLgAECn8UAAILAAcJyAcSggDzAAALAAcJyAcSggDzAAAAAA==.',
An='Ancalagrond:BAAALgAECgUJCgAAAA==.Andrâste:BAAALgAECgUJCAAAAA==.Anecia:BAAALgAECgEJAQABLgAECggJGwAMAN0NAA==.Angyaras:BAABLgAFFH8VAAINAAcJJR/SAQA0AgANAAcJJR/SAQA0AgAAAA==.Animos:BAAALgADCgYJBgAAAA==.Annehathaway:BAAALgAECgIJAwAAAA==.Anothercaion:BAAALgAECgUJDQAAAA==.Anthor:BAAALgADCgMJAwAAAA==.Antiihr:BAACLgAFFH8cAAIOAAcJmiFWAAB7AgAOAAcJmiFWAAB7AgAuAAQKfzoAAg4ACQn5JN4AAL4DAA4ACQn5JN4AAL4DAAAA.',
Ap='Apix:BAAALgAECgEJAQABLgAFFAMJCgAPAOoSAA==.',
Ar='Arcaisme:BAAALgAECgYJEwAAAA==.Arcticsnow:BAABLgAECn8cAAINAAcJbheLGQBHAQANAAcJbheLGQBHAQAAAA==.Arkose:BAABLgAECn8XAAIEAAcJqxsOFQAGAgAEAAcJqxsOFQAGAgAAAA==.Arkädia:BAAALgAECgQJBAAAAA==.Armistice:BAABLgAECn8XAAIQAAgJQSE+EwD5AgAQAAgJQSE+EwD5AgAAAA==.Artanos:BAABLgAECn8YAAIRAAYJygYeCQDQAAARAAYJygYeCQDQAAAAAA==.Artiazana:BAAALgADCgUJBgAAAA==.',
As='Aschen:BAAALgADCgYJBgAAAA==.Ashlyngrace:BAAALgAECgIJAgABLgAFFAQJCwAKAH8VAA==.Ashlynne:BAACLgAFFH8LAAIKAAQJfxXaIgAhAQAKAAQJfxXaIgAhAQAuAAQKfyAAAgoACQnVHtcJANsCAAoACQnVHtcJANsCAAAA.Ashlynnemia:BAAALgAECgYJCAAAAA==.Ashvara:BAAALgADCggJGQAAAA==.Aslynna:BAAALgAECgYJBgAAAA==.Asora:BAABLgAECn8rAAIJAAcJZgpelQAzAQAJAAcJZgpelQAzAQAAAA==.Aspect:BAAALgAECggJCwAAAA==.Aspensong:BAABLgAECn8rAAISAAkJzR/tAgDeAgASAAkJzR/tAgDeAgAAAA==.Astracious:BAAALgAECgYJBgAAAA==.',
At='Atax:BAABLgAECn8rAAITAAkJOhrbCgBTAgATAAkJOhrbCgBTAgAAAA==.Athená:BAAALgAECggJEgAAAA==.Atheum:BAAALgADCgQJBAAAAA==.',
Au='Auralyn:BAAALgADCgcJDgAAAA==.Aurelitrasza:BAAALgADCgkJFwAAAA==.',
Av='Avicena:BAAALgAECgUJCAAAAA==.Avicii:BAAALgADCgUJCgAAAA==.Avrice:BAAALgAECgYJDQAAAA==.',
Ax='Axfrosty:BAAALgADCgQJBAAAAA==.Axiona:BAAALgAECgEJAQAAAA==.',
Ay='Ayakia:BAABLgAECn8UAAIUAAcJpA4sNgBGAQAUAAcJpA4sNgBGAQAAAA==.Ayaku:BAAALgAECgIJAgAAAA==.',
Az='Azuraa:BAAALgADCgUJCAAAAA==.',
Ba='Badshot:BAAALgAECgYJDwAAAA==.Baiogg:BAABLgAECn8YAAIBAAcJMgVcmwDwAAABAAcJMgVcmwDwAAAAAA==.Baldord:BAAALgADCgMJBAAAAA==.Balthromaww:BAAALgAECgYJBwAAAA==.Balung:BAAALgAECgQJBgAAAA==.Bambu:BAAALgAECgYJEgAAAA==.Bamevoker:BAAALgAECgMJAwABLgAECgYJEgAVAAAAAA==.Bariggs:BAACLgAFFH8GAAIWAAIJvyPxGwC2AAAWAAIJvyPxGwC2AAAuAAQKfxoAAhYACAkVI+cEAMYCABYACAkVI+cEAMYCAAAA.Barilia:BAAALgAECgYJDwAAAA==.',
Be='Beals:BAAALgADCgMJAwAAAA==.Bearlyalive:BAAALgAECgIJAgAAAA==.Beladra:BAAALgADCgUJCwAAAA==.Belekor:BAAALgAECgYJCQAAAA==.Beltayn:BAAALgAECgYJCwAAAA==.Ben:BAABLgAECn8gAAIMAAkJfhouFABNAgAMAAkJfhouFABNAgAAAA==.Beriadan:BAABLgAECn8UAAIXAAgJ2xcgHgDEAQAXAAgJ2xcgHgDEAQAAAA==.Bevee:BAAALgAECgQJCQAAAA==.Bewitchin:BAAALgAECgEJAQAAAA==.',
Bi='Bigponch:BAAALgADCgEJAQAAAA==.Birst:BAAALgADCggJBAAAAA==.Bisque:BAAALgAECgMJAwAAAA==.',
Bl='Bladesrus:BAAALgAECgMJBQAAAA==.Blaithe:BAAALgAECgEJAQAAAA==.Bleddwen:BAAALgAECggJIwAAAQ==.Bliggix:BAAALgADCgQJBAAAAA==.Blrsama:BAAALgADCgUJBgAAAA==.',
Bo='Bodok:BAABLgAECn8wAAMLAAkJeRcDIAA3AgALAAkJeRcDIAA3AgAYAAEJyAXaLgAlAAAAAA==.Bohrnir:BAABLgAECn86AAMKAAkJaB5vEQCYAgAKAAkJaB5vEQCYAgAXAAMJ/QiZaQB0AAAAAA==.Boomonster:BAAALgAECgEJAQAAAA==.Borealsnow:BAAALgADCgkJEQAAAA==.Boüh:BAABLgAECn8jAAIZAAgJVB2dCQCuAgAZAAgJVB2dCQCuAgAAAA==.',
Br='Brackiss:BAAALgAECgMJAwAAAA==.Brokiinn:BAACLgAFFH8FAAIIAAIJ9BFiFQCvAAAIAAIJ9BFiFQCvAAAuAAQKfxoAAggACAl1GfAbAF8CAAgACAl1GfAbAF8CAAAA.Brutalix:BAAALgADCgYJDQAAAA==.Brynda:BAAALgADCgQJBAAAAA==.',
Bu='Budikah:BAAALgAECgQJAgAAAA==.Budlana:BAAALgAECgEJAgAAAA==.Burd:BAAALgADCgcJBwAAAA==.Burmeister:BAABLgAECn8qAAMaAAgJnAv3LgA1AQAaAAgJnAv3LgA1AQAbAAYJqAeybgDHAAAAAA==.Burnadine:BAABLgAECn8fAAMcAAgJMAfuEQD8AAAcAAgJMAfuEQD8AAABAAQJsQHE9gBRAAAAAA==.Burnswhnpee:BAACLgAFFH8HAAIBAAMJXxHjXgDaAAABAAMJXxHjXgDaAAAuAAQKfxsABBwACQkMFR4cAG0BABwABgnnEh4cAG0BAAEABwn+EN6FABkBAB0AAglUCMYiAGcAAAAA.Burtelby:BAAALgADCgYJBgAAAA==.',
['Bù']='Bùrd:BAAALgAECgcJBwAAAA==.',
['Bû']='Bûrd:BAABLgAECn83AAQRAAkJ3hIuAwDXAQARAAkJ8A8uAwDXAQAJAAcJzQxjnQAlAQAeAAYJ6Q+FBgAKAQAAAA==.',
Ca='Cadsuàne:BAAALgADCgUJCAAAAA==.Caliie:BAABLgAECn8rAAMKAAkJrwnWWQAZAQAKAAgJpAbWWQAZAQAXAAgJtgRuSADhAAAAAA==.Callektra:BAAALgADCgIJAgAAAA==.Callira:BAAALgAECgUJEAAAAA==.Cambiare:BAAALgADCgYJCgAAAA==.Canaandra:BAAALgADCgkJBwAAAA==.Captclamslam:BAABLgAECn8sAAMfAAkJ/xd4BgBKAgAfAAkJ/xd4BgBKAgASAAgJ+Q1SIAAHAQAAAA==.Carolline:BAAALgADCgkJCwAAAA==.Cassity:BAAALgAECgEJAQAAAA==.Catherinecay:BAAALgADCgcJBwAAAA==.Caylor:BAAALgADCgQJBAAAAA==.',
Ce='Cereania:BAAALgAECgYJEgAAAA==.Cerrabell:BAAALgADCgcJBwAAAA==.',
Ch='Charzzard:BAAALgADCgEJAQAAAA==.Charå:BAAALgADCgQJBAAAAA==.Checksmix:BAAALgAECgEJAQAAAA==.Chintakari:BAABLgAECn8cAAMIAAgJdRQRSACdAQAIAAgJdRQRSACdAQAWAAEJLwe4MAAxAAAAAA==.Chlorofill:BAAALgAECgcJCwAAAA==.Chronologic:BAAALgAECgYJEAAAAA==.Chthonyx:BAAALgAECgYJBgAAAA==.Chucklemonk:BAAALgADCggJDwAAAA==.',
Co='Cocidiae:BAAALgAECgEJBQAAAA==.Confusious:BAACLgAFFH8TAAIKAAUJ2RlSFQByAQAKAAUJ2RlSFQByAQAuAAQKfy0AAwoACQnkGKoiABECAAoACQnkGKoiABECABcAAQkqCbiUACYAAAAA.Coree:BAABLgAECn9EAAIgAAgJphLYBwCVAQAgAAgJphLYBwCVAQAAAA==.Cornflower:BAABLgAECn8cAAIEAAgJkQ92LABCAQAEAAgJkQ92LABCAQAAAA==.Corvaan:BAACLgAFFH8FAAILAAQJ5QIyTQDSAAALAAQJ5QIyTQDSAAAuAAQKfyUAAgsACQnlEZU5AL8BAAsACQnlEZU5AL8BAAAA.',
Cr='Cracklepants:BAAALgAECgQJBAAAAA==.Creg:BAABLgAECn8sAAILAAkJBiC9DADFAgALAAkJBiC9DADFAgAAAA==.Crotalhusk:BAAALgAECgEJAQAAAA==.Crowbarr:BAAALgADCgUJBQAAAA==.Cryostatic:BAAALgAECgcJCgABLgAECgYJKAAhAPMJAA==.',
Cu='Cultel:BAACLgAFFH8KAAIYAAMJ0Rn0BADfAAAYAAMJ0Rn0BADfAAAuAAQKf0IAAhgACQm3IiEBAA8DABgACQm3IiEBAA8DAAAA.',
Cy='Cyendia:BAABLgAECn8jAAIKAAgJiBmEGgBJAgAKAAgJiBmEGgBJAgAAAA==.Cyer:BAAALgAECgQJBgAAAA==.',
Da='Daddyraz:BAABLgAECn8XAAILAAgJnRWeZAB0AQALAAgJnRWeZAB0AQAAAA==.Dakan:BAAALgAECgQJBwAAAA==.Damadar:BAAALgAECgYJBgABLgAECggJGwAhACQeAA==.Daphcelyn:BAAALgAECgUJEAAAAA==.Dariusz:BAAALgAECggJEwAAAA==.Darkalen:BAABLgAECn82AAIiAAkJHh1mBwCBAgAiAAkJHh1mBwCBAgAAAA==.Darklodus:BAAALgADCgcJEwAAAA==.Darriuss:BAABLgAECn8kAAIQAAYJqgTr2wC8AAAQAAYJqgTr2wC8AAAAAA==.Darthvaderp:BAAALgAFFAEJAQABLgAFFAIJBQABAPIbAA==.Dathea:BAAALgADCgYJBgAAAA==.Davìd:BAAALgAECgEJAQABLgAFFAIJBAAVAAAAAA==.Dawnmist:BAAALgAECgQJCAAAAA==.Daxetandh:BAAALgAECgIJBgAAAA==.Daxetanir:BAAALgADCgMJAwABLgAFFAIJBQAXABEaAA==.Daxetans:BAACLgAFFH8FAAIXAAIJERpmFACpAAAXAAIJERpmFACpAAAuAAQKfz4AAxcACQngIQ0EAAoDABcACQngIQ0EAAoDAAoABwk+DN5GAGYBAAAA.',
De='Deadmoose:BAABLgAECn85AAIGAAkJBheyNwD+AQAGAAkJBheyNwD+AQAAAA==.Deathb:BAAALgADCgkJJgAAAA==.Deathjingle:BAACLgAFFH8JAAIGAAIJ4RyhnACaAAAGAAIJ4RyhnACaAAAuAAQKfzoAAyIACQkwIfUGAIoCACIACAkGIvUGAIoCAAYACQmYF4RHAB0CAAAA.Deecayed:BAABLgAECn8cAAIQAAgJkBTpWACiAQAQAAgJkBTpWACiAQAAAA==.Deecoy:BAAALgAECgYJDgAAAA==.Deestroyer:BAAALgAECgUJDwAAAA==.Deetermined:BAACLgAFFH8OAAIKAAQJEhGOKQADAQAKAAQJEhGOKQADAQAuAAQKfykAAgoACQkSIFIHABQDAAoACQkSIFIHABQDAAAA.Delion:BAAALgADCgIJAgAAAA==.Demhuloo:BAAALgAECgQJBwAAAA==.Demonburp:BAACLgAFFH8KAAILAAMJZR66OQARAQALAAMJZR66OQARAQAuAAQKfzoAAgsACQlkIlkHAAMDAAsACQlkIlkHAAMDAAAA.Denchy:BAABLgAECn8sAAIjAAgJigYiJwAHAQAjAAgJigYiJwAHAQAAAA==.Dendris:BAAALgAECgQJCAAAAA==.Denogginator:BAAALgADCgEJAQAAAA==.Desetraz:BAAALgAECgYJCwAAAQ==.Deval:BAAALgADCgQJBAAAAA==.Deyndine:BAABLgAECn8cAAIBAAcJthIjZQBdAQABAAcJthIjZQBdAQAAAA==.',
Dh='Dhurza:BAAALgAFFAIJAgAAAA==.',
Di='Diabolac:BAAALgAECgUJBQAAAA==.Disdain:BAAALgAECgYJDAAAAA==.Div:BAABLgAECn9AAAIhAAkJqR7HAgDRAgAhAAkJqR7HAgDRAgAAAA==.',
Do='Dogdays:BAAALgADCgkJCQAAAA==.Doki:BAAALgAECgIJAgAAAA==.Donk:BAAALgADCgEJAQAAAA==.Dorden:BAABLgAECn86AAMHAAkJIhHyIACuAQAHAAkJIhHyIACuAQAkAAcJJxAyHAD5AAAAAA==.Dorilax:BAABLgAECn8VAAMEAAgJrBFBIQDZAQAEAAgJrBFBIQDZAQAZAAEJvwFgXgAlAAABLgAECgkJFQABAOYdAA==.Dottarus:BAAALgAECgQJBQAAAA==.',
Dr='Draevus:BAAALgAECgQJBQAAAA==.Dragooniar:BAAALgAECgYJEgAAAA==.Draizen:BAAALgAECgkJDQAAAA==.Dralara:BAAALgADCggJDgAAAA==.Dreàd:BAABLgAECn8ZAAIXAAYJjxTHPgAIAQAXAAYJjxTHPgAIAQAAAA==.Driadora:BAAALgAECgYJCAAAAA==.Drinna:BAAALgAECgMJBgAAAA==.Drizzette:BAAALgADCgEJAQAAAA==.Droataxh:BAAALgADCgMJAwABLgAECgkJQAAJAOIgAA==.Droataxm:BAABLgAECn9AAAIJAAkJ4iBLDgBUAwAJAAkJ4iBLDgBUAwAAAA==.Druntress:BAABLgAECn8VAAIPAAgJ0xK8LADJAQAPAAgJ0xK8LADJAQAAAA==.',
Du='Duarraag:BAAALgADCgIJAQAAAA==.',
['Dà']='Dàvid:BAAALgAFFAIJBAAAAA==.Dàvìd:BAAALgAECgQJBAABLgAFFAIJBAAVAAAAAA==.',
['Dè']='Dèmonic:BAAALgAECgUJCAAAAA==.',
['Dë']='Dëërez:BAABLgAECn8hAAIbAAcJzQsBVAAeAQAbAAcJzQsBVAAeAQAAAA==.',
Eb='Eburi:BAACLgAFFH8FAAIGAAMJ5Qk3hQDJAAAGAAMJ5Qk3hQDJAAAuAAQKfxYAAgYACAlkFdxXAJoBAAYACAlkFdxXAJoBAAAA.',
Ed='Edgybear:BAAALgADCggJCAAAAA==.',
Ei='Eililis:BAAALgAECgMJCQAAAA==.',
El='Elani:BAAALgAECgMJAwABLgAECgYJDwAVAAAAAA==.Elaynaa:BAABLgAECn8fAAIXAAgJuxqXEwAjAgAXAAgJuxqXEwAjAgAAAA==.Eledweth:BAAALgADCgEJAgAAAA==.Elemengoat:BAAALgADCgQJBAAAAA==.Elfstar:BAAALgAECgYJEwAAAA==.Elihe:BAAALgADCgEJAQAAAA==.Elishan:BAAALgADCgkJEgAAAA==.Elishaunt:BAABLgAECn8WAAIYAAYJRg4yFgDLAAAYAAYJRg4yFgDLAAAAAA==.Elivan:BAAALgAECgYJBgAAAA==.Elleth:BAAALgAECgYJEAAAAA==.Elliana:BAAALgAECgQJBgAAAA==.Eloper:BAACLgAFFH8LAAIlAAQJmgZyIQD9AAAlAAQJmgZyIQD9AAAuAAQKfxQAAyUACAkyEMYyAFkBACUACAkyEMYyAFkBACMAAQl+C6pjACwAAAEuAAQKAQkBABUAAAAA.Elvoidra:BAAALgAECgMJBwAAAA==.Elykk:BAAALgAECggJDQAAAA==.',
Em='Emanymton:BAAALgAECgQJBAAAAA==.Emberana:BAAALgADCgUJBQAAAA==.',
En='Endb:BAAALgADCgkJIQAAAA==.Enjin:BAAALgADCgUJBQAAAA==.Envi:BAAALgADCgUJBQAAAA==.',
Er='Erisaria:BAAALgADCgQJBQAAAA==.Erixi:BAABLgAECn8jAAImAAgJphhOCQD2AQAmAAgJphhOCQD2AQAAAA==.Erodoreal:BAAALgAECggJEQAAAA==.',
Et='Etheria:BAAALgAECgYJCAAAAA==.',
Ev='Evissier:BAACLgAFFH8MAAIdAAQJ2xmrAQBqAQAdAAQJ2xmrAQBqAQAuAAQKfx0AAh0ACAmuIAcBAAIDAB0ACAmuIAcBAAIDAAAA.Evocore:BAAALgAECgYJEgAAAA==.',
Ex='Excelimagust:BAAALgAECgYJDAAAAA==.',
Fa='Faelieline:BAAALgADCgYJBwAAAA==.Faithful:BAAALgAECgcJBwABLgAECgkJJQAhABwbAA==.Falanor:BAAALgAECgQJBAABLgAECgYJCQAVAAAAAA==.Falcdhruid:BAAALgAECgQJCgAAAA==.Fangrage:BAAALgAECgMJBQAAAA==.Farundi:BAAALgAECgUJDQAAAA==.Fayemoon:BAAALgAECgYJEwAAAA==.',
Fe='Felara:BAAALgAECgYJBwABLgAFFAMJBgANABkdAA==.Felbutton:BAAALgAECgUJCQAAAA==.Feldemon:BAAALgAECgQJBgAAAA==.Fellost:BAAALgAECgQJBQABLgAFFAMJBgANABkdAA==.Felsen:BAAALgAECgIJAgABLgAFFAMJBgANABkdAA==.Felwit:BAACLgAFFH8GAAINAAMJGR2VEQD0AAANAAMJGR2VEQD0AAAuAAQKfxwAAg0ACQlOG2sOANkBAA0ACQlOG2sOANkBAAAA.Fennec:BAABLgAECn8dAAInAAcJSw9iCwBZAQAnAAcJSw9iCwBZAQAAAA==.Ferrozious:BAAALgAECgQJBAAAAA==.',
Fh='Fhyn:BAAALgAECgUJDAAAAA==.',
Fi='Fitzooth:BAAALgAFFAEJAQAAAA==.Fizzlezapp:BAAALgAECgEJAQAAAA==.',
Fl='Flamos:BAAALgADCgYJBgAAAA==.Florabelle:BAAALgAECgMJAwABLgAECggJHAAEAJEPAA==.Florid:BAABLgAECn8eAAIJAAgJwgk0fwBcAQAJAAgJwgk0fwBcAQAAAA==.Fluttershy:BAABLgAFFH8JAAIbAAYJ7AQ7GwBIAQAbAAYJ7AQ7GwBIAQAAAA==.',
Fo='Foshomomo:BAABLgAECn8qAAIUAAkJxBWVFAA7AgAUAAkJxBWVFAA7AgAAAA==.Fozzle:BAABLgAECn8nAAIJAAkJCA+HTQDWAQAJAAkJCA+HTQDWAQAAAA==.',
Fr='Fredoku:BAAALgAECgMJBAAAAA==.Fredragon:BAAALgAECgEJAQAAAA==.Frenndi:BAAALgAECgYJEwAAAA==.Frostbites:BAAALgAECgEJAQAAAA==.Frostbolts:BAAALgAECgEJAgAAAA==.',
Fu='Furroz:BAAALgAECgEJAQABLgAECgkJNgAiAB4dAA==.',
Fy='Fynedge:BAABLgAECn8jAAIQAAgJZgrHewBWAQAQAAgJZgrHewBWAQAAAA==.Fynnyntyss:BAABLgAECn89AAIoAAkJvxOqBAAEAgAoAAkJvxOqBAAEAgAAAA==.Fyrè:BAABLgAECn89AAIIAAkJGyPsBQAWAwAIAAkJGyPsBQAWAwAAAA==.',
['Fâ']='Fârrah:BAAALgAECgQJBgAAAA==.',
Ga='Gabriels:BAAALgADCgcJFQAAAA==.Gabrielspet:BAAALgADCgIJAgAAAA==.Gainsborough:BAAALgAECgYJBgAAAA==.Galactis:BAAALgAECgcJCgAAAA==.Gavinrad:BAAALgAECgQJBAAAAA==.',
Ge='Gelilla:BAAALgAECgIJAgAAAA==.Gelirri:BAAALgADCgIJAgAAAA==.Ger:BAAALgADCggJCgAAAA==.Geremiah:BAAALgAECgIJAgAAAA==.Getschwiftyy:BAAALgAECgEJAQAAAA==.',
Gi='Githnor:BAABLgAECn8+AAIQAAkJxwpDXACaAQAQAAkJxwpDXACaAQAAAA==.',
Gl='Glendara:BAAALgADCggJDwAAAA==.',
Go='Gorellan:BAAALgAECgQJBAAAAA==.Goretall:BAAALgADCgYJCAAAAA==.Gothen:BAAALgADCgEJAQAAAA==.',
Gr='Graelyn:BAABLgAECn8XAAMQAAcJLAvsjABhAQAQAAcJVgrsjABhAQAhAAIJQQmRQQA3AAAAAA==.Grilledchis:BAAALgAECgEJAQAAAA==.Grimseth:BAAALgADCgUJBQAAAA==.Grimwharf:BAAALgAECgUJCQAAAA==.Grishnákh:BAAALgADCgIJAgAAAA==.Gromnor:BAAALgAECgEJAQAAAA==.Grum:BAAALgADCgUJBQAAAA==.Grunaelyn:BAABLgAECn8aAAIXAAgJoBCyLQBeAQAXAAgJoBCyLQBeAQAAAA==.',
Gu='Guerrier:BAABLgAECn8VAAIPAAYJNA6yFQDnAAAPAAYJNA6yFQDnAAAAAA==.Gustgut:BAAALgAECgMJBAAAAA==.',
Ha='Haelynn:BAAALgADCgcJDAAAAA==.Hahkolhanna:BAAALgADCggJEwAAAA==.Handrido:BAAALgAECgYJCgAAAA==.Hantaro:BAAALgADCgMJAwAAAA==.Hasuna:BAABLgAECn8XAAMlAAgJ3gMATgDlAAAlAAgJtAMATgDlAAAjAAYJJgNZQwCDAAAAAA==.',
He='Heikuro:BAABLgAECn8wAAMYAAgJoSGvAgCmAgAYAAgJoSGvAgCmAgALAAYJwhnaZgBtAQAAAA==.Heiler:BAAALgAECgQJBAABLgAECgcJBwAVAAAAAA==.Heris:BAAALgADCgcJDAAAAA==.',
Hi='Hibby:BAAALgAECgMJBAAAAA==.',
Ho='Holymilk:BAAALgAECgIJAgAAAA==.Holysalt:BAAALgADCgUJCwAAAA==.Hommy:BAAALgADCgYJBgAAAA==.Hommytick:BAAALgADCgYJBwAAAA==.Honadain:BAABLgAECn8aAAIQAAYJshpFaQB8AQAQAAYJshpFaQB8AQAAAA==.Honordin:BAABLgAECn8wAAIQAAkJ1R+WGACSAgAQAAkJ1R+WGACSAgAAAA==.Hordestalker:BAAALgAECgQJBwAAAA==.Houllian:BAABLgAECn8WAAIBAAYJjQx7kAAEAQABAAYJjQx7kAAEAQAAAA==.Houtu:BAAALgAECgUJBQAAAA==.',
Hu='Hucha:BAAALgAECgMJBQAAAA==.Hundren:BAAALgAECgEJAQAAAA==.',
Hw='Hweilan:BAAALgAECgYJCwAAAA==.',
Hy='Hypnos:BAAALgAECgEJAQAAAA==.',
['Hö']='Hölyföx:BAAALgAECgQJBAAAAA==.',
Ia='Iamearl:BAAALgAECgYJDwAAAA==.Iamirishgirl:BAAALgADCgIJAgAAAA==.',
Ic='Icyhotness:BAAALgADCgYJBgAAAA==.Icê:BAAALgADCgcJFAAAAA==.',
Ik='Iklyn:BAAALgAECgMJAQAAAA==.',
Il='Illanna:BAAALgAECgMJAwAAAA==.',
Im='Imckickinit:BAAALgAECgQJBAAAAA==.Imorith:BAAALgAECgYJDwAAAA==.',
In='Inania:BAAALgAECggJEwAAAA==.Inception:BAAALgAECgIJAwAAAA==.Incidental:BAABLgAECn87AAMOAAkJMySrAQCOAwAOAAkJMySrAQCOAwAMAAMJFROuRgC6AAAAAA==.Inconell:BAABLgAECn8xAAIlAAgJAgYwQAAbAQAlAAgJAgYwQAAbAQAAAA==.Invega:BAAALgADCgkJDQAAAA==.',
Ip='Iport:BAAALgAECgIJAgAAAA==.Ippondoch:BAAALgAECgEJAQAAAA==.',
Ir='Iric:BAAALgAECgMJBAAAAA==.Irinal:BAAALgADCggJCAAAAA==.Ironi:BAACLgAFFH8KAAMbAAMJFQjVOACwAAAbAAMJFQjVOACwAAAaAAMJyQPTKgCjAAAuAAQKfz4AAxsACQltF9gWAG4CABsACQltF9gWAG4CABoABgmoCh5JALUAAAAA.',
Is='Isabelle:BAAALgAECgYJEAAAAA==.Isai:BAAALgAECgEJAQAAAA==.Iskandar:BAACLgAFFH8GAAIlAAIJYxb3MACbAAAlAAIJYxb3MACbAAAuAAQKfzYAAyUACQnHGe4PAFcCACUACQnHGe4PAFcCACMAAQliDOBiAC0AAAAA.',
Iy='Iyashaau:BAAALgAECgEJAgAAAQ==.',
Iz='Izaer:BAABLgAECn8gAAIEAAYJXBLBLQA5AQAEAAYJXBLBLQA5AQAAAA==.Iziel:BAAALgAECgYJEQAAAA==.',
Ja='Jababa:BAAALgADCgMJAwAAAA==.Jabzaklok:BAAALgAECgcJEwAAAA==.Jahirah:BAABLgAECn8gAAIJAAgJBheZWAC2AQAJAAgJBheZWAC2AQABLgAECggJIAABAGcPAA==.Jaleika:BAAALgADCgkJIwAAAA==.Janaian:BAABLgAECn8fAAMaAAgJURPjMAApAQAaAAgJURPjMAApAQAbAAMJ7g36nACRAAAAAA==.Jarius:BAABLgAECn8kAAICAAkJrgyJJgCvAQACAAkJrgyJJgCvAQAAAA==.Jashah:BAAALgADCgkJEgABLgAECgkJPQAoAL8TAA==.Jazaray:BAAALgADCgkJKwAAAA==.',
Je='Jean:BAABLgAECn80AAIIAAgJ7h3ZGABzAgAIAAgJ7h3ZGABzAgAAAA==.Jeez:BAABLgAFFH8HAAIfAAMJ9gniCgDAAAAfAAMJ9gniCgDAAAAAAA==.Jeri:BAACLgAFFH8ZAAMIAAYJoBq3HABRAQAIAAQJARy3HABRAQAPAAUJ9wrpEgAPAQAuAAQKfysAAwgACQlVI4goABICAAgACAmmI4goABICAA8ABglTHMsnAOwBAAAA.Jeriaze:BAAALgADCgkJEgAAAA==.',
Jo='Jokuo:BAAALgADCgEJAQAAAA==.Jonyy:BAAALgADCgcJCAAAAA==.Joona:BAAALgADCgUJBQAAAA==.Jorianna:BAAALgAECgYJEAAAAA==.Joru:BAACLgAFFH8gAAImAAgJ6h8MAADsAgAmAAgJ6h8MAADsAgAuAAQKfx4AAiYACAmrJYkDAKMCACYACAmrJYkDAKMCAAAA.',
Ju='Jul:BAAALgAECgcJCAABLgAECgcJCgAVAAAAAA==.',
Jy='Jynxmaze:BAAALgADCgQJAwAAAA==.',
['Jê']='Jênny:BAAALgAECgMJAwAAAA==.',
['Jí']='Jím:BAAALgADCgQJBAABLgAECggJJwABAEwlAA==.',
Ka='Kaai:BAAALgAECgYJEwAAAA==.Kabaul:BAABLgAECn8vAAMlAAkJDiJJAgCZAwAlAAkJDiJJAgCZAwAjAAEJcROVPgA7AAAAAA==.Kabir:BAABLgAECn8mAAIJAAgJ6wwzcAB9AQAJAAgJ6wwzcAB9AQAAAA==.Kadria:BAABLgAECn8jAAMbAAgJ7xvYGABcAgAbAAcJVR3YGABcAgAaAAgJChk+FgD0AQAAAA==.Kady:BAAALgAECgMJAwABLgAECggJGwAhACQeAA==.Kaelon:BAAALgAECgkJCQAAAA==.Kail:BAAALgAECgUJDwAAAA==.Kailanii:BAABLgAECn8fAAMbAAgJQBRILQDPAQAbAAgJQBRILQDPAQAaAAIJ5QZOdABRAAAAAA==.Kaiscer:BAAALgAECgMJBAAAAA==.Kaitsura:BAAALgADCgUJBQAAAA==.Kaiyne:BAABLgAECn8jAAMBAAkJFhWeSwChAQABAAkJFhWeSwChAQAcAAEJdQ8ScQA1AAAAAA==.Kajiere:BAAALgADCgIJAgAAAA==.Kalagon:BAAALgAECgEJAQAAAA==.Kalakeri:BAAALgAECgQJBAAAAA==.Kalaman:BAAALgAECgYJDAAAAA==.Kalian:BAABLgAECn8XAAIIAAcJ+xXzVgBxAQAIAAcJ+xXzVgBxAQAAAA==.Kalito:BAAALgAECgQJDQAAAA==.Kallei:BAAALgADCgEJAQAAAA==.Kamb:BAABLgAECn8rAAIYAAkJrRcwBQA0AgAYAAkJrRcwBQA0AgAAAA==.Kamuros:BAAALgADCgYJBgAAAA==.Karalee:BAAALgAECgUJDwAAAA==.Karn:BAAALgADCgEJAQAAAA==.Katieey:BAACLgAFFH8iAAIKAAgJDyECAAD0AgAKAAgJDyECAAD0AgAuAAQKfxcAAwoACQnYJMQHAPgCAAoACAmTJMQHAPgCABcABAmiHYQ7AF8BAAAA.Kayde:BAAALgAECggJDwAAAA==.Kayil:BAAALgAECgYJDAAAAA==.Kayl:BAACLgAFFH8KAAIHAAMJzQjpNQC8AAAHAAMJzQjpNQC8AAAuAAQKfzMAAwcACQlaGeUPAEsCAAcACQlaGeUPAEsCACgABAk/EdQoANkAAAAA.Kaylli:BAAALgAECgQJCwAAAA==.',
Ke='Kedalin:BAAALgAECgYJDAAAAA==.Keelnin:BAAALgAECgIJBAAAAA==.Keloko:BAAALgAECgQJBgAAAA==.Kennyloggy:BAACLgAFFH8jAAIaAAgJHyDwAAC4AgAaAAgJHyDwAAC4AgAuAAQKfzYAAhoACQmCJv8AANIDABoACQmCJv8AANIDAAAA.Kerlock:BAAALgAECgUJBQABLgAFFAIJBQApABwdAA==.Kerlok:BAAALgAECgQJBQABLgAFFAIJBQApABwdAA==.Kernunnos:BAAALgAECgIJAgAAAA==.Kevris:BAABLgAECn8gAAIBAAgJZw/YXwBrAQABAAgJZw/YXwBrAQAAAA==.Keydan:BAABLgAECn8gAAISAAgJKRGaFgBeAQASAAgJKRGaFgBeAQAAAA==.',
Kh='Khaitiff:BAAALgADCgYJBgAAAA==.Khyn:BAAALgAECgQJCQABLgAECgUJDAAVAAAAAA==.',
Ki='Killmaim:BAAALgAECgYJBwAAAA==.Killrok:BAAALgADCgUJBQAAAA==.Kinikey:BAABLgAECn8bAAIBAAgJQAaffgAnAQABAAgJQAaffgAnAQAAAA==.',
Kl='Klassy:BAACLgAFFH8IAAIWAAMJLRJhFgDzAAAWAAMJLRJhFgDzAAAuAAQKfzoAAhYACQmWIpkCAAcDABYACQmWIpkCAAcDAAAA.',
Kn='Knardil:BAAALgADCgIJBAAAAA==.',
Ko='Kolosim:BAAALgADCgYJBgAAAA==.Koppi:BAAALgAECgYJDQAAAA==.Korru:BAABLgAECn8ZAAMDAAcJTwwWMgAqAQADAAcJTwwWMgAqAQAEAAIJUgxocQBhAAAAAA==.Kotie:BAABLgAECn8tAAIaAAgJVxndFAADAgAaAAgJVxndFAADAgAAAA==.',
Kr='Kramz:BAACLgAFFH8KAAIBAAMJAxtfUAD9AAABAAMJAxtfUAD9AAAuAAQKfxkAAwEACQkRG24vAAICAAEABwkYGG4vAAICABwABgklG70TAK0BAAAA.Kronar:BAAALgAECgYJDQAAAA==.',
Ku='Kumojo:BAAALgADCgYJBwAAAA==.Kunka:BAAALgAECgYJCQAAAA==.Kurgan:BAAALgAECgEJBQAAAA==.',
Ky='Kyojin:BAAALgAECgEJAgAAAA==.Kyoshino:BAAALgAECgMJAwAAAA==.Kyrgune:BAAALgAECgQJBwAAAA==.',
['Kî']='Kîkuko:BAAALgAECgcJCgAAAA==.',
['Kÿ']='Kÿliah:BAAALgAECgEJAwAAAA==.',
La='Lalo:BAAALgAECgYJEAAAAA==.Landilion:BAAALgADCgYJBgAAAA==.Laoftey:BAACLgAFFH8KAAIKAAMJzRpHMQDoAAAKAAMJzRpHMQDoAAAuAAQKfzYAAwoACQmlHe0RAJMCAAoACQmlHe0RAJMCABcAAQnZD1uJAC8AAAAA.Laofty:BAAALgAECgEJAQAAAA==.Lar:BAAALgADCgEJAgAAAA==.Laserbeam:BAABLgAECn8YAAILAAcJ6xrEOQC+AQALAAcJ6xrEOQC+AQABLgAFFAIJBQABAPIbAA==.Laserface:BAAALgADCgkJCQAAAA==.Lasmori:BAAALgAECgYJDwAAAA==.Laxxbroo:BAAALgAECgQJBQAAAA==.Lazaris:BAAALgADCgYJBgAAAA==.',
Le='Leglock:BAABLgAECn8YAAILAAgJ+xDHTgB3AQALAAgJ+xDHTgB3AQAAAA==.Leiff:BAAALgADCgYJBgAAAA==.Leprhicon:BAAALgAECgYJCQAAAA==.Lesbireal:BAABLgAECn8jAAMQAAgJtxSGVwCmAQAQAAgJjRSGVwCmAQAhAAUJWRIiIQD+AAAAAA==.',
Li='Liastella:BAAALgADCgIJAgAAAA==.Lichtbringer:BAAALgAECgcJBwAAAA==.Liendria:BAAALgADCgIJAgAAAA==.Lifensoftpaw:BAACLgAFFH8cAAMMAAcJwRqGAQC9AQAMAAUJTiCGAQC9AQAUAAUJVAHDIADuAAAuAAQKfy4ABAwACQnoI3YEAPECAAwACQnoI3YEAPECAA4ABQl3HJ44AGcBABQAAglxAUNzAB8AAAAA.Lightcaller:BAAALgADCgEJAQAAAA==.Lightflasher:BAAALgAECgcJEwAAAA==.Likkash:BAAALgAECgcJDQABLgAECgkJNgAiAB4dAA==.Linari:BAAALgADCgMJAwAAAA==.Linthabeela:BAAALgADCgcJDgAAAA==.Lishalthen:BAAALgADCggJCAAAAA==.Lisyanthus:BAAALgAECgcJBwAAAA==.Livicecia:BAABLgAECn8bAAIfAAkJgQoNGQANAQAfAAkJgQoNGQANAQAAAA==.',
Lo='Loaftey:BAAALgADCggJCAAAAA==.Longworth:BAAALgADCgIJAgAAAA==.Lookman:BAABLgAECn8ZAAICAAYJAhxyIQDSAQACAAYJAhxyIQDSAQAAAA==.Lothema:BAAALgAECgYJCgAAAA==.Lowang:BAAALgAECgEJAgAAAA==.',
Lu='Lucaromu:BAAALgAECgEJAQAAAA==.Lucielinna:BAAALgAECggJDQABLgAECggJEgAVAAAAAA==.Luckiiem:BAACLgAFFH8KAAIJAAMJHxuPVwATAQAJAAMJHxuPVwATAQAuAAQKfzgAAgkACQn3ImQKABEDAAkACQn3ImQKABEDAAAA.Luisfriendsn:BAAALgADCgEJAQABLgAECgcJIgARAKMZAA==.Lunabreeze:BAAALgADCgkJEAAAAA==.Lunarkin:BAABLgAECn8cAAMaAAYJwg7aOwDvAAAaAAYJwg7aOwDvAAAbAAEJCxEJuwA0AAAAAA==.Luoma:BAABLgAECn8bAAIMAAgJ3Q2PJQBcAQAMAAgJ3Q2PJQBcAQAAAA==.Luthane:BAABLgAECn8oAAIQAAgJMQhdjQA2AQAQAAgJMQhdjQA2AQAAAA==.',
Ly='Lyfeliss:BAAALgAECgYJDgAAAA==.Lykinea:BAAALgAECgYJCwAAAA==.Lynn:BAAALgAECgUJBQABLgAFFAMJAwAVAAAAAA==.Lynnesa:BAAALgAECgIJAgAAAA==.',
Ma='Maccolyn:BAABLgAECn8iAAIQAAkJgxnBMAAcAgAQAAkJgxnBMAAcAgAAAA==.Magicpie:BAABLgAECn87AAIEAAkJfiKtAgBYAwAEAAkJfiKtAgBYAwAAAA==.Magikar:BAAALgAECgEJAQAAAA==.Magiren:BAAALgAECgYJBwAAAA==.Mahlock:BAACLgAFFH8KAAITAAMJEgxQIADfAAATAAMJEgxQIADfAAAuAAQKf0IAAhMACQnEHf4GAJgCABMACQnEHf4GAJgCAAAA.Mainah:BAAALgAECgIJAgAAAA==.Makanai:BAAALgAECgYJDgAAAA==.Makenai:BAAALgADCgkJKgABLgAECgYJDgAVAAAAAA==.Makishi:BAABLgAECn8sAAIYAAgJVx9UBABVAgAYAAgJVx9UBABVAgAAAA==.Malferious:BAAALgADCgkJCQAAAA==.Malfura:BAABLgAECn8fAAIaAAYJzRB4NQAPAQAaAAYJzRB4NQAPAQAAAA==.Malário:BAAALgADCgMJAwAAAA==.Manamontana:BAABLgAECn8XAAIJAAcJaQ4InACdAQAJAAcJaQ4InACdAQAAAA==.Mandragoria:BAAALgADCggJCAABLgAECgcJHAABALYSAA==.Maplebunny:BAAALgADCgMJAwAAAA==.Mascdomtop:BAACLgAFFH8KAAIEAAMJUB98EQAPAQAEAAMJUB98EQAPAQAuAAQKfyYAAwQACQmWHXMIAMQCAAQACQmWHXMIAMQCAAMACAlGCsMvADYBAAAA.Matalin:BAAALgAECgEJAQAAAA==.Maube:BAAALgAECgYJDgABLgAFFAQJFAAhAFgPAA==.Mayonnaise:BAAALgAECgEJAQAAAA==.Mazzarzul:BAABLgAECn8YAAMKAAcJURwrIQAbAgAKAAcJURwrIQAbAgAXAAEJIQe9jwAoAAABLgAFFAQJDwAWAIYRAA==.',
Me='Meebles:BAABLgAECn8+AAISAAkJUxSxDADcAQASAAkJUxSxDADcAQAAAA==.Meiana:BAACLgAFFH8FAAIHAAIJZAczRAB5AAAHAAIJZAczRAB5AAAuAAQKfyQAAgcACQkrFioWAAcCAAcACQkrFioWAAcCAAAA.Mekanismz:BAAALgADCgkJCQABLgAFFAMJCgAlAKAeAA==.Melanthia:BAAALgAECgEJAQAAAA==.Melasmus:BAAALgAECgEJAQAAAA==.Mendu:BAAALgADCgcJBwAAAA==.Mes:BAABLgAECn8WAAIpAAkJXiLQAwDrAgApAAkJXiLQAwDrAgAAAA==.Metacarpal:BAAALgAECgkJCQAAAA==.',
Mi='Micklaa:BAABLgAECn8pAAIJAAgJ/Al4egBmAQAJAAgJ/Al4egBmAQAAAA==.Mightybelle:BAAALgAECgkJAgAAAA==.Mightychi:BAABLgAECn8XAAIUAAYJXhd/MwBVAQAUAAYJXhd/MwBVAQAAAA==.Milan:BAAALgADCgkJCQAAAA==.Milicka:BAAALgADCgkJBwAAAA==.Milkbunny:BAAALgAECgYJBgAAAA==.Millenium:BAAALgAECgQJCgAAAA==.Mimz:BAAALgADCgYJBgAAAA==.Mingtai:BAABLgAECn8cAAIJAAYJgQy0qgAPAQAJAAYJgQy0qgAPAQAAAA==.Mirixa:BAAALgADCgYJBgAAAA==.Mizzakien:BAAALgAECgYJEwAAAA==.',
Mo='Monk:BAACLgAFFH8GAAIOAAMJPBvZFwCwAAAOAAMJPBvZFwCwAAAuAAQKfyEAAg4ABwlGJe8LAFcCAA4ABwlGJe8LAFcCAAEuAAUUBAkMACIAgh4A.Monkyo:BAAALgAECgcJEgAAAA==.Monrea:BAAALgADCgcJFgABLgAECgYJGgAQALIaAA==.Moondolli:BAAALgADCgEJAQAAAA==.Moonriver:BAABLgAECn80AAQKAAkJSwxMWgAfAQAKAAkJSwxMWgAfAQAmAAYJ2A3zFwADAQAXAAQJDQqjWwChAAAAAA==.Moonsinde:BAABLgAECn8fAAIaAAYJXxU6MQAoAQAaAAYJXxU6MQAoAQAAAA==.Moranta:BAABLgAECn8jAAMDAAgJCwNCSwCzAAADAAYJCgRCSwCzAAAEAAQJtANYSwCIAAAAAA==.Moressandra:BAAALgAECgYJDQAAAA==.',
Mu='Muncher:BAAALgAECgMJAwAAAA==.Munchiss:BAAALgADCgEJAQABLgAECggJGgAIAC0hAA==.Murathiel:BAAALgAECgQJCQABLgAFFAYJGgAUAKceAA==.Murdermass:BAAALgADCgkJEwAAAA==.Mushy:BAAALgAECgEJAQAAAA==.Musthdruid:BAAALgAECgYJBgAAAA==.',
My='Mycoxinyou:BAAALgADCgQJBAAAAA==.Mydruid:BAAALgAECgQJBAABLgAFFAIJAwAVAAAAAA==.Myke:BAAALgAECgEJAQAAAA==.Mykellcat:BAABLgAECn8cAAMbAAgJFyWJBABaAwAbAAgJFyWJBABaAwAaAAUJzxwrLgA5AQAAAA==.Myrogue:BAAALgAFFAIJAwAAAA==.Mysticarc:BAAALgAECggJEgAAAA==.Mystichorn:BAAALgAECgEJAQAAAA==.Mysticmurv:BAACLgAFFH8HAAIpAAMJBw0gEgDVAAApAAMJBw0gEgDVAAAuAAQKfxoAAikACAmAHLsQAFwCACkACAmAHLsQAFwCAAAA.Myvirdaeth:BAAALgADCgEJAQAAAA==.',
Na='Naeni:BAAALgAECgEJAgAAAA==.Nahli:BAAALgAECgkJEgAAAA==.Nakkarn:BAAALgADCgQJBAAAAA==.Nalgotica:BAAALgAFFAMJAwAAAA==.Nalynahwe:BAABLgAECn8XAAMbAAcJxhX3UAAoAQAbAAYJjBP3UAAoAQAfAAIJcAgfLABlAAAAAA==.Narima:BAABLgAECn8cAAMGAAcJdwturADwAAAGAAYJDw1urADwAAAiAAUJqwVVOQB/AAAAAA==.Naura:BAAALgADCgEJAQAAAA==.Navirose:BAAALgAECgUJDQAAAA==.',
Ne='Neltheron:BAAALgADCgIJAgAAAA==.',
Nh='Nhala:BAAALgAECgIJAgABLgAECgQJBQAVAAAAAA==.',
Ni='Niavarr:BAAALgADCgYJBgAAAA==.Nickspally:BAAALgADCggJCAABLgAFFAIJBgAfACgQAA==.Nightestrike:BAAALgAECgEJAQAAAA==.Nikodem:BAAALgAECgYJEwAAAA==.Ninali:BAAALgAECgYJCgAAAA==.Ninerva:BAAALgAECgkJEgAAAA==.Nivajh:BAAALgAECgEJAQAAAA==.',
No='Nore:BAABLgAECn8sAAIZAAgJaBipEQAuAgAZAAgJaBipEQAuAgAAAA==.',
Nv='Nvfos:BAAALgADCgUJBQAAAA==.',
Ny='Nyali:BAAALgAECgEJAQABLgAECggJHwAbAEAUAA==.',
['Nà']='Nàdya:BAABLgAECn9LAAQKAAkJqyFsBABLAwAKAAkJqyFsBABLAwAmAAQJOwi1HwCtAAAXAAIJNAOqggA7AAAAAA==.',
['Nî']='Nîghtshade:BAAALgADCgkJCAAAAA==.Nîkodemus:BAAALgADCgYJBgAAAA==.',
Ob='Oblivions:BAACLgAFFH8KAAIlAAMJoB7oIAAAAQAlAAMJoB7oIAAAAQAuAAQKfzQAAyUACQkGJcECACwDACUACQkGJcECACwDACMABAltH8AcAEgBAAAA.Oblivionsdk:BAAALgAECggJCwABLgAFFAMJCgAlAKAeAA==.',
Od='Odyfan:BAAALgADCgEJAQAAAA==.',
Of='Ofelia:BAAALgAECgYJDAAAAA==.',
Og='Ogion:BAAALgAECgEJAQAAAA==.',
Om='Omniray:BAABLgAECn8qAAIaAAcJhxjYHAC0AQAaAAcJhxjYHAC0AQAAAA==.Omnitruce:BAAALgAECgMJAwAAAA==.',
On='Onekark:BAAALgAECgQJCAABLgAFFAgJIwAKAL4bAA==.Onirei:BAAALgADCgEJAwAAAA==.',
Op='Ophèlia:BAAALgADCgMJDwAAAA==.',
Or='Orckus:BAAALgAECgYJDQAAAA==.Oreosbunny:BAAALgAECggJDgAAAA==.',
Os='Oshrick:BAAALgAECgEJAQAAAA==.Osvaldr:BAAALgAECgQJBQAAAA==.',
Ot='Otterr:BAAALgAECgQJBAAAAA==.',
Ow='Owil:BAAALgAECggJEgAAAA==.',
Pa='Palamedes:BAAALgAECgEJAQAAAA==.Paledin:BAAALgADCgEJAQAAAA==.Pandaburn:BAABLgAECn8gAAIJAAgJAxooQwD2AQAJAAgJAxooQwD2AQAAAA==.Pandais:BAABLgAECn8VAAIUAAgJcw/SKwCDAQAUAAgJcw/SKwCDAQAAAA==.Paranne:BAABLgAECn8+AAIJAAkJZx1kHACXAgAJAAkJZx1kHACXAgAAAA==.Paroxism:BAABLgAECn8nAAIaAAgJGyQlBwDDAgAaAAgJGyQlBwDDAgAAAA==.Parthurnax:BAABLgAECn8UAAMoAAYJmh1RBwCoAQAoAAYJmh1RBwCoAQAHAAEJVQErawAdAAAAAA==.Patapouf:BAABLgAECn8jAAMZAAcJHSKVEAA8AgAZAAYJBCOVEAA8AgADAAcJsB2eFwDmAQAAAA==.Patrisse:BAAALgADCgMJAwAAAA==.Pauhana:BAAALgAECgMJAwABLgAECggJGwAMAN0NAA==.',
Pe='Peanût:BAACLgAFFH8KAAIbAAMJ3gspNQC9AAAbAAMJ3gspNQC9AAAuAAQKfzwAAhsACQl8HIALAOkCABsACQl8HIALAOkCAAAA.Pesante:BAABLgAECn8zAAIZAAkJERngDQBkAgAZAAkJERngDQBkAgAAAA==.',
Ph='Phaket:BAAALgADCgYJBwAAAA==.Phatums:BAACLgAFFH8YAAMGAAUJMiPcKgByAQAGAAQJMiPcKgByAQAiAAEJAADYPgAAAAAuAAQKfyUAAgYACAnkIoESAA0DAAYACAnkIoESAA0DAAAA.Philippy:BAAALgADCgYJBwAAAA==.',
Pi='Pika:BAABLgAECn8bAAMaAAgJfA9sLABDAQAaAAgJFQtsLABDAQAfAAUJZRDsHQD3AAAAAA==.Pinix:BAAALgAECgMJBwAAAA==.Pinulito:BAAALgADCgMJAwAAAA==.Pippá:BAAALgAECgUJDQAAAA==.',
Po='Polonius:BAAALgAECggJEAAAAA==.',
Pr='Praline:BAAALgADCgEJAQAAAA==.Pranaverde:BAAALgAECgYJDAAAAA==.Prisevide:BAAALgAECgYJEwAAAA==.Priss:BAAALgADCgkJMgAAAA==.',
Pu='Pumpy:BAAALgADCgcJCAAAAA==.',
Py='Pythe:BAABLgAECn8+AAIQAAkJmCLhBgAgAwAQAAkJmCLhBgAgAwAAAA==.',
Qa='Qap:BAABLgAECn8oAAIRAAgJRhfqAgDrAQARAAgJRhfqAgDrAQAAAA==.Qara:BAAALgADCgYJBgAAAA==.',
Qu='Qualnorr:BAABLgAECn8YAAIIAAYJWAmJhgABAQAIAAYJWAmJhgABAQAAAA==.Quelastraaza:BAAALgAECgEJAQAAAA==.Queldraayan:BAAALgAECgUJCQAAAA==.Quelletois:BAAALgADCgkJCQABLgAECgUJCQAVAAAAAA==.Quipaulm:BAAALgADCgkJCQABLgAFFAQJEQAbAIwWAA==.Quixediah:BAACLgAFFH8RAAIbAAQJjBbZHgAtAQAbAAQJjBbZHgAtAQAuAAQKfyMAAxsACAn0IZAJAPkCABsACAn0IZAJAPkCABoABAlXGCQyACIBAAAA.Quixhea:BAABLgAECn8bAAICAAcJySEJDgCNAgACAAcJySEJDgCNAgABLgAFFAQJEQAbAIwWAA==.Quixxie:BAAALgADCggJDgABLgAFFAQJEQAbAIwWAA==.Quixxum:BAAALgAECgEJAQABLgAFFAQJEQAbAIwWAA==.',
Ra='Radalas:BAABLgAECn8bAAIhAAgJJB6YBgBQAgAhAAgJJB6YBgBQAgAAAA==.Radreliris:BAABLgAECn8UAAIDAAgJ5w7hKABgAQADAAgJ5w7hKABgAQAAAA==.Raelis:BAAALgADCggJCAABLgAECgkJOwAGAMcjAA==.Rahdalas:BAAALgADCgEJAQABLgAECggJGwAhACQeAA==.Rally:BAAALgAECgYJEwAAAA==.Ramanujan:BAAALgAECgIJAgAAAA==.Ramcco:BAEBLgAECn8lAAIDAAgJ+hnHEQAiAgADAAgJ+hnHEQAiAgAAAA==.Ranelle:BAABLgAECn8+AAIEAAkJ1hb2DgBRAgAEAAkJ1hb2DgBRAgAAAA==.Rasmira:BAABLgAECn8ZAAIpAAYJdRCAKgDvAAApAAYJdRCAKgDvAAAAAA==.Ravenis:BAABLgAECn8uAAITAAgJxyLXBwCIAgATAAgJxyLXBwCIAgAAAA==.Razekial:BAAALgAECgYJCQAAAA==.Razelikh:BAAALgAECgEJAQAAAA==.',
Re='Reedem:BAABLgAECn8fAAIMAAcJ0AtiMwAMAQAMAAcJ0AtiMwAMAQAAAA==.Regilock:BAACLgAFFH8iAAQBAAgJXxsmAgAVAgABAAcJWx4mAgAVAgAcAAQJzxFgBgD8AAAdAAEJUwwsBgBTAAAuAAQKfykABAEACQmNJdQIADoDAAEACQlZJdQIADoDABwABAnsHg8iAEUBAB0AAQkAAO4jAGIAAAAA.Regilocklr:BAAALgAFFAIJAgAAAA==.Reikí:BAABLgAECn8cAAIJAAgJeBEMagCLAQAJAAgJeBEMagCLAQAAAA==.Relarria:BAAALgAECgQJCwAAAA==.Renbe:BAAALgADCgYJCQAAAA==.Renwald:BAABLgAECn8UAAMQAAYJdxF3kwBWAQAQAAYJdxF3kwBWAQAhAAMJ0Ao4NAB3AAAAAA==.Revgard:BAAALgAECgYJEQAAAA==.',
Rh='Rhasalgul:BAAALgAECgMJCwAAAA==.',
Ri='Ricearoniog:BAAALgAECgEJAQAAAA==.Risingull:BAAALgAECgUJBgAAAA==.',
Ro='Rolhen:BAAALgAECgYJEAAAAA==.Ronso:BAAALgADCgQJBAAAAA==.Ronta:BAAALgADCgYJCgAAAA==.Rowain:BAAALgADCgkJGQAAAA==.',
Ru='Rustyheals:BAAALgADCgkJKgAAAA==.',
Ry='Ryanari:BAAALgAECgcJDAAAAA==.Rylacus:BAABLgAECn8hAAITAAgJwwyjHACHAQATAAgJwwyjHACHAQAAAA==.',
['Rá']='Rápháel:BAAALgAECgQJAQAAAA==.',
['Rê']='Rêgret:BAAALgADCgYJCQAAAA==.',
Sa='Saanda:BAAALgAECgYJEwAAAA==.Sagazboy:BAABLgAECn8eAAIQAAYJtRMRjQA2AQAQAAYJtRMRjQA2AQABLgAECgkJMgAQAOgWAA==.Sagazpally:BAABLgAECn8yAAIQAAkJ6BZCKABAAgAQAAkJ6BZCKABAAgAAAA==.Salandre:BAAALgADCgMJAwAAAA==.Salutations:BAABLgAECn8eAAMHAAkJwSPjBgDVAgAHAAgJhiTjBgDVAgAkAAEJTgPRNQAtAAABLgAFFAIJAwAVAAAAAA==.Salv:BAAALgADCgIJAgAAAA==.Sandp:BAAALgAFFAEJAQAAAA==.Sapphin:BAAALgAECgIJAgAAAA==.Sarlef:BAABLgAECn8hAAINAAgJuxWLEgCZAQANAAgJuxWLEgCZAQAAAA==.Sashafel:BAAALgADCggJCAAAAA==.',
Sc='Scarm:BAAALgAECgEJAgAAAA==.Schmiddy:BAAALgADCgYJBwAAAA==.Schrutebucks:BAAALgAECgEJAQABLgAFFAIJBQABAPIbAA==.Scyithe:BAAALgADCgYJBgAAAA==.',
Se='Sellidra:BAABLgAECn8oAAIIAAgJsQxuVQB1AQAIAAgJsQxuVQB1AQAAAA==.Sendcatpics:BAABLgAECn8sAAMCAAkJQxDkJgDzAQACAAkJQxDkJgDzAQAQAAUJBBrtgwByAQABLgAFFAIJAwAVAAAAAA==.Seo:BAAALgAFFAIJBAAAAA==.Serenitara:BAAALgADCgYJBgAAAA==.Serharimia:BAAALgAECgEJAQAAAA==.Sethia:BAAALgADCgQJBAABLgADCgUJBQAVAAAAAA==.Sevotarthe:BAAALgADCgUJBQAAAA==.Seyana:BAABLgAECn8aAAIIAAYJ8BgsXQBgAQAIAAYJ8BgsXQBgAQAAAA==.',
Sh='Shaaddow:BAAALgAECgYJBwAAAA==.Shadowkaos:BAAALgAECgUJCAAAAA==.Shaffer:BAABLgAECn8bAAMQAAgJLQwmcABuAQAQAAgJLQwmcABuAQACAAYJigyxQgANAQAAAA==.Shellmage:BAAALgAECgYJDAAAAA==.Shellshocker:BAACLgAFFH8HAAIXAAMJPSANDAApAQAXAAMJPSANDAApAQAuAAQKfyEAAhcACQn1JYkCADIDABcACQn1JYkCADIDAAAA.Shermantånk:BAAALgAECgQJBQAAAA==.Sheydon:BAAALgADCgQJBAAAAA==.Shiftstain:BAAALgADCgIJAgAAAA==.Shikï:BAACLgAFFH8JAAIDAAMJIiHRFQAcAQADAAMJIiHRFQAcAQAuAAQKfysAAgMACQlzJRUBAGsDAAMACQlzJRUBAGsDAAAA.Shivermoón:BAABLgAECn8pAAIbAAkJshLiJAACAgAbAAkJshLiJAACAgAAAA==.Shobek:BAAALgAECgYJBgAAAA==.Shortie:BAAALgADCgYJBgAAAA==.',
Si='Sigesar:BAABLgAECn8rAAIEAAkJaAfuKQBUAQAEAAkJaAfuKQBUAQAAAA==.Sigrún:BAAALgAECgYJBAAAAA==.Silvaria:BAAALgAECgMJBAAAAA==.Simina:BAAALgAECgEJAQAAAA==.Simpforsouls:BAABLgAECn8bAAIBAAcJZhpTOwDUAQABAAcJZhpTOwDUAQAAAA==.Simura:BAAALgAFFAEJAgAAAA==.Sinamara:BAAALgADCgkJGgAAAA==.Sinsimella:BAAALgAECgUJDAAAAA==.Sinõn:BAABLgAECn8cAAMWAAgJWR7OCAB3AgAWAAgJWR7OCAB3AgAIAAEJLwUK1AAyAAAAAA==.',
Sk='Skyliner:BAAALgAECgQJBQAAAA==.Skyskitty:BAAALgAECgYJCwAAAA==.Skywatcher:BAABLgAECn8rAAIIAAgJYQllYQBVAQAIAAgJYQllYQBVAQAAAA==.',
Sl='Slaughtering:BAAALgAECgYJEQAAAA==.',
Sm='Smesus:BAAALgAECgEJAQAAAA==.Smitemare:BAAALgAECgYJDQAAAA==.',
Sn='Sn:BAAALgAECgUJBQAAAA==.',
So='Sohka:BAAALgADCgYJBwAAAA==.Solare:BAAALgADCggJHgAAAA==.Solianti:BAAALgADCgYJBgAAAA==.Solodan:BAAALgAECgYJEQABLgAECggJJwAaALwbAA==.Solodane:BAAALgAECgcJEgABLgAECggJJwAaALwbAA==.Sonnwar:BAABLgAECn8hAAICAAgJixuhLADTAQACAAgJixuhLADTAQAAAA==.',
Sp='Spinsocket:BAAALgADCgkJCQAAAA==.Spliphtoker:BAAALgAECgQJDgAAAA==.Spookytotems:BAACLgAFFH8FAAImAAMJyAmTCQDSAAAmAAMJyAmTCQDSAAAuAAQKfyQAAiYACAmEFNsNAJwBACYACAmEFNsNAJwBAAAA.',
St='Stenston:BAAALgAECgcJDwAAAA==.Sterede:BAAALgAECgYJEAAAAA==.Stolensouls:BAAALgADCgQJBAAAAA==.Stonehenge:BAABLgAECn8iAAMQAAgJzAt/cgBpAQAQAAgJzAt/cgBpAQAhAAQJpQLFNwBWAAAAAA==.Stormb:BAAALgADCgkJIQAAAA==.Stormwolves:BAAALgAECgYJCAAAAA==.',
Sy='Sylphr:BAAALgAECgQJCwAAAA==.Sylphwild:BAAALgAECgIJAgABLgAFFAMJAwAVAAAAAA==.Sylvanase:BAAALgAECgcJCgAAAA==.Sylvara:BAAALgAECgEJAQAAAA==.Synapze:BAABLgAECn8sAAIJAAgJ0RRrUwDFAQAJAAgJ0RRrUwDFAQAAAA==.Syreite:BAABLgAECn8vAAISAAgJeBxLCAAxAgASAAgJeBxLCAAxAgAAAA==.Syreyna:BAAALgADCgIJAwAAAA==.',
Ta='Taessa:BAABLgAECn8VAAIpAAYJDhF0JwADAQApAAYJDhF0JwADAQAAAA==.Tahwye:BAAALgADCgkJOQAAAA==.Tainipuni:BAABLgAECn8bAAMEAAcJVgtNNgACAQAEAAYJxwxNNgACAQADAAUJqQbdTACrAAAAAA==.Takemi:BAAALgAECggJEQAAAA==.Tal:BAAALgAECggJCQABLgAFFAMJCgAhAFEUAA==.Tallac:BAAALgADCgYJBgABLgAFFAMJCgAhAFEUAA==.Tallaric:BAAALgAECgQJCAABLgAFFAMJCgAhAFEUAA==.Tallic:BAACLgAFFH8KAAIhAAMJURTRBwDNAAAhAAMJURTRBwDNAAAuAAQKfzIAAiEACQkRGXcJAAkCACEACQkRGXcJAAkCAAAA.Tamarah:BAABLgAECn8UAAIQAAYJewtzsgD5AAAQAAYJewtzsgD5AAAAAA==.Tamzyyn:BAABLgAECn8bAAIBAAgJHwUbkQADAQABAAgJHwUbkQADAQAAAA==.Tandemonium:BAAALgAECgEJAQABLgAFFAYJDwApAK8fAA==.Taniz:BAACLgAFFH8GAAMPAAIJwhDwGgCQAAAIAAIJXRC3XgCUAAAPAAIJCQzwGgCQAAAuAAQKfxcAAwgACAn6GgsZAHICAAgACAnqGgsZAHICAA8AAwn1DbF2AGQAAAAA.Tankfu:BAAALgAECgYJEwAAAA==.Tarsi:BAAALgAECgcJEwAAAA==.Tashoonne:BAAALgADCgYJCAAAAA==.Taylin:BAAALgAECgIJAgABLgAECgUJDAAVAAAAAA==.',
Te='Teareagana:BAAALgAECgYJCgABLgAFFAEJAQAVAAAAAA==.Tearinurside:BAAALgAECgYJEwAAAA==.Teddy:BAAALgADCgUJBQABLgAFFAMJCQAUACAcAA==.Telchar:BAABLgAECn8YAAIXAAcJbxAINAA7AQAXAAcJbxAINAA7AQAAAA==.Telidrel:BAAALgADCgMJAwAAAA==.Telrienn:BAAALgADCgIJAgAAAA==.Teratin:BAABLgAECn8gAAIOAAgJsyCGDQBAAgAOAAgJsyCGDQBAAgAAAA==.Tevellan:BAAALgADCgYJBwAAAA==.',
Th='Thaddeaus:BAACLgAFFH8GAAINAAIJvRYRGgCXAAANAAIJvRYRGgCXAAAuAAQKfxkAAg0ACAkMGR0NADoCAA0ACAkMGR0NADoCAAAA.Thaddeus:BAABLgAECn8rAAIQAAkJHRuYIABlAgAQAAkJHRuYIABlAgAAAA==.Thauris:BAAALgAECgEJBQAAAA==.Thealin:BAAALgAECgYJDQAAAA==.Thebeefyone:BAABLgAECn8WAAIJAAYJFhMAlwAwAQAJAAYJFhMAlwAwAQAAAA==.Thelesar:BAAALgADCgYJCAAAAA==.Therizin:BAAALgAECgYJEgAAAA==.Thesummoner:BAACLgAFFH8FAAIBAAIJ8husegCbAAABAAIJ8husegCbAAAuAAQKfxcAAwEACAkmINATAN4CAAEACAkmINATAN4CABwAAQnHFWBrADwAAAAA.Thicciana:BAABLgAFFH8KAAIOAAQJYx0aEwBRAQAOAAQJYx0aEwBRAQAAAA==.Thighs:BAAALgAECgYJCwAAAA==.Thorizan:BAAALgAECgQJBwAAAA==.Thugnificent:BAAALgADCgcJCgAAAA==.Thumpette:BAAALgADCgMJAwAAAA==.Thuviel:BAAALgAECgIJBAAAAA==.Thè:BAAALgAECgYJCwAAAA==.',
Ti='Tierant:BAAALgAECgYJCAAAAA==.Tituz:BAAALgADCgMJBAAAAA==.Tizaria:BAABLgAECn8lAAIEAAgJuhSeGQDWAQAEAAgJuhSeGQDWAQAAAA==.',
Tm='Tmai:BAAALgAECgYJEwAAAA==.',
To='Tolken:BAAALgAECgEJAQAAAA==.Tominaetor:BAABLgAECn8pAAIBAAYJthBSewAtAQABAAYJthBSewAtAQAAAA==.Tosoto:BAABLgAECn82AAMjAAkJ3x4DBQCbAgAjAAkJQh4DBQCbAgAlAAgJIhtdHADmAQAAAA==.Toxerus:BAAALgAECgMJBAAAAA==.',
Tr='Trixifox:BAAALgADCgUJBQABLgAECgYJEwAVAAAAAA==.Trixigossa:BAAALgADCggJEgABLgAECgYJEwAVAAAAAA==.Trobbio:BAAALgADCgIJAgAAAA==.',
Ts='Tso:BAACLgAFFH8HAAIUAAMJQhQLJgDEAAAUAAMJQhQLJgDEAAAuAAQKfyEAAxQACQnAFykWACwCABQACAnzGCkWACwCAAwABQmbD4RBAM0AAAAA.Tsukuyomï:BAAALgAECgMJBwABLgAFFAMJCQADACIhAA==.',
Tu='Tuskmunkey:BAAALgAECgUJDAAAAA==.',
Ty='Tyernan:BAABLgAECn86AAMCAAkJ1ws9JAC+AQACAAkJ1ws9JAC+AQAQAAIJyAQxJwFRAAAAAA==.Tyka:BAAALgADCgkJDwABLgAECggJGwAMAN0NAA==.Tym:BAAALgADCgkJDAAAAA==.Tyrael:BAABLgAECn87AAIQAAkJ2A4ZSQDMAQAQAAkJ2A4ZSQDMAQAAAA==.Tyreanna:BAAALgAECgQJBwAAAA==.Tyrioz:BAABLgAECn8gAAMCAAgJ7hEKQQAVAQACAAcJXQ8KQQAVAQAQAAQJIRBMFQFqAAAAAA==.',
Tz='Tzavcat:BAABLgAECn8dAAIbAAYJGwiTcADCAAAbAAYJGwiTcADCAAAAAA==.',
Ul='Uluhn:BAAALgADCggJDgABLgAECgQJBQAVAAAAAA==.',
Ur='Urklesnurkle:BAAALgAECggJDwAAAA==.',
Ut='Utadia:BAAALgAECgMJBAABLgAECgcJCgAVAAAAAA==.',
Uv='Uvsol:BAABLgAECn8UAAMbAAYJZxRARQBXAQAbAAYJZxRARQBXAQAaAAMJvwt9VgCEAAAAAA==.',
Va='Vadailla:BAAALgAECgYJBgABLgAECggJGwAMAN0NAA==.Vahrik:BAAALgAECgEJAQAAAA==.Valcane:BAAALgADCgkJEgAAAA==.Valdictorian:BAAALgAECgEJAQAAAA==.Valius:BAABLgAECn8jAAIoAAgJVyHuAQCcAgAoAAgJVyHuAQCcAgAAAA==.Vallarium:BAAALgADCggJHwAAAA==.Valornor:BAAALgAECgYJDQAAAA==.Valyerian:BAAALgAECgUJBgAAAA==.Vanacarde:BAAALgAECggJEAAAAA==.Vandilious:BAABLgAECn8XAAIhAAcJJQuGHQD6AAAhAAcJJQuGHQD6AAABLgAECggJHgAJAIcRAA==.Vandill:BAABLgAECn8eAAIJAAgJhxHYXgCmAQAJAAgJhxHYXgCmAQAAAA==.Vandyll:BAAALgADCgEJAgAAAA==.Vaneadra:BAAALgADCgcJDQAAAA==.Vaquitamuu:BAAALgAECgUJBQAAAA==.Vaxis:BAAALgADCgcJCwAAAA==.',
Ve='Veasnacool:BAAALgAFFAIJBAAAAA==.Velanlan:BAAALgADCgUJCQAAAA==.Velion:BAAALgADCgYJBgABLgAFFAMJCgAHAM0IAA==.Vestrit:BAAALgAECgIJAgAAAA==.',
Vh='Vhesper:BAAALgAECgQJBwAAAA==.',
Vi='Vii:BAABLgAECn8WAAIpAAgJ4wioIwAfAQApAAgJ4wioIwAfAQAAAA==.Vivacia:BAAALgAECgQJBAAAAA==.',
Vo='Voidfisting:BAABLgAECn8tAAMUAAgJ/AclNAAiAQAUAAgJ/AclNAAiAQAMAAcJhQvXNAAFAQAAAA==.Volfurion:BAAALgADCgQJBAAAAA==.Volthuun:BAAALgADCgIJBAAAAA==.Vontote:BAABLgAECn8bAAIiAAgJHSDDCABhAgAiAAgJHSDDCABhAgAAAA==.Vorix:BAAALgAECgYJEgAAAA==.Vorrel:BAAALgADCgkJFwABLgAFFAMJCgAHAM0IAA==.',
Vu='Vulzin:BAAALgAECgMJAwAAAA==.Vunak:BAAALgADCgcJDQAAAA==.',
['Ví']='Víc:BAABLgAECn8oAAICAAgJUCJKBgAJAwACAAgJUCJKBgAJAwAAAA==.',
Wa='Wandorf:BAEBLgAECn8rAAIGAAkJJBDaQQDbAQAGAAkJJBDaQQDbAQAAAA==.Warbacon:BAAALgADCgMJAwAAAA==.Wargyle:BAABLgAECn8pAAMBAAkJGBTbKwASAgABAAkJGBTbKwASAgAcAAEJAADMcAA1AAAAAA==.Warsmith:BAAALgAECgYJBgAAAA==.Warwolfe:BAABLgAECn88AAMBAAkJQguRTgCYAQABAAkJ9QqRTgCYAQAdAAUJ+QfyFgDIAAAAAA==.Wayler:BAAALgAECgIJAgAAAA==.',
We='Wealthywolf:BAABLgAECn8WAAMWAAcJwwcBGwAjAQAWAAcJwwcBGwAjAQAPAAEJwgBxmwATAAAAAA==.Werepinguin:BAAALgADCgMJAwAAAA==.',
Wh='Whitewicca:BAAALgADCgQJBAAAAA==.',
Wi='Wilbrew:BAAALgAECgEJAgABLgAECggJEgAVAAAAAA==.Wistful:BAABLgAECn8VAAIJAAgJVw18bQCDAQAJAAgJVw18bQCDAQAAAA==.',
Wl='Wlitia:BAAALgAECgYJCgAAAA==.',
Wo='Wolferunner:BAABLgAECn8lAAIIAAgJqwtqUwB6AQAIAAgJqwtqUwB6AQAAAA==.Woolk:BAAALgADCgkJCAAAAA==.',
Wr='Wrathome:BAABLgAECn8cAAMBAAcJgxqyQAALAgABAAcJgxqyQAALAgAcAAMJtgrURgCbAAAAAA==.Wráth:BAAALgADCggJCAAAAA==.',
Xa='Xalatäth:BAAALgAECgMJBAAAAA==.Xaldora:BAAALgAECgEJAgAAAA==.Xandrake:BAAALgAECgYJDAABLgAFFAcJGQAHAKccAA==.Xanolor:BAAALgADCgUJBQABLgAFFAIJBQAHAGQHAA==.',
Xd='Xdxvuu:BAABLgAECn8VAAMCAAcJmCCUGgAJAgACAAYJbCCUGgAJAgAQAAQJ/hIE3AC8AAAAAA==.',
Xe='Xerimok:BAABLgAECn8cAAIkAAgJEAfaFwAuAQAkAAgJEAfaFwAuAQAAAA==.',
Xi='Xinya:BAABLgAECn8bAAIGAAcJ+RVZYwB9AQAGAAcJ+RVZYwB9AQAAAA==.Xipa:BAACLgAFFH8KAAIPAAMJ6hKzEwDjAAAPAAMJ6hKzEwDjAAAuAAQKfzcAAw8ACQkKH5IDAG4CAA8ACAmlIJIDAG4CAAgAAQnQExjhAEsAAAAA.',
Xl='Xladykahlron:BAAALgADCgYJCAAAAA==.Xly:BAAALgAECgEJAQAAAA==.',
Xo='Xolara:BAAALgAECgIJBAAAAA==.',
Xs='Xsavior:BAAALgAECgYJEwAAAA==.Xshan:BAAALgAECgEJBAAAAA==.Xshando:BAAALgAECgQJCwAAAA==.',
Xy='Xyi:BAAALgAECggJEwAAAA==.',
Xz='Xzephyr:BAABLgAECn8tAAIaAAkJJCLVBADzAgAaAAkJJCLVBADzAgAAAA==.',
Ya='Yamato:BAABLgAECn8tAAINAAkJGQd9HAAoAQANAAkJGQd9HAAoAQAAAA==.Yasnah:BAAALgAECgYJBgAAAA==.',
Ye='Yesmín:BAAALgAECgcJDwAAAA==.',
Yo='Youwas:BAAALgAECgcJCgAAAA==.Yoveladari:BAAALgADCgIJAgAAAA==.',
Yu='Yukimenoko:BAABLgAECn8UAAILAAgJvhvuLgDrAQALAAgJvhvuLgDrAQAAAA==.Yukmouf:BAACLgAFFH8FAAIQAAIJ5R3zXwCtAAAQAAIJ5R3zXwCtAAAuAAQKfxUAAhAACAnaG2gjAJsCABAACAnaG2gjAJsCAAAA.',
Za='Zabrak:BAAALgAECgYJEAAAAA==.Zacharaius:BAAALgAECgYJBgAAAA==.Zakaris:BAAALgAECgYJEQAAAA==.Zalaeran:BAAALgADCgEJAQAAAA==.Zalatath:BAAALgADCgkJHgAAAA==.Zanbu:BAAALgAECgQJAgAAAA==.Zarrov:BAAALgADCgkJGgAAAA==.Zarrove:BAACLgAFFH8IAAIMAAMJuxymEQAOAQAMAAMJuxymEQAOAQAuAAQKfz4AAgwACQlYJAYCAEEDAAwACQlYJAYCAEEDAAAA.',
Ze='Zea:BAAALgAECgQJBwAAAA==.Zedael:BAABLgAECn8gAAIiAAgJaxfSGABpAQAiAAgJaxfSGABpAQAAAA==.Zeltri:BAAALgAECgQJCwAAAA==.Zephyran:BAAALgAECgIJAgAAAA==.Zeritha:BAAALgAECgQJBgAAAA==.Zerref:BAAALgAECgQJBAABLgAECggJIQANALsVAA==.',
Zh='Zhatva:BAABLgAECn8aAAIIAAgJLSGRIgAvAgAIAAgJLSGRIgAvAgAAAA==.Zhöe:BAABLgAECn8XAAMKAAkJXh47DQCyAgAKAAgJtR07DQCyAgAXAAkJyxyHOQAgAQAAAA==.',
Zo='Zoldor:BAABLgAECn8oAAMBAAgJeRNHSACrAQABAAcJdxNHSACrAQAcAAIJWA+9NAAzAAAAAA==.Zoleia:BAAALgADCgIJAwAAAA==.Zoral:BAAALgADCgUJBQAAAA==.Zore:BAAALgADCgYJBgAAAA==.',
Zu='Zuldokah:BAAALgADCgEJAQAAAA==.',
Zy='Zy:BAABLgAFFH8FAAIIAAMJHRebPwDtAAAIAAMJHRebPwDtAAAAAA==.Zycorr:BAABLgAECn8UAAIJAAYJQAID7QCgAAAJAAYJQAID7QCgAAAAAA==.Zyheal:BAAALgAECggJEwAAAA==.Zymor:BAAALgAECgYJDQAAAA==.Zytrex:BAABLgAECn8XAAIcAAYJjwenGQC3AAAcAAYJjwenGQC3AAAAAA==.',
['Äm']='Ämaterasu:BAAALgAECgIJAgABLgAFFAMJCQADACIhAA==.',
['Ða']='Ðaniel:BAAALgAECgYJDQAAAA==.',
['Ðr']='Ðraevus:BAAALgAECgQJDAAAAA==.',
['Ñÿ']='Ñÿx:BAABLgAECn8cAAIBAAgJlQGO1QCEAAABAAgJlQGO1QCEAAAAAA==.',
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
