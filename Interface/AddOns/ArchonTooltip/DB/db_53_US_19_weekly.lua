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

local lookup = {'DeathKnight-Frost','Paladin-Holy','Priest-Shadow','Priest-Holy','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Priest-Discipline','Warrior-Protection','Mage-Arcane','Warrior-Arms','Shaman-Elemental','DeathKnight-Blood','Rogue-Subtlety','Hunter-Survival','Shaman-Enhancement','Monk-Windwalker','Paladin-Retribution','Warlock-Demonology','Rogue-Outlaw','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Destruction','DeathKnight-Unholy','Warlock-Affliction','Druid-Guardian','Druid-Restoration','Rogue-Assassination','Mage-Frost','Evoker-Augmentation','Hunter-Marksmanship','Druid-Feral','Druid-Balance','Monk-Brewmaster','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Warrior-Fury',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abajaba:BAAANQAECgQICQAAAA==.Abractus:BAABNQAECn8bAAIBAAYK3hPCRACuAQABAAYK3hPCRACuAQAAAA==.',
Ad='Adaline:BAAANQADCgQIBAAAAA==.Aderrig:BAAANQADCgQIBAAAAA==.Adohlin:BAAANQABCgQIBQAAAA==.Adriana:BAABNQAECn8kAAICAAgK6R3LBACWAgACAAgK6R3LBACWAgAAAA==.Adrianix:BAAANQAECgcIEwAAAA==.Adru:BAABNQAECn8dAAMDAAcKwgZZOwBOAQADAAcKwgZZOwBOAQAEAAMK/gEk7QBdAAAAAA==.',
Ae='Aeglos:BAACNQAFFH8LAAIBAAMK1wqjBgDIAAABAAMK1wqjBgDIAAA1AAQKfyoAAgEACgr8HxgYAMoCAAEACgr8HxgYAMoCAAAA.Aehrick:BAAANQAECgQIBwAAAA==.Aentharion:BAAANQAECgUIEAAAAA==.',
Af='Afflixen:BAAANQAECgUICAABNQAECgYIEgAFAAAAAA==.',
Ai='Aileen:BAABNQAECn8dAAIGAAkKZApbjADxAQAGAAkKZApbjADxAQAAAA==.Aimshot:BAAANQAECgUIDAAAAA==.',
Al='Alakaz:BAAANQAECgEIAQAAAA==.Aldehyde:BAAANQADCgYIBwAAAA==.Alidoro:BAAANQADCgEIAQAAAA==.Alisaie:BAAANQAECgIIAgAAAA==.Alisonia:BAAANQADCgMIBQAAAA==.Alitikar:BAAANQADCgQIBAAAAA==.Alleximage:BAAANQAECgIIAQAAAA==.Alliancepaly:BAAANQADCgMIAwAAAA==.Alloy:BAAANQAECggICAAAAA==.Alorren:BAABNQAECn8eAAIHAAgKThYwbQDEAQAHAAgKThYwbQDEAQAAAA==.Aludor:BAAANQADCgEIAQAAAA==.',
Am='Ammo:BAAANQAECgEIAQABNQAECgoKKgAEAF4dAA==.Amo:BAAANQABCggIKQABNQAECgoKKgAEAF4dAA==.Amodegas:BAAANQAECgQIBAABNQAECgoKKgAEAF4dAA==.Amodillo:BAABNQAECn8qAAMEAAoKXh0oOQCEAgAEAAoKXh0oOQCEAgAIAAMKARNDFwC8AAAAAA==.Amoesh:BAAANQABCggIDwABNQAECgoKKgAEAF4dAA==.Amonra:BAAANQADCgYICQAAAA==.Amoose:BAAANQAECgIIAgABNQAECgoKKgAEAF4dAA==.Amynrar:BAAANQADCggIEAAAAA==.',
An='Andriia:BAAANQADCggIHwAAAA==.Anecia:BAAANQADCgcICgABNQAECgUIEQAFAAAAAA==.Angyaras:BAACNQAFFH8PAAIJAAcKwiSUAABCAgAJAAcKwiSUAABCAgA1AAQKfyEAAgkACgotJogBALYDAAkACgotJogBALYDAAAA.Animos:BAAANQADCgMIAwAAAA==.',
Ap='Apiix:BAABNQAECn8oAAIKAAoK3xbXRQAwAQAKAAoK3xbXRQAwAQAAAA==.',
Aq='Aquarat:BAAANQAECgEIAQAAAA==.',
Ar='Araaras:BAAANQAFFAEIAQAAAA==.Araiguma:BAAANQAECgcIDQABNQAFFAgILgAGAB4fAA==.Arcaisme:BAABNQAECn8XAAIKAAcKqgp4iwCvAAAKAAcKqgp4iwCvAAAAAA==.Arcticsnow:BAABNQAECn8WAAILAAYK+grF1QBEAQALAAYK+grF1QBEAQAAAA==.Ariealla:BAAANQADCgUIBQAAAA==.Ariskye:BAAANQADCggIBwAAAA==.Arkose:BAAANQAECgIIAwAAAA==.',
As='Aschen:BAAANQADCgIJAwAAAA==.Ashlyngrace:BAAANQAECgUIDwABNQAECgoKNQAHAL0gAA==.Ashlynne:BAABNQAECn81AAMHAAoKvSD7EwAsAwAHAAoKvSD7EwAsAwAMAAEKAADhRwEqAAAAAA==.Aspensong:BAAANQAECgUIEAAAAA==.Astracious:BAAANQAECgMIAwAAAA==.Astrayice:BAAANQADCgQIBQAAAA==.',
At='Atarkormu:BAAANQAECgQIDQABNQAECgkJJgANANIRAA==.Atax:BAABNQAECn8WAAIOAAcKLBkuFQAxAQAOAAcKLBkuFQAxAQAAAA==.Athená:BAAANQAECgQICgAAAA==.Atulkan:BAAANQAECgUIEgAAAA==.',
Au='Aurelitrasza:BAAANQAECgEIAgAAAA==.',
Av='Avalar:BAAANQADCgYIBgAAAA==.Avrice:BAAANQAECgUICAAAAA==.Avris:BAAANQAECgEIAQAAAA==.',
Ay='Ayayaras:BAAANQAFFAMIBAABNQAFFAcIDwAJAMIkAA==.Ayddayd:BAAANQADCgQICAAAAA==.Aylianya:BAAANQAECgUICQABNQAECgoKNQAHAL0gAA==.',
Az='Azimuth:BAAANQADCgYIBgAAAA==.',
Ba='Badshot:BAAANQADCgYIBgAAAA==.Bambu:BAAANQAECgEIAQABNQAECgUIEQAFAAAAAA==.Bamdruid:BAAANQADCggIEgABNQAECgUIEQAFAAAAAA==.Bamevoker:BAAANQAECgUIEQAAAA==.Bariggs:BAABNQAECn8hAAIPAAoKlCF2AgAVAwAPAAoKlCF2AgAVAwAAAA==.Barilia:BAAANQADCgQIBgAAAA==.',
Be='Beals:BAABNQAECn8VAAQMAAcK1xC+JQAlAQAMAAcK1xC+JQAlAQAHAAEK2hEcGwE2AAAQAAEKAAC8JAAAAAAAAA==.Beladra:BAAANQADCgQIBQAAAA==.Ben:BAABNQAECn8pAAIRAAoKjBmvAwD1AQARAAoKjBmvAwD1AQAAAA==.Beriadan:BAABNQAECn8qAAIMAAgKVyA5KgDXAgAMAAgKVyA5KgDXAgAAAA==.Bevee:BAABNQAECn8pAAMCAAkK5B8mEABLAwACAAkK5B8mEABLAwASAAEKAADXrgEwAAAAAA==.',
Bi='Bigwheels:BAAANQADCgYIBAAAAA==.Bisque:BAAANQADCgUIBQAAAA==.Bitemare:BAAANQADCgIIAgABNQAECgUICgAFAAAAAA==.Bixii:BAAANQADCgYIBgAAAA==.',
Bl='Bleddwen:BAAANQAECgYIFQAAAQ==.Blindseer:BAAANQABCgIIAgAAAA==.Bloodjustice:BAAANQAECgQIBAAAAA==.Blrsama:BAAANQAECgIIAwAAAA==.',
Bo='Bohrnir:BAAANQADCgUIBQAAAA==.Boozelee:BAAANQADCgMIAwAAAA==.Borealsnow:BAAANQADCgUIBwAAAA==.Bozo:BAAANQAECgcIDQAAAA==.Boüh:BAABNQAECn8aAAMIAAcKhxzIAQBjAQAIAAcKhxzIAQBjAQADAAIKPwv9ZwBhAAAAAA==.',
Br='Brutalix:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesonyou:BAABNQAECn8jAAMCAAgKow64KwAzAQACAAgKow64KwAzAQASAAcKDwUCDQEJAQAAAA==.Burnadine:BAABNQAECn8VAAITAAYKfAHyowBLAAATAAYKfAHyowBLAAAAAA==.Burnswhnpee:BAABNQAECn8dAAITAAgKcRNnewDyAQATAAgKcRNnewDyAQAAAA==.',
Ca='Caliie:BAAANQAECgQIDwAAAA==.Callektra:BAAANQADCggICwAAAA==.Callira:BAAANQADCgYIBgAAAA==.Calzypher:BAAANQADCgMIAwAAAA==.Cantata:BAAANQADCgcICAAAAA==.Captclamslam:BAAANQAECgIIAgAAAA==.Carhop:BAAANQADCgIIAgAAAA==.Carine:BAAANQADCgYIBgAAAA==.Caverick:BAAANQADCggICAAAAA==.Caw:BAAANQADCgMIAwABNQAECgIIAgAFAAAAAA==.Caydinse:BAAANQADCgQIBAAAAA==.Cayuga:BAAANQADCgUICAAAAA==.',
Ch='Charå:BAAANQADCgUIBQAAAA==.Chintakari:BAABNQAECn8bAAIGAAgKQwx5oADFAQAGAAgKQwx5oADFAQAAAA==.',
Cl='Clickër:BAAANQADCggIDAABNQAECgcIHgACACAiAA==.',
Co='Cocidiae:BAAANQADCggIGgAAAA==.Confusious:BAACNQAFFH8OAAIHAAUK7xR7BgBAAQAHAAUK7xR7BgBAAQA1AAQKfycAAgcACgqzHWIeAPICAAcACgqzHWIeAPICAAAA.Coppers:BAAANQADCggIBAAAAA==.Coree:BAABNQAECn8YAAIUAAUKOBAqEAAfAQAUAAUKOBAqEAAfAQAAAA==.Cornflower:BAAANQAECggIDwABNQAECgkJKAAGAP0QAA==.Corvaan:BAABNQAECn8XAAIVAAkK2w4NKwDpAQAVAAkK2w4NKwDpAQAAAA==.Corvhuunta:BAAANQAFFAIIAgAAAA==.',
Cr='Craft:BAAANQADCgMIAwAAAA==.Creg:BAAANQADCggIIgABNQAECgUIDAAFAAAAAA==.Crowbarr:BAAANQADCgYICwAAAA==.Cryostatic:BAAANQAECgQIBwABNQAECgYIDQAFAAAAAA==.',
Cu='Cultel:BAABNQAECn8pAAIWAAoKYBjmCABhAgAWAAoKYBjmCABhAgAAAA==.Cuulon:BAAANQADCgQIBgAAAA==.',
Cy='Cyendia:BAABNQAECn8hAAMMAAgKGgd+SQCyAAAMAAgKGgd+SQCyAAAHAAIK2AVafgBaAAAAAA==.Cynlea:BAAANQADCgYJCgAAAA==.',
Da='Daddyraz:BAAANQAECgUIDQAAAA==.Daemonquiver:BAAANQAECgUICQAAAA==.Dahtotems:BAABNQAECn8iAAIMAAoKpyT0BgCxAwAMAAoKpyT0BgCxAwAAAA==.Daphcelyn:BAAANQAECgQIBwAAAA==.Dariusz:BAABNQAECn8jAAIXAAgKyA5qEgBXAQAXAAgKyA5qEgBXAQAAAA==.Darkalen:BAABNQAECn8mAAINAAkK0hG3GQAfAQANAAkK0hG3GQAfAQAAAA==.Darkfogg:BAABNQAECn8XAAIMAAkKZiT0DACAAwAMAAkKZiT0DACAAwAAAA==.Darklodus:BAAANQADCgYICwAAAA==.Darkoros:BAAANQADCgYIBgABNQAECgkJJgANANIRAA==.Darksethia:BAAANQADCgQIBAAAAA==.Darksoul:BAAANQADCgQIBAAAAA==.Dathea:BAACNQAFFH8gAAIHAAcKIh1tBAA4AgAHAAcKIh1tBAA4AgA1AAQKfzsAAgcACgpNIFIPAEgDAAcACgpNIFIPAEgDAAAA.Daxetanlock:BAABNQAECn80AAMTAAoK5yFdIgD6AgATAAkKVSFdIgD6AgAYAAQKdxweLAAeAQAAAA==.Daxetans:BAAANQAECgIIAgABNQAECgoKNAATAOchAA==.',
De='Deathjingle:BAABNQAECn83AAMNAAoKDB5IDQB8AQAZAAoKfhzNMwBbAgANAAcK1B5IDQB8AQAAAA==.Deecayed:BAAANQAECgcIDAABNQAFFAIIBgAHAMsKAA==.Deecoy:BAAANQAECggIEAABNQAFFAIIBgAHAMsKAA==.Deemonic:BAAANQAECgYIEAABNQAFFAIIBgAHAMsKAA==.Deetermined:BAACNQAFFH8GAAIHAAIKywpzJAB7AAAHAAIKywpzJAB7AAA1AAQKfzcAAgcACgpaIJ8WABwDAAcACgpaIJ8WABwDAAAA.Deloisela:BAABNQAECn8pAAIKAAkKsQ31XwD9AAAKAAkKsQ31XwD9AAAAAA==.Denchy:BAABNQAECn8XAAILAAcKOwIHhwCQAAALAAcKOwIHhwCQAAAAAA==.Deylen:BAABNQAECn8kAAMCAAgKXwgGKwA2AQACAAgKXwgGKwA2AQASAAEKAAAwywEiAAAAAA==.Deyndine:BAABNQAECn8bAAMaAAYKphloDgBrAQAaAAQKZB5oDgBrAQATAAUKOQyy1wAaAQAAAA==.',
Di='Dizzyglaive:BAAANQADCgYIDQAAAA==.',
Dk='Dkllothe:BAAANQAECgIIBAAAAA==.',
Dl='Dlkffjj:BAAANQAECgEIAwAAAA==.',
Dm='Dmdk:BAABNQAFFH8HAAMBAAMKNSKEDQAFAQABAAMK6RqEDQAFAQAZAAIKIiHJFAC9AAAAAA==.Dmrwr:BAABNQAECn8bAAILAAgKuSSzHABEAwALAAgKuSSzHABEAwAAAA==.',
Do='Dodson:BAAANQADCgEIAQAAAA==.Dooid:BAAANQAECgEIAQAAAA==.Dorilax:BAAANQAECgIIBAABNQAECggIDwAFAAAAAA==.Dottarus:BAAANQADCgUIBQABNQAECgUICwAFAAAAAA==.',
Dr='Draegloth:BAAANQAECggIAgAAAA==.Draelick:BAAANQABCgIIAgAAAA==.Driadora:BAAANQAECgcIEgAAAA==.Droataxm:BAABNQAECn82AAIKAAoKACAzPQALAwAKAAoKACAzPQALAwAAAA==.Droataxpr:BAAANQAECgcICgABNQAECgoKNgAKAAAgAA==.Drogath:BAAANQADCgcIDQAAAA==.',
Du='Duarraag:BAAANQAECgEIAQAAAA==.',
['Dâ']='Dâvïd:BAABNQAECn83AAIbAAoK2BrWAQBlAgAbAAoK2BrWAQBlAgAAAA==.',
['Dä']='Däß:BAAANQADCgEJAQAAAA==.',
['Dë']='Dëërez:BAABNQAECn8jAAIcAAgK/BW4CQCcAQAcAAgK/BW4CQCcAQABNQAFFAIIBgAHAMsKAA==.',
Ei='Eililis:BAAANQADCgYIBwAAAA==.',
El='Elani:BAABNQAECn8aAAMCAAoKMRhuNwCGAgACAAoKMRhuNwCGAgASAAYK3w2x7gA/AQAAAA==.Elaynaa:BAABNQAECn8bAAIMAAYKXgwhPQDTAAAMAAYKXgwhPQDTAAAAAA==.Elidin:BAAANQADCgQIBAABNQABCggICgAFAAAAAA==.Elirwar:BAAANQADCgIIAgAAAA==.Elishaunt:BAAANQAECgUIDAABNQABCggICgAFAAAAAA==.Elleizah:BAAANQAECggICgABNQAECgoKMQAdAGMfAA==.Elleth:BAAANQAECgYICwAAAA==.Elliana:BAABNQAECn8WAAINAAcKsxjqSQDQAQANAAcKsxjqSQDQAQABNQAECgoKJQACANgeAA==.Elogio:BAAANQADCgYIEAAAAA==.Elvoidra:BAAANQAECgEIAQAAAA==.',
Em='Emanymton:BAAANQAECgMIBgAAAA==.Emiley:BAAANQAECgMIAwAAAA==.',
En='Endb:BAAANQAECggIAQAAAA==.',
Er='Erinn:BAAANQADCgYIBgAAAA==.Erisaria:BAAANQAECgEIAQAAAA==.Erixi:BAABNQAECn8bAAIQAAYKphVADwAMAQAQAAYKphVADwAMAQAAAA==.Eryn:BAAANQADCgEIAQAAAA==.',
Es='Esaria:BAAANQADCgEIAQAAAA==.',
Et='Etherns:BAAANQAECgEIAQAAAA==.',
Ev='Evissier:BAABNQAECn8rAAIaAAoKbCA7AQBVAwAaAAoKbCA7AQBVAwAAAA==.',
Ex='Excelimagust:BAAANQAECgUIDAAAAA==.',
Fa='Faelada:BAAANQADCggIEgAAAA==.Faid:BAAANQAECgYIEgAAAA==.Failor:BAAANQADCgYIBgAAAA==.Faize:BAAANQADCgEIAQAAAA==.Falcdhruid:BAAANQAECgIIAwAAAA==.Farundi:BAAANQAECgUICQAAAA==.',
Fe='Felana:BAAANQAECgUICAABNQAECggIIgAJAOEaAA==.Felbutton:BAAANQAECgYICgAAAA==.Felsen:BAAANQAECgUIDAABNQAECggIIgAJAOEaAA==.Felwit:BAABNQAECn8iAAIJAAgK4RoaDQBhAgAJAAgK4RoaDQBhAgAAAA==.Fennec:BAABNQAECn8fAAIdAAgKmhCTCQCGAQAdAAgKmhCTCQCGAQAAAA==.Feralie:BAAANQADCgYIBgAAAA==.Ferroz:BAAANQAECgQIEwABNQAECgkJJgANANIRAA==.Ferrozious:BAAANQAECgQICQABNQAECgkJJgANANIRAA==.',
Fl='Flamos:BAAANQAECgQIBAAAAA==.Flatline:BAAANQAECgYIDgAAAA==.Florabelle:BAABNQAECn8oAAIGAAkK/RBfQgAxAQAGAAkK/RBfQgAxAQAAAA==.Florid:BAAANQADCggIHAAAAA==.Florinaa:BAAANQADCgMIBAAAAA==.',
Fo='Foshomomo:BAAANQAECgUIEAAAAA==.Fozzle:BAABNQAECn8lAAIeAAgKqhSvCgAcAgAeAAgKqhSvCgAcAgAAAA==.',
Fr='Frenndi:BAAANQAECgIIAwAAAA==.',
Fu='Fuknazuga:BAAANQAECgQIBwAAAA==.Furroz:BAAANQAECgQICAABNQAECgkJJgANANIRAA==.',
Fy='Fynedge:BAABNQAECn8iAAISAAgKxQdn6ABLAQASAAgKxQdn6ABLAQAAAA==.Fynnyntyss:BAABNQAECn8kAAIfAAgK3g0UBAD8AAAfAAgK3g0UBAD8AAAAAA==.Fyrè:BAABNQAECn8vAAIGAAkKHh5/BgBhAgAGAAkKHh5/BgBhAgAAAA==.',
Ga='Garthe:BAAANQADCgEIAQAAAA==.',
Ge='Gelilla:BAAANQAECgMIAwAAAA==.Geoma:BAAANQAECgQIBAAAAA==.Gerlock:BAAANQAECgUIBQAAAA==.',
Gh='Ghastrider:BAAANQABCgEIAQAAAA==.Ghostlyt:BAAANQAECgEIAQAAAA==.',
Gi='Gigatin:BAABNQAECn8eAAINAAgKNx6XKQB2AgANAAgKNx6XKQB2AgAAAA==.Githnor:BAABNQAECn8vAAISAAkKKggYTgAoAQASAAkKKggYTgAoAQAAAA==.',
Go='Goldal:BAAANQAECgQICQAAAA==.Gorellan:BAAANQADCgYIGAAAAA==.',
Gr='Grimwharf:BAAANQAECgEIAQAAAA==.Grum:BAAANQADCgQIBgAAAA==.Grunaelyn:BAABNQAECn8XAAIMAAgKsRICdQDCAQAMAAgKsRICdQDCAQAAAA==.',
Gu='Guerrier:BAABNQAECn8jAAIgAAgKegp0EgDzAAAgAAgKegp0EgDzAAAAAA==.Guiong:BAAANQADCgYICgAAAA==.',
Gy='Gynx:BAAANQAECgEIAQAAAA==.',
['Gö']='Göttlich:BAAANQADCgUIBQABNQADCgUIBwAFAAAAAA==.',
Ha='Haidas:BAAANQAECgYIBgAAAA==.Hasuna:BAAANQADCgQIBAAAAA==.',
He='Healsoto:BAAANQADCgcIBwABNQAECgoKNAALAKUZAA==.Heikuro:BAABNQAECn8gAAMWAAgKJRkkBABdAQAWAAgKJRkkBABdAQAVAAMK5xdbWgCZAAAAAA==.Heybestie:BAAANQADCggICAAAAA==.',
Hi='Hillo:BAAANQAECgEIAQAAAA==.',
Ho='Holychonks:BAAANQADCgcIEAAAAA==.Hommy:BAAANQADCggIEgAAAA==.Honadain:BAAANQAECgQICQAAAA==.Honornight:BAAANQADCggJDgAAAA==.Hordestalker:BAAANQADCgUIBQAAAA==.Houtu:BAABNQAECn8qAAIHAAgKbBIEbgDBAQAHAAgKbBIEbgDBAQAAAA==.',
Hw='Hweilan:BAAANQADCgYIDAAAAA==.Hwil:BAAANQADCgYIBgAAAA==.',
Hy='Hydrokill:BAAANQADCggICAAAAA==.Hypnos:BAAANQAECgUIDAAAAA==.',
['Hö']='Hölyföx:BAAANQAECgEIAQAAAA==.',
Ia='Iamearl:BAABNQAECn8YAAIbAAcKoB7PBgCXAQAbAAcKoB7PBgCXAQAAAA==.',
In='Incidental:BAABNQAECn81AAIRAAoK4SFgCQA7AwARAAoK4SFgCQA7AwAAAA==.Inconell:BAAANQAECgQIDgAAAA==.Invega:BAAANQAECgIJAwAAAA==.',
Ir='Iric:BAAANQADCgQIBgAAAA==.Irino:BAAANQADCgUIBQAAAA==.',
Is='Isabelle:BAABNQAECn8aAAISAAcKmwszawDvAAASAAcKmwszawDvAAAAAA==.',
It='Itsredbush:BAAANQADCgQIBAAAAA==.',
Iz='Izaer:BAAANQAECgUIDgAAAA==.Iziel:BAAANQAECgcIEgAAAA==.Izumex:BAAANQAECgMIAwAAAA==.',
Ja='Jabzaklok:BAAANQAECgUIDQAAAA==.Jacky:BAAANQAFFAEIAQABNQAFFAUIDAADAMMYAA==.Jahirah:BAABNQAECn8eAAIKAAgKZRHa5QC+AQAKAAgKZRHa5QC+AQABNQAECgcIGwAZAJ8MAA==.Jahmunkey:BAAANQADCggIDAABNQAECgoKIAASAFMfAA==.Jaida:BAAANQAECgQIDAAAAA==.Jaleika:BAABNQAECn8mAAMKAAkKowkBMgBcAQAKAAkKowkBMgBcAQAeAAEKAAB+TQAsAAAAAA==.Jarius:BAAANQAECgQICAABNQAECgUICAAFAAAAAA==.Jayabalard:BAAANQAECgQIBAABNQAECgkJJgANANIRAA==.',
Je='Jean:BAABNQAECn87AAIGAAoKGiDtBQBuAgAGAAoKGiDtBQBuAgAAAA==.Jeez:BAABNQAECn8ZAAIhAAkK1BpHCgCXAgAhAAkK1BpHCgCXAgAAAA==.Jesmaríe:BAAANQAECgQICgAAAA==.',
Jo='Johadd:BAAANQADCgEIAQAAAA==.Jonnathen:BAAANQAECgUICAAAAA==.Jonyy:BAAANQADCgYIDgAAAA==.Jorianna:BAAANQAECgUIEgAAAA==.Joru:BAACNQAFFH8iAAIQAAgK+x4ZAADiAQAQAAgK+x4ZAADiAQA1AAQKfzMAAhAACgpFJjUCAIwDABAACgpFJjUCAIwDAAAA.',
Ju='Jurauth:BAAANQABCgQIBAAAAA==.Justyna:BAAANQAECgcIEAAAAA==.Juze:BAAANQAECgQICgABNQAECgcIBQAFAAAAAQ==.',
Ka='Kaai:BAABNQAECn8WAAIGAAcKrwtJtwCVAQAGAAcKrwtJtwCVAQAAAA==.Kabaul:BAABNQAECn82AAILAAoKXiQ9DwCDAwALAAoKXiQ9DwCDAwAAAA==.Kabir:BAABNQAECn8eAAIKAAcKiA6iRAAzAQAKAAcKiA6iRAAzAQAAAA==.Kadria:BAABNQAECn8bAAIiAAYKbxgGFgAtAQAiAAYKbxgGFgAtAQAAAA==.Kaideleigh:BAAANQABCgEIAQAAAA==.Kailanii:BAAANQAECgUIBQABNQAECgUICgAFAAAAAA==.Kaiyne:BAAANQAECgMIAwAAAA==.Kalagon:BAAANQADCgEIAQAAAA==.Kalaman:BAAANQADCgQICAAAAA==.Kalito:BAAANQADCgMIAwAAAA==.Kallivar:BAAANQAECgUIEgABNQAECgoKOwANABgjAA==.Kamb:BAAANQAECgUIEAAAAA==.Karalee:BAABNQAECn8VAAIGAAUKzwOqCAH1AAAGAAUKzwOqCAH1AAAAAA==.Katieey:BAACNQAFFH8cAAIHAAcK7iP7AQCbAgAHAAcK7iP7AQCbAgA1AAQKfyQAAgcACQrzJiIDALYDAAcACQrzJiIDALYDAAAA.Kaybee:BAAANQAECgUIDAAAAA==.Kayde:BAAANQADCgYIBgAAAA==.Kayil:BAABNQAECn8qAAIDAAoKUxPJHABeAgADAAoKUxPJHABeAgAAAA==.',
Ke='Kedalin:BAAANQAECgIIAwAAAA==.Kennyloggy:BAACNQAFFH8RAAIiAAcKtxd7BQBLAgAiAAcKtxd7BQBLAgA1AAQKfzwAAiIACgqTJNwCAF0CACIACgqTJNwCAF0CAAAA.Kevris:BAABNQAECn8VAAMTAAgKrglmrQB3AQATAAcK4gpmrQB3AQAaAAIKqgN3FAAuAAABNQAECgcIGwAZAJ8MAA==.Keydan:BAABNQAECn8WAAIbAAYK4hA4GwCyAAAbAAYK4hA4GwCyAAAAAA==.',
Kh='Khalunna:BAAANQADCgYIBgAAAA==.Khyn:BAAANQAECgQIBAABNQAECgUICgAFAAAAAA==.',
Ki='Kianni:BAAANQAECgIIAgAAAA==.Kirafrayen:BAAANQAECgEJAQABNQAECggIDQAFAAAAAA==.',
Kl='Klassy:BAABNQAECn8gAAIPAAoKjgyNBwD4AQAPAAoKjgyNBwD4AQAAAA==.',
Ko='Koppi:BAAANQAECgQICgAAAA==.Korru:BAAANQAECgQIBgAAAA==.Kotie:BAAANQAECgUIBQAAAA==.',
Kr='Kramz:BAAANQADCgcIDQAAAA==.Kreoss:BAAANQADCgQIBAABNQAECgoKLQAHACoQAA==.Kronar:BAABNQAECn81AAIGAAcK4gtuuQCRAQAGAAcK4gtuuQCRAQAAAA==.Krongar:BAAANQADCgQIBAAAAA==.Krumblo:BAEANQAECgUIDwABNQAECgcIHwAKAFEQAA==.Kryztof:BAAANQADCgYIBgAAAA==.',
Ku='Kuiraptor:BAAANQADCgcIDgAAAA==.Kumojo:BAAANQADCgEIAQAAAA==.Kunea:BAAANQADCgYIBgAAAA==.Kungfujace:BAAANQADCgYICwAAAA==.',
Ky='Kyrgune:BAAANQAECgQICAAAAA==.',
['Kà']='Kàhlan:BAAANQADCgYIBgAAAA==.',
La='Lahabreaa:BAAANQAECgIIAQAAAA==.Laoftey:BAABNQAECn8kAAIHAAoK1h/rDwBFAwAHAAoK1h/rDwBFAwAAAA==.Larquin:BAABNQAECn8bAAMZAAcKnwztbQBcAQAZAAcKnwztbQBcAQABAAUKdgZbeADDAAAAAA==.Lasmori:BAABNQAECn8cAAILAAgKUBfQGACjAQALAAgKUBfQGACjAQABNQAECgoKGgACADEYAA==.Laurenorder:BAAANQAECgUICgAAAA==.Laxxbroo:BAAANQAECgQICAAAAA==.',
Le='Leam:BAABNQAECn8XAAIbAAcKXQz1LAAxAQAbAAcKXQz1LAAxAQAAAA==.Leglock:BAABNQAECn8fAAMVAAcKWBJ9LQDWAQAVAAcKWBJ9LQDWAQAXAAIKjQPUiABVAAAAAA==.Leiff:BAAANQADCggIEgAAAA==.Leprhicon:BAAANQAECgMIBAAAAA==.Lesbihonest:BAAANQAECggIEAAAAA==.',
Li='Liendria:BAABNQAECn8eAAIGAAgKeRcmhQABAgAGAAgKeRcmhQABAgAAAA==.Lifegrind:BAAANQAECgcIBwAAAA==.Lifensoftpaw:BAACNQAFFH8YAAIRAAcK4BWjBAD2AQARAAcK4BWjBAD2AQA1AAQKfzcAAxEACgo6JG0AAD4DABEACgo6JG0AAD4DACMABQoYIOUSALYBAAAA.Lightemup:BAAANQAECgMIBQAAAA==.Lightkeeper:BAAANQABCgYIBAAAAA==.Likkash:BAAANQAECgQIBgABNQAECgkJJgANANIRAA==.Limildea:BAAANQADCgQIBgAAAA==.Linthabeela:BAAANQADCgEIAQAAAA==.Liquidchiken:BAAANQAECgQIBAAAAA==.Lishalthen:BAAANQADCggJFwAAAA==.Littletouch:BAAANQADCgIIAgAAAA==.Livicecia:BAABNQAECn8VAAIhAAkKYAgoGAB3AQAhAAkKYAgoGAB3AQAAAA==.',
Lu='Lucciana:BAAANQAECgUICQAAAA==.Lucielinna:BAAANQADCgUIBQABNQAECgQICgAFAAAAAA==.Luckiiem:BAABNQAECn8qAAIKAAoKnSH2LwAsAwAKAAoKnSH2LwAsAwAAAA==.Luisfriendsn:BAABNQAECn8eAAIKAAoKtA/vkABeAgAKAAoKtA/vkABeAgABNQAECgoKMAAKABsYAA==.Lumbo:BAEBNQAECn8fAAMKAAcKURCQ6AC5AQAKAAcKURCQ6AC5AQAeAAEK0gTZSQAxAAAAAA==.Lunare:BAAANQADCgUJBQAAAA==.Lunarkin:BAAANQAECgQIBgAAAA==.Luthane:BAABNQAECn8UAAISAAcKogoVDwEGAQASAAcKogoVDwEGAQAAAA==.',
Ly='Lykinea:BAAANQADCgYIBgAAAA==.Lyono:BAAANQAECgYIBgABNQAECgkJJgANANIRAA==.Lytebrite:BAABNQAECn8zAAICAAoKPhIyDwDhAQACAAoKPhIyDwDhAQAAAA==.',
['Lí']='Líu:BAAANQADCggICAAAAA==.',
['Lü']='Lümßo:BAEANQAECgcIEwABNQAECgcIHwAKAFEQAA==.',
Ma='Mainos:BAAANQADCgUIBwAAAA==.Maiyr:BAAANQAECgIIAgAAAA==.Makanai:BAAANQAECgYIEgAAAA==.Makenai:BAAANQADCggIBwABNQAECgYIEgAFAAAAAA==.Makishi:BAABNQAECn8eAAIWAAcK6R5pAgCrAQAWAAcK6R5pAgCrAQAAAA==.Malakenjin:BAAANQABCgUIBAAAAA==.Malferious:BAAANQADCgIIAgAAAA==.Malfura:BAABNQAECn8UAAIiAAYKMQqbYgBEAQAiAAYKMQqbYgBEAQAAAA==.Malário:BAAANQAECgcIDwAAAA==.Manamontana:BAAANQADCgYIEwABNQAECgUICgAFAAAAAA==.Mandragoria:BAAANQADCgQIBAABNQAECgYIGwAaAKYZAA==.Mattedfurry:BAAANQAECgIIAgAAAA==.Maube:BAAANQAECgEIAQABNQAFFAUIDwAkAMwNAA==.Mazzarzul:BAAANQAECgMIAQABNQAECgoKQgAPAKweAA==.',
Me='Meebles:BAABNQAECn8vAAIbAAkK1QuADgAgAQAbAAkK1QuADgAgAQAAAA==.Meiana:BAABNQAECn8fAAIlAAgKohaLEwAWAgAlAAgKohaLEwAWAgAAAA==.Melasmus:BAAANQADCgYIBgAAAA==.Mes:BAABNQAECn8XAAIXAAgKsB99HwCeAgAXAAgKsB99HwCeAgAAAA==.',
Mi='Micklaa:BAABNQAECn8bAAIKAAcKuAdiZwDuAAAKAAcKuAdiZwDuAAAAAA==.Midgeto:BAAANQADCgUIBQAAAA==.Miebi:BAAANQADCgYICwABNQAECgoKPQAjAIYfAA==.Milkbunny:BAAANQADCgUICQAAAA==.Mingtai:BAABNQAECn8bAAIKAAYKhwdMfADHAAAKAAYKhwdMfADHAAAAAA==.Misskaitlyn:BAAANQADCgcIBwAAAA==.Mixen:BAAANQAECgQIBAABNQAECgYIEgAFAAAAAA==.',
Mo='Moirrah:BAAANQADCgYIBgABNQAECgIIAQAFAAAAAA==.Moonriver:BAABNQAECn8jAAIHAAkKThrOCwAKAgAHAAkKThrOCwAKAgAAAA==.Moonsinde:BAAANQAECggICQAAAA==.Moonsindee:BAAANQAECggICAAAAA==.Moranta:BAABNQAECn8eAAMEAAcKoxZ/fACkAQAEAAcKoxZ/fACkAQADAAcKigUQSgDxAAAAAA==.Moressandra:BAAANQAECgUIAwAAAA==.Morfina:BAAANQAECgMIAgABNQAECgQIBgAFAAAAAA==.Morgaes:BAAANQAECgUIDgAAAA==.Mortannon:BAABNQAECn8dAAIGAAcKGhP8fAAUAgAGAAcKGhP8fAAUAgAAAA==.Morîarty:BAAANQADCgIIAgAAAA==.Mozzare:BAAANQADCggIDQABNQAECgkJLwAbANULAA==.',
Mu='Mushy:BAAANQADCgEIAQAAAA==.',
My='Mydruid:BAAANQAECggIEQABNQAECgoKMQAdAGMfAA==.Mysticarc:BAAANQADCgYIBgAAAA==.Mysticmurv:BAABNQAECn8nAAIKAAoK3QmuyAD0AQAKAAoK3QmuyAD0AQAAAA==.Mystieren:BAAANQAECgQICQABNQAFFAMIBQATAEUEAA==.Mywarlock:BAABNQAECn8xAAMdAAoKYx+vCQBBAwAdAAoK5h6vCQBBAwAOAAcKYBnQHgDaAQAAAA==.',
Na='Nakanatakeko:BAAANQADCgcIBgAAAA==.Nalgotica:BAAANQAFFAEIAQABNQAECgoKMAANAFYZAA==.Nalynahwe:BAAANQADCggJGwAAAA==.Narima:BAABNQAECn8UAAINAAYKPQsOeAAXAQANAAYKPQsOeAAXAQAAAA==.Nathronso:BAAANQADCgUIBQAAAA==.Nauticâ:BAAANQABCggIFAAAAA==.Navirose:BAAANQAECgUICQAAAA==.',
Ne='Necromos:BAAANQAECggICAAAAA==.Neltheron:BAAANQADCgMIAwAAAA==.',
Nh='Nhala:BAAANQADCgUICAABNQAECgUICwAFAAAAAA==.',
Ni='Niavarr:BAAANQAECgYIBwAAAA==.Nibblefluff:BAAANQADCgMIAwAAAA==.Nightestrike:BAAANQAECgQICgAAAA==.Ninali:BAABNQAECn8XAAIDAAcKKAgdOwBQAQADAAcKKAgdOwBQAQAAAA==.Nivek:BAAANQADCgUICQAAAA==.',
No='Noralai:BAAANQADCgUIBAAAAA==.Nore:BAAANQAECgUIDgAAAA==.',
Nt='Ntviss:BAAANQADCgYIBgAAAA==.',
Ny='Nyali:BAAANQAECgUIBQABNQAECgUICgAFAAAAAA==.',
['Nà']='Nàdya:BAABNQAECn86AAMHAAoK0BxTBACzAgAHAAoK0BxTBACzAgAMAAEKRg/xMQE3AAAAAA==.',
['Nî']='Nîghtshade:BAAANQADCgYIBwAAAA==.',
Ob='Obidin:BAAANQADCggICAABNQAECgYIFQAbAKwVAA==.Oblivions:BAABNQAECn8nAAILAAoKKR/+MQD4AgALAAoKKR/+MQD4AgAAAA==.',
Od='Odasa:BAABNQAECn8gAAIMAAYKihRMhQCXAQAMAAYKihRMhQCXAQAAAA==.',
Og='Ogion:BAAANQADCggICAAAAA==.',
Ol='Olahn:BAAANQAECgUICwAAAA==.',
On='Onekark:BAABNQAECn8YAAIHAAgKMRbqVAAUAgAHAAgKMRbqVAAUAgAAAA==.Onlysins:BAAANQADCggIGwAAAA==.',
Or='Orckus:BAAANQAECgUICgAAAA==.Oreosbunny:BAABNQAECn8oAAMSAAkK7xqJMwBmAQASAAkK7xqJMwBmAQAkAAMKhhEKIwCBAAAAAA==.Orìhimè:BAAANQABCgQIBAAAAA==.',
Pa='Padma:BAAANQADCgUIBAAAAA==.Pandaburn:BAABNQAECn8iAAIKAAgKYBk9DwDvAQAKAAgKYBk9DwDvAQAAAA==.Pandalock:BAAANQADCgYIBgAAAA==.Pandsome:BAAANQADCgYICwAAAA==.Paroxism:BAACNQAFFH8KAAIiAAUKBxdmDwB0AQAiAAUKBxdmDwB0AQA1AAQKfysAAiIACQoeJOARADgDACIACQoeJOARADgDAAAA.Parzival:BAAANQAECgQIBgABNQAECgYIEgAFAAAAAA==.Pawsome:BAAANQADCggIDgAAAA==.',
Pe='Peanût:BAABNQAECn8dAAMcAAoK7Rj9EgC2AgAcAAoK7Rj9EgC2AgAiAAIK8wcFnQBoAAAAAA==.Peautiful:BAAANQAECgUIBgAAAA==.',
Ph='Phaket:BAABNQAECn8kAAIGAAoKBhwQQwCiAgAGAAoKBhwQQwCiAgAAAA==.',
Pi='Picaduro:BAAANQADCgYICQAAAA==.Picture:BAAANQADCgcIEgABNQAFFAUIDgAHAO8UAA==.Pika:BAABNQAECn8mAAQhAAkKcBEiBgBUAQAhAAgK1hIiBgBUAQAcAAQK8QNFYACFAAAiAAUKSwmANgCBAAAAAA==.Pingvinas:BAAANQADCgQIBAAAAA==.Pippá:BAAANQAECgUICwAAAA==.',
Pl='Plorb:BAAANQAECgEIAQAAAA==.',
Po='Pockethealer:BAAANQAECgMIAwABNQAECgQIBgAFAAAAAA==.Polonius:BAAANQAECgYIEwAAAA==.Potato:BAAANQADCgIIAgAAAA==.',
Pr='Priss:BAAANQADCggIDQAAAA==.Probation:BAAANQADCgUICAAAAA==.',
Pu='Puchideperro:BAAANQAECgUICQAAAA==.Pujo:BAAANQADCgYIBgAAAA==.',
Pw='Pwil:BAAANQABCgMIAgABNQADCgYIBgAFAAAAAA==.',
Py='Pythe:BAABNQAECn8vAAISAAkKICERCABjAgASAAkKICERCABjAgAAAA==.',
Qa='Qap:BAAANQAECgIIAwAAAA==.',
Qi='Qingu:BAABNQAECn8kAAQfAAkKOA7VCQDeAQAfAAgKWA/VCQDeAQAlAAcKTAdmIgA3AQAmAAcKAwRjMgAFAQAAAA==.',
Qu='Qualnorr:BAAANQAECgUICwAAAA==.Quelastraaza:BAAANQADCgcICgAAAA==.Queldraayan:BAAANQAECgUIDQAAAA==.Quinnter:BAEANQAECgUICgAAAA==.Quixoker:BAEANQADCgQIBAABNQAECgUICgAFAAAAAA==.Quixxie:BAEANQAECgQIBAABNQAECgUICgAFAAAAAA==.',
Qw='Qwil:BAAANQABCgYICgABNQADCgYIBgAFAAAAAA==.',
Ra='Radagon:BAABNQAECn8jAAMCAAoKTg6/YwDtAQACAAoKTg6/YwDtAQASAAcKSROOzQCAAQABNQAFFAEIAQAFAAAAAA==.Radalas:BAABNQAECn8gAAIkAAcKIx+ZEwBqAgAkAAcKIx+ZEwBqAgAAAA==.Radreliris:BAAANQAECgQICQAAAA==.Raelithi:BAAANQABCgYIBAAAAA==.Rahdalas:BAAANQADCgIIAQABNQAECgcIIAAkACMfAA==.Rainfall:BAAANQADCgYIBgAAAA==.Rally:BAABNQAECn8XAAIGAAcKNAXJ0wBZAQAGAAcKNAXJ0wBZAQAAAA==.Ramcco:BAEBNQAECn8mAAIDAAgKOhyqHABfAgADAAgKOhyqHABfAgAAAA==.Ranelle:BAABNQAECn8vAAIEAAkKohiYEgDfAQAEAAkKohiYEgDfAQAAAA==.Rasmira:BAAANQAECgEIBAAAAA==.Ravenis:BAACNQAFFH8MAAIOAAUKmxNeBwCXAQAOAAUKmxNeBwCXAQA1AAQKfygAAg4ACQpmIhkEAFcDAA4ACQpmIhkEAFcDAAAA.',
Re='Reanette:BAAANQADCgQIBAABNQAECgoKMAANAFYZAA==.Rebekkah:BAAANQADCgQIBAAAAA==.Reedem:BAAANQAECgcIEAAAAA==.Regilock:BAACNQAFFH8cAAQTAAcKDyKUAQCUAgATAAcKDyKUAQCUAgAYAAIKqhJNDwCWAAAaAAEKAABwDgBIAAA1AAQKf5MABBMACgp5Jh8AABQEABMACgp5Jh8AABQEABgABAplJWsbAJIBABoAAgp7GpQZALsAAAAA.Reikí:BAAANQAECgQIBgABNQAECggIKgAMAFcgAA==.Relarria:BAAANQAECgIIAQAAAA==.Renbe:BAAANQADCgEIAQAAAA==.Revgard:BAAANQAECgUIDwAAAA==.',
Rh='Rhaenyrra:BAABNQAECn8YAAIeAAgK2QVjGAA2AQAeAAgK2QVjGAA2AQAAAA==.Rhaily:BAAANQADCgIIAgAAAA==.Rhallin:BAAANQAECgUICgAAAA==.Rhasalgul:BAAANQAECgQIBAAAAA==.',
Ro='Ronso:BAAANQADCgQJBAAAAA==.Rosiel:BAAANQABCgQIBAAAAA==.Rowain:BAABNQAECn8nAAMhAAkK9BFdIAAUAQAhAAYKCwldIAAUAQAcAAkKHQOLRgD9AAAAAA==.Rozemary:BAAANQADCggICAAAAA==.Rozilan:BAAANQADCggIBwAAAA==.',
Ry='Rylacus:BAABNQAECn8aAAIOAAYKiAhmIgDcAAAOAAYKiAhmIgDcAAAAAA==.Rylii:BAAANQAECgUIDgAAAA==.',
Sa='Saanda:BAAANQADCggIEAAAAA==.Safael:BAAANQADCggIDwAAAA==.Salandre:BAAANQAECgQICAAAAA==.Sarlef:BAABNQAECn8hAAIJAAgKkQdPEQCvAAAJAAgKkQdPEQCvAAAAAA==.',
Sc='Scarm:BAACNQAFFH8FAAITAAMKyQhrFABvAAATAAMKyQhrFABvAAA1AAQKfywAAhMACgo0HSkTAEEDABMACgo0HSkTAEEDAAAA.Scathed:BAAANQAECggIDAAAAA==.Scorpix:BAAANQAECgIIAgAAAA==.',
Se='Seaflower:BAAANQAECgIIAQAAAA==.Seig:BAAANQADCgQIBAAAAA==.Sellidra:BAABNQAECn8hAAIGAAcKDQlfsACjAQAGAAcKDQlfsACjAQAAAA==.Serenitara:BAAANQADCggIEwAAAA==.Serharimia:BAAANQADCgQIBAAAAA==.Serifanlord:BAAANQAECgQIBgAAAA==.Seyana:BAAANQAECgUIDgAAAA==.',
Sh='Shaaddow:BAAANQAECgQIDQAAAA==.Shadeau:BAAANQADCgMIAwAAAA==.Shaffer:BAAANQAECgYIDAAAAA==.Shamanlady:BAAANQAECgQIBAAAAA==.Shamwhoa:BAAANQABCgQIBwAAAA==.Shellshocker:BAABNQAECn8eAAIMAAoKJyW3BgCzAwAMAAoKJyW3BgCzAwAAAA==.Sheng:BAAANQADCgUJBQAAAA==.Shermantånk:BAAANQADCgYICAAAAA==.Shey:BAAANQADCggIDAAAAA==.Sheydon:BAAANQADCggICgAAAA==.Shikigamï:BAAANQAECgEJAQABNQAECgoKJgADAKMjAA==.Shikï:BAABNQAECn8mAAMDAAoKoyPgCQBCAwADAAoKoyPgCQBCAwAEAAQKxBtXkABlAQAAAA==.Shivermoón:BAABNQAECn8nAAIcAAkKog0aMwCCAQAcAAkKog0aMwCCAQAAAA==.',
Si='Siegbane:BAAANQAECgMIAwAAAA==.Sigesar:BAAANQADCggIIwAAAA==.Sigrún:BAABNQAECn8XAAINAAcKDAcEdgAfAQANAAcKDAcEdgAfAQAAAA==.Simpforsouls:BAAANQADCgMIAwAAAA==.Sinsimella:BAAANQAECgEIAQAAAA==.',
Sk='Skoall:BAAANQAECgQIBAABNQAECgoKKgAEAF4dAA==.Skullash:BAAANQADCgcIBwAAAA==.Skywatcher:BAABNQAECn8eAAIGAAcKNwX6XwDrAAAGAAcKNwX6XwDrAAAAAA==.',
Sl='Slaughtering:BAAANQAECgIIAgAAAA==.',
Sm='Smitemare:BAAANQAECgQIBQABNQAECgUICgAFAAAAAA==.',
Sn='Sneakmode:BAAANQAECgIIAgAAAA==.Sneakyz:BAAANQAECgUICQAAAA==.Snicky:BAAANQAECgEJAQAAAA==.',
So='Sohka:BAAANQADCgEIAQAAAA==.Solare:BAAANQAECggIBgAAAA==.Sonwarr:BAABNQAECn8jAAIEAAoKlxcoNACXAgAEAAoKlxcoNACXAgAAAA==.',
Sp='Spinsocket:BAAANQADCgIIAgAAAA==.Spliphtoker:BAAANQAECgEIAQAAAA==.',
St='Stabsolutely:BAAANQADCgUJBQABNQAECgUICgAFAAAAAA==.Steelpen:BAAANQAECgQIBgAAAA==.Stenston:BAABNQAECn8ZAAMnAAcKPgxMCAAKAQAnAAcKPgxMCAAKAQAJAAEKAABVKgAAAAAAAA==.Sterede:BAAANQAECgIIAwAAAA==.Stitchwhich:BAAANQAECgYICQABNQAECgcIBwAFAAAAAA==.Stonehenge:BAABNQAECn8hAAISAAcKswtqyQCJAQASAAcKswtqyQCJAQAAAA==.Stormb:BAAANQAECggIBwAAAA==.Stormwolves:BAAANQAECgQIBAAAAA==.',
Su='Summers:BAABNQAECn8VAAMkAAoKahMeLAB8AQAkAAgKfg4eLAB8AQACAAQKegvs8QCcAAAAAA==.Surfclub:BAAANQAECgYIBAAAAA==.',
Sy='Sylphr:BAAANQAECgEIAQABNQAECgoKMAANAFYZAA==.Sylphrená:BAAANQAECgEIAQABNQAECggIKgAMAFcgAA==.Sylphwild:BAABNQAECn8gAAMbAAoKJhNMCAB4AQAbAAoKJhNMCAB4AQAiAAMKxAp3kwCKAAABNQAECgoKMAANAFYZAA==.Sylvara:BAAANQAECgQICgAAAA==.Synkinz:BAABNQAECn8eAAIMAAcKoxawHwA8AQAMAAcKoxawHwA8AQAAAA==.Syntec:BAAANQABCgMIAgAAAA==.Syreite:BAABNQAECn8aAAIbAAcKKxbNGADmAQAbAAcKKxbNGADmAQAAAA==.',
Ta='Tacori:BAAANQAECgUIBgABNQAECgUICQAFAAAAAA==.Taessa:BAAANQAECgQIBgAAAA==.Tainipuni:BAAANQADCgYIBgAAAA==.Tallic:BAABNQAECn8pAAIkAAoKehnnEQCCAgAkAAoKehnnEQCCAgAAAA==.Talynayl:BAAANQADCgUIBwAAAA==.Tamarah:BAAANQAECgIIAQAAAA==.Tandemonium:BAAANQAECgcIDgABNQAFFAIICQAXAH8eAA==.Taniz:BAABNQAECn8sAAMGAAoKxhheOgC7AgAGAAkKchteOgC7AgAgAAgKPhLKDQAdAQAAAA==.Tarsi:BAABNQAECn8VAAMXAAYKJgctXAASAQAXAAYKwgYtXAASAQAVAAYKIwMSTgDrAAAAAA==.Taseg:BAAANQABCggICgAAAA==.',
Td='Td:BAABNQAFFH8iAAIMAAoKZiE5AAB7AgAMAAoKZiE5AAB7AgAAAA==.',
Te='Tearinurside:BAABNQAECn8XAAISAAcKxhrwkAADAgASAAcKxhrwkAADAgAAAA==.Telidrel:BAAANQADCgIIAwAAAA==.',
Tg='Tgi:BAAANQAECgQICAAAAA==.',
Th='Thaddeaus:BAABNQAECn81AAIJAAoK3R3QAACuAgAJAAoK3R3QAACuAgAAAA==.Thaddeus:BAAANQAECgUIEAAAAA==.Thealin:BAAANQAECgQIBQAAAA==.Thebeefyone:BAABNQAECn8WAAIKAAUK5Av2QAEhAQAKAAUK5Av2QAEhAQAAAA==.Thecanadian:BAAANQADCgQIBAAAAA==.Thegreatmel:BAAANQADCgIIAgAAAA==.Therizin:BAAANQAECgUICwAAAA==.Thesummoner:BAAANQAECgEIAQAAAA==.Thornel:BAAANQADCgEIAQAAAA==.Thorrek:BAAANQAECggIEQAAAA==.Thrallete:BAAANQADCgUIBQAAAA==.Thugnificent:BAAANQABCggIFAAAAA==.Thumpette:BAAANQAECgQIDgAAAA==.',
Ti='Tierant:BAAANQAECgMIAwAAAA==.Tinaris:BAAANQADCgUICQABNQAECggIHgANADceAA==.Tizaria:BAAANQAECgYIEgAAAA==.',
Tm='Tmai:BAAANQAECgYICwAAAA==.',
To='Tominaetor:BAAANQAECgQIBAAAAA==.Tookans:BAAANQABCgUIBQAAAA==.Tosoto:BAABNQAECn80AAMLAAoKpRnVCgARAgALAAoKQBTVCgARAgAJAAcK1xxIEgABAgAAAA==.Toxica:BAAANQADCgMIAwAAAA==.',
Tr='Travcula:BAABNQAECn8iAAIZAAoKQRWzFQAzAQAZAAoKQRWzFQAzAQAAAA==.Treefiddy:BAAANQADCgEIAgAAAA==.Trumpd:BAAANQADCgUIBQABNQAECgQIBgAFAAAAAA==.',
Ts='Tso:BAAANQADCgEIAQAAAA==.',
Tt='Ttriton:BAAANQADCgEIAQAAAA==.',
Tu='Tuuwa:BAAANQADCgMIAwAAAA==.',
Ty='Tyernan:BAABNQAECn8iAAISAAkK7wUK5wBNAQASAAkK7wUK5wBNAQAAAA==.Tyrioz:BAABNQAECn8eAAMCAAgKIRurSABEAgACAAgKIRurSABEAgASAAIKZQipagF1AAAAAA==.',
Tz='Tzavcat:BAABNQAECn8gAAIcAAgKTQaZGAD+AAAcAAgKTQaZGAD+AAAAAA==.',
Uh='Uhtred:BAAANQAECggIAgAAAA==.',
Un='Unknownmage:BAAANQABCgIIAgAAAA==.',
Ur='Urbi:BAABNQAECn8VAAILAAYKyg/qzwBTAQALAAYKyg/qzwBTAQAAAA==.',
Uv='Uvsol:BAAANQAECgYICQAAAA==.',
Va='Vadailla:BAAANQAECgUIEQAAAA==.Vahrik:BAAANQADCgMIAwAAAA==.Valeirra:BAAANQADCgMIBQAAAA==.Valius:BAABNQAECn8kAAIlAAgK9x9OAQARAgAlAAgK9x9OAQARAgAAAA==.Valkyrae:BAAANQADCgQIBAAAAA==.Valornor:BAAANQAECgIIAgAAAA==.Vandill:BAABNQAECn8pAAIKAAgKIhZOsgAeAgAKAAgKIhZOsgAeAgAAAA==.Vaxis:BAAANQADCgcIEwAAAA==.',
Ve='Veasnacool:BAABNQAECn8vAAIGAAkKrhWTFgDCAQAGAAkKrhWTFgDCAQAAAA==.Vestrit:BAAANQADCgIIAgABNQAECggIKgAMAFcgAA==.',
Vi='Visren:BAAANQADCgIIAgAAAA==.',
Vo='Vongoethe:BAAANQABCgIIAgAAAA==.Vontote:BAABNQAECn8kAAINAAgKFBsDCQCpAQANAAgKFBsDCQCpAQAAAA==.Vorix:BAAANQAECgIIAgAAAA==.',
Vy='Vyluna:BAAANQAECgQIBAAAAA==.',
['Ví']='Víc:BAABNQAECn8eAAICAAcKICL0BACOAgACAAcKICL0BACOAgAAAA==.',
Wa='Wandorf:BAEANQAECgUIEAAAAA==.Warwolfe:BAABNQAECn8mAAMTAAoKoQjknQCcAQATAAoKKwjknQCcAQAaAAIKHAr8HwB2AAAAAA==.Wayler:BAAANQADCggICAAAAA==.',
Wh='Whitewâlker:BAAANQABCgUIBQAAAA==.Whumpus:BAAANQADCgIIAgAAAA==.Whyn:BAAANQAECgUICQAAAA==.',
Wi='Willei:BAAANQADCgUICwAAAA==.Wixen:BAAANQAECgYICgABNQAECgYIEgAFAAAAAA==.',
Wo='Wolferunner:BAAANQAECgUIDQAAAA==.Wondermang:BAAANQAECgMICwAAAA==.Woofhoof:BAAANQADCgQIBAAAAA==.Worgenwebb:BAAANQAECgYIEgABNQAECgkJIgALAOofAA==.',
Xa='Xaiden:BAAANQADCgcJBwAAAA==.Xaldora:BAAANQADCgEIAQAAAA==.Xali:BAAANQAECgQIBQAAAA==.Xandrake:BAAANQAECgcIBwAAAA==.Xanthrens:BAAANQADCgQIBgAAAA==.',
Xd='Xdxvuu:BAAANQAECgYIDAAAAA==.',
Xe='Xerimok:BAAANQAECgUIEAAAAA==.',
Xi='Xinya:BAABNQAECn8aAAIZAAYKrg0TIADsAAAZAAYKrg0TIADsAAAAAA==.',
Xl='Xladykahlron:BAAANQADCgYIBgAAAA==.',
Xs='Xsavior:BAAANQAECggICwAAAA==.Xshando:BAAANQAECgMIBwAAAA==.Xsmkmonk:BAAANQAECgEIAQAAAA==.',
Xz='Xzephyr:BAABNQAECn8qAAIiAAkKcB62BAAIAgAiAAkKcB62BAAIAgAAAA==.',
Ya='Yamato:BAABNQAECn8XAAIJAAkKyg4oBgBcAQAJAAkKyg4oBgBcAQAAAA==.',
Ye='Yesmín:BAABNQAECn8lAAIEAAoKuBbvCgA1AgAEAAoKuBbvCgA1AgAAAA==.',
Yi='Yil:BAABNQAECn8oAAIEAAkKVhgoEgDkAQAEAAkKVhgoEgDkAQAAAA==.',
Yo='Youwas:BAAANQAECgUICgAAAA==.',
Ys='Yshtola:BAAANQADCgYICwAAAA==.',
Yu='Yukmouf:BAABNQAECn8gAAISAAoKUx9nHgCpAQASAAoKUx9nHgCpAQAAAA==.Yukshadow:BAAANQAECgQIBgAAAA==.Yuriika:BAAANQADCgYIBwAAAA==.Yuukmouf:BAAANQAECgYIDAABNQAECgoKIAASAFMfAA==.',
Za='Zabrak:BAAANQADCgMIAgAAAA==.Zakaris:BAABNQAECn8gAAIBAAcKBg4dMQDXAAABAAcKBg4dMQDXAAAAAA==.Zaladin:BAAANQADCgUIBQAAAA==.Zarrove:BAABNQAECn8oAAIRAAoK1BqREQDTAgARAAoK1BqREQDTAgAAAA==.Zawl:BAAANQAECgMIBQAAAA==.',
Ze='Zea:BAAANQADCgMIAwAAAA==.Zedael:BAAANQAECgcIDQAAAA==.Zellgadis:BAAANQADCgMIAgAAAA==.Zeltri:BAABNQAECn81AAIDAAgKtQh6NgBwAQADAAgKtQh6NgBwAQAAAA==.Zerg:BAABNQAECn8eAAITAAcKChIYRwD9AAATAAcKChIYRwD9AAAAAA==.Zerref:BAAANQAECgMIAwABNQAECggIIQAJAJEHAA==.',
Zh='Zhatva:BAACNQAFFH8KAAIGAAUKnhX6EABOAQAGAAUKnhX6EABOAQA1AAQKfzQAAwYACgqwIIIfABkDAAYACgqwIIIfABkDACAAAwosErdcALIAAAAA.Zhöe:BAAANQAECgYICgAAAA==.',
Zi='Zimzhealz:BAAANQADCgcIDQAAAA==.Zimzorzz:BAAANQADCgUIBwABNQADCgcIDQAFAAAAAA==.',
Zo='Zoelera:BAAANQAECgQIBgAAAA==.Zoldor:BAABNQAECn8fAAMTAAcKWBE1MQA1AQATAAcKWBE1MQA1AQAYAAEK8wgAfAAxAAAAAA==.Zoleia:BAAANQADCgMIAwAAAA==.Zorellion:BAABNQAECn8eAAITAAcKDwW9xQA/AQATAAcKDwW9xQA/AQAAAA==.',
Zu='Zuay:BAAANQADCgIIAgABNQAECggIFgAdAMUXAA==.Zulianguy:BAACNQAFFH8GAAISAAIKpw9gJgCKAAASAAIKpw9gJgCKAAA1AAQKfygAAyQACgqbIbEWAEcCACQABgq3IrEWAEcCABIABQpXIYNYABMBAAAA.',
Zy='Zycorr:BAAANQAECgIIBAAAAA==.Zytrex:BAAANQAECgUICAAAAA==.',
['Zá']='Zátsu:BAAANQABCgEIAQAAAA==.',
['Äm']='Ämaterasu:BAAANQAECgUIBgABNQAECgoKJgADAKMjAA==.',
['Ñÿ']='Ñÿx:BAABNQAECn8ZAAIaAAgKAwMEFAALAQAaAAgKAwMEFAALAQAAAA==.',
['ßl']='ßluerain:BAAANQABCgQIBQAAAA==.',
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
