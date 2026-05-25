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

local lookup = {'Mage-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','Paladin-Holy','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Devourer','Monk-Brewmaster','Warrior-Arms','DeathKnight-Blood','Rogue-Subtlety','DeathKnight-Unholy','Monk-Windwalker','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Restoration','Druid-Guardian','Warrior-Fury','Rogue-Assassination','Shaman-Enhancement','Evoker-Devastation','Shaman-Elemental','Warrior-Protection','Druid-Balance','Priest-Holy','Druid-Feral','Shaman-Restoration','Monk-Mistweaver','Priest-Shadow','DemonHunter-Havoc','Mage-Fire','Mage-Arcane','Priest-Discipline','Hunter-Marksmanship',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Aderai:BAAALgADCgYJCgAAAA==.',
Ae='Aeliong:BAAALgAECgEJAQAAAA==.Aendronys:BAAALgADCgQJAwAAAA==.',
Af='Afterparty:BAABLgAECn8bAAIBAAgJYhdkQwD2AQABAAgJYhdkQwD2AQAAAA==.',
Ag='Aguni:BAABLgAECn8dAAQCAAkJvx44DwC7AgACAAkJVB44DwC7AgADAAMJAR6qEQD/AAAEAAIJXRkqHQCUAAABLgAFFAQJCwAFAE0bAA==.',
Ah='Ahmin:BAAALgADCgYJBgAAAA==.',
Ai='Aiura:BAABLgAECn8XAAQGAAcJFAqIOgA2AQAGAAcJFAqIOgA2AQAHAAQJtQOxOABTAAAIAAEJSQIdWwEkAAAAAA==.',
Aj='Ajunlucky:BAACLgAFFH8VAAMJAAQJmBwVHQBPAQAJAAQJmBwVHQBPAQAKAAMJOQwRGADoAAAuAAQKfzgAAwkACQkpIpMLANMCAAkACQkpIpMLANMCAAoABQnoFXwrACMBAAAA.',
Al='Alagondar:BAABLgAECn8dAAIIAAgJHw5NbQB0AQAIAAgJHw5NbQB0AQAAAA==.Alakard:BAABLgAECn8mAAILAAgJyhtzIwAkAgALAAgJyhtzIwAkAgAAAA==.Alberich:BAAALgAECgcJDwAAAA==.Alexari:BAAALgADCgcJCwAAAA==.Alexthejoker:BAAALgADCgQJAwAAAA==.Alody:BAAALgAECgIJAgAAAA==.Althenath:BAAALgADCgMJBAAAAA==.',
Am='Amalica:BAABLgAECn8aAAIBAAUJaiE/ngCaAQABAAUJaiE/ngCaAQAAAA==.Amenadiel:BAAALgAECgcJEQAAAA==.Amuyal:BAAALgADCgYJBgAAAA==.',
An='Anaphylactic:BAAALgAECgYJBQAAAA==.Andrea:BAABLgAECn8fAAIMAAgJMRUVGgC2AQAMAAgJMRUVGgC2AQAAAA==.Andygibbs:BAAALgAECgkJCQAAAA==.Angelline:BAAALgAECgUJDgABLgAFFAMJEAANAOolAA==.Antimagi:BAAALgADCgkJCQAAAA==.',
Ap='Apheelia:BAAALgAECgUJEAAAAA==.Appypie:BAACLgAFFH8KAAIOAAQJUgcfHADIAAAOAAQJUgcfHADIAAAuAAQKfzYAAg4ACQlgE2oSALkBAA4ACQlgE2oSALkBAAAA.',
Ar='Arale:BAAALgAECgEJAQAAAA==.Aramala:BAAALgAECgIJAwAAAA==.Arkveld:BAACLgAFFH8IAAIPAAQJrx8UDQBuAQAPAAQJrx8UDQBuAQAuAAQKfzIAAg8ACAlfJUoGAKgCAA8ACAlfJUoGAKgCAAAA.Arthasia:BAABLgAFFH8GAAIQAAMJXSPKQgA/AQAQAAMJXSPKQgA/AQABLgAFFAgJJgAEAM0mAA==.',
As='Asten:BAAALgAECgUJBgAAAA==.',
At='Athair:BAABLgAECn8nAAIRAAgJIxwoDgA9AgARAAgJIxwoDgA9AgAAAA==.Athineana:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgUJBQABLgAFFAIJAwASAAAAAA==.Aulken:BAAALgADCgEJAQAAAA==.',
Ay='Aylinn:BAABLgAECn8iAAMTAAkJaRzqBACwAgATAAkJaRzqBACwAgAUAAEJVQYkhwAjAAAAAA==.Aylira:BAAALgAECgQJCAAAAA==.Aymonzo:BAABLgAECn8gAAMLAAkJyRY2PQCyAQALAAkJyRY2PQCyAQAVAAEJFBSyKQA4AAAAAA==.',
Az='Azem:BAAALgADCgkJDAAAAA==.',
Ba='Badlóck:BAAALgAECgcJBgAAAA==.Baharrar:BAACLgAFFH8TAAIWAAQJwh/qFQByAQAWAAQJwh/qFQByAQAuAAQKfysAAxYACQkZIvIJAPUCABYACQkZIvIJAPUCABcAAQn9EqBQADgAAAAA.Ballidur:BAAALgAECgMJBQABLgAECgkJDwASAAAAAA==.Barofslovr:BAAALgADCgcJBwABLgAECgcJFwAIAFwdAA==.Barrylowmana:BAAALgADCgcJBwAAAA==.Bartendresse:BAAALgAECgEJAQAAAA==.Bassault:BAAALgADCgYJBgAAAA==.Bastrasz:BAAALgAECgcJCwAAAA==.Batar:BAAALgADCgYJBgAAAA==.',
Be='Bearalas:BAACLgAFFH8OAAICAAUJ+RSVRAAbAQACAAUJ+RSVRAAbAQAuAAQKfxUAAgIACQmqG/YYAL8CAAIACQmqG/YYAL8CAAAA.Bearis:BAAALgADCgMJAwAAAA==.Beekin:BAAALgAECgUJCwAAAA==.Beeyah:BAABLgAECn8jAAIJAAgJUyHkHABPAgAJAAgJUyHkHABPAgAAAA==.Beldion:BAAALgAECgEJAQABLgAECgcJKAAMAMYXAA==.Bellator:BAAALgADCgMJAwAAAA==.Bellona:BAAALgADCgQJBAAAAA==.Bernarnold:BAABLgAECn8cAAIYAAcJ3B74IADDAQAYAAcJ3B74IADDAQAAAA==.Bettyspready:BAABLgAECn8YAAIZAAgJLw9CCQCKAQAZAAgJLw9CCQCKAQAAAA==.',
Bi='Bigmanooshki:BAAALgADCgcJCwAAAA==.Bigoysters:BAAALgAFFAEJAQAAAA==.Bigpoppapump:BAABLgAECn8kAAIaAAgJ8iRnAgDXAgAaAAgJ8iRnAgDXAgAAAA==.Bigthumbb:BAAALgAECgEJAQAAAA==.Bigvikingg:BAAALgAECgcJBQAAAA==.Bikook:BAAALgADCgIJAgABLgAFFAIJBQATADEDAA==.Binnyi:BAABLgAECn8vAAMbAAkJgQ/4BQDSAQAbAAkJgQ/4BQDSAQAUAAYJogbuPAD6AAAAAA==.Biwwy:BAAALgAECgEJAQAAAA==.',
Bl='Blabidil:BAAALgADCgQJBAAAAA==.Blackfoot:BAABLgAECn8XAAIcAAkJpRVTIgClAQAcAAkJpRVTIgClAQAAAA==.Blackyeshua:BAACLgAFFH8VAAIUAAUJvRaaHAAtAQAUAAUJvRaaHAAtAQAuAAQKfzQAAhQACQlDH9UMAHICABQACQlDH9UMAHICAAAA.Blastphemy:BAAALgADCgYJBgAAAA==.Blindpov:BAAALgADCggJCQAAAA==.Blâckwolf:BAAALgADCgUJBQAAAA==.',
Bo='Boanhead:BAAALgADCgIJAgAAAA==.Bogorline:BAAALgAECggJDQAAAA==.Boomtiloom:BAAALgAECgYJDAAAAA==.Borgastraz:BAABLgAECn8VAAQbAAYJhA9fEQDRAAAbAAUJzQ1fEQDRAAAUAAQJDgztRwC6AAATAAIJEAwTLABfAAAAAA==.Boru:BAAALgADCgcJBwAAAA==.Boshin:BAAALgAECgEJAQAAAA==.Boshintime:BAAALgAECgMJAwAAAA==.Bouberry:BAABLgAECn8XAAIDAAYJWx5DFQCgAQADAAYJWx5DFQCgAQAAAA==.',
Br='Brewstoes:BAAALgADCgQJBQAAAA==.Bricksquadx:BAAALgAECgMJBQAAAA==.Brink:BAAALgADCgMJAwAAAA==.Broki:BAAALgAECgEJAgAAAA==.Brugnir:BAAALgAECgYJBgABLgAECgUJBwASAAAAAA==.Bruwen:BAAALgAFFAIJAwAAAA==.',
Bu='Bubblegruff:BAAALgADCgkJIgAAAA==.Bubbleohsevn:BAABLgAECn8eAAIIAAcJoxNnbgBxAQAIAAcJoxNnbgBxAQAAAA==.Bubblesaurus:BAABLgAECn8vAAMUAAgJGhlcGgDjAQAUAAgJZhhcGgDjAQAbAAYJrg96IQAgAQAAAA==.Bum:BAAALgADCgkJCQAAAA==.Burlan:BAAALgAECgYJEgAAAA==.',
['Bé']='Béåst:BAAALgAECgYJDwAAAA==.',
['Bë']='Bërshton:BAAALgAECgYJCAAAAA==.',
Ca='Cakeshake:BAABLgAECn8cAAIJAAgJoxJMSACcAQAJAAgJoxJMSACcAQAAAA==.Caleris:BAABLgAECn8kAAIdAAkJERqfCgAiAgAdAAkJERqfCgAiAgAAAA==.Camelnuckle:BAABLgAECn8kAAIcAAkJphWwIQCqAQAcAAkJphWwIQCqAQAAAA==.Car:BAAALgADCgIJAgAAAA==.Cattle:BAABLgAECn8kAAIeAAkJyRZ+EAAzAgAeAAkJyRZ+EAAzAgAAAA==.',
Ch='Chaosglaive:BAAALgAECgcJEgAAAA==.Chaostorms:BAABLgAECn8UAAMHAAcJ9gukIADeAAAHAAcJ9gukIADeAAAGAAIJJQKseAA5AAAAAA==.Chess:BAAALgAECgYJCwAAAA==.Chickenhydra:BAAALgADCgYJBgAAAA==.Chlorophil:BAAALgADCgYJBwAAAA==.Choochew:BAAALgAECgEJAgAAAA==.Chowlock:BAACLgAFFH8HAAQEAAMJvSOBDQBkAAACAAIJ9iMPYgDTAAADAAEJkSO8EQBnAAAEAAEJSyOBDQBkAAAuAAQKfykABAMACQl2I9oCANMCAAMABwmeI9oCANMCAAQABglWIsoFAPUBAAIABQkhI81VAIQBAAAA.Chowmantwo:BAAALgADCgEJAQAAAA==.Chronical:BAAALgADCgcJBwAAAA==.',
Cl='Classicmonk:BAAALgAECgQJBQAAAA==.Clawsofpeace:BAAALgADCgkJDQABLgAECggJIQAfAGEOAA==.Cleverboi:BAAALgAECgMJBAAAAA==.',
Co='Coldflesh:BAAALgAECgkJAgAAAA==.Conlord:BAABLgAECn8XAAIQAAYJ5SP5RADRAQAQAAYJ5SP5RADRAQAAAA==.Constancia:BAAALgAECgUJDQAAAA==.',
Cr='Crackahjack:BAAALgAECgEJAQAAAA==.Craigor:BAAALgAECgYJCAABLgAECggJFgAdALEYAA==.Croppydust:BAAALgADCgcJDAAAAA==.Cryden:BAAALgADCgYJCQAAAA==.',
Cy='Cylicmylic:BAAALgAECgQJBAAAAA==.',
Cz='Czark:BAAALgAECgQJBAAAAA==.',
Da='Dalamaar:BAAALgADCgEJAQAAAA==.Dampundies:BAAALgAECgEJAQAAAA==.Dandey:BAAALgAECgYJBwAAAA==.Dangerdoom:BAAALgAECgIJAwABLgAECggJKgABAPAYAA==.Dangerdream:BAAALgAECgcJBwAAAA==.Dantee:BAABLgAECn85AAIVAAkJNB9WAgC5AgAVAAkJNB9WAgC5AgAAAA==.Daps:BAAALgADCgcJCgAAAA==.Darkfoxgrime:BAABLgAECn8kAAIRAAkJeRA/GgCzAQARAAkJeRA/GgCzAQAAAA==.Dartini:BAAALgAECgIJAgAAAA==.Datsmywife:BAABLgAECn8ZAAMgAAcJTRCMEQCVAQAgAAcJTRCMEQCVAQAeAAUJYAXYVQCHAAAAAA==.Davis:BAABLgAECn8iAAIQAAkJBhN8NwD+AQAQAAkJBhN8NwD+AQAAAA==.Dayquill:BAAALgAECgEJAQAAAA==.Daytimes:BAAALgAECgIJAgABLgAECgQJBgASAAAAAA==.Daytknight:BAAALgAECgMJAwAAAA==.',
De='Deadasice:BAAALgADCgkJEgAAAA==.Deadvikingg:BAABLgAFFH8FAAIQAAQJrwRVaQD3AAAQAAQJrwRVaQD3AAAAAA==.Deadwix:BAAALgADCgMJAwAAAA==.Deebss:BAAALgAECggJCwAAAA==.Degradation:BAAALgAECgEJBQAAAA==.Degru:BAAALgAECgYJDgABLgAECgkJGgAMAA0LAA==.Delaire:BAABLgAECn8ZAAIHAAgJAx3BBwAwAgAHAAgJAx3BBwAwAgAAAA==.Demenhunta:BAAALgAECgMJAgAAAA==.Demonkow:BAACLgAFFH8UAAMCAAUJJiH6IwBwAQACAAUJ/yD6IwBwAQAEAAEJCSUSDABrAAAuAAQKfyMAAwIACQlRIswnACMCAAIACAkgIswnACMCAAMABAkPIgcbAHUBAAAA.Dereksama:BAAALgADCgQJBAAAAA==.Destrah:BAAALgADCgUJBQAAAA==.Deviiarrc:BAACLgAFFH8VAAITAAQJLiISDgB+AQATAAQJLiISDgB+AQAuAAQKfysAAhMACQkZJSADADUDABMACQkZJSADADUDAAAA.',
Di='Dikan:BAAALgADCgEJAQAAAA==.Dinosaurman:BAAALgAECgQJBAAAAA==.Disintegrate:BAAALgAECgcJBwABLgAFFAYJHgAUAHMbAA==.',
Do='Doova:BAAALgAECgIJAQAAAA==.Dorik:BAAALgADCgYJBgAAAA==.Doroga:BAAALgAECgEJAQAAAA==.',
Dr='Dracar:BAACLgAFFH8LAAIIAAQJCRYdIwBMAQAIAAQJCRYdIwBMAQAuAAQKfyEAAggACAmYFQZSALQBAAgACAmYFQZSALQBAAAA.Drackian:BAAALgAECgQJBAAAAA==.Dragondyne:BAAALgAECggJCAABLgAFFAQJCgAMAG4WAA==.Drdurun:BAAALgADCgYJBwAAAA==.Drekavak:BAAALgAECgYJCAAAAA==.Drekfur:BAAALgAECgQJBAAAAA==.Drmmrfist:BAABLgAECn8vAAIMAAkJERZ1EwD3AQAMAAkJERZ1EwD3AQAAAA==.Drodolek:BAAALgAECgYJBgAAAA==.Druideca:BAAALgAECgYJDgAAAA==.Druidyne:BAAALgAECgkJCQABLgAFFAQJCgAMAG4WAA==.',
Du='Dustra:BAAALgAECgYJBwAAAA==.',
Dw='Dwippietiggs:BAABLgAECn8vAAIIAAkJwyDNEQC+AgAIAAkJwyDNEQC+AgAAAA==.',
Ea='Earthfeather:BAAALgAECgEJAQAAAA==.',
Ec='Echoesonmute:BAAALgADCgEJAQAAAA==.',
Ed='Edhochuli:BAAALgADCgUJBQABLgAECgcJDQASAAAAAA==.',
Ee='Eetee:BAABLgAECn8uAAQcAAkJ5xKEKwC7AQAcAAgJBhWEKwC7AQAhAAkJ/wxyQwBtAQAaAAQJNQvHHwDVAAAAAA==.',
Ek='Ekitten:BAAALgAECgYJCwABLgAFFAYJDwAiAC4mAA==.',
El='Elandria:BAABLgAECn8XAAIKAAcJsQHSPwCZAAAKAAcJsQHSPwCZAAAAAA==.Elohym:BAAALgADCgUJBQAAAA==.Elsea:BAAALgAECgQJDgAAAA==.',
Em='Emberstone:BAAALgAECgIJAgAAAA==.Emerys:BAAALgAECgYJBgAAAA==.Emotions:BAABLgAECn8bAAILAAgJgRTyPwCoAQALAAgJgRTyPwCoAQAAAA==.',
Ep='Epicdragon:BAABLgAECn8VAAIBAAkJSg3qTwDPAQABAAkJSg3qTwDPAQAAAA==.',
Eq='Equesmortis:BAAALgAECgYJDgAAAA==.',
Er='Erös:BAAALgAECgUJDwAAAA==.',
Et='Etatoned:BAABLgAECn8ZAAMfAAgJlhU2FgD5AQAfAAgJlhU2FgD5AQAjAAUJOAQeVQCFAAAAAA==.Etengaged:BAAALgAECgcJDgAAAA==.Ethavoc:BAAALgAECgMJAwAAAA==.Ethuln:BAAALgAECgEJAQAAAA==.',
Eu='Eurdice:BAAALgADCgIJAgAAAA==.',
Ev='Evo:BAAALgAECgMJAwABLgAECgkJLgABAPYdAA==.Evrae:BAABLgAECn8nAAIPAAgJ3hp2DwARAgAPAAgJ3hp2DwARAgAAAA==.',
Ex='Extragrace:BAABLgAECn8rAAIBAAYJ3AhTtwD6AAABAAYJ3AhTtwD6AAAAAA==.',
Ey='Eyeofjazz:BAAALgAECgkJCQAAAA==.',
Fa='Faithshand:BAABLgAECn8vAAMfAAkJ5QuQJwBlAQAfAAkJ5QuQJwBlAQAjAAUJRgTMSAC+AAAAAA==.Fallenbow:BAAALgAECgYJCgAAAA==.Fappa:BAACLgAFFH8KAAMEAAQJ9gk3AwAvAQAEAAQJ9gk3AwAvAQACAAMJZQLFcgCqAAAuAAQKf0EAAwQACQlxGN4DADcCAAQACQlhFd4DADcCAAIACQngFiErABUCAAAA.',
Fe='Fe:BAAALgAECgUJBgABLgAFFAYJFwAhAIAPAA==.Fearthemoo:BAAALgAECgEJAQABLgAECgcJFwAIAFwdAA==.Featherstone:BAAALgADCgQJBQAAAA==.Feelzdope:BAAALgADCgQJBAAAAA==.Feio:BAABLgAECn8rAAIkAAkJlx/aBgCdAgAkAAkJlx/aBgCdAgAAAA==.Felfirez:BAAALgAECgEJAQAAAA==.Fellhock:BAAALgAECgMJAwAAAA==.Felydrak:BAABLgAECn8aAAQbAAgJ1xSJDQABAgAbAAgJshOJDQABAgAUAAIJagx6ZwBuAAATAAMJowa6KgBoAAAAAA==.Fergilicious:BAABLgAECn8XAAIKAAYJlhWjEgCZAQAKAAYJlhWjEgCZAQABLgAECgcJFwAIAFwdAA==.',
Fi='Finkenator:BAACLgAFFH8XAAIBAAcJHRuLEAAFAgABAAcJHRuLEAAFAgAuAAQKfy0AAgEACQmgI68HAC0DAAEACQmgI68HAC0DAAAA.Finkler:BAACLgAFFH8MAAIBAAQJjRuCPABKAQABAAQJjRuCPABKAQAuAAQKfywAAgEACQnqIsIOAFEDAAEACQnqIsIOAFEDAAEuAAUUBwkXAAEAHRsA.Firedanny:BAAALgAECggJEwAAAA==.',
Fl='Flameshock:BAABLgAECn82AAQlAAkJBRN4AgD5AQAlAAkJwxF4AgD5AQAmAAQJRRAwCADsAAABAAQJdwOaJwGyAAAAAA==.Flippybippi:BAAALgAECgEJAQAAAA==.Flixur:BAACLgAFFH8gAAIBAAUJQBLSSQA0AQABAAUJQBLSSQA0AQAuAAQKfyMAAgEABwn4H29LAN0BAAEABwn4H29LAN0BAAAA.Fluffyduck:BAAALgAECgYJBgAAAA==.Flyzikman:BAAALgADCgEJAQAAAA==.',
Fo='Forestdump:BAAALgADCgYJBgABLgAECgcJDQASAAAAAA==.Forté:BAAALgADCgMJAwAAAA==.',
Fr='Freek:BAAALgAECgEJBAABLgAECgUJBwASAAAAAA==.Freewillie:BAAALgAECgEJAwABLgAECgQJBgASAAAAAA==.Friarmj:BAABLgAECn8wAAInAAkJuQ0vGQDbAQAnAAkJuQ0vGQDbAQAAAA==.Frigidbeach:BAAALgAECgYJDwAAAA==.Frozeny:BAAALgADCgcJDQAAAA==.',
Fu='Furrita:BAAALgADCgcJBwAAAA==.',
Ga='Galazeth:BAABLgAECn8cAAMUAAgJhx6PEwAhAgAUAAgJhx6PEwAhAgAbAAYJMA1XHQBEAQABLgAFFAQJCwAFAE0bAA==.Gamthor:BAABLgAECn8WAAIdAAgJsRggIQA2AQAdAAgJsRggIQA2AQAAAA==.Gaten:BAAALgAECggJDgAAAA==.',
Ge='Germz:BAAALgAECgkJBwAAAA==.',
Gi='Gildeddash:BAABLgAECn8ZAAIIAAgJCAewmAAiAQAIAAgJCAewmAAiAQAAAA==.Giudice:BAAALgAECgIJAgAAAA==.',
Gl='Glengoyne:BAAALgAECgQJDQAAAA==.Globoe:BAACLgAFFH8dAAMbAAkJ5R1FAAD/AQAUAAgJQRoxCAAPAgAbAAUJeyRFAAD/AQAuAAQKfzMAAxsACQksJkIAAMsDABsACQnhJUIAAMsDABQACAmCInsNAJ4CAAAA.Gluggther:BAAALgAECgQJBAAAAA==.',
Go='Goru:BAAALgADCgYJBgAAAA==.',
Gr='Grahz:BAAALgAECgEJAQAAAA==.Gravyboat:BAAALgAECgYJEwAAAA==.Graydawn:BAAALgADCgcJCQAAAA==.Grimwillie:BAAALgAECgQJBgAAAA==.Grismago:BAAALgAFFAEJAQAAAA==.Grizzlebee:BAAALgADCgEJAQAAAA==.',
Gu='Gusto:BAAALgAECgQJBwAAAA==.',
['Gë']='Gënghiskhän:BAAALgADCgUJBQAAAA==.',
Ha='Haakon:BAAALgAECgEJAQAAAA==.Hammertaint:BAAALgAECgkJEgAAAA==.Harrowing:BAABLgAECn9GAAIGAAkJsSPHAQCCAwAGAAkJsSPHAQCCAwAAAA==.Haurt:BAABLgAECn8zAAIeAAkJIhNVGQDUAQAeAAkJIhNVGQDUAQAAAA==.Havoq:BAAALgAECgMJAwAAAA==.',
He='Healamore:BAAALgADCgEJAgAAAA==.Healingway:BAAALgADCgUJBQABLgAECgcJDQASAAAAAA==.Heavyhooves:BAABLgAECn8lAAIYAAgJsxY7GwDvAQAYAAgJsxY7GwDvAQAAAA==.Helawix:BAAALgADCggJEgAAAA==.Hellful:BAABLgAECn8VAAMhAAkJjgoiQAB7AQAhAAkJjgoiQAB7AQAcAAMJxQEvfQBRAAAAAA==.Hellscrèam:BAAALgAECgQJBgAAAA==.Herc:BAAALgAECgEJAQAAAA==.',
Hi='Hischier:BAABLgAECn8hAAMEAAkJaxciBwDkAQAEAAcJVBwiBwDkAQACAAkJmwr5SwCgAQAAAA==.',
Ho='Holyjoey:BAAALgAECgYJDAAAAA==.Holymôley:BAABLgAECn8xAAIhAAkJdCHaBgAcAwAhAAkJdCHaBgAcAwAAAA==.Holytroller:BAAALgAECgUJCAAAAA==.Horgazm:BAAALgADCgEJAQAAAA==.Horrorcosmic:BAAALgADCgEJAQAAAA==.Hotbeeframen:BAAALgADCgEJAQAAAA==.',
Hu='Hulken:BAAALgADCgYJBgAAAA==.Humanpriest:BAAALgADCgEJAQABLgADCgkJCQASAAAAAA==.Hussongs:BAAALgAECgEJAQAAAA==.',
['Hû']='Hûnta:BAAALgADCgQJBAAAAA==.',
Ic='Iceegoose:BAAALgAECgEJAQAAAA==.',
Ie='Ieratha:BAABLgAECn8WAAIaAAYJTRoMDwCGAQAaAAYJTRoMDwCGAQAAAA==.',
Ih='Ihuntyou:BAAALgAECgkJBQAAAA==.',
Il='Illidanina:BAAALgADCgUJBQABLgAFFAgJJgAEAM0mAA==.',
Im='Impossibull:BAAALgADCgcJBwAAAA==.',
In='Invi:BAABLgAECn8jAAMGAAkJAh50EACPAgAGAAkJAh50EACPAgAIAAcJwhXpfACAAQAAAA==.',
Ip='Ipmonk:BAAALgAECgIJAgAAAA==.',
Ir='Ironbull:BAAALgADCgYJBgAAAA==.',
It='Itkøvian:BAAALgAECggJCAAAAA==.',
Ja='Jarrickah:BAAALgAECgQJBAAAAA==.Jaycito:BAAALgAECgYJCwAAAA==.Jayylols:BAAALgAECggJDwAAAA==.',
Je='Jeor:BAABLgAECn8bAAIIAAYJ5wcCwwDgAAAIAAYJ5wcCwwDgAAAAAA==.Jereome:BAAALgAECgYJDQAAAA==.Jezhus:BAAALgADCgkJBgAAAA==.',
Ji='Jigsy:BAABLgAECn8jAAMCAAkJ8CD8DgC9AgACAAgJ8CD8DgC9AgADAAMJBx+KLAAMAQAAAA==.Jigy:BAAALgAECgYJDAAAAA==.Jimmy:BAAALgADCgcJBwAAAA==.',
Jo='Jokerzwild:BAAALgADCgQJBwAAAA==.Jorker:BAABLgAECn8kAAILAAkJPxwRGgC4AgALAAkJPxwRGgC4AgAAAA==.Jovinistus:BAAALgADCgcJDwAAAA==.',
Ju='Judgecutìe:BAABLgAECn8aAAIGAAgJvRmTGwAAAgAGAAgJvRmTGwAAAgAAAA==.Jue:BAAALgAECgEJBQAAAA==.Juiice:BAAALgADCgcJBwAAAA==.',
['Jë']='Jësus:BAAALgAECgcJEAAAAA==.',
Ka='Kaioh:BAAALgAECgEJAQAAAA==.Kalandaelis:BAAALgADCgkJEgAAAA==.Kalei:BAAALgADCgYJBgAAAA==.Kamisama:BAAALgAECgYJCQAAAA==.Kawalskie:BAAALgAECgQJBQAAAA==.Kazraghand:BAABLgAECn82AAIKAAkJzwfHHACYAQAKAAkJzwfHHACYAQAAAA==.',
Ke='Kei:BAACLgAFFH8XAAILAAYJtBHMHwBqAQALAAYJtBHMHwBqAQAuAAQKfzEAAwsACAnRHSQcAE4CAAsACAnRHSQcAE4CACQAAQkYDGRxADMAAAAA.Kelsaru:BAAALgADCgYJBgAAAA==.Kelsio:BAABLgAECn88AAIJAAkJdBGfMwDkAQAJAAkJdBGfMwDkAQAAAA==.Kess:BAAALgAECgcJEgAAAA==.Keyboardcatt:BAABLgAECn8fAAIIAAgJdx3aLQAnAgAIAAgJdx3aLQAnAgAAAA==.',
Kh='Kharos:BAABLgAECn8lAAMfAAgJXwmVOwBNAQAfAAgJ0wWVOwBNAQAnAAgJZAcHNQASAQAAAA==.',
Ki='Kikeo:BAAALgAECggJCgABLgAFFAYJFwALALQRAA==.Killerwarz:BAAALgAECgEJAgAAAA==.Kirkoth:BAAALgAECgIJAwAAAA==.Kitariya:BAAALgADCgIJAgAAAA==.',
Kn='Knuts:BAABLgAECn8dAAMDAAcJawZlOwDGAAACAAcJXAalpgDcAAADAAcJFQJlOwDGAAAAAA==.',
Ko='Kogori:BAAALgAECgUJCgAAAA==.Konsentrated:BAABLgAECn8eAAIBAAYJ2BbIjQBAAQABAAYJ2BbIjQBAAQAAAA==.Kowtagion:BAAALgADCgYJBgABLgAFFAUJFAACACYhAA==.',
Ku='Kungfudegru:BAABLgAECn8aAAMMAAkJDQscIwBzAQAMAAkJBgscIwBzAQARAAUJ7wYTUwCRAAAAAA==.Kurator:BAAALgAECggJCgAAAA==.Kuraven:BAAALgADCgcJBwAAAA==.Kuromo:BAAALgADCgQJCgAAAA==.',
Ky='Kylidan:BAAALgAECgEJAgAAAA==.Kyradin:BAAALgADCgIJAgABLgADCgYJDAASAAAAAA==.Kyruutos:BAABLgAECn8iAAIIAAgJmAjpkgAsAQAIAAgJmAjpkgAsAQAAAA==.Kyvoker:BAAALgAECgQJBgAAAA==.',
['Kí']='Kítkat:BAABLgAECn85AAIhAAkJqhn+FAB2AgAhAAkJqhn+FAB2AgAAAA==.',
La='Lachulax:BAAALgAECgUJCAAAAA==.Lacie:BAAALgAECgMJBwAAAA==.Ladi:BAAALgAECgEJAQABLgAECgQJDgASAAAAAA==.',
Le='Legato:BAAALgAECgEJAwAAAA==.Leibowitzy:BAABLgAECn8oAAMMAAcJxhfZJABnAQAMAAYJ5BjZJABnAQARAAEJMBJMewA4AAAAAA==.Lettucee:BAAALgADCgYJBgAAAA==.Lexstrasza:BAAALgADCgEJAgAAAA==.',
Lh='Lhehitman:BAACLgAFFH8IAAIBAAQJRwy/UAAnAQABAAQJRwy/UAAnAQAuAAQKfzEAAwEACQmlIIIRANkCAAEACQmlIIIRANkCACYAAwmmEy4SAKEAAAAA.',
Li='Lifedeath:BAAALgADCgMJAwAAAA==.Lightsey:BAABLgAECn8WAAMGAAYJVw6hPQAnAQAGAAYJVw6hPQAnAQAIAAEJpQGThwESAAAAAA==.Lilth:BAAALgAECgIJBAABLgAECggJGgAGAL0ZAA==.Limitrx:BAABLgAECn8YAAILAAgJOwhMbwAeAQALAAgJOwhMbwAeAQAAAA==.Lindalamage:BAAALgADCgQJBQAAAA==.Linebreaker:BAABLgAECn8WAAIYAAgJlR6UPgCqAQAYAAgJlR6UPgCqAQAAAA==.Litezamatch:BAAALgADCgIJAgAAAA==.Liveloveslay:BAAALgAECgkJBQAAAA==.',
Lo='Loreena:BAAALgADCgIJAgAAAA==.Lorein:BAAALgAECgQJBQAAAA==.',
Lu='Luckydog:BAAALgAECgQJCAABLgAECgcJDwASAAAAAA==.Ludey:BAABLgAECn9KAAMEAAkJDh6AAgCAAgAEAAkJDh6AAgCAAgACAAEJeQQbLAEqAAAAAA==.Lutnick:BAAALgAECgEJAQAAAA==.Lutray:BAABLgAECn8vAAIdAAkJMiVNAQA/AwAdAAkJMiVNAQA/AwAAAA==.',
Ly='Lysandriloc:BAABLgAECn8jAAQCAAkJPQ+nSACqAQACAAkJNw2nSACqAQADAAUJlwUDOgDMAAAEAAMJERKwHACNAAAAAA==.',
Ma='Madcowdíseaz:BAABLgAECn8pAAIQAAkJWxhyKQA4AgAQAAkJWxhyKQA4AgAAAA==.Madskadoosh:BAAALgADCgEJAQAAAA==.Madtotems:BAAALgAECgcJEgAAAA==.Magnator:BAABLgAFFH8IAAIBAAMJDgQjcwDIAAABAAMJDgQjcwDIAAAAAA==.Malanore:BAABLgAECn8XAAILAAcJ9hMgWQCWAQALAAcJ9hMgWQCWAQAAAA==.Manbeartree:BAAALgAECgIJAgABLgAFFAYJHwAGAE8hAA==.Manbeärpig:BAAALgAECgQJBwAAAA==.Maomao:BAABLgAECn8qAAMfAAkJqBtaEABiAgAfAAkJqBtaEABiAgAnAAEJGxEqYgAzAAAAAA==.Margherita:BAAALgADCgEJAQAAAA==.Marodd:BAABLgAECn8mAAIjAAkJ0h6gCgCDAgAjAAkJ0h6gCgCDAgAAAA==.Mashìra:BAAALgAECgQJBAABLgAFFAQJDAAKAEkZAA==.Mashîra:BAABLgAFFH8MAAIKAAQJSRlaCwBSAQAKAAQJSRlaCwBSAQAAAA==.Matilda:BAAALgAECgEJAQAAAA==.Matylin:BAAALgADCgEJAQAAAA==.Maximus:BAACLgAFFH8JAAIoAAQJqBzqCgBpAQAoAAQJqBzqCgBpAQAuAAQKfyAAAigACQmsIx0BABADACgACQmsIx0BABADAAAA.',
Me='Meanmachine:BAAALgADCgIJAgAAAA==.Meatpocket:BAAALgAECgEJAgAAAA==.Meatwangs:BAABLgAECn8bAAMhAAkJZRj0HwAiAgAhAAkJZRj0HwAiAgAcAAIJXAsMdQBVAAAAAA==.Meleguar:BAAALgADCgIJBAAAAA==.Merihem:BAAALgADCggJDgAAAA==.Merpz:BAAALgADCgYJCwAAAA==.',
Mi='Mia:BAACLgAFFH8HAAILAAUJ1hJ0KwA5AQALAAUJ1hJ0KwA5AQAuAAQKfxUAAgsABgkLI6A6AAoCAAsABgkLI6A6AAoCAAAA.Miamore:BAAALgADCgEJAQABLgADCgkJCQASAAAAAA==.Milize:BAAALgAECgIJAgAAAA==.Milknkookies:BAAALgAECgIJAgAAAA==.Miney:BAAALgAECgEJAgAAAA==.Mirowen:BAAALgAECgYJBgABLgAECgUJBwASAAAAAA==.Misc:BAAALgAFFAEJAQAAAA==.Mistaeatit:BAABLgAECn8mAAIQAAgJQR9SKwAwAgAQAAgJQR9SKwAwAgAAAA==.Mitch:BAAALgAECgQJCAAAAA==.Miu:BAAALgAFFAMJAwAAAA==.',
Mk='Mkachen:BAAALgADCgUJBwAAAA==.',
Mo='Monkintrunk:BAAALgADCgIJAgABLgADCgkJEgASAAAAAA==.Moody:BAAALgAECgEJAQAAAA==.Moondotter:BAABLgAECn8XAAICAAYJghnoYQBlAQACAAYJghnoYQBlAQAAAA==.Moongoddess:BAAALgAECgIJAgABLgAECgYJFwACAIIZAA==.Moonslayer:BAABLgAECn8fAAMeAAkJCB+jBwC6AgAeAAkJCB+jBwC6AgAWAAEJiAFv6gAaAAAAAA==.Moovefool:BAABLgAECn8fAAMhAAgJIAhiVAAsAQAhAAgJIAhiVAAsAQAcAAYJNgpDTADUAAAAAA==.Mortimer:BAABLgAECn8qAAIQAAkJsRywIABjAgAQAAkJsRywIABjAgAAAA==.',
Mu='Mudgeon:BAAALgAECgYJEQAAAA==.Mulheron:BAAALgADCgMJBAAAAA==.Mulletmonk:BAAALgAECgQJCAAAAA==.',
['Mâ']='Mâshîrâ:BAABLgAECn8dAAMcAAgJHSKmCgDsAgAcAAgJHSKmCgDsAgAaAAMJwApDJACVAAABLgAFFAQJDAAKAEkZAA==.',
['Må']='Måshîrå:BAAALgAECgcJCQABLgAFFAQJDAAKAEkZAA==.',
Na='Nagarafan:BAABLgAECn8mAAIBAAgJzA37awCGAQABAAgJzA37awCGAQAAAA==.Nakor:BAABLgAECn8iAAIBAAgJGRByYgCdAQABAAgJGRByYgCdAQAAAA==.Natalie:BAAALgAECgQJCAAAAA==.Naughtybits:BAABLgAFFH8JAAIhAAUJhhjGEQCNAQAhAAUJhhjGEQCNAQAAAA==.',
Ne='Nefariat:BAAALgAECgMJBQAAAA==.Nefarious:BAAALgAECgEJAQABLgAECgMJBQASAAAAAA==.Nefeli:BAACLgAFFH8KAAMTAAQJfgFCGgC/AAATAAQJfgFCGgC/AAAUAAMJFwTiOQCnAAAuAAQKf0UAAxQACQl4HyQGAOMCABQACQl4HyQGAOMCABsACQlcGEQKADoCAAAA.Nelinne:BAABLgAECn8jAAMKAAgJeQFxPACuAAAKAAgJbQFxPACuAAAJAAMJDgFmygA7AAAAAA==.Nestia:BAAALgAECgYJDQAAAA==.Never:BAACLgAFFH8SAAICAAUJdyLrHQCHAQACAAUJdyLrHQCHAQAuAAQKfywAAwIACQmdJc0BALQDAAIACQmdJc0BALQDAAMABQnxIGoPANYBAAAA.',
Ni='Niccolò:BAAALgADCgEJAQAAAA==.Nidis:BAAALgADCgYJAQAAAA==.Nieve:BAAALgADCgEJAQAAAA==.Nightarrow:BAABLgAECn8rAAMJAAkJKRrFHwA/AgAJAAkJKRrFHwA/AgAoAAEJKwBVnAAKAAAAAA==.Nightbird:BAAALgAECgkJAgAAAA==.Nightshade:BAABLgAECn9HAAQJAAkJWx7eGABoAgAJAAkJWx7eGABoAgAKAAkJSxGOEAAQAgAoAAgJQwtPOACDAQAAAA==.Nil:BAAALgAECgcJDwAAAA==.Ninjamonkggz:BAABLgAECn8UAAIRAAcJRxNqKgCKAQARAAcJRxNqKgCKAQAAAA==.Nitron:BAAALgAFFAEJAQAAAA==.Nivyode:BAAALgAECgEJAQAAAA==.Nix:BAABLgAECn8mAAIBAAkJqRlpMQA1AgABAAkJqRlpMQA1AgAAAA==.',
No='Noanelororal:BAAALgAECgEJAQAAAA==.Nortney:BAABLgAECn8VAAIYAAgJ7hjfGgB1AgAYAAgJ7hjfGgB1AgAAAA==.Noskilzreq:BAAALgAECgYJDQAAAA==.Nostrum:BAAALgAECgYJCgAAAA==.Noughts:BAAALgADCgEJAQAAAA==.Novva:BAAALgAECgEJAQAAAA==.',
Nu='Nubootie:BAAALgAECgQJBAAAAA==.',
Ny='Nyckels:BAAALgADCgEJAQAAAA==.',
Oa='Oathbound:BAAALgADCgEJAQAAAA==.',
Ob='Oblaan:BAABLgAECn8uAAQCAAkJ+SC4CwDcAgACAAgJxiC4CwDcAgADAAUJSR2RFgCVAQAEAAIJMxyMJwBTAAAAAA==.',
Oc='Ocllo:BAABLgAECn8pAAIHAAkJJRi7CwDeAQAHAAkJJRi7CwDeAQAAAA==.Octopusy:BAAALgAECgUJCAAAAA==.',
Oj='Ojo:BAABLgAECn8hAAIZAAkJRw6RBwC3AQAZAAkJRw6RBwC3AQAAAA==.',
On='Onebuttonaug:BAAALgAECggJEwABLgAFFAgJHgAcACgWAA==.Oniana:BAABLgAECn8yAAIoAAgJvxg4CADXAQAoAAgJvxg4CADXAQAAAA==.',
Oo='Oozle:BAAALgADCgMJBQAAAA==.',
Op='Openwide:BAAALgADCgQJBwABLgAECgcJDQASAAAAAA==.Oprahwinfuri:BAAALgADCgYJBgAAAA==.',
Or='Orccrusher:BAAALgADCgQJBwAAAA==.Orndushin:BAAALgADCgIJAgAAAA==.',
Ot='Ot:BAAALgAECgUJBwAAAA==.',
Pa='Pagamas:BAACLgAFFH8OAAIBAAUJUR3HMwBcAQABAAUJUR3HMwBcAQAuAAQKfxsAAgEACAk/IiYwALICAAEACAk/IiYwALICAAAA.Painbringer:BAAALgAFFAMJAwAAAA==.Pajano:BAAALgADCgcJGQAAAA==.Palandari:BAAALgAECggJCgAAAA==.Palawin:BAAALgADCgkJCQAAAA==.Palonzo:BAAALgAECgQJBAAAAA==.Pandawan:BAAALgADCgkJDAAAAA==.Panter:BAABLgAECn8fAAMEAAgJch1TBAAlAgAEAAgJch1TBAAlAgACAAIJeBDQ3AB1AAAAAA==.Papaboomie:BAAALgAECgIJAgAAAA==.Pastimes:BAAALgAECgEJAQABLgAECgQJBgASAAAAAA==.',
Pe='Peachpear:BAAALgAECgcJEQAAAA==.Perditious:BAAALgAECgQJBAAAAA==.',
Ph='Pharaoh:BAABLgAECn88AAMjAAgJuRgDGADjAQAjAAgJuRgDGADjAQAfAAEJcwRwaAAlAAAAAA==.Pheneris:BAAALgADCgkJCQAAAA==.Phodoe:BAABLgAECn8pAAIWAAkJrwzSRABZAQAWAAkJrwzSRABZAQAAAA==.Phycara:BAAALgAECgYJCgAAAA==.Phyronix:BAAALgAECgQJBQAAAA==.',
Pi='Pickawp:BAAALgAECgQJBAAAAA==.Pikepole:BAAALgADCgkJCQAAAA==.Pishposh:BAAALgAECgIJAgAAAA==.',
Pl='Playne:BAABLgAECn8rAAIBAAkJihrUKABaAgABAAkJihrUKABaAgAAAA==.',
Pn='Pnzr:BAAALgAECgcJCgAAAA==.',
Po='Pokeureyeout:BAABLgAECn8fAAIJAAgJ6QqDVQB0AQAJAAgJ6QqDVQB0AQAAAA==.Poofarts:BAAALgAECgEJAQAAAA==.Poostorclose:BAAALgAECgQJCQAAAA==.Pootonium:BAAALgAECgYJCgAAAA==.Popaul:BAAALgADCgYJCwAAAA==.',
Pr='Prahn:BAABLgAECn8iAAIhAAkJuA1VPQCMAQAhAAkJuA1VPQCMAQAAAA==.Preaced:BAABLgAECn8hAAIfAAgJYQ4hKwCcAQAfAAgJYQ4hKwCcAQAAAA==.Prokix:BAABLgAECn8jAAIBAAgJZws4eQBpAQABAAgJZws4eQBpAQAAAA==.Propainiac:BAAALgAECgQJBAAAAA==.',
Pu='Pumpkinpuff:BAABLgAECn8iAAIiAAgJJiK6CQDKAgAiAAgJJiK6CQDKAgAAAA==.Purplppleatr:BAAALgADCgEJAQABLgAFFAQJBgAIAKQDAA==.',
['Pî']='Pîlot:BAABLgAECn8XAAIIAAcJXB2TQQDjAQAIAAcJXB2TQQDjAQAAAA==.',
Qu='Quiet:BAAALgAECgEJAQAAAA==.Quietkidz:BAAALgAECgEJAQAAAA==.Quiettreader:BAABLgAECn8kAAIBAAcJsxY0XwClAQABAAcJsxY0XwClAQAAAA==.Quokka:BAABLgAECn8pAAMWAAgJUyPbBwAgAwAWAAgJUyPbBwAgAwAeAAUJ5xdGNgBjAQAAAA==.',
Ra='Raambocatt:BAAALgAECgYJCwAAAA==.Raidboss:BAAALgAECggJDwAAAA==.Raklem:BAABLgAECn8kAAMJAAkJeA+kRQCkAQAJAAkJeA+kRQCkAQAoAAQJygNpbQCJAAAAAA==.Rampage:BAAALgADCgYJBgABLgAECgcJKAAMAMYXAA==.Ramssox:BAAALgAECgEJAQAAAA==.Ranni:BAAALgAFFAQJBAAAAA==.Raty:BAAALgAECgIJAgAAAA==.',
Re='Redeath:BAABLgAECn8bAAIOAAYJChCRJQD4AAAOAAYJChCRJQD4AAABLgAFFAQJBgAIAKQDAA==.Redirect:BAAALgAECgEJAQABLgAFFAQJBgAIAKQDAA==.Redonculous:BAABLgAECn8UAAIjAAgJ7BM4HQC0AQAjAAgJ7BM4HQC0AQAAAA==.Redpool:BAAALgAECgYJDAAAAA==.Reinault:BAACLgAFFH8VAAIRAAQJVQ/IEQANAQARAAQJVQ/IEQANAQAuAAQKfycAAxEACQmwHMoVADwCABEACQmwHMoVADwCACIABwnPCGI5AAMBAAAA.Reiramas:BAAALgAECgUJBQAAAA==.Relentful:BAAALgADCgIJAgAAAA==.Reliea:BAAALgAECgMJBAAAAA==.Renalla:BAAALgADCgYJBwAAAA==.Renix:BAAALgAECgMJAwAAAA==.Revansong:BAAALgAFFAIJAgABLgAFFAQJCAAPAK8fAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.',
Ro='Rob:BAAALgAECgUJBQAAAA==.Ronx:BAABLgAECn8mAAIBAAgJfBhoSQDjAQABAAgJfBhoSQDjAQAAAA==.Roodfrost:BAAALgADCgUJBwAAAA==.Roxxiloxxi:BAABLgAECn8yAAMCAAkJeAYhZABgAQACAAkJWwYhZABgAQADAAgJGgS0LgABAQAAAA==.Royal:BAABLgAECn8pAAIXAAgJDRVSFQBsAQAXAAgJDRVSFQBsAQABLgAFFAIJAgASAAAAAA==.',
Ru='Rudeboy:BAAALgAECgUJBgAAAA==.Ruination:BAAALgAECgEJBAAAAA==.Rukìa:BAAALgAECgEJAQABLgAFFAIJAwASAAAAAA==.',
Sa='Sabria:BAACLgAFFH8JAAIGAAQJJRSrGQAhAQAGAAQJJRSrGQAhAQAuAAQKf0IAAwYACQl9HasHAOwCAAYACQl9HasHAOwCAAgACAnND9lcAMwBAAAA.Sahee:BAAALgADCgMJAwAAAA==.Sahria:BAABLgAECn8XAAIhAAgJzAvpSwBLAQAhAAgJzAvpSwBLAQAAAA==.Samlosco:BAABLgAECn8sAAIbAAgJVxsPBAAgAgAbAAgJVxsPBAAgAgAAAA==.Saninth:BAAALgAECgEJAQAAAA==.Sanwicheater:BAAALgAFFAEJAQABLgAFFAUJDgABAFEdAA==.Satra:BAAALgADCggJDwAAAA==.Savus:BAAALgAECgYJEAAAAA==.',
Sc='Scalpelheals:BAACLgAFFH8iAAInAAkJqRSDAQAnAgAnAAkJqRSDAQAnAgAuAAQKfz8ABCcACQnDJb0AAKsDACcACQnDJb0AAKsDAB8ABwnvGvsbAP0BACMAAQkeCRliADQAAAAA.Sceledrus:BAAALgADCgcJDQAAAA==.Schizadin:BAAALgAECggJDwAAAA==.Schizology:BAAALgADCgkJDAAAAA==.',
Se='Sebekuul:BAAALgAECggJCgAAAQ==.Selbur:BAAALgADCgMJAwABLgAFFAcJFgARAN4dAA==.Selfie:BAAALgADCgEJAgAAAA==.Selys:BAAALgAECgcJBwABLgAECggJMAAYANgTAA==.Sence:BAAALgAECgEJAQAAAA==.Sendy:BAAALgAECgYJCAAAAA==.Sephurik:BAACLgAFFH8cAAIBAAgJPRW6AgBaAgABAAgJPRW6AgBaAgAuAAQKf0MAAgEACQnJI3YIAIMDAAEACQnJI3YIAIMDAAAA.Sepimoth:BAAALgADCgYJDAAAAA==.Septicaemia:BAAALgAECgMJAwAAAA==.Seriphan:BAAALgAECgEJAQAAAA==.Serovin:BAAALgADCgcJBwAAAA==.',
Sh='Shamaderp:BAAALgADCgYJBgAAAA==.Shanamana:BAAALgADCgIJAgAAAA==.Shaolin:BAAALgADCgUJBQABLgAFFAIJAwASAAAAAA==.Shawman:BAAALgADCgEJAQAAAA==.Sheepie:BAAALgADCgMJAwAAAA==.Shindorei:BAAALgAECgMJAwAAAA==.Shintai:BAAALgAECgUJDwAAAA==.Shnicklfritz:BAAALgADCgQJBQAAAA==.Showtek:BAABLgAECn8yAAMXAAkJVRyACAAsAgAXAAkJVRyACAAsAgAeAAgJMxVtHQCvAQAAAA==.Shyft:BAABLgAECn8dAAIPAAcJXBjnGgCXAQAPAAcJXBjnGgCXAQABLgAFFAIJAwASAAAAAA==.Shyfted:BAAALgADCgUJBQABLgAFFAIJAwASAAAAAA==.Shyfty:BAAALgAECgYJCQABLgAFFAIJAwASAAAAAA==.Shîn:BAABLgAECn8eAAQIAAcJzxstbwBwAQAIAAcJaxotbwBwAQAHAAMJGQ0hMgCFAAAGAAIJXAW2igBTAAAAAA==.',
Si='Sickology:BAAALgAECgQJBgAAAA==.Sikanda:BAACLgAFFH8LAAMFAAQJTRsIBgBMAQAFAAQJrBkIBgBMAQAQAAMJNBUXegDdAAAuAAQKfyYAAxAACAmCI98gAL4CABAACAmCI98gAL4CAAUABgkHIf4IALMBAAAA.Simplord:BAAALgAECgYJCQAAAA==.Sinara:BAAALgAECgUJCgAAAA==.Sintaxtwo:BAACLgAFFH8YAAMJAAYJsiOOFgBlAQAJAAUJlSOOFgBlAQAoAAUJZBzBEwADAQAuAAQKfyUAAygACQkUJTMIABwDACgACAnFIzMIABwDAAkABwksI4UdAEsCAAAA.Sion:BAABLgAECn8sAAIjAAkJUCFuBAD7AgAjAAkJUCFuBAD7AgAAAA==.Sithlordz:BAAALgAECgQJBgAAAA==.',
Sk='Sky:BAABLgAECn8dAAIBAAgJSiGJHwD2AgABAAgJSiGJHwD2AgAAAA==.Skyelf:BAABLgAECn8hAAIJAAgJOhCzLgD3AQAJAAgJOhCzLgD3AQAAAA==.Skyrizzy:BAAALgAECgEJAQAAAA==.',
Sl='Slickchic:BAAALgAECgUJBQAAAA==.Sluggerr:BAACLgAFFH8FAAIdAAMJdSAhEAADAQAdAAMJdSAhEAADAQAuAAQKfxQAAh0ACAlcILYIAJQCAB0ACAlcILYIAJQCAAAA.',
Sm='Smallpox:BAAALgAECgYJBwAAAA==.Smitemedaddy:BAAALgADCgYJBQAAAA==.Smoke:BAAALgAECgMJAwAAAA==.Smokedeuce:BAAALgAECgYJCQAAAA==.Smokyette:BAAALgAECgMJAwABLgAECgYJCQASAAAAAA==.',
So='Somira:BAAALgAECgUJCAAAAA==.Soraia:BAABLgAECn8fAAIBAAYJ5g2/pgAVAQABAAYJ5g2/pgAVAQAAAA==.',
Sp='Spanktotank:BAABLgAECn8bAAILAAYJaBF9ggDyAAALAAYJaBF9ggDyAAAAAA==.Spectrecles:BAAALgAECgYJCwABLgAECgcJDQASAAAAAA==.Spectrecless:BAAALgAECgcJDQAAAA==.Speez:BAABLgAECn8oAAMJAAkJwRKbLgD5AQAJAAkJwRKbLgD5AQAoAAEJuQGgmgAYAAAAAA==.Spookieturbo:BAAALgAFFAIJAgAAAA==.Spookyhunter:BAABLgAECn8YAAILAAgJoCTkCQDkAgALAAgJoCTkCQDkAgAAAA==.',
St='Stablehand:BAABLgAECn85AAIJAAkJOBpVJAAmAgAJAAkJOBpVJAAmAgAAAA==.Stephen:BAAALgADCgcJBwAAAA==.Steve:BAACLgAFFH8eAAMcAAgJKBZgAgDbAQAcAAgJKBZgAgDbAQAhAAIJUgEoVwBdAAAuAAQKfy0AAxwACQkOIrQCAIIDABwACQkOIrQCAIIDACEAAglyArukAEYAAAAA.Stonedfel:BAABLgAECn8dAAIkAAkJuA77IAC1AQAkAAkJuA77IAC1AQAAAA==.Stonkbonkk:BAABLgAECn8VAAIPAAYJkgbDMQDjAAAPAAYJkgbDMQDjAAAAAA==.Stylez:BAAALgAECgYJCwAAAA==.',
Su='Sucsuck:BAAALgAECgMJAwAAAA==.Sundora:BAACLgAFFH8GAAIIAAIJ6BJUZwCeAAAIAAIJ6BJUZwCeAAAuAAQKfxcAAggACAlDGD06APkBAAgACAlDGD06APkBAAAA.Sunhoof:BAABLgAECn8mAAMIAAkJoxSETgC9AQAIAAkJCxKETgC9AQAHAAYJGxcAFwBlAQAAAA==.Superuberbot:BAABLgAECn8iAAMjAAgJFxEfKwBSAQAjAAgJFxEfKwBSAQAfAAEJ7gGNawAfAAAAAA==.Superuberdot:BAABLgAECn8lAAQEAAcJtBc0EAArAQAEAAcJMxU0EAArAQACAAQJGRUFpQDfAAADAAUJDAYBJwBhAAAAAA==.Superuberhot:BAAALgAECgUJCAAAAA==.Superubernot:BAAALgAECgEJAwAAAA==.',
Sy='Sylvyr:BAAALgAECgQJCAAAAA==.Syntacks:BAABLgAECn8qAAIBAAgJ8BhlTQBOAgABAAgJ8BhlTQBOAgAAAA==.Syzara:BAAALgADCgYJCQAAAA==.',
['Sø']='Sørina:BAAALgAECgEJAQAAAA==.Sørrow:BAABLgAECn8fAAILAAgJtw4bYwA8AQALAAgJtw4bYwA8AQAAAA==.',
Ta='Tabi:BAABLgAECn8sAAIBAAkJXQYMcQB7AQABAAkJXQYMcQB7AQAAAA==.Tacts:BAAALgAFFAIJAgAAAA==.Taiyn:BAAALgAECgQJBAABLgAECggJFgAdALEYAA==.Takecare:BAAALgADCgIJAwAAAA==.Tankaa:BAAALgADCgYJBwAAAA==.',
Te='Terein:BAAALgADCgYJBwAAAA==.Test:BAAALgAECgcJDAAAAA==.',
Th='Thedawg:BAAALgADCgQJBAAAAA==.Thedayman:BAAALgAECgYJBgAAAA==.Theo:BAAALgAECgEJAQAAAA==.Therwinn:BAABLgAECn8hAAIJAAkJlyKAEAClAgAJAAkJlyKAEAClAgAAAA==.Thetaint:BAACLgAFFH8KAAIPAAQJwRloEQBRAQAPAAQJwRloEQBRAQAuAAQKfy8AAw8ACQkpIUgHAJMCAA8ACQkgIUgHAJMCABkABgmiG64KAGkBAAAA.Thoradin:BAAALgADCgEJAQAAAA==.Thraxion:BAAALgAECgYJDwAAAA==.Thread:BAAALgAECgQJBgAAAA==.Threestorms:BAAALgADCgQJBAAAAA==.Thunderkow:BAAALgADCgcJCAABLgAFFAUJFAACACYhAA==.Thunderous:BAAALgAECgQJCAAAAA==.',
Ti='Tinee:BAAALgADCgkJCQABLgAECggJGgABAHAaAA==.Tinyrunes:BAABLgAECn8UAAIQAAcJDBkQUwCnAQAQAAcJDBkQUwCnAQAAAA==.',
To='Tojiguro:BAAALgADCgYJBwAAAA==.Tommoorello:BAAALgADCgEJAQAAAA==.Torags:BAAALgADCgEJAgAAAA==.Torrask:BAAALgAECgIJAgAAAA==.Totemofpeace:BAAALgAECgkJEwABLgAECggJIQAfAGEOAA==.Towfu:BAABLgAECn8aAAIBAAgJcBq4PgAFAgABAAgJcBq4PgAFAgAAAA==.',
Tr='Traelayn:BAAALgAECgEJAQAAAA==.Trapgawd:BAAALgADCgEJAQAAAA==.Trentlock:BAACLgAFFH8VAAMCAAYJgRHbIAB8AQACAAYJgRHbIAB8AQAEAAIJiQgFHABFAAAuAAQKfzMABAQACAkdIh0LAHUBAAIABwkIHttWAIIBAAQABQkzIx0LAHUBAAMABQmyG7kOACcBAAAA.Tristae:BAAALgAECgcJDwAAAA==.Trollslingin:BAAALgADCgkJEAAAAA==.Truuk:BAAALgAECgYJCQAAAA==.',
Ts='Tsu:BAAALgAFFAEJAQAAAA==.',
Tu='Tunapie:BAAALgAECgEJAgAAAA==.',
Ty='Tyzula:BAAALgAECgcJCwAAAA==.',
['Tê']='Têstament:BAAALgAECgQJBAAAAA==.',
Ub='Ubasti:BAAALgAECgcJDgAAAA==.',
Un='Unstablesha:BAAALgAECgYJCwAAAA==.',
Ur='Urahara:BAAALgAECgQJBAAAAA==.',
Va='Valiriel:BAAALgADCgcJDQAAAA==.Variz:BAAALgAECgEJAgAAAA==.Varsalis:BAAALgADCgMJAwAAAA==.',
Ve='Velidra:BAAALgADCgYJCQAAAA==.Vellektra:BAAALgAECgEJAQAAAA==.Vernöm:BAAALgAECgQJBAAAAA==.Vethmoree:BAAALgAECgYJEQAAAA==.',
Vi='Via:BAAALgAECgYJAwAAAA==.Vil:BAACLgAFFH8eAAIjAAgJqhyiAABxAgAjAAgJqhyiAABxAgAuAAQKfykAAiMACQk7JtcCAHoDACMACQk7JtcCAHoDAAAA.Vilonus:BAABLgAECn8uAAICAAkJQQ/4QQC+AQACAAkJQQ/4QQC+AQAAAA==.Virvum:BAAALgAECgQJBAAAAA==.Vitiate:BAAALgAECgYJCQAAAA==.',
Vo='Voll:BAABLgAECn8aAAMnAAYJKhBvMQAnAQAnAAYJCBBvMQAnAQAfAAMJ+g4ETQB/AAAAAA==.',
['Và']='Vàáko:BAAALgAECgYJCAAAAA==.',
Wa='Warwix:BAAALgADCgMJAwAAAA==.Waxillium:BAAALgAECgcJCQAAAA==.',
We='Werebuddy:BAAALgADCgUJBQAAAA==.Weshyerga:BAABLgAFFH8HAAIXAAQJEyBVBAB6AQAXAAQJEyBVBAB6AQABLgAFFAUJEwAMAHImAA==.',
Wi='Wigly:BAABLgAECn8xAAInAAkJOBKPEgAjAgAnAAkJOBKPEgAjAgAAAA==.Willathewise:BAAALgAECgYJBgAAAA==.Wingsolid:BAAALgADCgYJCwABLgAECgcJDQASAAAAAA==.Withengar:BAABLgAECn8gAAILAAkJryB+CAD0AgALAAkJryB+CAD0AgAAAA==.',
Wr='Wrathrine:BAAALgAECgQJCQAAAA==.',
Wu='Wuoshi:BAACLgAFFH8LAAIiAAQJZAxBIQDqAAAiAAQJZAxBIQDqAAAuAAQKfxUAAyIACAkBE7cmAH0BACIACAkBE7cmAH0BABEAAQn8EIJ+ADQAAAAA.Wuuzzyy:BAAALgAECgcJDwAAAA==.',
Xa='Xaliko:BAABLgAECn8oAAMCAAkJ9iFGCQD0AgACAAkJ9iFGCQD0AgADAAYJUxZKEgC6AQAAAA==.Xanathos:BAAALgADCgUJBQAAAA==.Xanbaran:BAABLgAECn9LAAIfAAkJ3Ao/MgB3AQAfAAkJ3Ao/MgB3AQAAAA==.',
Xe='Xena:BAAALgAECgUJCAABLgAFFAIJAgASAAAAAA==.Xero:BAAALgAFFAIJAgAAAA==.',
Xo='Xorellion:BAABLgAECn8sAAIBAAkJrw0FVgC+AQABAAkJrw0FVgC+AQAAAA==.',
Xy='Xyrters:BAACLgAFFH8PAAITAAQJEREhFQAKAQATAAQJEREhFQAKAQAuAAQKfyAAAhMACAlPIWYEAA0DABMACAlPIWYEAA0DAAAA.',
Ya='Yamikaiba:BAAALgAECgEJAQAAAA==.',
Ye='Yeji:BAAALgADCgEJAQAAAA==.Yelhsa:BAAALgADCgYJCQAAAA==.',
Yi='Yiddiephokin:BAAALgADCgYJCAAAAA==.',
Yu='Yuki:BAAALgAECgUJBQAAAA==.Yukigodx:BAAALgADCggJEQAAAA==.Yukki:BAAALgAECggJCQAAAA==.',
Za='Zanus:BAAALgADCgEJAgAAAA==.Zapmommy:BAAALgADCgIJAgAAAA==.Zariel:BAAALgAECgQJCQAAAA==.Zartini:BAABLgAECn8TAAILAAkJdBc/VwBeAQALAAkJdBc/VwBeAQAAAA==.Zartööl:BAAALgAECgQJBAAAAA==.Zaylas:BAAALgADCgMJAwAAAA==.',
Ze='Zeeba:BAAALgADCgEJAQAAAA==.Zerildk:BAABLgAECn8fAAMQAAkJJRhZSgDAAQAQAAkJehZZSgDAAQAFAAIJzBZ1HwB8AAAAAA==.Zerphaine:BAABLgAECn8fAAIWAAkJthIKJwD1AQAWAAkJthIKJwD1AQAAAA==.Zevs:BAABLgAECn8VAAIHAAgJdwu+GQBEAQAHAAgJdwu+GQBEAQAAAA==.',
Zi='Zic:BAABLgAECn8XAAIQAAcJcAz9kwAZAQAQAAcJcAz9kwAZAQAAAA==.Zixxi:BAACLgAFFH8IAAIBAAMJRBNVYwDvAAABAAMJRBNVYwDvAAAuAAQKfzEAAgEACQk2HHMgAIICAAEACQk2HHMgAIICAAAA.',
Zu='Zulakar:BAABLgAECn8cAAIGAAYJlhlLNgCjAQAGAAYJlhlLNgCjAQAAAA==.Zurxes:BAABLgAECn8VAAITAAcJvBnpCgAJAgATAAcJvBnpCgAJAgAAAA==.',
Zy='Zynatra:BAAALgAECgQJBwAAAA==.',
['Âk']='Âkaeus:BAABLgAECn8kAAIcAAkJuhPtIACvAQAcAAkJuhPtIACvAQAAAA==.',
['Ça']='Çaz:BAAALgADCgcJBwAAAA==.',
['Ëv']='Ëvø:BAAALgAECgYJEAAAAA==.',
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
